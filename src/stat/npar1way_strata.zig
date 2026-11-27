//! Stratified linear-rank tests, SAS/STAT15.4 physical pp.7241-7242.
//! The PDF prints S_k/w_k although its prose defines w_k=1/(n_k+1).
//! SAS9.4 Usage Note25022 https://support.sas.com/kb/25/022.html independently
//! resolves that typo: multiply by w_k, as the van Elteren/CMH MODRIDIT test.
//! The published14-observation example is an executable exact-rational check.
const std = @import("std");
const ranks = @import("ranks.zig");
const math = @import("../functions.zig");
const A = std.mem.Allocator;
pub const Kind = enum { wilcoxon, median, vw, savage, data };
pub const Options = struct { kind: Kind = .wilcoxon, overall: bool = false, equal: bool = false };
pub const Stratum = struct { n: usize, selected_n: usize, sum: f64, expected: f64, variance: f64, weight: f64 };
pub const Result = struct { strata: []Stratum, selected: usize, sum: f64, expected: f64, variance: f64, z: ?f64, p_one: ?f64, p_two: ?f64 };
fn number(n: usize) f64 {
    return @floatFromInt(n);
}
fn scores(a: A, values: []const f64, kind: Kind) ![]f64 {
    if (kind == .data) return a.dupe(f64, values);
    const ranked = try ranks.rank(a, values, false, .mean);
    const result = try a.alloc(f64, values.len);
    const n = values.len;
    for (ranked.groups) |group| {
        var score: f64 = 0;
        for (group.first..group.first + group.count) |r| {
            score += switch (kind) {
                .wilcoxon => number(r),
                .median => if (number(r) > number(n + 1) / 2) @as(f64, 1) else 0,
                .vw => math.distQuantile(.normal, number(r) / number(n + 1), &.{}).?,
                .savage => blk: {
                    var h: f64 = -1;
                    for (1..r + 1) |i| h += 1 / number(n - i + 1);
                    break :blk h;
                },
                .data => unreachable,
            };
        }
        score /= number(group.count);
        for (values, 0..) |v, i| if (v == group.value) {
            result[i] = score;
        };
    }
    return result;
}
pub fn compute(a: A, values: []const f64, groups: []const usize, strata: []const usize, count: usize, options: Options) !Result {
    if (values.len != groups.len or groups.len != strata.len or count == 0) return error.InvalidInput;
    var counts = [_]usize{ 0, 0 };
    for (values, groups, strata) |v, g, k| {
        if (!std.math.isFinite(v) or g > 1 or k >= count) return error.InvalidInput;
        counts[g] += 1;
    }
    if (counts[0] == 0 or counts[1] == 0) return error.InvalidInput;
    const selected: usize = if (counts[0] <= counts[1]) 0 else 1;
    const all_scores = if (options.overall) try scores(a, values, options.kind) else null;
    const results = try a.alloc(Stratum, count);
    var sum: f64 = 0;
    var expected: f64 = 0;
    var variance: f64 = 0;
    for (results, 0..) |*result, k| {
        var local: std.ArrayList(f64) = .empty;
        var picked: std.ArrayList(bool) = .empty;
        for (values, groups, strata, 0..) |v, g, s, i| if (s == k) {
            try local.append(a, if (all_scores) |ss| ss[i] else v);
            try picked.append(a, g == selected);
        };
        const n = local.items.len;
        if (n == 0) return error.InvalidInput;
        const ranked = if (options.overall) local.items else try scores(a, local.items, options.kind);
        var total: f64 = 0;
        var subtotal: f64 = 0;
        var selected_n: usize = 0;
        for (ranked, picked.items) |score, pick| {
            total += score;
            if (pick) {
                subtotal += score;
                selected_n += 1;
            }
        }
        if (!std.math.isFinite(total) or !std.math.isFinite(subtotal)) return error.InvalidInput;
        const mean = total / number(n);
        var ss: f64 = 0;
        for (ranked) |score| ss += (score - mean) * (score - mean);
        if (!std.math.isFinite(ss)) return error.InvalidInput;
        const local_variance = if (n > 1) number(selected_n) * number(n - selected_n) / (number(n) * number(n - 1)) * ss else 0;
        const weight = if (options.equal) @as(f64, 1) else 1 / number(n + 1);
        result.* = .{ .n = n, .selected_n = selected_n, .sum = subtotal, .expected = number(selected_n) * mean, .variance = local_variance, .weight = weight };
        sum += weight * subtotal;
        expected += weight * result.expected;
        variance += weight * weight * local_variance;
    }
    if (!std.math.isFinite(sum) or !std.math.isFinite(expected) or !std.math.isFinite(variance)) return error.InvalidInput;
    const z = if (variance > 0) (sum - expected) / @sqrt(variance) else null;
    const p = if (z) |zz| math.distCdf(.normal, -@abs(zz), &.{}).? else null;
    return .{ .strata = results, .selected = selected, .sum = sum, .expected = expected, .variance = variance, .z = z, .p_one = p, .p_two = if (p) |pp| @min(1, 2 * pp) else null };
}

