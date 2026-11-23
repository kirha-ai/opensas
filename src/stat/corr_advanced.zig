//! CORR rank, Fisher, and reliability kernels. SAS Statistical Procedures pp21–32.
const std = @import("std");
const fns = @import("../functions.zig");
const proc = @import("../proc.zig");
const nan = std.math.nan(f64);
pub const Method = enum { pearson, spearman, kendall, hoeffding };
pub const Observation = struct { x: f64, y: f64, f: f64 = 1 };
pub const Estimate = struct { r: f64 = nan, p: f64 = nan, n: f64 = 0 };
pub fn normal(x: f64) f64 {
    return @import("corr_polychoric.zig").normalTail(-x);
}
pub fn probability(r: f64, df: f64) f64 {
    if (!(df > 0) or !std.math.isFinite(r)) return nan;
    return proc.betai(df / 2, 0.5, @max(0, (1 - @abs(r)) * (1 + @abs(r))));
}
/// Frequency multiplicities are kept compressed; ties include other copies of
/// the same input row and are equivalent to expanding the observations.
pub fn rank(a: std.mem.Allocator, data: []const Observation, method: Method) !Estimate {
    if (method == .hoeffding) return hoeffding(data);
    var result: Estimate = .{};
    for (data) |v| result.n += v.f;
    const n = result.n;
    if (n < 2) return result;
    if (method == .spearman) {
        const ranks = try a.alloc(Observation, data.len);
        defer a.free(ranks);
        for (data, 0..) |v, i| {
            var rx: f64 = 0.5;
            var ry: f64 = 0.5;
            for (data) |w| {
                if (w.x < v.x) rx += w.f else if (w.x == v.x) rx += w.f / 2;
                if (w.y < v.y) ry += w.f else if (w.y == v.y) ry += w.f / 2;
            }
            ranks[i] = .{ .x = rx, .y = ry, .f = v.f };
        }
        const mid = (n + 1) / 2;
        var xx: f64 = 0;
        var yy: f64 = 0;
        var xy: f64 = 0;
        for (ranks) |v| {
            xx += v.f * (v.x - mid) * (v.x - mid);
            yy += v.f * (v.y - mid) * (v.y - mid);
            xy += v.f * (v.x - mid) * (v.y - mid);
        }
        if (xx > 0 and yy > 0) result.r = std.math.clamp(xy / @sqrt(xx * yy), -1, 1);
        result.p = probability(result.r, n - 2);
        return result;
    }
    var score: f64 = 0;
    var tx: f64 = 0;
    var ty: f64 = 0;
    var vx: f64 = 0;
    var vy: f64 = 0;
    var ux: f64 = 0;
    var uy: f64 = 0;
    for (data, 0..) |v, i| {
        var xt: f64 = 0;
        var yt: f64 = 0;
        var firstx = true;
        var firsty = true;
        for (data, 0..) |w, j| {
            if (v.x == w.x) {
                xt += w.f;
                if (j < i) firstx = false;
            }
            if (v.y == w.y) {
                yt += w.f;
                if (j < i) firsty = false;
            }
            if (j > i) score += v.f * w.f * std.math.sign(v.x - w.x) * std.math.sign(v.y - w.y);
        }
        if (firstx) {
            tx += xt * (xt - 1);
            vx += xt * (xt - 1) * (2 * xt + 5);
            ux += xt * (xt - 1) * (xt - 2);
        }
        if (firsty) {
            ty += yt * (yt - 1);
            vy += yt * (yt - 1) * (2 * yt + 5);
            uy += yt * (yt - 1) * (yt - 2);
        }
    }
    const denom = (n * (n - 1) - tx) * (n * (n - 1) - ty);
    if (denom > 0) result.r = 2 * score / @sqrt(denom);
    if (n > 2 and denom > 0) {
        const variance = (n * (n - 1) * (2 * n + 5) - vx - vy) / 18 + tx * ty / (2 * n * (n - 1)) + ux * uy / (9 * n * (n - 1) * (n - 2));
        if (variance > 0) result.p = 2 * normal(-@abs(score) / @sqrt(variance));
    }
    return result;
}
pub const FisherOptions = struct { alpha: f64 = 0.05, rho0: f64 = 0, biasadj: bool = true, kind: enum { lower, upper, twosided } = .twosided };
pub const Fisher = struct { z: f64 = nan, bias: f64 = nan, estimate: f64 = nan, lower: f64 = nan, upper: f64 = nan, p: f64 = nan };
pub fn fisher(r: f64, count: f64, controls: usize, spearman: bool, opt: FisherOptions) Fisher {
    _ = spearman;
    const n = count - @as(f64, @floatFromInt(controls));
    if (!std.math.isFinite(r) or @abs(r) >= 1) return .{};
    const z = std.math.atanh(r);
    if (n <= 3) return .{ .z = z };
    const bias = if (opt.biasadj) r / (2 * (n - 1)) else 0;
    const se = 1 / @sqrt(n - 3);
    const q = -fns.distQuantile(.normal, opt.alpha / (if (opt.kind == .twosided) @as(f64, 2) else 1), &.{}).?;
    const testz = (z - std.math.atanh(opt.rho0) - opt.rho0 / (2 * (n - 1))) / se;
    return .{ .z = z, .bias = bias, .estimate = std.math.tanh(z - bias), .lower = if (opt.kind == .upper) -1 else std.math.tanh(z - bias - q * se), .upper = if (opt.kind == .lower) 1 else std.math.tanh(z - bias + q * se), .p = switch (opt.kind) {
        .lower => normal(-testz),
        .upper => normal(testz),
        .twosided => 2 * normal(-@abs(testz)),
    } };
}
test "CORR Fisher reports the transformed sample correlation at N=3" {
    const fit = fisher(0.5, 3, 0, false, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 0.54931), fit.z, 0.000005);
    for ([_]f64{ fit.bias, fit.estimate, fit.lower, fit.upper, fit.p }) |value|
        try std.testing.expect(std.math.isNan(value));
}
pub const AlphaRow = struct { raw: f64 = nan, standardized: f64 = nan, raw_correlation: f64 = nan, standardized_correlation: f64 = nan };
pub const Alpha = struct { raw: f64, standardized: f64, deleted: []const AlphaRow };
fn reliability(c: []const f64, n: usize, omit: ?usize) f64 {
    var trace: f64 = 0;
    var total: f64 = 0;
    for (0..n) |i| {
        if (omit == i) continue;
        trace += c[i * n + i];
        for (0..n) |j| {
            if (omit != j) total += c[i * n + j];
        }
    }
    const k: f64 = @floatFromInt(n - @as(usize, if (omit != null) 1 else 0));
    return if (k > 1 and total > 0) k / (k - 1) * (1 - trace / total) else nan;
}
fn itemCorrelation(c: []const f64, n: usize, item: usize) f64 {
    var cross: f64 = 0;
    var total: f64 = 0;
    for (0..n) |i| {
        if (i == item) continue;
        cross += c[item * n + i];
        for (0..n) |j| {
            if (j != item) total += c[i * n + j];
        }
    }
    return if (total > 0 and c[item * n + item] > 0) cross / @sqrt(total * c[item * n + item]) else nan;
}
pub fn alpha(a: std.mem.Allocator, covariance: []const f64, correlations: []const f64, n: usize) !Alpha {
    const deleted = try a.alloc(AlphaRow, n);
    for (deleted, 0..) |*d, i| d.* = .{ .raw = reliability(covariance, n, i), .standardized = reliability(correlations, n, i), .raw_correlation = itemCorrelation(covariance, n, i), .standardized_correlation = itemCorrelation(correlations, n, i) };
    return .{ .raw = reliability(covariance, n, null), .standardized = reliability(correlations, n, null), .deleted = deleted };
}

