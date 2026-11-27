//! Deterministic conditional rank distributions, S154 physical pp.7249-7251.
//! Enumerate fixed-margin score tables with their multinomial multiplicities.
//! Exact integer comparisons preserve ties/equidistant tails without a fitted
//! tolerance. Unsupported precision/state domains fail, never approximate.
const std = @import("std");
const ranks = @import("ranks.zig");
const A = std.mem.Allocator;
pub const Result = struct {
    right: bool = false,
    allocations: u64,
    lower_count: u64,
    upper_count: u64,
    two_sided_count: u64,
    point_count: u64,
    pub fn probability(self: Result, count: u64) f64 {
        return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(self.allocations));
    }
    pub fn asRanks(self: Result) ranks.Exact {
        return .{ .allocations = self.allocations, .lower_count = self.lower_count, .upper_count = self.upper_count, .two_sided_count = self.two_sided_count, .lower = self.probability(self.lower_count), .upper = self.probability(self.upper_count), .two_sided = self.probability(self.two_sided_count) };
    }
};
fn gcd(a0: i128, b0: i128) i128 {
    var a = a0;
    var b = b0;
    while (b != 0) {
        const r = @mod(a, b);
        a = b;
        b = r;
    }
    return a;
}
fn add(a: i128, b: i128) !i128 {
    const r = @addWithOverflow(a, b);
    if (r[1] != 0) return error.PrecisionLimit;
    return r[0];
}
fn mul(a: i128, b: i128) !i128 {
    const r = @mulWithOverflow(a, b);
    if (r[1] != 0) return error.PrecisionLimit;
    return r[0];
}
fn lcm(a: i128, b: i128) !i128 {
    return mul(@divExact(a, gcd(a, b)), b);
}
fn choose(n: usize, k0: usize) u64 {
    const k = @min(k0, n - k0);
    var r: u128 = 1;
    for (0..k) |i| r = r * (n - i) / (i + 1);
    return @intCast(r);
}
fn normalize(values: []i128) void {
    var minimum = values[0];
    for (values) |v| minimum = @min(minimum, v);
    var divisor: i128 = 0;
    for (values) |*v| {
        v.* -= minimum;
        divisor = gcd(divisor, v.*);
    }
    if (divisor > 1) for (values) |*v| {
        v.* = @divExact(v.*, divisor);
    };
}
/// Binary f64 observations are represented exactly, not rounded to a decimal
/// grid. The bounded integer domain is explicit and checked before shifts.
pub fn binaryScores(a: A, values: []const f64) ![]i128 {
    if (values.len == 0) return error.InvalidInput;
    const significands = try a.alloc(i128, values.len);
    const exponents = try a.alloc(i32, values.len);
    var minimum: i32 = 1024;
    for (values, 0..) |v, i| {
        if (!std.math.isFinite(v)) return error.InvalidInput;
        if (v == 0) {
            significands[i] = 0;
            exponents[i] = 0;
            continue;
        }
        const bits: @TypeOf(@as(u64, 0)) = @bitCast(v);
        const e = (bits >> 52) & 0x7ff;
        var m = (bits & 0xfffffffffffff) | (if (e != 0) @as(u64, 1) << 52 else 0);
        var exponent: i32 = if (e != 0) @as(i32, @intCast(e)) - 1023 - 52 else -1074;
        const zeros = @ctz(m);
        m >>= @intCast(zeros);
        exponent += @intCast(zeros);
        significands[i] = if (bits >> 63 != 0) -@as(i128, @intCast(m)) else @intCast(m);
        exponents[i] = exponent;
        minimum = @min(minimum, exponent);
    }
    const result = try a.alloc(i128, values.len);
    for (significands, exponents, result) |m, e, *r| {
        if (m == 0) {
            r.* = 0;
            continue;
        }
        const shift = e - minimum;
        if (shift < 0 or shift > 100) return error.PrecisionLimit;
        r.* = try mul(m, @as(i128, 1) << @intCast(shift));
        if (@abs(r.*) > @as(u128, 1) << 120) return error.PrecisionLimit;
    }
    normalize(result);
    return result;
}
pub fn scoreWeights(a: A, values: []const f64, kind: anytype, computed: []const f64) ![]i128 {
    if (values.len > 24) return error.ExactLimit;
    if (kind == .vw or kind == .klotz or kind == .conover) return error.ExactMethodUnverified;
    if (kind == .data) return binaryScores(a, computed);
    const rr = try ranks.rank(a, values, false, .mean);
    const n = values.len;
    var denominator: i128 = 1;
    if (kind == .savage) for (1..n + 1) |i| {
        denominator = try lcm(denominator, @intCast(i));
    };
    var tie_scale: i128 = 1;
    for (rr.groups) |g| tie_scale = try lcm(tie_scale, @intCast(g.count));
    const ordinal = try a.alloc(i128, n);
    var harmonic: i128 = 0;
    for (ordinal, 0..) |*value, i| {
        const r: @TypeOf(@as(i128, 0)) = @intCast(i + 1);
        const nf: i128 = @intCast(n);
        if (kind == .savage) harmonic += @divExact(denominator, @as(i128, @intCast(n - i)));
        value.* = switch (kind) {
            .wilcoxon => r,
            .median => if (2 * r > nf + 1) @as(i128, 1) else 0,
            .savage => harmonic - denominator,
            .ab => @min(r, nf + 1 - r),
            .mood => try mul(2 * r - (nf + 1), 2 * r - (nf + 1)),
            .st => 0,
            else => unreachable,
        };
    }
    if (kind == .st) {
        var lo: usize = 0;
        var hi = n - 1;
        for (0..n) |i| {
            if (i % 4 == 0 or i % 4 == 3) {
                ordinal[lo] = @intCast(i + 1);
                lo += 1;
            } else {
                ordinal[hi] = @intCast(i + 1);
                hi -|= 1;
            }
        }
    }
    const result = try a.alloc(i128, n);
    for (rr.groups) |g| {
        var sum: i128 = 0;
        for (ordinal[g.first - 1 ..][0..g.count]) |v| sum = try add(sum, v);
        const value = try mul(sum, @divExact(tie_scale, @as(i128, @intCast(g.count))));
        for (values, result) |v, *r| if (v == g.value) {
            r.* = value;
        };
    }
    normalize(result);
    return result;
}
const Cell = struct { score: i128, n: usize };
const Walk = struct {
    cells: []Cell,
    remaining: []usize,
    sums: []i128,
    counts: []const usize,
    denominator: i128,
    total_score: i128,
    n: usize,
    selected: usize,
    observed: i128,
    observed_distance: u128,
    rmd: bool = false,
    visited: usize = 0,
    result: Result = .{ .allocations = 0, .lower_count = 0, .upper_count = 0, .two_sided_count = 0, .point_count = 0 },
    fn statistic(self: *Walk) !i128 {
        var value: i128 = 0;
        for (self.sums, self.counts) |sum, count| value = try add(value, try mul(try mul(sum, sum), @divExact(self.denominator, @as(i128, @intCast(count)))));
        return value;
    }
    fn leaf(self: *Walk, weight: u64) !void {
        self.result.allocations += weight;
        if (self.rmd) {
            const sum = self.sums[0];
            if (sum <= self.observed) self.result.lower_count += weight;
            if (sum >= self.observed) self.result.upper_count += weight;
            if (sum == self.observed) self.result.point_count += weight;
            const numerator = try mul(sum, @intCast(self.counts[1]));
            const denominator = try mul(self.total_score - sum, @intCast(self.counts[0]));
            const observed_n = try mul(self.observed, @intCast(self.counts[1]));
            const observed_d = try mul(self.total_score - self.observed, @intCast(self.counts[0]));
            if (try mul(@max(numerator, denominator), @min(observed_n, observed_d)) >= try mul(@min(numerator, denominator), @max(observed_n, observed_d))) self.result.two_sided_count += weight;
            return;
        }
        if (self.counts.len == 2) {
            const sum = self.sums[self.selected];
            if (sum <= self.observed) self.result.lower_count += weight;
            if (sum >= self.observed) self.result.upper_count += weight;
            if (sum == self.observed) self.result.point_count += weight;
            const centered = try add(try mul(sum, @intCast(self.n)), -try mul(self.total_score, @intCast(self.counts[self.selected])));
            if (@abs(centered) >= self.observed_distance) self.result.two_sided_count += weight;
        } else {
            const stat = try self.statistic();
            if (stat <= self.observed) self.result.lower_count += weight;
            if (stat >= self.observed) {
                self.result.upper_count += weight;
                self.result.two_sided_count += weight;
            }
            if (stat == self.observed) self.result.point_count += weight;
        }
    }
    fn visit(self: *Walk, column: usize, weight: u64) anyerror!void {
        self.visited += 1;
        if (self.visited > 2_000_000) return error.ExactLimit;
        if (column == self.cells.len) {
            for (self.remaining) |n| if (n != 0) return;
            try self.leaf(weight);
            return;
        }
        try self.allocate(column, 0, self.cells[column].n, weight);
    }
    fn allocate(self: *Walk, column: usize, group: usize, left: usize, weight: u64) anyerror!void {
        if (group + 1 == self.remaining.len) {
            if (left > self.remaining[group]) return;
            self.remaining[group] -= left;
            const delta = try mul(self.cells[column].score, @intCast(left));
            self.sums[group] = try add(self.sums[group], delta);
            defer {
                self.remaining[group] += left;
                self.sums[group] -= delta;
            }
            try self.visit(column + 1, weight);
            return;
        }
        for (0..@min(left, self.remaining[group]) + 1) |take| {
            self.remaining[group] -= take;
            const delta = try mul(self.cells[column].score, @intCast(take));
            self.sums[group] = try add(self.sums[group], delta);
            defer {
                self.remaining[group] += take;
                self.sums[group] -= delta;
            }
            try self.allocate(column, group + 1, left - take, weight * choose(left, take));
        }
    }
};
pub fn testScores(a: A, weights: []const i128, groups: []const usize, counts: []const usize) !Result {
    return testMode(a, weights, groups, counts, false);
}
fn testMode(a: A, weights: []const i128, groups: []const usize, counts: []const usize, ratio_mode: bool) !Result {
    if (weights.len != groups.len or weights.len == 0 or weights.len > 24 or counts.len < 2 or counts.len > 8) return error.ExactLimit;
    var remaining = weights.len;
    var allocations: u128 = 1;
    var denom: i128 = 1;
    for (counts) |count| {
        if (count == 0 or count > remaining) return error.InvalidInput;
        allocations *= choose(remaining, count);
        if (allocations > std.math.maxInt(u64)) return error.ExactLimit;
        remaining -= count;
        denom = try lcm(denom, @intCast(count));
    }
    if (remaining != 0) return error.InvalidInput;
    const sums = try a.alloc(i128, counts.len);
    @memset(sums, 0);
    const actual = try a.alloc(usize, counts.len);
    @memset(actual, 0);
    var total: i128 = 0;
    for (weights, groups) |score, g| {
        if (g >= counts.len or score < 0) return error.InvalidInput;
        actual[g] += 1;
        sums[g] = try add(sums[g], score);
        total = try add(total, score);
    }
    if (!std.mem.eql(usize, counts, actual)) return error.InvalidInput;
    const selected: usize = if (ratio_mode or counts[0] <= counts[1]) 0 else 1;
    const sorted = try a.dupe(i128, weights);
    std.mem.sort(i128, sorted, {}, std.sort.asc(i128));
    var cells: std.ArrayList(Cell) = .empty;
    for (sorted) |score| {
        if (cells.items.len > 0 and cells.items[cells.items.len - 1].score == score) cells.items[cells.items.len - 1].n += 1 else try cells.append(a, .{ .score = score, .n = 1 });
    }
    var walk: Walk = .{ .cells = cells.items, .remaining = try a.dupe(usize, counts), .sums = sums, .counts = counts, .denominator = denom, .total_score = total, .n = weights.len, .selected = selected, .observed = 0, .observed_distance = 0, .rmd = ratio_mode };
    if (counts.len == 2) {
        walk.observed = sums[selected];
        walk.observed_distance = @abs(try add(try mul(sums[selected], @intCast(weights.len)), -try mul(total, @intCast(counts[selected]))));
    } else walk.observed = try walk.statistic();
    walk.result.right = counts.len > 2 or try mul(walk.observed, @intCast(weights.len)) > try mul(total, @intCast(counts[selected]));
    // Prove the full supported allocation domain fits before traversal.
    _ = try mul(try mul(total, total), denom);
    if (ratio_mode) _ = try mul(try mul(total, total), @as(i128, @intCast(counts[0] * counts[1])));
    @memset(sums, 0);
    try walk.visit(0, 1);
    if (walk.result.allocations != @as(u64, @intCast(allocations))) return error.InvalidInput;
    return walk.result;
}

