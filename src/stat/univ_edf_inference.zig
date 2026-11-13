//! Standalone UNIVARIATE EDF inference. No dependency on distribution fitting,
//! rendering, or ODS. Table 4.31 (Statistical Procedures pp.447–448) controls
//! availability; an unavailable test is distinct from a missing implementation.
const std = @import("std");
const diag = @import("../diag.zig");
pub const Family = enum { normal, lognormal, exponential, gamma, weibull, beta, power, gumbel, igauss, pareto, rayleigh, sb, su };
pub const Sign = enum { exact, less, greater };
pub const Probability = struct { value: f64, sign: Sign = .exact };
pub const Statistics = struct { d: f64, w2: f64, a2: f64 };
pub const Result = struct { d: ?Probability = null, w2: ?Probability = null, a2: ?Probability = null };
pub const Available = struct { d: bool = false, w2: bool = false, a2: bool = false };
const all: Available = .{ .d = true, .w2 = true, .a2 = true };
const quadratic: Available = .{ .w2 = true, .a2 = true };
/// True means estimated. Names match SAS option names, including lognormal
/// ZETA (scale) and SIGMA (shape), rather than a generic location/scale mapping.
pub const Estimated = struct {
    theta: bool = false,
    sigma: bool = false,
    mu: bool = false,
    zeta: bool = false,
    alpha: bool = false,
    beta: bool = false,
    c: bool = false,
    lambda: bool = false,
};
pub const Request = struct {
    family: Family,
    estimated: Estimated = .{},
    alpha: f64 = 1,
    beta: f64 = 1,
    sigma: f64 = 1,
    c: f64 = 1,
};

/// Availability is not permission to substitute a complete-parameter null law.
/// Shapes here are the fitted shapes when estimated, supplied shapes otherwise.
pub fn availability(r: Request) Available {
    const e = r.estimated;
    return switch (r.family) {
        .normal => if (e.mu != e.sigma) quadratic else all,
        .lognormal => if (e.theta) (if (r.sigma < 3) all else .{}) else if (e.zeta != e.sigma) quadratic else all,
        .exponential, .gumbel, .igauss, .pareto, .rayleigh => all,
        .gamma => if (e.theta or (e.sigma and e.alpha)) (if (r.alpha > 1) all else .{}) else all,
        .weibull => if (e.theta) (if (r.c > 2) all else .{}) else if (e.sigma or e.c) quadratic else all,
        .beta => if (e.theta or e.sigma) .{} else if (!e.alpha and !e.beta) all else if (e.alpha and e.beta and r.alpha < 5 and r.beta < 5) all else .{},
        .power => if (e.theta or e.sigma) .{} else if (!e.alpha or r.alpha < 5) all else .{},
        .sb, .su => .{},
    };
}

/// Linear probability interpolation, retaining the table's endpoint AND sign.
/// This is also useful for shape-specific critical tables supplied by callers.
pub fn interpolate(value: f64, critical: []const f64, probabilities: []const f64) Probability {
    std.debug.assert(critical.len == probabilities.len and critical.len > 1);
    if (value < critical[0]) return .{ .value = probabilities[0], .sign = .greater };
    for (1..critical.len) |i| {
        if (value <= critical[i]) return .{ .value = probabilities[i - 1] + (value - critical[i - 1]) / (critical[i] - critical[i - 1]) * (probabilities[i] - probabilities[i - 1]) };
    }
    return .{ .value = probabilities[probabilities.len - 1], .sign = .less };
}

fn validate(d: *diag.Diagnostics, s: Statistics, n: usize) diag.Error!void {
    if (n < 2 or !std.math.isFinite(s.d) or s.d < 0 or s.d > 1 or
        std.math.isNan(s.w2) or s.w2 < 0 or std.math.isNan(s.a2) or s.a2 < 0)
        return d.fail(error.ParseError, 0, "UNIVARIATE: invalid EDF statistics or sample size", .{});
}

