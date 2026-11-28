//! GLM row selection and full-rank contrast designs for hierarchical effects.
//! CLASS levels use formatted values; sum-to-zero contrasts permit Type III
//! tests by deleting an effect block in complete hierarchical factorial models.
//! This is not GLM's singular parameter-estimate presentation; CLASS SOLUTION,
//! empty-cell estimability and nonhierarchical categorical models stay loud.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const selection = @import("data_selection.zig");
const parse = @import("glm_parse.zig");
const levelizer = @import("class_levels.zig");
const A = std.mem.Allocator;
pub const Level = levelizer.Level;
pub const Class = struct { column: usize, levels: []const Level, row_levels: []const ?usize };
pub const Effect = struct { start: usize, len: usize };
pub const Design = struct {
    x: []const f64,
    y: []const f64,
    weights: []const f64,
    frequencies: []const f64,
    source_rows: []const usize,
    observations: []const selection.Observation,
    /// Original analysis/BY slice, before response-complete-case selection.
    input_observations: []const selection.Observation = &.{},
    classes: []const Class,
    effects: []const Effect,
    n: usize,
    p: usize,
    read: usize,
    response: usize,
};

fn appendUnique(a: A, list: *std.ArrayList(usize), column: usize) !void {
    if (std.mem.indexOfScalar(usize, list.items, column) == null) try list.append(a, column);
}
fn classIndex(spec: parse.Spec, column: usize) ?usize {
    return std.mem.indexOfScalar(usize, spec.classes, column);
}
fn mainEffect(spec: parse.Spec, column: usize) bool {
    for (spec.effects) |effect| if (effect.variables.len == 1 and effect.variables[0] == column) return true;
    return false;
}

pub fn build(cx: proc.ProcCtx, spec: parse.Spec, group: selection.View, response: usize) diag.Error!Design {
    const a = cx.arena;
    var required: std.ArrayList(usize) = .empty;
    try appendUnique(a, &required, response);
    for (spec.absorb) |ci| try appendUnique(a, &required, ci);
    if (spec.manova) for (spec.responses) |ci| try appendUnique(a, &required, ci);
    for (spec.effects) |effect| {
        var categorical = false;
        for (effect.variables) |ci| {
            try appendUnique(a, &required, ci);
            if (classIndex(spec, ci) != null) categorical = true;
        }
        if (categorical and !spec.intercept) return proc.failGap(cx.diags, 0, "PROC GLM: categorical NOINT parameterization is not implemented", .{});
        if (categorical and effect.variables.len > 1) {
            for (effect.variables) |ci| if (classIndex(spec, ci) == null) return proc.failGap(cx.diags, 0, "PROC GLM: mixed CLASS/continuous interaction hypotheses are not implemented", .{});
            if (effect.variables.len != 2 or effect.variables[0] == effect.variables[1]) return proc.failGap(cx.diags, 0, "PROC GLM: higher-order or repeated CLASS interactions are not implemented", .{});
            for (effect.variables) |ci| if (!mainEffect(spec, ci)) return proc.failGap(cx.diags, 0, "PROC GLM: nonhierarchical categorical effect tests are not implemented", .{});
        }
    }
    for (group.observations) |row| {
        for (required.items) |ci| if (row.cells[ci] == .num and !row.cells[ci].isMissing() and !std.math.isFinite(row.cells[ci].num)) return cx.diags.fail(error.ExecError, 0, "PROC GLM: nonfinite analysis value at observation {d}", .{row.source_number});
        for ([_]Value{ row.frequency, row.weight }) |v| if (!v.isMissing() and !std.math.isFinite(v.num)) return cx.diags.fail(error.ExecError, 0, "PROC GLM: nonfinite FREQ or WEIGHT at observation {d}", .{row.source_number});
    }
    const usable = try group.select(a, .{ .missing_columns = required.items, .frequency = .truncate_positive, .weight = .positive_only });
    const n = usable.observations.len;
    const infos = try a.alloc(Class, spec.classes.len);
    const rows = try a.alloc([]const Value, n);
    const counts = try a.alloc(f64, n);
    for (usable.observations, 0..) |row, i| {
        rows[i] = row.cells;
        counts[i] = row.frequency.num;
    }
    for (spec.classes, 0..) |ci, k| {
        // Child storage is backed by the procedure arena and remains live for
        // the design/renderer lifetime. The shared helper owns CLASS identity.
        const formed = try levelizer.build(a, spec.input.ds, rows, ci, .{ .order = spec.order, .frequencies = counts, .missing = .exclude });
        infos[k] = .{ .column = ci, .levels = formed.levels, .row_levels = formed.row_to_level };
    }
    const effects = try a.alloc(Effect, spec.effects.len);
    var p: usize = if (spec.intercept) 1 else 0;
    for (spec.effects, 0..) |effect, j| {
        var len: usize = 1;
        for (effect.variables) |ci| if (classIndex(spec, ci)) |k| {
            len = std.math.mul(usize, len, infos[k].levels.len -| 1) catch return cx.diags.fail(error.ExecError, 0, "PROC GLM: design dimensions overflow", .{});
        };
        effects[j] = .{ .start = p, .len = len };
        p = std.math.add(usize, p, len) catch return error.OutOfMemory;
    }
    const np = std.math.mul(usize, n, p) catch return error.OutOfMemory;
    const x = try a.alloc(f64, np);
    const y = try a.alloc(f64, n);
    const weights = try a.alloc(f64, n);
    const frequencies = try a.alloc(f64, n);
    const source_rows = try a.alloc(usize, n);
    for (usable.observations, 0..) |row, i| {
        y[i] = row.cells[response].num;
        weights[i] = row.weight.num;
        frequencies[i] = row.frequency.num;
        source_rows[i] = row.source_number;
        if (spec.intercept) x[i * p] = 1;
        for (spec.effects, effects) |effect, block| {
            for (0..block.len) |j| {
                var product: f64 = 1;
                var radix = j;
                for (effect.variables) |ci| {
                    if (classIndex(spec, ci)) |k| {
                        const levels = infos[k].levels;
                        const term = radix % (levels.len - 1);
                        radix /= levels.len - 1;
                        const found = infos[k].row_levels[i] orelse return error.ExecError;
                        product *= if (found == levels.len - 1) @as(f64, -1) else if (found == term) 1 else 0;
                    } else product *= row.cells[ci].num;
                }
                if (!std.math.isFinite(product)) return cx.diags.fail(error.ExecError, 0, "PROC GLM: design product overflow at observation {d}", .{row.source_number});
                x[i * p + block.start + j] = product;
            }
        }
    }
    return .{ .x = x, .y = y, .weights = weights, .frequencies = frequencies, .source_rows = source_rows, .observations = usable.observations, .input_observations = group.observations, .classes = infos, .effects = effects, .n = n, .p = p, .read = group.observations.len, .response = response };
}
