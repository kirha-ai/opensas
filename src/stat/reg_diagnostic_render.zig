//! Native REG collinearity/influence tables; all cells use actual kernel results.
const std = @import("std");
const parse = @import("reg_parse.zig");
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;
fn fixed(a: A, v: f64, comptime places: usize) ![]const u8 {
    if (!std.math.isFinite(v)) return ".";
    return std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{places}) ++ "}", .{v});
}
fn statistic(a: A, v: f64) ![]const u8 {
    if (@abs(v) >= 10000) return fixed(a, v, 0);
    if (v != 0 and @abs(v) < 0.001) return fixed(a, v, 8);
    return fixed(a, v, 5);
}
fn parameter(spec: parse.Spec, model: parse.Model, j: usize) []const u8 {
    return if (model.intercept and j == 0) "Intercept" else spec.ds.columns.items[model.regressors[j - @as(usize, if (model.intercept) 1 else 0)]].name;
}
pub fn collinearity(a: A, out: *std.ArrayList(u8), spec: parse.Spec, model: parse.Model, result: @import("reg_collinearity.zig").Result) !void {
    try out.print(a, "\nCollinearity Diagnostics{s}\nProportion of Variation\nNumber Eigenvalue Condition Index", .{if (result.centered) @as([]const u8, " (Intercept Adjusted)") else ""});
    for (0..result.columns) |j| try out.print(a, " {s}", .{parameter(spec, model, j + @as(usize, if (result.centered) 1 else 0))});
    try out.append(a, '\n');
    for (result.eigenvalues, result.condition_indices, 0..) |root, index, i| {
        try out.print(a, "{d} {s} {s}", .{ i + 1, try statistic(a, root), try fixed(a, index, 5) });
        for (0..result.columns) |j| try out.print(a, " {s}", .{try statistic(a, result.variance_proportions[i * result.columns + j])});
        try out.append(a, '\n');
    }
}
pub fn influence(a: A, out: *std.ArrayList(u8), spec: parse.Spec, model: parse.Model, source_rows: []const usize, fit: Fit, result: @import("reg_influence.zig").Result) !void {
    try out.print(a, "\nThe REG Procedure\nModel: {s}\nDependent Variable: {s}\n\nOutput Statistics\n\nDFBETAS\nObs Residual RStudent Hat Diag H Cov Ratio DFFITS", .{ model.label, spec.ds.columns.items[model.dependent].name });
    for (0..fit.coefficients.len) |j| try out.print(a, " {s}", .{parameter(spec, model, j)});
    try out.append(a, '\n');
    for (result.rows, source_rows) |row, observation| {
        try out.print(a, "{d} {s} {s} {s} {s} {s}", .{ observation, try fixed(a, row.residual, 4), try fixed(a, row.rstudent, 4), try fixed(a, row.leverage, 4), try fixed(a, row.covratio, 4), try fixed(a, row.dffits, 4) });
        for (row.dfbetas) |v| try out.print(a, " {s}", .{try fixed(a, v, 4)});
        try out.append(a, '\n');
    }
    var residual_sum: f64 = 0;
    for (fit.residuals) |r| residual_sum += r;
    try out.print(a, "\nSum of Residuals {s}\nSum of Squared Residuals {s}\nPredicted Residual SS (PRESS) {s}\n", .{ std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = residual_sum }, "best12."), " "), try statistic(a, fit.sse), if (result.press) |v| try statistic(a, v) else @as([]const u8, ".") });
}

pub fn serial(a: A, out: *std.ArrayList(u8), result: @import("reg_specification.zig").Serial) !void {
    try out.print(a, "\nDurbin-Watson D {s}\nNumber of Observations {d}\n1st Order Autocorrelation {s}\n", .{ try fixed(a, result.d, 3), result.n, try fixed(a, result.correlation, 3) });
}
pub fn lackFit(a: A, out: *std.ArrayList(u8), result: @import("reg_specification.zig").LackFit) !void {
    const probability = if (result.probability < 0.0001) @as([]const u8, "<.0001") else try fixed(a, result.probability, 4);
    try out.print(a, "\nLack of Fit Test\nSource DF Sum of Squares Mean Square F Value Pr > F\nLack of Fit {d} {s} {s} {s} {s}\nPure Error {d} {s} {s}\n", .{ result.lack_df, try statistic(a, result.lack_ss), try statistic(a, result.lack_ms), try fixed(a, result.f, 2), probability, result.pure_df, try statistic(a, result.pure_ss), try statistic(a, result.pure_ms) });
}
pub fn hetero(a: A, out: *std.ArrayList(u8), spec: parse.Spec, model: parse.Model, result: @import("reg_specification.zig").Hetero) !void {
    try out.print(a, "\nHeteroscedasticity Consistent Covariance Matrix\nHCCMETHOD={d}\nVariable", .{result.method});
    const p = result.errors.len;
    for (0..p) |j| try out.print(a, " {s}", .{parameter(spec, model, j)});
    try out.append(a, '\n');
    for (0..p) |i| {
        try out.print(a, "{s}", .{parameter(spec, model, i)});
        for (0..p) |j| try out.print(a, " {s}", .{try statistic(a, result.covariance[i * p + j])});
        try out.append(a, '\n');
    }
}
