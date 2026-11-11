//! Unconditional two-binomial inference, SAS/STAT pp.189–194,205–206.
//! Row totals are fixed; columns vary. At RD=d, p1=p2+d and
//! p2 in [max(0,-d),min(1,1-d)]; at RR=r, p1=r*p2 and
//! p2 in [0,min(1,1/r)]. Tail mass is maximized over the WHOLE interval.
//! Risk score/constraint algorithms belong to freq_risk, never duplicated here.
const std = @import("std");
const math = @import("../functions.zig");
const risk = @import("freq_risk.zig");
const exact = @import("freq_exact.zig");
const dist = @import("freq_exact_distribution.zig");
pub const Error = exact.Error;
pub const Family = enum { difference, relative_risk };
pub const Method = enum { noscore, score, score2 };
pub const Side = enum { left, right, two_sided };
pub const Bounds = struct { lower: f64, upper: f64 };
pub const TailResult = union(enum) { complete: Bounds, exhausted };
pub const LimitsResult = union(enum) { complete: exact.Interval, exhausted };
pub const Options = struct {
    budget: dist.Budget = .{},
    /// Absolute bound width for the nuisance supremum (floating roundoff aside).
    tolerance: f64 = 1e-10,
    /// Endpoint bracket width: absolute RD, log(RR) (approximately relative RR).
    /// This is separate from the nuisance p-value bound above.
    inversion_tolerance: f64 = 1e-11,
};
const max_n = 128;
const Work = struct {
    options: Options,
    used: u64 = 0,
    stopped: bool = false,
    fn tick(self: *Work) bool {
        if (self.stopped) return false;
        if (self.used == self.options.budget.max_tables or self.options.budget.stopped()) {
            self.stopped = true;
            return false;
        }
        self.used += 1;
        return true;
    }
};
fn choose(n: u32, k: u32) f64 {
    return @exp(math.lgammaOf(@as(f64, @floatFromInt(n)) + 1) - math.lgammaOf(@as(f64, @floatFromInt(k)) + 1) - math.lgammaOf(@as(f64, @floatFromInt(n - k)) + 1));
}
fn canonical(table: risk.Table2x2, column: risk.Column) Error![4]u32 {
    try table.validate();
    var c: [4]u32 = undefined;
    for (table.cells, 0..) |v, i| c[i] = try exact.integerCount(v);
    if (column == .second) {
        std.mem.swap(u32, &c[0], &c[1]);
        std.mem.swap(u32, &c[2], &c[3]);
    }
    return c;
}
fn tableOf(c: [4]u32) risk.Table2x2 {
    var v: [4]f64 = undefined;
    for (c, 0..) |x, i| v[i] = @floatFromInt(x);
    return .{ .cells = v };
}
fn statistic(c: [4]u32, family: Family, method: Method, null_value: f64) Error!f64 {
    const table = tableOf(c);
    if (method == .noscore) {
        const s = table.samples(.first);
        return switch (family) {
            .difference => s[0].proportion() - s[1].proportion(),
            // Documented modified RR (Gart-Nam), not raw division by zero.
            .relative_risk => (s[0].success + 0.5) / (s[0].total + 0.5) / ((s[1].success + 0.5) / (s[1].total + 0.5)),
        };
    }
    const value = switch (family) {
        .difference => try risk.differenceScore(table, .first, null_value, false),
        .relative_risk => try risk.relativeRiskScore(table, .first, null_value, false),
    };
    if (std.math.isNan(value)) return error.ExecError;
    return value; // Infinite scores are valid at degenerate candidate tables.
}
fn selected(value: f64, observed: f64, side: Side) bool {
    const x = if (side == .two_sided) @abs(value) else value;
    const y = if (side == .two_sided) @abs(observed) else observed;
    if (x == y) return true;
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return if (side == .left) x < y else x > y;
    const eps = 64 * std.math.floatEps(f64) * @max(1, @max(@abs(x), @abs(y)));
    return if (side == .left) x < y + eps else x > y - eps;
}
/// Multiply a degree-d Bernstein polynomial by affine p(t) with endpoints l,h.
fn multiply(coeff: *[max_n + 1]f64, d: usize, l: f64, h: f64) void {
    var j = d + 2;
    while (j > 0) {
        j -= 1;
        const den: @TypeOf(l) = @floatFromInt(d + 1);
        coeff[j] = (if (j <= d) @as(f64, @floatFromInt(d + 1 - j)) / den * coeff[j] * l else 0) + (if (j > 0) @as(f64, @floatFromInt(j)) / den * coeff[j - 1] * h else 0);
    }
}
/// Bernstein convex hull bounds certify the maximum; recursive subdivision
/// narrows the upper/lower gap instead of assuming a coarse grid found it.
fn maximize(coeff: []const f64, best: *f64, work: *Work, depth: usize) f64 {
    if (!work.tick()) return 1;
    var upper: f64 = 0;
    for (coeff) |v| upper = @max(upper, v);
    best.* = @max(best.*, @max(coeff[0], coeff[coeff.len - 1]));
    if (upper - best.* <= work.options.tolerance) return upper;
    if (depth == 64) {
        work.stopped = true;
        return 1;
    }
    var temp: [max_n + 1]f64 = undefined;
    var left: [max_n + 1]f64 = undefined;
    var right: [max_n + 1]f64 = undefined;
    @memcpy(temp[0..coeff.len], coeff);
    left[0] = temp[0];
    right[coeff.len - 1] = temp[coeff.len - 1];
    for (1..coeff.len) |level| {
        for (0..coeff.len - level) |j| temp[j] = (temp[j] + temp[j + 1]) / 2;
        left[level] = temp[0];
        right[coeff.len - level - 1] = temp[coeff.len - level - 1];
    }
    best.* = @max(best.*, left[coeff.len - 1]);
    const lu = maximize(left[0..coeff.len], best, work, depth + 1);
    if (work.stopped) return 1;
    const ru = maximize(right[0..coeff.len], best, work, depth + 1);
    return @max(lu, ru);
}

