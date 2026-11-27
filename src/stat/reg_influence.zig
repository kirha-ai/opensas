//! Leave-one-observation diagnostics from actual fitted crossproducts.
//! S154 physical pp.8627–8629; precision-weight extension uses sqrt(W)X.
const std = @import("std");
const diag = @import("../diag.zig");
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;
pub const Status = enum { ok, excluded, unit_leverage, no_variance, no_deleted_variance };
pub const Row = struct { status: Status = .ok, predicted: f64, residual: f64, leverage: f64, student: f64 = std.math.nan(f64), rstudent: f64 = std.math.nan(f64), cookd: f64 = std.math.nan(f64), covratio: f64 = std.math.nan(f64), dffits: f64 = std.math.nan(f64), press_residual: f64 = std.math.nan(f64), deleted_mse: f64 = std.math.nan(f64), dfbetas: []const f64, deleted_coefficients: []const f64 };
pub const Result = struct { rows: []const Row, press: ?f64, leverage_cutoff: f64, dffits_cutoff: f64, dfbetas_cutoff: f64, covratio_cutoff: f64 };
pub fn compute(a: A, x: []const f64, y: []const f64, weights: ?[]const f64, fit: Fit) diag.Error!Result {
    const n = y.len;
    const p = fit.coefficients.len;
    if (n == 0 or p == 0 or fit.rank != p or x.len != n * p or fit.residuals.len != n or fit.leverage.len != n or fit.covariance_unscaled.len != p * p) return error.ExecError;
    if (weights) |w| if (w.len != n) return error.ExecError;
    var count: usize = 0;
    for (0..n) |i| {
        const w = if (weights) |v| v[i] else 1;
        if (!std.math.isFinite(w) or w < 0) return error.ExecError;
        if (w > 0) count += 1;
    }
    // Frequency replication has a different deletion unit; never treat an
    // aggregated record as one ordinary observation without a defined contract.
    if (count != fit.n_used) return error.ExecError;
    const rows = try a.alloc(Row, n);
    var press: f128 = 0;
    var complete_press = true;
    for (rows, 0..) |*row, i| {
        const dfbetas = try a.alloc(f64, p);
        const deleted = try a.alloc(f64, p);
        @memset(dfbetas, std.math.nan(f64));
        @memset(deleted, std.math.nan(f64));
        row.* = .{ .predicted = fit.fitted[i], .residual = fit.residuals[i], .leverage = fit.leverage[i], .dfbetas = dfbetas, .deleted_coefficients = deleted };
        const w = if (weights) |v| v[i] else 1;
        const r = fit.residuals[i];
        const h = fit.leverage[i];
        if (w == 0) {
            row.status = .excluded;
            continue;
        }
        if (!std.math.isFinite(r) or !std.math.isFinite(h) or h < 0 or h > 1) return error.ExecError;
        const remaining = 1 - h;
        if (remaining <= 64 * std.math.floatEps(f64)) {
            row.status = .unit_leverage;
            complete_press = false;
            continue;
        }
        row.press_residual = r / remaining;
        press += @as(f128, w) * row.press_residual * row.press_residual;
        for (0..p) |j| {
            var v: f128 = 0;
            for (0..p) |k| v += @as(f128, fit.covariance_unscaled[j * p + k]) * x[i * p + k];
            deleted[j] = fit.coefficients[j] - @as(f64, @floatCast(v * @as(f128, w) * r / remaining));
        }
        if (!(fit.mse > 0) or !std.math.isFinite(fit.mse)) {
            row.status = .no_variance;
            continue;
        }
        row.student = @sqrt(w) * r / @sqrt(fit.mse * remaining);
        row.cookd = row.student * row.student * h / (@as(f64, @floatFromInt(p)) * remaining);
        if (fit.df_error <= 1) {
            row.status = .no_deleted_variance;
            continue;
        }
        const removed = w * r * r / remaining;
        var deleted_sse = fit.sse - removed;
        if (deleted_sse < 0 and @abs(deleted_sse) <= 64 * std.math.floatEps(f64) * (fit.sse + removed)) deleted_sse = 0;
        if (deleted_sse < 0) return error.ExecError;
        row.deleted_mse = deleted_sse / @as(f64, @floatFromInt(fit.df_error - 1));
        row.covratio = std.math.pow(f64, row.deleted_mse / fit.mse, @floatFromInt(p)) / remaining;
        if (!(row.deleted_mse > 0)) {
            row.status = .no_deleted_variance;
            continue;
        }
        row.rstudent = @sqrt(w) * r / @sqrt(row.deleted_mse * remaining);
        row.dffits = row.rstudent * @sqrt(h / remaining);
        for (dfbetas, 0..) |*v, j| if (fit.covariance_unscaled[j * p + j] > 0) {
            v.* = (fit.coefficients[j] - deleted[j]) / @sqrt(row.deleted_mse * fit.covariance_unscaled[j * p + j]);
        };
        if (!std.math.isFinite(row.rstudent) or !std.math.isFinite(row.covratio) or !std.math.isFinite(row.dffits)) return error.ExecError;
    }
    const nf: f64 = @floatFromInt(count);
    const pf: f64 = @floatFromInt(p);
    return .{ .rows = rows, .press = if (complete_press) @as(f64, @floatCast(press)) else null, .leverage_cutoff = 2 * pf / nf, .dffits_cutoff = 2 * @sqrt(pf / nf), .dfbetas_cutoff = 2 / @sqrt(nf), .covratio_cutoff = 3 * pf / nf };
}
