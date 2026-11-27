//! Exact two-sided one-sample and equal-allocation pooled two-sample t power.
//! One-sample S154 physical p.7887: F(1,N-1,N*(mean-nullmean)^2/sigma^2).
//! S154 physical pp.395-396: F ~ F(1,N-2, N*(difference/sigma)^2/4).
//! Use the complemented incomplete beta directly to avoid CDF cancellation.
const std = @import("std");
const f = @import("../functions.zig");
pub const solver = @import("power_solver.zig");
pub const Kind = enum { one_sample, two_sample };
pub const Design = struct {
    kind: Kind = .two_sample,
    difference: f64,
    sigma: f64,
    alpha: f64 = 0.05,
    pub fn valid(d: Design) bool {
        return std.math.isFinite(d.difference) and std.math.isFinite(d.sigma) and d.sigma > 0 and std.math.isFinite(d.alpha) and d.alpha > 0 and d.alpha < 1;
    }
    pub fn minimumN(d: Design) f64 {
        return if (d.kind == .one_sample) 2 else 4;
    }
    pub fn executable(d: Design, n: f64) f64 {
        return if (d.kind == .one_sample) @ceil(n) else executableN(n);
    }
    pub fn power(d: Design, n: f64) f64 {
        if (!d.valid() or !std.math.isFinite(n) or n <= (if (d.kind == .one_sample) @as(f64, 1) else 2)) return std.math.nan(f64);
        // Under the null the rejection probability is exactly alpha; avoid
        // inferring monotonicity from large-df quantile roundoff on a plateau.
        if (d.difference == 0) return d.alpha;
        const df = n - (if (d.kind == .one_sample) @as(f64, 1) else 2);
        // The shared quantile solver has a fixed upper bracket. Verify it
        // contains the requested critical value before using its result.
        if (1 - d.alpha == 1 or f.betaI(df / (df + 1e7), df / 2, 0.5) > d.alpha) return std.math.nan(f64);
        const critical = f.bisectCdf(.f, 1 - d.alpha, 1, df, 0, 1e7);
        const nc = n * std.math.pow(f64, d.difference / d.sigma, 2) / (if (d.kind == .one_sample) @as(f64, 1) else 4);
        if (!std.math.isFinite(nc) or nc > 1000) return std.math.nan(f64); // explicit numerical domain, never fabricated power=1
        const z = df / (df + critical);
        if (nc == 0) return f.betaI(z, df / 2, 0.5);
        const lambda = nc / 2;
        var weight = @exp(-lambda);
        var total: f64 = 0;
        for (0..2000) |j| {
            const jf: f64 = @floatFromInt(j);
            total += weight * f.betaI(z, df / 2, 0.5 + jf);
            // Missing Poisson mass bounds absolute probability error. For
            // j past the mode the remaining geometric tail is an upper bound.
            const next = weight * lambda / (jf + 1);
            if (jf + 2 > lambda and next / (1 - lambda / (jf + 2)) < 1e-14) return @min(1, total);
            weight = next;
        }
        return std.math.nan(f64);
    }
    pub fn sampleSize(d: Design, target: f64) solver.Result {
        const minimum = d.minimumN();
        if (!d.valid() or !std.math.isFinite(target) or target <= 0 or target >= 1) return .{ .status = .invalid_input, .x = minimum, .value = std.math.nan(f64), .lower = minimum, .upper = minimum, .iterations = 0 };
        var upper: f64 = minimum;
        while (upper < 1e7 and d.power(upper) < target) upper *= 2;
        return solver.invert(d, Design.power, target, minimum, upper, .{});
    }
};
pub fn executableN(continuous: f64) f64 {
    return 2 * @ceil(continuous / 2);
}

test "STAT-COMMON-018 exact power null, symmetry, continuous inversion and executable design" {
    const t = std.testing;
    const d: Design = .{ .difference = 2, .sigma = 3 };
    // SAS 15.4 original reference prints 0.910 at N=100 and 0.808 at N=74;
    // rounding bins are +/-0.0005, not tolerances chosen from our discrepancy.
    try t.expect(@abs(d.power(100) - 0.910) < 0.0005);
    try t.expect(@abs(d.power(74) - 0.808) < 0.0005);
    try t.expect(d.power(72) < 0.8);
    const root = d.sampleSize(0.8);
    try t.expectEqual(solver.Status.converged, root.status);
    try t.expect(root.x > 72 and root.x < 74);
    try t.expectApproxEqAbs(@as(f64, 0.8), d.power(root.x), 1e-10);
    try t.expectEqual(@as(f64, 74), executableN(root.x));
    try t.expectApproxEqAbs(d.power(100), (Design{ .difference = -2, .sigma = 3 }).power(100), 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.05), (Design{ .difference = 0, .sigma = 3 }).power(100), 1e-10);
    try t.expectEqual(solver.Status.target_above_range, (Design{ .difference = 0, .sigma = 3 }).sampleSize(0.8).status);
    try t.expectEqual(solver.Status.invalid_input, d.sampleSize(1).status);
    const below = d.sampleSize(d.power(4) / 2);
    try t.expectEqual(solver.Status.target_below_range, below.status);
    try t.expectEqual(@as(f64, 4), executableN(below.x));
    try t.expect(std.math.isNan((Design{ .difference = 2, .sigma = 0 }).power(100)));
}

