//! Computational restrictions and actual termination, S154 physical pp.6734-6738.
//! Nonconvergence severity also has independent in-repo reference COMMON033:
//! LOGISTIC iteration_limit.expected.rc=1 with convergence warnings. MIXED raw
//! SYSCC and its complete nonconverged table layout remain needs-oracle.
const std = @import("std");
const t = std.testing;
const math = @import("mixed_fit.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const H = struct {
    cx: proc.ProcCtx,
    model: math.Model,
    fn init(a: std.mem.Allocator) !H {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/persist_mixed_heights.sas", "heights", &.{ "Family", "Gender", "Height" }, &.{1}, 0);
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = .init(a);
        try lib.put("heights", ds);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        const cx = proc.ProcCtx{ .arena = a, .lib = lib, .diags = d };
        const tokens = try lex.tokenize(a, "proc mixed data=heights;class Family Gender;model Height=Gender;random Family Family*Gender;run;", d);
        const s = try @import("mixed_parse.zig").parse(cx, tokens);
        const m = try @import("mixed_model.zig").parse(cx, ds, s.statements, s.options.order, 0.05);
        const groups = try @import("mixed_input.zig").prepare(cx, s, m.required_columns);
        const x = try @import("mixed_design.zig").build(cx, m, groups[0].selected);
        const rs = try @import("mixed_random.zig").parse(cx, ds, m.matrix, s.statements);
        const z = try @import("mixed_random.zig").build(cx, rs, groups[0].selected);
        const components = try a.alloc(math.Component, z.components.len);
        for (components, z.components) |*target, source| target.* = .{ .name = source.name, .kernel = source.kernel, .columns = source.columns };
        return .{ .cx = cx, .model = .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components } };
    }
};
fn balanced(a: std.mem.Allocator, response: []const f64) !math.Model {
    const k = try a.alloc(f64, 36);
    for (0..6) |i| for (0..6) |j| {
        k[i * 6 + j] = if (i / 2 == j / 2) 1 else 0;
    };
    const c = try a.alloc(math.Component, 1);
    c[0] = .{ .name = "group", .kernel = k, .columns = 3 };
    return .{ .x = &.{ 1, 1, 1, 1, 1, 1 }, .y = response, .n = 6, .p = 1, .components = c };
}
test "MIXED018 actual iteration and evaluation limits preserve last finite state" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const good = try math.fit(a, h.model, .{});
    try t.expect(good.converged);
    try t.expect(math.statusInfo(good.status).attained());
    try t.expect(!math.statusInfo(good.status).nonclean());
    try t.expectEqual(@as(?u8, 0), math.statusInfo(good.status).sas_status);
    var count: usize = 0;
    for (good.iterations) |row| count += row.evaluations;
    try t.expectEqual(count, good.evaluation_count);
    try t.expectEqual(@as(usize, 0), good.rejected_evaluations);
    const zero = try math.fit(a, h.model, .{ .maxiter = 0 });
    try t.expectEqual(math.Status.max_iterations, zero.status);
    try t.expect(!zero.converged);
    try t.expect(!math.statusInfo(zero.status).attained());
    try t.expect(!math.statusInfo(zero.status).allowsInference(false));
    try t.expectEqual(@as(?u8, 1), math.statusInfo(zero.status).sas_status);
    try t.expectEqual(@as(usize, 0), zero.last_iteration);
    try t.expectEqual(@as(usize, 2), zero.evaluation_count);
    for (zero.variances) |v| try t.expect(std.math.isFinite(v) and v > 0);
    // Initialization and residual-only display baseline are distinct actual states.
    try t.expect(zero.minus2loglik < zero.iterations[0].objective);
    for (2..8) |budget| {
        const limited = try math.fit(a, h.model, .{ .maxfunc = budget });
        try t.expect(!limited.converged);
        try t.expectEqual(math.Status.max_evaluations, limited.status);
        try t.expect(math.statusInfo(limited.status).nonclean());
        try t.expect(!math.statusInfo(limited.status).attained());
        try t.expect(limited.evaluation_count <= budget);
        try t.expect(std.math.isFinite(limited.minus2loglik));
    }
}

