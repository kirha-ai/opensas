//! Independent contracts for COMMON028. No temporary oracle is read at runtime.
//! Analytic quadratics, Rosenbrock, and a quartic exercise actual objective,
//! gradient, Hessian, constrained steps, ridging, counters, and stopping state.
const std = @import("std");
const t = std.testing;
const o = @import("nloptions.zig");
const k = @import("nlopt_newton.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
fn options(a: std.mem.Allocator, d: *diag.Diagnostics, procedure: []const u8, source: []const u8) diag.Error!o.Options {
    const tokens = try lex.tokenize(a, source, d);
    return o.parse(d, procedure, 2, tokens[0 .. tokens.len - 1], 1);
}
fn tight() o.Options {
    return .{ .technique = .nrridg, .max_iterations = 500, .max_evaluations = 10000, .absgconv = .{ .threshold = 1e-10 }, .fconv = .{ .threshold = 0 }, .gconv = .{ .threshold = 0 } };
}
const Calls = struct { functions: usize = 0, gradients: usize = 0, hessians: usize = 0, outside: usize = 0 };
fn account(context: ?*anyopaque, gradient: ?[]f64, hessian: ?[]f64) void {
    if (context) |pointer| {
        const c: *Calls = @ptrCast(@alignCast(pointer));
        c.functions += 1;
        if (gradient != null) c.gradients += 1;
        if (hessian != null) c.hessians += 1;
    }
}
// f=7+(x-2)^2+(x-2)(y+3)+2(y+3)^2. H=[[2,1],[1,4]],
// unique optimum (2,-3), f=7, positive eigenvalues 3±sqrt(2).
fn quadratic(context: ?*anyopaque, x: []const f64, gradient: ?[]f64, hessian: ?[]f64) f64 {
    account(context, gradient, hessian);
    const u = x[0] - 2;
    const v = x[1] + 3;
    if (gradient) |g| {
        g[0] = 2 * u + v;
        g[1] = u + 4 * v;
    }
    if (hessian) |h| @memcpy(h, &[_]f64{ 2, 1, 1, 4 });
    return 7 + u * u + u * v + 2 * v * v;
}
fn rosenbrock(context: ?*anyopaque, x: []const f64, gradient: ?[]f64, hessian: ?[]f64) f64 {
    account(context, gradient, hessian);
    const u = 1 - x[0];
    const v = x[1] - x[0] * x[0];
    if (gradient) |g| {
        g[0] = -2 * u - 400 * x[0] * v;
        g[1] = 200 * v;
    }
    if (hessian) |h| @memcpy(h, &[_]f64{ 2 - 400 * x[1] + 1200 * x[0] * x[0], -400 * x[0], -400 * x[0], 200 });
    return u * u + 100 * v * v;
}
// f=(x²-3/2)²+1/4. Minima ±sqrt(3/2), f=1/4; H(0.2)<0.
fn quartic(context: ?*anyopaque, x: []const f64, gradient: ?[]f64, hessian: ?[]f64) f64 {
    account(context, gradient, hessian);
    if (gradient) |g| g[0] = 4 * x[0] * x[0] * x[0] - 6 * x[0];
    if (hessian) |h| h[0] = 12 * x[0] * x[0] - 6;
    const u = x[0] * x[0] - 1.5;
    return u * u + 0.25;
}
fn bounded(context: ?*anyopaque, x: []const f64, gradient: ?[]f64, hessian: ?[]f64) f64 {
    account(context, gradient, hessian);
    if (context) |pointer| {
        const c: *Calls = @ptrCast(@alignCast(pointer));
        if (x[0] < 0 or x[0] > 1 or x[1] < -1 or x[1] > 2) c.outside += 1;
    }
    if (gradient) |g| {
        g[0] = 2 * (x[0] - 3);
        g[1] = 4 * (x[1] + 2);
    }
    if (hessian) |h| @memcpy(h, &[_]f64{ 2, 0, 0, 4 });
    return (x[0] - 3) * (x[0] - 3) + 2 * (x[1] + 2) * (x[1] + 2);
}
fn historyIsActual(result: k.Result, objective: k.Objective) !void {
    try t.expectEqual(result.iterations + 1, result.history.len);
    for (result.history, 0..) |entry, index| {
        try t.expectEqual(entry.value, objective.evaluate(null, entry.parameters, null, null));
        if (index > 0) try t.expect(entry.value <= result.history[index - 1].value);
    }
}

test "COMMON028 documented applicability and technique-dependent common defaults" {
    for ([_][]const u8{ "calis", "GLIMMIX", "hpmixed", "PHREG", "surveyphreg", "VARIOGRAM" }) |p| try t.expect(o.applicable(p));
    for ([_][]const u8{ "LOGISTIC", "MIXED", "GLM", "GENMOD", "SPP", "unknown" }) |p| try t.expect(!o.applicable(p));
    try t.expect(!o.techniqueApplicable("GLIMMIX", .levmar));
    try t.expect(!o.techniqueApplicable("HPMIXED", .levmar));
    try t.expect(!o.techniqueApplicable("CALIS", .nmsimp));
    try t.expectEqual(o.Technique.levmar, o.defaults("CALIS", 39).technique);
    try t.expectEqual(o.Technique.quanew, o.defaults("CALIS", 40).technique);
    try t.expectEqual(o.Technique.nrridg, o.defaults("SURVEYPHREG", 2).technique);
    for ([_]o.Technique{ .trureg, .nrridg, .newrap, .levmar, .quanew, .dbldog, .congra, .nmsimp }, [_]usize{ 50, 50, 50, 50, 200, 200, 400, 1000 }, [_]usize{ 125, 125, 125, 125, 500, 500, 1000, 3000 }) |technique, iterations, evaluations| {
        const opt = o.Options{ .technique = technique };
        try t.expectEqual(iterations, opt.maxIterations());
        try t.expectEqual(evaluations, opt.maxEvaluations());
        try t.expectEqual(@as(f64, if (technique == .nmsimp) 1e-8 else 0), opt.absoluteX().threshold);
        try t.expectEqual(@as(f64, if (technique == .nmsimp) 1e-6 else 0), opt.secondFunction().threshold);
    }
    const defaults = o.Options{};
    try t.expectEqual(@as(f64, 1e-5), defaults.absgconv.threshold);
    try t.expectEqual(@as(f64, 1e-8), defaults.gconv.threshold);
    try t.expectEqual(@as(f64, 0), defaults.fsize);
    try t.expectEqual(-@sqrt(std.math.floatMax(f64)), defaults.absconv);
}
test "COMMON028 option aliases consecutive criteria and missing MAXITER" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const parsed = try options(a, &d, "GLIMMIX", "OM=NRRIDG MAXIT=. MAXFU=20 MINIT=2 ABSTOL=-10 ABSFTOL=1e-6 3 ABSGTOL=1e-7 ABSXTOL=0 FTOL=1e-8 FTOL2=0 GTOL=1e-9 GTOL2=0 XTOL=1e-5 2 FSIZE=1 XSIZE=2 SING=1e-9 LCE=0");
    try t.expectEqual(o.Technique.nrridg, parsed.technique);
    try t.expectEqual(@as(usize, 50), parsed.maxIterations());
    try t.expectEqual(@as(usize, 20), parsed.maxEvaluations());
    try t.expectEqual(@as(usize, 2), parsed.min_iterations);
    try t.expectEqual(@as(f64, -10), parsed.absconv);
    try t.expectEqual(@as(usize, 3), parsed.absfconv.consecutive);
    try t.expectEqual(@as(usize, 2), parsed.relativeX().consecutive);
    try t.expectEqual(@as(f64, 1), parsed.fsize);
    try t.expectEqual(@as(f64, 2), parsed.xsize);
    try t.expectEqual(@as(f64, 1e-9), parsed.singular);
    try t.expectEqual(@as(f64, 0), parsed.lcepsilon);
    try t.expectEqual(@as(usize, 0), d.list.items.len);
    const original_options = try options(a, &d, "GLIMMIX", "tech=quanew maxiter=50");
    try t.expectEqual(o.Technique.quanew, original_options.technique);
    // Parsing the original options is not an assertion that its GLIMMIX fit exists.
    try t.expect(!o.implemented(original_options.technique));
}
test "COMMON028 invalid input versus recognized unsupported controls captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer diag.resetGap();
    for ([_][]const u8{ "tech=garbage", "maxiter=-1", "maxiter=1.5", "absgconv=-1", "absgconv=1 0", "fsize=-1", "sing=2", "madeup=1", "maxfunc=1e99", "xconv=1e999", "tech=LM" }) |source| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try t.expectError(error.ParseError, options(a, &d, "GLIMMIX", source));
        try t.expect(d.hasErrors());
        try t.expect(!diag.gapHit());
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    for ([_][]const u8{ "update=BFGS", "linesearch=8", "maxtime=1", "hescal=1", "inhessian", "noprint" }) |source| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try t.expectError(error.ExecError, options(a, &d, "GLIMMIX", source));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, d.list.items[0].message, "not implemented") != null);
    }
    diag.resetGap();
    var d = diag.Diagnostics.init(a);
    try t.expectError(error.ParseError, options(a, &d, "MIXED", "tech=nrridg"));
    try t.expect(!diag.gapHit());
    try t.expectError(error.ExecError, o.requireImplemented(.{}, &d, 1));
    try t.expect(diag.gapHit());
}
test "COMMON028 NRRIDG analytic quadratic uses actual Hessian and a pure Newton step" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var calls = Calls{};
    const objective = k.Objective{ .context = &calls, .evaluate = quadratic };
    const result = try k.minimize(a, objective, &.{ 100, -200 }, .{}, tight());
    try t.expectEqual(k.Status.converged, result.status);
    try t.expectEqual(@as(usize, 1), result.iterations);
    try t.expectEqual(@as(usize, 0), result.ridge_trials);
    try t.expectApproxEqAbs(@as(f64, 2), result.parameters[0], 1e-12);
    try t.expectApproxEqAbs(@as(f64, -3), result.parameters[1], 1e-12);
    try t.expectApproxEqAbs(@as(f64, 7), result.value.?, 1e-12);
    for (result.gradient.?) |v| try t.expectApproxEqAbs(@as(f64, 0), v, 1e-12);
    try t.expectEqualSlices(f64, &.{ 2, 1, 1, 4 }, result.hessian.?);
    try t.expectEqual(@as(usize, 3), result.evaluations);
    try t.expectEqual(result.evaluations, calls.functions);
    try t.expectEqual(@as(usize, 2), calls.gradients);
    try t.expectEqual(calls.gradients, calls.hessians);
    try historyIsActual(result, objective);
}
test "COMMON028 NRRIDG difficult Rosenbrock starts and indefinite Hessian ridging" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][2]f64{ .{ -1.2, 1 }, .{ 0, 1 }, .{ 3, -4 } }) |initial| {
        const result = try k.minimize(a, .{ .evaluate = rosenbrock, .least_squares = true }, &initial, .{}, tight());
        try t.expectEqual(k.Status.converged, result.status);
        // Unique zero of both squared residuals: x=1 and y=x². 1e-6
        // parameter tolerance is stricter than sqrt(default ABSGCONV).
        for (result.parameters) |v| try t.expectApproxEqAbs(@as(f64, 1), v, 1e-6);
        try t.expect(result.value.? < 1e-16);
        try t.expect(result.ridge_trials > 0);
        try historyIsActual(result, .{ .evaluate = rosenbrock });
    }
    const result = try k.minimize(a, .{ .evaluate = quartic }, &.{0.2}, .{}, tight());
    try t.expectEqual(k.Status.converged, result.status);
    try t.expect(result.ridge_trials > 0);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 1.5)), result.parameters[0], 1e-7);
    try t.expectApproxEqAbs(@as(f64, 0.25), result.value.?, 1e-14);
    try t.expect(result.hessian.?[0] > 0);
    try historyIsActual(result, .{ .evaluate = quartic });
}
test "COMMON028 bounded NRRIDG KKT solution fixed coordinates and infeasible starts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var calls = Calls{};
    const objective = k.Objective{ .context = &calls, .evaluate = bounded };
    const result = try k.minimize(a, objective, &.{ 0.2, 0.5 }, .{ .lower = &.{ 0, -1 }, .upper = &.{ 1, 2 } }, tight());
    try t.expectEqual(k.Status.converged, result.status);
    try t.expectEqualSlices(f64, &.{ 1, -1 }, result.parameters);
    try t.expectEqual(@as(f64, 6), result.value.?);
    try t.expectEqualSlices(f64, &.{ -4, 4 }, result.gradient.?); // raw derivatives retained
    try t.expectEqual(@as(f64, 0), result.history[result.history.len - 1].gradient_max); // projected KKT derivative
    try t.expectEqual(@as(usize, 0), calls.outside);
    const fixed = try k.minimize(a, .{ .evaluate = quadratic }, &.{ 0, 20 }, .{ .lower = &.{ 0, -100 }, .upper = &.{ 0, 100 } }, tight());
    // At x=0, df/dy=-2+4(y+3)=0 => y=-5/2.
    try t.expectEqual(k.Status.converged, fixed.status);
    try t.expectApproxEqAbs(@as(f64, -2.5), fixed.parameters[1], 1e-12);
    try t.expectEqual(@as(f64, 0), fixed.parameters[0]);
    calls = .{};
    const infeasible = try k.minimize(a, objective, &.{ 0, 0 }, .{ .lower = &.{ 2, -1 }, .upper = &.{ 1, 2 } }, tight());
    try t.expectEqual(k.Status.infeasible, infeasible.status);
    try t.expectEqual(@as(usize, 0), calls.functions);
    try t.expect(infeasible.value == null);
    const outside = try k.minimize(a, objective, &.{ -1, 0 }, .{ .lower = &.{ 0, -1 }, .upper = &.{ 1, 2 } }, tight());
    try t.expectEqual(k.Status.infeasible, outside.status);
    try t.expectEqual(@as(usize, 0), calls.functions);
}
test "COMMON028 NONE evaluates supplied parameters without false optimization success" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var calls = Calls{};
    const result = try k.minimize(a, .{ .context = &calls, .evaluate = quadratic }, &.{ 0, 0 }, .{}, .{ .technique = .none });
    try t.expectEqual(k.Status.evaluation_only, result.status);
    try t.expectEqualSlices(f64, &.{ 0, 0 }, result.parameters);
    try t.expectEqual(@as(f64, 23), result.value.?);
    try t.expectEqualSlices(f64, &.{ -1, 10 }, result.gradient.?);
    try t.expectEqual(@as(usize, 1), calls.functions);
    try t.expectEqual(@as(usize, 0), result.iterations);
    try t.expect(result.criterion == null);
}
test "COMMON028 iteration and function limits retain the actual last completed iterate" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var limited = tight();
    limited.max_iterations = 1;
    const result = try k.minimize(a, .{ .evaluate = rosenbrock }, &.{ -1.2, 1 }, .{}, limited);
    try t.expectEqual(k.Status.iteration_limit, result.status);
    try t.expectEqual(@as(usize, 1), result.iterations);
    try t.expect(result.criterion == null);
    try t.expect(result.value.? < 24.2);
    try historyIsActual(result, .{ .evaluate = rosenbrock });
    limited.max_iterations = 0;
    const zero = try k.minimize(a, .{ .evaluate = rosenbrock }, &.{ -1.2, 1 }, .{}, limited);
    try t.expectEqual(k.Status.iteration_limit, zero.status);
    try t.expectEqualSlices(f64, &.{ -1.2, 1 }, zero.parameters);
    try t.expectEqual(@as(usize, 1), zero.evaluations);
    limited.max_iterations = 500;
    limited.max_evaluations = 2;
    const evaluations = try k.minimize(a, .{ .evaluate = rosenbrock }, &.{ -1.2, 1 }, .{}, limited);
    try t.expectEqual(k.Status.evaluation_limit, evaluations.status);
    try t.expectEqual(@as(usize, 1), evaluations.iterations);
    try t.expect(evaluations.evaluations > 2); // full iteration, documented overshoot
    try t.expectEqualSlices(f64, result.parameters, evaluations.parameters);
    try t.expectEqual(result.value, evaluations.value);
    limited = tight();
    limited.min_iterations = 3;
    const minimum = try k.minimize(a, .{ .evaluate = quadratic }, &.{ 2, -3 }, .{}, limited);
    try t.expectEqual(k.Status.converged, minimum.status);
    try t.expectEqual(@as(usize, 3), minimum.iterations);
}
test "COMMON028 numerical failures preserve valid state and reject malformed derivatives" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bad = struct {
        fn initial(_: ?*anyopaque, _: []const f64, _: ?[]f64, _: ?[]f64) f64 {
            return std.math.nan(f64);
        }
        fn next(_: ?*anyopaque, x: []const f64, g: ?[]f64, h: ?[]f64) f64 {
            if (x[0] != 0) return std.math.nan(f64);
            if (g) |v| v[0] = -1;
            if (h) |v| v[0] = 1;
            return 1;
        }
        fn asymmetric(_: ?*anyopaque, _: []const f64, g: ?[]f64, h: ?[]f64) f64 {
            if (g) |v| @memset(v, 1);
            if (h) |v| @memcpy(v, &[_]f64{ 2, 1, 0, 2 });
            return 1;
        }
    };
    const initial = try k.minimize(a, .{ .evaluate = bad.initial }, &.{0}, .{}, tight());
    try t.expectEqual(k.Status.numerical_failure, initial.status);
    try t.expect(initial.value == null and initial.gradient == null and initial.hessian == null);
    const failed = try k.minimize(a, .{ .evaluate = bad.next }, &.{0}, .{}, tight());
    try t.expectEqual(k.Status.numerical_failure, failed.status);
    try t.expectEqual(@as(f64, 1), failed.value.?);
    try t.expectEqualSlices(f64, &.{0}, failed.parameters);
    try t.expectEqualSlices(f64, &.{-1}, failed.gradient.?);
    try t.expectEqual(@as(usize, 0), failed.iterations);
    try t.expect(failed.evaluations > 1);
    const asymmetric = try k.minimize(a, .{ .evaluate = bad.asymmetric }, &.{ 0, 0 }, .{}, tight());
    try t.expectEqual(k.Status.numerical_failure, asymmetric.status);
    try t.expect(asymmetric.value == null);
    try t.expectError(error.ExecError, k.minimize(a, .{ .evaluate = quadratic }, &.{ 0, 0 }, .{}, .{ .technique = .quanew }));
}
test "COMMON028 source stopping equations include FSIZE XSIZE Hessian and consecutive resets" {
    const opt = o.Options{ .technique = .nrridg, .fsize = 10, .xsize = 2 };
    const m = k.metrics(opt, -4, &.{ 0, 5 }, &.{ 3, -4 }, -6, &.{ 1, 3 }, 8, 0.5);
    try t.expectEqual(@as(f64, 4), m.gradient_max);
    try t.expectEqual(@as(?f64, 2), m.absolute_function);
    try t.expectEqual(@as(?f64, 0.2), m.relative_function);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 5)), m.absolute_parameter.?, 1e-15);
    try t.expectEqual(@as(?f64, 0.5), m.relative_parameter);
    try t.expectEqual(@as(?f64, 4), m.predicted_reduction);
    try t.expectEqual(@as(?f64, 0.8), m.relative_gradient);
    try t.expectEqual(@as(?f64, 0.5), m.least_squares_gradient);
    var repeated = tight();
    repeated.absgconv = .{ .threshold = 1, .consecutive = 2 };
    var stopping = k.Stopping{};
    const small = k.Metrics{ .value = 10, .gradient_max = 1 };
    const large = k.Metrics{ .value = 10, .gradient_max = 2 };
    try t.expect(stopping.check(repeated, small, 0) == null);
    try t.expect(stopping.check(repeated, large, 1) == null);
    try t.expect(stopping.check(repeated, small, 2) == null);
    try t.expectEqual(o.Reason.absgconv, stopping.check(repeated, small, 3).?); // <=, not <
    var fonly = tight();
    fonly.absfconv = .{ .threshold = 0.25, .consecutive = 2 };
    fonly.min_iterations = 4;
    var fs = k.Stopping{};
    const fsmall = k.Metrics{ .value = 10, .gradient_max = 100, .absolute_function = 0.2 };
    try t.expect(fs.check(fonly, fsmall, 2) == null);
    try t.expect(fs.check(fonly, fsmall, 3) == null);
    try t.expectEqual(o.Reason.absfconv, fs.check(fonly, fsmall, 4).?);
}

