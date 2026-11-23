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
    right_sided: bool,
    two_doubled: f64,
    two_probability: f64,
    two_distance: f64,
    limits: exact.Interval,
};
pub const CommonResult = union(enum) { complete: Common, exhausted };
/// For central hypergeometrics, sum(C) = choose(N, row) and
/// sum(x*C) = sum(C) * row * column / N. The joint first moment can be
/// kept as exact binary64-representable integer coefficients while they fit.
/// Wider cases retain the log-scaled convolution and its centered moment.
const ExactMoment = struct {
    weight: u64 = 1,
    weighted_sum: u64 = 0,

    fn append(self: ExactMoment, d: exact.OddsDistribution) ?ExactMoment {
        const largest: u64 = 1 << 53;
        const k = @min(d.row, d.total - d.row);
        var weight: u128 = 1;
        var j: u64 = 1;
        while (j <= k) : (j += 1) {
            weight = weight * (d.total - k + j) / j;
            if (weight * self.weight > largest) return null;
        }
        const moment = if (d.total == 0) 0 else weight * d.row * d.col / d.total;
        const next_sum = weight * self.weighted_sum + moment * self.weight;
        if (next_sum > largest) return null;
        return .{ .weight = @intCast(weight * self.weight), .weighted_sum = @intCast(next_sum) };
    }
};
const Polynomial = struct {
    exact_moment: ?ExactMoment = null,
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
fn polynomial(a: std.mem.Allocator, strata: []const [4]u32, budget: Budget, native_units: bool) Error!Build {
    if (strata.len == 0) return error.ExecError;
    var logs = try a.alloc(f64, 1);
    errdefer a.free(logs);
    logs[0] = 0;
    var units = try a.alloc(bool, if (native_units) 1 else 0);
    defer a.free(units);
    if (native_units) units[0] = true;
    var lower: u64 = 0;
    var observed: u64 = 0;
    var work: u64 = 0;
    var moment: ?ExactMoment = .{};
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
        const next_len = logs.len + weights.len - 1;
        const next_units = try a.alloc(bool, if (native_units) next_len else 0);
        errdefer a.free(next_units);
        const next = try a.alloc(f64, next_len);
        @memset(next, -std.math.inf(f64));
        for (weights, 0..) |relative_log, j| {
            const x = d.lo + @as(u32, @intCast(j));
            const other = d.row - x;
            const unit = (x == 0 or x == d.col) and (other == 0 or other == d.total - d.col);
            for (logs, 0..) |v, i| {
                if (work == budget.max_tables or budget.stopped()) {
                    a.free(next);
                    a.free(next_units);
                    a.free(logs);
                    return .exhausted;
                }
                work += 1;
                const slot = i + j;
                const term = v + relative_log;
                if (!native_units) {
                    next[slot] = logAdd(next[slot], term);
                } else {
                    // In M9's large-table recurrence a raw weight of one
                    // survives alone, but contributes no additional mass
                    // when another path reaches the same sufficient sum.
                    const unit_term = units[i] and unit;
                    if (next[slot] == -std.math.inf(f64) or next_units[slot]) {
                        next[slot] = term;
                        next_units[slot] = unit_term;
                    } else if (!unit_term) {
                        next[slot] = logAdd(next[slot], term);
                    }
                }
            }
        }
        const peak = next[std.mem.findMax(f64, next)];
        for (next) |*v| v.* -= peak;
        a.free(logs);
        logs = next;
        a.free(units);
        units = next_units;
        if (moment) |value| moment = value.append(d);
        lower += d.lo;
        observed += d.observed;
    }
    return .{ .complete = .{ .logs = logs, .lower = lower, .observed = observed, .exact_moment = moment } };
}
/// Model M9's alternate raw-coefficient arithmetic only when a feasible
/// coefficient provably exceeds the range of binary64. Its earlier switch
/// in some sparse tables has no generally verified activation criterion.
pub fn commonOddsSas(a: std.mem.Allocator, strata: []const [4]u32, alpha: f64, budget: Budget) Error!CommonResult {
    var bits: u64 = 0;
    for (strata) |cells| {
        if (budget.stopped()) return .exhausted;
        const d = try exact.OddsDistribution.initStratum(cells);
        const x = d.mode(0);
        const other = d.row - x;
        // For k <= n/2, choose(n,k) >= 2^k. The product of independent
        // stratum coefficients at their modes is a feasible path.
        bits += @min(x, d.col - x) + @min(other, (d.total - d.col) - other);
        if (bits > std.math.floatExponentMax(f64)) return commonOddsMode(a, strata, alpha, budget, true);
    }
    return commonOdds(a, strata, alpha, budget);
}
pub fn commonOdds(a: std.mem.Allocator, strata: []const [4]u32, alpha: f64, budget: Budget) Error!CommonResult {
    return commonOddsMode(a, strata, alpha, budget, false);
}
fn commonOddsMode(a: std.mem.Allocator, strata: []const [4]u32, alpha: f64, budget: Budget, native_units: bool) Error!CommonResult {
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.ExecError;
    const built = try polynomial(a, strata, budget, native_units);
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
    const observed_offset: f64 = @floatFromInt(p.observed - p.lower);
    var expected = @as(f64, @floatFromInt(p.lower)) + mean;
    var right = observed_offset > mean;
    if (p.exact_moment) |moment| {
        const denominator: f64 = @floatFromInt(moment.weight);
        expected = @as(f64, @floatFromInt(moment.weighted_sum)) / denominator;
        mean = @as(f64, @floatFromInt(moment.weighted_sum - p.lower * moment.weight)) / denominator;
        right = @as(u128, p.observed) * moment.weight > moment.weighted_sum;
    }
    const control = exact.Control{ .context = budget.context, .expired = budget.expired };
    const t = (try p.tailsControlled(0, budget.max_tables, control)) orelse return .exhausted;
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
    const one = if (right) t.right else t.left;
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
    return .{ .complete = .{ .observed = p.observed, .expected = expected, .point = t.point, .one_sided = one, .right_sided = right, .two_doubled = @min(1, 2 * one), .two_probability = @min(1, probability), .two_distance = @min(1, distance), .limits = limits } };
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
test "COMOR over binary64 coefficient range distinguishes a unit path from a sole coefficient" {
    const t = std.testing;
    const a = [4]u32{ 0, 1, 1, 0 };
    const b = [4]u32{ 1, 798, 0, 1 };
    const diffuse = [4]u32{ 1, 2047, 0, 2048 };
    const stats = (try commonOddsSas(t.allocator, &.{ a, b, diffuse }, 0.05, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 799.0 / 1599.0), stats.point, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 799.0 / 1066.0), stats.one_sided, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 78.49746109345), stats.limits.upper, 1e-8);
    // Placing the diffuse factor first scales every path away from one.
    // M9 and the mathematical conditional convolution then coincide.
    const reordered = (try commonOddsSas(t.allocator, &.{ diffuse, a, b }, 0.05, .{})).complete;
    const math = (try commonOdds(t.allocator, &.{ a, b, diffuse }, 0.05, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 1599.0 / 3200.0), math.point, 1e-13);
    try t.expectApproxEqAbs(math.point, reordered.point, 1e-13);
    try t.expectApproxEqRel(math.limits.upper, reordered.limits.upper, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 78.54658242845), reordered.limits.upper, 1e-8);
}

