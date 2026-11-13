//! UNIVARIATE EDF probability conventions, separate from raw EDF statistics.
const std = @import("std");
const dist = @import("univ_distributions.zig");
const fitting = @import("univ_distribution_fit.zig");
const diag = @import("../diag.zig");
const inference = @import("univ_edf_inference.zig");
pub const Sign = inference.Sign;
pub const Probability = inference.Probability;
pub const Result = struct { statistics: dist.Edf, d: ?Probability, w2: ?Probability, a2: ?Probability, simulation: ?inference.SimulationResult = null };

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
    const raw = dist.edf(distribution, x).?;
    const stats: inference.Statistics = .{ .d = raw.d, .w2 = raw.w2, .a2 = raw.a2 };
    const r: inference.Request = .{
        .family = std.meta.stringToEnum(inference.Family, @tagName(request.family)).?,
        .estimated = .{ .theta = request.theta == null, .sigma = request.sigma == null, .mu = request.mu == null, .zeta = request.zeta == null, .alpha = request.alpha == null, .beta = request.beta == null, .c = request.c == null, .lambda = request.lambda == null },
        .alpha = distribution.p.alpha,
        .beta = distribution.p.beta,
        .sigma = distribution.p.sigma,
        .c = distribution.p.c,
    };
    switch (request.family) {
        .gumbel, .igauss, .pareto, .rayleigh => {
            const sample = try d.arena.alloc(f64, x.len);
            defer d.arena.free(sample);
            var bootstrap: Bootstrap = .{ .sample = sample, .distribution = distribution, .request = request };
            const result = try inference.simulate(d, r, stats, x.len, .{ .seed = try fitting.resolveSeed(d, request.edfseed), .samples = request.edfnsamples }, .{ .context = &bootstrap, .draw = Bootstrap.draw });
            return .{ .statistics = raw, .d = result.probabilities.d, .w2 = result.probabilities.w2, .a2 = result.probabilities.a2, .simulation = result };
        },
        else => {},
    }
    const result = try inference.tabulated(d, r, stats, x.len);
    return .{ .statistics = raw, .d = result.d, .w2 = result.w2, .a2 = result.a2 };
}

const Bootstrap = struct {
    sample: []f64,
    distribution: dist.Distribution,
    request: fitting.Request,
    fn draw(context: ?*anyopaque, random: std.Random, n: usize, d: *diag.Diagnostics) diag.Error!inference.Statistics {
        const self: *Bootstrap = @ptrCast(@alignCast(context.?));
        std.debug.assert(self.sample.len == n);
        for (self.sample) |*value| {
            // Open (0,1), with exactly representable half-unit endpoints.
            const u = (@as(f64, @floatFromInt(random.int(u64) >> 12)) + 0.5) / 4503599627370496.0;
            value.* = self.distribution.quantile(u);
            if (!std.math.isFinite(value.*)) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF generation failed; no replication was discarded", .{});
        }
        std.mem.sort(f64, self.sample, {}, std.sort.asc(f64));
        var request = self.request;
        var report: fitting.Report = .{};
        request.report = &report;
        request.trace = null;
        request.itprint = false;
        request.optprint = false;
        const fitted = fitting.fit(d, self.sample, request) catch return d.fail(error.ParseError, 0, "UNIVARIATE: EDF refit failed; no replication was discarded", .{});
        if (!report.converged) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF refit did not converge; no replication was discarded", .{});
        const raw = dist.edf(fitted, self.sample).?;
        return .{ .d = raw.d, .w2 = raw.w2, .a2 = raw.a2 };
    }
};

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
    try std.testing.expectApproxEqAbs(@as(f64, 0.07211573250396), result.d.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00651937389133), result.w2.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00380915227183), result.a2.?.value, 1e-12);
    const high = known(.{ .d = 0.005, .w2 = 0.000833333333333, .a2 = 0.0115 }, 100);
    try std.testing.expectEqual(Sign.greater, high.d.?.sign);
    try std.testing.expectEqual(@as(f64, 0.25), high.w2.?.value);
    const low = known(.{ .d = 0.5, .w2 = 3, .a2 = 10 }, 100);
    try std.testing.expectEqual(Sign.less, low.a2.?.sign);
    try std.testing.expectEqual(@as(f64, 0.001), low.a2.?.value);
    // Independent family: fully specified beta(2,3), n=12, retained beta probe.
    const beta = known(.{ .d = 0.28255208, .w2 = 0.28816861, .a2 = 5.36529733 }, 12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.248), beta.d.?.value, 0.0005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.155), beta.w2.?.value, 0.0005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.003), beta.a2.?.value, 0.0005);
    const small = known(.{ .d = 0.05, .w2 = 0.24226917403858, .a2 = 1.50521137435919 }, 20);
    try std.testing.expectApproxEqAbs(@as(f64, 0.21538982301264), small.w2.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.17894713415491), small.a2.?.value, 1e-12);
    const large = known(.{ .d = 0.05237359333768, .w2 = 0.72166739439574, .a2 = 4.07471388745455 }, 500);
    try std.testing.expectApproxEqAbs(@as(f64, 0.12694672993993), large.d.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01191559870513), large.w2.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00842972671407), large.a2.?.value, 1e-12);
}

