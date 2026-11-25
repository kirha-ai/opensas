//! TTEST Interval / QQ native graphs. S154 physical pp.10645,10649-10650.
//! Explicit ONLY requests avoid claiming unimplemented default SummaryPanel graphs.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const tt = @import("ttest.zig");
const decl = @import("ttest_parse.zig");
const fit = @import("ttest_fit.zig");
const two = @import("ttest_two_sample.zig");
const inference = @import("univ_inference.zig");
const selection = @import("data_selection.zig");
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
const W = std.Io.Writer;
const eq = std.ascii.eqlIgnoreCase;

pub const IntervalType = enum { test_mean, pergroup };
pub const Request = union(enum) { interval: IntervalType, qq };
pub const Options = struct { explicit: bool = false, only: bool = false, none: bool = false, show_h0: bool = false, requests: []const Request = &.{} };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn fail(d: *diag.Diagnostics, t: []const lex.Token, i: usize) diag.Error {
    return d.fail(error.ParseError, t[@min(i, t.len - 1)].line, "PROC TTEST: invalid PLOTS syntax near {s}", .{t[@min(i, t.len - 1)].text});
}
pub fn parse(a: A, d: *diag.Diagnostics, t: []const lex.Token, i: *usize) diag.Error!Options {
    var o: Options = .{ .explicit = true };
    i.* += 1;
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        while (!at(t, i.*, .rparen)) {
            if (!at(t, i.*, .name)) return fail(d, t, i.*);
            const name = t[i.*].text;
            if (eq(name, "only")) o.only = true else if (eq(name, "showh0") or eq(name, "shownull")) o.show_h0 = true else if (eq(name, "unpack") or eq(name, "unpackpanel")) return proc.failGap(d, t[i.*].line, "TTEST PLOTS UNPACK is not implemented", .{}) else return fail(d, t, i.*);
            i.* += 1;
        }
        i.* += 1;
    }
    if (!at(t, i.*, .eq)) {
        o.none = o.only;
        return o;
    }
    i.* += 1;
    const grouped = at(t, i.*, .lparen);
    if (grouped) i.* += 1;
    var requests: std.ArrayList(Request) = .empty;
    while (true) {
        if (!at(t, i.*, .name)) return fail(d, t, i.*);
        const token = t[i.*];
        i.* += 1;
        if (eq(token.text, "none")) o.none = true else if (eq(token.text, "qq") or eq(token.text, "qqplot")) {
            try requests.append(a, .qq);
        } else if (eq(token.text, "interval") or eq(token.text, "intervalplot")) {
            var kind: IntervalType = .test_mean;
            if (at(t, i.*, .lparen)) {
                i.* += 1;
                if (!at(t, i.*, .name) or !eq(t[i.*].text, "type") or !at(t, i.* + 1, .eq) or !at(t, i.* + 2, .name)) return fail(d, t, i.*);
                const value = t[i.* + 2];
                if (eq(value.text, "test")) kind = .test_mean else if (eq(value.text, "pergroup")) kind = .pergroup else if (eq(value.text, "period") or eq(value.text, "treatment")) return proc.failGap(d, value.line, "TTEST crossover interval graphs are not implemented", .{}) else return fail(d, t, i.* + 2);
                i.* += 3;
                if (!at(t, i.*, .rparen)) return fail(d, t, i.*);
                i.* += 1;
            }
            if (kind == .pergroup and o.show_h0) return d.fail(error.ParseError, token.line, "TYPE=PERGROUP cannot be combined with SHOWH0", .{});
            try requests.append(a, .{ .interval = kind });
        } else {
            inline for (.{ "all", "summary", "summaryplot", "histogram", "hist", "histdens", "box", "boxplot", "agreement", "agreementplot", "profiles", "profilesplot", "bootstrap", "boot" }) |known| if (eq(token.text, known)) return proc.failGap(d, token.line, "TTEST graph {s} is not implemented", .{token.text});
            return fail(d, t, i.* - 1);
        }
        if (!grouped) break;
        if (at(t, i.*, .rparen)) {
            i.* += 1;
            break;
        }
    }
    if (o.none and requests.items.len > 0) return d.fail(error.ParseError, t[i.* - 1].line, "PLOTS=NONE cannot be combined with other requests", .{});
    o.requests = requests.items;
    return o;
}

