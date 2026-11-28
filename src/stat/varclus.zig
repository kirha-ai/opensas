//! PROC VARCLUS (SAS/STAT 15.4 ch.129): PROC statement options, VAR / BY /
//! FREQ / WEIGHT roles, observation selection and the default oblique
//! principal component clustering of the correlation matrix, with its
//! listing and OUTSTAT= data set (STAT-VARCLUS-001).
//!
//! The listing layout is taken from a SAS listing of a MAXCLUSTERS=2 run on
//! labelled variables. Everything the cited pages define but this file does
//! not compute, or whose listing has not been verified against SAS, is a loud
//! D-009 gap: nothing is printed and no data set is created for that step.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fmt = @import("../format.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const pc = @import("princomp.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Spec = struct {
    input: proc.ProcInput,
    outstat: ?[]const u8 = null,
    // PROC statement (pp.10688-10695).
    maxc: ?usize = null,
    maxeigen: ?f64 = null,
    proportion: ?f64 = null,
    maxiter: usize = 10,
    maxsearch: ?usize = null,
    noprint: bool = false,
    plots: bool = false,
    vardef: pc.VarDef = .df,
    /// First option that names a feature owned by a later ticket.
    unsupported: ?[]const u8 = null,
    unsupported_line: usize = 0,
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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC VARCLUS: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
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
/// Canonical spelling of a PROC statement option (aliases of pp.10689-10695).
fn canonical(lower: []const u8) []const u8 {
    const pairs = [_][2][]const u8{
        .{ "covariance", "cov" },     .{ "maxc", "maxclusters" }, .{ "minc", "minclusters" },
        .{ "percent", "proportion" }, .{ "hi", "hierarchy" },     .{ "mg", "multiplegroup" },
        .{ "c", "corr" },             .{ "s", "simple" },         .{ "plot", "plots" },
    };
    for (pairs) |p| if (eq(lower, p[0])) return p[1];
    return lower;
}
fn number(t: []const lex.Token, i: usize) ?f64 {
    var j = i;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return null;
    return sign * (std.fmt.parseFloat(f64, t[j].text) catch return null);
}
fn width(t: []const lex.Token, i: usize) usize {
    return if (at(t, i, .minus)) 2 else 1;
}
fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC VARCLUS: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC VARCLUS: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
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
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: variable {s} in the {s} statement must be numeric", .{ n, role });
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var centroid = false;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = canonical(try std.ascii.allocLowerString(a, t[i].text));
        // SAS 9.4 (verified with MAXCLUSTERS=2 MAXCLUSTERS=3): the last
        // occurrence of a repeated PROC option is used.
        const valued = at(t, i + 1, .eq);
        const l = t[i].line;
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "outstat") and valued) {
            i = try memberName(cx, t, i + 2, &s.outstat);
        } else if ((eq(option, "maxclusters") or eq(option, "minclusters") or eq(option, "maxiter") or eq(option, "maxsearch") or eq(option, "random")) and valued) {
            const v = number(t, i + 2);
            const minimum: f64 = if (eq(option, "maxiter") or eq(option, "maxsearch")) 0 else 1;
            if (v == null or v.? != @floor(v.?) or v.? < minimum or v.? > 1e9)
                return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: {s}= must be an integer of at least {d}", .{ t[i].text, minimum });
            const n: usize = @intFromFloat(v.?);
            if (eq(option, "maxclusters")) s.maxc = n else if (eq(option, "maxiter")) s.maxiter = n else if (eq(option, "maxsearch")) s.maxsearch = n else if (eq(option, "minclusters")) {
                // p.10691: MINCLUSTERS=1 is the default start (one cluster).
                if (n != 1 and s.unsupported == null) {
                    s.unsupported = "MINCLUSTERS= greater than 1 (STAT-VARCLUS-003)";
                    s.unsupported_line = l;
                }
            } else if (s.unsupported == null) {
                s.unsupported = "RANDOM= with INITIAL=RANDOM (STAT-VARCLUS-003)";
                s.unsupported_line = l;
            }
            i += 2 + width(t, i + 2);
        } else if ((eq(option, "maxeigen") or eq(option, "proportion")) and valued) {
            var v = number(t, i + 2) orelse return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: {s}= must be a number", .{t[i].text});
            if (v < 0) return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: {s}= must be nonnegative", .{t[i].text});
            if (eq(option, "maxeigen")) s.maxeigen = v else {
                // p.10694: "Values greater than 1.0 are considered to be percentages".
                if (v > 1) v /= 100;
                s.proportion = v;
            }
            i += 2 + width(t, i + 2);
        } else if (eq(option, "vardef") and valued) {
            s.vardef = if (kw(t, i + 2, "df")) .df else if (kw(t, i + 2, "n")) .n else if (kw(t, i + 2, "wdf")) .wdf else if (kw(t, i + 2, "weight") or kw(t, i + 2, "wgt")) .weight else return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            i += 3;
        } else if ((eq(option, "outtree") or eq(option, "initial")) and valued) {
            if (s.unsupported == null) {
                s.unsupported = if (eq(option, "outtree")) "the OUTTREE= data set (STAT-VARCLUS-005)" else "INITIAL= (STAT-VARCLUS-003)";
                s.unsupported_line = l;
            }
            if (eq(option, "outtree")) {
                var ignored: ?[]const u8 = null;
                i = try memberName(cx, t, i + 2, &ignored);
            } else {
                if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
                const ok = [_][]const u8{ "group", "input", "random", "seed" };
                var known = false;
                for (ok) |k| known = known or eq(t[i + 2].text, k);
                if (!known) return cx.diags.fail(error.ParseError, l, "PROC VARCLUS: INITIAL= must be GROUP, INPUT, RANDOM or SEED", .{});
                i += 3;
            }
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
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "cov") or eq(option, "noint") or eq(option, "centroid") or eq(option, "hierarchy") or eq(option, "multiplegroup") or
            eq(option, "corr") or eq(option, "short") or eq(option, "simple") or eq(option, "summary") or eq(option, "trace"))
        {
            if (eq(option, "centroid")) centroid = true;
            if (s.unsupported == null) {
                s.unsupported = try std.fmt.allocPrint(a, "the {s} option (STAT-VARCLUS-002..006)", .{t[i].text});
                s.unsupported_line = l;
            }
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.10689: "You cannot specify both the CENTROID and MAXEIGEN= options."
    if (centroid and s.maxeigen != null) return cx.diags.fail(error.ParseError, line(t, 0), "PROC VARCLUS: the CENTROID and MAXEIGEN= options cannot both be specified", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC VARCLUS: input data set not found", .{});
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
    var var_seen = false;
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
            // p.10695: "If you specify more than one BY statement, only the last one specified is used."
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            // SAS 9.4 (verified): the variables of several VAR statements accumulate.
            var_seen = true;
            try columnList(cx, ds, t, i, end, "VAR", &vars);
        } else if (eq(word, "partial") or eq(word, "seed")) {
            return gap(cx.diags, t[i].line, "PROC VARCLUS: the {s} statement is not implemented (STAT-VARCLUS-003)", .{word});
        } else if (eq(word, "freq")) {
            // SAS 9.4 (verified): with several FREQ statements the first is used.
            const f = try oneNumeric(cx, ds, t, i, end, "FREQ");
            if (s.freq == null) s.freq = f;
        } else if (eq(word, "weight")) {
            // SAS 9.4 (verified): with several WEIGHT statements the first is used.
            const w = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
            if (s.weight == null) s.weight = w;
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (eq(word, "format")) {
            var j = i;
            try proc.parseProcFormat(a, t, &j, &formats);
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    for (formats.items) |spec| if (ds.indexOf(spec.name) == null) return cx.diags.fail(error.ParseError, 0, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, spec.name)});
    s.input.ds = try by.withFormats(a, ds, formats.items);
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (!var_seen) {
        // p.10696: all numeric variables not listed in other statements.
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC VARCLUS: no numeric variables to cluster", .{});
    return s;
}

/// One cluster component: first principal component of the members' correlations.
pub const Component = struct {
    /// Variance explained (first eigenvalue).
    explained: f64,
    /// Second eigenvalue; NaN for a one-member cluster.
    second: f64,
    /// Standardized scoring coefficients over all p variables (0 for nonmembers).
    score: []f64,
};

/// One level (number of clusters) of the divisive history.
pub const Level = struct {
    group: []usize,
    comps: []Component,
    /// Row-major p*k correlations of the variables with the components.
    structure: []f64,
    /// Row-major k*k inter-cluster correlations.
    ccorr: []f64,
    converged: bool,
};

fn members(a: A, group: []const usize, c: usize) ![]usize {
    var m: std.ArrayList(usize) = .empty;
    for (group, 0..) |g, j| if (g == c) try m.append(a, j);
    return m.items;
}

pub fn component(a: A, r: []const f64, p: usize, group: []const usize, c: usize) !Component {
    const m = try members(a, group, c);
    const score = try a.alloc(f64, p);
    @memset(score, 0);
    if (m.len == 0) return .{ .explained = 0, .second = nan, .score = score };
    const sub = try a.alloc(f64, m.len * m.len);
    for (m, 0..) |x, i| for (m, 0..) |y, j| {
        sub[i * m.len + j] = r[x * p + y];
    };
    const e = try pc.eigenSym(a, sub, m.len);
    const l1 = e.values[0];
    for (m, 0..) |x, i| score[x] = e.vectors[i * m.len] / @sqrt(l1);
    return .{ .explained = l1, .second = if (m.len > 1) e.values[1] else nan, .score = score };
}

fn corrWith(r: []const f64, p: usize, j: usize, score: []const f64) f64 {
    var s: f64 = 0;
    for (0..p) |i| s += r[j * p + i] * score[i];
    return s;
}

fn totalExplained(comps: []const Component) f64 {
    var s: f64 = 0;
    for (comps) |c| s += c.explained;
    return s;
}

fn computeComps(a: A, r: []const f64, p: usize, group: []const usize, k: usize) ![]Component {
    const comps = try a.alloc(Component, k);
    for (comps, 0..) |*c, ci| c.* = try component(a, r, p, group, ci);
    return comps;
}

/// Split cluster `c` into `c` and a new cluster `k` (p.10682 step 2): rotate
/// the first two eigenvectors by raw quartimax and assign each member to the
/// rotated component with the higher squared correlation.
fn split(a: A, r: []const f64, p: usize, group: []usize, c: usize, k: usize) !void {
    const m = try members(a, group, c);
    const n = m.len;
    const sub = try a.alloc(f64, n * n);
    for (m, 0..) |x, i| for (m, 0..) |y, j| {
        sub[i * n + j] = r[x * p + y];
    };
    const e = try pc.eigenSym(a, sub, n);
    // Quartimax on two columns: maximize sum of fourth powers; closed form
    // angle 4θ = atan2(2Σuv, Σ(u²−v²)), u = x²−y², v = 2xy.
    var num: f64 = 0;
    var den: f64 = 0;
    for (0..n) |i| {
        const x = e.vectors[i * n];
        const y = e.vectors[i * n + 1];
        const u = x * x - y * y;
        const v = 2 * x * y;
        num += 2 * u * v;
        den += u * u - v * v;
    }
    const theta = std.math.atan2(num, den) / 4;
    const co = @cos(theta);
    const si = @sin(theta);
    const b1 = try a.alloc(f64, n);
    const b2 = try a.alloc(f64, n);
    for (0..n) |i| {
        const x = e.vectors[i * n];
        const y = e.vectors[i * n + 1];
        b1[i] = x * co + y * si;
        b2[i] = -x * si + y * co;
    }
    var q1: f64 = 0;
    var q2: f64 = 0;
    for (0..n) |i| for (0..n) |j| {
        q1 += b1[i] * sub[i * n + j] * b1[j];
        q2 += b2[i] * sub[i * n + j] * b2[j];
    };
    const side = try a.alloc(bool, n);
    for (0..n) |i| {
        var s1: f64 = 0;
        var s2: f64 = 0;
        for (0..n) |j| {
            s1 += sub[i * n + j] * b1[j];
            s2 += sub[i * n + j] * b2[j];
        }
        side[i] = (s2 * s2) / q2 > (s1 * s1) / q1;
    }
    for (m, side) |x, sd| group[x] = if (sd) k else c;
    // The part whose component explains more variance keeps the old cluster
    // number (SAS listings: {SL,PL,PW} -> {PL,PW} stays cluster 1, {SL} is
    // the new cluster 3). On a tie the first member moves to the new cluster
    // (SAS listing, PROPORTION=1: {PL,PW} -> PW stays cluster 1, PL is the
    // new cluster 4). ponytail: one verified tie; the rule is not documented.
    const keep = try component(a, r, p, group, c);
    const moved = try component(a, r, p, group, k);
    if (moved.explained > keep.explained + 1e-12 or (@abs(moved.explained - keep.explained) <= 1e-12 and !side[0]))
        for (m, side) |x, sd| {
            group[x] = if (sd) c else k;
        };
}

/// Iterative reassignment (p.10683): NCS phase, then the search phase.
fn reassign(a: A, r: []const f64, p: usize, group: []usize, k: usize, maxiter: usize, maxsearch: usize) !bool {
    var converged = maxiter == 0;
    var it: usize = 0;
    while (it < maxiter) : (it += 1) {
        const comps = try computeComps(a, r, p, group, k);
        var changed = false;
        const next = try a.dupe(usize, group);
        for (0..p) |j| {
            var best = group[j];
            var best_r2 = std.math.pow(f64, corrWith(r, p, j, comps[best].score), 2);
            for (0..k) |c| {
                const r2 = std.math.pow(f64, corrWith(r, p, j, comps[c].score), 2);
                if (r2 > best_r2 + 1e-12) {
                    best = c;
                    best_r2 = r2;
                }
            }
            if (best != group[j]) {
                next[j] = best;
                changed = true;
            }
        }
        for (0..k) |c| if ((try members(a, next, c)).len == 0) return error.EmptyCluster;
        @memcpy(group, next);
        if (!changed) {
            converged = true;
            break;
        }
    }
    var pass: usize = 0;
    while (pass < maxsearch) : (pass += 1) {
        var moved = false;
        for (0..p) |j| {
            const from = group[j];
            if ((try members(a, group, from)).len == 1) continue;
            var base = totalExplained(try computeComps(a, r, p, group, k));
            for (0..k) |c| {
                if (c == group[j]) continue;
                const old = group[j];
                group[j] = c;
                const trial = totalExplained(try computeComps(a, r, p, group, k));
                if (trial > base + 1e-10) {
                    base = trial;
                    moved = true;
                } else group[j] = old;
            }
        }
        if (!moved) break;
    }
    return converged;
}

fn finish(a: A, r: []const f64, p: usize, group: []const usize, k: usize, converged: bool) !Level {
    const comps = try computeComps(a, r, p, group, k);
    const structure = try a.alloc(f64, p * k);
    for (0..p) |j| for (0..k) |c| {
        structure[j * k + c] = corrWith(r, p, j, comps[c].score);
    };
    const ccorr = try a.alloc(f64, k * k);
    for (0..k) |c| for (0..k) |d| {
        var s: f64 = 0;
        for (0..p) |i| s += comps[c].score[i] * corrWith(r, p, i, comps[d].score);
        ccorr[c * k + d] = if (c == d) 1 else s;
    };
    return .{ .group = try a.dupe(usize, group), .comps = comps, .structure = structure, .ccorr = ccorr, .converged = converged };
}

pub const Options = struct { maxc: usize, maxeigen: ?f64, proportion: ?f64, maxiter: usize, maxsearch: usize };

/// Why splitting stopped after the last level.
pub const Stop = enum { maxclusters, criterion, empty };

pub const History = struct {
    levels: []Level,
    stop: Stop,
    split_second: []f64,
    /// Per split: the cluster split (0-based) and whether PROPORTION= chose it.
    split_cluster: []usize = &.{},
    split_by_proportion: []bool = &.{},
};

/// The divisive history from one cluster (pp.10682-10683, 10689).
pub fn cluster(a: A, r: []const f64, p: usize, o: Options) !History {
    var levels: std.ArrayList(Level) = .empty;
    var seconds: std.ArrayList(f64) = .empty;
    var picked: std.ArrayList(usize) = .empty;
    var by_prop: std.ArrayList(bool) = .empty;
    const group = try a.alloc(usize, p);
    @memset(group, 0);
    try levels.append(a, try finish(a, r, p, group, 1, true));
    var stop: Stop = .maxclusters;
    while (true) {
        const k = levels.items.len;
        if (k >= o.maxc) break;
        const last = levels.items[k - 1];
        var pick: ?usize = null;
        var chosen_by_prop = false;
        if (o.maxeigen) |me| {
            for (last.comps, 0..) |c, ci| if (!std.math.isNan(c.second) and c.second > me and (pick == null or c.second > last.comps[pick.?].second)) {
                pick = ci;
            };
        }
        if (pick == null) if (o.proportion) |pr| {
            for (last.comps, 0..) |c, ci| {
                const n: f64 = @floatFromInt((try members(a, last.group, ci)).len);
                if (n > 1 and c.explained / n < pr and (pick == null or c.explained / n < last.comps[pick.?].explained / @as(f64, @floatFromInt((try members(a, last.group, pick.?)).len)))) pick = ci;
            }
            chosen_by_prop = pick != null;
        };
        const c = pick orelse {
            stop = .criterion;
            break;
        };
        try seconds.append(a, last.comps[c].second);
        try picked.append(a, c);
        try by_prop.append(a, chosen_by_prop);
        @memcpy(group, last.group);
        try split(a, r, p, group, c, k);
        const conv = reassign(a, r, p, group, k + 1, o.maxiter, o.maxsearch) catch |err| switch (err) {
            error.EmptyCluster => {
                stop = .empty;
                break;
            },
            else => |e| return e,
        };
        try levels.append(a, try finish(a, r, p, group, k + 1, conv));
    }
    return .{ .levels = levels.items, .stop = stop, .split_second = seconds.items, .split_cluster = picked.items, .split_by_proportion = by_prop.items };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn right(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try pad(a, out, w - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, w: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < w) try pad(a, out, w - text.len);
}
fn dec(a: A, v: f64, d: usize) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ v, d });
    if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
