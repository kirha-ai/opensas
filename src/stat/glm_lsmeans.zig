//! Balanced population margins, full GLM coefficients, and explicit Non-est.
//! S154 physical pp.4072–4076,4081,4144–4147; COMMON009 original SAS listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const coded = @import("design_matrix.zig");
const estimability = @import("glm_estimability.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const inference = @import("lsmeans_inference.zig");
pub const Request = struct { effect: usize, scheffe: bool = false, slice_columns: []const usize = &.{}, error_effect: ?usize = null, error_kind: ?@import("glm_test_statement.zig").Kind = null, e: bool = false, stderr: bool = false, singular: f64 = 1e-4, pdiff: bool = false, cl: bool = false, alpha: f64 = 0.05, adjust: inference.Adjustment = .none, adjust_explicit: bool = false };
pub const Mean = struct { levels: []const ?usize, coefficients: []const f64, inference: estimability.Result };
pub const Table = struct { slices: []const @import("glm_lsmeans_slice.zig").Result = &.{}, effect: []const u8, classes: []const coded.Class, columns: []const coded.Column, means: []const Mean, comparisons: []const inference.Difference = &.{}, mean_limits: []const inference.Interval = &.{}, df_error: usize = 0 };

/// Parses only the LSMEANS statement, after MODEL has resolved its effects.
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect, requests: *std.ArrayList(Request)) diag.Error!void {
    const first = requests.items.len;
    var i: usize = 1;
    while (i < tokens.len and tokens[i].tag != .slash) {
        var variables: std.ArrayList(usize) = .empty;
        while (true) {
            if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS requires a classification effect", .{});
            const ci = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: LSMEANS variable not found", .{});
            if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: LSMEANS requires CLASS variables", .{});
            if (std.mem.indexOfScalar(usize, variables.items, ci) != null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: repeated LSMEANS factor", .{});
            try variables.append(cx.arena, ci);
            i += 1;
            if (i == tokens.len or tokens[i].tag != .star) break;
            i += 1;
        }
        var found: ?usize = null;
        for (effects, 0..) |effect, e| {
            if (effect.variables.len != variables.items.len) continue;
            var matches = true;
            for (variables.items) |ci| if (std.mem.indexOfScalar(usize, effect.variables, ci) == null) {
                matches = false;
            };
            if (matches) {
                found = e;
                break;
            }
        }
        try requests.append(cx.arena, .{ .effect = found orelse return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS effect is not in MODEL", .{}) });
    }
    if (requests.items.len == first) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS requires effects", .{});
    var options: Request = .{ .effect = 0, .alpha = spec.proc_alpha };
    if (i < tokens.len) i += 1;
    while (i < tokens.len) {
        const token = tokens[i];
        if (token.tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS option", .{});
        if (std.ascii.eqlIgnoreCase(token.text, "e") and !(i + 1 < tokens.len and tokens[i + 1].tag == .eq)) {
            options.e = true;
            i += 1;
        } else if (eq(token.text, "e")) {
            i += 2; // E=; bare E was handled above.
            var variables: std.ArrayList(usize) = .empty;
            while (true) {
                if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS E= requires an effect", .{});
                const col = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS error variable not found", .{});
                try variables.append(cx.arena, col);
                i += 1;
                if (i == tokens.len or tokens[i].tag != .star) break;
                i += 1;
            }
            options.error_effect = for (effects, 0..) |effect, index| {
                if (effect.variables.len != variables.items.len) continue;
                var matches = true;
                for (effect.variables) |col| if (std.mem.count(usize, effect.variables, &.{col}) != std.mem.count(usize, variables.items, &.{col})) { matches = false; };
                if (matches) break index;
            } else return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS error effect is not in MODEL", .{});
        } else if (eq(token.text, "etype")) {
            if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or tokens[i + 2].tag != .number) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS ETYPE requires1,2,3,or4", .{});
            const value = std.fmt.parseFloat(f64, tokens[i + 2].text) catch return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS ETYPE", .{});
            if (!std.math.isFinite(value) or value < 1 or value > 4 or @floor(value) != value) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS ETYPE requires1,2,3,or4", .{});
            options.error_kind = @enumFromInt(@as(u3, @intFromFloat(value)));
            i += 3;
        } else if (std.ascii.eqlIgnoreCase(token.text, "stderr")) {
            options.stderr = true;
            i += 1;
        } else if (eq(token.text, "slice")) {
            if (options.slice_columns.len > 0 or i + 2 >= tokens.len or tokens[i + 1].tag != .eq) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: SLICE requires =CLASS-factor or =(CLASS-factors)", .{});
            i += 2;
            const parenthesized = tokens[i].tag == .lparen;
            if (parenthesized) i += 1;
            var columns: std.ArrayList(usize) = .empty;
            while (i < tokens.len and tokens[i].tag == .name) {
                const column = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, token.line, "PROC GLM: SLICE variable not found", .{});
                if (std.mem.indexOfScalar(usize, spec.classes, column) == null) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: SLICE requires CLASS factors", .{});
                if (std.mem.indexOfScalar(usize, columns.items, column) != null) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: repeated SLICE factor", .{});
                try columns.append(cx.arena, column);
                i += 1;
                if (!parenthesized) break;
            }
            if (columns.items.len == 0 or (parenthesized and (i >= tokens.len or tokens[i].tag != .rparen))) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: malformed SLICE factor list", .{});
            if (parenthesized) i += 1;
            options.slice_columns = columns.items;
        } else if (eq(token.text, "cl")) {
            options.cl = true;
            i += 1;
        } else if (eq(token.text, "pdiff") or eq(token.text, "diff")) {
            options.pdiff = true;
            i += 1;
            if (i < tokens.len and tokens[i].tag == .eq) {
                i += 1;
                if (i == tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: PDIFF requires a comparison type", .{});
                if (!eq(tokens[i].text, "all")) {
                    for ([_][]const u8{ "control", "controll", "controlu", "anom" }) |name| if (eq(tokens[i].text, name)) return proc.failGap(cx.diags, token.line, "PROC GLM: PDIFF={s} is not implemented", .{tokens[i].text});
                    return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid PDIFF type", .{});
                }
                if (!options.adjust_explicit) options.adjust = .tukey;
                i += 1;
            }
        } else if (eq(token.text, "adjust")) {
            if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or tokens[i + 2].tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: ADJUST requires a method", .{});
            const value = tokens[i + 2].text;
            options.scheffe = eq(value, "scheffe");
            options.adjust = if (options.scheffe or eq(value, "t")) .none else if (eq(value, "bon")) .bon else if (eq(value, "sidak")) .sidak else if (eq(value, "tukey")) .tukey else {
                for ([_][]const u8{ "dunnett", "nelson", "scheffe", "simulate", "sim", "smm", "gt2" }) |name| if (eq(value, name)) return proc.failGap(cx.diags, token.line, "PROC GLM: ADJUST={s} is not implemented", .{value});
                return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid ADJUST method", .{});
            };
            options.adjust_explicit = true;
            options.pdiff = true;
            i += 3;
        } else if (eq(token.text, "alpha") or eq(token.text, "singular")) {
            if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or tokens[i + 2].tag != .number) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS numeric option requires =number", .{});
            const value = std.fmt.parseFloat(f64, tokens[i + 2].text) catch return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS numeric option", .{});
            if (!std.math.isFinite(value) or value <= 0 or value >= 1) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS ALPHA/SINGULAR must be between zero and one", .{});
            if (eq(token.text, "alpha")) options.alpha = value else options.singular = value;
            i += 3;
        } else {
            for ([_][]const u8{ "at", "bylevel", "cov", "e", "etype", "lines", "linestable", "noprint", "obsmargins", "om", "out", "plot", "plots", "slice", "tdiff" }) |name| if (eq(token.text, name)) return proc.failGap(cx.diags, token.line, "PROC GLM: LSMEANS option {s} is not implemented", .{token.text});
            return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS option {s}", .{token.text});
        }
    }
    if (options.pdiff and options.stderr) return proc.failGap(cx.diags, 0, "PROC GLM: combined PDIFF and STDERR presentation is not implemented", .{});
    for (requests.items[first..]) |*request| {
        const effect = request.effect;
        request.* = options;
        request.effect = effect;
        for (request.slice_columns) |column| {
            if (effects[effect].variables.len < 2 or std.mem.indexOfScalar(usize, effects[effect].variables, column) == null) return cx.diags.fail(error.ParseError, 0, "PROC GLM: SLICE factor must belong to the requested interaction", .{});
        }
    }
}

fn compatible(target: []const ?usize, column: []const ?usize) bool {
    for (target, column) |t, c| if (t != null and c != null and t.? != c.?) return false;
    return true;
}

/// Arena-owned table. Reuse full GLM coding for E labels and observed cells;
/// refit its equivalent column space with the existing rank/QR primitive.
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request, mse: f64, df_error: usize) diag.Error!Table {
    if (request.error_effect != null and (request.stderr or request.pdiff)) return proc.failGap(cx.diags, 0, "PROC GLM: LSMEANS alternate error requires the full fitted effect tables", .{});
    return computeResolved(cx, spec, d, request, mse, df_error, mse, df_error);
}
/// Preserve the actual model rank/covariance basis while selecting the requested
/// inference scale/DF. E= is ignored unless STDERR/PDIFF/TDIFF is requested;
/// CL by itself does not activate it (S154 physical p.4076).
pub fn computeWithFit(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request, fit: @import("glm_fit.zig").Result) diag.Error!Table {
    var mse = fit.model.fit.mse;
    var df = fit.model.fit.df_error;
    if (request.error_effect) |effect| if (request.stderr or request.pdiff) {
        const Kind = @import("glm_test_statement.zig").Kind;
        const kind = request.error_kind orelse (if (spec.ss4) Kind.iv else if (spec.ss3 or spec.defaultSumsOfSquares()) Kind.iii else if (spec.ss2) Kind.ii else Kind.i);
        const available = switch (kind) { .i => spec.ss1 or spec.defaultSumsOfSquares(), .ii => spec.ss2, .iii => spec.ss3 or spec.defaultSumsOfSquares(), .iv => spec.ss4 };
        if (!available) return proc.failGap(cx.diags, 0, "PROC GLM: requested LSMEANS ETYPE was not computed in MODEL", .{});
        const table = switch (kind) { .i => fit.type_i, .ii => fit.type_ii, .iii => fit.type_iii, .iv => fit.type_iv };
        if (table.len != spec.effects.len) return error.ExecError;
        const error_effect = table[effect];
        if (error_effect.df == 0 or !std.math.isFinite(error_effect.ms) or !(error_effect.ms > 0)) return proc.failGap(cx.diags, 0, "PROC GLM: degenerate LSMEANS error-effect inference is not implemented", .{});
        mse = error_effect.ms;
        df = error_effect.df;
    };
    return computeResolved(cx, spec, d, request, fit.model.fit.mse, fit.model.fit.df_error, mse, df);
}
fn computeResolved(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request, model_mse: f64, model_df: usize, mse: f64, df_error: usize) diag.Error!Table {
    const a = cx.arena;
    const matrix = try estimability.codedDesign(cx, spec, d);
    var model = try estimability.fitCoded(cx, spec, d, matrix, model_mse, model_df);
    defer model.deinit(a);
    model.fit.mse = mse;
    model.fit.df_error = df_error;
    var means: std.ArrayList(Mean) = .empty;
    var name: []const u8 = spec.effects[request.effect].name;
    for (matrix.columns) |target| {
        if (target.effect_index == null or target.effect_index.? != request.effect) continue;
        name = target.effect_name;
        const l = try a.alloc(f64, matrix.p);
        for (matrix.columns, 0..) |column, j| {
            if (column.effect_index == null) {
                l[j] = 1;
                continue;
            }
            const effect = spec.effects[column.effect_index.?];
            var has_class = false;
            var has_continuous = false;
            for (effect.variables) |ci| {
                if (std.mem.indexOfScalar(usize, spec.classes, ci) != null) has_class = true else has_continuous = true;
            }
            if (has_class and has_continuous) return proc.failGap(cx.diags, 0, "PROC GLM: LSMEANS mixed covariate interactions are not implemented", .{});
            if (!has_class) {
                // Standard LS-means use the mean of each covariate product,
                // without precision weights (S154 physical pp.4145–4146).
                var sum: f64 = 0;
                var count: f64 = 0;
                for (0..matrix.n) |r| {
                    sum += matrix.x[r * matrix.p + j] * d.frequencies[r];
                    count += d.frequencies[r];
                }
                l[j] = sum / count;
            } else if (!compatible(target.class_values, column.class_values)) {
                l[j] = 0;
            } else {
                var count: usize = 0;
                for (matrix.columns) |other| if (other.effect_index == column.effect_index and compatible(target.class_values, other.class_values)) {
                    count += 1;
                };
                l[j] = 1 / @as(f64, @floatFromInt(count));
            }
        }
        try means.append(a, .{ .levels = target.class_values, .coefficients = l, .inference = try estimability.evaluate(model, l, request.singular) });
    }
    if (request.pdiff and means.items.len < 2) return proc.failGap(cx.diags, 0, "PROC GLM: LSMEANS comparisons need at least two levels", .{});
    if (request.pdiff and request.adjust == .tukey and means.items.len > 2) return proc.failGap(cx.diags, 0, "PROC GLM: Tukey studentized-range inference for more than two LS-means is not implemented", .{});
    const limits = try a.alloc(inference.Interval, means.items.len);
    for (means.items, limits) |mean, *limit| limit.* = if (request.cl) inference.interval(mean.inference, df_error, request.alpha, means.items.len, .none) catch return proc.failGap(cx.diags, 0, "PROC GLM: LSMEANS confidence critical value is outside the numerical domain", .{}) else .{};
    var scheffe_rank: usize = 0;
    if (request.scheffe) {
        const rows = try a.alloc([]const f64, means.items.len);
        const indices = try a.alloc(usize, means.items.len);
        for (means.items, rows, indices, 0..) |mean, *row, *index, i| { row.* = mean.coefficients; index.* = i; }
        const family = @import("lsmeans_slice.zig").testPartition(a, @import("linear_hypothesis.zig").fromRegression(model, request.singular), rows, indices) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, 0, "PROC GLM: Scheffe difference-family rank is outside the implemented domain", .{});
        if (family.result.status != .estimable or family.result.rank == 0) return proc.failGap(cx.diags, 0, "PROC GLM: Scheffe inference for a nonestimable difference family is not implemented", .{});
        scheffe_rank = family.result.rank;
    }
    var differences: std.ArrayList(inference.Difference) = .empty;
    if (request.pdiff) for (means.items, 0..) |left, i| for (i + 1..means.items.len) |j| {
        var difference = inference.difference(a, model, left.coefficients, means.items[j].coefficients, i, j, means.items.len, request.alpha, request.adjust, request.singular, request.cl and !request.scheffe) catch return proc.failGap(cx.diags, 0, "PROC GLM: LS-means difference inference is outside the implemented domain", .{});
        if (request.scheffe) {
            if (difference.inference.t_value) |value| difference.adjusted_p = @import("glm_scheffe.zig").probability(value, @floatFromInt(df_error), scheffe_rank) catch return proc.failGap(cx.diags, 0, "PROC GLM: Scheffe probability is outside the numerical domain", .{});
            if (request.cl and difference.inference.standard_error != null and df_error > 0) {
                const cutoff = @import("glm_scheffe.zig").critical(@floatFromInt(df_error), request.alpha, scheffe_rank) catch return proc.failGap(cx.diags, 0, "PROC GLM: Scheffe critical value is outside the numerical domain", .{});
                const radius = cutoff * difference.inference.standard_error.?;
                difference.limits = .{ .lower = difference.inference.estimate.? - radius, .upper = difference.inference.estimate.? + radius };
            }
        }
        try differences.append(a, difference);
    };
    return .{ .slices = try @import("glm_lsmeans_slice.zig").compute(cx, request, matrix.classes, means.items, model), .effect = name, .classes = matrix.classes, .columns = matrix.columns, .means = means.items, .comparisons = differences.items, .mean_limits = limits, .df_error = df_error };
}

