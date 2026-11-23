//! Standalone beta/power endpoint and generalized Pareto fitting support.
//! SAS convention: Pareto alpha is minus the usual extreme-value shape xi.
const std = @import("std");
const f = @import("../functions.zig");
const beta_solver = @import("univ_beta_fit.zig");
pub const Family = enum { beta, power, pareto };
pub const Parameters = struct { theta: f64 = 0, sigma: f64 = 1, alpha: f64 = 1, beta: f64 = 1 };
/// Null requests estimation. Caller applies SAS defaults before entering.
pub const Fixed = struct { theta: ?f64 = 0, sigma: ?f64 = null, alpha: ?f64 = null, beta: ?f64 = null };
pub const Method = enum { mle, epm };
/// Internal solver budget, not the accepted-but-ineffective SAS beta MAXITER.
pub const Controls = struct { maxiter: usize = 1000, tolerance: f64 = 1e-9, method: Method = .mle };
pub const Reason = enum { invalid_sample, invalid_parameters, invalid_controls, unsupported_combination, unsupported_method, initialization_failed, nonstationary_candidate, outside_support, no_local_maximum, iteration_limit, boundary_solution };
pub const Curve = struct { parameters: Parameters, log_likelihood: f64, iterations: usize = 0 };
pub const Result = union(enum) { converged: Curve, nonconverged: struct { reason: Reason, best: ?Curve = null } };
fn fail(reason: Reason) Result {
    return .{ .nonconverged = .{ .reason = reason } };
}

pub fn logLikelihood(family: Family, x: []const f64, p: Parameters) f64 {
    if (!(p.sigma > 0) or !std.math.isFinite(p.sigma) or !std.math.isFinite(p.theta) or !std.math.isFinite(p.alpha)) return -std.math.inf(f64);
    if (family != .pareto and (!(p.alpha > 0) or !(p.beta > 0) or !std.math.isFinite(p.beta))) return -std.math.inf(f64);
    var sum: f64 = 0;
    const beta = if (family == .power) 1 else p.beta;
    // B(alpha,1)=1/alpha exactly, including the power boundary limit.
    const lb = if (family == .beta and beta != 1) f.lgammaOf(p.alpha) + f.lgammaOf(beta) - f.lgammaOf(p.alpha + beta) else if (family != .pareto) -@log(p.alpha) else 0;
    for (x) |v| {
        const y = (v - p.theta) / p.sigma;
        if (!(y > 0)) return -std.math.inf(f64);
        if (family == .pareto) {
            if (p.alpha == 1 and y <= 1) {
                sum -= @log(p.sigma);
                continue;
            }
            if (p.alpha * y >= 1) return -std.math.inf(f64);
            // Stable through alpha=0, including finite-difference derivatives.
            const a = p.alpha * y;
            const ratio = if (@abs(a) < 1e-5) -y * (1 + a * (0.5 + a * (1.0 / 3.0 + a / 4))) else std.math.log1p(-a) / p.alpha;
            sum += -@log(p.sigma) + (1 - p.alpha) * ratio;
        } else {
            if (beta == 1 and y == 1) {
                sum += @log(p.alpha / p.sigma);
                continue;
            }
            if (!(y < 1)) return -std.math.inf(f64);
            sum += -@log(p.sigma) - lb + (p.alpha - 1) * @log(y) + (beta - 1) * std.math.log1p(-y);
        }
    }
    return if (std.math.isFinite(sum)) sum else -std.math.inf(f64);
}

pub fn fit(family: Family, x: []const f64, fixed: Fixed, controls: Controls) Result {
    if (controls.method != .mle) return fail(.unsupported_method);
    if (x.len < 2) return fail(.invalid_sample);
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return fail(.invalid_sample);
    inline for (std.meta.fields(Fixed)) |field| if (@field(fixed, field.name)) |v| {
        if (!std.math.isFinite(v)) return fail(.invalid_parameters);
    };
    if (fixed.sigma != null and fixed.sigma.? <= 0) return fail(.invalid_parameters);
    if (family != .pareto and ((fixed.alpha != null and fixed.alpha.? <= 0) or (fixed.beta != null and fixed.beta.? <= 0))) return fail(.invalid_parameters);
    if (controls.maxiter == 0 or !(controls.tolerance > 0) or !std.math.isFinite(controls.tolerance)) return fail(.invalid_controls);
    if (family == .pareto and fixed.theta == null) return fail(.unsupported_combination); // M9 syntax rejects EST.
    if (fixed.theta != null and x[0] <= fixed.theta.?) return fail(.outside_support);
    if (family != .pareto and fixed.theta != null and fixed.sigma != null and x[x.len - 1] >= fixed.theta.? + fixed.sigma.?) return fail(.outside_support);
    if (fixed.theta != null and fixed.sigma != null and fixed.alpha != null and (family != .beta or fixed.beta != null)) {
        const p: Parameters = .{ .theta = fixed.theta.?, .sigma = fixed.sigma.?, .alpha = fixed.alpha.?, .beta = fixed.beta orelse 1 };
        const ll = logLikelihood(family, x, p);
        return if (std.math.isFinite(ll)) .{ .converged = .{ .parameters = p, .log_likelihood = ll } } else fail(.outside_support);
    }
    if (x[0] == x[x.len - 1]) return fail(.invalid_sample);
    // Beta(alpha,1) is the power distribution. Paired M9 fits share the
    // initialization, including absence of a curve, for these endpoint masks.
    const power_curve = family == .power or (family == .beta and fixed.beta == 1);
    if (power_curve and fixed.theta == null and fixed.sigma != null and
        fixed.alpha != null and fixed.alpha.? > 0 and fixed.alpha.? < 1)
        return powerLocation(x, fixed.sigma.?, fixed.alpha.?);
    if (power_curve and fixed.theta != null) {
        const sigma = fixed.sigma orelse (powerScaleStart(x, fixed.theta.?, fixed.alpha == null) orelse return fail(.initialization_failed));
        if (!std.math.isFinite(sigma) or !(sigma > x[x.len - 1] - fixed.theta.?)) return fail(.initialization_failed);
        var sum: f64 = 0;
        for (x) |v| sum += @log((v - fixed.theta.?) / sigma);
        const p: Parameters = .{ .theta = fixed.theta.?, .sigma = sigma, .alpha = fixed.alpha orelse (-@as(f64, @floatFromInt(x.len)) / sum) };
        const curve: Curve = .{ .parameters = p, .log_likelihood = logLikelihood(family, x, p) };
        // This reproduces SAS's finite returned candidate, not a stationary
        // maximum in the documented parameter domain. Keep that distinction
        // explicit for the adapter even when all parameters match the oracle.
        return if (fixed.sigma == null) .{ .nonconverged = .{ .reason = .nonstationary_candidate, .best = curve } } else .{ .converged = curve };
    }
    if (family == .beta and fixed.theta != null and fixed.sigma == null and fixed.alpha == null and fixed.beta != null) {
        const theta = fixed.theta.?;
        const beta = fixed.beta.?;
        const moments = scaleMoments(x);
        const floor = if (moments) |m| m.admissibleWidth(x, theta, true) else null;
        if (beta < 1) return betaAtScaleFloor(x, theta, floor orelse return fail(.initialization_failed), beta, controls);
        const fitted = optimize(family, x, fixed, controls);
        if (fitted != .converged) return fitted;
        const p = fitted.converged.parameters;
        if (floor) |sigma| {
            if (p.sigma < sigma) return betaAtScaleFloor(x, theta, sigma, beta, controls);
        }
        const m = moments orelse return fitted;
        const pilot = m.pilot orelse return fitted;
        if (p.sigma > m.floor and !beta_solver.verifyInterior(x, theta, beta, pilot, m.floor, .{ .sigma = p.sigma, .alpha = p.alpha }, controls.maxiter))
            return fail(.iteration_limit);
        return fitted;
    }
    if (family == .pareto and fixed.alpha != null and fixed.sigma == null) {
        if (paretoScale(x, fixed.theta.?, fixed.alpha.?, controls)) |curve| return .{ .converged = curve };
    }
    if (family == .pareto and fixed.alpha == null) {
        if (fixed.sigma) |sigma| {
            const theta = fixed.theta.?;
            const n: f64 = @floatFromInt(x.len);
            var mean: f64 = 0;
            for (x) |v| mean += (v - theta) / n;
            const alpha = sigma / mean - 1;
            // For supplied sigma the first moment determines the initial
            // shape. M9 suppresses a curve if it falls outside the support.
            if (alpha * (x[x.len - 1] - theta) >= sigma) return fail(.initialization_failed);
            if (alpha != 0 and alpha < 1) {
                const p: Parameters = .{ .theta = theta, .sigma = sigma, .alpha = alpha };
                if (paretoNewton(x, p, .shape, controls)) |curve| return .{ .converged = curve };
            }
        } else {
            if (paretoJoint(x, fixed.theta.?, controls)) |curve| return .{ .converged = curve };
            return paretoProfile(x, fixed.theta.?, controls);
        }
    }
    return optimize(family, x, fixed, controls);
}

