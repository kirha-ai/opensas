//! Ridge regression on centered, unit-crossproduct columns (S154 pp.8648–8649).
//! Solve [Z; sqrt(k) I] gamma = [sqrt(W)(y-ybar); 0] with the existing QR.
//! No inverse of the unscaled normal equations is formed.
const std = @import("std");
const diag = @import("../diag.zig");
const qr = @import("reg_fit.zig");
const A = std.mem.Allocator;
pub const Point = struct {
    k: f64,
    coefficients: []const f64, // intercept, then original predictor order
    standardized: []const f64,
    vif: []const f64,
    rmse: f64,
    sse: f64,
};
pub const Path = struct { points: []const Point, means: []const f64, scales: []const f64, y_mean: f64, y_scale: f64 };

pub fn compute(a: A, x: []const f64, y: []const f64, p: usize, weights: ?[]const f64, constants: []const f64, error_df: usize) diag.Error!Path {
    const n = y.len;
    const np = std.math.mul(usize, n, p) catch return error.ExecError;
    if (n == 0 or p == 0 or x.len != np) return error.ExecError;
    if (weights) |w| if (w.len != n) return error.ExecError;
    var sw: f128 = 0;
    var sy: f128 = 0;
    const means = try a.alloc(f64, p);
    const scales = try a.alloc(f64, p);
    for (y, 0..) |value, i| {
        const w = if (weights) |ws| ws[i] else 1;
        if (!std.math.isFinite(value) or !std.math.isFinite(w) or w < 0) return error.ExecError;
        sw += w;
        sy += @as(f128, w) * value;
    }
    if (!(sw > 0)) return error.ExecError;
    const ym: f64 = @floatCast(sy / sw);
    for (0..p) |j| {
        var sum: f128 = 0;
        for (y, 0..) |_, i| {
            const value = x[i * p + j];
            if (!std.math.isFinite(value)) return error.ExecError;
            sum += @as(f128, if (weights) |ws| ws[i] else 1) * value;
        }
        means[j] = @floatCast(sum / sw);
        var css: f128 = 0;
        for (y, 0..) |_, i| {
            const d = @as(f128, x[i * p + j]) - means[j];
            css += @as(f128, if (weights) |ws| ws[i] else 1) * d * d;
        }
        scales[j] = @floatCast(@sqrt(css));
        if (!(scales[j] > 0) or !std.math.isFinite(scales[j])) return error.ExecError;
    }
    var ycss: f128 = 0;
    for (y, 0..) |value, i| {
        const d = @as(f128, value) - ym;
        ycss += @as(f128, if (weights) |ws| ws[i] else 1) * d * d;
    }
    const ys: f64 = @floatCast(@sqrt(ycss));
    if (!(ys > 0) or !std.math.isFinite(ys)) return error.ExecError;
    const rows = std.math.add(usize, n, p) catch return error.ExecError;
    const z = try a.alloc(f64, std.math.mul(usize, rows, p) catch return error.ExecError);
    const target = try a.alloc(f64, rows);
    @memset(z, 0);
    @memset(target, 0);
    for (y, 0..) |value, i| {
        const rootw = @sqrt(if (weights) |ws| ws[i] else 1);
        target[i] = rootw * (value - ym);
        for (0..p) |j| z[i * p + j] = rootw * (x[i * p + j] - means[j]) / scales[j];
    }
    const points = try a.alloc(Point, constants.len);
    for (constants, points) |k, *point| {
        if (!std.math.isFinite(k) or k < 0) return error.ExecError;
        for (0..p) |j| z[(n + j) * p + j] = @sqrt(k);
        var fitted = try qr.fit(a, z, target, rows, p, null);
        defer fitted.deinit(a);
        if (fitted.rank != p) return error.ExecError;
        const beta = try a.alloc(f64, p + 1);
        const standardized = try a.alloc(f64, p);
        const vif = try a.alloc(f64, p);
        var intercept: f128 = ym;
        for (0..p) |j| {
            beta[j + 1] = fitted.coefficients[j] / scales[j];
            standardized[j] = fitted.coefficients[j] / ys;
            intercept -= @as(f128, beta[j + 1]) * means[j];
            // diag(B Z'Z B) = ||Z B[:,j]||^2. The sum of squares avoids
            // cancellation in the algebraically equivalent B[j,j]-k*(B^2)[j,j].
            var variance: f128 = 0;
            for (0..n) |i| {
                var v: f128 = 0;
                for (0..p) |l| v += @as(f128, z[i * p + l]) * fitted.covariance_unscaled[l * p + j];
                variance += v * v;
            }
            vif[j] = @floatCast(variance);
        }
        beta[0] = @floatCast(intercept);
        var sse: f128 = 0;
        for (y, 0..) |value, i| {
            var prediction: f128 = ym;
            for (0..p) |j| prediction += (@as(f128, x[i * p + j]) - means[j]) * beta[j + 1];
            const residual = @as(f128, value) - prediction;
            sse += @as(f128, if (weights) |ws| ws[i] else 1) * residual * residual;
        }
        const ss: f64 = @floatCast(sse);
        if (!std.math.isFinite(ss)) return error.ExecError;
        point.* = .{ .k = k, .coefficients = beta, .standardized = standardized, .vif = vif, .sse = ss, .rmse = if (error_df > 0) @sqrt(ss / @as(f64, @floatFromInt(error_df))) else std.math.nan(f64) };
    }
    return .{ .points = points, .means = means, .scales = scales, .y_mean = ym, .y_scale = ys };
}