pub fn number(a: A, v: ?f64, decimals: usize) ![]const u8 {
    const value = v orelse return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, request: Request, table: Table) !void {
    const a = cx.arena;
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out) else if (cx.graph_title) |title| try out.print(a, "\n{s}\n", .{title});
    try out.appendSlice(a, "\nThe GLM Procedure\nLeast Squares Means\n");
    if (request.scheffe) try out.appendSlice(a, "Adjustment for Multiple Comparisons: Scheffe\n");
    if (request.adjust != .none) try out.print(a, "Adjustment for Multiple Comparisons: {s}\n", .{switch (request.adjust) {
        .none => "",
        .bon => "Bonferroni",
        .sidak => "Sidak",
        .tukey => "Tukey-Kramer",
    }});
    if (request.e) {
        try out.print(a, "\nCoefficients for {s} Least Square Means\n\n{s} Level\n", .{ table.effect, table.effect });
        for (table.classes, 0..) |class, c| {
            if (table.means.len == 0 or table.means[0].levels[c] == null) continue;
            var last = true;
            for (table.means[0].levels[c + 1 ..]) |level| if (level != null) {
                last = false;
            };
            if (last) try out.appendSlice(a, "Effect ");
            for (table.means) |mean| try out.print(a, "{s} ", .{class.map.levels[mean.levels[c].?].label});
            try out.append(a, '\n');
        }
        // Match SAS's Effect heading on the final level row.
        // The compact renderer preserves token and row order for corpus comparisons.
        try out.append(a, '\n');
        for (table.columns, 0..) |column, j| {
            try out.print(a, "{s}", .{column.effect_name});
            for (column.class_values, table.classes) |level, class| if (level) |v| try out.print(a, " {s}", .{class.map.levels[v].label});
            for (table.means) |mean| try out.print(a, " {s}", .{try std.fmt.allocPrint(a, "{d}", .{mean.coefficients[j]})});
            try out.append(a, '\n');
        }
    }
    if (request.pdiff or request.cl) {
        try @import("glm_lsmeans_compare_render.zig").render(cx, out, spec, d, request, table);
        return @import("glm_lsmeans_slice.zig").render(cx, out, spec, d.response, table);
    }
    try out.append(a, '\n');
    for (table.classes, 0..) |class, c| if (table.means.len > 0 and table.means[0].levels[c] != null) try out.print(a, "{s} ", .{spec.input.ds.columns.items[class.column].name});
    try out.print(a, "{s} LSMEAN", .{spec.input.ds.columns.items[d.response].name});
    if (request.stderr) try out.appendSlice(a, " Standard Error Pr > |t|");
    try out.appendSlice(a, "\n\n");
    for (table.means) |mean| {
        for (mean.levels, table.classes) |level, class| if (level) |v| try out.print(a, "{s} ", .{class.map.levels[v].label});
        const r = mean.inference;
        try out.print(a, "{s}", .{if (r.status == .nonestimable) "Non-est" else try number(a, r.estimate, 7)});
        if (request.stderr) try out.print(a, " {s} {s}", .{ try number(a, r.standard_error, 7), if (r.p_value != null and r.p_value.? < 0.0001) "<.0001" else try number(a, r.p_value, 4) });
        try out.append(a, '\n');
    }
    try @import("glm_lsmeans_slice.zig").render(cx, out, spec, d.response, table);
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, mse: f64, df_error: usize) diag.Error!void {
    for (spec.lsmeans) |request| {
        const table = compute(cx, spec, d, request, mse, df_error) catch |err| {
            if (err != error.ExecError) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC GLM: LSMEANS computation failed", .{});
        };
        if (!spec.noprint) try render(cx, out, spec, d, request, table);
    }
}