pub const PolyOptions = struct { converge: f64 = 0.0001, maxiter: usize = 200, ngroups: usize = 20, ordinal_var: bool = false };
pub const Poly = struct { r: f64 = nan, se: f64 = nan, wald: f64 = nan, p: f64 = nan, lr: f64 = nan, lr_p: f64 = nan, n: f64 = 0, converged: bool = false, unsupported_boundary: bool = false };
fn levels(a: std.mem.Allocator, data: []const Observation, x: bool) ![]f64 {
    var list: std.ArrayList(f64) = .empty;
    for (data) |d| {
        const v = if (x) d.x else d.y;
        if (std.mem.indexOfScalar(f64, list.items, v) == null) try list.append(a, v);
    }
    std.mem.sort(f64, list.items, {}, std.sort.asc(f64));
    return list.toOwnedSlice(a);
}
pub fn polychoric(a: std.mem.Allocator, data: []const Observation, opt: PolyOptions) !Poly {
    const xs = try levels(a, data, true);
    defer a.free(xs);
    const ys = try levels(a, data, false);
    defer a.free(ys);
    var result: Poly = .{};
    for (data) |d| result.n += d.f;
    if (xs.len < 2 or ys.len < 2 or xs.len > opt.ngroups or ys.len > opt.ngroups) return result;
    if (xs.len == ys.len) {
        var increasing = true;
        var decreasing = true;
        for (data) |d| {
            const ix = std.mem.indexOfScalar(f64, xs, d.x).?;
            const iy = std.mem.indexOfScalar(f64, ys, d.y).?;
            increasing = increasing and ix == iy;
            decreasing = decreasing and ix + iy + 1 == xs.len;
        }
        if (increasing or decreasing) {
            result.r = if (increasing) 1 else -1;
            result.se = 0;
            result.converged = true;
            return result;
        }
    }
    const counts = try a.alloc(f64, xs.len * ys.len);
    defer a.free(counts);
    @memset(counts, 0);
    for (data) |d| counts[std.mem.indexOfScalar(f64, xs, d.x).? * ys.len + std.mem.indexOfScalar(f64, ys, d.y).?] += d.f;
    const estimate = try @import("corr_polychoric.zig").polychoric(a, .{ .rows = xs.len, .cols = ys.len, .counts = counts, .row_scores = xs, .col_scores = ys }, .{ .converge = opt.converge, .maxiter = opt.maxiter });
    result.converged = estimate.converged;
    result.unsupported_boundary = estimate.information_unresolved;
    if (!result.converged) return result;
    result.r = estimate.coefficient.estimate orelse nan;
    result.se = estimate.coefficient.ase orelse nan;
    result.wald = if (result.se > 0) (result.r / result.se) * (result.r / result.se) else nan;
    result.p = if (result.se > 0) 2 * normal(-@abs(result.r / result.se)) else nan;
    if (estimate.likelihood_ratio) |lr| {
        result.lr = lr.statistic;
        result.lr_p = lr.p;
    }
    return result;
}
const Serial = struct { data: []const Observation, categories: []const f64, mean: f64, sd: f64 };
fn serialLikelihood(ctx: Serial, params: []const f64) f64 {
    const rho = params[ctx.categories.len - 1];
    if (@abs(rho) >= 1) return std.math.inf(f64);
    for (1..ctx.categories.len - 1) |i| if (params[i] <= params[i - 1]) return std.math.inf(f64);
    const residual = @sqrt((1 - rho) * (1 + rho));
    var ll: f64 = 0;
    for (ctx.data) |d| {
        const i = std.mem.indexOfScalar(f64, ctx.categories, d.y).?;
        const z = (d.x - ctx.mean) / ctx.sd;
        const lo = if (i == 0) -std.math.inf(f64) else (params[i - 1] - rho * z) / residual;
        const hi = if (i == ctx.categories.len - 1) std.math.inf(f64) else (params[i] - rho * z) / residual;
        const p = if (lo > 0) normal(-lo) - normal(-hi) else normal(hi) - normal(lo);
        if (!(p > 0)) return std.math.inf(f64);
        ll -= d.f * @log(p);
    }
    return ll;
}
fn solve(matrix: []f64, rhs: []f64) bool {
    const n = rhs.len;
    for (0..n) |i| {
        var pivot = i;
        for (i + 1..n) |j| {
            if (@abs(matrix[j * n + i]) > @abs(matrix[pivot * n + i])) pivot = j;
        }
        if (!std.math.isFinite(matrix[pivot * n + i]) or @abs(matrix[pivot * n + i]) < 1e-12) return false;
        for (0..n) |j| std.mem.swap(f64, &matrix[i * n + j], &matrix[pivot * n + j]);
        std.mem.swap(f64, &rhs[i], &rhs[pivot]);
        const scale = matrix[i * n + i];
        for (i..n) |j| matrix[i * n + j] /= scale;
        rhs[i] /= scale;
        for (0..n) |j| {
            if (i == j) continue;
            const f = matrix[j * n + i];
            for (i..n) |k| matrix[j * n + k] -= f * matrix[i * n + k];
            rhs[j] -= f * rhs[i];
        }
    }
    return true;
}
// Conditional cut/rho derivatives are the leading block. Standardized
// continuous location and scale supply the nuisance information used for SE.
fn serialInformation(ctx: Serial, params: []const f64, info: []f64, score: []f64, gradient: []f64) void {
    const k = params.len;
    const dim = k + 2;
    const ir = k - 1;
    const rho = params[ir];
    const s = @sqrt((1 - rho) * (1 + rho));
    const s3 = s * s * s;
    @memset(info, 0);
    @memset(gradient, 0);
    for (ctx.data) |d| {
        const z = (d.x - ctx.mean) / ctx.sd;
        const category = std.mem.indexOfScalar(f64, ctx.categories, d.y).?;
        const lo = if (category == 0) -std.math.inf(f64) else (params[category - 1] - rho * z) / s;
        const hi = if (category == ir) std.math.inf(f64) else (params[category] - rho * z) / s;
        const p = if (lo > 0) normal(-lo) - normal(-hi) else normal(hi) - normal(lo);
        if (!(p > 0)) {
            @memset(info, nan);
            return;
        }
        @memset(score, 0);
        var active: [5]usize = undefined;
        var cuts: usize = 0;
        // For each bounding CDF, dPhi(q)=phi(q)dq and
        // d²Phi(q)=phi(q)[d²q - q dq dq']. Combine before dividing by P.
        for ([_]f64{ lo, hi }, 0..) |q, edge| {
            if (!std.math.isFinite(q)) continue;
            const cut = if (edge == 0) category - 1 else category;
            active[cuts] = cut;
            cuts += 1;
            const ratio = (if (edge == 0) @as(f64, -1) else 1) * @exp(-q * q / 2) / (@sqrt(2 * std.math.pi) * p);
            const dr = (rho * params[cut] - z) / s3;
            const indices = [_]usize{ cut, ir, k, k + 1 };
            const dq = [_]f64{ 1 / s, dr, rho / s, rho * z / s };
            const d2 = [4][4]f64{
                .{ 0, rho / s3, 0, 0 },
                .{ rho / s3, params[cut] / s3 + 3 * rho * dr / (s * s), 1 / s3, z / s3 },
                .{ 0, 1 / s3, 0, -rho / s },
                .{ 0, z / s3, -rho / s, -2 * rho * z / s },
            };
            for (indices, 0..) |r, i| {
                score[r] += ratio * dq[i];
                for (indices, 0..) |c, j| info[r * dim + c] += d.f * ratio * (q * dq[i] * dq[j] - d2[i][j]);
            }
        }
        active[cuts..][0..3].* = .{ ir, k, k + 1 };
        for (active[0 .. cuts + 3]) |i| {
            gradient[i] -= d.f * score[i];
            for (active[0 .. cuts + 3]) |j| info[i * dim + j] += d.f * score[i] * score[j];
        }
        info[k * dim + k] += d.f;
        info[(k + 1) * dim + k + 1] += 2 * d.f;
    }
}
const BinaryStep = enum { ordinary, ridged, at_bound };

