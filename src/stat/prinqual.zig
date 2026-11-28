//! PROC PRINQUAL (SAS/STAT 15.4 ch.99): PROC statement options, the
//! TRANSFORM / BY / FREQ / ID / WEIGHT roles, observation selection (missing
//! values, nonpositive frequencies and weights, TYPE=), the iteration history
//! of the MTV and MAC methods and the default OUT= data set (STAT-PRINQUAL-001).
//!
//! Only IDENTITY transformations are computed: the iterations cannot change
//! them, so the analysis converges at iteration 1 and the MTV criterion is the
//! proportion of variance of the first N principal components of the
//! correlation (or COVARIANCE) matrix. Every other transformation, t-option,
//! method and output partition is a loud D-009 gap owned by a later PRINQUAL
//! ticket; nothing is printed and no data set is created for a step that hits
//! one. Listing layout, OUT= column order, passive-observation rows and the
//! notes and warnings were verified against SAS 9.4 runs on invented data.
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
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { mtv, mgv, mac };
pub const TStandard = enum { original, nomiss, center, z };

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement (pp.8040-8048). Defaults as documented.
    out: ?[]const u8 = null,
    method: Method = .mtv,
    n: usize = 2,
    maxiter: usize = 30,
    converge: f64 = 0.00001,
    cconverge: f64 = 0.0,
    change: usize = 1,
    inititer: usize = 0,
    refresh: usize = 5,
    singular: f64 = 1e-8,
    cov: bool = false,
    replace: bool = false,
    nomiss: bool = false,
    noprint: bool = false,
    nocheck: bool = false,
    dummy: bool = false,
    reiterate: bool = false,
    tstandard: TStandard = .original,
    prefix: []const u8 = "Prin",
    tprefix: []const u8 = "T",
    type_value: []const u8 = "SCORE",
    monotone: ?[2]u8 = null,
    untie: ?[2]u8 = null,
    /// First option that a later ticket owns (SCORES, APPROXIMATIONS, ...).
    gap_option: ?[]const u8 = null,
    plots: bool = false,
    // Roles.
    vars: []const usize = &.{},
    ids: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

/// Per-row role of one BY group (pp.8044, 8049, 8057, 8069).
pub const Status = enum { active, missing, freq, weight, type_excluded };

