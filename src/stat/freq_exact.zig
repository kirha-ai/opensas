//! Shared exact primitives for FREQ risk and exact integrations (D-029).
//! These kernels do not accept SAS syntax or render output. Counts must already
//! reflect the table layer's ordering, missing-value, and weight policies.
const std = @import("std");
const math = @import("../functions.zig");
pub const Error = @import("../diag.zig").Error;
pub const Interval = struct { lower: f64, upper: f64 };
pub const OddsResult = union(enum) { complete: Interval, exhausted };

/// Public adapters must call this before any float-to-integer cast. No rounding
/// tolerance: fractional weights are not frequencies for exact reference sets.
pub fn integerCount(value: f64) Error!u32 {
    if (!std.math.isFinite(value) or value < 0 or value > std.math.maxInt(u32) or @floor(value) != value) return error.ExecError;
    return @intFromFloat(value);
}
pub const Tails = struct { point: f64, left: f64, right: f64 };
pub const Binomial = struct { tails: Tails, one_sided: f64, two_sided: f64, mid_p: f64, limits: Interval };
pub const BinomialResult = union(enum) { complete: Binomial, exhausted };

/// Clock ownership stays in the execution adapter; avoids platform-specific
/// timing and dependency cycles in numerical primitives.
pub const Control = struct {
    context: ?*const anyopaque = null,
    expired: ?*const fn (?*const anyopaque) bool = null,
    pub fn stopped(self: Control) bool {
        return if (self.expired) |f| f(self.context) else false;
    }
};
fn validAlpha(alpha: f64) bool {
    return std.math.isFinite(alpha) and alpha > 0 and alpha < 1;
}
fn choose(n: f64, k: f64) f64 {
    return math.lgammaOf(n + 1) - math.lgammaOf(k + 1) - math.lgammaOf(n - k + 1);
}

/// Inclusive tails; exposed separately for noninferiority/equivalence callers.
/// Compute each tail directly (never subtract a nearly-one CDF).
pub fn binomialTails(k: u32, n: u32, p: f64) Error!Tails {
    if (n == 0 or k > n or !std.math.isFinite(p) or p < 0 or p > 1) return error.ExecError;
    if (p == 0) return .{ .point = if (k == 0) 1 else 0, .left = 1, .right = if (k == 0) 1 else 0 };
    if (p == 1) return .{ .point = if (k == n) 1 else 0, .left = if (k == n) 1 else 0, .right = 1 };
    const nf: f64 = @floatFromInt(n);
    const kf: f64 = @floatFromInt(k);
    return .{
        .point = @min(1, @exp(choose(nf, kf) + kf * @log(p) + (nf - kf) * std.math.log1p(-p))),
        .left = if (k == n) 1 else math.betaI(1 - p, nf - kf, kf + 1),
        .right = if (k == 0) 1 else math.betaI(p, kf, nf - kf + 1),
    };
}

/// SAS/STAT FREQ pp.176,179–180: equal-tail Clopper-Pearson or mid-p
/// inversion. Exact binomial two-sided p is twice the smaller inclusive tail,
/// unlike Fisher's probability ordering. The separately reported binomial
/// mid-p adjusts the one-sided value; the ordinary p-values remain unchanged.
pub fn binomial(k: u32, n: u32, p0: f64, alpha: f64, midp: bool) Error!Binomial {
    return (try binomialControlled(k, n, p0, alpha, midp, .{})).complete;
}
pub fn binomialControlled(k: u32, n: u32, p0: f64, alpha: f64, midp: bool, control: Control) Error!BinomialResult {
    if (!validAlpha(alpha)) return error.ExecError;
    if (control.stopped()) return .exhausted;
    const tails = try binomialTails(k, n, p0);
    const one = @min(tails.left, tails.right);
    var limits = Interval{ .lower = 0, .upper = 1 };
    if (k > 0) limits.lower = (try binomialLimitControlled(k, n, alpha / 2, midp, true, control)) orelse return .exhausted;
    if (k < n) limits.upper = (try binomialLimitControlled(k, n, alpha / 2, midp, false, control)) orelse return .exhausted;
    return .{ .complete = .{ .tails = tails, .one_sided = one, .two_sided = @min(1, 2 * one), .mid_p = @max(0, one - tails.point / 2), .limits = limits } };
}
/// Exact NI/TOST limits invert each one-sided test at alpha, hence nominal
/// confidence 1-2*alpha. Keep the full 0<alpha<1 SAS option range; discreteness
/// can leave overlapping limits even when nominal confidence is nonpositive.
pub fn binomialOneSidedLimits(k: u32, n: u32, alpha: f64, control: Control) Error!OddsResult {
    if (n == 0 or k > n or !validAlpha(alpha)) return error.ExecError;
    if (control.stopped()) return .exhausted;
    var limits = Interval{ .lower = 0, .upper = 1 };
    if (k > 0) limits.lower = (try binomialLimitControlled(k, n, alpha, false, true, control)) orelse return .exhausted;
    if (k < n) limits.upper = (try binomialLimitControlled(k, n, alpha, false, false, control)) orelse return .exhausted;
    return .{ .complete = limits };
}