const ParetoVector = @Vector(2, f64);

fn paretoDot(left: ParetoVector, right: ParetoVector) f64 {
    return @reduce(.Add, left * right);
}

fn paretoGradient(x: []const f64, point: Parameters) ParetoVector {
    return .{ paretoScore(x, point, .log_scale), paretoScore(x, point, .shape) };
}

/// The joint M9 iteration uses the moment estimates, sample variance with
/// divisor n-1, and a BFGS update in (log sigma, alpha) coordinates.
fn paretoJoint(x: []const f64, theta: f64, controls: Controls) ?Curve {
    var mean: f64 = 0;
    var squares: f64 = 0;
    for (x, 1..) |value, count| {
        const excess = value - theta;
        const delta = excess - mean;
        mean += delta / @as(f64, @floatFromInt(count));
        squares += delta * (excess - mean);
    }
    if (!(squares > 0 and mean > 0)) return null;
    const variance = squares / @as(f64, @floatFromInt(x.len - 1));
    const alpha = (mean * mean / variance - 1) / 2;
    const floor = alpha * (x[x.len - 1] - theta);
    const moment_scale = mean * (1 + alpha);
    const scale = if (moment_scale > floor) moment_scale else floor + 1e-6;
    if (!(scale > 0) or alpha >= 1) return null;
    var coordinates: ParetoVector = .{ @log(scale), alpha };
    var point: Parameters = .{ .theta = theta, .sigma = scale, .alpha = alpha };
    var ll = logLikelihood(.pareto, x, point);
    if (!std.math.isFinite(ll)) return null;
    var gradient = paretoGradient(x, point);
    // M9 limits the largest component of the initial ascent direction to five.
    const diagonal = @min(100, 5 / @reduce(.Max, @abs(gradient)));
    var inverse: [2]ParetoVector = .{ .{ diagonal, 0 }, .{ 0, diagonal } };
    var gain: f64 = 0;
    for (0..@min(controls.maxiter, 100)) |iteration| {
        if (@reduce(.Max, @abs(gradient)) <= 1e-5)
            return if (point.alpha < 1) .{ .parameters = point, .log_likelihood = ll, .iterations = iteration } else null;
        const direction: ParetoVector = .{ paretoDot(inverse[0], gradient), paretoDot(inverse[1], gradient) };
        const slope = paretoDot(direction, gradient);
        if (!(slope > 0) or !std.math.isFinite(slope)) return null;
        var step: f64 = if (iteration == 0) 1 else std.math.clamp(2.5 * gain / slope, 0.1, 1);
        var next: Parameters = undefined;
        var next_ll: f64 = undefined;
        var move: ParetoVector = undefined;
        for (0..64) |_| {
            move = @as(ParetoVector, @splat(step)) * direction;
            const proposed = coordinates + move;
            next = .{ .theta = theta, .sigma = @exp(proposed[0]), .alpha = proposed[1] };
            next_ll = logLikelihood(.pareto, x, next);
            gain = next_ll - ll;
            if (std.math.isFinite(next_ll) and gain >= 0.1 * step * slope) break;
            const quadratic = step * step * slope / (2 * (step * slope - gain));
            step = if (std.math.isFinite(quadratic)) std.math.clamp(quadratic, 0.1 * step, 0.9 * step) else 0.1 * step;
        } else return null;
        if (slope <= 1e-8 * @max(1, @abs(next_ll)))
            return if (next.alpha < 1) .{ .parameters = next, .log_likelihood = next_ll, .iterations = iteration + 1 } else null;
        const next_gradient = paretoGradient(x, next);
        const difference = gradient - next_gradient;
        const curvature = paretoDot(move, difference);
        if (!(curvature > 0) or !std.math.isFinite(curvature)) return null;
        const product: ParetoVector = .{ paretoDot(inverse[0], difference), paretoDot(inverse[1], difference) };
        const coefficient = (1 + paretoDot(difference, product) / curvature) / curvature;
        inline for (0..2) |row| {
            inverse[row] += @as(ParetoVector, @splat(coefficient * move[row])) * move -
                (@as(ParetoVector, @splat(move[row])) * product + @as(ParetoVector, @splat(product[row])) * move) /
                    @as(ParetoVector, @splat(curvature));
        }
        coordinates += move;
        point = next;
        ll = next_ll;
        gradient = next_gradient;
    }
    return null;
}

const ParetoAxis = enum { log_scale, shape };

fn paretoScore(x: []const f64, p: Parameters, axis: ParetoAxis) f64 {
    if (axis == .shape) {
        var sum: f64 = 0;
        for (x) |v| {
            const y = (v - p.theta) / p.sigma;
            const z = p.alpha * y;
            if (@abs(z) < 1e-4) {
                // Derivative of (1/alpha - 1) * log(1 - alpha*y);
                // avoid subtracting two O(1/alpha) terms at the exponential limit.
                sum += y * (1 + z * (1 + z * (1 + z))) -
                    y * y * (0.5 + z * (2.0 / 3.0 + z * (0.75 + z * 0.8)));
            } else {
                sum -= std.math.log1p(-z) / (p.alpha * p.alpha) + (1 / p.alpha - 1) * y / (1 - z);
            }
        }
        return sum;
    }
    var sum: f64 = 0;
    for (x) |v| {
        const excess = v - p.theta;
        sum += excess / (p.sigma - p.alpha * excess);
    }
    return (1 - p.alpha) * sum - @as(f64, @floatFromInt(x.len));
}

/// With a specified shape, M9 starts the log-scale iterations at the
/// first-moment estimate. Near the exponential limit it fits the mean and
/// retains the supplied shape in ParameterEstimates.
fn paretoScale(x: []const f64, theta: f64, alpha: f64, controls: Controls) ?Curve {
    const n: f64 = @floatFromInt(x.len);
    const maximum = x[x.len - 1] - theta;
    var mean: f64 = 0;
    for (x) |v| mean += (v - theta) / n;
    var p: Parameters = .{ .theta = theta, .sigma = mean, .alpha = alpha };
    if (alpha == 1 or @abs(alpha) < 1e-6) {
        if (alpha == 1) p.sigma = maximum;
        return .{ .parameters = p, .log_likelihood = logLikelihood(.pareto, x, p) };
    }
    if (!(alpha > -1 and alpha < 1)) return null;
    p.sigma = mean * (1 + alpha);
    // If a positive shape puts the moment estimate outside the support,
    // M9 starts one micro-unit above the physical scale boundary.
    if (p.sigma <= alpha * maximum) p.sigma = alpha * maximum + 1e-6;
    return paretoNewton(x, p, .log_scale, controls);
}

fn paretoPoint(p: Parameters, axis: ParetoAxis, coordinate: f64) Parameters {
    var point = p;
    switch (axis) {
        .log_scale => point.sigma = @exp(coordinate),
        .shape => point.alpha = coordinate,
    }
    return point;
}

fn paretoNewton(x: []const f64, initial: Parameters, axis: ParetoAxis, controls: Controls) ?Curve {
    var coordinate = if (axis == .shape) initial.alpha else @log(initial.sigma);
    var p = paretoPoint(initial, axis, coordinate);
    var ll = logLikelihood(.pareto, x, p);
    if (!std.math.isFinite(ll)) return null;
    const first_ridge: f64 = 1.0 / 32.0;
    var ridge: f64 = 0;
    for (0..@min(controls.maxiter, 80)) |i| {
        const score = paretoScore(x, p, axis);
        if (@abs(score) <= 1e-5) return .{ .parameters = p, .log_likelihood = ll, .iterations = i };
        const high = coordinate + std.math.cbrt(std.math.floatEps(f64)) * (1 + @abs(coordinate));
        const probe = paretoPoint(p, axis, high);
        const curvature = (paretoScore(x, probe, axis) - score) / (high - coordinate);
        if (!std.math.isFinite(curvature)) return null;
        // A positive shape curvature can lead to an unbounded boundary
        // likelihood. Keep that case in the existing constrained search.
        if (axis == .shape and curvature >= 0) return null;
        for (0..64) |_| {
            if (ridge > curvature) {
                const delta = score / (ridge - curvature);
                const next = coordinate + delta;
                const candidate = paretoPoint(p, axis, next);
                const next_ll = logLikelihood(.pareto, x, candidate);
                if (std.math.isFinite(next_ll) and next_ll >= ll) {
                    const projected = score * delta;
                    if (projected <= 1e-8 * (@abs(ll) + @abs(next_ll)))
                        return .{ .parameters = candidate, .log_likelihood = next_ll, .iterations = i + 1 };
                    if (ridge > 0) {
                        ridge /= if (next_ll - ll < 0.5 * projected) @as(f64, 2) else 4;
                        if (ridge < first_ridge) ridge = 0;
                    }
                    coordinate = next;
                    p = candidate;
                    ll = next_ll;
                    break;
                }
            }
            ridge = if (ridge == 0) first_ridge else 4 * ridge;
        } else return null;
    }
    return null;
}

