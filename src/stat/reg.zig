//! PROC REG input selection and execution. Computation belongs to reg_fit.zig.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
pub const parsing = @import("reg_parse.zig");
pub const Spec = parsing.Spec;
pub const Model = parsing.Model;
pub const parse = parsing.parse;

/// Row-major design, including the intercept when requested. Frequency counts
/// remain separate from relative precision weights: only frequencies affect N.
pub const Selected = struct {
    x: []const f64,
    y: []const f64,
    weights: []const f64,
    frequencies: []const f64,
    source_rows: []const usize,
    columns: usize,
    read: usize,
};
pub fn select(cx: proc.ProcCtx, spec: Spec, model: Model, rows: []const []const Value) diag.Error!Selected {
    var x: std.ArrayList(f64) = .empty;
    var y: std.ArrayList(f64) = .empty;
    var weights: std.ArrayList(f64) = .empty;
    var frequencies: std.ArrayList(f64) = .empty;
    var source: std.ArrayList(usize) = .empty;
    for (rows, 0..) |row, index| {
        var usable = true;
        for (spec.required) |ci| {
            const v = row[ci].num;
            if (std.math.isNan(v)) {
                usable = false;
                break;
            }
            if (!std.math.isFinite(v)) return cx.diags.fail(error.ExecError, 0, "PROC REG: nonfinite analysis value", .{});
        }
        if (!usable) continue;
        const weight = if (spec.weight) |c| row[c].num else 1;
        const frequency = if (spec.freq) |c| row[c].num else 1;
        if (std.math.isNan(weight) or weight <= 0 or std.math.isNan(frequency) or frequency < 1) continue;
        if (!std.math.isFinite(weight) or !std.math.isFinite(frequency)) return cx.diags.fail(error.ExecError, 0, "PROC REG: nonfinite frequency or weight", .{});
        if (model.intercept) try x.append(cx.arena, 1);
        for (model.regressors) |ci| try x.append(cx.arena, row[ci].num);
        try y.append(cx.arena, row[model.dependent].num);
        try weights.append(cx.arena, weight);
        try frequencies.append(cx.arena, @floor(frequency));
        try source.append(cx.arena, index + 1);
    }
    return .{ .x = x.items, .y = y.items, .weights = weights.items, .frequencies = frequencies.items, .source_rows = source.items, .columns = model.regressors.len + @as(usize, if (model.intercept) 1 else 0), .read = rows.len };
}

pub const FittedModel = struct {
    model: Model,
    input: Selected,
    weights: []const f64,
    count: f64,
    diagnostics: @import("reg_diagnostics.zig").Result,
};

/// Shared computation for listing execution and silent interactive REFIT.
fn fitModel(cx: proc.ProcCtx, spec: Spec, model: Model, rows: []const []const Value) diag.Error!FittedModel {
    const input = try select(cx, spec, model, rows);
    if (input.y.len == 0) return cx.diags.fail(error.ExecError, 0, "PROC REG: no usable observations", .{});
    // The solver accepts precision weights. Multiplying by frequency
    // gives the same crossproducts, then DF and covariance are adjusted
    // using the independently accumulated replication count.
    const w = try cx.arena.alloc(f64, input.y.len);
    var count: f64 = 0;
    for (w, input.weights, input.frequencies) |*dest, weight, freq| {
        dest.* = weight * freq;
        count += freq;
    }
    if (count >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return cx.diags.fail(error.ExecError, 0, "PROC REG: frequency total exceeds representable observation count", .{});
    const diagnostics = @import("reg_diagnostics.zig").fit(cx.arena, input.x, input.y, input.y.len, input.columns, w, model.intercept, model.singular) catch |err| {
        if (err == error.OutOfMemory) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC REG: numerical fit failed", .{});
    };

    var fitted = diagnostics;
    rescaleFrequencyInference(&fitted.fit, @intFromFloat(count));
    return .{ .model = model, .input = input, .weights = w, .count = count, .diagnostics = fitted };
}

/// Execute a complete initial REG step. Unsupported continuations remain loud.
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const @import("../lexer.zig").Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    try execute(cx, out, spec);
}
pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec) diag.Error!void {
    try executePrepared(cx, out, spec, null);
}