fn tail(c: [4]u32, family: Family, method: Method, null_value: f64, side: Side, work: *Work) Error!TailResult {
    const n1wide = @as(u64, c[0]) + c[1];
    const n2wide = @as(u64, c[2]) + c[3];
    if (n1wide + n2wide > max_n) return .exhausted;
    const n1: u32 = @intCast(n1wide);
    const n2: u32 = @intCast(n2wide);
    const n = n1 + n2;
    if (n1 == 0 or n2 == 0) return error.ExecError;
    if (!std.math.isFinite(null_value) or (family == .difference and @abs(null_value) > 1) or (family == .relative_risk and null_value <= 0)) return error.ExecError;
    if (!std.math.isFinite(work.options.tolerance) or work.options.tolerance <= 0 or work.options.tolerance >= 1) return error.ExecError;
    const p2lo = if (family == .difference) @max(0, -null_value) else 0;
    const p2hi = if (family == .difference) @min(1, 1 - null_value) else @min(1, 1 / null_value);
    const p1lo = if (family == .difference) p2lo + null_value else p2lo * null_value;
    const p1hi = if (family == .difference) p2hi + null_value else p2hi * null_value;
    const observed = try statistic(c, family, method, null_value);
    var sum: [max_n + 1]f64 = @splat(0);
    for (0..n1 + 1) |xx| for (0..n2 + 1) |yy| {
        if (!work.tick()) return .exhausted;
        const x: u32 = @intCast(xx);
        const y: u32 = @intCast(yy);
        const s = try statistic(.{ x, n1 - x, y, n2 - y }, family, method, null_value);
        if (!selected(s, observed, side)) continue;
        var coeff: [max_n + 1]f64 = @splat(0);
        coeff[0] = choose(n1, x) * choose(n2, y);
        var d: usize = 0;
        for (0..n1) |i| {
            multiply(&coeff, d, if (i < x) p1lo else 1 - p1lo, if (i < x) p1hi else 1 - p1hi);
            d += 1;
        }
        for (0..n2) |i| {
            multiply(&coeff, d, if (i < y) p2lo else 1 - p2lo, if (i < y) p2hi else 1 - p2hi);
            d += 1;
        }
        for (0..n + 1) |i| sum[i] += coeff[i];
    };
    var best: f64 = 0;
    const upper = maximize(sum[0 .. n + 1], &best, work, 0);
    if (work.stopped) return .exhausted;
    return .{ .complete = .{ .lower = @min(1, best), .upper = @min(1, upper) } };
}
pub fn riskTail(table: risk.Table2x2, column: risk.Column, family: Family, method: Method, null_value: f64, side: Side, options: Options) Error!TailResult {
    var work = Work{ .options = options };
    return tail(try canonical(table, column), family, method, null_value, side, &work);
}

