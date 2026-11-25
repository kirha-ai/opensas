//! TTEST arithmetic-mean core (STAT-TTEST-002); no parsing or rendering.
//! S154 physical pp.10596-10603,10616-10618. FREQ replicates observations;
//! WEIGHT changes precision, not degrees of freedom. For retained observations,
//! n=sum(freq), df=n-1, variance=sum(freq*weight*(x-mean)^2)/df,
//! SEM=std_dev/sqrt(sum(freq*weight)). No weight normalization is performed.
//! Shifted, compensated two-pass moments avoid subtracting raw sums of squares.
//! Caller filters missing/nonpositive FREQ/WEIGHT before invoking this core and
//! emits diagnostics for ExecError. Empty data and nonfinite arithmetic fail;
//! n=1 and zero variance retain descriptive results but undefined t tests are NaN.
const std = @import("std");
const diag = @import("../diag.zig");
const fns = @import("../functions.zig");
const inference = @import("univ_inference.zig");
const nan = std.math.nan(f64);
const inf = std.math.inf(f64);

/// upper is SAS SIDES=U (alternative mean > h0); lower is SIDES=L.
pub const Sides = enum { two_sided, upper, lower };
pub const Options = struct {
    h0: f64 = 0,
    alpha: f64 = 0.05,
    sides: Sides = .two_sided,
};
pub const Interval = struct { lower: f64 = nan, upper: f64 = nan };
pub const Result = struct {
    n: usize,
    sum_weights: f64,
    mean: f64,
    std_dev: f64 = nan,
    std_err: f64 = nan,
    minimum: f64 = nan,
    maximum: f64 = nan,
    df: f64,
    t: f64 = nan,
    p: f64 = nan,
    mean_ci: Interval = .{},
    std_dev_ci: Interval = .{},
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

fn validate(options: Options) diag.Error!void {
    if (!std.math.isFinite(options.h0) or !(options.alpha > 0 and options.alpha < 1)) return error.ExecError;
    // The shared chi-square inverse accepts a CDF probability. Do not silently
    // replace unrepresentable equal-tail probabilities by zero-width/infinite CIs.
    if (options.alpha / 2 == 0 or 1 - options.alpha / 2 == 1) return error.ExecError;
}

/// Signed one-/two-sided t probabilities, including fractional (Welch) df.
/// Evaluate the small beta tail directly; avoid subtracting a rounded CDF.
pub fn tProbability(t: f64, df: f64, sides: Sides) f64 {
    if (!(df > 0) or !std.math.isFinite(df) or std.math.isNan(t)) return nan;
    const magnitude = @abs(t);
    const ratio = @sqrt(df) / magnitude;
    const x = if (magnitude <= @sqrt(df)) 1 / (1 + (magnitude / @sqrt(df)) * (magnitude / @sqrt(df))) else (ratio * ratio) / (1 + ratio * ratio);
    const two_tail = if (x > 0) fns.betaI(x, df / 2, 0.5) else if (std.math.isInf(t)) @as(f64, 0) else blk: {
        // When x underflows, log(x) is still representable; the omitted terms
        // in I_x(a,b) are O(x), below f64 precision in this branch.
        const a = df / 2;
        const log_x = @log(df) - 2 * @log(magnitude);
        break :blk @exp(a * log_x - @log(a) - fns.lgammaOf(a) - fns.lgammaOf(0.5) + fns.lgammaOf(a + 0.5));
    };
    const small = 0.5 * @min(1, @max(0, two_tail));
    return switch (sides) {
        .two_sided => 2 * small,
        .upper => if (t >= 0) small else 1 - small,
        .lower => if (t <= 0) small else 1 - small,
    };
}

/// Normal-theory, equal-tailed standard-deviation interval, independent of SIDES.
/// Uses the existing shared chi-square inverse via UNIVARIATE's variance CI.
fn stdDevInterval(sd: f64, df: f64, alpha: f64) diag.Error!Interval {
    if (!(df > 0)) return .{};
    // Invert with unit CSS to avoid overflow from df*sd*sd.
    const variance = inference.varianceCI(1, df, .{}, alpha);
    const result: Interval = .{ .lower = sd * @sqrt(df * variance.lower), .upper = sd * @sqrt(df * variance.upper) };
    if (!std.math.isFinite(result.lower) or !std.math.isFinite(result.upper)) return error.ExecError;
    return result;
}

fn infer(result: *Result, options: Options) diag.Error!void {
    if (!(result.df > 0)) return;
    result.std_err = result.std_dev / @sqrt(result.sum_weights);
    if (!std.math.isFinite(result.std_err)) return error.ExecError;
    const tail = if (options.sides == .two_sided) options.alpha / 2 else options.alpha;
    const critical = -inference.tQuantile(tail, result.df);
    const margin = critical * result.std_err;
    result.mean_ci = .{
        .lower = if (options.sides == .lower) -inf else result.mean - margin,
        .upper = if (options.sides == .upper) inf else result.mean + margin,
    };
    if ((options.sides != .lower and !std.math.isFinite(result.mean_ci.lower)) or
        (options.sides != .upper and !std.math.isFinite(result.mean_ci.upper))) return error.ExecError;
    result.std_dev_ci = try stdDevInterval(result.std_dev, result.df, options.alpha);
    if (result.std_err > 0) {
        result.t = (result.mean - options.h0) / result.std_err;
        if (!std.math.isFinite(result.t)) return error.ExecError;
        result.p = tProbability(result.t, result.df, options.sides);
        if (!std.math.isFinite(result.p)) return error.ExecError;
    }
}

/// No allocation. Inputs are retained, finite observations; optional slices have
/// values.len entries. Frequencies >=1 are truncated; weights must be positive.
/// n is capped at the lesser of maxInt(usize) and 2^53-1 to preserve exact DF.
pub fn oneSample(values: []const f64, frequencies: ?[]const f64, weights: ?[]const f64, options: Options) diag.Error!Result {
    try validate(options);
    if (values.len == 0) return error.ExecError;
    if (frequencies) |freq| if (freq.len != values.len) return error.ExecError;
    if (weights) |ws| if (ws.len != values.len) return error.ExecError;
    var result: Result = .{ .n = 0, .sum_weights = 0, .mean = 0, .df = 0, .minimum = inf, .maximum = -inf };
    var sum_weights: Sum = .{};
    var shifted: Sum = .{};
    const max_n: usize = @min(std.math.maxInt(usize), 9007199254740991);
    for (values, 0..) |value, i| {
        const frequency = if (frequencies) |freq| @trunc(freq[i]) else 1;
        const weight = if (weights) |ws| ws[i] else 1;
        if (!std.math.isFinite(value) or !std.math.isFinite(frequency) or frequency < 1 or frequency > @as(f64, @floatFromInt(max_n)) or
            !std.math.isFinite(weight) or !(weight > 0)) return error.ExecError;
        const count: usize = @intFromFloat(frequency);
        if (count > max_n - result.n) return error.ExecError;
        result.n += count;
        const w = frequency * weight;
        sum_weights.add(w);
        shifted.add(w * (value - values[0]));
        result.minimum = @min(result.minimum, value);
        result.maximum = @max(result.maximum, value);
    }
    result.sum_weights = sum_weights.total();
    if (!(result.sum_weights > 0) or !std.math.isFinite(result.sum_weights)) return error.ExecError;
    const shift = shifted.total() / result.sum_weights;
    result.mean = values[0] + shift;
    if (!std.math.isFinite(result.mean)) return error.ExecError;
    result.df = @floatFromInt(result.n - 1);
    if (result.n > 1) {
        var css: Sum = .{};
        for (values, 0..) |value, i| {
            const frequency = if (frequencies) |freq| @trunc(freq[i]) else 1;
            const weight = if (weights) |ws| ws[i] else 1;
            const deviation = (value - values[0]) - shift;
            // Square after sqrt-weight scaling, so tiny precision weights can
            // accompany large finite deviations without raw-square overflow.
            const scaled = @sqrt(frequency * weight) * deviation;
            css.add(scaled * scaled);
        }
        result.std_dev = @sqrt(css.total() / result.df);
        if (!std.math.isFinite(result.std_dev)) return error.ExecError;
        try infer(&result, options);
    }
    return result;
}

/// Unweighted summary-statistics input (FREQ/WEIGHT are disallowed by TTEST).
/// Minimum/maximum remain NaN because summary N/MEAN/STD does not supply them.
pub fn fromSummary(n: usize, mean: f64, std_dev: f64, options: Options) diag.Error!Result {
    try validate(options);
    if (n == 0 or n > @min(std.math.maxInt(usize), 9007199254740991) or !std.math.isFinite(mean) or !std.math.isFinite(std_dev) or std_dev < 0) return error.ExecError;
    var result: Result = .{
        .n = n,
        .sum_weights = @floatFromInt(n),
        .mean = mean,
        .std_dev = if (n > 1) std_dev else nan,
        .df = @floatFromInt(n - 1),
    };
    try infer(&result, options);
    return result;
}

const court = [_]f64{ 43, 90, 84, 87, 116, 95, 86, 99, 93, 92, 121, 71, 66, 98, 79, 102, 60, 112, 105, 98 };

// Oracle tables round to four decimal places: 5e-5 is a half-display-unit,
// not a blanket probability tolerance. Independent identities below use 1e-12.
test "TTEST court default oracle and documented 90 percent upper interval" {
    const r = try oneSample(&court, null, null, .{});
    try std.testing.expectEqual(@as(usize, 20), r.n);
    try std.testing.expectEqual(@as(f64, 19), r.df);
    try std.testing.expectApproxEqAbs(@as(f64, 89.85), r.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 19.1456), r.std_dev, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 4.2811), r.std_err, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 80.8896), r.mean_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 98.8104), r.mean_ci.upper, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 14.5601), r.std_dev_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 27.9636), r.std_dev_ci.upper, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 20.99), r.t, 0.005);
    try std.testing.expect(r.p < 0.0001);
    try std.testing.expectEqual(@as(f64, 43), r.minimum);
    try std.testing.expectEqual(@as(f64, 121), r.maximum);
    const upper = try oneSample(&court, null, null, .{ .h0 = 80, .alpha = 0.1, .sides = .upper });
    try std.testing.expectApproxEqAbs(@as(f64, 84.1659), upper.mean_ci.lower, 0.00005);
    try std.testing.expectEqual(inf, upper.mean_ci.upper);
    try std.testing.expectApproxEqAbs(@as(f64, 15.2002), upper.std_dev_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 26.2374), upper.std_dev_ci.upper, 0.00005);
}

