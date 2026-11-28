const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const lsmeans = @import("glm_lsmeans.zig");
const at = @import("glm_lsmeans_at.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    const ku = 16384 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 128 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn parse(cx: proc.ProcCtx, text: []const u8) !glm.Spec { return glm.parse(cx, try lex.tokenize(cx.arena, text, cx.diags)); }
fn view(cx: proc.ProcCtx, spec: glm.Spec) !selection.View { return selection.View.init(cx.arena, spec.input, .{ .by = spec.by, .frequency = spec.freq, .weight = spec.weight }); }
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design { return glm.design.build(cx, spec, try view(cx, spec), spec.responses[0]); }

test "GLM015 AT means replace mean products and explicit values affect every covariate product" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (0..2) |g| for ([_][2]f64{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 2, 2 } }, 0..) |point, i| {
        const residual: f64 = (if (g == 0) @as(f64, 1) else -1) * (if (i % 2 == 0) @as(f64, 1) else -1);
        try ds.appendRow(&.{ .{ .num = @floatFromInt(g) }, .{ .num = point[0] }, .{ .num = point[1] }, .{ .num = 1 + 3 * @as(f64, @floatFromInt(g)) + 2 * point[0] + 4 * point[1] + 5 * point[0] * point[1] + residual } });
    };
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class g; model y=g x z x*z; lsmeans g; lsmeans g / at means; lsmeans g / at x=1.2; lsmeans g / at (x z)=(1.2 .3); lsmeans g / om bylevel at x=100; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    // xbar=zbar=3/4, mean(xz)=1; AT MEANS uses9/16, not1.
    const expected = [_][3]f64{ .{ 0.75, 0.75, 1 }, .{ 0.75, 0.75, 0.5625 }, .{ 1.2, 0.75, 0.9 }, .{ 1.2, 0.3, 0.36 }, .{ 0.75, 0.75, 1 } };
    for (spec.lsmeans, expected, [_]f64{ 10.5, 8.3125, 10.9, 6.4, 10.5 }) |request, coefficients, first_mean| {
        const table = try lsmeans.computeWithFit(cx, spec, d, request, fit);
        for (table.means, 0..) |mean, index| {
            for (coefficients, 3..) |coefficient, column| try close(coefficient, mean.coefficients[column]);
            try close(first_mean + 3 * @as(f64, @floatFromInt(index)), mean.inference.estimate.?);
        }
    }
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, output.items, "Least Squares Means"));
    try t.expectEqualStrings("", try diagnostics.render());
}

test "GLM015 AT uses precision weights and missing-response rows only within formatted observed cells" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    ds.columns.items[0].format = "1.";
    for ([_]f64{ 1.1, 2.1 }, [_]f64{ 1, 5 }) |g, intercept| for ([_]f64{ -1, 0, 1 }, [_]f64{ 1, 1, 2 }, [_]f64{ 1, -2, 0.5 }) |x, w, residual| try ds.appendRow(&.{ .{ .num = g }, .{ .num = x }, .{ .num = intercept + 2 * x + residual }, .{ .num = w } });
    const nan = std.math.nan(f64);
    try ds.appendRow(&.{ .{ .num = 1.4 }, .{ .num = 4 }, .{ .num = nan }, .{ .num = 2 } }); // formatted group1, retained
    try ds.appendRow(&.{ .{ .num = 3.2 }, .{ .num = 100 }, .{ .num = nan }, .{ .num = 100 } }); // all-missing group3, excluded
    try ds.appendRow(&.{ .{ .num = 1.1 }, .{ .num = nan }, .{ .num = 99 }, .{ .num = 1 } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class g; model y=g x; weight w; lsmeans g / stderr; lsmeans g / at means stderr cl; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try t.expectEqual(@as(usize, 9), d.input_observations.len);
    try t.expectEqual(@as(usize, 6), d.n);
    try t.expectEqual(@as(usize, 3), fit.model.fit.df_error);
    try close(11.0 / 3.0, fit.model.fit.mse);
    const population = try at.compute(cx, spec, d, spec.lsmeans[1].at.?);
    try t.expectEqual(@as(usize, 7), population.population_rows);
    try close(10, population.total_weight);
    try close(1, population.values[1]); // (fit weighted sum2 + missing row8)/10
    const standard = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    const adjusted = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[1], fit);
    for (standard.means, adjusted.means, [_]f64{ 1, 5 }) |before, after, intercept| {
        try close(0, before.coefficients[3]); // default ignores precision weighting
        try close(1, after.coefficients[3]);
        try close(intercept, before.inference.estimate.?);
        try close(intercept + 2, after.inference.estimate.?);
        try close(@sqrt(@as(f64, 23.0 / 24.0)), before.inference.standard_error.?);
        try close(@sqrt(@as(f64, 31.0 / 24.0)), after.inference.standard_error.?);
    }
    const z = (adjusted.mean_limits[0].upper.? - 3) / adjusted.means[0].inference.standard_error.?;
    const u = z / @sqrt(@as(f64, 3));
    try close(0.05, 1 - 2.0 / std.math.pi * (std.math.atan(u) + u / (1 + u * u))); // independent t3 tail
}

