//! STRATA adapter and conditional-only output. No unconditional fit, profile
//! likelihood or association statistic is used in this analysis path.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const l = @import("logistic.zig");
const design = @import("logistic_design.zig");
const levels = @import("class_levels.zig");
const conditional = @import("logistic_conditional.zig");
const kernel = @import("logistic_fit.zig");
const odds = @import("logistic_odds.zig");
const lists = @import("variable_lists.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;
pub const Group = struct { keys: []const usize, rows: []const usize, events: usize };
pub const Analysis = struct { data: @import("../dataset.zig").Dataset, design: design.Design, groups: []const Group, maps: []const levels.Levels, fit: conditional.Fit, read: usize, informative: usize };
pub const Prepared = struct { data: @import("../dataset.zig").Dataset, design: design.Design, groups: []const Group, maps: []const levels.Levels, read: usize, informative: usize };
fn num(a: A, value: f64, specification: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, specification), " ");
}
pub fn prepare(cx: proc.ProcCtx, s: l.Spec) diag.Error!Prepared {
    const a = cx.arena;
    if (s.model.weight != null or s.link_specified or s.nofit or s.ctable or s.lackfit != null or s.scale != .unspecified or s.roc_plot or s.roc_models.len > 0 or s.roc_contrast != null or (s.clodds != null and s.clodds.? != .wald)) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: requested statement or MODEL option is not available with STRATA", .{});
    if (s.model.classes.len > 0 or s.trials != null or s.by_columns.len > 0 or s.convergence_specified or s.maxiter_specified or s.fit_options.ridging != .relative or s.odds_requests.len > 0 or s.units_present or s.clodds != null) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: this conditional analysis adapter/option is not implemented", .{});
    const ds = s.input.ds;
    const maps = try a.alloc(levels.Levels, s.strata.len);
    for (s.strata, maps) |variable, *map| map.* = try levels.build(a, ds, ds.rows.items, variable.column, .{ .missing = if (s.strata_missing or variable.missing) .include else .exclude });
    var selected = ds.*;
    selected.rows = .empty;
    var origins: std.ArrayList(usize) = .empty;
    for (ds.rows.items, 0..) |row, i| {
        var valid = true;
        for (maps) |map| if (map.row_to_level[i] == null) {
            valid = false;
        };
        if (valid) {
            try selected.rows.append(a, row);
            try origins.append(a, i);
        }
    }
    if (selected.rows.items.len == 0) return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: no usable STRATA observations", .{});
    var model = s.model;
    model.allow_ordinal = true;
    const d = design.build(a, &selected, model, cx.diags) catch |err| {
        if (err == error.OutOfMemory or cx.diags.hasErrors()) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: no usable conditional model data", .{});
    };
    if (d.response.levels.len != 2) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: STRATA requires a binary response", .{});
    for (d.frequencies) |frequency| if (frequency != 1) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: nonunit conditional FREQ replication is not implemented", .{});
    if (d.p <= 1) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: intercept-only conditional output is not implemented", .{});
    if (s.strata_check) {
        const zero = try a.alloc(f64, d.n);
        @memset(zero, 0);
        var check = try @import("reg_fit.zig").fit(a, d.x, zero, d.n, d.p, null);
        defer check.deinit(a);
        if (check.rank != d.p) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: conditional dependent-covariate removal is not implemented", .{});
    }
    var groups: std.ArrayList(Group) = .empty;
    var group_rows: std.ArrayList(std.ArrayList(usize)) = .empty;
    for (d.source_rows, d.y, 0..) |source, y, i| {
        const raw = origins.items[source];
        const key = try a.alloc(usize, maps.len);
        for (maps, key) |map, *value| value.* = map.row_to_level[raw].?;
        var found: ?usize = null;
        for (groups.items, 0..) |group, index| if (std.mem.eql(usize, group.keys, key)) {
            found = index;
            break;
        };
        const index = found orelse blk: {
            try groups.append(a, .{ .keys = key, .rows = &.{}, .events = 0 });
            try group_rows.append(a, .empty);
            break :blk groups.items.len - 1;
        };
        if (group_rows.items[index].items.len >= 4096) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: conditional stratum exceeds the exact DP resource limit", .{});
        try group_rows.items[index].append(a, i);
        if (y == 1) groups.items[index].events += 1;
    }
    for (groups.items, group_rows.items) |*group, rows| group.rows = rows.items;
    const Sort = struct {
        fn less(_: void, left: Group, right: Group) bool {
            for (left.keys, right.keys) |x, y| {
                if (x != y) return x < y;
            }
            return false;
        }
    };
    std.mem.sort(Group, groups.items, {}, Sort.less);
    var informative: usize = 0;
    for (groups.items) |group| {
        if (group.events > 0 and group.events < group.rows.len) informative += group.rows.len;
    }
    if (informative == 0) return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: no informative strata contain both outcomes", .{});
    const p = d.p - 1;
    const x = try a.alloc(f64, d.n * p);
    for (0..d.n) |i| @memcpy(x[i * p ..][0..p], d.x[i * d.p + 1 ..][0..p]);
    var conditional_design = d;
    conditional_design.x = x;
    conditional_design.p = p;
    conditional_design.parameters = d.parameters[1..];
    const effects = try a.dupe(design.Effect, d.effects);
    for (effects) |*effect| effect.start -= 1;
    conditional_design.effects = effects;
    return .{ .data = selected, .design = conditional_design, .groups = groups.items, .maps = maps, .read = ds.rows.items.len, .informative = informative };
}
pub fn analyze(cx: proc.ProcCtx, s: l.Spec) diag.Error!Analysis {
    const prepared = try prepare(cx, s);
    const a = cx.arena;
    const strata = try a.alloc(conditional.Stratum, prepared.groups.len);
    for (prepared.groups, strata) |group, *stratum| stratum.* = .{ .rows = group.rows, .events = group.events };
    const fit = conditional.fit(a, prepared.design.x, prepared.design.y, prepared.design.p, strata, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: conditional likelihood is singular, unbounded, or exceeds the exact DP resource limit", .{});
    };
    if (fit.status != .converged) try cx.diags.warnStatus(0, "Conditional logistic optimization did not converge; results use the last iterate", .{});
    return .{ .data = prepared.data, .design = prepared.design, .groups = prepared.groups, .maps = prepared.maps, .fit = fit, .read = prepared.read, .informative = prepared.informative };
}
fn rowTest(a: A, out: *std.ArrayList(u8), label: []const u8, q: f64, df: usize) !void {
    try out.print(a, "{s} {s} {d} {s}\n", .{ label, try num(a, q, "10.4"), df, try num(a, kernel.chiTail(q, df), "pvalue6.4") });
}
pub fn renderHeader(a: A, out: *std.ArrayList(u8), s: l.Spec, result: anytype, optimization: bool) diag.Error!void {
    const d = result.design;
    const ds = s.input.ds;
    const response = ds.columns.items[s.model.response].name;
    try out.print(a, "The LOGISTIC Procedure\n\nConditional Analysis\n\nModel Information\n\nData Set {s}\nResponse Variable {s}\nNumber of Response Levels 2\nNumber of Strata {d}\n", .{ try lists.datasetName(a, ds), response, result.groups.len });
    if (s.model.frequency) |column| try out.print(a, "Frequency Variable {s}\n", .{ds.columns.items[column].name});
    try out.appendSlice(a, "Model binary logit\n");
    if (optimization) try out.appendSlice(a, "Optimization Technique Newton-Raphson ridge\n");
    try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\nNumber of Observations Informative {d}\n\nResponse Profile\n\nOrdered Total\nValue {s} Frequency\n\n", .{ result.read, d.n, result.informative, response });
    for (d.response.levels, 0..) |level, i| try out.print(a, "{d} {s} {s}\n", .{ i + 1, level.label, try num(a, level.frequency, "best12.") });
    try out.print(a, "\nProbability modeled is {s}={s}.\n\n", .{ response, d.response.levels[d.event_index].label });
    if (s.strata_summary) {
        const Pattern = struct { first: usize, second: usize, count: usize = 0, frequency: usize = 0 };
        var patterns: std.ArrayList(Pattern) = .empty;
        for (result.groups) |group| {
            const first = if (d.event_index == 0) group.events else group.rows.len - group.events;
            const second = group.rows.len - first;
            var index: ?usize = null;
            for (patterns.items, 0..) |pattern, j| if (pattern.first == first and pattern.second == second) {
                index = j;
                break;
            };
            const j = index orelse blk: {
                try patterns.append(a, .{ .first = first, .second = second });
                break :blk patterns.items.len - 1;
            };
            patterns.items[j].count += 1;
            patterns.items[j].frequency += group.rows.len;
        }
        const Sort = struct {
            fn less(_: void, x: Pattern, y: Pattern) bool {
                return x.first < y.first or (x.first == y.first and x.second < y.second);
            }
        };
        std.mem.sort(Pattern, patterns.items, {}, Sort.less);
        try out.print(a, "Strata Summary\n\n{s}\nResponse ------- Number of\nPattern {s} {s} Strata Frequency\n\n", .{ response, d.response.levels[0].label, d.response.levels[1].label });
        for (patterns.items, 0..) |pattern, i| try out.print(a, "{d} {d} {d} {d} {d}\n", .{ i + 1, pattern.first, pattern.second, pattern.count, pattern.frequency });
    }
    if (s.strata_info) {
        try out.appendSlice(a, "\nStrata Information\n\nStratum");
        for (s.strata) |variable| try out.print(a, " {s}", .{ds.columns.items[variable.column].name});
        try out.appendSlice(a, " Events Nonevents Frequency\n\n");
        for (result.groups, 0..) |group, i| {
            try out.print(a, "{d}", .{i + 1});
            for (result.maps, group.keys) |map, key| try out.print(a, " {s}", .{map.levels[key].label});
            try out.print(a, " {d} {d} {d}\n", .{ group.events, group.rows.len - group.events, group.rows.len });
        }
    }
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: l.Spec) diag.Error!void {
    const result = try analyze(cx, s);
    if (s.noprint) return;
    const a = cx.arena;
    const d = result.design;
    const fit = result.fit;
    try renderHeader(a, out, s, result, true);
    try out.appendSlice(a, "\nNewton-Raphson Ridge Optimization\n\nWithout Parameter Scaling\n\n");
    if (fit.status == .converged) try out.appendSlice(a, "Convergence criterion (GCONV=1E-8) satisfied.\n\n") else try out.appendSlice(a, "Conditional optimization terminated without convergence.\n\n");
    try out.appendSlice(a, "Model Fit Statistics\n\nWithout With\nCriterion Covariates Covariates\n\n");
    const null_deviance = -2 * fit.null_log_likelihood;
    const deviance = -2 * fit.log_likelihood;
    const p: f64 = @floatFromInt(d.p);
    for ([_][]const u8{ "AIC", "SC", "-2 Log L" }, [_]f64{ deviance + 2 * p, deviance + p * @log(@as(f64, @floatFromInt(result.informative))), deviance }) |label, value| try out.print(a, "{s} {s} {s}\n", .{ label, try num(a, null_deviance, "10.3"), try num(a, value, "10.3") });
    try out.appendSlice(a, "\nTesting Global Null Hypothesis: BETA=0\n\nTest Chi-Square DF Pr > ChiSq\n\n");
    try rowTest(a, out, "Likelihood Ratio", @max(0, 2 * (fit.log_likelihood - fit.null_log_likelihood)), d.p);
    try rowTest(a, out, "Score", fit.score_test, d.p);
    try rowTest(a, out, "Wald", try kernel.wald(a, fit.covariance, fit.coefficients), d.p);
    try out.appendSlice(a, "\nAnalysis of Conditional Maximum Likelihood Estimates\n\nStandard Wald\nParameter DF Estimate Error Chi-Square Pr > ChiSq\n\n");
    for (d.parameters, 0..) |parameter, j| {
        const variance = fit.covariance[j * d.p + j];
        const statistic = fit.coefficients[j] * fit.coefficients[j] / variance;
        try out.print(a, "{s} {s} 1 {s} {s} {s} {s}\n", .{ parameter.name, parameter.level orelse "", try num(a, fit.coefficients[j], "10.4"), try num(a, @sqrt(variance), "10.4"), try num(a, statistic, "10.4"), try num(a, kernel.chiTail(statistic, 1), "pvalue6.4") });
    }
    // Reuse only algebraic Wald contrasts of the actual conditional estimate
    // and covariance. No unconditional fitting/probability/profile is invoked.
    const algebra: kernel.Fit = .{ .coefficients = fit.coefficients, .covariance = fit.covariance, .probabilities = &.{}, .log_likelihood = fit.log_likelihood, .null_log_likelihood = fit.null_log_likelihood, .score_test = fit.score_test, .iterations = fit.iterations };
    var rows: std.ArrayList(@import("logistic_plots.zig").Row) = .empty;
    for (d.effects) |effect| {
        var interacting = effect.variables.len != 1;
        for (d.effects) |other| if (other.variables.len > 1 and std.mem.indexOfScalar(usize, other.variables, effect.column) != null) {
            interacting = true;
        };
        if (interacting) continue;
        const contrasts = try odds.contrasts(a, &result.data, d, d.p, .{ .variable = effect.column, .reference_only = true }, &.{1});
        try rows.appendSlice(a, try odds.wald(a, algebra, contrasts, s.alpha));
    }
    if (rows.items.len > 0 and !s.no_odds_ratio) {
        try out.print(a, "\nOdds Ratio Estimates\n\nPoint {s}% Wald\nEffect Estimate Confidence Limits\n\n", .{try num(a, 100 * (1 - s.alpha), "best8.")});
        for (rows.items) |row| try out.print(a, "{s} {s} {s} {s}\n", .{ row.label, try num(a, @exp(row.log_estimate), "10.3"), try num(a, @exp(row.log_lower), "10.3"), try num(a, @exp(row.log_upper), "10.3") });
    }
}
