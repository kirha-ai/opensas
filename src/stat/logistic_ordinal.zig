//! Multinomial cumulative and adjacent-category likelihoods, SAS/STAT15.4
//! physical pp.5907–5909,5918–5920. Parameter order is K cutpoints followed
//! by common slopes; input X contains one intercept followed by covariates.
//! Expected information uses sum_c (dP_c dP_c')/P_c, never binary pseudo-fits.
const std = @import("std");
const diag = @import("../diag.zig");
const fns = @import("../functions.zig");
const binary = @import("logistic_fit.zig");
const A = std.mem.Allocator;
pub const Link = enum { logit, probit, cloglog, alogit };
pub const Fit = struct {
    result: binary.Fit,
    levels: usize,
    parallel_score: ?f64 = null,
    parallel_df: usize = 0,
};
fn cdf(link: Link, eta: f64) f64 {
    return switch (link) {
        .logit => binary.probability(eta),
        .probit => fns.distCdf(.normal, eta, &.{}).?,
        .cloglog => -std.math.expm1(-@exp(eta)),
        .alogit => unreachable,
    };
}
fn density(link: Link, eta: f64) f64 {
    return switch (link) {
        .logit => blk: {
            const e = @exp(-@abs(eta));
            break :blk e / ((1 + e) * (1 + e));
        },
        .probit => @exp(-eta * eta / 2) / @sqrt(2 * std.math.pi),
        .cloglog => if (eta > 700) 0 else @exp(eta - @exp(eta)),
        .alogit => unreachable,
    };
}
fn densityDerivative(link: Link, eta: f64) f64 {
    const f = density(link, eta);
    return switch (link) {
        .logit => f * (1 - 2 * cdf(link, eta)),
        .probit => -eta * f,
        .cloglog => if (eta > 700) 0 else f * (1 - @exp(eta)),
        .alogit => unreachable,
    };
}
fn quantile(link: Link, p: f64) f64 {
    return switch (link) {
        .logit => @log(p / (1 - p)),
        .probit => fns.distQuantile(.normal, p, &.{}).?,
        .cloglog => @log(-std.math.log1p(-p)),
        .alogit => unreachable,
    };
}

/// Full probabilities and analytic Jacobian. parallel=false is the general
/// cumulative model with K separate (intercept, slopes) blocks, used only to
/// evaluate the proportional-lines score test at the fitted null model.
pub fn probabilities(a: A, link: Link, b: []const f64, x: []const f64, k: usize, parallel: bool, p: []f64, jac: []f64) diag.Error!void {
    const q = b.len;
    if (k == 0 or x.len == 0 or p.len != k + 1 or jac.len != (k + 1) * q) return error.ExecError;
    if (q != (if (parallel) k + x.len - 1 else k * x.len)) return error.ExecError;
    @memset(jac, 0);
    if (link == .alogit) {
        if (!parallel) return error.ExecError;
        const features = try a.alloc(f64, (k + 1) * q);
        defer a.free(features);
        @memset(features, 0);
        var max_log: f64 = 0;
        for (0..k + 1) |c| {
            p[c] = 0;
            for (0..q) |j| {
                const feature: f64 = if (j < k) (if (c <= j) 1 else 0) else @as(f64, @floatFromInt(k - c)) * x[j - k + 1];
                features[c * q + j] = feature;
                p[c] += feature * b[j];
            }
            max_log = @max(max_log, p[c]);
        }
        var sum: f64 = 0;
        for (p) |*value| {
            value.* = @exp(value.* - max_log);
            sum += value.*;
        }
        for (p) |*value| value.* /= sum;
        for (0..q) |j| {
            var mean: f64 = 0;
            for (p, 0..) |value, c| mean += value * features[c * q + j];
            for (p, 0..) |value, c| jac[c * q + j] = value * (features[c * q + j] - mean);
        }
    } else {
        var previous: f64 = 0;
        for (0..k) |c| {
            var eta: f64 = if (parallel) b[c] else b[c * x.len];
            for (1..x.len) |j| eta += x[j] * b[if (parallel) k + j - 1 else c * x.len + j];
            const cumulative = cdf(link, eta);
            const f = density(link, eta);
            p[c] = cumulative - previous;
            previous = cumulative;
            for (0..x.len) |j| {
                const index = if (parallel) (if (j == 0) c else k + j - 1) else c * x.len + j;
                const derivative = f * x[j];
                jac[c * q + index] += derivative;
                jac[(c + 1) * q + index] -= derivative;
            }
        }
        p[k] = 1 - previous;
    }
    for (p) |value| if (!(value > 0) or !std.math.isFinite(value)) return error.ExecError;
}

