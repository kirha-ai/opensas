//! Listing for the implemented one-factor REPEATED domain.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const glm = @import("glm.zig");
const repeated = @import("glm_repeated.zig");
const A = std.mem.Allocator;
fn number(a: A, x: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
fn probability(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else number(a, p, 4);
}

fn header(a: A, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(a, "\nThe GLM Procedure\nRepeated Measures Analysis of Variance\n");
}
fn annotation(a: A, out: *std.ArrayList(u8), r: repeated.Request) !void {
    if (r.transformation == .polynomial) try out.print(a, "\n{s}_N represents the nth degree polynomial contrast for {s}\n", .{ r.name, r.name });
}
fn row(a: A, out: *std.ArrayList(u8), name: []const u8, df: usize, ss: f64, error_ss: f64, error_df: usize, decimals: usize) !void {
    const ms = ss / @as(f64, @floatFromInt(df));
    const f = ms / (error_ss / @as(f64, @floatFromInt(error_df)));
    try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ name, df, try number(a, ss, decimals), try number(a, ms, decimals), try number(a, f, 2), try probability(a, @import("reg_fit.zig").fProbability(f, df, error_df)) });
}
fn errorRow(a: A, out: *std.ArrayList(u8), name: []const u8, df: usize, ss: f64, decimals: usize) !void {
    try out.print(a, "{s} {d} {s} {s}\n", .{ name, df, try number(a, ss, decimals), try number(a, ss / @as(f64, @floatFromInt(df)), decimals) });
}
fn correlations(a: A, out: *std.ArrayList(u8), labels: []const []const u8, e: []const f64, df: usize, transformed: bool) !void {
    const k = labels.len;
    try out.print(a, "\nPartial Correlation Coefficients from the Error SSCP Matrix{s} / Prob > |r|\n\nDF = {d}", .{ if (transformed) @as([]const u8, " of the Variables Defined by the Specified Transformation") else "", df });
    for (labels) |label| try out.print(a, " {s}", .{label});
    try out.append(a, '\n');
    for (labels, 0..) |label, i| {
        try out.print(a, "\n{s}", .{label});
        for (0..k) |j| {
            const r = e[i * k + j] / @sqrt(e[i * k + i] * e[j * k + j]);
            try out.print(a, " {s}", .{try number(a, r, 6)});
        }
        try out.append(a, '\n');
        for (0..k) |j| {
            if (i == j) continue;
            const r = e[i * k + j] / @sqrt(e[i * k + i] * e[j * k + j]);
            const t = @abs(r) * @sqrt(@as(f64, @floatFromInt(df - 1)) / @max(0, 1 - r * r));
            try out.print(a, " {s}", .{try probability(a, @import("reg_fit.zig").tProbability(t, df - 1))});
        }
        try out.append(a, '\n');
    }
}
fn matrix(a: A, out: *std.ArrayList(u8), labels: []const []const u8, values: []const f64) !void {
    for (labels) |label| try out.print(a, " {s}", .{label});
    try out.append(a, '\n');
    for (labels, 0..) |label, i| {
        try out.print(a, "{s}", .{label});
        for (0..labels.len) |j| try out.print(a, " {s}", .{try number(a, values[i * labels.len + j], 5)});
        try out.append(a, '\n');
    }
}
fn tail(f: f64, d1: f64, d2: f64) f64 {
    return @import("../functions.zig").betaI(d2 / (d2 + d1 * f), d2 / 2, d1 / 2);
}
fn trace(e: []const f64, k: usize) f64 {
    var sum: f64 = 0;
    for (0..k) |i| sum += e[i * k + i];
    return sum;
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: glm.Spec, result: repeated.Analysis) diag.Error!void {
    const a = cx.arena;
    const request = spec.repeated.?;
    const d = result.design;
    const k = spec.responses.len;
    const b = k - 1;
    const df = result.error_df;
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out) else if (cx.graph_title) |title| try out.print(a, "\n{s}\n", .{title});
    try out.appendSlice(a, "\nThe GLM Procedure\n");
    if (d.classes.len > 0) {
        try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
        for (d.classes) |class| {
            try out.print(a, "\n{s} {d}", .{ spec.input.ds.columns.items[class.column].name, class.levels.len });
            for (class.levels) |level| try out.print(a, " {s}", .{level.label});
            try out.append(a, '\n');
        }
    }
    try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ d.read, d.n });
    try header(a, out);
    try out.appendSlice(a, "\nRepeated Measures Level Information\n\n");
    const original_labels = try a.alloc([]const u8, k);
    var wrapped = false;
    for (spec.responses, original_labels) |ci, *label| {
        label.* = spec.input.ds.columns.items[ci].name;
        if (label.len > 10) wrapped = true;
    }
    if (wrapped) {
        for (original_labels) |label| if (label.len > 10) {
            try out.print(a, " {s}", .{label[0 .. label.len - 10]});
        };
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "Dependent Variable");
    for (original_labels) |label| try out.print(a, " {s}", .{label[label.len - @min(label.len, 10) ..]});
    try out.print(a, "\nLevel of {s}", .{request.name});
    for (request.levels) |value| try out.print(a, " {d}", .{value});
    try out.append(a, '\n');
    const labels = try a.alloc([]const u8, b);
    for (labels, 0..) |*label, j| label.* = try std.fmt.allocPrint(a, "{s}{s}{d}", .{ request.name, if (request.transformation == .polynomial) @as([]const u8, "_") else ".", j + 1 });
    if (request.printm) {
        try out.appendSlice(a, "\nM = Transformation Matrix\n");
        for (original_labels) |label| try out.print(a, " {s}", .{label});
        try out.append(a, '\n');
        for (result.transform, labels) |coefficients, label| {
            try out.print(a, "{s}", .{label});
            for (coefficients) |value| try out.print(a, " {s}", .{try number(a, value, 5)});
            try out.append(a, '\n');
        }
    }
    if (request.printe) {
        try correlations(a, out, original_labels, result.error_matrix, df, false);
        try out.appendSlice(a, "\nE = Error SSCP Matrix\n");
        try annotation(a, out, request);
        try matrix(a, out, labels, result.tests[0].error_matrix);
        try correlations(a, out, labels, result.tests[0].error_matrix, df, true);
        if (b > 1) {
            try out.appendSlice(a, "\nSphericity Tests\n\nMauchly's\nVariables DF Criterion Chi-Square Pr > ChiSq\n\n");
            for ([_][]const u8{ "Transformed Variates", "Orthogonal Components" }, [_]repeated.Sphericity{ result.transformed_sphere, result.sphere }) |name, sphere| try out.print(a, "{s} {d} {s} {s} {s}\n", .{ name, sphere.df, try number(a, sphere.criterion, 7), try number(a, sphere.chi_square, 6), try probability(a, sphere.probability) });
        }
    }
    for (result.tests, 0..) |test_result, i| {
        const name = if (i == 0) request.name else try std.fmt.allocPrint(a, "{s}*{s}", .{ request.name, spec.effects[i - 1].name });
        if (request.printh) {
            try out.print(a, "\nH = Type III SSCP Matrix for {s}\n", .{name});
            try matrix(a, out, labels, test_result.hypothesis);
        }
        if (request.nom) continue;
        // General approximate/upper-bound rendering requires separate verified
        // titles/footnotes. Current public domain is the exact rank-one case.
        try out.print(a, "\nMANOVA Test Criteria and Exact F Statistics for the Hypothesis of no {s} Effect\nH = Type III SSCP Matrix for {s}\nE = Error SSCP Matrix\n\nS={d} M={s} N={s}\n\nStatistic Value F Value Num DF Den DF Pr > F\n\n", .{ name, name, test_result.s, try number(a, test_result.m, 1), try number(a, test_result.n, 1) });
        for ([_][]const u8{ "Wilks' Lambda", "Pillai's Trace", "Hotelling-Lawley Trace", "Roy's Greatest Root" }, test_result.statistics) |stat_name, stat| try out.print(a, "{s} {s} {s} {s} {s} {s}\n", .{ stat_name, try number(a, stat.value, 8), try number(a, stat.f, 2), try number(a, stat.numerator_df, 0), try number(a, stat.denominator_df, 0), try probability(a, stat.probability) });
    }
    if (!request.nou) {
        try header(a, out);
        try out.appendSlice(a, "Tests of Hypotheses for Between Subjects Effects\n\nSource DF Type III SS Mean Square F Value Pr > F\n\n");
        const decimals: usize = 8;
        for (result.between.type_iii, spec.effects) |test_result, effect| try row(a, out, effect.name, test_result.df, test_result.ss, result.between.model.fit.sse, df, decimals);
        try errorRow(a, out, "Error", df, result.between.model.fit.sse, decimals);
        try header(a, out);
        try out.print(a, "Univariate Tests of Hypotheses for Within Subject Effects\n\nAdj Pr > F\nSource DF Type III SS Mean Square F Value Pr > F G - G {s}\n\n", .{switch (request.epsilon) {
            .hf => "H-F",
            .hfl => "H-F-L",
            .cm => "C-M",
        }});
        const error_ss = trace(result.orthogonal_tests[0].error_matrix, b);
        const within_decimals: usize = 8;
        for (result.orthogonal_tests, 0..) |test_result, i| {
            const name = if (i == 0) request.name else try std.fmt.allocPrint(a, "{s}*{s}", .{ request.name, spec.effects[i - 1].name });
            const ss = trace(test_result.hypothesis, b);
            const d1: f64 = @floatFromInt(b * test_result.q);
            const d2: f64 = @floatFromInt(b * df);
            const ms = ss / d1;
            const f = ms / (error_ss / d2);
            const eps = @min(1, @max(if (request.epsilon == .cm) 1 / @as(f64, @floatFromInt(b)) else 0, result.sphere.adjusted));
            try out.print(a, "{s} {d} {s} {s} {s} {s} {s} {s}\n", .{ name, b * test_result.q, try number(a, ss, within_decimals), try number(a, ms, within_decimals), try number(a, f, 2), try probability(a, tail(f, d1, d2)), try probability(a, tail(f, d1 * result.sphere.gg, d2 * result.sphere.gg)), try probability(a, tail(f, d1 * eps, d2 * eps)) });
        }
        try errorRow(a, out, try std.fmt.allocPrint(a, "Error({s})", .{request.name}), df * b, error_ss, within_decimals);
        try out.print(a, "\nGreenhouse-Geisser Epsilon {s}\n{s} Epsilon {s}\n", .{ try number(a, result.sphere.gg, 4), switch (request.epsilon) {
            .hf => "Huynh-Feldt",
            .hfl => "Huynh-Feldt-Lecoutre",
            .cm => "Chi-Muller",
        }, try number(a, result.sphere.adjusted, 4) });
    }
    if (request.summary) {
        try header(a, out);
        try out.appendSlice(a, "Analysis of Variance of Contrast Variables\n");
        try annotation(a, out, request);
        for (labels, 0..) |label, j| {
            try out.print(a, "\nContrast Variable: {s}\n\nSource DF Type III SS Mean Square F Value Pr > F\n\n", .{label});
            const error_ss = result.tests[0].error_matrix[j * b + j];
            const decimals: usize = 8;
            for (result.tests, 0..) |test_result, i| try row(a, out, if (i == 0) "Mean" else spec.effects[i - 1].name, test_result.q, test_result.hypothesis[j * b + j], error_ss, df, decimals);
            try errorRow(a, out, "Error", df, error_ss, decimals);
        }
    }
}
