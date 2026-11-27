//! TTEST listing from computed results; no numerical fitting in this module.
const std = @import("std");
const format = @import("../format.zig");
const options = @import("ttest_parse.zig");
const A = std.mem.Allocator;
const nan = std.math.nan(f64);

pub const Sample = struct {
    n: f64,
    mean: f64,
    stddev: f64,
    stderr: f64,
    minimum: f64 = nan,
    maximum: f64 = nan,
    lower: f64,
    upper: f64,
    std_lower: f64,
    std_upper: f64,
    df: f64,
    t: f64,
    p: f64,
};

fn num(a: A, x: f64, spec: []const u8) ![]const u8 {
    if (std.math.isInf(x)) return if (x < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}
pub fn statistics(a: A, out: *std.ArrayList(u8), s: Sample, summary: bool) !void {
    try out.appendSlice(a, "N Mean Std Dev Std Err");
    if (!summary) try out.appendSlice(a, " Minimum Maximum");
    try out.print(a, "\n{s} {s} {s} {s}", .{ try num(a, s.n, "best12."), try num(a, s.mean, "d8.3"), try num(a, s.stddev, "d8.3"), try num(a, s.stderr, "d8.3") });
    if (!summary) try out.print(a, " {s} {s}", .{ try num(a, s.minimum, "d8.3"), try num(a, s.maximum, "d8.3") });
    try out.appendSlice(a, "\n\n");
}
pub fn intervals(a: A, out: *std.ArrayList(u8), s: Sample, opts: options.Options) !void {
    const level = try num(a, 100 * (1 - opts.alpha), "best8.");
    try out.print(a, "Mean {s}% CL Mean Std Dev", .{level});
    if (opts.ci) try out.print(a, " {s}% CL Std Dev", .{level});
    try out.print(a, "\n{s} {s} {s} {s}", .{ try num(a, s.mean, "d8.3"), try num(a, s.lower, "d8.3"), try num(a, s.upper, "d8.3"), try num(a, s.stddev, "d8.3") });
    if (opts.ci) try out.print(a, " {s} {s}", .{ try num(a, s.std_lower, "d8.3"), try num(a, s.std_upper, "d8.3") });
    try out.appendSlice(a, "\n\n");
}
pub fn tests(a: A, out: *std.ArrayList(u8), s: Sample, opts: options.Options) !void {
    const tail: []const u8 = switch (opts.sides) {
        .two => "Pr > |t|",
        .upper => "Pr > t",
        .lower => "Pr < t",
    };
    try out.print(a, "DF t Value {s}\n{s} {s} {s}\n\n", .{ tail, try num(a, s.df, "best8."), try num(a, s.t, "8.2"), try num(a, s.p, "pvalue6.4") });
}

test "STAT-TTEST-001 SAS D8.3 display and one-sided unbounded intervals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("116.0", try num(a, 116, "d8.3"));
    try std.testing.expectEqualStrings("43.0000", try num(a, 43, "d8.3"));
    try std.testing.expectEqualStrings("<.0001", try num(a, 0.000001, "pvalue6.4"));
    try std.testing.expectEqualStrings("Infty", try num(a, std.math.inf(f64), "d8.3"));
    try std.testing.expectEqualStrings("-Infty", try num(a, -std.math.inf(f64), "d8.3"));
}
