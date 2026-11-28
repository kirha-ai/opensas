//! PROC FACTOR (SAS/STAT 15.4 ch.44): PROC statement options, VAR / BY /
//! FREQ / WEIGHT / PARTIAL / PRIORS roles, observation selection, and the
//! default analysis — METHOD=PRINCIPAL with PRIORS=ONE, no rotation — with the
//! SIMPLE, CORR and SCORE displays (STAT-FACTOR-001). Every documented option
//! or statement this file does not compute, or whose listing has not been
//! verified against a SAS listing, is a loud D-009 gap; nothing is printed for
//! a step that hits one.
//!
//! The correlation matrix, observation selection and the Jacobi
//! eigen-decomposition are PROC PRINCOMP's (src/stat/princomp.zig), called
//! read-only. With PRIORS=ONE the factor pattern is each eigenvector scaled by
//! the square root of its eigenvalue; the eigenvector orientation (nonnegative
//! element sum) reproduces the signs of the SAS listing of the chapter's
//! socioeconomics example. Listing layout is taken from that listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const pc = @import("princomp.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement (pp.2797-2816). Implemented defaults: METHOD=PRINCIPAL,
    // PRIORS=ONE, ROTATE=NONE, VARDEF=DF, NFACTORS= number of variables,
    // MINEIGEN=1 (total weighted variance / number of variables with unit
    // priors and no weights).
    simple: bool = false,
    corr: bool = false,
    score: bool = false,
    noprint: bool = false,
    /// OUTSTAT= member (STAT-DATASET-001): a TYPE=FACTOR data set (S154 Table A.2).
    outstat: ?[]const u8 = null,
    nfactors: ?usize = null,
    mineigen: ?f64 = null,
    // Roles.
    vars: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
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
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC FACTOR: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
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

/// Canonical spelling of a PROC statement option (aliases of pp.2801-2816).
fn canonical(lower: []const u8) []const u8 {
    const pairs = [_][2][]const u8{
        .{ "c", "corr" },              .{ "s", "simple" },             .{ "m", "method" },
        .{ "min", "mineigen" },        .{ "nfact", "nfactors" },       .{ "n", "nfactors" },
        .{ "prior", "priors" },        .{ "r", "rotate" },             .{ "conv", "converge" },
        .{ "covariance", "cov" },      .{ "ev", "eigenvectors" },      .{ "hey", "heywood" },
        .{ "hkp", "hkpower" },         .{ "nopmaxnorm", "nopromaxnorm" }, .{ "nplot", "nplots" },
        .{ "threads", "nthreads" },    .{ "pre", "prerotate" },        .{ "percent", "proportion" },
        .{ "p", "proportion" },        .{ "rconv", "rconverge" },      .{ "re", "reorder" },
        .{ "res", "residuals" },       .{ "se", "stderr" },            .{ "sing", "singular" },
        .{ "ultra", "ultraheywood" },  .{ "plot", "plot" },            .{ "cover", "ci" },
    };
    for (pairs) |p| if (eq(lower, p[0])) return p[1];
    return lower;
}

