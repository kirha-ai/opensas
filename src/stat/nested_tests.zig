//! STAT-NESTED-001 permanent tests: PROC NESTED options, CLASS/VAR/BY roles,
//! missing values, level runs, the balanced closed form and loud boundaries,
//! asserted through the captured diagnostics reporter (no spawned process).
//! Data are invented (D-011); expected values are hand sums of squares that
//! also match a SAS 15.4 reference listing of the same data.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const nested = @import("nested.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// columns: 0 g (char), 1 a, 2 b, 3 y, 4 z
const Row = struct { g: []const u8, a: f64, b: f64, y: f64, z: f64 };
const sample = [_]Row{
    .{ .g = "p", .a = 1, .b = 1, .y = 3, .z = 1 }, .{ .g = "p", .a = 1, .b = 1, .y = 5, .z = 2 },
    .{ .g = "p", .a = 1, .b = 2, .y = 4, .z = 4 }, .{ .g = "p", .a = 1, .b = 2, .y = 8, .z = 3 },
    .{ .g = "p", .a = 2, .b = 1, .y = 6, .z = 5 }, .{ .g = "p", .a = 2, .b = 1, .y = 7, .z = 7 },
    .{ .g = "p", .a = 2, .b = 2, .y = 2, .z = 6 }, .{ .g = "p", .a = 2, .b = 2, .y = 4, .z = 9 },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const s = try a.create(Dataset);
        s.* = Dataset.init(a, "s");
        _ = try s.addColumn("g", .char);
        for ([_][]const u8{ "a", "b", "y", "z" }) |n| _ = try s.addColumn(n, .num);
        for (sample) |r| try s.appendRow(&.{ .{ .str = r.g }, .{ .num = r.a }, .{ .num = r.b }, .{ .num = r.y }, .{ .num = r.z } });
        try self.lib.put("s", s);
        diag.resetGap();
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn tokens(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !nested.Spec {
        return nested.parse(self.cx(), try self.tokens(source));
    }
    fn run(self: *Env, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try nested.run(self.cx(), &out, try self.tokens(source));
        return out.items;
    }
};

test "STAT-NESTED-001 PROC options, defaults and variable roles" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Defaults: most recent data set, no AOV, no TRUNCATE, VAR = numeric non-CLASS.
    const d = try e.parse("proc nested; class a b; run;");
    try expect(!d.aov and !d.truncate and !d.var_given);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, d.class);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4 }, d.vars);
    const x = try e.parse("proc nested data=s aov; class a b / truncate; var z; by g; run;");
    try expect(x.aov and x.truncate and x.var_given);
    try std.testing.expectEqualSlices(usize, &.{4}, x.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, x.by_cols);
    // Variable ranges in CLASS and VAR; last BY statement wins.
    const r = try e.parse("proc nested data=s; class a--b; var y--z; by g; by descending g; run;");
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, r.class);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4 }, r.vars);
    try expect(r.by_desc[0]);
}

test "STAT-NESTED-001 user errors fail with rc 1 and gaps with rc 2" {
    const user_cases = [_][]const u8{
        "proc nested data=s; var y; run;", // CLASS required
        "proc nested data=nosuch; class a; run;",
        "proc nested data=s; class a; var g; run;", // VAR must be numeric
        "proc nested data=s; class a b; var b; run;", // both roles
        "proc nested data=s; class a a; run;",
        "proc nested data=s; class q; run;",
        "proc nested data=s bogus; class a; run;",
        "proc nested data=s; class a / bogus; run;",
        "proc nested data=s; model y=a; run;",
        "proc nested data=s; class a b y z; run;", // no analysis variable
        "proc nested data=s; class a b; var y; freq z; run;", // FREQ is not a NESTED statement
        "proc nested data=s; class a b; var y; format q 3.; run;",
    };
    for (user_cases) |src| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        try std.testing.expectError(error.ParseError, e.run(src));
        try expect(!diag.gapHit());
    }
    const gap_cases = [_][]const u8{
        "proc nested data=s; class a b; run;", // two VAR variables without AOV: covariation
        "proc nested data=s; class a b; var y; label a='x'; run;",
        "proc nested data=s; class a b; var y; by g; class b; run;", // second CLASS
        "proc nested data=s(where=(y>2)); class a b; var y; run;", // unbalanced after WHERE
    };
    for (gap_cases) |src| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        try std.testing.expectError(error.ParseError, e.run(src));
        try expect(diag.gapHit());
    }
}

