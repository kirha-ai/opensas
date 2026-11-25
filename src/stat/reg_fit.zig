//! Ordered, column-scaled QR least squares for REG (STAT-REG-002).
//! Two-pass modified Gram-Schmidt avoids forming X'WX and preserves SAS's
//! first-independent-column alias convention. All sums use compensation.
//! ponytail: a relative QR residual tolerance of 1e-12 detects numerical rank;
//! this is not yet the full SAS SINGULAR=/sweep tolerance policy. Extremely
//! ill-conditioned fits can have unstable coefficients even with stable QR.
//! Caller supplies the intercept, filters missing observations, and reports
//! ExecError diagnostics. Weights are precision weights, NOT frequencies.
const std = @import("std");
const diag = @import("../diag.zig");
const fns = @import("../functions.zig"); // shared statfns probability primitives
const nan = std.math.nan(f64);

pub const ModelStats = struct {
    df_model: usize,
    df_total: usize,
    ss_model: f64,
    ms_model: f64,
    f_value: f64,
    p_value: f64,
    r_square: f64,
    adj_r_square: f64,
};

pub const Fit = struct {
    coefficients: []f64,
    /// MSE-scaled covariance; aliased rows/columns are NaN.
    covariance: []f64,
    /// Covariance before MSE scaling; aliases fixed to zero. Useful for prediction.
    covariance_unscaled: []f64,
    se: []f64,
    aliased: []bool,
    /// Retained coefficients involved in a nonunique parameterization (SAS B).
    biased: []bool,
    fitted: []f64,
    residuals: []f64,
    /// Diagonal of the weighted hat matrix; zero for zero-weight observations.
    leverage: []f64,
    rank: usize,
    n_used: usize,
    df_error: usize,
    sse: f64,
    sst: f64,
    sst_uncorrected: f64,
    y_mean: f64,
    mse: f64,

    pub fn deinit(self: *Fit, a: std.mem.Allocator) void {
        inline for (.{ "coefficients", "covariance", "covariance_unscaled", "se", "aliased", "biased", "fitted", "residuals", "leverage" }) |field| a.free(@field(self, field));
        self.* = undefined;
    }

    /// has_intercept describes the supplied design; it is not inferred from X.
    pub fn modelStats(self: Fit, has_intercept: bool) ModelStats {
        const offset: usize = if (has_intercept and self.rank > 0) 1 else 0;
        const dm = self.rank - offset;
        const dt = self.n_used - offset;
        const total = if (has_intercept) self.sst else self.sst_uncorrected;
        const ss = @max(0, total - self.sse);
        const ms = if (dm > 0) ss / asFloat(dm) else nan;
        const fv = if (dm > 0 and self.df_error > 0 and self.mse > 0) ms / self.mse else nan;
        return .{
            .df_model = dm,
            .df_total = dt,
            .ss_model = ss,
            .ms_model = ms,
            .f_value = fv,
            .p_value = fProbability(fv, dm, self.df_error),
            .r_square = if (total > 0) 1 - self.sse / total else nan,
            .adj_r_square = if (total > 0 and self.df_error > 0) 1 - (self.sse / total) * asFloat(dt) / asFloat(self.df_error) else nan,
        };
    }

    pub fn coefficientT(self: Fit, j: usize) f64 {
        if (j >= self.se.len or !(self.se[j] > 0)) return nan;
        return self.coefficients[j] / self.se[j];
    }

    pub fn coefficientP(self: Fit, j: usize) f64 {
        return tProbability(self.coefficientT(j), self.df_error);
    }
};

/// Two-sided Student t tail, evaluated directly to avoid 1-CDF cancellation.
pub fn tProbability(t: f64, df: usize) f64 {
    if (df == 0 or std.math.isNan(t)) return nan;
    return fns.betaI(1 / (1 + (t / @sqrt(asFloat(df))) * (t / @sqrt(asFloat(df)))), asFloat(df) / 2, 0.5);
}

