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
    const estimate = try @import("corr_polychoric.zig").polychoric(a, .{ .rows = xs.len, .cols = ys.len, .counts = counts, .row_scores = xs, .col_scores = ys }, .{
        // CORR centers the Pearson start at the first pair retained by FREQ and missing-value rules.
        .score_origin = .{ data[0].x, data[0].y },
        .converge = opt.converge,
        .maxiter = opt.maxiter,
    });
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
const NewtonStep = enum { ordinary, ridged, at_bound };

/// Cholesky factors the free coordinates of the observed information.
/// The final fit includes two additional marginal coordinates.
fn factorInformation(info: []const f64, stride: usize, free: usize, ridge: f64, factor: []f64) bool {
    for (0..free) |i| {
        for (0..i + 1) |j| {
            var value = info[i * stride + j];
            if (i == j) value += ridge;
            for (0..j) |k| value -= factor[i * free + k] * factor[j * free + k];
            if (!std.math.isFinite(value)) return false;
            if (i == j) {
                if (value <= 0) return false;
                factor[i * free + j] = @sqrt(value);
            } else factor[i * free + j] = value / factor[j * free + j];
        }
    }
    return true;
}

fn newtonStep(info: []const f64, at_bound: bool, grad: []f64, factor: []f64) ?NewtonStep {
    const stride = grad.len + 2;
    const free = grad.len - @intFromBool(at_bound);
    var kind: NewtonStep = if (at_bound) .at_bound else .ordinary;
    // Once rho is fixed, check the relative information of the remaining
    // cuts before using their Newton decrement. A nearly unidentified cut
    // otherwise produces a spurious converged fit. Frequency replication
    // must not change this rank decision.
    if (at_bound) {
        var largest: f64 = 0;
        var smallest = std.math.inf(f64);
        for (0..free) |i| {
            const diagonal = info[i * stride + i];
            largest = @max(largest, diagonal);
            smallest = @min(smallest, diagonal);
        }
        if (!(smallest > largest * 1e-8)) return null;
    }
    if (!factorInformation(info, stride, free, 0, factor)) {
        var norm: f64 = 0;
        for (0..free) |i| {
            for (0..i + 1) |j| norm = std.math.hypot(norm, info[i * stride + j]);
        }
        var ridge = norm / (@as(f64, @floatFromInt(free * (free + 1))) / 2);
        if (!(ridge > 0) or !std.math.isFinite(ridge)) return null;
        while (!factorInformation(info, stride, free, ridge, factor)) {
            ridge *= 16;
            if (!std.math.isFinite(ridge)) return null;
        }
        // Try one lower ridge after positive curvature has been restored.
        if (ridge / 16 > 0 and factorInformation(info, stride, free, ridge / 16, factor)) ridge /= 16;
        if (!factorInformation(info, stride, free, ridge, factor)) return null;
        if (!at_bound) kind = .ridged;
    }
    for (0..free) |i| {
        for (0..i) |j| grad[i] -= factor[i * free + j] * grad[j];
        grad[i] /= factor[i * free + i];
    }
    for (0..free) |rev| {
        const i = free - 1 - rev;
        for (i + 1..free) |j| grad[i] -= factor[j * free + i] * grad[j];
        grad[i] /= factor[i * free + i];
    }
    if (at_bound) grad[grad.len - 1] = 0;
    return kind;
}

fn sweepIndex(i: usize, categories: usize) usize {
    return switch (i) {
        0 => categories,
        1 => categories + 1,
        2 => categories - 1,
        else => i - 3,
    };
}

