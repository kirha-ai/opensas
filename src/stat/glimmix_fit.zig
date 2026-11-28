//! PROC GLIMMIX default estimation kernel (STAT-GLIMMIX-002): binomial
//! events/trials response, logit link, one G-side random intercept per
//! subject, METHOD=RSPL. S154 physical pp.3830-3832 ("Pseudo-likelihood
//! Estimation Based on Linearization"), p.3720 (PCONV=), p.3890 (generalized
//! chi-square).
//!
//! The linearized pseudo-model is P = X beta + Z gamma + e with
//!   P = eta + (y/n - mu) / (mu (1 - mu)),  Var[e_j] = 1 / w_j,
//!   w_j = n_j mu_j (1 - mu_j),  G = sigma2 I,
//! so every block of V is diag(1/w) + sigma2 J and has the closed-form inverse
//! W - sigma2 W 1 1' W / (1 + sigma2 s), s = sum(w). The binomial scale is
//! fixed at 1 and nothing is profiled besides beta.
//!
//! ponytail: this kernel does not reproduce SAS's dual quasi-Newton path. The
//! inner optimization solves the one-parameter restricted pseudo-likelihood
//! score equation by bisection, so the per-optimization iteration history of
//! the SAS listing (subiterations, intermediate objective values) is NOT
//! available from here and must not be rendered from these numbers.
const std = @import("std");

pub const Error = error{ OutOfMemory, InvalidResponse, Singular, NoBracket };

pub const Input = struct {
    events: []const f64,
    trials: []const f64,
    /// Row-major n x p design matrix with full column rank.
    x: []const f64,
    p: usize,
    /// Subject index (0 .. subjects-1) of every observation.
    subject: []const usize,
    subjects: usize,
    pconv: f64,
    /// MAXOPT=: maximum number of linearized-model optimizations.
    max_updates: usize = 20,
};

pub const Fit = struct {
    converged: bool,
    /// Number of optimizations performed (SAS iterations 0 .. updates-1).
    updates: usize,
    /// PCONV= quantity of the last update.
    change: f64,
    beta: []f64,
    /// (X' V^-1 X)^-1 of the final linearization, row-major p x p.
    beta_cov: []f64,
    sigma2: f64,
    /// Asymptotic standard error; null on the lower boundary sigma2 = 0.
    sigma2_se: ?f64,
    /// Predicted random intercepts (estimated BLUPs), one per subject.
    gamma: []f64,
    /// -2 restricted log pseudo-likelihood of the final linearization.
    neg2_res_ll: f64,
    /// r' V^-1 r of the final linearization.
    gen_chisq: f64,
    /// Final linearization: pseudo-response and weights.
    pseudo: []f64,
    weight: []f64,
    /// Conditional means implied by the returned beta and gamma.
    mu: []f64,
};

