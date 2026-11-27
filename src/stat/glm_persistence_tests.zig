//! Durable original-data checks, imported by GLM's default unit-test gate.
//! The corpus owns the complete programs and listings. This module ports the
//! independent arithmetic and SVG contracts previously checked by Python.
const std = @import("std");
const t = std.testing;
const A = std.mem.Allocator;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const glm = @import("glm.zig");

pub fn read(a: A, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(t.io, path, a, .limited(1 << 20));
}

// Read the literal DATALINES from the same complete source as the corpus.
// Column declarations come from its INPUT statement; no fitted output is used.
pub fn data(a: A, path: []const u8, name: []const u8, names: []const []const u8, chars: []const usize, occurrence: usize) !Dataset {
    var source = try read(a, path);
    for (0..occurrence + 1) |_| {
        const start = std.mem.indexOf(u8, source, "datalines;") orelse return error.MissingData;
        source = source[start + "datalines;".len ..];
    }
    var words = std.mem.tokenizeAny(u8, source[0..std.mem.indexOfScalar(u8, source, ';').?], " \t\r\n");
    var ds = Dataset.init(a, name);
    for (names, 0..) |n, i| _ = try ds.addColumn(n, if (std.mem.indexOfScalar(usize, chars, i) != null) .char else .num);
    const row = try a.alloc(Value, names.len);
    while (words.peek() != null) {
        for (row, 0..) |*v, i| {
            const word = words.next() orelse return error.IncompleteRow;
            v.* = if (ds.columns.items[i].type == .char) .{ .str = word } else .{ .num = try std.fmt.parseFloat(f64, word) };
        }
        try ds.appendRow(row);
    }
    return ds;
}

pub fn attribute(tag: []const u8, name: []const u8) !f64 {
    const at = std.mem.indexOf(u8, tag, name) orelse return error.MissingAttribute;
    const value = tag[at + name.len ..];
    const end = std.mem.indexOfScalar(u8, value, '"') orelse return error.MissingQuote;
    const number = try std.fmt.parseFloat(f64, value[0..end]);
    try t.expect(std.math.isFinite(number));
    return number;
}

test "persistence GLM original SVG point identities predictions and all interval metadata" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = "tests/corpus/persist_glm_glm001_documented_feature.sas";
    var exp = try data(a, path, "exp", &.{ "A", "B", "Y" }, &.{ 0, 1 }, 0);
    var iron = try data(a, path, "iron", &.{ "fe", "loss" }, &.{}, 1);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("exp", &exp);
    try lib.put("iron", &iron);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const plots = @import("glm_plots.zig");
    for ([_][]const u8{
        "proc glm data=exp; class A B; model Y=A B A*B; run;",
        "proc glm data=iron; model loss=fe fe*fe; run;",
    }, 0..) |source, kind| {
        const spec = try glm.parse(cx, try @import("../lexer.zig").tokenize(a, source, &d));
        const view = try @import("data_selection.zig").View.init(a, spec.input, .{});
        const design = try glm.design.build(cx, spec, view, spec.responses[0]);
        var fit = try glm.fitDesign(cx, spec, design);
        defer fit.deinit(a);
        const bytes = if (kind == 0) try plots.interactionSvg(a, spec, design, fit, null) else try plots.fitSvg(a, spec, design, fit, null);
        var tags = std.mem.tokenizeScalar(u8, bytes, '<');
        var observed: usize = 0;
        var intervals: usize = 0;
        const predictions = [_]f64{ 13, 13, 10, 10, 19, 19, 17 };
        while (tags.next()) |tag| {
            if (std.mem.indexOf(u8, tag, "data-kind=\"observed\"") != null) {
                const row = if (kind == 0) exp.rows.items[observed] else iron.rows.items[observed];
                try t.expectEqual(@as(f64, @floatFromInt(observed + 1)), try attribute(tag, "data-source=\""));
                try t.expectEqual(if (kind == 0) row[2].num else row[1].num, try attribute(tag, "data-y=\""));
                const x = try attribute(tag, "data-x=\"");
                if (kind == 0) {
                    try t.expectEqual(@as(f64, if (observed < 4) 0 else 1), x);
                    // Original independent Python bound: 128 binary64 eps,
                    // scaled by the exact cell mean (2,2,2,1 cell counts).
                    try t.expectApproxEqAbs(predictions[observed], try attribute(tag, "data-predicted=\""), 128 * std.math.floatEps(f64) * predictions[observed]);
                } else try t.expectEqual(row[0].num, x);
                observed += 1;
            }
            if (std.mem.indexOf(u8, tag, "data-lclm=\"") != null) {
                var last = -std.math.inf(f64);
                for ([_][]const u8{ "data-lcli=\"", "data-lclm=\"", "data-predicted=\"", "data-uclm=\"", "data-ucli=\"" }) |attr| {
                    const v = try attribute(tag, attr);
                    try t.expect(v >= last);
                    last = v;
                }
                intervals += 1;
            }
        }
        try t.expectEqual(@as(usize, if (kind == 0) 7 else 13), observed);
        try t.expectEqual(@as(usize, if (kind == 0) 0 else 101), intervals);
        if (kind == 0) try t.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "data-kind=\"group-fit\""));
    }
    const scatter = try @import("sgscatter.zig").render(a, &d, .{ .ds = &iron, .x = 0, .y = 1 }, null);
    var tags = std.mem.tokenizeScalar(u8, scatter, '<');
    var n: usize = 0;
    while (tags.next()) |tag| if (std.mem.indexOf(u8, tag, "class=\"point\"") != null) {
        try t.expectEqual(iron.rows.items[n][0].num, try attribute(tag, "data-x=\""));
        try t.expectEqual(iron.rows.items[n][1].num, try attribute(tag, "data-y=\""));
        n += 1;
    };
    try t.expectEqual(@as(usize, 13), n);
    try t.expectEqualStrings("", try d.render());
}

