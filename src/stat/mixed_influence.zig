//! MIXED noniterative deletion diagnostics, S154 physical pp.6714-6719.
//! Reduced GLS is actually recomputed with the covariance submatrix. Profiles
//! preserve covariance ratios and recompute ONLY the common residual scale.
const std = @import("std");
const fit = @import("mixed_fit.zig");
const matrix = @import("mixed_fit_matrix.zig");
const A = std.mem.Allocator;
pub const Mode = enum { fixed_covariance, profile_reml, profile_ml };
pub const Deletion = struct { indices: []const usize };
pub const Status = enum { ok, rank_changed, insufficient_observations, zero_deleted_scale, numerical_failure };
pub const Row = struct {
    deleted: []const usize,
    status: Status = .ok,
    coefficients: []const f64 = &.{},
    covariance: []const f64 = &.{},
    scale_ratio: ?f64 = null,
    observed: ?f64 = null,
    predicted: ?f64 = null,
    residual: ?f64 = null,
    leverage: ?f64 = null,
    student: ?f64 = null,
    press_residual: ?f64 = null,
    press: ?f64 = null,
    cook_d: ?f64 = null,
    external_student: ?f64 = null,
    dffits: ?f64 = null,
    mdffits: ?f64 = null,
    covratio: ?f64 = null,
    covtrace: ?f64 = null,
    likelihood_distance: ?f64 = null,
};
pub const Report = struct { full: fit.GLS, rows: []const Row };
fn subset(a: A, c: []const f64, p: usize, indices: []const usize) ![]f64 {
    const result = try a.alloc(f64, indices.len * indices.len);
    for (indices, 0..) |j, r| for (indices, 0..) |k, s| {
        result[r * indices.len + s] = c[j * p + k];
    };
    return result;
}
fn quadratic(m: []const f64, v: []const f64) f64 {
    var result: f64 = 0;
    for (v, 0..) |x, i| for (v, 0..) |y, j| {
        result += x * m[i * v.len + j] * y;
    };
    return result;
}
fn predicted(model: fit.Model, coefficients: []const f64, i: usize) f64 {
    var value: f64 = 0;
    for (model.x[i * model.p ..][0..model.p], coefficients) |x, b| value += x * b;
    return value;
}
fn predictionVariance(model: fit.Model, covariance: []const f64, i: usize) f64 {
    return quadratic(covariance, model.x[i * model.p ..][0..model.p]);
}
pub fn analyse(a: A, model: fit.Model, v: []const f64, deletions: []const Deletion, mode: Mode) !Report {
    // Explicit bounded direct-refit implementation, not a hidden approximation.
    if (model.n > 128 or model.p > 64 or deletions.len > 128) return error.ResourceLimit;
    const full = try fit.knownCovarianceMatrix(a, model, v);
    const rank = full.rank;
    const df: f64 = @floatFromInt(if (mode == .profile_ml) model.n else model.n - rank);
    if (mode != .fixed_covariance and (!(df > 0) or @abs(full.quadratic - df) > 1e-7 * @max(1, df))) return error.InvalidProfileScale;
    const full_c = try subset(a, full.covariance, model.p, full.independent);
    const ci = try matrix.inverse(a, full_c, rank);
    const vi = try matrix.inverse(a, v, model.n);
    const rows = try a.alloc(Row, deletions.len);
    for (deletions, rows) |deletion, *result| {
        result.* = .{ .deleted = try a.dupe(usize, deletion.indices) };
        if (deletion.indices.len == 0) return error.InvalidInput;
        const removed = try a.alloc(bool, model.n);
        @memset(removed, false);
        for (deletion.indices) |i| {
            if (i >= model.n or removed[i]) return error.InvalidInput;
            removed[i] = true;
        }
        if (deletion.indices.len == 1) {
            const i = deletion.indices[0];
            const mean = predicted(model, full.coefficients, i);
            const resid = model.y[i] - mean;
            var leverage: f64 = 0;
            for (0..model.p) |j| for (0..model.p) |k| for (0..model.n) |h| {
                leverage += model.x[i * model.p + j] * full.covariance[j * model.p + k] * model.x[h * model.p + k] * vi.values[h * model.n + i];
            };
            const variance = v[i * model.n + i] - predictionVariance(model, full.covariance, i);
            result.observed = model.y[i];
            result.predicted = mean;
            result.residual = resid;
            result.leverage = leverage;
            if (variance > 64 * std.math.floatEps(f64) * @abs(v[i * model.n + i])) result.student = resid / @sqrt(variance);
        }
        const n = model.n - deletion.indices.len;
        if (n == 0) {
            result.status = .insufficient_observations;
            continue;
        }
        const kept = try a.alloc(usize, n);
        var next: usize = 0;
        for (removed, 0..) |drop, i| if (!drop) {
            kept[next] = i;
            next += 1;
        };
        const x = try a.alloc(f64, n * model.p);
        const y = try a.alloc(f64, n);
        const weights = if (model.weights != null) try a.alloc(f64, n) else null;
        for (kept, 0..) |source, i| {
            @memcpy(x[i * model.p ..][0..model.p], model.x[source * model.p ..][0..model.p]);
            y[i] = model.y[source];
            if (weights) |w| w[i] = model.weights.?[source];
        }
        const reduced_v = try a.alloc(f64, n * n);
        for (kept, 0..) |source, i| for (kept, 0..) |other, j| {
            reduced_v[i * n + j] = v[source * model.n + other];
        };
        const reduced = fit.knownCovarianceMatrix(a, .{ .x = x, .y = y, .n = n, .p = model.p, .weights = weights, .has_intercept = model.has_intercept, .singular = model.singular }, reduced_v) catch |err| {
            if (err == error.OutOfMemory) return err;
            result.status = if (err == error.NotPositiveDefinite) .numerical_failure else .rank_changed;
            continue;
        };
        if (!std.mem.eql(usize, full.independent, reduced.independent)) {
            result.status = .rank_changed;
            continue;
        }
        result.coefficients = reduced.coefficients;
        var press: f64 = 0;
        for (deletion.indices) |i| {
            const residual = model.y[i] - predicted(model, reduced.coefficients, i);
            press += residual * residual;
            if (deletion.indices.len == 1) result.press_residual = residual;
        }
        result.press = press;
        const delta = try a.alloc(f64, rank);
        for (full.independent, 0..) |j, k| delta[k] = full.coefficients[j] - reduced.coefficients[j];
        const distance = quadratic(ci.values, delta);
        result.cook_d = distance / @as(f64, @floatFromInt(rank));
        var factor: f64 = 1;
        if (mode != .fixed_covariance) {
            const reduced_df = if (mode == .profile_ml) n else n - rank;
            if (reduced_df == 0) {
                result.status = .insufficient_observations;
                continue;
            }
            factor = reduced.quadratic / @as(f64, @floatFromInt(reduced_df));
            if (!(factor > 0) or !std.math.isFinite(factor)) {
                result.status = .zero_deleted_scale;
                continue;
            }
        }
        result.scale_ratio = factor;
        const covariance = try a.dupe(f64, reduced.covariance);
        for (covariance) |*cell| cell.* *= factor;
        result.covariance = covariance;
        // With a nonprofiled covariance held at its full-data estimate, external
        // influence fields are unavailable (S154 pp.6715-6718). Do not fabricate
        // a fresh covariance estimate or set externally studentized=internally.
        if (mode == .fixed_covariance) continue;
        const dc = try subset(a, covariance, model.p, full.independent);
        const dci = try matrix.inverse(a, dc, rank);
        result.mdffits = quadratic(dci.values, delta) / @as(f64, @floatFromInt(rank));
        result.covratio = @exp(dci.logdet - ci.logdet);
        var trace: f64 = 0;
        for (0..rank) |i| for (0..rank) |j| {
            trace += ci.values[i * rank + j] * dc[j * rank + i];
        };
        result.covtrace = @abs(trace - @as(f64, @floatFromInt(rank)));
        // Evaluate the full-data likelihood at the DELETE-CASE coefficient/scale,
        // not the likelihood of the shortened dataset (S154 physical p.6719).
        const raw_distance = df * @log(factor) + (full.quadratic + distance) / factor - full.quadratic;
        const cancellation_bound = 128 * std.math.floatEps(f64) * (@abs(df * @log(factor)) + @abs((full.quadratic + distance) / factor) + @abs(full.quadratic) + 1);
        result.likelihood_distance = if (raw_distance >= -cancellation_bound) @max(0, raw_distance) else return error.NumericalFailure;
        if (deletion.indices.len == 1) {
            const i = deletion.indices[0];
            if (result.student) |student| result.external_student = student / @sqrt(factor);
            const variance = factor * predictionVariance(model, full.covariance, i);
            if (variance > 0) result.dffits = (predicted(model, full.coefficients, i) - predicted(model, reduced.coefficients, i)) / @sqrt(variance);
        }
    }
    return .{ .full = full, .rows = rows };
}

