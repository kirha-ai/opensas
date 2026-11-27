const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const means = @import("glm_means.zig");
const selection = @import("data_selection.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
fn close(expected: f64, actual: f64) !void {
    const ku = 4096 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 32 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn parse(cx: proc.ProcCtx, text: []const u8) !glm.Spec { return glm.parse(cx, try lex.tokenize(cx.arena, text, cx.diags)); }
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design { return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq }), spec.responses[0]); }

test "GLM013 complete unbalanced source separates observed means from balanced LS-means" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/glm/means_twoway.sas", "twoway", &.{ "Treatment", "Block", "y" }, &.{}, 0);
    try t.expectEqual(@as(usize, 33), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("twoway", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class Treatment Block; model y=Treatment|Block; means Treatment; lsmeans Treatment; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const raw = try means.compute(cx, spec, d, spec.means[0]);
    const adjusted = try @import("glm_lsmeans.zig").compute(cx, spec, d, spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    const raw_reference = [_]f64{ 320.0 / 11.0, 321.0 / 11.0, 332.0 / 11.0 };
    const ls_reference = [_]f64{ 25.6, 85.0 / 3.0, 310.0 / 9.0 };
    for (raw.groups, adjusted.means, raw_reference, ls_reference) |group, margin, raw_mean, ls_mean| {
        try t.expectEqual(@as(usize, 11), group.count);
        try close(raw_mean, group.means[0]);
        try close(ls_mean, margin.inference.estimate.?);
    }
    // Figure53.19 standard deviations, checked at half the printed unit.
    for (raw.groups, [_]f64{ 11.5104695, 11.5569735, 6.3058414 }) |group, sd| try t.expectApproxEqAbs(sd, group.standard_deviations[0], 0.00000005);
    var listing: std.ArrayList(u8) = .empty;
    try means.render(cx, &listing, spec, d, raw);
    try t.expectEqualStrings("\nThe GLM Procedure\n\nLevel of Treatment N y Mean Std Dev\n1 11 29.0909091 11.5104695\n2 11 29.1818182 11.5569735\n3 11 30.1818182 6.3058414\n", listing.items);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expect(std.mem.indexOf(u8, output.items, "Least Squares Means") != null);
    try t.expect(std.mem.indexOf(u8, output.items, listing.items) != null);
}

test "GLM013 MEANS FREQ matches expansion and DEPONLY excludes covariate summaries" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_][4]f64{ .{ 1, 0, 1, 2 }, .{ 1, 1, 4, 1 }, .{ 2, 0, 5, 1 }, .{ 2, 2, 8, 2 }, .{ 3, 3, 10, 1 } };
    var expanded = Dataset.init(a, "expanded");
    for (ds.columns.items) |column| _ = try expanded.addColumn(column.name, column.type);
    for (rows) |values| {
        var cells: [4]Value = undefined;
        for (values, &cells) |v, *cell| cell.* = .{ .num = v };
        try ds.appendRow(&cells);
        for (0..@as(usize, @intFromFloat(values[3]))) |_| try expanded.appendRow(&cells);
    }
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    try lib.put("expanded", &expanded);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const s = try parse(cx, "proc glm data=sample; class g; model y=g x; freq f; means g; means g / deponly; run;");
    const e = try parse(cx, "proc glm data=expanded; class g; model y=g x; means g; run;");
    const d = try design(cx, s);
    const raw = try means.compute(cx, s, d, s.means[0]);
    const dep = try means.compute(cx, s, d, s.means[1]);
    const rep = try means.compute(cx, e, try design(cx, e), e.means[0]);
    try t.expectEqualSlices(usize, &.{ 2, 1 }, raw.variables);
    try t.expectEqualSlices(usize, &.{2}, dep.variables);
    for (raw.groups, rep.groups, [_]usize{ 3, 3, 1 }, [_]f64{ 2, 7, 10 }) |group, literal, count, value| {
        try t.expectEqual(count, group.count);
        try close(value, group.means[0]);
        for (group.means, literal.means) |left, right| try close(left, right);
        for (group.standard_deviations, literal.standard_deviations) |left, right| {
            if (std.math.isNan(left)) try t.expect(std.math.isNan(right)) else try close(left, right);
        }
    }
    try close(@sqrt(@as(f64, 3)), raw.groups[0].standard_deviations[0]);
    try t.expect(std.math.isNan(raw.groups[2].standard_deviations[0]));
    var listing: std.ArrayList(u8) = .empty;
    try means.render(cx, &listing, s, d, dep);
    try t.expect(std.mem.endsWith(u8, listing.items, "3 1 10.0000000 .\n"));
}

