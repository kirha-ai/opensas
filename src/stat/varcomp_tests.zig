//! STAT-VARCOMP-001 parser, role and boundary tests via the captured
//! diagnostics reporter (no spawned process).
const std = @import("std");
const vc = @import("varcomp.zig");

test "STAT-VARCOMP-001 estimate cells follow the reference listing formats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { f64, []const u8 }{
        .{ 0.3176017115, "0.31760" },   .{ 0, "0" },                 .{ 2.0738685461, "2.07387" },
        .{ -0.0499835, "-0.04998" },    .{ -0.00224173, "-0.0022417" }, .{ 0.00896679, "0.0089668" },
        .{ 1.0258e-12, "1.0258E-12" },  .{ 4401703.84, "4401703.8" }, .{ -273.396512, "-273.39651" },
        .{ 1464.36727, "1464.4" },
    };
    for (cases) |c| try std.testing.expectEqualStrings(c[1], try vc.cell(a, c[0]));
}
