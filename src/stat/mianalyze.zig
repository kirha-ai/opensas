//! PROC MIANALYZE declarations, input data set forms, variable roles and the
//! default univariate listing, SAS/STAT 15.4 physical pp.6560-6571 (syntax and
//! input data sets) with the combining rules of "Combining Inferences from
//! Imputed Data Sets" in the same chapter. Everything whose displayed result
//! has not been proven against the SAS reference listing or an independent
//! derivation is a D-009 gap (rc 2) raised before any listing text is
//! produced, so a partial page can never be taken for a full analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const inference = @import("univ_inference.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    /// Display name of the DATA= data set, LIBREF.MEMBER in upper case.
    data_name: []const u8 = "",
    /// MODELEFFECTS columns, in statement order.
    effects: []const usize = &.{},
    /// STDERR columns, positionally matching `effects`; empty for the
    /// specially structured (EST) form.
    stderr: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    alpha: f64 = 0.05,
    /// Complete-data degrees of freedom; null leaves the DF unadjusted.
    edf: ?f64 = null,
    /// THETA0=/MU0= numbers: none (all 0), one (all effects) or one per effect.
    theta0: []const f64 = &.{},
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC MIANALYZE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC MIANALYZE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC MIANALYZE: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC MIANALYZE statement options (Table 83.1) owned by later
/// MIANALYZE tickets: the PARMS= family of input data sets and the
/// covariance/multivariate displays.
const later_options = [_][]const u8{ "parms", "parminfo", "covb", "xpxi", "wcov", "bcov", "tcov", "mult", "multivariate" };
const later_statements = [_][]const u8{ "class", "test" };

/// One optionally signed numeric literal at `i.*`.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus)) {
        sign = -1;
        i.* += 1;
    } else if (at(t, i.*, .plus)) i.* += 1;
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * x;
}

fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, tok: lex.Token, role: []const u8) diag.Error!usize {
    const c = ds.indexOf(tok.text) orelse return cx.diags.fail(error.ParseError, tok.line, "Variable {s} not found.", .{tok.text});
    if (ds.columns.items[c].type != .num) return user(cx, tok.line, "{s} variable {s} must be numeric", .{ role, tok.text });
    return c;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var theta: std.ArrayList(f64) = .empty;
    var theta_seen = false;
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
            const line = t[i].line;
            i += 2;
            s.alpha = try number(cx, t, &i);
            if (!(s.alpha > 0 and s.alpha < 1)) return user(cx, line, "ALPHA= must be between 0 and 1", .{});
        } else if (eq(word, "edf") and at(t, i + 1, .eq)) {
            const line = t[i].line;
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0)) return user(cx, line, "EDF= must be positive", .{});
            s.edf = x;
        } else if ((eq(word, "theta0") or eq(word, "mu0")) and at(t, i + 1, .eq)) {
            if (theta_seen) return invalid(cx, t, i);
            theta_seen = true;
            i += 2;
            try theta.append(cx.arena, try number(cx, t, &i));
            while (at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus) or at(t, i, .comma)) {
                if (at(t, i, .comma)) {
                    i += 1;
                    continue;
                }
                try theta.append(cx.arena, try number(cx, t, &i));
            }
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    s.theta0 = theta.items;
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return user(cx, 0, "input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    const shown = name orelse raw.name;
    s.data_name = try std.ascii.allocUpperString(cx.arena, if (std.mem.indexOfScalar(u8, shown, '.') != null) shown else try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{shown}));

    var bys: by.Statements = .{};
    var effects_seen = false;
    var stderr_seen = false;
    var effects: std.ArrayList(usize) = .empty;
    var errors: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "modeleffects")) {
            if (effects_seen) return gap(cx, t[i].line, "duplicate MODELEFFECTS statement policy is not verified", .{});
            effects_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                // Crossed and nested effects need CLASS variables, which are
                // only valid with a PARMS= data set (physical p.6564).
                if (at(t, j, .star) or at(t, j, .lparen) or at(t, j, .rparen) or at(t, j, .pipe)) return gap(cx, t[j].line, "crossed or nested MODELEFFECTS effects are not implemented", .{});
                if (!at(t, j, .name)) return invalid(cx, t, j);
                const c = try numericColumn(cx, ds, t[j], "MODELEFFECTS");
                if (std.mem.indexOfScalar(usize, effects.items, c) != null) return gap(cx, t[j].line, "repeated MODELEFFECTS variable policy is not verified", .{});
                try effects.append(cx.arena, c);
            }
        } else if (kw(t, i, "stderr")) {
            if (stderr_seen) return gap(cx, t[i].line, "duplicate STDERR statement policy is not verified", .{});
            stderr_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                try errors.append(cx.arena, try numericColumn(cx, ds, t[j], "STDERR"));
            }
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!effects_seen) return user(cx, 0, "MODELEFFECTS statement required", .{});
    // The standard errors correspond positionally to the effects (p.6566).
    if (stderr_seen and errors.items.len != effects.items.len) return user(cx, 0, "the STDERR statement lists {d} variables for {d} MODELEFFECTS effects", .{ errors.items.len, effects.items.len });
    if (s.theta0.len > 1 and s.theta0.len != effects.items.len) return gap(cx, 0, "a THETA0= list whose length differs from the number of effects is not verified", .{});
    s.effects = effects.items;
    s.stderr = errors.items;
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Combined inference for one parameter.
pub const Combined = struct {
    estimate: f64,
    between: f64,
    within: f64,
    total: f64,
    df: f64,
    /// Relative increase in variance due to nonresponse.
    increase: f64,
    /// Fraction of missing information.
    fraction: f64,
    efficiency: f64,
};

