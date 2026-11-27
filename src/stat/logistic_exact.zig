//! Finite scalar exact conditional distributions, S154 physical pp.5950–5953.
//! Counts are checked integers. Network mode factors stratum case constraints;
//! direct mode propagates the global sufficient-statistic states through each
//! observation. Neither mode samples or substitutes asymptotic probabilities.
const std = @import("std");
const diag = @import("../diag.zig");
const conditional = @import("logistic_conditional.zig");
const A = std.mem.Allocator;
pub const Method = enum { network, direct };
pub const Estimate = enum { none, parm, odds, both };
pub const Request = struct { variable: usize, estimate: Estimate = .none, alpha: ?f64 = null, midp_interval: bool = false, delta1: f64 = 0.5, delta2: f64 = 1, one_sided: bool = false };
pub const Point = struct { value: i64, count: u128 };
pub const Distribution = struct { points: []const Point, observed: i64, total: u128 };
pub const Tests = struct { observed_probability: f64, score: f64, probability_exact: f64, probability_mid: f64, score_exact: f64, score_mid: f64 };
pub const Inference = struct { estimate: f64, standard_error: f64, lower: f64, upper: f64, p_value: f64, median_unbiased: bool };
const Map = std.AutoHashMapUnmanaged(i64, u128);
const max_states = 65536;
fn add(a: A, map: *Map, key: i64, count: u128) diag.Error!void {
    if (map.count() >= max_states and !map.contains(key)) return error.ExecError;
    const entry = try map.getOrPut(a, key);
    entry.value_ptr.* = if (entry.found_existing) std.math.add(u128, entry.value_ptr.*, count) catch return error.ExecError else count;
}
pub fn build(a: A, x: []const f64, y: []const f64, strata: []const conditional.Stratum, method: Method) diag.Error!Distribution {
    if (x.len != y.len or x.len == 0 or x.len > 4096 or strata.len == 0) return error.ExecError;
    const integers = try a.alloc(i64, x.len);
    defer a.free(integers);
    var observed: i64 = 0;
    for (x, y, integers) |value, response, *integer| {
        if (!std.math.isFinite(value) or @trunc(value) != value or @abs(value) > 1e6 or (response != 0 and response != 1)) return error.ExecError;
        integer.* = @intFromFloat(value);
        if (response == 1) observed = std.math.add(i64, observed, integer.*) catch return error.ExecError;
    }
    const seen = try a.alloc(bool, x.len);
    defer a.free(seen);
    @memset(seen, false);
    var global: Map = .empty;
    defer global.deinit(a);
    try add(a, &global, 0, 1);
    for (strata) |stratum| {
        if (stratum.rows.len == 0 or stratum.rows.len > 128 or stratum.events > stratum.rows.len) return error.ExecError;
        var events: usize = 0;
        for (stratum.rows) |row| {
            if (row >= x.len or seen[row]) return error.ExecError;
            seen[row] = true;
            if (y[row] == 1) events += 1;
        }
        if (events != stratum.events) return error.ExecError;
        const m = stratum.events;
        const states = try a.alloc(Map, m + 1);
        defer a.free(states);
        for (states) |*map| map.* = .empty;
        defer for (states) |*map| map.deinit(a);
        if (method == .network) try add(a, &states[0], 0, 1) else {
            var iterator = global.iterator();
            while (iterator.next()) |entry| try add(a, &states[0], entry.key_ptr.*, entry.value_ptr.*);
        }
        var transitions: usize = 0;
        for (stratum.rows, 0..) |row, i| {
            var selected = @min(m, i + 1);
            while (selected > 0) : (selected -= 1) {
                var iterator = states[selected - 1].iterator();
                while (iterator.next()) |entry| {
                    transitions += 1;
                    if (transitions > 4_000_000) return error.ExecError;
                    const value = std.math.add(i64, entry.key_ptr.*, integers[row]) catch return error.ExecError;
                    try add(a, &states[selected], value, entry.value_ptr.*);
                }
            }
        }
        var next: Map = .empty;
        errdefer next.deinit(a);
        if (method == .network) {
            if (@as(u64, global.count()) * states[m].count() > 4_000_000) return error.ExecError;
            var left = global.iterator();
            while (left.next()) |first| {
                var right = states[m].iterator();
                while (right.next()) |second| {
                    const value = std.math.add(i64, first.key_ptr.*, second.key_ptr.*) catch return error.ExecError;
                    const count = std.math.mul(u128, first.value_ptr.*, second.value_ptr.*) catch return error.ExecError;
                    try add(a, &next, value, count);
                }
            }
        } else {
            var iterator = states[m].iterator();
            while (iterator.next()) |entry| try add(a, &next, entry.key_ptr.*, entry.value_ptr.*);
        }
        global.deinit(a);
        global = next;
    }
    for (seen) |value| if (!value) return error.ExecError;
    const points = try a.alloc(Point, global.count());
    var iterator = global.iterator();
    var i: usize = 0;
    var total: u128 = 0;
    while (iterator.next()) |entry| {
        points[i] = .{ .value = entry.key_ptr.*, .count = entry.value_ptr.* };
        total = std.math.add(u128, total, entry.value_ptr.*) catch return error.ExecError;
        i += 1;
    }
    const Sort = struct {
        fn less(_: void, left: Point, right: Point) bool {
            return left.value < right.value;
        }
    };
    std.mem.sort(Point, points, {}, Sort.less);
    if (total == 0 or !global.contains(observed)) return error.ExecError;
    return .{ .points = points, .observed = observed, .total = total };
}
fn probability(count: u128, total: u128) f64 {
    return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(total));
}
fn wideFloat(value: i256) f64 {
    // LLVM cannot lower a direct i256->f64 library conversion on this target.
    // Split into exactly scaled128-bit limbs; integer comparisons stay exact.
    const magnitude: u256 = @abs(value);
    const low: u128 = @truncate(magnitude);
    const high: u128 = @intCast(magnitude >> 128);
    const result = @as(f64, @floatFromInt(high)) * 0x1p128 + @as(f64, @floatFromInt(low));
    return if (value < 0) -result else result;
}
pub fn tests(distribution: Distribution, delta1: f64, delta2: f64) diag.Error!Tests {
    if (!(delta1 >= 0 and delta1 <= 1 and delta2 >= 0 and delta2 <= 1) or distribution.total == 0) return error.ExecError;
    var moment: i256 = 0;
    var observed_count: u128 = 0;
    for (distribution.points) |point| {
        moment += @as(i256, point.value) * @as(i256, point.count);
        if (point.value == distribution.observed) observed_count = point.count;
    }
    if (observed_count == 0) return error.ExecError;
    const difference: i256 = @as(i256, distribution.observed) * @as(i256, distribution.total) - moment;
    const observed_square: i512 = @as(i512, difference) * @as(i512, difference);
    var p_strict: u128 = 0;
    var p_ties: u128 = 0;
    var s_strict: u128 = 0;
    var s_ties: u128 = 0;
    const origin = distribution.observed;
    // Center at the observation using the exact integer first moment. This
    // retains a tiny nonzero score even when a central point has huge mass.
    const mean = -wideFloat(difference) / @as(f64, @floatFromInt(distribution.total));
    var variance: f64 = 0;
    for (distribution.points) |point| {
        const centered = @as(f64, @floatFromInt(point.value - origin)) - mean;
        variance += probability(point.count, distribution.total) * centered * centered;
        if (point.value == distribution.observed) continue;
        if (point.count < observed_count) p_strict += point.count else if (point.count == observed_count) p_ties += point.count;
        const deviation: i256 = @as(i256, point.value) * @as(i256, distribution.total) - moment;
        const square: i512 = @as(i512, deviation) * @as(i512, deviation);
        if (square > observed_square) s_strict += point.count else if (square == observed_square) s_ties += point.count;
    }
    const mass = probability(observed_count, distribution.total);
    const centered = @as(f64, @floatFromInt(distribution.observed - origin)) - mean;
    return .{ .observed_probability = mass, .score = if (variance > 0) centered * centered / variance else 0, .probability_exact = probability(p_strict + p_ties + observed_count, distribution.total), .probability_mid = probability(p_strict, distribution.total) + delta1 * mass + delta2 * probability(p_ties, distribution.total), .score_exact = probability(s_strict + s_ties + observed_count, distribution.total), .score_mid = probability(s_strict, distribution.total) + delta1 * mass + delta2 * probability(s_ties, distribution.total) };
}
pub const Moments = struct { mean: f64, centered_mean: f64, variance: f64, observed_mass: f64, left: f64, right: f64 };
pub fn moments(distribution: Distribution, beta: f64) diag.Error!Moments {
    if (!std.math.isFinite(beta) or distribution.points.len == 0) return error.ExecError;
    const origin = distribution.observed;
    var maximum: f64 = -std.math.inf(f64);
    for (distribution.points) |point| maximum = @max(maximum, @log(@as(f64, @floatFromInt(point.count))) + @as(f64, @floatFromInt(point.value - origin)) * beta);
    var sum: f64 = 0;
    var mean: f64 = 0;
    var mass: f64 = 0;
    var left: f64 = 0;
    var right: f64 = 0;
    for (distribution.points) |point| {
        const centered: f64 = @floatFromInt(point.value - origin);
        const weight = @exp(@log(@as(f64, @floatFromInt(point.count))) + centered * beta - maximum);
        sum += weight;
        mean += weight * centered;
        if (point.value == origin) mass += weight;
        if (point.value <= origin) left += weight;
        if (point.value >= origin) right += weight;
    }
    mean /= sum;
    var variance: f64 = 0;
    for (distribution.points) |point| {
        const centered = @as(f64, @floatFromInt(point.value - origin)) - mean;
        const weight = @exp(@log(@as(f64, @floatFromInt(point.count))) + @as(f64, @floatFromInt(point.value - origin)) * beta - maximum);
        variance += weight * centered * centered / sum;
    }
    return .{ .mean = mean + @as(f64, @floatFromInt(origin)), .centered_mean = mean, .variance = variance, .observed_mass = mass / sum, .left = left / sum, .right = right / sum };
}
fn meanRoot(distribution: Distribution) diag.Error!f64 {
    var low: f64 = -1;
    var high: f64 = 1;
    for (0..40) |_| {
        if ((try moments(distribution, low)).centered_mean <= 0) break;
        low *= 2;
    }
    for (0..40) |_| {
        if ((try moments(distribution, high)).centered_mean >= 0) break;
        high *= 2;
    }
    var beta: f64 = 0;
    for (0..100) |_| {
        const value = try moments(distribution, beta);
        const score = -value.centered_mean;
        if (!(value.variance > 0) or !std.math.isFinite(value.variance)) return error.ExecError;
        if (@abs(score / value.variance) <= 1e-12 * (1 + @abs(beta))) return beta;
        if (score > 0) low = beta else high = beta;
        const candidate = beta + score / value.variance;
        beta = if (std.math.isFinite(candidate) and candidate > low and candidate < high) candidate else (low + high) / 2;
    }
    return error.ExecError;
}
fn tailRoot(distribution: Distribution, right: bool, target: f64, delta: f64) diag.Error!f64 {
    if (!(target > 0 and target < 1 and delta >= 0 and delta <= 1)) return error.ExecError;
    var low: f64 = -1;
    var high: f64 = 1;
    for (0..40) |_| {
        const v = try moments(distribution, low);
        const tail = (if (right) v.right else v.left) - (1 - delta) * v.observed_mass;
        if (if (right) tail <= target else tail >= target) break;
        low *= 2;
    }
    for (0..40) |_| {
        const v = try moments(distribution, high);
        const tail = (if (right) v.right else v.left) - (1 - delta) * v.observed_mass;
        if (if (right) tail >= target else tail <= target) break;
        high *= 2;
    }
    for (0..120) |_| {
        const beta = (low + high) / 2;
        const v = try moments(distribution, beta);
        const tail = (if (right) v.right else v.left) - (1 - delta) * v.observed_mass;
        if (@abs(tail - target) <= 1e-12 * @min(target, 1 - target)) return beta;
        if (if (right) tail < target else tail > target) low = beta else high = beta;
    }
    return error.ExecError;
}
pub fn infer(distribution: Distribution, alpha: f64, midp: bool, delta1: f64, one_sided: bool) diag.Error!Inference {
    if (distribution.points.len < 2 or !(alpha > 0 and alpha < 1)) return error.ExecError;
    const minimum = distribution.points[0].value;
    const maximum = distribution.points[distribution.points.len - 1].value;
    const low_boundary = distribution.observed == minimum;
    const high_boundary = distribution.observed == maximum;
    const median = low_boundary or high_boundary;
    const baseline = try moments(distribution, 0);
    const delta: f64 = if (midp) delta1 else 1;
    if (median and delta <= alpha) return error.ExecError;
    const estimate = if (median) try tailRoot(distribution, high_boundary, 0.5, 1) else try meanRoot(distribution);
    const fitted = try moments(distribution, estimate);
    const tail = @min(baseline.left, baseline.right);
    const target = if (median or one_sided) alpha else alpha / 2;
    var lower = if (low_boundary) -std.math.inf(f64) else try tailRoot(distribution, true, target, delta);
    var upper = if (high_boundary) std.math.inf(f64) else try tailRoot(distribution, false, target, delta);
    if (one_sided and !median) {
        if (baseline.right <= baseline.left) upper = std.math.inf(f64) else lower = -std.math.inf(f64);
    }
    return .{ .estimate = estimate, .standard_error = if (median) std.math.nan(f64) else 1 / @sqrt(fitted.variance), .lower = lower, .upper = upper, .p_value = @min(1, if (median or one_sided) tail else 2 * tail), .median_unbiased = median };
}
