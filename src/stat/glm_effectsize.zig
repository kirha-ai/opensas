//! Effect-size computations for GLM F tests (S154 physical pp.4121–4122).
//! This is a computational foundation, not an EFFECTSIZE listing producer.
//! Predictor values are fixed, so population eta² = NC/(NC+N), not a random-X
//! approximation. Negative point estimates are retained as the guide requires.
const std = @import("std");
const diag = @import("../diag.zig");
const f = @import("../functions.zig");

pub const Interval = struct { lower: f64, upper: f64 };
pub const Summary = struct {
    nc_umvue: f64,
    nc_min_mse: f64,
    nc_interval: Interval,
    semipartial_eta: f64,
    semipartial_omega: f64,
    semipartial_interval: Interval,
    partial_eta: f64,
    partial_omega: f64,
    partial_interval: Interval,
};
pub const Input = struct {
    ss: f64,
    sse: f64,
    total_ss: f64,
    df: usize,
    df_error: usize,
    n: usize,
    alpha: f64 = 0.05,
};

/// Poisson-mixture CDF with an explicit omitted-mass bound. The existing
/// noncentralFCdf helper stops at 1e-7 mass, insufficient for interval inversion.
/// Keep that shared helper untouched; this consumer requires a 1e-14 tail.
/// NC<=1000 avoids underflow at the initial Poisson weight exp(-NC/2).
pub fn noncentralCdf(x: f64, df: f64, dfe: f64, nc: f64) diag.Error!f64 {
    if (!std.math.isFinite(x) or x < 0 or !std.math.isFinite(df) or df <= 0 or !std.math.isFinite(dfe) or dfe <= 0 or !std.math.isFinite(nc) or nc < 0 or nc > 1000) return error.ExecError;
    if (x == 0) return 0;
    const product = df * x;
    if (!std.math.isFinite(product) or !std.math.isFinite(product + dfe)) return error.ExecError;
    const z = product / (product + dfe);
    if (nc == 0) return f.betaI(z, df / 2, dfe / 2);
    const lambda = nc / 2;
    var weight = @exp(-lambda);
    var sum: f64 = 0;
    for (0..2000) |j| {
        const jf: f64 = @floatFromInt(j);
        const beta = f.betaI(z, df / 2 + jf, dfe / 2);
        if (!std.math.isFinite(beta) or beta < 0 or beta > 1) return error.ExecError;
        sum += weight * beta;
        const next = weight * lambda / (jf + 1);
        // After the Poisson mode successive ratios decrease. Their geometric
        // majorant bounds ALL remaining CDF terms because 0<=I_z(a,b)<=1.
        if (jf + 2 > lambda and next / (1 - lambda / (jf + 2)) <= 1e-14) return @min(1, sum);
        weight = next;
    }
    return error.ExecError;
}

/// Invert F_CDF(x;df,dfe,NC)=p. A root below the nonnegative parameter space
/// is reported as zero. A root beyond the validated domain fails, never clips.
pub fn noncentrality(x: f64, df: f64, dfe: f64, p: f64) diag.Error!f64 {
    if (!std.math.isFinite(p) or p <= 0 or p >= 1) return error.ExecError;
    if (try noncentralCdf(x, df, dfe, 0) <= p) return 0;
    var lo: f64 = 0;
    var hi: f64 = 1;
    while (try noncentralCdf(x, df, dfe, hi) > p) {
        if (hi == 1000) return error.ExecError;
        lo = hi;
        hi = @min(1000, 2 * hi);
    }
    for (0..80) |_| {
        const mid = lo + (hi - lo) / 2;
        if (try noncentralCdf(x, df, dfe, mid) > p) lo = mid else hi = mid;
        if (hi - lo <= 2e-12 * @max(1, hi)) return lo + (hi - lo) / 2;
    }
    return error.ExecError;
}
fn interval(x: f64, df: f64, dfe: f64, alpha: f64) diag.Error!Interval {
    return .{ .lower = try noncentrality(x, df, dfe, 1 - alpha / 2), .upper = try noncentrality(x, df, dfe, alpha / 2) };
}
fn proportion(nc: Interval, n: f64) Interval {
    return .{ .lower = nc.lower / (nc.lower + n), .upper = nc.upper / (nc.upper + n) };
}

