//! PROC ANOVA native graphs (STAT-ANOVA-010, S154 physical pp.1115–1117 and
//! 1143–1144): the grouped BoxPlot of a one-way model, the BoxPlot of each
//! MEANS effect and the Tukey LinesPlot that replaces the listing LINES table
//! when ODS Graphics is enabled. Identities follow the SAS ODS trace of the
//! Getting Started program (templates Stat.GLM.Graphics.*).
//!
//! ponytail: box statistics are NPAR1WAY's tested `summarize` (QNTLDEF=5,
//! 1.5 IQR fences); the drawing is ANOVA-local so no existing graph changes.
const std = @import("std");
const svg = @import("graphics_svg.zig");
const boxes = @import("npar1way_plots.zig");
const A = std.mem.Allocator;
const W = std.Io.Writer;

pub const Kind = enum { model, means };
pub const Inset = struct { f: f64, p: f64 };
pub const Object = struct { name: []const u8, label: ?[]const u8, template: []const u8, path: []const u8, kind: []const u8 };

fn byPrefix(a: A, by: ?usize) ![]const u8 {
    // ponytail: BY-group path component follows the other procedures; no SAS
    // trace of an ANOVA BY graph was available.
    if (by) |group| return std.fmt.allocPrint(a, "ANOVA.ByGroup{d}", .{group});
    return "ANOVA";
}

pub fn boxObject(a: A, kind: Kind, by: ?usize, response: []const u8, effect: []const u8) !Object {
    const prefix = try byPrefix(a, by);
    return switch (kind) {
        .model => .{ .name = "BoxPlot", .label = "Box Plot", .template = "Stat.GLM.Graphics.BoxPlot", .path = try std.fmt.allocPrint(a, "{s}.ANOVA.{s}.BoxPlot", .{ prefix, response }), .kind = "anova-boxplot" },
        .means => .{ .name = "BoxPlot", .label = try std.fmt.allocPrint(a, "Distribution of {s} by {s}", .{ response, effect }), .template = "Stat.GLM.Graphics.MeansBoxPlot", .path = try std.fmt.allocPrint(a, "{s}.Means.{s}.{s}.BoxPlot", .{ prefix, effect, response }), .kind = "anova-means-boxplot" },
    };
}

pub fn linesObject(a: A, by: ?usize, response: []const u8, effect: []const u8) !Object {
    return .{ .name = "LinesPlot", .label = null, .template = "Stat.GLM.Graphics.MeanLinesPlot", .path = try std.fmt.allocPrint(a, "{s}.Means.{s}.{s}.MCLines.Tukey.LinesPlot", .{ try byPrefix(a, by), effect, response }), .kind = "anova-linesplot" };
}

/// Trace and queue like Session.queue, but with SAS's own identity (the
/// LinesPlot has no Label line in the trace).
pub fn queue(session: *svg.Session, order: usize, object: Object, bytes: []const u8) !void {
    if (session.listing) |dest| {
        if (!dest.accepts(object.path)) return;
        try dest.traceObject(session.arena, object.name, object.label, object.template, object.path);
    }
    try session.prepared.append(session.arena, .{ .order = order, .kind = object.kind, .bytes = bytes });
}

fn open(w: *W, kind: []const u8, title: []const u8) !void {
    try w.writeAll("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"760\" height=\"510\" viewBox=\"0 0 760 510\" role=\"img\" data-kind=\"");
    try svg.escaped(w, kind);
    try w.writeAll("\"><title>");
    try svg.escaped(w, title);
    try w.writeAll("</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:12px system-ui,sans-serif;fill:#243447}.heading{font-size:17px;font-weight:600}.axes path{stroke:#7d8995;fill:none}.whisker,.median{stroke:#245e9b;stroke-width:1.4}.box{fill:#dae2ed;stroke:#555}.outlier{fill:white;stroke:#555}.mean{fill:none;stroke:#245e9b}.lines-bar{stroke:#245e9b;stroke-width:9}</style><text class=\"heading\" x=\"380\" y=\"26\" text-anchor=\"middle\">");
    try svg.escaped(w, title);
    try w.writeAll("</text>");
}