test "COMMON033 MIXED evaluation limit and numerical termination retain status with hidden listing" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The second case asks for gradient precision far below machine epsilon;
    // the actual finite-precision line search must stop, not claim convergence.
    for ([_][]const u8{ "maxfunc=2", "convg=1e-30 maxiter=100 maxfunc=1000" }, [_][]const u8{ "Maximum number of likelihood evaluations reached.", "No improving feasible likelihood step was found." }) |options, reason| {
        var h = try H.init(a);
        var capture = @import("../ods.zig").Capture{};
        var listing = @import("../ods_listing.zig").Listing{};
        h.cx.capture = &capture;
        h.cx.listing = &listing;
        try capture.parse(a, h.cx.diags, try lex.tokenize(a, "ods output CovParms=cp ConvergenceStatus=cs Tests3=tt FitStatistics=fs;", h.cx.diags));
        _ = try listing.parse(a, h.cx.diags, try lex.tokenize(a, "ods select none;", h.cx.diags));
        diag.resetGap();
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const source = try std.fmt.allocPrint(a, "proc mixed data=heights {s};class Family Gender;model Height=Gender;random Family Family*Gender;run;", .{options});
        try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, source, h.cx.diags));
        try capture.finish(h.cx.lib, h.cx.diags);
        try t.expectEqual(@as(usize, 0), out.items.len);
        const cs = h.cx.lib.find("cs").?;
        try t.expectEqual(@as(usize, 1), cs.rowCount());
        try t.expectEqual(@as(f64, 1), cs.rows.items[0][cs.indexOf("Status").?].num);
        try t.expectEqualStrings(reason, cs.rows.items[0][cs.indexOf("Reason").?].str);
        const cp = h.cx.lib.find("cp").?;
        try t.expectEqual(@as(usize, 3), cp.rowCount());
        for (cp.rows.items) |row| try t.expect(std.math.isFinite(row[cp.indexOf("Estimate").?].num));
        try t.expect(h.cx.lib.find("tt") == null and h.cx.lib.find("fs") == null);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors() or h.cx.diags.warning_status));
        var failures: usize = 0;
        for (h.cx.diags.list.items) |entry| {
            try t.expect(std.mem.indexOf(u8, entry.message, "Convergence criteria met.") == null);
            if (std.mem.indexOf(u8, entry.message, "Convergence criteria not met:") != null) failures += 1;
        }
        try t.expectEqual(@as(usize, 1), failures);
    }
}

test "COMMON033 MIXED known covariance is an evaluation not a failed or converged optimization" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try H.init(a);
    var capture = @import("../ods.zig").Capture{};
    h.cx.capture = &capture;
    try capture.parse(a, h.cx.diags, try lex.tokenize(a, "ods output CovParms=cp ConvergenceStatus=cs IterHistory=ih Tests3=tt;", h.cx.diags));
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=heights;class Family Gender;model Height=Gender;random Family Family*Gender;parms (1)(1)(1) /noiter;run;", h.cx.diags));
    try capture.finish(h.cx.lib, h.cx.diags);
    try t.expect(h.cx.lib.find("cs") == null and h.cx.lib.find("ih") == null);
    try t.expect(h.cx.lib.find("cp") != null and h.cx.lib.find("tt") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Convergence criteria") == null);
    try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors() or h.cx.diags.warning_status));
    const state = math.statusInfo(.evaluated);
    try t.expect(!state.attained() and !state.nonclean());
    try t.expect(state.sas_status == null and state.allowsInference(false));
}

