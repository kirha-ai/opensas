const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const hov = @import("glm_hov.zig");
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    const ku = 4096 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 32 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn data(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design {
    return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{}), spec.responses[0]);
}
fn source(cx: proc.ProcCtx, text: []const u8) !glm.Spec { return glm.parse(cx, try lex.tokenize(cx.arena, text, cx.diags)); }
fn sample(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "group", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (1..4) |g| for (0..3) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(g) }, .{ .num = @floatFromInt(g * i) } });
    try lib.put("sample", ds);
    return ds;
}

test "GLM007 HOVTEST dispersion and F inference agree with independent rational ANOVAs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const options = [_][]const u8{ "hovtest", "hovtest=levene(type=square)", "hovtest=levene(type=abs)", "hovtest=bf", "hovtest=obrien", "hovtest=obrien(w=0)" };
    const expected_ss = [_]f64{ 392.0 / 9.0, 392.0 / 9.0, 8.0 / 3.0, 8.0 / 3.0, 98, 98 };
    const expected_sse = [_]f64{ 196.0 / 3.0, 196.0 / 3.0, 28.0 / 3.0, 28.0 / 3.0, 1323.0 / 4.0, 147 };
    const expected_f = [_]f64{ 2, 2, 6.0 / 7.0, 6.0 / 7.0, 8.0 / 9.0, 2 };
    const test_names = [_][]const u8{ "Levene's", "Levene's", "Levene's", "Brown and Forsythe's", "O'Brien's", "O'Brien's" };
    const transformations = [_][]const u8{ "Squared Deviations from Group Means", "Squared Deviations from Group Means", "Absolute Deviations from Group Means", "Absolute Deviations from Group Medians", "Transformed Deviations", "Transformed Deviations" };
    const rows = [_][]const u8{
        "group 2 43.55555556 21.77777778 2.00 0.2160\nError 6 65.33333333 10.88888889\n",
        "group 2 43.55555556 21.77777778 2.00 0.2160\nError 6 65.33333333 10.88888889\n",
        "group 2 2.66666667 1.33333333 0.86 0.4705\nError 6 9.33333333 1.55555556\n",
        "group 2 2.66666667 1.33333333 0.86 0.4705\nError 6 9.33333333 1.55555556\n",
        "group 2 98.00000000 49.00000000 0.89 0.4591\nError 6 330.75000000 55.12500000\n",
        "group 2 98.00000000 49.00000000 2.00 0.2160\nError 6 147.00000000 24.50000000\n",
    };
    // For F(2,6), survival is (1+F/3)^-3. O'Brien's transformed group
    // means are exactly sample variances 1,4,9 for both W=.5 and W=0.
    for (options, 0..) |option, index| {
        const program = try std.fmt.allocPrint(a, "proc glm; class group; model y=group; means group / {s}; run;", .{option});
        const spec = try source(cx, program);
        const d = try data(cx, spec);
        const result = try hov.compute(cx, spec, d);
        try t.expectEqualSlices(usize, &.{ 3, 3, 3 }, result.counts);
        try t.expectEqualSlices(f64, &.{ 1, 2, 3 }, result.means);
        for ([_]f64{ 1, 2, 3 }, result.standard_deviations) |sd, actual| try close(sd, actual);
        try t.expectEqual(@as(usize, 2), result.df);
        try t.expectEqual(@as(usize, 6), result.df_error);
        try close(expected_ss[index], result.ss);
        try close(expected_sse[index], result.sse);
        try close(expected_f[index], result.f_value);
        const base = 1 + expected_f[index] / 3;
        try close(1 / (base * base * base), result.p_value);
        var output: std.ArrayList(u8) = .empty;
        try glm.execute(cx, &output, spec);
        // All HOV table fields and companion descriptives are checked, not
        // only a heading or selected statistic. Rows above round the exact
        // rational quantities and elementary F tails, never CLI-generated data.
        const expected_tail = try std.fmt.allocPrint(a,
            "\nThe GLM Procedure\n{s} Test for Homogeneity of y Variance\nANOVA of {s}\n\nSum of Mean\nSource DF Squares Square F Value Pr > F\n{s}" ++
            "\nThe GLM Procedure\n\nLevel of group N y Mean Std Dev\n" ++
            "1 3 1.0000000 1.0000000\n2 3 2.0000000 2.0000000\n3 3 3.0000000 3.0000000\n",
            .{ test_names[index], transformations[index], rows[index] });
        try t.expect(std.mem.endsWith(u8, output.items, expected_tail));
    }
    try t.expectEqualStrings("", try diagnostics.render());
}

