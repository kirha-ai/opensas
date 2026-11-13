//! CORR joint polychoric MLE: positive normal rectangle probabilities, analytic
//! cell derivatives and Fisher scoring. SAS uses Pearson initialization and the
//! information from the final scoring linearization; retained boundary oracles
//! distinguish these from zero initialization and post-update information.
const std = @import("std");
const fns = @import("../functions.zig");
const Error = @import("../diag.zig").Error;
const CountMatrix = @import("freq_tests.zig").CountMatrix;
const Measure = @import("freq_tests.zig").Measure;
const Test = @import("freq_tests.zig").Test;
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
pub const Polychoric = struct { coefficient: Measure, likelihood_ratio: ?Test, converged: bool, iterations: usize, information_unresolved: bool = false };
/// Accurate normal upper tail; erfc avoids subtracting a CDF from one.
pub fn normalTail(x: f64) f64 {
    if (std.math.isNan(x)) return x;
    const tail = @min(0.5, erfccheb(@abs(x) / @sqrt(2.0)) / 2);
    return if (x >= 0) tail else 1 - tail;
}
fn normalPdf(x: f64) f64 {
    return @exp(-x * x / 2) / @sqrt(2 * std.math.pi);
}
fn erfccheb(z: f64) f64 {
    const cof = [_]f64{
        -1.3026537197817094,   6.4196979235649026e-1, 1.9476473204185836e-2,
        -9.561514786808631e-3, -9.46595344482036e-4,  3.66839497852761e-4,
        4.2523324806907e-5,    -2.0278578112534e-5,   -1.624290004647e-6,
        1.303655835580e-6,     1.5626441722e-8,       -8.5238095915e-8,
        6.529054439e-9,        5.059343495e-9,        -9.91364156e-10,
        -2.27365122e-10,       9.6467911e-11,         2.394038e-12,
        -6.886027e-12,         8.94487e-13,           3.13092e-13,
        -1.12708e-13,          3.81e-16,              7.106e-15,
        -1.523e-15,            -9.4e-17,              1.21e-16,
        -2.8e-17,
    };
    const tc = 2.0 / (2.0 + z);
    const ty = 4.0 * tc - 2.0;
    var d: f64 = 0;
    var dd: f64 = 0;
    var j: usize = cof.len - 1;
    while (j > 0) : (j -= 1) {
        const tmp = d;
        d = ty * d - dd + cof[j];
        dd = tmp;
    }
    return tc * @exp(-z * z + 0.5 * (cof[0] + ty * d) - dd);
}

