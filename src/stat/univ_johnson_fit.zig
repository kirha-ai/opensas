//! Johnson support for FEAT-univ-distributions. No parser/render dependencies.
//! Shape convention: Z = gamma + delta * logit((X-theta)/lambda) (SB),
//! or gamma + delta * asinh((X-theta)/lambda) (SU). lambda is SAS SIGMA.
const std = @import("std");
pub const Family = enum { sb, su };
pub const Method = enum { moments, mle };
pub const Parameters = struct { theta: f64, lambda: f64, delta: f64, gamma: f64 };
/// Null means estimated. Caller applies SAS family defaults (SB: theta=0,
/// lambda=1; SU: all estimated) before calling. Fixed values are never starts.
pub const Fixed = struct { theta: ?f64 = null, lambda: ?f64 = null, delta: ?f64 = null, gamma: ?f64 = null };
pub const Iteration = struct { start: usize, iteration: usize, parameters: Parameters, log_likelihood: f64 };
pub const Controls = struct {
    trace_context: ?*anyopaque = null,
    trace: ?*const fn (?*anyopaque, Iteration) void = null,
    optmaxiter: usize = 500,
    optmaxstarts: usize = 100,
    optboundrange: f64 = 100,
    opttolerance: f64 = 1e-8,
    optseed: u64 = 1,
};
pub const Failure = enum { unsupported_combination, invalid_sample, invalid_parameters, invalid_controls, outside_support, no_moment_solution, iteration_limit, no_interior_maximum };
pub const Success = struct { parameters: Parameters, iterations: usize = 0, starts: usize = 0, log_likelihood: ?f64 = null };
/// A valid fallback is a curve, not an established optimum. The adapter must
/// publish its nonconvergence warning alongside it, never relabel it converged.
pub const Nonconvergence = struct { reason: Failure, best: ?Success = null };
pub const Result = union(enum) { converged: Success, nonconverged: Nonconvergence };

const Moments = struct { mean: f64, variance: f64, skew: f64, kurt: f64 };
fn sampleMoments(x: []const f64) Moments {
    const n: f64 = @floatFromInt(x.len);
    var mean: f64 = 0;
    for (x) |v| mean += v / n;
    var m2: f64 = 0;
    var m3: f64 = 0;
    var m4: f64 = 0;
    for (x) |v| {
        const a = v - mean;
        m2 += a * a;
        m3 += a * a * a;
        m4 += a * a * a * a;
    }
    const variance = m2 / (n - 1);
    return .{ .mean = mean, .variance = variance, .skew = n * m3 / ((n - 1) * (n - 2) * std.math.pow(f64, variance, 1.5)), .kurt = n * (n + 1) * m4 / ((n - 1) * (n - 2) * (n - 3) * variance * variance) - 3 * (n - 1) * (n - 1) / ((n - 2) * (n - 3)) };
}

/// Integrate central moments directly to avoid subtracting almost equal raw
/// moments near a normal limit. Simpson integration of the normal transform;
/// refinement agreement is checked before exposing a fitted SB curve.
fn population(family: Family, delta: f64, gamma: f64, steps: usize) Moments {
    const h = 20 / @as(f64, @floatFromInt(steps));
    var mean: f64 = 0;
    for (0..steps + 1) |i| {
        const z = -10 + h * @as(f64, @floatFromInt(i));
        const w = @exp(-z * z / 2) / @sqrt(2 * std.math.pi) * h / 3 * @as(f64, if (i == 0 or i == steps) 1 else if (i % 2 == 0) 2 else 4);
        const y = if (family == .sb) 1 / (1 + @exp((gamma - z) / delta)) else std.math.sinh((z - gamma) / delta);
        mean += w * y;
    }
    var m2: f64 = 0;
    var m3: f64 = 0;
    var m4: f64 = 0;
    for (0..steps + 1) |i| {
        const z = -10 + h * @as(f64, @floatFromInt(i));
        const w = @exp(-z * z / 2) / @sqrt(2 * std.math.pi) * h / 3 * @as(f64, if (i == 0 or i == steps) 1 else if (i % 2 == 0) 2 else 4);
        const y = (if (family == .sb) 1 / (1 + @exp((gamma - z) / delta)) else std.math.sinh((z - gamma) / delta)) - mean;
        m2 += w * y * y;
        m3 += w * y * y * y;
        m4 += w * y * y * y * y;
    }
    return .{ .mean = mean, .variance = m2, .skew = m3 / std.math.pow(f64, m2, 1.5), .kurt = m4 / (m2 * m2) - 3 };
}

