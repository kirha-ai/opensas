//! POWER listing fields preserve supplied/default order and Cartesian rows.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const engine = @import("power.zig");
const Scenario = engine.Scenario;
const Result = engine.Result;
const lists = @import("power_lists.zig");
fn fixed(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Scenario, result: Result, varying: [lists.dimension_count]bool) diag.Error!void {
    const n = result.sample_size;
    try out.appendSlice(cx.arena, "The POWER Procedure\n");
    try out.appendSlice(cx.arena, if (s.kind == .one_sample) "One-Sample t Test for Mean\n" else "Two-Sample t Test for Mean Difference\n");
    try out.appendSlice(cx.arena, "\nFixed Scenario Elements\n\nDistribution Normal\nMethod Exact\n");
    const mean_label = if (s.kind == .one_sample) "Mean" else "Mean Difference";
    const null_label = if (s.kind == .one_sample) "Null Mean" else "Null Difference";
    // Fixed elements list supplied parameters before defaults, each in the
    // documented internal order (S154 physical pp.7824 and 7855).
    if (s.sides_explicit and !varying[@intFromEnum(lists.Dimension.sides)]) try out.appendSlice(cx.arena, "Number of Sides 2\n");
    if (s.null_explicit and !varying[@intFromEnum(lists.Dimension.null_value)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ null_label, s.null_difference }));
    if (s.alpha_explicit and !varying[@intFromEnum(lists.Dimension.alpha)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Alpha {d}\n", .{s.alpha}));
    if (!varying[@intFromEnum(lists.Dimension.effect)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ mean_label, s.difference.? }));
    if (!varying[@intFromEnum(lists.Dimension.sigma)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Standard Deviation {d}\n", .{s.sigma.?}));
    if (!(if (s.n == null) varying[@intFromEnum(lists.Dimension.power)] else varying[@intFromEnum(lists.Dimension.n)])) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ if (s.n == null) "Nominal Power" else "Total Sample Size", if (s.n == null) s.power.? else n }));
    if (!s.sides_explicit and !varying[@intFromEnum(lists.Dimension.sides)]) try out.appendSlice(cx.arena, "Number of Sides 2\n");
    if (!s.null_explicit and !varying[@intFromEnum(lists.Dimension.null_value)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ null_label, s.null_difference }));
    if (!s.alpha_explicit and !varying[@intFromEnum(lists.Dimension.alpha)]) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Alpha {d}\n", .{s.alpha}));
    if (s.kind == .two_sample) try out.appendSlice(cx.arena, "Group 1 Weight 1\nGroup 2 Weight 1\n");
    try out.appendSlice(cx.arena, "\n");
}

pub fn scalar(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Scenario, result: Result) diag.Error!void {
    try fixed(cx, out, s, result, .{false} ** lists.dimension_count);
    const n = result.sample_size;
    const power = result.power;
    if (s.n == null) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed N Total\n\nActual N\nPower Total\n\n{d:.3} {d:.0}\n\n", .{ power, n })) else try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed Power\n\nPower\n\n{d:.3}\n", .{power}));
}

fn precision(values: []const ?f64) usize {
    var scale: f64 = 1;
    for (0..7) |digits| {
        var fits = true;
        for (values) |optional| if (optional) |x| {
            if (@abs(@round(x * scale) / scale - x) > 8 * std.math.floatEps(f64) * @abs(x)) fits = false;
        };
        if (fits) return digits;
        scale *= 10;
    }
    return 7;
}
fn numeric(a: std.mem.Allocator, x: ?f64, digits: usize) ![]const u8 {
    const v = x orelse return ".";
    return switch (digits) {
        0 => std.fmt.allocPrint(a, "{d:.0}", .{v}),
        1 => std.fmt.allocPrint(a, "{d:.1}", .{v}),
        2 => std.fmt.allocPrint(a, "{d:.2}", .{v}),
        3 => std.fmt.allocPrint(a, "{d:.3}", .{v}),
        4 => std.fmt.allocPrint(a, "{d:.4}", .{v}),
        5 => std.fmt.allocPrint(a, "{d:.5}", .{v}),
        6 => std.fmt.allocPrint(a, "{d:.6}", .{v}),
        else => std.fmt.allocPrint(a, "{d}", .{v}),
    };
}
pub fn scenarios(cx: proc.ProcCtx, out: *std.ArrayList(u8), rows: []const Scenario, results: []const Result, grid: lists.Grid) diag.Error!void {
    const varying = grid.varying();
    const s = rows[0];
    try fixed(cx, out, s, results[0], varying);
    try out.appendSlice(cx.arena, if (s.n == null) "Computed N Total\n\n" else "Computed Power\n\n");
    const upper = [lists.dimension_count][]const u8{ "Number", "Null", "", if (s.kind == .one_sample) "" else "Mean", "Std", "N", "Nominal" };
    const lower = [lists.dimension_count][]const u8{ "Sides", if (s.kind == .one_sample) "Mean" else "Diff", "Alpha", if (s.kind == .one_sample) "Mean" else "Diff", "Dev", "Total", "Power" };
    for (varying, 0..) |include, j| if (include and upper[j].len > 0) {
        try out.appendSlice(cx.arena, upper[j]);
        try out.appendSlice(cx.arena, " ");
    };
    if (s.n == null) try out.appendSlice(cx.arena, "Actual N");
    try out.appendSlice(cx.arena, "\nIndex ");
    for (varying, 0..) |include, j| if (include) {
        try out.appendSlice(cx.arena, lower[j]);
        try out.appendSlice(cx.arena, " ");
    };
    try out.appendSlice(cx.arena, if (s.n == null) "Power Total\n\n" else "Power\n\n");
    var digits: [lists.dimension_count]usize = undefined;
    for (grid.axes, 0..) |axis, j| digits[j] = precision(axis);
    for (results, 0..) |result, index| {
        try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{d} ", .{index + 1}));
        const row = grid.row(index);
        for (varying, 0..) |include, j| if (include) {
            try out.appendSlice(cx.arena, try numeric(cx.arena, row[j], digits[j]));
            try out.appendSlice(cx.arena, " ");
        };
        try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{d:.3}", .{result.power}));
        if (s.n == null) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, " {d:.0}", .{result.sample_size}));
        try out.appendSlice(cx.arena, "\n");
    }
    try out.appendSlice(cx.arena, "\n");
}

test "STAT-POWER-008 numeric column precision preserves decimal scenario values" {
    const t = std.testing;
    try t.expectEqual(@as(usize, 1), precision(&.{ 1, 1.5, 2 }));
    try t.expectEqual(@as(usize, 0), precision(&.{ 30, 50, 70, 100 }));
    const text = try numeric(t.allocator, 1, precision(&.{ 1, 1.5, 2 }));
    defer t.allocator.free(text);
    try t.expectEqualStrings("1.0", text);
}

test "STAT-POWER-008 tiny signed scenario values survive mixed zero columns" {
    const t = std.testing;
    const values = [_]?f64{ 0, 1e-20, -1e-20 };
    const digits = precision(&values);
    try t.expectEqual(@as(usize, 7), digits);
    for (values) |value| {
        const text = try numeric(t.allocator, value, digits);
        defer t.allocator.free(text);
        const restored = try std.fmt.parseFloat(f64, text);
        try t.expectEqual(value.?, restored);
        if (value.? != 0) try t.expect(restored != 0);
    }
}
