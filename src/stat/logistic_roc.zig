//! Empirical ROC areas and correlated DeLong covariance.
//! S154 physical pp.5934–5937: phi=1/0.5/0, frequency-weighted
//! placements, and Wald contrasts of areas. Analysis weights affect fits;
//! default ROC calculations use FREQ rather than analysis weights.
const std = @import("std");
const diag = @import("../diag.zig");
const reg = @import("reg_fit.zig");
const kernel = @import("logistic_fit.zig");
const A = std.mem.Allocator;
pub const Model = struct { label: []const u8, terms: []const []const usize = &.{}, pred: ?usize = null };
pub const Kind = enum { reference, adjacent, matrix };
pub const Contrast = struct { label: ?[]const u8 = null, kind: Kind = .reference, reference: ?[]const u8 = null, coefficients: []const f64 = &.{}, columns: usize = 0, display: bool = false, estimates: bool = false, all_pairs: bool = false, covariance: bool = false };
pub const Point = struct { threshold: f64, sensitivity: f64, false_positive: f64, positives: f64, negatives: f64, label: bool = false };
pub const Curve = struct { area: f64, concordant: f64, discordant: f64, tied: f64, points: []const Point };
pub const Result = struct { curves: []const Curve, covariance: []const f64, events: f64, nonevents: f64 };
pub const Test = struct { estimates: []const f64, covariance: []const f64, chi_square: f64, rank: usize };
fn phi(a: f64, b: f64) f64 {
    return if (a > b) 1 else if (a == b) 0.5 else 0;
}

pub fn compute(a: A, y: []const f64, scores: []const []const f64, frequency: []const f64, epsilon: f64) diag.Error!Result {
    if (y.len == 0 or frequency.len != y.len or scores.len == 0 or epsilon < 0 or !std.math.isFinite(epsilon)) return error.ExecError;
    var m: f64 = 0;
    var n: f64 = 0;
    for (y, frequency) |response, f| {
        if ((response != 0 and response != 1) or !(f > 0) or !std.math.isFinite(f)) return error.ExecError;
        if (response == 1) m += f else n += f;
    }
    // Area alone is defined with one event/nonevent, but a DeLong variance
    // requires at least two independent replicated observations in each arm.
    if (!(m > 1 and n > 1)) return error.ExecError;
    const curves = try a.alloc(Curve, scores.len);
    const placements = try a.alloc(f64, scores.len * y.len);
    defer a.free(placements);
    const order = try a.alloc(usize, y.len);
    defer a.free(order);
    const canonical = try a.alloc(f64, y.len);
    defer a.free(canonical);
    for (scores, 0..) |values, model| {
        if (values.len != y.len) return error.ExecError;
        for (values, 0..) |value, i| {
            if (!std.math.isFinite(value)) return error.ExecError;
            order[i] = i;
        }
        const Sort = struct {
            fn less(v: []const f64, i: usize, j: usize) bool {
                return v[i] > v[j];
            }
        };
        std.mem.sort(usize, order, values, Sort.less);
        var group_start: usize = 0;
        while (group_start < order.len) {
            var end = group_start + 1;
            while (end < order.len and values[order[group_start]] - values[order[end]] <= epsilon) : (end += 1) {}
            // Overlapping epsilon chains have no verified SAS grouping rule.
            // Reject that ambiguity rather than silently choose a tie layout.
            if (end < order.len and values[order[end - 1]] - values[order[end]] <= epsilon) return error.ExecError;
            for (order[group_start..end]) |index| canonical[index] = values[order[group_start]];
            group_start = end;
        }
        var nc: f64 = 0;
        var nt: f64 = 0;
        for (y, 0..) |response, i| {
            var placement: f64 = 0;
            for (y, 0..) |other, j| {
                if (response == other) continue;
                const comparison = if (response == 1) phi(canonical[i], canonical[j]) else phi(canonical[j], canonical[i]);
                placement += frequency[j] * comparison;
                if (response == 1) {
                    if (comparison == 1) nc += frequency[i] * frequency[j] else if (comparison == 0.5) nt += frequency[i] * frequency[j];
                }
            }
            placements[model * y.len + i] = placement / (if (response == 1) n else m);
        }
        const area = (nc + nt / 2) / (m * n);
        var points: std.ArrayList(Point) = .empty;
        try points.append(a, .{ .threshold = std.math.inf(f64), .sensitivity = 0, .false_positive = 0, .positives = 0, .negatives = n });
        var positives: f64 = 0;
        var false_positives: f64 = 0;
        var start: usize = 0;
        while (start < order.len) {
            const threshold = canonical[order[start]];
            var end = start;
            while (end < order.len and canonical[order[end]] == threshold) : (end += 1) {
                const index = order[end];
                if (y[index] == 1) positives += frequency[index] else false_positives += frequency[index];
            }
            try points.append(a, .{ .threshold = threshold, .sensitivity = positives / m, .false_positive = false_positives / n, .positives = positives, .negatives = n - false_positives });
            start = end;
        }
        // ID labels retain upper-left nondominated corners: points directly
        // below or right of another retained corner are suppressed (p.5844).
        for (points.items, 0..) |*point, i| {
            if (!std.math.isFinite(point.threshold)) continue;
            var dominated = false;
            for (points.items, 0..) |other, j| if (i != j and other.false_positive <= point.false_positive and other.sensitivity >= point.sensitivity and (other.false_positive < point.false_positive or other.sensitivity > point.sensitivity)) {
                dominated = true;
                break;
            };
            point.label = !dominated;
        }
        curves[model] = .{ .area = area, .concordant = nc, .discordant = m * n - nc - nt, .tied = nt, .points = points.items };
    }
    const covariance = try a.alloc(f64, scores.len * scores.len);
    for (0..scores.len) |r| for (0..scores.len) |s| {
        var events: f64 = 0;
        var nonevents: f64 = 0;
        for (y, 0..) |response, i| {
            const value = frequency[i] * (placements[r * y.len + i] - curves[r].area) * (placements[s * y.len + i] - curves[s].area);
            if (response == 1) events += value else nonevents += value;
        }
        covariance[r * scores.len + s] = events / (m * (m - 1)) + nonevents / (n * (n - 1));
    };
    return .{ .curves = curves, .covariance = covariance, .events = m, .nonevents = n };
}

