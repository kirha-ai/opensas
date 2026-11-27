//! Incomplete principal components on centered, unit-crossproduct predictors.
//! SAS/STAT 15.4 physical pp.8562 and 8648–8649: omit the m smallest
//! eigenvalues of Z'Z. The reference eigenproblem is symmetric; Jacobi rotations
//! preserve its orthonormal basis. Accumulate in f128 before storing binary64.
const std = @import("std");
const diag = @import("../diag.zig");
const ridge = @import("reg_ridge.zig");
const A = std.mem.Allocator;
pub const Point = struct {
    omitted: usize,
    coefficients: []const f64,
    vif: []const f64,
    sse: f64,
    rmse: f64,
};

pub fn compute(a: A, x: []const f64, y: []const f64, p: usize, weights: ?[]const f64, omissions: []const f64, full_error_df: usize) diag.Error![]const Point {
    const centered = try ridge.compute(a, x, y, p, weights, &.{}, full_error_df);
    const pp = std.math.mul(usize, p, p) catch return error.ExecError;
    const matrix = try a.alloc(f128, pp);
    const vectors = try a.alloc(f128, pp);
    const rhs = try a.alloc(f128, p);
    @memset(matrix, 0);
    @memset(vectors, 0);
    @memset(rhs, 0);
    for (0..p) |j| vectors[j * p + j] = 1;
    for (y, 0..) |value, i| {
        const w: f128 = if (weights) |ws| ws[i] else 1;
        for (0..p) |j| {
            const zj = (@as(f128, x[i * p + j]) - centered.means[j]) / centered.scales[j];
            rhs[j] += w * zj * (@as(f128, value) - centered.y_mean);
            for (0..p) |k| matrix[j * p + k] += w * zj * ((@as(f128, x[i * p + k]) - centered.means[k]) / centered.scales[k]);
        }
    }
    // Maximal-pivot Jacobi: stop on an absolute off-diagonal norm for this
    // unit-diagonal correlation matrix, not a tolerance fitted to source data.
    var converged = false;
    for (0..100 * pp) |_| {
        var r: usize = 0;
        var c: usize = 0;
        var largest: f128 = 0;
        for (0..p) |j| for (j + 1..p) |k| {
            if (@abs(matrix[j * p + k]) > largest) {
                largest = @abs(matrix[j * p + k]);
                r = j;
                c = k;
            }
        };
        if (largest <= 0x1p-100) {
            converged = true;
            break;
        }
        const off = matrix[r * p + c];
        const tau = (matrix[c * p + c] - matrix[r * p + r]) / (2 * off);
        const t = (if (tau >= 0) @as(f128, 1) else -1) / (@abs(tau) + @sqrt(1 + tau * tau));
        const cosine = 1 / @sqrt(1 + t * t);
        const sine = t * cosine;
        matrix[r * p + r] -= t * off;
        matrix[c * p + c] += t * off;
        matrix[r * p + c] = 0;
        matrix[c * p + r] = 0;
        for (0..p) |j| {
            if (j != r and j != c) {
                const jr = matrix[j * p + r];
                const jc = matrix[j * p + c];
                matrix[j * p + r] = cosine * jr - sine * jc;
                matrix[r * p + j] = matrix[j * p + r];
                matrix[j * p + c] = sine * jr + cosine * jc;
                matrix[c * p + j] = matrix[j * p + c];
            }
            const vr = vectors[j * p + r];
            const vc = vectors[j * p + c];
            vectors[j * p + r] = cosine * vr - sine * vc;
            vectors[j * p + c] = sine * vr + cosine * vc;
        }
    }
    if (!converged) return error.ExecError;
    const order = try a.alloc(usize, p);
    for (order, 0..) |*v, i| v.* = i;
    // Stable ascending order; a cut through a repeated eigenspace is rejected
    // below because the retained subspace then has no unique definition.
    for (0..p) |i| for (i + 1..p) |j| {
        if (matrix[order[j] * p + order[j]] < matrix[order[i] * p + order[i]]) std.mem.swap(usize, &order[i], &order[j]);
    };
    const result = try a.alloc(Point, omissions.len);
    for (omissions, result) |m, *point| {
        if (!std.math.isFinite(m) or m < 0 or m > @as(f64, @floatFromInt(p)) or m != @trunc(m)) return error.ExecError;
        const omitted: usize = @intFromFloat(m);
        if (omitted > 0 and omitted < p) {
            const low = matrix[order[omitted - 1] * p + order[omitted - 1]];
            const high = matrix[order[omitted] * p + order[omitted]];
            if (high - low <= 0x1p-44 * @as(f128, @floatFromInt(p))) return error.ExecError;
        }
        const beta = try a.alloc(f64, p + 1);
        const vif = try a.alloc(f64, p);
        const gamma = try a.alloc(f128, p);
        @memset(gamma, 0);
        @memset(vif, 0);
        for (order[omitted..]) |index| {
            const eigenvalue = matrix[index * p + index];
            if (!(eigenvalue > 0x1p-44)) return error.ExecError;
            var projection: f128 = 0;
            for (0..p) |j| projection += vectors[j * p + index] * rhs[j];
            for (0..p) |j| {
                const v = vectors[j * p + index];
                gamma[j] += v * projection / eigenvalue;
                vif[j] += @floatCast(v * v / eigenvalue);
            }
        }
        var intercept: f128 = centered.y_mean;
        for (0..p) |j| {
            beta[j + 1] = @floatCast(gamma[j] / centered.scales[j]);
            intercept -= @as(f128, beta[j + 1]) * centered.means[j];
        }
        beta[0] = @floatCast(intercept);
        var sse: f128 = 0;
        for (y, 0..) |value, i| {
            var residual: f128 = @as(f128, value) - centered.y_mean;
            for (0..p) |j| residual -= (@as(f128, x[i * p + j]) - centered.means[j]) * beta[j + 1];
            sse += (if (weights) |ws| @as(f128, ws[i]) else 1) * residual * residual;
        }
        const df = full_error_df + omitted;
        point.* = .{ .omitted = omitted, .coefficients = beta, .vif = vif, .sse = @floatCast(sse), .rmse = if (df > 0) @floatCast(@sqrt(sse / @as(f128, @floatFromInt(df)))) else std.math.nan(f64) };
    }
    return result;
}

