//! PROC ROBUSTREG declarations, variable roles, observation selection and the
//! default M-estimation listing, SAS/STAT 15.4 Chapter 107 (physical
//! pp.8784-8792 PROC statement, 8792 BY, 8793-8794 ID, 8799 WEIGHT; the M
//! estimator pp.8788-8793 of the chapter text).
//!
//! METHOD=M: iteratively reweighted least squares from the unweighted least
//! squares start with the bisquare weight function, the SCALE=MED scale step
//! sigma = median|r_i| / Phi^-1(0.75) after every location step, the H1
//! asymptotic covariance K^2 [sum psi^2/(n-p)] / [(1/n) sum psi']^2 sigma^2
//! (X'X)^-1, K = 1 + p/n Var(psi')/(E psi')^2, the robust R-square against
//! the location-scale M estimate, AICR/BICR and the deviance 2 s^2 sum rho.
//! Every number of the default listing was checked against the SAS 9.4
//! reference for the chapter's stack-loss data. Everything else (LEVERAGE /
//! MCD, TEST, LTS/S/MM, other weight functions and scales, PLOTS, OUTPUT,
//! CLASS) is a D-009 gap (rc 2) raised before any
//! listing text of the step is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fns = @import("../functions.zig");
const by = @import("by_groups.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

/// Phi^-1(0.75): the SCALE=MED consistency constant (p.8789).
pub const beta0: f64 = 0.6744897501960817;

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    namelen: usize = 20,
    /// Bisquare tuning constant (WF=BISQUARE(C=), Table 107.5 default).
    c: f64 = 4.685,
    eps: f64 = 1e-8,
    maxiter: usize = 1000,
    response: usize = 0,
    regressors: []const usize = &.{},
    alpha: f64 = 0.05,
    cutoff: f64 = 3,
    singular: f64 = 1e-8,
    diagnostics: bool = false,
    ids: []const usize = &.{},
    weight: ?usize = null,
    weight_line: usize = 0,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC ROBUSTREG: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC ROBUSTREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus)) {
        sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * x;
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC ROBUSTREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

/// Statements owned by later ROBUSTREG tickets.
const later_statements = [_][]const u8{ "class", "effect", "output", "test", "performance", "store", "estimate", "lsmeans" };

/// `METHOD=M<(options)>` (p.8788): only the reference-verified bisquare /
/// SCALE=MED / ASYMPCOV=H1 / CONVERGENCE=COEF path.
fn methodM(cx: proc.ProcCtx, t: []const lex.Token, start: usize, s: *Spec) diag.Error!usize {
    var i = start;
    if (!at(t, i, .lparen)) return i;
    i += 1;
    while (!at(t, i, .rparen)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if ((eq(word, "wf") or eq(word, "weightfunction")) and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const f = t[i + 2].text;
            if (!eq(f, "bisquare")) {
                if (oneOf(f, &.{ "andrews", "cauchy", "fair", "hampel", "huber", "logistic", "median", "talworth", "welsch" })) return gap(cx, t[i].line, "WF={s} is not implemented", .{f});
                return invalid(cx, t, i + 2);
            }
            i += 3;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "c") or !at(t, i + 2, .eq)) return invalid(cx, t, i + 1);
                i += 3;
                const x = try number(cx, t, &i);
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: the weight function constant C= must be positive", .{});
                s.c = x;
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (eq(word, "scale") and at(t, i + 1, .eq)) {
            if (!kw(t, i + 2, "med")) return gap(cx, t[i].line, "SCALE= other than MED is not implemented", .{});
            i += 3;
        } else if (eq(word, "asympcov") and at(t, i + 1, .eq)) {
            if (!kw(t, i + 2, "h1")) {
                if (kw(t, i + 2, "h2") or kw(t, i + 2, "h3")) return gap(cx, t[i].line, "ASYMPCOV={s} is not implemented", .{t[i + 2].text});
                return invalid(cx, t, i + 2);
            }
            i += 3;
        } else if (eq(word, "convergence") and at(t, i + 1, .eq)) {
            if (!kw(t, i + 2, "coef")) {
                if (kw(t, i + 2, "resid") or kw(t, i + 2, "weight")) return gap(cx, t[i].line, "CONVERGENCE={s} is not implemented", .{t[i + 2].text});
                return invalid(cx, t, i + 2);
            }
            i += 3;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "eps") or !at(t, i + 2, .eq)) return invalid(cx, t, i + 1);
                i += 3;
                const x = try number(cx, t, &i);
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: EPS= must be positive", .{});
                s.eps = x;
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (eq(word, "maxiter") and at(t, i + 1, .eq)) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x >= 1 and x == @trunc(x) and x < 1e9)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: MAXITER= must be a positive integer", .{});
            s.maxiter = @intFromFloat(x);
        } else if (oneOf(word, &.{ "nobias", "biastest", "inith", "initest", "k0", "efficiency" })) {
            return gap(cx, t[i].line, "METHOD=M option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    return i + 1;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            qualified = null;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "method") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const m = t[i + 2].text;
            if (oneOf(m, &.{ "lts", "s", "mm" })) return gap(cx, t[i].line, "METHOD={s} (subsampling estimation) is not implemented", .{m});
            if (!eq(m, "m")) return invalid(cx, t, i + 2);
            i = try methodM(cx, t, i + 3, &s);
        } else if (eq(word, "namelen") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x >= 20 and x <= 200 and x == @trunc(x))) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: NAMELEN= must be an integer between 20 and 200", .{});
            s.namelen = @intFromFloat(x);
        } else if (eq(word, "seed") and valued) {
            // ponytail: SEED= drives only the LTS/S subsampling (p.8788); the
            // M estimate implemented here is deterministic.
            i += 2;
            _ = try number(cx, t, &i);
        } else if (oneOf(word, &.{ "plots", "plot", "covout", "fwls", "inest", "itprint", "outest", "order" })) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC ROBUSTREG: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const upper = try std.ascii.allocUpperString(cx.arena, name orelse raw.name);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{upper}) else upper;
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var ids: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "multiple MODEL statements are not implemented", .{});
            try model(cx, ds, t, i + 1, end, &s);
            model_seen = true;
        } else if (kw(t, i, "weight")) {
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
            s.weight_line = t[i].line;
        } else if (kw(t, i, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, ids.items, c) == null) try ids.append(cx.arena, c);
            }
        } else if (kw(t, i, "by")) {
            // Only the last BY statement is used.
            bys = .{};
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "freq") or kw(t, i, "frequency")) {
            return invalid(cx, t, i);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC ROBUSTREG: MODEL statement required", .{});
    s.ids = ids.items;
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// `MODEL response = effects </ options>` (p.8782).
fn model(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!void {
    var i = start;
    if (at(t, i, .name) and at(t, i + 1, .colon)) return gap(cx, t[i].line, "MODEL labels are not implemented", .{});
    s.response = try numericColumn(cx, ds, t, i, "response");
    i += 1;
    if (!at(t, i, .eq)) return invalid(cx, t, i);
    i += 1;
    var regs: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) : (i += 1) {
        if (!at(t, i, .name)) return gap(cx, lineOf(t, i), "MODEL effect syntax {s} (interactions, nesting, lists) is not implemented", .{t[i].text});
        if (at(t, i + 1, .star) or at(t, i + 1, .lparen) or at(t, i + 1, .pipe) or at(t, i + 1, .minus) or at(t, i + 1, .at) or at(t, i + 1, .dollar)) return gap(cx, t[i].line, "MODEL effect syntax after {s} (interactions, nesting, lists) is not implemented", .{t[i].text});
        const c = try column(cx, ds, t, i);
        if (ds.columns.items[c].type != .num) return gap(cx, t[i].line, "character explanatory variable {s} needs the CLASS statement, which is not implemented", .{t[i].text});
        if (std.mem.indexOfScalar(usize, regs.items, c) != null) return gap(cx, t[i].line, "repeated MODEL effect policy is not verified", .{});
        try regs.append(cx.arena, c);
    }
    s.regressors = regs.items;
    if (at(t, i, .slash)) i += 1;
    while (i < end) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "alpha") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
        } else if (eq(word, "cutoff") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: CUTOFF= must be positive", .{});
            s.cutoff = x;
        } else if (eq(word, "singular") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC ROBUSTREG: SINGULAR= must be between 0 and 1", .{});
            s.singular = x;
        } else if (eq(word, "diagnostics") or eq(word, "diagnostic")) {
            if (at(t, i + 1, .lparen)) return gap(cx, t[i].line, "DIAGNOSTICS(ALL) is not implemented", .{});
            s.diagnostics = true;
            i += 1;
        } else if (eq(word, "leverage")) {
            return gap(cx, t[i].line, "LEVERAGE (MCD robust distances) is not implemented", .{});
        } else if (eq(word, "noint")) {
            return gap(cx, t[i].line, "NOINT (no-intercept robust R-square) is not implemented", .{});
        } else if (oneOf(word, &.{ "corrb", "covb", "itprint", "nogoodfit", "failratio" })) {
            return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
}

