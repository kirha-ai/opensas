//! UNIVARIATE inference kernels. No parsing or rendering (D-029).
//! SAS 9.4 Statistical Procedures pp.414–421,444–447.
const std = @import("std");
const f = @import("../functions.zig");
const Value = @import("../value.zig").Value;
const normality = @import("normality.zig");
const nan = std.math.nan(f64);
pub const Side = enum { twosided, lower, upper, symmetric, asymmetric };
pub const CI = struct {
    alpha: ?f64 = null,
    side: Side = .twosided,
    pub fn tail(self: CI, alpha: f64) f64 {
        return (self.alpha orelse alpha) / (if (self.side == .lower or self.side == .upper) @as(f64, 1) else 2);
    }
};
pub const Interval = struct { lower: f64 = nan, upper: f64 = nan, lower_rank: usize = 0, upper_rank: usize = 0, coverage: f64 = nan };
fn parameter(x: f64) Value {
    return .{ .num = x };
}
pub fn tQuantile(p: f64, df: f64) f64 {
    // The shared generic quantile uses a fixed +/-1e6 bracket, insufficient
    // for small alpha with one degree of freedom. Reuse its CDF with an
    // expanding bracket and invert the small tail directly.
    if (p > 0.5) return -tQuantile(1 - p, df);
    if (p == 0.5) return 0;
    var lo: f64 = -1;
    var hi: f64 = 0;
    while (f.distCdf(.t, lo, &.{ parameter(0), parameter(0), parameter(df) }).? > p and lo > -1e150) lo *= 2;
    for (0..100) |_| {
        const mid = lo + (hi - lo) / 2;
        if (f.distCdf(.t, mid, &.{ parameter(0), parameter(0), parameter(df) }).? < p) lo = mid else hi = mid;
    }
    return lo + (hi - lo) / 2;
}
pub fn tProbability(t: f64, df: f64) f64 {
    // Evaluate the small tail directly, avoiding cancellation for extreme t.
    return 2 * (f.distCdf(.t, -@abs(t), &.{ parameter(0), parameter(0), parameter(df) }) orelse nan);
}
pub fn meanCI(mean: f64, se: f64, df: f64, ci: CI, alpha: f64) Interval {
    if (!(df > 0) or !std.math.isFinite(se)) return .{};
    const margin = -tQuantile(ci.tail(alpha), df) * se;
    return .{ .lower = if (ci.side == .upper) nan else mean - margin, .upper = if (ci.side == .lower) nan else mean + margin };
}
pub fn varianceCI(css: f64, df: f64, ci: CI, alpha: f64) Interval {
    if (!(df > 0)) return .{};
    const tail = ci.tail(alpha);
    return .{ .lower = if (ci.side == .upper) nan else css / f.distQuantile(.chisq, 1 - tail, &.{ parameter(0), parameter(0), parameter(df) }).?, .upper = if (ci.side == .lower) nan else css / f.distQuantile(.chisq, tail, &.{ parameter(0), parameter(0), parameter(df) }).? };
}
pub const Trim = struct { k: usize, mean: f64, se: f64 = nan, df: f64, t: f64 = nan, p: f64 = nan, limits: Interval = .{} };
pub fn trimmed(x: []const f64, amount: f64, winsor: bool, mu0: f64, inference: bool, ci: CI, alpha: f64) ?Trim {
    const n: f64 = @floatFromInt(x.len);
    const count = if (amount < 1) @ceil(n * amount) else @floor(amount);
    if (count < 0 or count * 2 >= n) return null;
    const k: usize = @intFromFloat(count);
    const retained = n - 2 * count;
    var sum: f64 = 0;
    for (x[k .. x.len - k]) |v| sum += v;
    const wm = (sum + count * (x[k] + x[x.len - k - 1])) / n;
    var css: f64 = 0;
    for (x, 0..) |_, i| {
        const v = x[@min(@max(i, k), x.len - k - 1)] - wm;
        css += v * v;
    }
    var r: Trim = .{ .k = k, .mean = if (winsor) wm else sum / retained, .df = retained - 1 };
    if (inference and r.df > 0) {
        r.se = if (winsor) @sqrt(css / (n * (n - 1))) * (n - 1) / r.df else @sqrt(css / (retained * r.df));
        r.limits = meanCI(r.mean, r.se, r.df, ci, alpha);
        if (r.se > 0) {
            r.t = (r.mean - mu0) / r.se;
            r.p = tProbability(r.t, r.df);
        }
    }
    return r;
}
fn binomial(k: usize, n: usize, p: f64) f64 {
    return f.distCdf(.binomial, @floatFromInt(k), &.{ parameter(0), parameter(0), parameter(p), parameter(@floatFromInt(n)) }).?;
}
/// Central order-statistic intervals, retaining the best attainable symmetric
/// interval when nominal coverage is unavailable (SAS listing reports coverage).
pub fn distributionFree(x: []const f64, p: f64, ci: CI, alpha: f64) Interval {
    const n = x.len;
    if (n == 0 or p <= 0 or p >= 1) return .{};
    const target = 1 - (ci.alpha orelse alpha);
    if (ci.side == .lower) {
        var l: usize = 1;
        for (1..n + 1) |j| {
            if (1 - binomial(j - 1, n, p) >= target) l = j else break;
        }
        return if (l == 0) .{} else .{ .lower = x[l - 1], .lower_rank = l, .coverage = 1 - binomial(l - 1, n, p) };
    }
    if (ci.side == .upper) {
        for (1..n + 1) |u| {
            const c = binomial(u - 1, n, p);
            if (c >= target) return .{ .upper = x[u - 1], .upper_rank = u, .coverage = c };
        }
        return .{ .upper = x[n - 1], .upper_rank = n, .coverage = binomial(n - 1, n, p) };
    }
    // SAS centers the binomial rank search at round(n*p), tests the
    // nearly symmetric interval before the symmetric one, and reflects the
    // upper half. intervals.sas pins even/odd n and attainable coverage.
    if (p > 0.5) {
        const reflected = distributionFree(x, 1 - p, ci, alpha);
        if (reflected.lower_rank == 0) return .{};
        const l = n + 1 - reflected.upper_rank;
        const u = n + 1 - reflected.lower_rank;
        return .{ .lower = x[l - 1], .upper = x[u - 1], .lower_rank = l, .upper_rank = u, .coverage = reflected.coverage };
    }
    const center: usize = if (n == 2 and p >= 0.25) 2 else @intFromFloat(@ceil(@as(f64, @floatFromInt(n)) * p + 0.5 - 1e-13));
    var r: Interval = .{};
    var radius: usize = 1;
    while (radius < center) : (radius += 1) {
        const l = center - radius;
        for ([_]usize{ center + radius - 1, center + radius }) |u| {
            if (u > n) continue;
            const c = binomial(u - 1, n, p) - binomial(l - 1, n, p);
            r = .{ .lower = x[l - 1], .upper = x[u - 1], .lower_rank = l, .upper_rank = u, .coverage = c };
            if (l > 1 and p < 0.5 and u == center + radius) {
                const shifted = binomial(u - 2, n, p) - binomial(l - 2, n, p);
                if (shifted >= target and (c < target or shifted < c - 1e-13)) return .{ .lower = x[l - 2], .upper = x[u - 2], .lower_rank = l - 1, .upper_rank = u - 1, .coverage = shifted };
            }
            if (c >= target) {
                if (p == 0.5 and n % 2 == 1 and u == center + radius - 1 and u < n) return .{ .lower = x[l], .upper = x[u], .lower_rank = l + 1, .upper_rank = u + 1, .coverage = c };
                return r;
            }
        }
    }
    // When nominal coverage cannot be attained, retain the widest nearly
    // symmetric interval. Half-integer np permits an extra upper rank.
    const fallback: usize = @min(n, @as(usize, @intFromFloat(@floor(2 * @as(f64, @floatFromInt(n)) * p + 1 + 1e-12))));
    if (fallback >= 2 and fallback > r.upper_rank) r = .{ .lower = x[0], .upper = x[fallback - 1], .lower_rank = 1, .upper_rank = fallback, .coverage = binomial(fallback - 1, n, p) - binomial(0, n, p) };
    if (ci.side == .asymmetric) {
        var u = @max(r.upper_rank, 2);
        while (u <= n) : (u += 1) {
            const c = binomial(u - 1, n, p) - binomial(0, n, p);
            r = .{ .lower = x[0], .upper = x[u - 1], .lower_rank = 1, .upper_rank = u, .coverage = c };
            if (c >= target) return r;
        }
    }
    return r;
}
/// Invert the existing noncentral-t CDF; quantile inference uses delta=z_p*sqrt(n).
pub fn noncentralQuantile(p: f64, df: f64, delta: f64) f64 {
    if (delta == 0) return tQuantile(p, df);
    if (delta < 0) return -noncentralQuantile(1 - p, df, -delta);
    var lo: f64 = -1;
    var hi: f64 = 1;
    while (noncentralCDF(lo, df, delta) > p and lo > -1e100) lo *= 2;
    while (noncentralCDF(hi, df, delta) < p and hi < 1e100) hi *= 2;
    for (0..100) |_| {
        const mid = lo + (hi - lo) / 2;
        if (noncentralCDF(mid, df, delta) < p) lo = mid else hi = mid;
    }
    return lo + (hi - lo) / 2;
}
// AS243's finite Poisson series cannot cover large noncentralities. Integrate
// the normal conditional probability over a chi variate in that regime.
const ChiIntegral = struct {
    t: f64,
    df: f64,
    delta: f64,
    logc: f64,
    fn at(self: ChiIntegral, y: f64) f64 {
        if (y <= 0) return 0;
        const density = @exp(self.logc + (self.df - 1) * @log(y) - y * y / 2);
        return density * f.distCdf(.normal, self.t * y / @sqrt(self.df) - self.delta, &.{}).?;
    }
    fn integrate(self: ChiIntegral, l: f64, r: f64, fl: f64, fm: f64, fr: f64, whole: f64, tol: f64, depth: usize) f64 {
        const m = (l + r) / 2;
        const a = self.at((l + m) / 2);
        const b = self.at((m + r) / 2);
        const left = (m - l) * (fl + 4 * a + fm) / 6;
        const right = (r - m) * (fm + 4 * b + fr) / 6;
        const diff = left + right - whole;
        if (depth == 0 or @abs(diff) <= 15 * tol) return left + right + diff / 15;
        return self.integrate(l, m, fl, a, fm, left, tol / 2, depth - 1) + self.integrate(m, r, fm, b, fr, right, tol / 2, depth - 1);
    }
};
fn noncentralCDF(t: f64, df: f64, delta: f64) f64 {
    if (delta < 12) return f.noncentralTCdf(t, df, delta);
    const integral: ChiIntegral = .{ .t = t, .df = df, .delta = delta, .logc = (1 - df / 2) * @log(@as(f64, 2)) - f.lgammaOf(df / 2) };
    const lo = @max(0, @sqrt(df) - 12);
    const hi = @sqrt(df) + 12;
    var sum: f64 = 0;
    for (0..32) |i| {
        const l = lo + (hi - lo) * @as(f64, @floatFromInt(i)) / 32;
        const r = lo + (hi - lo) * @as(f64, @floatFromInt(i + 1)) / 32;
        const fl = integral.at(l);
        const fm = integral.at((l + r) / 2);
        const fr = integral.at(r);
        sum += integral.integrate(l, r, fl, fm, fr, (r - l) * (fl + 4 * fm + fr) / 6, 1e-12 / 32.0, 20);
    }
    return std.math.clamp(sum, 0, 1);
}
pub fn normalQuantileCI(mean: f64, sd: f64, n: usize, p: f64, ci: CI, alpha: f64) Interval {
    if (n < 2 or p < 0 or p > 1) return .{};
    const nf: f64 = @floatFromInt(n);
    const z = if (p == 0) @as(f64, -7.94134532617099) else if (p == 1) @as(f64, 7.94134532617099) else f.distQuantile(.normal, p, &.{}).?;
    const delta = z * @sqrt(nf);
    const tail = ci.tail(alpha);
    return .{ .lower = if (ci.side == .upper) nan else mean + sd / @sqrt(nf) * noncentralQuantile(tail, nf - 1, delta), .upper = if (ci.side == .lower) nan else mean + sd / @sqrt(nf) * noncentralQuantile(1 - tail, nf - 1, delta) };
}
pub const NormalTests = struct { primary: normality.Result, d: f64, pd: f64, w2: f64, pw2: f64, a2: f64, pa2: f64 };
fn tableProbability(x: f64, critical: []const f64, probabilities: []const f64) f64 {
    if (x <= critical[0]) return probabilities[0];
    for (1..critical.len) |i| if (x <= critical[i]) return probabilities[i - 1] + (x - critical[i - 1]) / (critical[i] - critical[i - 1]) * (probabilities[i] - probabilities[i - 1]);
    return probabilities[probabilities.len - 1];
}
fn logNormalTail(z: f64) f64 {
    const p = f.distCdf(.normal, -z, &.{}).?;
    if (p > 0) return @log(p);
    // Mills expansion only after the shared CDF underflows; avoids log(0).
    const inv = 1 / (z * z);
    return -z * z / 2 - @log(z) - 0.5 * @log(2 * std.math.pi) + @log(1 - inv + 3 * inv * inv - 15 * inv * inv * inv);
}
pub fn normalTests(a: std.mem.Allocator, x: []const f64) !?NormalTests {
    const primary = (try normality.compute(a, x)) orelse return null;
    const n: f64 = @floatFromInt(x.len);
    const center = x[0] / 2 + x[x.len - 1] / 2;
    const radius = @max(@abs(x[0] - center), @abs(x[x.len - 1] - center));
    var mean: f64 = 0;
    for (x) |v| mean += (v - center) / radius / n;
    var css: f64 = 0;
    for (x) |v| {
        const d = (v - center) / radius - mean;
        css += d * d;
    }
    const sd = @sqrt(css / (n - 1));
    var d: f64 = 0;
    var w: f64 = 1 / (12 * n);
    var ad: f64 = 0;
    for (x, 0..) |v, i| {
        const z = ((v - center) / radius - mean) / sd;
        const u = f.distCdf(.normal, z, &.{}).?;
        const j: f64 = @floatFromInt(i);
        d = @max(d, @max(u - j / n, (j + 1) / n - u));
        const diff = u - (j + 0.5) / n;
        w += diff * diff;
        ad += (2 * j + 1) * logNormalTail(-z) + (2 * n - 2 * j - 1) * logNormalTail(z);
    }
    ad = -n - ad / n;
    return .{ .primary = primary, .d = d, .pd = tableProbability(d * (@sqrt(n) - 0.01 + 0.85 / @sqrt(n)), &.{ 0.775, 0.819, 0.895, 0.955, 1.035 }, &.{ 0.15, 0.10, 0.05, 0.025, 0.01 }), .w2 = w, .pw2 = tableProbability(w * (1 + 0.5 / n), &.{ 0.074, 0.091, 0.104, 0.126, 0.148, 0.178, 0.208 }, &.{ 0.25, 0.15, 0.1, 0.05, 0.025, 0.01, 0.005 }), .a2 = ad, .pa2 = tableProbability(ad * (1 + 0.75 / n + 2.25 / (n * n)), &.{ 0.470, 0.561, 0.631, 0.752, 0.873, 1.035, 1.159 }, &.{ 0.25, 0.15, 0.1, 0.05, 0.025, 0.01, 0.005 }) };
}