fn binomialLimit(k: u32, n: u32, target: f64, midp: bool, lower: bool) Error!f64 {
    return (try binomialLimitControlled(k, n, target, midp, lower, .{})).?;
}
fn binomialLimitControlled(k: u32, n: u32, target: f64, midp: bool, lower: bool, control: Control) Error!?f64 {
    var lo: f64 = 0;
    var hi: f64 = 1;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const p = (lo + hi) / 2;
        const t = try binomialTails(k, n, p);
        const tail = (if (lower) t.right else t.left) - (if (midp) t.point / 2 else 0);
        if ((tail < target) == lower) lo = p else hi = p;
    }
    return (lo + hi) / 2;
}

/// Noncentral hypergeometric support for a row-major 2x2 table. A maximum
/// support length is an explicit caller resource budget, not an approximation.
pub const OddsDistribution = struct {
    lo: u32,
    hi: u32,
    observed: u32,
    row: u64,
    col: u64,
    total: u64,

    pub fn init(cells: [4]u32) Error!OddsDistribution {
        const row = @as(u64, cells[0]) + cells[1];
        const col = @as(u64, cells[0]) + cells[2];
        const total = row + cells[2] + cells[3];
        if (row == 0 or col == 0 or row == total or col == total or @min(row, col) > std.math.maxInt(u32)) return error.ExecError;
        return .{ .lo = @intCast((row + col) -| total), .hi = @intCast(@min(row, col)), .observed = cells[0], .row = row, .col = col, .total = total };
    }
    pub fn logWeight(self: OddsDistribution, x: u32, log_odds: f64) f64 {
        const xf: f64 = @floatFromInt(x);
        const rf: f64 = @floatFromInt(self.row);
        const cf: f64 = @floatFromInt(self.col);
        const nf: f64 = @floatFromInt(self.total);
        return choose(cf, xf) + choose(nf - cf, rf - xf) + @as(f64, @floatFromInt(x - self.lo)) * log_odds;
    }
    pub fn tails(self: OddsDistribution, log_odds: f64, max_support: u64) Error!Tails {
        return (try self.tailsControlled(log_odds, max_support, .{})).?;
    }
    pub fn tailsControlled(self: OddsDistribution, log_odds: f64, max_support: u64, control: Control) Error!?Tails {
        if (!std.math.isFinite(log_odds) or @as(u64, self.hi) - self.lo + 1 > max_support) return error.ExecError;
        // Normalize with log-sum-exp, retaining precision at extreme odds.
        var peak: f64 = -std.math.inf(f64);
        var x: u64 = self.lo;
        while (x <= self.hi) : (x += 1) {
            if (control.stopped()) return null;
            peak = @max(peak, self.logWeight(@intCast(x), log_odds));
        }
        var total: f64 = 0;
        var out = Tails{ .point = 0, .left = 0, .right = 0 };
        x = self.lo;
        while (x <= self.hi) : (x += 1) {
            if (control.stopped()) return null;
            const w = @exp(self.logWeight(@intCast(x), log_odds) - peak);
            total += w;
            if (x == self.observed) out.point = w;
            if (x <= self.observed) out.left += w;
            if (x >= self.observed) out.right += w;
        }
        out.point /= total;
        out.left /= total;
        out.right /= total;
        return out;
    }
};

