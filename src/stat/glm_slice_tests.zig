const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const glm = @import("glm.zig");
const lsmeans = @import("glm_lsmeans.zig");
const selection = @import("data_selection.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;
fn close(expected: f64, actual: f64) !void {
    const ku = 32 * 36 * 16 * 16 * (std.math.floatEps(f64) / 2);
    // Retained dummy-code normal matrix has norm100 and inverse norm4,
    // from the three-level indicator Gram matrices (norm5/inverse norm4).
    try t.expectApproxEqAbs(expected, actual, 400 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn parse(cx: proc.ProcCtx, text: []const u8) !glm.Spec { return glm.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, text, cx.diags)); }
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design { return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{ .weight = spec.weight, .frequency = spec.freq }), spec.responses[0]); }

test "GLM014 original simple-effects means and all sliced ANOVA fields match independent cells" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/glm/simple_effects.sas", "twoway", &.{ "A", "B", "Y" }, &.{}, 0);
    try t.expectEqual(@as(usize, 36), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("twoway", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B; lsmeans A*B / slice=B; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expectEqual(@as(usize, 3), table.slices.len);
    try close(899.0 / 50.0, fit.model.fit.sse);
    try close(899.0 / 1350.0, fit.model.fit.mse);
    const expected_means = [_]f64{ 10.875, 0.275, 0.275, 19.475, 0.175, -0.725, 29.625, 0.375, -0.5 };
    for (table.means, expected_means) |mean, expected| try close(expected, mean.inference.estimate.?);
    for (table.slices, [_]f64{ 105709.0 / 150.0, 2.0 / 25.0, 1321.0 / 600.0 }) |slice, expected_ss| {
        const r = slice.result;
        try t.expectEqual(@import("linear_hypothesis.zig").Status.estimable, r.status);
        try t.expectEqual(@as(usize, 2), r.rank);
        try close(27, r.denominator_df.?);
        try close(expected_ss, r.numerator_ss.?);
        const statistic = expected_ss / 2 / (899.0 / 1350.0);
        try close(statistic, r.f.?);
        // F(2,27) survival has this elementary form, independent of betaI.
        try close(std.math.pow(f64, 27 / (27 + 2 * statistic), 13.5), r.f_probability.?);
        try t.expectEqual(@as(usize, 2), slice.hypothesis.len);
    }
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expect(std.mem.endsWith(u8, output.items,
        "\nThe GLM Procedure\nLeast Squares Means\nA*B Effect Sliced by B for Y\n\nSum of\nB DF Squares Mean Square F Value Pr > F\n" ++
        "1 2 704.726667 352.363333 529.13 <.0001\n" ++
        "2 2 0.080000 0.040000 0.06 0.9418\n" ++
        "3 2 2.201667 1.100833 1.65 0.2103\n"));
    try t.expectEqualStrings("", try diagnostics.render());
}

test "GLM014 unbalanced slice uses actual covariance and full-model error DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    // Counts2,3 at B1 and3,2 at B2; full cell means are2,5,6,8.
    const rows = [_][3]f64{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 2, 1, 4 }, .{ 2, 1, 5 }, .{ 2, 1, 6 }, .{ 1, 2, 5 }, .{ 1, 2, 6 }, .{ 1, 2, 7 }, .{ 2, 2, 7 }, .{ 2, 2, 9 } };
    for (rows) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B; lsmeans A*B / slice=(B A); run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expectEqual(@as(usize, 4), table.slices.len);
    try close(8, fit.model.fit.sse);
    // B1 difference -3, unscaled variance1/2+1/3=5/6 => SS54/5.
    // B2 difference -2, same variance => SS24/5. Pool error over ALL cells:
    // DFE10-4=6 and MSE8/6, not the within-slice residual DF3.
    for (table.slices[0..2], [_]f64{ 54.0 / 5.0, 24.0 / 5.0 }) |slice, ss| {
        try close(6, slice.result.denominator_df.?);
        try t.expectEqual(@as(usize, 1), slice.result.rank);
        try close(ss, slice.result.numerator_ss.?);
        try close(ss / (4.0 / 3.0), slice.result.f.?);
    }
}

test "GLM014 slice empty comparisons retain missing inference and invalid targets are user errors" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 2, 1, 4 }, .{ 2, 1, 6 }, .{ 1, 2, 7 }, .{ 1, 2, 9 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B / ss1; lsmeans A*B / slice=B; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expectEqual(@as(usize, 2), table.slices.len);
    try t.expectEqual(@import("linear_hypothesis.zig").Status.zero_rank, table.slices[1].result.status);
    try t.expect(table.slices[1].result.f == null and table.slices[1].result.f_probability == null);
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, parse(cx, "proc glm; class A B; model Y=A B A*B; lsmeans A / slice=B; run;"));
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
}


