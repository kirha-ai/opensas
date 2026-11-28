//! STAT-LATTICE-001 permanent tests: PROC LATTICE options, VAR/BY roles, the
//! design variables, missing values, the balanced square lattice closed form
//! and loud boundaries, asserted through the captured diagnostics reporter
//! (no spawned process). The 3x3 data are the published Getting Started
//! sample of the users guide (Cochran and Cox pig feeding trial); expected
//! numbers are the published SAS 15.4 listing (PDF p.5513). The 2x2 case is
//! invented with hand sums of squares.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const lattice = @import("lattice.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// Group Block Treatment Weight of the published sample.
const pigs = [_][4]f64{
    .{ 1, 1, 1, 2.20 }, .{ 1, 1, 2, 1.84 }, .{ 1, 1, 3, 2.18 }, .{ 1, 2, 4, 2.05 }, .{ 1, 2, 5, 0.85 },
    .{ 1, 2, 6, 1.86 }, .{ 1, 3, 7, 0.73 }, .{ 1, 3, 8, 1.60 }, .{ 1, 3, 9, 1.76 }, .{ 2, 1, 1, 1.19 },
    .{ 2, 1, 4, 1.20 }, .{ 2, 1, 7, 1.15 }, .{ 2, 2, 2, 2.26 }, .{ 2, 2, 5, 1.07 }, .{ 2, 2, 8, 1.45 },
    .{ 2, 3, 3, 2.12 }, .{ 2, 3, 6, 2.03 }, .{ 2, 3, 9, 1.63 }, .{ 3, 1, 1, 1.81 }, .{ 3, 1, 5, 1.16 },
    .{ 3, 1, 9, 1.11 }, .{ 3, 2, 2, 1.76 }, .{ 3, 2, 6, 2.16 }, .{ 3, 2, 7, 1.80 }, .{ 3, 3, 3, 1.71 },
    .{ 3, 3, 4, 1.57 }, .{ 3, 3, 8, 1.13 }, .{ 4, 1, 1, 1.77 }, .{ 4, 1, 6, 1.57 }, .{ 4, 1, 8, 1.43 },
    .{ 4, 2, 2, 1.50 }, .{ 4, 2, 4, 1.60 }, .{ 4, 2, 9, 1.42 }, .{ 4, 3, 3, 2.04 }, .{ 4, 3, 5, 0.93 },
    .{ 4, 3, 7, 1.78 },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        // columns: 0 Group, 1 Block, 2 Treatment, 3 Weight, 4 Other, 5 g (char), 6 By
        const s = try a.create(Dataset);
        s.* = Dataset.init(a, "pigs");
        for ([_][]const u8{ "Group", "Block", "Treatment", "Weight", "Other" }) |n| _ = try s.addColumn(n, .num);
        _ = try s.addColumn("g", .char);
        _ = try s.addColumn("By", .num);
        for (0..2) |rep| for (pigs, 0..) |p, i| {
            const other: f64 = if (i == 5) nan else p[3] * 2;
            try s.appendRow(&.{ .{ .num = p[0] }, .{ .num = p[1] }, .{ .num = p[2] }, .{ .num = p[3] }, .{ .num = other }, .{ .str = "x" }, .{ .num = @floatFromInt(rep + 1) } });
        };
        try self.lib.put("pigs", s);
        diag.resetGap();
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn tokens(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !lattice.Spec {
        return lattice.parse(self.cx(), try self.tokens(source));
    }
    fn run(self: *Env, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try lattice.run(self.cx(), &out, try self.tokens(source));
        return out.items;
    }
    fn messages(self: *Env) ![]const u8 {
        return self.diags.render();
    }
};

fn fresh() !*Env {
    const e = try std.testing.allocator.create(Env);
    e.* = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    try e.init();
    return e;
}
fn done(e: *Env) void {
    e.arena.deinit();
    std.testing.allocator.destroy(e);
}

test "STAT-LATTICE-001 PROC options, defaults and variable roles" {
    const e = try fresh();
    defer done(e);
    // Defaults: most recent data set, no COVARIANCE; VAR omitted = every
    // numeric variable except Group/Block/Treatment/Rep (and here By).
    const d = try e.parse("proc lattice; run;");
    try expect(!d.covariance and !d.var_given and d.rep == null);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 6 }, d.vars);
    try expectEqual(@as(usize, 0), d.group);
    try expectEqual(@as(usize, 1), d.block);
    try expectEqual(@as(usize, 2), d.treatment);
    // BY variables are excluded from the default response list.
    const dby = try e.parse("proc lattice; by By; run;");
    try std.testing.expectEqualSlices(usize, &.{ 3, 4 }, dby.vars);
    try std.testing.expectEqualSlices(usize, &.{6}, dby.by_cols);
    const x = try e.parse("proc lattice data=pigs cov; var Weight; run;");
    try expect(x.covariance and x.var_given);
    try std.testing.expectEqualSlices(usize, &.{3}, x.vars);
    try expect((try e.parse("proc lattice data=pigs covariance; var weight--other; run;")).covariance);
    // Last BY statement wins (p.5514).
    const b = try e.parse("proc lattice data=pigs; by Group; by descending By; var Weight; run;");
    try std.testing.expectEqualSlices(usize, &.{6}, b.by_cols);
    try expect(b.by_desc[0]);
}

