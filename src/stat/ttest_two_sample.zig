//! Two-independent-sample normal-difference TTEST (STAT-TTEST-007).
//! S154 physical pp.10624-10626: pooled, Satterthwaite/Welch, Cochran-Cox,
//! equal-tailed confidence limits and folded-F equality of variances.
//! Inputs are ttest_fit summaries, with FREQ n distinct from precision sum_weights.
//! TEST=RATIO/lognormal transformations and CI=UMPU are not implemented here;
//! the invocation hook must retain visible guards for those distinct methods.
const std = @import("std");
const diag = @import("../diag.zig");
const fit = @import("ttest_fit.zig");
const inference = @import("univ_inference.zig");
const fns = @import("../functions.zig");
const format = @import("../format.zig");
const nan = std.math.nan(f64);
const inf = std.math.inf(f64);
const A = std.mem.Allocator;

pub const Options = struct {
    h0: f64 = 0,
    alpha: f64 = 0.05,
    sides: fit.Sides = .two_sided,
    cochran: bool = false,
};
pub const Comparison = struct {
    estimate: f64,
    std_dev: f64 = nan,
    std_err: f64,
    df: f64,
    t: f64 = nan,
    p: f64 = nan,
    mean_ci: fit.Interval = .{},
    std_dev_ci: fit.Interval = .{},
};
pub const Equality = struct { numerator_df: f64, denominator_df: f64, f: f64 = nan, p: f64 = nan };
pub const Result = struct {
    samples: [2]fit.Result,
    pooled: Comparison,
    satterthwaite: Comparison,
    cochran: ?Comparison,
    equality: Equality,
    options: Options,
};

fn meanInterval(mean: f64, se: f64, df: f64, o: Options) diag.Error!fit.Interval {
    if (!(df > 0)) return .{};
    const tail = if (o.sides == .two_sided) o.alpha / 2 else o.alpha;
    const margin = -inference.tQuantile(tail, df) * se;
    const r: fit.Interval = .{
        .lower = if (o.sides == .lower) -inf else mean - margin,
        .upper = if (o.sides == .upper) inf else mean + margin,
    };
    if ((o.sides != .lower and !std.math.isFinite(r.lower)) or (o.sides != .upper and !std.math.isFinite(r.upper))) return error.ExecError;
    return r;
}

fn sdInterval(sd: f64, df: f64, alpha: f64) diag.Error!fit.Interval {
    if (!(sd > 0 and df > 0)) return .{};
    const v = inference.varianceCI(1, df, .{}, alpha);
    const r: fit.Interval = .{ .lower = sd * @sqrt(df * v.lower), .upper = sd * @sqrt(df * v.upper) };
    if (!std.math.isFinite(r.lower) or !std.math.isFinite(r.upper)) return error.ExecError;
    return r;
}

fn statistic(delta: f64, se: f64) f64 {
    if (se > 0) return delta / se;
    return if (delta == 0) nan else if (delta < 0) -inf else inf;
}

fn comparison(estimate: f64, se: f64, df: f64, o: Options) diag.Error!Comparison {
    if (!std.math.isFinite(estimate) or !std.math.isFinite(se) or se < 0) return error.ExecError;
    const delta = estimate - o.h0;
    if (!std.math.isFinite(delta)) return error.ExecError;
    const t = statistic(delta, se);
    return .{ .estimate = estimate, .std_err = se, .df = df, .t = t, .p = fit.tProbability(t, df, o.sides), .mean_ci = try meanInterval(estimate, se, df, o) };
}

/// Invert the shared small Student tail without subtracting 1-p. Unlike the
/// generic inverse's fixed bracket, expansion reaches very small Cochran tails.
fn critical(two_tail: f64, df: f64, initial: f64) f64 {
    if (two_tail >= 1) return 0;
    if (!(two_tail > 0)) return inf;
    var lo: f64 = 0;
    var hi = @max(1, initial);
    while (fit.tProbability(hi, df, .two_sided) > two_tail) {
        if (hi >= std.math.floatMax(f64) / 2) return inf;
        hi *= 2;
    }
    for (0..100) |_| {
        const mid = lo + (hi - lo) / 2;
        if (mid == lo or mid == hi) break;
        if (fit.tProbability(mid, df, .two_sided) > two_tail) lo = mid else hi = mid;
    }
    return lo + (hi - lo) / 2;
}

