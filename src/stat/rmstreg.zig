//! PROC RMSTREG declarations, variable roles, observation selection and the
//! default pseudovalue-regression listing, SAS/STAT 15.4 Chapter 106
//! (physical pp.8735-8737 statement syntax, 8737 BY, 8742 FREQ, 8757 missing
//! values; the estimator itself pp.8749-8754). The restricted mean survival
//! time RMST(tau) is the area under the Kaplan-Meier curve up to tau; the
//! jackknife pseudovalues n*RMST - (n-1)*RMST(-i) are regressed with the
//! independence estimating equations (identity link: V=1; log link: V=mu)
//! and a sandwich variance I0^-1 I1 I0^-1. Everything whose displayed
//! result has not been proven against a SAS reference listing is a D-009 gap
//! (rc 2) raised before any listing text of the step is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fns = @import("../functions.zig");
const by = @import("by_groups.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Link = enum { log, linear };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    alpha: f64 = 0.05,
    tau: ?f64 = null,
    noprint: bool = false,
    singular: f64 = 1e-9,
    namelen: usize = 20,
    time: usize = 0,
    censor: ?usize = null,
    censor_values: []const f64 = &.{},
    covariates: []const usize = &.{},
    noint: bool = false,
    link: Link = .log,
    converge: f64 = 1e-4,
    maxiter: usize = 50,
    frequency: ?usize = null,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC RMSTREG: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC RMSTREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
/// A signed numeric literal at `i.*`; advances past it.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus)) {
        sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * x;
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC RMSTREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

/// Statements owned by later RMSTREG tickets.
const later_statements = [_][]const u8{ "class", "estimate", "lsmeans", "lsmestimate", "slice", "store", "test", "effectplot", "output" };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            qualified = null;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "alpha") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
        } else if (eq(word, "tau") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            // SAS 9.4 reference log for TAU=-1.
            if (x < 0) return cx.diags.fail(error.ParseError, t[i - 1].line, "The parameter value {s} is less than the minimum allowed value of 0.", .{try format.bestNum(cx.arena, x)});
            if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: TAU= must be positive", .{});
            s.tau = x;
        } else if ((eq(word, "singular") or eq(word, "epsilon")) and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: SINGULAR= must be between 0 and 1", .{});
            s.singular = x;
        } else if (eq(word, "namelen") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x >= 20 and x <= 200 and x == @trunc(x))) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: NAMELEN= must be an integer between 20 and 200", .{});
            s.namelen = @intFromFloat(x);
        } else if (eq(word, "ithistory")) {
            return gap(cx, t[i].line, "ITHISTORY (iteration history and last gradient) is not implemented", .{});
        } else if (eq(word, "outpv")) {
            return gap(cx, t[i].line, "OUTPV= output data set is not implemented", .{});
        } else if (eq(word, "plots") or eq(word, "plot")) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC RMSTREG: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const upper = try std.ascii.allocUpperString(cx.arena, name orelse raw.name);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{upper}) else upper;
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
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
            // The SAS 9.4 reference (two MODEL statements, no log message)
            // fits the first one.
            if (!model_seen) try model(cx, ds, t, i + 1, end, &s);
            model_seen = true;
        } else if (kw(t, i, "freq") or kw(t, i, "frequency")) {
            if (end != i + 2) return invalid(cx, t, i + 2);
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (kw(t, i, "by")) {
            // Only the last BY statement is used (p.8737).
            bys = .{};
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "weight")) {
            return invalid(cx, t, i);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC RMSTREG: MODEL statement required", .{});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// `MODEL time <*censor(list)> = <effects> </ options>` (p.8733).
fn model(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!void {
    var i = start;
    if (at(t, i, .lparen)) return gap(cx, t[i].line, "counting-process or interval MODEL responses are not implemented", .{});
    s.time = try numericColumn(cx, ds, t, i, "time");
    i += 1;
    if (at(t, i, .star)) {
        s.censor = try numericColumn(cx, ds, t, i + 1, "censoring");
        i += 2;
        if (!at(t, i, .lparen)) return invalid(cx, t, i);
        i += 1;
        var values: std.ArrayList(f64) = .empty;
        while (i < end and !at(t, i, .rparen)) {
            if (at(t, i, .comma)) {
                i += 1;
                continue;
            }
            if (kw(t, i, "to") or kw(t, i, "by")) return gap(cx, t[i].line, "censoring value ranges are not implemented", .{});
            try values.append(cx.arena, try number(cx, t, &i));
        }
        if (!at(t, i, .rparen) or values.items.len == 0) return invalid(cx, t, i);
        s.censor_values = values.items;
        i += 1;
    }
    if (!at(t, i, .eq)) return invalid(cx, t, i);
    i += 1;
    var covs: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) : (i += 1) {
        if (!at(t, i, .name)) return gap(cx, lineOf(t, i), "MODEL effect syntax {s} (interactions, nesting, lists) is not implemented", .{t[i].text});
        if (at(t, i + 1, .star) or at(t, i + 1, .lparen) or at(t, i + 1, .pipe) or at(t, i + 1, .minus) or at(t, i + 1, .at) or at(t, i + 1, .dollar)) return gap(cx, t[i].line, "MODEL effect syntax after {s} (interactions, nesting, lists) is not implemented", .{t[i].text});
        const c = try column(cx, ds, t, i);
        if (ds.columns.items[c].type != .num) return gap(cx, t[i].line, "character explanatory variable {s} needs the CLASS statement, which is not implemented", .{t[i].text});
        if (std.mem.indexOfScalar(usize, covs.items, c) != null) return gap(cx, t[i].line, "repeated MODEL effect policy is not verified", .{});
        try covs.append(cx.arena, c);
    }
    s.covariates = covs.items;
    if (at(t, i, .slash)) i += 1;
    while (i < end) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "noint")) {
            s.noint = true;
            i += 1;
        } else if (eq(word, "link") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (eq(v, "log")) s.link = .log else if (oneOf(v, &.{ "identity", "id", "linear" })) s.link = .linear else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "method") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (eq(v, "ipcw")) return gap(cx, t[i].line, "METHOD=IPCW is not implemented", .{});
            if (!eq(v, "pv")) return invalid(cx, t, i + 2);
            if (at(t, i + 3, .lparen)) return gap(cx, t[i].line, "METHOD= suboptions are not implemented", .{});
            i += 3;
        } else if (eq(word, "alpha") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
        } else if (eq(word, "converge") and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: CONVERGE= must be positive", .{});
            s.converge = x;
        } else if ((eq(word, "maxiter") or eq(word, "maxit")) and valued) {
            i += 2;
            const x = try number(cx, t, &i);
            if (!(x >= 0 and x == @trunc(x) and x < 1e6)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC RMSTREG: MAXITER= must be a nonnegative integer", .{});
            s.maxiter = @intFromFloat(x);
        } else if (oneOf(word, &.{ "convh", "corrb", "covb", "nofit" })) {
            return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
}

/// One used observation: FREQ count (truncated) and the design row.
pub const Unit = struct { time: f64, event: bool, freq: f64, x: []const f64 };

pub const Selected = struct {
    units: []Unit,
    read: usize,
    freq_read: f64,
};

/// Observation selection, p.8757 and FREQ p.8742: a missing explanatory
/// value, a missing or negative time, a missing censoring value and a missing
/// or (after truncation) below-one frequency each drop the observation. The
/// SAS 9.4 reference counts FREQ totals read over the observations whose
/// frequency and explanatory variables are valid (a missing response still
/// counts as read).
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    const p = s.covariates.len + @intFromBool(!s.noint);
    var units: std.ArrayList(Unit) = .empty;
    var freq_read: f64 = 0;
    row_loop: for (rows) |row| {
        var f: f64 = 1;
        if (s.frequency) |c| {
            if (selection.missing(row[c])) continue;
            f = @trunc(row[c].num);
            if (!(f >= 1)) continue;
        }
        for (s.covariates) |c| if (selection.missing(row[c])) continue :row_loop;
        freq_read += f;
        if (selection.missing(row[s.time]) or row[s.time].num < 0) continue;
        var event = true;
        if (s.censor) |c| {
            if (selection.missing(row[c])) continue;
            event = std.mem.indexOfScalar(f64, s.censor_values, row[c].num) == null;
        }
        const x = try a.alloc(f64, p);
        var k: usize = 0;
        if (!s.noint) {
            x[0] = 1;
            k = 1;
        }
        for (s.covariates) |c| {
            x[k] = row[c].num;
            k += 1;
        }
        try units.append(a, .{ .time = row[s.time].num, .event = event, .freq = f, .x = x });
    }
    return .{ .units = units.items, .read = rows.len, .freq_read = freq_read };
}