test "UNIVARIATE inference SAS core and EDF oracles" {
    // sasrun /tmp/opensas-stat-batch2/FEAT-univ-inference/core.sas -f text
    // Manual pp.417–419; SAS: trim 0.25 SE=1.080123, winsor SE=1.166667.
    const x = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const tr = trimmed(&x, 0.25, false, 0, true, .{}, 0.05).?;
    try std.testing.expectApproxEqAbs(@as(f64, 4.5), tr.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 14) / 12), tr.se, 1e-12);
    const wi = trimmed(&x, 0.25, true, 0, true, .{}, 0.05).?;
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 6.0), wi.se, 1e-12);
    const median = distributionFree(&x, 0.5, .{}, 0.05);
    try std.testing.expectEqual(@as(usize, 2), median.lower_rank);
    try std.testing.expectEqual(@as(usize, 8), median.upper_rank);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9609375), median.coverage, 1e-12);
    const nq = normalQuantileCI(4.5, @sqrt(@as(f64, 6)), 8, 0.99, .{}, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 7.84118), nq.lower, 5e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 16.63560), nq.upper, 5e-6);
    const nt = (try normalTests(std.testing.allocator, &x)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.97485827830837), nt.primary.statistic, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.104854), nt.d, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.017355), nt.w2, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.134), nt.a2, 5e-7);
    // edf.sas: normal score grids, with x=z+shape*(z*z-1).
    for ([_]usize{ 2, 3, 8, 8, 20, 50 }, [_]f64{ 0, 1, 0.5, 1, 0.3, 0.2 }, [_]f64{ 0.233176190161, 0.09660623452543, 0.10861366046061, 0.04287393893427, 0.08222057618134, 0.04546966928938 }, [_]f64{ 0.25, 0.15059332506245, 0.13915996788521, 0.05888051915315, 0.10951142833537, 0.07102042411743 }) |n, shape, pa, pw| {
        const vals = try std.testing.allocator.alloc(f64, n);
        defer std.testing.allocator.free(vals);
        for (vals, 0..) |*v, i| {
            const z = f.distQuantile(.normal, (@as(f64, @floatFromInt(i + 1)) - 0.375) / (@as(f64, @floatFromInt(n)) + 0.25), &.{}).?;
            v.* = z + shape * (z * z - 1);
        }
        std.mem.sort(f64, vals, {}, std.sort.asc(f64));
        const got = (try normalTests(std.testing.allocator, vals)).?;
        try std.testing.expectApproxEqAbs(pa, got.pa2, 1e-8);
        try std.testing.expectApproxEqAbs(pw, got.pw2, 1e-8);
    }
}

