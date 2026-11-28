//! STAT-CANCORR-001 permanent tests: PROC statement options, aliases and
//! defaults, VAR / WITH / BY / FREQ / WEIGHT roles, the missing-value and
//! FREQ / WEIGHT exclusion rules, the canonical kernel and the loud
//! execution boundaries. All data are invented (D-011); expected values are
//! hand mathematics stated next to each check, never opensas output. The full
//! listings are covered by tests/corpus/stat_cancorr001_*.sas against SAS 9.4.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const cancorr = @import("cancorr.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

/// g=1: x=(1,2,3,4,5), y=(2,1,4,3,5) (Pearson r = 8/10 = 0.8) plus excluded
/// rows (missing y, FREQ 0.5, WEIGHT 0, missing FREQ); g=2: the same five
/// pairs with the last pair given FREQ 2.7 (integer part 2).
fn build(a: std.mem.Allocator, lib: *Library) !void {
    const s = try a.create(Dataset);
    s.* = Dataset.init(a, "s");
    for ([_][]const u8{ "g", "x", "y", "z", "f", "w" }) |n| _ = try s.addColumn(n, .num);
    _ = try s.addColumn("c", .char);
    const rows = [_][6]f64{
        .{ 1, 1, 2, 5, 1, 1 },   .{ 1, 2, 1, 3, 1, 1 },   .{ 1, 3, 4, 4, 1, 1 },   .{ 1, 4, 3, 1, 1, 1 },
        .{ 1, 5, 5, 2, 1, 1 },   .{ 1, 9, nan, 1, 1, 1 }, .{ 1, 9, 9, 1, 0.5, 1 }, .{ 1, 9, 0, 1, 1, 0 },
        .{ 1, 9, 0, 1, nan, 1 }, .{ 2, 1, 2, 5, 1, 1 },   .{ 2, 2, 1, 3, 1, 1 },   .{ 2, 3, 4, 4, 1, 1 },
        .{ 2, 4, 3, 1, 1, 1 },   .{ 2, 5, 5, 2, 2.7, 1 },
    };
    for (rows) |r| try s.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .str = "k" } });
    try lib.put("s", s);
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        try build(a, &self.lib);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !cancorr.Spec {
        return cancorr.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return cancorr.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-CANCORR-001 PROC statement defaults, aliases and default VAR set" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const d = try env.parse("proc cancorr data=s; var x; with y; run;");
    // pp.2130-2131: prefixes V / W, names "VAR Variables" / "WITH
    // Variables", SINGULAR=1E-8.
    try expect(std.mem.eql(u8, d.vprefix, "V") and std.mem.eql(u8, d.wprefix, "W"));
    try expect(std.mem.eql(u8, d.vname, "VAR Variables") and std.mem.eql(u8, d.wname, "WITH Variables"));
    try approx(1e-8, d.singular, 0);
    try expect(!d.short and !d.noprint and d.freq == null and d.weight == null);
    const x = try env.parse("proc cancorr data=s vp=Left wp=Right vn='L set' wn=\"R set\" sing=1e-6 short noprint; var x; with y; freq f; weight w; by g; run;");
    try expect(std.mem.eql(u8, x.vprefix, "Left") and std.mem.eql(u8, x.wprefix, "Right"));
    try expect(std.mem.eql(u8, x.vname, "L set") and std.mem.eql(u8, x.wname, "R set"));
    try approx(1e-6, x.singular, 0);
    try expect(x.short and x.noprint);
    try expectEqual(@as(usize, 4), x.freq.?);
    try expectEqual(@as(usize, 5), x.weight.?);
    try expectEqual(@as(usize, 1), x.by_cols.len);
    const full = try env.parse("proc cancorr data=s vprefix=A wprefix=B vname='a' wname='b' singular=0.5; var x; with y; run;");
    try expect(std.mem.eql(u8, full.vprefix, "A") and std.mem.eql(u8, full.wname, "b"));
    // p.2133: without VAR, every numeric variable not named elsewhere (here
    // not WITH, BY, FREQ or WEIGHT); the character variable c is not used.
    const dv = try env.parse("proc cancorr data=s; with y; by g; freq f; weight w; run;");
    try expectEqual(@as(usize, 2), dv.vars.len);
    try expectEqual(@as(usize, 1), dv.vars[0]);
    try expectEqual(@as(usize, 3), dv.vars[1]);
    // p.2132: with more than one BY statement only the last is used.
    const b2 = try env.parse("proc cancorr data=s; var x; with y; by g; by z notsorted; run;");
    try expectEqual(@as(usize, 1), b2.by_cols.len);
    try expectEqual(@as(usize, 3), b2.by_cols[0]);
}

