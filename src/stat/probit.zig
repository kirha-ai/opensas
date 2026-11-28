//! PROC PROBIT (SAS/STAT 15.4 ch.100): statement parsing, variable roles,
//! observation selection, BY groups and the default listing of the
//! events/trials normal model with an estimated natural response rate
//! (STAT-PROBIT-001). Everything the cited pages define but this file does not
//! compute is a loud D-009 gap; nothing is printed for a step that hits one.
//!
//! Model (p.8108, Abbott's formula): p = C + (1 - C) * Phi(x'b). With LOG/LOG10
//! and OPTC, observations whose dose is <= 0 form the control group (p.8090):
//! they enter the likelihood with p = C and seed the initial C (p.8089).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fns = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const LogKind = enum { none, ln, log10 };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    // PROC statement (pp.8100-8105). Defaults: C=0 not estimated, HPROB=0.10,
    // ORDER=FORMATTED, NAMELEN=20.
    c: ?f64 = null,
    optc: bool = false,
    log: LogKind = .none,
    hprob: f64 = 0.10,
    order: classes.Order = .formatted,
    namelen: usize = 20,
    noprint: bool = false,
    covout: bool = false,
    inversecl: bool = false,
    lackfit: bool = false,
    plots: bool = false,
    inest: ?[]const u8 = null,
    outest: ?[]const u8 = null,
    xdata: ?[]const u8 = null,
    // Roles.
    response: usize = 0,
    trials: ?usize = null,
    effects: []const usize = &.{},
    class: []const usize = &.{},
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    model_options: []const []const u8 = &.{},
    later: []const []const u8 = &.{},
};

/// Why an observation is not an ordinary model observation.
pub const Selection = struct {
    read: usize,
    /// Ordinary (non-control) observations used in the fit, in row order.
    rows: []const usize,
    /// Control-group observations (LOG/LOG10 + OPTC, dose <= 0).
    control: []const usize,
    weight: []const f64, // parallel to rows
    control_weight: []const f64, // parallel to control
    missing: usize, // a missing response, trials, effect or CLASS value
    bad_weight: usize, // zero, negative or missing WEIGHT
    nonpositive_dose: usize, // dose <= 0 under LOG/LOG10 without OPTC: ignored
};

