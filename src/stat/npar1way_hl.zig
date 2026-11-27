//! Hodges-Lehmann shift, Moses and conditional exact limits.
//! SAS/STAT 15.4 physical pp.7242-7244. X is the caller-selected reference,
//! Y the comparison: estimate = median(Y-X), including all tied differences.
const std = @import("std");
const ranks = @import("ranks.zig");
const math = @import("../functions.zig");
const A = std.mem.Allocator;
pub const Interval = struct {
    lower: f64,
    upper: f64,
    pub fn midpoint(self: Interval) f64 {
        return self.lower / 2 + self.upper / 2;
    }
};
pub const Result = struct { estimate: f64, asymptotic: Interval, standard_error: f64, exact: ?Interval, lower_critical: ?f64 = null, upper_critical: ?f64 = null, allocations: u64 = 0 };
pub const Distribution = struct { counts: []u64, total: u64 };
/// Doubled Mann-Whitney U has integer support, even for tied ranks. Distinct
/// observation allocations, not equally weighted tied tables, define counts.
pub fn distribution(a: A, values: []const f64, n1: usize) !Distribution {
    const n = values.len;
    if (n1 == 0 or n1 >= n) return error.InvalidInput;
    if (n > 60) return error.ExactLimit;
    const ranked = try ranks.rank(a, values, false, .mean);
    if (ranked.n != n) return error.InvalidInput;
    const maxsum = n * (n + 1);
    const width = maxsum + 1;
    const dp = try a.alloc(u64, (n1 + 1) * width);
    defer a.free(dp);
    @memset(dp, 0);
    dp[0] = 1;
    for (ranked.values, 0..) |r, index| {
        const w: usize = @intFromFloat(2 * r);
        var k = @min(n1, index + 1);
        while (k > 0) : (k -= 1) {
            var s = maxsum;
            while (s >= w) : (s -= 1) dp[k * width + s] += dp[(k - 1) * width + s - w];
        }
    }
    const offset = n1 * (n1 + 1);
    const counts = try a.alloc(u64, 2 * n1 * (n - n1) + 1);
    @memcpy(counts, dp[n1 * width + offset ..][0..counts.len]);
    var total: u64 = 0;
    for (counts) |c| total += c;
    return .{ .counts = counts, .total = total };
}
pub fn compute(a: A, x: []const f64, y: []const f64, alpha: f64, exact: bool) !Result {
    if (x.len == 0 or y.len == 0 or !(alpha > 0 and alpha < 1)) return error.InvalidInput;
    if (x.len > 1_000_000 / y.len) return error.PairLimit;
    const m = x.len * y.len;
    const differences = try a.alloc(f64, m);
    var at: usize = 0;
    for (y) |yv| for (x) |xv| {
        if (!std.math.isFinite(xv) or !std.math.isFinite(yv) or !std.math.isFinite(yv - xv)) return error.InvalidInput;
        differences[at] = yv - xv;
        at += 1;
    };
    std.mem.sort(f64, differences, {}, std.sort.asc(f64));
    const pooled = try a.alloc(f64, x.len + y.len);
    @memcpy(pooled[0..x.len], x);
    @memcpy(pooled[x.len..], y);
    const picked = try a.alloc(bool, pooled.len);
    @memset(picked[0..x.len], false);
    @memset(picked[x.len..], true);
    const ranked = try ranks.rank(a, pooled, false, .mean);
    const moments = try ranks.linearRank(ranked.values, picked, false);
    const z = -math.distQuantile(.normal, alpha / 2, &.{}).?;
    if (!std.math.isFinite(z) or z <= 0) return error.InvalidInput;
    const cstar = @as(f64, @floatFromInt(m)) / 2 - z * @sqrt(moments.variance);
    const c: i64 = @intFromFloat(@floor(cstar));
    const ci: Interval = if (c < 1) .{ .lower = -std.math.inf(f64), .upper = std.math.inf(f64) } else .{ .lower = differences[@intCast(c - 1)], .upper = differences[m - @as(usize, @intCast(c))] };
    var result: Result = .{ .estimate = if (m % 2 == 1) differences[m / 2] else differences[m / 2 - 1] / 2 + differences[m / 2] / 2, .asymptotic = ci, .standard_error = (ci.upper - ci.lower) / (2 * z), .exact = null };
    if (exact) {
        const d = try distribution(a, pooled, y.len);
        result.allocations = d.total;
        const threshold = alpha / 2 * @as(f64, @floatFromInt(d.total));
        var tail = d.total;
        var lower: ?usize = null;
        var upper: ?usize = null;
        var cumulative: u64 = 0;
        for (d.counts, 0..) |count, twice_u| {
            if (count > 0 and @as(f64, @floatFromInt(tail)) <= threshold and lower == null) lower = twice_u;
            tail -= count;
            cumulative += count;
            if (count > 0 and @as(f64, @floatFromInt(cumulative)) <= threshold) upper = twice_u;
        }
        result.lower_critical = if (lower) |twice_u| @as(f64, @floatFromInt(twice_u)) / 2 else null;
        result.upper_critical = if (upper) |twice_u| @as(f64, @floatFromInt(twice_u)) / 2 else null;
        result.exact = .{ .lower = if (lower) |twice_u| differences[m - (twice_u + 1) / 2] else -std.math.inf(f64), .upper = if (upper) |twice_u| differences[m - twice_u / 2 - 1] else std.math.inf(f64) };
    }
    return result;
}

