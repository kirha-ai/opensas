//! GLM model and sequential/partial effect tests (STAT-GLM-002).
//! Reuses REG's ordered rank policy and QR; there is no second solver here.
//! The caller owns effect construction. For complete crossed CLASS models,
//! supply sum-to-zero contrasts and their products so that deleting an effect
//! tests the Type III equal-cell-weight hypothesis, NOT reference-cell effects.
//! Continuous effects use their raw columns (including polynomial powers).
//! Arbitrary dummy coding, missing-cell CLASS hypotheses, nesting and mixed
//! continuous/CLASS interactions need an estimable-function builder upstream;
//! this API does not infer those hypotheses from an unlabeled numeric matrix.
const std = @import("std");
const diag = @import("../diag.zig");
const reg = @import("reg_fit.zig");
const ranks = @import("reg_diagnostics.zig");
const A = std.mem.Allocator;
const nan = std.math.nan(f64);

/// Effects partition columns 1..p in MODEL order; column zero is the intercept.
/// A zero-width effect is allowed and has zero DF. Names remain caller-owned.
pub const Effect = struct { start: usize, len: usize };
pub const Options = struct {
    weights: ?[]const f64 = null,
    singular: f64 = ranks.default_singular,
};
pub const EffectTest = struct {
    rank_full: usize,
    rank_reduced: usize,
    df: usize,
    ss: f64,
    ms: f64,
    f_value: f64,
    p_value: f64,
};
pub const Result = struct {
    model: ranks.Result,
    type_i: []EffectTest,
    type_iii: []EffectTest,

    pub fn deinit(self: *Result, a: A) void {
        self.model.deinit(a);
        a.free(self.type_i);
        a.free(self.type_iii);
        self.* = undefined;
    }
};

/// x is n*p row-major, with a leading column of ones. Filter missing rows
/// upstream; weights are precision weights, not frequency counts. All tests
/// use the full model's error DF and MSE, including sequential Type I tests.
/// Rank-deficient effects have actual rank-difference DF, never column-count DF.
/// Zero-DF tests have SS=0 and undefined MS/F/p. Saturated models retain SS/DF
/// but have undefined F/p. Callers must report ExecError through diagnostics.
///
/// Numerical aliases are frozen at the full model's SINGULAR policy: excluded
/// columns are reconstructed in the retained space before submodel fitting.
/// Otherwise a rejected near-alias could reenter a reduced model and compare
/// nonnested fitted spaces. No model or hypothesis can acquire discarded rank.
pub fn fit(a: A, x: []const f64, y: []const f64, n: usize, p: usize, effects: []const Effect, options: Options) diag.Error!Result {
    var end: usize = 1;
    for (effects) |effect| {
        if (effect.start != end) return error.ExecError;
        end = std.math.add(usize, end, effect.len) catch return error.ExecError;
        if (end > p) return error.ExecError;
    }
    if (end != p) return error.ExecError;
    var model = try ranks.fit(a, x, y, n, p, options.weights, true, options.singular);
    errdefer model.deinit(a);
    const type_i = try a.alloc(EffectTest, effects.len);
    errdefer a.free(type_i);
    const type_iii = try a.alloc(EffectTest, effects.len);
    errdefer a.free(type_iii);
    const effective = try a.dupe(f64, x);
    defer a.free(effective);
    for (0..p) |j| {
        if (!model.fit.aliased[j]) continue;
        for (0..n) |i| {
            var sum: Sum = .{};
            for (0..p) |k| sum.add(x[i * p + k] * model.alias_coefficients[j * p + k]);
            effective[i * p + j] = sum.total();
            if (!std.math.isFinite(effective[i * p + j])) return error.ExecError;
        }
    }
    for (effects, 0..) |effect, e| {
        // Prefix columns define Type I; deleting a block from the complete
        // supplied hypothesis parameterization defines the partial Type III.
        const stop = effect.start + effect.len;
        const prefix_x = try select(a, effective, n, p, stop, null);
        defer a.free(prefix_x);
        var prefix = try ranks.fit(a, prefix_x, y, n, stop, options.weights, true, options.singular);
        defer prefix.deinit(a);
        type_i[e] = try reducedTest(a, effective, n, p, effect.start, null, prefix.fit, model.fit, options);
        type_iii[e] = try reducedTest(a, effective, n, p, p, effect, model.fit, model.fit, options);
    }
    return .{ .model = model, .type_i = type_i, .type_iii = type_iii };
}

