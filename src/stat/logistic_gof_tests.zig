//! Independent diagnostic and full-original contracts for STAT-LOGISTIC-008.
const std = @import("std");
const t = std.testing;
const l = @import("logistic.zig");
const g = @import("logistic_gof.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
fn original(a: A) !struct { ds: Dataset, program: []const u8 } {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic008_original.sas", a, .limited(1024 * 1024));
    const offset = std.mem.indexOf(u8, source, "datalines;").? + "datalines;".len;
    var values = std.mem.tokenizeAny(u8, source[offset..][0..std.mem.indexOfScalar(u8, source[offset..], ';').?], " \r\n\t");
    var ds = Dataset.init(a, "One");
    for ([_][]const u8{ "A", "B", "Y", "F" }) |name| _ = try ds.addColumn(name, .num);
    for (0..2) |a_| for (0..2) |b| for (1..3) |y| try ds.appendRow(&.{ .{ .num = @floatFromInt(a_) }, .{ .num = @floatFromInt(b) }, .{ .num = @floatFromInt(y) }, .{ .num = try std.fmt.parseFloat(f64, values.next().?) } });
    return .{ .ds = ds, .program = source[std.mem.indexOf(u8, source, "proc logistic data=One;").?..] };
}
test "LOGISTIC008 complete original subpopulation output persists without oracle" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("One", &fixture.ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var parts = std.mem.splitSequence(u8, fixture.program, "run;");
    var out: std.ArrayList(u8) = .empty;
    while (parts.next()) |part| {
        if (std.mem.trim(u8, part, " \r\n\t").len == 0) continue;
        const source = try std.fmt.allocPrint(a, "{s}run;", .{part});
        try l.run(cx, &out, try lex.tokenize(a, source, &d));
    }
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic008_original.txt", a, .limited(1024 * 1024));
    var words = std.mem.tokenizeAny(u8, expected["# corpus assertions\nwords ".len..], " \r\n\t");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (words.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "<missing>");
    try t.expect(actual.next() == null);
    try t.expectEqualStrings("", try d.render());
    const spec = try l.parse(cx, try lex.tokenize(a, "proc logistic; freq F; model Y=A / scale=none aggregate=(A B); run;", &d));
    const analysis = try l.analyze(cx, spec);
    const statistics = analysis.report.?.goodness.?;
    try t.expectEqual(@as(usize, 4), statistics.profiles);
    try t.expectEqual(@as(usize, 2), statistics.df);
    const ranged = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq F; model Y=A / scale=none aggregate=(A--B); run;", &d)));
    try t.expectEqual(statistics.pearson, ranged.report.?.goodness.?.pearson);
    try t.expectEqual(statistics.deviance, ranged.report.?.goodness.?.deviance);
    // Default GCONV stops at an approximation to the binomial MLE. Its
    // complete SAS listing is checked above, including four-decimal GOF values.
    try t.expectApproxEqAbs(@as(f64, 0.3531), statistics.pearson, 0.0000500001);
    try t.expectApproxEqAbs(@as(f64, 0.3541), statistics.deviance, 0.0000500001);
    // Separately verify the exact Pearson identity at analytical probabilities
    //54/187 and137/341 rather than demanding exact MLEs from a stopping rule.
    const groups = [_]g.Group{
        .{ .representative = 0, .events = 23, .trials = 86, .expected = 86.0 * 54.0 / 187.0 },
        .{ .representative = 1, .events = 31, .trials = 101, .expected = 101.0 * 54.0 / 187.0 },
        .{ .representative = 2, .events = 67, .trials = 167, .expected = 167.0 * 137.0 / 341.0 },
        .{ .representative = 3, .events = 70, .trials = 174, .expected = 174.0 * 137.0 / 341.0 },
    };
    try t.expectApproxEqAbs(@as(f64, 35493181624615.0 / 100519690651092.0), (try g.goodness(&groups, 2, false)).pearson, 1e-13);
}

test "LOGISTIC008 zero cells dispersion equations and saturated boundaries" {
    const group = [_]g.Group{.{ .representative = 0, .trials = 4, .events = 0, .expected = 2 }};
    const statistics = try g.goodness(&group, 0, false);
    try t.expectEqual(@as(f64, 4), statistics.pearson);
    try t.expectApproxEqAbs(8 * @log(@as(f64, 2)), statistics.deviance, 1e-14);
    try t.expectEqual(@as(f64, 4), try g.dispersion(statistics, .pearson, 1));
    try t.expectEqual(statistics.deviance, try g.dispersion(statistics, .deviance, 1));
    try t.expectEqual(@as(f64, 4), try g.dispersion(statistics, .constant, 2));
    const saturated = try g.goodness(&group, 1, false);
    try t.expectEqual(@as(usize, 0), saturated.df);
    try t.expectError(error.ExecError, g.dispersion(saturated, .pearson, 1));
    try t.expectError(error.ExecError, g.dispersion(statistics, .constant, 0));
}

test "LOGISTIC008 classification uses leave-one-Bernoulli correction and sample weights" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "Y", "F", "W" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 3 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 5 }, .{ .num = 2 } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "", "weight W;" }) |weight| {
        const source = try std.fmt.allocPrint(a, "proc logistic; freq F; {s} model Y(event='1')= / ctable pprob=(0.375 0.5); run;", .{weight});
        const analysis = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, source, &d)));
        const predictions = try g.crossvalidated(a, analysis.design, analysis.fit);
        const probability: f64 = 3.0 / 8.0;
        for ([_]f64{ 1, 0 }, predictions) |response, predicted| {
            const eta = @log(@as(f64, 3.0 / 5.0)) - (response - probability) / (probability * (1 - probability) * 7);
            try t.expectApproxEqAbs(1 / (1 + @exp(-eta)), predicted, 1e-14);
        }
        const rows = analysis.report.?.classification;
        try t.expectEqual(@as(usize, 2), rows.len);
        try t.expectEqual(@as(f64, 0), rows[0].true_positive);
        try t.expectEqual(@as(f64, 0), rows[0].true_negative);
        try t.expectEqual(@as(f64, 5), rows[0].false_positive);
        try t.expectEqual(@as(f64, 3), rows[0].false_negative);
        try t.expectEqual(@as(f64, 5), rows[1].true_negative);
        try t.expectEqual(@as(f64, 3), rows[1].false_negative);
        try t.expect(std.math.isNan(rows[1].positive_predictive));
        const grid = try g.cutpoints(a, predictions);
        try t.expectApproxEqAbs(@as(f64, 0.28), grid[0], 1e-14);
        try t.expectApproxEqAbs(@as(f64, 0.44), grid[grid.len - 1], 1e-14);
        for (grid[1..], grid[0 .. grid.len - 1]) |next, previous| try t.expectApproxEqAbs(@as(f64, 0.02), next - previous, 1e-14);
    }
}

