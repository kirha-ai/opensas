//! Executable SAS/STAT15.4 convergence contracts and independent MLE references.
const std = @import("std");
const t = std.testing;
const k = @import("logistic_fit.zig");
const c = @import("logistic_convergence.zig");
const l = @import("logistic.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
fn data(a: A) !Dataset {
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 0, 1, 2 }, .{ 0, 0, 8 }, .{ 1, 1, 7 }, .{ 1, 0, 3 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    return ds;
}
test "LOGISTIC005 convergence equations strict thresholds and OR semantics" {
    const metrics = c.metrics(-4, &.{ 0.006, 2.5 }, 2, -5, &.{ 0.005, 2 });
    try t.expectApproxEqAbs(@as(f64, 2.0 / 4.000001), metrics.gradient, 1e-15);
    try t.expectEqual(@as(?f64, 1), metrics.absolute_function);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 5.000001), metrics.relative_function.?, 1e-15);
    try t.expectEqual(@as(?f64, 0.25), metrics.parameter);
    try t.expect(c.satisfied(k.Options{ .gconv = 0, .xconv = 0.25 }, metrics) == null);
    try t.expectEqual(c.Reason.xconv, c.satisfied(k.Options{ .gconv = 0, .xconv = 0.25001 }, metrics).?.reason);
    try t.expectEqual(c.Reason.fconv, c.satisfied(k.Options{ .gconv = 1e-30, .fconv = 0.21 }, metrics).?.reason);
    try t.expectEqual(c.Reason.absfconv, c.satisfied(k.Options{ .gconv = 0, .absfconv = 1.01 }, metrics).?.reason);
    const initial = c.metrics(-4, &.{ 0.006, 2.5 }, 0, null, null);
    try t.expect(c.satisfied(k.Options{ .gconv = 0, .fconv = 1 }, initial) == null);
    try t.expectEqual(@as(usize, 25), (k.Options{}).max_iterations);
    const boundary = c.metrics(-1, &.{0.012}, 0, -2, &.{0.01});
    try t.expectApproxEqAbs(@as(f64, 0.2), boundary.parameter.?, 1e-15); // exactly0.01 uses relative, not absolute change
}
test "LOGISTIC005 supplied starts ridge modes and accepted objectives preserve analytic MLE" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 0, 1, 0, 1, 1, 1, 1 };
    const y = [_]f64{ 1, 0, 1, 0 };
    const f = [_]f64{ 2, 8, 7, 3 };
    for ([_]k.Ridging{ .relative, .absolute, .none }) |ridging| {
        const fit = try k.fitWeighted(a, &x, &y, 4, 2, &f, null, .{ .gconv = 1e-18, .initial = &.{ -5, 10 }, .ridging = ridging, .capture_history = true });
        try t.expect(fit.converged);
        // Independent saturated-binomial MLEs, covariance and null score.
        try t.expectApproxEqAbs(-@log(@as(f64, 4)), fit.coefficients[0], 1e-8);
        try t.expectApproxEqAbs(@log(@as(f64, 28.0 / 3.0)), fit.coefficients[1], 1e-8);
        for ([_]f64{ 0.625, -0.625, -0.625, 0.625 + 1.0 / 7.0 + 1.0 / 3.0 }, fit.covariance) |expected, actual| try t.expectApproxEqAbs(expected, actual, 1e-8);
        try t.expectApproxEqAbs(@as(f64, 500.0 / 99.0), fit.score_test, 1e-12);
        try t.expectApproxEqAbs(9 * @log(@as(f64, 0.45)) + 11 * @log(@as(f64, 0.55)), fit.null_log_likelihood, 1e-12);
        try t.expectApproxEqAbs(-25 - 20 * std.math.log1p(@exp(@as(f64, -5))), fit.history[0].log_likelihood, 1e-12);
        try t.expectEqual(fit.iterations + 1, fit.history.len);
        for (fit.history[1..], fit.history[0 .. fit.history.len - 1]) |current, previous| try t.expect(current.log_likelihood >= previous.log_likelihood);
        if (ridging == .none) {
            try t.expect(fit.halving_steps > 0);
            try t.expectEqual(@as(usize, 0), fit.ridge_steps);
        } else {
            try t.expect(fit.ridge_steps > 0);
            try t.expectEqual(@as(usize, 0), fit.halving_steps);
        }
    }
    try t.expectError(error.ExecError, k.fitWeighted(a, &x, &y, 4, 2, &f, null, .{ .initial = &.{0} }));
    try t.expectError(error.ExecError, k.fitWeighted(a, &x, &y, 4, 2, &f, null, .{ .initial = &.{ 0, std.math.nan(f64) } }));
}
test "LOGISTIC005 MAXITER retains actual last iterate and warns without false convergence" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try data(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic; freq f; model y(event='1')=x / maxiter=1; run;";
    const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
    const result = try l.analyze(cx, spec);
    const fit = result.fit;
    try t.expect(!fit.converged);
    try t.expectEqual(c.Reason.iteration_limit, fit.stop.reason);
    try t.expectEqual(@as(usize, 1), fit.iterations);
    // First Newton/Fisher increment at null p=9/20 is(-100/99,200/99).
    const intercept = @log(@as(f64, 9.0 / 11.0)) - 100.0 / 99.0;
    try t.expectApproxEqAbs(intercept, fit.coefficients[0], 1e-12);
    try t.expectApproxEqAbs(@as(f64, 200.0 / 99.0), fit.coefficients[1], 1e-12);
    const p0 = 1 / (1 + @exp(-intercept));
    const p1 = 1 / (1 + @exp(-intercept - 200.0 / 99.0));
    const v0 = 1 / (10 * p0 * (1 - p0));
    const v1 = 1 / (10 * p1 * (1 - p1));
    for ([_]f64{ v0, -v0, -v0, v0 + v1 }, fit.covariance) |expected, actual| try t.expectApproxEqAbs(expected, actual, 1e-12);
    try t.expectEqual(@as(usize, 1), d.list.items.len);
    try t.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    var output_diagnostics = diag.Diagnostics.init(a);
    const output_context: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &output_diagnostics };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try l.run(output_context, &out, try lex.tokenize(a, source, &output_diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "Convergence not attained after 1 iterations.") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "satisfied") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Analysis of Maximum Likelihood Estimates") != null);
    try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), output_diagnostics.hasErrors()));
}
test "LOGISTIC005 explicit criteria replace default and technique aliases use true fits" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try data(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "absfconv=0.001", "fconv=0.001", "xconv=0.001" }, [_]c.Reason{ .absfconv, .fconv, .xconv }) |option, reason| {
        const source = try std.fmt.allocPrint(a, "proc logistic; freq f; model y(event='1')=x / {s}; run;", .{option});
        const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
        try t.expectEqual(@as(f64, 0), spec.fit_options.gconv);
        const result = try l.analyze(cx, spec);
        try t.expect(result.fit.converged);
        try t.expectEqual(reason, result.fit.stop.reason);
        try t.expect(result.fit.stop.metric < result.fit.stop.threshold);
    }
    const source = "proc logistic; freq f; model y(event='1')=x / fconv=1 gconv=1e-30 tech=nr ridging=none; run;";
    const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
    const result = try l.analyze(cx, spec);
    try t.expectEqual(c.Reason.fconv, result.fit.stop.reason);
    try t.expectEqual(@as(usize, 1), result.fit.iterations);
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, source, &d));
    try t.expect(std.mem.indexOf(u8, out.items, "Optimization Technique Newton-Raphson") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Convergence criterion (FCONV=1) satisfied.") != null);
    const fisher = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; model y(event='1')=x / tech=fs gconv=1e-14; run;", &d)));
    const newton = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; model y(event='1')=x / technique=newton gconv=1e-14; run;", &d)));
    try t.expectEqualSlices(f64, fisher.fit.coefficients, newton.fit.coefficients);
    try t.expectEqualSlices(f64, fisher.fit.covariance, newton.fit.covariance);
    const score_only = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; model y(event='1')=x / nofit; run;", &d)));
    try t.expect(!score_only.fit.converged);
    try t.expectEqual(c.Reason.not_fit, score_only.fit.stop.reason);
    try t.expectEqual(@as(usize, 0), score_only.fit.coefficients.len);
}
