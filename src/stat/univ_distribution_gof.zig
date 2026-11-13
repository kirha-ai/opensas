//! UNIVARIATE EDF probability conventions, separate from raw EDF statistics.
const std = @import("std");
const dist = @import("univ_distributions.zig");
const fitting = @import("univ_distribution_fit.zig");
const diag = @import("../diag.zig");
pub const Sign = enum { exact, less, greater };
pub const Probability = struct { value: f64, sign: Sign };
pub const Result = struct { statistics: dist.Edf, d: Probability, w2: Probability, a2: Probability };

fn interpolate(value: f64, critical: []const f64, probabilities: []const f64) Probability {
    if (value < critical[0]) return .{ .value = probabilities[0], .sign = .greater };
    for (1..critical.len) |i| if (value <= critical[i]) return .{ .value = probabilities[i - 1] + (value - critical[i - 1]) / (critical[i] - critical[i - 1]) * (probabilities[i] - probabilities[i - 1]), .sign = .exact };
    return .{ .value = probabilities[probabilities.len - 1], .sign = .less };
}

/// Complete-parameter EDF distributions are invariant under the probability
/// integral transform. M9 stores the endpoint probability and a separate sign;
/// the stored endpoint must not be replaced with an extrapolated probability.
pub fn known(statistics: dist.Edf, n: usize) Result {
    std.debug.assert(n > 0);
    const nf: f64 = @floatFromInt(n);
    const probabilities = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.001 };
    return .{
        .statistics = statistics,
        .d = interpolate(statistics.d * (@sqrt(nf) + 0.12 + 0.11 / @sqrt(nf)), &.{ 1.019, 1.138, 1.224, 1.358, 1.480, 1.628, 1.731, 1.950 }, &probabilities),
        .w2 = interpolate((statistics.w2 - 0.4 / nf + 0.6 / (nf * nf)) * (1 + 1 / nf), &.{ 0.209, 0.284, 0.347, 0.461, 0.581, 0.743, 0.869, 1.167 }, &probabilities),
        .a2 = interpolate(statistics.a2, &.{ 1.248, 1.610, 1.933, 2.492, 3.070, 3.880, 4.500, 6.000 }, &probabilities),
    };
}

pub fn compute(d: *diag.Diagnostics, x: []const f64, distribution: dist.Distribution, request: fitting.Request) diag.Error!Result {
    if (x.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF tests require observations", .{});
    if (distribution.family != request.family) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF distribution and parameter request disagree", .{});
    if (request.family == .normal and request.mu == null and request.sigma == null) return normalEstimated(dist.edf(distribution, x).?, x.len);
    const all_known = switch (request.family) {
        .normal => request.mu != null and request.sigma != null,
        .lognormal => request.theta != null and request.zeta != null and request.sigma != null,
        .exponential => request.theta != null and request.sigma != null,
        .gamma, .power => request.theta != null and request.sigma != null and request.alpha != null,
        .weibull => request.theta != null and request.sigma != null and request.c != null,
        .beta => request.theta != null and request.sigma != null and request.alpha != null and request.beta != null,
        .gumbel, .igauss, .pareto, .rayleigh => return d.fail(error.ParseError, 0, "UNIVARIATE: simulated EDF probabilities are not implemented", .{}),
        .sb, .su => return d.fail(error.ParseError, 0, "UNIVARIATE: EDF probabilities are unavailable for Johnson distributions", .{}),
    };
    if (!all_known) return d.fail(error.ParseError, 0, "UNIVARIATE: estimated-parameter EDF probabilities are not implemented", .{});
    return known(dist.edf(distribution, x).?, x.len);
}

pub fn normalEstimated(statistics: dist.Edf, n: usize) Result {
    std.debug.assert(n > 0);
    const nf: f64 = @floatFromInt(n);
    const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005 };
    return .{
        .statistics = statistics,
        .d = interpolate(statistics.d * (@sqrt(nf) - 0.01 + 0.85 / @sqrt(nf)), &.{ 0.775, 0.819, 0.895, 0.955, 1.035 }, &.{ 0.15, 0.10, 0.05, 0.025, 0.01 }),
        .w2 = interpolate(statistics.w2 * (1 + 0.5 / nf), &.{ 0.074, 0.091, 0.104, 0.126, 0.148, 0.178, 0.201 }, &levels),
        .a2 = interpolate(statistics.a2 * (1 + 0.75 / nf + 2.25 / (nf * nf)), &.{ 0.470, 0.561, 0.631, 0.752, 0.873, 1.035, 1.159 }, &levels),
    };
}

test "UNIVARIATE complete-parameter EDF probabilities SAS M9 stored values and signs" {
    // dev4-univ-edf-known-20261113: g=16, n=100, x=Phi^-1(p^1.4).
    const result = known(.{ .d = 0.12819364691435, .w2 = 0.82642690884982, .a2 = 4.94656789806195 }, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 0.07211573250396), result.d.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00651937389133), result.w2.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00380915227183), result.a2.value, 1e-12);
    const high = known(.{ .d = 0.005, .w2 = 0.000833333333333, .a2 = 0.0115 }, 100);
    try std.testing.expectEqual(Sign.greater, high.d.sign);
    try std.testing.expectEqual(@as(f64, 0.25), high.w2.value);
    const low = known(.{ .d = 0.5, .w2 = 3, .a2 = 10 }, 100);
    try std.testing.expectEqual(Sign.less, low.a2.sign);
    try std.testing.expectEqual(@as(f64, 0.001), low.a2.value);
    // Independent family: fully specified beta(2,3), n=12, retained beta probe.
    const beta = known(.{ .d = 0.28255208, .w2 = 0.28816861, .a2 = 5.36529733 }, 12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.248), beta.d.value, 0.0005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.155), beta.w2.value, 0.0005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.003), beta.a2.value, 0.0005);
    const small = known(.{ .d = 0.05, .w2 = 0.24226917403858, .a2 = 1.50521137435919 }, 20);
    try std.testing.expectApproxEqAbs(@as(f64, 0.21538982301264), small.w2.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.17894713415491), small.a2.value, 1e-12);
    const large = known(.{ .d = 0.05237359333768, .w2 = 0.72166739439574, .a2 = 4.07471388745455 }, 500);
    try std.testing.expectApproxEqAbs(@as(f64, 0.12694672993993), large.d.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01191559870513), large.w2.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00842972671407), large.a2.value, 1e-12);
}

test "UNIVARIATE estimated-parameter requests cannot reuse known-parameter probabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    try std.testing.expectError(error.ParseError, compute(&d, &.{ 1, 2, 3 }, .{ .family = .normal, .p = .{} }, .{ .family = .normal, .mu = 0 }));
}

test "UNIVARIATE fitted-normal histogram EDF lower-tail knots match SAS M9" {
    const r = normalEstimated(.{ .d = 0.06316825604689, .w2 = 0.13635603505674, .a2 = 0.8901915619608 }, 100);
    try std.testing.expectEqual(Sign.greater, r.d.sign);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03745702814542), r.w2.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02277145446509), r.a2.value, 1e-12);
    const tail = normalEstimated(.{ .d = 0.1, .w2 = 0.1872120512639994 / 1.005, .a2 = 1 }, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00799738016), tail.w2.value, 1e-12);
}