pub fn active(cx: proc.ProcCtx) bool {
    const g = cx.graphics orelse return false;
    return g.enabled != false and (g.enabled == true or g.cli_dir != null or g.gpath != null);
}
pub fn validate(cx: proc.ProcCtx, s: decl.Spec) diag.Error!void {
    const o = s.options.plots;
    if (!active(cx) or o.none or s.options.plots_none or s.summary != null) return;
    if (!o.explicit or !o.only) return proc.failGap(cx.diags, s.line, "TTEST default SummaryPanel graphics are not implemented; explicit PLOTS(ONLY)=INTERVAL or QQ is supported", .{});
    if (s.crossover != null or s.options.distribution != .normal) return proc.failGap(cx.diags, s.line, "TTEST crossover/lognormal graphics are not implemented", .{});
    for (o.requests) |request| switch (request) {
        .qq => if (s.roles.weight != null) return proc.failGap(cx.diags, s.line, "TTEST weighted Q-Q plotting positions are not verified", .{}),
        .interval => |kind| if (kind == .pergroup and s.class == null) return cx.diags.fail(error.ParseError, s.line, "INTERVAL(TYPE=PERGROUP) requires CLASS", .{}),
    };
}

pub const IntervalPoint = struct { label: []const u8, estimate: f64, lower: f64, upper: f64, df: f64 };
pub const QQPoint = struct { probability: f64, quantile: f64, observed: f64 };
pub const QQGroup = struct { label: []const u8, mean: f64, sd: f64, points: []const QQPoint };
pub const Data = struct { variable: []const u8, class_name: ?[]const u8, classes: []const []const u8, intervals: []const IntervalPoint, qq: []const QQGroup, confidence: f64, h0: ?f64, bounds: ?@import("ttest_tost.zig").Bounds = null };
fn sides(s: decl.Sides) fit.Sides {
    return switch (s) {
        .two => .two_sided,
        .upper => .upper,
        .lower => .lower,
    };
}
fn less(_: void, a: f64, b: f64) bool {
    return a < b;
}

