//! TTEST arithmetic/geometric mean and CV extension (STAT-TTEST-003).
//! S154 physical p.10620 defines geometric mean and CV; p.10622 specifies
//! log(data), log(H0), normal analysis, and back-transformed confidence limits.
//! H0 defaults to 1 for lognormal data (physical p.10605). CI=EQUAL only.
//! Nonpositive responses are omitted with a warning; missing responses are
//! omitted separately. Confirmed with live SAS 9.4 on invented inputs, as are
//! all-omitted output and zero-variance t/CV-CI conventions (2026-11-25).
const std = @import("std");
const diag = @import("../diag.zig");
const normal = @import("ttest_fit.zig");
const format = @import("../format.zig");
const nan = std.math.nan(f64);
const inf = std.math.inf(f64);

pub const Options = struct {
    /// On the original response scale. Explicit H0<=0 is an error.
    h0: f64 = 1,
    alpha: f64 = 0.05,
    sides: normal.Sides = .two_sided,
    line: usize = 0,
};
pub const Result = struct {
    /// Means, SDs, and SEM in this member are on the natural-log scale.
    /// Its n/df/t/p are also the lognormal listing's n/df/t/p.
    log_fit: normal.Result,
    geometric_mean: f64 = nan,
    cv: f64 = nan,
    mean_ci: normal.Interval = .{},
    cv_ci: normal.Interval = .{},
    minimum: f64 = nan,
    maximum: f64 = nan,
    omitted_nonpositive: usize = 0,
    omitted_missing: usize = 0,
};

/// Dimensionless arithmetic CV (not a percentage), per physical p.10620.
/// Preserve the mean's sign; an undefined/zero denominator yields missing.
pub fn arithmeticCv(mean: f64, std_dev: f64) f64 {
    if (!std.math.isFinite(mean) or mean == 0 or !std.math.isFinite(std_dev) or std_dev < 0) return nan;
    const cv = std_dev / mean;
    return if (std.math.isFinite(cv)) cv else nan;
}

/// sqrt(exp(log_sd^2)-1), accurate near zero and without avoidable exp overflow.
/// A truly unrepresentable CV returns infinity; oneSample reports that as error.
pub fn cvFromLogSd(log_sd: f64) f64 {
    if (std.math.isNan(log_sd) or log_sd < 0) return nan;
    const variance = log_sd * log_sd;
    if (variance <= 1) return @sqrt(std.math.expm1(variance));
    return @exp(variance / 2) * @sqrt(-std.math.expm1(-variance));
}

fn finiteTransform(value: f64, d: *diag.Diagnostics, line: usize) diag.Error!f64 {
    if (std.math.isNan(value)) return nan;
    const transformed = @exp(value);
    if (!std.math.isFinite(transformed)) return d.fail(error.ExecError, line, "PROC TTEST: lognormal result exceeds the numeric range", .{});
    return transformed;
}