fn best8(a: A, v: f64) ![]const u8 {
    return fmt.bestNumW(a, v, 8) catch return error.OutOfMemory;
}
fn title(a: A, out: *Out, text: []const u8, indent: usize) !void {
    try out.appendSlice(a, "\n\n");
    try pad(a, out, indent);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}
fn dashes(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, '-', n);
    try out.appendSlice(a, "\n");
}

const Names = struct { names: []const []const u8, labels: []const []const u8, nw: usize, lw: usize, labelled: bool };

fn memberCount(group: []const usize, c: usize) usize {
    var n: usize = 0;
    for (group) |g| n += @intFromBool(g == c);
    return n;
}

const LevelStats = struct { total: f64, prop: f64, min_prop: f64, max_second: f64, min_r2: f64, max_ratio: f64 };

fn ownNext(lv: Level, j: usize) [2]f64 {
    const k = lv.comps.len;
    const own = std.math.pow(f64, lv.structure[j * k + lv.group[j]], 2);
    var next: f64 = nan;
    for (0..k) |c| if (c != lv.group[j]) {
        const r2 = std.math.pow(f64, lv.structure[j * k + c], 2);
        if (std.math.isNan(next) or r2 > next) next = r2;
    };
    return .{ own, next };
}

fn levelStats(lv: Level, p: usize) LevelStats {
    const k = lv.comps.len;
    var st: LevelStats = .{ .total = totalExplained(lv.comps), .prop = 0, .min_prop = std.math.inf(f64), .max_second = nan, .min_r2 = std.math.inf(f64), .max_ratio = nan };
    st.prop = st.total / @as(f64, @floatFromInt(p));
    for (lv.comps, 0..) |c, ci| {
        st.min_prop = @min(st.min_prop, c.explained / @as(f64, @floatFromInt(memberCount(lv.group, ci))));
        if (!std.math.isNan(c.second) and (std.math.isNan(st.max_second) or c.second > st.max_second)) st.max_second = c.second;
    }
    for (0..p) |j| {
        const on = ownNext(lv, j);
        st.min_r2 = @min(st.min_r2, on[0]);
        if (k > 1) {
            const ratio = (1 - on[0]) / (1 - on[1]);
            if (std.math.isNan(st.max_ratio) or ratio > st.max_ratio) st.max_ratio = ratio;
        }
    }
    return st;
}

