//! FREQ COMOR and EQOR/ZELEN (pp.226–228). COMOR convolves independent
//! noncentral hypergeometrics conditional on EACH stratum's margins. Zelen
//! additionally fixes the sum of (1,1) counts; the common odds parameter then
//! cancels. Pooling strata or dropping that extra conditioning is incorrect.
const std = @import("std");
const exact = @import("freq_exact.zig");
const dist = @import("freq_exact_distribution.zig");
pub const Error = exact.Error;
const Budget = dist.Budget;
fn logAdd(a: f64, b: f64) f64 {
    if (a == -std.math.inf(f64)) return b;
    if (b == -std.math.inf(f64)) return a;
    return @max(a, b) + std.math.log1p(@exp(-@abs(a - b)));
}
pub const Common = struct {
    observed: u64,
    expected: f64,
    point: f64,
    one_sided: f64,
    two_doubled: f64,
    two_probability: f64,
    two_distance: f64,
    limits: exact.Interval,
};
pub const CommonResult = union(enum) { complete: Common, exhausted };
const Polynomial = struct {
    logs: []f64,
    lower: u64,
    observed: u64,
    pub fn tailsControlled(self: Polynomial, theta: f64, _: u64, control: exact.Control) Error!?exact.Tails {
        var peak: f64 = -std.math.inf(f64);
        for (self.logs, 0..) |v, i| {
            if (control.stopped()) return null;
            peak = @max(peak, v + @as(f64, @floatFromInt(i)) * theta);
        }
        var total: f64 = 0;
        var t = exact.Tails{ .point = 0, .left = 0, .right = 0 };
        for (self.logs, 0..) |v, i| {
            if (control.stopped()) return null;
            const w = @exp(v + @as(f64, @floatFromInt(i)) * theta - peak);
            total += w;
            const x = self.lower + i;
            if (x <= self.observed) t.left += w;
            if (x >= self.observed) t.right += w;
            if (x == self.observed) t.point = w;
        }
        t.left /= total;
        t.right /= total;
        t.point /= total;
        return t;
    }
};
const Build = union(enum) { complete: Polynomial, exhausted };
fn polynomial(a: std.mem.Allocator, strata: []const [4]u32, budget: Budget) Error!Build {
    if (strata.len == 0) return error.ExecError;
    var logs = try a.alloc(f64, 1);
    errdefer a.free(logs);
    logs[0] = 0;
    var lower: u64 = 0;
    var observed: u64 = 0;
    var work: u64 = 0;
    for (strata) |cells| {
        const d = try exact.OddsDistribution.initStratum(cells);
        const width = @as(u64, d.hi) - d.lo + 1;
        if (width > budget.max_tables or logs.len > budget.max_tables - width + 1 or budget.stopped()) {
            a.free(logs);
            return .exhausted;
        }
        const weights = try a.alloc(f64, @intCast(width));
        defer a.free(weights);
        if (!d.centralLogWeights(d.lo, weights, d.mode(0), .{ .context = budget.context, .expired = budget.expired })) {
            a.free(logs);
            return .exhausted;
        }
        const next = try a.alloc(f64, logs.len + weights.len - 1);
        @memset(next, -std.math.inf(f64));
        for (weights, 0..) |relative_log, j| {
            for (logs, 0..) |v, i| {
                if (work == budget.max_tables or budget.stopped()) {
                    a.free(next);
                    a.free(logs);
                    return .exhausted;
                }
                work += 1;
                next[i + j] = logAdd(next[i + j], v + relative_log);
            }
        }
        const peak = next[std.mem.findMax(f64, next)];
        for (next) |*v| v.* -= peak;
        a.free(logs);
        logs = next;
        lower += d.lo;
        observed += d.observed;
    }
    return .{ .complete = .{ .logs = logs, .lower = lower, .observed = observed } };
}
pub fn commonOdds(a: std.mem.Allocator, strata: []const [4]u32, alpha: f64, budget: Budget) Error!CommonResult {
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.ExecError;
    const built = try polynomial(a, strata, budget);
    if (built == .exhausted) return .exhausted;
    const p = built.complete;
    defer a.free(p.logs);
    var peak: f64 = -std.math.inf(f64);
    for (p.logs) |v| peak = @max(peak, v);
    var total: f64 = 0;
    var mean: f64 = 0;
    for (p.logs, 0..) |v, i| {
        const w = @exp(v - peak);
        total += w;
        mean += w * @as(f64, @floatFromInt(i));
    }
    mean /= total;
    const control = exact.Control{ .context = budget.context, .expired = budget.expired };
    const t = (try p.tailsControlled(0, budget.max_tables, control)) orelse return .exhausted;
    const observed_offset: f64 = @floatFromInt(p.observed - p.lower);
    const observed_log = p.logs[@intCast(p.observed - p.lower)];
    var probability: f64 = 0;
    var distance: f64 = 0;
    const observed_distance = @abs(observed_offset - mean);
    for (p.logs, 0..) |v, i| {
        const w = @exp(v - peak) / total;
        const tolerance = 64 * std.math.floatEps(f64) * @max(1, @abs(observed_log));
        if (v <= observed_log + tolerance) probability += w;
        if (@abs(@as(f64, @floatFromInt(i)) - mean) >= observed_distance - 64 * std.math.floatEps(f64) * @max(1, observed_distance)) distance += w;
    }
    const one = if (observed_offset > mean) t.right else t.left;
    const upper = p.lower + p.logs.len - 1;
    const target = if (p.observed == p.lower or p.observed == upper) alpha else alpha / 2;
    if (budget.stopped()) return .exhausted;
    // Deadline checks also apply during interval inversion, not just convolution.
    var limits = exact.Interval{ .lower = 0, .upper = std.math.inf(f64) };
    inline for (.{ true, false }) |lower| {
        if (if (lower) p.observed != p.lower else p.observed != upper) {
            const endpoint = (try exact.invertOddsTail(p, target, false, lower, budget.max_tables, control)) orelse return .exhausted;
            if (lower) limits.lower = endpoint else limits.upper = endpoint;
        }
    }
    return .{ .complete = .{ .observed = p.observed, .expected = @as(f64, @floatFromInt(p.lower)) + mean, .point = t.point, .one_sided = one, .two_doubled = @min(1, 2 * one), .two_probability = @min(1, probability), .two_distance = @min(1, distance), .limits = limits } };
}

