//! STAT-TPSPLINE-001 unit tests: GCV path against the SAS 15.4 reference
//! listing and the large-lambda limit against a hand least-squares plane.
const std = @import("std");
const tp = @import("tpspline.zig");

fn surface(a: std.mem.Allocator) !struct { x: []f64, y: []f64 } {
    const x = try a.alloc(f64, 100);
    const y = try a.alloc(f64, 50);
    var k: usize = 0;
    for (0..5) |i| for (0..5) |j| for (1..3) |rep| {
        const x1 = -1 + 0.5 * @as(f64, @floatFromInt(i));
        const x2 = -1 + 0.5 * @as(f64, @floatFromInt(j));
        x[2 * k] = x1;
        x[2 * k + 1] = x2;
        y[k] = 3 + x1 - 2 * x2 + 0.5 * x1 * x2 + 0.1 * @cos(@as(f64, @floatFromInt(rep)) + x1 + x2);
        k += 1;
    };
    return .{ .x = x, .y = y };
}

test "STAT-TPSPLINE-001 GCV function and final estimate match the SAS reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try surface(a);
    const b = try tp.basis(a, d.x, d.y, 2);
    // SAS 15.4 GCV Function table.
    const ref = [_][2]f64{ .{ -4, 0.004833 }, .{ -3.5, 0.004734 }, .{ -3, 0.004467 }, .{ -2.5, 0.003912 } };
    for (ref) |r| try std.testing.expectApproxEqAbs(r[1], tp.stats(b, r[0]).gcv, 5e-7);
    const l = tp.minimize(b);
    try std.testing.expectApproxEqAbs(@as(f64, -1.7934), l, 5e-5);
    const st = tp.stats(b, l);
    try std.testing.expectApproxEqAbs(@as(f64, 7.7851), st.penalty, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0734), st.rss, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 33.8835), st.tr, 5e-5);
    const f = try tp.fitted(a, b, d.y, l);
    // OUT= row 1: P_y 4.54597.
    try std.testing.expectApproxEqAbs(@as(f64, 4.54597), f.f[0], 5e-6);
}

test "STAT-TPSPLINE-001 a huge lambda gives the least-squares plane" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Five points: (0,0) (1,0) (0,1) (1,1) (2,2), y = 1 2 3 5 4.
    const x = [_]f64{ 0, 0, 1, 0, 0, 1, 1, 1, 2, 2 };
    const y = [_]f64{ 1, 2, 3, 5, 4 };
    const b = try tp.basis(a, &x, &y, 2);
    const st = tp.stats(b, 12);
    // tr(I-A) -> n - 3 as lambda -> infinity.
    try std.testing.expectApproxEqAbs(@as(f64, 2), st.tr, 1e-6);
    // Hand OLS of y on (1, x1, x2): X'X = [5 4 4; 4 6 5; 4 5 6],
    // X'y = [15 15 16]; solution b = (41, 6, 29) / 23.
    const f = try tp.fitted(a, b, &y, 12);
    const plane = [_]f64{ 41.0 / 23.0, 47.0 / 23.0, 70.0 / 23.0, 76.0 / 23.0, 111.0 / 23.0 };
    for (plane, f.f) |p, q| try std.testing.expectApproxEqAbs(p, q, 1e-6);
}

test "STAT-TPSPLINE-001 OUTPUT variable order and labels follow the SAS reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // SAS 15.4 reference run: OUTPUT OUT= ADIAG STD RESID UCLM LCLM PRED.
    const s: tp.Spec = .{ .ds = undefined, .pred = true, .std = true, .resid = true, .lclm = true, .uclm = true, .adiag = true };
    const vars = try tp.outputVars(a, s, "y");
    const names = [_][]const u8{ "P_y", "StD_y", "R_y", "LCLM_y", "UCLM_y", "Adiag_y" };
    const labels = [_][]const u8{ "Predicted Value of y", "Standard Deviation of y", "Residual of y", "Lower 95% Confidence Limit for Mean of y", "Upper 95% Confidence Limit for Mean of y", "Diagonal Elements of Matrix A for y" };
    try std.testing.expectEqual(names.len, vars.len);
    for (vars, names, labels) |v, n, l| {
        try std.testing.expectEqualStrings(n, v.name);
        try std.testing.expectEqualStrings(l, v.label);
    }
    const s90: tp.Spec = .{ .ds = undefined, .uclm = true, .alpha = 0.1 };
    try std.testing.expectEqualStrings("Upper 90% Confidence Limit for Mean of y", (try tp.outputVars(a, s90, "y"))[0].label);
}
