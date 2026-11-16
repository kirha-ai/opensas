//! Common structured-table builder for ODS producers.
const std = @import("std");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
pub const Builder = struct {
    ds: Dataset,
    prefix: []const Value,
    pub fn init(a: std.mem.Allocator, source: *const Dataset, cols: []const usize, rep: ?[]const Value) !Builder {
        var b = Builder{ .ds = Dataset.init(a, ""), .prefix = &.{} };
        const cells = try a.alloc(Value, cols.len);
        for (cols, 0..) |ci, i| {
            const c = source.columns.items[ci];
            _ = try b.ds.addColumnLike(c.name, c);
            cells[i] = if (rep) |representative| representative[ci] else if (c.type == .num) Value.missing else .{ .str = "" };
        }
        b.prefix = cells;
        return b;
    }
    pub fn char(self: *Builder, name: []const u8, len: usize) !void {
        _ = try self.ds.addColumn(name, .char);
        self.ds.setLen(name, @max(1, len));
    }
    pub fn num(self: *Builder, name: []const u8, fmt: ?[]const u8) !void {
        _ = try self.ds.addColumn(name, .num);
        self.ds.setLen(name, 8);
        if (fmt) |f| self.ds.setFormat(name, f);
    }
    pub fn row(self: *Builder, values: []const Value) !void {
        const cells = try self.ds.arena.alloc(Value, self.prefix.len + values.len);
        @memcpy(cells[0..self.prefix.len], self.prefix);
        @memcpy(cells[self.prefix.len..], values);
        try self.ds.appendRow(cells);
    }
};
pub fn n(x: f64) Value {
    return .{ .num = x };
}
pub fn s(x: []const u8) Value {
    return .{ .str = x };
}
