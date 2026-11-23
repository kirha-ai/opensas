//! Long-form FREQ ODS tables retain the unformatted numeric statistic and its
//! independently formatted display string. M9 sizes character columns per table.
const std = @import("std");
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const parse = @import("freq_exact_parse.zig");
const fmt = @import("../format.zig");
pub fn probabilityFormat(a: std.mem.Allocator, style: parse.ProbabilityFormat) ![]const u8 {
    return switch (style) {
        .default, .exact => "PVALUE6.4",
        .named => |name| if (fmt.parseSpec(name).name.len == 0) try std.fmt.allocPrint(a, "F{s}", .{name}) else try std.ascii.allocUpperString(a, name),
    };
}

pub fn tableName(a: std.mem.Allocator, tab: *const @import("freq_table.zig").Table, number: usize) ![]const u8 {
    const dimensions = tab.dimensions;
    const last = dimensions[dimensions.len - 1].name;
    if (dimensions.len == 1) return std.fmt.allocPrint(a, "Table {s}", .{last});
    const row = dimensions[dimensions.len - 2].name;
    if (dimensions.len == 2) return std.fmt.allocPrint(a, "Table {s} * {s}", .{ row, last });
    return std.fmt.allocPrint(a, "Table {d} of {s} * {s}", .{ number, row, last });
}

pub const Rows = struct {
    a: std.mem.Allocator,
    builder: *b.Builder,
    title: []const u8,
    style: parse.ProbabilityFormat,
    lengths: [3]usize,

    pub fn init(a: std.mem.Allocator, t: *b.Builder, title: []const u8, style: parse.ProbabilityFormat, min_display: usize) !Rows {
        try t.char("Name1", 1);
        try t.char("Label1", 1);
        try t.char("cValue1", min_display);
        try t.num("nValue1", "D12.3");
        return .{ .a = a, .builder = t, .title = title, .style = style, .lengths = .{ 1, 1, min_display } };
    }
    pub fn add(self: *Rows, name: []const u8, label: []const u8, display: []const u8, value: ?f64) !void {
        for (&self.lengths, [_][]const u8{ name, label, display }) |*width, text| width.* = @max(width.*, text.len);
        try self.builder.row(&.{ b.s(self.title), b.s(name), b.s(label), b.s(display), if (value) |x| b.n(x) else Value.missing });
    }
    pub fn probability(self: *Rows, name: []const u8, label: []const u8, p: f64) !void {
        try self.add(name, label, try @import("freq_exact_render.zig").probability(self.a, p, self.style), p);
    }
    pub fn number(self: *Rows, name: []const u8, label: []const u8, x: f64, format: []const u8) !void {
        try self.add(name, label, std.mem.trim(u8, try fmt.apply(self.a, b.n(x), format), " "), x);
    }
    pub fn integer(self: *Rows, name: []const u8, label: []const u8, n: u64) !void {
        try self.add(name, label, try std.fmt.allocPrint(self.a, "{d}", .{n}), @floatFromInt(n));
    }
    pub fn finish(self: *Rows) void {
        for ([_][]const u8{ "Name1", "Label1", "cValue1" }, self.lengths) |name, length| self.builder.ds.setLen(name, length);
    }
};
