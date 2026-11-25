const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
const parsing = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const glm = @import("glm.zig");
const A = std.mem.Allocator;
fn parsed(cx: proc.ProcCtx, source: []const u8) !parsing.Spec {
    return parsing.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, source, cx.diags));
}
fn input(a: A, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("A", .char);
    for ([_][]const u8{ "x", "y1", "y2", "w", "f" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("id", .char);
    const rows = [_][5]f64{
        .{ 1, 10, std.math.nan(f64), 1, 2.9 }, .{ 2, std.math.nan(f64), 20, 2, 1 },
        .{ 3, 30, 40, 0, 1 },                  .{ std.math.nan(f64), 50, 60, 1, 1 },
        .{ 5, 70, 80, 1, 1 },                  .{ 6, 90, 100, 1, 0.9 },
        .{ 7, 110, 120, 1, 1 },
    };
    for (rows, 0..) |row, i| try ds.appendRow(&.{ .{ .str = if (i == 4) " " else if (i % 2 == 0) "A1" else "A2" }, .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] }, .{ .num = row[4] }, .{ .str = " " } });
    try lib.put("sample", ds);
    return ds;
}
fn view(a: A, spec: parsing.Spec) !selection.View {
    return selection.View.init(a, spec.input, .{ .by = spec.by, .frequency = spec.freq, .weight = spec.weight, .id = spec.ids });
}

test "GLM001 defaults explicit options and located invalid or unsupported declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try input(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const defaults = try parsed(cx, "proc glm; model y1=x; run;");
    try std.testing.expectEqual(@as(f64, 0.05), defaults.alpha);
    try std.testing.expectEqual(parsing.Order.formatted, defaults.order);
    try std.testing.expectEqual(@as(usize, 20), defaults.namelen);
    const explicit = try parsed(cx, "proc glm alpha=.1 namelen=32 order=data manova multipass noprint plots=none; class A; id id; freq f; weight w; model y1 y2=A x; run; weight absent; by absent; quit;");
    try std.testing.expect(explicit.manova and explicit.multipass and explicit.noprint and explicit.plots_none);
    try std.testing.expectEqual(@as(f64, 0.1), explicit.alpha);
    try std.testing.expectEqual(@as(?usize, 4), explicit.weight);
    for ([_][]const u8{ "proc glm alpha=2; model y1=x; run;", "proc glm namelen=19; model y1=x; run;", "proc glm order=wrong; model y1=x; run;", "proc glm; model y1=A; run;", "proc glm; model y1=x; class A; run;", "proc glm; model y1 x; run;" }) |source| {
        try std.testing.expectError(error.ParseError, parsed(cx, source));
        try std.testing.expect(d.list.items[d.list.items.len - 1].line > 0);
    }
    try std.testing.expectError(error.ParseError, parsed(cx, "proc glm outstat=x; model y1=x; run;"));
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "not implemented") != null);
}

test "GLM001 response-specific missingness MANOVA FREQ WEIGHT and original observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try input(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var spec = try parsed(cx, "proc glm; class A; model y1 y2=A x; freq f; weight w; id id; run;");
    const observations = try view(a, spec);
    const first = try design.build(cx, spec, observations, spec.responses[0]);
    const second = try design.build(cx, spec, observations, spec.responses[1]);
    try std.testing.expectEqualSlices(usize, &.{ 1, 7 }, first.source_rows);
    try std.testing.expectEqualSlices(usize, &.{ 2, 7 }, second.source_rows);
    try std.testing.expectEqualSlices(f64, &.{ 2, 1 }, first.frequencies);
    try std.testing.expectEqualSlices(f64, &.{ 2, 1 }, second.weights);
    try std.testing.expectEqual(@as(usize, 7), first.read);
    spec.manova = true;
    const listwise = try design.build(cx, spec, observations, spec.responses[0]);
    try std.testing.expectEqualSlices(usize, &.{7}, listwise.source_rows);
    try std.testing.expectEqual(@as(usize, 7), ds.rows.items.len);
    try std.testing.expectEqual(@as(f64, 2.9), ds.rows.items[0][5].num);
    try std.testing.expectEqualStrings(" ", first.observations[0].cells[6].str);
}