test "UNIVARIATE distribution-free SAS rank grid all sides" {
    // intervals.sas: alpha=.1; n=2,3,8,9,20,100; ranks equal x.
    const Case = struct { n: usize, p: f64, side: Side, l: usize, u: usize, alpha: f64 = 0.1 };
    const cases = [_]Case{
        .{ .n = 2, .p = 0.01, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 2, .p = 0.05, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 2, .p = 0.1, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 2, .p = 0.25, .side = .symmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.33, .side = .symmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.5, .side = .symmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.75, .side = .symmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.9, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 2, .p = 0.95, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 2, .p = 0.99, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.01, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.05, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.1, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.25, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.33, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.5, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.75, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.9, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.95, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 3, .p = 0.99, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 8, .p = 0.01, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 8, .p = 0.05, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 8, .p = 0.1, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 8, .p = 0.25, .side = .symmetric, .l = 1, .u = 5 },
        .{ .n = 8, .p = 0.33, .side = .symmetric, .l = 1, .u = 6 },
        .{ .n = 8, .p = 0.5, .side = .symmetric, .l = 2, .u = 7 },
        .{ .n = 8, .p = 0.75, .side = .symmetric, .l = 4, .u = 8 },
        .{ .n = 8, .p = 0.9, .side = .symmetric, .l = 6, .u = 8 },
        .{ .n = 8, .p = 0.95, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 8, .p = 0.99, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 9, .p = 0.01, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 9, .p = 0.05, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 9, .p = 0.1, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 9, .p = 0.25, .side = .symmetric, .l = 1, .u = 5 },
        .{ .n = 9, .p = 0.33, .side = .symmetric, .l = 1, .u = 6 },
        .{ .n = 9, .p = 0.5, .side = .symmetric, .l = 2, .u = 8 },
        .{ .n = 9, .p = 0.75, .side = .symmetric, .l = 5, .u = 9 },
        .{ .n = 9, .p = 0.9, .side = .symmetric, .l = 7, .u = 9 },
        .{ .n = 9, .p = 0.95, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 9, .p = 0.99, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 20, .p = 0.01, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 20, .p = 0.05, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 20, .p = 0.1, .side = .symmetric, .l = 1, .u = 5 },
        .{ .n = 20, .p = 0.25, .side = .symmetric, .l = 2, .u = 9 },
        .{ .n = 20, .p = 0.33, .side = .symmetric, .l = 4, .u = 11 },
        .{ .n = 20, .p = 0.5, .side = .symmetric, .l = 7, .u = 15 },
        .{ .n = 20, .p = 0.75, .side = .symmetric, .l = 12, .u = 19 },
        .{ .n = 20, .p = 0.9, .side = .symmetric, .l = 16, .u = 20 },
        .{ .n = 20, .p = 0.95, .side = .symmetric, .l = 18, .u = 20 },
        .{ .n = 20, .p = 0.99, .side = .symmetric, .l = 0, .u = 0 },
        .{ .n = 100, .p = 0.01, .side = .symmetric, .l = 1, .u = 3 },
        .{ .n = 100, .p = 0.05, .side = .symmetric, .l = 1, .u = 9 },
        .{ .n = 100, .p = 0.1, .side = .symmetric, .l = 6, .u = 16 },
        .{ .n = 100, .p = 0.25, .side = .symmetric, .l = 18, .u = 33 },
        .{ .n = 100, .p = 0.33, .side = .symmetric, .l = 26, .u = 42 },
        .{ .n = 100, .p = 0.5, .side = .symmetric, .l = 42, .u = 59 },
        .{ .n = 100, .p = 0.75, .side = .symmetric, .l = 68, .u = 83 },
        .{ .n = 100, .p = 0.9, .side = .symmetric, .l = 85, .u = 95 },
        .{ .n = 100, .p = 0.95, .side = .symmetric, .l = 92, .u = 100 },
        .{ .n = 100, .p = 0.99, .side = .symmetric, .l = 98, .u = 100 },
        .{ .n = 2, .p = 0.01, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.05, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.1, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.25, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.33, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.5, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.75, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.9, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.95, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 2, .p = 0.99, .side = .asymmetric, .l = 1, .u = 2 },
        .{ .n = 3, .p = 0.01, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.05, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.1, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.25, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.33, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.5, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.75, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.9, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.95, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 3, .p = 0.99, .side = .asymmetric, .l = 1, .u = 3 },
        .{ .n = 8, .p = 0.01, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.05, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.1, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.25, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.33, .side = .asymmetric, .l = 1, .u = 6 },
        .{ .n = 8, .p = 0.5, .side = .asymmetric, .l = 2, .u = 7 },
        .{ .n = 8, .p = 0.75, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.9, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.95, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 8, .p = 0.99, .side = .asymmetric, .l = 1, .u = 8 },
        .{ .n = 9, .p = 0.01, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 9, .p = 0.05, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 9, .p = 0.1, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 9, .p = 0.25, .side = .asymmetric, .l = 1, .u = 6 },
        .{ .n = 9, .p = 0.33, .side = .asymmetric, .l = 1, .u = 6 },
        .{ .n = 9, .p = 0.5, .side = .asymmetric, .l = 2, .u = 8 },
        .{ .n = 9, .p = 0.75, .side = .asymmetric, .l = 4, .u = 9 },
        .{ .n = 9, .p = 0.9, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 9, .p = 0.95, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 9, .p = 0.99, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 20, .p = 0.01, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 20, .p = 0.05, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 20, .p = 0.1, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 20, .p = 0.25, .side = .asymmetric, .l = 2, .u = 9 },
        .{ .n = 20, .p = 0.33, .side = .asymmetric, .l = 4, .u = 11 },
        .{ .n = 20, .p = 0.5, .side = .asymmetric, .l = 7, .u = 15 },
        .{ .n = 20, .p = 0.75, .side = .asymmetric, .l = 12, .u = 19 },
        .{ .n = 20, .p = 0.9, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 20, .p = 0.95, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 20, .p = 0.99, .side = .asymmetric, .l = 1, .u = 20 },
        .{ .n = 100, .p = 0.01, .side = .asymmetric, .l = 1, .u = 100 },
        .{ .n = 100, .p = 0.05, .side = .asymmetric, .l = 1, .u = 9 },
        .{ .n = 100, .p = 0.1, .side = .asymmetric, .l = 6, .u = 16 },
        .{ .n = 100, .p = 0.25, .side = .asymmetric, .l = 18, .u = 33 },
        .{ .n = 100, .p = 0.33, .side = .asymmetric, .l = 26, .u = 42 },
        .{ .n = 100, .p = 0.5, .side = .asymmetric, .l = 42, .u = 59 },
        .{ .n = 100, .p = 0.75, .side = .asymmetric, .l = 68, .u = 83 },
        .{ .n = 100, .p = 0.9, .side = .asymmetric, .l = 85, .u = 95 },
        .{ .n = 100, .p = 0.95, .side = .asymmetric, .l = 92, .u = 100 },
        .{ .n = 100, .p = 0.99, .side = .asymmetric, .l = 1, .u = 100 },
        .{ .n = 2, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.05, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.1, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.25, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.33, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.5, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.75, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.9, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 2, .p = 0.95, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 2, .p = 0.99, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 3, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.05, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.1, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.25, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.33, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.5, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.75, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 3, .p = 0.9, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 3, .p = 0.95, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 3, .p = 0.99, .side = .lower, .l = 3, .u = 0 },
        .{ .n = 8, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 8, .p = 0.05, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 8, .p = 0.1, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 8, .p = 0.25, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 8, .p = 0.33, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 8, .p = 0.5, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 8, .p = 0.75, .side = .lower, .l = 4, .u = 0 },
        .{ .n = 8, .p = 0.9, .side = .lower, .l = 6, .u = 0 },
        .{ .n = 8, .p = 0.95, .side = .lower, .l = 7, .u = 0 },
        .{ .n = 8, .p = 0.99, .side = .lower, .l = 8, .u = 0 },
        .{ .n = 9, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 9, .p = 0.05, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 9, .p = 0.1, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 9, .p = 0.25, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 9, .p = 0.33, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 9, .p = 0.5, .side = .lower, .l = 3, .u = 0 },
        .{ .n = 9, .p = 0.75, .side = .lower, .l = 5, .u = 0 },
        .{ .n = 9, .p = 0.9, .side = .lower, .l = 7, .u = 0 },
        .{ .n = 9, .p = 0.95, .side = .lower, .l = 8, .u = 0 },
        .{ .n = 9, .p = 0.99, .side = .lower, .l = 9, .u = 0 },
        .{ .n = 20, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 20, .p = 0.05, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 20, .p = 0.1, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 20, .p = 0.25, .side = .lower, .l = 3, .u = 0 },
        .{ .n = 20, .p = 0.33, .side = .lower, .l = 4, .u = 0 },
        .{ .n = 20, .p = 0.5, .side = .lower, .l = 7, .u = 0 },
        .{ .n = 20, .p = 0.75, .side = .lower, .l = 12, .u = 0 },
        .{ .n = 20, .p = 0.9, .side = .lower, .l = 16, .u = 0 },
        .{ .n = 20, .p = 0.95, .side = .lower, .l = 18, .u = 0 },
        .{ .n = 20, .p = 0.99, .side = .lower, .l = 19, .u = 0 },
        .{ .n = 100, .p = 0.01, .side = .lower, .l = 1, .u = 0 },
        .{ .n = 100, .p = 0.05, .side = .lower, .l = 2, .u = 0 },
        .{ .n = 100, .p = 0.1, .side = .lower, .l = 6, .u = 0 },
        .{ .n = 100, .p = 0.25, .side = .lower, .l = 20, .u = 0 },
        .{ .n = 100, .p = 0.33, .side = .lower, .l = 27, .u = 0 },
        .{ .n = 100, .p = 0.5, .side = .lower, .l = 44, .u = 0 },
        .{ .n = 100, .p = 0.75, .side = .lower, .l = 69, .u = 0 },
        .{ .n = 100, .p = 0.9, .side = .lower, .l = 86, .u = 0 },
        .{ .n = 100, .p = 0.95, .side = .lower, .l = 92, .u = 0 },
        .{ .n = 100, .p = 0.99, .side = .lower, .l = 98, .u = 0 },
        .{ .n = 2, .p = 0.01, .side = .upper, .l = 0, .u = 1 },
        .{ .n = 2, .p = 0.05, .side = .upper, .l = 0, .u = 1 },
        .{ .n = 2, .p = 0.1, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.25, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.33, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.5, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.75, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.9, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.95, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 2, .p = 0.99, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 3, .p = 0.01, .side = .upper, .l = 0, .u = 1 },
        .{ .n = 3, .p = 0.05, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 3, .p = 0.1, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 3, .p = 0.25, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.33, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.5, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.75, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.9, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.95, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 3, .p = 0.99, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 8, .p = 0.01, .side = .upper, .l = 0, .u = 1 },
        .{ .n = 8, .p = 0.05, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 8, .p = 0.1, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 8, .p = 0.25, .side = .upper, .l = 0, .u = 5 },
        .{ .n = 8, .p = 0.33, .side = .upper, .l = 0, .u = 5 },
        .{ .n = 8, .p = 0.5, .side = .upper, .l = 0, .u = 7 },
        .{ .n = 8, .p = 0.75, .side = .upper, .l = 0, .u = 8 },
        .{ .n = 8, .p = 0.9, .side = .upper, .l = 0, .u = 8 },
        .{ .n = 8, .p = 0.95, .side = .upper, .l = 0, .u = 8 },
        .{ .n = 8, .p = 0.99, .side = .upper, .l = 0, .u = 8 },
        .{ .n = 9, .p = 0.01, .side = .upper, .l = 0, .u = 1 },
        .{ .n = 9, .p = 0.05, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 9, .p = 0.1, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 9, .p = 0.25, .side = .upper, .l = 0, .u = 5 },
        .{ .n = 9, .p = 0.33, .side = .upper, .l = 0, .u = 6 },
        .{ .n = 9, .p = 0.5, .side = .upper, .l = 0, .u = 7 },
        .{ .n = 9, .p = 0.75, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 9, .p = 0.9, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 9, .p = 0.95, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 9, .p = 0.99, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 20, .p = 0.01, .side = .upper, .l = 0, .u = 2 },
        .{ .n = 20, .p = 0.05, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 20, .p = 0.1, .side = .upper, .l = 0, .u = 5 },
        .{ .n = 20, .p = 0.25, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 20, .p = 0.33, .side = .upper, .l = 0, .u = 10 },
        .{ .n = 20, .p = 0.5, .side = .upper, .l = 0, .u = 14 },
        .{ .n = 20, .p = 0.75, .side = .upper, .l = 0, .u = 18 },
        .{ .n = 20, .p = 0.9, .side = .upper, .l = 0, .u = 20 },
        .{ .n = 20, .p = 0.95, .side = .upper, .l = 0, .u = 20 },
        .{ .n = 20, .p = 0.99, .side = .upper, .l = 0, .u = 20 },
        .{ .n = 100, .p = 0.01, .side = .upper, .l = 0, .u = 3 },
        .{ .n = 100, .p = 0.05, .side = .upper, .l = 0, .u = 9 },
        .{ .n = 100, .p = 0.1, .side = .upper, .l = 0, .u = 15 },
        .{ .n = 100, .p = 0.25, .side = .upper, .l = 0, .u = 32 },
        .{ .n = 100, .p = 0.33, .side = .upper, .l = 0, .u = 40 },
        .{ .n = 100, .p = 0.5, .side = .upper, .l = 0, .u = 57 },
        .{ .n = 100, .p = 0.75, .side = .upper, .l = 0, .u = 81 },
        .{ .n = 100, .p = 0.9, .side = .upper, .l = 0, .u = 95 },
        .{ .n = 100, .p = 0.95, .side = .upper, .l = 0, .u = 99 },
        .{ .n = 100, .p = 0.99, .side = .upper, .l = 0, .u = 100 },
        .{ .n = 4, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 4, .p = 0.05, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 4, .p = 0.1, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 4, .p = 0.2, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 4, .p = 0.25, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 4, .p = 0.33, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 4, .p = 0.4, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.49, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.5, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.6, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.75, .side = .symmetric, .l = 2, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.9, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 4, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 5, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 5, .p = 0.05, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 5, .p = 0.1, .side = .symmetric, .l = 1, .u = 2, .alpha = 0.05 },
        .{ .n = 5, .p = 0.2, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 5, .p = 0.25, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 5, .p = 0.33, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.4, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.49, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.5, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.6, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.75, .side = .symmetric, .l = 3, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.9, .side = .symmetric, .l = 4, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 10, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 10, .p = 0.05, .side = .symmetric, .l = 1, .u = 2, .alpha = 0.05 },
        .{ .n = 10, .p = 0.1, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 10, .p = 0.2, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 10, .p = 0.25, .side = .symmetric, .l = 1, .u = 6, .alpha = 0.05 },
        .{ .n = 10, .p = 0.33, .side = .symmetric, .l = 1, .u = 7, .alpha = 0.05 },
        .{ .n = 10, .p = 0.4, .side = .symmetric, .l = 1, .u = 8, .alpha = 0.05 },
        .{ .n = 10, .p = 0.49, .side = .symmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 10, .p = 0.5, .side = .symmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 10, .p = 0.6, .side = .symmetric, .l = 3, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.75, .side = .symmetric, .l = 5, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.9, .side = .symmetric, .l = 8, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 15, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 15, .p = 0.05, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 15, .p = 0.1, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 15, .p = 0.2, .side = .symmetric, .l = 1, .u = 7, .alpha = 0.05 },
        .{ .n = 15, .p = 0.25, .side = .symmetric, .l = 1, .u = 8, .alpha = 0.05 },
        .{ .n = 15, .p = 0.33, .side = .symmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 15, .p = 0.4, .side = .symmetric, .l = 2, .u = 10, .alpha = 0.05 },
        .{ .n = 15, .p = 0.49, .side = .symmetric, .l = 4, .u = 12, .alpha = 0.05 },
        .{ .n = 15, .p = 0.5, .side = .symmetric, .l = 4, .u = 12, .alpha = 0.05 },
        .{ .n = 15, .p = 0.6, .side = .symmetric, .l = 6, .u = 14, .alpha = 0.05 },
        .{ .n = 15, .p = 0.75, .side = .symmetric, .l = 8, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.9, .side = .symmetric, .l = 12, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 40, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 40, .p = 0.05, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 40, .p = 0.1, .side = .symmetric, .l = 1, .u = 9, .alpha = 0.05 },
        .{ .n = 40, .p = 0.2, .side = .symmetric, .l = 4, .u = 14, .alpha = 0.05 },
        .{ .n = 40, .p = 0.25, .side = .symmetric, .l = 5, .u = 16, .alpha = 0.05 },
        .{ .n = 40, .p = 0.33, .side = .symmetric, .l = 7, .u = 19, .alpha = 0.05 },
        .{ .n = 40, .p = 0.4, .side = .symmetric, .l = 10, .u = 23, .alpha = 0.05 },
        .{ .n = 40, .p = 0.49, .side = .symmetric, .l = 14, .u = 27, .alpha = 0.05 },
        .{ .n = 40, .p = 0.5, .side = .symmetric, .l = 14, .u = 27, .alpha = 0.05 },
        .{ .n = 40, .p = 0.6, .side = .symmetric, .l = 18, .u = 31, .alpha = 0.05 },
        .{ .n = 40, .p = 0.75, .side = .symmetric, .l = 25, .u = 36, .alpha = 0.05 },
        .{ .n = 40, .p = 0.9, .side = .symmetric, .l = 32, .u = 40, .alpha = 0.05 },
        .{ .n = 40, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.05 },
        .{ .n = 101, .p = 0.01, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.05 },
        .{ .n = 101, .p = 0.05, .side = .symmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 101, .p = 0.1, .side = .symmetric, .l = 5, .u = 17, .alpha = 0.05 },
        .{ .n = 101, .p = 0.2, .side = .symmetric, .l = 12, .u = 28, .alpha = 0.05 },
        .{ .n = 101, .p = 0.25, .side = .symmetric, .l = 16, .u = 34, .alpha = 0.05 },
        .{ .n = 101, .p = 0.33, .side = .symmetric, .l = 24, .u = 43, .alpha = 0.05 },
        .{ .n = 101, .p = 0.4, .side = .symmetric, .l = 30, .u = 50, .alpha = 0.05 },
        .{ .n = 101, .p = 0.49, .side = .symmetric, .l = 40, .u = 60, .alpha = 0.05 },
        .{ .n = 101, .p = 0.5, .side = .symmetric, .l = 41, .u = 61, .alpha = 0.05 },
        .{ .n = 101, .p = 0.6, .side = .symmetric, .l = 52, .u = 72, .alpha = 0.05 },
        .{ .n = 101, .p = 0.75, .side = .symmetric, .l = 68, .u = 86, .alpha = 0.05 },
        .{ .n = 101, .p = 0.9, .side = .symmetric, .l = 85, .u = 97, .alpha = 0.05 },
        .{ .n = 101, .p = 0.99, .side = .symmetric, .l = 99, .u = 101, .alpha = 0.05 },
        .{ .n = 4, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 4, .p = 0.05, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 4, .p = 0.1, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 4, .p = 0.2, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 4, .p = 0.25, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 4, .p = 0.33, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 4, .p = 0.4, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.49, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.5, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.6, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.75, .side = .symmetric, .l = 2, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.9, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 4, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 5, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 5, .p = 0.05, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 5, .p = 0.1, .side = .symmetric, .l = 1, .u = 2, .alpha = 0.2 },
        .{ .n = 5, .p = 0.2, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 5, .p = 0.25, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 5, .p = 0.33, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 5, .p = 0.4, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 5, .p = 0.49, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.5, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.6, .side = .symmetric, .l = 2, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.75, .side = .symmetric, .l = 3, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.9, .side = .symmetric, .l = 4, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 10, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 10, .p = 0.05, .side = .symmetric, .l = 1, .u = 2, .alpha = 0.2 },
        .{ .n = 10, .p = 0.1, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 10, .p = 0.2, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 10, .p = 0.25, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 10, .p = 0.33, .side = .symmetric, .l = 2, .u = 6, .alpha = 0.2 },
        .{ .n = 10, .p = 0.4, .side = .symmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 10, .p = 0.49, .side = .symmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 10, .p = 0.5, .side = .symmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 10, .p = 0.6, .side = .symmetric, .l = 4, .u = 9, .alpha = 0.2 },
        .{ .n = 10, .p = 0.75, .side = .symmetric, .l = 6, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.9, .side = .symmetric, .l = 8, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 15, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 15, .p = 0.05, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 15, .p = 0.1, .side = .symmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 15, .p = 0.2, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 15, .p = 0.25, .side = .symmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 15, .p = 0.33, .side = .symmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 15, .p = 0.4, .side = .symmetric, .l = 4, .u = 9, .alpha = 0.2 },
        .{ .n = 15, .p = 0.49, .side = .symmetric, .l = 4, .u = 10, .alpha = 0.2 },
        .{ .n = 15, .p = 0.5, .side = .symmetric, .l = 5, .u = 11, .alpha = 0.2 },
        .{ .n = 15, .p = 0.6, .side = .symmetric, .l = 7, .u = 12, .alpha = 0.2 },
        .{ .n = 15, .p = 0.75, .side = .symmetric, .l = 9, .u = 14, .alpha = 0.2 },
        .{ .n = 15, .p = 0.9, .side = .symmetric, .l = 12, .u = 15, .alpha = 0.2 },
        .{ .n = 15, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 40, .p = 0.01, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 40, .p = 0.05, .side = .symmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 40, .p = 0.1, .side = .symmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 40, .p = 0.2, .side = .symmetric, .l = 5, .u = 12, .alpha = 0.2 },
        .{ .n = 40, .p = 0.25, .side = .symmetric, .l = 7, .u = 14, .alpha = 0.2 },
        .{ .n = 40, .p = 0.33, .side = .symmetric, .l = 9, .u = 17, .alpha = 0.2 },
        .{ .n = 40, .p = 0.4, .side = .symmetric, .l = 12, .u = 21, .alpha = 0.2 },
        .{ .n = 40, .p = 0.49, .side = .symmetric, .l = 16, .u = 25, .alpha = 0.2 },
        .{ .n = 40, .p = 0.5, .side = .symmetric, .l = 16, .u = 25, .alpha = 0.2 },
        .{ .n = 40, .p = 0.6, .side = .symmetric, .l = 20, .u = 29, .alpha = 0.2 },
        .{ .n = 40, .p = 0.75, .side = .symmetric, .l = 27, .u = 34, .alpha = 0.2 },
        .{ .n = 40, .p = 0.9, .side = .symmetric, .l = 34, .u = 39, .alpha = 0.2 },
        .{ .n = 40, .p = 0.99, .side = .symmetric, .l = 0, .u = 0, .alpha = 0.2 },
        .{ .n = 101, .p = 0.01, .side = .symmetric, .l = 1, .u = 3, .alpha = 0.2 },
        .{ .n = 101, .p = 0.05, .side = .symmetric, .l = 3, .u = 9, .alpha = 0.2 },
        .{ .n = 101, .p = 0.1, .side = .symmetric, .l = 7, .u = 15, .alpha = 0.2 },
        .{ .n = 101, .p = 0.2, .side = .symmetric, .l = 15, .u = 26, .alpha = 0.2 },
        .{ .n = 101, .p = 0.25, .side = .symmetric, .l = 19, .u = 31, .alpha = 0.2 },
        .{ .n = 101, .p = 0.33, .side = .symmetric, .l = 27, .u = 40, .alpha = 0.2 },
        .{ .n = 101, .p = 0.4, .side = .symmetric, .l = 34, .u = 47, .alpha = 0.2 },
        .{ .n = 101, .p = 0.49, .side = .symmetric, .l = 43, .u = 56, .alpha = 0.2 },
        .{ .n = 101, .p = 0.5, .side = .symmetric, .l = 45, .u = 58, .alpha = 0.2 },
        .{ .n = 101, .p = 0.6, .side = .symmetric, .l = 55, .u = 68, .alpha = 0.2 },
        .{ .n = 101, .p = 0.75, .side = .symmetric, .l = 71, .u = 83, .alpha = 0.2 },
        .{ .n = 101, .p = 0.9, .side = .symmetric, .l = 87, .u = 95, .alpha = 0.2 },
        .{ .n = 101, .p = 0.99, .side = .symmetric, .l = 99, .u = 101, .alpha = 0.2 },
        .{ .n = 4, .p = 0.01, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.05, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.1, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.2, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.25, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.33, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.4, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.49, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.5, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.6, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.75, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.9, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 4, .p = 0.99, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.05 },
        .{ .n = 5, .p = 0.01, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.05, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.1, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.2, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.25, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.33, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.4, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.49, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.5, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.6, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.75, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.9, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 5, .p = 0.99, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.05 },
        .{ .n = 10, .p = 0.01, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.05, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.1, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.2, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.25, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.33, .side = .asymmetric, .l = 1, .u = 7, .alpha = 0.05 },
        .{ .n = 10, .p = 0.4, .side = .asymmetric, .l = 1, .u = 8, .alpha = 0.05 },
        .{ .n = 10, .p = 0.49, .side = .asymmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 10, .p = 0.5, .side = .asymmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 10, .p = 0.6, .side = .asymmetric, .l = 3, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.75, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.9, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 10, .p = 0.99, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 15, .p = 0.01, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.05, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.1, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.2, .side = .asymmetric, .l = 1, .u = 8, .alpha = 0.05 },
        .{ .n = 15, .p = 0.25, .side = .asymmetric, .l = 1, .u = 8, .alpha = 0.05 },
        .{ .n = 15, .p = 0.33, .side = .asymmetric, .l = 2, .u = 9, .alpha = 0.05 },
        .{ .n = 15, .p = 0.4, .side = .asymmetric, .l = 2, .u = 10, .alpha = 0.05 },
        .{ .n = 15, .p = 0.49, .side = .asymmetric, .l = 4, .u = 12, .alpha = 0.05 },
        .{ .n = 15, .p = 0.5, .side = .asymmetric, .l = 4, .u = 12, .alpha = 0.05 },
        .{ .n = 15, .p = 0.6, .side = .asymmetric, .l = 6, .u = 14, .alpha = 0.05 },
        .{ .n = 15, .p = 0.75, .side = .asymmetric, .l = 8, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.9, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.05 },
        .{ .n = 15, .p = 0.99, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.05 },
        .{ .n = 40, .p = 0.01, .side = .asymmetric, .l = 1, .u = 40, .alpha = 0.05 },
        .{ .n = 40, .p = 0.05, .side = .asymmetric, .l = 1, .u = 40, .alpha = 0.05 },
        .{ .n = 40, .p = 0.1, .side = .asymmetric, .l = 1, .u = 9, .alpha = 0.05 },
        .{ .n = 40, .p = 0.2, .side = .asymmetric, .l = 4, .u = 14, .alpha = 0.05 },
        .{ .n = 40, .p = 0.25, .side = .asymmetric, .l = 5, .u = 16, .alpha = 0.05 },
        .{ .n = 40, .p = 0.33, .side = .asymmetric, .l = 7, .u = 19, .alpha = 0.05 },
        .{ .n = 40, .p = 0.4, .side = .asymmetric, .l = 10, .u = 23, .alpha = 0.05 },
        .{ .n = 40, .p = 0.49, .side = .asymmetric, .l = 14, .u = 27, .alpha = 0.05 },
        .{ .n = 40, .p = 0.5, .side = .asymmetric, .l = 14, .u = 27, .alpha = 0.05 },
        .{ .n = 40, .p = 0.6, .side = .asymmetric, .l = 18, .u = 31, .alpha = 0.05 },
        .{ .n = 40, .p = 0.75, .side = .asymmetric, .l = 25, .u = 36, .alpha = 0.05 },
        .{ .n = 40, .p = 0.9, .side = .asymmetric, .l = 32, .u = 40, .alpha = 0.05 },
        .{ .n = 40, .p = 0.99, .side = .asymmetric, .l = 1, .u = 40, .alpha = 0.05 },
        .{ .n = 101, .p = 0.01, .side = .asymmetric, .l = 1, .u = 101, .alpha = 0.05 },
        .{ .n = 101, .p = 0.05, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.05 },
        .{ .n = 101, .p = 0.1, .side = .asymmetric, .l = 5, .u = 17, .alpha = 0.05 },
        .{ .n = 101, .p = 0.2, .side = .asymmetric, .l = 12, .u = 28, .alpha = 0.05 },
        .{ .n = 101, .p = 0.25, .side = .asymmetric, .l = 16, .u = 34, .alpha = 0.05 },
        .{ .n = 101, .p = 0.33, .side = .asymmetric, .l = 24, .u = 43, .alpha = 0.05 },
        .{ .n = 101, .p = 0.4, .side = .asymmetric, .l = 30, .u = 50, .alpha = 0.05 },
        .{ .n = 101, .p = 0.49, .side = .asymmetric, .l = 40, .u = 60, .alpha = 0.05 },
        .{ .n = 101, .p = 0.5, .side = .asymmetric, .l = 41, .u = 61, .alpha = 0.05 },
        .{ .n = 101, .p = 0.6, .side = .asymmetric, .l = 52, .u = 72, .alpha = 0.05 },
        .{ .n = 101, .p = 0.75, .side = .asymmetric, .l = 68, .u = 86, .alpha = 0.05 },
        .{ .n = 101, .p = 0.9, .side = .asymmetric, .l = 85, .u = 97, .alpha = 0.05 },
        .{ .n = 101, .p = 0.99, .side = .asymmetric, .l = 1, .u = 101, .alpha = 0.05 },
        .{ .n = 4, .p = 0.01, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.05, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.1, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.2, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.25, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.33, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.4, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.49, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.5, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.6, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.75, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.9, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 4, .p = 0.99, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 5, .p = 0.01, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.05, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.1, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.2, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.25, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.33, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 5, .p = 0.4, .side = .asymmetric, .l = 1, .u = 4, .alpha = 0.2 },
        .{ .n = 5, .p = 0.49, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.5, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.6, .side = .asymmetric, .l = 2, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.75, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.9, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 5, .p = 0.99, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 10, .p = 0.01, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.05, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.1, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.2, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 10, .p = 0.25, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 10, .p = 0.33, .side = .asymmetric, .l = 2, .u = 6, .alpha = 0.2 },
        .{ .n = 10, .p = 0.4, .side = .asymmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 10, .p = 0.49, .side = .asymmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 10, .p = 0.5, .side = .asymmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 10, .p = 0.6, .side = .asymmetric, .l = 4, .u = 9, .alpha = 0.2 },
        .{ .n = 10, .p = 0.75, .side = .asymmetric, .l = 6, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.9, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.2 },
        .{ .n = 10, .p = 0.99, .side = .asymmetric, .l = 1, .u = 10, .alpha = 0.2 },
        .{ .n = 15, .p = 0.01, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.2 },
        .{ .n = 15, .p = 0.05, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.2 },
        .{ .n = 15, .p = 0.1, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.2 },
        .{ .n = 15, .p = 0.2, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 15, .p = 0.25, .side = .asymmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 15, .p = 0.33, .side = .asymmetric, .l = 3, .u = 8, .alpha = 0.2 },
        .{ .n = 15, .p = 0.4, .side = .asymmetric, .l = 4, .u = 9, .alpha = 0.2 },
        .{ .n = 15, .p = 0.49, .side = .asymmetric, .l = 4, .u = 10, .alpha = 0.2 },
        .{ .n = 15, .p = 0.5, .side = .asymmetric, .l = 5, .u = 11, .alpha = 0.2 },
        .{ .n = 15, .p = 0.6, .side = .asymmetric, .l = 7, .u = 12, .alpha = 0.2 },
        .{ .n = 15, .p = 0.75, .side = .asymmetric, .l = 9, .u = 14, .alpha = 0.2 },
        .{ .n = 15, .p = 0.9, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.2 },
        .{ .n = 15, .p = 0.99, .side = .asymmetric, .l = 1, .u = 15, .alpha = 0.2 },
        .{ .n = 40, .p = 0.01, .side = .asymmetric, .l = 1, .u = 40, .alpha = 0.2 },
        .{ .n = 40, .p = 0.05, .side = .asymmetric, .l = 1, .u = 5, .alpha = 0.2 },
        .{ .n = 40, .p = 0.1, .side = .asymmetric, .l = 2, .u = 7, .alpha = 0.2 },
        .{ .n = 40, .p = 0.2, .side = .asymmetric, .l = 5, .u = 12, .alpha = 0.2 },
        .{ .n = 40, .p = 0.25, .side = .asymmetric, .l = 7, .u = 14, .alpha = 0.2 },
        .{ .n = 40, .p = 0.33, .side = .asymmetric, .l = 9, .u = 17, .alpha = 0.2 },
        .{ .n = 40, .p = 0.4, .side = .asymmetric, .l = 12, .u = 21, .alpha = 0.2 },
        .{ .n = 40, .p = 0.49, .side = .asymmetric, .l = 16, .u = 25, .alpha = 0.2 },
        .{ .n = 40, .p = 0.5, .side = .asymmetric, .l = 16, .u = 25, .alpha = 0.2 },
        .{ .n = 40, .p = 0.6, .side = .asymmetric, .l = 20, .u = 29, .alpha = 0.2 },
        .{ .n = 40, .p = 0.75, .side = .asymmetric, .l = 27, .u = 34, .alpha = 0.2 },
        .{ .n = 40, .p = 0.9, .side = .asymmetric, .l = 34, .u = 39, .alpha = 0.2 },
        .{ .n = 40, .p = 0.99, .side = .asymmetric, .l = 1, .u = 40, .alpha = 0.2 },
        .{ .n = 101, .p = 0.01, .side = .asymmetric, .l = 1, .u = 101, .alpha = 0.2 },
        .{ .n = 101, .p = 0.05, .side = .asymmetric, .l = 3, .u = 9, .alpha = 0.2 },
        .{ .n = 101, .p = 0.1, .side = .asymmetric, .l = 7, .u = 15, .alpha = 0.2 },
        .{ .n = 101, .p = 0.2, .side = .asymmetric, .l = 15, .u = 26, .alpha = 0.2 },
        .{ .n = 101, .p = 0.25, .side = .asymmetric, .l = 19, .u = 31, .alpha = 0.2 },
        .{ .n = 101, .p = 0.33, .side = .asymmetric, .l = 27, .u = 40, .alpha = 0.2 },
        .{ .n = 101, .p = 0.4, .side = .asymmetric, .l = 34, .u = 47, .alpha = 0.2 },
        .{ .n = 101, .p = 0.49, .side = .asymmetric, .l = 43, .u = 56, .alpha = 0.2 },
        .{ .n = 101, .p = 0.5, .side = .asymmetric, .l = 45, .u = 58, .alpha = 0.2 },
        .{ .n = 101, .p = 0.6, .side = .asymmetric, .l = 55, .u = 68, .alpha = 0.2 },
        .{ .n = 101, .p = 0.75, .side = .asymmetric, .l = 71, .u = 83, .alpha = 0.2 },
        .{ .n = 101, .p = 0.9, .side = .asymmetric, .l = 87, .u = 95, .alpha = 0.2 },
        .{ .n = 101, .p = 0.99, .side = .asymmetric, .l = 1, .u = 101, .alpha = 0.2 },
    };
    var x: [101]f64 = undefined;
    for (&x, 0..) |*v, i| v.* = @floatFromInt(i + 1);
    var failures: usize = 0;
    for (cases) |c| {
        const got = distributionFree(x[0..c.n], c.p, .{ .side = c.side }, c.alpha);
        if (got.lower_rank != c.l or got.upper_rank != c.u) {
            std.debug.print("rank n={d} p={d} alpha={d} side={s}: got {d},{d}, expected {d},{d}\n", .{ c.n, c.p, c.alpha, @tagName(c.side), got.lower_rank, got.upper_rank, c.l, c.u });
            failures += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), failures);
}

