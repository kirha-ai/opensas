//! Independent MIXED population-margin, GLS covariance and source-DF contracts.
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const math = @import("mixed_fit.zig");
const ls = @import("mixed_lsmeans.zig");
const selection = @import("data_selection.zig");
const Prepared = struct { spec: @import("mixed_parse.zig").Spec, m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, requests: []const ls.Request };
fn prepare(cx: proc.ProcCtx, source: []const u8) !Prepared {
    const s = try @import("mixed_parse.zig").parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const m = try model.parse(cx, s.input.ds, s.statements, s.options.order, 0.05);
    const r = try random.parse(cx, s.input.ds, m.matrix, s.statements);
    const groups = try @import("mixed_input.zig").prepare(cx, s, m.required_columns);
    const view = groups[0].selected;
    return .{ .spec = s, .m = m, .r = r, .x = try fixed.build(cx, m, view), .z = try random.build(cx, r, view), .requests = try ls.parse(cx, m, s.statements) };
}
fn known(cx: proc.ProcCtx, p: Prepared, variances: []const f64) !math.GLS {
    const components = try cx.arena.alloc(math.Component, p.z.components.len);
    for (p.z.components, components) |src, *dst| dst.* = .{ .name = src.name, .kernel = src.kernel, .columns = src.columns };
    return math.knownCovariance(cx.arena, .{ .x = p.x.matrix.x, .y = p.x.y, .n = p.x.matrix.n, .p = p.x.matrix.p, .weights = p.x.weights, .components = components, .singular = p.m.options.singular }, variances);
}
test "STAT-MIXED-010 split-plot margins use actual GLS covariance and effect DF rather than ESTIMATE DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try prepare(cx, "proc mixed data=sp;class A B Block;model Y=A B A*B;random Block A*Block;lsmeans A /diff cl;run;");
    const fit = try known(cx, p, &.{ 2995.0 / 48.0, 2215.0 / 144.0, 337.0 / 36.0 });
    const result = try ls.compute(cx, p.m, p.r, p.x, p.z, fit, p.requests);
    try t.expectEqual(@as(usize, 3), result.means.len);
    try t.expectEqual(@as(usize, 3), result.differences.len);
    for (result.means, [_]f64{ 263.0 / 8.0, 273.0 / 8.0, 103.0 / 4.0 }) |mean, expected| {
        try t.expect(mean.inference.estimable);
        try t.expectApproxEqAbs(expected, mean.inference.estimate.?, 1e-9);
        try t.expectEqual(@as(f64, 6), mean.inference.df);
        try t.expectApproxEqAbs(@as(f64, 1979.0 / 96.0), mean.inference.se.? * mean.inference.se.?, 1e-8);
        // Source effectA hasDF6, while the previous explicit ESTIMATE endingA*B hasDF9.
        // t6(.975) independently solves F=.5+(15/16)*(u-2u^3/3+u^5/5), u=t/sqrt(6+t^2).
        const radius = 2.4469118511449699710712968455477153 * @sqrt(@as(f64, 1979.0 / 96.0));
        try t.expectApproxEqAbs(expected - radius, mean.inference.lower.?, 1e-8);
    }
    const diff = result.differences[0];
    try t.expectApproxEqAbs(@as(f64, -1.25), diff.inference.estimate.?, 1e-9);
    try t.expectApproxEqAbs(@as(f64, 321.0 / 32.0), diff.inference.se.? * diff.inference.se.?, 1e-8);
    try t.expectEqual(@as(f64, 6), diff.inference.df);
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed data=sp;class A B Block;model Y=A B A*B;random Block A*Block;lsmeans A;run;", &diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "Least Squares Means") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "A 1 32.8750 4.5403 6 7.24") != null);
}

