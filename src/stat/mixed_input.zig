//! MIXED input views preserve BY groups, precision weights and physical row IDs.
//! S154 p.6694 excludes nonpositive/missing weights; ID only controls OUTP/OUTPM.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const declarations = @import("mixed_parse.zig");
const selection = @import("data_selection.zig");
pub const Group = struct {
    raw: selection.View,
    selected: selection.View,
    read_count: usize,
    used_count: usize,
    excluded_count: usize,
};
/// missing_columns comes from the model contract, including its response and
/// required effect/class variables. The raw view remains available for future
/// prediction rows; precision weights never replicate observations.
pub fn prepare(cx: proc.ProcCtx, spec: declarations.Spec, missing_columns: []const usize) diag.Error![]Group {
    for (missing_columns) |ci| if (ci >= spec.input.ds.columns.items.len) return error.ExecError;
    const view = try selection.View.init(cx.arena, spec.input, spec.roles);
    const groups = try view.groups(cx.arena, spec.by_desc, spec.notsorted, cx.diags);
    const results = try cx.arena.alloc(Group, groups.len);
    for (groups, results) |group, *result| {
        const selected = try group.select(cx.arena, .{ .missing_columns = missing_columns, .weight = .positive_only });
        for (selected.observations) |row| if (!std.math.isFinite(row.weight.num)) return cx.diags.fail(error.ParseError, spec.line, "PROC MIXED: analysis weights must be finite", .{});
        result.* = .{ .raw = group, .selected = selected, .read_count = group.observations.len, .used_count = selected.observations.len, .excluded_count = group.observations.len - selected.observations.len };
    }
    return results;
}