/// Cochran-Cox p solves |t| = rho*t_df1(p)+(1-rho)*t_df2(p).
/// Solve on log(p), with the two ordinary t tails as rigorous brackets.
/// The displayed DF is missing when group sample sizes differ (p.10626).
fn cochranProbability(t: f64, df1: f64, df2: f64, rho: f64, sides: fit.Sides) f64 {
    if (std.math.isNan(t)) return nan;
    if (df1 == df2) return fit.tProbability(t, df1, sides);
    if (rho == 0) return fit.tProbability(t, df2, sides);
    if (rho == 1) return fit.tProbability(t, df1, sides);
    const target = @abs(t);
    if (target == 0) return if (sides == .two_sided) 1 else 0.5;
    if (std.math.isInf(target)) return switch (sides) {
        .two_sided => 0,
        .upper => if (t > 0) 0 else 1,
        .lower => if (t < 0) 0 else 1,
    };
    const p1 = fit.tProbability(target, df1, .two_sided);
    const p2 = fit.tProbability(target, df2, .two_sided);
    if (@max(p1, p2) == 0) return switch (sides) {
        .two_sided => 0,
        .upper => if (t > 0) 0 else 1,
        .lower => if (t < 0) 0 else 1,
    };
    var lo = @log(@max(@min(p1, p2), @as(f64, 0x0.0000000000001p-1022)));
    var hi = @log(@max(p1, p2));
    for (0..80) |_| {
        const mid = lo + (hi - lo) / 2;
        const p = @exp(mid);
        const bound = rho * critical(p, df1, target) + (1 - rho) * critical(p, df2, target);
        if (bound > target) lo = mid else hi = mid;
    }
    const p = @exp(lo + (hi - lo) / 2);
    return switch (sides) {
        .two_sided => p,
        .upper => if (t >= 0) p / 2 else 1 - p / 2,
        .lower => if (t <= 0) p / 2 else 1 - p / 2,
    };
}

fn equality(first: fit.Result, second: fit.Result) Equality {
    const large = if (first.std_dev >= second.std_dev) first else second;
    const small = if (first.std_dev >= second.std_dev) second else first;
    var r: Equality = .{ .numerator_df = large.df, .denominator_df = small.df };
    if (large.std_dev == 0) return r; // 0/0 is undefined
    if (small.std_dev == 0) {
        r.f = inf;
        r.p = 0;
        return r;
    }
    const ratio = large.std_dev / small.std_dev;
    r.f = ratio * ratio;
    const inv = small.std_dev / large.std_dev;
    const odds = (small.df / large.df) * inv * inv;
    const x = odds / (1 + odds);
    const upper = if (x > 0) fns.betaI(x, small.df / 2, large.df / 2) else blk: {
        // Preserve representable probabilities even if the F ratio overflows.
        const a = small.df / 2;
        const b = large.df / 2;
        const log_x = @log(small.df / large.df) + 2 * (@log(small.std_dev) - @log(large.std_dev));
        break :blk @exp(a * log_x - @log(a) - fns.lgammaOf(a) - fns.lgammaOf(b) + fns.lgammaOf(a + b));
    };
    r.p = @min(1, 2 * upper);
    return r;
}

fn refreshed(s: fit.Result, o: Options) diag.Error!fit.Result {
    if (s.n < 2 or s.df != @as(f64, @floatFromInt(s.n - 1)) or !std.math.isFinite(s.mean) or
        !std.math.isFinite(s.std_dev) or s.std_dev < 0 or !std.math.isFinite(s.sum_weights) or !(s.sum_weights > 0)) return error.ExecError;
    var r = s;
    r.std_err = s.std_dev / @sqrt(s.sum_weights);
    r.mean_ci = try meanInterval(s.mean, r.std_err, s.df, o);
    r.std_dev_ci = try sdInterval(s.std_dev, s.df, o.alpha);
    return r;
}

