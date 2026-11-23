//! Native SVGs from the statistical procedures' typed plot data.
const std = @import("std");
const diag = @import("../diag.zig");
const plot_data = @import("univ_plot_data.zig");
const lex = @import("../lexer.zig");
const distributions = @import("univ_distribution_render.zig");
const Plot = plot_data.Plot;
const A = std.mem.Allocator;
const W = std.Io.Writer;
const eq = std.ascii.eqlIgnoreCase;

const Artifact = struct { order: usize, kind: []const u8, bytes: []const u8 };
pub const Session = struct {
    arena: A,
    io: std.Io,
    diags: *diag.Diagnostics,
    cli_dir: ?[]const u8 = null,
    gpath: ?[]const u8 = null,
    enabled: ?bool = null,
    count: usize = 0,
    pending: std.ArrayList(Plot) = .empty,
    prepared: std.ArrayList(Artifact) = .empty,
    pub fn queue(self: *Session, order: usize, kind: []const u8, bytes: []const u8) !void {
        try self.prepared.append(self.arena, .{ .order = order, .kind = kind, .bytes = bytes });
    }
    pub fn clear(self: *Session) void {
        self.pending.clearRetainingCapacity();
        self.prepared.clearRetainingCapacity();
    }

    pub fn configure(self: *Session, toks: []const lex.Token) diag.Error!void {
        if (toks.len < 3) return;
        const sub = toks[1].text;
        if (eq(sub, "graphics")) {
            if (eq(toks[2].text, "on") or eq(toks[2].text, "off")) {
                if (toks.len > 3 and toks[3].tag != .semicolon and toks[3].tag != .eof)
                    return self.diags.fail(error.ParseError, toks[3].line, "ODS GRAPHICS: unsupported graphics setting {s}", .{toks[3].text});
                self.enabled = eq(toks[2].text, "on");
            }
        } else if (eq(sub, "listing")) {
            for (toks[2..], 2..) |t, i| if (eq(t.text, "gpath")) {
                if (i + 2 >= toks.len or toks[i + 1].tag != .eq or toks[i + 2].tag != .string or toks[i + 2].text.len == 0)
                    return self.diags.fail(error.ParseError, t.line, "ODS LISTING GPATH= requires a directory string", .{});
                self.gpath = toks[i + 2].text;
            };
        }
    }
    pub fn sink(self: *Session) ?plot_data.Sink {
        if (self.enabled == null and self.cli_dir == null and self.gpath == null) return null;
        return .{ .context = self, .emit = collect, .enabled = self.enabled orelse true };
    }
    fn collect(raw: ?*anyopaque, plot: Plot) diag.Error!void {
        const self: *Session = @ptrCast(@alignCast(raw.?));
        try self.pending.append(self.arena, plot);
    }
    pub fn flush(self: *Session) diag.Error!void {
        defer self.clear();
        const plots = self.pending.items;
        const used = try self.arena.alloc(bool, plots.len);
        @memset(used, false);
        for (plots, 0..) |p, i| {
            if (used[i]) continue;
            var panels: std.ArrayList(Plot) = .empty;
            for (plots[i..], i..) |other, j| {
                if (other.statement_index != p.statement_index or other.by_index != p.by_index or other.curve_index != p.curve_index or !eq(other.variable.name, p.variable.name)) continue;
                try panels.append(self.arena, other);
                used[j] = true;
            }
            const bytes = try render(self.arena, panels.items);
            try self.queue(p.statement_index, @tagName(p.kind), bytes);
        }
        std.mem.sort(Artifact, self.prepared.items, {}, byOrder);
        for (self.prepared.items) |g| try self.save(g.kind, g.bytes);
    }
    fn byOrder(_: void, a: Artifact, b: Artifact) bool {
        return a.order < b.order;
    }
    fn save(self: *Session, kind: []const u8, bytes: []const u8) diag.Error!void {
        const path = self.cli_dir orelse self.gpath orelse ".";
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(self.io, path) catch |e| return self.diags.fail(error.ExecError, 0, "Cannot create graphics directory {s}: {t}", .{ path, e });
        while (true) {
            self.count += 1;
            const name = try std.fmt.allocPrint(self.arena, "{s}/opensas-{d:0>4}-{s}.svg", .{ path, self.count, kind });
            var tmp = cwd.createFileAtomic(self.io, name, .{}) catch |e| return self.diags.fail(error.ExecError, 0, "Cannot create graphic {s}: {t}", .{ name, e });
            defer tmp.deinit(self.io);
            tmp.file.writeStreamingAll(self.io, bytes) catch |e| return self.diags.fail(error.ExecError, 0, "Cannot write graphic {s}: {t}", .{ name, e });
            tmp.link(self.io) catch |e| {
                if (e == error.PathAlreadyExists) continue;
                return self.diags.fail(error.ExecError, 0, "Cannot publish graphic {s}: {t}", .{ name, e });
            };
            try self.diags.report(.note, 0, "SVG graphic written to {s}.", .{name});
            return;
        }
    }
};