fn positiveBinaryInformation(a: f64, b: f64, c: f64) bool {
    return a > 0 and c > 0 and @abs(b) < @sqrt(a) * @sqrt(c);
}

fn binaryNewton(information: []const f64, at_bound: bool, gradient: []f64) ?BinaryStep {
    var a = information[0];
    const b = information[1];
    var c = information[5];
    if (!std.math.isFinite(a) or !std.math.isFinite(b) or !std.math.isFinite(c)) return null;
    if (at_bound) {
        if (!(a > 0)) return null;
        gradient[0] /= a;
        gradient[1] = 0;
        return .at_bound;
    }
    var kind: BinaryStep = .ordinary;
    if (!positiveBinaryInformation(a, b, c)) {
        // Restore positive curvature using the norm of the distinct observed
        // information entries. Choose the first positive-definite ridge on
        // the geometric sequence in either direction from norm/3.
        var ridge = std.math.hypot(std.math.hypot(a, b), c) / 3;
        if (!(ridge > 0)) return null;
        while (!positiveBinaryInformation(a + ridge, b, c + ridge)) {
            ridge *= 16;
            if (!std.math.isFinite(ridge)) return null;
        }
        while (ridge / 16 > 0 and positiveBinaryInformation(a + ridge / 16, b, c + ridge / 16)) ridge /= 16;
        a += ridge;
        c += ridge;
        kind = .ridged;
    }
    const pivot = c - (b / a) * b;
    if (!(pivot > 0)) return null;
    gradient[1] = (gradient[1] - b / a * gradient[0]) / pivot;
    gradient[0] = (gradient[0] - b * gradient[1]) / a;
    return kind;
}

