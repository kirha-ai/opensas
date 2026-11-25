//! REG-002 validation only. The production QR fitter is not altered.
//! Independent f128 normal equations are practical for these 2/3-column tests;
//! production fitting must continue to use scaled QR, not normal equations.
const std = @import("std");
const qr = @import("reg_fit.zig");
const population = [_]f64{ 3929, 5308, 7239, 9638, 12866, 17069, 23191, 31443, 39818, 50155, 62947, 75994, 91972, 105710, 122775, 131669, 151325, 179323, 203211, 226542, 248710, 281422 };
const u: f128 = 0x1p-53;
fn gamma(k: usize) f128 {
    const ku = @as(f128, @floatFromInt(k)) * u;
    return ku / (1 - ku);
}

fn reference(x: []const f64, y: []const f64, p: usize) [3]f128 {
    var equations = [_][4]f128{.{ 0, 0, 0, 0 }} ** 3;
    for (0..p) |j| {
        for (0..p) |k| for (y, 0..) |_, i| {
            equations[j][k] += @as(f128, x[i * p + j]) * @as(f128, x[i * p + k]);
        };
        for (y, 0..) |value, i| equations[j][p] += @as(f128, x[i * p + j]) * @as(f128, value);
    }
    for (0..p) |j| {
        var pivot = j;
        for (j + 1..p) |i| if (@abs(equations[i][j]) > @abs(equations[pivot][j])) {
            pivot = i;
        };
        std.mem.swap([4]f128, &equations[j], &equations[pivot]);
        const divisor = equations[j][j];
        std.debug.assert(divisor != 0);
        for (0..p + 1) |k| equations[j][k] /= divisor;
        for (0..p) |i| {
            if (i == j) continue;
            const factor = equations[i][j];
            for (0..p + 1) |k| equations[i][k] -= factor * equations[j][k];
        }
    }
    var beta = [_]f128{0} ** 3;
    for (0..p) |j| beta[j] = equations[j][p];
    return beta;
}

test "REG-002 QR orthogonality and predictions across polynomial units and centering" {
    // All transformations are dyadic, so changing units introduces no new
    // input rounding. Four bases * three response units * two polynomial orders.
    const bases = [_]struct { center: f64, scale: f64 }{
        .{ .center = 0, .scale = 1 },
        .{ .center = 0, .scale = 0x1p-20 },
        .{ .center = 0, .scale = 0x1p20 },
        .{ .center = 1895, .scale = 128 },
    };
    for (bases) |basis| for ([_]f64{ 0x1p-20, 1, 0x1p20 }) |response_scale| for ([_]usize{ 2, 3 }) |p| {
        var x_storage: [22 * 3]f64 = undefined;
        const x = x_storage[0 .. population.len * p];
        var y: [22]f64 = undefined;
        for (population, 0..) |value, i| {
            const year = @as(f64, @floatFromInt(1790 + 10 * i));
            const t = (year - basis.center) / basis.scale;
            x[i * p] = 1;
            x[i * p + 1] = t;
            if (p == 3) x[i * p + 2] = t * t;
            y[i] = value / 1000 * response_scale;
        }
        const beta = reference(x, &y, p);
        var fit = try qr.fit(std.testing.allocator, x, &y, y.len, p, null);
        defer fit.deinit(std.testing.allocator);
        try std.testing.expectEqual(p, fit.rank);
        var row_budget: [22]f128 = undefined;
        var exact_residual: [22]f128 = undefined;
        for (y, 0..) |value, i| {
            var prediction: f128 = 0;
            var envelope: f128 = @abs(@as(f128, value));
            for (0..p) |j| {
                const term = @as(f128, x[i * p + j]) * beta[j];
                prediction += term;
                envelope += @abs(term);
            }
            exact_residual[i] = @as(f128, value) - prediction;
            row_budget[i] = gamma(2 * p + 2) * envelope;
            // A deliberately independent forward check, not just an intercept
            // sum that could cancel even when individual predictions are wrong.
            try std.testing.expect(@abs(@as(f128, fit.fitted[i]) - prediction) <= row_budget[i]);
        }
        for (0..p) |j| {
            var observed: f64 = 0;
            var exact: f128 = 0;
            var residual_l1: f128 = 0;
            var evaluation: f128 = 0;
            for (fit.residuals, exact_residual, row_budget, 0..) |r, ref, budget, i| {
                const predictor = x[i * p + j];
                observed += predictor * r;
                exact += @as(f128, predictor) * ref;
                residual_l1 += @abs(@as(f128, predictor) * ref);
                evaluation += @abs(@as(f128, predictor)) * budget;
            }
            const accumulation = gamma(if (j == 0) y.len - 1 else 2 * y.len);
            const bound = evaluation + accumulation * (residual_l1 + evaluation);
            // Check the f128 reference itself is negligible relative to the
            // binary64 budget before using its exact normal-equation identity.
            try std.testing.expect(@abs(exact) <= bound * 1e-6);
            try std.testing.expect(@abs(@as(f128, observed)) <= bound);
        }
    };
}
