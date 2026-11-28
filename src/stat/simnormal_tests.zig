//! STAT-SIMNORMAL-001 unit tests. Expected values are SAS 9.4 output
//! (best16. dumps of RANNOR(54321) and PROC SIMNORMAL OUTSEED runs).
const std = @import("std");
const fns = @import("../functions.zig");

fn normal(state: *u64) f64 {
    const ua = fns.classicUniform(state);
    const ub = fns.classicUniform(state);
    return @sqrt(-2.0 * @log(ua)) * @cos(2.0 * std.math.pi * ub);
}

test "STAT-SIMNORMAL-001 classic normal stream and OUTSEED states match SAS 9.4" {
    // SAS 9.4: rannor(54321) x8 printed in best16.
    const want = [_]f64{ 0.53954455787141, 0.1515140630646, 1.05304516429687, 1.85220545878213, 0.53068241694995, 0.85303186627684, -1.6710145098835, 0.83212760433719 };
    var st: u64 = 54321;
    for (want) |w| try std.testing.expectApproxEqAbs(w, normal(&st), 5e-14);
    // SAS 9.4 OUTSEED (two VAR variables): 54321, 1704705799, 55996226, 366353659.
    st = 54321;
    const seeds = [_]u64{ 54321, 1704705799, 55996226, 366353659 };
    for (seeds) |sd| {
        try std.testing.expectEqual(sd, st);
        _ = normal(&st);
        _ = normal(&st);
    }
}

const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const simnormal = @import("simnormal.zig");

fn moments(a: std.mem.Allocator, lib: *Library, name: []const u8, ty: ?[]const u8, with_type: bool) !void {
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, name);
    d.ds_type = ty;
    if (with_type) _ = try d.addColumn("_TYPE_", .char);
    _ = try d.addColumn("_NAME_", .char);
    _ = try d.addColumn("x", .num);
    _ = try d.addColumn("y", .num);
    const pre: []const Value = if (with_type) &.{.{ .str = "COV" }} else &.{};
    for ([_][3]Value{ .{ .{ .str = "x" }, .{ .num = 1 }, .{ .num = 0 } }, .{ .{ .str = "y" }, .{ .num = 0 }, .{ .num = 1 } } }) |r| {
        var row: [4]Value = undefined;
        @memcpy(row[0..pre.len], pre);
        @memcpy(row[pre.len .. pre.len + 3], &r);
        try d.appendRow(row[0 .. pre.len + 3]);
    }
    try lib.put(name, d);
}

test "STAT-SIMNORMAL-001 unverified valid input is a loud gap and invalid input a user error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try moments(a, &lib, "cv", "COV", true);
    try moments(a, &lib, "uc", "UCOV", true);
    try moments(a, &lib, "plain", null, true);
    try moments(a, &lib, "notype", "COV", false);
    const cases = [_]struct { source: []const u8, rc: u8 }{
        // Valid SAS whose behaviour is not verified or owned by later tickets (rc 2).
        .{ .source = "proc simnormal data=uc out=o nr=1 seed=1; var x y; run;", .rc = 2 },
        .{ .source = "proc simnormal data=plain out=o nr=1 seed=1; var x y; run;", .rc = 2 },
        .{ .source = "proc simnormal data=notype out=o nr=1 seed=1; var x y; run;", .rc = 2 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=2147483647; var x y; run;", .rc = 2 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=1 sing1=1; var x y; run;", .rc = 2 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=1; var x; cond y; run;", .rc = 2 },
        // User errors with SAS 9.4 texts (rc 1).
        .{ .source = "proc simnormal data=cv out=o nr=-2 seed=1; var x y; run;", .rc = 1 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=1 sing2=3; var x y; run;", .rc = 1 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=1 bogus; var x y; run;", .rc = 1 },
        .{ .source = "proc simnormal data=cv out=o nr=1 seed=1; var x zz; run;", .rc = 1 },
        .{ .source = "proc simnormal data=nosuch out=o nr=1 seed=1; var x; run;", .rc = 1 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = simnormal.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        std.testing.expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try std.testing.expectEqual(@as(usize, 0), output.items.len);
        try std.testing.expect(lib.find("o") == null);
    }
}

test "STAT-SIMNORMAL-001 identity moments give the raw stream, Rnum and the SAS layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try moments(a, &lib, "cv", "COV", true);
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    try simnormal.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, "proc simnorm data=cv outsim=o numr=2 seed=54321 outseed; var x y; run;", &d));
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(usize, 2), o.rows.items.len);
    const names = [_][]const u8{ "x", "y", "Rnum", "Seed" };
    for (names, o.columns.items) |n, c| try std.testing.expectEqualStrings(n, c.name);
    // Identity covariance and no MEAN row: Y = W (SAS 9.4 RANNOR(54321) values).
    try std.testing.expectApproxEqAbs(@as(f64, 0.53954455787141), o.rows.items[0][0].num, 5e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1.85220545878213), o.rows.items[1][1].num, 5e-14);
    try std.testing.expectEqual(@as(f64, 2), o.rows.items[1][2].num);
    try std.testing.expectEqual(@as(f64, 1704705799), o.rows.items[1][3].num);
}