test "STAT-CANCORR-001 kernel: one pair reduces to the Pearson correlation" {
    // x=(1,2,3,4,5), y=(2,1,4,3,5): Sxy=8, Sxx=Syy=10, r=0.8; df = 4.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const res = try cancorr.analyze(a, &.{ 1, 2, 2, 1, 3, 4, 4, 3, 5, 5 }, &.{ 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1 }, 1, 1, 1e-8);
    try approx(0.8, res.r[0], 1e-14);
    try approx(4, res.df, 0);
    // Unit-variance standardized coefficients are 1; sd = sqrt(10/4).
    try approx(1, res.a[0], 1e-14);
    try approx(1, res.b[0], 1e-14);
    try approx(@sqrt(2.5), res.sdx[0], 1e-14);
    // Rao's F with p=q=1 is the regression F: r^2 (n-2) / (1-r^2) = 0.64*3/0.36.
    const ft = cancorr.rao(res, 0);
    try approx(0.36, ft.value, 1e-14);
    try approx(0.64 * 3 / 0.36, ft.f, 1e-12);
    try approx(1, ft.df1, 0);
    try approx(3, ft.df2, 1e-14);
    // s=1: every multivariate F is the same exact F.
    const mv = cancorr.multivariate(res);
    try expectEqual(@as(usize, 1), mv.s);
    try approx(0.64 / 0.36 * 3, mv.tests[3].f, 1e-12);
    try approx(0.64 / 0.36 * 3, mv.tests[1].f, 1e-12);
}

test "STAT-CANCORR-001 FREQ counts observations, WEIGHT does not alter df" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const xy = [_]f64{ 1, 2, 2, 1, 3, 4, 4, 3, 5, 5 };
    const xy6 = [_]f64{ 1, 2, 2, 1, 3, 4, 4, 3, 5, 5, 5, 5 };
    // FREQ 2 on the last pair == that pair listed twice (pp.2132-2133).
    const f2 = try cancorr.analyze(a, &xy, &.{ 1, 1, 1, 1, 2 }, &.{ 1, 1, 1, 1, 1 }, 1, 1, 1e-8);
    const dup = try cancorr.analyze(a, &xy6, &.{ 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1 }, 1, 1, 1e-8);
    // Six pairs: Sxx = Syy = 80 - 6*(10/3)^2 = 40/3, Sxy = 78 - 200/3 = 34/3,
    // r = 34/40 = 0.85.
    try approx(0.85, dup.r[0], 1e-14);
    try approx(dup.r[0], f2.r[0], 1e-14);
    try approx(5, f2.df, 0);
    try approx(dup.sdx[0], f2.sdx[0], 1e-14);
    // WEIGHT 2 on the same pair: same correlation as FREQ 2, but df stays 4.
    const w2 = try cancorr.analyze(a, &xy, &.{ 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 2 }, 1, 1, 1e-8);
    try approx(f2.r[0], w2.r[0], 1e-14);
    try approx(4, w2.df, 0);
    // Constant weights leave everything unchanged.
    const w3 = try cancorr.analyze(a, &xy, &.{ 1, 1, 1, 1, 1 }, &.{ 3, 3, 3, 3, 3 }, 1, 1, 1e-8);
    try approx(0.8, w3.r[0], 1e-14);
    try approx(4, w3.df, 0);
}

