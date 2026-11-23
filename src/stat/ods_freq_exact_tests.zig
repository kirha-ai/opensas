//! Fisher and conditional chi-square ODS tables. Monte Carlo requests retain
//! the observed statistic alongside the independently published sample estimates.
const std = @import("std");
const A = std.mem.Allocator;
const diag = @import("../diag.zig");
const ods = @import("../ods.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const Rows = @import("ods_freq_exact_rows.zig").Rows;
const public = @import("freq_exact_public.zig");
const parse = @import("freq_exact_parse.zig");
const dist = @import("freq_exact_distribution.zig");
const k = @import("freq_tests.zig");
const render = @import("freq_exact_render.zig");
const model = @import("freq_table.zig");

fn fisherRows(rows: *Rows, result: render.Fisher, opt: parse.Options) !void {
    if (result.first_cell) |f| {
        try rows.integer("Cell1_FREQ", "Cell (1,1) Frequency (F)", f);
        try rows.probability("XPL_FISH", "Left-sided Pr <= F", result.left.?);
        try rows.probability("XPR_FISH", "Right-sided Pr >= F", result.right.?);
        try rows.add("", "", "", null);
    }
    try rows.probability("P_TABLE", "Table Probability (P)", result.table_probability);
    try rows.probability("XP2_FISH", if (result.first_cell != null) "Two-sided Pr <= P" else "Pr <= P", result.p);
    if (opt.point) try rows.probability("XPT_FISH", if (result.first_cell != null) "Point     Pr  = P" else "Pr  = P", result.point);
    if (opt.midp) try rows.probability("XMP_FISH", "Mid p-Value", @max(0, result.p - result.point / 2));
}

fn chiRows(rows: *Rows, suffix: []const u8, statistic: k.Test, p: ?dist.Probabilities, opt: parse.Options) !void {
    const a = rows.a;
    try rows.number(try std.fmt.allocPrint(a, "_{s}_", .{suffix}), "Chi-Square", statistic.statistic, "10.4");
    try rows.number(try std.fmt.allocPrint(a, "DF_{s}", .{suffix}), "DF", statistic.df, "best12.");
    try rows.add(try std.fmt.allocPrint(a, "P_{s}", .{suffix}), "Asymptotic Pr >  ChiSq", try render.probability(a, statistic.p, .default), statistic.p);
    if (p) |exact| {
        try rows.probability(try std.fmt.allocPrint(a, "XP_{s}", .{suffix}), "Exact      Pr >= ChiSq", exact.two_sided);
        if (opt.point) try rows.probability(try std.fmt.allocPrint(a, "XPT_{s}", .{suffix[0..4]}), "Exact      Pr  = ChiSq", exact.point);
        if (opt.midp) try rows.probability(try std.fmt.allocPrint(a, "XMP_{s}", .{suffix}), "Exact Mid p-Value", @max(0, exact.two_sided - exact.point / 2));
    }
}

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, table: []const u8, m: model.CountMatrix, chisq: ?k.ChiSquare, exact: public.Tables, opt: parse.Options) diag.Error!void {
    if (capture.wants("FishersExact")) {
        var result = exact.fisher;
        // Automatic Fisher belongs to CHISQ only for an integer 2x2 table.
        // An explicitly exhausted test must never fall back to this result.
        if (result == null and !opt.families.contains(.fisher)) if (chisq) |chi| {
            if (chi.fisher) |f| result = .{ .first_cell = @intFromFloat(m.counts[0]), .table_probability = f.probability, .left = f.left, .right = f.right, .p = f.two_sided, .point = 0 };
        };
        if (result != null or exact.fisher_table_probability != null) {
            var builder = try b.Builder.init(a, source, by, rep);
            builder.ds.label = "Fisher's Exact Test";
            try builder.char("Table", 256);
            var rows = try Rows.init(a, &builder, table, opt.pformat, 1);
            if (result) |f| try fisherRows(&rows, f, if (exact.fisher != null) opt else .{}) else try rows.probability("P_TABLE", "Table Probability (P)", exact.fisher_table_probability.?);
            rows.finish();
            try capture.publish(a, d, "FishersExact", &builder.ds);
        }
    }
    const chi = chisq orelse return;
    for ([_]parse.Family{ .pchi, .lrchi, .mhchi }, [_][]const u8{ "PearsonChiSq", "LRChiSq", "MHChiSq" }, [_][]const u8{ "PCHI", "LRCHI", "MHCHI" }, [_]?k.Test{ chi.pearson, chi.likelihood_ratio, chi.mantel_haenszel }) |family, object, suffix, statistic| {
        if (!opt.families.contains(family) or !capture.wants(object) or statistic == null) continue;
        var builder = try b.Builder.init(a, source, by, rep);
        try builder.char("Table", 256);
        var rows = try Rows.init(a, &builder, table, opt.pformat, 10);
        try chiRows(&rows, suffix, statistic.?, exact.exact_tests.get(family), opt);
        rows.finish();
        try capture.publish(a, d, object, &builder.ds);
    }
}

test "2x3 Fisher ODS separates tied probability, mid-p, observed table mass and seeded simulation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    var library = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const input = try a.create(Dataset);
    input.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "r", "c", "w" }) |name| _ = try input.addColumn(name, .num);
    for ([_]u32{ 3, 1, 0, 0, 2, 2 }, 0..) |frequency, i| {
        try input.appendRow(&.{ b.n(@floatFromInt(1 + i / 3)), b.n(@floatFromInt(1 + i % 3)), b.n(@floatFromInt(frequency)) });
    }
    try library.put(input.name, input);
    var capture: ods.Capture = .{};
    var listing: std.ArrayList(u8) = .empty;
    const context = @import("../proc.zig").ProcCtx{ .arena = a, .diags = &diagnostics, .lib = &library, .capture = &capture };
    try capture.parse(a, &diagnostics, try lex.tokenize(a, "ods output FishersExact=f; ", &diagnostics));
    try @import("freq.zig").runFreq(context, &listing, try lex.tokenize(a, "proc freq data=sample;weight w / zeros;tables r*c;exact fisher / point midp;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    const exact = library.find("f").?;
    try std.testing.expectEqual(@as(usize, 4), exact.rowCount());
    for ([_][]const u8{ "P_TABLE", "XP2_FISH", "XPT_FISH", "XMP_FISH" }, [_]f64{ 3, 16, 12, 10 }, 0..) |name, numerator, i| {
        try std.testing.expectEqualStrings(name, exact.row(i)[1].str);
        try std.testing.expectApproxEqAbs(numerator / 70, exact.row(i)[4].num, 1e-13);
    }
    try capture.parse(a, &diagnostics, try lex.tokenize(a, "ods output FishersExact=g FishersExactMC=s;", &diagnostics));
    try @import("freq.zig").runFreq(context, &listing, try lex.tokenize(a, "proc freq data=sample;weight w / zeros;tables r*c;exact fisher / mc n=2000 seed=713 alpha=.05;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    try std.testing.expectEqual(@as(usize, 1), library.find("g").?.rowCount());
    const mc = library.find("s").?;
    try std.testing.expectEqual(@as(usize, 6), mc.rowCount());
    try std.testing.expectEqualStrings("95% Lower Conf Limit", mc.row(1)[2].str);
    try std.testing.expectEqualStrings("0.2495", mc.row(0)[3].str);
    try std.testing.expectEqual(@as(f64, 499.0 / 2000.0), mc.row(0)[4].num);
    try std.testing.expectEqual(@as(f64, 713), mc.row(5)[4].num);
    try std.testing.expect(!diagnostics.hasErrors());
}
