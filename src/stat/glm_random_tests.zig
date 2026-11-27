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
    _ = try sample(a, &lib);
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
    const ds = lib.get("sample").?;
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