test "STAT-LATTICE-001 Treatmnt alias and required design variables" {
    const e = try fresh();
    defer done(e);
    const a = e.arena.allocator();
    const t = try a.create(Dataset);
    t.* = Dataset.init(a, "old");
    for ([_][]const u8{ "group", "block", "treatmnt", "y" }) |n| _ = try t.addColumn(n, .num);
    try e.lib.put("old", t);
    const s = try e.parse("proc lattice data=old; run;");
    try expectEqual(@as(usize, 2), s.treatment);
    try std.testing.expectEqualSlices(usize, &.{3}, s.vars);
    const u = try a.create(Dataset);
    u.* = Dataset.init(a, "nob");
    for ([_][]const u8{ "group", "treatment", "y" }) |n| _ = try u.addColumn(n, .num);
    try e.lib.put("nob", u);
    try std.testing.expectError(error.ParseError, e.parse("proc lattice data=nob; run;"));
    try expect(!diag.gapHit());
    try expect(std.mem.indexOf(u8, try e.messages(), "design variable Block") != null);
}

test "STAT-LATTICE-001 user errors fail with rc 1 and gaps with rc 2" {
    const e = try fresh();
    defer done(e);
    const user_errors = [_][]const u8{
        "proc lattice data=nosuch; run;",
        "proc lattice data=pigs data=pigs; run;",
        "proc lattice data=pigs bogus; run;",
        "proc lattice data=pigs; var g; run;",
        "proc lattice data=pigs; var Group; run;", // design variables only: no response
        "proc lattice data=pigs; var nosuch; run;",
        "proc lattice data=pigs; var; run;",
        "proc lattice data=pigs; class Group; run;",
        "proc lattice data=pigs; by By; var Weight; freq Other; run;", // ERROR 180-322 in SAS 15.4
        "proc lattice data=pigs; by By; var Weight; weight Other; run;",
    };
    for (user_errors) |src| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, e.run(src));
        try expect(!diag.gapHit());
    }
    const gaps = [_][]const u8{
        "proc lattice data=pigs; var Weight; run;", // no BY: each treatment twice per group
        "proc lattice data=pigs cov; var Weight Other; run;", // no BY: each treatment twice per group
    };
    for (gaps) |src| {
        diag.resetGap();
        _ = e.run(src) catch {};
        try expect(diag.gapHit());
    }
}

fn column(a: std.mem.Allocator, j: usize, rows: []const [4]f64) ![]Value {
    const out = try a.alloc(Value, rows.len);
    for (rows, out) |r, *v| v.* = .{ .num = r[j] };
    return out;
}

test "STAT-LATTICE-001 balanced square lattice matches the published listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try lattice.design(a, try column(a, 0, &pigs), try column(a, 1, &pigs), try column(a, 2, &pigs));
    try expectEqual(@as(usize, 3), d.k);
    const y = try a.alloc(f64, pigs.len);
    for (pigs, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    try std.testing.expectEqualSlices(usize, &.{ 3, 8, 8, 8, 16, 24, 35 }, &r.df);
    const ss = [_]f64{ 0.07739, 1.4206, 1.4206, 3.2261, 1.2368, 2.6574, 5.9609 };
    for (ss, r.ss) |want, got| try approx(want, got, 0.00005);
    const ms = [_]f64{ 0.02580, 0.1776, 0.1776, 0.4033, 0.07730, 0.1107, 0.1703 };
    for (ms, r.ms) |want, got| try approx(want, got, 0.00005);
    try approx(0.04593, r.var_same, 0.000005);
    try approx(0.6259, r.lsd01, 0.00005);
    try approx(0.4543, r.lsd05, 0.00005);
    try approx(120.55, r.efficiency, 0.005);
    try expect(r.adjusted);
    const means = [_]f64{ 1.8035, 1.7544, 1.9643, 1.7267, 0.9393, 1.8448, 1.3870, 1.4347, 1.5004 };
    for (means, r.means) |want, got| try approx(want, got, 0.00005);
}