fn renderLevel(a: A, out: *Out, lv: Level, nm: Names) !void {
    const k = lv.comps.len;
    const p = nm.names.len;
    try out.appendSlice(a, "\n\nClustering algorithm converged.");
    try pad(a, out, 44);
    try out.appendSlice(a, "\n");
    const head = try std.fmt.allocPrint(a, "Cluster Summary for {d} Cluster{s}", .{ k, if (k == 1) "" else "s" });
    try title(a, out, head, (72 - head.len + 1) / 2);
    try out.appendSlice(a, "                        Cluster    Variation    Proportion        Second\n");
    try out.appendSlice(a, "Cluster    Members    Variation    Explained     Explained    Eigenvalue\n");
    try dashes(a, out, 72);
    for (lv.comps, 0..) |c, ci| {
        const n = memberCount(lv.group, ci);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{ci + 1}), 7);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{n}), 11);
        try right(a, out, try best8(a, @floatFromInt(n)), 13);
        try right(a, out, try best8(a, c.explained), 13);
        try right(a, out, try dec(a, c.explained / @as(f64, @floatFromInt(n)), 4), 14);
        try right(a, out, if (std.math.isNan(c.second)) "" else try dec(a, c.second, 4), 14);
        try out.appendSlice(a, "\n");
    }
    const st = levelStats(lv, p);
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\nTotal variation explained = {s} Proportion = {s}\n", .{ try best8(a, st.total), try dec(a, st.prop, 4) }));
    if (k < 2) return;
    // R-squared table (verified layout).
    const lw = nm.lw;
    const nw = nm.nw;
    const rule = 14 + nw + 32 + (if (nm.labelled) 4 + lw else 0);
    try out.appendSlice(a, "\n\n");
    try pad(a, out, 14 + nw + 6);
    try out.appendSlice(a, "R-squared with\n");
    try left(a, out, try std.fmt.allocPrint(a, "{d} Clusters", .{k}), 14 + nw + 4);
    try out.appendNTimes(a, '-', 18);
    try out.appendSlice(a, "\n");
    try pad(a, out, 14 + nw);
    try right(a, out, "Own", 11);
    try right(a, out, "Next", 11);
    try right(a, out, "1-R**2", 10);
    try out.appendSlice(a, if (nm.labelled) "    Variable\n" else "\n");
    try left(a, out, "Cluster", 14);
    try left(a, out, "Variable", nw);
    try right(a, out, "Cluster", 11);
    try right(a, out, "Closest", 11);
    try right(a, out, "Ratio", 10);
    try out.appendSlice(a, if (nm.labelled) "    Label\n" else "\n");
    for (0..k) |c| {
        try dashes(a, out, rule);
        var first = true;
        for (0..p) |j| {
            if (lv.group[j] != c) continue;
            const on = ownNext(lv, j);
            try left(a, out, if (first) try std.fmt.allocPrint(a, "Cluster {d}", .{c + 1}) else "", 14);
            first = false;
            try left(a, out, nm.names[j], nw);
            try right(a, out, try dec(a, on[0], 4), 11);
            try right(a, out, try dec(a, on[1], 4), 11);
            try right(a, out, try dec(a, (1 - on[0]) / (1 - on[1]), 4), 10);
            if (nm.labelled) {
                try pad(a, out, 4);
                try left(a, out, nm.labels[j], lw);
            }
            try out.appendSlice(a, "\n");
        }
    }
}

