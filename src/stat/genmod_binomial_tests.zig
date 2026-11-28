//! STAT-GENMOD-003 permanent tests: binomial-logit kernel, GLM-parameterization
//! design matrix with CLASS levels, aliasing, likelihood-ratio limits, the MODEL
//! option table and the loud boundaries. Data are invented (D-011); every
//! expected value is hand-derived in the comment next to it.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const genmod = @import("genmod.zig");
const logit = @import("genmod_logit.zig");
const k = @import("genmod_binomial.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const near = std.testing.expectApproxEqAbs;

test "STAT-GENMOD-003 kernel: saturated two-group logit equals the closed form" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Groups 3/10 and 6/10, columns intercept and group-2 indicator.
    const x = [_]f64{ 1, 0, 1, 1 };
    const r = [_]f64{ 3, 6 };
    const n = [_]f64{ 10, 10 };
    const f = try k.fitLogit(a, &x, &r, &n, 2);
    // b0 = logit(0.3) = ln(3/7); b1 = logit(0.6) - logit(0.3) = ln(3.5).
    try near(@log(3.0 / 7.0), f.beta[0], 1e-9);
    try near(@log(3.5), f.beta[1], 1e-9);
    // Inverse information: var(b0) = 1/(10*.3*.7), var(b1) = 1/2.1 + 1/(10*.6*.4), cov = -1/2.1.
    try near(1.0 / 2.1, f.cov[0], 1e-9);
    try near(-1.0 / 2.1, f.cov[1], 1e-9);
    try near(1.0 / 2.1 + 1.0 / 2.4, f.cov[3], 1e-9);
    // l = 3 ln.3 + 7 ln.7 + 6 ln.6 + 4 ln.4; full adds ln C(10,3) + ln C(10,6) = ln 120 + ln 210.
    const l = 3 * @log(0.3) + 7 * @log(0.7) + 6 * @log(0.6) + 4 * @log(0.4);
    try near(l, f.loglik, 1e-9);
    try near(l + @log(120.0) + @log(210.0), f.full_loglik, 1e-9);
    // A saturated model reproduces the counts.
    try near(0, f.deviance, 1e-9);
    try near(0, f.pearson, 1e-9);
}

test "STAT-GENMOD-003 kernel: intercept-only deviance, Pearson chi-square and zero cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 1/4 and 3/4: pooled p = 4/8 = 0.5, so the intercept is 0 and each fitted count is 2.
    const f = try k.fitLogit(a, &.{ 1, 1 }, &.{ 1, 3 }, &.{ 4, 4 }, 1);
    try near(0, f.beta[0], 1e-9);
    // D = 2[1 ln(1/2) + 3 ln(3/2) + 3 ln(3/2) + 1 ln(1/2)] = 12 ln 1.5 - 4 ln 2.
    try near(12 * @log(1.5) - 4 * @log(2.0), f.deviance, 1e-9);
    // X2 = (1-2)^2/(4*.25) + (3-2)^2/(4*.25) = 2.
    try near(2, f.pearson, 1e-9);
    // var = 1/(8 * .25) = 0.5.
    try near(0.5, f.cov[0], 1e-9);
    // 0/4 and 4/4 (0 log 0 = 0): p = 0.5, D = 2[4 ln 2 + 4 ln 2] = 16 ln 2.
    try near(16 * @log(2.0), k.deviance(&.{ 1, 1 }, &.{ 0, 4 }, &.{ 4, 4 }, 1, &.{0}), 1e-12);
    // No events at all: the maximum is at minus infinity, never a finite estimate.
    try std.testing.expectError(error.NotConverged, k.fitLogit(a, &.{ 1, 1 }, &.{ 0, 0 }, &.{ 4, 4 }, 1));
    // p.3544 validity rule.
    try expect(k.validObservation(0, 1) and k.validObservation(2.5, 2.5));
    try expect(!k.validObservation(-1, 3) and !k.validObservation(4, 3) and !k.validObservation(0, 0));
}

test "STAT-GENMOD-003 kernel: aliased columns in model order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Columns: intercept, x, level a, level b, level c, copy of x.
    // a + b + c = intercept, so c (the last level) depends on preceding columns;
    // the copy of x depends on x. Nothing else is dependent.
    const x = [_]f64{
        1, 0.5, 1, 0, 0, 0.5,
        1, 1.5, 1, 0, 0, 1.5,
        1, 2.0, 0, 1, 0, 2.0,
        1, 4.0, 0, 1, 0, 4.0,
        1, 3.0, 0, 0, 1, 3.0,
        1, 7.0, 0, 0, 1, 7.0,
    };
    const flags = try k.aliased(arena.allocator(), &x, 6, 6, k.singular_default);
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, false, true, true }, flags);
}

