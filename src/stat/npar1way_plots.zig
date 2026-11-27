//! Native Wilcoxon-score box plot for the NPAR1WAY default example.
//! SAS/STAT 15.4 physical p.7211 Figure90.7 and p.7270 graph identity.
//! Quartiles use SAS empirical QNTLDEF=5; whiskers stop at observations within
//! 1.5 IQR and remaining observations appear individually as outliers.
const std = @import("std");
const svg = @import("graphics_svg.zig");
const graph = @import("graph_ods.zig");
const axis_math = @import("npar1way_axis.zig");
const A = std.mem.Allocator;
pub const Box = struct { n: usize, q1: f64, median: f64, q3: f64, mean: f64, lower: f64, upper: f64, outliers: []f64 };
fn quantile(sorted: []const f64, p: f64) f64 {
    const position = @as(f64, @floatFromInt(sorted.len)) * p;
    const i: usize = @intFromFloat(position);
    if (position == @as(f64, @floatFromInt(i))) return if (std.math.isFinite(sorted[i - 1] + sorted[i])) (sorted[i - 1] + sorted[i]) / 2 else sorted[i - 1] / 2 + sorted[i] / 2;
    return sorted[i];
}
pub fn summarize(a: A, scores: []const f64, groups: []const usize, group_count: usize) ![]Box {
    if (scores.len != groups.len or group_count == 0) return error.InvalidInput;
    const result = try a.alloc(Box, group_count);
    for (result, 0..) |*box, g| {
        var values: std.ArrayList(f64) = .empty;
        var scale: f64 = 0;
        var total: f64 = 0;
        for (scores, groups) |score, group| {
            if (!std.math.isFinite(score) or group >= group_count) return error.InvalidInput;
            if (group == g) {
                try values.append(a, score);
                scale = @max(scale, @abs(score));
                total += score;
            }
        }
        if (values.items.len == 0) return error.InvalidInput;
        std.mem.sort(f64, values.items, {}, std.sort.asc(f64));
        var mean: f64 = 0;
        if (std.math.isFinite(total)) mean = total / @as(f64, @floatFromInt(values.items.len)) else if (scale > 0) {
            for (values.items) |v| mean += v / scale;
            mean = mean / @as(f64, @floatFromInt(values.items.len)) * scale;
        }
        const q1 = quantile(values.items, 0.25);
        const median = quantile(values.items, 0.5);
        const q3 = quantile(values.items, 0.75);
        const fence1 = q1 - 1.5 * (q3 - q1);
        const fence2 = q3 + 1.5 * (q3 - q1);
        var low: ?f64 = null;
        var high: f64 = 0;
        var outliers: std.ArrayList(f64) = .empty;
        for (values.items) |v| {
            if (v < fence1 or v > fence2) try outliers.append(a, v) else {
                if (low == null) low = v;
                high = v;
            }
        }
        box.* = .{ .n = values.items.len, .q1 = q1, .median = median, .q3 = q3, .mean = mean, .lower = low.?, .upper = high, .outliers = try outliers.toOwnedSlice(a) };
    }
    return result;
}
pub fn object(a: A, by: ?usize, variable: []const u8) !graph.Object {
    return @import("npar1way_graphs.zig").object(a, .wilcoxon, by, variable);
}