test "TTEST COMMON-005 signed tails and mean intervals" {
    const two = try oneSample(&court, null, null, .{ .h0 = 80 });
    const upper = try oneSample(&court, null, null, .{ .h0 = 80, .sides = .upper });
    const lower = try oneSample(&court, null, null, .{ .h0 = 80, .sides = .lower });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0329), two.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0164), upper.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9836), lower.p, 0.00005);
    try std.testing.expectApproxEqAbs(two.p, 2 * upper.p, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), upper.p + lower.p, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 82.4474), upper.mean_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 97.2526), lower.mean_ci.upper, 0.00005);
    try std.testing.expectEqual(inf, upper.mean_ci.upper);
    try std.testing.expectEqual(-inf, lower.mean_ci.lower);
    try std.testing.expectEqual(two.std_dev_ci, upper.std_dev_ci);
    try std.testing.expectEqual(two.std_dev_ci, lower.std_dev_ci);
    // Reflect the observations and h0: tails and bounds must reverse.
    var reflected: [20]f64 = undefined;
    for (court, &reflected) |value, *negative| negative.* = -value;
    const reversed = try oneSample(&reflected, null, null, .{ .h0 = -80, .sides = .lower });
    try std.testing.expectApproxEqAbs(upper.p, reversed.p, 1e-13);
    try std.testing.expectApproxEqAbs(-upper.mean_ci.lower, reversed.mean_ci.upper, 1e-12);
}

