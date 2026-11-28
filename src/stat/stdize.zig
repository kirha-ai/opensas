//! PROC STDIZE (SAS/STAT 15.4 ch.115, STAT-STDIZE-001): PROC statement
//! options, VAR / BY / FREQ / WEIGHT roles, missing-value rules, the OUT=
//! data set and the PSTAT "Location and Scale Measures" table.
//!
//! Implemented location/scale measures (Table 115.2, closed form): MEAN,
//! MEDIAN, SUM, EUCLEN, USTD, STD, RANGE, MIDRANGE, MAXABS, IQR and MAD;
//! STAT-STDIZE-003 adds ABW/AHUBER/AWAVE(c) with INITIAL=, SPACING(p) (+NORM),
//! AGK(p) and METHOD=IN(ds) with the LOCATION / SCALE statements and UNSTD.
//! Percentiles use the order-statistics method with PCTLDEF=5 (the documented
//! default). Every other documented option, method or statement — and every
//! listing whose layout has not been verified against a SAS listing — is a
//! loud D-009 gap; nothing is written or printed for a step that hits one.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const polychoric = @import("corr_polychoric.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { mean, median, sum, euclen, ustd, std, range, midrange, maxabs, iqr, mad, abw, ahuber, awave, agk, spacing, in };
pub const VarDef = enum { df, n, wdf, weight };

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement (pp.9445-9448). Defaults: METHOD=STD, ADD=0, MULT=1,
    // FUZZ=1E-14, VARDEF=DF, PCTLMTD=ORD_STAT, PCTLDEF=5.
    method: Method = .std,
    /// METHOD= argument: c of ABW/AHUBER/AWAVE, p of AGK/SPACING (p.9452).
    arg: f64 = 0,
    /// METHOD=IN(ds): the location/scale data set (p.9453).
    in_ds: ?*Dataset = null,
    /// LOCATION / SCALE statement variables (p.9450), names in the IN data set.
    loc_vars: []const []const u8 = &.{},
    scale_vars: []const []const u8 = &.{},
    unstd: bool = false,
    add: f64 = 0,
    mult: f64 = 1,
    fuzz: f64 = 1e-14,
    vardef: VarDef = .df,
    nomiss: bool = false,
    replace: bool = false,
    reponly: bool = false,
    /// MISSING=value: replaces missing values after standardizing.
    missing: ?f64 = null,
    /// MISSING=method: that method's location replaces missing values
    /// before standardizing (p.9446).
    missing_method: ?Method = null,
    missing_arg: f64 = 0,
    /// NORM (p.9446): IQR and MAD scales made consistent for a normal sigma.
    norm: bool = false,
    /// SNORM (p.9448): only meaningful for METHOD=SPACING.
    snorm: bool = false,
    /// INITIAL= was given (only meaningful for ABW, AHUBER, AWAVE).
    initial: bool = false,
    /// INITIAL= method for the A estimates (p.9445); default MAD.
    initial_method: Method = .mad,
    initial_arg: f64 = 0,
    pstat: bool = false,
    /// PCTLDEF= (pp.9446, 9455-9456) for ORD_STAT percentiles.
    pctldef: u8 = 5,
    pctldef_given: bool = false,
    /// PCTLPTS= was given (its values only feed OUTSTAT=).
    pctlpts: bool = false,
    /// OUT= member; null means the DATAn convention.
    out: ?[]const u8 = null,
    // Roles.
    vars: []const usize = &.{},
    freq: ?usize = null,
    /// FREQ / NOTRUNCATE (p.9450): frequencies used as given (> 0).
    notruncate: bool = false,
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
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC STDIZE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
/// `name` or `lib.name`, optionally followed by a data set option list.
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8, options: *bool) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) {
        options.* = true;
        j = proc.skipParen(t, j);
    }
    into.* = name;
    return j;
}
/// A signed numeric option value at t[i].
fn number(t: []const lex.Token, i: *usize) ?f64 {
    var neg = false;
    if (at(t, i.*, .minus)) {
        neg = true;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return null;
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return null;
    i.* += 1;
    return if (neg) -v else v;
}

const method_names = [_]struct { []const u8, Method }{
    .{ "mean", .mean },     .{ "median", .median }, .{ "sum", .sum },     .{ "euclen", .euclen },
    .{ "ustd", .ustd },     .{ "std", .std },       .{ "range", .range }, .{ "midrange", .midrange },
    .{ "maxabs", .maxabs }, .{ "iqr", .iqr },       .{ "mad", .mad },
    .{ "abw", .abw },       .{ "ahuber", .ahuber }, .{ "awave", .awave }, .{ "agk", .agk },
    .{ "spacing", .spacing }, .{ "in", .in },
};
/// Documented METHOD= names (p.9445) whose estimators are not implemented.
/// ponytail: L(p) follows the PROC FASTCLUS LEAST=p iteration, whose stopping
/// rule is not documented here (SAS L(1.5) differs from the exact minimizer
/// in the 6th decimal), so it stays a loud gap.
const method_gaps = [_][]const u8{ "l", "least" };
fn hasArg(m: Method) bool {
    return switch (m) {
        .abw, .ahuber, .awave, .agk, .spacing => true,
        else => false,
    };
}
fn isAEstimate(m: Method) bool {
    return m == .abw or m == .ahuber or m == .awave;
}
/// `(number)` after a method name at t[i.*] (SAS: ERROR 79-322 "Expecting a
/// (." when it is missing). ABW/AHUBER/AWAVE need c > 0 (SAS-verified ERROR).
fn methodArg(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, m: Method, l: usize) diag.Error!f64 {
    if (!at(t, i.*, .lparen)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: expecting a ( after METHOD {s}", .{@tagName(m)});
    i.* += 1;
    const v = number(t, i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: the {s} argument must be a number", .{@tagName(m)});
    if (!at(t, i.*, .rparen)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: expecting a ) after the {s} argument", .{@tagName(m)});
    i.* += 1;
    if (isAEstimate(m) and !(v > 0)) return cx.diags.fail(error.ParseError, l, "The value of METHOD= ABW(), AHUBER() or AWAVE() must be greater than zero.", .{});
    if (m == .agk or m == .spacing) {
        // SAS-verified ERROR text for p <= 0.
        if (!(v > 0)) return cx.diags.fail(error.ParseError, l, "The value of METHOD  = AGK() or METHOD  = SPACING() must be greater than zero.", .{});
        // ponytail: AGK(p) with p > 1 (SAS: "too small to have at least one
        // pair") is not modelled.
        if (m == .agk and v > 1) return proc.failGap(cx.diags, l, "PROC STDIZE: AGK(p) with p > 1 is not implemented", .{});
    }
    return v;
}

/// Documented PROC STDIZE options (Table 115.1) this ticket does not implement.
const option_gaps = [_][]const u8{ "keeplen", "oprefix", "sprefix", "outstat" };

fn methodByName(m: []const u8) ?Method {
    for (method_names) |p| if (eq(m, p[0])) return p[1];
    return null;
}
/// The PROC STDIZE location of `m` with that method's own WEIGHT rule:
/// RANGE, MIDRANGE and MAXABS ignore the WEIGHT variable (p.9450, SAS
/// warning "The WEIGHT variable does not apply").
fn ignoresWeight(m: Method) bool {
    return m == .range or m == .midrange or m == .maxabs;
}
/// ABW, AHUBER, AWAVE and SPACING also ignore it (SAS-verified WARNING).
fn ignoresWeightRobust(m: Method) bool {
    return m == .abw or m == .ahuber or m == .awave or m == .spacing;
}
fn isPercentile(m: Method) bool {
    return m == .median or m == .iqr or m == .mad;
}
/// Phi^-1(p) for 0.5 <= p < 1 by bisection on the erfc-accurate upper tail.
fn zQuantile(p: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 40;
    for (0..200) |_| {
        const mid = (lo + hi) / 2;
        if (mid == lo or mid == hi) break;
        if (1 - polychoric.normalTail(mid) < p) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}
/// 1 / Phi^-1(0.75): NORM divides IQR by 2*z(0.75) and MAD by z(0.75)
/// (SAS-verified: IQR 4 -> 2.965204, MAD 2 -> 2.965204).
const z75: f64 = 0.6744897501960817;

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
        const option = try std.ascii.allocLowerString(a, t[i].text);
        const l = t[i].line;
        // A repeated PROC statement option: the last one wins (SAS-verified
        // for METHOD=, ADD= and MULT=; flags are idempotent).
        _ = try seen.getOrPut(a, option);
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            var ignored = false;
            const after = try memberName(cx, t, first, &name, &ignored);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "out") and valued) {
            var options = false;
            i = try memberName(cx, t, i + 2, &s.out, &options);
            if (options) return gap(cx.diags, l, "PROC STDIZE: data set options on OUT= are not implemented", .{});
        } else if (eq(option, "method") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: METHOD= must be a method name", .{});
            const m = t[i + 2].text;
            if (methodByName(m)) |f| {
                s.method = f;
            } else {
                for (method_gaps) |g| if (eq(m, g)) return gap(cx.diags, l, "PROC STDIZE: METHOD={s} is not implemented (STAT-STDIZE-003)", .{m});
                return cx.diags.fail(error.ParseError, l, "PROC STDIZE: METHOD={s} is not a valid standardization method", .{m});
            }
            i += 3;
            if (hasArg(s.method)) {
                s.arg = try methodArg(cx, t, &i, s.method, l);
            } else if (s.method == .in) {
                // METHOD=IN(ds) (p.9453).
                if (!at(t, i, .lparen)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: expecting a ( after METHOD=IN", .{});
                var in_name: ?[]const u8 = null;
                var in_opts = false;
                i = try memberName(cx, t, i + 1, &in_name, &in_opts);
                if (in_opts) return gap(cx.diags, l, "PROC STDIZE: data set options on METHOD=IN( ) are not implemented", .{});
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
                s.in_ds = cx.lib.find(in_name.?) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: the METHOD=IN data set {s} does not exist", .{in_name.?});
            } else if (at(t, i, .lparen)) return gap(cx.diags, l, "PROC STDIZE: a METHOD= argument is not implemented", .{});
        } else if ((eq(option, "add") or eq(option, "mult") or eq(option, "fuzz")) and valued) {
            i += 2;
            const v = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: {s}= must be a number", .{option});
            if (eq(option, "add")) s.add = v else if (eq(option, "mult")) s.mult = v else {
                if (v < 0) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: FUZZ= must be nonnegative", .{});
                s.fuzz = v;
            }
        } else if (eq(option, "vardef") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            const v = t[i + 2].text;
            s.vardef = if (eq(v, "df")) .df else if (eq(v, "n")) .n else if (eq(v, "wdf")) .wdf else if (eq(v, "weight") or eq(v, "wgt")) .weight else return cx.diags.fail(error.ParseError, l, "PROC STDIZE: VARDEF={s} is not valid", .{v});
            i += 3;
        } else if (eq(option, "pctlmtd") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLMTD= must be ORD_STAT, ONEPASS or P2", .{});
            const v = t[i + 2].text;
            if (!eq(v, "ord_stat")) {
                // ponytail: the one-pass estimator modifies the P2 algorithm in
                // ways the guide does not specify (marker moves, p.9455); SAS
                // gives 8 / 58.2222 where order statistics give 17 / 50 for ten
                // values, so it stays a loud gap.
                if (eq(v, "onepass") or eq(v, "p2")) return gap(cx.diags, l, "PROC STDIZE: PCTLMTD={s} (one-pass quantile estimation) is not implemented", .{v});
                return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLMTD={s} is not valid", .{v});
            }
            i += 3;
        } else if (eq(option, "pctldef") and valued) {
            i += 2;
            const v = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLDEF= must be a number", .{});
            // SAS-verified text for 0 and 6. ponytail: a nonintegral value
            // is rejected the same way.
            if (!(v >= 1 and v <= 5 and v == @floor(v))) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is not within the required range of 1 and 5.", .{v});
            s.pctldef = @intFromFloat(v);
            s.pctldef_given = true;
            continue;
        } else if (eq(option, "missing") and valued) {
            i += 2;
            if (at(t, i, .name)) {
                const m = t[i].text;
                const f = methodByName(m) orelse {
                    for (method_gaps) |g| if (eq(m, g)) return gap(cx.diags, l, "PROC STDIZE: MISSING={s} is not implemented (STAT-STDIZE-003)", .{m});
                    return cx.diags.fail(error.ParseError, l, "PROC STDIZE: MISSING={s} is not a valid standardization method", .{m});
                };
                i += 1;
                if (f == .in) return gap(cx.diags, l, "PROC STDIZE: MISSING=IN is not implemented", .{});
                if (hasArg(f)) {
                    s.missing_arg = try methodArg(cx, t, &i, f, l);
                } else if (at(t, i, .lparen)) return gap(cx.diags, l, "PROC STDIZE: a MISSING= method argument is not implemented", .{});
                s.missing_method = f;
                s.missing = null;
            } else {
                s.missing = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: MISSING= must be a method or a number", .{});
                s.missing_method = null;
            }
        } else if (eq(option, "initial") and valued) {
            // p.9445: INITIAL=ABW, AHUBER, AWAVE and IN are not allowed (SAS:
            // ERROR 22-322 / 79-322); any other method name is accepted.
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: INITIAL= must be a method name", .{});
            const m = t[i + 2].text;
            const named = methodByName(m);
            const ok = (named != null and !isAEstimate(named.?) and named.? != .in) or eq(m, "l") or eq(m, "least");
            if (!ok) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: INITIAL={s} is not valid; expecting one of AGK, EUCLEN, IQR, LEAST, MAD, MAXABS, MEAN, MEDIAN, MIDRANGE, RANGE, SPACING, STD, SUM, USTD", .{m});
            s.initial = true;
            i += 3;
            const im = methodByName(m) orelse return gap(cx.diags, l, "PROC STDIZE: INITIAL={s} is not implemented (STAT-STDIZE-003)", .{m});
            s.initial_method = im;
            if (hasArg(im)) {
                s.initial_arg = try methodArg(cx, t, &i, im, l);
            } else if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(option, "nmarkers") and valued) {
            // Only used by PCTLMTD=ONEPASS (itself a STAT-STDIZE-004 gap); SAS
            // accepts and ignores it otherwise (verified with NMARKERS=3).
            i += 2;
            _ = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: NMARKERS= must be a number", .{});
        } else if (eq(option, "pctlpts") and valued) {
            // Only written to OUTSTAT= (itself a STAT-STDIZE-005 gap); SAS
            // accepts and ignores it otherwise (verified with PCTLPTS=10, 150).
            s.pctlpts = true;
            i += 2;
            _ = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLPTS= must be a list of numbers", .{});
            while (at(t, i, .comma) or at(t, i, .number)) {
                if (at(t, i, .comma)) i += 1;
                _ = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLPTS= must be a list of numbers", .{});
            }
            if (at(t, i, .name) and eq(t[i].text, "to")) return gap(cx.diags, l, "PROC STDIZE: PCTLPTS= TO/BY ranges are not implemented", .{});
        } else if (!valued and (eq(option, "unstd") or eq(option, "unstdize"))) {
            // Only used with METHOD=IN; SAS accepts and ignores it otherwise
            // (verified: plain METHOD=STD output).
            s.unstd = true;
            i += 1;
        } else if (!valued and eq(option, "norm")) {
            s.norm = true;
            i += 1;
        } else if (!valued and eq(option, "snorm")) {
            s.snorm = true;
            i += 1;
        } else if (!valued and eq(option, "nomiss")) {
            s.nomiss = true;
            i += 1;
        } else if (!valued and eq(option, "replace")) {
            s.replace = true;
            i += 1;
        } else if (!valued and eq(option, "reponly")) {
            s.reponly = true;
            i += 1;
        } else if (!valued and eq(option, "pstat")) {
            s.pstat = true;
            i += 1;
        } else {
            for (option_gaps) |g| if (eq(option, g)) return gap(cx.diags, l, "PROC STDIZE: the {s} option is not implemented", .{t[i].text});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // pp.9447-9448: "You cannot specify both the REPLACE and REPONLY options."
    if (s.replace and s.reponly) return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: you cannot specify both the REPLACE and REPONLY options", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: input data set not found", .{});
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
            // p.9449: with more than one BY statement only the last is used.
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            // SAS-verified: several VAR statements accumulate.
            var_seen = true;
            try columnList(cx, ds, t, i, end, "VAR", &vars);
        } else if (eq(word, "freq")) {
            // SAS-verified: with several FREQ statements the first is used.
            var stop = end;
            var notrunc = false;
            if (end > i + 2 and at(t, i + 2, .slash)) {
                stop = i + 2;
                for (t[i + 3 .. end]) |o| {
                    if (o.tag == .name and (eq(o.text, "notruncate") or eq(o.text, "notrunc"))) notrunc = true else return invalid(cx, t, i + 3);
                }
            }
            const f = try oneNumeric(cx, ds, t, i, stop, "FREQ");
            if (s.freq == null) {
                s.freq = f;
                s.notruncate = notrunc;
            }
        } else if (eq(word, "weight") or eq(word, "wgt")) {
            // SAS-verified: with several WEIGHT statements the first is used.
            const w = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
            if (s.weight == null) s.weight = w;
        } else if (eq(word, "location") or eq(word, "scale")) {
            // p.9450: variables of the METHOD=IN data set.
            // SAS-verified: without METHOD=IN, "No data set open to look up variables."
            if (s.method != .in) return cx.diags.fail(error.ParseError, t[i].line, "No data set open to look up variables.", .{});
            if (end == i + 1) return invalid(cx, t, end);
            var names: std.ArrayList([]const u8) = .empty;
            var j: usize = 0;
            const body = t[i + 1 .. end];
            while (j < body.len) try names.appendSlice(a, try lists.next(a, s.in_ds.?, body, &j, cx.diags));
            if (eq(word, "location")) s.loc_vars = names.items else s.scale_vars = names.items;
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
        // p.9450: without a VAR statement all numeric variables not listed in
        // the BY, FREQ and WEIGHT statements are used.
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: no numeric variables to standardize", .{});
    return s;
}

fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: the {s} statement takes exactly one variable", .{role});
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
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
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: variable {s} in the {s} statement must be numeric", .{ n, role });
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
}

/// One usable value of an analysis variable: x with its integer frequency f
/// and weight w.
pub const Obs = struct { x: f64, f: f64, w: f64 };

/// Values of variable `ci` used for its location and scale (pp.9450-9451,
/// 9457): nonmissing x, FREQ truncated and at least 1, WEIGHT above zero;
/// with NOMISS, rows missing any analysis variable are dropped.
pub fn usable(a: A, s: Spec, rows: []const []const Value, ci: usize) ![]Obs {
    var list: std.ArrayList(Obs) = .empty;
    rows: for (rows) |row| {
        const x = row[ci].num;
        if (std.math.isNan(x)) continue;
        if (s.nomiss) for (s.vars) |v| if (std.math.isNan(row[v].num)) continue :rows;
        var f: f64 = 1;
        if (s.freq) |fc| {
            if (s.notruncate) {
                // NOTRUNCATE (SAS-verified): a frequency 0.5 is used as is.
                f = row[fc].num;
                if (!(f > 0)) continue;
            } else {
                f = @floor(row[fc].num);
                if (!(f >= 1)) continue;
            }
        }
        var w: f64 = 1;
        if (s.weight) |wc| {
            w = row[wc].num;
            if (!(w > 0)) continue;
        }
        try list.append(a, .{ .x = x, .f = f, .w = w });
    }
    return list.items;
}

fn lessX(_: void, l: Obs, r: Obs) bool {
    return l.x < r.x;
}
/// The k-th (1-based) order statistic of the frequency-expanded sample.
fn orderStat(sorted: []const Obs, k: f64) f64 {
    var cum: f64 = 0;
    for (sorted) |o| {
        cum += o.f;
        if (cum >= k) return o.x;
    }
    return sorted[sorted.len - 1].x;
}
/// Percentile 100p of the usable values (Computing Quantiles, pp.9455-9456).
/// Unweighted (integer frequencies expand the sample), PCTLDEF=def with
/// np = j + g ((n+1)p for definition 4), x_0 = x_1 and x_{n+1} = x_n:
///   1: (1-g) x_j + g x_{j+1}
///   2: x_i, i = int(np + 1/2) if g != 1/2, else x_j (j even) / x_{j+1} (j odd)
///   3: x_j if g = 0, else x_{j+1}
///   4: (1-g) x_j + g x_{j+1} at (n+1)p
///   5: (x_j + x_{j+1}) / 2 if g = 0, else x_{j+1}
/// All five SAS-verified for MEDIAN, IQR and MAD with n = 6, 7, 8, 10.
/// Weighted (WEIGHT, or FREQ / NOTRUNCATE; weight w f): SAS 15.4 returns
/// x_{i+1} for sum_{j<=i} w_j < pW <= sum_{j<=i+1} w_j. ponytail: the guide
/// (p.9456) averages x_i and x_{i+1} when the cumulative weight equals pW
/// exactly, but real SAS does not (equal weights 2 on ten values give a median
/// x_5, not (x_5 + x_6) / 2; also verified at q1, q3 and with NOTRUNCATE), so
/// the observed rule is implemented.
pub fn percentile(a: A, obs: []const Obs, p: f64, def: u8, weighted: bool) !f64 {
    const sorted = try a.dupe(Obs, obs);
    std.mem.sort(Obs, sorted, {}, lessX);
    if (weighted) {
        var total: f64 = 0;
        for (sorted) |o| total += o.w * o.f;
        const target = p * total;
        var cum: f64 = 0;
        for (sorted) |o| {
            cum += o.w * o.f;
            if (cum >= target) return o.x;
        }
        return sorted[sorted.len - 1].x;
    }
    var n: f64 = 0;
    for (sorted) |o| n += o.f;
    const pos = if (def == 4) (n + 1) * p else n * p;
    const j = @floor(pos);
    const g = pos - j;
    const xj = orderStat(sorted, @max(j, 1));
    const xj1 = orderStat(sorted, @min(j + 1, n));
    return switch (def) {
        1, 4 => if (g == 0) xj else (1 - g) * xj + g * xj1,
        2 => if (g != 0.5) orderStat(sorted, @min(@max(@floor(pos + 0.5), 1), n)) else if (@mod(j, 2) == 0) xj else xj1,
        3 => if (g == 0) xj else xj1,
        else => if (g == 0) (xj + xj1) / 2 else xj1,
    };
}

pub const Measures = struct {
    location: f64,
    scale: f64,
    n: f64,
    /// NORM: the normalized scale used to standardize (PSTAT "Norm" column).
    norm: ?f64 = null,
    /// ABW/AHUBER/AWAVE used the initial estimates (no accepted value).
    fallback: bool = false,
    /// No usable values (Constant Data, p.9456): not standardized.
    empty: bool = false,
    /// FUZZ= reports this positive scale as 0 (still used to divide).
    fuzzed: bool = false,
};

/// Location and scale of Table 115.2 for one variable (Computation of the
/// Statistics, p.9454; weighted moments, p.9451). Null when the sample does
/// not determine the measure (no values, or a variance divisor <= 0).
pub fn measures(a: A, s: Spec, obs: []const Obs) error{OutOfMemory}!?Measures {
    // Constant Data / no usable values (SAS-verified for every closed-form
    // and robust method): the location is missing except 0 for EUCLEN and
    // MAXABS, the scale is missing except 1 for MEDIAN; see run for the
    // WARNING and the unstandardized output.
    if (obs.len == 0) return .{
        .location = if (s.method == .euclen or s.method == .maxabs) 0 else std.math.nan(f64),
        .scale = if (s.method == .median) 1 else std.math.nan(f64),
        .n = 0,
        .empty = true,
    };
    // Weighted percentiles (p.9456) for WEIGHT and FREQ / NOTRUNCATE.
    const wq = s.weight != null or s.notruncate;
    var n: f64 = 0;
    var sw: f64 = 0;
    var swx: f64 = 0;
    var swxx: f64 = 0;
    var lo = obs[0].x;
    var hi = obs[0].x;
    for (obs) |o| {
        n += o.f;
        sw += o.f * o.w;
        swx += o.f * o.w * o.x;
        swxx += o.f * o.w * o.x * o.x;
        lo = @min(lo, o.x);
        hi = @max(hi, o.x);
    }
    const mean = swx / sw;
    const d: f64 = switch (s.vardef) {
        .df => n - 1,
        .n => n,
        .wdf => sw - 1,
        .weight => sw,
    };
    var fallback = false;
    const loc_scale: [2]f64 = switch (s.method) {
        .mean => .{ mean, 1 },
        .median => .{ try percentile(a, obs, 0.5, s.pctldef, wq), 1 },
        .sum => .{ 0, swx },
        .euclen => .{ 0, @sqrt(swxx) },
        // SAS-verified NOTEs: "VARDEF= DF is equivalent to VARDEF= N" and
        // "VARDEF= WDF is equivalent to VARDEF= WEIGHT" for USTD (x = 4, 6:
        // sqrt(26); weighted sum w x^2 / sum w).
        .ustd => .{ 0, @sqrt(swxx / switch (s.vardef) {
            .df, .n => n,
            .wdf, .weight => sw,
        }) },
        .std => blk: {
            // SAS-verified (one value, VARDEF=DF): a divisor <= 0 is the
            // "scale <= 0" case, missing scale, location the mean.
            if (d <= 0) break :blk .{ mean, std.math.nan(f64) };
            var css: f64 = 0;
            for (obs) |o| css += o.f * o.w * (o.x - mean) * (o.x - mean);
            break :blk .{ mean, @sqrt(css / d) };
        },
        .range => .{ lo, hi - lo },
        .midrange => .{ (hi + lo) / 2, (hi - lo) / 2 },
        .maxabs => .{ 0, @max(@abs(lo), @abs(hi)) },
        .iqr => .{ try percentile(a, obs, 0.5, s.pctldef, wq), try percentile(a, obs, 0.75, s.pctldef, wq) - try percentile(a, obs, 0.25, s.pctldef, wq) },
        .mad => blk: {
            const med = try percentile(a, obs, 0.5, s.pctldef, wq);
            const dev = try a.alloc(Obs, obs.len);
            for (obs, dev) |o, *e| e.* = .{ .x = @abs(o.x - med), .f = o.f, .w = o.w };
            break :blk .{ med, try percentile(a, dev, 0.5, s.pctldef, wq) };
        },
        .abw, .ahuber, .awave => blk: {
            const r = (try aEstimate(a, s, obs, n)) orelse return null;
            fallback = r[2] != 0;
            break :blk .{ r[0], r[1] };
        },
        .agk => (try agk(a, obs, s.arg)) orelse return null,
        .spacing => (try spacing(a, obs, s.arg)) orelse return null,
        // Read from the METHOD=IN data set by the caller.
        .in => unreachable,
    };
    var location = loc_scale[0];
    var scale = loc_scale[1];
    // FUZZ= (p.9445) for the location and scale values.
    // SAS-verified (3,3,3,4 with FUZZ=0.2 and 0.6): a positive scale below
    // |location| * FUZZ is reported as 0 but the values are still divided by
    // the computed scale, with no WARNING.
    var fuzzed = false;
    if (scale < @abs(location) * s.fuzz) {
        if (scale > 0) fuzzed = true else scale = 0;
    } else if (@abs(location) < @abs(s.mult) * s.fuzz) location = 0;
    const normed: ?f64 = if (!s.norm) null else switch (s.method) {
        .iqr => scale / (2 * z75),
        .mad => scale / z75,
        // SAS-verified (p = 0.3, 0.5, 0.8): the minimum spacing over the
        // normal spacing containing p, 2 z((1 + p) / 2).
        .spacing => scale / (2 * zQuantile((1 + s.arg) / 2)),
        else => null,
    };
    return .{ .location = location, .scale = scale, .n = n, .norm = normed, .fallback = fallback, .fuzzed = fuzzed };
}

/// One-step M-estimate of location and A-estimate of scale (p.9454; Goodall
/// 1983, Iglewicz 1983). From the INITIAL= location T0 and scale S0 (default
/// MAD: median and raw median absolute deviation), with u = (x - T0)/(c S0):
///   T = T0 + c S0 sum psi(u) / sum psi'(u)
///   A = sqrt(n^2 / (n - 1)) c S0 sqrt(sum psi(u)^2) / |sum psi'(u)|
/// biweight psi = u(1-u^2)^2, Huber psi = max(-1, min(1, u)), wave psi =
/// sin(pi u), each zero outside |u| <= 1 (biweight, wave). Verified against
/// SAS: ABW(4) on the Getting Started data (162.889603 / 56.662855) and
/// ABW(4), AHUBER(1.5), AWAVE(2), INITIAL=STD / IQR on invented data.
fn aEstimate(a: A, s: Spec, obs: []const Obs, n: f64) error{OutOfMemory}!?[3]f64 {
    var init = s;
    init.method = s.initial_method;
    init.arg = s.initial_arg;
    init.norm = false;
    const m0 = (try measures(a, init, obs)) orelse return null;
    // ponytail: a missing initial scale (INITIAL=STD with one value) is not
    // verified; the caller reports a gap.
    if (std.math.isNan(m0.scale)) return null;
    // SAS-verified (constant data and one value, default INITIAL=MAD): a zero
    // initial scale gives the acceptance-interval NOTE, the initial location
    // and a zero scale (then the Constant Data WARNING).
    if (!(m0.scale > 0)) return .{ m0.location, 0, 1 };
    const cs = s.arg * m0.scale;
    var sp: f64 = 0;
    var sd: f64 = 0;
    var spp: f64 = 0;
    for (obs) |o| {
        const u = (o.x - m0.location) / cs;
        const pd: [2]f64 = switch (s.method) {
            .abw => if (@abs(u) < 1) .{ u * (1 - u * u) * (1 - u * u), (1 - u * u) * (1 - 5 * u * u) } else .{ 0, 0 },
            .ahuber => if (@abs(u) <= 1) .{ u, 1 } else .{ std.math.sign(u), 0 },
            .awave => if (@abs(u) <= 1) .{ @sin(std.math.pi * u), std.math.pi * @cos(std.math.pi * u) } else .{ 0, 0 },
            else => unreachable,
        };
        sp += o.f * pd[0];
        sd += o.f * pd[1];
        spp += o.f * pd[0] * pd[0];
    }
    // SAS-verified: when no observation is inside the acceptance interval
    // (sum psi' = 0; also an exactly cancelling wave sum of 4e-16) the
    // initial estimates are used, with a NOTE (see run).
    // ponytail: "cancelling" is |sum psi'| <= 1e-12 * n * max psi'.
    const dmax: f64 = if (s.method == .awave) std.math.pi else 1;
    if (@abs(sd) <= 1e-12 * n * dmax) return .{ m0.location, m0.scale, 1 };
    return .{ m0.location + cs * sp / sd, @sqrt(n * n / (n - 1)) * cs * @sqrt(spp) / @abs(sd), 0 };
}

/// The frequency-expanded sample in ascending order.
fn expanded(a: A, obs: []const Obs) ![]f64 {
    var v: std.ArrayList(f64) = .empty;
    for (obs) |o| try v.appendNTimes(a, o.x, @intFromFloat(o.f));
    std.mem.sort(f64, v.items, {}, std.sort.asc(f64));
    return v.items;
}

/// SPACING(p) (p.9454): the minimum difference x(i+k) - x(i) over the sorted
/// sample and the midpoint of the first such pair, k = ceil(p n) - 1
/// (SAS-verified for p = 0.25, 0.3, 0.5, 0.55, 0.8, 0.95, 1 with n = 10 and
/// p = 0.5 with n = 9 and 13). ponytail: p n is fuzzed by 1e-9 so that
/// 0.3 * 10 counts as 3. k = 0 or k >= n gives a zero scale (constant data).
fn spacing(a: A, obs: []const Obs, p: f64) !?[2]f64 {
    const v = try expanded(a, obs);
    if (v.len == 0) return null;
    const kf = @ceil(p * @as(f64, @floatFromInt(v.len)) - 1e-9) - 1;
    if (kf < 1 or kf >= @as(f64, @floatFromInt(v.len))) return .{ v[0], 0 };
    const k: usize = @intFromFloat(kf);
    var best: usize = 0;
    for (0..v.len - k) |i| if (v[i + k] - v[i] < v[best + k] - v[best]) {
        best = i;
    };
    return .{ (v[best] + v[best + k]) / 2, v[best + k] - v[best] };
}

/// AGK(p) (p.9454; PROC ACECLUS METHOD=COUNT, noniterative univariate
/// form): location is the mean; with m = floor(p n (n-1)/2) the m-th
/// smallest pairwise distance d* is the threshold and the scale is
/// sqrt(sum d^2 / (2 K)) over the K pairs with d <= d* (ties included).
/// SAS-verified for p = 0.2 and 0.5 with n = 10.
fn agk(a: A, obs: []const Obs, p: f64) !?[2]f64 {
    const v = try expanded(a, obs);
    const n = v.len;
    if (n < 2) return null;
    var d: std.ArrayList(f64) = .empty;
    var mean: f64 = 0;
    for (v, 0..) |x, i| {
        mean += x;
        for (v[i + 1 ..]) |y| try d.append(a, @abs(y - x));
    }
    mean /= @floatFromInt(n);
    std.mem.sort(f64, d.items, {}, std.sort.asc(f64));
    const m: usize = @intFromFloat(@floor(p * @as(f64, @floatFromInt(d.items.len))));
    // SAS ERROR "too small to have at least one pair": NaN scale, see run.
    if (m < 1) return .{ mean, std.math.nan(f64) };
    const threshold = d.items[m - 1];
    var ss: f64 = 0;
    var count: f64 = 0;
    for (d.items) |e| if (e <= threshold) {
        ss += e * e;
        count += 1;
    };
    return .{ mean, @sqrt(ss / (2 * count)) };
}

/// METHOD=IN(ds) (p.9453): location and scale per VAR variable from the
/// _TYPE_='LOCATION'/'SCALE' observations (ADD/MULT observations override
/// ADD=/MULT=, else two NOTEs), or, without _TYPE_, from the first observation
/// of the LOCATION and SCALE statement variables (matched by position).
/// Diagnostics are the SAS-verified texts.
fn readIn(cx: proc.ProcCtx, s: *Spec, names: []const []const u8) diag.Error![]Measures {
    const a = cx.arena;
    const ds = s.in_ds.?;
    const out = try a.alloc(Measures, names.len);
    if (ds.indexOf("_type_")) |tc| {
        if (ds.columns.items[tc].type != .char) return proc.failGap(cx.diags, 0, "PROC STDIZE: a numeric _TYPE_ in the METHOD=IN data set is not implemented", .{});
        const kinds = [_][]const u8{ "LOCATION", "SCALE", "ADD", "MULT" };
        var rows: [4]?[]const Value = .{ null, null, null, null };
        for (ds.rows.items) |r| {
            const v = std.mem.trimEnd(u8, r[tc].str, " ");
            for (kinds, 0..) |k, ki| if (rows[ki] == null and std.mem.eql(u8, v, k)) {
                rows[ki] = r;
            };
        }
        if (rows[0] == null or rows[1] == null) return proc.failGap(cx.diags, 0, "PROC STDIZE: a METHOD=IN data set without _TYPE_='LOCATION' and 'SCALE' observations is not implemented", .{});
        for (names, out) |n, *m| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, 0, "Variable {s} is not found in the METHOD= IN() data set.", .{n});
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, 0, "Variable {s} in the METHOD= IN() data set must be numeric.", .{n});
            m.* = .{ .location = rows[0].?[ci].num, .scale = rows[1].?[ci].num, .n = 0 };
        }
        if (rows[2] == null) try cx.diags.note(0, "No observation containing addition constant (_TYPE_=ADD) is found in the METHOD= IN() data set. The value specified in ADD= (or default) is used.", .{});
        if (rows[3] == null) try cx.diags.note(0, "No observation containing multiplication constant (_TYPE_=MULT) is found in the METHOD= IN() data set. The value specified in MULT= (or default) is used.", .{});
        // ponytail: one ADD/MULT per data set; per-variable constants differing
        // across variables are not modelled.
        for ([_]usize{ 2, 3 }) |ki| if (rows[ki]) |r| {
            const first = r[ds.indexOf(names[0]).?].num;
            for (names) |n| if (r[ds.indexOf(n).?].num != first) return proc.failGap(cx.diags, 0, "PROC STDIZE: METHOD=IN ADD/MULT constants that differ across variables are not implemented", .{});
            if (ki == 2) s.add = first else s.mult = first;
        };
        return out;
    }
    if (s.loc_vars.len == 0 or s.scale_vars.len == 0) return cx.diags.fail(error.ParseError, 0, "Neither the _TYPE_ variable is found in the METHOD= IN() data set nor the LOCATION and SCALE statements are specified.", .{});
    for ([_][]const []const u8{ s.loc_vars, s.scale_vars }, [_][]const u8{ "LOCATION", "SCALE" }) |vs, w|
        if (vs.len != names.len) return cx.diags.fail(error.ParseError, 0, "The number of variables in the {s} statement, {d}, is not equal to the number of variables in the VAR statement, {d}.", .{ w, vs.len, names.len });
    if (ds.rows.items.len == 0) return proc.failGap(cx.diags, 0, "PROC STDIZE: an empty METHOD=IN data set is not implemented", .{});
    const r = ds.rows.items[0];
    for (out, s.loc_vars, s.scale_vars) |*m, lv, sv| {
        const li = ds.indexOf(lv) orelse return cx.diags.fail(error.ParseError, 0, "Variable {s} is not found in the METHOD= IN() data set.", .{lv});
        const si = ds.indexOf(sv) orelse return cx.diags.fail(error.ParseError, 0, "Variable {s} is not found in the METHOD= IN() data set.", .{sv});
        if (ds.columns.items[li].type != .num or ds.columns.items[si].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC STDIZE: LOCATION and SCALE variables must be numeric", .{});
        m.* = .{ .location = r[li].num, .scale = r[si].num, .n = 0 };
    }
    return out;
}

/// Final OUT= value (p.9448): add + mult * (x - location) / scale, with the
/// FUZZ= rule |result| < mult * fuzz -> 0.
pub fn standardize(s: Spec, m: Measures, x: f64) f64 {
    const r = s.add + s.mult * (x - m.location) / (m.norm orelse m.scale);
    return if (@abs(r) < @abs(s.mult) * s.fuzz) 0 else r;
}

/// The verified PSTAT subtitle wording of each method (SAS listings).
fn labels(m: Method) ?[2][]const u8 {
    return switch (m) {
        .std => .{ "mean", "standard deviation" },
        .mad => .{ "median", "median abs dev from median" },
        .iqr => .{ "median", "interquartile range" },
        .abw => .{ "biweight 1-step M-estimate", "biweight A-estimate" },
        .ahuber => .{ "Huber 1-step M-estimate", "Huber A-estimate" },
        .awave => .{ "Wave 1-step M-estimate", "Wave A-estimate" },
        .spacing => .{ "mid minimum-spacing", "minimum spacing" },
        .agk => .{ "mean", "AGK estimate (ACECLUS)" },
        .in => .{ "read from data set", "read from data set" },
        // SAS-verified listings (STAT-STDIZE-004 runs with PSTAT).
        .mean => .{ "mean", "1." },
        .median => .{ "median", "1." },
        .sum => .{ "0.", "sum" },
        .euclen => .{ "0.", "Euclidean length" },
        .ustd => .{ "0.", "standard dev. about origin" },
        .range => .{ "minimum", "range" },
        .midrange => .{ "midrange", "range/2." },
        .maxabs => .{ "0.", "maximum abs value" },
    };
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

/// The PSTAT table, laid out as in the SAS listing: a Name column as wide as
/// the longest name (at least 4), then Location and Scale right-aligned in 16
/// columns with six decimals and N in 12.
fn table(a: A, out: *Out, names: []const []const u8, label: usize, lab: [2][]const u8, values: []const Measures, norm: bool, with_n: bool) !void {
    try out.print(a, "\nThe STDIZE Procedure\n\nLocation and Scale Measures\n \nLocation = {s}     Scale = {s}\n \n", .{ lab[0], lab[1] });
    try left(a, out, "Name", label);
    try right(a, out, "Location", 16);
    try right(a, out, "Scale", 16);
    // SAS-verified: NORM with IQR/MAD adds a Norm column after Scale.
    if (norm) try right(a, out, "Norm", 16);
    // SAS-verified: METHOD=IN prints no N column.
    if (with_n) try right(a, out, "N", 12);
    try out.appendSlice(a, "\n\n");
    for (names, values) |n, m| {
        try left(a, out, n, label);
        try right(a, out, try cell(a, m.location), 16);
        try right(a, out, try cell(a, if (m.fuzzed) 0 else m.scale), 16);
        if (norm) try right(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{m.norm.?}), 16);
        if (with_n) try right(a, out, try std.fmt.allocPrint(a, "{d}", .{m.n}), 12);
        try out.appendSlice(a, "\n");
    }
}

/// A PSTAT Location / Scale cell: six decimals, "." when missing and "0"
/// for an exact zero (SAS-verified: METHOD=SUM / USTD / MAXABS locations,
/// a FUZZ= zero scale, missing scales of constant data).
fn cell(a: A, v: f64) ![]const u8 {
    if (std.math.isNan(v)) return ".";
    if (v == 0) return "0";
    return std.fmt.allocPrint(a, "{d:.6}", .{v});
}

/// BY line flush left. ponytail: as in PROC FACTOR, the shared helper centers
/// the BY line; the NOCENTER reference listing has it at column 1.
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

fn anyLine(lines: []const ?[]const u8) bool {
    for (lines) |l| if (l != null) return true;
    return false;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    var s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;

    // p.9450: the WEIGHT variable and NOTRUNCATE apply only to some methods.
    // SAS-verified: when METHOD= or MISSING= names RANGE, MIDRANGE or MAXABS
    // the WEIGHT statement (WARNING + NOTE) and NOTRUNCATE (WARNING) are
    // ignored for the whole step, including the other method.
    const mm_range = if (s.missing_method) |mm| ignoresWeight(mm) else false;
    if (s.weight != null and (ignoresWeight(s.method) or mm_range)) {
        const which: []const u8 = if (ignoresWeight(s.method)) "METHOD" else "MISSING";
        const name = @tagName(if (ignoresWeight(s.method)) s.method else s.missing_method.?);
        try cx.diags.warnStatus(l0, "The WEIGHT variable does not apply to {s}= {s}.", .{ which, try std.ascii.allocUpperString(a, name) });
        try cx.diags.note(l0, "The WEIGHT statement is ignored.", .{});
        s.weight = null;
    }
    if (s.weight != null and ignoresWeightRobust(s.method)) {
        try cx.diags.warnStatus(l0, "The WEIGHT variable does not apply to METHOD= {s}.", .{try std.ascii.allocUpperString(a, @tagName(s.method))});
        try cx.diags.note(l0, "The WEIGHT statement is ignored.", .{});
        s.weight = null;
    }
    const robust = s.method == .abw or s.method == .ahuber or s.method == .awave or s.method == .agk or s.method == .spacing or s.method == .in;
    const mm_robust = if (s.missing_method) |mm| hasArg(mm) else false;
    if (s.weight != null and (robust or mm_robust or (isAEstimate(s.method) and hasArg(s.initial_method))))
        return gap(cx.diags, l0, "PROC STDIZE: WEIGHT with METHOD={s} or a robust MISSING=/INITIAL= method is not implemented", .{@tagName(s.method)});
    if (s.notruncate and (robust or mm_robust))
        return gap(cx.diags, l0, "PROC STDIZE: FREQ / NOTRUNCATE with METHOD={s} or a robust MISSING= method is not implemented", .{@tagName(s.method)});
    if (s.method == .in and s.by_cols.len > 0)
        return gap(cx.diags, l0, "PROC STDIZE: BY groups with METHOD=IN are not implemented", .{});
    if (s.norm and s.method == .agk) return gap(cx.diags, l0, "PROC STDIZE: NORM with METHOD=AGK is not implemented", .{});
    if (s.norm and s.method == .spacing and s.arg >= 1) return gap(cx.diags, l0, "PROC STDIZE: NORM with SPACING(p), p >= 1 is not verified", .{});
    if (s.snorm and s.method == .spacing) return gap(cx.diags, l0, "PROC STDIZE: SNORM with METHOD=SPACING is not implemented", .{});
    if (s.notruncate and (ignoresWeight(s.method) or mm_range)) {
        try cx.diags.warnStatus(l0, "The NOTRUNCATE option in the FREQ statement is ignored when the RANGE, MIDRANGE, or MAXABS method is specified.", .{});
        s.notruncate = false;
    }
    const pct = isPercentile(s.method) or (s.missing_method != null and isPercentile(s.missing_method.?)) or
        (isAEstimate(s.method) and isPercentile(s.initial_method));
    // PCTLDEF= diagnostics (SAS-verified texts): without a MEDIAN, IQR or MAD
    // method or PCTLPTS= it does not apply; with WEIGHT or FREQ / NOTRUNCATE
    // the weighted percentiles are used instead.
    if (s.pctldef_given) {
        if (isAEstimate(s.method) and !s.initial)
            return gap(cx.diags, l0, "PROC STDIZE: PCTLDEF= with the default INITIAL=MAD of METHOD={s} is not verified", .{@tagName(s.method)});
        if (!pct and !s.pctlpts) {
            try cx.diags.warnStatus(l0, "PCTLDEF= is only applicable with quantiles estimation; one of MEDIAN, IQR or MAD must be specified in METHOD=, MISSING= or INITIAL=, or PCTLPTS= needs to be specified.", .{});
        } else if (s.weight != null or s.notruncate) {
            try cx.diags.warnStatus(l0, "The PCTLDEF= option is not applicable when a WEIGHT statement or a FREQ/NOTRUNCATE statement is used.", .{});
            s.pctldef = 5;
        }
    }
    if (s.method == .ustd) {
        if (s.vardef == .df) try cx.diags.note(l0, "VARDEF= DF is equivalent to VARDEF= N when USTD is used for standardization or for the initial estimates for the A estimates.", .{});
        if (s.vardef == .wdf) try cx.diags.note(l0, "VARDEF= WDF is equivalent to VARDEF= WEIGHT when USTD is used for standardization.", .{});
    } else if (isAEstimate(s.method) and s.initial_method == .ustd and s.vardef == .df) {
        try cx.diags.note(l0, "VARDEF= DF is equivalent to VARDEF= N when USTD is used for standardization or for the initial estimates for the A estimates.", .{});
    }
    if (s.norm and s.method != .iqr and s.method != .mad and s.method != .spacing) {
        try cx.diags.warnStatus(l0, "The option NORM will be ignored since none of the standardization methods including MAD, IQR, AGK and SPACING has been specified for METHOD= .", .{});
        s.norm = false;
    }
    if (s.initial and !isAEstimate(s.method)) try cx.diags.note(l0, "INITIAL= will be ignored.", .{});
    if (s.snorm and s.method != .spacing) try cx.diags.warnStatus(l0, "The option SNORM will be ignored since SPACING has not been specified for either METHOD= or INITIAL=.", .{});
    if (ds.rows.items.len == 0) {
        try cx.diags.note(l0, "No observations in the DATA= data set.", .{});
        const dn = try std.ascii.allocUpperString(a, ds.name);
        try cx.diags.note(l0, "No observations in data set {s}{s}.", .{ if (std.mem.indexOfScalar(u8, dn, '.') == null) @as([]const u8, "WORK.") else "", dn });
    }
    if (s.pstat) {
        if (labels(s.method) == null) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT listing for METHOD={s} is not verified against SAS output (STAT-STDIZE-006)", .{@tagName(s.method)});
        if (s.weight != null and s.method != .in) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT Sum of Weights column is not verified against SAS output (STAT-STDIZE-006)", .{});
    }
    if (cx.capture) |c| if (c.wants("Statistics")) return gap(cx.diags, l0, "PROC STDIZE: ODS OUTPUT Statistics= is not implemented (STAT-STDIZE-006)", .{});

    if (s.pstat and groups.len > 1) if (cx.listing_titles) |titles| if (anyLine(&titles.footnotes))
        return gap(cx.diags, l0, "PROC STDIZE: footnotes on BY-group PSTAT pages are not verified against SAS output", .{});

    const names = try a.alloc([]const u8, p);
    var label: usize = 4;
    for (s.vars, names) |ci, *n| {
        n.* = ds.columns.items[ci].name;
        label = @max(label, n.len);
    }
    const member = s.out orelse blk: {
        var k: usize = 1;
        while (true) : (k += 1) {
            const candidate = try std.fmt.allocPrint(a, "data{d}", .{k});
            if (cx.lib.find(candidate) == null) break :blk candidate;
        }
    };
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, member);
    for (ds.columns.items) |c| _ = try o.addColumnLike(c.name, c);

    var body: Out = .empty;
    const ms = try a.alloc(Measures, p);
    const in_ms: ?[]const Measures = if (s.method == .in) try readIn(cx, &s, names) else null;
    // MISSING=method: that method's location, computed like METHOD=method
    // from the same usable values (p.9446; SAS-verified for MEDIAN, MEAN,
    // RANGE with METHOD=STD/IQR and REPLACE/REPONLY).
    const fill = try a.alloc(f64, p);
    var ms_spec = s;
    if (s.missing_method) |mm| {
        ms_spec.method = mm;
        ms_spec.arg = s.missing_arg;
        ms_spec.norm = false;
    }
    for (groups, 0..) |group, gi| {
        // SAS-verified: an empty DATA= set gives the two NOTEs above, an empty
        // OUT= data set and no PSTAT table.
        if (group.rows.len == 0) continue;
        // Constant Data (p.9456): a variable whose location or scale cannot
        // be used is copied unstandardized; its diagnostics are followed by
        // one BY-group NOTE per group (SAS-verified order).
        const skip = try a.alloc(bool, p);
        @memset(skip, false);
        // No usable value at all (an empty group, or every row dropped by
        // NOMISS): the location is missing.
        const none = try a.alloc(bool, p);
        @memset(none, false);
        var messages = false;
        for (s.vars, ms, fill, skip, none) |ci, *m, *fv, *sk, *no| {
            const obs = try usable(a, s, group.rows, ci);
            no.* = obs.len == 0;
            const vname = ds.columns.items[ci].name;
            if (s.missing_method != null) {
                const mm = (try measures(a, ms_spec, obs)) orelse return gap(cx.diags, l0, "PROC STDIZE: variable {s}: the MISSING= method location is not verified for these values", .{vname});
                fv.* = mm.location;
            }
            if (in_ms) |im| {
                m.* = im[std.mem.indexOfScalar(usize, s.vars, ci).?];
                if (!(m.scale > 0)) return gap(cx.diags, l0, "PROC STDIZE: a METHOD=IN scale that is missing or not positive is not implemented", .{});
                continue;
            }
            var few_agk = false;
            if (s.method == .agk and obs.len > 0) {
                var nn: f64 = 0;
                for (obs) |ob| nn += ob.f;
                few_agk = nn < 2;
            }
            if (few_agk) {
                // SAS-verified (one value): NOTE, the mean as location, a
                // missing scale and the "can not be computed" WARNING.
                var mean: f64 = 0;
                var nn: f64 = 0;
                for (obs) |ob| {
                    mean += ob.f * ob.x;
                    nn += ob.f;
                }
                m.* = .{ .location = mean / nn, .scale = std.math.nan(f64), .n = nn, .empty = true };
            } else m.* = (try measures(a, s, obs)) orelse return gap(cx.diags, l0, "PROC STDIZE: variable {s}: a missing INITIAL= scale for the A estimates is not verified", .{vname});
            if (s.method == .agk and !m.empty and std.math.isNan(m.scale)) return cx.diags.fail(error.ParseError, l0, "The value of METHOD= (or INITIAL= and MISSING= ) AGK() is too small to have at least one pair.", .{});
            if (m.empty and isAEstimate(s.method)) m.fallback = true;
            if (m.fallback) try cx.diags.note(l0, "After centered by the initial location estimate, all observations of variable {s} are outside the acceptance interval. Consequently, the original method chosen cannot be performed. Instead, the initial estimates of the location and the scale (specified from the INITIAL= option or by default) will be used as the location and scale measures.", .{vname});
            if (m.fallback or m.empty) messages = true;
            if (m.empty and s.method == .agk) try cx.diags.note(l0, "There are fewer than two usable observations in the data set or BY group for variable {s} when the AGK method is specified.", .{vname});
            if (m.empty) {
                // SAS-verified: also with REPONLY.
                try cx.diags.warnStatus(l0, "At least one of the scale and location estimators of variable {s} can not be computed. Variable {s} will not be standardized.", .{ vname, vname });
                sk.* = true;
            } else if (!(m.scale > 0)) {
                // SAS-verified: no WARNING with REPONLY (nothing is divided).
                if (!s.reponly) {
                    try cx.diags.warnStatus(l0, "The scale estimator for variable {s} is less than or equal to 0. Variable {s} will not be standardized and a missing value is assigned to its scale estimator.", .{ vname, vname });
                    messages = true;
                }
                m.scale = std.math.nan(f64);
                sk.* = true;
            }
            if (s.pstat) {
                const big = @max(if (std.math.isNan(m.location)) 0 else @abs(m.location), if (std.math.isNan(m.scale)) 0 else @abs(m.scale));
                const text = try std.fmt.allocPrint(a, "{d:.6}", .{big});
                if (text.len > 14) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT number layout for magnitudes this large is not verified", .{});
            }
        }
        if (messages and s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
        if (s.pstat) {
            // Verified (SAS listing): every BY-group page after the first
            // repeats the titles after one blank line.
            if (gi > 0) if (cx.listing_titles) |titles| if (anyLine(&titles.titles)) {
                try body.append(a, '\n');
                try titles.emitTitles(a, &body);
            };
            if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
            try table(a, &body, names, label, labels(s.method).?, ms, s.norm, s.method != .in);
        }
        for (group.rows) |row| {
            const values = try a.dupe(Value, row);
            for (s.vars, ms, fill, skip, none) |ci, m, fv, sk, no| {
                const x = row[ci].num;
                // SAS-verified (NOMISS dropping every row of a group): the
                // present values become missing, except with REPONLY.
                // ponytail: assumed the same for EUCLEN/MAXABS (location 0).
                if (no and !s.reponly and !std.math.isNan(x)) {
                    values[ci] = .{ .num = std.math.nan(f64) };
                    continue;
                }
                if (sk) {
                    // SAS-verified (constant, one-value and empty groups):
                    // values are copied; a missing value becomes the MISSING=
                    // method location with REPONLY, else MISSING=value, else the
                    // location with REPONLY; REPLACE and MISSING=method alone
                    // keep it missing.
                    if (std.math.isNan(x)) {
                        if (s.missing_method != null) {
                            if (s.reponly) values[ci] = .{ .num = fv };
                        } else if (s.missing) |v| {
                            values[ci] = .{ .num = v };
                        } else if (s.reponly) values[ci] = .{ .num = m.location };
                    }
                    continue;
                }
                if (std.math.isNan(x)) {
                    // Missing Values (p.9457): MISSING=value -> value after
                    // standardizing; MISSING=method -> that location before
                    // standardizing (both win over REPLACE, SAS-verified);
                    // REPLACE -> 0 even with ADD= (SAS-verified); REPONLY ->
                    // the location.
                    if (s.missing_method != null) {
                        values[ci] = .{ .num = if (s.reponly) fv else standardize(s, m, fv) };
                    } else if (s.missing) |v| values[ci] = .{ .num = v } else if (s.replace) {
                        values[ci] = .{ .num = 0 };
                    } else if (s.reponly) values[ci] = .{ .num = m.location };
                } else if (s.unstd and s.method == .in) {
                    // UNSTD (p.9448): x = location + scale * (y - add) / mult.
                    values[ci] = .{ .num = m.location + m.scale * (x - s.add) / s.mult };
                } else if (!s.reponly) values[ci] = .{ .num = standardize(s, m, x) };
            }
            try o.appendRow(values);
        }
    }
    try cx.lib.put(member, o);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    const upper = try std.ascii.allocUpperString(a, member);
    const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
    try out.appendSlice(a, body.items);
    // Verified (SAS listing): the step's listing ends with one blank line.
    if (body.items.len > 0) try out.append(a, '\n');
}

test {
    _ = @import("stdize_tests.zig");
}
