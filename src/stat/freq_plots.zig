//! Graphics consumers of FREQ's ordered weighted tables. SAS Statistical
//! Procedures pp. 127–140; Bangdiwala and Bryan (1987), agreement chart.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const freq = @import("freq.zig");
const tm = @import("freq_table.zig");
const stat = @import("freq_tests.zig");
const lex = @import("../lexer.zig");
const svg = @import("graphics_svg.zig");
const risk = @import("freq_risk.zig");
const strat = @import("freq_stratified.zig");
const A = std.mem.Allocator;
const W = std.Io.Writer;
const eq = std.ascii.eqlIgnoreCase;
const Kind = enum { freqplot, cumfreqplot, deviationplot, mosaicplot, agreeplot, relriskplot, oddsratioplot };
pub const LogBase = enum { none, two, e, ten };
const Order = enum { table, ascending, descending };
const Layout = enum { cluster, groupvertical, grouphorizontal, stacked };
const Scale = enum { freq, percent, grouppercent };
const Plot = struct { kind: Kind, scale: Scale = .freq, layout: Layout = .groupvertical, dot: bool = false, horizontal: bool = false, byrow: bool = false, nostat: bool = false, legend: bool = true, partial: bool = true, showscale: bool = true, square: bool = false, stats: bool = false, second_column: bool = false, common: bool = true, logbase: LogBase = .none, order: Order = .table };
pub const Options = struct {
    plots: []const Plot = &.{},
    only: bool = false,
};
fn token(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn tagOf(comptime E: type, v: []const u8) ?E {
    inline for (std.meta.tags(E)) |tag| if (eq(v, @tagName(tag))) return tag;
    return null;
}
pub fn parse(a: A, d: *diag.Diagnostics, t: []const lex.Token, i: *usize) diag.Error!Options {
    var opt = Options{};
    var list: std.ArrayList(Plot) = .empty;
    i.* += 1;
    if (token(t, i.*, .lparen)) {
        if (!token(t, i.* + 1, .name) or !eq(t[i.* + 1].text, "only") or !token(t, i.* + 2, .rparen)) return proc.failGap(d, 0, "PROC FREQ: unsupported global PLOTS option", .{});
        opt.only = true;
        i.* += 3;
    }
    if (!token(t, i.*, .eq)) return d.fail(error.ParseError, 0, "PROC FREQ: expected = in plot request", .{});
    i.* += 1;
    const grouped = token(t, i.*, .lparen);
    if (grouped) i.* += 1;
    while (true) {
        if (!token(t, i.*, .name)) return d.fail(error.ParseError, 0, "PROC FREQ: expected plot name", .{});
        const name = t[i.*].text;
        i.* += 1;
        if (eq(name, "none")) {
            opt.only = true;
            list.clearRetainingCapacity();
        } else {
            var orientation: ?bool = null;
            var p = Plot{ .kind = tagOf(Kind, name) orelse {
                // S154 Table 47.23 graphs without a renderer are gaps; any other name is the user's error.
                for ([_][]const u8{ "all", "kappaplot", "wtkappaplot", "riskdiffplot" }) |documented| if (eq(name, documented)) return proc.failGap(d, 0, "PROC FREQ: unsupported plot request {s}", .{name});
                return d.fail(error.ParseError, 0, "PROC FREQ: unknown plot request {s}", .{name});
            } };
            if (token(t, i.*, .lparen)) {
                i.* += 1;
                while (!token(t, i.*, .rparen)) {
                    if (!token(t, i.*, .name)) return d.fail(error.ParseError, 0, "PROC FREQ: expected plot option", .{});
                    const key = t[i.*].text;
                    i.* += 1;
                    if (isRatio(p.kind)) {
                        try ratioOption(d, t, i, &p, name, key);
                        continue;
                    }
                    if (p.kind == .deviationplot and eq(key, "nostat")) {
                        p.nostat = true;
                        continue;
                    }
                    if (p.kind == .mosaicplot and eq(key, "square")) {
                        p.square = true;
                        continue;
                    }
                    if (!token(t, i.*, .eq) or !token(t, i.* + 1, .name)) return d.fail(error.ParseError, 0, "PROC FREQ: invalid {s} plot option", .{key});
                    const v = t[i.* + 1].text;
                    i.* += 2;
                    const cart = p.kind == .freqplot or p.kind == .cumfreqplot or p.kind == .deviationplot;
                    if (cart and eq(key, "orient") and (eq(v, "horizontal") or eq(v, "vertical"))) orientation = eq(v, "horizontal") else if (cart and eq(key, "type") and (eq(v, "dotplot") or eq(v, "barchart"))) p.dot = eq(v, "dotplot") else if ((p.kind == .freqplot or p.kind == .cumfreqplot) and eq(key, "scale")) p.scale = tagOf(Scale, v) orelse return proc.failGap(d, 0, "PROC FREQ: unsupported plot scale {s}", .{v}) else if (p.kind == .freqplot and eq(key, "twoway")) p.layout = tagOf(Layout, v) orelse return d.fail(error.ParseError, 0, "PROC FREQ: invalid TWOWAY={s}", .{v}) else if (p.kind == .freqplot and eq(key, "groupby") and (eq(v, "row") or eq(v, "column"))) p.byrow = eq(v, "row") else if (p.kind == .agreeplot and (eq(v, "yes") or eq(v, "no"))) {
                        if (eq(key, "legend")) p.legend = eq(v, "yes") else if (eq(key, "partial")) p.partial = eq(v, "yes") else if (eq(key, "showscale")) p.showscale = eq(v, "yes") else return proc.failGap(d, 0, "PROC FREQ: unsupported AGREEPLOT option {s}", .{key});
                    } else return proc.failGap(d, 0, "PROC FREQ: unsupported {s} plot option {s}={s}", .{ name, key, v });
                }
                i.* += 1;
            }
            p.horizontal = orientation orelse p.dot;
            if (p.dot and p.layout == .cluster) return d.fail(error.ParseError, 0, "PROC FREQ: CLUSTER is unavailable for dot plots", .{});
            try list.append(a, p);
        }
        if (!grouped) break;
        if (token(t, i.*, .rparen)) {
            i.* += 1;
            break;
        }
    }
    opt.plots = list.items;
    return opt;
}

fn isRatio(kind: Kind) bool {
    return kind == .relriskplot or kind == .oddsratioplot;
}
/// Plot options of S154 Table 47.17 (physical p.3136). Documented options
/// without a renderer are loud gaps; anything else is a user error.
fn ratioOption(d: *diag.Diagnostics, t: []const lex.Token, i: *usize, p: *Plot, name: []const u8, key: []const u8) diag.Error!void {
    if (eq(key, "stats")) {
        p.stats = true;
        return;
    }
    if (eq(key, "exact")) return proc.failGap(d, 0, "PROC FREQ: unsupported {s} plot option EXACT", .{name});
    if (!token(t, i.*, .eq)) return d.fail(error.ParseError, 0, "PROC FREQ: invalid {s} plot option {s}", .{ name, key });
    i.* += 1;
    if (eq(key, "range") or eq(key, "cldisplay") or eq(key, "npanelpos")) return proc.failGap(d, 0, "PROC FREQ: unsupported {s} plot option {s}=", .{ name, key });
    if (!token(t, i.*, .name) and !token(t, i.*, .number)) return d.fail(error.ParseError, 0, "PROC FREQ: invalid {s} plot option {s}", .{ name, key });
    const v = t[i.*].text;
    i.* += 1;
    if (eq(key, "column") and p.kind == .relriskplot and (eq(v, "1") or eq(v, "2"))) {
        p.second_column = eq(v, "2");
    } else if (eq(key, "logbase") and (eq(v, "2") or eq(v, "e") or eq(v, "10"))) {
        p.logbase = if (eq(v, "2")) .two else if (eq(v, "e")) .e else .ten;
    } else if (eq(key, "order") and (eq(v, "ascending") or eq(v, "descending"))) {
        p.order = if (eq(v, "ascending")) .ascending else .descending;
    } else if (eq(key, "common") and (eq(v, "yes") or eq(v, "no"))) {
        p.common = eq(v, "yes");
    } else if (eq(key, "cl") and eq(v, "wald")) {
        // The default limit type.
    } else if (eq(key, "cl") and (eq(v, "exact") or eq(v, "lr") or eq(v, "score") or eq(v, "waldmodified") or (eq(v, "midp") and p.kind == .oddsratioplot))) {
        return proc.failGap(d, 0, "PROC FREQ: unsupported {s} plot option CL={s}", .{ name, v });
    } else return d.fail(error.ParseError, 0, "PROC FREQ: invalid {s} plot option {s}={s}", .{ name, key, v });
}

const palette = [_][]const u8{ "#829dc5", "#d89883", "#81b0a3", "#c9ad66", "#ad97bd", "#a0a19c" };
fn text(w: *W, x: f64, y: f64, value: []const u8, anchor: []const u8) !void {
    try w.print("<text x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"{s}\">", .{ x, y, anchor });
    try svg.escaped(w, value);
    try w.writeAll("</text>");
}
fn title(w: *W, kind: Kind, heading: []const u8, subtitle: []const u8, width: f64, height: f64) !void {
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" role=\"img\" data-kind=\"{s}\"><title>", .{ width, height, width, height, @tagName(kind) });
    try svg.escaped(w, heading);
    try w.writeAll("</title><style>text{font:12px system-ui,sans-serif;fill:#1d2935}.heading{font-size:18px;font-weight:600}.axes path{stroke:#84909c;fill:none}.grid{stroke:#dde3e8}.bar,.tile{stroke:#677c90;stroke-width:.75}.dot{stroke:white;stroke-width:1}</style>");
    try w.print("<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text class=\"heading\" text-anchor=\"middle\" x=\"{d}\" y=\"23\">", .{width / 2});
    try svg.escaped(w, heading);
    try w.writeAll("</text>");
    if (subtitle.len > 0) try text(w, width / 2, 42, subtitle, "middle");
}
fn level(a: A, l: tm.Level) ![]const u8 {
    return switch (l.value) {
        .str => |v| std.mem.trimEnd(u8, v, " "),
        .num => |v| if (std.math.isNan(v)) "." else try svg.label(a, v),
    };
}
fn subheading(a: A, by: []const u8, tab: *const tm.Table, stratum: usize) ![]const u8 {
    var out: W.Allocating = .init(a);
    try out.writer.writeAll(by);
    const n = tab.dimensions.len;
    if (n <= 2) return out.written();
    const key = stratum * tab.dimensions[n - 2].levels.len * tab.dimensions[n - 1].levels.len;
    for (tab.dimensions[0 .. n - 2], 0..) |dim, i| {
        if (out.written().len > 0) try out.writer.writeAll("    ");
        try out.writer.print("{s} = {s}", .{ dim.name, try level(a, tab.level(key, i)) });
    }
    return out.written();
}
const Rect = struct { x: f64, y: f64, w: f64, h: f64 };
fn rect(w: *W, r: Rect, class: []const u8, color: []const u8, count: f64, value: f64) !void {
    try w.print("<rect class=\"{s}\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"{s}\" data-count=\"{d}\" data-value=\"{d}\"/>", .{ class, r.x, r.y, @max(0, r.w), @max(0, r.h), color, count, value });
}
fn mark(w: *W, r: Rect, from: f64, to: f64, index: f64, spacing: f64, range: svg.Range, dot: bool, horizontal: bool, color: []const u8, count: f64, value: f64) !void {
    const lo = (from - range.lo) / (range.hi - range.lo);
    const hi = (to - range.lo) / (range.hi - range.lo);
    const x = if (horizontal) r.x + r.w * hi else r.x + index * r.w;
    const y = if (horizontal) r.y + r.h * (1 - index) else r.y + r.h * (1 - hi);
    if (dot) try w.print("<circle class=\"dot\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"4\" fill=\"{s}\" data-count=\"{d}\" data-value=\"{d}\"/>", .{ x, y, color, count, value }) else {
        const bar = if (horizontal) Rect{ .x = r.x + r.w * @min(lo, hi), .y = y - r.h * spacing / 2, .w = r.w * @abs(hi - lo), .h = r.h * spacing } else Rect{ .x = x - r.w * spacing / 2, .y = r.y + r.h * (1 - @max(lo, hi)), .w = r.w * spacing, .h = r.h * @abs(hi - lo) };
        try rect(w, bar, "bar", color, count, value);
    }
}
fn tickStep(range: svg.Range) f64 {
    const ideal = (range.hi - range.lo) / 5;
    const decade = std.math.pow(f64, 10, @floor(@log10(ideal)));
    const scale = ideal / decade;
    return decade * @as(f64, if (scale < 1.5) 1 else if (scale < 3) 2 else if (scale < 7) 5 else 10);
}
fn roundedRange(range: svg.Range) svg.Range {
    const step = tickStep(range);
    return .{ .lo = @floor(range.lo / step) * step, .hi = @ceil(range.hi / step) * step };
}
fn axes(a: A, w: *W, r: Rect, yr: svg.Range, horizontal: bool) !void {
    try w.print("<g class=\"axes\"><path d=\"M{d} {d}v{d}h{d}\"/>", .{ r.x, r.y, r.h, r.w });
    const step = tickStep(yr);
    const first = @ceil(yr.lo / step) * step;
    for (0..12) |i| {
        const v = first + @as(f64, @floatFromInt(i)) * step;
        if (v > yr.hi + step * 1e-10) break;
        const u = (v - yr.lo) / (yr.hi - yr.lo);
        const x = if (horizontal) r.x + u * r.w else r.x;
        const y = if (horizontal) r.y + r.h else r.y + r.h * (1 - u);
        try w.print("<line class=\"grid\" x1=\"{d:.2}\" y1=\"{d:.2}\" x2=\"{d:.2}\" y2=\"{d:.2}\"/>", .{ x, y, if (horizontal) x else x + r.w, if (horizontal) y - r.h else y });
        try text(w, if (horizontal) x else x - 7, if (horizontal) y + 16 else y + 4, try svg.label(a, v), if (horizontal) "middle" else "end");
    }
    try w.writeAll("</g>");
}
fn standardHeading(a: A, kind: Kind, rows: tm.Dimension, columns: ?tm.Dimension) ![]const u8 {
    const lead: []const u8 = switch (kind) {
        .freqplot, .mosaicplot => "Distribution of",
        .cumfreqplot => "Cumulative Distribution of",
        .deviationplot => "Deviations of",
        .agreeplot => "Agreement of",
        .relriskplot, .oddsratioplot => unreachable,
    };
    if (columns) |col| return std.fmt.allocPrint(a, "{s} {s} {s} {s}", .{ lead, rows.name, if (kind == .agreeplot) "and" else "by", col.name });
    return std.fmt.allocPrint(a, "{s} {s}", .{ lead, rows.name });
}
fn category(w: *W, r: Rect, pos: f64, s: []const u8, horizontal: bool) !void {
    try text(w, if (horizontal) r.x - 8 else r.x + r.w * pos, if (horizontal) r.y + r.h * (1 - pos) + 4 else r.y + r.h + 18, s, if (horizontal) "end" else "middle");
}
fn axisTitles(w: *W, r: Rect, x: []const u8, y: []const u8) !void {
    try text(w, r.x + r.w / 2, r.y + r.h + 45, x, "middle");
    try w.print("<text transform=\"translate(19 {d}) rotate(-90)\" text-anchor=\"middle\">", .{r.y + r.h / 2});
    try svg.escaped(w, y);
    try w.writeAll("</text>");
}
fn one(a: A, tab: *const tm.Table, req: freq.Request, p: Plot, sc: tm.ScoredMatrix, sub: []const u8) ![]const u8 {
    const counts = sc.matrix.counts;
    var total: f64 = 0;
    for (counts) |c| total += c;
    const values = try a.alloc(f64, counts.len);
    var cum: f64 = 0;
    var yr = svg.Range{ .lo = 0, .hi = 0 };
    const gof = if (p.kind == .deviationplot) try stat.goodnessOfFit(counts, req.resolved_expected, req.statistics.df) else null;
    const factor = if (gof != null) try stat.expectedFactor(counts.len, total, req.resolved_expected) else 1;
    for (counts, values, 0..) |c, *v, i| {
        cum += c;
        v.* = if (gof != null) blk: {
            const e = switch (req.resolved_expected) {
                .equal => total / @as(f64, @floatFromInt(counts.len)),
                .proportions, .frequencies => |list| list[i] * factor,
            };
            break :blk (c - e) / e;
        } else (if (p.kind == .cumfreqplot) cum else c) * (if (p.scale == .percent) 100 / total else 1);
        yr.add(v.*);
    }
    if (yr.hi == yr.lo) yr.hi = yr.lo + 1;
    yr = roundedRange(yr);
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    const dim = tab.dimensions[0];
    try title(w, p.kind, try standardHeading(a, p.kind, dim, null), sub, 690, 454);
    const r = Rect{ .x = 91, .y = 62, .w = 555, .h = 310 };
    try axes(a, w, r, yr, p.horizontal);
    const n = if (req.maxlevels) |max| if (p.kind == .freqplot) @min(max, counts.len) else counts.len else counts.len;
    for (values[0..n], counts[0..n], sc.row_levels[0..n], 0..) |v, c, l, i| {
        const k = @as(f64, @floatFromInt(n));
        const pos = (@as(f64, @floatFromInt(i)) + 0.5) / k;
        try category(w, r, pos, try level(a, l), p.horizontal);
        try mark(w, r, 0, v, pos, 0.78 / k, yr, p.dot, p.horizontal, palette[0], c, v);
    }
    const quantity: []const u8 = if (gof != null) "Relative Deviation" else if (p.scale == .percent) "Percent" else "Frequency";
    const dim_name = dim.label orelse dim.name;
    try axisTitles(w, r, if (p.horizontal) quantity else dim_name, if (p.horizontal) dim_name else quantity);
    if (gof) |g| if (!p.nostat and std.math.isFinite(g.pearson.p)) {
        const prob = try @import("../format.zig").apply(a, .{ .num = g.pearson.p }, "PVALUE6.4");
        try text(w, 91, 442, try std.fmt.allocPrint(a, "Pr > ChiSq   {s}", .{std.mem.trim(u8, prob, " ")}), "start");
    };
    try w.writeAll("</svg>");
    return out.written();
}

