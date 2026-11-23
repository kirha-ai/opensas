//! Shared exact primitives for FREQ risk and exact integrations (D-029).
//! These kernels do not accept SAS syntax or render output. Counts must already
//! reflect the table layer's ordering, missing-value, and weight policies.
const std = @import("std");
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
/// Stirling's remainder log(n!) - (n+1/2)log(n) + n - log(2*pi)/2.
fn factorialRemainder(n: u32) f64 {
    const x: f64 = @floatFromInt(n);
    if (n < 10) {
        var factorial: u32 = 1;
        for (2..@as(usize, n) + 1) |i| factorial *= @intCast(i);
        return @log(@as(f64, @floatFromInt(factorial))) - (x + 0.5) * @log(x) + x - 0.5 * @log(@as(f64, 2 * std.math.pi));
    }
    // The first omitted term is bounded by 7/(1092*n^13) for n >= 10.
    const u = 1 / (x * x);
    return (1.0 / 12.0 - u * (1.0 / 360.0 - u * (1.0 / 1260.0 - u * (1.0 / 1680.0 - u * (1.0 / 1188.0 - u * (691.0 / 360360.0)))))) / x;
}

/// log(n!) - n*log(n) + n, with 0*log(0) defined by continuity.
pub fn logFactorialCorrection(n: u32) f64 {
    if (n == 0) return 0;
    return 0.5 * @log(@as(f64, 2 * std.math.pi) * @as(f64, @floatFromInt(n))) + factorialRemainder(n);
}

/// x*log(x/mean) - (x-mean), with its even-power expansion near the mean.
pub fn poissonDeviance(x: f64, mean: f64, delta: f64) f64 {
    if (x == 0) return mean;
    if (mean == 0 or !std.math.isFinite(mean) or !std.math.isFinite(delta)) return std.math.inf(f64);
    if (delta == 0) return 0;
    const scale = x + mean;
    const v = if (std.math.isFinite(scale)) delta / scale else (0.5 * delta) / (0.5 * x + 0.5 * mean);
    if (@abs(v) > 0.125) {
        const ratio = x / mean;
        const log_ratio = if (ratio > 0 and std.math.isFinite(ratio)) @log(ratio) else @log(x) - @log(mean);
        const product = x * log_ratio;
        return if (std.math.isFinite(product)) product - delta else x * (log_ratio - delta / x);
    }
    const v2 = v * v;
    var term = (2 * v) * x;
    var sum = delta * v;
    var denominator: f64 = 3;
    while (true) : (denominator += 2) {
        term *= v2;
        const next = sum + term / denominator;
        if (next == sum) return sum;
        sum = next;
    }
}

/// Log probability of k successes for 0 < p < 1, including an empty split.
pub fn binomialLogPoint(k: u32, n: u32, p: f64) f64 {
    const total: f64 = @floatFromInt(n);
    if (k == 0) return total * std.math.log1p(-p);
    if (k == n) return total * @log(p);
    const successes: f64 = @floatFromInt(k);
    const failures: f64 = @floatFromInt(n - k);
    const small = @min(successes, failures);
    const delta = @mulAdd(f64, -total, p, successes);
    return factorialRemainder(n) - factorialRemainder(k) - factorialRemainder(n - k) -
        poissonDeviance(successes, total * p, delta) - poissonDeviance(failures, total * (1 - p), -delta) -
        0.5 * (@log(@as(f64, 2 * std.math.pi)) + @log(small) + std.math.log1p(-small / total));
}

