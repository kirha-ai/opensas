//! PROC CANCORR (SAS/STAT 15.4 ch.34, STAT-CANCORR-001): the PROC statement
//! options DATA= / VPREFIX= / WPREFIX= / VNAME= / WNAME= / SHORT / NOPRINT /
//! SINGULAR= (with their documented aliases), the VAR / WITH / BY / FREQ /
//! WEIGHT roles and the missing-value rule (pp.2126-2134), and the default
//! listing: canonical correlations with Lawley's adjusted values, standard
//! errors, Rao's F tests, the four multivariate statistics, raw and
//! standardized canonical coefficients and the canonical structure. Every
//! other documented option or statement is a loud D-009 gap.
//!
//! Computation: R is the (FREQ*WEIGHT) correlation matrix of the VAR (X, p)
//! and WITH (Y, q) variables. The eigen-decomposition of
//! Rxx^-1/2 Rxy Ryy^-1 Ryx Rxx^-1/2 (PROC PRINCOMP's Jacobi kernel, read-only)
//! gives the squared canonical correlations and, through Rxx^-1/2, the
//! standardized VAR coefficients a (unit variance); b = Ryy^-1 Ryx a / r.
//! Raw coefficients divide by the standard deviations (divisor sum(FREQ)-1,
//! p.2132: WEIGHT does not alter the degrees of freedom).
//! The test statistics use df = sum(FREQ) - 1 (pp.2132-2133); the formulas
//! are the chapter-5 multivariate tests, symmetric in p and q here.
//! Boundaries (SAS 9.4 verified listings): a canonical correlation of one
//! (Infty eigenvalue, missing traces), a zero correlation for one VAR and one
//! WITH variable, linearly dependent or constant variables (dropped by an
//! incremental Cholesky with SINGULAR=, tests use the set's rank, NOTE), no
//! more observations than variables (WARNING + NOTE, no multivariate table),
//! fewer than two observations (ERROR, per BY group). Coefficient pages whose
//! SAS signs or rounding noise are not reproduced stay loud gaps (SHORT works).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fns = @import("../functions.zig");
const format = @import("../format.zig");
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
    vprefix: []const u8 = "V",
    wprefix: []const u8 = "W",
    vname: []const u8 = "VAR Variables",
    wname: []const u8 = "WITH Variables",
    short: bool = false,
    noprint: bool = false,
    singular: f64 = 1e-8,
    vars: []const usize = &.{},
    with: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC CANCORR: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}

/// Table 34.1 plus the documented aliases (pp.2126-2131).
fn canonical(word: []const u8) ?[]const u8 {
    const aliases = [_][2][]const u8{
        .{ "c", "corr" },            .{ "red", "redundancy" }, .{ "s", "simple" },   .{ "sing", "singular" },
        .{ "vn", "vname" },          .{ "wn", "wname" },       .{ "vp", "vprefix" }, .{ "wp", "wprefix" },
        .{ "pprefix", "parprefix" }, .{ "wreg", "vdep" },      .{ "vreg", "wdep" },
    };
    for (aliases) |p| if (eq(word, p[0])) return p[1];
    const options = [_][]const u8{
        "all",        "b",     "clb",     "corr",   "corrb",    "data",      "edf",    "int",     "mstat",
        "ncan",       "noint", "noprint", "out",    "outstat",  "parprefix", "pcorr",  "probt",   "rdf",
        "redundancy", "seb",   "short",   "simple", "singular", "smc",       "spcorr", "sqpcorr", "sqspcorr",
        "stb",        "t",     "vdep",    "vname",  "vprefix",  "wdep",      "wname",  "wprefix",
    };
    for (options) |o| if (eq(word, o)) return o;
    return null;
}

fn number(t: []const lex.Token, i: usize) ?f64 {
    if (!at(t, i, .number)) return null;
    return std.fmt.parseFloat(f64, t[i].text) catch null;
}

fn varList(cx: proc.ProcCtx, ds: *Dataset, body: []const lex.Token, what: []const u8, into: *std.ArrayList(usize)) diag.Error!void {
    const a = cx.arena;
    var j: usize = 0;
    while (j < body.len) {
        const l = body[j].line;
        const names = try lists.next(a, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC CANCORR: variable {s} in the {s} statement is not on the input data set", .{ n, what });
            // pp.2133: the VAR and WITH variables must be numeric.
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC CANCORR: variable {s} in the {s} statement must be numeric", .{ n, what });
            if (std.mem.indexOfScalar(usize, into.items, ci) != null) return proc.failGap(cx.diags, l, "PROC CANCORR: a variable listed twice in the {s} statement is not verified", .{what});
            try into.append(a, ci);
        }
    }
}