/// One linearized mixed model and its restricted-likelihood profile.
const Lmm = struct {
    in: Input,
    pseudo: []const f64,
    w: []const f64,
    // Per-subject sums, filled by `sums`.
    s: []f64,
    a: []f64, // subjects x p: sum of w x
    b: []f64, // sum of w P
    // Scratch.
    m: []f64, // p x p
    c: []f64, // p x p
    rhs: []f64,
    beta: []f64,
    h: []f64,

    fn init(arena: std.mem.Allocator, in: Input) Error!Lmm {
        const p = in.p;
        return .{
            .in = in,
            .pseudo = &.{},
            .w = &.{},
            .s = try arena.alloc(f64, in.subjects),
            .a = try arena.alloc(f64, in.subjects * p),
            .b = try arena.alloc(f64, in.subjects),
            .m = try arena.alloc(f64, p * p),
            .c = try arena.alloc(f64, p * p),
            .rhs = try arena.alloc(f64, p),
            .beta = try arena.alloc(f64, p),
            .h = try arena.alloc(f64, p),
        };
    }

    fn sums(l: *Lmm, pseudo: []const f64, w: []const f64) void {
        const p = l.in.p;
        l.pseudo = pseudo;
        l.w = w;
        @memset(l.s, 0);
        @memset(l.a, 0);
        @memset(l.b, 0);
        for (l.in.subject, 0..) |i, j| {
            l.s[i] += w[j];
            l.b[i] += w[j] * pseudo[j];
            for (0..p) |k| l.a[i * p + k] += w[j] * l.in.x[j * p + k];
        }
    }

    const Profile = struct { objective: f64, gradient: f64, hessian: f64, quadratic: f64 };

    /// Profiles beta at `s2`; leaves beta in l.beta and (X'V^-1X)^-1 in l.c.
    /// objective = -2 l_R (p.3831), gradient/hessian = its derivatives in s2.
    fn profile(l: *Lmm, s2: f64) Error!Profile {
        const p = l.in.p;
        const n = l.pseudo.len;
        @memset(l.m, 0);
        @memset(l.rhs, 0);
        var log_v: f64 = 0;
        for (0..n) |j| {
            const row = l.in.x[j * p ..][0..p];
            log_v -= @log(l.w[j]);
            for (0..p) |k| {
                l.rhs[k] += l.w[j] * row[k] * l.pseudo[j];
                for (0..p) |q| l.m[k * p + q] += l.w[j] * row[k] * row[q];
            }
        }
        for (0..l.in.subjects) |i| {
            const d = 1.0 / (1.0 + s2 * l.s[i]);
            const ai = l.a[i * p ..][0..p];
            log_v += @log(1.0 + s2 * l.s[i]);
            for (0..p) |k| {
                l.rhs[k] -= s2 * d * ai[k] * l.b[i];
                for (0..p) |q| l.m[k * p + q] -= s2 * d * ai[k] * ai[q];
            }
        }
        const log_det = try invertSpd(l.m, l.c, p);
        for (0..p) |k| {
            var v: f64 = 0;
            for (0..p) |q| v += l.c[k * p + q] * l.rhs[q];
            l.beta[k] = v;
        }
        var quadratic: f64 = 0;
        for (0..n) |j| {
            const r = l.pseudo[j] - dot(l.in.x[j * p ..][0..p], l.beta);
            quadratic += l.w[j] * r * r;
        }
        var gradient: f64 = 0;
        var hessian: f64 = 0;
        @memset(l.h, 0);
        // l.m is free after inversion: reuse it for B = sum d^2 a a'.
        @memset(l.m, 0);
        for (0..l.in.subjects) |i| {
            const d = 1.0 / (1.0 + s2 * l.s[i]);
            const ai = l.a[i * p ..][0..p];
            const q = l.b[i] - dot(ai, l.beta);
            const aca = quad(l.c, ai, ai, p);
            quadratic -= s2 * d * q * q;
            gradient += l.s[i] * d - d * d * aca - d * d * q * q;
            hessian += -l.s[i] * l.s[i] * d * d + 2 * l.s[i] * d * d * d * (aca + q * q);
            for (0..p) |k| {
                l.h[k] += d * d * ai[k] * q;
                for (0..p) |r| l.m[k * p + r] += d * d * ai[k] * ai[r];
            }
        }
        // tr(B C B C) and 2 h' C h.
        var trace: f64 = 0;
        for (0..p) |k| for (0..p) |q| {
            var bc_kq: f64 = 0;
            var bc_qk: f64 = 0;
            for (0..p) |r| {
                bc_kq += l.m[k * p + r] * l.c[r * p + q];
                bc_qk += l.m[q * p + r] * l.c[r * p + k];
            }
            trace += bc_kq * bc_qk;
        };
        hessian -= trace + 2 * quad(l.c, l.h, l.h, p);
        const f: f64 = @floatFromInt(n - p);
        return .{ .objective = log_v + log_det + quadratic + f * @log(2.0 * std.math.pi), .gradient = gradient, .hessian = hessian, .quadratic = quadratic };
    }

    /// Minimizes -2 l_R over s2 >= 0 (lower boundary 0; objective p.3831).
    fn optimize(l: *Lmm) Error!f64 {
        if ((try l.profile(0)).gradient >= 0) return 0;
        var lo: f64 = 0;
        var hi: f64 = 1;
        while ((try l.profile(hi)).gradient < 0) {
            lo = hi;
            hi *= 2;
            if (hi > 1e12) return error.NoBracket;
        }
        while (true) {
            const mid = lo + (hi - lo) / 2;
            if (mid <= lo or mid >= hi) return mid;
            if ((try l.profile(mid)).gradient < 0) lo = mid else hi = mid;
        }
    }
};

