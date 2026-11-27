//! Native MIXED residual diagnostic graphs, S154 physical pp.6633-6637,6729-6734.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const data = @import("mixed_plot_data.zig");
const svg = @import("graphics_svg.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;
pub const Request = struct { kind: data.Kind, mode: data.Mode = .conditional, unpack: bool = false };
pub const Options = struct { explicit: bool = false, only: bool = false, none: bool = false, unpack: bool = false, obsno: bool = false, maxpoints: usize = 5000, requests: []const Request = &.{} };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(d: *diag.Diagnostics, t: []const lex.Token, i: usize) diag.Error {
    return d.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC MIXED: invalid PLOTS syntax near {s}", .{if (i < t.len) t[i].text else "<end>"});
}
pub fn parse(a: A, d: *diag.Diagnostics, t: []const lex.Token, index: *usize) diag.Error!Options {
    var o = Options{ .explicit = true };
    var i = index.* + 1;
    if (at(t, i, .lparen)) {
        i += 1;
        while (!at(t, i, .rparen)) {
            if (!at(t, i, .name)) return bad(d, t, i);
            const token = t[i];
            i += 1;
            if (eq(token.text, "only")) o.only = true else if (eq(token.text, "unpack") or eq(token.text, "unpackpanel")) o.unpack = true else if (eq(token.text, "obsno")) o.obsno = true else if (eq(token.text, "maxpoints")) {
                if (!at(t, i, .eq)) return bad(d, t, i);
                i += 1;
                if (at(t, i, .name) and eq(t[i].text, "none")) {
                    o.maxpoints = std.math.maxInt(usize);
                    i += 1;
                } else {
                    if (!at(t, i, .number)) return bad(d, t, i);
                    o.maxpoints = std.fmt.parseInt(usize, t[i].text, 10) catch return bad(d, t, i);
                    i += 1;
                }
            } else return bad(d, t, i - 1);
        }
        i += 1;
    }
    if (!at(t, i, .eq)) {
        index.* = i;
        return o;
    }
    i += 1;
    const grouped = at(t, i, .lparen);
    if (grouped) i += 1;
    var requests: std.ArrayList(Request) = .empty;
    while (true) {
        if (!at(t, i, .name)) return bad(d, t, i);
        const token = t[i];
        i += 1;
        if (eq(token.text, "none")) o.none = true else {
            const kind: data.Kind = if (eq(token.text, "residualpanel")) .residual else if (eq(token.text, "studentpanel")) .student else if (eq(token.text, "pearsonpanel")) .pearson else {
                for ([_][]const u8{ "all", "boxplot", "distance", "influenceestplot", "influencestatpanel", "press", "vcirypanel" }) |known| if (eq(token.text, known)) return proc.failGap(d, token.line, "PROC MIXED: graph {s} is not implemented", .{token.text});
                return bad(d, t, i - 1);
            };
            var modes: std.ArrayList(data.Mode) = .empty;
            var unpack = o.unpack;
            if (at(t, i, .lparen)) {
                i += 1;
                while (!at(t, i, .rparen)) {
                    if (!at(t, i, .name)) return bad(d, t, i);
                    const option = t[i];
                    i += 1;
                    if (eq(option.text, "unpack") or eq(option.text, "unpackpanel")) unpack = true else if (eq(option.text, "box") or eq(option.text, "boxplot")) return proc.failGap(d, option.line, "PROC MIXED: residual box plots are not implemented", .{}) else {
                        const mode: data.Mode = if (eq(option.text, "marginal") or eq(option.text, "noblup")) .marginal else if (eq(option.text, "conditional") or eq(option.text, "blup")) .conditional else return bad(d, t, i - 1);
                        if (std.mem.indexOfScalar(data.Mode, modes.items, mode) == null) try modes.append(a, mode);
                    }
                }
                i += 1;
            }
            if (modes.items.len == 0) try modes.append(a, .conditional);
            for (modes.items) |mode| try requests.append(a, .{ .kind = kind, .mode = mode, .unpack = unpack });
        }
        if (!grouped) break;
        if (at(t, i, .rparen)) {
            i += 1;
            break;
        }
    }
    if (o.none and requests.items.len > 0) return d.fail(error.ParseError, t[index.*].line, "PROC MIXED: PLOTS=NONE cannot be combined with requests", .{});
    o.requests = requests.items;
    index.* = i;
    return o;
}
pub fn effective(a: A, o: Options, residual: bool) ![]const Request {
    if (o.none) return &.{};
    var result: std.ArrayList(Request) = .empty;
    if (residual and !o.only) for ([_]data.Kind{ .residual, .student, .pearson }) |kind| try result.append(a, .{ .kind = kind, .unpack = o.unpack });
    for (o.requests) |request| {
        var duplicate = false;
        for (result.items) |old| if (old.kind == request.kind and old.mode == request.mode and old.unpack == request.unpack) {
            duplicate = true;
            break;
        };
        if (!duplicate) try result.append(a, request);
    }
    return result.items;
}
pub fn active(cx: proc.ProcCtx) bool {
    const g = cx.graphics orelse return false;
    return g.enabled != false and (g.enabled == true or g.cli_dir != null or g.gpath != null);
}
pub fn validate(cx: proc.ProcCtx, s: anytype, m: anytype) diag.Error!void {
    if (!active(cx) or s.options.plots_none) return;
    const requests = try effective(cx.arena, s.options.plots, m.options.residual);
    if (requests.len > 0 and s.options.method != .reml) return proc.failGap(cx.diags, s.line, "PROC MIXED: requested residual plots for this estimation method are not implemented", .{});
}
const Part = enum { scatter, histogram, qq, panel };
pub const FitSummary = struct { objective: f64, aic: f64, aicc: ?f64, bic: ?f64 };
fn xml(a: A, value: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    for (value) |c| switch (c) {
        '&' => try result.appendSlice(a, "&amp;"),
        '<' => try result.appendSlice(a, "&lt;"),
        '>' => try result.appendSlice(a, "&gt;"),
        '"' => try result.appendSlice(a, "&quot;"),
        else => try result.append(a, c),
    };
    return result.items;
}
fn title(a: A, request: Request, variable: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}{s}Residuals for {s}", .{ if (request.mode == .conditional) @as([]const u8, "Conditional ") else "", switch (request.kind) {
        .residual => @as([]const u8, ""),
        .student => "Studentized ",
        .pearson => "Pearson ",
    }, variable });
}
fn graphName(request: Request, part: Part) svg.graph_ods.Name {
    return switch (request.kind) {
        .residual => switch (part) {
            .panel => .ResidualPanel,
            .scatter => .ResidualByPredicted,
            .histogram => .ResidualHistogram,
            .qq => .ResidualQQplot,
        },
        .student => switch (part) {
            .panel => .StudentPanel,
            .scatter => .StudentByPredicted,
            .histogram => .StudentHistogram,
            .qq => .StudentQQplot,
        },
        .pearson => switch (part) {
            .panel => .PearsonPanel,
            .scatter => .PearsonByPredicted,
            .histogram => .PearsonHistogram,
            .qq => .PearsonQQplot,
        },
    };
}
const Frame = struct {
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
    xmin: f64,
    xmax: f64,
    ymin: f64,
    ymax: f64,
    fn x(f: Frame, v: f64) f64 {
        return f.left + (f.right - f.left) * (v - f.xmin) / (f.xmax - f.xmin);
    }
    fn y(f: Frame, v: f64) f64 {
        return f.bottom - (f.bottom - f.top) * (v - f.ymin) / (f.ymax - f.ymin);
    }
};
fn range(lo: f64, hi: f64) [2]f64 {
    const pad = if (hi > lo) (hi - lo) * 0.07 else @max(0.5, @abs(lo) * 0.05);
    return .{ lo - pad, hi + pad };
}
fn axes(a: A, out: *std.ArrayList(u8), f: Frame, xlabel: []const u8, ylabel: []const u8) !void {
    try out.print(a, "<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"#fcfdff\" stroke=\"#a9b5c4\"/>", .{ f.left, f.top, f.right - f.left, f.bottom - f.top });
    for (0..5) |i| {
        const t = @as(f64, @floatFromInt(i)) / 4;
        const x = f.xmin + t * (f.xmax - f.xmin);
        const y = f.ymin + t * (f.ymax - f.ymin);
        try out.print(a, "<path d=\"M{d} {d}V{d} M{d} {d}H{d}\" stroke=\"#e4e9ef\" fill=\"none\"/><text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\">{s}</text><text x=\"{d}\" y=\"{d}\" text-anchor=\"end\">{s}</text>", .{ f.x(x), f.top, f.bottom, f.left, f.y(y), f.right, f.x(x), f.bottom + 18, try xml(a, try svg.label(a, x)), f.left - 8, f.y(y) + 4, try xml(a, try svg.label(a, y)) });
    }
    try out.print(a, "<text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\">{s}</text><text transform=\"translate({d} {d}) rotate(-90)\" text-anchor=\"middle\">{s}</text>", .{ (f.left + f.right) / 2, f.bottom + 40, xlabel, f.left - 68, (f.top + f.bottom) / 2, ylabel });
}
fn chart(a: A, out: *std.ArrayList(u8), s: data.Series, part: Part, ox: f64, oy: f64, width: f64, height: f64, obsno: bool) !void {
    var xmin = std.math.inf(f64);
    var xmax = -std.math.inf(f64);
    var ymin = s.minimum;
    var ymax = s.maximum;
    switch (part) {
        .scatter => {
            for (s.points) |p| {
                xmin = @min(xmin, p.predicted);
                xmax = @max(xmax, p.predicted);
            }
            ymin = @min(0, ymin);
            ymax = @max(0, ymax);
        },
        .qq => {
            xmin = s.qq[0].quantile;
            xmax = s.qq[s.qq.len - 1].quantile;
            if (s.sd) |sd| if (sd > 0) {
                ymin = @min(ymin, s.mean + sd * xmin);
                ymax = @max(ymax, s.mean + sd * xmax);
            };
        },
        .histogram => {
            xmin = s.bins[0].lower;
            xmax = s.bins[s.bins.len - 1].upper;
            ymin = 0;
            ymax = 0;
            for (s.bins) |b| ymax = @max(ymax, b.percent);
            for (s.normal) |p| {
                xmin = @min(xmin, p.x);
                xmax = @max(xmax, p.x);
                ymax = @max(ymax, p.y);
            }
        },
        else => unreachable,
    }
    const xr = range(xmin, xmax);
    const yr = if (part == .histogram) [2]f64{ 0, @max(1, ymax * 1.12) } else range(ymin, ymax);
    const f = Frame{ .left = ox + 88, .top = oy + 30, .right = ox + width - 20, .bottom = oy + height - 55, .xmin = xr[0], .xmax = xr[1], .ymin = yr[0], .ymax = yr[1] };
    if (!std.math.isFinite(f.xmax - f.xmin) or !std.math.isFinite(f.ymax - f.ymin)) return error.InvalidRange;
    try out.print(a, "<g data-panel=\"{s}\" data-xmin=\"{d}\" data-xmax=\"{d}\" data-ymin=\"{d}\" data-ymax=\"{d}\" data-left=\"{d}\" data-right=\"{d}\" data-top=\"{d}\" data-bottom=\"{d}\">", .{ @tagName(part), f.xmin, f.xmax, f.ymin, f.ymax, f.left, f.right, f.top, f.bottom });
    try axes(a, out, f, switch (part) {
        .scatter => "Predicted Mean",
        .qq => "Quantile",
        .histogram => "Residual",
        else => unreachable,
    }, if (part == .histogram) "Percent" else "Residual");
    if (part == .scatter) {
        try out.print(a, "<path class=\"zero-reference\" d=\"M{d} {d}H{d}\" stroke=\"#8b97a6\" stroke-dasharray=\"4 3\"/>", .{ f.left, f.y(0), f.right });
        for (s.points) |p| {
            try out.print(a, "<circle class=\"observation\" data-source=\"{d}\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"3\" fill=\"white\" stroke=\"#315e9d\"><title>", .{ p.source, p.predicted, p.value, f.x(p.predicted), f.y(p.value) });
            if (obsno) try out.print(a, "Observation {d}; ", .{p.source});
            try out.print(a, "Predicted {d}; Residual {d}</title></circle>", .{ p.predicted, p.value });
        }
    }
    if (part == .qq) {
        if (s.sd) |sd| if (sd > 0) try out.print(a, "<path class=\"normal-reference\" data-intercept=\"{d}\" data-slope=\"{d}\" d=\"M{d} {d}L{d} {d}\" fill=\"none\" stroke=\"#8b97a6\"/>", .{ s.mean, sd, f.x(f.xmin), f.y(s.mean + sd * f.xmin), f.x(f.xmax), f.y(s.mean + sd * f.xmax) });
        for (s.qq) |p| try out.print(a, "<circle class=\"quantile\" data-source=\"{d}\" data-probability=\"{d}\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"3\" fill=\"white\" stroke=\"#315e9d\"/>", .{ p.source, p.probability, p.quantile, p.value, f.x(p.quantile), f.y(p.value) });
    }
    if (part == .histogram) {
        for (s.bins) |b| try out.print(a, "<rect class=\"bin\" data-lower=\"{d}\" data-upper=\"{d}\" data-count=\"{d}\" data-percent=\"{d}\" x=\"{d:.3}\" y=\"{d:.3}\" width=\"{d:.3}\" height=\"{d:.3}\" fill=\"#bfcedf\" stroke=\"#66788d\"/>", .{ b.lower, b.upper, b.count, b.percent, f.x(b.lower), f.y(b.percent), f.x(b.upper) - f.x(b.lower), f.y(0) - f.y(b.percent) });
        if (s.normal.len > 0) {
            try out.appendSlice(a, "<polyline class=\"normal-density\" fill=\"none\" stroke=\"#315e9d\" stroke-width=\"2\" points=\"");
            for (s.normal) |p| try out.print(a, "{d:.3},{d:.3} ", .{ f.x(p.x), f.y(p.y) });
            try out.appendSlice(a, "\"/>");
            for (s.normal) |p| try out.print(a, "<circle class=\"density-coordinate\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"0\"/>", .{ p.x, p.y, f.x(p.x), f.y(p.y) });
            try out.print(a, "<path d=\"M{d} {d}h20\" stroke=\"#315e9d\" stroke-width=\"2\"/><text x=\"{d}\" y=\"{d}\">Normal density</text>", .{ f.left + 8, f.top + 14, f.left + 34, f.top + 18 });
        } else try out.print(a, "<text x=\"{d}\" y=\"{d}\">Normal curve unavailable</text>", .{ f.left + 8, f.top + 18 });
    }
    try out.appendSlice(a, "</g>");
}
pub fn render(a: A, label: []const u8, s: data.Series, request: Request, part: Part, summary: ?FitSummary, obsno: bool) ![]const u8 {
    const width: usize = if (part == .panel) 900 else 620;
    const height: usize = if (part == .panel) 700 else 410;
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" role=\"img\" data-graph=\"{s}\" data-mode=\"{s}\" data-residual=\"{s}\"><title>{s}</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><g font-family=\"Arial,sans-serif\" font-size=\"11\" fill=\"#26364a\"><text x=\"{d}\" y=\"28\" text-anchor=\"middle\" font-size=\"18\" font-weight=\"bold\">{s}</text>", .{ width, height, width, height, @tagName(graphName(request, part)), @tagName(request.mode), @tagName(request.kind), try xml(a, label), width / 2, try xml(a, label) });
    try out.print(a, "<metadata data-observations=\"{d}\" data-missing=\"{d}\" data-mean=\"{d}\" data-minimum=\"{d}\" data-maximum=\"{d}\" data-sd=\"{s}\"/>", .{ s.points.len, s.missing, s.mean, s.minimum, s.maximum, if (s.sd) |sd| try std.fmt.allocPrint(a, "{d}", .{sd}) else "." });
    if (part == .panel) {
        try chart(a, &out, s, .scatter, 0, 45, 450, 300, obsno);
        try chart(a, &out, s, .histogram, 450, 45, 450, 300, obsno);
        try chart(a, &out, s, .qq, 0, 355, 450, 300, obsno);
        try out.appendSlice(a, "<g data-panel=\"statistics\"><text x=\"520\" y=\"395\" font-weight=\"bold\">Residual Statistics</text>");
        const lines = [_][]const u8{ try std.fmt.allocPrint(a, "Observations: {d}", .{s.points.len}), try std.fmt.allocPrint(a, "Missing residuals: {d}", .{s.missing}), try std.fmt.allocPrint(a, "Minimum: {d:.4}", .{s.minimum}), try std.fmt.allocPrint(a, "Mean: {d:.4}", .{s.mean}), try std.fmt.allocPrint(a, "Maximum: {d:.4}", .{s.maximum}), if (s.sd) |sd| try std.fmt.allocPrint(a, "Std Dev: {d:.4}", .{sd}) else "Std Dev: ." };
        for (lines, 0..) |line, i| try out.print(a, "<text x=\"520\" y=\"{d}\">{s}</text>", .{ 417 + i * 19, line });
        if (summary) |fit| {
            try out.appendSlice(a, "<text x=\"520\" y=\"552\" font-weight=\"bold\">Fit Statistics</text>");
            const fit_lines = [_][]const u8{ try std.fmt.allocPrint(a, "Objective: {d:.3}", .{fit.objective}), try std.fmt.allocPrint(a, "AIC: {d:.3}", .{fit.aic}), if (fit.aicc) |v| try std.fmt.allocPrint(a, "AICC: {d:.3}", .{v}) else "AICC: .", if (fit.bic) |v| try std.fmt.allocPrint(a, "BIC: {d:.3}", .{v}) else "BIC: ." };
            for (fit_lines, 0..) |line, i| try out.print(a, "<text x=\"520\" y=\"{d}\">{s}</text>", .{ 574 + i * 19, line });
        } else try out.appendSlice(a, "<text x=\"520\" y=\"552\">Covariance supplied (NOITER)</text>");
        try out.appendSlice(a, "</g>");
    } else try chart(a, &out, s, part, 0, 45, 620, 340, obsno);
    try out.appendSlice(a, "</g></svg>");
    return out.items;
}
pub fn execute(cx: proc.ProcCtx, s: anytype, m: anytype, group: anytype, x: anytype, z: anytype, fit: anytype, by_index: ?usize) diag.Error!void {
    if (!active(cx) or s.options.plots_none) return;
    const requests = try effective(cx.arena, s.options.plots, m.options.residual);
    if (requests.len == 0) return;
    if (x.matrix.n > s.options.plots.maxpoints) {
        try cx.diags.note(s.line, "PROC MIXED: residual graphs suppressed by MAXPOINTS={d}", .{s.options.plots.maxpoints});
        return;
    }
    const values = data.compute(cx.arena, x, z, fit) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED: residual plot covariance is not implemented for this boundary ({t})", .{err});
    const summary: ?FitSummary = if (fit.status == .evaluated) null else .{ .objective = fit.minus2loglik, .aic = fit.aic, .aicc = fit.aicc, .bic = fit.bic };
    var subtitle: std.ArrayList(u8) = .empty;
    if (s.roles.by.len > 0) try @import("by_groups.zig").appendLine(cx.arena, &subtitle, s.input.ds, group.raw.observations[0].cells, s.roles.by);
    for (requests, 0..) |request, order| {
        const series = data.series(cx.arena, values, request.kind, request.mode) catch |err| {
            if (err == error.NoFiniteResiduals) {
                try cx.diags.note(s.line, "PROC MIXED: no finite residuals for requested {s} plot", .{@tagName(request.kind)});
                continue;
            }
            return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED: residual graph numerical boundary ({t})", .{err});
        };
        const heading = try title(cx.arena, request, s.input.ds.columns.items[m.matrix.response].label orelse s.input.ds.columns.items[m.matrix.response].name);
        const label = if (subtitle.items.len > 0) try std.fmt.allocPrint(cx.arena, "{s} — {s}", .{ heading, std.mem.trim(u8, subtitle.items, " \r\n") }) else heading;
        const parts: []const Part = if (request.unpack) &.{ .scatter, .histogram, .qq } else &.{.panel};
        for (parts, 0..) |part, k| {
            const name = graphName(request, part);
            const object = try svg.graph_ods.mixed(cx.arena, name, by_index, label);
            const bytes = render(cx.arena, label, series, request, part, summary, s.options.plots.obsno) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED: residual graph rendering boundary ({t})", .{err});
            try cx.graphics.?.queue(((by_index orelse 1) - 1) * requests.len * 3 + order * 3 + k, try std.ascii.allocLowerString(cx.arena, @tagName(name)), bytes, object);
        }
    }
}

