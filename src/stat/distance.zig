//! PROC DISTANCE (SAS/STAT 15.4 ch.43): PROC statement options, VAR
//! measurement-level lists with STD= / WEIGHTS=, BY / FREQ / WEIGHT / ID /
//! COPY roles, observation selection, standardization and the OUT= proximity
//! matrix of the coordinate-distance methods (STAT-DISTANCE-001).
//!
//! PROC DISTANCE prints nothing; it always writes the OUT= data set (p.2757).
//! Rules verified against SAS listings (not only the chapter text):
//! - OUT= variable order: BY, COPY, ID, FREQ, WEIGHT, then the distances.
//! - An observation with FREQ < 1 / missing (or WEIGHT <= 0 / missing) is left
//!   out of the location/scale estimates only; its distances are still
//!   computed (the chapter text says they are set to missing; SAS does not).
//! - Standardization uses, per variable, every selected observation where
//!   that variable is not missing (NOMISS: only complete observations).
//! - A pair with no variable present in both observations is undefined:
//!   missing, or the UNDEF= value (also on the diagonal).
//! - SIZE distance = |sum w_j (x_j - y_j)| * sqrt(W) / sum w_j.
//! Everything else the cited pages define is a loud D-009 gap; no data set is
//! created for a step that hits one.
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

pub const Method = enum { euclid, sqeuclid, size, cityblock, chebychev, minkowski, power };
pub const VarDef = enum { df, n, wdf, weight };
pub const Level = enum { interval, ratio };
/// STD= methods with a closed-form scale. Location never matters for the
/// implemented (translation-invariant) distances, so only scales are kept.
pub const Std = enum { none, std, mean, range, midrange, sum, euclen, ustd, maxabs };

pub const Variable = struct { col: usize, level: Level, std: Std, weight: f64 };

pub const Spec = struct {
    input: proc.ProcInput,
    out: ?[]const u8 = null,
    method: Method = .euclid,
    p: f64 = 2,
    r: f64 = 2,
    square: bool = false,
    /// PREFIX=; null: "Dist" without ID, the bare ID values with ID (verified).
    prefix: ?[]const u8 = null,
    nostd: bool = false,
    nomiss: bool = false,
    undef: ?f64 = null,
    vardef: VarDef = .df,
    mult: f64 = 1,
    add: f64 = 0,
    vars: []const Variable = &.{},
    id: ?usize = null,
    copy: []const usize = &.{},
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
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC DISTANCE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
/// A signed number at t[i]; returns the index after it.
fn number(t: []const lex.Token, i: usize, into: *f64) ?usize {
    var j = i;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    } else if (at(t, j, .plus)) j += 1;
    if (!at(t, j, .number)) return null;
    into.* = sign * (std.fmt.parseFloat(f64, t[j].text) catch return null);
    return j + 1;
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
    if (at(t, j, .lparen)) return proc.failGap(cx.diags, t[i].line, "PROC DISTANCE: data set options on an output data set are not implemented", .{});
    into.* = name;
    return j;
}

const gap_methods = [_][]const u8{ "gower", "dgower", "cov", "corr", "dcorr", "sqcorr", "dsqcorr", "simratio", "disratio", "nonmetric", "canberra", "cosine", "dot", "overlap", "doverlap", "chisq", "chi", "phisq", "phi", "hamming", "match", "dmatch", "dsqmatch", "hamann", "rt", "ss1", "ss3", "dice", "rr", "blwnm", "k1", "jaccard", "djaccard" };
const gap_std = [_][]const u8{ "median", "iqr", "mad", "abw", "ahuber", "awave", "agk", "spacing", "l" };