test "GLM013 interaction MEANS retains only observed cells and follows CLASS level order" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "a", "b", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 2, 2, 8 }, .{ 2, 2, 10 }, .{ 1, 2, 4 }, .{ 1, 1, 2 } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] }, .{ .num = values[2] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const s = try parse(cx, "proc glm order=data; class a b; model y=a b a*b / ss1; means b*a; run;");
    const table = try means.compute(cx, s, try design(cx, s), s.means[0]);
    try t.expectEqual(@as(usize, 3), table.groups.len); // no fictitious absent cell
    for (table.groups, [_]f64{ 9, 4, 2 }) |group, expected| try close(expected, group.means[0]);
    try t.expectEqualSlices(usize, &.{ 0, 1 }, table.class_positions);
}

test "GLM013 unimplemented seven-group comparisons stay loud instead of using a shortcut" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("y", .num);
    for (0..14) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 2) }, .{ .num = @floatFromInt(i) } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "means g / waller regwq", "lsmeans g / pdiff=all" }) |statement| {
        diag.resetGap();
        defer diag.resetGap();
        const text = try std.fmt.allocPrint(a, "proc glm; class g; model y=g; {s}; run;", .{statement});
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.run(cx, &output, try lex.tokenize(a, text, &diagnostics)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    }
}


test "GLM013 LSMEANS alternate E uses selected MS DF while rank validation remains full-model" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for (1..4) |ai| for (1..3) |bi| for ([_]f64{ -1, 1 }) |error_value| {
        const av: f64 = @floatFromInt(ai);
        const bv: f64 = @floatFromInt(bi);
        try ds.appendRow(&.{ .{ .num = av }, .{ .num = bv }, .{ .num = 10 * av + 4 * bv + 2 * av * bv + error_value } });
    };
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm alpha=.1; class A B; model Y=A B A*B / alpha=.2; lsmeans A / stderr cl e=A*B; lsmeans A / cl e=A*B; lsmeans A / pdiff e=A*B; run;");
    try close(0.1, spec.proc_alpha);
    try close(0.2, spec.alpha); // MODEL ALPHA does not replace PROC default
    for (spec.lsmeans) |request| try close(0.1, request.alpha);
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try t.expectEqual(@as(usize, 6), fit.model.fit.df_error);
    try close(2, fit.model.fit.mse);
    // Orthogonal balanced data: interactionSS8/DF2 gives errorMS4.
    const table = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    try t.expectEqual(@as(usize, 2), table.df_error);
    const critical = @sqrt(@as(f64, 2)) * 0.9 / @sqrt(@as(f64, 0.19)); // exact t2 .95
    for (table.means, table.mean_limits, [_]f64{ 19, 32, 45 }) |mean, limit, expected| {
        try close(expected, mean.inference.estimate.?);
        try close(0.25, mean.inference.variance_factor.?);
        try close(1, mean.inference.standard_error.?);
        try close(expected - critical, limit.lower.?);
        try close(expected + critical, limit.upper.?);
    }
    // E= is explicitly ignored without STDERR/PDIFF/TDIFF, even with CL.
    const ignored = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[1], fit);
    try t.expectEqual(@as(usize, 6), ignored.df_error);
    try close(@sqrt(@as(f64, 0.5)), ignored.means[0].inference.standard_error.?);
    const compared = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[2], fit);
    try t.expectEqual(@as(usize, 3), compared.comparisons.len);
    try close(-13, compared.comparisons[0].inference.estimate.?);
    try close(@sqrt(@as(f64, 2)), compared.comparisons[0].inference.standard_error.?);
    // Exact two-sided t2 tail at13/sqrt2.
    try close(1 - 13 / @sqrt(@as(f64, 173)), compared.comparisons[0].adjusted_p.?);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    try t.expect(std.mem.indexOf(u8, output.items, "90% Confidence Limits") != null);
}