/// Allocates nothing. Inputs must have at least two replicated observations per
/// class. Recompute group intervals for the supplied alpha/sides, rather than
/// trusting that upstream summary construction used those same options.
pub fn compute(first: fit.Result, second: fit.Result, o: Options) diag.Error!Result {
    if (!std.math.isFinite(o.h0) or !(o.alpha > 0 and o.alpha < 1) or o.alpha / 2 == 0 or 1 - o.alpha / 2 == 1) return error.ExecError;
    const a = try refreshed(first, o);
    const b = try refreshed(second, o);
    const df = a.df + b.df;
    const difference = a.mean - b.mean;
    // Scaling and hypot avoid squaring huge SDs or SEMs in intermediate steps.
    const pooled_sd = std.math.hypot(a.std_dev * @sqrt(a.df / df), b.std_dev * @sqrt(b.df / df));
    const pooled_se = std.math.hypot(pooled_sd / @sqrt(a.sum_weights), pooled_sd / @sqrt(b.sum_weights));
    var pooled = try comparison(difference, pooled_se, df, o);
    pooled.std_dev = pooled_sd;
    // Physical p.10626 says n1+n2-1 here, but the unchanged SAS oracle uses
    // residual df=n1+n2-2 (20.4992 -> [14.3231,35.9747]); retain verified df.
    pooled.std_dev_ci = try sdInterval(pooled_sd, df, o.alpha);
    const se = std.math.hypot(a.std_err, b.std_err);
    const rho = if (se > 0) (a.std_err / se) * (a.std_err / se) else @as(f64, 0.5);
    const other = if (se > 0) (b.std_err / se) * (b.std_err / se) else @as(f64, 0.5);
    const welch_df = if (se > 0) 1 / (rho * rho / a.df + other * other / b.df) else nan;
    const welch = try comparison(difference, se, welch_df, o);
    var cochran: ?Comparison = null;
    if (o.cochran) cochran = .{
        .estimate = difference,
        .std_err = se,
        .df = if (a.n == b.n) a.df else nan,
        .t = welch.t,
        .p = cochranProbability(welch.t, a.df, b.df, rho, o.sides),
    };
    return .{ .samples = .{ a, b }, .pooled = pooled, .satterthwaite = welch, .cochran = cochran, .equality = equality(a, b), .options = o };
}

