//! Empirical CDF step geometry, SAS/STAT15.4 physical pp.7247-7249/7270.
const std = @import("std");
const ranks = @import("ranks.zig");
const axis_math = @import("npar1way_axis.zig");
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
pub const Step = struct { group: usize, value: f64, previous: f64, cdf: f64 };
pub fn steps(a: A, values: []const f64, groups: []const usize, count: usize) ![]Step {
    if (values.len != groups.len or count == 0) return error.InvalidInput;
    const totals = try a.alloc(usize, count);
    @memset(totals, 0);
    for (values, groups) |v, g| {
        if (!std.math.isFinite(v) or g >= count) return error.InvalidInput;
        totals[g] += 1;
    }
    for (totals) |n| if (n == 0) return error.InvalidInput;
    const ranked = try ranks.rank(a, values, false, .mean);
    if (ranked.groups.len > 100_000 / count) return error.PlotLimit;
    const cells = try a.alloc(usize, ranked.groups.len * count);
    @memset(cells, 0);
    for (values, groups) |value, group| {
        var lo: usize = 0;
        var hi = ranked.groups.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (ranked.groups[mid].value < value) lo = mid + 1 else hi = mid;
        }
        cells[group * ranked.groups.len + lo] += 1;
    }
    const result = try a.alloc(Step, ranked.groups.len * count);
    for (0..count) |g| {
        var cumulative: usize = 0;
        for (ranked.groups, 0..) |tie, i| {
            const before = @as(f64, @floatFromInt(cumulative)) / @as(f64, @floatFromInt(totals[g]));
            cumulative += cells[g * ranked.groups.len + i];
            result[g * ranked.groups.len + i] = .{ .group = g, .value = tie.value, .previous = before, .cdf = @as(f64, @floatFromInt(cumulative)) / @as(f64, @floatFromInt(totals[g])) };
        }
    }
    return result;
}
fn x(v: f64, lo: f64, hi: f64) f64 {
    return 80 + 620 * (axis_math.Axis{ .low = lo, .high = hi }).fraction(v);
}
fn y(p: f64) f64 {
    return 370 - 290 * p;
}
pub fn render(a: A, values: []const f64, groups: []const usize, labels: []const []const u8, variable: []const u8, class: []const u8, by: []const u8, p: ?f64) ![]const u8 {
    const grid = try steps(a, values, groups, labels.len);
    const per_group = grid.len / labels.len;
    const minimum = grid[0].value;
    const maximum = grid[per_group - 1].value;
    const axis = try axis_math.Axis.init(minimum, maximum, true);
    const lo = axis.low;
    const hi = axis.high;
    const height = 450 + ((labels.len + 3) / 4) * 24;
    var output: std.Io.Writer.Allocating = .init(a);
    errdefer output.deinit();
    const w = &output.writer;
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"760\" height=\"{d}\" viewBox=\"0 0 760 {d}\" role=\"img\" data-kind=\"edfplot\"><title>Empirical Distribution of ", .{ height, height });
    try svg.escaped(w, variable);
    try w.writeAll("</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:13px sans-serif;fill:#243448}.edf-line{fill:none;stroke-width:2}</style><text x=\"380\" y=\"28\" text-anchor=\"middle\" font-weight=\"bold\">Empirical Distribution of ");
    try svg.escaped(w, variable);
    try w.writeAll("</text><text x=\"380\" y=\"49\" text-anchor=\"middle\">");
    try svg.escaped(w, by);
    try w.writeAll("</text>");
    for (0..6) |i| {
        const value = @as(f64, @floatFromInt(i)) / 5;
        try w.print("<line x1=\"80\" x2=\"700\" y1=\"{d}\" y2=\"{d}\" stroke=\"#e0e5eb\"/><text x=\"70\" y=\"{d}\" text-anchor=\"end\">{d:.1}</text>", .{ y(value), y(value), y(value) + 4, value });
    }
    const marks = try axis_math.ticks(a, minimum, maximum);
    for (marks, 0..) |mark, i| {
        const anchor: []const u8 = if (marks.len == 1) (if (x(mark.value, lo, hi) > 620) @as([]const u8, "end") else if (x(mark.value, lo, hi) < 140) "start" else "middle") else if (i == 0) "start" else if (i + 1 == marks.len) "end" else "middle";
        try w.print("<text class=\"x-tick\" data-value=\"{e}\" x=\"{d}\" y=\"391\" text-anchor=\"{s}\">", .{ mark.value, x(mark.value, lo, hi), anchor });
        try svg.escaped(w, mark.label);
        try w.writeAll("</text>");
    }
    try w.writeAll("<path d=\"M80 80V370H700\" fill=\"none\" stroke=\"#777\"/><text transform=\"translate(25 225) rotate(-90)\" text-anchor=\"middle\">Cumulative Proportion</text><text x=\"390\" y=\"414\" text-anchor=\"middle\">");
    try svg.escaped(w, variable);
    try w.writeAll("</text>");
    const colors = [_][]const u8{ "#3766b0", "#bd473e", "#36846e", "#815fa8", "#b27823", "#278c9b", "#804c3b", "#666666" };
    for (labels, 0..) |label, g| {
        const color = colors[g % colors.len];
        try w.print("<g class=\"edf-group\" data-group=\"{d}\"><title>", .{g});
        try svg.escaped(w, label);
        try w.print("</title><polyline class=\"edf-line\" stroke=\"{s}\" points=\"80,370 ", .{color});
        for (grid[g * per_group ..][0..per_group]) |point| try w.print("{d},{d} {d},{d} ", .{ x(point.value, lo, hi), y(point.previous), x(point.value, lo, hi), y(point.cdf) });
        try w.writeAll("700,80\"/>");
        for (grid[g * per_group ..][0..per_group]) |point| try w.print("<circle class=\"edf-data\" display=\"none\" data-value=\"{d}\" data-previous=\"{d}\" data-cdf=\"{d}\" cx=\"{d}\" cy=\"{d}\"/>", .{ point.value, point.previous, point.cdf, x(point.value, lo, hi), y(point.cdf) });
        const lx = 80 + 160 * (g % 4);
        const ly = 440 + 24 * (g / 4);
        try w.print("<line x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\" stroke=\"{s}\" stroke-width=\"2\"/><text x=\"{d}\" y=\"{d}\">", .{ lx, lx + 20, ly, ly, color, lx + 25, ly + 4 });
        try svg.escaped(w, class);
        try w.writeAll("=");
        try svg.escaped(w, label);
        try w.writeAll("</text></g>");
    }
    if (p) |probability| {
        try w.writeAll("<text x=\"695\" y=\"65\" text-anchor=\"end\">Pr &gt; KSa ");
        if (probability < 0.0001) try w.writeAll("&lt;.0001") else try w.print("{d:.4}", .{probability});
        try w.writeAll("</text>");
    }
    try w.writeAll("</svg>\n");
    return output.written();
}
test "NPAR005 EDF graph exact jump geometry ties escaping and constant support" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [_]f64{ 1, 1, 4, 2, 3, 3 };
    const groups = [_]usize{ 0, 0, 0, 1, 1, 1 };
    const grid = try steps(a, &values, &groups, 2);
    try std.testing.expectEqual(@as(usize, 8), grid.len);
    for (grid[0..4], [_]f64{ 2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1 }) |point, cdf| try std.testing.expectEqual(cdf, point.cdf);
    for (grid[4..], [_]f64{ 0, 1.0 / 3.0, 1, 1 }) |point, cdf| try std.testing.expectEqual(cdf, point.cdf);
    const bytes = try render(a, &values, &groups, &.{ "<A&>", "B" }, "Value", "Group", "by=1", 0.5);
    try std.testing.expectEqual(@as(usize, 8), std.mem.count(u8, bytes, "class=\"edf-data\""));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "class=\"edf-line\""));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "&lt;A&amp;&gt;") != null);
    // Every data step must project onto the declared [80,700]x[370,80] axes.
    // The independent CDF values above and support[1,4] determine coordinates.
    // Compare numeric SVG attributes: decimal spelling is not a pixel identity.
    // 16*f64-epsilon*760 bounds the rounded padding/projection operations on
    // this well-conditioned support; it is a pixel bound, not a CDF tolerance.
    for (grid) |point| {
        const expected_x = 80 + 620 * (point.value - (1 - 0.15)) / ((4 + 0.15) - (1 - 0.15));
        const expected_y = 370 - 290 * point.cdf;
        const owner = try std.fmt.allocPrint(a, "<g class=\"edf-group\" data-group=\"{d}\">", .{point.group});
        const group_start = std.mem.indexOf(u8, bytes, owner).?;
        const section = bytes[group_start..][0..std.mem.indexOf(u8, bytes[group_start..], "</g>").?];
        const needle = try std.fmt.allocPrint(a, "data-value=\"{d}\" data-previous=\"{d}\" data-cdf=\"{d}\"", .{ point.value, point.previous, point.cdf });
        const location = std.mem.indexOf(u8, section, needle).? + needle.len;
        const rest = section[location..];
        for ([_][]const u8{ "cx=\"", "cy=\"" }, [_]f64{ expected_x, expected_y }) |attribute, expected| {
            const start = std.mem.indexOf(u8, rest, attribute).? + attribute.len;
            const end = start + std.mem.indexOfScalar(u8, rest[start..], '"').?;
            const actual = try std.fmt.parseFloat(f64, rest[start..end]);
            try std.testing.expectApproxEqAbs(expected, actual, 16 * std.math.floatEps(f64) * 760);
        }
    }
    const constant = try steps(a, &.{ 2, 2, 2, 2 }, &.{ 0, 0, 1, 1 }, 2);
    try std.testing.expectEqual(@as(usize, 2), constant.len);
    for (constant) |point| {
        try std.testing.expectEqual(@as(f64, 0), point.previous);
        try std.testing.expectEqual(@as(f64, 1), point.cdf);
    }
}

