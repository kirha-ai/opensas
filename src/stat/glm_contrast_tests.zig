const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const contrast = @import("glm_contrast.zig");
const kernel = @import("linear_hypothesis.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    const ku = 8192 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 64 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn design(cx: proc.ProcCtx, spec: glm.Spec, response: usize) !glm.design.Design {
    return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{}), response);
}

test "GLM011 multirow CONTRAST uses actual covariance and dependent row rank" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 3, 3, 7, 5, 9 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 2 + 1) }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class group; model y=group; contrast 'joint' group 1 0 -1, group 0 1 -1; contrast 'redundant' group 1 0 -1, group 0 1 -1, group 2 0 -2; contrast 'not estimable' group 1; run;", &diagnostics));
    const d = try design(cx, spec, spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const tables = try contrast.compute(cx, spec, d, fit.model.fit.mse, fit.model.fit.df_error);
    try t.expectEqual(@as(usize, 3), tables.len);
    // Means2,5,7; two contrasts(-5,-2), G_L=[[1,.5],[.5,1]].
    // SS=76/3; residual SS18 with DF3, hence MSE6 and F19/9.
    for (tables[0..2]) |table| {
        try t.expectEqual(kernel.Status.estimable, table.result.status);
        try t.expectEqual(@as(usize, 2), table.result.rank);
        try close(76.0 / 3.0, table.result.numerator_ss.?);
        try close(19.0 / 9.0, table.result.f.?);
        const ratio: f64 = 27.0 / 65.0;
        try close(ratio * @sqrt(ratio), table.result.f_probability.?);
        try close(3, table.result.denominator_df.?);
    }
    try t.expectEqual(kernel.Status.nonestimable, tables[2].result.status);
    try t.expect(tables[2].result.numerator_ss == null and tables[2].result.f == null and tables[2].result.f_probability == null);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expect(std.mem.indexOf(u8, output.items, "Contrast DF Contrast SS Mean Square F Value Pr > F") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "joint 2 25.33333333 12.66666667 2.11 0.2677") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "not estimable 0 Non-est . . .") != null);
}

test "GLM011 original formatted INPUT and all five univariate contrast quantities persist" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try @import("glm_persistence_tests.zig").read(a, "tests/fixtures/stat/glm/pottery_formatted.sas");
    const body_start = std.mem.indexOf(u8, source, "input Site").?;
    var lib = Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    var pdv = @import("../pdv.zig").Pdv.init(a);
    var evaluator: @import("../eval.zig").Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diagnostics };
    var executor = @import("../exec.zig").Executor.init(a, &pdv, &diagnostics, &evaluator, &lib);
    var ds = Dataset.init(a, "pottery");
    try executor.run(try @import("../parser.zig").parse(a, source[body_start..], &diagnostics), &ds);
    try lib.put("pottery", &ds);
    try t.expectEqual(@as(usize, 26), ds.rows.items.len);
    try t.expectEqualStrings("Llanederyn 1", std.mem.trimEnd(u8, ds.rows.items[0][0].str, " "));
    try close(4.4, ds.rows.items[0][1].num);
    try t.expectEqualStrings("Caldicot 11.", std.mem.trimEnd(u8, ds.rows.items[14][0].str, " "));
    try close(8, ds.rows.items[14][1].num);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm data=pottery manova; class Site; model Al Fe Mg Ca Na=Site; contrast 'Llanederyn vs. the rest' Site 1 1 1 -3; run;", &diagnostics));
    // All printed original univariate Contrast SS values, with bounds equal
    // to half a last displayed decimal unit. Input is NOT whitespace-normalized.
    const expected = [_]f64{ 785.2555886, 71.15144132, 56.59349339, 0.03531688, 0.23344446 };
    for (spec.responses, expected, 0..) |response, reference, index| {
        const d = try design(cx, spec, response);
        var fit = try glm.fitDesign(cx, spec, d);
        defer fit.deinit(a);
        const tables = try contrast.compute(cx, spec, d, fit.model.fit.mse, fit.model.fit.df_error);
        try t.expectEqual(@as(usize, 22), fit.model.fit.df_error);
        try t.expectEqual(@as(usize, 1), tables[0].result.rank);
        try t.expectApproxEqAbs(reference, tables[0].result.numerator_ss.?, @as(f64, if (index == 0) 0.00000005 else 0.000000005));
        try close(tables[0].result.numerator_ss.? / fit.model.fit.mse, tables[0].result.f.?);
    }
    try t.expect(!diagnostics.hasErrors());
}

test "GLM011 generalized eigenpairs preserve E normalization and H V equals E V Lambda" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = [_]f64{ 4, 0, 0, 0, 9, 0, 0, 0, 16 };
    // Whitened H=[[2,1,0],[1,2,0],[0,0,0]], exact roots3,1,0.
    const h = [_]f64{ 8, 6, 0, 6, 18, 0, 0, 0, 0 };
    const pair = try @import("reg_mtest.zig").characteristic(a, &e, &h, 3);
    for ([_]f64{ 3, 1, 0 }, pair.roots) |expected, actual| try close(expected, actual);
    for (0..3) |i| for (0..3) |j| {
        var gram: f64 = 0;
        for (0..3) |r| for (0..3) |s| { gram += pair.vectors[r * 3 + i] * e[r * 3 + s] * pair.vectors[s * 3 + j]; };
        try close(if (i == j) @as(f64, 1) else 0, gram);
        var hv: f64 = 0;
        var ev: f64 = 0;
        for (0..3) |k| { hv += h[i * 3 + k] * pair.vectors[k * 3 + j]; ev += e[i * 3 + k] * pair.vectors[k * 3 + j]; }
        try close(hv, ev * pair.roots[j]);
    };
    // Repeated roots have no unique sign/basis: assert all invariant fields,
    // not arbitrary sample-specific vector coordinates.
    const repeated = try @import("reg_mtest.zig").characteristic(a, &e, &e, 3);
    for (repeated.roots) |root| try close(1, root);
    try t.expectError(error.ExecError, @import("reg_mtest.zig").characteristic(a, &.{ 1, 0, 0, 0 }, &.{ 1, 0, 0, 1 }, 2));
}

test "GLM011 unsupported CONTRAST output and invalid rows stay explicit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 3, 2, 5 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; model y=x; contrast 'slope' x 1 / e; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    diag.resetGap();
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; model y=x; contrast 'empty' x 1,; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
}
