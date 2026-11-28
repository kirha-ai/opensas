//! PROC VARCOMP estimation kernels, SAS/STAT 15.4 "Computational Methods"
//! (physical pp.10722-10723): MIVQUE0 equations SSQ(X_i'MX_j) and the REML
//! Newton-Raphson iteration on ln|V| + r'V^-1 r + ln|X0'V^-1 X0|.
//! Every effect is a classification: an observation-to-level index map.
//! ponytail: dense n x n algebra (O(n^3) per iteration); the procedure caps n.
const std = @import("std");
const mat = @import("mixed_fit_matrix.zig");
const A = std.mem.Allocator;

pub const Effect = struct { level: []const u32, levels: usize };

pub const Problem = struct {
    y: []const f64,
    /// Fixed effects in model order, the intercept first.
    fixed: []const Effect,
    random: []const Effect,
};

pub const Error = error{ OutOfMemory, InvalidInput, NotPositiveDefinite, Singular };

/// Columns of the fixed design kept by a sequential (sweep-order) rank check:
/// a level indicator is dropped when it is a linear combination of the
/// columns before it, as the GLM-style generalized inverse does.
pub fn fixedDesign(a: A, p: Problem) Error!struct { x: []f64, cols: usize } {
    const n = p.y.len;
    var kept: std.ArrayList([]f64) = .empty; // orthonormal basis
    var raw: std.ArrayList([]f64) = .empty;
    for (p.fixed) |e| for (0..e.levels) |l| {
        const c = try a.alloc(f64, n);
        for (c, e.level) |*v, g| v.* = if (g == l) 1 else 0;
        const q = try a.dupe(f64, c);
        const norm0 = @sqrt(mat.dot(q, q));
        if (norm0 == 0) continue;
        for (kept.items) |b| {
            const d = mat.dot(q, b);
            for (q, b) |*v, w| v.* -= d * w;
        }
        const norm = @sqrt(mat.dot(q, q));
        if (norm <= 1e-9 * norm0) continue;
        for (q) |*v| v.* /= norm;
        try kept.append(a, q);
        try raw.append(a, c);
    };
    const k = raw.items.len;
    const x = try a.alloc(f64, n * k);
    for (raw.items, 0..) |c, j| for (0..n) |i| {
        x[i * k + j] = c[i];
    };
    return .{ .x = x, .cols = k };
}

fn zzt(a: A, e: Effect, n: usize) ![]f64 {
    const m = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        m[i * n + j] = if (e.level[i] == e.level[j]) 1 else 0;
    };
    return m;
}

/// P = V^-1 - V^-1 X (X'V^-1 X)^-1 X'V^-1 and the two log determinants.
const Projection = struct { p: []f64, logdet_v: f64, logdet_w: f64 };
fn projection(a: A, v: []const f64, x: []const f64, n: usize, k: usize) Error!Projection {
    const vi = mat.inverse(a, v, n) catch |e| return mapErr(e);
    const vx = try a.alloc(f64, n * k); // V^-1 X
    @memset(vx, 0);
    for (0..n) |i| for (0..n) |l| {
        const s = vi.values[i * n + l];
        if (s == 0) continue;
        for (0..k) |j| vx[i * k + j] += s * x[l * k + j];
    };
    const w = try a.alloc(f64, k * k);
    @memset(w, 0);
    for (0..n) |i| for (0..k) |r| for (0..k) |c| {
        w[r * k + c] += x[i * k + r] * vx[i * k + c];
    };
    const wi = mat.inverse(a, w, k) catch |e| return mapErr(e);
    const out = try a.dupe(f64, vi.values);
    const t = try a.alloc(f64, n * k); // V^-1 X W^-1
    @memset(t, 0);
    for (0..n) |i| for (0..k) |r| for (0..k) |c| {
        t[i * k + c] += vx[i * k + r] * wi.values[r * k + c];
    };
    for (0..n) |i| for (0..n) |j| {
        var s: f64 = 0;
        for (0..k) |c| s += t[i * k + c] * vx[j * k + c];
        out[i * n + j] -= s;
    };
    return .{ .p = out, .logdet_v = vi.logdet, .logdet_w = wi.logdet };
}
fn mapErr(e: anyerror) Error {
    return switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.NotPositiveDefinite => error.NotPositiveDefinite,
        else => error.InvalidInput,
    };
}

