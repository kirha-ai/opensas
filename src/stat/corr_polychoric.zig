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
pub const PolychoricOptions = struct {
    adjust: bool = false,
    converge: f64 = 0.0001,
    maxiter: usize = 200,
    alpha: f64 = 0.05,
    score_origin: ?[2]f64 = null,
};
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

fn conditionalVariance(rho: f64) f64 {
    return @mulAdd(f64, -rho, rho, 1);
}

fn conditionalCut(bound: f64, given: f64, rho: f64, sd: f64) f64 {
    return @mulAdd(f64, -rho, given, bound) / sd;
}

// Positive conditional-normal integration avoids subtracting four nearly equal
// bivariate CDFs. Split at every conditional transition before adaptive quadrature.
const Rectangle = struct {
    yl: f64,
    yu: f64,
    rho: f64,
    sd: f64,
    fn value(self: @This(), x: f64) f64 {
        return normalPdf(x) * normalInterval(conditionalCut(self.yl, x, self.rho, self.sd), conditionalCut(self.yu, x, self.rho, self.sd));
    }
};
fn normalInterval(lo: f64, hi: f64) f64 {
    if (lo > 0) return (erfccheb(lo / @sqrt(2.0)) - erfccheb(hi / @sqrt(2.0))) / 2;
    if (hi < 0) return (erfccheb(-hi / @sqrt(2.0)) - erfccheb(-lo / @sqrt(2.0))) / 2;
    return 1 - (erfccheb(-lo / @sqrt(2.0)) + erfccheb(hi / @sqrt(2.0))) / 2;
}
const QuadraturePanel = struct { lo: f64, hi: f64, value: f64, err: f64 };

/// Embedded Gauss 7 / Kronrod 15 rule. Nodes/weights are mathematical constants
/// from QUADPACK DQK15; variation and roundoff protect the error estimate against
/// an accidentally small difference between the two rules.
fn rectanglePanel(f: Rectangle, a: f64, b: f64) QuadraturePanel {
    const nodes = [_]f64{ 0.9914553711208126392, 0.9491079123427585245, 0.8648644233597690728, 0.7415311855993944399, 0.5860872354676911303, 0.4058451513773971669, 0.2077849550078984676 };
    const kronrod_weights = [_]f64{ 0.022935322010529225, 0.063092092629978553, 0.104790010322250184, 0.140653259715525919, 0.169004726639267903, 0.190350578064785410, 0.204432940075298892, 0.209482141084727828 };
    const gauss_weights = [_]f64{ 0.129484966168869693, 0.279705391489276668, 0.381830050505118945, 0.417959183673469388 };
    const middle = (a + b) / 2;
    const half = (b - a) / 2;
    const fc = f.value(middle);
    var kronrod = kronrod_weights[7] * fc;
    var gauss = gauss_weights[3] * fc;
    var absolute = kronrod_weights[7] * @abs(fc);
    var low: [7]f64 = undefined;
    var high: [7]f64 = undefined;
    for (nodes, 0..) |node, i| {
        low[i] = f.value(middle - half * node);
        high[i] = f.value(middle + half * node);
        kronrod += kronrod_weights[i] * (low[i] + high[i]);
        absolute += kronrod_weights[i] * (@abs(low[i]) + @abs(high[i]));
        if (i % 2 == 1) gauss += gauss_weights[i / 2] * (low[i] + high[i]);
    }
    const mean = kronrod / 2;
    var variation = kronrod_weights[7] * @abs(fc - mean);
    for (low, high, 0..) |l, h, i| variation += kronrod_weights[i] * (@abs(l - mean) + @abs(h - mean));
    variation *= @abs(half);
    absolute *= @abs(half);
    var err = @abs((kronrod - gauss) * half);
    if (variation > 0 and err > 0) err = variation * @min(1, std.math.pow(f64, 200 * err / variation, 1.5));
    err = @max(err, 50 * std.math.floatEps(f64) * absolute);
    return .{ .lo = a, .hi = b, .value = kronrod * half, .err = err };
}

