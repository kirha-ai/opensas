//! Bernoulli logit Fisher scoring (S154 physical pp.5909-5912,5914-5918).
//! Uses scaled QR from reg_fit for information solves, not normal-equation
//! inversion. Caller supplies an intercept in column zero. Arena-owned result.
const std = @import("std");
const diag = @import("../diag.zig");
const reg = @import("reg_fit.zig");
const fns = @import("../functions.zig");
const A = std.mem.Allocator;
pub const convergence = @import("logistic_convergence.zig");
pub const Technique = enum { automatic, fisher, newton };
pub const Ridging = enum { relative, absolute, none };
pub const Options = struct { gconv: f64 = 1e-8, absfconv: ?f64 = null, fconv: ?f64 = null, xconv: ?f64 = null, max_iterations: usize = 25, technique: Technique = .automatic, ridging: Ridging = .relative, initial: ?[]const f64 = null, return_incomplete: bool = false, capture_history: bool = false };
pub const Fit = struct {
    coefficients: []const f64,
    covariance: []const f64,
    probabilities: []const f64,
    log_likelihood: f64,
    null_log_likelihood: f64,
    score_test: f64,
    iterations: usize,
    converged: bool = true,
    stop: convergence.Stop = .{},
    history: []const convergence.Iteration = &.{},
    ridge_steps: usize = 0,
    halving_steps: usize = 0,
};
const Sum = struct {
    value: f64 = 0,
    correction: f64 = 0,
    fn add(s: *Sum, x: f64) void {
        const next = s.value + x;
        s.correction += if (@abs(s.value) >= @abs(x)) (s.value - next) + x else (x - next) + s.value;
        s.value = next;
    }
    fn total(s: Sum) f64 {
        return s.value + s.correction;
    }
};
fn dot(x: []const f64, y: []const f64) f64 {
    var s: Sum = .{};
    for (x, y) |v, w| s.add(v * w);
    return s.total();
}
fn softplus(x: f64) f64 {
    return @max(0, x) + std.math.log1p(@exp(-@abs(x)));
}
pub fn probability(eta: f64) f64 {
    const e = @exp(-@abs(eta));
    return if (eta >= 0) 1 / (1 + e) else e / (1 + e);
}
fn likelihood(x: []const f64, y: []const f64, b: []const f64, multiplicity: []const f64) f64 {
    var s: Sum = .{};
    for (y, 0..) |v, i| {
        const eta = dot(x[i * b.len ..][0..b.len], b);
        s.add(multiplicity[i] * (if (v == 1) -softplus(-eta) else -softplus(eta)));
    }
    return s.total();
}

pub fn fit(a: A, x: []const f64, y: []const f64, n: usize, p: usize, o: Options) diag.Error!Fit {
    return fitWeighted(a, x, y, n, p, null, null, o);
}

