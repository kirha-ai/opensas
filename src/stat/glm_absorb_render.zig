//! ABSORB-specific listing. Keeps absorbed Type I sources out of Type II/III.
const std = @import("std");
const proc = @import("../proc.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const absorb = @import("glm_absorb.zig");
const math = @import("glm_fit.zig");
const A = std.mem.Allocator;
fn number(a: A, value: f64, decimals: usize) ![]const u8 {
    return if (!std.math.isFinite(value)) "." else @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals}));
}
fn probability(a: A, value: f64) ![]const u8 {
    return if (std.math.isFinite(value) and value < 0.0001) "<.0001" else number(a, value, 4);
}
fn places(maximum: f64, digits: i32) usize {
    if (!(maximum > 0) or !std.math.isFinite(maximum)) return @intCast(digits);
    const e: i32 = @intFromFloat(@floor(@log10(maximum)));
    return @intCast(@max(0, @min(12, digits - e)));
}
fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8)) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |title| try out.print(cx.arena, "\n{s}\n", .{title});
    try out.appendSlice(cx.arena, "\nThe GLM Procedure\n");
}
fn flag(spec: parse.Spec, comptime name: []const u8) bool {
    return if (@hasField(parse.Spec, name)) @field(spec, name) else false;
}
fn row(a: A, out: *std.ArrayList(u8), name: []const u8, t: math.EffectTest, decimals: usize) !void {
    try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ name, t.df, try number(a, t.ss, decimals), try number(a, t.ms, decimals), try number(a, t.f_value, 2), try probability(a, t.p_value) });
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, r: absorb.Result) !void {
    const a = cx.arena;
    try heading(cx, out);
    if (d.classes.len > 0) {
        try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
        for (d.classes) |c| {
            try out.print(a, "\n{s} {d}", .{ spec.input.ds.columns.items[c.column].name, c.levels.len });
            for (c.levels) |level| try out.print(a, " {s}", .{level.label});
            try out.append(a, '\n');
        }
    }
    try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ d.read, d.n });
    if (spec.freq != null) try out.print(a, "Sum of Frequencies Used {d}\n", .{r.n_used});
    if (spec.weight) |ci| try out.print(a, "Weight: {s}\n", .{spec.input.ds.columns.items[ci].name});
    try heading(cx, out);
    const response = spec.input.ds.columns.items[d.response].name;
    try out.print(a, "\nDependent Variable: {s}\n\nSum of\nSource DF Squares Mean Square F Value Pr > F\n", .{response});
    const total = r.sst;
    const decimals = places(total, 9);
    try out.print(a, "\nModel {d} {s} {s} {s} {s}\n\nError {d} {s} {s}\n\n{s} Total {d} {s}\n", .{ r.model.df_model, try number(a, r.model.ss_model, decimals), try number(a, r.model.ms_model, decimals), try number(a, r.model.f_value, 2), try probability(a, r.model.p_value), r.df_error, try number(a, r.sse, decimals), try number(a, r.mse, decimals), @as([]const u8, "Corrected"), r.model.df_total, try number(a, total, decimals) });
    try out.print(a, "\nR-Square Coeff Var Root MSE {s} Mean\n\n{s} {s} {s} {s}\n", .{ response, try number(a, r.model.r_square, 6), try number(a, 100 * @sqrt(r.mse) / r.y_mean, 6), try number(a, @sqrt(r.mse), 6), try number(a, r.y_mean, places(@abs(r.y_mean), 6)) });
    const defaults = !flag(spec, "ss1") and !flag(spec, "ss2") and !flag(spec, "ss3") and !flag(spec, "ss4");
    if (defaults or flag(spec, "ss1")) {
        var maximum: f64 = 0;
        for (r.absorbed) |item| maximum = @max(maximum, @abs(item.test_value.ss));
        if (r.conditional) |c| for (c.type_i) |t| {
            maximum = @max(maximum, @abs(t.ss));
        };
        const dec = places(maximum, 9);
        try out.appendSlice(a, "\nSource DF Type I SS Mean Square F Value Pr > F\n\n");
        for (r.absorbed) |item| try row(a, out, item.name, item.test_value, dec);
        const model_tests = if (r.conditional) |c| c.type_i else r.zero_effects;
        for (spec.effects, model_tests) |effect, t| try row(a, out, effect.name, t, dec);
    }
    if (flag(spec, "ss2") and spec.effects.len > 0) try table(a, out, spec, "II", if (r.conditional) |c| c.type_ii else r.zero_effects);
    if ((defaults or flag(spec, "ss3")) and spec.effects.len > 0) try table(a, out, spec, "III", if (r.conditional) |c| c.type_iii else r.zero_effects);
    if (spec.classes.len == 0) if (r.conditional) |c| {
        try out.appendSlice(a, "\nStandard\nParameter Estimate Error t Value Pr > |t|\n\n");
        var largest: f64 = 0;
        var largest_se: f64 = 0;
        for (c.model.fit.coefficients, c.model.fit.se) |coefficient, se| {
            largest = @max(largest, @abs(coefficient));
            if (std.math.isFinite(se)) largest_se = @max(largest_se, se);
        }
        for (c.model.fit.coefficients, c.model.fit.se, 0..) |coefficient, se, j| try out.print(a, "{s} {s} {s} {s} {s}\n", .{ spec.effects[j].name, try number(a, coefficient, places(largest, 9)), try number(a, se, places(largest_se, 8)), try number(a, c.model.fit.coefficientT(j), 2), try probability(a, c.model.fit.coefficientP(j)) });
    };
}
fn table(a: A, out: *std.ArrayList(u8), spec: parse.Spec, kind: []const u8, tests: []const math.EffectTest) !void {
    var maximum: f64 = 0;
    for (tests) |t| maximum = @max(maximum, @abs(t.ss));
    const dec = places(maximum, 9);
    try out.print(a, "\nSource DF Type {s} SS Mean Square F Value Pr > F\n\n", .{kind});
    for (spec.effects, tests) |effect, t| try row(a, out, effect.name, t, dec);
}