/// M9 retains the moment-based width when it bounds the fitted scale.
/// For beta < 1 the scale score is always negative. For beta > 1 the
/// width can also exceed an interior likelihood maximizer. Fit alpha
/// conditional on the retained width.
fn betaAtScaleFloor(x: []const f64, theta: f64, sigma: f64, beta: f64, controls: Controls) Result {
    const n: f64 = @floatFromInt(x.len);
    var mean_log: f64 = 0;
    for (x) |v| mean_log += @log((v - theta) / sigma) / n;
    // The conditional alpha score decreases strictly from +infinity to the
    // sample mean of log(y/sigma), so its root is unique.
    var lower: f64 = 0;
    var upper: f64 = 1;
    while (f.digammaOf(upper + beta) - f.digammaOf(upper) + mean_log > 0) {
        upper *= 2;
        if (!std.math.isFinite(upper)) return fail(.no_local_maximum);
    }
    for (0..@min(controls.maxiter, 100)) |iter| {
        const alpha = lower + (upper - lower) / 2;
        if (alpha == lower or alpha == upper) {
            const p: Parameters = .{ .theta = theta, .sigma = sigma, .alpha = alpha, .beta = beta };
            const curve: Curve = .{ .parameters = p, .log_likelihood = logLikelihood(.beta, x, p), .iterations = iter };
            return .{ .nonconverged = .{ .reason = .nonstationary_candidate, .best = curve } };
        }
        if (f.digammaOf(alpha + beta) - f.digammaOf(alpha) + mean_log > 0) lower = alpha else upper = alpha;
    }
    return fail(.iteration_limit);
}

/// Verified M9 slice: estimated theta, supplied sigma and 0<alpha<1.
/// SAS's retained point is not a stationary MLE. Its public adapter must carry
/// the nonstationary_candidate status even when parameters match.
fn powerLocation(x: []const f64, sigma: f64, alpha: f64) Result {
    @setFloatMode(.strict); // IEEE rounding order is part of the oracle contract.
    const lo = x[0];
    const hi = x[x.len - 1];
    const span = hi - lo;
    if (!(sigma > span)) return fail(.outside_support);
    // Actual reset and nonreset n=2/3 probes emit no curve; n=4 works even
    // when four-moment shape geometry is inadmissible. No pilot-shape guard.
    if (x.len < 4) return fail(.initialization_failed);
    const n: f64 = @floatFromInt(x.len);
    var normalized_mean: f64 = 0;
    for (x) |v| normalized_mean += ((v - lo) / span) / n;
    const mean = lo + span * normalized_mean;
    const location = mean - sigma * alpha / (alpha + 1);
    const gap = lo - location;
    const reset = gap <= 0;
    const theta = lo - (if (reset) @as(f64, 0.001) else @min(@as(f64, 0.001), 0.1 * gap));
    if (reset) {
        // Preserve operation order AND equality. Independent +/-ULP oracle
        // controls distinguish this from sigma-span >= .002 and from a strict
        // bound comparison. Do not insert a tolerance or reassociate it.
        const lower = (hi - sigma) + 0.001;
        const upper = lo - 0.001;
        if (!(lower <= upper)) return fail(.initialization_failed);
    }
    if (!std.math.isFinite(theta) or !(theta < lo and theta + sigma > hi))
        return fail(.initialization_failed);
    const p: Parameters = .{ .theta = theta, .sigma = sigma, .alpha = alpha };
    const ll = logLikelihood(.power, x, p);
    if (!std.math.isFinite(ll)) return fail(.initialization_failed);
    return .{ .nonconverged = .{ .reason = .nonstationary_candidate, .best = .{ .parameters = p, .log_likelihood = ll } } };
}

/// M9 fixed-theta power scale initializer, prospectively verified on fresh
/// shapes/n, fixed alpha, affine changes and inadmissible moment regions.
/// Samples are normalized before forming central moments to avoid overflow
/// and loss of precision from translating observations far from zero.
const ScaleMoments = struct {
    mean: f64,
    variance: f64,
    floor: f64,
    pilot: ?beta_solver.Point = null,

    fn admissibleWidth(self: ScaleMoments, x: []const f64, theta: f64, estimate_alpha: bool) ?f64 {
        if (estimate_alpha and self.pilot == null) return null;
        const span = x[x.len - 1] - x[0];
        const sigma = self.floor;
        if (!(sigma > x[x.len - 1] - theta) or !std.math.isFinite(sigma)) return null;
        if (estimate_alpha) {
            // The shape start must also be admissible for the actual fixed
            // endpoints, not just for the four-moment distribution's endpoints.
            const ymean = (x[0] - theta) / sigma + (span / sigma) * self.mean;
            const yvariance = self.variance * (span / sigma) * (span / sigma);
            if (!(ymean * (1 - ymean) > yvariance)) return null;
        }
        return sigma;
    }
};

fn scaleMoments(x: []const f64) ?ScaleMoments {
    if (x.len < 4) return null;
    const span = x[x.len - 1] - x[0];
    if (!(span > 0) or !std.math.isFinite(span)) return null;
    const n: f64 = @floatFromInt(x.len);
    var mean: f64 = 0;
    for (x) |v| mean += ((v - x[0]) / span) / n;
    var ss2: f64 = 0;
    var ss3: f64 = 0;
    var ss4: f64 = 0;
    for (x) |v| {
        const d = (v - x[0]) / span - mean;
        ss2 += d * d;
        ss3 += d * d * d;
        ss4 += d * d * d * d;
    }
    const variance = ss2 / (n - 1);
    const skew = n * ss3 / ((n - 1) * (n - 2) * variance * @sqrt(variance));
    const kurt = n * (n + 1) * ss4 / ((n - 1) * (n - 2) * (n - 3) * variance * variance) - 3 * (n - 1) * (n - 1) / ((n - 2) * (n - 3));
    const denominator = 1.5 * skew * skew - kurt;
    const total = (6 + 3 * kurt - 3 * skew * skew) / denominator;
    var moments: ScaleMoments = .{ .mean = mean, .variance = variance, .floor = span + 0.002 };
    if (denominator > 0 and total > 0 and std.math.isFinite(total)) {
        const imbalance2 = skew * skew * (total + 2) * (total + 2) / (16 * (total + 1) + skew * skew * (total + 2) * (total + 2));
        if (!(imbalance2 >= 0 and imbalance2 < 1)) return null;
        const width = 2 * span * @sqrt(variance * (total + 1) / (1 - imbalance2));
        if (!std.math.isFinite(width)) return null;
        moments.floor = span + @min(@as(f64, 0.002), 0.1 * (width - span));
        moments.pilot = .{ .sigma = width, .alpha = 0.5 * (1 - std.math.copysign(@sqrt(imbalance2), skew)) * total };
    }
    return moments;
}

fn powerScaleStart(x: []const f64, theta: f64, estimate_alpha: bool) ?f64 {
    const moments = scaleMoments(x) orelse return null;
    return moments.admissibleWidth(x, theta, estimate_alpha);
}

const Problem = struct {
    family: Family,
    x: []const f64,
    fixed: Fixed,
    range: f64,
    fn decode(self: Problem, q: [4]f64) Parameters {
        const lo = self.x[0];
        const hi = self.x[self.x.len - 1];
        var p: Parameters = .{};
        if (self.family != .pareto) {
            p.theta = self.fixed.theta orelse (if (self.fixed.sigma) |s| (hi - s) + (lo - (hi - s)) / (1 + @exp(-q[0])) else lo - self.range * @exp(q[0]));
            p.sigma = self.fixed.sigma orelse (hi + self.range * @exp(q[1]) - p.theta);
            p.alpha = self.fixed.alpha orelse @exp(q[2]);
            p.beta = if (self.family == .power) 1 else self.fixed.beta orelse @exp(q[3]);
        } else {
            p.theta = self.fixed.theta.?;
            // Grimshaw's regular search region is alpha<=1. Beyond it,
            // the endpoint likelihood is unbounded; never call a rounded
            // spike at an observed maximum a converged MLE.
            p.alpha = self.fixed.alpha orelse (1 - @exp(q[2]));
            p.sigma = self.fixed.sigma orelse (@max(@as(f64, 0), p.alpha * (hi - p.theta)) + self.range * @exp(q[1]));
        }
        return p;
    }
    fn value(self: Problem, q: [4]f64) f64 {
        return -logLikelihood(self.family, self.x, self.decode(q)) / @as(f64, @floatFromInt(self.x.len));
    }
};
const Point = struct { q: [4]f64, value: f64 };
fn less(_: void, a: Point, b: Point) bool {
    return a.value < b.value;
}

