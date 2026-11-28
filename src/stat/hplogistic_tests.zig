//! STAT-HPLOGISTIC-001 unit tests: the Newton path against SAS 15.4
//! reference runs (ITDETAILS) on invented eight-row data.
const std = @import("std");
const hp = @import("hplogistic.zig");

test "STAT-HPLOGISTIC-001 Newton path and ABSGCONV stop match the SAS reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // y = 0 is the event (first ordered value); x = 1..8.
    const ev = [_]f64{ 1, 0, 1, 0, 1, 0, 0, 1 };
    var x: [16]f64 = undefined;
    for (0..8) |i| {
        x[2 * i] = 1;
        x[2 * i + 1] = @floatFromInt(i + 1);
    }
    const m = [_]f64{1} ** 8;
    const r = (try hp.fit(a, &x, &ev, &m, 8, 2, 8)).?;
    try std.testing.expectEqual(@as(usize, 3), r.history.len);
    try std.testing.expectEqual(hp.Stop.absgconv, r.stop);
    for (r.history, [_]f64{ 0.6880897889, 0.6871739354, 0.6871738342 }) |h, f| try std.testing.expectApproxEqAbs(f, h.f, 5e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 0.048213), r.history[0].max_grad, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4316), r.beta[0], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, -0.09591), r.beta[1], 5e-6);
    // Standard errors 1.5735 and 0.3119.
    try std.testing.expectApproxEqAbs(@as(f64, 1.5735), @sqrt(r.cov[0]), 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3119), @sqrt(r.cov[3]), 5e-5);
}

test "STAT-HPLOGISTIC-001 FREQ and WEIGHT: objective normalized by the frequency sum, lagged GCONV" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Columns: intercept, g=a indicator, x; weight*freq multiplicities.
    const rows = [_][5]f64{ .{ 1, 0, 1, 1, 1 }, .{ 1, 1, 2, 2, 1 }, .{ 1, 0, 3, 1, 2 }, .{ 0, 1, 4, 1, 1 }, .{ 0, 0, 5, 3, 1 }, .{ 0, 1, 6, 1, 1 }, .{ 0, 1, 7, 1, 3 }, .{ 1, 0, 8, 2, 1 } };
    var x: [24]f64 = undefined;
    var ev: [8]f64 = undefined;
    var m: [8]f64 = undefined;
    for (rows, 0..) |row, i| {
        x[3 * i] = 1;
        x[3 * i + 1] = row[0];
        x[3 * i + 2] = row[2];
        ev[i] = 1 - row[1];
        m[i] = row[3] * row[4];
    }
    const r = (try hp.fit(a, &x, &ev, &m, 8, 3, 11)).?;
    try std.testing.expectEqual(@as(usize, 4), r.history.len);
    try std.testing.expectEqual(hp.Stop.gconv, r.stop);
    for (r.history, [_]f64{ 0.8609412684, 0.8538579196, 0.8538281656, 0.853828164 }) |h, f| try std.testing.expectApproxEqAbs(f, h.f, 5e-11);
    // -2 Log Likelihood 18.7842.
    try std.testing.expectApproxEqAbs(@as(f64, 18.7842), -2 * r.ll, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, -1.2229), r.beta[0], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 1.6876), r.beta[1], 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 1.8950), @sqrt(r.cov[0]), 5e-5);
}
