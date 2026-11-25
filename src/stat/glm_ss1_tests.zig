//! STAT-COMMON-010: public SS1 path and independent sequential hypotheses.
const std = @import("std");
const testing = std.testing;
const A = std.mem.Allocator;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const render = @import("glm_render.zig");

const Analysis = struct { spec: glm.Spec, data: glm.design.Design, result: glm.math.Result };
fn analyze(cx: proc.ProcCtx, source: []const u8) !Analysis {
    const spec = try glm.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try @import("data_selection.zig").View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    const data = try glm.design.build(cx, spec, view, spec.responses[0]);
    return .{ .spec = spec, .data = data, .result = try glm.fitDesign(cx, spec, data) };
}
fn normalized(a: A, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var words = std.mem.tokenizeAny(u8, source, " \t\r\n");
    while (words.next()) |word| {
        if (out.items.len > 0) try out.append(a, ' ');
        try out.appendSlice(a, word);
    }
    return out.items;
}
fn factorial(a: A, lib: *Library, missing: bool) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cells");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    for (0..if (missing) @as(usize, 6) else 8) |i| {
        try ds.appendRow(&.{
            .{ .str = if (i < 4) "A1" else "A2" },
            .{ .str = if ((i / 2) % 2 == 0) "B1" else "B2" },
            .{ .num = @as(f64, @floatFromInt(1 + 4 * (i / 2) + 2 * (i % 2))) },
        });
    }
    try lib.put("cells", ds);
}

test "COMMON010 SS1 original unbalanced model retains all tables except unrequested Type III" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("weight", .num);
    _ = try ds.addColumn("freq", .num);
    const zs = [_]f64{ 1, 1, 2, 1, 3, 2, 4, 3, 5, 3, 5, 4 };
    const ys = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    for (zs, ys, 0..) |z, y, i| try ds.appendRow(&.{
        .{ .num = @floatFromInt(i + 1) },    .{ .num = z },                                                   .{ .num = y },
        .{ .str = if (i < 6) "A" else "B" }, .{ .num = if (i == 1 or i == 4 or i == 7 or i == 10) 2 else 1 }, .{ .num = if (i == 2 or i == 7) 2 else 1 },
    });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const result = try analyze(cx, "proc glm data=sample; class group; model y=group x z / ss1; run; quit;");
    try testing.expect(result.spec.ss1_only);
    try testing.expectEqual(@as(usize, 12), result.data.n);
    try testing.expectEqual(@as(usize, 8), result.result.model.fit.df_error);
    for (result.result.type_i, [_]f64{ 494.0833333, 101.15, 0.7432584 }) |effect, ss| {
        try testing.expectEqual(@as(usize, 1), effect.df);
        try testing.expectApproxEqAbs(ss, effect.ss, 5e-8);
    }
    try testing.expectApproxEqAbs(@as(f64, 8.9400749), result.result.model.fit.sse, 5e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.4384), result.result.type_i[2].p_value, 5e-5);
    var output: std.ArrayList(u8) = .empty;
    try render.render(cx, &output, result.spec, result.data, result.result);
    const actual = try normalized(a, output.items);
    try testing.expect(std.mem.indexOf(u8, actual, "Type I SS") != null);
    try testing.expect(std.mem.indexOf(u8, actual, "Type III SS") == null);
    try testing.expect(std.mem.indexOf(u8, actual, "group 1 494.0833333 494.0833333 442.13 <.0001") != null);
    try testing.expect(std.mem.indexOf(u8, actual, "z 1 0.7432584 0.7432584 0.67 0.4384") != null);
    try testing.expect(!diagnostics.hasErrors());
    var defaults = result.spec;
    defaults.ss1_only = false;
    output.clearRetainingCapacity();
    try render.render(cx, &output, defaults, result.data, result.result);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type III SS") != null);
    const combined = try glm.parse(cx, try lex.tokenize(a, "proc glm; model y=x z / ss1 singular=.000001 noint; run;", &diagnostics));
    try testing.expect(combined.ss1_only and !combined.intercept);
    try testing.expectEqual(@as(f64, 0.000001), combined.singular);
    try testing.expectError(error.ParseError, glm.parse(cx, try lex.tokenize(a, "proc glm; model y=x / ss1=1; run;", &diagnostics)));
}

