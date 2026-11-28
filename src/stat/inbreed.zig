//! PROC INBREED (SAS/STAT 15.4 ch.71, STAT-INBREED-001): PROC statement
//! options DATA=, COVAR, MATRIX, IND, INDL, MATRIXL, INIT=, NOPRINT; the VAR and BY roles,
//! the default (unaddressed) VAR variables, the documented missing-value
//! rules (pp.5278-5279) and the overlapping-population coancestry recursion
//! (pp.5280-5285), the CLASS nonoverlapping-generation recursion, the
//! MATRIX / IND listings and "Number of Individuals". Everything the cited
//! pages define but this file does not compute is a loud D-009 gap: GENDER,
//! MATINGS, AVERAGE, SELFDIAG and OUTCOV=; non-dyadic covariance values
//! (see checkCov) and populations over 5000 individuals.
//!
//! Coancestry f (overlapping mode, individuals in population order; for X
//! older than Y with parents C, D): f_XY = (f_XC + f_XD)/2, f_XX =
//! (1 + F_X)/2, F_X = f_AB for parents A, B. A coancestry with an unknown
//! individual is INIT/2, or missing when INIT= is absent (missing terms count
//! 0 in a sum; a sum of only missing terms stays missing, which the reference
//! listings show as "."). Covariance = 2f. A covariance variable value on an
//! observation fixes Cov of that individual's two parents (latest wins).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Spec = struct {
    input: proc.ProcInput,
    covar: bool = false,
    matrix: bool = false,
    ind: bool = false,
    noprint: bool = false,
    /// INDL / MATRIXL (p.5276): the IND / MATRIX tables for the last
    /// generation only (every generation whose number equals the last one's,
    /// p.5277); without CLASS the whole population is the last generation.
    indl: bool = false,
    matrixl: bool = false,
    /// INIT= value; null when the option is absent (unknown coancestry missing).
    init: ?f64 = null,
    /// Column indices: individual, parent1, parent2, optional covariance.
    ind_col: usize = 0,
    p1_col: usize = 0,
    p2_col: usize = 0,
    cov_col: ?usize = null,
    /// CLASS generation variable (nonoverlapping mode), p.5277.
    class_col: ?usize = null,
    var_given: bool = false,
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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC INBREED: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var data_name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const o = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(o, "data") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            data_name = t[i + 2].text;
            var j = i + 3;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                data_name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[i + 2].text, t[j + 1].text });
                qualified = i + 2;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if (eq(o, "init") and valued) {
            // p.5276: INIT=cov, a number.
            var j = i + 2;
            const neg = at(t, j, .minus);
            if (neg) j += 1;
            if (!at(t, j, .number)) return cx.diags.fail(error.ParseError, t[i].line, "PROC INBREED: INIT= requires a numeric value", .{});
            const v = std.fmt.parseFloat(f64, t[j].text) catch return cx.diags.fail(error.ParseError, t[j].line, "PROC INBREED: invalid INIT= value {s}", .{t[j].text});
            s.init = if (neg) -v else v;
            i = j + 1;
        } else if (eq(o, "outcov") and valued) {
            return gap(cx.diags, t[i].line, "PROC INBREED: OUTCOV= is not implemented (STAT-INBREED-005)", .{});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(o, "covar") or eq(o, "c")) {
            s.covar = true;
            i += 1;
        } else if (eq(o, "matrix") or eq(o, "m")) {
            s.matrix = true;
            i += 1;
        } else if (eq(o, "ind") or eq(o, "i")) {
            s.ind = true;
            i += 1;
        } else if (eq(o, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(o, "average") or eq(o, "a")) {
            return gap(cx.diags, t[i].line, "PROC INBREED: the AVERAGE option is not implemented (STAT-INBREED-003)", .{});
        } else if (eq(o, "indl")) {
            s.indl = true;
            i += 1;
        } else if (eq(o, "matrixl")) {
            s.matrixl = true;
            i += 1;
        } else if (eq(o, "selfdiag")) {
            return gap(cx.diags, t[i].line, "PROC INBREED: the SELFDIAG option is not implemented (STAT-INBREED-005)", .{});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.5275: without DATA= the most recently created data set is used.
    const raw = (if (data_name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC INBREED: input data set {s} not found", .{data_name orelse "_LAST_"});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = data_name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var addressed: std.ArrayList(usize) = .empty;
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
            // p.5276: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (s.var_given) return gap(cx.diags, t[i].line, "PROC INBREED: more than one VAR statement is not verified", .{});
            s.var_given = true;
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                const names = try lists.next(a, ds, body, &j, cx.diags);
                for (names) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC INBREED: VAR variable {s} not found", .{n});
                    if (std.mem.indexOfScalar(usize, vars.items, ci) != null) return cx.diags.fail(error.ParseError, l, "PROC INBREED: variable {s} appears more than once in the VAR statement", .{n});
                    try vars.append(a, ci);
                }
            }
            // p.5278: three or four variables.
            if (vars.items.len < 3 or vars.items.len > 4) return cx.diags.fail(error.ParseError, t[i].line, "PROC INBREED: the VAR statement requires three or four variables (individual parent1 parent2 <covariance>), found {d}", .{vars.items.len});
        } else if (eq(word, "class")) {
            if (s.class_col != null) return gap(cx.diags, t[i].line, "PROC INBREED: more than one CLASS statement is not verified", .{});
            // p.5277: CLASS variable; one generation variable.
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC INBREED: the CLASS statement names exactly one generation variable", .{});
            const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC INBREED: CLASS variable {s} not found", .{t[i + 1].text});
            // p.5277: generation numbers must be integers.
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC INBREED: the CLASS variable {s} must be numeric (integer generation numbers)", .{t[i + 1].text});
            s.class_col = ci;
        } else if (eq(word, "gender")) {
            return gap(cx.diags, t[i].line, "PROC INBREED: the GENDER statement is not implemented (STAT-INBREED-003)", .{});
        } else if (eq(word, "matings")) {
            return gap(cx.diags, t[i].line, "PROC INBREED: the MATINGS statement is not implemented (STAT-INBREED-003)", .{});
        } else if (eq(word, "format") or eq(word, "label") or eq(word, "attrib") or eq(word, "freq") or eq(word, "weight")) {
            return gap(cx.diags, t[i].line, "PROC INBREED: a {s} statement inside the step is not implemented", .{word});
        } else if (eq(word, "where")) {
            // Applied to DATA= by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(a, ds, cx.diags);
    const bcols = try a.alloc(usize, pb.names.len);
    for (pb.names, bcols) |n, *c| {
        c.* = ds.indexOf(n).?;
        try addressed.append(a, c.*);
    }
    s.by_cols = bcols;
    if (s.class_col) |c| try addressed.append(a, c);
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (!s.var_given) {
        // SAS 9.4 reference run (2026-11-28): the log says so.
        try cx.diags.warn(0, "The VAR statement was not specified.  All the variables in the {s} data set will be used instead.", .{try lists.datasetName(a, ds)});
        // p.5278/p.5280: the first three unaddressed variables, plus an
        // unaddressed fourth one as the covariance variable.
        for (0..ds.columns.items.len) |ci| {
            if (std.mem.indexOfScalar(usize, addressed.items, ci) != null) continue;
            try vars.append(a, ci);
            if (vars.items.len == 4) break;
        }
        if (vars.items.len < 3) return cx.diags.fail(error.ParseError, line(t, 0), "PROC INBREED: the data set needs at least three variables not used in other statements (individual, parent1, parent2)", .{});
        if (vars.items.len == 4 and ds.columns.items[vars.items[3]].type != .num)
            return gap(cx.diags, line(t, 0), "PROC INBREED: without a VAR statement, a character fourth variable {s} (covariance must be numeric) is not verified", .{ds.columns.items[vars.items[3]].name});
    } else {
        for (vars.items) |ci| if (std.mem.indexOfScalar(usize, addressed.items, ci) != null)
            return gap(cx.diags, line(t, 0), "PROC INBREED: a BY or CLASS variable that is also a VAR variable is not verified", .{});
    }
    s.ind_col = vars.items[0];
    s.p1_col = vars.items[1];
    s.p2_col = vars.items[2];
    if (vars.items.len == 4) {
        s.cov_col = vars.items[3];
        // p.5278: the fourth variable, if specified, must be numeric.
        if (ds.columns.items[vars.items[3]].type != .num) return cx.diags.fail(error.ParseError, line(t, 0), "PROC INBREED: the covariance variable {s} must be numeric", .{ds.columns.items[vars.items[3]].name});
    }
    if (s.init) |v| try checkCov(cx, v, "INIT=");
    if (s.noprint) {
        // SAS 9.4 reference run (2026-11-28): NOPRINT without OUTCOV= (OUTCOV=
        // itself is a gap above) is an error and nothing is computed.
        if (s.matrixl) try cx.diags.warn(0, "The MATRIXL option conflicts with the NOPRINT option. The MATRIXL option is ignored.", .{});
        if (s.indl) return gap(cx.diags, line(t, 0), "PROC INBREED: the INDL option together with NOPRINT is not verified", .{});
        return cx.diags.fail(error.ParseError, line(t, 0), "The NOPRINT option was specified without OUTCOV= option. Procedure output can not be viewed, unless either printing is enabled or OUTCOV= data set is given.  Computations will not be performed.", .{});
    }
    return s;
}

/// A covariance value (INIT= or the covariance variable). ponytail: SAS 9.4
/// prints coefficients derived from non-dyadic values one fourth-decimal
/// unit low in a pattern not identified (reference runs 2026-11-28: 0.3 ->
/// 0.2999, 0.65 -> 0.6499, 1.135 -> 1.1349, and 0.123456 gives
/// Cov(parent, offspring) 0.5616 where (1 + 0.123456)/2 = 0.561728), while
/// dyadic values (0.25, 0.46875, 0.875) print exactly rounded. So only
/// values that are exact binary fractions (multiples of 2**-20) are
/// computed; any other value fails loud instead of printing a plausible
/// number SAS would not print; so are values below 0.001 (see below). Values
/// outside [0, 2] are reset by SAS with a
/// WARNING whose rule is not verified here.
fn checkCov(cx: proc.ProcCtx, v: f64, what: []const u8) diag.Error!void {
    if (v < 0 or v > 2) return proc.failGap(cx.diags, 0, "PROC INBREED: {s} covariance value {d} outside the range [0, 2] is not implemented", .{ what, v });
    // Reference run: a covariance value 0.00005 displays as "." (treated as
    // an unknown zero); where that threshold lies, and how an explicit 0 on
    // the covariance variable displays, is not verified.
    if (v < 0.001 and !(v == 0 and std.mem.eql(u8, what, "INIT="))) return proc.failGap(cx.diags, 0, "PROC INBREED: {s} covariance value {d} below 0.001 is not verified", .{ what, v });
    const scaled = v * 1048576.0;
    if (scaled != @round(scaled)) return proc.failGap(cx.diags, 0, "PROC INBREED: {s} covariance value {d} is not an exact binary fraction; SAS 9.4's fourth-decimal display for such values is not reproduced (STAT-INBREED-001 known divergence)", .{ what, v });
}

/// p.5278: only the first 12 characters of a character name are recognized;
/// null = missing.
fn nameKey(a: A, v: Value) !?[]const u8 {
    switch (v) {
        .str => |x| {
            const tr = std.mem.trimEnd(u8, x, " ");
            if (std.mem.trim(u8, tr, " ").len == 0) return null;
            return tr[0..@min(tr.len, 12)];
        },
        .num => |x| {
            if (std.math.isNan(x)) return null;
            return try proc.cellText(a, v);
        },
    }
}

/// One analysed population (a BY group).
pub const Population = struct {
    names: []const []const u8,
    /// Parent display text (blank for an inserted or parentless individual).
    p1_text: []const []const u8,
    p2_text: []const []const u8,
    sire: []const ?usize,
    dam: []const ?usize,
    /// Symmetric n x n coancestry; NaN = missing (unknown).
    f: []const f64,
    /// Inbreeding coefficient F_X; NaN = missing.
    inbreeding: []const f64,

    pub fn n(self: Population) usize {
        return self.names.len;
    }
    /// Displayed coefficient (covariance = 2f; inbreeding mode shows F on
    /// the diagonal and f off it).
    pub fn value(self: Population, covar: bool, i: usize, j: usize) f64 {
        const k = self.names.len;
        if (covar) return 2 * self.f[i * k + j];
        if (i == j) return self.inbreeding[i];
        return self.f[i * k + j];
    }
};

fn pairKey(i: usize, j: usize) u64 {
    const lo = @min(i, j);
    const hi = @max(i, j);
    return (@as(u64, lo) << 32) | hi;
}
fn half(x: f64, y: f64) f64 {
    if (std.math.isNan(x) and std.math.isNan(y)) return nan;
    return ((if (std.math.isNan(x)) 0 else x) + (if (std.math.isNan(y)) 0 else y)) / 2;
}

/// Builds the population of one BY group and computes the coancestries.
pub fn build(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, first_obs: usize) diag.Error!Population {
    const a = cx.arena;
    const ds = s.input.ds;
    var names: std.ArrayList([]const u8) = .empty;
    var p1t: std.ArrayList([]const u8) = .empty;
    var p2t: std.ArrayList([]const u8) = .empty;
    var sire: std.ArrayList(?usize) = .empty;
    var dam: std.ArrayList(?usize) = .empty;
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    var fixed: std.AutoHashMapUnmanaged(u64, f64) = .empty;
    const ind_name = ds.columns.items[s.ind_col].name;
    const p_names = [2][]const u8{ ds.columns.items[s.p1_col].name, ds.columns.items[s.p2_col].name };
    for (rows, 0..) |row, r| {
        const obs = if (s.input.srcobs) |so| so[first_obs + r] else first_obs + r + 1;
        const who = try nameKey(a, row[s.ind_col]);
        const cov: f64 = if (s.cov_col) |c| row[c].num else nan;
        if (who == null) {
            // p.5278: a missing individual is not added; for an overlapping
            // population such an observation cannot assign a covariance.
            try cx.diags.warn(0, "Variable {s} has a missing value at observation {d}.  It will be skipped.", .{ ind_name, obs });
            continue;
        }
        if (index.get(who.?) != null) {
            // p.5272: only the first occurrence is used.
            try cx.diags.warn(0, "Individual {s}={s} has been previously defined.  Observation {d} corresponding to this individual will not be processed.", .{ ind_name, who.?, obs });
            continue;
        }
        var par: [2]?usize = .{ null, null };
        for ([_]usize{ s.p1_col, s.p2_col }, 0..) |pc, k| {
            const pk = try nameKey(a, row[pc]);
            if (pk == null) {
                try cx.diags.note(0, "{s} parent {s} of individual {s}={s} is missing at observation {d}.", .{ if (k == 0) "First" else "Second", p_names[k], ind_name, who.?, obs });
                continue;
            }
            if (index.get(pk.?)) |pi| {
                par[k] = pi;
                continue;
            }
            // p.5271/p.5280: an unknown parent is inserted, unrelated and
            // parentless, just before the observation naming it.
            try index.put(a, pk.?, names.items.len);
            par[k] = names.items.len;
            try names.append(a, pk.?);
            try p1t.append(a, "");
            try p2t.append(a, "");
            try sire.append(a, null);
            try dam.append(a, null);
        }
        try index.put(a, who.?, names.items.len);
        try names.append(a, who.?);
        try p1t.append(a, (try nameKey(a, row[s.p1_col])) orelse "");
        try p2t.append(a, (try nameKey(a, row[s.p2_col])) orelse "");
        try sire.append(a, par[0]);
        try dam.append(a, par[1]);
        if (!std.math.isNan(cov)) {
            if (par[0] == null or par[1] == null) return proc.failGap(cx.diags, 0, "PROC INBREED: a covariance value at observation {d} for an individual with a missing parent is not verified", .{obs});
            try checkCov(cx, cov, "the covariance variable's");
            // p.5272: the latest specification overrides earlier ones.
            try fixed.put(a, pairKey(par[0].?, par[1].?), cov / 2);
        }
    }

    const k = names.items.len;
    // ponytail: a dense k x k coancestry matrix; SAS's large-population
    // storage is not reproduced, so a population needing more than ~200 MB
    // fails loud instead of exhausting memory.
    if (k > 5000) return proc.failGap(cx.diags, 0, "PROC INBREED: populations of more than 5000 individuals ({d}) are not implemented", .{k});
    // INIT=0 displays like an absent INIT= ("." for unknown pairs; reference
    // run, SAS 9.4): both mean a zero coancestry that is not known.
    const unknown: f64 = if (s.init) |v| (if (v != 0) v / 2 else nan) else nan;
    const f = try a.alloc(f64, k * k);
    const inb = try a.alloc(f64, k);
    for (0..k) |j| {
        const sj = sire.items[j];
        const dj = dam.items[j];
        // Coancestries with j for every older individual i (sj, dj < j).
        for (0..j) |i| {
            const v = if (fixed.get(pairKey(i, j))) |x| x else half(
                if (sj) |p| f[i * k + p] else unknown,
                if (dj) |p| f[i * k + p] else unknown,
            );
            f[i * k + j] = v;
            f[j * k + i] = v;
        }
        const fx = if (sj != null and dj != null) f[sj.? * k + dj.?] else unknown;
        inb[j] = fx;
        f[j * k + j] = (1 + (if (std.math.isNan(fx)) 0 else fx)) / 2;
    }
    return .{ .names = names.items, .p1_text = p1t.items, .p2_text = p2t.items, .sire = sire.items, .dam = dam.items, .f = f, .inbreeding = inb };
}

fn quarter(x: [4]f64) f64 {
    var sum: f64 = 0;
    var known = false;
    for (x) |v| if (!std.math.isNan(v)) {
        sum += v;
        known = true;
    };
    return if (known) sum / 4 else nan;
}

pub const Generation = struct { label: []const u8, pop: Population };

/// Nonoverlapping generations (CLASS, pp.5277-5282): generations in input
/// order; parents are individuals of the previous generation (an unknown
/// parent is appended to it, unrelated, and not displayed); for X (A, B) and
/// Y (C, D): f_XY = (f_AC + f_AD + f_BC + f_BD)/4, f_XX = (1 + f_AB)/2. An
/// observation with a missing individual assigns Cov(parent1, parent2)
/// between two current-generation individuals, applied to their whole
/// families (full sibs); the latest assignment wins.
pub fn buildGenerations(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, first_obs: usize) diag.Error![]Generation {
    const a = cx.arena;
    const gap = proc.failGap;
    const ds = s.input.ds;
    const gc = s.class_col.?;
    const ind_name = ds.columns.items[s.ind_col].name;
    const unknown: f64 = if (s.init) |v| (if (v != 0) v / 2 else nan) else nan;
    const self_unknown = (1 + (if (std.math.isNan(unknown)) 0 else unknown)) / 2;
    var gens: std.ArrayList(Generation) = .empty;
    // Previous generation: names, coancestry (row-major, width prev_w).
    var prev_index: std.StringHashMapUnmanaged(usize) = .empty;
    var prev_f: []const f64 = &.{};
    var prev_w: usize = 0;
    var prev_extra: usize = 0; // unknown parents appended to the previous generation
    var r: usize = 0;
    while (r < rows.len) {
        const gv = rows[r][gc].num;
        if (std.math.isNan(gv)) {
            r += 1; // p.5278: observations with missing generation are excluded
            continue;
        }
        if (gv != @trunc(gv)) return cx.diags.fail(error.ParseError, 0, "PROC INBREED: generation number {d} is not an integer", .{gv});
        // p.5277 and a SAS 9.4 reference run (2026-11-28): a generation
        // number that recurs after another one starts a new generation whose
        // parents are the previous run's individuals.
        var end = r;
        while (end < rows.len and (std.math.isNan(rows[end][gc].num) or rows[end][gc].num == gv)) end += 1;

        var names: std.ArrayList([]const u8) = .empty;
        var p1t: std.ArrayList([]const u8) = .empty;
        var p2t: std.ArrayList([]const u8) = .empty;
        var par: std.ArrayList([2]?usize) = .empty;
        var index: std.StringHashMapUnmanaged(usize) = .empty;
        const Assign = struct { x: usize, y: usize, f: f64 };
        var assigns: std.ArrayList(Assign) = .empty;
        for (rows[r..end], r..) |row, rr| {
            if (std.math.isNan(row[gc].num)) continue;
            const obs = if (s.input.srcobs) |so| so[first_obs + rr] else first_obs + rr + 1;
            const who = try nameKey(a, row[s.ind_col]);
            const k1 = try nameKey(a, row[s.p1_col]);
            const k2 = try nameKey(a, row[s.p2_col]);
            const cov: f64 = if (s.cov_col) |c| row[c].num else nan;
            if (who == null) {
                // p.5280: an assignment observation between two individuals
                // already defined in the current generation.
                if (std.math.isNan(cov) or k1 == null or k2 == null) return gap(cx.diags, 0, "PROC INBREED: an observation with a missing individual and no complete covariance assignment (observation {d}) is not verified for nonoverlapping generations", .{obs});
                const x = index.get(k1.?) orelse return gap(cx.diags, 0, "PROC INBREED: covariance assignment at observation {d} names {s}, which is not defined earlier in its generation; that case is not verified", .{ obs, k1.? });
                const y = index.get(k2.?) orelse return gap(cx.diags, 0, "PROC INBREED: covariance assignment at observation {d} names {s}, which is not defined earlier in its generation; that case is not verified", .{ obs, k2.? });
                try checkCov(cx, cov, "the covariance variable's");
                try assigns.append(a, .{ .x = x, .y = y, .f = cov / 2 });
                continue;
            }
            if (index.get(who.?) != null) {
                try cx.diags.warn(0, "Individual {s}={s} has been previously defined.  Observation {d} corresponding to this individual will not be processed.", .{ ind_name, who.?, obs });
                continue;
            }
            // p.5280: with CLASS, defining individuals and assigning
            // covariances are separate observations; the value here would
            // concern the previous generation, already reported (the Guide's
            // Figure 71.2 does not use it). Not applied, and said so.
            if (!std.math.isNan(cov)) try cx.diags.warn(0, "The covariance value at observation {d} defines no assignment for nonoverlapping generations and is ignored.", .{obs});
            var pp: [2]?usize = .{ null, null };
            for ([2]?[]const u8{ k1, k2 }, 0..) |pk, k| {
                if (pk == null) continue;
                if (prev_index.get(pk.?)) |pi| {
                    pp[k] = pi;
                    continue;
                }
                // pp.5271-5272: appended to the previous generation, unrelated.
                const pi = prev_w + prev_extra;
                prev_extra += 1;
                try prev_index.put(a, pk.?, pi);
                pp[k] = pi;
            }
            try index.put(a, who.?, names.items.len);
            try names.append(a, who.?);
            try p1t.append(a, k1 orelse "");
            try p2t.append(a, k2 orelse "");
            try par.append(a, pp);
        }
        const k = names.items.len;
        if (k > 5000) return gap(cx.diags, 0, "PROC INBREED: generations of more than 5000 individuals ({d}) are not implemented", .{k});
        const pf = struct {
            fn get(f: []const f64, w: usize, unk: f64, self_unk: f64, i: ?usize, j: ?usize) f64 {
                if (i == null or j == null) return unk;
                if (i.? < w and j.? < w) return f[i.? * w + j.?];
                return if (i.? == j.?) self_unk else unk;
            }
        }.get;
        const f = try a.alloc(f64, k * k);
        const inb = try a.alloc(f64, k);
        for (0..k) |x| {
            const ab = par.items[x];
            const fx = pf(prev_f, prev_w, unknown, self_unknown, ab[0], ab[1]);
            inb[x] = fx;
            f[x * k + x] = (1 + (if (std.math.isNan(fx)) 0 else fx)) / 2;
            for (0..x) |y| {
                const cd = par.items[y];
                const v = quarter(.{
                    pf(prev_f, prev_w, unknown, self_unknown, ab[0], cd[0]),
                    pf(prev_f, prev_w, unknown, self_unknown, ab[0], cd[1]),
                    pf(prev_f, prev_w, unknown, self_unknown, ab[1], cd[0]),
                    pf(prev_f, prev_w, unknown, self_unknown, ab[1], cd[1]),
                });
                f[x * k + y] = v;
                f[y * k + x] = v;
            }
        }
        // Family = same first parent and same second parent (Example 71.1:
        // individuals with parents 1,2 and 2,1 are not one family).
        const fam = struct {
            fn same(p: []const [2]?usize, x: usize, y: usize) bool {
                if (x == y) return true;
                const u = p[x];
                const w = p[y];
                if (u[0] == null or u[1] == null or w[0] == null or w[1] == null) return false;
                return u[0].? == w[0].? and u[1].? == w[1].?;
            }
        }.same;
        for (assigns.items) |as| {
            if (fam(par.items, as.x, as.y)) return gap(cx.diags, 0, "PROC INBREED: a covariance assignment within one family is not verified", .{});
            for (0..k) |x| {
                if (!fam(par.items, x, as.x)) continue;
                for (0..k) |y| {
                    if (!fam(par.items, y, as.y)) continue;
                    f[x * k + y] = as.f;
                    f[y * k + x] = as.f;
                }
            }
        }
        const sire = try a.alloc(?usize, k);
        const dam = try a.alloc(?usize, k);
        for (par.items, sire, dam) |pp, *x, *y| {
            x.* = pp[0];
            y.* = pp[1];
        }
        try gens.append(a, .{
            .label = try proc.cellText(a, .{ .num = gv }),
            .pop = .{ .names = names.items, .p1_text = p1t.items, .p2_text = p2t.items, .sire = sire, .dam = dam, .f = f, .inbreeding = inb },
        });
        prev_index = index;
        prev_f = f;
        prev_w = k;
        prev_extra = 0;
        r = end;
    }
    return gens.items;
}

/// Fw.4 with half-away rounding; missing as "." aligned on the decimal point.
fn cell(a: A, v: f64) ![]const u8 {
    if (std.math.isNan(v)) return ".    ";
    const scaled = @round(@abs(v) * 10000);
    const whole: u64 = @intFromFloat(@floor(scaled / 10000));
    const frac: u64 = @intFromFloat(scaled - @as(f64, @floatFromInt(whole)) * 10000);
    return std.fmt.allocPrint(a, "{s}{d}.{d:0>4}", .{ if (v < 0 and scaled != 0) "-" else "", whole, frac });
}
fn pad(a: A, out: *Out, n: usize) !void {
    for (0..n) |_| try out.append(a, ' ');
}
fn left(a: A, out: *Out, text: []const u8, w: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < w) try pad(a, out, w - text.len);
}
fn right(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try pad(a, out, w - text.len);
    try out.appendSlice(a, text);
}

