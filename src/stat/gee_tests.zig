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

test "STAT-GEE-001 DESCENDING hint wraps like the LINESIZE=160 reference listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // SAS 9.4 reference lines: the first line ends after "option" (Symptom2)
    // and after "in" (Symptom), i.e. at most 159 columns with the blank.
    const cases = [_]struct { name: []const u8, event: []const u8, other: []const u8, tail: []const u8 }{
        .{ .name = "Symptom2", .event = "0", .other = "1", .tail = "in the PROC statement.\n" },
        .{ .name = "Symptom", .event = "0", .other = "1", .tail = "the PROC statement.\n" },
    };
    for (cases) |c| {
        const text = try std.fmt.allocPrint(a, "PROC GEE is modeling the probability that {s}='{s}'. One way to change this to model the probability that {s}='{s}' is to specify the DESCENDING option in the PROC statement.", .{ c.name, c.event, c.name, c.other });
        var out: std.ArrayList(u8) = .empty;
        try gee.wrapText(a, &out, text, 160);
        const nl = std.mem.indexOfScalar(u8, out.items, '\n').?;
        try std.testing.expect(nl <= 159);
        try std.testing.expectEqualStrings(c.tail, out.items[nl + 1 ..]);
    }
}