fn binaryVariance(information: []const f64) ?f64 {
    for (information) |v| if (!std.math.isFinite(v)) return null;
    if (information[0] == 0 and information[5] == 0) return null;
    // Sweep the marginal location, scale, correlation, then cut. A dependent
    // or nonpositive direction contributes zero variance. Keeping rho before
    // the cut is observable for an almost separated sample with finite SE.
    const order = [_]usize{ 2, 3, 1, 0 };
    var matrix: [4][4]f64 = undefined;
    for (order, 0..) |r, i| for (order, 0..) |c, j| {
        matrix[i][j] = information[4 * r + c];
    };
    var rhs = [4]f64{ 0, 0, 1, 0 };
    for (0..4) |i| {
        const pivot = matrix[i][i];
        if (pivot < 1e-8) {
            for (0..4) |j| {
                matrix[i][j] = 0;
                matrix[j][i] = 0;
            }
            rhs[i] = 0;
            continue;
        }
        for (i..4) |j| matrix[i][j] /= pivot;
        rhs[i] /= pivot;
        for (0..4) |j| {
            if (i == j) continue;
            const factor = matrix[j][i];
            for (i..4) |k| matrix[j][k] -= factor * matrix[i][k];
            rhs[j] -= factor * rhs[i];
        }
    }
    return if (std.math.isFinite(rhs[2])) @max(0, rhs[2]) else null;
}

