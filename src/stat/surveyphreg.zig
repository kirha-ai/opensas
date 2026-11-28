//! PROC SURVEYPHREG declarations, variable roles, observation selection and
//! the default listing of a Cox proportional hazards model with continuous
//! covariates under Taylor-series (linearization) variance estimation,
//! SAS/STAT 15.4 chapter 122, physical pp.10010-10042 (syntax), 10042-10058
//! (missing values, Taylor series linearization, degrees of freedom, global
//! tests, model fit): Model Information, observation counts and weights,
//! Design Summary, event/censoring summaries, Variance Estimation, fit
//! statistics, global tests (unadjusted and adjusted likelihood ratio, Wald)
//! and parameter estimates with t tests and hazard ratios; FREQ, BY groups
//! and the exclusion of observations with missing MODEL, WEIGHT, STRATA or
//! CLUSTER values (pp.10042-10043), all checked against SAS reference
//! listings. Every other documented feature is a D-009 gap (rc 2) raised
//! before any listing text.
//! ponytail: the design reuses surveyfreq_design (valid-observation rules,
//! PSUs nested in strata) and a self-contained weighted Breslow partial
//! likelihood; STAT-COMMON-016 owns unifying the survey kernels.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const reg = @import("reg_fit.zig");
const lifetest = @import("lifetest.zig");
pub const design = @import("surveyfreq_design.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    roles: design.Roles = .{},
    time: ?usize = null,
    censor: ?usize = null,
    censor_values: []const f64 = &.{},
    covariates: []const usize = &.{},
    model_line: usize = 0,
    /// FREQ variable: each observation counts trunc(value) times (p.10024).
    freq: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    by_notsorted: bool = false,
    /// NOPRINT suppresses every displayed table (p.10014); the fit still runs.
    noprint: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYPHREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYPHREG: " ++ text, args);
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
fn roleColumns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, what: []const u8) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        if (at(t, j, .slash)) return gap(cx, t[j].line, "{s} statement options are not implemented", .{what});
        const line = t[j].line;
        const names = try lists.next(cx.arena, ds, t[0..end], &j, cx.diags);
        for (names) |n| try cols.append(cx.arena, ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{n}));
    }
    if (cols.items.len == 0) return invalid(cx, t, end);
    return cols.items;
}

/// Documented MODEL options (Table 122.7) owned by later SURVEYPHREG tickets.
const later_model_options = [_][]const u8{ "alpha", "clparm", "covb", "entrytime", "firth", "hess", "invhess", "risklimits", "rl", "seratio", "singular", "varratio" };