test "COMMON033 MIXED infeasible covariance and arithmetic gap emit no successful results" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |arithmetic_gap| {
        var h = try H.init(a);
        if (arithmetic_gap) {
            const ds = h.cx.lib.find("heights").?;
            for (ds.rows.items, 0..) |*row, i| {
                const changed = try a.dupe(@import("../value.zig").Value, row.*);
                changed[ds.indexOf("Height").?] = .{ .num = if (i % 2 == 0) 1e200 else -1e200 };
                row.* = changed;
            }
        }
        var capture = @import("../ods.zig").Capture{};
        h.cx.capture = &capture;
        try capture.parse(a, h.cx.diags, try lex.tokenize(a, "ods output CovParms=cp ConvergenceStatus=cs Tests3=tt FitStatistics=fs;", h.cx.diags));
        diag.resetGap();
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const source = if (arithmetic_gap)
            "proc mixed data=heights;model Height=;parms (1) /noiter;run;"
        else
            "proc mixed data=heights;class Family;model Height=;random Family;parms (-100)(1) /noiter nobound;run;";
        try t.expectError(if (arithmetic_gap) error.ParseError else error.ExecError, @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, source, h.cx.diags)));
        try capture.finish(h.cx.lib, h.cx.diags);
        try t.expectEqual(@as(usize, 0), out.items.len);
        for ([_][]const u8{ "cp", "cs", "tt", "fs" }) |name| try t.expect(h.cx.lib.find(name) == null);
        try t.expectEqual(@as(u8, if (arithmetic_gap) 2 else 1), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors() or h.cx.diags.warning_status));
        try t.expectEqual(diag.Severity.err, h.cx.diags.list.items[0].severity);
        // The non-PD supplied covariance is a user/model failure. Finite but
        // enormous responses exceed implemented arithmetic: retain D-009 gap2,
        // not a fabricated SAS status or a claim that the model is invalid.
        try t.expect(std.mem.indexOf(u8, h.cx.diags.list.items[0].message, if (arithmetic_gap) "PARMS point cannot be evaluated" else "no feasible PARMS grid point") != null);
    }
}
test "MIXED018 convergence controls follow independent profile derivatives" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = try balanced(a, &.{ -1, 1, 1, 3, 3, 5 });
    for ([_]math.Convergence{ .hessian, .gradient, .function }) |kind| {
        const fit = try math.fit(a, model, .{ .start = &.{ 1, 1 }, .criterion = kind, .absolute = true, .convergence = 1e-12 });
        try t.expect(fit.converged);
        const r = fit.variances[0] / fit.variances[1];
        const d = 1 + 2 * r;
        // f(D)=5ln((6+16/D)/5)+2ln(D)+constant; D=1+2r.
        const numerator = 12 * d - 48;
        const denominator = d * (6 * d + 16);
        const gradient = 2 * numerator / denominator;
        const hessian = 4 * (12 * denominator - numerator * (12 * d + 16)) / (denominator * denominator);
        const last = fit.iterations[fit.iterations.len - 1];
        if (kind == .gradient) try t.expectApproxEqAbs(@abs(gradient), last.criterion.?, 1e-12);
        if (kind == .hessian) try t.expectApproxEqAbs(gradient * gradient / hessian, last.criterion.?, 1e-12);
        if (kind == .function) {
            for (fit.iterations[1..], fit.iterations[0 .. fit.iterations.len - 1]) |row, previous| try t.expectApproxEqAbs(@abs(row.objective - previous.objective), row.criterion.?, 1e-12);
        }
        try t.expectApproxEqAbs(@as(f64, 3), fit.variances[0], 1e-5);
        try t.expectApproxEqAbs(@as(f64, 2), fit.variances[1], 1e-5);
    }
    const h = try H.init(a);
    for ([_][]const u8{ "convh=1e-7", "convg=1e-7 absolute", "convf=1e-9 absolute" }) |option| {
        const code = try std.fmt.allocPrint(a, "proc mixed data=heights {s};class Family Gender;model Height=Gender;random Family Family*Gender;run;", .{option});
        const s = try @import("mixed_parse.zig").parse(h.cx, try lex.tokenize(a, code, h.cx.diags));
        try t.expect(s.options.convergence_explicit);
        try t.expect(s.options.convergence > 0);
    }
}
test "MIXED018 response-scale identity avoids squared-quadratic overflow" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const response = [_]f64{ -1, 1, 1, 3, 3, 5 };
    const model = try balanced(a, &response);
    const base = try math.fit(a, model, .{ .absolute = true, .convergence = 1e-12 });
    for ([_]f64{ 1e-100, 1e100 }) |scale| {
        var scaled = response;
        for (&scaled) |*v| v.* *= scale;
        var m = model;
        m.y = &scaled;
        const fit = try math.fit(a, m, .{ .absolute = true, .convergence = 1e-12 });
        try t.expect(fit.converged);
        for (base.variances, fit.variances) |expected, actual| try t.expectApproxEqRel(expected * scale * scale, actual, 1e-8);
        try t.expectApproxEqRel(base.coefficients[0] * scale, fit.coefficients[0], 1e-8);
        try t.expectApproxEqAbs(base.minus2loglik + 10 * @log(scale), fit.minus2loglik, 1e-8);
    }
    try t.expectError(error.DegenerateResponse, math.fit(a, try balanced(a, &.{ 2, 2, 2, 2, 2, 2 }), .{}));
}
test "MIXED018 lower-bound release is missing rather than a fabricated criterion" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try math.fit(a, try balanced(a, &.{ -1, 1, 1, 3, 3, 5 }), .{ .ols_start = true, .absolute = true, .convergence = 1e-12 });
    try t.expect(fit.converged);
    try t.expectEqual(@as(usize, 1), fit.iterations[0].iteration);
    try t.expect(fit.iterations[0].criterion == null);
    try t.expect(fit.iterations[0].parameters[0] > 0);
    const boundary = try math.fit(a, try balanced(a, &.{ 1, -1, 1, -1, 1, -1 }), .{ .start = &.{ 1e-14, 1 } });
    try t.expect(boundary.converged);
    try t.expectEqual(@as(f64, 0), boundary.variances[0]);
}
test "MIXED018 nonconvergence retains covariance and status with warning exit1" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try H.init(a);
    var capture = @import("../ods.zig").Capture{};
    var listing = @import("../ods_listing.zig").Listing{};
    h.cx.capture = &capture;
    h.cx.listing = &listing;
    try capture.parse(a, h.cx.diags, try lex.tokenize(a, "ods output CovParms=cp ConvergenceStatus=cs IterHistory=ih Tests3=tt FitStatistics=fs;", h.cx.diags));
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=heights maxiter=0;class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.cx.diags));
    try capture.finish(h.cx.lib, h.cx.diags);
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors() or h.cx.diags.warning_status));
    try t.expect(h.cx.diags.warning_status and !h.cx.diags.hasErrors());
    const cp = h.cx.lib.find("cp").?;
    try t.expectEqual(@as(usize, 3), cp.rowCount());
    for (cp.rows.items) |row| try t.expect(std.math.isFinite(row[cp.indexOf("Estimate").?].num));
    const cs = h.cx.lib.find("cs").?;
    try t.expectEqual(@as(f64, 1), cs.rows.items[0][cs.indexOf("Status").?].num);
    try t.expect(std.mem.indexOf(u8, cs.rows.items[0][cs.indexOf("Reason").?].str, "Maximum number of iterations") != null);
    try t.expect(h.cx.lib.find("ih") != null);
    try t.expect(h.cx.lib.find("tt") == null and h.cx.lib.find("fs") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Convergence criteria not met") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Covariance Parameter Estimates") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Type 3 Tests") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Fit Statistics") == null);
}