/// Supported domain has positive residual SS, DFE>4 (finite variance for the
/// min-MSE noncentrality estimate), and nondegenerate corrected total SS.
/// Zero effect SS is valid; zero residual variation and unsupported domains
/// return ExecError so future PROC integration cannot manufacture intervals.
pub fn compute(input: Input) diag.Error!Summary {
    const ss = input.ss;
    const sse = input.sse;
    const total = input.total_ss;
    if (!std.math.isFinite(ss) or ss < 0 or !std.math.isFinite(sse) or sse <= 0 or !std.math.isFinite(total) or total <= ss or input.df == 0 or input.df_error <= 4 or input.n <= input.df or input.n - input.df <= 1 or !std.math.isFinite(input.alpha) or input.alpha <= 0 or input.alpha >= 1) return error.ExecError;
    if (input.df_error > input.n - input.df - 1 or sse > total) return error.ExecError;
    const df: f64 = @floatFromInt(input.df);
    const dfe: f64 = @floatFromInt(input.df_error);
    const n: f64 = @floatFromInt(input.n);
    const mse = sse / dfe;
    const observed_f = ss / (df * mse);
    const nc = try interval(observed_f, df, dfe, input.alpha);
    // Conservative semipartial limits use a synthetic reduced ANOVA with
    // SSE=total-SS and DFE=N-DF-1; S154 physical p.4122.
    const reduced_dfe = n - df - 1;
    const reduced_f = (ss / df) / ((total - ss) / reduced_dfe);
    const semi_nc = try interval(reduced_f, df, reduced_dfe, input.alpha);
    return .{
        .nc_umvue = df * (dfe - 2) * observed_f / dfe - df,
        .nc_min_mse = df * (dfe - 4) * observed_f / dfe - df * (dfe - 4) / (dfe - 2),
        .nc_interval = nc,
        .semipartial_eta = ss / total,
        .semipartial_omega = (ss - df * mse) / (total + mse),
        .semipartial_interval = proportion(semi_nc, n),
        .partial_eta = ss / (ss + sse),
        .partial_omega = (ss - df * mse) / (ss + (n - df) * mse),
        .partial_interval = proportion(nc, n),
    };
}

test "GLM006 noncentral F inversion agrees with independent closed form" {
    // For DF=DFE=2, I_z(1+j,1)=z^(j+1), so the entire Poisson series
    // sums exactly to z*exp(-NC*(1-z)/2). No beta/Poisson implementation is
    // used by this reference; inverse NC=-2 log(p/z)/(1-z).
    // Budget eight roundoff units per term over the hard 2000-term cap,
    // plus the explicit omitted-mass bound. Root tolerance is derived below
    // from the exact CDF derivative, not from an observed root discrepancy.
    const cdf_budget = 8 * 2000 * std.math.floatEps(f64) + 1e-14;
    for ([_]f64{ 0.1, 1, 4, 20 }) |x| {
        const z = x / (x + 1);
        for ([_]f64{ 0, 0.01, 1, 10, 100, 1000 }) |nc| {
            const exact = z * @exp(-nc * (1 - z) / 2);
            try std.testing.expectApproxEqAbs(exact, try noncentralCdf(x, 2, 2, nc), cdf_budget);
        }
        const p = z / 3;
        const exact_root = -2 * @log(p / z) / (1 - z);
        const derivative = p * (1 - z) / 2;
        const root_budget = 2 * cdf_budget / derivative + 2e-12 * @max(1, exact_root);
        try std.testing.expectApproxEqAbs(exact_root, try noncentrality(x, 2, 2, p), root_budget);
    }
    try std.testing.expectEqual(@as(f64, 0), try noncentrality(4, 2, 2, 0.9));
    try std.testing.expectEqual(@as(f64, 0), try noncentrality(0, 2, 2, 0.5));
    try std.testing.expectError(error.ExecError, noncentrality(1e6, 2, 2, 0.05));
    try std.testing.expectError(error.ExecError, noncentralCdf(1, 2, 2, 1001));
}

