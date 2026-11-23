//! SAS ODS PearsonCorr and SimpleStats schemas over CORR's typed Result.
const std = @import("std");
const corr = @import("corr.zig");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
pub fn publish(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, result: corr.Result) diag.Error!void {
    const spec = result.spec;
    if (spec.options.noprint) return;
    try validateMode(d, capture, spec);
    for (result.groups) |group| {
        var label_len: usize = 0;
        var name_len: usize = 1;
        for (group.simple) |v| {
            const c = spec.ds.columns.items[v.column];
            if (c.label) |label| label_len = @max(label_len, label.len);
            name_len = @max(name_len, c.name.len);
        }
        if (!spec.options.nosimple and capture.wants("SimpleStats")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Simple Statistics";
            try t.char("Variable", @max(8, name_len));
            for ([_][]const u8{ "NObs", "Mean", "StdDev", "Sum", "Min", "Max" }, 0..) |name, i| try t.num(name, if (i == 0) "8." else "D10.");
            t.ds.setLabel("NObs", "N");
            t.ds.setLabel("StdDev", "Std Dev");
            t.ds.setLabel("Min", "Minimum");
            t.ds.setLabel("Max", "Maximum");
            if (label_len > 0) try t.char("Label", label_len);
            for (group.simple) |v| {
                const c = spec.ds.columns.items[v.column];
                var cells = [_]Value{ b.s(c.name), b.n(v.n), b.n(v.mean), b.n(v.stddev), b.n(v.sum), b.n(v.minimum), b.n(v.maximum), b.s(c.label orelse "") };
                try t.row(cells[0..if (label_len > 0) 8 else 7]);
            }
            try capture.publish(a, d, "SimpleStats", &t.ds);
        }
        if (group.polychoric.len > 0 and capture.wants("PolychoricCorr")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Polychoric Correlations";
            try t.char("Var", @max(8, name_len));
            try t.char("WithVar", @max(8, name_len));
            t.ds.setLabel("Var", "Variable");
            t.ds.setLabel("WithVar", "With Variable");
            // M9 includes the two ordinal tests in this object under NOPROB
            // and NOCORR as well. The names, widths and labels are from CONTENTS.
            for ([_][]const u8{ "NObs", "Corr", "StdErr", "WaldChiSq", "ProbWaldChiSq", "LRChiSq", "ProbLRChiSq" }, [_][]const u8{ "8.", "D10.", "D10.", "10.4", "PVALUE6.4", "10.4", "PVALUE6.4" }, [_][]const u8{ "N", "Polychoric Correlation", "Standard Error", "Chi-Square", "Pr > ChiSq", "Chi-Square", "Pr > ChiSq" }) |name, fmt, label| {
                try t.num(name, fmt);
                t.ds.setLabel(name, label);
            }
            for (group.polychoric) |entry| {
                // Without WITH, the leading variable is the first VAR in the
                // pair. With WITH, Var and WithVar follow their statements.
                const v = if (spec.with.len == 0) entry.row else entry.column;
                const w = if (spec.with.len == 0) entry.column else entry.row;
                const e = entry.estimate;
                try t.row(&.{ b.s(spec.ds.columns.items[v].name), b.s(spec.ds.columns.items[w].name), b.n(e.n), b.n(e.r), b.n(e.se), b.n(e.wald), b.n(e.p), b.n(e.lr), b.n(e.lr_p) });
            }
            try capture.publish(a, d, "PolychoricCorr", &t.ds);
        }
        if (spec.options.pearson and !spec.options.nocorr and capture.wants("PearsonCorr"))
            try publishMatrix(a, d, capture, spec, group, group.pairs, name_len, label_len, "PearsonCorr", "Pearson Correlations");
        if (spec.partial.len == 0) {
            if (group.spearman.len > 0 and capture.wants("SpearmanCorr"))
                try publishMatrix(a, d, capture, spec, group, group.spearman, name_len, label_len, "SpearmanCorr", "Spearman Correlations");
            if (group.kendall.len > 0 and capture.wants("KendallCorr"))
                try publishMatrix(a, d, capture, spec, group, group.kendall, name_len, label_len, "KendallCorr", "Kendall Correlations");
        }
    }
}
fn publishMatrix(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group, matrix: []const corr.Pair, name_len: usize, label_len: usize, name: []const u8, label: []const u8) diag.Error!void {
    var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
    t.ds.label = label;
    try t.char("Variable", name_len);
    if (label_len > 0) try t.char("Label", label_len);
    var different_n = false;
    for (matrix) |p| if (p.n != matrix[0].n) {
        different_n = true;
    };
    for (spec.vars) |ci| try t.num(spec.ds.columns.items[ci].name, "8.5");
    if (!spec.options.noprob) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "P{s}", .{spec.ds.columns.items[ci].name}), "PVALUE8.4");
    if (different_n) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "N{s}", .{spec.ds.columns.items[ci].name}), "8.");
    const rows = if (spec.with.len > 0) spec.with else spec.vars;
    for (rows, 0..) |ri, row| {
        var cells: std.ArrayList(Value) = .empty;
        try cells.append(a, b.s(spec.ds.columns.items[ri].name));
        if (label_len > 0) try cells.append(a, b.s(spec.ds.columns.items[ri].label orelse ""));
        const pairs = matrix[row * spec.vars.len ..][0..spec.vars.len];
        for (pairs) |p| try cells.append(a, b.n(p.r));
        if (!spec.options.noprob) for (pairs) |p| try cells.append(a, if (p.row == p.column) Value.specialMissing('_') else b.n(p.p));
        if (different_n) for (pairs) |p| try cells.append(a, b.n(p.n));
        try t.row(cells.items);
    }
    try capture.publish(a, d, name, &t.ds);
}
// The advanced producer is landing independently. Do not interpret its partial
// pairs or rank-specific SimpleStats schema as the ordinary Pearson objects.
// The compile-time field checks also preserve the pre-advanced Result contract.
fn validateMode(d: *diag.Diagnostics, capture: *const ods.Capture, spec: anytype) diag.Error!void {
    if (!capture.wants("PearsonCorr") and !capture.wants("SimpleStats")) return;
    if (@hasField(@TypeOf(spec), "partial")) if (spec.partial.len > 0) {
        diag.markGap();
        return d.fail(error.ParseError, 0, "ODS OUTPUT: partial CORR table schemas are not supported", .{});
    };
    inline for (.{ "spearman", "kendall", "hoeffding" }) |field| {
        if (@hasField(@TypeOf(spec.options), field)) if (@field(spec.options, field)) {
            diag.markGap();
            return d.fail(error.ParseError, 0, "ODS OUTPUT: rank CORR table schemas are not supported", .{});
        };
    }
    inline for (.{ "polychoric", "polyserial" }) |field| {
        if (@hasField(@TypeOf(spec.options), field)) if (@field(spec.options, field) != null) {
            diag.markGap();
            return d.fail(error.ParseError, 0, "ODS OUTPUT: ordinal CORR table schemas are not supported", .{});
        };
    }
}

