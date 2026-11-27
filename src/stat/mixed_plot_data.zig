//! MIXED residual diagnostics, S154 physical pp.6712-6713,6729-6734.
//! Q=X Cov(beta_hat) X'; marginal variance=diag(V-Q); conditional=diag(RPR).
//! Uses actual supplied/fitted VC matrices; it never treats a different R as VC.
const std = @import("std");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const matrix = @import("mixed_fit_matrix.zig");
const f = @import("../functions.zig");
const A = std.mem.Allocator;
pub const Kind = enum { residual, student, pearson };
pub const Mode = enum { conditional, marginal };
pub const Data = struct { n: usize, source_rows: []const usize, marginal_prediction: []f64, conditional_prediction: []f64, marginal_raw: []f64, conditional_raw: []f64, marginal_variance: []f64, conditional_variance: []f64, marginal_response_variance: []f64, conditional_response_variance: []f64 };
pub fn compute(a: A, x: fixed.Design, z: random.Design, fit: anytype) !Data {
    const n = x.matrix.n;
    const p = x.matrix.p;
    if (n == 0 or z.n != n or fit.coefficients.len != p or fit.covariance.len != p * p or fit.variances.len != z.components.len + 1) return error.InvalidInput;
    for (fit.variances) |v| if (!std.math.isFinite(v) or v < 0) return error.UnsupportedCovariance;
    const residual = fit.variances[fit.variances.len - 1];
    if (!(residual > 0)) return error.UnsupportedCovariance;
    const v = try a.alloc(f64, n * n);
    @memset(v, 0);
    const r = try a.alloc(f64, n);
    for (0..n) |i| {
        if (!(x.weights[i] > 0) or !std.math.isFinite(x.weights[i])) return error.InvalidInput;
        r[i] = residual / x.weights[i];
        v[i * n + i] = r[i];
    }
    for (z.components, fit.variances[0..z.components.len]) |component, theta| {
        if (component.kernel.len != n * n) return error.InvalidInput;
        for (v, component.kernel) |*cell, k| cell.* += theta * k;
    }
    const vi = try matrix.inverse(a, v, n);
    const b = try a.alloc(f64, n * p);
    @memset(b, 0);
    for (0..n) |i| for (0..n) |j| for (0..p) |k| {
        b[i * p + k] += vi.values[i * n + j] * x.matrix.x[j * p + k];
    };
    const result = Data{ .n = n, .source_rows = x.source_rows, .marginal_prediction = try a.alloc(f64, n), .conditional_prediction = try a.alloc(f64, n), .marginal_raw = try a.alloc(f64, n), .conditional_raw = try a.alloc(f64, n), .marginal_variance = try a.alloc(f64, n), .conditional_variance = try a.alloc(f64, n), .marginal_response_variance = try a.alloc(f64, n), .conditional_response_variance = r };
    for (0..n) |i| {
        var prediction: f64 = 0;
        var q: f64 = 0;
        var correction: f64 = 0;
        for (0..p) |j| {
            prediction += x.matrix.x[i * p + j] * fit.coefficients[j];
            for (0..p) |k| {
                q += x.matrix.x[i * p + j] * fit.covariance[j * p + k] * x.matrix.x[i * p + k];
                correction += b[i * p + j] * fit.covariance[j * p + k] * b[i * p + k];
            }
        }
        result.marginal_prediction[i] = prediction;
        result.marginal_raw[i] = x.y[i] - prediction;
        result.marginal_variance[i] = try nonnegative(v[i * n + i] - q, @max(v[i * n + i], @abs(q)));
        result.conditional_variance[i] = r[i] * r[i] * try nonnegative(vi.values[i * n + i] - correction, @max(vi.values[i * n + i], @abs(correction)));
        result.marginal_response_variance[i] = v[i * n + i];
    }
    for (0..n) |i| {
        var value: f64 = 0;
        for (0..n) |j| value += vi.values[i * n + j] * result.marginal_raw[j];
        result.conditional_raw[i] = r[i] * value;
        result.conditional_prediction[i] = x.y[i] - result.conditional_raw[i];
    }
    return result;
}
fn nonnegative(value: f64, scale: f64) !f64 {
    if (!std.math.isFinite(value) or value < -64 * std.math.floatEps(f64) * scale) return error.InvalidCovariance;
    return if (value <= 64 * std.math.floatEps(f64) * scale) 0 else value;
}
pub const Point = struct { predicted: f64, value: f64, source: usize };
pub const QQ = struct { probability: f64, quantile: f64, value: f64, source: usize };
pub const Bin = struct { lower: f64, upper: f64, count: usize, percent: f64 };
pub const Curve = struct { x: f64, y: f64 };
pub const Series = struct { points: []const Point, qq: []const QQ, bins: []const Bin, normal: []const Curve, missing: usize, mean: f64, sd: ?f64, minimum: f64, maximum: f64 };
pub fn series(a: A, d: Data, kind: Kind, mode: Mode) !Series {
    const raw = if (mode == .marginal) d.marginal_raw else d.conditional_raw;
    const predicted = if (mode == .marginal) d.marginal_prediction else d.conditional_prediction;
    const variance = if (kind == .student) (if (mode == .marginal) d.marginal_variance else d.conditional_variance) else (if (mode == .marginal) d.marginal_response_variance else d.conditional_response_variance);
    var points: std.ArrayList(Point) = .empty;
    var mean: f64 = 0;
    var m2: f64 = 0;
    var minimum = std.math.inf(f64);
    var maximum = -std.math.inf(f64);
    for (raw, predicted, variance, d.source_rows) |value, pred, var_value, id| {
        const v = if (kind == .residual) value else if (var_value > 0) value / @sqrt(var_value) else std.math.nan(f64);
        if (std.math.isNan(v)) continue;
        if (!std.math.isFinite(v) or !std.math.isFinite(pred)) return error.InvalidInput;
        try points.append(a, .{ .predicted = pred, .value = v, .source = id });
        const delta = v - mean;
        mean += delta / @as(f64, @floatFromInt(points.items.len));
        m2 += delta * (v - mean);
        minimum = @min(minimum, v);
        maximum = @max(maximum, v);
    }
    if (points.items.len == 0) return error.NoFiniteResiduals;
    const n = points.items.len;
    const sd: ?f64 = if (n > 1) @sqrt(@max(0, m2 / @as(f64, @floatFromInt(n - 1)))) else null;
    if (sd) |value| if (!std.math.isFinite(value)) return error.InvalidInput;
    const sorted = try a.dupe(Point, points.items);
    std.mem.sort(Point, sorted, {}, struct {
        fn less(_: void, l: Point, r: Point) bool {
            return l.value < r.value or (l.value == r.value and l.source < r.source);
        }
    }.less);
    const qq = try a.alloc(QQ, n);
    for (sorted, qq, 0..) |point, *q, i| {
        const probability = (@as(f64, @floatFromInt(i)) + 0.625) / (@as(f64, @floatFromInt(n)) + 0.25);
        q.* = .{ .probability = probability, .quantile = f.distQuantile(.normal, probability, &.{}).?, .value = point.value, .source = point.source };
    }
    // Deterministic native histogram: sqrt(n) target bins and outward nice width.
    // This is not a claim of pixel-identical undocumented SAS automatic binning.
    const width = if (maximum > minimum) nice((maximum - minimum) / @ceil(@sqrt(@as(f64, @floatFromInt(n))))) else @as(f64, 1);
    const lower = if (maximum > minimum) @floor(minimum / width) * width else minimum - 0.5;
    const count: @TypeOf(n) = @max(1, @as(usize, @intFromFloat(@ceil((maximum - lower) / width))));
    const bins = try a.alloc(Bin, count);
    for (bins, 0..) |*bin, i| bin.* = .{ .lower = lower + width * @as(f64, @floatFromInt(i)), .upper = lower + width * @as(f64, @floatFromInt(i + 1)), .count = 0, .percent = 0 };
    for (points.items) |point| {
        const index = @min(count - 1, @as(usize, @intFromFloat(@max(0, @floor((point.value - lower) / width)))));
        bins[index].count += 1;
    }
    for (bins) |*bin| bin.percent = 100 * @as(f64, @floatFromInt(bin.count)) / @as(f64, @floatFromInt(n));
    var curve: std.ArrayList(Curve) = .empty;
    if (sd) |s| if (s > 0) {
        const lo = @min(lower, mean - 3.5 * s);
        const hi = @max(bins[bins.len - 1].upper, mean + 3.5 * s);
        for (0..65) |i| {
            const value = lo + (hi - lo) * @as(f64, @floatFromInt(i)) / 64;
            try curve.append(a, .{ .x = value, .y = 100 * width * @exp(-0.5 * std.math.pow(f64, (value - mean) / s, 2)) / (s * @sqrt(2 * std.math.pi)) });
        }
    };
    return .{ .points = points.items, .qq = qq, .bins = bins, .normal = curve.items, .missing = d.n - n, .mean = mean, .sd = sd, .minimum = minimum, .maximum = maximum };
}
fn nice(x: f64) f64 {
    const power = std.math.pow(f64, 10, @floor(@log10(x)));
    const ratio = x / power;
    for ([_]f64{ 1, 2, 2.5, 4, 5, 8, 10 }) |v| if (ratio <= v) return v * power;
    return 10 * power;
}

