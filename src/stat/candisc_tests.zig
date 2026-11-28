//! STAT-CANDISC-001 unit tests (see candisc.zig). Expected values are the
//! SAS 9.4 reference listings recorded in tests/corpus/stat_candisc_*.txt;
//! nothing here is regenerated from opensas output.
const std = @import("std");
const candisc = @import("candisc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;

fn plants(a: std.mem.Allocator) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "plants");
    _ = try ds.addColumn("grp", .char);
    for ([_][]const u8{ "x1", "x2", "x3" }) |n| _ = try ds.addColumn(n, .num);
    const rows = [_]struct { []const u8, [3]f64 }{
        .{ "A", .{ 2.1, 3.5, 1.0 } }, .{ "A", .{ 2.5, 3.1, 1.4 } }, .{ "A", .{ 1.9, 3.9, 0.8 } }, .{ "A", .{ 2.8, 3.3, 1.9 } },
        .{ "B", .{ 3.9, 2.2, 2.5 } }, .{ "B", .{ 4.4, 2.0, 2.9 } }, .{ "B", .{ 3.6, 2.9, 2.1 } }, .{ "B", .{ 4.1, 2.4, 3.3 } },
        .{ "C", .{ 5.2, 4.1, 1.2 } }, .{ "C", .{ 5.9, 4.6, 0.7 } }, .{ "C", .{ 6.3, 3.8, 1.6 } }, .{ "C", .{ 5.5, 4.9, 1.1 } },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1][0] }, .{ .num = r[1][1] }, .{ .num = r[1][2] } });
    return ds;
}

test "STAT-CANDISC-001 roots, Wilks' lambda and signed raw coefficients match the SAS listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try plants(a);
    const s: candisc.Spec = .{ .ds = ds, .class = 0, .vars = &.{ 1, 2, 3 } };
    const r = try candisc.analyze(a, s, ds.rows.items);
    try std.testing.expectEqual(@as(usize, 3), r.levels.len);
    try std.testing.expectEqual(@as(usize, 2), r.ncomp);
    // SAS (stat_candisc_basic.txt): eigenvalues 45.1789, 2.9626; Wilks 0.00546487.
    try std.testing.expectApproxEqAbs(@as(f64, 45.1789), r.roots[0], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 2.9626), r.roots[1], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00546487), r.stats.statistics[0].value, 5e-9);
    // SAS Raw Canonical Coefficients, including the sign of Can2.
    const raw = [_]f64{ 3.362471466, 1.801616389, -1.225215890, -0.681785803, 0.899617600, -1.058153100 };
    for (raw, r.raw[0..6]) |want, got| try std.testing.expectApproxEqAbs(want, got, 5e-9);
}

test "STAT-CANDISC-001 roles: CLASS required, FREQ numeric, first CLASS statement wins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try lib.put("plants", try plants(a));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try std.testing.expectError(error.ParseError, candisc.parse(cx, try lex.tokenize(a, "proc candisc data=plants; var x1 x2; run;", &d)));
    try std.testing.expectError(error.ParseError, candisc.parse(cx, try lex.tokenize(a, "proc candisc data=plants; class grp; var x1; freq grp; run;", &d)));
    try std.testing.expect(d.hasErrors());
    const s = try candisc.parse(cx, try lex.tokenize(a, "proc candisc data=plants; class grp; class x3; var x1 x2; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), s.class);
    try std.testing.expectEqual(@as(usize, 2), s.vars.len);
    // Without VAR: every numeric variable not named elsewhere.
    const all = try candisc.parse(cx, try lex.tokenize(a, "proc candisc data=plants; class grp; run;", &d));
    try std.testing.expectEqual(@as(usize, 3), all.vars.len);
}
