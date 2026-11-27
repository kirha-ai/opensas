//! Shared rank/tie and two-sample inference contracts (STAT-COMMON-017).
//! SAS/STAT 15.4, physical PDF pp. 295-302 and 7236-7239: rank internal
//! numeric values, average equal ranks, and distinguish conditional exact
//! permutation tails from continuity-corrected normal approximations. Exact
//! two-sided tails follow physical PDF p. 7251: equidistant from E0(T).
const std = @import("std");

pub const Ties = enum { mean, low, high, dense };
pub const TieGroup = struct { value: f64, first: usize, count: usize };
pub const Ranked = struct {
    /// Original observation order; NaN inputs have NaN rank and no tie group.
    values: []f64,
    /// Sorted order, first is the one-based ordinal position before averaging.
    groups: []TieGroup,
    n: usize,
    /// Sum(t^3-t), useful for the Wilcoxon/Kruskal-Wallis tie correction.
    tie_correction: f64,
};

pub fn rank(a: std.mem.Allocator, values: []const f64, descending: bool, ties: Ties) !Ranked {
    const Entry = struct { index: usize, value: f64 };
    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(a);
    const result = try a.alloc(f64, values.len);
    errdefer a.free(result);
    @memset(result, std.math.nan(f64));
    for (values, 0..) |v, i| {
        if (!std.math.isNan(v)) try entries.append(a, .{ .index = i, .value = v });
    }
    std.mem.sort(Entry, entries.items, descending, struct {
        fn less(desc: bool, x: Entry, y: Entry) bool {
            return if (desc) x.value > y.value else x.value < y.value;
        }
    }.less);
    var groups: std.ArrayList(TieGroup) = .empty;
    errdefer groups.deinit(a);
    var correction: f64 = 0;
    var i: usize = 0;
    while (i < entries.items.len) {
        var j = i + 1;
        while (j < entries.items.len and entries.items[j].value == entries.items[i].value) j += 1;
        try groups.append(a, .{ .value = entries.items[i].value, .first = i + 1, .count = j - i });
        const lo: f64 = @floatFromInt(i + 1);
        const hi: f64 = @floatFromInt(j);
        const r: f64 = switch (ties) {
            .mean => (lo + hi) / 2,
            .low => lo,
            .high => hi,
            .dense => @floatFromInt(groups.items.len),
        };
        for (entries.items[i..j]) |e| result[e.index] = r;
        const t: f64 = @floatFromInt(j - i);
        correction += t * t * t - t;
        i = j;
    }
    return .{ .values = result, .groups = try groups.toOwnedSlice(a), .n = entries.items.len, .tie_correction = correction };
}

pub const LinearRank = struct {
    n: usize,
    selected_n: usize,
    sum: f64,
    expected: f64,
    variance: f64,
    /// Null for constant scores: no asymptotic standardized test exists.
    z: ?f64,
    /// Two-group ANOVA score statistic, without continuity correction.
    chi_square: ?f64,
};

/// Caller selects the tested class; PROC NPAR1WAY chooses the smaller class,
/// with first-input class breaking equal-size ties. NaN scores are excluded.
/// No probability here is labeled exact: z uses a normal approximation.
pub fn linearRank(scores: []const f64, selected: []const bool, continuity: bool) error{InvalidInput}!LinearRank {
    if (scores.len != selected.len) return error.InvalidInput;
    var n: usize = 0;
    var n1: usize = 0;
    var total: f64 = 0;
    var s: f64 = 0;
    for (scores, selected) |r, pick| {
        if (std.math.isNan(r)) continue;
        if (!std.math.isFinite(r)) return error.InvalidInput;
        n += 1;
        total += r;
        if (pick) {
            n1 += 1;
            s += r;
        }
    }
    if (n1 == 0 or n1 == n) return error.InvalidInput;
    const nf: f64 = @floatFromInt(n);
    const n1f: f64 = @floatFromInt(n1);
    const mean = total / nf;
    var ss: f64 = 0;
    for (scores) |r| {
        if (!std.math.isNan(r)) ss += (r - mean) * (r - mean);
    }
    const variance = n1f * (nf - n1f) / (nf * (nf - 1)) * ss;
    const expected = n1f * mean;
    const delta = s - expected;
    // SAS adds/subtracts 0.5 according to the original sign; do not clamp.
    const corrected = delta + if (!continuity or delta == 0) @as(f64, 0) else if (delta < 0) @as(f64, 0.5) else @as(f64, -0.5);
    return .{ .n = n, .selected_n = n1, .sum = s, .expected = expected, .variance = variance, .z = if (variance > 0) corrected / @sqrt(variance) else null, .chi_square = if (variance > 0) delta * delta / variance else null };
}

