//! Finite statistical graph coordinates and roundtrip-readable tick labels.
//! Prefer translated ratios for close endpoints; scale only when their span
//! overflows. Tick labels identify the actual f64 tick, never a rounded zero.
const std = @import("std");
const A = std.mem.Allocator;
pub const Axis = struct {
    low: f64,
    high: f64,
    pub fn init(minimum: f64, maximum: f64, padded: bool) !Axis {
        if (!std.math.isFinite(minimum) or !std.math.isFinite(maximum) or minimum > maximum) return error.InvalidInput;
        const pad = if (minimum == maximum) @max(0.5, @abs(minimum) * 0.05) else if (padded) maximum * 0.05 - minimum * 0.05 else 0;
        const low = @max(-std.math.floatMax(f64), minimum - pad);
        const high = @min(std.math.floatMax(f64), maximum + pad);
        if (!(high > low)) return error.InvalidInput;
        return .{ .low = low, .high = high };
    }
    pub fn fraction(self: Axis, value: f64) f64 {
        const width = self.high - self.low;
        return if (std.math.isFinite(width)) (value - self.low) / width else blk: {
            const scale = @max(@abs(self.low), @abs(self.high));
            break :blk (value / scale - self.low / scale) / (self.high / scale - self.low / scale);
        };
    }
    pub fn interpolate(self: Axis, t: f64) f64 {
        if (t <= 0) return self.low;
        if (t >= 1) return self.high;
        const width = self.high - self.low;
        return if (std.math.isFinite(width)) self.low + width * t else self.low * (1 - t) + self.high * t;
    }
};
pub fn label(a: A, value: f64) ![]const u8 {
    if (!std.math.isFinite(value)) return error.InvalidInput;
    if (value == 0) return a.dupe(u8, "0");
    return if (@abs(value) < 0.0001 or @abs(value) >= 1e7) std.fmt.allocPrint(a, "{e}", .{value}) else std.fmt.allocPrint(a, "{d}", .{value});
}
pub const Tick = struct { value: f64, label: []const u8 };
pub fn ticks(a: A, minimum: f64, maximum: f64) ![]Tick {
    if (!std.math.isFinite(minimum) or !std.math.isFinite(maximum) or minimum > maximum) return error.InvalidInput;
    if (minimum == maximum) return a.dupe(Tick, &.{.{ .value = minimum, .label = try label(a, minimum) }});
    const span: Axis = .{ .low = minimum, .high = maximum };
    var list: std.ArrayList(Tick) = .empty;
    // Three roundtrip labels remain readable even for 24-character exponents.
    for (0..3) |i| {
        const value = if (i == 1 and minimum < 0 and maximum > 0) @as(f64, 0) else span.interpolate(@as(f64, @floatFromInt(i)) / 2);
        if (list.items.len > 0 and value == list.items[list.items.len - 1].value) continue;
        try list.append(a, .{ .value = value, .label = try label(a, value) });
    }
    return list.toOwnedSlice(a);
}
test "NPAR010 finite axis geometry tiny subnormal extreme and neighboring inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tiny = std.math.floatTrueMin(f64);
    const max = std.math.floatMax(f64);
    const cases = [_][2]f64{ .{ 1e-9, 6e-9 }, .{ -max, max }, .{ max, max }, .{ -max, -max }, .{ tiny, 2 * tiny }, .{ 1, std.math.nextAfter(f64, 1, 2) }, .{ 2, 2 } };
    for (cases) |range| {
        const axis = try Axis.init(range[0], range[1], true);
        try std.testing.expect(std.math.isFinite(axis.low) and std.math.isFinite(axis.high));
        for (range) |value| {
            const fraction = axis.fraction(value);
            try std.testing.expect(std.math.isFinite(fraction) and fraction >= 0 and fraction <= 1);
        }
        const marks = try ticks(a, range[0], range[1]);
        for (marks, 0..) |mark, i| {
            try std.testing.expectEqual(mark.value, try std.fmt.parseFloat(f64, mark.label));
            if (i > 0) try std.testing.expect(mark.value > marks[i - 1].value and !std.mem.eql(u8, mark.label, marks[i - 1].label));
        }
    }
    const wide = try Axis.init(-max, max, false);
    try std.testing.expectEqual(@as(f64, 0), wide.fraction(-max));
    try std.testing.expectEqual(@as(f64, 0.5), wide.fraction(0));
    try std.testing.expectEqual(@as(f64, 1), wide.fraction(max));
}