test "GLM015 AT excludes missing CLASS combinations even when each level is observed elsewhere" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 1, 0, 14 }, .{ 1, 1, 1, 14 }, .{ 1, 2, 0, 15 }, .{ 1, 2, 1, 19 }, .{ 2, 1, 0, 23 }, .{ 2, 1, 1, 25 }, .{ 1, 1, 3, std.math.nan(f64) }, .{ 2, 2, 100, std.math.nan(f64) } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] }, .{ .num = values[2] }, .{ .num = values[3] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model y=A B x; lsmeans A / at means; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    for (table.means, [_]f64{ 227.0 / 14.0, 367.0 / 14.0 }) |mean, expected| {
        try close(6.0 / 7.0, mean.coefficients[5]);
        try close(expected, mean.inference.estimate.?);
    }
    try t.expectEqual(@as(usize, 2), table.df_error);
}

test "GLM015 AT population is confined to each actual NOTSORTED BY slice" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "batch", "g", "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 1 }, [_]f64{ 0, 10, 20 }) |batch, offset| {
        for (0..2) |g| for (0..2) |i| {
            const x = offset + 2 * @as(f64, @floatFromInt(i));
            const residual: f64 = if (g == i) 1 else -1;
            try ds.appendRow(&.{ .{ .num = batch }, .{ .num = @floatFromInt(g) }, .{ .num = x }, .{ .num = 1 + 4 * @as(f64, @floatFromInt(g)) + 2 * x + residual } });
        };
        try ds.appendRow(&.{ .{ .num = batch }, .{ .num = 0 }, .{ .num = offset + 8 }, .{ .num = std.math.nan(f64) } });
    }
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; by batch notsorted; class g; model y=g x; lsmeans g / at means; run;");
    const groups = try (try view(cx, spec)).groups(a, spec.descending, spec.notsorted, &diagnostics);
    try t.expectEqual(@as(usize, 3), groups.len);
    for (groups, [_]f64{ 0, 10, 20 }) |group, offset| {
        const d = try glm.design.build(cx, spec, group, spec.responses[0]);
        const population = try at.compute(cx, spec, d, spec.lsmeans[0].at.?);
        try t.expectEqual(@as(usize, 5), population.population_rows);
        try close(offset + 12.0 / 5.0, population.values[2]);
    }
}

test "GLM015 AT invalid assignments and unproved response domains remain explicit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "y", "z" }) |name| _ = try ds.addColumn(name, .num);
    for (0..6) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 3) }, .{ .num = @floatFromInt(i % 3) }, .{ .num = @floatFromInt(i) }, .{ .num = @floatFromInt(i * i) } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "at g=1", "at z=1", "at (x x)=(1 2)", "at (x)=(1 2)", "at x=." }) |option| {
        diag.resetGap();
        defer diag.resetGap();
        const text = try std.fmt.allocPrint(a, "proc glm; class g; model y=g x; lsmeans g / {s}; run;", .{option});
        try t.expectError(error.ParseError, parse(cx, text));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    }
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class g; model y z=g x; lsmeans g / at means; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
}


test "GLM015 OM and BYLEVEL use global and conditional observed CLASS margins" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "y", "w", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 1, 2, 6 }, .{ 2, 1, 10 }, .{ 2, 2, 12 }, .{ 2, 2, 14 }, .{ 2, 2, 16 }, .{ 2, 2, 18 } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] }, .{ .num = values[2] }, .{ .num = 1 }, .{ .num = 1 } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model y=A B A*B; lsmeans A; lsmeans A / om stderr; lsmeans A / om bylevel stderr; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const balanced = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    const observed = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[1], fit);
    const within = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[2], fit);
    for (balanced.means, [_]f64{ 4, 12.5 }) |mean, expected| try close(expected, mean.inference.estimate.?);
    for (observed.means, [_]f64{ 4.5, 13.125 }, [_]f64{ 649.0 / 256.0, 671.0 / 512.0 }) |mean, expected, variance| {
        try close(expected, mean.inference.estimate.?);
        try close(@sqrt(variance), mean.inference.standard_error.?);
        try close(3.0 / 8.0, mean.coefficients[3]);
        try close(5.0 / 8.0, mean.coefficients[4]);
    }
    for (within.means, [_]f64{ 10.0 / 3.0, 14 }, [_]f64{ 11.0 / 6.0, 11.0 / 10.0 }) |mean, expected, variance| {
        try close(expected, mean.inference.estimate.?);
        try close(@sqrt(variance), mean.inference.standard_error.?);
    }
    // Missing dependent values still contribute observed margins, with the
    // precision weight and truncated FREQ. They do not change model fitting DF.
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = std.math.nan(f64) }, .{ .num = 4 }, .{ .num = 2.9 } });
    const weighted = try parse(cx, "proc glm; class A B; model y=A B A*B; weight w; freq f; lsmeans A / obsmargins stderr; run;");
    const wd = try design(cx, weighted);
    var wf = try glm.fitDesign(cx, weighted, wd);
    defer wf.deinit(a);
    const wt = try lsmeans.computeWithFit(cx, weighted, wd, weighted.lsmeans[0], wf);
    try t.expectEqual(@as(usize, 8), wd.n);
    try t.expectEqual(@as(usize, 4), wt.df_error);
    for (wt.means, [_]f64{ 21.0 / 4.0, 225.0 / 16.0 }) |mean, expected| {
        try close(expected, mean.inference.estimate.?);
        try close(3.0 / 16.0, mean.coefficients[3]);
        try close(13.0 / 16.0, mean.coefficients[4]);
    }
    try close(@sqrt(@as(f64, 3817.0 / 1024.0)), wt.means[0].inference.standard_error.?);
}