fn select(a: A, x: []const f64, n: usize, p: usize, stop: usize, omit: ?Effect) diag.Error![]f64 {
    const width = stop - if (omit) |e| e.len else 0;
    const out = try a.alloc(f64, n * width);
    for (0..n) |i| {
        var k: usize = 0;
        for (0..stop) |j| {
            if (omit) |e| if (j >= e.start and j < e.start + e.len) continue;
            out[i * width + k] = x[i * p + j];
            k += 1;
        }
    }
    return out;
}

fn reducedTest(a: A, x: []const f64, n: usize, p: usize, stop: usize, omit: ?Effect, full: reg.Fit, error_model: reg.Fit, options: Options) diag.Error!EffectTest {
    const width = stop - if (omit) |e| e.len else 0;
    const reduced_x = try select(a, x, n, p, stop, omit);
    defer a.free(reduced_x);
    // Project fitted values rather than subtracting large, nearly equal SSEs.
    // For nested spaces ||(Pfull-Preduced)y||² is the hypothesis SS.
    var reduced = try ranks.fit(a, reduced_x, full.fitted, n, width, options.weights, true, options.singular);
    defer reduced.deinit(a);
    if (reduced.fit.rank > full.rank) return error.ExecError;
    const df = full.rank - reduced.fit.rank;
    const ss = if (df == 0) 0 else reduced.fit.sse;
    const ms = if (df > 0) ss / @as(f64, @floatFromInt(df)) else nan;
    const f = if (df > 0 and error_model.df_error > 0 and error_model.mse > 0) ms / error_model.mse else nan;
    return .{ .rank_full = full.rank, .rank_reduced = reduced.fit.rank, .df = df, .ss = ss, .ms = ms, .f_value = f, .p_value = reg.fProbability(f, df, error_model.df_error) };
}

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

const testing = std.testing;
const three_effects = [_]Effect{ .{ .start = 1, .len = 1 }, .{ .start = 2, .len = 1 }, .{ .start = 3, .len = 1 } };

test "GLM unbalanced factorial oracle and independent equal-cell contrasts" {
    const y = [_]f64{ 12, 14, 11, 9, 20, 18, 17 };
    const cell = [_]usize{ 0, 0, 1, 1, 2, 2, 3 };
    var x: [28]f64 = undefined;
    for (cell, 0..) |c, i| {
        const av: f64 = if (c < 2) 1 else -1;
        const bv: f64 = if (c % 2 == 0) 1 else -1;
        @memcpy(x[i * 4 ..][0..4], &[_]f64{ 1, av, bv, av * bv });
    }
    var result = try fit(testing.allocator, &x, &y, 7, 4, &three_effects, .{});
    defer result.deinit(testing.allocator);
    const model = result.model.fit;
    try testing.expectEqual(@as(usize, 4), model.rank);
    try testing.expectEqual(@as(usize, 7), model.n_used);
    try testing.expectEqual(@as(usize, 3), model.df_error);
    try testing.expectApproxEqAbs(@as(f64, 6), model.sse, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 97.71428571), model.sst, 5e-9);
    try testing.expectApproxEqAbs(@as(f64, 91.71428571), model.modelStats(true).ss_model, 5e-9);
    try testing.expectApproxEqAbs(@as(f64, 0.0253), model.modelStats(true).p_value, 5e-5);
    const expected_i = [_]f64{ 80.04761905, 11.26666667, 0.4 };
    const expected_iii = [_]f64{ 67.6, 10, 0.4 };
    const pi = [_]f64{ 0.0080, 0.0982, 0.6850 };
    const piii = [_]f64{ 0.0101, 0.1114, 0.6850 };
    // Independent cell-mean contrasts: Var(c'mean)/sigma²=sum(c²/ncell).
    // This establishes equal weighting of the four cells despite unequal n.
    const means = [_]f64{ 13, 10, 19, 17 };
    const counts = [_]f64{ 2, 2, 2, 1 };
    const contrasts = [_][4]f64{ .{ 1, 1, -1, -1 }, .{ 1, -1, 1, -1 }, .{ 1, -1, -1, 1 } };
    for (0..3) |j| {
        try testing.expectEqual(@as(usize, 1), result.type_i[j].df);
        try testing.expectEqual(@as(usize, 1), result.type_iii[j].df);
        try testing.expectApproxEqAbs(expected_i[j], result.type_i[j].ss, 5e-9);
        try testing.expectApproxEqAbs(expected_iii[j], result.type_iii[j].ss, 1e-11);
        try testing.expectApproxEqAbs(pi[j], result.type_i[j].p_value, 5e-5);
        try testing.expectApproxEqAbs(piii[j], result.type_iii[j].p_value, 5e-5);
        var estimate: f64 = 0;
        var variance: f64 = 0;
        for (contrasts[j], means, counts) |c, m, count| {
            estimate += c * m;
            variance += c * c / count;
        }
        try testing.expectApproxEqAbs(estimate * estimate / variance, result.type_iii[j].ss, 1e-11);
        try testing.expectApproxEqAbs(expected_iii[j] / 2, result.type_iii[j].f_value, 1e-11);
    }
    for (cell, model.fitted) |c, prediction| try testing.expectApproxEqAbs(means[c], prediction, 1e-12);
}

