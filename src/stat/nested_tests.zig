//! STAT-NESTED-001/-002 permanent tests: PROC NESTED options, CLASS/VAR/BY roles,
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
        "proc nested data=s; class q; run;",
        "proc nested data=s bogus; class a; run;",
        "proc nested data=s; class a / bogus; run;",
        "proc nested data=s; model y=a; run;",
        "proc nested data=s; class a b y z; run;", // no analysis variable
        "proc nested data=s; class a b; var y; freq z; run;", // FREQ is not a NESTED statement
        "proc nested data=s; class a b; var y; format q 3.; run;",
        "proc nested data=s; by descending a; class b; var y; run;", // BY not sorted (SAS ERROR, no listing)
    };
    for (user_cases) |src| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        try std.testing.expectError(error.ParseError, e.run(src));
        try expect(!diag.gapHit());
    }
    const gap_cases = [_][]const u8{
        "proc nested data=s; class a a; var y; run;", // repeated CLASS variable: zero-df factor (STAT-NESTED-004)
        "proc nested data=s; class a b; var y; by g; class b; run;", // CLASS a b b
        "proc nested data=s; class a b; var y; attrib y transcode=no; run;",
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

test "STAT-NESTED-001 repeated CLASS/VAR statements, LABEL, ATTRIB, all-missing groups" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Several CLASS and VAR statements concatenate (SAS 15.4 reference run).
    const c = try e.parse("proc nested data=s aov; class a; class b; var y; var z y; run;");
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, c.class);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 3 }, c.vars);
    // A numeric BY variable stays in the default VAR list.
    const b = try e.parse("proc nested data=s; by a; class b; run;");
    try std.testing.expectEqualSlices(usize, &.{ 1, 3, 4 }, b.vars);
    // LABEL / ATTRIB LABEL= / ATTRIB FORMAT= leave the listing unchanged;
    // an unknown LABEL variable is a WARNING (status rc 1, as the SAS run).
    const row = "a                1        0.125000       0.02    0.9126    b            0.125000       -2.000000      0.0000";
    const l = try e.run("proc nested data=s; class a b; var y; label y='Yield' q='x'; attrib a label='A' format=8.2; run;");
    try expect(std.mem.indexOf(u8, l, row) != null);
    try expect(!diag.gapHit());
    try expect(e.diags.warning_status);
    // Unquoted LABEL text, ATTRIB LENGTH=/INFORMAT= and an unknown ATTRIB
    // variable (WARNING) are accepted, as in the SAS reference run; TRUNCATE
    // on a later CLASS statement applies to every CLASS variable.
    const u = try e.run("proc nested data=s; class a; class b / truncate; var y; label y=Yield of plot b=Bee; attrib y length=8 informat=best12. q label='x'; run;");
    try expect(std.mem.indexOf(u8, u, row) != null);
    try expect((try e.parse("proc nested data=s; class a; class b / truncate; var y; run;")).truncate);
    // VAR y y under AOV: the analysis is listed twice.
    const twice = try e.run("proc nested data=s aov; class a b; var y y; run;");
    try expectEqual(@as(usize, 2), std.mem.count(u8, twice, "Analysis of Variance for Variable y"));
    // All observations missing: a WARNING (status rc 1) and no listing.
    const s0 = e.lib.find("s").?;
    for (s0.rows.items) |r| @constCast(r)[3] = .{ .num = nan };
    const none = try e.run("proc nested data=s; class a b; var y; run;");
    try expectEqual(@as(usize, 0), none.len);
    try expect(!diag.gapHit());
    try expect(!e.diags.hasErrors());
}

test "STAT-NESTED-002 three-stage balanced variance components match a hand calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Batch(2) / Sample(2) / Assay(2), 2 replicates each (invented data).
    const ys = [_]f64{ 10, 12, 11, 15, 14, 13, 18, 16, 20, 17, 19, 22, 15, 16, 21, 18 };
    var keys: [16][]const Value = undefined;
    for (0..16) |i| keys[i] = try a.dupe(Value, &.{
        .{ .num = @floatFromInt(i / 8 + 1) }, .{ .num = @floatFromInt(i / 4 % 2 + 1) }, .{ .num = @floatFromInt(i / 2 % 2 + 1) },
    });
    const d = try nested.design(a, &keys);
    try expect(d.balanced);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4, 8 }, d.levels);
    const r = try nested.anova(a, d, &ys);
    try expectEqual(@as(usize, 16), r.n);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 4, 8 }, r.df);
    // Diagonal EMS coefficients = observations per level of each factor.
    try std.testing.expectEqualSlices(f64, &.{ 8, 4, 2 }, r.coef);
    // Hand: grand mean 257/16; batch means 14.125, 18; sample means 12, 15.25,
    // 19.5, 17.5; assay means 11, 13, 13.5, 17, 18.5, 20.5, 15.5, 19.5.
    try approx(@as(f64, 16.0625), r.mean, 1e-12);
    try approx(@as(f64, 186.9375), r.total_ss, 1e-10);
    try approx(@as(f64, 95.0625), r.ss[0], 1e-10);
    try approx(@as(f64, 29.125), r.ss[1], 1e-10);
    try approx(@as(f64, 36.25), r.ss[2], 1e-10);
    try approx(@as(f64, 26.5), r.ss[3], 1e-10);
    const x = try nested.derive(a, r);
    try approx(@as(f64, 3.3125), x.comp[3], 1e-12);
    try approx(@as(f64, (9.0625 - 3.3125) / 2.0), x.comp[2], 1e-12);
    try approx(@as(f64, (14.5625 - 9.0625) / 4.0), x.comp[1], 1e-12);
    try approx(@as(f64, (95.0625 - 14.5625) / 8.0), x.comp[0], 1e-12);
    try approx(@as(f64, 17.625), x.total_comp, 1e-12);
    try approx(@as(f64, 2.4375), x.se_mean, 1e-12);
    // F(1,2) upper tail in closed form: 1 - sqrt(x), x = F/(F+2).
    const f0: f64 = 95.0625 / 14.5625;
    try approx(f0, x.f[0], 1e-12);
    try approx(1 - @sqrt(f0 / (f0 + 2)), x.p[0], 1e-9);
    // F(2,4) upper tail in closed form: (1 + 2F/4)^-2.
    const f1: f64 = 14.5625 / 9.0625;
    try approx(1 / ((1 + f1 / 2) * (1 + f1 / 2)), x.p[1], 1e-9);
    // F(4,8): x = F/(F+2), tail = sum_{j<2} C(5,j) x^j (1-x)^(5-j).
    const f2: f64 = 9.0625 / 3.3125;
    const xb = f2 / (f2 + 2);
    try approx(std.math.pow(f64, 1 - xb, 5) + 5 * xb * std.math.pow(f64, 1 - xb, 4), x.p[2], 1e-9);
}

