//! PROC TPSPLINE statements, roles and the default GCV path, SAS/STAT 15.4
//! Chapter 125 (PROC TPSPLINE statement pp.10298-10302, BY pp.10302-10303,
//! FREQ p.10303, ID p.10303, MODEL pp.10303-10306, OUTPUT pp.10306-10307,
//! Computational Formulas pp.10308-10312). The fit is the penalized
//! thin-plate smoothing spline of Wahba: with X = (1 x) = (Q1 Q2)(R;0) and
//! B = Q2'KQ2 = U diag(l) U', I - A(lambda) = n lambda Q2 U diag(1/(l+n lambda)) U'Q2',
//! so the GCV function, residuals, trace and hat diagonal are closed-form in
//! the eigen-decomposition of B. X = (T Z) holds the monomials of degree < m
//! in the d smoothing variables and the regression variables, K the basis
//! function eta_md (any d <= 6, m <= 10). What has not been proven against a
//! SAS reference run (the upper and lower ends of the smoothing-parameter
//! search, SCORE, the COEF output keyword, PLOTS=, and the combinations
//! named in the gap messages) is a D-009 gap (rc 2) raised before any
//! listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const functions = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const pc = @import("princomp.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    deps: []const usize = &.{},
    regs: []const usize = &.{},
    smooth: []const usize = &.{},
    lognl: []const f64 = &.{},
    /// LAMBDA= list (used only without LOGNLAMBDA=).
    lambda: []const f64 = &.{},
    lambda0: ?f64 = null,
    lognl0: ?f64 = null,
    df: ?f64 = null,
    range: ?[2]f64 = null,
    distance: f64 = 0,
    alpha: f64 = 0.05,
    m: usize = 2,
    out: ?[]const u8 = null,
    pred: bool = false,
    std: bool = false,
    resid: bool = false,
    lclm: bool = false,
    uclm: bool = false,
    adiag: bool = false,
    freq: ?usize = null,
    ids: []const usize = &.{},
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
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC TPSPLINE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC TPSPLINE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC TPSPLINE: " ++ text, args);
}

fn dsName(a: A, cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        if (!at(t, i.* + 1, .name)) return invalid(cx, t, i.* + 1);
        name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    return name;
}

/// A signed numeric literal.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * v;
}

fn startsNumber(t: []const lex.Token, i: usize) bool {
    return at(t, i, .number) or ((at(t, i, .minus) or at(t, i, .plus)) and at(t, i + 1, .number));
}

/// A list of values: numbers separated by blanks or commas and `start TO stop
/// <BY increment>` items, enclosed in parentheses (SAS 15.4 reference run:
/// `LOGNL=-2` is "ERROR 79-322: Expecting a (.").
pub fn valueList(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const f64 {
    const a = cx.arena;
    if (!at(t, i.*, .lparen)) return user(cx, lineOf(t, i.*), "expecting a ( to start the list of values", .{});
    i.* += 1;
    var vals: std.ArrayList(f64) = .empty;
    while (startsNumber(t, i.*)) {
        const start = try number(cx, t, i);
        if (kw(t, i.*, "to")) {
            i.* += 1;
            const stop = try number(cx, t, i);
            var inc: f64 = 1;
            if (kw(t, i.*, "by")) {
                i.* += 1;
                inc = try number(cx, t, i);
            }
            // SAS 15.4 reference run: (-2 to -4 by -1) lists -2 -3 -4.
            if (inc == 0 or (inc > 0 and stop < start) or (inc < 0 and stop > start)) return gap(cx, lineOf(t, i.*), "a TO list whose BY increment does not move toward the stop value is not verified", .{});
            var k: f64 = 0;
            const tol = 1e-9 * @abs(inc);
            while (if (inc > 0) start + k * inc <= stop + tol else start + k * inc >= stop - tol) : (k += 1) try vals.append(a, start + k * inc);
        } else try vals.append(a, start);
        if (at(t, i.*, .comma)) i.* += 1;
    }
    if (!at(t, i.*, .rparen)) return invalid(cx, t, i.*);
    i.* += 1;
    if (vals.items.len == 0) return invalid(cx, t, i.*);
    return vals.items;
}

fn column(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, t[i].text)});
}

fn numeric(cx: proc.ProcCtx, ds: *Dataset, c: usize, line: usize, role: []const u8) diag.Error!void {
    if (ds.columns.items[c].type != .num) return user(cx, line, "{s} variable {s} must be numeric", .{ role, ds.columns.items[c].name });
}

