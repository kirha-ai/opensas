//! Shared t-based LS-mean comparison inference (S154 physical pp.492,507).
//! The consumer supplies actual estimable L vectors/model covariance; a missing
//! individual margin never implies that its difference is nonestimable.
const std = @import("std");
const f = @import("../functions.zig");
const ranks = @import("reg_diagnostics.zig");
const linear = @import("glm_estimability.zig");
pub const Adjustment = enum { none, bon, sidak, tukey };
pub const Interval = struct { lower: ?f64 = null, upper: ?f64 = null };
pub const Difference = struct { i: usize, j: usize, coefficients: []const f64, inference: linear.Result, adjusted_p: ?f64 = null, limits: Interval = .{} };
fn comparisons(levels: usize) !f64 {
    if (levels < 2) return error.InvalidInput;
    return @as(f64, @floatFromInt(levels)) * @as(f64, @floatFromInt(levels - 1)) / 2;
}
pub fn probability(raw: f64, levels: usize, adjust: Adjustment) !f64 {
    if (!std.math.isFinite(raw) or raw < 0 or raw > 1) return error.InvalidInput;
    const m = try comparisons(levels);
    return switch (adjust) {
        .none => raw,
        .bon => @min(1, m * raw),
        .sidak => if (raw == 1) 1 else -std.math.expm1(m * std.math.log1p(-raw)),
        .tukey => if (levels == 2) raw else error.UnsupportedAdjustment,
    };
}
pub fn critical(df: f64, alpha: f64, levels: usize, adjust: Adjustment) !f64 {
    if (!std.math.isFinite(df) or df <= 0 or !std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.InvalidInput;
    const tail = switch (adjust) {
        .none => alpha,
        .bon => alpha / (try comparisons(levels)),
        .sidak => -std.math.expm1(std.math.log1p(-alpha) / (try comparisons(levels))),
        .tukey => if (levels == 2) alpha else return error.UnsupportedAdjustment,
    };
    // For two means Q_2=sqrt(2)*abs(T): Tukey's studentized-range critical
    // divided bysqrt(2) is exactly the two-sided t critical, not an approximation.
    const target = 1 - tail / 2;
    const endpoint = f.betaI(df / (df + 1e12), df / 2, 0.5) / 2;
    if (target >= 1 - endpoint or target == 1) return error.NumericalDomain;
    return f.bisectCdf(.t, target, df, 0, -1e6, 1e6);
}
pub fn interval(result: linear.Result, df: usize, alpha: f64, levels: usize, adjust: Adjustment) !Interval {
    if (result.status == .nonestimable or result.standard_error == null or df == 0) return .{};
    const radius = (try critical(@floatFromInt(df), alpha, levels, adjust)) * result.standard_error.?;
    return .{ .lower = result.estimate.? - radius, .upper = result.estimate.? + radius };
}
pub fn difference(a: std.mem.Allocator, fit: ranks.Result, left: []const f64, right: []const f64, i: usize, j: usize, levels: usize, alpha: f64, adjust: Adjustment, singular: f64, with_limits: bool) !Difference {
    if (left.len != right.len) return error.InvalidInput;
    const l = try a.alloc(f64, left.len);
    for (left, right, l) |x, y, *v| v.* = x - y;
    const result = try linear.evaluate(fit, l, singular);
    return .{ .i = i, .j = j, .coefficients = l, .inference = result, .adjusted_p = if (result.p_value) |p| try probability(p, levels, adjust) else null, .limits = if (with_limits) try interval(result, fit.fit.df_error, alpha, levels, adjust) else .{} };
}

test "STAT-COMMON-026 multiplicity corrections and two-level Tukey use exact identities" {
    const t = std.testing;
    try t.expectApproxEqAbs(@as(f64, 0.3), try probability(0.1, 3, .bon), 1e-15);
    try t.expectApproxEqAbs(@as(f64, 0.271), try probability(0.1, 3, .sidak), 1e-15);
    try t.expectEqual(@as(f64, 1), try probability(0.7, 3, .bon));
    // Four levels have six comparisons, not four.
    try t.expectApproxEqAbs(@as(f64, 0.6), try probability(0.1, 4, .bon), 1e-15);
    try t.expectApproxEqAbs(@as(f64, 0.468559), try probability(0.1, 4, .sidak), 1e-15);
    try t.expectApproxEqAbs(@as(f64, 3e-20), try probability(1e-20, 3, .sidak), 1e-34);
    try t.expectEqual(try probability(0.0576, 2, .none), try probability(0.0576, 2, .tukey));
    try t.expectEqual(try critical(9, 0.05, 2, .none), try critical(9, 0.05, 2, .tukey));
    // Independently tabulated Student t9 .975 quantile.
    try t.expectApproxEqAbs(@as(f64, 2.2621571627409915), try critical(9, 0.05, 2, .tukey), 1e-10);
    try t.expectError(error.UnsupportedAdjustment, probability(0.1, 3, .tukey));
    try t.expectError(error.UnsupportedAdjustment, critical(9, 0.05, 3, .tukey));
    try t.expect((try critical(9, 0.05, 3, .bon)) > (try critical(9, 0.05, 3, .sidak)));
    try t.expect((try critical(9, 0.05, 3, .sidak)) > (try critical(9, 0.05, 3, .none)));
}

test "STAT-COMMON-026 differences can be estimable when both margins are not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try ranks.fit(a, &.{ 1, 1, 1, 1, 1, 1 }, &.{ 1, 2, 3 }, 3, 2, null, true, 1e-9);
    try std.testing.expectEqual(linear.Status.nonestimable, (try linear.evaluate(fit, &.{ 0, 1 }, 1e-4)).status);
    try std.testing.expectEqual(linear.Status.nonestimable, (try linear.evaluate(fit, &.{ 1, 2 }, 1e-4)).status);
    const result = try difference(a, fit, &.{ 0, 1 }, &.{ 1, 2 }, 0, 1, 2, 0.05, .none, 1e-4, true);
    try std.testing.expectEqual(linear.Status.estimable, result.inference.status);
    try std.testing.expectApproxEqAbs(@as(f64, -2), result.inference.estimate.?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.inference.variance_factor.?, 1e-12);
    try std.testing.expectApproxEqAbs(1 - @sqrt(@as(f64, 6.0 / 7.0)), result.adjusted_p.?, 1e-12);
}
