//! Parameter estimation, independent of graph and table rendering.
const std = @import("std");
const dist = @import("univ_distributions.zig");
const diag = @import("../diag.zig");
const functions = @import("../functions.zig");
const johnson = @import("univ_johnson_fit.zig");
const endpoint = @import("univ_endpoint_fit.zig");
pub const Report = struct { converged: bool = true, no_fit: bool = false, reason: ?[]const u8 = null, iterations: usize = 0, starts: usize = 0 };
pub const Trace = struct {
    allocator: std.mem.Allocator,
    iterations: std.ArrayList(johnson.Iteration) = .empty,
    failed: bool = false,
    fn record(context: ?*anyopaque, iteration: johnson.Iteration) void {
        const self: *Trace = @ptrCast(@alignCast(context.?));
        self.iterations.append(self.allocator, iteration) catch {
            self.failed = true;
        };
    }
};
pub const JohnsonMethod = enum { percentiles, moments, mle };
pub const Request = struct {
    family: dist.Family,
    theta: ?f64 = 0,
    sigma: ?f64 = null,
    mu: ?f64 = null,
    zeta: ?f64 = null,
    alpha: ?f64 = null,
    beta: ?f64 = null,
    c: ?f64 = null,
    lambda: ?f64 = null,
    delta: ?f64 = null,
    gamma: ?f64 = null,
    maxiter: usize = 20,
    alphainitial: ?f64 = null,
    alphadelta: f64 = 1e-5,
    fitmethod: JohnsonMethod = .percentiles,
    fitinterval: f64 = 0.524,
    fittolerance: f64 = 0.01,
    optboundrange: f64 = 100,
    optmaxiter: usize = 500,
    optmaxstarts: usize = 100,
    optseed: ?f64 = null,
    opttolerance: f64 = 1e-8,
    optprint: bool = false,
    itprint: bool = false,
    edfnsamples: usize = 500,
    edfseed: ?f64 = null,
    report: ?*Report = null,
    trace: ?*Trace = null,
    specified_fields: std.StaticBitSet(std.meta.fields(dist.Parameters).len) = .initEmpty(),

    pub fn specified(self: Request, comptime name: []const u8) bool {
        inline for (std.meta.fields(dist.Parameters), 0..) |field, i| {
            if (comptime std.mem.eql(u8, field.name, name)) return self.specified_fields.isSet(i);
        }
        @compileError("unknown distribution parameter");
    }
};

