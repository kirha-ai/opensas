//! GLM text tables. Numeric results are supplied by glm_fit, not calculated here.
const std = @import("std");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");
const A = std.mem.Allocator;
const proc = @import("../proc.zig");
fn number(a: A, value: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(value)) return ".";
    return @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals}));
}
fn probability(a: A, value: f64) ![]const u8 {
    return if (std.math.isFinite(value) and value < 0.0001) "<.0001" else number(a, value, 4);
}
fn places(maximum: f64, digits: i32) usize {
    if (!(maximum > 0) or !std.math.isFinite(maximum)) return @intCast(digits);
    const exponent: i32 = @intFromFloat(@floor(@log10(maximum)));
    return @intCast(@max(0, @min(12, digits - exponent)));
}
fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8)) !void {
    if (@hasField(proc.ProcCtx, "listing_titles")) {
        if (cx.listing_titles) |titles| {
            try titles.emitTitles(cx.arena, out);
        } else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    } else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    try out.appendSlice(cx.arena, "\nThe GLM Procedure\n");
}

pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, result: math.Result) !void {
    const tables = try @import("glm_estimate.zig").computeAll(cx, spec, d, result.model.fit.mse, result.model.fit.df_error);
    try renderPrepared(cx, out, spec, d, result, tables);
}