/// SAS/STAT pp.201–202: at observed OR=0/infinity, the finite endpoint
/// uses alpha, NOT alpha/2. Zero margins are undefined, not infinite odds.
pub fn oddsRatio(cells: [4]u32, alpha: f64, midp: bool, max_support: u64) Error!OddsResult {
    return oddsRatioControlled(cells, alpha, midp, max_support, .{});
}
pub fn oddsRatioControlled(cells: [4]u32, alpha: f64, midp: bool, max_support: u64, control: Control) Error!OddsResult {
    if (!validAlpha(alpha)) return error.ExecError;
    const d = try OddsDistribution.init(cells);
    if (@as(u64, d.hi) - d.lo + 1 > max_support) return .exhausted;
    if (control.stopped()) return .exhausted;
    const boundary = d.observed == d.lo or d.observed == d.hi;
    const target = if (boundary) alpha else alpha / 2;
    var limits = Interval{ .lower = 0, .upper = std.math.inf(f64) };
    if (d.observed != d.lo) limits.lower = (try oddsLimit(d, target, midp, true, max_support, control)) orelse return .exhausted;
    if (d.observed != d.hi) limits.upper = (try oddsLimit(d, target, midp, false, max_support, control)) orelse return .exhausted;
    return .{ .complete = limits };
}

fn oddsLimit(d: OddsDistribution, target: f64, midp: bool, lower: bool, budget: u64, control: Control) Error!?f64 {
    // u32 counts imply finite nonstructural roots well inside exp(±128).
    var lo: f64 = -128;
    var hi: f64 = 128;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const m = (lo + hi) / 2;
        const t = (try d.tailsControlled(m, budget, control)) orelse return null;
        const tail = (if (lower) t.right else t.left) - (if (midp) t.point / 2 else 0);
        if ((tail < target) == lower) lo = m else hi = m;
    }
    return @exp((lo + hi) / 2);
}

// SAS oracle primitives-v2.sas in /tmp/opensas-stat-batch2/FEAT-freq-exact:
// n=10,k=2,p0=.3 gives p1=.3828,p2=.7656,mid-p=.2660,
// CP=[.0252,.5561]; k=0 CP upper=.3085, mid-p upper=.2589.
// Unrounded assertions below additionally use the binomial sum/inversion.
test "exact binomial inclusive tails, boundary limits and invalid inputs" {
    const t = std.testing;
    const b = try binomial(2, 10, 0.3, 0.05, false);
    try t.expectApproxEqAbs(@as(f64, 0.3827827864), b.one_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.7655655728), b.two_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.025210726326833), b.limits.lower, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.556095462307642), b.limits.upper, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.26604556615), b.mid_p, 1e-12);
    const z = try binomial(0, 10, 0.3, 0.05, false);
    try t.expectEqual(@as(f64, 0), z.limits.lower);
    try t.expectApproxEqAbs(1 - std.math.pow(f64, 0.025, 0.1), z.limits.upper, 1e-12);
    const m = try binomial(0, 10, 0.3, 0.05, true);
    try t.expectApproxEqAbs(1 - std.math.pow(f64, 0.05, 0.1), m.limits.upper, 1e-12);
    try t.expectError(error.ExecError, binomial(11, 10, 0.5, 0.05, false));
    try t.expectError(error.ExecError, binomial(0, 0, 0.5, 0.05, false));
    try t.expectError(error.ExecError, binomial(1, 10, std.math.nan(f64), 0.05, false));
    try t.expectError(error.ExecError, binomial(1, 10, 0.5, 1, false));
    const certainty = try binomialTails(10, 10, 1);
    try t.expectEqual(@as(f64, 1), certainty.point);
}

