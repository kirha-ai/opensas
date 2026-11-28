//! PROC GENMOD (SAS/STAT 15.4 ch.51) — STAT-GENMOD-003: events/trials binomial
//! model with the logit link, aliased-column detection for the GLM-style CLASS
//! parameterization, and likelihood-ratio (profile) confidence limits.
//!
//! Formulas (physical PDF pp.3572–3577 "Log-Likelihood Functions" and
//! "Goodness of Fit", pp.3580–3581 "Parameterization Used in PROC GENMOD",
//! pp.3583–3584 "Likelihood Ratio-Based Confidence Intervals"), scale fixed at 1,
//! no FREQ/WEIGHT, p_i = 1/(1+exp(-x_i'beta)):
//!   l      = sum [ r log p + (n-r) log(1-p) ]            ("Log Likelihood")
//!   ll     = l + sum log C(n, r)                         ("Full Log Likelihood")
//!   score  = X'(r - n p),  information = X' diag(n p (1-p)) X
//!            (the logit link is canonical: observed = expected information)
//!   D      = 2 sum [ r log(r/(n p)) + (n-r) log((n-r)/(n(1-p))) ], 0 log 0 = 0
//!   X2     = sum (r - n p)^2 / (n p (1-p))
//!   limit  : l*(b_j) = l_max - chi2(1-alpha; 1)/2, l* the profile log likelihood
//!
//! Aliasing: "The columns of X'X are checked in the order in which the model is
//! specified for dependence on preceding columns"; a pivot must be at least
//! SINGULAR= times the original diagonal (default 1E7 * machine epsilon).
//!
//! Limits: `quadraticLimit` is the documented quadratic-surface iteration with
//! the documented CICONV stopping rule; `profileLimit` (bracketing and bisection
//! on b_j with an inner Newton maximization) solves the same equation to full
//! precision and is the fallback when the quadratic iteration fails.
//! ponytail: iterates to the numerical maximum rather than SAS's CONVERGE=1E-4
//! iterate (same disclosure as genmod_fit.zig).
const std = @import("std");
const normal = @import("genmod_fit.zig");
const A = std.mem.Allocator;

pub const Error = error{ OutOfMemory, Singular, NotConverged, Unbounded };

/// SINGULAR= default (p.3554): 1E7 times the machine epsilon.
pub const singular_default: f64 = 1e7 * std.math.floatEps(f64);

/// MODEL statement (p.3544): "The values of both events and (trials-events)
/// must be nonnegative, and the value of the trials variable must be greater
/// than 0 for an observation to be valid."
pub fn validObservation(r: f64, n: f64) bool {
    return r >= 0 and n - r >= 0 and n > 0;
}

fn eta(x: []const f64, q: usize, i: usize, beta: []const f64) f64 {
    var s: f64 = 0;
    for (0..q) |j| s += x[i * q + j] * beta[j];
    return s;
}
fn logP(e: f64) f64 {
    return @min(e, 0) - std.math.log1p(@exp(-@abs(e)));
}
pub fn probability(e: f64) f64 {
    return if (e >= 0) 1 / (1 + @exp(-e)) else @exp(e) / (1 + @exp(e));
}

/// l(beta) = sum r log p + (n-r) log(1-p), binomial coefficients dropped.
pub fn logLik(x: []const f64, r: []const f64, n: []const f64, q: usize, beta: []const f64) f64 {
    var s: f64 = 0;
    for (r, n, 0..) |ri, ni, i| {
        const e = eta(x, q, i, beta);
        s += ri * logP(e) + (ni - ri) * logP(-e);
    }
    return s;
}

/// sum log C(n, r): the data-only term of the full log likelihood.
pub fn logCoefficients(r: []const f64, n: []const f64) f64 {
    var s: f64 = 0;
    for (r, n) |ri, ni| s += std.math.lgamma(f64, ni + 1) - std.math.lgamma(f64, ri + 1) - std.math.lgamma(f64, ni - ri + 1);
    return s;
}

/// g = X'(r - n p), h = X' diag(n p (1-p)) X (row-major q*q).
pub fn scoreInformation(x: []const f64, r: []const f64, n: []const f64, q: usize, beta: []const f64, g: []f64, h: []f64) void {
    @memset(g, 0);
    @memset(h, 0);
    for (r, n, 0..) |ri, ni, i| {
        const p = probability(eta(x, q, i, beta));
        const w = ni * p * (1 - p);
        for (0..q) |j| {
            g[j] += (ri - ni * p) * x[i * q + j];
            for (0..q) |k| h[j * q + k] += w * x[i * q + j] * x[i * q + k];
        }
    }
}

