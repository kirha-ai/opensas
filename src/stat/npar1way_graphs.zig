//! NPAR1WAY graph identities and available numerical producers, S154 p7270.
const std = @import("std");
const graph = @import("graph_ods.zig");
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
pub const Kind = enum { anova, wilcoxon, median, vw, savage, ab, st, klotz, mood, conover, data, fp, edf };
pub const size = std.meta.tags(Kind).len;
pub const Definition = struct { name: graph.Name, section: []const u8, title: []const u8, kind: []const u8 };
pub fn definition(kind: Kind) Definition {
    return switch (kind) {
        .anova => .{ .name = .ANOVABoxPlot, .section = "ANOVA", .title = "Raw Data", .kind = "anovaboxplot" },
        .wilcoxon => .{ .name = .WilcoxonBoxPlot, .section = "Wilcoxon", .title = "Wilcoxon Scores", .kind = "wilcoxonboxplot" },
        .median => .{ .name = .MedianPlot, .section = "Median", .title = "Median Scores", .kind = "medianplot" },
        .vw => .{ .name = .VWBoxPlot, .section = "VW", .title = "Van der Waerden Scores", .kind = "vwboxplot" },
        .savage => .{ .name = .SavageBoxPlot, .section = "Savage", .title = "Savage Scores", .kind = "savageboxplot" },
        .ab => .{ .name = .ABBoxPlot, .section = "AB", .title = "Ansari-Bradley Scores", .kind = "abboxplot" },
        .st => .{ .name = .STBoxPlot, .section = "ST", .title = "Siegel-Tukey Scores", .kind = "stboxplot" },
        .klotz => .{ .name = .KlotzBoxPlot, .section = "Klotz", .title = "Klotz Scores", .kind = "klotzboxplot" },
        .mood => .{ .name = .MoodBoxPlot, .section = "Mood", .title = "Mood Scores", .kind = "moodboxplot" },
        .conover => .{ .name = .ConoverBoxPlot, .section = "Conover", .title = "Conover Scores", .kind = "conoverboxplot" },
        .data => .{ .name = .DataScoresBoxPlot, .section = "DataScores", .title = "Data Scores", .kind = "datascoresboxplot" },
        .fp => .{ .name = .FPBoxPlot, .section = "FP", .title = "Fligner-Policello Placements", .kind = "fpboxplot" },
        .edf => .{ .name = .EDFPlot, .section = "EDF", .title = "Empirical Distribution", .kind = "edfplot" },
    };
}
pub fn parse(text: []const u8) ?Kind {
    inline for (std.meta.tags(Kind)) |kind| if (std.ascii.eqlIgnoreCase(text, @tagName(kind)) or std.ascii.eqlIgnoreCase(text, @tagName(definition(kind).name))) return kind;
    if (std.ascii.eqlIgnoreCase(text, "normal") or std.ascii.eqlIgnoreCase(text, "normalboxplot")) return .vw;
    if (std.ascii.eqlIgnoreCase(text, "datascores")) return .data;
    return null;
}
pub fn object(a: A, kind: Kind, by: ?usize, variable: []const u8) !graph.Object {
    const d = definition(kind);
    const prefix = if (by) |i| try std.fmt.allocPrint(a, "Npar1way.ByGroup{d}", .{i}) else "Npar1way";
    // Templates/section paths verified in NPAR010 original SAS TRACE for
    // ANOVA/Wilcoxon/Median/VW/Savage/EDF. Other families retain truthful names.
    const verified = kind == .anova or kind == .wilcoxon or kind == .median or kind == .vw or kind == .savage or kind == .edf;
    return .{ .name = d.name, .label = if (kind == .median) "Median Plot" else if (kind == .edf) "EDF Plot" else "Box Plot", .template = if (!verified) null else if (kind == .median) "Stat.NPAR1WAY.Graphics.MedianPlot" else if (kind == .edf) "Stat.NPAR1WAY.Graphics.EDFPlot" else "Stat.NPAR1WAY.Graphics.BoxPlot", .path = try std.fmt.allocPrint(a, "{s}.{s}.{s}.{s}", .{ prefix, try @import("../ods_listing.zig").pathPart(a, variable), d.section, @tagName(d.name) }) };
}
pub fn median(a: A, scores: []const f64, groups: []const usize, labels: []const []const u8, variable: []const u8, class: []const u8, by: []const u8, p: ?f64) ![]const u8 {
    if (scores.len != groups.len or labels.len == 0) return error.InvalidInput;
    const n = try a.alloc(usize, labels.len);
    const above = try a.alloc(f64, labels.len);
    @memset(n, 0);
    @memset(above, 0);
    for (scores, groups) |score, g| {
        if (g >= labels.len or !(score >= 0 and score <= 1)) return error.InvalidInput;
        n[g] += 1;
        above[g] += score;
    }
    var max: f64 = 1;
    for (n) |count| {
        if (count == 0) return error.InvalidInput;
        max = @max(max, @as(f64, @floatFromInt(count)));
    }
    var out: std.Io.Writer.Allocating = .init(a);
    const w = &out.writer;
    try w.writeAll("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"480\" viewBox=\"0 0 720 480\" data-kind=\"medianplot\"><title>Median Scores for ");
    try svg.escaped(w, variable);
    try w.writeAll("</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:13px sans-serif;fill:#243448}</style><text x=\"360\" y=\"28\" text-anchor=\"middle\">Median Scores for ");
    try svg.escaped(w, variable);
    try w.writeAll("</text><text x=\"360\" y=\"48\" text-anchor=\"middle\">");
    try svg.escaped(w, by);
    try w.writeAll("</text><path d=\"M90 70V390H660\" fill=\"none\" stroke=\"#777\"/><text transform=\"translate(28 230) rotate(-90)\" text-anchor=\"middle\">Frequency</text>");
    for (0..6) |i| {
        const value = max * @as(f64, @floatFromInt(i)) / 5;
        try w.print("<text x=\"80\" y=\"{d}\" text-anchor=\"end\">{d:.1}</text>", .{ 394 - 320 * value / max, value });
    }
    const width = @min(@as(f64, 50), 380 / @as(f64, @floatFromInt(labels.len)));
    for (labels, n, above, 0..) |label, count, high, g| {
        const low = @as(f64, @floatFromInt(count)) - high;
        const xx = 90 + 570 * (@as(f64, @floatFromInt(g)) + 0.5) / @as(f64, @floatFromInt(labels.len));
        try w.print("<g class=\"median-bar\" data-group=\"{d}\" data-n=\"{d}\" data-above=\"{d}\" data-below=\"{d}\"><rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"#9eb5d5\"/><rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"#e5aa70\"/><text x=\"{d}\" y=\"413\" text-anchor=\"middle\">", .{ g, count, high, low, xx - width / 2, 390 - 320 * low / max, width, 320 * low / max, xx - width / 2, 390 - 320 * (low + high) / max, width, 320 * high / max, xx });
        try svg.escaped(w, label);
        try w.writeAll("</text></g>");
    }
    try w.writeAll("<text x=\"375\" y=\"435\" text-anchor=\"middle\">");
    try svg.escaped(w, class);
    try w.writeAll("</text><rect x=\"110\" y=\"453\" width=\"12\" height=\"12\" fill=\"#9eb5d5\"/><text x=\"128\" y=\"464\">Below Median</text><rect x=\"260\" y=\"453\" width=\"12\" height=\"12\" fill=\"#e5aa70\"/><text x=\"278\" y=\"464\">Above Median</text>");
    if (p) |v| {
        try w.writeAll("<text x=\"655\" y=\"464\" text-anchor=\"end\">Pr &gt; ChiSq ");
        if (v < 0.0001) try w.writeAll("&lt;.0001") else try w.print("{d:.4}", .{v});
        try w.writeAll("</text>");
    }
    try w.writeAll("</svg>\n");
    return out.written();
}

pub const Table = struct { section: ?[]const u8 = null, label: ?[]const u8 = null, template: ?[]const u8 = null };
pub fn table(name: []const u8) Table {
    if (std.mem.eql(u8, name, "ClassMeans")) return .{ .section = "ANOVA", .label = "Class Means", .template = "Stat.Npar1way.ClassMeans" };
    if (std.mem.eql(u8, name, "ANOVA")) return .{ .section = "ANOVA", .label = "ANOVA", .template = "Stat.Npar1way.ANOVA" };
    for ([_][]const u8{ "Wilcoxon", "Median", "VW", "Savage" }) |section| {
        if (std.mem.startsWith(u8, name, section)) {
            const suffix = name[section.len..];
            if (std.mem.eql(u8, suffix, "Scores")) return .{ .section = section, .label = "Scores", .template = "Stat.Npar1way.ClassScores" };
            if (std.mem.eql(u8, suffix, "Test")) return .{ .section = section, .label = "Two-Sample Test", .template = "Stat.Npar1way.TwoSampleTest" };
            if (std.mem.eql(u8, suffix, "Analysis")) return .{ .section = section, .label = "One-Way Analysis", .template = "Stat.Npar1way.OneWayAnalysis" };
        }
    }
    if (std.mem.eql(u8, name, "KruskalWallisTest")) return .{ .section = "Wilcoxon", .label = "Kruskal-Wallis Test", .template = "Stat.Npar1way.OneWayAnalysis" };
    const names = [_][]const u8{ "KSTest", "KSStats", "KS2Stats", "CVMTest", "CVMStats", "KuiperTest", "KuiperStats" };
    const labels = [_][]const u8{ "Kolmogorov-Smirnov Test", "Kolmogorov-Smirnov Statistics", "Kolmogorov-Smirnov Two-Sample Statistics", "Cramer-von Mises Test", "Cramer-von Mises Statistics", "Kuiper Test", "Kuiper Two-Sample Statistics" };
    for (names, labels) |n, l| if (std.mem.eql(u8, name, n)) return .{ .section = "EDF", .label = l, .template = if (std.mem.endsWith(u8, name, "Test")) "Stat.Npar1way.EDF" else "Stat.Npar1way.EdfFactoid" };
    return .{};
}

test "NPAR010 complete graph catalog default median data and negative score geometry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = @import("npar1way_stats_tests.zig");
    const groups = source.groups();
    const r = try @import("npar1way_stats.zig").compute(a, &source.gains, &groups, 5, .{});
    for (std.meta.tags(Kind)) |kind| {
        try std.testing.expectEqual(kind, parse(@tagName(definition(kind).name)).?);
        try std.testing.expect(@import("graph_ods.zig").known(@tagName(definition(kind).name)));
    }
    const raw_boxes = try @import("npar1way_plots.zig").summarize(a, &source.gains, &groups, 5);
    // Independent sorted first class: 200,208,208,216,218,219,220,224,
    // 224,228,229,229,232,232,233,235; QNTLDEF5 averages at positions4/8/12.
    try std.testing.expectEqual(@as(f64, 217), raw_boxes[0].q1);
    try std.testing.expectEqual(@as(f64, 224), raw_boxes[0].median);
    try std.testing.expectEqual(@as(f64, 230.5), raw_boxes[0].q3);
    try std.testing.expectEqual(@as(f64, 222.1875), raw_boxes[0].mean);
    try std.testing.expectEqual(@as(f64, 273), raw_boxes[1].upper); // exactly on upper fence
    const median_scores = r.scores[1];
    const bytes = try median(a, median_scores.values, &groups, &.{ "0", ".04", ".07", ".10", ".13" }, "Gain", "Dose", "", median_scores.p);
    for ([_]usize{ 16, 11, 12, 17, 11 }, [_]f64{ 16, 11, 6, 0, 0 }, 0..) |n, above, g| {
        const row = try std.fmt.allocPrint(a, "data-group=\"{d}\" data-n=\"{d}\" data-above=\"{d}\" data-below=\"{d}\"", .{ g, n, above, @as(f64, @floatFromInt(n)) - above });
        try std.testing.expect(std.mem.indexOf(u8, bytes, row) != null);
    }
    const box = @import("npar1way_plots.zig");
    for (r.scores) |score| {
        if (score.kind == .median) continue;
        const d = definition(parse(@tagName(score.kind)).?);
        const image = try box.renderNamed(a, score.values, &groups, &.{ "0", ".04", ".07", ".10", ".13" }, "Gain", "Dose", score.p, "", d.kind, d.title, "Score", "Pr > ChiSq");
        try std.testing.expectEqual(@as(usize, 67), std.mem.count(u8, image, "class=\"score-data\""));
        var rest = image;
        while (std.mem.indexOf(u8, rest, "class=\"score-data\"")) |start| {
            rest = rest[start..];
            const cy = std.mem.indexOf(u8, rest, "cy=\"").? + 4;
            const end = cy + std.mem.indexOfScalar(u8, rest[cy..], '"').?;
            const y = try std.fmt.parseFloat(f64, rest[cy..end]);
            try std.testing.expect(std.math.isFinite(y) and y >= 70 and y <= 390);
            rest = rest[end..];
        }
    }
}

test "NPAR010 raw box summaries and coordinates remain finite at extreme ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const max = std.math.floatMax(f64);
    const plots = @import("npar1way_plots.zig");
    const values = [_]f64{ -max, -max / 2, max / 2, max };
    const groups = [_]usize{ 0, 0, 1, 1 };
    const boxes = try plots.summarize(a, &values, &groups, 2);
    for (boxes) |box| {
        try std.testing.expect(std.math.isFinite(box.mean));
        try std.testing.expect(std.math.isFinite(box.median));
    }
    const image = try plots.renderNamed(a, &values, &groups, &.{ "A", "B" }, "x", "g", null, "", "anovaboxplot", "Raw Data", "Value", "Pr > F");
    var rest = image;
    while (std.mem.indexOf(u8, rest, "class=\"score-data\"")) |start| {
        rest = rest[start..];
        const at = std.mem.indexOf(u8, rest, "cy=\"").? + 4;
        const end = at + std.mem.indexOfScalar(u8, rest[at..], '"').?;
        const value = try std.fmt.parseFloat(f64, rest[at..end]);
        try std.testing.expect(std.math.isFinite(value) and value >= 70 and value <= 390);
        rest = rest[end..];
    }
}
