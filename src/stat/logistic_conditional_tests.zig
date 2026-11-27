//! Conditional likelihood identities independent of unconditional fitting.
const std = @import("std");
const t = std.testing;
const c = @import("logistic_conditional.zig");
const driver = @import("logistic_conditional_proc.zig");
const l = @import("logistic.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;

test "LOGISTIC006 matched pairs condition out intercept and retain constant stratum likelihoods" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Three positive discordant, one negative discordant and two concordant
    // pairs. MLE=log(3), Var=1/3+1; concordants each still contribute-log(2).
    const x = [_]f64{ 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1 };
    const y = [_]f64{ 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0 };
    const groups = [_]c.Stratum{ .{ .rows = &.{ 0, 1 }, .events = 1 }, .{ .rows = &.{ 2, 3 }, .events = 1 }, .{ .rows = &.{ 4, 5 }, .events = 1 }, .{ .rows = &.{ 6, 7 }, .events = 1 }, .{ .rows = &.{ 8, 9 }, .events = 1 }, .{ .rows = &.{ 10, 11 }, .events = 1 } };
    const fit = try c.fit(a, &x, &y, 1, &groups, .{ .gconv = 1e-14 });
    try t.expectEqual(c.Status.converged, fit.status);
    try t.expectApproxEqAbs(@log(@as(f64, 3)), fit.coefficients[0], 1e-7);
    try t.expectApproxEqAbs(@as(f64, 4.0 / 3.0), fit.covariance[0], 1e-7);
    try t.expectApproxEqAbs(-6 * @log(@as(f64, 2)), fit.null_log_likelihood, 1e-12);
    try t.expectApproxEqAbs(-2 * @log(@as(f64, 2)) + 3 * @log(@as(f64, 0.75)) + @log(@as(f64, 0.25)), fit.log_likelihood, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), fit.score_test, 1e-12);
    const shifted = try a.dupe(f64, &x);
    for (&groups, 0..) |group, i| for (group.rows) |row| {
        shifted[row] += 1e9 + @as(f64, @floatFromInt(i)) * 100;
    };
    const same = try c.fit(a, shifted, &y, 1, &groups, .{ .gconv = 1e-14 });
    try t.expectEqualSlices(f64, fit.coefficients, same.coefficients);
    try t.expectEqual(fit.log_likelihood, same.log_likelihood);
    const flipped = try a.alloc(f64, y.len);
    for (y, flipped) |value, *target| target.* = 1 - value;
    const inverse = try c.fit(a, &x, flipped, 1, &groups, .{ .gconv = 1e-14 });
    try t.expectApproxEqAbs(-fit.coefficients[0], inverse.coefficients[0], 1e-12);
    try t.expectApproxEqAbs(fit.covariance[0], inverse.covariance[0], 1e-12);
}

test "LOGISTIC006 multicase DP agrees with exhaustive subset moments and Hessian" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 0, 0, 1, 0, 0, 1, 1, 1 };
    const y = [_]f64{ 1, 0, 0, 1 };
    const beta = [_]f64{ 0.4, -0.7 };
    const group = [_]c.Stratum{.{ .rows = &.{ 0, 1, 2, 3 }, .events = 2 }};
    const evaluation = try c.evaluate(a, &x, &y, 2, &group, &beta);
    // Enumerate all six size-two subsets independently of the production DP.
    var normalizer: f64 = 0;
    var first = [_]f64{ 0, 0 };
    var second = [_]f64{ 0, 0, 0, 0 };
    for (0..4) |i| for (i + 1..4) |j| {
        const sum = [_]f64{ x[2 * i] + x[2 * j], x[2 * i + 1] + x[2 * j + 1] };
        const weight = @exp(sum[0] * beta[0] + sum[1] * beta[1]);
        normalizer += weight;
        for (0..2) |r| {
            first[r] += weight * sum[r];
            for (0..2) |s| second[2 * r + s] += weight * sum[r] * sum[s];
        }
    };
    try t.expectApproxEqAbs(beta[0] + beta[1] - @log(normalizer), evaluation.log_likelihood, 1e-13);
    for (0..2) |i| {
        try t.expectApproxEqAbs(1 - first[i] / normalizer, evaluation.gradient[i], 1e-13);
        for (0..2) |j| try t.expectApproxEqAbs(second[2 * i + j] / normalizer - first[i] * first[j] / (normalizer * normalizer), evaluation.information[2 * i + j], 1e-13);
    }
    const fit = try c.fit(a, &x, &y, 2, &group, .{});
    try t.expectEqualSlices(f64, &.{ 0, 0 }, fit.coefficients);
    for (fit.covariance, [_]f64{ 3, 0, 0, 3 }) |actual, expected| try t.expectApproxEqAbs(expected, actual, 1e-12);
    // Ties produce multiplicities 1,4,1 for the selected sum0,1,2.
    const tied = try c.evaluate(a, &.{ 0, 0, 1, 1 }, &.{ 1, 0, 1, 0 }, 1, &group, &.{0});
    try t.expectApproxEqAbs(-@log(@as(f64, 6)), tied.log_likelihood, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 3.0), tied.information[0], 1e-14);
    const extreme = try c.evaluate(a, &.{ 0, 0, 1, 1 }, &.{ 1, 0, 1, 0 }, 1, &group, &.{1000});
    try t.expectApproxEqAbs(@as(f64, -1000), extreme.log_likelihood, 1e-10);
    try t.expectApproxEqAbs(@as(f64, -1), extreme.gradient[0], 1e-12);
}