pub fn singletonDeletions(a: A, n: usize) ![]const Deletion {
    const out = try a.alloc(Deletion, n);
    for (out, 0..) |*d, i| d.* = .{ .indices = try a.dupe(usize, &.{i}) };
    return out;
}

test "MIXED013 profiled scalar REML deletion matches hand-computed mean variance and influence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = fit.Model{ .x = &.{ 1, 1, 1, 1 }, .y = &.{ 1, 3, 5, 7 }, .n = 4, .p = 1 };
    const sigma: f64 = 20.0 / 3.0;
    var v = [_]f64{0} ** 16;
    for (0..4) |i| v[i * 4 + i] = sigma;
    const result = try analyse(a, model, &v, &.{.{ .indices = &.{0} }}, .profile_reml);
    const r = result.rows[0];
    try std.testing.expectEqual(Status.ok, r.status);
    try std.testing.expectApproxEqAbs(@as(f64, 4), r.predicted.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5), r.coefficients[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), r.leverage.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -4), r.press_residual.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 16), r.press.?, 1e-12);
    try std.testing.expectApproxEqAbs(-3 / @sqrt(@as(f64, 5)), r.student.?, 1e-12);
    try std.testing.expectApproxEqAbs(-@sqrt(@as(f64, 3)), r.external_student.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), r.scale_ratio.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), r.cook_d.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1), r.dffits.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), r.covratio.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), r.covtrace.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), r.mdffits.?, 1e-12);
    try std.testing.expectApproxEqAbs(3 * @log(@as(f64, 0.6)) + 3, r.likelihood_distance.?, 1e-12);
    const fixed_result = try analyse(a, model, &v, &.{.{ .indices = &.{0} }}, .fixed_covariance);
    try std.testing.expect(fixed_result.rows[0].external_student == null and fixed_result.rows[0].dffits == null and fixed_result.rows[0].covratio == null);
    try std.testing.expectApproxEqAbs(r.cook_d.?, fixed_result.rows[0].cook_d.?, 1e-12);
}