/// Positive t critical value for a two-sided 1-alpha interval.
pub fn tCritical(alpha: f64, df: usize) f64 {
    if (!(alpha > 0 and alpha < 1) or df == 0) return nan;
    return -@import("univ_inference.zig").tQuantile(alpha / 2, asFloat(df));
}

pub fn fProbability(f: f64, df1: usize, df2: usize) f64 {
    if (df1 == 0 or df2 == 0 or std.math.isNan(f) or f < 0) return nan;
    return fns.betaI(1 / (1 + f * (asFloat(df1) / asFloat(df2))), asFloat(df2) / 2, asFloat(df1) / 2);
}

fn asFloat(x: usize) f64 {
    return @floatFromInt(x);
}

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

fn dot(x: []const f64, y: []const f64) f64 {
    var s: Sum = .{};
    for (x, y) |a, b| s.add(a * b);
    return s.total();
}

/// x is n*p row-major. All inputs must be finite; weights must be nonnegative.
/// Zero-weight rows are excluded from DF/sums but retain fitted/residual values.
/// No positive-weight rows, malformed dimensions, or overflow return ExecError.
/// A saturated fit is valid, with df_error=0 and undefined inference as NaN.
/// Caller owns the returned arrays; temporary storage is freed on every path.
pub fn fit(a: std.mem.Allocator, x: []const f64, y: []const f64, n: usize, p: usize, weights: ?[]const f64) diag.Error!Fit {
    const np = std.math.mul(usize, n, p) catch return error.ExecError;
    const pp = std.math.mul(usize, p, p) catch return error.ExecError;
    if (n == 0 or p == 0 or x.len != np or y.len != n) return error.ExecError;
    if (weights) |w| if (w.len != n) return error.ExecError;
    for (x) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (y) |v| if (!std.math.isFinite(v)) return error.ExecError;
    if (weights) |w| for (w) |v| {
        if (!std.math.isFinite(v) or v < 0) return error.ExecError;
    };

    // An internal arena makes all error paths (including OOM) leak-free.
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    const q = try tmp.alloc(f64, np); // contiguous orthonormal columns
    const r = try tmp.alloc(f64, pp); // basis rows, original-column indices
    @memset(r, 0);
    const v = try tmp.alloc(f64, n);
    const wy = try tmp.alloc(f64, n);
    const sqrt_w = try tmp.alloc(f64, n);
    const scales = try tmp.alloc(f64, p);
    const active = try tmp.alloc(usize, p);
    const qty = try tmp.alloc(f64, p);
    const beta = try tmp.alloc(f64, p);
    @memset(beta, 0);
    const alias = try tmp.alloc(bool, p);
    @memset(alias, true);
    const biased = try tmp.alloc(bool, p);
    @memset(biased, false);
    var n_used: usize = 0;
    var sw: Sum = .{};
    var sy: Sum = .{};
    var anchor: f64 = 0;
    for (0..n) |i| {
        const w = if (weights) |ws| ws[i] else 1;
        sqrt_w[i] = @sqrt(w);
        wy[i] = sqrt_w[i] * y[i];
        if (!std.math.isFinite(wy[i])) return error.ExecError;
        if (w == 0) continue;
        if (n_used == 0) anchor = y[i];
        n_used += 1;
        sw.add(w);
        sy.add(w * (y[i] - anchor));
    }
    if (n_used == 0 or !std.math.isFinite(sw.total())) return error.ExecError;
    const y_mean = anchor + sy.total() / sw.total();
    if (!std.math.isFinite(y_mean)) return error.ExecError;

    var rank: usize = 0;
    for (0..p) |j| {
        // Max scaling avoids squaring large raw predictor values.
        var scale: f64 = 0;
        for (0..n) |i| {
            v[i] = sqrt_w[i] * x[i * p + j];
            if (!std.math.isFinite(v[i])) return error.ExecError;
            scale = @max(scale, @abs(v[i]));
        }
        scales[j] = if (scale > 0) scale else 1;
        if (scale == 0) continue;
        for (v) |*value| value.* /= scale;
        const original_norm = @sqrt(dot(v, v));
        // Reorthogonalization is essential for raw Year/YearSq and aliases.
        for (0..2) |_| {
            for (0..rank) |k| {
                const qk = q[k * n ..][0..n];
                const projection = dot(qk, v);
                r[k * p + j] += projection;
                for (v, qk) |*value, qvalue| value.* -= projection * qvalue;
            }
        }
        const norm = @sqrt(@max(0, dot(v, v)));
        if (rank >= n_used or norm <= 1e-12 * original_norm) continue;
        alias[j] = false;
        active[rank] = j;
        r[rank * p + j] = norm;
        const qk = q[rank * n ..][0..n];
        for (v, qk) |value, *qvalue| qvalue.* = value / norm;
        qty[rank] = dot(qk, wy);
        rank += 1;
    }
    var k = rank;
    while (k > 0) {
        k -= 1;
        const j = active[k];
        var s: Sum = .{};
        for (k + 1..rank) |h| s.add(r[k * p + active[h]] * beta[active[h]]);
        beta[j] = (qty[k] - s.total()) / r[k * p + j];
    }
    // Invert only the retained triangular factor; never invert normal equations.
    const inv = try tmp.alloc(f64, pp);
    @memset(inv, 0);
    for (0..rank) |col| {
        k = col + 1;
        while (k > 0) {
            k -= 1;
            var s: Sum = .{};
            for (k + 1..col + 1) |h| s.add(r[k * p + active[h]] * inv[h * p + col]);
            inv[k * p + col] = ((if (k == col) @as(f64, 1) else 0) - s.total()) / r[k * p + active[k]];
        }
    }
    // Alias relations also identify retained estimates needing SAS's B marker.
    for (0..p) |j| {
        if (!alias[j]) continue;
        for (0..rank) |h| {
            var s: Sum = .{};
            for (h..rank) |c| s.add(inv[h * p + c] * r[c * p + j]);
            if (@abs(s.total()) > 1e-10) biased[active[h]] = true;
        }
    }
    for (beta, scales) |*b, scale| {
        b.* /= scale;
        if (!std.math.isFinite(b.*)) return error.ExecError;
    }
    const fitted = try tmp.alloc(f64, n);
    const residuals = try tmp.alloc(f64, n);
    const leverage = try tmp.alloc(f64, n);
    var rss: Sum = .{};
    var tss: Sum = .{};
    var uss: Sum = .{};
    for (0..n) |i| {
        fitted[i] = dot(x[i * p ..][0..p], beta);
        residuals[i] = y[i] - fitted[i];
        var h: Sum = .{};
        for (0..rank) |j| h.add(q[j * n + i] * q[j * n + i]);
        leverage[i] = @min(1, @max(0, h.total()));
        const er = sqrt_w[i] * residuals[i];
        const centered = sqrt_w[i] * (y[i] - y_mean);
        rss.add(er * er);
        tss.add(centered * centered);
        uss.add(wy[i] * wy[i]);
        if (!std.math.isFinite(fitted[i]) or !std.math.isFinite(residuals[i])) return error.ExecError;
    }
    if (!std.math.isFinite(rss.total()) or !std.math.isFinite(tss.total()) or !std.math.isFinite(uss.total())) return error.ExecError;
    const df_error = n_used - rank;
    const mse = if (df_error > 0) rss.total() / asFloat(df_error) else nan;
    const cov0 = try tmp.alloc(f64, pp);
    const cov = try tmp.alloc(f64, pp);
    const se = try tmp.alloc(f64, p);
    @memset(cov0, 0);
    @memset(cov, nan);
    @memset(se, nan);
    for (0..rank) |i| {
        const row = active[i];
        for (0..rank) |j| {
            const col = active[j];
            const value = dot(inv[i * p ..][0..rank], inv[j * p ..][0..rank]) / scales[row] / scales[col];
            if (!std.math.isFinite(value)) return error.ExecError;
            cov0[row * p + col] = value;
            cov[row * p + col] = value * mse;
            if (df_error > 0 and !std.math.isFinite(cov[row * p + col])) return error.ExecError;
        }
        se[row] = @sqrt(cov[row * p + row]);
    }
    // Copy only final state into the caller's allocator (arena-compatible).
    var result: Fit = .{
        .coefficients = &.{},
        .covariance = &.{},
        .covariance_unscaled = &.{},
        .se = &.{},
        .aliased = &.{},
        .biased = &.{},
        .fitted = &.{},
        .residuals = &.{},
        .leverage = &.{},
        .rank = rank,
        .n_used = n_used,
        .df_error = df_error,
        .sse = rss.total(),
        .sst = tss.total(),
        .sst_uncorrected = uss.total(),
        .y_mean = y_mean,
        .mse = mse,
    };
    errdefer result.deinit(a);
    result.coefficients = try a.dupe(f64, beta);
    result.covariance = try a.dupe(f64, cov);
    result.covariance_unscaled = try a.dupe(f64, cov0);
    result.se = try a.dupe(f64, se);
    result.aliased = try a.dupe(bool, alias);
    result.biased = try a.dupe(bool, biased);
    result.fitted = try a.dupe(f64, fitted);
    result.residuals = try a.dupe(f64, residuals);
    result.leverage = try a.dupe(f64, leverage);
    return result;
}