// Independent validation: condition a noncentral t on X=sqrt(chi-square(df)).
// Integrate [Phi(delta-cX/sqrt(df)) + Phi(-delta-cX/sqrt(df))] f_chi(X)dX.
// This normal/chi quadrature has no Poisson or incomplete-beta terms.
fn conditionalPower(d: Design, n: f64, intervals: usize) f64 {
    const df = n - (if (d.kind == .one_sample) @as(f64, 1) else 2);
    const c = @sqrt(f.bisectCdf(.f, 1 - d.alpha, 1, df, 0, 1e7));
    const delta = @sqrt(n) * d.difference / ((if (d.kind == .one_sample) @as(f64, 1) else 2) * d.sigma);
    const upper = @sqrt(df) + 12;
    const h = upper / @as(f64, @floatFromInt(intervals));
    var sum: f64 = if (df == 1) @sqrt(@as(f64, 2) / std.math.pi) else 0;
    for (1..intervals) |i| {
        const x = h * @as(f64, @floatFromInt(i));
        const density = @exp((df - 1) * @log(x) - x * x / 2 - (df / 2 - 1) * @log(@as(f64, 2)) - f.lgammaOf(df / 2));
        const probability = f.distCdf(.normal, delta - c * x / @sqrt(df), &.{}).? + f.distCdf(.normal, -delta - c * x / @sqrt(df), &.{}).?;
        sum += (if (i % 2 == 0) @as(f64, 2) else 4) * density * probability;
    }
    return h * sum / 3;
}
test "STAT-COMMON-018 noncentral F power agrees with independent normal chi integration" {
    const d: Design = .{ .difference = 2, .sigma = 3 };
    for ([_]f64{ 72, 74, 100 }) |n| {
        // chi tail above sqrt(df)+12 < exp(-72) by Gaussian norm
        // concentration. Halving Simpson spacing verifies discretization;
        // 2e-10 accommodates beta/normal special-function roundoff, far below
        // the reference listing's +/-0.0005 rounding interval.
        const coarse = conditionalPower(d, n, 4096);
        const fine = conditionalPower(d, n, 8192);
        try std.testing.expectApproxEqAbs(coarse, fine, 1e-11);
        try std.testing.expectApproxEqAbs(fine, d.power(n), 2e-10);
    }
}

test "STAT-POWER-002 one-sample default and independent small-sample power" {
    const t = std.testing;
    const Case = struct { mean: f64, sigma: f64, printed: f64 };
    // Entire scalar quantities from S154 Getting Started, physical pp.7737-7738.
    // Each three-decimal reference owns its +/-0.0005 rounding interval.
    for ([_]Case{ .{ .mean = 8, .sigma = 40, .printed = 0.682 }, .{ .mean = 5, .sigma = 30, .printed = 0.527 }, .{ .mean = 5, .sigma = 50, .printed = 0.229 }, .{ .mean = 10, .sigma = 30, .printed = 0.982 }, .{ .mean = 10, .sigma = 50, .printed = 0.682 } }) |c| {
        const d: Design = .{ .kind = .one_sample, .difference = c.mean, .sigma = c.sigma };
        try t.expect(@abs(d.power(150) - c.printed) < 0.0005);
        const independent = conditionalPower(d, 150, 8192);
        try t.expectApproxEqAbs(independent, d.power(150), 2e-10);
    }
    // At the null, a continuous exact level-alpha test rejects with alpha at
    // every valid N, including N=2. No sampled/golden numeric approximation.
    const null_design: Design = .{ .kind = .one_sample, .difference = 0, .sigma = 3 };
    try t.expectEqual(@as(f64, 0.05), null_design.power(2));
    try t.expectEqual(@as(f64, 0.05), null_design.power(3));
    try t.expect(std.math.isNan(null_design.power(1)));
    // F(1,1) has a heavy tail: at alpha=1e-8 the critical value exceeds
    // the 1e7 bracket. Report a numerical gap rather than capped power.
    try t.expect(std.math.isNan((Design{ .kind = .one_sample, .difference = 1, .sigma = 1, .alpha = 1e-8 }).power(2)));
    const small: Design = .{ .kind = .one_sample, .difference = 1, .sigma = 1 };
    const coarse = conditionalPower(small, 2, 32768);
    const fine = conditionalPower(small, 2, 65536);
    try t.expectApproxEqAbs(coarse, fine, 1e-11);
    try t.expectApproxEqAbs(fine, small.power(2), 2e-10);
}

test "STAT-POWER-002 one-sample inverse preserves executable rounding and direction symmetry" {
    const t = std.testing;
    const d: Design = .{ .kind = .one_sample, .difference = 8, .sigma = 40 };
    const root = d.sampleSize(0.8);
    try t.expectEqual(solver.Status.converged, root.status);
    try t.expectApproxEqAbs(@as(f64, 0.8), d.power(root.x), 1e-10);
    const n = d.executable(root.x);
    try t.expect(d.power(n) >= 0.8);
    try t.expect(d.power(n - 1) < 0.8);
    try t.expectEqual(@ceil(root.x), n);
    try t.expectApproxEqAbs(d.power(150), (Design{ .kind = .one_sample, .difference = -8, .sigma = 40 }).power(150), 1e-14);
    try t.expectApproxEqAbs(d.power(150), (Design{ .kind = .one_sample, .difference = 4, .sigma = 20 }).power(150), 1e-14);
}
