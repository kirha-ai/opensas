//! COMMON029 source pp.539-543. Whole original plus independently derived
//! balanced cell-means tests. No temporary oracle is used by any regression.
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("slice_parse.zig");
const slice = @import("lsmeans_slice.zig");
const H = struct {
    cx: proc.ProcCtx,
    fn init(a: std.mem.Allocator) !H {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        const source = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/persist_common029_slice.sas", "sample", &.{ "x", "z", "y", "group", "weight", "freq" }, &.{3}, 0);
        ds.* = .init(a, "factorial");
        for (source.columns.items) |column| _ = try ds.addColumnLike(column.name, column);
        _ = try ds.addColumn("h", .num);
        for (source.rows.items, 0..) |row, i| {
            const cells = try a.alloc(@import("../value.zig").Value, 7);
            @memcpy(cells[0..6], row);
            cells[6] = .{ .num = @floatFromInt((i + 1) % 2) };
            try ds.appendRow(cells);
        }
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = .init(a);
        try lib.put("factorial", ds);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        return .{ .cx = .{ .arena = a, .lib = lib, .diags = d } };
    }
    fn run(h: H, options: []const u8) ![]const u8 {
        const code = try std.fmt.allocPrint(h.cx.arena, "proc mixed data=factorial;class group h;model y=group|h;{s}run;", .{options});
        var out: std.ArrayList(u8) = .empty;
        try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(h.cx.arena, code, h.cx.diags));
        return out.items;
    }
};
fn words(want: []const u8, got: []const u8) !void {
    var w = std.mem.tokenizeAny(u8, want, " \t\r\n");
    var g = std.mem.tokenizeAny(u8, got, " \t\r\n");
    while (w.next()) |token| try t.expectEqualStrings(token, g.next() orelse return error.MissingField);
    try t.expect(g.next() == null);
}
test "COMMON029 complete original simple effects and differences" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const actual = try h.run("slice group*h / sliceby=h diff;");
    const expected = try @import("ttest_test_assets.zig").listing(a, "tests/corpus/persist_common029_slice.txt");
    try words(expected, actual);
    try t.expect(!h.cx.diags.hasErrors());
}
test "COMMON029 shared slice full joint hypotheses and per-partition adjustment" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const linear = @import("linear_hypothesis.zig");
    const model = linear.Model{ .estimates = &.{ 1, 2, 4 }, .covariance_kernel = &.{ 0.5, 0, 0, 0, 1.0 / 3.0, 0, 0, 0, 0.25 }, .alias_transpose = &.{ 1, 0, 0, 0, 1, 0, 0, 0, 1 }, .scale = 1, .denominator_df = 10, .estimability_tolerance = 1e-10, .rank_tolerance = 1e-12 };
    const rows = [_][]const f64{ &.{ 1, 0, 0 }, &.{ 0, 1, 0 }, &.{ 0, 0, 1 } };
    const result = try slice.testPartition(a, model, &rows, &.{ 0, 1, 2 });
    try t.expectEqual(@as(usize, 2), result.hypotheses.len);
    try t.expectEqualSlices(f64, &.{ 1, -1, 0 }, result.hypotheses[0].coefficients);
    try t.expectEqualSlices(f64, &.{ 1, 0, -1 }, result.hypotheses[1].coefficients);
    // Delta=(-1,-3), covariance[[5/6,1/2],[1/2,3/4]] hasdet3/8.
    // Quadratic14, rank2 =>F7; F(2,10)tail=(5/12)^5.
    try t.expectEqual(linear.Status.estimable, result.result.status);
    try t.expectEqual(@as(usize, 2), result.result.rank);
    try t.expectApproxEqAbs(@as(f64, 7), result.result.f.?, 1e-12);
    try t.expectApproxEqAbs(std.math.pow(f64, 5.0 / 12.0, 5), result.result.f_probability.?, 1e-12);
    const margins = [_]slice.Row{ .{ .levels = &.{ 0, 0 }, .coefficients = rows[0] }, .{ .levels = &.{ 0, 1 }, .coefficients = rows[1] }, .{ .levels = &.{ 0, 2 }, .coefficients = rows[2] } };
    const partition = (try slice.partitions(a, &margins, &.{0}))[0];
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = 3, .q = 0, .coefficients = model.estimates, .covariance = model.covariance_kernel, .aliases = model.alias_transpose };
    for ([_]@import("lsmeans_inference.zig").Adjustment{ .bon, .sidak }) |method| {
        const got = try slice.compute(a, joint, &margins, partition, 10, 0.05, 1e-10, 1e-12, true, method, true);
        try t.expectEqual(@as(usize, 3), got.differences.len);
        for (got.differences) |difference| {
            const p = difference.value.p.?;
            const expected = if (method == .bon) @min(1, 3 * p) else 1 - std.math.pow(f64, 1 - p, 3);
            try t.expectApproxEqAbs(expected, difference.adjusted_p.?, 1e-14);
            try t.expect(difference.lower.? < difference.value.estimate.? and difference.upper.? > difference.value.estimate.?);
        }
    }
}
test "COMMON029 nonestimable margins can have estimable differences and rank is not row count" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const linear = @import("linear_hypothesis.zig");
    const model = linear.Model{ .estimates = &.{ 2, 0 }, .covariance_kernel = &.{ 4, 0, 0, 0 }, .alias_transpose = &.{ 1, 0, 0, 0 }, .scale = 1, .denominator_df = 8, .estimability_tolerance = 1e-8, .rank_tolerance = 1e-10 };
    const rows = [_][]const f64{ &.{ 1, 1 }, &.{ 0, 1 }, &.{ -1, 1 } };
    const result = try slice.testPartition(a, model, &rows, &.{ 0, 1, 2 });
    try t.expectEqual(linear.Status.estimable, result.result.status);
    try t.expectEqual(@as(usize, 1), result.result.rank);
    try t.expectApproxEqAbs(@as(f64, 1), result.result.f.?, 1e-12);
    const bad = [_][]const f64{ &.{ 1, 1 }, &.{ 0, 0 } };
    const missing = try slice.testPartition(a, model, &bad, &.{ 0, 1 });
    try t.expectEqual(linear.Status.nonestimable, missing.result.status);
    try t.expect(missing.result.f == null and missing.result.f_probability == null);
    const one = try slice.testPartition(a, model, &rows, &.{0});
    try t.expectEqual(linear.Status.zero_rank, one.result.status);
    try t.expect(one.result.f == null);
}
test "COMMON029 defaults multiple rules formatted filters and real nof diffs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const defaults = try h.run("slice group*h /diff;");
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, defaults, "F Test for group*h"));
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, defaults, "Simple Differences of group*h"));
    const selected = try h.run("slice group*h / simple(h='1' group='A') diff;");
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, selected, "F Test for group*h"));
    try t.expect(std.mem.indexOf(u8, selected, "h 1 A B -12.6667 2.9814 8 -4.25 0.0028") != null);
    const nof = try h.run("slice group*h /sliceby=h nof;");
    try t.expect(std.mem.indexOf(u8, nof, "F Test for group*h") == null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, nof, "Simple Differences of group*h"));
    const means = try h.run("slice group*h /sliceby=h means;");
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, means, "\ngroup*h Least Squares Means Slice"));
    const intervals = try h.run("slice group*h /sliceby=h means cl;");
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, intervals, "Alpha Lower Upper"));
    const lo = 9 - 2.306004135204166 * @sqrt(@as(f64, 40.0 / 9.0));
    const hi = 9 + 2.306004135204166 * @sqrt(@as(f64, 40.0 / 9.0));
    const interval = try std.fmt.allocPrint(a, "0.05 {d:.4} {d:.4}", .{ lo, hi });
    try t.expect(std.mem.indexOf(u8, intervals, interval) != null);
    for ([_][]const u8{ "mixed", "LOGISTIC", "GENMOD", "PLM", "SURVEYREG" }) |name| try t.expect(parse.applicable(name));
    for ([_][]const u8{ "GLM", "REG", "TTEST" }) |name| try t.expect(!parse.applicable(name));
}
test "COMMON029 applicability and unavailable population margins fail visibly" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "slice group;", "slice group h;", "slice x*h;", "slice group*h /sliceby=x;" }) |source| {
        const h = try H.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, h.run(source));
        try t.expect(!diag.gapHit());
    }
    const h = try H.init(a);
    const tokens = try lex.tokenize(a, "group*h / diff", h.cx.diags);
    try t.expectError(error.ParseError, parse.parse(h.cx, "GLM", tokens[0 .. tokens.len - 1], 1));
    const missing = try H.init(a);
    const ds = missing.cx.lib.find("factorial").?;
    var rows: std.ArrayList([]const @import("../value.zig").Value) = .empty;
    for (ds.rows.items) |row| if (!(std.mem.eql(u8, row[3].str, "B") and row[6].num == 1)) {
        try rows.append(a, row);
    };
    ds.rows = rows;
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, @import("mixed.zig").run(missing.cx, &out, try lex.tokenize(a, "proc mixed data=factorial;class group h;model y=group|h x /notest;slice group*h /sliceby=h diff;run;", missing.cx.diags)));
    try t.expect(diag.gapHit());
}