fn parseModel(cx: proc.ProcCtx, s: *Spec, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    const a = cx.arena;
    const line = t[start].line;
    var i = start + 1;
    var deps: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .eq)) : (i += 1) {
        const c = try column(cx, s.ds, t, i);
        try numeric(cx, s.ds, c, line, "Dependent");
        try deps.append(a, c);
    }
    if (deps.items.len == 0 or !at(t, i, .eq)) return user(cx, line, "the MODEL statement needs dependent-variables = (smoothing-variables)", .{});
    i += 1;
    var smooth: std.ArrayList(usize) = .empty;
    var regs: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) {
        if (at(t, i, .lparen)) {
            if (smooth.items.len > 0) return gap(cx, line, "more than one smoothing-variable list is not verified", .{});
            i += 1;
            while (i < end and !at(t, i, .rparen)) : (i += 1) {
                const c = try column(cx, s.ds, t, i);
                try numeric(cx, s.ds, c, line, "Smoothing");
                // SAS 15.4 reference run: `(x1 x1)` is rank deficient.
                for (smooth.items) |q| if (q == c) return cx.diags.fail(error.ParseError, line, dependent_cols, .{});
                try smooth.append(a, c);
            }
            if (!at(t, i, .rparen)) return invalid(cx, t, i);
            i += 1;
        } else if (at(t, i, .name)) {
            // "At least one smoothing variable is required, and it must be
            // listed after the regression variables" (p.10303).
            if (smooth.items.len > 0) return user(cx, line, "regression variables must be listed before the smoothing variables", .{});
            const c = try column(cx, s.ds, t, i);
            if (s.ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, line, "Variable {s} in list does not match type prescribed for this list.", .{t[i].text});
            try regs.append(a, c);
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (smooth.items.len == 0) return user(cx, line, "at least one smoothing variable, in parentheses, is required", .{});
    var lognl_given = false;
    var lambda: ?[]const f64 = null;
    var lambda_line: usize = line;
    var lambda0: ?f64 = null;
    var m_given: ?f64 = null;
    if (at(t, i, .slash)) {
        i += 1;
        while (i < end) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            const w = t[i].text;
            const wline = t[i].line;
            if (!at(t, i + 1, .eq)) return invalid(cx, t, i);
            i += 2;
            if (eq(w, "lognlambda") or eq(w, "lognl")) {
                s.lognl = try valueList(cx, t, &i);
                lognl_given = true;
            } else if (eq(w, "lambda")) {
                lambda = try valueList(cx, t, &i);
                lambda_line = wline;
            } else if (eq(w, "alpha")) {
                const v = try number(cx, t, &i);
                if (!(v > 0 and v < 1)) return user(cx, line, "ALPHA= must be between 0 and 1", .{});
                s.alpha = v;
            } else if (eq(w, "m")) {
                const v = try number(cx, t, &i);
                if (!(v >= 1) or v != @floor(v)) return user(cx, line, "M= must be a positive integer", .{});
                m_given = v;
            } else if (eq(w, "distance") or eq(w, "d")) {
                const v = try number(cx, t, &i);
                if (v < 0) return gap(cx, line, "a negative DISTANCE= value is not verified", .{});
                s.distance = v;
            } else if (eq(w, "lambda0")) {
                lambda0 = try number(cx, t, &i);
            } else if (eq(w, "lognlambda0") or eq(w, "lognl0")) {
                s.lognl0 = try number(cx, t, &i);
            } else if (eq(w, "df")) {
                const v = try number(cx, t, &i);
                // SAS 15.4 reference runs: DF=0 and DF=-1 warn and are ignored.
                if (!(v > 0)) {
                    try cx.diags.warn(wline, "The input value of the DF= option must be positive. The DF= option will be ignored.", .{});
                } else s.df = v;
            } else if (eq(w, "range")) {
                if (!at(t, i, .lparen)) return invalid(cx, t, i);
                i += 1;
                const lo = try number(cx, t, &i);
                // SAS 15.4 reference run: RANGE=(-3 -2) is "ERROR 78-322:
                // Expecting a ','."
                if (!at(t, i, .comma)) return cx.diags.fail(error.ParseError, wline, "Expecting a ','.", .{});
                i += 1;
                const hi = try number(cx, t, &i);
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
                // SAS 15.4 reference runs: RANGE=(-2,-3) and (-3,-3) are errors.
                if (!(lo < hi)) return cx.diags.fail(error.ParseError, wline, "The lower bound for the RANGE option must be less than the upper bound.", .{});
                s.range = .{ lo, hi };
            } else return invalid(cx, t, i - 2);
        }
    }
    // SAS 15.4 reference runs for the precedence warnings below.
    if (lambda) |vals| {
        if (lognl_given) {
            try cx.diags.warn(lambda_line, "Both LAMBDA= and LOGNLAMBDA= options have been used at the same time, only the LOGNLAMBDA= option will be in effect.", .{});
        } else {
            var ok = true;
            for (vals) |v| if (!(v > 0)) {
                ok = false;
            };
            if (ok) s.lambda = vals else try cx.diags.warn(lambda_line, "LAMBDA= ignored since at least one input LAMBDA value is not positive or too large.", .{});
        }
    }
    if (lambda0) |v| {
        if (s.lognl0 != null) {
            try cx.diags.warn(line, "Both LAMBDA0= and LOGNLAMBDA0= options have been used at the same time, only the LOGNLAMBDA0= option will be in effect.", .{});
        } else if (!(v > 0)) {
            try cx.diags.warn(line, "LAMBDA0= ignored since input LAMBDA0 value is either not positive or too large.", .{});
        } else s.lambda0 = v;
    }
    for (regs.items) |r| for (smooth.items) |c| if (c == r) return cx.diags.fail(error.ParseError, line, "At least one variable appears on both smoothing variable and regression variable lists.", .{});
    for (deps.items) |d| {
        for (smooth.items) |c| if (c == d) return cx.diags.fail(error.ParseError, line, both_lists, .{});
        for (regs.items) |c| if (c == d) return cx.diags.fail(error.ParseError, line, both_lists, .{});
    }
    // "The default value is max(2, int(d/2)+1)" (p.10305); SAS 15.4
    // reference run: M=1 with d=2 warns and uses the default.
    const d = smooth.items.len;
    const def_m = @max(2, d / 2 + 1);
    s.m = def_m;
    if (m_given) |v| {
        if (2 * v <= @as(f64, @floatFromInt(d))) {
            try cx.diags.warn(line, "Input value of the option M must be larger than d/2, where d is the number of smoothing variables. Set to the default value.", .{});
        } else if (v > 10) {
            return gap(cx, line, "M={d} is not verified (orders above 10)", .{v});
        } else s.m = @intFromFloat(v);
    }
    if (d > 6) return gap(cx, line, "{d} smoothing variables are not verified (at most 6)", .{d});
    if (s.distance > 0 and regs.items.len > 0) return gap(cx, line, "DISTANCE= greater than 0 with regression variables is not verified", .{});
    if (s.df != null and s.range != null) return gap(cx, line, "DF= together with RANGE= is not verified", .{});
    s.deps = deps.items;
    s.regs = regs.items;
    s.smooth = smooth.items;
}

const dependent_cols = "Columns generated by input variables are linearly dependent.";
const both_lists = "At least one variable appears on both dependent and independent lists.";

fn parseOutput(cx: proc.ProcCtx, s: *Spec, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    const a = cx.arena;
    const line = t[start].line;
    var i = start + 1;
    var any = false;
    while (i < end) {
        if (kw(t, i, "out") and at(t, i + 1, .eq)) {
            i += 2;
            s.out = try dsName(a, cx, t, &i);
            if (at(t, i, .lparen)) return gap(cx, line, "data set options on OUT= are not implemented", .{});
        } else if (kw(t, i, "pred")) {
            s.pred = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "std")) {
            s.std = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "resid") or kw(t, i, "r")) {
            s.resid = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "adiag")) {
            s.adiag = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "lclm")) {
            s.lclm = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "uclm")) {
            s.uclm = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "coef")) {
            return gap(cx, line, "the OUTPUT keyword {s} is not implemented (STAT-TPSPLINE-006)", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
    }
    if (s.out == null) return user(cx, line, "OUT= is required in the OUTPUT statement", .{});
    // "If no keyword is present, the data set contains only the original data
    // set and predicted values" (p.10306).
    if (!any) s.pred = true;
}

fn graphicsOn(cx: proc.ProcCtx) bool {
    const g = cx.graphics orelse return false;
    return g.enabled orelse false;
}