pub const Zelen = struct { point: f64, p: f64, tables: u64 };
pub const ZelenResult = union(enum) { complete: Zelen, exhausted };
const Weights = struct { lo: u64, values: []f64 };
const ZelenSearch = struct {
    distributions: []const exact.OddsDistribution,
    log_weights: []const Weights,
    remaining_lo: []const u64,
    remaining_hi: []const u64,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    total: f64 = -std.math.inf(f64),
    tail: f64 = -std.math.inf(f64),
    fn visit(self: *ZelenSearch, k: usize, remaining: u64, weight: f64, magnitude: f64) Error!void {
        if (self.stopped) return;
        if (self.budget.stopped()) {
            self.stopped = true;
            return;
        }
        if (k == self.distributions.len) {
            if (remaining != 0) return;
            if (self.count == self.budget.max_tables) {
                self.stopped = true;
                return;
            }
            self.count += 1;
            self.total = logAdd(self.total, weight);
            if (weight <= 64 * std.math.floatEps(f64) * @max(1, magnitude)) self.tail = logAdd(self.tail, weight);
            return;
        }
        const d = self.distributions[k];
        const lo = @max(@as(u64, d.lo), remaining -| self.remaining_hi[k + 1]);
        if (remaining < self.remaining_lo[k + 1]) return;
        const hi = @min(@as(u64, d.hi), remaining - self.remaining_lo[k + 1]);
        var x = lo;
        while (x <= hi) : (x += 1) {
            const factor = self.log_weights[k].values[@intCast(x - self.log_weights[k].lo)];
            try self.visit(k + 1, remaining - x, weight + factor, magnitude + @abs(factor));
            if (self.stopped) return;
        }
    }
};
pub fn zelen(a: std.mem.Allocator, strata: []const [4]u32, budget: Budget) Error!ZelenResult {
    if (strata.len == 0) return error.ExecError;
    if (strata.len > 256) return .exhausted;
    const ds = try a.alloc(exact.OddsDistribution, strata.len);
    defer a.free(ds);
    const lo = try a.alloc(u64, strata.len + 1);
    defer a.free(lo);
    const hi = try a.alloc(u64, strata.len + 1);
    defer a.free(hi);
    var observed: u64 = 0;
    for (strata, ds) |cells, *d| {
        d.* = try exact.OddsDistribution.initStratum(cells);
        observed += d.observed;
    }
    lo[strata.len] = 0;
    hi[strata.len] = 0;
    var i = strata.len;
    while (i > 0) {
        i -= 1;
        lo[i] = lo[i + 1] + ds[i].lo;
        hi[i] = hi[i + 1] + ds[i].hi;
    }
    const weights = try a.alloc(Weights, strata.len);
    defer a.free(weights);
    var allocated: usize = 0;
    defer for (weights[0..allocated]) |w| a.free(w.values);
    for (ds, weights) |d, *w| {
        // Fixing the sum can leave a single feasible count in a stratum
        // whose marginal support is huge. Build only that feasible range.
        w.lo = @max(@as(u64, d.lo), observed -| (hi[0] - d.hi));
        const last = @min(@as(u64, d.hi), observed - (lo[0] - d.lo));
        const width = last - w.lo + 1;
        if (width > budget.max_tables or budget.stopped()) return .exhausted;
        w.values = try a.alloc(f64, @intCast(width));
        allocated += 1;
        if (!d.centralLogWeights(@intCast(w.lo), w.values, d.observed, .{ .context = budget.context, .expired = budget.expired })) return .exhausted;
    }
    var search = ZelenSearch{ .distributions = ds, .log_weights = weights, .remaining_lo = lo, .remaining_hi = hi, .budget = budget };
    try search.visit(0, observed, 0, 0);
    if (search.stopped) return .exhausted;
    return .{ .complete = .{ .point = @exp(-search.total), .p = @min(1, @exp(search.tail - search.total)), .tables = search.count } };
}