/// Raw statistics are not overwritten by the finite-sample corrections used
/// for inference. Null means SAS does not supply that test, not p=missing due
/// to an unfinished implementation. Missing tables produce a diagnostic.
pub fn tabulated(d: *diag.Diagnostics, r: Request, s: Statistics, n: usize) diag.Error!Result {
    try validate(d, s, n);
    if (!(r.alpha > 0) or !(r.beta > 0) or !(r.sigma > 0) or !(r.c > 0) or
        !std.math.isFinite(r.alpha) or !std.math.isFinite(r.beta) or !std.math.isFinite(r.sigma) or !std.math.isFinite(r.c))
        return d.fail(error.ParseError, 0, "UNIVARIATE: invalid EDF inference shape", .{});
    const available = availability(r);
    if (!available.a2) return .{};
    const e = r.estimated;
    const nf: f64 = @floatFromInt(n);
    const fixed = switch (r.family) {
        .normal => !e.mu and !e.sigma,
        .lognormal => !e.theta and !e.zeta and !e.sigma,
        .exponential => !e.theta and !e.sigma,
        .gamma, .power => !e.theta and !e.sigma and !e.alpha,
        .weibull => !e.theta and !e.sigma and !e.c,
        .beta => !e.theta and !e.sigma and !e.alpha and !e.beta,
        else => false,
    };
    if (fixed) {
        const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.001 };
        return .{
            .d = interpolate(s.d * (@sqrt(nf) + 0.12 + 0.11 / @sqrt(nf)), &.{ 1.019, 1.138, 1.224, 1.358, 1.480, 1.628, 1.731, 1.950 }, &levels),
            .w2 = interpolate((s.w2 - 0.4 / nf + 0.6 / (nf * nf)) * (1 + 1 / nf), &.{ 0.209, 0.284, 0.347, 0.461, 0.581, 0.743, 0.869, 1.167 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.248, 1.610, 1.933, 2.492, 3.070, 3.880, 4.500, 6.000 }, &levels),
        };
    }
    if (r.family == .normal or (r.family == .lognormal and !e.theta)) {
        const location = if (r.family == .normal) e.mu else e.zeta;
        if (location and e.sigma) {
            const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005 };
            return .{
                .d = interpolate(s.d * (@sqrt(nf) - 0.01 + 0.85 / @sqrt(nf)), &.{ 0.775, 0.819, 0.895, 0.955, 1.035 }, &.{ 0.15, 0.10, 0.05, 0.025, 0.01 }),
                .w2 = interpolate(s.w2 * (1 + 0.5 / nf), &.{ 0.074, 0.091, 0.104, 0.126, 0.148, 0.178, 0.201 }, &levels),
                .a2 = interpolate(s.a2 * (1 + 0.75 / nf + 2.25 / (nf * nf)), &.{ 0.470, 0.561, 0.631, 0.752, 0.873, 1.035, 1.159 }, &levels),
            };
        }
        const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.0025 };
        // SAS applies no sample correction in either partial-normal case.
        return if (location) .{
            .w2 = interpolate(s.w2, &.{ 0.094, 0.117, 0.134, 0.165, 0.197, 0.238, 0.270, 0.302 }, &levels),
            .a2 = interpolate(s.a2, &.{ 0.644, 0.782, 0.894, 1.087, 1.285, 1.551, 1.756, 1.964 }, &levels),
        } else .{
            .w2 = interpolate(s.w2, &.{ 0.190, 0.263, 0.327, 0.442, 0.562, 0.725, 0.851, 0.978 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.072, 1.430, 1.743, 2.308, 2.898, 3.702, 4.324, 4.954 }, &levels),
        };
    }
    if (r.family == .weibull and !e.theta) {
        const levels = [_]f64{ 0.25, 0.10, 0.05, 0.025, 0.01 };
        if (e.sigma and e.c) {
            const correction = 1 + 0.2 / @sqrt(nf);
            return .{
                .w2 = interpolate(s.w2 * correction, &.{ 0.073, 0.102, 0.124, 0.146, 0.175 }, &levels),
                .a2 = interpolate(s.a2 * correction, &.{ 0.474, 0.637, 0.757, 0.877, 1.038 }, &levels),
            };
        }
        return if (e.sigma) .{
            .w2 = interpolate(s.w2 * (1 + 0.16 / nf), &.{ 0.116, 0.175, 0.222, 0.271, 0.338 }, &levels),
            .a2 = interpolate(s.a2 * (1 + 0.3 / nf), &.{ 0.736, 1.062, 1.321, 1.591, 1.959 }, &levels),
        } else .{
            .w2 = interpolate(s.w2, &.{ 0.186, 0.320, 0.431, 0.547, 0.705 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.060, 1.725, 2.277, 2.854, 3.640 }, &levels),
        };
    }
    return d.fail(error.ParseError, 0, "UNIVARIATE: EDF inference requires unimplemented parameter-dependent tables or a simulation callback for {s}", .{@tagName(r.family)});
}