fn executePrepared(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, prepared: ?[]const FittedModel) diag.Error!void {
    if (prepared) |fits| if (spec.by.len != 0 or fits.len != spec.models.len) return cx.diags.fail(error.ExecError, 0, "PROC REG: inconsistent prepared model results", .{});
    const groups = try @import("by_groups.zig").checkedSlices(cx.arena, spec.ds, spec.by, spec.descending, spec.notsorted, cx.diags);
    if (groups.len == 0) return cx.diags.fail(error.ExecError, 0, "PROC REG: no observations", .{});
    const estimates = if (spec.outest != null) try @import("reg_outest.zig").Builder.init(cx.arena, spec, cx.diags) else null;
    for (groups) |group| {
        if (group.rep) |rep| if (!spec.noprint) {
            try @import("by_groups.zig").appendLine(cx.arena, out, spec.ds, rep, spec.by);
        };
        for (spec.models, 0..) |model, model_index| {
            const computed = if (prepared) |fits| fits[model_index] else try fitModel(cx, spec, model, group.rows);
            const input = computed.input;
            const w = computed.weights;
            const count = computed.count;
            const diagnostics = computed.diagnostics;
            const fit = diagnostics.fit;
            var ridge_path: ?@import("reg_ridge.zig").Path = null;
            var ridge_x: []const f64 = &.{};
            if (spec.ridge.len > 0) {
                if (fit.rank != input.columns or model.regressors.len == 0 or !(fit.sst > 0)) return proc.failGap(cx.diags, 0, "PROC REG: ridge paths with aliased columns or constant responses are not implemented", .{});
                const p = model.regressors.len;
                const x = try cx.arena.alloc(f64, input.y.len * p);
                for (0..input.y.len) |row| @memcpy(x[row * p ..][0..p], input.x[row * input.columns + 1 ..][0..p]);
                ridge_x = x;
                ridge_path = @import("reg_ridge.zig").compute(cx.arena, x, input.y, p, w, spec.ridge, fit.df_error) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return cx.diags.fail(error.ExecError, 0, "PROC REG: ridge numerical calculation failed", .{});
                };
            }
            if (estimates) |builder| {
                try builder.append(cx.arena, model, group.rep, fit);
                if (ridge_path) |path| for (path.points) |point| try builder.appendRidge(cx.arena, model, group.rep, fit, point);
            }
            const stats = fit.modelStats(model.intercept);
            const ts = try cx.arena.alloc(f64, input.columns);
            const ps = try cx.arena.alloc(f64, input.columns);
            const tolerances = try cx.arena.alloc(f64, input.columns);
            const vifs = try cx.arena.alloc(f64, input.columns);
            for (ts, ps, 0..) |*t, *p, j| {
                t.* = fit.coefficientT(j);
                p.* = fit.coefficientP(j);
                if (fit.aliased[j]) {
                    tolerances[j] = std.math.nan(f64);
                    vifs[j] = std.math.nan(f64);
                    continue;
                }
                if (model.intercept and j == 0) {
                    tolerances[j] = std.math.nan(f64);
                    vifs[j] = 0;
                    continue;
                }
                var sumw: f64 = 0;
                var sumx: f64 = 0;
                for (w, 0..) |weight, k| {
                    sumw += weight;
                    sumx += weight * input.x[k * input.columns + j];
                }
                const mean = if (model.intercept) sumx / sumw else 0;
                var ss: f64 = 0;
                for (w, 0..) |weight, k| {
                    const delta = input.x[k * input.columns + j] - mean;
                    ss += weight * delta * delta;
                }
                vifs[j] = ss * fit.covariance_unscaled[j * input.columns + j];
                tolerances[j] = 1 / vifs[j];
            }
            var dependencies: std.ArrayList(u8) = .empty;
            for (fit.aliased, 0..) |aliased, j| {
                if (!aliased) continue;
                const name = parameterName(spec, model, j);
                try dependencies.print(cx.arena, "{s} = ", .{name});
                var terms: usize = 0;
                for (fit.aliased, 0..) |other_alias, k| {
                    if (other_alias) continue;
                    const coefficient = diagnostics.alias_coefficients[j * input.columns + k];
                    if (coefficient == 0) continue;
                    if (terms > 0) try dependencies.appendSlice(cx.arena, if (coefficient < 0) " - " else " + ");
                    const displayed = if (terms > 0) @abs(coefficient) else coefficient;
                    try dependencies.print(cx.arena, "{s} * {s}", .{ std.mem.trim(u8, try @import("../format.zig").apply(cx.arena, .{ .num = displayed }, "best12."), " "), parameterName(spec, model, k) });
                    terms += 1;
                }
                if (terms == 0) try dependencies.appendSlice(cx.arena, "0");
                try dependencies.append(cx.arena, '\n');
            }
            if (!spec.noprint) try @import("reg_render.zig").render(cx.arena, out, spec, model, input.read, input.y.len, .{
                .n = count,
                .rank = fit.rank,
                .df_model = @floatFromInt(stats.df_model),
                .df_error = @floatFromInt(fit.df_error),
                .df_total = @floatFromInt(stats.df_total),
                .ss_model = stats.ss_model,
                .ss_error = fit.sse,
                .ss_total = if (model.intercept) fit.sst else fit.sst_uncorrected,
                .ms_model = stats.ms_model,
                .ms_error = fit.mse,
                .f = stats.f_value,
                .p = stats.p_value,
                .root_mse = @sqrt(fit.mse),
                .mean = fit.y_mean,
                .cv = 100 * @sqrt(fit.mse) / fit.y_mean,
                .r_square = stats.r_square,
                .adj_r_square = stats.adj_r_square,
                .aliased = fit.aliased,
                .biased = fit.biased,
                .dependencies = dependencies.items,
                .estimates = fit.coefficients,
                .errors = fit.se,
                .t = ts,
                .probabilities = ps,
                .tolerance = tolerances,
                .vif = vifs,
            });
            if (ridge_path) |path| try @import("reg_ridge_plots.zig").execute(cx, spec, model, path, ridge_x, input.y, fit);
            if (!spec.noprint and (model.residual or model.cli or model.clm)) {
                if (spec.ids.len > 0 or spec.freq != null or spec.weight != null or input.y.len != input.read) return proc.failGap(cx.diags, 0, "PROC REG: diagnostic listing with ID, FREQ, WEIGHT or excluded rows is not implemented", .{});
                if (fit.df_error == 0 or !(fit.mse > 0)) return proc.failGap(cx.diags, 0, "PROC REG: diagnostic listing for zero residual variance is not implemented", .{});
                for (fit.leverage) |h| if (!(h < 1)) return proc.failGap(cx.diags, 0, "PROC REG: diagnostic listing for unit leverage is not implemented", .{});
                try @import("reg_render.zig").observations(cx.arena, out, spec, model, input.y, fit);
            }
        }
    }
    // Publish only after every BY/model fit and output row has succeeded.
    if (estimates) |builder| {
        try builder.ridgeFormats(cx.arena);
        try cx.lib.put(spec.outest.?, builder.ds);
    }
}