/// One used observation (input row index kept for the diagnostics table).
pub const Unit = struct { obs: usize, y: f64, w: f64, x: []const f64 };

pub const Selected = struct { units: []Unit, read: usize, missing: usize };

/// Observation selection (verified against SAS 9.4 for invented edits of the
/// stack-loss data): a missing response or regressor, and a missing or
/// nonpositive weight, drop the observation and count as "Missing Values".
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    const p = s.regressors.len + 1;
    var units: std.ArrayList(Unit) = .empty;
    row_loop: for (rows, 0..) |row, r| {
        if (selection.missing(row[s.response])) continue;
        for (s.regressors) |c| if (selection.missing(row[c])) continue :row_loop;
        var w: f64 = 1;
        if (s.weight) |c| {
            if (selection.missing(row[c]) or !(row[c].num > 0)) continue;
            w = row[c].num;
        }
        const x = try a.alloc(f64, p);
        x[0] = 1;
        for (s.regressors, 1..) |c, k| x[k] = row[c].num;
        try units.append(a, .{ .obs = r, .y = row[s.response].num, .w = w, .x = x });
    }
    return .{ .units = units.items, .read = rows.len, .missing = rows.len - units.items.len };
}

// Bisquare (p.8791): W(x) = (1 - (x/c)^2)^2 for |x| <= c, else 0.
pub fn weightFn(u: f64, c: f64) f64 {
    if (!(@abs(u) <= c)) return 0;
    const q = (u / c) * (u / c);
    return (1 - q) * (1 - q);
}
pub fn psi(u: f64, c: f64) f64 {
    return u * weightFn(u, c);
}
pub fn dpsi(u: f64, c: f64) f64 {
    if (!(@abs(u) <= c)) return 0;
    const q = (u / c) * (u / c);
    return (1 - q) * (1 - 5 * q);
}
/// rho with rho' = psi: c^2/6 (1 - (1 - (x/c)^2)^3), constant beyond c.
pub fn rho(u: f64, c: f64) f64 {
    if (!(@abs(u) <= c)) return c * c / 6;
    const q = (u / c) * (u / c);
    return c * c / 6 * (1 - (1 - q) * (1 - q) * (1 - q));
}