/// Documented PROC FACTOR options (pp.2797-2816) that this ticket does not
/// implement: a valid program using one must fail visibly (D-009).
const documented_gaps = [_][]const u8{
    "all",       "alpha",        "ci",          "converge",  "cov",       "eigenvectors", "flag",     "fuzz",
    "gamma",     "heywood",      "hkpower",     "map",       "maxiter",   "msa",          "nobs",     "nocorr",
    "noint",     "nopromaxnorm", "norm",        "nplots",    "nthreads",  "out",          "parallel",
    "parprefix", "plot",         "plotref",     "plots",     "power",     "prefix",       "preplot",  "prerotate",
    "print",     "proportion",   "random",      "rconverge", "reorder",   "residuals",    "riter",    "round",
    "scree",     "stderr",       "singular",    "target",    "tau",       "ultraheywood", "vardef",   "weight",
};

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = canonical(try std.ascii.allocLowerString(a, t[i].text));
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, t[i].line, "PROC FACTOR: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "method") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: METHOD= must be a method name", .{});
            const m = t[i + 2].text;
            if (!(eq(m, "principal") or eq(m, "prin") or eq(m, "p"))) {
                const known = [_][]const u8{ "alpha", "a", "harris", "h", "image", "i", "ml", "m", "pattern", "prinit", "score", "uls", "u" };
                for (known) |k| if (eq(m, k)) return gap(cx.diags, t[i].line, "PROC FACTOR: METHOD={s} is not implemented (STAT-FACTOR-002)", .{m});
                return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: METHOD={s} is not a valid method", .{m});
            }
            i += 3;
        } else if (eq(option, "priors") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: PRIORS= must be a prior communality method", .{});
            const m = t[i + 2].text;
            if (!(eq(m, "one") or eq(m, "o"))) {
                const known = [_][]const u8{ "asmc", "a", "input", "i", "max", "m", "random", "r", "smc", "s" };
                for (known) |k| if (eq(m, k)) return gap(cx.diags, t[i].line, "PROC FACTOR: PRIORS={s} is not implemented (STAT-FACTOR-005)", .{m});
                return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: PRIORS={s} is not a valid prior communality method", .{m});
            }
            i += 3;
        } else if (eq(option, "rotate") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: ROTATE= must be a rotation name", .{});
            const m = t[i + 2].text;
            if (!(eq(m, "none") or eq(m, "n"))) return gap(cx.diags, t[i].line, "PROC FACTOR: ROTATE={s} is not implemented", .{m});
            i += 3;
        } else if (eq(option, "nfactors") and valued) {
            if (at(t, i + 2, .name)) return gap(cx.diags, t[i].line, "PROC FACTOR: NFACTORS={s} (a named extraction criterion) is not implemented (STAT-FACTOR-004)", .{t[i + 2].text});
            if (at(t, i + 2, .minus)) return gap(cx.diags, t[i].line, "PROC FACTOR: NFACTORS=-1 is not implemented (STAT-FACTOR-004)", .{});
            const n = (if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null) orelse
                return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: NFACTORS= must be an integer", .{});
            if (n == 0) return gap(cx.diags, t[i].line, "PROC FACTOR: NFACTORS=0 is not implemented (STAT-FACTOR-004)", .{});
            s.nfactors = n;
            i += 3;
        } else if (eq(option, "mineigen") and valued) {
            // p.2804: "Negative values of p are not allowed."
            const v = if (at(t, i + 2, .number)) std.fmt.parseFloat(f64, t[i + 2].text) catch null else null;
            if (v == null) return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: MINEIGEN= must be a nonnegative number", .{});
            s.mineigen = v.?;
            i += 3;
        } else if (valued and eq(option, "proportion")) {
            return gap(cx.diags, t[i].line, "PROC FACTOR: PROPORTION= is not implemented (STAT-FACTOR-004)", .{});
        } else if (eq(option, "simple") and !valued) {
            s.simple = true;
            i += 1;
        } else if (eq(option, "corr") and !valued) {
            s.corr = true;
            i += 1;
        } else if (eq(option, "score") and !valued) {
            s.score = true;
            i += 1;
        } else if (eq(option, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "outstat") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &s.outstat);
            if (after > 0 and at(t, after - 1, .rparen)) return gap(cx.diags, t[i].line, "PROC FACTOR: data set options on OUTSTAT= are not implemented", .{});
            i = after;
        } else {
            for (documented_gaps) |g| if (eq(option, g)) return gap(cx.diags, t[i].line, "PROC FACTOR: the {s} option is not implemented", .{t[i].text});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC FACTOR: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    // pp.2824-2826: TYPE=CORR/COV/UCOV/FACTOR/... input is read by _TYPE_.
    if (ds.indexOf("_type_") != null) return gap(cx.diags, line(t, 0), "PROC FACTOR: input data sets with a _TYPE_ variable (TYPE=CORR, COV, FACTOR, ...) are not implemented", .{});
    if (ds.ds_type) |ty| return gap(cx.diags, line(t, 0), "PROC FACTOR: TYPE={s} input data sets are not implemented", .{ty}); // STAT-DATASET-001

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var var_seen = false;
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
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx.diags, t[i].line, "PROC FACTOR: more than one VAR statement is not verified", .{});
            var_seen = true;
            try columnList(cx, ds, t, i, end, "VAR", &vars);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC FACTOR: more than one FREQ statement is not verified", .{});
            s.freq = try oneNumeric(cx, ds, t, i, end, "FREQ");
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC FACTOR: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
        } else if (eq(word, "partial")) {
            return gap(cx.diags, t[i].line, "PROC FACTOR: the PARTIAL statement is not implemented (STAT-FACTOR-003)", .{});
        } else if (eq(word, "priors")) {
            return gap(cx.diags, t[i].line, "PROC FACTOR: the PRIORS statement is not implemented (STAT-FACTOR-005)", .{});
        } else if (eq(word, "pathdiagram")) {
            return gap(cx.diags, t[i].line, "PROC FACTOR: the PATHDIAGRAM statement is not implemented", .{});
        } else if (eq(word, "format")) {
            return gap(cx.diags, t[i].line, "PROC FACTOR: a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (!var_seen) {
        // p.2823: without a VAR statement all numeric variables not listed in
        // other statements are analyzed.
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC FACTOR: no numeric variables to analyze", .{});
    return s;
}

fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC FACTOR: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}
fn columnList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, into: *std.ArrayList(usize)) diag.Error!void {
    if (end == i + 1) return invalid(cx, t, end);
    const body = t[i + 1 .. end];
    var j: usize = 0;
    while (j < body.len) {
        const l = body[j].line;
        const names = try lists.next(cx.arena, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC FACTOR: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC FACTOR: variable {s} in the {s} statement must be numeric", .{ n, role });
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
}

/// The PRINCOMP view of this step, for its selection and moment kernels.
fn kernelSpec(s: Spec) pc.Spec {
    return .{ .input = s.input, .vars = s.vars, .freq = s.freq, .weight = s.weight };
}

pub const Retained = struct { count: usize, criterion: []const u8 };

/// Number of factors retained (pp.2804-2806) for PRIORS=ONE with one
/// criterion. Null when the combination is not verified.
pub fn retained(s: Spec, values: []const f64) ?Retained {
    const p = values.len;
    if (s.nfactors != null and s.mineigen != null) return null;
    if (s.nfactors) |n| {
        if (n > p) return null;
        return .{ .count = n, .criterion = "NFACTOR" };
    }
    // Default MINEIGEN = total weighted variance / number of variables = 1.
    const threshold = s.mineigen orelse 1.0;
    var count: usize = 0;
    for (values) |v| {
        if (v >= threshold) count += 1 else break;
    }
    return .{ .count = count, .criterion = "MINEIGEN" };
}

pub const Solution = struct {
    /// Row-major p*nf factor pattern.
    pattern: []const f64,
    /// Row-major p*nf standardized scoring coefficients (R^-1 * pattern).
    scoring: []const f64,
    /// Final communality of each variable.
    communality: []const f64,
};

/// PRIORS=ONE principal-component factors: pattern = v_k * sqrt(lambda_k);
/// standardized scoring coefficients = R^-1 * pattern = v_k / sqrt(lambda_k).
pub fn solve(a: A, e: pc.Eigen, p: usize, nf: usize) !Solution {
    const pattern = try a.alloc(f64, p * nf);
    const scoring = try a.alloc(f64, p * nf);
    const comm = try a.alloc(f64, p);
    @memset(comm, 0);
    for (0..p) |j| for (0..nf) |k| {
        const root = @sqrt(e.values[k]);
        const v = e.vectors[j * p + k];
        pattern[j * nf + k] = v * root;
        scoring[j * nf + k] = v / root;
        comm[j] += v * root * v * root;
    };
    return .{ .pattern = pattern, .scoring = scoring, .communality = comm };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try pad(a, out, width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try pad(a, out, width - text.len);
}
fn title(a: A, out: *Out, text: []const u8, indent: usize) !void {
    try out.appendSlice(a, "\n\n");
    try pad(a, out, indent);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}
/// Heading over a table with a row-label column (verified: left = floor).
fn labelledIndent(width: usize, text: usize) usize {
    return if (width > text) (width - text) / 2 else 0;
}
/// Heading over a one-row table without labels (verified: left = ceil).
fn rowIndent(width: usize, text: usize) usize {
    return if (width + 1 > text) (width + 1 - text) / 2 else 0;
}
/// Eigenvalue-table numbers, as in PROC PRINCOMP's listing.
fn fixed(a: A, value: f64, width: usize, decimals: usize) ![]const u8 {
    var d = decimals;
    while (true) : (d -= 1) {
        var text: []const u8 = try std.fmt.allocPrint(a, "{d:.[1]}", .{ value, d });
        if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) text = text[1..];
        if (text.len > width and std.mem.startsWith(u8, text, "-0.")) text = try std.fmt.allocPrint(a, "-{s}", .{text[2..]});
        if (text.len <= width or d == 0) return text;
    }
}
fn num(a: A, value: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ value, decimals });
}

