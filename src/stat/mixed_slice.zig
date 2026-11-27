//! MIXED adapter for the shared SLICE statement and actual fitted L covariance.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const coded = @import("design_matrix.zig");
const syntax = @import("slice_parse.zig");
const kernel = @import("lsmeans_slice.zig");
const means = @import("mixed_lsmeans.zig");
const linear = @import("mixed_contrasts_kernel.zig");
const fmt = @import("../format.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { effect: usize, spec: syntax.Spec };
pub fn parse(cx: proc.ProcCtx, m: model.Spec, statements: anytype) diag.Error![]const Request {
    var requests: std.ArrayList(Request) = .empty;
    for (statements) |statement| if (statement.kind == .slice) {
        const spec = try syntax.parse(cx, "MIXED", statement.tokens, statement.line);
        var effects: std.ArrayList(coded.Effect) = .empty;
        try model.effects(cx, m.source, spec.effect, &effects);
        if (effects.items.len != 1) return cx.diags.fail(error.ParseError, statement.line, "SLICE requires exactly one MODEL interaction", .{});
        const target = try coded.normalize(cx.arena, m.source, m.matrix.classes, effects.items[0]);
        if (target.continuous.len > 0 or target.crossed.len + target.nested.len < 2) return cx.diags.fail(error.ParseError, statement.line, "SLICE requires an interaction of at least two CLASS variables", .{});
        if (target.nested.len > 0) return proc.failGap(cx.diags, statement.line, "SLICE: nested interaction population margins are not implemented", .{});
        var found: ?usize = null;
        for (m.matrix.effects, 0..) |effect, i| {
            const normalized = try coded.normalize(cx.arena, m.source, m.matrix.classes, effect);
            if (eq(normalized.name, target.name)) {
                found = i;
                break;
            }
        }
        const index = found orelse return cx.diags.fail(error.ParseError, statement.line, "SLICE effect is not in MODEL", .{});
        for (spec.rules) |rule| for (rule.factors) |name| {
            const ci = m.source.indexOf(name) orelse return cx.diags.fail(error.ParseError, statement.line, "SLICEBY variable {s} not found", .{name});
            if (std.mem.indexOfScalar(usize, target.crossed, ci) == null) return cx.diags.fail(error.ParseError, statement.line, "SLICEBY must be a CLASS subset of the sliced effect", .{});
        };
        try requests.append(cx.arena, .{ .effect = index, .spec = spec });
    };
    return requests.items;
}
fn levelText(m: model.Spec, x: fixed.Design, c: usize, value: usize) []const u8 {
    const label = x.matrix.classes[c].map.levels[value].label;
    return if (m.source.columns.items[x.matrix.classes[c].column].type == .num) std.mem.trim(u8, label, " ") else std.mem.trimEnd(u8, label, " ");
}
fn number(a: A, v: ?f64, format: []const u8) ![]const u8 {
    return if (v) |value| std.mem.trim(u8, try fmt.apply(a, .{ .num = value }, format), " ") else ".";
}
fn rowLevels(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, x: fixed.Design, row: kernel.Row, classes: []const usize) !void {
    for (classes) |c| try out.print(cx.arena, " {s}", .{levelText(m, x, c, row.levels[c].?)});
}
pub fn publishRouted(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, requests: []const Request, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    const a = cx.arena;
    const joint = linear.Joint{ .p = x.matrix.p, .q = 0, .coefficients = fitted.coefficients, .covariance = fitted.covariance, .aliases = fitted.alias_coefficients };
    for (requests) |request| {
        const spec = request.spec;
        const options = spec.options;
        const effect = try coded.normalize(a, m.source, m.matrix.classes, m.matrix.effects[request.effect]);
        const source_rows = try means.coefficients(cx, m, x, request.effect);
        const rows = try a.alloc(kernel.Row, source_rows.len);
        for (source_rows, rows) |source, *row| row.* = .{ .levels = source.levels, .coefficients = source.l };
        var target: std.ArrayList(usize) = .empty;
        var expected: usize = 1;
        for (x.matrix.classes, 0..) |class, c| if (std.mem.indexOfScalar(usize, effect.crossed, class.column) != null) {
            try target.append(a, c);
            expected = std.math.mul(usize, expected, class.map.levels.len) catch return error.OutOfMemory;
        };
        if (rows.len != expected) return proc.failGap(cx.diags, spec.line, "SLICE: missing CLASS-cell population margins are not implemented; no cells are silently dropped", .{});
        var rules: std.ArrayList(syntax.Rule) = .empty;
        try rules.appendSlice(a, spec.rules);
        if (rules.items.len == 0) for (target.items) |c| {
            const names = try a.alloc([]const u8, 1);
            names[0] = m.source.columns.items[x.matrix.classes[c].column].name;
            try rules.append(a, .{ .factors = names });
        };
        const df: f64 = if (options.df) |v| v else if (m.options.ddfm == .residual or z.components.len == 0) @floatFromInt(fitted.df_error) else @floatFromInt(try random.containmentDF(cx, r, x.matrix, z, request.effect, x.weights, m.options.singular));
        if (!(df > 0)) return proc.failGap(cx.diags, spec.line, "SLICE: denominator degrees of freedom are unavailable", .{});
        for (rules.items) |rule| {
            const classes = try a.alloc(usize, rule.factors.len);
            for (rule.factors, classes) |name, *dest| {
                const ci = m.source.indexOf(name).?;
                dest.* = for (x.matrix.classes, 0..) |class, k| {
                    if (class.column == ci) break k;
                } else return error.ExecError;
            }
            for (classes, 0..) |c, i| if (std.mem.indexOfScalar(usize, classes[0..i], c) != null) return cx.diags.fail(error.ParseError, spec.line, "SLICEBY repeats a CLASS variable", .{});
            if (rule.values.len > 0 and classes.len != 1) return proc.failGap(cx.diags, spec.line, "SLICE: formatted selectors for joint partition effects are not independently verified", .{});
            const parts = kernel.partitions(a, rows, classes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "SLICE: invalid population partition ({t})", .{err});
            var selected: usize = 0;
            for (parts) |partition| {
                if (rule.values.len > 0) {
                    const actual = levelText(m, x, classes[0], partition.levels[0]);
                    const matches = for (rule.values) |value| {
                        if (std.mem.eql(u8, actual, std.mem.trimEnd(u8, value, " "))) break true;
                    } else false;
                    if (!matches) continue;
                }
                selected += 1;
                var label: std.ArrayList(u8) = .empty;
                for (partition.classes, partition.levels, 0..) |c, level, i| {
                    if (i > 0) try label.append(a, ' ');
                    try label.print(a, "{s} {s}", .{ m.source.columns.items[x.matrix.classes[c].column].name, levelText(m, x, c, level) });
                }
                var varying: std.ArrayList(usize) = .empty;
                for (target.items) |c| if (std.mem.indexOfScalar(usize, classes, c) == null) {
                    try varying.append(a, c);
                };
                const result = kernel.compute(a, joint, rows, partition, df, options.alpha, options.singular, m.options.singular, options.diff, options.adjust, options.cl) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "SLICE inference boundary is not implemented ({t})", .{err});
                if (cx.capture) |capture| {
                    if (!options.nof and capture.wants("SliceTests")) return proc.failGap(cx.diags, spec.line, "SLICE: SliceTests typed metadata is not independently verified", .{});
                    if (options.means and capture.wants("Slices")) return proc.failGap(cx.diags, spec.line, "SLICE: Slices typed metadata is not independently verified", .{});
                    if (result.differences.len > 0 and capture.wants("SliceDiffs")) return proc.failGap(cx.diags, spec.line, "SLICE: SliceDiffs typed metadata is not independently verified", .{});
                }
                if (!options.nof) {
                    const start = out.items.len;
                    try out.print(a, "\nF Test for {s} Least Squares Means Slice\n\nNum Den\nSlice DF DF F Value Pr > F\n\n{s} ", .{ effect.name, label.items });
                    const test_value = result.test_result;
                    if (!test_value.estimable) try out.appendSlice(a, ". . . .\n") else try out.print(a, "{d} {d} {s} {s}\n", .{ test_value.num_df, test_value.den_df, try number(a, test_value.f, "12.2"), try number(a, test_value.p, "pvalue6.4") });
                    if (route) |rr| try rr.finish(a, out, start, "SliceTests");
                }
                if (options.means) {
                    const start = out.items.len;
                    try out.print(a, "\n{s} Least Squares Means Slice\n\nStandard\nSlice", .{effect.name});
                    for (varying.items) |c| try out.print(a, " {s}", .{m.source.columns.items[x.matrix.classes[c].column].name});
                    try out.appendSlice(a, " Estimate Error DF t Value Pr > |t|");
                    if (options.cl) try out.appendSlice(a, " Alpha Lower Upper");
                    try out.appendSlice(a, "\n\n");
                    for (partition.rows) |index| {
                        const value = linear.estimate(joint, rows[index].coefficients, df, options.alpha, .two, options.singular) catch return proc.failGap(cx.diags, spec.line, "SLICE mean inference boundary", .{});
                        try out.appendSlice(a, label.items);
                        try rowLevels(cx, out, m, x, rows[index], varying.items);
                        if (!value.estimable) try out.appendSlice(a, " Non-est . . . .") else try out.print(a, " {s} {s} {d} {s} {s}", .{ try number(a, value.estimate, "12.4"), try number(a, value.se, "12.4"), df, try number(a, value.t, "12.2"), try number(a, value.p, "pvalue6.4") });
                        if (options.cl) try out.print(a, " {d} {s} {s}", .{ options.alpha, try number(a, value.lower, "12.4"), try number(a, value.upper, "12.4") });
                        try out.append(a, '\n');
                    }
                    if (route) |rr| try rr.finish(a, out, start, "Slices");
                }
                if (result.differences.len > 0) {
                    const start = out.items.len;
                    try out.print(a, "\nSimple Differences of {s} Least Squares Means\n\nStandard\nSlice", .{effect.name});
                    for (varying.items) |c| try out.print(a, " {s}", .{m.source.columns.items[x.matrix.classes[c].column].name});
                    for (varying.items) |c| try out.print(a, " _{s}", .{m.source.columns.items[x.matrix.classes[c].column].name});
                    try out.appendSlice(a, " Estimate Error DF t Value Pr > |t|");
                    if (options.adjust != .none) try out.appendSlice(a, " Adjustment Adj P");
                    if (options.cl) try out.appendSlice(a, " Alpha Lower Upper");
                    try out.appendSlice(a, "\n\n");
                    for (result.differences) |difference| {
                        const value = difference.value;
                        try out.appendSlice(a, label.items);
                        try rowLevels(cx, out, m, x, rows[difference.left], varying.items);
                        try rowLevels(cx, out, m, x, rows[difference.right], varying.items);
                        if (!value.estimable) try out.appendSlice(a, " Non-est . . . .") else try out.print(a, " {s} {s} {d} {s} {s}", .{ try number(a, value.estimate, "12.4"), try number(a, value.se, "12.4"), df, try number(a, value.t, "12.2"), try number(a, value.p, "pvalue6.4") });
                        if (options.adjust != .none) try out.print(a, " {s} {s}", .{ switch (options.adjust) {
                            .none => "None",
                            .bon => "Bonferroni",
                            .sidak => "Sidak",
                            .tukey => "Tukey-Kramer",
                        }, try number(a, difference.adjusted_p, "pvalue6.4") });
                        if (options.cl) try out.print(a, " {d} {s} {s}", .{ options.alpha, try number(a, difference.lower, "12.4"), try number(a, difference.upper, "12.4") });
                        try out.append(a, '\n');
                    }
                    if (route) |rr| try rr.finish(a, out, start, "SliceDiffs");
                }
            }
            if (selected == 0) return proc.failGap(cx.diags, spec.line, "SLICE: unmatched formatted-value selector diagnostics are not independently verified", .{});
        }
    }
}
test {
    _ = @import("mixed_slice_tests.zig");
}
