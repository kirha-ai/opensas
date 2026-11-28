//! PROC GENMOD (SAS/STAT 15.4 ch.51) — STAT-GENMOD-002: maximum likelihood fit
//! of the Normal generalized linear model with an identity or log link and the
//! scale (sigma) estimated by maximum likelihood.
//!
//! Formulas (Details: "Log-Likelihood Functions", "Maximum Likelihood Fitting",
//! "Goodness of Fit", "Dispersion Parameter"), with f the FREQ value:
//!   l(beta, sigma) = -1/2 sum f [ (y-mu)^2/sigma^2 + log(sigma^2) + log(2 pi) ]
//!   gradient_j     = sum f (y-mu) mu'(eta) x_j / sigma^2
//!   -Hessian_jk    = sum f [ mu'^2 - (y-mu) mu'' ] x_j x_k / sigma^2   (observed)
//!   sigma^2        = sum f (y-mu)^2 / sum f                             (ML)
//!   deviance = Pearson chi-square = sum f (y-mu)^2 (unit variance function)
//! The covariance is the inverse OBSERVED information (GENMOD's Newton-Raphson
//! default); beta and sigma are orthogonal at the estimate because the cross
//! derivative is proportional to the beta score, which is zero there.
//!
//! ponytail: Normal only. Other distributions/links, WEIGHT, OFFSET, CLASS
//! designs and aliased columns are loud gaps in genmod.zig, not handled here.
//! ponytail: iterates to the numerical maximum (relative step < 1e-9) rather
//! than stopping at SAS's default CONVERGE=1E-4 iterate; with quadratic
//! convergence the two agree far below the printed 4 decimals.
const std = @import("std");
const convergence = @import("convergence_status.zig");
const A = std.mem.Allocator;

pub const Link = enum { identity, log };
pub const Error = error{ OutOfMemory, Singular, NotConverged, InvalidStart };

pub const Fit = struct {
    p: usize,
    /// Sum of frequencies.
    n: f64,
    beta: []f64,
    /// p*p row-major covariance of beta.
    cov: []f64,
    mu: []f64,
    scale: f64,
    scale_se: f64,
    deviance: f64,
    loglik: f64,
    iterations: usize,
    state: convergence.State,
};

fn mean(link: Link, e: f64) f64 {
    return switch (link) {
        .identity => e,
        .log => @exp(e),
    };
}

fn eta(x: []const f64, p: usize, i: usize, beta: []const f64) f64 {
    var s: f64 = 0;
    for (0..p) |j| s += x[i * p + j] * beta[j];
    return s;
}

/// Residual sum of squares sum f (y-mu)^2.
pub fn sse(x: []const f64, y: []const f64, f: []const f64, p: usize, link: Link, beta: []const f64) f64 {
    var s: f64 = 0;
    for (y, f, 0..) |yi, fi, i| {
        const r = yi - mean(link, eta(x, p, i, beta));
        s += fi * r * r;
    }
    return s;
}

/// Log likelihood at arbitrary (beta, sigma); used by the fit and by the
/// finite-difference checks of the score and information.
pub fn logLik(x: []const f64, y: []const f64, f: []const f64, p: usize, link: Link, beta: []const f64, sigma: f64) f64 {
    var n: f64 = 0;
    for (f) |fi| n += fi;
    const v = sigma * sigma;
    return -0.5 * (sse(x, y, f, p, link, beta) / v + n * @log(2 * std.math.pi * v));
}

/// Unscaled score g = sum f (y-mu) mu' x and unscaled information
/// h = sum f [mu'^2 - (y-mu) mu''] x x' (observed) or sum f mu'^2 x x' (expected).
pub fn scoreInformation(x: []const f64, y: []const f64, f: []const f64, p: usize, link: Link, beta: []const f64, observed: bool, g: []f64, h: []f64) void {
    @memset(g, 0);
    @memset(h, 0);
    for (y, f, 0..) |yi, fi, i| {
        const e = eta(x, p, i, beta);
        const m = mean(link, e);
        const d1: f64 = if (link == .log) m else 1;
        const d2: f64 = if (link == .log) m else 0;
        const r = yi - m;
        const w = fi * (d1 * d1 - (if (observed) r * d2 else 0));
        for (0..p) |j| {
            g[j] += fi * r * d1 * x[i * p + j];
            for (0..p) |k| h[j * p + k] += w * x[i * p + j] * x[i * p + k];
        }
    }
}

/// In-place Cholesky factor (lower) of a symmetric p*p matrix. False when the
/// matrix is not positive definite relative to its own diagonal.
pub fn cholesky(m: []f64, p: usize) bool {
    for (0..p) |j| {
        const original = m[j * p + j];
        var d = original;
        for (0..j) |k| d -= m[j * p + k] * m[j * p + k];
        if (!(d > 1e-12 * @abs(original)) or !(original > 0)) return false;
        const l = @sqrt(d);
        m[j * p + j] = l;
        for (j + 1..p) |i| {
            var s = m[i * p + j];
            for (0..j) |k| s -= m[i * p + k] * m[j * p + k];
            m[i * p + j] = s / l;
        }
    }
    return true;
}