test "COMOR chooses the inclusive left tail at an exactly representable conditional mean" {
    const t = std.testing;
    // M9 CommonOddsRatioTest gives XPL_COMOR=527/735; the other
    // inclusive tail is 1651/2205. The cell-count sum equals E[S]=8.
    const a = [4]u32{ 7, 12, 1, 1 };
    const b = [4]u32{ 1, 15, 0, 5 };
    for ([_][2][4]u32{ .{ a, b }, .{ b, a } }) |tables| {
        const r = (try commonOdds(t.allocator, &tables, 0.05, .{})).complete;
        try t.expectEqual(@as(f64, 8), r.expected);
        try t.expect(!r.right_sided);
        try t.expectApproxEqAbs(@as(f64, 527.0 / 735.0), r.one_sided, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 61.0 / 126.0), r.one_sided - r.point / 2, 1e-14);
    }
    const right = (try commonOdds(t.allocator, &.{ .{ 8, 11, 0, 2 }, b }, 0.05, .{})).complete;
    try t.expect(right.right_sided);
    try t.expectApproxEqAbs(@as(f64, 208.0 / 735.0), right.one_sided, 1e-14);
}

test "COMOR keeps the selected tail when a wide conditional mean rounds to the observed count" {
    const t = std.testing;
    // Changing the second stratum total on either side of 600000 reverses the
    // deviation, while the raw conditional center in binary64 rounds to
    // 600000 on both sides. The side must travel with its probability.
    for ([_]u32{ 599_999, 600_001 }, [_]bool{ true, false }, [_]f64{ 0.7454541212114142, 0.7636358787880823 }) |n, right, one| {
        const tables = [_][4]u32{ .{ 599_998, 1, 1, 0 }, .{ 1, n - 2, 0, 1 }, .{ 1, 3, 2, 6 } };
        const r = (try commonOdds(t.allocator, &tables, 0.05, .{})).complete;
        try t.expectEqual(right, r.right_sided);
        try t.expectApproxEqAbs(one, r.one_sided, 3e-14);
    }
}

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
