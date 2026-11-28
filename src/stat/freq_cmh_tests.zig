//! STAT-FREQ-014: hand-calculated Cochran-Mantel-Haenszel checks. Every
//! expected value below is an exact rational derived in the adjacent comment
//! from SAS/STAT 15.4 "Cochran-Mantel-Haenszel Statistics" (PROC FREQ details),
//! not from OpenSAS output. Bounds: the statistics are sums/ratios of small
//! integers, so 1e-12 absolute covers f64 rounding of O(10) operations on
//! O(1) values (each ≤ 2^-52 relative); no bound is fitted to observations.
const std = @import("std");
const k = @import("freq_stratified.zig");
const Matrix = k.Matrix;
const tol = 1e-12;

/// Independent chi-square(1) upper tail: erfc(sqrt(q/2)) from the Maclaurin
/// series erf(x) = 2/sqrt(pi) * sum (-1)^n x^(2n+1) / (n! (2n+1)). For x ≤ 2
/// the largest term is < 3 and 80 terms leave a remainder far below 1e-15, so
/// cancellation error is bounded by ~3 * 80 * 2^-52 < 1e-13.
fn chi1Tail(q: f64) f64 {
    const x = @sqrt(q / 2);
    std.debug.assert(x <= 2);
    var term = x;
    var sum = x;
    var n: f64 = 1;
    while (n < 80) : (n += 1) {
        term *= -x * x / n;
        sum += term / (2 * n + 1);
    }
    return 1 - 2.0 / @sqrt(@as(f64, std.math.pi)) * sum;
}

fn expectChi(expected_q: f64, df: f64, expected_p: f64, actual: ?k.Chi) !void {
    const got = actual orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(expected_q, got.statistic, tol);
    try std.testing.expectEqual(df, got.df);
    try std.testing.expectApproxEqAbs(expected_p, got.p, 1e-10);
}

test "STAT-FREQ-014 2x2 strata rational CMH with degenerate strata" {
    const a = std.testing.allocator;
    // Stratum A [[3,1],[1,3]], n=8: E(n11)=4*4/8=2, n11-E=1,
    //   V=r1 r2 c1 c2/(n^2 (n-1))=256/(64*7)=4/7.
    // Stratum B [[2,1],[1,2]], n=6: E=3*3/6=3/2, n11-E=1/2, V=81/(36*5)=9/20.
    // Q = (1+1/2)^2 / (4/7+9/20) = (9/4)/(143/140) = 315/143, df=1.
    // For 2x2 tables all three statistics coincide under any scores.
    const sa: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 3, 1, 1, 3 } };
    const sb: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 2, 1, 1, 2 } };
    // Degenerate strata carry no information: empty; a single observation
    // (the n-1 divisor is zero); a zero row margin and a zero column margin
    // (n11-E=0 and V=0).
    const empty: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } };
    const single: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 1, 0, 0 } };
    const no_row: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 4, 3 } };
    const no_col: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 5, 0, 2 } };
    const q: f64 = 315.0 / 143.0;
    for ([_]k.CmhKind{ .correlation, .row_mean, .general }) |kind| {
        try expectChi(q, 1, chi1Tail(q), try k.cmh(a, &.{ sa, sb }, kind));
        try expectChi(q, 1, chi1Tail(q), try k.cmh(a, &.{ empty, sa, single, no_row, sb, no_col }, kind));
        // Only degenerate strata: zero aggregate variance, statistic undefined.
        try std.testing.expectEqual(@as(?k.Chi, null), try k.cmh(a, &.{ empty, single, no_row, no_col }, kind));
        // Opposite associations cancel exactly: A plus A with rows exchanged.
        const flipped: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 1, 3, 3, 1 } };
        try expectChi(0, 1, 1, try k.cmh(a, &.{ sa, flipped }, kind));
    }
}