test "COMMON028 every accepted stopping control drives the optimizer on real quartic derivatives" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // At x=2: f=13/2, g=20, H=42. Pure Newton gives x=32/21.
    // No thresholds below are fitted to an observed optimization result.
    const next_x: f64 = 32.0 / 21.0;
    const next_f = std.math.pow(f64, next_x * next_x - 1.5, 2) + 0.25;
    const df = 6.5 - next_f;
    for ([_]o.Reason{ .absconv, .absgconv, .fconv2, .gconv, .gconv2, .absfconv, .absxconv, .fconv, .xconv }) |reason| {
        var settings = tight();
        settings.absgconv.threshold = 0;
        switch (reason) {
            .absconv => settings.absconv = 6.5,
            .absgconv => settings.absgconv.threshold = 20,
            .fconv2 => settings.fconv2 = .{ .threshold = 100.0 / 21.0 + 1e-14 },
            .gconv => settings.gconv.threshold = (400.0 / 42.0) / 6.5 + 1e-14,
            .gconv2 => settings.gconv2.threshold = 20 / @sqrt(@as(f64, 6.5 * 42)) + 1e-14,
            .absfconv => settings.absfconv.threshold = df + 1e-14,
            .absxconv => settings.absxconv = .{ .threshold = 10.0 / 21.0 + 1e-14 },
            .fconv => settings.fconv.threshold = df / 6.5 + 1e-14,
            .xconv => settings.xconv = .{ .threshold = 5.0 / 21.0 + 1e-14 },
        }
        const result = try k.minimize(a, .{ .evaluate = quartic, .least_squares = true }, &.{2}, .{}, settings);
        try t.expectEqual(k.Status.converged, result.status);
        try t.expectEqual(reason, result.criterion.?);
        const at_initial = reason == .absconv or reason == .absgconv or reason == .fconv2 or reason == .gconv or reason == .gconv2;
        try t.expectEqual(@as(usize, if (at_initial) 0 else 1), result.iterations);
        try t.expectApproxEqAbs(if (at_initial) @as(f64, 2) else next_x, result.parameters[0], 1e-14);
        try t.expectApproxEqAbs(if (at_initial) @as(f64, 6.5) else next_f, result.value.?, 1e-14);
    }
    var repeat = tight();
    repeat.absgconv = .{ .threshold = 20, .consecutive = 3 };
    const result = try k.minimize(a, .{ .evaluate = quartic }, &.{2}, .{}, repeat);
    try t.expectEqual(k.Status.converged, result.status);
    try t.expectEqual(o.Reason.absgconv, result.criterion.?);
    try t.expectEqual(@as(usize, 2), result.iterations);
}
