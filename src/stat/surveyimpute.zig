//! PROC SURVEYIMPUTE declarations, variable roles, basic options and the
//! fully efficient fractional imputation (FEFI) of CLASS items with
//! delete-one-PSU jackknife replicate weights, SAS/STAT 15.4 physical
//! pp.9704-9725 (statements, Missing Values, Missing Data Patterns), the FEFI
//! algorithm pp.9726-9730 and the displayed output pp.9763-9765.
//!
//! Listing: Imputation Information, Number of Observations, Class Level
//! Information, Design Summary, Missing Data Patterns (with Group Means),
//! Donor Cell Counts, Iteration History, convergence line and Imputation
//! Summary. OUTPUT OUT= (UnitID, ImpIndex, ImpWt, imputed items) without
//! replication; with VARMETHOD=JACKKNIFE the OUTPUT statement (ImpRepWt_r,
//! OUTJKCOEFS=) stays a gap. Every other documented feature (hot-deck and
//! FHDI random draws, continuous items, CELLS, IMPJOINT, BRR/bootstrap,
//! REPWEIGHTS input, excluded observations, units left unimputed) is a D-009
//! gap (rc 2) raised before any listing text exists.
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
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    vars: []const usize = &.{},
    class: []const usize = &.{},
    strata: []const usize = &.{},
    clusters: []const usize = &.{},
    weight: ?usize = null,
    id: ?usize = null,
    jackknife: bool = false,
    noprint: bool = false,
    abs_conv: f64 = 0.00001,
    rel_conv: f64 = 0.001,
    max_iter: usize = 100,
    max_donor_cells: usize = 5000,
    out: ?[]const u8 = null,
    output_seen: bool = false,
    outjk: ?[]const u8 = null,
    name_impwt: []const u8 = "ImpWt",
    name_index: []const u8 = "ImpIndex",
    name_unit: []const u8 = "UnitID",
    name_frac: ?[]const u8 = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    line: usize = 0,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYIMPUTE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn userError(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC SURVEYIMPUTE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYIMPUTE: " ++ text, args);
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

fn dataName(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        if (!at(t, i.* + 1, .name)) return invalid(cx, t, i.* + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    if (at(t, i.*, .lparen)) return gap(cx, t[i.*].line, "data set options on an OUTPUT data set are not implemented", .{});
    return name;
}

fn roleColumns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, what: []const u8) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        if (at(t, j, .slash)) return gap(cx, t[j].line, "{s} statement options are not implemented", .{what});
        if (at(t, j, .lparen)) return gap(cx, t[j].line, "{s} variable options are not implemented", .{what});
        const line = t[j].line;
        const names = try lists.next(cx.arena, ds, t[0..end], &j, cx.diags);
        for (names) |n| try cols.append(cx.arena, ds.indexOf(n) orelse return userError(cx, line, "Variable {s} not found.", .{n}));
    }
    if (cols.items.len == 0) return invalid(cx, t, end);
    return cols.items;
}

fn appendNew(a: A, list: *std.ArrayList(usize), cols: []const usize) !void {
    for (cols) |c| if (std.mem.indexOfScalar(usize, list.items, c) == null) try list.append(a, c);
}