/// Rubin's combining rules for `m` point estimates `q` with variance
/// estimates `u` (chapter 83, "Combining Inferences from Imputed Data Sets"):
///   Qbar = mean(q), W = mean(u), B = sum((q-Qbar)^2)/(m-1),
///   T = W + (1+1/m)B, r = (1+1/m)B/W, v_m = (m-1)(1+1/r)^2,
///   lambda = (r + 2/(v_m+3))/(r+1), RE = 1/(1+lambda/m).
/// With complete-data degrees of freedom v0 (EDF=) the Barnard-Rubin
/// adjustment replaces v_m by 1/(1/v_m + 1/v_obs),
///   v_obs = (1-gamma) v0 (v0+1)/(v0+3), gamma = (1+1/m)B/T.
/// The fraction of missing information keeps the unadjusted v_m.
pub fn combine(q: []const f64, u: []const f64, edf: ?f64) Combined {
    const m: f64 = @floatFromInt(q.len);
    var qbar: f64 = 0;
    var within: f64 = 0;
    for (q, u) |x, v| {
        qbar += x;
        within += v;
    }
    qbar /= m;
    within /= m;
    var between: f64 = 0;
    for (q) |x| between += (x - qbar) * (x - qbar);
    between /= m - 1;
    return derive(m, qbar, within, between, edf);
}

/// The quantities that follow from m, Qbar, W and B alone.
pub fn derive(m: f64, qbar: f64, within: f64, between: f64, edf: ?f64) Combined {
    const inflated = (1 + 1 / m) * between;
    const total = within + inflated;
    const r = inflated / within;
    const vm = (m - 1) * (1 + 1 / r) * (1 + 1 / r);
    var df = vm;
    if (edf) |v0| {
        const vobs = (1 - inflated / total) * v0 * (v0 + 1) / (v0 + 3);
        df = 1 / (1 / vm + 1 / vobs);
    }
    const lambda = (r + 2 / (vm + 3)) / (r + 1);
    return .{ .estimate = qbar, .between = between, .within = within, .total = total, .df = df, .increase = r, .fraction = lambda, .efficiency = 1 / (1 + lambda / m) };
}

pub const Parameter = struct {
    name: []const u8,
    c: Combined,
    minimum: f64,
    maximum: f64,
    theta0: f64,
};
pub const Analysis = struct {
    imputations: usize,
    parameters: []const Parameter,
    /// First observation of the BY group (null without BY).
    rep: ?[]const Value = null,
};

const parm_types = [_][]const u8{ "parm", "parms", "ols", "final" };
const cov_types = [_][]const u8{ "cov", "covb" };
const moment_types = [_][]const u8{ "mean", "n", "std", "corr" };

fn charValue(v: Value) []const u8 {
    return switch (v) {
        .str => |x| std.mem.trim(u8, x, " "),
        else => "",
    };
}
fn num(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        else => std.math.nan(f64),
    };
}

/// Point estimates and their variances per imputation, one slice per effect.
const Estimates = struct { q: [][]f64, u: [][]f64 };

