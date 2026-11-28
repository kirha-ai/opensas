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

/// Linearized "meat" of the regression sandwich variance, SAS/STAT 15.4
/// chapter 123 (Variance Estimation, Taylor series):
///   G = sum_h (1 - f_h) n_h/(n_h - 1) sum_i (e_hi - ebar_h)(e_hi - ebar_h)',
///   e_hi = sum over the observations of unit i of  w r x,
/// returned row-major p x p. `x` holds the n design rows row-major (n*p),
/// `r` the residuals. The caller applies the (n-1)/(n-p) adjustment and the
/// generalized inverse of X'WX on both sides.
pub fn taylorRegressionMeat(a: A, d: Design, x: []const f64, r: []const f64, p: usize) ![]f64 {
    const unit = try a.alloc(f64, d.n_clusters * p);
    defer a.free(unit);
    const unit_stratum = try a.alloc(usize, d.n_clusters);
    defer a.free(unit_stratum);
    @memset(unit, 0);
    for (r, d.weight, d.cluster, d.stratum, 0..) |res, w, c, h, k| {
        for (0..p) |j| unit[c * p + j] += w * res * x[k * p + j];
        unit_stratum[c] = h;
    }
    const count = try a.alloc(f64, d.n_strata);
    defer a.free(count);
    const mean = try a.alloc(f64, d.n_strata * p);
    defer a.free(mean);
    @memset(count, 0);
    @memset(mean, 0);
    for (unit_stratum, 0..) |h, c| {
        count[h] += 1;
        for (0..p) |j| mean[h * p + j] += unit[c * p + j];
    }
    for (count, 0..) |n, h| if (n > 0) for (0..p) |j| {
        mean[h * p + j] /= n;
    };
    const g = try a.alloc(f64, p * p);
    @memset(g, 0);
    for (unit_stratum, 0..) |h, c| {
        const n = count[h];
        if (n < 2) continue;
        const fpc = if (d.rate) |rt| 1 - rt[h] else 1;
        const factor = fpc * n / (n - 1);
        for (0..p) |i| for (0..p) |j| {
            g[i * p + j] += factor * (unit[c * p + i] - mean[h * p + i]) * (unit[c * p + j] - mean[h * p + j]);
        };
    }
    return g;
}

/// Replication (resampling) design shared by the survey procedures,
/// SAS/STAT 15.4 chapter 15 "Variance Estimation" (physical pp.273-274) and
/// the SURVEYMEANS jackknife (chapter 121): R replicate weight vectors over
/// the n observations, row-major (R*n), and a coefficient alpha_r per
/// replicate. The variance of any estimator theta is
///   V = sum_r alpha_r (theta_r - theta)^2.
pub const Replicates = struct {
    /// Replicate weights, `count` rows of `n` observations each.
    weight: []f64,
    alpha: []f64,
    /// Stratum and deleted PSU of each replicate.
    stratum: []usize,
    deleted: []usize,
    n: usize,
    count: usize,

    pub fn row(self: Replicates, r: usize) []const f64 {
        return self.weight[r * self.n ..][0..self.n];
    }
    pub fn deinit(self: Replicates, a: A) void {
        a.free(self.weight);
        a.free(self.alpha);
        a.free(self.stratum);
        a.free(self.deleted);
    }
};

/// A stratum holding a single PSU has no delete-one jackknife replicate;
/// the procedure decides how to report it (error, collapse or omission).
pub const ReplicateError = error{ SinglePsuStratum, OutOfMemory };

