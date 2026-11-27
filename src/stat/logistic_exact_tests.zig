//! Exact finite-mass and full-original regressions for STAT-LOGISTIC-011.
const std = @import("std");
const t = std.testing;
const e = @import("logistic_exact.zig");
const c = @import("logistic_conditional.zig");
const driver = @import("logistic_conditional_proc.zig");
const l = @import("logistic.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;

test "LOGISTIC011 exact direct and network masses retain tied-state mid-p definition" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const group = [_]c.Stratum{.{ .rows = &.{ 0, 1, 2, 3 }, .events = 2 }};
    for ([_]e.Method{ .network, .direct }) |method| {
        const distribution = try e.build(a, &.{ 0, 0, 1, 1 }, &.{ 1, 1, 0, 0 }, &group, method);
        try t.expectEqual(@as(u128, 6), distribution.total);
        try t.expectEqual(@as(usize, 3), distribution.points.len);
        for (distribution.points, [_]i64{ 0, 1, 2 }, [_]u128{ 1, 4, 1 }) |point, value, count| {
            try t.expectEqual(value, point.value);
            try t.expectEqual(count, point.count);
        }
        const result = try e.tests(distribution, 0.5, 1);
        try t.expectApproxEqAbs(@as(f64, 3), result.score, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.probability_exact, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.score_exact, 1e-14);
        // Lancaster subtracts half the observed point's mass ONLY. The other
        // equally extreme point retains full mass, per physical p.5952.
        try t.expectApproxEqAbs(@as(f64, 0.25), result.probability_mid, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 0.25), result.score_mid, 1e-14);
        const changed = try e.tests(distribution, 0.5, 0);
        try t.expectApproxEqAbs(@as(f64, 1.0 / 12.0), changed.score_mid, 1e-14);
        const moments = try e.moments(distribution, @log(@as(f64, 2)));
        try t.expectApproxEqAbs(@as(f64, 16.0 / 13.0), moments.mean, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 56.0 / 169.0), moments.variance, 1e-14);
    }
}
fn binomial(a: A, n: usize, successes: usize) !e.Distribution {
    const x = try a.alloc(f64, 2 * n);
    const y = try a.alloc(f64, 2 * n);
    const strata = try a.alloc(c.Stratum, n);
    for (0..n) |i| {
        x[2 * i] = 1;
        x[2 * i + 1] = 0;
        y[2 * i] = if (i < successes) 1 else 0;
        y[2 * i + 1] = 1 - y[2 * i];
        const rows = try a.dupe(usize, &.{ 2 * i, 2 * i + 1 });
        strata[i] = .{ .rows = rows, .events = 1 };
    }
    return e.build(a, x, y, strata, .network);
}
test "LOGISTIC011 estimates and exact mid-p limits invert finite tails independently" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const distribution = try binomial(a, 18, 13);
    const result = try e.infer(distribution, 0.05, false, 0.5, false);
    try t.expectApproxEqAbs(@log(@as(f64, 13.0 / 5.0)), result.estimate, 1e-10);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 18.0 / 65.0)), result.standard_error, 1e-10);
    try t.expectApproxEqAbs(@as(f64, 25232.0 / 262144.0), result.p_value, 1e-14);
    for ([_]bool{ false, true }) |midp| {
        const interval = try e.infer(distribution, 0.05, midp, 0.5, false);
        for ([_]f64{ interval.lower, interval.upper }, [_]bool{ true, false }) |endpoint, right| {
            // Independent binomial probability recurrence, not the production
            // log-sum-exp evaluator or a beta-quantile implementation.
            const p = 1 / (1 + @exp(-endpoint));
            var probability = std.math.pow(f64, 1 - p, 18);
            var tail: f64 = 0;
            var observed: f64 = 0;
            for (0..19) |k| {
                if ((right and k >= 13) or (!right and k <= 13)) tail += probability;
                if (k == 13) observed = probability;
                if (k < 18) probability *= @as(f64, @floatFromInt(18 - k)) / @as(f64, @floatFromInt(k + 1)) * p / (1 - p);
            }
            if (midp) tail -= 0.5 * observed;
            try t.expectApproxEqAbs(@as(f64, 0.025), tail, 2e-11); // root target1e-12 plus finite-sum rounding
        }
    }
    const test_result = try e.tests(distribution, 0.5, 1);
    try t.expectApproxEqAbs(@as(f64, 3.5555555555555556), test_result.score, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 8568.0 / 262144.0), test_result.observed_probability, 1e-14);
    try t.expectApproxEqAbs(@as(f64, (25232.0 - 4284.0) / 262144.0), test_result.score_mid, 1e-14);
}
test "LOGISTIC011 separated boundaries use median unbiased estimate without asymptotic substitution" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]usize{ 0, 3 }) |successes| {
        const distribution = try binomial(a, 3, successes);
        const result = try e.infer(distribution, 0.05, false, 0.5, false);
        const p = std.math.pow(f64, 0.5, 1.0 / 3.0);
        const expected = @log(p / (1 - p));
        try t.expect(result.median_unbiased);
        try t.expect(std.math.isNan(result.standard_error));
        try t.expectApproxEqAbs(if (successes == 3) expected else -expected, result.estimate, 1e-10);
        try t.expectEqual(@as(f64, 0.125), result.p_value); // one-sided p-value for MUE
        const bound_probability = std.math.pow(f64, 0.05, 1.0 / 3.0);
        const bound = @log(bound_probability / (1 - bound_probability));
        if (successes == 3) {
            try t.expectApproxEqAbs(bound, result.lower, 1e-10);
            try t.expect(std.math.isPositiveInf(result.upper));
        } else {
            try t.expectApproxEqAbs(-bound, result.upper, 1e-10);
            try t.expect(std.math.isNegativeInf(result.lower));
        }
    }
    const degenerate: e.Distribution = .{ .points = &.{.{ .value = 0, .count = 2 }}, .observed = 0, .total = 2 };
    try t.expectEqual(@as(f64, 1), (try e.tests(degenerate, 0.5, 1)).score_exact);
    try t.expectError(error.ExecError, e.infer(degenerate, 0.05, false, 0.5, false));
}