test "MIXED017 conditional marginal residual covariance and Pearson denominators are independent rational identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x: fixed.Design = .{ .matrix = .{ .x = @constCast(&[_]f64{ 1, 1, 1, 1 }), .n = 4, .p = 1, .source_rows = &.{ 0, 1, 2, 3 }, .columns = &.{}, .classes = &.{} }, .y = &.{ 1, 3, 5, 7 }, .weights = &.{ 1, 1, 1, 1 }, .source_rows = &.{ 11, 12, 21, 22 } };
    const z: random.Design = .{ .n = 4, .q = 2, .z = &.{ 1, 0, 1, 0, 0, 1, 0, 1 }, .columns = &.{}, .components = &.{.{ .name = "group", .kernel = &.{ 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1 }, .columns = 2, .effect_index = 0, .request_index = 0, .group_index = 0 }}, .subject_count = 2, .max_obs_per_subject = 2, .first_effect_levels = 2 };
    const fit = .{ .coefficients = @as([]const f64, &.{4}), .covariance = @as([]const f64, &.{1.25}), .variances = @as([]const f64, &.{ 2, 1 }) };
    const d = try compute(a, x, z, fit);
    for ([_]f64{ -1.4, 0.6, -0.6, 1.4 }, d.conditional_raw, d.conditional_prediction, x.y) |wanted, raw, pred, y| {
        try std.testing.expectApproxEqAbs(wanted, raw, 2e-14);
        try std.testing.expectApproxEqAbs(y - wanted, pred, 2e-14);
    }
    for (d.marginal_variance, d.conditional_variance, d.marginal_response_variance, d.conditional_response_variance) |m, c, vm, vc| {
        try std.testing.expectApproxEqAbs(@as(f64, 1.75), m, 2e-14);
        try std.testing.expectApproxEqAbs(@as(f64, 0.55), c, 2e-14);
        try std.testing.expectEqual(@as(f64, 3), vm);
        try std.testing.expectEqual(@as(f64, 1), vc);
    }
    const marginal = try series(a, d, .pearson, .marginal);
    const conditional = try series(a, d, .student, .conditional);
    try std.testing.expectApproxEqAbs(-3 / @sqrt(@as(f64, 3)), marginal.points[0].value, 2e-14);
    try std.testing.expectApproxEqAbs(-1.4 / @sqrt(@as(f64, 0.55)), conditional.points[0].value, 2e-14);
    try std.testing.expectEqual(@as(usize, 11), conditional.points[0].source);
    var total: usize = 0;
    var percent: f64 = 0;
    for (conditional.bins) |bin| {
        total += bin.count;
        percent += bin.percent;
    }
    try std.testing.expectEqual(@as(usize, 4), total);
    try std.testing.expectApproxEqAbs(@as(f64, 100), percent, 1e-12);
    try std.testing.expectEqual(@as(usize, 65), conditional.normal.len);
    try std.testing.expectEqual(@as(usize, 4), conditional.qq.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.625 / 4.25), conditional.qq[0].probability, 1e-15);
    const zero = try compute(a, x, z, .{ .coefficients = @as([]const f64, &.{4}), .covariance = @as([]const f64, &.{0.25}), .variances = @as([]const f64, &.{ 0, 1 }) });
    for (zero.marginal_raw, zero.conditional_raw) |m, c| try std.testing.expectApproxEqAbs(m, c, 2e-14);
    try std.testing.expectError(error.UnsupportedCovariance, compute(a, x, z, .{ .coefficients = fit.coefficients, .covariance = fit.covariance, .variances = @as([]const f64, &.{ -1, 1 }) }));
}
