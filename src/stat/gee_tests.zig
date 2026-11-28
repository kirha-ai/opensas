//! STAT-GEE-001 unit tests: parse/validation outcomes through the captured
//! diagnostics reporter, and the covariance cell format.
const std = @import("std");
const gee = @import("gee.zig");

test "STAT-GEE-001 covariance cells follow the reference listing digits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Figure 50.4 / oracle listing cells.
    const cases = [_]struct { x: f64, text: []const u8 }{
        .{ .x = 3.260694, .text = "3.26069" },
        .{ .x = -0.163128, .text = "-0.16313" },
        .{ .x = 0.0025201, .text = "0.002520" },
        .{ .x = 0.0337912, .text = "0.03379" },
        .{ .x = -0.552614, .text = "-0.55261" },
    };
    for (cases) |c| try std.testing.expectEqualStrings(c.text, try gee.covText(a, c.x));
}