pub fn contrastTest(a: A, result: Result, coefficients: []const f64, rows: usize) diag.Error!Test {
    const k = result.curves.len;
    if (rows == 0 or coefficients.len != rows * k or result.covariance.len != k * k) return error.ExecError;
    const estimates = try a.alloc(f64, rows);
    @memset(estimates, 0);
    const covariance = try a.alloc(f64, rows * rows);
    @memset(covariance, 0);
    for (0..rows) |r| {
        for (0..k) |j| estimates[r] += coefficients[r * k + j] * result.curves[j].area;
        for (0..rows) |s| for (0..k) |i| for (0..k) |j| {
            covariance[r * rows + s] += coefficients[r * k + i] * result.covariance[i * k + j] * coefficients[s * k + j];
        };
    }
    var solution = try reg.fit(a, covariance, estimates, rows, rows, null);
    defer solution.deinit(a);
    var q: f64 = 0;
    for (0..rows) |i| {
        var fitted: f64 = 0;
        var scale: f64 = @abs(estimates[i]);
        for (0..rows) |j| {
            const term = covariance[i * rows + j] * solution.coefficients[j];
            fitted += term;
            scale += @abs(term);
        }
        if (@abs(fitted - estimates[i]) > 512 * std.math.floatEps(f64) * @as(f64, @floatFromInt(rows)) * @max(1, scale)) return error.ExecError;
        q += estimates[i] * solution.coefficients[i];
    }
    if (!std.math.isFinite(q) or q < -1e-12) return error.ExecError;
    return .{ .estimates = estimates, .covariance = covariance, .chi_square = @max(0, q), .rank = solution.rank };
}

pub fn referenceContrast(a: A, k: usize, reference: usize) diag.Error![]const f64 {
    if (k < 2 or reference >= k) return error.ExecError;
    const result = try a.alloc(f64, (k - 1) * k);
    @memset(result, 0);
    var row: usize = 0;
    for (0..k) |j| if (j != reference) {
        result[row * k + j] = 1;
        result[row * k + reference] = -1;
        row += 1;
    };
    return result;
}