/// Retain positive finite response values after the caller's FREQ/WEIGHT
/// selection; NaN responses and nonpositive responses are omitted here.
/// Optional frequency/weight slices have values.len entries and are compacted
/// alongside responses. Fractional FREQ truncation and weight semantics reuse
/// ttest_fit. No returned memory requires deinit; scratch is always freed.
/// The diagnostics argument is required so omitted invalid data cannot be silent.
/// If nothing remains, return N=DF=0 and missing statistics, matching SAS.
pub fn oneSample(a: std.mem.Allocator, values: []const f64, frequencies: ?[]const f64, weights: ?[]const f64, options: Options, d: *diag.Diagnostics) diag.Error!Result {
    if (!(options.h0 > 0) or !std.math.isFinite(options.h0)) return d.fail(error.ExecError, options.line, "H0 must be greater than zero for a test of a mean ratio or when lognormal data is assumed.", .{});
    if (!(options.alpha > 0 and options.alpha < 1) or options.alpha / 2 == 0 or 1 - options.alpha / 2 == 1)
        return d.fail(error.ExecError, options.line, "PROC TTEST: ALPHA must define representable confidence limits between 0 and 1", .{});
    if (frequencies) |freq| if (freq.len != values.len) return d.fail(error.ExecError, options.line, "PROC TTEST: frequency length differs from response length", .{});
    if (weights) |w| if (w.len != values.len) return d.fail(error.ExecError, options.line, "PROC TTEST: weight length differs from response length", .{});

    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    const logs = try tmp.alloc(f64, values.len);
    const freq = if (frequencies != null) try tmp.alloc(f64, values.len) else null;
    const weight = if (weights != null) try tmp.alloc(f64, values.len) else null;
    var result: Result = .{ .log_fit = .{ .n = 0, .sum_weights = 0, .mean = nan, .df = 0 } };
    var used: usize = 0;
    for (values, 0..) |value, i| {
        if (std.math.isNan(value)) {
            result.omitted_missing += 1;
            continue;
        }
        if (!std.math.isFinite(value)) return d.fail(error.ExecError, options.line, "PROC TTEST: nonfinite lognormal response", .{});
        if (value <= 0) {
            result.omitted_nonpositive += 1;
            continue;
        }
        logs[used] = @log(value);
        if (freq) |fs| fs[used] = frequencies.?[i];
        if (weight) |ws| ws[used] = weights.?[i];
        if (used == 0) {
            result.minimum = value;
            result.maximum = value;
        } else {
            result.minimum = @min(result.minimum, value);
            result.maximum = @max(result.maximum, value);
        }
        used += 1;
    }
    if (result.omitted_nonpositive > 0) try d.report(.warning, options.line, "{d} observations with invalid response values have been deleted. The response was less than or equal to zero for the lognormal distribution.", .{result.omitted_nonpositive});
    if (used == 0) return result;
    const log_h0 = @log(options.h0);
    result.log_fit = normal.oneSample(logs[0..used], if (freq) |fs| fs[0..used] else null, if (weight) |ws| ws[0..used] else null, .{ .h0 = log_h0, .alpha = options.alpha, .sides = options.sides }) catch |err| {
        if (err == error.ExecError) return d.fail(error.ExecError, options.line, "PROC TTEST: invalid frequency/weight or nonfinite lognormal calculation", .{});
        return err;
    };
    const fit = &result.log_fit;
    result.geometric_mean = try finiteTransform(fit.mean, d, options.line);
    if (!(result.geometric_mean > 0)) return d.fail(error.ExecError, options.line, "PROC TTEST: geometric mean is below the numeric range", .{});
    result.cv = cvFromLogSd(fit.std_dev);
    result.mean_ci = .{
        .lower = if (fit.mean_ci.lower == -inf) 0 else try finiteTransform(fit.mean_ci.lower, d, options.line),
        .upper = if (fit.mean_ci.upper == inf) inf else try finiteTransform(fit.mean_ci.upper, d, options.line),
    };
    if (fit.std_dev > 0) result.cv_ci = .{
        .lower = cvFromLogSd(fit.std_dev_ci.lower),
        .upper = cvFromLogSd(fit.std_dev_ci.upper),
    };
    if (std.math.isInf(result.cv) or std.math.isInf(result.cv_ci.lower) or std.math.isInf(result.cv_ci.upper))
        return d.fail(error.ExecError, options.line, "PROC TTEST: lognormal coefficient of variation exceeds the numeric range", .{});
    if (fit.df > 0 and fit.std_dev == 0) {
        // SAS reports a signed infinite t for a nonzero numerator; 0/0 stays
        // missing. CV=0 has missing CV confidence limits, not a [0,0] CI.
        const delta = fit.mean - log_h0;
        if (delta != 0) {
            fit.t = if (delta < 0) -inf else inf;
            fit.p = normal.tProbability(fit.t, fit.df, options.sides);
        }
    }
    return result;
}

fn number(a: std.mem.Allocator, value: f64, spec: []const u8) diag.Error![]const u8 {
    if (std.math.isInf(value)) return if (value < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}

/// Optional lognormal listing body. Caller emits procedure/variable/BY headers.
/// show_cv_ci=false supports CI=NONE; true is CI=EQUAL. No UMPU computation.
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), result: Result, options: Options, show_cv_ci: bool) diag.Error!void {
    const r = result;
    try out.appendSlice(a, "Geometric Coefficient\nN Mean of Variation Minimum Maximum\n");
    try out.print(a, "{s} {s} {s} {s} {s}\n\n", .{
        try number(a, @floatFromInt(r.log_fit.n), "best12."), try number(a, r.geometric_mean, "d8.3"),
        try number(a, r.cv, "d8.3"),                          try number(a, r.minimum, "d8.3"),
        try number(a, r.maximum, "d8.3"),
    });
    const level = try number(a, 100 * (1 - options.alpha), "best8.");
    try out.print(a, "Geometric Coefficient\nMean {s}% CL Mean of Variation", .{level});
    if (show_cv_ci) try out.print(a, " {s}% CL CV", .{level});
    try out.print(a, "\n{s} {s} {s} {s}", .{
        try number(a, r.geometric_mean, "d8.3"), try number(a, r.mean_ci.lower, "d8.3"),
        try number(a, r.mean_ci.upper, "d8.3"),  try number(a, r.cv, "d8.3"),
    });
    if (show_cv_ci) try out.print(a, " {s} {s}", .{ try number(a, r.cv_ci.lower, "d8.3"), try number(a, r.cv_ci.upper, "d8.3") });
    const tail: []const u8 = switch (options.sides) {
        .two_sided => "Pr > |t|",
        .upper => "Pr > t",
        .lower => "Pr < t",
    };
    try out.print(a, "\n\nDF t Value {s}\n{s} {s} {s}\n\n", .{
        tail, try number(a, r.log_fit.df, "best8."), try number(a, r.log_fit.t, "8.2"), try number(a, r.log_fit.p, "pvalue6.4"),
    });
}

