//! UNIVARIATE EDF probability conventions, separate from raw EDF statistics.
const std = @import("std");
const dist = @import("univ_distributions.zig");
const fitting = @import("univ_distribution_fit.zig");
const diag = @import("../diag.zig");
const inference = @import("univ_edf_inference.zig");
pub const Sign = inference.Sign;
pub const Probability = inference.Probability;
pub const AccountedSimulator = inference.AccountedSimulator;
pub const Result = struct { statistics: dist.Edf, d: ?Probability, w2: ?Probability, a2: ?Probability, simulation: ?inference.AccountedSimulationResult = null };

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
        .a2 = if (n >= 5) interpolate(statistics.a2, &.{ 1.248, 1.610, 1.933, 2.492, 3.070, 3.880, 4.500, 6.000 }, &probabilities) else null,
    };
}

pub fn compute(d: *diag.Diagnostics, x: []const f64, distribution: dist.Distribution, request: fitting.Request) diag.Error!Result {
    return computeWithSampler(d, x, distribution, request, null);
}

/// An explicit embedding sampler permits deterministic integration checks and
/// specialized callers; the normal public path always generates/refits here.
pub fn computeWithSampler(d: *diag.Diagnostics, x: []const f64, distribution: dist.Distribution, request: fitting.Request, sampler: ?inference.AccountedSimulator) diag.Error!Result {
    if (x.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF tests require observations", .{});
    if (distribution.family != request.family) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF distribution and parameter request disagree", .{});
    // Fit on every original observation. M9 removes all fitted exponential
    // threshold equalities only from EDF, including supplied-threshold cases.
    var boundary_count: usize = 0;
    if (request.family == .exponential) while (boundary_count < x.len and x[boundary_count] == distribution.p.theta) : (boundary_count += 1) {};
    if (boundary_count == x.len) return .{ .statistics = .{ .d = std.math.nan(f64), .w2 = std.math.nan(f64), .a2 = std.math.nan(f64) }, .d = null, .w2 = null, .a2 = null };
    const raw = dist.edf(distribution, x[boundary_count..]).?;
    const stats: inference.Statistics = .{ .d = raw.d, .w2 = raw.w2, .a2 = raw.a2 };
    const r: inference.Request = .{
        .family = std.meta.stringToEnum(inference.Family, @tagName(request.family)).?,
        .estimated = .{ .theta = request.theta == null, .sigma = request.sigma == null, .mu = request.mu == null, .zeta = request.zeta == null, .alpha = request.alpha == null, .beta = request.beta == null, .c = request.c == null, .lambda = request.lambda == null },
        .alpha = distribution.p.alpha,
        .beta = distribution.p.beta,
        .sigma = distribution.p.sigma,
        .c = distribution.p.c,
        .exponential_boundary_count = if (request.family == .exponential) boundary_count else null,
    };
    switch (request.family) {
        .gumbel, .igauss, .pareto, .rayleigh => {
            const sample = try d.arena.alloc(f64, x.len);
            defer d.arena.free(sample);
            var bootstrap: Bootstrap = .{ .sample = sample, .distribution = distribution, .request = request };
            const result = try inference.simulateAccounted(d, r, stats, x.len, .{ .seed = try fitting.resolveSeed(d, request.edfseed), .samples = request.edfnsamples }, sampler orelse .{ .context = &bootstrap, .draw = Bootstrap.drawAccounted });
            const probabilities = result.probabilities orelse inference.Result{};
            return .{ .statistics = raw, .d = probabilities.d, .w2 = probabilities.w2, .a2 = probabilities.a2, .simulation = result };
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
    const Attempt = union(enum) {
        statistics: inference.Statistics,
        numerical_fit_failure: struct { reason: []const u8, retained_candidate: bool },
    };
    fn drawAccounted(context: ?*anyopaque, random: std.Random, n: usize, d: *diag.Diagnostics) diag.Error!inference.SimulationAttempt {
        const self: *Bootstrap = @ptrCast(@alignCast(context.?));
        return switch (try self.attempt(random, n, d)) {
            .statistics => |statistics| .{ .valid = statistics },
            .numerical_fit_failure => |failure| .{ .numerical_fit_failure = .{ .reason = failure.reason, .retained_candidate = failure.retained_candidate } },
        };
    }
    fn draw(context: ?*anyopaque, random: std.Random, n: usize, d: *diag.Diagnostics) diag.Error!inference.Statistics {
        const self: *Bootstrap = @ptrCast(@alignCast(context.?));
        const result = self.attempt(random, n, d) catch |err| {
            if (err == error.OutOfMemory) return err;
            try d.report(.err, 0, "UNIVARIATE: EDF refit failed; no replication was discarded", .{});
            return err;
        };
        return switch (result) {
            .statistics => |statistics| statistics,
            .numerical_fit_failure => |failure| d.fail(error.ParseError, 0, "UNIVARIATE: EDF numerical refit failure ({s}); no replication was discarded", .{failure.reason}),
        };
    }

    /// Separate expected numerical fit failures from malformed requests and
    /// unsupported algorithms. Only the explicit accounting API consumes the
    /// failure outcome; the compatibility draw callback remains strict.
    fn attempt(self: *Bootstrap, random: std.Random, n: usize, d: *diag.Diagnostics) diag.Error!Attempt {
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
        var trial_diagnostics = diag.Diagnostics.init(d.arena);
        const fitted = fitting.fit(&trial_diagnostics, self.sample, request) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (!report.converged and report.reason != null) return .{ .numerical_fit_failure = .{ .reason = report.reason.?, .retained_candidate = false } };
            try d.list.appendSlice(d.arena, trial_diagnostics.list.items);
            return err;
        };
        if (!report.converged) return .{ .numerical_fit_failure = .{ .reason = report.reason orelse "nonconverged", .retained_candidate = true } };
        try d.list.appendSlice(d.arena, trial_diagnostics.list.items);
        const raw = dist.edf(fitted, self.sample).?;
        return .{ .statistics = .{ .d = raw.d, .w2 = raw.w2, .a2 = raw.a2 } };
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
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "invalid iteration controls") != null);
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

test "UNIVARIATE conditional Pareto callback preserves counts and matches independent SAS references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var x: [40]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const u = std.math.pow(f64, (@as(f64, @floatFromInt(i)) + 0.5) / 40, 1.5);
        v.* = (std.math.pow(f64, 1 - u, -0.3) - 1) / 0.3;
    }
    var d = diag.Diagnostics.init(a);
    const request: fitting.Request = .{ .family = .pareto, .theta = 0, .sigma = 1 };
    const fitted = try fitting.fit(&d, &x, request);
    const observed = dist.edf(fitted, &x).?;
    const references = [_]struct { seed: u64, valid: usize, exceedances: [3]usize }{
        .{ .seed = 17, .valid = 976, .exceedances = .{ 201, 38, 21 } },
        .{ .seed = 13579, .valid = 985, .exceedances = .{ 214, 39, 24 } },
        .{ .seed = 24680, .valid = 972, .exceedances = .{ 227, 47, 23 } },
    };
    for (references) |reference| {
        var sample: [40]f64 = undefined;
        var sampler: Bootstrap = .{ .sample = &sample, .distribution = fitted, .request = request };
        var rng = std.Random.DefaultPrng.init(reference.seed);
        var valid: usize = 0;
        var failures: usize = 0;
        var counts: [3]usize = @splat(0);
        for (0..997) |replication| {
            switch (try sampler.attempt(rng.random(), sample.len, &d)) {
                .statistics => |statistics| {
                    valid += 1;
                    if (statistics.d >= observed.d) counts[0] += 1;
                    if (statistics.w2 >= observed.w2) counts[1] += 1;
                    if (statistics.a2 >= observed.a2) counts[2] += 1;
                },
                .numerical_fit_failure => failures += 1,
            }
            try std.testing.expectEqual(replication + 1, valid + failures);
        }
        try std.testing.expect(valid > 0);
        const denominator: f64 = @floatFromInt(valid);
        const reference_denominator: f64 = @floatFromInt(reference.valid);
        for (counts, reference.exceedances) |count, expected_count| {
            try std.testing.expect(count <= valid);
            const probability = @as(f64, @floatFromInt(count)) / denominator;
            const expected = @as(f64, @floatFromInt(expected_count)) / reference_denominator;
            const pooled = @max((probability + expected) / 2, 1 / @min(denominator, reference_denominator));
            const tolerance = 5 * @sqrt(pooled * (1 - pooled) * (1 / denominator + 1 / reference_denominator)) + 1 / @min(denominator, reference_denominator);
            try std.testing.expectApproxEqAbs(expected, probability, tolerance);
        }
        try std.testing.expect(!d.hasErrors());
    }
}