// SAS generators.sas: COMOR POINT=.5, one-sided=.75; convolving
// [1,4,1] with itself gives [1,8,18,8,1]/36. Pooling gives different mass.
test "common odds conditional convolution and one-stratum reduction" {
    const t = std.testing;
    const c = (try commonOdds(t.allocator, &.{ .{ 2, 0, 0, 2 }, .{ 0, 2, 2, 0 } }, 0.05, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.5), c.point, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.75), c.one_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), c.two_doubled, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), c.two_probability, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), c.two_distance, 1e-12);
    const single = (try commonOdds(t.allocator, &.{.{ 1, 9, 11, 3 }}, 0.05, .{})).complete;
    const odds = (try exact.oddsRatio(.{ 1, 9, 11, 3 }, 0.05, false, 100)).complete;
    try t.expectApproxEqRel(odds.lower, single.limits.lower, 1e-12);
    try t.expectApproxEqRel(odds.upper, single.limits.upper, 1e-12);
    try t.expect((try commonOdds(t.allocator, &.{ .{ 2, 0, 0, 2 }, .{ 0, 2, 2, 0 } }, 0.05, .{ .max_tables = 2 })) == .exhausted);
}

// SAS generators-v2.sas unequal strata gives .0357 = 1/28. Dropping
// conditioning on S=2 gives 1/30: this discriminates the generator itself.
test "Zelen conditions on sum of diagonal counts" {
    const t = std.testing;
    const z = (try zelen(t.allocator, &.{ .{ 0, 2, 2, 0 }, .{ 2, 0, 0, 3 } }, .{})).complete;
    try t.expectEqual(@as(u64, 3), z.tables);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 28.0), z.point, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 28.0), z.p, 1e-12);
    try t.expect((try zelen(t.allocator, &.{ .{ 0, 2, 2, 0 }, .{ 2, 0, 0, 3 } }, .{ .max_tables = 2 })) == .exhausted);
}