test "REG IPC independent two-axis eigensystem and intercept-only endpoint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // X'X=[[10,8],[8,10]], correlation eigenvalues 1.8 and .2,
    // eigenvectors (1,1)/sqrt(2), (1,-1)/sqrt(2). y=10+3x-z+e,
    // e=(1,-1,-1,1), orthogonal to intercept and both predictors.
    const points = try compute(arena.allocator(), &.{ -2, -1, -1, -2, 1, 2, 2, 1 }, &.{ 6, 8, 10, 16 }, 2, null, &.{ 0, 1, 2 }, 1);
    const coefficients = [_][3]f64{ .{ 10, 3, -1 }, .{ 10, 1, 1 }, .{ 10, 0, 0 } };
    const errors = [_]f64{ 4, 20, 56 };
    const vifs = [_]f64{ 25.0 / 9.0, 5.0 / 18.0, 0 };
    for (points, coefficients, errors, vifs, 0..) |point, beta, sse, vif, i| {
        for (point.coefficients, beta) |got, want| try std.testing.expectApproxEqAbs(want, got, 1e-13);
        for (point.vif) |got| try std.testing.expectApproxEqAbs(vif, got, 1e-13);
        try std.testing.expectApproxEqAbs(sse, point.sse, 1e-12);
        try std.testing.expectApproxEqAbs(@sqrt(sse / @as(f64, @floatFromInt(1 + i))), point.rmse, 1e-13);
    }
}

test "REG IPC refuses a nonunique cut and invalid omission count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ -1, -1, -1, 1, 1, -1, 1, 1 };
    const y = [_]f64{ 12, 4, 14, 10 };
    try std.testing.expectError(error.ExecError, compute(a, &x, &y, 2, null, &.{1}, 1));
    try std.testing.expectError(error.ExecError, compute(a, &x, &y, 2, null, &.{0.5}, 1));
    try std.testing.expectError(error.ExecError, compute(a, &x, &y, 2, null, &.{3}, 1));
}

test "REG IPC coefficient units translations and weight scaling preserve retained subspace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ -2, -1, -1, -2, 1, 2, 2, 1 };
    const y = [_]f64{ 6, 8, 10, 16 };
    var changed: [8]f64 = undefined;
    var response: [4]f64 = undefined;
    for (y, 0..) |v, i| {
        changed[2 * i] = 50 + 4 * x[2 * i];
        changed[2 * i + 1] = -30 + x[2 * i + 1] / 2;
        response[i] = 7 + 3 * v;
    }
    const original = try compute(a, &x, &y, 2, null, &.{ 0, 1, 2 }, 1);
    const transformed_path = try compute(a, &changed, &response, 2, &.{ 2, 2, 2, 2 }, &.{ 0, 1, 2 }, 1);
    for (original, transformed_path) |r, t| {
        try std.testing.expectApproxEqAbs(3 * r.coefficients[1] / 4, t.coefficients[1], 1e-13);
        try std.testing.expectApproxEqAbs(6 * r.coefficients[2], t.coefficients[2], 1e-13);
        for (r.vif, t.vif) |rv, tv| try std.testing.expectApproxEqAbs(rv, tv, 1e-13);
        try std.testing.expectApproxEqRel(18 * r.sse, t.sse, 1e-13);
        try std.testing.expectApproxEqRel(@sqrt(18.0) * r.rmse, t.rmse, 1e-13);
        for (0..4) |i| {
            const rp = r.coefficients[0] + x[2 * i] * r.coefficients[1] + x[2 * i + 1] * r.coefficients[2];
            const tp = t.coefficients[0] + changed[2 * i] * t.coefficients[1] + changed[2 * i + 1] * t.coefficients[2];
            try std.testing.expectApproxEqAbs(7 + 3 * rp, tp, 1e-12);
        }
    }
}