/// Inclusive binomial tails. Start at the observed mass and sum away from
/// the mode. Ratios decrease on that side, so a geometric series bounds
/// the unvisited mass. The opposite inclusive tail excludes only strict mass.
pub fn binomialTails(k: u32, n: u32, p: f64) Error!Tails {
    return (try binomialTailsControlled(k, n, p, .{})).?;
}
pub fn binomialTailsControlled(k: u32, n: u32, p: f64, control: Control) Error!?Tails {
    if (n == 0 or k > n or !std.math.isFinite(p) or p < 0 or p > 1) return error.ExecError;
    if (control.stopped()) return null;
    if (p == 0) return .{ .point = if (k == 0) 1 else 0, .left = 1, .right = if (k == 0) 1 else 0 };
    if (p == 1) return .{ .point = if (k == n) 1 else 0, .left = if (k == n) 1 else 0, .right = 1 };
    const total: f64 = @floatFromInt(n);
    const log_point = binomialLogPoint(k, n, p);
    const point = @exp(log_point);
    if (k == 0 or k == n) return .{ .point = point, .left = if (k == 0) point else 1, .right = if (k == 0) 1 else point };
    if (p == 0.5 and k == n - k) {
        const symmetric = (1 + point) / 2;
        return .{ .point = point, .left = symmetric, .right = symmetric };
    }
    const down = @as(f64, @floatFromInt(k)) < (total + 1) * p;
    const odds = if (down) (1 - p) / p else p / (1 - p);
    var i = if (down) k else n - k;
    var relative: f64 = 1;
    var beyond: f64 = 0;
    var compensation: f64 = 0;
    while (i > 0) : (i -= 1) {
        if (control.stopped()) return null;
        const x: f64 = @floatFromInt(i);
        const ratio = x / (total - x + 1) * odds;
        relative *= ratio;
        const corrected = relative - compensation;
        const next = beyond + corrected;
        compensation = (next - beyond) - corrected;
        beyond = next;
        if (relative * ratio <= std.math.floatEps(f64) * (1 - ratio) * (1 + beyond)) break;
    }
    const included = @min(1, @exp(log_point + std.math.log1p(beyond)));
    const complement = if (beyond == 0) 1 else -std.math.expm1(@min(0, log_point + @log(beyond)));
    return .{ .point = point, .left = if (down) included else complement, .right = if (down) complement else included };
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
    const tails = (try binomialTailsControlled(k, n, p0, control)) orelse return .exhausted;
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

fn binomialLimitControlled(k: u32, n: u32, target: f64, midp: bool, lower: bool, control: Control) Error!?f64 {
    if (control.stopped()) return null;
    if ((lower and k == n) or (!lower and k == 0)) {
        const log_tail = @log(if (midp) 2 * target else target) / @as(f64, @floatFromInt(n));
        return if (lower) @exp(log_tail) else -std.math.expm1(log_tail);
    }
    var lo: f64 = 0;
    var hi: f64 = 1;
    while (true) {
        const p = (lo + hi) / 2;
        if (p == lo or p == hi) return p;
        const t = (try binomialTailsControlled(k, n, p, control)) orelse return null;
        const tail = (if (lower) t.right else t.left) - (if (midp) t.point / 2 else 0);
        if ((tail < target) == lower) lo = p else hi = p;
    }
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
        const d = try initStratum(cells);
        if (d.row == 0 or d.col == 0 or d.row == d.total or d.col == d.total) return error.ExecError;
        return d;
    }
    /// A degenerate stratum contributes a single conditional outcome of mass
    /// one. Keep its fixed count/slot in pooled inference; the standalone odds
    /// interval API above still rejects undefined zero-margin odds ratios.
    pub fn initStratum(cells: [4]u32) Error!OddsDistribution {
        const row = @as(u64, cells[0]) + cells[1];
        const col = @as(u64, cells[0]) + cells[2];
        const total = row + cells[2] + cells[3];
        if (@min(row, col) > std.math.maxInt(u32)) return error.ExecError;
        return .{ .lo = @intCast((row + col) -| total), .hi = @intCast(@min(row, col)), .observed = cells[0], .row = row, .col = col, .total = total };
    }
    // Ratio of adjacent noncentral hypergeometric weights. All four counts
    // are positive here, including when the lower support is nonzero.
    fn logStep(self: OddsDistribution, x: u32, log_odds: f64) f64 {
        const right_top: f64 = @floatFromInt(self.row - x);
        const left_bottom: f64 = @floatFromInt(self.col - x);
        const left_top: f64 = @floatFromInt(@as(u64, x) + 1);
        const right_bottom: f64 = @floatFromInt((self.total - self.col) - (self.row - x) + 1);
        return @log((right_top / left_top) * (left_bottom / right_bottom)) + log_odds;
    }
    pub fn mode(self: OddsDistribution, log_odds: f64) u32 {
        var lo = self.lo;
        var hi = self.hi;
        while (lo < hi) {
            const x = lo + (hi - lo) / 2;
            if (self.logStep(x, log_odds) > 0) lo = x + 1 else hi = x;
        }
        return lo;
    }
    /// Compute central log masses on a contiguous support relative to pivot.
    /// Each stratum's constant factor cancels in both COMOR and Zelen.
    pub fn centralLogWeights(self: OddsDistribution, lower: u32, values: []f64, pivot: u32, control: Control) bool {
        const center: usize = pivot - lower;
        values[center] = 0;
        for (center + 1..values.len) |i| {
            if (control.stopped()) return false;
            values[i] = values[i - 1] + self.logStep(lower + @as(u32, @intCast(i - 1)), 0);
        }
        var i = center;
        while (i > 0) {
            if (control.stopped()) return false;
            i -= 1;
            values[i] = values[i + 1] - self.logStep(lower + @as(u32, @intCast(i)), 0);
        }
        return true;
    }
    pub fn tails(self: OddsDistribution, log_odds: f64, max_support: u64) Error!Tails {
        return (try self.tailsControlled(log_odds, max_support, .{})).?;
    }
    pub fn tailsControlled(self: OddsDistribution, log_odds: f64, max_support: u64, control: Control) Error!?Tails {
        if (!std.math.isFinite(log_odds) or @as(u64, self.hi) - self.lo + 1 > max_support) return error.ExecError;
        if (control.stopped()) return null;
        // Starting at a mode keeps every relative weight at most one and
        // avoids cancellation between log-gamma values of large margins.
        const pivot = self.mode(log_odds);
        var total: f64 = 0;
        var out = Tails{ .point = 0, .left = 0, .right = 0 };
        for ([_]bool{ true, false }) |right| {
            var x = pivot;
            var log_weight: f64 = 0;
            while (true) {
                if (control.stopped()) return null;
                const w = @exp(log_weight);
                if (w == 0) break;
                if (right or x != pivot) {
                    total += w;
                    if (x == self.observed) out.point = w;
                    if (x <= self.observed) out.left += w;
                    if (x >= self.observed) out.right += w;
                }
                if (right) {
                    if (x == self.hi) break;
                    log_weight += self.logStep(x, log_odds);
                    x += 1;
                } else {
                    if (x == self.lo) break;
                    x -= 1;
                    log_weight -= self.logStep(x, log_odds);
                }
            }
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
    if (d.observed != d.lo) limits.lower = (try invertOddsTail(d, target, midp, true, max_support, control)) orelse return .exhausted;
    if (d.observed != d.hi) limits.upper = (try invertOddsTail(d, target, midp, false, max_support, control)) orelse return .exhausted;
    return .{ .complete = limits };
}

pub fn invertOddsTail(d: anytype, target: f64, midp: bool, lower: bool, budget: u64, control: Control) Error!?f64 {
    var lo: f64 = -1;
    var hi: f64 = 1;
    // The confidence level also determines the bracket. A table with two
    // feasible outcomes alone can have a finite upper limit of 1/alpha - 1.
    for ([_]bool{ false, true }) |right| {
        const edge = if (right) &hi else &lo;
        while (true) {
            const t = (try d.tailsControlled(edge.*, budget, control)) orelse return null;
            const tail = (if (lower) t.right else t.left) - (if (midp) t.point / 2 else 0);
            if (((tail < target) == lower) != right) break;
            if (right and std.math.isInf(@exp(edge.*))) return std.math.inf(f64);
            if (!right and @exp(edge.*) == 0) return 0;
            edge.* *= 2;
        }
    }
    for (0..80) |_| {
        const m = (lo + hi) / 2;
        if (m == lo or m == hi) break;
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

test "exact binomial mass and tails match independent integer sums" {
    const t = std.testing;
    for (1..17) |size| {
        const n: u32 = @intCast(size);
        for (1..4) |numerator| {
            const p = @as(f64, @floatFromInt(numerator)) / 4;
            var coefficients: [17]u64 = @splat(0);
            var choose: u64 = 1;
            for (0..size + 1) |i| {
                coefficients[i] = choose * std.math.pow(u64, numerator, i) * std.math.pow(u64, 4 - numerator, size - i);
                choose = choose * (size - i) / (i + 1);
            }
            const denominator: f64 = @floatFromInt(std.math.pow(u64, 4, size));
            var left: u64 = 0;
            for (coefficients[0 .. size + 1], 0..) |weight, i| {
                const upper_numerator = @as(u64, @intFromFloat(denominator)) - left;
                left += weight;
                const tails = try binomialTails(@intCast(i), n, p);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(weight)) / denominator, tails.point, 2e-14);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(left)) / denominator, tails.left, 2e-14);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(upper_numerator)) / denominator, tails.right, 2e-14);
            }
        }
    }
}