pub fn data(cx: proc.ProcCtx, s: decl.Spec, g: tt.Group, analysis: tt.Analysis, kind: IntervalType, want_qq: bool) diag.Error!Data {
    const a = cx.arena;
    const variable = if (analysis.pair) |pair| try std.fmt.allocPrint(a, "Difference: {s} - {s}", .{ s.input.ds.columns.items[pair.left].name, s.input.ds.columns.items[pair.right].name }) else s.input.ds.columns.items[analysis.column].name;
    var intervals: std.ArrayList(IntervalPoint) = .empty;
    var labels: std.ArrayList([]const u8) = .empty;
    if (s.class != null) for (analysis.classes) |c| {
        try labels.append(a, c.label);
    };
    var confidence = 1 - s.options.alpha;
    var bounds: ?@import("ttest_tost.zig").Bounds = null;
    if (s.class != null and kind == .test_mean) {
        const r = try two.compute(analysis.samples[0], analysis.samples[1], .{ .h0 = s.options.h0, .alpha = s.options.alpha, .sides = sides(s.options.sides) });
        for ([_]two.Comparison{ r.pooled, r.satterthwaite }, [_][]const u8{ "Pooled", "Satterthwaite" }) |c, label| {
            var ci = c.mean_ci;
            if (s.options.tost) |limits| {
                ci = (try @import("ttest_tost.zig").evaluate(c.estimate, c.std_err, c.df, limits, s.options.alpha, .difference)).interval;
                confidence = 1 - 2 * s.options.alpha;
                bounds = limits;
            }
            try intervals.append(a, .{ .label = label, .estimate = c.estimate, .lower = ci.lower, .upper = ci.upper, .df = c.df });
        }
    } else for (analysis.samples, 0..) |sample, k| {
        var ci = sample.mean_ci;
        if (kind == .pergroup) {
            const m = -inference.tQuantile(s.options.alpha / 2, sample.df) * sample.std_err;
            ci = .{ .lower = sample.mean - m, .upper = sample.mean + m };
        } else if (s.options.tost) |limits| {
            ci = (try @import("ttest_tost.zig").evaluate(sample.mean, sample.std_err, sample.df, limits, s.options.alpha, .difference)).interval;
            confidence = 1 - 2 * s.options.alpha;
            bounds = limits;
        }
        try intervals.append(a, .{ .label = if (s.class != null) labels.items[k] else "Mean", .estimate = sample.mean, .lower = ci.lower, .upper = ci.upper, .df = sample.df });
    }
    var qq: std.ArrayList(QQGroup) = .empty;
    if (want_qq) {
        const missing = if (analysis.pair) |pair| try a.dupe(usize, &.{ pair.left, pair.right }) else if (s.class) |c| try a.dupe(usize, &.{ analysis.column, c }) else try a.dupe(usize, &.{analysis.column});
        const selected = try g.view.select(a, .{ .missing_columns = missing, .frequency = .truncate_positive });
        const expanded = try selected.dataset(a, true, cx.diags);
        var values: [2]std.ArrayList(f64) = .{ .empty, .empty };
        for (expanded.rows.items) |row| {
            const k: usize = if (s.class) |c| blk: {
                const column = s.input.ds.columns.items[c];
                const raw = if (column.format) |fmt| try @import("../format.zig").apply(a, row[c], fmt) else try proc.cellText(a, row[c]);
                break :blk if (std.mem.eql(u8, std.mem.trim(u8, raw, " "), labels.items[0])) 0 else 1;
            } else 0;
            try values[k].append(a, if (analysis.pair) |pair| row[pair.left].num - row[pair.right].num else row[analysis.column].num);
        }
        for (analysis.samples, 0..) |sample, k| {
            if (values[k].items.len > 100000) return proc.failGap(cx.diags, s.line, "TTEST Q-Q plot exceeds the supported 100000 points", .{});
            std.mem.sort(f64, values[k].items, {}, less);
            // Reuse the existing SAS normal QQ construction (Blom positions).
            const values_plot = try @import("univ_distribution_values.zig").quantilePlot(a, cx.diags, values[k].items, .{ .family = .normal, .p = .{ .mu = 0, .sigma = 1 } }, 0.375, 0.25, false);
            const points = try a.alloc(QQPoint, values_plot.points.len);
            for (values_plot.points, points) |source, *point| point.* = .{ .probability = source.probability, .quantile = source.theoretical, .observed = source.observed };
            try qq.append(a, .{ .label = if (s.class != null) labels.items[k] else variable, .mean = sample.mean, .sd = sample.std_dev, .points = points });
        }
    }
    return .{ .variable = variable, .class_name = if (s.class) |c| s.input.ds.columns.items[c].name else null, .classes = labels.items, .intervals = intervals.items, .qq = qq.items, .confidence = confidence, .h0 = if (s.options.plots.show_h0) s.options.h0 else null, .bounds = bounds };
}