pub const SimulationOptions = struct {
    /// Caller resolves omitted/time-of-day seed once, and can retain it in ODS.
    seed: u64,
    samples: usize = 500,
};
pub const SimulationResult = struct {
    probabilities: Result,
    exceedances: [3]usize,
    samples: usize,
    seed: u64,
    /// Binomial standard errors, in D/W2/A2 order. These describe Monte Carlo
    /// uncertainty, not uncertainty about the model or its fitted parameters.
    standard_errors: [3]f64,
};
pub const Simulator = struct {
    context: ?*anyopaque = null,
    /// Generate n observations from the fitted null, refit the estimated
    /// parameters with the same constraints, and return raw EDF statistics.
    /// Preserve fixed parameters. Errors propagate; never discard failed fits.
    draw: *const fn (?*anyopaque, std.Random, usize, *diag.Diagnostics) diag.Error!Statistics,
};

/// Parametric bootstrap for the four simulation families (manual p.446).
/// A fixed seed is reproducible with this implementation; SAS does not promise
/// its random stream, so cross-engine comparisons must allow Monte Carlo error.
pub fn simulate(d: *diag.Diagnostics, r: Request, observed: Statistics, n: usize, options: SimulationOptions, sampler: Simulator) diag.Error!SimulationResult {
    try validate(d, observed, n);
    switch (r.family) {
        .gumbel, .igauss, .pareto, .rayleigh => {},
        else => return d.fail(error.ParseError, 0, "UNIVARIATE: this family requires tabulated EDF probabilities", .{}),
    }
    if (options.samples == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: EDFNSAMPLES must be positive", .{});
    var generator = std.Random.DefaultPrng.init(options.seed);
    var counts = [_]usize{0} ** 3;
    for (0..options.samples) |_| {
        const s = try sampler.draw(sampler.context, generator.random(), n, d);
        try validate(d, s, n);
        if (s.d >= observed.d) counts[0] += 1;
        if (s.w2 >= observed.w2) counts[1] += 1;
        if (s.a2 >= observed.a2) counts[2] += 1;
    }
    const m: f64 = @floatFromInt(options.samples);
    var p: [3]Probability = undefined;
    var se: [3]f64 = undefined;
    for (counts, 0..) |k, i| {
        p[i] = .{ .value = @as(f64, @floatFromInt(k)) / m };
        se[i] = @sqrt(p[i].value * (1 - p[i].value) / m);
    }
    return .{ .probabilities = .{ .d = p[0], .w2 = p[1], .a2 = p[2] }, .exceedances = counts, .standard_errors = se, .samples = options.samples, .seed = options.seed };
}

test "dev5 EDF Table 4.31 estimation masks and strict shape boundaries" {
    try std.testing.expect(!availability(.{ .family = .normal, .estimated = .{ .mu = true } }).d);
    try std.testing.expect(availability(.{ .family = .normal, .estimated = .{ .mu = true } }).a2);
    try std.testing.expect(!availability(.{ .family = .lognormal, .estimated = .{ .theta = true }, .sigma = 3 }).a2);
    try std.testing.expect(availability(.{ .family = .lognormal, .estimated = .{ .theta = true }, .sigma = 2.99 }).d);
    try std.testing.expect(!availability(.{ .family = .gamma, .estimated = .{ .alpha = true, .sigma = true } }).a2);
    try std.testing.expect(availability(.{ .family = .gamma, .estimated = .{ .alpha = true } }).a2);
    try std.testing.expect(!availability(.{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2 }).a2);
    try std.testing.expect(availability(.{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2.01 }).d);
    try std.testing.expect(!availability(.{ .family = .weibull, .estimated = .{ .c = true } }).d);
    try std.testing.expect(!availability(.{ .family = .power, .estimated = .{ .alpha = true }, .alpha = 5 }).a2);
    try std.testing.expect(!availability(.{ .family = .beta, .estimated = .{ .alpha = true } }).a2);
    try std.testing.expect(availability(.{ .family = .beta, .estimated = .{ .alpha = true, .beta = true }, .alpha = 4.99 }).a2);
    try std.testing.expect(!availability(.{ .family = .beta, .estimated = .{ .alpha = true, .beta = true }, .beta = 5 }).a2);
    for ([_]Family{ .sb, .su }) |f| try std.testing.expectEqual(Available{}, availability(.{ .family = f }));
}

test "dev5 EDF interpolation preserves exact knots and endpoint signs" {
    const knots = [_]f64{ 1, 2, 3 };
    const levels = [_]f64{ 0.25, 0.05, 0.01 };
    try std.testing.expectEqual(Sign.exact, interpolate(1, &knots, &levels).sign);
    try std.testing.expectEqual(Sign.exact, interpolate(3, &knots, &levels).sign);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), interpolate(1.5, &knots, &levels).value, 1e-15);
    try std.testing.expectEqual(Probability{ .value = 0.25, .sign = .greater }, interpolate(0, &knots, &levels));
    try std.testing.expectEqual(Probability{ .value = 0.01, .sign = .less }, interpolate(4, &knots, &levels));
}