test "wide exact binomial central and rare probabilities retain both inclusive tails" {
    const t = std.testing;
    const n = 2_000_000_000;
    // C(2m,m)/4^m = (1-1/(8m)+1/(128m^2)+O(m^-3))/sqrt(pi*m).
    const middle = try binomialTails(n / 2, n, 0.5);
    const point: f64 = 0.00001784124115929755600033808453;
    try t.expectApproxEqRel(point, middle.point, 2e-14);
    try t.expectApproxEqAbs((1 + point) / 2, middle.left, 2e-14);
    try t.expectEqual(middle.left, middle.right);
    const neighbor = try binomialTails(n / 2 - 1, n, 0.5);
    try t.expectApproxEqAbs((1 - point) / 2, neighbor.left, 2e-14);
    // For k=1, the two masses are (1-p)^n and n*p*(1-p)^(n-1).
    const rare = try binomialTails(1, n, 5e-10);
    try t.expectApproxEqRel(@as(f64, 0.36787944126341218), rare.point, 2e-14);
    try t.expectApproxEqRel(@as(f64, 0.73575888234288464), rare.left, 2e-14);
    try t.expectApproxEqRel(@as(f64, 0.63212055892052754), rare.right, 2e-14);
    const boundary = try binomialTails(0, n, 1e-16);
    try t.expectEqual(boundary.point, boundary.left);
    try t.expectApproxEqRel(@as(f64, 0.9999998000000200), boundary.left, 2e-15);
    const Timer = struct {
        remaining: usize,
        fn expired(raw: ?*const anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(@constCast(raw.?)));
            if (self.remaining == 0) return true;
            self.remaining -= 1;
            return false;
        }
    };
    var timer = Timer{ .remaining = 10 };
    try t.expect((try binomialTailsControlled(n / 2 - 1, n, 0.5, .{ .context = &timer, .expired = Timer.expired })) == null);
    const single = try binomial(1, 1, 0.5, 1e-100, false);
    try t.expectApproxEqRel(@as(f64, 5e-101), single.limits.lower, 5e-14);
    const first = try binomial(1, 2, 0.5, 1e-100, false);
    // 1-(1-p)^2=alpha/2. The endpoint is alpha/4 at this precision.
    try t.expectApproxEqRel(@as(f64, 2.5e-101), first.limits.lower, 5e-14);
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