test "GLM iron polynomial and simple regression original oracle" {
    const fe = [_]f64{ 0.01, 0.48, 0.71, 0.95, 1.19, 0.01, 0.48, 1.44, 0.71, 1.96, 0.01, 1.44, 1.96 };
    const y = [_]f64{ 127.6, 124.0, 110.8, 103.9, 101.5, 130.1, 122.0, 92.3, 113.1, 83.7, 128.0, 91.4, 86.2 };
    var x: [39]f64 = undefined;
    var linear: [26]f64 = undefined;
    for (fe, 0..) |v, i| {
        @memcpy(x[i * 3 ..][0..3], &[_]f64{ 1, v, v * v });
        @memcpy(linear[i * 2 ..][0..2], &[_]f64{ 1, v });
    }
    var quad = try fit(testing.allocator, &x, &y, 13, 3, three_effects[0..2], .{});
    defer quad.deinit(testing.allocator);
    var line = try fit(testing.allocator, &linear, &y, 13, 2, three_effects[0..1], .{});
    defer line.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 10), quad.model.fit.df_error);
    try testing.expectEqual(@as(usize, 11), line.model.fit.df_error);
    try testing.expectApproxEqAbs(@as(f64, 100.086334), quad.model.fit.sse, 5e-7);
    try testing.expectApproxEqAbs(@as(f64, 102.850233), line.model.fit.sse, 5e-7);
    try testing.expectApproxEqAbs(@as(f64, 3396.616923), quad.model.fit.sst, 5e-7);
    try testing.expectApproxEqAbs(@as(f64, 3293.766690), quad.type_i[0].ss, 5e-7);
    try testing.expectApproxEqAbs(@as(f64, 2.7638994), quad.type_i[1].ss, 5e-8);
    try testing.expectApproxEqAbs(@as(f64, 356.7572421), quad.type_iii[0].ss, 5e-8);
    try testing.expectApproxEqAbs(@as(f64, 2.7638994), quad.type_iii[1].ss, 5e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.6107), quad.type_iii[1].p_value, 5e-5);
    try testing.expectApproxEqAbs(@as(f64, 3293.766690), line.type_iii[0].ss, 5e-7);
    try testing.expectApproxEqAbs(line.type_i[0].ss, line.type_iii[0].ss, 1e-10);
    for ([_]f64{ 130.3199337, -26.2203900, 1.1552018 }, quad.model.fit.coefficients) |expected, actual| try testing.expectApproxEqAbs(expected, actual, 5e-8);
    for ([_]f64{ 1.77096213, 4.39177557, 2.19828568 }, quad.model.fit.se) |expected, actual| try testing.expectApproxEqAbs(expected, actual, 5e-9);
    for ([_]f64{ 129.7865993, -24.0198934 }, line.model.fit.coefficients) |expected, actual| try testing.expectApproxEqAbs(expected, actual, 5e-8);
    for ([_]f64{ 1.40273671, 1.27976715 }, line.model.fit.se) |expected, actual| try testing.expectApproxEqAbs(expected, actual, 5e-9);
    for (quad.type_iii, 1..) |effect, j| {
        const t = quad.model.fit.coefficientT(j);
        try testing.expectApproxEqAbs(t * t, effect.f_value, 1e-10);
        try testing.expectApproxEqAbs(quad.model.fit.coefficientP(j), effect.p_value, 1e-12);
    }
}

