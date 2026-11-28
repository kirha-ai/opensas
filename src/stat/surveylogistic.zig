//! PROC SURVEYLOGISTIC declarations, variable roles, observation selection and
//! the default listing of a binary logit model with continuous covariates
//! under Taylor-series (linearization) variance estimation, SAS/STAT 15.4
//! physical pp.9786-9790, 9803-9840 and 9843-9857: Model Information,
//! Variance Estimation, observation counts and weights, Response Profile,
//! convergence, fit statistics, global tests (first-order Rao-Scott
//! likelihood ratio, score, Wald), parameter estimates with t tests, odds
//! ratios and association statistics. Every other documented feature is a
//! D-009 gap (rc 2) raised before any listing text exists.
//! ponytail: the design reuses surveyfreq_design (valid-observation rules,
//! PSUs nested in strata); STAT-COMMON-016 owns unifying the survey kernels.
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
const kernel = @import("logistic_fit.zig");
const reg = @import("reg_fit.zig");
pub const design = @import("surveyfreq_design.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Event = union(enum) {
    /// Default: the lowest Ordered Value is modeled.
    first,
    descending,
    /// EVENT='formatted value'.
    value: []const u8,
};

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    roles: design.Roles = .{},
    alpha: f64 = 0.05,
    response: ?usize = null,
    event: Event = .first,
    covariates: []const usize = &.{},
    model_line: usize = 0,
    by_cols: []const usize = &.{},
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYLOGISTIC: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYLOGISTIC: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return x;
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

/// Documented MODEL options (Table 120.6) owned by later SURVEYLOGISTIC tickets.
const later_model_options = [_][]const u8{ "absfconv", "fconv", "gconv", "xconv", "maxiter", "maxstep", "ridging", "singular", "corrb", "covb", "clodds", "clparm", "df", "expb", "itprint", "noint", "nodummyprint", "noodds", "offset", "parmlabel", "rsquare", "stb", "chisq", "alpha", "orpvalue", "rsq", "influence", "lackfit", "aggregate", "scale", "ctable", "pprob", "outroc", "roceps", "fast", "selection", "include", "start", "stop", "best", "sequential", "slentry", "slstay", "details" };