pub const Exact = struct {
    allocations: u64,
    lower_count: u64,
    upper_count: u64,
    two_sided_count: u64,
    /// Inclusive conditional permutation tails. Distinct tied observations
    /// remain distinct allocations, rather than equally weighting tie patterns.
    lower: f64,
    upper: f64,
    two_sided: f64,
};

/// Exact rank-sum distribution by subset-count dynamic programming. Doubled
/// midranks are integral. The caller must supply ascending MEAN ranks. Guard
/// invalid rank vectors and resource limits explicitly; never substitute a
/// normal approximation. n<=60 keeps every binomial allocation count in u64.
pub fn exactRankSum(a: std.mem.Allocator, ranks: []const f64, selected: []const bool) !Exact {
    const moments = try linearRank(ranks, selected, false);
    if (moments.n > 60) return error.ExactLimit;
    var weights: std.ArrayList(usize) = .empty;
    defer weights.deinit(a);
    var total_weight: usize = 0;
    var observed: usize = 0;
    for (ranks, selected) |r, pick| {
        if (std.math.isNan(r)) continue;
        if (r < 1 or r > @as(f64, @floatFromInt(moments.n)) or r * 2 != @floor(r * 2)) return error.InvalidInput;
        const w: usize = @intFromFloat(r * 2);
        try weights.append(a, w);
        total_weight += w;
        if (pick) observed += w;
    }
    if (total_weight != moments.n * (moments.n + 1)) return error.InvalidInput;
    std.mem.sort(usize, weights.items, {}, std.sort.asc(usize));
    var first: usize = 0;
    while (first < weights.items.len) {
        var end = first + 1;
        while (end < weights.items.len and weights.items[end] == weights.items[first]) end += 1;
        // The repeated doubled midrank must equal the endpoints' sum.
        if (weights.items[first] != first + 1 + end) return error.InvalidInput;
        first = end;
    }
    const width = total_weight + 1;
    const dp = try a.alloc(u64, (moments.selected_n + 1) * width);
    defer a.free(dp);
    @memset(dp, 0);
    dp[0] = 1;
    for (weights.items, 0..) |w, index| {
        var k = @min(index + 1, moments.selected_n);
        while (k > 0) : (k -= 1) {
            var s = total_weight;
            while (s >= w) : (s -= 1) dp[k * width + s] += dp[(k - 1) * width + s - w];
        }
    }
    var lower: u64 = 0;
    var upper: u64 = 0;
    var two: u64 = 0;
    var total: u64 = 0;
    // Integer arithmetic for |S-E(S)| avoids tolerance-dependent tail inclusion.
    const center: i64 = @intCast(moments.selected_n * total_weight);
    const distance = @abs(@as(i64, @intCast(observed * moments.n)) - center);
    for (dp[moments.selected_n * width ..][0..width], 0..) |count, s| {
        total += count;
        if (s <= observed) lower += count;
        if (s >= observed) upper += count;
        if (@abs(@as(i64, @intCast(s * moments.n)) - center) >= distance) two += count;
    }
    const den: f64 = @floatFromInt(total);
    return .{ .allocations = total, .lower_count = lower, .upper_count = upper, .two_sided_count = two, .lower = @as(f64, @floatFromInt(lower)) / den, .upper = @as(f64, @floatFromInt(upper)) / den, .two_sided = @as(f64, @floatFromInt(two)) / den };
}

test "STAT-COMMON-017 ranks reverse ties constants missing and exact equality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nan = std.math.nan(f64);
    const x = [_]f64{ 3, 1, nan, 3, 2 };
    const r = try rank(a, &x, false, .mean);
    try std.testing.expectEqualSlices(f64, &.{ 3.5, 1 }, r.values[0..2]);
    try std.testing.expect(std.math.isNan(r.values[2]));
    try std.testing.expectEqualSlices(f64, &.{ 3.5, 2 }, r.values[3..]);
    try std.testing.expectEqual(@as(usize, 4), r.n);
    try std.testing.expectEqual(@as(f64, 6), r.tie_correction);
    try std.testing.expectEqual(@as(usize, 3), r.groups.len);
    try std.testing.expectEqual(@as(usize, 2), r.groups[2].count);
    const reversed = try rank(a, &x, true, .mean);
    for (r.values, reversed.values) |v, rv| if (!std.math.isNan(v)) try std.testing.expectEqual(@as(f64, 5), v + rv);
    for ([_]Ties{ .low, .high, .dense }, [_]f64{ 3, 4, 3 }) |kind, want| {
        const q = try rank(a, &x, false, kind);
        try std.testing.expectEqual(want, q.values[0]);
    }
    const constant = try rank(a, &.{ 7, 7, 7, nan }, false, .mean);
    const m = try linearRank(constant.values, &.{ true, false, false, true }, true);
    try std.testing.expectEqual(@as(f64, 0), m.variance);
    try std.testing.expect(m.z == null and m.chi_square == null);
    const e = try exactRankSum(a, constant.values, &.{ true, false, false, true });
    try std.testing.expectEqual(@as(u64, 3), e.allocations);
    try std.testing.expectEqual(@as(f64, 1), e.two_sided);
    const close = try rank(a, &.{ 1, 1 + 2 * std.math.floatEps(f64) }, false, .mean);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, close.values);
    const empty = try rank(a, &.{ nan, nan }, false, .mean);
    try std.testing.expectEqual(@as(usize, 0), empty.n);
    try std.testing.expectError(error.InvalidInput, linearRank(empty.values, &.{ true, false }, true));
    try std.testing.expectError(error.InvalidInput, linearRank(&.{ 1, 2 }, &.{true}, true));
    try std.testing.expectError(error.InvalidInput, exactRankSum(a, &.{ 1.2, 1.8 }, &.{ true, false }));
}

