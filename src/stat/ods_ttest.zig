//! Typed TTEST ODS producers. Listings are never parsed or rounded to create data.
//! Primary schemas: unchanged STAT-TTEST-010 SAS 9.4 M9 oracle and descriptor.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const ods = @import("../ods.zig");
const listing = @import("../ods_listing.zig");
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const fit = @import("ttest_fit.zig");
const two = @import("ttest_two_sample.zig");
const tt = @import("ttest.zig");
const decl = @import("ttest_parse.zig");
const umpu = @import("ttest_umpu.zig");
const A = std.mem.Allocator;
const absent = Value.specialMissing('_');

pub fn path(a: A, s: decl.Spec, by_index: usize, analysis: tt.Analysis) ![]const u8 {
    const variable = if (analysis.pair) |pair| try std.fmt.allocPrint(a, "{s}_{s}", .{ s.input.ds.columns.items[pair.left].name, s.input.ds.columns.items[pair.right].name }) else s.input.ds.columns.items[analysis.column].name;
    const name = try listing.pathPart(a, variable);
    return if (s.roles.by.len > 0) std.fmt.allocPrint(a, "Ttest.ByGroup{d}.{s}", .{ by_index, name }) else std.fmt.allocPrint(a, "Ttest.{s}", .{name});
}
const Row = struct {
    class: []const u8 = "",
    method: []const u8 = "",
    variances: []const u8 = "",
    n: ?usize = null,
    mean: f64,
    mean_ci: fit.Interval,
    sd: ?f64 = null,
    sd_ci: fit.Interval = .{},
    umpu_ci: fit.Interval = .{},
    se: f64,
    minimum: ?f64 = null,
    maximum: ?f64 = null,
};
fn fromSample(s: fit.Result, label: []const u8, alpha: f64) diag.Error!Row {
    return .{ .class = label, .n = s.n, .mean = s.mean, .mean_ci = s.mean_ci, .sd = s.std_dev, .sd_ci = s.std_dev_ci, .umpu_ci = try umpu.sdInterval(s.std_dev, s.df, alpha), .se = s.std_err, .minimum = s.minimum, .maximum = s.maximum };
}
fn fromComparison(c: two.Comparison, pooled: bool, alpha: f64) diag.Error!Row {
    return .{ .class = "Diff (1-2)", .method = if (pooled) "Pooled" else "Satterthwaite", .variances = if (pooled) "Equal" else "Unequal", .mean = c.estimate, .mean_ci = c.mean_ci, .sd = if (pooled) c.std_dev else null, .sd_ci = c.std_dev_ci, .umpu_ci = if (pooled) try umpu.sdInterval(c.std_dev, c.df, alpha) else .{}, .se = c.std_err };
}
fn optional(x: ?f64) Value {
    return if (x) |v| b.n(v) else absent;
}
fn make(a: A, s: decl.Spec, g: tt.Group, name: []const u8, label: []const u8) !b.Builder {
    var t = try b.Builder.init(a, s.input.ds, s.roles.by, g.representative);
    t.ds.label = label;
    try t.char("Variable", name.len);
    return t;
}
fn commonColumns(t: *b.Builder, class_len: usize, limits: bool) !void {
    if (class_len > 0) {
        try t.char("Class", class_len);
        try t.char("Method", 13);
        if (limits) try t.char("Variances", 7);
    }
}
fn addCommon(cells: *std.ArrayList(Value), a: A, variable: []const u8, row: Row, two_samples: bool, limits: bool) !void {
    try cells.append(a, b.s(variable));
    if (two_samples) {
        try cells.appendSlice(a, &.{ b.s(row.class), b.s(row.method) });
        if (limits) try cells.append(a, b.s(row.variances));
    }
}