test "REG independent hand calculation and inference" {
    // y=(1,2,2), x=(0,1,2): beta=(7/6,1/2), SSE=1/6,
    // (X'X)^-1 = ((5/6,-1/2),(-1/2,1/2)), residual df=1.
    var result = try fit(std.testing.allocator, &.{ 1, 0, 1, 1, 1, 2 }, &.{ 1, 2, 2 }, 3, 2, null);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 6.0), result.coefficients[0], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.coefficients[1], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 6.0), result.sse, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), result.sst, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 / 36.0), result.covariance[0], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0 / 12.0), result.covariance[1], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 12.0), result.covariance[3], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 / 6.0), result.leverage[0], 1e-13);
    const stats = result.modelStats(true);
    try std.testing.expectEqual(@as(usize, 1), result.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 3), stats.f_value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), stats.p_value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.coefficientP(1), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), stats.r_square, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.adj_r_square, 1e-13);
}

test "REG SASHELP.CLASS documented default numeric oracle" {
    // Public SASHELP.CLASS sample, S154 physical pp.8542-8543.
    const height = [_]f64{ 69, 56.5, 65.3, 62.8, 63.5, 57.3, 59.8, 62.5, 62.5, 59, 51.3, 64.3, 56.3, 66.5, 72, 64.8, 67, 57.5, 66.5 };
    const weight = [_]f64{ 112.5, 84, 98, 102.5, 102.5, 83, 84.5, 112.5, 84, 99.5, 50.5, 90, 77, 112, 150, 128, 133, 85, 112 };
    var x: [38]f64 = undefined;
    for (height, 0..) |h, i| {
        x[2 * i] = 1;
        x[2 * i + 1] = h;
    }
    var result = try fit(std.testing.allocator, &x, &weight, 19, 2, null);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 19), result.n_used);
    try std.testing.expectEqual(@as(usize, 17), result.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, -143.02692), result.coefficients[0], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 3.89903), result.coefficients[1], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 32.27459), result.se[0], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.51609), result.se[1], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 2142.48772), result.sse, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 9335.73684), result.sst, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0004), result.coefficientP(0), 0.00005);
    try std.testing.expect(result.modelStats(true).p_value < 0.0001);
}

