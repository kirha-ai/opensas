//! STAT-ORTHOREG-001 kernel and cell-format tests (no spawned process).
const std = @import("std");
const o = @import("orthoreg.zig");

test "STAT-ORTHOREG-001 BESTD18.9 and BESTD12.9 cells match SAS PUT output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Expected strings: SAS 9.4 PUT(x, BESTD18.9) / PUT(x, BESTD12.9).
    const c18 = [_]struct { f64, []const u8 }{
        .{ 1.2345678901234567e-9, "1.2345678901235E-9" }, .{ 1.2345678901234567e-7, "0.000000123456789" },
        .{ 1.2345678901234567e-5, "0.000012345678901" },  .{ 1.2345678901234567e-4, "0.000123456789" },
        .{ 1.2345678901234567, "1.234567890123" },          .{ 1234.5678901234567, "1234.567890123450" },
        .{ 12345.678901234567, "12345.67890" },             .{ 123456789.01234567, "123456789.01235" },
        .{ 12345678901.234567, "12345678901.23450" },       .{ -1.9490713904123456e-9, "-1.949071390412E-9" },
        .{ -1949.0713904123456, "-1949.071390412340" },    .{ -0.5, "-0.500000000000" },
        .{ 185008826, "185008826" },                        .{ 185008826.0000001, "185008826.00000" },
        .{ 0, "0" },
    };
    for (c18) |c| try std.testing.expectEqualStrings(c[1], try o.bestd(a, c[0], 18));
    const c12 = [_]struct { f64, []const u8 }{
        .{ 1.2345678901234567e-6, "1.2345679E-6" }, .{ -1.9490713904123456e-9, "-1.949071E-9" },
        .{ 1.2345678901234567e-5, "0.0000123457" }, .{ 0.12345678901234567, "0.123456789" },
        .{ 0.012345678901234567, "0.0123456789" },  .{ -0.019490713904123456, "-0.019490714" },
        .{ 1.2345678901234567, "1.234567890" },     .{ 12345.678901234567, "12345.67890" },
        .{ 123456789.01234567, "123456789.0" },     .{ 1234567890.1234567, "1234567890" },
        .{ 12345678901.234567, "12345678901" },     .{ -19490713904.123456, "-19490713904" },
        .{ 185008826.0000001, "185008826.0" },
    };
    for (c12) |c| try std.testing.expectEqualStrings(c[1], try o.bestd(a, c[0], 12));
}

test "STAT-ORTHOREG-001 Givens fit reproduces a hand-solved weighted line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // x = 0,1,2,3; y = 1,3,2,5; w = 1,2,1,1. Hand solution of the weighted
    // normal equations: S_w=5, S_wx=7, S_wxx=15, S_wy=14, S_wxy=25 →
    // slope = (5*25-7*14)/(5*15-49) = 27/26, intercept = (14-7*27/26)/5 = 35/26.
    const rows = [_][]const f64{ &.{ 1, 0 }, &.{ 1, 1 }, &.{ 1, 2 }, &.{ 1, 3 } };
    const f = try o.fitGivens(a, &rows, &.{ 1, 3, 2, 5 }, &.{ 1, 2, 1, 1 }, 1e-12);
    try std.testing.expectApproxEqRel(27.0 / 26.0, f.beta[1], 1e-14);
    try std.testing.expectApproxEqRel(35.0 / 26.0, f.beta[0], 1e-14);
    // SSE = sum w (y - yhat)^2; SSM = weighted corrected SS - SSE.
    var sse: f64 = 0;
    for (rows, [_]f64{ 1, 3, 2, 5 }, [_]f64{ 1, 2, 1, 1 }) |r, y, w| {
        const e = y - (f.beta[0] + f.beta[1] * r[1]);
        sse += w * e * e;
    }
    try std.testing.expectApproxEqRel(sse, f.sse, 1e-12);
    try std.testing.expectApproxEqRel(83.0 / 26.0, f.sse, 1e-14);
    const css = (1.0 + 18.0 + 4.0 + 25.0) - 14.0 * 14.0 / 5.0; // 44/5
    try std.testing.expectApproxEqRel(css - sse, f.ssm, 1e-12);
    try std.testing.expectEqual(@as(usize, 2), f.df_error);
    // Var(slope) = MSE * S_w / det.
    const mse = sse / 2.0;
    try std.testing.expectApproxEqRel(@sqrt(mse * 5.0 / 26.0), f.se[1], 1e-12);
    try std.testing.expectError(error.Singular, o.fitGivens(a, &[_][]const f64{ &.{ 1, 2 }, &.{ 1, 2 }, &.{ 1, 2 } }, &.{ 1, 2, 3 }, &.{ 1, 1, 1 }, 1e-12));
}