test "TTEST independent hand moments Student Cauchy and chi-square df2" {
    // x=(1,2,3): mean=2, CSS=2, variance=1, SEM=1/sqrt(3), df=2.
    // Chi-square(2) has Q(p)=-2*ln(1-p), independently checking both SD limits.
    const r = try oneSample(&.{ 1, 2, 3 }, null, null, .{ .h0 = 2 });
    try std.testing.expectEqual(@as(f64, 2), r.mean);
    try std.testing.expectEqual(@as(f64, 1), r.std_dev);
    try std.testing.expectApproxEqAbs(1 / @sqrt(@as(f64, 3)), r.std_err, 1e-14);
    try std.testing.expectEqual(@as(f64, 0), r.t);
    try std.testing.expectEqual(@as(f64, 1), r.p);
    try std.testing.expectApproxEqAbs(@sqrt(2 / (-2 * @log(@as(f64, 0.025)))), r.std_dev_ci.lower, 1e-11);
    try std.testing.expectApproxEqAbs(@sqrt(2 / (-2 * @log(@as(f64, 0.975)))), r.std_dev_ci.upper, 1e-10);
    // Student(1) is Cauchy: two-sided tail at 1 is 1/2; at sqrt(3), 1/3.
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), tProbability(1, 1, .two_sided), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), tProbability(@sqrt(@as(f64, 3)), 1, .two_sided), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), tProbability(-1, 1, .upper), 1e-13);
    // For large t the Cauchy two-tail is 2/(pi*t) to relative O(1/t^2).
    try std.testing.expectApproxEqRel(@as(f64, 2.0 / (std.math.pi * 1e100)), tProbability(1e100, 1, .two_sided), 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 2.0 / (std.math.pi * 1e200)), tProbability(1e200, 1, .two_sided), 1e-12);
}