pub const Range = struct {
    lo: f64 = std.math.inf(f64),
    hi: f64 = -std.math.inf(f64),
    pub fn add(r: *Range, x: f64) void {
        r.lo = @min(r.lo, x);
        r.hi = @max(r.hi, x);
    }
    pub fn padded(r: Range) Range {
        const margin = if (r.hi > r.lo) (r.hi - r.lo) * 0.05 else @max(1, @abs(r.lo) * 0.05);
        return .{ .lo = r.lo - margin, .hi = r.hi + margin };
    }
    pub fn at(r: Range, t: f64) f64 {
        return r.lo * (1 - t) + r.hi * t;
    }
    fn fraction(r: Range, v: f64) f64 {
        return (v - r.lo) / (r.hi - r.lo);
    }
};
pub const Bounds = struct {
    x: Range,
    y: Range,
    top: f64,
    bottom: f64,
    pub const left: f64 = 88;
    pub const right: f64 = 660;
    pub fn px(b: Bounds, x: f64) f64 {
        return left + (right - left) * b.x.fraction(x);
    }
    pub fn py(b: Bounds, y: f64) f64 {
        return b.bottom - (b.bottom - b.top) * b.y.fraction(y);
    }
};

pub fn escaped(w: *W, value: []const u8) W.Error!void {
    for (value) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        '\'' => try w.writeAll("&apos;"),
        0...8, 11, 12, 14...31 => try w.writeAll("�"),
        else => try w.writeByte(c),
    };
}
pub fn label(a: A, x: f64) ![]const u8 {
    if (x == 0) return "0";
    if (@abs(x) < 0.0001 or @abs(x) >= 1e6) return std.fmt.allocPrint(a, "{e:.3}", .{x});
    const s = try std.fmt.allocPrint(a, "{d:.4}", .{x});
    return std.mem.trimEnd(u8, std.mem.trimEnd(u8, s, "0"), ".");
}
const XY = struct { x: f64, y: f64 };
fn coordinate(plot: Plot, point: plot_data.Point) XY {
    if (plot.kind == .probability) {
        const q = point.theoretical_quantile.?;
        return if (plot.rotated) .{ .x = point.x, .y = q } else .{ .x = q, .y = point.y };
    }
    return .{ .x = point.x, .y = point.y };
}
fn probabilityPosition(plot: Plot, p: f64) f64 {
    if (plot.weibull2) return @log(-std.math.log1p(-p));
    var curve = plot.distribution;
    curve.p.theta = 0;
    if (curve.family != .lognormal) curve.p.sigma = 1;
    curve.p.zeta = 0;
    curve.p.mu = 0;
    return curve.quantile(p);
}
pub fn tick(a: A, w: *W, b: Bounds, horizontal: bool, position: f64, value: f64) !void {
    const x = if (horizontal) b.px(position) else Bounds.left;
    const y = if (horizontal) b.bottom else b.py(position);
    if (horizontal)
        try w.print("<path d=\"M{d:.2} {d:.2}v5\"/><text x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"middle\">{s}</text>\n", .{ x, y, x, y + 21, try label(a, value) })
    else
        try w.print("<path d=\"M{d:.2} {d:.2}h-5\"/><text x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"end\">{s}</text>\n", .{ x, y, x - 10, y + 4, try label(a, value) });
}
fn axes(a: A, w: *W, p: Plot, b: Bounds) !void {
    try w.print("<g class=\"axes\"><path d=\"M{d} {d}V{d}H{d}\"/>\n", .{ Bounds.left, b.top, b.bottom, Bounds.right });
    for ([_]bool{ true, false }) |horizontal| {
        const range = if (horizontal) b.x else b.y;
        if (p.kind == .probability and horizontal != p.rotated) {
            for ([_]f64{ 0.001, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 0.999 }) |prob| {
                const pos = probabilityPosition(p, prob);
                if (pos >= range.lo and pos <= range.hi) try tick(a, w, b, horizontal, pos, 100 * prob);
            }
        } else for (0..6) |i| {
            const pos = range.at(@as(f64, @floatFromInt(i)) / 5);
            try tick(a, w, b, horizontal, pos, pos);
        }
    }
    try w.writeAll("</g>\n");
}
fn extraAxes(a: A, w: *W, p: Plot, b: Bounds) !void {
    for ([_]bool{ true, false }) |horizontal| {
        const r = if (horizontal) b.x else b.y;
        for (if (horizontal) p.axes.href else p.axes.vref) |v| {
            const position = if (p.kind == .probability and horizontal != p.rotated) blk: {
                if (v <= 0 or v >= 100) continue;
                break :blk probabilityPosition(p, v / 100);
            } else v;
            if (!std.math.isFinite(position) or position < r.lo or position > r.hi) continue;
            try w.print("<path class=\"{s}\" data-value=\"{d}\" data-position=\"{d}\" stroke=\"#9b887a\" stroke-dasharray=\"5 4\" d=\"", .{ if (horizontal) "href" else "vref", v, position });
            if (horizontal) try w.print("M{d:.2} {d:.2}V{d:.2}", .{ b.px(position), b.top, b.bottom }) else try w.print("M{d:.2} {d:.2}H{d:.2}", .{ Bounds.left, b.py(position), Bounds.right });
            try w.writeAll("\"/>");
        }
    }
    if (!p.axes.percentile) return;
    const horizontal = !p.rotated;
    const r = if (horizontal) b.x else b.y;
    try w.writeAll("<g class=\"percentiles\">");
    for (p.axes.percentiles) |percent| {
        const position = probabilityPosition(p, percent / 100);
        if (!std.math.isFinite(position) or position < r.lo or position > r.hi) continue;
        const px = if (horizontal) b.px(position) else Bounds.right;
        const py = if (horizontal) b.top else b.py(position);
        if (p.axes.grid) {
            try w.print("<path class=\"percentile-grid\" data-percent=\"{d}\" stroke=\"#dee3e8\" d=\"", .{percent});
            if (horizontal) try w.print("M{d:.2} {d:.2}V{d:.2}", .{ px, b.top, b.bottom }) else try w.print("M{d:.2} {d:.2}H{d:.2}", .{ Bounds.left, py, Bounds.right });
            try w.writeAll("\"/>");
        }
        try w.print("<path stroke=\"#75808a\" d=\"M{d:.2} {d:.2}{s}\"/><text data-percent=\"{d}\" data-quantile=\"{d}\" text-anchor=\"{s}\" x=\"{d:.2}\" y=\"{d:.2}\">{s}</text>", .{ px, py, if (horizontal) "v-4" else "h4", percent, position, if (horizontal) "middle" else "start", if (horizontal) px else px + 6, if (horizontal) py - 7 else py + 3, try label(a, percent) });
    }
    if (horizontal) try w.print("<path d=\"M{d} {d}H{d}\" stroke=\"#75808a\"/><text text-anchor=\"middle\" x=\"374\" y=\"{d}\">", .{ Bounds.left, b.top, Bounds.right, b.top - 24 }) else try w.print("<path d=\"M{d} {d}V{d}\" stroke=\"#75808a\"/><text text-anchor=\"middle\" transform=\"translate(714 {d}) rotate(90)\">", .{ Bounds.right, b.top, b.bottom, (b.bottom + b.top) / 2 });
    const axis_label = p.axes.percentile_label orelse try std.fmt.allocPrint(a, "{s} percentile", .{distributions.familyName(p.distribution.family)});
    try escaped(w, axis_label);
    try w.writeAll("</text></g>");
}
fn finitePoint(p: XY) bool {
    return std.math.isFinite(p.x) and std.math.isFinite(p.y);
}