test "REG COMMON-001 and COMMON-003 retained rank covariance and inference" {
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    const z = [_]f64{ 1, 1, 2, 1, 3, 2, 4, 3, 5, 3, 5, 4 };
    var x: [36]f64 = undefined;
    var singular: [48]f64 = undefined;
    for (0..12) |i| {
        const xi = asFloat(i + 1);
        @memcpy(x[3 * i ..][0..3], &[_]f64{ 1, xi, z[i] });
        @memcpy(singular[4 * i ..][0..4], &[_]f64{ 1, xi, 2 * xi, z[i] });
    }
    var result = try fit(std.testing.allocator, &x, &y, 12, 3, null);
    defer result.deinit(std.testing.allocator);
    var deficient = try fit(std.testing.allocator, &singular, &y, 12, 4, null);
    defer deficient.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), deficient.rank);
    try std.testing.expectEqual(@as(usize, 9), deficient.df_error);
    try std.testing.expect(deficient.aliased[2] and deficient.biased[1]);
    try std.testing.expect(!deficient.biased[0] and !deficient.biased[3]);
    try std.testing.expectEqual(@as(f64, 0), deficient.coefficients[2]);
    try std.testing.expect(std.math.isNan(deficient.se[2]));
    const expected_beta = [_]f64{ 1.33390, 1.81763, 0.62407 };
    const expected_se = [_]f64{ 0.76219, 0.17986, 0.44211 };
    const mapped = [_]usize{ 0, 1, 3 };
    for (0..3) |j| {
        try std.testing.expectApproxEqAbs(expected_beta[j], result.coefficients[j], 0.000005);
        try std.testing.expectApproxEqAbs(expected_se[j], result.se[j], 0.000005);
        try std.testing.expectApproxEqAbs(result.coefficients[j], deficient.coefficients[mapped[j]], 1e-12);
        for (0..3) |k| try std.testing.expectApproxEqAbs(result.covariance[j * 3 + k], deficient.covariance[mapped[j] * 4 + mapped[k]], 1e-12);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 12.09695), result.sse, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 604.91667), result.sst, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1140), result.coefficientP(0), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1917), result.coefficientP(2), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 220.53), result.modelStats(true).f_value, 0.005);
    for (result.fitted, deficient.fitted) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-12);
}