test "STAT-LATTICE-001 2x2 lattice hand calculation" {
    // k=2: treatments 1..4, groups {12|34}, {13|24}, {14|23}. Invented y.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_][4]f64{
        .{ 1, 1, 1, 10 }, .{ 1, 1, 2, 12 }, .{ 1, 2, 3, 9 },  .{ 1, 2, 4, 15 },
        .{ 2, 1, 1, 11 }, .{ 2, 1, 3, 7 },  .{ 2, 2, 2, 14 }, .{ 2, 2, 4, 16 },
        .{ 3, 1, 1, 8 },  .{ 3, 1, 4, 13 }, .{ 3, 2, 2, 12 }, .{ 3, 2, 3, 10 },
    };
    const d = try lattice.design(a, try column(a, 0, &rows), try column(a, 1, &rows), try column(a, 2, &rows));
    const y = try a.alloc(f64, rows.len);
    for (rows, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    // G = 137, CF = 137^2/12 = 1564.0833; sum y^2 = 1649 -> total 84.9167.
    // Reps 46,48,43: (46^2+48^2+43^2)/4 - CF = 1567.25 - 1564.0833 = 3.1667.
    // Treatments 29,38,26,44: 841+1444+676+1936 = 4897; 4897/3 - CF =
    // 1632.3333 - 1564.0833 = 68.25. Blocks 22,24 | 18,30 | 21,22:
    // 3209/2 - 1567.25 = 37.25 unadjusted. Q_t = T_t - (block totals)/2:
    // -1.5, 1, -6, 6.5; sum Q^2 / k = 81.5/2 = 40.75; blocks adj = 37.25 +
    // 40.75 - 68.25 = 9.75; intra = 84.9167 - 3.1667 - 68.25 - 9.75 = 3.75
    // with (k-1)(k^2-1) = 3 df.
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 3, 3, 3, 6, 11 }, &r.df);
    try approx(3.166667, r.ss[0], 1e-5);
    try approx(9.75, r.ss[1], 1e-9);
    try approx(68.25, r.ss[3], 1e-9);
    try approx(3.75, r.ss[4], 1e-9);
    try approx(13.5, r.ss[5], 1e-9);
    try approx(84.916667, r.ss[6], 1e-5);
    // Eb = 3.25, Ee = 1.25; mu = 2/(4*3.25) = 0.153846; Ee' = Ee(1+2 mu) =
    // 1.634615; variance = 2 Ee'/3 = 1.089744; RCBD MS = 13.5/6 = 2.25;
    // efficiency = 225/1.634615 = 137.647 (> 105: means adjusted).
    try approx(1.089744, r.var_same, 1e-6);
    try approx(137.647, r.efficiency, 1e-3);
    try expect(r.adjusted);
    // C_b = sum T - 3B: {1,2} 1, {3,4} -2, {1,3} 1, {2,4} -8, {1,4} 10,
    // {2,3} -2; W_1 = 1+1+10 = 12; mean_1 = (29 + 12 mu)/3 = 10.282051.
    try approx(10.282051, r.means[0], 1e-6);
    // W_4 = -2-8+10 = 0 -> mean_4 = 44/3.
    try approx(44.0 / 3.0, r.means[3], 1e-9);
    // t(0.975, 3) = 3.182446: LSD.05 = 3.182446 * sqrt(1.089744) = 3.322181.
    try approx(3.322181, r.lsd05, 1e-5);
}

test "STAT-LATTICE-001 design validation and missing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bad = pigs;
    // Missing design value -> analysis not performed.
    bad[4][1] = nan;
    try std.testing.expectError(error.MissingDesignValue, lattice.design(a, try column(a, 0, &bad), try column(a, 1, &bad), try column(a, 2, &bad)));
    bad = pigs;
    bad[4][2] = 0;
    try std.testing.expectError(error.InvalidDesignValue, lattice.design(a, try column(a, 0, &bad), try column(a, 1, &bad), try column(a, 2, &bad)));
    bad = pigs;
    bad[4][2] = 1.5;
    try std.testing.expectError(error.InvalidDesignValue, lattice.design(a, try column(a, 0, &bad), try column(a, 1, &bad), try column(a, 2, &bad)));
    // Two groups only: a partially balanced square lattice (STAT-LATTICE-002).
    try expectEqual(@as(usize, 2), (try lattice.design(a, try column(a, 0, pigs[0..18]), try column(a, 1, pigs[0..18]), try column(a, 2, pigs[0..18]))).m);
    // A treatment twice in one group.
    bad = pigs;
    bad[1][2] = 1;
    try std.testing.expectError(error.NotBalancedSquare, lattice.design(a, try column(a, 0, &bad), try column(a, 1, &bad), try column(a, 2, &bad)));
}