fn dot(u: []const f64, v: []const f64) f64 {
    var t: f64 = 0;
    for (u, v) |x, y| t += x * y;
    return t;
}
fn quad(c: []const f64, u: []const f64, v: []const f64, p: usize) f64 {
    var t: f64 = 0;
    for (0..p) |k| for (0..p) |q| {
        t += u[k] * c[k * p + q] * v[q];
    };
    return t;
}

/// Cholesky inverse of the symmetric positive definite p x p `m` into `out`;
/// returns log|m|. `m` is overwritten with its lower factor.
fn invertSpd(m: []f64, out: []f64, p: usize) Error!f64 {
    var log_det: f64 = 0;
    for (0..p) |j| {
        for (0..j + 1) |k| {
            var v = m[j * p + k];
            for (0..k) |r| v -= m[j * p + r] * m[k * p + r];
            if (k == j) {
                if (!(v > 0) or !std.math.isFinite(v)) return error.Singular;
                m[j * p + j] = @sqrt(v);
                log_det += @log(v);
            } else m[j * p + k] = v / m[k * p + k];
        }
    }
    // Solve L L' out = I column by column.
    for (0..p) |col| {
        for (0..p) |j| {
            var v: f64 = if (j == col) 1 else 0;
            for (0..j) |r| v -= m[j * p + r] * out[r * p + col];
            out[j * p + col] = v / m[j * p + j];
        }
        var j = p;
        while (j > 0) {
            j -= 1;
            var v = out[j * p + col];
            for (j + 1..p) |r| v -= m[r * p + j] * out[r * p + col];
            out[j * p + col] = v / m[j * p + j];
        }
    }
    return log_det;
}

fn expit(eta: f64) f64 {
    return if (eta >= 0) 1.0 / (1.0 + @exp(-eta)) else @exp(eta) / (1.0 + @exp(eta));
}

/// Doubly iterative RSPL fit. Not converged within `max_updates` is reported
/// through `converged = false`; the caller must surface that, never hide it.
pub fn fit(arena: std.mem.Allocator, in: Input) Error!Fit {
    const n = in.events.len;
    const p = in.p;
    if (n == 0 or p == 0 or n <= p or in.trials.len != n or in.subject.len != n or in.x.len != n * p) return error.InvalidResponse;
    for (in.events, in.trials, in.subject) |y, t, i| {
        if (!std.math.isFinite(y) or !std.math.isFinite(t) or !(t > 0) or y < 0 or y > t or i >= in.subjects) return error.InvalidResponse;
    }
    const eta = try arena.alloc(f64, n);
    const pseudo = try arena.alloc(f64, n);
    const w = try arena.alloc(f64, n);
    const mu = try arena.alloc(f64, n);
    const gamma = try arena.alloc(f64, in.subjects);
    const previous = try arena.alloc(f64, p + 1);
    // ponytail: start from the data with the usual continuity adjustment so
    // that 0 and n counts have a finite logit; the converged fixed point does
    // not depend on this choice, SAS's intermediate optimizations may.
    for (in.events, in.trials, eta) |y, t, *e| {
        const m0 = (y + 0.5) / (t + 1.0);
        e.* = @log(m0 / (1.0 - m0));
    }
    var l = try Lmm.init(arena, in);
    var result = Fit{ .converged = false, .updates = 0, .change = std.math.inf(f64), .beta = l.beta, .beta_cov = l.c, .sigma2 = 0, .sigma2_se = null, .gamma = gamma, .neg2_res_ll = 0, .gen_chisq = 0, .pseudo = pseudo, .weight = w, .mu = mu };
    while (result.updates < in.max_updates) {
        for (0..n) |j| {
            const m = expit(eta[j]);
            const v = m * (1.0 - m);
            if (!(v > 0)) return error.Singular;
            pseudo[j] = eta[j] + (in.events[j] / in.trials[j] - m) / v;
            w[j] = in.trials[j] * v;
        }
        l.sums(pseudo, w);
        const s2 = try l.optimize();
        const prof = try l.profile(s2);
        for (0..in.subjects) |i| gamma[i] = s2 * (l.b[i] - dot(l.a[i * p ..][0..p], l.beta)) / (1.0 + s2 * l.s[i]);
        for (0..n) |j| {
            eta[j] = dot(in.x[j * p ..][0..p], l.beta) + gamma[in.subject[j]];
            mu[j] = expit(eta[j]);
        }
        // p.3720: largest 2 |b(u) - b(u-1)| / (|b(u)| + |b(u-1)|) over fixed
        // effects and covariance parameters.
        var change: f64 = if (result.updates == 0) std.math.inf(f64) else 0;
        for (0..p + 1) |k| {
            const now = if (k < p) l.beta[k] else s2;
            if (result.updates > 0) {
                const scale = @abs(now) + @abs(previous[k]);
                if (scale > 0) change = @max(change, 2 * @abs(now - previous[k]) / scale);
            }
            previous[k] = now;
        }
        result.updates += 1;
        result.change = change;
        result.sigma2 = s2;
        result.sigma2_se = if (s2 > 0 and prof.hessian > 0) @sqrt(2.0 / prof.hessian) else null;
        result.neg2_res_ll = prof.objective;
        result.gen_chisq = prof.quadratic;
        if (change < in.pconv) {
            result.converged = true;
            break;
        }
    }
    return result;
}