test "NPAR006 original Savage integer tail agrees with independent labelled enumeration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [_]f64{ 1, 1, 3, 3, 4, 3, 4, 4, 4, 15, 4, 4, 10, 10, 26 };
    const groups = [_]usize{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 };
    const Kind = enum { savage, wilcoxon, median, ab, st, mood, vw, klotz, conover, data };
    const weights = try scoreWeights(a, &values, Kind.savage, &.{});
    const result = try testScores(a, weights, &groups, &.{ 5, 5, 5 });
    // Independently derived exact Savage scores, denominator1081080, from
    // harmonic sums and tie averages. No engine output supplies these values.
    const reference = [_]i128{ -970398, -970398, -755808, -755808, -188644, -755808, -188644, -188644, -188644, 1425111, -188644, -188644, 704391, 704391, 2506191 };
    var observed: i128 = 0;
    for (0..3) |g| {
        var sum: i128 = 0;
        for (reference[g * 5 ..][0..5]) |v| sum += v;
        observed += sum * sum;
    }
    var total: u64 = 0;
    var tail: u64 = 0;
    var point: u64 = 0;
    // Enumerate distinguishable labels, in contrast to production's weighted
    // tied-score tables. 15 choose5 times10 choose5=756756 allocations.
    for (0..(@as(usize, 1) << 15)) |first| {
        if (@popCount(first) != 5) continue;
        var sum1: i128 = 0;
        var rest: [10]i128 = undefined;
        var at: usize = 0;
        for (reference, 0..) |v, i| {
            if (first & (@as(usize, 1) << @intCast(i)) != 0) sum1 += v else {
                rest[at] = v;
                at += 1;
            }
        }
        for (0..(@as(usize, 1) << 10)) |second| {
            if (@popCount(second) != 5) continue;
            var sum2: i128 = 0;
            var sum3: i128 = 0;
            for (rest, 0..) |v, i| {
                if (second & (@as(usize, 1) << @intCast(i)) != 0) sum2 += v else sum3 += v;
            }
            const stat = sum1 * sum1 + sum2 * sum2 + sum3 * sum3;
            total += 1;
            if (stat >= observed) tail += 1;
            if (stat == observed) point += 1;
        }
    }
    try std.testing.expectEqual(@as(u64, 756756), total);
    try std.testing.expectEqual(total, result.allocations);
    try std.testing.expectEqual(tail, result.upper_count);
    try std.testing.expectEqual(point, result.point_count);
    try std.testing.expectEqual(@as(u64, 33696), tail);
    try std.testing.expectEqual(@as(u64, 1080), point);
    try std.testing.expectApproxEqAbs(@as(f64, 24.0 / 539.0), result.probability(tail), 1e-16);
}
test "NPAR006 tied masses asymmetric two-sided tails constant and domain guards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const two = try testScores(a, &.{ 0, 0, 1, 2 }, &.{ 0, 0, 1, 1 }, &.{ 2, 2 });
    try std.testing.expectEqual(@as(u64, 6), two.allocations);
    try std.testing.expectEqual(@as(u64, 1), two.lower_count);
    try std.testing.expectEqual(@as(u64, 2), two.two_sided_count);
    try std.testing.expectEqual(@as(u64, 1), two.point_count);
    const asymmetric = try testScores(a, &.{ 0, 0, 0, 2, 3 }, &.{ 1, 1, 1, 1, 0 }, &.{ 1, 4 });
    try std.testing.expectEqual(@as(u64, 1), asymmetric.two_sided_count);
    try std.testing.expectEqual(@as(u64, 5), asymmetric.allocations);
    const multi = try testScores(a, &.{ 0, 0, 1, 1, 2, 2 }, &.{ 0, 0, 1, 1, 2, 2 }, &.{ 2, 2, 2 });
    try std.testing.expectEqual(@as(u64, 90), multi.allocations);
    try std.testing.expectEqual(@as(u64, 6), multi.upper_count);
    const constant = try testScores(a, &.{ 0, 0, 0, 0 }, &.{ 0, 0, 1, 1 }, &.{ 2, 2 });
    try std.testing.expectEqual(constant.allocations, constant.point_count);
    try std.testing.expectError(error.InvalidInput, testScores(a, &.{ 0, 1 }, &.{ 0, 1 }, &.{ 0, 2 }));
    try std.testing.expectError(error.PrecisionLimit, binaryScores(a, &.{ 1e-300, 1e300 }));
    const raw = try binaryScores(a, &.{ -0.5, 0, 0.5, 1 });
    try std.testing.expectEqualSlices(i128, &.{ 0, 1, 2, 3 }, raw);
}

