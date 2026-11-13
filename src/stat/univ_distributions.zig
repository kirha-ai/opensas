//! Numerical distribution contract for UNIVARIATE. No rendering or ODS state.
//! SAS Statistical Procedures pp.431–459. Parameters use SAS names, not the
//! conventions of an external statistics library.
const std = @import("std");
const f = @import("../functions.zig");
const diag = @import("../diag.zig");
const inf = std.math.inf(f64);
pub const Family = enum { normal, lognormal, exponential, gamma, weibull, beta, power, rayleigh, pareto, gumbel, igauss, sb, su };

pub const Parameters = struct {
    theta: f64 = 0,
    sigma: f64 = 1,
    mu: f64 = 0,
    zeta: f64 = 0,
    alpha: f64 = 1,
    beta: f64 = 1,
    c: f64 = 1,
    lambda: f64 = 1,
    delta: f64 = 1,
    gamma: f64 = 0,
};

pub const Distribution = struct {
    family: Family,
    p: Parameters,

    pub fn validate(self: Distribution, d: *diag.Diagnostics) diag.Error!void {
        inline for (std.meta.fields(Parameters)) |field| {
            if (!std.math.isFinite(@field(self.p, field.name))) return d.fail(error.ParseError, 0, "UNIVARIATE: nonfinite distribution parameter {s}", .{field.name});
        }
        const p = self.p;
        if (p.sigma <= 0 or
            ((self.family == .beta or self.family == .power or self.family == .gamma) and p.alpha <= 0) or
            (self.family == .beta and p.beta <= 0) or
            (self.family == .weibull and p.c <= 0) or
            (self.family == .igauss and (p.mu <= 0 or p.lambda <= 0)) or
            ((self.family == .sb or self.family == .su) and p.delta <= 0))
            return d.fail(error.ParseError, 0, "UNIVARIATE: invalid distribution scale or shape", .{});
    }

    pub fn cdf(self: Distribution, x: f64) f64 {
        const p = self.p;
        const y = (x - p.theta) / p.sigma;
        return switch (self.family) {
            .normal => normal((x - p.mu) / p.sigma),
            .lognormal => if (x <= p.theta) 0 else normal((@log(x - p.theta) - p.zeta) / p.sigma),
            .exponential => if (y <= 0) 0 else -std.math.expm1(-y),
            .gamma => if (y <= 0) 0 else f.gammaP(p.alpha, y),
            .weibull => if (y <= 0) 0 else -std.math.expm1(-std.math.pow(f64, y, p.c)),
            .rayleigh => if (y <= 0) 0 else -std.math.expm1(-y * y / 2),
            .beta => if (y <= 0) 0 else if (y >= 1) 1 else f.betaI(y, p.alpha, p.beta),
            .power => if (y <= 0) 0 else if (y >= 1) 1 else std.math.pow(f64, y, p.alpha),
            .pareto => if (y <= 0) 0 else if (p.alpha == 0) -std.math.expm1(-y) else if (p.alpha > 0 and y >= 1 / p.alpha) 1 else -std.math.expm1(std.math.log1p(-p.alpha * y) / p.alpha),
            .gumbel => @exp(-@exp(-(x - p.mu) / p.sigma)),
            .igauss => blk: {
                if (x <= 0) break :blk 0;
                const r = @sqrt(p.lambda / x);
                const z = -r * (x / p.mu + 1);
                break :blk @min(1, normal(r * (x / p.mu - 1)) + @exp(2 * p.lambda / p.mu + logNormalTail(-z)));
            },
            .sb => if (y <= 0) 0 else if (y >= 1) 1 else normal(p.gamma + p.delta * @log(y / (1 - y))),
            .su => normal(p.gamma + p.delta * std.math.asinh(y)),
        };
    }

    pub fn logPdf(self: Distribution, x: f64) f64 {
        const p = self.p;
        const y = (x - p.theta) / p.sigma;
        const lnorm = 0.5 * @log(2 * std.math.pi);
        switch (self.family) {
            .normal => {
                const z = (x - p.mu) / p.sigma;
                return -z * z / 2 - @log(p.sigma) - lnorm;
            },
            .gumbel => {
                const z = (x - p.mu) / p.sigma;
                return -z - @exp(-z) - @log(p.sigma);
            },
            .su => {
                const z = p.gamma + p.delta * std.math.asinh(y);
                return @log(p.delta / p.sigma) - lnorm - std.math.log1p(y * y) / 2 - z * z / 2;
            },
            .igauss => {
                if (x <= 0) return -inf;
                return @log(p.lambda / (2 * std.math.pi)) / 2 - 1.5 * @log(x) - p.lambda * std.math.pow(f64, x / p.mu - 1, 2) / (2 * x);
            },
            .exponential => return if (y < 0) -inf else -@log(p.sigma) - y,
            else => {},
        }
        if (y <= 0) return -inf;
        return switch (self.family) {
            .lognormal => blk: {
                const z = (@log(x - p.theta) - p.zeta) / p.sigma;
                break :blk -z * z / 2 - @log(p.sigma * (x - p.theta)) - lnorm;
            },
            .gamma => blk: {
                if (p.alpha < 10) break :blk (p.alpha - 1) * @log(y) - y - f.lgammaOf(p.alpha) - @log(p.sigma);
                const u = (y - p.alpha) / p.alpha;
                const deviance = if (@abs(u) < 1e-4) u * u * (-0.5 + u * (1.0 / 3.0 + u * (-0.25 + u * 0.2))) else std.math.log1p(u) - u;
                const inv = 1 / p.alpha;
                const stirling = inv * (1.0 / 12.0 - inv * inv * (1.0 / 360.0 - inv * inv / 1260));
                break :blk p.alpha * deviance - @log(y) + 0.5 * @log(p.alpha) - lnorm - stirling - @log(p.sigma);
            },
            .weibull => @log(p.c / p.sigma) + (p.c - 1) * @log(y) - std.math.pow(f64, y, p.c),
            .rayleigh => @log(y / p.sigma) - y * y / 2,
            .beta => if (y >= 1) -inf else (p.alpha - 1) * @log(y) + (p.beta - 1) * std.math.log1p(-y) - @log(p.sigma) - f.lgammaOf(p.alpha) - f.lgammaOf(p.beta) + f.lgammaOf(p.alpha + p.beta),
            .power => if (y >= 1) -inf else @log(p.alpha / p.sigma) + (p.alpha - 1) * @log(y),
            .pareto => if (p.alpha == 0) -@log(p.sigma) - y else if (p.alpha > 0 and y >= 1 / p.alpha) -inf else -@log(p.sigma) + (1 / p.alpha - 1) * std.math.log1p(-p.alpha * y),
            .sb => blk: {
                if (y >= 1) break :blk -inf;
                const z = p.gamma + p.delta * @log(y / (1 - y));
                break :blk @log(p.delta / p.sigma) - @log(y) - std.math.log1p(-y) - lnorm - z * z / 2;
            },
            else => unreachable,
        };
    }

    pub fn pdf(self: Distribution, x: f64) f64 {
        return @exp(self.logPdf(x));
    }

    fn logProbability(self: Distribution, x: f64, upper: bool) f64 {
        const p = self.p;
        if (self.family == .normal) {
            const z = (x - p.mu) / p.sigma;
            return logNormalTail(if (upper) z else -z);
        }
        if (self.family == .lognormal and x > p.theta) {
            const z = (@log(x - p.theta) - p.zeta) / p.sigma;
            return logNormalTail(if (upper) z else -z);
        }
        const y = (x - p.theta) / p.sigma;
        if (upper and y > 0) switch (self.family) {
            .exponential => return -y,
            .weibull => return -std.math.pow(f64, y, p.c),
            .rayleigh => return -y * y / 2,
            .pareto => return if (p.alpha == 0) -y else if (p.alpha > 0 and y >= 1 / p.alpha) -inf else std.math.log1p(-p.alpha * y) / p.alpha,
            else => {},
        };
        if (self.family == .gumbel) {
            const z = -(x - p.mu) / p.sigma;
            if (!upper) return -@exp(z);
            if (z < -36) return z;
            return @log(-std.math.expm1(-@exp(z)));
        }
        const u = self.cdf(x);
        return if (upper) std.math.log1p(-u) else @log(u);
    }

    /// Caller supplies a probability strictly between zero and one.
    pub fn quantile(self: Distribution, probability: f64) f64 {
        if (!(probability > 0 and probability < 1)) return std.math.nan(f64);
        const p = self.p;
        const z = f.distQuantile(.normal, probability, &.{}).?;
        const e = -std.math.log1p(-probability);
        switch (self.family) {
            .normal => return p.mu + p.sigma * z,
            .lognormal => return p.theta + @exp(p.zeta + p.sigma * z),
            .exponential => return p.theta + p.sigma * e,
            .weibull => return p.theta + p.sigma * std.math.pow(f64, e, 1 / p.c),
            .rayleigh => return p.theta + p.sigma * @sqrt(2 * e),
            .power => return p.theta + p.sigma * std.math.pow(f64, probability, 1 / p.alpha),
            .pareto => return p.theta + p.sigma * (if (p.alpha == 0) e else -std.math.expm1(-p.alpha * e) / p.alpha),
            .gumbel => return p.mu - p.sigma * @log(-@log(probability)),
            .sb => return p.theta + p.sigma / (1 + @exp((p.gamma - z) / p.delta)),
            .su => return p.theta + p.sigma * std.math.sinh((z - p.gamma) / p.delta),
            else => {},
        }
        var lo: f64 = if (self.family == .igauss) 0 else p.theta;
        var hi = if (self.family == .igauss) p.mu else p.theta + p.sigma;
        if (self.family != .beta) {
            var k: usize = 0;
            while (self.cdf(hi) < probability and k < 1024) : (k += 1) {
                hi = lo + 2 * (hi - lo);
                if (!std.math.isFinite(hi)) return std.math.nan(f64);
            }
        }
        for (0..160) |_| {
            const mid = lo / 2 + hi / 2;
            if (mid == lo or mid == hi) break;
            if (self.cdf(mid) < probability) lo = mid else hi = mid;
        }
        return lo / 2 + hi / 2;
    }
};

