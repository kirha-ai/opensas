//! Listing of typed risk reports. No inference, parsing, or dataset access.
const std = @import("std");
const Error = @import("../diag.zig").Error;
pub const Row = struct { label: []const u8, values: [5]?f64 = .{ null, null, null, null, null }, probability: [5]bool = .{ false, false, false, false, false } };
pub const Section = struct { title: []const u8, subtitle: []const u8 = "", columns: []const []const u8, rows: []const Row, note: []const u8 = "" };
pub const Report = struct { sections: []const Section = &.{}, sample_size: ?f64 = null };
fn pad(a: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8, width: usize, right: bool) Error!void {
    const n = width - @min(width, s.len);
    if (right) try out.appendNTimes(a, ' ', n);
    try out.appendSlice(a, s);
    if (!right) try out.appendNTimes(a, ' ', n);
}
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), report: Report) Error!void {
    for (report.sections) |section| {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\n", .{section.title}));
        if (section.subtitle.len > 0) try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\n", .{section.subtitle}));
        try out.append(a, '\n');
        var label_width: usize = 28;
        for (section.rows) |row| label_width = @max(label_width, row.label.len + 2);
        if (section.columns.len > 1) {
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
}
