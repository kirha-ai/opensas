//! Shared linear TEST inference: actual fitted estimates, reflexive g2 covariance
//! kernel, and the caller's estimability/rank policies. S154 pp.278–284,545–546,
//! 8598–8599. No procedure's effect syntax is inferred from another procedure.
const std = @import("std");
const diag = @import("../diag.zig");
const ranks = @import("reg_diagnostics.zig");
const A = std.mem.Allocator;
pub const Row = struct { coefficients: []const f64, rhs: f64 = 0 };
pub const Model = struct {
    estimates: []const f64,
    covariance_kernel: []const f64,
    /// H^T, H=G X'WX. Row j expresses original column j in retained columns k.
    /// A row L is estimable iff L_j=sum_k L_k*alias_transpose[j*p+k].
    alias_transpose: []const f64,
    scale: ?f64,
    denominator_df: ?f64,
    estimability_tolerance: f64,
    rank_tolerance: f64,
};
pub const Status = enum { estimable, nonestimable, zero_rank, inconsistent };
pub const Result = struct {
    status: Status,
    rank: usize = 0,
    numerator_ss: ?f64 = null,
    wald: ?f64 = null,
    f: ?f64 = null,
    denominator_df: ?f64 = null,
    f_probability: ?f64 = null,
    chi_square_probability: ?f64 = null,
};
pub fn fromRegression(model: ranks.Result, tolerance: f64) Model {
    return .{ .estimates = model.fit.coefficients, .covariance_kernel = model.fit.covariance_unscaled, .alias_transpose = model.alias_coefficients, .scale = if (std.math.isFinite(model.fit.mse) and model.fit.mse >= 0) model.fit.mse else null, .denominator_df = if (model.fit.df_error > 0) @as(f64, @floatFromInt(model.fit.df_error)) else null, .estimability_tolerance = tolerance, .rank_tolerance = model.singular };
}

pub fn evaluate(a: A, model: Model, rows: []const Row, denominator_override: ?f64) diag.Error!Result {
    const p = model.estimates.len;
    const q = rows.len;
    const pp = std.math.mul(usize, p, p) catch return error.ExecError;
    const qq = std.math.mul(usize, q, q) catch return error.ExecError;
    if (p == 0 or model.covariance_kernel.len != pp or model.alias_transpose.len != pp or !(model.estimability_tolerance > 0 and model.estimability_tolerance < 1) or !(model.rank_tolerance > 0 and model.rank_tolerance < 1)) return error.ExecError;
    for (model.estimates) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (model.covariance_kernel) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (model.alias_transpose) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (0..p) |i| for (0..p) |j| {
        const left = model.covariance_kernel[i * p + j];
        const right = model.covariance_kernel[j * p + i];
        if (@abs(left - right) > model.rank_tolerance * @max(1, @max(@abs(left), @abs(right)))) return error.ExecError;
    };
    if (model.scale) |scale| if (!std.math.isFinite(scale) or scale < 0) return error.ExecError;
    const denominator_df = denominator_override orelse model.denominator_df;
    if (denominator_df) |df| if (!std.math.isFinite(df) or df <= 0) return error.ExecError;
    var estimable = true;
    for (rows) |row| {
        if (row.coefficients.len != p or !std.math.isFinite(row.rhs)) return error.ExecError;
        for (row.coefficients, 0..) |coefficient, j| {
            if (!std.math.isFinite(coefficient)) return error.ExecError;
            var projected: f128 = 0;
            for (row.coefficients, 0..) |l, k| projected += @as(f128, l) * model.alias_transpose[j * p + k];
            const magnitude = if (coefficient == 0) @as(f128, 1) else @abs(@as(f128, coefficient));
            if (@abs(projected - coefficient) > magnitude * model.estimability_tolerance) estimable = false;
        }
    }
    if (!estimable) return .{ .status = .nonestimable };
    if (q == 0) return .{ .status = .zero_rank, .numerator_ss = 0 };
    const matrix = try a.alloc(f128, qq);
    const delta = try a.alloc(f128, q);
    const norms = try a.alloc(f128, q);
    @memset(matrix, 0);
    for (rows, 0..) |row, i| {
        delta[i] = -@as(f128, row.rhs);
        for (row.coefficients, model.estimates) |coefficient, beta| delta[i] += @as(f128, coefficient) * beta;
        for (rows, 0..) |other, j| for (0..p) |l| for (0..p) |k| {
            matrix[i * q + j] += @as(f128, row.coefficients[l]) * model.covariance_kernel[l * p + k] * other.coefficients[k];
        };
        if (matrix[i * q + i] < 0) return error.ExecError;
        norms[i] = if (matrix[i * q + i] > 0) @sqrt(matrix[i * q + i]) else 1;
    }
    // Standardize each hypothesis row before rank decisions; multiplying a
    // restriction by10^-12 or10^12 must not change its rank or inference.
    var delta_scale: f128 = 1;
    for (0..q) |i| {
        delta[i] /= norms[i];
        delta_scale = @max(delta_scale, @abs(delta[i]));
        for (0..q) |j| matrix[i * q + j] /= norms[i] * norms[j];
    }
    var rank: usize = 0;
    var ss: f128 = 0;
    while (rank < q) {
        var pivot = rank;
        for (rank..q) |i| {
            if (matrix[i * q + i] < -model.rank_tolerance) return error.ExecError;
            if (matrix[i * q + i] > matrix[pivot * q + pivot]) pivot = i;
        }
        if (matrix[pivot * q + pivot] <= model.rank_tolerance) break;
        for (0..q) |j| std.mem.swap(f128, &matrix[rank * q + j], &matrix[pivot * q + j]);
        for (0..q) |i| std.mem.swap(f128, &matrix[i * q + rank], &matrix[i * q + pivot]);
        std.mem.swap(f128, &delta[rank], &delta[pivot]);
        const divisor = matrix[rank * q + rank];
        ss += delta[rank] * delta[rank] / divisor;
        for (rank + 1..q) |i| {
            delta[i] -= matrix[i * q + rank] * delta[rank] / divisor;
            for (rank + 1..q) |j| matrix[i * q + j] -= matrix[i * q + rank] * matrix[rank * q + j] / divisor;
        }
        rank += 1;
    }
    for (delta[rank..]) |remaining| if (@abs(remaining) > delta_scale * model.rank_tolerance) return .{ .status = .inconsistent, .rank = rank };
    if (rank == 0) return .{ .status = .zero_rank, .numerator_ss = 0 };
    const numerator: f64 = @floatCast(ss);
    if (!std.math.isFinite(numerator) or numerator < 0) return error.ExecError;
    var result = Result{ .status = .estimable, .rank = rank, .numerator_ss = numerator, .denominator_df = denominator_df };
    if (model.scale) |scale| if (scale > 0) {
        const wald = numerator / scale;
        if (!std.math.isFinite(wald)) return error.ExecError;
        result.wald = wald;
        result.chi_square_probability = @import("logistic_fit.zig").chiTail(wald, rank);
        if (denominator_df) |df| {
            const rankf: f64 = @floatFromInt(rank);
            result.f = wald / rankf;
            result.f_probability = @import("../functions.zig").betaI(df / (df + wald), df / 2, rankf / 2);
        }
    };
    return result;
}