fn header(a: A, out: *Out, ds: *Dataset, s: Spec, group: ?[]const Value, gen: ?[]const u8) !void {
    if (group) |row| try by.appendLine(a, out, ds, row, s.by_cols);
    try out.appendSlice(a, "\nThe INBREED Procedure\n\n");
    // ponytail: the generation line layout follows the User's Guide figures
    // (Figure 71.2), not a captured listing.
    if (gen) |g| try out.print(a, "{s} = {s}\n\n", .{ ds.columns.items[s.class_col.?].name, g });
}

/// Name-column widths: a character variable shows its first 12 characters
/// (min(length, 12)); a numeric one the widest value; never narrower than
/// its header.
fn nameWidths(ds: *Dataset, s: Spec, p: Population) [3]usize {
    var w: [3]usize = undefined;
    for ([_]usize{ s.ind_col, s.p1_col, s.p2_col }, 0..) |ci, k| {
        const col = ds.columns.items[ci];
        var width: usize = col.name.len;
        if (col.type == .char) {
            width = @max(width, @min(col.len orelse 8, 12));
        } else {
            const texts = switch (k) {
                0 => p.names,
                1 => p.p1_text,
                else => p.p2_text,
            };
            for (texts) |x| width = @max(width, x.len);
        }
        w[k] = width;
    }
    return w;
}