test "STAT-MIXED-010 unequal cell counts use balanced margins and explicit alpha requests CL" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "cells");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 0 }, .{ 1, 1, 2 }, .{ 1, 2, 5 }, .{ 2, 1, 9 }, .{ 2, 2, 11 }, .{ 2, 2, 13 }, .{ 2, 2, 15 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = Library.init(a);
    try lib.put("cells", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try prepare(cx, "proc mixed;class A B;model Y=A B A*B;lsmeans A /alpha=.1 df=5 pdiff=all;run;");
    try t.expect(p.requests[0].cl);
    try t.expectEqual(@import("lsmeans_inference.zig").Adjustment.none, p.requests[0].adjust);
    const fit = try known(cx, p, &.{1});
    const result = try ls.compute(cx, p.m, p.r, p.x, p.z, fit, p.requests);
    for (result.means, [_]f64{ 3, 11 }, [_]f64{ 3.0 / 8.0, 1.0 / 3.0 }) |mean, expected, variance| {
        try t.expectApproxEqAbs(expected, mean.inference.estimate.?, 1e-12);
        try t.expectApproxEqAbs(variance, mean.inference.se.? * mean.inference.se.?, 1e-12);
        try t.expectEqual(@as(f64, 5), mean.inference.df);
    }
}

fn irrigation(a: std.mem.Allocator) !Dataset {
    const source = try @import("glm_persistence_tests.zig").read(a, "tests/fixtures/stat/mixed/irrigation_data.sas");
    const start = std.mem.indexOf(u8, source, "datalines;").? + 10;
    const end = std.mem.indexOfScalarPos(u8, source, start, ';').?;
    var tokens = std.mem.tokenizeAny(u8, source[start..end], " \r\n\t");
    var ds = Dataset.init(a, "line");
    _ = try ds.addColumn("Block", .num);
    _ = try ds.addColumn("Cult", .char);
    _ = try ds.addColumn("row", .num);
    _ = try ds.addColumn("Sbplt", .num);
    _ = try ds.addColumn("Irrig", .num);
    _ = try ds.addColumn("Dir", .char);
    _ = try ds.addColumn("Y", .num);
    var row: usize = 0;
    while (tokens.next()) |block| {
        row += 1;
        const cultivar = tokens.next().?;
        for (1..13) |subplot| {
            const y = try std.fmt.parseFloat(f64, tokens.next().?);
            try ds.appendRow(&.{ .{ .num = try std.fmt.parseFloat(f64, block) }, .{ .str = cultivar }, .{ .num = @floatFromInt(row) }, .{ .num = @floatFromInt(subplot) }, .{ .num = @floatFromInt(if (subplot <= 6) subplot else 13 - subplot) }, .{ .str = if (subplot <= 6) "North" else "South" }, .{ .num = y } });
        }
    }
    return ds;
}
test "STAT-MIXED-010 whole public irrigation data builds 27 margin rows with independent effect-specific DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try irrigation(a);
    try t.expectEqual(@as(usize, 108), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("line", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try prepare(cx, "proc mixed;class Block Cult Dir Irrig;model Y=Cult|Dir|Irrig@2;random Block Block*Dir Block*Irrig;lsmeans Cult|Irrig;run;");
    try t.expectEqual(@as(usize, 48), p.x.matrix.p);
    try t.expectEqual(@as(usize, 27), p.z.q);
    try t.expectEqual(@as(usize, 3), p.requests.len);
    for (p.requests, [_]usize{ 3, 6, 18 }, [_]usize{ 68, 10, 68 }) |request, row_count, df| {
        const rows = try ls.coefficients(cx, p.m, p.x, request.effect);
        try t.expectEqual(row_count, rows.len);
        // Fixed rank=1+2+1+5+2+10+5=26; random increment=2+2+10=14.
        // Hence fallbackDF108-40=68; Block*Irrig contributes(3-1)*(6-1)=10.
        try t.expectEqual(df, try random.containmentDF(cx, p.r, p.x.matrix, p.z, request.effect, p.x.weights, p.m.options.singular));
        for (rows) |margin| for (0..p.m.matrix.effects.len) |effect| {
            var sum: f64 = 0;
            for (p.x.matrix.columns, margin.l) |column, value| if (column.effect_index == effect) {
                sum += value;
            };
            try t.expectApproxEqAbs(@as(f64, 1), sum, 64 * std.math.floatEps(f64));
        };
    }
    // This validates X/Z/L/DF, not a replacement diagonal fit for the original
    // requested Toeplitz covariance. The full original still requires that fitter.
}

test "STAT-MIXED-010 differences are estimable independently of disconnected margins" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "disconnected");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 0 }, .{ 1, 1, 2 }, .{ 2, 1, 2 }, .{ 2, 1, 4 }, .{ 3, 2, 9 }, .{ 3, 2, 11 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = Library.init(a);
    try lib.put("disconnected", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const p = try prepare(cx, "proc mixed;class A B;model Y=A B /notest;lsmeans A /diff;run;");
    const fit = try known(cx, p, &.{1});
    const result = try ls.compute(cx, p.m, p.r, p.x, p.z, fit, p.requests);
    try t.expect(!result.means[0].inference.estimable and !result.means[1].inference.estimable);
    const difference = result.differences[0];
    try t.expect(difference.inference.estimable);
    try t.expectApproxEqAbs(@as(f64, -2), difference.inference.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), difference.inference.se.?, 1e-12);
    try t.expect(!result.differences[1].inference.estimable);
}

test "STAT-MIXED-010 parser scopes and unavailable algorithms fail through captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("sp", &ds);
    const Case = struct { code: []const u8, rc: u8 };
    for ([_]Case{ .{ .code = "proc mixed;class A B Block;lsmeans A;model Y=A B;run;", .rc = 1 }, .{ .code = "proc mixed;class A B Block;model Y=A B;lsmeans;run;", .rc = 1 }, .{ .code = "proc mixed;class A B Block;model Y=A B;lsmeans A /adjust=t;run;", .rc = 1 }, .{ .code = "proc mixed;class A B Block;model Y=A B;lsmeans A /at means;run;", .rc = 2 } }) |c| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try t.expectError(error.ParseError, prepare(cx, c.code));
        try t.expectEqual(c.rc, diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const p = try prepare(cx, "proc mixed;class A B Block;model Y=A B A*B;lsmeans A /adjust=tukey;run;");
    const fit = try known(cx, p, &.{1});
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, ls.compute(cx, p.m, p.r, p.x, p.z, fit, p.requests));
    try t.expect(diag.gapHit());
}

test "STAT-MIXED-010 real LSMeans and Diffs objects honor selection and trace identities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    var listing = @import("../ods_listing.zig").Listing{};
    listing.trace = &diagnostics;
    _ = try listing.parse(a, &diagnostics, try lex.tokenize(a, "ods select LSMeans Diffs;", &diagnostics));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics, .listing = &listing };
    var out: std.ArrayList(u8) = .empty;
    const source = "proc mixed;class A B Block;model Y=A B A*B;random Block A*Block;lsmeans A /diff;run;";
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "Least Squares Means") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Differences of Least Squares Means") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Covariance Parameter Estimates") == null);
    var means = false;
    var diffs = false;
    for (diagnostics.list.items) |entry| {
        means = means or std.mem.indexOf(u8, entry.message, "Path:       Mixed.LSMeans") != null;
        diffs = diffs or std.mem.indexOf(u8, entry.message, "Path:       Mixed.Diffs") != null;
    }
    try t.expect(means and diffs);
    _ = try listing.parse(a, &diagnostics, try lex.tokenize(a, "ods select none;", &diagnostics));
    out.clearRetainingCapacity();
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    try t.expectEqual(@as(usize, 0), out.items.len);
}
