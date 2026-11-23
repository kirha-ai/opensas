//! Typed UNIVARIATE inference objects, populated from the same estimates as LISTING.
const std = @import("std");
const u = @import("ods_univariate.zig");
const b = @import("ods_table.zig");
const fmt = @import("ods_univ_formats.zig");
const inference = @import("univ_inference.zig");

pub fn counts(ctx: ?u.Context, positive: f64, negative: f64) !void {
    var t = (try u.Context.start(ctx, "LocationCounts", "Location Counts")) orelse return;
    try t.char("Count", 14, "");
    try t.num("Value", "8.", "Value of Count");
    for ([_][]const u8{ "Num Obs > Mu0", "Num Obs ^= Mu0", "Num Obs < Mu0" }, [_]f64{ positive, positive + negative, negative }) |name, value|
        try t.row(&.{ b.s(name), b.n(value) });
    try t.finish();
}

pub const scale_names = [_][]const u8{ "Interquartile Range", "Gini's Mean Difference", "MAD", "Sn", "Qn" };
pub fn robust(ctx: ?u.Context, estimates: [5]f64, sigmas: [5]f64) !void {
    var t = (try u.Context.start(ctx, "RobustScale", "Robust Measures of Scale")) orelse return;
    const a = t.builder.ds.arena;
    try t.char("Measure", 22, "Robust Measure of Scale");
    try t.num("Value", try fmt.statistic(a, &estimates), "Value of Robust Measure of Scale");
    try t.num("Sigma", try fmt.statistic(a, &sigmas), "Estimate of Sigma");
    for (scale_names, estimates, sigmas) |name, value, sigma| try t.row(&.{ b.s(name), b.n(value), b.n(sigma) });
    try t.finish();
}

pub const NormalRow = struct {
    name: []const u8,
    symbol: []const u8,
    statistic: f64,
    p: f64,
    upper: f64,
    pub fn sign(r: NormalRow) []const u8 {
        if (r.upper == 0) return "";
        if (r.p == r.upper) return ">";
        if (r.p == (if (r.upper == 0.15) @as(f64, 0.01) else 0.005)) return "<";
        return "";
    }
};
pub fn normal(ctx: ?u.Context, rows: []const NormalRow) !void {
    var t = (try u.Context.start(ctx, "TestsForNormality", "Tests for Normality")) orelse return;
    try t.char("Test", 18, "Goodness-of-Fit Test");
    try t.char("TestLab", 4, "Label for Goodness-of-Fit Statistic");
    try t.num("Stat", "BEST8.", "Value of Goodness-of-Fit Statistic");
    try t.char("pType", 9, "p-value Label");
    try t.char("pSign", 1, "Sign of p-value");
    try t.num("pValue", "PVALUE6.4", "p-value");
    for (rows) |r| {
        const desc = try std.fmt.allocPrint(t.builder.ds.arena, "Pr {s} {s}", .{ if (r.upper == 0) @as([]const u8, "<") else ">", r.symbol });
        try t.row(&.{ b.s(r.name), b.s(r.symbol), b.n(r.statistic), b.s(desc), b.s(r.sign()), b.n(r.p) });
    }
    try t.finish();
}

pub fn basic(ctx: ?u.Context, mean: f64, deviation: f64, mean_ci: inference.Interval, var_ci: inference.Interval, ci: inference.CI, alpha: f64) !void {
    var t = (try u.Context.start(ctx, "BasicIntervals", "Basic Confidence Limits Assuming Normality")) orelse return;
    const a = t.builder.ds.arena;
    const level = 100 * (1 - (ci.alpha orelse alpha));
    try t.char("Parameter", 13, "");
    try t.num("Estimate", "D10.", "");
    if (ci.side != .upper) try t.num("LowerCL", "D10.", try std.fmt.allocPrint(a, "Lower {d}% Confidence Limit", .{level}));
    if (ci.side != .lower) try t.num("UpperCL", "D10.", try std.fmt.allocPrint(a, "Upper {d}% Confidence Limit", .{level}));
    for ([_][]const u8{ "Mean", "Std Deviation", "Variance" }, [_]f64{ mean, deviation, deviation * deviation }, [_]f64{ mean_ci.lower, @sqrt(var_ci.lower), var_ci.lower }, [_]f64{ mean_ci.upper, @sqrt(var_ci.upper), var_ci.upper }) |name, value, lower, upper| {
        var cells = [_]@import("../value.zig").Value{ b.s(name), b.n(value), b.n(lower), b.n(upper) };
        if (ci.side == .upper) cells[2] = b.n(upper);
        try t.row(cells[0..if (ci.side != .lower and ci.side != .upper) @as(usize, 4) else 3]);
    }
    try t.finish();
}

pub const TailRow = struct {
    percent: f64,
    count: f64,
    mean: f64,
    se: f64,
    lower: f64,
    upper: f64,
    df: f64,
    t: f64,
    p: f64,
};
fn tailFormat(a: std.mem.Allocator, rows: []const TailRow, comptime field: []const u8) ![]const u8 {
    const values = try a.alloc(f64, rows.len);
    for (rows, values) |r, *v| v.* = @field(r, field);
    return fmt.statistic(a, values);
}
pub fn tailMeans(ctx: ?u.Context, winsor: bool, df: bool, ci: inference.CI, alpha: f64, rows: []const TailRow) !void {
    if (rows.len == 0) return;
    const kind = if (winsor) @as([]const u8, "Winsorized") else "Trimmed";
    var t = (try u.Context.start(ctx, if (winsor) "WinsorizedMeans" else "TrimmedMeans", if (winsor) "Winsorized Means" else "Trimmed Means")) orelse return;
    const a = t.builder.ds.arena;
    const level = 100 * (1 - (ci.alpha orelse alpha));
    try t.num("HalfP", "6.2", try std.fmt.allocPrint(a, "Percent {s} in Tail", .{kind}));
    try t.num("HalfN", "6.", try std.fmt.allocPrint(a, "Number {s} in Tail", .{kind}));
    try t.num("Mean", try tailFormat(a, rows, "mean"), try std.fmt.allocPrint(a, "{s} Mean", .{kind}));
    if (df) {
        try t.num("StdMean", try tailFormat(a, rows, "se"), try std.fmt.allocPrint(a, "Std Error of {s} Mean", .{kind}));
        if (ci.side != .upper) try t.num("LCLMean", try tailFormat(a, rows, "lower"), try std.fmt.allocPrint(a, "Lower {d}% Confidence Limit for Mean", .{level}));
        if (ci.side != .lower) try t.num("UCLMean", try tailFormat(a, rows, "upper"), try std.fmt.allocPrint(a, "Upper {d}% Confidence Limit for Mean", .{level}));
        try t.num("DF", "6.", "Degrees of Freedom");
        try t.num("tValue", try tailFormat(a, rows, "t"), "t Value");
        try t.num("Probt", "PVALUE6.4", "Pr > |t|");
    }
    for (rows) |r| {
        var cells: std.ArrayList(@import("../value.zig").Value) = .empty;
        try cells.appendSlice(a, &.{ b.n(r.percent), b.n(r.count), b.n(r.mean) });
        if (df) {
            try cells.append(a, b.n(r.se));
            if (ci.side != .upper) try cells.append(a, b.n(r.lower));
            if (ci.side != .lower) try cells.append(a, b.n(r.upper));
            try cells.appendSlice(a, &.{ b.n(r.df), b.n(r.t), b.n(r.p) });
        }
        try t.row(cells.items);
    }
    try t.finish();
}
