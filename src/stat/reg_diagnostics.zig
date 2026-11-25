//! Ordered REG rank decisions and alias equations (STAT-COMMON-003).
//! S154 physical pp.61, 8574, 8588, 8624, 8649: generalized inverses,
//! SINGULAR, TOL/VIF, nonunique estimates and the ordered pivot/CSS rule.
//! The underlying solver remains reg_fit's scaled QR. We select columns using
//! residual sums of squares (the sweep pivots), then fit the retained design.
//! No normal-equation inversion and no duplicate TOL/VIF implementation.
const std = @import("std");
const diag = @import("../diag.zig");
const qr = @import("reg_fit.zig");
const A = std.mem.Allocator;
const nan = std.math.nan(f64);
pub const default_singular: f64 = 1e-9;
pub const RankStatus = enum { full_rank, nearly_singular, rank_deficient };

pub const Result = struct {
    fit: qr.Fit,
    /// Row j expresses original column j in retained original columns k.
    /// Retained rows are identity rows; omitted coefficient slots are zero.
    /// On positive-weight rows, X = X * transpose(alias_coefficients),
    /// up to the declared rank tolerance. Ignored rows need not obey aliases.
    alias_coefficients: []f64,
    /// Ordered residual SS / CSS (USS without intercept). Intercept: NaN.
    /// These are sequential rank pivots, NOT the final-model TOL statistic.
    pivot_tolerance: []f64,
    status: RankStatus,
    singular: f64,

    pub fn deinit(self: *Result, a: A) void {
        self.fit.deinit(a);
        a.free(self.alias_coefficients);
        a.free(self.pivot_tolerance);
        self.* = undefined;
    }
};

const Sum = struct {
    value: f64 = 0,
    correction: f64 = 0,
    fn add(self: *Sum, x: f64) void {
        const next = self.value + x;
        self.correction += if (@abs(self.value) >= @abs(x)) (self.value - next) + x else (x - next) + self.value;
        self.value = next;
    }
    fn total(self: Sum) f64 {
        return self.value + self.correction;
    }
};