pub fn polyserial(a: std.mem.Allocator, data: []const Observation, opt: PolyOptions) !Poly {
    var result: Poly = .{};
    const cats = try levels(a, data, false);
    defer a.free(cats);
    if (cats.len > opt.ngroups) return result;
    var sum: f64 = 0;
    for (data) |d| {
        result.n += d.f;
        sum += d.f * d.x;
    }
    if (cats.len < 2 or result.n < 2) return result;
    const mean = sum / result.n;
    var css: f64 = 0;
    var y_sum: f64 = 0;
    const origin_y = cats[0];
    for (data) |d| {
        css += d.f * (d.x - mean) * (d.x - mean);
        y_sum += d.f * (d.y - origin_y);
    }
    const y_mean = y_sum / result.n;
    var yy: f64 = 0;
    var xy: f64 = 0;
    for (data) |d| {
        const dy = (d.y - origin_y) - y_mean;
        yy += d.f * dy * dy;
        xy += d.f * (d.x - mean) * dy;
    }
    if (!(css > 0)) return result;
    var increasing = true;
    var decreasing = true;
    for (data) |d| for (data) |e| {
        if (d.y < e.y) {
            increasing = increasing and d.x < e.x;
            decreasing = decreasing and d.x > e.x;
        }
    };
    const ctx: Serial = .{ .data = data, .categories = cats, .mean = mean, .sd = @sqrt(css / result.n) };
    if (increasing or decreasing) {
        var affine = true;
        if (cats.len == 2) {
            var level_values = [2]?f64{ null, null };
            for (data) |d| {
                const j = @intFromBool(d.y == cats[1]);
                if (level_values[j]) |previous| {
                    if (d.x != previous) {
                        affine = false;
                        break;
                    }
                } else level_values[j] = d.x;
            }
        }
        if (cats.len > 2 or affine) {
            result.r = if (increasing) 1 else -1;
            result.converged = true;
            return result;
        }
    }
    const dim = cats.len;
    const params = try a.alloc(f64, dim);
    defer a.free(params);
    for (cats[0 .. dim - 1], 0..) |c, i| {
        var below: f64 = 0;
        for (data) |d| {
            if (d.y <= c) below += d.f;
        }
        params[i] = fns.distQuantile(.normal, below / result.n, &.{}).?;
    }
    params[dim - 1] = 0;
    const null_ll = serialLikelihood(ctx, params);
    // The observed Hessian at independence can be indefinite for strongly
    // associated pairs. Initialize at the marginal Pearson correlation.
    params[dim - 1] = xy / @sqrt(css * yy);
    const information = try a.alloc(f64, (dim + 2) * (dim + 2));
    defer a.free(information);
    const score = try a.alloc(f64, dim + 2);
    defer a.free(score);
    const gradient = try a.alloc(f64, dim + 2);
    defer a.free(gradient);
    const hess = try a.alloc(f64, dim * dim);
    defer a.free(hess);
    const grad = try a.alloc(f64, dim);
    defer a.free(grad);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    const marginal_ll = result.n * (@log(ctx.sd) + 0.5 * (1 + @log(2.0 * std.math.pi)));
    const bound = @max(0.99, 1 - opt.converge / 2);
    for (0..opt.maxiter) |_| {
        const base = serialLikelihood(ctx, params);
        serialInformation(ctx, params, information, score, gradient);
        @memcpy(grad, gradient[0..dim]);
        var kind: BinaryStep = .ordinary;
        if (dim == 2) {
            kind = binaryNewton(information, @abs(params[1]) == bound, grad) orelse break;
        } else {
            for (0..dim) |j| @memcpy(hess[j * dim ..][0..dim], information[j * (dim + 2) ..][0..dim]);
            if (!solve(hess, grad)) break;
        }
        // The decrement measures the remaining local improvement against the
        // full joint likelihood, including the scale of the continuous margin.
        var decrement: f64 = 0;
        for (gradient[0..dim], grad) |g, step| decrement += g * step;
        if (decrement >= 0 and decrement <= 10000 * std.math.floatEps(f64) * @abs(base + marginal_ll)) {
            result.converged = true;
            break;
        }
        const dr = -grad[dim - 1];
        const limit = std.math.copysign(bound, dr);
        const to_limit = if (dr == 0) 0 else (limit - params[dim - 1]) / dr;
        // A nearby endpoint and its midpoint bracket the ordinary Newton
        // trial. The endpoint can be selected even when it extends the step.
        const project = dim == 2 and dr != 0 and (kind == .ridged or (to_limit > 0 and to_limit < 2));
        var scale: f64 = if (project) to_limit else 1;
        var accepted = false;
        for (0..30) |trial| {
            for (params, 0..) |p, i| candidate[i] = p - scale * grad[i];
            if (project and trial == 0) candidate[1] = limit;
            const objective = serialLikelihood(ctx, candidate);
            if (project and trial == 0) {
                const midpoint = [2]f64{ params[0] - 0.5 * scale * grad[0], (params[1] + limit) / 2 };
                if (serialLikelihood(ctx, &midpoint) < objective) {
                    scale /= 2;
                    continue;
                }
            }
            if (objective <= base + 1e-10) {
                accepted = true;
                break;
            }
            if (trial == 0 and !project) {
                const halfway = 0.5 * to_limit;
                if (halfway > 0 and halfway < 1) {
                    // A shortened correlation move also shortens every cut
                    // along the same Newton direction.
                    scale = halfway;
                    continue;
                }
            }
            scale /= 2;
        }
        if (!accepted) break;
        var change: f64 = 0;
        for (params, candidate) |p, c| change = @max(change, @abs(p - c));
        @memcpy(params, candidate);
        if (change < opt.converge) {
            result.converged = true;
            break;
        }
    }
    if (!result.converged) return result;
    serialInformation(ctx, params, information, score, gradient);
    const variance: ?f64 = if (dim == 2) binaryVariance(information) else v: {
        @memset(gradient, 0);
        gradient[dim - 1] = 1;
        break :v if (solve(information, gradient) and gradient[dim - 1] > 0) gradient[dim - 1] else null;
    };
    result.se = @sqrt(variance orelse {
        result.converged = false;
        return result;
    });
    result.r = params[dim - 1];
    if (result.se > 0) {
        result.wald = (result.r / result.se) * (result.r / result.se);
        result.p = 2 * normal(-@abs(result.r / result.se));
    }
    result.lr = @max(0, 2 * (null_ll - serialLikelihood(ctx, params)));
    result.lr_p = 2 * normal(-@sqrt(result.lr));
    return result;
}