fn shapeMoments(family: Family, delta: f64, gamma: f64) Moments {
    if (family == .sb) return population(family, delta, gamma, 512);
    // Exact SU central moments (normal exponential moments), expressed in
    // hyperbolic functions to retain precision at small skewness.
    const w = @exp(1 / (delta * delta));
    const a = -gamma / delta;
    const w2 = w * w;
    const variance = (w - 1) * (w * std.math.cosh(2 * a) + 1) / 2;
    const m3 = @sqrt(w) * (w - 1) * (w - 1) * (w * (w + 2) * std.math.sinh(3 * a) + 3 * std.math.sinh(a)) / 4;
    const m4 = (w - 1) * (w - 1) / 8 * (w2 * (w2 * w2 + 2 * w2 * w + 3 * w2 - 3) * std.math.cosh(4 * a) + 4 * w2 * (w + 2) * std.math.cosh(2 * a) + 3 * (2 * w + 1));
    return .{ .mean = @sqrt(w) * std.math.sinh(a), .variance = variance, .skew = m3 / std.math.pow(f64, variance, 1.5), .kurt = m4 / (variance * variance) - 3 };
}

fn residual(family: Family, q: [2]f64, target: Moments) [2]f64 {
    const m = shapeMoments(family, @exp(q[0]), q[1]);
    return .{ (m.skew - target.skew) / (1 + @abs(target.skew)), (m.kurt - target.kurt) / (1 + @abs(target.kurt)) };
}
fn norm(r: [2]f64) f64 {
    if (!std.math.isFinite(r[0]) or !std.math.isFinite(r[1])) return std.math.inf(f64);
    return @max(@abs(r[0]), @abs(r[1]));
}

fn momentFit(family: Family, x: []const f64, fixed: Fixed) Result {
    if (x.len < 4) return .{ .nonconverged = .{ .reason = .invalid_sample } };
    const target = sampleMoments(x);
    // Multiple shape starts are needed near the lognormal dividing curve.
    for ([_]f64{ 0.5, 1, 2, 4, 8 }) |delta0| {
        var q: [2]f64 = .{ @log(delta0), if (family == .sb) target.skew else -target.skew };
        for (0..100) |iter| {
            const r = residual(family, q, target);
            if (norm(r) < 1e-10) {
                const delta = @exp(q[0]);
                const m = shapeMoments(family, delta, q[1]);
                if (family == .sb) {
                    const refined = population(family, delta, q[1], 2048);
                    if (@abs(refined.skew - m.skew) > 1e-8 or @abs(refined.kurt - m.kurt) > 1e-8) break;
                }
                const lambda = @sqrt(target.variance / m.variance);
                const p: Parameters = .{ .theta = fixed.theta orelse (target.mean - lambda * m.mean), .lambda = fixed.lambda orelse lambda, .delta = fixed.delta orelse delta, .gamma = fixed.gamma orelse q[1] };
                if (!supported(family, x, p)) return .{ .nonconverged = .{ .reason = .outside_support } };
                return .{ .converged = .{ .parameters = p, .iterations = iter + 1 } };
            }
            var jac: [2][2]f64 = undefined;
            for (0..2) |j| {
                var plus = q;
                var minus = q;
                const h = 1e-5 * (1 + @abs(q[j]));
                plus[j] += h;
                minus[j] -= h;
                const rp = residual(family, plus, target);
                const rm = residual(family, minus, target);
                for (0..2) |k| jac[k][j] = (rp[k] - rm[k]) / (2 * h);
            }
            const det = jac[0][0] * jac[1][1] - jac[0][1] * jac[1][0];
            if (!std.math.isFinite(det) or @abs(det) < 1e-16) break;
            const step: [2]f64 = .{ (jac[1][1] * r[0] - jac[0][1] * r[1]) / det, (jac[0][0] * r[1] - jac[1][0] * r[0]) / det };
            var rate: f64 = 1;
            var accepted = false;
            for (0..24) |_| {
                const next: [2]f64 = .{ q[0] - rate * step[0], q[1] - rate * step[1] };
                if (@abs(next[0]) < 8 and @abs(next[1]) < 100 and norm(residual(family, next, target)) < norm(r)) {
                    q = next;
                    accepted = true;
                    break;
                }
                rate *= 0.5;
            }
            if (!accepted) break;
        }
    }
    return .{ .nonconverged = .{ .reason = .no_moment_solution } };
}

fn supported(family: Family, x: []const f64, p: Parameters) bool {
    if (!std.math.isFinite(p.theta) or !std.math.isFinite(p.lambda) or !std.math.isFinite(p.delta) or !std.math.isFinite(p.gamma) or p.lambda <= 0 or p.delta <= 0) return false;
    if (family == .sb) for (x) |v| {
        if (v <= p.theta or v >= p.theta + p.lambda) return false;
    };
    return true;
}