fn parseModel(cx: proc.ProcCtx, s: *Spec, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    var i = start;
    s.model_line = t[i].line;
    if (at(t, i, .lparen)) return gap(cx, t[i].line, "the counting process style of input MODEL (t1, t2) is not implemented", .{});
    const time = try column(cx, ds, t, i);
    if (ds.columns.items[time].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: the failure time variable {s} must be numeric", .{t[i].text});
    i += 1;
    var censor: ?usize = null;
    var values: std.ArrayList(f64) = .empty;
    if (at(t, i, .star)) {
        i += 1;
        const c = try column(cx, ds, t, i);
        // The censoring variable must be numeric (p.10017).
        if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: the censoring variable {s} must be numeric", .{t[i].text});
        censor = c;
        i += 1;
        if (!at(t, i, .lparen)) return invalid(cx, t, i);
        i += 1;
        while (!at(t, i, .rparen)) {
            if (i >= end) return invalid(cx, t, i);
            if (at(t, i, .comma)) {
                i += 1;
                continue;
            }
            try values.append(cx.arena, try number(cx, t, &i));
        }
        if (values.items.len == 0) return invalid(cx, t, i);
        i += 1;
    }
    if (!at(t, i, .eq)) return invalid(cx, t, i);
    i += 1;
    var covs: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) {
        if (!at(t, i, .name)) {
            if (at(t, i, .star) or at(t, i, .pipe) or at(t, i, .at) or at(t, i, .lparen))
                return gap(cx, t[i].line, "interaction, nested and constructed MODEL effects are not implemented", .{});
            return invalid(cx, t, i);
        }
        if (at(t, i + 1, .minus) or at(t, i + 1, .colon) or at(t, i + 1, .star) or at(t, i + 1, .pipe) or at(t, i + 1, .at) or at(t, i + 1, .lparen))
            return gap(cx, t[i].line, "variable lists and interaction, nested or constructed MODEL effects are not implemented", .{});
        const c = try column(cx, ds, t, i);
        if (ds.columns.items[c].type != .num) return gap(cx, t[i].line, "character MODEL effects (CLASS variables) are not implemented", .{});
        try covs.append(cx.arena, c);
        i += 1;
    }
    if (at(t, i, .slash)) {
        i += 1;
        if (i == end) return invalid(cx, t, i);
        while (i < end) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            const o = t[i].text;
            const valued = at(t, i + 1, .eq);
            const value = if (valued and at(t, i + 2, .name)) t[i + 2].text else "";
            if (eq(o, "ties") and valued) {
                if (!eq(value, "breslow")) {
                    if (eq(value, "efron")) return gap(cx, t[i].line, "TIES=EFRON is not implemented", .{});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (eq(o, "vadjust") and valued) {
                if (!eq(value, "df")) {
                    if (oneOf(value, &.{ "none", "avgrepss" })) return gap(cx, t[i].line, "VADJUST={s} is not implemented", .{value});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (eq(o, "df") and valued) {
                if (!eq(value, "parmadj") or at(t, i + 3, .lparen)) {
                    if (at(t, i + 2, .number) or oneOf(value, &.{ "allreps", "design", "designadj", "none", "parmadj" })) return gap(cx, t[i].line, "DF= values other than the default PARMADJ are not implemented", .{});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (oneOf(o, &later_model_options)) {
                return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{o});
            } else return invalid(cx, t, i);
        }
    }
    s.time = time;
    s.censor = censor;
    s.censor_values = values.items;
    s.covariates = covs.items;
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
            if (name != null) return invalid(cx, t, i);
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on DATA= are not implemented", .{});
        } else if (eq(word, "missing") and !valued) {
            s.roles.missing = true;
            i += 1;
        } else if (eq(word, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "namelen") and valued) {
            // NAMELEN=n, 20 <= n <= 200 (p.10013; SAS 9.4 run for the range
            // message). It only truncates effect names longer than n; names
            // wider than the verified Parameter column already fail loudly.
            i += 2;
            const v = try number(cx, t, &i);
            if (!(v >= 20 and v <= 200)) return cx.diags.fail(error.ParseError, t[i - 1].line, "The parameter value {d} is not within the required range of 20 and 200.", .{v});
        } else if (oneOf(word, &.{ "atrisk", "nomcar", "noprint", "namelen", "plots", "plot" })) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "data", "freq" })) return gap(cx, t[i].line, "ORDER={s} is not implemented", .{v});
            // CLASS ordering only; without CLASS it changes nothing.
            if (!oneOf(v, &.{ "internal", "formatted" })) return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "varmethod") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "brr", "jackknife", "jk", "bootstrap" })) return gap(cx, t[i].line, "VARMETHOD={s} is not implemented", .{v});
            if (!eq(v, "taylor")) return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "VARMETHOD=TAYLOR method options are not implemented", .{});
        } else if (oneOf(word, &.{ "rate", "r", "total", "n" }) and valued) {
            return gap(cx, t[i].line, "the {s}= option (finite population correction) is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYPHREG: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    s.data_name = raw.name;
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var weight_seen = false;
    var freq_seen = false;
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
            // Exactly one MODEL statement (p.10017).
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: only one MODEL statement is allowed", .{});
            model_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            try parseModel(cx, &s, ds, t, i + 1, end);
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: only one WEIGHT statement is allowed", .{});
            weight_seen = true;
            if (end != i + 2) return invalid(cx, t, i + 2);
            const c = try column(cx, ds, t, i + 1);
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.roles.weight = c;
        } else if (kw(t, i, "freq")) {
            // The FREQ statement allows one frequency variable (p.10024);
            // what SAS does with a second statement is not verified.
            if (freq_seen) return gap(cx, t[i].line, "several FREQ statements are not implemented", .{});
            freq_seen = true;
            if (end != i + 2) return invalid(cx, t, i + 2);
            const c = try column(cx, ds, t, i + 1);
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYPHREG: FREQ variable {s} must be numeric", .{t[i + 1].text});
            s.freq = c;
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            if (s.roles.strata.len > 0) return gap(cx, t[i].line, "several STRATA statements are not implemented", .{});
            s.roles.strata = try roleColumns(cx, ds, t, i + 1, end, "STRATA");
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            if (s.roles.clusters.len > 0) return gap(cx, t[i].line, "several CLUSTER statements are not implemented", .{});
            s.roles.clusters = try roleColumns(cx, ds, t, i + 1, end, "CLUSTER");
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (at(t, i, .name) and oneOf(t[i].text, &.{ "repweights", "repweight", "class", "domain", "contrast", "effect", "estimate", "hazardratio", "lsmeans", "lsmestimate", "output", "slice", "store", "test", "format" })) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (at(t, i, .name) and at(t, i + 1, .eq)) {
            return gap(cx, t[i].line, "programming statements (time-dependent covariates) are not implemented", .{});
        } else if (!kw(t, i, "where")) {
            return invalid(cx, t, i);
        }
        i = end + 1;
    }
    // The MODEL statement is required (p.10017).
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYPHREG: a MODEL statement is required", .{});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.by_notsorted = pb.notsorted;
    return s;
}