test "STAT-LATTICE-001 BY groups and dropped response variables" {
    const e = try fresh();
    defer done(e);
    // Two identical BY groups give two identical analyses.
    const out = try e.run("proc lattice data=pigs; by By; var Weight; run;");
    try expectEqual(@as(usize, 2), std.mem.count(u8, out, "The Lattice Procedure"));
    try expect(std.mem.indexOf(u8, out, "By=1") != null and std.mem.indexOf(u8, out, "By=2") != null);
    try expectEqual(@as(usize, 2), std.mem.count(u8, out, "Efficiency Relative to RCBD                120.55"));
    try expect(!diag.gapHit());
    // Other has a missing value: it is dropped with a warning, the other
    // response is analyzed; with every response dropped nothing is listed.
    const both = try e.run("proc lattice data=pigs; by By; var Other Weight; run;");
    try std.testing.expectEqualStrings(out, both);
    try expect(std.mem.indexOf(u8, try e.messages(), "WARNING: One (or more) missing values have been encountered for the response variable Other. This variable will be dropped from the analysis.") != null);
    try expectEqual(@as(usize, 0), (try e.run("proc lattice data=pigs; by By; var Other; run;")).len);
    try expect(!diag.gapHit());
    // Unsorted BY data is a user error.
    diag.resetGap();
    try std.testing.expectError(error.ParseError, e.run("proc lattice data=pigs; by descending By; var Weight; run;"));
    try expect(!diag.gapHit());
}

test "STAT-LATTICE-001 missing design values and empty input are user errors" {
    const e = try fresh();
    defer done(e);
    const a = e.arena.allocator();
    const src = e.lib.find("pigs").?;
    const f = try a.create(Dataset);
    f.* = Dataset.init(a, "f");
    for ([_][]const u8{ "Group", "Block", "Treatment", "Weight" }) |n| _ = try f.addColumn(n, .num);
    for (src.rows.items[0..36], 0..) |r, i| try f.appendRow(&.{ if (i == 2) .{ .num = nan } else r[0], r[1], r[2], r[3] });
    try e.lib.put("f", f);
    try std.testing.expectError(error.ParseError, e.run("proc lattice data=f; run;"));
    try expect(!diag.gapHit());
    try expect(std.mem.indexOf(u8, try e.messages(), "Missing value(s) encountered for GROUP variable.") != null);
    const z = try a.create(Dataset);
    z.* = Dataset.init(a, "z");
    for ([_][]const u8{ "Group", "Block", "Treatment", "Weight" }) |n| _ = try z.addColumn(n, .num);
    try e.lib.put("z", z);
    try std.testing.expectError(error.ParseError, e.run("proc lattice data=z; run;"));
    try expect(!diag.gapHit());
}

test "STAT-LATTICE-001 COVARIANCE sums of products" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try lattice.design(a, try column(a, 0, &pigs), try column(a, 1, &pigs), try column(a, 2, &pigs));
    const x = try a.alloc(f64, pigs.len);
    const y = try a.alloc(f64, pigs.len);
    for (pigs, x, y) |p, *u, *v| {
        u.* = p[3];
        v.* = 2 * p[3] + p[2] / 7;
    }
    const rx = try lattice.analyze(a, d, x);
    const ry = try lattice.analyze(a, d, y);
    // SP(x, x) = SS(x) for every source.
    const self = try lattice.products(a, d, x, x, rx, rx);
    for (self, rx.ss) |sp, ss| try approx(ss, sp, 1e-12);
    // y = 2x + t/7 with t constant within treatments: every source but
    // Treatments has SP(x, y) = 2 SS(x) (the published Weight sums of
    // squares doubled, as in the SAS 15.4 reference run: 0.1548, 2.8412,
    // 2.4736, 5.3148); Treatments gains sum_t T_t (t/7) r terms.
    const sp = try lattice.products(a, d, x, y, rx, ry);
    for ([_]usize{ 0, 1, 2, 4, 5 }) |i| try approx(2 * rx.ss[i], sp[i], 1e-10);
    try approx(0.1548, sp[0], 0.00005);
    try approx(2.8412, sp[1], 0.00005);
    try approx(4.5336, sp[3], 0.00005);
    try approx(10.0032, sp[6], 0.00005);
}

