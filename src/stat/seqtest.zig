//! PROC SEQTEST (SAS/STAT 15.4 ch.111): the PROC statement options, the
//! BOUNDARY= / DATA= / PARMS= input data sets, their variable roles and the
//! information level and standardized test statistic of the current stage
//! (STAT-SEQTEST-001, "PROC SEQTEST Statement" and "Input Data Sets",
//! pp.9156-9169).
//!
//! The group sequential computation itself (boundary adjustment by error
//! spending, Type I/II error probabilities, the Design Information and Test
//! Information tables) is owned by STAT-SEQTEST-002/003 and is a loud D-009
//! gap: a step that validates cleanly still stops with rc 2 and prints
//! nothing, never an approximate boundary.
//!
//! Classification: valid SAS that is not implemented, or input whose SAS
//! behavior the chapter does not state (repeated options, out-of-order stages,
//! missing values in required cells), is a gap (rc 2); a missing required
//! option or variable and a value outside a documented value set are user
//! errors (rc 1).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Scale = enum { mle, score, stdz, pvalue };
pub const Stop = enum { reject, accept, both };
pub const Alt = enum { upper, lower, twosided };
pub const Key = enum { alpha, beta, both };
pub const CiType = enum { lower, upper, twosided };
pub const Order = enum { lr, mle, stagewise };
pub const InfoVar = enum { info, events, nobs, none, stderr };
pub const AdjMethod = enum { none, errline, errfuncgamma, errfuncobf, errfuncpoc, errfuncpow };
/// The boundary a per-boundary ERRSPENDADJ( ) / ERRSPENDMIN( ) applies to.
pub const Which = enum { all, alpha, lower_alpha, upper_alpha, beta, lower_beta, upper_beta };

pub const Adjust = struct { which: Which, method: AdjMethod, param: ?f64 = null };
pub const MinSpend = struct { which: Which, values: []const f64 };

pub const Spec = struct {
    // Input data sets (pp.9156, 9158, 9163).
    boundary: ?[]const u8 = null,
    data: ?[]const u8 = null,
    parms: ?[]const u8 = null,
    testvar: ?[]const u8 = null,
    infovar: ?InfoVar = null,
    // Boundaries. Documented defaults.
    betaboundary_binding: bool = true,
    betaoverlap_adjust: bool = true,
    boundarykey: Key = .alpha,
    bscale: Scale = .stdz,
    adjust: []const Adjust = &.{},
    errspendmin: []const MinSpend = &.{},
    infoadj_prop: bool = true,
    nstages: ?usize = null,
    maxinfo: ?f64 = null,
    // p-values and confidence intervals.
    cialpha: f64 = 0.05,
    cialpha_lower: ?f64 = null,
    cialpha_upper: ?f64 = null,
    /// null = the documented default derived from the design's alternative.
    citype: ?CiType = null,
    order: Order = .stagewise,
    // Table and graphics output requests.
    condpower: bool = false,
    errspend: bool = false,
    predpower: bool = false,
    pss: bool = false,
    rci: bool = false,
    stopprob: bool = false,
    plots: bool = false,
};

/// The BOUNDARY= data set (p.9167).
pub const Boundary = struct {
    alt: Alt,
    stop: Stop,
    scale: Scale,
    stages: usize,
    info_prop: []const f64,
    info: ?[]const f64 = null,
    nobs: ?[]const f64 = null,
    events: ?[]const f64 = null,
    altref_l: ?f64 = null,
    altref_u: ?f64 = null,
};

/// The current stage read from DATA= or PARMS= (pp.9168-9169).
pub const Current = struct {
    stage: usize,
    /// Information level of the stage; null = taken from BOUNDARY=.
    info: ?f64,
    scale: ?Scale = null,
    estimate: ?f64 = null,
    /// The test statistic on the standardized Z scale (null without TESTVAR=).
    z: ?f64 = null,
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
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC SEQTEST: invalid option or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn badValue(cx: proc.ProcCtx, t: []const lex.Token, i: usize, comptime allowed: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC SEQTEST: {s}= must be " ++ allowed, .{t[i].text});
}
fn pick(comptime E: type, t: []const lex.Token, i: usize, names: []const struct { []const u8, E }) ?E {
    if (!at(t, i, .name)) return null;
    for (names) |p| if (eq(t[i].text, p[0])) return p[1];
    return null;
}

/// libref.member or member. Data set options in parentheses are not verified.
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) return proc.failGap(cx.diags, line(t, j), "PROC SEQTEST: data set options on {s} are not implemented", .{name});
    into.* = name;
    return j;
}