fn xlogy(v: f64, ratio: f64) f64 {
    return if (v == 0) 0 else v * @log(ratio);
}
pub fn deviance(x: []const f64, r: []const f64, n: []const f64, q: usize, beta: []const f64) f64 {
    var s: f64 = 0;
    for (r, n, 0..) |ri, ni, i| {
        const p = probability(eta(x, q, i, beta));
        s += xlogy(ri, ri / (ni * p)) + xlogy(ni - ri, (ni - ri) / (ni * (1 - p)));
    }
    return 2 * s;
}
pub fn pearson(x: []const f64, r: []const f64, n: []const f64, q: usize, beta: []const f64) f64 {
    var s: f64 = 0;
    for (r, n, 0..) |ri, ni, i| {
        const p = probability(eta(x, q, i, beta));
        s += (ri - ni * p) * (ri - ni * p) / (ni * p * (1 - p));
    }
    return s;
}

/// Flags the columns of the rows*p design that depend linearly on preceding
/// columns (true = aliased), by a sequential Cholesky pass over X'X in model
/// order with the documented relative pivot tolerance.
pub fn aliased(a: A, x: []const f64, rows: usize, p: usize, singular: f64) error{OutOfMemory}![]bool {
    const m = try a.alloc(f64, p * p);
    @memset(m, 0);
    for (0..rows) |i| for (0..p) |j| for (0..p) |k| {
        m[j * p + k] += x[i * p + j] * x[i * p + k];
    };
    const flags = try a.alloc(bool, p);
    for (0..p) |j| {
        const original = m[j * p + j];
        var d = original;
        for (0..j) |k| {
            if (!flags[k]) d -= m[j * p + k] * m[j * p + k];
        }
        flags[j] = !(original > 0) or !(d >= singular * original);
        if (flags[j]) continue;
        const l = @sqrt(d);
        m[j * p + j] = l;
        for (j + 1..p) |i| {
            var s = m[i * p + j];
            for (0..j) |k| {
                if (!flags[k]) s -= m[i * p + k] * m[j * p + k];
            }
            m[i * p + j] = s / l;
        }
    }
    return flags;
}

/// Newton-Raphson maximization of l over the free coordinates; `fixed` holds
/// one coordinate at its current value (profile likelihood). `beta` is the
/// start and receives the maximizer. Returns the maximized log likelihood.
pub fn maximize(a: A, x: []const f64, r: []const f64, n: []const f64, q: usize, beta: []f64, fixed: ?usize) Error!f64 {
    const m = if (fixed != null) q - 1 else q;
    const g = try a.alloc(f64, q);
    const h = try a.alloc(f64, q * q);
    const gr = try a.alloc(f64, m);
    const hr = try a.alloc(f64, m * m);
    const trial = try a.alloc(f64, q);
    var current = logLik(x, r, n, q, beta);
    if (m == 0) return current;
    var iterations: usize = 0;
    while (iterations < 200) : (iterations += 1) {
        scoreInformation(x, r, n, q, beta, g, h);
        var jr: usize = 0;
        for (0..q) |j| {
            if (fixed == j) continue;
            gr[jr] = g[j];
            var kr: usize = 0;
            for (0..q) |k| {
                if (fixed == k) continue;
                hr[jr * m + kr] = h[j * q + k];
                kr += 1;
            }
            jr += 1;
        }
        if (!normal.cholesky(hr, m)) return error.Singular;
        normal.choleskySolve(hr, m, gr);
        var step: f64 = 1;
        var next = current;
        var halvings: usize = 0;
        while (true) : (halvings += 1) {
            jr = 0;
            for (0..q) |j| {
                if (fixed == j) {
                    trial[j] = beta[j];
                } else {
                    trial[j] = beta[j] + step * gr[jr];
                    jr += 1;
                }
            }
            next = logLik(x, r, n, q, trial);
            if (std.math.isFinite(next) and next >= current - 1e-12 * @abs(current)) break;
            if (halvings == 40) return error.NotConverged;
            step /= 2;
        }
        var change: f64 = 0;
        for (trial, beta) |tv, bv| {
            change = @max(change, @abs(tv - bv) / @max(1, @abs(tv)));
            // A coefficient running away means the maximum is at infinity (separation).
            if (@abs(tv) > 1e3) return error.NotConverged;
        }
        @memcpy(beta, trial);
        current = next;
        if (change < 1e-11) return current;
    }
    return error.NotConverged;
}

pub const Fit = struct {
    q: usize,
    beta: []f64,
    /// q*q row-major inverse information.
    cov: []f64,
    loglik: f64,
    full_loglik: f64,
    deviance: f64,
    pearson: f64,
};

/// `x` is the rows*q row-major FULL-RANK design (aliased columns removed).
pub fn fitLogit(a: A, x: []const f64, r: []const f64, n: []const f64, q: usize) Error!Fit {
    std.debug.assert(x.len == r.len * q and r.len == n.len and q > 0);
    const beta = try a.alloc(f64, q);
    @memset(beta, 0);
    const l = try maximize(a, x, r, n, q, beta, null);
    const g = try a.alloc(f64, q);
    const h = try a.alloc(f64, q * q);
    scoreInformation(x, r, n, q, beta, g, h);
    if (!normal.cholesky(h, q)) return error.Singular;
    const cov = try a.alloc(f64, q * q);
    for (0..q) |j| {
        @memset(g, 0);
        g[j] = 1;
        normal.choleskySolve(h, q, g);
        for (0..q) |k| cov[k * q + j] = g[k];
    }
    return .{ .q = q, .beta = beta, .cov = cov, .loglik = l, .full_loglik = l + logCoefficients(r, n), .deviance = deviance(x, r, n, q, beta), .pearson = pearson(x, r, n, q, beta) };
}