const Evaluation = struct { ll: f64, gradient: []f64, information: []f64, probabilities: []f64 };
fn evaluate(a: A, link: Link, b: []const f64, x: []const f64, y: []const usize, pcols: usize, k: usize, multiplicity: []const f64, parallel: bool) diag.Error!Evaluation {
    const q = b.len;
    const gradient = try a.alloc(f64, q);
    const information = try a.alloc(f64, q * q);
    const probs = try a.alloc(f64, y.len * (k + 1));
    const jac = try a.alloc(f64, (k + 1) * q);
    defer a.free(jac);
    @memset(gradient, 0);
    @memset(information, 0);
    var ll: f64 = 0;
    for (y, 0..) |response, i| {
        const pi = probs[i * (k + 1) ..][0 .. k + 1];
        try probabilities(a, link, b, x[i * pcols ..][0..pcols], k, parallel, pi, jac);
        ll += multiplicity[i] * @log(pi[response]);
        for (0..q) |j| {
            gradient[j] += multiplicity[i] * jac[response * q + j] / pi[response];
            for (0..q) |h| for (pi, 0..) |value, c| {
                information[j * q + h] += multiplicity[i] * jac[c * q + j] * jac[c * q + h] / value;
            };
        }
    }
    return .{ .ll = ll, .gradient = gradient, .information = information, .probabilities = probs };
}

// The parallel-lines score uses the observed negative Hessian at the fitted
// restricted model (S154 physical pp.5918–5920), whereas Fisher scoring and
// coefficient covariance use expected information. These differ for ordinal
// cumulative links even though they coincide in the binary-logit case.
fn observedInformation(a: A, link: Link, b: []const f64, x: []const f64, y: []const usize, pcols: usize, k: usize, multiplicity: []const f64) diag.Error![]f64 {
    const q = b.len;
    const info = try a.alloc(f64, q * q);
    @memset(info, 0);
    const probabilities_ = try a.alloc(f64, k + 1);
    defer a.free(probabilities_);
    const jac = try a.alloc(f64, (k + 1) * q);
    defer a.free(jac);
    for (y, 0..) |response, i| {
        const row = x[i * pcols ..][0..pcols];
        try probabilities(a, link, b, row, k, false, probabilities_, jac);
        const p = probabilities_[response];
        for (0..q) |j| for (0..q) |h| {
            info[j * q + h] += multiplicity[i] * jac[response * q + j] * jac[response * q + h] / (p * p);
        };
        for (0..k) |cutpoint| {
            const sign: f64 = if (cutpoint == response) 1 else if (cutpoint + 1 == response) -1 else continue;
            const eta = dot(b[cutpoint * pcols ..][0..pcols], row);
            const second = sign * densityDerivative(link, eta);
            for (0..pcols) |j| for (0..pcols) |h| {
                info[(cutpoint * pcols + j) * q + cutpoint * pcols + h] -= multiplicity[i] * second * row[j] * row[h] / p;
            };
        }
    }
    return info;
}

/// SPD information solve via Cholesky, including a diagonal-scale rank check.
/// No regularization enters reported covariance; failed rank is an explicit error.
fn solve(a: A, matrix: []const f64, rhs: []const f64) diag.Error![]f64 {
    const n = rhs.len;
    if (matrix.len != n * n) return error.ExecError;
    const l = try a.alloc(f64, n * n);
    defer a.free(l);
    @memset(l, 0);
    for (0..n) |i| for (0..i + 1) |j| {
        var v = matrix[i * n + j];
        for (0..j) |h| v -= l[i * n + h] * l[j * n + h];
        if (i == j) {
            if (!(v > @abs(matrix[i * n + i]) * 1e-12)) return error.ExecError;
            l[i * n + j] = @sqrt(v);
        } else l[i * n + j] = v / l[j * n + j];
    };
    const result = try a.dupe(f64, rhs);
    for (0..n) |i| {
        for (0..i) |j| result[i] -= l[i * n + j] * result[j];
        result[i] /= l[i * n + i];
    }
    var i = n;
    while (i > 0) {
        i -= 1;
        for (i + 1..n) |j| result[i] -= l[j * n + i] * result[j];
        result[i] /= l[i * n + i];
    }
    return result;
}
fn dot(x: []const f64, y: []const f64) f64 {
    var sum: f64 = 0;
    for (x, y) |a, b| sum += a * b;
    return sum;
}
fn inverse(a: A, matrix: []const f64, n: usize) diag.Error![]f64 {
    const result = try a.alloc(f64, n * n);
    const rhs = try a.alloc(f64, n);
    defer a.free(rhs);
    for (0..n) |j| {
        @memset(rhs, 0);
        rhs[j] = 1;
        const column = try solve(a, matrix, rhs);
        defer a.free(column);
        for (0..n) |i| result[i * n + j] = column[i];
    }
    return result;
}