/// Nelder-Mead in support-preserving coordinates, followed by an explicit
/// boundary check. Finite stopped candidates remain tagged nonconverged.
fn optimize(family: Family, x: []const f64, fixed: Fixed, controls: Controls) Result {
    const problem: Problem = .{ .family = family, .x = x, .fixed = fixed, .range = x[x.len - 1] - x[0] };
    if (family != .pareto and fixed.theta == null and fixed.sigma != null and fixed.sigma.? <= problem.range) return fail(.outside_support);
    var axes: [4]usize = undefined;
    var dim: usize = 0;
    const free = [_]bool{ fixed.theta == null, fixed.sigma == null, fixed.alpha == null, family == .beta and fixed.beta == null };
    for (free, 0..) |yes, j| if (yes) {
        axes[dim] = j;
        dim += 1;
    };
    var global: ?Curve = null;
    var any_converged = false;
    var boundary = false;
    var total: usize = 0;
    for (0..3) |start| {
        var initial: [4]f64 = .{ -2 + @as(f64, @floatFromInt(start)), -2 + @as(f64, @floatFromInt(start)), @log(@as(f64, 2)), @log(@as(f64, 3)) };
        if (family != .pareto and fixed.theta == null and fixed.sigma != null) initial[0] = 0;
        if (family == .pareto) {
            var mean: f64 = 0;
            for (x) |v| mean += (v - fixed.theta.?) / @as(f64, @floatFromInt(x.len));
            initial[2] = @log(1.3 - 0.3 * @as(f64, @floatFromInt(start)));
            initial[1] = @log(mean / problem.range);
        }
        var simplex: [5]Point = undefined;
        simplex[0] = .{ .q = initial, .value = problem.value(initial) };
        for (0..dim) |j| {
            var q = initial;
            q[axes[j]] += 0.2;
            simplex[j + 1] = .{ .q = q, .value = problem.value(q) };
        }
        var converged = false;
        for (0..controls.maxiter) |_| {
            total += 1;
            std.mem.sort(Point, simplex[0 .. dim + 1], {}, less);
            var diameter: f64 = 0;
            for (simplex[1 .. dim + 1]) |p| for (axes[0..dim]) |j| {
                diameter = @max(diameter, @abs(p.q[j] - simplex[0].q[j]));
            };
            if (diameter < @sqrt(controls.tolerance) and simplex[dim].value - simplex[0].value < controls.tolerance and std.math.isFinite(simplex[0].value)) {
                converged = true;
                break;
            }
            var center = simplex[0].q;
            for (axes[0..dim]) |j| {
                center[j] = 0;
                for (simplex[0..dim]) |p| center[j] += p.q[j] / @as(f64, @floatFromInt(dim));
            }
            var reflected = center;
            for (axes[0..dim]) |j| reflected[j] = 2 * center[j] - simplex[dim].q[j];
            const vr = problem.value(reflected);
            if (vr < simplex[0].value) {
                var expanded = center;
                for (axes[0..dim]) |j| expanded[j] = center[j] + 2 * (reflected[j] - center[j]);
                const ve = problem.value(expanded);
                simplex[dim] = if (ve < vr) .{ .q = expanded, .value = ve } else .{ .q = reflected, .value = vr };
            } else if (vr < simplex[dim - 1].value) {
                simplex[dim] = .{ .q = reflected, .value = vr };
            } else {
                var contracted = center;
                for (axes[0..dim]) |j| contracted[j] = center[j] + 0.5 * ((if (vr < simplex[dim].value) reflected[j] else simplex[dim].q[j]) - center[j]);
                const vc = problem.value(contracted);
                if (vc < @min(vr, simplex[dim].value)) simplex[dim] = .{ .q = contracted, .value = vc } else {
                    for (simplex[1 .. dim + 1]) |*p| {
                        for (axes[0..dim]) |j| p.q[j] = (p.q[j] + simplex[0].q[j]) / 2;
                        p.value = problem.value(p.q);
                    }
                }
            }
        }
        std.mem.sort(Point, simplex[0 .. dim + 1], {}, less);
        const p = problem.decode(simplex[0].q);
        const ll = logLikelihood(family, x, p);
        const edge = if (family != .pareto) ((fixed.theta == null and (x[0] - p.theta) / problem.range < 1e-8) or (fixed.sigma == null and (p.theta + p.sigma - x[x.len - 1]) / problem.range < 1e-8)) else p.alpha > 0 and (p.sigma / p.alpha - (x[x.len - 1] - p.theta)) / problem.range < 1e-8;
        if (std.math.isFinite(ll) and (global == null or ll > global.?.log_likelihood)) {
            global = .{ .parameters = p, .log_likelihood = ll };
            any_converged = converged and stationary(problem, simplex[0].q, axes[0..dim]);
            boundary = edge;
        }
    }
    if (global) |*g| {
        // At alpha=1 and max(x-theta)<sigma the shape score is strictly
        // positive. The transformed search can round alpha up to one even
        // though this uniform curve is not a likelihood maximum.
        if (family == .pareto and fixed.sigma != null and fixed.alpha == null and g.parameters.alpha == 1 and
            g.parameters.sigma > x[x.len - 1] - g.parameters.theta) return fail(.no_local_maximum);
        g.iterations = total;
        if (any_converged and !boundary) return .{ .converged = g.* };
        // SAS emits no beta curve when endpoint estimation fails. Retain
        // Pareto's finite boundary candidates explicitly as warned fits.
        return .{ .nonconverged = .{ .reason = if (boundary) .boundary_solution else .iteration_limit, .best = if (family != .beta) g.* else null } };
    }
    return fail(.no_local_maximum);
}

fn check(expected: Parameters, result: Result, tolerance: f64) !void {
    const curve = switch (result) {
        .converged => |c| c,
        .nonconverged => |n| {
            std.debug.print("endpoint failure {s}\n", .{@tagName(n.reason)});
            return error.TestUnexpectedResult;
        },
    };
    inline for (std.meta.fields(Parameters)) |field| try std.testing.expectApproxEqAbs(@field(expected, field.name), @field(curve.parameters, field.name), tolerance);
}

test "endpoint beta SAS M9 all fixed estimated combinations" {
    var x: [101]f64 = undefined;
    for (&x, 0..) |*v, i| v.* = f.distQuantile(.beta, (@as(f64, @floatFromInt(i + 1)) - 0.375) / 101.25, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 2 }, .{ .num = 3 } }).?;
    const expected = [_]Parameters{
        .{ .theta = 0, .sigma = 1, .alpha = 2, .beta = 3 },
        .{ .theta = 0.003474, .sigma = 1, .alpha = 2, .beta = 3 },
        .{ .theta = 0, .sigma = 0.990724, .alpha = 2, .beta = 3 },
        .{ .theta = 0.008588, .sigma = 0.977054, .alpha = 2, .beta = 3 },
        .{ .theta = 0, .sigma = 1, .alpha = 2.009625, .beta = 3 },
        .{ .theta = 0.011914, .sigma = 1, .alpha = 1.90133, .beta = 3 },
        .{ .theta = 0, .sigma = 0.98363, .alpha = 2.049554, .beta = 3 },
        .{ .theta = 0.012588, .sigma = 0.979395, .alpha = 1.940936, .beta = 3 },
        .{ .theta = 0, .sigma = 1, .alpha = 2, .beta = 3.016591 },
        .{ .theta = 0.008123, .sigma = 1, .alpha = 2, .beta = 3.111371 },
        .{ .theta = 0, .sigma = 0.96286, .alpha = 2, .beta = 2.803269 },
        .{ .theta = 0.007139, .sigma = 0.964088, .alpha = 2, .beta = 2.891322 },
        .{ .theta = 0, .sigma = 1, .alpha = 2.05622, .beta = 3.088703 },
        .{ .theta = 0.011111, .sigma = 1, .alpha = 1.944047, .beta = 3.071715 },
        .{ .theta = 0, .sigma = 0.957832, .alpha = 1.970388, .beta = 2.739213 },
        .{ .theta = 0.021695, .sigma = 0.910261, .alpha = 1.669283, .beta = 2.349019 },
    };
    for (expected, 0..) |p, mask| {
        const fixed: Fixed = .{ .theta = if (mask & 1 == 0) 0 else null, .sigma = if (mask & 2 == 0) 1 else null, .alpha = if (mask & 4 == 0) 2 else null, .beta = if (mask & 8 == 0) 3 else null };
        const result = fit(.beta, &x, fixed, .{});
        try check(p, result, 1e-4);
    }
}

test "endpoint Pareto SAS M9 negative shape fixed and estimated" {
    var x: [101]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 101.25;
        v.* = 2 * (std.math.pow(f64, 1 - q, -0.3) - 1) / 0.3;
    }
    try check(.{ .theta = 0, .sigma = 2.043369, .alpha = -0.26684 }, fit(.pareto, &x, .{}, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 1.991393, .alpha = -0.3 }, fit(.pareto, &x, .{ .alpha = -0.3 }, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 2, .alpha = -0.27802 }, fit(.pareto, &x, .{ .sigma = 2 }, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 2.764319, .alpha = 0 }, fit(.pareto, &x, .{ .alpha = 0 }, .{}), 5e-5);
}

