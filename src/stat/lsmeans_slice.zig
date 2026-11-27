//! Procedure-independent SLICE hypothesis construction from actual L rows.
//! S154 physical pp.539-540: first-minus-other joint hypothesis, and all
//! pairwise differences WITHIN each partition. Never test raw cell means when
//! the consumer supplied adjusted GLS population margins.
const std = @import("std");
const linear = @import("mixed_contrasts_kernel.zig");
const adjust = @import("lsmeans_inference.zig");
const A = std.mem.Allocator;
pub const Row = struct { levels: []const ?usize, coefficients: []const f64 };
pub const Partition = struct { classes: []const usize, levels: []const usize, rows: []const usize };
pub const Difference = struct { left: usize, right: usize, coefficients: []const f64, value: linear.Estimate, adjusted_p: ?f64 = null, lower: ?f64 = null, upper: ?f64 = null };
pub const TestResult = struct { hypotheses: []const @import("linear_hypothesis.zig").Row, result: @import("linear_hypothesis.zig").Result };
pub fn testPartition(a: A, model: @import("linear_hypothesis.zig").Model, rows: []const []const f64, indices: []const usize) !TestResult {
    if (indices.len == 0) return error.InvalidInput;
    const width = model.estimates.len;
    for (indices) |i| if (i >= rows.len or rows[i].len != width) return error.InvalidInput;
    const hypotheses = try a.alloc(@import("linear_hypothesis.zig").Row, indices.len - 1);
    for (indices[1..], hypotheses) |index, *h| {
        const l = try a.alloc(f64, width);
        for (rows[indices[0]], rows[index], l) |left, right, *v| v.* = left - right;
        h.* = .{ .coefficients = l };
    }
    return .{ .hypotheses = hypotheses, .result = try @import("linear_hypothesis.zig").evaluate(a, model, hypotheses, null) };
}
pub const Result = struct { hypothesis: []const f64, test_result: linear.Contrast, differences: []const Difference };
pub fn partitions(a: A, rows: []const Row, classes: []const usize) ![]const Partition {
    if (rows.len == 0 or classes.len == 0) return error.InvalidInput;
    var out: std.ArrayList(Partition) = .empty;
    const used = try a.alloc(bool, rows.len);
    @memset(used, false);
    for (rows, 0..) |row, index| {
        if (used[index]) continue;
        const values = try a.alloc(usize, classes.len);
        for (classes, values) |c, *v| {
            if (c >= row.levels.len or row.levels[c] == null) return error.InvalidInput;
            v.* = row.levels[c].?;
        }
        var members: std.ArrayList(usize) = .empty;
        for (rows, 0..) |candidate, j| {
            var match = true;
            for (classes, values) |c, v| {
                if (c >= candidate.levels.len or candidate.levels[c] == null or candidate.levels[c].? != v) match = false;
            }
            if (match) {
                try members.append(a, j);
                used[j] = true;
            }
        }
        try out.append(a, .{ .classes = try a.dupe(usize, classes), .levels = values, .rows = members.items });
    }
    return out.items;
}
pub fn compute(a: A, j: linear.Joint, rows: []const Row, partition: Partition, df: f64, alpha: f64, singular: f64, rank_tolerance: f64, with_diff: bool, adjustment: adjust.Adjustment, with_cl: bool) !Result {
    if (j.q != 0) return error.InvalidInput;
    const width = j.p + j.q;
    if (partition.rows.len == 0) return error.InvalidInput;
    for (partition.rows) |i| if (i >= rows.len or rows[i].coefficients.len != width) return error.InvalidInput;
    const count = partition.rows.len;

    const all_rows = try a.alloc([]const f64, rows.len);
    for (rows, all_rows) |row, *target| target.* = row.coefficients;
    const tested = try testPartition(a, .{ .estimates = j.coefficients, .covariance_kernel = j.covariance, .alias_transpose = j.aliases, .scale = 1, .denominator_df = df, .estimability_tolerance = singular, .rank_tolerance = rank_tolerance }, all_rows, partition.rows);
    const l = try a.alloc(f64, (count - 1) * width);
    for (tested.hypotheses, 0..) |h, i| @memcpy(l[i * width ..][0..width], h.coefficients);
    const test_result = linear.Contrast{ .estimable = tested.result.status == .estimable or tested.result.status == .zero_rank, .num_df = tested.result.rank, .den_df = df, .f = tested.result.f, .p = tested.result.f_probability };
    var diffs: std.ArrayList(Difference) = .empty;
    if (with_diff) for (partition.rows, 0..) |left, i| for (partition.rows[i + 1 ..]) |right| {
        const delta = try a.alloc(f64, width);
        for (rows[left].coefficients, rows[right].coefficients, delta) |u, v, *d| d.* = u - v;
        const value = try linear.estimate(j, delta, df, alpha, .two, singular);
        var result = Difference{ .left = left, .right = right, .coefficients = delta, .value = value };
        if (value.p) |p| result.adjusted_p = try adjust.probability(p, count, adjustment);
        if (with_cl and value.estimable and value.se != null) {
            const critical = try adjust.critical(df, alpha, count, adjustment);
            result.lower = value.estimate.? - critical * value.se.?;
            result.upper = value.estimate.? + critical * value.se.?;
        }
        try diffs.append(a, result);
    };
    return .{ .hypothesis = l, .test_result = test_result, .differences = diffs.items };
}
