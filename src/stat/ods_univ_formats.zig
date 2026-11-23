//! Data-dependent numeric formats used by the Base.Univariate ODS templates.
const std = @import("std");
const A = std.mem.Allocator;

fn fixed(a: A, width: usize, decimals: usize) ![]const u8 {
    return if (decimals == 0) std.fmt.allocPrint(a, "{d}.", .{width}) else std.fmt.allocPrint(a, "{d}.{d}", .{ width, decimals });
}

fn exponent(x: f64) i32 {
    return @intFromFloat(@floor(@log10(@abs(x))));
}

/// Measurements use just enough places to preserve the sample's precision,
/// up to six significant digits. Reserve one column for the sign in all cases.
pub fn measurement(a: A, values: []const f64) ![]const u8 {
    var digits: usize = 1;
    var decimals: usize = 0;
    for (values) |v| {
        if (v == 0 or !std.math.isFinite(v)) continue;
        const exp = exponent(v);
        if (exp > 13 or exp < -12) return "BEST12.";
        digits = @max(digits, @as(usize, @intCast(@max(1, exp + 1))));
        const max_places: usize = @intCast(@max(0, 5 - exp));
        var places: usize = 0;
        var scaled = v;
        while (places < max_places and @abs(scaled - @round(scaled)) > 1e-13 * @max(1, @abs(scaled))) : (places += 1) scaled *= 10;
        decimals = @max(decimals, places);
    }
    return fixed(a, digits + 1 + decimals + @intFromBool(decimals != 0), decimals);
}

/// ODS formats location and scale statistics within an eight-column field.
/// SAS uses the D format when a fixed field would obscure the statistic.
pub fn statistic(a: A, values: []const f64) ![]const u8 {
    var integer_width: usize = 0;
    for (values) |value| {
        if (!std.math.isFinite(value) or value == 0) continue;
        const exp = exponent(value);
        if (exp < -3 or exp > 6) return "D8.3";
        const width: usize = @intCast(@max(1, exp + 1));
        integer_width = @max(integer_width, width + @intFromBool(value < 0));
    }
    if (integer_width == 0) return "8.";
    return fixed(a, 8, 7 -| integer_width);
}

test "UNIVARIATE M9 formats distinguish signed, fractional, large, tiny and constant data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { values: []const f64, measurement: []const u8, location: []const f64, statistic: []const u8 }{
        .{ .values = &.{ 1, 19 }, .measurement = "3.", .location = &.{ 10, 10 }, .statistic = "8.5" },
        .{ .values = &.{ -12, 6 }, .measurement = "3.", .location = &.{ -3, -3 }, .statistic = "8.5" },
        .{ .values = &.{ 1.0 / 11.0, 19.0 / 11.0 }, .measurement = "10.7", .location = &.{10.0 / 11.0}, .statistic = "8.6" },
        .{ .values = &.{ 18500, 126500 }, .measurement = "7.", .location = &.{72500}, .statistic = "8.2" },
        .{ .values = &.{ 0.000001, 0.000019 }, .measurement = "9.6", .location = &.{0.000010}, .statistic = "D8.3" },
        .{ .values = &.{0}, .measurement = "2.", .location = &.{0}, .statistic = "8." },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c.measurement, try measurement(a, c.values));
        try std.testing.expectEqualStrings(c.statistic, try statistic(a, c.location));
    }
}