const sample = [_]f64{ 43, 90, 84, 87, 116, 95, 86, 99, 93, 92, 121, 71 };

test "LOGNORMAL TTEST003 unchanged numeric oracle normal and lognormal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const arithmetic = try normal.oneSample(&sample, null, null, .{});
    const geometric = try oneSample(std.testing.allocator, &sample, null, null, .{}, &d);
    try std.testing.expectEqual(@as(usize, 12), geometric.log_fit.n);
    try std.testing.expectEqual(@as(f64, 11), geometric.log_fit.df);
    // 5e-5 is half the oracle's four-decimal display unit; coarser fields
    // (102.4,103.2,t-values) receive their own half-display-unit tolerance.
    try std.testing.expectApproxEqAbs(@as(f64, 89.75), arithmetic.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 19.9687), arithmetic.std_dev, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 5.7645), arithmetic.std_err, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 77.0625), arithmetic.mean_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 102.4), arithmetic.mean_ci.upper, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 14.1457), arithmetic.std_dev_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 33.9045), arithmetic.std_dev_ci.upper, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 87.2660), geometric.geometric_mean, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2682), geometric.cv, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 73.8122), geometric.mean_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 103.2), geometric.mean_ci.upper, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1883), geometric.cv_ci.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4708), geometric.cv_ci.upper, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 58.75), geometric.log_fit.t, 0.005);
    try std.testing.expect(geometric.log_fit.p < 0.0001);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    var out: std.ArrayList(u8) = .empty;
    try render(arena.allocator(), &out, geometric, .{}, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "12 87.2660 0.2682 43.0000 121.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "87.2660 73.8122 103.2 0.2682 0.1883 0.4708") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "11 58.75 <.0001") != null);
}

test "LOGNORMAL independent exact log moments and chi-square transforms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    // logs=(0,1,2): mean=1, variance=1, SEM=1/sqrt(3), df=2.
    const e = @exp(@as(f64, 1));
    const r = try oneSample(std.testing.allocator, &.{ 1, e, e * e }, null, null, .{ .h0 = e }, &d);
    try std.testing.expectApproxEqAbs(e, r.geometric_mean, 1e-13);
    try std.testing.expectApproxEqAbs(@sqrt(e - 1), r.cv, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0), r.log_fit.t, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.log_fit.p, 1e-13);
    // Student(2) CDF has elementary inverse: t=sqrt(2)*u/sqrt(1-u^2).
    const u: f64 = 0.95;
    const t = @sqrt(@as(f64, 2)) * u / @sqrt(1 - u * u);
    try std.testing.expectApproxEqAbs(@exp(1 - t / @sqrt(@as(f64, 3))), r.mean_ci.lower, 1e-12);
    try std.testing.expectApproxEqAbs(@exp(1 + t / @sqrt(@as(f64, 3))), r.mean_ci.upper, 1e-10);
    // Chi-square(2) quantiles are -2*ln(1-p); transform variance endpoints.
    try std.testing.expectApproxEqAbs(@sqrt(std.math.expm1(-1 / @log(@as(f64, 0.025)))), r.cv_ci.lower, 1e-11);
    try std.testing.expectApproxEqRel(@sqrt(std.math.expm1(-1 / @log(@as(f64, 0.975)))), r.cv_ci.upper, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), arithmeticCv(8, 2), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, -0.25), arithmeticCv(-8, 2), 1e-15);
    try std.testing.expect(std.math.isNan(arithmeticCv(0, 2)));
    try std.testing.expectApproxEqRel(@as(f64, 1e-10), cvFromLogSd(1e-10), 1e-14);
    // exp(900) overflows, but sqrt(exp(900)-1) ~= exp(450) is representable.
    try std.testing.expectApproxEqRel(@exp(@as(f64, 450)), cvFromLogSd(30), 1e-14);
}

