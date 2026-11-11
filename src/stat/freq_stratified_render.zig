//! Typed stratified FREQ listings. All estimates/tests/weights are supplied by
//! kernels; this module never rebuilds a table or substitutes another method.
const std = @import("std");
const k = @import("freq_stratified.zig");
const risk = @import("freq_stratified_risk.zig");
const parse = @import("freq_stratified_parse.zig");
const format = @import("../format.zig");
const Error = @import("../diag.zig").Error;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
fn text(a: A, out: *Out, s: []const u8) Error!void {
    try out.appendSlice(a, s);
}
fn number(a: A, v: ?f64) Error![]const u8 {
    return if (v) |x| if (std.math.isFinite(x)) try std.fmt.allocPrint(a, "{d:.4}", .{x}) else "." else ".";
}
fn probability(a: A, v: ?f64) Error![]const u8 {
    return if (v) |x| if (std.math.isFinite(x) and x < 0.0001) "<.0001" else try number(a, x) else ".";
}
fn pad(a: A, out: *Out, s: []const u8, width: usize, right: bool) Error!void {
    const n = width - @min(width, s.len);
    if (right) try out.appendNTimes(a, ' ', n);
    try text(a, out, s);
    if (!right) try out.appendNTimes(a, ' ', n);
}
fn num(a: A, out: *Out, v: ?f64, width: usize) Error!void {
    try pad(a, out, try number(a, v), width, true);
}
fn prob(a: A, out: *Out, v: ?f64, width: usize) Error!void {
    try pad(a, out, try probability(a, v), width, true);
}
fn pair(a: A, out: *Out, label: []const u8, value: ?f64, p: bool) Error!void {
    try pad(a, out, label, 27, false);
    if (p) try prob(a, out, value, 10) else if (std.mem.eql(u8, label, "DF") and value != null) try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{value.?}), 10, true) else try num(a, out, value, 10);
    try text(a, out, "\n");
}
pub fn chiSquare(a: A, out: *Out, title: []const u8, result: ?k.Chi, restore: bool) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n", .{title}));
    if (restore) {
        try pair(a, out, "Chi-Square", if (result) |r| r.statistic else null, false);
        try pair(a, out, "DF", if (result) |r| r.df else null, false);
        try pair(a, out, "Pr > ChiSq", if (result) |r| r.p else null, true);
    } else {
        try text(a, out, "Chi-Square        DF    Pr > ChiSq\n");
        try num(a, out, if (result) |r| r.statistic else null, 10);
        try pad(a, out, if (result) |r| try std.fmt.allocPrint(a, "{d}", .{r.df}) else ".", 10, true);
        try prob(a, out, if (result) |r| r.p else null, 14);
        try text(a, out, "\n");
    }
}
pub fn ordered(a: A, out: *Out, result: ?k.Normal, is_jt: bool) Error!void {
    try text(a, out, if (is_jt) "\nJonckheere-Terpstra Test\n" else "\nCochran-Armitage Trend Test\n");
    if (is_jt) try pair(a, out, "Statistic", if (result) |r| r.statistic else null, false);
    try pair(a, out, if (is_jt) "Z" else "Statistic (Z)", if (result) |r| r.z else null, false);
    try pair(a, out, if (result != null and result.?.z > 0) "One-sided Pr > Z" else "One-sided Pr < Z", if (result) |r| r.p_one else null, true);
    try pair(a, out, "Two-sided Pr > |Z|", if (result) |r| r.p_two else null, true);
}
pub fn cmh(a: A, out: *Out, results: [3]?k.Chi, limit: u2, score_label: []const u8) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\nCochran-Mantel-Haenszel Statistics (Based on {s})\n", .{score_label}));
    try text(a, out, "Statistic    Alternative Hypothesis    DF       Value      Prob\n---------------------------------------------------------------\n");
    const labels = [_][]const u8{ "Nonzero Correlation", "Row Mean Scores Differ", "General Association" };
    for (0..limit) |i| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{i + 1}), 9, true);
        try text(a, out, "    ");
        try pad(a, out, labels[i], 25, false);
        try pad(a, out, if (results[i]) |r| try std.fmt.allocPrint(a, "{d}", .{r.df}) else ".", 2, true);
        try num(a, out, if (results[i]) |r| r.statistic else null, 12);
        try prob(a, out, if (results[i]) |r| r.p else null, 10);
        try text(a, out, "\n");
    }
}
pub const RatioRow = struct { label: []const u8, mh: ?k.Ratio, logit: ?k.Ratio, corrected: bool = false };
pub fn ratios(a: A, out: *Out, rows: []const RatioRow, alpha: f64) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\nCommon Odds Ratio and Relative Risks\nStatistic                 Method               Value    {s}% Confidence Limits\n", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}));
    var corrected = false;
    for (rows) |row| {
        inline for (.{ false, true }) |logit| {
            const r = if (logit) row.logit else row.mh;
            try pad(a, out, if (logit) "" else row.label, 26, false);
            try pad(a, out, if (logit) (if (row.corrected) "Logit **" else "Logit") else "Mantel-Haenszel", 17, false);
            try num(a, out, if (r) |v| v.value else null, 10);
            try num(a, out, if (r) |v| v.lower else null, 12);
            try num(a, out, if (r) |v| v.upper else null, 12);
            try text(a, out, "\n");
        }
        corrected = corrected or row.corrected;
    }
    if (corrected) try text(a, out, "** These logit estimators use a correction of 0.5 in every cell of affected tables.\n");
}
pub const CommonRow = struct { method: risk.Method, result: ?risk.Result };
fn methodName(method: risk.Method) []const u8 {
    return switch (method) {
        .mantel_haenszel => "Mantel-Haenszel",
        .klingenberg => "Klingenberg",
        .minimum_risk => "Minimum Risk",
        .summary_score => "Summary Score",
        .newcombe => "Newcombe",
        .newcombe_mr => "Newcombe (MR)",
    };
}
fn selected(method: risk.Method, set: parse.Methods) bool {
    return switch (method) {
        .mantel_haenszel => set.mh,
        .klingenberg => set.klingenberg,
        .minimum_risk => set.mr,
        .summary_score => set.score,
        .newcombe => set.newcombe,
        .newcombe_mr => set.newcombe_mr,
    };
}
pub fn common(a: A, out: *Out, rows: []const CommonRow, options: parse.Common, alpha: f64, column_label: []const u8) Error!void {
    const limits = options.selectedLimits();
    const tests = options.selectedTests();
    var heading = false;
    for (rows) |row| if (selected(row.method, limits)) {
        // SAS omits undefined Newcombe rows, rather than substituting Wald.
        if ((row.method == .newcombe or row.method == .newcombe_mr) and (row.result == null or row.result.?.limits.lower == null)) continue;
        if (!heading) {
            try text(a, out, try std.fmt.allocPrint(a, "\nConfidence Limits for the Common Risk Difference\nMethod                 Value       Error    {s}% Confidence Limits\n", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}));
            heading = true;
        }
        try pad(a, out, methodName(row.method), 20, false);
        try num(a, out, if (row.result) |r| r.value else null, 10);
        if (row.result != null and row.result.?.variance != null) try num(a, out, @sqrt(row.result.?.variance.?), 12) else try pad(a, out, "", 12, false);
        try num(a, out, if (row.result) |r| r.limits.lower else null, 12);
        try num(a, out, if (row.result) |r| r.limits.upper else null, 12);
        try text(a, out, "\n");
    };
    if (heading) try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n", .{column_label}));
    heading = false;
    for (rows) |row| if (selected(row.method, tests)) {
        if (!heading) {
            try text(a, out, "\nCommon Risk Difference Tests\nMethod           Risk Difference           Z    Pr > |Z|\n");
            heading = true;
        }
        try pad(a, out, methodName(row.method), 20, false);
        try num(a, out, if (row.result) |r| r.value else null, 12);
        try num(a, out, if (row.result) |r| r.z else null, 12);
        try prob(a, out, if (row.result) |r| r.p_two else null, 12);
        try text(a, out, "\n");
    };
    if (heading) try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n", .{column_label}));
}
pub const WeightRow = struct { controls: []const []const u8 = &.{}, stratum: []const u8, difference: ?f64, frequency: f64, fraction: f64, mh: ?f64 = null, mr: ?f64 = null, score_midpoint: ?f64 = null, score: ?f64 = null };
pub fn commonWeights(a: A, out: *Out, rows: []const WeightRow, selected_weights: parse.Methods) Error!void {
    return commonWeightsWithControls(a, out, rows, selected_weights, &.{});
}
pub fn commonWeightsWithControls(a: A, out: *Out, rows: []const WeightRow, selected_weights: parse.Methods, names: []const []const u8) Error!void {
    if (!selected_weights.mh and !selected_weights.mr and !selected_weights.score) return;
    try text(a, out, "\nStratum Risk Differences and Weights\n");
    try pad(a, out, "Stratum", 16, false);
    for (names) |name| try pad(a, out, name, 12, false);
    try text(a, out, " Difference   Frequency    Fraction");
    if (selected_weights.mh) try text(a, out, "   MH Weight");
    if (selected_weights.mr) try text(a, out, "   MR Weight");
    if (selected_weights.score) try text(a, out, " Score Midpoint Score Weight");
    try text(a, out, "\n");
    for (rows) |r| {
        try pad(a, out, r.stratum, 16, false);
        for (r.controls) |value| try pad(a, out, value, 12, false);
        try num(a, out, r.difference, 11);
        try pad(a, out, try format.bestNumW(a, r.frequency, 12), 12, true);
        try num(a, out, r.fraction, 12);
        if (selected_weights.mh) try num(a, out, r.mh, 12);
        if (selected_weights.mr) try num(a, out, r.mr, 12);
        if (selected_weights.score) {
            try num(a, out, r.score_midpoint, 15);
            try num(a, out, r.score, 13);
        }
        try text(a, out, "\n");
    }
}
pub fn gailSimon(a: A, out: *Out, result: ?k.GailSimon) Error!void {
    try text(a, out, "\nGail-Simon Test for Qualitative Interactions\nStatistic                              Value      Prob\n");
    const labels = [_][]const u8{ "Q+ (Positive Risk Differences)", "Q- (Negative Risk Differences)", "Q (Two-Sided)" };
    const values = [3]?f64{ if (result) |r| r.positive else null, if (result) |r| r.negative else null, if (result) |r| r.two_sided else null };
    const probs = [3]?f64{ if (result) |r| r.p_positive else null, if (result) |r| r.p_negative else null, if (result) |r| r.p_two else null };
    for (labels, values, probs) |label, v, p| {
        try pad(a, out, label, 36, false);
        try num(a, out, v, 10);
        try prob(a, out, p, 10);
        try text(a, out, "\n");
    }
}
pub fn kappa(a: A, out: *Out, title: []const u8, value: ?k.Estimate, alpha: f64, restore: bool) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n", .{title}));
    if (restore) {
        try pair(a, out, "Kappa", if (value) |v| v.value else null, false);
        try pair(a, out, "ASE", if (value) |v| @sqrt(v.variance) else null, false);
        try pair(a, out, try std.fmt.allocPrint(a, "{s}% Lower Conf Limit", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}), if (value) |v| v.lower else null, false);
        try pair(a, out, try std.fmt.allocPrint(a, "{s}% Upper Conf Limit", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}), if (value) |v| v.upper else null, false);
    } else {
        try text(a, out, try std.fmt.allocPrint(a, "Estimate       Standard Error    {s}% Confidence Limits\n", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}));
        try num(a, out, if (value) |v| v.value else null, 10);
        try num(a, out, if (value) |v| @sqrt(v.variance) else null, 19);
        try num(a, out, if (value) |v| v.lower else null, 13);
        try num(a, out, if (value) |v| v.upper else null, 13);
        try text(a, out, "\n");
    }
}
pub fn kappaTest(a: A, out: *Out, title: []const u8, result: ?k.Kappa, null_value: f64) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n", .{title}));
    try pair(a, out, "Null Value", null_value, false);
    if (null_value == 0) try pair(a, out, "H0 Std Err", if (result) |r| @sqrt(r.null_variance) else null, false);
    const test_result = if (result) |r| r.test_result else null;
    try pair(a, out, "Z", if (test_result) |t| t.z else null, false);
    try pair(a, out, if (test_result != null and test_result.?.z > 0) "Pr > Z" else "Pr < Z", if (test_result) |t| t.p_one else null, true);
    try pair(a, out, "Pr > |Z|", if (test_result) |t| t.p_two else null, true);
}
pub fn agreementDetails(a: A, out: *Out, details: k.AgreementDetails, weighted: ?k.Kappa, include_simple: bool, include_weighted: bool) Error!void {
    if (include_simple) {
        try text(a, out, "\nKappa Details\n");
        try pair(a, out, "Observed Agreement", details.observed, false);
        try pair(a, out, "Chance-Expected Agreement", details.expected, false);
        try pair(a, out, "Maximum Kappa", details.maximum_kappa, false);
        if (details.prevalence != null) {
            try pair(a, out, "Prevalence Index", details.prevalence, false);
            try pair(a, out, "Bias Index", details.bias, false);
        }
        try pair(a, out, "B_N Measure", details.bn, false);
    }
    if (include_weighted and weighted != null) {
        try text(a, out, "\nWeighted Kappa Details\n");
        try pair(a, out, "Observed Agreement", if (weighted) |w| w.observed else null, false);
        try pair(a, out, "Chance-Expected Agreement", if (weighted) |w| w.expected else null, false);
    }
}
pub fn kappaWeights(a: A, out: *Out, labels: []const []const u8, weights: []const f64) Error!void {
    if (labels.len == 0 or weights.len / labels.len != labels.len or weights.len % labels.len != 0) return error.ExecError;
    try text(a, out, "\nKappa Coefficient Weights\n");
    try pad(a, out, "", 12, false);
    for (labels) |label| try pad(a, out, label, 12, true);
    try text(a, out, "\n");
    for (labels, 0..) |label, i| {
        try pad(a, out, label, 12, false);
        for (0..labels.len) |j| try num(a, out, weights[i * labels.len + j], 12);
        try text(a, out, "\n");
    }
}