/// Profile log likelihood l*(b) for coordinate j. `work` is the warm start and
/// receives the constrained maximizer.
pub fn profile(a: A, x: []const f64, r: []const f64, n: []const f64, q: usize, j: usize, b: f64, work: []f64) Error!f64 {
    work[j] = b;
    return maximize(a, x, r, n, q, work, j);
}

/// One endpoint of the likelihood-ratio confidence interval for coordinate j:
/// the b on the requested side of the estimate with
/// 2 (l_max - l*(b)) = chi (chi = chi-square(1-alpha; 1) quantile).
/// error.Unbounded: the profile never drops that far (no finite endpoint).
pub fn profileLimit(a: A, x: []const f64, r: []const f64, n: []const f64, f: Fit, j: usize, upper: bool, chi: f64) Error!f64 {
    const q = f.q;
    const target = f.loglik - 0.5 * chi;
    const sign: f64 = if (upper) 1 else -1;
    const se = @sqrt(f.cov[j * q + j]);
    const work = try a.alloc(f64, q);
    @memcpy(work, f.beta);
    var inside = f.beta[j]; // l* >= target
    var width = @sqrt(chi) * se;
    var outside = inside;
    var found = false;
    for (0..40) |_| {
        outside = f.beta[j] + sign * width;
        const l = profile(a, x, r, n, q, j, outside, work) catch |err| switch (err) {
            error.NotConverged => return error.Unbounded,
            else => return err,
        };
        if (l < target) {
            found = true;
            break;
        }
        inside = outside;
        width *= 1.5;
    }
    if (!found) return error.Unbounded;
    @memcpy(work, f.beta);
    for (0..200) |_| {
        const mid = inside + (outside - inside) / 2;
        if (mid == inside or mid == outside) break;
        const l = try profile(a, x, r, n, q, j, mid, work);
        if (l >= target) inside = mid else outside = mid;
        if (@abs(outside - inside) <= 1e-13 * @max(1, @abs(mid))) break;
    }
    return inside + (outside - inside) / 2;
}

/// CICONV= default (p.3546).
pub const ciconv_default: f64 = 1e-4;

/// The documented endpoint iteration (pp.3583-3584): starting at the maximum
/// likelihood estimate, the log likelihood is replaced by its quadratic
/// approximation l + d'g - d'Id/2 (g the gradient, I the information), for
/// which the constrained problem has the exact solution
///   d = I^-1 (g + lambda u_j),  lambda^2 = 2 (l - l0 + g'I^-1 g / 2) / (I^-1)_jj,
/// lambda > 0 for the upper endpoint. Iteration stops when |l - l0| <= ciconv
/// and (g + lambda u_j)' I^-1 (g + lambda u_j) <= ciconv, the two documented
/// conditions. Returns null when the iteration leaves the region where the
/// quadratic has a solution or does not converge; callers then use profileLimit.
pub fn quadraticLimit(a: A, x: []const f64, r: []const f64, n: []const f64, f: Fit, j: usize, upper: bool, chi: f64, ciconv: f64) error{OutOfMemory}!?f64 {
    const q = f.q;
    const target = f.loglik - 0.5 * chi;
    const beta = try a.alloc(f64, q);
    @memcpy(beta, f.beta);
    const g = try a.alloc(f64, q);
    const h = try a.alloc(f64, q * q);
    const vg = try a.alloc(f64, q);
    const ve = try a.alloc(f64, q);
    for (0..50) |_| {
        const l = logLik(x, r, n, q, beta);
        if (!std.math.isFinite(l)) return null;
        scoreInformation(x, r, n, q, beta, g, h);
        if (!normal.cholesky(h, q)) return null;
        @memcpy(vg, g);
        normal.choleskySolve(h, q, vg);
        @memset(ve, 0);
        ve[j] = 1;
        normal.choleskySolve(h, q, ve);
        var gvg: f64 = 0;
        for (g, vg) |gv, v| gvg += gv * v;
        const square = 2 * (l - target + 0.5 * gvg) / ve[j];
        if (!(square > 0)) return null;
        const lambda = if (upper) @sqrt(square) else -@sqrt(square);
        // (g + lambda u)' I^-1 (g + lambda u) = g'I^-1 g + 2 lambda (I^-1 g)_j + lambda^2 (I^-1)_jj
        const residual = gvg + 2 * lambda * vg[j] + lambda * lambda * ve[j];
        if (@abs(l - target) <= ciconv and residual <= ciconv) return beta[j];
        for (beta, vg, ve) |*b, v, e| {
            b.* += v + lambda * e;
            if (@abs(b.*) > 1e3) return null;
        }
    }
    return null;
}

test {
    _ = @import("genmod_binomial_tests.zig");
}