// A standalone test callback: the complete-parameter probability integral
// transform is uniform for each of the four families. Estimated Rayleigh scale
// is sqrt(mean(x^2)/2), equivalently mean of exponential transformed values.
const TestSampler = struct {
    refit_rayleigh: bool = false,
    fn draw(raw: ?*anyopaque, random: std.Random, n: usize, diagnostics: *diag.Diagnostics) diag.Error!Statistics {
        const self: *TestSampler = @ptrCast(@alignCast(raw.?));
        const u = try diagnostics.arena.alloc(f64, n);
        defer diagnostics.arena.free(u);
        var mean: f64 = 0;
        for (u) |*v| {
            v.* = -@log(1 - random.float(f64));
            mean += v.* / @as(f64, @floatFromInt(n));
        }
        for (u) |*v| v.* = -std.math.expm1(-v.* / (if (self.refit_rayleigh) mean else 1));
        std.mem.sort(f64, u, {}, std.sort.asc(f64));
        const nf: f64 = @floatFromInt(n);
        var s: Statistics = .{ .d = 0, .w2 = 1 / (12 * nf), .a2 = -nf };
        for (u, 0..) |v, i| {
            const fi: f64 = @floatFromInt(i);
            s.d = @max(s.d, @max((fi + 1) / nf - v, v - fi / nf));
            const delta = v - (fi + 0.5) / nf;
            s.w2 += delta * delta;
            s.a2 -= (2 * fi + 1) / nf * (@log(v) + std.math.log1p(-u[n - i - 1]));
        }
        return s;
    }
};

test "dev5 EDF simulations agree with independent SAS M9 within binomial uncertainty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sampler: TestSampler = .{};
    const cases = [_]struct { family: Family, stats: Statistics, p: [3]f64, refit: bool = false }{
        .{ .family = .rayleigh, .stats = .{ .d = 0.16062095035231, .w2 = 0.47827512405361, .a2 = 2.93957796590725 }, .p = .{ 0.2269, 0.0462, 0.0305 } },
        .{ .family = .rayleigh, .stats = .{ .d = 0.10001215220679, .w2 = 0.11990472112324, .a2 = 0.96463236078575 }, .p = .{ 0.6012, 0.2315, 0.1294 }, .refit = true },
        .{ .family = .gumbel, .stats = .{ .d = 0.38732655154844, .w2 = 1.94483849079829, .a2 = 9.05693013472377 }, .p = .{ 0, 0.0001, 0.0001 } },
        .{ .family = .igauss, .stats = .{ .d = 0.16728255176424, .w2 = 0.38546561039003, .a2 = 1.95835761620976 }, .p = .{ 0.188, 0.077, 0.095 } },
        .{ .family = .pareto, .stats = .{ .d = 0.18132138066867, .w2 = 0.40966827227087, .a2 = 2.59352817496381 }, .p = .{ 0.1288, 0.0704, 0.0454 } },
    };
    for (cases) |c| {
        sampler.refit_rayleigh = c.refit;
        const result = try simulate(&d, .{ .family = c.family }, c.stats, 40, .{ .seed = 86531, .samples = 10000 }, .{ .context = &sampler, .draw = TestSampler.draw });
        const ps = [_]f64{ result.probabilities.d.?.value, result.probabilities.w2.?.value, result.probabilities.a2.?.value };
        for (ps, c.p) |actual, reference| {
            // Independent 10,000-replicate experiments: five pooled binomial
            // standard errors plus one count. Continuity floor handles zero.
            const pooled = @max((actual + reference) / 2, 1.0 / 10000.0);
            const tolerance = 5 * @sqrt(2 * pooled * (1 - pooled) / 10000) + 1.0 / 10000.0;
            try std.testing.expectApproxEqAbs(reference, actual, tolerance);
        }
    }
}

