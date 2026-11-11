//! EXACT listing renderers. Results and resource status are supplied by the
//! execution adapter; this module never computes tests or selects reference sets.
const std = @import("std");
const fmt = @import("../format.zig");
const parse = @import("freq_exact_parse.zig");
const dist = @import("freq_exact_distribution.zig");
const strata = @import("freq_exact_strata.zig");
const Error = dist.Error;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);

pub fn probability(a: A, value: ?f64, style: parse.ProbabilityFormat) Error![]const u8 {
    const p = value orelse return ".";
    if (!std.math.isFinite(p)) return ".";
    return switch (style) {
        .default => if (p < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{p}),
        .exact => std.mem.trim(u8, try fmt.apply(a, .{ .num = p }, if (p < 0.001 and p > 0) "e10.3" else "6.4"), " "),
        .named => |name| std.mem.trim(u8, try fmt.apply(a, .{ .num = p }, name), " "),
    };
}
fn line(a: A, out: *Out, label: []const u8, value: []const u8) Error!void {
    try out.appendSlice(a, label);
    try out.appendNTimes(a, ' ', @max(1, 34 -| label.len));
    try out.appendSlice(a, value);
    try out.append(a, '\n');
}
fn pLine(a: A, out: *Out, label: []const u8, value: ?f64, options: parse.Options) Error!void {
    try line(a, out, label, try probability(a, value, options.pformat));
}
fn nLine(a: A, out: *Out, label: []const u8, value: f64) Error!void {
    try line(a, out, label, if (std.math.isFinite(value)) try std.fmt.allocPrint(a, "{d:.4}", .{value}) else if (value == std.math.inf(f64)) "Infinity" else ".");
}

pub const Test = struct { statistic: ?f64 = null, probabilities: dist.Probabilities, directional: bool = false, right_sided: bool = false };
pub const Result = union(enum) { complete: Test, exhausted };
pub fn testResult(a: A, out: *Out, title: []const u8, result: Result, options: parse.Options) Error!void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n\n", .{title}));
    if (result == .exhausted) {
        try pLine(a, out, "Exact Pr >= Statistic", null, options);
        try out.appendSlice(a, "NOTE: Exact computation did not complete within the resource limit.\n");
        return;
    }
    const r = result.complete;
    if (r.statistic) |value| try nLine(a, out, "Statistic", value);
    if (r.directional) try pLine(a, out, if (r.right_sided) "One-sided Pr >= Statistic" else "One-sided Pr <= Statistic", r.probabilities.one_sided, options) else try pLine(a, out, "Exact Pr >= Statistic", r.probabilities.two_sided, options);
    if (options.point) try pLine(a, out, "Point Pr = Statistic", r.probabilities.point, options);
    if (options.midp) try pLine(a, out, "Mid p-Value", @max(0, (if (r.directional) r.probabilities.one_sided else r.probabilities.two_sided) - r.probabilities.point / 2), options);
    if (r.directional) try pLine(a, out, "Two-sided Pr >= |Statistic|", r.probabilities.two_sided, options);
}

pub const Fisher = struct { first_cell: ?u32 = null, table_probability: f64, left: ?f64 = null, right: ?f64 = null, p: f64, point: f64 };
pub fn fisher(a: A, out: *Out, r: Fisher, options: parse.Options) Error!void {
    try out.appendSlice(a, "\nFisher's Exact Test\n----------------------------------\n");
    if (r.first_cell) |cell| {
        try line(a, out, "Cell (1,1) Frequency (F)", try std.fmt.allocPrint(a, "{d}", .{cell}));
        try pLine(a, out, "Left-sided Pr <= F", r.left, options);
        try pLine(a, out, "Right-sided Pr >= F", r.right, options);
    }
    try pLine(a, out, "Table Probability (P)", r.table_probability, options);
    try pLine(a, out, if (r.first_cell != null) "Two-sided Pr <= P" else "Pr <= P", r.p, options);
    if (options.point) try pLine(a, out, "Point Pr = P", r.point, options);
    if (options.midp) try pLine(a, out, "Mid p-Value", @max(0, r.p - r.point / 2), options);
}