pub const FitError = error{ OutOfMemory, Singular, NoConvergence, ZeroScale };

/// Gauss-Jordan inverse of the p x p row-major `m`; a pivot below `tol`
/// times its original diagonal is a singularity.
pub fn invert(a: A, m: []const f64, p: usize, tol: f64) FitError![]f64 {
    const w = try a.dupe(f64, m);
    const inv = try a.alloc(f64, p * p);
    @memset(inv, 0);
    for (0..p) |k| inv[k * p + k] = 1;
    for (0..p) |c| {
        var best = c;
        for (c + 1..p) |r| if (@abs(w[r * p + c]) > @abs(w[best * p + c])) {
            best = r;
        };
        if (!(@abs(w[best * p + c]) > tol * @abs(m[c * p + c])) or w[best * p + c] == 0) return error.Singular;
        if (best != c) for (0..p) |j| {
            std.mem.swap(f64, &w[c * p + j], &w[best * p + j]);
            std.mem.swap(f64, &inv[c * p + j], &inv[best * p + j]);
        };
        const piv = w[c * p + c];
        for (0..p) |j| {
            w[c * p + j] /= piv;
            inv[c * p + j] /= piv;
        }
        for (0..p) |r| if (r != c) {
            const f = w[r * p + c];
            if (f != 0) for (0..p) |j| {
                w[r * p + j] -= f * w[c * p + j];
                inv[r * p + j] -= f * inv[c * p + j];
            };
        };
    }
    return inv;
}