test "specified Pareto shape follows M9 log-scale Newton steps and exponential limit" {
    const sample = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    for ([_]f64{ 1, 1e5 }, [_]f64{ 6.9179109917530734, 691791.0998294684 }) |scale, expected| {
        var x: [sample.len]f64 = undefined;
        for (sample, &x) |v, *out| out.* = -3 + v * scale;
        const curve = fit(.pareto, &x, .{ .theta = -3, .alpha = 0.2 }, .{}).converged;
        try std.testing.expectApproxEqAbs(expected / scale, curve.parameters.sigma / scale, 1e-10);
    }
    const tied = [_]f64{ 1, 1, 1, 2, 3, 8, 23 };
    try check(.{ .sigma = 3.658276968259533, .alpha = -0.3 }, fit(.pareto, &tied, .{ .alpha = -0.3 }, .{}), 1e-11);
    try check(.{ .sigma = 16.177794893374532, .alpha = 0.65 }, fit(.pareto, &tied, .{ .alpha = 0.65 }, .{}), 1e-10);
    const small = [_]f64{ 0.25, 0.65, 0.77, 1.33, 2.35, 6.23, 12.51 };
    for ([_]f64{ -1e-8, 9.999e-7, 1e-6 }, [_]f64{ 3.4414285714285713, 3.4414285714285713, 3.4414320128571427 }) |alpha, expected| {
        const curve = fit(.pareto, &small, .{ .alpha = alpha }, .{}).converged;
        try std.testing.expectEqual(alpha, curve.parameters.alpha);
        try std.testing.expectApproxEqAbs(expected, curve.parameters.sigma, 1e-12);
    }
}

test "specified Pareto scale follows native shape Newton iterations and support checks" {
    var gp: [40]f64 = undefined;
    for (&gp, 0..) |*v, i| {
        const u = std.math.pow(f64, (@as(f64, @floatFromInt(i)) + 0.5) / 40, 1.5);
        v.* = (std.math.pow(f64, 1 - u, -0.3) - 1) / 0.3;
    }
    const curve = fit(.pareto, &gp, .{ .sigma = 1 }, .{}).converged;
    try std.testing.expectApproxEqAbs(@as(f64, -0.2015124150754448), curve.parameters.alpha, 1e-11);
    // The moment-based initial shape exceeds sigma / max(x).
    const heavy = [_]f64{ 1, 1, 1, 2, 3, 8, 23 };
    const absent = fit(.pareto, &heavy, .{ .sigma = 7.8 }, .{});
    try std.testing.expectEqual(Reason.initialization_failed, absent.nonconverged.reason);
    try std.testing.expect(absent.nonconverged.best == null);
}

test "endpoint heldout shifted scaled beta Pareto and power" {
    var b: [77]f64 = undefined;
    var g: [77]f64 = undefined;
    var p: [77]f64 = undefined;
    for (&b, &g, &p, 0..) |*bv, *gv, *pv, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 77.25;
        bv.* = -3 + 7 * f.distQuantile(.beta, q, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 3 }, .{ .num = 4 } }).?;
        gv.* = 5 + 3 * (1 - std.math.pow(f64, 1 - q, 0.2)) / 0.2;
        pv.* = std.math.pow(f64, q, 0.2);
    }
    try check(.{ .theta = -2.64712, .sigma = 5.940861, .alpha = 2.161829, .beta = 2.691863 }, fit(.beta, &b, .{ .theta = null }, .{}), 2e-4);
    try check(.{ .theta = -3, .sigma = 6.63445, .alpha = 2.945211, .beta = 3.560869 }, fit(.beta, &b, .{ .theta = -3 }, .{}), 2e-4);
    try check(.{ .theta = -2.92361, .sigma = 7, .alpha = 3, .beta = 4.19181 }, fit(.beta, &b, .{ .theta = null, .sigma = 7, .alpha = 3 }, .{}), 2e-4);
    try check(.{ .theta = 5, .sigma = 3.099691, .alpha = 0.242724 }, fit(.pareto, &g, .{ .theta = 5 }, .{}), 1e-4);
    try check(.{ .theta = 5, .sigma = 2.952003, .alpha = 0.2 }, fit(.pareto, &g, .{ .theta = 5, .alpha = 0.2 }, .{}), 1e-4);
    try check(.{ .theta = 5, .sigma = 3, .alpha = 0.22375 }, fit(.pareto, &g, .{ .theta = 5, .sigma = 3 }, .{}), 1e-4);
    try check(.{ .theta = 0, .sigma = 1, .alpha = 5.055881 }, fit(.power, &p, .{ .sigma = 1 }, .{}), 1e-6);
}