/// Compact Bernoulli frequency representation. An events/trials row becomes at
/// most two weighted rows; no expansion proportional to the trial count is used.
pub fn fitWeighted(a: A, x: []const f64, y: []const f64, n: usize, p: usize, frequency: ?[]const f64, analysis_weights: ?[]const f64, o: Options) diag.Error!Fit {
    if (n == 0 or p == 0 or x.len != (std.math.mul(usize, n, p) catch return error.ExecError) or y.len != n or !convergence.valid(o)) return error.ExecError;
    if (frequency) |f| if (f.len != n) return error.ExecError;
    if (analysis_weights) |w| if (w.len != n) return error.ExecError;
    const multiplicity = try a.alloc(f64, n);
    defer a.free(multiplicity);
    var total: f64 = 0;
    var events: f64 = 0;
    for (y, 0..) |v, i| {
        if (v != 0 and v != 1) return error.ExecError;
        const f = if (frequency) |f| f[i] else 1;
        const w = if (analysis_weights) |w| w[i] else 1;
        if (!(f > 0) or !(w > 0) or !std.math.isFinite(f * w)) return error.ExecError;
        multiplicity[i] = f * w;
        total += multiplicity[i];
        events += multiplicity[i] * v;
        if (x[i * p] != 1) return error.ExecError;
    }
    for (x) |v| if (!std.math.isFinite(v)) return error.ExecError;
    const nf: f64 = @floatFromInt(n);
    if (!(events > 0 and events < total) or !std.math.isFinite(total)) return error.ExecError;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    var iteration = std.heap.ArenaAllocator.init(a);
    defer iteration.deinit();
    const b = try tmp.alloc(f64, p);
    @memset(b, 0);
    b[0] = @log(events / (total - events));
    const candidate = try tmp.alloc(f64, p);
    const probabilities = try tmp.alloc(f64, n);
    const weights = try tmp.alloc(f64, n);
    const residuals = try tmp.alloc(f64, n);
    const working = try tmp.alloc(f64, n);
    const gradient = try tmp.alloc(f64, p);
    const null_ll = likelihood(x, y, b, multiplicity);
    var score_test: f64 = 0;
    if (o.initial) |initial| {
        if (initial.len != p) return error.ExecError;
        for (initial) |value| if (!std.math.isFinite(value)) return error.ExecError;
        score_test = (try nullScore(a, x, y, p, frequency orelse blk: {
            const ones = try tmp.alloc(f64, n);
            @memset(ones, 1);
            break :blk ones;
        }, analysis_weights orelse blk: {
            const ones = try tmp.alloc(f64, n);
            @memset(ones, 1);
            break :blk ones;
        })).statistic;
        @memcpy(b, initial);
    }
    const previous_b = try tmp.alloc(f64, p);
    var previous_ll: ?f64 = null;
    var history: std.ArrayList(convergence.Iteration) = .empty;
    var ridge_steps: usize = 0;
    var halving_steps: usize = 0;
    for (0..o.max_iterations + 1) |iter| {
        _ = iteration.reset(.retain_capacity);
        const ll = likelihood(x, y, b, multiplicity);
        if (!std.math.isFinite(ll)) return error.ExecError;
        var separates = true;
        for (y, 0..) |v, i| {
            const eta = dot(x[i * p ..][0..p], b);
            const e = @exp(-@abs(eta));
            const denom = 1 + e;
            probabilities[i] = if (eta >= 0) 1 / denom else e / denom;
            weights[i] = multiplicity[i] * e / (denom * denom);
            residuals[i] = multiplicity[i] * (if (v == 1) (if (eta >= 0) e / denom else 1 / denom) else -probabilities[i]);
            if (!((v == 1 and eta > 0) or (v == 0 and eta < 0))) separates = false;
            if (!(weights[i] > 0)) return error.ExecError;
            working[i] = residuals[i] / weights[i];
        }
        if (separates) return error.ExecError; // finite unpenalized MLE does not exist
        for (0..p) |j| {
            var sum: Sum = .{};
            for (0..n) |i| sum.add(x[i * p + j] * residuals[i]);
            gradient[j] = sum.total();
        }
        var step = try reg.fit(iteration.allocator(), x, working, n, p, weights);
        defer step.deinit(iteration.allocator());
        if (step.rank != p) return error.ExecError;
        const norm = dot(gradient, step.coefficients);
        if (iter == 0 and o.initial == null) score_test = @max(0, norm);
        // Published standardized-information check for quasi-separation.
        if (iter >= 8) for (1..p) |j| {
            var mean: Sum = .{};
            for (0..n) |i| mean.add(x[i * p + j]);
            const center = mean.total() / nf;
            var css: Sum = .{};
            for (0..n) |i| {
                const z = x[i * p + j] - center;
                css.add(z * z);
            }
            if (step.covariance_unscaled[j * p + j] * (css.total() / nf) > 5000) return error.ExecError;
        };
        const metrics = convergence.metrics(ll, b, norm, previous_ll, if (previous_ll != null) previous_b else null);
        if (o.capture_history) try history.append(a, .{ .index = iter, .log_likelihood = ll, .metrics = metrics });
        const stop = convergence.satisfied(o, metrics);
        if (stop != null or iter == o.max_iterations) {
            if (stop == null and !o.return_incomplete) return error.ExecError;
            for (0..p) |j| if (!(step.covariance_unscaled[j * p + j] > 0) or !std.math.isFinite(step.covariance_unscaled[j * p + j])) return error.ExecError;
            return .{ .coefficients = try a.dupe(f64, b), .covariance = try a.dupe(f64, step.covariance_unscaled), .probabilities = try a.dupe(f64, probabilities), .log_likelihood = ll, .null_log_likelihood = null_ll, .score_test = score_test, .iterations = iter, .converged = stop != null, .stop = stop orelse .{ .reason = .iteration_limit, .threshold = @floatFromInt(o.max_iterations), .metric = metrics.gradient }, .history = history.items, .ridge_steps = ridge_steps, .halving_steps = halving_steps };
        }
        for (0..p) |j| candidate[j] = b[j] + step.coefficients[j];
        var accepted = std.math.isFinite(likelihood(x, y, candidate, multiplicity)) and likelihood(x, y, candidate, multiplicity) >= ll;
        if (!accepted and o.ridging == .none) {
            var factor: f64 = 0.5;
            for (0..40) |_| {
                halving_steps += 1;
                for (0..p) |j| candidate[j] = b[j] + factor * step.coefficients[j];
                const next = likelihood(x, y, candidate, multiplicity);
                if (std.math.isFinite(next) and next >= ll) {
                    accepted = true;
                    break;
                }
                factor /= 2;
            }
        }
        if (!accepted and o.ridging != .none) {
            // Default RIDGING=RELATIVE (S154 physical p.5883): add a relative
            // diagonal penalty to information, increasing it until LL improves.
            // QR on appended diagonal rows avoids explicitly inverting X'WX.
            const augmented_x = try iteration.allocator().alloc(f64, (n + p) * p);
            const augmented_y = try iteration.allocator().alloc(f64, n + p);
            const augmented_w = try iteration.allocator().alloc(f64, n + p);
            @memset(augmented_x, 0);
            @memcpy(augmented_x[0 .. n * p], x);
            @memcpy(augmented_y[0..n], working);
            @memset(augmented_y[n..], 0);
            @memcpy(augmented_w[0..n], weights);
            @memset(augmented_w[n..], 1);
            const norms = try iteration.allocator().alloc(f64, p);
            for (0..p) |j| {
                var norm_x: f64 = 0;
                for (0..n) |i| norm_x = std.math.hypot(norm_x, @sqrt(weights[i]) * x[i * p + j]);
                norms[j] = norm_x;
            }
            var ridge: f64 = 0.0001;
            for (0..40) |_| {
                ridge_steps += 1;
                for (0..p) |j| augmented_x[(n + j) * p + j] = @sqrt(ridge) * (if (o.ridging == .relative) norms[j] else 1);
                var adjusted = try reg.fit(iteration.allocator(), augmented_x, augmented_y, n + p, p, augmented_w);
                defer adjusted.deinit(iteration.allocator());
                for (0..p) |j| candidate[j] = b[j] + adjusted.coefficients[j];
                const next = likelihood(x, y, candidate, multiplicity);
                if (std.math.isFinite(next) and next >= ll) {
                    accepted = true;
                    break;
                }
                ridge *= 2;
            }
        }
        if (!accepted) return error.ExecError;
        @memcpy(previous_b, b);
        previous_ll = ll;
        @memcpy(b, candidate);
    }
    return error.ExecError;
}

