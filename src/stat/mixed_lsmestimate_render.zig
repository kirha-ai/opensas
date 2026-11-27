//! LSMESTIMATE listing from computed K*L1 estimates; no numerical values are
//! taken from listing text. ODS descriptors/capture beyond names remain gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const module = @import("mixed_lsmestimate.zig");
const fmt = @import("../format.zig");
fn n(a: std.mem.Allocator, x: ?f64, spec: []const u8) ![]const u8 {
    return if (x) |v| std.mem.trim(u8, try fmt.apply(a, .{ .num = v }, spec), " ") else ".";
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), results: []const module.Result, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    if (results.len == 0) return;
    var count: usize = 0;
    var cl = false;
    var adjusted = false;
    var one_sided = false;
    for (results) |result| {
        if (!result.request.joint_only) count += result.rows.len;
        cl = cl or result.request.cl;
        adjusted = adjusted or result.request.adjust != .none;
        one_sided = one_sided or result.request.tail != .two;
    }
    if (cx.capture) |capture| {
        if (count > 0 and capture.wants("LSMEstimates")) return proc.failGap(cx.diags, 0, "PROC MIXED: LSMEstimates typed metadata is not independently verified", .{});
        for (results) |result| if (result.joint != null and capture.wants("Contrasts")) return proc.failGap(cx.diags, 0, "PROC MIXED: joint LSMESTIMATE typed metadata is not independently verified", .{});
    }
    if (count > 0 and one_sided) for (results) |result| if (result.request.tail != results[0].request.tail) return proc.failGap(cx.diags, 0, "PROC MIXED: mixed-tail LSMESTIMATE table styles are not implemented", .{});
    if (count > 0) {
        const start = out.items.len;
        try out.print(cx.arena, "\nLeast Squares Means Estimate{s}\n", .{if (count == 1) @as([]const u8, "") else "s"});
        if (adjusted) {
            const method = results[0].request.adjust;
            for (results) |result| if (result.request.adjust != method) return proc.failGap(cx.diags, 0, "PROC MIXED: mixed LSMESTIMATE adjustment table styles are not implemented", .{});
            try out.print(cx.arena, "Adjustment for Multiplicity: {s}\n", .{switch (method) {
                .none => "None",
                .bon => "Bonferroni",
                .sidak => "Sidak",
            }});
        }
        try out.appendSlice(cx.arena, "\nStandard\nEffect Label Estimate Error DF t Value");
        if (one_sided) try out.appendSlice(cx.arena, if (results[0].request.tail == .lower) " Tails Pr < t" else " Tails Pr > t") else try out.appendSlice(cx.arena, " Pr > |t|");
        if (adjusted) try out.appendSlice(cx.arena, " Adj P");
        if (cl) try out.appendSlice(cx.arena, " Alpha Lower Upper");
        if (cl and adjusted) try out.appendSlice(cx.arena, " Adj Lower Adj Upper");
        try out.appendSlice(cx.arena, "\n\n");
        for (results) |result| if (!result.request.joint_only) for (result.rows) |row| {
            const value = row.inference;
            try out.print(cx.arena, "{s} {s}", .{ result.request.name, row.label });
            if (!value.estimable) try out.appendSlice(cx.arena, " Non-est . . .") else try out.print(cx.arena, " {s} {s} {d} {s}", .{ try n(cx.arena, value.estimate, "12.4"), try n(cx.arena, value.se, "12.4"), value.df, try n(cx.arena, value.t, "12.2") });
            if (one_sided) try out.print(cx.arena, " {s}", .{switch (result.request.tail) {
                .two => "Two",
                .lower => "Lower",
                .upper => "Upper",
            }});
            try out.print(cx.arena, " {s}", .{try n(cx.arena, value.p, "pvalue6.4")});
            if (adjusted) try out.print(cx.arena, " {s}", .{try n(cx.arena, row.adjusted_p, "pvalue6.4")});
            if (cl) {
                if (result.request.cl) try out.print(cx.arena, " {d} {s} {s}", .{ result.request.alpha, if (value.estimable and result.request.tail == .lower) @as([]const u8, "-Infty") else try n(cx.arena, value.lower, "12.4"), if (value.estimable and result.request.tail == .upper) @as([]const u8, "Infty") else try n(cx.arena, value.upper, "12.4") }) else try out.appendSlice(cx.arena, " . . .");
            }
            if (cl and adjusted) try out.print(cx.arena, " {s} {s}", .{ if (value.estimable and result.request.tail == .lower) @as([]const u8, "-Infty") else try n(cx.arena, row.adjusted_lower, "12.4"), if (value.estimable and result.request.tail == .upper) @as([]const u8, "Infty") else try n(cx.arena, row.adjusted_upper, "12.4") });
            try out.append(cx.arena, '\n');
        };
        if (route) |routed| try routed.finish(cx.arena, out, start, "LSMEstimates");
    }
    var joint_count: usize = 0;
    for (results) |result| if (result.joint != null) {
        joint_count += 1;
    };
    if (joint_count > 0) {
        const start = out.items.len;
        try out.appendSlice(cx.arena, "\nContrasts\n\nNum Den\nLabel DF DF F Value Pr > F\n");
        for (results) |result| if (result.joint) |joint| {
            const label = result.request.joint_label orelse blk: {
                for (result.request.rows) |row| if (row.explicit_label) break :blk row.label;
                break :blk result.request.name;
            };
            if (joint.estimable) try out.print(cx.arena, "{s} {d} {d} {s} {s}\n", .{ label, joint.num_df, joint.den_df, try n(cx.arena, joint.f, "12.2"), try n(cx.arena, joint.p, "pvalue6.4") }) else try out.print(cx.arena, "{s} . . . .\n", .{label});
        };
        if (route) |routed| try routed.finish(cx.arena, out, start, "Contrasts");
    }
}
