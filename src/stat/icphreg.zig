//! PROC ICPHREG declarations, variable roles, observation selection and the
//! piecewise-constant proportional hazards listing (STAT-ICPHREG-001),
//! SAS/STAT 15.4 physical pp.5207-5214, 5217-5218, 5221, 5223-5224,
//! 5228-5229 and 5246; the likelihood is the full likelihood of "Model and
//! Likelihood" (p.5230).
//!
//! Implemented: DATA=, ALPHA=, NAMELEN=, NOPRINT, THREADS=/NOTHREADS; CLASS
//! (with the DESCENDING option); MODEL (lower, upper) = main effects /
//! BASEHAZ=PCH(INTERVALS=(list)); BY; ID; HAZARDRATIO for a two-level CLASS
//! effect without options. The fit is a Newton-Raphson maximisation of the
//! full likelihood over the baseline hazards and the GLM-coded effects.
//!
//! Fail loud (D-009, rc 2), owned by later ICPHREG tickets: the default
//! (NINTERVAL=) break-point placement, estimates that reach the hazard lower
//! bound ("Fixed Parameters"), ITHISTORY, exact (lower = upper) responses,
//! FREQ and STRATA listings, and every other documented option/statement.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const class_levels = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const lists = @import("variable_lists.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    lower: usize = 0,
    upper: usize = 0,
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    class_desc: bool = false,
    /// Interior break points of BASEHAZ=PCH(INTERVALS=); null = not given.
    intervals: ?[]const f64 = null,
    hazard_ratios: []const usize = &.{},
    freq: ?usize = null,
    strata: []const usize = &.{},
    strata_missing: bool = false,
    ids: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    alpha: f64 = 0.05,
    namelen: usize = 20,
    noprint: bool = false,
    ithistory: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC ICPHREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC ICPHREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Table 70.2 options owned by later ICPHREG tickets.
const later_options = [_][]const u8{ "nloptions", "plots", "plot", "singular" };
/// Documented statements owned by later ICPHREG tickets.
const later_statements = [_][]const u8{ "baseline", "effect", "estimate", "lsmeans", "lsmestimate", "output", "slice", "store", "test", "format" };
/// Documented MODEL options owned by later ICPHREG tickets.
const later_model_options = [_][]const u8{ "alpha", "corrb", "covb", "entrytime", "entry", "hazardscale", "itprint", "nopolish", "fitmethod", "maxiter", "converge", "gconv", "convergence", "initial", "noint", "offset", "maxitem", "vcov" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC ICPHREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}
fn number(t: []const lex.Token, i: usize) ?f64 {
    var sign: f64 = 1;
    var j = i;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return null;
    return sign * (std.fmt.parseFloat(f64, t[j].text) catch return null);
}