/// MIVQUE0 estimates (random components then error) from the SSQ system.
pub fn mivque0(a: A, p: Problem) Error![]f64 {
    const n = p.y.len;
    const d = try fixedDesign(a, p);
    const ident = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        ident[i * n + j] = if (i == j) 1 else 0;
    };
    const m = (try projection(a, ident, d.x, n, d.cols)).p; // M = I - X(X'X)^-X'
    const r = p.random.len;
    const q = r + 1;
    // MZ_i as n x levels; error "Z" is the identity.
    const mz = try a.alloc([]f64, r);
    for (p.random, mz) |e, *out| {
        out.* = try a.alloc(f64, n * e.levels);
        @memset(out.*, 0);
        for (0..n) |i| for (0..n) |l| {
            out.*[i * e.levels + e.level[l]] += m[i * n + l];
        };
    }
    const my = try mat.vector(a, m, p.y, n);
    const s = try a.alloc(f64, q * q);
    const rhs = try a.alloc(f64, q);
    for (0..r) |i| {
        const ei = p.random[i];
        for (0..r) |j| {
            const ej = p.random[j];
            // SSQ(Z_i' M Z_j) = sum over (li,lj) of (sum_obs Z_i[obs,li] * MZ_j[obs,lj])^2
            var ss: f64 = 0;
            const block = try a.alloc(f64, ei.levels * ej.levels);
            @memset(block, 0);
            for (0..n) |o| for (0..ej.levels) |lj| {
                block[ei.level[o] * ej.levels + lj] += mz[j][o * ej.levels + lj];
            };
            for (block) |v| ss += v * v;
            s[i * q + j] = ss;
        }
        var tr: f64 = 0; // tr(Z_i'MZ_i)
        for (0..n) |o| tr += mz[i][o * ei.levels + ei.level[o]];
        s[i * q + r] = tr;
        s[r * q + i] = tr;
        const zy = try a.alloc(f64, ei.levels);
        @memset(zy, 0);
        for (0..n) |o| zy[ei.level[o]] += my[o];
        rhs[i] = mat.dot(zy, zy);
    }
    s[r * q + r] = @as(f64, @floatFromInt(n - d.cols));
    rhs[r] = mat.dot(my, my);
    return solve(a, s, rhs, q);
}

/// Gaussian elimination with partial pivoting; error when singular.
fn solve(a: A, m0: []const f64, b0: []const f64, q: usize) Error![]f64 {
    const m = try a.dupe(f64, m0);
    const b = try a.dupe(f64, b0);
    for (0..q) |c| {
        var piv = c;
        for (c + 1..q) |r| if (@abs(m[r * q + c]) > @abs(m[piv * q + c])) {
            piv = r;
        };
        if (@abs(m[piv * q + c]) < 1e-12) return error.Singular;
        if (piv != c) {
            for (0..q) |j| std.mem.swap(f64, &m[c * q + j], &m[piv * q + j]);
            std.mem.swap(f64, &b[c], &b[piv]);
        }
        for (c + 1..q) |r| {
            const f = m[r * q + c] / m[c * q + c];
            for (c..q) |j| m[r * q + j] -= f * m[c * q + j];
            b[r] -= f * b[c];
        }
    }
    var i = q;
    while (i > 0) {
        i -= 1;
        var s = b[i];
        for (i + 1..q) |j| s -= m[i * q + j] * b[j];
        b[i] = s / m[i * q + i];
    }
    return b;
}

/// Full-parameter -2 REML objective, gradient and observed Hessian over the
/// active components (random effects with a positive value, then error).
pub const Eval = struct { objective: f64, grad: []f64, hess: []f64 };