test "COMMON029 original partitions use actual GLS L covariance and independent rational contrasts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const code = "proc mixed data=factorial;class group h;model y=group|h;run;";
    const declarations = try @import("mixed_parse.zig").parse(h.cx, try lex.tokenize(a, code, h.cx.diags));
    const model = try @import("mixed_model.zig").parse(h.cx, declarations.input.ds, declarations.statements, .formatted, 0.05);
    const groups = try @import("mixed_input.zig").prepare(h.cx, declarations, model.required_columns);
    const design = try @import("mixed_design.zig").build(h.cx, model, groups[0].selected);
    const math = @import("mixed_fit.zig");
    const fit = try math.fit(a, .{ .x = design.matrix.x, .y = design.y, .n = design.matrix.n, .p = design.matrix.p, .weights = design.weights }, .{});
    try t.expectEqual(@as(usize, 8), fit.df_error);
    try t.expectApproxEqAbs(@as(f64, 40.0 / 3.0), fit.residual_variance, 1e-10);
    const means = try @import("mixed_lsmeans.zig").coefficients(h.cx, model, design, 2);
    const rows = try a.alloc(slice.Row, means.len);
    for (means, rows) |mean, *row| row.* = .{ .levels = mean.levels, .coefficients = mean.l };
    const partitions = try slice.partitions(a, rows, &.{1});
    try t.expectEqual(@as(usize, 2), partitions.len);
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = design.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    for (partitions, [_]f64{ -13, -38.0 / 3.0 }, [_]f64{ 1521.0 / 80.0, 1444.0 / 80.0 }) |partition, estimate, f_value| {
        const result = try slice.compute(a, joint, rows, partition, 8, 0.05, 1e-4, model.options.singular, true, .none, true);
        try t.expectEqual(@as(usize, 1), result.test_result.num_df);
        try t.expectApproxEqAbs(f_value, result.test_result.f.?, 1e-10);
        try t.expectEqual(@as(usize, 1), result.differences.len);
        const difference = result.differences[0];
        try t.expectApproxEqAbs(estimate, difference.value.estimate.?, 1e-10);
        try t.expectApproxEqAbs(@as(f64, 80.0 / 9.0), difference.value.se.? * difference.value.se.?, 1e-10);
        try t.expectApproxEqAbs(result.test_result.f.?, difference.value.t.? * difference.value.t.?, 1e-10);
        try t.expectApproxEqAbs(result.test_result.p.?, difference.value.p.?, 1e-14);
    }
}

