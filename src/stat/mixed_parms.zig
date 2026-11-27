//! PARMS value lists, input data, grid evaluation and explicit covariance starts.
//! SAS/STAT15.4 physical pp.6668-6671; profiled grid example pp.6755-6757.
//! Grid rows retain supplied values separately from profiled covariance values.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const fit = @import("mixed_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Spec = struct { values: []const []const f64 = &.{}, data_name: ?[]const u8 = null, noiter: bool = false, noprint: bool = false, noprofile: bool = false, nobound: bool = false, ols: bool = false, ratios: bool = false, logdeth: bool = false, hold: []const usize = &.{}, lower: []const ?f64 = &.{}, upper: []const ?f64 = &.{}, line: usize = 0 };
const Reader = struct {
    cx: proc.ProcCtx,
    t: []const lex.Token,
    i: usize = 0,
    fn at(r: Reader, tag: lex.Tag) bool {
        return r.i < r.t.len and r.t[r.i].tag == tag;
    }
    fn is(r: Reader, s: []const u8) bool {
        return r.at(.name) and eq(r.t[r.i].text, s);
    }
    fn bad(r: Reader) diag.Error {
        return r.cx.diags.fail(error.ParseError, if (r.i < r.t.len) r.t[r.i].line else 0, "PROC MIXED: invalid PARMS value or option", .{});
    }
    fn number(r: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (r.at(.minus) or r.at(.plus)) {
            if (r.at(.minus)) sign = -1;
            r.i += 1;
        }
        if (!r.at(.number)) return r.bad();
        const v = sign * (std.fmt.parseFloat(f64, r.t[r.i].text) catch return r.bad());
        r.i += 1;
        if (!std.math.isFinite(v)) return r.bad();
        return v;
    }
    fn values(r: *Reader, paren: bool) diag.Error![]f64 {
        if (paren) {
            if (!r.at(.lparen)) return r.bad();
            r.i += 1;
        }
        var out: std.ArrayList(f64) = .empty;
        while (r.at(.number) or r.at(.minus) or r.at(.plus)) {
            const start = try r.number();
            var end = start;
            var step: f64 = 1;
            if (r.is("to")) {
                r.i += 1;
                end = try r.number();
                if (r.is("by")) {
                    r.i += 1;
                    step = try r.number();
                }
            }
            if (step == 0 or (end - start) * step < 0) return r.bad();
            const quotient = (end - start) / step;
            if (!std.math.isFinite(quotient) or quotient > 4095) return proc.failGap(r.cx.diags, 0, "PROC MIXED: PARMS value list exceeds the implemented 4096-value limit", .{});
            const count: usize = @intFromFloat(@floor(quotient + 64 * std.math.floatEps(f64) * @max(1, @abs(quotient))) + 1);
            for (0..count) |i| {
                var v = start + @as(f64, @floatFromInt(i)) * step;
                if (@abs(v - end) <= 64 * std.math.floatEps(f64) * @max(1, @abs(end))) v = end;
                try out.append(r.cx.arena, v);
            }
            if (r.at(.comma)) r.i += 1;
        }
        if (out.items.len == 0) return r.bad();
        if (paren) {
            if (!r.at(.rparen)) return r.bad();
            r.i += 1;
        }
        return out.items;
    }
    fn bounds(r: *Reader) diag.Error![]?f64 {
        var out: std.ArrayList(?f64) = .empty;
        while (r.at(.number) or r.at(.minus) or r.at(.plus) or r.at(.dot)) {
            if (r.at(.dot)) {
                try out.append(r.cx.arena, null);
                r.i += 1;
            } else try out.append(r.cx.arena, try r.number());
            if (r.at(.comma)) r.i += 1;
        }
        if (out.items.len == 0) return r.bad();
        return out.items;
    }
};
pub fn parse(cx: proc.ProcCtx, statements: anytype) diag.Error!?Spec {
    var result: ?Spec = null;
    for (statements) |statement| {
        if (statement.kind != .parms) continue;
        if (result != null) return cx.diags.fail(error.ParseError, statement.line, "PROC MIXED: only one PARMS statement is allowed", .{});
        var s = Spec{ .line = statement.line };
        var r = Reader{ .cx = cx, .t = statement.tokens };
        var lists: std.ArrayList([]const f64) = .empty;
        while (r.at(.lparen)) try lists.append(cx.arena, try r.values(true));
        s.values = lists.items;
        if (r.i < r.t.len) {
            if (!r.at(.slash)) return r.bad();
            r.i += 1;
        }
        while (r.i < r.t.len) {
            if (!r.at(.name)) return r.bad();
            const name = r.t[r.i].text;
            r.i += 1;
            if (eq(name, "noiter")) s.noiter = true else if (eq(name, "noprint")) s.noprint = true else if (eq(name, "noprofile")) s.noprofile = true else if (eq(name, "nobound")) s.nobound = true else if (eq(name, "ols")) s.ols = true else if (eq(name, "ratios")) s.ratios = true else if (eq(name, "logdeth")) s.logdeth = true else {
                if (!r.at(.eq)) return r.bad();
                r.i += 1;
                if (eq(name, "lowerb")) s.lower = try r.bounds() else if (eq(name, "upperb")) s.upper = try r.bounds() else if (eq(name, "hold") or eq(name, "eqcons")) {
                    const values = try r.values(r.at(.lparen));
                    const hold = try cx.arena.alloc(usize, values.len);
                    for (values, hold) |v, *index| {
                        if (v < 1 or v != @floor(v) or v > 1000000) return r.bad();
                        index.* = @intFromFloat(v - 1);
                    }
                    s.hold = hold;
                } else if (eq(name, "parmsdata") or eq(name, "pdata")) {
                    if (s.data_name != null) return proc.failGap(cx.diags, s.line, "PROC MIXED: repeated PARMSDATA is not verified", .{});
                    if (!r.at(.name)) return r.bad();
                    var data = r.t[r.i].text;
                    r.i += 1;
                    if (r.at(.dot)) {
                        r.i += 1;
                        if (!r.at(.name)) return r.bad();
                        data = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ data, r.t[r.i].text });
                        r.i += 1;
                    }
                    s.data_name = data;
                    if (r.at(.lparen)) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMSDATA data-set options are not implemented", .{});
                } else return r.bad();
            }
        }
        if (s.values.len == 0 and s.data_name == null and !s.ols and s.lower.len == 0 and s.upper.len == 0 and s.hold.len == 0 and !s.nobound) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: PARMS requires values or initialization options", .{});
        if (s.values.len > 0 and s.data_name != null) return proc.failGap(cx.diags, s.line, "PROC MIXED: simultaneous PARMS lists and PARMSDATA precedence is not verified", .{});
        if (s.ols and (s.values.len > 0 or s.data_name != null)) return proc.failGap(cx.diags, s.line, "PROC MIXED: OLS combined with explicit PARMS values is not verified", .{});
        result = s;
    }
    return result;
}
pub fn grid(cx: proc.ProcCtx, s: Spec, count: usize) diag.Error![]const []const f64 {
    if (s.lower.len > count or s.upper.len > count) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: too many PARMS boundary values", .{});
    for (s.hold) |i| if (i >= count) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: HOLD index exceeds covariance parameter count", .{});
    for (0..count) |i| {
        const lo = if (i < s.lower.len) s.lower[i] else null;
        const hi = if (i < s.upper.len) s.upper[i] else null;
        if (lo != null and hi != null and lo.? > hi.?) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: LOWERB exceeds UPPERB", .{});
    }
    if (s.data_name) |name| {
        const ds = cx.lib.find(name) orelse return cx.diags.fail(error.ParseError, s.line, "File {s} does not exist.", .{name});
        if (ds.rows.items.len > 4096) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMSDATA grid exceeds 4096 points", .{});
        var rows: std.ArrayList([]const f64) = .empty;
        if (ds.indexOf("Est")) |column| {
            if (ds.indexOf("CovP1") != null) return proc.failGap(cx.diags, s.line, "PROC MIXED: ambiguous Est and CovP columns in PARMSDATA", .{});
            if (ds.columns.items[column].type != .num or ds.rows.items.len != count) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: Est PARMSDATA must contain one numeric value per covariance parameter", .{});
            const point = try cx.arena.alloc(f64, count);
            for (ds.rows.items, point) |row, *value| {
                value.* = row[column].num;
                if (!std.math.isFinite(value.*)) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: missing/nonfinite PARMSDATA value", .{});
            }
            try rows.append(cx.arena, point);
        } else {
            const columns = try cx.arena.alloc(usize, count);
            for (columns, 0..) |*column, i| {
                column.* = ds.indexOf(try std.fmt.allocPrint(cx.arena, "CovP{d}", .{i + 1})) orelse return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: PARMSDATA lacks CovP{d}", .{i + 1});
                if (ds.columns.items[column.*].type != .num) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: PARMSDATA covariance values must be numeric", .{});
            }
            for (ds.rows.items) |row| {
                const point = try cx.arena.alloc(f64, count);
                for (columns, point) |column, *value| {
                    value.* = row[column].num;
                    if (!std.math.isFinite(value.*)) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: missing/nonfinite PARMSDATA value", .{});
                }
                try rows.append(cx.arena, point);
            }
        }
        if (rows.items.len == 0) return cx.diags.fail(error.ExecError, s.line, "PROC MIXED: PARMSDATA is empty", .{});
        return rows.items;
    }
    if (s.values.len != count) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: PARMS requires {d} covariance parameter lists", .{count});
    var total: usize = 1;
    for (s.values) |values| {
        total = std.math.mul(usize, total, values.len) catch return error.OutOfMemory;
        if (total > 4096) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS grid exceeds 4096 points", .{});
    }
    const rows = try cx.arena.alloc([]const f64, total);
    for (rows, 0..) |*row, index| {
        const point = try cx.arena.alloc(f64, count);
        var div = total;
        for (s.values, 0..) |values, i| {
            div /= values.len;
            point[i] = values[(index / div) % values.len];
        }
        row.* = point;
    }
    return rows;
}
pub const Point = struct { gls: fit.GLS, values: []f64, objective: f64, profile: bool };
fn constantResponse(model: fit.Model) bool {
    if (!model.has_intercept or model.y.len == 0) return false;
    for (model.y) |v| if (v != model.y[0]) return false;
    return true;
}
pub fn evaluatePoint(a: A, model: fit.Model, values: []const f64, profile: bool, method: fit.Method) !Point {
    if (profile and constantResponse(model)) return error.DegenerateResponse;
    var gls = try fit.knownCovariance(a, model, values);
    const adjusted = try a.dupe(f64, values);
    if (profile) {
        const df = @as(f64, @floatFromInt(if (method == .reml) model.n - gls.rank else model.n));
        if (!(df > 0)) return error.DegenerateResponse;
        const scale = gls.quadratic / df;
        if (!(scale > 0) or !std.math.isFinite(scale)) return error.DegenerateResponse;
        const change = gls.quadratic / scale - gls.quadratic;
        gls.minus2reml += @as(f64, @floatFromInt(model.n - gls.rank)) * @log(scale) + change;
        gls.minus2ml += @as(f64, @floatFromInt(model.n)) * @log(scale) + change;
        gls.quadratic /= scale;
        for (adjusted) |*v| v.* *= scale;
        for (gls.covariance) |*v| v.* *= scale;
    }
    return .{ .gls = gls, .values = adjusted, .objective = if (method == .reml) gls.minus2reml else gls.minus2ml, .profile = profile };
}
pub const Row = struct { values: []const f64, objective: ?f64, residual: ?f64 };
pub const Result = struct { fit: fit.Fit, rows: []const Row, profile: bool, likelihood_ratio: ?@import("mixed_render.zig").LikelihoodRatio = null };
fn admissible(s: Spec, values: []const f64) bool {
    for (values, 0..) |v, i| {
        const lower: f64 = if (i < s.lower.len and s.lower[i] != null) s.lower[i].? else if (s.nobound) -std.math.inf(f64) else 0;
        const upper = if (i < s.upper.len and s.upper[i] != null) s.upper[i].? else std.math.inf(f64);
        if (v < lower or v > upper) return false;
    }
    return true;
}
pub fn execute(cx: proc.ProcCtx, model: fit.Model, s: Spec, options: fit.Options, proc_noprofile: bool) diag.Error!Result {
    if (model.n == 0 or model.n > 512) return cx.diags.fail(error.ExecError, s.line, "PROC MIXED: invalid PARMS model dimensions", .{});
    if (s.logdeth) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS LOGDETH is not implemented", .{});
    const raw = proc_noprofile or s.noprofile or s.hold.len > 0;
    if (!raw and constantResponse(model)) return proc.failGap(cx.diags, s.line, "PROC MIXED: a constant response has no finite positive residual-profile optimum", .{});
    if (!s.noiter and (raw or s.lower.len > 0 or s.upper.len > 0 or s.nobound)) return proc.failGap(cx.diags, s.line, "PROC MIXED: iterative PARMS bounds/HOLD/NOBOUND or unprofiled optimization are not implemented", .{});
    if (!raw and (s.lower.len > 0 or s.upper.len > 0 or s.hold.len > 0 or s.nobound)) return proc.failGap(cx.diags, s.line, "PROC MIXED: profile-coupled PARMS boundary constraints are not implemented; explicit unprofiled NOITER values are supported", .{});
    if (s.ols) {
        if (s.noiter or s.ratios) return proc.failGap(cx.diags, s.line, "PROC MIXED: OLS with NOITER/RATIOS is not verified", .{});
        var o = options;
        o.ols_start = true;
        const result = fit.fit(cx.arena, model, o) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED: OLS initialization failed ({t})", .{err});
        return .{ .fit = result, .rows = &.{}, .profile = true };
    }
    if (s.values.len == 0 and s.data_name == null) return proc.failGap(cx.diags, s.line, "PROC MIXED: boundary-only PARMS default initialization is not implemented", .{});
    const candidates = try grid(cx, s, model.components.len + 1);
    if (candidates.len > 2_000_000 / (model.n * model.n)) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS dense grid workspace limit exceeded", .{});
    var rows: std.ArrayList(Row) = .empty;
    var best: ?Point = null;
    for (candidates) |values| {
        if (s.ratios and values[values.len - 1] != 1) return proc.failGap(cx.diags, s.line, "PROC MIXED: RATIOS with a nonunit residual entry is not verified", .{});
        if (!admissible(s, values)) {
            try rows.append(cx.arena, .{ .values = values, .objective = null, .residual = null });
            continue;
        }
        const value = evaluatePoint(cx.arena, model, values, !raw, options.method) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidInput, error.NotPositiveDefinite, error.DegenerateResponse => {
                try rows.append(cx.arena, .{ .values = values, .objective = null, .residual = null });
                continue;
            },
            else => return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS point cannot be evaluated ({t})", .{err}),
        };
        try rows.append(cx.arena, .{ .values = values, .objective = value.objective, .residual = value.values[value.values.len - 1] });
        if (best == null or value.objective < best.?.objective) best = value;
    }
    const chosen = best orelse return cx.diags.fail(error.ExecError, s.line, "PROC MIXED: no feasible PARMS grid point satisfies bounds and positive definite covariance", .{});
    if (s.noiter) {
        const g = chosen.gls;
        return .{ .fit = .{ .n = g.n, .p = g.p, .rank = g.rank, .independent = g.independent, .coefficients = g.coefficients, .covariance = g.covariance, .alias_coefficients = g.alias_coefficients, .variances = chosen.values, .residual_variance = chosen.values[chosen.values.len - 1], .minus2loglik = chosen.objective, .aic = std.math.nan(f64), .aicc = null, .bic = null, .iterations = &.{}, .converged = false, .status = .evaluated, .method = options.method, .df_error = g.df_error }, .rows = rows.items, .profile = !raw };
    }
    var o = options;
    o.start = chosen.values;
    const fitted = fit.fit(cx.arena, model, o) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS initialized optimization failed ({t})", .{err});
    var lrt: ?@import("mixed_render.zig").LikelihoodRatio = null;
    const regular = model.components.len > 0 and for (chosen.values[0..model.components.len], fitted.variances[0..model.components.len]) |initial_value, final_value| {
        if (initial_value <= 0 or final_value <= 0) break false;
    } else true;
    if (regular and fitted.converged) {
        const statistic = @max(0, chosen.objective - fitted.minus2loglik);
        lrt = .{ .df = model.components.len, .statistic = statistic, .p = 1 - @import("../functions.zig").gammaP(@as(f64, @floatFromInt(model.components.len)) / 2, statistic / 2) };
    }
    return .{ .fit = fitted, .rows = rows.items, .profile = true, .likelihood_ratio = lrt };
}
pub fn renderSearch(a: A, out: *std.ArrayList(u8), result: Result, s: Spec) !void {
    if (s.noprint or result.rows.len == 0) return;
    try out.appendSlice(a, "\nParameter Search\n\n");
    for (0..result.rows[0].values.len) |i| try out.print(a, "CovP{d} ", .{i + 1});
    if (result.profile) try out.appendSlice(a, "Variance ");
    try out.appendSlice(a, if (result.fit.method == .reml) "Res Log Like -2 Res Log Like\n" else "Log Like -2 Log Like\n");
    for (result.rows) |row| {
        for (row.values) |v| try out.print(a, "{d:.4} ", .{v});
        if (result.profile) {
            if (row.residual) |v| try out.print(a, "{d:.4} ", .{v}) else try out.appendSlice(a, ". ");
        }
        if (row.objective) |v| try out.print(a, "{d:.4} {d:.4}\n", .{ -v / 2, v }) else try out.appendSlice(a, ". .\n");
    }
}
test {
    _ = @import("mixed_parms_tests.zig");
}
