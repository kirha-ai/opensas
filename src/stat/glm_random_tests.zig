const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const random = @import("glm_random.zig");
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    // Small full-rank orthogonal designs: conservative operation-count and
    // conditioning budget independent of observed implementation differences.
    const ku = 4096 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 64 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn sample(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y", "w" }) |name| _ = try ds.addColumn(name, .num);
    for (1..4) |ai| for (1..3) |bi| for ([_]f64{ -1, 1 }) |error_value| {
        const av: f64 = @floatFromInt(ai);
        const bv: f64 = @floatFromInt(bi);
        try ds.appendRow(&.{ .{ .num = av }, .{ .num = bv }, .{ .num = 10 * av + 4 * bv + 2 * av * bv + error_value }, .{ .num = 1 } });
    };
    try lib.put("sample", ds);
    return ds;
}

test "GLM007 complete original GLM RANDOM prefix preserves every SAS token and note" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    var ds = try helper.data(a, "tests/corpus/stat_glm_random_two_way.sas", "machine", &.{ "machine", "person", "rating" }, &.{}, 0);
    try t.expectEqual(@as(usize, 44), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("machine", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = try helper.read(a, "tests/corpus/stat_glm_random_two_way.sas");
    const start = std.mem.indexOf(u8, source, "proc glm").?;
    var output: std.ArrayList(u8) = .empty;
    try glm.run(cx, &output, try lex.tokenize(a, source[start..], &diagnostics));
    const contract = try helper.read(a, "tests/corpus/stat_glm_random_two_way.txt");
    const words_start = std.mem.indexOf(u8, contract, "words ").? + 6;
    const end = std.mem.indexOfScalarPos(u8, contract, words_start, '\n').?;
    var expected = std.mem.tokenizeAny(u8, contract[words_start..end], " \t\r\n");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    while (expected.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "");
    try t.expect(actual.next() == null);
    try t.expect(!diagnostics.hasErrors());
    try t.expectEqual(@as(usize, 1), diagnostics.list.items.len);
    try t.expectEqualStrings("TYPE I EMS not available without the E1 option.", diagnostics.list.items[0].message);
}

test "GLM007 balanced EMS and random TEST match independent orthogonal ANOVA" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class A B; model Y=A B A*B; random B A*B / test; run;", &diagnostics));
    const view = try selection.View.init(a, spec.input, .{});
    const d = try glm.design.build(cx, spec, view, spec.responses[0]);
    var fitted = try glm.fitDesign(cx, spec, d);
    defer fitted.deinit(a);
    const result = try random.compute(cx, spec, d, fitted);
    // With a=3,b=2,r=2, EMS(A)=sigma_e²+2sigma_AB²+Q(A),
    // EMS(B)=sigma_e²+2sigma_AB²+6sigma_B² and EMS(AB)=sigma_e²+2sigma_AB².
    try close(2, result.coefficients[0][1]);
    try close(0, result.coefficients[0][0]);
    try close(2, result.coefficients[1][1]);
    try close(6, result.coefficients[1][0]);
    try close(2, result.coefficients[2][1]);
    try close(0, result.coefficients[2][0]);
    // Orthogonal component SS: A=4*169*2=1352; B=6*(16+16)=192;
    // AB=8, residual=12. Every group has two replicates, so DFE=6.
    for ([_]f64{ 1352, 192, 8 }, fitted.type_iii) |ss, effect| try close(ss, effect.ss);
    try close(12, fitted.model.fit.sse);
    try t.expectEqual(@as(usize, 6), fitted.model.fit.df_error);
    for (result.tests[0..2]) |test_value| {
        try close(1, test_value.interaction_weight);
        try close(0, test_value.error_weight);
        try close(4, test_value.denominator_ms);
        try close(2, test_value.denominator_df);
    }
    try close(169, result.tests[0].f_value);
    try close(1.0 / 170.0, result.tests[0].p_value); // F(2,2) survival=1/(1+F)
    try close(48, result.tests[1].f_value);
    try close(1 - @sqrt(@as(f64, 24.0 / 25.0)), result.tests[1].p_value); // F(1,2)
    try close(2, result.tests[2].f_value);
    try close(0.216, result.tests[2].p_value); // F(2,6) survival=(1+F/3)^-3
    var listing: std.ArrayList(u8) = .empty;
    try random.render(cx, &listing, spec, d, fitted, result);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, listing.items, "Error: MS(A*B) 2 8.000000 4.000000"));
    try t.expect(std.mem.indexOf(u8, listing.items, "0.0000*MS(Error)") == null);
}