const Frame = struct {
    left: f64,
    right: f64,
    top: f64,
    bottom: f64,
    x: svg.Range,
    y: svg.Range,
    fn px(f: Frame, v: f64) f64 {
        return f.left + (f.right - f.left) * (v - f.x.lo) / (f.x.hi - f.x.lo);
    }
    fn py(f: Frame, v: f64) f64 {
        return f.bottom - (f.bottom - f.top) * (v - f.y.lo) / (f.y.hi - f.y.lo);
    }
};
fn tickStep(span: f64) f64 {
    const rough = span / 6;
    const magnitude = std.math.pow(f64, 10, @floor(std.math.log10(rough)));
    const relative = rough / magnitude;
    const factor: f64 = if (relative <= 1) 1 else if (relative <= 2) 2 else if (relative <= 2.5) 2.5 else if (relative <= 5) 5 else 10;
    return magnitude * factor;
}
fn nice(r: svg.Range) svg.Range {
    if (!std.math.isFinite(r.lo) or !std.math.isFinite(r.hi)) return .{ .lo = 0, .hi = 1 };
    const p = r.padded();
    var step = tickStep(p.hi - p.lo);
    var result: svg.Range = undefined;
    for (0..8) |_| {
        result = .{ .lo = @floor(p.lo / step) * step, .hi = @ceil(p.hi / step) * step };
        const next = tickStep(result.hi - result.lo);
        if (next <= step) return result;
        step = next;
    }
    return result;
}
fn text(w: *W, x: f64, y: f64, value: []const u8, anchor: []const u8) !void {
    try w.print("<text x=\"{d:.2}\" y=\"{d:.2}\" text-anchor=\"{s}\">", .{ x, y, anchor });
    try svg.escaped(w, value);
    try w.writeAll("</text>\n");
}
fn begin(w: *W, width: f64, height: f64, kind: []const u8, title: []const u8) !void {
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" data-kind=\"{s}\" role=\"img\"><title>", .{ width, height, width, height, kind });
    try svg.escaped(w, title);
    try w.writeAll("</title><style>text{font:13px Arial,sans-serif;fill:#263445}.title text{font-size:20px;font-weight:600}.grid{stroke:#e5e9ef;stroke-width:1}.axis{stroke:#8390a2;fill:none}.reference{stroke:#8591a1;stroke-dasharray:5 4;fill:none}.interval{stroke-width:3;fill:none}.point{stroke-width:2;fill:white}</style><rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n");
    try w.writeAll("<g class=\"title\">");
    try text(w, width / 2, 32, title, "middle");
    try w.writeAll("</g>\n");
}
fn xTicks(a: A, w: *W, f: Frame) !void {
    const step = tickStep(f.x.hi - f.x.lo);
    const count: usize = @intFromFloat(@floor((f.x.hi - f.x.lo) / step + 0.5));
    for (0..count + 1) |i| {
        const v = f.x.lo + @as(f64, @floatFromInt(i)) * step;
        const x = f.px(v);
        try w.print("<path class=\"grid\" d=\"M{d:.2} {d:.2}V{d:.2}\"/>", .{ x, f.top, f.bottom });
        try text(w, x, f.bottom + 23, try svg.label(a, v), "middle");
    }
    try w.print("<path class=\"axis\" d=\"M{d} {d}V{d}H{d}\"/>", .{ f.left, f.top, f.bottom, f.right });
}

