//! Arithmetic MEANS for GLM, S154 physical pp.4086–4090,4129–4131.
//! These are observed groups, not balanced population margins or LS-means.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { effect: usize, deponly: bool = false };
pub const Group = struct { key: usize, levels: []const usize, count: usize, means: []f64, standard_deviations: []f64 };
pub const Table = struct { effect: usize, class_positions: []const usize, variables: []const usize, groups: []Group };
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect, requests: *std.ArrayList(Request)) diag.Error!void {
    const first = requests.items.len;
    var i: usize = 1;
    while (i < tokens.len and tokens[i].tag != .slash) {
        var variables: std.ArrayList(usize) = .empty;
        while (true) {
            if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: MEANS requires CLASS effects", .{});
            const col = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: MEANS variable not found", .{});
            if (std.mem.indexOfScalar(usize, spec.classes, col) == null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: MEANS effects must contain only CLASS variables", .{});
            if (std.mem.indexOfScalar(usize, variables.items, col) != null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: repeated MEANS factor", .{});
            try variables.append(cx.arena, col);
            i += 1;
            if (i == tokens.len or tokens[i].tag != .star) break;
            i += 1;
        }
        const found = for (effects, 0..) |effect, index| {
            if (effect.variables.len != variables.items.len) continue;
            var matches = true;
            for (variables.items) |col| if (std.mem.indexOfScalar(usize, effect.variables, col) == null) { matches = false; };
            if (matches) break index;
        } else return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: MEANS effect is not in MODEL", .{});
        try requests.append(cx.arena, .{ .effect = found });
    }
    if (requests.items.len == first) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: MEANS requires an effect", .{});
    var deponly = false;
    if (i < tokens.len) i += 1;
    while (i < tokens.len) : (i += 1) {
        if (eq(tokens[i].text, "deponly")) deponly = true else {
            for ([_][]const u8{ "alpha", "bon", "cldiff", "clm", "duncan", "dunnett", "dunnettl", "dunnettu", "e", "etype", "gabriel", "gt2", "hovtest", "htype", "kratio", "lines", "linestable", "lsd", "nosort", "regwq", "scheffe", "sidak", "smm", "snk", "t", "tukey", "waller", "welch" }) |known| if (eq(tokens[i].text, known)) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: MEANS option {s} is not implemented in this combination", .{tokens[i].text});
            return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: unknown MEANS option {s}", .{tokens[i].text});
        }
    }
    for (requests.items[first..]) |*request| request.deponly = deponly;
}
const Sum = struct {
    value: f64 = 0, correction: f64 = 0,
    fn add(self: *Sum, x: f64) void { const next = self.value + x; self.correction += if (@abs(self.value) >= @abs(x)) (self.value - next) + x else (x - next) + self.value; self.value = next; }
    fn total(self: Sum) f64 { return self.value + self.correction; }
};
fn less(_: void, left: Group, right: Group) bool { return left.key < right.key; }
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request) diag.Error!Table {
    if (spec.weight != null) return proc.failGap(cx.diags, 0, "PROC GLM: weighted MEANS standard-deviation conventions are not implemented", .{});
    const a = cx.arena;
    var positions: std.ArrayList(usize) = .empty;
    for (d.classes, 0..) |class, index| if (std.mem.indexOfScalar(usize, spec.effects[request.effect].variables, class.column) != null) try positions.append(a, index);
    var variables: std.ArrayList(usize) = .empty;
    try variables.append(a, d.response);
    if (!request.deponly) for (spec.effects) |effect| for (effect.variables) |col| {
        if (std.mem.indexOfScalar(usize, spec.classes, col) == null and std.mem.indexOfScalar(usize, variables.items, col) == null) try variables.append(a, col);
    };
    var groups: std.ArrayList(Group) = .empty;
    const keys = try a.alloc(usize, d.n);
    for (0..d.n) |row| {
        var key: usize = 0;
        for (positions.items) |index| {
            key = std.math.mul(usize, key, d.classes[index].levels.len) catch return error.ExecError;
            key = std.math.add(usize, key, d.classes[index].row_levels[row].?) catch return error.ExecError;
        }
        keys[row] = key;
        var found = false;
        for (groups.items) |group| if (group.key == key) { found = true; break; };
        if (!found) {
            const levels = try a.alloc(usize, positions.items.len);
            for (positions.items, levels) |index, *level| level.* = d.classes[index].row_levels[row].?;
            try groups.append(a, .{ .key = key, .levels = levels, .count = 0, .means = try a.alloc(f64, variables.items.len), .standard_deviations = try a.alloc(f64, variables.items.len) });
        }
    }
    std.mem.sort(Group, groups.items, {}, less);
    for (groups.items) |*group| {
        var count: usize = 0;
        for (keys, d.frequencies) |key, frequency| if (key == group.key) {
            if (!std.math.isFinite(frequency) or frequency < 1 or frequency >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.ExecError;
            count = std.math.add(usize, count, @intFromFloat(frequency)) catch return error.ExecError;
        };
        if (count == 0) return error.ExecError;
        group.count = count;
        for (variables.items, group.means, group.standard_deviations) |column, *mean, *sd| {
            var anchor: ?f64 = null;
            var total: Sum = .{};
            for (keys, d.observations, d.frequencies) |key, observation, frequency| if (key == group.key) {
                const value = observation.cells[column].num;
                if (!std.math.isFinite(value)) return error.ExecError;
                if (anchor == null) anchor = value;
                total.add(frequency * (value - anchor.?));
            };
            mean.* = anchor.? + total.total() / @as(f64, @floatFromInt(count));
            var deviations: Sum = .{};
            for (keys, d.observations, d.frequencies) |key, observation, frequency| if (key == group.key) { const delta = observation.cells[column].num - mean.*; deviations.add(frequency * delta * delta); };
            if (!std.math.isFinite(mean.*) or !std.math.isFinite(deviations.total())) return cx.diags.fail(error.ExecError, 0, "PROC GLM: MEANS numerical overflow", .{});
            sd.* = if (count > 1) @sqrt(@max(0, deviations.total()) / @as(f64, @floatFromInt(count - 1))) else std.math.nan(f64);
        }
    }
    return .{ .effect = request.effect, .class_positions = positions.items, .variables = variables.items, .groups = groups.items };
}
fn number(a: std.mem.Allocator, value: f64) ![]const u8 { return if (!std.math.isFinite(value)) "." else std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, "32.7"), " "); }
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, table: Table) diag.Error!void {
    if (spec.noprint) return;
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |title| try out.print(cx.arena, "\n{s}\n", .{title});
    try out.appendSlice(cx.arena, "\nThe GLM Procedure\n\nLevel of ");
    for (table.class_positions) |index| try out.print(cx.arena, "{s} ", .{spec.input.ds.columns.items[d.classes[index].column].name});
    try out.appendSlice(cx.arena, "N");
    for (table.variables) |column| try out.print(cx.arena, " {s} Mean Std Dev", .{spec.input.ds.columns.items[column].name});
    try out.append(cx.arena, '\n');
    for (table.groups) |group| {
        for (group.levels, table.class_positions) |level, index| try out.print(cx.arena, "{s} ", .{d.classes[index].levels[level].label});
        try out.print(cx.arena, "{d}", .{group.count});
        for (group.means, group.standard_deviations) |mean, sd| try out.print(cx.arena, " {s} {s}", .{ try number(cx.arena, mean), try number(cx.arena, sd) });
        try out.append(cx.arena, '\n');
    }
}
pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design) diag.Error!void {
    for (spec.means) |request| try render(cx, out, spec, d, try compute(cx, spec, d, request));
}
test { _ = @import("glm_means_tests.zig"); }