test "GLM exact aliases use effect ranks and grouped estimable space" {
    const t = [_]f64{ -2, -1, 0, 1, 2 };
    const y = [_]f64{ -1, 2, 1, 6, 7 }; // 3+2t+(0,1,-2,1,0)
    var x: [15]f64 = undefined;
    for (t, 0..) |v, i| @memcpy(x[i * 3 ..][0..3], &[_]f64{ 1, v, 2 * v });
    var result = try fit(testing.allocator, &x, &y, 5, 3, three_effects[0..2], .{});
    defer result.deinit(testing.allocator);
    try testing.expectEqual(ranks.RankStatus.rank_deficient, result.model.status);
    try testing.expectEqual(@as(usize, 2), result.model.fit.rank);
    try testing.expectEqual(@as(usize, 3), result.model.fit.df_error);
    try testing.expectApproxEqAbs(@as(f64, 6), result.model.fit.sse, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 40), result.type_i[0].ss, 1e-12);
    try testing.expectEqual(@as(usize, 0), result.type_i[1].df);
    for (result.type_iii) |effect| {
        try testing.expectEqual(@as(usize, 2), effect.rank_full);
        try testing.expectEqual(@as(usize, 2), effect.rank_reduced);
        try testing.expectEqual(@as(usize, 0), effect.df);
        try testing.expectEqual(@as(f64, 0), effect.ss);
        try testing.expect(std.math.isNan(effect.ms) and std.math.isNan(effect.f_value) and std.math.isNan(effect.p_value));
    }
    var grouped = try fit(testing.allocator, &x, &y, 5, 3, &.{.{ .start = 1, .len = 2 }}, .{});
    defer grouped.deinit(testing.allocator);
    // The slope space has one DF even though its effect owns two columns.
    try testing.expectEqual(@as(usize, 1), grouped.type_iii[0].df);
    try testing.expectApproxEqAbs(@as(f64, 40), grouped.type_iii[0].ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 20), grouped.type_iii[0].f_value, 1e-12);
}

test "GLM near rank independent orthogonal components and frozen aliases" {
    const t = [_]f64{ -2, -1, 0, 1, 2 };
    const z = [_]f64{ 1, -2, 2, -2, 1 };
    const noise = [_]f64{ 1, -2, 0, 2, -1 };
    // t, z, noise are mutually orthogonal and centered, with norms² 10,14,10.
    // This determines all SS without invoking another regression implementation.
    var y: [5]f64 = undefined;
    var x: [15]f64 = undefined;
    for ([_]f64{ 1e-6, 1e-3 }) |delta| {
        for (t, z, noise, 0..) |v, orthogonal, residual, i| {
            y[i] = 3 + 2 * v + orthogonal + residual;
            @memcpy(x[i * 3 ..][0..3], &[_]f64{ 1, v, v + delta * orthogonal });
        }
        var result = try fit(testing.allocator, &x, &y, 5, 3, three_effects[0..2], .{});
        defer result.deinit(testing.allocator);
        const expected_pivot = 14 * delta * delta / (10 + 14 * delta * delta);
        try testing.expectApproxEqAbs(expected_pivot, result.model.pivot_tolerance[2], 1e-16);
        try testing.expectApproxEqAbs(@as(f64, 40), result.type_i[0].ss, 1e-10);
        if (delta == 1e-6) {
            try testing.expectEqual(@as(usize, 2), result.model.fit.rank);
            try testing.expectApproxEqAbs(@as(f64, 24), result.model.fit.sse, 1e-10);
            try testing.expectEqual(@as(usize, 0), result.type_i[1].df);
            for (result.type_iii) |effect| try testing.expectEqual(@as(usize, 0), effect.df);
        } else {
            try testing.expectEqual(ranks.RankStatus.nearly_singular, result.model.status);
            try testing.expectEqual(@as(usize, 3), result.model.fit.rank);
            try testing.expectApproxEqAbs(@as(f64, 10), result.model.fit.sse, 1e-9);
            try testing.expectApproxEqAbs(@as(f64, 14), result.type_i[1].ss, 1e-9);
            try testing.expectApproxEqAbs(@as(f64, 14), result.type_iii[1].ss, 1e-9);
            const beta_t = 2 - 1 / delta;
            const conditional_ss = beta_t * beta_t * 10 * expected_pivot;
            try testing.expectApproxEqAbs(conditional_ss, result.type_iii[0].ss, 1e-9);
            try testing.expectApproxEqAbs(conditional_ss / 5, result.type_iii[0].f_value, 1e-9);
        }
    }
}