/// Weighted Breslow partial likelihood at `beta` for n observations with
/// covariate rows `x` (n*p), times, event indicators and weights (p.10047):
///   log L = sum_i w_i d_i [b'z_i - log S0(t_i)],
///   S0(t) = sum_{t_j >= t} w_j exp(b'z_j).
/// Fills the score `u` (p) and the observed information `info` (p*p).
pub const Cox = struct {
    n: usize,
    p: usize,
    x: []const f64,
    time: []const f64,
    event: []const bool,
    weight: []const f64,

    pub fn evaluate(c: Cox, a: A, beta: []const f64, u: []f64, info: []f64) !f64 {
        const p = c.p;
        @memset(u, 0);
        @memset(info, 0);
        const s1 = try a.alloc(f64, p);
        const s2 = try a.alloc(f64, p * p);
        var ll: f64 = 0;
        for (0..c.n) |i| {
            if (!c.event[i]) continue;
            var s0: f64 = 0;
            @memset(s1, 0);
            @memset(s2, 0);
            for (0..c.n) |j| {
                if (c.time[j] < c.time[i]) continue;
                const r = c.weight[j] * @exp(dot(c.x[j * p ..][0..p], beta));
                s0 += r;
                for (0..p) |k| {
                    s1[k] += r * c.x[j * p + k];
                    for (0..p) |l| s2[k * p + l] += r * c.x[j * p + k] * c.x[j * p + l];
                }
            }
            const w = c.weight[i];
            ll += w * (dot(c.x[i * p ..][0..p], beta) - @log(s0));
            for (0..p) |k| {
                u[k] += w * (c.x[i * p + k] - s1[k] / s0);
                for (0..p) |l| info[k * p + l] += w * (s2[k * p + l] / s0 - s1[k] * s1[l] / (s0 * s0));
            }
        }
        return ll;
    }

    /// Score residuals L_j (p.10045, Breslow):
    ///   L_j = d_j (z_j - Zbar(t_j)) - sum_{events i, t_i <= t_j}
    ///         w_i exp(b'z_j) / S0(t_i) (z_j - Zbar(t_i)).
    pub fn scoreResiduals(c: Cox, a: A, beta: []const f64) ![]f64 {
        const p = c.p;
        const n = c.n;
        const s0 = try a.alloc(f64, n);
        const zbar = try a.alloc(f64, n * p);
        @memset(zbar, 0);
        for (0..n) |i| {
            var t0: f64 = 0;
            for (0..n) |j| {
                if (c.time[j] < c.time[i]) continue;
                const r = c.weight[j] * @exp(dot(c.x[j * p ..][0..p], beta));
                t0 += r;
                for (0..p) |k| zbar[i * p + k] += r * c.x[j * p + k];
            }
            s0[i] = t0;
            for (0..p) |k| zbar[i * p + k] /= t0;
        }
        const res = try a.alloc(f64, n * p);
        @memset(res, 0);
        for (0..n) |j| {
            const risk = @exp(dot(c.x[j * p ..][0..p], beta));
            if (c.event[j]) for (0..p) |k| {
                res[j * p + k] += c.x[j * p + k] - zbar[j * p + k];
            };
            for (0..n) |i| {
                if (!c.event[i] or c.time[i] > c.time[j]) continue;
                const f = c.weight[i] * risk / s0[i];
                for (0..p) |k| res[j * p + k] -= f * (c.x[j * p + k] - zbar[i * p + k]);
            }
        }
        return res;
    }
};

fn dot(x: []const f64, y: []const f64) f64 {
    var s: f64 = 0;
    for (x, y) |u, v| s += u * v;
    return s;
}

fn invert(a: A, m: []const f64, p: usize) ![]f64 {
    // Gauss-Jordan with partial pivoting; p is the (small) parameter count.
    const w = try a.alloc(f64, p * 2 * p);
    for (0..p) |r| for (0..2 * p) |c| {
        w[r * 2 * p + c] = if (c < p) m[r * p + c] else if (c - p == r) 1 else 0;
    };
    for (0..p) |col| {
        var piv = col;
        for (col + 1..p) |r| if (@abs(w[r * 2 * p + col]) > @abs(w[piv * 2 * p + col])) {
            piv = r;
        };
        if (!(@abs(w[piv * 2 * p + col]) > 1e-300)) return error.Singular;
        if (piv != col) for (0..2 * p) |c| std.mem.swap(f64, &w[piv * 2 * p + c], &w[col * 2 * p + c]);
        const d = w[col * 2 * p + col];
        for (0..2 * p) |c| w[col * 2 * p + c] /= d;
        for (0..p) |r| if (r != col) {
            const f = w[r * 2 * p + col];
            for (0..2 * p) |c| w[r * 2 * p + c] -= f * w[col * 2 * p + c];
        };
    }
    const inv = try a.alloc(f64, p * p);
    for (0..p) |r| for (0..p) |c| {
        inv[r * p + c] = w[r * 2 * p + p + c];
    };
    return inv;
}

pub const Fit = struct { beta: []f64, ll: f64, ll0: f64, info: []f64, converged: bool };

/// Newton-Raphson with step halving to GCONV=1E-8 (relative gradient
/// criterion g' I^-1 g / |log L|); the optimum does not depend on the
/// ridging variant SAS uses (NRRIDG).
pub fn fit(a: A, c: Cox) !Fit {
    const p = c.p;
    const beta = try a.alloc(f64, p);
    @memset(beta, 0);
    const u = try a.alloc(f64, p);
    const info = try a.alloc(f64, p * p);
    const zero = try a.alloc(f64, p);
    @memset(zero, 0);
    const ll0 = try c.evaluate(a, zero, u, info);
    var ll = ll0;
    var converged = false;
    var iter: usize = 0;
    while (iter < 60) : (iter += 1) {
        ll = try c.evaluate(a, beta, u, info);
        const inv = invert(a, info, p) catch return error.Singular;
        var step = try a.alloc(f64, p);
        for (0..p) |r| step[r] = dot(inv[r * p ..][0..p], u);
        const gconv = dot(u, step) / @max(@abs(ll), 1e-6);
        // ponytail: GCONV=1E-8 decides convergence, but SAS's reported
        // estimate is the fully converged one (a reference BY group differs
        // in the fourth digit when stopping at 1E-8), so iterate on to the
        // rounding floor.
        converged = converged or gconv < 1e-8;
        if (gconv < 1e-20 or (converged and !(gconv > 0))) break;
        var scale: f64 = 1;
        const trial = try a.alloc(f64, p);
        while (true) {
            for (0..p) |r| trial[r] = beta[r] + scale * step[r];
            const lt = try c.evaluate(a, trial, try a.alloc(f64, p), try a.alloc(f64, p * p));
            if (lt >= ll or scale < 1e-6) break;
            scale /= 2;
        }
        @memcpy(beta, trial);
    }
    ll = try c.evaluate(a, beta, u, info);
    return .{ .beta = beta, .ll = ll, .ll0 = ll0, .info = info, .converged = converged };
}

