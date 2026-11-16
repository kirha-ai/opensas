//! Moments reported with fitted distributions, independent of rendering.
const std = @import("std");
const f = @import("../functions.zig");
const dist = @import("univ_distributions.zig");
const nan = std.math.nan(f64);
pub const Moments = struct { mean: f64, sd: f64, skewness: f64 = nan, kurtosis: f64 = nan, mode: f64 = nan };

pub fn compute(d: dist.Distribution) Moments {
    const p = d.p;
    return switch (d.family) {
        .normal => .{ .mean = p.mu, .sd = p.sigma },
        .exponential => .{ .mean = p.theta + p.sigma, .sd = p.sigma },
        .gamma => .{ .mean = p.theta + p.alpha * p.sigma, .sd = p.sigma * @sqrt(p.alpha) },
        .lognormal => blk: {
            const m = @exp(p.zeta + p.sigma * p.sigma / 2);
            break :blk .{ .mean = p.theta + m, .sd = m * @sqrt(std.math.expm1(p.sigma * p.sigma)) };
        },
        .weibull => blk: {
            const g1 = @exp(f.lgammaOf(1 + 1 / p.c));
            const g2 = @exp(f.lgammaOf(1 + 2 / p.c));
            break :blk .{ .mean = p.theta + p.sigma * g1, .sd = p.sigma * @sqrt(g2 - g1 * g1) };
        },
        .beta, .power => blk: {
            const b = if (d.family == .beta) p.beta else 1;
            const total = p.alpha + b;
            break :blk .{ .mean = p.theta + p.sigma * p.alpha / total, .sd = p.sigma * @sqrt(p.alpha * b / (total * total * (total + 1))) };
        },
        .rayleigh => .{ .mean = p.theta + p.sigma * @sqrt(std.math.pi / 2.0), .sd = p.sigma * @sqrt((4.0 - std.math.pi) / 2.0) },
        .pareto => .{ .mean = if (p.alpha > -1) p.theta + p.sigma / (1 + p.alpha) else nan, .sd = if (p.alpha > -0.5) p.sigma / ((1 + p.alpha) * @sqrt(1 + 2 * p.alpha)) else nan },
        .gumbel => .{ .mean = p.mu + 0.5772156649015329 * p.sigma, .sd = p.sigma * std.math.pi / @sqrt(@as(f64, 6)) },
        .igauss => .{ .mean = p.mu, .sd = @sqrt(p.mu * p.mu * p.mu / p.lambda) },
        .sb, .su => johnson(d),
    };
}

fn logistic(x: f64) f64 {
    return if (x >= 0) 1 / (1 + @exp(-x)) else @exp(x) / (1 + @exp(x));
}

fn johnson(d: dist.Distribution) Moments {
    const p = d.p;
    var raw: [4]f64 = @splat(0);
    if (d.family == .su) {
        // E[sinh(T)^k], T normal(-gamma/delta,1/delta^2), binomial expansion.
        const choose = [_][5]f64{ .{ 1, 1, 0, 0, 0 }, .{ 1, 2, 1, 0, 0 }, .{ 1, 3, 3, 1, 0 }, .{ 1, 4, 6, 4, 1 } };
        for (&raw, 1..) |*moment, k| {
            for (0..k + 1) |j| {
                const power = @as(f64, @floatFromInt(k)) - 2 * @as(f64, @floatFromInt(j));
                const sign: f64 = if (j % 2 == 0) 1 else -1;
                moment.* += sign * choose[k - 1][j] * @exp(-power * p.gamma / p.delta + power * power / (2 * p.delta * p.delta));
            }
            moment.* /= std.math.pow(f64, 2, @floatFromInt(k));
        }
    } else {
        // Integrate bounded powers against the standard-normal density. The
        // omitted mass outside +/-12 is below 4e-33; theta/sigma applied later.
        const intervals = 4096;
        const step = 24.0 / @as(f64, @floatFromInt(intervals));
        for (0..intervals + 1) |i| {
            const z = -12 + step * @as(f64, @floatFromInt(i));
            const weight: f64 = if (i == 0 or i == intervals) 1 else if (i % 2 == 0) 2 else 4;
            const y = logistic((z - p.gamma) / p.delta);
            var power = y;
            for (&raw) |*moment| {
                moment.* += weight * @exp(-z * z / 2) / @sqrt(2 * std.math.pi) * power * step / 3;
                power *= y;
            }
        }
    }
    const mean = raw[0];
    const variance = raw[1] - mean * mean;
    const m3 = raw[2] - 3 * mean * raw[1] + 2 * mean * mean * mean;
    const m4 = raw[3] - 4 * mean * raw[2] + 6 * mean * mean * raw[1] - 3 * std.math.pow(f64, mean, 4);
    return .{ .mean = p.theta + p.sigma * mean, .sd = p.sigma * @sqrt(variance), .skewness = m3 / std.math.pow(f64, variance, 1.5), .kurtosis = m4 / (variance * variance) - 3, .mode = johnsonMode(d) };
}

fn modeScore(d: dist.Distribution, z: f64) f64 {
    const t = (z - d.p.gamma) / d.p.delta;
    return if (d.family == .su) -z - std.math.tanh(t) / d.p.delta else -z + (2 * logistic(t) - 1) / d.p.delta;
}

fn johnsonMode(d: dist.Distribution) f64 {
    var best_log = -std.math.inf(f64);
    var best: f64 = nan;
    var previous = -1 / d.p.delta;
    var score = modeScore(d, previous);
    for (1..257) |i| {
        const next = (-1 + 2 * @as(f64, @floatFromInt(i)) / 256) / d.p.delta;
        const next_score = modeScore(d, next);
        if (score >= 0 and next_score <= 0) {
            var lo = previous;
            var hi = next;
            for (0..80) |_| {
                const mid = lo / 2 + hi / 2;
                if (modeScore(d, mid) > 0) lo = mid else hi = mid;
            }
            const z = lo / 2 + hi / 2;
            const t = (z - d.p.gamma) / d.p.delta;
            const x = d.p.theta + d.p.sigma * (if (d.family == .su) std.math.sinh(t) else logistic(t));
            const ll = d.logPdf(x);
            if (ll > best_log) {
                best_log = ll;
                best = x;
            }
        }
        previous = next;
        score = next_score;
    }
    return best;
}

test "UNIVARIATE Johnson reported moments SAS M9" {
    const sb = compute(.{ .family = .sb, .p = .{ .delta = 1.354119918172094, .gamma = 0.5024580352329555 } });
    try std.testing.expectApproxEqAbs(@as(f64, 0.418029), sb.mean, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.161322), sb.sd, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.253151), sb.skewness, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, -0.52327), sb.kurtosis, 5e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.37608), sb.mode, 5e-6);
    const su = compute(.{ .family = .su, .p = .{ .theta = 2.9214224348414284, .sigma = 1.8376276520385977, .delta = 1.1182614155122592, .gamma = 0.3576266349079934 } });
    try std.testing.expectApproxEqAbs(@as(f64, 2.029824), su.mean, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 2.764539), su.sd, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 2.591597), su.mode, 5e-7);
}
