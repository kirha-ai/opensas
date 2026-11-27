//! Exact scalar STRATA inference. EXACTONLY never invokes asymptotic fitting,
//! including at a separated boundary where the finite MUE is required.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const l = @import("logistic.zig");
const conditional = @import("logistic_conditional.zig");
const conditional_proc = @import("logistic_conditional_proc.zig");
const exact = @import("logistic_exact.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;
fn num(a: A, value: f64, specification: []const u8) ![]const u8 {
    if (std.math.isInf(value)) return if (value > 0) "Infinity" else "-Infinity";
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, specification), " ");
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: l.Spec) diag.Error!void {
    const request = s.exact_request orelse return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: EXACTONLY requires an EXACT statement", .{});
    if (s.strata.len == 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: exact analysis without STRATA is not implemented", .{});
    const prepared = try conditional_proc.prepare(cx, s);
    const d = prepared.design;
    if (d.p != 1 or d.effects.len != 1 or d.effects[0].variables.len != 1 or d.effects[0].column != request.variable) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: exact nuisance-covariate and multivariate conditioning is not implemented", .{});
    const a = cx.arena;
    const strata = try a.alloc(conditional.Stratum, prepared.groups.len);
    for (prepared.groups, strata) |group, *stratum| stratum.* = .{ .rows = group.rows, .events = group.events };
    const distribution = exact.build(a, d.x, d.y, strata, s.exact_method) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: exact analysis requires bounded integer sufficient statistics and finite count/state resources", .{});
    };
    if (distribution.points.len < 2) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: degenerate exact conditional inference is not implemented", .{});
    const tests = try exact.tests(distribution, request.delta1, request.delta2);
    const alpha = request.alpha orelse s.alpha;
    const inference = if (request.estimate != .none) exact.infer(distribution, alpha, request.midp_interval, request.delta1, request.one_sided) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: exact conditional estimate/interval did not attain its finite probability target", .{});
    } else null;
    if (s.noprint) return;
    if (s.exact_only) try conditional_proc.renderHeader(a, out, s, prepared, false) else try conditional_proc.run(cx, out, s);
    const name = prepared.data.columns.items[request.variable].name;
    try out.appendSlice(a, "\nExact Conditional Analysis\n\nExact Conditional Tests\n\n--- p-Value ---\nEffect Test Statistic Exact Mid\n\n");
    try out.print(a, "{s} Score {s} {s} {s}\nProbability {s} {s} {s}\n", .{ name, try num(a, tests.score, "10.4"), try num(a, tests.score_exact, "pvalue6.4"), try num(a, tests.score_mid, "pvalue6.4"), try num(a, tests.observed_probability, "10.4"), try num(a, tests.probability_exact, "pvalue6.4"), try num(a, tests.probability_mid, "pvalue6.4") });
    if (inference) |result| {
        if (request.estimate == .parm or request.estimate == .both) {
            try out.print(a, "\nExact Parameter Estimates\n\nStandard {s}% Confidence\nParameter Estimate Error Limits p-Value\n\n", .{try num(a, 100 * (1 - alpha), "best8.")});
            try out.print(a, "{s} {s}{s} {s} {s} {s} {s}\n", .{ name, try num(a, result.estimate, "10.4"), if (result.median_unbiased) " *" else "", try num(a, result.standard_error, "10.4"), try num(a, result.lower, "10.4"), try num(a, result.upper, "10.4"), try num(a, result.p_value, "pvalue6.4") });
            if (result.median_unbiased) try out.appendSlice(a, "Note: * indicates a median unbiased estimate and a one-sided p-value.\n");
        }
        if (request.estimate == .odds or request.estimate == .both) {
            try out.print(a, "\nExact Odds Ratios\n\n{s}% Confidence\nParameter Estimate Limits p-Value\n\n", .{try num(a, 100 * (1 - alpha), "best8.")});
            try out.print(a, "{s} {s}{s} {s} {s} {s}\n", .{ name, try num(a, @exp(result.estimate), "10.3"), if (result.median_unbiased) " *" else "", try num(a, @exp(result.lower), "10.3"), try num(a, @exp(result.upper), "10.3"), try num(a, result.p_value, "pvalue6.4") });
            if (result.median_unbiased and request.estimate == .odds) try out.appendSlice(a, "Note: * indicates a median unbiased estimate and a one-sided p-value.\n");
        }
    }
}