test "GLM007 RANDOM unsupported domains and malformed effects stay captured" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{
        "proc glm; class A B; model Y=A B A*B; random B A*B / q; run;",
        "proc glm; class A B; model Y=A B A*B; weight w; random B A*B / test; run;",
        "proc glm; class A B; model Y=A B A*B; random A B A*B / test; run;",
    }) |source| {
        diag.resetGap();
        defer diag.resetGap();
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, source, &diagnostics)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expectEqual(@as(usize, 0), output.items.len);
    }
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class A B; model Y=A B A*B; random B B; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    for (ds.rows.items) |*observation| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[2] = .{ .num = 0 };
        observation.* = cells;
    }
    diag.resetGap();
    output.clearRetainingCapacity();
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class A B; model Y=A B A*B; random B A*B / test; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expectEqual(@as(usize, 0), output.items.len);
}

fn oneWaySample(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 3, 4, 5, 6, 7, 9, 11 }, [_]f64{ 1, 1, 2, 2, 2, 3, 3, 3 }) |y, group| try ds.appendRow(&.{ .{ .num = group }, .{ .num = y } });
    try lib.put("sample", ds);
    return ds;
}

test "GLM009 one-way RANDOM has unbalanced IID-level EMS and exact residual test" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try oneWaySample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class group; model y=group; random group / test; run;", &diagnostics));
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const r = try random.compute(cx, spec, d, fit);
    try t.expect(r.one_way);
    // Counts(2,3,3): c=(8-(4+9+9)/8)/2=21/8. Full independent random
    // level indicators imply K_ij=1 iff the group indices agree, NOT a
    // sum-to-zero constrained random-coefficient covariance.
    try close(21.0 / 8.0, r.coefficients[0][0]);
    const coded = try @import("glm_estimability.zig").codedDesign(cx, spec, d);
    for (0..8) |i| for (0..8) |j| {
        var covariance_entry: f64 = 0;
        for (coded.columns, 0..) |column, k| if (column.effect_index != null) { covariance_entry += coded.x[i * coded.p + k] * coded.x[j * coded.p + k]; };
        try close(if (d.classes[0].row_levels[i] == d.classes[0].row_levels[j]) @as(f64, 1) else 0, covariance_entry);
    };
    // Group means(2,5,9), grandmean23/4: SSA=123/2, SSE=12.
    try close(123.0 / 2.0, fit.type_iii[0].ss);
    try close(12, fit.model.fit.sse);
    try close(12.0 / 5.0, r.tests[0].denominator_ms);
    try close(5, r.tests[0].denominator_df);
    try close(205.0 / 16.0, r.tests[0].f_value);
    const q: f64 = 8.0 / 49.0; // F(2,5) tail=(1+2F/5)^(-5/2)
    try close(q * q * @sqrt(q), r.tests[0].p_value);
    var output: std.ArrayList(u8) = .empty;
    try random.render(cx, &output, spec, d, fit, r);
    const expected =
        \\The GLM Procedure
        \\Source Type III Expected Mean Square
        \\group Var(Error) + 2.625 Var(group)
        \\The GLM Procedure
        \\Tests of Hypotheses for Mixed Model Analysis of Variance
        \\Dependent Variable: y
        \\Source DF Type III SS Mean Square F Value Pr > F
        \\group 2 61.500000 30.750000 12.81 0.0108
        \\Error: MS(Error) 5 12.000000 2.400000
    ;
    var want = std.mem.tokenizeAny(u8, expected, " \t\r\n");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    while (want.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "");
    try t.expect(actual.next() == null);
}

test "GLM009 multiple RANDOM requests are separate and fixed estimates retain fixed error variance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try oneWaySample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class group; model y=group; estimate 'first-last' group 1 0 -1; random group; random group / test; lsmeans group / stderr; run;", &diagnostics));
    try t.expect(!spec.random.?.tests);
    try t.expect(spec.random.?.next.?.tests);
    try t.expect(spec.random.?.next.?.next == null);
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const analyses = try random.computeAll(cx, spec, d, fit);
    try t.expectEqual(@as(usize, 2), analyses.len);
    try close(analyses[0].result.coefficients[0][0], analyses[1].result.coefficients[0][0]);
    const estimates = try @import("glm_estimate.zig").computeAll(cx, spec, d, fit.model.fit.mse, fit.model.fit.df_error);
    try close(-7, estimates[0].inference.estimate.?);
    try close(@sqrt(@as(f64, 2)), estimates[0].inference.standard_error.?);
    // A-C variance=MSE*(1/2+1/3)=2. Substitution of the RANDOM numerator
    // MS or a mixed-model covariance would violate the source p.4099 contract.
    const means = try @import("glm_lsmeans.zig").compute(cx, spec, d, spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    for ([_]f64{ 2, 5, 9 }, [_]f64{ 6.0 / 5.0, 4.0 / 5.0, 4.0 / 5.0 }, means.means) |mean, variance, row| {
        try close(mean, row.inference.estimate.?);
        try close(@sqrt(variance), row.inference.standard_error.?);
    }
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, output.items, "Type III Expected Mean Square"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, output.items, "Tests of Hypotheses for Mixed Model Analysis of Variance"));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, output.items, "first-last -7.00000000 1.41421356"));
}