/// Table-wide fixed decimals of the matrix tables (SAS listings): 5 when a
/// value rounds to magnitude 1 or more, else 6 with "-." for negatives, in an
/// 8-column number.
fn matrixDecimals(lv: Level, values: []const f64, stride_var: bool, p: usize) usize {
    const k = lv.comps.len;
    for (0..p) |j| for (0..k) |c| {
        const v = if (stride_var) values[j * k + c] else lv.comps[c].score[j];
        if (@abs(v) >= 0.9999995) return 5;
    };
    return 6;
}
fn matrixNumber(a: A, v: f64, d: usize) ![]const u8 {
    const text = try dec(a, v, d);
    if (d == 6 and std.mem.startsWith(u8, text, "-0.")) return std.fmt.allocPrint(a, "-{s}", .{text[2..]});
    return text;
}

fn matrixTable(a: A, out: *Out, heading: []const u8, nm: Names, k: usize, values: []const f64, stride_var: bool, lv: Level) !void {
    // Verified layouts: the name column is at least as wide as "Cluster";
    // with labels 6 spaces and a label column follow.
    const lw: usize = if (nm.labelled) nm.lw else 0;
    var mw: usize = 7;
    for (nm.names) |n| mw = @max(mw, n.len);
    const nw = if (nm.labelled) mw + 6 else mw;
    const total = nw + lw + 14 * k;
    const d = matrixDecimals(lv, values, stride_var, nm.names.len);
    try title(a, out, heading, (total - heading.len) / 2);
    try left(a, out, "Cluster", nw + lw);
    for (0..k) |c| try right(a, out, try std.fmt.allocPrint(a, "{d}", .{c + 1}), 14);
    try out.appendSlice(a, "\n");
    try dashes(a, out, total);
    for (nm.names, 0..) |n, j| {
        try left(a, out, n, nw);
        if (nm.labelled) try left(a, out, nm.labels[j], lw);
        for (0..k) |c| {
            const v = if (stride_var) values[j * k + c] else lv.comps[c].score[j];
            try right(a, out, try matrixNumber(a, v, d), 14);
        }
        try out.appendSlice(a, "\n");
    }
}