fn unitLess(_: void, x: Unit, y: Unit) bool {
    return x.time < y.time;
}

/// Kaplan-Meier RMST(tau) (p.8749) over `sorted` (ascending time) with one
/// unit of observation `drop` removed: sum of S(t_{i-1})(t_i - t_{i-1}) over
/// the event times below tau plus S(t_N)(tau - t_N).
pub fn rmst(sorted: []const Unit, tau: f64, drop: ?usize) f64 {
    var at_risk: f64 = 0;
    for (sorted) |u| at_risk += u.freq;
    if (drop != null) at_risk -= 1;
    var s: f64 = 1;
    var previous: f64 = 0;
    var area: f64 = 0;
    var i: usize = 0;
    while (i < sorted.len) {
        const time = sorted[i].time;
        var d: f64 = 0;
        var c: f64 = 0;
        var j = i;
        while (j < sorted.len and sorted[j].time == time) : (j += 1) {
            const f = sorted[j].freq - @as(f64, if (drop != null and drop.? == j) 1 else 0);
            if (sorted[j].event) d += f else c += f;
        }
        if (time >= tau) break;
        if (d > 0) {
            area += s * (time - previous);
            s *= 1 - d / at_risk;
            previous = time;
        }
        at_risk -= d + c;
        i = j;
    }
    return area + s * (tau - previous);
}