/// Rank selection uses the SAS pivot < SINGULAR*CSS rule. A zero column or
/// zero-CSS column after the intercept is aliased. The first column must be
/// all ones when has_intercept=true. Missing rows must be filtered upstream.
/// Weights are nonnegative precision weights (or FREQ*WEIGHT); zero-weight
/// rows do not influence rank. Positive weights are normalized internally.
///
/// The existing QR solver has an additional roundoff floor (relative column
/// residual norm 1e-12). If it cannot represent a design retained by this policy,
/// return ExecError rather than silently changing rank. Likewise nonfinite
/// inputs/intermediates, invalid dimensions/policy and weight underflow fail.
/// Nearly singular means an accepted pivot <= sqrt(SINGULAR); it is a warning
/// classification, not a second exclusion threshold. Scaling a predictor or
/// multiplying all positive weights by the same factor preserves the policy.
///
/// The embedded fit is in ORIGINAL column order. Its covariance_unscaled is a
/// reflexive generalized inverse of X'WX for exact dependencies (not a claim
/// of a Moore-Penrose inverse). Aliased estimates are 0, SE/covariance NaN.
pub fn fit(a: A, x: []const f64, y: []const f64, n: usize, p: usize, weights: ?[]const f64, has_intercept: bool, singular: f64) diag.Error!Result {
    const np = std.math.mul(usize, n, p) catch return error.ExecError;
    const pp = std.math.mul(usize, p, p) catch return error.ExecError;
    if (n == 0 or p == 0 or x.len != np or y.len != n or !std.math.isFinite(singular) or !(singular > 0 and singular < 1)) return error.ExecError;
    if (weights) |w| if (w.len != n) return error.ExecError;
    for (x) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (y) |v| if (!std.math.isFinite(v)) return error.ExecError;
    if (has_intercept) for (0..n) |i| {
        if (x[i * p] != 1) return error.ExecError;
    };

    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const tmp = arena.allocator();
    const w = try tmp.alloc(f64, n);
    var max_weight: f64 = if (weights == null) 1 else 0;
    if (weights) |ws| for (ws) |v| {
        if (!std.math.isFinite(v) or v < 0) return error.ExecError;
        max_weight = @max(max_weight, v);
    };
    if (max_weight == 0) return error.ExecError;
    var positive: usize = 0;
    var sumw: Sum = .{};
    for (w, 0..) |*v, i| {
        const raw = if (weights) |ws| ws[i] else 1;
        v.* = raw / max_weight;
        if (raw > 0 and v.* == 0) return error.ExecError;
        if (v.* > 0) positive += 1;
        sumw.add(v.*);
    }
    const normalized = try tmp.alloc(f64, np);
    const scales = try tmp.alloc(f64, p);
    for (0..p) |j| {
        var scale: f64 = 0;
        for (0..n) |i| if (w[i] > 0) {
            scale = @max(scale, @abs(x[i * p + j]));
        };
        scales[j] = if (scale == 0) 1 else scale;
        // Ignored rows must not overflow a scaled auxiliary regression.
        for (0..n) |i| normalized[i * p + j] = if (w[i] > 0) x[i * p + j] / scales[j] else 0;
    }
    const active = try tmp.alloc(usize, p);
    const alias = try tmp.alloc(bool, p);
    @memset(alias, true);
    const pivots = try tmp.alloc(f64, p);
    @memset(pivots, nan);
    const target = try tmp.alloc(f64, n);
    var rank: usize = 0;
    var near = false;
    for (0..p) |j| {
        var sx: Sum = .{};
        for (0..n) |i| {
            target[i] = normalized[i * p + j];
            sx.add(w[i] * target[i]);
        }
        const center = if (has_intercept and j != 0) sx.total() / sumw.total() else 0;
        var css: Sum = .{};
        for (target, w) |v, wi| css.add(wi * (v - center) * (v - center));
        const denominator = css.total();
        if (!std.math.isFinite(denominator) or denominator < 0) return error.ExecError;
        if (denominator == 0) {
            pivots[j] = 0;
            continue;
        }
        var residual_ss = denominator;
        if (rank > 0) {
            const design = try subset(tmp, normalized, n, p, active[0..rank]);
            var auxiliary = try qr.fit(tmp, design, target, n, rank, w);
            defer auxiliary.deinit(tmp);
            if (auxiliary.rank != rank) return error.ExecError;
            residual_ss = auxiliary.sse;
        }
        const ratio = residual_ss / denominator;
        if (!std.math.isFinite(ratio) or ratio < 0) return error.ExecError;
        pivots[j] = if (has_intercept and j == 0) nan else ratio;
        if (ratio < singular or rank == positive) continue;
        if (!(has_intercept and j == 0) and ratio <= @sqrt(singular)) near = true;
        alias[j] = false;
        active[rank] = j;
        rank += 1;
    }

    const equations = try tmp.alloc(f64, pp);
    @memset(equations, 0);
    const biased = try tmp.alloc(bool, p);
    @memset(biased, false);
    if (rank > 0) {
        const design = try subset(tmp, normalized, n, p, active[0..rank]);
        for (0..p) |j| {
            if (!alias[j]) {
                equations[j * p + j] = 1;
                continue;
            }
            for (0..n) |i| target[i] = normalized[i * p + j];
            var auxiliary = try qr.fit(tmp, design, target, n, rank, w);
            defer auxiliary.deinit(tmp);
            if (auxiliary.rank != rank) return error.ExecError;
            // Suppress roundoff in normalized coordinates, never by an absolute
            // original-unit cutoff (which would lose e.g. 1e-15 * a large column).
            var largest: f64 = 1;
            for (auxiliary.coefficients) |c| largest = @max(largest, @abs(c));
            const cleanup = 64 * std.math.floatEps(f64) * @as(f64, @floatFromInt(@max(n, p))) * largest;
            for (active[0..rank], auxiliary.coefficients) |k, c| {
                if (@abs(c) <= cleanup) continue;
                const coefficient = (c * scales[j]) / scales[k];
                if (!std.math.isFinite(coefficient) or coefficient == 0) return error.ExecError;
                equations[j * p + k] = coefficient;
                biased[k] = true;
            }
        }
    }

    const design = if (rank > 0) try subset(tmp, x, n, p, active[0..rank]) else x;
    var base = try qr.fit(tmp, design, y, n, if (rank > 0) rank else p, weights);
    defer base.deinit(tmp);
    if (base.rank != rank) return error.ExecError;
    var expanded = base;
    inline for (.{ "coefficients", "covariance", "covariance_unscaled", "se", "aliased", "biased", "fitted", "residuals", "leverage" }) |field| @field(expanded, field) = &.{};
    errdefer expanded.deinit(a);
    expanded.coefficients = try a.alloc(f64, p);
    @memset(expanded.coefficients, 0);
    expanded.se = try a.alloc(f64, p);
    @memset(expanded.se, nan);
    expanded.covariance = try a.alloc(f64, pp);
    @memset(expanded.covariance, nan);
    expanded.covariance_unscaled = try a.alloc(f64, pp);
    @memset(expanded.covariance_unscaled, 0);
    expanded.aliased = try a.dupe(bool, alias);
    expanded.biased = try a.dupe(bool, biased);
    expanded.fitted = try a.dupe(f64, base.fitted);
    expanded.residuals = try a.dupe(f64, base.residuals);
    expanded.leverage = try a.dupe(f64, base.leverage);
    for (active[0..rank], 0..) |j, h| {
        expanded.coefficients[j] = base.coefficients[h];
        expanded.se[j] = base.se[h];
        for (active[0..rank], 0..) |k, l| {
            expanded.covariance[j * p + k] = base.covariance[h * rank + l];
            expanded.covariance_unscaled[j * p + k] = base.covariance_unscaled[h * rank + l];
        }
    }
    const owned_equations = try a.dupe(f64, equations);
    errdefer a.free(owned_equations);
    return .{
        .fit = expanded,
        .alias_coefficients = owned_equations,
        .pivot_tolerance = try a.dupe(f64, pivots),
        .status = if (rank < p) .rank_deficient else if (near) .nearly_singular else .full_rank,
        .singular = singular,
    };
}