pub fn publishNormal(cx: proc.ProcCtx, s: decl.Spec, g: tt.Group, analysis: tt.Analysis, comparison: ?two.Result) diag.Error!void {
    const capture = cx.capture orelse return;
    if (!capture.wants("Statistics") and !capture.wants("ConfLimits") and !capture.wants("TTests") and !capture.wants("Equality")) return;
    if (analysis.pair != null) return proc.failGap(cx.diags, s.line, "TTEST paired ODS dataset schemas are not verified", .{});
    const a = cx.arena;
    const name = s.input.ds.columns.items[analysis.column].name;
    const is_two = comparison != null;
    var class_len: usize = if (is_two) 10 else 0;
    if (is_two) for (analysis.classes) |c| {
        class_len = @max(class_len, c.label.len);
    };
    if (capture.wants("Statistics") or capture.wants("ConfLimits")) {
        var rows: std.ArrayList(Row) = .empty;
        if (comparison) |r| {
            try rows.append(a, try fromSample(r.samples[0], analysis.classes[0].label, s.options.alpha));
            try rows.append(a, try fromSample(r.samples[1], analysis.classes[1].label, s.options.alpha));
            try rows.append(a, try fromComparison(r.pooled, true, s.options.alpha));
            try rows.append(a, try fromComparison(r.satterthwaite, false, s.options.alpha));
        } else try rows.append(a, try fromSample(analysis.samples[0], "", s.options.alpha));
        if (capture.wants("Statistics")) {
            var t = try make(a, s, g, name, "Statistics");
            try commonColumns(&t, class_len, false);
            try t.num("N", "8.");
            for ([_][]const u8{ "Mean", "LowerCLMean", "UpperCLMean", "StdDev", "LowerCLStdDev", "UpperCLStdDev", "UMPULowerCLStdDev", "UMPUUpperCLStdDev", "StdErr", "Minimum", "Maximum" }) |col| try t.num(col, "D8.3");
            for (rows.items) |row| {
                var cells: std.ArrayList(Value) = .empty;
                try addCommon(&cells, a, name, row, is_two, false);
                try cells.appendSlice(a, &.{ if (row.n) |n| b.n(@floatFromInt(n)) else absent, b.n(row.mean), b.n(row.mean_ci.lower), b.n(row.mean_ci.upper), optional(row.sd), if (row.sd != null) b.n(row.sd_ci.lower) else absent, if (row.sd != null) b.n(row.sd_ci.upper) else absent, if (row.sd != null) b.n(row.umpu_ci.lower) else absent, if (row.sd != null) b.n(row.umpu_ci.upper) else absent, b.n(row.se), optional(row.minimum), optional(row.maximum) });
                try t.row(cells.items);
            }
            try capture.publish(a, cx.diags, "Statistics", &t.ds);
        }
        if (capture.wants("ConfLimits")) {
            var t = try make(a, s, g, name, "Confidence Limits");
            try commonColumns(&t, class_len, true);
            for ([_][]const u8{ "Mean", "LowerCLMean", "UpperCLMean", "StdDev", "LowerCLStdDev", "UpperCLStdDev", "UMPULowerCLStdDev", "UMPUUpperCLStdDev" }) |col| try t.num(col, "D8.3");
            for (rows.items) |row| {
                var cells: std.ArrayList(Value) = .empty;
                try addCommon(&cells, a, name, row, is_two, true);
                try cells.appendSlice(a, &.{ b.n(row.mean), b.n(row.mean_ci.lower), b.n(row.mean_ci.upper), optional(row.sd), if (row.sd != null) b.n(row.sd_ci.lower) else absent, if (row.sd != null) b.n(row.sd_ci.upper) else absent, if (row.sd != null) b.n(row.umpu_ci.lower) else absent, if (row.sd != null) b.n(row.umpu_ci.upper) else absent });
                try t.row(cells.items);
            }
            try capture.publish(a, cx.diags, "ConfLimits", &t.ds);
        }
    }
    if (capture.wants("TTests") and s.options.tost == null) {
        var t = try make(a, s, g, name, "T-Tests");
        if (is_two) {
            try t.char("Method", 13);
            try t.char("Variances", 7);
        }
        try t.num("tValue", "7.2");
        t.ds.setLabel("tValue", "t Value");
        try t.num("DF", "BEST6.");
        try t.num("Probt", "PVALUE6.4");
        t.ds.setLabel("Probt", switch (s.options.sides) {
            .two => "Pr > |t|",
            .upper => "Pr > t",
            .lower => "Pr < t",
        });
        if (comparison) |r| {
            try t.row(&.{ b.s(name), b.s("Pooled"), b.s("Equal"), b.n(r.pooled.t), b.n(r.pooled.df), b.n(r.pooled.p) });
            try t.row(&.{ b.s(name), b.s("Satterthwaite"), b.s("Unequal"), b.n(r.satterthwaite.t), b.n(r.satterthwaite.df), b.n(r.satterthwaite.p) });
            if (r.cochran) |c| try t.row(&.{ b.s(name), b.s("Cochran"), b.s("Unequal"), b.n(c.t), b.n(c.df), b.n(c.p) });
        } else {
            const r = analysis.samples[0];
            try t.row(&.{ b.s(name), b.n(r.t), b.n(r.df), b.n(r.p) });
        }
        try capture.publish(a, cx.diags, "TTests", &t.ds);
    }
    if (capture.wants("Equality")) if (comparison) |r| {
        var t = try make(a, s, g, name, "Equality of Variances");
        try t.char("Method", 8);
        try t.num("NumDF", "BEST6.");
        try t.num("DenDF", "BEST6.");
        try t.num("FValue", "7.2");
        t.ds.setLabel("FValue", "F Value");
        try t.num("ProbF", "PVALUE6.4");
        t.ds.setLabel("ProbF", "Pr > F");
        try t.row(&.{ b.s(name), b.s("Folded F"), b.n(r.equality.numerator_df), b.n(r.equality.denominator_df), b.n(r.equality.f), b.n(r.equality.p) });
        try capture.publish(a, cx.diags, "Equality", &t.ds);
    };
}