test "GLM006 effect sizes reproduce published Figure 53.16 rounding bins" {
    // S154 physical pp.4123–4124. Exact rational ANOVA from the 56 public
    // Response observations: corrected total=265107/1400, SSE=504/5,
    // Gender SS=5041/350, Task SS=106847/2800, interaction SS=100799/2800.
    // Published values are checked at HALF a final displayed decimal unit,
    // not a tolerance selected after observing implementation discrepancies.
    const references = [_][12]f64{
        .{ 4.72, 4.48, 0.521, 17.1, 0.0761, 0.0626, 0.0019, 0.2030, 0.1250, 0.0820, 0.0092, 0.2342 },
        .{ 9.14, 8.69, 0.870, 27.3, 0.2015, 0.1239, 0.0000, 0.2772, 0.2746, 0.1502, 0.0153, 0.3277 },
        .{ 8.29, 7.87, 0.463, 25.9, 0.1901, 0.1126, 0.0000, 0.2639, 0.2632, 0.1385, 0.0082, 0.3160 },
    };
    for ([_]f64{ 5041.0 / 350.0, 106847.0 / 2800.0, 100799.0 / 2800.0 }, [_]usize{ 1, 6, 6 }, references) |ss, df, reference| {
        const s = try compute(.{ .ss = ss, .sse = 504.0 / 5.0, .total_ss = 265107.0 / 1400.0, .df = df, .df_error = 42, .n = 56, .alpha = 0.1 });
        const values = [_]f64{ s.nc_umvue, s.nc_min_mse, s.nc_interval.lower, s.nc_interval.upper, s.semipartial_eta, s.semipartial_omega, s.semipartial_interval.lower, s.semipartial_interval.upper, s.partial_eta, s.partial_omega, s.partial_interval.lower, s.partial_interval.upper };
        for (values, reference, 0..) |actual, expected, i| try std.testing.expectApproxEqAbs(expected, actual, @as(f64, if (i < 2) 0.005 else if (i == 2) 0.0005 else if (i == 3) 0.05 else 0.00005));
    }
}

test "GLM006 effect-size zero effects negative estimates scaling and domain failures" {
    const input: Input = .{ .ss = 0, .sse = 40, .total_ss = 80, .df = 2, .df_error = 10, .n = 16 };
    const zero = try compute(input);
    try std.testing.expectEqual(@as(f64, -2), zero.nc_umvue);
    try std.testing.expectEqual(@as(f64, -1.5), zero.nc_min_mse);
    try std.testing.expectEqual(@as(f64, 0), zero.partial_eta);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0 / 7.0), zero.partial_omega, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, -2.0 / 21.0), zero.semipartial_omega, 1e-14);
    try std.testing.expectEqual(Interval{ .lower = 0, .upper = 0 }, zero.nc_interval);
    var changed = input;
    changed.ss = 20;
    const original = try compute(changed);
    changed.ss *= 100;
    changed.sse *= 100;
    changed.total_ss *= 100;
    const scaled = try compute(changed);
    inline for (.{ "nc_umvue", "nc_min_mse", "semipartial_eta", "semipartial_omega", "partial_eta", "partial_omega" }) |field| try std.testing.expectApproxEqAbs(@field(original, field), @field(scaled, field), 1e-12);
    inline for (.{ "nc_interval", "semipartial_interval", "partial_interval" }) |field| {
        try std.testing.expectApproxEqAbs(@field(original, field).lower, @field(scaled, field).lower, 1e-10);
        try std.testing.expectApproxEqAbs(@field(original, field).upper, @field(scaled, field).upper, 1e-10);
    }
    changed = input;
    changed.df_error = 4;
    try std.testing.expectError(error.ExecError, compute(changed));
    changed = input;
    changed.sse = 0;
    try std.testing.expectError(error.ExecError, compute(changed));
    changed = input;
    changed.alpha = 1;
    try std.testing.expectError(error.ExecError, compute(changed));
}
