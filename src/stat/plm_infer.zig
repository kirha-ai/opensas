//! Stored-model inference for PROC PLM (S154 physical pp.7620–7627, "Getting
//! Started"): the quantities behind SHOW FIT, SHOW PARMS and TEST, computed
//! from the restored native GLM store only (no access to the original data).
//!
//! The store holds a full-rank sum-to-zero basis b with MSE-scaled covariance
//! C. SAS displays the singular GLM (less-than-full-rank) parameterisation.
//! Both describe the same mean vector on every cell of the CLASS grid, so with
//! F = sum-to-zero design and S = singular design on the complete grid, and K
//! the singular columns that are NOT linear combinations of earlier columns
//! (the columns the in-order sweep keeps; all others are set to zero),
//!     S_K g = F b   =>   g = T b,  T = (S_K' S_K)^-1 S_K' F,  Var(g) = T C T'.
//! The identity is exact when span(S) == span(F) on the grid; that is checked
//! (rank(S) == p and S_K T == F) and anything else is refused, never guessed.
const std = @import("std");
const store = @import("store.zig");
const fProbability = @import("reg_fit.zig").fProbability;
const A = std.mem.Allocator;

pub const Error = error{ OutOfMemory, Unsupported };
pub const Parm = struct {
    /// Null = Intercept, else index into Model.effects.
    effect: ?usize,
    /// One entry per Model.classes: the level index this row refers to.
    levels: []const ?usize,
    estimate: f64,
    /// Null for a parameter the sweep sets to zero (printed as '.').
    stderr: ?f64,
    /// False when the parameter is not uniquely estimable (PROC GLM's 'B'
    /// flag): some null vector of the singular design has a nonzero entry here.
    estimable: bool = true,
};
pub const EffectTest = struct { num_df: usize, den_df: usize, f: f64, p: f64 };

const max_cells = 20000;
const max_work = 8_000_000;

fn classOnly(m: store.Model) bool {
    if (m.covariates.len != 0) return false;
    for (m.effects) |e| for (e.factors) |f| if (f.class_index == null) return false;
    return true;
}