pub fn intervalSvg(a: A, d: Data, pergroup: bool, global_title: ?[]const u8) ![]const u8 {
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    const title = try std.fmt.allocPrint(a, "{s} Interval Plot", .{if (d.class_name != null and !pergroup) @as([]const u8, "Difference") else "Mean"});
    try begin(w, 940, 440, "ttest-interval", global_title orelse title);
    const subtitle = if (d.class_name != null and !pergroup) try std.fmt.allocPrint(a, "{s}: {s} - {s}  |  {s}", .{ d.class_name.?, d.classes[0], d.classes[1], d.variable }) else d.variable;
    try text(w, 470, 58, subtitle, "middle");
    var range: svg.Range = .{};
    for (d.intervals) |v| {
        range.add(v.estimate);
        if (std.math.isFinite(v.lower)) range.add(v.lower);
        if (std.math.isFinite(v.upper)) range.add(v.upper);
    }
    if (d.h0) |v| range.add(v);
    if (d.bounds) |v| {
        range.add(v.lower);
        range.add(v.upper);
    }
    const frame: Frame = .{ .left = 175, .right = 885, .top = 95, .bottom = 320, .x = nice(range), .y = .{ .lo = 0, .hi = 1 } };
    try xTicks(a, w, frame);
    try w.writeAll("<defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"4\" refY=\"4\" orient=\"auto-start-reverse\"><path d=\"M0 0L8 4L0 8z\" fill=\"#2563eb\"/></marker></defs>");
    if (d.h0) |v| {
        try w.print("<path class=\"reference\" data-null=\"{d}\" d=\"M{d:.2} {d}V{d}\"/>", .{ v, frame.px(v), frame.top, frame.bottom });
        try text(w, frame.px(v), 84, try std.fmt.allocPrint(a, "H0 = {s}", .{try svg.label(a, v)}), "middle");
    }
    if (d.bounds) |bounds| for ([_]f64{ bounds.lower, bounds.upper }) |v| {
        try w.print("<path stroke=\"#16856a\" stroke-dasharray=\"5 4\" data-equivalence-bound=\"{d}\" d=\"M{d:.2} {d}V{d}\"/>", .{ v, frame.px(v), frame.top, frame.bottom });
    };
    for (d.intervals, 0..) |v, i| {
        const y = frame.top + (frame.bottom - frame.top) * (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(d.intervals.len));
        const color: []const u8 = if (i % 2 == 0) "#2563eb" else "#c45b22";
        try text(w, frame.left - 16, y + 4, v.label, "end");
        try w.writeAll("<g class=\"interval-row\" data-method=\"");
        try svg.escaped(w, v.label);
        try w.print("\" data-estimate=\"{d}\" data-lower=\"{d}\" data-upper=\"{d}\" data-df=\"{d}\">", .{ v.estimate, v.lower, v.upper, v.df });
        if (!std.math.isNan(v.lower) and !std.math.isNan(v.upper)) {
            const lo = if (std.math.isInf(v.lower)) frame.left + 5 else frame.px(v.lower);
            const hi = if (std.math.isInf(v.upper)) frame.right - 5 else frame.px(v.upper);
            try w.print("<path class=\"interval\" stroke=\"{s}\" d=\"M{d:.2} {d:.2}H{d:.2}\"{s}{s}/>", .{ color, lo, y, hi, if (std.math.isInf(v.lower)) @as([]const u8, " marker-start=\"url(#arrow)\"") else "", if (std.math.isInf(v.upper)) @as([]const u8, " marker-end=\"url(#arrow)\"") else "" });
            for ([_]f64{ v.lower, v.upper }) |limit| if (std.math.isFinite(limit)) {
                try w.print("<path stroke=\"{s}\" d=\"M{d:.2} {d:.2}v14\"/>", .{ color, frame.px(limit), y - 7 });
            };
        }
        try w.print("<circle class=\"point\" stroke=\"{s}\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"5\"/></g>", .{ color, frame.px(v.estimate), y });
    }
    try text(w, (frame.left + frame.right) / 2, 375, if (d.class_name != null and !pergroup) "Difference in means" else "Mean", "middle");
    try text(w, 470, 407, try std.fmt.allocPrint(a, "Points: estimates   |   Bars: {s}% confidence intervals", .{try svg.label(a, 100 * d.confidence)}), "middle");
    try w.writeAll("</svg>");
    return out.written();
}

