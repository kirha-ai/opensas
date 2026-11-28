//! STAT-QUANTREG-001 permanent tests.
const std = @import("std");
const q = @import("quantreg.zig");

test "STAT-QUANTREG-001 intercept-only median fit is the sample median (hand math)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const y = [_]f64{ 3, 1, 7, 4, 10 };
    const x = [_]f64{ 1, 1, 1, 1, 1 };
    const d: q.Design = .{ .x = &x, .n = 5, .p = 1 };
    const v = try q.fitVertex(a, d, &y, 0.5, null);
    try std.testing.expectApproxEqAbs(@as(f64, 4), v.beta[0], 1e-12);
    // sum |y - 4| / 2 = (1 + 3 + 3 + 0 + 6) / 2 = 6.5
    try std.testing.expectApproxEqAbs(@as(f64, 6.5), q.objective(d, &y, 0.5, v.beta), 1e-12);
}

test "STAT-QUANTREG-001 exact line through two points interpolates (hand math)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // y = 1 + 2x exactly for 3 of 5 points; the median fit recovers it.
    const y = [_]f64{ 1, 3, 5, 20, -10 };
    const x = [_]f64{ 1, 0, 1, 1, 1, 2, 1, 3, 1, 4 };
    const d: q.Design = .{ .x = &x, .n = 5, .p = 2 };
    const v = try q.fitVertex(a, d, &y, 0.5, null);
    const obj = q.objective(d, &y, 0.5, v.beta);
    // residuals of 1+2x: 0,0,0,13,-19 -> objective 16; nothing can do better
    try std.testing.expect(obj <= 16 + 1e-9);
}

test "STAT-QUANTREG-001 summary statistics use definition 5 and scaled MAD (hand math)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const s = try q.summarize(arena.allocator(), &.{ 1, 2, 3, 4 });
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), s.q1, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), s.median, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), s.q3, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), s.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(5.0 / 3.0), s.sd, 1e-12);
    // |x - 2.5| = 1.5,0.5,0.5,1.5 -> median 1.0 -> 1.4826
    try std.testing.expectApproxEqAbs(@as(f64, 1.4826), s.mad, 1e-12);
}
