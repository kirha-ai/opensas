//! Values underlying histogram/CDF/PP/QQ/probability plots. No graphics.
const std = @import("std");
const diag = @import("../diag.zig");
const distributions = @import("univ_distributions.zig");
const Distribution = distributions.Distribution;
pub const Bin = struct { lower: f64, upper: f64, midpoint: f64, count: usize, observed_percent: f64, expected_percent: ?f64 };

/// Explicit equally spaced endpoints. Trim unoccupied outer bins in output,
/// retaining interior empty bins (OUTHISTOGRAM, printed pp.462–463).
pub fn histogram(a: std.mem.Allocator, d: *diag.Diagnostics, sorted: []const f64, endpoints: []const f64, right_included: bool, curve: ?Distribution) diag.Error![]Bin {
    if (endpoints.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram needs at least two endpoints", .{});
    const width = endpoints[1] - endpoints[0];
    if (!(width > 0) or !std.math.isFinite(width)) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram endpoints must increase", .{});
    for (endpoints[1..], 1..) |v, i| if (!std.math.isFinite(v) or @abs(v - endpoints[i - 1] - width) > 1e-10 * width) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram endpoints must be equally spaced", .{});
    const bins = try a.alloc(Bin, endpoints.len - 1);
    for (bins, 0..) |*bin, i| bin.* = .{ .lower = endpoints[i], .upper = endpoints[i + 1], .midpoint = endpoints[i] / 2 + endpoints[i + 1] / 2, .count = 0, .observed_percent = 0, .expected_percent = if (curve) |c| 100 * (c.cdf(endpoints[i + 1]) - c.cdf(endpoints[i])) else null };
    for (sorted, 0..) |x, j| {
        if (!std.math.isFinite(x) or (j > 0 and x < sorted[j - 1]) or x < endpoints[0] or x > endpoints[endpoints.len - 1]) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram endpoints do not cover the sorted finite sample", .{});
        var at: usize = 0;
        while (at + 1 < bins.len and (if (right_included) x > bins[at].upper else x >= bins[at].upper)) at += 1;
        bins[at].count += 1;
    }
    if (sorted.len == 0) return bins[0..0];
    for (bins) |*bin| bin.observed_percent = 100 * @as(f64, @floatFromInt(bin.count)) / @as(f64, @floatFromInt(sorted.len));
    var start: usize = 0;
    var stop = bins.len;
    while (start < stop and bins[start].count == 0) start += 1;
    while (stop > start and bins[stop - 1].count == 0) stop -= 1;
    return bins[start..stop];
}

pub const Point = struct { observed: f64, probability: f64, theoretical: f64 };
/// Standardized quantiles as in Table 4.35; return reference line separately.
/// Weibull2 uses log(x-theta), log(-log(1-p)), log(sigma), and 1/c.
pub const QuantilePlot = struct { points: []Point, intercept: f64, slope: f64 };
pub fn quantilePlot(a: std.mem.Allocator, d: *diag.Diagnostics, sorted: []const f64, curve: Distribution, rankadj: f64, nadj: f64, weibull2: bool) diag.Error!QuantilePlot {
    try curve.validate(d);
    if (!std.math.isFinite(rankadj) or !std.math.isFinite(nadj)) return d.fail(error.ParseError, 0, "UNIVARIATE: rank adjustments must be finite", .{});
    if (weibull2 and curve.family != .weibull) return d.fail(error.ParseError, 0, "UNIVARIATE: WEIBULL2 requires a Weibull distribution", .{});
    var standard = curve;
    var intercept = curve.p.theta;
    var slope = curve.p.sigma;
    standard.p.theta = 0;
    standard.p.sigma = 1;
    switch (curve.family) {
        .normal, .gumbel => {
            intercept = curve.p.mu;
            standard.p.mu = 0;
        },
        .lognormal => {
            standard.p.sigma = curve.p.sigma;
            standard.p.zeta = 0;
            slope = @exp(curve.p.zeta);
        },
        .igauss, .sb, .su => return d.fail(error.ParseError, 0, "UNIVARIATE: this family is not supported for standardized probability plots", .{}),
        else => {},
    }
    if (weibull2) {
        intercept = @log(curve.p.sigma);
        slope = 1 / curve.p.c;
    }
    const points = try a.alloc(Point, sorted.len);
    for (sorted, points, 0..) |x, *point, i| {
        if (!std.math.isFinite(x) or (i > 0 and x < sorted[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: quantile plot requires a sorted finite sample", .{});
        const p = distributions.rankProbability(i, sorted.len, rankadj, nadj);
        if (!(p > 0 and p < 1)) return d.fail(error.ParseError, 0, "UNIVARIATE: rank adjustments put probabilities outside (0,1)", .{});
        if (weibull2 and x <= curve.p.theta) return d.fail(error.ParseError, 0, "UNIVARIATE: WEIBULL2 observation must exceed THETA", .{});
        point.* = .{ .observed = if (weibull2) @log(x - curve.p.theta) else x, .probability = p, .theoretical = if (weibull2) @log(-std.math.log1p(-p)) else standard.quantile(p) };
    }
    return .{ .points = points, .intercept = intercept, .slope = slope };
}

test "UNIVARIATE histogram SAS percentages and explicit endpoint inclusion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const x = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const fit = @import("univ_distribution_fit.zig");
    const curve = try fit.fit(&d, &x, .{ .family = .normal, .mu = 5 });
    const bins = try histogram(a, &d, &x, &.{ -5, 0, 5, 10, 15, 20, 25 }, false, curve);
    try std.testing.expectEqual(@as(usize, 4), bins.len);
    try std.testing.expectEqual(@as(f64, 50), bins[0].observed_percent);
    try std.testing.expectApproxEqAbs(@as(f64, 36.4544), bins[0].expected_percent.?, 5e-5);
    try std.testing.expectEqual(@as(usize, 1), bins[3].count);
    const right = try histogram(a, &d, &x, &.{ 0, 5, 10, 15, 20 }, true, null);
    try std.testing.expectEqual(@as(usize, 3), right.len);
    try std.testing.expectEqual(@as(usize, 3), right[1].count);
    try std.testing.expectEqual(@as(usize, 1), right[2].count);
    try std.testing.expectError(error.ParseError, histogram(a, &d, &x, &.{ 0, 5, 15 }, false, null));
}

test "UNIVARIATE probability plot Weibull2 transform and reference parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const result = try quantilePlot(a, &d, &.{ 2, 3, 4 }, .{ .family = .weibull, .p = .{ .theta = 1, .sigma = 2, .c = 3 } }, 0.375, 0.25, true);
    try std.testing.expectEqual(@as(f64, 0.5), result.points[1].probability);
    try std.testing.expectApproxEqAbs(@log(@log(@as(f64, 2))), result.points[1].theoretical, 1e-14);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 2)), result.intercept, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.slope, 1e-14);
}