/// Equal-tailed NOSCORE/SCORE inversion or absolute-score SCORE2 inversion.
/// Returns bracketed numerical endpoints; no fixed-margin shortcut is valid.
pub fn riskLimits(table: risk.Table2x2, column: risk.Column, family: Family, method: Method, alpha: f64, options: Options) Error!LimitsResult {
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1 or !std.math.isFinite(options.inversion_tolerance) or options.inversion_tolerance <= 0 or options.inversion_tolerance >= 1) return error.ExecError;
    const c = try canonical(table, column);
    const s = tableOf(c).samples(.first);
    const estimate = if (family == .difference) s[0].proportion() - s[1].proportion() else if (c[2] == 0) std.math.inf(f64) else s[0].proportion() / s[1].proportion();
    const target = if (method == .score2) alpha else alpha / 2;
    var out = exact.Interval{ .lower = if (family == .difference) -1 else 0, .upper = if (family == .difference) 1 else std.math.inf(f64) };
    var work = Work{ .options = options };
    for ([_]bool{ true, false }) |lower| {
        // RR structural endpoints; all-zero event rows require their own
        // modified-statistic inversion and are not silently declared [0,inf].
        if (family == .relative_risk and ((lower and c[0] == 0) or (!lower and c[2] == 0))) continue;
        if (family == .difference and ((lower and estimate == -1) or (!lower and estimate == 1))) continue;
        var center: f64 = if (family == .difference) estimate else if (estimate == 0) -2 else if (std.math.isInf(estimate)) 2 else @log(estimate);
        if (family == .relative_risk and (estimate == 0 or std.math.isInf(estimate))) {
            // Establish an accepted finite inner bracket near a structural MLE.
            // log(floatMin) is not a useful center and can exhaust the bracket
            // before testing any finite upper bound for an observed zero risk.
            while (true) {
                const inner = try tail(c, family, method, @exp(center), if (method == .score2) .two_sided else if (lower) .right else .left, &work);
                if (inner == .exhausted) return .exhausted;
                if (inner.complete.lower > target) break;
                center *= 2;
                if (@abs(center) > 700) return .exhausted;
            }
        }
        var width: f64 = 2;
        var lo: f64 = if (lower) (if (family == .difference) -1 else center - width) else center;
        var hi: f64 = if (lower) center else if (family == .difference) 1 else center + width;
        if (family == .relative_risk and method == .noscore) {
            // The nuisance endpoint p2=0 makes both successes zero. If that
            // table is in the ordered tail, its probability is 1 for EVERY RR:
            // this proves the structural 0/infinity endpoint, without treating
            // an arbitrary finite log-RR cutoff as infinity.
            const zero_score = try statistic(.{ 0, @intFromFloat(s[0].total), 0, @intFromFloat(s[1].total) }, family, method, 1);
            const observed_score = try statistic(c, family, method, 1);
            if (selected(zero_score, observed_score, if (lower) .right else .left)) continue;
        }
        while (true) {
            const boundary = if (lower) lo else hi;
            if (family == .relative_risk and @abs(boundary) > 700) return .exhausted;
            const boundary_result = try tail(c, family, method, if (family == .difference) boundary else @exp(boundary), if (method == .score2) .two_sided else if (lower) .right else .left, &work);
            if (boundary_result == .exhausted) return .exhausted;
            if (boundary_result.complete.upper <= target) break;
            if (family == .difference) break;
            width *= 2;
            if (lower) lo = center - width else hi = center + width;
        }
        for (0..100) |_| {
            if (hi - lo <= options.inversion_tolerance) break;
            const mid = (lo + hi) / 2;
            const null_value = if (family == .difference) mid else @exp(mid);
            const result = try tail(c, family, method, null_value, if (method == .score2) .two_sided else if (lower) .right else .left, &work);
            if (result == .exhausted) return .exhausted;
            // Use the certified upper bound, conservatively including nuisance
            // uncertainty. p-error is at most Options.tolerance.
            const accepted = result.complete.upper > target;
            if (accepted == lower) hi = mid else lo = mid;
        }
        if (hi - lo > options.inversion_tolerance) return .exhausted;
        const endpoint = if (family == .difference) (lo + hi) / 2 else @exp((lo + hi) / 2);
        if (lower) out.lower = endpoint else out.upper = endpoint;
    }
    return .{ .complete = out };
}

// SAS generators.sas [0,3;2,1], Barnard two=.2188/one=.1094 vs
// Fisher=.4000. Exact tail polynomial is u^2(6-10u), u=p(1-p), maximized
// at p=.5: 7/32. This checks the generator AND nuisance supremum.
test "unconditional Barnard supremum is not Fisher conditioning" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 0, 3, 2, 1 } };
    const two = (try riskTail(table, .first, .difference, .score, 0, .two_sided, .{})).complete;
    try t.expect(two.lower <= 0.21875 + 1e-12 and two.upper >= 0.21875 - 1e-12);
    try t.expect(two.upper - two.lower <= 1e-10);
    const one = (try riskTail(table, .first, .difference, .score, 0, .left, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.109375), one.upper, 1e-10);
    try t.expect((try riskTail(table, .first, .difference, .score, 0, .left, .{ .budget = .{ .max_tables = 1 } })) == .exhausted);
}