test "REG ridge orthogonal hand solution k=0 and k=1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try compute(a, &.{ -1, -1, -1, 1, 1, -1, 1, 1 }, &.{ 12, 4, 14, 10 }, 2, null, &.{ 0, 1 }, 1);
    for (result.points, [_][]const f64{ &.{ 10, 2, -3 }, &.{ 10, 1, -1.5 } }, [_]f64{ 4, 17 }, [_]f64{ 1, 0.25 }) |point, beta, sse, vif| {
        for (point.coefficients, beta) |actual, want| try std.testing.expectApproxEqAbs(want, actual, 1e-13);
        try std.testing.expectApproxEqAbs(sse, point.sse, 1e-12);
        for (point.vif) |v| try std.testing.expectApproxEqAbs(vif, v, 1e-13);
        try std.testing.expectApproxEqAbs(@sqrt(sse), point.rmse, 1e-13);
    }
}

test "REG ridge translation predictor units and response scaling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ -1, -1, -1, 1, 1, -1, 1, 1 };
    const y = [_]f64{ 12, 4, 14, 10 };
    var transformed: [8]f64 = undefined;
    var scaled_y: [4]f64 = undefined;
    for (y, 0..) |v, i| {
        transformed[2 * i] = 100 + 4 * x[2 * i];
        transformed[2 * i + 1] = -7 + 0.25 * x[2 * i + 1];
        scaled_y[i] = 3 * v;
    }
    const raw = try compute(a, &x, &y, 2, null, &.{ 0, 0.1, 1 }, 1);
    const changed = try compute(a, &transformed, &scaled_y, 2, null, &.{ 0, 0.1, 1 }, 1);
    for (raw.points, changed.points) |r, c| {
        for (r.vif, c.vif) |v, w| try std.testing.expectApproxEqAbs(v, w, 1e-13);
        for (r.standardized, c.standardized) |v, w| try std.testing.expectApproxEqAbs(v, w, 1e-13);
        try std.testing.expectApproxEqAbs(3 * r.rmse, c.rmse, 1e-11);
        for (y, 0..) |_, i| {
            const rp = r.coefficients[0] + r.coefficients[1] * x[2 * i] + r.coefficients[2] * x[2 * i + 1];
            const cp = c.coefficients[0] + c.coefficients[1] * transformed[2 * i] + c.coefficients[2] * transformed[2 * i + 1];
            try std.testing.expectApproxEqAbs(3 * rp, cp, 1e-11);
        }
    }
}

test "REG ridge undefined scales and invalid penalties fail explicitly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.ExecError, compute(a, &.{ 1, 1 }, &.{ 1, 2 }, 1, null, &.{0.1}, 1));
    try std.testing.expectError(error.ExecError, compute(a, &.{ 1, 2 }, &.{ 1, 2 }, 1, null, &.{-1}, 1));
}