pub fn fit(a: A, link: Link, x: []const f64, y: []const usize, pcols: usize, levels: usize, frequencies: []const f64, weights: []const f64, options: binary.Options) diag.Error!Fit {
    if (levels < 2 or pcols == 0 or y.len == 0 or x.len != y.len * pcols or frequencies.len != y.len or weights.len != y.len or !(options.gconv > 0)) return error.ExecError;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    const k = levels - 1;
    const q = k + pcols - 1;
    const counts = try tmp.alloc(f64, levels);
    @memset(counts, 0);
    const multiplicity = try tmp.alloc(f64, y.len);
    var total: f64 = 0;
    for (y, 0..) |value, i| {
        if (value >= levels or x[i * pcols] != 1 or !(frequencies[i] > 0) or !(weights[i] > 0)) return error.ExecError;
        multiplicity[i] = frequencies[i] * weights[i];
        if (!std.math.isFinite(multiplicity[i])) return error.ExecError;
        counts[value] += multiplicity[i];
        total += multiplicity[i];
    }
    for (x) |value| if (!std.math.isFinite(value)) return error.ExecError;
    for (counts) |count| if (!(count > 0)) return error.ExecError;
    const b = try tmp.alloc(f64, q);
    @memset(b, 0);
    var cumulative: f64 = 0;
    for (0..k) |j| {
        cumulative += counts[j];
        b[j] = if (link == .alogit) @log(counts[j] / counts[j + 1]) else quantile(link, cumulative / total);
    }
    var null_ll: f64 = 0;
    for (counts) |count| null_ll += count * @log(count / total);
    var global_score: f64 = 0;
    var iteration = std.heap.ArenaAllocator.init(tmp);
    defer iteration.deinit();
    for (0..options.max_iterations) |iter| {
        _ = iteration.reset(.retain_capacity);
        const ia = iteration.allocator();
        const e = try evaluate(ia, link, b, x, y, pcols, k, multiplicity, true);
        const step = try solve(ia, e.information, e.gradient);
        const norm = dot(e.gradient, step);
        if (iter == 0) global_score = @max(0, norm);
        // S154 physical p.5912: after eight iterations, do not report a
        // finite converged fit for a completely separated observed response.
        if (iter > 8) {
            var separated = true;
            for (y, 0..) |response, i| {
                const row = e.probabilities[i * levels ..][0..levels];
                var largest: usize = 0;
                for (row, 0..) |probability_, c| if (probability_ > row[largest]) {
                    largest = c;
                };
                if (largest != response) separated = false;
            }
            if (separated) return error.ExecError;
        }
        if (norm >= 0 and norm / (@abs(e.ll) + 1e-6) <= options.gconv) {
            const cov = try inverse(a, e.information, q);
            var answer: Fit = .{ .levels = levels, .result = .{ .coefficients = try a.dupe(f64, b), .covariance = cov, .probabilities = try a.dupe(f64, e.probabilities), .log_likelihood = e.ll, .null_log_likelihood = null_ll, .score_test = global_score, .iterations = iter } };
            if (link != .alogit and k > 1 and pcols > 1) {
                const unrestricted = try ia.alloc(f64, k * pcols);
                for (0..k) |j| {
                    unrestricted[j * pcols] = b[j];
                    @memcpy(unrestricted[j * pcols + 1 ..][0 .. pcols - 1], b[k..]);
                }
                const general = try evaluate(ia, link, unrestricted, x, y, pcols, k, multiplicity, false);
                // Evaluate the documented score quadratic with the observed
                // Hessian. Sparse categories can restrict its identifiable
                // subspace; a range check below rejects inconsistent systems.
                const observed = try observedInformation(ia, link, unrestricted, x, y, pcols, k, multiplicity);
                var score_fit = try @import("reg_fit.zig").fit(ia, observed, general.gradient, unrestricted.len, unrestricted.len, null);
                defer score_fit.deinit(ia);
                // Solve in the identifiable subspace. Sparse observed categories
                // can make the Hessian singular; require an actual solution of
                // I*delta=g so an arbitrary least-squares projection cannot
                // fabricate a score. A generalized solution gives the same
                // quadratic for every nullspace representative when g is in
                // the range of the symmetric I.
                for (0..unrestricted.len) |j| {
                    const predicted = dot(observed[j * unrestricted.len ..][0..unrestricted.len], score_fit.coefficients);
                    var scale: f64 = @abs(general.gradient[j]);
                    for (0..unrestricted.len) |h| scale += @abs(observed[j * unrestricted.len + h] * score_fit.coefficients[h]);
                    if (@abs(predicted - general.gradient[j]) > 512 * std.math.floatEps(f64) * @as(f64, @floatFromInt(unrestricted.len)) * @max(1, scale)) return error.ExecError;
                }
                const quadratic = dot(general.gradient, score_fit.coefficients);
                if (!std.math.isFinite(quadratic) or quadratic < -512 * std.math.floatEps(f64) * @max(1, dot(general.gradient, general.gradient))) return error.ExecError;
                answer.parallel_score = @max(0, quadratic);
                answer.parallel_df = (k - 1) * (pcols - 1);
            }
            return answer;
        }
        const candidate = try ia.alloc(f64, q);
        var accepted = false;
        // SAS default relative ridging: retry with increasing diagonal penalty
        // when an update makes cumulative probabilities invalid or decreases LL.
        var ridge: f64 = 0;
        for (0..40) |_| {
            const adjustment = if (ridge == 0) step else blk: {
                const penalized = try ia.dupe(f64, e.information);
                for (0..q) |j| penalized[j * q + j] *= 1 + ridge;
                break :blk try solve(ia, penalized, e.gradient);
            };
            for (0..q) |j| candidate[j] = b[j] + adjustment[j];
            const next = evaluate(ia, link, candidate, x, y, pcols, k, multiplicity, true) catch |err| {
                if (err == error.OutOfMemory) return err;
                ridge = if (ridge == 0) 0.0001 else ridge * 2;
                continue;
            };
            if (next.ll >= e.ll) {
                accepted = true;
                break;
            }
            ridge = if (ridge == 0) 0.0001 else ridge * 2;
        }
        if (!accepted) return error.ExecError;
        @memcpy(b, candidate);
    }
    return error.ExecError;
}

