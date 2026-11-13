//! CORR-specific specialization of the existing FREQ joint polychoric MLE.
//! CORR requires absolute parameter-change convergence (Statistical Procedures
//! p14); keeping this specialization local avoids changing FREQ's relative rule.
const std = @import("std");
const fns = @import("../functions.zig");
const Error = @import("../diag.zig").Error;
const CountMatrix = @import("freq_tests.zig").CountMatrix;
const Measure = @import("freq_tests.zig").Measure;
const Test = @import("freq_tests.zig").Test;
fn sq(x: f64) f64 {
    return x * x;
}
fn sum(xs: []const f64) f64 {
    var total: f64 = 0;
    for (xs) |x| total += x;
    return total;
}
fn countValid(xs: []const f64) bool {
    for (xs) |x| if (!std.math.isFinite(x) or x < 0) return false;
    return std.math.isFinite(sum(xs)) and sum(xs) > 0;
}
fn measure(est: f64, variance: f64, null_variance: f64, alpha: f64) Measure {
    _ = null_variance;
    _ = alpha;
    return .{ .estimate = if (std.math.isFinite(est)) est else null, .ase = if (std.math.isFinite(variance) and variance >= 0) @sqrt(variance) else null };
}
fn chi(x: f64, df: f64) Test {
    const statistic = @max(0, x);
    return .{ .statistic = statistic, .df = df, .p = chiTail(statistic, df) };
}
const Margins = struct { row: []f64, col: []f64, n: f64, nr: usize, nc: usize };
fn margins(a: std.mem.Allocator, m: CountMatrix) Error!Margins {
    if (m.rows == 0 or m.cols == 0 or m.rows > std.math.maxInt(usize) / m.cols or m.counts.len != m.rows * m.cols or !countValid(m.counts)) return error.ExecError;
    if (m.row_scores) |s| {
        if (s.len != m.rows) return error.ExecError;
        for (s) |v| if (!std.math.isFinite(v)) return error.ExecError;
    }
    if (m.col_scores) |s| {
        if (s.len != m.cols) return error.ExecError;
        for (s) |v| if (!std.math.isFinite(v)) return error.ExecError;
    }
    const r = try a.alloc(f64, m.rows);
    const c = try a.alloc(f64, m.cols);
    @memset(r, 0);
    @memset(c, 0);
    for (m.counts, 0..) |v, k| {
        r[k / m.cols] += v;
        c[k % m.cols] += v;
    }
    var nr: usize = 0;
    var nc: usize = 0;
    for (r) |v| {
        if (v > 0) nr += 1;
    }
    for (c) |v| {
        if (v > 0) nc += 1;
    }
    return .{ .row = r, .col = c, .n = sum(r), .nr = nr, .nc = nc };
}
pub const PolychoricOptions = struct { adjust: bool = false, converge: f64 = 0.0001, maxiter: usize = 200, alpha: f64 = 0.05 };
pub const Polychoric = struct { coefficient: Measure, likelihood_ratio: ?Test, converged: bool, iterations: usize };
fn normalCdf(x: f64) f64 {
    return fns.distCdf(.normal, x, &.{}).?;
}
fn normalPdf(x: f64) f64 {
    return @exp(-x * x / 2) / @sqrt(2 * std.math.pi);
}
/// Plackett integral with rho=sin(theta), avoiding the endpoint square-root.
fn bivariateCdf(x: f64, y: f64, rho: f64) f64 {
    if (x <= -9 or y <= -9) return 0;
    if (x >= 9) return normalCdf(y);
    if (y >= 9) return normalCdf(x);
    if (rho == 0) return normalCdf(x) * normalCdf(y);
    const angle = std.math.asin(rho);
    const segments = 1024;
    const h = angle / segments;
    var integral: f64 = 0;
    for (0..segments + 1) |i| {
        const t = h * @as(f64, @floatFromInt(i));
        const s = @sin(t);
        const c = @cos(t);
        const v = @exp(-(x * x - 2 * s * x * y + y * y) / (2 * c * c));
        integral += v * @as(f64, if (i == 0 or i == segments) 1 else if (i % 2 == 0) 2 else 4);
    }
    return normalCdf(x) * normalCdf(y) + h * integral / (6 * std.math.pi);
}
fn cellProbability(m: CountMatrix, params: []const f64, i: usize, j: usize) f64 {
    const rho = params[params.len - 1];
    const xl = if (i == 0) -10 else params[i - 1];
    const xu = if (i + 1 == m.rows) 10 else params[i];
    const yl = if (j == 0) -10 else params[m.rows + j - 2];
    const yu = if (j + 1 == m.cols) 10 else params[m.rows + j - 1];
    return @max(0, bivariateCdf(xu, yu, rho) - bivariateCdf(xl, yu, rho) - bivariateCdf(xu, yl, rho) + bivariateCdf(xl, yl, rho));
}
fn negativeLogLikelihood(m: CountMatrix, params: []const f64) f64 {
    if (@abs(params[params.len - 1]) >= 0.999999) return std.math.inf(f64);
    for (1..m.rows - 1) |i| if (params[i] <= params[i - 1]) return std.math.inf(f64);
    for (m.rows..params.len - 1) |j| if (params[j] <= params[j - 1]) return std.math.inf(f64);
    var result: f64 = 0;
    for (m.counts, 0..) |n, k| {
        if (n == 0) continue;
        const p = cellProbability(m, params, k / m.cols, k % m.cols);
        if (p <= 0) return std.math.inf(f64);
        result -= n * @log(p);
    }
    return result;
}
/// Pivoted solve; callers retain the original matrix when they need its inverse.
fn linearSolve(matrix: []f64, rhs: []f64) bool {
    const n = rhs.len;
    for (0..n) |i| {
        var pivot = i;
        for (i + 1..n) |j| if (@abs(matrix[j * n + i]) > @abs(matrix[pivot * n + i])) {
            pivot = j;
        };
        if (@abs(matrix[pivot * n + i]) < 1e-12) return false;
        for (0..n) |k| std.mem.swap(f64, &matrix[i * n + k], &matrix[pivot * n + k]);
        std.mem.swap(f64, &rhs[i], &rhs[pivot]);
        const scale = matrix[i * n + i];
        for (i..n) |k| matrix[i * n + k] /= scale;
        rhs[i] /= scale;
        for (0..n) |j| {
            if (j == i) continue;
            const factor = matrix[j * n + i];
            for (i..n) |k| matrix[j * n + k] -= factor * matrix[i * n + k];
            rhs[j] -= factor * rhs[i];
        }
    }
    return true;
}
pub fn polychoric(a: std.mem.Allocator, input: CountMatrix, opts: PolychoricOptions) Error!Polychoric {
    if (!(opts.alpha > 0 and opts.alpha < 1) or !std.math.isFinite(opts.converge) or opts.converge <= 0 or opts.maxiter == 0) return error.ExecError;
    var m = input;
    const counts = try a.dupe(f64, input.counts);
    defer a.free(counts);
    m.counts = counts;
    if (opts.adjust and m.rows == 2 and m.cols == 2 and counts.len == 4) {
        var zeros: usize = 0;
        var zero: usize = 0;
        for (counts, 0..) |v, k| if (v == 0) {
            zeros += 1;
            zero = k;
        };
        if (zeros == 1) {
            counts[zero] += 0.5;
            counts[3 - zero] += 0.5;
            counts[zero ^ 1] -= 0.5;
            counts[zero ^ 2] -= 0.5;
        }
    }
    const t = try margins(a, m);
    defer a.free(t.row);
    defer a.free(t.col);
    if (t.nr < 2 or t.nc < 2 or t.nr != m.rows or t.nc != m.cols) return error.ExecError;
    const dim = m.rows + m.cols - 1;
    const params = try a.alloc(f64, dim);
    defer a.free(params);
    var cum: f64 = 0;
    for (t.row[0 .. m.rows - 1], 0..) |v, i| {
        cum += v / t.n;
        params[i] = fns.distQuantile(.normal, cum, &.{}).?;
    }
    cum = 0;
    for (t.col[0 .. m.cols - 1], 0..) |v, j| {
        cum += v / t.n;
        params[m.rows + j - 1] = fns.distQuantile(.normal, cum, &.{}).?;
    }
    params[dim - 1] = 0;
    const null_ll = negativeLogLikelihood(m, params);
    if (m.rows == 2 and m.cols == 2 and ((counts[1] == 0 and counts[2] == 0) or (counts[0] == 0 and counts[3] == 0))) {
        const r: f64 = if (counts[1] == 0) 1 else -1;
        return .{ .coefficient = measure(r, 0, 0, opts.alpha), .likelihood_ratio = null, .converged = true, .iterations = 0 };
    }
    // SAS reports the constrained tetrachoric boundary as +/-0.999 for
    // exactly one zero cell without ADJUST; the likelihood is saturated.
    // Oracle boundary.sas: rho=-0.9990, ASE=0, LR=17.2930 for [0,9;11,3].
    if (m.rows == 2 and m.cols == 2 and !opts.adjust) {
        var zero_count: usize = 0;
        var zero_index: usize = 0;
        for (counts, 0..) |v, i| if (v == 0) {
            zero_count += 1;
            zero_index = i;
        };
        if (zero_count == 1) {
            var saturated: f64 = 0;
            for (counts) |v| if (v > 0) {
                saturated -= v * @log(v / t.n);
            };
            const rho: f64 = if (zero_index == 0 or zero_index == 3) -0.999 else 0.999;
            return .{ .coefficient = measure(rho, 0, 0, opts.alpha), .likelihood_ratio = chi(2 * (null_ll - saturated), 1), .converged = true, .iterations = 0 };
        }
    }
    const hessian = try a.alloc(f64, dim * dim);
    defer a.free(hessian);
    const gradient = try a.alloc(f64, dim);
    defer a.free(gradient);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    const delta: f64 = 0.0001;
    var converged = false;
    var iterations: usize = 0;
    while (iterations < opts.maxiter) {
        iterations += 1;
        const base = negativeLogLikelihood(m, params);
        for (0..dim) |i| {
            const old = params[i];
            params[i] = old + delta;
            const plus = negativeLogLikelihood(m, params);
            params[i] = old - delta;
            const minus = negativeLogLikelihood(m, params);
            params[i] = old;
            gradient[i] = (plus - minus) / (2 * delta);
            hessian[i * dim + i] = (plus - 2 * base + minus) / sq(delta);
            for (0..i) |j| {
                const other = params[j];
                params[i] = old + delta;
                params[j] = other + delta;
                const pp = negativeLogLikelihood(m, params);
                params[j] = other - delta;
                const pm = negativeLogLikelihood(m, params);
                params[i] = old - delta;
                const mm = negativeLogLikelihood(m, params);
                params[j] = other + delta;
                const mp = negativeLogLikelihood(m, params);
                params[i] = old;
                params[j] = other;
                const value = (pp - pm - mp + mm) / (4 * sq(delta));
                hessian[i * dim + j] = value;
                hessian[j * dim + i] = value;
            }
        }
        if (!linearSolve(hessian, gradient)) break;
        var scale: f64 = 1;
        var accepted = false;
        for (0..30) |_| {
            for (params, 0..) |p, i| candidate[i] = p - scale * gradient[i];
            if (negativeLogLikelihood(m, candidate) <= base + 1e-10) {
                accepted = true;
                break;
            }
            scale /= 2;
        }
        if (!accepted) break;
        var change: f64 = 0;
        for (params, candidate) |p, c| change = @max(change, @abs(c - p));
        @memcpy(params, candidate);
        if (change < opts.converge) {
            converged = true;
            break;
        }
    }
    if (!converged) return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations };
    // Expected multinomial information for simultaneous thresholds and rho.
    @memset(hessian, 0);
    for (m.counts, 0..) |_, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        const p = cellProbability(m, params, i, j);
        if (p <= 0) continue;
        for (0..dim) |l| {
            const old = params[l];
            params[l] = old + delta;
            const plus = cellProbability(m, params, i, j);
            params[l] = old - delta;
            const minus = cellProbability(m, params, i, j);
            params[l] = old;
            gradient[l] = (plus - minus) / (2 * delta);
        }
        for (0..dim) |r| for (0..dim) |c| {
            hessian[r * dim + c] += t.n * gradient[r] * gradient[c] / p;
        };
    }
    @memset(gradient, 0);
    gradient[dim - 1] = 1;
    const variance = if (linearSolve(hessian, gradient)) gradient[dim - 1] else std.math.nan(f64);
    return .{ .coefficient = measure(params[dim - 1], variance, variance, opts.alpha), .likelihood_ratio = chi(2 * (null_ll - negativeLogLikelihood(m, params)), 1), .converged = converged, .iterations = iterations };
}

fn chiTail(x: f64, df: f64) f64 {
    const a = df / 2;
    const z = x / 2;
    if (z < a + 1) return @max(0, 1 - fns.gammaP(a, z));
    const tiny: f64 = 1e-300;
    var b = z + 1 - a;
    var c: f64 = 1 / tiny;
    var d = 1 / b;
    var h = d;
    for (1..10000) |k| {
        const i: f64 = @floatFromInt(k);
        const an = -i * (i - a);
        b += 2;
        d = an * d + b;
        if (@abs(d) < tiny) d = tiny;
        c = b + an / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1 / d;
        const delta = d * c;
        h *= delta;
        if (@abs(delta - 1) < 1e-15) break;
    }
    return @max(0, @min(1, @exp(-z + a * @log(z) - fns.lgammaOf(a)) * h));
}
