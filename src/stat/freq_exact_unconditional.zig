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
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.ExecError;
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
        var lo: f64 = if (family == .difference) (if (lower) -1 else estimate) else (if (lower) -64 else @log(@max(estimate, 1e-20)));
        var hi: f64 = if (family == .difference) (if (lower) estimate else 1) else (if (lower) @log(@min(estimate, 1e20)) else 64);
        const boundary = if (lower) lo else hi;
        const boundary_result = try tail(c, family, method, if (family == .difference) boundary else @exp(boundary), if (method == .score2) .two_sided else if (lower) .right else .left, &work);
        if (boundary_result == .exhausted) return .exhausted;
        if (boundary_result.complete.upper > target) continue;
        for (0..60) |_| {
            const mid = (lo + hi) / 2;
            const null_value = if (family == .difference) mid else @exp(mid);
            const result = try tail(c, family, method, null_value, if (method == .score2) .two_sided else if (lower) .right else .left, &work);
            if (result == .exhausted) return .exhausted;
            // Use the certified upper bound, conservatively including nuisance
            // uncertainty. p-error is at most Options.tolerance.
            const accepted = result.complete.upper > target;
            if (accepted == lower) hi = mid else lo = mid;
        }
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