test "STAT-CANCORR-001 BY groups and observation exclusions in the listing" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc cancorr data=s short; var x; with y; freq f; weight w; by g; run;");
    // g=1: the missing-y, FREQ 0.5, WEIGHT 0 and missing-FREQ rows are
    // excluded (pp.2132-2134): r = 0.8, SE = (1-0.64)/sqrt(4) = 0.18.
    // g=2: FREQ 2.7 counts as 2, so r = 0.85 (six pairs, df 5).
    try expect(std.mem.indexOf(u8, out.items, "g=1") != null);
    try expect(std.mem.indexOf(u8, out.items, "g=2") != null);
    try expect(std.mem.indexOf(u8, out.items, "     0.800000") != null);
    try expect(std.mem.indexOf(u8, out.items, "     0.180000") != null);
    try expect(std.mem.indexOf(u8, out.items, "     0.850000") != null);
    // SHORT: only the canonical correlation and multivariate tables.
    try expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Multivariate Statistics"));
    try expect(std.mem.indexOf(u8, out.items, "Raw Canonical") == null);
    out.clearRetainingCapacity();
    try env.run(&out, "proc cancorr data=s noprint; var x; with y; run;");
    try expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-CANCORR-001 repeated VAR / WITH statements accumulate; empty input is a NOTE" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // SAS 9.4: "var a; var c; with b;" analyses VAR = {a, c} (Num DF 2).
    const two = try env.parse("proc cancorr data=s; var x; var z; with y; with w; run;");
    try expectEqual(@as(usize, 2), two.vars.len);
    try expectEqual(@as(usize, 3), two.vars[1]);
    try expectEqual(@as(usize, 2), two.with.len);
    try expectEqual(@as(usize, 5), two.with[1]);
    // SAS 9.4: an empty input prints nothing and notes "No observations in
    // the input data set." (rc 0).
    const e = try env.arena.allocator().create(Dataset);
    e.* = Dataset.init(env.arena.allocator(), "e");
    for ([_][]const u8{ "x", "y" }) |n| _ = try e.addColumn(n, .num);
    try env.lib.put("e", e);
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc cancorr data=e; var x; with y; run;");
    try expectEqual(@as(usize, 0), out.items.len);
    try expect(!env.diags.hasErrors() and !diag.gapHit());
}

test "STAT-CANCORR-001 invalid input and loud gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    const e = try a.create(Dataset);
    e.* = Dataset.init(a, "e");
    for ([_][]const u8{ "x", "y" }) |n| _ = try e.addColumn(n, .num);
    try lib.put("e", e);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        .{ .source = "proc cancorr data=s; var x; run;", .rc = 1 }, // WITH is required
        .{ .source = "proc cancorr data=s; var c; with y; run;", .rc = 1 }, // character VAR
        .{ .source = "proc cancorr data=s; var x; with c; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s; var x; with zz; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s; var x; with y; freq c; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s; var x; with y; weight zz; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s bogus; var x; with y; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s vname=abc; var x; with y; run;", .rc = 1 }, // unquoted
        .{ .source = "proc cancorr data=s singular=1; var x; with y; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s singular=0; var x; with y; run;", .rc = 1 },
        .{ .source = "proc cancorr data=nosuch; var x; with y; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s; var x; with y; bogus; run;", .rc = 1 },
        .{ .source = "proc cancorr data=s out=o; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s outstat=o; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s ncan=1; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s redundancy; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s vdep; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s edf=10; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s mstat=exact; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s short short; var x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s; var x; with y; partial z; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s; var x; var x; with y; run;", .rc = 2 }, // repeated across statements
        .{ .source = "proc cancorr data=s; var x; with y; freq f; freq w; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s; var x; with y; weight w; weight f; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s; var x y; with y; run;", .rc = 2 }, // in both sets
        .{ .source = "proc cancorr data=s; var x x; with y; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s; var x; with y; freq x; run;", .rc = 2 },
        .{ .source = "proc cancorr data=s(where=(g=1 and x<3)); var x; with y; run;", .rc = 2 }, // too few
        // SAS 9.4: "WARNING: The variable w is constant." then "ERROR: A
        // correlation matrix has zero rank."
        .{ .source = "proc cancorr data=s(where=(g=1 and x<9)); var x; with w; run;", .rc = 1 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = cancorr.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expectEqual(@as(usize, 0), output.items.len);
    }
}