/// One-row tables (variance explained, communalities, squared multiple
/// correlations): width 10 then 16 per column; every value of the row shares
/// the decimals that put the largest in ten characters ("0.98782629",
/// " 1.0000000", " 2.8733136", " 0.2148369").
fn rowValues(a: A, out: *Out, values: []const f64) !void {
    var big: f64 = 0;
    for (values) |v| big = @max(big, @abs(v));
    const digits: usize = if (big < 1) 0 else @as(usize, @intFromFloat(@floor(@log10(big)))) + 1;
    for (values, 0..) |v, k| try right(a, out, try num(a, v, 8 - digits), if (k == 0) 10 else 16);
    try out.appendSlice(a, "\n");
}
fn rowHeader(a: A, out: *Out, labels: []const []const u8) !void {
    for (labels, 0..) |l, k| try right(a, out, l, if (k == 0) 10 else 16);
    try out.appendSlice(a, "\n\n");
}
fn matrix(a: A, out: *Out, names: []const []const u8, label: usize, heads: []const []const u8, values: []const f64, heading: []const u8) !void {
    const nc = heads.len;
    try title(a, out, heading, labelledIndent(label + 16 * nc, heading.len));
    try pad(a, out, label);
    for (heads) |h| try right(a, out, h, 16);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |n, j| {
        try left(a, out, n, label);
        for (0..nc) |k| try right(a, out, try num(a, values[j * nc + k], 5), 16);
        try out.appendSlice(a, "\n");
    }
}