fn num(a: A, x: f64, spec: []const u8) diag.Error![]const u8 {
    if (std.math.isInf(x)) return if (x < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}

/// Four separate renderers preserve existing Statistics/ConfLimits/TTests/
/// Equality ODS selection boundaries. Labels are already formatted CLASS levels.
pub fn statistics(a: A, out: *std.ArrayList(u8), r: Result, class_name: []const u8, labels: [2][]const u8, summary: bool) diag.Error!void {
    try out.print(a, "{s} Method N Mean Std Dev Std Err", .{class_name});
    if (!summary) try out.appendSlice(a, " Minimum Maximum");
    try out.appendSlice(a, "\n\n");
    for (r.samples, labels) |s, label| {
        try out.print(a, "{s} {s} {s} {s} {s}", .{ label, try num(a, @floatFromInt(s.n), "best12."), try num(a, s.mean, "d8.3"), try num(a, s.std_dev, "d8.3"), try num(a, s.std_err, "d8.3") });
        if (!summary) try out.print(a, " {s} {s}", .{ try num(a, s.minimum, "d8.3"), try num(a, s.maximum, "d8.3") });
        try out.appendSlice(a, "\n");
    }
    try out.print(a, "Diff (1-2) Pooled {s} {s} {s}\nDiff (1-2) Satterthwaite {s} {s}\n\n", .{
        try num(a, r.pooled.estimate, "d8.3"),        try num(a, r.pooled.std_dev, "d8.3"),        try num(a, r.pooled.std_err, "d8.3"),
        try num(a, r.satterthwaite.estimate, "d8.3"), try num(a, r.satterthwaite.std_err, "d8.3"),
    });
}

pub fn intervals(a: A, out: *std.ArrayList(u8), r: Result, class_name: []const u8, labels: [2][]const u8, show_sd_ci: bool) diag.Error!void {
    const level = try num(a, 100 * (1 - r.options.alpha), "best8.");
    try out.print(a, "{s} Method Mean {s}% CL Mean Std Dev", .{ class_name, level });
    if (show_sd_ci) try out.print(a, " {s}% CL Std Dev", .{level});
    try out.appendSlice(a, "\n\n");
    for (r.samples, labels) |s, label| {
        try out.print(a, "{s} {s} {s} {s} {s}", .{ label, try num(a, s.mean, "d8.3"), try num(a, s.mean_ci.lower, "d8.3"), try num(a, s.mean_ci.upper, "d8.3"), try num(a, s.std_dev, "d8.3") });
        if (show_sd_ci) try out.print(a, " {s} {s}", .{ try num(a, s.std_dev_ci.lower, "d8.3"), try num(a, s.std_dev_ci.upper, "d8.3") });
        try out.appendSlice(a, "\n");
    }
    const p = r.pooled;
    try out.print(a, "Diff (1-2) Pooled {s} {s} {s} {s}", .{ try num(a, p.estimate, "d8.3"), try num(a, p.mean_ci.lower, "d8.3"), try num(a, p.mean_ci.upper, "d8.3"), try num(a, p.std_dev, "d8.3") });
    if (show_sd_ci) try out.print(a, " {s} {s}", .{ try num(a, p.std_dev_ci.lower, "d8.3"), try num(a, p.std_dev_ci.upper, "d8.3") });
    const w = r.satterthwaite;
    try out.print(a, "\nDiff (1-2) Satterthwaite {s} {s} {s}\n\n", .{ try num(a, w.estimate, "d8.3"), try num(a, w.mean_ci.lower, "d8.3"), try num(a, w.mean_ci.upper, "d8.3") });
}

fn testRow(a: A, out: *std.ArrayList(u8), method: []const u8, variances: []const u8, r: Comparison) diag.Error!void {
    try out.print(a, "{s} {s} {s} {s} {s}\n", .{ method, variances, try num(a, r.df, "best6."), try num(a, r.t, "8.2"), try num(a, r.p, "pvalue6.4") });
}
pub fn tests(a: A, out: *std.ArrayList(u8), r: Result) diag.Error!void {
    const tail: []const u8 = switch (r.options.sides) {
        .two_sided => "Pr > |t|",
        .upper => "Pr > t",
        .lower => "Pr < t",
    };
    try out.print(a, "Method Variances DF t Value {s}\n\n", .{tail});
    try testRow(a, out, "Pooled", "Equal", r.pooled);
    try testRow(a, out, "Satterthwaite", "Unequal", r.satterthwaite);
    if (r.cochran) |c| try testRow(a, out, "Cochran", "Unequal", c);
    try out.appendSlice(a, "\n");
}
pub fn equalityTable(a: A, out: *std.ArrayList(u8), r: Result) diag.Error!void {
    const e = r.equality;
    try out.print(a, "Equality of Variances\n\nMethod Num DF Den DF F Value Pr > F\n\nFolded F {s} {s} {s} {s}\n\n", .{
        try num(a, e.numerator_df, "best8."), try num(a, e.denominator_df, "best8."), try num(a, e.f, "8.2"), try num(a, e.p, "pvalue6.4"),
    });
}

const oracle_first = [_]f64{ 43, 90, 84, 87, 116, 95 };
const oracle_second = [_]f64{ 86, 99, 93, 92, 121, 71 };
fn oracleResult() !Result {
    return compute(try fit.oneSample(&oracle_first, null, null, .{}), try fit.oneSample(&oracle_second, null, null, .{}), .{ .cochran = true });
}

test "TWO_SAMPLE original complete table oracle tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try oracleResult();
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "The TTEST Procedure\n\nVariable: x\n\n");
    try statistics(a, &out, r, "group", .{ "A", "B" }, false);
    try intervals(a, &out, r, "group", .{ "A", "B" }, true);
    try tests(a, &out, r);
    try equalityTable(a, &out, r);
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/STAT15.4-oracle/STAT-TTEST-007/two_sample_variance.expected.txt", a, .limited(1024 * 1024));
    var e = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t\x0c");
    while (e.next()) |word| try std.testing.expectEqualStrings(word, actual.next() orelse "<missing>");
    try std.testing.expect(actual.next() == null);
}