/// Conditional likelihood: solve the normal location/scale score equations
/// exactly for free gamma/delta. This also covers either shape held fixed.
fn conditional(family: Family, x: []const f64, fixed: Fixed, theta: f64, lambda: f64) ?Success {
    if (!(lambda > 0) or !std.math.isFinite(lambda)) return null;
    const n: f64 = @floatFromInt(x.len);
    var tmean: f64 = 0;
    var t2: f64 = 0;
    var jac: f64 = 0;
    for (x) |v| {
        const y = (v - theta) / lambda;
        if (family == .sb and !(y > 0 and y < 1)) return null;
        const t = if (family == .sb) @log(y) - std.math.log1p(-y) else std.math.asinh(y);
        tmean += t / n;
        t2 += t * t / n;
        jac += if (family == .sb) -@log(lambda) - @log(y) - std.math.log1p(-y) else -@log(lambda) - 0.5 * std.math.log1p(y * y);
    }
    var variance: f64 = 0;
    for (x) |v| {
        const y = (v - theta) / lambda;
        const t = if (family == .sb) @log(y) - std.math.log1p(-y) else std.math.asinh(y);
        variance += (t - tmean) * (t - tmean) / n;
    }
    const delta = fixed.delta orelse (if (fixed.gamma) |g| (if (g * tmean >= 0) 2 / (@sqrt(g * g * tmean * tmean + 4 * t2) + g * tmean) else (@sqrt(g * g * tmean * tmean + 4 * t2) - g * tmean) / (2 * t2)) else 1 / @sqrt(variance));
    const gamma = fixed.gamma orelse -delta * tmean;
    const p: Parameters = .{ .theta = theta, .lambda = lambda, .delta = delta, .gamma = gamma };
    if (!supported(family, x, p)) return null;
    const ll = n * (@log(delta) - 0.5 * @log(2 * std.math.pi) - 0.5 * ((gamma + delta * tmean) * (gamma + delta * tmean) + delta * delta * variance)) + jac;
    if (!std.math.isFinite(ll)) return null;
    return .{ .parameters = p, .log_likelihood = ll };
}

pub fn fit(family: Family, method: Method, x: []const f64, fixed: Fixed, controls: Controls) Result {
    if (x.len < 2) return .{ .nonconverged = .{ .reason = .invalid_sample } };
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return .{ .nonconverged = .{ .reason = .invalid_sample } };
    inline for (std.meta.fields(Fixed)) |field| {
        if (@field(fixed, field.name)) |v| if (!std.math.isFinite(v)) return .{ .nonconverged = .{ .reason = .invalid_parameters } };
    }
    if ((fixed.lambda != null and fixed.lambda.? <= 0) or (fixed.delta != null and fixed.delta.? <= 0)) return .{ .nonconverged = .{ .reason = .invalid_parameters } };
    if (controls.optmaxiter == 0 or controls.optmaxstarts == 0 or !(controls.opttolerance > 0) or !std.math.isFinite(controls.opttolerance) or !(controls.optboundrange > 0) or !std.math.isFinite(controls.optboundrange) or controls.optseed == 0) return .{ .nonconverged = .{ .reason = .invalid_controls } };
    if (fixed.theta != null and fixed.lambda != null and fixed.delta != null and fixed.gamma != null) {
        const p: Parameters = .{ .theta = fixed.theta.?, .lambda = fixed.lambda.?, .delta = fixed.delta.?, .gamma = fixed.gamma.? };
        return if (supported(family, x, p)) .{ .converged = .{ .parameters = p } } else .{ .nonconverged = .{ .reason = .outside_support } };
    }
    if (x[0] == x[x.len - 1]) return .{ .nonconverged = .{ .reason = .invalid_sample } };
    if (family == .sb) {
        if (fixed.delta != null or fixed.gamma != null or (fixed.theta == null and fixed.lambda != null)) return .{ .nonconverged = .{ .reason = .unsupported_combination } };
        if (method == .mle and (fixed.theta == null or fixed.lambda == null)) return .{ .nonconverged = .{ .reason = .unsupported_combination } };
    }
    if (family == .su and method == .moments and (fixed.theta != null or fixed.lambda != null or fixed.delta != null or fixed.gamma != null)) return .{ .nonconverged = .{ .reason = .unsupported_combination } };
    if (method == .moments) return momentFit(family, x, fixed);
    if (fixed.theta != null and fixed.lambda != null) return if (conditional(family, x, fixed, fixed.theta.?, fixed.lambda.?)) |s| .{ .converged = s } else .{ .nonconverged = .{ .reason = .outside_support } };
    return mleFit(family, x, fixed, controls);
}

