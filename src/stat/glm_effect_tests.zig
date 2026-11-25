//! GLM003 effect structure tests. No parser, design, or renderer implementation.
//! S154 physical pp.4066–4067,4092–4096,4107–4110. Computational contrasts are
//! checked against the documented model space, not claimed as GLM SOLUTION columns.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
const glm = @import("glm.zig");
const A = std.mem.Allocator;
fn parse(cx: proc.ProcCtx, source: []const u8) !glm.Spec {
    return glm.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, source, cx.diags));
}
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design {
    const view = try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    return glm.design.build(cx, spec, view, spec.responses[0]);
}
fn close(expected: f64, actual: f64, n: usize, p: usize) !void {
    // Two-pass projections use O(np²) multiply/add operations. 32np² bounds
    // the small fit's compensated dot/update work. These balanced contrast
    // Gram matrices have infinity condition number 3, computed independently.
    const u = std.math.floatEps(f64) / 2;
    const ku = @as(f64, @floatFromInt(32 * n * p * p)) * u;
    try std.testing.expectApproxEqAbs(expected, actual, 3 * ku / (1 - ku) * @max(1, @abs(expected)));
}

test "GLM003 three-level contrast space and reference-order invariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("C", .char);
    _ = try ds.addColumn("y", .num);
    for ([_][]const u8{ "C", "C", "A", "A", "B", "B" }, [_]f64{ 8, 10, 1, 3, 4, 6 }) |c, y| try ds.appendRow(&.{ .{ .str = c }, .{ .num = y } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const data_spec = try parse(cx, "proc glm order=data; class C; model y=C; run;");
    const internal_spec = try parse(cx, "proc glm order=internal; class C; model y=C; run;");
    const data = try design(cx, data_spec);
    const internal = try design(cx, internal_spec);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, -1, -1, 1, -1, -1 }, data.x);
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, -1, 1, -1, -1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1 }, internal.x);
    try std.testing.expectEqual(@as(usize, 2), data.effects[0].len);
    // Recover the three documented indicator columns exactly from the
    // contrast basis: D1=(1+2c1-c2)/3, D2=(1-c1+2c2)/3, D3=(1-c1-c2)/3.
    for (0..data.n) |i| {
        const c1 = data.x[i * data.p + 1];
        const c2 = data.x[i * data.p + 2];
        const indicators = [_]f64{ (1 + 2 * c1 - c2) / 3, (1 - c1 + 2 * c2) / 3, (1 - c1 - c2) / 3 };
        for (indicators, 0..) |value, j| try std.testing.expectEqual(@as(f64, if (i / 2 == j) 1 else 0), value);
    }
    var first = try glm.fitDesign(cx, data_spec, data);
    defer first.deinit(a);
    var second = try glm.fitDesign(cx, internal_spec, internal);
    defer second.deinit(a);
    for ([_]f64{ 9, 9, 2, 2, 5, 5 }, first.model.fit.fitted, second.model.fit.fitted) |expected, left, right| {
        try close(expected, left, 6, 3);
        try close(expected, right, 6, 3);
    }
    try std.testing.expectEqual(@as(usize, 3), first.model.fit.rank);
    try std.testing.expectEqual(@as(usize, 3), first.model.fit.df_error);
    try close(6, first.model.fit.sse, 6, 3);
    try close(148.0 / 3.0, first.type_iii[0].ss, 6, 3);
    try close(first.type_iii[0].ss, second.type_iii[0].ss, 6, 3);
}

