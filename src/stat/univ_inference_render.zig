//! UNIVARIATE inference listing tables; computations live in univ_inference.
const std = @import("std");
const k = @import("univ_inference.zig");
const Options = @import("univ_inference_parse.zig").Options;
const Summary = @import("univariate.zig").Summary;
const h = @import("../proc.zig").UnivariateHelpers;
const typed = @import("ods_univ_tests.zig");
const A = std.mem.Allocator;
fn num(a: A, x: f64) ![]const u8 {
    return if (std.math.isNan(x)) "." else std.fmt.allocPrint(a, "{d:.6}", .{x});
}
fn cells(a: A, out: *std.ArrayList(u8), name: []const u8, values: []const f64) !void {
    try out.appendSlice(a, name);
    for (values) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s}", .{try num(a, v)}));
}
fn row(a: A, out: *std.ArrayList(u8), name: []const u8, values: []const f64) !void {
    try cells(a, out, name, values);
    try out.append(a, '\n');
}
fn bounds(ci: k.CI, both: *const [2]f64) []const f64 {
    return switch (ci.side) {
        .lower => both[0..1],
        .upper => both[1..],
        else => both,
    };
}
fn boundLabels(ci: k.CI) []const u8 {
    return switch (ci.side) {
        .lower => "Lower",
        .upper => "Upper",
        else => "Lower  Upper",
    };
}
fn basicRow(a: A, out: *std.ArrayList(u8), name: []const u8, estimate: f64, ci: k.CI, lower: f64, upper: f64) !void {
    try cells(a, out, name, &.{estimate});
    try row(a, out, "", bounds(ci, &.{ lower, upper }));
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
pub fn render(a: A, out: *std.ArrayList(u8), z: Summary, df: bool, def: u8, mu0: f64, opt: Options, listing: @import("../ods_listing.zig").Tables, ods: ?@import("ods_univariate.zig").Context) !void {
    if (!opt.normal and !opt.robustscale and !opt.loccount and opt.basic == null and opt.df == null and opt.normal_ci == null and opt.trim.len == 0 and opt.winsor.len == 0) return;
    const x = try a.alloc(f64, z.pairs.len);
    defer a.free(x);
    for (z.pairs, 0..) |v, j| x[j] = v.x;
    if (opt.basic) |ci| {
        const start = out.items.len;
        try heading(a, out, "Basic Confidence Limits Assuming Normality", ci, opt.alpha);
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Parameter  Estimate  {s}\n", .{boundLabels(ci)}));
        const n: f64 = @floatFromInt(z.s.n);
        const mean = k.meanCI(z.s.mean, z.s.std / @sqrt(z.s.sumw), n - 1, ci, opt.alpha);
        const variance = k.varianceCI(z.s.css, n - 1, ci, opt.alpha);
        try basicRow(a, out, "Mean", z.s.mean, ci, mean.lower, mean.upper);
        try basicRow(a, out, "Std Deviation", z.s.std, ci, @sqrt(variance.lower), @sqrt(variance.upper));
        try basicRow(a, out, "Variance", z.s.std * z.s.std, ci, variance.lower, variance.upper);
        try typed.basic(ods, z.s.mean, z.s.std, mean, variance, ci, opt.alpha);
        try listing.finish(a, out, start, "BasicIntervals");
    }
    if (opt.loccount) {
        const start = out.items.len;
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
        try typed.counts(ods, positive, negative);
        try listing.finish(a, out, start, "LocationCounts");
    }
    if (opt.normal) {
        const start = out.items.len;
        try out.appendSlice(a, "\nTests for Normality\nTest  Statistic  p Value\n");
        const tests = try k.normalTests(a, x);
        const missing = std.math.nan(f64);
        const rows = [_]typed.NormalRow{
            .{ .name = "Shapiro-Wilk", .symbol = "W", .statistic = if (tests) |t| t.primary.statistic else missing, .p = if (tests) |t| t.primary.p else missing, .upper = 0 },
            .{ .name = "Kolmogorov-Smirnov", .symbol = "D", .statistic = if (tests) |t| t.d else missing, .p = if (tests) |t| t.pd else missing, .upper = 0.15 },
            .{ .name = "Cramer-von Mises", .symbol = "W-Sq", .statistic = if (tests) |t| t.w2 else missing, .p = if (tests) |t| t.pw2 else missing, .upper = 0.25 },
            .{ .name = "Anderson-Darling", .symbol = "A-Sq", .statistic = if (tests) |t| t.a2 else missing, .p = if (tests) |t| t.pa2 else missing, .upper = 0.25 },
        };
        const active = rows[@intFromBool(x.len > 2000)..];
        for (active) |r| {
            if (tests == null) {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}  {s}  .  .\n", .{ r.name, r.symbol }));
            } else try normalRow(a, out, r.name, r.symbol, r.statistic, r.p, r.upper);
        }
        try typed.normal(ods, active);
        try listing.finish(a, out, start, "TestsForNormality");
    }
    for ([_]bool{ false, true }) |winsor| {
        const start = out.items.len;
        const values = if (winsor) opt.winsor else opt.trim;
        const ci = if (winsor) opt.winsor_ci else opt.trim_ci;
        if (values.len == 0) continue;
        if (df) try heading(a, out, if (winsor) "Winsorized Means" else "Trimmed Means", ci, opt.alpha) else try out.appendSlice(a, if (winsor) "\nWinsorized Means\n" else "\nTrimmed Means\n");
        try out.appendSlice(a, if (df) try std.fmt.allocPrint(a, "Percent in Tail  Number in Tail  Mean  Std Error  {s}  DF  t  Pr > |t|\n", .{boundLabels(ci)}) else "Percent in Tail  Number in Tail  Mean\n");
        var captured: std.ArrayList(typed.TailRow) = .empty;
        for (values) |amount| {
            if (amount == 0) continue;
            const n: f64 = @floatFromInt(x.len);
            const count = if (amount < 1) @ceil(amount * n) else amount;
            const pct = 100 * count / n;
            const missing = std.math.nan(f64);
            const r = k.trimmed(x, amount, winsor, mu0, df, ci, opt.alpha) orelse k.Trim{ .k = 0, .mean = missing, .df = missing };
            if (df) {
                try cells(a, out, "", &.{ pct, count, r.mean, r.se });
                try cells(a, out, "", bounds(ci, &.{ r.limits.lower, r.limits.upper }));
                try cells(a, out, "", &.{ r.df, r.t });
                const pv = if (std.math.isNan(r.p)) "." else if (r.p < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{r.p});
                try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s}\n", .{pv}));
            } else try row(a, out, "", &.{ pct, count, r.mean });
            if (ods != null) try captured.append(a, .{ .percent = pct, .count = count, .mean = r.mean, .se = r.se, .lower = r.limits.lower, .upper = r.limits.upper, .df = r.df, .t = r.t, .p = r.p });
        }
        try typed.tailMeans(ods, winsor, df, ci, opt.alpha, captured.items);
        try listing.finish(a, out, start, if (winsor) "WinsorizedMeans" else "TrimmedMeans");
    }
    if (opt.robustscale) {
        const start = out.items.len;
        try out.appendSlice(a, "\nRobust Measures of Scale\nMeasure  Value  Estimate of Sigma\n");
        var estimates: [5]f64 = undefined;
        var sigmas: [5]f64 = undefined;
        for (typed.scale_names, [_][]const u8{ "qrange", "gini", "mad", "sn", "qn" }, [_][]const u8{ "std_qrange", "std_gini", "std_mad", "std_sn", "std_qn" }, 0..) |name, key, sigma, i| {
            estimates[i] = z.value(key, def, .df, mu0);
            sigmas[i] = z.value(sigma, def, .df, mu0);
            try row(a, out, name, &.{ estimates[i], sigmas[i] });
        }
        try typed.robust(ods, estimates, sigmas);
        try listing.finish(a, out, start, "RobustScale");
    }
    for ([_]bool{ false, true }) |distribution_free| {
        const start = out.items.len;
        const ci = (if (distribution_free) opt.df else opt.normal_ci) orelse continue;
        try heading(a, out, if (distribution_free) "Quantile Confidence Limits Distribution Free" else "Quantile Confidence Limits Assuming Normality", ci, opt.alpha);
        const rank_labels = if (!distribution_free) "" else switch (ci.side) {
            .lower => "  LCL Rank  Coverage",
            .upper => "  UCL Rank  Coverage",
            else => "  LCL Rank  UCL Rank  Coverage",
        };
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Percentile  {s}{s}\n", .{ boundLabels(ci), rank_labels }));
        for ([_]f64{ 99, 95, 90, 75, 50, 25, 10, 5, 1 }) |p| {
            const interval = if (distribution_free) k.distributionFree(x, p / 100, ci, opt.alpha) else k.normalQuantileCI(z.s.mean, z.s.std, z.s.n, p / 100, ci, opt.alpha);
            try cells(a, out, "", &.{p});
            try cells(a, out, "", bounds(ci, &.{ interval.lower, interval.upper }));
            if (distribution_free) {
                const lower_rank: f64 = if (interval.lower_rank == 0) std.math.nan(f64) else @floatFromInt(interval.lower_rank);
                const upper_rank: f64 = if (interval.upper_rank == 0) std.math.nan(f64) else @floatFromInt(interval.upper_rank);
                try cells(a, out, "", bounds(ci, &.{ lower_rank, upper_rank }));
                try cells(a, out, "", &.{100 * interval.coverage});
            }
            try out.append(a, '\n');
        }
        try listing.section(a, out, start, "Quantiles", false);
    }
}