test "COMMON010 missing-cell Type I matrices are estimable and use rank increments" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try factorial(a, &lib, true);
    var diagnostics = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss1; run;");
    try testing.expectEqual(@as(usize, 3), r.result.model.fit.rank);
    try testing.expectEqual(@as(usize, 3), r.result.model.fit.df_error);
    try testing.expectApproxEqAbs(@as(f64, 6), r.result.model.fit.sse, 1e-11);
    // Cell means (2,6,10), each n=2; A2B2 is absent. Sequential data-space
    // hypotheses compare A1's two-cell average with A2B1, then A1B1 with A1B2.
    // G_i = U_i'X includes later effects, as in S154 pp.284–285.
    const u = [_][6]f64{ .{ 0.25, 0.25, 0.25, 0.25, -0.5, -0.5 }, .{ 0.5, 0.5, -0.5, -0.5, 0, 0 } };
    const expected_l = [_][4]f64{ .{ 0, 2, -1, 1 }, .{ 0, 0, 2, 2 } };
    const null_vector = [_]f64{ 1, -1, -1, 1 }; // -Intercept+A+B-AB=0
    for (u, expected_l, 0..) |contrast, expected, e| {
        var l: [4]f64 = @splat(0);
        var uy: f64 = 0;
        var norm: f64 = 0;
        for (contrast, 0..) |c, i| {
            uy += c * r.data.y[i];
            norm += c * c;
            for (0..4) |j| l[j] += c * r.data.x[i * 4 + j];
        }
        var null_product: f64 = 0;
        var lbeta: f64 = 0;
        var variance: f64 = 0;
        for (l, expected, null_vector, 0..) |value, target, null_value, j| {
            try testing.expectApproxEqAbs(target, value, 1e-12);
            null_product += value * null_value;
            lbeta += value * r.result.model.fit.coefficients[j];
            for (0..4) |k| variance += value * r.result.model.fit.covariance_unscaled[j * 4 + k] * l[k];
        }
        try testing.expectApproxEqAbs(@as(f64, 0), null_product, 1e-12);
        try testing.expectApproxEqAbs(uy, lbeta, 1e-11);
        try testing.expectApproxEqAbs(norm, variance, 1e-11);
        try testing.expectApproxEqAbs(uy * uy / norm, r.result.type_i[e].ss, 1e-11);
        try testing.expectApproxEqAbs(uy * uy / (2 * norm), r.result.type_i[e].f_value, 1e-11);
        try testing.expectEqual(@as(usize, 1), r.result.type_i[e].df);
        try testing.expectEqual(e + 2, r.result.type_i[e].rank_full);
        // H=uu'/||u||² is an idempotent rank-one projection; trace(H)=DF.
        var trace: f64 = 0;
        for (contrast, 0..) |ci, i| {
            trace += ci * ci / norm;
            for (contrast, 0..) |cj, j| {
                var h2: f64 = 0;
                for (contrast) |ck| h2 += (ci * ck / norm) * (ck * cj / norm);
                try testing.expectApproxEqAbs(contrast[i] * contrast[j] / norm, h2, 1e-12);
            }
        }
        try testing.expectApproxEqAbs(@as(f64, 1), trace, 1e-12);
    }
    try testing.expectEqual(@as(usize, 0), r.result.type_i[2].df);
    try testing.expectEqual(@as(f64, 0), r.result.type_i[2].ss);
    try testing.expect(std.math.isNan(r.result.type_i[2].f_value));
    try testing.expectApproxEqAbs(@as(f64, 64), r.result.model.fit.modelStats(true).ss_model, 1e-11);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, r.spec);
    try testing.expect(std.mem.indexOf(u8, try normalized(a, output.items), "A*B 0 0.00000000 . . .") != null);
    try testing.expect(!diagnostics.hasErrors());
    // SS1 support does not silently enable missing-cell Type III hypotheses.
    var defaults = r.spec;
    defaults.ss1_only = false;
    try testing.expectError(error.ParseError, glm.fitDesign(cx, defaults, r.data));
    try testing.expect(diagnostics.hasErrors());
    // An SS1 table does not make predictions in a missing cell estimable.
    var graphs = @import("graphics_svg.zig").Session{ .arena = a, .io = testing.io, .diags = &diagnostics, .enabled = true };
    var graph_cx = cx;
    graph_cx.graphics = &graphs;
    var graph_spec = r.spec;
    graph_spec.plots_none = false;
    try testing.expectError(error.ParseError, glm.fitDesign(graph_cx, graph_spec, r.data));
    try testing.expect(std.mem.indexOf(u8, diagnostics.list.items[diagnostics.list.items.len - 1].message, "PLOTS=NONE") != null);
}

test "COMMON010 Type I effect order changes unbalanced hypotheses but not balanced SS" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ true, false }) |missing| {
        var lib = Library.init(a);
        try factorial(a, &lib, missing);
        var diagnostics = diag.Diagnostics.init(a);
        const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &diagnostics };
        const ab = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss1; run;");
        const ba = try analyze(cx, "proc glm plots=none; class A B; model y=B A A*B / ss1; run;");
        const expected_ab = if (missing) [_]f64{ 48, 16, 0 } else [_]f64{ 128, 32, 0 };
        const expected_ba = if (missing) [_]f64{ 0, 64, 0 } else [_]f64{ 32, 128, 0 };
        var total: f64 = 0;
        for (ab.result.type_i, ba.result.type_i, expected_ab, expected_ba) |av, bv, ass, bss| {
            try testing.expectApproxEqAbs(ass, av.ss, 1e-10);
            try testing.expectApproxEqAbs(bss, bv.ss, 1e-10);
            total += av.ss;
        }
        try testing.expectApproxEqAbs(total, ab.result.model.fit.modelStats(true).ss_model, 1e-10);
        try testing.expectApproxEqAbs(ab.result.model.fit.sse, ba.result.model.fit.sse, 1e-10);
        try testing.expectEqual(@as(usize, if (missing) 0 else 1), ab.result.type_i[2].df);
    }
}
