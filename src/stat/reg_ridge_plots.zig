//! REG ridge paths and ordinary-fit diagnostics, rendered by the native SVG queue.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parse = @import("reg_parse.zig");
const ridge = @import("reg_ridge.zig");
const Fit = @import("reg_fit.zig").Fit;
const fns = @import("../functions.zig");
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
const colors = [_][]const u8{ "#3155a6", "#bd493c", "#247e68", "#8155a4", "#a67820", "#3a809c", "#cc6a89", "#657b35", "#6d657e", "#82583d" };
const Series = struct { name: []const u8, x: []const f64, y: []const f64, line: bool = false, bars: bool = false, edges: []const f64 = &.{} };
const Panel = struct { title: []const u8, xlabel: []const u8, ylabel: []const u8, series: []const Series = &.{}, logx: bool = false, logy: bool = false, text: []const []const u8 = &.{}, padx: bool = true, nonnegative: bool = false };
fn xml(a: A, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        '&' => try out.appendSlice(a, "&amp;"),
        '<' => try out.appendSlice(a, "&lt;"),
        '>' => try out.appendSlice(a, "&gt;"),
        '"' => try out.appendSlice(a, "&quot;"),
        else => try out.append(a, c),
    };
    return out.items;
}
fn transformed(value: f64, log: bool) f64 {
    return if (log) @log10(value) else value;
}
fn render(a: A, title: []const u8, panels: []const Panel, columns: usize, metadata: []const u8) ![]const u8 {
    const pw: f64 = if (columns == 1) 940 else 380;
    const ph: f64 = if (columns == 1) 320 else 285;
    const rows = (panels.len + columns - 1) / columns;
    const width = pw * @as(f64, @floatFromInt(columns));
    const height = 75 + ph * @as(f64, @floatFromInt(rows));
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{d}\" height=\"{d}\" viewBox=\"0 0 {d} {d}\"><title>{s}</title><metadata>{s}</metadata><rect width=\"100%\" height=\"100%\" fill=\"white\"/><g font-family=\"Arial,sans-serif\" fill=\"#22324a\"><text x=\"{d}\" y=\"30\" text-anchor=\"middle\" font-size=\"20\" font-weight=\"bold\">{s}</text>", .{ width, height, width, height, try xml(a, title), try xml(a, metadata), width / 2, try xml(a, title) });
    for (panels, 0..) |panel, index| {
        const ox = pw * @as(f64, @floatFromInt(index % columns));
        const oy = 55 + ph * @as(f64, @floatFromInt(index / columns));
        const left = ox + 90;
        const right = ox + pw - 24;
        const top = oy + 30;
        const bottom = oy + ph - 68;
        try out.print(a, "<g data-panel=\"{s}\"><text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\" font-size=\"14\" font-weight=\"bold\">{s}</text>", .{ try xml(a, panel.title), (left + right) / 2, oy + 15, try xml(a, panel.title) });
        if (panel.text.len > 0) {
            for (panel.text, 0..) |line, i| try out.print(a, "<text x=\"{d}\" y=\"{d}\" font-size=\"13\">{s}</text>", .{ left, top + 25 * @as(f64, @floatFromInt(i + 1)), try xml(a, line) });
            try out.appendSlice(a, "</g>");
            continue;
        }
        var xmin = std.math.inf(f64);
        var xmax = -std.math.inf(f64);
        var ymin = std.math.inf(f64);
        var ymax = -std.math.inf(f64);
        for (panel.series) |series| for (series.x, series.y) |x, y| {
            if (!std.math.isFinite(x) or !std.math.isFinite(y) or (panel.logx and x <= 0) or (panel.logy and y <= 0)) continue;
            xmin = @min(xmin, transformed(x, panel.logx));
            xmax = @max(xmax, transformed(x, panel.logx));
            ymin = @min(ymin, transformed(y, panel.logy));
            ymax = @max(ymax, transformed(y, panel.logy));
        };
        if (!std.math.isFinite(xmin) or !std.math.isFinite(ymin)) return error.ExecError;
        for (panel.series) |series| if (series.bars) {
            ymin = @min(0, ymin);
            if (series.edges.len != series.x.len + 1) return error.ExecError;
            xmin = @min(xmin, series.edges[0]);
            xmax = @max(xmax, series.edges[series.edges.len - 1]);
        };
        if (panel.logy) {
            ymin = @floor(ymin);
            ymax = @ceil(ymax);
        } else {
            const margin = if (ymax > ymin) (ymax - ymin) * 0.07 else @max(1, @abs(ymax) * 0.1);
            ymin -= margin;
            ymax += margin;
        }
        if (xmax == xmin) {
            xmin -= 0.5;
            xmax += 0.5;
        }
        if (ymax == ymin) ymax = ymin + 1;
        if (panel.nonnegative and !panel.logy) ymin = 0;
        if (!panel.logy and ymax > ymin) {
            const rough = (ymax - ymin) / 4;
            const power = std.math.pow(f64, 10, @floor(@log10(rough)));
            const ratio = rough / power;
            const multiplier: f64 = if (ratio <= 1) 1 else if (ratio <= 2) 2 else if (ratio <= 2.5) 2.5 else if (ratio <= 5) 5 else 10;
            const step = power * multiplier;
            ymin = @floor(ymin / step) * step;
            ymax = @ceil(ymax / step) * step;
        }
        if (!panel.logx and panel.padx) {
            const m = (xmax - xmin) * 0.02;
            xmin -= m;
            xmax += m;
        }
        if (!std.math.isFinite(xmax - xmin) or !std.math.isFinite(ymax - ymin)) return error.ExecError;
        try out.print(a, "<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"#fbfcfe\" stroke=\"#aeb9c6\"/>", .{ left, top, right - left, bottom - top });
        for (0..5) |tick| {
            const f = @as(f64, @floatFromInt(tick)) / 4;
            const tx = xmin + f * (xmax - xmin);
            const ty = ymin + f * (ymax - ymin);
            const px = left + f * (right - left);
            const py = bottom - f * (bottom - top);
            try out.print(a, "<path d=\"M {d} {d} V {d} M {d} {d} H {d}\" fill=\"none\" stroke=\"#e1e6ed\"/><text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\" font-size=\"10\">{s}</text><text x=\"{d}\" y=\"{d}\" text-anchor=\"end\" font-size=\"10\">{s}</text>", .{ px, top, bottom, left, py, right, px, bottom + 16, try svg.label(a, if (panel.logx) std.math.pow(f64, 10, tx) else tx), left - 7, py + 4, try svg.label(a, if (panel.logy) std.math.pow(f64, 10, ty) else ty) });
        }
        try out.print(a, "<text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\" font-size=\"12\">{s}</text><text transform=\"translate({d},{d}) rotate(-90)\" text-anchor=\"middle\" font-size=\"12\">{s}</text>", .{ (left + right) / 2, bottom + 35, try xml(a, panel.xlabel), ox + 17, (top + bottom) / 2, try xml(a, panel.ylabel) });
        for (panel.series, 0..) |series, si| {
            const color = colors[si % colors.len];
            if (series.line) try out.print(a, "<polyline data-series=\"{s}\" fill=\"none\" stroke=\"{s}\" stroke-width=\"1.8\" points=\"", .{ try xml(a, series.name), color });
            for (series.x, series.y, 0..) |x, y, bin| {
                if (!std.math.isFinite(x) or !std.math.isFinite(y) or (panel.logx and x <= 0) or (panel.logy and y <= 0)) continue;
                const px = left + (transformed(x, panel.logx) - xmin) / (xmax - xmin) * (right - left);
                const py = bottom - (transformed(y, panel.logy) - ymin) / (ymax - ymin) * (bottom - top);
                if (series.line) try out.print(a, "{d:.3},{d:.3} ", .{ px, py }) else if (series.bars) {
                    const bar_left = left + (series.edges[bin] - xmin) / (xmax - xmin) * (right - left);
                    const width_bar = (series.edges[bin + 1] - series.edges[bin]) / (xmax - xmin) * (right - left);
                    const zero = bottom - (0 - ymin) / (ymax - ymin) * (bottom - top);
                    try out.print(a, "<rect data-x=\"{d}\" data-y=\"{d}\" x=\"{d:.3}\" y=\"{d:.3}\" width=\"{d:.3}\" height=\"{d:.3}\" fill=\"{s}\" fill-opacity=\".65\"/>", .{ x, y, bar_left, @min(py, zero), width_bar, @abs(zero - py), color });
                } else try out.print(a, "<circle data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"2.8\" fill=\"{s}\" fill-opacity=\".8\"/>", .{ x, y, px, py, color });
            }
            if (series.line) try out.appendSlice(a, "\"/>");
            if (panel.series.len > 1) {
                const lx = left + @as(f64, @floatFromInt(si)) * (right - left) / @as(f64, @floatFromInt(panel.series.len));
                try out.print(a, "<path d=\"M {d} {d} h 18\" stroke=\"{s}\" stroke-width=\"2\"/><text x=\"{d}\" y=\"{d}\" font-size=\"11\">{s}</text>", .{ lx, bottom + 52, color, lx + 22, bottom + 56, try xml(a, series.name) });
            }
        }
        try out.appendSlice(a, "</g>");
    }
    try out.appendSlice(a, "</g></svg>");
    return out.items;
}
fn queue(cx: proc.ProcCtx, spec: parse.Spec, model: parse.Model, name: svg.graph_ods.Name, kind: []const u8, order: usize, panels: []const Panel, columns: usize, metadata: []const u8) diag.Error!void {
    const session = cx.graphics orelse return proc.failGap(cx.diags, 0, "PROC REG: graphics consumer unavailable", .{});
    const heading: []const u8 = switch (name) {
        .RidgePanel => "Ridge Regression Analysis",
        .VIFPlot => "Variance Inflation Factors",
        .RidgePlot => "Ridge Traces",
        .DiagnosticsPanel => "Fit Diagnostics",
        .ResidualPlot => "Residual Plots",
        else => @tagName(name),
    };
    const title = try std.fmt.allocPrint(cx.arena, "{s} for {s}", .{ heading, spec.ds.columns.items[model.dependent].name });
    const bytes = render(cx.arena, title, panels, columns, metadata) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else cx.diags.fail(error.ExecError, 0, "PROC REG: undefined graph coordinates", .{});
    try session.queue(order, kind, bytes, .{ .name = name, .label = title, .template = null, .path = try std.fmt.allocPrint(cx.arena, "Reg.{s}.{s}.{s}", .{ model.label, spec.ds.columns.items[model.dependent].name, @tagName(name) }) });
}
pub fn execute(cx: proc.ProcCtx, spec: parse.Spec, model: parse.Model, path: ridge.Path, x: []const f64, y: []const f64, fit: Fit) diag.Error!void {
    if (spec.noprint or spec.ridge_plots.disabled) return;
    const g = cx.graphics orelse return;
    if (g.enabled == false) return;
    if (spec.by.len > 0) return proc.failGap(cx.diags, 0, "PROC REG: ridge graphs with BY groups are not implemented", .{});
    const a = cx.arena;
    const p = model.regressors.len;
    const n = y.len;
    if (!spec.ridge_plots.only and (p == 1 or spec.weight != null or spec.freq != null)) return proc.failGap(cx.diags, 0, "PROC REG: these default diagnostics are not implemented; request PLOTS(ONLY)=RIDGE", .{});
    if (p > 10) return proc.failGap(cx.diags, 0, "PROC REG: ridge graphs with more than ten predictors are not implemented", .{});
    const ks = try a.alloc(f64, path.points.len);
    const vs = try a.alloc(Series, p);
    const bs = try a.alloc(Series, p);
    for (path.points, ks) |point, *k| k.* = point.k;
    for (model.regressors, 0..) |ci, j| {
        const v = try a.alloc(f64, ks.len);
        const b = try a.alloc(f64, ks.len);
        for (path.points, 0..) |point, i| {
            v[i] = point.vif[j];
            b[i] = point.standardized[j];
        }
        vs[j] = .{ .name = spec.ds.columns.items[ci].name, .x = ks, .y = v, .line = true };
        bs[j] = .{ .name = spec.ds.columns.items[ci].name, .x = ks, .y = b, .line = true };
    }
    const vp = Panel{ .title = "Variance Inflation Factors", .xlabel = "Ridge Parameter", .ylabel = if (spec.ridge_plots.vif_log) "VIF (log scale)" else "VIF", .series = vs, .logx = spec.ridge_plots.ridge_log, .logy = spec.ridge_plots.vif_log, .padx = false, .nonnegative = true };
    const bp = Panel{ .title = "Ridge Traces", .xlabel = "Ridge Parameter", .ylabel = "Standardized Coefficient", .series = bs, .logx = spec.ridge_plots.ridge_log, .padx = false };
    const metadata = try std.json.Stringify.valueAlloc(a, .{ .procedure = "REG", .kind = "ridge", .predictors = blk: {
        const names = try a.alloc([]const u8, p);
        for (model.regressors, 0..) |ci, j| names[j] = spec.ds.columns.items[ci].name;
        break :blk names;
    }, .points = path.points, .vif_log = spec.ridge_plots.vif_log, .ridge_log = spec.ridge_plots.ridge_log }, .{});
    if (spec.ridge_plots.unpack) {
        try queue(cx, spec, model, .VIFPlot, "vif", 20, &.{vp}, 1, metadata);
        try queue(cx, spec, model, .RidgePlot, "ridge", 21, &.{bp}, 1, metadata);
    } else try queue(cx, spec, model, .RidgePanel, "ridge-panel", 20, &.{ vp, bp }, 1, metadata);
    if (spec.ridge_plots.only) return;
    if (fit.df_error < 2 or !(fit.mse > 0)) return proc.failGap(cx.diags, 0, "PROC REG: default diagnostics need positive variance and at least two residual DF", .{});
    const student = try a.alloc(f64, n);
    const cooks = try a.alloc(f64, n);
    const obs = try a.alloc(f64, n);
    for (fit.residuals, fit.leverage, 0..) |r, h, i| {
        const deleted = (fit.sse - r * r / (1 - h)) / @as(f64, @floatFromInt(fit.df_error - 1));
        if (!(h < 1) or !(deleted > 0)) return proc.failGap(cx.diags, 0, "PROC REG: undefined studentized diagnostic", .{});
        student[i] = r / @sqrt(deleted * (1 - h));
        cooks[i] = (r * r / (fit.mse * @as(f64, @floatFromInt(fit.rank)))) * h / ((1 - h) * (1 - h));
        obs[i] = @floatFromInt(i + 1);
    }
    const sorted = try a.dupe(f64, fit.residuals);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const quantiles = try a.alloc(f64, n);
    const ranks = try a.alloc(f64, n);
    const fit_ranks = try a.alloc(f64, n);
    const centered = try a.alloc(f64, n);
    for (0..n) |i| {
        quantiles[i] = fns.distQuantile(.normal, (@as(f64, @floatFromInt(i)) + 0.625) / (@as(f64, @floatFromInt(n)) + 0.25), &.{}).?;
        ranks[i] = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        fit_ranks[i] = 2 + ranks[i];
        centered[i] = fit.fitted[i] - fit.y_mean;
    }
    std.mem.sort(f64, centered, {}, std.sort.asc(f64));
    const edges = try @import("univ_histogram_bins.zig").automatic(a, cx.diags, sorted, false, false);
    const hx = try a.alloc(f64, edges.len - 1);
    const hy = try a.alloc(f64, edges.len - 1);
    @memset(hy, 0);
    for (hx, 0..) |*mid, i| mid.* = (edges[i] + edges[i + 1]) / 2;
    for (sorted) |v| {
        for (hy, 0..) |*count, i| {
            if (v >= edges[i] and (v < edges[i + 1] or (i + 1 == hy.len and v <= edges[i + 1]))) {
                count.* += 100 / @as(f64, @floatFromInt(n));
                break;
            }
        }
    }
    const stats = fit.modelStats(true);
    const text = try a.alloc([]const u8, 6);
    text[0] = try std.fmt.allocPrint(a, "Observations: {d}", .{fit.n_used});
    text[1] = try std.fmt.allocPrint(a, "Parameters: {d}", .{fit.rank});
    text[2] = try std.fmt.allocPrint(a, "Error DF: {d}", .{fit.df_error});
    text[3] = try std.fmt.allocPrint(a, "Root MSE: {d:.5}", .{@sqrt(fit.mse)});
    text[4] = try std.fmt.allocPrint(a, "R-Square: {d:.4}", .{stats.r_square});
    text[5] = try std.fmt.allocPrint(a, "Adj R-Sq: {d:.4}", .{stats.adj_r_square});
    const panels = [_]Panel{
        .{ .title = "Residual by Predicted", .xlabel = "Predicted", .ylabel = "Residual", .series = &.{.{ .name = "Residual", .x = fit.fitted, .y = fit.residuals }} },
        .{ .title = "RStudent by Predicted", .xlabel = "Predicted", .ylabel = "RStudent", .series = &.{.{ .name = "RStudent", .x = fit.fitted, .y = student }} },
        .{ .title = "RStudent by Leverage", .xlabel = "Leverage", .ylabel = "RStudent", .series = &.{.{ .name = "RStudent", .x = fit.leverage, .y = student }} },
        .{ .title = "Normal Q-Q", .xlabel = "Normal Quantile", .ylabel = "Residual", .series = &.{.{ .name = "Residual", .x = quantiles, .y = sorted }} },
        .{ .title = "Observed by Predicted", .xlabel = "Predicted", .ylabel = "Observed", .series = &.{.{ .name = "Observed", .x = fit.fitted, .y = y }} },
        .{ .title = "Cook's D", .xlabel = "Observation", .ylabel = "Cook's D", .series = &.{.{ .name = "Cook's D", .x = obs, .y = cooks }} },
        .{ .title = "Residual Histogram", .xlabel = "Residual", .ylabel = "Percent", .series = &.{.{ .name = "Percent", .x = hx, .y = hy, .bars = true, .edges = edges }}, .nonnegative = true, .padx = false },
        .{ .title = "Residual-Fit Spread", .xlabel = "Residual (left) / Fit (right)", .ylabel = "Centered value", .series = &.{ .{ .name = "Residual", .x = ranks, .y = sorted, .line = true }, .{ .name = "Fit", .x = fit_ranks, .y = centered, .line = true } } },
        .{ .title = "Fit Statistics", .xlabel = "", .ylabel = "", .text = text },
    };
    const diagnostic_meta = try std.json.Stringify.valueAlloc(a, .{ .procedure = "REG", .kind = "diagnostics", .fitted = fit.fitted, .residuals = fit.residuals, .leverage = fit.leverage, .rstudent = student, .cooks_d = cooks, .histogram_endpoints = edges }, .{});
    try queue(cx, spec, model, .DiagnosticsPanel, "diagnostics", 0, &panels, 3, diagnostic_meta);
    const residual_panels = try a.alloc(Panel, p);
    for (model.regressors, 0..) |ci, j| {
        const xx = try a.alloc(f64, n);
        for (0..n) |i| xx[i] = x[i * p + j];
        const series = try a.alloc(Series, 1);
        series[0] = .{ .name = "Residual", .x = xx, .y = fit.residuals };
        residual_panels[j] = .{ .title = spec.ds.columns.items[ci].name, .xlabel = spec.ds.columns.items[ci].name, .ylabel = "Residual", .series = series };
    }
    try queue(cx, spec, model, .ResidualPlot, "residuals", 1, residual_panels, if (p > 1) 2 else 1, diagnostic_meta);
}