test "COMMON029 routing follows produced slice objects and unproduced captures warn" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try H.init(a);
    var dest = @import("../ods_listing.zig").Listing{};
    dest.trace = h.cx.diags;
    h.cx.listing = &dest;
    _ = try dest.parse(a, h.cx.diags, try lex.tokenize(a, "ods select SliceDiffs;", h.cx.diags));
    const output = try h.run("slice group*h /sliceby=h diff;");
    try t.expect(std.mem.indexOf(u8, output, "Simple Differences") != null);
    try t.expect(std.mem.indexOf(u8, output, "F Test for") == null);
    try t.expect(std.mem.indexOf(u8, output, "Model Information") == null);
    var traces: usize = 0;
    for (h.cx.diags.list.items) |entry| if (std.mem.indexOf(u8, entry.message, "Path:       Mixed.SliceDiffs") != null) {
        traces += 1;
    };
    try t.expectEqual(@as(usize, 2), traces);
    var other = try H.init(a);
    var capture = @import("../ods.zig").Capture{};
    other.cx.capture = &capture;
    try capture.parse(a, other.cx.diags, try lex.tokenize(a, "ods output SliceTests=absent;", other.cx.diags));
    _ = try other.run("slice group*h /sliceby=h nof;");
    try capture.finish(other.cx.lib, other.cx.diags);
    try t.expect(other.cx.lib.find("absent") == null);
    try t.expect(!other.cx.diags.hasErrors());
    var warnings: usize = 0;
    for (other.cx.diags.list.items) |entry| if (entry.severity == .warning) {
        warnings += 1;
    };
    try t.expectEqual(@as(usize, 1), warnings);
    const code_gap = try H.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, code_gap.run("code file='unused.sas';"));
    try t.expect(diag.gapHit());
}