/// Statements of the chapter that later PROBIT tickets own.
const later_statements = [_][]const u8{ "output", "cdfplot", "inset", "ippplot", "lpredplot", "predpplot", "contrast", "effectplot", "estimate", "lsmeans", "lsmestimate", "slice", "store", "test", "effect" };

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC PROBIT: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "PROC PROBIT: variable {s} in the {s} statement is not on the input data set", .{ t[i].text, role });
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const ci = try column(cx, ds, t, i, role);
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC PROBIT: variable {s} in the {s} statement must be numeric", .{ t[i].text, role });
    return ci;
}
/// `name` or `libref.name` after `OPTION=`; returns the index after it.
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) j = proc.skipParen(t, j);
    into.* = name;
    return j;
}
/// A probability option value: a number strictly between 0 and 1 (C= also
/// admits 0, the documented default rate).
fn rate(cx: proc.ProcCtx, t: []const lex.Token, i: usize, option: []const u8, allow_zero: bool) diag.Error!f64 {
    const v = if (at(t, i, .number)) std.fmt.parseFloat(f64, t[i].text) catch null else null;
    if (v == null or !(v.? < 1) or v.? < 0 or (!allow_zero and v.? == 0))
        return cx.diags.fail(error.ParseError, line(t, i), "PROC PROBIT: {s}= must be a number between 0 and 1", .{option});
    return v.?;
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
        const lower = try std.ascii.allocLowerString(a, t[i].text);
        const option: []const u8 = if (eq(lower, "ln")) "log" else if (eq(lower, "plot")) "plots" else lower;
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return proc.failGap(cx.diags, t[i].line, "PROC PROBIT: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "c") and valued) {
            s.c = try rate(cx, t, i + 2, "C", true);
            i += 3;
        } else if (eq(option, "hprob") and valued) {
            s.hprob = try rate(cx, t, i + 2, "HPROB", false);
            i += 3;
        } else if (eq(option, "namelen") and valued) {
            const n = if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null;
            if (n == null or n.? < 20 or n.? > 200) return cx.diags.fail(error.ParseError, t[i].line, "PROC PROBIT: NAMELEN= must be an integer between 20 and 200", .{});
            s.namelen = n.?;
            i += 3;
        } else if (eq(option, "order") and valued) {
            s.order = if (kw(t, i + 2, "data")) .data else if (kw(t, i + 2, "formatted")) .formatted else if (kw(t, i + 2, "freq")) .freq else if (kw(t, i + 2, "internal")) .internal else return cx.diags.fail(error.ParseError, t[i].line, "PROC PROBIT: ORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
            i += 3;
        } else if (eq(option, "inest") and valued) {
            i = try memberName(cx, t, i + 2, &s.inest);
        } else if (eq(option, "outest") and valued) {
            i = try memberName(cx, t, i + 2, &s.outest);
        } else if (eq(option, "xdata") and valued) {
            i = try memberName(cx, t, i + 2, &s.xdata);
        } else if (eq(option, "plots")) {
            // PLOTS=NONE suppresses all plots (p.8105): nothing to draw.
            i += 1;
            var none = false;
            if (at(t, i, .eq)) {
                i += 1;
                if (at(t, i, .lparen)) {
                    none = kw(t, i + 1, "none") and at(t, i + 2, .rparen);
                    i = proc.skipParen(t, i);
                } else if (at(t, i, .name)) {
                    none = eq(t[i].text, "none");
                    i += 1;
                    if (at(t, i, .lparen)) i = proc.skipParen(t, i);
                } else return invalid(cx, t, i);
            }
            s.plots = !none;
        } else if (eq(option, "inversecl")) {
            s.inversecl = true;
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "optc")) {
            s.optc = true;
            i += 1;
        } else if (eq(option, "log") or eq(option, "log10")) {
            // LN/LOG and LOG10 are alternatives; the chapter gives no precedence.
            if (s.log != .none) return proc.failGap(cx.diags, t[i].line, "PROC PROBIT: LOG/LN together with LOG10 is not verified", .{});
            s.log = if (eq(option, "log")) .ln else .log10;
            i += 1;
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "covout")) {
            s.covout = true;
            i += 1;
        } else if (eq(option, "lackfit")) {
            s.lackfit = true;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC PROBIT: input data set not found", .{});
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
    var model_options: std.ArrayList([]const u8) = .empty;
    var later: std.ArrayList([]const u8) = .empty;
    var model_seen = false;
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
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.8105: "If you specify more than one BY statement, only the last one specified is used."
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "class")) {
            // p.8106: "The CLASS statement must precede the MODEL statement."
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC PROBIT: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .lparen) or at(t, j, .slash)) return proc.failGap(cx.diags, t[j].line, "PROC PROBIT: CLASS options are not implemented (STAT-PROBIT-003)", .{});
                const ci = try column(cx, ds, t, j, "CLASS");
                if (!has(class.items, ci)) try class.append(a, ci);
            }
        } else if (eq(word, "model")) {
            if (model_seen) return proc.failGap(cx.diags, t[i].line, "PROC PROBIT: more than one MODEL statement is not verified", .{});
            model_seen = true;
            var j = i + 1;
            s.response = try column(cx, ds, t, j, "MODEL");
            j += 1;
            if (at(t, j, .lparen)) return proc.failGap(cx.diags, t[j].line, "PROC PROBIT: response variable options are not implemented (STAT-PROBIT-002)", .{});
            if (at(t, j, .slash)) {
                s.trials = try numericColumn(cx, ds, t, j + 1, "MODEL");
                if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, t[j].line, "PROC PROBIT: the events variable in events/trials syntax must be numeric", .{});
                j += 2;
            }
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) {
                    if (at(t, j, .star) or at(t, j, .pipe) or at(t, j, .lparen) or at(t, j, .rparen) or at(t, j, .at) or at(t, j, .number))
                        return proc.failGap(cx.diags, t[j].line, "PROC PROBIT: crossed, nested and bar effects are not implemented (STAT-PROBIT-003)", .{});
                    return invalid(cx, t, j);
                }
                const ci = try column(cx, ds, t, j, "MODEL");
                if (ds.columns.items[ci].type != .num and !has(class.items, ci))
                    return cx.diags.fail(error.ParseError, t[j].line, "PROC PROBIT: character variable {s} in the MODEL statement must be a CLASS variable", .{t[j].text});
                try effects.append(a, ci);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    try model_options.append(a, t[j].text);
                    j += 1;
                    if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                    if (at(t, j, .eq)) {
                        j += 1;
                        if (j >= end) return invalid(cx, t, j);
                        if (at(t, j, .lparen)) j = proc.skipParen(t, j) else {
                            j += 1;
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                        }
                    }
                }
            }
        } else if (eq(word, "weight")) {
            if (s.weight != null) return proc.failGap(cx.diags, t[i].line, "PROC PROBIT: more than one WEIGHT statement is not verified", .{});
            if (end != i + 2) return invalid(cx, t, @min(i + 2, end));
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (oneOf(word, &later_statements)) {
            try later.append(a, try std.ascii.allocLowerString(a, word));
        } else if (eq(word, "format")) {
            return proc.failGap(cx.diags, t[i].line, "PROC PROBIT: a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC PROBIT: a MODEL statement is required", .{});
    s.class = class.items;
    s.effects = effects.items;
    s.model_options = model_options.items;
    s.later = later.items;
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// The dose variable: the first continuous (non-CLASS) independent variable.
pub fn doseColumn(s: Spec) ?usize {
    for (s.effects) |ci| if (!has(s.class, ci)) return ci;
    return null;
}

/// Observation selection for one BY group (pp.8090, 8120): an observation
/// with a missing response, trials, independent or CLASS value is not used;
/// with WEIGHT, a zero, negative or missing weight is not used. Under
/// LOG/LOG10 a dose <= 0 makes the observation a control (OPTC) or ignored.
pub fn prepare(a: A, s: Spec, rows: []const []const Value) !Selection {
    var kept: std.ArrayList(usize) = .empty;
    var control: std.ArrayList(usize) = .empty;
    var w_kept: std.ArrayList(f64) = .empty;
    var w_control: std.ArrayList(f64) = .empty;
    var out: Selection = .{ .read = rows.len, .rows = &.{}, .control = &.{}, .weight = &.{}, .control_weight = &.{}, .missing = 0, .bad_weight = 0, .nonpositive_dose = 0 };
    const dose = if (s.log != .none) doseColumn(s) else null;
    for (rows, 0..) |row, k| {
        var w: f64 = 1;
        var w_ok = true;
        if (s.weight) |ci| {
            w = row[ci].num;
            w_ok = !std.math.isNan(w) and w > 0;
        }
        var miss = selection.missing(row[s.response]);
        if (s.trials) |ci| miss = miss or selection.missing(row[ci]);
        for (s.effects) |ci| miss = miss or selection.missing(row[ci]);
        for (s.class) |ci| miss = miss or selection.missing(row[ci]);
        if (miss) out.missing += 1;
        if (!w_ok) out.bad_weight += 1;
        if (miss or !w_ok) continue;
        if (dose) |ci| if (row[ci].num <= 0) {
            if (s.optc) {
                try control.append(a, k);
                try w_control.append(a, w);
            } else out.nonpositive_dose += 1;
            continue;
        };
        try kept.append(a, k);
        try w_kept.append(a, w);
    }
    out.rows = kept.items;
    out.control = control.items;
    out.weight = w_kept.items;
    out.control_weight = w_control.items;
    return out;
}

// ---------------------------------------------------------------- estimation

pub const FitError = error{ OutOfMemory, Singular, NotConverged };

pub const Fit = struct {
    /// Regression coefficients (intercept first), then C when estimated.
    theta: []f64,
    /// Inverse of the observed information, row-major, dimension theta.len.
    cov: []f64,
    loglik: f64,
    iterations: usize,
};

fn normalCdf(x: f64) f64 {
    return fns.distCdf(.normal, x, &.{}).?;
}
fn normalPdf(x: f64) f64 {
    return @exp(-x * x / 2) / @sqrt(2 * std.math.pi);
}

/// Solve the symmetric system m * x = rhs in place by Gaussian elimination
/// with partial pivoting; `m` is destroyed.
fn solve(m: []f64, rhs: []f64, n: usize) error{Singular}!void {
    for (0..n) |c| {
        var pivot = c;
        for (c + 1..n) |r| if (@abs(m[r * n + c]) > @abs(m[pivot * n + c])) {
            pivot = r;
        };
        if (!(@abs(m[pivot * n + c]) > 1e-12)) return error.Singular;
        if (pivot != c) {
            for (0..n) |k| std.mem.swap(f64, &m[c * n + k], &m[pivot * n + k]);
            std.mem.swap(f64, &rhs[c], &rhs[pivot]);
        }
        for (c + 1..n) |r| {
            const f = m[r * n + c] / m[c * n + c];
            if (f == 0) continue;
            for (c..n) |k| m[r * n + k] -= f * m[c * n + k];
            rhs[r] -= f * rhs[c];
        }
    }
    var c = n;
    while (c > 0) {
        c -= 1;
        var sum = rhs[c];
        for (c + 1..n) |k| sum -= m[c * n + k] * rhs[k];
        rhs[c] = sum / m[c * n + c];
    }
}

pub const Problem = struct {
    /// Design rows of the ordinary observations (n * p, intercept included).
    x: []const f64,
    events: []const f64,
    trials: []const f64,
    weight: []const f64,
    p: usize,
    /// Control group totals (weighted): they contribute r*log(C) + (n-r)*log(1-C).
    control_events: f64 = 0,
    control_trials: f64 = 0,
    /// Natural response rate: the fixed value, or the initial estimate.
    c: f64 = 0,
    estimate_c: bool = false,
};

const Derivatives = struct { loglik: f64, gradient: []f64, expected: []f64, observed: []f64 };

/// Log likelihood, score, expected information and observed information
/// (negative Hessian) of the binomial model p = C + (1-C)*Phi(x'b).
fn derivatives(a: A, q: Problem, theta: []const f64) !?Derivatives {
    const k = theta.len;
    const c = if (q.estimate_c) theta[q.p] else q.c;
    const d: Derivatives = .{ .loglik = 0, .gradient = try a.alloc(f64, k), .expected = try a.alloc(f64, k * k), .observed = try a.alloc(f64, k * k) };
    @memset(d.gradient, 0);
    @memset(d.expected, 0);
    @memset(d.observed, 0);
    var ll: f64 = 0;
    const g = try a.alloc(f64, k);
    for (q.events, q.trials, q.weight, 0..) |r, n, w, i| {
        const row = q.x[i * q.p ..][0..q.p];
        var eta: f64 = 0;
        for (row, theta[0..q.p]) |xv, b| eta += xv * b;
        const cdf = normalCdf(eta);
        const pdf = normalPdf(eta);
        const prob = c + (1 - c) * cdf;
        if (!(prob > 0 and prob < 1)) return null;
        ll += w * (r * @log(prob) + (n - r) * @log(1 - prob));
        const d1 = w * (r / prob - (n - r) / (1 - prob));
        const d2 = -w * (r / (prob * prob) + (n - r) / ((1 - prob) * (1 - prob)));
        const info = w * n / (prob * (1 - prob));
        for (row, 0..) |xv, j| g[j] = (1 - c) * pdf * xv;
        if (q.estimate_c) g[q.p] = 1 - cdf;
        for (0..k) |u| {
            d.gradient[u] += d1 * g[u];
            for (0..k) |v| {
                d.expected[u * k + v] += info * g[u] * g[v];
                // Second derivatives of p: (1-C)*(-eta*pdf)*x x' for b,b; -pdf*x for b,C; 0 for C,C.
                var second: f64 = 0;
                if (u < q.p and v < q.p) second = (1 - c) * (-eta * pdf) * row[u] * row[v] else if (u < q.p) second = -pdf * row[u] else if (v < q.p) second = -pdf * row[v];
                d.observed[u * k + v] -= d2 * g[u] * g[v] + d1 * second;
            }
        }
    }
    if (q.control_trials > 0) {
        const r = q.control_events;
        const n = q.control_trials;
        if (!(c > 0 and c < 1)) return null;
        ll += r * @log(c) + (n - r) * @log(1 - c);
        if (q.estimate_c) {
            const u = q.p;
            d.gradient[u] += r / c - (n - r) / (1 - c);
            d.expected[u * k + u] += n / (c * (1 - c));
            d.observed[u * k + u] += r / (c * c) + (n - r) / ((1 - c) * (1 - c));
        }
    }
    if (!std.math.isFinite(ll)) return null;
    var result = d;
    result.loglik = ll;
    return result;
}

/// Maximum likelihood by Fisher scoring with step halving, started at b = 0
/// and the supplied C. The reported covariance is the inverse of the observed
/// information at the solution (the reference standard errors are reproduced
/// by the observed, not the expected, information).
pub fn fitModel(a: A, q: Problem) FitError!Fit {
    const k = q.p + @intFromBool(q.estimate_c);
    const theta = try a.alloc(f64, k);
    @memset(theta, 0);
    if (q.estimate_c) theta[q.p] = q.c;
    var current = (try derivatives(a, q, theta)) orelse return error.NotConverged;
    const trial = try a.alloc(f64, k);
    const step = try a.alloc(f64, k);
    const matrix = try a.alloc(f64, k * k);
    var iteration: usize = 0;
    while (iteration < 200) : (iteration += 1) {
        @memcpy(matrix, current.expected);
        @memcpy(step, current.gradient);
        try solve(matrix, step, k);
        var scale: f64 = 1;
        var accepted: ?Derivatives = null;
        for (0..40) |_| {
            for (trial, theta, step) |*tv, old, dv| tv.* = old + scale * dv;
            const inside = !q.estimate_c or (trial[q.p] > 0 and trial[q.p] < 1);
            if (inside) if (try derivatives(a, q, trial)) |next| if (next.loglik >= current.loglik - 1e-13 * @abs(current.loglik)) {
                accepted = next;
                break;
            };
            scale /= 2;
        }
        const next = accepted orelse return error.NotConverged;
        var change: f64 = 0;
        for (trial, theta) |tv, old| change = @max(change, @abs(tv - old) / (@abs(old) + 1e-6));
        @memcpy(theta, trial);
        current = next;
        var gmax: f64 = 0;
        for (current.gradient) |gv| gmax = @max(gmax, @abs(gv));
        if (change < 1e-11 and gmax < 1e-7) break;
    } else return error.NotConverged;
    // Invert the observed information column by column.
    const cov = try a.alloc(f64, k * k);
    const column_rhs = try a.alloc(f64, k);
    for (0..k) |j| {
        @memcpy(matrix, current.observed);
        @memset(column_rhs, 0);
        column_rhs[j] = 1;
        try solve(matrix, column_rhs, k);
        for (0..k) |r| cov[r * k + j] = column_rhs[r];
    }
    for (0..k) |j| if (!(cov[j * k + j] > 0)) return error.Singular;
    return .{ .theta = theta, .cov = cov, .loglik = current.loglik, .iterations = iteration + 1 };
}

/// Tolerance-distribution parameters of a one-dose model (p.8099 listing):
/// MU = -b0/b1, SIGMA = 1/b1, with the delta-method covariance of
/// (MU, SIGMA, _C_) from the covariance of (b0, b1, C).
pub const Tolerance = struct { mu: f64, sigma: f64, cov: [9]f64 };
pub fn tolerance(f: Fit) Tolerance {
    const b0 = f.theta[0];
    const b1 = f.theta[1];
    // Jacobian rows: d(MU), d(SIGMA), d(C) with respect to (b0, b1, C).
    const jac = [3][3]f64{ .{ -1 / b1, b0 / (b1 * b1), 0 }, .{ 0, -1 / (b1 * b1), 0 }, .{ 0, 0, 1 } };
    var out: Tolerance = .{ .mu = -b0 / b1, .sigma = 1 / b1, .cov = undefined };
    for (0..3) |u| for (0..3) |v| {
        var sum: f64 = 0;
        for (0..3) |i| for (0..3) |j| {
            sum += jac[u][i] * f.cov[i * 3 + j] * jac[v][j];
        };
        out.cov[u * 3 + v] = sum;
    };
    return out;
}

// ----------------------------------------------------------------- rendering

fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn number(a: A, out: *Out, x: f64, decimals: usize, width: usize) !void {
    try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals }), width);
}
fn centered(a: A, out: *Out, title: []const u8, width: usize) !void {
    if (title.len < width) try out.appendNTimes(a, ' ', (width - title.len) / 2);
    try out.appendSlice(a, title);
    try out.append(a, '\n');
}
fn pvalue(a: A, out: *Out, p: f64, width: usize) !void {
    if (p < 0.0001) try padLeft(a, out, "<.0001", width) else try number(a, out, p, 4, width);
}