/// A signed numeric literal at `i`.
fn number(t: []const lex.Token, i: usize) ?struct { v: f64, next: usize } {
    var j = i;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return null;
    const v = std.fmt.parseFloat(f64, t[j].text) catch return null;
    return .{ .v = sign * v, .next = j + 1 };
}

/// One or more numbers (ERRSPENDMIN=, CREF=).
fn numbers(cx: proc.ProcCtx, t: []const lex.Token, i: usize, nonneg: bool, into: *std.ArrayList(f64)) diag.Error!usize {
    var j = i;
    while (number(t, j)) |r| {
        if (nonneg and r.v < 0) return cx.diags.fail(error.ParseError, line(t, j), "PROC SEQTEST: CREF= values must be nonnegative", .{});
        try into.append(cx.arena, r.v);
        j = r.next;
    }
    if (into.items.len == 0) return cx.diags.fail(error.ParseError, line(t, i), "PROC SEQTEST: a list of numbers is required", .{});
    return j;
}

/// `(CREF= c1 c2 ...)` or `(TYPE=...)` sub-options of CONDPOWER, PSS, STOPPROB.
fn tableSuboptions(cx: proc.ProcCtx, t: []const lex.Token, i: usize, allow_type: bool) diag.Error!usize {
    if (!at(t, i, .lparen)) return i;
    var j = i + 1;
    while (!at(t, j, .rparen)) {
        if (kw(t, j, "cref") and at(t, j + 1, .eq)) {
            var list: std.ArrayList(f64) = .empty;
            j = try numbers(cx, t, j + 2, true, &list);
        } else if (allow_type and kw(t, j, "type") and at(t, j + 1, .eq)) {
            if (!kw(t, j + 2, "allstages") and !kw(t, j + 2, "finalstage")) return badValue(cx, t, j, "ALLSTAGES or FINALSTAGE");
            j += 3;
        } else return invalid(cx, t, j);
    }
    return j + 1;
}

