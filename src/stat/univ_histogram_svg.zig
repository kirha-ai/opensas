//! Draw the same histogram bins, parameter estimates and kernel grids supplied
//! to the procedure's numerical outputs. CLASS panels share axes.
const std = @import("std");
const svg = @import("graphics_svg.zig");
const ann = @import("univ_graph_annotations.zig");
const dist = @import("univ_distributions.zig");
const kernel = @import("univ_kernel.zig");
const values = @import("univ_distribution_values.zig");
const dist_render = @import("univ_distribution_render.zig");
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;
const W = std.Io.Writer;
pub const Curve = struct { distribution: dist.Distribution, fill: bool };
pub const Panel = struct {
    keys: []const @import("univ_plot_data.zig").Key,
    bins: []const values.Bin,
    curves: []const Curve,
    kernel_rows: []const []const Value,
    inset: ann.Box,
    n: usize,
};
pub const Options = struct {
    variable: @import("../dataset.zig").Column,
    title: []const u8,
    scale: kernel.VScale,
    barlabel: ?kernel.VScale,
    endpoint_labels: bool,
    endpoints: []const f64,
    bin_width: f64,
};

fn barHeight(bin: values.Bin, scale: kernel.VScale) f64 {
    return switch (scale) {
        .count => @floatFromInt(bin.count),
        .percent => bin.observed_percent,
        .proportion => bin.observed_percent / 100,
    };
}
fn fitted(c: Curve, v: f64, opt: Options, n: usize) f64 {
    return kernel.scaleDensity(@exp(c.distribution.logPdf(v)), opt.bin_width, n, opt.scale);
}
fn draw(a: A, w: *W, panels: []const Panel, opt: Options) !void {
    var x = svg.Range{};
    var maximum: f64 = 0;
    for (opt.endpoints) |v| x.add(v);
    for (panels) |p| {
        for (p.bins) |b| {
            x.add(b.lower);
            x.add(b.upper);
            maximum = @max(maximum, barHeight(b, opt.scale));
        }
        for (p.kernel_rows) |row| {
            x.add(row[row.len - 3].num);
            maximum = @max(maximum, row[row.len - 2].num);
        }
    }
    for (panels) |p| for (p.curves) |c| for (0..257) |i| {
        const y = fitted(c, x.at(@as(f64, @floatFromInt(i)) / 256), opt, p.n);
        if (std.math.isFinite(y)) maximum = @max(maximum, y);
    };
    const row_height: f64 = if (panels.len == 1) 335 else 220;
    var headroom: f64 = if (opt.barlabel != null) 19 else 8;
    for (panels) |p| switch (p.inset.pos) {
        .nw, .n, .ne => if (p.inset.lines.len > 0) {
            const rows: f64 = @floatFromInt(p.inset.lines.len + @intFromBool(p.inset.header.len != 0));
            headroom = @max(headroom, 32 + 16 * rows);
        },
        else => {},
    };
    const required = if (maximum > 0) maximum / (1 - @min(0.75, headroom / (row_height - 45))) else 1;
    const base = std.math.pow(f64, 10, @floor(@log10(required / 5)));
    const decade = required / 5 / base;
    const tick_step = base * @as(f64, if (decade <= 1.5) 1 else if (decade <= 3) 2 else if (decade <= 7) 5 else 10);
    const y_ticks: usize = @intFromFloat(@ceil(required / tick_step));
    const y_range = svg.Range{ .lo = 0, .hi = @as(f64, @floatFromInt(y_ticks)) * tick_step };
    const height = 102 + row_height * @as(f64, @floatFromInt(panels.len));
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"690\" height=\"{d}\" viewBox=\"0 0 690 {d}\" role=\"img\" data-kind=\"histogram\"><title>", .{ height, height });
    try svg.escaped(w, opt.title);
    try w.writeAll("</title><style>text{font:12px system-ui,sans-serif;fill:#1d2935}.heading{font-size:18px;font-weight:600}.facet{font-weight:600}.axes path{stroke:#75808a;fill:none}.bar{fill:#dce9f5;stroke:#6d8298}.density,.kernel{stroke-width:1.8;fill:none}.bar-label{font-size:11px}</style>");
    try w.print("<rect width=\"690\" height=\"{d}\" fill=\"white\"/><text class=\"heading\" x=\"345\" y=\"25\" text-anchor=\"middle\">", .{height});
    try svg.escaped(w, opt.title);
    try w.writeAll("</text><text x=\"88\" y=\"45\">");
    try svg.keyText(w, panels[0].keys, false);
    try w.writeAll("</text>");
    const palette = [_][]const u8{ "#a25032", "#196b66", "#765b9e", "#355d88" };
    for (panels, 0..) |p, j| {
        const top = 62 + row_height * @as(f64, @floatFromInt(j));
        const b = svg.Bounds{ .x = x, .y = y_range, .top = top, .bottom = top + row_height - 45 };
        try w.print("<g class=\"panel\" data-panel=\"{d}\"><text class=\"facet\" x=\"88\" y=\"{d}\">", .{ j + 1, top - 5 });
        try svg.keyText(w, p.keys, true);
        try w.writeAll("</text>");
        try w.print("<g class=\"axes\"><path d=\"M{d} {d}V{d}H{d}\"/>", .{ svg.Bounds.left, top, b.bottom, svg.Bounds.right });
        for (0..y_ticks + 1) |i| {
            const v = @as(f64, @floatFromInt(i)) * tick_step;
            try svg.tick(a, w, b, false, v, v);
        }
        const anchor = opt.endpoints[0] + if (opt.endpoint_labels) @as(f64, 0) else opt.bin_width / 2;
        const first_tick = @ceil((x.lo - anchor) / opt.bin_width);
        const last_tick = @floor((x.hi - anchor) / opt.bin_width);
        const stride = @max(1, @ceil((last_tick - first_tick) / 10));
        for (0..11) |i| {
            const at = first_tick + @as(f64, @floatFromInt(i)) * stride;
            if (at > last_tick) break;
            const v = anchor + at * opt.bin_width;
            if (std.math.isFinite(v)) try svg.tick(a, w, b, true, v, v);
        }
        try w.writeAll("</g>");
        for (p.bins) |bin| {
            const val = barHeight(bin, opt.scale);
            const y = b.py(val);
            try w.print("<rect class=\"bar\" data-lower=\"{d}\" data-upper=\"{d}\" data-count=\"{d}\" data-height=\"{d}\" x=\"{d:.2}\" width=\"{d:.2}\" y=\"{d:.2}\" height=\"{d:.2}\"/>", .{ bin.lower, bin.upper, bin.count, val, b.px(bin.lower), b.px(bin.upper) - b.px(bin.lower), y, b.bottom - y });
            if (opt.barlabel) |scale| {
                try w.print("<text class=\"bar-label\" x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"middle\">{s}</text>", .{ b.px(bin.midpoint), y - 5, try svg.label(a, barHeight(bin, scale)) });
            }
        }
        var legends: std.ArrayList([]const u8) = .empty;
        for (p.curves, 0..) |c, i| {
            const color = palette[i % palette.len];
            const fill = c.fill and p.curves.len == 1 and p.kernel_rows.len == 0;
            const name = dist_render.familyName(c.distribution.family);
            var points: W.Allocating = .init(a);
            for (0..257) |k| {
                const v = x.at(@as(f64, @floatFromInt(k)) / 256);
                const y = fitted(c, v, opt, p.n);
                if (std.math.isFinite(y)) try points.writer.print("{s}{d:.2} {d:.2}", .{ if (points.written().len == 0) "M" else " L", b.px(v), b.py(y) });
            }
            if (fill) try w.print("<path class=\"density-fill\" fill=\"{s}\" fill-opacity=\"0.2\" d=\"{s} L{d} {d}H{d}Z\"/>", .{ color, points.written(), svg.Bounds.right, b.bottom, svg.Bounds.left });
            try w.print("<path class=\"density\" data-family=\"{s}\" stroke=\"{s}\" d=\"{s}\"/>", .{ name, color, points.written() });
            try legends.append(a, name);
        }
        var k: usize = 0;
        while (k < p.kernel_rows.len) {
            const first = p.kernel_rows[k];
            const at = first.len - 5;
            const name = try std.fmt.allocPrint(a, "{s} kernel (c={s})", .{ first[at].str, try svg.label(a, first[at + 1].num) });
            const color = palette[legends.items.len % palette.len];
            try legends.append(a, name);
            try w.print("<path class=\"kernel\" stroke=\"{s}\" d=\"", .{color});
            const start = k;
            while (k < p.kernel_rows.len) : (k += 1) {
                const row = p.kernel_rows[k];
                if (k > start and (row[at + 2].num <= p.kernel_rows[k - 1][at + 2].num or !std.mem.eql(u8, row[at].str, first[at].str) or row[at + 1].num != first[at + 1].num)) break;
                try w.print("{s}{d:.2} {d:.2}", .{ if (k == start) "M" else " L", b.px(row[at + 2].num), b.py(row[at + 3].num) });
            }
            try w.writeAll("\"/>");
        }
        if (legends.items.len > 0) {
            try w.print("<text class=\"legend\" x=\"660\" y=\"{d}\" text-anchor=\"end\">", .{top - 5});
            for (legends.items, 0..) |name, i| {
                if (i != 0) try w.writeAll(" · ");
                try w.print("<tspan fill=\"{s}\">", .{palette[i % palette.len]});
                try svg.escaped(w, name);
                try w.writeAll("</tspan>");
            }
            try w.writeAll("</text>");
        }
        try svg.drawInset(w, p.inset, b);
        try w.writeAll("</g>");
    }
    try w.print("<text class=\"axis-x\" text-anchor=\"middle\" x=\"374\" y=\"{d}\">", .{height - 13});
    try svg.escaped(w, opt.variable.label orelse opt.variable.name);
    try w.writeAll("</text>");
    try w.print("<text class=\"axis-y\" text-anchor=\"middle\" transform=\"translate(18 {d}) rotate(-90)\">{s}</text></svg>", .{ height / 2, switch (opt.scale) {
        .percent => "Percent",
        .proportion => "Proportion",
        .count => "Count",
    } });
}
pub fn render(a: A, panels: []const Panel, opt: Options) @import("../diag.zig").Error![]const u8 {
    var out: W.Allocating = .init(a);
    draw(a, &out.writer, panels, opt) catch return error.OutOfMemory;
    return out.written();
}