fn median(a: A, values: []const f64) !f64 {
    const v = try a.dupe(f64, values);
    std.mem.sort(f64, v, {}, std.sort.asc(f64));
    const k = v.len;
    return if (k % 2 == 1) v[k / 2] else (v[k / 2 - 1] + v[k / 2]) / 2;
}

fn residuals(a: A, units: []const Unit, beta: []const f64, q: usize) ![]f64 {
    const r = try a.alloc(f64, units.len);
    for (units, r) |u, *e| {
        var fit: f64 = 0;
        for (0..q) |j| fit += u.x[j] * beta[j];
        e.* = u.y - fit;
    }
    return r;
}

/// Weighted least squares on the first `q` design columns with weights
/// unit.w * extra[i].
fn wls(a: A, units: []const Unit, extra: ?[]const f64, q: usize, tol: f64) FitError![]f64 {
    const h = try a.alloc(f64, q * q);
    const g = try a.alloc(f64, q);
    @memset(h, 0);
    @memset(g, 0);
    for (units, 0..) |u, i| {
        const w = u.w * (if (extra) |e| e[i] else 1);
        for (0..q) |j| {
            g[j] += w * u.x[j] * u.y;
            for (0..q) |k| h[j * q + k] += w * u.x[j] * u.x[k];
        }
    }
    const inv = try invert(a, h, q, tol);
    const beta = try a.alloc(f64, q);
    for (0..q) |j| {
        var sum: f64 = 0;
        for (0..q) |k| sum += inv[j * q + k] * g[k];
        beta[j] = sum;
    }
    return beta;
}

pub const MFit = struct { beta: []f64, scale: f64, iterations: usize };

/// IRLS M estimate on the first `q` columns (p.8789 "Algorithm"): OLS
/// start, bisquare weights from r/sigma, SCALE=MED update after every
/// location step, stop when the largest relative coefficient change is below
/// `eps` (absolute change for coefficients near zero).
pub fn mEstimate(a: A, units: []const Unit, q: usize, c: f64, eps: f64, maxiter: usize, tol: f64) FitError!MFit {
    var beta = try wls(a, units, null, q, tol);
    const abs_r = try a.alloc(f64, units.len);
    var r = try residuals(a, units, beta, q);
    for (r, abs_r) |e, *x| x.* = @abs(e);
    var scale = try median(a, abs_r) / beta0;
    if (!(scale > 0)) return error.ZeroScale;
    const w = try a.alloc(f64, units.len);
    var it: usize = 0;
    while (it < maxiter) {
        for (r, w) |e, *x| x.* = weightFn(e / scale, c);
        const next = try wls(a, units, w, q, tol);
        var change: f64 = 0;
        for (beta, next) |old, new| change = @max(change, if (@abs(old) > 1e-8) @abs(new - old) / @abs(old) else @abs(new - old));
        beta = next;
        it += 1;
        r = try residuals(a, units, beta, q);
        for (r, abs_r) |e, *x| x.* = @abs(e);
        scale = try median(a, abs_r) / beta0;
        if (!(scale > 0)) return error.ZeroScale;
        if (change < eps) return .{ .beta = beta, .scale = scale, .iterations = it };
    }
    return error.NoConvergence;
}

pub const Result = struct {
    fit: MFit,
    se: []f64,
    std_resid: []f64,
    r_square: f64,
    aicr: f64,
    bicr: f64,
    deviance: f64,
};

