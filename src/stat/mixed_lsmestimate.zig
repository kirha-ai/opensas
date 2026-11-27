//! MIXED LSMESTIMATE: K weights LS-means, L=K*L1 weights fixed parameters.
//! S154 physical pp.510-522; GLM is explicitly outside the shared applicability.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const ls = @import("mixed_lsmeans.zig");
const coded = @import("design_matrix.zig");
const linear = @import("mixed_contrasts_kernel.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Row = struct { label: []const u8, values: []const f64, divisor: f64 = 1, explicit_label: bool = false };
pub const Request = struct { effect: usize, name: []const u8, line: usize, rows: []const Row, divisors: []const f64 = &.{1}, df: ?f64 = null, alpha: f64 = 0.05, cl: bool = false, singular: f64 = 1e-4, adjust: enum { none, bon, sidak } = .none, tail: linear.Tail = .two, joint: bool = false, joint_only: bool = false, joint_label: ?[]const u8 = null };
pub const Estimate = struct { label: []const u8, k: []const f64, l: []const f64, inference: linear.Estimate, adjusted_p: ?f64 = null, adjusted_lower: ?f64 = null, adjusted_upper: ?f64 = null };
pub const Result = struct { request: Request, rows: []const Estimate, joint: ?linear.Contrast = null };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, line: usize, comptime message: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC MIXED LSMESTIMATE: " ++ message, .{});
}
fn numeric(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, line: usize, missing: bool) diag.Error!?f64 {
    if (missing and at(t, i.*, .dot)) {
        i.* += 1;
        return null;
    }
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return bad(cx, line, "expected a finite number");
    const value = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return bad(cx, line, "invalid number"));
    i.* += 1;
    if (!std.math.isFinite(value)) return bad(cx, line, "number must be finite");
    return value;
}
pub fn parse(cx: proc.ProcCtx, m: model.Spec, statements: anytype) diag.Error![]const Request {
    var requests: std.ArrayList(Request) = .empty;
    for (statements) |statement| if (statement.kind == .lsmestimate) {
        const t = statement.tokens;
        var i: usize = 0;
        var variables: std.ArrayList(usize) = .empty;
        while (true) {
            if (!at(t, i, .name)) return bad(cx, statement.line, "one MODEL CLASS effect is required");
            const ci = m.source.indexOf(t[i].text) orelse return bad(cx, statement.line, "effect variable not found");
            if (std.mem.indexOfScalar(usize, m.matrix.classes, ci) == null) return bad(cx, statement.line, "effect must contain only CLASS variables");
            try variables.append(cx.arena, ci);
            i += 1;
            if (!at(t, i, .star)) break;
            i += 1;
        }
        if (at(t, i, .lparen) or at(t, i, .pipe)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: nested/bar LSMESTIMATE effect specification is not implemented", .{});
        const normal = try coded.normalize(cx.arena, m.source, m.matrix.classes, .{ .factors = variables.items });
        var effect: ?usize = null;
        for (m.matrix.effects, 0..) |candidate, index| {
            const n = try coded.normalize(cx.arena, m.source, m.matrix.classes, candidate);
            if (eq(n.name, normal.name)) {
                effect = index;
                break;
            }
        }
        var rows: std.ArrayList(Row) = .empty;
        while (i < t.len and !at(t, i, .slash)) {
            var row: Row = .{ .label = try std.fmt.allocPrint(cx.arena, "Row {d}", .{rows.items.len + 1}), .values = &.{} };
            if (at(t, i, .string)) {
                row.label = t[i].text;
                row.explicit_label = true;
                i += 1;
            }
            if (at(t, i, .lbrace)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: nonpositional LSMESTIMATE coefficients are not implemented", .{});
            var values: std.ArrayList(f64) = .empty;
            while (at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus)) try values.append(cx.arena, (try numeric(cx, t, &i, statement.line, false)).?);
            if (values.items.len == 0) return bad(cx, statement.line, "row requires coefficients");
            row.values = values.items;
            if (at(t, i, .name) and eq(t[i].text, "divisor")) {
                i += 1;
                if (!at(t, i, .eq)) return bad(cx, statement.line, "row DIVISOR requires =number");
                i += 1;
                row.divisor = (try numeric(cx, t, &i, statement.line, true)) orelse 1;
                if (row.divisor == 0) return bad(cx, statement.line, "DIVISOR must be nonzero");
            }
            try rows.append(cx.arena, row);
            if (i == t.len or at(t, i, .slash)) break;
            if (!at(t, i, .comma)) return bad(cx, statement.line, "expected comma or options slash");
            i += 1;
            if (i == t.len or at(t, i, .slash)) return bad(cx, statement.line, "empty estimate row");
        }
        if (rows.items.len == 0) return bad(cx, statement.line, "at least one estimate row is required");
        var request: Request = .{ .effect = effect orelse return bad(cx, statement.line, "effect is not in MODEL"), .name = normal.name, .line = statement.line, .rows = rows.items };
        if (at(t, i, .slash)) i += 1;
        while (i < t.len) {
            if (!at(t, i, .name)) return bad(cx, statement.line, "invalid option");
            const option = t[i].text;
            i += 1;
            if (eq(option, "cl")) {
                request.cl = true;
                continue;
            }
            if (eq(option, "joint")) {
                request.joint = true;
                if (at(t, i, .lparen)) {
                    i += 1;
                    while (i < t.len and !at(t, i, .rparen)) {
                        if (at(t, i, .name) and (eq(t[i].text, "only") or eq(t[i].text, "noest"))) {
                            request.joint_only = true;
                            i += 1;
                        } else if (at(t, i, .name) and eq(t[i].text, "label")) {
                            i += 1;
                            if (!at(t, i, .eq) or !at(t, i + 1, .string)) return bad(cx, statement.line, "JOINT LABEL requires a quoted label");
                            request.joint_label = t[i + 1].text;
                            i += 2;
                        } else return proc.failGap(cx.diags, statement.line, "PROC MIXED: this JOINT option is not implemented", .{});
                    }
                    if (!at(t, i, .rparen)) return bad(cx, statement.line, "unterminated JOINT options");
                    i += 1;
                }
                continue;
            }
            if (eq(option, "lower") or eq(option, "lowertailed") or eq(option, "upper") or eq(option, "uppertailed")) {
                const tail: linear.Tail = if (eq(option, "lower") or eq(option, "lowertailed")) .lower else .upper;
                if (request.tail != .two and request.tail != tail) return bad(cx, statement.line, "LOWER and UPPER cannot be combined");
                request.tail = tail;
                continue;
            }
            if (eq(option, "adjust")) {
                if (!at(t, i, .eq) or !at(t, i + 1, .name)) return bad(cx, statement.line, "ADJUST requires a method");
                const name = t[i + 1].text;
                i += 2;
                request.adjust = if (eq(name, "t")) .none else if (eq(name, "bon")) .bon else if (eq(name, "sidak")) .sidak else {
                    for ([_][]const u8{ "scheffe", "simulate", "sim" }) |known| if (eq(name, known)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: LSMESTIMATE adjustment {s} is not implemented", .{name});
                    return bad(cx, statement.line, "invalid LSMESTIMATE adjustment");
                };
                continue;
            }
            if (eq(option, "divisor")) {
                if (!at(t, i, .eq)) return bad(cx, statement.line, "DIVISOR requires a list");
                i += 1;
                var values: std.ArrayList(f64) = .empty;
                while (at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus) or at(t, i, .dot)) {
                    const v = (try numeric(cx, t, &i, statement.line, true)) orelse 1;
                    if (v == 0) return bad(cx, statement.line, "DIVISOR must be nonzero");
                    try values.append(cx.arena, v);
                    if (at(t, i, .comma)) {
                        i += 1;
                        if (!(at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus) or at(t, i, .dot))) return bad(cx, statement.line, "missing divisor after comma");
                    }
                }
                if (values.items.len == 0) return bad(cx, statement.line, "empty divisor list");
                request.divisors = values.items;
                continue;
            }
            if (eq(option, "alpha") or eq(option, "df") or eq(option, "singular")) {
                if (!at(t, i, .eq)) return bad(cx, statement.line, "option requires =number");
                i += 1;
                const v = (try numeric(cx, t, &i, statement.line, false)).?;
                if (v <= 0 or (!eq(option, "df") and v >= 1)) return bad(cx, statement.line, "invalid ALPHA/DF/SINGULAR value");
                if (eq(option, "df")) request.df = v else if (eq(option, "alpha")) {
                    request.alpha = v;
                    request.cl = true;
                } else request.singular = v;
                continue;
            }
            for ([_][]const u8{ "adjdfe", "at", "bylevel", "om", "obsmargins", "e", "elsm", "stepdown", "testvalue", "testmean", "chisq", "cov", "corr", "seed", "plot", "plots" }) |known| if (eq(option, known)) return proc.failGap(cx.diags, statement.line, "PROC MIXED: LSMESTIMATE option {s} is not implemented", .{option});
            // The common chapter explicitly excludes MIXED from EXP/ILINK/CATEGORY.
            // PLOTS remains a gap: the MIXED summary lists it, while common
            // graphical details describe only Bayesian consumers.
            return bad(cx, statement.line, "unknown or inapplicable LSMESTIMATE option");
        }
        if (request.joint and request.tail != .two) return proc.failGap(cx.diags, statement.line, "PROC MIXED: order-restricted joint LSMESTIMATE tests are not implemented", .{});
        try requests.append(cx.arena, request);
    };
    return requests.items;
}
pub fn compute(cx: proc.ProcCtx, m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, request: Request) diag.Error!Result {
    const margins = try ls.coefficients(cx, m, x, request.effect);
    const p = x.matrix.p;
    const joint = linear.Joint{ .p = p, .q = 0, .coefficients = fitted.coefficients, .covariance = fitted.covariance, .aliases = fitted.alias_coefficients };
    if (request.df == null and m.has_repeated and z.components.len == 0 and m.options.ddfm == .default) return proc.failGap(cx.diags, request.line, "PROC MIXED: default between-within LSMESTIMATE DF is not implemented", .{});
    const df: f64 = if (request.df) |v| v else if (m.options.ddfm == .residual or z.components.len == 0) @floatFromInt(fitted.df_error) else @floatFromInt(try random.containmentDF(cx, r, x.matrix, z, request.effect, x.weights, m.options.singular));
    const rows = try cx.arena.alloc(Estimate, request.rows.len);
    const joint_l = try cx.arena.alloc(f64, rows.len * p);
    @memset(joint_l, 0);
    for (request.rows, 0..) |row, index| {
        const divisor = row.divisor * request.divisors[@min(index, request.divisors.len - 1)];
        if (!std.math.isFinite(divisor) or divisor == 0) return bad(cx, request.line, "invalid combined divisor");
        const k = try cx.arena.alloc(f64, margins.len);
        @memset(k, 0);
        const l = joint_l[index * p ..][0..p];
        for (margins, 0..) |margin, j| {
            k[j] = (if (j < row.values.len) row.values[j] else 0) / divisor;
            if (!std.math.isFinite(k[j])) return bad(cx, request.line, "coefficient overflow");
            for (l, margin.l) |*v, coefficient| v.* += k[j] * coefficient;
        }
        if (row.values.len > margins.len) try cx.diags.warn(request.line, "PROC MIXED: extra LSMESTIMATE coefficients are ignored", .{});
        var inferred = linear.estimateWithLimits(joint, l, df, request.alpha, request.tail, request.singular, request.cl) catch |err| return proc.failGap(cx.diags, request.line, "PROC MIXED: LSMESTIMATE inference boundary is not implemented ({t})", .{err});
        if (inferred.estimable and inferred.se != null and inferred.se.? == 0 and request.cl) {
            if (request.tail != .lower) inferred.lower = inferred.estimate;
            if (request.tail != .upper) inferred.upper = inferred.estimate;
        }
        rows[index] = .{ .label = row.label, .k = k, .l = l, .inference = inferred };
        if (request.adjust != .none) {
            if (!inferred.estimable) return proc.failGap(cx.diags, request.line, "PROC MIXED: multiplicity with nonestimable LSMESTIMATE rows is not verified", .{});
            if (inferred.p) |raw| {
                const count: f64 = @floatFromInt(rows.len);
                rows[index].adjusted_p = if (request.adjust == .bon) @min(1, raw * count) else if (raw == 1) 1 else -std.math.expm1(count * std.math.log1p(-raw));
                if (request.cl and inferred.se != null) {
                    const a = if (request.adjust == .bon) request.alpha / count else -std.math.expm1(std.math.log1p(-request.alpha) / count);
                    const adjusted = linear.estimateWithLimits(joint, l, df, a, request.tail, request.singular, true) catch return proc.failGap(cx.diags, request.line, "PROC MIXED: adjusted LSMESTIMATE confidence interval is unavailable", .{});
                    rows[index].adjusted_lower = adjusted.lower;
                    rows[index].adjusted_upper = adjusted.upper;
                }
            }
        }
    }
    const combined = if (request.joint) linear.contrast(cx.arena, joint, joint_l, rows.len, df, request.singular) catch |err| return proc.failGap(cx.diags, request.line, "PROC MIXED: joint LSMESTIMATE boundary is unavailable ({t})", .{err}) else null;
    return .{ .request = request, .rows = rows, .joint = combined };
}

pub fn publishRouted(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, requests: []const Request, route: ?*@import("mixed_ods_route.zig").Router) diag.Error!void {
    if (requests.len == 0) return;
    const results = try cx.arena.alloc(Result, requests.len);
    for (requests, results) |request, *result| result.* = try compute(cx, m, r, x, z, fitted, request);
    try @import("mixed_lsmestimate_render.zig").render(cx, out, results, route);
}
