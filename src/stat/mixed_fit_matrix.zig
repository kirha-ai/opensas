//! Small dense SPD matrix operations used by MIXED covariance likelihoods.
const std = @import("std");
const A = std.mem.Allocator;
pub const Inverse = struct { values: []f64, logdet: f64 };
pub fn inverse(a: A, m: []const f64, n: usize) !Inverse {
    if (n == 0 or m.len != n * n) return error.InvalidInput;
    const l = try a.alloc(f64, n * n);
    @memset(l, 0);
    var logdet: f64 = 0;
    for (0..n) |i| for (0..i + 1) |j| {
        var value = m[i * n + j];
        if (!std.math.isFinite(value)) return error.InvalidInput;
        for (0..j) |k| value -= l[i * n + k] * l[j * n + k];
        if (i == j) {
            if (!(value > 0)) return error.NotPositiveDefinite;
            l[i * n + j] = @sqrt(value);
            logdet += @log(value);
        } else l[i * n + j] = value / l[j * n + j];
    };
    const out = try a.alloc(f64, n * n);
    const y = try a.alloc(f64, n);
    for (0..n) |column| {
        for (0..n) |i| {
            var value: f64 = if (i == column) 1 else 0;
            for (0..i) |k| value -= l[i * n + k] * y[k];
            y[i] = value / l[i * n + i];
        }
        var i = n;
        while (i > 0) {
            i -= 1;
            var value = y[i];
            for (i + 1..n) |k| value -= l[k * n + i] * out[k * n + column];
            out[i * n + column] = value / l[i * n + i];
        }
    }
    return .{ .values = out, .logdet = logdet };
}
pub fn multiply(a: A, x: []const f64, y: []const f64, n: usize) ![]f64 {
    const out = try a.alloc(f64, n * n);
    @memset(out, 0);
    for (0..n) |i| for (0..n) |k| for (0..n) |j| {
        out[i * n + j] += x[i * n + k] * y[k * n + j];
    };
    return out;
}
pub fn vector(a: A, x: []const f64, y: []const f64, n: usize) ![]f64 {
    const out = try a.alloc(f64, n);
    @memset(out, 0);
    for (0..n) |i| for (0..n) |j| {
        out[i] += x[i * n + j] * y[j];
    };
    return out;
}
pub fn dot(x: []const f64, y: []const f64) f64 {
    var sum: f64 = 0;
    for (x, y) |u, v| sum += u * v;
    return sum;
}
pub fn traceProduct(x: []const f64, y: []const f64, n: usize) f64 {
    var sum: f64 = 0;
    for (0..n) |i| for (0..n) |j| {
        sum += x[i * n + j] * y[j * n + i];
    };
    return sum;
}