fn percentile(x: []const f64, p: f64) f64 {
    const rank = p * @as(f64, @floatFromInt(x.len));
    const i: usize = @intFromFloat(rank);
    if (i == 0) return x[0];
    if (i >= x.len) return x[x.len - 1];
    return if (rank == @floor(rank)) (x[i - 1] + x[i]) / 2 else x[i];
}
fn percentileStart(x: []const f64) ?Parameters {
    // Phi(-3*.524), Phi(-.524), Phi(.524), Phi(3*.524).
    const a = percentile(x, 0.05797527560823886);
    const b = percentile(x, 0.300139269931611);
    const c = percentile(x, 0.699860730068389);
    const d = percentile(x, 0.9420247243917611);
    const n = b - a;
    const m = d - c;
    const p = c - b;
    if (!(n > 0 and m > 0 and p > 0) or n * m / (p * p) <= 1.01) return null;
    const delta = 1.048 / std.math.acosh((m + n) / (2 * p));
    const gamma = delta * std.math.atanh((n - m) / (2 * p * std.math.sinh(1.048 / delta)));
    const lambda = p / (2 * std.math.cosh(gamma / delta) * std.math.sinh(0.524 / delta));
    return .{ .theta = (b + c) / 2 + lambda * std.math.sinh(gamma / delta) * std.math.cosh(0.524 / delta), .lambda = lambda, .delta = delta, .gamma = gamma };
}

const Profile = struct {
    family: Family,
    x: []const f64,
    fixed: Fixed,
    center: f64,
    scale: f64,
    fn evaluate(self: Profile, q: [2]f64) ?Success {
        return conditional(self.family, self.x, self.fixed, self.fixed.theta orelse (self.center + self.scale * q[0]), self.fixed.lambda orelse (self.scale * @exp(q[1])));
    }
    fn value(self: Profile, q: [2]f64) f64 {
        const s = self.evaluate(q) orelse return std.math.inf(f64);
        return -s.log_likelihood.? / @as(f64, @floatFromInt(self.x.len));
    }
};