fn subset(a: A, x: []const f64, n: usize, p: usize, active: []const usize) ![]f64 {
    const out = try a.alloc(f64, n * active.len);
    for (0..n) |i| for (active, 0..) |j, k| {
        out[i * active.len + k] = x[i * p + j];
    };
    return out;
}

/// Apply the retained-space projection to a new response using QR, avoiding
/// multiplication by ill-conditioned normal equations. Rank is rechecked using
/// the same policy; the caller owns the returned fitted vector.
pub fn project(a: A, x: []const f64, response: []const f64, n: usize, p: usize, weights: ?[]const f64, has_intercept: bool, singular: f64) diag.Error![]f64 {
    var result = try fit(a, x, response, n, p, weights, has_intercept, singular);
    defer result.deinit(a);
    return a.dupe(f64, result.fit.fitted);
}

const testing = std.testing;
fn expectClose(expected: f64, actual: f64, tolerance: f64) !void {
    try testing.expectApproxEqAbs(expected, actual, tolerance);
}

fn multiply(a: A, lhs: []const f64, rhs: []const f64, rows: usize, inner: usize, cols: usize) ![]f64 {
    const out = try a.alloc(f64, rows * cols);
    for (0..rows) |i| for (0..cols) |j| {
        var sum: f64 = 0;
        for (0..inner) |k| sum += lhs[i * inner + k] * rhs[k * cols + j];
        out[i * cols + j] = sum;
    };
    return out;
}