pub const Rmd = struct { ratio: f64, ratio_two: f64, medians: [2]f64, mean_deviations: [2]f64, counts: [2]usize, exact: Result };
/// Initial validated RMD domain: integer observations of magnitude<=1e12,
/// n<=24. Doubled deviations retain even-sample half-integer medians exactly.
/// Noninteger/wider and observed zero-mean-deviation cases remain explicit gaps.
pub fn rmd(a: A, values: []const f64, groups: []const usize) !Rmd {
    if (values.len != groups.len or values.len > 24 or values.len == 0) return error.ExactLimit;
    var samples = [_]std.ArrayList(i128){ .empty, .empty };
    for (values, groups) |v, g| {
        if (g > 1 or !std.math.isFinite(v)) return error.InvalidInput;
        if (v != @floor(v) or @abs(v) > 1e12) return error.PrecisionLimit;
        try samples[g].append(a, @intFromFloat(v));
    }
    var median2: [2]i128 = undefined;
    var counts: [2]usize = undefined;
    for (&samples, 0..) |*sample, g| {
        const n = sample.items.len;
        if (n == 0) return error.InvalidInput;
        counts[g] = n;
        std.mem.sort(i128, sample.items, {}, std.sort.asc(i128));
        median2[g] = if (n % 2 == 1) 2 * sample.items[n / 2] else sample.items[n / 2 - 1] + sample.items[n / 2];
    }
    const deviations = try a.alloc(i128, values.len);
    var sums = [_]i128{ 0, 0 };
    for (values, groups, deviations) |v, g, *d| {
        d.* = @intCast(@abs(2 * @as(i128, @intFromFloat(v)) - median2[g]));
        sums[g] += d.*;
    }
    if (sums[0] == 0 or sums[1] == 0) return error.DegenerateRmd;
    const numerator = sums[0] * @as(i128, @intCast(counts[1]));
    const denominator = sums[1] * @as(i128, @intCast(counts[0]));
    const ratio = @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
    return .{ .ratio = ratio, .ratio_two = @max(ratio, 1 / ratio), .medians = .{ @as(f64, @floatFromInt(median2[0])) / 2, @as(f64, @floatFromInt(median2[1])) / 2 }, .mean_deviations = .{ @as(f64, @floatFromInt(sums[0])) / (2 * @as(f64, @floatFromInt(counts[0]))), @as(f64, @floatFromInt(sums[1])) / (2 * @as(f64, @floatFromInt(counts[1]))) }, .counts = counts, .exact = try testMode(a, deviations, groups, &counts, true) };
}
test "NPAR006 RMD exact conditional deviations point mid tails and zero permutation cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try rmd(a, &.{ 1, 3, 5, 2, 3, 4 }, &.{ 0, 0, 0, 1, 1, 1 });
    try std.testing.expectEqual(@as(f64, 2), r.ratio);
    try std.testing.expectEqualSlices(f64, &.{ 3, 3 }, &r.medians);
    try std.testing.expectEqual(@as(u64, 20), r.exact.allocations);
    try std.testing.expectEqual(@as(u64, 6), r.exact.upper_count);
    try std.testing.expectEqual(@as(u64, 12), r.exact.two_sided_count);
    try std.testing.expectEqual(@as(u64, 4), r.exact.point_count);
    // Independent 20 labelled subsets of deviations0,0,1,1,0,2 include
    // two infinite RMD2 endpoints (all three zeros in either sample).
    const unequal = try rmd(a, &.{ 2, 3, 4, 1, 5 }, &.{ 0, 0, 0, 1, 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), unequal.ratio, 1e-16);
    try std.testing.expectEqual(@as(u64, 10), unequal.exact.allocations);
    try std.testing.expectEqual(@as(u64, 1), unequal.exact.lower_count);
    try std.testing.expectEqual(@as(u64, 3), unequal.exact.two_sided_count);
    const z = try rmd(a, &.{ 2, 2, 3, 1, 2, 4 }, &.{ 0, 0, 0, 1, 1, 1 });
    const d = [_]usize{ 0, 0, 1, 1, 0, 2 };
    var lower: u64 = 0;
    var point: u64 = 0;
    var two: u64 = 0;
    for (0..64) |mask| {
        if (@popCount(mask) != 3) continue;
        var sum: usize = 0;
        for (d, 0..) |v, i| if (mask & (@as(usize, 1) << @intCast(i)) != 0) {
            sum += v;
        };
        if (sum <= 1) lower += 1;
        if (sum == 1) point += 1;
        if (sum == 0 or sum == 4 or @max(sum, 4 - sum) >= 3 * @min(sum, 4 - sum)) two += 1;
    }
    try std.testing.expectEqual(lower, z.exact.lower_count);
    try std.testing.expectEqual(point, z.exact.point_count);
    try std.testing.expectEqual(two, z.exact.two_sided_count);
    try std.testing.expectEqual(@as(u64, 14), two);
    try std.testing.expectError(error.DegenerateRmd, rmd(a, &.{ 1, 1, 2, 3 }, &.{ 0, 0, 1, 1 }));
    try std.testing.expectError(error.PrecisionLimit, rmd(a, &.{ 0.1, 2, 3, 4 }, &.{ 0, 0, 1, 1 }));
}