test "FEAT-odsoutput richer CORR producers cannot mislabel captured tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods output PearsonCorr=p SimpleStats=s;", &d));
    try std.testing.expectError(error.ParseError, validateMode(&d, &capture, .{ .options = .{}, .partial = &[_]usize{1} }));
    try std.testing.expectError(error.ParseError, validateMode(&d, &capture, .{ .options = .{ .spearman = true } }));
    try std.testing.expectError(error.ParseError, validateMode(&d, &capture, .{ .options = .{ .polychoric = @as(?u8, 1) } }));
    try std.testing.expect(d.hasErrors());
}

test "M9 ODS multiple rank matrices route method-specific p-values and diagonal missing codes" {
    // SAS M9 ods_multiple_rank_tables. The two 2x5 objects share a schema.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Dataset = @import("../dataset.zig").Dataset;
    const lex = @import("../lexer.zig");
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][2]f64{ .{ 1, 8 }, .{ 2, 6 }, .{ 2, 6 }, .{ 3, 2 }, .{ 4, 5 }, .{ 5, 3 }, .{ 6, 1 }, .{ 8, 4 }, .{ 9, 1 } }) |xy|
        try ds.appendRow(&.{ .{ .num = xy[0] }, .{ .num = xy[1] } });
    try lib.put(ds.name, ds);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output SpearmanCorr=s KendallCorr=k;", &d));
    var listing: std.ArrayList(u8) = .empty;
    try corr.run(.{ .arena = a, .diags = &d, .lib = &lib, .capture = &capture }, &listing, try lex.tokenize(a, "proc corr data=sample spearman kendall;var x y;run;", &d));
    try capture.finish(&lib, &d);
    for ([_][]const u8{ "s", "k" }, [_]f64{ -0.81857, -0.69573 }, [_]f64{ 0.0070, 0.0110 }) |name, coef, p| {
        const rs = lib.find(name).?;
        try std.testing.expectEqual(@as(usize, 2), rs.rowCount());
        try std.testing.expectEqual(@as(usize, 5), rs.columns.items.len);
        for ([_][]const u8{ "Variable", "x", "y", "Px", "Py" }, rs.columns.items) |expected, column| try std.testing.expectEqualStrings(expected, column.name);
        try std.testing.expectApproxEqAbs(coef, rs.row(0)[2].num, 0.000005);
        try std.testing.expectApproxEqAbs(p, rs.row(0)[4].num, 0.00005);
        try std.testing.expectEqual(Value.missingRank(Value.specialMissing('_').num), Value.missingRank(rs.row(0)[3].num));
    }
}