/// DATA= with a STDERR statement (p.6567): every observation is one
/// imputation holding the estimates and their standard errors.
fn readPlain(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Estimates {
    const k = s.effects.len;
    const e: Estimates = .{ .q = try cx.arena.alloc([]f64, k), .u = try cx.arena.alloc([]f64, k) };
    for (0..k) |j| {
        e.q[j] = try cx.arena.alloc(f64, rows.len);
        e.u[j] = try cx.arena.alloc(f64, rows.len);
        for (rows, 0..) |row, r| {
            const estimate = num(row[s.effects[j]]);
            const se = num(row[s.stderr[j]]);
            if (std.math.isNan(estimate) or std.math.isNan(se)) return gap(cx, 0, "the result for a missing estimate or standard error is not verified", .{});
            if (se < 0) return user(cx, 0, "negative standard error for {s} in observation {d}", .{ s.input.ds.columns.items[s.effects[j]].name, r + 1 });
            e.q[j][r] = estimate;
            e.u[j][r] = se * se;
        }
    }
    return e;
}

/// Specially structured DATA= data set of the EST form (p.6567): per
/// _Imputation_, estimates on the _TYPE_ PARM/PARMS/OLS/FINAL observation and
/// each variance on the diagonal of the _TYPE_ COV/COVB observations, which
/// are identified by _NAME_.
/// ponytail: opensas data sets carry no TYPE= attribute, so the EST form is
/// recognised by the absence of a STDERR statement together with a character
/// _TYPE_ variable; SAS decides from the data set type.
fn readStructured(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Estimates {
    const ds = s.input.ds;
    const type_c = ds.indexOf("_TYPE_") orelse return user(cx, 0, "a STDERR statement is required when the DATA= data set is not a TYPE=EST, COV or CORR data set", .{});
    if (ds.columns.items[type_c].type != .char) return user(cx, 0, "_TYPE_ must be a character variable", .{});
    const imp_c = ds.indexOf("_Imputation_") orelse return user(cx, 0, "the variable _Imputation_ is required in a TYPE=EST, COV or CORR data set", .{});
    if (ds.columns.items[imp_c].type != .num) return user(cx, 0, "_Imputation_ must be a numeric variable", .{});
    const name_c = ds.indexOf("_NAME_");
    const k = s.effects.len;
    var ids: std.ArrayList(f64) = .empty;
    var q: std.ArrayList([]?f64) = .empty;
    var u: std.ArrayList([]?f64) = .empty;
    for (rows) |row| {
        const kind = charValue(row[type_c]);
        if (oneOf(kind, &moment_types)) return gap(cx, 0, "TYPE=COV and TYPE=CORR input data sets (_TYPE_={s}) are not implemented", .{kind});
        const is_parm = oneOf(kind, &parm_types);
        const is_cov = oneOf(kind, &cov_types);
        if (!is_parm and !is_cov) continue;
        const id = num(row[imp_c]);
        if (std.math.isNan(id)) return gap(cx, 0, "the result for a missing _Imputation_ value is not verified", .{});
        const slot = std.mem.indexOfScalar(f64, ids.items, id) orelse blk: {
            try ids.append(cx.arena, id);
            const qs = try cx.arena.alloc(?f64, k);
            const us = try cx.arena.alloc(?f64, k);
            @memset(qs, null);
            @memset(us, null);
            try q.append(cx.arena, qs);
            try u.append(cx.arena, us);
            break :blk ids.items.len - 1;
        };
        if (is_parm) {
            for (s.effects, 0..) |c, j| {
                if (q.items[slot][j] != null) return user(cx, 0, "more than one parameter estimate observation for _Imputation_={d}", .{id});
                q.items[slot][j] = num(row[c]);
            }
        } else {
            const nc = name_c orelse return user(cx, 0, "the variable _NAME_ is required to identify covariance observations", .{});
            const label = charValue(row[nc]);
            for (s.effects, 0..) |c, j| if (eq(label, ds.columns.items[c].name)) {
                if (u.items[slot][j] != null) return user(cx, 0, "more than one covariance observation for {s} in _Imputation_={d}", .{ label, id });
                u.items[slot][j] = num(row[c]);
            };
        }
    }
    const m = ids.items.len;
    const e: Estimates = .{ .q = try cx.arena.alloc([]f64, k), .u = try cx.arena.alloc([]f64, k) };
    for (0..k) |j| {
        e.q[j] = try cx.arena.alloc(f64, m);
        e.u[j] = try cx.arena.alloc(f64, m);
        const effect = ds.columns.items[s.effects[j]].name;
        for (0..m) |r| {
            const estimate = q.items[r][j] orelse return user(cx, 0, "no parameter estimates for _Imputation_={d}", .{ids.items[r]});
            const variance = u.items[r][j] orelse return user(cx, 0, "no covariance observation for {s} in _Imputation_={d}", .{ effect, ids.items[r] });
            if (std.math.isNan(estimate) or std.math.isNan(variance)) return gap(cx, 0, "the result for a missing estimate or variance is not verified", .{});
            if (variance < 0) return user(cx, 0, "negative variance for {s} in _Imputation_={d}", .{ effect, ids.items[r] });
            e.q[j][r] = estimate;
            e.u[j][r] = variance;
        }
    }
    return e;
}

fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Analysis {
    const e = if (s.stderr.len > 0) try readPlain(cx, s, rows) else try readStructured(cx, s, rows);
    const m = if (e.q.len > 0) e.q[0].len else 0;
    // ponytail: the SAS message text for unusable input is not in the
    // reference; the step fails as a data error (rc 1).
    if (m == 0) return user(cx, 0, "no imputations were read from the input data set", .{});
    if (m == 1) return gap(cx, 0, "the result for a single imputation is not verified", .{});
    const parameters = try cx.arena.alloc(Parameter, s.effects.len);
    for (parameters, 0..) |*p, j| {
        const c = combine(e.q[j], e.u[j], s.edf);
        var lo = e.q[j][0];
        var hi = lo;
        for (e.q[j]) |x| {
            lo = @min(lo, x);
            hi = @max(hi, x);
        }
        p.* = .{ .name = s.input.ds.columns.items[s.effects[j]].name, .c = c, .minimum = lo, .maximum = hi, .theta0 = if (s.theta0.len == 0) 0 else if (s.theta0.len == 1) s.theta0[0] else s.theta0[j] };
    }
    return .{ .imputations = m, .parameters = parameters };
}

/// One analysis per BY group; raises the documented data errors.
pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Analysis {
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try cx.arena.alloc(Analysis, slices.len);
    for (slices, groups) |slice, *group| {
        group.* = try analyze(cx, s, slice.rows);
        group.rep = slice.rep;
    }
    return groups;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn padRight(a: A, out: *Out, s: []const u8, width: usize) !void {
    if (s.len < width) try out.appendNTimes(a, ' ', width - s.len);
    try out.appendSlice(a, s);
}
fn padLeft(a: A, out: *Out, s: []const u8, width: usize) !void {
    try out.appendSlice(a, s);
    if (s.len < width) try out.appendNTimes(a, ' ', width - s.len);
}
fn centered(a: A, out: *Out, s: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| s.len) / 2);
    try out.appendSlice(a, s);
    try out.append(a, '\n');
}
/// A 12.6 cell right-justified in `width`.
fn cell6(cx: proc.ProcCtx, out: *Out, x: f64, width: usize) diag.Error!void {
    const s = try fixed(cx.arena, x, 6);
    if (s.len > 12) return gap(cx, 0, "display of values that overflow the 12.6 listing columns is not verified", .{});
    try padRight(cx.arena, out, s, width);
}
fn integerDigits(x: f64) usize {
    var digits: usize = 0;
    var v = @floor(@abs(x));
    while (v >= 1) : (v /= 10) digits += 1;
    return digits;
}
/// Decimals of one confidence-limit column. The reference shows a column-wide
/// choice in an 8-character field: the lower limits (largest magnitude 73.2)
/// print with 5 decimals and the upper limits (largest 112.2) with 4.
/// ponytail: two rules explain the reference, "largest magnitude keeps seven
/// significant digits" and "most decimals with which every value fits in 8
/// characters". Only columns where both agree on 4 or 5 decimals are
/// rendered; anything else stays a gap until a reference pins the rule.
fn limitDecimals(cx: proc.ProcCtx, values: []const f64) diag.Error!usize {
    var largest: f64 = 0;
    for (values) |x| largest = @max(largest, @abs(x));
    const by_digits = 7 -| integerDigits(largest);
    var by_fit: usize = 0;
    var d: usize = 7;
    while (d > 0) : (d -= 1) {
        var fits = true;
        for (values) |x| fits = fits and (try fixed(cx.arena, x, d)).len <= 8;
        if (fits) {
            by_fit = d;
            break;
        }
    }
    if (by_digits != by_fit or (by_fit != 4 and by_fit != 5)) return gap(cx, 0, "confidence limit display outside the verified 4- and 5-decimal columns is not verified", .{});
    return by_fit;
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, an: Analysis) diag.Error!void {
    const a = cx.arena;
    // Execution boundary: only the listing shape proven against the SAS
    // reference is produced.
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group listing layout is not verified", .{});
    const percent = 100 * (1 - s.alpha);
    if (@abs(percent - @round(percent)) > 1e-9 or percent < 10) return gap(cx, 0, "confidence limit heading for ALPHA={d} is not verified", .{s.alpha});
    const count = an.parameters.len;
    const ses = try a.alloc(f64, count);
    const lower = try a.alloc(f64, count);
    const upper = try a.alloc(f64, count);
    for (an.parameters, 0..) |p, j| {
        // ponytail: the reference pins the 9-character Parameter column only.
        if (p.name.len > 9) return gap(cx, 0, "listing columns for parameter names longer than 9 characters are not verified", .{});
        if (!(p.c.between > 0)) return gap(cx, 0, "the result for a zero between-imputation variance is not verified", .{});
        if (!(p.c.within > 0)) return gap(cx, 0, "the result for a zero within-imputation variance is not verified", .{});
        ses[j] = @sqrt(p.c.total);
        const margin = -inference.tQuantile(s.alpha / 2, p.c.df) * ses[j];
        lower[j] = p.c.estimate - margin;
        upper[j] = p.c.estimate + margin;
    }
    const lower_decimals = try limitDecimals(cx, lower);
    const upper_decimals = try limitDecimals(cx, upper);

    var body: Out = .empty;
    try body.appendSlice(a, "\nThe MIANALYZE Procedure\n\n");
    const m_text = try std.fmt.allocPrint(a, "{d}", .{an.imputations});
    const value_width = @max(s.data_name.len, m_text.len) + 1;
    try centered(a, &body, "Model Information", 26 + value_width);
    try body.appendSlice(a, "\nData Set                  ");
    try padLeft(a, &body, s.data_name, value_width);
    try body.appendSlice(a, "\nNumber of Imputations     ");
    try padLeft(a, &body, m_text, value_width);
    try body.appendSlice(a, "\n\n\n");

    try centered(a, &body, try std.fmt.allocPrint(a, "Variance Information ({d} Imputations)", .{an.imputations}), 109);
    try body.appendSlice(a, " \n" ++
        "                                                                       Relative       Fraction\n" ++
        "             -----------------Variance-----------------                Increase        Missing       Relative\n" ++
        "Parameter         Between         Within          Total       DF    in Variance    Information     Efficiency\n\n");
    for (an.parameters) |p| {
        try padLeft(a, &body, p.name, 9);
        try cell6(cx, &body, p.c.between, 16);
        try cell6(cx, &body, p.c.within, 15);
        try cell6(cx, &body, p.c.total, 15);
        try padRight(a, &body, std.mem.trim(u8, try format.bestNumW(a, p.c.df, 6), " "), 9);
        try cell6(cx, &body, p.c.increase, 15);
        try cell6(cx, &body, p.c.fraction, 15);
        try cell6(cx, &body, p.c.efficiency, 15);
        try body.append(a, '\n');
    }
    try body.appendSlice(a, "\n\n");
    try centered(a, &body, try std.fmt.allocPrint(a, "Parameter Estimates ({d} Imputations)", .{an.imputations}), 150);
    try body.appendSlice(a, " \n" ++
        "                                                                                                                                  t for H0:\n");
    try body.print(a, "Parameter        Estimate      Std Error    {d}% Confidence Limits        DF        Minimum        Maximum         Theta0   Parameter=Theta0   Pr > |t|\n\n", .{@as(u32, @intFromFloat(@round(percent)))});
    for (an.parameters, 0..) |p, j| {
        const t_value = (p.c.estimate - p.theta0) / ses[j];
        const probability = inference.tProbability(t_value, p.c.df);
        try padLeft(a, &body, p.name, 9);
        try cell6(cx, &body, p.c.estimate, 16);
        try cell6(cx, &body, ses[j], 15);
        try padRight(a, &body, try fixed(a, lower[j], lower_decimals), 13);
        try padRight(a, &body, try fixed(a, upper[j], upper_decimals), 13);
        try padRight(a, &body, std.mem.trim(u8, try format.bestNumW(a, p.c.df, 6), " "), 9);
        try cell6(cx, &body, p.minimum, 15);
        try cell6(cx, &body, p.maximum, 15);
        try padRight(a, &body, std.mem.trim(u8, try format.bestNumW(a, p.theta0, 12), " "), 15);
        const t_text = try fixed(a, t_value, 2);
        if (t_text.len > 7) return gap(cx, 0, "display of t statistics that overflow the 7.2 column is not verified", .{});
        try padRight(a, &body, t_text, 19);
        try padRight(a, &body, if (probability < 0.0001) "<.0001" else try fixed(a, probability, 4), 11);
        try body.append(a, '\n');
    }
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const groups = try plan(cx, s);
    if (groups.len == 0) return user(cx, 0, "no imputations were read from the input data set", .{});
    for (groups) |group| try render(cx, out, s, group);
}

test {
    _ = @import("mianalyze_tests.zig");
}