fn original(a: A) !struct { ds: Dataset, program: []const u8 } {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic006_matched_pairs.sas", a, .limited(1024 * 1024));
    const begin = std.mem.indexOf(u8, source, "datalines;").? + "datalines;".len;
    var values = std.mem.tokenizeAny(u8, source[begin..][0..std.mem.indexOfScalar(u8, source[begin..], ';').?], " \r\n\t");
    var ds = Dataset.init(a, "Data1");
    for ([_][]const u8{ "ID", "Outcome", "Gall", "Hyper" }) |name| _ = try ds.addColumn(name, .num);
    for (1..64) |id| for ([_]f64{ 1, 0 }) |outcome| try ds.appendRow(&.{ .{ .num = @floatFromInt(id) }, .{ .num = outcome }, .{ .num = try std.fmt.parseFloat(f64, values.next().?) }, .{ .num = try std.fmt.parseFloat(f64, values.next().?) } });
    return .{ .ds = ds, .program = source[std.mem.indexOf(u8, source, "proc logistic data=Data1;").?..] };
}
test "LOGISTIC006 complete original asymptotic PROC has conditional counts inference and no association" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("Data1", &fixture.ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    const tokens = try lex.tokenize(a, fixture.program, &d);
    try l.run(cx, &out, tokens);
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic006_matched_pairs.txt", a, .limited(1024 * 1024));
    var words = std.mem.tokenizeAny(u8, expected["# corpus assertions\nwords ".len..], " \r\n\t");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (words.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "<missing>");
    try t.expect(actual.next() == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Association") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Intercept") == null);
    const result = try driver.analyze(cx, try l.parse(cx, tokens));
    try t.expectEqual(@as(usize, 63), result.groups.len);
    try t.expectEqual(@as(usize, 126), result.informative);
    try t.expectEqual(@as(usize, 1), result.design.p);
    // The default stopping iterate is compared with the complete SAS listing
    // above, not forced to equal the mathematical optimum beyond its tolerance.
    // At the independent optimum log(13/5), the exact score is zero and
    // information65/18; all63 strata, including covariate-concordant pairs,
    // contribute to the null likelihood.
    const strata = try a.alloc(c.Stratum, result.groups.len);
    for (result.groups, strata) |group, *stratum| stratum.* = .{ .rows = group.rows, .events = group.events };
    const optimum = try c.evaluate(a, result.design.x, result.design.y, 1, strata, &.{@log(@as(f64, 13.0 / 5.0))});
    try t.expectApproxEqAbs(@as(f64, 0), optimum.gradient[0], 1e-12);
    try t.expectApproxEqAbs(@as(f64, 65.0 / 18.0), optimum.information[0], 1e-12);
    try t.expectApproxEqAbs(-63 * @log(@as(f64, 2)), result.fit.null_log_likelihood, 1e-12);
    try t.expectEqualStrings("", try d.render());
}