test "LOGNORMAL scale invariance original H0 and one-sided support" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const r = try oneSample(std.testing.allocator, &sample, null, null, .{ .h0 = 80, .sides = .upper }, &d);
    var scaled: [12]f64 = undefined;
    for (sample, &scaled) |x, *v| v.* = x * 10;
    const other = try oneSample(std.testing.allocator, &scaled, null, null, .{ .h0 = 800, .sides = .upper }, &d);
    try std.testing.expectApproxEqRel(r.geometric_mean * 10, other.geometric_mean, 1e-13);
    try std.testing.expectApproxEqRel(r.mean_ci.lower * 10, other.mean_ci.lower, 1e-13);
    try std.testing.expectApproxEqAbs(r.cv, other.cv, 1e-13);
    try std.testing.expectApproxEqAbs(r.cv_ci.upper, other.cv_ci.upper, 1e-13);
    try std.testing.expectApproxEqAbs(r.log_fit.t, other.log_fit.t, 1e-12);
    try std.testing.expectApproxEqAbs(r.log_fit.p, other.log_fit.p, 1e-13);
    try std.testing.expectEqual(inf, r.mean_ci.upper);
    const lower = try oneSample(std.testing.allocator, &sample, null, null, .{ .h0 = 80, .sides = .lower }, &d);
    try std.testing.expectEqual(@as(f64, 0), lower.mean_ci.lower);
    try std.testing.expectApproxEqAbs(@as(f64, 1), lower.log_fit.p + r.log_fit.p, 1e-14);
    try std.testing.expectEqual(r.cv_ci, lower.cv_ci);
}

test "LOGNORMAL response deletion warnings preserve frequency weight alignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const e = @exp(@as(f64, 1));
    const r = try oneSample(std.testing.allocator, &.{ -1, 1, 0, nan, e }, &.{ 10, 1.9, 8, 4, 2.1 }, &.{ 3, 2, 7, 6, 1 }, .{ .line = 17 }, &d);
    try std.testing.expectEqual(@as(usize, 3), r.log_fit.n);
    try std.testing.expectEqual(@as(f64, 4), r.log_fit.sum_weights);
    try std.testing.expectApproxEqAbs(@exp(@as(f64, 0.5)), r.geometric_mean, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), r.log_fit.std_dev * r.log_fit.std_dev, 1e-14);
    try std.testing.expectEqual(@as(usize, 2), r.omitted_nonpositive);
    try std.testing.expectEqual(@as(usize, 1), r.omitted_missing);
    try std.testing.expectEqual(@as(f64, 1), r.minimum);
    try std.testing.expectEqual(e, r.maximum);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expectEqual(@as(usize, 17), d.list.items[0].line);
    try std.testing.expect(!d.hasErrors());
    const all = try oneSample(std.testing.allocator, &.{ -1, 0, nan }, null, null, .{}, &d);
    try std.testing.expectEqual(@as(usize, 0), all.log_fit.n);
    try std.testing.expectEqual(@as(f64, 0), all.log_fit.df);
    try std.testing.expect(std.math.isNan(all.geometric_mean) and std.math.isNan(all.cv));
}

test "LOGNORMAL zero variance and invalid H0 captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const constant = try oneSample(std.testing.allocator, &.{ 2, 2, 2 }, null, null, .{}, &d);
    try std.testing.expectEqual(@as(f64, 0), constant.cv);
    try std.testing.expectEqual(@as(f64, 2), constant.mean_ci.lower);
    try std.testing.expect(std.math.isNan(constant.cv_ci.lower));
    try std.testing.expectEqual(inf, constant.log_fit.t);
    try std.testing.expectEqual(@as(f64, 0), constant.log_fit.p);
    const equal = try oneSample(std.testing.allocator, &.{ 2, 2, 2 }, null, null, .{ .h0 = 2 }, &d);
    try std.testing.expect(std.math.isNan(equal.log_fit.t));
    const single = try oneSample(std.testing.allocator, &.{2}, null, null, .{}, &d);
    try std.testing.expect(std.math.isNan(single.cv) and std.math.isNan(single.mean_ci.lower));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{ 1, 2 }, null, null, .{ .h0 = 0 }, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{ 1, 2 }, null, null, .{ .h0 = -1 }, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{inf}, null, null, .{}, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{1}, &.{}, null, .{}, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{1}, null, &.{-1}, .{}, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{1}, null, null, .{ .alpha = 1 }, &d));
    try std.testing.expectError(error.ExecError, oneSample(std.testing.allocator, &.{ 1e-300, 1e300 }, null, null, .{}, &d));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "H0 must be greater than zero") != null);
}

fn allocationCheck(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    _ = try oneSample(a, &.{ 0, 1, 2, 3 }, &.{ 1, 1, 2, 1 }, &.{ 1, 1, 1, 2 }, .{}, &d);
}

test "LOGNORMAL allocation failures preserve caller and scratch ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCheck, .{});
}