/// GLM singular-parameterisation estimates and standard errors, in SAS order
/// (last factor of an interaction varies fastest).
pub fn parameters(a: A, m: store.Model) Error![]const Parm {
    // ponytail: covariate models need the grid extended by covariate columns;
    // refused until a SAS reference for such a store exists.
    if (!classOnly(m)) return error.Unsupported;
    const p = m.coefficients.len;
    const nc = m.classes.len;
    var n: usize = 1;
    for (m.classes) |c| {
        if (c.levels.len == 0) return error.Unsupported;
        n = std.math.mul(usize, n, c.levels.len) catch return error.Unsupported;
        if (n > max_cells) return error.Unsupported;
    }
    // Singular column catalogue.
    var parms: std.ArrayList(Parm) = .empty;
    if (m.intercept) try parms.append(a, .{ .effect = null, .levels = try nulls(a, nc), .estimate = 0, .stderr = null });
    for (m.effects, 0..) |e, ei| {
        var width: usize = 1;
        for (e.factors) |f| width *= m.classes[f.class_index.?].levels.len;
        for (0..width) |j| {
            const lv = try nulls(a, nc);
            var radix = j;
            var k = e.factors.len;
            while (k > 0) {
                k -= 1;
                const ci = e.factors[k].class_index.?;
                const count = m.classes[ci].levels.len;
                // A class repeated inside one effect is not a GLM effect shape handled here.
                if (lv[ci] != null) return error.Unsupported;
                lv[ci] = radix % count;
                radix /= count;
            }
            try parms.append(a, .{ .effect = ei, .levels = lv, .estimate = 0, .stderr = null });
        }
    }
    const q = parms.items.len;
    if (n * (q + p) > max_work) return error.Unsupported;
    const f_design = try a.alloc(f64, n * p);
    const s_design = try a.alloc(f64, n * q);
    const cell = try a.alloc(usize, nc);
    for (0..n) |r| {
        var radix = r;
        for (cell, m.classes) |*l, c| {
            l.* = radix % c.levels.len;
            radix /= c.levels.len;
        }
        // Same coding as store.row: first factor fastest, last level = -1.
        const fr = f_design[r * p ..][0..p];
        @memset(fr, 0);
        if (m.intercept) fr[0] = 1;
        for (m.effects) |e| for (0..e.len) |j| {
            var rj = j;
            var product: f64 = 1;
            for (e.factors) |factor| {
                const ci = factor.class_index.?;
                const count = m.classes[ci].levels.len;
                const term = rj % (count - 1);
                rj /= count - 1;
                product *= if (cell[ci] == count - 1) @as(f64, -1) else if (cell[ci] == term) 1 else 0;
            }
            fr[e.start + j] = product;
        };
        for (parms.items, 0..) |parm, j| {
            var hit = true;
            for (parm.levels, cell) |want, have| {
                if (want) |w| hit = hit and w == have;
            }
            s_design[r * q + j] = if (hit) 1 else 0;
        }
    }
    // Modified Gram-Schmidt in column order: a column whose residual vanishes
    // is a linear combination of earlier columns (zeroed by the sweep).
    const kept = try a.alloc(usize, p);
    const qm = try a.alloc(f64, n * p);
    const rm = try a.alloc(f64, p * p);
    @memset(rm, 0);
    const work = try a.alloc(f64, n);
    const coef = try a.alloc(f64, p);
    var rank: usize = 0;
    for (0..q) |j| {
        var norm0: f64 = 0;
        for (work, 0..) |*w, r| {
            w.* = s_design[r * q + j];
            norm0 += w.* * w.*;
        }
        for (0..rank) |k| {
            var dot: f64 = 0;
            for (work, 0..) |w, r| dot += w * qm[r * p + k];
            coef[k] = dot;
            for (work, 0..) |*w, r| w.* -= dot * qm[r * p + k];
        }
        var norm: f64 = 0;
        for (work) |w| norm += w * w;
        // 0/1 columns on an integer grid: a dependent column leaves rounding
        // noise ~1e-30 while an independent one keeps at least 1/n of its mass.
        if (norm <= 1e-10 * norm0) {
            // S_j = S_K c with c = R^-1 (Q' S_j): (c, -1 at j) is a null vector,
            // so j and every kept column with c != 0 are not estimable.
            parms.items[j].estimable = false;
            var u = rank;
            while (u > 0) {
                u -= 1;
                var v = coef[u];
                for (u + 1..rank) |w| v -= rm[u * p + w] * coef[w];
                coef[u] = v / rm[u * p + u];
                if (@abs(coef[u]) > 1e-9) parms.items[kept[u]].estimable = false;
            }
            continue;
        }
        if (rank == p) return error.Unsupported;
        const scale = @sqrt(norm);
        for (work, 0..) |w, r| qm[r * p + rank] = w / scale;
        for (0..rank) |k| rm[k * p + rank] = coef[k];
        rm[rank * p + rank] = scale;
        kept[rank] = j;
        rank += 1;
    }
    if (rank != p) return error.Unsupported;
    // T = R^-1 Q' F.
    const tm = try a.alloc(f64, p * p);
    for (0..p) |k| for (0..p) |c| {
        var dot: f64 = 0;
        for (0..n) |r| dot += qm[r * p + k] * f_design[r * p + c];
        tm[k * p + c] = dot;
    };
    var k = p;
    while (k > 0) {
        k -= 1;
        for (0..p) |c| {
            var v = tm[k * p + c];
            for (k + 1..p) |u| v -= rm[k * p + u] * tm[u * p + c];
            tm[k * p + c] = v / rm[k * p + k];
        }
    }
    // span(S_K) must contain F exactly, otherwise the two parameterisations
    // are different models and no faithful mapping exists.
    for (0..n) |r| for (0..p) |c| {
        var v: f64 = 0;
        for (0..p) |u| v += s_design[r * q + kept[u]] * tm[u * p + c];
        if (@abs(v - f_design[r * p + c]) > 1e-8) return error.Unsupported;
    };
    for (0..p) |u| {
        var estimate: f64 = 0;
        var variance: f64 = 0;
        for (0..p) |c| {
            estimate += tm[u * p + c] * m.coefficients[c];
            for (0..p) |d| variance += tm[u * p + c] * m.covariance[c * p + d] * tm[u * p + d];
        }
        if (!std.math.isFinite(estimate) or !std.math.isFinite(variance) or variance < 0) return error.Unsupported;
        parms.items[kept[u]].estimate = estimate;
        parms.items[kept[u]].stderr = @sqrt(variance);
    }
    return parms.items;
}
fn nulls(a: A, n: usize) ![]?usize {
    const out = try a.alloc(?usize, n);
    @memset(out, null);
    return out;
}

/// Type III F test of one model effect. In a CLASS-only model whose
/// sum-to-zero basis has full rank, the Type III hypothesis for an effect is
/// that the effect's own sum-to-zero coefficients b_E vanish, so
///     F = b_E' (C_EE)^-1 b_E / q,   q = len(b_E),
/// with C_EE the (already MSE-scaled) covariance block and the residual
/// degrees of freedom in the denominator.
pub fn type3(a: A, m: store.Model, effect: usize) Error!EffectTest {
    if (!classOnly(m)) return error.Unsupported;
    const e = m.effects[effect];
    const q = e.len;
    const p = m.coefficients.len;
    if (q == 0) return error.Unsupported;
    const l = try a.alloc(f64, q * q);
    const z = try a.alloc(f64, q);
    // Cholesky C_EE = L L'; solve L z = b_E; quadratic form = z'z.
    for (0..q) |i| {
        for (0..i + 1) |j| {
            var v = m.covariance[(e.start + i) * p + e.start + j];
            for (0..j) |u| v -= l[i * q + u] * l[j * q + u];
            if (i == j) {
                if (!(v > 1e-12 * m.covariance[(e.start + i) * p + e.start + i])) return error.Unsupported;
                l[i * q + i] = @sqrt(v);
            } else l[i * q + j] = v / l[j * q + j];
        }
        var v = m.coefficients[e.start + i];
        for (0..i) |u| v -= l[i * q + u] * z[u];
        z[i] = v / l[i * q + i];
    }
    var quad: f64 = 0;
    for (z) |v| quad += v * v;
    const f = quad / @as(f64, @floatFromInt(q));
    if (!std.math.isFinite(f)) return error.Unsupported;
    return .{ .num_df = q, .den_df = m.df_error, .f = f, .p = fProbability(f, q, m.df_error) };
}
