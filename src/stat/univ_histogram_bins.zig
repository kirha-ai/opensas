//! Automatic histogram intervals: Terrell–Scott initial count and SAS's
//! preferred decimal widths. Explicit interval counting is in values.zig.
const std = @import("std");
const diag = @import("../diag.zig");

pub fn automatic(a: std.mem.Allocator, d: *diag.Diagnostics, sorted: []const f64, endpoints: bool, right: bool) diag.Error![]f64 {
    if (sorted.len == 0) return &.{};
    const min = sorted[0];
    const max = sorted[sorted.len - 1];
    if (!std.math.isFinite(min) or !std.math.isFinite(max)) return d.fail(error.ParseError, 0, "UNIVARIATE: nonfinite automatic histogram range", .{});
    if (min == max) return d.fail(error.ParseError, 0, "UNIVARIATE: automatic constant-sample bins are not implemented", .{});
    const count = @ceil(std.math.cbrt(2 * @as(f64, @floatFromInt(sorted.len))));
    const initial = (max - min) / count;
    const unit = std.math.pow(f64, 10, @floor(@log10(initial)));
    var width = unit;
    for ([_]f64{ 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8 }) |factor| {
        if (factor * unit <= initial * (1 + 1e-14)) width = factor * unit;
    }
    var first: f64 = undefined;
    var last: f64 = undefined;
    if (endpoints) {
        first = if (right) (@ceil(min / width) - 1) * width else @floor(min / width) * width;
        last = if (right) @ceil(max / width) * width else (@floor(max / width) + 1) * width;
    } else {
        // Anchor the last center on the lower half-width grid. This explains
        // the half-bin phase at width=.15 for [0,1], versus zero phase at .3.
        const last_center = @floor(2 * max / width) * width / 2;
        var first_center = last_center - @floor((last_center - min) / width + 0.5) * width;
        if (first_center + width / 2 <= min) first_center += width;
        first = first_center - width / 2;
        last = last_center + width / 2;
    }
    const intervals: usize = @intFromFloat(@round((last - first) / width));
    const result = try a.alloc(f64, intervals + 1);
    for (result, 0..) |*v, i| v.* = first + @as(f64, @floatFromInt(i)) * width;
    return result;
}

test "UNIVARIATE automatic bin widths and midpoint phase SAS M9" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    for ([_]usize{ 2, 3, 8, 20, 100, 1000 }, [_]f64{ 0.5, 0.5, 0.3, 0.25, 0.15, 0.06 }, [_]f64{ 0, 0, 0, 0, 0.075, 0.03 }) |n, width, midpoint| {
        const x = try a.alloc(f64, n);
        for (x, 0..) |*v, i| v.* = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        const bins = try automatic(a, &d, x, false, false);
        try std.testing.expectApproxEqAbs(width, bins[1] - bins[0], 1e-12);
        try std.testing.expectApproxEqAbs(midpoint, (bins[0] + bins[1]) / 2, 1e-12);
        const ends = try automatic(a, &d, x, true, false);
        try std.testing.expectApproxEqAbs(@as(f64, 0), ends[0], 1e-12);
    }
    const bins = try automatic(a, &d, &.{ 1, 2, 3, 4, 6, 8, 10, 15 }, false, false);
    try std.testing.expectEqualSlices(f64, &.{ 0, 4, 8, 12, 16 }, bins);
}