pub fn executeWithFit(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, fit: @import("glm_fit.zig").Result) diag.Error!void {
    for (spec.lsmeans) |request| {
        const table = try computeWithFit(cx, spec, d, request, fit);
        if (!spec.noprint) try render(cx, out, spec, d, request, table);
    }
}

const testing = std.testing;
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
fn sample(a: A, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cells");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("h", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 6, 9, 12, 4, 7, 13, 19, 23, 24 }, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 6) "A" else "B" }, .{ .num = if (i >= 3 and i < 6) 1 else 0 }, .{ .num = y } });
    try lib.put("cells", ds);
    return ds;
}
fn analyzed(cx: proc.ProcCtx, source: []const u8) !struct { spec: parse.Spec, d: design.Design } {
    const s = try parse.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try selection.View.init(cx.arena, s.input, .{ .frequency = s.freq, .weight = s.weight });
    return .{ .spec = s, .d = try design.build(cx, s, view, s.responses[0]) };
}

test "COMMON009 original empty-cell coefficients and nonestimable marginal fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group h; model y=group|h; lsmeans group*h / e; lsmeans group h / e stderr singular=1e-6; run;");
    try testing.expectEqual(@as(usize, 3), r.spec.lsmeans.len);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqual(@as(usize, 3), table.means.len);
    try testing.expectEqual(@as(usize, 8), table.columns.len);
    const expected = [_][8]f64{ .{ 1, 1, 0, 1, 0, 1, 0, 0 }, .{ 1, 1, 0, 0, 1, 0, 1, 0 }, .{ 1, 0, 1, 1, 0, 0, 0, 1 } };
    for (table.means, expected, [_]f64{ 9, 8, 22 }) |mean, l, value| {
        try testing.expectEqualSlices(f64, &l, mean.coefficients);
        try testing.expectEqual(estimability.Status.estimable, mean.inference.status);
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), mean.inference.variance_factor.?, 1e-12);
    }
    try testing.expectEqualStrings("group*h", table.columns[5].effect_name);
    for ([_][2]?usize{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 } }, table.columns[5..]) |levels, column| try testing.expectEqualSlices(?usize, &levels, column.class_values);
    const marginal = try compute(cx, r.spec, r.d, r.spec.lsmeans[1], 74.0 / 6.0, 6);
    try testing.expectApproxEqAbs(@as(f64, 8.5), marginal.means[0].inference.estimate.?, 1e-12);
    const bad = marginal.means[1].inference;
    try testing.expectEqual(estimability.Status.nonestimable, bad.status);
    inline for (.{ "estimate", "variance_factor", "standard_error", "t_value", "p_value" }) |field| try testing.expect(@field(bad, field) == null);
    var output: std.ArrayList(u8) = .empty;
    try render(cx, &output, r.spec, r.d, r.spec.lsmeans[1], marginal);
    try testing.expect(std.mem.indexOf(u8, output.items, "B Non-est . .\n") != null);
    try testing.expect(!diagnostics.hasErrors());
}