test "LOGISTIC008 PEVENT classification matches published stratified sampling table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "Screen");
    _ = try ds.addColumn("Disease", .char);
    _ = try ds.addColumn("Test", .num);
    _ = try ds.addColumn("Count", .num);
    for ([_][]const u8{ "Present", "Present", "Absent", "Absent" }, [_]f64{ 1, 0, 1, 0 }, [_]f64{ 950, 50, 10, 990 }) |response, test_, count| try ds.appendRow(&.{ .{ .str = response }, .{ .num = test_ }, .{ .num = count } });
    var lib = Library.init(a);
    try lib.put("Screen", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    const source = "proc logistic; freq Count; model Disease(event='Present')=Test / pevent=.5 .01 ctable pprob=.5; run;";
    try l.run(cx, &out, try lex.tokenize(a, source, &d));
    const offset = std.mem.indexOf(u8, out.items, "Classification Table").?;
    // Entire published object, S154 physical p.6008 (Example79.5), all
    // counts and posterior percentages, including the prior probability field.
    const expected = "Classification Table Correct Incorrect Percentages Prob Prob Non- Non- Sensi- Speci- Pos Neg Event Level Event Event Event Event Correct tivity ficity Pred Pred 0.500 0.500 950 990 10 50 97.0 95.0 99.0 99.0 95.2 0.010 0.500 950 990 10 50 99.0 95.0 99.0 49.0 99.9";
    var words = std.mem.tokenizeAny(u8, expected, " ");
    var actual = std.mem.tokenizeAny(u8, out.items[offset..], " \r\n\t");
    while (words.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "<missing>");
    try t.expect(actual.next() == null);
    try t.expectEqualStrings("", try d.render());
}