fn checkIdentities(a: A, x: []const f64, n: usize, p: usize, w: ?[]const f64, result: Result, tolerance: f64) !void {
    // Independent direct products are verification only, never the solver.
    const normal = try a.alloc(f64, p * p);
    for (0..p) |i| for (0..p) |j| {
        normal[i * p + j] = 0;
        for (0..n) |k| normal[i * p + j] += x[k * p + i] * x[k * p + j] * (if (w) |ws| ws[k] else 1);
    };
    const g = result.fit.covariance_unscaled;
    const ag = try multiply(a, normal, g, p, p, p);
    const aga = try multiply(a, ag, normal, p, p, p);
    const ga = try multiply(a, g, normal, p, p, p);
    const gag = try multiply(a, ga, g, p, p, p);
    for (normal, aga) |expected, actual| try expectClose(expected, actual, tolerance * @max(1, @abs(expected)));
    for (g, gag) |expected, actual| try expectClose(expected, actual, tolerance * @max(1, @abs(expected)));
    // Reconstruct X from retained columns and the reported alias equations.
    for (0..n) |i| for (0..p) |j| {
        var value: f64 = 0;
        for (0..p) |k| value += x[i * p + k] * result.alias_coefficients[j * p + k];
        try expectClose(x[i * p + j], value, tolerance * @max(1, @abs(x[i * p + j])));
    };
    const projection = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        var value: f64 = 0;
        for (0..p) |k| for (0..p) |l| {
            value += x[i * p + k] * g[k * p + l] * x[j * p + l];
        };
        projection[i * n + j] = value * (if (w) |ws| ws[j] else 1);
    };
    const squared = try multiply(a, projection, projection, n, n, n);
    for (projection, squared) |expected, actual| try expectClose(expected, actual, tolerance * @max(1, @abs(expected)));
    var trace: f64 = 0;
    for (0..n) |i| {
        trace += projection[i * n + i];
        for (0..n) |j| {
            // W P = P' W, including zero-weight rows.
            const wi = if (w) |ws| ws[i] else 1;
            const wj = if (w) |ws| ws[j] else 1;
            try expectClose(wi * projection[i * n + j], wj * projection[j * n + i], tolerance);
        }
    }
    try expectClose(@floatFromInt(result.fit.rank), trace, tolerance);
}

test "STAT-COMMON-003 full rank independent inverse, coefficients and projection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1 };
    const y = [_]f64{ 1, 2, 3, 5 };
    var result = try fit(a, &x, &y, 4, 3, null, true, default_singular);
    defer result.deinit(a);
    try testing.expectEqual(RankStatus.full_rank, result.status);
    const inverse = [_]f64{ 0.75, -0.5, -0.5, -0.5, 1, 0, -0.5, 0, 1 };
    for (inverse, result.fit.covariance_unscaled) |expected, actual| try expectClose(expected, actual, 1e-13);
    for ([_]f64{ 0.75, 1.5, 2.5 }, result.fit.coefficients) |expected, actual| try expectClose(expected, actual, 1e-13);
    const projected = try project(a, &x, &y, 4, 3, null, true, default_singular);
    for ([_]f64{ 0.75, 2.25, 3.25, 4.75 }, projected) |expected, actual| try expectClose(expected, actual, 1e-13);
    const twice = try project(a, &x, projected, 4, 3, null, true, default_singular);
    for (projected, twice) |expected, actual| try expectClose(expected, actual, 1e-13);
    try checkIdentities(a, &x, 4, 3, null, result, 1e-12);
}

test "STAT-COMMON-003 unchanged singular oracle alias DF B and TOL VIF quantities" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    const z = [_]f64{ 1, 1, 2, 1, 3, 2, 4, 3, 5, 3, 5, 4 };
    var x: [48]f64 = undefined;
    for (0..12) |i| {
        const xi: f64 = @floatFromInt(i + 1);
        @memcpy(x[4 * i ..][0..4], &[_]f64{ 1, xi, 2 * xi, z[i] });
    }
    var result = try fit(a, &x, &y, 12, 4, null, true, default_singular);
    defer result.deinit(a);
    try testing.expectEqual(@as(usize, 3), result.fit.rank);
    try testing.expectEqual(RankStatus.rank_deficient, result.status);
    try testing.expectEqualSlices(bool, &.{ false, false, true, false }, result.fit.aliased);
    try testing.expectEqualSlices(bool, &.{ false, true, false, false }, result.fit.biased);
    try testing.expectEqual(@as(f64, 0), result.fit.coefficients[2]);
    try testing.expect(std.math.isNan(result.fit.se[2]));
    for ([_]f64{ 0, 2, 0, 0 }, result.alias_coefficients[8..12]) |expected, actual| try expectClose(expected, actual, 1e-13);
    // Independent CSS from integer sums: 650-78^2/12=143;
    // 120-34^2/12=71/3. Final TOL/VIF belongs to reg.zig, not duplicated here.
    const vx = 143 * result.fit.covariance_unscaled[5];
    const vz = (71.0 / 3.0) * result.fit.covariance_unscaled[15];
    try expectClose(3.44169, vx, 0.000005);
    try expectClose(3.44169, vz, 0.000005);
    try expectClose(0.29055, 1 / vx, 0.000005);
    try expectClose(0.29055, 1 / vz, 0.000005);
    for ([_]f64{ 1.33390, 1.81763, 0, 0.62407 }, result.fit.coefficients) |expected, actual| try expectClose(expected, actual, 0.000005);
    try checkIdentities(a, &x, 12, 4, null, result, 1e-10);
}