pub const Fit = struct {
    n: usize,
    x: []f64,
    cols: usize,
    zz: [][]f64,
};

pub fn prepare(a: A, p: Problem) Error!Fit {
    const n = p.y.len;
    const d = try fixedDesign(a, p);
    const zz = try a.alloc([]f64, p.random.len);
    for (p.random, zz) |e, *m| m.* = try zzt(a, e, n);
    return .{ .n = n, .x = d.x, .cols = d.cols, .zz = zz };
}

/// theta: random components then error; active[i] false holds theta[i] at 0.

pub const Profiled = struct { q: f64, objective: f64, grad: []f64, info: []f64 };
/// REML profiled over the error variance: V = s2 H, H = I + sum gamma_i Z_iZ_i',
/// s2 = y'P_H y/(n-p); gradient over the active ratios and the profiled
/// expected information tr(PV_iPV_j) - tr(PV_i)tr(PV_j)/(n-p).
/// `objective` is the full -2 REML log likelihood ln|V| + r'V^-1 r + ln|X'V^-1X|
/// at the profiled point.
pub fn profiled(a: A, f: Fit, y: []const f64, gamma: []const f64, active: []const bool) Error!Profiled {
    const n = f.n;
    const r = f.zz.len;
    const v = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        var s: f64 = if (i == j) 1 else 0;
        for (0..r) |c| s += gamma[c] * f.zz[c][i * n + j];
        v[i * n + j] = s;
    };
    const pr = try projection(a, v, f.x, n, f.cols);
    const py = try mat.vector(a, pr.p, y, n);
    const q = mat.dot(y, py);
    if (!(q > 0)) return error.Singular;
    const df: f64 = @floatFromInt(n - f.cols);
    var idx: std.ArrayList(usize) = .empty;
    for (0..r) |c| if (active[c]) try idx.append(a, c);
    const m = idx.items.len;
    const pv = try a.alloc([]f64, m);
    const tr = try a.alloc(f64, m);
    const grad = try a.alloc(f64, m);
    for (idx.items, 0..) |c, s| {
        pv[s] = try mat.multiply(a, pr.p, f.zz[c], n);
        tr[s] = 0;
        for (0..n) |i| tr[s] += pv[s][i * n + i];
        const vpy = try mat.vector(a, f.zz[c], py, n);
        grad[s] = tr[s] - df * mat.dot(py, vpy) / q;
    }
    const info = try a.alloc(f64, m * m);
    for (0..m) |s| for (0..m) |t| {
        info[s * m + t] = mat.traceProduct(pv[s], pv[t], n) - tr[s] * tr[t] / df;
    };
    const obj = df * @log(q / df) + pr.logdet_v + pr.logdet_w + df;
    return .{ .q = q, .objective = obj, .grad = grad, .info = info };
}

pub const Reml = struct {
    /// Random components (model order) then error.
    theta: []f64,
    /// Asymptotic covariance (row-major, same order); zero rows for zeros.
    cov: []f64,
    converged: bool,
    iterations: usize,
    /// Objective as SAS reports it: -2 REML log likelihood less (n-p) and
    /// ln|X'X| (verified against the reference iteration 0 and final rows).
    objective: f64,
    start: []f64,
};