test "TTEST001 frequency and precision weight oracle all BY variable cells" {
    const frequency = [_]f64{ 1, 2, 1, 1, 1, 1 };
    const weight = [_]f64{ 1, 1, 2, 1, 1, 2 };
    const samples = [_][6]f64{
        .{ 43, 90, 84, 87, 116, 95 }, .{ 40, 84, 88, 80, 110, 91 },
        .{ 86, 99, 93, 92, 121, 71 }, .{ 79, 101, 90, 85, 115, 72 },
    };
    const means = [_]f64{ 87.1111, 84.0000, 91.6667, 89.4444 };
    const sd = [_]f64{ 22.1393, 21.4398, 17.5973, 16.6244 };
    const sem = [_]f64{ 7.3798, 7.1466, 5.8658, 5.5415 };
    const lo_mean = [_]f64{ 69.0535, 66.5129, 77.3136, 75.8850 };
    const lo_sd = [_]f64{ 14.2664, 13.8157, 11.3396, 10.7126 };
    const hi_sd = [_]f64{ 48.7522, 47.2119, 38.7505, 36.6080 };
    for (samples, 0..) |sample, i| {
        const r = try oneSample(&sample, &frequency, &weight, .{});
        try std.testing.expectEqual(@as(usize, 7), r.n);
        try std.testing.expectEqual(@as(f64, 6), r.df);
        try std.testing.expectEqual(@as(f64, 9), r.sum_weights);
        try std.testing.expectApproxEqAbs(means[i], r.mean, 0.00005);
        try std.testing.expectApproxEqAbs(sd[i], r.std_dev, 0.00005);
        try std.testing.expectApproxEqAbs(sem[i], r.std_err, 0.00005);
        try std.testing.expectApproxEqAbs(lo_mean[i], r.mean_ci.lower, 0.00005);
        try std.testing.expectApproxEqAbs(lo_sd[i], r.std_dev_ci.lower, 0.00005);
        try std.testing.expectApproxEqAbs(hi_sd[i], r.std_dev_ci.upper, 0.00005);
    }
}