fn integrateRectangle(f: Rectangle, a: f64, b: f64) f64 {
    var panels: [4096]QuadraturePanel = undefined;
    panels[0] = rectanglePanel(f, a, b);
    var len: usize = 1;
    while (true) {
        var value: f64 = 0;
        var err: f64 = 0;
        var worst: usize = 0;
        for (panels[0..len], 0..) |p, i| {
            if (!std.math.isFinite(p.value) or !std.math.isFinite(p.err)) return std.math.nan(f64);
            value += p.value;
            err += p.err;
            if (p.err > panels[worst].err) worst = i;
        }
        // Recompute the relative budget from the current estimate, rather than
        // permanently dividing a potentially underestimated first-panel budget.
        if (err <= @max(@abs(value) * 1e-10, 1e-300)) return value;
        if (len == panels.len) return std.math.nan(f64);
        const previous = panels[worst];
        const middle = (previous.lo + previous.hi) / 2;
        if (middle == previous.lo or middle == previous.hi) return std.math.nan(f64);
        panels[worst] = rectanglePanel(f, previous.lo, middle);
        panels[len] = rectanglePanel(f, middle, previous.hi);
        len += 1;
    }
}
pub fn rectangleProbability(xl: f64, xu: f64, yl: f64, yu: f64, rho: f64) f64 {
    if (rho == 0) return normalInterval(xl, xu) * normalInterval(yl, yu);
    // The derivative of a normal rectangle probability at independence is
    // the product of the two endpoint density differences (Mehler's expansion).
    // Retain the linear term when the remaining terms are below roundoff.
    const x_bound = @max(1, @abs(xl), @abs(xu));
    const y_bound = @max(1, @abs(yl), @abs(yu));
    if (@abs(rho) * x_bound * y_bound <= @sqrt(std.math.floatEps(f64))) {
        const independent = normalInterval(xl, xu) * normalInterval(yl, yu);
        const derivative = (normalPdf(xl) - normalPdf(xu)) * (normalPdf(yl) - normalPdf(yu));
        return @max(0, @mulAdd(f64, rho, derivative, independent));
    }
    const f: Rectangle = .{ .yl = yl, .yu = yu, .rho = rho, .sd = @sqrt(conditionalVariance(rho)) };
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
        const probability = integrateRectangle(f, a, b);
        if (!std.math.isFinite(probability)) return probability;
        total += probability;
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
    const variance = conditionalVariance(rho);
    const dx = @mulAdd(f64, -rho, y, x);
    const exponent = @mulAdd(f64, dx / variance, dx, y * y);
    return @exp(-exponent / 2) / (2 * std.math.pi * @sqrt(variance));
}
fn cellGradient(m: CountMatrix, params: []const f64, i: usize, j: usize, out: []f64) void {
    @memset(out, 0);
    const rho = params[params.len - 1];
    const sd = @sqrt(conditionalVariance(rho));
    const xl = if (i == 0) -40 else params[i - 1];
    const xu = if (i + 1 == m.rows) 40 else params[i];
    const yl = if (j == 0) -40 else params[m.rows + j - 2];
    const yu = if (j + 1 == m.cols) 40 else params[m.rows + j - 1];
    if (i > 0) out[i - 1] = -normalPdf(xl) * normalInterval(conditionalCut(yl, xl, rho, sd), conditionalCut(yu, xl, rho, sd));
    if (i + 1 < m.rows) out[i] = normalPdf(xu) * normalInterval(conditionalCut(yl, xu, rho, sd), conditionalCut(yu, xu, rho, sd));
    if (j > 0) out[m.rows + j - 2] = -normalPdf(yl) * normalInterval(conditionalCut(xl, yl, rho, sd), conditionalCut(xu, yl, rho, sd));
    if (j + 1 < m.cols) out[m.rows + j - 1] = normalPdf(yu) * normalInterval(conditionalCut(xl, yu, rho, sd), conditionalCut(xu, yu, rho, sd));
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
        if (!std.math.isFinite(p) or p <= 0) return std.math.inf(f64);
        result -= n * @log(p);
    }
    return result;
}
/// Rank-aware information solve. The absolute 1e-8 pivot decision is pinned
/// by native CORR frequency transitions; SINGULAR= governs PARTIAL instead.
/// Dropped coordinates have zero solution/variance, as a generalized sweep.
/// Nonfinite or malformed input is unavailable, never a zero-variance result.
pub fn solveInformation(matrix: []f64, rhs: []f64) ?usize {
    const n = rhs.len;
    if (n != 0 and n > std.math.maxInt(usize) / n) return null;
    if (matrix.len != n * n) return null;
    for (matrix) |value| if (!std.math.isFinite(value)) return null;
    for (rhs) |value| if (!std.math.isFinite(value)) return null;
    var rank: usize = 0;
    for (0..n) |i| {
        var pivot = i;
        for (i + 1..n) |j| if (@abs(matrix[j * n + i]) > @abs(matrix[pivot * n + i])) {
            pivot = j;
        };
        if (@abs(matrix[pivot * n + i]) < 1e-8) {
            for (0..n) |j| {
                matrix[j * n + i] = 0;
                matrix[i * n + j] = 0;
            }
            matrix[i * n + i] = 1;
            rhs[i] = 0;
            continue;
        }
        rank += 1;
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
    for (matrix) |value| if (!std.math.isFinite(value)) return null;
    for (rhs) |value| if (!std.math.isFinite(value)) return null;
    return rank;
}
// Use a power of two for each score axis so rescaling preserves its significand.
// Scaling before centering also keeps differences between opposite extremes finite.
fn scoreScale(scores: ?[]const f64) f64 {
    var largest: f64 = 0;
    for (scores orelse return 1) |score| largest = @max(largest, @abs(score));
    if (largest == 0) return 1;
    return std.math.ldexp(@as(f64, 1), std.math.frexp(largest).exponent - 1);
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
    // Both margins use the same reciprocal of the total frequency. Apply it
    // after summing counts so small rounding errors do not build up by level.
    const inverse_n = 1 / t.n;
    var cum: f64 = 0;
    for (t.row[0 .. m.rows - 1], 0..) |v, i| {
        cum += v;
        params[i] = fns.distQuantile(.normal, cum * inverse_n, &.{}).?;
    }
    cum = 0;
    for (t.col[0 .. m.cols - 1], 0..) |v, j| {
        cum += v;
        params[m.rows + j - 1] = fns.distQuantile(.normal, cum * inverse_n, &.{}).?;
    }
    params[dim - 1] = 0;
    const null_ll = negativeLogLikelihood(m, params);
    if (m.rows == 2 and m.cols == 2 and ((counts[1] == 0 and counts[2] == 0) or (counts[0] == 0 and counts[3] == 0))) {
        const r: f64 = if (counts[1] == 0) 1 else -1;
        return .{ .coefficient = measure(r, 0, 0, opts.alpha), .likelihood_ratio = null, .converged = true, .iterations = 0 };
    }
    const origin = opts.score_origin orelse [2]f64{
        if (m.row_scores) |scores| scores[0] else 0,
        if (m.col_scores) |scores| scores[0] else 0,
    };
    const x_scale = scoreScale(m.row_scores);
    const y_scale = scoreScale(m.col_scores);
    const x_origin = origin[0] / x_scale;
    const y_origin = origin[1] / y_scale;
    var sx: f64 = 0;
    var sy: f64 = 0;
    var xx: f64 = 0;
    var yy: f64 = 0;
    var xy: f64 = 0;
    for (m.counts, 0..) |n, index| {
        const x = (if (m.row_scores) |scores| scores[index / m.cols] else @as(f64, @floatFromInt(index / m.cols))) / x_scale - x_origin;
        const y = (if (m.col_scores) |scores| scores[index % m.cols] else @as(f64, @floatFromInt(index % m.cols))) / y_scale - y_origin;
        sx += n * x;
        sy += n * y;
        xx += n * x * x;
        yy += n * y * y;
        xy += n * x * y;
    }
    const x_sd = @sqrt(xx - sx * sx / t.n);
    const y_sd = @sqrt(yy - sy * sy / t.n);
    // CORR takes the reciprocal column deviation first. The two divisions
    // preserve the ordering observed in native VAR and WITH first-step fits.
    params[dim - 1] = (xy - sx * sy / t.n) * ((1 / y_sd) / x_sd);
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
    var occupied: usize = 0;
    for (m.counts, 0..) |n, i| {
        if (n == 0) continue;
        occupied += 1;
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
    const four_by_four_boundary = boundary and m.rows == 4 and m.cols == 4;
    const projected_boundary = boundary and (m.rows == 2 or m.cols == 2 or (m.rows == 3 and m.cols == 3) or four_by_four_boundary);
    // Rounding uncertainty in the two sums of occupied-cell log likelihoods.
    // Each term involves a logarithm and multiplication before summation.
    const ku = @as(f64, @floatFromInt(occupied + 2)) * std.math.floatEps(f64) / 2;
    const accumulated_roundoff = ku / (1 - ku);
    var boundary_distance: f64 = 0.001;
    var converged = false;
    var unresolved_projection = false;
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
            if (!std.math.isFinite(probability) or (probability <= 0 and n > 0))
                return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations };
            if (!(probability > 0)) continue;
            cellGradient(m, params, i, j, derivatives);
            // SAS's information denominator safeguard is distinct from the
            // actual likelihood probability. The bounded case-2 oracle also
            // discriminates this at finite, nonzero standard errors.
            const information_probability = @max(probability, 1e-12);
            for (0..dim) |r| {
                gradient[r] -= n * derivatives[r] / probability;
                for (0..dim) |c| hessian[r * dim + c] += t.n * derivatives[r] * derivatives[c] / information_probability;
            }
        }
        @memcpy(saved_information, hessian);
        if (solveInformation(hessian, gradient) == null) break;
        var scale: f64 = 1;
        var accepted = false;
        for (0..30) |_| {
            for (params, 0..) |p, i| candidate[i] = p - scale * gradient[i];
            // SAS first-step oracle: an overshoot is restarted at +/-0.999,
            // rather than halving all coordinates solely to force |rho|<1.
            // Successive overshoots on the supported boundaries refine this distance
            // by one decimal place (positive and negative M9 MAXITER traces).
            if (@abs(candidate[dim - 1]) >= 1) {
                // Once the likelihood is indistinguishable from its saturated
                // lower bound, the comparison cannot resolve another retraction.
                if (four_by_four_boundary and base - saturated <= accumulated_roundoff * (base + saturated))
                    unresolved_projection = true;
                const rho = std.math.copysign(1 - boundary_distance, candidate[dim - 1]);
                if (@abs(rho) == 1) return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations, .information_unresolved = true };
                candidate[dim - 1] = rho;
                if (projected_boundary) boundary_distance *= 0.1;
            }
            if (negativeLogLikelihood(m, candidate) <= base + 1e-10) {
                accepted = true;
                break;
            }
            scale /= 2;
        }
        if (!accepted) break;
        var change: f64 = 0;
        // SAS uses the updated estimate for both the relative denominator and
        // the near-zero decision. Fresh crossing controls pin both directions
        // across .01; equality retains relative scaling (stopping-fix evidence).
        for (params, candidate, gradient) |p, c, step| {
            // Projecting rho shortens its apparent move. M9 tests the
            // scoring increment before this projection on the supported boundaries.
            const delta = if (projected_boundary) scale * step else c - p;
            change = @max(change, @abs(delta) / (if (@abs(c) < 0.01) 1 else @abs(c)));
        }
        @memcpy(params, candidate);
        if (boundary and !projected_boundary and negativeLogLikelihood(m, params) - saturated <= t.n * 1e-10) {
            // The likelihood gap is below the quadrature error budget. A
            // validated rank decision alone does not establish the remaining
            // SAS boundary-step convention, so preserve this public guard.
            return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations, .information_unresolved = true };
        }
        if (change < opts.converge) {
            converged = true;
            break;
        }
    }
    // When the specified limit is reached before convergence, CORR reports
    // ordinary nonconvergence. An unresolved likelihood retraction prevents
    // publishing an estimate or diagnosing an earlier numerical failure.
    if (!converged or unresolved_projection) return .{
        .coefficient = .{},
        .likelihood_ratio = null,
        .converged = false,
        .iterations = iterations,
        .information_unresolved = unresolved_projection and (converged or iterations < opts.maxiter),
    };
    // SAS uses the information matrix from the final scoring linearization.
    // Re-evaluating at the updated rho materially changes sparse-boundary SEs.
    @memcpy(hessian, saved_information);
    @memset(gradient, 0);
    gradient[dim - 1] = 1;
    const variance = if (solveInformation(hessian, gradient) != null) gradient[dim - 1] else std.math.nan(f64);
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