test "GLM009 zero observed random effect retains F zero while unidentifiable variance remains loud" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("y", .num);
    for (1..4) |group| for ([_]f64{ -1, 0, 1 }) |y| try ds.appendRow(&.{ .{ .num = @floatFromInt(group) }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const tokens = try lex.tokenize(a, "proc glm; class group; model y=group; random group / test; run;", &diagnostics);
    const spec = try glm.parse(cx, tokens);
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const r = try random.compute(cx, spec, d, fit);
    try close(3, r.coefficients[0][0]);
    try close(0, r.tests[0].f_value);
    try close(1, r.tests[0].p_value);
    // One observation per level has no residual variance information.
    var saturated = Dataset.init(a, "sample");
    _ = try saturated.addColumn("group", .num);
    _ = try saturated.addColumn("y", .num);
    for (1..4) |group| try saturated.appendRow(&.{ .{ .num = @floatFromInt(group) }, .{ .num = @floatFromInt(group) } });
    try lib.put("sample", &saturated);
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, tokens));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expectEqual(@as(usize, 0), output.items.len);
}

test "GLM009 requested Type IV EMS reuse only validated equal hypothesis spaces" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "ss4", "ss3 ss4" }, 0..) |options, request_index| {
        const text = try std.fmt.allocPrint(a, "proc glm; class A B; model Y=A B A*B / {s}; random B A*B / test; run;", .{options});
        const spec = try glm.parse(cx, try lex.tokenize(a, text, &diagnostics));
        const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
        var fit = try glm.fitDesign(cx, spec, d);
        defer fit.deinit(a);
        try t.expectEqual(@import("glm_fit.zig").TypeIVBasis.complete_factorial, fit.type_iv_basis.?);
        const analyses = try random.computeAll(cx, spec, d, fit);
        try t.expectEqual(@as(usize, request_index + 1), analyses.len);
        try t.expectEqual(random.SumOfSquares.iv, analyses[analyses.len - 1].result.ss_kind);
        if (request_index == 1) try t.expectEqual(random.SumOfSquares.iii, analyses[0].result.ss_kind);
        for (analyses) |analysis| {
            try close(2, analysis.result.coefficients[0][1]);
            try close(6, analysis.result.coefficients[1][0]);
            try close(169, analysis.result.tests[0].f_value);
            try close(1.0 / 170.0, analysis.result.tests[0].p_value);
        }
        var output: std.ArrayList(u8) = .empty;
        try glm.execute(cx, &output, spec);
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, output.items, "Type IV Expected Mean Square"));
        try t.expectEqual(@as(usize, request_index), std.mem.count(u8, output.items, "Type III Expected Mean Square"));
        try t.expectEqual(@as(usize, 4), std.mem.count(u8, output.items, "Type IV SS"));
        try t.expectEqual(@as(usize, 4 * request_index), std.mem.count(u8, output.items, "Type III SS"));
    }
    try t.expectEqualStrings("", try diagnostics.render());
    // A one-way CLASS effect has the separate no-contained-effects basis.
    _ = try oneWaySample(a, &lib);
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class group; model y=group / ss4; random group / test; run;", &diagnostics));
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try t.expectEqual(@import("glm_fit.zig").TypeIVBasis.no_contained_effects, fit.type_iv_basis.?);
    const result = try random.compute(cx, spec, d, fit);
    try t.expect(result.one_way);
    try t.expectEqual(random.SumOfSquares.iv, result.ss_kind);
    try close(21.0 / 8.0, result.coefficients[0][0]);
    try close(205.0 / 16.0, result.tests[0].f_value);
}