test "GLM007 Brown Forsythe uses group medians and excludes missing responses" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 0, 0, 9, 0, 3, 9 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 3 + 1) }, .{ .num = y } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = std.math.nan(f64) } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try source(cx, "proc glm; class group; model y=group; means group / hovtest=bf; run;");
    const d = try data(cx, spec);
    const result = try hov.compute(cx, spec, d);
    try t.expectEqualSlices(f64, &.{ 0, 0, 9, 3, 0, 6 }, result.dispersion);
    try t.expectEqualSlices(usize, &.{ 3, 3 }, result.counts);
    try close(0, result.ss);
    try close(72, result.sse);
    try close(0, result.f_value);
    try close(1, result.p_value);
    try t.expectEqual(@as(usize, 4), result.df_error);
}

test "GLM007 Levene matches complete public UPSIT data and published table precision" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/glm/upsit_hov.sas", "upsit", &.{ "agegroup", "smell" }, &.{}, 0);
    try t.expectEqual(@as(usize, 180), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("upsit", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try source(cx, "proc glm; class agegroup; model smell=agegroup; means agegroup / hovtest; run;");
    const result = try hov.compute(cx, spec, try data(cx, spec));
    try t.expectEqualSlices(usize, &.{ 38, 36, 21, 43, 42 }, result.counts);
    try t.expectEqual(@as(usize, 4), result.df);
    try t.expectEqual(@as(usize, 175), result.df_error);
    // S154 physical p.4216, Output53.10.2. Bounds are half a displayed unit.
    try t.expectApproxEqAbs(@as(f64, 0.0799), result.ss, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 0.0200), result.ms, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 0.5503), result.sse, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 0.00314), result.mse, 0.000005);
    try t.expectApproxEqAbs(@as(f64, 6.35), result.f_value, 0.005);
    try t.expect(result.p_value < 0.0001);
}

test "GLM007 unsupported HOV domains retain captured diagnostics and no fake inference" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "hovtest welch" }) |option| {
        diag.resetGap();
        defer diag.resetGap();
        const program = try std.fmt.allocPrint(a, "proc glm; class group; model y=group; means group / {s}; run;", .{option});
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, program, &diagnostics)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expectEqual(@as(usize, 0), output.items.len);
    }
    for (ds.rows.items) |*observation| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[1] = .{ .num = 0 };
        observation.* = cells;
    }
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class group; model y=group; means group / hovtest; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expectEqual(@as(usize, 0), output.items.len);
}

test "GLM007 Bartlett corrected likelihood ratio matches independent log identity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try source(cx, "proc glm; class group; model y=group; means group / hovtest=bartlett; run;");
    const result = try hov.compute(cx, spec, try data(cx, spec));
    // Equal group N=3, sample variances 1,4,9: pooled=14/3 and correction=11/9.
    // For two chi-square DF the survival is exactly exp(-T/2).
    const statistic = (9.0 / 11.0) * (6 * @log(@as(f64, 14.0 / 3.0)) - 2 * @log(@as(f64, 36)));
    try close(statistic, result.chi_square.?);
    try close(@exp(-statistic / 2), result.p_value);
    try t.expectEqual(@as(usize, 2), result.df);
    try t.expect(std.math.isNan(result.f_value) and std.math.isNan(result.ss));
    try t.expectEqual(@as(usize, 0), result.dispersion.len);
    var listing: std.ArrayList(u8) = .empty;
    try hov.render(cx, &listing, spec, try data(cx, spec), result);
    try t.expectEqualStrings(
        "\nThe GLM Procedure\nBartlett's Test for Homogeneity of y Variance\n\nSource DF Chi-Square Pr > ChiSq\ngroup 2 1.6982 0.4278\n" ++
        "\nThe GLM Procedure\n\nLevel of group N y Mean Std Dev\n" ++
        "1 3 1.0000000 1.0000000\n2 3 2.0000000 2.0000000\n3 3 3.0000000 3.0000000\n", listing.items);
    // Equal positive group variances give exactly a null statistic. A location
    // change cannot affect the likelihood ratio.
    for (ds.rows.items, 0..) |*observation, index| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[1] = .{ .num = @floatFromInt(index % 3 + (index / 3) * 10) };
        observation.* = cells;
    }
    const equal = try hov.compute(cx, spec, try data(cx, spec));
    try close(0, equal.chi_square.?);
    try close(1, equal.p_value);
    for (ds.rows.items[0..3]) |*observation| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[1] = .{ .num = 0 };
        observation.* = cells;
    }
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.execute(cx, &output, spec));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expectEqual(@as(usize, 0), output.items.len);
}
