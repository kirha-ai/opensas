//! Survey sample design and the Taylor-series (linearization) variance of a
//! weighted mean, SAS/STAT 15.4 chapter 121 "Statistical Computations"
//! (Mean; Variance and Standard Error of the Mean). Shared by the survey
//! procedures: the design is strata, primary sampling units (clusters) inside
//! strata, observation weights and an optional per-stratum sampling rate.
const std = @import("std");
const A = std.mem.Allocator;

pub const Design = struct {
    /// Stratum index of every observation, 0..n_strata-1.
    stratum: []const usize,
    /// Primary sampling unit of every observation, 0..n_clusters-1. A unit
    /// belongs to exactly one stratum. Without clustering every observation
    /// is its own unit.
    cluster: []const usize,
    weight: []const f64,
    n_strata: usize,
    n_clusters: usize,
    /// Sampling fraction f_h of every stratum; null means no finite
    /// population correction.
    rate: ?[]const f64 = null,

    /// Degrees of freedom of the Taylor variance: units minus strata.
    pub fn df(self: Design) f64 {
        return @as(f64, @floatFromInt(self.n_clusters)) - @as(f64, @floatFromInt(self.n_strata));
    }
};

pub const Estimate = struct {
    mean: f64,
    stderr: f64,
    sum_weights: f64,
    /// A stratum with a single sampling unit contributes no variance; the
    /// caller decides how to report it.
    single_unit_stratum: bool,
};

/// Weighted mean  ybar = sum(w y) / sum(w)  and its linearized variance
///   V = sum_h (1 - f_h) n_h/(n_h - 1) sum_i (e_hi - ebar_h)^2,
///   e_hi = sum over the observations of unit i of  w (y - ybar) / sum(w),
/// where n_h counts the sampling units of stratum h.
pub fn taylorMean(a: A, d: Design, y: []const f64) !Estimate {
    var sum_w: f64 = 0;
    var sum_wy: f64 = 0;
    for (y, d.weight) |v, w| {
        sum_w += w;
        sum_wy += w * v;
    }
    const mean = sum_wy / sum_w;
    const unit = try a.alloc(f64, d.n_clusters);
    defer a.free(unit);
    const unit_stratum = try a.alloc(usize, d.n_clusters);
    defer a.free(unit_stratum);
    @memset(unit, 0);
    for (y, d.weight, d.cluster, d.stratum) |v, w, c, h| {
        unit[c] += w * (v - mean) / sum_w;
        unit_stratum[c] = h;
    }
    const count = try a.alloc(f64, d.n_strata);
    defer a.free(count);
    const total = try a.alloc(f64, d.n_strata);
    defer a.free(total);
    const squares = try a.alloc(f64, d.n_strata);
    defer a.free(squares);
    @memset(count, 0);
    @memset(total, 0);
    @memset(squares, 0);
    for (unit, unit_stratum) |e, h| {
        count[h] += 1;
        total[h] += e;
    }
    for (unit, unit_stratum) |e, h| {
        const dev = e - total[h] / count[h];
        squares[h] += dev * dev;
    }
    var variance: f64 = 0;
    var single = false;
    for (count, squares, 0..) |n, ss, h| {
        if (n < 2) {
            single = true;
            continue;
        }
        const fpc = if (d.rate) |r| 1 - r[h] else 1;
        variance += fpc * n / (n - 1) * ss;
    }
    return .{ .mean = mean, .stderr = @sqrt(variance), .sum_weights = sum_w, .single_unit_stratum = single };
}

test "STAT-SURVEYMEANS-001 Taylor variance reduces to (1-f)s^2/n for a simple random sample" {
    const a = std.testing.allocator;
    // y = 1..5, N = 50: mean 3, s^2 = 2.5, V = 0.9 * 2.5 / 5 = 0.45.
    const y = [_]f64{ 1, 2, 3, 4, 5 };
    const e = try taylorMean(a, .{ .stratum = &.{ 0, 0, 0, 0, 0 }, .cluster = &.{ 0, 1, 2, 3, 4 }, .weight = &.{ 10, 10, 10, 10, 10 }, .n_strata = 1, .n_clusters = 5, .rate = &.{0.1} }, &y);
    try std.testing.expectApproxEqAbs(@as(f64, 3), e.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.45)), e.stderr, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 50), e.sum_weights, 1e-12);
    try std.testing.expect(!e.single_unit_stratum);
}

test "STAT-SURVEYMEANS-001 Taylor variance sums cluster totals within strata" {
    const a = std.testing.allocator;
    // Stratum 0 units {1,3},{5}; stratum 1 units {2},{4,6}; equal weights.
    // ybar = 3.5; unit totals of (y-ybar)/6: -0.5, 0.25 | -0.25, 0.5.
    // Each stratum: deviations +-0.375, sum of squares 0.28125, times
    // n/(n-1) = 2 gives 0.5625; V = 1.125, df = 4 - 2.
    const d: Design = .{ .stratum = &.{ 0, 0, 0, 1, 1, 1 }, .cluster = &.{ 0, 0, 1, 2, 3, 3 }, .weight = &.{ 1, 1, 1, 1, 1, 1 }, .n_strata = 2, .n_clusters = 4 };
    const e = try taylorMean(a, d, &.{ 1, 3, 5, 2, 4, 6 });
    try std.testing.expectApproxEqAbs(@as(f64, 3.5), e.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 1.125)), e.stderr, 1e-12);
    try std.testing.expectEqual(@as(f64, 2), d.df());
}

test "STAT-SURVEYMEANS-001 a single-unit stratum is flagged and adds no variance" {
    const a = std.testing.allocator;
    const e = try taylorMean(a, .{ .stratum = &.{ 0, 0, 1 }, .cluster = &.{ 0, 1, 2 }, .weight = &.{ 1, 1, 1 }, .n_strata = 2, .n_clusters = 3 }, &.{ 1, 3, 8 });
    try std.testing.expect(e.single_unit_stratum);
    // ybar = 4; e = -1, -1/3; mean -2/3; squares 2/9; times 2 = 4/9.
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), e.stderr, 1e-12);
}