fn parseMethod(cx: proc.ProcCtx, t: []const lex.Token, i: usize, s: *Spec) diag.Error!usize {
    const l = line(t, i);
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const w = t[i].text;
    const simple = [_]struct { []const u8, Method }{ .{ "euclid", .euclid }, .{ "sqeuclid", .sqeuclid }, .{ "size", .size }, .{ "cityblock", .cityblock }, .{ "chebychev", .chebychev } };
    for (simple) |m| if (eq(w, m[0])) {
        s.method = m[1];
        return i + 1;
    };
    if ((eq(w, "l") or eq(w, "power")) and at(t, i + 1, .lparen)) {
        var p: f64 = 0;
        var j = number(t, i + 2, &p) orelse return invalid(cx, t, i + 2);
        if (!(p > 0)) return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: the METHOD={s} power must be a positive number", .{w});
        s.p = p;
        s.r = p;
        if (eq(w, "power")) {
            if (!at(t, j, .comma)) return invalid(cx, t, j);
            var r: f64 = 0;
            j = number(t, j + 1, &r) orelse return invalid(cx, t, j + 1);
            if (!(r > 0)) return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: the METHOD=POWER root must be a positive number", .{});
            s.r = r;
            s.method = .power;
        } else s.method = .minkowski;
        if (!at(t, j, .rparen)) return invalid(cx, t, j);
        return j + 1;
    }
    for (gap_methods) |m| if (eq(w, m)) return proc.failGap(cx.diags, l, "PROC DISTANCE: METHOD={s} is not implemented (STAT-DISTANCE-003)", .{w});
    return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: METHOD={s} is not a valid proximity method", .{w});
}

fn parseStd(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!Std {
    const l = line(t, i);
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const w = t[i].text;
    inline for (@typeInfo(Std).@"enum".fields) |f| {
        if (!std.mem.eql(u8, f.name, "none") and eq(w, f.name)) {
            if (at(t, i + 1, .lparen)) return invalid(cx, t, i + 1);
            return @enumFromInt(f.value);
        }
    }
    for (gap_std) |m| if (eq(w, m)) return proc.failGap(cx.diags, l, "PROC DISTANCE: STD={s} is not implemented (STAT-STDIZE methods; STAT-DISTANCE-003)", .{w});
    return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: STD={s} is not a valid standardization method", .{w});
}

/// `VAR level (variables </ options>) ...` (pp.2742-2746).
fn parseVar(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, into: *std.ArrayList(Variable), explicit: *bool) diag.Error!void {
    const a = cx.arena;
    const gap = proc.failGap;
    var i = start;
    if (i == end) return invalid(cx, t, i);
    while (i < end) {
        const l = line(t, i);
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const level: Level = if (eq(word, "interval")) .interval else if (eq(word, "ratio")) .ratio else if (eq(word, "ordinal") or eq(word, "nominal") or eq(word, "anominal"))
            return gap(cx.diags, l, "PROC DISTANCE: the {s} level of measurement is not implemented (STAT-DISTANCE-003)", .{word})
        else
            return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: {s} is not a level of measurement (ANOMINAL, NOMINAL, ORDINAL, INTERVAL or RATIO)", .{word});
        if (!at(t, i + 1, .lparen)) return invalid(cx, t, i + 1);
        const close = proc.skipParen(t, i + 1) - 1;
        if (close > end or !at(t, close, .rparen)) return invalid(cx, t, i + 1);
        var slash = i + 2;
        while (slash < close and !at(t, slash, .slash)) slash += 1;
        const names = t[i + 2 .. slash];
        if (names.len == 0) return invalid(cx, t, slash);
        var cols: std.ArrayList(usize) = .empty;
        var j: usize = 0;
        while (j < names.len) {
            const nl = names[j].line;
            for (try lists.next(a, ds, names, &j, cx.diags)) |n| {
                const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, nl, "PROC DISTANCE: variable {s} in the VAR statement is not on the input data set", .{n});
                if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, nl, "PROC DISTANCE: variable {s} has the {s} level of measurement and must be numeric", .{ n, word });
                for (into.items) |v| if (v.col == ci) return cx.diags.fail(error.ParseError, nl, "PROC DISTANCE: variable {s} appears more than once in the VAR statement", .{n});
                if (has(cols.items, ci)) return cx.diags.fail(error.ParseError, nl, "PROC DISTANCE: variable {s} appears more than once in the VAR statement", .{n});
                try cols.append(a, ci);
            }
        }
        var std_m: Std = .none;
        var weights: std.ArrayList(f64) = .empty;
        if (slash < close) {
            var k = slash + 1;
            while (k < close) {
                const ol = line(t, k);
                if (!at(t, k, .name) or !at(t, k + 1, .eq)) return invalid(cx, t, k);
                const opt = t[k].text;
                if (eq(opt, "std")) {
                    std_m = try parseStd(cx, t, k + 2);
                    explicit.* = true;
                    k += 3;
                } else if (eq(opt, "weights") or eq(opt, "weight")) {
                    k += 2;
                    while (k < close) {
                        if (at(t, k, .comma)) {
                            k += 1;
                            continue;
                        }
                        var w: f64 = 0;
                        var next = number(t, k, &w) orelse break;
                        if (!(w >= 0)) return gap(cx.diags, ol, "PROC DISTANCE: a negative WEIGHTS= value is not verified against SAS output", .{});
                        if (kw(t, next, "to")) {
                            // p.2746: start TO stop BY increment (verified: 1 to 2 by 1 = 1 2).
                            var stop: f64 = 0;
                            var inc: f64 = 0;
                            const after_stop = number(t, next + 1, &stop) orelse return invalid(cx, t, next + 1);
                            if (!kw(t, after_stop, "by")) return invalid(cx, t, after_stop);
                            next = number(t, after_stop + 1, &inc) orelse return invalid(cx, t, after_stop + 1);
                            if (!(inc > 0) or !(stop >= w)) return gap(cx.diags, ol, "PROC DISTANCE: a WEIGHTS= TO/BY list that does not increase is not verified against SAS output", .{});
                            var m: f64 = 0;
                            while (w + m * inc <= stop + 1e-9 * inc) : (m += 1) try weights.append(a, w + m * inc);
                        } else try weights.append(a, w);
                        k = next;
                    }
                    if (weights.items.len == 0) return cx.diags.fail(error.ParseError, ol, "PROC DISTANCE: WEIGHTS= needs at least one weight", .{});
                } else if (eq(opt, "missing") or eq(opt, "absent") or eq(opt, "order")) {
                    return gap(cx.diags, ol, "PROC DISTANCE: the VAR {s}= option is not implemented (STAT-DISTANCE-003)", .{opt});
                } else return invalid(cx, t, k);
            }
        }
        if (level == .interval) switch (std_m) {
            .sum, .euclen, .ustd, .maxabs => return cx.diags.fail(error.ParseError, l, "Standardization methods such as SUM, EUCLEN, USTD or MAXABS are invalid for standardizing variables with interval level of measurement.", .{}),
            else => {},
        };
        for (cols.items, 0..) |ci, k| {
            // p.2746: the last weight serves the remaining variables; extra weights are discarded.
            const w: f64 = if (weights.items.len == 0) 1 else weights.items[@min(k, weights.items.len - 1)];
            try into.append(a, .{ .col = ci, .level = level, .std = std_m, .weight = w });
        }
        i = close + 1;
    }
}