test "GLM001 unbalanced factorial contrast design and independent Type I III counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "exp");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("Y", .num);
    for ([_]f64{ 12, 14, 11, 9, 20, 18, 17 }, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 4) "A1" else "A2" }, .{ .str = if (i < 2 or (i >= 4 and i < 6)) "B1" else "B2" }, .{ .num = y } });
    try lib.put("exp", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parsed(cx, "proc glm data=exp; class A B; model Y=A B A*B; run;");
    const x = try design.build(cx, spec, try view(a, spec), spec.responses[0]);
    try std.testing.expectEqual(@as(usize, 7), x.n);
    try std.testing.expectEqual(@as(usize, 4), x.p);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 1, 1 }, x.x[0..4]);
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, -1, 1 }, x.x[24..28]);
    var result = try glm.fitDesign(cx, spec, x);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), result.model.fit.rank);
    try std.testing.expectEqual(@as(usize, 3), result.model.fit.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 6), result.model.fit.sse, 1e-12);
    // Cell means 13,10,19,17 and sample sizes 2,2,2,1 give the equal-cell
    // marginal hypotheses A:6.5, B:-2.5, interaction:0.5; SSE=6, MSE=2.
    for (result.type_i, [_]f64{ 1681.0 / 21.0, 169.0 / 15.0, 0.4 }) |test_value, expected| try std.testing.expectApproxEqAbs(expected, test_value.ss, 1e-10);
    for (result.type_iii, [_]f64{ 67.6, 10, 0.4 }) |test_value, expected| {
        try std.testing.expectEqual(@as(usize, 1), test_value.df);
        try std.testing.expectApproxEqAbs(expected, test_value.ss, 1e-10);
    }
}

test "GLM001 BY groups response counts and raw source provenance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "x", "y" }) |n| _ = try ds.addColumn(n, .num);
    for (0..6) |i| try ds.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = @floatFromInt(i % 3) }, .{ .num = @floatFromInt(1 + 2 * i) } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parsed(cx, "proc glm; by g; model y=x; run;");
    const input_view = try view(a, spec);
    const groups = try input_view.groups(a, spec.descending, spec.notsorted, &d);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    for (groups, 0..) |group, j| {
        const data = try design.build(cx, spec, group, spec.responses[0]);
        try std.testing.expectEqual(@as(usize, 3), data.n);
        try std.testing.expectEqual(1 + 3 * j, data.source_rows[0]);
    }
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = 4 }, .{ .num = 9 } });
    const bad = try view(a, spec);
    try std.testing.expectError(error.ParseError, bad.groups(a, spec.descending, false, &d));
    const notsorted = try bad.groups(a, spec.descending, true, &d);
    try std.testing.expectEqual(@as(usize, 3), notsorted.len);
}

test "GLM001 FREQ WEIGHT and NOINT use distinct counts and model degrees of freedom" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "w", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 2 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y }, .{ .num = if (i == 1) 2 else 1 }, .{ .num = if (i == 1) 2.9 else 1 } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parsed(cx, "proc glm; model y=x; freq f; weight w; run;");
    const data = try design.build(cx, spec, try view(a, spec), spec.responses[0]);
    var result = try glm.fitDesign(cx, spec, data);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), data.n);
    try std.testing.expectEqual(@as(usize, 4), result.model.fit.n_used);
    try std.testing.expectEqual(@as(usize, 2), result.model.fit.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.model.fit.sse, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), result.model.fit.coefficients[0], 1e-12);
    const noint = try parsed(cx, "proc glm; model y=x / noint; run;");
    const origin = try design.build(cx, noint, try view(a, noint), noint.responses[0]);
    var zero = try glm.fitDesign(cx, noint, origin);
    defer zero.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), zero.model.fit.rank);
}

test "GLM001 graphics curve confidence bands follow independent Cauchy inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 2 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parsed(cx, "proc glm; model y=x; run;");
    const data = try design.build(cx, spec, try view(a, spec), spec.responses[0]);
    var result = try glm.fitDesign(cx, spec, data);
    defer result.deinit(a);
    const plots = @import("glm_plots.zig");
    const curve = try plots.curve(a, spec, data, result);
    try std.testing.expectEqual(@as(usize, 101), curve.len);
    const critical: f64 = 1.0 / @tan(@as(f64, std.math.pi) * 0.025);
    const mean = 7.0 / 6.0;
    try std.testing.expectApproxEqAbs(mean, curve[0].predicted, 1e-12);
    try std.testing.expectApproxEqAbs(mean - critical * @sqrt(5.0 / 36.0), curve[0].lower_mean, 1e-9);
    try std.testing.expectApproxEqAbs(mean + critical * @sqrt(11.0 / 36.0), curve[0].upper_individual, 1e-9);
    const bytes = try plots.fitSvg(a, spec, data, result, "Quoted <title>");
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, bytes, "data-kind=\"observed\""));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Quoted &lt;title&gt;") != null);
}

test "GLM001 empty observations and unsupported categorical hypotheses are loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "empty");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try lib.put("empty", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var output: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ExecError, glm.run(cx, &output, try @import("../lexer.zig").tokenize(a, "proc glm; model y=x; run;", &d)));
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = 1 }, .{ .num = 2 } });
    const spec = try parsed(cx, "proc glm; class A; model y=A*x; run;");
    try std.testing.expectError(error.ParseError, design.build(cx, spec, try view(a, spec), spec.responses[0]));
    try std.testing.expect(d.hasErrors());
}

test {
    _ = @import("glm_effect_tests.zig");
}
