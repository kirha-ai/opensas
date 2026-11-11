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
    fn tails(self: Polynomial, theta: f64) exact.Tails {
        var peak: f64 = -std.math.inf(f64);
        for (self.logs, 0..) |v, i| peak = @max(peak, v + @as(f64, @floatFromInt(i)) * theta);
        var total: f64 = 0;
        var t = exact.Tails{ .point = 0, .left = 0, .right = 0 };
        for (self.logs, 0..) |v, i| {
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
    fn limit(self: Polynomial, target: f64, lower: bool) f64 {
        var lo: f64 = -128;
        var hi: f64 = 128;
        for (0..80) |_| {
            const m = (lo + hi) / 2;
            const t = self.tails(m);
            if (((if (lower) t.right else t.left) < target) == lower) lo = m else hi = m;
        }
        return @exp((lo + hi) / 2);
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
        const d = try exact.OddsDistribution.init(cells);
        const width = @as(u64, d.hi) - d.lo + 1;
        if (width > budget.max_tables or logs.len > budget.max_tables - width + 1 or budget.stopped()) {
            a.free(logs);
            return .exhausted;
        }
        const next = try a.alloc(f64, logs.len + @as(usize, @intCast(width)) - 1);
        @memset(next, -std.math.inf(f64));
        for (logs, 0..) |v, i| {
            var x: u64 = d.lo;
            while (x <= d.hi) : (x += 1) {
                if (work == budget.max_tables or budget.stopped()) {
                    a.free(next);
                    a.free(logs);
                    return .exhausted;
                }
                work += 1;
                const j = i + @as(usize, @intCast(x - d.lo));
                next[j] = logAdd(next[j], v + d.logWeight(@intCast(x), 0));
            }
        }
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
        mean += w * @as(f64, @floatFromInt(p.lower + i));
    }
    mean /= total;
    const t = p.tails(0);
    const observed_log = p.logs[@intCast(p.observed - p.lower)];
    var probability: f64 = 0;
    var distance: f64 = 0;
    const observed_distance = @abs(@as(f64, @floatFromInt(p.observed)) - mean);
    for (p.logs, 0..) |v, i| {
        const w = @exp(v - peak) / total;
        const tolerance = 64 * std.math.floatEps(f64) * @max(1, @abs(observed_log));
        if (v <= observed_log + tolerance) probability += w;
        if (@abs(@as(f64, @floatFromInt(p.lower + i)) - mean) >= observed_distance - 64 * std.math.floatEps(f64) * @max(1, observed_distance)) distance += w;
    }
    const one = if (@as(f64, @floatFromInt(p.observed)) > mean) t.right else t.left;
    const upper = p.lower + p.logs.len - 1;
    const target = if (p.observed == p.lower or p.observed == upper) alpha else alpha / 2;
    if (budget.stopped()) return .exhausted;
    // Deadline checks also apply during interval inversion, not just convolution.
    var limits = exact.Interval{ .lower = 0, .upper = std.math.inf(f64) };
    inline for (.{ true, false }) |lower| {
        if (if (lower) p.observed != p.lower else p.observed != upper) {
            var lo: f64 = -128;
            var hi: f64 = 128;
            for (0..80) |_| {
                if (budget.stopped()) return .exhausted;
                const m = (lo + hi) / 2;
                const tt = p.tails(m);
                if (((if (lower) tt.right else tt.left) < target) == lower) lo = m else hi = m;
            }
            if (lower) limits.lower = @exp((lo + hi) / 2) else limits.upper = @exp((lo + hi) / 2);
        }
    }
    return .{ .complete = .{ .observed = p.observed, .expected = mean, .point = t.point, .one_sided = one, .two_doubled = @min(1, 2 * one), .two_probability = @min(1, probability), .two_distance = @min(1, distance), .limits = limits } };
}

pub const Zelen = struct { point: f64, p: f64, tables: u64 };
pub const ZelenResult = union(enum) { complete: Zelen, exhausted };
const ZelenSearch = struct {
    distributions: []const exact.OddsDistribution,
    remaining_lo: []const u64,
    remaining_hi: []const u64,
    observed_log: f64,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    total: f64 = -std.math.inf(f64),
    tail: f64 = -std.math.inf(f64),
    fn visit(self: *ZelenSearch, k: usize, remaining: u64, weight: f64) Error!void {
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
            if (weight <= self.observed_log + 64 * std.math.floatEps(f64) * @max(1, @abs(self.observed_log))) self.tail = logAdd(self.tail, weight);
            return;
        }
        const d = self.distributions[k];
        const lo = @max(@as(u64, d.lo), remaining -| self.remaining_hi[k + 1]);
        if (remaining < self.remaining_lo[k + 1]) return;
        const hi = @min(@as(u64, d.hi), remaining - self.remaining_lo[k + 1]);
        var x = lo;
        while (x <= hi) : (x += 1) {
            try self.visit(k + 1, remaining - x, weight + d.logWeight(@intCast(x), 0));
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
    var weight: f64 = 0;
    for (strata, ds) |cells, *d| {
        d.* = try exact.OddsDistribution.init(cells);
        observed += d.observed;
        weight += d.logWeight(d.observed, 0);
    }
    lo[strata.len] = 0;
    hi[strata.len] = 0;
    var i = strata.len;
    while (i > 0) {
        i -= 1;
        lo[i] = lo[i + 1] + ds[i].lo;
        hi[i] = hi[i + 1] + ds[i].hi;
    }
    var search = ZelenSearch{ .distributions = ds, .remaining_lo = lo, .remaining_hi = hi, .observed_log = weight, .budget = budget };
    try search.visit(0, observed, 0);
    if (search.stopped) return .exhausted;
    return .{ .complete = .{ .point = @exp(weight - search.total), .p = @min(1, @exp(search.tail - search.total)), .tables = search.count } };
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