const Page = struct { names: []const []const u8, label: usize, factors: []const []const u8 };

fn inputPage(a: A, out: *Out, s: Spec, pg: Page, read: usize, sel: pc.Selection, m: pc.Moments, subtitle: bool) !void {
    const p = pg.names.len;
    try out.appendSlice(a, "\nThe FACTOR Procedure\n");
    if (subtitle) try out.appendSlice(a, "Initial Factor Method: Principal Components\n");
    try out.appendSlice(a, "\n");
    const n: usize = @intFromFloat(sel.n);
    const rows = [_][2][]const u8{
        .{ "Input Data Type", "Raw Data" },
        .{ "Number of Records Read", try std.fmt.allocPrint(a, "{d}", .{read}) },
        .{ "Number of Records Used", try std.fmt.allocPrint(a, "{d}", .{sel.rows.len}) },
        .{ "N for Significance Tests", try std.fmt.allocPrint(a, "{d}", .{n}) },
    };
    for (rows) |r| {
        try left(a, out, r[0], 32);
        try right(a, out, r[1], 8);
        try out.appendSlice(a, "\n");
    }
    if (s.simple) {
        try title(a, out, try std.fmt.allocPrint(a, "Means and Standard Deviations from {d} Observations", .{n}), 0);
        const lw = @max(8, pg.label);
        try left(a, out, "Variable", lw);
        try right(a, out, "Mean", 14);
        try right(a, out, "Std Dev", 14);
        try out.appendSlice(a, "\n\n");
        for (pg.names, 0..) |name, j| {
            try left(a, out, name, lw);
            try right(a, out, try num(a, m.mean[j], 3), 14);
            try right(a, out, try num(a, m.std[j], 4), 14);
            try out.appendSlice(a, "\n");
        }
    }
    if (s.corr) try matrix(a, out, pg.names, pg.label, pg.names, m.corr, "Correlations");
    _ = p;
}