/// Jackknife pseudovalues n*RMST - (n-1)*RMST(-i), one per used observation
/// (every unit of an observation shares it), in `sorted` order.
pub fn pseudovalues(a: A, sorted: []const Unit, tau: f64) ![]f64 {
    var n: f64 = 0;
    for (sorted) |u| n += u.freq;
    const full = rmst(sorted, tau, null);
    const pv = try a.alloc(f64, sorted.len);
    for (pv, 0..) |*v, k| v.* = n * full - (n - 1) * rmst(sorted, tau, k);
    return pv;
}

pub const Fit = struct {
    beta: []f64,
    cov: []f64,
    converged: bool,
    iterations: usize,
};
pub const FitError = error{ OutOfMemory, Singular, Nonpositive };

/// Solves `m` (p x p, row major) x = b in place by Gauss-Jordan elimination
/// with partial pivoting; a pivot below `tol` times its original diagonal is
/// a singularity. Returns the inverse in `inv`.
fn invert(a: A, m: []const f64, p: usize, tol: f64) FitError![]f64 {
    const w = try a.dupe(f64, m);
    const inv = try a.alloc(f64, p * p);
    @memset(inv, 0);
    for (0..p) |k| inv[k * p + k] = 1;
    for (0..p) |c| {
        var best = c;
        for (c + 1..p) |r| if (@abs(w[r * p + c]) > @abs(w[best * p + c])) {
            best = r;
        };
        if (!(@abs(w[best * p + c]) > tol * @abs(m[c * p + c])) or w[best * p + c] == 0) return error.Singular;
        if (best != c) for (0..p) |j| {
            std.mem.swap(f64, &w[c * p + j], &w[best * p + j]);
            std.mem.swap(f64, &inv[c * p + j], &inv[best * p + j]);
        };
        const piv = w[c * p + c];
        for (0..p) |j| {
            w[c * p + j] /= piv;
            inv[c * p + j] /= piv;
        }
        for (0..p) |r| if (r != c) {
            const f = w[r * p + c];
            if (f != 0) for (0..p) |j| {
                w[r * p + j] -= f * w[c * p + j];
                inv[r * p + j] -= f * inv[c * p + j];
            };
        };
    }
    return inv;
}