test "STAT-GENMOD-003 kernel: likelihood-ratio limits solve the profile equation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const chi: f64 = 3.841458820694124; // chi-square(0.95; 1)
    // Two groups with a group indicator. With the intercept fixed at b the
    // indicator still fits group 2 exactly, so the profile for the intercept is
    // group 1's own likelihood: l1(b) = 3 b - 10 ln(1 + e^b), maximum at ln(3/7).
    const x = [_]f64{ 1, 0, 1, 1 };
    const r = [_]f64{ 3, 6 };
    const n = [_]f64{ 10, 10 };
    const f = try k.fitLogit(a, &x, &r, &n, 2);
    const top = 3 * @log(0.3) + 7 * @log(0.7);
    const lo = try k.profileLimit(a, &x, &r, &n, f, 0, false, chi);
    const hi = try k.profileLimit(a, &x, &r, &n, f, 0, true, chi);
    try expect(lo < f.beta[0] and f.beta[0] < hi);
    for ([_]f64{ lo, hi }) |b| try near(chi, 2 * (top - (3 * b - 10 * @log(1 + @exp(b)))), 1e-8);
    // The interval is not symmetric (p = 0.3 is off-centre): the lower arm is longer.
    try expect(f.beta[0] - lo > hi - f.beta[0]);
    // The documented quadratic iteration stops once |l - l0| <= CICONV = 1E-4,
    // i.e. 2 (l_max - l) within 2E-4 of the quantile, on the same side as the exact root.
    for ([_]bool{ false, true }, [_]f64{ lo, hi }) |side, exact| {
        const b = (try k.quadraticLimit(a, &x, &r, &n, f, 0, side, chi, k.ciconv_default)).?;
        try near(chi, 2 * (top - (3 * b - 10 * @log(1 + @exp(b)))), 2e-4);
        try near(exact, b, 1e-3);
    }
}

const Row = struct { c: []const u8, x: f64, r: f64, n: f64 };
// Level a: 3/10 twice; level b: 6/10 twice. x is unused by the main fit.
const sample = [_]Row{
    .{ .c = "b", .x = 1, .r = 6, .n = 10 },
    .{ .c = "a", .x = 2, .r = 3, .n = 10 },
    .{ .c = "a", .x = 4, .r = 3, .n = 10 },
    .{ .c = "b", .x = 8, .r = 6, .n = 10 },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env, rows: []const Row) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "sample");
        _ = try ds.addColumn("c", .char);
        for ([_][]const u8{ "x", "r", "n" }) |name| _ = try ds.addColumn(name, .num);
        for (rows) |row| try ds.appendRow(&.{ .{ .str = row.c }, .{ .num = row.x }, .{ .num = row.r }, .{ .num = row.n } });
        try self.lib.put("sample", ds);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn tokens(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
};

test "STAT-GENMOD-003 design matrix: intercept, covariate and one indicator per CLASS level" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init(&sample);
    const s = try genmod.parse(e.cx(), try e.tokens("proc genmod data=sample; class c; model r/n = x c / dist=bin; run;"));
    const sel = try genmod.prepare(e.cx(), s, s.input.ds.rows.items);
    const d = try logit.design(e.arena.allocator(), s, sel, s.input.ds.rows.items);
    // Levels sort a, b (formatted order), whatever the data order. Columns:
    // Intercept, x, c=a, c=b; rows in data order b, a, a, b.
    try expectEqual(@as(usize, 4), d.p);
    try std.testing.expectEqualSlices(f64, &.{
        1, 1, 0, 1,
        1, 2, 1, 0,
        1, 4, 1, 0,
        1, 8, 0, 1,
    }, d.x);
    try expect(d.columns[0].level == null and d.columns[1].level.? == 0 and d.columns[2].level.? == 1);
    // Effect order follows the MODEL statement, not the CLASS statement.
    const s2 = try genmod.parse(e.cx(), try e.tokens("proc genmod data=sample; class c; model r/n = c x / dist=bin; run;"));
    const d2 = try logit.design(e.arena.allocator(), s2, sel, s2.input.ds.rows.items);
    try std.testing.expectEqualSlices(f64, &.{ 1, 0, 1, 1 }, d2.x[0..4]);
}

