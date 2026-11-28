//! PROC GENMOD (SAS/STAT 15.4 ch.51) — STAT-GENMOD-001: PROC statement options,
//! variable roles (BY/CLASS/MODEL/FREQ/WEIGHT/STRATA) and observation selection.
//! Physical PDF pp.3509–3514 (PROC options), 3525 (BY), 3541 (FREQ), 3565–3567
//! (STRATA, WEIGHT), 3616 (Missing Values).
//!
//! ponytail: no estimation lives here yet. Every syntactically valid step ends
//! in a D-009 gap (exit 2) after its declarations and data roles validate, so
//! a GENMOD step can never silently succeed. The fit, OUTPUT, residuals and all
//! other statements belong to STAT-GENMOD-002..023; `parse` and `prepare` are
//! the parameter object and selected-observation interface they build on.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;

pub const Stratum = struct { column: usize, missing: bool = false };
pub const Check = enum { covariates, none, all };

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement (p.3509): defaults are the documented ones.
    descending: bool = false,
    exact_only: bool = false,
    namelen: usize = 20,
    order: classes.Order = .formatted,
    rorder: classes.Order = .formatted,
    // Roles.
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    class: []const usize = &.{},
    response: usize = 0,
    trials: ?usize = null,
    effects: []const usize = &.{},
    dist: ?[]const u8 = null,
    link: ?[]const u8 = null,
    /// MODEL options other than DIST=/LINK=, by name, in source order.
    model_options: []const []const u8 = &.{},
    frequency: ?usize = null,
    weight: ?usize = null,
    strata: []const Stratum = &.{},
    strata_check: Check = .covariates,
    strata_nosummary: bool = false,
    strata_info: bool = false,
    exact: bool = false,
    /// Statements owned by later GENMOD tickets, by name, in source order.
    later: []const []const u8 = &.{},
};

/// One BY group's selected observations. `rows` indexes the supplied slice.
pub const Selection = struct {
    read: usize,
    used: usize,
    /// Truncated FREQ totals (equal to the counts when there is no FREQ).
    frequency_read: f64,
    frequency_used: f64,
    /// Observations dropped for a missing response/trials/effect/CLASS/STRATA value.
    missing: usize,
    /// Observations dropped for a FREQ value that is missing or less than 1.
    bad_frequency: usize,
    /// Observations dropped for a WEIGHT value that is missing or not positive.
    bad_weight: usize,
    rows: []const usize,
    frequency: []const f64,
    weight: []const f64,
    /// One entry per CLASS variable, levelized over the used observations.
    levels: []const classes.Levels,
};