test "persistence COMMON010 011 012 independent exact rational SS and F on original data" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try data(a, "tests/corpus/persist_glm_common010_unbalanced_sums_of_squares.sas", "sample", &.{ "x", "z", "y", "group", "weight", "freq" }, &.{3}, 0);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try glm.parse(cx, try @import("../lexer.zig").tokenize(a, "proc glm; class group; model y=group x z / ss1 ss2 ss3 ss4; run;", &d));
    const view = try @import("data_selection.zig").View.init(a, spec.input, .{});
    const design = try glm.design.build(cx, spec, view, spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, design);
    defer fit.deinit(a);
    // Exact normal-equation fractions from the independent Python verifier.
    // Full SSE=2387/267; nested sequential SSE differences and drop-one
    // differences are distinct. No production fit generated these references.
    const sequential = [_]f64{ 5929.0 / 12.0, 2023.0 / 20.0, 1323.0 / 1780.0 };
    const conditional = [_]f64{ 1243256.0 / 393825.0, 147175.0 / 1958.0, 1323.0 / 1780.0 };
    const mse = 2387.0 / 2136.0;
    try t.expectApproxEqAbs(mse, fit.model.fit.mse, 1e-12);
    for ([_][]const @import("glm_fit.zig").EffectTest{ fit.type_i, fit.type_ii, fit.type_iii, fit.type_iv }, 0..) |table, i| {
        try t.expectEqual(@as(usize, 3), table.len);
        for (table, if (i == 0) sequential else conditional) |effect, ss| {
            try t.expectEqual(@as(usize, 1), effect.df);
            // 4096 eps times scale bounds arithmetic/conditioning of this
            // twelve-row full-rank fixture; far tighter than printed digits.
            try t.expectApproxEqAbs(ss, effect.ss, 4096 * std.math.floatEps(f64) * @max(1, ss));
            try t.expectApproxEqAbs(ss, effect.ms, 4096 * std.math.floatEps(f64) * @max(1, ss));
            try t.expectApproxEqAbs(ss / mse, effect.f_value, 4096 * std.math.floatEps(f64) * @max(1, ss / mse));
        }
    }
}