test "STAT-GENMOD-003 CLASS fit listing: reference level row, counts and criteria" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init(&sample);
    var out: std.ArrayList(u8) = .empty;
    try genmod.run(e.cx(), &out, try e.tokens("proc genmod data=sample; class c; model r/n = c / dist=bin link=logit; run;"));
    const text = out.items;
    const wanted = [_][]const u8{
        "Response Variable (Events)              r", // value column as wide as WORK.SAMPLE
        "Number of Events                     18", // 6+3+3+6
        "Number of Trials                     40",
        "c               2    a b",
        "       2    Nonevent           22",
        // The class means are fitted exactly: deviance 0 on 4 - 2 = 2 DF.
        "Deviance                       2          0.0000          0.0000",
        // l = 2(3 ln.3 + 7 ln.7) + 2(6 ln.6 + 4 ln.4) = -25.6775
        "Log Likelihood                          -25.6775",
        // + 2 ln 120 + 2 ln 210 = 20.2692 -> -5.4083
        "Full Log Likelihood                      -5.4083",
        // AIC = 10.8166 + 2*2; AICC = AIC + 2*2*3/(4-2-1); BIC = 10.8166 + 2 ln 4
        "AIC (smaller is better)                  14.8166",
        "AICC (smaller is better)                 26.8166",
        "BIC (smaller is better)                  13.5892",
        "Wald 95% Confidence",
        // Intercept = logit(0.6) = ln 1.5 = 0.4055, se = sqrt(1/(20*.6*.4)) = 0.4564,
        // limits 0.4055 -/+ 1.959964*0.4564 = -0.4891, 1.3001; chi = (0.4055/0.4564)^2 = 0.79
        "Intercept          1      0.4055      0.4564     -0.4891      1.3001          0.79",
        // c a = logit(.3) - logit(.6) = ln(2/7) = -1.2528, se = sqrt(1/4.8 + 1/4.2) = 0.6682
        "c            a     1     -1.2528      0.6682",
        "c            b     0      0.0000      0.0000      0.0000      0.0000           .           .",
        "Scale              0      1.0000      0.0000      1.0000      1.0000",
        "NOTE: The scale parameter was held fixed.",
    };
    for (wanted) |w| expect(std.mem.indexOf(u8, text, w) != null) catch |err| {
        std.debug.print("missing: {s}\n---\n{s}\n", .{ w, text });
        return err;
    };
    // LRCI changes only the heading and the two limit columns: no extra table.
    var lr: std.ArrayList(u8) = .empty;
    try genmod.run(e.cx(), &lr, try e.tokens("proc genmod data=sample; class c; model r/n = c / dist=bin lrci; run;"));
    try expect(std.mem.indexOf(u8, lr.items, "Likelihood Ratio 95%") != null);
    try expect(std.mem.indexOf(u8, lr.items, "Wald 95% Confidence") == null);
    try expect(std.mem.indexOf(u8, lr.items, "Intercept          1      0.4055      0.4564") != null);
    try expectEqual(std.mem.count(u8, text, "\n"), std.mem.count(u8, lr.items, "\n"));
}

test "STAT-GENMOD-003 MODEL option table and loud boundaries" {
    try expect(logit.modelOption("LRCI").?.owner.len == 0);
    try expect(logit.modelOption("WaldCI").?.owner.len == 0);
    try expect(logit.modelOption("type3").?.owner.len > 0);
    try expect(logit.modelOption("frobnicate") == null);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // rc 1: not a MODEL option at all (binomial and Normal paths).
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin frobnicate; run;", .rc = 1 },
        .{ .source = "proc genmod; model r = x / frobnicate; run;", .rc = 1 },
        // rc 2: documented, not implemented or not verified.
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin type3; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin alpha=0.1 lrci; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin noint; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin lrci waldci; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin link=probit; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=poisson; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c; run;", .rc = 2 }, // no DIST=
        .{ .source = "proc genmod; class c; model r/n = c x x / dist=bin; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin; by n; run;", .rc = 2 }, // n is constant: one BY group
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin; freq x; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin; output out=o pred=p; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c / dist=bin; zeromodel x; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r(event='1') = c / dist=bin; run;", .rc = 2 },
        .{ .source = "proc genmod; class c(ref='a'); model r/n = c / dist=bin; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r/n = c*x / dist=bin; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model r = c / dist=bin; run;", .rc = 2 }, // single-trial response
        .{ .source = "proc genmod; class c; model r = c; run;", .rc = 2 }, // CLASS in a Normal model
        // trials < events in every row: invalid observations are not silently dropped.
        .{ .source = "proc genmod; class c; model n/r = c / dist=bin; run;", .rc = 2 },
        // x and n are proportional to nothing here, but 4 parameters on 4 rows leave no DF.
        .{ .source = "proc genmod; class c; model r/n = c x n / dist=bin; run;", .rc = 2 },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (cases) |case| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(arena.allocator()) };
        try e.init(&sample);
        diag.resetGap();
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const result = genmod.run(e.cx(), &out, try e.tokens(case.source));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), e.diags.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        // Fail loud means nothing printed for the step.
        try expectEqual(@as(usize, 0), out.items.len);
    }
}

test "STAT-GENMOD-003 separation is a loud gap, never a finite estimate" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    // Level a has no events: its coefficient runs to minus infinity.
    try e.init(&.{
        .{ .c = "a", .x = 1, .r = 0, .n = 10 },
        .{ .c = "a", .x = 2, .r = 0, .n = 10 },
        .{ .c = "b", .x = 3, .r = 6, .n = 10 },
        .{ .c = "b", .x = 4, .r = 5, .n = 10 },
    });
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, genmod.run(e.cx(), &out, try e.tokens("proc genmod data=sample; class c; model r/n = c / dist=bin; run;")));
    try expect(diag.gapHit());
    try expectEqual(@as(usize, 0), out.items.len);
}
