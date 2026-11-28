//! PROC GENMOD (SAS/STAT 15.4 ch.51) — STAT-GENMOD-001: PROC statement options,
//! variable roles (BY/CLASS/MODEL/FREQ/WEIGHT/STRATA) and observation selection.
//! Physical PDF pp.3509–3514 (PROC options), 3525 (BY), 3541 (FREQ), 3565–3567
//! (STRATA, WEIGHT), 3616 (Missing Values).
//!
//! STAT-GENMOD-002 adds the default listing for the Normal model with an
//! identity or log link and ML scale (kernel in genmod_fit.zig).
//!
//! STAT-GENMOD-003 adds the events/trials binomial-logit model with CLASS main
//! effects and LRCI/WALDCI (genmod_logit.zig, kernel genmod_binomial.zig) and
//! the MODEL option table (unknown option: user error; documented: gap).
//!
//! ponytail: every other valid step (other DIST=/LINK=, CLASS designs, FREQ,
//! WEIGHT, MODEL options, unfinished OUTPUT keywords and all later statements) still ends in a
//! D-009 gap (exit 2) with NOTHING printed, so a GENMOD step can never
//! silently succeed. `parse` and `prepare` are the parameter object and
//! selected-observation interface later tickets build on.
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
const fit = @import("genmod_fit.zig");
const output = @import("genmod_output.zig");
const logit = @import("genmod_logit.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Stratum = struct { column: usize, missing: bool = false };
pub const Check = enum { covariates, none, all };

pub const Spec = struct {
    input: proc.ProcInput,
    /// Input data set name as written (or the last data set), for Model Information.
    data_name: []const u8 = "",
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
    /// OUTPUT statement (p.3555): OUT= member and keyword=name requests in source order.
    output: ?output.Request = null,
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

const later_statements = [_][]const u8{ "assess", "assessment", "bayes", "code", "contrast", "deviance", "effectplot", "estimate", "exactoptions", "fwdlink", "invlink", "lsmeans", "lsmestimate", "repeated", "slice", "store", "variance", "zeromodel" };
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

/// OUTPUT <OUT=data-set> <keyword=name ...> (p.3555). Unknown keywords and
/// malformed syntax are user errors; documented shapes that are not computed
/// (and rules the section does not state) are loud gaps.
fn parseOutput(cx: proc.ProcCtx, t: []const lex.Token, start: usize, end: usize, repeated: bool) diag.Error!output.Request {
    const a = cx.arena;
    if (repeated) return proc.failGap(cx.diags, t[start].line, "PROC GENMOD: more than one OUTPUT statement is not verified", .{});
    var request: output.Request = .{ .name = "" };
    var items: std.ArrayList(output.Item) = .empty;
    var out_seen = false;
    var j = start + 1;
    while (j < end) {
        if (!at(t, j, .name) or !at(t, j + 1, .eq)) return invalid(cx, t, j);
        const word = t[j].text;
        j += 2;
        if (j >= end) return invalid(cx, t, j - 1);
        if (eq(word, "out")) {
            if (out_seen) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: a repeated OUTPUT OUT= is not verified", .{});
            out_seen = true;
            if (!at(t, j, .name)) return invalid(cx, t, j);
            request.name = t[j].text;
            j += 1;
            if (j < end and at(t, j, .dot)) {
                if (j + 1 >= end or !at(t, j + 1, .name)) return invalid(cx, t, j);
                request.name = try std.fmt.allocPrint(a, "{s}.{s}", .{ request.name, t[j + 1].text });
                j += 2;
            }
            if (j < end and at(t, j, .lparen)) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: data set options on OUTPUT OUT= are not implemented (STAT-GENMOD-018)", .{});
            continue;
        }
        const k = output.kind(word) orelse {
            if (output.documentedGap(word)) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: OUTPUT keyword {s}= is not implemented (STAT-GENMOD-018)", .{word});
            return cx.diags.fail(error.ParseError, t[j].line, "PROC GENMOD: {s} is not a valid OUTPUT statement keyword", .{word});
        };
        // p.3556: only the DFBETA family takes a parenthesized list or _ALL_.
        if (!at(t, j, .name)) return invalid(cx, t, j);
        for (items.items) |item| {
            if (item.kind == k) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: a repeated OUTPUT keyword {s}= is not verified", .{word});
            if (eq(item.name, t[j].text)) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: OUTPUT variable name {s} used twice is not verified", .{t[j].text});
        }
        try items.append(a, .{ .kind = k, .name = t[j].text });
        j += 1;
    }
    if (!out_seen) return proc.failGap(cx.diags, t[start].line, "PROC GENMOD: OUTPUT without OUT= (DATAn naming) is not implemented; specify OUT=", .{});
    if (eq(request.name, "_null_")) return proc.failGap(cx.diags, t[start].line, "PROC GENMOD: OUTPUT OUT=_NULL_ is not verified", .{});
    request.items = items.items;
    return request;
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
    s.data_name = name orelse raw.name;
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
            // p.3544: MODEL response <(variable-options)> = ...
            if (at(t, j, .lparen)) return proc.failGap(cx.diags, t[j].line, "PROC GENMOD: response variable options are not implemented (STAT-GENMOD-004)", .{});
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
        } else if (eq(word, "output")) {
            s.output = try parseOutput(cx, t, i, end, s.output != null);
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
        if (s.output != null) return cx.diags.fail(error.ParseError, model_line, "PROC GENMOD: the output statement is not available with a STRATA statement", .{});
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

/// Two-sided 95% standard normal quantile, PROBIT(0.975) (ALPHA= is a gap).
const z95: f64 = 1.959963984540054;

/// One BY group's listing: Model Information, Number of Observations,
/// Criteria For Assessing Goodness Of Fit, the convergence line and Analysis
/// Of Maximum Likelihood Parameter Estimates (Getting Started, pp.3489–3508).
fn render(a: A, out: *Out, s: Spec, sel: Selection, link: fit.Link, r: fit.Fit) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe GENMOD Procedure\n\n");
    const data_name = blk: {
        const upper = try std.ascii.allocUpperString(a, s.data_name);
        break :blk if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    };
    const info = [_][2][]const u8{
        .{ "Data Set", data_name },
        .{ "Distribution", "Normal" },
        .{ "Link Function", if (link == .log) "Log" else "Identity" },
        .{ "Dependent Variable", ds.columns.items[s.response].name },
    };
    var value_width: usize = 0;
    for (info) |row| value_width = @max(value_width, row[1].len);
    try centered(a, out, "Model Information", 22 + value_width);
    try out.append(a, '\n');
    for (info) |row| {
        try padRight(a, out, row[0], 18);
        try padLeft(a, out, row[1], value_width + 4);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n\n\n", .{ sel.read, sel.used });

    const p: f64 = @floatFromInt(r.p);
    const df = r.n - p;
    const variance = r.scale * r.scale;
    try centered(a, out, "Criteria For Assessing Goodness Of Fit", 64);
    try out.appendSlice(a, " \nCriterion                     DF           Value        Value/DF\n\n");
    // Normal: unit variance function, so Pearson chi-square equals the deviance.
    for ([_][]const u8{ "Deviance", "Scaled Deviance", "Pearson Chi-Square", "Scaled Pearson X2" }, [_]f64{ r.deviance, r.deviance / variance, r.deviance, r.deviance / variance }) |label, value| {
        try padRight(a, out, label, 24);
        try number(a, out, df, 0, 8);
        try number(a, out, value, 4, 16);
        try number(a, out, value / df, 4, 16);
        try out.append(a, '\n');
    }
    // p+1 parameters: the regression coefficients and the ML scale.
    const k = p + 1;
    const aic = -2 * r.loglik + 2 * k;
    // Normal: the full log likelihood has no extra data-only term.
    for ([_][]const u8{ "Log Likelihood", "Full Log Likelihood", "AIC (smaller is better)", "AICC (smaller is better)", "BIC (smaller is better)" }, [_]f64{ r.loglik, r.loglik, aic, aic + 2 * k * (k + 1) / (r.n - k - 1), -2 * r.loglik + k * @log(r.n) }) |label, value| {
        try padRight(a, out, label, 32);
        try number(a, out, value, 4, 16);
        try out.appendNTimes(a, ' ', 16);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try padRight(a, out, "Algorithm converged.", 75);
    try out.appendSlice(a, "\n\n\n");

    var name_width: usize = 9;
    for (s.effects) |ci| name_width = @max(name_width, ds.columns.items[ci].name.len);
    const extra = name_width - 9;
    try out.appendNTimes(a, ' ', extra);
    try centered(a, out, "Analysis Of Maximum Likelihood Parameter Estimates", 91);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', extra);
    try out.appendSlice(a, "                               Standard     Wald 95% Confidence          Wald\n");
    try padRight(a, out, "Parameter", name_width);
    try out.appendSlice(a, "    DF    Estimate       Error           Limits           Chi-Square    Pr > ChiSq\n\n");
    for (0..r.p) |j| {
        const se = @sqrt(r.cov[j * r.p + j]);
        const chi = (r.beta[j] / se) * (r.beta[j] / se);
        const pv = chiTail(chi, 1);
        try padRight(a, out, if (j == 0) "Intercept" else ds.columns.items[s.effects[j - 1]].name, name_width);
        try out.appendSlice(a, "     1");
        try number(a, out, r.beta[j], 4, 12);
        try number(a, out, se, 4, 12);
        try number(a, out, r.beta[j] - z95 * se, 4, 12);
        try number(a, out, r.beta[j] + z95 * se, 4, 12);
        try number(a, out, chi, 2, 14);
        if (pv < 0.0001) try padLeft(a, out, "<.0001", 14) else try number(a, out, pv, 4, 14);
        try out.append(a, '\n');
    }
    // Scale limits are Wald limits for log(sigma), back-transformed.
    const spread = @exp(z95 * r.scale_se / r.scale);
    try padRight(a, out, "Scale", name_width);
    try out.appendSlice(a, "     1");
    try number(a, out, r.scale, 4, 12);
    try number(a, out, r.scale_se, 4, 12);
    try number(a, out, r.scale / spread, 4, 12);
    try number(a, out, r.scale * spread, 4, 12);
    try out.appendNTimes(a, ' ', 28);
    try out.appendSlice(a, "\n\nNOTE: The scale parameter was estimated by maximum likelihood.\n");
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const selections = try a.alloc(Selection, groups.len);
    for (groups, selections) |group, *sel| sel.* = try prepare(cx, s, group.rows);
    if (s.later.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: the {s} statement is not implemented", .{s.later[0]});
    if (s.exact or s.exact_only or s.strata.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: exact analysis is not implemented (STAT-GENMOD-010)", .{});
    // STAT-GENMOD-003: an option outside Table 51.7 is a user error everywhere.
    for (s.model_options) |name| if (logit.modelOption(name) == null)
        return cx.diags.fail(error.ParseError, l0, "PROC GENMOD: {s} is not a valid MODEL statement option", .{name});
    // STAT-GENMOD-003: events/trials binomial-logit model with CLASS main effects.
    if (s.trials != null and s.dist != null) {
        if (groups.len != 1) return proc.failGap(cx.diags, l0, "PROC GENMOD: BY groups or an empty input with a binomial model are not verified (STAT-GENMOD-003 remaining gap)", .{});
        var body: Out = .empty;
        try logit.run(cx, &body, s, selections[0], groups[0].rows, l0);
        return out.appendSlice(a, body.items);
    }
    // STAT-GENMOD-002 fits the Normal model with an identity or log link.
    // Everything else stays a loud gap: nothing is printed for the step.
    if (s.dist) |d| if (!eq(d, "normal") and !eq(d, "nor") and !eq(d, "n"))
        return proc.failGap(cx.diags, l0, "PROC GENMOD: DIST={s} estimation is not implemented (only DIST=NORMAL; STAT-GENMOD-005)", .{d});
    const link: fit.Link = if (s.link) |v| (if (eq(v, "log")) .log else if (eq(v, "identity") or eq(v, "id")) .identity else return proc.failGap(cx.diags, l0, "PROC GENMOD: LINK={s} is not implemented for DIST=NORMAL (STAT-GENMOD-005)", .{v})) else .identity;
    if (s.model_options.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: MODEL option {s} is not implemented (STAT-GENMOD-003)", .{s.model_options[0]});
    if (s.class.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: CLASS effects in the fitted model are not implemented (STAT-GENMOD-003/004)", .{});
    if (s.trials != null) return proc.failGap(cx.diags, l0, "PROC GENMOD: events/trials responses are not implemented (STAT-GENMOD-005)", .{});
    if (s.frequency != null or s.weight != null) return proc.failGap(cx.diags, l0, "PROC GENMOD: FREQ and WEIGHT in the fitted model are not verified against SAS output (STAT-GENMOD-002 remaining gap)", .{});
    if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, l0, "PROC GENMOD: the response variable must be numeric for DIST=NORMAL", .{});
    for (s.effects, 0..) |ci, j| if (has(s.effects[0..j], ci))
        return proc.failGap(cx.diags, l0, "PROC GENMOD: a repeated MODEL effect is not verified", .{});

    const p = s.effects.len + 1;
    var result: ?*Dataset = null;
    if (s.output) |request| {
        if (cx.lib.readonlyOut(request.name)) return cx.lib.failReadonly(request.name);
        // The section does not say what happens when a statistic takes the
        // name of an input variable; do not guess.
        for (request.items) |item| if (ds.indexOf(item.name) != null)
            return proc.failGap(cx.diags, l0, "PROC GENMOD: OUTPUT variable {s} already exists in the input data set; replacement is not verified", .{item.name});
        const created = try a.create(Dataset);
        created.* = Dataset.init(a, request.name);
        for (ds.columns.items) |c| _ = try created.addColumnLike(c.name, c);
        for (request.items) |item| _ = try created.addColumn(item.name, .num);
        result = created;
    }
    var body: Out = .empty;
    const Message = struct { row: []const Value };
    var messages: std.ArrayList(Message) = .empty;
    for (groups, selections) |group, sel| {
        // The printed layouts for these boundaries are not verified against SAS.
        if (sel.used <= p + 2) return proc.failGap(cx.diags, l0, "PROC GENMOD: a fit with {d} usable observations for {d} parameters is not verified", .{ sel.used, p + 1 });
        const x = try a.alloc(f64, sel.used * p);
        const y = try a.alloc(f64, sel.used);
        for (sel.rows, 0..) |ri, i| {
            const row = group.rows[ri];
            y[i] = row[s.response].num;
            x[i * p] = 1;
            for (s.effects, 1..) |ci, j| x[i * p + j] = row[ci].num;
        }
        const r = fit.fitNormal(a, x, y, sel.frequency, p, link) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return proc.failGap(cx.diags, l0, "PROC GENMOD: linearly dependent model columns (aliased parameters) are not implemented (STAT-GENMOD-004)", .{}),
            error.NotConverged => return proc.failGap(cx.diags, l0, "PROC GENMOD: the fit did not converge; nonconvergence reporting is not implemented", .{}),
            error.InvalidStart => return proc.failGap(cx.diags, l0, "PROC GENMOD: the log link needs a positive mean response for initial values; other starts are not implemented", .{}),
        };
        if (!(r.deviance > 0)) return proc.failGap(cx.diags, l0, "PROC GENMOD: a perfect fit (zero scale) is not verified", .{});
        if (s.by_cols.len > 0) try by.appendLine(a, &body, ds, group.rows[0], s.by_cols);
        try render(a, &body, s, sel, link, r);
        if (result) |created| {
            const request = s.output.?;
            const h = (try output.leverages(a, x, r.mu, p, link)) orelse return proc.failGap(cx.diags, l0, "PROC GENMOD: OUTPUT leverages for a singular weighted cross-product matrix are not verified", .{});
            for (h) |hv| if (!(hv < 1)) return proc.failGap(cx.diags, l0, "PROC GENMOD: OUTPUT standardized residuals at leverage 1 are not verified", .{});
            // p.3556: every input observation gets a row. XBETA, STDXBETA and
            // the predicted value with its limits need only the covariates;
            // residuals and leverage need an observation used in the fit.
            var used: usize = 0;
            for (group.rows, 0..) |row, ri| {
                const fitted = used < sel.rows.len and sel.rows[used] == ri;
                var design: ?[]f64 = try a.alloc(f64, p);
                design.?[0] = 1;
                for (s.effects, 1..) |ci, j| {
                    if (selection.missing(row[ci])) {
                        design = null;
                        break;
                    }
                    design.?[j] = row[ci].num;
                }
                const cells = try a.alloc(Value, created.columns.items.len);
                @memcpy(cells[0..row.len], row);
                for (request.items, row.len..) |item, ci|
                    cells[ci] = .{ .num = output.value(item.kind, .{ .x = design, .y = row[s.response].num, .h = if (fitted) h[used] else null }, r, link, z95) };
                if (fitted) used += 1;
                try created.appendRow(cells);
            }
        }
        try messages.append(a, .{ .row = group.rows[0] });
    }
    for (messages.items) |m| {
        try cx.diags.note(0, "Algorithm converged.", .{});
        try cx.diags.note(0, "The scale parameter was estimated by maximum likelihood.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, m.row, s.by_cols);
    }
    if (result) |created| {
        const member = s.output.?.name;
        try cx.lib.put(member, created);
        // Reference log: "NOTE: The data set WORK.RESIDUALS has 16 observations and 9 variables."
        // ponytail: a one-level name is reported under WORK (no USER libref lookup).
        const upper = try std.ascii.allocUpperString(a, member);
        const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, created.rows.items.len, created.columns.items.len });
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("genmod_tests.zig");
    _ = @import("genmod_fit.zig");
    _ = @import("genmod_binomial.zig");
}
