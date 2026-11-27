//! REG010: actual PRINT matrices and session TEST, independent fixed designs.
const std = @import("std");
const reg = @import("reg.zig");
const test_statement = @import("reg_test.zig");
const h = @import("linear_hypothesis.zig");
const ranks = @import("reg_diagnostics.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;
const A = std.mem.Allocator;
const x = [_]f64{ 1, -2, -1, 1, -1, -2, 1, 1, 2, 1, 2, 1 };
const y = [_]f64{ 6, 8, 10, 16 };
fn close(want: f64, got: f64) !void {
    try std.testing.expectApproxEqAbs(want, got, 1e-12 * @max(1, @abs(want)));
}
fn setup(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (y, 0..) |response, i| try ds.appendRow(&.{ .{ .num = x[3 * i + 1] }, .{ .num = x[3 * i + 2] }, .{ .num = response } });
    try lib.put("sample", ds);
}
fn run(a: A, lib: *Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var listing: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &listing, try lex.tokenize(a, source, d));
    return listing.items;
}
test "REG010 PRINT contains actual covariance inverse and both bordered vectors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = try ranks.fit(a, &x, &y, 4, 3, null, true, 1e-9);
    const geometry = h.fromRegression(model, 1e-9);
    const rows = [_]h.Row{ .{ .coefficients = &.{ 0, 1, 0 } }, .{ .coefficients = &.{ 0, 0, 1 } } };
    const printed = try test_statement.intermediate(a, geometry, &rows);
    try std.testing.expectEqual(@as(usize, 2), printed.dimension);
    for (printed.covariance, [_]f64{ 5.0 / 18.0, -2.0 / 9.0, -2.0 / 9.0, 5.0 / 18.0 }) |got, want| try close(want, got);
    for (printed.inverse, [_]f64{ 10, 8, 8, 10 }) |got, want| try close(want, got);
    for (printed.difference, [_]f64{ 3, -1 }) |got, want| try close(want, got);
    for (printed.solution, [_]f64{ 22, 14 }) |got, want| try close(want, got);
    for (0..2) |i| for (0..2) |j| {
        var product: f64 = 0;
        for (0..2) |k| product += printed.covariance[i * 2 + k] * printed.inverse[k * 2 + j];
        try close(if (i == j) 1 else 0, product);
    };
    var quadratic: f64 = 0;
    for (printed.difference, printed.solution) |d, v| quadratic += d * v;
    try close((try h.evaluate(a, geometry, &rows, null)).numerator_ss.?, quadratic);
    const changed = try test_statement.intermediate(a, geometry, &.{ .{ .coefficients = &.{ 0, 1000, 0 } }, .{ .coefficients = &.{ 0, 0, 0.001 } } });
    try close(0.022, changed.solution[0]);
    try close(14000, changed.solution[1]);
    const affine = try test_statement.intermediate(a, geometry, &.{.{ .coefficients = &.{ 0, 2, -3 }, .rhs = 5 }});
    try close(113.0 / 18.0, affine.covariance[0]);
    try close(4, affine.difference[0]);
    try close(18.0 / 113.0, affine.inverse[0]);
    try close(72.0 / 113.0, affine.solution[0]);
}

test "REG010 TEST PRINT respects NOPRINT and malformed option combinations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const listing = try run(a, &lib, &d, "proc reg data=sample; model y=x z; test x,z / print; run;");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "\nTestCov\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "\nInvTestCov\n"));
    try std.testing.expect(std.mem.indexOf(u8, listing, "Row Col1 Col2 Lb-c") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Row Col1 Col2 InvCov*(Lb-c)") != null);
    try std.testing.expectEqual(@as(usize, 0), (try run(a, &lib, &d, "proc reg data=sample noprint; model y=x z; test x,z / print; run;")).len);
    for ([_][]const u8{ "proc reg data=sample; model y=x z; test x / print nonsense; run;", "proc reg data=sample; model y=x z; test x / ; run;", "proc reg data=sample; model y=x z; test x / chisq; run;" }) |source| {
        var errors = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &errors, source));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), errors.hasErrors()));
    }
    var errors = diag.Diagnostics.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &errors, "proc reg data=sample; model y=x z; test x,2*x / print; run;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), errors.hasErrors()));
}