test "COMMON009 missing response and blank CLASS do not create levels or cells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    try ds.appendRow(&.{ .{ .str = "C" }, .{ .num = 2 }, @import("../value.zig").Value.missing });
    try ds.appendRow(&.{ .{ .str = " " }, .{ .num = 2 }, .{ .num = 999 } });
    try ds.appendRow(&.{ .{ .str = "C" }, @import("../value.zig").Value.missing, .{ .num = 999 } });
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm order=data; class group h; model y=group h group*h / ss1; lsmeans h*group / e; run;");
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqual(@as(usize, 9), r.d.n);
    try testing.expectEqual(@as(usize, 3), table.means.len);
    try testing.expectEqual(@as(usize, 2), table.classes[0].map.levels.len);
    try testing.expectEqual(@as(usize, 2), table.classes[1].map.levels.len);
    try testing.expectEqualStrings("group*h", table.effect);
}

test "COMMON009 LSMEANS parsing rejects invalid effects and unsupported options loudly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{
        "proc glm; class group h; lsmeans group; model y=group; run;",
        "proc glm; class group h; model y=group; lsmeans h; run;",
        "proc glm; class group h; model y=group; lsmeans; run;",
        "proc glm; class group h; model y=group; lsmeans group*; run;",
        "proc glm; class group h; model y=group; lsmeans group / singular=0; run;",
        "proc glm; class group h; model y=group; lsmeans group / e=h; run;",
    }) |source| {
        try testing.expectError(error.ParseError, parse.parse(cx, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.list.items[diagnostics.list.items.len - 1].line > 0);
    }
}