fn original(a: A) !struct { ds: Dataset, source: []const u8 } {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic011_matched_exact.sas", a, .limited(1024 * 1024));
    const begin = std.mem.indexOf(u8, source, "datalines;").? + "datalines;".len;
    var values = std.mem.tokenizeAny(u8, source[begin..][0..std.mem.indexOfScalar(u8, source[begin..], ';').?], " \r\n\t");
    var ds = Dataset.init(a, "Data1");
    for ([_][]const u8{ "ID", "Outcome", "Gall", "Hyper" }) |name| _ = try ds.addColumn(name, .num);
    for (1..64) |id| for ([_]f64{ 1, 0 }) |outcome| try ds.appendRow(&.{ .{ .num = @floatFromInt(id) }, .{ .num = outcome }, .{ .num = try std.fmt.parseFloat(f64, values.next().?) }, .{ .num = try std.fmt.parseFloat(f64, values.next().?) } });
    return .{ .ds = ds, .source = source };
}
test "LOGISTIC011 both original PROCs and exact absolute masses persist without oracle" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("Data1", &fixture.ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = fixture.source[std.mem.indexOf(u8, fixture.source, "proc logistic data=Data1;").?..];
    var segments = std.mem.splitSequence(u8, source, "run;");
    var out: std.ArrayList(u8) = .empty;
    while (segments.next()) |segment| {
        if (std.mem.trim(u8, segment, " \r\n\t").len == 0) continue;
        const program = try std.fmt.allocPrint(a, "{s}run;", .{segment});
        try l.run(cx, &out, try lex.tokenize(a, program, &diagnostics));
    }
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic011_matched_exact.txt", a, .limited(1024 * 1024));
    var words = std.mem.tokenizeAny(u8, expected["# corpus assertions\nwords ".len..], " \r\n\t");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (words.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "<missing>");
    try t.expect(actual.next() == null);
    try t.expectEqualStrings("", try diagnostics.render());
    const spec = try l.parse(cx, try lex.tokenize(a, "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; exact Gall / estimate=both; run;", &diagnostics));
    const prepared = try driver.prepare(cx, spec);
    const strata = try a.alloc(c.Stratum, prepared.groups.len);
    for (prepared.groups, strata) |group, *stratum| stratum.* = .{ .rows = group.rows, .events = group.events };
    const network = try e.build(a, prepared.design.x, prepared.design.y, strata, .network);
    const direct = try e.build(a, prepared.design.x, prepared.design.y, strata, .direct);
    try t.expectEqual(@as(u128, 1) << 63, network.total);
    try t.expectEqual(@as(usize, 19), network.points.len);
    var choose: u128 = 1;
    for (network.points, direct.points, 0..) |point, other, k| {
        if (k > 0) choose = choose * (19 - k) / k;
        try t.expectEqual(choose * (@as(u128, 1) << 45), point.count);
        try t.expectEqual(point.value, other.value);
        try t.expectEqual(point.count, other.count);
    }
    try t.expectEqual(network.points[0].value + 13, network.observed);
}

