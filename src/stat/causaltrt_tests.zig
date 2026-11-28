//! STAT-CAUSALTRT-001 permanent tests: PROC statement options and defaults,
//! CLASS / PSMODEL / MODEL / BY / FREQ declarations, documented ordering and
//! duplicate rules, user errors and loud gaps (asserted through the captured
//! diagnostics), and a hand-calculated IPW / IPWR case. Data are invented
//! (D-011). Expected values are hand mathematics, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const ct = @import("causaltrt.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
// columns: 0 g, 1 t, 2 y, 3 x, 4 c, 5 f, 6 s
const Row = struct { g: f64, t: f64, y: f64, x: f64, c: f64, f: f64, s: []const u8 };
const sample = [_]Row{
    .{ .g = 1, .t = 1, .y = 1, .x = 1, .c = 0, .f = 1, .s = "a" },
    .{ .g = 1, .t = 0, .y = 0, .x = 2, .c = 1, .f = 2, .s = "b" },
    .{ .g = 1, .t = 1, .y = 0, .x = 3, .c = 0, .f = 1, .s = "a" },
    .{ .g = 1, .t = 0, .y = 1, .x = 4, .c = 1, .f = 1, .s = "b" },
    .{ .g = 2, .t = 1, .y = 1, .x = 2, .c = 0, .f = 1, .s = "a" },
    .{ .g = 2, .t = 0, .y = 0, .x = nan, .c = 1, .f = 1, .s = "b" },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "s");
        for ([_][]const u8{ "g", "t", "y", "x", "c", "f" }) |n| _ = try ds.addColumn(n, .num);
        _ = try ds.addColumn("s", .char);
        for (sample) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .num = r.t }, .{ .num = r.y }, .{ .num = r.x }, .{ .num = r.c }, .{ .num = r.f }, .{ .str = r.s } });
        try self.lib.put("s", ds);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !ct.Spec {
        return ct.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn fails(self: *Env, source: []const u8, gap: bool) !void {
        self.diags = diag.Diagnostics.init(self.arena.allocator());
        diag.resetGap();
        if (self.parse(source)) |_| return error.TestExpectedError else |_| {}
        try expect(self.diags.hasErrors());
        try expectEqual(gap, diag.gapHit());
    }
};

test "STAT-CAUSALTRT-001 PROC options, roles and defaults" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // pp.2420, 2426, 2440: PSMODEL effects only -> IPWR; ALPHA=0.05;
    // no DIST= and an outcome outside CLASS -> normal; EVENT=FIRST.
    const d = try env.parse("proc causaltrt data=s; psmodel t=x; model y; run;");
    try expectEqual(ct.Method.ipwr, d.method);
    try approx(@as(f64, 0.05), d.alpha, 0);
    try expectEqual(ct.Dist.normal, d.dist);
    try expect(d.treatment.pick == .event_first and !d.treatment.descending);
    try expectEqual(@as(usize, 1), d.treatment.col);
    try std.testing.expectEqualSlices(usize, &.{3}, d.ps_effects);
    const e = try env.parse("proc causaltrt data=s method=ipw alpha=0.1 noprint desc namelen=40 threads=2; class c; psmodel t(ref='0')=x c; model y(desc) / dist=bin; freq f; by g; by g; run;");
    try expectEqual(ct.Method.ipw, e.method);
    try approx(@as(f64, 0.1), e.alpha, 0);
    try expect(e.noprint and e.descending and e.outcome.descending);
    try expectEqual(ct.Dist.binomial, e.dist);
    try std.testing.expectEqualStrings("0", e.treatment.pick.ref);
    try std.testing.expectEqualSlices(usize, &.{4}, e.class);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4 }, e.ps_effects);
    try expectEqual(@as(?usize, 5), e.freq);
    // p.2436: only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{0}, e.by_cols);
    const f = try env.parse("proc causaltrt data=s; psmodel t(event='1')=x; model y(ref=first) / distribution=binomial; run;");
    try std.testing.expectEqualStrings("1", f.treatment.pick.event);
    try expect(f.outcome.pick == .event_last);
}