test "CORR single-zero tetrachoric tables use the requested iteration limit" {
    const cases = [_]struct { counts: [4]f64, rho: f64, lr: f64, converges_by_20: bool }{
        .{ .counts = .{ 0, 5, 5, 10 }, .rho = -0.98265, .lr = 3.3980, .converges_by_20 = false },
        .{ .counts = .{ 5, 0, 10, 5 }, .rho = 0.98265, .lr = 3.3980, .converges_by_20 = false },
        .{ .counts = .{ 0, 4, 8, 12 }, .rho = -0.98187, .lr = 3.6322, .converges_by_20 = false },
        .{ .counts = .{ 0, 9, 11, 3 }, .rho = -0.99900, .lr = 17.2930, .converges_by_20 = true },
    };
    for (cases) |c| {
        const matrix: CountMatrix = .{ .rows = 2, .cols = 2, .counts = &c.counts };
        for ([_]usize{ 20, 200 }) |maxiter| {
            const result = try polychoric(std.testing.allocator, matrix, .{ .converge = 0.0001, .maxiter = maxiter });
            try std.testing.expectEqual(maxiter == 200 or c.converges_by_20, result.converged);
            if (!result.converged) {
                try std.testing.expectEqual(maxiter, result.iterations);
                try std.testing.expect(result.coefficient.estimate == null);
                continue;
            }
            try std.testing.expectApproxEqAbs(c.rho, result.coefficient.estimate.?, 0.000005);
            try std.testing.expectEqual(@as(f64, 0), result.coefficient.ase.?);
            try std.testing.expectApproxEqAbs(c.lr, result.likelihood_ratio.?.statistic, 0.00005);
        }
    }
}