test "STAT-COMMON-003 scaled alias equations retain small original-unit coefficients" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var x: [16]f64 = undefined;
    for (0..4) |i| {
        const u: f64 = @floatFromInt(i % 2);
        const v: f64 = @floatFromInt(i / 2);
        @memcpy(x[i * 4 ..][0..4], &[_]f64{ 1, 1e15 * u, v, 7 + 2 * u - 3 * v });
    }
    var result = try fit(a, &x, &.{ 1, 2, 3, 5 }, 4, 4, null, true, default_singular);
    defer result.deinit(a);
    try expectClose(7, result.alias_coefficients[12], 1e-12);
    try expectClose(2e-15, result.alias_coefficients[13], 1e-28);
    try expectClose(-3, result.alias_coefficients[14], 1e-12);
    try testing.expectEqualSlices(bool, &.{ true, true, true, false }, result.fit.biased);
    // Reconstruction is checked directly; absolute 1e-10 coefficient trimming
    // would erase the second term and miss the alias by 2 on two observations.
    for (0..4) |i| {
        var reconstructed: f64 = 0;
        for (0..4) |j| reconstructed += x[i * 4 + j] * result.alias_coefficients[12 + j];
        try expectClose(x[i * 4 + 3], reconstructed, 1e-12);
    }
}

test "STAT-COMMON-003 weighted reflexive inverse and projection with zero-weight row" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 0, 0, 1, 1, 2, 1, 2, 4, 1, 3, 6 };
    const w = [_]f64{ 1, 2, 1, 0 };
    var result = try fit(a, &x, &.{ 1, 2, 2, 1000 }, 4, 3, &w, true, default_singular);
    defer result.deinit(a);
    try expectClose(0.75, result.fit.covariance_unscaled[0], 1e-13);
    try expectClose(-0.5, result.fit.covariance_unscaled[1], 1e-13);
    try expectClose(0.5, result.fit.covariance_unscaled[4], 1e-13);
    try checkIdentities(a, &x, 4, 3, &w, result, 1e-12);
    const projected = try project(a, &x, &.{ 1, 2, 2, 1000 }, 4, 3, &w, true, default_singular);
    for ([_]f64{ 1.25, 1.75, 2.25, 2.75 }, projected) |expected, actual| try expectClose(expected, actual, 1e-13);
}