fn correlationVariance(matrix: []f64, rhs: []f64, at_bound: bool) ?f64 {
    const stride = rhs.len;
    const categories = stride - 2;
    const rho = categories - 1;
    var has_information = false;
    for (matrix) |v| if (!std.math.isFinite(v)) return null;
    for (0..categories) |i| if (matrix[i * stride + i] != 0) {
        has_information = true;
        break;
    };
    if (!has_information) return null;
    @memset(rhs, 0);
    rhs[rho] = 1;
    // Sweep the marginal location and scale, correlation, then thresholds.
    for (0..stride) |row| {
        const i = sweepIndex(row, categories);
        const pivot = matrix[i * stride + i];
        if (pivot < 1e-8) {
            // A free correlation needs positive information after removing
            // the continuous margin. Only a fixed boundary can have zero SE.
            if (i == rho and !at_bound) return null;
            for (0..stride) |j| {
                matrix[i * stride + j] = 0;
                matrix[j * stride + i] = 0;
            }
            rhs[i] = 0;
            continue;
        }
        for (row..stride) |col| matrix[i * stride + sweepIndex(col, categories)] /= pivot;
        rhs[i] /= pivot;
        for (0..stride) |j| {
            if (i == j) continue;
            const scale = matrix[j * stride + i];
            for (row..stride) |col| {
                const k = sweepIndex(col, categories);
                matrix[j * stride + k] -= scale * matrix[i * stride + k];
            }
            rhs[j] -= scale * rhs[i];
        }
    }
    return if (std.math.isFinite(rhs[rho])) @max(0, rhs[rho]) else null;
}

