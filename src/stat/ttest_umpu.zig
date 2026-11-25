//! UMPU standard-deviation intervals required by hidden TTEST ODS columns.
//! S154 physical pp.10621-10622: acceptance mass and first moment both equal
//! 1-alpha. For chi-square(df), the moment condition reduces to equal endpoint
//! x*density(x), or df*log(c1/c2)-c1+c2=0.
const std = @import("std");
const f = @import("../functions.zig");
const Value = @import("../value.zig").Value;
const fit = @import("ttest_fit.zig");
const diag = @import("../diag.zig");

pub fn chiQuantile(p: f64, df: f64) f64 {
    var lo: f64 = 0;
    var hi = @max(1, df);
    while (f.distCdf(.chisq, hi, &.{ Value{ .num = 0 }, Value{ .num = 0 }, Value{ .num = df } }).? < p and hi < 1e300) hi *= 2;
    for (0..120) |_| {
        const mid = lo + (hi - lo) / 2;
        if (mid == lo or mid == hi) break;
        if (f.distCdf(.chisq, mid, &.{ Value{ .num = 0 }, Value{ .num = 0 }, Value{ .num = df } }).? < p) lo = mid else hi = mid;
    }
    return lo + (hi - lo) / 2;
}
pub fn sdInterval(sd: f64, df: f64, alpha: f64) diag.Error!fit.Interval {
    if (!(df > 0) or std.math.isNan(sd)) return .{};
    if (!(alpha > 0 and alpha < 1) or !std.math.isFinite(sd) or sd < 0) return error.ExecError;
    var lo: f64 = 0;
    var hi = alpha;
    var c1: f64 = 0;
    var c2: f64 = 0;
    for (0..80) |_| {
        const p = lo + (hi - lo) / 2;
        if (p == lo or p == hi) break;
        c1 = chiQuantile(p, df);
        c2 = chiQuantile(1 - alpha + p, df);
        const residual = df * (@log(c1) - @log(c2)) - c1 + c2;
        if (residual > 0) hi = p else lo = p;
    }
    const p = lo + (hi - lo) / 2;
    c1 = chiQuantile(p, df);
    c2 = chiQuantile(1 - alpha + p, df);
    const r: fit.Interval = .{ .lower = sd * @sqrt(df / c2), .upper = sd * @sqrt(df / c1) };
    if (!std.math.isFinite(r.lower) or !std.math.isFinite(r.upper)) return error.ExecError;
    return r;
}

test "TTEST ODS UMPU endpoints satisfy independent mass and moment equations" {
    const df: f64 = 5;
    const alpha: f64 = 0.05;
    const r = try sdInterval(1, df, alpha);
    const c1 = df / (r.upper * r.upper);
    const c2 = df / (r.lower * r.lower);
    const mass = f.distCdf(.chisq, c2, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = df } }).? - f.distCdf(.chisq, c1, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = df } }).?;
    const moment = f.distCdf(.chisq, c2, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = df + 2 } }).? - f.distCdf(.chisq, c1, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = df + 2 } }).?;
    try std.testing.expectApproxEqAbs(1 - alpha, mass, 2e-14);
    try std.testing.expectApproxEqAbs(1 - alpha, moment, 2e-14);
    const scaled = try sdInterval(3, df, alpha);
    try std.testing.expectApproxEqAbs(3 * r.lower, scaled.lower, 1e-14);
    try std.testing.expectApproxEqAbs(3 * r.upper, scaled.upper, 1e-14);
}