fn normal(z: f64) f64 {
    return f.distCdf(.normal, z, &.{}).?;
}

fn logNormalTail(z: f64) f64 {
    if (z > 8) return f.logStdNormTail(z);
    return @log(normal(-z));
}

pub const Edf = struct { d: f64, w2: f64, a2: f64 };
/// Raw EDF statistics; p-value availability depends on which parameters were
/// estimated. Do not reuse known-parameter p-values for estimated fits.
pub fn edf(dist: Distribution, sorted: []const f64) ?Edf {
    if (sorted.len == 0) return null;
    const n: f64 = @floatFromInt(sorted.len);
    var result: Edf = .{ .d = 0, .w2 = 1 / (12 * n), .a2 = -n };
    for (sorted, 0..) |v, i| {
        const j: f64 = @floatFromInt(i);
        const u = dist.cdf(v);
        result.d = @max(result.d, @max(u - j / n, (j + 1) / n - u));
        result.w2 += std.math.pow(f64, u - (j + 0.5) / n, 2);
        result.a2 -= ((2 * j + 1) * dist.logProbability(v, false) + (2 * n - 2 * j - 1) * dist.logProbability(v, true)) / n;
    }
    return result;
}

test "UNIVARIATE EDF SAS normal fitted statistics and stable tails" {
    const curve: Distribution = .{ .family = .normal, .p = .{ .mu = 5, .sigma = @sqrt(@as(f64, 20.625)) } };
    const result = edf(curve, &.{ 1, 2, 3, 4, 6, 8, 10, 15 }).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.04091812), result.w2, 5e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.38811470), result.a2, 5e-9);
    const extreme = edf(.{ .family = .normal, .p = .{} }, &.{ -40, 0, 40 }).?;
    try std.testing.expect(std.math.isFinite(extreme.a2));
}

pub fn rankProbability(index: usize, n: usize, rankadj: f64, nadj: f64) f64 {
    return (@as(f64, @floatFromInt(index + 1)) - rankadj) / (@as(f64, @floatFromInt(n)) + nadj);
}

test "UNIVARIATE fixed distribution inverse probabilities and support" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    inline for (std.meta.tags(Family)) |family| {
        const dist: Distribution = .{ .family = family, .p = .{ .mu = 2, .sigma = 3, .alpha = 0.7, .beta = 2, .c = 1.7, .delta = 2, .lambda = 4 } };
        try dist.validate(&d);
        for ([_]f64{ 0.0001, 0.01, 0.25, 0.5, 0.9, 0.9999 }) |p| {
            try std.testing.expectApproxEqAbs(p, dist.cdf(dist.quantile(p)), 2e-9);
        }
    }
    const bounded: Distribution = .{ .family = .beta, .p = .{ .theta = 2, .sigma = 3 } };
    try std.testing.expectEqual(@as(f64, 0), bounded.cdf(2));
    try std.testing.expectEqual(@as(f64, 1), bounded.cdf(5));
    try std.testing.expectEqual(@as(f64, 0), bounded.pdf(5));
}