test "TTEST frequency replication versus weight scaling and shifted moments" {
    const r = try oneSample(&.{ 1, 3 }, &.{ 1.9, 2.1 }, &.{ 2, 1 }, .{});
    const expanded = try oneSample(&.{ 1, 3, 3 }, null, &.{ 2, 1, 1 }, .{});
    // n=3, W=4, mean=2, weighted CSS=4, variance=2, SEM=sqrt(1/2).
    try std.testing.expectEqual(@as(usize, 3), r.n);
    try std.testing.expectEqual(@as(f64, 2), r.mean);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2)), r.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.5)), r.std_err, 1e-14);
    try std.testing.expectApproxEqAbs(r.std_dev, expanded.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(r.p, expanded.p, 1e-14);
    const scaled = try oneSample(&.{ 1, 3 }, &.{ 1, 2 }, &.{ 8, 4 }, .{});
    try std.testing.expectEqual(r.n, scaled.n);
    try std.testing.expectApproxEqAbs(2 * r.std_dev, scaled.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(r.std_err, scaled.std_err, 1e-14);
    try std.testing.expectApproxEqAbs(r.p, scaled.p, 1e-14);
    const shifted = try oneSample(&.{ 1e12 + 1, 1e12 + 3 }, &.{ 1, 2 }, &.{ 2, 1 }, .{ .h0 = 1e12 });
    try std.testing.expectApproxEqAbs(r.std_dev, shifted.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(r.t, shifted.t, 1e-14);
}

test "TTEST summary input degenerate samples and validation" {
    const raw = try oneSample(&court, null, null, .{ .h0 = 80 });
    const summary = try fromSummary(raw.n, raw.mean, raw.std_dev, .{ .h0 = 80 });
    try std.testing.expectApproxEqAbs(raw.p, summary.p, 1e-14);
    try std.testing.expectEqual(raw.mean_ci, summary.mean_ci);
    try std.testing.expectEqual(raw.std_dev_ci, summary.std_dev_ci);
    try std.testing.expect(std.math.isNan(summary.minimum));
    const single = try oneSample(&.{2}, null, null, .{});
    try std.testing.expectEqual(@as(f64, 0), single.df);
    try std.testing.expect(std.math.isNan(single.t) and std.math.isNan(single.std_dev));
    const constant = try oneSample(&.{ 2, 2, 2 }, null, null, .{});
    try std.testing.expectEqual(@as(f64, 0), constant.std_dev);
    try std.testing.expectEqual(@as(f64, 2), constant.mean_ci.lower);
    try std.testing.expect(std.math.isNan(constant.t) and std.math.isNan(constant.p));
    try std.testing.expect(std.math.isNan(tProbability(1, 0, .two_sided)));
    try std.testing.expectError(error.ExecError, oneSample(&.{}, null, null, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{nan}, null, null, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, &.{}, null, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, &.{0.9}, null, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, null, &.{0}, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, null, &.{inf}, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, &.{1e30}, null, .{}));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, null, null, .{ .alpha = 0 }));
    try std.testing.expectError(error.ExecError, oneSample(&.{1}, null, null, .{ .h0 = inf }));
    try std.testing.expectError(error.ExecError, oneSample(&.{ -1e308, 1e308 }, null, null, .{}));
    try std.testing.expectError(error.ExecError, fromSummary(3, 1, -1, .{}));
}