/// Two-sided 95% standard normal quantile, PROBIT(0.975).
const z95: f64 = 1.959963984540054;

const Counts = struct { observations: usize, events: f64, trials: f64, control_events: f64, control_trials: f64, used: usize, used_events: f64, used_trials: f64 };

/// One BY group's listing for the LOG10 + OPTC events/trials model with one
/// dose variable and a control group (reference: Getting Started, p.8099).
/// ponytail: column widths follow the reference listing; names longer than
/// the reference's widen only the name column.
fn render(a: A, out: *Out, s: Spec, counts: Counts, f: Fit) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe Probit Procedure\n\n");
    const data_name = blk: {
        const upper = try std.ascii.allocUpperString(a, s.data_name);
        break :blk if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    };
    const whole = struct {
        fn text(al: A, x: f64) ![]const u8 {
            return std.fmt.allocPrint(al, "{d:.0}", .{x});
        }
    }.text;
    const info = [_][2][]const u8{
        .{ "Data Set", data_name },
        .{ "Events Variable", ds.columns.items[s.response].name },
        .{ "Trials Variable", ds.columns.items[s.trials.?].name },
        .{ "Number of Observations", try std.fmt.allocPrint(a, "{d}", .{counts.observations}) },
        .{ "Number of Events", try whole(a, counts.events) },
        .{ "Number of Trials", try whole(a, counts.trials) },
        .{ "Number of Events In Control Group", try whole(a, counts.control_events) },
        .{ "Number of Trials In Control Group", try whole(a, counts.control_trials) },
        .{ "Name of Distribution", "Normal" },
        .{ "Log Likelihood", try std.fmt.allocPrint(a, "{d:.7}", .{f.loglik}) },
    };
    var value_width: usize = 12;
    for (info) |row| value_width = @max(value_width, row[1].len);
    try centered(a, out, "Model Information", 37 + value_width);
    try out.append(a, '\n');
    for (info) |row| {
        try padRight(a, out, row[0], 33);
        try padLeft(a, out, row[1], value_width + 4);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n", .{ counts.observations, counts.used });
    try out.print(a, "Number of Events           {s:>12}\nNumber of Trials           {s:>12}\n\n\n", .{ try whole(a, counts.used_events), try whole(a, counts.used_trials) });
    try padRight(a, out, "Algorithm converged.", 75);
    try out.appendSlice(a, "\n\n\n");

    const dose_name = try std.fmt.allocPrint(a, "Log10({s})", .{ds.columns.items[s.effects[0]].name});
    const se = [3]f64{ @sqrt(f.cov[0]), @sqrt(f.cov[4]), @sqrt(f.cov[8]) };
    const chi = [2]f64{ (f.theta[0] / se[0]) * (f.theta[0] / se[0]), (f.theta[1] / se[1]) * (f.theta[1] / se[1]) };

    const effect_width = @max(@as(usize, 17), dose_name.len);
    const effect_extra = effect_width - 17;
    try out.appendNTimes(a, ' ', effect_extra / 2);
    try centered(a, out, "Type III Analysis of Effects", 49);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', effect_extra);
    try out.appendSlice(a, "                               Wald\n");
    try padRight(a, out, "Effect", effect_width);
    try out.appendSlice(a, "  DF    Chi-Square    Pr > ChiSq\n\n");
    try padRight(a, out, dose_name, effect_width);
    try out.appendSlice(a, "   1");
    try number(a, out, chi[1], 4, 14);
    try pvalue(a, out, chiTail(chi[1], 1), 14);
    try out.appendSlice(a, "\n\n\n");

    const name_width = @max(@as(usize, 11), dose_name.len);
    const extra = name_width - 11;
    try out.appendNTimes(a, ' ', extra / 2);
    try centered(a, out, "Analysis of Maximum Likelihood Parameter Estimates", 69);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', extra);
    try out.appendSlice(a, "                        Standard   95% Confidence     Chi-\n");
    try padRight(a, out, "Parameter", name_width);
    try out.appendSlice(a, " DF Estimate    Error       Limits       Square Pr > ChiSq\n\n");
    for ([_][]const u8{ "Intercept", dose_name, "_C_" }, 0..) |label, j| {
        try padRight(a, out, label, name_width);
        try out.appendSlice(a, "  1");
        try number(a, out, f.theta[j], 4, 9);
        try number(a, out, se[j], 4, 9);
        try number(a, out, f.theta[j] - z95 * se[j], 4, 9);
        try number(a, out, f.theta[j] + z95 * se[j], 4, 9);
        if (j < 2) {
            try number(a, out, chi[j], 2, 8);
            try pvalue(a, out, chiTail(chi[j], 1), 11);
        } else try out.appendNTimes(a, ' ', 19);
        try out.append(a, '\n');
    }

    const tol = tolerance(f);
    try out.appendSlice(a, "\n\nProbit Model in Terms of Tolerance Distribution\n \n        MU         SIGMA\n\n");
    try number(a, out, tol.mu, 8, 10);
    try number(a, out, tol.sigma, 8, 14);
    try out.appendSlice(a, "\n\n\n");
    try centered(a, out, "Estimated Covariance Matrix for Tolerance Parameters", 59);
    try out.appendSlice(a, " \n                     MU             SIGMA               _C_\n\n");
    for ([_][]const u8{ "MU", "SIGMA", "_C_" }, 0..) |label, u| {
        try padRight(a, out, label, 5);
        for (0..3) |v| try number(a, out, tol.cov[u * 3 + v], 6, 18);
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const selections = try a.alloc(Selection, groups.len);
    for (groups, selections) |group, *sel| sel.* = try prepare(a, s, group.rows);

    // Boundaries owned by later PROBIT tickets: fail visibly, print nothing.
    if (s.later.len > 0) return gap(cx.diags, l0, "PROC PROBIT: the {s} statement is not implemented ({s})", .{ s.later[0], if (eq(s.later[0], "output")) "STAT-PROBIT-010" else "STAT-PROBIT-007..012" });
    if (s.plots) return gap(cx.diags, l0, "PROC PROBIT: PLOTS= graphs are not implemented (STAT-PROBIT-012)", .{});
    if (s.model_options.len > 0) return gap(cx.diags, l0, "PROC PROBIT: MODEL option {s} is not implemented (STAT-PROBIT-002/003)", .{s.model_options[0]});
    if (s.inversecl) return gap(cx.diags, l0, "PROC PROBIT: INVERSECL is not implemented (STAT-PROBIT-005)", .{});
    if (s.lackfit) return gap(cx.diags, l0, "PROC PROBIT: LACKFIT is not implemented (STAT-PROBIT-004)", .{});
    if (s.inest != null or s.outest != null or s.xdata != null or s.covout) return gap(cx.diags, l0, "PROC PROBIT: INEST=, OUTEST=, COVOUT and XDATA= are not implemented (STAT-PROBIT-009)", .{});
    if (s.noprint) return gap(cx.diags, l0, "PROC PROBIT: NOPRINT is not verified (no output data set is implemented yet; STAT-PROBIT-009)", .{});
    if (s.class.len > 0) return gap(cx.diags, l0, "PROC PROBIT: CLASS effects in the fitted model are not implemented (STAT-PROBIT-003)", .{});
    if (s.trials == null) return gap(cx.diags, l0, "PROC PROBIT: single-variable (binary/ordinal) responses are not implemented (STAT-PROBIT-002)", .{});
    if (s.weight != null) return gap(cx.diags, l0, "PROC PROBIT: the weighted listing is not verified against SAS output (STAT-PROBIT-002)", .{});
    if (s.effects.len != 1) return gap(cx.diags, l0, "PROC PROBIT: only one continuous dose variable is implemented; {d} independent variables are not (STAT-PROBIT-002/003)", .{s.effects.len});
    if (s.log != .log10 or !s.optc) return gap(cx.diags, l0, "PROC PROBIT: only the LOG10 OPTC listing is verified against SAS output; other LOG/LN/C=/OPTC combinations are not implemented (STAT-PROBIT-002)", .{});

    var body: Out = .empty;
    const trials_col = s.trials.?;
    const dose_col = s.effects[0];
    for (groups, selections) |group, sel| {
        if (sel.missing > 0) return gap(cx.diags, l0, "PROC PROBIT: the listing counts with observations excluded for missing values are not verified (STAT-PROBIT-002)", .{});
        if (sel.control.len == 0) return gap(cx.diags, l0, "PROC PROBIT: OPTC without a control group (no dose <= 0) is not implemented (STAT-PROBIT-002)", .{});
        if (sel.rows.len < 3) return gap(cx.diags, l0, "PROC PROBIT: a fit with {d} usable dose groups is not verified", .{sel.rows.len});
        const n = sel.rows.len;
        const x = try a.alloc(f64, n * 2);
        const events = try a.alloc(f64, n);
        const trials = try a.alloc(f64, n);
        var counts: Counts = .{ .observations = group.rows.len, .events = 0, .trials = 0, .control_events = 0, .control_trials = 0, .used = n, .used_events = 0, .used_trials = 0 };
        for (group.rows) |row| {
            const r = row[s.response].num;
            const m = row[trials_col].num;
            // The chapter's cited pages do not say how invalid counts are handled.
            if (!(m > 0) or r < 0 or r > m) return gap(cx.diags, l0, "PROC PROBIT: events/trials values outside 0 <= events <= trials, trials > 0 are not verified", .{});
        }
        for (sel.rows, 0..) |ri, i| {
            const row = group.rows[ri];
            x[i * 2] = 1;
            x[i * 2 + 1] = std.math.log10(row[dose_col].num);
            events[i] = row[s.response].num;
            trials[i] = row[trials_col].num;
            counts.used_events += events[i];
            counts.used_trials += trials[i];
        }
        for (sel.control) |ri| {
            counts.control_events += group.rows[ri][s.response].num;
            counts.control_trials += group.rows[ri][trials_col].num;
        }
        counts.events = counts.used_events + counts.control_events;
        counts.trials = counts.used_trials + counts.control_trials;
        // p.8089: C= is the initial estimate under OPTC; otherwise the
        // control group's response rate.
        const start = s.c orelse counts.control_events / counts.control_trials;
        if (!(start > 0 and start < 1)) return gap(cx.diags, l0, "PROC PROBIT: an initial natural response rate of 0 or 1 is not implemented (STAT-PROBIT-002)", .{});
        const r = fitModel(a, .{ .x = x, .events = events, .trials = trials, .weight = sel.weight, .p = 2, .control_events = counts.control_events, .control_trials = counts.control_trials, .c = start, .estimate_c = true }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx.diags, l0, "PROC PROBIT: a singular information matrix is not implemented (STAT-PROBIT-002)", .{}),
            error.NotConverged => return gap(cx.diags, l0, "PROC PROBIT: the fit did not converge; nonconvergence reporting is not implemented (STAT-PROBIT-002)", .{}),
        };
        if (s.by_cols.len > 0) try by.appendLine(a, &body, ds, group.rows[0], s.by_cols);
        try render(a, &body, s, counts, r);
    }
    for (groups) |group| {
        try cx.diags.note(0, "Algorithm converged.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("probit_tests.zig");
}