test "TWO_SAMPLE oracle numeric pooled Welch Cochran and variance equality" {
    const r = try oracleResult();
    // Printed four-decimal fields use half-display-unit tolerances; these
    // bounds do not replace the independent high-precision checks below.
    try std.testing.expectApproxEqAbs(@as(f64, -7.8333), r.pooled.estimate, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 20.4992), r.pooled.std_dev, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 11.8352), r.pooled.std_err, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 8.8705), r.satterthwaite.df, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5230), r.pooled.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5249), r.satterthwaite.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5373), r.cochran.?.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4320), r.equality.p, 0.00005);
}

test "TWO_SAMPLE independent hand computation precision weights and scale invariance" {
    // A=(1,2,3), B=(3,4,5): each sample variance=1, df=2.
    // Difference=-2, pooled/Welch SE=sqrt(2/3), df=4, F=1, F tail=1.
    const a = try fit.oneSample(&.{ 1, 2, 3 }, null, null, .{});
    const b = try fit.oneSample(&.{ 3, 4, 5 }, null, null, .{});
    const r = try compute(a, b, .{ .cochran = true });
    try std.testing.expectApproxEqAbs(@as(f64, -2), r.pooled.estimate, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.pooled.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.0 / 3.0)), r.pooled.std_err, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 4), r.satterthwaite.df, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.equality.f, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.equality.p, 1e-13);
    // Student(2) two-tail at sqrt(6): 1-sqrt(3)/2 (Cochran df=2).
    try std.testing.expectApproxEqAbs(1 - @sqrt(@as(f64, 3)) / 2, r.cochran.?.p, 1e-13);
    const wa = try fit.oneSample(&.{ 1, 2, 3 }, null, &.{ 4, 4, 4 }, .{});
    const wb = try fit.oneSample(&.{ 3, 4, 5 }, null, &.{ 4, 4, 4 }, .{});
    const weighted = try compute(wa, wb, .{ .cochran = true });
    try std.testing.expectApproxEqAbs(2 * r.pooled.std_dev, weighted.pooled.std_dev, 1e-13);
    try std.testing.expectApproxEqAbs(r.pooled.std_err, weighted.pooled.std_err, 1e-13);
    try std.testing.expectApproxEqAbs(r.satterthwaite.df, weighted.satterthwaite.df, 1e-13);
    try std.testing.expectApproxEqAbs(r.cochran.?.p, weighted.cochran.?.p, 1e-13);
}

test "TWO_SAMPLE sided tests H0 and swapping class order" {
    const a = try fit.oneSample(&oracle_first, null, null, .{});
    const b = try fit.oneSample(&oracle_second, null, null, .{});
    const lower = try compute(a, b, .{ .h0 = 2, .sides = .lower, .cochran = true });
    const upper = try compute(b, a, .{ .h0 = -2, .sides = .upper, .cochran = true });
    try std.testing.expectApproxEqAbs(lower.pooled.p, upper.pooled.p, 1e-13);
    try std.testing.expectApproxEqAbs(lower.satterthwaite.p, upper.satterthwaite.p, 1e-13);
    try std.testing.expectApproxEqAbs(lower.cochran.?.p, upper.cochran.?.p, 1e-13);
    try std.testing.expectEqual(-inf, lower.pooled.mean_ci.lower);
    try std.testing.expectEqual(inf, upper.pooled.mean_ci.upper);
    try std.testing.expectApproxEqAbs(-lower.pooled.mean_ci.upper, upper.pooled.mean_ci.lower, 1e-12);
    try std.testing.expectApproxEqAbs(lower.equality.p, upper.equality.p, 1e-13);
}