const Testing = struct {
    fn sample(a: A) !*@import("../dataset.zig").Dataset {
        const Dataset = @import("../dataset.zig").Dataset;
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "sample");
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("group", .char);
        for ([_]f64{ 43, 90, 84, 87, 116, 95, 86, 99, 93, 92, 121, 71 }, 0..) |x, i| try ds.appendRow(&.{ b.n(x), b.s(if (i < 6) "A" else "B") });
        return ds;
    }
};

test "TTEST ODS typed original schemas precision special missing and TRACE identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods output Statistics=stats ConfLimits=limits TTests=tests Equality=variance;", &d));
    var selection: listing.Listing = .{ .trace = &d };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture, .listing = &selection };
    var out: std.ArrayList(u8) = .empty;
    try tt.runTtest(cx, &out, try @import("../lexer.zig").tokenize(a, "proc ttest data=sample; class group; var x; run;", &d));
    try capture.finish(&lib, &d);
    const stats = lib.find("stats").?;
    const limits = lib.find("limits").?;
    const tests = lib.find("tests").?;
    const equality = lib.find("variance").?;
    try std.testing.expectEqual(@as(usize, 4), stats.rows.items.len);
    try std.testing.expectEqual(@as(usize, 15), stats.columns.items.len);
    // All Statistics names reconstructed by the independent Python verifier
    // from all three vertical header panels in the original SAS listing.
    for ([_][]const u8{ "Variable", "Class", "Method", "N", "Mean", "LowerCLMean", "UpperCLMean", "StdDev", "LowerCLStdDev", "UpperCLStdDev", "UMPULowerCLStdDev", "UMPUUpperCLStdDev", "StdErr", "Minimum", "Maximum" }, stats.columns.items) |name, col|
        try std.testing.expectEqualStrings(name, col.name);
    // Independently solved at 70 decimal digits by mpmath from the published
    // mass/moment equations (S154 pp.10621-10622), not fitted to SAS endpoints.
    // Port of dev5-precision-reference.py's 2e-12 accuracy bound. The discrepant
    // SAS upper endpoints remain a PARK blocker, not a relaxed baseline test.
    const independent = [3][2]f64{
        .{ 14.0857023636606677238079520183254, 53.6831236977216182037906490660967 },
        .{ 9.69781372800273567316032580064943, 36.9600975881003249106143239137669 },
        .{ 13.9064983423993988298985184793070, 34.5702393828515526037835190616999 },
    };
    for (independent, stats.rows.items[0..3]) |bounds, row| {
        try std.testing.expectApproxEqAbs(bounds[0], row[stats.indexOf("UMPULowerCLStdDev").?].num, 2e-12);
        try std.testing.expectApproxEqAbs(bounds[1], row[stats.indexOf("UMPUUpperCLStdDev").?].num, 2e-12);
    }
    try std.testing.expectEqual(@as(usize, 4), limits.rows.items.len);
    try std.testing.expectEqual(@as(usize, 12), limits.columns.items.len);
    try std.testing.expectEqual(@as(usize, 2), tests.rows.items.len);
    try std.testing.expectEqual(@as(usize, 6), tests.columns.items.len);
    try std.testing.expectEqual(@as(usize, 1), equality.rows.items.len);
    try std.testing.expectEqual(@as(usize, 6), equality.columns.items.len);
    const mean = stats.rows.items[0][stats.indexOf("Mean").?].num;
    try std.testing.expectApproxEqAbs(@as(f64, 515.0 / 6.0), mean, 2e-14); // exact rational mean, two rounded f64 operations
    try std.testing.expect(@abs(mean - 85.8333) > 0.00003); // never scrape the four-decimal listing
    try std.testing.expectEqual(@as(u8, '_'), Value.missingChar(stats.rows.items[2][stats.indexOf("N").?].num));
    try std.testing.expectEqual(@as(u8, '_'), Value.missingChar(stats.rows.items[3][stats.indexOf("StdDev").?].num));
    try std.testing.expectEqualStrings("T-Tests", tests.label.?);
    for ([_][]const u8{ "Variable", "Method", "Variances", "tValue", "DF", "Probt" }, tests.columns.items, [_]usize{ 1, 13, 7, 8, 8, 8 }) |name, col, len| {
        try std.testing.expectEqualStrings(name, col.name);
        try std.testing.expectEqual(@as(?usize, len), col.len);
    }
    try std.testing.expectEqualStrings("7.2", tests.columns.items[3].format.?);
    try std.testing.expectEqualStrings("t Value", tests.columns.items[3].label.?);
    try std.testing.expectEqualStrings("BEST6.", tests.columns.items[4].format.?);
    try std.testing.expectEqualStrings("PVALUE6.4", tests.columns.items[5].format.?);
    try std.testing.expectEqualStrings("Pr > |t|", tests.columns.items[5].label.?);
    const trace = try d.render();
    for ([_][]const u8{ "Statistics", "ConfLimits", "TTests", "Equality" }) |name| {
        const path_text = try std.fmt.allocPrint(a, "Path:       Ttest.x.{s}", .{name});
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, trace, path_text));
        try std.testing.expect(std.mem.indexOf(u8, trace, try std.fmt.allocPrint(a, "Template:   Stat.TTest.{s}", .{name})) != null);
    }
    try std.testing.expect(!d.hasErrors());
}

test "TTEST ODS selection and closed listing leave typed capture independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    var select: listing.Listing = .{};
    _ = try select.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods select TTests;", &d));
    try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods output Statistics=hidden TTests=shown;", &d));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture, .listing = &select };
    const code = try @import("../lexer.zig").tokenize(a, "proc ttest data=sample; class group; var x; run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try tt.runTtest(cx, &out, code);
    try capture.finish(&lib, &d);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "DF t Value") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Std Dev") == null);
    try std.testing.expectEqual(@as(usize, 4), lib.find("hidden").?.rows.items.len);
    try std.testing.expectEqual(@as(usize, 2), lib.find("shown").?.rows.items.len);
    select.open = false;
    out.clearRetainingCapacity();
    try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods output TTests=closed;", &d));
    try tt.runTtest(cx, &out, code);
    try capture.finish(&lib, &d);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 2), lib.find("closed").?.rows.items.len);
    try std.testing.expect(!d.hasErrors());
}
