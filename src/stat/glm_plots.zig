//! Native default GLM FitPlot and IntPlot for the documented foundation models.
//! S154 physical pp.4061,4064,4170–4172. Unsupported graph families stay loud.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const svg = @import("graphics_svg.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");
const A = std.mem.Allocator;
const W = std.Io.Writer;
pub const CurvePoint = struct { x: f64, predicted: f64, lower_mean: f64, upper_mean: f64, lower_individual: f64, upper_individual: f64 };
const colors = [_][]const u8{ "#245e9b", "#b04f27", "#40804c", "#8455a2", "#a67e18", "#267d83" };

fn predictor(spec: parse.Spec) ?usize {
    if (spec.classes.len != 0 or spec.effects.len == 0) return null;
    const ci = spec.effects[0].variables[0];
    for (spec.effects) |effect| for (effect.variables) |column| {
        if (column != ci) return null;
    };
    return ci;
}
pub fn curve(a: A, spec: parse.Spec, d: design.Design, result: math.Result) diag.Error![]CurvePoint {
    const ci = predictor(spec) orelse return error.ExecError;
    const fitted = result.model.fit;
    if (fitted.df_error == 0 or !std.math.isFinite(fitted.mse)) return error.ExecError;
    var range: svg.Range = .{};
    for (d.observations) |row| range.add(row.cells[ci].num);
    const critical = @import("reg_fit.zig").tCritical(spec.alpha, fitted.df_error);
    const out = try a.alloc(CurvePoint, 101);
    const basis = try a.alloc(f64, d.p);
    for (out, 0..) |*point, i| {
        const x = range.at(@as(f64, @floatFromInt(i)) / 100);
        if (spec.intercept) basis[0] = 1;
        for (spec.effects, d.effects) |effect, block| {
            var power: f64 = 1;
            for (effect.variables) |_| power *= x;
            basis[block.start] = power;
        }
        var prediction: f64 = 0;
        var variance: f64 = 0;
        for (0..d.p) |j| {
            prediction += basis[j] * fitted.coefficients[j];
            for (0..d.p) |k| variance += basis[j] * fitted.covariance[j * d.p + k] * basis[k];
        }
        if (!std.math.isFinite(prediction) or !std.math.isFinite(variance)) return error.ExecError;
        // A tiny negative quadratic form can result from cancellation; a
        // materially negative covariance quadratic form is a numerical failure.
        if (variance < -128 * std.math.floatEps(f64) * @max(1, fitted.mse)) return error.ExecError;
        variance = @max(0, variance);
        const mean_radius = critical * @sqrt(variance);
        const individual_radius = critical * @sqrt(variance + fitted.mse);
        point.* = .{ .x = x, .predicted = prediction, .lower_mean = prediction - mean_radius, .upper_mean = prediction + mean_radius, .lower_individual = prediction - individual_radius, .upper_individual = prediction + individual_radius };
    }
    return out;
}
fn open(w: *W, name: []const u8, title: ?[]const u8) !void {
    try w.writeAll("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"760\" height=\"510\" viewBox=\"0 0 760 510\" role=\"img\"><title>");
    try svg.escaped(w, name);
    try w.writeAll("</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:12px system-ui,sans-serif;fill:#243447}.heading{font-size:17px;font-weight:600}.axes path{stroke:#7d8995;fill:none}</style><text class=\"heading\" x=\"380\" y=\"26\" text-anchor=\"middle\">");
    try svg.escaped(w, title orelse name);
    try w.writeAll("</text>");
}
fn axes(a: A, w: *W, b: svg.Bounds, xlabel: []const u8, ylabel: []const u8, numeric_x: bool) !void {
    try w.print("<g class=\"axes\"><path d=\"M88 {d}V{d}H660\"/>", .{ b.top, b.bottom });
    for (0..6) |i| {
        const t = @as(f64, @floatFromInt(i)) / 5;
        if (numeric_x) try svg.tick(a, w, b, true, b.x.at(t), b.x.at(t));
        try svg.tick(a, w, b, false, b.y.at(t), b.y.at(t));
    }
    try w.writeAll("</g><text x=\"374\" y=\"460\" text-anchor=\"middle\">");
    try svg.escaped(w, xlabel);
    try w.writeAll("</text><text transform=\"translate(20 245) rotate(-90)\" text-anchor=\"middle\">");
    try svg.escaped(w, ylabel);
    try w.writeAll("</text>");
}
fn band(w: *W, b: svg.Bounds, points: []const CurvePoint, individual: bool) !void {
    try w.print("<polygon data-kind=\"{s}\" fill=\"{s}\" stroke=\"none\" points=\"", .{ if (individual) @as([]const u8, "individual-confidence") else "mean-confidence", if (individual) @as([]const u8, "#edf2f7") else "#c7dbee" });
    for (points) |p| try w.print("{d:.3},{d:.3} ", .{ b.px(p.x), b.py(if (individual) p.lower_individual else p.lower_mean) });
    var i = points.len;
    while (i > 0) {
        i -= 1;
        const p = points[i];
        try w.print("{d:.3},{d:.3} ", .{ b.px(p.x), b.py(if (individual) p.upper_individual else p.upper_mean) });
    }
    try w.writeAll("\"/>");
}
pub fn fitSvg(a: A, spec: parse.Spec, d: design.Design, result: math.Result, title: ?[]const u8) diag.Error![]const u8 {
    const ci = predictor(spec) orelse return error.ExecError;
    const points = try curve(a, spec, d, result);
    var xr: svg.Range = .{};
    var yr: svg.Range = .{};
    for (d.observations, d.y) |row, y| {
        xr.add(row.cells[ci].num);
        yr.add(y);
    }
    for (points) |p| {
        yr.add(p.lower_individual);
        yr.add(p.upper_individual);
    }
    const b = svg.Bounds{ .x = xr.padded(), .y = yr.padded(), .top = 65, .bottom = 420 };
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    open(w, "Fit Plot", title) catch return error.OutOfMemory;
    band(w, b, points, true) catch return error.OutOfMemory;
    band(w, b, points, false) catch return error.OutOfMemory;
    w.writeAll("<polyline data-kind=\"fitted\" fill=\"none\" stroke=\"#245e9b\" stroke-width=\"2\" points=\"") catch return error.OutOfMemory;
    for (points) |p| w.print("{d:.3},{d:.3} ", .{ b.px(p.x), b.py(p.predicted) }) catch return error.OutOfMemory;
    w.writeAll("\"/>") catch return error.OutOfMemory;
    for (points) |p| w.print("<metadata data-x=\"{d}\" data-predicted=\"{d}\" data-lclm=\"{d}\" data-uclm=\"{d}\" data-lcli=\"{d}\" data-ucli=\"{d}\"/>", .{ p.x, p.predicted, p.lower_mean, p.upper_mean, p.lower_individual, p.upper_individual }) catch return error.OutOfMemory;
    for (d.observations, d.y) |row, y| w.print("<circle data-kind=\"observed\" data-source=\"{d}\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"3.5\" fill=\"white\" stroke=\"#245e9b\"/>", .{ row.source_number, row.cells[ci].num, y, b.px(row.cells[ci].num), b.py(y) }) catch return error.OutOfMemory;
    axes(a, w, b, spec.input.ds.columns.items[ci].name, spec.input.ds.columns.items[d.response].name, true) catch return error.OutOfMemory;
    w.print("<text x=\"88\" y=\"490\">{d:.0}% mean confidence band; {d:.0}% individual prediction band</text></svg>", .{ 100 * (1 - spec.alpha), 100 * (1 - spec.alpha) }) catch return error.OutOfMemory;
    return out.written();
}
pub fn interactionSvg(a: A, spec: parse.Spec, d: design.Design, result: math.Result, title: ?[]const u8) diag.Error![]const u8 {
    if (d.classes.len != 2 or d.classes[0].levels.len == 0 or d.classes[1].levels.len == 0) return error.ExecError;
    for (spec.effects) |effect| for (effect.variables) |ci| {
        if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) return error.ExecError;
    };
    const left = d.classes[0];
    const group = d.classes[1];
    var yr: svg.Range = .{};
    for (d.y) |y| yr.add(y);
    for (result.model.fit.fitted) |y| yr.add(y);
    const b = svg.Bounds{ .x = (svg.Range{ .lo = 0, .hi = @floatFromInt(left.levels.len - 1) }).padded(), .y = yr.padded(), .top = 65, .bottom = 420 };
    var out: W.Allocating = .init(a);
    const w = &out.writer;
    open(w, "Interaction Plot", title) catch return error.OutOfMemory;
    for (group.levels, 0..) |g, k| {
        const color = colors[k % colors.len];
        w.print("<polyline data-kind=\"group-fit\" data-group=\"{d}\" fill=\"none\" stroke=\"{s}\" stroke-width=\"2\" points=\"", .{ k, color }) catch return error.OutOfMemory;
        for (left.levels, 0..) |_, j| {
            var sum: f64 = 0;
            var count: usize = 0;
            for (d.observations, result.model.fit.fitted, 0..) |_, pred, row_index| {
                if (left.row_levels[row_index].? == j and group.row_levels[row_index].? == k) {
                    sum += pred;
                    count += 1;
                }
            }
            if (count == 0) return error.ExecError;
            w.print("{d:.3},{d:.3} ", .{ b.px(@floatFromInt(j)), b.py(sum / @as(f64, @floatFromInt(count))) }) catch return error.OutOfMemory;
        }
        w.writeAll("\"/>") catch return error.OutOfMemory;
        w.print("<text x=\"{d}\" y=\"490\" style=\"fill:{s}\">", .{ 88 + @as(usize, k) * 110, color }) catch return error.OutOfMemory;
        svg.escaped(w, g.label) catch return error.OutOfMemory;
        w.writeAll("</text>") catch return error.OutOfMemory;
    }
    for (d.observations, d.y, 0..) |row, y, i| {
        const j = left.row_levels[i].?;
        const k = group.row_levels[i].?;
        w.print("<circle data-kind=\"observed\" data-source=\"{d}\" data-group=\"{d}\" data-x=\"{d}\" data-y=\"{d}\" data-predicted=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"{d}\" fill=\"{s}\" stroke=\"{s}\"/>", .{ row.source_number, k, j, y, result.model.fit.fitted[i], b.px(@floatFromInt(j)), b.py(y), if (k % 2 == 0) @as(usize, 4) else 3, if (k % 2 == 0) @as([]const u8, "white") else colors[k % colors.len], colors[k % colors.len] }) catch return error.OutOfMemory;
    }
    axes(a, w, b, spec.input.ds.columns.items[left.column].name, spec.input.ds.columns.items[d.response].name, false) catch return error.OutOfMemory;
    for (left.levels, 0..) |item, j| {
        w.print("<text x=\"{d:.3}\" y=\"442\" text-anchor=\"middle\">", .{b.px(@floatFromInt(j))}) catch return error.OutOfMemory;
        svg.escaped(w, item.label) catch return error.OutOfMemory;
        w.writeAll("</text>") catch return error.OutOfMemory;
    }
    w.writeAll("</svg>") catch return error.OutOfMemory;
    return out.written();
}
pub fn emit(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, result: math.Result, order: usize) diag.Error!void {
    const session = cx.graphics orelse return;
    if (session.enabled != true or spec.plots_none or spec.noprint) return;
    const is_fit = predictor(spec) != null;
    if (!is_fit and d.classes.len != 2) return proc.failGap(cx.diags, 0, "PROC GLM: this default graph family requires STAT-GLM-020", .{});
    const bytes = if (is_fit) try fitSvg(cx.arena, spec, d, result, cx.graph_title) else interactionSvg(cx.arena, spec, d, result, cx.graph_title) catch return proc.failGap(cx.diags, 0, "PROC GLM: this interaction graph is not implemented", .{});
    const name: svg.graph_ods.Name = if (is_fit) .FitPlot else .IntPlot;
    try session.queue(order, if (is_fit) "glm-fit" else "glm-interaction", bytes, .{ .name = name, .label = if (is_fit) "Fit Plot" else "Interaction Plot", .template = null, .path = try std.fmt.allocPrint(cx.arena, "GLM.{s}.{s}", .{ spec.input.ds.columns.items[d.response].name, @tagName(name) }) });
}