test "risk interval method oracle and column orientation" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 3, 3, 1 } };
    const ci = (try riskLimits(table, .first, .difference, .noscore, 0.05, .{})).complete;
    const reverse = (try riskLimits(table, .second, .difference, .noscore, 0.05, .{})).complete;
    try t.expectApproxEqAbs(-ci.upper, reverse.lower, 1e-8);
    try t.expectApproxEqAbs(-ci.lower, reverse.upper, 1e-8);
    try t.expectApproxEqAbs(@as(f64, -0.9363), ci.lower, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 0.3017), ci.upper, 0.00005);
    const methods = [_]Method{ .noscore, .score, .score2 };
    const rd_lower = [_]f64{ -0.9363, -0.9363, -0.9072 };
    const rd_upper = [_]f64{ 0.3017, 0.3017, 0.2500 };
    for (methods, rd_lower, rd_upper) |method, lower, upper| {
        const rd = (try riskLimits(table, .first, .difference, method, 0.05, .{})).complete;
        try t.expectApproxEqAbs(lower, rd.lower, 0.00005);
        try t.expectApproxEqAbs(upper, rd.upper, 0.00005);
    }
    const rr_lower = [_]f64{ 0, 0.0118, 0.0238 };
    // Independently maximize the explicit 25-table polynomial. SAS prints
    // 12.8095; its tail at that rounded value is .02499938057535682.
    // The exact root is 12.809175283792893; public SAS parity is pending,
    // not hidden by widening the four-decimal oracle tolerance.
    const rr_upper = [_]f64{ 12.809175283792893, 1.7874, 1.6859 };
    for (methods, rr_lower, rr_upper) |method, lower, upper| {
        const rr = (try riskLimits(table, .first, .relative_risk, method, 0.05, .{})).complete;
        try t.expectApproxEqAbs(lower, rr.lower, 0.00005);
        try t.expectApproxEqAbs(upper, rr.upper, if (method == .noscore) @as(f64, 5e-8) else 0.00005);
    }
}

// This tests numerical inversion accuracy, not agreement with SAS's coarser
// internal search. Independent direct 25-table polynomial root below; the SAS
// BEST32 oracle remains 12.8094895576158 and is tracked separately.
test "RR NOSCORE inversion accuracy separates endpoint and nuisance tolerances" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 3, 3, 1 } };
    const precise = (try riskLimits(table, .first, .relative_risk, .noscore, 0.05, .{ .tolerance = 1e-13, .inversion_tolerance = 1e-13, .budget = .{ .max_tables = 5000000 } })).complete;
    try t.expectApproxEqAbs(@as(f64, 12.809175283792893), precise.upper, 1e-9);
    try t.expectEqual(@as(f64, 0), precise.lower);
    const inside = (try riskTail(table, .first, .relative_risk, .noscore, precise.upper * (1 - 1e-7), .left, .{ .tolerance = 1e-13 })).complete;
    const outside = (try riskTail(table, .first, .relative_risk, .noscore, precise.upper * (1 + 1e-7), .left, .{ .tolerance = 1e-13 })).complete;
    try t.expect(inside.lower > 0.025 and outside.upper < 0.025);
    const reverse = (try riskLimits(.{ .cells = .{ 3, 1, 1, 3 } }, .first, .relative_risk, .noscore, 0.05, .{ .tolerance = 1e-13, .inversion_tolerance = 1e-13 })).complete;
    try t.expectApproxEqRel(1 / precise.upper, reverse.lower, 1e-9);
    try t.expect(std.math.isInf(reverse.upper));
}

test "unconditional zero and infinite observed risks retain finite opposite bounds" {
    const t = std.testing;
    for ([_]Method{ .noscore, .score, .score2 }) |method| {
        const zero = (try riskLimits(.{ .cells = .{ 0, 4, 2, 2 } }, .first, .relative_risk, method, 0.05, .{})).complete;
        const infinite = (try riskLimits(.{ .cells = .{ 2, 2, 0, 4 } }, .first, .relative_risk, method, 0.05, .{})).complete;
        try t.expectEqual(@as(f64, 0), zero.lower);
        try t.expect(std.math.isFinite(zero.upper) and zero.upper > 0);
        try t.expect(std.math.isInf(infinite.upper));
        try t.expectApproxEqRel(1 / zero.upper, infinite.lower, 1e-7);
    }
}

