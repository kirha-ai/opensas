//! Bounded monotone inversion shared by power/sample-size and interval-precision
//! procedures. S154 physical pp.394-396: inverse sample sizes are numerical;
//! executable sample sizes must be handled by the calling design, not the root.
const std = @import("std");
pub const Status = enum { converged, target_below_range, target_above_range, invalid_input, nonfinite_evaluation, iteration_limit };
pub const Result = struct { status: Status, x: f64, value: f64, lower: f64, upper: f64, iterations: usize };
pub const Options = struct { x_tolerance: f64 = 1e-9, max_iterations: usize = 128 };
/// Caller guarantees a continuous nondecreasing function over [lower,upper].
/// A probability endpoint is not silently clamped to a feasible design.
pub fn invert(context: anytype, comptime evaluate: anytype, target: f64, lower: f64, upper: f64, options: Options) Result {
    var r: Result = .{ .status = .invalid_input, .x = lower, .value = std.math.nan(f64), .lower = lower, .upper = upper, .iterations = 0 };
    if (!std.math.isFinite(target) or !std.math.isFinite(lower) or !std.math.isFinite(upper) or lower > upper or !std.math.isFinite(options.x_tolerance) or options.x_tolerance <= 0) return r;
    const fl = evaluate(context, lower);
    const fu = evaluate(context, upper);
    if (!std.math.isFinite(fl) or !std.math.isFinite(fu)) {
        r.status = .nonfinite_evaluation;
        return r;
    }
    if (fl > fu) return r;
    r.value = fl;
    if (target < fl) {
        r.status = .target_below_range;
        return r;
    }
    if (target > fu) {
        r.status = .target_above_range;
        r.x = upper;
        r.value = fu;
        return r;
    }
    if (target == fl or target == fu) {
        r.status = .converged;
        r.x = if (target == fl) lower else upper;
        r.value = target;
        return r;
    }
    while (r.iterations < options.max_iterations) {
        r.iterations += 1;
        r.x = r.lower / 2 + r.upper / 2;
        r.value = evaluate(context, r.x);
        if (!std.math.isFinite(r.value)) {
            r.status = .nonfinite_evaluation;
            return r;
        }
        if (r.value == target or r.upper - r.lower <= options.x_tolerance) {
            r.status = .converged;
            return r;
        }
        if (r.value < target) r.lower = r.x else r.upper = r.x;
    }
    r.status = .iteration_limit;
    return r;
}

test "STAT-COMMON-018 inversion preserves endpoints, infeasibility and convergence status" {
    const F = struct {
        fn square(_: void, x: f64) f64 {
            return x * x;
        }
        fn bad(_: void, _: f64) f64 {
            return std.math.nan(f64);
        }
    };
    const t = std.testing;
    const r = invert({}, F.square, 2, 0, 2, .{});
    try t.expectEqual(Status.converged, r.status);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 2)), r.x, 1e-9);
    try t.expect(r.lower <= @sqrt(@as(f64, 2)) and r.upper >= @sqrt(@as(f64, 2)));
    try t.expectEqual(Status.converged, invert({}, F.square, 0, 0, 2, .{}).status);
    try t.expectEqual(@as(f64, 2), invert({}, F.square, 4, 0, 2, .{}).x);
    try t.expectEqual(Status.target_above_range, invert({}, F.square, 5, 0, 2, .{}).status);
    try t.expectEqual(Status.target_below_range, invert({}, F.square, -1, 0, 2, .{}).status);
    try t.expectEqual(Status.invalid_input, invert({}, F.square, 1, 2, 0, .{}).status);
    try t.expectEqual(Status.nonfinite_evaluation, invert({}, F.bad, 1, 0, 2, .{}).status);
    try t.expectEqual(Status.iteration_limit, invert({}, F.square, 2, 0, 2, .{ .max_iterations = 1 }).status);
}