test "REG raw Year and YearSq oracle and prediction quantities" {
    const population = [_]f64{ 3929, 5308, 7239, 9638, 12866, 17069, 23191, 31443, 39818, 50155, 62947, 75994, 91972, 105710, 122775, 131669, 151325, 179323, 203211, 226542, 248710, 281422 };
    var y: [22]f64 = undefined;
    var linear: [44]f64 = undefined;
    var quadratic: [66]f64 = undefined;
    var centered: [66]f64 = undefined;
    for (population, 0..) |value, i| {
        const year = 1790 + 10 * asFloat(i);
        y[i] = value / 1000;
        @memcpy(linear[2 * i ..][0..2], &[_]f64{ 1, year });
        @memcpy(quadratic[3 * i ..][0..3], &[_]f64{ 1, year, year * year });
        const t = (year - 1895) / 100;
        @memcpy(centered[3 * i ..][0..3], &[_]f64{ 1, t, t * t });
    }
    var lin = try fit(std.testing.allocator, &linear, &y, 22, 2, null);
    defer lin.deinit(std.testing.allocator);
    var quad = try fit(std.testing.allocator, &quadratic, &y, 22, 3, null);
    defer quad.deinit(std.testing.allocator);
    var stable = try fit(std.testing.allocator, &centered, &y, 22, 3, null);
    defer stable.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f64, -2345.85498), lin.coefficients[0], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.28786), lin.coefficients[1], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 641.58160), lin.mse, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 161.39279), lin.se[0], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, -40.5778), lin.fitted[0], 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 10.4424), @sqrt(lin.mse * lin.leverage[0]), 0.00005);
    const t = tCritical(0.05, lin.df_error);
    const sem = @sqrt(lin.mse * lin.leverage[0]);
    const sep = @sqrt(lin.mse * (1 + lin.leverage[0]));
    try std.testing.expectApproxEqAbs(@as(f64, -62.3602), lin.fitted[0] - t * sem, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -18.7953), lin.fitted[0] + t * sem, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -97.7280), lin.fitted[0] - t * sep, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 16.5725), lin.fitted[0] + t * sep, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 170.97193), quad.sse, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, -24.04581), quad.coefficients[1], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 639.50181), quad.se[0], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.67547), quad.se[1], 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00017820), quad.se[2], 0.000000005);
    try std.testing.expectApproxEqAbs(@as(f64, 6.2127), quad.fitted[0], 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.7565), @sqrt(quad.mse * quad.leverage[0]), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 8864.19), quad.modelStats(true).f_value, 0.005);
    var press: Sum = .{};
    for (quad.residuals, quad.leverage, quad.fitted, stable.fitted) |residual, h, raw, scaled| {
        press.add((residual / (1 - h)) * (residual / (1 - h)));
        try std.testing.expectApproxEqAbs(raw, scaled, 1e-8);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 237.71229), press.total(), 0.000005);
    try std.testing.expectApproxEqAbs(stable.sse, quad.sse, 1e-8);
    // Check covariance-derived mean variance against independent Q row norm.
    var mean_var: Sum = .{};
    for (0..3) |i| for (0..3) |j| mean_var.add(quadratic[i] * quad.covariance[i * 3 + j] * quadratic[j]);
    try std.testing.expectApproxEqAbs(quad.mse * quad.leverage[0], mean_var.total(), 1e-7);
}