fn oneVar(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, i: usize, end: usize, what: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CANCORR: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, what });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC CANCORR: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, what });
    return ci;
}

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
        const o = canonical(t[i].text) orelse return invalid(cx, t, i);
        if ((try seen.getOrPut(a, o)).found_existing) return gap(cx.diags, t[i].line, "PROC CANCORR: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(o, "data") and valued) {
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            var j = first + 1;
            name = t[first].text;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[first].text, t[j + 1].text });
                qualified = first;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if ((eq(o, "vprefix") or eq(o, "wprefix")) and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            if (eq(o, "vprefix")) s.vprefix = t[i + 2].text else s.wprefix = t[i + 2].text;
            i += 3;
        } else if ((eq(o, "vname") or eq(o, "wname")) and valued) {
            // p.2131: a character constant in single or double quotes.
            if (!at(t, i + 2, .string)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CANCORR: {s}= requires a quoted character constant", .{t[i].text});
            if (eq(o, "vname")) s.vname = t[i + 2].text else s.wname = t[i + 2].text;
            i += 3;
        } else if (eq(o, "singular") and valued) {
            // p.2130: 0 < p < 1.
            const v = number(t, i + 2) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CANCORR: SINGULAR= must be a number between 0 and 1", .{});
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CANCORR: SINGULAR= must be a number between 0 and 1", .{});
            s.singular = v;
            i += 3;
        } else if (eq(o, "short") and !valued) {
            s.short = true;
            i += 1;
        } else if (eq(o, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(o, "data") or eq(o, "vprefix") or eq(o, "wprefix") or eq(o, "vname") or eq(o, "wname") or eq(o, "singular") or eq(o, "short") or eq(o, "noprint")) {
            return invalid(cx, t, i + 1);
        } else {
            const owner: []const u8 = if (eq(o, "out") or eq(o, "outstat") or eq(o, "parprefix"))
                " (STAT-CANCORR-004)"
            else if (eq(o, "edf") or eq(o, "rdf") or eq(o, "noint") or eq(o, "mstat"))
                " (STAT-CANCORR-003)"
            else
                " (STAT-CANCORR-005)";
            return gap(cx.diags, t[i].line, "PROC CANCORR: the {s} option is not implemented{s}", .{ t[i].text, owner });
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC CANCORR: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    // p.2127: TYPE=CORR, COV, FACTOR, SSCP, UCORR or UCOV input is read by _TYPE_.
    if (ds.indexOf("_type_") != null) return gap(cx.diags, line(t, 0), "PROC CANCORR: input data sets with a _TYPE_ variable (TYPE=CORR, COV, SSCP, ...) are not implemented", .{});

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var with: std.ArrayList(usize) = .empty;
    var var_seen = false;
    var with_seen = false;
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
            // SAS 9.4: repeated VAR (and WITH) statements accumulate.
            var_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            try varList(cx, ds, t[i + 1 .. end], "VAR", &vars);
        } else if (eq(word, "with")) {
            with_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            try varList(cx, ds, t[i + 1 .. end], "WITH", &with);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC CANCORR: more than one FREQ statement is not verified", .{});
            s.freq = try oneVar(cx, ds, t, i, end, "FREQ");
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC CANCORR: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneVar(cx, ds, t, i, end, "WEIGHT");
        } else if (eq(word, "partial")) {
            return gap(cx.diags, t[i].line, "PROC CANCORR: the PARTIAL statement is not implemented (STAT-CANCORR-003)", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (eq(word, "format") or eq(word, "label") or eq(word, "attrib")) {
            return gap(cx.diags, t[i].line, "PROC CANCORR: a {s} statement inside the step is not implemented", .{word});
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // p.2126: the WITH statement is required.
    if (!with_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CANCORR: a WITH statement is required", .{});
    // p.2132: if you specify more than one BY statement, only the last is used.
    if (bys.lists.items.len > 1) bys.lists.items = bys.lists.items[bys.lists.items.len - 1 ..];
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (!var_seen) {
        // p.2133: all numeric variables not mentioned in other statements.
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num) continue;
            if (std.mem.indexOfScalar(usize, with.items, ci) != null or std.mem.indexOfScalar(usize, cols, ci) != null) continue;
            if (s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
        if (vars.items.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CANCORR: no numeric variables remain for the VAR set", .{});
    }
    // SAS 9.4: a variable in both sets is analysed (a canonical correlation
    // of one, Infty eigenvalue).
    for ([_]?usize{ s.freq, s.weight }) |role| if (role) |ci| {
        if (std.mem.indexOfScalar(usize, vars.items, ci) != null or std.mem.indexOfScalar(usize, with.items, ci) != null)
            return gap(cx.diags, line(t, 0), "PROC CANCORR: variable {s} used both as an analysis variable and as FREQ or WEIGHT is not verified", .{ds.columns.items[ci].name});
    };
    s.vars = vars.items;
    s.with = with.items;
    return s;
}

/// The canonical analysis of one group.
pub const Result = struct {
    /// Ranks of the VAR and WITH sets (the test statistics use these).
    p: usize,
    q: usize,
    /// sum(FREQ) - 1.
    df: f64,
    /// Canonical correlations, descending, min(p, q) of them.
    r: []const f64,
    /// Standardized coefficients, row-major (all VAR variables)*s and
    /// (all WITH variables)*s; a linearly dependent variable has zeros.
    a: []const f64,
    b: []const f64,
    sdx: []const f64,
    sdy: []const f64,
    /// Correlation matrix of all (X, Y) variables.
    corr: []const f64,
    /// A set had a linearly dependent variable (displayed NOTE).
    x_deficient: bool = false,
    y_deficient: bool = false,
    /// Constant variables (indices into the p+q columns), dropped like a
    /// linearly dependent one (SAS 9.4 WARNING).
    constant: []const usize = &.{},
};

pub const Failure = error{ Singular, ZeroCorrelation, TooFew, OutOfMemory };

/// Variables of `set` (indices into the k x k matrix `corr`) kept in order:
/// one whose R square on the earlier kept variables is at least 1 - singular
/// is linearly dependent and dropped (incremental Cholesky of the
/// correlation matrix).
fn independent(a: A, corr: []const f64, k: usize, set: []const usize, constant: []const usize, singular: f64) ![]usize {
    var kept: std.ArrayList(usize) = .empty;
    const l = try a.alloc(f64, set.len * set.len);
    @memset(l, 0);
    const z = try a.alloc(f64, set.len);
    for (set) |j| {
        if (std.mem.indexOfScalar(usize, constant, j) != null) continue;
        const m = kept.items.len;
        var ss: f64 = 0;
        for (0..m) |r| {
            var v = corr[kept.items[r] * k + j];
            for (0..r) |t| v -= l[r * set.len + t] * z[t];
            z[r] = v / l[r * set.len + r];
            ss += z[r] * z[r];
        }
        const d = 1 - ss;
        if (!(d > singular)) continue;
        for (0..m) |t| l[m * set.len + t] = z[t];
        l[m * set.len + m] = @sqrt(d);
        try kept.append(a, j);
    }
    return kept.items;
}

fn pick(a: A, m: []const f64, k: usize, rows: []const usize, cols: []const usize) ![]f64 {
    const o = try a.alloc(f64, rows.len * cols.len);
    for (rows, 0..) |r, i| for (cols, 0..) |c, j| {
        o[i * cols.len + j] = m[r * k + c];
    };
    return o;
}

/// ponytail: an eigenvector entry this small relative to the column's
/// largest is rounding noise of an exact zero (SAS 9.4 prints 0 for a
/// variable that does not enter a canonical correlation of one).
fn snap(v: []f64) void {
    var mx: f64 = 0;
    for (v) |x| mx = @max(mx, @abs(x));
    for (v) |*x| if (@abs(x.*) < 1e-10 * mx) {
        x.* = 0;
    };
}

/// `x` holds n rows of p+q values, `f` the frequencies and `w` the weights.
pub fn analyze(a: A, x: []const f64, f: []const f64, w: []const f64, p_all: usize, q_all: usize, singular: f64) Failure!Result {
    const k = p_all + q_all;
    const nrows = f.len;
    var n: f64 = 0;
    var sw: f64 = 0;
    for (f, w) |fi, wi| {
        n += fi;
        sw += fi * wi;
    }
    if (n - 1 <= 0) return error.TooFew;
    const mean = try a.alloc(f64, k);
    @memset(mean, 0);
    for (0..nrows) |r| for (0..k) |j| {
        mean[j] += f[r] * w[r] * x[r * k + j] / sw;
    };
    const css = try a.alloc(f64, k * k);
    @memset(css, 0);
    for (0..nrows) |r| for (0..k) |i| for (0..k) |j| {
        css[i * k + j] += f[r] * w[r] * (x[r * k + i] - mean[i]) * (x[r * k + j] - mean[j]);
    };
    const corr = try a.alloc(f64, k * k);
    const sd = try a.alloc(f64, k);
    var constant: std.ArrayList(usize) = .empty;
    for (0..k) |i| {
        if (!(css[i * k + i] > 0)) try constant.append(a, i);
        sd[i] = @sqrt(css[i * k + i] / (n - 1));
    }
    for (0..k) |i| for (0..k) |j| {
        const zero = !(css[i * k + i] > 0) or !(css[j * k + j] > 0);
        corr[i * k + j] = if (i == j) 1 else if (zero) 0 else css[i * k + j] / @sqrt(css[i * k + i] * css[j * k + j]);
    };
    const xs = try a.alloc(usize, p_all);
    for (xs, 0..) |*v, i| v.* = i;
    const ys = try a.alloc(usize, q_all);
    for (ys, 0..) |*v, i| v.* = p_all + i;
    // SAS 9.4: a linearly dependent variable gets zero coefficients and the
    // tests use the rank of its set (NOTE in the listing).
    const kx = try independent(a, corr, k, xs, constant.items, singular);
    const ky = try independent(a, corr, k, ys, constant.items, singular);
    const p = kx.len;
    const q = ky.len;
    if (p == 0 or q == 0) return error.Singular;
    const rxx = try pick(a, corr, k, kx, kx);
    const ryy = try pick(a, corr, k, ky, ky);
    const rxy = try pick(a, corr, k, kx, ky);
    const ryx = try pick(a, corr, k, ky, kx);
    const rxx_h = try powSym(a, rxx, p, -0.5, singular);
    const ryy_i = try powSym(a, ryy, q, -1, singular);
    // M = Rxx^-1/2 Rxy Ryy^-1 Ryx Rxx^-1/2.
    const m = try mul(a, try mul(a, try mul(a, try mul(a, rxx_h, rxy, p, p, q), ryy_i, p, q, q), ryx, p, q, p), rxx_h, p, p, p);
    for (0..p) |i| for (0..i) |j| {
        const v = (m[i * p + j] + m[j * p + i]) / 2;
        m[i * p + j] = v;
        m[j * p + i] = v;
    };
    const e = try pc.eigenSym(a, m, p);
    const s = @min(p, q);
    const r = try a.alloc(f64, s);
    const ca = try a.alloc(f64, p_all * s);
    const cb = try a.alloc(f64, q_all * s);
    @memset(ca, 0);
    @memset(cb, 0);
    const u = try a.alloc(f64, p);
    for (0..s) |c| {
        var rsq = e.values[c];
        // SAS 9.4 displays a canonical correlation of one (Infty eigenvalue).
        if (rsq >= 1 - 1e-12) rsq = 1;
        for (0..p) |i| u[i] = e.vectors[i * p + c];
        const av = try mul(a, rxx_h, u, p, p, 1);
        var bv: []f64 = undefined;
        if (!(rsq > 1e-12)) {
            // SAS 9.4 (one VAR and one WITH variable): r = 0 with both
            // standardized coefficients 1; otherwise b is undetermined.
            if (p != 1 or q != 1) return error.ZeroCorrelation;
            rsq = 0;
            bv = try a.alloc(f64, 1);
            bv[0] = 1;
            r[c] = 0;
        } else {
            r[c] = @sqrt(rsq);
            bv = try mul(a, try mul(a, ryy_i, ryx, q, q, p), av, q, p, 1);
            for (bv) |*v| v.* /= r[c];
        }
        snap(av);
        snap(bv);
        // ponytail: orientation = nonnegative sum of the standardized
        // coefficients of the larger set (VAR on a tie); this reproduces every
        // SAS 9.4 listing checked (3x3, 2x3, 3x2 and 5x2 cases).
        var sum: f64 = 0;
        if (q > p) {
            for (bv) |v| sum += v;
        } else for (av) |v| sum += v;
        const sign: f64 = if (sum < 0) -1 else 1;
        for (kx, 0..) |ix, i| ca[ix * s + c] = sign * av[i];
        for (ky, 0..) |iy, i| cb[(iy - p_all) * s + c] = sign * bv[i];
    }
    return .{ .p = p, .q = q, .df = n - 1, .r = r, .a = ca, .b = cb, .sdx = sd[0..p_all], .sdy = sd[p_all..], .corr = corr, .x_deficient = p < p_all, .y_deficient = q < q_all, .constant = constant.items };
}

fn sub(a: A, m: []const f64, k: usize, r0: usize, c0: usize, nr: usize, nc: usize) ![]f64 {
    const o = try a.alloc(f64, nr * nc);
    for (0..nr) |i| for (0..nc) |j| {
        o[i * nc + j] = m[(r0 + i) * k + c0 + j];
    };
    return o;
}
fn mul(a: A, x: []const f64, y: []const f64, n: usize, m: usize, l: usize) ![]f64 {
    const o = try a.alloc(f64, n * l);
    for (0..n) |i| for (0..l) |j| {
        var acc: f64 = 0;
        for (0..m) |t| acc += x[i * m + t] * y[t * l + j];
        o[i * l + j] = acc;
    };
    return o;
}
/// M^power of a symmetric positive definite correlation matrix.
fn powSym(a: A, m: []const f64, n: usize, power: f64, singular: f64) Failure![]f64 {
    const e = try pc.eigenSym(a, m, n);
    if (!(e.values[n - 1] > singular)) return error.Singular;
    const o = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        var acc: f64 = 0;
        for (0..n) |t| acc += e.vectors[i * n + t] * std.math.pow(f64, e.values[t], power) * e.vectors[j * n + t];
        o[i * n + j] = acc;
    };
    return o;
}

/// Lawley's (1959) first-order bias correction (p.2138); null where SAS
/// displays a missing value. ponytail: "might not be computable" is taken as
/// nearly equal or near-zero correlations, an adjusted value above the raw
/// correlation, or above the previous adjusted value; verified against SAS
/// 9.4 for the chapter's Jobs data and invented 2x3 / 3x2 / 5x2 tables.
pub fn adjusted(a: A, res: Result) ![]?f64 {
    const s = res.r.len;
    const o = try a.alloc(?f64, s);
    const pq: f64 = @floatFromInt(res.p + res.q);
    var prev: ?f64 = null;
    for (res.r, 0..) |ri, i| {
        o[i] = null;
        const r2 = ri * ri;
        var ok = ri > 1e-8;
        var sum: f64 = 0;
        for (res.r, 0..) |rj, j| if (j != i) {
            const d = r2 - rj * rj;
            if (@abs(d) < 1e-8) ok = false else sum += rj * rj / d;
        };
        if (ok) {
            const t = pq - 2 - r2 + 2 * (1 - r2) * sum;
            const v = ri - (1 - r2) / (2 * res.df * ri) * t;
            if (v <= ri and (prev == null or v <= prev.?)) o[i] = v;
        }
        if (o[i]) |v| prev = v;
    }
    return o;
}

pub const FTest = struct { value: f64, f: f64, df1: f64, df2: f64, prob: f64 };

fn fprob(f: f64, d1: f64, d2: f64) f64 {
    if (!(d2 > 0)) return nan;
    if (std.math.isInf(f)) return 0;
    if (!(f > 0)) return 1;
    return fns.betaI(d2 / (d2 + d1 * f), d2 / 2, d1 / 2);
}
fn ftest(value: f64, f: f64, d1: f64, d2: f64) FTest {
    return .{ .value = value, .f = f, .df1 = d1, .df2 = d2, .prob = fprob(f, d1, d2) };
}

/// Rao's F for the likelihood ratio of canonical correlations k.. (p.2138).
pub fn rao(res: Result, k: usize) FTest {
    var lr: f64 = 1;
    for (res.r[k..]) |x| lr *= 1 - x * x;
    const pf: f64 = @floatFromInt(res.p);
    const qf: f64 = @floatFromInt(res.q);
    const pk = pf - @as(f64, @floatFromInt(k));
    const qk = qf - @as(f64, @floatFromInt(k));
    const t = if (pk * pk + qk * qk - 5 > 0) @sqrt((pk * pk * qk * qk - 4) / (pk * pk + qk * qk - 5)) else 1;
    const w = res.df - (pf + qf + 1) / 2;
    const d1 = pk * qk;
    const d2 = w * t - pk * qk / 2 + 1;
    const power = std.math.pow(f64, lr, 1 / t);
    // SAS 9.4: zero denominator degrees of freedom leave F missing.
    const f = if (!(d2 > 0)) nan else if (power == 0) std.math.inf(f64) else (1 - power) / power * d2 / d1;
    return ftest(lr, f, d1, d2);
}

pub const Multivariate = struct { s: usize, m: f64, n: f64, tests: [4]FTest };

pub fn multivariate(res: Result) Multivariate {
    const pf: f64 = @floatFromInt(res.p);
    const qf: f64 = @floatFromInt(res.q);
    const s = res.r.len;
    const sf: f64 = @floatFromInt(s);
    const m = (@abs(pf - qf) - 1) / 2;
    const n = (res.df - pf - qf - 1) / 2;
    var pillai: f64 = 0;
    var hotelling: f64 = 0;
    for (res.r) |x| {
        pillai += x * x;
        hotelling += if (x == 1) std.math.inf(f64) else x * x / (1 - x * x);
    }
    const roy = if (res.r[0] == 1) std.math.inf(f64) else res.r[0] * res.r[0] / (1 - res.r[0] * res.r[0]);
    var tests: [4]FTest = undefined;
    tests[0] = rao(res, 0);
    const rd1 = @max(pf, qf);
    const rd2 = res.df - rd1;
    tests[3] = ftest(roy, roy * rd2 / rd1, rd1, rd2);
    if (s == 1) {
        tests[1] = ftest(pillai, tests[3].f, rd1, rd2);
        tests[2] = ftest(hotelling, tests[3].f, rd1, rd2);
    } else {
        const pd1 = sf * (2 * m + sf + 1);
        const pd2 = sf * (2 * n + sf + 1);
        tests[1] = ftest(pillai, (pd2 / pd1) * pillai / (sf - pillai), pd1, pd2);
        if (n > 0) {
            const den = 2 * (2 * n + 1) * (n - 1);
            const recip = den / ((pf + 2 * n) * (qf + 2 * n) - den);
            const hd2 = 4 + (pf * qf + 2) * recip;
            const c = (2 + (pf * qf + 2) * recip) / (2 * n);
            tests[2] = ftest(hotelling, (hotelling / c) * hd2 / (pf * qf), pf * qf, hd2);
        } else {
            const hd1 = sf * (2 * m + sf + 1);
            const hd2 = 2 * (sf * n + 1);
            tests[2] = ftest(hotelling, hd2 * hotelling / (sf * hd1), hd1, hd2);
        }
    }
    return .{ .s = s, .m = m, .n = n, .tests = tests };
}

// ---------------------------------------------------------------- listing

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
fn fixed(a: A, value: f64, decimals: usize) ![]const u8 {
    var text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ value, decimals });
    if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) text = text[1..];
    return text;
}
fn best(a: A, value: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}
fn prob(a: A, value: f64) ![]const u8 {
    if (value < 0.0001) return "<.0001";
    return fixed(a, value, 4);
}
/// SAS 9.4: an infinite statistic prints Infty; a missing one prints a
/// dot at the decimal-point position of the column.
fn num(a: A, out: *Out, value: f64, decimals: usize, width: usize) !void {
    if (std.math.isInf(value)) return right(a, out, "Infty", width);
    if (std.math.isNan(value)) {
        try pad(a, out, width - decimals - 1);
        try out.append(a, '.');
        return pad(a, out, decimals);
    }
    try right(a, out, try fixed(a, value, decimals), width);
}
fn probCol(a: A, out: *Out, value: f64, width: usize) !void {
    if (std.math.isNan(value)) return num(a, out, value, 4, width);
    try right(a, out, try prob(a, value), width);
}
const nan = std.math.nan(f64);

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (width > text.len) try pad(a, out, (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

const header =
    \\                                                                                                                 Test of H0: The canonical correlations in the
    \\                                                                          Eigenvalues of Inv(E)*H                  current row and all that follow are zero
    \\                          Adjusted  Approximate      Squared                = CanRsq/(1-CanRsq)
    \\            Canonical    Canonical     Standard    Canonical                                                  Likelihood  Approximate
    \\          Correlation  Correlation        Error  Correlation  Eigenvalue  Difference  Proportion  Cumulative       Ratio      F Value  Num DF  Den DF  Pr > F
    \\
;

fn canCorrTable(a: A, out: *Out, res: Result) !void {
    const s = res.r.len;
    const adj = try adjusted(a, res);
    const ev = try a.alloc(f64, s);
    // SAS 9.4: a canonical correlation of one has an Infty eigenvalue, a
    // missing proportion, and the finite eigenvalues share the proportions.
    var total: f64 = 0;
    for (res.r, ev) |x, *e| {
        e.* = if (x == 1) std.math.inf(f64) else x * x / (1 - x * x);
        if (x != 1) total += e.*;
    }
    try out.appendSlice(a, "\n" ++ header ++ "\n");
    var cum: f64 = 0;
    for (0..s) |k| {
        const x = res.r[k];
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 8);
        try right(a, out, try fixed(a, x, 6), 13);
        if (adj[k]) |v| try right(a, out, try fixed(a, v, 6), 13) else try out.appendSlice(a, "      .      ");
        try right(a, out, try fixed(a, (1 - x * x) / @sqrt(res.df), 6), 13);
        try right(a, out, try fixed(a, x * x, 6), 13);
        try num(a, out, ev[k], 4, 12);
        if (k + 1 < s) try num(a, out, ev[k] - ev[k + 1], 4, 12) else try pad(a, out, 12);
        if (std.math.isInf(ev[k])) {
            try num(a, out, nan, 4, 12);
            try num(a, out, nan, 4, 12);
        } else {
            // SAS 9.4: a zero canonical correlation alone has proportion 0.
            const share = if (total > 0) ev[k] / total else 0;
            cum += share;
            try num(a, out, share, 4, 12);
            try num(a, out, cum, 4, 12);
        }
        const ft = rao(res, k);
        try num(a, out, ft.value, 8, 12);
        try num(a, out, ft.f, 2, 13);
        try right(a, out, try best(a, ft.df1, "best6."), 8);
        try right(a, out, try best(a, ft.df2, "best6."), 8);
        try probCol(a, out, ft.prob, 8);
        try out.append(a, '\n');
    }
    if (s == 1) try out.appendSlice(a, "\nNOTE: The F statistic is exact.\n");
}

fn multivariateTable(a: A, out: *Out, res: Result) !void {
    const mv = multivariate(res);
    const width = 79;
    try out.appendSlice(a, "\n\n\n");
    try centered(a, out, if (mv.s == 1) "Multivariate Statistics and Exact F Statistics" else "Multivariate Statistics and F Approximations", width);
    try out.appendSlice(a, " \n");
    try centered(a, out, try std.fmt.allocPrint(a, "S={d}    M={d}    N={d}", .{ mv.s, mv.m, mv.n }), width);
    try out.appendSlice(a, " \nStatistic                        Value    F Value    Num DF    Den DF    Pr > F\n\n");
    for ([_][]const u8{ "Wilks' Lambda", "Pillai's Trace", "Hotelling-Lawley Trace", "Roy's Greatest Root" }, mv.tests) |label, ft| {
        // SAS 9.4: an infinite trace or root prints as missing value and F.
        const inf_value = std.math.isInf(ft.value);
        try left(a, out, label, 24);
        try num(a, out, if (inf_value) nan else ft.value, 8, 14);
        try num(a, out, if (inf_value) nan else ft.f, 2, 11);
        try right(a, out, try best(a, ft.df1, "best6."), 10);
        try right(a, out, try best(a, ft.df2, "best6."), 10);
        try probCol(a, out, ft.prob, 10);
        try out.append(a, '\n');
    }
    if (mv.s > 1) {
        try out.append(a, '\n');
        try centered(a, out, "NOTE: F Statistic for Roy's Greatest Root is an upper bound.", width);
        if (mv.s <= 2) try centered(a, out, "NOTE: F Statistic for Wilks' Lambda is exact.", width);
    }
}

const Rows = struct { names: []const []const u8, labels: ?[]const []const u8 };

/// Verified layout: name column = longest name (+ 6 when labels follow), then the label column
/// (longest label) when any row has a label, then one column per canonical
/// variable of width max(heading, value width) + 6.
fn matrix(a: A, out: *Out, title: []const u8, rows: Rows, heads: []const []const u8, values: []const f64, raw: bool) !void {
    var nw: usize = 0;
    for (rows.names) |n| nw = @max(nw, n.len);
    if (rows.labels != null) nw += 6;
    var lw: usize = 0;
    if (rows.labels) |ls| for (ls) |l| {
        lw = @max(lw, l.len);
    };
    const vw: usize = if (raw) 12 else 8;
    var width = nw + lw;
    const cw = try a.alloc(usize, heads.len);
    for (heads, cw) |h, *w| {
        w.* = @max(h.len, vw) + 6;
        width += w.*;
    }
    try out.append(a, '\n');
    try centered(a, out, title, width);
    try out.appendSlice(a, " \n");
    try pad(a, out, nw + lw);
    for (heads, cw) |h, w| try right(a, out, h, w);
    try out.appendSlice(a, "\n\n");
    const nc = heads.len;
    for (rows.names, 0..) |n, i| {
        try left(a, out, n, nw);
        if (rows.labels) |ls| try left(a, out, ls[i], lw);
        for (0..nc) |k| {
            const v = values[i * nc + k];
            try right(a, out, if (raw) try best(a, v, "best12.") else try fixed(a, v, 4), cw[k]);
        }
        try out.append(a, '\n');
    }
}

fn rowsOf(a: A, ds: *Dataset, cols: []const usize) !Rows {
    const names = try a.alloc([]const u8, cols.len);
    const labels = try a.alloc([]const u8, cols.len);
    var any = false;
    for (cols, names, labels) |ci, *n, *l| {
        const c = ds.columns.items[ci];
        n.* = c.name;
        l.* = c.label orelse "";
        if (c.label != null) any = true;
    }
    return .{ .names = names, .labels = if (any) labels else null };
}

fn headings(a: A, prefix: []const u8, s: usize) ![]const []const u8 {
    const o = try a.alloc([]const u8, s);
    for (o, 0..) |*h, k| h.* = try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, k + 1 });
    return o;
}

fn pageStart(a: A, cx: proc.ProcCtx, out: *Out, first: *bool, byline: []const u8, subtitle: []const u8) !void {
    if (!first.*) if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
    first.* = false;
    try out.append(a, '\n');
    if (byline.len > 0) try out.print(a, "{s}\n\n", .{byline});
    try out.print(a, "The CANCORR Procedure\n \n{s}\n", .{subtitle});
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    if (cx.capture) |c| for ([_][]const u8{ "CanCorr", "CanStructureVCan", "CanStructureWCan", "MultStat", "RawCanCoefV", "RawCanCoefW", "StdCanCoefV", "StdCanCoefW" }) |tbl| {
        if (c.wants(tbl)) return gap(cx.diags, l0, "PROC CANCORR: ODS OUTPUT {s}= is not implemented (STAT-CANCORR-005)", .{tbl});
    };
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;
    const q = s.with.len;
    const cols = try std.mem.concat(a, usize, &.{ s.vars, s.with });
    const xrows = try rowsOf(a, ds, s.vars);
    const yrows = try rowsOf(a, ds, s.with);
    var body: Out = .empty;
    var first = true;
    // SAS 9.4: an empty input data set is a NOTE, not an error.
    if (ds.rows.items.len == 0) return cx.diags.note(l0, "No observations in the input data set.", .{});
    for (groups) |group| {
        const logged = cx.diags.count();
        // p.2134: an observation with a missing value for any analysis
        // variable is omitted; pp.2132-2133: FREQ < 1 and WEIGHT <= 0 (or
        // missing) observations are not used, and only the integer part of
        // FREQ counts.
        var x: std.ArrayList(f64) = .empty;
        var f: std.ArrayList(f64) = .empty;
        var w: std.ArrayList(f64) = .empty;
        var omitted: usize = 0;
        rows: for (group.rows) |row| {
            for (cols) |ci| if (row[ci].isMissing()) {
                omitted += 1;
                continue :rows;
            };
            var fi: f64 = 1;
            if (s.freq) |ci| {
                if (row[ci].isMissing()) continue;
                fi = @floor(row[ci].num);
                if (fi < 1) continue;
            }
            var wi: f64 = 1;
            if (s.weight) |ci| {
                if (row[ci].isMissing() or !(row[ci].num > 0)) continue;
                wi = row[ci].num;
            }
            for (cols) |ci| try x.append(a, row[ci].num);
            try f.append(a, fi);
            try w.append(a, wi);
        }
        var nobs: f64 = 0;
        for (f.items) |v| nobs += v;
        const upper = try std.ascii.allocUpperString(a, ds.name);
        const prefix: []const u8 = if (std.mem.indexOfScalar(u8, upper, '.') == null) "WORK." else "";
        // SAS 9.4 (p.2134 rule): the omitted count is a WARNING.
        if (omitted > 0) try cx.diags.warn(l0, "{d} of {d} observations in data set {s}{s} omitted due to missing values.", .{ omitted, group.rows.len, prefix, upper });
        // SAS 9.4: fewer than two observations stop the step; in a BY group
        // the ERROR names the group and the other groups are analysed.
        if (nobs < 2) {
            if (s.by_cols.len == 0) return cx.diags.fail(error.ParseError, l0, "There must be at least 2 observations in data set {s}{s}.", .{ prefix, upper });
            try cx.diags.recoverableErr(l0, "There must be at least 2 observations in data set {s}{s}.", .{ prefix, upper });
            try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
            continue;
        }
        // SAS 9.4: with at most p+q observations a WARNING and NOTE replace
        // the multivariate table. ponytail: the canonical coefficients of such
        // a fit are not unique; only listings matching SAS 9.4 are accepted.
        const few = nobs <= @as(f64, @floatFromInt(p + q));
        if (few and !s.short) return gap(cx.diags, l0, "PROC CANCORR: canonical coefficients for {d} observations and {d} variables (not more observations than variables) are not verified; SHORT is supported", .{ nobs, p + q });
        // SAS 9.4: when every variable of one set is constant, each gets a
        // WARNING and the step stops with "A correlation matrix has zero rank."
        for ([_][]const usize{ s.vars, s.with }, 0..) |set, si| {
            var constant: usize = 0;
            for (set, 0..) |_, j| {
                const at_col = if (si == 0) j else p + j;
                var lo = std.math.inf(f64);
                var hi = -std.math.inf(f64);
                for (0..f.items.len) |r| {
                    lo = @min(lo, x.items[r * (p + q) + at_col]);
                    hi = @max(hi, x.items[r * (p + q) + at_col]);
                }
                if (lo == hi) constant += 1;
            }
            if (f.items.len > 0 and constant == set.len) {
                for (set) |ci| try cx.diags.warn(l0, "The variable {s} is constant.", .{ds.columns.items[ci].name});
                return cx.diags.fail(error.ParseError, l0, "A correlation matrix has zero rank.", .{});
            }
        }
        const res = analyze(a, x.items, f.items, w.items, p, q, s.singular) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx.diags, l0, "PROC CANCORR: a constant or linearly dependent VAR or WITH variable set is not verified", .{}),
            error.ZeroCorrelation => return gap(cx.diags, l0, "PROC CANCORR: a zero canonical correlation is not verified", .{}),
            error.TooFew => return gap(cx.diags, l0, "PROC CANCORR: fewer than two usable observations is not verified", .{}),
        };
        if (few) {
            try cx.diags.warn(l0, "The number of observations {d} is not greater than the number of variables {d}.", .{ nobs, p + q });
            try cx.diags.note(l0, "No multivariate tests performed due to insufficient degrees of freedom.", .{});
        }
        for (res.constant) |j| try cx.diags.warn(l0, "The variable {s} is constant.", .{ds.columns.items[cols[j]].name});
        // ponytail: the orientation rule does not reproduce SAS 9.4's signs for
        // a rank-deficient set (checked on a 3x2 case); only SHORT is accepted.
        if ((res.x_deficient or res.y_deficient) and !s.short) return gap(cx.diags, l0, "PROC CANCORR: canonical coefficients for a linearly dependent VAR or WITH variable set are not verified; SHORT is supported", .{});
        // SAS 9.4 wording: one deficient set keeping min(p, q) canonical
        // variables, or both sets deficient with fewer; other mixes unverified.
        const reduced = res.r.len < @min(p, q);
        if (res.x_deficient != res.y_deficient and reduced or res.x_deficient and res.y_deficient and !reduced)
            return gap(cx.diags, l0, "PROC CANCORR: this combination of linearly dependent VAR and WITH variables is not verified", .{});
        // ponytail: with a canonical correlation of one SAS 9.4 prints the
        // rounding noise of exact zeros (e.g. 7.931816E-17); coefficient pages
        // are accepted only for one VAR and one WITH variable.
        if (res.r[0] == 1 and !s.short and (p != 1 or q != 1)) return gap(cx.diags, l0, "PROC CANCORR: canonical coefficients for a canonical correlation of one are not verified; SHORT is supported", .{});
        // SAS 9.4: the BY-group NOTE follows only a group's own messages.
        if (s.by_cols.len > 0 and cx.diags.count() > logged) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
        if (s.noprint) continue;
        const vh = try headings(a, s.vprefix, res.r.len);
        const wh = try headings(a, s.wprefix, res.r.len);
        var byline: []const u8 = "";
        if (s.by_cols.len > 0) {
            var tmp: Out = .empty;
            try by.appendLine(a, &tmp, ds, group.rows[0], s.by_cols);
            byline = std.mem.trim(u8, tmp.items, " \n");
        }
        try pageStart(a, cx, &body, &first, byline, "Canonical Correlation Analysis");
        // SAS 9.4 (VAR set verified): a linearly dependent variable.
        const what: []const u8 = if (reduced) "canonical correlations and coefficients" else "canonical coefficients";
        if (res.x_deficient) try body.print(a, "\nNOTE: The correlation matrix for the {s} is less than full rank. Therefore, some {s} will be zero.\n", .{ s.vname, what });
        if (res.y_deficient) try body.print(a, "\nNOTE: The correlation matrix for the {s} is less than full rank. Therefore, some {s} will be zero.\n", .{ s.wname, what });
        if (res.x_deficient or res.y_deficient) try body.append(a, '\n');
        try canCorrTable(a, &body, res);
        // SAS 9.4 keeps one blank line where the multivariate table would start.
        if (few) try body.append(a, '\n') else try multivariateTable(a, &body, res);
        if (s.short) continue;
        const sc = res.r.len;
        const rawa = try a.alloc(f64, p * sc);
        const rawb = try a.alloc(f64, q * sc);
        for (0..p) |i| for (0..sc) |k| {
            rawa[i * sc + k] = res.a[i * sc + k] / res.sdx[i];
        };
        for (0..q) |i| for (0..sc) |k| {
            rawb[i * sc + k] = res.b[i * sc + k] / res.sdy[i];
        };
        try pageStart(a, cx, &body, &first, byline, "Canonical Correlation Analysis");
        try matrix(a, &body, try std.fmt.allocPrint(a, "Raw Canonical Coefficients for the {s}", .{s.vname}), xrows, vh, rawa, true);
        try matrix(a, &body, try std.fmt.allocPrint(a, "Raw Canonical Coefficients for the {s}", .{s.wname}), yrows, wh, rawb, true);
        try pageStart(a, cx, &body, &first, byline, "Canonical Correlation Analysis");
        try matrix(a, &body, try std.fmt.allocPrint(a, "Standardized Canonical Coefficients for the {s}", .{s.vname}), xrows, vh, res.a, false);
        try matrix(a, &body, try std.fmt.allocPrint(a, "Standardized Canonical Coefficients for the {s}", .{s.wname}), yrows, wh, res.b, false);
        // Canonical structure: corr(X, V) = Rxx a, corr(Y, W) = Ryy b,
        // corr(X, W) = Rxy b, corr(Y, V) = Ryx a.
        const k = p + q;
        const rxx = try sub(a, res.corr, k, 0, 0, p, p);
        const ryy = try sub(a, res.corr, k, p, p, q, q);
        const rxy = try sub(a, res.corr, k, 0, p, p, q);
        const ryx = try sub(a, res.corr, k, p, 0, q, p);
        try pageStart(a, cx, &body, &first, byline, "Canonical Structure");
        try matrix(a, &body, try std.fmt.allocPrint(a, "Correlations Between the {s} and Their Canonical Variables", .{s.vname}), xrows, vh, try mul(a, rxx, res.a, p, p, sc), false);
        try matrix(a, &body, try std.fmt.allocPrint(a, "Correlations Between the {s} and Their Canonical Variables", .{s.wname}), yrows, wh, try mul(a, ryy, res.b, q, q, sc), false);
        try matrix(a, &body, try std.fmt.allocPrint(a, "Correlations Between the {s} and the Canonical Variables of the {s}", .{ s.vname, s.wname }), xrows, wh, try mul(a, rxy, res.b, p, q, sc), false);
        try matrix(a, &body, try std.fmt.allocPrint(a, "Correlations Between the {s} and the Canonical Variables of the {s}", .{ s.wname, s.vname }), yrows, vh, try mul(a, ryx, res.a, q, p, sc), false);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("cancorr_tests.zig");
}