const Grid = struct {
    sc: tm.ScoredMatrix,
    rows: []const f64,
    cols: []const f64,
    total: f64,
    fn init(a: A, sc: tm.ScoredMatrix) !Grid {
        const m = sc.matrix;
        const rows = try a.alloc(f64, m.rows);
        const cols = try a.alloc(f64, m.cols);
        @memset(rows, 0);
        @memset(cols, 0);
        var total: f64 = 0;
        for (0..m.rows) |r| for (0..m.cols) |c| {
            const value = m.counts[r * m.cols + c];
            rows[r] += value;
            cols[c] += value;
            total += value;
        };
        return .{ .sc = sc, .rows = rows, .cols = cols, .total = total };
    }
    fn at(g: Grid, r: usize, c: usize) f64 {
        return g.sc.matrix.counts[r * g.sc.matrix.cols + c];
    }
    fn v(g: Grid, r: usize, c: usize, p: Plot) f64 {
        const count = g.at(r, c);
        const denom = if (p.byrow) g.rows[r] else g.cols[c];
        return switch (p.scale) {
            .freq => count,
            .percent => count / g.total * 100,
            .grouppercent => if (denom > 0) count / denom * 100 else 0,
        };
    }
};
// A vertical panel layout puts the table's row levels on the Y axis.
// Turning each graph cell horizontally exchanges category and panel roles.
fn rowsOnAxis(p: Plot) bool {
    const transposed = (p.layout == .groupvertical and p.horizontal) or (p.layout == .grouphorizontal and !p.horizontal);
    return p.byrow != transposed;
}
fn twoFrequency(a: A, p: Plot, g: Grid, row: tm.Dimension, col: tm.Dimension, subtitle: []const u8, start: usize, nfacets: usize) ![]const u8 {
    const rows_on_axis = rowsOnAxis(p);
    const cats = if (rows_on_axis) g.sc.row_levels else g.sc.col_levels;
    const series = if (rows_on_axis) g.sc.col_levels else g.sc.row_levels;
    const dim = if (rows_on_axis) row else col;
    const other = if (rows_on_axis) col else row;
    const panels = p.layout == .groupvertical or p.layout == .grouphorizontal;
    const npc = if (panels) nfacets else 1;
    const across = p.layout == .grouphorizontal;
    const width: f64 = if (across) 110 + @as(f64, @floatFromInt(npc)) * 235 else 690;
    const height: f64 = if (panels and !across) 113 + @as(f64, @floatFromInt(npc)) * 165 else 465;
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try title(w, p.kind, try standardHeading(a, p.kind, row, col), subtitle, width, height);
    var max: f64 = 0;
    for (0..cats.len) |i| {
        var sum: f64 = 0;
        for (0..series.len) |j| {
            const v = g.v(if (rows_on_axis) i else j, if (rows_on_axis) j else i, p);
            max = @max(max, v);
            sum += v;
        }
        if (p.layout == .stacked and !p.dot) max = @max(max, sum);
    }
    const yr = roundedRange(.{ .lo = 0, .hi = if (max > 0) max else 1 });
    const categorical = dim.label orelse dim.name;
    const quantity: []const u8 = if (p.scale == .freq) "Frequency" else "Percent";
    for (0..npc) |pi| {
        const rect_ = Rect{ .x = if (across) 85 + 235 * @as(f64, @floatFromInt(pi)) else 89, .y = if (panels and !across) 78 + 165 * @as(f64, @floatFromInt(pi)) else 72, .w = if (across) 210 else 550, .h = if (panels and !across) 120 else 285 };
        try w.writeAll("<g class=\"panel\">");
        if (panels) try text(w, rect_.x, rect_.y - 7, try std.fmt.allocPrint(a, "{s} = {s}", .{ other.name, try level(a, series[start + pi]) }), "start");
        try axes(a, w, rect_, yr, p.horizontal);
        for (cats, 0..) |l, i| {
            const nc = @as(f64, @floatFromInt(cats.len));
            const middle = (@as(f64, @floatFromInt(i)) + 0.5) / nc;
            try category(w, rect_, middle, try level(a, l), p.horizontal);
            const from = if (panels) start + pi else 0;
            const end = if (panels) from + 1 else series.len;
            var base: f64 = 0;
            for (from..end) |j| {
                const rr = if (rows_on_axis) i else j;
                const cc = if (rows_on_axis) j else i;
                const v = g.v(rr, cc, p);
                const ns = @as(f64, @floatFromInt(series.len));
                const pos = if (p.layout == .cluster) middle + ((@as(f64, @floatFromInt(j)) + 0.5) / ns - 0.5) * 0.86 / nc else middle;
                const band = 0.86 / nc / (if (p.layout == .cluster) ns else 1);
                try mark(w, rect_, base, base + v, pos, band, yr, p.dot, p.horizontal, palette[j % palette.len], g.at(rr, cc), v);
                if (p.layout == .stacked and !p.dot) base += v;
            }
        }
        if (pi + 1 == npc) try axisTitles(w, rect_, if (p.horizontal) quantity else categorical, if (p.horizontal) categorical else quantity);
        try w.writeAll("</g>");
    }
    if (!panels) {
        const spacing = (width - 100) / @as(f64, @floatFromInt(series.len));
        for (series, 0..) |l, j| {
            const x = 60 + @as(f64, @floatFromInt(j)) * spacing;
            try w.print("<rect x=\"{d:.2}\" y=\"{d}\" width=\"9\" height=\"9\" fill=\"{s}\"/>", .{ x, height - 25, palette[j % palette.len] });
            try text(w, x + 12, height - 17, try std.fmt.allocPrint(a, "{s} = {s}", .{ other.name, try level(a, l) }), "start");
        }
    }
    try w.writeAll("</svg>");
    return out.written();
}
fn mosaic(a: A, p: Plot, g: Grid, row: tm.Dimension, col: tm.Dimension, sub: []const u8) ![]const u8 {
    const r = Rect{ .x = 90, .y = 58, .w = if (p.square) 390 else 545, .h = 390 };
    const width = r.w + 145;
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try title(w, p.kind, try standardHeading(a, p.kind, row, col), sub, width, 515);
    var begin_x: f64 = 0;
    for (g.cols, g.sc.col_levels, 0..) |margin, l, c| {
        if (margin == 0) continue;
        const panel_w = r.w * margin / g.total;
        const x = r.x + begin_x / g.total * r.w;
        var begin_y: f64 = 0;
        for (g.rows, 0..) |_, i| {
            const n = g.at(i, c);
            const height = r.h * n / margin;
            if (n > 0) try rect(w, .{ .x = x + 1, .y = r.y + begin_y / margin * r.h + 1, .w = @max(0, panel_w - 2), .h = @max(0, height - 2) }, "tile", palette[(g.rows.len - 1 - i) % palette.len], n, n / g.total);
            if (c == 0 and n > 0) try text(w, r.x - 6, r.y + (begin_y + n / 2) / margin * r.h + 4, try level(a, g.sc.row_levels[i]), "end");
            begin_y += n;
        }
        try text(w, x + panel_w / 2, r.y + r.h + 20, try level(a, l), "middle");
        begin_x += margin;
    }
    try axisTitles(w, r, col.label orelse col.name, row.label orelse row.name);
    try w.writeAll("</svg>");
    return out.written();
}
fn agreement(a: A, p: Plot, g: Grid, row: tm.Dimension, col: tm.Dimension, sub: []const u8) ![]const u8 {
    const r = Rect{ .x = 102, .y = 64, .w = 400, .h = 400 };
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try title(w, p.kind, try standardHeading(a, p.kind, row, col), sub, 620, 549);
    const scale = r.w / g.total;
    var row0: f64 = 0;
    var col0: f64 = 0;
    try w.print("<rect class=\"frame\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"none\" stroke=\"#86909a\"/>", .{ r.x, r.y, r.w, r.h });
    for (g.rows, g.cols, 0..) |rows, cols, i| {
        // Successive agreement bands are nested rectangles of row and
        // column counts within a given distance of the diagonal cell.
        var band = if (p.partial) g.rows.len else @as(usize, 1);
        while (band > 0) {
            band -= 1;
            var left = row0;
            var bottom = col0;
            var wide: f64 = 0;
            var high: f64 = 0;
            for (0..g.rows.len) |j| {
                if (j + band < i) {
                    left += g.at(i, j);
                    bottom += g.at(j, i);
                }
                if (j + band >= i and j <= i + band) {
                    wide += g.at(i, j);
                    high += g.at(j, i);
                }
            }
            const shade: []const u8 = if (band == 0) "#8eafcf" else if (band == 1) "#d0e2ee" else "#eff5f9";
            try rect(w, .{ .x = r.x + left * scale, .y = r.y + r.h - (bottom + high) * scale, .w = wide * scale, .h = high * scale }, if (band == 0) "exact" else "partial", shade, g.at(i, i), wide * high);
        }
        try w.print("<rect class=\"margin\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\" fill=\"none\" stroke=\"#6989a8\"/>", .{ r.x + row0 * scale, r.y + r.h - (col0 + cols) * scale, rows * scale, cols * scale });
        try text(w, r.x + (row0 + rows / 2) * scale, r.y + r.h + 18, try level(a, g.sc.row_levels[i]), "middle");
        try text(w, r.x - 7, r.y + r.h - (col0 + cols / 2) * scale + 3, try level(a, g.sc.col_levels[i]), "end");
        row0 += rows;
        col0 += cols;
    }
    try w.print("<path class=\"diagonal\" d=\"M{d} {d}l{d} -{d}\" stroke=\"#899fb7\"/>", .{ r.x, r.y + r.h, r.w, r.h });
    if (p.showscale) {
        for (0..5) |i| {
            const t = @as(f64, @floatFromInt(i)) / 4;
            try text(w, r.x + r.w + 7, r.y + r.h * (1 - t) + 4, try svg.label(a, t * g.total), "start");
        }
        try w.print("<text text-anchor=\"middle\" transform=\"translate(557 {d}) rotate(-90)\">Cumulative Frequency</text>", .{r.y + r.h / 2});
    }
    try axisTitles(w, r, row.label orelse row.name, col.label orelse col.name);
    if (p.legend) {
        try text(w, 125, 536, "Exact agreement", "start");
        try w.writeAll("<rect x=\"106\" y=\"526\" width=\"11\" height=\"11\" fill=\"#8eafcf\"/>");
        if (p.partial) {
            try text(w, 290, 536, "Partial agreement", "start");
            try w.writeAll("<rect x=\"270\" y=\"526\" width=\"11\" height=\"11\" fill=\"#d0e2ee\"/>");
        }
    }
    try w.writeAll("</svg>");
    return out.written();
}
fn applicable(kind: Kind, req: freq.Request, n: usize) bool {
    return switch (kind) {
        .freqplot => true,
        .cumfreqplot => n == 1,
        .deviationplot => n == 1 and req.statistics.chisq,
        .mosaicplot => n >= 2,
        .agreeplot => n >= 2 and req.stratified.agreement.enabled,
        // Summary graphs: one per multiway table, never per stratum.
        .relriskplot, .oddsratioplot => false,
    };
}
pub const RatioRow = struct { label: []const u8, value: ?f64 = null, lower: ?f64 = null, upper: ?f64 = null, common: bool = false };
/// Stratum Wald ratios plus, optionally, the Mantel-Haenszel common ratio.
/// Both come unchanged from the listing kernels (S154 physical pp.3204-3207,
/// 3234-3236); no estimate is recomputed here.
pub fn ratioRows(a: A, p: Plot, labels: []const []const u8, matrices: []const strat.Matrix, alpha: f64, with_common: bool) diag.Error![]RatioRow {
    var rows: std.ArrayList(RatioRow) = .empty;
    const column: risk.Column = if (p.second_column) .second else .first;
    for (labels, matrices) |name, m| {
        if (m.rows != 2 or m.cols != 2) return error.ExecError;
        var row = RatioRow{ .label = name };
        if (risk.ratio(.{ .cells = m.counts[0..4].* }, column, if (p.kind == .oddsratioplot) .odds_ratio else .relative_risk, alpha, .wald, false)) |v| {
            if (v.estimate) |e| if (std.math.isFinite(e)) {
                row.value = e;
                row.lower = v.limits.lower;
                row.upper = v.limits.upper;
            };
        } else |_| {}
        try rows.append(a, row);
    }
    if (p.order != .table) std.mem.sort(RatioRow, rows.items, p.order, struct {
        fn before(order: Order, x: RatioRow, y: RatioRow) bool {
            const u = x.value orelse return false;
            const v = y.value orelse return true;
            return if (order == .ascending) u < v else u > v;
        }
    }.before);
    if (with_common) {
        const mh = try strat.mantelHaenszelRatios(matrices, alpha);
        const common = if (p.kind == .oddsratioplot) mh.odds else if (p.second_column) mh.column2 else mh.column1;
        if (common) |v| try rows.append(a, .{ .label = "Common", .value = v.value, .lower = v.lower, .upper = v.upper, .common = true });
    }
    return rows.toOwnedSlice(a);
}
fn axisValue(v: f64, base: LogBase) f64 {
    return switch (base) {
        .none => v,
        .two => @log2(v),
        .e => @log(v),
        .ten => @log10(v),
    };
}
/// Axis extent in axis units: data units, or exponents on a LOGBASE= axis.
/// The null value one is always inside the extent.
pub fn ratioRange(rows: []const RatioRow, base: LogBase) svg.Range {
    var range = svg.Range{ .lo = axisValue(1, base), .hi = axisValue(1, base) };
    for (rows) |row| for ([_]?f64{ row.value, row.lower, row.upper }) |item| {
        const v = item orelse continue;
        if (!std.math.isFinite(v) or (base != .none and v <= 0)) continue;
        range.add(axisValue(v, base));
    };
    if (base == .none) {
        range.lo = @min(range.lo, 0);
        if (range.hi == range.lo) range.hi = range.lo + 1;
        return roundedRange(range);
    }
    range = .{ .lo = @floor(range.lo), .hi = @ceil(range.hi) };
    if (range.hi == range.lo) range.hi += 1;
    return range;
}
/// Fraction of the axis length at which a ratio is drawn.
pub fn ratioPosition(v: f64, range: svg.Range, base: LogBase) f64 {
    if (base != .none and v <= 0) return 0;
    return std.math.clamp((axisValue(v, base) - range.lo) / (range.hi - range.lo), 0, 1);
}
const ratio_row_height: f64 = 34;
fn ratioRect(p: Plot, count: usize) Rect {
    return .{ .x = 150, .y = 62, .w = if (p.stats) 300 else 490, .h = ratio_row_height * @as(f64, @floatFromInt(@max(count, 1))) };
}
pub fn ratioSvg(a: A, p: Plot, rows: []const RatioRow, sub: []const u8, alpha: f64) ![]const u8 {
    const odds = p.kind == .oddsratioplot;
    const statistic: []const u8 = if (odds) "Odds Ratio" else "Relative Risk";
    const percent = try svg.label(a, 100 * (1 - alpha));
    const r = ratioRect(p, rows.len);
    const range = ratioRange(rows, p.logbase);
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try title(w, p.kind, try std.fmt.allocPrint(a, "{s}s with {s}% Wald Confidence Limits", .{ statistic, percent }), sub, 690, r.y + r.h + 70);
    try w.print("<g class=\"axes\" data-scale=\"{s}\"><path d=\"M{d} {d}v{d}h{d}\"/>", .{ if (p.logbase == .none) "linear" else @tagName(p.logbase), r.x, r.y, r.h, r.w });
    const step: f64 = if (p.logbase == .none) tickStep(range) else @max(1, @ceil((range.hi - range.lo) / 8));
    var tick = @ceil(range.lo / step) * step;
    while (tick <= range.hi + step * 1e-10) : (tick += step) {
        const x = r.x + r.w * (tick - range.lo) / (range.hi - range.lo);
        const shown = switch (p.logbase) {
            .none => tick,
            .two => std.math.pow(f64, 2, tick),
            .e => @exp(tick),
            .ten => std.math.pow(f64, 10, tick),
        };
        try w.print("<line class=\"grid\" x1=\"{d:.2}\" y1=\"{d:.2}\" x2=\"{d:.2}\" y2=\"{d:.2}\"/>", .{ x, r.y, x, r.y + r.h });
        try text(w, x, r.y + r.h + 16, try svg.label(a, shown), "middle");
    }
    try w.writeAll("</g>");
    const one_x = r.x + r.w * ratioPosition(1, range, p.logbase);
    try w.print("<line class=\"reference\" data-value=\"1\" x1=\"{d:.2}\" y1=\"{d:.2}\" x2=\"{d:.2}\" y2=\"{d:.2}\" stroke=\"#84909c\" stroke-dasharray=\"4 3\"/>", .{ one_x, r.y, one_x, r.y + r.h });
    if (p.stats) {
        try text(w, r.x + r.w + 62, r.y - 8, statistic, "end");
        try text(w, r.x + r.w + 200, r.y - 8, try std.fmt.allocPrint(a, "{s}% Confidence Limits", .{percent}), "end");
    }
    for (rows, 0..) |row, i| {
        const y = r.y + ratio_row_height * (@as(f64, @floatFromInt(i)) + 0.5);
        try text(w, r.x - 8, y + 4, row.label, "end");
        try w.print("<g class=\"{s}\" data-label=\"", .{if (row.common) "estimate common" else "estimate"});
        try svg.escaped(w, row.label);
        try w.writeAll("\"");
        if (row.value) |v| try w.print(" data-value=\"{d}\"", .{v});
        if (row.lower) |v| try w.print(" data-lower=\"{d}\"", .{v});
        if (row.upper) |v| try w.print(" data-upper=\"{d}\"", .{v});
        try w.writeAll(">");
        if (row.lower != null and row.upper != null) {
            const lo = r.x + r.w * ratioPosition(row.lower.?, range, p.logbase);
            const hi = r.x + r.w * ratioPosition(row.upper.?, range, p.logbase);
            try w.print("<path class=\"limits\" d=\"M{d:.2} {d:.2}H{d:.2}M{d:.2} {d:.2}v10M{d:.2} {d:.2}v10\" stroke=\"#445b73\" fill=\"none\"/>", .{ lo, y, hi, lo, y - 5, hi, y - 5 });
        }
        if (row.value) |v| {
            const x = r.x + r.w * ratioPosition(v, range, p.logbase);
            if (row.common) try w.print("<path class=\"diamond\" d=\"M{d:.2} {d:.2}l6 6l-6 6l-6 -6z\" fill=\"{s}\"/>", .{ x, y - 6, palette[1] }) else try w.print("<circle class=\"dot\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"4\" fill=\"{s}\"/>", .{ x, y, palette[0] });
        }
        try w.writeAll("</g>");
        if (p.stats) for ([_]?f64{ row.value, row.lower, row.upper }, [_]f64{ 62, 130, 200 }) |item, dx| if (item) |v| {
            try w.print("<text class=\"stat\" x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"end\">{d:.4}</text>", .{ r.x + r.w + dx, y + 4, v });
        };
    }
    try text(w, r.x + r.w / 2, r.y + r.h + 45, if (odds) statistic else if (p.second_column) "Relative Risk (Column 2)" else "Relative Risk (Column 1)", "middle");
    try w.writeAll("</svg>");
    return out.written();
}
/// S154 Table 47.23 (physical p.3257): h x 2 x 2 tables only, and only with the
/// TABLES option that computes the ratios. COMMON needs CMH (physical p.3137).
fn ratioGraphs(cx: proc.ProcCtx, session: *svg.Session, tab: *tm.Table, req: freq.Request, plots: []const Plot, strata: []const usize, by: []const u8, by_number: ?usize, table_number: usize) diag.Error!void {
    const a = cx.arena;
    const n = tab.dimensions.len;
    if (n < 3) return;
    const measures = req.statistics.measures and !req.statistics.measures_only_implied;
    var labels: std.ArrayList([]const u8) = .empty;
    var matrices: std.ArrayList(strat.Matrix) = .empty;
    const size = tab.dimensions[n - 1].levels.len * tab.dimensions[n - 2].levels.len;
    for (strata) |id| {
        const sc = (try tab.matrix(a, id)) orelse continue;
        var total: f64 = 0;
        for (sc.matrix.counts) |c| total += c;
        if (!(total > 0)) continue;
        if (sc.matrix.rows != 2 or sc.matrix.cols != 2) return;
        var name: W.Allocating = .init(a);
        for (0..n - 2) |j| {
            if (j > 0) name.writer.writeByte(' ') catch return error.OutOfMemory;
            name.writer.writeAll(level(a, tab.level(id * size, j)) catch return error.OutOfMemory) catch return error.OutOfMemory;
        }
        try labels.append(a, name.written());
        try matrices.append(a, sc.matrix);
    }
    if (matrices.items.len == 0) return;
    for (plots) |p| {
        if (!isRatio(p.kind)) continue;
        const odds = p.kind == .oddsratioplot;
        if (!(measures or req.risk.relative_risk != null or (odds and req.risk.odds_ratio != null))) continue;
        const rows = try ratioRows(a, p, labels.items, matrices.items, req.statistics.alpha, p.common and req.stratified.cmh > 0);
        const bytes = ratioSvg(a, p, rows, by, req.statistics.alpha) catch return error.OutOfMemory;
        try session.queue(0, @tagName(p.kind), bytes, try svg.graph_ods.freq(a, if (odds) .ORPlot else .RelRiskPlot, by_number, table_number, false, false, false));
    }
}
pub fn execute(cx: proc.ProcCtx, tab: *tm.Table, req: freq.Request, by: []const u8, by_number: ?usize, table_number: usize) diag.Error!void {
    const opt = req.plots;
    const n = tab.dimensions.len;
    const session = cx.graphics orelse {
        if (opt.plots.len > 0) return proc.failGap(cx.diags, 0, "PROC FREQ: PLOTS requires a graphics consumer", .{});
        return;
    };
    if (session.enabled == false or tab.negative or !(tab.total > 0)) return;
    var requested: std.ArrayList(Plot) = .empty;
    try requested.appendSlice(cx.arena, opt.plots);
    if (!opt.only) for ([_]Kind{ .deviationplot, .agreeplot }) |kind| {
        if (!applicable(kind, req, n)) continue;
        for (requested.items) |p| {
            if (p.kind == kind) break;
        } else try requested.append(cx.arena, .{ .kind = kind });
    };
    if (requested.items.len == 0) return;
    if (n >= 2 and (tab.dimensions[n - 1].levels.len == 0 or tab.dimensions[n - 2].levels.len == 0)) return;
    const a = cx.arena;
    const strata = if (n <= 2) @as([]const usize, &.{0}) else try freq.analysisStrata(a, tab);
    for (strata) |id| {
        if (n > 2 and tab.excluded(id * tab.dimensions[n - 1].levels.len * tab.dimensions[n - 2].levels.len)) {
            var skip = false;
            const key = id * tab.dimensions[n - 1].levels.len * tab.dimensions[n - 2].levels.len;
            for (0..n - 2) |j| if (!tab.include_missing and tab.level(key, j).missing) {
                skip = true;
                break;
            };
            if (skip) continue;
        }
        const sc = (try tab.matrix(a, id)) orelse continue;
        if (sc.matrix.rows == 0 or sc.matrix.cols == 0) continue;
        const g = try Grid.init(a, sc);
        if (!(g.total > 0)) continue;
        const sub = subheading(a, by, tab, id) catch return error.OutOfMemory;
        for (requested.items) |p| {
            if (!applicable(p.kind, req, n)) continue;
            const name: svg.graph_ods.Name = switch (p.kind) {
                .freqplot => .FreqPlot,
                .cumfreqplot => .CumFreqPlot,
                .mosaicplot => .MosaicPlot,
                .agreeplot => .AgreePlot,
                .deviationplot => .DeviationPlot,
                .relriskplot, .oddsratioplot => unreachable,
            };
            const object = try svg.graph_ods.freq(a, name, by_number, table_number, n == 1, p.dot, p.layout == .cluster or p.layout == .stacked);
            if (n == 1) {
                if (p.scale == .grouppercent) return cx.diags.fail(error.ParseError, 0, "PROC FREQ: GROUPPERCENT requires a two-way table", .{});
                const bytes = one(a, tab, req, p, sc, sub) catch |e| return if (e == error.ExecError) error.ExecError else error.OutOfMemory;
                try session.queue(0, @tagName(p.kind), bytes, object);
                continue;
            }
            const row = tab.dimensions[n - 2];
            const col = tab.dimensions[n - 1];
            const kind = @tagName(p.kind);
            switch (p.kind) {
                .freqplot => {
                    const facets = if (p.layout == .groupvertical or p.layout == .grouphorizontal) (if (rowsOnAxis(p)) g.cols.len else g.rows.len) else 1;
                    const pages = (facets + 3) / 4;
                    const per_page = (facets + pages - 1) / pages;
                    var first: usize = 0;
                    while (first < facets) : (first += per_page) {
                        const bytes = twoFrequency(a, p, g, row, col, sub, first, @min(per_page, facets - first)) catch return error.OutOfMemory;
                        try session.queue(0, kind, bytes, object);
                    }
                },
                .mosaicplot => try session.queue(0, kind, mosaic(a, p, g, row, col, sub) catch return error.OutOfMemory, object),
                .agreeplot => if (g.rows.len == g.cols.len) {
                    try session.queue(0, kind, agreement(a, p, g, row, col, sub) catch return error.OutOfMemory, object);
                },
                else => {},
            }
        }
    }
    try ratioGraphs(cx, session, tab, req, requested.items, strata, by, by_number, table_number);
}