test "REG weighted hand calculation zero weights and weight-scale invariance" {
    const x = [_]f64{ 1, 0, 1, 1, 1, 2, 1, 100 };
    const y = [_]f64{ 1, 2, 2, 1000 };
    var result = try fit(std.testing.allocator, &x, &y, 4, 2, &.{ 1, 2, 1, 0 });
    defer result.deinit(std.testing.allocator);
    var scaled = try fit(std.testing.allocator, &x, &y, 4, 2, &.{ 10, 20, 10, 0 });
    defer scaled.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), result.n_used);
    try std.testing.expectEqual(@as(usize, 1), result.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), result.coefficients[0], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.coefficients[1], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), result.sse, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), result.sst, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1875), result.covariance[0], 1e-13);
    try std.testing.expectEqual(@as(f64, 0), result.leverage[3]);
    for (result.covariance, scaled.covariance) |a, b| try std.testing.expectApproxEqAbs(a, b, 1e-13);
    try std.testing.expectApproxEqAbs(10 * result.sse, scaled.sse, 1e-13);
}

test "REG saturated underdetermined zero-design no-intercept and invalid inputs" {
    const a = std.testing.allocator;
    var saturated = try fit(a, &.{ 1, 0, 0, 1, 1, 1 }, &.{ 2, 3 }, 2, 3, null);
    defer saturated.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), saturated.rank);
    try std.testing.expectEqual(@as(usize, 0), saturated.df_error);
    try std.testing.expect(saturated.aliased[2] and std.math.isNan(saturated.mse));
    var zero = try fit(a, &.{ 0, 0 }, &.{ 1, 2 }, 2, 1, null);
    defer zero.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), zero.rank);
    try std.testing.expectEqual(@as(f64, 5), zero.sse);
    var origin = try fit(a, &.{ 1, 2, 3 }, &.{ 1, 2, 2 }, 3, 1, null);
    defer origin.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), origin.modelStats(false).df_total);
    try std.testing.expectApproxEqAbs(@as(f64, 11.0 / 14.0), origin.coefficients[0], 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 121.0 / 126.0), origin.modelStats(false).r_square, 1e-13);
    try std.testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 2, null));
    try std.testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, &.{-1}));
    try std.testing.expectError(error.ExecError, fit(a, &.{1}, &.{1}, 1, 1, &.{0}));
    try std.testing.expectError(error.ExecError, fit(a, &.{nan}, &.{1}, 1, 1, null));
    try std.testing.expectError(error.ExecError, fit(a, &.{1}, &.{std.math.inf(f64)}, 1, 1, null));
    try std.testing.expectError(error.ExecError, fit(a, &.{1}, &.{1e300}, 1, 1, null));
}

fn allocationCheck(a: std.mem.Allocator) !void {
    var result = try fit(a, &.{ 1, 0, 1, 1, 1, 2 }, &.{ 1, 2, 2 }, 3, 2, null);
    defer result.deinit(a);
}

test "REG allocation failures free scratch and partial result" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCheck, .{});
}
