//! MIXED population margins use full fixed X and the fitted GLS covariance.
//! S154 physical pp.6646-6652: effect-specific denominator DF, not ESTIMATE's
//! last-listed-effect convention. No residual covariance is substituted here.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const coded = @import("design_matrix.zig");
const linear = @import("mixed_contrasts_kernel.zig");
const comparison = @import("lsmeans_inference.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { effect: usize, line: usize = 0, alpha: f64 = 0.05, cl: bool = false, diff: bool = false, adjust: comparison.Adjustment = .none, df: ?f64 = null, singular: f64 = 1e-4 };
pub const Mean = struct { request: usize, effect: usize, name: []const u8, levels: []const ?usize, coefficients: []const f64, inference: linear.Estimate };
pub const Difference = struct { request: usize, left: usize, right: usize, inference: linear.Estimate, adjusted_p: ?f64 = null, lower: ?f64 = null, upper: ?f64 = null };
pub const Result = struct { means: []const Mean, differences: []const Difference, used_classes: []const usize };
fn bad(cx: proc.ProcCtx, line: usize, comptime text: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC MIXED LSMEANS: " ++ text, .{});
}
fn token(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
pub fn parse(cx: proc.ProcCtx, m: model.Spec, statements: anytype) diag.Error![]const Request {
    var result: std.ArrayList(Request) = .empty;
    for (statements) |statement| if (statement.kind == .lsmeans) {
        const t = statement.tokens;
        var slash: usize = 0;
        while (slash < t.len and !token(t, slash, .slash)) slash += 1;
        if (slash == 0) return bad(cx, statement.line, "at least one fixed CLASS effect is required");
        var expanded: std.ArrayList(coded.Effect) = .empty;
        try model.effects(cx, m.source, t[0..slash], &expanded);
        var request: Request = .{ .effect = 0, .line = statement.line };
        var i = if (slash < t.len) slash + 1 else slash;
        while (i < t.len) {
            if (!token(t, i, .name)) return bad(cx, statement.line, "invalid option");
            const name = t[i].text;
            i += 1;
            if (eq(name, "cl")) {
                request.cl = true;
                continue;
            }
            if (eq(name, "diff") or eq(name, "pdiff")) {
                request.diff = true;
                if (token(t, i, .eq)) {
                    i += 1;
                    if (!token(t, i, .name)) return bad(cx, statement.line, "comparison type is required");
                    if (!eq(t[i].text, "all")) {
                        for ([_][]const u8{ "control", "controll", "controlu" }) |known| if (eq(t[i].text, known)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: control LS-mean comparisons are not implemented", .{});
                        return bad(cx, statement.line, "invalid DIFF type");
                    }
                    i += 1;
                }
                continue;
            }
            if (eq(name, "adjust")) {
                if (!token(t, i, .eq) or !token(t, i + 1, .name)) return bad(cx, statement.line, "ADJUST requires a method");
                i += 1;
                const method = t[i].text;
                i += 1;
                request.adjust = if (eq(method, "bon")) .bon else if (eq(method, "sidak")) .sidak else if (eq(method, "tukey")) .tukey else {
                    for ([_][]const u8{ "dunnett", "scheffe", "simulate", "sim", "smm", "gt2" }) |known| if (eq(method, known)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: ADJUST={s} LS-means inference is not implemented", .{method});
                    return bad(cx, statement.line, "invalid ADJUST method");
                };
                request.diff = true;
                continue;
            }
            if (eq(name, "adjdfe")) {
                if (!token(t, i, .eq) or !token(t, i + 1, .name)) return bad(cx, statement.line, "ADJDFE requires SOURCE or ROW");
                i += 1;
                if (eq(t[i].text, "row")) return proc.failGap(cx.diags, statement.line, "PROC MIXED: rowwise LS-means DF adjustment is not implemented", .{});
                if (!eq(t[i].text, "source")) return bad(cx, statement.line, "invalid ADJDFE method");
                i += 1;
                continue;
            }
            if (eq(name, "alpha") or eq(name, "df") or eq(name, "singular")) {
                if (!token(t, i, .eq) or !token(t, i + 1, .number)) return bad(cx, statement.line, "numeric option requires =number");
                i += 1;
                const v = std.fmt.parseFloat(f64, t[i].text) catch return bad(cx, statement.line, "invalid number");
                i += 1;
                if (!std.math.isFinite(v) or v <= 0 or (!eq(name, "df") and v >= 1)) return bad(cx, statement.line, "invalid ALPHA/DF/SINGULAR value");
                if (eq(name, "df")) request.df = v else if (eq(name, "singular")) request.singular = v else {
                    request.alpha = v;
                    request.cl = true;
                }
                continue;
            }
            for ([_][]const u8{ "at", "bylevel", "corr", "cov", "e", "om", "obsmargins", "slice" }) |known| if (eq(name, known)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: LSMEANS option {s} is not implemented", .{name});
            return bad(cx, statement.line, "unknown option");
        }
        for (expanded.items) |effect| {
            const normalized = try coded.normalize(cx.arena, m.source, m.matrix.classes, effect);
            if (normalized.continuous.len > 0) return bad(cx, statement.line, "LS-means require CLASS-only effects");
            var found: ?usize = null;
            for (m.matrix.effects, 0..) |candidate, j| {
                const name = try coded.normalize(cx.arena, m.source, m.matrix.classes, candidate);
                if (eq(name.name, normalized.name)) {
                    found = j;
                    break;
                }
            }
            var item = request;
            item.effect = found orelse return bad(cx, statement.line, "effect is not in MODEL");
            var duplicate = false;
            for (result.items) |prior| if (prior.effect == item.effect and std.meta.eql(prior, item)) {
                duplicate = true;
            };
            if (!duplicate) try result.append(cx.arena, item);
        }
    };
    return result.items;
}
fn compatible(target: []const ?usize, column: []const ?usize) bool {
    for (target, column) |t, c| if (t != null and c != null and t.? != c.?) return false;
    return true;
}
pub const Coefficients = struct { levels: []const ?usize, l: []const f64, name: []const u8 };
pub fn coefficients(cx: proc.ProcCtx, m: model.Spec, x: fixed.Design, effect_index: usize) diag.Error![]const Coefficients {
    var rows: std.ArrayList(Coefficients) = .empty;
    for (m.matrix.effects) |effect| if (effect.nested.len > 0) return proc.failGap(cx.diags, m.line, "PROC MIXED: nested LS-mean population weights are not implemented", .{});
    for (x.matrix.columns) |target| {
        if (target.effect_index == null or target.effect_index.? != effect_index) continue;
        const l = try cx.arena.alloc(f64, x.matrix.p);
        for (x.matrix.columns, 0..) |column, j| {
            if (column.effect_index == null) {
                l[j] = 1;
                continue;
            }
            const effect = m.matrix.effects[column.effect_index.?];
            var categorical = false;
            var continuous = false;
            for (effect.factors) |ci| if (std.mem.indexOfScalar(usize, m.matrix.classes, ci) != null) {
                categorical = true;
            } else {
                continuous = true;
            };
            if (categorical and continuous) return proc.failGap(cx.diags, m.line, "PROC MIXED: covariate-by-CLASS LS-mean construction is not implemented", .{});
            if (!categorical) {
                var sum: f64 = 0;
                for (0..x.matrix.n) |r| sum += x.matrix.x[r * x.matrix.p + j];
                l[j] = sum / @as(f64, @floatFromInt(x.matrix.n));
            } else if (!compatible(target.class_values, column.class_values)) l[j] = 0 else {
                var count: usize = 0;
                for (x.matrix.columns) |other| if (other.effect_index == column.effect_index and compatible(target.class_values, other.class_values)) {
                    count += 1;
                };
                l[j] = 1 / @as(f64, @floatFromInt(count));
            }
        }
        try rows.append(cx.arena, .{ .levels = target.class_values, .l = l, .name = target.effect_name });
    }
    return rows.items;
}
pub fn compute(cx: proc.ProcCtx, m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, requests: []const Request) diag.Error!Result {
    const j = linear.Joint{ .p = x.matrix.p, .q = 0, .coefficients = fitted.coefficients, .covariance = fitted.covariance, .aliases = fitted.alias_coefficients };
    var means: std.ArrayList(Mean) = .empty;
    var diffs: std.ArrayList(Difference) = .empty;
    const used = try cx.arena.alloc(bool, x.matrix.classes.len);
    @memset(used, false);
    for (requests, 0..) |request, index| {
        const rows = try coefficients(cx, m, x, request.effect);
        if (request.diff and request.adjust == .tukey and rows.len > 2) return proc.failGap(cx.diags, request.line, "PROC MIXED: Tukey studentized-range inference beyond two LS-means is not implemented", .{});
        if (request.df == null and m.has_repeated and z.components.len == 0 and m.options.ddfm == .default) return proc.failGap(cx.diags, request.line, "PROC MIXED: default between-within LS-means DF is not implemented", .{});
        const df: f64 = if (request.df) |v| v else if (m.options.ddfm == .residual or z.components.len == 0) @floatFromInt(fitted.df_error) else @floatFromInt(try random.containmentDF(cx, r, x.matrix, z, request.effect, x.weights, m.options.singular));
        const start = means.items.len;
        for (rows) |row| {
            for (row.levels, 0..) |level, k| if (level != null) {
                used[k] = true;
            };
            const value = linear.estimate(j, row.l, df, request.alpha, .two, request.singular) catch |err| return proc.failGap(cx.diags, request.line, "PROC MIXED: LS-mean numerical boundary is not implemented ({t})", .{err});
            try means.append(cx.arena, .{ .request = index, .effect = request.effect, .name = row.name, .levels = row.levels, .coefficients = row.l, .inference = value });
        }
        if (request.diff) for (rows, 0..) |left, i| for (i + 1..rows.len) |k| {
            const l = try cx.arena.alloc(f64, x.matrix.p);
            for (l, left.l, rows[k].l) |*v, a, b| v.* = a - b;
            const value = linear.estimate(j, l, df, request.alpha, .two, request.singular) catch |err| return proc.failGap(cx.diags, request.line, "PROC MIXED: LS-mean difference boundary is not implemented ({t})", .{err});
            var item: Difference = .{ .request = index, .left = start + i, .right = start + k, .inference = value };
            if (value.p) |p| item.adjusted_p = comparison.probability(p, rows.len, request.adjust) catch return proc.failGap(cx.diags, request.line, "PROC MIXED: comparison adjustment is not implemented", .{});
            if (value.estimable and value.se != null and request.cl) {
                const critical = comparison.critical(df, request.alpha, rows.len, request.adjust) catch return proc.failGap(cx.diags, request.line, "PROC MIXED: adjusted critical value is not implemented", .{});
                item.lower = value.estimate.? - critical * value.se.?;
                item.upper = value.estimate.? + critical * value.se.?;
            }
            try diffs.append(cx.arena, item);
        };
    }
    var classes: std.ArrayList(usize) = .empty;
    for (used, 0..) |yes, i| if (yes) try classes.append(cx.arena, i);
    return .{ .means = means.items, .differences = diffs.items, .used_classes = classes.items };
}

pub fn publishRouted(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, requests: []const Request, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    if (requests.len == 0) return;
    const result = try compute(cx, m, r, x, z, fitted, requests);
    try @import("mixed_lsmeans_render.zig").render(cx, out, m, x, result, requests, route);
}