pub fn attribute(text: []const u8, key: []const u8) !f64 {
    var buffer: [80]u8 = undefined;
    const prefix = try std.fmt.bufPrint(&buffer, "{s}=\"", .{key});
    const start = (std.mem.indexOf(u8, text, prefix) orelse return error.MissingAttribute) + prefix.len;
    const end = std.mem.indexOfScalarPos(u8, text, start, '"') orelse return error.MissingAttribute;
    return std.fmt.parseFloat(f64, text[start..end]);
}
pub fn verifyGeometry(bytes: []const u8) !void {
    // Independent affine coordinate equation, checked against SVG's declared
    // ranges, for every actual circle (scatter,QQ,density). 0.0005 is half of
    // the renderer's three-decimal pixel unit, not a statistical tolerance.
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, cursor, "<g data-panel=")) |begin| {
        const header_end = std.mem.indexOfScalarPos(u8, bytes, begin, '>') orelse return error.MissingAttribute;
        const end = std.mem.indexOfPos(u8, bytes, header_end, "</g>") orelse return error.MissingAttribute;
        cursor = end + 4;
        const header = bytes[begin..header_end];
        if (std.mem.indexOf(u8, header, "statistics") != null) continue;
        const xmin = try attribute(header, "data-xmin");
        const xmax = try attribute(header, "data-xmax");
        const ymin = try attribute(header, "data-ymin");
        const ymax = try attribute(header, "data-ymax");
        const left = try attribute(header, "data-left");
        const right = try attribute(header, "data-right");
        const top = try attribute(header, "data-top");
        const bottom = try attribute(header, "data-bottom");
        var position = header_end;
        while (std.mem.indexOfPos(u8, bytes[0..end], position, "<circle ")) |point| {
            const stop = std.mem.indexOfScalarPos(u8, bytes, point, '>') orelse return error.MissingAttribute;
            const tag = bytes[point..stop];
            position = stop + 1;
            const x = try attribute(tag, "data-x");
            const y = try attribute(tag, "data-y");
            const cx = try attribute(tag, "cx");
            const cy = try attribute(tag, "cy");
            try std.testing.expectApproxEqAbs(left + (right - left) * (x - xmin) / (xmax - xmin), cx, 0.000501);
            try std.testing.expectApproxEqAbs(bottom - (bottom - top) * (y - ymin) / (ymax - ymin), cy, 0.000501);
            try std.testing.expect(cx >= left - 0.001 and cx <= right + 0.001 and cy >= top - 0.001 and cy <= bottom + 0.001);
        }
    }
}