test "UNIVARIATE MC typed numerical failures do not swallow malformed requests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Zero = struct {
        fn fill(_: *@This(), bytes: []u8) void {
            @memset(bytes, 0);
        }
    };
    var state: Zero = .{};
    const random = std.Random.init(&state, Zero.fill);
    var sample: [40]f64 = undefined;
    var sampler: Bootstrap = .{ .sample = &sample, .distribution = .{ .family = .pareto, .p = .{ .sigma = 1, .alpha = -0.3 } }, .request = .{ .family = .pareto, .sigma = 1 } };
    var d = diag.Diagnostics.init(a);
    // A degenerate generated sample has no estimate; it is a typed numerical
    // outcome, not malformed SAS input and not a substituted statistic.
    const result = try sampler.attempt(random, sample.len, &d);
    try std.testing.expect(result == .numerical_fit_failure);
    try std.testing.expectEqualStrings("invalid_sample", result.numerical_fit_failure.reason);
    try std.testing.expect(!result.numerical_fit_failure.retained_candidate);
    try std.testing.expectEqual(@as(usize, 0), d.count());
    // Until the additive accounting API lands, the existing simulation path
    // remains explicitly strict; refactoring must not silently exclude draws.
    try std.testing.expectError(error.ParseError, Bootstrap.draw(&sampler, random, sample.len, &d));
    try std.testing.expect(d.hasErrors());
    var malformed = diag.Diagnostics.init(a);
    sampler.request.maxiter = 0;
    try std.testing.expectError(error.ParseError, sampler.attempt(random, sample.len, &malformed));
    try std.testing.expect(malformed.hasErrors());
    var unsupported = diag.Diagnostics.init(a);
    sampler.request.maxiter = 20;
    sampler.request.theta = null;
    try std.testing.expectError(error.ParseError, sampler.attempt(random, sample.len, &unsupported));
    try std.testing.expect(unsupported.hasErrors());
}