const later_statements = [_][]const u8{ "assess", "assessment", "bayes", "code", "contrast", "deviance", "effectplot", "estimate", "exactoptions", "fwdlink", "invlink", "lsmeans", "lsmestimate", "output", "repeated", "slice", "store", "variance", "zeromodel" };
/// p.3566: statements "not available with a STRATA statement".
const strata_conflicts = [_][]const u8{ "assess", "assessment", "bayes", "contrast", "effectplot", "estimate", "lsmeans", "lsmestimate", "output", "repeated", "slice", "store" };

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
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC GENMOD: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn orderValue(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!classes.Order {
    if (kw(t, i, "data")) return .data;
    if (kw(t, i, "formatted")) return .formatted;
    if (kw(t, i, "freq")) return .freq;
    if (kw(t, i, "internal")) return .internal;
    return cx.diags.fail(error.ParseError, line(t, i), "PROC GENMOD: ORDER=/RORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "PROC GENMOD: variable {s} in the {s} statement is not on the input data set", .{ t[i].text, role });
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const ci = try column(cx, ds, t, i, role);
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC GENMOD: variable {s} in the {s} statement must be numeric", .{ t[i].text, role });
    return ci;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
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
        if ((try seen.getOrPut(a, canonical)).found_existing) return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: repeated PROC statement option {s} is not verified", .{t[i].text});
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
        } else if (eq(canonical, "exactonly")) {
            s.exact_only = true;
            i += 1;
        } else if (eq(canonical, "namelen") and at(t, i + 1, .eq)) {
            const n = if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null;
            if (n == null or n.? < 20 or n.? > 200) return cx.diags.fail(error.ParseError, t[i].line, "PROC GENMOD: NAMELEN= must be an integer between 20 and 200", .{});
            s.namelen = n.?;
            i += 3;
        } else if ((eq(canonical, "order") or eq(canonical, "rorder")) and at(t, i + 1, .eq)) {
            const value = try orderValue(cx, t, i + 2);
            if (eq(canonical, "order")) s.order = value else s.rorder = value;
            i += 3;
        } else if (eq(canonical, "plots")) {
            return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: PLOTS is not implemented (STAT-GENMOD-020)", .{});
        } else return invalid(cx, t, i); // includes NOPRINT, documented as unavailable (p.3514)
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC GENMOD: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var class: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var model_options: std.ArrayList([]const u8) = .empty;
    var strata: std.ArrayList(Stratum) = .empty;
    var later: std.ArrayList([]const u8) = .empty;
    var strata_missing_all = false;
    var model_seen = false;
    var model_line: usize = 0;
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
        } else if (eq(word, "class")) {
            // p.3526: "The CLASS statement must precede the MODEL statement."
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC GENMOD: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .lparen) or at(t, j, .slash)) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: CLASS options are not implemented (STAT-GENMOD-003)", .{});
                const ci = try column(cx, ds, t, j, "CLASS");
                if (!has(class.items, ci)) try class.append(a, ci);
            }
        } else if (eq(word, "model")) {
            if (model_seen) return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: more than one MODEL statement is not verified", .{});
            model_seen = true;
            model_line = t[i].line;
            var j = i + 1;
            s.response = try column(cx, ds, t, j, "MODEL");
            j += 1;
            if (at(t, j, .slash)) {
                s.trials = try numericColumn(cx, ds, t, j + 1, "MODEL");
                if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, t[j].line, "PROC GENMOD: the events variable in events/trials syntax must be numeric", .{});
                j += 2;
            }
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) {
                    if (at(t, j, .star) or at(t, j, .pipe) or at(t, j, .lparen) or at(t, j, .rparen) or at(t, j, .at) or at(t, j, .number))
                        return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: crossed, nested and bar effects are not implemented (STAT-GENMOD-004)", .{});
                    return invalid(cx, t, j);
                }
                const ci = try column(cx, ds, t, j, "MODEL");
                if (ds.columns.items[ci].type != .num and !has(class.items, ci))
                    return cx.diags.fail(error.ParseError, t[j].line, "PROC GENMOD: character variable {s} in the MODEL statement must be a CLASS variable", .{t[j].text});
                try effects.append(a, ci);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const option = t[j].text;
                    j += 1;
                    var value: ?[]const u8 = null;
                    if (at(t, j, .eq)) {
                        j += 1;
                        if (j >= end) return invalid(cx, t, j);
                        const first = j;
                        if (at(t, j, .lparen)) j = proc.skipParen(t, j) else {
                            j += 1;
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                        }
                        if (j == first + 1 and (t[first].tag == .name or t[first].tag == .number)) value = t[first].text;
                    }
                    const is_dist = oneOf(option, &.{ "dist", "d", "error", "err" });
                    if (is_dist or eq(option, "link")) {
                        const v = value orelse return proc.failGap(cx.diags, line(t, j - 1), "PROC GENMOD: MODEL {s}= with a parenthesized or missing value is not implemented (STAT-GENMOD-003)", .{option});
                        const slot = if (is_dist) &s.dist else &s.link;
                        if (slot.* != null) return proc.failGap(cx.diags, line(t, j - 1), "PROC GENMOD: repeated MODEL option {s}= is not verified", .{option});
                        slot.* = v;
                    } else try model_options.append(a, option);
                }
            }
        } else if (eq(word, "freq") or eq(word, "frequency")) {
            if (s.frequency != null) return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: more than one FREQ statement is not verified", .{});
            if (end != i + 2) return invalid(cx, t, @min(i + 2, end));
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (eq(word, "weight") or eq(word, "scwgt")) {
            if (s.weight != null) return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: more than one WEIGHT statement is not verified", .{});
            if (end != i + 2) return invalid(cx, t, @min(i + 2, end));
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (eq(word, "strata")) {
            // p.3565: several STRATA statements equal one with all variables.
            var j = i + 1;
            var count: usize = 0;
            while (j < end and !at(t, j, .slash)) {
                const ci = try column(cx, ds, t, j, "STRATA");
                j += 1;
                var item: Stratum = .{ .column = ci };
                if (at(t, j, .lparen)) {
                    if (!kw(t, j + 1, "missing") or !at(t, j + 2, .rparen)) return invalid(cx, t, j + 1);
                    item.missing = true;
                    j += 3;
                }
                count += 1;
                var known = false;
                for (strata.items) |*old| if (old.column == ci) {
                    old.missing = old.missing or item.missing;
                    known = true;
                };
                if (!known) try strata.append(a, item);
            }
            if (count == 0) return invalid(cx, t, j); // "At least one variable must be specified"
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (kw(t, j, "missing")) {
                        strata_missing_all = true;
                        j += 1;
                    } else if (kw(t, j, "nosummary")) {
                        s.strata_nosummary = true;
                        j += 1;
                    } else if (kw(t, j, "info")) {
                        s.strata_info = true;
                        j += 1;
                    } else if ((kw(t, j, "checkdependency") or kw(t, j, "check")) and at(t, j + 1, .eq)) {
                        s.strata_check = if (kw(t, j + 2, "none")) .none else if (kw(t, j + 2, "covariates")) .covariates else if (kw(t, j + 2, "all")) .all else return invalid(cx, t, j + 2);
                        j += 3;
                    } else return invalid(cx, t, j);
                }
            }
        } else if (eq(word, "exact")) {
            s.exact = true;
        } else if (oneOf(word, &later_statements)) {
            try later.append(a, try std.ascii.allocLowerString(a, word));
        } else if (eq(word, "format")) {
            return proc.failGap(cx.diags, t[i].line, "PROC GENMOD: a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC GENMOD: a MODEL statement is required", .{});
    if (strata_missing_all) for (strata.items) |*item| {
        item.missing = true;
    };
    s.class = class.items;
    s.effects = effects.items;
    s.model_options = model_options.items;
    s.strata = strata.items;
    s.later = later.items;
    if (s.strata.len > 0) {
        // p.3565–3566. The reference SAS text for these conditions is not
        // available; the classification (user error) follows the document.
        if (!s.exact) return cx.diags.fail(error.ParseError, model_line, "PROC GENMOD: the STRATA statement requires an EXACT statement", .{});
        for (s.later) |statement| if (oneOf(statement, &strata_conflicts))
            return cx.diags.fail(error.ParseError, model_line, "PROC GENMOD: the {s} statement is not available with a STRATA statement", .{statement});
    }
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Observation selection for one BY group (pp.3541, 3567, 3616):
/// an observation is used only if the response, trials, every MODEL effect
/// variable and every CLASS variable are nonmissing, the FREQ value truncates
/// to at least 1, and the WEIGHT value is positive. FREQ is truncated here.
pub fn prepare(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Selection {
    const a = cx.arena;
    var out: Selection = .{ .read = rows.len, .used = 0, .frequency_read = 0, .frequency_used = 0, .missing = 0, .bad_frequency = 0, .bad_weight = 0, .rows = &.{}, .frequency = &.{}, .weight = &.{}, .levels = &.{} };
    var kept: std.ArrayList(usize) = .empty;
    var freqs: std.ArrayList(f64) = .empty;
    var weights: std.ArrayList(f64) = .empty;
    const mask = try a.alloc(bool, rows.len);
    const mask_freq = try a.alloc(f64, rows.len);
    for (rows, 0..) |row, k| {
        mask[k] = false;
        mask_freq[k] = 0;
        var f: f64 = 1;
        var f_ok = true;
        if (s.frequency) |ci| {
            const x = row[ci].num;
            f_ok = !std.math.isNan(x) and x >= 1;
            f = if (f_ok) @floor(x) else 0;
        }
        out.frequency_read += f;
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
        for (s.strata) |item| miss = miss or (!item.missing and selection.missing(row[item.column]));
        if (miss) out.missing += 1;
        if (!f_ok) out.bad_frequency += 1;
        if (!w_ok) out.bad_weight += 1;
        if (miss or !f_ok or !w_ok) continue;
        mask[k] = true;
        mask_freq[k] = f;
        out.frequency_used += f;
        try kept.append(a, k);
        try freqs.append(a, f);
        try weights.append(a, w);
    }
    out.used = kept.items.len;
    out.rows = kept.items;
    out.frequency = freqs.items;
    out.weight = weights.items;
    const levels = try a.alloc(classes.Levels, s.class.len);
    for (s.class, 0..) |ci, k| levels[k] = try classes.build(a, s.input.ds, rows, ci, .{ .order = s.order, .include_rows = mask, .frequencies = mask_freq });
    out.levels = levels;
    return out;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    _ = out; // nothing may be printed until an owning ticket supplies real results
    const s = try parse(cx, t);
    const groups = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    for (groups) |group| _ = try prepare(cx, s, group.rows);
    if (s.later.len > 0) return proc.failGap(cx.diags, line(t, 0), "PROC GENMOD: the {s} statement is not implemented", .{s.later[0]});
    if (s.exact or s.exact_only or s.strata.len > 0) return proc.failGap(cx.diags, line(t, 0), "PROC GENMOD: exact analysis is not implemented (STAT-GENMOD-010)", .{});
    return proc.failGap(cx.diags, line(t, 0), "PROC GENMOD: generalized linear model estimation is not implemented (STAT-GENMOD-002)", .{});
}

test {
    _ = @import("genmod_tests.zig");
}