/// Sorted finite sample, after FREQ expansion. No missing-value filtering or
/// grouping is performed here. Invalid requests and failed fits are distinct
/// diagnostics; no stale last iterate is returned as a converged fit.
pub fn fit(d: *diag.Diagnostics, x: []const f64, request: Request) diag.Error!dist.Distribution {
    const r = request;
    if (r.report) |report| report.* = .{};
    if (x.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: distribution fit requires at least two observations", .{});
    for (x, 0..) |v, i| {
        if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: fit sample must be sorted and finite", .{});
    }
    if (r.maxiter == 0 or !(r.alphadelta > 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid iteration controls", .{});
    if (r.family == .sb or r.family == .su) return fitJohnson(d, x, r);
    if (r.family == .pareto or (r.family == .beta and (r.theta == null or r.sigma == null))) return fitEndpoint(d, x, r);
    if (r.itprint and r.family == .weibull and (r.c == null or r.theta == null)) {
        diag.markGap();
        return d.fail(error.ParseError, 0, "UNIVARIATE: Weibull ITPRINT history is not implemented", .{});
    }
    if (r.theta == null and (r.family == .gamma or r.family == .lognormal or r.family == .weibull)) return fitThreshold(d, x, r);
    const n: f64 = @floatFromInt(x.len);
    var p: dist.Parameters = .{};
    inline for (std.meta.fields(dist.Parameters)) |field| {
        if (@field(r, field.name)) |v| @field(p, field.name) = v;
    }
    var mean: f64 = 0;
    for (x) |v| mean += v / n;
    var css: f64 = 0;
    for (x) |v| css += (v - mean) * (v - mean);
    if (r.theta == null) {
        if (r.family != .exponential) return d.fail(error.ParseError, 0, "UNIVARIATE: estimated threshold is not implemented for {s}", .{@tagName(r.family)});
        p.theta = if (r.sigma == null) (n * x[0] - mean) / (n - 1) else x[0];
    }
    switch (r.family) {
        .normal => {
            p.mu = r.mu orelse mean;
            p.sigma = r.sigma orelse @sqrt(if (r.mu != null) (css + n * (mean - p.mu) * (mean - p.mu)) / n else css / (n - 1));
        },
        .lognormal => {
            if (x[0] <= p.theta) return support(d);
            var lm: f64 = 0;
            for (x) |v| lm += @log(v - p.theta) / n;
            p.zeta = r.zeta orelse lm;
            var ss: f64 = 0;
            for (x) |v| ss += std.math.pow(f64, @log(v - p.theta) - p.zeta, 2);
            p.sigma = r.sigma orelse @sqrt(ss / (n - 1));
        },
        .exponential => {
            if (x[0] < p.theta) return support(d);
            p.sigma = r.sigma orelse (mean - p.theta);
        },
        .rayleigh => {
            if (x[0] < p.theta) return support(d);
            p.sigma = r.sigma orelse @sqrt((css / n + (mean - p.theta) * (mean - p.theta)) / 2);
        },
        .igauss => {
            if (x[0] <= 0) return support(d);
            p.mu = r.mu orelse mean;
            var sum: f64 = 0;
            for (x) |v| sum += (v - p.mu) * (v - p.mu) / (p.mu * p.mu * v);
            p.lambda = r.lambda orelse n / sum;
        },
        .gamma => {
            if (x[0] <= p.theta) return support(d);
            var logmean: f64 = 0;
            for (x) |v| logmean += @log(v - p.theta) / n;
            if (r.alpha == null) {
                const gap = @log(mean - p.theta) - logmean;
                var a = r.alphainitial orelse (3 - gap + @sqrt((gap - 3) * (gap - 3) + 24 * gap)) / (12 * gap);
                var converged = false;
                for (0..r.maxiter) |_| {
                    const value = if (r.sigma) |s| digamma(a) + @log(s) - logmean else digamma(a) - @log(a) + gap;
                    const slope = trigamma(a) - (if (r.sigma == null) 1 / a else @as(f64, 0));
                    var next = a - value / slope;
                    if (next <= 0) next = a / 2;
                    if (@abs(next - a) < r.alphadelta) converged = true;
                    a = next;
                    if (converged) break;
                }
                if (!converged) return convergence(d);
                p.alpha = a;
            }
            p.sigma = r.sigma orelse (mean - p.theta) / p.alpha;
        },
        .weibull => {
            if (x[0] <= p.theta) return support(d);
            var lm: f64 = 0;
            for (x) |v| lm += @log(v - p.theta) / n;
            if (r.c == null) {
                var c: f64 = 1;
                var converged = false;
                for (0..r.maxiter) |_| {
                    var s0: f64 = 0;
                    var s1: f64 = 0;
                    var s2: f64 = 0;
                    const scale = r.sigma orelse (x[x.len - 1] - p.theta);
                    for (x) |v| {
                        const l = @log((v - p.theta) / scale);
                        const w = @exp(c * l);
                        s0 += w;
                        s1 += w * l;
                        s2 += w * l * l;
                    }
                    const value = if (r.sigma != null) 1 / c + lm - @log(scale) - s1 / n else 1 / c + lm - @log(scale) - s1 / s0;
                    const deriv = if (r.sigma != null) -1 / (c * c) - s2 / n else -1 / (c * c) - s2 / s0 + (s1 / s0) * (s1 / s0);
                    var next = c - value / deriv;
                    if (next <= 0) next = c / 2;
                    if (@abs(next - c) < 1e-8) converged = true;
                    c = next;
                    if (converged) break;
                }
                if (!converged) return convergence(d);
                p.c = c;
            }
            if (r.sigma == null) {
                const scale = x[x.len - 1] - p.theta;
                var sum: f64 = 0;
                for (x) |v| sum += std.math.pow(f64, (v - p.theta) / scale, p.c) / n;
                p.sigma = scale * std.math.pow(f64, sum, 1 / p.c);
            }
        },
        .power => {
            if (r.sigma == null) return d.fail(error.ParseError, 0, "UNIVARIATE: power scale estimation is not implemented", .{});
            if (x[0] <= p.theta or x[x.len - 1] >= p.theta + p.sigma) return support(d);
            var sum: f64 = 0;
            for (x) |v| sum += @log((v - p.theta) / p.sigma);
            p.alpha = r.alpha orelse -n / sum;
        },
        .beta => {
            if (r.sigma == null) return d.fail(error.ParseError, 0, "UNIVARIATE: beta scale estimation is not implemented", .{});
            if (x[0] <= p.theta or x[x.len - 1] >= p.theta + p.sigma) return support(d);
            var lx: f64 = 0;
            var ly: f64 = 0;
            for (x) |v| {
                const y = (v - p.theta) / p.sigma;
                lx += @log(y) / n;
                ly += std.math.log1p(-y) / n;
            }
            var a = r.alpha orelse 1;
            var b = r.beta orelse 1;
            var converged = r.alpha != null and r.beta != null;
            for (0..100) |_| {
                if (converged) break;
                const psi = digamma(a + b);
                const tri = trigamma(a + b);
                const ga = digamma(a) - psi - lx;
                const gb = digamma(b) - psi - ly;
                const aa = trigamma(a) - tri;
                const bb = trigamma(b) - tri;
                var da: f64 = 0;
                var db: f64 = 0;
                if (r.alpha == null and r.beta == null) {
                    const det = aa * bb - tri * tri;
                    da = (bb * ga + tri * gb) / det;
                    db = (tri * ga + aa * gb) / det;
                } else if (r.alpha == null) da = ga / aa else db = gb / bb;
                var step: f64 = 1;
                while (a - step * da <= 0 or b - step * db <= 0) step /= 2;
                a -= step * da;
                b -= step * db;
                converged = @max(@abs(step * da), @abs(step * db)) < 1e-10;
            }
            if (!converged) return convergence(d);
            p.alpha = a;
            p.beta = b;
        },
        .gumbel => {
            if (r.sigma == null) {
                var lo = @sqrt(css / n) * 1e-6;
                var hi = @sqrt(css / n) * 100 + @abs((r.mu orelse mean) - mean);
                if (!(lo > 0)) return support(d);
                for (0..100) |_| {
                    const s = lo / 2 + hi / 2;
                    var score: f64 = 0;
                    if (r.mu) |mu| {
                        for (x) |v| {
                            const z = (v - mu) / s;
                            score += z * (-std.math.expm1(-z)) / n;
                        }
                        score -= 1;
                    } else {
                        var sw: f64 = 0;
                        var swx: f64 = 0;
                        for (x) |v| {
                            const w = @exp(-(v - x[0]) / s);
                            sw += w;
                            swx += w * v;
                        }
                        score = mean - swx / sw - s;
                    }
                    if (score > 0) lo = s else hi = s;
                }
                p.sigma = lo / 2 + hi / 2;
            }
            if (r.mu == null) {
                var sw: f64 = 0;
                for (x) |v| sw += @exp(-(v - x[0]) / p.sigma) / n;
                p.mu = x[0] - p.sigma * @log(sw);
            }
        },
        .pareto => {
            if (r.alpha == null or r.sigma == null) return d.fail(error.ParseError, 0, "UNIVARIATE: Pareto parameter estimation is not implemented", .{});
        },
        .sb, .su => unreachable, // dispatched to fitJohnson before this switch
    }
    const result: dist.Distribution = .{ .family = r.family, .p = p };
    try result.validate(d);
    for (x) |v| if (!std.math.isFinite(result.logPdf(v))) return support(d);
    return result;
}

fn logLikelihood(x: []const f64, distribution: dist.Distribution) f64 {
    var sum: f64 = 0;
    for (x) |v| sum += distribution.logPdf(v);
    return sum;
}

fn thresholdCandidate(d: *diag.Diagnostics, x: []const f64, r: Request, log_distance: f64) ?dist.Distribution {
    var fixed = r;
    fixed.theta = x[0] - (x[x.len - 1] - x[0]) * @exp(log_distance);
    // Failed conditional iterations are not a fitted curve. Keep their
    // diagnostics local; the caller reports failure of the complete fit.
    var local = diag.Diagnostics.init(d.arena);
    return fit(&local, x, fixed) catch null;
}

fn thresholdLikelihood(d: *diag.Diagnostics, x: []const f64, r: Request, distance: f64) f64 {
    const candidate = thresholdCandidate(d, x, r, distance) orelse return -std.math.inf(f64);
    // M9 uses the adjusted lognormal profile with n-1 log(sigma), matching
    // its n-1 shape estimate. The unadjusted MLE gives theta=.398939 on the
    // retained gamma-score sample; SAS returns .896031.
    return logLikelihood(x, candidate) + (if (r.family == .lognormal and r.sigma == null) @log(candidate.p.sigma) else @as(f64, 0));
}

fn fitThreshold(d: *diag.Diagnostics, x: []const f64, r: Request) diag.Error!dist.Distribution {
    if (x[0] == x[x.len - 1]) return support(d);
    var best: ?dist.Distribution = null;
    var best_ll = -std.math.inf(f64);
    var left: f64 = -16;
    var middle: f64 = -15.75;
    var fl = thresholdLikelihood(d, x, r, left);
    var fm = thresholdLikelihood(d, x, r, middle);
    // Three-parameter likelihoods can be unbounded at a support endpoint.
    // Select an interior local maximum, never a finite last boundary iterate.
    for (0..126) |_| {
        const right = middle + 0.25;
        const fr = thresholdLikelihood(d, x, r, right);
        if (fm > fl and fm > fr and std.math.isFinite(fm)) {
            var lo = left;
            var hi = right;
            const ratio = 0.6180339887498949;
            var u = hi - ratio * (hi - lo);
            var v = lo + ratio * (hi - lo);
            var fu = thresholdLikelihood(d, x, r, u);
            var fv = thresholdLikelihood(d, x, r, v);
            for (0..80) |_| {
                if (fu > fv) {
                    hi = v;
                    v = u;
                    fv = fu;
                    u = hi - ratio * (hi - lo);
                    fu = thresholdLikelihood(d, x, r, u);
                } else {
                    lo = u;
                    u = v;
                    fu = fv;
                    v = lo + ratio * (hi - lo);
                    fv = thresholdLikelihood(d, x, r, v);
                }
            }
            const at = if (fu > fv) u else v;
            const score = @max(fu, fv);
            if (score > best_ll) {
                best = thresholdCandidate(d, x, r, at);
                best_ll = score;
            }
        }
        left = middle;
        middle = right;
        fl = fm;
        fm = fr;
    }
    return best orelse return convergence(d);
}

test "UNIVARIATE estimated thresholds SAS M9 lognormal gamma Weibull" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var x: [51]f64 = undefined;
    const base: dist.Distribution = .{ .family = .gamma, .p = .{ .theta = 2, .alpha = 3, .sigma = 2 } };
    for (&x, 0..) |*v, i| v.* = base.quantile((@as(f64, @floatFromInt(i + 1)) - 0.375) / 51.25);
    const ln = try fit(&d, &x, .{ .family = .lognormal, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, 0.896031), ln.p.theta, 2e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 1.845943), ln.p.zeta, 2e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 0.481258), ln.p.sigma, 2e-6);
    const gamma = try fit(&d, &x, .{ .family = .gamma, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, 2.37173), gamma.p.theta, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 2.659039), gamma.p.alpha, 5e-5);
    const weibull = try fit(&d, &x, .{ .family = .weibull, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, 2.76106), weibull.p.theta, 2e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 1.592397), weibull.p.c, 2e-5);
    // Pareto on this sample is not covered by this threshold-fit assertion:
    // M9 suppresses its curve while the profile helper finds an interior fit.
    // Tracked as PARETO-PRESENCE in the dev4 acceptance inventory, not accepted.
}