test "endpoint SAS degeneracy, uniform boundary and failed endpoint fits" {
    const x = &[_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const beta = fit(.beta, x, .{ .theta = null }, .{});
    try std.testing.expect(beta == .nonconverged);
    try std.testing.expect(beta.nonconverged.best == null);
    try std.testing.expect(fit(.beta, x, .{ .theta = null, .alpha = 1, .beta = 1 }, .{}) == .nonconverged);
    try std.testing.expect(fit(.beta, x, .{ .theta = 0, .alpha = 0.5, .beta = 0.5 }, .{}) == .nonconverged);
    try std.testing.expect(fit(.power, x, .{ .theta = null }, .{}) == .nonconverged);
    try check(.{ .theta = 0, .sigma = 15, .alpha = 1 }, fit(.pareto, x, .{ .alpha = 1 }, .{}), 1e-12);
    try check(.{ .theta = 0, .sigma = 10.99992, .alpha = 0.6815 }, fit(.pareto, x, .{}, .{}), 2e-4);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.beta, &.{ 1, 1, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.outside_support, fit(.beta, &.{ 0, 0.5, 1 }, .{ .sigma = 1 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.unsupported_combination, fit(.pareto, x, .{ .theta = null }, .{}).nonconverged.reason);
}

test "endpoint stopped power curves remain explicit and Pareto absent roots remain loud" {
    var x: [41]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 41.25;
        v.* = q * q;
    }
    const r = fit(.power, &x, .{}, .{});
    try std.testing.expectEqual(Reason.nonstationary_candidate, r.nonconverged.reason);
    const p = r.nonconverged.best.?.parameters;
    // M9's returned pilot, not the earlier mathematical max(x) boundary
    // substitution. Retained HEX16 estimates establish the new expectation.
    try std.testing.expectApproxEqAbs(@as(f64, 0.9716969696969697), p.sigma, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5171650979229946), p.alpha, 5e-5);
    try std.testing.expect(p.sigma > x[40]);
    try std.testing.expect(std.math.isFinite(r.nonconverged.best.?.log_likelihood));
    for ([_]f64{ 1, 3, 4 }) |shift| {
        var y = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
        for (&y) |*v| v.* += shift;
        const absent = fit(.pareto, &y, .{}, .{});
        try std.testing.expectEqual(Reason.no_local_maximum, absent.nonconverged.reason);
        try std.testing.expect(absent.nonconverged.best == null);
    }
}

const ParetoProfile = struct {
    x: []const f64,
    theta: f64,
    maximum: f64,
    const Evaluation = struct { score: f64, slope: f64 };
    // Store the derivative of the unscaled score u²*score. It has the same
    // nonzero roots, and its extrema can isolate pairs missed by a sign scan.
    fn evaluate(self: @This(), u: f64) Evaluation {
        const n: f64 = @floatFromInt(self.x.len);
        if (@abs(u) < 0.001) {
            // Divide Grimshaw's score by its spurious u^2 zero. The series
            // remains continuous through the exponential limit at u=0.
            var m = [_]f64{0} ** 9;
            m[0] = 1;
            for (self.x) |v| {
                const z = (v - self.theta) / self.maximum;
                var power = z;
                for (1..9) |k| {
                    m[k] += power / n;
                    power *= z;
                }
            }
            var sum: f64 = 0;
            var slope: f64 = 0;
            var power: f64 = 1;
            for (2..9) |k| {
                var coefficient = m[k];
                for (1..k + 1) |j| coefficient -= m[j] * m[k - j] / @as(f64, @floatFromInt(j));
                sum += coefficient * power;
                slope += @as(f64, @floatFromInt(k)) * coefficient * power;
                power *= u;
            }
            return .{ .score = sum, .slope = u * slope };
        }
        var logarithm: f64 = 0;
        var reciprocal: f64 = 0;
        var reciprocal_derivative: f64 = 0;
        for (self.x) |v| {
            const z = u * (v - self.theta) / self.maximum;
            logarithm += std.math.log1p(-z) / n;
            const inv = 1 / (1 - z);
            reciprocal += inv / n;
            reciprocal_derivative += (v - self.theta) / self.maximum * inv * inv / n;
        }
        return .{
            .score = ((1 + logarithm) * reciprocal - 1) / (u * u),
            .slope = (1 - reciprocal) * reciprocal / u + (1 + logarithm) * reciprocal_derivative,
        };
    }

    fn turningPoint(self: @This(), lower: f64, upper: f64, lower_slope: f64) f64 {
        var lo = lower;
        var hi = upper;
        for (0..55) |_| {
            const mid = (lo + hi) / 2;
            if (mid == lo or mid == hi) break;
            if (self.evaluate(mid).slope * lower_slope > 0) lo = mid else hi = mid;
        }
        return (lo + hi) / 2;
    }
    fn curve(self: @This(), u: f64) ?Curve {
        const n: f64 = @floatFromInt(self.x.len);
        var sigma: f64 = 0;
        for (self.x) |v| {
            const z = (v - self.theta) / self.maximum;
            sigma += self.maximum * (if (@abs(u * z) < 1e-5) z * (1 + u * z * (0.5 + u * z / 3)) else -std.math.log1p(-u * z) / u) / n;
        }
        const p: Parameters = .{ .theta = self.theta, .sigma = sigma, .alpha = u * sigma / self.maximum };
        if (p.alpha > 1) return null;
        const ll = logLikelihood(.pareto, self.x, p);
        return if (std.math.isFinite(ll)) .{ .parameters = p, .log_likelihood = ll } else null;
    }
};

fn paretoProfile(x: []const f64, theta: f64, controls: Controls) Result {
    const problem: ParetoProfile = .{ .x = x, .theta = theta, .maximum = x[x.len - 1] - theta };
    var previous = -@exp(@as(f64, 16));
    var previous_eval = problem.evaluate(previous);
    var best: ?Curve = null;
    var total: usize = 0;
    // Logarithmic coverage on both sides of the exponential limit, and
    // increasingly fine resolution toward the finite upper support endpoint.
    for (0..321) |i| {
        const fi: f64 = @floatFromInt(i);
        const next = if (i < 160) -@exp(16 - (fi + 1) * 0.2) else if (i == 160) @as(f64, 0) else -std.math.expm1(-@exp(-16 + (fi - 160) * 0.12));
        const next_eval = problem.evaluate(next);
        var boundaries = [_]f64{ next, next };
        var count: usize = 1;
        if (previous * next > 0 and previous_eval.score * next_eval.score > 0 and
            previous_eval.slope * previous_eval.score < 0 and next_eval.slope * next_eval.score > 0)
        {
            const turning = problem.turningPoint(previous, next, previous_eval.slope);
            if (problem.evaluate(turning).score * previous_eval.score < 0) {
                boundaries[0] = turning;
                count = 2;
            }
        }
        for (boundaries[0..count]) |bound| {
            const bound_eval = if (bound == next) next_eval else problem.evaluate(bound);
            const lower = previous;
            const fl_start = previous_eval.score;
            previous = bound;
            previous_eval = bound_eval;
            if (fl_start * bound_eval.score >= 0 and bound_eval.score != 0) continue;
            var lo = lower;
            var hi = bound;
            var fl = fl_start;
            var resolved = false;
            for (0..controls.maxiter) |_| {
                total += 1;
                const mid = lo / 2 + hi / 2;
                const fm = problem.evaluate(mid).score;
                if (fm == 0 or hi - lo < controls.tolerance * (1 + @abs(mid))) {
                    lo = mid;
                    hi = mid;
                    resolved = true;
                    break;
                }
                if (fl * fm <= 0) hi = mid else {
                    lo = mid;
                    fl = fm;
                }
            }
            const u = lo / 2 + hi / 2;
            if (problem.curve(u)) |candidate| {
                if (!resolved) return .{ .nonconverged = .{ .reason = .iteration_limit, .best = .{ .parameters = candidate.parameters, .log_likelihood = candidate.log_likelihood, .iterations = total } } };
                const h = @min(1e-4 * (1 + @abs(u)), (1 - u) / 4);
                const left = problem.curve(u - h);
                const right = problem.curve(u + h);
                if (left != null and right != null and candidate.log_likelihood >= left.?.log_likelihood and candidate.log_likelihood >= right.?.log_likelihood and (best == null or candidate.log_likelihood > best.?.log_likelihood)) best = candidate;
            }
        }
    }
    if (best) |*curve| {
        curve.iterations = total;
        return .{ .converged = curve.* };
    }
    // No interior root is not permission to publish an arbitrary endpoint
    // spike. SAS likewise suppresses most no-MLE cases (retained shift probe).
    return fail(.no_local_maximum);
}

fn stationary(problem: Problem, q: [4]f64, axes: []const usize) bool {
    const base = problem.value(q);
    var hess: [4][4]f64 = std.mem.zeroes([4][4]f64);
    var steps: [4]f64 = undefined;
    for (axes, 0..) |axis, i| {
        const h = 1e-4 * (1 + @abs(q[axis]));
        steps[i] = h;
        var plus = q;
        var minus = q;
        plus[axis] += h;
        minus[axis] -= h;
        const vp = problem.value(plus);
        const vm = problem.value(minus);
        const gradient = (vp - vm) / (2 * h);
        if (!std.math.isFinite(gradient) or @abs(gradient) > 1e-4) return false;
        hess[i][i] = (vp - 2 * base + vm) / (h * h);
        for (0..i) |j| {
            const other = axes[j];
            plus[other] += steps[j];
            minus[other] += steps[j];
            const pp = problem.value(plus);
            const mp = problem.value(minus);
            plus[other] -= 2 * steps[j];
            minus[other] -= 2 * steps[j];
            hess[i][j] = (pp - mp - problem.value(plus) + problem.value(minus)) / (4 * h * steps[j]);
            hess[j][i] = hess[i][j];
        }
    }
    // Cholesky rejects saddles and numerically flat infinite-parameter limits.
    for (0..axes.len) |i| {
        for (0..i + 1) |j| {
            var v = hess[i][j];
            for (0..j) |k| v -= hess[i][k] * hess[j][k];
            if (i == j) {
                if (!(v > 1e-10) or !std.math.isFinite(v)) return false;
                hess[i][j] = @sqrt(v);
            } else hess[i][j] = v / hess[j][j];
        }
    }
    return true;
}

test "endpoint affine invariance and explicit unsupported method and budget status" {
    var x: [51]f64 = undefined;
    var y: [51]f64 = undefined;
    for (&x, &y, 0..) |*v, *w, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 51.25;
        v.* = 2 * (std.math.pow(f64, 1 - q, -0.25) - 1) / 0.25;
        w.* = -20 + 7 * v.*;
    }
    const a = fit(.pareto, &x, .{}, .{}).converged;
    const b = fit(.pareto, &y, .{ .theta = -20 }, .{}).converged;
    try std.testing.expectApproxEqAbs(a.parameters.alpha, b.parameters.alpha, 1e-8);
    try std.testing.expectApproxEqAbs(7 * a.parameters.sigma, b.parameters.sigma, 1e-7);
    try std.testing.expectApproxEqAbs(a.log_likelihood - 51 * @log(@as(f64, 7)), b.log_likelihood, 1e-9);
    try std.testing.expectEqual(Reason.unsupported_method, fit(.pareto, &x, .{}, .{ .method = .epm }).nonconverged.reason);
    const limited = fit(.pareto, &x, .{}, .{ .maxiter = 1 });
    try std.testing.expectEqual(Reason.iteration_limit, limited.nonconverged.reason);
    try std.testing.expect(limited.nonconverged.best != null);
    try std.testing.expectEqual(@as(usize, 1), limited.nonconverged.best.?.iterations);
    try std.testing.expectEqual(Reason.invalid_controls, fit(.pareto, &x, .{}, .{ .maxiter = 0 }).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.beta, &.{ 2, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_parameters, fit(.beta, &.{ 0.1, 0.2 }, .{ .sigma = -1 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.pareto, &.{ 1, std.math.nan(f64) }, .{}, .{}).nonconverged.reason);
}

test "endpoint power and beta second shape one share the same likelihood including upper boundary" {
    const x = [_]f64{ 0.1, 0.2, 0.4, 0.8, 1 };
    for ([_]f64{ 0.5, 1, 2, 7 }) |alpha| {
        for ([_]f64{ 1, 1.2, 3 }) |sigma| {
            const p: Parameters = .{ .alpha = alpha, .beta = 1, .sigma = sigma };
            try std.testing.expectEqual(logLikelihood(.power, &x, p), logLikelihood(.beta, &x, p));
        }
    }
    // The likelihood's one-sided boundary extension is not a relaxation of
    // SAS validation for an explicitly supplied endpoint equal to the data.
    try std.testing.expectEqual(Reason.outside_support, fit(.beta, &x, .{ .sigma = 1, .alpha = 2, .beta = 1 }, .{}).nonconverged.reason);
}

test "beta with fixed second shape one reproduces SAS power endpoint fits" {
    // M9 likelihood-equivalence: same observations in original and shifted
    // units. A feasible fixed threshold alone does not ensure a scale estimate.
    for ([_]f64{ 0, 5 }, [_]f64{ 1, 10 }, [_]f64{ 0.00010101010101, 5.00129568411386 }) |offset, width, theta| {
        var x: [41]f64 = undefined;
        for (&x, 1..) |*v, i| {
            const q = (@as(f64, @floatFromInt(i)) - 0.375) / 41.25;
            v.* = offset + width * q * q;
        }
        const location = fit(.beta, &x, .{ .theta = null, .sigma = width, .alpha = 0.5, .beta = 1 }, .{});
        try std.testing.expectEqual(Reason.nonstationary_candidate, location.nonconverged.reason);
        try std.testing.expectApproxEqAbs(theta, location.nonconverged.best.?.parameters.theta, 1e-12);
        const scale = fit(.beta, &x, .{ .theta = offset, .sigma = null, .beta = 1 }, .{});
        if (offset == 0) {
            try std.testing.expectEqual(Reason.nonstationary_candidate, scale.nonconverged.reason);
            const fitted = scale.nonconverged.best.?.parameters;
            try std.testing.expectApproxEqAbs(@as(f64, 0.97169696969696), fitted.sigma, 1e-12);
            try std.testing.expectApproxEqAbs(@as(f64, 0.51716509792299), fitted.alpha, 1e-6);
        } else {
            try std.testing.expectEqual(Reason.initialization_failed, scale.nonconverged.reason);
            try std.testing.expect(scale.nonconverged.best == null);
        }
    }
}

test "endpoint positive Pareto is a reflected power likelihood with analytic scores" {
    const p: Parameters = .{ .theta = -2, .sigma = 7, .alpha = 0.3 };
    const x = [_]f64{ -1, 0, 2, 3, 5 };
    var reflected: [x.len]f64 = undefined;
    const width = p.sigma / p.alpha;
    for (&reflected, x) |*y, v| y.* = p.theta + width - v;
    const power: Parameters = .{ .sigma = width, .alpha = 1 / p.alpha };
    try std.testing.expectApproxEqAbs(logLikelihood(.pareto, &x, p), logLikelihood(.power, &reflected, power), 1e-12);
    // Check the physical scale score against the density, independently of
    // profile coordinates and the optimizer's numerical derivatives.
    var score: f64 = 0;
    for (x) |v| score += -1 / p.sigma + (1 - p.alpha) * (v - p.theta) / (p.sigma * (p.sigma - p.alpha * (v - p.theta)));
    var plus = p;
    var minus = p;
    plus.sigma += 1e-5;
    minus.sigma -= 1e-5;
    const numerical = (logLikelihood(.pareto, &x, plus) - logLikelihood(.pareto, &x, minus)) / 2e-5;
    try std.testing.expectApproxEqAbs(score, numerical, 1e-9);
}

test "endpoint SAS returned fallback curves admit feasible likelihood improvements" {
    var x: [41]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 41.25;
        v.* = q * q;
    }
    // HEX16 ODS values from solver-diagnostics.log, not rounded table text.
    const sas_power: Parameters = .{ .theta = -0.0004709966269561704, .sigma = 0.9716969696969697, .alpha = 0.528649722075328 };
    const original = logLikelihood(.power, &x, sas_power);
    try std.testing.expectEqual(original, logLikelihood(.beta, &x, sas_power));
    var next = sas_power;
    next.theta += 0.1 * (x[0] - sas_power.theta);
    try std.testing.expect(logLikelihood(.power, &x, next) > original);
    next = sas_power;
    next.sigma -= 0.1 * (sas_power.theta + sas_power.sigma - x[x.len - 1]);
    try std.testing.expect(logLikelihood(.power, &x, next) > original);

    const y = [_]f64{ 3, 4, 5, 6, 8, 10, 12, 17 };
    const sas_pareto: Parameters = .{ .sigma = 17.793117455502788, .alpha = 1.0451945031410557 };
    next = sas_pareto;
    next.sigma -= 0.1 * (sas_pareto.sigma - sas_pareto.alpha * y[y.len - 1]);
    try std.testing.expect(std.math.isFinite(logLikelihood(.pareto, &y, next)));
    try std.testing.expect(logLikelihood(.pareto, &y, next) > logLikelihood(.pareto, &y, sas_pareto));
    // This establishes why these oracle curves cannot be used as expected
    // stationary optima. It does NOT waive matching their public output.
}

test "endpoint fixed power scale bypasses the four-moment initializer" {
    const x = [_]f64{ 0.1, 0.2, 0.8 };
    const supplied = fit(.power, &x, .{ .theta = 0, .sigma = 1 }, .{});
    try std.testing.expect(supplied == .converged);
    try std.testing.expectApproxEqAbs(-3 / (@log(@as(f64, 0.1)) + @log(@as(f64, 0.2)) + @log(@as(f64, 0.8))), supplied.converged.parameters.alpha, 1e-12);
    const estimated = fit(.power, &x, .{ .theta = 0 }, .{});
    try std.testing.expectEqual(Reason.initialization_failed, estimated.nonconverged.reason);
    try std.testing.expect(estimated.nonconverged.best == null);
}

test "endpoint fixed-theta power prospective oracle candidate and retained inadmissible-pilot gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rows = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_endpoint_power_dev3_cases.txt"), '\n');
    var matched: usize = 0;
    var unresolved: usize = 0;
    while (rows.next()) |row| {
        if (row[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, row, '|');
        const id = fields.next().?;
        const theta = try std.fmt.parseFloat(f64, fields.next().?);
        const raw_alpha = fields.next().?;
        const alpha = if (std.mem.eql(u8, raw_alpha, "est")) null else try std.fmt.parseFloat(f64, raw_alpha);
        const expected_sigma = fields.next().?;
        const expected_alpha = fields.next().?;
        var samples = std.mem.splitScalar(u8, fields.next().?, ',');
        var x: std.ArrayList(f64) = .empty;
        while (samples.next()) |value| try x.append(arena.allocator(), try std.fmt.parseFloat(f64, value));
        const result = fit(.power, x.items, .{ .theta = theta, .alpha = alpha }, .{});
        try std.testing.expect(result == .nonconverged);
        const got = result.nonconverged;
        if (std.mem.eql(u8, expected_sigma, "est")) {
            try std.testing.expect(got.best == null);
            matched += 1;
            continue;
        }
        if (got.best == null) {
            // This invalid-four-moment/free-alpha case returns a curve in SAS.
            // Keep the mismatch visible, not silently converted to a golden
            // failure or hidden by dropping the row from the oracle corpus.
            try std.testing.expectEqualStrings("initial_edge_04", id);
            try std.testing.expectEqual(Reason.initialization_failed, got.reason);
            unresolved += 1;
            continue;
        }
        try std.testing.expectEqual(Reason.nonstationary_candidate, got.reason);
        const p = got.best.?.parameters;
        try std.testing.expectEqual(theta, p.theta);
        if (alpha) |a| try std.testing.expectEqual(a, p.alpha);
        const sigma = try std.fmt.parseFloat(f64, expected_sigma);
        try std.testing.expectApproxEqAbs(sigma, p.sigma, 1e-10 * (1 + sigma));
        try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, expected_alpha), p.alpha, 5e-5);
        try std.testing.expect(p.sigma > x.items[x.items.len - 1] - theta);
        try std.testing.expect(std.math.isFinite(got.best.?.log_likelihood));
        matched += 1;
    }
    try std.testing.expectEqual(@as(usize, 84), matched);
    try std.testing.expectEqual(@as(usize, 1), unresolved);
}

