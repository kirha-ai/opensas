//! UNIVARIATE inference listing tables; computations live in univ_inference.
const std = @import("std");
const k = @import("univ_inference.zig");
const Options = @import("univ_inference_parse.zig").Options;
const Summary = @import("univariate.zig").Summary;
const h = @import("../proc.zig").UnivariateHelpers;
const A = std.mem.Allocator;
fn num(a: A, x: f64) ![]const u8 {
    return if (std.math.isNan(x)) "." else std.fmt.allocPrint(a, "{d:.6}", .{x});
}
fn row(a: A, out: *std.ArrayList(u8), name: []const u8, values: []const f64) !void {
    try out.appendSlice(a, name);
    for (values) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s}", .{try num(a, v)}));
    try out.append(a, '\n');
}
fn heading(a: A, out: *std.ArrayList(u8), text: []const u8, ci: k.CI, alpha: f64) !void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n{d}% {s}\n", .{ text, 100 * (1 - (ci.alpha orelse alpha)), switch (ci.side) {
        .lower => "Lower Confidence Bound",
        .upper => "Upper Confidence Bound",
        else => "Confidence Limits",
    } }));
}
fn normalRow(a: A, out: *std.ArrayList(u8), name: []const u8, symbol: []const u8, stat: f64, p: f64, bound: f64) !void {
    const qualifier: []const u8 = if (bound > 0 and p == bound) ">" else if (bound > 0 and p == (if (bound == 0.15) @as(f64, 0.01) else 0.005)) "<" else if (bound == 0 and p < 0.0001) "<" else " ";
    try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}  {s}  {d:.6}  {s}{d:.4}\n", .{ name, symbol, stat, qualifier, if (bound == 0) @max(p, 0.0001) else p }));
}
pub fn render(a: A, out: *std.ArrayList(u8), z: Summary, df: bool, def: u8, mu0: f64, opt: Options) !void {
    if (!opt.normal and !opt.robustscale and !opt.loccount and opt.basic == null and opt.df == null and opt.normal_ci == null and opt.trim.len == 0 and opt.winsor.len == 0) return;
    const x = try a.alloc(f64, z.pairs.len);
    defer a.free(x);
    for (z.pairs, 0..) |v, j| x[j] = v.x;
    if (opt.basic) |ci| {
        try heading(a, out, "Basic Confidence Limits Assuming Normality", ci, opt.alpha);
        try out.appendSlice(a, "Parameter  Estimate  Lower  Upper\n");
        const n: f64 = @floatFromInt(z.s.n);
        const mean = k.meanCI(z.s.mean, z.s.std / @sqrt(z.s.sumw), n - 1, ci, opt.alpha);
        const variance = k.varianceCI(z.s.css, n - 1, ci, opt.alpha);
        try row(a, out, "Mean", &.{ z.s.mean, mean.lower, mean.upper });
        try row(a, out, "Std Deviation", &.{ z.s.std, @sqrt(variance.lower), @sqrt(variance.upper) });
        try row(a, out, "Variance", &.{ z.s.std * z.s.std, variance.lower, variance.upper });
    }
    if (opt.loccount) {
        var positive: f64 = 0;
        var negative: f64 = 0;
        for (x) |v| {
            if (v > mu0) positive += 1;
            if (v < mu0) negative += 1;
        }
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nLocation Counts: Mu0={d}\n", .{mu0}));
        try row(a, out, "Num Obs > Mu0", &.{positive});
        try row(a, out, "Num Obs ^= Mu0", &.{positive + negative});
        try row(a, out, "Num Obs < Mu0", &.{negative});
    }
    if (opt.normal) {
        try out.appendSlice(a, "\nTests for Normality\nTest  Statistic  p Value\n");
        if (try k.normalTests(a, x)) |tests| {
            if (tests.primary.method == .shapiro_wilk) try normalRow(a, out, "Shapiro-Wilk", "W", tests.primary.statistic, tests.primary.p, 0);
            try normalRow(a, out, "Kolmogorov-Smirnov", "D", tests.d, tests.pd, 0.15);
            try normalRow(a, out, "Cramer-von Mises", "W-Sq", tests.w2, tests.pw2, 0.25);
            try normalRow(a, out, "Anderson-Darling", "A-Sq", tests.a2, tests.pa2, 0.25);
        } else {
            if (x.len <= 2000) try out.appendSlice(a, "Shapiro-Wilk  W  .  .\n");
            try out.appendSlice(a, "Kolmogorov-Smirnov  D  .  .\nCramer-von Mises  W-Sq  .  .\nAnderson-Darling  A-Sq  .  .\n");
        }
    }
    for ([_]bool{ false, true }) |winsor| {
        const values = if (winsor) opt.winsor else opt.trim;
        const ci = if (winsor) opt.winsor_ci else opt.trim_ci;
        if (values.len == 0) continue;
        if (df) try heading(a, out, if (winsor) "Winsorized Means" else "Trimmed Means", ci, opt.alpha) else try out.appendSlice(a, if (winsor) "\nWinsorized Means\n" else "\nTrimmed Means\n");
        try out.appendSlice(a, if (df) "Percent in Tail  Number in Tail  Mean  Std Error  Lower  Upper  DF  t  Pr > |t|\n" else "Percent in Tail  Number in Tail  Mean\n");
        for (values) |amount| {
            if (amount == 0) continue; // SAS omits zero trimming requests.
            const n: f64 = @floatFromInt(x.len);
            const count = if (amount < 1) @ceil(amount * n) else amount;
            const pct = 100 * count / n;
            if (k.trimmed(x, amount, winsor, mu0, df, ci, opt.alpha)) |r| {
                if (df) try row(a, out, "", &.{ pct, @round(count), r.mean, r.se, r.limits.lower, r.limits.upper, r.df, r.t, r.p }) else try row(a, out, "", &.{ pct, @round(count), r.mean });
            } else {
                const missing = std.math.nan(f64);
                if (df) try row(a, out, "", &.{ pct, @round(count), missing, missing, missing, missing, missing, missing, missing }) else try row(a, out, "", &.{ pct, @round(count), missing });
            }
        }
    }
    if (opt.robustscale) {
        try out.appendSlice(a, "\nRobust Measures of Scale\nMeasure  Value  Estimate of Sigma\n");
        for ([_][]const u8{ "Interquartile Range", "Gini's Mean Difference", "MAD", "Sn", "Qn" }, [_][]const u8{ "qrange", "gini", "mad", "sn", "qn" }, [_][]const u8{ "std_qrange", "std_gini", "std_mad", "std_sn", "std_qn" }) |name, key, sigma| try row(a, out, name, &.{ z.value(key, def, .df, mu0), z.value(sigma, def, .df, mu0) });
    }
    for ([_]bool{ false, true }) |distribution_free| {
        const ci = (if (distribution_free) opt.df else opt.normal_ci) orelse continue;
        try heading(a, out, if (distribution_free) "Quantile Confidence Limits Distribution Free" else "Quantile Confidence Limits Assuming Normality", ci, opt.alpha);
        try out.appendSlice(a, if (distribution_free) "Percentile  Lower  Upper  LCL Rank  UCL Rank  Coverage\n" else "Percentile  Lower  Upper\n");
        for ([_]f64{ 99, 95, 90, 75, 50, 25, 10, 5, 1 }) |p| {
            const interval = if (distribution_free) k.distributionFree(x, p / 100, ci, opt.alpha) else k.normalQuantileCI(z.s.mean, z.s.std, z.s.n, p / 100, ci, opt.alpha);
            if (distribution_free) try row(a, out, "", &.{ p, interval.lower, interval.upper, if (interval.lower_rank == 0) std.math.nan(f64) else @floatFromInt(interval.lower_rank), if (interval.upper_rank == 0) std.math.nan(f64) else @floatFromInt(interval.upper_rank), 100 * interval.coverage }) else try row(a, out, "", &.{ p, interval.lower, interval.upper });
        }
    }
}