test "dev5 EDF seed reproducibility, sample counts, and loud callback failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sampler: TestSampler = .{};
    const callback: Simulator = .{ .context = &sampler, .draw = TestSampler.draw };
    const stats: Statistics = .{ .d = 0.15, .w2 = 0.2, .a2 = 1 };
    const r: Request = .{ .family = .rayleigh };
    const a = try simulate(&d, r, stats, 20, .{ .seed = 42 }, callback);
    const b = try simulate(&d, r, stats, 20, .{ .seed = 42 }, callback);
    try std.testing.expectEqualDeep(a, b);
    try std.testing.expectEqual(@as(usize, 500), a.samples);
    const c = try simulate(&d, r, stats, 20, .{ .seed = 43 }, callback);
    try std.testing.expect(!std.meta.eql(a.exceedances, c.exceedances));
    try std.testing.expectError(error.ParseError, simulate(&d, r, stats, 20, .{ .seed = 42, .samples = 0 }, callback));
    try std.testing.expectError(error.ParseError, simulate(&d, .{ .family = .normal }, stats, 20, .{ .seed = 42 }, callback));
    const Failure = struct {
        fn draw(_: ?*anyopaque, _: std.Random, _: usize, diagnostics: *diag.Diagnostics) diag.Error!Statistics {
            return diagnostics.fail(error.ExecError, 0, "test bootstrap fit did not converge", .{});
        }
    };
    try std.testing.expectError(error.ExecError, simulate(&d, r, stats, 20, .{ .seed = 42 }, .{ .draw = Failure.draw }));
    try std.testing.expect(d.hasErrors());
}

test "dev5 EDF independent heldout SAS partial normal lognormal and Weibull tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var lines = std.mem.splitScalar(u8, @embedFile("testdata/univ_edf_dev5_heldout.txt"), '\n');
    var checked: usize = 0;
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \r").len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next().?;
        const n = try std.fmt.parseInt(usize, std.mem.trim(u8, fields.next().?, " "), 10);
        _ = fields.next().?; // independent perturbation index, retained for replay
        const statistic = std.mem.trim(u8, fields.next().?, " ");
        const value = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
        const expected = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
        const sign = std.mem.trim(u8, fields.next().?, " \r");
        const eq = std.mem.eql;
        const r: Request = if (eq(u8, id, "nmu")) .{ .family = .normal, .estimated = .{ .sigma = true } } else if (eq(u8, id, "nsig")) .{ .family = .normal, .estimated = .{ .mu = true } } else if (eq(u8, id, "lz")) .{ .family = .lognormal, .estimated = .{ .sigma = true } } else if (eq(u8, id, "ls")) .{ .family = .lognormal, .estimated = .{ .zeta = true } } else if (eq(u8, id, "wboth")) .{ .family = .weibull, .estimated = .{ .sigma = true, .c = true } } else if (eq(u8, id, "wc")) .{ .family = .weibull, .estimated = .{ .sigma = true }, .c = 4 } else if (eq(u8, id, "wsig")) .{ .family = .weibull, .estimated = .{ .c = true } } else unreachable;
        const w = eq(u8, statistic, "W-Sq");
        const result = try tabulated(&d, r, .{ .d = 0, .w2 = if (w) value else 0, .a2 = if (w) 0 else value }, n);
        try std.testing.expect(result.d == null);
        const p = if (w) result.w2.? else result.a2.?;
        try std.testing.expectApproxEqAbs(expected, p.value, 1e-10);
        const expected_sign: Sign = if (eq(u8, sign, ">")) .greater else if (eq(u8, sign, "<")) .less else .exact;
        try std.testing.expectEqual(expected_sign, p.sign);
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 1708), checked);
}

test "dev5 EDF unimplemented inference differs from documented unavailability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const s: Statistics = .{ .d = 0.1, .w2 = 0.1, .a2 = 0.5 };
    const unavailable = try tabulated(&d, .{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2 }, s, 30);
    try std.testing.expectEqual(Result{}, unavailable);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectError(error.ParseError, tabulated(&d, .{ .family = .gamma, .estimated = .{ .theta = true }, .alpha = 2 }, s, 30));
    try std.testing.expectError(error.ParseError, tabulated(&d, .{ .family = .exponential, .estimated = .{ .sigma = true } }, s, 30));
    try std.testing.expectError(error.ParseError, tabulated(&d, .{ .family = .normal }, s, 0));
    try std.testing.expect(d.hasErrors());
}