test "UNIVARIATE exponential EDF filters every boundary tie after full-sample fitting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const requests = [_]fitting.Request{
        .{ .family = .exponential, .theta = 1, .sigma = 4 },
        .{ .family = .exponential, .theta = 1 },
        .{ .family = .exponential, .theta = null, .sigma = 4 },
        .{ .family = .exponential, .theta = null },
    };
    const statistics = [_][3]f64{
        .{ 0.29706503780716, 0.19846494206599, 0.12850819832608 },
        .{ 0.20612584565148, 0.27298140699918, 0.35541564637523 },
        .{ 0.29706503780716, 0.19846494206599, 0.12850819832608 },
        .{ 0.11841005329693, 0.07027225654644, 0.07101417870101 },
    };
    const probabilities = [_][3]f64{
        .{ 0.14609523741611, 0.25, 0.25 },
        .{ 0.0610498063026, 0.02109092820893, 0.00463333633783 },
        .{ 0.13903989532036, 0.25, 0.25 },
        .{ 0.16259807862917, 0.25, 0.25 },
    };
    for (requests, statistics, probabilities) |request, expected_stat, expected_p| {
        for (1..4) |ties| {
            var x: [10]f64 = undefined;
            for (&x, 0..) |*v, i| v.* = if (i < ties) 1 else @floatFromInt(i - ties + 2);
            const fitted = try fitting.fit(&d, &x, request);
            if (request.theta != null and request.sigma == null) {
                var sum: f64 = 0;
                for (x) |v| sum += v - 1;
                try std.testing.expectApproxEqAbs(sum / 10, fitted.p.sigma, 1e-14);
            }
            const result = try compute(&d, &x, fitted, request);
            try std.testing.expect(std.math.isFinite(result.statistics.a2));
            try std.testing.expectApproxEqAbs(expected_stat[ties - 1], result.statistics.w2, 1e-12);
            try std.testing.expectApproxEqAbs(expected_p[ties - 1], result.w2.?.value, 1e-10);
        }
    }
    const known_request: fitting.Request = .{ .family = .exponential, .theta = 0, .sigma = 1 };
    const single = try compute(&d, &.{ 0, @log(@as(f64, 2)) }, .{ .family = .exponential, .p = .{} }, known_request);
    try std.testing.expect(single.d != null and single.w2 != null and single.a2 == null);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 12.0), single.statistics.w2, 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02798611111111), single.w2.?.value, 1e-12);
    const empty = try compute(&d, &.{ 0, 0, 0 }, .{ .family = .exponential, .p = .{} }, known_request);
    try std.testing.expect(empty.d == null and empty.w2 == null and empty.a2 == null);
    try std.testing.expect(std.math.isNan(empty.statistics.d));
    try std.testing.expect(!d.hasErrors());
}