pub fn qqSvg(a: A, d: Data, global_title: ?[]const u8) ![]const u8 {
    const width: f64 = if (d.qq.len > 1) 1020 else 560;
    const height: f64 = 530;
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try begin(w, width, height, "ttest-qq", global_title orelse try std.fmt.allocPrint(a, "Q-Q Plots of {s}", .{d.variable}));
    var qmax: f64 = 1;
    var yr: svg.Range = .{};
    for (d.qq) |g| for (g.points) |p| {
        qmax = @max(qmax, @ceil(@abs(p.quantile)));
        yr.add(p.observed);
    };
    for (d.qq) |g| if (std.math.isFinite(g.sd)) {
        yr.add(g.mean - g.sd * qmax);
        yr.add(g.mean + g.sd * qmax);
    };
    const y = nice(yr);
    for (d.qq, 0..) |g, k| {
        const left = 75 + @as(f64, @floatFromInt(k)) * 490;
        const frame: Frame = .{ .left = left, .right = left + 390, .top = 95, .bottom = 420, .x = .{ .lo = -qmax, .hi = qmax }, .y = y };
        const color: []const u8 = if (k % 2 == 0) "#2563eb" else "#c45b22";
        try text(w, (frame.left + frame.right) / 2, 70, try std.fmt.allocPrint(a, "{s}{s}{s} (n={d})", .{ d.class_name orelse "", if (d.class_name != null) @as([]const u8, " = ") else "", g.label, g.points.len }), "middle");
        try w.writeAll("<g class=\"qq-panel\" data-group=\"");
        try svg.escaped(w, g.label);
        try w.print("\" data-n=\"{d}\" data-mean=\"{d}\" data-sd=\"{d}\" data-xmin=\"{d}\" data-xmax=\"{d}\" data-ymin=\"{d}\" data-ymax=\"{d}\">", .{ g.points.len, g.mean, g.sd, frame.x.lo, frame.x.hi, y.lo, y.hi });
        try xTicks(a, w, frame);
        const y_step = tickStep(y.hi - y.lo);
        const y_count: usize = @intFromFloat(@floor((y.hi - y.lo) / y_step + 0.5));
        for (0..y_count + 1) |i| {
            const v = y.lo + @as(f64, @floatFromInt(i)) * y_step;
            try w.print("<path class=\"grid\" d=\"M{d:.2} {d:.2}H{d:.2}\"/>", .{ frame.left, frame.py(v), frame.right });
            try text(w, frame.left - 10, frame.py(v) + 4, try svg.label(a, v), "end");
        }
        if (std.math.isFinite(g.sd)) try w.print("<path class=\"reference\" data-intercept=\"{d}\" data-slope=\"{d}\" d=\"M{d:.2} {d:.2}L{d:.2} {d:.2}\"/>", .{ g.mean, g.sd, frame.left, frame.py(g.mean - g.sd * qmax), frame.right, frame.py(g.mean + g.sd * qmax) });
        for (g.points) |p| try w.print("<circle class=\"point\" stroke=\"{s}\" data-probability=\"{d}\" data-quantile=\"{d}\" data-observed=\"{d}\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"4\"/>", .{ color, p.probability, p.quantile, p.observed, frame.px(p.quantile), frame.py(p.observed) });
        try w.writeAll("</g>");
        try text(w, (frame.left + frame.right) / 2, 467, "Normal Quantile", "middle");
        try w.print("<text text-anchor=\"middle\" transform=\"translate({d} 257) rotate(-90)\">", .{left - 55});
        try svg.escaped(w, d.variable);
        try w.writeAll("</text>");
    }
    try text(w, width / 2, 507, "Circles: observations   |   Dashed lines: fitted normal reference", "middle");
    try w.writeAll("</svg>");
    return out.written();
}