const t_ = std.testing;
const default_pconv: f64 = 1e8 * std.math.floatEps(f64) / 2.0;

/// Published sample data: SAS/STAT 15.4 User's Guide, "Getting Started:
/// GLIMMIX Procedure" (multicenter side-effect counts; center, group, n,
/// sideeffect), groups A then B within each of 15 centers.
const gs_n = [_]f64{ 32, 33, 30, 28, 23, 24, 22, 22, 20, 21, 19, 20, 17, 17, 16, 15, 13, 14, 13, 13, 11, 12, 10, 9, 9, 9, 8, 8, 7, 8 };
const gs_y = [_]f64{ 14, 18, 4, 8, 14, 9, 7, 10, 6, 12, 1, 3, 2, 6, 7, 9, 1, 5, 3, 1, 1, 2, 1, 0, 2, 6, 1, 1, 1, 0 };

fn gettingStarted(a: std.mem.Allocator, flip: bool, reverse: bool) !Input {
    const n = gs_n.len;
    const x = try a.alloc(f64, n * 2);
    const y = try a.alloc(f64, n);
    const t = try a.alloc(f64, n);
    const s = try a.alloc(usize, n);
    for (0..n) |k| {
        const j = if (reverse) n - 1 - k else k;
        x[k * 2] = 1;
        x[k * 2 + 1] = if (j % 2 == 0) 1 else 0; // group A indicator; B is the reference
        t[k] = gs_n[j];
        y[k] = if (flip) gs_n[j] - gs_y[j] else gs_y[j];
        s[k] = if (reverse) 14 - j / 2 else j / 2;
    }
    return .{ .events = y, .trials = t, .x = x, .p = 2, .subject = s, .subjects = 15, .pconv = default_pconv };
}

