//! MIXED listing boundaries for real LSMean and difference records.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const ls = @import("mixed_lsmeans.zig");
const format = @import("../format.zig");
fn number(a: std.mem.Allocator, v: ?f64, spec: []const u8) ![]const u8 {
    return if (v) |value| std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ") else ".";
}
fn levels(cx: proc.ProcCtx, out: *std.ArrayList(u8), x: fixed.Design, row: ls.Mean, used: []const usize) !void {
    for (used) |ci| if (row.levels[ci]) |value| try out.print(cx.arena, " {s}", .{x.matrix.classes[ci].map.levels[value].label});
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, x: fixed.Design, result: ls.Result, requests: []const ls.Request, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    if (requests.len == 0) return;
    if (cx.capture) |capture| {
        if (capture.wants("LSMeans")) return proc.failGap(cx.diags, m.line, "PROC MIXED: LSMeans typed metadata is not independently verified", .{});
        if (result.differences.len > 0 and capture.wants("Diffs")) return proc.failGap(cx.diags, m.line, "PROC MIXED: Diffs typed metadata is not independently verified", .{});
    }
    var any_cl = false;
    for (requests) |r| any_cl = any_cl or r.cl;
    const start = out.items.len;
    try out.appendSlice(cx.arena, "\nLeast Squares Means\n\nStandard\nEffect");
    for (result.used_classes) |ci| try out.print(cx.arena, " {s}", .{m.source.columns.items[x.matrix.classes[ci].column].name});
    try out.appendSlice(cx.arena, " Estimate Error DF t Value Pr > |t|");
    if (any_cl) try out.appendSlice(cx.arena, " Alpha Lower Upper");
    try out.appendSlice(cx.arena, "\n\n");
    for (result.means) |mean| {
        try out.appendSlice(cx.arena, mean.name);
        try levels(cx, out, x, mean, result.used_classes);
        const value = mean.inference;
        if (!value.estimable) try out.appendSlice(cx.arena, " Non-est . . . .") else try out.print(cx.arena, " {s} {s} {d} {s} {s}", .{ try number(cx.arena, value.estimate, "12.4"), try number(cx.arena, value.se, "12.4"), value.df, try number(cx.arena, value.t, "12.2"), try number(cx.arena, value.p, "pvalue6.4") });
        if (any_cl) {
            const r = requests[mean.request];
            try out.print(cx.arena, " {s} {s} {s}", .{ if (r.cl) try std.fmt.allocPrint(cx.arena, "{d}", .{r.alpha}) else ".", if (r.cl) try number(cx.arena, value.lower, "12.4") else ".", if (r.cl) try number(cx.arena, value.upper, "12.4") else "." });
        }
        try out.append(cx.arena, '\n');
    }
    if (route) |routed| try routed.finish(cx.arena, out, start, "LSMeans");
    if (result.differences.len > 0) {
        const first = out.items.len;
        var adjusted = false;
        for (requests) |r| adjusted = adjusted or r.adjust != .none;
        try out.appendSlice(cx.arena, "\nDifferences of Least Squares Means\n\nStandard\nEffect");
        for (result.used_classes) |ci| try out.print(cx.arena, " {s}", .{m.source.columns.items[x.matrix.classes[ci].column].name});
        for (result.used_classes) |ci| try out.print(cx.arena, " _{s}", .{m.source.columns.items[x.matrix.classes[ci].column].name});
        try out.appendSlice(cx.arena, " Estimate Error DF t Value Pr > |t|");
        if (adjusted) try out.appendSlice(cx.arena, " Adjustment Adj P");
        if (any_cl) try out.appendSlice(cx.arena, " Alpha Lower Upper");
        try out.appendSlice(cx.arena, "\n\n");
        for (result.differences) |difference| {
            const left = result.means[difference.left];
            const right = result.means[difference.right];
            const value = difference.inference;
            const request = requests[difference.request];
            try out.appendSlice(cx.arena, left.name);
            try levels(cx, out, x, left, result.used_classes);
            try levels(cx, out, x, right, result.used_classes);
            if (!value.estimable) try out.appendSlice(cx.arena, " Non-est . . . .") else try out.print(cx.arena, " {s} {s} {d} {s} {s}", .{ try number(cx.arena, value.estimate, "12.4"), try number(cx.arena, value.se, "12.4"), value.df, try number(cx.arena, value.t, "12.2"), try number(cx.arena, value.p, "pvalue6.4") });
            if (adjusted) try out.print(cx.arena, " {s} {s}", .{ switch (request.adjust) {
                .none => "None",
                .bon => "Bonferroni",
                .sidak => "Sidak",
                .tukey => "Tukey-Kramer",
            }, try number(cx.arena, difference.adjusted_p, "pvalue6.4") });
            if (any_cl) try out.print(cx.arena, " {s} {s} {s}", .{ if (request.cl) try std.fmt.allocPrint(cx.arena, "{d}", .{request.alpha}) else ".", if (request.cl) try number(cx.arena, difference.lower, "12.4") else ".", if (request.cl) try number(cx.arena, difference.upper, "12.4") else "." });
            try out.append(cx.arena, '\n');
        }
        if (route) |routed| try routed.finish(cx.arena, out, first, "Diffs");
    }
}