// SAS strata-boundaries.sas/.txt/.log, zero errors/warnings, under
// /tmp/opensas-stat-batch2/FEAT-freq-exact. Empty and zero-row middle strata
// leave COMOR point=.5, one=.75, limits[.0434,23.0483], EQOR p=.1111.
test "COMOR and Zelen preserve degenerate stratum factors" {
    const t = std.testing;
    const base = [_][4]u32{ .{ 2, 0, 0, 2 }, .{ 0, 2, 2, 0 } };
    const reference = (try commonOdds(t.allocator, &base, 0.05, .{})).complete;
    const reference_z = (try zelen(t.allocator, &base, .{})).complete;
    for ([_][4]u32{ .{ 0, 0, 0, 0 }, .{ 0, 0, 1, 1 }, .{ 3, 2, 0, 0 } }) |middle| {
        const all = [_][4]u32{ base[0], middle, base[1] };
        const result = (try commonOdds(t.allocator, &all, 0.05, .{})).complete;
        const z = (try zelen(t.allocator, &all, .{})).complete;
        try t.expectApproxEqAbs(reference.point, result.point, 1e-12);
        try t.expectApproxEqAbs(reference.one_sided, result.one_sided, 1e-12);
        try t.expectApproxEqRel(reference.limits.lower, result.limits.lower, 1e-12);
        try t.expectApproxEqRel(reference.limits.upper, result.limits.upper, 1e-12);
        try t.expectEqual(reference.observed + middle[0], result.observed);
        try t.expectApproxEqAbs(reference_z.p, z.p, 1e-12);
        try t.expectApproxEqAbs(reference_z.point, z.point, 1e-12);
    }
    try t.expectError(error.ExecError, exact.OddsDistribution.init(.{ 0, 0, 1, 1 }));
}

test "stratified conditional weights retain sparse wide margins and level-dependent limits" {
    const t = std.testing;
    // Independently convolve C(A+1,x) C(3,3-x) with [1,4,1] at A=2e9.
    // For Zelen retain only x+y=2, and evaluate the conditional mass and
    // probability ordering from the same integer coefficients.
    const intervals = [_]exact.Interval{
        .{ .lower = 7.8622258440045604e-11, .upper = 1.7649517346936823e-7 },
        .{ .lower = 5665877.317452853, .upper = 12719044451.801937 },
    };
    for ([_][4]u32{ .{ 1, 2, 2_000_000_000, 1 }, .{ 2, 1, 1, 2_000_000_000 } }, intervals) |row, reference| {
        const strata = [_][4]u32{ row, .{ 1, 1, 1, 1 } };
        const common = (try commonOdds(t.allocator, &strata, 0.05, .{})).complete;
        try t.expectApproxEqRel(reference.lower, common.limits.lower, 3e-14);
        try t.expectApproxEqRel(reference.upper, common.limits.upper, 3e-14);
        try t.expectApproxEqRel(@as(f64, 7.5e-10), common.point, 3e-14);
        const equal = (try zelen(t.allocator, &strata, .{})).complete;
        try t.expectApproxEqRel(@as(f64, 3.9999999840000001e-9), equal.point, 3e-14);
        try t.expectApproxEqRel(@as(f64, 3.9999999841666667e-9), equal.p, 3e-14);
    }
    const edge = [_][4]u32{ .{ 0, 1, 1, 0 }, .{ 0, 1, 1, 0 } };
    const interval = (try commonOdds(t.allocator, &edge, 1e-220, .{})).complete.limits;
    // The probability of the observed sum is 1/(1+theta)^2.
    try t.expectApproxEqRel(@as(f64, 1e110), interval.upper, 8e-14);
    // Conditioning the sum to zero retains one configuration, even with a
    // marginal support of over two billion. Its exact probability is one.
    const fixed = [_][4]u32{ .{ 0, 2_147_483_647, 2_147_483_647, 0 }, .{ 0, 1, 1, 0 } };
    const only = (try zelen(t.allocator, &fixed, .{ .max_tables = 1 })).complete;
    try t.expectEqual(@as(u64, 1), only.tables);
    try t.expectEqual(@as(f64, 1), only.point);
    try t.expectEqual(@as(f64, 1), only.p);
}