test "STAT-LATTICE-001 Rep variable" {
    const e = try fresh();
    defer done(e);
    const a = e.arena.allocator();
    const src = e.lib.find("pigs").?;
    // Rep constant 1 is the basic plan; a missing Rep is a user error; a
    // single observation with Rep 2 is an incomplete repetition.
    for ([_]f64{ 1, nan, 2 }, 0..) |second, case| {
        const r = try a.create(Dataset);
        r.* = Dataset.init(a, "r");
        for ([_][]const u8{ "Group", "Block", "Treatment", "Weight", "Rep" }) |n| _ = try r.addColumn(n, .num);
        for (src.rows.items[0..36], 0..) |row, i| try r.appendRow(&.{ row[0], row[1], row[2], row[3], .{ .num = if (i == 7) second else 1 } });
        try e.lib.put("r", r);
        diag.resetGap();
        switch (case) {
            0 => try expect(std.mem.indexOf(u8, try e.run("proc lattice data=r; run;"), "Efficiency Relative to RCBD                120.55") != null),
            1 => {
                try std.testing.expectError(error.ParseError, e.run("proc lattice data=r; run;"));
                try expect(!diag.gapHit());
                try expect(std.mem.indexOf(u8, try e.messages(), "Missing value(s) encountered for REP variable.") != null);
            },
            else => {
                // A Rep 2 holding one observation leaves empty cells: a user
                // error as in the SAS 15.4 reference run with an emptied group.
                try std.testing.expectError(error.ParseError, e.run("proc lattice data=r; run;"));
                try expect(!diag.gapHit());
                try expect(std.mem.indexOf(u8, try e.messages(), "There are 0 observations in the GROUP 1 TREATMENT 8 REP 1 Cell.") != null);
            },
        }
    }
}

test "STAT-LATTICE-001 repeated basic plan matches the SAS 15.4 reference run" {
    // Rep 1 = published sample, Rep 2 = Weight*1.1 + mod(3t+b,5)/10 - g/20
    // (tests/corpus/stat_lattice001_repeated.sas); expected values are the
    // SAS 15.4 listing of that program.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 2 * pigs.len;
    const g = try a.alloc(Value, n);
    const b = try a.alloc(Value, n);
    const tr = try a.alloc(Value, n);
    const rp = try a.alloc(Value, n);
    const y = try a.alloc(f64, n);
    for (0..2) |rep| for (pigs, 0..) |p, i| {
        const o = rep * pigs.len + i;
        g[o] = .{ .num = p[0] };
        b[o] = .{ .num = p[1] };
        tr[o] = .{ .num = p[2] };
        rp[o] = .{ .num = @floatFromInt(rep + 1) };
        y[o] = if (rep == 0) p[3] else p[3] * 1.1 + @mod(p[2] * 3 + p[1], 5) / 10 - p[0] / 20;
    };
    const d = try lattice.designRep(a, g, b, tr, rp, null);
    try expectEqual(@as(usize, 2), d.p);
    const r = try lattice.analyze(a, d, y);
    try std.testing.expectEqualSlices(usize, &.{ 7, 16, 8, 8, 40, 56, 71 }, &r.df);
    try expectEqual(@as(usize, 8), r.df_a);
    const ss = [_]f64{ 1.5420, 3.1214, 3.0855, 7.2039, 2.7698, 5.8912, 14.6370 };
    for (ss, r.ss) |want, got| try approx(want, got, 0.00005);
    try approx(0.03587, r.ss_a, 0.000005);
    try approx(0.004484, r.ms_a, 0.0000005);
    try approx(0.02083, r.var_same, 0.000005);
    try approx(0.3903, r.lsd01, 0.00005);
    try approx(0.2917, r.lsd05, 0.00005);
    try approx(126.29, r.efficiency, 0.005);
    const means = [_]f64{ 2.0413, 1.9092, 2.0812, 1.8939, 1.0101, 1.9363, 1.5590, 1.5099, 1.5945 };
    for (means, r.means) |want, got| try approx(want, got, 0.00005);
    // Independent identity: an exact copy as Rep 2 has no variation among
    // blocks holding the same treatments (Component A = 0) and doubles every
    // other sum of squares except Replications/Total, which gain the copy too.
    @memcpy(y[pigs.len..], y[0..pigs.len]);
    for (pigs, 0..) |p, i| y[pigs.len + i] = p[3];
    const c = try lattice.analyze(a, d, y);
    try approx(0, c.ss_a, 1e-10);
    try approx(2 * 3.2261, c.ss[3], 0.0001);
    try approx(2 * 1.4206, c.ss[1], 0.0001);
    // A Rep 2 whose blocks carry other labels is not the same basic plan
    // (SAS 15.4: "TREATMENT 1 has been placed into two different cells in
    // GROUP 1 REP 2.").
    for (pigs, 0..) |p, i| if (p[0] == 1) {
        b[pigs.len + i] = .{ .num = @mod(p[1], 3) + 1 };
    };
    var cell: lattice.Cell = .{};
    try std.testing.expectError(error.RepeatedCellConflict, lattice.designRep(a, g, b, tr, rp, &cell));
    try expectEqual(lattice.Cell{ .group = 1, .treatment = 1, .rep = 2 }, cell);
    // Rep 2 without Group 4: "There are 0 observations in the GROUP 4
    // TREATMENT 1 REP 2 Cell."
    for (pigs, 0..) |p, i| b[pigs.len + i] = .{ .num = p[1] };
    try std.testing.expectError(error.RepeatedCellMissing, lattice.designRep(a, g[0 .. n - 9], b[0 .. n - 9], tr[0 .. n - 9], rp[0 .. n - 9], &cell));
    try expectEqual(lattice.Cell{ .group = 4, .treatment = 1, .rep = 2 }, cell);
}