test "NPAR004 original HL complete intervals and independent label enumeration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1.94, 1.94, 2.92, 2.92, 2.92, 2.92, 3.27, 3.27, 3.27, 3.27, 3.70, 3.70, 3.74 };
    const y = [_]f64{ 3.27, 3.27, 3.27, 3.70, 3.70, 3.74 };
    const r = try compute(a, &x, &y, 0.02, true);
    try std.testing.expectApproxEqAbs(@as(f64, 0.35), r.estimate, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0), r.asymptotic.lower, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.82), r.asymptotic.upper, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1762), r.standard_error, 0.00005); // half unit at displayed4decimals
    try std.testing.expectApproxEqAbs(@as(f64, 0), r.exact.?.lower, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1.33), r.exact.?.upper, 1e-14);
    try std.testing.expectEqual(@as(?f64, 67), r.lower_critical);
    try std.testing.expectEqual(@as(?f64, 11), r.upper_critical);
    var pooled: [19]f64 = undefined;
    @memcpy(pooled[0..13], &x);
    @memcpy(pooled[13..], &y);
    const dist = try distribution(a, &pooled, 6);
    var enumerated = [_]u64{0} ** 157;
    // Independent definition: sum pairwise 0/1/2 indicators, no rank sums/DP.
    for (0..(@as(usize, 1) << 19)) |mask| {
        if (@popCount(mask) != 6) continue;
        var twice_u: usize = 0;
        for (pooled, 0..) |yv, j| if (mask & (@as(usize, 1) << @intCast(j)) != 0) {
            for (pooled, 0..) |xv, i| if (mask & (@as(usize, 1) << @intCast(i)) == 0) {
                twice_u += if (yv > xv) @as(usize, 2) else if (yv == xv) @as(usize, 1) else 0;
            };
        };
        enumerated[twice_u] += 1;
    }
    try std.testing.expectEqualSlices(u64, &enumerated, dist.counts);
    try std.testing.expectEqual(@as(u64, 27132), dist.total);
}
test "NPAR004 HL orientation translation odd pair count and unattainable finite tails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try compute(a, &.{ 1, 2, 3 }, &.{ 5, 6, 7 }, 0.2, true);
    const reverse = try compute(a, &.{ 5, 6, 7 }, &.{ 1, 2, 3 }, 0.2, true);
    const shifted = try compute(a, &.{ 101, 102, 103 }, &.{ 105, 106, 107 }, 0.2, true);
    try std.testing.expectEqual(@as(f64, 4), r.estimate);
    try std.testing.expectEqual(-r.estimate, reverse.estimate);
    try std.testing.expectEqual(r.estimate, shifted.estimate);
    try std.testing.expectEqual(r.exact.?.lower, -reverse.exact.?.upper);
    try std.testing.expectEqual(r.exact.?.upper, -reverse.exact.?.lower);
    const tiny = try compute(a, &.{1}, &.{2}, 0.05, true);
    try std.testing.expect(std.math.isNegativeInf(tiny.exact.?.lower));
    try std.testing.expect(std.math.isPositiveInf(tiny.exact.?.upper));
    try std.testing.expectError(error.InvalidInput, compute(a, &.{1}, &.{2}, 0, true));
}