fn parseBasehaz(cx: proc.ProcCtx, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!usize {
    var i = start;
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const kind = t[i].text;
    if (!oneOf(kind, &.{ "pch", "piecewise", "piecewiseexponential", "pcbh" })) {
        if (oneOf(kind, &.{ "splines", "cubicsplines", "unspecified", "discrete" })) return gap(cx, t[i].line, "BASEHAZ={s} is not implemented (STAT-ICPHREG-005)", .{kind});
        return invalid(cx, t, i);
    }
    i += 1;
    if (!at(t, i, .lparen)) return gap(cx, t[i -| 1].line, "BASEHAZ=PCH without INTERVALS= (default break points) is not implemented (STAT-ICPHREG-005)", .{});
    i += 1;
    var seen = false;
    while (i < end and !at(t, i, .rparen)) {
        if (at(t, i, .comma)) {
            i += 1;
            continue;
        }
        if (kw(t, i, "nintervals") or kw(t, i, "ninterval") or kw(t, i, "n")) return gap(cx, t[i].line, "BASEHAZ=PCH(NINTERVAL=) break-point selection is not implemented (STAT-ICPHREG-005)", .{});
        if (!(kw(t, i, "intervals") or kw(t, i, "interval")) or !at(t, i + 1, .eq) or !at(t, i + 2, .lparen)) return invalid(cx, t, i);
        if (seen) return gap(cx, t[i].line, "repeated INTERVALS= policy is not verified", .{});
        seen = true;
        var j = i + 3;
        var values: std.ArrayList(f64) = .empty;
        while (j < end and !at(t, j, .rparen)) {
            if (at(t, j, .comma)) {
                j += 1;
                continue;
            }
            if (kw(t, j, "to") or kw(t, j, "by")) return gap(cx, t[j].line, "INTERVALS= ranges are not implemented", .{});
            const v = number(t, j) orelse return invalid(cx, t, j);
            j += if (at(t, j, .minus)) 2 else 1;
            if (!(v > 0)) return cx.diags.fail(error.ParseError, t[j - 1].line, "PROC ICPHREG: INTERVALS= values must be positive", .{});
            if (values.items.len > 0 and !(v > values.items[values.items.len - 1])) return gap(cx, t[j - 1].line, "INTERVALS= values that are not strictly increasing are not implemented", .{});
            try values.append(cx.arena, v);
        }
        if (!at(t, j, .rparen) or values.items.len == 0) return invalid(cx, t, j);
        s.intervals = values.items;
        i = j + 1;
    }
    if (!at(t, i, .rparen)) return invalid(cx, t, i);
    if (!seen) return gap(cx, t[i].line, "BASEHAZ=PCH without INTERVALS= (default break points) is not implemented (STAT-ICPHREG-005)", .{});
    return i + 1;
}

fn parseModel(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!void {
    var i = start + 1;
    if (!at(t, i, .lparen)) return gap(cx, lineOf(t, i), "the MODEL time*censor(list) response form is not implemented (STAT-ICPHREG-003)", .{});
    s.lower = try numericColumn(cx, ds, t, i + 1, "lower-bound");
    var j = i + 2;
    if (at(t, j, .comma)) j += 1;
    s.upper = try numericColumn(cx, ds, t, j, "upper-bound");
    if (!at(t, j + 1, .rparen)) return invalid(cx, t, j + 1);
    i = j + 2;
    if (!at(t, i, .eq)) return invalid(cx, t, i);
    i += 1;
    var effects: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) : (i += 1) {
        if (at(t, i, .star) or at(t, i, .lparen) or at(t, i, .pipe) or at(t, i, .at)) return gap(cx, t[i].line, "interaction, nested and bar effects are not implemented (STAT-ICPHREG-004)", .{});
        const c = try column(cx, ds, t, i);
        if (std.mem.indexOfScalar(usize, effects.items, c) != null) return gap(cx, t[i].line, "repeated MODEL effect policy is not verified", .{});
        try effects.append(cx.arena, c);
    }
    s.effects = effects.items;
    if (at(t, i, .slash)) i += 1;
    while (i < end) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (oneOf(word, &.{ "basehaz", "base", "b" }) and at(t, i + 1, .eq)) {
            i = try parseBasehaz(cx, t, i + 2, end, s);
        } else if (oneOf(word, &later_model_options)) {
            return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
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
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            const v = number(t, i + 2) orelse return invalid(cx, t, i + 2);
            // "The number must be between 0 and 1" (p.5207).
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC ICPHREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = v;
            i += if (at(t, i + 2, .minus)) 4 else 3;
        } else if (eq(word, "namelen") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const n = std.fmt.parseInt(usize, t[i + 2].text, 10) catch return invalid(cx, t, i + 2);
            if (n < 20 or n > 200) return cx.diags.fail(error.ParseError, t[i].line, "PROC ICPHREG: NAMELEN={d} is outside the documented range 20 to 200", .{n});
            s.namelen = n;
            i += 3;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "ithistory")) {
            s.ithistory = true;
            i += 1;
        } else if (eq(word, "nothreads")) {
            i += 1;
        } else if (eq(word, "threads") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var hrs: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var strata: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (at(t, i, .name) and at(t, i + 1, .colon)) return gap(cx, t[i].line, "statement labels are not implemented", .{});
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "multiple MODEL statements are not implemented", .{});
            model_seen = true;
            try parseModel(cx, ds, t, i, end, &s);
        } else if (kw(t, i, "class")) {
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS variable options are not implemented (STAT-ICPHREG-003)", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "desc") or kw(t, j, "descending")) {
                        s.class_desc = true;
                    } else if (at(t, j, .name)) {
                        return gap(cx, t[j].line, "CLASS option {s} is not implemented (STAT-ICPHREG-003)", .{t[j].text});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "freq")) {
            if (s.freq != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, @min(end, i + 2));
            s.freq = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (kw(t, i, "strata")) {
            var j = i + 1;
            if (j == end) return invalid(cx, t, j);
            while (j < end and !at(t, j, .slash)) : (j += 1) try strata.append(cx.arena, try column(cx, ds, t, j));
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "missing")) s.strata_missing = true else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| try ids.append(cx.arena, try column(cx, ds, t, j));
        } else if (kw(t, i, "hazardratio")) {
            var j = i + 1;
            if (at(t, j, .name) and at(t, j + 1, .name)) return gap(cx, t[j].line, "HAZARDRATIO labels are not implemented (STAT-ICPHREG-007)", .{});
            if (at(t, j, .string)) return gap(cx, t[j].line, "HAZARDRATIO labels are not implemented (STAT-ICPHREG-007)", .{});
            const c = try column(cx, ds, t, j);
            j += 1;
            if (j != end) return gap(cx, t[j].line, "HAZARDRATIO options are not implemented (STAT-ICPHREG-007)", .{});
            try hrs.append(cx.arena, c);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: MODEL statement required", .{});
    s.classes = classes.items;
    s.ids = ids.items;
    s.strata = strata.items;
    s.hazard_ratios = hrs.items;
    for (s.effects) |c| if (ds.columns.items[c].type != .num and std.mem.indexOfScalar(usize, s.classes, c) == null)
        return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: character variable {s} in the MODEL statement must be a CLASS variable", .{ds.columns.items[c].name});
    for (s.hazard_ratios) |c| if (std.mem.indexOfScalar(usize, s.effects, c) == null)
        return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: HAZARDRATIO variable {s} is not a MODEL effect", .{ds.columns.items[c].name});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

pub const Exclusion = enum { missing_bounds, lower_above_upper, missing_explanatory, missing_strata, missing_frequency, nonpositive_frequency };
pub const Status = union(enum) {
    right_censored,
    left_censored,
    interval_censored,
    exact,
    excluded: Exclusion,
};
pub const ClassVariable = struct {
    column: usize,
    labels: []const []const u8,
    /// Level index per input row (null when excluded).
    row_level: []const ?usize,
};
pub const Selected = struct {
    status: []const Status,
    read: usize,
    used: usize = 0,
    right: usize = 0,
    left: usize = 0,
    interval: usize = 0,
    exact: usize = 0,
    /// A used observation with a zero lower bound (p.5230 treats it as left
    /// censoring; the count row it lands in is not verified).
    zero_lower: usize = 0,
    negative_bound: usize = 0,
    classes: []const ClassVariable = &.{},
};

/// Observation selection, "Missing Values" (p.5246) and the response table
/// of the MODEL statement (p.5212): both bounds missing or lower > upper drops
/// the observation; a missing explanatory (MODEL) variable, a missing STRATA
/// value without STRATA / MISSING, and a missing or nonpositive FREQ value
/// drop it too. The first failing rule is recorded.
pub fn select(a: A, ds: *const Dataset, s: Spec, rows: []const []const Value) diag.Error!Selected {
    const status = try a.alloc(Status, rows.len);
    const mask = try a.alloc(bool, rows.len);
    var sel: Selected = .{ .status = status, .read = rows.len };
    for (rows, status, mask) |row, *st, *keep| {
        const l = row[s.lower];
        const r = row[s.upper];
        const lm = selection.missing(l);
        const rm = selection.missing(r);
        st.* = if (lm and rm) .{ .excluded = .missing_bounds } else if (lm) .left_censored else if (rm) .right_censored else if (l.num == r.num) .exact else if (l.num < r.num) .interval_censored else .{ .excluded = .lower_above_upper };
        if (st.* != .excluded) for (s.effects) |e| if (selection.missing(row[e])) {
            st.* = .{ .excluded = .missing_explanatory };
            break;
        };
        if (st.* != .excluded and !s.strata_missing) for (s.strata) |c| if (selection.missing(row[c])) {
            st.* = .{ .excluded = .missing_strata };
            break;
        };
        if (st.* != .excluded) if (s.freq) |f| {
            if (selection.missing(row[f])) st.* = .{ .excluded = .missing_frequency } else if (!(row[f].num > 0)) st.* = .{ .excluded = .nonpositive_frequency };
        };
        keep.* = st.* != .excluded;
        switch (st.*) {
            .excluded => {},
            .right_censored => sel.right += 1,
            .left_censored => sel.left += 1,
            .interval_censored => sel.interval += 1,
            .exact => sel.exact += 1,
        }
        if (keep.*) {
            sel.used += 1;
            if (!lm and l.num == 0) sel.zero_lower += 1;
            if ((!lm and l.num < 0) or (!rm and r.num < 0)) sel.negative_bound += 1;
        }
    }
    var classes: std.ArrayList(ClassVariable) = .empty;
    for (s.classes) |col| {
        if (std.mem.indexOfScalar(usize, s.effects, col) == null) continue;
        const levels = try class_levels.build(a, ds, rows, col, .{ .include_rows = mask });
        const n = levels.levels.len;
        const labels = try a.alloc([]const u8, n);
        for (levels.levels, 0..) |level, k| labels[if (s.class_desc) n - 1 - k else k] = std.mem.trim(u8, level.label, " ");
        const row_level = try a.alloc(?usize, rows.len);
        for (levels.row_to_level, row_level) |lv, *out| out.* = if (lv) |k| (if (s.class_desc) n - 1 - k else k) else null;
        try classes.append(a, .{ .column = col, .labels = labels, .row_level = row_level });
    }
    sel.classes = classes.items;
    return sel;
}

// ---------------------------------------------------------------------------
// Full-likelihood kernel for a piecewise-constant baseline hazard.

/// One used observation: cumulative-hazard exposures of the lower and upper
/// bound per interval (`upper` null = right-censored) and the design row.
pub const Obs = struct { lower: []const f64, upper: ?[]const f64, x: []const f64 };

pub fn exposures(a: A, cuts: []const f64, t: ?f64) ![]f64 {
    const k = cuts.len + 1;
    const d = try a.alloc(f64, k);
    for (d, 0..) |*v, j| {
        const lo: f64 = if (j == 0) 0 else cuts[j - 1];
        const hi: f64 = if (j == cuts.len) std.math.inf(f64) else cuts[j];
        v.* = if (t) |tt| @max(0, @min(tt, hi) - lo) else 0;
    }
    return d;
}

/// Log likelihood, gradient and Hessian over theta = (haz_1..haz_K, beta).
pub fn evaluate(obs: []const Obs, k: usize, theta: []const f64, grad: []f64, hess: []f64) f64 {
    const p = theta.len;
    @memset(grad, 0);
    @memset(hess, 0);
    var ll: f64 = 0;
    for (obs) |o| {
        var eta: f64 = 0;
        for (o.x, theta[k..]) |x, b| eta += x * b;
        const e = @exp(eta);
        var av: f64 = 0;
        for (o.lower, theta[0..k]) |d, h| av += d * h;
        var bv: f64 = 0;
        if (o.upper) |u| for (u, theta[0..k]) |d, h| {
            bv += d * h;
        };
        const ca = av * e;
        const sa = @exp(-ca);
        const cb = if (o.upper != null) bv * e else 0;
        const sb = if (o.upper != null) @exp(-cb) else 0;
        const D = sa - sb;
        ll += @log(D);
        // Derivatives of D with respect to (a, b, eta).
        const d1 = [3]f64{ -e * sa, e * sb, -ca * sa + cb * sb };
        const d2 = [3][3]f64{
            .{ e * e * sa, 0, e * sa * (ca - 1) },
            .{ 0, -e * e * sb, e * sb * (1 - cb) },
            .{ e * sa * (ca - 1), e * sb * (1 - cb), -ca * sa + ca * ca * sa + cb * sb - cb * cb * sb },
        };
        var l1: [3]f64 = undefined;
        var l2: [3][3]f64 = undefined;
        for (0..3) |m| l1[m] = d1[m] / D;
        for (0..3) |m| for (0..3) |n| {
            l2[m][n] = d2[m][n] / D - l1[m] * l1[n];
        };
        // Jacobian rows: theta_j -> (da, db, deta).
        for (0..p) |j| {
            const jj = jac(o, k, j);
            grad[j] += jj[0] * l1[0] + jj[1] * l1[1] + jj[2] * l1[2];
            for (0..p) |q| {
                const jq = jac(o, k, q);
                var v: f64 = 0;
                for (0..3) |m| for (0..3) |n| {
                    v += jj[m] * l2[m][n] * jq[n];
                };
                hess[j * p + q] += v;
            }
        }
    }
    return ll;
}
fn jac(o: Obs, k: usize, j: usize) [3]f64 {
    if (j < k) return .{ o.lower[j], if (o.upper) |u| u[j] else 0, 0 };
    return .{ 0, 0, o.x[j - k] };
}

/// Solves m x = rhs in place (m is p x p, destroyed); false when singular.
pub fn solve(m: []f64, rhs: []f64, p: usize) bool {
    for (0..p) |c| {
        var piv = c;
        for (c + 1..p) |r| if (@abs(m[r * p + c]) > @abs(m[piv * p + c])) {
            piv = r;
        };
        if (@abs(m[piv * p + c]) < 1e-300) return false;
        if (piv != c) {
            for (0..p) |q| std.mem.swap(f64, &m[c * p + q], &m[piv * p + q]);
            std.mem.swap(f64, &rhs[c], &rhs[piv]);
        }
        for (0..p) |r| if (r != c) {
            const f = m[r * p + c] / m[c * p + c];
            if (f != 0) {
                for (c..p) |q| m[r * p + q] -= f * m[c * p + q];
                rhs[r] -= f * rhs[c];
            }
        };
    }
    for (0..p) |c| rhs[c] /= m[c * p + c];
    return true;
}

pub const Fit = struct { theta: []f64, cov: []f64, ll: f64, max_grad: f64 };
pub const FitError = error{ OutOfMemory, NoConvergence, Boundary, Singular };

/// Damped Newton-Raphson ascent from beta = 0 and a flat hazard. Converges on
/// a gradient far below ABSGCONV=1E-5 so the displayed digits are those of the
/// maximiser, not of an optimiser path. An estimate on the hazard lower bound
/// is reported as `Boundary` (the caller gaps it).
pub fn fit(a: A, obs: []const Obs, k: usize, p: usize, start_hazard: f64) FitError!Fit {
    const theta = try a.alloc(f64, p);
    @memset(theta, 0);
    for (theta[0..k]) |*h| h.* = start_hazard;
    const g = try a.alloc(f64, p);
    const h = try a.alloc(f64, p * p);
    const m = try a.alloc(f64, p * p);
    const step = try a.alloc(f64, p);
    const trial = try a.alloc(f64, p);
    const g2 = try a.alloc(f64, p);
    const h2 = try a.alloc(f64, p * p);
    var ll = evaluate(obs, k, theta, g, h);
    var iter: usize = 0;
    while (iter < 500) : (iter += 1) {
        var gmax: f64 = 0;
        for (g) |v| gmax = @max(gmax, @abs(v));
        if (gmax < 1e-10) break;
        var ridge: f64 = 0;
        var moved = false;
        attempt: for (0..60) |_| {
            for (0..p) |r| for (0..p) |c| {
                m[r * p + c] = -h[r * p + c] + if (r == c) ridge else 0;
            };
            @memcpy(step, g);
            if (!solve(m, step, p)) {
                ridge = if (ridge == 0) 1e-6 else ridge * 10;
                continue;
            }
            var scale: f64 = 1;
            for (0..40) |_| {
                var ok = true;
                for (0..p) |j| {
                    trial[j] = theta[j] + scale * step[j];
                    if (j < k and !(trial[j] > 0)) ok = false;
                }
                if (ok) {
                    const lt = evaluate(obs, k, trial, g2, h2);
                    if (std.math.isFinite(lt) and lt >= ll - 1e-12 * @abs(ll)) {
                        @memcpy(theta, trial);
                        @memcpy(g, g2);
                        @memcpy(h, h2);
                        ll = lt;
                        moved = true;
                        break :attempt;
                    }
                }
                scale /= 2;
            }
            ridge = if (ridge == 0) 1e-6 else ridge * 10;
        }
        if (!moved) break;
    }
    var gmax: f64 = 0;
    for (g) |v| gmax = @max(gmax, @abs(v));
    for (theta[0..k]) |hz| if (hz < 1e-7) return error.Boundary;
    if (!(gmax < 1e-5)) return error.NoConvergence;
    const cov = try a.alloc(f64, p * p);
    for (0..p) |c| {
        for (0..p) |r| for (0..p) |q| {
            m[r * p + q] = -h[r * p + q];
        };
        @memset(step, 0);
        step[c] = 1;
        if (!solve(m, step, p)) return error.Singular;
        for (0..p) |r| cov[r * p + c] = step[r];
    }
    for (0..p) |j| if (!(cov[j * p + j] > 0)) return error.Singular;
    return .{ .theta = theta, .cov = cov, .ll = ll, .max_grad = gmax };
}

/// Two-sided standard normal quantile z with P(|Z| > z) = alpha, by bisection
/// on the 1-df chi-square tail.
pub fn zQuantile(alpha: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 40;
    for (0..200) |_| {
        const mid = (lo + hi) / 2;
        if (chiTail(mid * mid, 1) > alpha) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

// ---------------------------------------------------------------------------
// Listing.

fn num(a: A, v: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = v }, spec), " ");
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
fn title(a: A, out: *Out, text: []const u8, width: usize) !void {
    try pad(a, out, (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn intervalText(a: A, v: f64) ![]const u8 {
    if (std.math.isInf(v)) return "Infty";
    return format.bestNum(a, v);
}

const Column = struct { level: ?[]const u8 };

fn byLine(a: A, out: *Out, s: Spec, rep: ?[]const Value) !void {
    if (s.by_cols.len == 0) return;
    // ponytail: left-aligned (NOCENTER), the shape of the reference listings
    // and of the other per-page BY procedures (tpspline).
    var line: Out = .empty;
    try by.appendLine(a, &line, s.input.ds, rep.?, s.by_cols);
    if (line.items.len > 0) try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
}

fn group(cx: proc.ProcCtx, out: *Out, s: Spec, rep: ?[]const Value, rows: []const []const Value) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const sel = try select(a, ds, s, rows);
    if (sel.exact > 0) return gap(cx, 0, "exact (lower = upper) responses are not implemented (STAT-ICPHREG-005)", .{});
    if (sel.zero_lower > 0) return gap(cx, 0, "a zero lower bound is not implemented; set it to missing for left censoring", .{});
    if (sel.negative_bound > 0) return gap(cx, 0, "negative response bounds are not implemented", .{});
    if (s.freq != null) return gap(cx, 0, "FREQ statement listing is not implemented (STAT-ICPHREG-011)", .{});
    if (s.strata.len > 0) return gap(cx, 0, "stratified baseline hazards (STRATA statement) are not implemented (STAT-ICPHREG-005)", .{});
    if (s.ithistory) return gap(cx, 0, "ITHISTORY is not implemented (STAT-ICPHREG-011)", .{});
    if (sel.used == 0) return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: no valid observations are available", .{});
    for (sel.classes) |cv| if (cv.labels.len < 1) return cx.diags.fail(error.ParseError, 0, "PROC ICPHREG: no valid observations are available", .{});
    const cuts = s.intervals orelse return gap(cx, 0, "the default BASEHAZ= (NINTERVAL=5 break points) is not implemented (STAT-ICPHREG-005)", .{});
    const k = cuts.len + 1;

    // Design: GLM coding, last (reference) level aliased.
    var nbeta: usize = 0;
    for (s.effects) |e| nbeta += if (classOf(sel, e)) |cv| cv.labels.len - 1 else 1;
    const p = k + nbeta;
    var obs: std.ArrayList(Obs) = .empty;
    var max_bound: f64 = 0;
    for (rows, sel.status, 0..) |row, st, ri| {
        if (st == .excluded) continue;
        const x = try a.alloc(f64, nbeta);
        @memset(x, 0);
        var col: usize = 0;
        for (s.effects) |e| {
            if (classOf(sel, e)) |cv| {
                const lv = cv.row_level[ri].?;
                if (lv < cv.labels.len - 1) x[col + lv] = 1;
                col += cv.labels.len - 1;
            } else {
                x[col] = row[e].num;
                col += 1;
            }
        }
        const lo: ?f64 = if (selection.missing(row[s.lower])) null else row[s.lower].num;
        const hi: ?f64 = if (selection.missing(row[s.upper])) null else row[s.upper].num;
        if (lo) |v| max_bound = @max(max_bound, v);
        if (hi) |v| max_bound = @max(max_bound, v);
        try obs.append(a, .{ .lower = try exposures(a, cuts, lo orelse 0), .upper = if (hi) |v| try exposures(a, cuts, v) else null, .x = x });
    }
    const start = if (max_bound > 0) 1 / max_bound else 1;
    const f = fit(a, obs.items, k, p, start) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Boundary => return gap(cx, 0, "a baseline hazard estimate at the lower bound (Fixed Parameters) is not implemented (STAT-ICPHREG-005)", .{}),
        error.NoConvergence => return gap(cx, 0, "the likelihood maximisation did not converge; the remedies are not implemented (STAT-ICPHREG-005)", .{}),
        error.Singular => return gap(cx, 0, "a singular information matrix is not implemented (STAT-ICPHREG-005)", .{}),
    };
    try cx.diags.note(0, "Convergence criterion (ABSGCONV=0.00001) satisfied.", .{});
    if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, rep.?, s.by_cols);
    if (s.noprint) return;

    // Model Information.
    try out.append(a, '\n');
    if (s.by_cols.len > 0) {
        try byLine(a, out, s, rep);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "The ICPHREG Procedure\n\n");
    {
        const vals = [_][]const u8{ try lists.datasetName(a, ds), ds.columns.items[s.lower].name, ds.columns.items[s.upper].name, "Piecewise Constant" };
        const labels = [_][]const u8{ "Data Set", "Left Boundary", "Right Boundary", "Baseline Hazard" };
        var w: usize = 0;
        for (vals) |v| w = @max(w, v.len);
        try title(a, out, "Model Information", 19 + w);
        try out.append(a, '\n');
        for (labels, vals) |l, v| {
            try left(a, out, l, 19);
            try right(a, out, v, w);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    const counts = [_]struct { []const u8, usize }{
        .{ "Number of Observations Read", sel.read },
        .{ "Number of Observations Used", sel.used },
        .{ "Right Censored Observations", sel.right },
        .{ "Interval Censored Observations", sel.interval },
        .{ "Left Censored Observations", sel.left },
    };
    for (counts) |c| {
        try left(a, out, c[0], 30);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{c[1]}), 12);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    if (sel.classes.len > 0) {
        if (s.by_cols.len > 0) {
            try byLine(a, out, s, rep);
            try out.append(a, '\n');
        }
        var nw: usize = 7;
        var vw: usize = 6;
        const texts = try a.alloc([]const u8, sel.classes.len);
        for (sel.classes, texts) |cv, *tx| {
            nw = @max(nw, ds.columns.items[cv.column].name.len);
            tx.* = try std.mem.join(a, " ", cv.labels);
            vw = @max(vw, tx.len);
        }
        try title(a, out, "Class Level Information", nw + 4 + 6 + 4 + vw);
        try out.appendSlice(a, " \n");
        try left(a, out, "Name", nw + 4);
        try out.appendSlice(a, "Levels    ");
        try left(a, out, "Values", vw);
        try out.appendSlice(a, "\n\n");
        for (sel.classes, texts) |cv, tx| {
            try left(a, out, ds.columns.items[cv.column].name, nw + 4);
            try right(a, out, try std.fmt.allocPrint(a, "{d}", .{cv.labels.len}), 6);
            try pad(a, out, 4);
            try left(a, out, tx, vw);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    // Constant Hazard Time Intervals.
    try out.appendSlice(a, "  Constant Hazard Time Intervals\n \n      Interval          Hazard\n  [Lower      Upper)    Parameter\n\n");
    for (0..k) |j| {
        try right(a, out, try intervalText(a, if (j == 0) 0 else cuts[j - 1]), 8);
        try right(a, out, try intervalText(a, if (j == cuts.len) std.math.inf(f64) else cuts[j]), 12);
        try pad(a, out, 4);
        try left(a, out, try std.fmt.allocPrint(a, "Haz{d}", .{j + 1}), 9);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try title(a, out, "Optimization Information", 44);
    try out.append(a, '\n');
    try out.appendSlice(a, "Optimization Technique        Newton-Raphson\n");
    try left(a, out, "Parameters in Optimization", 30);
    try left(a, out, try std.fmt.allocPrint(a, "{d}", .{p}), 14);
    try out.appendSlice(a, "\n\n      Convergence criterion (ABSGCONV=0.00001) satisfied.       \n\n\n");
    // Fit Statistics.
    {
        const n: f64 = @floatFromInt(sel.used);
        const pf: f64 = @floatFromInt(p);
        const m2 = -2 * f.ll;
        try title(a, out, "Fit Statistics", 48);
        try out.append(a, '\n');
        const stats = [_]struct { []const u8, f64 }{
            .{ "-2 Log Likelihood", m2 },
            .{ "AIC (Smaller is Better)", m2 + 2 * pf },
            .{ "AICC (Smaller is Better)", m2 + 2 * pf * n / (n - pf - 1) },
            .{ "BIC (Smaller is Better)", m2 + pf * @log(n) },
        };
        for (stats) |st| {
            try left(a, out, st[0], 24);
            const v = if (std.math.isFinite(st[1]) and n - pf - 1 > 0) try num(a, st[1], "24.3") else ".";
            try right(a, out, v, 24);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    // Analysis of Maximum Likelihood Parameter Estimates.
    const z = zQuantile(s.alpha);
    {
        var ew: usize = 9;
        for (s.effects) |e| ew = @max(ew, ds.columns.items[e].name.len);
        const cw = try a.alloc(usize, sel.classes.len);
        for (sel.classes, cw) |cv, *w| {
            w.* = ds.columns.items[cv.column].name.len;
            for (cv.labels) |l| w.* = @max(w.*, l.len);
        }
        var lead: usize = ew + 4;
        for (cw) |w| lead += w + 4;
        const width = lead + 2 + 12 * 4 + 11 + 14;
        const pct = try std.fmt.allocPrint(a, "{d}% Confidence", .{@round((1 - s.alpha) * 100 * 1e6) / 1e6});
        try title(a, out, "Analysis of Maximum Likelihood Parameter Estimates", width);
        try out.appendSlice(a, " \n");
        try pad(a, out, lead + 2 + 12 + 4);
        try out.appendSlice(a, "Standard");
        // The CI header is centred over the two limit fields (without gaps).
        const span = 20;
        try pad(a, out, 4 + (span -| pct.len) / 2);
        try out.appendSlice(a, pct);
        try pad(a, out, span - (span -| pct.len) / 2 - pct.len);
        try right(a, out, "Chi-", 11);
        try out.append(a, '\n');
        try left(a, out, "Effect", ew + 4);
        for (sel.classes, cw) |cv, w| try left(a, out, ds.columns.items[cv.column].name, w + 4);
        try out.appendSlice(a, "DF    Estimate       Error");
        try pad(a, out, 4 + 7);
        try out.appendSlice(a, "Limits");
        try pad(a, out, 7);
        try right(a, out, "Square", 11);
        try out.appendSlice(a, "    Pr > ChiSq\n\n");
        var idx: usize = 0;
        for (0..k) |j| {
            const est = f.theta[j];
            const se = @sqrt(f.cov[j * p + j]);
            try left(a, out, try std.fmt.allocPrint(a, "Haz{d}", .{j + 1}), lead);
            try right(a, out, "1", 2);
            try right(a, out, try num(a, est, "12.4"), 12);
            try right(a, out, try num(a, se, "12.4"), 12);
            try right(a, out, try num(a, @max(0, est - z * se), "12.4"), 12);
            try right(a, out, try num(a, est + z * se, "12.4"), 12);
            try pad(a, out, 25);
            try out.append(a, '\n');
        }
        idx = k;
        for (s.effects) |e| {
            const cvo = classOf(sel, e);
            const nl = if (cvo) |cv| cv.labels.len else 1;
            for (0..nl) |lv| {
                try left(a, out, ds.columns.items[e].name, ew + 4);
                for (sel.classes, cw) |cv, w| try left(a, out, if (cv.column == e) cv.labels[lv] else "", w + 4);
                const aliased = cvo != null and lv == nl - 1;
                if (aliased) {
                    try right(a, out, "0", 2);
                    try right(a, out, "0.0000", 12);
                    try pad(a, out, 12 * 3 + 25);
                } else {
                    const est = f.theta[idx];
                    const se = @sqrt(f.cov[idx * p + idx]);
                    const chi = (est / se) * (est / se);
                    try right(a, out, "1", 2);
                    try right(a, out, try num(a, est, "12.4"), 12);
                    try right(a, out, try num(a, se, "12.4"), 12);
                    try right(a, out, try num(a, est - z * se, "12.4"), 12);
                    try right(a, out, try num(a, est + z * se, "12.4"), 12);
                    try right(a, out, try num(a, chi, "11.2"), 11);
                    try right(a, out, try num(a, chiTail(chi, 1), "pvalue6.4"), 14);
                    idx += 1;
                }
                try out.append(a, '\n');
            }
        }
    }
    // Hazard ratios (two-level CLASS effects only).
    for (s.hazard_ratios) |e| {
        const cv = classOf(sel, e) orelse return gap(cx, 0, "HAZARDRATIO for a continuous effect is not implemented (STAT-ICPHREG-007)", .{});
        if (cv.labels.len != 2) return gap(cx, 0, "HAZARDRATIO for a CLASS effect with other than two levels is not implemented (STAT-ICPHREG-007)", .{});
        var j: usize = k;
        for (s.effects) |e2| {
            if (e2 == e) break;
            j += if (classOf(sel, e2)) |c2| c2.labels.len - 1 else 1;
        }
        const est = f.theta[j];
        const se = @sqrt(f.cov[j * p + j]);
        const name = ds.columns.items[e].name;
        const desc = try std.fmt.allocPrint(a, "{s} {s} vs {s}", .{ name, cv.labels[0], cv.labels[1] });
        const dw = @max(desc.len, 11);
        try out.appendSlice(a, "\n\n");
        try title(a, out, try std.fmt.allocPrint(a, "Hazard Ratios for {s}", .{name}), dw + 4 + 8 + 12 + 12);
        try out.appendSlice(a, " \n");
        try pad(a, out, dw + 4 + 3);
        try out.appendSlice(a, "Point     ");
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d}% Wald Confidence\n", .{@round((1 - s.alpha) * 100 * 1e6) / 1e6}));
        try left(a, out, "Description", dw + 4);
        try out.appendSlice(a, "Estimate           Limits\n\n");
        try left(a, out, desc, dw + 4);
        try right(a, out, try num(a, @exp(est), "8.3"), 8);
        try right(a, out, try num(a, @exp(est - z * se), "12.3"), 12);
        try right(a, out, try num(a, @exp(est + z * se), "12.3"), 12);
        try out.append(a, '\n');
    }
}

fn classOf(sel: Selected, col: usize) ?ClassVariable {
    for (sel.classes) |cv| if (cv.column == col) return cv;
    return null;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    // Every group is validated and fitted before any text is kept, so a gap
    // in a later BY group never leaves a partial listing.
    var body: Out = .empty;
    for (slices) |slice| try group(cx, &body, s, slice.rep, slice.rows);
    try out.appendSlice(cx.arena, body.items);
}

test {
    _ = @import("icphreg_tests.zig");
}