test "PolychoricCorr captures named full-precision ordinal pairs and native descriptors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 0, 0, 110 }, .{ 0, 1, 352 }, .{ 10, 1, 418 }, .{ 20, 1, 110 } }) |v| try ds.appendRow(&.{ b.n(v[0]), b.n(v[1]), b.n(v[2]) });
    try lib.put("d", &ds);
    const lexer = @import("../lexer.zig");
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "proc corr data=d polychoric(converge=1e-6) noprob;var x;with y;freq f;run;", "proc corr data=d polychoric(converge=1e-6) nocorr;var x y;freq f;run;" }) |source| {
        try capture.parse(a, &d, try lexer.tokenize(a, "ods output PolychoricCorr=fit;", &d));
        try corr.run(cx, &listing, try lexer.tokenize(a, source, &d));
        try capture.finish(&lib, &d);
        const fit = lib.find("fit").?;
        try std.testing.expectEqual(@as(usize, 9), fit.columns.items.len);
        try std.testing.expectEqual(@as(usize, 1), fit.rowCount());
        const row = fit.row(0);
        try std.testing.expectEqualStrings("x", row[fit.indexOf("Var").?].str);
        try std.testing.expectEqualStrings("y", row[fit.indexOf("WithVar").?].str);
        try std.testing.expectEqual(@as(?usize, 8), fit.columns.items[0].len);
        try std.testing.expectEqualStrings("D10.", fit.columns.items[3].format.?);
        try std.testing.expectEqualStrings("Polychoric Correlation", fit.columns.items[3].label.?);
        try std.testing.expectEqualStrings("PVALUE6.4", fit.columns.items[8].format.?);
        try std.testing.expectEqual(@as(f64, 990), row[2].num);
        try std.testing.expectApproxEqAbs(@as(f64, 0.98771303566856), row[3].num, 5e-8);
        try std.testing.expectEqual(@as(f64, 0), row[4].num);
        try std.testing.expect(row[5].isMissing() and row[6].isMissing());
        try std.testing.expectApproxEqAbs(@as(f64, 183.527618505065), row[7].num, 1e-7);
        try std.testing.expectApproxEqRel(@as(f64, 8.2269409306717e-42), row[8].num, 1e-7);
    }
}