fn renderMatrices(a: A, out: *Out, lv: Level, nm: Names) !void {
    const k = lv.comps.len;
    {
        try matrixTable(a, out, "Standardized Scoring Coefficients", nm, k, &.{}, false, lv);
        try matrixTable(a, out, "Cluster Structure", nm, k, lv.structure, true, lv);
        const tw = 7 + 14 * k;
        try title(a, out, "Inter-Cluster Correlations", (tw - 26) / 2);
        try left(a, out, "Cluster", 7);
        for (0..k) |c| try right(a, out, try std.fmt.allocPrint(a, "{d}", .{c + 1}), 14);
        try out.appendSlice(a, "\n\n");
        for (0..k) |c| {
            try left(a, out, try std.fmt.allocPrint(a, "{d}", .{c + 1}), 7);
            for (0..k) |d| try right(a, out, try dec(a, lv.ccorr[c * k + d], 5), 14);
            try out.appendSlice(a, "\n");
        }
    }
}

fn renderHistory(a: A, out: *Out, h: History, p: usize) !void {
    try out.appendSlice(a, "\n\n");
    try out.appendSlice(a, "                 Total     Proportion       Minimum       Maximum                  Maximum\n");
    try out.appendSlice(a, "             Variation             of    Proportion        Second      Minimum      1-R**2\n");
    try out.appendSlice(a, "  Number     Explained      Variation     Explained    Eigenvalue    R-squared       Ratio\n");
    try out.appendSlice(a, "      of            by      Explained          by a          in a        for a       for a\n");
    try out.appendSlice(a, "Clusters      Clusters    by Clusters       Cluster       Cluster     Variable    Variable\n");
    try dashes(a, out, 90);
    for (h.levels, 0..) |l, li| {
        const st = levelStats(l, p);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{li + 1}), 8);
        try right(a, out, try dec(a, st.total, 6), 14);
        try right(a, out, try dec(a, st.prop, 4), 15);
        try right(a, out, try dec(a, st.min_prop, 4), 14);
        // Verified (PROPORTION=1, four single-variable clusters): a level of
        // only single-variable clusters shows a maximum second eigenvalue of 0.
        try right(a, out, try dec(a, if (std.math.isNan(st.max_second)) 0 else st.max_second, 6), 14);
        try right(a, out, try dec(a, st.min_r2, 4), 13);
        try right(a, out, if (std.math.isNan(st.max_ratio)) "" else try dec(a, st.max_ratio, 4), 12);
        try out.appendSlice(a, "\n");
    }
}