// If the conditional fit fails, a one-to-one order of the observed values
// determines the sign of the limiting correlation without identifying its error.
fn serialFallback(result: Poly, ctx: Serial, values: []f64) Poly {
    @memset(values, nan);
    for (ctx.data) |d| {
        const j = std.mem.indexOfScalar(f64, ctx.categories, d.y).?;
        if (std.math.isNan(values[j])) values[j] = d.x else if (d.x != values[j]) return result;
    }
    const increasing = values[1] > values[0];
    for (values[1..], values[0 .. values.len - 1]) |right, left| {
        if ((increasing and right <= left) or (!increasing and right >= left)) return result;
    }
    return .{ .n = result.n, .r = if (increasing) 1 else -1, .converged = true };
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
    const ctx: Serial = .{ .data = data, .categories = cats, .mean = mean, .sd = @sqrt(css / result.n) };
    const start_r = xy / @sqrt(css * yy);
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
    // associated pairs. Pull a large marginal Pearson correlation halfway
    // back toward 0.9 for the initial joint fit.
    params[dim - 1] = if (@abs(start_r) > 0.9) (start_r + std.math.copysign(@as(f64, 0.9), start_r)) / 2 else start_r;
    const information = try a.alloc(f64, (dim + 2) * (dim + 2));
    defer a.free(information);
    const score = try a.alloc(f64, dim + 2);
    defer a.free(score);
    const gradient = try a.alloc(f64, dim + 2);
    defer a.free(gradient);
    const factor = try a.alloc(f64, dim * dim);
    defer a.free(factor);
    const grad = try a.alloc(f64, dim);
    defer a.free(grad);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    const marginal_ll = result.n * (@log(ctx.sd) + 0.5 * (1 + @log(2.0 * std.math.pi)));
    const bound = @max(0.99, 1 - opt.converge / 2);
    var consecutive_ridges: usize = 0;
    for (0..opt.maxiter) |_| {
        const base = serialLikelihood(ctx, params);
        serialInformation(ctx, params, information, score, gradient);
        @memcpy(grad, gradient[0..dim]);
        const kind = newtonStep(information, @abs(params[dim - 1]) == bound, grad, factor) orelse break;
        if (kind == .ridged) {
            consecutive_ridges += 1;
            if (consecutive_ridges > 10) break;
        } else consecutive_ridges = 0;
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
        const projection_limit: f64 = if (kind == .ridged) 10 else 2;
        const project = to_limit > 0 and to_limit < projection_limit;
        var scale: f64 = if (project) to_limit else 1;
        var accepted = false;
        for (0..30) |trial| {
            for (params, 0..) |p, i| candidate[i] = p - scale * grad[i];
            if (project and trial == 0) candidate[dim - 1] = limit;
            const objective = serialLikelihood(ctx, candidate);
            if (project and trial == 0) {
                // Compare the endpoint with a retraction no longer than the
                // ordinary Newton step. This is also the next step if it wins.
                const retraction = @min(1, scale / 2);
                for (params, 0..) |v, i| score[i] = v - retraction * grad[i];
                if (serialLikelihood(ctx, score[0..dim]) < objective) {
                    scale = retraction;
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
    if (!result.converged) return serialFallback(result, ctx, params);
    serialInformation(ctx, params, information, score, gradient);
    const variance = correlationVariance(information, gradient, @abs(params[dim - 1]) == bound);
    result.se = @sqrt(variance orelse {
        result.converged = false;
        return serialFallback(result, ctx, params);
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
    const Reference = struct { tolerance: f64, first_success: usize, lr: f64 };
    for ([_]Reference{
        .{ .tolerance = 0.01, .first_success = 6, .lr = 21.2736613123838 },
        .{ .tolerance = 0.008, .first_success = 8, .lr = 21.3767589182459 },
        .{ .tolerance = 0.006, .first_success = 8, .lr = 21.5215656621666 },
        .{ .tolerance = 0.004, .first_success = 9, .lr = 21.7492337767932 },
        .{ .tolerance = 0.00174230229798, .first_success = 17, .lr = 22.3050902699286 },
    }) |ref| {
        const early = try polyserial(std.testing.allocator, &data, .{ .converge = ref.tolerance, .maxiter = ref.first_success - 1 });
        try std.testing.expect(!early.converged);
        const fit = try polyserial(std.testing.allocator, &data, .{ .converge = ref.tolerance, .maxiter = ref.first_success });
        try std.testing.expectApproxEqAbs(1 - ref.tolerance / 2, fit.r, 1e-12);
        try std.testing.expectEqual(@as(f64, 0), fit.se);
        try std.testing.expectApproxEqAbs(ref.lr, fit.lr, 1e-11);
    }
    const unbounded = try polyserial(std.testing.allocator, &data, .{ .converge = 0.001, .maxiter = 1000 });
    try std.testing.expect(!unbounded.converged);
    try std.testing.expect(std.math.isNan(unbounded.r) and std.math.isNan(unbounded.se) and std.math.isNan(unbounded.lr));
}

test "CORR rejects an unidentified interior polyserial correlation" {
    const xs = [_]f64{ -9.5, -3, -2.875, -2.625, -0.5, 1.625, 1.875, 2.375, 6.625, 8.875 };
    const frequencies = [_]f64{ 4, 1, 5, 2, 1, 5, 2, 1, 5, 2 };
    var data: [xs.len]Observation = undefined;
    for (&data, xs, frequencies, 0..) |*d, x, f, i| d.* = .{ .x = x, .y = if (i < 2) 0 else 1, .f = f };
    const interior = try polyserial(std.testing.allocator, &data, .{ .converge = 0.999, .maxiter = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.85273567684712), interior.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.84641999442579), interior.se, 1e-12);
    data[9].x = 9.375;
    const unidentified = try polyserial(std.testing.allocator, &data, .{ .converge = 0.999, .maxiter = 1 });
    try std.testing.expect(!unidentified.converged);
    try std.testing.expectEqual(@as(f64, 28), unidentified.n);
    try std.testing.expect(std.math.isNan(unidentified.r) and std.math.isNan(unidentified.se) and std.math.isNan(unidentified.lr));
    const later = try polyserial(std.testing.allocator, &data, .{ .converge = 0.1, .maxiter = 2 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.91162567840006), later.r, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.12697158584352), later.se, 1e-12);
}

test "CORR polyserial refines multiple thresholds at the correlation limit" {
    const sample = [_]Observation{
        .{ .x = 0, .y = 0, .f = 2 },  .{ .x = 1, .y = 0, .f = 3 },
        .{ .x = 4, .y = 1, .f = 2 },  .{ .x = 5, .y = 1, .f = 1 },
        .{ .x = 7, .y = 1, .f = 3 },  .{ .x = 11, .y = 2, .f = 1 },
        .{ .x = 13, .y = 2, .f = 3 }, .{ .x = 17, .y = 3, .f = 3 },
        .{ .x = 20, .y = 3, .f = 2 },
    };
    const Reference = struct { rows: usize, n: f64, loose_lr: f64, se: f64, lr: f64 };
    for ([_]Reference{
        .{ .rows = 7, .n = 15, .loose_lr = 31.0221204994084, .se = 0.01854056085855, .lr = 32.54847870752 },
        .{ .rows = 9, .n = 20, .loose_lr = 48.8362793662018, .se = 0.00820483578153, .lr = 54.8829228418885 },
    }) |ref| {
        const data = sample[0..ref.rows];
        const loose = try polyserial(std.testing.allocator, data, .{ .converge = 0.5, .maxiter = 1 });
        try std.testing.expectApproxEqAbs(@as(f64, 0.99), loose.r, 1e-13);
        try std.testing.expectEqual(@as(f64, 0), loose.se);
        try std.testing.expectApproxEqAbs(ref.loose_lr, loose.lr, 1e-12);
        const early = try polyserial(std.testing.allocator, data, .{ .converge = 0.01, .maxiter = 5 });
        try std.testing.expect(!early.converged);
        const fit = try polyserial(std.testing.allocator, data, .{ .converge = 0.01 });
        try std.testing.expectApproxEqAbs(@as(f64, 0.995), fit.r, 1e-13);
        try std.testing.expectApproxEqAbs(ref.se, fit.se, 1e-13);
        try std.testing.expectApproxEqAbs(ref.lr, fit.lr, 1e-12);
        const unidentified = try polyserial(std.testing.allocator, data, .{});
        try std.testing.expect(!unidentified.converged and std.math.isNan(unidentified.r));
        try std.testing.expectEqual(ref.n, unidentified.n);
    }
}

test "CORR polyserial fits ordered singleton levels before inferring a perfect correlation" {
    var data = [_]Observation{ .{ .x = 0, .y = 0, .f = 2 }, .{ .x = 1, .y = 1, .f = 3 }, .{ .x = 2, .y = 2, .f = 4 } };
    const loose = try polyserial(std.testing.allocator, &data, .{ .converge = 0.5, .maxiter = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.99), loose.r, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04625421046509), loose.se, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 19.0711762740653), loose.lr, 1e-12);
    const affine = try polyserial(std.testing.allocator, &data, .{ .converge = 0.01 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.995), affine.r, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 6.8828210825935), affine.se, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 19.0954250461286), affine.lr, 1e-12);
    for ([_]f64{ 1, -1 }) |sign| {
        data[1].x = sign;
        data[2].x = 15 * sign;
        const first = try polyserial(std.testing.allocator, &data, .{ .converge = 0.17172, .maxiter = 1 });
        try std.testing.expectApproxEqAbs(sign * 0.99, first.r, 1e-13);
        try std.testing.expectApproxEqAbs(@as(f64, 15.4445465820126), first.lr, 1e-12);
        const exhausted = try polyserial(std.testing.allocator, &data, .{ .converge = 0.17170, .maxiter = 1 });
        try std.testing.expectEqual(sign, exhausted.r);
        try std.testing.expect(std.math.isNan(exhausted.se) and std.math.isNan(exhausted.lr));
    }
    data[1].x = 1;
    data[2].x = 13.10920;
    const identified = try polyserial(std.testing.allocator, &data, .{ .converge = 0.1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.99), identified.r, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 15.8116500170551), identified.lr, 1e-12);
    data[2].x = 13.10923;
    const dependent = try polyserial(std.testing.allocator, &data, .{ .converge = 0.1 });
    try std.testing.expectEqual(@as(f64, 1), dependent.r);
    try std.testing.expect(std.math.isNan(dependent.se) and std.math.isNan(dependent.lr));
}
