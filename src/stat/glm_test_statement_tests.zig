const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const tests = @import("glm_test_statement.zig");
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    const ku = 32 * 24 * 15 * 15 * (std.math.floatEps(f64) / 2);
    // Balanced split-plot effect spaces are orthogonal. Their categorical
    // Gram blocks are I+J: the A and Block contrast inverse norms are1 and
    // 5/4, giving kappa_infinity<=15 after the B replication factor. For the
    // six-cell unbalanced example, counts1..2 give kappa_2<=6 and hence
    // kappa_infinity<=36. An envelope100 covers both independently.
    try t.expectApproxEqAbs(expected, actual, 100 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn parse(cx: proc.ProcCtx, text: []const u8) !glm.Spec { return glm.parse(cx, try lex.tokenize(cx.arena, text, cx.diags)); }
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design {
    return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight }), spec.responses[0]);
}
fn unbalanced(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "a", "b", "y" }) |name| _ = try ds.addColumn(name, .num);
    // S154 physical p.4115, all ten published observations.
    const rows = [_][3]f64{ .{ 1, 1, 23.5 }, .{ 1, 1, 23.7 }, .{ 1, 2, 28.7 }, .{ 2, 1, 8.9 }, .{ 2, 2, 5.6 }, .{ 2, 2, 8.9 }, .{ 3, 1, 10.3 }, .{ 3, 1, 12.5 }, .{ 3, 2, 13.6 }, .{ 3, 2, 14.6 } };
    for (rows) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    try lib.put("sample", ds);
    return ds;
}

test "GLM012 complete split-plot TEST listing uses nominated effect MS and actual error DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    var ds = try helper.data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    try t.expectEqual(@as(usize, 24), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = try helper.read(a, "tests/corpus/stat_glm_test_split_plot.sas");
    const start = std.mem.indexOf(u8, source, "proc glm").?;
    const spec = try parse(cx, source[start..]);
    var fit = try glm.fitDesign(cx, spec, try design(cx, spec));
    defer fit.deinit(a);
    const tables = try tests.compute(cx, spec, fit);
    try t.expectEqual(@as(usize, 1), tables.len);
    const row = tables[0].rows[0];
    try t.expectEqual(@as(usize, 9), fit.model.fit.df_error);
    try t.expectEqual(@as(usize, 6), row.error_df); // never substitute residual DF9
    try close(3919.0 / 12.0, row.numerator.ss);
    try close(963.0 / 4.0, tables[0].denominator.ss);
    try close(321.0 / 8.0, tables[0].denominator.ms);
    try close(3919.0 / 963.0, row.f_value);
    const ratio: f64 = 2889.0 / 6808.0; // independent F(2,6) survival
    try close(ratio * ratio * ratio, row.p_value);
    // Independent balanced ANOVA of the A-by-Block cell means, averaged
    // over the two B observations in each cell.
    const cells = [_][3]f64{ .{ 48.5, 43, 37 }, .{ 27.5, 32, 31.5 }, .{ 28, 29, 17 }, .{ 27.5, 32.5, 17.5 } };
    const amean = [_]f64{ 263.0 / 8.0, 273.0 / 8.0, 206.0 / 8.0 };
    const blockmean = [_]f64{ 257.0 / 6.0, 182.0 / 6.0, 148.0 / 6.0, 155.0 / 6.0 };
    const grand: f64 = 371.0 / 12.0;
    var ss: f64 = 0;
    for (cells, blockmean) |block, mean| for (block, amean) |cell, am| { const interaction = cell - mean - am + grand; ss += 2 * interaction * interaction; };
    try close(963.0 / 4.0, ss);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    const expected = try helper.read(a, "tests/corpus/stat_glm_test_split_plot.txt");
    const word_start = std.mem.indexOf(u8, expected, "words ").? + 6;
    const word_end = std.mem.indexOfScalarPos(u8, expected, word_start, '\n').?;
    var want = std.mem.tokenizeAny(u8, expected[word_start..word_end], " \t\r\n");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    while (want.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "");
    try t.expect(actual.next() == null);
    try t.expectEqualStrings("", try diagnostics.render());
}

test "GLM012 HTYPE ETYPE select distinct computed sums and multiple H effects are not pooled" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try unbalanced(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx,
        "proc glm; class a b; model y=a b a*b / ss1 ss2 ss3 ss4; " ++
        "test h=a e=b / htype=1 etype=3; " ++
        "test e=b h=a / htype=3 etype=1; " ++
        "test h=a a*b e=b / htype=2 etype=2; " ++
        "test h=a e=b; run;");
    var fit = try glm.fitDesign(cx, spec, try design(cx, spec));
    defer fit.deinit(a);
    const tables = try tests.compute(cx, spec, fit);
    try t.expectEqual(@as(usize, 4), tables.len);
    try t.expectEqual(@as(usize, 2), tables[2].rows.len);
    try t.expectEqual(tests.Kind.iv, tables[3].request.hypothesis_kind);
    try t.expectEqual(tests.Kind.iv, tables[3].request.error_kind);
    // Independent rational normal-equation/cell-mean arithmetic on the ten
    // published rows: TypeI A=494031/1000, TypeII A=1746921/3500,
    // TypeIII A=670751/1400. Residualized B'Y=-10, B'B=28/3 gives
    // TypeI/II B=75/7. Equal-cell B contrast=-2.05, variance4/9 gives
    // TypeIII B=15129/1600. Interaction SS=22023/1400 for all four types.
    const hypotheses = [_]f64{ 494031.0 / 1000.0, 670751.0 / 1400.0, 1746921.0 / 3500.0, 670751.0 / 1400.0 };
    const denominators = [_]f64{ 15129.0 / 1600.0, 75.0 / 7.0, 75.0 / 7.0, 15129.0 / 1600.0 };
    for (tables, hypotheses, denominators) |table, hss, ess| {
        const row = table.rows[0];
        try close(hss, row.numerator.ss);
        try close(ess, table.denominator.ss);
        try t.expectEqual(@as(usize, 2), row.numerator.df);
        try t.expectEqual(@as(usize, 1), row.error_df);
        const statistic = hss / 2 / ess;
        try close(statistic, row.f_value);
        try close(1 / @sqrt(1 + 2 * statistic), row.p_value); // F(2,1) tail
    }
    try close(22023.0 / 1400.0, tables[2].rows[1].numerator.ss);
    try t.expectEqual(@as(usize, 2), tables[2].rows[1].numerator.df);
    var output: std.ArrayList(u8) = .empty;
    try tests.render(cx, &output, spec, tables);
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, output.items, "Tests of Hypotheses Using"));
    try t.expect(std.mem.indexOf(u8, output.items, "Type III MS for b as an Error Term\n\nSource DF Type I SS") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "Type I MS for b as an Error Term\n\nSource DF Type III SS") != null);
}