/// Delete-one-PSU jackknife (JKn) replicates: one replicate per PSU in PSU
/// order (verified against a SAS 9.4 VARMETHOD=JK(OUTWEIGHTS= OUTJKCOEFS=)
/// listing of the STAT-COMMON-016 design: 6 replicates, coefficients 2/3,
/// SE 1.781669). Replicate r deletes PSU i of stratum h: weight 0 on i, weight
/// w n_h/(n_h - 1) on the other units of h, unchanged elsewhere; alpha_r =
/// (n_h - 1)/n_h. Replicate count = number of PSUs. The design's sampling
/// rate is NOT applied: SAS 9.4 SURVEYMEANS VARMETHOD=JK with RATE=0.25
/// prints the same standard error as without it (reference run); a
/// procedure that documents a jackknife fpc scales `alpha` itself.
pub fn jackknife(a: A, d: Design) ReplicateError!Replicates {
    const n = d.weight.len;
    const per = try a.alloc(f64, d.n_strata);
    defer a.free(per);
    const psu_stratum = try a.alloc(usize, d.n_clusters);
    defer a.free(psu_stratum);
    @memset(per, 0);
    const seen = try a.alloc(bool, d.n_clusters);
    defer a.free(seen);
    @memset(seen, false);
    for (d.cluster, d.stratum) |c, h| if (!seen[c]) {
        seen[c] = true;
        psu_stratum[c] = h;
        per[h] += 1;
    };
    for (seen) |v| std.debug.assert(v);
    for (per) |m| if (m < 2) return error.SinglePsuStratum;
    const r_count = d.n_clusters;
    const out: Replicates = .{
        .weight = try a.alloc(f64, r_count * n),
        .alpha = try a.alloc(f64, r_count),
        .stratum = try a.alloc(usize, r_count),
        .deleted = try a.alloc(usize, r_count),
        .n = n,
        .count = r_count,
    };
    for (0..r_count) |r| {
        const h = psu_stratum[r];
        const nh = per[h];
        out.alpha[r] = (nh - 1) / nh;
        out.stratum[r] = h;
        out.deleted[r] = r;
        for (0..n) |k| out.weight[r * n + k] = if (d.cluster[k] == r) 0 else if (d.stratum[k] == h) d.weight[k] * nh / (nh - 1) else d.weight[k];
    }
    return out;
}

/// BRR needs exactly two PSUs in every stratum.
pub const BrrError = error{ NotTwoPsusPerStratum, UnverifiedHadamardOrder, OutOfMemory };

/// Balanced repeated replication: R = the smallest multiple of 4 greater
/// than H (chapter 121, BRR). Stratum h uses column h + 1 of the Hadamard
/// matrix (the all-ones column 0 is skipped); +1 keeps the first PSU of the
/// stratum with weight 2w and drops the second, -1 the reverse. alpha_r =
/// 1/R. ponytail: only R = 4 (the Sylvester H4, verified against SAS 9.4
/// OUTWEIGHTS= listings for H = 2 and H = 3) is implemented; larger orders
/// (H >= 4) are UnverifiedHadamardOrder. Fay's method is not provided.
pub fn brr(a: A, d: Design) BrrError!Replicates {
    const n = d.weight.len;
    const h_count = d.n_strata;
    const r_count = (h_count / 4 + 1) * 4;
    if (r_count != 4) return error.UnverifiedHadamardOrder;
    const first = try a.alloc(?usize, h_count);
    defer a.free(first);
    const per = try a.alloc(usize, h_count);
    defer a.free(per);
    @memset(first, null);
    @memset(per, 0);
    const seen = try a.alloc(bool, d.n_clusters);
    defer a.free(seen);
    @memset(seen, false);
    // PSU indices are in sorted PSU order, so the smaller index of a
    // stratum is its first PSU.
    for (d.cluster, d.stratum) |c, h| if (!seen[c]) {
        seen[c] = true;
        per[h] += 1;
        first[h] = if (first[h]) |f| @min(f, c) else c;
    };
    for (per) |m| if (m != 2) return error.NotTwoPsusPerStratum;
    const h4 = [4][4]i2{ .{ 1, 1, 1, 1 }, .{ 1, -1, 1, -1 }, .{ 1, 1, -1, -1 }, .{ 1, -1, -1, 1 } };
    const out: Replicates = .{
        .weight = try a.alloc(f64, r_count * n),
        .alpha = try a.alloc(f64, r_count),
        .stratum = try a.alloc(usize, r_count),
        .deleted = try a.alloc(usize, r_count),
        .n = n,
        .count = r_count,
    };
    for (0..r_count) |r| {
        out.alpha[r] = 1.0 / @as(f64, @floatFromInt(r_count));
        // BRR replicates span every stratum; no single donor stratum/PSU.
        out.stratum[r] = h_count;
        out.deleted[r] = d.n_clusters;
        for (0..n) |k| {
            const h = d.stratum[k];
            const keep_first = h4[r][h + 1] == 1;
            const is_first = d.cluster[k] == first[h].?;
            out.weight[r * n + k] = if (keep_first == is_first) 2 * d.weight[k] else 0;
        }
    }
    return out;
}