test "STAT-LATTICE-001 no recovery when the block mean square is below the intra-block error" {
    // Y1 = Treatment + mod(7n,5)/10 (stat_lattice001_options_roles case G1);
    // SAS 15.4: Ee 0.02620, Variance of Difference 0.01310 = 2 Ee / r, LSDs
    // on the 24 randomized complete block df, efficiency 73.7633,
    // unadjusted means T / r.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try lattice.design(a, try column(a, 0, &pigs), try column(a, 1, &pigs), try column(a, 2, &pigs));
    const y = try a.alloc(f64, pigs.len);
    for (pigs, y, 1..) |p, *v, obs| v.* = p[2] + @as(f64, @floatFromInt((obs * 7) % 5)) / 10;
    const r = try lattice.analyze(a, d, y);
    try expect(r.ms[1] < r.ms[4] and !r.adjusted);
    try approx(0.02620, r.ms[4], 0.000005);
    try approx(2 * r.ms[4] / 4, r.var_same, 1e-12);
    try approx(0.01310, r.var_same, 0.000005);
    try approx(0.3201, r.lsd01, 0.00005);
    try approx(0.2362, r.lsd05, 0.00005);
    try approx(73.7633, r.efficiency, 0.00005);
    const means = [_]f64{ 1.1500, 2.2750, 3.1500, 4.2750, 5.0750, 6.2500, 7.3250, 8.1250, 9.1750 };
    for (means, r.means) |want, got| try approx(want, got, 0.00005);
}

// Example 75.1 (p.5505): Treatment Yield pairs, Group 1..2, Block 1..5, five
// plots per block in input order (Cochran and Cox 1957, p.406).
const soy = [_]f64{
    1,  6,  2,  7,  3,  5,  4,  8,  5,  6,  6,  16, 7,  12, 8,  12, 9,  13, 10, 8,
    11, 17, 12, 7,  13, 7,  14, 9,  15, 14, 16, 18, 17, 16, 18, 13, 19, 13, 20, 14,
    21, 14, 22, 15, 23, 11, 24, 14, 25, 14, 1,  24, 6,  13, 11, 24, 16, 11, 21, 8,
    2,  21, 7,  11, 12, 14, 17, 11, 22, 23, 3,  16, 8,  4,  13, 12, 18, 12, 23, 12,
    4,  17, 9,  10, 14, 30, 19, 9,  24, 23, 5,  15, 10, 15, 15, 22, 20, 16, 25, 19,
};

test "STAT-LATTICE-002 partially balanced square lattice matches Example 75.1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rows: [50][4]f64 = undefined;
    for (&rows, 0..) |*r, i| r.* = .{ @floatFromInt(i / 25 + 1), @floatFromInt(i % 25 / 5 + 1), soy[2 * i], soy[2 * i + 1] };
    const d = try lattice.design(a, try column(a, 0, &rows), try column(a, 1, &rows), try column(a, 2, &rows));
    try expectEqual(@as(usize, 5), d.k);
    try expectEqual(@as(usize, 2), d.m);
    const y = try a.alloc(f64, rows.len);
    for (rows, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    try expect(r.partial and r.adjusted);
    try std.testing.expectEqualSlices(usize, &.{ 1, 8, 8, 24, 16, 24, 49 }, &r.df);
    const ss = [_]f64{ 212.18, 501.84, 501.84, 559.28, 218.48, 720.32, 1491.78 };
    for (ss, r.ss) |want, got| try approx(want, got, 0.005);
    const ms = [_]f64{ 212.18, 62.7300, 62.7300, 23.3033, 13.6550, 30.0133, 30.4445 };
    for (ms, r.ms) |want, got| try approx(want, got, 0.00005);
    try approx(15.7915, r.var_same, 0.00005);
    try approx(17.9280, r.var_diff, 0.00005);
    try approx(17.2159, r.var_avg, 0.00005);
    try approx(12.1189, r.lsd01, 0.00005);
    try approx(8.7959, r.lsd05, 0.00005);
    try approx(174.34, r.efficiency, 0.005);
    const means = [_]f64{ 19.0681, 16.9728, 14.6463, 14.7687, 12.8470, 13.1701, 9.0748, 6.7483, 8.3707, 8.4489, 23.5511, 12.4558, 12.6293, 20.7517, 19.3299, 12.6224, 10.5272, 10.7007, 7.3231, 11.4013, 11.6259, 18.5306, 12.2041, 17.3265, 15.4048 };
    for (means, r.means) |want, got| try approx(want, got, 0.00005);
}