test "STAT-CAUSALTRT-001 user errors and loud gaps via captured diagnostics" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // User errors (rc 1): required statements, ordering, ranges, roles.
    const user = [_][]const u8{
        "proc causaltrt data=s; psmodel t=x; run;",
        "proc causaltrt data=s; model y; run;",
        "proc causaltrt data=s; psmodel t=x c; model y; class c; run;",
        "proc causaltrt data=s alpha=0; psmodel t=x; model y; run;",
        "proc causaltrt data=s alpha=1.5; psmodel t=x; model y; run;",
        "proc causaltrt data=s namelen=10; psmodel t=x; model y; run;",
        "proc causaltrt data=s method=bogus; psmodel t=x; model y; run;",
        "proc causaltrt data=s bogus; psmodel t=x; model y; run;",
        "proc causaltrt data=s; psmodel t=nosuch; model y; run;",
        "proc causaltrt data=s; psmodel t=s; model y; run;",
        "proc causaltrt data=s; psmodel t=x; model y / dist=bogus; run;",
        "proc causaltrt data=s; psmodel t=x; model y; freq s; run;",
        "proc causaltrt data=s; psmodel t=x; model t / dist=bin; run;",
        "proc causaltrt data=nosuch; psmodel t=x; model y; run;",
    };
    for (user) |src| try env.fails(src, false);
    // Valid but unimplemented or unverified (rc 2).
    const gaps = [_][]const u8{
        "proc causaltrt data=s method=aipw; psmodel t=x; model y=x; run;",
        "proc causaltrt data=s method=ipws; psmodel t=x; model y; run;",
        "proc causaltrt data=s method=regadj; psmodel t; model y=x; run;",
        "proc causaltrt data=s; psmodel t=x; model y=x; run;",
        "proc causaltrt data=s; psmodel t; model y; run;",
        "proc causaltrt data=s att; psmodel t=x; model y; run;",
        "proc causaltrt data=s plots=none; psmodel t=x; model y; run;",
        "proc causaltrt data=s covdiffps; psmodel t=x; model y; run;",
        "proc causaltrt data=s; psmodel t=x*x; model y; run;",
        "proc causaltrt data=s; psmodel t=x / plots=all; model y; run;",
        "proc causaltrt data=s; psmodel t=x; model y / dist=poisson; run;",
        "proc causaltrt data=s; psmodel t=x; model y / link=log; run;",
        "proc causaltrt data=s; class c / ref=first; psmodel t=x c; model y; run;",
        "proc causaltrt data=s; psmodel t=x; model y; bootstrap nboot=10; run;",
        "proc causaltrt data=s; psmodel t=x; model y; output out=o; run;",
        "proc causaltrt data=s; psmodel t=x; psmodel t=c; model y; run;",
        "proc causaltrt data=s; psmodel t=x; model y(desc) / dist=normal; run;",
        "proc causaltrt data=s; psmodel t(order=data)=x; model y; run;",
    };
    for (gaps) |src| try env.fails(src, true);
}

test "STAT-CAUSALTRT-001 ORDER=, RORDER=, repeated options and FREQ statement rules" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // Defaults (pp.2441-2442): ORDER=FORMATTED, RORDER=FORMATTED; no EVENT=/REF=.
    const d = try env.parse("proc causaltrt data=s; psmodel t=x; model y / dist=bin; run;");
    try expect(d.order == .formatted and d.rorder == .formatted and !d.outcome.explicit);
    // SAS 9.4 verified: repeated METHOD=/ALPHA= are not errors; the last wins.
    const r = try env.parse("proc causaltrt data=s method=ipw method=ipwr alpha=0.1 alpha=0.2 order=data order=freq rorder=data rorder=internal; psmodel t=x; model y(ref=first) / dist=bin; run;");
    try expectEqual(ct.Method.ipwr, r.method);
    try approx(@as(f64, 0.2), r.alpha, 0);
    try expect(r.order == .freq and r.rorder == .internal and r.outcome.explicit);
    // SAS 9.4 verified: a second DATA= is ignored with a warning.
    env.diags = diag.Diagnostics.init(env.arena.allocator());
    const w = try env.parse("proc causaltrt data=s data=nosuch; psmodel t=x; model y; run;");
    try expectEqual(@as(usize, 1), w.treatment.col);
    try expect(env.diags.count() > 0 and !env.diags.hasErrors());
    const user = [_][]const u8{
        "proc causaltrt data=s order=bogus; psmodel t=x; model y; run;",
        "proc causaltrt data=s rorder=; psmodel t=x; model y; run;",
        // SAS 9.4 verified: "Only one FREQ statement is allowed."
        "proc causaltrt data=s; psmodel t=x; model y; freq f; freq f; run;",
    };
    for (user) |src| try env.fails(src, false);
}

test "STAT-CAUSALTRT-001 hand-calculated IPW and IPWR estimates" {
    // Constant propensity score e = 1/2 (intercept-only PS model on a
    // balanced treatment): IPWR = treated / control outcome means, IPW =
    // 2 * mean(t y) and 2 * mean((1-t) y). Hand mathematics.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 1, 1, 1 };
    const t = [_]f64{ 1, 1, 0, 0 };
    const y = [_]f64{ 1, 0, 1, 1 };
    const e = [_]f64{ 0.5, 0.5, 0.5, 0.5 };
    const f = [_]f64{ 1, 1, 1, 1 };
    const r = (try ct.estimate(a, .ipwr, &x, 1, &t, &y, &e, &f)).?;
    try approx(@as(f64, 0.5), r.pom1, 1e-12);
    try approx(@as(f64, 1.0), r.pom0, 1e-12);
    try approx(@as(f64, -0.5), r.ate, 1e-12);
    // IPWR sandwich with a constant score: the PS score x(t-e) is orthogonal
    // to the ratio scores here, so V(mu1) = sum (t/e)^2 (y-mu1)^2 / (sum t/e)^2
    // = (4*0.25*2) / 16 = 0.125; V(mu0) = 0 (all control y equal).
    try approx(@as(f64, @sqrt(0.125)), r.se1, 1e-12);
    try approx(@as(f64, 0), r.se0, 1e-12);
    const w = (try ct.estimate(a, .ipw, &x, 1, &t, &y, &e, &f)).?;
    try approx(@as(f64, 0.5), w.pom1, 1e-12);
    try approx(@as(f64, 1.0), w.pom0, 1e-12);
    // FREQ = 2 on every row: identical point estimates (p.2438).
    const f2 = [_]f64{ 2, 2, 2, 2 };
    const r2 = (try ct.estimate(a, .ipwr, &x, 1, &t, &y, &e, &f2)).?;
    try approx(r.pom1, r2.pom1, 1e-12);
    try approx(r.se1 / @sqrt(2.0), r2.se1, 1e-12);
}