/// S154 physical p.5918: ordinal predicted mean scores use zero-based ordered
/// values; default bins have width (levels-1)/500. FREQ, not WEIGHT, counts pairs.
pub fn association(a: A, y: []const f64, probabilities_: []const f64, levels: usize, frequencies: []const f64) diag.Error!binary.WeightedAssociation {
    if (levels < 3 or probabilities_.len != y.len * levels or frequencies.len != y.len) return error.ExecError;
    const bins = try a.alloc(f64, y.len);
    defer a.free(bins);
    const width = @as(f64, @floatFromInt(levels - 1)) / 500;
    for (bins, 0..) |*bin, i| {
        var mean: f64 = 0;
        for (0..levels) |c| mean += @as(f64, @floatFromInt(c)) * probabilities_[i * levels + c];
        bin.* = @floor(mean / width);
    }
    var result: binary.WeightedAssociation = .{};
    for (y, 0..) |first, i| for (y[i + 1 ..], i + 1..) |second, j| {
        if (first == second) continue;
        const count = frequencies[i] * frequencies[j];
        result.pairs += count;
        const lower = if (first < second) bins[i] else bins[j];
        const higher = if (first < second) bins[j] else bins[i];
        if (lower < higher) result.concordant += count else if (lower > higher) result.discordant += count else result.tied += count;
    };
    return result;
}

