//! PROC PSMATCH (SAS/STAT 15.4 ch.101, STAT-PSMATCH-001): PROC statement
//! (DATA=, REGION=CS), CLASS / PSMODEL / MATCH / ASSESS / OUTPUT / BY / FREQ /
//! ID declarations and roles, the binary logistic propensity score fit, the
//! extended common support region, greedy nearest neighbor matching without
//! replacement (deterministic ORDER=DESCENDING|ASCENDING, K=1) and the default
//! listing (Data Information, Propensity Score Information, Matching
//! Information, Standardized Mean Differences) plus OUT(OBS=MATCH)=.
//!
//! Formulas (pp.8203-8204, 8213-8218, verified against the SAS listing):
//! - PS = fitted P(treated) of the main-effects logit model (CLASS covariates
//!   as indicators; the fitted probabilities do not depend on the coding).
//! - Pooled SD = sqrt((var_treated + var_control) / 2), n-1 divisors, over all
//!   observations; CS = [max(min_t, min_c), min(max_t, max_c)] in LPS,
//!   extended by 0.25 * pooled SD(LPS) at each end (EXTEND default).
//! - Caliper = r * pooled SD(LPS) (MULT=STDDEV default); treated units in the
//!   region in descending PS order each take the nearest available control in
//!   LPS (ties: first in data order) when |difference| <= caliper.
//! - Standardized difference = mean difference / pooled SD of All; percent
//!   reduction = 100 * (1 - |d| / |d_All|), floored at 0; variance ratio.
//! Everything else the cited pages define is a loud D-009 gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lfit = @import("logistic_fit.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Order = enum { descending, ascending };
pub const ObsSel = enum { all, region, match };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    class_cols: []const usize = &.{},
    treat: ?usize = null,
    treated_text: []const u8 = "",
    covs: []const usize = &.{},
    match: bool = false,
    k: usize = 1,
    order: Order = .descending,
    caliper: f64 = 0.25,
    assess: bool = false,
    assess_lps: bool = false,
    assess_vars: []const usize = &.{},
    out: ?[]const u8 = null,
    out_obs: ObsSel = .all,
    ps_name: []const u8 = "_PS_",
    weight_name: []const u8 = "_MATCHWGT_",
    matchid_name: ?[]const u8 = null,
    freq: ?usize = null,
    id: ?usize = null,
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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC PSMATCH: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
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
fn column(cx: proc.ProcCtx, ds: *const Dataset, tok: lex.Token, role: []const u8) diag.Error!usize {
    return ds.indexOf(tok.text) orelse cx.diags.fail(error.ParseError, tok.line, "PROC PSMATCH: variable {s} in the {s} statement is not on the input data set", .{ tok.text, role });
}
fn oneVar(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, numeric: bool) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = try column(cx, ds, t[i + 1], role);
    if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC PSMATCH: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var region_seen = false;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const l = t[i].line;
        if (kw(t, i, "data") and at(t, i + 1, .eq)) {
            if (name != null) return gap(cx.diags, l, "PROC PSMATCH: repeated DATA= option is not verified", .{});
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const j = i + 3;
            name = t[i + 2].text;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                return gap(cx.diags, l, "PROC PSMATCH: a two-level DATA= name is not verified", .{});
            }
            if (at(t, j, .lparen)) return gap(cx.diags, l, "PROC PSMATCH: data set options on DATA= are not verified", .{});
            i = j;
        } else if (kw(t, i, "region") and at(t, i + 1, .eq)) {
            if (region_seen) return gap(cx.diags, l, "PROC PSMATCH: repeated REGION= option is not verified", .{});
            region_seen = true;
            if (kw(t, i + 2, "cs")) {
                if (at(t, i + 3, .lparen)) return gap(cx.diags, l, "PROC PSMATCH: REGION=CS(EXTEND=...) suboptions are not implemented (STAT-PSMATCH-002)", .{});
                i += 3;
            } else if (kw(t, i + 2, "treated") or kw(t, i + 2, "allobs")) {
                return gap(cx.diags, l, "PROC PSMATCH: REGION={s} is not implemented; only REGION=CS is verified (STAT-PSMATCH-002)", .{t[i + 2].text});
            } else return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: REGION= must be ALLOBS, CS or TREATED", .{});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC PSMATCH: input data set not found", .{});
    s.data_name = name orelse raw.name;
    s.input = try proc.procInputObs(a, raw, t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var classes: std.ArrayList(usize) = .empty;
    var covs: std.ArrayList(usize) = .empty;
    var avars: std.ArrayList(usize) = .empty;
    var class_seen = false;
    var model_seen = false;
    var match_seen = false;
    var output_seen = false;
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
        const l = t[i].line;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "class")) {
            if (class_seen) return gap(cx.diags, l, "PROC PSMATCH: more than one CLASS statement is not verified", .{});
            class_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            for (t[i + 1 .. end]) |tok| {
                if (tok.tag != .name) return gap(cx.diags, l, "PROC PSMATCH: CLASS variable options are not implemented", .{});
                const ci = try column(cx, ds, tok, "CLASS");
                if (has(classes.items, ci)) return gap(cx.diags, l, "PROC PSMATCH: variable {s} listed twice in the CLASS statement is not verified", .{tok.text});
                if (ds.columns.items[ci].format != null) return gap(cx.diags, l, "PROC PSMATCH: a formatted CLASS variable is not verified", .{});
                try classes.append(a, ci);
            }
        } else if (eq(word, "psmodel")) {
            if (model_seen) return gap(cx.diags, l, "PROC PSMATCH: more than one PSMODEL statement is not verified", .{});
            model_seen = true;
            // p.8202: the CLASS statement must precede the PSMODEL statement.
            if (!class_seen) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: the CLASS statement must precede the PSMODEL statement", .{});
            var j = i + 1;
            if (!at(t, j, .name)) return invalid(cx, t, j);
            const tci = try column(cx, ds, t[j], "PSMODEL");
            if (!has(classes.items, tci)) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: the treatment variable {s} must be specified in the CLASS statement", .{t[j].text});
            s.treat = tci;
            j += 1;
            if (!at(t, j, .lparen) or !kw(t, j + 1, "treated") or !at(t, j + 2, .eq) or !at(t, j + 4, .rparen))
                return gap(cx.diags, l, "PROC PSMATCH: a PSMODEL treatment variable without the (TREATED='value') option is not implemented", .{});
            if (!at(t, j + 3, .string) and !at(t, j + 3, .number)) return invalid(cx, t, j + 3);
            s.treated_text = t[j + 3].text;
            j += 5;
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .slash)) return gap(cx.diags, l, "PROC PSMATCH: PSMODEL options after / are not implemented (STAT-PSMATCH-003)", .{});
                if (!at(t, j, .name) or (j + 1 < end and !at(t, j + 1, .name) and !at(t, j + 1, .slash)))
                    return gap(cx.diags, l, "PROC PSMATCH: PSMODEL effects other than main effects are not implemented (STAT-PSMATCH-003)", .{});
                const ci = try column(cx, ds, t[j], "PSMODEL");
                if (ci == tci) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: the treatment variable cannot be an effect in the PSMODEL statement", .{});
                if (has(covs.items, ci)) return gap(cx.diags, l, "PROC PSMATCH: a repeated PSMODEL effect is not verified", .{});
                if (!has(classes.items, ci) and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: variable {s} must be numeric or a CLASS variable", .{t[j].text});
                try covs.append(a, ci);
            }
        } else if (eq(word, "match")) {
            if (match_seen) return gap(cx.diags, l, "PROC PSMATCH: more than one MATCH statement is not verified", .{});
            match_seen = true;
            s.match = true;
            var method_greedy = false;
            var j = i + 1;
            while (j < end) {
                if (kw(t, j, "method") and at(t, j + 1, .eq)) {
                    if (!kw(t, j + 2, "greedy")) return gap(cx.diags, l, "PROC PSMATCH: METHOD={s} is not implemented; only METHOD=GREEDY is (STAT-PSMATCH-004)", .{t[@min(j + 2, end)].text});
                    method_greedy = true;
                    j += 3;
                    if (at(t, j, .lparen)) {
                        j += 1;
                        while (!at(t, j, .rparen)) {
                            if (j >= end) return invalid(cx, t, j);
                            if (kw(t, j, "k") and at(t, j + 1, .eq)) {
                                var v: f64 = 0;
                                j = number(t, j + 2, &v) orelse return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: K= must be a positive integer", .{});
                                if (!(v >= 1) or v != @floor(v)) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: K= must be a positive integer", .{});
                                if (v != 1) return gap(cx.diags, l, "PROC PSMATCH: greedy matching with K > 1 is not verified (STAT-PSMATCH-004)", .{});
                            } else if (kw(t, j, "order") and at(t, j + 1, .eq)) {
                                if (kw(t, j + 2, "descending")) s.order = .descending else if (kw(t, j + 2, "ascending")) s.order = .ascending else if (kw(t, j + 2, "random")) {
                                    return gap(cx.diags, l, "PROC PSMATCH: ORDER=RANDOM (SAS pseudo-random stream) is not implemented", .{});
                                } else return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: ORDER= must be ASCENDING, DESCENDING or RANDOM", .{});
                                j += 3;
                            } else return invalid(cx, t, j);
                        }
                        j += 1;
                    }
                } else if (kw(t, j, "distance") and at(t, j + 1, .eq)) {
                    if (!kw(t, j + 2, "lps")) return gap(cx.diags, l, "PROC PSMATCH: DISTANCE= other than LPS is not implemented (STAT-PSMATCH-004)", .{});
                    j += 3;
                } else if (kw(t, j, "caliper")) {
                    if (at(t, j + 1, .lparen)) return gap(cx.diags, l, "PROC PSMATCH: CALIPER suboptions are not implemented (STAT-PSMATCH-004)", .{});
                    if (!at(t, j + 1, .eq)) return invalid(cx, t, j + 1);
                    if (at(t, j + 2, .dot)) return gap(cx.diags, l, "PROC PSMATCH: CALIPER=. is not verified", .{});
                    var v: f64 = 0;
                    j = number(t, j + 2, &v) orelse return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: CALIPER= must be a number", .{});
                    if (!(v > 0)) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: CALIPER= must be missing or greater than 0", .{});
                    s.caliper = v;
                } else if (at(t, j, .name) and (at(t, j + 1, .eq) or at(t, j + 1, .lparen))) {
                    return gap(cx.diags, l, "PROC PSMATCH: the MATCH {s}= option is not implemented (STAT-PSMATCH-004)", .{t[j].text});
                } else return invalid(cx, t, j);
            }
            // p.8215: the default METHOD=OPTIMAL needs a network-flow solver.
            if (!method_greedy) return gap(cx.diags, l, "PROC PSMATCH: the default METHOD=OPTIMAL is not implemented; specify METHOD=GREEDY (STAT-PSMATCH-004)", .{});
        } else if (eq(word, "assess")) {
            if (s.assess) return gap(cx.diags, l, "PROC PSMATCH: more than one ASSESS statement is not verified", .{});
            s.assess = true;
            var j = i + 1;
            while (j < end) {
                if (kw(t, j, "lps")) {
                    s.assess_lps = true;
                    j += 1;
                } else if (kw(t, j, "var") and at(t, j + 1, .eq) and at(t, j + 2, .lparen)) {
                    j += 3;
                    while (!at(t, j, .rparen)) {
                        if (j >= end or !at(t, j, .name)) return invalid(cx, t, j);
                        const ci = try column(cx, ds, t[j], "ASSESS");
                        if (has(classes.items, ci)) return gap(cx.diags, l, "PROC PSMATCH: assessing a CLASS variable is not implemented (STAT-PSMATCH-005)", .{});
                        if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: variable {s} in the ASSESS statement must be numeric", .{t[j].text});
                        if (has(avars.items, ci)) return gap(cx.diags, l, "PROC PSMATCH: a variable listed twice in VAR= is not verified", .{});
                        try avars.append(a, ci);
                        j += 1;
                    }
                    j += 1;
                } else if (kw(t, j, "ps") or kw(t, j, "allcov") or at(t, j, .slash)) {
                    return gap(cx.diags, l, "PROC PSMATCH: the ASSESS {s} request is not implemented (STAT-PSMATCH-005)", .{t[j].text});
                } else return invalid(cx, t, j);
            }
            if (!s.assess_lps and avars.items.len == 0) return gap(cx.diags, l, "PROC PSMATCH: the default ASSESS PS request is not implemented (STAT-PSMATCH-005)", .{});
        } else if (eq(word, "output")) {
            if (output_seen) return gap(cx.diags, l, "PROC PSMATCH: more than one OUTPUT statement is not verified", .{});
            output_seen = true;
            var j = i + 1;
            if (!kw(t, j, "out")) return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: the OUTPUT statement requires OUT=", .{});
            j += 1;
            if (at(t, j, .lparen)) {
                if (!kw(t, j + 1, "obs") or !at(t, j + 2, .eq) or !at(t, j + 4, .rparen)) return invalid(cx, t, j + 1);
                if (kw(t, j + 3, "all")) s.out_obs = .all else if (kw(t, j + 3, "region")) s.out_obs = .region else if (kw(t, j + 3, "match")) s.out_obs = .match else return cx.diags.fail(error.ParseError, l, "PROC PSMATCH: OBS= must be ALL, REGION or MATCH", .{});
                j += 5;
            }
            if (!at(t, j, .eq) or !at(t, j + 1, .name)) return invalid(cx, t, j);
            if (at(t, j + 2, .dot) or at(t, j + 2, .lparen)) return gap(cx.diags, l, "PROC PSMATCH: a two-level or option-bearing OUT= name is not verified", .{});
            s.out = t[j + 1].text;
            j += 2;
            while (j < end) {
                if (!at(t, j, .name) or !at(t, j + 1, .eq) or !at(t, j + 2, .name)) return invalid(cx, t, j);
                const v = t[j + 2].text;
                if (kw(t, j, "ps")) s.ps_name = v else if (kw(t, j, "matchid")) s.matchid_name = v else if (kw(t, j, "weight")) s.weight_name = v else if (kw(t, j, "lps") or kw(t, j, "strata")) {
                    return gap(cx.diags, l, "PROC PSMATCH: the OUTPUT {s}= keyword is not implemented (STAT-PSMATCH-006)", .{t[j].text});
                } else return invalid(cx, t, j);
                j += 3;
            }
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, l, "PROC PSMATCH: more than one FREQ statement is not verified", .{});
            s.freq = try oneVar(cx, ds, t, i, end, "FREQ", true);
        } else if (eq(word, "id")) {
            if (s.id != null) return gap(cx.diags, l, "PROC PSMATCH: more than one ID statement is not verified", .{});
            s.id = try oneVar(cx, ds, t, i, end, "ID", false);
        } else if (eq(word, "strata") or eq(word, "psweight") or eq(word, "psdata")) {
            return gap(cx.diags, l, "PROC PSMATCH: the {s} statement is not implemented (STAT-PSMATCH-002/007)", .{word});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // p.8202: CLASS and PSMODEL (or PSDATA) are required.
    if (!class_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC PSMATCH: a CLASS statement is required", .{});
    if (!model_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC PSMATCH: a PSMODEL or PSDATA statement is required", .{});
    // p.8211: MATCH is not allowed with FREQ.
    if (s.match and s.freq != null) return cx.diags.fail(error.ParseError, line(t, 0), "PROC PSMATCH: the MATCH statement is not allowed if a FREQ statement is specified", .{});
    if (!s.match) return gap(cx.diags, line(t, 0), "PROC PSMATCH: analysis without a MATCH statement (weighting, stratification) is not implemented (STAT-PSMATCH-002/007)", .{});
    if (!region_seen) return gap(cx.diags, line(t, 0), "PROC PSMATCH: the default REGION=TREATED is not implemented; only REGION=CS is verified (STAT-PSMATCH-002)", .{});
    if (!s.assess) return gap(cx.diags, line(t, 0), "PROC PSMATCH: a MATCH analysis without an ASSESS statement is not verified", .{});
    if (s.out != null and s.out_obs != .match) return gap(cx.diags, line(t, 0), "PROC PSMATCH: OUTPUT OUT(OBS=ALL|REGION)= with MATCH is not verified (STAT-PSMATCH-006)", .{});
    if (covs.items.len == 0) return gap(cx.diags, line(t, 0), "PROC PSMATCH: an intercept-only PSMODEL is not verified", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (cols.len > 0 and s.out != null) return gap(cx.diags, line(t, 0), "PROC PSMATCH: OUTPUT with a BY statement (MATCHID numbering across groups) is not verified", .{});
    s.class_cols = classes.items;
    s.covs = covs.items;
    s.assess_vars = avars.items;
    return s;
}

const Stats = struct { n: usize = 0, w: f64 = 0, mean: f64 = nan, sd: f64 = nan, variance: f64 = nan, min: f64 = nan, max: f64 = nan };

fn stats(values: []const f64, sel: []const bool) Stats {
    var s: Stats = .{};
    var sum: f64 = 0;
    for (values, sel) |v, k| if (k) {
        s.n += 1;
        sum += v;
        s.min = if (s.n == 1) v else @min(s.min, v);
        s.max = if (s.n == 1) v else @max(s.max, v);
    };
    if (s.n == 0) return s;
    s.w = @floatFromInt(s.n);
    s.mean = sum / s.w;
    var ss: f64 = 0;
    for (values, sel) |v, k| if (k) {
        ss += (v - s.mean) * (v - s.mean);
    };
    if (s.n > 1) {
        s.variance = ss / (s.w - 1);
        s.sd = @sqrt(s.variance);
    }
    return s;
}

pub const Sets = enum(u2) { all, region, matched };

/// The result of one analysis (one BY group).
pub const Group = struct {
    ps: []f64,
    lps: []f64,
    treated: []bool,
    used: []bool,
    in_region: []bool,
    matched: []bool,
    match_id: []usize,
    lower: f64,
    upper: f64,
    caliper: f64,
    n_sets: usize,
    total_diff: f64,
    short_controls: bool,
    caliper_unmatched: usize = 0,
};

pub const Fail = error{ OutOfMemory, NotConverged, Unmatched, Degenerate, Levels };

/// Matching on already computed propensity scores (`used` marks analysed
/// rows). Exposed for unit tests.
pub fn matchGreedy(a: A, ps: []f64, treated: []const bool, used: []const bool, caliper_r: f64, order: Order, g: *Group) Fail!void {
    const n = ps.len;
    const lps = try a.alloc(f64, n);
    for (ps, 0..) |p, r| lps[r] = if (used[r]) @log(p / (1 - p)) else nan;
    g.lps = lps;
    const selt = try a.alloc(bool, n);
    const selc = try a.alloc(bool, n);
    for (0..n) |r| {
        selt[r] = used[r] and treated[r];
        selc[r] = used[r] and !treated[r];
    }
    const st = stats(lps, selt);
    const sc = stats(lps, selc);
    if (st.n < 2 or sc.n < 2) return error.Degenerate;
    const sd = @sqrt((st.variance + sc.variance) / 2);
    const lo = @max(st.min, sc.min) - 0.25 * sd;
    const hi = @min(st.max, sc.max) + 0.25 * sd;
    g.lower = lfit.probability(lo);
    g.upper = lfit.probability(hi);
    g.caliper = caliper_r * sd;
    const in_region = try a.alloc(bool, n);
    for (0..n) |r| in_region[r] = used[r] and lps[r] >= lo and lps[r] <= hi;
    g.in_region = in_region;
    // Treated units in the region, ordered by PS (stable: data order on ties).
    var order_rows: std.ArrayList(usize) = .empty;
    for (0..n) |r| if (in_region[r] and treated[r]) try order_rows.append(a, r);
    const Ctx = struct {
        ps: []const f64,
        desc: bool,
        fn lt(c: @This(), x: usize, y: usize) bool {
            return if (c.desc) c.ps[x] > c.ps[y] else c.ps[x] < c.ps[y];
        }
    };
    std.sort.insertion(usize, order_rows.items, Ctx{ .ps = ps, .desc = order == .descending }, Ctx.lt);
    const matched = try a.alloc(bool, n);
    const ids = try a.alloc(usize, n);
    @memset(matched, false);
    @memset(ids, 0);
    g.caliper_unmatched = 0;
    var sets: usize = 0;
    var total: f64 = 0;
    var short = false;
    for (order_rows.items) |tr| {
        var best: ?usize = null;
        var bd: f64 = std.math.inf(f64);
        for (0..n) |c| {
            if (!in_region[c] or treated[c] or matched[c]) continue;
            const d = @abs(lps[tr] - lps[c]);
            if (d < bd) {
                bd = d;
                best = c;
            }
        }
        const c = best orelse {
            short = true;
            continue;
        };
        if (bd > g.caliper) {
            g.caliper_unmatched += 1;
            continue;
        }
        sets += 1;
        matched[tr] = true;
        matched[c] = true;
        ids[tr] = sets;
        ids[c] = sets;
        total += bd;
    }
    g.matched = matched;
    g.match_id = ids;
    g.n_sets = sets;
    g.total_diff = total;
    g.short_controls = short;
}

fn levelText(a: A, v: Value) ![]const u8 {
    return proc.cellText(a, v);
}

fn analyze(a: A, ds: *const Dataset, rows: []const []const Value, s: Spec) Fail!Group {
    const n = rows.len;
    const treat = s.treat.?;
    var g: Group = undefined;
    const used = try a.alloc(bool, n);
    const treated = try a.alloc(bool, n);
    // Distinct levels of each CLASS covariate among the used rows.
    for (rows, 0..) |row, r| {
        var ok = !row[treat].isMissing();
        for (s.covs) |ci| if (row[ci].isMissing()) {
            ok = false;
        };
        used[r] = ok;
        treated[r] = ok and std.mem.eql(u8, try levelText(a, row[treat]), s.treated_text);
    }
    // Exactly two treatment levels.
    var control_level: ?[]const u8 = null;
    for (rows, 0..) |row, r| if (used[r] and !treated[r]) {
        const txt = try levelText(a, row[treat]);
        if (control_level) |c| {
            if (!std.mem.eql(u8, c, txt)) return error.Levels;
        } else control_level = txt;
    };
    if (control_level == null) return error.Levels;
    // Design: intercept, one column per continuous covariate, indicators for
    // all but the last sorted level of a CLASS covariate.
    var levels: std.ArrayList([]const Value) = .empty;
    var p: usize = 1;
    for (s.covs) |ci| {
        if (!has(s.class_cols, ci)) {
            try levels.append(a, &.{});
            p += 1;
            continue;
        }
        var lv: std.ArrayList(Value) = .empty;
        for (rows, 0..) |row, r| if (used[r]) {
            var found = false;
            for (lv.items) |x| if (proc.cmpValue(x, row[ci]) == .eq) {
                found = true;
            };
            if (!found) try lv.append(a, row[ci]);
        };
        std.sort.insertion(Value, lv.items, {}, struct {
            fn lt(_: void, x: Value, y: Value) bool {
                return proc.cmpValue(x, y) == .lt;
            }
        }.lt);
        try levels.append(a, lv.items);
        if (lv.items.len > 1) p += lv.items.len - 1;
    }
    var m: usize = 0;
    for (used) |u| if (u) {
        m += 1;
    };
    const x = try a.alloc(f64, m * p);
    const y = try a.alloc(f64, m);
    var k: usize = 0;
    for (rows, 0..) |row, r| if (used[r]) {
        const xr = x[k * p ..][0..p];
        xr[0] = 1;
        var c: usize = 1;
        for (s.covs, 0..) |ci, e| {
            const lv = levels.items[e];
            if (!has(s.class_cols, ci)) {
                xr[c] = row[ci].num;
                c += 1;
            } else if (lv.len > 1) {
                for (lv[0 .. lv.len - 1]) |v| {
                    xr[c] = if (proc.cmpValue(v, row[ci]) == .eq) 1 else 0;
                    c += 1;
                }
            }
        }
        y[k] = if (treated[r]) 1 else 0;
        k += 1;
    };
    _ = ds;
    // ponytail: SAS PSMATCH reports the MLE to more digits than LOGISTIC's
    // default GCONV=1e-8 delivers (LPS SD 0.311586 vs 0.311578); iterate to
    // machine precision instead. Verified against the reference listing.
    const f = lfit.fit(a, x, y, m, p, .{ .gconv = 1e-15, .max_iterations = 50 }) catch return error.Degenerate;
    if (!f.converged) return error.NotConverged;
    const ps = try a.alloc(f64, n);
    k = 0;
    for (0..n) |r| {
        if (used[r]) {
            ps[r] = f.probabilities[k];
            k += 1;
        } else ps[r] = nan;
    }
    g.ps = ps;
    g.treated = treated;
    g.used = used;
    try matchGreedy(a, ps, treated, used, s.caliper, s.order, &g);
    return g;
}

fn fixed(a: A, v: f64, d: usize) ![]const u8 {
    if (std.math.isNan(v)) return ".";
    return switch (d) {
        2 => std.fmt.allocPrint(a, "{d:.2}", .{v}),
        3 => std.fmt.allocPrint(a, "{d:.3}", .{v}),
        4 => std.fmt.allocPrint(a, "{d:.4}", .{v}),
        5 => std.fmt.allocPrint(a, "{d:.5}", .{v}),
        else => std.fmt.allocPrint(a, "{d:.6}", .{v}),
    };
}
fn spaces(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn left(a: A, out: *Out, text: []const u8, w: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < w) try spaces(a, out, w - text.len);
}
fn right(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try spaces(a, out, w - text.len) else try out.append(a, ' ');
    try out.appendSlice(a, text);
}
fn centered(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try spaces(a, out, (w - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

const Pair = struct { []const u8, []const u8 };
fn keyValue(a: A, out: *Out, title: []const u8, rows: []const Pair) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (rows) |r| {
        lw = @max(lw, r[0].len);
        vw = @max(vw, r[1].len);
    }
    try centered(a, out, title, lw + 4 + vw);
    try out.append(a, '\n');
    for (rows) |r| {
        try left(a, out, r[0], lw);
        try right(a, out, r[1], vw + 4);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
}

fn pick(a: A, g: Group, set: Sets, treated: bool) ![]bool {
    const v = try a.alloc(bool, g.ps.len);
    for (v, 0..) |*b, r| {
        const base = g.used[r] and g.treated[r] == treated;
        b.* = base and switch (set) {
            .all => true,
            .region => g.in_region[r],
            .matched => g.matched[r],
        };
    }
    return v;
}

fn upperName(a: A, n: []const u8) ![]const u8 {
    const u = try std.ascii.allocUpperString(a, n);
    return if (std.mem.indexOfScalar(u8, n, '.') == null) std.fmt.allocPrint(a, "WORK.{s}", .{u}) else u;
}

/// Page header after a page break: titles and the BY line (verified).
fn pageHeader(cx: proc.ProcCtx, out: *Out, ds: *const Dataset, s: Spec, rows: []const []const Value) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out);
    if (s.by_cols.len > 0) try by.appendLine(cx.arena, out, @constCast(ds), rows[0], s.by_cols);
}

fn render(cx: proc.ProcCtx, out: *Out, ds: *const Dataset, s: Spec, g: Group, rows: []const []const Value) !void {
    const a = cx.arena;
    const tname = ds.columns.items[s.treat.?].name;
    var control_text: []const u8 = "";
    for (rows, 0..) |row, r| if (g.used[r] and !g.treated[r]) {
        control_text = try proc.cellText(a, row[s.treat.?]);
        break;
    };
    const cnt = struct {
        fn f(v: []const bool) usize {
            var c: usize = 0;
            for (v) |b| if (b) {
                c += 1;
            };
            return c;
        }
    }.f;
    const ta = try pick(a, g, .all, true);
    const ca = try pick(a, g, .all, false);
    const tr = try pick(a, g, .region, true);
    const cr = try pick(a, g, .region, false);
    const tm = try pick(a, g, .matched, true);
    const cm = try pick(a, g, .matched, false);
    try out.appendSlice(a, "\nThe PSMATCH Procedure\n\n");
    var info: std.ArrayList(Pair) = .empty;
    try info.append(a, .{ "Data Set", try upperName(a, s.data_name) });
    if (s.out) |o| try info.append(a, .{ "Output Data Set", try upperName(a, o) });
    try info.append(a, .{ "Treatment Variable", tname });
    try info.append(a, .{ "Treated Group", s.treated_text });
    try info.append(a, .{ "All Obs (Treated)", try std.fmt.allocPrint(a, "{d}", .{cnt(ta)}) });
    try info.append(a, .{ "All Obs (Control)", try std.fmt.allocPrint(a, "{d}", .{cnt(ca)}) });
    try info.append(a, .{ "Support Region", "Extended Common Support" });
    try info.append(a, .{ "Lower PS Support", try fixed(a, g.lower, 6) });
    try info.append(a, .{ "Upper PS Support", try fixed(a, g.upper, 6) });
    try info.append(a, .{ "Support Region Obs (Treated)", try std.fmt.allocPrint(a, "{d}", .{cnt(tr)}) });
    try info.append(a, .{ "Support Region Obs (Control)", try std.fmt.allocPrint(a, "{d}", .{cnt(cr)}) });
    try keyValue(a, out, "Data Information", info.items);

    // Propensity Score Information (fixed 151-column layout).
    const tlabel = try std.fmt.allocPrint(a, "Treated ({s} = {s})", .{ tname, s.treated_text });
    const clabel = try std.fmt.allocPrint(a, "Control ({s} = {s})", .{ tname, control_text });
    try centered(a, out, "Propensity Score Information", 151);
    try out.appendSlice(a, " \n");
    try spaces(a, out, 142);
    try out.appendSlice(a, "Treated -\n");
    try spaces(a, out, 16);
    for ([_][]const u8{ tlabel, clabel }) |lab| {
        const fill = 58 - lab.len;
        try spaces(a, out, 3);
        try out.appendNTimes(a, '-', fill / 2);
        try out.appendSlice(a, lab);
        try out.appendNTimes(a, '-', fill - fill / 2);
    }
    try out.appendSlice(a, "     Control\n");
    try spaces(a, out, 49);
    try out.appendSlice(a, "Standard");
    try spaces(a, out, 53);
    try out.appendSlice(a, "Standard");
    try spaces(a, out, 29);
    try out.appendSlice(a, "Mean\n");
    try out.appendSlice(a, "Observations            N     Weight     Mean   Deviation   Minimum   Maximum        N     Weight     Mean   Deviation   Minimum   Maximum   Difference\n\n");
    const labels = [_][]const u8{ "All", "Region", "Matched", "Weighted Matched" };
    const tsets = [_][]bool{ ta, tr, tm, tm };
    const csets = [_][]bool{ ca, cr, cm, cm };
    // Verified (SAS 9.4): the difference column keeps six characters, so a
    // negative difference anywhere drops it to three decimals.
    var diff_dec: usize = 4;
    for (0..4) |li| {
        const dlt = stats(g.ps, tsets[li]).mean - stats(g.ps, csets[li]).mean;
        if (dlt < 0) diff_dec = 3;
    }
    for (labels, 0..) |lab, li| {
        try left(a, out, lab, 16);
        const st = stats(g.ps, tsets[li]);
        const sc = stats(g.ps, csets[li]);
        for ([_]Stats{ st, sc }) |x| {
            try right(a, out, try std.fmt.allocPrint(a, "{d}", .{x.n}), 9);
            try right(a, out, if (li == 3) try fixed(a, x.w, 2) else "", 11);
            try right(a, out, try fixed(a, x.mean, 4), 9);
            try right(a, out, try fixed(a, x.sd, 4), 12);
            try right(a, out, try fixed(a, x.min, 4), 10);
            try right(a, out, try fixed(a, x.max, 4), 10);
        }
        try right(a, out, try fixed(a, st.mean - sc.mean, diff_dec), 13);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    var mi: std.ArrayList(Pair) = .empty;
    try mi.append(a, .{ "Distance Metric", "Logit of Propensity Score" });
    try mi.append(a, .{ "Method", "Greedy Matching" });
    try mi.append(a, .{ "Control/Treated Ratio", "1" });
    try mi.append(a, .{ "Order", if (s.order == .descending) "Descending" else "Ascending" });
    try mi.append(a, .{ "Caliper (Logit PS)", try fixed(a, g.caliper, 6) });
    try mi.append(a, .{ "Matched Sets", try std.fmt.allocPrint(a, "{d}", .{g.n_sets}) });
    try mi.append(a, .{ "Matched Obs (Treated)", try std.fmt.allocPrint(a, "{d}", .{cnt(tm)}) });
    try mi.append(a, .{ "Matched Obs (Control)", try std.fmt.allocPrint(a, "{d}", .{cnt(cm)}) });
    try mi.append(a, .{ "Total Absolute Difference", try fixed(a, g.total_diff, 6) });
    // Drop the trailing blank pair: the next page header follows directly.
    try keyValue(a, out, "Matching Information", mi.items);
    out.items.len -= 1;

    // Standardized Mean Differences (104-column layout).
    try pageHeader(cx, out, ds, s, rows);
    try out.appendSlice(a, "The PSMATCH Procedure\n\n");
    try centered(a, out, "Standardized Mean Differences (Treated - Control)", 104);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "                                              Mean     Standard    Standardized      Percent    Variance\n");
    try out.appendSlice(a, "Variable            Observations        Difference    Deviation      Difference    Reduction       Ratio\n\n");
    var vars: std.ArrayList(struct { []const u8, []const f64 }) = .empty;
    if (s.assess_lps) try vars.append(a, .{ "Logit Prop Score", g.lps });
    for (s.assess_vars) |ci| {
        const v = try a.alloc(f64, rows.len);
        for (rows, 0..) |row, r| v[r] = row[ci].num;
        try vars.append(a, .{ ds.columns.items[ci].name, v });
    }
    for (vars.items) |vv| {
        const st0 = stats(vv[1], ta);
        const sc0 = stats(vv[1], ca);
        const sd = @sqrt((st0.variance + sc0.variance) / 2);
        const d0 = (st0.mean - sc0.mean) / sd;
        for (labels, 0..) |lab, li| {
            const st = stats(vv[1], tsets[li]);
            const sc = stats(vv[1], csets[li]);
            const d = (st.mean - sc.mean) / sd;
            try left(a, out, if (li == 0) vv[0] else "", 20);
            try left(a, out, lab, 16);
            try right(a, out, try fixed(a, st.mean - sc.mean, 5), 14);
            try right(a, out, if (li == 0) try fixed(a, sd, 5) else "", 13);
            try right(a, out, try fixed(a, d, 5), 16);
            try right(a, out, if (li == 0) "" else try fixed(a, @max(0, 100 * (1 - @abs(d) / @abs(d0))), 2), 13);
            try right(a, out, try fixed(a, st.variance / sc.variance, 4), 12);
            try out.append(a, '\n');
        }
    }
    try out.append(a, '\n');
    try centered(a, out, "Standard deviation of All observations used to compute standardized differences", 104);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const gap = proc.failGap;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return gap(cx.diags, l0, "PROC PSMATCH: an input data set with no observations is not verified against SAS output", .{});
    var o: ?*Dataset = null;
    if (s.out) |_| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, s.out.?);
        for (ds.columns.items) |col| _ = try d.addColumnLike(col.name, col);
        for ([_]?[]const u8{ s.ps_name, s.weight_name, s.matchid_name }) |nm| if (nm) |x| {
            if (d.indexOf(x) != null) return gap(cx.diags, l0, "PROC PSMATCH: an output variable named like an input variable is not verified", .{});
            _ = try d.addColumn(x, .num);
        };
        // Labels verified with PROC CONTENTS on the SAS output data set.
        d.setLabel(s.ps_name, "Propensity Score");
        d.setLabel(s.weight_name, "Matched obs ATT weight");
        if (s.matchid_name) |x| d.setLabel(x, "Matched ID number");
        o = d;
    }
    for (groups) |grp| {
        const g = analyze(a, ds, grp.rows, s) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Levels => return cx.diags.fail(error.ExecError, l0, "PROC PSMATCH: the treatment variable must have exactly two levels, one of them the TREATED= value", .{}),
            error.NotConverged => return gap(cx.diags, l0, "PROC PSMATCH: a propensity score model that does not converge is not verified", .{}),
            error.Degenerate => return gap(cx.diags, l0, "PROC PSMATCH: a degenerate propensity score fit (fewer than two treated or control observations) is not verified", .{}),
            error.Unmatched => return gap(cx.diags, l0, "PROC PSMATCH: treated units left unmatched by the caliper are not verified", .{}),
        };
        // Verified (SAS 9.4): the warning is issued whenever a treated unit in
        // the region stays unmatched, by the caliper or by exhausted controls.
        if (g.short_controls or g.caliper_unmatched > 0) try cx.diags.warnStatus(l0, "Some treated units do not have matched controls because there are not enough available controls for these treated units.", .{});
        try pageHeader(cx, out, ds, s, grp.rows);
        try render(cx, out, ds, s, g, grp.rows);
        if (o) |d| for (grp.rows, 0..) |row, r| {
            if (!g.matched[r]) continue;
            const values = try a.alloc(Value, d.columns.items.len);
            @memcpy(values[0..row.len], row);
            var c = row.len;
            values[c] = .{ .num = g.ps[r] };
            c += 1;
            values[c] = .{ .num = 1 };
            c += 1;
            if (s.matchid_name != null) values[c] = .{ .num = @floatFromInt(g.match_id[r]) };
            try d.appendRow(values);
        };
    }
    if (o) |d| {
        try cx.lib.put(s.out.?, d);
        try cx.diags.note(0, "The data set {s} has {d} observations and {d} variables.", .{ try upperName(a, s.out.?), d.rows.items.len, d.columns.items.len });
    }
}

test {
    _ = @import("psmatch_tests.zig");
}