/// General Wald quadratic for a coefficient block, solved through QR.
pub fn wald(a: A, cov: []const f64, b: []const f64) diag.Error!f64 {
    if (b.len == 0) return 0;
    var solution = try reg.fit(a, cov, b, b.len, b.len, null);
    defer solution.deinit(a);
    if (solution.rank != b.len) return error.ExecError;
    const q = dot(b, solution.coefficients);
    if (!std.math.isFinite(q)) return error.ExecError;
    return @max(0, q);
}
pub fn blockWald(a: A, r: Fit, start: usize, len: usize) diag.Error!f64 {
    const p = r.coefficients.len;
    if (start + len > p) return error.ExecError;
    const cov = try a.alloc(f64, len * len);
    defer a.free(cov);
    for (0..len) |i| for (0..len) |j| {
        cov[i * len + j] = r.covariance[(start + i) * p + start + j];
    };
    return wald(a, cov, r.coefficients[start..][0..len]);
}
pub fn chiTail(value: f64, df: usize) f64 {
    if (df == 0 or std.math.isNan(value) or value < 0) return std.math.nan(f64);
    if (std.math.isInf(value)) return 0;
    const shape = @as(f64, @floatFromInt(df)) / 2;
    const x = value / 2;
    if (x < shape + 1) return @max(0, 1 - fns.gammaP(shape, x));
    // The shared lower-gamma function subtracts this small upper tail from 1.
    // Evaluate its continued fraction directly to preserve small p-values.
    const tiny: f64 = 1e-300;
    var b = x + 1 - shape;
    var c: f64 = 1 / tiny;
    var d = 1 / b;
    var h = d;
    for (1..1000) |i| {
        const fi: f64 = @floatFromInt(i);
        const an = -fi * (fi - shape);
        b += 2;
        d = an * d + b;
        if (@abs(d) < tiny) d = tiny;
        c = b + an / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1 / d;
        const delta = d * c;
        h *= delta;
        if (@abs(delta - 1) <= 4 * std.math.floatEps(f64)) break;
    }
    return @min(1, @max(0, @exp(-x + shape * @log(x) - fns.lgammaOf(shape)) * h));
}