test "REG010 interactive labeled TEST refits current ADD model and does not repeat on RUN" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=sample; var z; model y=x; run;", &d)) };
    var listing: std.ArrayList(u8) = .empty;
    try std.testing.expect(try session.continuation(cx, &listing, try lex.tokenize(a, "first: test x; add z; second: test x,z / print; run;", &d)));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing.items, "Test first Results"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing.items, "Test second Results"));
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Numerator 1 48.40000 12.74 0.0703") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Numerator 2 26.00000 6.50 0.2673") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Model: MODEL1.1") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, listing.items, "Analysis of Variance"));
    try std.testing.expectEqual(@as(?usize, 3), session.next_test_number);
    const before = listing.items.len;
    try std.testing.expectError(error.ParseError, session.continuation(cx, &listing, try lex.tokenize(a, "test unknown;", &d)));
    try std.testing.expectEqual(before, listing.items.len);
    try std.testing.expectEqual(@as(?usize, 3), session.next_test_number);
    try std.testing.expect(!try session.continuation(cx, &listing, try lex.tokenize(a, "quit;", &d)));
}

test "REG010 continuation admission and BY boundary use captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    try std.testing.expect(reg.continuationStart(try lex.tokenize(a, "label: test x;", &d)));
    try std.testing.expect(reg.continuationStart(try lex.tokenize(a, "test x;", &d)));
    try std.testing.expect(!reg.continuationStart(try lex.tokenize(a, "label: data sample;", &d)));
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=sample; by z; model y=x; run;", &d)) };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, session.continuation(cx, &out, try lex.tokenize(a, "test x;", &d)));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "REG010 estimable aliased TEST remains valid while nonestimability and zero variance stay loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "alias");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ -1, 0, 1, 2 }, [_]f64{ 1, 2, 4, 4 }) |v, response| try ds.appendRow(&.{ .{ .num = v }, .{ .num = 2 * v }, .{ .num = response } });
    try lib.put("alias", ds);
    const listing = try run(a, &lib, &d, "proc reg data=alias; model y=x z; test x+2*z / print; run;");
    try std.testing.expect(std.mem.indexOf(u8, listing, "Numerator 1 6.05000 17.29 0.0533") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "InvTestCov") != null);
    var errors = diag.Diagnostics.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &errors, "proc reg data=alias; model y=x z; test x; run;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), errors.hasErrors()));
    try std.testing.expect(std.mem.indexOf(u8, errors.list.items[errors.list.items.len - 1].message, "nonestimable") != null);
    const constant = try a.create(Dataset);
    constant.* = Dataset.init(a, "constant");
    _ = try constant.addColumn("x", .num);
    _ = try constant.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3, 4 }) |v| try constant.appendRow(&.{ .{ .num = v }, .{ .num = 5 } });
    try lib.put("constant", constant);
    var constant_errors = diag.Diagnostics.init(a);
    diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &constant_errors, "proc reg data=constant; model y=x; test x; run;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), constant_errors.hasErrors()));
    try std.testing.expect(std.mem.indexOf(u8, constant_errors.list.items[constant_errors.list.items.len - 1].message, "residual variance") != null);
}

test "REG010 TEST syntax diagnostics identify TEST without changing RESTRICT grammar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &d, "proc reg data=sample; model y=x z; test unknown; run;"));
    try std.testing.expect(std.mem.startsWith(u8, d.list.items[d.list.items.len - 1].message, "PROC REG TEST:"));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    var r = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, run(a, &lib, &r, "proc reg data=sample; model y=x z; restrict unknown; run;"));
    try std.testing.expect(std.mem.startsWith(u8, r.list.items[r.list.items.len - 1].message, "PROC REG RESTRICT:"));
}
