//! GLM-specific LS-mean comparison listing, separate from shared inference.
//! Field order follows S154 chapter53 (not the common GLM-excluding syntax).
const std = @import("std");
const proc = @import("../proc.zig");
const glm = @import("glm_lsmeans.zig");
const parsing = @import("glm_parse.zig");
const design = @import("glm_design.zig");
fn columns(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parsing.Spec, table: glm.Table) !void {
    for (table.classes, 0..) |class, c| if (table.means.len > 0 and table.means[0].levels[c] != null) try out.print(cx.arena, "{s} ", .{spec.input.ds.columns.items[class.column].name});
}
fn labels(cx: proc.ProcCtx, out: *std.ArrayList(u8), table: glm.Table, mean: glm.Mean) !void {
    for (mean.levels, table.classes) |level, class| if (level) |v| try out.print(cx.arena, "{s} ", .{class.map.levels[v].label});
}
fn probability(a: std.mem.Allocator, p: ?f64) ![]const u8 {
    return if (p != null and p.? < 0.0001) "<.0001" else glm.number(a, p, 4);
}
fn pair(table: glm.Table, i: usize, j: usize) ?f64 {
    for (table.comparisons) |comparison| if ((comparison.i == i and comparison.j == j) or (comparison.i == j and comparison.j == i)) return comparison.adjusted_p;
    return null;
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parsing.Spec, d: design.Design, request: glm.Request, table: glm.Table) !void {
    const a = cx.arena;
    const response = spec.input.ds.columns.items[d.response].name;
    const k = table.means.len;
    try out.append(a, '\n');
    if (request.pdiff) try out.appendSlice(a, if (k == 2) "H0:LSMean1=\nLSMean2\n" else "LSMEAN\n");
    try columns(cx, out, spec, table);
    try out.print(a, "{s} LSMEAN", .{response});
    if (request.pdiff) try out.appendSlice(a, if (k == 2) " Pr > |t|" else " Number");
    if (request.stderr) try out.appendSlice(a, " Standard Error Pr > |t|");
    try out.appendSlice(a, "\n\n");
    for (table.means, 0..) |mean, i| {
        try labels(cx, out, table, mean);
        try out.print(a, "{s}", .{if (mean.inference.status == .nonestimable) "Non-est" else try glm.number(a, mean.inference.estimate, 7)});
        if (request.pdiff) {
            if (k == 2) {
                if (i == 0) try out.print(a, " {s}", .{try probability(a, pair(table, 0, 1))});
            } else try out.print(a, " {d}", .{i + 1});
        }
        if (request.stderr) try out.print(a, " {s} {s}", .{ try glm.number(a, mean.inference.standard_error, 7), try probability(a, mean.inference.p_value) });
        try out.append(a, '\n');
    }
    if (request.pdiff and k > 2) {
        try out.print(a, "\nLeast Squares Means for effect {s}\nPr > |t| for H0: LSMean(i)=LSMean(j)\nDependent Variable: {s}\n\ni/j", .{ table.effect, response });
        for (0..k) |j| try out.print(a, " {d}", .{j + 1});
        try out.append(a, '\n');
        for (0..k) |i| {
            try out.print(a, "{d}", .{i + 1});
            for (0..k) |j| if (i != j) {
                try out.print(a, " {s}", .{try probability(a, pair(table, i, j))});
            };
            try out.append(a, '\n');
        }
    }
    if (request.cl) {
        const percent = 100 * (1 - request.alpha);
        try out.append(a, '\n');
        try columns(cx, out, spec, table);
        try out.print(a, "{s} LSMEAN {d}% Confidence Limits\n\n", .{ response, percent });
        for (table.means, table.mean_limits) |mean, limit| {
            try labels(cx, out, table, mean);
            try out.print(a, "{s} {s} {s}\n", .{ if (mean.inference.status == .nonestimable) "Non-est" else try glm.number(a, mean.inference.estimate, 6), try glm.number(a, limit.lower, 6), try glm.number(a, limit.upper, 6) });
        }
        if (request.pdiff) {
            try out.print(a, "\nLeast Squares Means for Effect {s}\n\nDifference {s}{d}%\nBetween Confidence Limits for\ni j Means LSMean(i)-LSMean(j)\n\n", .{ table.effect, if (request.adjust != .none) @as([]const u8, "Simultaneous ") else "", percent });
            for (table.comparisons) |comparison| try out.print(a, "{d} {d} {s} {s} {s}\n", .{ comparison.i + 1, comparison.j + 1, if (comparison.inference.status == .nonestimable) "Non-est" else try glm.number(a, comparison.inference.estimate, 6), try glm.number(a, comparison.limits.lower, 6), try glm.number(a, comparison.limits.upper, 6) });
        }
    }
}