test "STAT-LATTICE-002 simple 2x2 lattice hand calculation" {
    // k = 2, m = 2: groups {1,2|3,4} and {1,3|2,4}. Invented y.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_][4]f64{
        .{ 1, 1, 1, 10 }, .{ 1, 1, 2, 12 }, .{ 1, 2, 3, 9 }, .{ 1, 2, 4, 15 },
        .{ 2, 1, 1, 11 }, .{ 2, 1, 3, 7 },  .{ 2, 2, 2, 14 }, .{ 2, 2, 4, 16 },
    };
    const d = try lattice.design(a, try column(a, 0, &rows), try column(a, 1, &rows), try column(a, 2, &rows));
    const y = try a.alloc(f64, rows.len);
    for (rows, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    // G = 94, CF = 1104.5, sum y^2 = 1172 -> total 67.5. Reps 46, 48:
    // 4420/4 - CF = 0.5. Treatments 21, 26, 16, 31: 2334/2 - CF = 62.5.
    // Blocks 22, 24 | 18, 30; C_b = sum T - 2B: 3, -1 | 1, -3; blocks adj =
    // 20/(2*2*1) - (2^2 + 2^2)/(4*2*1) = 5 - 1 = 4; intra = 67.5 - 0.5 -
    // 62.5 - 4 = 0.5 on (k-1)(mk-k-1) = 1 df.
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 2, 3, 1, 3, 7 }, &r.df);
    for ([_]f64{ 0.5, 4, 4, 62.5, 0.5, 4.5, 67.5 }, r.ss) |want, got| try approx(want, got, 1e-9);
    // Eb = 2, Ee = 0.5: w = 2, w' = 1/(2*2 - 0.5) = 2/7, mu = (12/7) /
    // (2 (2 + 2/7)) = 3/8. 2Ee/m = 0.5: same block 0.5(1 + 3/8) = 0.6875,
    // different 0.5(1 + 3/4) = 0.875, average 0.5(1 + 4(3/8)/3) = 0.75;
    // efficiency = 1.5 / (m/2 * 0.75) = 200%.
    try expect(r.partial and r.adjusted);
    try approx(0.6875, r.var_same, 1e-12);
    try approx(0.875, r.var_diff, 1e-12);
    try approx(0.75, r.var_avg, 1e-12);
    try approx(200, r.efficiency, 1e-9);
    // t(0.975, 1) = 12.706205: LSD.05 = 12.706205 * sqrt(0.75) = 11.003893.
    try approx(11.003893, r.lsd05, 1e-5);
    // W_t = sum of C_b over the blocks holding t: C11 + C21 = 4,
    // C11 + C22 = 0, C12 + C21 = 0, C12 + C22 = -4 -> (T + 3/8 W)/2.
    for ([_]f64{ 11.25, 13, 8, 14.75 }, r.means) |want, got| try approx(want, got, 1e-12);
}

test "STAT-LATTICE-002 simple 3x3 lattice of groups 2 and 4 (SAS 15.4 reference run)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rows: [18][4]f64 = undefined;
    var n: usize = 0;
    for (pigs) |p| if (p[0] == 2 or p[0] == 4) {
        rows[n] = p;
        if (p[0] == 4) rows[n][0] = 1;
        n += 1;
    };
    const d = try lattice.design(a, try column(a, 0, &rows), try column(a, 1, &rows), try column(a, 2, &rows));
    const y = try a.alloc(f64, rows.len);
    for (rows, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    try expect(r.partial and r.adjusted);
    for ([_]f64{ 0.000200, 0.7503, 0.7503, 1.6011, 0.1260, 0.8763, 2.4776 }, r.ss) |want, got| try approx(want, got, 0.00005);
    try approx(0.03151, r.ms[4], 0.000005);
    try approx(0.04025, r.var_same, 0.000005);
    try approx(0.04899, r.var_diff, 0.000005);
    try approx(0.04462, r.var_avg, 0.000005);
    try approx(0.9725, r.lsd01, 0.00005);
    try approx(0.5865, r.lsd05, 0.00005);
    try approx(245.51, r.efficiency, 0.005);
    for ([_]f64{ 1.6894, 1.8315, 1.9191, 1.7023, 0.8156, 1.6821, 1.6314, 1.2986, 1.5000 }, r.means) |want, got| try approx(want, got, 0.00005);
}