test "GLM003 two-by-three interaction columns and independent balanced ANOVA" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    const means = [_]f64{ 1, 3, 4, 8, 9, 11 };
    for (means, 0..) |mean, cell| for ([_]f64{ -1, 1 }) |delta| try ds.appendRow(&.{ .{ .str = if (cell < 3) "A1" else "A2" }, .{ .str = ([_][]const u8{ "B1", "B2", "B3" })[cell % 3] }, .{ .num = mean + delta } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; class A B; model y=A B A*B; run;");
    const matrix = try design(cx, spec);
    try std.testing.expectEqual(@as(usize, 6), matrix.p);
    for (matrix.effects, [_]usize{ 1, 2, 2 }, [_]usize{ 1, 2, 4 }) |effect, width, start| {
        try std.testing.expectEqual(width, effect.len);
        try std.testing.expectEqual(start, effect.start);
    }
    for (0..12) |i| {
        const ac: f64 = if (i < 6) 1 else -1;
        const blevel = (i / 2) % 3;
        const b1: f64 = if (blevel == 0) 1 else if (blevel == 2) -1 else 0;
        const b2: f64 = if (blevel == 1) 1 else if (blevel == 2) -1 else 0;
        try std.testing.expectEqualSlices(f64, &.{ 1, ac, b1, b2, ac * b1, ac * b2 }, matrix.x[i * 6 ..][0..6]);
    }
    var result = try glm.fitDesign(cx, spec, matrix);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 6), result.model.fit.rank);
    try std.testing.expectEqual(@as(usize, 6), result.model.fit.df_error);
    try close(12, result.model.fit.sse, 12, 6);
    // Marginal A means 8/3,28/3; B means 9/2,6,15/2; equal replication=2.
    for (result.type_i, result.type_iii, [_]f64{ 400.0 / 3.0, 18, 2.0 / 3.0 }, [_]usize{ 1, 2, 2 }) |sequential, partial, ss, df| {
        try std.testing.expectEqual(df, partial.df);
        try close(ss, sequential.ss, 12, 6);
        try close(ss, partial.ss, 12, 6);
    }
    for (result.model.fit.fitted, 0..) |value, i| try close(means[i / 2], value, 12, 6);
}

test "GLM003 numeric effect products preserve factors and MODEL order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = -2 }, .{ .num = 3 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 0.5 }, .{ .num = -4 }, .{ .num = 2 } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; model y=x z x*x x*z x*x*z; run;");
    const matrix = try design(cx, spec);
    try std.testing.expectEqual(@as(usize, 6), matrix.p);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1 }, spec.effects[4].variables);
    try std.testing.expectEqualStrings("x*x*z", spec.effects[4].name);
    try std.testing.expectEqualSlices(f64, &.{ 1, -2, 3, 4, -6, 12, 1, 0.5, -4, 0.25, -2, -1 }, matrix.x);
}

test "GLM003 unsupported reference nesting and empty-cell Type IV remain captured gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .str = "A1" }, .{ .str = "B1" }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .str = "A1" }, .{ .str = "B2" }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .str = "A2" }, .{ .str = "B1" }, .{ .num = 3 } });
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    defer diag.resetGap();
    for ([_][]const u8{
        "proc glm; class A(ref=first) B; model y=A B; run;",
        "proc glm; class A B; model y=A B(A); run;",
        "proc glm; class A B; model y=A|B(A); run;",
    }) |source| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, parse(cx, source));
        try std.testing.expect(diag.gapHit());
        try std.testing.expect(d.list.items[d.list.items.len - 1].line > 0);
    }
    const spec = try parse(cx, "proc glm; class A B; model y=A B A*B / ss4; run;");
    const matrix = try design(cx, spec);
    diag.resetGap();
    try std.testing.expectError(error.ParseError, glm.fitDesign(cx, spec, matrix));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "rank-deficient") != null);
}

test "GLM003 documented default singularity retains a pivot between 1e-9 and 1e-7" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 3, 5 }, 0..) |y, i| {
        const x: f64 = if (i < 2) -1 else 1;
        const v: f64 = if (i % 2 == 0) -1 else 1;
        try ds.appendRow(&.{ .{ .num = x }, .{ .num = x + 1e-4 * v }, .{ .num = y } });
    }
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; model y=x z; run;");
    // S154 physical p.4095: machine-dependent default approximately 1e-9.
    // The exact normalized pivot is 1e-8/(1+1e-8), above that default.
    try std.testing.expectEqual(@as(f64, 1e-9), spec.singular);
    const matrix = try design(cx, spec);
    var result = try glm.fitDesign(cx, spec, matrix);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), result.model.fit.rank);
    try std.testing.expectEqual(@as(usize, 1), result.model.fit.df_error);
    try std.testing.expect(!d.hasErrors());
}

test "GLM003 second MODEL is invalid input rather than an unsupported capability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    diag.resetGap();
    defer diag.resetGap();
    // Physical p.4092 explicitly permits only one MODEL per GLM procedure.
    try std.testing.expectError(error.ParseError, parse(cx, "proc glm; model y=x; model y=; run;"));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(!diag.gapHit());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expect(d.list.items[d.list.items.len - 1].line > 0);
}