fn mleFit(family: Family, x: []const f64, fixed: Fixed, controls: Controls) Result {
    const sm = sampleMoments(x);
    const profile: Profile = .{ .family = family, .x = x, .fixed = fixed, .center = sm.mean, .scale = @sqrt(sm.variance) };
    const initial = percentileStart(x) orelse Parameters{ .theta = sm.mean, .lambda = @sqrt(sm.variance), .delta = 1, .gamma = 0 };
    const origin: [2]f64 = .{ (initial.theta - sm.mean) / profile.scale, @log(initial.lambda / profile.scale) };
    var rng = std.Random.DefaultPrng.init(controls.optseed);
    var best: ?Success = null;
    var fallback: ?Success = null;
    var limited = false;
    var total: usize = 0;
    for (0..controls.optmaxstarts) |start| {
        var q = origin;
        if (start != 0) {
            // Positive scales use log coordinates. Seeded starts explore the
            // documented range around the percentile starting estimate.
            q[0] += (2 * rng.random().float(f64) - 1) * controls.optboundrange * initial.lambda / profile.scale;
            q[1] += (2 * rng.random().float(f64) - 1) * @log(1 + controls.optboundrange);
        }
        var converged = false;
        for (0..controls.optmaxiter) |iteration| {
            total += 1;
            const value = profile.value(q);
            if (!std.math.isFinite(value)) break;
            const valid = profile.evaluate(q).?;
            if (fallback == null or valid.log_likelihood.? > fallback.?.log_likelihood.?) fallback = valid;
            if (controls.trace) |trace| {
                const current = profile.evaluate(q).?;
                trace(controls.trace_context, .{ .start = start + 1, .iteration = iteration + 1, .parameters = current.parameters, .log_likelihood = current.log_likelihood.? });
            }
            var grad = [_]f64{ 0, 0 };
            var hess = [_][2]f64{ .{ 1, 0 }, .{ 0, 1 } };
            const free = [_]bool{ fixed.theta == null, fixed.lambda == null };
            const h = [_]f64{ 1e-4 * (1 + @abs(q[0])), 1e-4 * (1 + @abs(q[1])) };
            for (0..2) |j| {
                if (!free[j]) continue;
                var plus = q;
                var minus = q;
                plus[j] += h[j];
                minus[j] -= h[j];
                const vp = profile.value(plus);
                const vm = profile.value(minus);
                plus[j] += h[j];
                minus[j] -= h[j];
                grad[j] = (-profile.value(plus) + 8 * vp - 8 * vm + profile.value(minus)) / (12 * h[j]);
                hess[j][j] = (vp - 2 * value + vm) / (h[j] * h[j]);
            }
            if (free[0] and free[1]) {
                hess[0][1] = (profile.value(.{ q[0] + h[0], q[1] + h[1] }) - profile.value(.{ q[0] + h[0], q[1] - h[1] }) - profile.value(.{ q[0] - h[0], q[1] + h[1] }) + profile.value(.{ q[0] - h[0], q[1] - h[1] })) / (4 * h[0] * h[1]);
                hess[1][0] = hess[0][1];
            }
            const det = hess[0][0] * hess[1][1] - hess[0][1] * hess[1][0];
            // An interior maximum requires positive profile curvature, not
            // just small changes along a divergent normal/lognormal limit.
            if (norm(grad) <= controls.opttolerance and hess[0][0] > 1e-9 and hess[1][1] > 1e-9 and det > 1e-10) {
                converged = true;
                break;
            }
            var step = grad;
            if (hess[0][0] > 0 and hess[1][1] > 0 and det > 1e-10) {
                step = .{ (hess[1][1] * grad[0] - hess[0][1] * grad[1]) / det, (hess[0][0] * grad[1] - hess[1][0] * grad[0]) / det };
            }
            const cap = @max(@as(f64, 1), norm(step));
            for (&step) |*v| v.* /= cap;
            var rate: f64 = 1;
            var accepted = false;
            for (0..30) |_| {
                const next: [2]f64 = .{ q[0] - rate * step[0], q[1] - rate * step[1] };
                if (profile.value(next) < value - 1e-4 * rate * (grad[0] * step[0] + grad[1] * step[1])) {
                    q = next;
                    accepted = true;
                    break;
                }
                rate /= 2;
            }
            if (!accepted) break;
            if (iteration + 1 == controls.optmaxiter) limited = true;
        }
        // Include the last accepted step even when its iteration used the
        // remaining budget; never preserve an invalid trial from line search.
        if (profile.evaluate(q)) |valid| {
            if (fallback == null or valid.log_likelihood.? > fallback.?.log_likelihood.?) fallback = valid;
        }
        if (converged) {
            const candidate = profile.evaluate(q).?;
            if (best == null or candidate.log_likelihood.? > best.?.log_likelihood.?) best = candidate;
        }
    }
    if (best) |*s| {
        // A stopped start can beat a converged local optimum. Preserve the
        // better curve and its unresolved status instead of hiding it behind
        // a worse optimum from another start.
        if (fallback == null or fallback.?.log_likelihood.? <= s.log_likelihood.? + controls.opttolerance * @as(f64, @floatFromInt(x.len))) {
            s.iterations = total;
            s.starts = controls.optmaxstarts;
            return .{ .converged = s.* };
        }
    }
    if (fallback) |*s| {
        s.iterations = total;
        s.starts = controls.optmaxstarts;
    }
    return .{ .nonconverged = .{ .reason = if (limited) .iteration_limit else .no_interior_maximum, .best = fallback } };
}

test "Johnson SU analytic moments agree with independent normal quadrature" {
    for ([_]f64{ 0.8, 1.2, 2, 5 }) |delta| {
        for ([_]f64{ -0.8, 0, 0.6 }) |gamma| {
            const exact = shapeMoments(.su, delta, gamma);
            const numerical = population(.su, delta, gamma, 4096);
            try std.testing.expectApproxEqRel(exact.variance, numerical.variance, 1e-10);
            try std.testing.expectApproxEqAbs(exact.skew, numerical.skew, 1e-8);
            try std.testing.expectApproxEqRel(exact.kurt, numerical.kurt, 2e-6);
        }
    }
}

fn oracleSample(family: Family) [101]f64 {
    var x: [101]f64 = undefined;
    var lines = std.mem.tokenizeScalar(u8, @embedFile("univ_johnson_dev3_scores.csv"), '\n');
    for (&x) |*v| {
        const z = std.fmt.parseFloat(f64, lines.next().?) catch unreachable;
        v.* = if (family == .sb) 1 / (1 + @exp((0.4 - z) / 1.2)) else 3 + 2 * std.math.sinh((z - 0.4) / 1.2);
    }
    return x;
}
fn checkParameters(expected: Parameters, result: Result, tolerance: f64) !void {
    if (result != .converged) {
        std.debug.print("Johnson failed: {s}\n", .{@tagName(result.nonconverged.reason)});
        return error.TestUnexpectedResult;
    }
    inline for (std.meta.fields(Parameters)) |field| {
        try std.testing.expectApproxEqAbs(@field(expected, field.name), @field(result.converged.parameters, field.name), tolerance);
    }
}