test "MIXED013 oblique leverage may be negative and rank-changing deletions stay unavailable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = fit.Model{ .x = &.{ 1, 1 }, .y = &.{ 2, 5 }, .n = 2, .p = 1 };
    const r = try analyse(a, model, &.{ 1, 2, 2, 9 }, try singletonDeletions(a, 2), .fixed_covariance);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 6.0), r.rows[0].leverage.?, 2e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0 / 6.0), r.rows[1].leverage.?, 2e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.rows[0].leverage.? + r.rows[1].leverage.?, 2e-12);
    const high = fit.Model{ .x = &.{ 1, 0, 1, 0, 1, 0, 1, 1 }, .y = &.{ 1, 2, 4, 8 }, .n = 4, .p = 2 };
    var v = [_]f64{0} ** 16;
    for (0..4) |i| v[i * 4 + i] = 1;
    const deleted = try analyse(a, high, &v, &.{ .{ .indices = &.{3} }, .{ .indices = &.{ 0, 1, 2, 3 } } }, .fixed_covariance);
    try std.testing.expectEqual(Status.rank_changed, deleted.rows[0].status);
    try std.testing.expect(deleted.rows[0].cook_d == null and deleted.rows[0].press == null);
    try std.testing.expectApproxEqAbs(@as(f64, 1), deleted.rows[0].leverage.?, 1e-12);
    try std.testing.expect(deleted.rows[0].student == null);
    try std.testing.expectEqual(Status.insufficient_observations, deleted.rows[1].status);
    try std.testing.expectError(error.InvalidInput, analyse(a, high, &v, &.{.{ .indices = &.{ 0, 0 } }}, .fixed_covariance));
    var over = high;
    over.n = 129;
    try std.testing.expectError(error.ResourceLimit, analyse(a, over, &v, &.{.{ .indices = &.{0} }}, .fixed_covariance));
}

test "MIXED013 near-collinear reparameterization preserves prediction and Cook diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const epsilon: f64 = 1e-4;
    const predictors = [_]f64{ 0, 1, 2, 3, 4, 5 };
    const third = [_]f64{ 1, -1, 2, 0, -2, 1 };
    var x: [18]f64 = undefined;
    var near: [18]f64 = undefined;
    var v = [_]f64{0} ** 36;
    for (predictors, third, 0..) |p, z, i| {
        x[i * 3] = 1;
        x[i * 3 + 1] = p;
        x[i * 3 + 2] = z;
        near[i * 3] = 1;
        near[i * 3 + 1] = p;
        near[i * 3 + 2] = p + epsilon * z;
        v[i * 6 + i] = 1;
    }
    const y = [_]f64{ 1, 2, 4, 3, 7, 8 };
    const original = fit.Model{ .x = &x, .y = &y, .n = 6, .p = 3, .singular = 1e-12 };
    var transformed = original;
    transformed.x = &near;
    const sets = try singletonDeletions(a, 6);
    const base = try analyse(a, original, &v, sets, .fixed_covariance);
    const changed = try analyse(a, transformed, &v, sets, .fixed_covariance);
    // The invertible x2=x1+epsilon*z transform has squared condition growth
    // O(1/epsilon²). This a-priori floating budget is not fitted to discrepancies.
    const tolerance = 256 * std.math.floatEps(f64) / (epsilon * epsilon);
    for (base.rows, changed.rows) |b, c| {
        try std.testing.expectEqual(Status.ok, c.status);
        try std.testing.expectApproxEqAbs(b.press_residual.?, c.press_residual.?, tolerance * 8);
        try std.testing.expectApproxEqAbs(b.cook_d.?, c.cook_d.?, tolerance * 8);
    }
}

