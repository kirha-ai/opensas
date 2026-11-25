//! Listing of typed risk reports. No inference, parsing, or dataset access.
const std = @import("std");
const Error = @import("../diag.zig").Error;
pub const Row = struct { label: []const u8, values: [5]?f64 = .{ null, null, null, null, null }, probability: [5]bool = .{ false, false, false, false, false } };
pub const Section = struct { title: []const u8, subtitle: []const u8 = "", columns: []const []const u8, rows: []const Row, note: []const u8 = "", confidence_label: ?[]const u8 = null };
pub const RiskColumn = struct {
    estimates: [4]@import("freq_risk.zig").Estimate,
    binomial_limits: [3]?@import("freq_risk.zig").Interval = @splat(null),
};
const inference = @import("freq_risk_inference.zig");
pub const BinomialAnalysis = struct { name: []const u8, null_value: f64, variance: inference.Variance, hypothesis: inference.Hypothesis, result: inference.Analysis, fallback: Section };
pub const Binomial = struct { event: []const u8, estimate: @import("freq_risk.zig").Estimate, alpha: f64, explicit_limits: bool, limits: []const Row, analyses: []const BinomialAnalysis };
pub const Report = struct { sections: []const Section = &.{}, sample_size: ?f64 = null, risk_columns: [2]?RiskColumn = @splat(null), binomial: ?Binomial = null };
pub fn confidence(a: std.mem.Allocator, alpha: f64) Error![]const u8 {
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = 100 * (1 - alpha) }, "best12."), " ");
}
fn pad(a: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8, width: usize, right: bool) Error!void {
    const n = width - @min(width, s.len);
    if (right) try out.appendNTimes(a, ' ', n);
    try out.appendSlice(a, s);
    if (!right) try out.appendNTimes(a, ' ', n);
}
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), report: Report) Error!void {
    if (report.binomial) |bin| return renderBinomial(a, out, bin);
    for (report.sections) |section| try renderSection(a, out, section);
}
fn renderSection(a: std.mem.Allocator, out: *std.ArrayList(u8), section: Section) Error!void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n", .{section.title}));
    if (section.subtitle.len > 0) try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\n", .{section.subtitle}));
    try out.append(a, '\n');
    var label_width: usize = 28;
    for (section.rows) |row| label_width = @max(label_width, row.label.len + 2);
    if (section.confidence_label) |label| {
        try pad(a, out, "Statistic", label_width, false);
        try pad(a, out, "Value", 12, true);
        try pad(a, out, label, 28, true);
        try out.appendSlice(a, "\n------------------------------------------------------------------\n");
    } else if (section.columns.len > 1) {
        try pad(a, out, "Statistic / Method", label_width, false);
        for (section.columns) |column| try pad(a, out, column, @max(12, column.len + 2), true);
        try out.append(a, '\n');
    }
    for (section.rows) |row| {
        try pad(a, out, row.label, label_width, false);
        for (section.columns, 0..) |column, i| {
            const s = if (row.values[i]) |v| (if (std.math.isNan(v)) "." else if (std.math.isInf(v)) "Infinity" else if (row.probability[i] and v < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{v})) else ".";
            try pad(a, out, s, @max(12, column.len + 2), true);
        }
        try out.append(a, '\n');
    }
    if (section.note.len > 0) try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n", .{section.note}));
}