fn methodOptions(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, s: *Spec) diag.Error!void {
    // METHOD=FEFI(ABSEMWTCONV= MAXDONORCELLS= MAXEMITER= RELEMWTCONV=), p.9705.
    i.* += 1;
    while (!at(t, i.*, .rparen)) {
        if (!at(t, i.*, .name) or !at(t, i.* + 1, .eq)) return invalid(cx, t, i.*);
        const o = t[i.*].text;
        const line = t[i.*].line;
        i.* += 2;
        const x = try number(cx, t, i);
        if (eq(o, "absemwtconv")) {
            if (!(x > 0)) return userError(cx, line, "ABSEMWTCONV= must be a positive number", .{});
            s.abs_conv = x;
        } else if (eq(o, "relemwtconv")) {
            if (!(x > 0)) return userError(cx, line, "RELEMWTCONV= must be a positive number", .{});
            s.rel_conv = x;
        } else if (eq(o, "maxemiter") or eq(o, "maxdonorcells")) {
            if (!(x >= 1) or x != @floor(x)) return userError(cx, line, "{s}= must be a positive integer", .{o});
            if (eq(o, "maxemiter")) s.max_iter = @intFromFloat(x) else s.max_donor_cells = @intFromFloat(x);
        } else return invalid(cx, t, i.* - 3);
    }
    i.* += 1;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .line = lineOf(t, 0) };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var method_fefi: ?bool = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const line = t[i].line;
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
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "method") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            i += 3;
            if (eq(v, "fefi")) {
                method_fefi = true;
                if (at(t, i, .lparen)) try methodOptions(cx, t, &i, &s);
            } else if (oneOf(v, &.{ "fhdi", "hotdeck", "hd" })) {
                return gap(cx, line, "METHOD={s} (random donor selection) is not implemented", .{v});
            } else return userError(cx, line, "METHOD={s} is not a valid imputation method", .{v});
        } else if (eq(word, "varmethod") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            i += 3;
            if (oneOf(v, &.{ "jackknife", "jk" })) {
                if (at(t, i, .lparen)) return gap(cx, line, "VARMETHOD=JACKKNIFE method-options are not implemented", .{});
                s.jackknife = true;
            } else if (oneOf(v, &.{ "brr", "bootstrap" })) {
                return gap(cx, line, "VARMETHOD={s} replicate weights are not implemented", .{v});
            } else return userError(cx, line, "VARMETHOD={s} is not a valid variance estimation method", .{v});
        } else if (eq(word, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "data", "freq" })) return gap(cx, line, "ORDER={s} is not implemented", .{v});
            if (!oneOf(v, &.{ "internal", "formatted" })) return userError(cx, line, "ORDER={s} is not a valid sort order", .{v});
            i += 3;
        } else if (eq(word, "ndonors") and valued) {
            return gap(cx, line, "NDONORS= (hot-deck and FHDI donor selection) is not implemented", .{});
        } else if (eq(word, "seed") and valued) {
            // FEFI draws no random numbers; the seed is validated and unused.
            i += 2;
            const x = try number(cx, t, &i);
            if (x != @floor(x)) return userError(cx, line, "SEED= must be an integer", .{});
        } else if (oneOf(word, &.{ "rate", "r", "total", "n" }) and valued) {
            // Ignored for jackknife replicates (p.9709); data-set forms are gaps.
            if (!at(t, i + 2, .number)) return gap(cx, line, "{s}= with a data set is not implemented", .{word});
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x >= 0)) return userError(cx, line, "{s}= must be a nonnegative number", .{word});
            if (!s.jackknife) return gap(cx, line, "{s}= finite population correction for bootstrap replicates is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return userError(cx, s.line, "input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var class: std.ArrayList(usize) = .empty;
    var clusters: std.ArrayList(usize) = .empty;
    var strata_seen = false;
    var weight_seen = false;
    var var_seen = false;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const line = t[i].line;
        if (kw(t, i, "var")) {
            if (var_seen) return gap(cx, line, "several VAR statements are not implemented", .{});
            var_seen = true;
            try appendNew(cx.arena, &vars, try roleColumns(cx, ds, t, i + 1, end, "VAR"));
        } else if (kw(t, i, "class")) {
            try appendNew(cx.arena, &class, try roleColumns(cx, ds, t, i + 1, end, "CLASS"));
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            // Variables of all CLUSTER statements form the clusters (p.9715).
            try appendNew(cx.arena, &clusters, try roleColumns(cx, ds, t, i + 1, end, "CLUSTER"));
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            if (strata_seen) return gap(cx, line, "several STRATA statements are not implemented", .{});
            strata_seen = true;
            s.strata = try roleColumns(cx, ds, t, i + 1, end, "STRATA");
        } else if (kw(t, i, "weight")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            if (weight_seen) return gap(cx, line, "several WEIGHT statements are not implemented", .{});
            weight_seen = true;
            const c = ds.indexOf(t[i + 1].text) orelse return userError(cx, line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[c].type != .num) return userError(cx, line, "WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.weight = c;
        } else if (kw(t, i, "id")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return userError(cx, line, "the ID statement names exactly one variable", .{});
            if (s.id != null) return gap(cx, line, "several ID statements are not implemented", .{});
            s.id = ds.indexOf(t[i + 1].text) orelse return userError(cx, line, "Variable {s} not found.", .{t[i + 1].text});
        } else if (kw(t, i, "output")) {
            // Only the first OUTPUT statement is used (p.9716).
            if (!s.output_seen) try outputStatement(cx, t, i + 1, end, &s);
            s.output_seen = true;
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "repweights") or kw(t, i, "repweight")) {
            return gap(cx, line, "REPWEIGHTS statement (adjusting supplied replicate weights) is not implemented", .{});
        } else if (kw(t, i, "cells")) {
            return gap(cx, line, "CELLS statement (imputation cells) is not implemented", .{});
        } else if (kw(t, i, "impjoint")) {
            return gap(cx, line, "IMPJOINT statement (marginal or grouped imputation) is not implemented", .{});
        } else if (kw(t, i, "format")) {
            return gap(cx, line, "FORMAT statement (formatted levels) is not implemented", .{});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    // The PROC SURVEYIMPUTE and VAR statements are required (p.9703).
    if (!var_seen) return userError(cx, s.line, "a VAR statement is required", .{});
    s.vars = vars.items;
    s.class = class.items;
    s.clusters = clusters.items;
    for (s.vars) |c| if (std.mem.indexOfScalar(usize, s.class, c) == null) {
        // Default METHOD= is HOTDECK unless every VAR variable is CLASS (p.9705).
        if (method_fefi == null) return gap(cx, s.line, "METHOD=HOTDECK (the default when VAR variable {s} is not a CLASS variable) is not implemented", .{ds.columns.items[c].name});
        return gap(cx, s.line, "two-stage FEFI for the continuous VAR variable {s} is not implemented", .{ds.columns.items[c].name});
    };
    for (s.class) |c| if (std.mem.indexOfScalar(usize, s.vars, c) == null)
        return gap(cx, s.line, "CLASS variable {s} that is not a VAR variable (auxiliary IMPJOINT variable) is not implemented", .{ds.columns.items[c].name});
    for (s.vars) |c| if (ds.columns.items[c].format != null) return gap(cx, s.line, "formatted CLASS levels of {s} are not implemented", .{ds.columns.items[c].name});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

fn outputStatement(cx: proc.ProcCtx, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!void {
    var j = start;
    while (j < end) {
        if (!at(t, j, .name)) return invalid(cx, t, j);
        const o = t[j].text;
        const line = t[j].line;
        const valued = at(t, j + 1, .eq);
        if (eq(o, "out") and valued) {
            j += 2;
            s.out = try dataName(cx, t, &j);
        } else if (eq(o, "outjkcoefs") and valued) {
            j += 2;
            s.outjk = try dataName(cx, t, &j);
        } else if (oneOf(o, &.{ "fractionalweights", "impadjweights", "impindex", "obsid" })) {
            var v: ?[]const u8 = null;
            j += 1;
            if (valued) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                v = t[j + 1].text;
                j += 2;
            }
            if (eq(o, "fractionalweights")) {
                s.name_frac = v orelse return userError(cx, line, "FRACTIONALWEIGHTS= requires a variable name", .{});
            } else if (eq(o, "impadjweights")) {
                s.name_impwt = v orelse return userError(cx, line, "IMPADJWEIGHTS= requires a variable name", .{});
            } else if (eq(o, "impindex")) {
                if (v) |n| s.name_index = n;
            } else if (v) |n| s.name_unit = n;
        } else if (oneOf(o, &.{ "donorid", "impstatus", "outcontlevels" })) {
            return gap(cx, line, "OUTPUT keyword {s} is not implemented", .{o});
        } else return invalid(cx, t, j);
    }
}

// ---------------------------------------------------------------------------
// FEFI EM-by-weighting, pp.9726-9728.

pub const Em = struct {
    /// fractions[i][l]: fractional weight of donor cell l of unit i.
    fractions: [][]f64,
    abs: []const f64,
    rel: []const f64,
    converged: bool,
    /// The absolute criterion (not the relative one) stopped the run.
    by_abs: bool = false,
};

/// One EM run. `donors[i]` are the joint-cell keys of unit i (one key for a
/// complete respondent); `start` null initialises from the complete
/// respondents (step 1), otherwise from the given fractions (replicates).
/// Differences are measured on the fractionally adjusted weights w_i w_il.
pub fn em(a: A, donors: []const []const u64, complete: []const bool, w: []const f64, start: ?[]const []const f64, abs_conv: f64, rel_conv: f64, max_iter: usize) !Em {
    var q = std.AutoHashMap(u64, f64).init(a);
    const f = try a.alloc([]f64, donors.len);
    if (start) |st| {
        for (f, st) |*row, src| row.* = try a.dupe(f64, src);
    } else {
        var total: f64 = 0;
        for (donors, complete, w) |d, c, wi| if (c) {
            const e = try q.getOrPutValue(d[0], 0);
            e.value_ptr.* += wi;
            total += wi;
        };
        for (f, donors) |*row, d| {
            row.* = try a.alloc(f64, d.len);
            fill(row.*, d, &q);
        }
    }
    var abs_hist: std.ArrayList(f64) = .empty;
    var rel_hist: std.ArrayList(f64) = .empty;
    var converged = false;
    var by_abs = false;
    var it: usize = 0;
    while (it < max_iter) : (it += 1) {
        // M-step: joint probabilities from every unit's fractional rows (the
        // common normalising constant cancels in the E-step).
        q.clearRetainingCapacity();
        for (donors, f, w) |d, row, wi| for (d, row) |k, fl| {
            const e = try q.getOrPutValue(k, 0);
            e.value_ptr.* += wi * fl;
        };
        var max_abs: f64 = 0;
        var max_rel: f64 = 0;
        for (donors, f, w) |d, row, wi| {
            if (d.len == 1) continue;
            const old = try a.dupe(f64, row);
            fill(row, d, &q);
            for (old, row) |o, n| {
                max_abs = @max(max_abs, @abs(wi * n - wi * o));
                if (o > 0) max_rel = @max(max_rel, @abs(n - o) / o);
            }
        }
        try abs_hist.append(a, max_abs);
        try rel_hist.append(a, max_rel);
        if (max_abs < abs_conv or max_rel < rel_conv) {
            converged = true;
            by_abs = !(max_rel < rel_conv);
            break;
        }
    }
    return .{ .fractions = f, .abs = abs_hist.items, .rel = rel_hist.items, .converged = converged, .by_abs = by_abs };
}

fn fill(row: []f64, d: []const u64, q: *const std.AutoHashMap(u64, f64)) void {
    var sum: f64 = 0;
    for (d) |k| sum += q.get(k) orelse 0;
    if (!(sum > 0)) return;
    for (row, d) |*x, k| x.* = (q.get(k) orelse 0) / sum;
}

// ---------------------------------------------------------------------------
// Planning one BY group.

const Pattern = struct { observed: []const bool, freq: usize = 0, weight: f64 = 0, means: []f64 };
const DonorCount = struct { donors: usize, units: usize };

const Group = struct {
    rows: []const []const Value,
    first_obs: usize,
    levels: [][]Value,
    codes: [][]i32,
    weights: []f64,
    donors: [][]u64,
    patterns: []Pattern,
    donor_counts: []DonorCount,
    sum_w: f64,
    fit: Em,
    strata_n: usize,
    clusters_n: usize,
    replicates: [][][]f64,
    coefs: []f64,
    donor_stratum: []usize,
    missing_n: usize,
    missing_w: f64,
};

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}
fn lessValue(_: void, x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a < y.num,
        .str => |a| std.mem.order(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")) == .lt,
    };
}
fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a == y.num,
        .str => |a| std.mem.eql(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}
fn sameKey(row_a: []const Value, row_b: []const Value, cols: []const usize) bool {
    for (cols) |c| if (!sameValue(row_a[c], row_b[c])) return false;
    return true;
}
fn lessKey(row_a: []const Value, row_b: []const Value, cols: []const usize) bool {
    for (cols) |c| {
        if (sameValue(row_a[c], row_b[c])) continue;
        return lessValue({}, row_a[c], row_b[c]);
    }
    return false;
}

fn plan(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, first_obs: usize) diag.Error!Group {
    const a = cx.arena;
    const p = s.vars.len;
    var g: Group = undefined;
    g.rows = rows;
    g.first_obs = first_obs;
    const n = rows.len;
    if (n == 0) return gap(cx, s.line, "imputation of an empty input data set or BY group is not verified", .{});
    g.weights = try a.alloc(f64, n);
    for (rows, g.weights) |r, *w| {
        w.* = if (s.weight) |c| r[c].num else 1;
        if (!(w.* > 0)) return gap(cx, s.line, "observations excluded by a missing or nonpositive WEIGHT value are not implemented", .{});
        for (s.strata) |c| if (isMissing(r[c])) return gap(cx, s.line, "observations excluded by a missing STRATA value are not implemented", .{});
        for (s.clusters) |c| if (isMissing(r[c])) return gap(cx, s.line, "observations excluded by a missing CLUSTER value are not implemented", .{});
    }
    // Levels: ascending internal (unformatted) values, p.9708.
    g.levels = try a.alloc([]Value, p);
    for (s.vars, g.levels) |c, *lv| {
        var list: std.ArrayList(Value) = .empty;
        for (rows) |r| {
            if (isMissing(r[c])) continue;
            for (list.items) |x| {
                if (sameValue(x, r[c])) break;
            } else try list.append(a, r[c]);
        }
        std.mem.sort(Value, list.items, {}, lessValue);
        lv.* = list.items;
        if (lv.len == 0) return gap(cx, s.line, "a VAR variable without observed levels is not implemented", .{});
    }
    var radix = try a.alloc(u64, p);
    var span: u64 = 1;
    var j = p;
    while (j > 0) {
        j -= 1;
        radix[j] = span;
        span = std.math.mul(u64, span, g.levels[j].len) catch return gap(cx, s.line, "too many joint levels", .{});
    }
    g.codes = try a.alloc([]i32, n);
    const complete = try a.alloc(bool, n);
    for (rows, g.codes, complete) |r, *code, *done| {
        code.* = try a.alloc(i32, p);
        done.* = true;
        for (s.vars, code.*, g.levels) |c, *x, lv| {
            x.* = -1;
            if (isMissing(r[c])) {
                done.* = false;
                continue;
            }
            for (lv, 0..) |v, k| if (sameValue(v, r[c])) {
                x.* = @intCast(k);
            };
        }
    }
    // Donor cells: distinct joint cells of the complete respondents that agree
    // with the recipient's observed items, in level order (p.9727).
    var complete_keys: std.ArrayList(u64) = .empty;
    for (g.codes, complete) |code, done| if (done) {
        var k: u64 = 0;
        for (code, radix) |x, r| k += @as(u64, @intCast(x)) * r;
        if (std.mem.indexOfScalar(u64, complete_keys.items, k) == null) try complete_keys.append(a, k);
    };
    std.mem.sort(u64, complete_keys.items, {}, std.sort.asc(u64));
    g.donors = try a.alloc([]u64, n);
    var counts: std.ArrayList(DonorCount) = .empty;
    g.missing_n = 0;
    g.missing_w = 0;
    g.sum_w = 0;
    for (g.codes, complete, g.donors, g.weights) |code, done, *d, w| {
        g.sum_w += w;
        var list: std.ArrayList(u64) = .empty;
        if (done) {
            var k: u64 = 0;
            for (code, radix) |x, r| k += @as(u64, @intCast(x)) * r;
            try list.append(a, k);
        } else {
            g.missing_n += 1;
            g.missing_w += w;
            for (complete_keys.items) |k| {
                const ok = for (code, radix, g.levels) |x, r, lv| {
                    if (x >= 0 and (k / r) % lv.len != @as(u64, @intCast(x))) break false;
                } else true;
                if (ok) try list.append(a, k);
            }
            if (list.items.len == 0 or list.items.len > s.max_donor_cells)
                return gap(cx, s.line, "units left unimputed (no donor cell or more than MAXDONORCELLS= cells) are not implemented", .{});
        }
        d.* = list.items;
        const m: usize = if (done) 0 else list.items.len;
        for (counts.items) |*e| {
            if (e.donors == m) {
                e.units += 1;
                break;
            }
        } else try counts.append(a, .{ .donors = m, .units = 1 });
    }
    std.mem.sort(DonorCount, counts.items, {}, struct {
        fn f(_: void, x: DonorCount, y: DonorCount) bool {
            return x.donors < y.donors;
        }
    }.f);
    g.donor_counts = counts.items;
    try patterns(a, s, &g);
    g.fit = try em(a, g.donors, complete, g.weights, null, s.abs_conv, s.rel_conv, s.max_iter);
    if (!g.fit.converged) return gap(cx, s.line, "the listing when the EM algorithm does not converge within MAXEMITER= iterations is not verified", .{});
    try design(cx, s, &g, complete);
    return g;
}

fn patterns(a: A, s: Spec, g: *Group) !void {
    const p = s.vars.len;
    var list: std.ArrayList(Pattern) = .empty;
    var width: usize = 0;
    for (g.levels) |lv| width += lv.len;
    for (g.codes, g.weights) |code, w| {
        const pat = for (list.items) |*e| {
            const same = for (e.observed, code) |o, x| {
                if (o != (x >= 0)) break false;
            } else true;
            if (same) break e;
        } else blk: {
            const obs = try a.alloc(bool, p);
            for (obs, code) |*o, x| o.* = x >= 0;
            const means = try a.alloc(f64, width);
            @memset(means, 0);
            try list.append(a, .{ .observed = obs, .means = means });
            break :blk &list.items[list.items.len - 1];
        };
        pat.freq += 1;
        pat.weight += w;
        var off: usize = 0;
        for (code, g.levels) |x, lv| {
            if (x >= 0) pat.means[off + @as(usize, @intCast(x))] += w;
            off += lv.len;
        }
    }
    for (list.items) |*pat| for (pat.means) |*m| {
        m.* /= pat.weight;
    };
    // Groups: observed (X) before missing (.), variable by variable in VAR order.
    std.mem.sort(Pattern, list.items, {}, struct {
        fn f(_: void, x: Pattern, y: Pattern) bool {
            for (x.observed, y.observed) |ox, oy| if (ox != oy) return ox;
            return false;
        }
    }.f);
    g.patterns = list.items;
}

/// Delete-one-PSU jackknife (p.9744): replicate r drops PSU r of stratum h,
/// rescales the other PSUs of h by n_h/(n_h-1), coefficient (n_h-1)/n_h, and
/// reruns the EM from the full-sample fractions with the replicate weights.
fn design(cx: proc.ProcCtx, s: Spec, g: *Group, complete: []const bool) diag.Error!void {
    const a = cx.arena;
    const n = g.rows.len;
    const order = try a.alloc(usize, n);
    for (order, 0..) |*o, k| o.* = k;
    const Ctx = struct {
        rows: []const []const Value,
        strata: []const usize,
        clusters: []const usize,
        fn less(c: @This(), x: usize, y: usize) bool {
            if (!sameKey(c.rows[x], c.rows[y], c.strata)) return lessKey(c.rows[x], c.rows[y], c.strata);
            if (c.clusters.len == 0) return x < y;
            if (!sameKey(c.rows[x], c.rows[y], c.clusters)) return lessKey(c.rows[x], c.rows[y], c.clusters);
            return x < y;
        }
    };
    const ctx: Ctx = .{ .rows = g.rows, .strata = s.strata, .clusters = s.clusters };
    std.mem.sort(usize, order, ctx, Ctx.less);
    const stratum = try a.alloc(usize, n);
    const psu = try a.alloc(usize, n);
    var psu_stratum: std.ArrayList(usize) = .empty;
    var strata_n: usize = 0;
    for (order, 0..) |r, k| {
        const prev = if (k > 0) order[k - 1] else null;
        const new_stratum = prev == null or !sameKey(g.rows[r], g.rows[prev.?], s.strata);
        if (new_stratum) strata_n += 1;
        const new_psu = new_stratum or s.clusters.len == 0 or !sameKey(g.rows[r], g.rows[prev.?], s.clusters);
        if (new_psu) try psu_stratum.append(a, strata_n - 1);
        stratum[r] = strata_n - 1;
        psu[r] = psu_stratum.items.len - 1;
    }
    g.strata_n = strata_n;
    g.clusters_n = psu_stratum.items.len;
    // Clusters nested in strata: the same cluster value in two strata is two PSUs.
    g.replicates = &.{};
    g.coefs = &.{};
    g.donor_stratum = &.{};
    if (!s.jackknife) return;
    const per = try a.alloc(usize, strata_n);
    @memset(per, 0);
    for (psu_stratum.items) |h| per[h] += 1;
    for (per) |m| if (m < 2) return gap(cx, s.line, "jackknife replicates for a stratum with a single PSU are not implemented", .{});
    const R = psu_stratum.items.len;
    // ponytail: only the replicate count and coefficients are computed. The
    // replicate EM start rule is not settled: starting from the full-sample
    // initial fractions reproduces four of the six Figure 119.10 replicate
    // cells checked in surveyimpute_tests.zig but not all, so ImpRepWt_r
    // values are never written (OUTPUT with VARMETHOD=JACKKNIFE is a gap).
    g.replicates = try a.alloc([][]f64, R);
    g.coefs = try a.alloc(f64, R);
    g.donor_stratum = psu_stratum.items;
    for (0..R) |r| {
        const nh: f64 = @floatFromInt(per[psu_stratum.items[r]]);
        g.coefs[r] = (nh - 1) / nh;
        g.replicates[r] = &.{};
    }
    _ = complete;
}

// ---------------------------------------------------------------------------
// Listing.

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn fixed(a: A, x: f64, comptime decimals: u8) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
fn flush(a: A, out: *Out, b: []u8) !void {
    try proc.flush(a, out, b);
}
fn levelText(a: A, v: Value) ![]const u8 {
    return switch (v) {
        .num => |x| format.bestNum(a, x),
        .str => |t| std.mem.trim(u8, t, " "),
    };
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, g: Group) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const cols = ds.columns.items;
    try out.appendSlice(a, "\nThe SURVEYIMPUTE Procedure\n\n");
    // Imputation Information.
    {
        var labels: std.ArrayList([]const u8) = .empty;
        var values: std.ArrayList([]const u8) = .empty;
        const dn = try std.ascii.allocUpperString(a, ds.name);
        try labels.append(a, "Data Set");
        try values.append(a, if (std.mem.indexOfScalar(u8, dn, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{dn}) else dn);
        if (s.weight) |c| {
            try labels.append(a, "Weight Variable");
            try values.append(a, cols[c].name);
        }
        for ([_][]const usize{ s.strata, s.clusters }, [_][2][]const u8{ .{ "Stratum Variable", "Stratum Variables" }, .{ "Cluster Variable", "Cluster Variables" } }) |role, names| {
            for (role, 0..) |c, k| {
                try labels.append(a, if (k > 0) "" else if (role.len == 1) names[0] else names[1]);
                try values.append(a, cols[c].name);
            }
        }
        try labels.append(a, "Imputation Method");
        try values.append(a, "FEFI");
        if (s.jackknife) {
            try labels.append(a, "Replication Method");
            try values.append(a, "JACKKNIFE");
            try labels.append(a, "Number of Replicates");
            try values.append(a, try std.fmt.allocPrint(a, "{d}", .{g.replicates.len}));
        }
        var vw: usize = 0;
        for (values.items) |v| vw = @max(vw, v.len);
        try centered(a, out, "Imputation Information", 25 + vw);
        try out.append(a, '\n');
        for (labels.items, values.items) |l, v| {
            try out.appendSlice(a, l);
            try out.appendNTimes(a, ' ', 25 - l.len);
            try out.appendSlice(a, v);
            try out.appendNTimes(a, ' ', vw - v.len);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    // Number of Observations.
    {
        const nobs = try std.fmt.allocPrint(a, "{d}", .{g.rows.len});
        const sw = try format.bestNum(a, g.sum_w);
        for ([_][]const u8{ "Number of Observations Read", "Number of Observations Used", "Sum of Weights Read", "Sum of Weights Used" }, [_][]const u8{ nobs, nobs, sw, sw }, 0..) |l, v, k| {
            if (k >= 2 and s.weight == null) break;
            const b = try proc.line(a, 44);
            proc.putLeft(b, 1, l);
            proc.putRight(b, 44, v);
            try flush(a, out, b);
        }
        try out.appendSlice(a, "\n\n");
    }
    // Class Level Information.
    if (s.class.len > 0) {
        var nw: usize = 5;
        var vw: usize = 0;
        const texts = try a.alloc([]const u8, s.vars.len);
        for (s.vars, g.levels, texts) |c, lv, *tx| {
            nw = @max(nw, cols[c].name.len);
            var buf: Out = .empty;
            for (lv, 0..) |v, k| {
                if (k > 0) try buf.append(a, ' ');
                try buf.appendSlice(a, try levelText(a, v));
            }
            tx.* = buf.items;
            vw = @max(vw, buf.items.len + 1);
        }
        try centered(a, out, "Class Level Information", nw + 16 + vw);
        try out.appendSlice(a, " \n");
        var b = try proc.line(a, nw + 16 + vw);
        proc.putLeft(b, 1, "Class");
        proc.putRight(b, nw + 12, "Levels");
        proc.putLeft(b, nw + 17, "Values");
        try flush(a, out, b);
        try out.append(a, '\n');
        for (s.vars, g.levels, texts) |c, lv, tx| {
            b = try proc.line(a, nw + 16 + vw);
            proc.putLeft(b, 1, cols[c].name);
            proc.putRight(b, nw + 12, try std.fmt.allocPrint(a, "{d}", .{lv.len}));
            proc.putLeft(b, nw + 17, tx);
            try out.appendSlice(a, b);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    // Design Summary.
    if (s.strata.len > 0 or s.clusters.len > 0) {
        try centered(a, out, "Design Summary", 32);
        try out.append(a, '\n');
        if (s.strata.len > 0) try pairLine(a, out, "Number of Strata", g.strata_n);
        if (s.clusters.len > 0) try pairLine(a, out, "Number of Clusters", g.clusters_n);
        try out.appendSlice(a, "\n\n");
    }
    try renderPatterns(a, out, s, g);
    // Donor Cell Counts.
    {
        try out.appendSlice(a, "        Donor Cell Counts\n \n                           Total\n  Donors       Units        Rows\n\n");
        for (g.donor_counts) |dc| {
            const b = try proc.line(a, 32);
            proc.putRight(b, 8, try std.fmt.allocPrint(a, "{d}", .{dc.donors}));
            proc.putRight(b, 20, try std.fmt.allocPrint(a, "{d}", .{dc.units}));
            proc.putRight(b, 32, try std.fmt.allocPrint(a, "{d}", .{dc.units * @max(dc.donors, 1)}));
            try flush(a, out, b);
        }
        try out.appendSlice(a, "\n\n");
    }
    // Iteration History.
    {
        try out.appendSlice(a, "          Iteration History\n \n                Maximum       Maximum\nIteration      Absolute      Relative\n   Number    Difference    Difference\n\n");
        for (g.fit.abs, g.fit.rel, 1..) |ad, rd, k| {
            const b = try proc.line(a, 37);
            proc.putRight(b, 9, try std.fmt.allocPrint(a, "{d}", .{k}));
            proc.putRight(b, 23, try format.bestNumW(a, ad, 8));
            proc.putRight(b, 37, try fixed(a, rd, 5));
            try flush(a, out, b);
        }
        try out.appendSlice(a, "\n                     EM algorithm converged                     \n\n\n");
    }
    // Imputation Summary.
    {
        try out.appendSlice(a, "                Imputation Summary\n \n                           Number of        Sum of\nObservation Status      Observations       Weights\n\n");
        const done_n = g.rows.len - g.missing_n;
        const done_w = g.sum_w - g.missing_w;
        const rows = [_]struct { []const u8, usize, f64 }{
            .{ "Nonmissing", done_n, done_w }, .{ "Missing", g.missing_n, g.missing_w },
            .{ "", 0, 0 },                     .{ "Missing, Imputed", g.missing_n, g.missing_w },
            .{ "Missing, Not Imputed", 0, 0 },
        };
        for (rows) |r| {
            if (r[0].len == 0) {
                try out.append(a, '\n');
                continue;
            }
            const b = try proc.line(a, 50);
            proc.putLeft(b, 1, r[0]);
            proc.putRight(b, 36, try std.fmt.allocPrint(a, "{d}", .{r[1]}));
            proc.putRight(b, 50, try format.bestNum(a, r[2]));
            try flush(a, out, b);
        }
    }
}

fn pairLine(a: A, out: *Out, label: []const u8, v: usize) !void {
    const b = try proc.line(a, 32);
    proc.putLeft(b, 1, label);
    proc.putRight(b, 32, try std.fmt.allocPrint(a, "{d}", .{v}));
    try flush(a, out, b);
}

fn renderPatterns(a: A, out: *Out, s: Spec, g: Group) !void {
    const cols = s.input.ds.columns.items;
    // Pattern columns: Group (5), then each variable after 4 spaces, the X/.
    // mark centred; Freq +12, Sum of Weights +14, two percents +14 and +12.
    var edge: usize = 5;
    const starts = try a.alloc(usize, s.vars.len);
    for (s.vars, starts) |c, *st| {
        st.* = edge + 5;
        edge += 4 + cols[c].name.len;
    }
    const e_freq = edge + 12;
    const e_sw = e_freq + 14;
    const e_up = e_sw + 14;
    const width = e_up + 12;
    try centered(a, out, "Missing Data Patterns", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putRight(b, e_sw, "Sum of");
    proc.putRight(b, e_up, "Unweighted");
    proc.putRight(b, width, "Weighted");
    try flush(a, out, b);
    b = try proc.line(a, width);
    proc.putLeft(b, 1, "Group");
    for (s.vars, starts) |c, st| proc.putLeft(b, st, cols[c].name);
    proc.putRight(b, e_freq, "Freq");
    proc.putRight(b, e_sw, "Weights");
    proc.putRight(b, e_up, "Percent");
    proc.putRight(b, width, "Percent");
    try flush(a, out, b);
    try out.append(a, '\n');
    const n: f64 = @floatFromInt(g.rows.len);
    for (g.patterns, 1..) |pat, k| {
        b = try proc.line(a, width);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{k}));
        for (s.vars, starts, pat.observed) |c, st, o| proc.putLeft(b, st + (cols[c].name.len - 1) / 2, if (o) "X" else ".");
        proc.putRight(b, e_freq, try std.fmt.allocPrint(a, "{d}", .{pat.freq}));
        proc.putRight(b, e_sw, try format.bestNum(a, pat.weight));
        proc.putRight(b, e_up, try fixed(a, 100 * @as(f64, @floatFromInt(pat.freq)) / n, 2));
        proc.putRight(b, width, try fixed(a, 100 * pat.weight / g.sum_w, 2));
        try flush(a, out, b);
    }
    try out.append(a, '\n');
    // Group Means: one column per CLASS level, all of one width.
    var labels: std.ArrayList([]const u8) = .empty;
    var owner: std.ArrayList(usize) = .empty;
    for (s.vars, g.levels, 0..) |c, lv, j| for (lv) |v| {
        try labels.append(a, try std.fmt.allocPrint(a, "{s} {s}", .{ cols[c].name, try levelText(a, v) }));
        try owner.append(a, j);
    };
    var cw: usize = 8;
    for (labels.items) |l| cw = @max(cw, l.len);
    cw += 4;
    const mw = 5 + cw * labels.items.len;
    try centered(a, out, "Missing Data Patterns", mw);
    try out.appendSlice(a, " \n");
    {
        const span = mw - 9;
        const title = "Group Means";
        const right = (span - title.len) / 2;
        const left = span - title.len - right;
        try out.appendNTimes(a, ' ', 9);
        try out.appendNTimes(a, '-', left);
        try out.appendSlice(a, title);
        try out.appendNTimes(a, '-', right);
        try out.append(a, '\n');
    }
    b = try proc.line(a, mw);
    proc.putLeft(b, 1, "Group");
    for (labels.items, 1..) |l, k| proc.putRight(b, 5 + cw * k, l);
    try flush(a, out, b);
    try out.append(a, '\n');
    for (g.patterns, 1..) |pat, k| {
        b = try proc.line(a, mw);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{k}));
        for (pat.means, owner.items, 1..) |m, j, col| proc.putRight(b, 5 + cw * col, if (pat.observed[j]) try fixed(a, m, 6) else ".");
        try flush(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

// ---------------------------------------------------------------------------
// Output data sets.

fn outputs(cx: proc.ProcCtx, s: Spec, groups: []const Group) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.output_seen and s.jackknife) return gap(cx, s.line, "OUTPUT with VARMETHOD=JACKKNIFE (imputation-adjusted replicate weights ImpRepWt_r) is not implemented", .{});
    const R = if (groups.len > 0) groups[0].replicates.len else 0;
    for (groups) |g| if (g.replicates.len != R) return gap(cx, s.line, "BY groups with different numbers of jackknife replicates in one OUT= data set are not implemented", .{});
    if (s.output_seen) {
        const member = s.out orelse blk: {
            var k: usize = 1;
            while (true) : (k += 1) {
                const candidate = try std.fmt.allocPrint(a, "data{d}", .{k});
                if (cx.lib.find(candidate) == null) break :blk candidate;
            }
        };
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        // ponytail: column order UnitID ImpIndex ImpWt [FracWgt] inputs
        // ImpRepWt_r follows the users-guide listings (pp.9717, 9763), not a
        // PROC CONTENTS of a SAS run.
        if (s.id == null) _ = try o.addColumn(s.name_unit, .num);
        _ = try o.addColumn(s.name_index, .num);
        _ = try o.addColumn(s.name_impwt, .num);
        if (s.name_frac) |f| _ = try o.addColumn(f, .num);
        for (ds.columns.items) |c| {
            if (o.indexOf(c.name) != null) return gap(cx, s.line, "an input variable named like an OUTPUT variable ({s}) is not implemented", .{c.name});
            _ = try o.addColumnLike(c.name, c);
        }
        for (1..R + 1) |r| _ = try o.addColumn(try std.fmt.allocPrint(a, "ImpRepWt_{d}", .{r}), .num);
        const lead: usize = (if (s.id == null) @as(usize, 1) else 0) + 2 + @as(usize, if (s.name_frac != null) 1 else 0);
        for (groups) |g| for (g.rows, g.donors, g.fit.fractions, g.weights, 0..) |row, d, fr, w, i| {
            for (d, fr, 0..) |key, f, l| {
                const vals = try a.alloc(Value, o.columns.items.len);
                var k: usize = 0;
                if (s.id == null) {
                    vals[k] = .{ .num = @floatFromInt(g.first_obs + i + 1) };
                    k += 1;
                }
                const imputed = for (g.codes[i]) |x| {
                    if (x < 0) break true;
                } else false;
                vals[k] = .{ .num = if (imputed) @floatFromInt(l + 1) else 0 };
                vals[k + 1] = .{ .num = w * f };
                if (s.name_frac != null) vals[k + 2] = .{ .num = f };
                @memcpy(vals[lead .. lead + row.len], row);
                // Imputed items take the donor cell's levels.
                var rem = key;
                var radix: u64 = 1;
                for (g.levels) |lv| radix *= lv.len;
                for (s.vars, g.levels) |c, lv| {
                    radix /= lv.len;
                    const x = rem / radix;
                    rem %= radix;
                    vals[lead + c] = lv[@intCast(x)];
                }
                for (0..R) |r| vals[lead + row.len + r] = .{ .num = g.replicates[r][i][l] };
                try o.appendRow(vals);
            }
        };
        try cx.lib.put(member, o);
        try note(cx, member, o);
    }
    if (s.outjk) |member| {
        if (!s.jackknife) return gap(cx, s.line, "OUTJKCOEFS= without VARMETHOD=JACKKNIFE is not implemented", .{});
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        for (s.by_cols) |c| _ = try o.addColumnLike(ds.columns.items[c].name, ds.columns.items[c]);
        _ = try o.addColumn("Replicate", .num);
        _ = try o.addColumn("JKCoefficient", .num);
        if (s.strata.len > 0) _ = try o.addColumn("DonorStratum", .num);
        for (groups) |g| for (g.coefs, g.donor_stratum, 1..) |c, h, r| {
            const vals = try a.alloc(Value, o.columns.items.len);
            for (s.by_cols, 0..) |bc, k| vals[k] = g.rows[0][bc];
            const b = s.by_cols.len;
            vals[b] = .{ .num = @floatFromInt(r) };
            vals[b + 1] = .{ .num = c };
            if (s.strata.len > 0) vals[b + 2] = .{ .num = @floatFromInt(h + 1) };
            try o.appendRow(vals);
        };
        try cx.lib.put(member, o);
        try note(cx, member, o);
    }
}

fn note(cx: proc.ProcCtx, member: []const u8, o: *const Dataset) !void {
    const upper = try std.ascii.allocUpperString(cx.arena, member);
    const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
}

fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.input.srcobs != null) return gap(cx, s.line, "UnitID numbering for a WHERE- or OBS=-selected input is not implemented", .{});
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    var first: usize = 0;
    for (slices, groups) |slice, *g| {
        g.* = try plan(cx, s, slice.rows, first);
        first += slice.rows.len;
    }
    if (groups.len == 0) return gap(cx, s.line, "imputation of an empty input data set is not verified", .{});
    var body: Out = .empty;
    if (!s.noprint) for (groups) |g| {
        if (s.by_cols.len > 0) {
            try byLine(a, &body, ds, g.rows[0], s.by_cols);
        }
        try render(cx, &body, s, g);
    };
    try outputs(cx, s, groups);
    // ponytail: one NOTE for the step, worded after the first group's run.
    if (groups[0].fit.by_abs) {
        try cx.diags.note(s.line, "Convergence achieved; maximum absolute difference less than {d} for fractional weights for the EM algorithm.", .{s.abs_conv});
    } else try cx.diags.note(s.line, "Convergence achieved; maximum relative difference less than {d} for fractional weights for the EM algorithm.", .{s.rel_conv});
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("surveyimpute_tests.zig");
}