test "GLM012 TEST requires explicit H E and only MODEL-requested SS types" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try unbalanced(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "test h=a", "test e=b", "test h=a e=a b", "test h=a e=b / htype=2", "test h=a e=b / etype=4", "test h=a e=b / htype=2.5", "test h=a e=b / wrong=3" }) |statement| {
        diag.resetGap();
        defer diag.resetGap();
        const program = try std.fmt.allocPrint(a, "proc glm; class a b; model y=a b a*b; {s}; run;", .{statement});
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, program, &diagnostics)));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expectEqual(@as(usize, 0), output.items.len);
    }
}

test "GLM012 degenerate H E inference is explicit while valid zero SS gives p one" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "a", "b", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (0..2) |ai| for (0..2) |bi| for ([_]f64{ -1, 1 }) |error_value| try ds.appendRow(&.{ .{ .num = @floatFromInt(ai) }, .{ .num = @floatFromInt(bi) }, .{ .num = 5 * @as(f64, @floatFromInt(bi)) + error_value } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class a b; model y=a b; test h=a e=b; test h=b e=b; run;");
    var fit = try glm.fitDesign(cx, spec, try design(cx, spec));
    defer fit.deinit(a);
    const tables = try tests.compute(cx, spec, fit);
    try close(0, tables[0].rows[0].numerator.ss);
    try close(0, tables[0].rows[0].f_value);
    try close(1, tables[0].rows[0].p_value);
    // The procedure must not silently validate independence assumptions. User
    // H=E produces the requested ratio1 and F(1,1) tail1/2 (source caution).
    try close(1, tables[1].rows[0].f_value);
    try close(0.5, tables[1].rows[0].p_value);
    // Collapse A to one level: E=A has zero DF, while H=A is nonestimable.
    for (ds.rows.items) |*observation| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[0] = .{ .num = 1 };
        observation.* = cells;
    }
    for ([_][]const u8{ "test h=b e=a", "test h=a e=b" }) |statement| {
        diag.resetGap();
        defer diag.resetGap();
        const program = try std.fmt.allocPrint(a, "proc glm; class a b; model y=a b; {s}; run;", .{statement});
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, program, &diagnostics)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expectEqual(@as(usize, 0), output.items.len);
    }
    const messages = try diagnostics.render();
    try t.expect(std.mem.indexOf(u8, messages, "degenerate error effect") != null);
    try t.expect(std.mem.indexOf(u8, messages, "nonestimable hypothesis effect") != null);
}

test "GLM012 complete original GLM and MIXED sequence retains all 481 reference tokens" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    var ds = try helper.data(a, "tests/corpus/stat_glm_random_two_way.sas", "machine", &.{ "machine", "person", "rating" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("machine", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var output: std.ArrayList(u8) = .empty;
    // Exact two analysis blocks from the original. Both operate on the SAME
    // persistent library and output stream; no re-created input between PROCs.
    try glm.run(cx, &output, try lex.tokenize(a, "proc glm data=machine; class machine person; model rating=machine person machine*person; random person machine*person / test; run;", &diagnostics));
    try @import("mixed.zig").run(cx, &output, try lex.tokenize(a, "proc mixed data=machine method=type3; class machine person; model rating=machine; random person machine*person; run;", &diagnostics));
    // Reuse the canonical existing expected contracts, not duplicate goldens.
    const prefix = try helper.read(a, "tests/corpus/stat_glm_random_two_way.txt");
    const word_start = std.mem.indexOf(u8, prefix, "words ").? + 6;
    const word_end = std.mem.indexOfScalarPos(u8, prefix, word_start, '\n').?;
    const suffix = try helper.read(a, "tests/fixtures/stat/mixed/machine_type3_full.txt");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    var count: usize = 0;
    for ([_][]const u8{ prefix[word_start..word_end], suffix }) |contract| {
        var expected = std.mem.tokenizeAny(u8, contract, " \t\r\n");
        while (expected.next()) |word| {
            try t.expectEqualStrings(word, actual.next() orelse "");
            count += 1;
        }
    }
    try t.expectEqual(@as(usize, 481), count);
    try t.expect(actual.next() == null);
    try t.expect(!diagnostics.hasErrors());
    try t.expectEqual(@as(usize, 1), diagnostics.list.items.len);
    try t.expectEqualStrings("TYPE I EMS not available without the E1 option.", diagnostics.list.items[0].message);
}