test "LOGISTIC008 Hosmer Lemeshow tie blocks target rule and final group merge" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // F=13,G=5 -> target3. The p=.3 tie block has frequency5 and may not
    // split. The final frequency1 is <13/(2*5), so it merges backward.
    const groups = try g.hosmerGroups(a, &.{ 0, 1, 0, 0, 1, 1, 0 }, &.{ 0.1, 0.2, 0.3, 0.3, 0.4, 0.5, 0.6 }, &.{ 2, 2, 3, 2, 1, 2, 1 }, 5);
    try t.expectEqual(@as(usize, 3), groups.len);
    for (groups, [_]f64{ 4, 5, 4 }, [_]f64{ 2, 0, 3 }, [_]f64{ 0.6, 1.5, 2.0 }) |group, total, events, expected| {
        try t.expectEqual(total, group.trials);
        try t.expectEqual(events, group.events);
        try t.expectApproxEqAbs(expected, group.expected, 1e-14);
    }
    const result = try g.hosmerStatistic(groups, .{ .groups = 5 });
    try t.expectEqual(@as(usize, 1), result.df);
    try t.expectApproxEqAbs(@as(f64, 2494.0 / 357.0), result.statistic, 1e-12);
    try t.expectEqual(@as(usize, 7), (try g.hosmerStatistic(groups, .{ .groups = 5, .df = 7 })).df);
    try t.expectEqual(@as(usize, 2), (try g.hosmerStatistic(groups, .{ .groups = 5, .reduce = 1 })).df);
    const tied = try g.hosmerGroups(a, &.{ 0, 1 }, &.{ 0.5, 0.5 }, &.{ 3, 5 }, 10);
    try t.expectEqual(@as(usize, 1), tied.len);
    try t.expectError(error.ExecError, g.hosmerStatistic(tied, .{}));
}

test "LOGISTIC008 actual LACKFIT integration uses fitted probabilities and requested degrees" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "hl");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 2, 3, 4, 6, 7, 8 }, 0..) |events, x| {
        try ds.appendRow(&.{ .{ .num = @floatFromInt(x) }, .{ .num = 1 }, .{ .num = events } });
        try ds.appendRow(&.{ .{ .num = @floatFromInt(x) }, .{ .num = 0 }, .{ .num = 10 - events } });
    }
    var lib = Library.init(a);
    try lib.put("hl", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic; freq f; model y(event='1')=x / lackfit(ngroups=5) ctable pprob=(0.3,0.5 to 0.8 by 0.1); run;";
    const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
    try t.expectEqual(@as(usize, 5), spec.pprob.len);
    for (spec.pprob, [_]f64{ 0.3, 0.5, 0.6, 0.7, 0.8 }) |actual, expected| try t.expectApproxEqAbs(expected, actual, 1e-14);
    const result = try l.analyze(cx, spec);
    const hl = result.report.?.hosmer.?;
    try t.expectEqual(@as(usize, 5), hl.groups.len);
    try t.expectEqual(@as(usize, 3), hl.df);
    var expected_chi: f64 = 0;
    for (hl.groups, [_]f64{ 10, 10, 10, 10, 20 }, [_]f64{ 2, 3, 4, 6, 15 }, 0..) |group, n, events, i| {
        const probability = 1 / (1 + @exp(-(result.fit.coefficients[0] + result.fit.coefficients[1] * @as(f64, @floatFromInt(i)))));
        var expected = 10 * probability;
        if (i == 4) expected += 10 / (1 + @exp(-(result.fit.coefficients[0] + 5 * result.fit.coefficients[1])));
        try t.expectEqual(n, group.trials);
        try t.expectEqual(events, group.events);
        try t.expectApproxEqAbs(expected, group.expected, 1e-12);
        expected_chi += (events - expected) * (events - expected) / (expected * (1 - expected / n));
    }
    try t.expectApproxEqAbs(expected_chi, hl.statistic, 1e-12);
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, source, &d));
    try t.expect(std.mem.indexOf(u8, out.items, "Partition for the Hosmer and Lemeshow Test") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "y = 1 y = 0") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Classification Table") != null);
    const overridden = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; model y(event='1')=x / lackfit(ngroups=5 df=7); run;", &d)));
    try t.expectEqual(@as(usize, 7), overridden.report.?.hosmer.?.df);
    try t.expectEqual(hl.statistic, overridden.report.?.hosmer.?.statistic);
}