fn parseModel(cx: proc.ProcCtx, s: *Spec, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    var i = start;
    s.model_line = t[i].line;
    const response = try column(cx, ds, t, i);
    i += 1;
    if (at(t, i, .slash)) return gap(cx, t[i].line, "events/trials MODEL syntax is not implemented", .{});
    if (at(t, i, .lparen)) {
        i += 1;
        while (!at(t, i, .rparen)) {
            if (i >= end or !at(t, i, .name)) return invalid(cx, t, i);
            const o = t[i].text;
            if (oneOf(o, &.{ "descending", "desc" })) {
                if (s.event != .first) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: only one of the EVENT= and DESCENDING response options can be specified", .{});
                s.event = .descending;
                i += 1;
            } else if (eq(o, "event") and at(t, i + 1, .eq)) {
                if (s.event != .first) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: only one of the EVENT= and DESCENDING response options can be specified", .{});
                if (at(t, i + 2, .string) or at(t, i + 2, .number)) {
                    s.event = .{ .value = std.mem.trim(u8, t[i + 2].text, " ") };
                } else if (at(t, i + 2, .name) and oneOf(t[i + 2].text, &.{ "first", "last" })) {
                    return gap(cx, t[i].line, "EVENT={s} is not implemented", .{t[i + 2].text});
                } else return invalid(cx, t, i + 2);
                i += 3;
            } else if (eq(o, "order") and at(t, i + 1, .eq)) {
                if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
                const v = t[i + 2].text;
                // Numeric unformatted responses order alike under both.
                if (!oneOf(v, &.{ "internal", "formatted" })) {
                    if (oneOf(v, &.{ "data", "freq" })) return gap(cx, t[i].line, "response option ORDER={s} is not implemented", .{v});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (oneOf(o, &.{ "reference", "ref" })) {
                return gap(cx, t[i].line, "response option {s}= is not implemented", .{o});
            } else return invalid(cx, t, i);
        }
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
            if (oneOf(o, &.{ "link", "l" }) and valued) {
                if (!oneOf(value, &.{ "logit", "logistic" })) {
                    if (oneOf(value, &.{ "probit", "normit", "cloglog", "cll", "glogit", "complementary" })) return gap(cx, t[i].line, "LINK={s} is not implemented", .{value});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (oneOf(o, &.{ "technique", "tech" }) and valued) {
                if (!oneOf(value, &.{ "fisher", "fisherscoring" })) {
                    if (oneOf(value, &.{ "newton", "nr", "newtonraphson" })) return gap(cx, t[i].line, "TECHNIQUE={s} is not implemented", .{value});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (eq(o, "vadjust") and valued) {
                if (!eq(value, "df")) {
                    if (oneOf(value, &.{ "morel", "none" })) return gap(cx, t[i].line, "VADJUST={s} is not implemented", .{value});
                    return invalid(cx, t, i + 2);
                }
                i += 3;
            } else if (oneOf(o, &later_model_options)) {
                return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{o});
            } else return invalid(cx, t, i);
        }
    }
    s.response = response;
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
        } else if (eq(word, "alpha") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYLOGISTIC: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
        } else if (oneOf(word, &.{ "nomcar", "nosort", "namelen", "inest", "noprint", "plots", "plot", "ordinal" })) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "data", "freq" })) return gap(cx, t[i].line, "ORDER={s} is not implemented", .{v});
            // CLASS ordering only; numeric unformatted variables order alike.
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
            const is_rate = eq(word[0..1], "r");
            if (s.roles.fpc != .none) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: only one of the RATE= and TOTAL= options can be specified", .{});
            if (at(t, i + 2, .name)) return gap(cx, t[i].line, "{s}=SAS-data-set (stratum-level values) is not implemented", .{word});
            i += 2;
            const x = try number(cx, t, &i);
            if (is_rate) {
                if (!(x > 0 and x <= 100)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYLOGISTIC: RATE= must be a positive number not above 100", .{});
                s.roles.fpc = .{ .rate = if (x == 1) 1 else if (x > 1) x / 100 else x };
            } else {
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYLOGISTIC: TOTAL= must be a positive number", .{});
                s.roles.fpc = .{ .total = x };
            }
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYLOGISTIC: input dataset not found", .{});
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
            // Only one MODEL statement is allowed (p.9790).
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: only one MODEL statement is allowed", .{});
            model_seen = true;
            try parseModel(cx, &s, ds, t, i + 1, end);
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: only one WEIGHT statement is allowed", .{});
            weight_seen = true;
            if (end != i + 2) return invalid(cx, t, i + 2);
            const c = try column(cx, ds, t, i + 1);
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYLOGISTIC: WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.roles.weight = c;
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            if (s.roles.strata.len > 0) return gap(cx, t[i].line, "several STRATA statements are not implemented", .{});
            s.roles.strata = try roleColumns(cx, ds, t, i + 1, end, "STRATA");
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            if (s.roles.clusters.len > 0) return gap(cx, t[i].line, "several CLUSTER statements are not implemented", .{});
            s.roles.clusters = try roleColumns(cx, ds, t, i + 1, end, "CLUSTER");
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (oneOf(t[i].text, &.{ "class", "freq", "domain", "repweights", "repweight", "contrast", "effect", "estimate", "lsmeans", "lsmestimate", "output", "slice", "store", "test", "units", "format" }) and at(t, i, .name)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) {
            if (at(t, i + 1, .colon) or at(t, i, .string)) return gap(cx, t[i].line, "labeled TEST statements are not implemented", .{});
            return invalid(cx, t, i);
        }
        i = end + 1;
    }
    // The PROC SURVEYLOGISTIC and MODEL statements are required (p.9790).
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYLOGISTIC: a MODEL statement is required", .{});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    return s;
}

pub const Level = struct { value: f64, count: usize, weight: f64 };