fn factorPage(a: A, out: *Out, pg: Page, e: pc.Eigen, r: Retained, sol: Solution) !void {
    const p = pg.names.len;
    const nf = r.count;
    try out.appendSlice(a, "\nThe FACTOR Procedure\nInitial Factor Method: Principal Components\n\nPrior Communality Estimates: ONE    \n\n");
    // With PRIORS=ONE the total is the number of variables and the average 1.
    try title(a, out, try std.fmt.allocPrint(a, "Eigenvalues of the Correlation Matrix: Total = {d}  Average = 1", .{p}), 0);
    try out.appendSlice(a, "        Eigenvalue    Difference    Proportion    Cumulative\n\n");
    var total: f64 = 0;
    for (e.values) |v| total += v;
    var cumulative: f64 = 0;
    for (e.values, 0..) |v, k| {
        cumulative += v;
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 4);
        try right(a, out, try fixed(a, v, 10, 8), 14);
        try right(a, out, if (k + 1 < p) try fixed(a, v - e.values[k + 1], 10, 8) else "", 14);
        try right(a, out, try fixed(a, v / total, 6, 4), 14);
        try right(a, out, try fixed(a, cumulative / total, 6, 4), 14);
        try out.appendSlice(a, "\n");
    }
    try out.print(a, "\n{d} {s} will be retained by the {s} criterion.\n\n", .{ nf, if (nf == 1) "factor" else "factors", r.criterion });

    try matrix(a, out, pg.names, pg.label, pg.factors, sol.pattern, "Factor Pattern");

    const heading = "Variance Explained by Each Factor";
    try title(a, out, heading, rowIndent(10 + 16 * (nf - 1), heading.len));
    try rowHeader(a, out, pg.factors);
    try rowValues(a, out, e.values[0..nf]);

    var comm_total: f64 = 0;
    for (sol.communality) |c| comm_total += c;
    const comm = try std.fmt.allocPrint(a, "Final Communality Estimates: Total = {d:.6}", .{comm_total});
    try title(a, out, comm, rowIndent(10 + 16 * (p - 1), comm.len));
    try rowHeader(a, out, pg.names);
    try rowValues(a, out, sol.communality);
}

fn scorePage(a: A, out: *Out, pg: Page, sol: Solution) !void {
    const nf = pg.factors.len;
    try out.appendSlice(a, "\nThe FACTOR Procedure\nInitial Factor Method: Principal Components\n\nScoring Coefficients Estimated by Regression\n\n");
    const heading = "Squared Multiple Correlations of the Variables with Each Factor";
    try title(a, out, heading, rowIndent(10 + 16 * (nf - 1), heading.len));
    try rowHeader(a, out, pg.factors);
    // diag(P' R^-1 P) = lambda_k / lambda_k = 1 for principal components.
    const smc = try a.alloc(f64, nf);
    @memset(smc, 1);
    try rowValues(a, out, smc);
    try matrix(a, out, pg.names, pg.label, pg.factors, sol.scoring, "Standardized Scoring Coefficients");
}

/// BY line, left-aligned. ponytail: opensas ignores OPTIONS NOCENTER and lays
/// every FACTOR table out flush left, as the NOCENTER reference listing does;
/// the shared helper centers the BY line, so it is re-aligned here to match
/// that listing ("_oracle_by=1" at column 1).
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