pub const Selection = struct {
    status: []const Status,
    /// FREQ integer portion times WEIGHT for active rows, else 0.
    w: []const f64,
    /// Active rows (observations, not frequencies).
    rows: usize,
    missing: usize,
    freq: usize,
    weight: usize,
    type_excluded: usize,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC PRINQUAL: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
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

/// Canonical spelling of a PROC statement option (aliases of pp.8040-8048).
fn canonical(lower: []const u8) []const u8 {
    const pairs = [_][2][]const u8{
        .{ "apr", "aprefix" },    .{ "approx", "approximations" }, .{ "app", "approximations" },
        .{ "cco", "cconverge" },  .{ "cha", "change" },            .{ "con", "converge" },
        .{ "cov", "covariance" }, .{ "cor", "correlations" },      .{ "dum", "dummy" },
        .{ "ini", "inititer" },   .{ "max", "maxiter" },           .{ "mdp", "mdpref" },
        .{ "met", "method" },     .{ "mon", "monotone" },          .{ "noc", "nocheck" },
        .{ "nom", "nomiss" },     .{ "nop", "noprint" },           .{ "pre", "prefix" },
        .{ "ref", "refresh" },    .{ "rei", "reiterate" },         .{ "rep", "replace" },
        .{ "sco", "scores" },     .{ "sin", "singular" },          .{ "std", "standard" },
        .{ "tpr", "tprefix" },    .{ "tst", "tstandard" },         .{ "typ", "type" },
        .{ "unt", "untie" },      .{ "plot", "plots" },
    };
    for (pairs) |p| if (eq(lower, p[0])) return p[1];
    return lower;
}

/// p.8043: a positive integer option; SAS's range message for 0 (verified
/// for N=0: "The parameter value 0 is not within the required range of 1 and 9999.").
fn intOption(cx: proc.ProcCtx, t: []const lex.Token, i: usize, min: usize) diag.Error!usize {
    if (!at(t, i + 2, .number)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= requires an integer value", .{t[i].text});
    const v = std.fmt.parseInt(usize, t[i + 2].text, 10) catch return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= requires an integer value", .{t[i].text});
    if (v < min or v > 9999) return cx.diags.fail(error.ParseError, t[i].line, "The parameter value {d} is not within the required range of {d} and 9999.", .{ v, min });
    return v;
}
fn numOption(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!struct { v: f64, next: usize } {
    var j = i + 2;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= requires a numeric value", .{t[i].text});
    const v = std.fmt.parseFloat(f64, t[j].text) catch return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= requires a numeric value", .{t[i].text});
    return .{ .v = sign * v, .next = j + 1 };
}
/// MONOTONE= / UNTIE= (pp.8043, 8048): two letters in alphabetical order.
fn twoLetters(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error![2]u8 {
    const ok = at(t, i + 2, .name) and t[i + 2].text.len == 2 and std.ascii.isAlphabetic(t[i + 2].text[0]) and std.ascii.isAlphabetic(t[i + 2].text[1]) and
        std.ascii.toUpper(t[i + 2].text[0]) <= std.ascii.toUpper(t[i + 2].text[1]);
    if (!ok) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= must be two letters in alphabetical order", .{t[i].text});
    return .{ std.ascii.toUpper(t[i + 2].text[0]), std.ascii.toUpper(t[i + 2].text[1]) };
}

fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}
fn columnList(cx: proc.ProcCtx, ds: *const Dataset, body: []const lex.Token, l: usize, role: []const u8, numeric: bool, into: *std.ArrayList(usize)) diag.Error!void {
    var j: usize = 0;
    while (j < body.len) {
        const names = try lists.next(cx.arena, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC PRINQUAL: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC PRINQUAL: variable {s} in the {s} transformation must be numeric", .{ n, role });
            if (has(into.items, ci)) {
                if (numeric) return proc.failGap(cx.diags, l, "PROC PRINQUAL: variable {s} listed more than once in the TRANSFORM statement is not verified (STAT-PRINQUAL-003)", .{n});
                continue;
            }
            try into.append(cx.arena, ci);
        }
    }
}

const transforms = [_][2][]const u8{
    .{ "arsin", "ars" },    .{ "exp", "exp" },     .{ "log", "log" },    .{ "logit", "logit" },
    .{ "power", "pow" },    .{ "rank", "ran" },    .{ "linear", "lin" }, .{ "monotone", "mon" },
    .{ "mspline", "msp" },  .{ "opscore", "ops" }, .{ "spline", "spl" }, .{ "untie", "unt" },
    .{ "identity", "ide" }, .{ "sspline", "ssp" },
};
fn transformName(word: []const u8) ?[]const u8 {
    for (transforms) |p| if (eq(word, p[0]) or eq(word, p[1])) return p[0];
    return null;
}

/// TRANSFORM transform(variables </ t-options>) ... ; (p.8037).
fn transformStatement(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, vars: *std.ArrayList(usize)) diag.Error!void {
    var j = i + 1;
    while (j < end) {
        if (!at(t, j, .name)) return invalid(cx, t, j);
        const name = transformName(t[j].text) orelse return invalid(cx, t, j);
        if (!at(t, j + 1, .lparen)) return invalid(cx, t, j + 1);
        const close = proc.skipParen(t, j + 1) - 1;
        if (close >= end or !at(t, close, .rparen)) return invalid(cx, t, j + 1);
        var stop = j + 2;
        while (stop < close and !at(t, stop, .slash)) stop += 1;
        if (stop == j + 2) return invalid(cx, t, stop);
        if (!eq(name, "identity")) return proc.failGap(cx.diags, t[j].line, "PROC PRINQUAL: the {s} transformation is not implemented (STAT-PRINQUAL-003)", .{t[j].text});
        if (stop < close) return proc.failGap(cx.diags, t[stop].line, "PROC PRINQUAL: transformation options (t-options) are not implemented (STAT-PRINQUAL-003)", .{});
        try columnList(cx, ds, t[j + 2 .. stop], t[j].line, "IDENTITY", true, vars);
        j = close + 1;
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = canonical(try std.ascii.allocLowerString(a, t[i].text));
        // A repeated option: the last one is used (verified against SAS 9.4
        // for N=, TPREFIX= and METHOD=; no note or warning is logged).
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &s.out);
        } else if (eq(option, "method") and valued) {
            s.method = if (kw(t, i + 2, "mtv")) .mtv else if (kw(t, i + 2, "mgv")) .mgv else if (kw(t, i + 2, "mac")) .mac else return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: METHOD= must be MAC, MGV or MTV", .{});
            i += 3;
        } else if (eq(option, "tstandard") and valued) {
            s.tstandard = if (kw(t, i + 2, "original") or kw(t, i + 2, "ori")) .original else if (kw(t, i + 2, "nomiss") or kw(t, i + 2, "nom")) .nomiss else if (kw(t, i + 2, "center") or kw(t, i + 2, "cen")) .center else if (kw(t, i + 2, "z")) .z else return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: TSTANDARD= must be CENTER, NOMISS, ORIGINAL or Z", .{});
            i += 3;
        } else if (eq(option, "n") and valued) {
            s.n = try intOption(cx, t, i, 1);
            i += 3;
        } else if (eq(option, "maxiter") and valued) {
            s.maxiter = try intOption(cx, t, i, 0);
            i += 3;
        } else if (eq(option, "change") and valued) {
            s.change = try intOption(cx, t, i, 1);
            i += 3;
        } else if (eq(option, "inititer") and valued) {
            s.inititer = try intOption(cx, t, i, 0);
            i += 3;
        } else if (eq(option, "refresh") and valued) {
            s.refresh = try intOption(cx, t, i, 1);
            i += 3;
        } else if ((eq(option, "converge") or eq(option, "cconverge") or eq(option, "singular")) and valued) {
            const r = try numOption(cx, t, i);
            if (eq(option, "converge")) s.converge = r.v else if (eq(option, "cconverge")) s.cconverge = r.v else {
                if (!(r.v > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: SINGULAR= must be positive", .{});
                s.singular = r.v;
            }
            i = r.next;
        } else if ((eq(option, "prefix") or eq(option, "tprefix")) and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: {s}= must be a name", .{t[i].text});
            if (eq(option, "prefix")) s.prefix = t[i + 2].text else s.tprefix = t[i + 2].text;
            i += 3;
        } else if (eq(option, "type") and valued) {
            if (!at(t, i + 2, .name) and !at(t, i + 2, .string)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINQUAL: TYPE= must be a name or quoted text", .{});
            s.type_value = t[i + 2].text;
            i += 3;
        } else if ((eq(option, "monotone") or eq(option, "untie")) and valued) {
            const v = try twoLetters(cx, t, i);
            if (eq(option, "monotone")) s.monotone = v else s.untie = v;
            i += 3;
        } else if (eq(option, "aprefix") or eq(option, "mdpref")) {
            // APREFIX= implies APPROXIMATIONS; MDPREF implies SCORES and CORRELATIONS.
            s.gap_option = s.gap_option orelse t[i].text;
            i += 1;
            if (at(t, i, .eq)) i += 2;
        } else if (eq(option, "plots")) {
            i += 1;
            var none = false;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
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
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "covariance")) {
            s.cov = true;
            i += 1;
        } else if (eq(option, "replace")) {
            s.replace = true;
            i += 1;
        } else if (eq(option, "nomiss")) {
            s.nomiss = true;
            i += 1;
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "nocheck")) {
            s.nocheck = true;
            i += 1;
        } else if (eq(option, "dummy")) {
            s.dummy = true;
            i += 1;
        } else if (eq(option, "reiterate")) {
            s.reiterate = true;
            i += 1;
        } else if (eq(option, "scores") or eq(option, "approximations") or eq(option, "correlations") or eq(option, "standard")) {
            s.gap_option = s.gap_option orelse t[i].text;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC PRINQUAL: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var transform_statements: usize = 0;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
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
            // p.8036: "If you specify more than one BY statement, only the last one specified is used."
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "transform") or eq(word, "transformation") or eq(word, "tra")) {
            transform_statements += 1;
            if (transform_statements == 1) try transformStatement(cx, ds, t, i, end, &vars);
        } else if (eq(word, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            try columnList(cx, ds, t[i + 1 .. end], t[i].line, "ID", false, &ids);
        } else if (eq(word, "freq")) {
            // Verified against SAS 9.4: with two FREQ (or WEIGHT) statements the
            // first one is used, silently (unlike BY, where the last one wins).
            const ci = try oneNumeric(cx, ds, t, i, end, "FREQ");
            if (s.freq == null) s.freq = ci;
        } else if (eq(word, "weight")) {
            const ci = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
            if (s.weight == null) s.weight = ci;
        } else if (eq(word, "format")) {
            var j = i;
            try proc.parseProcFormat(a, t, &j, &formats);
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // Verified SAS error for no TRANSFORM statement, two TRANSFORM statements
    // and (by its wording) a single variable.
    if (transform_statements != 1 or vars.items.len < 2)
        return cx.diags.fail(error.ParseError, line(t, 0), "A single TRANSFORM statement with at least one transformation name and at least two variables is required.", .{});
    // FORMAT statement (verified against SAS 9.4): the formats attach to the
    // variables for this step, so OUT= carries them on the original and the
    // transformed variables and _NAME_ is the formatted ID value. The input
    // data set itself is not changed (a shallow copy carries the formats).
    if (formats.items.len > 0) {
        const copy = try a.create(Dataset);
        copy.* = Dataset.init(a, ds.name);
        copy.sortseq_linguistic = ds.sortseq_linguistic;
        try copy.columns.appendSlice(a, ds.columns.items);
        try copy.rows.appendSlice(a, ds.rows.items);
        for (formats.items) |f| {
            const ci = copy.indexOf(f.name) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC PRINQUAL: variable {s} in the FORMAT statement is not on the input data set", .{f.name});
            copy.columns.items[ci].format = if (f.spec.len == 0) null else f.spec;
        }
        s.input.ds = copy;
    }
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.ids = ids.items;
    s.vars = vars.items;
    return s;
}

/// Observation selection for one BY group. An observation is passive (blank
/// _TYPE_, weight 0) when an IDENTITY variable is missing, its frequency is
/// below 1 or its weight is not positive (pp.8044, 8049, 8057, 8069); an
/// observation with a nonblank _TYPE_ other than TYPE= leaves the analysis and
/// the OUT= data set (p.8047, verified).
pub fn select(a: A, s: Spec, ds: *const Dataset, rows: []const []const Value) !Selection {
    const status = try a.alloc(Status, rows.len);
    const w = try a.alloc(f64, rows.len);
    var sel: Selection = .{ .status = status, .w = w, .rows = 0, .missing = 0, .freq = 0, .weight = 0, .type_excluded = 0 };
    const type_col = ds.indexOf("_TYPE_");
    for (rows, 0..) |row, ri| {
        w[ri] = 0;
        status[ri] = st: {
            if (type_col) |tc| if (ds.columns.items[tc].type == .char) {
                const v = std.mem.trim(u8, row[tc].str, " ");
                if (v.len > 0 and !eq(v, std.mem.trim(u8, s.type_value, " "))) break :st .type_excluded;
            };
            for (s.vars) |ci| if (std.math.isNan(row[ci].num)) break :st .missing;
            var f: f64 = 1;
            if (s.freq) |ci| {
                f = @floor(row[ci].num);
                if (!(f >= 1)) break :st .freq;
            }
            var wt: f64 = 1;
            if (s.weight) |ci| {
                wt = row[ci].num;
                if (!(wt > 0)) break :st .weight;
            }
            w[ri] = f * wt;
            break :st .active;
        };
        switch (status[ri]) {
            .active => sel.rows += 1,
            .missing => sel.missing += 1,
            .freq => sel.freq += 1,
            .weight => sel.weight += 1,
            .type_excluded => sel.type_excluded += 1,
        }
    }
    return sel;
}

pub const Moments = struct {
    mean: []const f64,
    /// Standard deviation with divisor (active observations - 1).
    std: []const f64,
    /// Row-major p*p analysis matrix (correlations, or covariances with COV).
    matrix: []const f64,
};

/// Weighted means and cross products of the active rows. Null when a
/// variable has no variance (constant variables are a STAT-PRINQUAL-005 gap).
pub fn moments(a: A, s: Spec, rows: []const []const Value, sel: Selection) !?Moments {
    const p = s.vars.len;
    const mean = try a.alloc(f64, p);
    const sd = try a.alloc(f64, p);
    const css = try a.alloc(f64, p * p);
    @memset(mean, 0);
    @memset(css, 0);
    var sw: f64 = 0;
    for (rows, sel.w) |row, w| {
        if (w == 0) continue;
        sw += w;
        for (s.vars, mean) |ci, *m| m.* += w * row[ci].num;
    }
    for (mean) |*m| m.* /= sw;
    for (rows, sel.w) |row, w| {
        if (w == 0) continue;
        for (s.vars, 0..) |ci, j| {
            const dj = row[ci].num - mean[j];
            for (s.vars[0 .. j + 1], 0..) |ck, k| css[j * p + k] += w * dj * (row[ck].num - mean[k]);
        }
    }
    for (0..p) |j| {
        if (!(css[j * p + j] > 0)) return null;
        sd[j] = @sqrt(css[j * p + j] / (@as(f64, @floatFromInt(sel.rows)) - 1));
    }
    const matrix = try a.alloc(f64, p * p);
    for (0..p) |j| for (0..j + 1) |k| {
        const r = if (s.cov) css[j * p + k] else if (j == k) 1.0 else css[j * p + k] / @sqrt(css[j * p + j] * css[k * p + k]);
        matrix[j * p + k] = r;
        matrix[k * p + j] = r;
    };
    return .{ .mean = mean, .std = sd, .matrix = matrix };
}

/// MTV criterion: proportion of the total variance accounted for by the
/// first N principal components (p.8046).
pub fn proportion(a: A, m: Moments, p: usize, n: usize) !f64 {
    const e = try princomp.eigenSym(a, m.matrix, p);
    var total: f64 = 0;
    var top: f64 = 0;
    for (e.values, 0..) |v, k| {
        total += v;
        if (k < n) top += v;
    }
    return top / total;
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}

/// Iteration history of an analysis that converged at iteration 1 (every
/// variable IDENTITY), in the verified SAS layout.
pub fn render(a: A, out: *Out, method: Method, criterion: f64, few_obs: bool) !void {
    try out.appendSlice(a, "\nThe PRINQUAL Procedure\n\n");
    switch (method) {
        .mtv => {
            try out.appendSlice(a, "                  PRINQUAL MTV Algorithm Iteration History\n \n");
            try out.appendSlice(a, "Iteration    Average    Maximum     Proportion    Criterion\n");
            try out.appendSlice(a, "   Number     Change     Change    of Variance       Change    Note\n");
            try out.appendNTimes(a, '-', 76);
            try out.print(a, "\n        1    0.00000    0.00000    {d:>11.5}                 Converged    \n", .{criterion});
        },
        .mac => {
            try out.appendSlice(a, "    PRINQUAL MAC Algorithm Iteration History\n \n");
            try out.appendSlice(a, "Iteration    Average    Maximum\n");
            try out.appendSlice(a, "   Number     Change     Change    Note\n");
            try out.appendNTimes(a, '-', 48);
            try out.appendSlice(a, "\n        1    0.00000    0.00000    Converged    \n");
        },
        .mgv => unreachable,
    }
    try out.appendSlice(a, "\nAlgorithm converged.");
    try pad(a, out, 54);
    try out.appendSlice(a, "\n");
    if (few_obs) try out.appendSlice(a, "WARNING: The number of observations is less than or equal to the number of variables.\nWARNING: Multiple optimal solutions may exist.\n");
}

/// BY line of a group. Verified against SAS 9.4 under NOCENTER: a blank
/// line, then `g=1` at column 1 (the shared statistical BY line is centred;
/// opensas listings are uncentred, so this procedure strips the indent).
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    var it = std.mem.splitScalar(u8, tmp.items, '\n');
    var first = true;
    while (it.next()) |l| {
        if (!first) try out.append(a, '\n');
        first = false;
        try out.appendSlice(a, std.mem.trimStart(u8, l, " "));
    }
}

fn deletionNotes(cx: proc.ProcCtx, sel: Selection) !void {
    var reasons: usize = 0;
    if (sel.type_excluded > 0) try cx.diags.note(0, "{d} observations of nonblank _TYPE_ not equal 'SCORE' are excluded from the analysis and the output data set.", .{sel.type_excluded});
    const items = [_]struct { n: usize, why: []const u8 }{
        .{ .n = sel.missing, .why = "missing values" },
        .{ .n = sel.freq, .why = "nonpositive frequencies" },
        .{ .n = sel.weight, .why = "nonpositive weights" },
    };
    for (items) |it| if (it.n > 0) {
        reasons += 1;
        try cx.diags.note(0, "{d} observations were deleted from the analysis due to {s}.", .{ it.n, it.why });
    };
    if (reasons > 1) try cx.diags.note(0, "A total of {d} observations were deleted.", .{sel.missing + sel.freq + sel.weight});
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const p = s.vars.len;

    // Boundaries owned by later PRINQUAL tickets: fail visibly, print nothing.
    if (s.gap_option) |o| return gap(cx.diags, l0, "PROC PRINQUAL: the {s} option (component scores, approximations or correlations in OUT=) is not implemented (STAT-PRINQUAL-007)", .{o});
    if (s.plots) return gap(cx.diags, l0, "PROC PRINQUAL: PLOTS= graphs are not implemented (STAT-PRINQUAL-009)", .{});
    if (s.method == .mgv) return gap(cx.diags, l0, "PROC PRINQUAL: METHOD=MGV is not implemented (STAT-PRINQUAL-003)", .{});
    // Verified SAS warning; the analysis continues with N = number of variables.
    const ncomp = if (s.n > p) blk: {
        try cx.diags.warn(l0, "More components were requested than variables to be analyzed. N={d} assumed.", .{p});
        break :blk p;
    } else s.n;
    if (s.maxiter == 0 or s.change != 1 or s.inititer != 0 or !(s.converge > 0))
        return gap(cx.diags, l0, "PROC PRINQUAL: MAXITER=0, CHANGE=, INITITER= or a nonpositive CONVERGE= (more than one displayed iteration) is not verified against SAS output (STAT-PRINQUAL-004)", .{});
    if ((s.tstandard == .center or s.tstandard == .z) and (s.freq != null or s.weight != null))
        return gap(cx.diags, l0, "PROC PRINQUAL: TSTANDARD=CENTER or Z with FREQ or WEIGHT is not verified against SAS output (STAT-PRINQUAL-007)", .{});
    // Variable names (p.8055): prefix plus the original name within 32 characters.
    const tnames = try a.alloc([]const u8, p);
    for (s.vars, tnames) |ci, *n| {
        const orig = ds.columns.items[ci].name;
        n.* = if (s.replace) orig else try std.fmt.allocPrint(a, "{s}{s}", .{ s.tprefix, orig });
        if (n.len > 32) return gap(cx.diags, l0, "PROC PRINQUAL: transformed variable name truncation for {s} is not implemented (STAT-PRINQUAL-007)", .{orig});
    }

    // Verified: an empty input data set gives a note, no listing and an
    // empty OUT= data set with the usual variables.
    const empty = ds.rows.items.len == 0;
    if (empty) try cx.diags.note(l0, "No observations in data set {s}.", .{try std.ascii.allocUpperString(a, if (std.mem.indexOfScalar(u8, ds.name, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{ds.name}) else ds.name)});
    const groups = if (empty) &[_]proc.BySlice{} else try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    // Validate and compute every group before anything prints.
    const sels = try a.alloc(Selection, groups.len);
    const moms = try a.alloc(Moments, groups.len);
    const crits = try a.alloc(f64, groups.len);
    for (groups, sels, moms, crits) |group, *sel, *m, *c| {
        sel.* = try select(a, s, ds, group.rows);
        // Verified against SAS 9.4: a BY group with fewer than two active
        // observations logs "ERROR: Too few observations.", prints nothing,
        // writes no OUT= rows (not even its passive ones) and the remaining
        // groups are analysed. Skipped groups are marked by rows < 2 below.
        // Without BY the step stops after that ERROR, leaving an empty OUT=
        // data set with the usual variables (also verified).
        if (sel.rows < 2) continue;
        if (sel.rows <= p and s.method == .mac) return gap(cx.diags, l0, "PROC PRINQUAL: METHOD=MAC with no more observations than variables is not verified against SAS output (STAT-PRINQUAL-003)", .{});
        m.* = (try moments(a, s, group.rows, sel.*)) orelse return gap(cx.diags, l0, "PROC PRINQUAL: a constant variable is not implemented (STAT-PRINQUAL-005)", .{});
        c.* = try proportion(a, m.*, p, ncomp);
    }

    // OUT= (p.8053, column order verified): BY, _TYPE_, _NAME_, FREQ, WEIGHT,
    // original variables (unless REPLACE), transformed variables, ID.
    const member = s.out orelse blk: {
        // ponytail: the first unused WORK.DATAn, not a session counter.
        var k: usize = 1;
        while (cx.lib.find(try std.fmt.allocPrint(a, "DATA{d}", .{k})) != null) k += 1;
        break :blk try std.fmt.allocPrint(a, "DATA{d}", .{k});
    };
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, member);
    var src: std.ArrayList(?usize) = .empty; // input column, or null for _TYPE_/_NAME_/T
    const add = struct {
        fn f(al: A, od: *Dataset, list: *std.ArrayList(?usize), d: *const Dataset, ci: usize) !void {
            for (list.items) |x| if (x != null and x.? == ci) return;
            _ = try od.addColumnLike(d.columns.items[ci].name, d.columns.items[ci]);
            try list.append(al, ci);
        }
    }.f;
    for (s.by_cols) |ci| try add(a, o, &src, ds, ci);
    _ = try o.addColumn("_TYPE_", .char);
    o.setLen("_TYPE_", 8);
    _ = try o.addColumn("_NAME_", .char);
    o.setLen("_NAME_", 32);
    try src.appendSlice(a, &.{ null, null });
    if (s.freq) |ci| try add(a, o, &src, ds, ci);
    if (s.weight) |ci| try add(a, o, &src, ds, ci);
    if (!s.replace) for (s.vars) |ci| try add(a, o, &src, ds, ci);
    const t_first = o.columns.items.len;
    for (s.vars, tnames) |ci, n| {
        if (o.indexOf(n) != null) return gap(cx.diags, l0, "PROC PRINQUAL: transformed variable name {s} collides with another OUT= variable (STAT-PRINQUAL-007)", .{n});
        _ = try o.addColumnLike(n, ds.columns.items[ci]);
        o.columns.items[o.columns.items.len - 1].label = try std.fmt.allocPrint(a, "{s} Transformation", .{ds.columns.items[ci].name});
        try src.append(a, null);
    }
    // Verified against SAS 9.4: an ID variable already in OUT= (for example
    // a TRANSFORM variable) is written again under a numbered name, with
    // "NOTE: Variable x already exists on file WORK.O, using x2 instead.".
    for (s.ids) |ci| {
        if (std.mem.indexOfScalar(?usize, src.items, ci) == null) {
            try add(a, o, &src, ds, ci);
            continue;
        }
        const orig = ds.columns.items[ci].name;
        var k: usize = 2;
        var n = try std.fmt.allocPrint(a, "{s}{d}", .{ orig, k });
        while (o.indexOf(n) != null) : (k += 1) n = try std.fmt.allocPrint(a, "{s}{d}", .{ orig, k + 1 });
        try cx.diags.note(0, "Variable {s} already exists on file {s}{s}, using {s} instead.", .{ orig, if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "", try std.ascii.allocUpperString(a, member), n });
        _ = try o.addColumnLike(n, ds.columns.items[ci]);
        try src.append(a, ci);
    }

    var body: Out = .empty;
    for (groups, sels, moms, crits) |group, sel, m, c| {
        var row_no: usize = 0; // verified: ROW1, ROW2, ... restart in each BY group
        try deletionNotes(cx, sel);
        if (sel.rows < 2) {
            try cx.diags.recoverableErr(0, "Too few observations.", .{});
            if (s.by_cols.len > 0) {
                try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
                continue;
            }
            try cx.lib.put(member, o);
            try cx.diags.warn(0, "The data set {s}{s} may be incomplete.  When this step was stopped there were 0 observations and {d} variables.", .{ if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "", try std.ascii.allocUpperString(a, member), o.columns.items.len });
            return;
        }
        if (!s.noprint) {
            if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
            try render(a, &body, s.method, c, sel.rows <= p and s.method == .mtv);
        }
        if (sel.rows <= p and s.method == .mtv) {
            try cx.diags.warn(0, "The number of observations is less than or equal to the number of variables.", .{});
            try cx.diags.warn(0, "Multiple optimal solutions may exist.", .{});
        }
        try cx.diags.note(0, "Algorithm converged.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
        const values = try a.alloc(Value, o.columns.items.len);
        for (group.rows, sel.status) |row, status| {
            if (status == .type_excluded) continue;
            row_no += 1;
            for (src.items, 0..) |from, k| {
                if (from) |ci| values[k] = row[ci];
            }
            values[s.by_cols.len] = .{ .str = if (status == .active) "SCORE" else "" };
            values[s.by_cols.len + 1] = .{ .str = if (s.ids.len > 0) blk: {
                const info = ds.columns.items[s.ids[0]];
                const text = if (info.format) |fmt| try format.apply(a, row[s.ids[0]], fmt) else try proc.cellText(a, row[s.ids[0]]);
                break :blk std.mem.trim(u8, text, " ");
            } else try std.fmt.allocPrint(a, "ROW{d}", .{row_no}) };
            // TSTANDARD= (p.8047, verified): ORIGINAL/NOMISS leave IDENTITY
            // values unchanged; CENTER and Z use the active observations.
            for (s.vars, 0..) |ci, j| {
                const x = row[ci].num;
                values[t_first + j] = .{ .num = if (std.math.isNan(x)) x else switch (s.tstandard) {
                    .original, .nomiss => x,
                    .center => x - m.mean[j],
                    .z => (x - m.mean[j]) / m.std[j],
                } };
            }
            try o.appendRow(values);
        }
    }
    try cx.lib.put(member, o);
    const upper = try std.ascii.allocUpperString(a, member);
    const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, o.rows.items.len, o.columns.items.len });
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("prinqual_tests.zig");
}
