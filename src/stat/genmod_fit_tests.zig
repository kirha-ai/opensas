//! STAT-GENMOD-002 permanent tests for the Normal GLM kernel: closed-form
//! estimates, score equations, finite-difference information, deviance and
//! likelihood identities, and FREQ equivalence. No SAS output is used here;
//! every expected value is derived independently in the test.
//! Data: invented (D-011), except `nor`, the published sample of SAS/STAT 15.4
//! Example "Normal Regression, Log Link" (ch.51).
const std = @import("std");
const fit = @import("genmod_fit.zig");
const expect = std.testing.expect;

fn close(actual: f64, expected: f64, tolerance: f64) !void {
    if (!(@abs(actual - expected) <= tolerance * @max(1, @abs(expected)))) {
        std.debug.print("expected {d}, found {d}\n", .{ expected, actual });
        return error.TestExpectedApproxEqual;
    }
}

fn design(a: std.mem.Allocator, xs: []const f64) ![]f64 {
    const x = try a.alloc(f64, xs.len * 2);
    for (xs, 0..) |v, i| {
        x[2 * i] = 1;
        x[2 * i + 1] = v;
    }
    return x;
}
fn ones(a: std.mem.Allocator, n: usize) ![]f64 {
    const f = try a.alloc(f64, n);
    @memset(f, 1);
    return f;
}

const nor_x = [_]f64{ 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5 };
const nor_y = [_]f64{ 5, 7, 9, 7, 10, 8, 11, 9, 16, 13, 14, 25, 24, 34, 32, 30 };

test "STAT-GENMOD-002 identity link equals the closed-form least squares solution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const xs = [_]f64{ 0, 1, 2, 3, 4, 5, 6 };
    const ys = [_]f64{ 1.5, 2, 4.5, 5, 8, 8.5, 12 };
    // Hand calculation: n=7, xbar=3, ybar=41.5/7, Sxx=28, Sxy=sum (x-3) y.
    const n: f64 = 7;
    var sxy: f64 = 0;
    var ybar: f64 = 0;
    for (xs, ys) |x, y| {
        sxy += (x - 3) * y;
        ybar += y / n;
    }
    const slope = sxy / 28;
    const intercept = ybar - 3 * slope;
    var rss: f64 = 0;
    for (xs, ys) |x, y| rss += (y - intercept - slope * x) * (y - intercept - slope * x);
    const r = try fit.fitNormal(a, try design(a, &xs), &ys, try ones(a, 7), 2, .identity);
    // Linear model: Newton is exact in one step; only rounding remains.
    try close(r.beta[0], intercept, 1e-12);
    try close(r.beta[1], slope, 1e-12);
    try close(r.deviance, rss, 1e-12);
    try close(r.scale, @sqrt(rss / n), 1e-12); // ML divisor n, not n-p
    // Cov = sigma^2 (X'X)^-1: var(slope) = sigma^2/Sxx, var(intercept) = sigma^2 (1/n + xbar^2/Sxx).
    try close(r.cov[3], rss / n / 28, 1e-12);
    try close(r.cov[0], rss / n * (1 / n + 9.0 / 28.0), 1e-12);
    try close(r.cov[1], -3 * rss / n / 28, 1e-12);
    try close(r.scale_se, r.scale / @sqrt(2 * n), 1e-14);
    try close(r.loglik, -0.5 * n * (@log(2 * std.math.pi * rss / n) + 1), 1e-12);
    try expect(r.state.attained() and r.state.allowsInference(false));
}

test "STAT-GENMOD-002 log link with a two-level regressor reproduces the group means" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Saturated in the mean: mu takes one free value per x, so the ML fitted
    // means are the group means 4 and 10; the deviance is the within-group SS.
    const xs = [_]f64{ 0, 0, 0, 1, 1, 1, 1 };
    const ys = [_]f64{ 3, 4, 5, 8, 9, 11, 12 };
    const r = try fit.fitNormal(a, try design(a, &xs), &ys, try ones(a, 7), 2, .log);
    // Stop rule: relative step < 1e-9; under quadratic convergence the
    // remaining error is below the last step, so 1e-8 is a safe bound.
    try close(r.beta[0], @log(4.0), 1e-8);
    try close(r.beta[1], @log(10.0 / 4.0), 1e-8);
    try close(r.deviance, 2 + 10, 1e-8); // (1+0+1) + (4+1+1+4)
    try close(r.scale, @sqrt(12.0 / 7.0), 1e-8);
    for (r.mu, xs) |m, x| try close(m, if (x == 0) 4 else 10, 1e-8);
    // Delta method on the group means (residuals sum to zero within a group,
    // so the observed information equals the expected one here):
    // var(log m0) = sigma^2/(n0 m0^2), var(b1) = that + sigma^2/(n1 m1^2).
    const v = 12.0 / 7.0;
    try close(r.cov[0], v / (3 * 16.0), 1e-7);
    try close(r.cov[3], v / (3 * 16.0) + v / (4 * 100.0), 1e-7);
}