fn number(a: std.mem.Allocator, value: ?f64, probability: bool) Error![]const u8 {
    const v = value orelse return ".";
    if (std.math.isNan(v)) return ".";
    if (std.math.isInf(v)) return "Infinity";
    return if (probability and v < 0.0001) "<.0001" else std.fmt.allocPrint(a, "{d:.4}", .{v});
}
fn pair(a: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, value: ?f64, probability: bool) Error!void {
    try pad(a, out, label, 26, false);
    try pad(a, out, try number(a, value, probability), 12, true);
    try out.append(a, '\n');
}
fn renderBinomial(a: std.mem.Allocator, out: *std.ArrayList(u8), bin: Binomial) Error!void {
    const level = try confidence(a, bin.alpha);
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\nBinomial Proportion\n{s}\n\n", .{bin.event}));
    try pair(a, out, "Proportion", bin.estimate.estimate, false);
    try pair(a, out, "ASE", bin.estimate.se, false);
    if (!bin.explicit_limits) {
        try pair(a, out, try std.fmt.allocPrint(a, "{s}% Lower Conf Limit", .{level}), bin.estimate.limits.lower, false);
        try pair(a, out, try std.fmt.allocPrint(a, "{s}% Upper Conf Limit", .{level}), bin.estimate.limits.upper, false);
        if (bin.limits.len > 0) {
            try out.appendSlice(a, "\nExact Conf Limits\n");
            try pair(a, out, try std.fmt.allocPrint(a, "{s}% Lower Conf Limit", .{level}), bin.limits[0].values[0], false);
            try pair(a, out, try std.fmt.allocPrint(a, "{s}% Upper Conf Limit", .{level}), bin.limits[0].values[1], false);
        }
    } else if (bin.limits.len > 0) {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nConfidence Limits for the Binomial Proportion\nProportion = {s}\n\nType                       {s}% Confidence Limits\n", .{ try number(a, bin.estimate.estimate, false), level }));
        for (bin.limits) |row| {
            try pad(a, out, row.label, 27, false);
            try pad(a, out, try number(a, row.values[0], false), 12, true);
            try pad(a, out, try number(a, row.values[1], false), 14, true);
            try out.append(a, '\n');
        }
    }
    for (bin.analyses) |analysis| {
        const result = analysis.result;
        const p0 = try @import("../format.zig").bestNumW(a, analysis.null_value, 12);
        if (analysis.hypothesis == .equality) {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nTest of H0: Proportion = {s}\n\n", .{p0}));
            try pair(a, out, if (analysis.variance == .null_value) "ASE under H0" else "ASE (Sample)", result.lower.se, false);
            try pair(a, out, "Z", result.lower.z, false);
            const right = (result.lower.z orelse 0) > 0;
            try pair(a, out, if (right) "One-sided Pr >  Z" else "One-sided Pr <  Z", if (right) result.lower.right else result.lower.left, true);
            try pair(a, out, "Two-sided Pr > |Z|", result.p, true);
        } else if (analysis.hypothesis == .equivalence and analysis.variance == .sample) {
            const bounds = analysis.hypothesis.equivalence;
            const format = @import("../format.zig");
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nEquivalence Analysis\n\nH0: P - p0 <= Lower Margin or >= Upper Margin\nHa: Lower Margin < P - p0 < Upper Margin\n\np0 = {s}   Lower Margin = {s}   Upper Margin = {s}\n\nProportion    ASE (Sample)\n\n", .{ p0, try format.bestNumW(a, bounds.lower - analysis.null_value, 12), try format.bestNumW(a, bounds.upper - analysis.null_value, 12) }));
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}  {s}\n\nTwo One-Sided Tests (TOST)\n\nTest                   Z        P-Value\n\n", .{ try number(a, bin.estimate.estimate, false), try number(a, result.lower.se, false) }));
            try out.appendSlice(a, try std.fmt.allocPrint(a, "Lower Margin {s} Pr > Z {s}\nUpper Margin {s} Pr < Z {s}\nOverall {s}\n", .{ try number(a, result.lower.z, false), try number(a, result.lower.right, true), try number(a, result.upper.?.z, false), try number(a, result.upper.?.left, true), try number(a, result.p, true) }));
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nEquivalence Limits    {s}% Confidence Limits\n\n{s} {s} {s} {s}\n", .{ try confidence(a, 2 * bin.alpha), try number(a, bounds.lower, false), try number(a, bounds.upper, false), try number(a, result.limits.lower, false), try number(a, result.limits.upper, false) }));
        } else {
            try renderSection(a, out, analysis.fallback);
            continue;
        }
        if (analysis.fallback.note.len > 0) try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n", .{analysis.fallback.note}));
    }
}