test "GLM014 Scheffe uses finite F distribution and actual difference-family rank" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 0, 2, 3, 5, 6, 7, 8 }, [_]f64{ 1, 1, 2, 2, 3, 3, 3 }) |y, group| try ds.appendRow(&.{ .{ .num = group }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class group; model y=group; lsmeans group / pdiff adjust=scheffe cl; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expect(spec.lsmeans[0].scheffe);
    try t.expectEqual(@as(usize, 4), table.df_error);
    try close(1.5, fit.model.fit.mse);
    // Means1,4,7; difference-space rank2. First t²=6, so adjusted
    // F=3 with DF(2,4), upper tail(1+3/2)^-2=4/25.
    try close(-3, table.comparisons[0].inference.estimate.?);
    try close(4.0 / 25.0, table.comparisons[0].adjusted_p.?);
    try close(25.0 / 1681.0, table.comparisons[1].adjusted_p.?);
    const critical = @sqrt(4 * (1 / @sqrt(@as(f64, 0.05)) - 1));
    const radius = critical * @sqrt(@as(f64, 1.5));
    try close(-3 - radius, table.comparisons[0].limits.lower.?);
    try close(-3 + radius, table.comparisons[0].limits.upper.?);
    // Individual margins stay unadjusted: t4 upper-tail identity, not Scheffe.
    const z = (table.mean_limits[0].upper.? - 1) / table.means[0].inference.standard_error.?;
    const u = z / @sqrt(z * z + 4);
    try close(0.05, 1 - 1.5 * u + 0.5 * u * u * u);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expect(std.mem.indexOf(u8, output.items, "Adjustment for Multiple Comparisons: Scheffe") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "Difference Simultaneous 95%") != null);
}

test "GLM014 Scheffe retains nonestimable margins when their complete difference space is estimable" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "C", "Y" }) |name| _ = try ds.addColumn(name, .num);
    // C is aliased with B, but the A contrast is identified across every B.
    // Balanced margins over B(3 levels) and C(2 levels) disagree, making each
    // individual A margin Non-est. Their common nuisance part cancels.
    for (1..3) |av| for (1..4) |bv| for ([_]f64{ -1, 1 }) |noise| try ds.appendRow(&.{ .{ .num = @floatFromInt(av) }, .{ .num = @floatFromInt(bv) }, .{ .num = if (bv < 3) 1 else 2 }, .{ .num = 10 * @as(f64, @floatFromInt(av)) + 2 * @as(f64, @floatFromInt(bv)) + noise } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B C; model Y=A B C / ss1; lsmeans A / pdiff adjust=scheffe cl; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    for (table.means) |mean| try t.expectEqual(@import("glm_estimability.zig").Status.nonestimable, mean.inference.status);
    const comparison = table.comparisons[0];
    try t.expectEqual(@import("glm_estimability.zig").Status.estimable, comparison.inference.status);
    try close(-10, comparison.inference.estimate.?);
    try close(@sqrt(@as(f64, 0.5)), comparison.inference.standard_error.?);
    // Scheffe rank1 is exactly F(1,df)=t_df²; no k-based shortcut needed.
    try close(comparison.inference.p_value.?, comparison.adjusted_p.?);
    try t.expect(comparison.limits.lower != null and comparison.limits.upper != null);
    for (table.mean_limits) |interval| try t.expect(interval.lower == null and interval.upper == null);
}


test "GLM014 precision-weighted cell comparisons use weight sums and observation DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y", "w" }) |name| _ = try ds.addColumn(name, .num);
    for (1..3) |av| for (1..3) |bv| for (0..2) |rep| try ds.appendRow(&.{ .{ .num = @floatFromInt(av) }, .{ .num = @floatFromInt(bv) }, .{ .num = 2 * @as(f64, @floatFromInt(av - 1)) + 10 * @as(f64, @floatFromInt(bv - 1)) + 4 * @as(f64, @floatFromInt(rep)) }, .{ .num = if (rep == 0) 1 else 3 } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B; weight w; lsmeans A*B / slice=B; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const table = try lsmeans.computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    for (table.means, [_]f64{ 3, 13, 5, 15 }) |mean, expected| try close(expected, mean.inference.estimate.?);
    // Every cell has sumweights4 and weighted SSE12. N is8, not sumweights16:
    // pooled MSE48/(8-4)=12. Difference variance=MSE*(1/4+1/4)=6.
    try close(48, fit.model.fit.sse);
    try t.expectEqual(@as(usize, 4), fit.model.fit.df_error);
    for (table.slices) |slice| {
        try close(8, slice.result.numerator_ss.?); // difference²/(1/4+1/4)
        try close(4, slice.result.denominator_df.?);
        try close(2.0 / 3.0, slice.result.f.?);
        const u = 1 / @sqrt(@as(f64, 7)); // exact two-sided t4 tail
        try close(1 - 1.5 * u + 0.5 * u * u * u, slice.result.f_probability.?);
    }
}
