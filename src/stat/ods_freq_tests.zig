//! Capture cells computed by FREQ's asymptotic test kernels.
const std = @import("std");
const b = @import("ods_table.zig");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const freq = @import("freq.zig");
const model = @import("freq_table.zig");
const stats = @import("freq_tests.zig");
const execute = @import("freq_tests_execute.zig");
const A = std.mem.Allocator;

pub fn levels(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, names: []const []const u8, totals: []const usize, misses: []const usize) !void {
    if (!capture.wants("NLevels") or names.len == 0) return;
    var table = try b.Builder.init(a, source, by, rep);
    table.ds.label = "Number of Variable Levels";
    var name_width: usize = 1;
    var label_width: usize = 0;
    for (names) |name| {
        const column = source.columns.items[source.indexOf(name).?];
        name_width = @max(name_width, column.name.len);
        if (column.label) |label| label_width = @max(label_width, label.len);
    }
    try table.char("TableVar", name_width);
    table.ds.setLabel("TableVar", "Table Variable");
    if (label_width > 0) {
        try table.char("TableVarLabel", label_width);
        table.ds.setLabel("TableVarLabel", "Table Variable Label");
    }
    for ([_][]const u8{ "NLevels", "NMissLevels", "NNonMissLevels" }, [_][]const u8{ "Number of Levels", "Number of Missing Levels", "Number of Nonmissing Levels" }) |field, label| {
        try table.num(field, "BEST8.");
        table.ds.setLabel(field, label);
    }
    for (names, totals, misses) |name, total, missing| {
        const column = source.columns.items[source.indexOf(name).?];
        var cells: std.ArrayList(Value) = .empty;
        try cells.append(a, b.s(column.name));
        if (label_width > 0) try cells.append(a, b.s(column.label orelse ""));
        try cells.appendSlice(a, &.{ b.n(@floatFromInt(total)), b.n(@floatFromInt(missing)), b.n(@floatFromInt(total - missing)) });
        try table.row(cells.items);
    }
    try capture.publish(a, d, "NLevels", &table.ds);
}

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, number: usize, req: freq.Request, report: execute.Report) !void {
    const nd = tab.dimensions.len;
    if (report.goodness_of_fit) |gof| {
        const title = try std.fmt.allocPrint(a, "Table {s}", .{tab.dimensions[0].name});
        for ([_]bool{ false, true }) |likelihood| {
            const name = if (likelihood) "OneWayLRChiSq" else "OneWayChiSq";
            if (!capture.wants(name) or (likelihood and !req.statistics.lrchi)) continue;
            if (req.exact.families.contains(if (likelihood) .lrchi else .pchi))
                return @import("../proc.zig").failGap(d, 0, "PROC FREQ: exact rows of ODS OUTPUT {s} are not implemented", .{name});
            const test_result = if (likelihood) gof.likelihood_ratio else gof.pearson;
            var table = try b.Builder.init(a, source, by, rep);
            table.ds.label = if (likelihood) "One-Way Likelihood Ratio Chi-Square Test" else "One-Way Chi-Square Test";
            try table.char("Table", 256);
            try table.char("Name1", if (likelihood) 8 else 7);
            try table.char("Label1", 10);
            const codes = if (likelihood) [_][]const u8{ "_LRCHI_", "DF_LRCHI", "P_LRCHI" } else [_][]const u8{ "_PCHI_", "DF_PCHI", "P_PCHI" };
            const labels = [_][]const u8{ "Chi-Square", "DF", "Pr > ChiSq" };
            const values = [_]f64{ test_result.statistic, test_result.df, test_result.p };
            const formatted = [_][]const u8{
                std.mem.trim(u8, try @import("../format.zig").apply(a, b.n(values[0]), "10.4"), " "),
                std.mem.trim(u8, try @import("../format.zig").apply(a, b.n(values[1]), "BEST8."), " "),
                std.mem.trim(u8, try @import("../format.zig").apply(a, b.n(values[2]), "PVALUE6.4"), " "),
            };
            var width: usize = 1;
            for (formatted) |s| width = @max(width, s.len);
            try table.char("cValue1", width);
            try table.num("nValue1", "D12.3");
            const show_warn = !likelihood and report.warning != null;
            if (show_warn) try table.num("Warning", "1.");
            for (codes, labels, values, formatted) |code, label, value, rendered| {
                const row = [_]Value{ b.s(title), b.s(code), b.s(label), b.s(rendered), b.n(value), b.n(if (report.warning orelse false) 1 else 0) };
                try table.row(row[0..if (show_warn) 6 else 5]);
            }
            try capture.publish(a, d, name, &table.ds);
        }
    }
    const chi = report.chi_square orelse return;
    if (!capture.wants("ChiSq")) return;
    const r = tab.dimensions[nd - 2].name;
    const c = tab.dimensions[nd - 1].name;
    const title = if (nd > 2) try std.fmt.allocPrint(a, "Table {d} of {s} * {s}", .{ number, r, c }) else try std.fmt.allocPrint(a, "Table {s} * {s}", .{ r, c });
    var table = try b.Builder.init(a, source, by, rep);
    table.ds.label = "Chi-Square Tests";
    try table.char("Table", 256);
    try table.char("Statistic", 28);
    try table.num("DF", "2.");
    try table.num("Value", "10.4");
    try table.num("Prob", "PVALUE6.4");
    if (report.warning != null) {
        try table.num("Warning", "BEST8.");
        table.ds.setLabel("Warning", "Chi-Square Warning");
    }
    const mh_label = switch (req.statistics.score_type) {
        .table => "Mantel-Haenszel Chi-Square",
        .rank => "MH Chi-Square (Rank Scores)",
        .ridit => "MH Chi-Square (Ridit Scores)",
        .modridit => "MH Chi-Square (Mod. Ridits)",
    };
    for ([_][]const u8{ "Chi-Square", "Likelihood Ratio Chi-Square", "Continuity Adj. Chi-Square", mh_label }, [_]?stats.Test{ chi.pearson, chi.likelihood_ratio, chi.continuity, chi.mantel_haenszel }, 0..) |label, maybe, i| {
        const t = maybe orelse continue;
        const row = [_]Value{ b.s(title), b.s(label), b.n(t.df), b.n(t.statistic), b.n(t.p), b.n(if (i == 0 and (report.warning orelse false)) 1 else 0) };
        try table.row(row[0..if (report.warning != null) 6 else 5]);
    }
    const absent = Value.specialMissing('_');
    for ([_][]const u8{ "Phi Coefficient", "Contingency Coefficient", "Cramer's V" }, [_]f64{ chi.phi, chi.contingency, chi.cramer_v }) |label, value| {
        const row = [_]Value{ b.s(title), b.s(label), absent, b.n(value), absent, b.n(0) };
        try table.row(row[0..if (report.warning != null) 6 else 5]);
    }
    try capture.publish(a, d, "ChiSq", &table.ds);
}