test "COMMON009 unequal counts use balanced margins and FREQ WEIGHT inference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "weighted");
    _ = try ds.addColumn("group", .char);
    for ([_][]const u8{ "h", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][5]f64{ .{ 0, 0, 1, 2, 1 }, .{ 0, 0, 3, 1, 2 }, .{ 0, 1, 5, 1, 1 }, .{ 0, 1, 7, 1, 1 }, .{ 1, 0, 9, 1, 1 }, .{ 1, 0, 11, 1, 1 }, .{ 1, 1, 13, 1, 1 }, .{ 1, 1, 15, 1, 1 } }) |r| try ds.appendRow(&.{ .{ .str = if (r[0] == 0) "A" else "B" }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] } });
    try lib.put("weighted", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group h; model y=group h group*h; freq f; weight w; lsmeans group / e stderr; run;");
    var fit = try @import("glm.zig").fitDesign(cx, r.spec, r.d);
    defer fit.deinit(a);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    // A0 precision total 4, weighted mean 2; A1 total 2, mean 6.
    // Balanced margin is (2+6)/2=4 regardless of physical/frequency imbalance.
    try testing.expectEqual(@as(usize, 5), fit.model.fit.df_error);
    try testing.expectApproxEqAbs(@as(f64, 4), table.means[0].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 3.0 / 16.0), table.means[0].inference.variance_factor.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 12), table.means[1].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.25), table.means[1].inference.variance_factor.?, 1e-12);
    try testing.expectApproxEqAbs(@sqrt(2.0 * 3.0 / 16.0), table.means[0].inference.standard_error.?, 1e-12);
}

