//! LOGISTIC stopping rules, S154 physical pp.5874,5876–5877,5881,5883,5887–5888,5911.
//! Explicit MODEL criteria replace the implicit GCONV default; enabled
//! criteria are combined by OR. Previous states mean accepted iterations.
const std = @import("std");
pub const Reason = enum { gconv, absfconv, fconv, xconv, iteration_limit, not_fit };
pub const Stop = struct { reason: Reason = .gconv, threshold: f64 = 1e-8, metric: f64 = 0 };
pub const Metrics = struct { gradient: f64, absolute_function: ?f64 = null, relative_function: ?f64 = null, parameter: ?f64 = null };
pub const Iteration = struct { index: usize, log_likelihood: f64, metrics: Metrics };
pub fn name(reason: Reason) []const u8 {
    return switch (reason) {
        .gconv => "GCONV",
        .absfconv => "ABSFCONV",
        .fconv => "FCONV",
        .xconv => "XCONV",
        .iteration_limit => "MAXITER",
        .not_fit => "NOFIT",
    };
}
pub fn metrics(ll: f64, b: []const f64, norm: f64, previous_ll: ?f64, previous_b: ?[]const f64) Metrics {
    var result: Metrics = .{ .gradient = norm / (@abs(ll) + 1e-6) };
    if (previous_ll) |old| {
        result.absolute_function = @abs(ll - old);
        result.relative_function = @abs(ll - old) / (@abs(old) + 1e-6);
    }
    if (previous_b) |old| {
        var maximum: f64 = 0;
        for (b, old) |current, previous| maximum = @max(maximum, if (@abs(previous) < 0.01) @abs(current - previous) else @abs((current - previous) / previous));
        result.parameter = maximum;
    }
    return result;
}
pub fn satisfied(options: anytype, state: Metrics) ?Stop {
    if (options.absfconv) |threshold| if (state.absolute_function) |metric| if (metric < threshold) return .{ .reason = .absfconv, .threshold = threshold, .metric = metric };
    if (options.fconv) |threshold| if (state.relative_function) |metric| if (metric < threshold) return .{ .reason = .fconv, .threshold = threshold, .metric = metric };
    if (options.gconv > 0 and state.gradient >= 0 and state.gradient < options.gconv) return .{ .reason = .gconv, .threshold = options.gconv, .metric = state.gradient };
    if (options.xconv) |threshold| if (state.parameter) |metric| if (metric < threshold) return .{ .reason = .xconv, .threshold = threshold, .metric = metric };
    return null;
}
pub fn valid(options: anytype) bool {
    if (options.max_iterations == 0 or options.max_iterations == std.math.maxInt(usize) or options.gconv < 0 or !std.math.isFinite(options.gconv)) return false;
    var active = options.gconv > 0;
    inline for (.{ "absfconv", "fconv", "xconv" }) |field| if (@field(options, field)) |threshold| {
        if (!(threshold > 0) or !std.math.isFinite(threshold)) return false;
        active = true;
    };
    return active;
}
