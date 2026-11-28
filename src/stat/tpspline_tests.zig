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

test "STAT-TPSPLINE-003 thin-plate basis constants and polynomial-space dimensions by hand" {
    const pi = std.math.pi;
    const r: f64 = 1.7;
    // d=2, m=2: r^2 log r / (8 pi) (p.10309).
    try std.testing.expectApproxEqRel(r * r * @log(r) / (8 * pi), tp.kernel(r, 2, 2), 1e-14);
    // d=1, m=2: Gamma(-3/2) / (2^4 sqrt(pi)) r^3 = (4 sqrt(pi)/3) / (16 sqrt(pi)) r^3 = r^3/12.
    try std.testing.expectApproxEqRel(r * r * r / 12, tp.kernel(r, 1, 2), 1e-14);
    // d=3, m=2: Gamma(-1/2) / (2^4 pi^(3/2)) r = -r / (8 pi).
    try std.testing.expectApproxEqRel(-r / (8 * pi), tp.kernel(r, 3, 2), 1e-14);
    // d=2, m=3: (-1)^5 / (2^5 pi 2! 2!) r^4 log r.
    try std.testing.expectApproxEqRel(-std.math.pow(f64, r, 4) * @log(r) / (128 * pi), tp.kernel(r, 2, 3), 1e-14);
    // d=4, m=3: (-1)^6 / (2^5 pi^2 2! 1!) r^2 log r.
    try std.testing.expectApproxEqRel(r * r * @log(r) / (64 * pi * pi), tp.kernel(r, 4, 3), 1e-14);
    try std.testing.expectEqual(@as(f64, 0), tp.kernel(0, 2, 2));
    // M = C(m+d-1, d): SAS 15.4 reference listings show 2, 3, 4, 6 and 15.
    try std.testing.expectEqual(@as(usize, 2), tp.polyDim(1, 2));
    try std.testing.expectEqual(@as(usize, 3), tp.polyDim(2, 2));
    try std.testing.expectEqual(@as(usize, 4), tp.polyDim(3, 2));
    try std.testing.expectEqual(@as(usize, 6), tp.polyDim(2, 3));
    try std.testing.expectEqual(@as(usize, 15), tp.polyDim(4, 3));
}

test "STAT-TPSPLINE-003 DF= solves tr(A) = df and a regression variable enlarges the null space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try surface(a);
    const b = try tp.basis(a, d.x, d.y, 2);
    const l = tp.solveDf(b, 10).?;
    try std.testing.expectApproxEqAbs(@as(f64, 40), tp.stats(b, l).tr, 1e-9);
    // tr(A) cannot fall to the polynomial-space dimension 3.
    try std.testing.expect(tp.solveDf(b, 3) == null);
    // One regression variable: tr(I-A) -> n - 4 as lambda -> infinity.
    const zr = try a.alloc(f64, 50);
    for (zr, 0..) |*v, i| v.* = @as(f64, @floatFromInt(i % 5)) / 4;
    const bz = try tp.basisFull(a, d.x, zr, 1, d.y, 2, 2);
    try std.testing.expectApproxEqAbs(@as(f64, 46), tp.stats(bz, 15).tr, 1e-6);
    // A regression variable equal to 2*x1 is rank deficient.
    for (zr, 0..) |*v, i| v.* = 2 * d.x[2 * i];
    try std.testing.expectError(error.LinearlyDependent, tp.basisFull(a, d.x, zr, 1, d.y, 2, 2));
}