pub fn hoeffding(data: []const Observation) Estimate {
    var result: Estimate = .{};
    for (data) |d| result.n += d.f;
    const n = result.n;
    if (n < 5) return result;
    var d1: f64 = 0;
    var d2: f64 = 0;
    var d3: f64 = 0;
    for (data) |v| {
        var rx: f64 = 0.5;
        var ry: f64 = 0.5;
        // Exclude the current copy; the other f-1 copies contribute one quarter.
        var q: f64 = 0.75;
        for (data) |w| {
            if (w.x < v.x) rx += w.f else if (w.x == v.x) rx += w.f / 2;
            if (w.y < v.y) ry += w.f else if (w.y == v.y) ry += w.f / 2;
            if (w.x < v.x and w.y < v.y) q += w.f else if (w.x == v.x and w.y == v.y) q += w.f / 4 else if ((w.x == v.x and w.y < v.y) or (w.y == v.y and w.x < v.x)) q += w.f / 2;
        }
        d1 += v.f * (q - 1) * (q - 2);
        d2 += v.f * (rx - 1) * (rx - 2) * (ry - 1) * (ry - 2);
        d3 += v.f * (rx - 2) * (ry - 2) * (q - 1);
    }
    result.r = 30 * ((n - 2) * (n - 3) * d1 + d2 - 2 * (n - 2) * d3) / (n * (n - 1) * (n - 2) * (n - 3) * (n - 4));
    result.p = @import("corr_hoeffding_probability.zig").probability(result.r, result.n);
    return result;
}

test "CORR polyserial Fitness1 RunTime and Oxygen from SAS example 2.5" {
    const observed = [_][2]f64{
        .{ 11.37, 8 },
        .{ 10.07, 9 },
        .{ 8.65, 10 },
        .{ 8.17, 11 },
        .{ 11.63, 8 },
        .{ 11.95, 9 },
        .{ 10.85, 9 },
        .{ 13.08, 7 },
        .{ 8.63, 12 },
        .{ 10.13, 10 },
        .{ 14.03, 7 },
        .{ 11.12, 8 },
        .{ 10.60, 9 },
        .{ 10.33, 10 },
        .{ 8.95, 9 },
        .{ 10.95, 8 },
        .{ 10.00, 9 },
        .{ 10.25, 9 },
        .{ 12.63, 7 },
        .{ 11.17, 9 },
        .{ 9.63, 9 },
        .{ 8.92, 10 },
        .{ 11.08, 9 },
        .{ 12.88, 7 },
        .{ 10.47, 9 },
        .{ 9.93, 10 },
        .{ 11.50, 9 },
        .{ 10.50, 9 },
    };
    var data: [observed.len]Observation = undefined;
    for (observed, &data) |v, *d| d.* = .{ .x = v[0], .y = v[1] };
    const fit = try polyserial(std.testing.allocator, &data, .{});
    try std.testing.expect(fit.converged);
    try std.testing.expectEqual(@as(f64, 28), fit.n);
    try std.testing.expectApproxEqAbs(@as(f64, -0.91042), fit.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04071), fit.se, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 500.0345), fit.wald, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 38.6963), fit.lr, 0.00005);
}

test "CORR polyserial joint likelihood scale controls the final Newton update" {
    const observations = [_]Observation{
        .{ .x = -1.699, .y = 0, .f = 1 },
        .{ .x = 3.177, .y = 2, .f = 1 },
        .{ .x = -1.437, .y = 1, .f = 5 },
        .{ .x = -0.216, .y = 2, .f = 4 },
        .{ .x = 6.056, .y = 1, .f = 4 },
        .{ .x = 3.596, .y = 2, .f = 3 },
        .{ .x = 1.577, .y = 1, .f = 2 },
        .{ .x = -6.034, .y = 0, .f = 5 },
        .{ .x = 3.635, .y = 2, .f = 2 },
        .{ .x = -2.391, .y = 0, .f = 1 },
        .{ .x = -0.065, .y = 2, .f = 1 },
        .{ .x = 1.288, .y = 2, .f = 6 },
        .{ .x = -0.425, .y = 1, .f = 2 },
        .{ .x = 2.199, .y = 1, .f = 4 },
        .{ .x = -2.077, .y = 0, .f = 2 },
        .{ .x = 0.65, .y = 1, .f = 6 },
        .{ .x = 2.285, .y = 2, .f = 3 },
        .{ .x = 2.275, .y = 2, .f = 5 },
        .{ .x = 4.241, .y = 2, .f = 6 },
        .{ .x = -1.212, .y = 1, .f = 2 },
        .{ .x = -0.587, .y = 2, .f = 1 },
        .{ .x = -2.21, .y = 2, .f = 1 },
        .{ .x = 6.12, .y = 2, .f = 4 },
    };
    for ([_]f64{ 1, 1048576, 1.0 / 1048576.0 }) |scale| {
        var data = observations;
        for (&data) |*d| d.x *= scale;
        const at_four = try polyserial(std.testing.allocator, &data, .{ .maxiter = 4, .converge = 1e-10 });
        try std.testing.expectEqual(scale != 1, at_four.converged);
        if (at_four.converged) try std.testing.expectApproxEqAbs(@as(f64, 0.68377621855765), at_four.r, 1e-12);
        const fit = try polyserial(std.testing.allocator, &data, .{ .converge = 1e-10 });
        const expected: f64 = if (scale == 1) 0.68377458477580 else 0.68377621855765;
        try std.testing.expectApproxEqAbs(expected, fit.r, 1e-12);
    }
}