test "REG selection keeps frequency, weight and source observations separate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "extra", "w", "f" }) |n| _ = try ds.addColumn(n, .num);
    for ([_][5]f64{ .{ 1, 3, 0, 2, 2.9 }, .{ 2, 5, std.math.nan(f64), 1, 1 }, .{ 3, 7, 0, 0, 1 }, .{ 4, 9, 0, 1, 0.9 }, .{ 5, 11, 0, 3, 1 } }) |row| {
        var cells: [5]Value = undefined;
        for (row, 0..) |v, i| cells[i] = .{ .num = v };
        try ds.appendRow(&cells);
    }
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const tokens = try @import("../lexer.zig").tokenize(a, "proc reg; var extra; weight w; freq f; model y=x; run; quit;", &d);
    const spec = try parse(cx, tokens);
    const chosen = try select(cx, spec, spec.models[0], ds.rows.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 5 }, chosen.source_rows);
    try std.testing.expectEqualSlices(f64, &.{ 2, 1 }, chosen.frequencies);
    try std.testing.expectEqualSlices(f64, &.{ 2, 3 }, chosen.weights);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 1, 5 }, chosen.x);
    try std.testing.expectEqual(@as(usize, 5), ds.rows.items.len);
}

test "REG parsing distinguishes invalid syntax from unsupported documented features" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("id", .char);
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const lex = @import("../lexer.zig");
    for ([_][]const u8{ "proc reg; model y x; run;", "proc reg alpha=2; model y=x; run;", "proc reg; model id=x; run;", "proc reg; model y=x*x; run;", "proc reg; freq x y; model y=x; run;", "proc reg; model y=x / nonsense; run;" }) |src| {
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, src, &d)));
    }
    try std.testing.expect(d.hasErrors());
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc reg; model y=x / selection=stepwise; run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "not implemented") != null);
}