test "LOGISTIC008 ignored SCALE and AGGREGATE controls and unsupported paths are visible" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    var lib = Library.init(a);
    try lib.put("One", &fixture.ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "scale=none", "scale=pearson", "scale=deviance", "aggregate=(A B)", "pprob=(0 .5 1) pevent=.01" }) |options| {
        const source = try std.fmt.allocPrint(a, "proc logistic; freq F; model Y=A / {s}; run;", .{options});
        const spec = try l.parse(cx, try lex.tokenize(a, source, &d));
        try t.expect(!l.diagnosticOptions(spec));
        const analysis = try l.analyze(cx, spec);
        try t.expect(analysis.report == null);
    }
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{ "scale=pearson aggregate", "scale=2", "scale=williams", "lackfit(ngroups=4)", "pprob=1.1 ctable", "gof", "ctable" }, [_]u8{ 2, 2, 1, 1, 1, 2, 2 }) |options, rc| {
        var errors = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const context: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
        const source = try std.fmt.allocPrint(a, "proc logistic; freq F; model Y=A / {s}; run;", .{options});
        diag.resetGap();
        try t.expectError(error.ParseError, l.run(context, &out, try lex.tokenize(a, source, &errors)));
        try t.expectEqual(rc, diag.exitCode(diag.gapHit(), errors.hasErrors()));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "LOGISTIC008 grouped trial provenance and aggregation boundaries remain explicit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "grouped");
    for ([_][]const u8{ "r", "n", "x", "f", "w", "constant" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 4 }, 0..) |events, i| try ds.appendRow(&.{ .{ .num = events }, .{ .num = 5 }, .{ .num = @floatFromInt(i) }, .{ .num = 2 }, .{ .num = 2 }, .{ .num = 0 } });
    var lib = Library.init(a);
    try lib.put("grouped", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const single = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; model r/n=x / scale=none; run;", &d)));
    const repeated = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; model r/n=x / scale=none aggregate; run;", &d)));
    try t.expectEqual(@as(usize, 3), single.report.?.goodness.?.profiles);
    try t.expectEqual(@as(usize, 1), single.report.?.goodness.?.df);
    try t.expect(single.report.?.goodness.?.grouped);
    try t.expect(!repeated.report.?.goodness.?.grouped);
    try t.expectEqual(@as(usize, 3), repeated.report.?.goodness.?.profiles);
    try t.expectApproxEqAbs(2 * single.report.?.goodness.?.pearson, repeated.report.?.goodness.?.pearson, 1e-10);
    try t.expectApproxEqAbs(2 * single.report.?.goodness.?.deviance, repeated.report.?.goodness.?.deviance, 1e-10);
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{
        "proc logistic; freq f; model r/n=x / scale=none; run;",
        "proc logistic; weight w; model r/n=x / scale=none aggregate; run;",
        "proc logistic; model r/n=x / scale=none aggregate=(constant); run;",
        "proc logistic; model r/n=x / lackfit; run;",
    }) |source| {
        var errors = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const context: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
        diag.resetGap();
        try t.expectError(error.ParseError, l.run(context, &out, try lex.tokenize(a, source, &errors)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), errors.hasErrors()));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    try t.expectError(error.ExecError, g.goodness(&.{}, 0, false));
}

test "LOGISTIC008 CTABLE is ignored for ordinal response as documented" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try original(a);
    try fixture.ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 3 }, .{ .num = 1 } });
    var lib = Library.init(a);
    try lib.put("One", &fixture.ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const result = try l.analyze(cx, try l.parse(cx, try lex.tokenize(a, "proc logistic; freq F; model Y= / ctable; run;", &d)));
    try t.expectEqual(@as(usize, 3), result.design.response.levels.len);
    try t.expect(result.report == null);
    try t.expectEqualStrings("", try d.render());
}