/// Full model, H1 covariance and goodness of fit (pp.8792-8794).
pub fn analyze(a: A, units: []const Unit, p: usize, c: f64, eps: f64, maxiter: usize, tol: f64) FitError!Result {
    const f = try mEstimate(a, units, p, c, eps, maxiter, tol);
    const n: f64 = @floatFromInt(units.len);
    const pf: f64 = @floatFromInt(p);
    const r = try residuals(a, units, f.beta, p);
    const u = try a.alloc(f64, units.len);
    var psi2: f64 = 0;
    var mean_d: f64 = 0;
    var sum_rho: f64 = 0;
    // AICR penalty sums: SAS 9.4 weights psi^2 by w^3 and psi' by w (found
    // and checked on two weighted reference listings; w = 1 gives the
    // documented 2 E psi^2 / E psi').
    var psi2_w3: f64 = 0;
    var dpsi_w: f64 = 0;
    for (r, u, units) |e, *x, unit| {
        x.* = e / f.scale;
        psi2 += unit.w * psi(x.*, c) * psi(x.*, c);
        psi2_w3 += unit.w * unit.w * unit.w * psi(x.*, c) * psi(x.*, c);
        mean_d += dpsi(x.*, c);
        dpsi_w += unit.w * dpsi(x.*, c);
        sum_rho += unit.w * rho(x.*, c);
    }
    mean_d /= n;
    var var_d: f64 = 0;
    for (u) |x| var_d += (dpsi(x, c) - mean_d) * (dpsi(x, c) - mean_d);
    var_d /= n;
    if (!(mean_d > 0)) return error.Singular;
    const k = 1 + pf / n * var_d / (mean_d * mean_d);
    const h = try a.alloc(f64, p * p);
    @memset(h, 0);
    for (units) |unit| for (0..p) |j| for (0..p) |l| {
        h[j * p + l] += unit.w * unit.x[j] * unit.x[l];
    };
    const inv = try invert(a, h, p, tol);
    const factor = k * k * (psi2 / (n - pf)) / (mean_d * mean_d) * f.scale * f.scale;
    const se = try a.alloc(f64, p);
    for (se, 0..) |*e, j| e.* = @sqrt(factor * inv[j * p + j]);
    // Location-scale M estimate; its residuals are scaled by the full-model
    // scale in the robust R-square (reference-verified).
    const loc = try mEstimate(a, units, 1, c, eps, maxiter, tol);
    var rho0: f64 = 0;
    for (units) |unit| rho0 += unit.w * rho((unit.y - loc.beta[0]) / f.scale, c);
    const alpha = 2 * psi2_w3 / dpsi_w;
    return .{
        .fit = f,
        .se = se,
        .std_resid = u,
        .r_square = (rho0 - sum_rho) / rho0,
        .aicr = 2 * sum_rho + alpha * pf,
        .bicr = 2 * sum_rho + pf * @log(n),
        .deviance = 2 * f.scale * f.scale * sum_rho,
    };
}