test "CORR four-level ordinal boundaries with a distinguishable projected step" {
    const cases = [_]struct { counts: [16]f64, lr: f64 }{
        .{ .counts = .{ 35, 0, 0, 0, 17, 30, 0, 0, 0, 21, 9, 0, 0, 0, 16, 7 }, .lr = 197.83030675715 },
        .{ .counts = .{ 2240, 0, 0, 0, 1344, 0, 0, 0, 3008, 0, 0, 0, 960, 2176, 1792, 832 }, .lr = 11314.7268426884 },
    };
    for (cases) |c| {
        const m: CountMatrix = .{ .rows = 4, .cols = 4, .counts = &c.counts, .row_scores = &.{ -9, 0, 11, 31 }, .col_scores = &.{ -17, -4, 8, 13 } };
        const early = try polychoric(std.testing.allocator, m, .{ .converge = 1e-6, .maxiter = 20 });
        try std.testing.expect(!early.converged and !early.information_unresolved);
        const fit = try polychoric(std.testing.allocator, m, .{ .converge = 1e-6 });
        try std.testing.expect(fit.converged);
        try std.testing.expectApproxEqAbs(@as(f64, 0.9999), fit.coefficient.estimate.?, 1e-12);
        try std.testing.expectEqual(@as(f64, 0), fit.coefficient.ase.?);
        try std.testing.expectApproxEqAbs(c.lr, fit.likelihood_ratio.?.statistic, 1e-7);
    }
}

