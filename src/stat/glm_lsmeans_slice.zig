//! GLM LSMEANS SLICE= consumer, S154 physical pp.4141–4143.
//! Partitioning and hypothesis construction are shared; GLM supplies its actual
//! full-model g2 covariance, residual scale/DF, and source-specific CLASS rows.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parsing = @import("glm_parse.zig");
const glm = @import("glm_lsmeans.zig");
const shared = @import("lsmeans_slice.zig");
const linear = @import("linear_hypothesis.zig");
pub const Result = struct { class_position: usize, level: usize, hypothesis: []const linear.Row, result: linear.Result };
pub fn compute(cx: proc.ProcCtx, request: glm.Request, classes: []const @import("design_matrix.zig").Class, means: []const glm.Mean, model: @import("reg_diagnostics.zig").Result) diag.Error![]const Result {
    if (request.slice_columns.len == 0) return &.{};
    if (request.error_effect != null) return proc.failGap(cx.diags, 0, "PROC GLM: combined SLICE and alternate LSMEANS error effects are not implemented", .{});
    const rows = try cx.arena.alloc(shared.Row, means.len);
    const coefficients = try cx.arena.alloc([]const f64, means.len);
    for (means, rows, coefficients) |mean, *row, *l| { row.* = .{ .levels = mean.levels, .coefficients = mean.coefficients }; l.* = mean.coefficients; }
    var results: std.ArrayList(Result) = .empty;
    for (request.slice_columns) |column| {
        const index = for (classes, 0..) |class, i| { if (class.column == column) break i; } else return error.ExecError;
        const partitions = shared.partitions(cx.arena, rows, &.{index}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, 0, "PROC GLM: unsupported SLICE CLASS partition", .{});
        for (partitions) |partition| {
            // Never discard a nonestimable individual margin before forming
            // differences: the shared kernel checks the joint L rows themselves.
            const tested = shared.testPartition(cx.arena, linear.fromRegression(model, request.singular), coefficients, partition.rows) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, 0, "PROC GLM: SLICE hypothesis is outside the implemented numerical domain", .{});
            if (tested.result.status == .inconsistent) return proc.failGap(cx.diags, 0, "PROC GLM: inconsistent SLICE hypothesis rows", .{});
            try results.append(cx.arena, .{ .class_position = index, .level = partition.levels[0], .hypothesis = tested.hypotheses, .result = tested.result });
        }
    }
    return results.items;
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parsing.Spec, response: usize, table: glm.Table) diag.Error!void {
    var previous: ?usize = null;
    for (table.slices) |slice| {
        const class = table.classes[slice.class_position];
        if (previous == null or previous.? != slice.class_position) {
            if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |title| try out.print(cx.arena, "\n{s}\n", .{title});
            try out.print(cx.arena, "\nThe GLM Procedure\nLeast Squares Means\n{s} Effect Sliced by {s} for {s}\n\nSum of\n{s} DF Squares Mean Square F Value Pr > F\n", .{ table.effect, spec.input.ds.columns.items[class.column].name, spec.input.ds.columns.items[response].name, spec.input.ds.columns.items[class.column].name });
            previous = slice.class_position;
        }
        const r = slice.result;
        const ms: ?f64 = if (r.numerator_ss != null and r.rank > 0) r.numerator_ss.? / @as(f64, @floatFromInt(r.rank)) else null;
        try out.print(cx.arena, "{s} {d} {s} {s} {s} {s}\n", .{ class.map.levels[slice.level].label, r.rank, if (r.status == .nonestimable) "Non-est" else try glm.number(cx.arena, r.numerator_ss, 6), try glm.number(cx.arena, ms, 6), try glm.number(cx.arena, r.f, 2), if (r.f_probability != null and r.f_probability.? < 0.0001) "<.0001" else try glm.number(cx.arena, r.f_probability, 4) });
    }
}