test "LOGISTIC007 saturated multinomial intercepts covariance and probabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]Link{ .logit, .probit, .cloglog, .alogit }) |link| {
        const result = try fit(a, link, &.{ 1, 1, 1 }, &.{ 0, 1, 2 }, 1, 3, &.{ 2, 3, 5 }, &.{ 1, 1, 1 }, .{});
        const r = result.result;
        for (0..3) |i| for ([_]f64{ 0.2, 0.3, 0.5 }, 0..) |p, c| try std.testing.expectApproxEqAbs(p, r.probabilities[i * 3 + c], 1e-12);
        try std.testing.expectApproxEqAbs(2 * @log(@as(f64, 0.2)) + 3 * @log(@as(f64, 0.3)) + 5 * @log(@as(f64, 0.5)), r.log_likelihood, 1e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0), r.score_test, 1e-20);
        try std.testing.expect(result.parallel_score == null);
        if (link == .alogit) {
            try std.testing.expectApproxEqAbs(@log(@as(f64, 2.0 / 3.0)), r.coefficients[0], 1e-12);
            try std.testing.expectApproxEqAbs(@log(@as(f64, 3.0 / 5.0)), r.coefficients[1], 1e-12);
            // Delta method for log(n0/n1), log(n1/n2); shared middle
            // category makes the off-diagonal covariance negative.
            for ([_]f64{ 1.0 / 2.0 + 1.0 / 3.0, -1.0 / 3.0, -1.0 / 3.0, 1.0 / 3.0 + 1.0 / 5.0 }, r.covariance) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
        } else {
            // Multinomial empirical CDF covariance (min(Fi,Fj)-FiFj)/N,
            // transformed by inverse-CDF derivatives. 1e-12 covers f64
            // arithmetic and Cholesky in this well-conditioned 2x2 case.
            const cumulative = [_]f64{ 0.2, 0.5 };
            for (cumulative, 0..) |fi, i| {
                const alpha = switch (link) {
                    .logit => @log(fi / (1 - fi)),
                    .probit => if (i == 0) -0.8416212335729143 else @as(f64, 0),
                    .cloglog => @log(-@log(1 - fi)),
                    .alogit => unreachable,
                };
                try std.testing.expectApproxEqAbs(alpha, r.coefficients[i], 1e-12);
                const di = switch (link) {
                    .logit => fi * (1 - fi),
                    .probit => @exp(-alpha * alpha / 2) / @sqrt(2 * std.math.pi),
                    .cloglog => -(1 - fi) * @log(1 - fi),
                    .alogit => unreachable,
                };
                for (cumulative, 0..) |fj, j| {
                    const aj = r.coefficients[j];
                    const dj = switch (link) {
                        .logit => fj * (1 - fj),
                        .probit => @exp(-aj * aj / 2) / @sqrt(2 * std.math.pi),
                        .cloglog => -(1 - fj) * @log(1 - fj),
                        .alogit => unreachable,
                    };
                    try std.testing.expectApproxEqAbs((@min(fi, fj) - fi * fj) / (10 * di * dj), r.covariance[2 * i + j], 1e-12);
                }
            }
        }
    }
}

test "LOGISTIC007 analytic probability derivatives and boundary failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]Link{ .logit, .probit, .cloglog, .alogit }) |link| {
        const b = [_]f64{ -0.7, 0.8, 0.4 };
        var p: [3]f64 = undefined;
        var jac: [9]f64 = undefined;
        try probabilities(a, link, &b, &.{ 1, 0.7 }, 2, true, &p, &jac);
        try std.testing.expectApproxEqAbs(@as(f64, 1), p[0] + p[1] + p[2], 1e-14);
        for (0..3) |j| {
            var plus = b;
            var minus = b;
            const h = 1e-5;
            plus[j] += h;
            minus[j] -= h;
            var pp: [3]f64 = undefined;
            var pm: [3]f64 = undefined;
            var unused: [9]f64 = undefined;
            try probabilities(a, link, &plus, &.{ 1, 0.7 }, 2, true, &pp, &unused);
            try probabilities(a, link, &minus, &.{ 1, 0.7 }, 2, true, &pm, &unused);
            for (0..3) |c| try std.testing.expectApproxEqAbs((pp[c] - pm[c]) / (2 * h), jac[c * 3 + j], 2e-9); // O(h²) + eps/h
        }
    }
    try std.testing.expectError(error.ExecError, fit(a, .logit, &.{ 1, 1 }, &.{ 0, 2 }, 1, 3, &.{ 2, 5 }, &.{ 1, 1 }, .{}));
    try std.testing.expectError(error.ExecError, fit(a, .logit, &.{ 1, 0, 1, 0, 1, 0 }, &.{ 0, 1, 2 }, 2, 3, &.{ 2, 3, 5 }, &.{ 1, 1, 1 }, .{}));
    try std.testing.expectError(error.ExecError, fit(a, .logit, &.{ 1, 1, 1 }, &.{ 0, 1, 2 }, 1, 3, &.{ 2, 3, 5 }, &.{ 1, 1, 1 }, .{ .max_iterations = 0 }));
    try std.testing.expectError(error.ExecError, fit(a, .logit, &.{ 1, 0, 1, 1, 1, 2 }, &.{ 0, 1, 2 }, 2, 3, &.{ 1, 1, 1 }, &.{ 1, 1, 1 }, .{}));
}