// Positive conditional-normal integration avoids subtracting four nearly equal
// bivariate CDFs. Split at every conditional transition before adaptive Simpson.
const Rectangle = struct {
    yl: f64,
    yu: f64,
    rho: f64,
    sd: f64,
    fn value(self: @This(), x: f64) f64 {
        return normalPdf(x) * normalInterval((self.yl - self.rho * x) / self.sd, (self.yu - self.rho * x) / self.sd);
    }
};
fn normalInterval(lo: f64, hi: f64) f64 {
    if (lo > 0) return (erfccheb(lo / @sqrt(2.0)) - erfccheb(hi / @sqrt(2.0))) / 2;
    if (hi < 0) return (erfccheb(-hi / @sqrt(2.0)) - erfccheb(-lo / @sqrt(2.0))) / 2;
    return 1 - (erfccheb(-lo / @sqrt(2.0)) + erfccheb(hi / @sqrt(2.0))) / 2;
}
fn integrateRectangle(f: Rectangle, a: f64, b: f64, fa: f64, fb: f64, fc: f64, whole: f64, tolerance: f64, depth: usize) f64 {
    const c = (a + b) / 2;
    const fl = f.value((a + c) / 2);
    const fr = f.value((c + b) / 2);
    const left = (c - a) * (fa + 4 * fl + fc) / 6;
    const right = (b - c) * (fc + 4 * fr + fb) / 6;
    if (depth == 0 or @abs(left + right - whole) <= 15 * tolerance) return left + right + (left + right - whole) / 15;
    return integrateRectangle(f, a, c, fa, fc, fl, left, tolerance / 2, depth - 1) + integrateRectangle(f, c, b, fc, fb, fr, right, tolerance / 2, depth - 1);
}
pub fn rectangleProbability(xl: f64, xu: f64, yl: f64, yu: f64, rho: f64) f64 {
    if (rho == 0) return normalInterval(xl, xu) * normalInterval(yl, yu);
    const f: Rectangle = .{ .yl = yl, .yu = yu, .rho = rho, .sd = @sqrt((1 - rho) * (1 + rho)) };
    var cuts: [23]f64 = undefined;
    cuts[0] = xl;
    cuts[1] = xu;
    var len: usize = 2;
    for ([_]f64{ 0, -8, -4, -2, 2, 4, 8 }) |x| {
        if (x > xl and x < xu) {
            cuts[len] = x;
            len += 1;
        }
    }
    for ([_]f64{ yl, yu }) |y| for ([_]f64{ -12, -8, -4, 0, 4, 8, 12 }) |k| {
        const x = (y + k * f.sd) / rho;
        if (x > xl and x < xu) {
            cuts[len] = x;
            len += 1;
        }
    };
    std.mem.sort(f64, cuts[0..len], {}, std.sort.asc(f64));
    var total: f64 = 0;
    for (cuts[0 .. len - 1], cuts[1..len]) |a, b| {
        if (a == b) continue;
        const fa = f.value(a);
        const fb = f.value(b);
        const fc = f.value((a + b) / 2);
        const whole = (b - a) * (fa + 4 * fc + fb) / 6;
        total += integrateRectangle(f, a, b, fa, fb, fc, whole, @max(@abs(whole) * 1e-10, 1e-300), 18);
    }
    return @max(0, total);
}
fn cellProbability(m: CountMatrix, params: []const f64, i: usize, j: usize) f64 {
    const xl = if (i == 0) -40 else params[i - 1];
    const xu = if (i + 1 == m.rows) 40 else params[i];
    const yl = if (j == 0) -40 else params[m.rows + j - 2];
    const yu = if (j + 1 == m.cols) 40 else params[m.rows + j - 1];
    return rectangleProbability(xl, xu, yl, yu, params[params.len - 1]);
}
fn bivariateDensity(x: f64, y: f64, rho: f64) f64 {
    const variance = (1 - rho) * (1 + rho);
    return @exp(-((x - rho * y) * (x - rho * y) / variance + y * y) / 2) / (2 * std.math.pi * @sqrt(variance));
}
fn cellGradient(m: CountMatrix, params: []const f64, i: usize, j: usize, out: []f64) void {
    @memset(out, 0);
    const rho = params[params.len - 1];
    const sd = @sqrt((1 - rho) * (1 + rho));
    const xl = if (i == 0) -40 else params[i - 1];
    const xu = if (i + 1 == m.rows) 40 else params[i];
    const yl = if (j == 0) -40 else params[m.rows + j - 2];
    const yu = if (j + 1 == m.cols) 40 else params[m.rows + j - 1];
    if (i > 0) out[i - 1] = -normalPdf(xl) * normalInterval((yl - rho * xl) / sd, (yu - rho * xl) / sd);
    if (i + 1 < m.rows) out[i] = normalPdf(xu) * normalInterval((yl - rho * xu) / sd, (yu - rho * xu) / sd);
    if (j > 0) out[m.rows + j - 2] = -normalPdf(yl) * normalInterval((xl - rho * yl) / sd, (xu - rho * yl) / sd);
    if (j + 1 < m.cols) out[m.rows + j - 1] = normalPdf(yu) * normalInterval((xl - rho * yu) / sd, (xu - rho * yu) / sd);
    out[params.len - 1] = bivariateDensity(xu, yu, rho) - bivariateDensity(xl, yu, rho) - bivariateDensity(xu, yl, rho) + bivariateDensity(xl, yl, rho);
}
fn negativeLogLikelihood(m: CountMatrix, params: []const f64) f64 {
    if (@abs(params[params.len - 1]) >= 1) return std.math.inf(f64);
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
    var sx: f64 = 0;
    var sy: f64 = 0;
    var xx: f64 = 0;
    var yy: f64 = 0;
    var xy: f64 = 0;
    for (m.counts, 0..) |n, index| {
        const x: f64 = if (m.row_scores) |scores| scores[index / m.cols] - scores[0] else @floatFromInt(index / m.cols);
        const y: f64 = if (m.col_scores) |scores| scores[index % m.cols] - scores[0] else @floatFromInt(index % m.cols);
        sx += n * x;
        sy += n * y;
        xx += n * x * x;
        yy += n * y * y;
        xy += n * x * y;
    }
    params[dim - 1] = (xy - sx * sy / t.n) / @sqrt((xx - sx * sx / t.n) * (yy - sy * sy / t.n));
    const hessian = try a.alloc(f64, dim * dim);
    defer a.free(hessian);
    const gradient = try a.alloc(f64, dim);
    defer a.free(gradient);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    const derivatives = try a.alloc(f64, dim);
    defer a.free(derivatives);
    const saved_information = try a.alloc(f64, dim * dim);
    defer a.free(saved_information);
    var concordant = false;
    var discordant = false;
    var saturated: f64 = 0;
    for (m.counts, 0..) |n, i| {
        if (n == 0) continue;
        saturated -= n * @log(n / t.n);
        for (m.counts, 0..) |other, j| {
            if (other == 0) continue;
            const dr = @as(i64, @intCast(i / m.cols)) - @as(i64, @intCast(j / m.cols));
            const dc = @as(i64, @intCast(i % m.cols)) - @as(i64, @intCast(j % m.cols));
            concordant = concordant or dr * dc > 0;
            discordant = discordant or dr * dc < 0;
        }
    }
    const boundary = !(concordant and discordant);
    var converged = false;
    var iterations: usize = 0;
    while (iterations < opts.maxiter) {
        iterations += 1;
        const base = negativeLogLikelihood(m, params);
        @memset(hessian, 0);
        @memset(gradient, 0);
        for (m.counts, 0..) |n, cell| {
            const i = cell / m.cols;
            const j = cell % m.cols;
            const probability = cellProbability(m, params, i, j);
            if (!(probability > 0)) continue;
            cellGradient(m, params, i, j, derivatives);
            for (0..dim) |r| {
                gradient[r] -= n * derivatives[r] / probability;
                for (0..dim) |c| hessian[r * dim + c] += t.n * derivatives[r] * derivatives[c] / probability;
            }
        }
        @memcpy(saved_information, hessian);
        if (!linearSolve(hessian, gradient)) break;
        var scale: f64 = 1;
        var accepted = false;
        for (0..30) |_| {
            for (params, 0..) |p, i| candidate[i] = p - scale * gradient[i];
            // SAS first-step oracle: an overshoot is restarted at +/-0.999,
            // rather than halving all coordinates solely to force |rho|<1.
            if (@abs(candidate[dim - 1]) >= 1) candidate[dim - 1] = if (candidate[dim - 1] > 0) 0.999 else -0.999;
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
        if (boundary and negativeLogLikelihood(m, params) - saturated <= t.n * 1e-10) {
            // The likelihood gap is below the rectangle quadrature's relative
            // error budget. A finite Wald SE is not numerically certified here.
            return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations, .information_unresolved = true };
        }
        if (change < opts.converge) {
            converged = true;
            break;
        }
    }
    if (!converged) return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations };
    // SAS uses the information matrix from the final scoring linearization.
    // Re-evaluating at the updated rho materially changes sparse-boundary SEs.
    @memcpy(hessian, saved_information);
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