test "REG BY uses sorted groups and rejects reversal; IDs do not filter missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "g" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("id", .char);
    for ([_]f64{ 1, 1, 2, 2 }) |g| try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = g }, .{ .str = "" } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc reg; by g; id id; model y=x; run;", &d));
    const by = @import("by_groups.zig");
    const groups = try by.checkedSlices(a, spec.ds, spec.by, spec.descending, spec.notsorted, &d);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    for (groups) |g| {
        const chosen = try select(cx, spec, spec.models[0], g.rows);
        try std.testing.expectEqual(@as(usize, 2), chosen.y.len);
    }
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 1 }, .{ .str = "" } });
    try std.testing.expectError(error.ParseError, by.checkedSlices(a, spec.ds, spec.by, spec.descending, false, &d));
}

test "REG missingness is shared across multiple models and VAR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "z" }) |n| _ = try ds.addColumn(n, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, Value.missing });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 4 }, .{ .num = 6 } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc reg; first: model y=x; second: model z=x; run;", &d));
    for (spec.models) |m| {
        const chosen = try select(cx, spec, m, ds.rows.items);
        try std.testing.expectEqualSlices(usize, &.{2}, chosen.source_rows);
    }
    try std.testing.expectEqualStrings("second", spec.models[1].label);
}

/// Replication changes residual degrees of freedom, unlike precision weights.
/// Keep every representation of inference consistent after changing the MSE.
fn rescaleFrequencyInference(fit: *@import("reg_fit.zig").Fit, count: usize) void {
    fit.n_used = count;
    fit.df_error = count - fit.rank;
    fit.mse = if (fit.df_error > 0) fit.sse / @as(f64, @floatFromInt(fit.df_error)) else std.math.nan(f64);
    const p = fit.coefficients.len;
    for (fit.covariance, fit.covariance_unscaled, 0..) |*cov, unscaled, i| {
        cov.* = if (fit.aliased[i / p] or fit.aliased[i % p]) std.math.nan(f64) else fit.mse * unscaled;
    }
    for (fit.se, 0..) |*se, j| se.* = @sqrt(fit.covariance[j * p + j]);
}

test "REG replication rescales covariance and standard errors together" {
    var fit = try @import("reg_fit.zig").fit(std.testing.allocator, &.{ 1, 1, 1, 2, 1, 3 }, &.{ 2, 5, 5 }, 3, 2, &.{ 2, 2, 2 });
    defer fit.deinit(std.testing.allocator);
    rescaleFrequencyInference(&fit, 6);
    try std.testing.expectEqual(@as(usize, 4), fit.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), fit.mse, 1e-12);
    for (fit.covariance, fit.covariance_unscaled) |cov, unscaled| try std.testing.expectApproxEqAbs(0.75 * unscaled, cov, 1e-12);
    for (fit.se, 0..) |se, j| try std.testing.expectApproxEqAbs(se * se, fit.covariance[j * 2 + j], 1e-12);
}

fn parameterName(spec: Spec, model: Model, i: usize) []const u8 {
    return if (model.intercept and i == 0) "Intercept" else spec.ds.columns.items[model.regressors[i - @as(usize, if (model.intercept) 1 else 0)]].name;
}
/// Keep the CLI continuation admission list beside its owning interpreter.
pub fn continuationKeyword(word: []const u8) bool {
    inline for (.{ "add", "delete", "print", "refit", "run", "quit", "model", "mtest", "output", "paint", "plot", "restrict", "reweight", "test" }) |name| {
        if (std.ascii.eqlIgnoreCase(word, name)) return true;
    }
    return false;
}