test "Johnson MOMENTS SAS M9 corrected sample moments and endpoint replacement" {
    const b = oracleSample(.sb);
    const u = oracleSample(.su);
    try checkParameters(.{ .theta = 0.005489, .lambda = 0.982055, .delta = 1.177443, .gamma = 0.382718 }, fit(.sb, .moments, &b, .{}, .{}), 7e-7);
    try checkParameters(.{ .theta = 0, .lambda = 1, .delta = 1.177443, .gamma = 0.382718 }, fit(.sb, .moments, &b, .{ .theta = 0, .lambda = 1 }, .{}), 7e-7);
    try checkParameters(.{ .theta = 0, .lambda = 0.982055, .delta = 1.177443, .gamma = 0.382718 }, fit(.sb, .moments, &b, .{ .theta = 0 }, .{}), 7e-7);
    try checkParameters(.{ .theta = 4.17255, .lambda = 3.455171, .delta = 1.885994, .gamma = 0.962658 }, fit(.su, .moments, &u, .{}, .{}), 6e-6);
}

test "Johnson MLE SAS M9 conditional shapes and unrestricted SU" {
    const b = oracleSample(.sb);
    const u = oracleSample(.su);
    try checkParameters(.{ .theta = 0, .lambda = 1, .delta = 1.219036, .gamma = 0.406345 }, fit(.sb, .mle, &b, .{ .theta = 0, .lambda = 1 }, .{}), 6e-7);
    try checkParameters(.{ .theta = 3, .lambda = 2, .delta = 1.219036, .gamma = 0.406345 }, fit(.su, .mle, &u, .{ .theta = 3, .lambda = 2 }, .{}), 6e-7);
    try checkParameters(.{ .theta = 3, .lambda = 2, .delta = 2, .gamma = 0.666667 }, fit(.su, .mle, &u, .{ .theta = 3, .lambda = 2, .delta = 2 }, .{}), 6e-7);
    try checkParameters(.{ .theta = 3.09919, .lambda = 2.220152, .delta = 1.314593, .gamma = 0.455041 }, fit(.su, .mle, &u, .{}, .{ .optseed = 123, .optmaxstarts = 8 }), 2e-5);
}