/// REML from the MIVQUE0 ratios (negative ones set to zero, error profiled),
/// iterated on the ratios until the objective changes by less than epsilon.
/// ponytail: SAS's exact Newton-Raphson variant is not reproduced, so the
/// path differs after the start; the optimum and covariance do not.
pub fn reml(a: A, p: Problem, epsilon: f64, maxiter: usize) Error!Reml {
    const f = try prepare(a, p);
    const n = f.n;
    if (n <= f.cols) return error.Singular;
    const r = f.zz.len;
    const df: f64 = @floatFromInt(n - f.cols);
    const mq = try mivque0(a, p);
    if (!(mq[r] > 0)) return error.Singular;
    const gamma = try a.alloc(f64, r);
    const active = try a.alloc(bool, r + 1);
    for (0..r) |c| {
        gamma[c] = @max(mq[c], 0) / mq[r];
        active[c] = gamma[c] > 0;
    }
    active[r] = true;
    const xtx = try a.alloc(f64, f.cols * f.cols);
    @memset(xtx, 0);
    for (0..n) |i| for (0..f.cols) |u| for (0..f.cols) |w| {
        xtx[u * f.cols + w] += f.x[i * f.cols + u] * f.x[i * f.cols + w];
    };
    const logdet_xtx = (mat.inverse(a, xtx, f.cols) catch |e| return mapErr(e)).logdet;
    var start: []f64 = &.{};
    var prev: f64 = 0;
    var it: usize = 0;
    var converged = false;
    var last: Profiled = undefined;
    var reported: f64 = 0;
    var settled = false;
    var polish: usize = 0;
    const all = try a.alloc(bool, r);
    @memset(all, true);
    while (true) : (it += 1) {
        last = try profiled(a, f, p.y, gamma, all);
        const obj = last.objective - df - logdet_xtx;
        if (it == 0) {
            start = try a.alloc(f64, r + 1);
            for (0..r) |c| start[c] = gamma[c] * last.q / df;
            start[r] = last.q / df;
        } else if (!converged and @abs(obj - prev) < epsilon) {
            converged = true;
            reported = obj;
        }
        prev = obj;
        // After the EPSILON= criterion is met, Fisher steps continue until the
        // ratios settle, so the reported optimum matches SAS's quadratically
        // converged Newton-Raphson end point (scoring converges linearly).
        if (converged and (settled or polish >= 500)) break;
        if (converged) polish += 1;
        // A ratio at zero moves only when the objective decreases into the
        // feasible side (projected Fisher scoring).
        var sel: std.ArrayList(usize) = .empty;
        for (0..r) |c| if (gamma[c] > 0 or last.grad[c] < 0) try sel.append(a, c);
        const m = sel.items.len;
        if (m == 0) {
            if (!converged) reported = obj;
            converged = true;
            break;
        }
        if (!converged and it >= maxiter) break;
        const info = try a.alloc(f64, m * m);
        const grad = try a.alloc(f64, m);
        for (sel.items, 0..) |c, u| {
            grad[u] = last.grad[c];
            for (sel.items, 0..) |d, w| info[u * m + w] = last.info[c * r + d];
        }
        const step = try solve(a, info, grad, m);
        settled = true;
        for (sel.items, step) |c, d| {
            if (@abs(d) > 1e-13 * @max(gamma[c], 1e-3)) settled = false;
            // Negative REML estimates are constrained to zero (p.10722).
            gamma[c] = @max(gamma[c] - d, 0);
        }
    }
    for (0..r) |c| active[c] = gamma[c] > 0;
    const s2 = last.q / df;
    const theta = try a.alloc(f64, r + 1);
    for (0..r) |c| theta[c] = gamma[c] * s2;
    theta[r] = s2;
    // Covariance: 2 x inverse observed Hessian of the -2 log likelihood.
    const ev = try evaluate(a, f, p.y, theta, active);
    var m: usize = 0;
    for (active) |b| m += @intFromBool(b);
    const inv = mat.inverse(a, ev.hess, m) catch |e| return mapErr(e);
    const q = r + 1;
    const cov = try a.alloc(f64, q * q);
    @memset(cov, 0);
    var ii: usize = 0;
    for (0..q) |i| if (active[i]) {
        var jj: usize = 0;
        for (0..q) |j| if (active[j]) {
            cov[i * q + j] = 2 * inv.values[ii * m + jj];
            jj += 1;
        };
        ii += 1;
    };
    return .{ .theta = theta, .cov = cov, .converged = converged, .iterations = it, .objective = if (converged) reported else prev, .start = start };
}