fn table(a: A, out: *Out, ds: *Dataset, s: Spec, p: Population, title: []const u8, labels: []const []const u8, widths: []const usize, row_cells: []const []const []const u8) !void {
    const nw = nameWidths(ds, s, p);
    var total: usize = nw[0] + nw[1] + nw[2] + 4 * 3;
    for (widths, 0..) |w, k| total += w + (if (k > 0) @as(usize, 4) else 0);
    try pad(a, out, if (total > title.len) (total - title.len) / 2 else 0);
    try out.appendSlice(a, title);
    try out.appendSlice(a, "\n \n");
    for ([_]usize{ s.ind_col, s.p1_col, s.p2_col }, 0..) |ci, k| {
        try left(a, out, ds.columns.items[ci].name, nw[k]);
        try pad(a, out, 4);
    }
    for (labels, widths, 0..) |l, w, k| {
        if (k > 0) try pad(a, out, 4);
        try right(a, out, l, w);
    }
    try out.appendSlice(a, "\n\n");
    for (0..p.n()) |r| {
        const nm = [3][]const u8{ p.names[r], p.p1_text[r], p.p2_text[r] };
        for (nm, 0..) |x, k| {
            try left(a, out, x, nw[k]);
            try pad(a, out, 4);
        }
        for (row_cells[r], widths, 0..) |c, w, k| {
            if (k > 0) try pad(a, out, 4);
            try right(a, out, c, w);
        }
        try out.append(a, '\n');
    }
}