test {
    _ = axis_math;
}

test "NPAR010 EDF rendered tick labels roundtrip at tiny and extreme finite scales" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const max = std.math.floatMax(f64);
    for ([_][4]f64{ .{ 1e-9, 2e-9, 4e-9, 6e-9 }, .{ -max, -max / 2, max / 2, max }, .{ max, max, max, max }, .{ 1, 1, std.math.nextAfter(f64, 1, 2), std.math.nextAfter(f64, 1, 2) } }) |values| {
        const image = try render(a, &values, &.{ 0, 1, 0, 1 }, &.{ "A", "B" }, "x", "g", "", null);
        var rest = image;
        var count: usize = 0;
        while (std.mem.indexOf(u8, rest, "class=\"x-tick\"")) |index| {
            rest = rest[index..];
            const at = std.mem.indexOf(u8, rest, "data-value=\"").? + 12;
            const end = at + std.mem.indexOfScalar(u8, rest[at..], '"').?;
            const value = try std.fmt.parseFloat(f64, rest[at..end]);
            const label_start = std.mem.indexOfScalar(u8, rest, '>').? + 1;
            const label_end = label_start + std.mem.indexOf(u8, rest[label_start..], "</text>").?;
            try std.testing.expectEqual(value, try std.fmt.parseFloat(f64, rest[label_start..label_end]));
            count += 1;
            rest = rest[label_end..];
        }
        try std.testing.expect(count >= 1);
        rest = image;
        while (std.mem.indexOf(u8, rest, "class=\"edf-data\"")) |index| {
            rest = rest[index..];
            const at = std.mem.indexOf(u8, rest, "cx=\"").? + 4;
            const end = at + std.mem.indexOfScalar(u8, rest[at..], '"').?;
            const coordinate = try std.fmt.parseFloat(f64, rest[at..end]);
            try std.testing.expect(std.math.isFinite(coordinate) and coordinate >= 80 and coordinate <= 700);
            rest = rest[end..];
        }
    }
}