pub fn choleskySolve(l: []const f64, p: usize, b: []f64) void {
    for (0..p) |i| {
        var s = b[i];
        for (0..i) |k| s -= l[i * p + k] * b[k];
        b[i] = s / l[i * p + i];
    }
    var i = p;
    while (i > 0) {
        i -= 1;
        var s = b[i];
        for (i + 1..p) |k| s -= l[k * p + i] * b[k];
        b[i] = s / l[i * p + i];
    }
}

/// `x` is the n*p row-major design INCLUDING the intercept column.
pub fn fitNormal(a: A, x: []const f64, y: []const f64, f: []const f64, p: usize, link: Link) Error!Fit {
    const rows = y.len;
    std.debug.assert(x.len == rows * p and f.len == rows and p > 0);
    var n: f64 = 0;
    var ybar: f64 = 0;
    for (y, f) |yi, fi| {
        n += fi;
        ybar += fi * yi;
    }
    if (!(n > 0)) return error.InvalidStart;
    ybar /= n;
    const beta = try a.alloc(f64, p);
    @memset(beta, 0);
    if (link == .log) {
        // Intercept-only start at the marginal mean; needs a positive mean.
        if (!(ybar > 0)) return error.InvalidStart;
        beta[0] = @log(ybar);
    }
    const g = try a.alloc(f64, p);
    const h = try a.alloc(f64, p * p);
    const trial = try a.alloc(f64, p);
    var current = sse(x, y, f, p, link, beta);
    var iterations: usize = 0;
    var converged = false;
    while (iterations < 200) {
        iterations += 1;
        scoreInformation(x, y, f, p, link, beta, true, g, h);
        if (!cholesky(h, p)) {
            // Ridge-free fallback: the expected information is X'WX with W > 0.
            scoreInformation(x, y, f, p, link, beta, false, g, h);
            if (!cholesky(h, p)) return error.Singular;
        }
        choleskySolve(h, p, g); // g now holds the Newton step
        var step: f64 = 1;
        var next = current;
        var halvings: usize = 0;
        while (true) : (halvings += 1) {
            for (trial, beta, g) |*tv, bv, gv| tv.* = bv + step * gv;
            next = sse(x, y, f, p, link, trial);
            if (std.math.isFinite(next) and next <= current * (1 + 1e-12) + 1e-300) break;
            if (halvings == 40) return error.NotConverged;
            step /= 2;
        }
        var change: f64 = 0;
        for (trial, beta) |tv, bv| change = @max(change, @abs(tv - bv) / (@abs(tv) + 1e-6));
        @memcpy(beta, trial);
        current = next;
        if (convergence.meets(change, 1e-9, true)) {
            converged = true;
            break;
        }
    }
    if (!converged) return error.NotConverged;

    const cov = try a.alloc(f64, p * p);
    scoreInformation(x, y, f, p, link, beta, true, g, h);
    if (!cholesky(h, p)) return error.Singular;
    const variance = current / n;
    for (0..p) |j| {
        @memset(trial, 0);
        trial[j] = 1;
        choleskySolve(h, p, trial);
        for (0..p) |k| cov[k * p + j] = variance * trial[k];
    }
    const mu = try a.alloc(f64, rows);
    for (mu, 0..) |*m, i| m.* = mean(link, eta(x, p, i, beta));
    const sigma = @sqrt(variance);
    return .{
        .p = p,
        .n = n,
        .beta = beta,
        .cov = cov,
        .mu = mu,
        .scale = sigma,
        // -d2l/dsigma2 at the maximum is 2n/sigma^2.
        .scale_se = sigma / @sqrt(2 * n),
        .deviance = current,
        .loglik = -0.5 * n * (@log(2 * std.math.pi * variance) + 1),
        .iterations = iterations,
        .state = .{ .outcome = .converged, .estimates = .solution },
    };
}

/// WEIGHT statement (p.3567): the dispersion is divided by w_i, so the fit
/// minimizes sum f w (y-mu)^2 while n stays the frequency sum. Verified against
/// SAS 9.4: sigma^2 = sum f w r^2 / sum f, and the log likelihood gains
/// +0.5 sum f log w_i.
pub fn fitNormalWeighted(a: A, x: []const f64, y: []const f64, f: []const f64, w: ?[]const f64, p: usize, link: Link) Error!Fit {
    const weights = w orelse return fitNormal(a, x, y, f, p, link);
    std.debug.assert(weights.len == f.len);
    const fw = try a.alloc(f64, f.len);
    var n: f64 = 0;
    var log_w: f64 = 0;
    for (fw, f, weights) |*v, fi, wi| {
        v.* = fi * wi;
        n += fi;
        log_w += fi * @log(wi);
    }
    var r = try fitNormal(a, x, y, fw, p, link);
    const old_variance = r.scale * r.scale;
    const variance = r.deviance / n;
    for (r.cov) |*c| c.* *= variance / old_variance;
    r.n = n;
    r.scale = @sqrt(variance);
    r.scale_se = r.scale / @sqrt(2 * n);
    r.loglik = -0.5 * n * (@log(2 * std.math.pi * variance) + 1) + 0.5 * log_w;
    return r;
}

test {
    _ = @import("genmod_fit_tests.zig");
}