fn series(w: *W, p: Plot, b: Bounds) !void {
    if (p.kind == .cdf) {
        try w.print("<path class=\"empirical\" d=\"M{d:.2} {d:.2}", .{ Bounds.left, b.py(0) });
        for (p.points, 0..) |v, i| {
            if (!plot_data.visiblePoint(p, i)) continue;
            try w.print(" H{d:.2} V{d:.2}", .{ b.px(v.x), b.py(v.y) });
        }
        try w.print(" H{d}\"/>\n", .{Bounds.right});
        if (p.cdf_overlay) {
            try w.writeAll("<path class=\"fitted\" d=\"");
            for (0..129) |i| {
                const x = b.x.at(@as(f64, @floatFromInt(i)) / 128);
                const y = p.distribution.cdf(x) * p.probability_scale;
                try w.print("{s}{d:.2} {d:.2} ", .{ if (i == 0) "M" else "L", b.px(x), b.py(y) });
            }
            try w.writeAll("\"/>\n");
        }
        return;
    }
    if (p.reference) |ref| {
        const q = if (p.rotated) b.y else b.x;
        const v0 = ref.intercept + ref.slope * q.lo;
        const v1 = ref.intercept + ref.slope * q.hi;
        try w.print("<path class=\"reference\" data-intercept=\"{d}\" data-slope=\"{d}\" d=\"M{d:.2} {d:.2}L{d:.2} {d:.2}\"/>\n", .{ ref.intercept, ref.slope, b.px(if (p.rotated) v0 else q.lo), b.py(if (p.rotated) q.lo else v0), b.px(if (p.rotated) v1 else q.hi), b.py(if (p.rotated) q.hi else v1) });
    }
    for (p.points, 0..) |point, i| {
        if (!plot_data.visiblePoint(p, i)) continue;
        const xy = coordinate(p, point);
        if (!finitePoint(xy)) continue;
        try w.print("<circle class=\"point\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"3.4\" data-x=\"{d}\" data-y=\"{d}\" data-observed=\"{d}\"/>\n", .{ b.px(xy.x), b.py(xy.y), point.x, point.y, point.observed });
    }
}
pub fn keyText(w: *W, keys: []const plot_data.Key, class: bool) !void {
    var separator: []const u8 = "";
    for (keys) |key| if (key.class == class) {
        try w.writeAll(separator);
        try escaped(w, key.column.label orelse key.column.name);
        try w.writeAll(" = ");
        try escaped(w, key.display);
        separator = "   ";
    };
}
fn graph(a: A, w: *W, panels: []const Plot) !void {
    const first = panels[0];
    const heading = switch (first.kind) {
        .cdf => "Cumulative Distribution Function",
        .pp => "P-P Plot",
        .qq => "Q-Q Plot",
        .probability => "Probability Plot",
    };
    const title = try first.title.value(a, first.global_title, heading, first.variable);
    const rowheight: f64 = if (first.square) Bounds.right - Bounds.left + 35 else if (panels.len == 1) 335 else 210;
    const axis_height: f64 = if (first.axes.percentile and !first.rotated) 40 else 0;
    const width: f64 = if (first.axes.percentile and first.rotated) 736 else 690;
    const height = 118 + (rowheight + axis_height) * @as(f64, @floatFromInt(panels.len));
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" role=\"img\" aria-labelledby=\"title\" data-kind=\"{s}\">\n<title id=\"title\">", .{ width, height, width, height, @tagName(first.kind) });
    try escaped(w, title);
    try w.writeAll("</title>\n<style>text{font-family:system-ui,sans-serif;fill:#1d2935;font-size:12px}.heading{font-size:18px;font-weight:600}.facet{font-weight:600}.axes path{stroke:#75808a;fill:none}.point{stroke:#244f85;fill:white;stroke-width:1.4}.empirical{fill:none;stroke:#244f85;stroke-width:2}.fitted,.reference{fill:none;stroke:#a25032;stroke-width:1.6}</style>\n");
    try w.print("<rect width=\"100%\" height=\"{d}\" fill=\"white\"/><text x=\"345\" y=\"25\" text-anchor=\"middle\" class=\"heading\">", .{height});
    try escaped(w, title);
    try w.writeAll("</text>\n<text x=\"88\" y=\"46\">");
    try keyText(w, first.keys, false);
    try w.writeAll("</text>\n");
    var x_range: Range = .{};
    var y_range: Range = .{};
    for (panels) |p| for (p.points) |point| {
        const q = coordinate(p, point);
        if (!finitePoint(q)) continue;
        x_range.add(q.x);
        y_range.add(q.y);
    };
    if (!std.math.isFinite(x_range.lo)) return error.InvalidPlot;
    if (first.kind == .probability) {
        const probability_axis = if (first.rotated) &y_range else &x_range;
        probability_axis.add(probabilityPosition(first, 0.01));
        probability_axis.add(probabilityPosition(first, 0.99));
    }
    x_range = x_range.padded();
    y_range = y_range.padded();
    if (first.kind == .pp) x_range = .{ .lo = 0, .hi = 1 };
    if (first.kind == .cdf or first.kind == .pp) y_range = .{ .lo = 0, .hi = first.probability_scale };
    for (panels, 0..) |p, i| {
        const top = 65 + axis_height + (rowheight + axis_height) * @as(f64, @floatFromInt(i));
        const b = Bounds{ .x = x_range, .y = y_range, .top = top, .bottom = top + rowheight - 35 };
        try w.print("<g class=\"panel\" data-panel=\"{d}\"><text class=\"facet\" x=\"88\" y=\"{d}\">", .{ i + 1, top - 4 - axis_height });
        try keyText(w, p.keys, true);
        try w.writeAll("</text>\n");
        if (p.kind == .pp or p.reference != null or (p.kind == .cdf and p.cdf_overlay)) {
            try w.print("<text class=\"fit-label\" x=\"660\" y=\"{d}\" text-anchor=\"end\">{s}", .{ top - 4 - axis_height, distributions.familyName(p.distribution.family) });
            for (try distributions.parameters(a, p.distribution)) |par| {
                if (par.symbol.len != 0) try w.print(" {s}={s}", .{ par.symbol, try label(a, par.value) });
            }
            try w.writeAll("</text>\n");
        }
        try axes(a, w, p, b);
        try extraAxes(a, w, p, b);
        try w.print("<clipPath id=\"clip{d}\"><rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/></clipPath><g clip-path=\"url(#clip{d})\">\n", .{ i, Bounds.left, top, Bounds.right - Bounds.left, b.bottom - top, i });
        try series(w, p, b);
        try w.writeAll("</g>");
        try drawInset(w, p.inset, b);
        try w.writeAll("</g>\n");
    }
    const variable = first.variable.label orelse first.variable.name;
    const observed = if (first.weibull2) try std.fmt.allocPrint(a, "Log {s}", .{variable}) else variable;
    const family = if (first.weibull2) "log-Weibull" else distributions.familyName(first.distribution.family);
    const axis_x = switch (first.kind) {
        .pp => try std.fmt.allocPrint(a, "{s} cumulative probability", .{family}),
        .qq => try std.fmt.allocPrint(a, "{s} quantile", .{family}),
        .probability => try std.fmt.allocPrint(a, "{s} percentile", .{family}),
        .cdf => observed,
    };
    const axis_y = switch (first.kind) {
        .pp => "Empirical cumulative probability",
        .cdf => if (first.probability_scale == 100) "Cumulative percent" else "Cumulative probability",
        else => observed,
    };
    try w.print("<text class=\"axis-x\" x=\"374\" y=\"{d}\" text-anchor=\"middle\">", .{height - 14});
    try escaped(w, if (first.rotated) axis_y else axis_x);
    try w.writeAll("</text>\n");
    try w.print("<text class=\"axis-y\" transform=\"translate(18 {d}) rotate(-90)\" text-anchor=\"middle\">", .{height / 2});
    try escaped(w, if (first.rotated) axis_x else axis_y);
    try w.writeAll("</text>\n</svg>\n");
}
pub fn render(a: A, panels: []const Plot) diag.Error![]const u8 {
    var writer: W.Allocating = .init(a);
    graph(a, &writer.writer, panels) catch |e| return if (e == error.InvalidPlot) error.ExecError else error.OutOfMemory;
    return writer.written();
}