test "MIXED018 rejected likelihood trials consume budget on an unbounded residual boundary" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const k = [_]f64{ 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1 };
    const model = math.Model{ .x = &.{ 1, 1, 1, 1 }, .y = &.{ 1, 1, 2, 2 }, .n = 4, .p = 1, .components = &.{.{ .name = "group", .kernel = &k, .columns = 2 }} };
    // Both within-group contrasts are exactly zero; the residual-profile
    // likelihood is unbounded as sigma² approaches zero. No finite optimum is
    // claimed, and failed non-PD/degenerate trial evaluations still cost budget.
    const result = try math.fit(a, model, .{ .start = &.{ 1, 1 }, .maxiter = 100, .maxfunc = 80, .absolute = true, .convergence = 1e-12 });
    try t.expect(!result.converged);
    try t.expectEqual(math.Status.max_evaluations, result.status);
    try t.expectEqual(@as(usize, 80), result.evaluation_count);
    try t.expect(result.rejected_evaluations > 0);
    try t.expect(std.math.isFinite(result.minus2loglik));
    var recorded: usize = 0;
    for (result.iterations) |row| recorded += row.evaluations;
    try t.expect(recorded <= result.evaluation_count);
}

test "MIXED018 unsupported computational techniques stay visible and nonpositive tolerances are explicit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "scoring=5", "ridge=1e-4", "lognote", "nobound", "convh=0", "convh=1e-8 convg=1e-8" }) |option| {
        const h = try H.init(a);
        diag.resetGap();
        defer diag.resetGap();
        const source = try std.fmt.allocPrint(a, "proc mixed data=heights {s};class Family Gender;model Height=Gender;random Family Family*Gender;run;", .{option});
        var out: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, source, h.cx.diags)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors()));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}