fn samplePercentile(x: []const f64, probability: f64) f64 {
    const rank = @as(f64, @floatFromInt(x.len)) * probability;
    const lower: usize = @intFromFloat(@floor(rank));
    if (lower == 0) return x[0];
    if (lower >= x.len) return x[x.len - 1];
    return if (rank == @floor(rank)) x[lower - 1] / 2 + x[lower] / 2 else x[lower];
}

fn fitJohnson(d: *diag.Diagnostics, x: []const f64, r: Request) diag.Error!dist.Distribution {
    if (r.fitmethod != .percentiles) {
        const result = johnson.fit(if (r.family == .sb) .sb else .su, if (r.fitmethod == .moments) .moments else .mle, x, .{ .theta = r.theta, .lambda = r.sigma, .delta = r.delta, .gamma = r.gamma }, .{ .optmaxiter = r.optmaxiter, .optmaxstarts = r.optmaxstarts, .optboundrange = r.optboundrange, .opttolerance = r.opttolerance, .optseed = try resolveSeed(d, r.optseed), .trace_context = r.trace, .trace = if (r.trace != null) Trace.record else null });
        if (r.trace) |trace| if (trace.failed) return error.OutOfMemory;
        const success = switch (result) {
            .converged => |success| success,
            .nonconverged => |failure| blk: {
                switch (failure.reason) {
                    .invalid_parameters, .invalid_controls, .unsupported_combination, .outside_support => return d.fail(error.ParseError, 0, "UNIVARIATE: invalid Johnson fit: {s}", .{@tagName(failure.reason)}),
                    else => {},
                }
                if (r.report) |report| report.* = .{ .converged = false, .no_fit = failure.best == null, .reason = @tagName(failure.reason) };
                try d.warn(0, "UNIVARIATE: Johnson fit did not converge ({s}); {s}", .{ @tagName(failure.reason), if (failure.best != null) "retaining the finite fallback curve" else "no fitted curve is available" });
                break :blk failure.best orelse return error.ParseError;
            },
        };
        if (r.report) |report| {
            report.iterations = success.iterations;
            report.starts = success.starts;
        }
        const p = success.parameters;
        const fitted: dist.Distribution = .{ .family = r.family, .p = .{ .theta = p.theta, .sigma = p.lambda, .delta = p.delta, .gamma = p.gamma } };
        try fitted.validate(d);
        return fitted;
    }
    var p: dist.Parameters = .{};
    if (r.theta == null or r.sigma == null or r.delta == null or r.gamma == null) {
        if (r.fitmethod != .percentiles) return d.fail(error.ParseError, 0, "UNIVARIATE: Johnson {s} estimation is not implemented", .{@tagName(r.fitmethod)});
        const z = r.fitinterval;
        if (!(z > 0) or !std.math.isFinite(z) or !(r.fittolerance >= 0 and r.fittolerance < 1)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid Johnson percentile controls", .{});
        const a = samplePercentile(x, functions.distCdf(.normal, -3 * z, &.{}).?);
        const b = samplePercentile(x, functions.distCdf(.normal, -z, &.{}).?);
        const c = samplePercentile(x, functions.distCdf(.normal, z, &.{}).?);
        const e = samplePercentile(x, functions.distCdf(.normal, 3 * z, &.{}).?);
        const n = b - a;
        const middle = c - b;
        const m = e - c;
        if (!(n > 0 and middle > 0 and m > 0)) return convergence(d);
        const ratio = n * m / (middle * middle);
        if (r.family == .su) {
            if (ratio <= 1 + r.fittolerance) return d.fail(error.ParseError, 0, "UNIVARIATE: percentile ratio does not select a Johnson SU distribution", .{});
            p.delta = 2 * z / std.math.acosh((m + n) / (2 * middle));
            p.gamma = p.delta * std.math.atanh((n - m) / (2 * middle * std.math.sinh(2 * z / p.delta)));
            p.sigma = middle / (2 * std.math.cosh(p.gamma / p.delta) * std.math.sinh(z / p.delta));
            p.theta = (b + c) / 2 + p.sigma * std.math.sinh(p.gamma / p.delta) * std.math.cosh(z / p.delta);
        } else {
            if (ratio >= 1 - r.fittolerance) return d.fail(error.ParseError, 0, "UNIVARIATE: percentile ratio does not select a Johnson SB distribution", .{});
            // Inverse-logit quantiles are a fractional linear transform of
            // four geometrically spaced odds. Their cross-ratio determines r.
            const cross = (1 + middle / n) * (1 + middle / m);
            const rr = (cross - 2 + @sqrt((cross - 2) * (cross - 2) - 4)) / 2;
            const k = middle / n;
            const odds = (rr - k) / (k * rr * rr - rr);
            p.sigma = n * (1 + odds) * (1 + odds * rr) / (odds * (rr - 1));
            p.theta = a - p.sigma * odds / (1 + odds);
            p.delta = 2 * z / @log(rr);
            p.gamma = -3 * z - p.delta * @log(odds);
        }
    }
    // SAS estimates the percentile curve first, then honors fixed parameters;
    // fixed SB endpoints do not trigger a conditional refit of the shapes.
    if (r.theta) |v| p.theta = v;
    if (r.sigma) |v| p.sigma = v;
    if (r.delta) |v| p.delta = v;
    if (r.gamma) |v| p.gamma = v;
    const result: dist.Distribution = .{ .family = r.family, .p = p };
    try result.validate(d);
    for (x) |v| if (!std.math.isFinite(result.logPdf(v))) return support(d);
    return result;
}

/// Resolve the omitted clock-derived seed once per fit/simulation. Explicit
/// seeds repeat this implementation's stream, not SAS's proprietary sequence.
pub fn resolveSeed(d: *diag.Diagnostics, seed: ?f64) diag.Error!u64 {
    if (seed) |value| if (value != 0) {
        if (!std.math.isFinite(value) or value < 0 or value != @floor(value) or value >= @as(f64, @floatFromInt(std.math.maxInt(u64)))) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid random seed", .{});
        return @intFromFloat(value);
    };
    const now = std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds;
    const bits: u96 = @bitCast(now);
    return @max(1, @as(u64, @truncate(bits)));
}

fn fitEndpoint(d: *diag.Diagnostics, x: []const f64, r: Request) diag.Error!dist.Distribution {
    const family: endpoint.Family = switch (r.family) {
        .beta => .beta,
        .power => .power,
        .pareto => .pareto,
        else => unreachable,
    };
    const result = endpoint.fit(family, x, .{ .theta = r.theta, .sigma = r.sigma, .alpha = r.alpha, .beta = r.beta }, .{});
    const success = switch (result) {
        .converged => |success| success,
        .nonconverged => |failure| blk: {
            switch (failure.reason) {
                .invalid_parameters, .invalid_controls, .unsupported_combination, .unsupported_method, .outside_support => return d.fail(error.ParseError, 0, "UNIVARIATE: invalid endpoint fit: {s}", .{@tagName(failure.reason)}),
                else => {},
            }
            if (r.report) |report| report.* = .{ .converged = false, .no_fit = failure.best == null, .reason = @tagName(failure.reason) };
            try d.warn(0, "UNIVARIATE: {s} fit did not converge ({s}); {s}", .{ @tagName(r.family), @tagName(failure.reason), if (failure.best != null) "retaining the finite fallback curve" else "no fitted curve is available" });
            break :blk failure.best orelse return error.ParseError;
        },
    };
    if (r.report) |report| report.iterations = success.iterations;
    const p = success.parameters;
    const fitted: dist.Distribution = .{ .family = r.family, .closed_upper = (r.family == .pareto and p.alpha == 1) or (r.family != .pareto and r.sigma == null and p.beta == 1), .p = .{ .theta = p.theta, .sigma = p.sigma, .alpha = p.alpha, .beta = p.beta } };
    try fitted.validate(d);
    for (x) |v| if (!std.math.isFinite(fitted.logPdf(v))) return support(d);
    return fitted;
}

test "UNIVARIATE Johnson percentile fitting SAS M9 fixed and estimated endpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var u: [101]f64 = undefined;
    var b: [101]f64 = undefined;
    for (&u, &b, 0..) |*uv, *bv, i| {
        const z = functions.distQuantile(.normal, (@as(f64, @floatFromInt(i + 1)) - 0.375) / 101.25, &.{}).?;
        uv.* = 3 + 2 * std.math.sinh((z - 0.4) / 1.2);
        bv.* = 1 / (1 + @exp((0.4 - z) / 1.2));
    }
    const su = try fit(&d, &u, .{ .family = .su, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, 2.921422), su.p.theta, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 1.837628), su.p.sigma, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 1.118261), su.p.delta, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.357627), su.p.gamma, 5e-7);
    const sb = try fit(&d, &b, .{ .family = .sb, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, -0.0390644103866), sb.p.theta, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 1.118077), sb.p.sigma, 5e-7);
    const fixed = try fit(&d, &b, .{ .family = .sb, .sigma = 1 });
    try std.testing.expectEqual(@as(f64, 0), fixed.p.theta);
    try std.testing.expectEqual(@as(f64, 1), fixed.p.sigma);
    try std.testing.expectApproxEqAbs(@as(f64, 1.35412), fixed.p.delta, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.502458), fixed.p.gamma, 5e-7);
}

