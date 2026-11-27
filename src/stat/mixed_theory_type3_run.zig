//! METHOD=TYPE3 uses moment covariance estimates in GLS, not optimized REML.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const declarations = @import("mixed_parse.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const input = @import("mixed_input.zig");
const math = @import("mixed_fit.zig");
const theory = @import("mixed_theory_type3.zig");
const render = @import("mixed_render.zig");
const format = @import("../format.zig");
fn decimal(a: std.mem.Allocator, x: f64) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:.4}", .{x});
    return std.mem.trimEnd(u8, std.mem.trimEnd(u8, text, "0"), ".");
}
fn probability(a: std.mem.Allocator, p: f64) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = p }, "pvalue6.4"), " ");
}
fn dfText(a: std.mem.Allocator, df: f64) ![]const u8 {
    return if (df == @floor(df)) std.fmt.allocPrint(a, "{d:.0}", .{df}) else std.fmt.allocPrint(a, "{d:.3}", .{df});
}
fn anova(a: std.mem.Allocator, out: *std.ArrayList(u8), moments: theory.Result) !void {
    try out.appendSlice(a, "Type 3 Analysis of Variance\n\nSum of Error\nSource DF Squares Mean Square Expected Mean Square Error Term DF F Value Pr > F\n\n");
    const interaction = moments.rows[moments.anova.interaction].name;
    const main = moments.rows[moments.anova.random_main].name;
    for (moments.rows, 0..) |row, i| {
        const test_value = row.anova_test;
        try out.print(a, "{s} {d} {d:.6} {d:.6} Var(Residual) + {s} Var({s}) ", .{ row.name, row.df, row.ss, row.ms, try decimal(a, moments.anova.coefficients[i][1]), interaction });
        if (i == moments.anova.interaction) try out.appendSlice(a, "MS(Residual) ") else if (test_value.interaction_weight == 1) try out.print(a, "MS({s}) ", .{interaction}) else try out.print(a, "{d:.4} MS({s}) ", .{ test_value.interaction_weight, interaction });
        try out.print(a, "{s} {d:.2} {s}\n", .{ try dfText(a, test_value.denominator_df), test_value.f_value, try probability(a, test_value.p_value) });
        if (i == moments.anova.fixed) try out.print(a, "+ Q({s}) ", .{row.name}) else if (i == moments.anova.random_main) try out.print(a, "+ {s} Var({s}) ", .{ try decimal(a, moments.anova.coefficients[i][0]), main });
        if (i != moments.anova.interaction and test_value.error_weight != 0) try out.print(a, "+ {d:.4} MS(Residual)", .{test_value.error_weight});
        if (i != moments.anova.interaction) try out.append(a, '\n');
    }
    try out.print(a, "Residual {d} {d:.6} {d:.6} Var(Residual) . . . .\n\n", .{ moments.residual_df, moments.residual_ss, moments.residual_ms });
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: declarations.Spec, m: model.Spec, r: random.Spec, group: input.Group, x: fixed.Design, z: random.Design, components: []const math.Component, names: []const []const u8) diag.Error!void {
    return runRouted(cx, out, s, m, r, group, x, z, components, names, null);
}
pub fn runRouted(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: declarations.Spec, m: model.Spec, r: random.Spec, group: input.Group, x: fixed.Design, z: random.Design, components: []const math.Component, names: []const []const u8, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    const moments = try theory.estimate(cx, m, r, z, group.selected);
    const gls = math.knownCovariance(cx.arena, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components, .has_intercept = m.matrix.intercept, .singular = m.options.singular }, moments.variances) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED METHOD=TYPE3: GLS boundary is not implemented ({t})", .{err});
    var tests: std.ArrayList(render.NamedTest) = .empty;
    if (!m.options.notest) for (m.matrix.effects, 0..) |_, ei| {
        const contrast = try fixed.type3(cx, m, x, ei);
        const df = if (m.options.ddfm == .residual) gls.df_error else try random.containmentDF(cx, r, x.matrix, z, ei, x.weights, m.options.singular);
        if (df == 0) return proc.failGap(cx.diags, s.line, "PROC MIXED METHOD=TYPE3: zero denominator DF is not implemented", .{});
        const result = math.testContrast(cx.arena, gls, contrast.coefficients, contrast.rows, df) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED METHOD=TYPE3: nonestimable GLS test ({t})", .{err});
        try tests.append(cx.arena, .{ .name = contrast.name, .num_df = result.num_df, .den_df = result.den_df, .f = result.f, .p = result.p });
    };
    if (s.roles.by.len > 0) try @import("by_groups.zig").appendLine(cx.arena, out, s.input.ds, group.raw.observations[0].cells, s.roles.by);
    try @import("mixed_info.zig").renderRouted(cx.arena, out, s, m, group, x, z, route);
    var start = out.items.len;
    try anova(cx.arena, out, moments);
    if (route) |rr| try rr.finish(cx.arena, out, start, "Type3");
    start = out.items.len;
    try out.appendSlice(cx.arena, "Covariance Parameter Estimates\n\nCov Parm Estimate\n");
    for (names, moments.variances) |name, value| try out.print(cx.arena, "{s} {d:.4}\n", .{ name, value });
    if (route) |rr| try rr.finish(cx.arena, out, start, "CovParms");
    start = out.items.len;
    var count: f64 = 0;
    for (moments.variances) |v| if (v > 0) {
        count += 1;
    };
    // S154 physical p.6630: REML IC uses covariance parameter count, n*=N-rankX
    // for AICC, and effective subjects (first random-effect levels here) for BIC.
    const nstar = @max(@as(f64, @floatFromInt(gls.n - gls.rank)), count + 2);
    const aic = gls.minus2reml + 2 * count;
    const aicc = aic + 2 * count * (count + 1) / (nstar - count - 1);
    const neff = @as(f64, @floatFromInt(z.first_effect_levels));
    const bic = gls.minus2reml + count * (if (neff > 0) @log(neff) else 0);
    try out.print(cx.arena, "\nFit Statistics\n\n-2 Res Log Likelihood {d:.1}\nAIC (Smaller is Better) {d:.1}\nAICC (Smaller is Better) {d:.1}\nBIC (Smaller is Better) {d:.1}\n", .{ gls.minus2reml, aic, aicc, bic });
    if (route) |rr| try rr.finish(cx.arena, out, start, "FitStatistics");
    if (!m.options.notest) {
        start = out.items.len;
        try out.appendSlice(cx.arena, "\nType 3 Tests of Fixed Effects\n\nNum Den\nEffect DF DF F Value Pr > F\n");
        for (tests.items) |row| try out.print(cx.arena, "{s} {d} {d} {d:.2} {s}\n", .{ row.name, row.num_df, row.den_df, row.f, try probability(cx.arena, row.p) });
    }
    if (!m.options.notest) if (route) |rr| try rr.finish(cx.arena, out, start, "Tests3");
    const typed = math.Fit{ .n = gls.n, .p = gls.p, .rank = gls.rank, .independent = gls.independent, .coefficients = gls.coefficients, .covariance = gls.covariance, .alias_coefficients = gls.alias_coefficients, .variances = try cx.arena.dupe(f64, moments.variances), .residual_variance = moments.variances[moments.variances.len - 1], .minus2loglik = gls.minus2reml, .aic = aic, .aicc = aicc, .bic = bic, .iterations = &.{}, .converged = false, .status = .evaluated, .method = .reml, .df_error = gls.df_error };
    try @import("mixed_ods.zig").publish(cx, s, m, group, x, z, r, typed, names, tests.items, null, null);
    const requests = try @import("mixed_contrasts.zig").parse(cx, m, z, s.statements);
    try @import("mixed_contrasts.zig").publishRouted(cx, out, m, r, x, z, gls, moments.variances, requests, route);
}