test "MIXED013 complete public Absorb sample basic diagnostics obey independent group formulas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Public Example84.7 full input; iterative covariance updates are NOT
    // substituted by these fixed-covariance diagnostics.
    const groups = [4][6]f64{ .{ 164, 172, 168, 177, 156, 195 }, .{ 178, 191, 197, 182, 185, 177 }, .{ 175, 193, 178, 171, 163, 176 }, .{ 155, 166, 149, 164, 170, 168 } };
    const means = [_]f64{ 172, 185, 176, 162 };
    const variances = [_]f64{ 178, 60.4, 97.6, 67.6 };
    var x = [_]f64{0} ** 96;
    var y: [24]f64 = undefined;
    var v = [_]f64{0} ** 576;
    for (groups, 0..) |group, g| for (group, 0..) |value, j| {
        const i = g * 6 + j;
        y[i] = value;
        x[i * 4 + g] = 1;
        v[i * 24 + i] = variances[g];
    };
    const model = fit.Model{ .x = &x, .y = &y, .n = 24, .p = 4, .has_intercept = false };
    const report = try analyse(a, model, &v, try singletonDeletions(a, 24), .fixed_covariance);
    const tolerance = 64 * std.math.floatEps(f64) * 24 * 195 * 3; // n sums, observed scale195, variance condition<3
    for (report.rows, 0..) |r, i| {
        const g = i / 6;
        const residual = y[i] - means[g];
        const press = residual * 6.0 / 5.0;
        const delta = residual / 5;
        try std.testing.expectEqual(Status.ok, r.status);
        try std.testing.expectApproxEqAbs(means[g], r.predicted.?, tolerance);
        try std.testing.expectApproxEqAbs(residual, r.residual.?, tolerance);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 6.0), r.leverage.?, tolerance);
        try std.testing.expectApproxEqAbs(press, r.press_residual.?, tolerance);
        try std.testing.expectApproxEqAbs(delta * delta / (variances[g] / 6) / 4, r.cook_d.?, tolerance);
        try std.testing.expectApproxEqAbs(residual / @sqrt(variances[g] * 5 / 6), r.student.?, tolerance);
        try std.testing.expect(r.external_student == null);
    }
}

test "MIXED013 grouped deletion and ML scale use the proper retained sample size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = fit.Model{ .x = &.{ 1, 1, 1, 1 }, .y = &.{ 1, 3, 5, 7 }, .n = 4, .p = 1 };
    var v = [_]f64{0} ** 16;
    for (0..4) |i| v[i * 4 + i] = 20.0 / 3.0;
    const grouped = try analyse(a, model, &v, &.{.{ .indices = &.{ 0, 1 } }}, .profile_reml);
    const r = grouped.rows[0];
    try std.testing.expectApproxEqAbs(@as(f64, 34), r.press.?, 1e-12);
    try std.testing.expect(r.press_residual == null and r.dffits == null);
    try std.testing.expectApproxEqAbs(@as(f64, 2.4), r.cook_d.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4), r.mdffits.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), r.covratio.?, 1e-12);
    try std.testing.expectApproxEqAbs(15 + 3 * @log(@as(f64, 0.3)), r.likelihood_distance.?, 1e-12);
    for (0..4) |i| v[i * 4 + i] = 5;
    const ml = try analyse(a, model, &v, &.{.{ .indices = &.{0} }}, .profile_ml);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0 / 15.0), ml.rows[0].scale_ratio.?, 1e-12);
    try std.testing.expectApproxEqAbs(5 + 4 * @log(@as(f64, 8.0 / 15.0)), ml.rows[0].likelihood_distance.?, 1e-12);
    const perfect = fit.Model{ .x = &.{ 1, 1, 1 }, .y = &.{ 0, 0, 1 }, .n = 3, .p = 1 };
    var pv = [_]f64{0} ** 9;
    for (0..3) |i| pv[i * 3 + i] = 1.0 / 3.0;
    const zero = try analyse(a, perfect, &pv, &.{.{ .indices = &.{2} }}, .profile_reml);
    try std.testing.expectEqual(Status.zero_deleted_scale, zero.rows[0].status);
    try std.testing.expect(zero.rows[0].cook_d != null and zero.rows[0].external_student == null and zero.rows[0].likelihood_distance == null);
}