test "STAT-COMMON-017 tied original rank sum agrees with independent enumeration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Original public/synthetic fixture after ROUND(x,10), preserved here so
    // deleting the temporary reference directory cannot remove the regression.
    const x = [_]f64{ 40, 90, 80, 90, 120, 100, 90, 100, 90, 90, 120, 70 };
    const pick = [_]bool{ true, true, true, true, true, true, false, false, false, false, false, false };
    const r = try rank(a, &x, false, .mean);
    try std.testing.expectEqualSlices(f64, &.{ 1, 6, 3, 6, 11.5, 9.5, 6, 9.5, 6, 6, 11.5, 2 }, r.values);
    try std.testing.expectEqual(@as(f64, 132), r.tie_correction); // 5^3-5 + 2*(2^3-2)
    const m = try linearRank(r.values, &pick, true);
    try std.testing.expectEqual(@as(f64, 37), m.sum);
    try std.testing.expectEqual(@as(f64, 39), m.expected);
    try std.testing.expectEqual(@as(f64, 36), m.variance);
    try std.testing.expectEqual(@as(f64, -0.25), m.z.?);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 9.0), m.chi_square.?, 1e-15);
    const exact = try exactRankSum(a, r.values, &pick);
    // Independent exhaustive label enumeration, not the DP recurrence. All
    // choose(12,6)=924 assignments equiprobable, including tied observations.
    var total: u64 = 0;
    var lower: u64 = 0;
    var upper: u64 = 0;
    var two: u64 = 0;
    for (0..(1 << 12)) |mask| {
        if (@popCount(mask) != 6) continue;
        var sum: f64 = 0;
        for (r.values, 0..) |v, i| if ((mask & (@as(usize, 1) << @intCast(i))) != 0) {
            sum += v;
        };
        total += 1;
        if (sum <= 37) lower += 1;
        if (sum >= 37) upper += 1;
        if (@abs(sum - 39) >= 2) two += 1;
    }
    try std.testing.expectEqual(@as(u64, 924), total);
    try std.testing.expectEqual(total, exact.allocations);
    try std.testing.expectEqual(lower, exact.lower_count);
    try std.testing.expectEqual(upper, exact.upper_count);
    try std.testing.expectEqual(two, exact.two_sided_count);
    try std.testing.expectEqual(@as(u64, 370), lower);
    try std.testing.expectEqual(@as(u64, 740), two);
    // Displayed SAS values 0.4004 and 0.8009: half-unit in 4 decimals.
    try std.testing.expectApproxEqAbs(@as(f64, 0.4004), exact.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8009), exact.two_sided, 0.00005);
}

test "STAT-COMMON-017 asymmetric exact tails and explicit exact resource limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try rank(a, &.{ 1, 1, 1, 2, 3 }, false, .mean);
    // Five equally likely singleton allocations have sums 2,2,2,4,5.
    // For observed 5, mean 3, |S-3|>=2 includes only 5: P2=1/5.
    // Doubling the smaller one-sided tail would incorrectly give 2/5.
    const e = try exactRankSum(a, r.values, &.{ false, false, false, false, true });
    try std.testing.expectEqual(@as(u64, 5), e.allocations);
    try std.testing.expectEqual(@as(u64, 1), e.upper_count);
    try std.testing.expectEqual(@as(u64, 1), e.two_sided_count);
    try std.testing.expectEqual(@as(f64, 0.2), e.two_sided);
    // These sum correctly to n(n+1)/2 but are not valid midranks.
    try std.testing.expectError(error.InvalidInput, exactRankSum(a, &.{ 1, 1, 4, 4 }, &.{ true, false, false, false }));
    var many: [61]f64 = undefined;
    var selected = [_]bool{false} ** 61;
    selected[0] = true;
    for (&many, 0..) |*v, i| v.* = @floatFromInt(i + 1);
    try std.testing.expectError(error.ExactLimit, exactRankSum(a, &many, &selected));
}