/// G = (n-1)/(n-p) sum_h n_h (1-f_h)/(n_h-1) sum_i (e_hi+ - ebar_h)(...)',
/// e_hij = w_hij L_hij (p.10046).
pub fn meatMatrix(a: A, d: design.Design, res: []const f64, p: usize, units: f64) ![]f64 {
    const e = try a.alloc(f64, d.clusters() * p);
    @memset(e, 0);
    for (0..d.kept.len) |k| for (0..p) |j| {
        e[d.psu[k] * p + j] += d.weight[k] * res[k * p + j];
    };
    const mean = try a.alloc(f64, d.strata() * p);
    @memset(mean, 0);
    for (0..d.clusters()) |c| for (0..p) |j| {
        mean[d.psu_stratum[c] * p + j] += e[c * p + j];
    };
    for (0..d.strata()) |h| for (0..p) |j| {
        mean[h * p + j] /= @floatFromInt(d.stratum_psus[h]);
    };
    const g = try a.alloc(f64, p * p);
    @memset(g, 0);
    for (0..d.clusters()) |c| {
        const h = d.psu_stratum[c];
        const nh: f64 = @floatFromInt(d.stratum_psus[h]);
        const factor = if (nh > 1) nh * d.stratum_fpc[h] / (nh - 1) else 0;
        for (0..p) |r| for (0..p) |s| {
            g[r * p + s] += factor * (e[c * p + r] - mean[h * p + r]) * (e[c * p + s] - mean[h * p + s]);
        };
    }
    const pf: f64 = @floatFromInt(p);
    for (g) |*v| v.* *= (units - 1) / (units - pf);
    return g;
}

fn sandwich(a: A, bread: []const f64, meat: []const f64, p: usize) ![]f64 {
    const tmp = try a.alloc(f64, p * p);
    const v = try a.alloc(f64, p * p);
    for (0..p) |r| for (0..p) |c| {
        var s: f64 = 0;
        for (0..p) |k| s += bread[r * p + k] * meat[k * p + c];
        tmp[r * p + c] = s;
    };
    for (0..p) |r| for (0..p) |c| {
        var s: f64 = 0;
        for (0..p) |k| s += tmp[r * p + k] * bread[k * p + c];
        v[r * p + c] = s;
    };
    return v;
}

pub const Result = struct {
    d: design.Design,
    /// Observations read and the sum of their valid (positive) weights.
    read: usize,
    sum_weights_read: f64,
    /// Observations used (rows of `d`), their frequency total and weighted
    /// frequency total; without FREQ the frequency is 1.
    n: usize,
    units: f64,
    weighted_units: f64,
    /// FREQ totals read: every row with a valid frequency, including rows
    /// excluded by MODEL values (SAS 9.4 run).
    freq_read: f64 = 0,
    wfreq_read: f64 = 0,
    /// Observations excluded for missing values (Variance Estimation note).
    excluded: bool,
    events: f64,
    weighted_events: f64,
    beta: []const f64,
    covariance: []const f64,
    neg2ll: f64,
    neg2ll_null: f64,
    df: usize,
    lr: f64,
    lr_adj: f64,
    wald: f64,
};

fn isCensored(s: Spec, v: f64) bool {
    for (s.censor_values) |c| if (c == v) return true;
    return false;
}