pub fn executeAnalysis(cx: proc.ProcCtx, s: decl.Spec, g: tt.Group, analysis: tt.Analysis, by_index: usize, order: *usize) diag.Error!void {
    if (!active(cx) or s.options.plots.none or s.options.plots_none or s.summary != null) return;
    const session = cx.graphics.?;
    const prefix = try @import("ods_ttest.zig").path(cx.arena, s, by_index, analysis);
    // Stable table-like order: Interval then QQPlot, regardless of spelling order.
    for ([_]bool{ false, true }) |want_qq| for (s.options.plots.requests) |req| {
        const is_qq = req == .qq;
        if (is_qq != want_qq) continue;
        const kind: IntervalType = if (req == .interval) req.interval else .test_mean;
        const values = try data(cx, s, g, analysis, kind, is_qq);
        const bytes = if (is_qq) qqSvg(cx.arena, values, cx.graph_title) catch return error.OutOfMemory else intervalSvg(cx.arena, values, kind == .pergroup, cx.graph_title) catch return error.OutOfMemory;
        const name: svg.graph_ods.Name = if (is_qq) .QQPlot else .Interval;
        const label: []const u8 = if (is_qq) (if (s.class != null) "Q-Q Plots" else "Q-Q Plot") else if (s.class != null and kind == .test_mean) "Difference Interval Plot" else "Mean Interval Plot";
        try session.queue(order.*, if (is_qq) "ttest-qq" else "ttest-interval", bytes, .{ .name = name, .label = label, .template = if (is_qq) (if (s.class != null) @as(?[]const u8, "Stat.TTest.Graphics.QQ2") else null) else "Stat.TTest.Graphics.Interval", .path = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ prefix, @tagName(name) }) });
        order.* += 1;
    };
}

const Testing = struct {
    fn sample(a: A) !*@import("../dataset.zig").Dataset {
        const Dataset = @import("../dataset.zig").Dataset;
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "sample");
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("group", .char);
        for ([_]f64{ 43, 90, 84, 87, 116, 95, 86, 99, 93, 92, 121, 71 }, 0..) |x, k| try ds.appendRow(&.{ .{ .num = x }, .{ .str = if (k < 6) "A" else "B" } });
        return ds;
    }
};

test "TTEST GRAPHICS interval endpoints and all QQ observations probabilities and quantiles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try decl.parse(cx, try lex.tokenize(a, "proc ttest data=sample plots(only)=(interval qq); class group; var x; run;", &d));
    const r = try tt.compute(cx, s);
    const plot = try data(cx, s, r.groups[0], r.groups[0].analyses[0], .test_mean, true);
    try std.testing.expectEqual(@as(usize, 2), plot.intervals.len);
    try std.testing.expectEqualStrings("Pooled", plot.intervals[0].label);
    try std.testing.expectEqualStrings("Satterthwaite", plot.intervals[1].label);
    for (plot.intervals) |p| try std.testing.expectApproxEqAbs(@as(f64, -47.0 / 6.0), p.estimate, 2e-14);
    // Half the reference listing's displayed 4-decimal unit; graph metadata is unrounded.
    try std.testing.expectApproxEqAbs(@as(f64, -34.2038), plot.intervals[0].lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 18.5372), plot.intervals[0].upper, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -34.6661), plot.intervals[1].lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 18.9995), plot.intervals[1].upper, 0.00005);
    try std.testing.expectEqual(@as(f64, 10), plot.intervals[0].df);
    const observed = [_][6]f64{ .{ 43, 84, 87, 90, 95, 116 }, .{ 71, 86, 92, 93, 99, 121 } };
    const probabilities = [_]f64{ 0.1, 0.26, 0.42, 0.58, 0.74, 0.9 };
    // Independent standard-normal inverse values (Python NormalDist/mpmath).
    const quantiles = [_]f64{ -1.2815515655446004, -0.643345405392917, -0.201893479141851, 0.201893479141851, 0.643345405392917, 1.2815515655446004 };
    for (plot.qq, observed, [_][]const u8{ "A", "B" }) |g, ys, label| {
        try std.testing.expectEqualStrings(label, g.label);
        try std.testing.expectEqual(@as(usize, 6), g.points.len);
        for (g.points, ys, probabilities, quantiles) |p, y, prob, q| {
            try std.testing.expectEqual(y, p.observed);
            try std.testing.expectApproxEqAbs(prob, p.probability, 2e-16);
            try std.testing.expectApproxEqAbs(q, p.quantile, 2e-9);
        }
    }
    try std.testing.expectApproxEqAbs(@as(f64, 515.0 / 6.0), plot.qq[0].mean, 2e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 3421.0 / 6.0)), plot.qq[0].sd, 1e-13);
    try std.testing.expectEqualStrings("", try d.render());
}

