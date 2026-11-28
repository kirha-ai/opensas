//! GLM LSMEANS AT, S154 physical pp.4145–4146/Table53.14.
//! AT changes product moments, precision weighting and missing-response sampling.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const selection = @import("data_selection.zig");
const Value = @import("../value.zig").Value;
pub const Setting = struct { column: usize, value: f64 };
pub const Request = struct { settings: []const Setting = &.{} };
pub const Covariates = struct { values: []f64, population_rows: usize, total_weight: f64 };
fn covariate(cx: proc.ProcCtx, token: lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!usize {
    if (token.tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: AT requires covariate names", .{});
    const col = spec.input.ds.indexOf(token.text) orelse return cx.diags.fail(error.ParseError, token.line, "PROC GLM: AT variable not found", .{});
    if (spec.input.ds.columns.items[col].type != .num or std.mem.indexOfScalar(usize, spec.classes, col) != null) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: AT requires continuous covariates", .{});
    for (effects) |effect| if (std.mem.indexOfScalar(usize, effect.variables, col) != null) return col;
    return cx.diags.fail(error.ParseError, token.line, "PROC GLM: AT covariate is not in MODEL", .{});
}
fn number(cx: proc.ProcCtx, tokens: []const lex.Token, i: *usize, line: usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (i.* < tokens.len and (tokens[i.*].tag == .minus or tokens[i.*].tag == .plus)) { if (tokens[i.*].tag == .minus) sign = -1; i.* += 1; }
    if (i.* >= tokens.len or tokens[i.*].tag != .number) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT requires finite numeric values", .{});
    const result = sign * (std.fmt.parseFloat(f64, tokens[i.*].text) catch return cx.diags.fail(error.ParseError, line, "PROC GLM: invalid AT number", .{}));
    if (!std.math.isFinite(result)) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT values must be finite", .{});
    i.* += 1;
    return result;
}
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, i: *usize, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    const line = tokens[i.*].line;
    i.* += 1;
    if (i.* >= tokens.len) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT requires MEANS or a covariate assignment", .{});
    if (std.ascii.eqlIgnoreCase(tokens[i.*].text, "means") and !(i.* + 1 < tokens.len and tokens[i.* + 1].tag == .eq)) { i.* += 1; return .{}; }
    const grouped = tokens[i.*].tag == .lparen;
    if (grouped) i.* += 1;
    var columns: std.ArrayList(usize) = .empty;
    while (i.* < tokens.len and tokens[i.*].tag == .name) {
        const col = try covariate(cx, tokens[i.*], spec, effects);
        if (std.mem.indexOfScalar(usize, columns.items, col) != null) return cx.diags.fail(error.ParseError, line, "PROC GLM: duplicate AT covariate", .{});
        try columns.append(cx.arena, col);
        i.* += 1;
        if (!grouped) break;
    }
    if (columns.items.len == 0 or (grouped and (i.* == tokens.len or tokens[i.*].tag != .rparen))) return cx.diags.fail(error.ParseError, line, "PROC GLM: invalid AT covariate list", .{});
    if (grouped) i.* += 1;
    if (i.* == tokens.len or tokens[i.*].tag != .eq) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT assignment requires =", .{});
    i.* += 1;
    if (grouped) {
        if (i.* == tokens.len or tokens[i.*].tag != .lparen) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT value list requires parentheses", .{});
        i.* += 1;
    }
    const settings = try cx.arena.alloc(Setting, columns.items.len);
    for (columns.items, settings) |col, *setting| setting.* = .{ .column = col, .value = try number(cx, tokens, i, line) };
    if (grouped) {
        if (i.* == tokens.len or tokens[i.*].tag != .rparen) return cx.diags.fail(error.ParseError, line, "PROC GLM: AT value count must match covariates", .{});
        i.* += 1;
    }
    return .{ .settings = settings };
}
const Sum = struct {
    value: f64 = 0, correction: f64 = 0,
    fn add(self: *Sum, x: f64) void { const next = self.value + x; self.correction += if (@abs(self.value) >= @abs(x)) (self.value - next) + x else (x - next) + self.value; self.value = next; }
    fn total(self: Sum) f64 { return self.value + self.correction; }
};
pub const Population = struct { observations: []const selection.Observation, map_rows: []const usize, maps: []const @import("class_levels.zig").Levels, covariates: []const usize };
/// Use only the caller's original BY slice. AT excludes all-response-missing
/// cells; observed CLASS margins include those cells when all levels are fitted.
pub fn population(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, exclude_missing_cells: bool) diag.Error!Population {
    if (spec.responses.len != 1) return proc.failGap(cx.diags, 0, "PROC GLM: multivariate marginal-population sampling is not implemented", .{});
    const a = cx.arena;
    var required: std.ArrayList(usize) = .empty;
    var covariates: std.ArrayList(usize) = .empty;
    for (spec.classes) |col| {
        const used = for (spec.effects) |effect| { if (std.mem.indexOfScalar(usize, effect.variables, col) != null) break true; } else false;
        if (!used) return proc.failGap(cx.diags, 0, "PROC GLM: marginal populations with unused CLASS declarations are not implemented", .{});
        try required.append(a, col);
    }
    for (spec.effects) |effect| for (effect.variables) |col| {
        if (std.mem.indexOfScalar(usize, required.items, col) == null) try required.append(a, col);
        if (std.mem.indexOfScalar(usize, spec.classes, col) == null and std.mem.indexOfScalar(usize, covariates.items, col) == null) try covariates.append(a, col);
    };
    if (d.input_observations.len == 0 and d.read != d.n) return proc.failGap(cx.diags, 0, "PROC GLM: marginal-population rows are unavailable", .{});
    const original: selection.View = .{ .source = spec.input.ds, .roles = .{ .frequency = spec.freq, .weight = spec.weight }, .observations = if (d.input_observations.len > 0) d.input_observations else d.observations };
    const eligible = try original.select(a, .{ .missing_columns = required.items, .frequency = .truncate_positive, .weight = .positive_only });
    const all_rows = try a.alloc([]const Value, d.n + eligible.observations.len);
    for (d.observations, all_rows[0..d.n]) |row, *target| target.* = row.cells;
    for (eligible.observations, all_rows[d.n..]) |row, *target| target.* = row.cells;
    const maps = try a.alloc(@import("class_levels.zig").Levels, spec.classes.len);
    for (spec.classes, maps) |col, *map| map.* = try @import("class_levels.zig").build(a, spec.input.ds, all_rows, col, .{ .order = .data });
    const key = try a.alloc(usize, spec.classes.len);
    var cells: std.StringHashMapUnmanaged(void) = .empty;
    for (0..d.n) |row| {
        for (maps, key) |map, *part| part.* = map.row_to_level[row] orelse return error.ExecError;
        try cells.put(a, try a.dupe(u8, std.mem.sliceAsBytes(key)), {});
    }
    var rows: std.ArrayList(selection.Observation) = .empty;
    var map_rows: std.ArrayList(usize) = .empty;
    for (eligible.observations, 0..) |row, index| {
        var valid = true;
        for (maps, key) |map, *part| { part.* = map.row_to_level[d.n + index] orelse blk: { valid = false; break :blk 0; }; }
        if (!valid) continue;
        if (exclude_missing_cells) {
            if (!cells.contains(std.mem.sliceAsBytes(key))) continue;
        } else {
            for (maps, key) |map, value| {
                const known = for (map.row_to_level[0..d.n]) |level| { if (level != null and level.? == value) break true; } else false;
                if (!known) return proc.failGap(cx.diags, 0, "PROC GLM: observed margins with new unfitted CLASS levels are not implemented", .{});
            }
        }
        try rows.append(a, row);
        try map_rows.append(a, d.n + index);
    }
    return .{ .observations = rows.items, .map_rows = map_rows.items, .maps = maps, .covariates = covariates.items };
}
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request) diag.Error!Covariates {
    const a = cx.arena;
    const pop = try population(cx, spec, d, true);
    const sums = try a.alloc(Sum, pop.covariates.len);
    @memset(sums, .{});
    const anchors = try a.alloc(?f64, pop.covariates.len);
    @memset(anchors, null);
    var total_weight: Sum = .{};
    for (pop.observations) |row| {
        const weight = row.frequency.num * row.weight.num;
        if (!std.math.isFinite(weight) or !(weight > 0)) return proc.failGap(cx.diags, 0, "PROC GLM: AT weighting exceeds the supported numerical domain", .{});
        total_weight.add(weight);
        for (pop.covariates, sums, anchors) |col, *sum, *anchor| {
            const value = row.cells[col].num;
            if (!std.math.isFinite(value)) return cx.diags.fail(error.ExecError, 0, "PROC GLM: nonfinite AT population covariate", .{});
            if (anchor.* == null) anchor.* = value;
            sum.add(weight * (value - anchor.*.?));
        }
    }
    if (pop.observations.len == 0 or !std.math.isFinite(total_weight.total())) return proc.failGap(cx.diags, 0, "PROC GLM: no supported AT population", .{});
    const values = try a.alloc(f64, spec.input.ds.columns.items.len);
    @memset(values, std.math.nan(f64));
    for (pop.covariates, sums, anchors) |col, sum, anchor| {
        values[col] = anchor.? + sum.total() / total_weight.total();
        if (!std.math.isFinite(values[col])) return cx.diags.fail(error.ExecError, 0, "PROC GLM: AT covariate mean overflow", .{});
    }
    for (request.settings) |setting| values[setting.column] = setting.value;
    return .{ .values = values, .population_rows = pop.observations.len, .total_weight = total_weight.total() };
}