test "CORR normalizes cumulative polychoric margins using a shared reciprocal" {
    // On these independent tables, SAS 9.4 M9's first-step SE changes in
    // opposite directions after removing the theoretical 1/sqrt(FREQ) factor.
    const cases = [_]struct { counts: [4]f64, scale: f64, native_se: [2]f64 }{
        .{ .counts = .{ 3250, 350, 1820, 196 }, .scale = 43, .native_se = .{ 0.029514289368863387, 0.0045008869331344585 } },
        .{ .counts = .{ 10260, 972, 7695, 729 }, .scale = 5, .native_se = .{ 0.016030816097741426, 0.007169198905869558 } },
    };
    for (cases) |case| {
        var normalized: [2]f64 = undefined;
        for ([_]f64{ 1, case.scale }, 0..) |scale, i| {
            var counts = case.counts;
            for (&counts) |*n| n.* *= scale;
            const fit = try polychoric(std.testing.allocator, .{ .rows = 2, .cols = 2, .counts = &counts }, .{ .converge = 0.99, .maxiter = 1 });
            try std.testing.expect(fit.converged);
            const se = fit.coefficient.ase.?;
            try std.testing.expectApproxEqAbs(case.native_se[i], se, 5e-17);
            normalized[i] = se * @sqrt(scale);
        }
        const expected = std.math.order(case.native_se[0], case.native_se[1] * @sqrt(case.scale));
        try std.testing.expectEqual(expected, std.math.order(normalized[0], normalized[1]));
    }
}

