//! PROC CORR PLOTS= selection, scatter matrices and Hotelling ellipses.
//! SAS Statistical Procedures, printed pp. 12–14, 32–33, examples 2.8–2.9.
const std = @import("std");
const proc = @import("../proc.zig");
const corr = @import("corr.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const svg = @import("graphics_svg.zig");
const Value = @import("../value.zig").Value;
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;
const W = std.Io.Writer;
const Ellipse = enum { prediction, confidence, none };
const Request = struct { kind: enum { scatter, matrix }, nvar: usize = 5, nwith: usize = 5, histogram: bool = false, inset: bool = true, ellipse: Ellipse = .prediction, alpha: []const f64 = &.{0.05} };
pub const Options = struct { requests: []const Request = &.{}, max_points: usize = 5000 };

fn tok(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn integer(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, unlimited: []const u8) diag.Error!usize {
    if (tok(t, i.*, .name) and eq(t[i.*].text, unlimited)) {
        i.* += 1;
        return std.math.maxInt(usize);
    }
    if (!tok(t, i.*, .number)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: plot option requires a positive integer or {s}", .{unlimited});
    const count = std.fmt.parseInt(usize, t[i.*].text, 10) catch return cx.diags.fail(error.ParseError, 0, "PROC CORR: invalid plot limit", .{});
    if (count == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: plot limit must be positive", .{});
    i.* += 1;
    return count;
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!Options {
    var opt = Options{};
    var list: std.ArrayList(Request) = .empty;
    i.* += 1;
    if (tok(t, i.*, .lparen)) {
        i.* += 1;
        if (!tok(t, i.*, .name) or !eq(t[i.*].text, "maxpoints") or !tok(t, i.* + 1, .eq)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: expected PLOTS(MAXPOINTS=...)", .{});
        i.* += 2;
        opt.max_points = try integer(cx, t, i, "none");
        if (!tok(t, i.*, .rparen)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: unclosed PLOTS option", .{});
        i.* += 1;
    }
    if (!tok(t, i.*, .eq)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: PLOTS requires a plot request", .{});
    i.* += 1;
    const grouped = tok(t, i.*, .lparen);
    if (grouped) i.* += 1;
    while (true) {
        if (!tok(t, i.*, .name)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: expected a plot name", .{});
        const name = t[i.*].text;
        i.* += 1;
        if (eq(name, "all")) {
            try list.appendSlice(cx.arena, &.{ .{ .kind = .scatter }, .{ .kind = .matrix } });
        } else if (eq(name, "none")) {
            list.clearRetainingCapacity();
        } else {
            var req = Request{ .kind = if (eq(name, "scatter")) .scatter else if (eq(name, "matrix")) .matrix else return cx.diags.fail(error.ParseError, 0, "PROC CORR: unknown plot request {s}", .{name}) };
            if (tok(t, i.*, .lparen)) {
                i.* += 1;
                while (!tok(t, i.*, .rparen)) {
                    if (!tok(t, i.*, .name)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: expected plot option", .{});
                    const key = t[i.*].text;
                    i.* += 1;
                    if (req.kind == .matrix and (eq(key, "hist") or eq(key, "histogram"))) {
                        req.histogram = true;
                        continue;
                    }
                    if (req.kind == .scatter and eq(key, "noinset")) {
                        req.inset = false;
                        continue;
                    }
                    if (!tok(t, i.*, .eq)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: option {s} requires =", .{key});
                    i.* += 1;
                    if (eq(key, "nvar") or eq(key, "nwith")) {
                        const n = @min(10, try integer(cx, t, i, "all"));
                        if (eq(key, "nvar")) req.nvar = n else req.nwith = n;
                    } else if (req.kind == .scatter and eq(key, "ellipse")) {
                        if (!tok(t, i.*, .name)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: expected ellipse type", .{});
                        const val = t[i.*].text;
                        req.ellipse = if (eq(val, "confidence")) .confidence else if (eq(val, "prediction")) .prediction else if (eq(val, "none")) .none else return cx.diags.fail(error.ParseError, 0, "PROC CORR: invalid ellipse type", .{});
                        i.* += 1;
                    } else if (req.kind == .scatter and eq(key, "alpha")) {
                        var alphas: std.ArrayList(f64) = .empty;
                        while (tok(t, i.*, .number)) {
                            const alpha = std.fmt.parseFloat(f64, t[i.*].text) catch return cx.diags.fail(error.ParseError, 0, "PROC CORR: invalid ellipse alpha", .{});
                            if (!(alpha > 0 and alpha < 1)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: ellipse alpha must be between 0 and 1", .{});
                            try alphas.append(cx.arena, alpha);
                            i.* += 1;
                        }
                        if (alphas.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: expected ellipse alpha", .{});
                        req.alpha = alphas.items;
                    } else return cx.diags.fail(error.ParseError, 0, "PROC CORR: unsupported plot option {s}", .{key});
                }
                i.* += 1;
            }
            try list.append(cx.arena, req);
        }
        if (!grouped) break;
        if (tok(t, i.*, .rparen)) {
            i.* += 1;
            break;
        }
    }
    opt.requests = list.items;
    return opt;
}

const XY = struct { x: f64, y: f64 };
const Cell = struct { points: []const XY, pair: corr.Pair, xr: svg.Range, yr: svg.Range };
const PointRows = struct { row: []const Value, weight: f64 };
fn center(v: []f64, rows: []const PointRows) void {
    var sum: f64 = 0;
    var mean: f64 = 0;
    var origin: f64 = 0;
    for (v, rows) |x, r| {
        if (r.weight == 0) continue;
        if (sum == 0) origin = x;
        sum += r.weight;
        mean += ((x - origin) - mean) * (r.weight / sum);
    }
    for (v) |*x| x.* = (x.* - origin) - mean;
}
fn residualize(a: A, s: corr.Spec, rows: []const PointRows, x: []f64, y: []f64) !void {
    center(x, rows);
    center(y, rows);
    var basis: std.ArrayList([]const f64) = .empty;
    for (s.partial) |col| {
        const v = try a.alloc(f64, rows.len);
        for (v, rows) |*n, r| n.* = r.row[col].num;
        center(v, rows);
        const original = dot(v, v, rows);
        for (basis.items) |q| subtract(v, q, dot(v, q, rows));
        const length = dot(v, v, rows);
        if (!(length > 0) or length < s.options.singular * original) continue;
        for (v) |*n| n.* /= @sqrt(length);
        try basis.append(a, v);
        subtract(x, v, dot(x, v, rows));
        subtract(y, v, dot(y, v, rows));
    }
}
fn dot(x: []const f64, y: []const f64, rows: []const PointRows) f64 {
    var sum: f64 = 0;
    for (x, y, rows) |l, r, p| sum += l * r * p.weight;
    return sum;
}
fn subtract(x: []f64, y: []const f64, k: f64) void {
    for (x, y) |*v, q| v.* -= k * q;
}
fn cell(a: A, s: corr.Spec, g: corr.Group, xi: usize, yi: usize) !Cell {
    const xc = s.vars[xi];
    const yc = (if (s.with.len > 0) s.with else s.vars)[yi];
    const pair = g.pairs[yi * s.vars.len + xi];
    var accepted: std.ArrayList(PointRows) = .empty;
    for (g.rows) |row| {
        const mass = corr.mass(s, row) orelse continue;
        if (row[xc].isMissing() or row[yc].isMissing()) continue;
        try accepted.append(a, .{ .row = row, .weight = mass.w });
    }
    const x = try a.alloc(f64, accepted.items.len);
    const y = try a.alloc(f64, accepted.items.len);
    for (accepted.items, x, y) |p, *u, *v| {
        u.* = p.row[xc].num;
        v.* = p.row[yc].num;
    }
    if (s.partial.len > 0) try residualize(a, s, accepted.items, x, y);
    var xr = svg.Range{};
    var yr = svg.Range{};
    const points = try a.alloc(XY, x.len);
    for (points, x, y) |*p, u, v| {
        p.* = .{ .x = u, .y = v };
        xr.add(u);
        yr.add(v);
    }
    if (points.len == 0) {
        xr = .{ .lo = 0, .hi = 1 };
        yr = xr;
    }
    return .{ .points = points, .pair = pair, .xr = xr.padded(), .yr = yr.padded() };
}
fn open(w: *W, width: f64, height: f64, kind: []const u8, name: []const u8) !void {
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" role=\"img\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\" data-kind=\"{s}\"><title>{s}</title><style>text{{font:12px system-ui,sans-serif;fill:#1d2935}}.heading{{font-size:18px;font-weight:600}}.axes path,.frame{{stroke:#85909b;fill:none}}.point{{stroke:#285789;fill:white;stroke-width:1.3}}.ellipse{{stroke:#995034;stroke-width:1.4;fill:none}}.bin{{stroke:#687f96;fill:#dce9f5}}</style><rect width=\"100%\" height=\"100%\" fill=\"white\"/>", .{ width, height, width, height, kind, name });
    try w.print("<text class=\"heading\" text-anchor=\"middle\" x=\"{d}\" y=\"25\">{s}</text>", .{ width / 2, name });
}
fn axisName(a: A, s: corr.Spec, col: usize) ![]const u8 {
    const c = s.ds.columns.items[col];
    const name = c.label orelse c.name;
    return if (s.partial.len > 0) try std.fmt.allocPrint(a, "{s} residual", .{name}) else name;
}
fn groupKeys(a: A, w: *W, s: corr.Spec, g: corr.Group, width: f64) !void {
    if (g.by_values) |row| if (s.by.len > 0) {
        try w.print("<text text-anchor=\"middle\" x=\"{d}\" y=\"45\">", .{width / 2});
        for (s.by, 0..) |c, i| {
            if (i > 0) try w.writeAll("   ");
            try svg.escaped(w, s.ds.columns.items[c].name);
            try w.writeAll(" = ");
            const v = row[c];
            const value = if (v == .str) v.str else try @import("../format.zig").apply(a, v, s.ds.columns.items[c].format orelse "BEST12.");
            try svg.escaped(w, std.mem.trim(u8, value, " "));
        }
        try w.writeAll("</text>");
    };
}
const Frame = struct {
    left: f64,
    right: f64,
    top: f64,
    bottom: f64,
    xr: svg.Range,
    yr: svg.Range,
    fn x(f: Frame, v: f64) f64 {
        return f.left + (v - f.xr.lo) / (f.xr.hi - f.xr.lo) * (f.right - f.left);
    }
    fn y(f: Frame, v: f64) f64 {
        return f.bottom - (v - f.yr.lo) / (f.yr.hi - f.yr.lo) * (f.bottom - f.top);
    }
};
fn drawPoints(w: *W, points: []const XY, f: Frame, rad: f64) !void {
    for (points) |p| try w.print("<circle class=\"point\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.2}\" cy=\"{d:.2}\" r=\"{d}\"/>", .{ p.x, p.y, f.x(p.x), f.y(p.y), rad });
}
fn scatter(a: A, s: corr.Spec, g: corr.Group, c: Cell, req: Request) ![]const u8 {
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try open(w, 690, 460, "scatter", if (s.partial.len == 0) "Scatter Plot" else "Partial Residual Scatter Plot");
    try groupKeys(a, w, s, g, 690);
    const b = svg.Bounds{ .x = c.xr, .y = c.yr, .top = 66, .bottom = 394 };
    const f = Frame{ .left = svg.Bounds.left, .right = svg.Bounds.right, .top = b.top, .bottom = b.bottom, .xr = b.x, .yr = b.y };
    try w.print("<g class=\"axes\"><path d=\"M{d} {d}V{d}H{d}\"/>", .{ f.left, f.top, f.bottom, f.right });
    for (0..6) |i| {
        const t = @as(f64, @floatFromInt(i)) / 5;
        try svg.tick(a, w, b, true, b.x.at(t), b.x.at(t));
        try svg.tick(a, w, b, false, b.y.at(t), b.y.at(t));
    }
    try w.writeAll("</g><text class=\"axis-x\" x=\"374\" y=\"449\" text-anchor=\"middle\">");
    try svg.escaped(w, try axisName(a, s, c.pair.column));
    try w.writeAll("</text><text class=\"axis-y\" transform=\"translate(18 230) rotate(-90)\" text-anchor=\"middle\">");
    try svg.escaped(w, try axisName(a, s, c.pair.row));
    try w.writeAll("</text>");
    try w.print("<clipPath id=\"frame\"><rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/></clipPath><g clip-path=\"url(#frame)\">", .{ f.left, f.top, f.right - f.left, f.bottom - f.top });
    const p = c.pair;
    const has_ellipse = req.ellipse != .none and p.n > 2 and p.variance_x > 0 and p.variance_y > 0 and @abs(p.r) < 1;
    if (has_ellipse) {
        const mx = if (s.partial.len == 0) p.mean_x else 0;
        const my = if (s.partial.len == 0) p.mean_y else 0;
        const sx = @sqrt(p.variance_x);
        const sy = @sqrt(p.variance_y);
        for (req.alpha) |alpha| {
            // Hotelling's T² critical value using the closed form of F(2,n−2).
            const k = (p.n - 1) / p.n * std.math.expm1(-2 * @log(alpha) / (p.n - 2)) * (if (req.ellipse == .prediction) p.n + 1 else @as(f64, 1));
            const radius = @sqrt(k);
            try w.print("<path class=\"ellipse\" data-type=\"{s}\" data-alpha=\"{d}\" data-factor=\"{d}\" d=\"", .{ @tagName(req.ellipse), alpha, k });
            for (0..129) |j| {
                const angle = 2 * std.math.pi * @as(f64, @floatFromInt(j)) / 128;
                const u = @cos(angle);
                const v = @sin(angle);
                try w.print("{s}{d:.2} {d:.2}", .{ if (j == 0) "M" else " L", f.x(mx + radius * sx * u), f.y(my + radius * sy * (p.r * u + @sqrt(1 - p.r * p.r) * v)) });
            }
            try w.writeAll("Z\"/>");
        }
    }
    try drawPoints(w, c.points, f, 3);
    try w.writeAll("</g>");
    if (req.inset) {
        const l = @import("univ_graph_annotations.zig").Line;
        const prob = if (std.math.isFinite(p.p)) try @import("../format.zig").apply(a, .{ .num = p.p }, "PVALUE6.4") else ".";
        try svg.drawInset(w, .{ .lines = &[_]l{ .{ .key = "Observations", .value = try svg.label(a, p.n) }, .{ .key = "Correlation", .value = if (std.math.isFinite(p.r)) try svg.label(a, p.r) else "." }, .{ .key = "p-Value", .value = std.mem.trim(u8, prob, " ") } }, .pos = .nw }, b);
    }
    if (has_ellipse) {
        try w.writeAll("<text class=\"legend\" x=\"660\" y=\"59\" text-anchor=\"end\">");
        for (req.alpha, 0..) |alpha, i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("{s}%", .{try svg.label(a, 100 * (1 - alpha))});
        }
        try w.print(" {s} ellipse</text>", .{@tagName(req.ellipse)});
    }
    try w.writeAll("</svg>");
    return out.written();
}

fn matrix(a: A, d: *diag.Diagnostics, s: corr.Spec, g: corr.Group, req: Request) ![]const u8 {
    const cols = s.vars[0..@min(s.vars.len, req.nvar)];
    const sym = s.with.len == 0;
    const rows = if (sym) cols else s.with[0..@min(s.with.len, req.nwith)];
    const tile: f64 = 158;
    const width = 95 + tile * @as(f64, @floatFromInt(cols.len));
    const height = 100 + tile * @as(f64, @floatFromInt(rows.len));
    var charts = try a.alloc(Cell, rows.len * cols.len);
    const xdomains = try a.alloc(svg.Range, cols.len);
    @memset(xdomains, .{});
    const ydomains = try a.alloc(svg.Range, rows.len);
    @memset(ydomains, .{});
    for (rows, 0..) |_, yi| for (cols, 0..) |_, xi| {
        const c = try cell(a, s, g, xi, yi);
        charts[yi * cols.len + xi] = c;
        for (c.points) |p| {
            xdomains[xi].add(p.x);
            ydomains[yi].add(p.y);
        }
    };
    for (xdomains) |*xr| xr.* = if (std.math.isFinite(xr.lo)) xr.padded() else .{ .lo = 0, .hi = 1 };
    for (ydomains) |*yr| yr.* = if (std.math.isFinite(yr.lo)) yr.padded() else .{ .lo = 0, .hi = 1 };
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    try open(w, width, height, "matrix", "Scatter Plot Matrix");
    try groupKeys(a, w, s, g, width);
    for (rows, 0..) |yc, yi| for (cols, 0..) |xc, xi| {
        const left = 72 + tile * @as(f64, @floatFromInt(xi));
        const top = 63 + tile * @as(f64, @floatFromInt(yi));
        const f = Frame{ .left = left, .right = left + tile - 4, .top = top, .bottom = top + tile - 4, .xr = xdomains[xi], .yr = ydomains[yi] };
        const c = charts[yi * cols.len + xi];
        try w.writeAll("<g class=\"panel\" data-x-variable=\"");
        try svg.escaped(w, s.ds.columns.items[xc].name);
        try w.writeAll("\" data-y-variable=\"");
        try svg.escaped(w, s.ds.columns.items[yc].name);
        try w.writeAll("\">");
        try w.print("<rect class=\"frame\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/>", .{ left, top, tile - 4, tile - 4 });
        if (yi == 0) {
            try w.print("<text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\">", .{ left + tile / 2, top - 7 });
            try svg.escaped(w, try axisName(a, s, xc));
            try w.writeAll("</text>");
        }
        if (xi == 0) {
            try w.print("<text transform=\"translate(17 {d}) rotate(-90)\" text-anchor=\"middle\">", .{top + tile / 2});
            try svg.escaped(w, try axisName(a, s, yc));
            try w.writeAll("</text>");
        }
        if (sym and xc == yc) {
            if (req.histogram and c.points.len != 0) {
                const binning = @import("univ_histogram_bins.zig");
                const hist = @import("univ_histogram_output.zig");
                const sorted = try a.alloc(f64, c.points.len);
                for (sorted, c.points) |*v, p| v.* = p.x;
                std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
                const plan = try binning.determine(a, d, &.{.{ .sorted = sorted }}, .{});
                const bins = try hist.bins(a, d, sorted, plan.endpoints, .{ .bin_width = plan.width }, null);
                var max_count: usize = 1;
                for (bins) |b| max_count = @max(max_count, b.count);
                if (bins.len > 0) {
                    const inner = Frame{ .left = f.left + 3, .right = f.right - 3, .top = f.top + 6, .bottom = f.bottom - 1, .xr = .{ .lo = bins[0].lower, .hi = bins[bins.len - 1].upper }, .yr = .{ .lo = 0, .hi = @floatFromInt(max_count) } };
                    for (bins) |b| {
                        const bh = inner.y(@floatFromInt(b.count));
                        try w.print("<rect class=\"bin\" data-count=\"{d}\" x=\"{d:.2}\" y=\"{d:.2}\" width=\"{d:.2}\" height=\"{d:.2}\"/>", .{ b.count, inner.x(b.lower), bh, inner.x(b.upper) - inner.x(b.lower), inner.bottom - bh });
                    }
                }
            } else {
                try w.print("<text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\">", .{ left + tile / 2, top + tile / 2 });
                try svg.escaped(w, try axisName(a, s, xc));
                try w.writeAll("</text>");
            }
        } else try drawPoints(w, c.points, f, 2.1);
        if (yi + 1 == rows.len) for (0..3) |j| {
            const x = f.xr.at((0.15 + 0.35 * @as(f64, @floatFromInt(j))));
            try w.print("<text text-anchor=\"middle\" x=\"{d:.2}\" y=\"{d:.2}\">{s}</text>", .{ f.x(x), f.bottom + 16, try svg.label(a, x) });
        };
        if (xi == 0) for (0..3) |j| {
            const y = f.yr.at((0.15 + 0.35 * @as(f64, @floatFromInt(j))));
            try w.print("<text text-anchor=\"end\" x=\"{d:.2}\" y=\"{d:.2}\">{s}</text>", .{ left - 5, f.y(y) + 4, try svg.label(a, y) });
        };
        try w.writeAll("</g>");
    };
    try w.writeAll("</svg>");
    return out.written();
}
pub fn execute(cx: proc.ProcCtx, r: corr.Result) diag.Error!void {
    const s = r.spec;
    const opt = s.options.plots;
    if (opt.requests.len == 0 or s.options.noprint) return;
    const session = cx.graphics orelse return proc.failGap(cx.diags, 0, "PROC CORR: PLOTS requires a graphics consumer", .{});
    if (session.enabled == false) return;
    var warned = false;
    for (r.groups) |g| for (opt.requests) |req| {
        if (g.rows.len > opt.max_points) {
            if (!warned) try cx.diags.warn(0, "Scatter plots with more than {d} points have been suppressed. Use the PLOTS(MAXPOINTS= ) option in the PROC CORR statement to change or override the cutoff.", .{opt.max_points});
            warned = true;
            continue;
        }
        if (req.kind == .matrix) {
            if (s.vars.len == 0) continue;
            const bytes = matrix(cx.arena, cx.diags, s, g, req) catch |e| return if (e == error.ParseError) error.ParseError else error.OutOfMemory;
            try session.queue(0, "matrix", bytes);
        } else {
            const nr = if (s.with.len > 0) @min(s.with.len, req.nwith) else @min(s.vars.len, req.nvar);
            for (0..nr) |y| for (0..@min(s.vars.len, req.nvar)) |x| {
                if (s.with.len == 0 and x >= y) continue;
                const c = try cell(cx.arena, s, g, x, y);
                if (c.points.len == 0) continue;
                const bytes = scatter(cx.arena, s, g, c, req) catch return error.OutOfMemory;
                try session.queue(0, "scatter", bytes);
            };
        }
    };
}