test "STAT-LATTICE-002 simple rectangular lattice without recovery (SAS 15.4 reference run)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // k = 3, 12 treatments, rows and columns of a 4x4 grid without its
    // diagonal (stat_lattice002_rectangular, invented data).
    const rect = [_][4]f64{
        .{ 1, 1, 1, 10.2 }, .{ 1, 1, 2, 11.5 }, .{ 1, 1, 3, 9.8 },  .{ 1, 2, 4, 12.1 },  .{ 1, 2, 5, 13.0 },  .{ 1, 2, 6, 11.7 },
        .{ 1, 3, 7, 8.9 },  .{ 1, 3, 8, 10.4 }, .{ 1, 3, 9, 9.5 },  .{ 1, 4, 10, 12.8 }, .{ 1, 4, 11, 11.1 }, .{ 1, 4, 12, 13.6 },
        .{ 2, 1, 4, 11.4 }, .{ 2, 1, 7, 9.9 },  .{ 2, 1, 10, 12.2 }, .{ 2, 2, 1, 10.9 }, .{ 2, 2, 8, 9.7 },   .{ 2, 2, 11, 12.5 },
        .{ 2, 3, 2, 12.0 }, .{ 2, 3, 5, 12.4 }, .{ 2, 3, 12, 14.1 }, .{ 2, 4, 3, 9.1 },  .{ 2, 4, 6, 10.8 },  .{ 2, 4, 9, 10.3 },
    };
    const d = try lattice.design(a, try column(a, 0, &rect), try column(a, 1, &rect), try column(a, 2, &rect));
    try expect(d.rect and d.k == 3 and d.m == 2);
    const y = try a.alloc(f64, rect.len);
    for (rect, y) |p, *v| v.* = p[3];
    const r = try lattice.analyze(a, d, y);
    try expect(!r.unverified and !r.adjusted and !r.partial);
    try std.testing.expectEqualSlices(usize, &.{ 1, 6, 6, 11, 5, 11, 23 }, &r.df);
    for ([_]f64{ 0.02042, 1.4925, 1.4925, 43.2846, 2.2821, 3.7746, 47.0796 }, r.ss) |want, got| try approx(want, got, 0.00005);
    try approx(0.4564, r.var_same, 0.00005);
    try approx(2.0982, r.lsd01, 0.00005);
    try approx(1.4870, r.lsd05, 0.00005);
    try approx(75.1822, r.efficiency, 0.00005);
    try approx(10.55, r.means[0], 1e-9);
    // Strong block effects in group 1 (Eb > Ee): rectangular recovery is
    // not verified and is flagged for the caller's gap.
    for (rect, y) |p, *v| v.* = p[3] + if (p[0] == 1) 3 * p[1] else 0;
    try expect((try lattice.analyze(a, d, y)).unverified);
}

test "STAT-LATTICE-002 designs outside the implemented lattices stay loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A partially balanced plan repeated through Rep.
    const n = 36;
    const g = try a.alloc(Value, n);
    const b = try a.alloc(Value, n);
    const tr = try a.alloc(Value, n);
    const rp = try a.alloc(Value, n);
    for (0..n) |i| {
        const p = pigs[i % 18];
        g[i] = .{ .num = p[0] };
        b[i] = .{ .num = p[1] };
        tr[i] = .{ .num = p[2] };
        rp[i] = .{ .num = @floatFromInt(i / 18 + 1) };
    }
    try std.testing.expectError(error.NotBalancedSquare, lattice.designRep(a, g, b, tr, rp, null));
    // The same pair twice in one block of two groups.
    var twice = pigs;
    for (twice[9..18], pigs[0..9]) |*r, p| r.* = .{ 2, p[1], p[2], p[3] };
    try std.testing.expectError(error.NotBalancedSquare, lattice.design(a, try column(a, 0, twice[0..18]), try column(a, 1, twice[0..18]), try column(a, 2, twice[0..18])));
}