test "UNIVARIATE estimated-parameter requests cannot reuse known-parameter probabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const partial = try compute(&d, &.{ 1, 2, 3 }, .{ .family = .normal, .p = .{} }, .{ .family = .normal, .mu = 0 });
    try std.testing.expect(partial.d == null and partial.w2 != null and partial.a2 != null);
}

test "UNIVARIATE fitted-normal histogram EDF lower-tail knots match SAS M9" {
    const r = normalEstimated(.{ .d = 0.06316825604689, .w2 = 0.13635603505674, .a2 = 0.8901915619608 }, 100);
    try std.testing.expectEqual(Sign.greater, r.d.?.sign);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03745702814542), r.w2.?.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02277145446509), r.a2.?.value, 1e-12);
    const tail = normalEstimated(.{ .d = 0.1, .w2 = 0.1872120512639994 / 1.005, .a2 = 1 }, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00799738016), tail.w2.?.value, 1e-12);
}

test "UNIVARIATE EDF adapter generates and refits actual family samples with a fixed seed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var x: [40]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const u = std.math.pow(f64, (@as(f64, @floatFromInt(i)) + 0.5) / 40, 1.5);
        v.* = @sqrt(-2 * std.math.log1p(-u));
    }
    // SAS M9, dev5-edf-mc.sas: independent 10,000-replicate reference.
    const cases = [_]struct { request: fitting.Request, probabilities: [3]f64 }{
        .{ .request = .{ .family = .rayleigh, .sigma = 1 }, .probabilities = .{ 0.2269, 0.0462, 0.0305 } },
        .{ .request = .{ .family = .rayleigh }, .probabilities = .{ 0.6012, 0.2315, 0.1294 } },
        .{ .request = .{ .family = .gumbel, .mu = 0, .sigma = 1 }, .probabilities = .{ 0, 0.0001, 0.0001 } },
        .{ .request = .{ .family = .igauss, .mu = 1, .lambda = 1 }, .probabilities = .{ 0.188, 0.077, 0.095 } },
        .{ .request = .{ .family = .pareto, .sigma = 1, .alpha = -0.5 }, .probabilities = .{ 0.1288, 0.0704, 0.0454 } },
    };
    for (cases) |case| {
        var request = case.request;
        request.edfseed = 86531;
        request.edfnsamples = 2000;
        const curve = try fitting.fit(&d, &x, request);
        const result = try compute(&d, &x, curve, request);
        try std.testing.expectEqual(@as(usize, 2000), result.simulation.?.samples);
        try std.testing.expectEqual(@as(u64, 86531), result.simulation.?.seed);
        for ([_]f64{ result.d.?.value, result.w2.?.value, result.a2.?.value }, case.probabilities) |actual, reference| {
            const pooled = @max((actual + reference) / 2, 1.0 / 2000.0);
            const tolerance = 5 * @sqrt(pooled * (1 - pooled) * (1.0 / 2000.0 + 1.0 / 10000.0)) + 1.0 / 2000.0;
            try std.testing.expectApproxEqAbs(reference, actual, tolerance);
        }
    }
    const request: fitting.Request = .{ .family = .rayleigh, .edfseed = 91, .edfnsamples = 30 };
    const curve = try fitting.fit(&d, &x, request);
    const first = try compute(&d, &x, curve, request);
    const again = try compute(&d, &x, curve, request);
    try std.testing.expectEqualDeep(first, again);
    var invalid = request;
    invalid.maxiter = 0;
    try std.testing.expectError(error.ParseError, compute(&d, &x, curve, invalid));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "no replication was discarded") != null);
}