test "CORR polyserial shortens both thresholds and correlation on a rejected step" {
    const data = [_]Observation{
        .{ .x = 2.612, .y = 2, .f = 4 },
        .{ .x = -3.36, .y = 1, .f = 6 },
        .{ .x = -1.262, .y = 1, .f = 5 },
        .{ .x = -3.008, .y = 1, .f = 6 },
        .{ .x = 1.25, .y = 1, .f = 1 },
        .{ .x = -0.568, .y = 0, .f = 1 },
        .{ .x = 1.829, .y = 2, .f = 3 },
        .{ .x = 1.45, .y = 1, .f = 5 },
        .{ .x = -4.449, .y = 0, .f = 4 },
        .{ .x = -1.326, .y = 1, .f = 3 },
        .{ .x = -0.953, .y = 1, .f = 1 },
        .{ .x = 1.687, .y = 2, .f = 6 },
        .{ .x = 0.484, .y = 1, .f = 5 },
        .{ .x = 1.668, .y = 2, .f = 1 },
        .{ .x = -3.812, .y = 1, .f = 6 },
        .{ .x = -1.221, .y = 0, .f = 4 },
        .{ .x = 4.922, .y = 2, .f = 5 },
        .{ .x = 1.8, .y = 1, .f = 2 },
        .{ .x = 2.963, .y = 2, .f = 3 },
        .{ .x = 2.91, .y = 2, .f = 1 },
        .{ .x = 0.799, .y = 2, .f = 6 },
        .{ .x = 1.977, .y = 1, .f = 1 },
        .{ .x = 1.76, .y = 2, .f = 1 },
        .{ .x = 4.85, .y = 2, .f = 6 },
        .{ .x = -1.913, .y = 1, .f = 6 },
        .{ .x = 5.31, .y = 2, .f = 5 },
        .{ .x = -1.538, .y = 2, .f = 1 },
        .{ .x = -1.137, .y = 1, .f = 2 },
        .{ .x = 0.921, .y = 2, .f = 2 },
        .{ .x = -1.94, .y = 0, .f = 2 },
        .{ .x = 3.764, .y = 2, .f = 2 },
        .{ .x = -3.78, .y = 0, .f = 2 },
        .{ .x = -0.956, .y = 2, .f = 1 },
        .{ .x = 2.754, .y = 2, .f = 5 },
        .{ .x = -1.512, .y = 0, .f = 6 },
        .{ .x = 3.864, .y = 2, .f = 3 },
        .{ .x = 4.187, .y = 2, .f = 1 },
    };
    const first = try polyserial(std.testing.allocator, &data, .{ .converge = 0.3, .maxiter = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.86989065214826), first.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02526779447916), first.se, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 99.3876369375033), first.lr, 1e-10);
    const second = try polyserial(std.testing.allocator, &data, .{ .converge = 0.12, .maxiter = 2 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.84206670280242), second.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03345008464088), second.se, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 101.129366689651), second.lr, 1e-10);
    const tight = try polyserial(std.testing.allocator, &data, .{ .converge = 1e-10 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.82922750554063), tight.r, 1e-12);
}

