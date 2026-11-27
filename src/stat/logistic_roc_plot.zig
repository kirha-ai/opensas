//! Native ROC geometry with all empirical vertices and probability labels.
const std = @import("std");
const roc = @import("logistic_roc.zig");
const graphics = @import("graphics_svg.zig");
const format = @import("../format.zig");
const diag = @import("../diag.zig");
const A = std.mem.Allocator;
pub fn svg(a: A, curves: []const roc.Curve, labels: []const []const u8, probabilities: bool, overlay: bool) ![]const u8 {
    if (curves.len == 0 or curves.len != labels.len) return error.ExecError;
    const height: usize = if (overlay) 650 + 28 * curves.len else 680;
    var output: std.Io.Writer.Allocating = .init(a);
    errdefer output.deinit();
    const w = &output.writer;
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"{d}\" viewBox=\"0 0 800 {d}\" role=\"img\" data-kind=\"{s}\"><title>", .{ height, height, if (overlay) "logistic-roc-overlay" else "logistic-roc" });
    const title = if (overlay) "ROC Curves" else try std.fmt.allocPrint(a, "ROC Curve for {s}", .{labels[0]});
    try graphics.escaped(w, title);
    try w.writeAll("</title><desc>Empirical sensitivity versus one minus specificity. Diagonal indicates random classification.</desc><rect width=\"100%\" height=\"100%\" fill=\"white\"/><style>text{font:14px sans-serif;fill:#243448}.grid{stroke:#dce3ec;stroke-width:1}.curve{fill:none;stroke-width:2.3}.cutpoint{font-size:12px}</style>");
    try w.writeAll("<text x=\"400\" y=\"31\" text-anchor=\"middle\" style=\"font-size:20px;font-weight:600\">");
    try graphics.escaped(w, title);
    try w.writeAll("</text>");
    if (!overlay) try w.print("<text x=\"400\" y=\"56\" text-anchor=\"middle\">Area under the curve = {d:.4}</text>", .{curves[0].area});
    for (0..6) |i| {
        const value = @as(f64, @floatFromInt(i)) / 5;
        const x = 90 + 600 * value;
        const y = 590 - 500 * value;
        try w.print("<line class=\"grid\" x1=\"{d}\" x2=\"{d}\" y1=\"90\" y2=\"590\"/><line class=\"grid\" x1=\"90\" x2=\"690\" y1=\"{d}\" y2=\"{d}\"/><text x=\"{d}\" y=\"614\" text-anchor=\"middle\">{d:.1}</text><text x=\"76\" y=\"{d}\" text-anchor=\"end\">{d:.1}</text>", .{ x, x, y, y, x, value, y + 5, value });
    }
    try w.writeAll("<rect x=\"90\" y=\"90\" width=\"600\" height=\"500\" fill=\"none\" stroke=\"#66778b\"/><line x1=\"90\" y1=\"590\" x2=\"690\" y2=\"90\" stroke=\"#999\" stroke-dasharray=\"6 5\" data-reference=\"random\"/><text x=\"390\" y=\"642\" text-anchor=\"middle\">1 - Specificity</text><text x=\"27\" y=\"340\" text-anchor=\"middle\" transform=\"rotate(-90 27 340)\">Sensitivity</text>");
    const colors = [_][]const u8{ "#2467a6", "#bc482d", "#2b8155", "#8454a0", "#a56b12" };
    for (curves, labels, 0..) |curve, label, index| {
        const color = colors[index % colors.len];
        try w.writeAll("<g data-model=\"");
        try graphics.escaped(w, label);
        try w.print("\" data-area=\"{d}\"><polyline class=\"curve\" stroke=\"{s}\" points=\"", .{ curve.area, color });
        for (curve.points) |point| try w.print("{d},{d} ", .{ 90 + 600 * point.false_positive, 590 - 500 * point.sensitivity });
        try w.writeAll("\"/>");
        for (curve.points) |point| {
            const x = 90 + 600 * point.false_positive;
            const y = 590 - 500 * point.sensitivity;
            try w.print("<g class=\"roc-point\" data-threshold=\"{d}\" data-sensitivity=\"{d}\" data-fpr=\"{d}\" data-positive=\"{d}\" data-negative=\"{d}\" data-x=\"{d}\" data-y=\"{d}\">", .{ point.threshold, point.sensitivity, point.false_positive, point.positives, point.negatives, x, y });
            if (probabilities and point.label) {
                const text = std.mem.trim(u8, try format.apply(a, .{ .num = point.threshold }, "6.2"), " ");
                try w.print("<circle cx=\"{d}\" cy=\"{d}\" r=\"3\" fill=\"{s}\"/><text class=\"cutpoint\" x=\"{d}\" y=\"{d}\">", .{ x, y, color, x + 8, y - 7 });
                try graphics.escaped(w, text);
                try w.writeAll("</text>");
            }
            try w.writeAll("</g>");
        }
        try w.writeAll("</g>");
        if (overlay) {
            const y = 668 + 28 * index;
            try w.print("<line x1=\"140\" x2=\"180\" y1=\"{d}\" y2=\"{d}\" stroke=\"{s}\" stroke-width=\"3\"/><text x=\"193\" y=\"{d}\">", .{ y, y, color, y + 5 });
            try graphics.escaped(w, label);
            try w.print(" (AUC={d:.4})</text>", .{curve.area});
        }
    }
    if (probabilities) try w.writeAll("<text x=\"680\" y=\"578\" text-anchor=\"end\" style=\"font-size:12px\">Points labeled by predicted probability</text>");
    try w.writeAll("</svg>\n");
    return output.written();
}
