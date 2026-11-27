//! GLM ABSORB: weighted within-stratum projection, not dummy-column expansion.
//! S154 physical pp.4065,4106,4124–4125. Multiple keys are successively nested.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const io = @import("../io.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");
const reg = @import("reg_fit.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const nan = std.math.nan(f64);
pub const Absorbed = struct { name: []const u8, test_value: math.EffectTest };
pub const Result = struct {
    /// Conditional fit: no intercept, and effective residual-space N=N-rank(A).
    /// Its coefficient covariance uses the full model's residual degrees of freedom.
    conditional: ?math.Result,
    absorbed: []Absorbed,
    zero_effects: []math.EffectTest,
    within_x: []const f64,
    within_y: []const f64,
    weights: []const f64,
    absorbed_rank: usize,
    rank: usize,
    n_used: usize,
    df_error: usize,
    sse: f64,
    sst: f64,
    sst_uncorrected: f64,
    y_mean: f64,
    mse: f64,
    model: reg.ModelStats,
    pub fn deinit(self: *Result, a: A) void {
        if (self.conditional) |*conditional_fit| conditional_fit.deinit(a);
        a.free(self.absorbed);
        a.free(self.zero_effects);
    }
};
const Sum = struct {
    value: f64 = 0,
    correction: f64 = 0,
    fn add(self: *Sum, x: f64) void {
        const next = self.value + x;
        self.correction += if (@abs(self.value) >= @abs(x)) (self.value - next) + x else (x - next) + self.value;
        self.value = next;
    }
    fn total(self: Sum) f64 {
        return self.value + self.correction;
    }
};
fn equal(left: []const @import("../value.zig").Value, right: []const @import("../value.zig").Value, keys: []const usize) bool {
    for (keys) |ci| if (proc.cmpValue(left[ci], right[ci]) != .eq) return false;
    return true;
}
pub fn validate(cx: proc.ProcCtx, spec: parse.Spec, group: selection.View) diag.Error!void {
    const desc = try cx.arena.alloc(bool, spec.absorb.len);
    @memset(desc, false);
    for (spec.absorb) |ci| if (spec.input.ds.columns.items[ci].format != null) return proc.failGap(cx.diags, 0, "PROC GLM: formatted ABSORB keys are not implemented", .{});
    for (group.observations, 0..) |row, i| if (i > 0) {
        if (proc.byOrderViolation(row.cells, group.observations[i - 1].cells, spec.absorb, desc, spec.input.ds.sortseq_linguistic orelse io.global_sortseq_linguistic) != null)
            return cx.diags.fail(error.ParseError, 0, "PROC GLM: data are not sorted by the ABSORB variables at observation {d}", .{row.source_number});
    };
}
fn weightedMean(values: []const f64, weights: []const f64) diag.Error!f64 {
    var sw: Sum = .{};
    var delta: Sum = .{};
    const anchor = values[0];
    for (values, weights) |value, w| {
        sw.add(w);
        delta.add(w * (value - anchor));
    }
    const mean = anchor + delta.total() / sw.total();
    if (!std.math.isFinite(mean) or !std.math.isFinite(sw.total()) or !(sw.total() > 0)) return error.ExecError;
    return mean;
}
fn ss(values: []const f64, weights: []const f64, mean: f64) diag.Error!f64 {
    var result: Sum = .{};
    for (values, weights) |v, w| result.add(w * (v - mean) * (v - mean));
    const value = result.total();
    if (!std.math.isFinite(value) or value < 0) return error.ExecError;
    return value;
}
fn difference(cx: proc.ProcCtx, large: f64, small: f64) diag.Error!f64 {
    const value = large - small;
    const budget = 128 * std.math.floatEps(f64) * @max(1, @max(large, small));
    if (value < -budget) return cx.diags.fail(error.ExecError, 0, "PROC GLM: absorption projection increased residual SS", .{});
    return @max(0, value);
}
fn update(test_value: *math.EffectTest, mse: f64, df_error: usize, extra: usize) void {
    test_value.rank_full += extra;
    test_value.rank_reduced += extra;
    test_value.f_value = if (test_value.df > 0 and df_error > 0 and mse > 0) test_value.ms / mse else nan;
    test_value.p_value = reg.fProbability(test_value.f_value, test_value.df, df_error);
}

pub fn fit(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design) diag.Error!Result {
    const a = cx.arena;
    if (spec.absorb.len == 0 or !spec.intercept or d.n == 0 or d.p == 0) return cx.diags.fail(error.ExecError, 0, "PROC GLM: no valid observations for ABSORB", .{});
    const w = try a.alloc(f64, d.n);
    var count: usize = 0;
    for (w, d.weights, d.frequencies) |*combined, precision, freq| {
        combined.* = precision * freq;
        if (!std.math.isFinite(combined.*) or !(combined.* > 0) or freq >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return cx.diags.fail(error.ExecError, 0, "PROC GLM: invalid ABSORB weight/frequency", .{});
        count = std.math.add(usize, count, @intFromFloat(freq)) catch return error.ExecError;
    }
    const mean = try weightedMean(d.y, w);
    const total = try ss(d.y, w, mean);
    const uncorrected = try ss(d.y, w, 0);
    const yp = try a.alloc(f64, d.n);
    const q = d.p - 1;
    const xp = try a.alloc(f64, d.n * q);
    const absorbed = try a.alloc(Absorbed, spec.absorb.len);
    errdefer a.free(absorbed);
    var previous_ss = total;
    var previous_rank: usize = 1;
    var absorbed_rank: usize = 0;
    const scratch = try a.alloc(f64, d.n);
    for (spec.absorb, 0..) |ci, depth| {
        const keys = spec.absorb[0 .. depth + 1];
        var start: usize = 0;
        var groups: usize = 0;
        while (start < d.n) {
            var end = start + 1;
            while (end < d.n and equal(d.observations[start].cells, d.observations[end].cells, keys)) end += 1;
            const center = try weightedMean(d.y[start..end], w[start..end]);
            for (start..end) |i| yp[i] = d.y[i] - center;
            if (depth + 1 == spec.absorb.len) for (0..q) |j| {
                for (start..end) |i| scratch[i - start] = d.x[i * d.p + j + 1];
                const xmean = try weightedMean(scratch[0 .. end - start], w[start..end]);
                for (start..end) |i| xp[i * q + j] = d.x[i * d.p + j + 1] - xmean;
            };
            groups += 1;
            start = end;
        }
        const residual = try ss(yp, w, 0);
        const effect_ss = try difference(cx, previous_ss, residual);
        var label: std.ArrayList(u8) = .empty;
        try label.appendSlice(a, spec.input.ds.columns.items[ci].name);
        if (depth > 0) {
            try label.append(a, '(');
            for (spec.absorb[0..depth], 0..) |parent, j| {
                if (j > 0) try label.append(a, ' ');
                try label.appendSlice(a, spec.input.ds.columns.items[parent].name);
            }
            try label.append(a, ')');
        }
        const df = groups - previous_rank;
        absorbed[depth] = .{ .name = label.items[0..@min(label.items.len, spec.namelen)], .test_value = .{ .rank_full = groups, .rank_reduced = previous_rank, .df = df, .ss = effect_ss, .ms = if (df > 0) effect_ss / @as(f64, @floatFromInt(df)) else nan, .f_value = nan, .p_value = nan } };
        previous_ss = residual;
        previous_rank = groups;
        absorbed_rank = groups;
    }
    var conditional: ?math.Result = null;
    errdefer if (conditional) |*c| c.deinit(a);
    if (q > 0) {
        const effects = try a.alloc(math.Effect, d.effects.len);
        for (effects, d.effects) |*e, original| e.* = .{ .start = original.start - 1, .len = original.len };
        const factors = if (spec.ss2) try a.alloc(math.Factors, spec.effects.len) else null;
        if (factors) |metadata| for (metadata, spec.effects) |*target, effect| {
            var classes: std.ArrayList(usize) = .empty;
            var continuous: std.ArrayList(usize) = .empty;
            for (effect.variables) |col| {
                if (std.mem.indexOfScalar(usize, spec.classes, col) != null) try classes.append(a, col) else try continuous.append(a, col);
            }
            target.* = .{ .classes = classes.items, .continuous = continuous.items };
        };
        conditional = math.fit(a, xp, yp, d.n, q, effects, .{ .weights = d.weights, .frequencies = d.frequencies, .has_intercept = false, .singular = spec.singular, .type_ii = factors }) catch |err| {
            if (err == error.OutOfMemory) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC GLM: absorbed numerical fit failed", .{});
        };
    }
    const residual_rank = if (conditional) |c| c.model.fit.rank else 0;
    const explicit_three = if (@hasField(parse.Spec, "ss3")) spec.ss3 else false;
    const explicit_four = if (@hasField(parse.Spec, "ss4")) spec.ss4 else false;
    const wants_three = explicit_three or (!spec.ss1 and !spec.ss2 and !explicit_four);
    if (residual_rank < q and spec.effects.len > 1 and (wants_three or spec.classes.len == 0))
        return proc.failGap(cx.diags, 0, "PROC GLM: confounded multi-effect ABSORB hypotheses or parameter displays are not implemented", .{});
    const rank = absorbed_rank + residual_rank;
    if (rank > count) return cx.diags.fail(error.ExecError, 0, "PROC GLM: absorbed rank exceeds available observations", .{});
    const df_error = count - rank;
    const residual = if (conditional) |c| c.model.fit.sse else previous_ss;
    const mse = if (df_error > 0) residual / @as(f64, @floatFromInt(df_error)) else nan;
    if (conditional) |*c| {
        c.model.fit.n_used = count - absorbed_rank;
        c.model.fit.df_error = df_error;
        c.model.fit.mse = mse;
        for (c.model.fit.covariance, c.model.fit.covariance_unscaled, 0..) |*cov, base, i| cov.* = if (c.model.fit.aliased[i / q] or c.model.fit.aliased[i % q]) nan else mse * base;
        for (c.model.fit.se, 0..) |*se, j| se.* = @sqrt(c.model.fit.covariance[j * q + j]);
        inline for (.{ "type_i", "type_ii", "type_iii", "type_iv" }) |field| if (@hasField(math.Result, field)) {
            for (@field(c.*, field)) |*value| update(value, mse, df_error, absorbed_rank);
        };
    }
    for (absorbed) |*effect| update(&effect.test_value, mse, df_error, 0);
    const offset: usize = 1;
    const df_model = rank - offset;
    const df_total = count - offset;
    const chosen_total = total;
    const ss_model = try difference(cx, chosen_total, residual);
    const ms_model = if (df_model > 0) ss_model / @as(f64, @floatFromInt(df_model)) else nan;
    const f = if (df_model > 0 and df_error > 0 and mse > 0) ms_model / mse else nan;
    const zero_effects = try a.alloc(math.EffectTest, if (q == 0) spec.effects.len else 0);
    for (zero_effects) |*value| value.* = .{ .rank_full = absorbed_rank, .rank_reduced = absorbed_rank, .df = 0, .ss = 0, .ms = nan, .f_value = nan, .p_value = nan };
    return .{ .conditional = conditional, .absorbed = absorbed, .zero_effects = zero_effects, .within_x = xp, .within_y = yp, .weights = w, .absorbed_rank = absorbed_rank, .rank = rank, .n_used = count, .df_error = df_error, .sse = residual, .sst = total, .sst_uncorrected = uncorrected, .y_mean = mean, .mse = mse, .model = .{
        .df_model = df_model,
        .df_total = df_total,
        .ss_model = ss_model,
        .ms_model = ms_model,
        .f_value = f,
        .p_value = reg.fProbability(f, df_model, df_error),
        .r_square = if (chosen_total > 0) 1 - residual / chosen_total else nan,
        .adj_r_square = if (chosen_total > 0 and df_error > 0) 1 - (residual / chosen_total) * @as(f64, @floatFromInt(df_total)) / @as(f64, @floatFromInt(df_error)) else nan,
    } };
}

test {
    _ = @import("glm_absorb_tests.zig");
}