/// `last`: this generation's number equals the last generation's (always
/// true without CLASS), so MATRIXL / INDL show their tables (reference runs,
/// SAS 9.4, 2026-11-28: other generations print only their header and
/// "Number of Individuals").
fn render(a: A, out: *Out, s: Spec, p: Population, group: ?[]const Value, gen: ?[]const u8, last: bool) !void {
    const ds = s.input.ds;
    const kind: []const u8 = if (s.covar) "Covariance" else "Inbreeding";
    const n = p.n();
    var any = false;
    if (s.matrix or (s.matrixl and last)) {
        try header(a, out, ds, s, group, gen);
        const widths = try a.alloc(usize, n);
        for (p.names, widths) |nm, *w| w.* = @max(8, nm.len);
        const rows = try a.alloc([]const []const u8, n);
        for (0..n) |i| {
            const r = try a.alloc([]const u8, n);
            for (0..n) |j| r[j] = try cell(a, p.value(s.covar, i, j));
            rows[i] = r;
        }
        try table(a, out, ds, s, p, try std.fmt.allocPrint(a, "{s} Coefficients", .{kind}), p.names, widths, rows);
        any = true;
    }
    if (s.ind or (s.indl and last)) {
        try header(a, out, ds, s, group, gen);
        const rows = try a.alloc([]const []const u8, n);
        for (0..n) |i| {
            const r = try a.alloc([]const u8, 1);
            r[0] = try cell(a, p.value(s.covar, i, i));
            rows[i] = r;
        }
        try table(a, out, ds, s, p, try std.fmt.allocPrint(a, "{s} Coefficients of Individuals", .{kind}), &.{"Coefficient"}, &.{12}, rows);
        any = true;
    }
    if (any) try out.appendSlice(a, "\n") else try header(a, out, ds, s, group, gen);
    if (any) try out.appendSlice(a, "\n");
    try out.print(a, "Number of Individuals    {d}\n", .{n});
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    // Reference run (SAS 9.4): an empty DATA= data set prints nothing.
    if (ds.rows.items.len == 0) return cx.diags.note(0, "No observations in data set {s}.", .{try lists.datasetName(a, ds)});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    var first: usize = 0;
    for (groups) |g| {
        defer first += g.rows.len;
        if (g.rows.len == 0) continue;
        const rep = if (s.by_cols.len > 0) g.rep else null;
        if (s.class_col != null) {
            const gens = try buildGenerations(cx, s, g.rows, first);
            if (s.noprint) continue;
            const last_label = if (gens.len > 0) gens[gens.len - 1].label else "";
            for (gens) |gen| if (gen.pop.n() > 0) try render(a, out, s, gen.pop, rep, gen.label, std.mem.eql(u8, gen.label, last_label));
            continue;
        }
        const p = try build(cx, s, g.rows, first);
        // A group whose observations all lack the individual prints nothing.
        if (s.noprint or p.n() == 0) continue;
        try render(a, out, s, p, rep, null, true);
    }
}

test {
    _ = @import("inbreed_tests.zig");
}