test "GLIMMIX002 Getting Started RSPL fit: published estimates and estimating equations" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const in = try gettingStarted(a, false, false);
    const f = try fit(a, in);
    try t_.expect(f.converged);
    try t_.expect(f.change < default_pconv);
    // Published listing values (Getting Started figures); each bound is half a
    // unit of the last printed digit, i.e. the listing's own rounding.
    try t_.expectApproxEqAbs(@as(f64, 0.6176), f.sigma2, 5e-5);
    try t_.expectApproxEqAbs(@as(f64, 0.3181), f.sigma2_se.?, 5e-5);
    try t_.expectApproxEqAbs(@as(f64, -0.8071), f.beta[0], 5e-5);
    try t_.expectApproxEqAbs(@as(f64, -0.4896), f.beta[1], 5e-5);
    try t_.expectApproxEqAbs(@as(f64, 0.2514), @sqrt(f.beta_cov[0]), 5e-5);
    try t_.expectApproxEqAbs(@as(f64, 0.2034), @sqrt(f.beta_cov[3]), 5e-5);
    try t_.expectApproxEqAbs(@as(f64, 81.44), f.neg2_res_ll, 5e-3);
    try t_.expectApproxEqAbs(@as(f64, 30.69), f.gen_chisq, 5e-3);
    try t_.expectApproxEqAbs(@as(f64, 1.10), f.gen_chisq / 28.0, 5e-3);

    // Independent of the V^-1 algebra: at the fixed point the mixed model
    // equations of the linearization reduce to the penalized quasi-likelihood
    // score equations X'(y - n mu) = 0 and Z'(y - n mu) = gamma / sigma2.
    // Bound: successive parameter estimates agree to PCONV (relative), so the
    // linear predictor moved by at most ~PCONV * |eta|; the scores have slope
    // sum(n mu (1 - mu)) <= sum(n) / 4, giving |score| <= 1e-6 * sum(n) with
    // more than an order of magnitude of headroom for |eta| <= 3.
    var total: f64 = 0;
    for (in.trials) |v| total += v;
    const bound = 1e-6 * total;
    var score = [_]f64{ 0, 0 };
    const zscore = try a.alloc(f64, 15);
    @memset(zscore, 0);
    for (0..in.events.len) |j| {
        const e = in.events[j] - in.trials[j] * f.mu[j];
        score[0] += e;
        score[1] += in.x[j * 2 + 1] * e;
        zscore[in.subject[j]] += e;
    }
    try t_.expectApproxEqAbs(@as(f64, 0), score[0], bound);
    try t_.expectApproxEqAbs(@as(f64, 0), score[1], bound);
    var gamma_sum: f64 = 0;
    for (zscore, f.gamma) |z, g| {
        try t_.expectApproxEqAbs(z, g / f.sigma2, bound);
        gamma_sum += g;
    }
    // Consequence of the intercept score equation.
    try t_.expectApproxEqAbs(@as(f64, 0), gamma_sum / f.sigma2, 2 * bound);

    // Restricted score of the final linearization vanishes at sigma2, and the
    // analytic Hessian behind the standard error matches a central difference
    // of the analytic gradient (truncation error O(h^2), h = 1e-4).
    var l = try Lmm.init(a, in);
    l.sums(f.pseudo, f.weight);
    const at = try l.profile(f.sigma2);
    try t_.expect(@abs(at.gradient) < 1e-9);
    const h = 1e-4;
    const up = try l.profile(f.sigma2 + h);
    const down = try l.profile(f.sigma2 - h);
    try t_.expectApproxEqRel(at.hessian, (up.gradient - down.gradient) / (2 * h), 1e-5);
    // ... and the gradient is the derivative of the objective.
    try t_.expectApproxEqAbs((up.objective - down.objective) / (2 * h), at.gradient, 1e-6);
    // The objective is a minimum there.
    try t_.expect(up.objective > at.objective and down.objective > at.objective);
}

test "GLIMMIX002 fit invariances: complement response, observation order, subject labels" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try fit(a, try gettingStarted(a, false, false));
    // Modelling non-events negates the linear predictor: beta and gamma flip
    // sign, the variance component and the objective are unchanged.
    const flipped = try fit(a, try gettingStarted(a, true, false));
    try t_.expect(flipped.converged);
    try t_.expectApproxEqAbs(base.sigma2, flipped.sigma2, 1e-9);
    try t_.expectApproxEqAbs(-base.beta[0], flipped.beta[0], 1e-9);
    try t_.expectApproxEqAbs(-base.beta[1], flipped.beta[1], 1e-9);
    try t_.expectApproxEqAbs(base.neg2_res_ll, flipped.neg2_res_ll, 1e-9);
    try t_.expectApproxEqAbs(-base.gamma[3], flipped.gamma[3], 1e-9);
    // Reversed observation order and relabelled subjects: same fit.
    const reversed = try fit(a, try gettingStarted(a, false, true));
    try t_.expectApproxEqAbs(base.sigma2, reversed.sigma2, 1e-9);
    try t_.expectApproxEqAbs(base.beta[1], reversed.beta[1], 1e-9);
    try t_.expectApproxEqAbs(base.sigma2_se.?, reversed.sigma2_se.?, 1e-9);
    try t_.expectApproxEqAbs(base.gamma[3], reversed.gamma[14 - 3], 1e-9);
    try t_.expectApproxEqAbs(base.gen_chisq, reversed.gen_chisq, 1e-9);
}