test "GLM013 LSMEANS ETYPE chooses actual error table and inactive ETYPE has no effect" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 12 }, .{ 1, 1, 14 }, .{ 1, 2, 11 }, .{ 1, 2, 9 }, .{ 2, 1, 20 }, .{ 2, 1, 18 }, .{ 2, 2, 17 } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] }, .{ .num = values[2] } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B; lsmeans A / stderr e=B etype=1; lsmeans A / stderr e=B; lsmeans A / stderr etype=2; run;");
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const one = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[0], fit);
    const three = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[1], fit);
    const residual = try @import("glm_lsmeans.zig").computeWithFit(cx, spec, d, spec.lsmeans[2], fit);
    // Equal-cell A1 margin variancefactor=(1/2+1/2)/4=1/4.
    // Source original B TypeI=169/15, TypeIII=10; B has one DF.
    try close(@sqrt(@as(f64, 169.0 / 60.0)), one.means[0].inference.standard_error.?);
    try close(@sqrt(@as(f64, 2.5)), three.means[0].inference.standard_error.?);
    try close(@sqrt(@as(f64, 0.5)), residual.means[0].inference.standard_error.?);
    try t.expectEqual(@as(usize, 1), one.df_error);
    try t.expectEqual(@as(usize, 1), three.df_error);
    try t.expectEqual(@as(usize, 3), residual.df_error); // ETYPE ignored without E=
    try close(one.means[0].inference.estimate.?, three.means[0].inference.estimate.?);
}


test "GLM013 original held-input plants baseline keeps all21 rows and exact ANOVA contract" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    const text = try helper.read(a, "tests/corpus/stat_glm_plants_baseline.sas");
    const input_start = std.mem.indexOf(u8, text, "input Type").?;
    const proc_start = std.mem.indexOf(u8, text, "proc glm;").?;
    var diagnostics = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var pdv = @import("../pdv.zig").Pdv.init(a);
    var evaluator: @import("../eval.zig").Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diagnostics };
    var executor = @import("../exec.zig").Executor.init(a, &pdv, &diagnostics, &evaluator, &lib);
    var ds = Dataset.init(a, "plants");
    try executor.run(try @import("../parser.zig").parse(a, text[input_start..proc_start], &diagnostics), &ds);
    try t.expectEqual(@as(usize, 21), ds.rows.items.len);
    try lib.put("plants", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics, .graph_title = "Balanced Data from Randomized Complete Block" };
    const spec = try parse(cx, text[proc_start..]);
    const d = try design(cx, spec);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try t.expectEqual(@as(usize, 12), fit.model.fit.df_error);
    try close(691.0 / 35.0, fit.model.fit.sse);
    try close(2279.0 / 70.0, fit.model.fit.y_mean);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    const contract = try helper.read(a, "tests/corpus/stat_glm_plants_baseline.txt");
    const start = std.mem.indexOf(u8, contract, "words ").? + 6;
    const end = std.mem.indexOfScalarPos(u8, contract, start, '\n').?;
    var want = std.mem.tokenizeAny(u8, contract[start..end], " \t\r\n");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    while (want.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "");
    try t.expect(actual.next() == null);
    try t.expect(!diagnostics.hasErrors());
}