test "GLM015 observed margins preserve nonestimability and BYLEVEL can restore an estimable target" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 1, 2, 7 }, .{ 2, 1, 9 }, .{ 2, 1, 11 } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] }, .{ .num = values[2] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model y=A B A*B / ss1; lsmeans A; lsmeans A / om; lsmeans A / om bylevel stderr; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const standard = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    const observed = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[1], fit);
    const conditional = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[2], fit);
    try t.expectEqual(@import("glm_estimability.zig").Status.nonestimable, standard.means[1].inference.status);
    try t.expectEqual(@import("glm_estimability.zig").Status.nonestimable, observed.means[1].inference.status);
    try t.expect(observed.means[1].inference.estimate == null and observed.means[1].inference.standard_error == null);
    try t.expectEqual(@import("glm_estimability.zig").Status.estimable, conditional.means[1].inference.status);
    try close(10, conditional.means[1].inference.estimate.?);
    try close(1, conditional.means[1].inference.standard_error.?);
    try close(1, conditional.means[1].coefficients[3]);
    try close(0, conditional.means[1].coefficients[4]);
}

// S154 physical4146–4147: conditional margins use precision weights and
// FREQ multiplicity; AT is disabled. Weighted within-group residuals below
// sum to zero and are orthogonal to x, hence the raw mean and its variance
// MSE/sum(FREQ*WEIGHT) are independent closed-form checks.
test "GLM015 weighted conditional covariate means retain frequency DF and ignore AT" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "y", "w", "f" }) |name| _ = try ds.addColumn(name, .num);
    for (0..2) |group| for ([_]f64{ -1, 0, 1 }, [_]f64{ 1, 1, 2 }, [_]f64{ 1, -2, 0.5 }) |delta, weight, residual| {
        const g: f64 = @floatFromInt(group);
        const x = 10 * g + delta;
        try ds.appendRow(&.{ .{ .num = g }, .{ .num = x }, .{ .num = 1 + 4 * g + 2 * x + residual }, .{ .num = weight }, .{ .num = 2.9 } });
    };
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class g; model y=g x; weight w; freq f; lsmeans g / om bylevel at x=100 stderr; lsmeans g / at means; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expectEqual(@as(usize, 9), table.df_error);
    try close(22.0 / 9.0, fit.model.fit.mse);
    for (table.means, [_]f64{ 0.25, 10.25 }, [_]f64{ 1.5, 25.5 }) |mean, x, expected| {
        try close(x, mean.coefficients[3]);
        try close(expected, mean.inference.estimate.?);
        try close(@sqrt(@as(f64, 11.0 / 36.0)), mean.inference.standard_error.?);
    }
    const covariates = try at.compute(cx, spec, d, spec.lsmeans[1].at.?);
    try close(16, covariates.total_weight);
    try close(5.25, covariates.values[1]);
    try t.expectEqualStrings("", try diagnostics.render());
}

test "GLM015 unproved observed-population domains emit captured gaps" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |new_level| {
        var ds = Dataset.init(a, "sample");
        for ([_][]const u8{ "g", "x", "y" }) |name| _ = try ds.addColumn(name, .num);
        for (0..2) |g| for (0..3) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(g) }, .{ .num = @floatFromInt(i) }, .{ .num = @floatFromInt(g * 4 + i * i) } });
        try ds.appendRow(&.{ .{ .num = if (new_level) 2 else 0 }, .{ .num = 4 }, .{ .num = std.math.nan(f64) } });
        var lib = Library.init(a);
        try lib.put("sample", &ds);
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        diag.resetGap();
        defer diag.resetGap();
        const spec = try parse(cx, "proc glm; class g; model y=g x; lsmeans g / om bylevel; run;");
        const d = try design(cx, spec);
        var fit = try glm.fitDesign(cx, spec, d);
        defer fit.deinit(a);
        try t.expectError(error.ParseError, lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit));
        const message = if (new_level) "PROC GLM: observed margins with new unfitted CLASS levels are not implemented" else "PROC GLM: BYLEVEL covariate sampling with missing responses is not implemented";
        try t.expectEqualStrings(try std.fmt.allocPrint(a, "ERROR: {s}\n", .{message}), try diagnostics.render());
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    }
}
