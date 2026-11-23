//! Physical-coordinate likelihood iterations for fixed-theta, fixed-beta fits.
//! Small-unit samples can have a regular maximum in rescaled coordinates
//! that the physical iteration never reaches. A stationary moment start can
//! still succeed at much higher curvature on precisely the same observations.
const std = @import("std");
const f = @import("../functions.zig");

pub const Point = struct { sigma: f64, alpha: f64 };
const Pair = struct { scale: f64, shape: f64 };
const Information = struct {
    scale: f64,
    shape: f64,
    cross: f64,

    fn determinant(self: Information) f64 {
        return self.scale * self.shape - self.cross * self.cross;
    }

    fn positive(self: Information) bool {
        return self.scale > 0 and self.shape > 0 and self.determinant() > 0;
    }

    fn regular(self: Information) bool {
        if (!self.positive()) return false;
        const top = (self.scale + self.shape + std.math.hypot(self.scale - self.shape, 2 * self.cross)) / 2;
        // Two supplied parameters have unit diagonal entries. At a condition
        // number of 1e6, M9 switches from the ordinary step to the ridge step.
        return @max(1, top) <= 1e6 * @min(1, self.determinant() / top);
    }

    fn solve(self: Information, score: Pair) Pair {
        const det = self.determinant();
        return .{
            .scale = (self.shape * score.scale - self.cross * score.shape) / det,
            .shape = (self.scale * score.shape - self.cross * score.scale) / det,
        };
    }

    fn direction(self: Information, score: Pair) ?Pair {
        if (self.regular()) return self.solve(score);
        // The two fixed unit diagonals contribute 2 to the squared Frobenius
        // norm. M9 one-step controls identify the first penalty as ||H|| / 32.
        var ridge = @sqrt(self.scale * self.scale + self.shape * self.shape + 2 * (1 + self.cross * self.cross)) / 32;
        for (0..64) |_| {
            const h = Information{ .scale = self.scale + ridge, .shape = self.shape + ridge, .cross = self.cross };
            if (h.positive()) return h.solve(score);
            ridge *= 4;
        }
        return null;
    }
};

const Evaluation = struct {
    score: Pair,
    h: Information,
    likelihood: f64,

    fn converged(self: Evaluation) bool {
        if (!self.h.positive()) return false;
        const step = self.h.solve(self.score);
        const decrease = self.score.scale * step.scale + self.score.shape * step.shape;
        // SAS/STAT relative gradient convergence (GCONV). Use the observed
        // information here; ridging the stopping test can disguise a large
        // remaining shape score when the scale direction is stiff.
        return decrease >= 0 and decrease <= 1e-8 * @max(1, @abs(self.likelihood));
    }
};

const Sample = struct {
    x: []const f64,
    theta: f64,
    beta: f64,
    mean_log: f64,

    fn evaluate(self: Sample, p: Point) Evaluation {
        const n: f64 = @floatFromInt(self.x.len);
        const log_scale = @log(p.sigma);
        var odds: f64 = 0;
        var squares: f64 = 0;
        var log_tail: f64 = 0;
        for (self.x) |value| {
            const x = value - self.theta;
            const ratio = x / (p.sigma - x);
            odds += ratio;
            squares += (1 + ratio) * (1 + ratio);
            log_tail += std.math.log1p(-x / p.sigma);
        }
        const log_beta = f.lgammaOf(p.alpha) + f.lgammaOf(self.beta) - f.lgammaOf(p.alpha + self.beta);
        return .{
            .score = .{
                .scale = ((self.beta - 1) * odds - n * p.alpha) / p.sigma,
                .shape = n * (f.digammaOf(p.alpha + self.beta) - f.digammaOf(p.alpha) + self.mean_log - log_scale),
            },
            .h = .{
                .scale = ((self.beta - 1) * squares - n * (p.alpha + self.beta - 1)) / (p.sigma * p.sigma),
                .shape = n * (f.trigammaOf(p.alpha) - f.trigammaOf(p.alpha + self.beta)),
                .cross = n / p.sigma,
            },
            .likelihood = n * (-log_beta - log_scale + (p.alpha - 1) * (self.mean_log - log_scale)) + (self.beta - 1) * log_tail,
        };
    }
};

/// Verify a regular interior solution when scale dominates the information
/// and either the candidate or an intermediate step needs a ridge. A transient
/// ill-conditioned step can still lead to convergence. Active width bounds
/// have a separate estimator in univ_endpoint_fit.
pub fn verifyInterior(x: []const f64, theta: f64, beta: f64, pilot: Point, floor: f64, fitted: Point, maxiter: usize) bool {
    const maximum = x[x.len - 1] - theta;
    if (!(pilot.sigma > maximum and pilot.sigma > floor and pilot.alpha > 0.001)) return true;
    var log_sum: f64 = 0;
    for (x) |v| log_sum += @log(v - theta);
    const sample: Sample = .{ .x = x, .theta = theta, .beta = beta, .mean_log = log_sum / @as(f64, @floatFromInt(x.len)) };
    const h = sample.evaluate(fitted).h;
    if (!h.positive() or h.scale <= @max(1, h.shape)) return true;
    var scale_ill_conditioned = !h.regular();
    var current = pilot;
    var at = sample.evaluate(current);
    // The SAS/STAT Newton methods default to 50 iterations (Shared Concepts,
    // Optimization Options). Longer runs can publish curves omitted by M9.
    for (0..@min(maxiter, 50)) |_| {
        if (at.converged()) return true;
        if (at.h.positive() and at.h.scale > @max(1, at.h.shape) and !at.h.regular()) scale_ill_conditioned = true;
        const delta = at.h.direction(at.score) orelse return !scale_ill_conditioned;
        var fraction: f64 = 1;
        if (delta.shape < 0) fraction = @min(fraction, 0.5 * (current.alpha - 0.001) / -delta.shape);
        if (delta.scale < 0) fraction = @min(fraction, 0.5 * (current.sigma - floor) / -delta.scale);
        for (0..48) |_| {
            const next: Point = .{ .sigma = current.sigma + fraction * delta.scale, .alpha = current.alpha + fraction * delta.shape };
            if (next.sigma == current.sigma and next.alpha == current.alpha) return !scale_ill_conditioned;
            if (next.sigma > maximum) {
                const trial = sample.evaluate(next);
                if (trial.likelihood >= at.likelihood) {
                    current = next;
                    at = trial;
                    break;
                }
            }
            fraction *= 0.5;
        } else return !scale_ill_conditioned;
    }
    return !scale_ill_conditioned or at.converged();
}

test "analytic ridge step matches a native beta fit with two supplied parameters" {
    // Independent M9 sample. With a slightly perturbed fixed second shape the
    // fitted table moves one step from its four-moment point.
    const x = [_]f64{ 2382491.7585883369, 3132717.8363576713, 4310010.6986129349, 4348565.6111373138, 4356538.8245248143, 4955022.7257061666, 5712152.2197101284, 5778974.9748990936, 6107213.4094476709, 6420941.8453887142, 7838634.4924343238, 10483582.1883725, 11088842.405083138 };
    const pilot: Point = .{ .sigma = 15360678.061462434, .alpha = 1.1412472380168814 };
    var sum: f64 = 0;
    for (x) |v| sum += @log(v);
    const sample: Sample = .{ .x = &x, .theta = 0, .beta = 1.2999490566300864, .mean_log = sum / @as(f64, x.len) };
    const at = sample.evaluate(pilot);
    const d = at.h.direction(at.score).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1.1413344007780701), pilot.alpha + d.shape, 2e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 15360678.061460283), pilot.sigma + d.scale, 5e-8);
}