test "unconditional small-table interval coverage includes boundary outcomes" {
    const t = std.testing;
    for ([_]Family{ .difference, .relative_risk }) |family| for ([_]Method{ .noscore, .score, .score2 }) |method| {
        var intervals: [9]exact.Interval = undefined;
        for (0..3) |x| for (0..3) |y| {
            intervals[x * 3 + y] = (try riskLimits(.{ .cells = .{ @floatFromInt(x), @floatFromInt(2 - x), @floatFromInt(y), @floatFromInt(2 - y) } }, .first, family, method, 0.05, .{})).complete;
        };
        for ([_]f64{ 0.05, 0.2, 0.5, 0.8, 0.95 }) |p1| for ([_]f64{ 0.05, 0.2, 0.5, 0.8, 0.95 }) |p2| {
            const truth = if (family == .difference) p1 - p2 else p1 / p2;
            const pmf1 = [_]f64{ (1 - p1) * (1 - p1), 2 * p1 * (1 - p1), p1 * p1 };
            const pmf2 = [_]f64{ (1 - p2) * (1 - p2), 2 * p2 * (1 - p2), p2 * p2 };
            var coverage: f64 = 0;
            for (0..3) |x| for (0..3) |y| {
                const ci = intervals[x * 3 + y];
                if (truth >= ci.lower - 1e-10 and truth <= ci.upper + 1e-10) coverage += pmf1[x] * pmf2[y];
            };
            try t.expect(coverage >= 0.95 - 1e-10);
        };
    };
}

// Unequal row totals and high ALPHA stress different test-ordering breakpoints.
// Probability weights below are independent explicit Bin(2,p1)*Bin(3,p2)
// formulas, not the engine's Bernstein polynomial or score implementation.
test "unconditional unequal-row coverage across confidence levels" {
    const t = std.testing;
    for ([_]f64{ 0.05, 0.2, 0.8 }) |alpha| for ([_]Family{ .difference, .relative_risk }) |family| for ([_]Method{ .noscore, .score, .score2 }) |method| {
        var intervals: [12]exact.Interval = undefined;
        for (0..3) |x| for (0..4) |y| {
            const result = try riskLimits(.{ .cells = .{ @floatFromInt(x), @floatFromInt(2 - x), @floatFromInt(y), @floatFromInt(3 - y) } }, .first, family, method, alpha, .{});
            try t.expect(result == .complete);
            intervals[x * 4 + y] = result.complete;
        };
        for ([_]f64{ 0.1, 0.35, 0.65, 0.9 }) |p1| for ([_]f64{ 0.1, 0.35, 0.65, 0.9 }) |p2| {
            const truth = if (family == .difference) p1 - p2 else p1 / p2;
            const pmf1 = [_]f64{ (1 - p1) * (1 - p1), 2 * p1 * (1 - p1), p1 * p1 };
            const pmf2 = [_]f64{ (1 - p2) * (1 - p2) * (1 - p2), 3 * p2 * (1 - p2) * (1 - p2), 3 * p2 * p2 * (1 - p2), p2 * p2 * p2 };
            var coverage: f64 = 0;
            for (0..3) |x| for (0..4) |y| {
                const ci = intervals[x * 4 + y];
                if (truth >= ci.lower - 1e-10 and truth <= ci.upper + 1e-10) coverage += pmf1[x] * pmf2[y];
            };
            try t.expect(coverage >= 1 - alpha - 1e-10);
        };
    };
}

// Independent rational polynomial/Sturm oracle:
// python3 /tmp/opensas-stat-batch2/FEAT-freq-exact/rr-noscore-sturm.py
// Root bracket width1.22e-20, all nuisance stationary points isolated to1e-25.
// Isolated real SAS gives upper=.84 at alpha=.95 and .99 (zero errors/warnings),
// so this is a documented unresolved behavioral difference, not a relaxed SAS
// tolerance. At .84 the documented tail supremum is .5547206220161103>.475.
test "RR NOSCORE high alpha follows independently inverted unconditional tail" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 1, 2, 1 } };
    const options = Options{ .tolerance = 1e-13, .inversion_tolerance = 1e-13 };
    const ci = (try riskLimits(table, .first, .relative_risk, .noscore, 0.95, options)).complete;
    try t.expectEqual(@as(f64, 0), ci.lower);
    try t.expectApproxEqAbs(@as(f64, 0.9884657555036446), ci.upper, 1e-10);
    const at_sas = (try riskTail(table, .first, .relative_risk, .noscore, 0.84, .left, options)).complete;
    try t.expectApproxEqAbs(@as(f64, 0.5547206220161103), at_sas.lower, 1e-12);
    try t.expect(at_sas.lower > 0.475);
}