test "CORR binary-margin polychoric boundary uses the native information rank at both frequency scales" {
    const xs = [_]f64{ 0, 10, 20 };
    const ys = [_]f64{ 0, 1 };
    // Same ordinal margins and association. Only the information scale changes.
    for ([_]f64{ 11, 12 }, [_]f64{ 0.98771303566856, 0.999 }, [_]f64{ 183.527618505065, 200.211947460075 }, [_]f64{ 8.2269409306717e-42, 1.8775016946271e-45 }) |scale, rho, lr, p| {
        var counts = [_]f64{ 10, 32, 0, 38, 0, 10 };
        for (&counts) |*n| n.* *= scale;
        const matrix: CountMatrix = .{ .rows = 3, .cols = 2, .counts = &counts, .row_scores = &xs, .col_scores = &ys };
        const result = try polychoric(std.testing.allocator, matrix, .{ .converge = 1e-6 });
        try std.testing.expect(result.converged);
        try std.testing.expectApproxEqAbs(rho, result.coefficient.estimate.?, 5e-8);
        try std.testing.expectEqual(@as(f64, 0), result.coefficient.ase.?);
        try std.testing.expectApproxEqAbs(lr, result.likelihood_ratio.?.statistic, 1e-7);
        try std.testing.expectApproxEqRel(p, result.likelihood_ratio.?.p, 1e-7);
    }
}