pub const Session = struct {
    spec: Spec,
    revision: usize = 0,
    fitted: []const FittedModel = &.{},
    base_labels: []const []const u8 = &.{},
    other_models: bool = false,

    /// The current MODEL is the last MODEL statement, including every response
    /// from that statement. Crossproduct/missingness variables remain frozen.
    fn current(self: *Session, cx: proc.ProcCtx) diag.Error!Spec {
        if (self.spec.models.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC REG: no current MODEL", .{});
        if (self.spec.by.len > 0) return cx.diags.fail(error.ParseError, 0, "PROC REG: interactivity is disabled with BY processing", .{});
        const group = self.spec.models[self.spec.models.len - 1].statement_index;
        var first = self.spec.models.len - 1;
        while (first > 0 and self.spec.models[first - 1].statement_index == group) first -= 1;
        self.other_models = self.other_models or first > 0;
        var selected = self.spec;
        selected.models = self.spec.models[first..];
        return selected;
    }

    fn compute(cx: proc.ProcCtx, spec: Spec) diag.Error![]const FittedModel {
        const fits = try cx.arena.alloc(FittedModel, spec.models.len);
        for (spec.models, fits) |model, *fit| fit.* = try fitModel(cx, spec, model, spec.ds.rows.items);
        return fits;
    }

    /// REFIT has no listing or output-dataset side effects. It still executes
    /// the numerical fit and exposes failures; it is never an inert keyword.
    pub fn refit(self: *Session, cx: proc.ProcCtx) diag.Error!void {
        self.fitted = try compute(cx, try self.current(cx));
    }

    fn edit(self: *Session, cx: proc.ProcCtx, tokens: []const @import("../lexer.zig").Token, adding: bool) diag.Error!void {
        var selected = try self.current(cx);
        const variables = try parsing.columns(cx, selected.ds, tokens[1..], true);
        if (variables.len == 0) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC REG {s} requires variables", .{if (adding) @as([]const u8, "ADD") else "DELETE"});
        for (variables) |ci| {
            if (adding and std.mem.indexOfScalar(usize, selected.required, ci) == null) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC REG: ADD variable {s} was not declared before RUN", .{selected.ds.columns.items[ci].name});
            if (!adding) for (selected.models) |model| {
                if (std.mem.indexOfScalar(usize, model.regressors, ci) == null) return proc.failGap(cx.diags, tokens[0].line, "PROC REG: DELETE of inactive variable {s} is not implemented", .{selected.ds.columns.items[ci].name});
            };
        }
        const labels = if (self.base_labels.len > 0) self.base_labels else blk: {
            const names = try cx.arena.alloc([]const u8, selected.models.len);
            for (names, selected.models) |*name, model| name.* = model.label;
            break :blk names;
        };
        const old_models = selected.models;
        const models = try cx.arena.dupe(Model, selected.models);
        for (models, 0..) |*model, j| {
            var columns: std.ArrayList(usize) = .empty;
            for (model.regressors) |ci| {
                if (adding or std.mem.indexOfScalar(usize, variables, ci) == null) try columns.append(cx.arena, ci);
            }
            if (adding) for (variables) |ci| {
                if (std.mem.indexOfScalar(usize, columns.items, ci) == null) try columns.append(cx.arena, ci);
            };
            if (!model.intercept and columns.items.len == 0) return proc.failGap(cx.diags, tokens[0].line, "PROC REG: deleting every parameter of a NOINT model is not implemented", .{});
            model.regressors = columns.items;
            model.label = try std.fmt.allocPrint(cx.arena, "{s}.{d}", .{ labels[j], self.revision + 1 });
        }
        selected.models = models;
        const fits = try compute(cx, selected);
        // Commit only after validation and all response fits succeed.
        self.spec = selected;
        self.fitted = fits;
        self.base_labels = labels;
        self.revision += 1;
        for (variables) |ci| {
            if (!adding or std.mem.indexOfScalar(usize, old_models[0].regressors, ci) == null)
                try cx.diags.note(tokens[0].line, "Variable {s} is {s}.", .{ selected.ds.columns.items[ci].name, if (adding) @as([]const u8, "added") else "deleted" });
        }
        try cx.diags.note(tokens[0].line, "Due to {s} {s} statement, the model label is now {s}.", .{ if (adding) @as([]const u8, "an") else "a", if (adding) @as([]const u8, "ADD") else "DELETE", models[0].label });
    }

    pub fn continuation(self: *Session, cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const @import("../lexer.zig").Token) diag.Error!bool {
        const eq = std.ascii.eqlIgnoreCase;
        var i: usize = 0;
        while (i < t.len and t[i].tag != .eof) {
            if (t[i].tag == .semicolon) {
                i += 1;
                continue;
            }
            var end = i;
            while (end < t.len and t[end].tag != .semicolon and t[end].tag != .eof) end += 1;
            if (end == t.len or t[end].tag != .semicolon) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected semicolon", .{});
            if (t[i].tag != .name) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected an interactive statement", .{});
            if (eq(t[i].text, "add") or eq(t[i].text, "delete")) {
                try self.edit(cx, t[i..end], eq(t[i].text, "add"));
            } else if (eq(t[i].text, "refit")) {
                if (end != i + 1) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG REFIT takes no arguments", .{});
                try self.refit(cx);
            } else if (eq(t[i].text, "print")) {
                if (end != i + 1) {
                    inline for (.{ "acov", "all", "cli", "clm", "collin", "collinoint", "corrb", "covb", "dw", "i", "influence", "p", "partial", "pcorr1", "pcorr2", "r", "scorr1", "scorr2", "seqb", "spec", "ss1", "ss2", "stb", "tol", "vif", "xpx", "anova", "modeldata" }) |name| {
                        if (eq(t[i + 1].text, name)) return proc.failGap(cx.diags, t[i + 1].line, "PROC REG PRINT {s} is not implemented", .{t[i + 1].text});
                    }
                    return cx.diags.fail(error.ParseError, t[i + 1].line, "PROC REG: invalid PRINT option {s}", .{t[i + 1].text});
                }
                const selected = try self.current(cx);
                if (self.other_models and selected.outest != null) return proc.failGap(cx.diags, t[i].line, "PROC REG: interactive OUTEST with multiple MODEL statements is not implemented", .{});
                try self.refit(cx);
                // Execute at this statement, not at the later RUN. Otherwise
                // PRINT; DELETE x; PRINT; RUN would lose the first result.
                try executePrepared(cx, out, selected, self.fitted);
            } else if (eq(t[i].text, "run") or eq(t[i].text, "quit")) {
                if (end != i + 1) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: invalid execution boundary", .{});
                if (eq(t[i].text, "quit")) {
                    for (t[end + 1 ..]) |tok| if (tok.tag != .semicolon and tok.tag != .eof) return cx.diags.fail(error.ParseError, tok.line, "PROC REG: statement after QUIT", .{});
                    return false;
                }
            } else {
                if (continuationKeyword(t[i].text)) return proc.failGap(cx.diags, t[i].line, "PROC REG: continuation {s} is not implemented", .{t[i].text});
                return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: invalid interactive statement {s}", .{t[i].text});
            }
            i = end + 1;
        }
        return true;
    }
};

test "REG input WHERE and observation options preserve source data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3, 4 }) |x| try ds.appendRow(&.{ .{ .num = x }, .{ .num = 2 * x } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc reg data=work.sample(where=(x>1) obs=2); model y=x; run;", &d));
    const selected = try select(cx, spec, spec.models[0], spec.ds.rows.items);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 1, 3 }, selected.x);
    try std.testing.expectEqual(@as(usize, 4), ds.rows.items.len);
    try std.testing.expectEqual(@as(f64, 1), ds.rows.items[0][0].num);
}