fn support(d: *diag.Diagnostics) diag.Error {
    return d.fail(error.ParseError, 0, "UNIVARIATE: sample is outside the distribution support or fit is degenerate", .{});
}
fn convergence(d: *diag.Diagnostics) diag.Error {
    return d.fail(error.ParseError, 0, "UNIVARIATE: distribution parameter estimation did not converge", .{});
}
fn digamma(value: f64) f64 {
    var x = value;
    var result: f64 = 0;
    while (x < 12) : (x += 1) result -= 1 / x;
    const q = 1 / (x * x);
    return result + @log(x) - 0.5 / x - q * (1.0 / 12.0 - q * (1.0 / 120.0 - q * (1.0 / 252.0 - q / 240)));
}
fn trigamma(value: f64) f64 {
    var x = value;
    var result: f64 = 0;
    while (x < 12) : (x += 1) result += 1 / (x * x);
    const q = 1 / (x * x);
    return result + 1 / x + q / 2 + q / x * (1.0 / 6.0 - q * (1.0 / 30.0 - q * (1.0 / 42.0 - q / 30)));
}

test "UNIVARIATE fits SAS M9 fixed and estimated parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const x = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const norm = try fit(&d, &x, .{ .family = .normal, .mu = 5 });
    try std.testing.expectApproxEqAbs(@as(f64, 4.541476), norm.p.sigma, 5e-7);
    const ln = try fit(&d, &x, .{ .family = .lognormal, .zeta = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 1.046037), ln.p.sigma, 5e-7);
    const exp = try fit(&d, &x, .{ .family = .exponential, .theta = null });
    try std.testing.expectApproxEqAbs(@as(f64, 0.267857142857), exp.p.theta, 1e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 5.857142857143), exp.p.sigma, 1e-11);
    const gamma = try fit(&d, &x, .{ .family = .gamma });
    try std.testing.expectApproxEqAbs(@as(f64, 1.788518), gamma.p.alpha, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 3.424622), gamma.p.sigma, 5e-7);
    const weibull = try fit(&d, &x, .{ .family = .weibull });
    try std.testing.expectApproxEqAbs(@as(f64, 1.417463), weibull.p.c, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 6.752248), weibull.p.sigma, 5e-7);
    const ig = try fit(&d, &x, .{ .family = .igauss, .mu = 5 });
    try std.testing.expectApproxEqAbs(@as(f64, 6.145967), ig.p.lambda, 5e-7);
    const gumbel = try fit(&d, &x, .{ .family = .gumbel });
    try std.testing.expectApproxEqAbs(@as(f64, 4.113469), gumbel.p.mu, 5e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 3.278538), gumbel.p.sigma, 5e-6);
    const gm = try fit(&d, &x, .{ .family = .gumbel, .mu = 5 });
    // SAS's optimizer stops several micro-units before the scalar score root.
    try std.testing.expectApproxEqAbs(@as(f64, 3.608504), gm.p.sigma, 5e-6);
    const pareto = try fit(&d, &x, .{ .family = .pareto });
    try std.testing.expectApproxEqAbs(@as(f64, 0.6815), pareto.p.alpha, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 10.99992), pareto.p.sigma, 2e-4);
    const bounded = [_]f64{ 0.02, 0.05, 0.1, 0.15, 0.2, 0.3, 0.45, 0.6, 0.75, 0.9, 0.95, 0.99 };
    const beta = try fit(&d, &bounded, .{ .family = .beta, .sigma = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.603334), beta.p.alpha, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.65165), beta.p.beta, 5e-7);
    const power = try fit(&d, &bounded, .{ .family = .power, .sigma = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.765082), power.p.alpha, 5e-7);
    try std.testing.expectError(error.ParseError, fit(&d, &x, .{ .family = .gamma, .maxiter = 1 }));
    try std.testing.expectError(error.ParseError, fit(&d, &x, .{ .family = .lognormal, .theta = 1 }));
}

test "UNIVARIATE uniform Pareto endpoint has finite likelihood" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const curve = try fit(&d, &.{ 1, 2, 4, 8 }, .{ .family = .pareto, .alpha = 1 });
    try std.testing.expectEqual(@as(f64, 8), curve.p.sigma);
    try std.testing.expectApproxEqAbs(@as(f64, 0.125), curve.pdf(8), 1e-15);
    const power: dist.Distribution = .{ .family = .power, .closed_upper = true, .p = .{ .theta = 1, .sigma = 4, .alpha = 2 } };
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), power.pdf(5), 1e-15);
}
