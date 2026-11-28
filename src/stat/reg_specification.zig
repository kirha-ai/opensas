//! REG013 specification diagnostics. S154 physical pp.8642–8644,8647–8648.
//! These kernels accept an ordinary unweighted fit after listwise deletion.
//! The producer rejects WEIGHT/FREQ/REWEIGHT and restricted fits explicitly:
//! precision weights, replication counts and ordered residuals are not interchangeable.
const std = @import("std");
const diag = @import("../diag.zig");
const qr = @import("reg_fit.zig");
const A = std.mem.Allocator;
const nan = std.math.nan(f64);

pub const Serial = struct { d: f64, correlation: f64, n: usize };
/// Missing rows have already been removed; adjacency is in retained input order.
/// Scaling by max|e| prevents squaring overflow without changing either ratio.
pub fn serial(residuals: []const f64) diag.Error!Serial {
    if (residuals.len == 0) return error.ExecError;
    var scale: f64 = 0;
    for (residuals) |e| {
        if (!std.math.isFinite(e)) return error.ExecError;
        scale = @max(scale, @abs(e));
    }
    if (scale == 0) return .{ .d = nan, .correlation = nan, .n = residuals.len };
    var ss: f64 = 0;
    var difference: f64 = 0;
    var cross: f64 = 0;
    var previous: f64 = 0;
    for (residuals, 0..) |raw, i| {
        const e = raw / scale;
        ss += e * e;
        if (i > 0) {
            difference += (e - previous) * (e - previous);
            cross += e * previous;
        }
        previous = e;
    }
    return .{ .d = difference / ss, .correlation = cross / ss, .n = residuals.len };
}

pub const LackFit = struct {
    groups: usize,
    pure_df: usize,
    lack_df: usize,
    pure_ss: f64,
    lack_ss: f64,
    pure_ms: f64,
    lack_ms: f64,
    f: f64,
    probability: f64,
};
/// Exact regressor equality defines replication; no arbitrary grouping tolerance.
/// Within-group centered sums avoid cancellation from subtracting two large SS.
pub fn lackFit(a: A, x: []const f64, y: []const f64, fit: qr.Fit) diag.Error!LackFit {
    const n = y.len;
    const p = fit.coefficients.len;
    if (n == 0 or p == 0 or x.len != n * p or fit.n_used != n or fit.rank > n or fit.df_error != n - fit.rank or fit.fitted.len != n) return error.ExecError;
    for (x) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (y) |v| if (!std.math.isFinite(v)) return error.ExecError;
    const assigned = try a.alloc(bool, n);
    defer a.free(assigned);
    @memset(assigned, false);
    var groups: usize = 0;
    var pure: f64 = 0;
    var lack: f64 = 0;
    for (0..n) |i| {
        if (assigned[i]) continue;
        groups += 1;
        var count: usize = 0;
        var mean: f64 = 0;
        var ss: f64 = 0;
        // Work relative to the first response to preserve translated data.
        for (i..n) |j| {
            if (!std.mem.eql(f64, x[i * p ..][0..p], x[j * p ..][0..p])) continue;
            assigned[j] = true;
            count += 1;
            const value = y[j] - y[i];
            const delta = value - mean;
            mean += delta / @as(f64, @floatFromInt(count));
            ss += delta * (value - mean);
        }
        pure += ss;
        const bias = (y[i] - fit.fitted[i]) + mean;
        lack += @as(f64, @floatFromInt(count)) * bias * bias;
    }
    if (groups < fit.rank or !std.math.isFinite(pure) or !std.math.isFinite(lack)) return error.ExecError;
    const pd = n - groups;
    const ld = groups - fit.rank;
    const pm = if (pd > 0) pure / @as(f64, @floatFromInt(pd)) else nan;
    const lm = if (ld > 0) lack / @as(f64, @floatFromInt(ld)) else nan;
    const f = if (pd > 0 and ld > 0 and pm > 0) lm / pm else nan;
    return .{ .groups = groups, .pure_df = pd, .lack_df = ld, .pure_ss = pure, .lack_ss = lack, .pure_ms = pm, .lack_ms = lm, .f = f, .probability = qr.fProbability(f, ld, pd) };
}

pub const Hetero = struct { covariance: []f64, errors: []f64, method: u2 };
/// HC0–3 sandwich computed as sum_i adjustment_i (G x_i)(G x_i)' e_i².
/// G is the actual unscaled covariance, in original parameter order.
/// Only full rank ordinary fits are accepted; HC2/3 require leverage <1.
pub fn hetero(a: A, x: []const f64, fit: qr.Fit, method: u2) diag.Error!Hetero {
    const n = fit.residuals.len;
    const p = fit.coefficients.len;
    if (p == 0 or n <= p or fit.rank != p or fit.n_used != n or fit.df_error != n - p or x.len != n * p or fit.covariance_unscaled.len != p * p or fit.leverage.len != n) return error.ExecError;
    for (x) |v| if (!std.math.isFinite(v)) return error.ExecError;
    const covariance = try a.alloc(f64, p * p);
    errdefer a.free(covariance);
    @memset(covariance, 0);
    const score = try a.alloc(f64, p);
    defer a.free(score);
    for (fit.residuals, fit.leverage, 0..) |e, h, i| {
        if (!std.math.isFinite(e) or !std.math.isFinite(h) or h < 0 or h > 1 or (method >= 2 and !(h < 1))) return error.ExecError;
        const correction: f64 = switch (method) {
            0 => 1,
            1 => @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(n - p)),
            2 => 1 / (1 - h),
            3 => 1 / ((1 - h) * (1 - h)),
        };
        for (score, 0..) |*v, j| {
            v.* = 0;
            for (0..p) |k| v.* += fit.covariance_unscaled[j * p + k] * x[i * p + k];
            v.* *= e * @sqrt(correction);
        }
        for (0..p) |j| for (j..p) |k| {
            covariance[j * p + k] += score[j] * score[k];
        };
    }
    const errors = try a.alloc(f64, p);
    errdefer a.free(errors);
    for (0..p) |j| {
        for (j..p) |k| {
            if (!std.math.isFinite(covariance[j * p + k])) return error.ExecError;
            covariance[k * p + j] = covariance[j * p + k];
        }
        errors[j] = @sqrt(covariance[j * p + j]);
    }
    return .{ .covariance = covariance, .errors = errors, .method = method };
}
