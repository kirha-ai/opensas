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
    if (n <= 3 or !std.math.isFinite(r) or @abs(r) >= 1) return .{};
    const z = std.math.atanh(r);
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
    const mean = if (params.len > ctx.categories.len) params[ctx.categories.len] else ctx.mean;
    const sd = if (params.len > ctx.categories.len) @exp(params[ctx.categories.len + 1]) else ctx.sd;
    if (@abs(rho) >= 0.999999) return std.math.inf(f64);
    for (1..ctx.categories.len - 1) |i| if (params[i] <= params[i - 1]) return std.math.inf(f64);
    const residual = @sqrt(1 - rho * rho);
    var ll: f64 = 0;
    for (ctx.data) |d| {
        const i = std.mem.indexOfScalar(f64, ctx.categories, d.y).?;
        const z = (d.x - mean) / sd;
        if (params.len > ctx.categories.len) ll += d.f * (@log(sd) + z * z / 2);
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
fn derivatives(ctx: Serial, params: []f64, hess: []f64, gradient: []f64) void {
    const d: f64 = 0.00005;
    const n = params.len;
    const base = serialLikelihood(ctx, params);
    for (0..n) |i| {
        const old = params[i];
        params[i] = old + d;
        const plus = serialLikelihood(ctx, params);
        params[i] = old - d;
        const minus = serialLikelihood(ctx, params);
        params[i] = old;
        gradient[i] = (plus - minus) / (2 * d);
        hess[i * n + i] = (plus - 2 * base + minus) / (d * d);
        for (0..i) |j| {
            const other = params[j];
            params[i] = old + d;
            params[j] = other + d;
            const pp = serialLikelihood(ctx, params);
            params[j] = other - d;
            const pm = serialLikelihood(ctx, params);
            params[i] = old - d;
            const mm = serialLikelihood(ctx, params);
            params[j] = other + d;
            const mp = serialLikelihood(ctx, params);
            params[i] = old;
            params[j] = other;
            hess[i * n + j] = (pp - pm - mp + mm) / (4 * d * d);
            hess[j * n + i] = hess[i * n + j];
        }
    }
}
pub fn polyserial(a: std.mem.Allocator, data: []const Observation, opt: PolyOptions) !Poly {
    var result: Poly = .{};
    const cats = try levels(a, data, false);
    defer a.free(cats);
    var sum: f64 = 0;
    for (data) |d| {
        result.n += d.f;
        sum += d.f * d.x;
    }
    if (cats.len < 2 or cats.len > opt.ngroups or result.n < 2) return result;
    const mean = sum / result.n;
    var css: f64 = 0;
    for (data) |d| css += d.f * (d.x - mean) * (d.x - mean);
    if (!(css > 0)) return result;
    var increasing = true;
    var decreasing = true;
    for (data) |d| for (data) |e| {
        if (d.y < e.y) {
            increasing = increasing and d.x < e.x;
            decreasing = decreasing and d.x > e.x;
        }
    };
    if (increasing or decreasing) {
        result.r = if (increasing) 1 else -1;
        result.converged = true;
        return result;
    }
    const ctx: Serial = .{ .data = data, .categories = cats, .mean = mean, .sd = @sqrt(css / result.n) };
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
    const hess = try a.alloc(f64, dim * dim);
    defer a.free(hess);
    const grad = try a.alloc(f64, dim);
    defer a.free(grad);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    for (0..opt.maxiter) |_| {
        const base = serialLikelihood(ctx, params);
        derivatives(ctx, params, hess, grad);
        if (!solve(hess, grad)) break;
        var scale: f64 = 1;
        var accepted = false;
        for (0..30) |_| {
            for (params, 0..) |p, i| candidate[i] = p - scale * grad[i];
            if (serialLikelihood(ctx, candidate) <= base + 1e-10) {
                accepted = true;
                break;
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
    const full = try a.alloc(f64, dim + 2);
    defer a.free(full);
    @memcpy(full[0..dim], params);
    full[dim] = mean;
    full[dim + 1] = @log(ctx.sd);
    const information = try a.alloc(f64, (dim + 2) * (dim + 2));
    defer a.free(information);
    const inverse = try a.alloc(f64, dim + 2);
    defer a.free(inverse);
    derivatives(ctx, full, information, inverse);
    @memset(inverse, 0);
    inverse[dim - 1] = 1;
    if (!solve(information, inverse) or !(inverse[dim - 1] > 0)) {
        result.converged = false;
        return result;
    }
    result.r = params[dim - 1];
    result.se = @sqrt(inverse[dim - 1]);
    result.wald = (result.r / result.se) * (result.r / result.se);
    result.p = 2 * normal(-@abs(result.r / result.se));
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
