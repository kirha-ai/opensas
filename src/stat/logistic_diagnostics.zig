//! Pregibon one-step binary-logit diagnostics, S154 physical pp.5938–5941.
//! Frequency replicates contribute to the fitted covariance; deletion is of
//! one observation, not of every replicate. No universal cutoff is specified.
const std = @import("std");
const diag = @import("../diag.zig");
const A = std.mem.Allocator;
pub const Row = struct {
    source: usize = 0,
    x: []const f64,
    pearson: f64,
    deviance: f64,
    leverage: f64,
    dfbetas: []const f64,
    change: []const f64,
    c: f64,
    cbar: f64,
    difdev: f64,
    difchisq: f64,
    standardized_pearson: f64,
    standardized_deviance: f64,
    likelihood: f64,
};

/// The covariance must be the unscaled inverse information matrix of the
/// fitted logit model. `events`/`trials` refer to this original binomial row.
pub fn observation(a: A, x: []const f64, covariance: []const f64, events: f64, trials: f64, weight: f64, probability: f64) diag.Error!Row {
    const p = x.len;
    if (p == 0 or covariance.len != p * p or !(trials > 0) or !(weight > 0) or !(events >= 0 and events <= trials) or !(probability > 0 and probability < 1) or !std.math.isFinite(trials * weight)) return error.ExecError;
    const vx = try a.alloc(f64, p);
    const change = try a.alloc(f64, p);
    const dfbetas = try a.alloc(f64, p);
    var variance: f64 = 0;
    for (x, 0..) |v, i| {
        if (!std.math.isFinite(v) or !(covariance[i * p + i] > 0)) return error.ExecError;
        vx[i] = 0;
        for (x, 0..) |u, j| vx[i] += covariance[i * p + j] * u;
        variance += v * vx[i];
    }
    const residual = events - trials * probability;
    const binomial_variance = trials * probability * (1 - probability);
    const h = weight * binomial_variance * variance;
    if (!std.math.isFinite(h) or h < 0 or h > 1 + 64 * std.math.floatEps(f64)) return error.ExecError;
    const pearson = @sqrt(weight) * residual / @sqrt(binomial_variance);
    var deviance_square: f64 = 0;
    if (events > 0) deviance_square += events * @log(events / (trials * probability));
    if (events < trials) deviance_square += (trials - events) * @log((trials - events) / (trials * (1 - probability)));
    const sign: f64 = if (residual < 0) -1 else 1;
    const deviance = sign * @sqrt(@max(0, 2 * weight * deviance_square));
    const missing = std.math.nan(f64);
    // A saturated row has no deletion information. Preserve its residuals and
    // leverage, while explicitly representing undefined deletion measures.
    const denominator = 1 - h;
    const available = denominator > 0;
    for (0..p) |i| {
        change[i] = if (available) weight * residual * vx[i] / denominator else missing;
        dfbetas[i] = change[i] / @sqrt(covariance[i * p + i]);
    }
    const cbar = if (available) pearson * pearson * h / denominator else missing;
    const ep = if (available) pearson / @sqrt(denominator) else missing;
    const ed = if (available) deviance / @sqrt(denominator) else missing;
    return .{
        .x = x,
        .pearson = pearson,
        .deviance = deviance,
        .leverage = h,
        .dfbetas = dfbetas,
        .change = change,
        .cbar = cbar,
        .c = if (available) cbar / denominator else missing,
        .difdev = deviance * deviance + cbar,
        // Algebraic cancellation also defines the h=0 limit, avoiding 0/0.
        .difchisq = if (available) pearson * pearson / denominator else missing,
        .standardized_pearson = ep,
        .standardized_deviance = ed,
        .likelihood = if (available) sign * @sqrt(h * ep * ep + denominator * ed * ed) else missing,
    };
}

pub const Information = struct { minus2logl: f64, aic: f64, sc: f64, aicc: f64, rsquare: f64, max_rescaled: f64 };
/// S154 physical pp.5914–5916. n is total trial frequency, f is observation
/// frequency, and w is the total analysis mass for the likelihood's units.
pub fn information(ll: f64, null_ll: f64, constant: f64, parameters: usize, n: f64, f: f64, w: f64) diag.Error!Information {
    if (!std.math.isFinite(ll) or !std.math.isFinite(null_ll) or !std.math.isFinite(constant) or !(n > 0) or !(f > 0) or !(w > 0) or !std.math.isFinite(n + f + w)) return error.ExecError;
    const p: f64 = @floatFromInt(parameters);
    const rsquare = -std.math.expm1(2 * (null_ll - ll) / w);
    // Binomial likelihood includes log choose(n,r). It cancels in the
    // likelihood ratio but must remain in the maximum attainable R-square.
    const maximum = -std.math.expm1(2 * (null_ll + constant) / w);
    return .{ .minus2logl = -2 * ll, .aic = -2 * ll + 2 * p, .sc = -2 * ll + p * @log(n), .aicc = -2 * ll + (if (f > p + 2) 2 * p * f / (f - p - 1) else 2 * p * (p + 2)), .rsquare = rsquare, .max_rescaled = if (maximum > 0) rsquare / maximum else std.math.nan(f64) };
}