pub const Ks = struct { statistics: [3]f64, tail_counts: [3]u64, point_counts: [3]u64, allocations: u64, p: [3]f64 };
const KsWalk = struct {
    ties: []const ranks.TieGroup,
    n0: usize,
    n1: usize,
    observed: [3]usize,
    total: u64 = 0,
    tails: [3]u64 = @splat(0),
    points: [3]u64 = @splat(0),
    visited: usize = 0,
    fn visit(self: *KsWalk, i: usize, a: usize, b: usize, plus: usize, minus: usize, weight: u64) anyerror!void {
        self.visited += 1;
        if (self.visited > 2_000_000) return error.ExactLimit;
        if (i == self.ties.len) {
            if (a != self.n0 or b != self.n1) return;
            self.total += weight;
            for ([_]usize{ @max(plus, minus), plus, minus }, self.observed, 0..) |value, observed, j| {
                if (value >= observed) self.tails[j] += weight;
                if (value == observed) self.points[j] += weight;
            }
            return;
        }
        const count = self.ties[i].count;
        for (0..@min(count, self.n0 - a) + 1) |take| {
            if (count - take > self.n1 - b) continue;
            const next_a = a + take;
            const next_b = b + count - take;
            const difference = @as(i64, @intCast(self.n1 * next_a)) - @as(i64, @intCast(self.n0 * next_b));
            try self.visit(i + 1, next_a, next_b, @max(plus, if (difference > 0) @as(usize, @intCast(difference)) else 0), @max(minus, if (difference < 0) @as(usize, @intCast(-difference)) else 0), weight * choose(count, take));
        }
    }
};
pub fn ks(a: A, values: []const f64, groups: []const usize) !Ks {
    if (values.len != groups.len or values.len == 0 or values.len > 60) return error.ExactLimit;
    var n0: usize = 0;
    for (values, groups) |v, g| {
        if (!std.math.isFinite(v) or g > 1) return error.InvalidInput;
        if (g == 0) n0 += 1;
    }
    const n1 = values.len - n0;
    if (n0 == 0 or n1 == 0) return error.InvalidInput;
    const rr = try ranks.rank(a, values, false, .mean);
    var used0: usize = 0;
    var used1: usize = 0;
    var plus: usize = 0;
    var minus: usize = 0;
    for (rr.groups) |tie| {
        for (values, groups) |v, g| if (v == tie.value) {
            if (g == 0) used0 += 1 else used1 += 1;
        };
        const difference = @as(i64, @intCast(n1 * used0)) - @as(i64, @intCast(n0 * used1));
        if (difference > 0) plus = @max(plus, @as(usize, @intCast(difference))) else minus = @max(minus, @as(usize, @intCast(-difference)));
    }
    var walk: KsWalk = .{ .ties = rr.groups, .n0 = n0, .n1 = n1, .observed = .{ @max(plus, minus), plus, minus } };
    try walk.visit(0, 0, 0, 0, 0, 1);
    if (walk.total != choose(values.len, n0)) return error.InvalidInput;
    var result: Ks = .{ .statistics = undefined, .tail_counts = walk.tails, .point_counts = walk.points, .allocations = walk.total, .p = undefined };
    for (0..3) |i| {
        result.statistics[i] = @as(f64, @floatFromInt(walk.observed[i])) / @as(f64, @floatFromInt(n0 * n1));
        result.p[i] = @as(f64, @floatFromInt(walk.tails[i])) / @as(f64, @floatFromInt(walk.total));
    }
    return result;
}
test "NPAR006 KS tied empirical steps exact tails distinguish asymptotic and artificial tie order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try ks(a, &.{ 1, 1, 2, 2 }, &.{ 0, 0, 1, 1 });
    try std.testing.expectEqual(@as(u64, 6), r.allocations);
    try std.testing.expectEqualSlices(u64, &.{ 2, 1, 6 }, &r.tail_counts);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 0 }, &r.statistics);
    const unequal = try ks(a, &.{ 1, 2, 3, 4, 5 }, &.{ 0, 0, 1, 1, 1 });
    try std.testing.expectEqual(@as(u64, 10), unequal.allocations);
    try std.testing.expectEqualSlices(u64, &.{ 2, 1, 10 }, &unequal.tail_counts);
    const constant = try ks(a, &.{ 1, 1, 1, 1 }, &.{ 0, 0, 1, 1 });
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 0 }, &constant.statistics);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 1 }, &constant.p);
    // Independent six label allocations evaluated after BOTH observations at
    // each tied value; counting intermediate tie order would give false tails.
    var tails = [_]u64{ 0, 0, 0 };
    for (0..16) |mask| {
        if (@popCount(mask) != 2) continue;
        var first: usize = 0;
        for (0..2) |i| if (mask & (@as(usize, 1) << @intCast(i)) != 0) {
            first += 1;
        };
        const diff = @as(i64, @intCast(2 * first)) - @as(i64, @intCast(2 * (2 - first)));
        const p: usize = if (diff > 0) @intCast(diff) else 0;
        const m: usize = if (diff < 0) @intCast(-diff) else 0;
        for ([_]usize{ @max(p, m), p, m }, [_]usize{ 4, 4, 0 }, 0..) |v, o, j| if (v >= o) {
            tails[j] += 1;
        };
    }
    try std.testing.expectEqualSlices(u64, &tails, &r.tail_counts);
}