test "MIXED017 plot option defaults NONE ONLY UNPACK MAXPOINTS and unsupported requests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var i: usize = 0;
    const t = try lex.tokenize(a, "plots(only obsno maxpoints=10)=(studentpanel(marginal conditional unpack) residualpanel)", &d);
    const o = try parse(a, &d, t, &i);
    try std.testing.expect(o.only and o.obsno);
    try std.testing.expectEqual(@as(usize, 10), o.maxpoints);
    try std.testing.expectEqual(@as(usize, 3), o.requests.len);
    try std.testing.expect(o.requests[0].unpack);
    try std.testing.expectEqual(data.Mode.marginal, o.requests[0].mode);
    try std.testing.expectEqual(@as(usize, 0), (try effective(a, .{}, false)).len);
    try std.testing.expectEqual(@as(usize, 3), (try effective(a, .{}, true)).len);
    try std.testing.expectEqual(@as(usize, 0), (try effective(a, .{ .none = true }, true)).len);
    i = 0;
    const none = try parse(a, &d, try lex.tokenize(a, "plot=none", &d), &i);
    try std.testing.expect(none.none);
    for ([_][]const u8{ "plots=all", "plots=boxplot", "plots=residualpanel(box)", "plots=influenceestplot" }) |code| {
        i = 0;
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, parse(a, &d, try lex.tokenize(a, code, &d), &i));
        try std.testing.expect(diag.gapHit());
    }
}