fn oneVar(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, numeric: bool) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC DISTANCE: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    const want: @TypeOf(ds.columns.items[ci].type) = if (numeric) .num else .char;
    if (ds.columns.items[ci].type != want) return cx.diags.fail(error.ParseError, t[i].line, "PROC DISTANCE: variable {s} in the {s} statement must be {s}", .{ t[i + 1].text, role, if (numeric) @as([]const u8, "numeric") else "character" });
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
        const l = t[i].line;
        const option = try std.ascii.allocLowerString(a, t[i].text);
        // Verified (SAS 9.4 run): a repeated METHOD= or PREFIX= keeps the last value.
        const last_wins = eq(option, "method") or eq(option, "prefix");
        if ((try seen.getOrPut(a, option)).found_existing and !last_wins) return gap(cx.diags, l, "PROC DISTANCE: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            name = t[first].text;
            var j = first + 1;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[first].text, t[j + 1].text });
                qualified = first;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &s.out);
        } else if (eq(option, "method") and valued) {
            i = try parseMethod(cx, t, i + 2, &s);
        } else if (eq(option, "shape") and valued) {
            if (kw(t, i + 2, "triangle") or kw(t, i + 2, "tri")) s.square = false else if (kw(t, i + 2, "square") or kw(t, i + 2, "squ") or kw(t, i + 2, "sqr")) s.square = true else return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: SHAPE= must be TRIANGLE, TRI, SQUARE, SQU or SQR", .{});
            i += 3;
        } else if (eq(option, "prefix") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: PREFIX= must be a name", .{});
            s.prefix = t[i + 2].text;
            i += 3;
        } else if ((eq(option, "undef") or eq(option, "mult") or eq(option, "add") or eq(option, "fuzz")) and valued) {
            var v: f64 = 0;
            i = number(t, i + 2, &v) orelse return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: {s}= must be a number", .{t[i].text});
            if (eq(option, "undef")) s.undef = v else if (eq(option, "mult")) s.mult = v else if (eq(option, "add")) s.add = v else if (!(v >= 0)) return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: FUZZ= must be nonnegative", .{});
            // FUZZ= only rounds the OUTSDZ= scores (p.2736), which are a gap below.
        } else if (eq(option, "vardef") and valued) {
            s.vardef = if (kw(t, i + 2, "df")) .df else if (kw(t, i + 2, "n")) .n else if (kw(t, i + 2, "wdf")) .wdf else if (kw(t, i + 2, "weight") or kw(t, i + 2, "wgt")) .weight else return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            i += 3;
        } else if (valued and (eq(option, "absent") or eq(option, "initial") or eq(option, "rankscore") or eq(option, "outsdz"))) {
            return gap(cx.diags, l, "PROC DISTANCE: the {s}= option is not implemented (STAT-DISTANCE-003/004)", .{t[i].text});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "nostd")) {
            s.nostd = true;
            i += 1;
        } else if (eq(option, "nomiss")) {
            s.nomiss = true;
            i += 1;
        } else if (eq(option, "norm") or eq(option, "snorm")) {
            // Only rescale AGK/IQR/MAD/SPACING (pp.2740-2742), which are gaps.
            i += 1;
        } else if (eq(option, "replace") or eq(option, "reponly") or eq(option, "stdonly")) {
            return gap(cx.diags, l, "PROC DISTANCE: the {s} option is not implemented (STAT-DISTANCE-003)", .{t[i].text});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC DISTANCE: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList(Variable) = .empty;
    var copy: std.ArrayList(usize) = .empty;
    var var_seen = false;
    var explicit_std = false;
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
            // p.2747: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            // Verified (SAS 9.4 run): several VAR statements add their lists together.
            var_seen = true;
            try parseVar(cx, ds, t, i + 1, end, &vars, &explicit_std);
        } else if (eq(word, "id")) {
            if (s.id != null) return gap(cx.diags, t[i].line, "PROC DISTANCE: more than one ID statement is not verified", .{});
            s.id = try oneVar(cx, ds, t, i, end, "ID", false);
        } else if (eq(word, "copy")) {
            if (end == i + 1) return invalid(cx, t, end);
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                for (try lists.next(a, ds, body, &j, cx.diags)) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC DISTANCE: variable {s} in the COPY statement is not on the input data set", .{n});
                    if (!has(copy.items, ci)) try copy.append(a, ci);
                }
            }
        } else if (eq(word, "freq") or eq(word, "frequency")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC DISTANCE: more than one FREQ statement is not verified", .{});
            s.freq = try oneVar(cx, ds, t, i, end, "FREQ", true);
        } else if (eq(word, "weight") or eq(word, "wgt")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC DISTANCE: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneVar(cx, ds, t, i, end, "WEIGHT", true);
        } else if (eq(word, "format")) {
            return gap(cx.diags, t[i].line, "PROC DISTANCE: a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // p.2735: both the PROC DISTANCE and the VAR statement are required.
    if (!var_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC DISTANCE: the VAR statement is required", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.copy = copy.items;

    // pp.2744, 2730: standardization is mandatory with more than one level;
    // the default method is then STD. NOSTD suppresses it.
    var mixed = false;
    for (vars.items) |v| if (v.level != vars.items[0].level) {
        mixed = true;
    };
    if (s.nostd) {
        for (vars.items) |*v| v.std = .none;
    } else if (mixed) {
        for (vars.items) |*v| if (v.std == .none) {
            v.std = .std;
        };
    }
    s.vars = vars.items;
    return s;
}

/// Scale of one variable over the selected observations (p.2748 formulas).
/// Returns null when the scale is zero or undefined.
fn scale(s: Spec, v: Variable, rows: []const []const Value, use: []const bool) ?f64 {
    var n: f64 = 0;
    var sw: f64 = 0;
    var swx: f64 = 0;
    var swxx: f64 = 0;
    var lo = std.math.inf(f64);
    var hi = -std.math.inf(f64);
    var maxabs: f64 = 0;
    for (rows, use) |row, u| {
        if (!u) continue;
        const x = row[v.col].num;
        if (std.math.isNan(x)) continue;
        const f: f64 = if (s.freq) |ci| @floor(row[ci].num) else 1;
        const w: f64 = if (s.weight) |ci| row[ci].num else 1;
        n += f;
        sw += f * w;
        swx += f * w * x;
        swxx += f * w * x * x;
        lo = @min(lo, x);
        hi = @max(hi, x);
        maxabs = @max(maxabs, @abs(x));
    }
    if (n == 0) return null;
    const d: f64 = switch (s.vardef) {
        .df => n - 1,
        .n => n,
        .wdf => sw - 1,
        .weight => sw,
    };
    const result: f64 = switch (v.std) {
        .none, .mean => 1,
        .std => blk: {
            const mean = swx / sw;
            var css: f64 = 0;
            for (rows, use) |row, u| {
                if (!u or std.math.isNan(row[v.col].num)) continue;
                const f: f64 = if (s.freq) |ci| @floor(row[ci].num) else 1;
                const w: f64 = if (s.weight) |ci| row[ci].num else 1;
                const dx = row[v.col].num - mean;
                css += f * w * dx * dx;
            }
            if (!(d > 0)) return null;
            break :blk @sqrt(css / d);
        },
        .range => hi - lo,
        .midrange => (hi - lo) / 2,
        .sum => swx,
        .euclen => @sqrt(swxx),
        .ustd => if (d > 0) @sqrt(swxx / d) else return null,
        .maxabs => maxabs,
    };
    if (!(result > 0) or std.math.isInf(result)) return null;
    return result;
}

/// The proximity between two standardized observations (pp.2750-2751), or
/// null when undefined (no variable present in both).
pub fn proximity(s: Spec, x: []const f64, y: []const f64) ?f64 {
    var total: f64 = 0; // W: every variable weight, missing or not
    var sw: f64 = 0;
    var acc: f64 = 0;
    for (s.vars, x, y) |v, xj, yj| {
        total += v.weight;
        if (std.math.isNan(xj) or std.math.isNan(yj)) continue;
        const w = v.weight;
        const dj = xj - yj;
        sw += w;
        switch (s.method) {
            .euclid, .sqeuclid => acc += w * dj * dj,
            .cityblock => acc += w * @abs(dj),
            .size => acc += w * dj,
            .chebychev => acc = @max(acc, w * @abs(dj)),
            .minkowski, .power => acc += w * std.math.pow(f64, @abs(dj), s.p),
        }
    }
    if (!(sw > 0)) return null;
    const adj = total / sw;
    return switch (s.method) {
        .euclid => @sqrt(acc * adj),
        .sqeuclid => acc * adj,
        .cityblock => acc * adj,
        .size => @abs(acc) * @sqrt(total) / sw,
        .chebychev => acc,
        .minkowski, .power => std.math.pow(f64, acc * adj, 1 / s.r),
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    _ = out; // p.2757: PROC DISTANCE displays no output.
    const a = cx.arena;
    const gap = proc.failGap;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    // p.2740: without OUT= the data set follows the DATAn convention (verified:
    // DATA1, then DATA2). ponytail: the first unused WORK.DATAn, not a session counter.
    const member = s.out orelse blk: {
        var k: usize = 1;
        while (cx.lib.find(try std.fmt.allocPrint(a, "DATA{d}", .{k})) != null) k += 1;
        break :blk try std.fmt.allocPrint(a, "DATA{d}", .{k});
    };
    // Verified: the distance names use the unformatted ID values even when
    // the ID variable has a format (the column keeps its format).
    var any_std = false;
    for (s.vars) |v| {
        if (v.std != .none) any_std = true;
    }
    // Verified (SAS 9.4 run): with NOSTD, MULT= still multiplies every value
    // (distances scale by MULT=); without NOSTD and without standardization
    // (one level, no STD=) MULT= and ADD= have no effect.
    const nostd_mult: f64 = if (!any_std and s.nostd) s.mult else 1;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);

    // Distance variable names: PREFIX= plus 1..n or plus the ID values.
    var names: std.ArrayList([]const u8) = .empty;
    var width: usize = 0;
    // Verified: the matrix width is the first BY group's size; a smaller
    // later group is padded with all-missing rows carrying its BY values and
    // the first group's ID value at that position.
    // Verified (SAS 9.4 run): a later BY group larger than the first widens the
    // matrix to the largest group, and every smaller group (the first one too)
    // is padded; padded rows carry the BY values, blank/missing COPY, FREQ and
    // WEIGHT values and missing distances even with UNDEF=.
    if (groups.len > 0) width = groups[0].rows.len;
    if (s.by_cols.len > 0 and groups.len == 0 and (s.copy.len > 0 or s.id != null or s.freq != null or s.weight != null))
        return gap(cx.diags, l0, "PROC DISTANCE: an empty input data set with a BY statement and COPY, ID, FREQ or WEIGHT is not verified against SAS output", .{});
    for (groups) |g| {
        if (g.rows.len > width) {
            if (s.id != null) return gap(cx.diags, l0, "PROC DISTANCE: an ID statement with a BY group larger than the first BY group is not verified against SAS output", .{});
            width = g.rows.len;
        }
    }
    const id_text = try a.alloc([]const u8, width);
    var raw_ids: std.ArrayList([]const u8) = .empty;
    for (0..width) |k| {
        const nm = if (s.id) |ci| blk: {
            const text = std.mem.trim(u8, groups[0].rows[k][ci].str, " ");
            id_text[k] = groups[0].rows[k][ci].str;
            for (groups[1..]) |g| if (k < g.rows.len and !std.mem.eql(u8, std.mem.trim(u8, g.rows[k][ci].str, " "), text))
                return cx.diags.fail(error.ParseError, l0, "The ID variable must have the same values in the same order in each BY group.", .{});
            if (text.len == 0) return cx.diags.fail(error.ParseError, l0, "The ID variable contains at least one missing value. No distance matrix will be created.", .{});
            if (s.prefix == null and std.ascii.isDigit(text[0])) return gap(cx.diags, l0, "PROC DISTANCE: an ID value starting with a digit and no PREFIX= is not verified against SAS output", .{});
            for (text) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return gap(cx.diags, l0, "PROC DISTANCE: ID value '{s}' is not a valid name suffix; the naming rule is not verified", .{text});
            // Verified: a repeated ID value gets the suffix 2 (a, b, c, a2, b2).
            var seen_before: usize = 0;
            for (raw_ids.items) |o| {
                if (std.mem.eql(u8, o, text)) seen_before += 1 else if (eq(o, text)) return gap(cx.diags, l0, "PROC DISTANCE: ID values differing only in case are not verified against SAS output", .{});
            }
            try raw_ids.append(a, text);
            if (seen_before > 1) return gap(cx.diags, l0, "PROC DISTANCE: an ID value repeated more than twice is not verified against SAS output", .{});
            const pre = s.prefix orelse "";
            break :blk if (seen_before == 1) try std.fmt.allocPrint(a, "{s}{s}2", .{ pre, text }) else try std.fmt.allocPrint(a, "{s}{s}", .{ pre, text });
        } else try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix orelse "Dist", k + 1 });
        if (nm.len > 32) return gap(cx.diags, l0, "PROC DISTANCE: distance variable name {s} is longer than 32 characters", .{nm});
        for (names.items) |o| if (eq(o, nm)) return gap(cx.diags, l0, "PROC DISTANCE: distance variable name {s} collides with another; the rule is not verified", .{nm});
        try names.append(a, nm);
    }

    // OUT= layout (verified): BY, COPY, ID, FREQ, WEIGHT, distances.
    var carried: std.ArrayList(usize) = .empty;
    for (s.by_cols) |ci| try carried.append(a, ci);
    for (s.copy) |ci| if (!has(carried.items, ci)) try carried.append(a, ci);
    for ([_]?usize{ s.id, s.freq, s.weight }) |opt| if (opt) |ci| if (!has(carried.items, ci)) try carried.append(a, ci);
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, member);
    for (carried.items) |ci| _ = try o.addColumnLike(ds.columns.items[ci].name, ds.columns.items[ci]);
    for (names.items) |nm| {
        if (o.indexOf(nm) != null) return gap(cx.diags, l0, "PROC DISTANCE: distance variable {s} collides with a carried variable; the rule is not verified", .{nm});
        _ = try o.addColumn(nm, .num);
    }
    // STAT-COMMON-019: every implemented method (Table 43.3 coordinate
    // distances) is a dissimilarity, so OUT= is TYPE=DISTANCE (p.2757); the
    // TYPE=SIMILAR methods are gaps, so no similarity matrix is ever labelled.
    o.ds_type = "DISTANCE";

    const p = s.vars.len;
    for (groups) |g| {
        const n = g.rows.len;
        // Observations entering location/scale estimates (pp.2748, 2756).
        const use = try a.alloc(bool, n);
        const complete = try a.alloc(bool, n);
        for (g.rows, use, complete) |row, *u, *c| {
            c.* = true;
            for (s.vars) |v| if (std.math.isNan(row[v.col].num)) {
                c.* = false;
            };
            const f: f64 = if (s.freq) |ci| row[ci].num else 1;
            const w: f64 = if (s.weight) |ci| row[ci].num else 1;
            u.* = f >= 1 and w > 0 and (!s.nomiss or c.*);
        }
        const scales = try a.alloc(f64, p);
        for (s.vars, scales) |v, *sc| {
            if (v.std == .none) {
                sc.* = 1 / nostd_mult;
                continue;
            }
            sc.* = scale(s, v, g.rows, use) orelse {
                // Verified (SAS 9.4 run, STD=STD on a constant variable): two
                // WARNINGs and no OUT= data set. ponytail: the scale is treated
                // as undefined when zero or not computable, like the constant case.
                const vn = ds.columns.items[v.col].name;
                if (s.by_cols.len > 0) return gap(cx.diags, l0, "PROC DISTANCE: a zero or undefined scale for variable {s} inside a BY group is not verified against SAS output", .{vn});
                try cx.diags.warnStatus(l0, "The scale estimator for variable {s} is less than or equal to 0.  {s} will not be standardized.", .{ vn, vn });
                try cx.diags.warnStatus(l0, "Because some variables can not be standardized, PROC DISTANCE will not compute the distance matrix. Choose other standardization methods for those variables.", .{});
                try cx.diags.note(l0, "OUT= data set is not created.", .{});
                return;
            };
            if (v.std != .none) sc.* /= s.mult;
        }
        const z = try a.alloc(f64, n * p);
        for (g.rows, 0..) |row, r| for (s.vars, 0..) |v, j| {
            z[r * p + j] = row[v.col].num / scales[j];
        };
        for (g.rows, 0..) |row, r| {
            const values = try a.alloc(Value, o.columns.items.len);
            @memset(values, Value.missing);
            for (carried.items, 0..) |ci, k| values[k] = row[ci];
            for (0..n) |c| {
                const slot = &values[carried.items.len + c];
                if (!s.square and c > r) {
                    slot.* = Value.missing;
                    continue;
                }
                const d: ?f64 = if (s.nomiss and (!complete[r] or !complete[c])) null else proximity(s, z[r * p .. (r + 1) * p], z[c * p .. (c + 1) * p]);
                slot.* = if (d) |v| .{ .num = v } else if (s.undef) |u| .{ .num = u } else Value.missing;
            }
            try o.appendRow(values);
        }
        for (n..width) |k| {
            const values = try a.alloc(Value, o.columns.items.len);
            @memset(values, Value.missing);
            for (carried.items, 0..) |ci, c| {
                if (has(s.by_cols, ci)) values[c] = g.rows[0][ci] else if (s.id == ci) values[c] = .{ .str = id_text[k] } else if (ds.columns.items[ci].type != .num) values[c] = .{ .str = "" };
            }
            try o.appendRow(values);
        }
    }
    try cx.lib.put(member, o);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    const upper = try std.ascii.allocUpperString(a, member);
    const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, o.rows.items.len, o.columns.items.len });
}

test {
    _ = @import("distance_tests.zig");
}