test "FREQ ODS keeps BY missing levels and Chi-square footnotes and list margins typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var capture: ods.Capture = .{};
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("site", .char);
    for ([_][]const u8{ "row", "col", "w" }) |s| _ = try ds.addColumn(s, .num);
    ds.setLabel("row", "A labeled row");
    ds.setLabel("site", "Study site");
    ds.setFormat("site", "$char1.");
    ds.setInformat("site", "$char1.");
    const nan = std.math.nan(f64);
    for ([_][3]f64{ .{ nan, 1, 2 }, .{ 1, 1, 1 }, .{ 1, 2, 5 }, .{ 2, 1, 7 }, .{ 2, 2, 3 }, .{ 1, nan, 1 }, .{ 1, 1, 6 }, .{ 1, 2, 9 }, .{ 2, 1, 13 }, .{ 2, 2, 4 } }, 0..) |r, i| try ds.appendRow(&.{ b.s(if (i < 5) "A" else "B"), b.n(r[0]), b.n(r[1]), b.n(r[2]) });
    try lib.put("d", &ds);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
    var out: std.ArrayList(u8) = .empty;
    try capture.parse(a, &d, try lex.tokenize(a, "ods output NLevels=n ChiSq=c;", &d));
    try freq.runFreq(cx, &out, try lex.tokenize(a, "proc freq data=d nlevels;by site;tables row*col / chisq(warn=output);weight w;run;", &d));
    try capture.finish(&lib, &d);
    const n = lib.find("n").?;
    try std.testing.expectEqual(@as(usize, 4), n.rowCount());
    try std.testing.expectEqualStrings("Study site", n.columns.items[0].label.?);
    try std.testing.expectEqualStrings("$CHAR1.", n.columns.items[0].format.?);
    try std.testing.expect(n.columns.items[0].informat == null);
    try std.testing.expectEqualStrings("A labeled row", n.row(0)[n.indexOf("TableVarLabel").?].str);
    try std.testing.expectEqual(@as(f64, 1), n.row(0)[n.indexOf("NMissLevels").?].num);
    const c = lib.find("c").?;
    try std.testing.expectEqual(@as(usize, 14), c.rowCount());
    try std.testing.expectEqual(@as(f64, 1), c.row(0)[c.indexOf("Warning").?].num);
    try std.testing.expectEqual(@as(f64, 0), c.row(1)[c.indexOf("Warning").?].num);
    try std.testing.expectEqual(Value.missingRank(Value.specialMissing('_').num), Value.missingRank(c.row(4)[c.indexOf("DF").?].num));
    try capture.parse(a, &d, try lex.tokenize(a, "ods output List=l CrossList=t;", &d));
    try freq.runFreq(cx, &out, try lex.tokenize(a, "proc freq data=d;tables site*row*col /list line;tables row*col /crosslist(stdres pearsonres) nofreq;weight w;run;", &d));
    try capture.finish(&lib, &d);
    const l = lib.find("l").?;
    try std.testing.expectEqual(@as(usize, 8), l.rowCount());
    try std.testing.expectEqual(@as(f64, 8), l.row(7)[l.indexOf("Line").?].num);
    const t = lib.find("t").?;
    try std.testing.expectEqual(@as(usize, 9), t.rowCount());
    try std.testing.expect(t.indexOf("Frequency") == null);
    try std.testing.expectEqualStrings("Total", t.row(2)[t.indexOf("F_col").?].str);
    try std.testing.expectEqual(@as(f64, 3), t.row(8)[t.indexOf("Missing").?].num);
    try std.testing.expectEqual(Value.missingRank(Value.specialMissing('_').num), Value.missingRank(t.row(8)[t.indexOf("StdResidual").?].num));
}