test "UNIVARIATE normal percentile large noncentrality SAS endpoints" {
    // endpoints.sas; noncentral-t integration is needed beyond the shared
    // AS243 Poisson-series iteration range. Absolute interval tolerance 1e-6.
    for ([_]usize{ 8, 2001 }, [_]f64{ -35.258601836477, -3736.38934347812 }, [_]f64{ -8.23390172562075, -3447.27735722692 }) |n, lo, hi| {
        const nf: f64 = @floatFromInt(n);
        const got = normalQuantileCI((nf + 1) / 2, @sqrt(nf * (nf + 1) / 12), n, 0, .{}, 0.05);
        try std.testing.expectApproxEqAbs(lo, got.lower, 1e-6);
        try std.testing.expectApproxEqAbs(hi, got.upper, 1e-6);
    }
}
test {
    _ = @import("univ_inference_tests.zig");
}

pub fn signedRankAsymptotic(d: []const i64, tobs: i64) f64 {
    const nf: f64 = @floatFromInt(d.len);
    const s = @as(f64, @floatFromInt(tobs)) / 4.0;
    // SAS Statistical Procedures p.417: Iman/Conover t approximation,
    // not a continuity-corrected normal approximation. Using actual doubled
    // midranks incorporates ties exactly: V = sum(rank^2)/4.
    // rank.sas oracle n=21, x=1..21: S=115.5, p=9.1830084743323E-8.
    var variance: f64 = 0;
    for (d) |rank| {
        const r: f64 = @floatFromInt(rank);
        variance += r * r / 16;
    }
    const denominator = nf * variance - s * s;
    if (denominator <= 0) return if (s == 0) 1 else 0;
    return tProbability(s * @sqrt((nf - 1) / denominator), nf - 1);
}