test "COMMON009 class data ordering changes coefficients and row labels together" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    std.mem.reverse([]const @import("../value.zig").Value, ds.rows.items);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm order=data; class group h; model y=group h group*h / ss1; lsmeans group*h / e; run;");
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqualStrings("B", table.classes[0].map.levels[0].label);
    for (table.means, [_]f64{ 22, 9, 8 }, [_][2]?usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 } }) |mean, value, levels| {
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectEqualSlices(?usize, &levels, mean.levels);
    }
}

test "COMMON009 adjusted covariate means differ from raw group means" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "adjusted");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    const noise = [_]f64{ -1, 2, -1 };
    for (0..6) |i| {
        const x: f64 = @floatFromInt(i % 3 + (if (i < 3) @as(usize, 0) else 2));
        const intercept: f64 = if (i < 3) 10 else 20;
        try ds.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = x }, .{ .num = intercept + 2 * x + noise[i % 3] } });
    }
    try lib.put("adjusted", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group; model y=group x; lsmeans group / e; run;");
    var fit = try @import("glm.zig").fitDesign(cx, r.spec, r.d);
    defer fit.deinit(a);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    // Noise is centered and orthogonal to x within each group. The common
    // slope is 2; at global x=2 margins are14,24, not raw means12,26.
    for (table.means, [_]f64{ 14, 24 }) |mean, value| {
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectEqual(@as(f64, 2), mean.coefficients[3]);
    }
    try testing.expectApproxEqAbs(@as(f64, 4), fit.model.fit.mse, 1e-12);
}

