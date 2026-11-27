//! Native listing for REG MTEST; computations live in reg_mtest.zig.
const std = @import("std");
const mtest = @import("reg_mtest.zig");
const A = std.mem.Allocator;
fn formatted(a: A, value: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, spec), " ");
}
fn probability(a: A, value: f64) ![]const u8 {
    if (value < 0.0001) return "<.0001";
    return std.fmt.allocPrint(a, "{d:.4}", .{value});
}
pub fn render(a: A, out: *std.ArrayList(u8), model_label: []const u8, spec: mtest.Spec, result: mtest.Result) !void {
    try out.print(a, "\nThe REG Procedure\nModel: {s}\n", .{model_label});
    if (spec.label) |label| try out.print(a, "Multivariate Test: {s}\n", .{label}) else try out.print(a, "Multivariate Test {d}\n", .{spec.number});
    if (spec.print) {
        for ([_][]const u8{ "Error Matrix (E)", "Hypothesis Matrix (H)" }, [_][]const f64{ result.error_matrix, result.hypothesis }) |name, matrix| {
            try out.print(a, "\n{s}\n\n", .{name});
            for (0..result.p) |i| {
                for (0..result.p) |j| {
                    if (j > 0) try out.append(a, ' ');
                    try out.appendSlice(a, try formatted(a, matrix[i * result.p + j], "best12."));
                }
                try out.append(a, '\n');
            }
        }
    }
    try out.print(a, "\nMultivariate Statistics and {s}\n\nS={d} M={d} N={d}\n\nStatistic Value F Value Num DF Den DF Pr > F\n\n", .{ if (result.s == 1) @as([]const u8, "Exact F Statistics") else "F Approximations", result.s, result.m, result.n });
    for ([_][]const u8{ "Wilks' Lambda", "Pillai's Trace", "Hotelling-Lawley Trace", "Roy's Greatest Root" }, result.statistics) |name, row| {
        try out.print(a, "{s} {d:.8} {d:.2} {s} {s} {s}\n", .{ name, row.value, row.f, try formatted(a, row.numerator_df, "best6."), try formatted(a, row.denominator_df, "best6."), try probability(a, row.probability) });
    }
    if (result.s > 1) {
        try out.appendSlice(a, "\nNOTE: F Statistic for Roy's Greatest Root is an upper bound.\n");
        if (result.s <= 2) try out.appendSlice(a, "NOTE: F Statistic for Wilks' Lambda is exact.\n");
    }
}