test "conditional odds limits retain sparse wide margins and extreme confidence levels" {
    const t = std.testing;
    // The four possible weights at odds theta are
    // C(A+1,x) C(3,3-x) theta^x for A=2e9 and x=0,1,2,3.
    // Independently invert those four integer coefficients at 95-digit precision.
    const wide = [4]u32{ 1, 2, 2_000_000_000, 1 };
    const reversed = [4]u32{ 2, 1, 1, 2_000_000_000 };
    for ([_]bool{ false, true }, [_]Interval{
        .{ .lower = 4.2553788979219666e-12, .upper = 1.1283469174905303e-8 },
        .{ .lower = 8.619148326189801e-12, .upper = 7.469988112533252e-9 },
    }) |midp, reference| {
        const interval = (try oddsRatio(wide, 0.05, midp, 4)).complete;
        const flipped = (try oddsRatio(reversed, 0.05, midp, 4)).complete;
        try t.expectApproxEqRel(reference.lower, interval.lower, 2e-14);
        try t.expectApproxEqRel(reference.upper, interval.upper, 2e-14);
        try t.expectApproxEqRel(1 / reference.upper, flipped.lower, 2e-14);
        try t.expectApproxEqRel(1 / reference.lower, flipped.upper, 2e-14);
        // For a support of two with equal central weights, the upper tail at
        // the lower boundary is 1/(1+theta), or half that when using mid-p.
        const alpha = 1e-100;
        const extreme = (try oddsRatio(.{ 0, 1, 1, 0 }, alpha, midp, 2)).complete;
        const reciprocal = (try oddsRatio(.{ 1, 0, 0, 1 }, alpha, midp, 2)).complete;
        const upper = (if (midp) @as(f64, 0.5) else 1) / alpha - 1;
        try t.expectApproxEqRel(upper, extreme.upper, 8e-14);
        try t.expectApproxEqRel(1 / upper, reciprocal.lower, 8e-14);
    }
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
fn beforeBlakerJump(k: u32, n: u32, opposite: u32, p: f64, control: Control) Error!?f64 {
    const observed = (try binomialTailsControlled(k, n, p, control)) orelse return null;
    if (opposite == 0) return observed.right;
    const other = (try binomialTailsControlled(opposite - 1, n, p, control)) orelse return null;
    return observed.right + other.left;
}
fn blakerLower(k: u32, n: u32, alpha: f64, control: Control) Error!?f64 {
    if (k == 0) return 0;
    const cp = (try binomialLimitControlled(k, n, alpha / 2, false, true, control)) orelse return null;
    const at_cp = (try binomialTailsControlled(k, n, cp, control)) orelse return null;
    var first: u64 = 0;
    var end: u64 = k;
    while (first < end) {
        if (control.stopped()) return null;
        const mid = (first + end) / 2;
        const opposite = (try binomialTailsControlled(@intCast(mid), n, cp, control)) orelse return null;
        if (opposite.left <= at_cp.right) first = mid + 1 else end = mid;
    }
    // first is the next left-tail count to enter the acceptability sum.
    const next: u32 = @intCast(first);
    var lo = cp;
    var hi: f64 = 1;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const mid = (lo + hi) / 2;
        const opposite = (try binomialTailsControlled(next, n, mid, control)) orelse return null;
        const observed = (try binomialTailsControlled(k, n, mid, control)) orelse return null;
        if (opposite.left > observed.right) lo = mid else hi = mid;
    }
    const jump = (lo + hi) / 2;
    const before = (try beforeBlakerJump(k, n, next, jump, control)) orelse return null;
    if (before <= alpha) return jump;
    lo = cp;
    hi = jump;
    for (0..80) |_| {
        if (control.stopped()) return null;
        const mid = (lo + hi) / 2;
        const probability = (try beforeBlakerJump(k, n, next, mid, control)) orelse return null;
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

// SAS interval-highalpha.sas (0 errors/warnings): exact NI/TOST confidence
// is 1-2*alpha, but discreteness can leave overlapping limits at alpha>=.5.
test "exact binomial high alpha one-sided limits match SAS" {
    for ([_]f64{ 0.5, 0.6 }, [_]f64{ 0.1623, 0.1921 }, [_]f64{ 0.2586, 0.2255 }) |alpha, lo, hi| {
        const result = (try binomialOneSidedLimits(2, 10, alpha, .{})).complete;
        try std.testing.expectApproxEqAbs(lo, result.lower, 0.00005);
        try std.testing.expectApproxEqAbs(hi, result.upper, 0.00005);
    }
}