test "COMMON029 actual nuisance population coefficients remain fractional with GLS scaling" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const ds = h.cx.lib.find("factorial").?;
    // Each of the four group*h cells observes each nuisance C level once.
    _ = try ds.addColumn("c", .num);
    for (ds.rows.items, 0..) |row, i| {
        const values = try a.alloc(@import("../value.zig").Value, 8);
        @memcpy(values[0..7], row[0..7]);
        values[7] = .{ .num = @floatFromInt((i / 2) % 3) };
        ds.rows.items[i] = values;
    }
    const source = "proc mixed data=factorial;class group h c;model y=group|h c;run;";
    const decl = try @import("mixed_parse.zig").parse(h.cx, try lex.tokenize(a, source, h.cx.diags));
    const model = try @import("mixed_model.zig").parse(h.cx, ds, decl.statements, .formatted, 0.05);
    const groups = try @import("mixed_input.zig").prepare(h.cx, decl, model.required_columns);
    const design = try @import("mixed_design.zig").build(h.cx, model, groups[0].selected);
    const math = @import("mixed_fit.zig");
    const fit = try math.fit(a, .{ .x = design.matrix.x, .y = design.y, .n = design.matrix.n, .p = design.matrix.p }, .{});
    // Independent orthogonal ANOVA: oldwithinSS320/3 minus C SS589/6
    // leaves17/2 on6df, henceMSE17/12 and difference variance17/18.
    try t.expectEqual(@as(usize, 6), fit.df_error);
    try t.expectApproxEqAbs(@as(f64, 17.0 / 12.0), fit.residual_variance, 1e-11);
    const margins = try @import("mixed_lsmeans.zig").coefficients(h.cx, model, design, 2);
    const rows = try a.alloc(slice.Row, margins.len);
    for (margins, rows) |margin, *row| {
        row.* = .{ .levels = margin.levels, .coefficients = margin.l };
        for (design.matrix.columns, 0..) |column, j| if (column.effect_index != null and column.effect_index.? == 3) {
            try t.expectApproxEqAbs(@as(f64, 1.0 / 3.0), margin.l[j], 1e-15);
        };
    }
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = design.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    const parts = try slice.partitions(a, rows, &.{1});
    for (parts, [_]f64{ 3042.0 / 17.0, 2888.0 / 17.0 }) |part, expected| {
        const result = try slice.compute(a, joint, rows, part, 6, 0.05, 1e-4, model.options.singular, true, .none, false);
        try t.expectApproxEqAbs(expected, result.test_result.f.?, 1e-8);
        try t.expectApproxEqAbs(@as(f64, 17.0 / 18.0), result.differences[0].value.se.? * result.differences[0].value.se.?, 1e-11);
    }
}