test "TTEST GRAPHICS ODS OFF NONE selection and reference TRACE identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var listing: proc.OdsListing = .{ .trace = &d };
    var session: svg.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true, .listing = &listing };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &session, .listing = &listing };
    const code = try lex.tokenize(a, "proc ttest plots(only)=(interval qq); class group; var x; run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try tt.runTtest(cx, &out, code);
    try std.testing.expectEqual(@as(usize, 2), session.prepared.items.len);
    const log = try d.render();
    try std.testing.expect(std.mem.indexOf(u8, log, "Name:       Interval\nLabel:      Difference Interval Plot\nTemplate:   Stat.TTest.Graphics.Interval\nPath:       Ttest.x.Interval") != null);
    try std.testing.expect(std.mem.indexOf(u8, log, "Name:       QQPlot\nLabel:      Q-Q Plots\nTemplate:   Stat.TTest.Graphics.QQ2\nPath:       Ttest.x.QQPlot") != null);
    try std.testing.expectEqual(@as(usize, 12), std.mem.count(u8, session.prepared.items[1].bytes, "data-observed="));
    session.clear();
    session.enabled = false;
    out.clearRetainingCapacity();
    try tt.runTtest(cx, &out, code);
    try std.testing.expectEqual(@as(usize, 0), session.prepared.items.len);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Analysis") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Pooled") != null);
    session.enabled = true;
    out.clearRetainingCapacity();
    try tt.runTtest(cx, &out, try lex.tokenize(a, "proc ttest plots=none; class group; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), session.prepared.items.len);
    _ = try listing.parse(a, &d, try lex.tokenize(a, "ods select Interval;", &d));
    out.clearRetainingCapacity();
    try tt.runTtest(cx, &out, code);
    try std.testing.expectEqual(@as(usize, 1), session.prepared.items.len);
    try std.testing.expect(std.mem.indexOf(u8, session.prepared.items[0].bytes, "ttest-interval") != null);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(!d.hasErrors());
}

test "TTEST GRAPHICS one-sided arrows and per-group intervals retain parameter meaning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try decl.parse(cx, try lex.tokenize(a, "proc ttest sides=u plots(only showh0)=interval; class group; var x; run;", &d));
    const r = try tt.compute(cx, s);
    const plot = try data(cx, s, r.groups[0], r.groups[0].analyses[0], .test_mean, false);
    for (plot.intervals) |p| try std.testing.expectEqual(std.math.inf(f64), p.upper);
    const bytes = try intervalSvg(a, plot, false, null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "marker-end="));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "data-null=\"0\"") != null);
    const pergroup = try data(cx, s, r.groups[0], r.groups[0].analyses[0], .pergroup, false);
    try std.testing.expectEqualStrings("A", pergroup.intervals[0].label);
    try std.testing.expectApproxEqAbs(@as(f64, 60.7747), pergroup.intervals[0].lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 110.8919), pergroup.intervals[0].upper, 0.00005);
    try std.testing.expect(std.math.isFinite(pergroup.intervals[1].upper));
}

test "TTEST GRAPHICS unsupported defaults and invalid plot options fail visibly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    for ([_][]const u8{ "plots(only)=(qq bogus)", "plots(only)=interval(type=bogus)", "plots(only showh0)=interval(type=pergroup)" }) |header| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const source = try std.fmt.allocPrint(a, "proc ttest {s}; class group; var x; run;", .{header});
        try std.testing.expectError(error.ParseError, decl.parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasErrors());
    }
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var session: svg.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &session };
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, tt.runTtest(cx, &out, try lex.tokenize(a, "proc ttest; class group; var x; run;", &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expectEqual(@as(usize, 0), session.prepared.items.len);
}