/// Plot requests of the PLOTS option (pp.10298-10302) with the aliases the
/// SAS 15.4 syntax error lists (RESIDHIST, RHIST, SCOREPANEL).
const plot_requests = [_][]const u8{
    "all",                 "contourfit",         "contourfitpanel",   "criterionplot", "criterion",
    "diagnosticspanel",    "diagnostics",        "fitpanel",          "fitplot",       "fit",
    "none",                "observedbypredicted", "qqplot",           "qq",            "residualbysmooth",
    "residualbypredicted", "residualhistogram",  "residhist",         "rhist",         "residualpanel",
    "residuals",           "rfplot",             "rf",                "scoreplot",     "score",
    "scorepanel",
};

fn isPlotRequest(w: []const u8) bool {
    for (plot_requests) |r| if (eq(w, r)) return true;
    return false;
}

/// One plot request and its documented suboptions. Returns true for NONE.
fn plotRequest(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!bool {
    if (!at(t, i.*, .name) or !isPlotRequest(t[i.*].text)) return user(cx, lineOf(t, i.*), "Syntax error in the PLOTS option at {s}, expecting one of the following: (, ALL, CONTOURFIT, CONTOURFITPANEL, CRITERION, DIAGNOSTICS, FIT, FITPANEL, NONE, OBSERVEDBYPREDICTED, QQ, QQPLOT, RESIDHIST, RESIDUALBYPREDICTED, RESIDUALBYSMOOTH, RESIDUALHISTOGRAM, RESIDUALS, RF, RFPLOT, RHIST, SCORE, SCOREPANEL.", .{if (i.* < t.len) t[i.*].text else "<end>"});
    const none = eq(t[i.*].text, "none");
    i.* += 1;
    if (!at(t, i.*, .lparen)) return none;
    i.* += 1;
    while (!at(t, i.*, .rparen)) {
        if (kw(t, i.*, "clm") or kw(t, i.*, "unpack") or kw(t, i.*, "smooth") or kw(t, i.*, "nopath")) {
            i.* += 1;
        } else if (kw(t, i.*, "obs") and at(t, i.* + 1, .eq) and (kw(t, i.* + 2, "gradient") or kw(t, i.* + 2, "none") or kw(t, i.* + 2, "outline") or kw(t, i.* + 2, "outlinegradient"))) {
            i.* += 3;
        } else return gap(cx, lineOf(t, i.*), "the plot suboption {s} is not verified (STAT-TPSPLINE-008)", .{if (i.* < t.len) t[i.*].text else "<end>"});
    }
    i.* += 1;
    return none;
}

/// PLOTS <(global-plot-options)> <= plot-request | =(plot-request ...)>.
/// Returns true when the only request is NONE.
fn parsePlots(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!bool {
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        while (!at(t, i.*, .rparen)) {
            if (kw(t, i.*, "only") or kw(t, i.*, "unpack")) {
                i.* += 1;
            } else return gap(cx, lineOf(t, i.*), "the global plot option {s} is not verified (STAT-TPSPLINE-008)", .{if (i.* < t.len) t[i.*].text else "<end>"});
        }
        i.* += 1;
    }
    if (!at(t, i.*, .eq)) return false;
    i.* += 1;
    if (!at(t, i.*, .lparen)) return plotRequest(cx, t, i);
    i.* += 1;
    var n: usize = 0;
    var all_none = true;
    while (!at(t, i.*, .rparen)) : (n += 1) {
        if (!try plotRequest(cx, t, i)) all_none = false;
    }
    i.* += 1;
    return n > 0 and all_none;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var plots_seen = false;
    var plots_none = false;
    var plots_line: usize = 0;
    var i: usize = 2;
    const l0 = lineOf(t, 0);
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            // SAS 15.4 reference run: the first DATA= is used and a later one
            // warns.
            if (data != null) try cx.diags.warn(t[i].line, "Ignoring second data set reference.", .{});
            i += 2;
            const name = try dsName(a, cx, t, &i);
            if (data == null) data = name;
            if (at(t, i, .lparen)) {
                var depth: usize = 0;
                while (i < t.len and !at(t, i, .eof)) : (i += 1) {
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (eq(word, "plots") or eq(word, "plot")) {
            // SAS 15.4 reference run: with ODS Graphics off, several PLOTS
            // options give one warning; which one wins with ODS Graphics on is
            // not verified (STAT-TPSPLINE-008).
            if (plots_seen and graphicsOn(cx)) return gap(cx, t[i].line, "more than one PLOTS option with ODS Graphics enabled is not verified (STAT-TPSPLINE-008)", .{});
            if (!plots_seen) plots_line = t[i].line;
            plots_seen = true;
            i += 1;
            plots_none = try parsePlots(cx, t, &i);
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // SAS 15.4 reference runs: with ODS Graphics disabled, any PLOTS option
    // (PLOTS=NONE included) warns and the listing is unchanged; with ODS
    // Graphics enabled, the default plots and every request but NONE are
    // ODS Graphics output (STAT-TPSPLINE-008).
    if (graphicsOn(cx)) {
        if (!plots_none) return gap(cx, if (plots_seen) plots_line else l0, "ODS Graphics plots are not implemented (STAT-TPSPLINE-008); use PLOTS=NONE or ODS GRAPHICS OFF", .{});
    } else if (plots_seen) try cx.diags.warn(plots_line, "You must enable ODS graphics before requesting plots.", .{});
    const raw = if (data) |name|
        cx.lib.find(name) orelse return user(cx, l0, "input data set {s} not found", .{name})
    else
        proc.lastDataset(cx.lib) orelse return user(cx, l0, "there is no default input data set (_LAST_ is _NULL_)", .{});
    s.ds = try proc.procInput(a, raw, t, cx.diags);

    var bys: by.Statements = .{};
    var by_seen = false;
    var model_seen = false;
    var output_seen = false;
    var ids: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "more than one MODEL statement is not verified", .{});
            model_seen = true;
            try parseModel(cx, &s, t, i, end);
        } else if (kw(t, i, "output")) {
            if (output_seen) return gap(cx, t[i].line, "more than one OUTPUT statement is not verified", .{});
            output_seen = true;
            try parseOutput(cx, &s, t, i, end);
        } else if (kw(t, i, "freq")) {
            if (end != i + 2) return user(cx, t[i].line, "the FREQ statement takes exactly one variable", .{});
            // SAS 15.4 reference run: a second FREQ statement is an error.
            if (s.freq != null) return cx.diags.fail(error.ParseError, t[i].line, "Freq statement is used incorrectly.", .{});
            const c = try column(cx, s.ds, t, i + 1);
            if (s.ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} in list does not match type prescribed for this list.", .{t[i + 1].text});
            s.freq = c;
        } else if (kw(t, i, "id")) {
            // "more than one ID statement can be used"; the values only label
            // plot tooltips (p.10303).
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) {
                const line = t[j].line;
                const names = try lists.next(a, s.ds, t[0..end], &j, cx.diags);
                for (names) |n| {
                    const c = s.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                    try ids.append(a, c);
                }
            }
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.10302).
            by_seen = true;
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "score")) {
            return gap(cx, t[i].line, "the SCORE statement is not implemented (STAT-TPSPLINE-005)", .{});
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where")) {
            // Step boundaries; WHERE is applied by procInput.
        } else if (kw(t, i, "weight") or kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib")) {
            return gap(cx, t[i].line, "the {s} statement is not implemented", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return user(cx, l0, "a MODEL statement is required", .{});
    s.ids = ids.items;
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    return s;
}

/// The thin-plate basis function eta_md(r) (Computational Formulas,
/// p.10308): for d even (-1)^(m+1+d/2) / (2^(2m-1) pi^(d/2) (m-1)! (m-d/2)!)
/// r^(2m-d) log r, for d odd Gamma(d/2-m) / (2^(2m) pi^(d/2) (m-1)!) r^(2m-d).
/// d=2, m=2 gives E2(s) = ||s||^2 log||s|| / (2^3 pi) (p.10309).
pub fn kernel(r: f64, d: usize, m: usize) f64 {
    if (r == 0) return 0;
    const df: f64 = @floatFromInt(d);
    const pw = std.math.pow(f64, r, @floatFromInt(2 * m - d));
    const pi_d = std.math.pow(f64, std.math.pi, df / 2);
    if (d % 2 == 0) {
        const sign: f64 = if ((m + 1 + d / 2) % 2 == 0) 1 else -1;
        const den = std.math.pow(f64, 2, @floatFromInt(2 * m - 1)) * pi_d * factorial(m - 1) * factorial(m - d / 2);
        return sign / den * pw * @log(r);
    }
    const den = std.math.pow(f64, 2, @floatFromInt(2 * m)) * pi_d * factorial(m - 1);
    return halfGamma(@as(i64, @intCast(d)) - 2 * @as(i64, @intCast(m))) / den * pw;
}

fn factorial(k: usize) f64 {
    var f: f64 = 1;
    for (2..k + 1) |j| f *= @floatFromInt(j);
    return f;
}

/// Gamma(h/2) for an odd integer h, from Gamma(1/2) = sqrt(pi).
fn halfGamma(h: i64) f64 {
    var g: f64 = @sqrt(std.math.pi);
    var x: i64 = 1; // current argument is x/2
    while (x > h) : (x -= 2) g /= @as(f64, @floatFromInt(x - 2)) / 2;
    while (x < h) : (x += 2) g *= @as(f64, @floatFromInt(x)) / 2;
    return g;
}

/// Dimension of the polynomial space, C(m+d-1, d) (p.10308).
pub fn polyDim(d: usize, m: usize) usize {
    var c: f64 = 1;
    for (0..d) |j| c = c * @as(f64, @floatFromInt(m + j)) / @as(f64, @floatFromInt(j + 1));
    return @intFromFloat(@round(c));
}

/// Exponent tuples of the monomials of total degree < m in d variables.
fn monomials(a: A, d: usize, m: usize) ![]const []const usize {
    var all: std.ArrayList([]const usize) = .empty;
    const cur = try a.alloc(usize, d);
    @memset(cur, 0);
    const Rec = struct {
        fn go(al: A, list: *std.ArrayList([]const usize), e: []usize, j: usize, left: usize) !void {
            if (j == e.len) {
                try list.append(al, try al.dupe(usize, e));
                return;
            }
            for (0..left + 1) |k| {
                e[j] = k;
                try go(al, list, e, j + 1, left - k);
            }
            e[j] = 0;
        }
    };
    try Rec.go(a, &all, cur, 0, m - 1);
    return all.items;
}

/// The lambda-independent part of the fit.
pub const Basis = struct {
    n: usize,
    k: usize,
    /// W = Q2 U, n*k row-major.
    w: []f64,
    lam: []f64,
    /// z = W'y.
    z: []f64,
};

pub const Stats = struct { gcv: f64, rss: f64, tr: f64, penalty: f64 };

pub const FitError = error{ OutOfMemory, LinearlyDependent };

/// Householder QR of X (n*p); returns Q2 (n*(n-p)), an orthonormal basis of
/// the null space of X'. A column with no component outside the span of the
/// earlier ones is rank deficiency.
fn nullBasis(a: A, xm: []const f64, n: usize, p: usize) FitError![]f64 {
    const r = try a.dupe(f64, xm);
    const q = try a.alloc(f64, n * n);
    @memset(q, 0);
    for (0..n) |i| q[i * n + i] = 1;
    const v = try a.alloc(f64, n);
    for (0..p) |j| {
        var full: f64 = 0;
        for (0..n) |i| full += xm[i * p + j] * xm[i * p + j];
        var norm: f64 = 0;
        for (j..n) |i| norm += r[i * p + j] * r[i * p + j];
        norm = @sqrt(norm);
        if (j >= n or !(norm > 1e-9 * @max(@sqrt(full), 1e-300))) return error.LinearlyDependent;
        const alpha = if (r[j * p + j] > 0) -norm else norm;
        @memset(v, 0);
        for (j..n) |i| v[i] = r[i * p + j];
        v[j] -= alpha;
        var vv: f64 = 0;
        for (j..n) |i| vv += v[i] * v[i];
        if (vv == 0) continue;
        for (0..p) |c| {
            var dot: f64 = 0;
            for (j..n) |i| dot += v[i] * r[i * p + c];
            const f = 2 * dot / vv;
            for (j..n) |i| r[i * p + c] -= f * v[i];
        }
        // Q <- Q H.
        for (0..n) |row| {
            var dot: f64 = 0;
            for (j..n) |i| dot += q[row * n + i] * v[i];
            const f = 2 * dot / vv;
            for (j..n) |i| q[row * n + i] -= f * v[i];
        }
    }
    const k = n - p;
    const q2 = try a.alloc(f64, n * k);
    for (0..n) |i| for (0..k) |c| {
        q2[i * k + c] = q[i * n + p + c];
    };
    return q2;
}

/// d=2, m=2, no regression variables.
pub fn basis(a: A, x: []const f64, y: []const f64, d: usize) FitError!Basis {
    return basisFull(a, x, &.{}, 0, y, d, defaultOrder(d));
}

fn defaultOrder(d: usize) usize {
    return @max(2, d / 2 + 1);
}

/// x: n*d smoothing coordinates, zr: n*p regression values, y: n responses,
/// m: penalty order. X = (T Z) with T the monomials of degree < m (p.10309).
pub fn basisFull(a: A, x: []const f64, zr: []const f64, p: usize, y: []const f64, d: usize, m: usize) FitError!Basis {
    const n = y.len;
    const mons = try monomials(a, d, m);
    const cols = mons.len + p;
    if (cols >= n) return error.LinearlyDependent;
    const xm = try a.alloc(f64, n * cols);
    for (0..n) |i| {
        for (mons, 0..) |e, c| {
            var v: f64 = 1;
            for (e, 0..) |pw, l| v *= std.math.pow(f64, x[i * d + l], @floatFromInt(pw));
            xm[i * cols + c] = v;
        }
        for (0..p) |c| xm[i * cols + mons.len + c] = zr[i * p + c];
    }
    const k = n - cols;
    const q2 = try nullBasis(a, xm, n, cols);
    const kq = try a.alloc(f64, n * k);
    const krow = try a.alloc(f64, n);
    for (0..n) |i| {
        for (0..n) |j| {
            var ss: f64 = 0;
            for (0..d) |l| {
                const diff = x[i * d + l] - x[j * d + l];
                ss += diff * diff;
            }
            krow[j] = kernel(@sqrt(ss), d, m);
        }
        for (0..k) |c| {
            var acc: f64 = 0;
            for (0..n) |j| acc += krow[j] * q2[j * k + c];
            kq[i * k + c] = acc;
        }
    }
    const b = try a.alloc(f64, k * k);
    for (0..k) |r| for (0..k) |c| {
        var acc: f64 = 0;
        for (0..n) |i| acc += q2[i * k + r] * kq[i * k + c];
        b[r * k + c] = acc;
    };
    for (0..k) |r| for (0..r) |c| {
        const avg = 0.5 * (b[r * k + c] + b[c * k + r]);
        b[r * k + c] = avg;
        b[c * k + r] = avg;
    };
    const e = try pc.eigenSym(a, b, k);
    const w = try a.alloc(f64, n * k);
    for (0..n) |i| for (0..k) |c| {
        var acc: f64 = 0;
        for (0..k) |r| acc += q2[i * k + r] * e.vectors[r * k + c];
        w[i * k + c] = acc;
    };
    const lam = try a.alloc(f64, k);
    const z = try a.alloc(f64, k);
    for (0..k) |c| {
        // B is positive semidefinite; rounding can leave tiny negatives.
        lam[c] = @max(e.values[c], 0);
        var acc: f64 = 0;
        for (0..n) |i| acc += w[i * k + c] * y[i];
        z[c] = acc;
    }
    return .{ .n = n, .k = k, .w = w, .lam = lam, .z = z };
}

/// GCV(lambda) = (1/n)||(I-A)y||^2 / [(1/n)tr(I-A)]^2 at log10(n lambda) = l
/// (p.10311); the penalty is delta'K delta.
pub fn stats(b: Basis, l: f64) Stats {
    const nl = std.math.pow(f64, 10, l);
    var tr: f64 = 0;
    var rss: f64 = 0;
    var pen: f64 = 0;
    for (b.lam, b.z) |lk, zk| {
        const wk = nl / (lk + nl);
        tr += wk;
        rss += wk * wk * zk * zk;
        pen += lk * zk * zk / ((lk + nl) * (lk + nl));
    }
    const nf: f64 = @floatFromInt(b.n);
    return .{ .gcv = nf * rss / (tr * tr), .rss = rss, .tr = tr, .penalty = pen };
}

/// Lower end of the smoothing-parameter search on the log10(n lambda)
/// scale. SAS 15.4 reference runs (n = 30 and 50, d = 2, 3, 4, kernels
/// rescaled by 100) all stop at -6.9773 = log10(sqrt(50 * 2^-52)) when GCV
/// decreases toward interpolation or DF= exceeds what is reachable.
pub const search_lo: f64 = -6.977283;

/// The GCV minimizer on the log10(n lambda) scale over [lo, hi]: a grid
/// followed by golden-section refinement of the best bracket.
pub fn minimizeIn(b: Basis, lo: f64, hi: f64) f64 {
    const steps: usize = 300;
    const step = (hi - lo) / @as(f64, @floatFromInt(steps));
    var best: usize = 0;
    var best_v = std.math.inf(f64);
    for (0..steps + 1) |s| {
        const v = stats(b, lo + step * @as(f64, @floatFromInt(s))).gcv;
        if (v < best_v) {
            best_v = v;
            best = s;
        }
    }
    var x0 = lo + step * @as(f64, @floatFromInt(if (best == 0) 0 else best - 1));
    var x1 = lo + step * @as(f64, @floatFromInt(@min(best + 1, steps)));
    const g: f64 = (@sqrt(@as(f64, 5.0)) - 1) / 2;
    var c = x1 - g * (x1 - x0);
    var d = x0 + g * (x1 - x0);
    var fc = stats(b, c).gcv;
    var fd = stats(b, d).gcv;
    while (x1 - x0 > 1e-10) {
        if (fc < fd) {
            x1 = d;
            d = c;
            fd = fc;
            c = x1 - g * (x1 - x0);
            fc = stats(b, c).gcv;
        } else {
            x0 = c;
            c = d;
            fc = fd;
            d = x0 + g * (x1 - x0);
            fd = stats(b, d).gcv;
        }
    }
    return 0.5 * (x0 + x1);
}

pub fn minimize(b: Basis) f64 {
    return minimizeIn(b, search_lo, search_hi);
}

/// Upper end of the default search (see `upperLimitReached`).
pub const search_hi: f64 = 5;

/// log10(n lambda) with tr(A) = df, tr(A) decreasing in lambda; null when df
/// is at or below the polynomial-space limit within the search.
pub fn solveDf(b: Basis, df: f64) ?f64 {
    const nf: f64 = @floatFromInt(b.n);
    const dfAt = struct {
        fn f(bb: Basis, l: f64, n: f64) f64 {
            return n - stats(bb, l).tr;
        }
    }.f;
    // SAS 15.4 reference runs: DF= at or above the reachable maximum stops at
    // the lower end of the search.
    if (dfAt(b, search_lo, nf) <= df) return search_lo;
    var hi: f64 = 20;
    if (dfAt(b, hi, nf) >= df) return null;
    var lo: f64 = search_lo;
    for (0..200) |_| {
        const mid = 0.5 * (lo + hi);
        if (dfAt(b, mid, nf) > df) lo = mid else hi = mid;
    }
    return 0.5 * (lo + hi);
}

/// Fitted values and hat diagonal at log10(n lambda) = l.
pub fn fitted(a: A, b: Basis, y: []const f64, l: f64) !struct { f: []f64, adiag: []f64 } {
    const nl = std.math.pow(f64, 10, l);
    const f = try a.alloc(f64, b.n);
    const ad = try a.alloc(f64, b.n);
    for (0..b.n) |i| {
        var res: f64 = 0;
        var off: f64 = 0;
        for (0..b.k) |c| {
            const wic = b.w[i * b.k + c];
            const wk = nl / (b.lam[c] + nl);
            res += wic * wk * b.z[c];
            off += wic * wic * wk;
        }
        f[i] = y[i] - res;
        ad[i] = 1 - off;
    }
    return .{ .f = f, .adiag = ad };
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => false,
    };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try pad(a, out, (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

const Row = struct { label: []const u8, value: []const u8 };

/// A two-column label/value table (SAS 15.4 reference layout).
/// `fixed_vw` > 0 fixes the value column width; SAS 15.4 reference runs:
/// longer Summary Statistics values (2558.1432) extend into the gap.
fn table(a: A, out: *Out, titles: []const []const u8, rows: []const Row, gap_w: usize, blanks: usize, fixed_vw: usize) !void {
    var lw: usize = 0;
    var vw: usize = fixed_vw;
    for (rows) |r| {
        lw = @max(lw, r.label.len);
        if (fixed_vw == 0) vw = @max(vw, r.value.len);
    }
    const width = lw + gap_w + vw;
    try out.appendNTimes(a, '\n', blanks);
    for (titles) |tt| try centered(a, out, tt, width);
    try out.append(a, '\n');
    for (rows) |r| {
        try out.appendSlice(a, r.label);
        try pad(a, out, @max(width -| (r.label.len + r.value.len), 1));
        try out.appendSlice(a, r.value);
        try out.append(a, '\n');
    }
}

pub const OutVar = struct { name: []const u8, label: []const u8 };

/// OUTPUT variables: SAS 15.4 reference run order P_, StD_, R_, LCLM_,
/// UCLM_, Adiag_ whatever the keyword order, with these labels.
pub fn outputVars(a: A, s: Spec, dname: []const u8) ![]const OutVar {
    const pct = try std.fmt.allocPrint(a, "{d}", .{@round(1e6 * 100 * (1 - s.alpha)) / 1e6});
    var vars: std.ArrayList(OutVar) = .empty;
    for ([_]struct { on: bool, prefix: []const u8, label: []const u8 }{
        .{ .on = s.pred, .prefix = "P_", .label = "Predicted Value of " },
        .{ .on = s.std, .prefix = "StD_", .label = "Standard Deviation of " },
        .{ .on = s.resid, .prefix = "R_", .label = "Residual of " },
        .{ .on = s.lclm, .prefix = "LCLM_", .label = try std.fmt.allocPrint(a, "Lower {s}% Confidence Limit for Mean of ", .{pct}) },
        .{ .on = s.uclm, .prefix = "UCLM_", .label = try std.fmt.allocPrint(a, "Upper {s}% Confidence Limit for Mean of ", .{pct}) },
        .{ .on = s.adiag, .prefix = "Adiag_", .label = "Diagonal Elements of Matrix A for " },
    }) |kwd| if (kwd.on) try vars.append(a, .{
        .name = try std.fmt.allocPrint(a, "{s}{s}", .{ kwd.prefix, dname }),
        .label = try std.fmt.allocPrint(a, "{s}{s}", .{ kwd.label, dname }),
    });
    return vars.items;
}

/// One dependent variable's analysis inside one BY group.
const Fit = struct {
    keep: []usize,
    /// Expanded (FREQ) design: smoothing coordinates, regression values, responses.
    x: []f64,
    zr: []f64,
    y: []f64,
    owner: []usize,
    missing: usize,
    unique: usize,
};

/// DISTANCE= grouping (p.10304): sort by the smoothing variables in MODEL
/// order; each point joins the current unique point unless some coordinate
/// differs from it by more than D/2, when it becomes the next unique point.
/// Replaces x in place by its unique point; returns the number of them.
fn groupDistance(a: A, x: []f64, n: usize, d: usize, dist: f64) !usize {
    const idx = try a.alloc(usize, n);
    for (idx, 0..) |*v, k| v.* = k;
    const Ctx = struct {
        x: []const f64,
        d: usize,
        fn less(c: @This(), l: usize, r: usize) bool {
            for (0..c.d) |j| {
                const u = c.x[l * c.d + j];
                const v = c.x[r * c.d + j];
                if (u != v) return u < v;
            }
            return l < r;
        }
    };
    std.mem.sort(usize, idx, Ctx{ .x = x, .d = d }, Ctx.less);
    const u = try a.alloc(f64, d);
    var count: usize = 0;
    for (idx, 0..) |r, k| {
        var far = k == 0;
        if (!far) for (0..d) |j| if (@abs(x[r * d + j] - u[j]) > dist / 2) {
            far = true;
        };
        if (far) {
            @memcpy(u, x[r * d .. r * d + d]);
            count += 1;
        } else @memcpy(x[r * d .. r * d + d], u);
    }
    return count;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (s.ds.rows.items.len == 0 or slices.len == 0) return cx.diags.fail(error.ParseError, 0, "No valid observations in the input data set or one of the variables in the model statement contains all missing values.", .{});
    const cols = s.ds.columns.items;
    const d = s.smooth.len;
    const p = s.regs.len;
    const mdim = polyDim(d, s.m);
    const z = functions.distQuantile(.normal, 1 - s.alpha / 2, &.{}).?;
    const nd = s.deps.len;
    if (nd > 1 and s.by_cols.len > 0) return gap(cx, 0, "several dependent variables with BY groups are not verified", .{});

    var o: ?*Dataset = null;
    // OUTPUT variables: SAS 15.4 reference run with two dependents orders
    // them keyword by keyword (P_y P_y2 R_y R_y2).
    var per_kw: usize = 0;
    if (s.out) |member| {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, member);
        for (cols) |c| _ = try ds.addColumnLike(c.name, c);
        const first = try outputVars(a, s, cols[s.deps[0]].name);
        per_kw = first.len;
        for (0..per_kw) |kq| for (s.deps) |dep| {
            const ov = (try outputVars(a, s, cols[dep].name))[kq];
            if (ds.indexOf(ov.name) != null) return gap(cx, 0, "output variable {s} collides with another variable; the rule is not verified", .{ov.name});
            _ = try ds.addColumn(ov.name, .num);
            ds.setLabel(ov.name, ov.label);
        };
        o = ds;
    }

    // Validate every group before any listing text.
    var truncated = false;
    var nonpositive = false;
    const fits = try a.alloc(Fit, slices.len * nd);
    for (slices, 0..) |slice, si| for (s.deps, 0..) |dep, di| {
        const g = &fits[si * nd + di];
        var keep: std.ArrayList(usize) = .empty;
        var miss: usize = 0;
        var dropped: usize = 0;
        for (slice.rows, 0..) |row, r| {
            // SAS 15.4 reference runs: a missing smoothing variable counts the
            // observation as missing whatever its frequency; otherwise a
            // missing FREQ value drops it silently and a FREQ value below one
            // drops it with a NOTE ("less than one ... not used", p.10303),
            // neither being counted as missing; only then does a missing
            // response count as missing (per dependent variable, SAS 15.4
            // reference run with two dependents).
            for (s.regs) |c| if (isMissing(row[c])) return gap(cx, 0, "missing regression-variable values are not verified", .{});
            var bad = false;
            for (s.smooth) |c| if (isMissing(row[c])) {
                bad = true;
            };
            if (bad) {
                miss += 1;
                continue;
            }
            if (s.freq) |fc| {
                const fv = row[fc].num;
                if (std.math.isNan(fv)) {
                    dropped += 1;
                    continue;
                }
                if (fv != @floor(fv)) truncated = true;
                if (fv < 1) {
                    nonpositive = true;
                    dropped += 1;
                    continue;
                }
            }
            if (isMissing(row[dep])) miss += 1 else try keep.append(a, r);
        }
        if ((miss > 0 or dropped > 0) and o != null) return gap(cx, 0, "OUTPUT values for observations excluded by missing values or FREQ are not verified (STAT-TPSPLINE-006)", .{});
        if (keep.items.len == 0) {
            g.* = .{ .keep = keep.items, .x = &.{}, .zr = &.{}, .y = &.{}, .owner = &.{}, .missing = miss, .unique = 0 };
            continue;
        }
        // FREQ: "treats the data as if each observation appears n times"
        // (p.10303); only the integer portion is used.
        var xs: std.ArrayList(f64) = .empty;
        var zs: std.ArrayList(f64) = .empty;
        var ys: std.ArrayList(f64) = .empty;
        var owner: std.ArrayList(usize) = .empty;
        const kx = try a.alloc(f64, keep.items.len * d);
        for (keep.items, 0..) |r, k| for (s.smooth, 0..) |c, j| {
            kx[k * d + j] = slice.rows[r][c].num;
        };
        var unique: usize = 0;
        if (s.distance > 0) {
            unique = try groupDistance(a, kx, keep.items.len, d, s.distance);
        } else for (0..keep.items.len) |k| {
            var seen = false;
            for (0..k) |q| {
                if (std.mem.eql(f64, kx[q * d .. q * d + d], kx[k * d .. k * d + d])) {
                    seen = true;
                    break;
                }
            }
            if (!seen) unique += 1;
        }
        for (keep.items, 0..) |r, k| {
            const row = slice.rows[r];
            const times: usize = if (s.freq) |fc| @intFromFloat(@floor(row[fc].num)) else 1;
            for (0..times) |_| {
                try xs.appendSlice(a, kx[k * d .. k * d + d]);
                for (s.regs) |c| try zs.append(a, row[c].num);
                try ys.append(a, row[dep].num);
                try owner.append(a, k);
            }
        }
        // The spline needs more unique design points than the dimension of
        // the polynomial space.
        if (unique <= mdim) return gap(cx, 0, "{d} or fewer unique smoothing design points is not verified", .{mdim});
        g.* = .{ .keep = keep.items, .x = xs.items, .zr = zs.items, .y = ys.items, .owner = owner.items, .missing = miss, .unique = unique };
    };

    if (nonpositive) try cx.diags.note(0, "At least one observation was not used in computations because of non-positive frequency.", .{});
    if (truncated) try cx.diags.note(0, "At least one frequency has been truncated because of a non-integer value.", .{});
    const no_valid = "No valid observations in the input data set or one of the variables in the model statement contains all missing values.";
    for (slices, 0..) |slice, si| {
        const fitted_vals = try a.alloc([]const f64, nd * per_kw);
        var ran = false;
        for (s.deps, 0..) |dep, di| {
            const g = fits[si * nd + di];
            const dname = cols[dep].name;
            // SAS 15.4 reference runs: an empty input or a group with no usable
            // observation is an ERROR; under BY the other groups still run.
            if (g.y.len == 0) {
                if (s.by_cols.len == 0) return cx.diags.fail(error.ParseError, 0, no_valid, .{});
                try cx.diags.report(.err, 0, no_valid, .{});
                try by.reportNote(a, cx.diags, s.ds, slice.rep.?, s.by_cols);
                continue;
            }
            ran = true;
            const b = basisFull(a, g.x, g.zr, p, g.y, d, s.m) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                // SAS 15.4 reference runs: a regression variable collinear with
                // the polynomial space, or one listed twice.
                error.LinearlyDependent => return cx.diags.fail(error.ParseError, 0, dependent_cols, .{}),
            };
            const nf: f64 = @floatFromInt(g.y.len);
            // Precedence (p.10305 and SAS 15.4 reference runs): DF= over
            // LOGNLAMBDA0= over LAMBDA0= over the GCV minimum (within RANGE=).
            const lfin = if (s.df) |df|
                solveDf(b, df) orelse return gap(cx, 0, "DF={d} at or below the polynomial-space dimension is not verified", .{df})
            else if (s.lognl0) |l|
                l
            else if (s.lambda0) |l0|
                std.math.log10(nf * l0)
            else if (s.range) |r|
                minimizeIn(b, r[0], r[1])
            else blk: {
                const l = minimize(b);
                if (l > search_hi - 0.5) return gap(cx, 0, "the GCV minimum lies at the upper end of the smoothing-parameter search, whose SAS limit is not verified", .{});
                break :blk l;
            };
            // SAS 15.4 reference runs at the lower end of the search (GCV
            // decreasing toward interpolation, DF= at or above nq) agree in
            // log10(n lambda) but not in the last digits of the penalty and
            // the near-zero residual statistics.
            if (s.lognl0 == null and s.lambda0 == null and s.range == null and lfin <= search_lo + 1e-6) return gap(cx, 0, "the smoothing-parameter search reached its lower end (log10(n*Lambda) = -6.9773); the SAS statistics there are not reproduced", .{});
            const st = stats(b, lfin);
            const fit = try fitted(a, b, g.y, lfin);
            const sigma = @sqrt(st.rss / st.tr);

            try pageStart(cx, out);
            try byLine(a, out, s, slice);
            try out.print(a, "\nThe TPSPLINE Procedure\nDependent Variable:  {s}\n", .{dname});
            if (s.freq) |fc| try out.print(a, "Frequency Variable:  {s}\n", .{cols[fc].name});
            try table(a, out, &.{"Summary of Input Data Set"}, &.{
                .{ .label = "Number of Non-Missing Observations", .value = try std.fmt.allocPrint(a, "{d}", .{g.y.len}) },
                .{ .label = "Number of Missing Observations", .value = try std.fmt.allocPrint(a, "{d}", .{g.missing}) },
                .{ .label = "Unique Smoothing Design Points", .value = try std.fmt.allocPrint(a, "{d}", .{g.unique}) },
            }, 4, 1, 0);
            try table(a, out, &.{"Summary of Final Model"}, &.{
                .{ .label = "Number of Regression Variables", .value = try std.fmt.allocPrint(a, "{d}", .{p}) },
                .{ .label = "Number of Smoothing Variables", .value = try std.fmt.allocPrint(a, "{d}", .{d}) },
                .{ .label = "Order of Derivative in the Penalty", .value = try std.fmt.allocPrint(a, "{d}", .{s.m}) },
                .{ .label = "Dimension of Polynomial Space", .value = try std.fmt.allocPrint(a, "{d}", .{mdim + p}) },
            }, 4, 2, 0);
            // LOGNLAMBDA= wins over LAMBDA=; LAMBDA= values are listed on the
            // log10(n lambda) scale in the order given (SAS 15.4 reference run).
            var grid = s.lognl;
            if (grid.len == 0 and s.lambda.len > 0) {
                const lv = try a.alloc(f64, s.lambda.len);
                for (s.lambda, lv) |l0, *v| v.* = std.math.log10(nf * l0);
                grid = lv;
            }
            if (grid.len > 0) {
                var bi: usize = 0;
                const vals = try a.alloc(f64, grid.len);
                for (grid, vals, 0..) |l, *v, k| {
                    v.* = stats(b, l).gcv;
                    if (v.* < vals[bi]) bi = k;
                }
                try out.appendSlice(a, "\n\n          GCV Function\n \nlog10(n*Lambda)             GCV\n\n");
                for (grid, vals, 0..) |l, v, k| {
                    const lt = try std.fmt.allocPrint(a, "{d:.6}", .{l});
                    const vt = try std.fmt.allocPrint(a, "{d:.6}", .{v});
                    try pad(a, out, 15 -| lt.len);
                    try out.appendSlice(a, lt);
                    try pad(a, out, 16 -| vt.len);
                    try out.appendSlice(a, vt);
                    try out.appendSlice(a, if (k == bi) "*\n" else " \n");
                }
                try out.appendSlice(a, "\nNote: * indicates minimum GCV value.\n");
            }
            const f4 = struct {
                fn f(al: A, v: f64) ![]const u8 {
                    return std.fmt.allocPrint(al, "{d:.4}", .{v});
                }
            }.f;
            try table(a, out, &.{ "Summary Statistics", "of Final Estimation" }, &.{
                .{ .label = "log10(n*Lambda)", .value = try f4(a, lfin) },
                .{ .label = "Smoothing Penalty", .value = try f4(a, st.penalty) },
                .{ .label = "Residual SS", .value = try f4(a, st.rss) },
                .{ .label = "Tr(I-A)", .value = try f4(a, st.tr) },
                .{ .label = "Model DF", .value = try f4(a, nf - st.tr) },
                .{ .label = "Standard Deviation", .value = try f4(a, sigma) },
                .{ .label = "GCV", .value = try f4(a, st.gcv) },
            }, 9, 2, 7);
            if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);

            if (o != null) {
                // The first expanded copy of each kept observation carries its fit.
                const first = try a.alloc(usize, g.keep.len);
                var k: usize = g.owner.len;
                while (k > 0) {
                    k -= 1;
                    first[g.owner[k]] = k;
                }
                var kq: usize = 0;
                const add = struct {
                    fn f(vals: [][]const f64, slot: *usize, ndeps: usize, di_: usize, arr: []f64) void {
                        vals[slot.* * ndeps + di_] = arr;
                        slot.* += 1;
                    }
                }.f;
                const pr = try a.alloc(f64, g.keep.len);
                const sd = try a.alloc(f64, g.keep.len);
                const rs = try a.alloc(f64, g.keep.len);
                const lo = try a.alloc(f64, g.keep.len);
                const up = try a.alloc(f64, g.keep.len);
                const ad = try a.alloc(f64, g.keep.len);
                for (g.keep, 0..) |r, q| {
                    const e = first[q];
                    const se = sigma * @sqrt(@max(fit.adiag[e], 0));
                    pr[q] = fit.f[e];
                    sd[q] = se;
                    rs[q] = slice.rows[r][dep].num - fit.f[e];
                    lo[q] = fit.f[e] - z * se;
                    up[q] = fit.f[e] + z * se;
                    ad[q] = fit.adiag[e];
                }
                if (s.pred) add(fitted_vals, &kq, nd, di, pr);
                if (s.std) add(fitted_vals, &kq, nd, di, sd);
                if (s.resid) add(fitted_vals, &kq, nd, di, rs);
                if (s.lclm) add(fitted_vals, &kq, nd, di, lo);
                if (s.uclm) add(fitted_vals, &kq, nd, di, up);
                if (s.adiag) add(fitted_vals, &kq, nd, di, ad);
            }
        }
        if (o) |ds| if (ran) {
            // Missing values make OUTPUT a gap above, so every dependent keeps
            // the same observations.
            const keep = fits[si * nd].keep;
            for (keep, 0..) |r, q| {
                const vals = try a.alloc(Value, ds.columns.items.len);
                @memcpy(vals[0..cols.len], slice.rows[r]);
                for (fitted_vals, 0..) |arr, c| vals[cols.len + c] = .{ .num = arr[q] };
                try ds.appendRow(vals);
            }
        };
    }
    if (o) |ds| {
        const member = s.out.?;
        try cx.lib.put(member, ds);
        const upper = try std.ascii.allocUpperString(a, member);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, ds.rows.items.len, ds.columns.items.len });
    }
}

/// A new listing page: SAS 15.4 reference runs separate pages by one blank
/// line, which the procedure-title line supplies when no TITLE is active.
fn pageStart(cx: proc.ProcCtx, out: *Out) !void {
    const titles = cx.listing_titles orelse return;
    for (titles.titles) |ln| if (ln != null) {
        try out.append(cx.arena, '\n');
        break;
    };
    try titles.emitTitles(cx.arena, out);
}

fn byLine(a: A, out: *Out, s: Spec, slice: proc.BySlice) !void {
    if (s.by_cols.len == 0) return;
    var line: Out = .empty;
    try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
    if (line.items.len > 0) {
        try out.append(a, '\n');
        try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
    }
}

test {
    _ = @import("tpspline_tests.zig");
}