/// Independence estimating equations on pseudovalues `y`, FREQ-weighted,
/// solved by Fisher scoring (exact in one step for the identity link), with
/// the sandwich covariance I0^-1 I1 I0^-1 (pp.8753-8754).
pub fn fit(a: A, units: []const Unit, y: []const f64, p: usize, intercept: bool, link: Link, converge: f64, maxiter: usize, tol: f64) FitError!Fit {
    const beta = try a.alloc(f64, p);
    @memset(beta, 0);
    const h = try a.alloc(f64, p * p);
    const g = try a.alloc(f64, p);
    var converged = link == .linear;
    var iterations: usize = 0;
    if (link == .log) {
        var total: f64 = 0;
        var n: f64 = 0;
        for (units, y) |u, v| {
            total += u.freq * v;
            n += u.freq;
        }
        if (!(total > 0)) return error.Nonpositive;
        // ponytail: the start is the intercept-only solution when there is an
        // intercept column; any start reaches the same root of the equations.
        if (intercept) beta[0] = @log(total / n);
    }
    while (true) {
        @memset(h, 0);
        @memset(g, 0);
        for (units, y) |u, v| {
            var eta: f64 = 0;
            for (u.x, beta) |xj, bj| eta += xj * bj;
            const mu = if (link == .log) @exp(eta) else eta;
            const w = if (link == .log) mu else 1;
            for (0..p) |j| {
                g[j] += u.freq * u.x[j] * (v - mu);
                for (0..p) |k| h[j * p + k] += u.freq * w * u.x[j] * u.x[k];
            }
        }
        const inv = try invert(a, h, p, tol);
        if (link == .linear and iterations == 1) break;
        if (link == .log and (converged or iterations >= maxiter)) break;
        var change: f64 = 0;
        for (0..p) |j| {
            var step: f64 = 0;
            for (0..p) |k| step += inv[j * p + k] * g[k];
            const old = beta[j];
            beta[j] += step;
            const diff = if (@abs(old) > 0.08) @abs(step / old) else @abs(step);
            change = @max(change, diff);
        }
        iterations += 1;
        if (link == .log and change < converge) converged = true;
    }
    // Sandwich at the final estimate.
    @memset(h, 0);
    const meat = try a.alloc(f64, p * p);
    @memset(meat, 0);
    for (units, y) |u, v| {
        var eta: f64 = 0;
        for (u.x, beta) |xj, bj| eta += xj * bj;
        const mu = if (link == .log) @exp(eta) else eta;
        const w = if (link == .log) mu else 1;
        for (0..p) |j| for (0..p) |k| {
            h[j * p + k] += u.freq * w * u.x[j] * u.x[k];
            meat[j * p + k] += u.freq * (u.x[j] * (v - mu)) * (u.x[k] * (v - mu));
        };
    }
    const inv = try invert(a, h, p, tol);
    const cov = try a.alloc(f64, p * p);
    for (0..p) |r| for (0..p) |c| {
        var sum: f64 = 0;
        for (0..p) |j| for (0..p) |k| {
            sum += inv[r * p + j] * meat[j * p + k] * inv[k * p + c];
        };
        cov[r * p + c] = sum;
    };
    return .{ .beta = beta, .cov = cov, .converged = converged, .iterations = iterations };
}

/// Upper-tail chi-square probability.
pub fn chiProbability(x: f64, df: f64) f64 {
    return 1 - fns.gammaP(df / 2, x / 2);
}
/// z with P(|Z| <= z) = 1 - alpha, from P(|Z| <= z) = P(1/2, z^2/2).
pub fn zCritical(alpha: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 40;
    for (0..200) |_| {
        const mid = (lo + hi) / 2;
        if (fns.gammaP(0.5, mid * mid / 2) < 1 - alpha) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
    // SAS never prints a negative zero.
    if (text[0] == '-') {
        for (text[1..]) |ch| if (ch != '0' and ch != '.') return text;
        return text[1..];
    }
    return text;
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else fixed(a, p, 4);
}
/// A count as SAS prints it in BEST8: an integer here (FREQ truncates).
fn count(a: A, x: f64) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{@as(i64, @intFromFloat(x))});
}

/// Two-column table with its title centred over the table width.
fn infoTable(a: A, out: *Out, title: ?[]const u8, rows: []const [2][]const u8) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (rows) |r| {
        lw = @max(lw, r[0].len);
        vw = @max(vw, r[1].len);
    }
    const width = lw + 4 + vw;
    if (title) |tt| {
        if (tt.len < width) try out.appendNTimes(a, ' ', (width - tt.len) / 2);
        try out.print(a, "{s}\n\n", .{tt});
    }
    for (rows) |r| {
        try padLeft(a, out, r[0], lw + 4);
        try padRight(a, out, r[1], vw);
        try out.append(a, '\n');
    }
}

const Group = struct { sel: Selected, rep: ?[]const Value };