test "UNIVARIATE estimated-family MC callbacks agree with independent M9 probes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var x: [40]f64 = undefined;
    var gp: [40]f64 = undefined;
    for (&x, &gp, 0..) |*v, *p, i| {
        const u = std.math.pow(f64, (@as(f64, @floatFromInt(i)) + 0.5) / 40, 1.5);
        v.* = @sqrt(-2 * std.math.log1p(-u));
        p.* = (std.math.pow(f64, 1 - u, -0.3) - 1) / 0.3;
    }
    const cases = [_]struct { id: []const u8, request: fitting.Request, probabilities: [3]f64 }{
        .{ .id = "ge", .request = .{ .family = .gumbel }, .probabilities = .{ 1, 0.9894, 0.9924 } },
        .{ .id = "gm", .request = .{ .family = .gumbel, .mu = 0 }, .probabilities = .{ 0, 0, 0 } },
        .{ .id = "gs", .request = .{ .family = .gumbel, .sigma = 1 }, .probabilities = .{ 0.0132, 0.0006, 0.0004 } },
        .{ .id = "ie", .request = .{ .family = .igauss }, .probabilities = .{ 0.022, 0.0014, 0.0012 } },
        .{ .id = "im", .request = .{ .family = .igauss, .mu = 1 }, .probabilities = .{ 0.0972, 0.0336, 0.0404 } },
        .{ .id = "il", .request = .{ .family = .igauss, .lambda = 1 }, .probabilities = .{ 0.1134, 0.0206, 0.0246 } },
        .{ .id = "pa", .request = .{ .family = .pareto, .alpha = -0.3 }, .probabilities = .{ 0.8004, 0.4602, 0.2696 } },
        .{ .id = "pe", .request = .{ .family = .pareto }, .probabilities = .{ 0.9728, 0.8428, 0.6252 } },
    };
    for (cases) |case| {
        var d = diag.Diagnostics.init(a);
        var request = case.request;
        request.edfseed = 86531;
        request.edfnsamples = 1000;
        const sample: []const f64 = if (request.family == .pareto) &gp else &x;
        const fitted = try fitting.fit(&d, sample, request);
        const result = compute(&d, sample, fitted, request) catch |err| {
            std.debug.print("MC probe {s}: {s}\n", .{ case.id, @errorName(err) });
            for (d.list.items) |entry| std.debug.print("{s}\n", .{entry.message});
            return err;
        };
        try std.testing.expectEqual(@as(usize, 1000), result.simulation.?.samples);
        for ([_]f64{ result.d.?.value, result.w2.?.value, result.a2.?.value }, case.probabilities) |actual, reference| {
            const pooled = @max((actual + reference) / 2, 1.0 / 1000.0);
            const tolerance = 5 * @sqrt(pooled * (1 - pooled) * (1.0 / 1000.0 + 1.0 / 5000.0)) + 1.0 / 1000.0;
            try std.testing.expectApproxEqAbs(reference, actual, tolerance);
        }
    }
}