pub fn evaluate(a: A, f: Fit, y: []const f64, theta: []const f64, active: []const bool) Error!Eval {
    const n = f.n;
    const r = f.zz.len;
    const v = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        var s: f64 = if (i == j) theta[r] else 0;
        for (0..r) |c| s += theta[c] * f.zz[c][i * n + j];
        v[i * n + j] = s;
    };
    const pr = try projection(a, v, f.x, n, f.cols);
    const py = try mat.vector(a, pr.p, y, n);
    const obj = pr.logdet_v + mat.dot(y, py) + pr.logdet_w;
    // Active derivative matrices V_i.
    var idx: std.ArrayList(usize) = .empty;
    for (0..r + 1) |c| if (active[c]) try idx.append(a, c);
    const m = idx.items.len;
    const pv = try a.alloc([]f64, m); // P V_i
    const pvpy = try a.alloc([]f64, m); // P V_i P y
    for (idx.items, 0..) |c, s| {
        if (c == r) {
            pv[s] = pr.p;
        } else pv[s] = try mat.multiply(a, pr.p, f.zz[c], n);
        pvpy[s] = try mat.vector(a, pv[s], py, n);
    }
    const grad = try a.alloc(f64, m);
    const hess = try a.alloc(f64, m * m);
    for (0..m) |s| {
        var tr: f64 = 0;
        for (0..n) |i| tr += pv[s][i * n + i];
        const vi_py = if (idx.items[s] == r) py else try mat.vector(a, f.zz[idx.items[s]], py, n);
        grad[s] = tr - mat.dot(py, vi_py);
        for (0..m) |t| {
            const ttr = mat.traceProduct(pv[s], pv[t], n);
            const vj_py = if (idx.items[t] == r) py else try mat.vector(a, f.zz[idx.items[t]], py, n);
            const pvj = try mat.vector(a, pr.p, vj_py, n);
            hess[s * m + t] = -ttr + 2 * mat.dot(vi_py, pvj);
        }
    }
    return .{ .objective = obj, .grad = grad, .hess = hess };
}


/// Rubber cure data of the guide's introductory example (PDF p.10716),
/// in data order: Lab 1..3, Temp 145/155/165, Batch A/B/C, four replicates.
const cure_y = [_]f64{ 18.6, 17.0, 18.7, 18.7, 14.5, 15.8, 16.5, 17.6, 21.1, 20.8, 21.8, 21.0, 9.5, 9.4, 9.5, 10.0, 7.8, 8.3, 8.9, 9.1, 11.2, 10.0, 11.5, 11.1, 5.4, 5.3, 5.7, 5.3, 5.2, 4.9, 4.3, 5.2, 6.3, 6.4, 5.8, 5.6, 20.0, 20.1, 19.4, 20.0, 18.4, 18.1, 16.5, 16.7, 22.5, 22.7, 21.5, 21.3, 11.4, 11.5, 11.4, 11.5, 10.8, 11.1, 9.5, 9.7, 13.3, 14.0, 12.0, 11.5, 6.8, 6.9, 6.0, 5.7, 6.0, 6.1, 5.0, 5.2, 7.7, 8.0, 6.6, 6.3, 19.7, 18.3, 16.8, 17.1, 16.3, 16.7, 14.4, 15.2, 22.7, 21.9, 19.3, 19.3, 9.3, 10.2, 9.8, 9.5, 9.1, 9.2, 8.0, 9.0, 11.3, 11.0, 10.9, 11.4, 6.7, 6.0, 5.0, 4.8, 5.7, 5.5, 4.6, 5.4, 6.6, 6.5, 5.9, 5.8 };

