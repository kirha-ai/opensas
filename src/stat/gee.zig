//! PROC GEE (SAS/STAT 15.4 ch.50) — STAT-GEE-001: PROC statement options,
//! variable roles (BY/CLASS/MODEL/REPEATED/FREQ/WEIGHT), observation
//! selection and the default listing of the binary-logit model with an
//! exchangeable working correlation (Getting Started, Figures 50.1–50.7).
//! Physical PDF pp.3426–3428 (PROC GEE, BY, CLASS), 3431–3432 (FREQ),
//! 3435–3436 (MODEL DIST=/LINK=), 3439–3442 (REPEATED), 3444 (WEIGHT).
//!
//! Fit (standard GEE, Liang and Zeger 1986): independence logistic start,
//! then Fisher-scoring updates with the moment estimates
//!   phi   = sum e^2 / (N - p)
//!   alpha = sum_i sum_{j<k} e_ij e_ik / ((sum_i n_i(n_i-1)/2 - p) phi)
//! of the exchangeable working correlation, e the Pearson residuals.
//! Model-based covariance I0^-1, empirical I0^-1 I1 I0^-1 (sandwich);
//! QIC = -2Q + 2 trace(Omega_I V_R), QICu = -2Q + 2p (Pan 2001).
//!
//! ponytail: everything outside that verified slice — other DIST=/LINK=,
//! TYPE= other than EXCH/CS, WITHIN=, LOGOR=, FREQ, WEIGHT, MISSMODEL,
//! CLASS options, crossed/nested effects, observations dropped for missing
//! values, the later statements — is a D-009 gap (exit 2) that prints nothing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const kernel = @import("genmod_binomial.zig");
const linalg = @import("genmod_fit.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    descending: bool = false,
    namelen: usize = 20,
    order: classes.Order = .formatted,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    class: []const usize = &.{},
    response: usize = 0,
    effects: []const usize = &.{},
    dist: ?[]const u8 = null,
    link: ?[]const u8 = null,
    subject: usize = 0,
    exchangeable: bool = false,
    covb: bool = false,
    corrw: bool = false,
    maxiter: usize = 50,
    converge: f64 = 1e-4,
    frequency: ?usize = null,
    weight: ?usize = null,
    /// The first construct that parses but is not implemented: reported at run.
    gap: ?[]const u8 = null,
    gap_line: usize = 0,
};

/// Statements owned by later GEE tickets.
const later = [_][2][]const u8{
    .{ "missmodel", "STAT-GEE-004" },  .{ "estimate", "STAT-GEE-007" },
    .{ "lsmeans", "STAT-GEE-008" },    .{ "lsmestimate", "STAT-GEE-008" },
    .{ "slice", "STAT-GEE-008" },      .{ "store", "STAT-GEE-009" },
    .{ "output", "STAT-GEE-010" },     .{ "effectplot", "STAT-GEE-012" },
};
/// Table 50.7 MODEL options other than DIST=/LINK= (p.3435), with aliases.
const model_options = [_][]const u8{ "alpha", "noint", "noscale", "offset", "scale", "pscale", "dscale", "type3", "wald" };
/// Table 50.10 REPEATED options other than SUBJECT=/TYPE=/COVB/CORRW/MAXITER=/CONVERGE= (pp.3439–3442).
const repeated_options = [_][]const u8{ "alphainit", "corrb", "ecorrb", "ecovb", "initial", "intercept", "logor", "mcorrb", "mcovb", "modelse", "subcluster", "subclust", "withinsubject", "within", "zdata", "zrow" };

fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC GEE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "PROC GEE: variable {s} in the {s} statement is not on the input data set", .{ t[i].text, role });
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const ci = try column(cx, ds, t, i, role);
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC GEE: variable {s} in the {s} statement must be numeric", .{ t[i].text, role });
    return ci;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn setGap(s: *Spec, a: A, l: usize, comptime fmt: []const u8, args: anytype) !void {
    if (s.gap != null) return;
    s.gap = try std.fmt.allocPrint(a, fmt, args);
    s.gap_line = l;
}
fn positiveInt(t: []const lex.Token, i: usize) ?usize {
    if (!at(t, i, .number)) return null;
    return std.fmt.parseInt(usize, t[i].text, 10) catch null;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = try std.ascii.allocLowerString(a, t[i].text);
        const canonical: []const u8 = if (eq(option, "descend") or eq(option, "desc")) "descending" else option;
        // SAS documents no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, canonical)).found_existing) return proc.failGap(cx.diags, t[i].line, "PROC GEE: repeated PROC statement option {s} is not verified", .{t[i].text});
        if (eq(canonical, "data") and at(t, i + 1, .eq)) {
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(canonical, "descending")) {
            s.descending = true;
            i += 1;
        } else if (eq(canonical, "namelen") and at(t, i + 1, .eq)) {
            // p.3427: "The default and minimum value is 20."
            const n = positiveInt(t, i + 2);
            if (n == null or n.? < 20) return cx.diags.fail(error.ParseError, t[i].line, "PROC GEE: NAMELEN= must be an integer of at least 20", .{});
            s.namelen = n.?;
            i += 3;
        } else if (eq(canonical, "order") and at(t, i + 1, .eq)) {
            s.order = if (kw(t, i + 2, "data")) .data else if (kw(t, i + 2, "formatted")) .formatted else if (kw(t, i + 2, "freq")) .freq else if (kw(t, i + 2, "internal")) .internal else return cx.diags.fail(error.ParseError, line(t, i), "PROC GEE: ORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
            i += 3;
        } else if (eq(canonical, "plots")) {
            try setGap(&s, a, t[i].line, "PROC GEE: PLOTS is not implemented (STAT-GEE-012)", .{});
            i += 1;
            if (at(t, i, .eq)) {
                i += 1;
                if (at(t, i, .lparen)) i = proc.skipParen(t, i) else i += 1;
            }
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC GEE: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.data_name = name orelse raw.name;
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var class: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var model_seen = false;
    var repeated_seen = false;
    var class_seen = false;
    var freq_seen = false;
    var weight_seen = false;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const l = t[i].line;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.3428: with more than one BY statement only the last is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "class")) {
            // p.3428: the CLASS statement must appear before the MODEL statement.
            if (model_seen) return cx.diags.fail(error.ParseError, l, "PROC GEE: the CLASS statement must appear before the MODEL statement", .{});
            // p.3426: all other statements can appear only once; SAS's handling is not verified.
            if (class_seen) return proc.failGap(cx.diags, l, "PROC GEE: more than one CLASS statement is not verified", .{});
            class_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .lparen) or at(t, j, .slash)) return proc.failGap(cx.diags, t[j].line, "PROC GEE: CLASS options are not implemented (STAT-GEE-003)", .{});
                const ci = try column(cx, ds, t, j, "CLASS");
                if (!has(class.items, ci)) try class.append(a, ci);
            }
        } else if (eq(word, "model")) {
            if (model_seen) return proc.failGap(cx.diags, l, "PROC GEE: more than one MODEL statement is not verified", .{});
            model_seen = true;
            var j = i + 1;
            s.response = try column(cx, ds, t, j, "MODEL");
            j += 1;
            if (at(t, j, .slash)) {
                _ = try numericColumn(cx, ds, t, j + 1, "MODEL");
                try setGap(&s, a, l, "PROC GEE: events/trials responses are not implemented (STAT-GEE-003)", .{});
                j += 2;
            }
            if (at(t, j, .lparen)) return proc.failGap(cx.diags, t[j].line, "PROC GEE: response variable options are not implemented (STAT-GEE-003)", .{});
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) {
                    if (at(t, j, .star) or at(t, j, .pipe) or at(t, j, .lparen) or at(t, j, .rparen) or at(t, j, .at))
                        return proc.failGap(cx.diags, t[j].line, "PROC GEE: crossed, nested and bar effects are not implemented (STAT-GEE-003)", .{});
                    return invalid(cx, t, j);
                }
                const ci = try column(cx, ds, t, j, "MODEL");
                if (ds.columns.items[ci].type != .num and !has(class.items, ci))
                    return cx.diags.fail(error.ParseError, t[j].line, "PROC GEE: character variable {s} in the MODEL statement must be a CLASS variable", .{t[j].text});
                if (has(effects.items, ci)) return proc.failGap(cx.diags, t[j].line, "PROC GEE: a repeated MODEL effect is not verified", .{});
                try effects.append(a, ci);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const opt = t[j].text;
                    if (oneOf(opt, &.{ "dist", "d", "error", "err", "link" })) {
                        if (!at(t, j + 1, .eq) or !at(t, j + 2, .name)) return invalid(cx, t, j + 1);
                        const value = t[j + 2].text;
                        if (eq(opt, "link")) {
                            if (s.link != null) return proc.failGap(cx.diags, t[j].line, "PROC GEE: a repeated MODEL option LINK= is not verified", .{});
                            if (!oneOf(value, &.{ "cloglog", "cll", "cumcll", "ccll", "cumlogit", "clogit", "cumprobit", "cprobit", "glogit", "identity", "id", "log", "logit", "probit", "inverse", "reciprocal", "powerminus2" }))
                                return cx.diags.fail(error.ParseError, t[j + 2].line, "PROC GEE: LINK={s} is not a valid link function", .{value});
                            s.link = value;
                        } else {
                            if (s.dist != null) return proc.failGap(cx.diags, t[j].line, "PROC GEE: a repeated MODEL option DIST= is not verified", .{});
                            if (!oneOf(value, &.{ "binomial", "bin", "b", "gamma", "gam", "g", "igaussian", "ig", "multinomial", "mult", "negbin", "nb", "normal", "nor", "n", "poisson", "poi", "p" }))
                                return cx.diags.fail(error.ParseError, t[j + 2].line, "PROC GEE: DIST={s} is not a valid distribution", .{value});
                            s.dist = value;
                        }
                        j += 3;
                    } else if (oneOf(opt, &model_options)) {
                        try setGap(&s, a, t[j].line, "PROC GEE: MODEL option {s} is not implemented (STAT-GEE-003/007)", .{opt});
                        j += 1;
                        if (at(t, j, .eq)) j += 2;
                    } else return cx.diags.fail(error.ParseError, t[j].line, "PROC GEE: {s} is not a valid MODEL statement option", .{opt});
                }
            }
        } else if (eq(word, "repeated")) {
            if (repeated_seen) return proc.failGap(cx.diags, l, "PROC GEE: more than one REPEATED statement is not verified", .{});
            repeated_seen = true;
            var j = i + 1;
            if (!(kw(t, j, "subject") or kw(t, j, "sub")) or !at(t, j + 1, .eq))
                return cx.diags.fail(error.ParseError, l, "PROC GEE: the REPEATED statement requires SUBJECT=", .{});
            j += 2;
            s.subject = try column(cx, ds, t, j, "REPEATED");
            j += 1;
            if (at(t, j, .star) or at(t, j, .lparen))
                return proc.failGap(cx.diags, t[j].line, "PROC GEE: interaction or nested SUBJECT= effects are not implemented (STAT-GEE-005)", .{});
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const opt = t[j].text;
                    if (eq(opt, "type") or eq(opt, "corr")) {
                        if (!at(t, j + 1, .eq) or !at(t, j + 2, .name)) return invalid(cx, t, j + 1);
                        const value = t[j + 2].text;
                        j += 3;
                        if (eq(value, "exch") or eq(value, "cs")) {
                            s.exchangeable = true;
                        } else if (oneOf(value, &.{ "ar", "ind", "mdep", "unstr", "un", "user", "fixed" })) {
                            try setGap(&s, a, t[j - 1].line, "PROC GEE: TYPE={s} is not implemented (only TYPE=EXCH; STAT-GEE-005)", .{value});
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                        } else return cx.diags.fail(error.ParseError, t[j - 1].line, "PROC GEE: TYPE={s} is not a valid correlation structure", .{value});
                    } else if (eq(opt, "covb")) {
                        s.covb = true;
                        j += 1;
                    } else if (eq(opt, "corrw")) {
                        s.corrw = true;
                        j += 1;
                    } else if ((eq(opt, "maxiter") or eq(opt, "maxit")) and at(t, j + 1, .eq)) {
                        s.maxiter = positiveInt(t, j + 2) orelse return cx.diags.fail(error.ParseError, t[j].line, "PROC GEE: MAXITER= must be a nonnegative integer", .{});
                        j += 3;
                    } else if (eq(opt, "converge") and at(t, j + 1, .eq)) {
                        const v = if (at(t, j + 2, .number)) std.fmt.parseFloat(f64, t[j + 2].text) catch null else null;
                        if (v == null or !(v.? > 0)) return cx.diags.fail(error.ParseError, t[j].line, "PROC GEE: CONVERGE= must be a positive number", .{});
                        s.converge = v.?;
                        j += 3;
                    } else if (oneOf(opt, &repeated_options)) {
                        try setGap(&s, a, t[j].line, "PROC GEE: REPEATED option {s} is not implemented (STAT-GEE-005)", .{opt});
                        j += 1;
                        if (at(t, j, .eq)) {
                            j += 1;
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j) else j += 1;
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                        }
                    } else return cx.diags.fail(error.ParseError, t[j].line, "PROC GEE: {s} is not a valid REPEATED statement option", .{opt});
                }
            } else if (j < end) return invalid(cx, t, j);
        } else if (eq(word, "freq") or eq(word, "frequency")) {
            if (freq_seen) return proc.failGap(cx.diags, l, "PROC GEE: more than one FREQ statement is not verified", .{});
            freq_seen = true;
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
            if (end != i + 2) return invalid(cx, t, i + 2);
        } else if (eq(word, "weight")) {
            if (weight_seen) return proc.failGap(cx.diags, l, "PROC GEE: more than one WEIGHT statement is not verified", .{});
            weight_seen = true;
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
            if (end != i + 2) return invalid(cx, t, i + 2);
        } else {
            var owner: ?[]const u8 = null;
            for (later) |entry| if (eq(word, entry[0])) {
                owner = entry[1];
            };
            if (owner) |o| {
                try setGap(&s, a, l, "PROC GEE: the {s} statement is not implemented ({s})", .{ word, o });
            } else return invalid(cx, t, i);
        }
        i = end;
    }
    // p.3426: "The PROC GEE, MODEL, and REPEATED statements are required."
    if (!model_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC GEE: a MODEL statement is required", .{});
    if (!repeated_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC GEE: a REPEATED statement is required", .{});
    // p.3440: variables in the subject effect must be listed in the CLASS statement.
    if (!has(class.items, s.subject)) return cx.diags.fail(error.ParseError, line(t, 0), "PROC GEE: the SUBJECT= variable {s} must be listed in the CLASS statement", .{ds.columns.items[s.subject].name});
    const resolved = try bys.resolve(a, ds, cx.diags);
    const by_cols = try a.alloc(usize, resolved.names.len);
    for (resolved.names, by_cols) |n, *ci| ci.* = ds.indexOf(n).?;
    s.by_cols = by_cols;
    s.by_desc = resolved.desc;
    s.notsorted = resolved.notsorted;
    s.class = class.items;
    s.effects = effects.items;
    return s;
}

/// Selected observations of one BY group. Rows index the supplied slice.
pub const Selection = struct {
    read: usize,
    used: usize,
    rows: []const usize,
    levels: []const classes.Levels,
    response: classes.Levels,
};

/// Missing response, effect, CLASS or SUBJECT values drop the observation
/// (pp.3440–3442: without WITHIN= missing values are not used).
pub fn prepare(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Selection {
    const a = cx.arena;
    var kept: std.ArrayList(usize) = .empty;
    const mask = try a.alloc(bool, rows.len);
    for (rows, 0..) |row, k| {
        var miss = selection.missing(row[s.response]) or selection.missing(row[s.subject]);
        for (s.effects) |ci| miss = miss or selection.missing(row[ci]);
        for (s.class) |ci| miss = miss or selection.missing(row[ci]);
        mask[k] = !miss;
        if (!miss) try kept.append(a, k);
    }
    const levels = try a.alloc(classes.Levels, s.class.len);
    for (s.class, 0..) |ci, k| levels[k] = try classes.build(a, s.input.ds, rows, ci, .{ .order = s.order, .include_rows = mask });
    const response = try classes.build(a, s.input.ds, rows, s.response, .{ .order = .formatted, .include_rows = mask });
    return .{ .read = rows.len, .used = kept.items.len, .rows = kept.items, .levels = levels, .response = response };
}

const Column = struct { effect: usize, level: ?usize = null };

fn classIndex(s: Spec, ci: usize) ?usize {
    return std.mem.indexOfScalar(usize, s.class, ci);
}

pub const Fit = struct {
    q: usize,
    beta: []f64,
    model_cov: []f64,
    emp_cov: []f64,
    alpha: f64,
    qic: f64,
    qicu: f64,
};

/// Inverse of a q*q symmetric positive definite matrix.
fn inverse(a: A, m: []const f64, q: usize) error{ OutOfMemory, Singular }![]f64 {
    const l = try a.dupe(f64, m);
    if (!linalg.cholesky(l, q)) return error.Singular;
    const inv = try a.alloc(f64, q * q);
    const e = try a.alloc(f64, q);
    for (0..q) |j| {
        @memset(e, 0);
        e[j] = 1;
        linalg.choleskySolve(l, q, e);
        for (0..q) |k| inv[k * q + j] = e[k];
    }
    return inv;
}

fn expit(eta: f64) f64 {
    return kernel.probability(eta);
}

/// Residual moments at `beta`: returns alpha (exchangeable).
fn moments(x: []const f64, y: []const f64, q: usize, beta: []const f64, clusters: []const []const usize, mu: []f64, e: []f64) error{Degenerate}!f64 {
    const n = y.len;
    var ss: f64 = 0;
    for (0..n) |i| {
        var eta: f64 = 0;
        for (0..q) |j| eta += x[i * q + j] * beta[j];
        mu[i] = expit(eta);
        e[i] = (y[i] - mu[i]) / @sqrt(mu[i] * (1 - mu[i]));
        ss += e[i] * e[i];
    }
    const qf: f64 = @floatFromInt(q);
    const phi = ss / (@as(f64, @floatFromInt(n)) - qf);
    var cross: f64 = 0;
    var pairs: f64 = 0;
    for (clusters) |c| {
        for (c, 0..) |r1, j| for (c[j + 1 ..]) |r2| {
            cross += e[r1] * e[r2];
        };
        const m: f64 = @floatFromInt(c.len);
        pairs += m * (m - 1) / 2;
    }
    if (!(pairs - qf > 0) or !(phi > 0)) return error.Degenerate;
    return cross / ((pairs - qf) * phi);
}

pub const FitError = error{ OutOfMemory, Singular, NotConverged, Degenerate };

/// Accumulates I0 = sum D'V^-1 D and (optionally) the score and the sandwich
/// meat for exchangeable working correlation `alpha` (scale cancels; phi=1).
fn accumulate(a: A, x: []const f64, y: []const f64, q: usize, mu: []const f64, clusters: []const []const usize, alpha: f64, info: []f64, score: []f64, meat: []f64) FitError!void {
    @memset(info, 0);
    @memset(score, 0);
    @memset(meat, 0);
    for (clusters) |c| {
        const m = c.len;
        const v = try a.alloc(f64, m * m);
        for (c, 0..) |r1, j| for (c, 0..) |r2, k| {
            const corr: f64 = if (j == k) 1 else alpha;
            v[j * m + k] = corr * @sqrt(mu[r1] * (1 - mu[r1]) * mu[r2] * (1 - mu[r2]));
        };
        if (!linalg.cholesky(v, m)) return error.Singular;
        // W = V^-1 D, column by column (D = A X for the logit link).
        const w = try a.alloc(f64, m * q);
        const col = try a.alloc(f64, m);
        for (0..q) |p| {
            for (c, 0..) |r, j| col[j] = mu[r] * (1 - mu[r]) * x[r * q + p];
            linalg.choleskySolve(v, m, col);
            for (0..m) |j| w[j * q + p] = col[j];
        }
        const u = try a.alloc(f64, q);
        @memset(u, 0);
        for (c, 0..) |r, j| for (0..q) |p| {
            u[p] += w[j * q + p] * (y[r] - mu[r]);
        };
        for (0..q) |p| {
            score[p] += u[p];
            for (0..q) |pp| {
                var s: f64 = 0;
                for (c, 0..) |r, j| s += w[j * q + p] * mu[r] * (1 - mu[r]) * x[r * q + pp];
                info[p * q + pp] += s;
                meat[p * q + pp] += u[p] * u[pp];
            }
        }
    }
}

fn converged(old: []const f64, new: []const f64, tol: f64) bool {
    for (old, new) |b0, b1| {
        const d = @abs(b1 - b0);
        // p.3440: relative difference when |estimate| > 0.08.
        const crit = if (@abs(b0) > 0.08) d / @abs(b0) else d;
        if (!(crit < tol)) return false;
    }
    return true;
}

/// Standard GEE for a binary response with the logit link and exchangeable
/// working correlation. `x` is the full-rank rows*q design.
pub fn fitExchangeable(a: A, x: []const f64, y: []const f64, q: usize, clusters: []const []const usize, maxiter: usize, tol: f64) FitError!Fit {
    const n = y.len;
    const ones = try a.alloc(f64, n);
    @memset(ones, 1);
    const start = kernel.fitLogit(a, x, y, ones, q) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Singular => return error.Singular,
        else => return error.NotConverged,
    };
    const beta = try a.dupe(f64, start.beta);
    const mu = try a.alloc(f64, n);
    const e = try a.alloc(f64, n);
    const info = try a.alloc(f64, q * q);
    const score = try a.alloc(f64, q);
    const meat = try a.alloc(f64, q * q);
    var alpha: f64 = 0;
    var done = false;
    var iter: usize = 0;
    var hits: usize = 0;
    while (iter < maxiter) : (iter += 1) {
        alpha = try moments(x, y, q, beta, clusters, mu, e);
        try accumulate(a, x, y, q, mu, clusters, alpha, info, score, meat);
        const l = try a.dupe(f64, info);
        if (!linalg.cholesky(l, q)) return error.Singular;
        const step = try a.dupe(f64, score);
        linalg.choleskySolve(l, q, step);
        const old = try a.dupe(f64, beta);
        for (beta, step) |*b, d| b.* += d;
        // p.3440 "less than number on two successive iterations": the
        // criterion must hold for two consecutive updates.
        if (converged(old, beta, tol)) {
            if (hits > 0) {
                done = true;
                break;
            }
            hits += 1;
        } else hits = 0;
    }
    if (!done) return error.NotConverged;
    // Covariances and the reported correlation at the final estimates.
    alpha = try moments(x, y, q, beta, clusters, mu, e);
    try accumulate(a, x, y, q, mu, clusters, alpha, info, score, meat);
    const model_cov = try inverse(a, info, q);
    const emp_cov = try a.alloc(f64, q * q);
    for (0..q) |r| for (0..q) |c| {
        var s: f64 = 0;
        for (0..q) |k| for (0..q) |l| {
            s += model_cov[r * q + k] * meat[k * q + l] * model_cov[l * q + c];
        };
        emp_cov[r * q + c] = s;
    };
    // QIC (Pan 2001): binomial quasi-likelihood at the GEE estimates and the
    // independence model-based information Omega_I = X' diag(mu(1-mu)) X.
    var quasi: f64 = 0;
    const omega = try a.alloc(f64, q * q);
    @memset(omega, 0);
    for (0..n) |i| {
        quasi += y[i] * @log(mu[i]) + (1 - y[i]) * @log(1 - mu[i]);
        const v = mu[i] * (1 - mu[i]);
        for (0..q) |r| for (0..q) |c| {
            omega[r * q + c] += v * x[i * q + r] * x[i * q + c];
        };
    }
    var trace: f64 = 0;
    for (0..q) |r| for (0..q) |c| {
        trace += omega[r * q + c] * emp_cov[c * q + r];
    };
    const qf: f64 = @floatFromInt(q);
    return .{ .q = q, .beta = beta, .model_cov = model_cov, .emp_cov = emp_cov, .alpha = alpha, .qic = -2 * quasi + 2 * trace, .qicu = -2 * quasi + 2 * qf };
}

// ---------------------------------------------------------------- listing

fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn number(a: A, out: *Out, x: f64, decimals: usize, width: usize) !void {
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
    var zero = text.len > 0 and text[0] == '-';
    for (text) |c| {
        if (c != '-' and c != '0' and c != '.') zero = false;
    }
    try padLeft(a, out, if (zero) text[1..] else text, width);
}
fn centered(a: A, out: *Out, title: []const u8, width: usize) !void {
    if (title.len < width) try out.appendNTimes(a, ' ', (width - title.len) / 2);
    try out.appendSlice(a, title);
    try out.append(a, '\n');
}
/// Covariance cells (Figure 50.4 reference): four significant digits below
/// 0.01, five decimals from 0.01 to 10.
/// ponytail: magnitudes outside [0.001, 10) use six significant digits; no
/// reference listing with such a covariance was replayed.
pub fn covText(a: A, x: f64) ![]const u8 {
    const ax = @abs(x);
    if (ax == 0) return "0";
    var decimals: usize = 5;
    if (ax < 0.01) {
        const exp: i32 = @intFromFloat(@floor(@log10(ax)));
        decimals = @intCast(-exp + 3);
    } else if (ax >= 10) {
        const exp: i32 = @intFromFloat(@floor(@log10(ax)));
        decimals = @intCast(@max(0, 5 - exp));
    }
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}

const Model = struct {
    columns: []const Column,
    alias: []const bool,
    fit: Fit,
    clusters: usize,
    max_size: usize,
    min_size: usize,
    event: usize,
    events: usize,
};

fn label(s: Spec, sel: Selection, c: Column) []const u8 {
    const lv = c.level orelse return "";
    return std.mem.trim(u8, sel.levels[classIndex(s, s.effects[c.effect]).?].levels[lv].label, " ");
}

fn render(a: A, out: *Out, s: Spec, sel: Selection, m: Model) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe GEE Procedure\n\n");
    const upper = try std.ascii.allocUpperString(a, s.data_name);
    const data_name = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    const response_name = ds.columns.items[s.response].name;
    const info = [_][2][]const u8{
        .{ "Data Set", data_name },
        .{ "Distribution", "Binomial" },
        .{ "Link Function", "Logit" },
        .{ "Dependent Variable", response_name },
    };
    var value_width: usize = 0;
    for (info) |row| value_width = @max(value_width, row[1].len);
    try centered(a, out, "Model Information", 22 + value_width);
    try out.append(a, '\n');
    for (info) |row| {
        try padRight(a, out, row[0], 18);
        try padLeft(a, out, row[1], value_width + 4);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\nNumber of Events           {d:>12}\nNumber of Trials           {d:>12}\n\n\n", .{ sel.read, sel.used, m.events, sel.used });

    // Class Level Information: values wrap at 50 columns (reference listing).
    var name_width: usize = 5;
    for (s.class) |ci| name_width = @max(name_width, ds.columns.items[ci].name.len);
    try centered(a, out, "Class Level Information", name_width + 16 + 50);
    try out.appendSlice(a, " \n");
    try padRight(a, out, "Class", name_width);
    try out.appendSlice(a, "      Levels    Values\n\n");
    for (s.class, sel.levels) |ci, levels| {
        try padRight(a, out, ds.columns.items[ci].name, name_width);
        try out.print(a, "{d:>12}    ", .{levels.levels.len});
        var width: usize = 0;
        for (levels.levels) |level| {
            const text = std.mem.trim(u8, level.label, " ");
            if (width > 0 and width + 1 + text.len > 50) {
                try out.appendNTimes(a, ' ', 50 - width);
                try out.append(a, '\n');
                try out.appendNTimes(a, ' ', name_width + 16);
                width = 0;
            }
            if (width > 0) {
                try out.append(a, ' ');
                width += 1;
            }
            try out.appendSlice(a, text);
            width += text.len;
        }
        try out.appendNTimes(a, ' ', 50 -| width);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");

    // Response Profile: ordered values, the event first (DESCENDING reverses).
    var rw: usize = response_name.len;
    for (sel.response.levels) |lv| rw = @max(rw, std.mem.trim(u8, lv.label, " ").len);
    try centered(a, out, "Response Profile", 12 + rw + 13);
    try out.appendSlice(a, " \n Ordered");
    try out.appendNTimes(a, ' ', rw + 12);
    try out.appendSlice(a, "Total\n   Value    ");
    try padLeft(a, out, response_name, rw);
    try out.appendSlice(a, "    Frequency\n\n");
    const levels = sel.response.levels;
    for (0..levels.len) |k| {
        const lv = if (s.descending) levels.len - 1 - k else k;
        try out.print(a, "{d:>8}    ", .{k + 1});
        try padLeft(a, out, std.mem.trim(u8, levels[lv].label, " "), rw);
        try out.print(a, "{d:>13.0}\n", .{levels[lv].frequency});
    }
    const event_label = std.mem.trim(u8, levels[m.event].label, " ");
    try out.print(a, "\nPROC GEE is modeling the probability that {s}='{s}'.\n\n\n", .{ response_name, event_label });

    // Parameter Information: one column per CLASS variable among the effects.
    var class_cols: std.ArrayList(usize) = .empty;
    for (s.effects) |ci| if (classIndex(s, ci) != null) try class_cols.append(a, ci);
    var effect_width: usize = 9;
    for (s.effects) |ci| effect_width = @max(effect_width, ds.columns.items[ci].name.len);
    var level_widths = try a.alloc(usize, class_cols.items.len);
    for (class_cols.items, 0..) |ci, k| {
        level_widths[k] = ds.columns.items[ci].name.len;
        for (sel.levels[classIndex(s, ci).?].levels) |lv| level_widths[k] = @max(level_widths[k], std.mem.trim(u8, lv.label, " ").len);
    }
    var total: usize = 16 + effect_width;
    for (level_widths) |w| total += 4 + w;
    try centered(a, out, "Parameter Information", total);
    try out.appendSlice(a, " \nParameter       ");
    try padRight(a, out, "Effect", effect_width);
    for (class_cols.items, level_widths) |ci, w| {
        try out.appendSlice(a, "    ");
        try padRight(a, out, ds.columns.items[ci].name, w);
    }
    try out.appendSlice(a, "\n\n");
    for (0..m.columns.len + 1) |j| {
        try padRight(a, out, try std.fmt.allocPrint(a, "Prm{d}", .{j + 1}), 16);
        const c: ?Column = if (j == 0) null else m.columns[j - 1];
        try padRight(a, out, if (c) |cc| ds.columns.items[s.effects[cc.effect]].name else "Intercept", effect_width);
        for (class_cols.items, level_widths) |ci, w| {
            try out.appendSlice(a, "    ");
            const text = if (c != null and s.effects[c.?.effect] == ci) label(s, sel, c.?) else "";
            try padRight(a, out, text, w);
        }
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");

    try centered(a, out, "GEE Model Information", 45);
    try out.append(a, '\n');
    const subject = try std.fmt.allocPrint(a, "{s} ({d} levels)", .{ ds.columns.items[s.subject].name, m.clusters });
    const gee_rows = [_][2][]const u8{
        .{ "Correlation Structure", "Exchangeable" },
        .{ "Subject Effect", subject },
        .{ "Number of Clusters", try std.fmt.allocPrint(a, "{d}", .{m.clusters}) },
        .{ "Correlation Matrix Dimension", try std.fmt.allocPrint(a, "{d}", .{m.max_size}) },
        .{ "Maximum Cluster Size", try std.fmt.allocPrint(a, "{d}", .{m.max_size}) },
        .{ "Minimum Cluster Size", try std.fmt.allocPrint(a, "{d}", .{m.min_size}) },
    };
    var gw: usize = 0;
    for (gee_rows) |row| gw = @max(gw, row[1].len);
    for (gee_rows) |row| {
        try padRight(a, out, row[0], 28);
        try padLeft(a, out, row[1], gw + 4);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");

    const f = m.fit;
    var kept: std.ArrayList(usize) = .empty; // full parameter numbers of the reduced columns
    for (m.alias, 0..) |flag, j| if (!flag) try kept.append(a, j);
    if (s.covb) {
        for ([_][]const u8{ "Covariance Matrix (Model-Based)", "Covariance Matrix (Empirical)" }, [_][]const f64{ f.model_cov, f.emp_cov }) |title, cov| {
            try centered(a, out, title, 4 + 15 * f.q);
            try out.appendSlice(a, " \n    ");
            for (kept.items) |j| try padLeft(a, out, try std.fmt.allocPrint(a, "Prm{d}", .{j + 1}), 15);
            try out.appendSlice(a, "\n\n");
            for (kept.items, 0..) |j, r| {
                try padRight(a, out, try std.fmt.allocPrint(a, "Prm{d}", .{j + 1}), 4);
                for (0..f.q) |c| try padLeft(a, out, try covText(a, cov[r * f.q + c]), 15);
                try out.append(a, '\n');
            }
            try out.appendSlice(a, "\n\n");
        }
    }
    if (s.corrw) {
        try centered(a, out, "Working Correlation Matrix", 5 + 13 * m.max_size);
        try out.appendSlice(a, " \n     ");
        for (0..m.max_size) |k| try padLeft(a, out, try std.fmt.allocPrint(a, "Obs {d}", .{k + 1}), 13);
        try out.appendSlice(a, "\n\n");
        for (0..m.max_size) |r| {
            try padRight(a, out, try std.fmt.allocPrint(a, "Obs {d}", .{r + 1}), 5);
            for (0..m.max_size) |c| try number(a, out, if (r == c) 1 else f.alpha, 4, 13);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    try out.appendSlice(a, " Exchangeable Working\n     Correlation\n\nCorrelation");
    try number(a, out, f.alpha, 4, 11);
    try out.appendSlice(a, "\n\n\n  GEE Fit Criteria\n\nQIC ");
    try number(a, out, f.qic, 4, 17);
    try out.appendSlice(a, "\nQICu");
    try number(a, out, f.qicu, 4, 17);
    try out.appendSlice(a, "\n\n\n");

    // Parameter estimates with empirical standard errors (Figure 50.7).
    var level_width: usize = 0;
    for (m.columns) |c| level_width = @max(level_width, label(s, sel, c).len);
    const lead = effect_width + 4 + level_width;
    try centered(a, out, "Parameter Estimates for Response Model", lead + 71);
    try centered(a, out, "with Empirical Standard Error Estimates", lead + 71);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', lead);
    try out.appendSlice(a, "                Standard       95% Confidence\n");
    try padRight(a, out, "Parameter", lead);
    try out.appendSlice(a, "    Estimate       Error           Limits                 Z    Pr > |Z|\n\n");
    for (0..m.columns.len + 1) |j| {
        const c: ?Column = if (j == 0) null else m.columns[j - 1];
        try padRight(a, out, if (c) |cc| ds.columns.items[s.effects[cc.effect]].name else "Intercept", effect_width + 4);
        try padRight(a, out, if (c) |cc| label(s, sel, cc) else "", level_width);
        if (m.alias[j]) {
            try out.appendSlice(a, "      0.0000      0.0000      0.0000      0.0000        .         .    \n");
            continue;
        }
        const r = std.mem.indexOfScalar(usize, kept.items, j).?;
        const b = f.beta[r];
        const se = @sqrt(f.emp_cov[r * f.q + r]);
        const z = b / se;
        const pv = chiTail(z * z, 1);
        try number(a, out, b, 4, 12);
        try number(a, out, se, 4, 12);
        try number(a, out, b - z95 * se, 4, 12);
        try number(a, out, b + z95 * se, 4, 12);
        try number(a, out, z, 2, 11);
        if (pv < 0.0001) try padLeft(a, out, "<.0001", 12) else try number(a, out, pv, 4, 12);
        try out.append(a, '\n');
    }
}

/// PROBIT(0.975) (ALPHA= is a gap, STAT-GEE-003).
const z95: f64 = 1.959963984540054;

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    if (s.gap) |message| return proc.failGap(cx.diags, s.gap_line, "{s}", .{message});
    // Table 50.8: without DIST= the model is Normal/identity.
    const d = s.dist orelse return proc.failGap(cx.diags, l0, "PROC GEE: the default Normal distribution is not implemented (only DIST=BINOMIAL; STAT-GEE-003)", .{});
    if (!oneOf(d, &.{ "binomial", "bin", "b" })) return proc.failGap(cx.diags, l0, "PROC GEE: DIST={s} is not implemented (only DIST=BINOMIAL; STAT-GEE-003)", .{d});
    if (s.link) |v| if (!eq(v, "logit")) return proc.failGap(cx.diags, l0, "PROC GEE: LINK={s} is not implemented (only LINK=LOGIT; STAT-GEE-003)", .{v});
    if (!s.exchangeable) return proc.failGap(cx.diags, l0, "PROC GEE: the default independent working correlation (TYPE=IND) is not implemented (only TYPE=EXCH; STAT-GEE-005)", .{});
    // pp.3431–3432, 3444: documented, but no SAS reference listing was replayed.
    if (s.frequency != null) return proc.failGap(cx.diags, l0, "PROC GEE: the FREQ statement is not verified against SAS output (STAT-GEE-001 remaining gap)", .{});
    if (s.weight != null) return proc.failGap(cx.diags, l0, "PROC GEE: the WEIGHT statement is not verified against SAS output (STAT-GEE-001 remaining gap)", .{});

    // ponytail: ORDER= other than FORMATTED may also reorder the response
    // levels, and NAMELEN= shortening was not replayed; both stay loud.
    if (s.order != .formatted) return proc.failGap(cx.diags, l0, "PROC GEE: ORDER= other than FORMATTED is not verified against SAS output (STAT-GEE-001 remaining gap)", .{});
    for (s.effects) |ci| if (ds.columns.items[ci].name.len > s.namelen) return proc.failGap(cx.diags, l0, "PROC GEE: effect names longer than NAMELEN={d} are not verified against SAS output (STAT-GEE-001 remaining gap)", .{s.namelen});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return proc.failGap(cx.diags, l0, "PROC GEE: an empty input data set is not verified", .{});
    var body: Out = .empty;
    var notes: std.ArrayList([]const u8) = .empty;
    for (groups) |group| {
        const rows = group.rows;
        const sel = try prepare(cx, s, rows);
        if (sel.used != sel.read) return proc.failGap(cx.diags, l0, "PROC GEE: observations with missing values (dropped from clusters) are not verified against SAS output", .{});
        const levels = sel.response.levels;
        if (levels.len != 2) return proc.failGap(cx.diags, l0, "PROC GEE: a binomial response with {d} levels is not verified (STAT-GEE-003)", .{levels.len});
        const event: usize = if (s.descending) 1 else 0;
        const y = try a.alloc(f64, sel.used);
        var events: usize = 0;
        for (sel.rows, 0..) |ri, i| {
            y[i] = if (sel.response.row_to_level[ri].? == event) 1 else 0;
            if (y[i] == 1) events += 1;
        }
        // GLM parameterization design (intercept, one column per CLASS level).
        var columns: std.ArrayList(Column) = .empty;
        for (s.effects, 0..) |ci, e| {
            if (classIndex(s, ci)) |k| {
                for (0..sel.levels[k].levels.len) |lv| try columns.append(a, .{ .effect = e, .level = lv });
            } else try columns.append(a, .{ .effect = e });
        }
        const p = columns.items.len + 1;
        const full = try a.alloc(f64, sel.used * p);
        for (sel.rows, 0..) |ri, i| {
            full[i * p] = 1;
            for (columns.items, 1..) |c, j| {
                const ci = s.effects[c.effect];
                full[i * p + j] = if (c.level) |lv| (if (sel.levels[classIndex(s, ci).?].row_to_level[ri] == lv) 1 else 0) else rows[ri][ci].num;
            }
        }
        const alias = try kernel.aliased(a, full, sel.used, p, kernel.singular_default);
        for (alias, 0..) |flag, j| {
            var expected = false;
            if (j > 0) if (columns.items[j - 1].level) |lv| {
                expected = lv + 1 == sel.levels[classIndex(s, s.effects[columns.items[j - 1].effect]).?].levels.len;
            };
            if (flag != expected) return proc.failGap(cx.diags, l0, "PROC GEE: linearly dependent model columns beyond the CLASS reference levels are not implemented (STAT-GEE-003)", .{});
        }
        var q: usize = 0;
        for (alias) |flag| q += @intFromBool(!flag);
        const x = try a.alloc(f64, sel.used * q);
        for (0..sel.used) |i| {
            var k: usize = 0;
            for (alias, 0..) |flag, j| if (!flag) {
                x[i * q + k] = full[i * p + j];
                k += 1;
            };
        }
        // Clusters: subject levels, observations in data order (p.3441).
        const subject_levels = sel.levels[classIndex(s, s.subject).?];
        const members = try a.alloc(std.ArrayList(usize), subject_levels.levels.len);
        for (members) |*mb| mb.* = .empty;
        for (sel.rows, 0..) |ri, i| try members[subject_levels.row_to_level[ri].?].append(a, i);
        const clusters = try a.alloc([]const usize, members.len);
        var max_size: usize = 0;
        var min_size: usize = std.math.maxInt(usize);
        for (members, clusters) |mb, *c| {
            c.* = mb.items;
            max_size = @max(max_size, mb.items.len);
            min_size = @min(min_size, mb.items.len);
        }
        const f = fitExchangeable(a, x, y, q, clusters, s.maxiter, s.converge) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return proc.failGap(cx.diags, l0, "PROC GEE: a singular GEE information or working covariance matrix is not implemented", .{}),
            error.NotConverged => return proc.failGap(cx.diags, l0, "PROC GEE: the GEE iteration did not converge; nonconvergence reporting is not implemented", .{}),
            error.Degenerate => return proc.failGap(cx.diags, l0, "PROC GEE: too few within-cluster pairs to estimate the exchangeable correlation are not verified", .{}),
        };
        if (s.by_cols.len > 0) {
            // ponytail: the whole GEE listing is laid out as under NOCENTER
            // (every replayed reference uses it), so the BY line is too.
            var by_line: Out = .empty;
            try by.appendLine(a, &by_line, ds, rows[0], s.by_cols);
            var it = std.mem.splitScalar(u8, by_line.items, '\n');
            var first = true;
            while (it.next()) |text| {
                if (!first) try body.append(a, '\n');
                first = false;
                try body.appendSlice(a, std.mem.trimStart(u8, text, " "));
            }
        }
        try render(a, &body, s, sel, .{ .columns = columns.items, .alias = alias, .fit = f, .clusters = clusters.len, .max_size = max_size, .min_size = min_size, .event = event, .events = events });
        try notes.append(a, try std.fmt.allocPrint(a, "{s}='{s}'", .{ ds.columns.items[s.response].name, std.mem.trim(u8, levels[event].label, " ") }));
    }
    for (notes.items, groups) |n, group| {
        try cx.diags.note(0, "PROC GEE is modeling the probability that {s}.", .{n});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("gee_tests.zig");
}