test "endpoint dev5 fixed-sigma fixed-alpha power location all retained and prospective M9 cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rows = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_endpoint_power_location_dev5.txt"), '\n');
    var returned: usize = 0;
    var absent: usize = 0;
    while (rows.next()) |row| {
        if (row[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, row, '|');
        const id = fields.next().?;
        const sigma = try std.fmt.parseFloat(f64, fields.next().?);
        const alpha = try std.fmt.parseFloat(f64, fields.next().?);
        const expected = fields.next().?;
        const exact = std.mem.eql(u8, fields.next().?, "1");
        var samples = std.mem.splitScalar(u8, fields.next().?, ',');
        var x: std.ArrayList(f64) = .empty;
        while (samples.next()) |value| try x.append(arena.allocator(), try std.fmt.parseFloat(f64, value));
        const result = fit(.power, x.items, .{ .theta = null, .sigma = sigma, .alpha = alpha }, .{});
        errdefer std.debug.print("power location oracle case {s}\n", .{id});
        try std.testing.expect(result == .nonconverged);
        const failure = result.nonconverged;
        if (std.mem.eql(u8, expected, "none")) {
            try std.testing.expectEqual(Reason.initialization_failed, failure.reason);
            try std.testing.expect(failure.best == null);
            absent += 1;
        } else {
            try std.testing.expectEqual(Reason.nonstationary_candidate, failure.reason);
            const curve = failure.best.?;
            const theta = try std.fmt.parseFloat(f64, expected);
            if (exact) try std.testing.expectEqual(theta, curve.parameters.theta) else try std.testing.expectApproxEqAbs(theta, curve.parameters.theta, 1e-12);
            try std.testing.expectEqual(sigma, curve.parameters.sigma);
            try std.testing.expectEqual(alpha, curve.parameters.alpha);
            try std.testing.expectEqual(@as(usize, 0), curve.iterations);
            try std.testing.expect(curve.parameters.theta < x.items[0]);
            try std.testing.expect(curve.parameters.theta + sigma > x.items[x.items.len - 1]);
            try std.testing.expect(std.math.isFinite(curve.log_likelihood));
            returned += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 93), returned);
    try std.testing.expectEqual(@as(usize, 41), absent);
}