fn render(a: A, out: *Out, h: History, nm: Names, n: f64, o: Options, maxeigen_shown: f64, proportion_shown: f64) !void {
    try out.appendSlice(a, "\nOblique Principal Component Cluster Analysis\n\n");
    try left(a, out, "Observations", 12);
    try right(a, out, try best8(a, n), 15);
    try pad(a, out, 4);
    try left(a, out, "Proportion", 10);
    try right(a, out, try best8(a, proportion_shown), 11);
    try out.appendSlice(a, "\n");
    try left(a, out, "Variables", 12);
    try right(a, out, try std.fmt.allocPrint(a, "{d}", .{nm.names.len}), 15);
    try pad(a, out, 4);
    try left(a, out, "Maxeigen", 10);
    try right(a, out, try best8(a, maxeigen_shown), 11);
    try out.appendSlice(a, "\n");
    _ = o;
    for (h.levels, 0..) |lv, li| {
        try renderLevel(a, out, lv, nm);
        // Verified: the matrices follow every level with two or more clusters.
        if (lv.comps.len >= 2) try renderMatrices(a, out, lv, nm);
        if (li + 1 < h.levels.len) {
            const c = h.split_cluster[li];
            if (h.split_by_proportion[li]) {
                const cp = lv.comps[c];
                const n_members: f64 = @floatFromInt((try members(a, lv.group, c)).len);
                try out.appendSlice(a, try std.fmt.allocPrint(a, "\nCluster {d} will be split because it has the smallest proportion of variation explained, {s}, which is less than the PROPORTION={s} value.\n", .{ c + 1, try best8(a, cp.explained / n_members), try best8(a, proportion_shown) }));
            } else try out.appendSlice(a, try std.fmt.allocPrint(a, "\nCluster {d} will be split because it has the largest second eigenvalue, {s}, which is greater than the MAXEIGEN={s} value.\n", .{ c + 1, try best8(a, h.split_second[li]), try best8(a, maxeigen_shown) }));
        }
    }
    // Verified: with one cluster (criterion or MAXCLUSTERS=1) no history
    // table follows; after two or more clusters it does.
    if (h.stop == .criterion) try out.appendSlice(a, "\nNo cluster meets the criterion for splitting.\n");
    if (h.levels.len > 1) try renderHistory(a, out, h, nm.names.len);
}

const Stat = struct {
    ds: *Dataset,
    key: usize,
    cells: []Value,
    fn save(self: Stat, ncl: f64, tag: []const u8, name: []const u8, values: []const f64) !void {
        self.cells[self.key] = .{ .num = ncl };
        self.cells[self.key + 1] = .{ .str = tag };
        self.cells[self.key + 2] = .{ .str = name };
        for (self.cells[self.key + 3 ..], 0..) |*c, j| c.* = .{ .num = if (j < values.len) values[j] else nan };
        try self.ds.appendRow(self.cells);
    }
};