/// Grouped box plot of `values` by `groups` (index into `labels`).
pub fn boxSvg(a: A, kind: Kind, values: []const f64, groups: []const usize, labels: []const []const u8, response: []const u8, class: []const u8, inset: ?Inset) ![]const u8 {
    const summary = try boxes.summarize(a, values, groups, labels.len);
    var range: svg.Range = .{};
    for (values) |v| range.add(v);
    const b: svg.Bounds = .{ .x = .{ .lo = 0, .hi = 1 }, .y = range.padded(), .top = 60, .bottom = 420 };
    var out: W.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try open(w, if (kind == .model) "anova-boxplot" else "anova-means-boxplot", try std.fmt.allocPrint(a, "Distribution of {s}", .{response}));
    try w.print("<g class=\"axes\"><path d=\"M88 {d}V{d}H660\"/>", .{ b.top, b.bottom });
    for (0..6) |i| {
        const t = @as(f64, @floatFromInt(i)) / 5;
        try svg.tick(a, w, b, false, b.y.at(t), b.y.at(t));
    }
    try w.writeAll("</g><text x=\"374\" y=\"465\" text-anchor=\"middle\">");
    try svg.escaped(w, class);
    try w.writeAll("</text><text transform=\"translate(20 240) rotate(-90)\" text-anchor=\"middle\">");
    try svg.escaped(w, response);
    try w.writeAll("</text>");
    const count: f64 = @floatFromInt(labels.len);
    const half = @min(@as(f64, 28), 200 / count);
    for (summary, labels, 0..) |s, label, i| {
        const x = b.px((@as(f64, @floatFromInt(i)) + 0.5) / count);
        try w.print("<g class=\"anova-box\" data-group=\"{d}\" data-n=\"{d}\" data-q1=\"{d}\" data-median=\"{d}\" data-q3=\"{d}\" data-mean=\"{d}\" data-lower=\"{d}\" data-upper=\"{d}\"><title>", .{ i, s.n, s.q1, s.median, s.q3, s.mean, s.lower, s.upper });
        try svg.escaped(w, label);
        try w.writeAll("</title>");
        try w.print("<line class=\"whisker\" x1=\"{d:.2}\" x2=\"{d:.2}\" y1=\"{d:.2}\" y2=\"{d:.2}\"/><line class=\"whisker\" x1=\"{d:.2}\" x2=\"{d:.2}\" y1=\"{d:.2}\" y2=\"{d:.2}\"/><line class=\"whisker\" x1=\"{d:.2}\" x2=\"{d:.2}\" y1=\"{d:.2}\" y2=\"{d:.2}\"/>", .{ x, x, b.py(s.lower), b.py(s.upper), x - half / 2, x + half / 2, b.py(s.lower), b.py(s.lower), x - half / 2, x + half / 2, b.py(s.upper), b.py(s.upper) });
        try w.print("<rect class=\"box\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\"/><line class=\"median\" x1=\"{d:.2}\" x2=\"{d:.2}\" y1=\"{d:.2}\" y2=\"{d:.2}\"/>", .{ x - half, b.py(s.q3), 2 * half, b.py(s.q1) - b.py(s.q3), x - half, x + half, b.py(s.median), b.py(s.median) });
        const y = b.py(s.mean);
        try w.print("<path class=\"mean\" d=\"M{d:.2} {d:.2}L{d:.2} {d:.2}L{d:.2} {d:.2}L{d:.2} {d:.2}Z\"/>", .{ x, y - 5, x + 5, y, x, y + 5, x - 5, y });
        for (s.outliers) |v| try w.print("<circle class=\"outlier\" data-value=\"{d}\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"3\"/>", .{ v, x, b.py(v) });
        try w.print("<text x=\"{d:.2}\" y=\"441\" text-anchor=\"middle\">", .{x});
        try svg.escaped(w, label);
        try w.writeAll("</text></g>");
    }
    // Every plotted observation stays machine-readable; only the summaries
    // and outliers are visible.
    for (values, groups, 0..) |v, g, i| try w.print("<circle class=\"anova-data\" display=\"none\" data-index=\"{d}\" data-group=\"{d}\" data-value=\"{d}\" cy=\"{d:.2}\"/>", .{ i, g, v, b.py(v) });
    if (inset) |stats| {
        try w.print("<g class=\"anova-inset\" data-f=\"{d:.2}\"><text x=\"650\" y=\"76\" text-anchor=\"end\">F {d:.2}</text><text x=\"650\" y=\"92\" text-anchor=\"end\">Prob &gt; F ", .{ stats.f, stats.f });
        if (stats.p < 0.0001) try w.writeAll("&lt;.0001") else try w.print("{d:.4}", .{stats.p});
        try w.writeAll("</text></g>");
    }
    try w.writeAll("</svg>\n");
    return out.written();
}