test "GLM weighted manual slope and empty effect" {
    const x = [_]f64{ 1, 0, 1, 1, 1, 2, 1, 100 };
    const y = [_]f64{ 1, 2, 2, 1000 };
    const effects = [_]Effect{ .{ .start = 1, .len = 0 }, .{ .start = 1, .len = 1 } };
    var result = try fit(testing.allocator, &x, &y, 4, 2, &effects, .{ .weights = &.{ 1, 2, 1, 0 } });
    defer result.deinit(testing.allocator);
    // Weighted mean=7/4, centered Sxx=2, Sxy=1, SST=3/4.
    try testing.expectEqual(@as(usize, 3), result.model.fit.n_used);
    try testing.expectEqual(@as(usize, 1), result.model.fit.df_error);
    try testing.expectEqual(@as(usize, 0), result.type_i[0].df);
    try testing.expectEqual(@as(usize, 0), result.type_iii[0].df);
    try testing.expectApproxEqAbs(@as(f64, 0.25), result.model.fit.sse, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.5), result.type_iii[1].ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 2), result.type_iii[1].f_value, 1e-12);
    var scaled = try fit(testing.allocator, &x, &y, 4, 2, &effects, .{ .weights = &.{ 10, 20, 10, 0 } });
    defer scaled.deinit(testing.allocator);
    try testing.expectApproxEqAbs(10 * result.type_iii[1].ss, scaled.type_iii[1].ss, 1e-12);
    try testing.expectApproxEqAbs(result.type_iii[1].f_value, scaled.type_iii[1].f_value, 1e-12);
}

test "GLM grouped CLASS contrast has two numerator degrees of freedom" {
    // Three cell means 2,5,8, sizes 2,2,1; SSE=4, grand mean=4.4.
    const x = [_]f64{ 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, -1, -1 };
    const y = [_]f64{ 1, 3, 4, 6, 8 };
    var result = try fit(testing.allocator, &x, &y, 5, 3, &.{.{ .start = 1, .len = 2 }}, .{});
    defer result.deinit(testing.allocator);
    const between: f64 = 2 * (2 - 4.4) * (2 - 4.4) + 2 * (5 - 4.4) * (5 - 4.4) + (8 - 4.4) * (8 - 4.4);
    try testing.expectEqual(@as(usize, 2), result.type_iii[0].df);
    try testing.expectApproxEqAbs(@as(f64, 4), result.model.fit.sse, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, between), result.type_i[0].ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, between), result.type_iii[0].ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, between / 4), result.type_iii[0].f_value, 1e-12);
    // For F(2,2), the survival function is 1/(1+F).
    try testing.expectApproxEqAbs(@as(f64, 1 / (1 + between / 4)), result.type_iii[0].p_value, 1e-12);
}