pub fn monteCarlo(a: A, out: *Out, title: []const u8, estimate: ?dist.Estimate, samples: u64, seed: u64, options: parse.Options) Error!void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\nMonte Carlo Estimate for the Exact Test\n\n", .{title}));
    try pLine(a, out, "Estimated p-Value", if (estimate) |v| v.p else null, options);
    const level = (1 - options.alpha) * 100;
    try pLine(a, out, try std.fmt.allocPrint(a, "{d}% Lower Conf Limit", .{level}), if (estimate) |v| v.lower else null, options);
    try pLine(a, out, try std.fmt.allocPrint(a, "{d}% Upper Conf Limit", .{level}), if (estimate) |v| v.upper else null, options);
    try line(a, out, "Number of Samples", try std.fmt.allocPrint(a, "{d}", .{samples}));
    try line(a, out, "Initial Seed", try std.fmt.allocPrint(a, "{d}", .{seed}));
    if (estimate == null) try out.appendSlice(a, "NOTE: Monte Carlo computation did not complete within the resource limit.\n");
}

pub fn commonOdds(a: A, out: *Out, r: strata.Common, alpha: f64, options: parse.Options) Error!void {
    try out.appendSlice(a, "\nCommon Odds Ratio\n\nExact Confidence Limits\n");
    try nLine(a, out, try std.fmt.allocPrint(a, "{d}% Lower Conf Limit", .{100 * (1 - alpha)}), r.limits.lower);
    try nLine(a, out, try std.fmt.allocPrint(a, "{d}% Upper Conf Limit", .{100 * (1 - alpha)}), r.limits.upper);
    try out.appendSlice(a, "\nExact Test of H0: Common Odds Ratio = 1\n\n");
    try nLine(a, out, "Cell (1,1) Sum (S)", @floatFromInt(r.observed));
    try nLine(a, out, "Mean of S under H0", r.expected);
    try pLine(a, out, if (@as(f64, @floatFromInt(r.observed)) > r.expected) "One-sided Pr >= S" else "One-sided Pr <= S", r.one_sided, options);
    if (options.point) try pLine(a, out, "Point Pr = S", r.point, options);
    if (options.midp) try pLine(a, out, "Mid p-Value", @max(0, r.one_sided - r.point / 2), options);
    try out.appendSlice(a, "\nTwo-sided P-values\n");
    try pLine(a, out, "2 * One-sided", r.two_doubled, options);
    try pLine(a, out, "Sum <= Point", r.two_probability, options);
    try pLine(a, out, "Pr >= |S - Mean|", r.two_distance, options);
}

test "Fisher rendering distinguishes observed mass from tied POINT and missing resource results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: Out = .empty;
    try fisher(a, &out, .{ .first_cell = 1, .table_probability = 0.00134607618791, .left = 0.00137972809261, .right = 0.9999663480953, .p = 0.00275945618522, .point = 0.00269215237582 }, .{ .point = true, .midp = true });
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.0013") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.0027") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.0014") != null);
    out.clearRetainingCapacity();
    try testResult(a, &out, "Exact Pearson", .exhausted, .{});
    try std.testing.expect(std.mem.indexOf(u8, out.items, "resource limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.0000") == null);
    try std.testing.expectEqualStrings("<.0001", try probability(a, 0.000001, .default));
    try std.testing.expectEqualStrings("0.123456", try probability(a, 0.123456, .{ .named = "8.6" }));
}

pub fn zelen(a: A, out: *Out, r: strata.Zelen, options: parse.Options) Error!void {
    try out.appendSlice(a, "\nZelen's Exact Test for Equal Odds Ratios\n\n");
    try pLine(a, out, "Zelen's Exact Test (P)", r.point, options);
    try pLine(a, out, "Exact Pr <= P", r.p, options);
}