test "STAT-NESTED-002 listing precision conventions of the default analysis" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const out = try e.run("proc nested data=s; class a b; var y; run;");
    // SS / mean square / component 6 decimals, F 2, Pr > F and percent 4,
    // mean and its standard error 8 (SAS 15.4 reference listings).
    try expect(std.mem.indexOf(u8, out, "Total            7       28.875000                                      4.125000        5.625000    100.0000") != null);
    try expect(std.mem.indexOf(u8, out, "b                2       16.250000       2.60    0.1890    Error        8.125000        2.500000     44.4444") != null);
    try expect(std.mem.indexOf(u8, out, "y Mean                          4.87500000") != null);
    try expect(std.mem.indexOf(u8, out, "Standard Error of y Mean        0.12500000") != null);
}

test "STAT-NESTED-003 unbalanced EMS coefficients and components match a hand calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A(3) / B within A with cell sizes 2,3 | 3,1 | 2,2,2 (invented data).
    const ab = [_][2]f64{ .{ 1, 1 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 2 }, .{ 1, 2 }, .{ 2, 1 }, .{ 2, 1 }, .{ 2, 1 }, .{ 2, 2 }, .{ 3, 1 }, .{ 3, 1 }, .{ 3, 2 }, .{ 3, 2 }, .{ 3, 3 }, .{ 3, 3 } };
    const ys = [_]f64{ 3, 5, 4, 6, 8, 7, 9, 8, 2, 6, 4, 5, 7, 9, 6 };
    var keys: [15][]const Value = undefined;
    for (ab, 0..) |x, i| keys[i] = try a.dupe(Value, &.{ .{ .num = x[0] }, .{ .num = x[1] } });
    const d = try nested.design(a, &keys);
    try expect(!d.balanced);
    const r = try nested.anova(a, d, &ys);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4, 8 }, r.df);
    // Hand: C_AA = (15 - (25+16+36)/15)/2; C_AB = ((4+9)/5 + (9+1)/4 + 12/6
    // - 35/15)/2; C_BB = (15 - 7.1)/4.
    try approx(@as(f64, (15.0 - 77.0 / 15.0) / 2.0), r.ems[0][0], 1e-12);
    try approx(@as(f64, (7.1 - 35.0 / 15.0) / 2.0), r.ems[0][1], 1e-12);
    try approx(@as(f64, 1.975), r.ems[1][1], 1e-12);
    try approx(@as(f64, 0), r.ems[1][0], 0);
    // SS: A 4.3, B 38.133333..., error 20.5 (cell means by hand).
    try approx(@as(f64, 4.3), r.ss[0], 1e-10);
    try approx(@as(f64, 38.13333333333333), r.ss[1], 1e-10);
    try approx(@as(f64, 20.5), r.ss[2], 1e-10);
    const x = try nested.derive(a, r);
    const msb = 38.13333333333333 / 4.0;
    const sb = (msb - 2.5625) / 1.975;
    try approx(sb, x.comp[1], 1e-10);
    try approx((2.15 - 2.5625 - r.ems[0][1] * sb) / r.ems[0][0], x.comp[0], 1e-10);
}

test "STAT-NESTED-003 unbalanced runs and covariation list with a WARNING, no gap" {
    // Unbalanced after WHERE, y with y and the default two-variable list
    // (analysis of covariation) now list; one WARNING per unbalanced design.
    const cases = [_]struct { src: []const u8, warnings: usize }{
        .{ .src = "proc nested data=s(where=(y>2)); class a b; var y; run;", .warnings = 1 },
        .{ .src = "proc nested data=s; class a b; var y; var y; run;", .warnings = 0 },
        .{ .src = "proc nested data=s; class a b; var y z; run;", .warnings = 0 },
    };
    for (cases) |c| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        const listing = try e.run(c.src);
        try expect(!diag.gapHit());
        try expect(!e.diags.hasErrors());
        try expect(std.mem.indexOf(u8, listing, "Nested Random Effects Analysis of Variance") != null);
        if (c.warnings == 0) try expect(std.mem.indexOf(u8, listing, "Covariance of Variable y with") != null);
        var n: usize = 0;
        for (e.diags.list.items) |m| {
            if (std.mem.indexOf(u8, m.message, "The design is not balanced--F tests cannot be computed.") != null) n += 1;
        }
        try expectEqual(c.warnings, n);
    }
}