test "stratified rendering keeps SAS values missing markers and selection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: Out = .empty;
    const tables = [_]risk.Table{ .{ .cells = .{ 16, 11, 5, 20 } }, .{ .cells = .{ 12, 16, 7, 19 } } };
    const result = (try risk.commonDifference(a, &tables, .mantel_haenszel, .{ .alpha = 0.1 })).?;
    try common(a, &out, &.{.{ .method = .mantel_haenszel, .result = result }}, .{ .limits = .{ .mh = true }, .tests = .{ .mh = true } }, 0.1, "Column 1 (c = 1)");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "90% Confidence Limits") != null);
    for ([_][]const u8{ "0.2738", "0.1250", "0.4225", "3.0270", "0.0025" }) |v| try std.testing.expect(std.mem.indexOf(u8, out.items, v) != null);
    out.clearRetainingCapacity();
    try common(a, &out, &.{.{ .method = .mantel_haenszel, .result = result }}, .{ .limits = .{} }, 0.1, "Column 1");
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try ordered(a, &out, .{ .statistic = 1720.5, .z = 6.443, .p_one = 0.0000001, .p_two = 0.0000002 }, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1720.5000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "<.0001") != null);
    out.clearRetainingCapacity();
    try chiSquare(a, &out, "Cochran's Q", null, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "nan") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, ".") != null);
    out.clearRetainingCapacity();
    try kappa(a, &out, "Simple Kappa Coefficient", .{ .value = 0.3891, .variance = 0.1239 * 0.1239, .lower = 0.1463, .upper = 0.6320 }, 0.05, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "ASE") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "95% Lower Conf Limit") != null);
}