test "LOGISTIC007 observed cumulative Hessian matches derivative of full score" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, -0.3, 1, 0.4, 1, 1.1 };
    const y = [_]usize{ 0, 1, 2 };
    const frequencies = [_]f64{ 2, 3, 5 };
    // Separate cutpoint slopes, evaluated inside the common-slope null.
    const b = [_]f64{ -0.7, 0.2, 0.8, 0.2 };
    for ([_]Link{ .logit, .probit, .cloglog }) |link| {
        const info = try observedInformation(a, link, &b, &x, &y, 2, 2, &frequencies);
        for (0..4) |j| {
            var plus = b;
            var minus = b;
            const h = 1e-5;
            plus[j] += h;
            minus[j] -= h;
            const ep = try evaluate(a, link, &plus, &x, &y, 2, 2, &frequencies, false);
            const em = try evaluate(a, link, &minus, &x, &y, 2, 2, &frequencies, false);
            for (0..4) |i| {
                // Central differences: O(h²) truncation plus eps/h cancellation.
                try std.testing.expectApproxEqAbs(-(ep.gradient[i] - em.gradient[i]) / (2 * h), info[i * 4 + j], 2e-8);
                try std.testing.expectApproxEqAbs(info[j * 4 + i], info[i * 4 + j], 1e-13);
            }
        }
    }
}

test "LOGISTIC007 closed-form cumulative slope and frequency weight likelihood equivalence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1 };
    const y = [_]usize{ 0, 1, 2, 0, 1, 2 };
    const frequencies = [_]f64{ 2, 3, 5, 5, 3, 2 };
    // Two empirical distributions (0.2,0.3,0.5) and (0.5,0.3,0.2)
    // exactly lie on a common cumulative-logit shift of log(4).
    const result = try fit(a, .logit, &x, &y, 2, 3, &frequencies, &.{ 1, 1, 1, 1, 1, 1 }, .{ .gconv = 1e-14 });
    const expected = [_]f64{ -@log(@as(f64, 4)), 0, @log(@as(f64, 4)) };
    for (expected, result.result.coefficients) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0), result.parallel_score.?, 1e-12);
    const weighted = try fit(a, .logit, &x, &y, 2, 3, &.{ 1, 1, 1, 1, 1, 1 }, &frequencies, .{ .gconv = 1e-14 });
    try std.testing.expectEqualSlices(f64, result.result.coefficients, weighted.result.coefficients);
    try std.testing.expectEqualSlices(f64, result.result.covariance, weighted.result.covariance);
    try std.testing.expectEqual(result.result.log_likelihood, weighted.result.log_likelihood);
    // Independent expected-information evaluation from the empirical CDFs,
    // then verify every element of I Cov = identity (not just diagonals).
    var info = [_]f64{0} ** 9;
    for ([_][2]f64{ .{ 0.2, 0.5 }, .{ 0.5, 0.8 } }, 0..) |f, group| {
        const d1 = f[0] * (1 - f[0]);
        const d2 = f[1] * (1 - f[1]);
        const g: f64 = @floatFromInt(group);
        const jac = [_][3]f64{ .{ d1, 0, d1 * g }, .{ -d1, d2, (d2 - d1) * g }, .{ 0, -d2, -d2 * g } };
        for ([_]f64{ f[0], f[1] - f[0], 1 - f[1] }, jac) |p, derivative| for (0..3) |i| for (0..3) |j| {
            info[3 * i + j] += 10 * derivative[i] * derivative[j] / p;
        };
    }
    for (0..3) |i| for (0..3) |j| {
        var product: f64 = 0;
        for (0..3) |k| product += info[3 * i + k] * result.result.covariance[3 * k + j];
        try std.testing.expectApproxEqAbs(@as(f64, if (i == j) 1 else 0), product, 1e-7);
    };
}