fn writeStat(a: A, st: Stat, by_values: []const Value, m: pc.Moments, n: f64, h: History, names: []const []const u8) !void {
    const p = names.len;
    @memcpy(st.cells[0..by_values.len], by_values);
    try st.save(nan, "MEAN", "", m.mean);
    try st.save(nan, "STD", "", m.std);
    const ns = try a.alloc(f64, p);
    @memset(ns, n);
    try st.save(nan, "N", "", ns);
    for (names, 0..) |nme, j| try st.save(nan, "CORR", nme, m.corr[j * p ..][0..p]);
    const row = try a.alloc(f64, p);
    for (h.levels) |lv| {
        const k = lv.comps.len;
        const ncl: f64 = @floatFromInt(k);
        const kk = @min(k, p);
        @memset(row, nan);
        for (0..kk) |c| row[c] = @floatFromInt(memberCount(lv.group, c));
        try st.save(ncl, "MEMBERS", "", row);
        @memset(row, nan);
        for (0..kk) |c| row[c] = lv.comps[c].explained;
        try st.save(ncl, "VAREXP", "", row);
        @memset(row, nan);
        for (0..kk) |c| row[c] = lv.comps[c].explained / @as(f64, @floatFromInt(memberCount(lv.group, c)));
        try st.save(ncl, "PROPOR", "", row);
        for (0..p) |j| row[j] = @floatFromInt(lv.group[j] + 1);
        try st.save(ncl, "GROUP", "", row);
        for (0..p) |j| row[j] = ownNext(lv, j)[0];
        try st.save(ncl, "RSQUARED", "", row);
        for (0..k) |c| try st.save(ncl, "SCORE", try std.fmt.allocPrint(a, "Clus{d}", .{c + 1}), lv.comps[c].score);
        for (0..k) |c| {
            for (0..p) |j| row[j] = lv.structure[j * k + c];
            try st.save(ncl, "STRUCTUR", try std.fmt.allocPrint(a, "Clus{d}", .{c + 1}), row);
        }
        for (0..k) |c| {
            @memset(row, nan);
            for (0..kk) |d| row[d] = lv.ccorr[c * k + d];
            try st.save(ncl, "CCORR", try std.fmt.allocPrint(a, "Clus{d}", .{c + 1}), row);
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    if (s.unsupported) |what| return gap(cx.diags, s.unsupported_line, "PROC VARCLUS: {s} is not implemented", .{what});
    if (s.plots) return gap(cx.diags, l0, "PROC VARCLUS: PLOTS= graphs are not implemented (STAT-VARCLUS-007)", .{});
    if (!s.noprint) if (cx.graphics) |g| if (g.enabled == true) return gap(cx.diags, l0, "PROC VARCLUS: the default dendrogram under ODS GRAPHICS is not implemented (STAT-VARCLUS-007)", .{});
    // p.10686: DATA= may be TYPE=CORR, COV, UCORR, UCOV, FACTOR, SSCP; opensas
    // keeps no data set TYPE= attribute, so such input is not read as a matrix.
    if (ds.indexOf("_type_") != null) return gap(cx.diags, l0, "PROC VARCLUS: input data sets with a _TYPE_ variable (TYPE=CORR, COV, UCORR, UCOV, FACTOR, SSCP) are not implemented", .{});
    // SAS 9.4 (verified): an empty input prints nothing, notes it and does not fail.
    if (ds.rows.items.len == 0) {
        const upper = try std.ascii.allocUpperString(a, ds.name);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, ds.name, '.') == null) "WORK." else "";
        return cx.diags.note(l0, "No observations were selected from data set {s}{s}.", .{ lib_prefix, upper });
    }
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;
    // p.10691: MAXCLUSTERS= defaults to the number of variables. MAXEIGEN=
    // defaults to 0 with MAXCLUSTERS= and to 1 (correlations) otherwise,
    // unless PROPORTION= is given.
    const maxc = @min(s.maxc orelse p, p);
    const maxeigen: ?f64 = s.maxeigen orelse if (s.proportion != null) null else if (s.maxc != null) 0 else 1;
    const opts: Options = .{ .maxc = maxc, .maxeigen = maxeigen, .proportion = s.proportion, .maxiter = s.maxiter, .maxsearch = s.maxsearch orelse 1000 / p };

    const names = try a.alloc([]const u8, p);
    const labels = try a.alloc([]const u8, p);
    var nw: usize = 8;
    var lw: usize = 5;
    var any_label = false;
    for (s.vars, names, labels) |ci, *n, *lab| {
        const col = ds.columns.items[ci];
        n.* = col.name;
        lab.* = col.label orelse "";
        if (col.label != null and col.label.?.len > 0) any_label = true;
        nw = @max(nw, col.name.len);
        lw = @max(lw, lab.len);
    }
    const nm: Names = .{ .names = names, .labels = labels, .nw = nw, .lw = lw, .labelled = any_label };

    var created: ?*Dataset = null;
    var key: usize = 0;
    if (s.outstat) |member| {
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        for (s.by_cols) |c| try o.columns.append(a, ds.columns.items[c]);
        key = s.by_cols.len;
        var name_len: usize = 8;
        for (names) |n| name_len = @max(name_len, n.len);
        try o.columns.append(a, .{ .name = "_NCL_", .type = .num, .len = 8 });
        try o.columns.append(a, .{ .name = "_TYPE_", .type = .char, .len = 8 });
        try o.columns.append(a, .{ .name = "_NAME_", .type = .char, .len = name_len });
        for (s.vars) |ci| {
            const col = ds.columns.items[ci];
            if (o.indexOf(col.name) != null) return gap(cx.diags, l0, "PROC VARCLUS: OUTSTAT= column {s} collides with a BY or reserved column; not supported", .{col.name});
            try o.columns.append(a, .{ .name = col.name, .type = .num, .len = 8, .label = col.label });
        }
        created = o;
    }

    var body: Out = .empty;
    for (groups) |group| {
        const ps: pc.Spec = .{ .input = s.input, .vars = s.vars, .freq = s.freq, .weight = s.weight, .vardef = s.vardef };
        const sel = try pc.select(a, ps, group.rows);
        {
            // Log warnings of the SAS run (rc 1): observations omitted for a
            // missing value, then for a nonpositive weight or truncated frequency.
            var missing: usize = 0;
            var dropped: usize = 0;
            rows: for (group.rows) |row| {
                for (s.vars) |ci| if (std.math.isNan(row[ci].num)) {
                    missing += 1;
                    continue :rows;
                };
                if (s.freq) |ci| if (std.math.isNan(row[ci].num)) {
                    missing += 1;
                    continue :rows;
                };
                if (s.weight) |ci| if (std.math.isNan(row[ci].num)) {
                    missing += 1;
                    continue :rows;
                };
                if (s.freq) |ci| if (!(@floor(row[ci].num) >= 1)) {
                    dropped += 1;
                    continue :rows;
                };
                if (s.weight) |ci| if (!(row[ci].num > 0)) {
                    dropped += 1;
                };
            }
            const upper = try std.ascii.allocUpperString(a, ds.name);
            const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, ds.name, '.') == null) "WORK." else "";
            if (missing > 0) try cx.diags.warnStatus(l0, "{d} of {d} observations in data set {s}{s} omitted due to missing values.", .{ missing, group.rows.len, lib_prefix, upper });
            if (dropped > 0) try cx.diags.warnStatus(l0, "{d} of {d} observations in data set {s}{s} omitted due to nonpositive weight or truncated frequency.", .{ dropped, group.rows.len, lib_prefix, upper });
        }
        if (group.rows.len == 1 and s.by_cols.len == 0) {
            const upper = try std.ascii.allocUpperString(a, ds.name);
            const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, ds.name, '.') == null) "WORK." else "";
            return cx.diags.fail(error.ParseError, l0, "There must be at least 2 observations in data set {s}{s}.", .{ lib_prefix, upper });
        }
        if (sel.n < 2) return gap(cx.diags, l0, "PROC VARCLUS: an analysis with fewer than two usable observations is not verified against SAS output", .{});
        const m = (try pc.moments(a, ps, group.rows, sel)) orelse return gap(cx.diags, l0, "PROC VARCLUS: a variable with zero variance is not verified against SAS output", .{});
        const h = cluster(a, m.corr, p, opts) catch return error.OutOfMemory;
        for (h.levels) |lv| if (!lv.converged) return gap(cx.diags, l0, "PROC VARCLUS: the listing when the NCS phase does not converge within MAXITER= is not implemented", .{});
        if (h.stop == .empty) return gap(cx.diags, l0, "PROC VARCLUS: a split that leaves a cluster without members is not verified against SAS output", .{});
        for (h.levels) |_| try cx.diags.note(0, "Clustering algorithm converged.", .{});
        if (!s.noprint) {
            if (s.maxeigen != null and s.proportion != null)
                return gap(cx.diags, l0, "PROC VARCLUS: the listing with both MAXEIGEN= and PROPORTION= is not verified against SAS output; use NOPRINT with OUTSTAT=", .{});
            // Listings verified against SAS 9.4: default options, MAXCLUSTERS=
            // (1, 2, 3), MAXEIGEN=, PROPORTION=/PERCENT= and their
            // combination, stopping by MAXCLUSTERS= or by the criterion.
            if (s.by_cols.len > 0 and !io.global_nobyline) {
                // Verified (NOCENTER): the BY line starts in column 1, with
                // the formatted value of a formatted BY variable.
                // ponytail: the CENTER option is not tracked.
                try body.append(a, '\n');
                for (s.by_cols, 0..) |c, bi| {
                    if (bi > 0) try body.append(a, ' ');
                    try body.appendSlice(a, ds.columns.items[c].name);
                    try body.append(a, '=');
                    const v = group.rows[0][c];
                    try body.appendSlice(a, if (ds.columns.items[c].format) |spec| std.mem.trim(u8, try fmt.apply(a, v, spec), " ") else try proc.cellText(a, v));
                }
                try body.append(a, '\n');
            }
            // Verified header values: MAXEIGEN= alone shows Proportion 0;
            // PROPORTION= alone shows Maxeigen 0; MAXCLUSTERS= alone shows
            // Proportion 1, Maxeigen 0; defaults show Proportion 0, Maxeigen 1.
            const prop_shown: f64 = s.proportion orelse if (s.maxeigen != null) 0 else if (s.maxc != null) 1 else 0;
            try render(a, &body, h, nm, sel.n, opts, maxeigen orelse 0, prop_shown);
        }
        if (created) |o| {
            const cells = try a.alloc(Value, o.columns.items.len);
            const byv = try a.alloc(Value, s.by_cols.len);
            for (s.by_cols, byv) |c, *v| v.* = group.rows[0][c];
            try writeStat(a, .{ .ds = o, .key = key, .cells = cells }, byv, m, sel.n, h, names);
        }
    }
    if (created) |o| {
        const member = s.outstat.?;
        try cx.lib.put(member, o);
        const upper = try std.ascii.allocUpperString(a, member);
        const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("varclus_tests.zig");
}