test "conditional odds tails, reciprocal intervals, zero cells and resource budget" {
    const t = std.testing;
    const d = try OddsDistribution.init(.{ 1, 9, 11, 3 });
    const tails = try d.tails(0, 100);
    try t.expectApproxEqAbs(@as(f64, 0.001346076187912), tails.point, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.001379728092610), tails.left, 1e-12);
    const ci = (try oddsRatio(.{ 1, 9, 11, 3 }, 0.05, false, 100)).complete;
    // precision.sas ODS OddsRatioCLs, SAS/STAT pp.201–202. SAS's endpoint
    // search differs from direct inversion by up to 5.4e-9 on this table;
    // 1e-8 is an absolute oracle tolerance, not the inversion stopping rule.
    try t.expectApproxEqAbs(@as(f64, 0.00063600294886), ci.lower, 1e-8);
    try t.expectApproxEqAbs(@as(f64, 0.42586647460669), ci.upper, 1e-8);
    const mid = (try oddsRatio(.{ 1, 9, 11, 3 }, 0.05, true, 100)).complete;
    try t.expectApproxEqAbs(@as(f64, 0.00127425756282), mid.lower, 1e-8);
    try t.expectApproxEqAbs(@as(f64, 0.33512702428241), mid.upper, 1e-8);
    const reversed = (try oddsRatio(.{ 9, 1, 3, 11 }, 0.05, false, 100)).complete;
    try t.expectApproxEqRel(1 / ci.upper, reversed.lower, 1e-11);
    try t.expectApproxEqRel(1 / ci.lower, reversed.upper, 1e-11);
    const zero = (try oddsRatio(.{ 0, 5, 5, 0 }, 0.05, false, 100)).complete;
    try t.expectEqual(@as(f64, 0), zero.lower);
    const zd = try OddsDistribution.init(.{ 0, 5, 5, 0 });
    try t.expectApproxEqAbs(@as(f64, 0.05), (try zd.tails(@log(zero.upper), 100)).left, 1e-12);
    try t.expect((try oddsRatio(.{ 1, 9, 11, 3 }, 0.05, false, 5)) == .exhausted);
    try t.expectError(error.ExecError, OddsDistribution.init(.{ 0, 0, 1, 2 }));
}

test "exact public count conversion never truncates or overflows" {
    const t = std.testing;
    try t.expectEqual(@as(u32, 0), try integerCount(0));
    try t.expectEqual(std.math.maxInt(u32), try integerCount(4294967295));
    for ([_]f64{ -1, 0.5, 1.0000000000000002, 4294967296, std.math.inf(f64), std.math.nan(f64) }) |value| {
        try t.expectError(error.ExecError, integerCount(value));
    }
}

/// Blaker acceptability: P(min(F(X),G(X)) <= min(F(k),G(k))).
/// Unlike probability-ordered Fisher and twice-the-smaller-tail binomial tests,
/// the opposite tail is included only as far as its cumulative mass permits.
pub fn binomialBlakerP(k: u32, n: u32, p: f64) Error!f64 {
    const observed = try binomialTails(k, n, p);
    const gamma = @min(observed.left, observed.right);
    var left: f64 = 0;
    var right: f64 = 0;
    var lo: u64 = 0;
    var hi: u64 = @as(u64, n) + 1;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if ((try binomialTails(@intCast(mid), n, p)).left <= gamma) lo = mid + 1 else hi = mid;
    }
    if (lo > 0) left = (try binomialTails(@intCast(lo - 1), n, p)).left;
    lo = 0;
    hi = @as(u64, n) + 1;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if ((try binomialTails(@intCast(mid), n, p)).right <= gamma) hi = mid else lo = mid + 1;
    }
    if (lo <= n) right = (try binomialTails(@intCast(lo), n, p)).right;
    return @min(1, left + right);
}