pub const Association = struct { concordant: usize = 0, discordant: usize = 0, tied: usize = 0, pairs: usize = 0 };
pub fn association(y: []const f64, probabilities: []const f64) Association {
    var r: Association = .{};
    for (y, 0..) |first, i| for (y[i + 1 ..], i + 1..) |second, j| {
        if (first == second) continue;
        r.pairs += 1;
        const event = if (first == 1) probabilities[i] else probabilities[j];
        const nonevent = if (first == 0) probabilities[i] else probabilities[j];
        if (event > nonevent) r.concordant += 1 else if (event < nonevent) r.discordant += 1 else r.tied += 1;
    };
    return r;
}

test "LOGISTIC_FIT independent intercept and two-binomial-group estimates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const intercept = try fit(a, &.{ 1, 1, 1, 1 }, &.{ 1, 0, 0, 0 }, 4, 1, .{});
    try std.testing.expectApproxEqAbs(@log(@as(f64, 1.0 / 3.0)), intercept.coefficients[0], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), intercept.covariance[0], 1e-13);
    const y = [_]f64{ 1, 1, 0, 0, 0, 1, 1, 1, 0, 0 };
    var x: [20]f64 = undefined;
    for (0..10) |i| {
        @memcpy(x[2 * i ..][0..2], &[_]f64{ 1, if (i < 5) 0 else 1 });
    }
    const r = try fit(a, &x, &y, 10, 2, .{ .gconv = 1e-20 });
    try std.testing.expectApproxEqAbs(@log(@as(f64, 2.0 / 3.0)), r.coefficients[0], 1e-9);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 2.25)), r.coefficients[1], 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 / 6.0), r.covariance[0], 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 / 3.0), r.covariance[3], 1e-9);
    try std.testing.expectApproxEqAbs(@exp(@as(f64, -10)), chiTail(20, 2), 1e-17);
}
test "LOGISTIC_FIT rejects separation singularity and invalid responses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.ExecError, fit(a, &.{ 1, 0, 1, 1 }, &.{ 0, 1 }, 2, 2, .{}));
    try std.testing.expectError(error.ExecError, fit(a, &.{ 1, 1, 1, 1, 1, 1, 1, 1 }, &.{ 0, 1, 0, 1 }, 4, 2, .{}));
    try std.testing.expectError(error.ExecError, fit(a, &.{ 1, 1 }, &.{ 0, 2 }, 2, 1, .{}));
}

pub const WeightedAssociation = struct { concordant: f64 = 0, discordant: f64 = 0, tied: f64 = 0, pairs: f64 = 0 };
pub fn associationWeighted(y: []const f64, probabilities: []const f64, frequencies: []const f64) WeightedAssociation {
    var r: WeightedAssociation = .{};
    for (y, 0..) |first, i| for (y[i + 1 ..], i + 1..) |second, j| {
        if (first == second) continue;
        const count = frequencies[i] * frequencies[j];
        r.pairs += count;
        const event = if (first == 1) probabilities[i] else probabilities[j];
        const nonevent = if (first == 0) probabilities[i] else probabilities[j];
        if (event > nonevent) r.concordant += count else if (event < nonevent) r.discordant += count else r.tied += count;
    };
    return r;
}

/// Global score at the intercept-only null, without estimating a full model.
/// NOFIT still requests this statistic (S154 physical pp.5918–5919).
pub fn nullScore(a: A, x: []const f64, y: []const f64, p: usize, frequencies: []const f64, weights_: []const f64) diag.Error!struct { statistic: f64, log_likelihood: f64 } {
    if (p == 0 or y.len == 0 or x.len != y.len * p or frequencies.len != y.len or weights_.len != y.len) return error.ExecError;
    const weights = try a.alloc(f64, y.len);
    defer a.free(weights);
    const working = try a.alloc(f64, y.len);
    defer a.free(working);
    const gradient = try a.alloc(f64, p);
    defer a.free(gradient);
    @memset(gradient, 0);
    var total: f64 = 0;
    var events: f64 = 0;
    for (y, frequencies, weights_) |value, frequency, weight| {
        if (value != 0 and value != 1) return error.ExecError;
        total += frequency * weight;
        events += value * frequency * weight;
    }
    if (!(events > 0 and events < total)) return error.ExecError;
    const probability_ = events / total;
    for (y, 0..) |value, i| {
        const multiplicity = frequencies[i] * weights_[i];
        weights[i] = multiplicity * probability_ * (1 - probability_);
        working[i] = (value - probability_) / (probability_ * (1 - probability_));
        for (0..p) |j| gradient[j] += x[i * p + j] * multiplicity * (value - probability_);
    }
    var solution = try reg.fit(a, x, working, y.len, p, weights);
    defer solution.deinit(a);
    if (solution.rank != p) return error.ExecError;
    return .{ .statistic = @max(0, dot(gradient, solution.coefficients)), .log_likelihood = events * @log(probability_) + (total - events) * std.math.log1p(-probability_) };
}