/// Everything the listing shows, computed before any text exists.
pub const Result = struct {
    d: design.Design,
    levels: [2]Level,
    /// Index into `levels` of the modeled event (Ordered Value - 1 ordering).
    event: usize,
    n: usize,
    p: usize,
    coefficients: []const f64,
    /// Design (sandwich) covariance, p x p.
    covariance: []const f64,
    neg2ll: f64,
    neg2ll_null: f64,
    sum_weights: f64,
    /// Design degrees of freedom f.
    df: usize,
    lr_f: f64,
    correction: f64,
    score_f: f64,
    wald_f: f64,
    assoc: kernel.WeightedAssociation,
};

fn invert(a: A, m: []const f64, p: usize) diag.Error![]f64 {
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
        if (!(@abs(w[piv * 2 * p + col]) > 1e-300)) return error.ExecError;
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

/// G = (n-1)/(n-p) sum_h n_h (1-f_h)/(n_h-1) sum_i (e_hi - ebar_h)(e_hi - ebar_h)',
/// e_hi = sum_j w_hij (y_hij - mu_hij) x_hij (p.9844, binary logit).
fn meatMatrix(a: A, d: design.Design, x: []const f64, y: []const f64, mu: []const f64, p: usize) ![]f64 {
    const e = try a.alloc(f64, d.clusters() * p);
    @memset(e, 0);
    for (0..d.kept.len) |k| for (0..p) |j| {
        e[d.psu[k] * p + j] += d.weight[k] * (y[k] - mu[k]) * x[k * p + j];
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
        const factor = nh * d.stratum_fpc[h] / (nh - 1);
        for (0..p) |r| for (0..p) |s| {
            g[r * p + s] += factor * (e[c * p + r] - mean[h * p + r]) * (e[c * p + s] - mean[h * p + s]);
        };
    }
    const n: f64 = @floatFromInt(d.kept.len);
    const pf: f64 = @floatFromInt(p);
    for (g) |*v| v.* *= (n - 1) / (n - pf);
    return g;
}

/// Meat of the simple-random-sampling Taylor covariance:
/// n/(n-p) sum_i (e_i - ebar)(e_i - ebar)', e_i = w_i (y_i - mu_i) x_i.
fn srsMeat(a: A, d: design.Design, x: []const f64, y: []const f64, mu: []const f64, p: usize) ![]f64 {
    const n = d.kept.len;
    const mean = try a.alloc(f64, p);
    @memset(mean, 0);
    for (0..n) |k| for (0..p) |j| {
        mean[j] += d.weight[k] * (y[k] - mu[k]) * x[k * p + j] / @as(f64, @floatFromInt(n));
    };
    const g = try a.alloc(f64, p * p);
    @memset(g, 0);
    for (0..n) |k| for (0..p) |r| for (0..p) |c| {
        const er = d.weight[k] * (y[k] - mu[k]) * x[k * p + r] - mean[r];
        const ec = d.weight[k] * (y[k] - mu[k]) * x[k * p + c] - mean[c];
        g[r * p + c] += er * ec;
    };
    const nf: f64 = @floatFromInt(n);
    const pf: f64 = @floatFromInt(p);
    for (g) |*v| v.* *= nf / (nf - pf);
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

/// Fit and inference for one validated design. `rows` are the slice rows.
pub fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, d: design.Design) diag.Error!Result {
    const a = cx.arena;
    const n = d.kept.len;
    const p = s.covariates.len + 1;
    const resp = s.response.?;
    var levels: std.ArrayList(Level) = .empty;
    for (d.kept, d.weight) |r, w| {
        const v = rows[r][resp].num;
        for (levels.items) |*l| {
            if (l.value == v) {
                l.count += 1;
                l.weight += w;
                break;
            }
        } else try levels.append(a, .{ .value = v, .count = 1, .weight = w });
    }
    if (levels.items.len != 2) {
        if (levels.items.len > 2) return gap(cx, s.model_line, "response variables with more than two levels (cumulative logit model) are not implemented", .{});
        return cx.diags.fail(error.ParseError, s.model_line, "PROC SURVEYLOGISTIC: the response variable must have at least two levels", .{});
    }
    std.mem.sort(Level, levels.items, {}, struct {
        fn lt(_: void, l: Level, r: Level) bool {
            return l.value < r.value;
        }
    }.lt);
    var ordered = [2]Level{ levels.items[0], levels.items[1] };
    if (s.event == .descending) std.mem.swap(Level, &ordered[0], &ordered[1]);
    var event: usize = 0;
    switch (s.event) {
        .first, .descending => {},
        .value => |text| {
            var found: ?usize = null;
            for (ordered, 0..) |l, k| if (std.mem.eql(u8, std.mem.trim(u8, try format.bestNum(a, l.value), " "), text)) {
                found = k;
            };
            event = found orelse return cx.diags.fail(error.ParseError, s.model_line, "PROC SURVEYLOGISTIC: the response level {s} specified in the EVENT= option is not found", .{text});
        },
    }
    const x = try a.alloc(f64, n * p);
    const y = try a.alloc(f64, n);
    for (d.kept, 0..) |r, k| {
        x[k * p] = 1;
        for (s.covariates, 1..) |c, j| x[k * p + j] = rows[r][c].num;
        y[k] = if (rows[r][resp].num == ordered[event].value) 1 else 0;
    }
    const fit = kernel.fitWeighted(a, x, y, n, p, null, d.weight, .{ .technique = .fisher }) catch
        return gap(cx, s.model_line, "the listing for a model whose maximum likelihood fit does not converge or has separated or singular data is not implemented", .{});
    if (!fit.converged) return gap(cx, s.model_line, "the listing for a model without convergence is not implemented", .{});
    const meat = try meatMatrix(a, d, x, y, fit.probabilities, p);
    const cov = try sandwich(a, fit.covariance, meat, p);
    const df = if (s.roles.clusters.len > 0) d.clusters() - d.strata() else n - d.strata();
    // Wald, one restriction: F = b^2 / V (p.9856, r = 1).
    const wald_f = fit.coefficients[1] * fit.coefficients[1] / cov[p + 1];
    // Likelihood ratio with normalized weights (p.9854): Q = (n / sum w) LR.
    const nf: f64 = @floatFromInt(n);
    const lr = (nf / d.sum_weights) * 2 * (fit.log_likelihood - fit.null_log_likelihood);
    // Design effect of the slope (p.9854): V_rr / V_rr^srs, V^srs the
    // Taylor-series covariance of the same fit under simple random sampling
    // (one stratum, every observation its own PSU, no FPC). It reproduces the
    // reference correction; the inverse normalized information does not.
    const srs = try sandwich(a, fit.covariance, try srsMeat(a, d, x, y, fit.probabilities, p), p);
    const correction = cov[p + 1] / srs[p + 1];
    // Score at the intercept-only fit: g' G~^-1 g with g the weighted score
    // vector and G~ the design meat matrix, both evaluated at the null fit.
    var events: f64 = 0;
    for (y, d.weight) |v, w| events += v * w;
    const mu0 = try a.alloc(f64, n);
    @memset(mu0, events / d.sum_weights);
    const g = try a.alloc(f64, p);
    @memset(g, 0);
    for (0..n) |k| for (0..p) |j| {
        g[j] += d.weight[k] * (y[k] - mu0[k]) * x[k * p + j];
    };
    const meat0 = try invert(a, try meatMatrix(a, d, x, y, mu0, p), p);
    var score: f64 = 0;
    for (0..p) |r| for (0..p) |c| {
        score += g[r] * meat0[r * p + c] * g[c];
    };
    const ones = try a.alloc(f64, n);
    @memset(ones, 1);
    return .{
        .d = d,
        .levels = ordered,
        .event = event,
        .n = n,
        .p = p,
        .coefficients = fit.coefficients,
        .covariance = cov,
        .neg2ll = -2 * fit.log_likelihood,
        .neg2ll_null = -2 * fit.null_log_likelihood,
        .sum_weights = d.sum_weights,
        .df = df,
        .lr_f = lr / correction,
        .correction = correction,
        .score_f = score,
        .wald_f = wald_f,
        .assoc = kernel.associationWeighted(y, fit.probabilities, ones),
    };
}

pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error!Result {
    const a = cx.arena;
    const ds = s.input.ds;
    const resp = s.response.?;
    const rv = ds.columns.items[resp];
    if (rv.type != .num or rv.format != null) return gap(cx, s.model_line, "character or formatted response variables are not implemented", .{});
    if (s.covariates.len == 0) return gap(cx, s.model_line, "the intercept-only model listing is not implemented", .{});
    if (s.covariates.len > 1) return gap(cx, s.model_line, "global tests with more than one restriction (second-order Rao-Scott default) are not implemented", .{});
    if (s.roles.weight == null) return gap(cx, 0, "the listing without a WEIGHT statement is not verified", .{});
    if (s.roles.strata.len == 0 and s.roles.clusters.len == 0) return gap(cx, 0, "the unadjusted likelihood ratio test of a design without STRATA or CLUSTER is not implemented", .{});
    if (s.roles.strata.len > 1 or s.roles.clusters.len > 1) return gap(cx, 0, "Model Information for several STRATA or CLUSTER variables is not verified", .{});
    if (s.roles.fpc != .none) return gap(cx, 0, "the listing with RATE= or TOTAL= (finite population correction) is not verified", .{});
    // Raised before per-group checks so a BY request never reports a group
    // data error first.
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group processing and listing layout are not verified", .{});
    const slices = try by.checkedSlices(a, ds, s.by_cols, &.{}, false, cx.diags);
    if (slices.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    const rows = slices[0].rows;
    // Missing response or covariate values exclude the observation (MCAR, p.9828).
    for (rows) |obs| {
        var missing = std.math.isNan(obs[resp].num);
        for (s.covariates) |c| missing = missing or std.math.isNan(obs[c].num);
        if (missing) return gap(cx, 0, "the listing for observations excluded by missing MODEL values is not verified", .{});
    }
    const d = try design.build(a, rows, s.roles);
    if (d.kept.len == 0) return gap(cx, 0, "the result for an input without valid observations is not verified", .{});
    if (d.bad_weight + d.bad_design > 0) return gap(cx, 0, "the listing for input with observations excluded by missing or nonpositive WEIGHT, STRATA or CLUSTER values is not verified", .{});
    if (d.singlePsuStratum()) return gap(cx, 0, "variance estimation for a stratum with a single cluster is not implemented", .{});
    const df = if (s.roles.clusters.len > 0) d.clusters() - d.strata() else d.kept.len - d.strata();
    if (df == 0) return gap(cx, 0, "inference with zero design degrees of freedom is not implemented", .{});
    return analyze(cx, s, rows, d);
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
    const rname = ds.columns.items[s.response.?].name;
    var b: Out = .empty;
    try b.appendSlice(a, "\nThe SURVEYLOGISTIC Procedure\n\n");
    try centered(a, &b, "Model Information", 53);
    try b.append(a, '\n');
    const upper = try std.ascii.allocUpperString(a, s.data_name);
    const dsname = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    const count = struct {
        fn f(al: A, v: usize) ![]const u8 {
            return std.fmt.allocPrint(al, "{d}", .{v});
        }
    }.f;
    try pair(cx, &b, "Data Set", dsname, 30, 53);
    try pair(cx, &b, "Response Variable", rname, 30, 53);
    try pair(cx, &b, "Number of Response Levels", "2", 30, 53);
    if (s.roles.strata.len > 0) {
        try pair(cx, &b, "Stratum Variable", ds.columns.items[s.roles.strata[0]].name, 30, 53);
        try pair(cx, &b, "Number of Strata", try count(a, r.d.strata()), 30, 53);
    }
    if (s.roles.clusters.len > 0) {
        try pair(cx, &b, "Cluster Variable", ds.columns.items[s.roles.clusters[0]].name, 30, 53);
        try pair(cx, &b, "Number of Clusters", try count(a, r.d.clusters()), 30, 53);
    }
    try pair(cx, &b, "Weight Variable", ds.columns.items[s.roles.weight.?].name, 30, 53);
    try pair(cx, &b, "Model", "Binary Logit", 30, 53);
    try pair(cx, &b, "Optimization Technique", "Fisher's Scoring", 30, 53);
    try pair(cx, &b, "Variance Adjustment", "Degrees of Freedom (DF)", 30, 53);
    try b.appendSlice(a, "\n\n");
    try centered(a, &b, "Variance Estimation", 46);
    try b.append(a, '\n');
    try b.appendSlice(a, "Method                           Taylor Series\nVariance Adjustment    Degrees of Freedom (DF)\n\n\n");
    const sw = try format.bestNum(a, r.sum_weights);
    try row(cx, &b, 39, "Number of Observations Read", &.{try count(a, r.d.read)}, &.{39});
    try row(cx, &b, 39, "Number of Observations Used", &.{try count(a, r.n)}, &.{39});
    try row(cx, &b, 39, "Sum of Weights Read", &.{sw}, &.{39});
    try row(cx, &b, 39, "Sum of Weights Used", &.{sw}, &.{39});
    try b.appendSlice(a, "\n\n");
    try centered(a, &b, "Response Profile", 52);
    try b.appendSlice(a, " \n Ordered                      Total            Total\n");
    try row(cx, &b, 52, "   Value", &.{ rname, "Frequency", "Weight" }, &.{ 21, 35, 52 });
    try b.append(a, '\n');
    for (r.levels, 0..) |l, k| try row(cx, &b, 52, "", &.{ try count(a, k + 1), try format.bestNum(a, l.value), try count(a, l.count), try fixed(a, l.weight, 5) }, &.{ 8, 21, 35, 52 });
    try b.append(a, '\n');
    try b.print(a, "Probability modeled is {s}={s}.\n\n\n", .{ rname, try format.bestNum(a, r.levels[r.event].value) });
    try centered(a, &b, "Model Convergence Status", 64);
    try b.append(a, '\n');
    try b.appendSlice(a, "         Convergence criterion (GCONV=1E-8) satisfied.          \n\n\n");
    try centered(a, &b, "Model Fit Statistics", 38);
    try b.appendSlice(a, " \n                             Intercept\n              Intercept            and\nCriterion          Only     Covariates\n\n");
    const pf: f64 = @floatFromInt(r.p);
    const lnw = @log(r.sum_weights);
    try row(cx, &b, 38, "AIC", &.{ try fixed(a, r.neg2ll_null + 2, 3), try fixed(a, r.neg2ll + 2 * pf, 3) }, &.{ 23, 38 });
    try row(cx, &b, 38, "SC", &.{ try fixed(a, r.neg2ll_null + lnw, 3), try fixed(a, r.neg2ll + pf * lnw, 3) }, &.{ 23, 38 });
    try row(cx, &b, 38, "-2 Log L", &.{ try fixed(a, r.neg2ll_null, 3), try fixed(a, r.neg2ll, 3) }, &.{ 23, 38 });
    try b.appendSlice(a, "\n\n");
    try centered(a, &b, "Testing Global Null Hypothesis: BETA=0", 65);
    try b.appendSlice(a, " \nTest                 F Value       Num DF       Den DF     Pr > F\n\n");
    const dfs = try count(a, r.df);
    const tests = [_]struct { []const u8, f64 }{ .{ "Likelihood Ratio", r.lr_f }, .{ "Score", r.score_f }, .{ "Wald", r.wald_f } };
    for (tests) |te| try row(cx, &b, 65, te[0], &.{ try fixed(a, te[1], 2), "1", dfs, try pvalue(a, reg.fProbability(te[1], 1, r.df)) }, &.{ 28, 41, 54, 65 });
    try b.append(a, '\n');
    const corr = try fixed(a, r.correction, 4);
    if (corr.len != 6) return gap(cx, 0, "the Rao-Scott note for a design correction of 10 or more is not verified", .{});
    try centered(a, &b, "NOTE: First-order Rao-Scott design correction", 65);
    try centered(a, &b, try std.fmt.allocPrint(a, "{s} applied to the likelihood ratio test.", .{corr}), 65);
    try b.appendSlice(a, "\n\n");
    try centered(a, &b, "Analysis of Maximum Likelihood Estimates", 56);
    try b.appendSlice(a, " \n                         Standard\nParameter    Estimate       Error    t Value    Pr > |t|\n\n");
    for (0..r.p) |j| {
        const name = if (j == 0) "Intercept" else ds.columns.items[s.covariates[j - 1]].name;
        const se = @sqrt(r.covariance[j * r.p + j]);
        const tv = r.coefficients[j] / se;
        try row(cx, &b, 56, name, &.{ try fixed(a, r.coefficients[j], 4), try fixed(a, se, 4), try fixed(a, tv, 2), try pvalue(a, reg.tProbability(tv, r.df)) }, &.{ 21, 33, 44, 56 });
    }
    try b.append(a, '\n');
    try centered(a, &b, try std.fmt.allocPrint(a, "NOTE: The degrees of freedom for the t tests is {d}.", .{r.df}), 56);
    try b.appendSlice(a, "\n\n");
    try centered(a, &b, "Odds Ratio Estimates", 42);
    const pct = try format.bestNum(a, 100 * (1 - s.alpha));
    if (pct.len != 2) return gap(cx, 0, "odds ratio confidence headers for ALPHA= levels other than two-digit percentages are not verified", .{});
    try b.print(a, "                     \n             Point       {s}% Confidence\nEffect    Estimate           Limits\n\n", .{pct});
    const tc = reg.tCritical(s.alpha, r.df);
    for (1..r.p) |j| {
        const se = @sqrt(r.covariance[j * r.p + j]);
        const est = r.coefficients[j];
        const ors = [_]f64{ @exp(est), @exp(est - tc * se), @exp(est + tc * se) };
        for (ors) |v| if (!(v < 999.9995)) return gap(cx, 0, "odds ratios of 1000 or more (>999.999 display) are not implemented", .{});
        try row(cx, &b, 42, ds.columns.items[s.covariates[j - 1]].name, &.{ try fixed(a, ors[0], 3), try fixed(a, ors[1], 3), try fixed(a, ors[2], 3) }, &.{ 18, 30, 42 });
    }
    try b.append(a, '\n');
    try centered(a, &b, "NOTE: The degrees of freedom in computing", 42);
    try centered(a, &b, try std.fmt.allocPrint(a, "the confidence limits is {d}.", .{r.df}), 42);
    try b.appendSlice(a, "\n\n");
    const as = r.assoc;
    const nf: f64 = @floatFromInt(r.n);
    const gamma = if (as.concordant + as.discordant > 0) (as.concordant - as.discordant) / (as.concordant + as.discordant) else std.math.nan(f64);
    try b.appendSlice(a, "Association of Predicted Probabilities and Observed Responses\n\n");
    const lines = [_]struct { []const u8, []const u8, []const u8, []const u8 }{
        .{ "Percent Concordant", try fixed(a, 100 * as.concordant / as.pairs, 1), "Somers' D", try fixed(a, (as.concordant - as.discordant) / as.pairs, 3) },
        .{ "Percent Discordant", try fixed(a, 100 * as.discordant / as.pairs, 1), "Gamma", try fixed(a, gamma, 3) },
        .{ "Percent Tied", try fixed(a, 100 * as.tied / as.pairs, 1), "Tau-a", try fixed(a, 2 * (as.concordant - as.discordant) / (nf * (nf - 1)), 3) },
        .{ "Pairs", try format.bestNum(a, as.pairs), "c", try fixed(a, (as.concordant + 0.5 * as.tied) / as.pairs, 3) },
    };
    for (lines) |l| {
        const ln = try proc.line(a, 49);
        proc.putLeft(ln, 1, l[0]);
        if (l[1].len > 8) return gap(cx, 0, "association values wider than the verified layout are not implemented", .{});
        proc.putRight(ln, 27, l[1]);
        proc.putLeft(ln, 32, l[2]);
        proc.putRight(ln, 49, l[3]);
        try b.appendSlice(a, ln);
        try b.append(a, '\n');
    }
    try cx.diags.note(s.model_line, "PROC SURVEYLOGISTIC is modeling the probability that {s}={s}.", .{ rname, try format.bestNum(a, r.levels[r.event].value) });
    try cx.diags.note(s.model_line, "Convergence criterion (GCONV=1E-8) satisfied.", .{});
    try out.appendSlice(a, b.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const r = try plan(cx, s);
    try render(cx, out, s, r);
}

test {
    _ = @import("surveylogistic_tests.zig");
}