test "endpoint dev5 power location preserves validation and nonstationary status" {
    const x = [_]f64{ 0, 0.125, 0.25, 0.5, 1 };
    const fixed: Fixed = .{ .theta = null, .sigma = 1.01, .alpha = 0.125 };
    const got = fit(.power, &x, fixed, .{}).nonconverged;
    try std.testing.expectEqual(Reason.nonstationary_candidate, got.reason);
    const curve = got.best.?;
    var better = curve.parameters;
    better.theta += (x[0] - better.theta) / 2;
    try std.testing.expect(logLikelihood(.power, &x, better) > curve.log_likelihood);
    try std.testing.expectEqual(Reason.outside_support, fit(.power, &x, .{ .theta = null, .sigma = 1, .alpha = 0.125 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.power, &.{ 1, 1, 1, 1 }, fixed, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.power, &.{ 1, 0, 2, 3 }, fixed, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_parameters, fit(.power, &x, .{ .theta = null, .sigma = 2, .alpha = 0 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_controls, fit(.power, &x, fixed, .{ .maxiter = 0 }).nonconverged.reason);
    try std.testing.expectEqual(Reason.unsupported_method, fit(.power, &x, fixed, .{ .method = .epm }).nonconverged.reason);
}

test "beta free scale and first shape retain the fitted lower scale bound" {
    // Retained SAS M9 controlled-grid with the second shape supplied.
    var x: [41]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 41.25;
        v.* = 0.1 * q * q;
    }
    for ([_]f64{ 0.9, 0.99 }, [_]f64{ 0.4914333926, 0.5140115130 }) |beta, alpha| {
        const result = fit(.beta, &x, .{ .theta = 0, .beta = beta }, .{});
        try std.testing.expect(result == .nonconverged);
        try std.testing.expectEqual(Reason.nonstationary_candidate, result.nonconverged.reason);
        const p = result.nonconverged.best.?.parameters;
        try std.testing.expectApproxEqAbs(@as(f64, 0.097421574461495), p.sigma, 2e-15);
        try std.testing.expectApproxEqAbs(alpha, p.alpha, 4e-6);
    }
    // Independent M9 probe: n=9 beta(1.7,2.3), .015-wide support.
    var narrow: [9]f64 = undefined;
    for (&narrow, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.29) / 9.42;
        v.* = 0.015 * f.distQuantile(.beta, q, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 1.7 }, .{ .num = 2.3 } }).?;
    }
    const failed = fit(.beta, &narrow, .{ .theta = 0, .beta = 0.65 }, .{});
    try std.testing.expect(failed == .nonconverged and failed.nonconverged.best == null);
    const interior = fit(.beta, &x, .{ .theta = 0, .beta = 1.1 }, .{});
    try std.testing.expect(interior == .converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.097583568), interior.converged.parameters.sigma, 5e-8);
}

test "M9 joint Pareto estimates and conditional fit presence on seeded draws" {
    const observed = [_]f64{ 0.12, 0.23, 0.31, 0.48, 0.52, 0.76, 0.87, 1.03, 1.29, 1.36, 1.70, 2.28, 2.74, 3.52, 4.85, 6.21 };
    const native: Parameters = .{ .sigma = 1.8684768733855683, .alpha = 0.056857224936872064 };
    try check(native, fit(.pareto, &observed, .{}, .{}), 1e-10);

    // M9 ParameterEstimates from separate PROC fits to RANUNI(817) draws
    // of this fitted distribution. The near-endpoint fit in draw 128 is
    // retained even though the profile root search alone rejected it.
    var state: u64 = 817;
    for (1..129) |rep| {
        var x: [observed.len]f64 = undefined;
        for (&x) |*value| {
            state = (397204094 * state) % 2147483647;
            const uniform = @as(f64, @floatFromInt(state)) / 2147483647;
            value.* = native.sigma * (1 - std.math.pow(f64, uniform, native.alpha)) / native.alpha;
        }
        if (rep != 6 and rep != 7 and rep != 128) continue;
        std.mem.sort(f64, &x, {}, std.sort.asc(f64));
        const fitted = fit(.pareto, &x, .{}, .{});
        switch (rep) {
            6 => try check(.{ .sigma = 1.1329569111780897, .alpha = -0.1650242896286304 }, fitted, 1e-10),
            7 => try std.testing.expect(fitted == .nonconverged and fitted.nonconverged.best == null),
            128 => try std.testing.expect(fitted == .converged),
            else => unreachable,
        }
    }
}

test "Pareto profile isolates the supported local maximum between two adjacent roots" {
    // M9 returned sigma=1.81161316, alpha=0.88998287 for this 16-value sample.
    const x = [_]f64{ 0.17945781591940654, 0.22410221645861458, 0.23281313583046595, 0.29019361215709338, 0.36933287331190595, 0.38257567475311544, 0.40989061974203794, 0.51096190575725786, 0.64809332516627816, 1.0198637278475928, 1.1847242109320089, 1.2059546430497177, 1.2689145725502562, 1.7441018133009203, 1.8494279942521605, 2.0165321863387438 };
    try check(.{ .theta = 0, .sigma = 1.8116131558896376, .alpha = 0.8899828665921032 }, fit(.pareto, &x, .{}, .{}), 3e-5);
}

test "beta scale bound is active for a fixed second shape above one" {
    // SAS M9, n=29 beta(.55,3.2) plotting positions on shifted support.
    // The same scale bound applies to both shapes, with different fitted alpha.
    const theta = -3.75;
    var x: [29]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const u = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 29.25;
        v.* = theta + 0.082 * f.distQuantile(.beta, u, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 0.55 }, .{ .num = 3.2 } }).?;
    }
    for ([_]f64{ 1.03, 1.35 }, [_]f64{ 0.41969434818877055, 0.471445076666332 }) |beta, alpha| {
        const result = fit(.beta, &x, .{ .theta = theta, .beta = beta }, .{});
        try std.testing.expect(result == .nonconverged);
        try std.testing.expectEqual(Reason.nonstationary_candidate, result.nonconverged.reason);
        const p = result.nonconverged.best.?.parameters;
        try std.testing.expectApproxEqAbs(@as(f64, 0.05155409052906523), p.sigma, 1e-10);
        try std.testing.expectApproxEqAbs(alpha, p.alpha, 1.6e-5);
    }
}

test "joint beta scale and shape require convergence in the data units" {
    var x: [31]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 31.25;
        v.* = 0.01 * f.distQuantile(.beta, q, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 2 }, .{ .num = 3 } }).?;
    }
    // M9 suppresses the joint fit but returns the conditional scale on these
    // same observations. At ten times the scale the joint fit also succeeds.
    const absent = fit(.beta, &x, .{ .beta = 1.5 }, .{});
    try std.testing.expect(absent == .nonconverged and absent.nonconverged.best == null);
    const conditional = fit(.beta, &x, .{ .alpha = 1.5, .beta = 1.5 }, .{});
    try std.testing.expect(conditional == .converged);
    for (&x) |*v| v.* *= 10;
    const ordinary = fit(.beta, &x, .{ .beta = 1.5 }, .{});
    try std.testing.expect(ordinary == .converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0837191503604), ordinary.converged.parameters.sigma, 1e-6);
}

test "a higher-curvature beta fit can return after one ridge step" {
    // M9 suppresses the first solution and retains the second. Both have the
    // same normalized observations and the same initial raw scale score (+3).
    var x = [_]f64{ 0.00024324621448663513, 0.0023203177327168786, 0.0037588317287499738, 0.005759822400300694, 0.0066628209350688026, 0.0072065854535222924, 0.0073427548989732439, 0.0085233617709824915, 0.0090611158144312722, 0.010443118349569997, 0.010499253131446321, 0.010548226292403842, 0.010766689567083914, 0.010798034966839622, 0.011086561189288548, 0.011485969022098605, 0.012877047325498145, 0.013909314438639268, 0.015937431860890038 };
    const absent = fit(.beta, &x, .{ .theta = -0.025688868104032762, .beta = 4.4415865084545372 }, .{});
    try std.testing.expect(absent == .nonconverged and absent.nonconverged.best == null);
    for (&x) |*v| v.* *= @sqrt(@as(f64, 1.25 / 8.0));
    const retained = fit(.beta, &x, .{ .theta = -0.010154416715049353, .beta = 4.4406851454131342 }, .{});
    try std.testing.expect(retained == .converged);
}
