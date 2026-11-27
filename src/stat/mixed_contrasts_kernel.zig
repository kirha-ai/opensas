//! MIXED fixed/random inference: S154 physical pp.6702-6705 and6641-6645.
//! Joint covariance describes (beta_hat-beta,u_hat-u), not Var(u_hat).
const std = @import("std");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const matrix = @import("mixed_fit_matrix.zig");
const f = @import("../functions.zig");
pub const Joint = struct { p: usize, q: usize, coefficients: []const f64, covariance: []const f64, aliases: []const f64 };
pub fn joint(a: std.mem.Allocator, x: fixed.Design, z: random.Design, fitted: anytype, variances: []const f64) !Joint {
    const n = x.matrix.n;
    const p = x.matrix.p;
    const q = z.q;
    const dimension = p + q;
    if (z.n != n or x.y.len != n or x.weights.len != n or x.matrix.x.len != n * p or z.z.len != n * q or z.columns.len != q or fitted.coefficients.len != p or fitted.covariance.len != p * p) return error.InvalidInput;
    const coefficients = try a.alloc(f64, dimension);
    @memcpy(coefficients[0..p], fitted.coefficients);
    const covariance = try a.alloc(f64, dimension * dimension);
    @memset(covariance, 0);
    for (0..p) |i| for (0..p) |j| {
        covariance[i * dimension + j] = fitted.covariance[i * p + j];
    };
    if (q == 0) return .{ .p = p, .q = 0, .coefficients = coefficients, .covariance = covariance, .aliases = fitted.alias_coefficients };
    if (variances.len != z.components.len + 1) return error.InvalidInput;
    for (variances) |v| if (!std.math.isFinite(v) or v < 0) return error.UnsupportedNegativeVariance;
    const residual = variances[variances.len - 1];
    if (residual <= 0) return error.InvalidInput;
    const v = try a.alloc(f64, n * n);
    @memset(v, 0);
    for (0..n) |i| {
        if (x.weights[i] <= 0 or !std.math.isFinite(x.weights[i])) return error.InvalidInput;
        v[i * n + i] = residual / x.weights[i];
    }
    for (z.components) |component| if (component.kernel.len != n * n) return error.InvalidInput;
    for (z.components, variances[0..z.components.len]) |component, theta| for (v, component.kernel) |*target, value| {
        target.* += theta * value;
    };
    const vi = try matrix.inverse(a, v, n);
    const g = try a.alloc(f64, q);
    for (z.columns, 0..) |column, j| {
        var found: ?usize = null;
        for (z.components, 0..) |component, k| if (component.request_index == column.request_index and component.effect_index == column.effect_index and component.group_index == column.group_index) {
            if (found != null) return error.InvalidInput;
            found = k;
        };
        g[j] = variances[found orelse return error.InvalidInput];
    }
    const b = try a.alloc(f64, n * p);
    @memset(b, 0);
    for (0..n) |i| for (0..n) |j| for (0..p) |k| {
        b[i * p + k] += vi.values[i * n + j] * x.matrix.x[j * p + k];
    };
    const residuals = try a.dupe(f64, x.y);
    for (0..n) |i| for (0..p) |j| {
        residuals[i] -= x.matrix.x[i * p + j] * fitted.coefficients[j];
    };
    const py = try matrix.vector(a, vi.values, residuals, n);
    for (0..q) |j| {
        var value: f64 = 0;
        for (0..n) |i| value += z.z[i * q + j] * py[i];
        coefficients[p + j] = g[j] * value;
    }
    // C21=-G Z' V^-1 X C11. The negative sign is essential for narrow
    // inference: treating fixed/random prediction errors as independent fails.
    for (0..q) |i| for (0..p) |j| {
        var value: f64 = 0;
        for (0..n) |r| for (0..p) |k| {
            value += z.z[r * q + i] * b[r * p + k] * fitted.covariance[k * p + j];
        };
        covariance[(p + i) * dimension + j] = -g[i] * value;
        covariance[j * dimension + p + i] = -g[i] * value;
    };
    const projection = try a.dupe(f64, vi.values);
    for (0..n) |i| for (0..n) |j| for (0..p) |h| for (0..p) |k| {
        projection[i * n + j] -= b[i * p + h] * fitted.covariance[h * p + k] * b[j * p + k];
    };
    for (0..q) |i| for (i..q) |j| {
        var value: f64 = 0;
        for (0..n) |r| for (0..n) |s| {
            value += z.z[r * q + i] * projection[r * n + s] * z.z[s * q + j];
        };
        const result = (if (i == j) g[i] else 0) - g[i] * g[j] * value;
        covariance[(p + i) * dimension + p + j] = result;
        covariance[(p + j) * dimension + p + i] = result;
    };
    return .{ .p = p, .q = q, .coefficients = coefficients, .covariance = covariance, .aliases = fitted.alias_coefficients };
}
pub fn estimable(j: Joint, l: []const f64, tolerance: f64) bool {
    if (l.len != j.p + j.q or j.aliases.len != j.p * j.p or !std.math.isFinite(tolerance) or tolerance <= 0 or tolerance >= 1) return false;
    var scale: f64 = 0;
    for (l[0..j.p]) |v| scale = @max(scale, @abs(v));
    if (scale == 0) scale = 1;
    for (0..j.p) |c| {
        var projected: f64 = 0;
        for (0..j.p) |k| projected += l[k] * j.aliases[c * j.p + k];
        if (@abs(l[c] - projected) > scale * tolerance) return false;
    }
    return true;
}
pub const Tail = enum { two, lower, upper };
pub const Estimate = struct { estimable: bool, estimate: ?f64 = null, se: ?f64 = null, t: ?f64 = null, p: ?f64 = null, df: f64, lower: ?f64 = null, upper: ?f64 = null };
pub fn estimate(j: Joint, l: []const f64, df: f64, alpha: f64, tail: Tail, tolerance: f64) !Estimate {
    return estimateWithLimits(j, l, df, alpha, tail, tolerance, true);
}
pub fn estimateWithLimits(j: Joint, l: []const f64, df: f64, alpha: f64, tail: Tail, tolerance: f64, want_limits: bool) !Estimate {
    if (!std.math.isFinite(df) or df <= 0 or !std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1 or !std.math.isFinite(tolerance) or tolerance <= 0 or tolerance >= 1) return error.InvalidInput;
    if (!estimable(j, l, tolerance)) return .{ .estimable = false, .df = df };
    var value: f64 = 0;
    var variance: f64 = 0;
    const n = j.p + j.q;
    for (l, j.coefficients) |v, beta| value += v * beta;
    for (0..n) |r| for (0..n) |c| {
        variance += l[r] * j.covariance[r * n + c] * l[c];
    };
    if (!std.math.isFinite(value) or !std.math.isFinite(variance) or variance < 0) return error.InvalidCovariance;
    var result: Estimate = .{ .estimable = true, .estimate = value, .se = @sqrt(variance), .df = df };
    if (variance == 0) return result;
    const t = value / @sqrt(variance);
    if (!std.math.isFinite(t)) return error.NumericalDomain;
    const two = f.betaI(df / (df + t * t), df / 2, 0.5);
    result.t = t;
    result.p = switch (tail) {
        .two => two,
        .lower => if (t < 0) two / 2 else 1 - two / 2,
        .upper => if (t > 0) two / 2 else 1 - two / 2,
    };
    if (!want_limits) return result;
    const target = 1 - alpha / (if (tail == .two) @as(f64, 2) else 1);
    const endpoint_tail = f.betaI(df / (df + 1e12), df / 2, 0.5) / 2;
    if (target <= endpoint_tail or target >= 1 - endpoint_tail or target == 0 or target == 1) return error.NumericalDomain;
    const critical = f.bisectCdf(.t, target, df, 0, -1e6, 1e6);
    if (tail != .lower) result.lower = value - critical * @sqrt(variance);
    if (tail != .upper) result.upper = value + critical * @sqrt(variance);
    return result;
}
pub const Contrast = struct { estimable: bool, num_df: usize = 0, den_df: f64, f: ?f64 = null, p: ?f64 = null };
pub fn contrast(a: std.mem.Allocator, j: Joint, l: []const f64, rows: usize, df: f64, tolerance: f64) !Contrast {
    const n = j.p + j.q;
    if (rows == 0 or l.len != rows * n or df <= 0 or !std.math.isFinite(df)) return error.InvalidInput;
    const estimates = try a.alloc(f64, rows);
    @memset(estimates, 0);
    const covariance = try a.alloc(f64, rows * rows);
    @memset(covariance, 0);
    for (0..rows) |r| {
        const row = l[r * n ..][0..n];
        if (!estimable(j, row, tolerance)) return .{ .estimable = false, .den_df = df };
        for (row, j.coefficients) |v, beta| estimates[r] += v * beta;
        for (0..rows) |s| for (0..n) |h| for (0..n) |k| {
            covariance[r * rows + s] += row[h] * j.covariance[h * n + k] * l[s * n + k];
        };
    }
    const zeros = try a.alloc(f64, rows);
    @memset(zeros, 0);
    const ranked = try @import("reg_fit.zig").fit(a, covariance, zeros, rows, rows, null);
    if (ranked.rank == 0) return .{ .estimable = true, .num_df = 0, .den_df = df };
    const chosen = try a.alloc(usize, ranked.rank);
    var next: usize = 0;
    for (ranked.aliased, 0..) |alias, k| if (!alias) {
        chosen[next] = k;
        next += 1;
    };
    const reduced = try a.alloc(f64, chosen.len * chosen.len);
    const e = try a.alloc(f64, chosen.len);
    for (chosen, 0..) |r, i| {
        e[i] = estimates[r];
        for (chosen, 0..) |s, k| reduced[i * chosen.len + k] = covariance[r * rows + s];
    }
    const inverse = try matrix.inverse(a, reduced, chosen.len);
    const wald = matrix.dot(e, try matrix.vector(a, inverse.values, e, e.len));
    if (!std.math.isFinite(wald) or wald < 0) return error.InvalidCovariance;
    const q: f64 = @floatFromInt(chosen.len);
    const statistic = wald / q;
    return .{ .estimable = true, .num_df = chosen.len, .den_df = df, .f = statistic, .p = f.betaI(df / (df + q * statistic), df / 2, q / 2) };
}