// MIXED012 uses the production MODEL/X/Z parser and actual known-covariance
// GLS. Known variances are inputs to this mathematical check, never a stand-in
// fit for an unsupported residual covariance structure.
const SlicePrepared = struct {
    m: @import("mixed_model.zig").Spec,
    r: @import("mixed_random.zig").Spec,
    x: @import("mixed_design.zig").Design,
    z: @import("mixed_random.zig").Design,
    requests: []const @import("mixed_slice.zig").Request,
};
fn slicePrepare(cx: proc.ProcCtx, source: []const u8) !SlicePrepared {
    const s = try @import("mixed_parse.zig").parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const m = try @import("mixed_model.zig").parse(cx, s.input.ds, s.statements, s.options.order, 0.05);
    const r = try @import("mixed_random.zig").parse(cx, s.input.ds, m.matrix, s.statements);
    const groups = try @import("mixed_input.zig").prepare(cx, s, m.required_columns);
    return .{ .m = m, .r = r, .x = try @import("mixed_design.zig").build(cx, m, groups[0].selected), .z = try @import("mixed_random.zig").build(cx, r, groups[0].selected), .requests = try @import("mixed_slice.zig").parse(cx, m, s.statements) };
}
fn sliceKnown(cx: proc.ProcCtx, p: SlicePrepared, variances: []const f64) !@import("mixed_fit.zig").GLS {
    const math = @import("mixed_fit.zig");
    const components = try cx.arena.alloc(math.Component, p.z.components.len);
    for (p.z.components, components) |src, *dst| dst.* = .{ .name = src.name, .kernel = src.kernel, .columns = src.columns };
    return math.knownCovariance(cx.arena, .{ .x = p.x.matrix.x, .y = p.x.y, .n = p.x.matrix.n, .p = p.x.matrix.p, .weights = p.x.weights, .components = components, .singular = p.m.options.singular }, variances);
}
fn sliceRows(cx: proc.ProcCtx, p: SlicePrepared) ![]const slice.Row {
    const means = try @import("mixed_lsmeans.zig").coefficients(cx, p.m, p.x, p.requests[0].effect);
    const rows = try cx.arena.alloc(slice.Row, means.len);
    for (means, rows) |mean, *row| row.* = .{ .levels = mean.levels, .coefficients = mean.l };
    return rows;
}
test "STAT-MIXED-012 unbalanced slices use actual cell GLS covariance and per-partition Bonferroni family" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "cells");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 0 }, .{ 1, 1, 2 }, .{ 1, 2, 5 }, .{ 1, 3, 7 }, .{ 1, 3, 9 }, .{ 1, 3, 11 }, .{ 2, 1, 3 }, .{ 2, 2, 6 }, .{ 2, 2, 8 }, .{ 2, 3, 10 }, .{ 2, 3, 12 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("cells", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try slicePrepare(cx, "proc mixed;class A B;model Y=A|B;slice A*B /sliceby=A adjust=bon cl df=6;run;");
    const fit = try sliceKnown(cx, p, &.{2});
    const rows = try sliceRows(cx, p);
    const parts = try slice.partitions(a, rows, &.{0});
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = p.x.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    try t.expectEqual(@as(usize, 5), fit.df_error);
    const df = try @import("mixed_slice.zig").denominatorDF(cx, p.m, p.r, p.x, p.z, fit.df_error, p.requests[0]);
    try t.expectEqual(@as(f64, 6), df);
    // Cell means=(1,5,9)/(3,7,11), n=(2,1,3)/(1,2,2), Var=2/n.
    // Wald Q=sum n*(mean-weighted_mean)^2/2; F=Q/2.
    const variances = [_][3]f64{ .{ 3, 5.0 / 3.0, 8.0 / 3.0 }, .{ 3, 3, 2 } };
    for (parts, [_]f64{ 58.0 / 3.0, 56.0 / 5.0 }, variances) |part, expected_f, expected_variances| {
        const result = try slice.compute(a, joint, rows, part, df, 0.05, 1e-4, p.m.options.singular, true, .bon, true);
        try t.expectEqual(@as(usize, 2), result.test_result.num_df);
        try t.expectApproxEqAbs(expected_f, result.test_result.f.?, 1e-10);
        // F(2,6) survival=(3/(3+F))^3.
        try t.expectApproxEqAbs(std.math.pow(f64, 3 / (3 + expected_f), 3), result.test_result.p.?, 1e-12);
        try t.expectEqual(@as(usize, 3), result.differences.len);
        for (result.differences, [_]f64{ -4, -8, -4 }, expected_variances) |d, expected, variance| {
            try t.expectApproxEqAbs(expected, d.value.estimate.?, 1e-11);
            try t.expectApproxEqAbs(variance, d.value.se.? * d.value.se.?, 1e-11);
            try t.expectApproxEqAbs(@min(1, 3 * d.value.p.?), d.adjusted_p.?, 1e-14);
            // Independent t6 CDF integral after u=t/sqrt(6+t^2).
            const critical = (d.upper.? - expected) / @sqrt(variance);
            const u = critical / @sqrt(6 + critical * critical);
            const cdf = 0.5 + 15.0 / 16.0 * (u - 2.0 / 3.0 * u * u * u + 1.0 / 5.0 * u * u * u * u * u);
            try t.expectApproxEqAbs(@as(f64, 1 - 0.05 / 6.0), cdf, 1e-11);
            try t.expectApproxEqAbs(2 * expected - d.upper.?, d.lower.?, 1e-11);
        }
    }
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed_slice.zig").publishRouted(cx, &out, p.m, p.r, p.x, p.z, fit, p.requests, null);
    try t.expectEqual(@as(usize, 6), std.mem.count(u8, out.items, "Bonferroni"));
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 2 6 19.33") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "A 2 2 6 11.20") != null);
    // End-to-end estimated residual variance is SSE/DF=14/5, so the
    // same two F statistics scale by 2/(14/5), without changing source L.
    var actual: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(cx, &actual, try lex.tokenize(a, "proc mixed;class A B;model Y=A|B;slice A*B /sliceby=A adjust=bon cl df=6;run;", &diagnostics));
    try t.expect(std.mem.indexOf(u8, actual.items, "A 1 2 6 13.81") != null);
    try t.expect(std.mem.indexOf(u8, actual.items, "A 2 2 6 8.00") != null);
    try t.expect(!diagnostics.hasErrors());
}

test "STAT-MIXED-012 actual aliased nuisance margins retain nonestimable status but valid within-slice differences" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "aliased");
    for ([_][]const u8{ "A", "B", "C", "Y" }) |name| _ = try ds.addColumn(name, .num);
    // C=A: no observations for A1/C2 or A2/C1. All A*B target cells
    // exist; balancing over C makes their means nonestimable. Within-A
    // B contrasts cancel that missing nuisance direction, across-A do not.
    for ([_][3]f64{ .{ 1, 1, 0 }, .{ 1, 1, 2 }, .{ 1, 2, 4 }, .{ 1, 2, 6 }, .{ 2, 1, 8 }, .{ 2, 1, 10 }, .{ 2, 2, 14 }, .{ 2, 2, 16 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[0] }, .{ .num = row[2] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("aliased", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try slicePrepare(cx, "proc mixed;class A B C;model Y=A|B C /notest;slice A*B /sliceby(A B) means diff;run;");
    const fit = try sliceKnown(cx, p, &.{2});
    const rows = try sliceRows(cx, p);
    const linear = @import("mixed_contrasts_kernel.zig");
    const joint = linear.Joint{ .p = p.x.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    for (rows) |row| {
        const mean = try linear.estimate(joint, row.coefficients, 4, 0.05, .two, 1e-4);
        try t.expect(!mean.estimable);
        try t.expect(mean.estimate == null and mean.se == null and mean.p == null);
    }
    const parts = try slice.partitions(a, rows, &.{0});
    for (parts, [_]f64{ -4, -6 }) |part, expected| {
        const result = try slice.compute(a, joint, rows, part, 4, 0.05, 1e-4, p.m.options.singular, true, .none, true);
        try t.expect(result.test_result.estimable);
        try t.expectApproxEqAbs(expected, result.differences[0].value.estimate.?, 1e-11);
        try t.expectApproxEqAbs(@as(f64, 2), result.differences[0].value.se.? * result.differences[0].value.se.?, 1e-11);
        try t.expectApproxEqAbs(expected * expected / 2, result.test_result.f.?, 1e-11);
    }
    for (try slice.partitions(a, rows, &.{1})) |part| {
        const result = try slice.compute(a, joint, rows, part, 4, 0.05, 1e-4, p.m.options.singular, true, .none, false);
        try t.expect(!result.test_result.estimable and result.test_result.f == null and result.test_result.p == null);
        try t.expect(!result.differences[0].value.estimable);
    }
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed_slice.zig").publishRouted(cx, &out, p.m, p.r, p.x, p.z, fit, p.requests, null);
    try t.expectEqual(@as(usize, 10), std.mem.count(u8, out.items, "Non-est"));
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 1 2 -4.0000 1.4142 4") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "B 1 . . . .") != null);
}

test "STAT-MIXED-012 split plot uses sliced effect containment DF and actual random covariance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try slicePrepare(cx, "proc mixed;class A B Block;model Y=A B A*B;random Block A*Block;slice A*B /sliceby=A diff cl;run;");
    const fit = try sliceKnown(cx, p, &.{ 2995.0 / 48.0, 2215.0 / 144.0, 337.0 / 36.0 });
    const df = try @import("mixed_slice.zig").denominatorDF(cx, p.m, p.r, p.x, p.z, fit.df_error, p.requests[0]);
    // N=24, rankX=6; rank[X Z]=15. No RANDOM term contains A*B,
    // so source DF=24-15=9, not residual18 or main-effect A's6.
    try t.expectEqual(@as(usize, 18), fit.df_error);
    try t.expectEqual(@as(f64, 9), df);
    const rows = try sliceRows(cx, p);
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = p.x.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    const parts = try slice.partitions(a, rows, &.{0});
    for (parts, [_]f64{ 8.25, 7.75, 0.5 }) |part, expected| {
        const result = try slice.compute(a, joint, rows, part, df, 0.05, 1e-4, p.m.options.singular, true, .none, true);
        const d = result.differences[0].value;
        // Four-block B differences cancel both shared random components;
        // variance=2*Residual/4=337/72, while cell means retain them.
        try t.expectApproxEqAbs(expected, d.estimate.?, 1e-9);
        try t.expectApproxEqAbs(@as(f64, 337.0 / 72.0), d.se.? * d.se.?, 1e-9);
        try t.expectApproxEqAbs(expected * expected * 72 / 337, result.test_result.f.?, 1e-9);
        try t.expectApproxEqAbs(result.test_result.p.?, d.p.?, 1e-13);
        const radius = 2.2621571628540993 * @sqrt(@as(f64, 337.0 / 72.0)); // t9(.975)
        try t.expectApproxEqAbs(expected - radius, d.lower.?, 1e-8);
    }
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed_slice.zig").publishRouted(cx, &out, p.m, p.r, p.x, p.z, fit, p.requests, null);
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 1 2 8.2500 2.1635 9") != null);
    var residual_model = p.m;
    residual_model.options.ddfm = .residual;
    try t.expectEqual(@as(f64, 18), try @import("mixed_slice.zig").denominatorDF(cx, residual_model, p.r, p.x, p.z, fit.df_error, p.requests[0]));
    var override = p.requests[0];
    override.spec.options.df = 7.5;
    try t.expectEqual(@as(f64, 7.5), try @import("mixed_slice.zig").denominatorDF(cx, p.m, p.r, p.x, p.z, fit.df_error, override));
}

test "STAT-MIXED-012 unavailable repeated default DF is diagnosed before inference" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try H.init(a);
    const p = try slicePrepare(h.cx, "proc mixed data=factorial;class group h;model y=group|h;repeated h /subject=group;slice group*h;run;");
    try t.expect(p.m.has_repeated);
    try t.expectEqual(@as(usize, 0), p.z.components.len);
    // Only test DF dispatch here: no diagonal fit is substituted for the
    // unsupported REPEATED covariance, and the full PROC remains fail-loud.
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, @import("mixed_slice.zig").denominatorDF(h.cx, p.m, p.r, p.x, p.z, 8, p.requests[0]));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors()));
    try t.expect(std.mem.indexOf(u8, h.cx.diags.list.items[h.cx.diags.list.items.len - 1].message, "between-within") != null);
    var request = p.requests[0];
    request.spec.options.df = 5;
    try t.expectEqual(@as(f64, 5), try @import("mixed_slice.zig").denominatorDF(h.cx, p.m, p.r, p.x, p.z, 8, request));
    var residual_model = p.m;
    residual_model.options.ddfm = .residual;
    try t.expectEqual(@as(f64, 8), try @import("mixed_slice.zig").denominatorDF(h.cx, residual_model, p.r, p.x, p.z, 8, p.requests[0]));
}