/// Tukey grouping graph. `labels`/`means` are sorted by descending mean and
/// `masks` is `anova.tukeyGroups` for them: one vertical bar per group
/// covers the means that are not significantly different.
pub fn linesSvg(a: A, labels: []const []const u8, means: []const f64, masks: []const u32, response: []const u8, effect: []const u8, alpha: f64) ![]const u8 {
    if (labels.len != means.len or labels.len != masks.len or labels.len == 0) return error.InvalidInput;
    var out: W.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try open(w, "anova-linesplot", try std.fmt.allocPrint(a, "{s} Tukey Grouping for Means of {s} (Alpha = {d})", .{ response, effect, alpha }));
    try w.writeAll("<text x=\"380\" y=\"46\" text-anchor=\"middle\">Means covered by the same bar are not significantly different.</text><text x=\"200\" y=\"84\" text-anchor=\"end\" font-weight=\"bold\">");
    try svg.escaped(w, effect);
    try w.writeAll("</text><text x=\"300\" y=\"84\" text-anchor=\"end\" font-weight=\"bold\">Estimate</text>");
    const step = @min(@as(f64, 44), 360 / @as(f64, @floatFromInt(labels.len)));
    for (labels, means, masks, 0..) |label, mean, mask, i| {
        const y = 110 + step * @as(f64, @floatFromInt(i));
        var letters: [32]u8 = undefined;
        var n: usize = 0;
        for (0..32) |g| if (mask & (@as(u32, 1) << @intCast(g)) != 0) {
            letters[n] = 'A' + @as(u8, @intCast(g));
            n += 1;
        };
        try w.print("<g class=\"lines-row\" data-row=\"{d}\" data-mean=\"{d}\" data-groups=\"{s}\"><text x=\"200\" y=\"{d:.2}\" text-anchor=\"end\">", .{ i, mean, letters[0..n], y + 4 });
        try svg.escaped(w, label);
        try w.print("</text><text x=\"300\" y=\"{d:.2}\" text-anchor=\"end\">{d:.4}</text></g>", .{ y + 4, mean });
    }
    for (0..32) |g| {
        const bit = @as(u32, 1) << @intCast(g);
        var first: ?usize = null;
        var last: usize = 0;
        for (masks, 0..) |mask, i| if (mask & bit != 0) {
            if (first == null) first = i;
            last = i;
        };
        const f = first orelse continue;
        const x = 340 + 26 * @as(f64, @floatFromInt(g));
        try w.print("<line class=\"lines-bar\" data-group=\"{c}\" data-first=\"{d}\" data-last=\"{d}\" x1=\"{d}\" x2=\"{d}\" y1=\"{d:.2}\" y2=\"{d:.2}\"/>", .{ 'A' + @as(u8, @intCast(g)), f, last, x, x, 110 + step * @as(f64, @floatFromInt(f)) - 9, 110 + step * @as(f64, @floatFromInt(last)) + 9 });
    }
    try w.writeAll("</svg>\n");
    return out.written();
}