/// The OUTSTAT= data set (STAT-DATASET-001; S154 pp.10880-10881, TYPE=FACTOR
/// p.10890): `_TYPE_` / `_NAME_` (character, length 8, labelled as SAS labels
/// them) then one numeric column per analysis variable. Rows, as SAS 9.4 writes
/// them for METHOD=PRINCIPAL PRIORS=ONE with no rotation: MEAN, STD, N, one CORR
/// row per variable (_NAME_ = the row variable), COMMUNAL, PRIORS, EIGENVAL (all
/// p eigenvalues), one PATTERN row per retained factor (_NAME_ = FactorK).
pub fn outstatSet(a: A, member: []const u8, names: []const []const u8, m: pc.Moments, n: f64, e: pc.Eigen, sol: Solution, factors: []const []const u8) !*Dataset {
    const p = names.len;
    const nf = factors.len;
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, member);
    o.ds_type = "FACTOR";
    try o.columns.append(a, .{ .name = "_TYPE_", .type = .char, .len = 8, .label = "Type of Observation" });
    try o.columns.append(a, .{ .name = "_NAME_", .type = .char, .len = 8, .label = "Row Variable Name" });
    for (names) |nm| try o.columns.append(a, .{ .name = nm, .type = .num, .len = 8 });
    const Row = struct {
        fn add(al: A, ds: *Dataset, ty: []const u8, name: []const u8, vals: []const f64) !void {
            const cells = try al.alloc(Value, vals.len + 2);
            cells[0] = .{ .str = ty };
            cells[1] = .{ .str = name };
            for (vals, 0..) |v, k| cells[k + 2] = .{ .num = v };
            try ds.appendRow(cells);
        }
    };
    const buf = try a.alloc(f64, p);
    try Row.add(a, o, "MEAN", "", m.mean);
    try Row.add(a, o, "STD", "", m.std);
    @memset(buf, n);
    try Row.add(a, o, "N", "", buf);
    for (names, 0..) |nm, j| try Row.add(a, o, "CORR", nm, m.corr[j * p .. (j + 1) * p]);
    try Row.add(a, o, "COMMUNAL", "", sol.communality);
    @memset(buf, 1); // PRIORS=ONE
    try Row.add(a, o, "PRIORS", "", buf);
    try Row.add(a, o, "EIGENVAL", "", e.values[0..p]);
    for (factors, 0..) |f, k| {
        const row = try a.alloc(f64, p);
        for (row, 0..) |*v, j| v.* = sol.pattern[j * nf + k];
        try Row.add(a, o, "PATTERN", f, row);
    }
    return o;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;

    if (s.freq != null or s.weight != null) return gap(cx.diags, l0, "PROC FACTOR: the FREQ/WEIGHT analysis and its listing are not verified against SAS output", .{});
    if (s.mineigen) |v| if (v < 0) return cx.diags.fail(error.ParseError, l0, "PROC FACTOR: negative values of MINEIGEN= are not allowed", .{});
    if (!s.noprint) if (cx.graphics) |g| if (g.enabled == true) return gap(cx.diags, l0, "PROC FACTOR: ODS GRAPHICS output is not implemented", .{});
    if (cx.capture) |c| for ([_][]const u8{ "StdScoreCoef", "FactorPattern", "Eigenvalues", "FinalCommun", "VarExplain", "Corr", "SimpleStats", "NObs" }) |table| {
        if (c.wants(table)) return gap(cx.diags, l0, "PROC FACTOR: ODS OUTPUT {s}= is not implemented", .{table});
    };

    const names = try a.alloc([]const u8, p);
    var label: usize = 0;
    for (s.vars, names) |ci, *n| {
        n.* = ds.columns.items[ci].name;
        label = @max(label, n.len);
        if (n.len > 15) return gap(cx.diags, l0, "PROC FACTOR: the listing layout for variable name {s} longer than 15 characters is not verified", .{n.*});
    }
    if (s.outstat != null) {
        // STAT-DATASET-001: the TYPE=FACTOR layout written here is the SAS 9.4
        // reference for METHOD=PRINCIPAL PRIORS=ONE without rotation; the rows a
        // SCORE request or BY groups add are not verified (STAT-FACTOR-008).
        if (s.score) return gap(cx.diags, l0, "PROC FACTOR: OUTSTAT= together with SCORE is not implemented (STAT-FACTOR-008)", .{});
        if (s.by_cols.len > 0) return gap(cx.diags, l0, "PROC FACTOR: OUTSTAT= with a BY statement is not implemented (STAT-FACTOR-008)", .{});
        for (names) |n| if (n.len > 8) return gap(cx.diags, l0, "PROC FACTOR: OUTSTAT= with variable name {s} longer than 8 characters (_NAME_ length) is not verified (STAT-FACTOR-008)", .{n});
    }
    const ks = kernelSpec(s);
    var body: Out = .empty;
    for (groups, 0..) |group, gi| {
        const sel = try pc.select(a, ks, group.rows);
        if (sel.n < 2) return gap(cx.diags, l0, "PROC FACTOR: an analysis with fewer than two usable observations is not verified against SAS output", .{});
        if (sel.n <= @as(f64, @floatFromInt(p))) return gap(cx.diags, l0, "PROC FACTOR: a singular correlation matrix (no more observations than variables) is not verified against SAS output", .{});
        const m = (try pc.moments(a, ks, group.rows, sel)) orelse return gap(cx.diags, l0, "PROC FACTOR: a variable with zero variance is not verified against SAS output", .{});
        for (m.mean, m.std) |mu, sd| if (!(@abs(mu) < 1e7 and sd < 1e7)) return gap(cx.diags, l0, "PROC FACTOR: the SIMPLE number layout for magnitudes of at least 1E7 is not verified", .{});
        const e = try pc.eigenSym(a, m.corr, p);
        const r = retained(s, e.values) orelse return gap(cx.diags, l0, "PROC FACTOR: this combination of NFACTORS= and MINEIGEN= (or NFACTORS= above the number of variables) is not verified (STAT-FACTOR-004)", .{});
        if (r.count == 0) return gap(cx.diags, l0, "PROC FACTOR: an analysis that retains no factors is not verified (STAT-FACTOR-004)", .{});
        const factors = try a.alloc([]const u8, r.count);
        for (factors, 0..) |*f, k| f.* = try std.fmt.allocPrint(a, "Factor{d}", .{k + 1});
        const ls: usize = if (io.global_linesize == 0) 132 else io.global_linesize;
        const widest = label + 16 * @max(p, r.count);
        if (widest > ls) return gap(cx.diags, l0, "PROC FACTOR: tables wider than the line size ({d} > {d}) are not implemented", .{ widest, ls });
        const sol = try solve(a, e, p, r.count);
        try cx.diags.note(0, "{d} {s} will be retained by the {s} criterion.", .{ r.count, if (r.count == 1) "factor" else "factors", r.criterion });
        if (s.outstat) |member| {
            if (r.count > 9) return gap(cx.diags, l0, "PROC FACTOR: OUTSTAT= with more than nine factors (_NAME_ length) is not verified (STAT-FACTOR-008)", .{});
            const o = try outstatSet(a, member, names, m, sel.n, e, sol, factors);
            try cx.lib.put(member, o);
            const upper = try std.ascii.allocUpperString(a, member);
            const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
            try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
        }
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
        if (s.noprint) continue;
        const pg: Page = .{ .names = names, .label = label, .factors = factors };
        if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
        // Verified: from the second BY group on, the first page carries the
        // previous page's "Initial Factor Method" subtitle.
        try inputPage(a, &body, s, pg, group.rows.len, sel, m, gi > 0);
        if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
        try factorPage(a, &body, pg, e, r, sol);
        if (s.score) {
            if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
            try scorePage(a, &body, pg, sol);
        }
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("factor_tests.zig");
}