/// Fit and inference for one validated design. `rows` are the rows given to
/// `design.build`; `freq` holds the truncated frequency of every kept row.
pub fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, d: design.Design, freq: []const f64) diag.Error!Result {
    const a = cx.arena;
    const n = d.kept.len;
    const p = s.covariates.len;
    const x = try a.alloc(f64, n * p);
    const time = try a.alloc(f64, n);
    const event = try a.alloc(bool, n);
    // A frequency f repeats the observation f times inside its own PSU, so
    // it multiplies the sampling weight in every sum (p.10024).
    const wf = try a.alloc(f64, n);
    var events: f64 = 0;
    var wevents: f64 = 0;
    var units: f64 = 0;
    var wunits: f64 = 0;
    for (d.kept, 0..) |r, k| {
        for (s.covariates, 0..) |c, j| x[k * p + j] = rows[r][c].num;
        time[k] = rows[r][s.time.?].num;
        event[k] = if (s.censor) |c| !isCensored(s, rows[r][c].num) else true;
        wf[k] = d.weight[k] * freq[k];
        units += freq[k];
        wunits += wf[k];
        if (event[k]) {
            events += freq[k];
            wevents += wf[k];
        }
    }
    if (events == 0) return gap(cx, s.model_line, "the listing for data without events is not implemented", .{});
    const cox: Cox = .{ .n = n, .p = p, .x = x, .time = time, .event = event, .weight = wf };
    const f = fit(a, cox) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return gap(cx, s.model_line, "the listing for a model with a singular information matrix is not implemented", .{}),
    };
    if (!f.converged) return gap(cx, s.model_line, "the listing for a model without convergence is not implemented", .{});
    const bread = invert(a, f.info, p) catch return gap(cx, s.model_line, "the listing for a model with a singular information matrix is not implemented", .{});
    const res = try cox.scoreResiduals(a, f.beta);
    // e_hij = w_hij f_hij L_hij: fold the frequency into the residual and
    // let meatMatrix apply the sampling weight.
    for (0..n) |k| for (0..p) |j| {
        res[k * p + j] *= freq[k];
    };
    const cov = try sandwich(a, bread, try meatMatrix(a, d, res, p, units), p);
    const df = d.clusters() - d.strata();
    const lr = 2 * (f.ll - f.ll0);
    // Generalized design effect (p.10055): V_srswr = I^-1 sum(w)/n; with one
    // parameter its single eigenvalue is V / V_srswr and a^2 = 0 (p.10057).
    const deff = cov[0] / (bread[0] * wunits / units);
    return .{
        .d = d,
        .read = 0,
        .sum_weights_read = 0,
        .n = n,
        .units = units,
        .weighted_units = wunits,
        .excluded = false,
        .events = events,
        .weighted_events = wevents,
        .beta = f.beta,
        .covariance = cov,
        .neg2ll = -2 * f.ll,
        .neg2ll_null = -2 * f.ll0,
        .df = df,
        .lr = lr,
        .lr_adj = (units / wunits) * lr / deff,
        // DF=PARMADJ, p = 1: F = (d-p+1) Q/(p d) = Q with d-p+1 = d.
        .wald = f.beta[0] * f.beta[0] / cov[0],
    };
}

/// Statement-level restrictions of the verified listing, raised before any
/// group is analyzed so a BY request never reports a group data error first.
fn checkSupported(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    if (s.covariates.len == 0) return gap(cx, s.model_line, "the model without covariates is not implemented", .{});
    if (s.covariates.len > 1) return gap(cx, s.model_line, "models with more than one parameter (eigenvalue adjusted likelihood ratio and PARMADJ Wald tests) are not implemented", .{});
    // Without WEIGHT every weight is 1; without STRATA one stratum; without
    // CLUSTER every observation is its own PSU (p.10052). FREQ is verified
    // only with both WEIGHT and CLUSTER (its copies stay inside one PSU).
    if (s.freq != null and (s.roles.weight == null or s.roles.clusters.len == 0)) return gap(cx, 0, "FREQ without both WEIGHT and CLUSTER statements is not verified", .{});
}

/// A stratum with one cluster contributes no variance (meatMatrix) and SAS
/// warns per stratum, numbering the levels in sorted order (SAS 9.4 runs).
fn warnSinglePsu(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, d: design.Design) diag.Error!void {
    if (s.roles.strata.len != 1 or std.meta.activeTag(rows[0][s.roles.strata[0]]) != .num) return gap(cx, 0, "the single-cluster stratum warning for character or several STRATA variables is not implemented", .{});
    const c = s.roles.strata[0];
    for (d.stratum_psus, 0..) |n, h| {
        if (n != 1) continue;
        const v = rows[d.stratum_rep[h]][c].num;
        var level: usize = 1;
        for (d.stratum_rep) |o| {
            const u = rows[o][c].num;
            if (std.math.isNan(v)) break;
            if (std.math.isNan(u) or u < v) level += 1;
        }
        try cx.diags.warn(0, "Stratum level {d} contains only a single cluster. Single-cluster strata are not included in the variance estimates.", .{level});
    }
}