/// `(ALPHA)`, `(LOWERREJECT)`, ... after ERRSPENDADJ / BOUNDARYADJ / ERRSPENDMIN (pp.9160-9162).
fn whichBoundary(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!struct { w: Which, next: usize } {
    if (!at(t, i, .lparen)) return .{ .w = .all, .next = i };
    const w = pick(Which, t, i + 1, &.{
        .{ "alpha", .alpha },            .{ "reject", .alpha },
        .{ "loweralpha", .lower_alpha }, .{ "lowerreject", .lower_alpha },
        .{ "upperalpha", .upper_alpha }, .{ "upperreject", .upper_alpha },
        .{ "beta", .beta },              .{ "accept", .beta },
        .{ "lowerbeta", .lower_beta },   .{ "loweraccept", .lower_beta },
        .{ "upperbeta", .upper_beta },   .{ "upperaccept", .upper_beta },
    }) orelse return invalid(cx, t, i + 1);
    if (!at(t, i + 2, .rparen)) return invalid(cx, t, i + 2);
    return .{ .w = w, .next = i + 3 };
}

/// The PROC SEQTEST statement (p.9156). `t[0..2]` is `proc seqtest`.
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{};
    var adjust: std.ArrayList(Adjust) = .empty;
    var mins: std.ArrayList(MinSpend) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const o = t[i].text;
        const l = t[i].line;
        // Canonical option name for the repeated-option check (aliases folded).
        const canon: []const u8 = if (eq(o, "overlap")) "betaoverlap" else if (eq(o, "bscale")) "boundaryscale" else if (eq(o, "boundaryadj")) "errspendadj" else o;
        var key = try std.ascii.allocLowerString(a, canon);
        if ((eq(o, "errspendadj") or eq(o, "boundaryadj") or eq(o, "errspendmin")) and at(t, i + 1, .lparen) and at(t, i + 2, .name))
            key = try std.fmt.allocPrint(a, "{s}({s})", .{ key, try std.ascii.allocLowerString(a, t[i + 2].text) });
        // The chapter states no rule for a repeated option; do not guess one.
        if ((try seen.getOrPut(a, key)).found_existing) return proc.failGap(cx.diags, l, "PROC SEQTEST: repeated option {s} is not verified", .{o});
        if ((eq(o, "data") or eq(o, "parms"))) {
            var j = i + 1;
            if (at(t, j, .lparen)) {
                j += 1;
                while (!at(t, j, .rparen)) {
                    if (kw(t, j, "testvar") and at(t, j + 1, .eq) and at(t, j + 2, .name)) {
                        if (s.testvar != null) return proc.failGap(cx.diags, l, "PROC SEQTEST: TESTVAR= given more than once is not verified", .{});
                        s.testvar = t[j + 2].text;
                    } else if (kw(t, j, "infovar") and at(t, j + 1, .eq)) {
                        if (s.infovar != null) return proc.failGap(cx.diags, l, "PROC SEQTEST: INFOVAR= given more than once is not verified", .{});
                        // p.9158 DATA(INFOVAR=): _Info_, Events, NObs, None; p.9159 PARMS(INFOVAR=): Events, NObs, None, StdErr.
                        s.infovar = if (eq(o, "data"))
                            pick(InfoVar, t, j + 2, &.{ .{ "_info_", .info }, .{ "events", .events }, .{ "nobs", .nobs }, .{ "none", .none } }) orelse
                                return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: DATA(INFOVAR=) must be _INFO_, EVENTS, NOBS or NONE", .{})
                        else
                            pick(InfoVar, t, j + 2, &.{ .{ "stderr", .stderr }, .{ "events", .events }, .{ "nobs", .nobs }, .{ "none", .none } }) orelse
                                return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: PARMS(INFOVAR=) must be EVENTS, NOBS, NONE or STDERR", .{});
                    } else return invalid(cx, t, j);
                    j += 3;
                }
                j += 1;
            }
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            i = try memberName(cx, t, j + 1, if (eq(o, "data")) &s.data else &s.parms);
            continue;
        }
        const valued = at(t, i + 1, .eq);
        const v = i + 2;
        if (eq(o, "boundary") and valued) {
            i = try memberName(cx, t, v, &s.boundary);
        } else if (eq(o, "betaboundary") and valued) {
            s.betaboundary_binding = if (kw(t, v, "binding")) true else if (kw(t, v, "nonbinding")) false else return badValue(cx, t, i, "BINDING or NONBINDING");
            i += 3;
        } else if ((eq(o, "betaoverlap") or eq(o, "overlap")) and valued) {
            s.betaoverlap_adjust = if (kw(t, v, "adjust")) true else if (kw(t, v, "noadjust")) false else return badValue(cx, t, i, "ADJUST or NOADJUST");
            i += 3;
        } else if (eq(o, "boundarykey") and valued) {
            s.boundarykey = pick(Key, t, v, &.{ .{ "alpha", .alpha }, .{ "beta", .beta }, .{ "both", .both } }) orelse return badValue(cx, t, i, "ALPHA, BETA or BOTH");
            i += 3;
        } else if ((eq(o, "boundaryscale") or eq(o, "bscale")) and valued) {
            s.bscale = pick(Scale, t, v, &.{ .{ "mle", .mle }, .{ "score", .score }, .{ "stdz", .stdz }, .{ "pvalue", .pvalue } }) orelse return badValue(cx, t, i, "MLE, SCORE, STDZ or PVALUE");
            i += 3;
        } else if (eq(o, "cialpha") and valued) {
            const r = number(t, v) orelse return badValue(cx, t, i, "a number");
            if (!(r.v > 0 and r.v < 1)) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: CIALPHA= must be between 0 and 1", .{});
            s.cialpha = r.v;
            i = r.next;
            if (at(t, i, .lparen)) {
                i += 1;
                while (!at(t, i, .rparen)) {
                    const lower = kw(t, i, "lower");
                    if (!(lower or kw(t, i, "upper")) or !at(t, i + 1, .eq)) return invalid(cx, t, i);
                    const q = number(t, i + 2) orelse return badValue(cx, t, i, "a number");
                    if (!(q.v > 0 and q.v < 0.5)) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: CIALPHA {s}= must be between 0 and 0.5", .{t[i].text});
                    if (lower) s.cialpha_lower = q.v else s.cialpha_upper = q.v;
                    i = q.next;
                }
                i += 1;
            }
        } else if (eq(o, "citype") and valued) {
            s.citype = pick(CiType, t, v, &.{ .{ "lower", .lower }, .{ "upper", .upper }, .{ "twosided", .twosided } }) orelse return badValue(cx, t, i, "LOWER, UPPER or TWOSIDED");
            i += 3;
        } else if (eq(o, "errspendadj") or eq(o, "boundaryadj")) {
            const w = try whichBoundary(cx, t, i + 1);
            if (!at(t, w.next, .eq)) return invalid(cx, t, w.next);
            const m = w.next + 1;
            var item: Adjust = .{ .which = w.w, .method = pick(AdjMethod, t, m, &.{
                .{ "none", .none },               .{ "errline", .errline },
                .{ "errfuncgamma", .errfuncgamma }, .{ "errfuncobf", .errfuncobf },
                .{ "errfuncpoc", .errfuncpoc },   .{ "errfuncpow", .errfuncpow },
            }) orelse return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: {s}= must be NONE, ERRLINE, ERRFUNCGAMMA, ERRFUNCOBF, ERRFUNCPOC or ERRFUNCPOW", .{o}) };
            i = m + 1;
            // ERRFUNCGAMMA(GAMMA=) default -2; ERRFUNCPOW(RHO=) default 2 (p.9160).
            if (item.method == .errfuncgamma) item.param = -2;
            if (item.method == .errfuncpow) item.param = 2;
            if (at(t, i, .lparen)) {
                const want: []const u8 = switch (item.method) {
                    .errfuncgamma => "gamma",
                    .errfuncpow => "rho",
                    else => return invalid(cx, t, i),
                };
                if (!kw(t, i + 1, want) or !at(t, i + 2, .eq)) return invalid(cx, t, i + 1);
                const r = number(t, i + 3) orelse return invalid(cx, t, i + 3);
                if (!at(t, r.next, .rparen)) return invalid(cx, t, r.next);
                item.param = r.v;
                i = r.next + 1;
            }
            try adjust.append(a, item);
        } else if (eq(o, "errspendmin")) {
            const w = try whichBoundary(cx, t, i + 1);
            if (!at(t, w.next, .eq)) return invalid(cx, t, w.next);
            var list: std.ArrayList(f64) = .empty;
            i = try numbers(cx, t, w.next + 1, false, &list);
            for (list.items) |x| if (x < 0) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: ERRSPENDMIN= values must be nonnegative", .{});
            try mins.append(a, .{ .which = w.w, .values = list.items });
        } else if (eq(o, "infoadj") and valued) {
            s.infoadj_prop = if (kw(t, v, "prop")) true else if (kw(t, v, "none")) false else return badValue(cx, t, i, "NONE or PROP");
            i += 3;
        } else if (eq(o, "nstages") and valued) {
            const n = if (at(t, v, .number)) std.fmt.parseInt(usize, t[v].text, 10) catch 0 else 0;
            if (n < 1) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: NSTAGES= must be a positive integer", .{});
            s.nstages = n;
            i += 3;
        } else if (eq(o, "maxinfo") and valued) {
            const r = number(t, v) orelse return badValue(cx, t, i, "a positive number");
            if (!(r.v > 0)) return badValue(cx, t, i, "a positive number");
            s.maxinfo = r.v;
            i = r.next;
        } else if (eq(o, "order") and valued) {
            s.order = pick(Order, t, v, &.{ .{ "lr", .lr }, .{ "mle", .mle }, .{ "stagewise", .stagewise } }) orelse return badValue(cx, t, i, "LR, MLE or STAGEWISE");
            i += 3;
        } else if (eq(o, "condpower")) {
            s.condpower = true;
            i = try tableSuboptions(cx, t, i + 1, true);
        } else if (eq(o, "pss") or eq(o, "stopprob")) {
            if (eq(o, "pss")) s.pss = true else s.stopprob = true;
            i = try tableSuboptions(cx, t, i + 1, false);
        } else if (eq(o, "errspend") or eq(o, "predpower") or eq(o, "rci")) {
            if (eq(o, "errspend")) s.errspend = true else if (eq(o, "predpower")) s.predpower = true else s.rci = true;
            i += 1;
        } else if (eq(o, "plots")) {
            // ODS Graphics plots are owned by a later SEQTEST ticket; skip the
            // request balanced and fail loud at run time.
            s.plots = true;
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
            if (at(t, i, .eq)) {
                i += 1;
                if (at(t, i, .lparen)) i = proc.skipParen(t, i) else if (at(t, i, .name)) {
                    i += 1;
                    if (at(t, i, .lparen)) i = proc.skipParen(t, i);
                } else return invalid(cx, t, i);
            }
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.9156: PROC SEQTEST is the only statement of the procedure.
    i += 1;
    while (i < t.len and !at(t, i, .eof)) : (i += 1) {
        if (at(t, i, .semicolon)) continue;
        if (!(kw(t, i, "run") or kw(t, i, "quit")) or !at(t, i + 1, .semicolon)) return cx.diags.fail(error.ParseError, line(t, i), "PROC SEQTEST: statement {s} is not valid; PROC SEQTEST is the only statement of the procedure", .{if (i < t.len) t[i].text else ""});
        i += 1;
    }
    if (s.boundary == null) return cx.diags.fail(error.ParseError, line(t, 0), "PROC SEQTEST: the BOUNDARY= option is required", .{});
    s.adjust = adjust.items;
    s.errspendmin = mins.items;
    return s;
}

fn findDs(cx: proc.ProcCtx, l: usize, name: []const u8, opt: []const u8) diag.Error!*Dataset {
    return cx.lib.find(name) orelse cx.diags.fail(error.ParseError, l, "PROC SEQTEST: {s}= data set {s} does not exist", .{ opt, name });
}
fn need(cx: proc.ProcCtx, l: usize, ds: *const Dataset, opt: []const u8, name: []const u8) diag.Error!usize {
    return ds.indexOf(name) orelse cx.diags.fail(error.ParseError, l, "PROC SEQTEST: variable {s} is required in the {s}= data set", .{ name, opt });
}
fn numCell(cx: proc.ProcCtx, l: usize, ds: *const Dataset, r: usize, c: usize, opt: []const u8) diag.Error!f64 {
    const val = ds.row(r)[c];
    const x = switch (val) {
        .num => |n| n,
        .str => return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: variable {s} in the {s}= data set must be numeric", .{ ds.columns.items[c].name, opt }),
    };
    if (std.math.isNan(x)) return proc.failGap(cx.diags, l, "PROC SEQTEST: a missing value of {s} in the {s}= data set (observation {d}) is not verified", .{ ds.columns.items[c].name, opt, r + 1 });
    return x;
}
fn strCell(cx: proc.ProcCtx, l: usize, ds: *const Dataset, r: usize, c: usize, opt: []const u8) diag.Error![]const u8 {
    return switch (ds.row(r)[c]) {
        .str => |x| std.mem.trim(u8, x, " "),
        .num => cx.diags.fail(error.ParseError, l, "PROC SEQTEST: variable {s} in the {s}= data set must be character", .{ ds.columns.items[c].name, opt }),
    };
}
fn scaleOf(text: []const u8) ?Scale {
    const pairs = [_]struct { []const u8, Scale }{ .{ "mle", .mle }, .{ "score", .score }, .{ "stdz", .stdz }, .{ "pvalue", .pvalue } };
    for (pairs) |p| if (eq(text, p[0])) return p[1];
    return null;
}
/// One documented code that is the same on every observation.
fn constantCode(comptime E: type, cx: proc.ProcCtx, l: usize, ds: *const Dataset, c: usize, opt: []const u8, names: []const struct { []const u8, E }, comptime allowed: []const u8) diag.Error!E {
    var first: ?E = null;
    for (0..ds.rowCount()) |r| {
        const text = try strCell(cx, l, ds, r, c, opt);
        var got: ?E = null;
        for (names) |p| if (eq(text, p[0])) {
            got = p[1];
        };
        const g = got orelse return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: {s} in the {s}= data set must be " ++ allowed ++ " (found '{s}')", .{ ds.columns.items[c].name, opt, text });
        if (first) |f| {
            if (f != g) return proc.failGap(cx.diags, l, "PROC SEQTEST: {s} changing across observations of the {s}= data set is not verified", .{ ds.columns.items[c].name, opt });
        } else first = g;
    }
    return first.?;
}
fn optionalColumn(cx: proc.ProcCtx, l: usize, ds: *const Dataset, name: []const u8, opt: []const u8) diag.Error!?[]const f64 {
    const c = ds.indexOf(name) orelse return null;
    const out = try cx.arena.alloc(f64, ds.rowCount());
    for (out, 0..) |*x, r| x.* = try numCell(cx, l, ds, r, c, opt);
    return out;
}

/// The BOUNDARY= data set (p.9167): codes, stages, information proportions,
/// the boundary variables of Table 111.2 and the alternative references.
pub fn loadBoundary(cx: proc.ProcCtx, l: usize, name: []const u8) diag.Error!Boundary {
    const ds = try findDs(cx, l, name, "BOUNDARY");
    const o = "BOUNDARY";
    const c_scale = try need(cx, l, ds, o, "_Scale_");
    const c_stop = try need(cx, l, ds, o, "_Stop_");
    const c_alt = try need(cx, l, ds, o, "_ALT_");
    const c_stage = try need(cx, l, ds, o, "_Stage_");
    const c_prop = try need(cx, l, ds, o, "_InfoProp_");
    const k = ds.rowCount();
    if (k == 0) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: the BOUNDARY= data set has no observations", .{});
    var b: Boundary = .{
        .scale = try constantCode(Scale, cx, l, ds, c_scale, o, &.{ .{ "mle", .mle }, .{ "score", .score }, .{ "stdz", .stdz }, .{ "pvalue", .pvalue } }, "MLE, STDZ, SCORE or PVALUE"),
        .stop = try constantCode(Stop, cx, l, ds, c_stop, o, &.{ .{ "reject", .reject }, .{ "accept", .accept }, .{ "both", .both } }, "REJECT, ACCEPT or BOTH"),
        .alt = try constantCode(Alt, cx, l, ds, c_alt, o, &.{ .{ "upper", .upper }, .{ "lower", .lower }, .{ "twosided", .twosided } }, "UPPER, LOWER or TWOSIDED"),
        .stages = k,
        .info_prop = undefined,
    };
    const prop = try cx.arena.alloc(f64, k);
    for (0..k) |r| {
        const st = try numCell(cx, l, ds, r, c_stage, o);
        if (st != @as(f64, @floatFromInt(r + 1))) return proc.failGap(cx.diags, l, "PROC SEQTEST: BOUNDARY= stages that are not 1, 2, ... in order are not verified", .{});
        prop[r] = try numCell(cx, l, ds, r, c_prop, o);
        const prev: f64 = if (r == 0) 0 else prop[r - 1];
        if (!(prop[r] > prev and prop[r] <= 1)) return proc.failGap(cx.diags, l, "PROC SEQTEST: information proportions that do not increase within (0,1] are not verified", .{});
    }
    if (@abs(prop[k - 1] - 1) > 1e-8) return proc.failGap(cx.diags, l, "PROC SEQTEST: a final-stage information proportion other than 1 is not verified", .{});
    b.info_prop = prop;
    // Table 111.2: boundary variables required by the alternative and the stopping rule.
    const lower = b.alt != .upper;
    const upper = b.alt != .lower;
    const alpha = b.stop != .accept;
    const beta = b.stop != .reject;
    // One-sided designs (Table 111.2): accept-only keeps the beta boundary, reject-only the alpha boundary.
    const req = [_]struct { []const u8, bool }{
        .{ "Bound_LA", lower and alpha },
        .{ "Bound_LB", lower and beta },
        .{ "Bound_UB", upper and beta },
        .{ "Bound_UA", upper and alpha },
    };
    for (req) |q| if (q[1]) {
        const c = try need(cx, l, ds, o, q[0]);
        for (0..k) |r| _ = try numCell(cx, l, ds, r, c, o);
    };
    if (lower) b.altref_l = try numCell(cx, l, ds, 0, try need(cx, l, ds, o, "AltRef_L"), o);
    if (upper) b.altref_u = try numCell(cx, l, ds, 0, try need(cx, l, ds, o, "AltRef_U"), o);
    b.info = try optionalColumn(cx, l, ds, "_Info_", o);
    b.nobs = try optionalColumn(cx, l, ds, "NObs", o);
    b.events = try optionalColumn(cx, l, ds, "Events", o);
    if (b.info) |info| for (info, 0..) |x, r| {
        const prev: f64 = if (r == 0) 0 else info[r - 1];
        if (!(x > prev)) return proc.failGap(cx.diags, l, "PROC SEQTEST: BOUNDARY= _Info_ levels that do not increase are not verified", .{});
    };
    return b;
}

/// Information from a sample size column: I_k = I*_k * (n_k / n*_k) (pp.9168-9169).
fn infoFromCount(cx: proc.ProcCtx, l: usize, b: Boundary, stage: usize, n: f64, which: []const f64, opt: []const u8, var_name: []const u8) diag.Error!f64 {
    const info = b.info orelse return proc.failGap(cx.diags, l, "PROC SEQTEST: deriving the information level from {s} without _Info_ in the BOUNDARY= data set is not implemented", .{var_name});
    if (!(n > 0) or !(which[stage - 1] > 0)) return proc.failGap(cx.diags, l, "PROC SEQTEST: a nonpositive {s} in the {s}= data set is not verified", .{ var_name, opt });
    return info[stage - 1] * (n / which[stage - 1]);
}

/// Standardized Z of a statistic on `scale` with information `info` (p.9168:
/// MLE est*sqrt(I); score est/sqrt(I)). The p-value scale is a gap.
fn standardize(cx: proc.ProcCtx, l: usize, scale: Scale, est: f64, info: f64) diag.Error!f64 {
    return switch (scale) {
        .stdz => est,
        .mle => est * @sqrt(info),
        .score => est / @sqrt(info),
        .pvalue => proc.failGap(cx.diags, l, "PROC SEQTEST: a test statistic on the PVALUE scale is not implemented (STAT-SEQTEST-002)", .{}),
    };
}

/// The PARMS= (p.9168) or DATA= (p.9168) data set: the current stage, its
/// information level and, with TESTVAR=, its test statistic.
pub fn loadCurrent(cx: proc.ProcCtx, l: usize, s: Spec, b: Boundary) diag.Error!?Current {
    const parms = s.parms != null;
    if (parms and s.data != null) return proc.failGap(cx.diags, l, "PROC SEQTEST: DATA= together with PARMS= is not verified", .{});
    const name = s.parms orelse s.data orelse {
        if (s.testvar != null or s.infovar != null) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: TESTVAR= and INFOVAR= need a DATA= or PARMS= data set", .{});
        return null;
    };
    const o: []const u8 = if (parms) "PARMS" else "DATA";
    const ds = try findDs(cx, l, name, o);
    const c_stage = try need(cx, l, ds, o, "_Stage_");
    // Observation selection: with TESTVAR= in PARMS=, the rows of that parameter.
    var rows: std.ArrayList(usize) = .empty;
    var c_test: ?usize = null;
    if (s.testvar) |tv| {
        if (parms) {
            const c_par = ds.indexOf("Parameter") orelse ds.indexOf("Effect") orelse ds.indexOf("Variable") orelse ds.indexOf("Parm") orelse
                return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: variable Parameter, Effect, Variable or Parm is required in the PARMS= data set", .{});
            for (0..ds.rowCount()) |r| if (eq(try strCell(cx, l, ds, r, c_par, o), tv)) try rows.append(cx.arena, r);
            if (rows.items.len == 0) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: test variable {s} is not found in the PARMS= data set", .{tv});
            c_test = try need(cx, l, ds, o, "Estimate");
        } else {
            c_test = try need(cx, l, ds, o, tv);
            for (0..ds.rowCount()) |r| try rows.append(cx.arena, r);
        }
    } else for (0..ds.rowCount()) |r| try rows.append(cx.arena, r);
    if (rows.items.len == 0) return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: the {s}= data set has no observations", .{o});
    if (rows.items.len > 1) return proc.failGap(cx.diags, l, "PROC SEQTEST: more than one current-stage observation in the {s}= data set is not implemented", .{o});
    const r = rows.items[0];
    const st = try numCell(cx, l, ds, r, c_stage, o);
    const kmax = s.nstages orelse b.stages;
    if (st != @floor(st) or st < 1 or st > @as(f64, @floatFromInt(@min(kmax, b.stages))))
        return proc.failGap(cx.diags, l, "PROC SEQTEST: a {s}= _Stage_ of {d} outside the BOUNDARY= stages is not verified", .{ o, st });
    var cur: Current = .{ .stage = @intFromFloat(st), .info = null };
    if (c_test != null) {
        const sc = try need(cx, l, ds, o, "_Scale_");
        const text = try strCell(cx, l, ds, r, sc, o);
        cur.scale = scaleOf(text) orelse return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: _Scale_ in the {s}= data set must be MLE, STDZ, SCORE or PVALUE (found '{s}')", .{ o, text });
        cur.estimate = try numCell(cx, l, ds, r, c_test.?, o);
    }
    // Information level (INFOVAR= defaults, pp.9158-9159).
    const iv: InfoVar = s.infovar orelse blk: {
        if (parms and ds.indexOf("StdErr") != null) break :blk .stderr;
        if (!parms and ds.indexOf("_Info_") != null) break :blk .info;
        if (ds.indexOf("NObs") != null and b.nobs != null) break :blk .nobs;
        if (ds.indexOf("Events") != null and b.events != null) break :blk .events;
        break :blk .none;
    };
    switch (iv) {
        .none => {},
        .stderr => {
            const se = try numCell(cx, l, ds, r, try need(cx, l, ds, o, "StdErr"), o);
            if (!(se > 0)) return proc.failGap(cx.diags, l, "PROC SEQTEST: a nonpositive StdErr in the PARMS= data set is not verified", .{});
            // p.9169: score statistic I = s^2; otherwise I = 1/s^2.
            cur.info = if (cur.scale == .score) se * se else 1 / (se * se);
        },
        .info => {
            const x = try numCell(cx, l, ds, r, try need(cx, l, ds, o, "_Info_"), o);
            if (!(x > 0)) return proc.failGap(cx.diags, l, "PROC SEQTEST: a nonpositive _Info_ in the DATA= data set is not verified", .{});
            cur.info = x;
        },
        .nobs, .events => {
            const vn: []const u8 = if (iv == .nobs) "NObs" else "Events";
            const n = try numCell(cx, l, ds, r, try need(cx, l, ds, o, vn), o);
            const bcol = (if (iv == .nobs) b.nobs else b.events) orelse return cx.diags.fail(error.ParseError, l, "PROC SEQTEST: variable {s} is required in the BOUNDARY= data set", .{vn});
            cur.info = try infoFromCount(cx, l, b, cur.stage, n, bcol, o, vn);
        },
    }
    if (cur.estimate) |est| {
        const info = cur.info orelse if (b.info) |bi| bi[cur.stage - 1] else if (cur.scale == .stdz) 1 else
            return proc.failGap(cx.diags, l, "PROC SEQTEST: a test statistic without an information level is not implemented", .{});
        cur.z = try standardize(cx, l, cur.scale.?, est, info);
    }
    return cur;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    _ = out;
    const l0 = line(t, 0);
    const s = try parse(cx, t);
    const b = try loadBoundary(cx, l0, s.boundary.?);
    _ = try loadCurrent(cx, l0, s, b);
    // ponytail: the inputs are fully validated; every listing needs the group
    // sequential recursion (STAT-SEQTEST-002/003), so the step stops here.
    if (s.plots) return proc.failGap(cx.diags, l0, "PROC SEQTEST: PLOTS= graphs are not implemented", .{});
    return proc.failGap(cx.diags, l0, "PROC SEQTEST: the group sequential boundary computation and the Design Information and Test Information tables are not implemented (STAT-SEQTEST-002, STAT-SEQTEST-003)", .{});
}

test {
    _ = @import("seqtest_tests.zig");
}