test "LOGISTIC012 Mann Whitney ties DeLong covariance and contrast have rational references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // First scores yield 3 concordant,1 tied event/nonevent pair, hence7/8.
    // Placements (1,3/4) and (3/4,1) give variance1/32. The second
    // curve reverses all comparisons: area1/8 and covariance-1/32.
    const result = try compute(a, &.{ 1, 1, 0, 0 }, &.{ &.{ 0.9, 0.8, 0.8, 0.1 }, &.{ 0.1, 0.8, 0.8, 0.9 } }, &.{ 1, 1, 1, 1 }, 0);
    try std.testing.expectEqual(@as(f64, 0.875), result.curves[0].area);
    try std.testing.expectEqual(@as(f64, 0.125), result.curves[1].area);
    try std.testing.expectEqualSlices(f64, &.{ 0.03125, -0.03125, -0.03125, 0.03125 }, result.covariance);
    const test_result = try contrastTest(a, result, &.{ 1, -1 }, 1);
    try std.testing.expectEqual(@as(usize, 1), test_result.rank);
    try std.testing.expectApproxEqAbs(@as(f64, 4.5), test_result.chi_square, 1e-12);
    const points = result.curves[0].points;
    try std.testing.expectEqual(@as(usize, 4), points.len);
    for (points, [_]f64{ 0, 0, 0.5, 1 }, [_]f64{ 0, 0.5, 1, 1 }) |point, fpr, tpr| {
        try std.testing.expectEqual(fpr, point.false_positive);
        try std.testing.expectEqual(tpr, point.sensitivity);
    }
    var area: f64 = 0;
    for (points[1..], points[0 .. points.len - 1]) |right, left| area += (right.false_positive - left.false_positive) * (right.sensitivity + left.sensitivity) / 2;
    try std.testing.expectEqual(result.curves[0].area, area);
}

test "LOGISTIC012 frequency replication degenerate scores and epsilon boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const y = [_]f64{ 1, 1, 0, 0 };
    const score = [_]f64{ 0.9, 0.8, 0.8, 0.1 };
    const frequencies = [_]f64{ 2, 3, 4, 5 };
    const weighted = try compute(a, &y, &.{&score}, &frequencies, 0);
    var ys: std.ArrayList(f64) = .empty;
    var ss: std.ArrayList(f64) = .empty;
    var fs: std.ArrayList(f64) = .empty;
    for (y, score, frequencies) |response, value, frequency| for (0..@as(usize, @intFromFloat(frequency))) |_| {
        try ys.append(a, response);
        try ss.append(a, value);
        try fs.append(a, 1);
    };
    const expanded = try compute(a, ys.items, &.{ss.items}, fs.items, 0);
    try std.testing.expectApproxEqAbs(weighted.curves[0].area, expanded.curves[0].area, 1e-14);
    try std.testing.expectApproxEqAbs(weighted.covariance[0], expanded.covariance[0], 1e-14);
    const constant = try compute(a, &y, &.{ &.{ 0.5, 0.5, 0.5, 0.5 }, &.{ 0.5, 0.5, 0.5, 0.5 } }, &.{ 1, 1, 1, 1 }, 0);
    try std.testing.expectEqual(@as(f64, 0.5), constant.curves[0].area);
    try std.testing.expectEqual(@as(f64, 0), constant.covariance[0]);
    const zero = try contrastTest(a, constant, &.{ 1, -1 }, 1);
    try std.testing.expectEqual(@as(usize, 0), zero.rank);
    try std.testing.expectEqual(@as(f64, 0), zero.chi_square);
    try std.testing.expectError(error.ExecError, compute(a, &.{ 1, 0 }, &.{&.{ 0.9, 0.1 }}, &.{ 1, 1 }, 0));
    try std.testing.expectError(error.ExecError, compute(a, &y, &.{&.{ 0.9, std.math.nan(f64), 0.8, 0.1 }}, &.{ 1, 1, 1, 1 }, 0));
    const merged = try compute(a, &y, &.{&.{ 0.9, 0.8 + 1e-10, 0.8, 0.1 }}, &.{ 1, 1, 1, 1 }, 1e-8);
    try std.testing.expectEqual(@as(f64, 0.875), merged.curves[0].area);
    try std.testing.expectError(error.ExecError, compute(a, &y, &.{&.{ 0.5, 0.5 + 0.75e-8, 0.5 + 1.5e-8, 0.1 }}, &.{ 1, 1, 1, 1 }, 1e-8));
}