/// One analysis group (the whole input, or one BY group).
pub fn plan(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Result {
    const a = cx.arena;
    var sum_read: f64 = 0;
    var kept: std.ArrayList([]const Value) = .empty;
    var freq_of: std.ArrayList(f64) = .empty;
    var model_missing: usize = 0;
    var freq_bad: usize = 0;
    var freq_read: f64 = 0;
    var wfreq_read: f64 = 0;
    for (rows) |obs| {
        const w = if (s.roles.weight) |c| obs[c].num else 1;
        // Sum of Weights Read counts the positive weights only (SAS 9.4 run:
        // a negative weight is excluded and not read).
        if (w > 0) sum_read += w;
        if (obs[s.time.?].num < 0) return gap(cx, 0, "the listing for observations excluded by negative failure times is not verified", .{});
        // Missing MODEL values exclude the observation (p.10043).
        var bad = std.math.isNan(obs[s.time.?].num) or (if (s.censor) |c| std.math.isNan(obs[c].num) else false);
        for (s.covariates) |c| bad = bad or std.math.isNan(obs[c].num);
        var f: f64 = 1;
        if (s.freq) |c| {
            f = @trunc(obs[c].num);
            // A missing or nonpositive frequency excludes the observation
            // (p.10024); its weight is still read (SAS 9.4 run).
            if (!(f >= 1)) {
                freq_bad += 1;
                continue;
            }
            freq_read += f;
            wfreq_read += w * f;
        }
        if (bad) {
            model_missing += 1;
            continue;
        }
        try kept.append(a, obs);
        try freq_of.append(a, f);
    }
    const d = try design.build(a, kept.items, s.roles);
    // Every observation excluded by its WEIGHT: SAS 9.4 writes this ERROR
    // and no listing; other all-excluded inputs are not verified.
    if (d.kept.len == 0 and d.bad_weight == rows.len and s.by_cols.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYPHREG: No nonmissing observations.", .{});
    if (d.kept.len == 0) return gap(cx, 0, "the result for an input without valid observations is not verified", .{});
    const excluded = model_missing + d.bad_weight + d.bad_design + freq_bad;
    // Every exclusion (MODEL, WEIGHT, STRATA, CLUSTER, FREQ) gives the
    // "Missing Values Excluded" row (SAS 9.4 runs). With FREQ, exclusions by
    // FREQ and MODEL values are verified; by WEIGHT or design values not.
    if (s.freq != null and d.bad_weight + d.bad_design > 0) return gap(cx, 0, "the FREQ listing with observations excluded by WEIGHT, STRATA or CLUSTER values is not verified", .{});
    if (d.singlePsuStratum()) try warnSinglePsu(cx, s, kept.items, d);
    if (d.clusters() == d.strata()) return gap(cx, 0, "inference with zero design degrees of freedom is not implemented", .{});
    const freq = try a.alloc(f64, d.kept.len);
    for (d.kept, 0..) |r, k| freq[k] = freq_of.items[r];
    var r = try analyze(cx, s, kept.items, d, freq);
    r.read = rows.len;
    r.sum_weights_read = sum_read;
    r.freq_read = freq_read;
    r.wfreq_read = wfreq_read;
    r.excluded = excluded > 0;
    return r;
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn fixed(a: A, x: f64, comptime decimals: u8) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return fixed(a, p, 4);
}
fn count(a: A, v: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{v});
}
/// One row: left-aligned first text at column 1, then right-aligned fields.
fn row(cx: proc.ProcCtx, out: *Out, width: usize, first: []const u8, fields: []const []const u8, edges: []const usize) diag.Error!void {
    const a = cx.arena;
    const b = try proc.line(a, width);
    proc.putLeft(b, 1, first);
    var left = first.len;
    for (fields, edges) |text, edge| {
        // ponytail: fixed columns as in the reference; wider values need the
        // template's width rules.
        if (text.len + left >= edge) return gap(cx, 0, "listing columns for values wider than the verified layout are not implemented", .{});
        proc.putRight(b, edge, text);
        left = edge;
    }
    try out.appendSlice(a, b);
    try out.append(a, '\n');
}
fn pair(cx: proc.ProcCtx, out: *Out, label: []const u8, value: []const u8, label_width: usize, width: usize) diag.Error!void {
    const a = cx.arena;
    if (label.len > label_width or label_width + value.len > width) return gap(cx, 0, "Model Information values wider than the verified layout are not implemented", .{});
    try out.appendSlice(a, label);
    try out.appendNTimes(a, ' ', label_width - label.len);
    try out.appendSlice(a, value);
    try out.appendNTimes(a, ' ', width - label_width - value.len);
    try out.append(a, '\n');
}

pub fn render(cx: proc.ProcCtx, out: *Out, s: Spec, r: Result) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const cols = ds.columns.items;
    var b: Out = .empty;
    try b.appendSlice(a, "\nThe SURVEYPHREG Procedure\n\n");
    const upper = try std.ascii.allocUpperString(a, s.data_name);
    const dsname = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    // Value column at least 8 wide (the reference's WORK.FQ / BRESLOW rows).
    var width: usize = @max(32, 24 + dsname.len);
    const fname = if (s.freq) |c| cols[c].name else "";
    const wname = if (s.roles.weight) |c| cols[c].name else "";
    const sname = if (s.roles.strata.len > 0) cols[s.roles.strata[0]].name else "";
    const cname = if (s.roles.clusters.len > 0) cols[s.roles.clusters[0]].name else "";
    const names = [_][]const u8{ cols[s.time.?].name, if (s.censor) |c| cols[c].name else "", wname, sname, cname, "BRESLOW", fname };
    for (names) |nm| width = @max(width, 24 + nm.len);
    var cvb: Out = .empty;
    for (s.censor_values, 0..) |v, k| {
        if (k > 0) try cvb.appendSlice(a, "  ");
        try cvb.appendSlice(a, try format.bestNum(a, v));
    }
    const cv = cvb.items;
    for (s.roles.strata) |c| width = @max(width, 24 + cols[c].name.len);
    for (s.roles.clusters) |c| width = @max(width, 24 + cols[c].name.len);
    width = @max(width, 24 + cv.len);
    try centered(a, &b, "Model Information", width);
    try b.append(a, '\n');
    try pair(cx, &b, "Data Set", dsname, 24, width);
    try pair(cx, &b, "Dependent Variable", names[0], 24, width);
    // Without a censoring variable every time is an event and both rows
    // are omitted (SAS 9.4 run).
    if (s.censor != null) {
        try pair(cx, &b, "Censoring Variable", names[1], 24, width);
        try pair(cx, &b, "Censoring Value(s)", cv, 24, width);
    }
    if (s.roles.weight != null) try pair(cx, &b, "Weight Variable", names[2], 24, width);
    if (s.freq != null) try pair(cx, &b, "Frequency Variable", fname, 24, width);
    // Several variables: plural label, one name per line (SAS 9.4 run).
    for (s.roles.strata, 0..) |c, k| try pair(cx, &b, if (k > 0) "" else if (s.roles.strata.len > 1) "Stratum Variables" else "Stratum Variable", cols[c].name, 24, width);
    for (s.roles.clusters, 0..) |c, k| try pair(cx, &b, if (k > 0) "" else if (s.roles.clusters.len > 1) "Cluster Variables" else "Cluster Variable", cols[c].name, 24, width);
    try pair(cx, &b, "Ties Handling", names[5], 24, width);
    try b.appendSlice(a, "\n\n");
    const sw = try format.bestNum(a, r.d.sum_weights);
    try row(cx, &b, 44, "Number of Observations Read", &.{try count(a, r.read)}, &.{44});
    try row(cx, &b, 44, "Number of Observations Used", &.{try count(a, r.n)}, &.{44});
    if (s.roles.weight != null) {
        try row(cx, &b, 44, "Sum of Weights Read", &.{try format.bestNum(a, r.sum_weights_read)}, &.{44});
        try row(cx, &b, 44, "Sum of Weights Used", &.{sw}, &.{44});
    }
    if (s.freq != null) {
        const fu = try format.bestNum(a, r.units);
        const wu = try format.bestNum(a, r.weighted_units);
        try row(cx, &b, 44, "Sum of Frequencies Read", &.{try format.bestNum(a, r.freq_read)}, &.{44});
        try row(cx, &b, 44, "Sum of Frequencies Used", &.{fu}, &.{44});
        try row(cx, &b, 44, "Sum of Weighted Frequencies Read", &.{try format.bestNum(a, r.wfreq_read)}, &.{44});
        try row(cx, &b, 44, "Sum of Weighted Frequencies Used", &.{wu}, &.{44});
    }
    // Design Summary (SAS 9.4 runs): both rows in 32 columns; a single row
    // is label + 14 columns wide; without STRATA and CLUSTER no table.
    const has_s = s.roles.strata.len > 0;
    const has_c = s.roles.clusters.len > 0;
    if (has_s and has_c) {
        try b.appendSlice(a, "\n\n         Design Summary\n\n");
        try row(cx, &b, 32, "Number of Strata", &.{try count(a, r.d.strata())}, &.{32});
        try row(cx, &b, 32, "Number of Clusters", &.{try count(a, r.d.clusters())}, &.{32});
    } else if (has_s) {
        try b.appendSlice(a, "\n\n        Design Summary\n\n");
        try row(cx, &b, 30, "Number of Strata", &.{try count(a, r.d.strata())}, &.{30});
    } else if (has_c) {
        try b.appendSlice(a, "\n\n         Design Summary\n\n");
        try row(cx, &b, 32, "Number of Clusters", &.{try count(a, r.d.clusters())}, &.{32});
    }
    try b.appendSlice(a, "\n\nSummary of the Number of Event and Censored Values\n \n                                     Percent\n   Total       Event    Censored    Censored\n\n");
    try row(cx, &b, 44, "", &.{ try format.bestNum(a, r.units), try format.bestNum(a, r.events), try format.bestNum(a, r.units - r.events), try fixed(a, 100 * (r.units - r.events) / r.units, 2) }, &.{ 8, 20, 32, 44 });
    const sumw = r.weighted_units;
    if (s.roles.weight != null) try b.appendSlice(a, "\n\nSummary of the Weighted Number of Event and Censored Values\n \n                                     Percent\n   Total       Event    Censored    Censored\n\n");
    if (s.roles.weight != null) try row(cx, &b, 44, "", &.{ try format.bestNum(a, sumw), try format.bestNum(a, r.weighted_events), try format.bestNum(a, sumw - r.weighted_events), try fixed(a, 100 * (sumw - r.weighted_events) / sumw, 2) }, &.{ 8, 20, 32, 44 });
    if (r.excluded) {
        try b.appendSlice(a, "\n\n      Variance Estimation\n\nMethod            Taylor Series\nMissing Values         Excluded\n\n\n");
    } else try b.appendSlice(a, "\n\n  Variance Estimation\n\nMethod    Taylor Series\n\n\n");
    try b.appendSlice(a, "         Model Fit Statistics\n \n                 Without           With\nCriterion     Covariates     Covariates\n\n");
    const pf: f64 = @floatFromInt(s.covariates.len);
    try row(cx, &b, 39, "-2 LOG L", &.{ try fixed(a, r.neg2ll_null, 3), try fixed(a, r.neg2ll, 3) }, &.{ 24, 39 });
    try row(cx, &b, 39, "AIC", &.{ try fixed(a, r.neg2ll_null, 3), try fixed(a, r.neg2ll + 2 * pf, 3) }, &.{ 24, 39 });
    try b.appendSlice(a, "\n\n                 Testing Global Null Hypothesis: BETA=0\n \n                                    Test       Num       Den\nTest                           Statistic        DF        DF     p-Value\n\n");
    const dfs = try count(a, r.df);
    try row(cx, &b, 72, "Likelihood Ratio (Unadj.)", &.{ try fixed(a, r.lr, 4), "1", "Infty", try pvalue(a, lifetest.chiProbability(r.lr, 1)) }, &.{ 40, 50, 60, 72 });
    try row(cx, &b, 72, "Likelihood Ratio (Adj.)", &.{ try fixed(a, r.lr_adj, 4), "1", "Infty", try pvalue(a, lifetest.chiProbability(r.lr_adj, 1)) }, &.{ 40, 50, 60, 72 });
    try row(cx, &b, 72, "Wald", &.{ try fixed(a, r.wald, 4), "1", dfs, try pvalue(a, reg.fProbability(r.wald, 1, r.df)) }, &.{ 40, 50, 60, 72 });
    try b.appendSlice(a, "\n\n                      Analysis of Maximum Likelihood Estimates\n \n                                          Standard                             Hazard\nParameter       DF        Estimate           Error    t Value    Pr > |t|       Ratio\n\n");
    const p = s.covariates.len;
    for (0..p) |j| {
        const se = @sqrt(r.covariance[j * p + j]);
        const tv = r.beta[j] / se;
        const hr = @exp(r.beta[j]);
        if (!(hr < 999.9995)) return gap(cx, 0, "hazard ratios of 1000 or more (>999.999 display) are not implemented", .{});
        try row(cx, &b, 85, cols[s.covariates[j]].name, &.{ dfs, try fixed(a, r.beta[j], 6), try fixed(a, se, 6), try fixed(a, tv, 2), try pvalue(a, reg.tProbability(tv, r.df)), try fixed(a, hr, 3) }, &.{ 18, 34, 50, 61, 73, 85 });
    }
    try out.appendSlice(a, b.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    try checkSupported(cx, s);
    const ds = s.input.ds;
    const slices = try by.checkedSlices(cx.arena, ds, s.by_cols, s.by_desc, s.by_notsorted, cx.diags);
    // An empty input without BY is a data error (SAS 9.4 run: ERROR, no
    // listing); empty BY input is not verified.
    if ((slices.len == 0 or slices[0].rows.len == 0) and s.by_cols.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYPHREG: No valid observations present.", .{});
    if (slices.len == 0 or slices[0].rows.len == 0) return gap(cx, 0, "the result for an empty BY input data set is not verified", .{});
    // Every group is computed before any text exists.
    const results = try cx.arena.alloc(Result, slices.len);
    for (slices, results) |slice, *r| r.* = try plan(cx, s, slice.rows);
    for (slices, results) |slice, r| {
        if (s.noprint) break;
        if (s.by_cols.len > 0) try by.appendLine(cx.arena, out, ds, slice.rep.?, s.by_cols);
        try render(cx, out, s, r);
    }
    try cx.diags.note(s.model_line, "Convergence criterion (GCONV=1E-8) satisfied.", .{});
}

test "STAT-SURVEYPHREG-001 weighted Breslow partial likelihood and score residuals by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Three subjects, times 1, 2, 3, all events, z = 0, 1, 0, weights 1, 2, 1.
    // At b = 0: S0(1) = 4, S0(2) = 3, S0(3) = 1; log L0 = -log 4 - 2 log 3 - 0.
    const c: Cox = .{ .n = 3, .p = 1, .x = &.{ 0, 1, 0 }, .time = &.{ 1, 2, 3 }, .event = &.{ true, true, true }, .weight = &.{ 1, 2, 1 } };
    var u: [1]f64 = undefined;
    var info: [1]f64 = undefined;
    const ll = try c.evaluate(a, &.{0}, &u, &info);
    try std.testing.expectApproxEqAbs(-@log(4.0) - 2 * @log(3.0), ll, 1e-12);
    // Zbar(1) = 2/4, Zbar(2) = 2/3, Zbar(3) = 0. U = 1(0-1/2) + 2(1-2/3) + 0 = 1/6.
    try std.testing.expectApproxEqAbs(1.0 / 6.0, u[0], 1e-12);
    // I = 1(1/2 - 1/4) + 2(2/3 - 4/9) + 1(0) = 1/4 + 4/9.
    try std.testing.expectApproxEqAbs(0.25 + 4.0 / 9.0, info[0], 1e-12);
    const res = try c.scoreResiduals(a, &.{0});
    // L_1 = (0 - 1/2) - 1/4 (0 - 1/2) = -3/8.
    try std.testing.expectApproxEqAbs(-0.375, res[0], 1e-12);
    // L_2 = (1 - 2/3) - [1/4 (1 - 1/2) + 2/3 (1 - 2/3)] = 1/3 - 1/8 - 2/9.
    try std.testing.expectApproxEqAbs(1.0 / 3.0 - 0.125 - 2.0 / 9.0, res[1], 1e-12);
    // The weighted residuals sum to the score.
    try std.testing.expectApproxEqAbs(u[0], res[0] + 2 * res[1] + res[2], 1e-12);
}

test "STAT-SURVEYPHREG-001 fit reaches a zero score" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const c: Cox = .{ .n = 5, .p = 1, .x = &.{ 1, 3, 2, 5, 4 }, .time = &.{ 2, 1, 4, 3, 5 }, .event = &.{ true, true, false, true, true }, .weight = &.{ 1, 2, 1, 1.5, 1 } };
    const f = try fit(a, c);
    try std.testing.expect(f.converged);
    var u: [1]f64 = undefined;
    var info: [1]f64 = undefined;
    _ = try c.evaluate(a, f.beta, &u, &info);
    try std.testing.expectApproxEqAbs(@as(f64, 0), u[0], 1e-6);
    try std.testing.expect(f.ll >= f.ll0);
}