test "STAT-NESTED-001 levels are contiguous runs and balance is checked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = Value{ .num = 1 };
    const m = Value{ .num = 2 };
    // Keys (A,B): 1 1 / 1 2 / 2 1 / 2 2 / 1 1 -> A has 3 runs.
    const rows = [_][]const Value{ &.{ n, n }, &.{ n, m }, &.{ m, n }, &.{ m, m }, &.{ n, n } };
    const d = try nested.design(a, &rows);
    try std.testing.expectEqualSlices(usize, &.{ 3, 5 }, d.levels);
    try expect(!d.balanced);
    const d2 = try nested.design(a, rows[0..4]);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4 }, d2.levels);
    try expect(d2.balanced);
}

test "STAT-NESTED-001 balanced closed form matches hand sums of squares" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var keys: [8][]const Value = undefined;
    var y: [8]f64 = undefined;
    for (sample, 0..) |r, i| {
        keys[i] = try a.dupe(Value, &.{ .{ .num = r.a }, .{ .num = r.b } });
        y[i] = r.y;
    }
    const d = try nested.design(a, &keys);
    const r = try nested.anova(a, d, &y);
    // Hand: grand mean 4.875; A means 5, 4.75; B means 4, 6, 6.5, 3.
    try approx(@as(f64, 4.875), r.mean, 1e-12);
    try approx(@as(f64, 28.875), r.total_ss, 1e-12);
    try approx(@as(f64, 0.125), r.ss[0], 1e-12);
    try approx(@as(f64, 16.25), r.ss[1], 1e-12);
    try approx(@as(f64, 12.5), r.ss[2], 1e-12);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 4 }, r.df);
    try std.testing.expectEqualSlices(f64, &.{ 4, 2 }, r.coef);
    const x = try nested.derive(a, r);
    // s2_e = 3.125, s2_B = (8.125-3.125)/2 = 2.5, s2_A = (0.125-8.125)/4 = -2.
    try approx(@as(f64, 3.125), x.comp[2], 1e-12);
    try approx(@as(f64, 2.5), x.comp[1], 1e-12);
    try approx(@as(f64, -2), x.comp[0], 1e-12);
    // The negative component is excluded from the total.
    try approx(@as(f64, 5.625), x.total_comp, 1e-12);
    try approx(@as(f64, 0.125 / 8.125), x.f[0], 1e-12);
    try approx(@as(f64, 2.6), x.f[1], 1e-12);
    try approx(@as(f64, 0.125), x.se_mean, 1e-12);
    // Pr > F as printed by SAS: 0.9126 and 0.1890.
    try approx(@as(f64, 0.9126), x.p[0], 5e-5);
    try approx(@as(f64, 0.1890), x.p[1], 5e-5);
}

test "STAT-NESTED-001 missing CLASS or VAR values omit the observation" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = e.lib.find("s").?;
    // A fully missing extra replicate block keeps the design balanced.
    try s.appendRow(&.{ .{ .str = "p" }, .{ .num = 2 }, .{ .num = 2 }, .{ .num = nan }, .{ .num = 1 } });
    try s.appendRow(&.{ .{ .str = "p" }, .{ .num = nan }, .{ .num = 2 }, .{ .num = 4 }, .{ .num = 1 } });
    const out = try e.run("proc nested data=s; class a b; var y; run;");
    try expect(std.mem.indexOf(u8, out, "Total            7       28.875000") != null);
    try expect(std.mem.indexOf(u8, out, "a                1        0.125000       0.02    0.9126    b            0.125000       -2.000000      0.0000") != null);
}

test "STAT-NESTED-001 FORMAT groups CLASS levels and an empty data set lists nothing" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = e.lib.find("s").?;
    // a = 1.1/1.2 and 2.1/2.2 alternate; under format 1. they are levels 1 and 2.
    for (s.rows.items, 0..) |r, k| {
        const row: []Value = @constCast(r);
        row[1] = .{ .num = row[1].num + if (k % 2 == 0) @as(f64, 0.1) else 0.2 };
    }
    const out = try e.run("proc nested data=s; format a 1.; class a b; var y; run;");
    try expect(std.mem.indexOf(u8, out, "a                1        0.125000       0.02    0.9126    b            0.125000       -2.000000      0.0000") != null);
    // Unformatted, every raw a value starts a new run (8 levels of a), so b
    // has zero degrees of freedom: a loud gap.
    diag.resetGap();
    try std.testing.expectError(error.ParseError, e.run("proc nested data=s; class a b; var y; run;"));
    try expect(diag.gapHit());
    // An input data set without observations: no listing, no error.
    const empty = try e.arena.allocator().create(Dataset);
    empty.* = Dataset.init(e.arena.allocator(), "none");
    for ([_][]const u8{ "a", "y" }) |n| _ = try empty.addColumn(n, .num);
    try e.lib.put("none", empty);
    diag.resetGap();
    const none = try e.run("proc nested data=none; class a; var y; run;");
    try expectEqual(@as(usize, 0), none.len);
    try expect(!diag.gapHit());
}