test "GLM009 RANDOM FREQ equals literal replication for EMS and denominator inference" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    var expanded = Dataset.init(a, "expanded");
    for (ds.columns.items) |column| _ = try expanded.addColumn(column.name, column.type);
    for (ds.rows.items) |*observation| {
        const cells = try a.dupe(@import("../value.zig").Value, observation.*);
        cells[3] = .{ .num = 2 };
        observation.* = cells;
        try expanded.appendRow(cells);
        try expanded.appendRow(cells);
    }
    try lib.put("expanded", &expanded);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const programs = [_][]const u8{
        "proc glm data=sample; class A B; model Y=A B A*B; freq w; random B A*B / test; run;",
        "proc glm data=expanded; class A B; model Y=A B A*B; random B A*B / test; run;",
    };
    var results: [2]random.Result = undefined;
    for (programs, 0..) |program, index| {
        const spec = try glm.parse(cx, try lex.tokenize(a, program, &diagnostics));
        const view = try selection.View.init(a, spec.input, .{ .frequency = spec.freq });
        const d = try glm.design.build(cx, spec, view, spec.responses[0]);
        var fit = try glm.fitDesign(cx, spec, d);
        defer fit.deinit(a);
        results[index] = try random.compute(cx, spec, d, fit);
        try t.expectEqual(@as(usize, 24), fit.model.fit.n_used);
        try t.expectEqual(@as(usize, 18), fit.model.fit.df_error);
        try close(24, fit.model.fit.sse);
        try close(4.0 / 3.0, fit.model.fit.mse);
    }
    for (results[0].coefficients, results[1].coefficients) |left, right| for (left, right) |x, y| try close(x, y);
    for (results[0].tests, results[1].tests) |left, right| {
        inline for (.{ "interaction_weight", "error_weight", "denominator_ms", "denominator_df", "f_value", "p_value" }) |field| try close(@field(left, field), @field(right, field));
    }
    try close(4, results[0].coefficients[0][1]);
    try close(12, results[0].coefficients[1][0]);
    try close(6, results[0].tests[2].f_value);
    // For F(2,18), survival at6 is (1+6/9)^-9=(3/5)^9.
    try close(std.math.pow(f64, 3.0 / 5.0, 9), results[0].tests[2].p_value);
    // A one-way FREQ request uses replicated group counts in the coefficient,
    // not the number of stored rows: two copies of counts(2,3,3) give21/4.
    const one = try oneWaySample(a, &lib);
    _ = try one.addColumn("frequency", .num);
    for (one.rows.items) |*observation| {
        const cells = try a.alloc(@import("../value.zig").Value, 3);
        @memcpy(cells[0..2], observation.*);
        cells[2] = .{ .num = 2 };
        observation.* = cells;
    }
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm data=sample; class group; model y=group; freq frequency; random group / test; run;", &diagnostics));
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{ .frequency = spec.freq }), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const result = try random.compute(cx, spec, d, fit);
    try close(21.0 / 4.0, result.coefficients[0][0]);
    try close(13, result.tests[0].denominator_df);
    try close(24.0 / 13.0, result.tests[0].denominator_ms);
    try close(533.0 / 16.0, result.tests[0].f_value);
}

test "GLM009 RANDOM rejects nonclassification effects and invalid option syntax as user errors" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try oneWaySample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{
        "proc glm; model y=group; random group; run;",
        "proc glm; class group; model y=group; random group / test=1; run;",
        "proc glm; class group; model y=group; random group / invalid; run;",
    }) |program| {
        diag.resetGap();
        defer diag.resetGap();
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, program, &diagnostics)));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try t.expectEqual(@as(usize, 0), output.items.len);
    }
    try t.expect(std.mem.indexOf(u8, try diagnostics.render(), "RANDOM effects must contain only CLASS variables") != null);
    // Q is documented, but not yet implemented: it remains a capability gap.
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class group; model y=group; random group / q; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    // Multiple requests before RUN are supported; interactive RANDOM must not
    // accidentally succeed only through the direct parser execution path.
    diag.resetGap();
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class group; model y=group; run; random group / test; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
}

test "GLM009 an explicitly random interaction does not make its main effects random" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try glm.parse(cx, try lex.tokenize(a, "proc glm; class A B; model Y=A B A*B; random A*B / test; run;", &diagnostics));
    const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const result = try random.compute(cx, spec, d, fit);
    try t.expect(result.interaction_only and !result.one_way);
    for (result.coefficients) |row| { try close(0, row[0]); try close(2, row[1]); }
    try close(169, result.tests[0].f_value);
    try close(48, result.tests[1].f_value);
    var output: std.ArrayList(u8) = .empty;
    try random.render(cx, &output, spec, d, fit, result);
    try t.expect(std.mem.indexOf(u8, output.items, "A Var(Error) + 2 Var(A*B) + Q(A)") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "B Var(Error) + 2 Var(A*B) + Q(B)") != null);
    try t.expect(std.mem.indexOf(u8, output.items, "Var(A)") == null);
    try t.expect(std.mem.indexOf(u8, output.items, "Var(B)") == null);
    // The reverse implication is equally invalid: random main effects do not
    // silently make the omitted interaction random (S154 physical p.4100).
    diag.resetGap();
    defer diag.resetGap();
    output.clearRetainingCapacity();
    try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, "proc glm; class A B; model Y=A B A*B; random A B / test; run;", &diagnostics)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expectEqual(@as(usize, 0), output.items.len);
}
