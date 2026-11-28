//! Studentized range distribution with finite error degrees of freedom
//! (STAT-ANOVA-007; S154 ch.53 "Multiple Comparisons", Tukey's HSD).
//!
//! Q = R/s where R is the range of k independent N(0,1) and df*s^2 ~ chi2(df):
//!   P(Q<q) = integral_0^inf f_s(s) * W(q*s; k) ds,
//!   W(w;k) = k * integral phi(z) [Phi(z) - Phi(z-w)]^(k-1) dz   (z = maximum),
//!   f_s(s) = 2 (df/2)^(df/2) / Gamma(df/2) * s^(df-1) * exp(-df s^2/2).
//! Both integrals use the trapezoid rule on the whole line (outer after
//! s = e^u), which converges geometrically for these analytic, rapidly
//! decaying integrands.
//! ponytail: fixed step sizes instead of adaptive error control; the tests
//! pin k=2 against sqrt(2)*t and an independent Simpson integration.
const std = @import("std");
const f = @import("../functions.zig");

fn sf(x: f64) f64 {
    return @exp(f.logStdNormTail(x));
}

/// Distribution function of the range of k independent standard normals.
pub fn normalRangeCdf(w: f64, k: usize) f64 {
    if (!(w > 0)) return 0;
    const h = 0.1;
    const power: f64 = @floatFromInt(k - 1);
    var sum: f64 = 0;
    var i: i32 = -90;
    while (i <= 90) : (i += 1) {
        const z = @as(f64, @floatFromInt(i)) * h;
        const inside = sf(z - w) - sf(z);
        if (inside <= 0) continue;
        sum += @exp(-z * z / 2) * std.math.pow(f64, inside, power);
    }
    return @min(1, @as(f64, @floatFromInt(k)) * sum * h / @sqrt(2 * std.math.pi));
}

/// P(Q < q) for k means and df error degrees of freedom.
pub fn cdf(q: f64, k: usize, df: f64) error{InvalidArgument}!f64 {
    if (k < 2 or !(df >= 1) or !std.math.isFinite(df) or std.math.isNan(q)) return error.InvalidArgument;
    if (q <= 0) return 0;
    const spread = @sqrt(40 / df);
    const lo = -40 / df - spread;
    const hi = @log(1 + spread) + 0.5 * @log(1 + 100 / df);
    const h = @min(0.05, 0.2 / @sqrt(df));
    const steps: usize = @intFromFloat(@ceil((hi - lo) / h));
    const constant = @log(2.0) + df / 2 * @log(df / 2) - f.lgammaOf(df / 2);
    var sum: f64 = 0;
    for (0..steps + 1) |i| {
        const u = lo + @as(f64, @floatFromInt(i)) * h;
        const s = @exp(u);
        const density = @exp(constant + df * u - df * s * s / 2);
        if (density == 0) continue;
        sum += density * normalRangeCdf(q * s, k);
    }
    return @max(0, @min(1, sum * h));
}

/// Upper-alpha critical value: q with P(Q > q) = alpha.
pub fn critical(alpha: f64, k: usize, df: f64) error{InvalidArgument}!f64 {
    if (!(alpha > 0 and alpha < 1)) return error.InvalidArgument;
    const target = 1 - alpha;
    var lo: f64 = 0;
    var hi: f64 = 8;
    while (try cdf(hi, k, df) < target) {
        hi *= 2;
        if (hi > 1e6) return error.InvalidArgument;
    }
    while (hi - lo > 1e-11 * @max(1, hi)) {
        const mid = (lo + hi) / 2;
        if (try cdf(mid, k, df) < target) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

// Independent check: composite Simpson over the chi-square variable x
// (s = sqrt(x/df)) with the inner integral conditioned on the MINIMUM
// instead of the maximum: W(w) = k * integral phi(z) [Phi(z+w)-Phi(z)]^(k-1) dz.
fn simpsonRange(w: f64, k: usize) f64 {
    const n: usize = 2000;
    const a: f64 = -10;
    const h = 20.0 / @as(f64, @floatFromInt(n));
    var sum: f64 = 0;
    for (0..n + 1) |i| {
        const z = a + h * @as(f64, @floatFromInt(i));
        const value = @exp(-z * z / 2) / @sqrt(2 * std.math.pi) * std.math.pow(f64, @max(0, sf(z) - sf(z + w)), @floatFromInt(k - 1));
        sum += value * @as(f64, if (i == 0 or i == n) 1 else if (i % 2 == 1) 4 else 2);
    }
    return @as(f64, @floatFromInt(k)) * sum * h / 3;
}
fn simpsonCdf(q: f64, k: usize, df: f64, upper: f64, n: usize) f64 {
    const h = upper / @as(f64, @floatFromInt(n));
    var sum: f64 = 0;
    for (1..n + 1) |i| { // density vanishes at x=0 for df>2
        const x = h * @as(f64, @floatFromInt(i));
        const density = @exp((df / 2 - 1) * @log(x) - x / 2 - df / 2 * @log(2.0) - f.lgammaOf(df / 2));
        sum += density * simpsonRange(q * @sqrt(x / df), k) * @as(f64, if (i == n) 1 else if (i % 2 == 1) 4 else 2);
    }
    return sum * h / 3;
}

test "ANOVA007 studentized range: k=2 equals sqrt(2)*t, and matches independent Simpson integration" {
    const t = std.testing;
    // k=2: Q = |X1-X2|/s = sqrt(2)*|T|, so q(alpha;2,df) = sqrt(2)*t(1-alpha/2;df).
    // t(0.975;10) = 2.228138852 and t(0.975;4) = 2.776445105 (standard tables).
    try t.expectApproxEqAbs(@sqrt(2.0) * 2.228138852, try critical(0.05, 2, 10), 2e-8);
    try t.expectApproxEqAbs(@sqrt(2.0) * 2.776445105, try critical(0.05, 2, 4), 2e-8);
    // Independent quadrature (different rule, variable and conditioning).
    // Simpson error here is far below 1e-7; the bound is the quadrature
    // budget of both rules, not a fit to an observed difference.
    for ([_]struct { q: f64, k: usize, df: f64 }{ .{ .q = 4.37265, .k = 6, .df = 24 }, .{ .q = 3.5, .k = 3, .df = 4 }, .{ .q = 5.0, .k = 4, .df = 9 } }) |c| {
        try t.expectApproxEqAbs(simpsonCdf(c.q, c.k, c.df, 40 + 20 * c.df, 4000), try cdf(c.q, c.k, c.df), 1e-7);
    }
    // Published table values (Harter 1960): q(.05;6,24)=4.373, q(.05;3,10)=3.877,
    // q(.01;4,12)=5.502; table rounding is 0.0005.
    try t.expectApproxEqAbs(4.373, try critical(0.05, 6, 24), 5e-4);
    try t.expectApproxEqAbs(3.877, try critical(0.05, 3, 10), 5e-4);
    try t.expectApproxEqAbs(5.502, try critical(0.01, 4, 12), 5e-4);
    try t.expectError(error.InvalidArgument, critical(0, 3, 10));
    try t.expectError(error.InvalidArgument, critical(0.05, 1, 10));
    try t.expectError(error.InvalidArgument, critical(0.05, 3, 0));
}