test "STAT-GENMOD-002 published Normal/log sample: score, information and likelihood identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = try design(a, &nor_x);
    const f = try ones(a, nor_y.len);
    const r = try fit.fitNormal(a, x, &nor_y, f, 2, .log);

    // Score equations. g = H * (remaining error) and the remaining error is
    // below the stop rule 1e-9 (|beta_k| + 1e-6), so |g_j| <= sum_k |H_jk| e_k.
    var g: [2]f64 = undefined;
    var h: [4]f64 = undefined;
    fit.scoreInformation(x, &nor_y, f, 2, .log, r.beta, true, &g, &h);
    for (0..2) |j| {
        var bound: f64 = 0;
        for (0..2) |k| bound += @abs(h[j * 2 + k]) * 1e-9 * (@abs(r.beta[k]) + 1e-6);
        if (!(@abs(g[j]) <= bound)) {
            std.debug.print("score {d} = {d}, bound {d}\n", .{ j, g[j], bound });
            return error.TestUnexpectedResult;
        }
    }

    // Identities: deviance is the residual SS, the ML scale makes the scaled
    // deviance equal n, and the reported log likelihood is l(beta, sigma).
    try close(r.deviance, fit.sse(x, &nor_y, f, 2, .log, r.beta), 1e-14);
    var rss: f64 = 0;
    for (r.mu, nor_y) |m, y| rss += (y - m) * (y - m);
    try close(r.deviance, rss, 1e-13);
    try close(r.deviance / (r.scale * r.scale), 16, 1e-13);
    try close(r.loglik, fit.logLik(x, &nor_y, f, 2, .log, r.beta, r.scale), 1e-13);

    // Information by central second differences of the log likelihood in the
    // standardized coordinates u_i = theta_i / se_i, theta = (b0, b1, sigma),
    // with step 1e-3. There the negative Hessian is the inverse correlation
    // matrix and the fourth derivatives are O(1) (for b1: 8 se^2
    // sum(mu^2 x^4)/sum(mu^2 x^2) <= 8 * 0.0206^2 * 25 < 0.1), so truncation
    // step^2 |d4 l| / 12 < 1e-7 and rounding 4 eps |l| / step^2 ~ 3e-8 per
    // entry. Multiplied by correlation entries (at most 1, three terms) the
    // product differs from I by < 1e-5.
    const se = [3]f64{ @sqrt(r.cov[0]), @sqrt(r.cov[3]), r.scale_se };
    const theta = [3]f64{ r.beta[0], r.beta[1], r.scale };
    var info: [9]f64 = undefined;
    for (0..3) |i| for (0..3) |j| {
        var sum: f64 = 0;
        for ([_]f64{ 1, -1 }) |si| for ([_]f64{ 1, -1 }) |sj| {
            var point = theta;
            point[i] += si * 1e-3 * se[i];
            point[j] += sj * 1e-3 * se[j];
            sum += si * sj * fit.logLik(x, &nor_y, f, 2, .log, point[0..2], point[2]);
        };
        info[i * 3 + j] = -sum / 4e-6;
    };
    const corr = [9]f64{ 1, r.cov[1] / (se[0] * se[1]), 0, r.cov[2] / (se[0] * se[1]), 1, 0, 0, 0, 1 };
    for (0..3) |i| for (0..3) |j| {
        var product: f64 = 0;
        for (0..3) |k| product += info[i * 3 + k] * corr[k * 3 + j];
        if (!(@abs(product - @as(f64, if (i == j) 1 else 0)) <= 1e-5)) {
            std.debug.print("information product [{d},{d}] = {d}\n", .{ i, j, product });
            return error.TestUnexpectedResult;
        }
    };
    // The maximum is a maximum: nearby points have a lower log likelihood.
    for ([_]f64{ 1e-3, -1e-3 }) |d| {
        try expect(fit.logLik(x, &nor_y, f, 2, .log, &.{ r.beta[0] + d, r.beta[1] }, r.scale) < r.loglik);
        try expect(fit.logLik(x, &nor_y, f, 2, .log, &.{ r.beta[0], r.beta[1] + d }, r.scale) < r.loglik);
        try expect(fit.logLik(x, &nor_y, f, 2, .log, r.beta, r.scale + d) < r.loglik);
    }
}

test "STAT-GENMOD-002 FREQ=2 equals duplicated observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const xs = [_]f64{ 0, 1, 2, 3, 4 };
    const ys = [_]f64{ 2, 3, 3.5, 6, 9 };
    const twice_x = xs ++ xs;
    const twice_y = ys ++ ys;
    const two = try a.alloc(f64, 5);
    @memset(two, 2);
    for ([_]fit.Link{ .identity, .log }) |link| {
        const weighted = try fit.fitNormal(a, try design(a, &xs), &ys, two, 2, link);
        const doubled = try fit.fitNormal(a, try design(a, &twice_x), &twice_y, try ones(a, 10), 2, link);
        // Same sums in a different order: rounding only.
        try close(weighted.n, 10, 0);
        for (weighted.beta, doubled.beta) |w, d| try close(w, d, 1e-11);
        for (weighted.cov, doubled.cov) |w, d| try close(w, d, 1e-11);
        try close(weighted.scale, doubled.scale, 1e-11);
        try close(weighted.scale_se, doubled.scale_se, 1e-11);
        try close(weighted.deviance, doubled.deviance, 1e-11);
        try close(weighted.loglik, doubled.loglik, 1e-11);
    }
}

test "STAT-GENMOD-002 kernel failures are reported, never a fabricated fit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Constant regressor: collinear with the intercept.
    const xs = [_]f64{ 2, 2, 2, 2 };
    const ys = [_]f64{ 1, 2, 3, 5 };
    try std.testing.expectError(error.Singular, fit.fitNormal(a, try design(a, &xs), &ys, try ones(a, 4), 2, .identity));
    // Log link with a non-positive mean response has no documented start here.
    const negative = [_]f64{ -1, -2, -3, 1 };
    try std.testing.expectError(error.InvalidStart, fit.fitNormal(a, try design(a, &[_]f64{ 0, 1, 2, 3 }), &negative, try ones(a, 4), 2, .log));
}