test "STAT-FREQ-014 3x2 rational CMH separates correlation from nominal alternatives" {
    const a = std.testing.allocator;
    // T = [[3,1],[1,3],[3,1]], n=12, rows 4/4/4, columns 7/5, table scores
    // 1,2,3 and 1,2. Expected counts 7/3 and 5/3 per row.
    // Pearson = 16/35 + 64/35 + 16/35 = 96/35; one stratum general association
    //   Q_G = (n-1)/n * Pearson = 11/12 * 96/35 = 88/35, df=(R-1)(C-1)=2.
    // Two columns: row mean scores Q_S = Q_G = 88/35, df=R-1=2.
    // Correlation: sum n_ij (a_i-2)(c_j-17/12) = (-1)(-2/3)+0+(1)(-2/3)=0,
    //   Q_C = 0, df=1, p=1.
    // Chi-square(2) upper tail is exactly exp(-Q/2).
    const t: Matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 3, 1, 1, 3, 3, 1 } };
    const q: f64 = 88.0 / 35.0;
    try expectChi(0, 1, 1, try k.cmh(a, &.{t}, .correlation));
    try expectChi(q, 2, @exp(-q / 2), try k.cmh(a, &.{t}, .row_mean));
    try expectChi(q, 2, @exp(-q / 2), try k.cmh(a, &.{t}, .general));
    // Two identical strata double both G and Var(G): Q = 2*88/35 = 176/35.
    try expectChi(2 * q, 2, @exp(-q), try k.cmh(a, &.{ t, t }, .general));
    try expectChi(2 * q, 2, @exp(-q), try k.cmh(a, &.{ t, t }, .row_mean));
    // Column-exchanged second stratum: G_1 + G_2 = 0 exactly although each
    // stratum is associated, so the statistic is 0 with p=1.
    const swapped: Matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 1, 3, 3, 1, 1, 3 } };
    try expectChi(0, 2, 1, try k.cmh(a, &.{ t, swapped }, .general));
    // Explicit stratum row scores 1,2,4 (mean 7/3): S_xx=4*(16+1+25)/9=56/3,
    // S_yy=7*25/144+5*49/144=35/12, S_xy=(-4/3)(-2/3)+(-1/3)(4/3)+(5/3)(-2/3)
    // =-2/3, r^2=(4/9)/(490/9)=2/245, Q_C=(n-1) r^2=22/245, df=1.
    var scored = t;
    scored.row_scores = &.{ 1, 2, 4 };
    scored.col_scores = &.{ 1, 2 };
    const qc: f64 = 22.0 / 245.0;
    try expectChi(qc, 1, chi1Tail(qc), try k.cmh(a, &.{scored}, .correlation));
    // Nominal alternatives ignore the row scores.
    try expectChi(q, 2, @exp(-q / 2), try k.cmh(a, &.{scored}, .general));
    // An all-zero column leaves the general-association covariance singular.
    const flat: Matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 3, 0, 1, 0, 3, 0 } };
    try std.testing.expectEqual(@as(?k.Chi, null), try k.cmh(a, &.{flat}, .general));
}

test "STAT-FREQ-014 rational Mantel-Haenszel ratios and Breslow-Day homogeneity" {
    // A [[3,1],[1,3]] n=8, B [[2,1],[1,2]] n=6.
    // OR_MH = (9/8+4/6)/(1/8+1/6) = (43/24)/(7/24) = 43/7.
    // RR_MH(col 1) = (3*4/8+2*3/6)/(1*4/8+1*3/6) = (5/2)/1 = 5/2.
    // RR_MH(col 2) = (1*4/8+1*3/6)/(3*4/8+2*3/6) = 2/5.
    const sa: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 3, 1, 1, 3 } };
    const sb: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 2, 1, 1, 2 } };
    const empty: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } };
    const r = try k.mantelHaenszelRatios(&.{ sa, empty, sb }, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 43.0 / 7.0), r.odds.?.value, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), r.column1.?.value, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), r.column2.?.value, tol);
    // Robins-Breslow-Greenland log variance: P=(a+d)/n, Q=(b+c)/n, R=ad/n,
    // S=bc/n. A: P=3/4,Q=1/4,R=9/8,S=1/8; B: P=2/3,Q=1/3,R=2/3,S=1/6.
    // sum PR=27/32+4/9=371/288, sum(PS+QR)=3/8+1/3=17/24, sum QS=1/32+1/18
    // =25/288, R=43/24, S=7/24:
    // var = (371/288)/(2*(43/24)^2) + (17/24)/(2*(43/24)(7/24)) + (25/288)/(2*(7/24)^2)
    //     = 371/1849 + 204/301 + 25/49.
    const v: f64 = 371.0 / 1849.0 + 204.0 / 301.0 + 25.0 / 49.0;
    try std.testing.expectApproxEqAbs(v, r.odds.?.log_variance.?, tol);
    // Limits are OR*exp(±z*sqrt(var)); their product is OR^2 for any z and
    // the log-width identifies z = 1.959963984540054 (normal 97.5% point).
    try std.testing.expectApproxEqRel(@as(f64, 43.0 / 7.0) * (43.0 / 7.0), r.odds.?.lower.? * r.odds.?.upper.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.959963984540054), @log(r.odds.?.upper.? / r.odds.?.lower.?) / (2 * @sqrt(v)), 1e-9);
    // Breslow-Day: identical strata have a common odds ratio equal to each
    // stratum's own (9), so fitted counts equal observed counts and both the
    // statistic and Tarone's adjustment are 0 with df = q-1 = 1.
    const same = (try k.breslowDay(&.{ sa, sa }, 9)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0), same.unadjusted.statistic, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 0), same.tarone.statistic, tol);
    try std.testing.expectEqual(@as(f64, 1), same.unadjusted.df);
    try std.testing.expectApproxEqAbs(@as(f64, 1), same.unadjusted.p, tol);
    // Common odds ratio 1 fits E=r c/n. A: E=2, 1/Var=4*(1/2)=2, (3-2)^2*2=2.
    // C=[[1,3],[3,1]]: E=2, (1-2)^2*2=2. Q_BD=4, df=1. Residual sum is
    // 1+(-1)=0, so Tarone's correction term vanishes: Q_BDT=4.
    const sc: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 1, 3, 3, 1 } };
    const het = (try k.breslowDay(&.{ sa, empty, sc }, 1)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 4), het.unadjusted.statistic, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 4), het.tarone.statistic, 1e-9);
    try std.testing.expectEqual(@as(usize, 2), het.strata);
    try std.testing.expectApproxEqAbs(chi1Tail(4), het.unadjusted.p, 1e-9);
    // Fewer than two informative strata: homogeneity is undefined.
    try std.testing.expectEqual(@as(?k.BreslowDay, null), try k.breslowDay(&.{ sa, empty }, 9));
}