test "CORR separated binary polyserial threshold, reflected units, and information rank" {
    const a = std.testing.allocator;
    var data: [8]Observation = undefined;
    for ([_]f64{ 1, -16 }) |scale| {
        for (&data, 0..) |*d, i| d.* = .{ .x = scale * @as(f64, @floatFromInt(i + 1)) + 100, .y = if (i < 4) 0 else 1 };
        const sign: f64 = if (scale > 0) 1 else -1;
        for ([_]usize{ 1, 2, 4, 8, 16, 32, 200 }) |cap| {
            for ([_]f64{ 0.01, 0.0001, 0.000001 }) |tolerance| {
                const fit = try polyserial(a, &data, .{ .maxiter = cap, .converge = tolerance });
                if (cap == 1 or tolerance == 0.000001) {
                    try std.testing.expect(!fit.converged);
                    try std.testing.expect(std.math.isNan(fit.r) and std.math.isNan(fit.se) and std.math.isNan(fit.lr));
                } else {
                    const loose = tolerance == 0.01;
                    try std.testing.expectApproxEqAbs(sign * (1 - tolerance / 2), fit.r, 1e-13);
                    try std.testing.expectApproxEqAbs(@as(f64, if (loose) 0.01873725665189 else 0), fit.se, 1e-13);
                    try std.testing.expectApproxEqAbs(@as(f64, if (loose) 11.0304970502865 else 11.0903548889591), fit.lr, 1e-12);
                    if (!loose) try std.testing.expect(std.math.isNan(fit.wald));
                }
            }
        }
    }
    const tied = [_]Observation{
        .{ .x = 7, .y = 1, .f = 3 }, .{ .x = 2, .y = 0, .f = 1 },
        .{ .x = 6, .y = 1, .f = 2 }, .{ .x = 1, .y = 0, .f = 3 },
        .{ .x = 2, .y = 0, .f = 1 },
    };
    const compressed = [_]Observation{ .{ .x = 1, .y = 0, .f = 3 }, .{ .x = 2, .y = 0, .f = 2 }, .{ .x = 6, .y = 1, .f = 2 }, .{ .x = 7, .y = 1, .f = 3 } };
    const compressed_fit = try polyserial(a, &compressed, .{ .converge = 0.01 });
    const tied_fit = try polyserial(a, &tied, .{ .converge = 0.01 });
    try std.testing.expectApproxEqAbs(compressed_fit.r, tied_fit.r, 1e-12);
    try std.testing.expectApproxEqAbs(compressed_fit.lr, tied_fit.lr, 1e-12);
    for (&data, 0..) |*d, i| d.* = .{ .x = @log(@as(f64, @floatFromInt(i + 2))), .y = if (i < 3) 0 else 1, .f = @floatFromInt((i + 1) % 3 + 1) };
    const asymmetric = try polyserial(a, &data, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 0.99995), asymmetric.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 62.2280906596448), asymmetric.se, 1e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 22.0744440656105), asymmetric.lr, 1e-11);
}

test "CORR binary polyserial separates continuous scale from the iteration cap" {
    const xs = [_]f64{ -8, -7, -3, -1, 1, 3, 5 };
    const frequencies = [_]f64{ 1, 2, 2, 1, 3, 2, 1 };
    var data: [xs.len]Observation = undefined;
    for (&data, xs, frequencies, 0..) |*d, x, f, i| d.* = .{ .x = x, .y = if (i < 4) 0 else 1, .f = f };
    const options: PolyOptions = .{ .maxiter = 8, .converge = 0.0001 };
    const original = try polyserial(std.testing.allocator, &data, options);
    try std.testing.expect(!original.converged);
    try std.testing.expectEqual(@as(f64, 12), original.n);
    for (&data) |*d| d.x = 64 - 8 * d.x;
    const reflected = try polyserial(std.testing.allocator, &data, options);
    try std.testing.expectApproxEqAbs(@as(f64, -0.99995), reflected.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.26221114484028), reflected.se, 1e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 16.6355323332525), reflected.lr, 1e-11);
}

test "CORR partially overlapping binary categories return inside the correlation bound" {
    const xs = [_]f64{ -13, -11.75, -4.375, -4, -1.25, -0.875, 3, 4, 5.875, 6.75 };
    const ys = [_]f64{ 1, 1, 1, 1, 0, 1, 0, 0, 0, 0 };
    const frequencies = [_]f64{ 4, 1, 5, 4, 4, 3, 1, 2, 1, 4 };
    var data: [xs.len]Observation = undefined;
    for (&data, xs, ys, frequencies) |*d, x, y, f| d.* = .{ .x = x, .y = y, .f = f };
    const fit = try polyserial(std.testing.allocator, &data, .{ .converge = 0.01 });
    try std.testing.expectApproxEqAbs(@as(f64, -0.97652920115824), fit.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02404594247376), fit.se, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 27.8786552569544), fit.lr, 1e-11);
}

test "CORR probes a nearby binary endpoint beyond the ordinary Newton step" {
    const xs = [_]f64{ -9.5, -3, -2.875, -2.625, -0.5, 1.625, 1.875, 2.375, 6.625, 8.875 };
    const frequencies = [_]f64{ 4, 1, 5, 2, 1, 5, 2, 1, 5, 2 };
    var data: [xs.len]Observation = undefined;
    for (&data, xs, frequencies, 0..) |*d, x, f, i| d.* = .{ .x = x, .y = if (i < 2) 0 else 1, .f = f };
    const early = try polyserial(std.testing.allocator, &data, .{ .converge = 0.01, .maxiter = 5 });
    try std.testing.expect(!early.converged);
    const fit = try polyserial(std.testing.allocator, &data, .{ .converge = 0.01, .maxiter = 6 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.995), fit.r, 1e-12);
    try std.testing.expectEqual(@as(f64, 0), fit.se);
    try std.testing.expectApproxEqAbs(@as(f64, 21.2736613123838), fit.lr, 1e-11);
}
