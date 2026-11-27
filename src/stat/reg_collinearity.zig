//! Belsley-Kuh-Welsch scaled-crossproduct diagnostics, S154 pp.8624–8626.
//! COLLIN retains the intercept; COLLINOINT projects it out before scaling.
const std = @import("std");
const diag = @import("../diag.zig");
const A = std.mem.Allocator;
pub const Result = struct { columns: usize, centered: bool, crossproduct: []const f64, eigenvalues: []const f64, condition_indices: []const f64, variance_proportions: []const f64 };
pub fn compute(a: A, x: []const f64, n: usize, p: usize, weights: ?[]const f64, intercept: bool, adjust_intercept: bool) diag.Error!Result {
    if (n == 0 or p == 0 or p > 16 or x.len != n * p or (adjust_intercept and !intercept)) return error.ExecError;
    if (weights) |w| if (w.len != n) return error.ExecError;
    const offset: usize = if (adjust_intercept) 1 else 0;
    const q = p - offset;
    if (q == 0) return error.ExecError;
    const means = try a.alloc(f128, q);
    const scale = try a.alloc(f128, q);
    @memset(means, 0);
    @memset(scale, 0);
    var sw: f128 = 0;
    for (0..n) |i| {
        const w = if (weights) |v| v[i] else 1;
        if (!std.math.isFinite(w) or w < 0) return error.ExecError;
        sw += w;
        for (0..q) |j| {
            const value = x[i * p + j + offset];
            if (!std.math.isFinite(value)) return error.ExecError;
            if (adjust_intercept) means[j] += @as(f128, w) * value;
        }
    }
    if (!(sw > 0)) return error.ExecError;
    for (means) |*v| v.* /= sw;
    for (0..n) |i| for (0..q) |j| {
        const delta = @as(f128, x[i * p + j + offset]) - means[j];
        scale[j] += @as(f128, if (weights) |w| w[i] else 1) * delta * delta;
    };
    for (scale) |*v| {
        if (!(v.* > 0)) return error.ExecError;
        v.* = @sqrt(v.*);
    }
    const matrix = try a.alloc(f64, q * q);
    const identity = try a.alloc(f64, q * q);
    @memset(identity, 0);
    for (0..q) |j| {
        identity[j * q + j] = 1;
        for (0..q) |k| {
            var value: f128 = 0;
            for (0..n) |i| value += @as(f128, if (weights) |w| w[i] else 1) * ((@as(f128, x[i * p + j + offset]) - means[j]) / scale[j]) * ((@as(f128, x[i * p + k + offset]) - means[k]) / scale[k]);
            matrix[j * q + k] = @floatCast(value);
        }
    }
    // E=I makes the existing generalized eigensolver an ordinary symmetric
    // eigenproblem. No statistical-kernel assumptions or rotations are changed.
    const eig = try @import("reg_mtest.zig").characteristic(a, identity, matrix, q);
    const indices = try a.alloc(f64, q);
    const proportions = try a.alloc(f64, q * q);
    for (eig.roots, indices) |value, *ci| {
        if (!(value > 0)) return error.ExecError;
        ci.* = @sqrt(eig.roots[0] / value);
    }
    for (0..q) |j| {
        var total: f128 = 0;
        for (0..q) |k| {
            const v = eig.vectors[j * q + k];
            total += @as(f128, v) * v / eig.roots[k];
        }
        if (!(total > 0)) return error.ExecError;
        for (0..q) |k| {
            const v = eig.vectors[j * q + k];
            proportions[k * q + j] = @floatCast((@as(f128, v) * v / eig.roots[k]) / total);
        }
    }
    return .{ .columns = q, .centered = adjust_intercept, .crossproduct = matrix, .eigenvalues = eig.roots, .condition_indices = indices, .variance_proportions = proportions };
}