test "STAT-MIXED-009 joint BLUE BLUP covariance has correct cross signs and zero-G boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x: fixed.Design = .{ .matrix = .{ .x = @constCast(&[_]f64{ 1, 1, 1, 1 }), .n = 4, .p = 1, .source_rows = &.{ 0, 1, 2, 3 }, .columns = &.{.{ .effect_name = "Intercept", .effect_index = null, .class_values = &.{} }}, .classes = &.{} }, .y = &.{ 1, 3, 5, 7 }, .weights = &.{ 1, 1, 1, 1 }, .source_rows = &.{ 1, 2, 3, 4 } };
    const columns = [_]random.Column{.{ .name = "group", .effect_index = 0, .request_index = 0, .subject_index = 0, .group_index = 0 }} ** 2;
    const z: random.Design = .{ .n = 4, .q = 2, .z = &.{ 1, 0, 1, 0, 0, 1, 0, 1 }, .columns = &columns, .components = &.{.{ .name = "group", .kernel = &.{ 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1 }, .columns = 2, .effect_index = 0, .request_index = 0, .group_index = 0 }}, .subject_count = 1, .max_obs_per_subject = 4, .first_effect_levels = 2 };
    // Two groups, two observations each, G=2I,R=I. Group means2 and6;
    // GLSmean4, shrinkage4/5, prediction-error covariance derived blockwise.
    const fitted = .{ .coefficients = @as([]const f64, &.{4}), .covariance = @as([]const f64, &.{1.25}), .alias_coefficients = @as([]const f64, &.{1}) };
    const j = try joint(a, x, z, fitted, &.{ 2, 1 });
    for ([_]f64{ 4, -1.6, 1.6 }, j.coefficients) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
    for ([_]f64{ 1.25, -1, -1, -1, 1.2, 0.8, -1, 0.8, 1.2 }, j.covariance) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
    const e = try estimate(j, &.{ 1, 1, 0 }, 8, 0.05, .two, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f64, 2.4), e.estimate.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.45), e.se.? * e.se.?, 1e-12);
    const reduced = try joint(a, x, z, .{ .coefficients = @as([]const f64, &.{4}), .covariance = @as([]const f64, &.{0.25}), .alias_coefficients = @as([]const f64, &.{1}) }, &.{ 0, 1 });
    try std.testing.expectEqualSlices(f64, &.{ 4, 0, 0 }, reduced.coefficients);
    const zero = try estimate(reduced, &.{ 0, 1, -1 }, 8, 0.05, .two, 1e-4);
    try std.testing.expect(zero.estimable and zero.estimate.? == 0 and zero.se.? == 0 and zero.t == null and zero.p == null);
    try std.testing.expectError(error.UnsupportedNegativeVariance, joint(a, x, z, fitted, &.{ -0.1, 1 }));
}

test "STAT-MIXED-009 dependent CONTRAST rows use covariance rank and fixed nonestimability stays typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const j: Joint = .{ .p = 1, .q = 2, .coefficients = &.{ 4, -1.6, 1.6 }, .covariance = &.{ 1.25, -1, -1, -1, 1.2, 0.8, -1, 0.8, 1.2 }, .aliases = &.{1} };
    const result = try contrast(a, j, &.{ 0, 1, -1, 0, 2, -2 }, 2, 8, 1e-4);
    try std.testing.expect(result.estimable);
    try std.testing.expectEqual(@as(usize, 1), result.num_df);
    try std.testing.expectApproxEqAbs(@as(f64, 12.8), result.f.?, 1e-10);
    const singular: Joint = .{ .p = 2, .q = 0, .coefficients = &.{ 2, 0 }, .covariance = &.{ 1, 0, 0, 0 }, .aliases = &.{ 1, 0, 1, 0 } };
    try std.testing.expect(!(try estimate(singular, &.{ 1, 0 }, 8, 0.05, .two, 1e-4)).estimable);
    try std.testing.expect((try estimate(singular, &.{ 1, 1 }, 8, 0.05, .two, 1e-4)).estimable);
}