test "CORR binary-margin nested thresholds retain finite SE and stop on the unprojected increment" {
    const cases = [_]struct { matrix: CountMatrix, rho: f64, se: f64, lr: f64 }{
        .{ .matrix = .{ .rows = 2, .cols = 3, .counts = &.{ 7, 11, 0, 0, 0, 17 }, .row_scores = &.{ 0, 1 }, .col_scores = &.{ 0, 1, 3 } }, .rho = 0.99999999, .se = 2.8341430859619e-6, .lr = 48.488578142682 },
        .{ .matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 0, 9, 0, 13, 21, 0 }, .row_scores = &.{ 0, 2, 7 }, .col_scores = &.{ -1, 0 } }, .rho = -0.99999999, .se = 2.5566692489271e-6, .lr = 59.5835297853088 },
    };
    for (cases) |c| {
        const early = try polychoric(std.testing.allocator, c.matrix, .{ .converge = 3.7e-7, .maxiter = 5 });
        try std.testing.expect(!early.converged);
        const result = try polychoric(std.testing.allocator, c.matrix, .{ .converge = 3.7e-7, .maxiter = 6 });
        try std.testing.expect(result.converged);
        try std.testing.expectEqual(@as(usize, 6), result.iterations);
        try std.testing.expectApproxEqAbs(c.rho, result.coefficient.estimate.?, 1e-12);
        try std.testing.expectApproxEqRel(c.se, result.coefficient.ase.?, 1e-4);
        try std.testing.expectApproxEqAbs(c.lr, result.likelihood_ratio.?.statistic, 1e-7);
    }
}

test "CORR stopping normalization uses updated estimates across the near-zero threshold" {
    // Invented fresh controls and SAS 9.4M9 results: stopping-fix/native.txt.
    // The first two cross from abs(old)<.01 to abs(new)>.01; the other two
    // cross back below .01. Positive and negative coordinates are covered.
    const Case = struct {
        counts: []const f64,
        xs: []const f64,
        ys: []const f64,
        converge: f64,
        iterations: usize,
        rho: f64,
        se: f64,
        lr: f64,
    };
    const cases = [_]Case{
        .{ .counts = &.{ 55, 102, 193, 41, 61, 8, 71, 97, 67 }, .xs = &.{ 0, 7, 9 }, .ys = &.{ -5, 3, 5 }, .converge = 0.4748404097390406, .iterations = 2, .rho = -0.3505292843734581, .se = 0.0452902589640991, .lr = 50.75449895064003 },
        .{ .counts = &.{ 218, 55, 310, 136, 222, 214 }, .xs = &.{ -3, 3 }, .ys = &.{ -6, 2, 9 }, .converge = 0.49718716894559606, .iterations = 2, .rho = -0.030698731836646755, .se = 0.04236659486667584, .lr = 0.5260991117779668 },
        .{ .counts = &.{ 88, 190, 282, 214, 329, 30 }, .xs = &.{ -6, -5 }, .ys = &.{ -7, 0, 5 }, .converge = 0.3745590095305732, .iterations = 1, .rho = -0.6115755673158315, .se = 0.03575778491086687, .lr = 250.292951417337 },
        .{ .counts = &.{ 79, 214, 218, 292, 134, 75 }, .xs = &.{ -4, 4 }, .ys = &.{ -5, 3, 11 }, .converge = 0.30662452789839933, .iterations = 1, .rho = -0.5913893044649507, .se = 0.03778653417969465, .lr = 205.38319212380748 },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const matrix: CountMatrix = .{ .rows = c.xs.len, .cols = c.ys.len, .counts = c.counts, .row_scores = c.xs, .col_scores = c.ys };
        const first = try polychoric(arena.allocator(), matrix, .{ .converge = c.converge, .maxiter = 1 });
        try std.testing.expectEqual(c.iterations == 1, first.converged);
        const result = try polychoric(arena.allocator(), matrix, .{ .converge = c.converge });
        try std.testing.expect(result.converged);
        try std.testing.expectEqual(c.iterations, result.iterations);
        try std.testing.expectApproxEqAbs(c.rho, result.coefficient.estimate.?, 5e-8);
        try std.testing.expectApproxEqAbs(c.se, result.coefficient.ase.?, 5e-6);
        try std.testing.expectApproxEqRel(c.se, result.coefficient.ase.?, 1e-4);
        try std.testing.expectApproxEqAbs(c.lr, result.likelihood_ratio.?.statistic, 1e-7 + 2e-9 * sum(c.counts));
    }
}