pub fn chiProbability(x: f64, df: f64) f64 {
    return 1 - fns.gammaP(df / 2, x / 2);
}
pub fn zCritical(alpha: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 40;
    for (0..200) |_| {
        const mid = (lo + hi) / 2;
        if (fns.gammaP(0.5, mid * mid / 2) < 1 - alpha) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

/// Quartiles as the reference Summary Statistics print them: position
/// (n+1)p; an integer position is that order statistic, otherwise the mean
/// of the two neighbours (checked: n = 21 Q1 = mean of the 5th and 6th, n = 16
/// Q3 = mean of the 12th and 13th). ponytail: other sample sizes (for
/// example n = 18, where this differs from Tukey's hinges) are not
/// reference-checked.
pub fn quantile(sorted: []const f64, prob: f64) f64 {
    const n: f64 = @floatFromInt(sorted.len);
    const pos = (n + 1) * prob;
    if (pos <= 1) return sorted[0];
    if (pos >= n) return sorted[sorted.len - 1];
    const lo: usize = @intFromFloat(@floor(pos));
    if (pos == @floor(pos)) return sorted[lo - 1];
    return (sorted[lo - 1] + sorted[lo]) / 2;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
    if (text[0] == '-') {
        for (text[1..]) |ch| if (ch != '0' and ch != '.') return text;
        return text[1..];
    }
    return text;
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn centred(a: A, out: *Out, title: []const u8, width: usize) !void {
    if (title.len < width) try out.appendNTimes(a, ' ', (width - title.len + 1) / 2);
    try out.print(a, "{s}\n", .{title});
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else fixed(a, p, 4);
}
fn idText(a: A, v: Value) ![]const u8 {
    return switch (v) {
        .str => |x| std.mem.trimEnd(u8, x, " "),
        .num => |x| format.bestNum(a, x),
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    if (s.diagnostics) for (s.ids) |c| {
        if (ds.columns.items[c].type == .num) return gap(cx, 0, "a numeric ID variable in the diagnostics table is not verified", .{});
    };
    if (s.diagnostics and s.ids.len != 1) return gap(cx, 0, "the diagnostics table without exactly one ID variable is not verified", .{});
    if (cx.capture) |c| for ([_][]const u8{ "ModelInfo", "NObs", "ParmInfo", "SummaryStatistics", "ParameterEstimates", "Diagnostics", "DiagSummary", "GoodFit" }) |tbl| {
        if (c.wants(tbl)) return gap(cx, 0, "ODS OUTPUT {s}= is not implemented", .{tbl});
    };
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0 or (slices.len == 1 and slices[0].rows.len == 0)) return gap(cx, 0, "the result for an input data set without observations is not verified", .{});
    const p = s.regressors.len + 1;
    const z = zCritical(s.alpha);
    var body: Out = .empty;
    for (slices) |slice| {
        const sel = try select(a, s, slice.rows);
        if (sel.units.len <= p) return gap(cx, 0, "a BY group or data set with no more used observations than parameters is not verified", .{});
        const res = analyze(a, sel.units, p, s.c, s.eps, s.maxiter, s.singular) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx, 0, "a singular design is not verified", .{}),
            error.NoConvergence => return gap(cx, 0, "the listing for M estimates that did not converge is not verified", .{}),
            error.ZeroScale => return gap(cx, 0, "a zero median absolute residual (zero scale) is not verified", .{}),
        };
        try cx.diags.note(0, "Algorithm converged for the M estimates.", .{});
        try cx.diags.note(0, "Algorithm converged for the location-scale M estimates.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, slice.rows[0], s.by_cols);
        try render(a, &body, cx, s, slice, sel, res, z);
    }
    try out.appendSlice(a, body.items);
}

fn render(a: A, body: *Out, cx: proc.ProcCtx, s: Spec, slice: proc.BySlice, sel: Selected, res: Result, z: f64) !void {
    const ds = s.input.ds;
    const p = s.regressors.len + 1;
    if (cx.listing_titles) |titles| try titles.emitTitles(a, body);
    try body.append(a, '\n');
    if (s.by_cols.len > 0) {
        var tmp: Out = .empty;
        try by.appendLine(a, &tmp, ds, slice.rows[0], s.by_cols);
        try body.print(a, "{s}\n\n", .{std.mem.trim(u8, tmp.items, " \n")});
    }
    try body.appendSlice(a, "The ROBUSTREG Procedure\n\n");

    // Model Information: labels 31 wide, values right-aligned.
    var info: std.ArrayList([2][]const u8) = .empty;
    try info.append(a, .{ "Data Set", s.data_name });
    try info.append(a, .{ "Dependent Variable", ds.columns.items[s.response].name });
    if (s.weight) |c| try info.append(a, .{ "Weight Variable", ds.columns.items[c].name });
    try info.append(a, .{ "Number of Independent Variables", try std.fmt.allocPrint(a, "{d}", .{s.regressors.len}) });
    try info.append(a, .{ "Number of Observations", try std.fmt.allocPrint(a, "{d}", .{sel.units.len}) });
    if (sel.missing > 0) try info.append(a, .{ "Missing Values", try std.fmt.allocPrint(a, "{d}", .{sel.missing}) });
    try info.append(a, .{ "Method", "M Estimation" });
    // ponytail: the value column is at least 14 wide (reference listings);
    // longer values widen it.
    var vw: usize = 14;
    for (info.items) |r| vw = @max(vw, r[1].len);
    try centred(a, body, "Model Information", 35 + vw);
    try body.append(a, '\n');
    for (info.items) |r| {
        try left(a, body, r[0], 31);
        try right(a, body, r[1], vw + 4);
        try body.append(a, '\n');
    }
    try body.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n", .{ sel.read, sel.units.len });
    if (s.weight != null) {
        var sum_w: f64 = 0;
        for (sel.units) |unit| sum_w += unit.w;
        try body.print(a, "Sum of Weights             {s:>12}\n", .{try format.bestNum(a, sum_w)});
    }
    if (sel.missing > 0) try body.print(a, "Missing Values             {d:>12}\n", .{sel.missing});

    // Parameter Information.
    const names = try a.alloc([]const u8, p);
    names[0] = "Intercept";
    for (s.regressors, 1..) |c, k| {
        const n = ds.columns.items[c].name;
        names[k] = n[0..@min(n.len, s.namelen)];
    }
    var pw: usize = 9;
    for (names) |n| pw = @max(pw, n.len);
    try body.appendSlice(a, "\n\n");
    // ponytail: the reference prints this title flush left over the
    // default 22-wide table; wider names are not reference-checked.
    try body.appendSlice(a, "Parameter Information\n \n");
    try left(a, body, "Parameter", pw + 4);
    try body.appendSlice(a, "Effect\n\n");
    for (names) |n| {
        try left(a, body, n, pw + 4);
        try left(a, body, n, pw);
        try body.append(a, '\n');
    }

    // Summary Statistics over the used observations (regressors, response).
    var vars: std.ArrayList(usize) = .empty;
    try vars.appendSlice(a, s.regressors);
    try vars.append(a, s.response);
    var nw: usize = 8;
    for (vars.items) |c| nw = @max(nw, ds.columns.items[c].name.len);
    nw += 1;
    const total = nw + 12 * 5 + 13;
    try body.appendSlice(a, "\n\n");
    try centred(a, body, "Summary Statistics", total);
    try body.appendSlice(a, " \n");
    try right(a, body, "Standard", nw + 12 * 4 + 13);
    try body.append(a, '\n');
    try left(a, body, "Variable", nw);
    try body.appendSlice(a, "          Q1      Median          Q3        Mean    Deviation         MAD\n\n");
    const n_used = sel.units.len;
    const values = try a.alloc(f64, n_used);
    const dev = try a.alloc(f64, n_used);
    for (vars.items, 0..) |c, vi| {
        for (sel.units, values) |u, *v| v.* = if (vi == s.regressors.len) u.y else u.x[vi + 1];
        var mean: f64 = 0;
        for (values) |v| mean += v;
        mean /= @floatFromInt(n_used);
        var ss: f64 = 0;
        for (values) |v| ss += (v - mean) * (v - mean);
        const sd = @sqrt(ss / @as(f64, @floatFromInt(n_used - 1)));
        std.mem.sort(f64, values, {}, std.sort.asc(f64));
        const med = quantile(values, 0.5);
        for (values, dev) |v, *d| d.* = @abs(v - med);
        const mad = try median(a, dev) / beta0;
        try left(a, body, ds.columns.items[c].name, nw);
        for ([_]f64{ quantile(values, 0.25), med, quantile(values, 0.75), mean }) |v| try right(a, body, try fixed(a, v, 4), 12);
        try right(a, body, try fixed(a, sd, 4), 13);
        try right(a, body, try fixed(a, mad, 4), 12);
        try body.append(a, '\n');
    }

    // Parameter Estimates.
    const width = pw + 58;
    try body.appendSlice(a, "\n\n");
    try centred(a, body, "Parameter Estimates", width);
    try body.appendSlice(a, " \n");
    try body.appendNTimes(a, ' ', pw + 13);
    const level = try format.bestNum(a, 100 * (1 - s.alpha));
    const conf = try std.fmt.allocPrint(a, "{s}% Confidence", .{level});
    if (conf.len != 14) return gap(cx, 0, "the confidence-limit header for ALPHA={s} is not verified", .{try format.bestNum(a, s.alpha)});
    try body.print(a, "Standard   {s}     Chi-\n", .{conf});
    try left(a, body, "Parameter", pw);
    try body.appendSlice(a, " DF Estimate    Error       Limits       Square Pr > ChiSq\n\n");
    for (0..p) |j| {
        const b = res.fit.beta[j];
        const se = res.se[j];
        const chi = b * b / (se * se);
        const cells = [_][]const u8{ try fixed(a, b, 4), try fixed(a, se, 4), try fixed(a, b - z * se, 4), try fixed(a, b + z * se, 4) };
        for (cells) |cell| if (cell.len > 8) return gap(cx, 0, "parameter display wider than the 8-column reference layout is not verified", .{});
        const chi_text = try fixed(a, chi, 2);
        if (chi_text.len > 7) return gap(cx, 0, "chi-square display wider than the reference layout is not verified", .{});
        try left(a, body, names[j], pw);
        try body.appendSlice(a, "  1");
        for (cells) |cell| try right(a, body, cell, 9);
        try right(a, body, chi_text, 8);
        try right(a, body, try pvalue(a, chiProbability(chi, 1)), 11);
        try body.append(a, '\n');
    }
    const scale_text = try fixed(a, res.fit.scale, 4);
    if (scale_text.len > 8) return gap(cx, 0, "scale display wider than the reference layout is not verified", .{});
    try left(a, body, "Scale", pw);
    try body.appendSlice(a, "  1");
    try right(a, body, scale_text, 9);
    try body.appendNTimes(a, ' ', 46);
    try body.append(a, '\n');

    // Diagnostics (outliers only: LEVERAGE is a gap).
    var outliers: usize = 0;
    for (res.std_resid) |r| {
        if (@abs(r) > s.cutoff) outliers += 1;
    }
    if (s.diagnostics and outliers > 0) {
        const idc = s.ids[0];
        var iw: usize = ds.columns.items[idc].name.len;
        for (sel.units) |u| iw = @max(iw, (try idText(a, slice.rows[u.obs][idc])).len);
        try body.appendSlice(a, "\n\n");
        try centred(a, body, "Diagnostics", 10 + iw + 37);
        try body.appendSlice(a, " \n");
        try right(a, body, "Standardized", 10 + iw + 21);
        try body.append(a, '\n');
        try right(a, body, "Robust", 10 + iw + 21);
        try body.appendSlice(a, "\n   Obs    ");
        try left(a, body, ds.columns.items[idc].name, iw);
        try body.appendSlice(a, "             Residual      Outlier\n\n");
        for (sel.units, res.std_resid) |u, r| {
            if (!(@abs(r) > s.cutoff)) continue;
            try body.print(a, "{d:>6}    ", .{u.obs + 1});
            try left(a, body, try idText(a, slice.rows[u.obs][idc]), iw);
            try right(a, body, try fixed(a, r, 4), 21);
            try body.appendSlice(a, "         *      \n");
        }
    }

    // Diagnostics Summary.
    try body.appendSlice(a, "\n\n");
    try centred(a, body, "Diagnostics Summary", 37);
    try body.appendSlice(a, " \nObservation\nType           Proportion      Cutoff\n\n");
    const prop = @as(f64, @floatFromInt(outliers)) / @as(f64, @floatFromInt(n_used));
    try left(a, body, "Outlier", 11);
    try right(a, body, try fixed(a, prop, 4), 14);
    try right(a, body, try fixed(a, s.cutoff, 4), 12);
    try body.append(a, '\n');

    // Goodness-of-Fit.
    try body.appendSlice(a, "\n\n   Goodness-of-Fit\n \nStatistic       Value\n\n");
    const fits = [_]struct { []const u8, f64 }{ .{ "R-Square", res.r_square }, .{ "AICR", res.aicr }, .{ "BICR", res.bicr }, .{ "Deviance", res.deviance } };
    for (fits) |row| {
        try left(a, body, row[0], 9);
        try right(a, body, try fixed(a, row[1], 4), 12);
        try body.append(a, '\n');
    }
}

test {
    _ = @import("robustreg_tests.zig");
}