test "STAT-VARCOMP-001 REML start, optimum, objective and covariance match the SAS reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var icpt: [108]u32 = undefined;
    var temp: [108]u32 = undefined;
    var lab: [108]u32 = undefined;
    var tl: [108]u32 = undefined;
    var btl: [108]u32 = undefined;
    for (0..108) |o| {
        const l: u32 = @intCast(o / 36);
        const t: u32 = @intCast((o / 12) % 3);
        const b: u32 = @intCast((o / 4) % 3);
        icpt[o] = 0;
        temp[o] = t;
        lab[o] = l;
        tl[o] = t * 3 + l;
        btl[o] = (t * 3 + l) * 3 + b;
    }
    const p: Problem = .{ .y = &cure_y, .fixed = &.{ .{ .level = &icpt, .levels = 1 }, .{ .level = &temp, .levels = 3 } }, .random = &.{ .{ .level = &lab, .levels = 3 }, .{ .level = &tl, .levels = 9 }, .{ .level = &btl, .levels = 27 } } };
    const r = try reml(a, p, 1e-8, 50);
    // SAS "REML Iterations" row 0 and final row, "REML Estimates" and
    // "Asymptotic Covariance Matrix of Estimates" (reference listing).
    const start = [_]f64{ 0.5094464340, 0, 2.4004888633, 0.5787185225 };
    for (start, r.start) |e, x| try std.testing.expectApproxEqAbs(e, x, 5e-11);
    const final = [_]f64{ 0.3176017115, 0, 2.0738685461, 0.6026234568 };
    for (final, r.theta) |e, x| try std.testing.expectApproxEqAbs(e, x, 2e-9);
    try std.testing.expect(r.converged);
    try std.testing.expectApproxEqAbs(13.0893125555, r.objective, 5e-10);
    const cov = [_]f64{ 0.32452, 0, -0.04998, 0, 0, 0, 0, 0, -0.04998, 0, 0.45042, -0.0022417, 0, 0, -0.0022417, 0.0089668 };
    for (cov, r.cov) |e, x| try std.testing.expectApproxEqAbs(e, x, 6e-6);
}

test "STAT-VARCOMP-001 MIVQUE0 SSQ system reproduces the guide's two-way example" {
    // Output 130.1.2 data (PDF p.10730): a, b, y; FIXED=1 (a fixed).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p = hemmerle(&ab_buf);
    const est = try mivque0(a, p);
    try std.testing.expectApproxEqAbs(@as(f64, 1466.1), est[0], 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, -35.49170), est[1], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 105.73660), est[2], 5e-5);
}

// Hemmerle and Hartley (1973) data of Example 130.1 (PDF p.10730).
const hh_a = [_]u32{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 };
const hh_b = [_]u32{ 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1 };
const hh_y = [_]f64{ 237, 254, 246, 178, 179, 208, 178, 187, 146, 145, 141, 186, 183, 142, 125, 136 };
const hh_icpt = [_]u32{0} ** 16;
var ab_buf: [16]u32 = undefined;
var hh_fixed: [2]Effect = undefined;
var hh_random: [2]Effect = undefined;
fn hemmerle(ab: *[16]u32) Problem {
    for (ab, hh_a, hh_b) |*o, x, z| o.* = x * 2 + z;
    hh_fixed = .{ .{ .level = &hh_icpt, .levels = 1 }, .{ .level = &hh_a, .levels = 3 } };
    hh_random = .{ .{ .level = &hh_b, .levels = 2 }, .{ .level = ab, .levels = 6 } };
    return .{ .y = &hh_y, .fixed = &hh_fixed, .random = &hh_random };
}

test "STAT-VARCOMP-001 REML lets a zero start component re-enter (guide Output 130.1.4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try reml(a, hemmerle(&ab_buf), 1e-8, 50);
    const start = [_]f64{ 1269.52701, 0, 91.5581191305 };
    for (start, r.start) |e, x| try std.testing.expectApproxEqAbs(e, x, 5e-6);
    const final = [_]f64{ 1464.36727, 26.9588525177, 78.8423898761 };
    for (final, r.theta) |e, x| try std.testing.expectApproxEqRel(e, x, 2e-6);
    try std.testing.expectApproxEqAbs(63.0311265127, r.objective, 5e-9);
    const cov = [_]f64{ 4401703.8, 1.29359, -273.39651, 1.29359, 3559.1, -502.85157, -273.39651, -502.85157, 1249.7 };
    for (cov, r.cov) |e, x| try std.testing.expectApproxEqAbs(e, x, @max(@abs(e) * 2e-5, 6e-5));
}