test "NPAR004 SAS UsageNote25022 resolves default stratum weights by independent exact arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Published Lehmann14-observation example in SAS9.4 UsageNote25022.
    const values = [_]f64{ 236, 255, 183, 179, 193, 115, 128, 132, 61, 70, 79, 67, 84, 88 };
    const groups = [_]usize{ 0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1 };
    const strata = [_]usize{ 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 3 };
    const r = try compute(a, &values, &groups, &strata, 4, .{});
    // Sum of per-stratum centered sums/n+1 = -65/84; sumV/(n+1)^2=55/252.
    try std.testing.expectApproxEqAbs(-@as(f64, 65.0 / 84.0), r.sum - r.expected, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 55.0 / 252.0), r.variance, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 2.7435064935064935), r.z.? * r.z.?, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.097650277881934), r.p_two.?, 1e-12);
    const equal = try compute(a, &values, &groups, &strata, 4, .{ .equal = true });
    try std.testing.expectApproxEqAbs(@as(f64, -0.5 + 0 - 1 - 2.5), equal.sum - equal.expected, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 6.833333333333333), equal.variance, 1e-14);
}
test "NPAR004 stratified tie scoring overall ranks class orientation and degenerate strata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [_]f64{ 1, 1, 2, 3, 10, 10, 12, 15 };
    const groups = [_]usize{ 0, 0, 1, 1, 0, 0, 1, 1 };
    const strata = [_]usize{ 0, 0, 0, 0, 1, 1, 1, 1 };
    for ([_]Kind{ .wilcoxon, .median, .vw, .savage, .data }) |kind| {
        const r = try compute(a, &values, &groups, &strata, 2, .{ .kind = kind, .equal = true });
        const swapped = try compute(a, &values, &.{ 1, 1, 0, 0, 1, 1, 0, 0 }, &strata, 2, .{ .kind = kind, .equal = true });
        try std.testing.expectApproxEqAbs(r.variance, swapped.variance, 1e-12);
        try std.testing.expectApproxEqAbs(r.z.?, -swapped.z.?, 1e-12);
    }
    const overall = try compute(a, &values, &groups, &strata, 2, .{ .overall = true, .equal = true });
    try std.testing.expectEqual(@as(f64, 3), overall.strata[0].sum);
    try std.testing.expectEqual(@as(f64, 11), overall.strata[1].sum);
    const constant = try compute(a, &.{ 1, 1, 2, 2 }, &.{ 0, 0, 1, 1 }, &.{ 0, 0, 1, 1 }, 2, .{});
    try std.testing.expectEqual(@as(f64, 0), constant.variance);
    try std.testing.expect(constant.z == null and constant.p_two == null);
}