/// Invert Blaker's discontinuous acceptability without assuming globally
/// monotone p-values. Starting at the CP lower bound, identify the next
/// opposite-tail inclusion jump F(j;p)=G(k;p). Before this jump, G(k)+F(j-1)
/// has at most one minimum, so an upward crossing is bracketable. At the jump
/// acceptability is 2*G(k)>=alpha. Upper endpoint follows binomial symmetry.
pub fn binomialBlaker(k: u32, n: u32, alpha: f64) Error!Interval {
    if (n == 0 or k > n or !validAlpha(alpha)) return error.ExecError;
    return (try binomialBlakerControlled(k, n, alpha, .{})).complete;
}
pub fn binomialBlakerControlled(k: u32, n: u32, alpha: f64, control: Control) Error!OddsResult {
    if (n == 0 or k > n or !validAlpha(alpha)) return error.ExecError;
    if (control.stopped()) return .exhausted;
    const lower = (try blakerLower(k, n, alpha, control)) orelse return .exhausted;
    const upper = 1 - ((try blakerLower(n - k, n, alpha, control)) orelse return .exhausted);
    return .{ .complete = .{ .lower = lower, .upper = upper } };
}
fn blakerLower(k: u32, n: u32, alpha: f64, control: Control) Error!?f64 {
    if (k == 0) return 0;
    const cp = (try binomialLimitControlled(k, n, alpha / 2, false, true, control)) orelse return null;
    const gamma = (try binomialTails(k, n, cp)).right;
    var first: u64 = 0;
    var end: u64 = k;
    while (first < end) {
        if (control.stopped()) return null;
        const mid = (first + end) / 2;
        if ((try binomialTails(@intCast(mid), n, cp)).left <= gamma) first = mid + 1 else end = mid;
    }
    // first is the next left-tail count to enter the acceptability sum.
    const next: u32 = @intCast(first);
    var lo = cp;
    var hi: f64 = 1;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const mid = (lo + hi) / 2;
        if ((try binomialTails(next, n, mid)).left > (try binomialTails(k, n, mid)).right) lo = mid else hi = mid;
    }
    const jump = (lo + hi) / 2;
    const before = (try binomialTails(k, n, jump)).right + (if (next == 0) @as(f64, 0) else (try binomialTails(next - 1, n, jump)).left);
    if (before <= alpha) return jump;
    lo = cp;
    hi = jump;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const mid = (lo + hi) / 2;
        const probability = (try binomialTails(k, n, mid)).right + (if (next == 0) @as(f64, 0) else (try binomialTails(next - 1, n, mid)).left);
        if (probability <= alpha) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

// SAS risk-blaker.sas ODS BinomialCLs (BEST32), FREQ p.177:
// k=2,n=10: [.03677145593142,.55555286230792]. SAS's numerical
// endpoint search is compared at 1e-6 absolute; coverage is independently checked.
test "Blaker inversion handles opposite-tail jumps and small-n coverage" {
    const t = std.testing;
    const ci = try binomialBlaker(2, 10, 0.05);
    try t.expectApproxEqAbs(@as(f64, 0.03677145593142), ci.lower, 1e-6);
    try t.expectApproxEqAbs(@as(f64, 0.55555286230792), ci.upper, 1e-6);
    const boundary = try binomialBlaker(0, 10, 0.05);
    try t.expectEqual(@as(f64, 0), boundary.lower);
    for (1..16) |nn| {
        const n: u32 = @intCast(nn);
        var intervals: [16]Interval = undefined;
        for (0..nn + 1) |kk| intervals[kk] = try binomialBlaker(@intCast(kk), n, 0.05);
        for (1..100) |pp| {
            const p = @as(f64, @floatFromInt(pp)) / 100;
            var coverage: f64 = 0;
            for (intervals[0 .. nn + 1], 0..) |interval, kk| {
                if (p >= interval.lower and p <= interval.upper) coverage += (try binomialTails(@intCast(kk), n, p)).point;
            }
            try t.expect(coverage >= 0.95 - 1e-12);
        }
    }
}

fn deadlineExpired(_: ?*const anyopaque) bool {
    return true;
}
test "exact interval deadline returns status not numerical limits" {
    const control = Control{ .expired = deadlineExpired };
    try std.testing.expect((try oddsRatioControlled(.{ 1, 9, 11, 3 }, 0.05, false, 100, control)) == .exhausted);
    try std.testing.expect((try binomialControlled(2, 10, 0.3, 0.05, false, control)) == .exhausted);
    try std.testing.expect((try binomialBlakerControlled(2, 10, 0.05, control)) == .exhausted);
}

// SAS public/freq_exact_controls.sas: NI/TOST use 90% CP limits at alpha=.05,
// distinct from the estimate's default 95% limits [.0252,.5561].
test "exact binomial NI interval uses one-sided alpha" {
    const r = (try binomialOneSidedLimits(2, 10, 0.05, .{})).complete;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0368), r.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5069), r.upper, 0.00005);
}
