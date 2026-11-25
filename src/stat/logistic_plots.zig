//! LOGISTIC ODDSRATIO AT estimates and native confidence-limit plots.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const design = @import("logistic_design.zig");
const fit = @import("logistic_fit.zig");
const fns = @import("../functions.zig");
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
pub const Row = struct { label: []const u8, log_estimate: f64, log_lower: f64, log_upper: f64 };
pub fn atRows(a: A, ds: *const Dataset, d: design.Design, r: fit.Fit, variable: usize, at_variable: usize, values: []const f64, alpha: f64) diag.Error![]const Row {
    if (ds.columns.items[variable].type != .num or ds.columns.items[at_variable].type != .num) return error.ExecError;
    var found = false;
    for (d.effects) |effect| if (std.mem.indexOfScalar(usize, effect.variables, variable) != null) {
        found = true;
        break;
    };
    if (!found) return error.ExecError;
    const settings = try a.alloc(f64, ds.columns.items.len);
    @memset(settings, 0);
    for (d.effects) |effect| for (effect.variables) |ci| {
        var sum: f64 = 0;
        for (d.source_rows, d.frequencies) |source, freq| sum += ds.rows.items[source][ci].num * freq;
        settings[ci] = sum / d.total_frequency;
    };
    const contrast = try a.alloc(f64, d.p);
    const rows = try a.alloc(Row, values.len);
    const z = fns.distQuantile(.normal, 1 - alpha / 2, &.{}).?;
    for (values, rows) |value, *row| {
        settings[at_variable] = value;
        @memset(contrast, 0);
        for (d.effects) |effect| {
            if (effect.class_index != null) return error.ExecError;
            var lo: f64 = 1;
            var hi: f64 = 1;
            for (effect.variables) |ci| {
                lo *= settings[ci];
                hi *= settings[ci] + @as(f64, if (ci == variable) 1 else 0);
            }
            contrast[effect.start] = hi - lo;
        }
        var estimate: f64 = 0;
        var variance: f64 = 0;
        for (0..d.p) |j| {
            estimate += contrast[j] * r.coefficients[j];
            for (0..d.p) |k| variance += contrast[j] * r.covariance[j * d.p + k] * contrast[k];
        }
        if (!std.math.isFinite(estimate) or !std.math.isFinite(variance) or variance < 0) return error.ExecError;
        const margin = z * @sqrt(variance);
        row.* = .{ .label = try std.fmt.allocPrint(a, "{s} at {s}={s}", .{ ds.columns.items[variable].name, ds.columns.items[at_variable].name, try @import("../format.zig").bestNum(a, value) }), .log_estimate = estimate, .log_lower = estimate - margin, .log_upper = estimate + margin };
    }
    return rows;
}
pub fn render(a: A, rows: []const Row, title: []const u8, by_label: []const u8) ![]const u8 {
    if (rows.len == 0) return error.ExecError;
    var low: f64 = 0;
    var high: f64 = 0;
    for (rows) |row| {
        low = @min(low, row.log_lower);
        high = @max(high, row.log_upper);
    }
    const pad = @max(0.05, (high - low) * 0.08);
    low -= pad;
    high += pad;
    const height = 150 + rows.len * 55;
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"840\" height=\"{d}\" viewBox=\"0 0 840 {d}\" role=\"img\" data-kind=\"logistic-oddsratio\"><title>", .{ height, height });
    try svg.escaped(w, title);
    try w.writeAll("</title><desc>Wald odds ratios and confidence intervals. ");
    try svg.escaped(w, by_label);
    try w.writeAll("</desc><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:14px sans-serif;fill:#243448}.ci{stroke:#2864a0;stroke-width:2}.point{fill:#2864a0}</style><text x=\"420\" y=\"28\" text-anchor=\"middle\" font-size=\"19\">");
    try svg.escaped(w, title);
    try w.writeAll("</text><text x=\"420\" y=\"51\" text-anchor=\"middle\">");
    try svg.escaped(w, by_label);
    try w.writeAll("</text>");
    const bottom: f64 = @floatFromInt(height - 60);
    const zero = 240 + (0 - low) / (high - low) * 550;
    try w.print("<line x1=\"{d}\" x2=\"{d}\" y1=\"68\" y2=\"{d}\" stroke=\"#999\" stroke-dasharray=\"4 4\" data-reference=\"1\"/>", .{ zero, zero, bottom });
    for (rows, 0..) |row, i| {
        const y: f64 = 90 + 55 * @as(f64, @floatFromInt(i));
        const x = 240 + (row.log_estimate - low) / (high - low) * 550;
        const l = 240 + (row.log_lower - low) / (high - low) * 550;
        const u = 240 + (row.log_upper - low) / (high - low) * 550;
        try w.writeAll("<g class=\"odds-row\" data-label=\"");
        try svg.escaped(w, row.label);
        try w.print("\" data-estimate=\"{d}\" data-lower=\"{d}\" data-upper=\"{d}\" data-log-estimate=\"{d}\"><text x=\"225\" y=\"{d}\" text-anchor=\"end\">", .{ @exp(row.log_estimate), @exp(row.log_lower), @exp(row.log_upper), row.log_estimate, y + 5 });
        try svg.escaped(w, row.label);
        try w.print("</text><line class=\"ci\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/><line class=\"ci\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/><line class=\"ci\" x1=\"{d}\" x2=\"{d}\" y1=\"{d}\" y2=\"{d}\"/><circle class=\"point\" cx=\"{d}\" cy=\"{d}\" r=\"4\"/></g>", .{ l, u, y, y, l, l, y - 6, y + 6, u, u, y - 6, y + 6, x, y });
    }
    try w.print("<line x1=\"240\" x2=\"790\" y1=\"{d}\" y2=\"{d}\" stroke=\"#444\"/>", .{ bottom, bottom });
    for (0..6) |i| {
        const t = @as(f64, @floatFromInt(i)) / 5;
        try w.print("<text x=\"{d}\" y=\"{d}\" text-anchor=\"middle\">{d:.3}</text>", .{ 240 + t * 550, bottom + 22, @exp(low + t * (high - low)) });
    }
    try w.print("<text x=\"515\" y=\"{d}\" text-anchor=\"middle\">Odds Ratio (log scale)</text></svg>\n", .{height - 12});
    return out.written();
}