fn cureProblem(bufs: *[5][108]u32) Problem {
    for (0..108) |o| {
        const l: u32 = @intCast(o / 36);
        const t: u32 = @intCast((o / 12) % 3);
        const b: u32 = @intCast((o / 4) % 3);
        bufs[0][o] = 0;
        bufs[1][o] = t;
        bufs[2][o] = l;
        bufs[3][o] = t * 3 + l;
        bufs[4][o] = (t * 3 + l) * 3 + b;
    }
    cure_fixed = .{ .{ .level = &bufs[0], .levels = 1 }, .{ .level = &bufs[1], .levels = 3 } };
    cure_random = .{ .{ .level = &bufs[2], .levels = 3 }, .{ .level = &bufs[3], .levels = 9 }, .{ .level = &bufs[4], .levels = 27 } };
    return .{ .y = &cure_y, .fixed = &cure_fixed, .random = &cure_random };
}
var cure_fixed: [2]Effect = undefined;
var cure_random: [3]Effect = undefined;
var cure_buf: [5][108]u32 = undefined;

fn norm1(m: []const f64, k: usize) f64 {
    var best: f64 = 0;
    for (0..k) |j| {
        var s: f64 = 0;
        for (0..k) |i| s += @abs(m[i * k + j]);
        best = @max(best, s);
    }
    return best;
}

// Balanced-design identity (independent of opensas output). With Var(Temp*Lab)
// at its zero boundary, the cure design has three random-effect strata with
// expected mean squares t1 = s_e (df 108-27 = 81), t2 = s_e + 4 s_b (Batch and
// Temp*Lab pooled) and t3 = s_e + 4 s_b + 36 s_l (Lab). REML on balanced
// data factors into independent strata, so the information in (t1,t2,t3) is
// diagonal with Var(t_k) = 2 t_k^2 / df_k, and s_e = t1, s_b = (t2-t1)/4,
// s_l = (t3-t2)/36. Hence Cov(s_l, s_e) = 0 exactly, Var(s_e) = 2 t1^2/81
// and Cov(s_b, s_e) = -Var(s_e)/4. The SAS cell 1.0258E-12 is round-off.
// The computed zero is bounded by the standard first-order error bound for
// inverting the 3x3 Hessian, c * n * u * kappa_1(H) * max|Cov| with c = 4
// (accumulation over n = 108 observations in the traces, then the solve);
// the corpus fixture uses 0~1E-10, asserted here to cover that bound.
test "STAT-VARCOMP-001 balanced cure covariance: Var(Lab) x Var(Error) is exactly zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p = cureProblem(&cure_buf);
    const r = try reml(a, p, 1e-8, 50);
    const te = r.theta[3];
    const var_e = 2 * te * te / 81.0;
    try std.testing.expectApproxEqRel(var_e, r.cov[15], 1e-9);
    try std.testing.expectApproxEqRel(-var_e / 4, r.cov[11], 1e-9);
    try std.testing.expectApproxEqRel(-var_e / 4, r.cov[14], 1e-9);
    const f = try prepare(a, p);
    const active = [_]bool{ true, false, true, true };
    const ev = try evaluate(a, f, p.y, r.theta, &active);
    const inv = try mat.inverse(a, ev.hess, 3);
    const kappa = norm1(ev.hess, 3) * norm1(inv.values, 3);
    var maxc: f64 = 0;
    for (r.cov) |c| maxc = @max(maxc, @abs(c));
    const tol = 4 * 108 * std.math.floatEps(f64) * kappa * maxc;
    try std.testing.expect(tol <= 1e-10);
    try std.testing.expect(@abs(r.cov[3]) <= tol);
    try std.testing.expect(@abs(r.cov[12]) <= tol);
}

