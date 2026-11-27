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
    try t.expectError(error.ParseError, @import("mixed.zig").run(missing.cx, &out, try lex.tokenize(a, "proc mixed data=factorial;class group h;model y=group|h /notest;slice group*h /sliceby=h diff;run;", missing.cx.diags)));
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