test "LOGISTIC006 formatted multi-variable strata missing controls and uninformative sets" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const format = @import("../format.zig");
    const entries = [_]format.UserFmtEntry{ .{ .lo = 11, .hi = 12, .label = "A" }, .{ .lo = 21, .hi = 22, .label = "B" }, .{ .lo = 31, .hi = 32, .label = "C" }, .{ .lo = 41, .hi = 42, .label = "D" }, .{ .lo = 51, .hi = 52, .label = "E" } };
    const formats = [_]format.UserFmt{.{ .name = "matchedset", .is_char = false, .entries = &entries }};
    const old = format.userFormats();
    format.setUserFormats(&formats);
    defer format.setUserFormats(old);
    var ds = Dataset.init(a, "matched");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("region", .char);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("x", .num);
    const ys = [_]f64{ 1, 0, 1, 0, 1, 0, 1, 1, 0, 0 };
    const xs = [_]f64{ 1, 0, 1, 0, 0, 1, 1, 0, 0, 1 };
    for (ys, xs, 0..) |y, x, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(10 * (i / 2 + 1) + i % 2 + 1) }, .{ .str = if (i < 8) "R" else " " }, .{ .num = y }, .{ .num = x } });
    var lib = Library.init(a);
    try lib.put("matched", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic; strata id; strata region / missing info nosummary; format id matchedset.; model y(event='1')=x; run;";
    const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
    const result = try driver.analyze(cx, spec);
    try t.expectEqual(@as(usize, 2), spec.strata.len);
    try t.expectEqual(@as(usize, 5), result.groups.len);
    try t.expectEqual(@as(usize, 10), result.read);
    try t.expectEqual(@as(usize, 10), result.design.n);
    try t.expectEqual(@as(usize, 6), result.informative);
    // For this two-versus-one discordance likelihood, mean-value theorem
    // bounds coefficient error by |score|/min(I) between b and log(2).
    // GCONV bounds score²/I by 1e-8*|LL|; no observed discrepancy sets a tolerance.
    const b = result.fit.coefficients[0];
    const p_case = 1 / (1 + @exp(-b));
    const information = 3 * p_case * (1 - p_case);
    const minimum_information = @min(information, @as(f64, 2.0 / 3.0));
    const bound = @sqrt(1e-8 * @abs(result.fit.log_likelihood) * information) / minimum_information;
    try t.expect(@abs(b - @log(@as(f64, 2))) <= bound + 1e-12);
    try t.expectApproxEqAbs(-3 * @log(@as(f64, 2)), result.fit.null_log_likelihood, 1e-12);
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, source, &d));
    try t.expect(std.mem.indexOf(u8, out.items, "Strata Information") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Strata Summary") == null);
    const selected = try driver.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; strata id region; format id matchedset.; model y(event='1')=x; run;", &d)));
    try t.expectEqual(@as(usize, 8), selected.design.n);
    try t.expectEqual(@as(usize, 4), selected.groups.len);
    try t.expectEqual(@as(usize, 6), selected.informative);
    try t.expectEqualSlices(f64, result.fit.coefficients, selected.fit.coefficients);
    // Per-variable MISSING includes numeric missing IDs independently of the
    // global option; the all-nonevent stratum stays reported but uninfluential.
    for (8..10) |i| {
        const row = try a.dupe(@import("../value.zig").Value, ds.rows.items[i]);
        row[0] = @import("../value.zig").Value.missing;
        row[1] = .{ .str = "R" };
        ds.rows.items[i] = row;
    }
    const missing = try driver.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; strata id(missing) region; format id matchedset.; model y(event='1')=x; run;", &d)));
    try t.expectEqual(@as(usize, 5), missing.groups.len);
    try t.expectEqual(@as(usize, 10), missing.design.n);
}

test "LOGISTIC006 conditional invalid and unsupported paths fail without unconditional output" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("Data1", &fixture.ds);
    diag.resetGap();
    defer diag.resetGap();
    const cases = [_]struct { source: []const u8, rc: u8 }{
        .{ .source = "proc logistic; strata ID; weight Hyper; model Outcome(event='1')=Gall; run;", .rc = 1 },
        .{ .source = "proc logistic; strata ID; model Outcome(event='1')=Gall / link=logit; run;", .rc = 1 },
        .{ .source = "proc logistic; strata ID; model Outcome(event='1')=Gall / nofit; run;", .rc = 1 },
        .{ .source = "proc logistic; strata ID; model Outcome(event='1')=Gall / ctable pprob=.5; run;", .rc = 1 },
        .{ .source = "proc logistic; strata ID; model Outcome(event='1')=Gall / clodds=pl; run;", .rc = 1 },
        .{ .source = "proc logistic; strata ID / check=all; model Outcome(event='1')=Gall; run;", .rc = 2 },
        .{ .source = "proc logistic exactonly; strata ID; model Outcome(event='1')=Gall; exact Gall; run;", .rc = 2 },
        .{ .source = "proc logistic; strata ID; model Outcome(event='1')=ID; run;", .rc = 2 },
    };
    for (cases) |case| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try t.expectError(error.ParseError, l.run(cx, &out, try lex.tokenize(a, case.source, &d)));
        try t.expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors() or d.warning_status));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    const group = [_]c.Stratum{.{ .rows = &.{ 0, 1 }, .events = 1 }};
    try t.expectError(error.ExecError, c.fit(a, &.{ 1, 1 }, &.{ 1, 0 }, 1, &group, .{}));
    try t.expectError(error.ExecError, c.evaluate(a, &.{ 0, 1 }, &.{ 1, 0 }, 1, &.{.{ .rows = &.{ 0, 1 }, .events = 0 }}, &.{0}));
    const diverging = try c.fit(a, &.{ 1, 0 }, &.{ 1, 0 }, 1, &group, .{ .max_iterations = 3 });
    try t.expectEqual(c.Status.iteration_limit, diverging.status);
    try t.expect(std.math.isFinite(diverging.coefficients[0]));
}
