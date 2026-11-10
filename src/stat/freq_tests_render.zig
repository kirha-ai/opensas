//! Rendering of typed FREQ results; no computation or table construction.
const std = @import("std");
const k = @import("freq_tests.zig");
const parse = @import("freq_tests_parse.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const Error = @import("../diag.zig").Error;
fn text(a: A, out: *Out, s: []const u8) Error!void {
    try out.appendSlice(a, s);
}
fn number(a: A, value: ?f64) Error![]const u8 {
    return if (value) |v| try std.fmt.allocPrint(a, "{d:.4}", .{v}) else ".";
}
fn probability(a: A, value: ?f64) Error![]const u8 {
    return if (value) |v| (if (v < 0.0001) "<.0001" else try number(a, v)) else ".";
}
fn pad(a: A, out: *Out, s: []const u8, width: usize, right: bool) Error!void {
    const n = width - @min(width, s.len);
    if (right) try out.appendNTimes(a, ' ', n);
    try text(a, out, s);
    if (!right) try out.appendNTimes(a, ' ', n);
}
fn pair(a: A, out: *Out, label: []const u8, value: ?f64, p: bool) Error!void {
    try pad(a, out, label, 25, false);
    try pad(a, out, if (p) try probability(a, value) else try number(a, value), 9, true);
    try text(a, out, "\n");
}
pub fn goodnessOfFit(a: A, out: *Out, result: k.GoodnessOfFit, opts: parse.Options) Error!void {
    const hypothesis: []const u8 = switch (opts.expected) {
        .equal => "Equal Proportions",
        .proportions, .proportion_dataset => "Specified Proportions",
        .frequencies, .frequency_dataset => "Specified Frequencies",
    };
    try text(a, out, try std.fmt.allocPrint(a, "\nChi-Square Test\nfor {s}\n\n", .{hypothesis}));
    try pair(a, out, "Chi-Square", result.pearson.statistic, false);
    try pair(a, out, "DF", result.pearson.df, false);
    try pair(a, out, "Pr > ChiSq", result.pearson.p, true);
    if (opts.lrchi) {
        try text(a, out, try std.fmt.allocPrint(a, "\nLikelihood Ratio Chi-Square Test\nfor {s}\n\n", .{hypothesis}));
        try pair(a, out, "Chi-Square", result.likelihood_ratio.statistic, false);
        try pair(a, out, "DF", result.likelihood_ratio.df, false);
        try pair(a, out, "Pr > ChiSq", result.likelihood_ratio.p, true);
    }
    if (result.sparse and opts.warn.display) try text(a, out, "\nWARNING: More than 20% of the cells have expected counts less than 5. Chi-Square may not be a valid test.\n");
}
fn chiRow(a: A, out: *Out, label: []const u8, result: k.Test) Error!void {
    try pad(a, out, label, 30, false);
    try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{result.df}), 4, true);
    try pad(a, out, try number(a, result.statistic), 12, true);
    try pad(a, out, try probability(a, result.p), 10, true);
    try text(a, out, "\n");
}
fn coefficient(a: A, out: *Out, label: []const u8, value: f64) Error!void {
    try pad(a, out, label, 34, false);
    try pad(a, out, try number(a, value), 12, true);
    try text(a, out, "\n");
}
pub fn contingency(a: A, out: *Out, result: k.ChiSquare, opts: parse.Options, first_cell: f64) Error!void {
    try text(a, out, "\nStatistic                     DF       Value      Prob\n------------------------------------------------------\n");
    try chiRow(a, out, "Chi-Square", result.pearson);
    try chiRow(a, out, "Likelihood Ratio Chi-Square", result.likelihood_ratio);
    if (result.continuity) |r| try chiRow(a, out, "Continuity Adj. Chi-Square", r);
    if (result.mantel_haenszel) |r| try chiRow(a, out, "Mantel-Haenszel Chi-Square", r);
    try coefficient(a, out, "Phi Coefficient", result.phi);
    try coefficient(a, out, "Contingency Coefficient", result.contingency);
    try coefficient(a, out, "Cramer's V", result.cramer_v);
    if (result.sparse and opts.warn.display) try text(a, out, "\nWARNING: More than 20% of the cells have expected counts less than 5. Chi-Square may not be a valid test.\n");
    if (result.fisher) |f| {
        try text(a, out, "\nFisher's Exact Test\n----------------------------------\n");
        try pair(a, out, "Cell (1,1) Frequency (F)", first_cell, false);
        try pair(a, out, "Left-sided Pr <= F", f.left, true);
        try pair(a, out, "Right-sided Pr >= F", f.right, true);
        try pair(a, out, "Table Probability (P)", f.probability, true);
        try pair(a, out, "Two-sided Pr <= P", f.two_sided, true);
    }
}
fn measureRow(a: A, out: *Out, label: []const u8, m: k.Measure, cl: bool) Error!void {
    try pad(a, out, label, 36, false);
    try pad(a, out, try number(a, m.estimate), 10, true);
    try pad(a, out, try number(a, m.ase), 10, true);
    if (cl) {
        try pad(a, out, try number(a, m.lower), 11, true);
        try pad(a, out, try number(a, m.upper), 11, true);
    }
    try text(a, out, "\n");
}
fn testMeasure(a: A, out: *Out, label: []const u8, m: k.Measure, alpha: f64, poly: bool, lr: ?k.Test) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\n{s}\n----------------------------------\n", .{label}));
    try pair(a, out, "Estimate", m.estimate, false);
    try pair(a, out, "ASE", m.ase, false);
    try pair(a, out, try std.fmt.allocPrint(a, "{d}% Lower Conf Limit", .{100 * (1 - alpha)}), m.lower, false);
    try pair(a, out, try std.fmt.allocPrint(a, "{d}% Upper Conf Limit", .{100 * (1 - alpha)}), m.upper, false);
    try text(a, out, try std.fmt.allocPrint(a, "\nTest of H0: {s} = 0\n\n", .{label}));
    if (!poly) try pair(a, out, "ASE under H0", m.null_se, false);
    try pair(a, out, "Z", m.z, false);
    try pair(a, out, if ((m.z orelse 0) > 0) "One-sided Pr > Z" else "One-sided Pr < Z", m.p_one, true);
    try pair(a, out, "Two-sided Pr > |Z|", m.p_two, true);
    if (poly) {
        try pair(a, out, "LR Chi-Square", if (lr) |v| v.statistic else null, false);
        try pair(a, out, "Pr > ChiSq", if (lr) |v| v.p else null, true);
    }
}
pub fn measures(a: A, out: *Out, ordinal: k.Association, nominal: k.Nominal, poly: ?k.Polychoric, two: bool, opts: parse.Options, tests: parse.Tests) Error!void {
    if (opts.cl) try text(a, out, try std.fmt.allocPrint(a, "\nStatistic                              Value       ASE     {d}% Confidence Limits\n", .{100 * (1 - opts.alpha)})) else try text(a, out, "\nStatistic                              Value       ASE\n");
    try text(a, out, "----------------------------------------------------------------------------\n");
    const names = [_][]const u8{ "Gamma", "Kendall's Tau-b", "Stuart's Tau-c", "Somers' D C|R", "Somers' D R|C", "Pearson Correlation", "Spearman Correlation" };
    const ms = [_]k.Measure{ ordinal.gamma, ordinal.tau_b, ordinal.tau_c, ordinal.somers_cr, ordinal.somers_rc, ordinal.pearson, ordinal.spearman };
    const selected = [_]bool{ tests.gamma, tests.tau_b, tests.tau_c, tests.somers_cr, tests.somers_rc, tests.pearson, tests.spearman };
    for (names, ms) |name, m| try measureRow(a, out, name, m, opts.cl);
    const poly_name = if (two) "Tetrachoric Correlation" else "Polychoric Correlation";
    if (poly) |p| try measureRow(a, out, poly_name, p.coefficient, opts.cl);
    const nominal_names = [_][]const u8{ "Lambda Asymmetric C|R", "Lambda Asymmetric R|C", "Lambda Symmetric", "Uncertainty Coefficient C|R", "Uncertainty Coefficient R|C", "Uncertainty Coefficient Symmetric" };
    const ns = [_]k.Measure{ nominal.lambda_cr, nominal.lambda_rc, nominal.lambda_symmetric, nominal.uncertainty_cr, nominal.uncertainty_rc, nominal.uncertainty_symmetric };
    for (nominal_names, ns) |name, m| try measureRow(a, out, name, m, opts.cl);
    for (names, ms, selected) |name, m, selected_test| if (selected_test) {
        try testMeasure(a, out, name, m, opts.alpha, false, null);
    };
    if (poly) |p| {
        if (tests.polychoric) try testMeasure(a, out, poly_name, p.coefficient, opts.alpha, true, p.likelihood_ratio);
        if (!p.converged) try text(a, out, "\nPolychoric correlation computations did not converge.\n");
    }
}
pub fn risks(a: A, out: *Out, r: k.Risks, alpha: f64) Error!void {
    try text(a, out, try std.fmt.allocPrint(a, "\nOdds Ratio and Relative Risks\n\nStatistic                        Value       {d}% Confidence Limits\n------------------------------------------------------------------\n", .{100 * (1 - alpha)}));
    const names = [_][]const u8{ "Odds Ratio", "Relative Risk (Column 1)", "Relative Risk (Column 2)" };
    const rs = [_]k.Risk{ r.odds_ratio, r.column1, r.column2 };
    var missing = false;
    for (names, rs) |name, result| {
        if (result.estimate == null) {
            missing = true;
            continue;
        }
        try pad(a, out, name, 28, false);
        try pad(a, out, try number(a, result.estimate), 10, true);
        try pad(a, out, try number(a, result.lower), 14, true);
        try pad(a, out, try number(a, result.upper), 14, true);
        try text(a, out, "\n");
    }
    if (missing) try text(a, out, "\nOne or more statistics not computed -- zero cell.\n");
}

test "FEAT-freq-tests renderer retains automatic Fisher and requested TEST output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = k.CountMatrix{ .rows = 2, .cols = 2, .counts = &.{ 1, 9, 11, 3 } };
    var out: Out = .empty;
    try contingency(a, &out, try k.contingency(a, m, null), .{ .chisq = true }, 1);
    try measures(a, &out, try k.association(a, m, 0.05), try k.nominal(a, m, 0.05), try k.polychoric(a, m, .{}), true, .{ .measures = true, .cl = true }, .{ .gamma = true, .polychoric = true });
    try risks(a, &out, try k.risks(m.counts, 0.05), 0.05);
    for ([_][]const u8{ "Fisher's Exact Test", "Two-sided Pr <= P", "ASE under H0", "Tetrachoric Correlation", "LR Chi-Square", "Uncertainty Coefficient Symmetric", "Relative Risk (Column 2)" }) |needle| try std.testing.expect(std.mem.indexOf(u8, out.items, needle) != null);
}