test "REG empty and all-excluded inputs report captured errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    const tokens = try @import("../lexer.zig").tokenize(a, "proc reg; model y=x; run;", &d);
    try std.testing.expectError(error.ExecError, run(cx, &out, tokens));
    try ds.appendRow(&.{ Value.missing, .{ .num = 1 } });
    try std.testing.expectError(error.ExecError, run(cx, &out, tokens));
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "REG default enabled graphics fail loudly and PLOTS NONE disables them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try lib.put("sample", &ds);
    var graphics = @import("graphics_svg.zig").Session{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    const lex = @import("../lexer.zig");
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc reg;model y=x;run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "default ODS graphics") != null);
    _ = try parse(cx, try lex.tokenize(a, "proc reg plots=none;model y=x;run;", &d));
}

test "REG default model labels count statements rather than response variables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "z" }) |n| _ = try ds.addColumn(n, .num);
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc reg;model y z=x;model x=y;run;", &d));
    for (spec.models, [_][]const u8{ "MODEL1", "MODEL1", "MODEL2" }) |model, label| try std.testing.expectEqualStrings(label, model.label);
}

test "REG TYPE column in WHERE is not a summary dataset TYPE option" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "type" }) |n| _ = try ds.addColumn(n, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 1 } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc reg data=sample(where=(type=1));model y=x;run;", &d));
    try std.testing.expectEqual(@as(usize, 1), spec.ds.rows.items.len);
}

test "STAT-COMMON-004 weighted listing identifies weight without changing observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 1 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 2 }, .{ .num = 1 } });
    try lib.put("sample", &ds);
    const toks = try @import("../lexer.zig").tokenize(a, "proc reg data=sample; model y=x; weight w; run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
    try std.testing.expect(!d.hasErrors());
    const heading = std.mem.indexOf(u8, out.items, "Weight: w") orelse return error.TestUnexpectedResult;
    const observations = std.mem.indexOf(u8, out.items, "Number of Observations Used 3") orelse return error.TestUnexpectedResult;
    const anova = std.mem.indexOf(u8, out.items, "Analysis of Variance") orelse return error.TestUnexpectedResult;
    try std.testing.expect(observations < heading and heading < anova);
}

test {
    _ = @import("reg_interactive_tests.zig");
    _ = @import("reg_persistence_tests.zig");
}