pub fn mantelFleiss(a: A, out: *Out, value: ?f64) Error!void {
    try pair(a, out, "Mantel-Fleiss Criterion", value, false);
    if (value != null and value.? < 5) try text(a, out, "WARNING: The Mantel-Fleiss criterion is less than 5.\n");
}
pub fn heterogeneity(a: A, out: *Out, value: ?k.Heterogeneity, df: ?f64, alpha: f64) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\nI-Square Measure of Heterogeneity\nI-Square      DF    {s}% Uncertainty Limits\n", .{try format.bestNumW(a, 100 * (1 - alpha), 12)}));
    if (value) |v| {
        try text(a, out, try std.fmt.allocPrint(a, "{d:.2}%", .{v.percent}));
        try pad(a, out, if (df) |d| try std.fmt.allocPrint(a, "{d}", .{d}) else ".", 8, true);
        try text(a, out, try std.fmt.allocPrint(a, "    {d:.2}%    {d:.2}%\n", .{ v.lower, v.upper }));
    } else {
        try text(a, out, "       .");
        try pad(a, out, if (df) |d| try std.fmt.allocPrint(a, "{d}", .{d}) else ".", 8, true);
        try text(a, out, "           .           .\n");
        if (df != null and df.? > 0) try text(a, out, "I-square is not computed because Q is 0.\n");
    }
}
pub fn mcnemar(a: A, out: *Out, result: ?k.Chi, null_ratio: f64, restore: bool) Error!void {
    if (null_ratio != 1) try pair(a, out, "Null Ratio", null_ratio, false);
    try chiSquare(a, out, "McNemar's Test", result, restore);
    if (result == null) try text(a, out, "NOTE: There are no discordant pairs.\n");
}