test "STAT-MIXED-012 WEIGHT and complete-case selection flow into slice GLS estimates and variance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "weighted");
    for ([_][]const u8{ "A", "B", "Y", "W" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 1, 0, 1 }, .{ 1, 1, 4, 3 }, .{ 1, 2, 6, 1 }, .{ 1, 2, 8, 3 }, .{ 2, 1, 10, 1 }, .{ 2, 1, 14, 3 }, .{ 2, 2, 20, 1 }, .{ 2, 2, 22, 3 }, .{ 1, 1, 1000, 0 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = std.math.nan(f64) }, .{ .num = 100 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("weighted", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try slicePrepare(cx, "proc mixed;class A B;model Y=A|B;weight W;slice A*B /sliceby=A diff;run;");
    try t.expectEqual(@as(usize, 8), p.x.matrix.n);
    const fit = try sliceKnown(cx, p, &.{2});
    const rows = try sliceRows(cx, p);
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = p.x.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    const parts = try slice.partitions(a, rows, &.{0});
    const df = try @import("mixed_slice.zig").denominatorDF(cx, p.m, p.r, p.x, p.z, fit.df_error, p.requests[0]);
    try t.expectEqual(@as(f64, 4), df);
    // Known residual2 and each cell weight sum4: Var(mean)=1/2.
    // Precision-weighted means=(3,7.5,13,21.5), not raw means=(2,7,12,21).
    for (parts, [_]f64{ -4.5, -8.5 }) |part, expected| {
        const result = try slice.compute(a, joint, rows, part, df, 0.05, 1e-4, p.m.options.singular, true, .none, false);
        const d = result.differences[0].value;
        try t.expectApproxEqAbs(expected, d.estimate.?, 1e-11);
        try t.expectApproxEqAbs(@as(f64, 1), d.se.?, 1e-11);
        try t.expectApproxEqAbs(expected * expected, result.test_result.f.?, 1e-10);
        try t.expectApproxEqAbs(result.test_result.p.?, d.p.?, 1e-13);
    }
}

test "STAT-MIXED-012 saturated missing cell remains explicit while complete slices and observed differences survive" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "incomplete");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    // A1/B1 is absent, including the default first hypothesis anchor. Every
    // observed cell has two responses mean +/-1, so REML MSE=10/5=2.
    for ([_][3]f64{ .{ 1, 2, 4 }, .{ 1, 2, 6 }, .{ 1, 3, 8 }, .{ 1, 3, 10 }, .{ 2, 1, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 6 }, .{ 2, 2, 8 }, .{ 2, 3, 10 }, .{ 2, 3, 12 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("incomplete", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try slicePrepare(cx, "proc mixed;class A B;model Y=A|B /notest;slice A*B /sliceby=A means diff cl;run;");
    const fit = try sliceKnown(cx, p, &.{2});
    const rows = try @import("mixed_slice.zig").populationRows(cx, p.m, p.x, p.requests[0].effect);
    try t.expectEqual(@as(usize, 6), rows.len);
    try t.expectEqual(@as(usize, 5), fit.df_error);
    try t.expect(!rows[0].available);
    try t.expectEqual(@as(usize, 0), rows[0].coefficients.len);
    try t.expectEqualSlices(?usize, &.{ 0, 0 }, rows[0].levels);
    for (rows[1..]) |row| {
        try t.expect(row.available);
        try t.expectEqual(p.x.matrix.p, row.coefficients.len);
    }
    const joint = @import("mixed_contrasts_kernel.zig").Joint{ .p = p.x.matrix.p, .q = 0, .coefficients = fit.coefficients, .covariance = fit.covariance, .aliases = fit.alias_coefficients };
    const parts = try slice.partitions(a, rows, &.{0});
    try t.expectError(error.InvalidInput, slice.compute(a, joint, rows, parts[0], 0, 0.05, 1e-4, p.m.options.singular, true, .none, true));
    const absent = try slice.compute(a, joint, rows, parts[0], 5, 0.05, 1e-4, p.m.options.singular, true, .none, true);
    // Equality of all three population cells is untestable, but B2-B3 is
    // fully identified. Never drop B1 and relabel a one-df test as the full F.
    try t.expect(!absent.test_result.estimable);
    try t.expect(absent.test_result.f == null and absent.test_result.p == null);
    try t.expectEqual(@as(usize, 0), absent.hypothesis.len);
    try t.expectEqual(@as(usize, 3), absent.differences.len);
    for (absent.differences[0..2]) |d| {
        try t.expect(!d.value.estimable);
        try t.expect(d.value.estimate == null and d.value.se == null and d.value.p == null);
        try t.expect(d.lower == null and d.upper == null and d.adjusted_p == null);
        try t.expectEqual(@as(usize, 0), d.coefficients.len);
    }
    try t.expect(absent.differences[2].value.estimable);
    try t.expectApproxEqAbs(@as(f64, -4), absent.differences[2].value.estimate.?, 1e-11);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 2)), absent.differences[2].value.se.?, 1e-11);
    const complete = try slice.compute(a, joint, rows, parts[1], 5, 0.05, 1e-4, p.m.options.singular, true, .none, true);
    try t.expectEqual(@as(usize, 2), complete.test_result.num_df);
    try t.expectApproxEqAbs(@as(f64, 16), complete.test_result.f.?, 1e-10);
    try t.expectApproxEqAbs(std.math.pow(f64, 5.0 / 37.0, 2.5), complete.test_result.p.?, 1e-12);
    for (complete.differences) |d| try t.expect(d.value.estimable);
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed;class A B;model Y=A|B /notest;slice A*B /sliceby=A means diff cl;run;", &diagnostics));
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, out.items, "Non-est"));
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 . . . .") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "A 2 2 5 16.00") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 2 3 -4.0000 1.4142 5") != null);
    try t.expect(!diagnostics.hasErrors());
    // Unknown multiplicity-family semantics are not guessed from the count
    // of observed cells. Missing target cells with ADJUST stay explicit gaps.
    diag.resetGap();
    defer diag.resetGap();
    var requests = try a.dupe(@import("mixed_slice.zig").Request, p.requests);
    requests[0].spec.options.adjust = .bon;
    out.clearRetainingCapacity();
    try t.expectError(error.ParseError, @import("mixed_slice.zig").publishRouted(cx, &out, p.m, p.r, p.x, p.z, fit, requests, null));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try t.expect(std.mem.indexOf(u8, diagnostics.list.items[diagnostics.list.items.len - 1].message, "UnavailableAdjustmentFamily") != null);
}
