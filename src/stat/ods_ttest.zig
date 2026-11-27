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
    // A requested name that this design does not produce must remain unmatched:
    // Capture.finish emits the SAS warning. Do not turn it into a schema gap.
    const wants_test = capture.wants("TTests") and s.options.tost == null;
    const wants_equality = capture.wants("Equality") and comparison != null;
    if (!capture.wants("Statistics") and !capture.wants("ConfLimits") and !wants_test and !wants_equality) return;
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
    // Independently calculated at 70 decimal places by
    // tests/fixtures/stat/ttest/reference.py from S154 pp.10621-10626.
    // Every cell of all four requested datasets is checked, including blank
    // strings and special ._ values. UMPU uses the mathematical solution, not
    // the three discrepant SAS upper endpoints (which remain a ticket blocker).
    fn completeOriginal(stats: *const @import("../dataset.zig").Dataset, limits: *const @import("../dataset.zig").Dataset, tests: *const @import("../dataset.zig").Dataset, equality: *const @import("../dataset.zig").Dataset) !void {
        const missing = std.math.nan(f64);
        const expected = [4][12]f64{
            .{ 6, 85.8333333333333333333, 60.7747381007815410681, 110.891928565885125599, 23.8781629667499058776, 14.9049404030893774207, 58.5639165130867311886, 14.0857023636606677238, 53.6831236977216182038, 9.74821921059317263124, 43, 116 },
            .{ 6, 93.6666666666666666667, 76.4141660403827386120, 110.919167292950594721, 16.4397891308455251325, 10.2618479309240194324, 40.3204567910959897867, 9.69781372800273567316, 36.9600975881003249106, 6.71151580825408206417, 71, 121 },
            .{ missing, -7.83333333333333333333, -34.2038270481825641533, 18.5371603815158974866, 20.4991869757477617546, 14.3231313314478429861, 35.9747109184386830223, 13.9064983423993988299, 34.5702393828515526038, 11.8352111186164407273, missing, missing },
            .{ missing, -7.83333333333333333333, -34.6661493251826518839, 18.9994826585159852172, missing, missing, missing, missing, missing, 11.8352111186164407273, missing, missing },
        };
        const classes = [_][]const u8{ "A", "B", "Diff (1-2)", "Diff (1-2)" };
        const methods = [_][]const u8{ "", "", "Pooled", "Satterthwaite" };
        const variances = [_][]const u8{ "", "", "Equal", "Unequal" };
        const limit_names = [_][]const u8{ "Variable", "Class", "Method", "Variances", "Mean", "LowerCLMean", "UpperCLMean", "StdDev", "LowerCLStdDev", "UpperCLStdDev", "UMPULowerCLStdDev", "UMPUUpperCLStdDev" };
        for (limit_names, limits.columns.items) |name, col| try std.testing.expectEqualStrings(name, col.name);
        for ([_]*const @import("../dataset.zig").Dataset{ stats, limits }, 0..) |ds, kind| {
            try std.testing.expectEqualStrings(if (kind == 0) "Statistics" else "Confidence Limits", ds.label.?);
            for (ds.columns.items, 0..) |col, j| try std.testing.expectEqual(j < 3 + kind, col.type == .char);
            for (ds.rows.items, expected, 0..) |row, ref, i| {
                try std.testing.expectEqualStrings("x", row[0].str);
                try std.testing.expectEqualStrings(classes[i], row[1].str);
                try std.testing.expectEqualStrings(methods[i], row[2].str);
                if (kind == 1) try std.testing.expectEqualStrings(variances[i], row[3].str);
                const start: usize = if (kind == 0) 0 else 1;
                const stop: usize = if (kind == 0) 12 else 9;
                for (ref[start..stop], start..) |want, j| {
                    const got = row[j + 3].num;
                    if (std.math.isNan(want)) {
                        try std.testing.expect(std.math.isNan(got));
                        try std.testing.expectEqual(@as(u8, '_'), Value.missingChar(got));
                        continue;
                    }
                    const eps = std.math.floatEps(f64);
                    var tolerance = 64 * eps * @max(1, @abs(want));
                    if (j == 5 or j == 6) {
                        // Inverting a chi-square CDF: |d sd / d p| =
                        // sd_endpoint/(2*q*f(q)). Propagate a conservative
                        // 256-ulp probability budget plus endpoint rounding.
                        // The density uses elementary half/integer gamma here,
                        // independent of the implementation's CDF and inverse.
                        const df: f64 = if (i < 2) 5 else 10;
                        const q = df * ref[4] * ref[4] / (want * want);
                        const gamma: f64 = if (i < 2) 3 * @sqrt(@as(f64, std.math.pi)) / 4 else 24;
                        const density = @exp((df / 2 - 1) * @log(q / 2) - q / 2) / (2 * gamma);
                        tolerance += want / (2 * q * density) * 256 * eps;
                    } else if (j == 7 or j == 8) tolerance = 2e-12;
                    try std.testing.expectApproxEqAbs(want, got, tolerance);
                }
            }
        }
        const test_values = [2][3]f64{
            .{ -0.661866801937460096991, 10, 0.523015130794195647269 },
            .{ -0.661866801937460096991, 8.87048094786399565111, 0.524875590267479617597 },
        };
        for (tests.rows.items, test_values, 0..) |row, ref, i| {
            try std.testing.expectEqualStrings("x", row[0].str);
            try std.testing.expectEqualStrings(methods[i + 2], row[1].str);
            try std.testing.expectEqualStrings(variances[i + 2], row[2].str);
            for (ref, row[3..]) |want, got| try std.testing.expectApproxEqAbs(want, got.num, 256 * std.math.floatEps(f64) * @max(1, @abs(want)));
        }
        const equality_names = [_][]const u8{ "Variable", "Method", "NumDF", "DenDF", "FValue", "ProbF" };
        for (equality_names, equality.columns.items, 0..) |name, col, i| {
            try std.testing.expectEqualStrings(name, col.name);
            try std.testing.expectEqual(i < 2, col.type == .char);
        }
        try std.testing.expectEqualStrings("Equality of Variances", equality.label.?);
        const row = equality.rows.items[0];
        try std.testing.expectEqualStrings("x", row[0].str);
        try std.testing.expectEqualStrings("Folded F", row[1].str);
        const eq_values = [_]f64{ 5, 5, 2.10964479526393685249, 0.432030793097767682722 };
        for (eq_values, row[2..]) |want, got| try std.testing.expectApproxEqAbs(want, got.num, 256 * std.math.floatEps(f64) * @max(1, @abs(want)));
    }
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
    try Testing.completeOriginal(stats, limits, tests, equality);
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