test "STAT-COMMON-003 near collinearity ordered SINGULAR policy and scale invariance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const y = [_]f64{ 1, 2, 3, 5 };
    for ([_]f64{ 1e-4, 1e-5 }) |epsilon| {
        var x: [12]f64 = undefined;
        var scaled: [12]f64 = undefined;
        for (0..4) |i| {
            const u: f64 = if (i < 2) -1 else 1;
            const v: f64 = if (i % 2 == 0) -1 else 1;
            @memcpy(x[i * 3 ..][0..3], &[_]f64{ 1, u, u + epsilon * v });
            @memcpy(scaled[i * 3 ..][0..3], &[_]f64{ 1, u * 1e-6, (u + epsilon * v) * 1e6 });
        }
        var result = try fit(a, &x, &y, 4, 3, null, true, default_singular);
        defer result.deinit(a);
        var rescaled = try fit(a, &scaled, &y, 4, 3, &.{ 100, 100, 100, 100 }, true, default_singular);
        defer rescaled.deinit(a);
        const pivot = epsilon * epsilon / (1 + epsilon * epsilon);
        try expectClose(pivot, result.pivot_tolerance[2], pivot * 1e-8);
        try expectClose(pivot, rescaled.pivot_tolerance[2], pivot * 1e-8);
        const expected_rank: usize = if (epsilon == 1e-4) 3 else 2;
        try testing.expectEqual(expected_rank, result.fit.rank);
        try testing.expectEqual(expected_rank, rescaled.fit.rank);
        try testing.expectEqual(if (expected_rank == 3) RankStatus.nearly_singular else RankStatus.rank_deficient, result.status);
        if (expected_rank == 3) {
            // AGA/GAG products lose precision proportional to 1/pivot. This
            // bound is dimensionless and accounts for the normal-matrix condition.
            try checkIdentities(a, &x, 4, 3, null, result, 128 * std.math.floatEps(f64) / pivot);
        } else {
            var permissive = try fit(a, &x, &y, 4, 3, null, true, 1e-12);
            defer permissive.deinit(a);
            try testing.expectEqual(@as(usize, 3), permissive.fit.rank);
        }
        for (result.fit.fitted, rescaled.fit.fitted) |left, right| try expectClose(left, right, 1e-9);
    }
}

test "STAT-COMMON-003 malformed nonfinite zero-rank and no-intercept cases" {
    const a = testing.allocator;
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 2, null, true, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{2}, &.{1}, 1, 1, null, true, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, &.{-1}, true, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, &.{0}, true, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{nan}, &.{1}, 1, 1, null, false, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{std.math.inf(f64)}, 1, 1, null, true, default_singular));
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, null, true, 0));
    try testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, null, true, nan));
    var zero = try fit(a, &.{ 0, 0 }, &.{ 1, 2 }, 2, 1, null, false, default_singular);
    defer zero.deinit(a);
    try testing.expectEqual(@as(usize, 0), zero.fit.rank);
    try expectClose(5, zero.fit.sse, 0);
    var origin = try fit(a, &.{ 1, 2, 3 }, &.{ 1, 2, 2 }, 3, 1, null, false, default_singular);
    defer origin.deinit(a);
    try expectClose(11.0 / 14.0, origin.fit.coefficients[0], 1e-13);
}

fn allocationCheck(a: A) !void {
    var result = try fit(a, &.{ 1, 0, 0, 1, 1, 2, 1, 2, 4 }, &.{ 1, 2, 2 }, 3, 3, null, true, default_singular);
    defer result.deinit(a);
}

test "STAT-COMMON-003 allocation failures preserve ownership" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationCheck, .{});
}

test "STAT-COMMON-003 rank policy reports QR precision disagreement instead of silent success" {
    // CSS-based policy retains the second column, but its relative raw-column
    // residual is below reg_fit's documented 1e-12 QR floor. Do not pretend a
    // successful rank-one fit obeys the requested rank-two policy.
    try testing.expectError(error.ExecError, fit(testing.allocator, &.{ 1, 1e14 - 1, 1, 1e14, 1, 1e14 + 1 }, &.{ 1, 2, 3 }, 3, 2, null, true, default_singular));
}

test "STAT-COMMON-003 zero-weight observations do not constrain alias equations" {
    const a = testing.allocator;
    var result = try fit(a, &.{ 1, 0, 0, 1, 1, 2, 1, 2, 999 }, &.{ 1, 2, 500 }, 3, 3, &.{ 1, 1, 0 }, true, default_singular);
    defer result.deinit(a);
    try testing.expectEqual(@as(usize, 2), result.fit.rank);
    try expectClose(2, result.alias_coefficients[7], 1e-13);
    try expectClose(3, result.fit.fitted[2], 1e-13);
    try testing.expectEqual(@as(usize, 0), result.fit.df_error);
    try testing.expect(std.math.isNan(result.fit.mse));
}