test "stratified renderer exercises typed summaries weights and agreement details" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: Out = .empty;
    const strata = [_]k.Matrix{ .{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } }, .{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } } };
    const stat = (try k.cmh(a, &strata, .correlation)).?;
    try cmh(a, &out, .{ stat, stat, stat }, 1, "Table Scores");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "8.3052") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Row Mean Scores Differ") == null);
    const mh = try k.mantelHaenszelRatios(&strata, 0.05);
    try ratios(a, &out, &.{.{ .label = "Odds Ratio", .mh = mh.odds, .logit = null, .corrected = true }}, 0.05);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "3.3132") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "correction of 0.5") != null);
    try commonWeights(a, &out, &.{.{ .stratum = "female", .difference = 0.3926, .frequency = 52, .fraction = 0.4906, .mh = 0.4905, .mr = 0.4997, .score_midpoint = 0.3738, .score = 0.5158 }}, .{ .mh = true, .mr = true, .score = true });
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.5158") != null);
    try gailSimon(a, &out, .{ .positive = 11.6027, .negative = 0, .two_sided = 0, .p_positive = 0.0011, .p_negative = 0.75, .p_two = 0.5 });
    try std.testing.expect(std.mem.indexOf(u8, out.items, "11.6027") != null);
    const m: k.Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 18, 3, 1, 7, 12, 4, 2, 9, 24 } };
    const kap = (try k.kappa(a, m, .simple, 0.05, 0)).?;
    const weighted = (try k.kappa(a, m, .cicchetti_allison, 0.05, 0)).?;
    try kappaTest(a, &out, "Test of H0: Kappa = 0", kap, 0);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "6.4731") != null);
    try agreementDetails(a, &out, (try k.agreementDetails(a, m, 0.05)).?, weighted, true, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.8868") != null);
    const weights = try k.kappaWeights(a, m, .cicchetti_allison);
    try kappaWeights(a, &out, &.{ "1", "2", "3" }, weights);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.5000") != null);
    try mantelFleiss(a, &out, 4);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "less than 5") != null);
    try heterogeneity(a, &out, .{ .percent = 32.47, .lower = 0, .upper = 76.77 }, 1, 0.05);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "76.77%") != null);
    try mcnemar(a, &out, null, 2, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "no discordant pairs") != null);
}

test "stratified fractional weights and confidence labels reuse bounded numeric format" {
    // completion_edges.sas: alpha.8 displays20%,frequency5.4; estimates/limits
    // are unchanged. Shared BEST12 preserves meaningful fractional digits.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: Out = .empty;
    const tables = [_]risk.Table{ .{ .cells = .{ 1.6, 1.1, 0.5, 2 } }, .{ .cells = .{ 1.2, 1.6, 0.7, 1.9 } } };
    const result = (try risk.commonDifference(a, &tables, .mantel_haenszel, .{ .alpha = 0.8 })).?;
    try common(a, &out, &.{.{ .method = .mantel_haenszel, .result = result }}, .{ .limits = .{ .mh = true } }, 0.8, "Column1");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "20% Confidence Limits") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.2013") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.3462") != null);
    try commonWeights(a, &out, &.{.{ .stratum = "2", .difference = 0.1593, .frequency = 1.2 + 1.6 + 0.7 + 1.9, .fraction = 0.5094, .mh = 0.5095 }}, .{ .mh = true });
    try std.testing.expect(std.mem.indexOf(u8, out.items, "         5.4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "999999") == null);
    try kappa(a, &out, "Kappa", null, 0.8, true);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "20% Lower Conf Limit") != null);
}
