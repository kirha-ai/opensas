//! REG listing presentation; all values come from the numerical result.
const std = @import("std");
const parse = @import("reg_parse.zig");
const A = std.mem.Allocator;
pub const Result = struct {
    n: f64,
    rank: usize,
    df_model: f64,
    df_error: f64,
    df_total: f64,
    ss_model: f64,
    ss_error: f64,
    ss_total: f64,
    ms_model: f64,
    ms_error: f64,
    f: f64,
    p: f64,
    root_mse: f64,
    mean: f64,
    cv: f64,
    r_square: f64,
    adj_r_square: f64,
    aliased: []const bool,
    biased: []const bool,
    dependencies: []const u8,
    estimates: []const f64,
    errors: []const f64,
    robust_errors: []const f64 = &.{},
    t: []const f64,
    probabilities: []const f64,
    tolerance: []const f64 = &.{},
    vif: []const f64 = &.{},
    restrictions: []const @import("reg_restrict.zig").Multiplier = &.{},
};
fn number(a: A, x: f64, comptime places: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{places}) ++ "}", .{x});
}
/// STAT-REG-001: the ANOVA F Value column is 7 wide in SAS 9.4 (runs: 975748,
/// 13381.5, 1349087, 1.215E7); a value whose two-decimal form does not fit is
/// shown in BEST7.
fn fValue(a: A, x: f64) ![]const u8 {
    const fixed = try number(a, x, 2);
    if (fixed.len <= 7) return fixed;
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, "best7."), " ");
}
fn statistic(a: A, x: f64) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    if (x == 0) return "0"; // STAT-REG-001: SAS 9.4 prints an exact zero as 0
    // SAS BESTD-style listing: five decimals at ordinary scales, integral
    // display for large sums, additional precision for very small estimates.
    if (@abs(x) >= 10000) return number(a, x, 0);
    if (x != 0 and @abs(x) < 0.001) return number(a, x, 8);
    return number(a, x, 5);
}
fn probability(a: A, p: f64) ![]const u8 {
    if (!std.math.isFinite(p)) return ".";
    if (p < 0.0001) return "<.0001";
    return number(a, p, 4);
}
pub fn render(a: A, out: *std.ArrayList(u8), spec: parse.Spec, model: parse.Model, read: usize, used: usize, r: Result) !void {
    try out.print(a, "\nThe REG Procedure\nModel: {s}\nDependent Variable: {s}", .{ model.label, spec.ds.columns.items[model.dependent].name });
    if (spec.ds.columns.items[model.dependent].label) |label| if (label.len > 0) {
        try out.print(a, " {s}", .{label});
    };
    if (r.restrictions.len > 0) try out.appendSlice(a, "\n\nNOTE: Restrictions have been applied to parameter estimates.");
    // STAT-REG-001: SAS prints no observation counts for TYPE=CORR/COV/SSCP input.
    if (spec.summary) try out.appendSlice(a, "\n") else try out.print(a, "\n\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ read, used });
    if (spec.freq != null) try out.print(a, "Sum of Frequencies Used {d}\n", .{r.n});
    if (spec.weight) |ci| try out.print(a, "\nWeight: {s}\n", .{spec.ds.columns.items[ci].name});
    try out.appendSlice(a, "\nAnalysis of Variance\n\nSum of Mean\nSource DF Squares Square F Value Pr > F\n\n");
    try out.print(a, "Model {s} {s} {s} {s} {s}\nError {s} {s} {s}\n{s} Total {s} {s}\n\n", .{ try number(a, r.df_model, 0), try statistic(a, r.ss_model), try statistic(a, r.ms_model), try fValue(a, r.f), try probability(a, r.p), try number(a, r.df_error, 0), try statistic(a, r.ss_error), try statistic(a, r.ms_error), if (model.intercept) @as([]const u8, "Corrected") else "Uncorrected", try number(a, r.df_total, 0), try statistic(a, r.ss_total) });
    try out.print(a, "Root MSE {s} R-Square {s}\nDependent Mean {s} Adj R-Sq {s}\nCoeff Var {s}\n", .{ try statistic(a, r.root_mse), try number(a, r.r_square, 4), try statistic(a, r.mean), try number(a, r.adj_r_square, 4), try statistic(a, r.cv) });
    if (r.dependencies.len > 0) try out.print(a, "\nNOTE: Model is not full rank. Least-squares solutions for the parameters are not unique. Some statistics will be misleading. A reported DF of 0 or B means that\n      the estimate is biased.\nNOTE: The following parameters have been set to 0, since the variables are a linear combination of other variables as shown.\n\n{s}\n", .{r.dependencies});
    try out.appendSlice(a, "\nParameter Estimates\n\nParameter Standard");
    if (model.vif) try out.appendSlice(a, " Variance");
    const labels = for (model.regressors) |ci| {
        if (spec.ds.columns.items[ci].label != null) break true;
    } else false;
    try out.appendSlice(a, if (labels) "\nVariable Label DF Estimate Error t Value Pr > |t|" else "\nVariable DF Estimate Error t Value Pr > |t|");
    if (r.robust_errors.len > 0) try out.appendSlice(a, " Heteroscedasticity Consistent Standard Error");
    if (model.tol) try out.appendSlice(a, " Tolerance");
    if (model.vif) try out.appendSlice(a, " Inflation");
    try out.appendSlice(a, "\n\n");
    for (r.estimates, 0..) |estimate, i| {
        const name = if (model.intercept and i == 0) "Intercept" else spec.ds.columns.items[model.regressors[i - @as(usize, if (model.intercept) 1 else 0)]].name;
        try out.print(a, "{s}", .{name});
        if (labels) {
            const label = if (model.intercept and i == 0) "Intercept" else spec.ds.columns.items[model.regressors[i - @as(usize, if (model.intercept) 1 else 0)]].label orelse "";
            try out.print(a, " {s}", .{label});
        }
        try out.print(a, " {s} {s} {s} {s} {s}", .{ if (r.aliased[i]) @as([]const u8, "0") else if (r.biased[i]) "B" else "1", if (r.aliased[i]) @as([]const u8, "0") else try statistic(a, estimate), try statistic(a, r.errors[i]), try number(a, r.t[i], 2), try probability(a, r.probabilities[i]) });
        if (r.robust_errors.len > 0) try out.print(a, " {s}", .{try statistic(a, r.robust_errors[i])});
        if (model.tol) try out.print(a, " {s}", .{try statistic(a, r.tolerance[i])});
        if (model.vif) try out.print(a, " {s}", .{if (model.intercept and i == 0) @as([]const u8, "0") else try statistic(a, r.vif[i])});
        try out.append(a, '\n');
    }
    for (r.restrictions) |restriction| {
        try out.print(a, "RESTRICT{s} -1 {s} {s} {s} {s}*", .{ if (labels) @as([]const u8, " ") else "", try statistic(a, restriction.estimate), try statistic(a, restriction.se), try number(a, restriction.t, 2), try probability(a, restriction.probability) });
        if (model.tol) try out.appendSlice(a, " .");
        if (model.vif) try out.appendSlice(a, " .");
        try out.append(a, '\n');
    }
    if (r.restrictions.len > 0) try out.appendSlice(a, "\n* Probability computed using beta distribution.\n");
}

pub fn observations(a: A, out: *std.ArrayList(u8), spec: parse.Spec, model: parse.Model, y: []const f64, fit: @import("reg_fit.zig").Fit) !void {
    // ponytail: currently the combined R CLM CLI listing only; other column
    // combinations fail visibly in the caller until their layouts are covered.
    try out.print(a, "\nThe REG Procedure\nModel: {s}\nDependent Variable: {s}\n\nOutput Statistics\n\nStd\nError\nDependent Predicted Mean Std Error Student\nObs Variable Value Predict {d}% CL Mean {d}% CL Predict Residual Residual Residual -2-1 0 1 2 Cook's D\n\n", .{ model.label, spec.ds.columns.items[model.dependent].name, 100 * (1 - model.alpha), 100 * (1 - model.alpha) });
    const critical = @import("reg_fit.zig").tCritical(model.alpha, fit.df_error);
    var sum: f64 = 0;
    var press: f64 = 0;
    for (y, fit.fitted, fit.residuals, fit.leverage, 0..) |dep, pred, res, h, i| {
        const sem = @sqrt(fit.mse * h);
        const sep = @sqrt(fit.mse * (1 + h));
        const ser = @sqrt(fit.mse * (1 - h));
        const student = res / ser;
        const cook = student * student * h / ((1 - h) * @as(f64, @floatFromInt(fit.rank)));
        sum += res;
        press += (res / (1 - h)) * (res / (1 - h));
        var chart = [_]u8{' '} ** 13;
        chart[6] = '|';
        const stars: usize = if (std.math.isFinite(student)) @intFromFloat(@min(6, @floor(@abs(student) * 2))) else 0;
        for (0..stars) |k| {
            if (student < 0) chart[5 - k] = '*' else chart[7 + k] = '*';
        }
        try out.print(a, "{d} {d:.2} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.3} {d:.3} |{s}| {d:.3}\n", .{ i + 1, dep, pred, sem, pred - critical * sem, pred + critical * sem, pred - critical * sep, pred + critical * sep, res, ser, student, chart, cook });
    }
    try out.print(a, "\nSum of Residuals {s}\nSum of Squared Residuals {s}\nPredicted Residual SS (PRESS) {s}\n", .{ std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = sum }, "best12."), " "), try statistic(a, fit.sse), try statistic(a, press) });
}

test {
    _ = @import("reg_orthogonality_tests.zig");
}