/// The Getting Started data of Chapter 125 (published sample data): x1 x2 y.
const measure = [_]f64{ -1.0, -1.0, 15.54483570, -1.0, -1.0, 15.76312613, -0.5, -1.0, 18.67397826, -0.5, -1.0, 18.49722167, 0.0, -1.0, 19.66086310, 0.0, -1.0, 19.80231311, 0.5, -1.0, 18.59838649, 0.5, -1.0, 18.51904737, 1.0, -1.0, 15.86842815, 1.0, -1.0, 16.03913832, -1.0, -0.5, 10.92383867, -1.0, -0.5, 11.14066546, -0.5, -0.5, 14.81392847, -0.5, -0.5, 14.82830425, 0.0, -0.5, 16.56449698, 0.0, -0.5, 16.44307297, 0.5, -0.5, 14.90792284, 0.5, -0.5, 15.05653924, 1.0, -0.5, 10.91956264, 1.0, -0.5, 10.94227538, -1.0, 0.0, 9.61492010, -1.0, 0.0, 9.64648093, -0.5, 0.0, 14.03133439, -0.5, 0.0, 14.03122345, 0.0, 0.0, 15.77400253, 0.0, 0.0, 16.00412514, 0.5, 0.0, 13.99627680, 0.5, 0.0, 14.02826553, 1.0, 0.0, 9.55700164, 1.0, 0.0, 9.58467047, -1.0, 0.5, 11.20625177, -1.0, 0.5, 11.08651907, -0.5, 0.5, 14.83723493, -0.5, 0.5, 14.99369172, 0.0, 0.5, 16.55494349, 0.0, 0.5, 16.51294369, 0.5, 0.5, 14.98448603, 0.5, 0.5, 14.71816070, 1.0, 0.5, 11.14575565, 1.0, 0.5, 11.17168689, -1.0, 1.0, 15.82595514, -1.0, 1.0, 15.96022497, -0.5, 1.0, 18.64014953, -0.5, 1.0, 18.56095997, 0.0, 1.0, 19.54375504, 0.0, 1.0, 19.80902641, 0.5, 1.0, 18.56884576, 0.5, 1.0, 18.61010439, 1.0, 1.0, 15.86586951, 1.0, 1.0, 15.90136745 };