test "Johnson invalid samples, support endpoints and SAS unsupported combinations stay tagged" {
    const b = oracleSample(.sb);
    const u = oracleSample(.su);
    try std.testing.expectEqual(Failure.unsupported_combination, fit(.sb, .mle, &b, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.unsupported_combination, fit(.sb, .mle, &b, .{ .theta = 0, .lambda = 1, .delta = 2 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.unsupported_combination, fit(.su, .moments, &u, .{ .theta = 3 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.outside_support, fit(.sb, .mle, &.{ 0, 0.5, 1 }, .{ .theta = 0, .lambda = 1 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.invalid_sample, fit(.su, .moments, &.{ 1, 1, 1, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.invalid_sample, fit(.su, .mle, &.{ 2, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Failure.invalid_controls, fit(.su, .mle, &u, .{}, .{ .optmaxiter = 0 }).nonconverged.reason);
    try std.testing.expectEqual(Failure.iteration_limit, fit(.su, .mle, &u, .{}, .{ .optmaxiter = 1, .optmaxstarts = 1 }).nonconverged.reason);
}

test "Johnson heldout SAS M9 opposite skew and conditional endpoint fits" {
    var b: [77]f64 = undefined;
    var u: [77]f64 = undefined;
    var lines = std.mem.tokenizeScalar(u8, @embedFile("univ_johnson_dev3_heldout_scores.csv"), '\n');
    for (&b, &u) |*bv, *uv| {
        const z = try std.fmt.parseFloat(f64, lines.next().?);
        bv.* = -2 + 5 / (1 + @exp((-0.7 - z) / 0.8));
        uv.* = -4 + 1.5 * std.math.sinh((z + 0.65) / 0.9);
    }
    try checkParameters(.{ .theta = -2.00445, .lambda = 5.010861, .delta = 0.803561, .gamma = -0.70178 }, fit(.sb, .moments, &b, .{}, .{}), 5e-5);
    try checkParameters(.{ .theta = -2, .lambda = 5, .delta = 0.816062, .gamma = -0.71405 }, fit(.sb, .mle, &b, .{ .theta = -2, .lambda = 5 }, .{}), 6e-6);
    try std.testing.expectEqual(Failure.no_moment_solution, fit(.su, .moments, &u, .{}, .{}).nonconverged.reason);
    const controls: Controls = .{ .optseed = 321, .optmaxstarts = 10 };
    try checkParameters(.{ .theta = -3.99631, .lambda = 1.478673, .delta = 0.9, .gamma = -0.65 }, fit(.su, .mle, &u, .{ .delta = 0.9, .gamma = -0.65 }, controls), 3e-5);
    try checkParameters(.{ .theta = -4.01707, .lambda = 1.471514, .delta = 0.9, .gamma = -0.6635 }, fit(.su, .mle, &u, .{ .delta = 0.9 }, controls), 3e-5);
    try checkParameters(.{ .theta = -4.00661, .lambda = 1.5976, .delta = 0.945017, .gamma = -0.65 }, fit(.su, .mle, &u, .{ .gamma = -0.65 }, controls), 3e-5);
    try checkParameters(.{ .theta = -4.11589, .lambda = 1.625806, .delta = 0.969355, .gamma = -0.71541 }, fit(.su, .mle, &u, .{}, controls), 3e-5);
    try checkParameters(.{ .theta = -4, .lambda = 1.592326, .delta = 0.946429, .gamma = -0.66147 }, fit(.su, .mle, &u, .{ .theta = -4 }, controls), 3e-5);
    try checkParameters(.{ .theta = -4.07354, .lambda = 1.5, .delta = 0.926071, .gamma = -0.69808 }, fit(.su, .mle, &u, .{ .lambda = 1.5 }, controls), 3e-5);
    try checkParameters(.{ .theta = -4, .lambda = 1.5, .delta = 0.914818, .gamma = -0.65 }, fit(.su, .mle, &u, .{ .theta = -4, .lambda = 1.5, .gamma = -0.65 }, controls), 6e-6);
}

test "Johnson symmetric moments, strict optimizer controls and normal-limit failure" {
    var b: [51]f64 = undefined;
    var u: [51]f64 = undefined;
    var z: [51]f64 = undefined;
    var lines = std.mem.tokenizeScalar(u8, @embedFile("univ_johnson_dev3_boundary_scores.csv"), '\n');
    for (&b, &u, &z) |*bv, *uv, *zv| {
        zv.* = try std.fmt.parseFloat(f64, lines.next().?);
        bv.* = 1 / (1 + @exp(-zv.* / 0.7));
        uv.* = 2 * std.math.sinh(zv.* / 1.1);
    }
    try checkParameters(.{ .theta = -0.00101, .lambda = 1.002028, .delta = 0.698438, .gamma = 0 }, fit(.sb, .moments, &b, .{}, .{}), 6e-6);
    try checkParameters(.{ .theta = 0, .lambda = 4.011827, .delta = 1.837622, .gamma = 0 }, fit(.su, .moments, &u, .{}, .{}), 6e-6);
    try std.testing.expectEqual(Failure.no_moment_solution, fit(.su, .moments, &z, .{}, .{}).nonconverged.reason);
    try std.testing.expect(fit(.su, .mle, &z, .{}, .{ .optmaxstarts = 1, .optseed = 42 }) == .nonconverged);
    try checkParameters(.{ .theta = 0, .lambda = 2.403494, .delta = 1.281552, .gamma = 0 }, fit(.su, .mle, &u, .{}, .{ .optmaxstarts = 1, .optboundrange = 2, .opttolerance = 1e-10, .optseed = 42 }), 6e-6);
}

test "Johnson seeded starts and trace honor iteration budget without labelling fallback converged" {
    const Trace = struct {
        count: usize = 0,
        digest: f64 = 0,
        fn record(context: ?*anyopaque, row: Iteration) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.count += 1;
            self.digest += row.parameters.theta + row.parameters.lambda + row.log_likelihood;
        }
    };
    var a: Trace = .{};
    var b: Trace = .{};
    const x = oracleSample(.su);
    var options: Controls = .{ .optmaxiter = 1, .optmaxstarts = 3, .optboundrange = 2, .optseed = 42, .trace = Trace.record, .trace_context = &a };
    try std.testing.expect(fit(.su, .mle, &x, .{}, options) == .nonconverged);
    options.trace_context = &b;
    try std.testing.expect(fit(.su, .mle, &x, .{}, options) == .nonconverged);
    try std.testing.expectEqual(@as(usize, 3), a.count);
    try std.testing.expectEqual(a.count, b.count);
    try std.testing.expectEqual(a.digest, b.digest);
    b = .{};
    options.optseed = 43;
    _ = fit(.su, .mle, &x, .{}, options);
    try std.testing.expect(a.digest != b.digest);
    const fixed: Fixed = .{ .theta = 0, .lambda = 1, .delta = 1, .gamma = 0 };
    try std.testing.expect(fit(.sb, .mle, &.{ 0.5, 0.5 }, fixed, .{}) == .converged);
}

test "Johnson fits preserve affine transformations and fixed parameter identity" {
    const original = oracleSample(.su);
    var shifted: [101]f64 = undefined;
    for (&shifted, original) |*v, x| v.* = 10000 + 100 * x;
    inline for (.{ Method.moments, Method.mle }) |method| {
        const controls: Controls = .{ .optmaxstarts = 1 };
        const p = fit(.su, method, &original, .{}, controls).converged.parameters;
        const transformed: Parameters = .{ .theta = 10000 + 100 * p.theta, .lambda = 100 * p.lambda, .delta = p.delta, .gamma = p.gamma };
        try checkParameters(transformed, fit(.su, method, &shifted, .{}, controls), 2e-4);
    }
    const options: Fixed = .{ .theta = 10300, .lambda = 200, .gamma = 0.4 };
    const p = fit(.su, .mle, &shifted, options, .{}).converged.parameters;
    try std.testing.expectEqual(options.theta.?, p.theta);
    try std.testing.expectEqual(options.lambda.?, p.lambda);
    try std.testing.expectEqual(options.gamma.?, p.gamma);
}

test "Johnson SAS IterLimit keeps a valid explicitly nonconverged curve and fixed values" {
    var x: [51]f64 = undefined;
    var z: [51]f64 = undefined;
    var lines = std.mem.tokenizeScalar(u8, @embedFile("univ_johnson_dev3_boundary_scores.csv"), '\n');
    for (&x, &z) |*v, *score| {
        score.* = try std.fmt.parseFloat(f64, lines.next().?);
        v.* = 2 * std.math.sinh(score.* / 1.1);
    }
    const Objective = struct {
        // Direct observation-wise density calculation, independent of the
        // optimizer's profiled sufficient-statistic likelihood calculation.
        fn value(sample: []const f64, p: Parameters) f64 {
            var sum: f64 = 0;
            for (sample) |v| {
                const y = (v - p.theta) / p.lambda;
                const normal = p.gamma + p.delta * std.math.asinh(y);
                sum += @log(p.delta / p.lambda) - 0.5 * @log(2 * std.math.pi * (1 + y * y)) - normal * normal / 2;
            }
            return sum;
        }
    };
    // boundaries.log: IterLimit, zero local optima, but a returned curve.
    // Its printed parameter vector is a lower bound, not a demand that our
    // different local solver reproduce SAS's one-step trajectory.
    const sas_fallback: Parameters = .{ .theta = 0, .lambda = 1.653148, .delta = 0.94738, .gamma = 0 };
    for ([_]Fixed{ .{}, .{ .theta = 0 }, .{ .gamma = 0 }, .{ .delta = 1.1 } }) |fixed| {
        const result = fit(.su, .mle, &x, fixed, .{ .optseed = 42, .optmaxstarts = 1, .optmaxiter = 1 });
        try std.testing.expect(result == .nonconverged);
        try std.testing.expectEqual(Failure.iteration_limit, result.nonconverged.reason);
        const candidate = result.nonconverged.best.?;
        try std.testing.expect(supported(.su, &x, candidate.parameters));
        try std.testing.expectApproxEqAbs(Objective.value(&x, candidate.parameters), candidate.log_likelihood.?, 1e-10);
        if (fixed.delta == null) try std.testing.expect(candidate.log_likelihood.? >= Objective.value(&x, sas_fallback) - 1e-4);
        inline for (std.meta.fields(Fixed)) |field| {
            if (@field(fixed, field.name)) |v| try std.testing.expectEqual(v, @field(candidate.parameters, field.name));
        }
        try std.testing.expectEqual(@as(usize, 1), candidate.iterations);
        try std.testing.expectEqual(@as(usize, 1), candidate.starts);
    }
    const normal_limit = fit(.su, .mle, &z, .{}, .{ .optseed = 42, .optmaxstarts = 1 });
    try std.testing.expect(normal_limit == .nonconverged);
    try std.testing.expect(supported(.su, &z, normal_limit.nonconverged.best.?.parameters));
    try std.testing.expect(std.math.isFinite(normal_limit.nonconverged.best.?.log_likelihood.?));
    const invalid = fit(.sb, .mle, &.{ 0, 0.5, 1 }, .{ .theta = 0, .lambda = 1 }, .{});
    try std.testing.expectEqual(Failure.outside_support, invalid.nonconverged.reason);
    try std.testing.expect(invalid.nonconverged.best == null);
}