test "GLIMMIX002 hand-checkable case: equal proportions put the variance on its boundary" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Invented data: four observations, two subjects, 2 events of 10 each.
    // Every observed proportion is 0.2, so mu = 0.2 solves the score equation
    // exactly, the pseudo-response is constant (= logit 0.2), all residuals
    // are zero and the restricted score at sigma2 = 0 is
    // tr(P Z Z') >= 0: the estimate is the boundary value 0.
    // With w = 10 * 0.2 * 0.8 = 1.6 for each observation:
    //   -2 l_R = -4 log 1.6 + log(4 * 1.6) + 0 + (4 - 1) log(2 pi),
    //   Var[beta] = 1 / (4 * 1.6) = 0.15625.
    const in = Input{ .events = &.{ 2, 2, 2, 2 }, .trials = &.{ 10, 10, 10, 10 }, .x = &.{ 1, 1, 1, 1 }, .p = 1, .subject = &.{ 0, 0, 1, 1 }, .subjects = 2, .pconv = default_pconv };
    const f = try fit(a, in);
    try t_.expect(f.converged);
    try t_.expectEqual(@as(f64, 0), f.sigma2);
    try t_.expectEqual(@as(?f64, null), f.sigma2_se);
    // Bounds: the reported covariance and objective belong to the FINAL
    // linearization, whose weights come from the previous estimate. That
    // estimate differs from the last one by less than PCONV * |beta|
    // (|beta| = log 4 < 1.4), so mu is within 0.16 * 1.4 * PCONV < 2.5e-9 and
    // w = 10 mu (1 - mu) within 6 * 2.5e-9 = 1.5e-8 absolute (1e-8 relative).
    // Var[beta] = 1 / sum(w) inherits the relative bound; the objective has
    // |d/dw| = |-1/w + 1/sum(w)| per observation, at most 4 * 1e-8 in total.
    try t_.expectApproxEqAbs(@log(0.25), f.beta[0], 1.4 * default_pconv);
    try t_.expectApproxEqRel(@as(f64, 0.15625), f.beta_cov[0], 1e-8);
    try t_.expectApproxEqAbs(-4.0 * @log(1.6) + @log(6.4) + 3.0 * @log(2.0 * std.math.pi), f.neg2_res_ll, 4e-8);
    try t_.expectApproxEqAbs(@as(f64, 0), f.gen_chisq, 1e-12);
    for (f.gamma) |g| try t_.expectEqual(@as(f64, 0), g);
    for (f.mu) |m| try t_.expectApproxEqAbs(@as(f64, 0.2), m, 2.5e-9);
}

test "GLIMMIX002 invalid responses, deficient designs and exhausted MAXOPT are reported" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ok = Input{ .events = &.{ 2, 3, 1, 4 }, .trials = &.{ 10, 10, 10, 10 }, .x = &.{ 1, 1, 1, 1 }, .p = 1, .subject = &.{ 0, 0, 1, 1 }, .subjects = 2, .pconv = default_pconv };
    var bad = ok;
    bad.events = &.{ 2, 11, 1, 4 }; // events > trials
    try t_.expectError(error.InvalidResponse, fit(a, bad));
    bad = ok;
    bad.trials = &.{ 10, 0, 10, 10 };
    try t_.expectError(error.InvalidResponse, fit(a, bad));
    bad = ok;
    bad.subject = &.{ 0, 0, 1, 2 }; // subject index out of range
    try t_.expectError(error.InvalidResponse, fit(a, bad));
    // Two identical columns: X' V^-1 X is singular.
    bad = ok;
    bad.x = &.{ 1, 1, 1, 1, 1, 1, 1, 1 };
    bad.p = 2;
    try t_.expectError(error.Singular, fit(a, bad));
    // One optimization can never satisfy PCONV (no previous estimate).
    var one = try gettingStarted(a, false, false);
    one.max_updates = 1;
    const f = try fit(a, one);
    try t_.expect(!f.converged);
    try t_.expectEqual(@as(usize, 1), f.updates);
}