pub fn renderPrepared(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, result: math.Result, estimates: []const @import("glm_estimate.zig").Table) !void {
    const a = cx.arena;
    if (spec.ss4 and (result.type_iv_basis == null or result.type_iv.len != spec.effects.len)) return proc.failGap(cx.diags, 0, "PROC GLM: Type IV hypotheses have not been validated", .{});
    const fitted = result.model.fit;
    const model = fitted.modelStats(spec.intercept);
    // Computed before any output so an unsupported SOLUTION leaves no partial listing.
    var solution_text: std.ArrayList(u8) = .empty;
    if (spec.solution and spec.classes.len > 0) try solution(cx, &solution_text, spec, d, result);
    try heading(cx, out);
    if (d.classes.len > 0) {
        try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
        for (d.classes) |class| {
            try out.print(a, "\n{s} {d}", .{ spec.input.ds.columns.items[class.column].name, class.levels.len });
            for (class.levels) |level| try out.print(a, " {s}", .{level.label});
            try out.append(a, '\n');
        }
    }
    try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ d.read, d.n });
    if (spec.freq != null) try out.print(a, "Sum of Frequencies Used {d}\n", .{fitted.n_used});
    if (spec.weight) |ci| try out.print(a, "Weight: {s}\n", .{spec.input.ds.columns.items[ci].name});
    try @import("glm_estimate.zig").renderCoefficients(cx, out, estimates);
    try heading(cx, out);
    const response = spec.input.ds.columns.items[d.response].name;
    try out.print(a, "\nDependent Variable: {s}\n\nSum of\nSource DF Squares Mean Square F Value Pr > F\n", .{response});
    const total = if (spec.intercept) fitted.sst else fitted.sst_uncorrected;
    const decimals = places(@max(total, @max(model.ss_model, fitted.sse)), 9);
    try out.print(a, "\nModel {d} {s} {s} {s} {s}\n\nError {d} {s} {s}\n\n{s} Total {d} {s}\n", .{
        model.df_model,                 try number(a, model.ss_model, decimals), try number(a, model.ms_model, decimals), try number(a, model.f_value, 2),                                     try probability(a, model.p_value),
        fitted.df_error,                try number(a, fitted.sse, decimals),     try number(a, fitted.mse, decimals),     if (spec.intercept) @as([]const u8, "Corrected") else "Uncorrected", model.df_total,
        try number(a, total, decimals),
    });
    const cv = 100 * @sqrt(fitted.mse) / fitted.y_mean;
    try out.print(a, "\nR-Square Coeff Var Root MSE {s} Mean\n\n{s} {s} {s} {s}\n", .{
        response, try number(a, model.r_square, 6), try number(a, cv, places(@abs(cv), 6)), try number(a, @sqrt(fitted.mse), 6), try number(a, fitted.y_mean, places(@abs(fitted.y_mean), 6)),
    });
    const default_ss = spec.defaultSumsOfSquares();
    if (default_ss or spec.ss1) try effects(a, out, spec, "I", result.type_i);
    if (spec.ss2) try effects(a, out, spec, "II", result.type_ii);
    if (default_ss or spec.ss3) try effects(a, out, spec, "III", result.type_iii);
    if (spec.ss4) try effects(a, out, spec, "IV", result.type_iv);
    if (spec.classes.len == 0) {
        try out.appendSlice(a, "\nStandard\nParameter Estimate Error t Value Pr > |t|\n\n");
        var maximum: f64 = 0;
        var max_se: f64 = 0;
        for (fitted.coefficients, fitted.se) |coefficient, se| {
            maximum = @max(maximum, @abs(coefficient));
            if (std.math.isFinite(se)) max_se = @max(max_se, se);
        }
        for (fitted.coefficients, fitted.se, 0..) |coefficient, se, j| {
            const name = if (spec.intercept and j == 0) "Intercept" else spec.effects[j - @as(usize, if (spec.intercept) 1 else 0)].name;
            try out.print(a, "{s} {s} {s} {s} {s}\n", .{ name, try number(a, coefficient, places(maximum, 9)), try number(a, se, places(max_se, 8)), try number(a, fitted.coefficientT(j), 2), try probability(a, fitted.coefficientP(j)) });
        }
    }
    try out.appendSlice(a, solution_text.items);
    try @import("glm_estimate.zig").renderResults(cx, out, estimates);
}
/// MODEL / SOLUTION for CLASS models (S154 PROC GLM "Parameter Estimates"):
/// the singular parameterization is derived from the full-rank fit by
/// plm_infer.parameters; shapes it cannot map exactly stay a loud gap.
fn solution(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, result: math.Result) !void {
    const a = cx.arena;
    const fitted = result.model.fit;
    const gap = "PROC GLM: SOLUTION is implemented only for full-rank CLASS-only models without BY, ABSORB, RANDOM, TEST, MANOVA or formatted CLASS variables";
    if (fitted.rank != d.p or fitted.df_error == 0 or !std.math.isFinite(fitted.mse)) return proc.failGap(cx.diags, 0, gap, .{});
    var plain = spec;
    plain.store = .{ .name = "work._solution_" };
    if (spec.responses.len != 1 or spec.by.len > 0 or spec.random != null or spec.test_requests.len > 0 or spec.manova) return proc.failGap(cx.diags, 0, gap, .{});
    for (spec.classes) |ci| if (spec.input.ds.columns.items[ci].format != null) return proc.failGap(cx.diags, 0, gap, .{});
    const model = try @import("store_glm.zig").model(cx, plain, d, result);
    const parms = @import("plm_infer.zig").parameters(a, model) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return proc.failGap(cx.diags, 0, gap, .{}),
    };
    var maximum: f64 = 0;
    var max_se: f64 = 0;
    var singular = false;
    for (parms) |parm| {
        maximum = @max(maximum, @abs(parm.estimate));
        if (parm.stderr) |se| max_se = @max(max_se, se);
        singular = singular or !parm.estimable;
    }
    try out.appendSlice(a, "\nStandard\nParameter Estimate Error t Value Pr > |t|\n\n");
    for (parms) |parm| {
        try out.appendSlice(a, if (parm.effect) |e| model.effects[e].name else "Intercept");
        if (parm.effect) |e| for (model.effects[e].factors) |factor| {
            const ci = factor.class_index.?;
            try out.print(a, " {s}", .{std.mem.trim(u8, model.classes[ci].levels[parm.levels[ci].?].label, " ")});
        };
        try out.print(a, " {s}{s}", .{ try number(a, parm.estimate, places(maximum, 9)), if (parm.estimable) "" else " B" });
        if (parm.stderr) |se| {
            const t_value = parm.estimate / se;
            try out.print(a, " {s} {s} {s}\n", .{ try number(a, se, places(max_se, 8)), try number(a, t_value, 2), try probability(a, @import("univ_inference.zig").tProbability(t_value, @floatFromInt(fitted.df_error))) });
        } else try out.appendSlice(a, " . . .\n");
    }
    if (singular) try out.appendSlice(a, "\nNOTE: The X'X matrix has been found to be singular, and a generalized inverse was used to solve the normal equations. Terms whose estimates are followed by\nthe letter 'B' are not uniquely estimable.\n");
}
fn effects(a: A, out: *std.ArrayList(u8), spec: parse.Spec, kind: []const u8, tests: []const math.EffectTest) !void {
    var maximum: f64 = 0;
    for (tests) |test_value| maximum = @max(maximum, @abs(test_value.ss));
    const decimals = places(maximum, 9);
    try out.print(a, "\nSource DF Type {s} SS Mean Square F Value Pr > F\n\n", .{kind});
    for (spec.effects, tests) |effect, test_value| try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{
        effect.name, test_value.df, try number(a, test_value.ss, decimals), try number(a, test_value.ms, decimals), try number(a, test_value.f_value, 2), try probability(a, test_value.p_value),
    });
}