test "COMMON009 MODEL bar is token-level ordered subset expansion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const left = try analyzed(cx, "proc glm; class group h; model y=group|h; lsmeans group*h / e; run;");
    const right = try analyzed(cx, "proc glm; class group h; model y=group h group*h; lsmeans group*h / e; run;");
    try testing.expectEqualSlices(f64, right.d.x, left.d.x);
    for (left.spec.effects, right.spec.effects) |l, r| {
        try testing.expectEqualStrings(r.name, l.name);
        try testing.expectEqualSlices(usize, r.variables, l.variables);
    }
    var lo: std.ArrayList(u8) = .empty;
    var ro: std.ArrayList(u8) = .empty;
    try @import("glm.zig").execute(cx, &lo, left.spec);
    try @import("glm.zig").execute(cx, &ro, right.spec);
    try testing.expectEqualStrings(ro.items, lo.items);
    // Three generic variable operands exercise left-to-right order and @degree
    // without depending on a particular pair of CLASS names or source spacing.
    const expanded = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y = group | h | y @2; run;", &diagnostics));
    for (expanded.effects, [_][]const u8{ "group", "h", "group*h", "y", "group*y", "h*y" }) |effect, name| try testing.expectEqualStrings(name, effect.name);
    const repeated = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y=group|h|group; run;", &diagnostics));
    try testing.expectEqual(@as(usize, 3), repeated.effects.len);
    const main_only = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y=group|h@1; run;", &diagnostics));
    try testing.expectEqual(@as(usize, 2), main_only.effects.len);
    for ([_][]const u8{
        "proc glm; class group h; model y=group|; run;",
        "proc glm; class group h; model y=group||h; run;",
        "proc glm; class group h; model y=group|h@0; run;",
        "proc glm; class group h; model y=group|h@1.5; run;",
        "proc glm; class group h; model y=group|missing_variable; run;",
        "proc glm; class group h; model y=group*h|h; run;",
    }) |source| {
        try testing.expectError(error.ParseError, parse.parse(cx, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.list.items[diagnostics.list.items.len - 1].line > 0);
    }
}

test "STAT-COMMON-026 complete adjusted listing preserves fields and analytic two-level intervals" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    var ds = try helper.data(a, "tests/corpus/stat_common026_adjusted_lsmeans.sas", "sample", &.{ "x", "z", "y", "group", "weight", "freq" }, &.{3}, 0);
    try testing.expectEqual(@as(usize, 12), ds.rows.items.len);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const program = try helper.read(a, "tests/corpus/stat_common026_adjusted_lsmeans.sas");
    const start = std.mem.indexOf(u8, program, "proc glm data=sample").?;
    var out: std.ArrayList(u8) = .empty;
    try @import("glm.zig").run(cx, &out, try lex.tokenize(a, program[start..], &diagnostics));
    const contract = try helper.read(a, "tests/corpus/stat_common026_adjusted_lsmeans.txt");
    const word_start = std.mem.indexOf(u8, contract, "words ").? + 6;
    const end = std.mem.indexOfScalarPos(u8, contract, word_start, '\n').?;
    var expected = std.mem.tokenizeAny(u8, contract[word_start..end], " \r\n\t");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (expected.next()) |word| try testing.expectEqualStrings(word, actual.next() orelse return error.TestUnexpectedResult);
    try testing.expect(actual.next() == null);
    try testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-COMMON-026 adjusted margins difference variance and intervals match rational ANCOVA" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/stat_common026_adjusted_lsmeans.sas", "sample", &.{ "x", "z", "y", "group", "weight", "freq" }, &.{3}, 0);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group; model y=group x; lsmeans group / pdiff cl adjust=tukey; run;");
    var fit = try @import("glm.zig").fitDesign(cx, r.spec, r.d);
    defer fit.deinit(a);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    // Within-group Sxx=35,Sxy=119/2 -> slope17/10. Means at globalx=13/2:
    // A=17/2+3*17/10=68/5, B=64/3-3*17/10=487/30.
    const mse: f64 = 581.0 / 540.0;
    const mean_factor: f64 = 89.0 / 210.0;
    const diff_factor: f64 = 143.0 / 105.0;
    try testing.expectApproxEqAbs(mse, fit.model.fit.mse, 1e-11);
    for (table.means, [_]f64{ 68.0 / 5.0, 487.0 / 30.0 }, table.mean_limits) |mean, value, limits| {
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-10);
        try testing.expectApproxEqAbs(mean_factor, mean.inference.variance_factor.?, 1e-12);
        // Independent t(9) .975 reference, with ordinary mean limits unadjusted.
        const radius = 2.2621571627409915 * @sqrt(mse * mean_factor);
        try testing.expectApproxEqAbs(value - radius, limits.lower.?, 1e-9);
        try testing.expectApproxEqAbs(value + radius, limits.upper.?, 1e-9);
    }
    try testing.expectEqual(@as(usize, 1), table.comparisons.len);
    const pair = table.comparisons[0];
    try testing.expectApproxEqAbs(@as(f64, -79.0 / 30.0), pair.inference.estimate.?, 1e-10);
    try testing.expectApproxEqAbs(diff_factor, pair.inference.variance_factor.?, 1e-12);
    const radius = 2.2621571627409915 * @sqrt(mse * diff_factor);
    try testing.expectApproxEqAbs(-79.0 / 30.0 - radius, pair.limits.lower.?, 1e-9);
    try testing.expectApproxEqAbs(-79.0 / 30.0 + radius, pair.limits.upper.?, 1e-9);
    try testing.expectEqual(pair.inference.p_value, pair.adjusted_p); // two levels: exact Tukey=t
}