test "GLM Type I follows effect order while Type III survives contrast scaling" {
    const y = [_]f64{ 12, 14, 11, 9, 20, 18, 17 };
    const cell = [_]usize{ 0, 0, 1, 1, 2, 2, 3 };
    var x: [28]f64 = undefined;
    var reversed: [28]f64 = undefined;
    for (cell, 0..) |c, i| {
        const av: f64 = if (c < 2) 1 else -1;
        const bv: f64 = if (c % 2 == 0) 1 else -1;
        @memcpy(x[i * 4 ..][0..4], &[_]f64{ 1, av, bv, av * bv });
        @memcpy(reversed[i * 4 ..][0..4], &[_]f64{ 1, bv * 1e-8, av * -1e8, av * bv * 3 });
    }
    var original = try fit(testing.allocator, &x, &y, 7, 4, &three_effects, .{});
    defer original.deinit(testing.allocator);
    var swapped = try fit(testing.allocator, &reversed, &y, 7, 4, &three_effects, .{});
    defer swapped.deinit(testing.allocator);
    for ([_]usize{ 1, 0, 2 }, 0..) |j, k| try testing.expectApproxEqAbs(original.type_iii[j].ss, swapped.type_iii[k].ss, 1e-10);
    // B-first: mean(B1)=16, mean(B2)=37/3; two-group between SS.
    const b_first = (4.0 * 3.0 / 7.0) * (16.0 - 37.0 / 3.0) * (16.0 - 37.0 / 3.0);
    try testing.expectApproxEqAbs(@as(f64, b_first), swapped.type_i[0].ss, 1e-10);
    try testing.expect(@abs(swapped.type_i[1].ss - original.type_i[0].ss) > 1);
    var total: f64 = 0;
    for (swapped.type_i) |effect| total += effect.ss;
    try testing.expectApproxEqAbs(swapped.model.fit.modelStats(true).ss_model, total, 1e-10);
}

test "GLM saturated model malformed ownership and nonfinite rejection" {
    const a = testing.allocator;
    var saturated = try fit(a, &.{ 1, 0, 1, 1 }, &.{ 2, 3 }, 2, 2, three_effects[0..1], .{});
    defer saturated.deinit(a);
    try testing.expectEqual(@as(usize, 0), saturated.model.fit.df_error);
    try testing.expectEqual(@as(usize, 1), saturated.type_iii[0].df);
    try testing.expectApproxEqAbs(@as(f64, 0.5), saturated.type_iii[0].ss, 1e-12);
    try testing.expect(std.math.isNan(saturated.type_iii[0].f_value));
    var intercept = try fit(a, &.{ 1, 1 }, &.{ 2, 4 }, 2, 1, &.{}, .{});
    defer intercept.deinit(a);
    try testing.expectEqual(@as(usize, 0), intercept.type_i.len);
    try testing.expectApproxEqAbs(@as(f64, 2), intercept.model.fit.sse, 1e-12);
    try testing.expectError(error.ExecError, fit(a, &.{ 1, 2 }, &.{1}, 1, 2, &.{}, .{}));
    try testing.expectError(error.ExecError, fit(a, &.{ 1, 2 }, &.{1}, 1, 2, &.{.{ .start = 0, .len = 2 }}, .{}));
    try testing.expectError(error.ExecError, fit(a, &.{ 1, 2 }, &.{1}, 1, 2, &.{.{ .start = 1, .len = std.math.maxInt(usize) }}, .{}));
    try testing.expectError(error.ExecError, fit(a, &.{ 1, nan }, &.{1}, 1, 2, three_effects[0..1], .{}));
    try testing.expectError(error.ExecError, fit(a, &.{ 2, 3 }, &.{1}, 1, 2, three_effects[0..1], .{}));
    try testing.expectError(error.ExecError, fit(a, &.{ 1, 2 }, &.{1}, 1, 2, three_effects[0..1], .{ .singular = 0 }));
}

fn allocationCheck(a: A) !void {
    var result = try fit(a, &.{ 1, 0, 1, 1, 1, 2 }, &.{ 1, 2, 2 }, 3, 2, three_effects[0..1], .{});
    defer result.deinit(a);
}

test "GLM allocation failures free model and effect test storage" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationCheck, .{});
}