test "TWO_SAMPLE degenerate variance and invalid summary inputs" {
    const constant = try fit.oneSample(&.{ 1, 1, 1 }, null, null, .{});
    const varying = try fit.oneSample(&.{ 1, 2, 3 }, null, null, .{});
    const r = try compute(constant, varying, .{ .cochran = true });
    try std.testing.expectApproxEqAbs(@as(f64, 2), r.satterthwaite.df, 1e-13);
    try std.testing.expectEqual(inf, r.equality.f);
    try std.testing.expectEqual(@as(f64, 0), r.equality.p);
    try std.testing.expectApproxEqAbs(r.satterthwaite.p, r.cochran.?.p, 1e-13);
    const same = try compute(constant, constant, .{});
    try std.testing.expect(std.math.isNan(same.pooled.t) and std.math.isNan(same.equality.p));
    var bad = varying;
    bad.sum_weights = 0;
    try std.testing.expectError(error.ExecError, compute(bad, varying, .{}));
    try std.testing.expectError(error.ExecError, compute(varying, varying, .{ .alpha = 0 }));
    try std.testing.expectError(error.ExecError, compute(varying, varying, .{ .h0 = inf }));
    const single = try fit.oneSample(&.{1}, null, null, .{});
    try std.testing.expectError(error.ExecError, compute(single, varying, .{}));
}

test "TWO_SAMPLE very unequal n3 n300 independent formulas and live SAS reference" {
    // A=(1,2,3), B=(3,4,5) repeated 100 times: means 2 and 4,
    // CSS=2 and 200. Reference values independently obtained with SAS 9.4
    // ODS TTests/Equality/ConfLimits BEST32. on 2026-11-25.
    const a = try fit.fromSummary(3, 2, 1, .{});
    const b = try fit.fromSummary(300, 4, @sqrt(@as(f64, 200.0 / 299.0)), .{});
    const r = try compute(a, b, .{ .cochran = true });
    const v1: f64 = 1.0 / 3.0;
    const v2: f64 = 2.0 / 897.0;
    const df = (v1 + v2) * (v1 + v2) / (v1 * v1 / 2 + v2 * v2 / 299);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 202.0 / 301.0)), r.pooled.std_dev, 1e-13);
    try std.testing.expectApproxEqAbs(df, r.satterthwaite.df, 1e-12);
    try std.testing.expectEqual(@as(f64, 301), r.pooled.df);
    try std.testing.expect(std.math.isNan(r.cochran.?.df));
    try std.testing.expectApproxEqAbs(@as(f64, -4.20762957641104), r.pooled.t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -3.45257379077274), r.satterthwaite.t, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00003409602125), r.pooled.p, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.07322332062955), r.satterthwaite.p, 1e-11);
    // Independent 128-node Gauss-Legendre integration of the t(299) density,
    // with the elementary t(2) inverse, gives this equation-based root.
    try std.testing.expectApproxEqAbs(@as(f64, 0.07419586760210986), r.cochran.?.p, 1e-12);
    // SAS differs by 3.405e-9 here; retain a separate, narrowly bounded check
    // rather than weakening the independent root check or matching its rounding.
    try std.testing.expectApproxEqAbs(@as(f64, 0.07419587100656), r.cochran.?.p, 5e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4518399377042), r.equality.p, 1e-11);
    try std.testing.expectApproxEqAbs(@as(f64, -2.93538487433307), r.pooled.mean_ci.lower, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -4.4610633597195), r.satterthwaite.mean_ci.lower, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.758665434156), r.pooled.std_dev_ci.lower, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.89032469936905), r.pooled.std_dev_ci.upper, 1e-10);
    const reversed = try compute(b, a, .{ .cochran = true });
    try std.testing.expectApproxEqAbs(r.cochran.?.p, reversed.cochran.?.p, 1e-12);
    try std.testing.expectApproxEqAbs(r.equality.p, reversed.equality.p, 1e-12);
}