fn y(value: f64, axis: axis_math.Axis) f64 {
    return if (axis.low == 0 and @abs(value) <= std.math.floatMax(f64) / 320) 390 - 320 * value / axis.high else 390 - 320 * axis.fraction(value);
}
fn x(group: usize, count: usize) f64 {
    return 90 + 570 * (@as(f64, @floatFromInt(group)) + 0.5) / @as(f64, @floatFromInt(count));
}
pub fn render(a: A, scores: []const f64, groups: []const usize, labels: []const []const u8, response_name: []const u8, class_name: []const u8, probability: ?f64, by_label: []const u8) ![]const u8 {
    return renderNamed(a, scores, groups, labels, response_name, class_name, probability, by_label, "wilcoxonboxplot", "Distribution of Wilcoxon Scores", "Score", "Pr > ChiSq");
}
pub fn renderNamed(a: A, scores: []const f64, groups: []const usize, labels: []const []const u8, response_name: []const u8, class_name: []const u8, probability: ?f64, by_label: []const u8, kind: []const u8, title_prefix: []const u8, axis: []const u8, probability_label: []const u8) ![]const u8 {
    const boxes = try summarize(a, scores, groups, labels.len);
    var maximum: f64 = -std.math.inf(f64);
    var minimum: f64 = std.math.inf(f64);
    for (scores) |score| {
        maximum = @max(maximum, score);
        minimum = @min(minimum, score);
    }
    const fixed = std.mem.eql(u8, kind, "wilcoxonboxplot") or std.mem.eql(u8, kind, "fpboxplot");
    const ymax = if (std.mem.eql(u8, kind, "fpboxplot")) @ceil(@max(1, maximum)) else @ceil(@max(1, maximum) / 10) * 10;
    const axis_range = if (fixed) try axis_math.Axis.init(0, ymax, false) else try axis_math.Axis.init(minimum, maximum, true);
    var marks = try axis_math.ticks(a, axis_range.low, axis_range.high);
    if (fixed and @mod(ymax, 7) == 0) {
        marks = try a.alloc(axis_math.Tick, 8);
        for (marks, 0..) |*mark, i| {
            const value = ymax * @as(f64, @floatFromInt(i)) / 7;
            mark.* = .{ .value = value, .label = try axis_math.label(a, value) };
        }
    }
    var max_label: usize = 0;
    for (marks) |mark| max_label = @max(max_label, mark.label.len);
    const left: f64 = @max(90, @as(f64, @floatFromInt(max_label * 7 + 55)));
    const title = try std.fmt.allocPrint(a, "{s} for {s}", .{ title_prefix, response_name });
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"470\" viewBox=\"0 0 720 470\" role=\"img\" data-kind=\"");
    try svg.escaped(w, kind);
    try w.writeAll("\"><title>");
    try svg.escaped(w, title);
    try w.writeAll("</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:13px sans-serif;fill:#243448}.whisker,.median{stroke:#3766b0;stroke-width:1.4}.box{fill:#dae2ed;stroke:#555}.outlier{fill:white;stroke:#555}.mean{fill:none;stroke:#3766b0}</style><text x=\"360\" y=\"27\" text-anchor=\"middle\" font-weight=\"bold\">");
    try svg.escaped(w, title);
    try w.writeAll("</text><text x=\"360\" y=\"49\" text-anchor=\"middle\">");
    try svg.escaped(w, by_label);
    try w.writeAll("</text>");
    for (marks) |mark| {
        const yy = y(mark.value, axis_range);
        try w.print("<line x1=\"{d}\" x2=\"660\" y1=\"{d}\" y2=\"{d}\" stroke=\"#dce2e8\"/><text class=\"y-tick\" data-value=\"{e}\" x=\"{d}\" y=\"{d}\" text-anchor=\"end\">", .{ left, yy, yy, mark.value, left - 10, yy + 4 });
        try svg.escaped(w, mark.label);
        try w.writeAll("</text>");
    }
    try w.print("<path d=\"M{d} 70V390H660\" fill=\"none\" stroke=\"#87939e\"/><text transform=\"translate(28 230) rotate(-90)\" text-anchor=\"middle\">", .{left});
    try svg.escaped(w, axis);
    try w.writeAll("</text><text x=\"375\" y=\"449\" text-anchor=\"middle\">");
    try svg.escaped(w, class_name);
    try w.writeAll("</text>");
    const half = @min(@as(f64, 25), 190 / @as(f64, @floatFromInt(labels.len)));
    for (boxes, labels, 0..) |b, label, i| {
        const xx = left + (660 - left) * (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(labels.len));
        try w.print("<g class=\"score-box\" data-group=\"{d}\" data-n=\"{d}\" data-q1=\"{d}\" data-median=\"{d}\" data-q3=\"{d}\" data-mean=\"{d}\" data-lower=\"{d}\" data-upper=\"{d}\"><title>", .{ i, b.n, b.q1, b.median, b.q3, b.mean, b.lower, b.upper });
        try svg.escaped(w, label);
        try w.writeAll("</title>");
        try w.print("<line class=\"whisker\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/><line class=\"whisker\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/><line class=\"whisker\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/>", .{ xx, xx, y(b.lower, axis_range), y(b.upper, axis_range), xx - half / 2, xx + half / 2, y(b.lower, axis_range), y(b.lower, axis_range), xx - half / 2, xx + half / 2, y(b.upper, axis_range), y(b.upper, axis_range) });
        try w.print("<rect class=\"box\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/><line class=\"median\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/>", .{ xx - half, y(b.q3, axis_range), 2 * half, y(b.q1, axis_range) - y(b.q3, axis_range), xx - half, xx + half, y(b.median, axis_range), y(b.median, axis_range) });
        const yy = y(b.mean, axis_range);
        try w.print("<path class=\"mean\" d=\"M{d} {d}L{d} {d}L{d} {d}L{d} {d}Z\"/>", .{ xx, yy - 5, xx + 5, yy, xx, yy + 5, xx - 5, yy });
        for (b.outliers) |v| try w.print("<circle class=\"outlier\" data-score=\"{d}\" cx=\"{d}\" cy=\"{d}\" r=\"3\"/>", .{ v, xx, y(v, axis_range) });
        try w.print("<text x=\"{d}\" y=\"414\" text-anchor=\"middle\">", .{xx});
        try svg.escaped(w, label);
        try w.writeAll("</text></g>");
    }
    // Retain every plotted input score and coordinate as machine-readable data,
    // while only box summaries and outliers are visible (matching Figure90.7).
    for (scores, groups, 0..) |score, g, i| try w.print("<circle class=\"score-data\" display=\"none\" data-index=\"{d}\" data-group=\"{d}\" data-score=\"{d}\" cx=\"{d}\" cy=\"{d}\"/>", .{ i, g, score, left + (660 - left) * (@as(f64, @floatFromInt(g)) + 0.5) / @as(f64, @floatFromInt(labels.len)), y(score, axis_range) });
    if (probability) |p| {
        try w.writeAll("<text x=\"655\" y=\"435\" text-anchor=\"end\">");
        try svg.escaped(w, probability_label);
        try w.writeAll(" ");
        if (p < 0.0001) try w.writeAll("&lt;.0001") else try w.print("{d:.4}", .{p});
        try w.writeAll("</text>");
    }
    try w.writeAll("</svg>\n");
    return out.written();
}