test "STAT-TPSPLINE-003 Smoothing Penalty digits against an independent 40-digit solve" {
    // Independent method: Python Decimal at 40-50 digits, direct Gaussian
    // elimination of the bordered system (K + n lambda I) delta + X alpha = y,
    // X' delta = 0 (p.10309), penalty = delta'K delta; DF= cases bisect
    // tr(A) = df with tr(I-A) = n lambda tr(C), C the delta block of the
    // inverse; GCV minimum by golden section to 1e-9. Different algorithm
    // from the Householder + Jacobi eigen path under test.
    // Bound: the eigen path is backward stable; its first-order relative
    // error in the penalty is at most 10 * kappa * n * u with
    // kappa = (lmax + n lambda) / (n lambda), u = 2^-53. Each independent
    // value lies more than that bound away from the 4-decimal rounding
    // boundary, so the printed digit is determined; it is opensas's digit.
    // SAS 15.4 prints one unit less in the last place in each case (its
    // value lies at least 5e-6 below the exact one, outside the bound).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = measure.len / 3;
    const Case = struct { what: []const u8, sas: []const u8, ours: []const u8, exact: f64 };
    const cases = [_]Case{
        .{ .what = "d2 lognl0=-3.4762", .sas = "2558.1438", .ours = "2558.1439", .exact = 2558.1438607661 },
        .{ .what = "d3 lognl0=-3", .sas = "5693.3970", .ours = "5693.3971", .exact = 5693.3970553498 },
        .{ .what = "y2 lognl0=-3", .sas = "2816.1337", .ours = "2816.1338", .exact = 2816.1337570977 },
        .{ .what = "d2 df=10", .sas = "1179.5087", .ours = "1179.5088", .exact = 1179.5088034374 },
        .{ .what = "z (x1 x2) df=12", .sas = "1364.6695", .ours = "1364.6696", .exact = 1364.6695970574 },
        .{ .what = "d2 lognl0=-3 (agrees)", .sas = "2514.2929", .ours = "2514.2929", .exact = 2514.2929291707 },
        .{ .what = "d2 GCV minimum", .sas = "2558.1432", .ours = "2558.1433", .exact = 2558.1432709453 },
    };
    for (cases) |c| {
        const nn: usize = if (std.mem.startsWith(u8, c.what, "y2")) n - 1 else n;
        const d: usize = if (std.mem.startsWith(u8, c.what, "d3")) 3 else 2;
        const p: usize = if (std.mem.startsWith(u8, c.what, "z ")) 1 else 0;
        const x = try a.alloc(f64, nn * d);
        const y = try a.alloc(f64, nn);
        const zr = try a.alloc(f64, nn * p);
        var r: usize = 0;
        for (0..n) |k| {
            const obs = k + 1;
            if (nn < n and obs == 3) continue;
            const x1 = measure[3 * k];
            const x2 = measure[3 * k + 1];
            const z = @as(f64, @floatFromInt(obs % 5)) / 4;
            x[r * d] = x1;
            x[r * d + 1] = x2;
            if (d == 3) x[r * d + 2] = @as(f64, @floatFromInt((obs * 7) % 11)) / 10;
            if (p == 1) zr[r] = z;
            y[r] = if (nn < n) measure[3 * k + 2] + x1 * x2 + z else measure[3 * k + 2];
            r += 1;
        }
        const b = try tp.basisFull(a, x, zr, p, y, d, 2);
        const l: f64 = if (std.mem.indexOf(u8, c.what, "df=10") != null)
            tp.solveDf(b, 10).?
        else if (std.mem.indexOf(u8, c.what, "df=12") != null)
            tp.solveDf(b, 12).?
        else if (std.mem.indexOf(u8, c.what, "GCV") != null)
            tp.minimize(b)
        else if (std.mem.indexOf(u8, c.what, "-3.4762") != null) -3.4762 else -3;
        const pen = tp.stats(b, l).penalty;
        const nl = std.math.pow(f64, 10, l);
        const kappa = (b.lam[0] + nl) / nl;
        var bound = 10 * kappa * @as(f64, @floatFromInt(nn)) * std.math.floatEps(f64) / 2 * c.exact;
        // GCV minimum: the independent search gives log10(n lambda) =
        // -3.4761888173, opensas -3.4761888002; add |dPenalty/dl| * 5e-8.
        if (std.mem.indexOf(u8, c.what, "GCV") != null) {
            try std.testing.expectApproxEqAbs(@as(f64, -3.4761888173), l, 5e-8);
            const slope = (tp.stats(b, l + 1e-6).penalty - tp.stats(b, l - 1e-6).penalty) / 2e-6;
            bound += @abs(slope) * 5e-8;
        }
        // DF=: the independent bisection fixes l to 0.3 / 2^34 < 2e-11;
        // add |dPenalty/dl| * 1e-10.
        if (std.mem.indexOf(u8, c.what, "df=") != null) {
            const slope = (tp.stats(b, l + 1e-6).penalty - tp.stats(b, l - 1e-6).penalty) / 2e-6;
            bound += @abs(slope) * 1e-10;
        }
        if (!(@abs(pen - c.exact) <= bound)) std.debug.print("{s}: pen={d:.10} exact={d:.10} bound={e}\n", .{ c.what, pen, c.exact, bound });
        try std.testing.expect(@abs(pen - c.exact) <= bound);
        // The exact value is farther than the bound from the rounding boundary.
        const scaled = c.exact * 1e4;
        try std.testing.expect(@abs(scaled - @floor(scaled) - 0.5) * 1e-4 > bound);
        try std.testing.expectEqualStrings(c.ours, try std.fmt.allocPrint(a, "{d:.4}", .{pen}));
        try std.testing.expectEqualStrings(c.ours, try std.fmt.allocPrint(a, "{d:.4}", .{c.exact}));
        const sas = try std.fmt.parseFloat(f64, c.sas);
        if (!std.mem.eql(u8, c.sas, c.ours)) try std.testing.expect(@abs(sas + 0.00005 - c.exact) > bound);
    }
}