test "LOGISTIC011 EXACTONLY separated input reaches finite MUE and direct method controls" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "separated");
    for ([_][]const u8{ "id", "y", "x" }) |name| _ = try ds.addColumn(name, .num);
    for (1..4) |id| {
        try ds.appendRow(&.{ .{ .num = @floatFromInt(id) }, .{ .num = 1 }, .{ .num = 1 } });
        try ds.appendRow(&.{ .{ .num = @floatFromInt(id) }, .{ .num = 0 }, .{ .num = 0 } });
    }
    var lib = Library.init(a);
    try lib.put("separated", &ds);
    for ([_][]const u8{ "network", "direct" }) |method| {
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        const source = try std.fmt.allocPrint(a, "proc logistic data=separated exactonly; strata id; model y(event='1')=x; exactoptions method={s} epsilon=.25; exact x / estimate=both; run;", .{method});
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        defer diag.resetGap();
        try l.run(cx, &out, try lex.tokenize(a, source, &diagnostics));
        try t.expectEqualStrings("", try diagnostics.render());
        try t.expect(!diagnostics.warning_status);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expect(std.mem.indexOf(u8, out.items, "median unbiased estimate and a one-sided p-value") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Infinity") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "0.1250") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Optimization Technique") == null);
        try t.expect(std.mem.indexOf(u8, out.items, "Model Fit Statistics") == null);
        try t.expect(std.mem.indexOf(u8, out.items, "Association") == null);
    }
}

test "LOGISTIC011 parser mid-p alpha and one-sided estimates use requested exact tails" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("Data1", &fixture.ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; exactoptions method=direct; exact Gall / estimate=parm cltype=midp midpfactor=(.5 .5) alpha=.1 onesided; run;";
    const spec = try l.parse(cx, try lex.tokenize(a, source, &diagnostics));
    try t.expectEqual(e.Method.direct, spec.exact_method);
    try t.expectEqual(@as(f64, 0.5), spec.exact_request.?.delta2);
    try t.expectEqual(@as(f64, 0.1), spec.exact_request.?.alpha.?);
    const distribution = try binomial(a, 18, 13);
    const result = try e.infer(distribution, 0.1, true, 0.5, true);
    try t.expect(std.math.isPositiveInf(result.upper));
    try t.expectApproxEqAbs(@as(f64, 12616.0 / 262144.0), result.p_value, 1e-14);
    const endpoint = try e.moments(distribution, result.lower);
    try t.expectApproxEqAbs(@as(f64, 0.1), endpoint.right - 0.5 * endpoint.observed_mass, 2e-12);
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "90% Confidence") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Exact Odds Ratios") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Infinity") != null);
}

test "LOGISTIC011 exact applicability count overflow and RNG requests stay explicit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectError(error.ExecError, binomial(a, 128, 64)); // total2^128 cannot fit a u128; no floating count fallback
    try t.expectError(error.ExecError, e.build(a, &.{ 0, 0.5 }, &.{ 0, 1 }, &.{.{ .rows = &.{ 0, 1 }, .events = 1 }}, .network));
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("Data1", &fixture.ds);
    const cases = [_]struct { source: []const u8, rc: u8 }{
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall Hyper; exact Gall / estimate; run;", .rc = 2 },
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; exactoptions method=networkmc; exact Gall; run;", .rc = 2 },
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; exactoptions method=mcmc; exact Gall; run;", .rc = 2 },
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; exact Gall / alpha=0; run;", .rc = 1 },
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; model Outcome(event='1')=Gall; run;", .rc = 1 },
        .{ .source = "proc logistic data=Data1 exactonly; strata ID; exact Gall; model Outcome(event='1')=Gall; run;", .rc = 1 },
    };
    diag.resetGap();
    defer diag.resetGap();
    for (cases) |case| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try t.expectError(error.ParseError, l.run(cx, &out, try lex.tokenize(a, case.source, &d)));
        try t.expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors() or d.warning_status));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "LOGISTIC011 weak finite information and tiny alpha do not trigger false root convergence" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const central: u128 = 1_000_000_000_000_000_000_000_000;
    const flat: e.Distribution = .{ .points = &.{ .{ .value = 0, .count = 1 }, .{ .value = 1, .count = central }, .{ .value = 2, .count = 4 } }, .observed = 1, .total = central + 5 };
    // Mean=t is equivalent to exp(-b)=4exp(b), even though the raw score
    // is only O(1e-24). A fixed absolute score tolerance would return false0.
    const estimate = try e.infer(flat, 0.05, false, 0.5, false);
    try t.expectApproxEqAbs(-@log(@as(f64, 2)), estimate.estimate, 1e-10);
    try t.expect((try e.tests(flat, 0.5, 1)).score > 0);
    const boundary = try binomial(a, 3, 3);
    const small = try e.infer(boundary, 1e-8, false, 0.5, false);
    const p = std.math.pow(f64, 1e-8, 1.0 / 3.0);
    try t.expectApproxEqAbs(@log(p / (1 - p)), small.lower, 1e-9);
    const tail = try e.moments(boundary, small.lower);
    try t.expectApproxEqRel(@as(f64, 1e-8), tail.observed_mass, 2e-11);
}