/// Replication variance of the weighted mean: theta_r is the mean under
/// replicate weights r, V = sum_r alpha_r (theta_r - theta)^2 with theta the
/// full-sample mean.
pub fn replicateMeanVariance(rep: Replicates, full_weight: []const f64, y: []const f64) f64 {
    const theta = weightedMean(full_weight, y);
    var v: f64 = 0;
    for (0..rep.count) |r| {
        const dev = weightedMean(rep.row(r), y) - theta;
        v += rep.alpha[r] * dev * dev;
    }
    return v;
}

fn weightedMean(w: []const f64, y: []const f64) f64 {
    var sw: f64 = 0;
    var swy: f64 = 0;
    for (w, y) |wi, yi| {
        sw += wi;
        swy += wi * yi;
    }
    return swy / sw;
}

/// The STAT-COMMON-016 reference design (invented data): x = 1..12,
/// y as below, stratum 1 + (x > 6), PSU ceil(x/2), weight 1 + mod(x, 3).
const common016 = struct {
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    const stratum = [_]usize{ 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1 };
    const cluster = [_]usize{ 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 };
    const weight = [_]f64{ 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1 };
    fn design(rate: ?[]const f64) Design {
        return .{ .stratum = &stratum, .cluster = &cluster, .weight = &weight, .n_strata = 2, .n_clusters = 6, .rate = rate };
    }
};

test "STAT-COMMON-016 stratified cluster Taylor mean agrees with exact enumeration" {
    const a = std.testing.allocator;
    // Exact rational enumeration (independent of this kernel): sum(w) = 24,
    // mean = 358/24 = 179/12; PSU totals of w(y - mean)/24 within strata
    // give V = 41077/13824, SE = 1.7237826152... (SAS 9.4 reference listing
    // prints 14.916667, 1.723783, df = 6 PSUs - 2 strata = 4).
    const e = try taylorMean(a, common016.design(null), &common016.y);
    try std.testing.expectApproxEqAbs(@as(f64, 179.0 / 12.0), e.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 41077.0 / 13824.0)), e.stderr, 1e-12);
    try std.testing.expectEqual(@as(f64, 24), e.sum_weights);
    try std.testing.expectEqual(@as(f64, 4), common016.design(null).df());
    try std.testing.expect(!e.single_unit_stratum);
    // A first-stage rate f_h scales each stratum's contribution by 1 - f_h:
    // a common rate scales V exactly (SAS 9.4 RATE=0.25 listing: SE
    // 1.492840 = sqrt(0.75 * 41077/13824)).
    const f = try taylorMean(a, common016.design(&.{ 0.25, 0.25 }), &common016.y);
    try std.testing.expectApproxEqAbs(0.75 * 41077.0 / 13824.0, f.stderr * f.stderr, 1e-12);
}

test "STAT-COMMON-016 jackknife replicate dimensions, weights and variance by enumeration" {
    const a = std.testing.allocator;
    const rep = try jackknife(a, common016.design(null));
    defer rep.deinit(a);
    // One replicate per PSU, each over all 12 observations.
    try std.testing.expectEqual(@as(usize, 6), rep.count);
    try std.testing.expectEqual(@as(usize, 72), rep.weight.len);
    // Replicate 1 deletes PSU 1 (x = 1, 2) of stratum 1 (n_h = 3): the other
    // stratum-1 weights are multiplied by 3/2, stratum 2 unchanged.
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 1.5, 3, 4.5, 1.5, 2, 3, 1, 2, 3, 1 }, rep.row(0));
    for (rep.alpha) |x| try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), x, 1e-15);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 1, 1, 1 }, rep.stratum);
    // Replicate means by exact enumeration: 148/9, 743/51, 665/48, 233/15,
    // 258/17, 225/16; V = (2/3) sum (theta_r - 179/12)^2 = 356679677/112363200.
    const v = replicateMeanVariance(rep, &common016.weight, &common016.y);
    try std.testing.expectApproxEqAbs(@as(f64, 356679677.0 / 112363200.0), v, 1e-12);
    // The design's rate does not enter the coefficients (SAS 9.4 SE
    // 1.781669 with and without RATE=0.25).
    const fr = try jackknife(a, common016.design(&.{ 0.5, 0.25 }));
    defer fr.deinit(a);
    try std.testing.expectEqualSlices(f64, rep.alpha, fr.alpha);
}