pub fn drawInset(w: *W, box: @import("univ_graph_annotations.zig").Box, b: Bounds) !void {
    if (box.lines.len == 0) return;
    var chars: usize = box.header.len;
    for (box.lines) |l| chars = @max(chars, l.key.len + l.value.len + 3);
    const width = @min(540, @max(84, 16 + 7 * @as(f64, @floatFromInt(chars))));
    const height = 11 + 16 * @as(f64, @floatFromInt(box.lines.len + @intFromBool(box.header.len > 0)));
    const x = switch (box.pos) {
        .nw, .w, .sw => Bounds.left + 9,
        .ne, .e, .se => Bounds.right - width - 9,
        .n, .s => (Bounds.left + Bounds.right - width) / 2,
    };
    const y = switch (box.pos) {
        .nw, .n, .ne => b.top + 8,
        .sw, .s, .se => b.bottom - height - 8,
        .w, .e => (b.top + b.bottom - height) / 2,
    };
    try w.print("<g class=\"inset\" data-pos=\"{s}\"><rect x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"white\" stroke=\"#82909a\"/>", .{ @tagName(box.pos), x, y, width, height });
    var baseline = y + 16;
    if (box.header.len > 0) {
        try w.print("<text x=\"{d:.2}\" y=\"{d:.2}\" font-weight=\"600\">", .{ x + 7, baseline });
        try escaped(w, box.header);
        try w.writeAll("</text>");
        baseline += 16;
    }
    for (box.lines) |l| {
        try w.print("<text x=\"{d:.2}\" y=\"{d:.2}\">", .{ x + 7, baseline });
        try escaped(w, l.key);
        try w.print("</text><text text-anchor=\"end\" x=\"{d:.2}\" y=\"{d:.2}\">", .{ x + width - 7, baseline });
        try escaped(w, l.value);
        try w.writeAll("</text>");
        baseline += 16;
    }
    try w.writeAll("</g>\n");
}