test "STAT-COMMON-026 GLM applicability PDIFF defaults and conditional ALPHA are source specific" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const bare = try analyzed(cx, "proc glm; class group; model y=group; lsmeans group /pdiff; run;");
    try testing.expectEqual(inference.Adjustment.none, bare.spec.lsmeans[0].adjust);
    const all = try analyzed(cx, "proc glm; class group; model y=group; lsmeans group /pdiff=all; run;");
    try testing.expectEqual(inference.Adjustment.tukey, all.spec.lsmeans[0].adjust);
    const override = try analyzed(cx, "proc glm; class group; model y=group; lsmeans group /adjust=t pdiff=all; run;");
    try testing.expectEqual(inference.Adjustment.none, override.spec.lsmeans[0].adjust);
    const implied = try analyzed(cx, "proc glm; class group; model y=group; lsmeans group /adjust=bon; run;");
    try testing.expect(implied.spec.lsmeans[0].pdiff);
    const alpha = try analyzed(cx, "proc glm alpha=.1; class group; model y=group; lsmeans group /alpha=.2; run;");
    try testing.expectEqual(@as(f64, 0.2), alpha.spec.lsmeans[0].alpha);
    try testing.expect(!alpha.spec.lsmeans[0].cl);
    // Shared chapter permits omitted effects/ILINK/DF; GLM's own syntax doesnot.
    for ([_][]const u8{ "proc glm; class group; model y=group; lsmeans; run;", "proc glm; class group; model y=group; lsmeans group /ilink; run;", "proc glm; class group; model y=group; lsmeans group /df=9; run;", "proc glm; class group; model y=group; lsmeans group /adjust=typo; run;" }) |source| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, parse.parse(.{ .arena = a, .lib = &lib, .diags = &d }, try lex.tokenize(a, source, &d)));
        try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
}

test "STAT-COMMON-026 disconnected additive margins keep estimable differences" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "disconnected");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 0, 2, 2, 4, 9, 11 }, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 2) "a1" else if (i < 4) "a2" else "a3" }, .{ .str = if (i < 4) "b1" else "b2" }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("disconnected", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class A B; model y=A B; lsmeans A /pdiff cl; run;");
    // Three observed cell means have rank3; within-cell SS=6, df=3, MSE=2.
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 2, 3);
    try testing.expectEqual(@as(usize, 3), table.means.len);
    try testing.expectEqual(@as(usize, 3), table.comparisons.len);
    try testing.expectEqual(estimability.Status.nonestimable, table.means[0].inference.status);
    try testing.expectEqual(estimability.Status.nonestimable, table.means[1].inference.status);
    const diff = table.comparisons[0];
    try testing.expectEqual(estimability.Status.estimable, diff.inference.status);
    try testing.expectApproxEqAbs(@as(f64, -2), diff.inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1), diff.inference.variance_factor.?, 1e-12);
    // Student t3 atsqrt2 has an independent elementary arctangent tail.
    const probability = 1 - @as(f64, 2) / std.math.pi * (std.math.atan(@sqrt(@as(f64, 2.0 / 3.0))) + @sqrt(@as(f64, 6)) / 5);
    try testing.expectApproxEqAbs(probability, diff.adjusted_p.?, 1e-12);
    try testing.expectEqual(estimability.Status.nonestimable, table.comparisons[1].inference.status);
    try testing.expect(table.comparisons[1].adjusted_p == null);
}

test "STAT-COMMON-026 GLM ALPHA without CL cannot alter or suppress requested probabilities" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var plain: std.ArrayList(u8) = .empty;
    var altered: std.ArrayList(u8) = .empty;
    try @import("glm.zig").run(cx, &plain, try lex.tokenize(a, "proc glm; class group; model y=group; lsmeans group /pdiff; run;", &diagnostics));
    try @import("glm.zig").run(cx, &altered, try lex.tokenize(a, "proc glm; class group; model y=group; lsmeans group /pdiff alpha=1e-20; run;", &diagnostics));
    try testing.expectEqualStrings(plain.items, altered.items);
}

test { _ = @import("glm_slice_tests.zig"); }