test "STAT-COMMON-016 BRR replicate weights and variance agree with SAS and enumeration" {
    const a = std.testing.allocator;
    // Same data with PSU ceil(x/3): two PSUs per stratum, H = 2, R = 4.
    const d: Design = .{ .stratum = &common016.stratum, .cluster = &.{ 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3 }, .weight = &common016.weight, .n_strata = 2, .n_clusters = 4 };
    const rep = try brr(a, d);
    defer rep.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), rep.count);
    // SAS 9.4 VARMETHOD=BRR(OUTWEIGHTS=) RepWt_1..RepWt_4 of this design.
    try std.testing.expectEqualSlices(f64, &.{ 4, 6, 2, 0, 0, 0, 4, 6, 2, 0, 0, 0 }, rep.row(0));
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 0, 4, 6, 2, 4, 6, 2, 0, 0, 0 }, rep.row(1));
    try std.testing.expectEqualSlices(f64, &.{ 4, 6, 2, 0, 0, 0, 0, 0, 0, 4, 6, 2 }, rep.row(2));
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 0, 4, 6, 2, 0, 0, 0, 4, 6, 2 }, rep.row(3));
    // Replicate means 12, 15, 89/6, 107/6: V = 613/144 (SAS SE 2.063236).
    try std.testing.expectApproxEqAbs(@as(f64, 613.0 / 144.0), replicateMeanVariance(rep, &common016.weight, &common016.y), 1e-12);
    // H = 3 strata (stratum ceil(x/4), PSU ceil(x/2)) use columns 1..3 of
    // H4: SAS 9.4 RepWt_1..4 below; replicate means 143/12, 175/11, 108/7,
    // 182/11, V = 3671209/1138368 (SAS SE 1.795822).
    const d3: Design = .{ .stratum = &.{ 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2 }, .cluster = &common016.cluster, .weight = &common016.weight, .n_strata = 3, .n_clusters = 6 };
    const rep3 = try brr(a, d3);
    defer rep3.deinit(a);
    try std.testing.expectEqualSlices(f64, &.{ 4, 6, 0, 0, 6, 2, 0, 0, 2, 4, 0, 0 }, rep3.row(0));
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 2, 4, 6, 2, 0, 0, 0, 0, 6, 2 }, rep3.row(1));
    try std.testing.expectEqualSlices(f64, &.{ 4, 6, 0, 0, 0, 0, 4, 6, 0, 0, 6, 2 }, rep3.row(2));
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 2, 4, 0, 0, 4, 6, 2, 4, 0, 0 }, rep3.row(3));
    try std.testing.expectApproxEqAbs(@as(f64, 3671209.0 / 1138368.0), replicateMeanVariance(rep3, &common016.weight, &common016.y), 1e-12);
    // Three PSUs in a stratum, or an unverified Hadamard order, refuse.
    try std.testing.expectError(error.NotTwoPsusPerStratum, brr(a, common016.design(null)));
    const many: Design = .{ .stratum = &.{ 0, 0, 1, 1, 2, 2, 3, 3 }, .cluster = &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, .weight = &.{ 1, 1, 1, 1, 1, 1, 1, 1 }, .n_strata = 4, .n_clusters = 8 };
    try std.testing.expectError(error.UnverifiedHadamardOrder, brr(a, many));
}

test "STAT-COMMON-016 jackknife refuses a single-PSU stratum" {
    const a = std.testing.allocator;
    const d: Design = .{ .stratum = &.{ 0, 0, 1 }, .cluster = &.{ 0, 1, 2 }, .weight = &.{ 1, 1, 1 }, .n_strata = 2, .n_clusters = 3 };
    try std.testing.expectError(error.SinglePsuStratum, jackknife(a, d));
}

test "STAT-SURVEYREG-001 regression meat of an intercept-only design is the mean variance times sum(w)^2" {
    const a = std.testing.allocator;
    // Intercept only: e_hi = w (y - ybar); the mean's linearized variance
    // uses e / sum(w), so G = V(mean) * sum(w)^2 = 0.45 * 50^2.
    const d: Design = .{ .stratum = &.{ 0, 0, 0, 0, 0 }, .cluster = &.{ 0, 1, 2, 3, 4 }, .weight = &.{ 10, 10, 10, 10, 10 }, .n_strata = 1, .n_clusters = 5, .rate = &.{0.1} };
    const g = try taylorRegressionMeat(a, d, &.{ 1, 1, 1, 1, 1 }, &.{ -2, -1, 0, 1, 2 }, 1);
    defer a.free(g);
    try std.testing.expectApproxEqAbs(@as(f64, 0.45 * 2500), g[0], 1e-9);
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
