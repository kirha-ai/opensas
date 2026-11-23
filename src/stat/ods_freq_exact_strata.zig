//! Exact multiway inference combines the same observed strata used by FREQ
//! for its Mantel-Haenszel estimates and Breslow-Day test.
const std = @import("std");
const A = std.mem.Allocator;
const diag = @import("../diag.zig");
const ods = @import("../ods.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const Rows = @import("ods_freq_exact_rows.zig").Rows;
const parse = @import("freq_exact_parse.zig");
const joint = @import("freq_exact_strata.zig");
const strat = @import("freq_stratified_execute.zig");
pub const Results = struct { common: ?joint.Common = null, zelen: ?joint.Zelen = null };

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, title: []const u8, asym: strat.Report, tests: Results, alpha: f64, opt: parse.Options) diag.Error!void {
    if (tests.common) |r| {
        if (capture.wants("CommonOddsRatioCL")) {
            var t = try b.Builder.init(a, source, by, rep);
            t.ds.label = "Exact Confidence Limits for the Common Odds Ratio";
            const mh = if (asym.ratios.len > 0) asym.ratios[0].mh else null;
            try @import("ods_freq_risk.zig").ratioLimits(a, &t, title, "Mantel-Haenszel Estimate", "MHOR", "COMOR", alpha, if (mh) |v| v.value else null, if (mh) |v| .{ .lower = v.lower, .upper = v.upper } else .{}, r.limits);
            try capture.publish(a, d, "CommonOddsRatioCL", &t.ds);
        }
        if (capture.wants("CommonOddsRatioTest")) {
            var t = try b.Builder.init(a, source, by, rep);
            t.ds.label = "Exact Test of H0: Common Odds Ratio = 1";
            try t.char("Table", 256);
            var rows = try Rows.init(a, &t, title, opt.pformat, 10);
            const sum: f64 = @floatFromInt(r.observed);
            const right = sum > r.expected;
            try rows.number("S_COMOR", "Cell (1,1) Sum (S)", sum, "10.4");
            try rows.number("M0_COMOR", "Mean of S under H0", r.expected, "10.4");
            try rows.add("", "", "", null);
            try rows.probability(if (right) "XPR_COMOR" else "XPL_COMOR", if (right) "One-sided Pr >=  S" else "One-sided Pr <=  S", r.one_sided);
            try rows.probability("XPT_COMOR", "Point     Pr  =  S", r.point);
            if (opt.midp) try rows.probability("XMP_COMOR", "Mid p-Value", @max(0, r.one_sided - r.point / 2));
            try rows.add("", "", "", null);
            try rows.add("", "Two-sided P-values", "", null);
            try rows.probability("XP2A_COMOR", "2 * One-sided", r.two_doubled);
            try rows.probability("XP2B_COMOR", "Sum <= Point", r.two_probability);
            try rows.probability("XP2C_COMOR", "Pr >= |S - Mean|", r.two_distance);
            rows.finish();
            try capture.publish(a, d, "CommonOddsRatioTest", &t.ds);
        }
    }
    if (tests.zelen) |r| {
        if (!capture.wants("EqualOddsRatios")) return;
        var t = try b.Builder.init(a, source, by, rep);
        t.ds.label = "Tests for Equal Odds Ratios";
        try t.char("Table", 256);
        var rows = try Rows.init(a, &t, title, opt.pformat, 1);
        if (asym.breslow_day) |bd| {
            const chi = bd.unadjusted;
            try rows.number("_BDCHI_", "Breslow-Day Chi-Square", chi.statistic, "6.4");
            try rows.number("DF_BDCHI", "DF", chi.df, "best12.");
            try rows.add("P_BDCHI", "Pr > ChiSq", try @import("freq_exact_render.zig").probability(a, chi.p, .default), chi.p);
            try rows.add("", "", "", null);
        }
        try rows.probability("_EQOR_", "Zelen's Exact Test (P)", r.point);
        try rows.probability("XP_EQOR", "Exact Pr <= P", r.p);
        rows.finish();
        try capture.publish(a, d, "EqualOddsRatios", &t.ds);
    }
}

test "common odds and Zelen ODS expose distinct conditional distributions under POINT and MIDP" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    var library = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const input = try a.create(Dataset);
    input.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "r", "c", "w" }) |name| _ = try input.addColumn(name, .num);
    for (1..3) |g| for (1..3) |row| for (1..3) |col| {
        const count = 1 + (2 * row + col + g * row * col) % 4;
        try input.appendRow(&.{ b.n(@floatFromInt(g)), b.n(@floatFromInt(row)), b.n(@floatFromInt(col)), b.n(@floatFromInt(count)) });
    };
    try library.put(input.name, input);
    var capture: ods.Capture = .{};
    var listing: std.ArrayList(u8) = .empty;
    try capture.parse(a, &diagnostics, try lex.tokenize(a, "ods output CommonOddsRatioCL=limits CommonOddsRatioTest=common EqualOddsRatios=zelen;", &diagnostics));
    try @import("freq.zig").runFreq(.{ .arena = a, .lib = &library, .diags = &diagnostics, .capture = &capture }, &listing, try lex.tokenize(a, "proc freq data=sample;tables g*r*c;weight w;exact comor eqor / point midp pformat=8.6;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    const common = library.find("common").?;
    try std.testing.expectEqual(@as(usize, 11), common.rowCount());
    try std.testing.expectEqualStrings("Summary for r * c", common.row(0)[0].str);
    try std.testing.expectEqualStrings("XMP_COMOR", common.row(5)[1].str);
    try std.testing.expectEqualStrings("0.396645", common.row(5)[3].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.39664502164502), common.row(5)[4].num, 1e-12);
    const limits = library.find("limits").?;
    try std.testing.expectEqualStrings("XU_COMOR", limits.row(8)[1].str);
    // Independent convolution of the two hypergeometric weights gives
    // [60,760,3360,6300,5460,2160,360,20]. Its left-tail .025 root is
    // 6.5499652083319966; the finite-precision M9 root is 6.54996520953192.
    try std.testing.expectApproxEqAbs(@as(f64, 6.5499652083319966), limits.row(8)[4].num, 1e-13);
    try std.testing.expectEqualStrings("6.5500", limits.row(8)[3].str);
    const zelen = library.find("zelen").?;
    try std.testing.expectEqualStrings("XP_EQOR", zelen.row(5)[1].str);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0 / 7.0), zelen.row(5)[4].num, 1e-12);
    try std.testing.expect(!diagnostics.hasErrors());
}