test "UNIVARIATE EDF adapter preserves unrounded shape availability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var fitted: dist.Distribution = .{ .family = .beta, .p = .{ .alpha = 4.9999996, .beta = 2 } };
    var x: [40]f64 = undefined;
    for (&x, 0..) |*v, i| v.* = fitted.quantile((@as(f64, @floatFromInt(i)) + 0.5) / 40);
    const request: fitting.Request = .{ .family = .beta, .sigma = 1 };
    const below = try compute(&d, &x, fitted, request);
    try std.testing.expect(below.d != null and below.w2 != null and below.a2 != null);
    fitted.p.alpha = 5;
    const boundary = try compute(&d, &x, fitted, request);
    try std.testing.expect(boundary.d == null and boundary.w2 == null and boundary.a2 == null);
}

test "UNIVARIATE accounted adapter reports controlled exclusions and zero valid results" {
    const Controlled = struct {
        calls: usize = 0,
        all_fail: bool = false,
        fatal: bool = false,
        fn draw(raw: ?*anyopaque, _: std.Random, _: usize, d: *diag.Diagnostics) diag.Error!inference.SimulationAttempt {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            if (self.fatal and self.calls == 2) return d.fail(error.ExecError, 0, "controlled fatal error", .{});
            if (self.all_fail or self.calls == 2 or self.calls == 4) return .{ .numerical_fit_failure = .{ .reason = "controlled numerical failure", .retained_candidate = false } };
            return .{ .valid = if (self.calls == 3) .{ .d = 0.125, .w2 = 1.0 / 48.0, .a2 = 0.14 } else .{ .d = 0.9, .w2 = 0.973333333333, .a2 = 5.63 } };
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sampler: Controlled = .{};
    const request: fitting.Request = .{ .family = .rayleigh, .sigma = 1, .edfseed = 17, .edfnsamples = 5 };
    const result = try computeWithSampler(&d, &.{ 0.5, 1, 2, 3 }, .{ .family = .rayleigh, .p = .{} }, request, .{ .context = &sampler, .draw = Controlled.draw });
    try std.testing.expectEqual(@as(usize, 5), sampler.calls);
    try std.testing.expectEqual(@as(usize, 5), result.simulation.?.attempted);
    try std.testing.expectEqual(@as(usize, 3), result.simulation.?.valid);
    try std.testing.expectEqual(@as(usize, 2), result.simulation.?.failed);
    try std.testing.expectEqual(inference.SimulationStatus.conditional, result.simulation.?.status);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), result.d.?.value, 1e-15);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.0 / 27.0)), result.simulation.?.standard_errors.?[0], 1e-15);
    try std.testing.expect(!d.hasErrors());
    sampler = .{ .all_fail = true };
    var none_diag = diag.Diagnostics.init(arena.allocator());
    const none = try computeWithSampler(&none_diag, &.{ 0.5, 1, 2, 3 }, .{ .family = .rayleigh, .p = .{} }, request, .{ .context = &sampler, .draw = Controlled.draw });
    try std.testing.expectEqual(@as(usize, 5), sampler.calls);
    try std.testing.expect(none.d == null and none.w2 == null and none.a2 == null);
    try std.testing.expect(none.simulation.?.standard_errors == null and none_diag.hasErrors());
    sampler = .{ .all_fail = true, .fatal = true };
    var fatal_diag = diag.Diagnostics.init(arena.allocator());
    try std.testing.expectError(error.ExecError, computeWithSampler(&fatal_diag, &.{ 0.5, 1, 2, 3 }, .{ .family = .rayleigh, .p = .{} }, request, .{ .context = &sampler, .draw = Controlled.draw }));
    try std.testing.expectEqual(@as(usize, 2), sampler.calls);
}