fn attribute(element: []const u8, key: []const u8) !f64 {
    const begin = (std.mem.indexOf(u8, element, key) orelse return error.TestUnexpectedResult) + key.len;
    const end = std.mem.indexOfScalarPos(u8, element, begin, '"') orelse return error.TestUnexpectedResult;
    return std.fmt.parseFloat(f64, element[begin..end]);
}

test "REG005 diagnostic histogram bins stay inside plot with exact edge widths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try render(arena.allocator(), "Histogram", &.{.{ .title = "Percent", .xlabel = "Residual", .ylabel = "Percent", .series = &.{.{ .name = "Percent", .x = &.{ 0.5, 2 }, .y = &.{ 25, 75 }, .bars = true, .edges = &.{ 0, 1, 3 } }}, .nonnegative = true, .padx = false }}, 1, "{}");
    // One-column panel bounds are x=[90,916], y=[85,307]. Bins have
    // widths 1 and 2 in data space, so they must tile the entire plot 1:2.
    var cursor: usize = 0;
    var previous_right: f64 = 90;
    for ([_]f64{ 1, 2 }) |width| {
        const begin = std.mem.indexOfPos(u8, result, cursor, "<rect data-x=") orelse return error.TestUnexpectedResult;
        const end = std.mem.indexOfScalarPos(u8, result, begin, '>') orelse return error.TestUnexpectedResult;
        const bar = result[begin..end];
        const x = try attribute(bar, " x=\"");
        const y = try attribute(bar, " y=\"");
        const w = try attribute(bar, " width=\"");
        const h = try attribute(bar, " height=\"");
        try std.testing.expectApproxEqAbs(previous_right, x, 0.001);
        try std.testing.expectApproxEqAbs(826 * width / 3, w, 0.001);
        try std.testing.expect(y >= 85);
        try std.testing.expectApproxEqAbs(@as(f64, 307), y + h, 0.001);
        previous_right = x + w;
        cursor = end;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 916), previous_right, 0.001);
    try std.testing.expect(std.mem.indexOfPos(u8, result, cursor, "<rect data-x=") == null);
}