// S154 physical pp.10642-10644: TOST replaces TTests; Equality belongs only
// to independent two-sample or crossover designs. An ODS name with no object
// is an unmatched request, not an unsupported schema for a produced object.
test "TTEST absent objects warn without inventing datasets or schema errors" {
    const cases = [_]struct { code: []const u8, request: []const u8 }{
        .{ .code = "proc ttest data=sample; var x; run;", .request = "Equality" },
        .{ .code = "proc ttest data=sample; paired x*y; run;", .request = "Equality" },
        .{ .code = "proc ttest data=sample dist=lognormal; var x; run;", .request = "Equality" },
        .{ .code = "proc ttest data=sample tost(-100,100); paired x*y; run;", .request = "TTests" },
        .{ .code = "proc ttest data=sample dist=lognormal tost(0.1,1000); var x; run;", .request = "TTests" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var lib = @import("../exec.zig").Library.init(a);
        const ds = try Testing.sample(a);
        _ = try ds.addColumn("y", .num);
        // Supply a nonconstant paired difference so all inference paths are
        // independently valid, preserving the existing sample's two columns.
        for (ds.rows.items, 0..) |*row, i| {
            const cells = try a.alloc(Value, 3);
            @memcpy(cells[0..2], row.*);
            cells[2] = b.n(@as(f64, @floatFromInt(i + 1)));
            row.* = cells;
        }
        try lib.put("sample", ds);
        var d = diag.Diagnostics.init(a);
        var capture: ods.Capture = .{};
        const statement = try std.fmt.allocPrint(a, "ods output {s}=absent;", .{case.request});
        try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, statement, &d));
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        defer diag.resetGap();
        try tt.runTtest(cx, &out, try @import("../lexer.zig").tokenize(a, case.code, &d));
        try capture.finish(&lib, &d);
        try std.testing.expect(lib.find("absent") == null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(!diag.gapHit());
        try std.testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors() or d.warning_status));
        try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
        try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "Output '{s}' was not created. Make sure the output object is produced by the procedure.", .{case.request}), d.list.items[0].message);
    }
}

test "TTEST produced unverified paired and lognormal schemas retain D009 gaps" {
    const cases = [_]struct { code: []const u8, request: []const u8 }{
        .{ .code = "proc ttest data=sample; paired x*y; run;", .request = "Statistics" },
        .{ .code = "proc ttest data=sample dist=lognormal; var x; run;", .request = "ConfLimits" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var lib = @import("../exec.zig").Library.init(a);
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = @import("../dataset.zig").Dataset.init(a, "sample");
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("y", .num);
        for ([_][2]f64{ .{ 2, 1 }, .{ 4, 1 }, .{ 8, 2 } }) |row| try ds.appendRow(&.{ b.n(row[0]), b.n(row[1]) });
        try lib.put("sample", ds);
        var d = diag.Diagnostics.init(a);
        var capture: ods.Capture = .{};
        const statement = try std.fmt.allocPrint(a, "ods output {s}=unsupported;", .{case.request});
        try capture.parse(a, &d, try @import("../lexer.zig").tokenize(a, statement, &d));
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, tt.runTtest(cx, &out, try @import("../lexer.zig").tokenize(a, case.code, &d)));
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expect(lib.find("unsupported") == null);
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "ODS dataset schemas are not verified") != null);
    }
}
