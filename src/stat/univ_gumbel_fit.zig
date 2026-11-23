//! Likelihood iterations for Gumbel scale with optional fixed location.
//! M9 ParameterEstimates on shifted and rescaled samples distinguish the raw
//! score, the finite-difference Newton step, and the additive diagonal ridge.
const std = @import("std");

pub const Estimate = struct { mu: f64, sigma: f64 };
const Evaluation = struct { location: f64, scale: f64, log_likelihood: f64 };
const Curvature = struct { location: f64, cross: f64, scale: f64 };

fn evaluate(x: []const f64, mu: f64, sigma: f64) Evaluation {
    var location: f64 = 0;
    var scale: f64 = 0;
    var log_likelihood = -@as(f64, @floatFromInt(x.len)) * @log(sigma);
    for (x) |v| {
        const z = (v - mu) / sigma;
        const residual = -std.math.expm1(-z);
        location += residual;
        scale += z * residual - 1;
        log_likelihood -= z + (1 - residual);
    }
    return .{ .location = location / sigma, .scale = scale / sigma, .log_likelihood = log_likelihood };
}

fn curvature(x: []const f64, start: Estimate, base: Evaluation, fixed_mu: bool) Curvature {
    // Forward differences of the analytic score. Symmetrize the two mixed
    // derivatives before solving for a joint location/scale update.
    const increment = std.math.cbrt(std.math.floatEps(f64));
    const high_sigma = start.sigma + increment * (1 + @abs(start.sigma));
    const scale = evaluate(x, start.mu, high_sigma);
    const ds = high_sigma - start.sigma;
    const ss = (scale.scale - base.scale) / ds;
    if (fixed_mu) return .{ .scale = ss, .location = 0, .cross = 0 };
    const high_mu = start.mu + increment * (1 + @abs(start.mu));
    const location = evaluate(x, high_mu, start.sigma);
    const dm = high_mu - start.mu;
    return .{
        .scale = ss,
        .location = (location.location - base.location) / dm,
        .cross = ((location.scale - base.scale) / dm + (scale.location - base.location) / ds) / 2,
    };
}

fn update(score: Evaluation, h: Curvature, ridge: f64, fixed_mu: bool) ?Estimate {
    const ss = ridge - h.scale;
    if (!(ss > 0)) return null;
    if (fixed_mu) return .{ .mu = 0, .sigma = score.scale / ss };
    const mm = ridge - h.location;
    const determinant = mm * ss - h.cross * h.cross;
    if (!(mm > 0 and determinant > 0)) return null;
    return .{
        .mu = (ss * score.location + h.cross * score.scale) / determinant,
        .sigma = (h.cross * score.location + mm * score.scale) / determinant,
    };
}

const Proposal = struct {
    estimate: Estimate,
    evaluation: Evaluation,
    projected_gain: f64,
};

fn propose(x: []const f64, current: Estimate, score: Evaluation, h: Curvature, ridge: f64, fixed_mu: bool) ?Proposal {
    const delta = update(score, h, ridge, fixed_mu) orelse return null;
    const next = Estimate{ .mu = current.mu + delta.mu, .sigma = current.sigma + delta.sigma };
    if (!(next.sigma > 0) or !std.math.isFinite(next.sigma) or !std.math.isFinite(next.mu)) return null;
    const trial = evaluate(x, next.mu, next.sigma);
    const projected = score.scale * delta.sigma + (if (fixed_mu) @as(f64, 0) else score.location * delta.mu);
    if (!(trial.log_likelihood >= score.log_likelihood and projected >= 0) or !std.math.isFinite(projected)) return null;
    return .{ .estimate = next, .evaluation = trial, .projected_gain = projected };
}

/// Returns null when the unregularized restart fails or the score is not
/// finite. The caller can still solve the one-dimensional profile score there.
pub fn fit(x: []const f64, initial: Estimate, fixed_mu: bool) ?Estimate {
    const first_ridge: f64 = 1.0 / 32.0;
    var current = initial;
    var score = evaluate(x, current.mu, current.sigma);
    var ridge: f64 = 0;
    var restarting = false;
    for (0..80) |_| {
        if (@abs(score.scale) <= 1e-5 and (fixed_mu or @abs(score.location) <= 1e-5)) return current;
        if (!std.math.isFinite(score.scale) or (!fixed_mu and !std.math.isFinite(score.location))) return null;
        const h = curvature(x, current, score, fixed_mu);
        for (0..64) |_| {
            if (propose(x, current, score, h, ridge, fixed_mu)) |trial| {
                if (trial.projected_gain <= 1e-8 * (@abs(score.log_likelihood) + @abs(trial.evaluation.log_likelihood))) return trial.estimate;
                if (ridge > 0) {
                    // Relax the diagonal penalty faster when the likelihood
                    // gains at least half the first-order prediction.
                    const gain = trial.evaluation.log_likelihood - score.log_likelihood;
                    ridge /= if (gain < 0.5 * trial.projected_gain) @as(f64, 2) else 4;
                    if (ridge < first_ridge) {
                        ridge = 0;
                        restarting = true;
                    }
                } else restarting = false;
                current = trial.estimate;
                score = trial.evaluation;
                break;
            }
            if (ridge == 0 and restarting) return null;
            ridge = if (ridge == 0) first_ridge else 4 * ridge;
        } else return null;
    }
    return null;
}