// Unbalanced Hemmerle-Hartley data (Output 130.1.4). SAS stops its
// Newton-Raphson at the first iterate whose objective change is below
// EPSILON = 1E-8 (p.10717), so its printed covariance is evaluated at that
// iterate, not at the exact optimum opensas reports. Two checks:
// (1) evaluating the covariance at the guide's printed final iterate
//     reproduces the guide's printed cells to their print precision, which
//     identifies the stopping point as the whole cause of the last-digit
//     differences (strict equality at the optimum is false);
// (2) bound for the corpus fixture: near the optimum the -2 REML objective is
//     quadratic with Hessian H = 2 Cov^-1, so a stop with objective gap <= eps
//     gives d' Cov^-1 d <= eps, i.e. |d_k| <= sqrt(eps Cov_kk). Each cell's
//     bound is sum_k |dCov/dtheta_k| sqrt(eps Cov_kk) (central differences),
//     and the fixture tolerances must cover it (computed: 2510.53 for
//     Var(b), 0.15419 for Var(b) x Var(Error); fixture uses 2511 / 0.155).
test "STAT-VARCOMP-001 Output 130.1.4 covariance: stopping point explains the last digits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p = hemmerle(&ab_buf);
    const f = try prepare(a, p);
    const active = [_]bool{ true, true, true };
    const covAt = struct {
        fn go(al: A, fit: Fit, y: []const f64, th: []const f64, act: []const bool) ![9]f64 {
            const ev = try evaluate(al, fit, y, th, act);
            const iv = try mat.inverse(al, ev.hess, 3);
            var c: [9]f64 = undefined;
            for (0..9) |i| c[i] = 2 * iv.values[i];
            return c;
        }
    }.go;
    const guide_cov = [_]f64{ 4401703.8, 1.29359, -273.39651, 1.29359, 3559.1, -502.85157, -273.39651, -502.85157, 1249.7 };
    const half = [_]f64{ 0.05, 5e-6, 5e-6, 5e-6, 0.05, 5e-6, 5e-6, 5e-6, 0.05 };
    const sas_final = [_]f64{ 1464.36727, 26.9588525177, 78.8423898761 };
    const at_sas = try covAt(a, f, p.y, &sas_final, &active);
    // Every cell except Var(b) x Var(Error) matches at print precision. That
    // cell evaluates to -273.396529 at both the SAS iterate and the optimum,
    // versus the printed -273.39651: a 1.9E-5 residual whose cause is NOT
    // explained (strict equality is false); it is covered only by bound (2).
    for (guide_cov, at_sas, half, 0..) |e, x, h, i| {
        if (i == 2 or i == 6) {
            try std.testing.expect(@abs(e - x) > h);
        } else try std.testing.expectApproxEqAbs(e, x, h);
    }
    const r = try reml(a, p, 1e-8, 50);
    const corpus_tol = [_]f64{ 2511, 0, 0.155, 0, 0, 0, 0.155, 0, 0 };
    var bound = [_]f64{0} ** 9;
    for (0..3) |k| {
        const d = std.math.sqrt(1e-8 * r.cov[k * 4]);
        var hi: [3]f64 = r.theta[0..3].*;
        var lo: [3]f64 = r.theta[0..3].*;
        const h = 1e-4 * r.theta[k];
        hi[k] += h;
        lo[k] -= h;
        const ch = try covAt(a, f, p.y, &hi, &active);
        const cl = try covAt(a, f, p.y, &lo, &active);
        for (0..9) |i| bound[i] += @abs((ch[i] - cl[i]) / (2 * h)) * d;
    }
    for (0..9) |i| {
        try std.testing.expect(@abs(r.cov[i] - guide_cov[i]) <= bound[i] + half[i]);
        if (corpus_tol[i] > 0) try std.testing.expect(corpus_tol[i] >= bound[i] + half[i]);
    }
}