test "UNIVARIATE extreme central t confidence tail exceeds generic bracket" {
    // df=1 is exactly Cauchy: t_p=-cot(pi*p). Absolute 1e-5 at 3.18e7
    // corresponds to relative 3.2e-13, not a relaxed ordinary-CI tolerance.
    const p: f64 = 1e-8;
    try std.testing.expectApproxEqAbs(-1 / @tan(std.math.pi * p), tQuantile(p, 1), 1e-5);
}
test "UNIVARIATE EDF bounds ties and SW method boundary" {
    // edf.sas: n=20,shape=.5 -> CvM/AD <.005, KS=.03910080069439.
    // Existing OUTTABLE normality qualification is also required for NORMAL.
    const a = std.testing.allocator;
    for ([_]usize{ 20, 2001 }) |n| {
        const x = try a.alloc(f64, n);
        defer a.free(x);
        for (x, 0..) |*v, i| {
            const z = f.distQuantile(.normal, (@as(f64, @floatFromInt(i + 1)) - 0.375) / (@as(f64, @floatFromInt(n)) + 0.25), &.{}).?;
            v.* = z + 0.5 * (z * z - 1);
        }
        std.mem.sort(f64, x, {}, std.sort.asc(f64));
        const result = (try normalTests(a, x)).?;
        try std.testing.expectEqual(@as(f64, 0.005), result.pw2);
        try std.testing.expectEqual(@as(f64, 0.005), result.pa2);
        if (n == 20) try std.testing.expectApproxEqAbs(@as(f64, 0.03910080069439), result.pd, 1e-8) else try std.testing.expectEqual(normality.Method.kolmogorov_smirnov, result.primary.method);
    }
    try std.testing.expectEqual(@as(?NormalTests, null), try normalTests(a, &.{ 7, 7, 7 }));
    try std.testing.expectEqual(@as(?NormalTests, null), try normalTests(a, &.{1}));
    const ties = (try normalTests(a, &.{ 0, 0, 1 })).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), ties.primary.statistic, 1e-10);
}
test "UNIVARIATE moment intervals SAS precise ODS values and one-sided tails" {
    // listing-numeric.sas/Table bi, manual p.417. Exact central calculations
    // checked at 1e-9 absolute, not at listing precision.
    const m = meanCI(4.5, @sqrt(@as(f64, 0.75)), 7, .{}, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 2.45217532771588), m.lower, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 6.54782467228411), m.upper, 1e-9);
    const v = varianceCI(42, 7, .{}, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 2.62290753049708), v.lower, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 24.853994901052), v.upper, 1e-9);
    const lower = meanCI(4.5, @sqrt(@as(f64, 0.75)), 7, .{ .side = .lower }, 0.025);
    try std.testing.expectEqual(m.lower, lower.lower);
    try std.testing.expect(std.math.isNan(lower.upper));
    const upper = varianceCI(42, 7, .{ .side = .upper }, 0.025);
    try std.testing.expectEqual(v.upper, upper.upper);
    try std.testing.expect(std.math.isNan(upper.lower));
}