/// Per-BY-group fit and listing; nothing is written until every group of
/// the step has been checked against the execution boundary.
pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    if (cx.capture) |c| for ([_][]const u8{ "ModelInfo", "NObs", "ConvergenceStatus", "Type3Test", "ParameterEstimates" }) |tbl| {
        if (c.wants(tbl)) return gap(cx, 0, "ODS OUTPUT {s}= is not implemented", .{tbl});
    };
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0 or (slices.len == 1 and slices[0].rows.len == 0)) return gap(cx, 0, "the result for an input data set without observations is not verified", .{});
    const p = s.covariates.len + @intFromBool(!s.noint);
    if (p == 0) return gap(cx, 0, "a model without parameters (NOINT and no effects) is not verified", .{});
    const z = zCritical(s.alpha);
    var body: Out = .empty;
    for (slices) |slice| {
        const sel = try select(a, s, slice.rows);
        if (sel.units.len == 0) {
            // SAS 9.4 reference: the groups before keep their pages.
            try out.appendSlice(a, body.items);
            const err = cx.diags.fail(error.ParseError, 0, "No valid observations due to invalid or missing values in the response, explanatory, or frequency variable.", .{});
            if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, slice.rows[0], s.by_cols);
            return err;
        }
        std.mem.sort(Unit, sel.units, {}, unitLess);
        var events: f64 = 0;
        var used: f64 = 0;
        var last_event: ?f64 = null;
        var largest: f64 = 0;
        for (sel.units) |u| {
            used += u.freq;
            largest = @max(largest, u.time);
            if (u.event) {
                events += u.freq;
                last_event = u.time;
            }
        }
        const tau = s.tau orelse last_event orelse return gap(cx, 0, "the default TAU= without any event time is not verified", .{});
        if (!(tau > 0)) return gap(cx, 0, "a nonpositive default TAU= (largest event time) is not verified", .{});
        if (s.tau != null and tau > largest) try cx.diags.warn(0, "The specified TAU= value is greater than the largest observed time.", .{});
        const y = try pseudovalues(a, sel.units, tau);
        const result = fit(a, sel.units, y, p, !s.noint, s.link, s.converge, s.maxiter, s.singular) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx, 0, "a singular design or Hessian is not verified", .{}),
            error.Nonpositive => return gap(cx, 0, "LINK=LOG with a nonpositive mean pseudovalue is not verified", .{}),
        };
        if (!result.converged) return gap(cx, 0, "the listing for estimates that did not converge (MAXITER= exceeded) is not verified", .{});
        try cx.diags.note(0, "Algorithm converged.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, slice.rows[0], s.by_cols);
        if (s.noprint) continue;

        // Model information.
        // Titles open every page (the CLI passes them; tests do not).
        if (cx.listing_titles) |titles| try titles.emitTitles(a, &body);
        try body.append(a, '\n');
        if (s.by_cols.len > 0) {
            var tmp: Out = .empty;
            try by.appendLine(a, &tmp, ds, slice.rows[0], s.by_cols);
            try body.print(a, "{s}\n\n", .{std.mem.trim(u8, tmp.items, " \n")});
        }
        try body.appendSlice(a, "The RMSTREG Procedure\n\n");
        var info: std.ArrayList([2][]const u8) = .empty;
        try info.append(a, .{ "Data Set", s.data_name });
        try info.append(a, .{ "Time Variable", ds.columns.items[s.time].name });
        if (s.censor) |c| {
            try info.append(a, .{ "Censoring Variable", ds.columns.items[c].name });
            var values: Out = .empty;
            for (s.censor_values, 0..) |v, k| {
                if (k > 0) try values.appendSlice(a, "  ");
                try values.appendSlice(a, try format.bestNum(a, v));
            }
            try info.append(a, .{ "Censoring Value(s)", values.items });
        }
        if (s.frequency) |c| try info.append(a, .{ "Frequency Variable", ds.columns.items[c].name });
        try info.append(a, .{ "Link Function", if (s.link == .log) "Log" else "Linear" });
        try info.append(a, .{ "Estimation Method", "Pseudo Value" });
        try info.append(a, .{ "Tau Value", try format.bestNum(a, tau) });
        try infoTable(a, &body, "Model Information", info.items);
        try body.appendSlice(a, "\n\n");
        var nobs: std.ArrayList([2][]const u8) = .empty;
        try nobs.append(a, .{ "Number of Observations Read", try count(a, @floatFromInt(sel.read)) });
        try nobs.append(a, .{ "Number of Observations Used", try count(a, @floatFromInt(sel.units.len)) });
        if (s.frequency != null) {
            try nobs.append(a, .{ "Sum of Frequencies Read", try count(a, sel.freq_read) });
            try nobs.append(a, .{ "Sum of Frequencies Used", try count(a, used) });
        }
        // ponytail: the count column is BEST8 wide in the reference.
        for (nobs.items) |*r| if (r[1].len < 8) {
            r[1] = try std.fmt.allocPrint(a, "{s: >8}", .{r[1]});
        };
        for (nobs.items) |r| try body.print(a, "{s: <27}    {s}\n", .{ r[0], r[1] });
        try body.appendSlice(a, "\n\nSummary of the Number of Event and Censored Values\n \n   Total       Event    Censored\n\n");
        try body.print(a, "{s: >8}    {s: >8}    {s: >8}\n", .{ try count(a, used), try count(a, events), try count(a, used - events) });
        try body.appendSlice(a, "\n\n                       Convergence Status\n\n                      Algorithm converged.                      \n\n\n");

        // Effect and parameter names, truncated to NAMELEN=.
        const names = try a.alloc([]const u8, p);
        var k: usize = 0;
        if (!s.noint) {
            names[0] = "Intercept";
            k = 1;
        }
        for (s.covariates) |c| {
            const n = ds.columns.items[c].name;
            names[k] = n[0..@min(n.len, s.namelen)];
            k += 1;
        }
        const se = try a.alloc(f64, p);
        for (se, 0..) |*e, j| e.* = @sqrt(result.cov[j * p + j]);
        const first_effect: usize = @intFromBool(!s.noint);
        if (s.covariates.len > 0) {
            var ew: usize = 6;
            for (names[first_effect..]) |n| ew = @max(ew, n.len);
            const width = ew + 36;
            const title = "Type 3 Analysis of Effects";
            try body.appendNTimes(a, ' ', (width - title.len) / 2);
            try body.print(a, "{s}\n \n", .{title});
            try padLeft(a, &body, "Effect", ew);
            try body.appendSlice(a, "      DF    Chi-Square    Pr > ChiSq\n\n");
            for (first_effect..p) |j| {
                const chi = result.beta[j] * result.beta[j] / result.cov[j * p + j];
                try padLeft(a, &body, names[j], ew);
                try body.appendSlice(a, "       1");
                try padRight(a, &body, try fixed(a, chi, 4), 14);
                try padRight(a, &body, try pvalue(a, chiProbability(chi, 1)), 14);
                try body.append(a, '\n');
            }
        }
        try body.appendSlice(a, "\n\n");
        var pw: usize = 9;
        for (names) |n| pw = @max(pw, n.len);
        const width = pw + 79;
        const title = "Analysis of Parameter Estimates";
        try body.appendNTimes(a, ' ', (width - title.len) / 2);
        try body.print(a, "{s}\n \n", .{title});
        const level = try format.bestNum(a, 100 * (1 - s.alpha));
        try body.appendNTimes(a, ' ', pw + 22);
        try body.appendSlice(a, "Standard");
        const conf = try std.fmt.allocPrint(a, "{s}% Confidence", .{level});
        try padRight(a, &body, conf, 21);
        try body.appendSlice(a, "          Chi-\n");
        try padLeft(a, &body, "Parameter", pw);
        try body.appendSlice(a, "    DF    Estimate       Error           Limits            Square    Pr > ChiSq\n\n");
        for (0..p) |j| {
            const b = result.beta[j];
            const chi = b * b / result.cov[j * p + j];
            const cells = [_][]const u8{ try fixed(a, b, 4), try fixed(a, se[j], 4), try fixed(a, b - z * se[j], 4), try fixed(a, b + z * se[j], 4) };
            for (cells) |cell| if (cell.len > 8) return gap(cx, 0, "parameter display wider than the 8-column reference layout is not verified", .{});
            const chi_text = try fixed(a, chi, 2);
            if (chi_text.len > 7) return gap(cx, 0, "chi-square display wider than the reference layout is not verified", .{});
            try padLeft(a, &body, names[j], pw);
            try body.appendSlice(a, "     1");
            for (cells) |cell| try padRight(a, &body, cell, 12);
            try padRight(a, &body, chi_text, 11);
            try padRight(a, &body, try pvalue(a, chiProbability(chi, 1)), 14);
            try body.append(a, '\n');
        }
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("rmstreg_tests.zig");
}
