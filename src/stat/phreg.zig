//! PROC PHREG (STAT-PHREG-001): PROC/MODEL/BY/FREQ/ID/STRATA/WEIGHT roles,
//! observation selection, and the Breslow partial-likelihood Newton fit for
//! plain numeric covariates. Everything owned by later PHREG tickets (CLASS,
//! effects, counting-process input, other TIES=, BASELINE, BAYES, programming
//! statements, output data sets, plots) fails loud as a D-009 gap.
//! ponytail: listing layouts that have no SAS reference yet (FREQ, WEIGHT,
//! STRATA, no censoring variable, several censoring values, labelled
//! covariates) gap instead of printing an unverified table.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fmt = @import("../format.zig");
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const missing = @import("data_selection.zig").missing;
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;

pub const Spec = struct {
    input: proc.ProcInput,
    time: usize = 0,
    censor: ?usize = null,
    censor_values: []const f64 = &.{},
    covariates: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    frequency: ?usize = null,
    notruncate: bool = false,
    weight: ?usize = null,
    strata: []const usize = &.{},
    strata_missing: bool = false,
    id: []const usize = &.{},
    noprint: bool = false,
    nosummary: bool = false,
    alpha: f64 = 0.05,
};

// Documented names owned by later tickets: visible gap (rc 2), never a no-op.
const gap_proc_options = [_][]const u8{ "atrisk", "covout", "covm", "covs", "covsandwich", "ev", "fast", "inest", "outest", "plots", "plot", "zph", "tau", "simple", "namelen", "multipass" };
const gap_statements = [_][]const u8{ "assess", "baseline", "bayes", "class", "contrast", "effect", "estimate", "hazardratio", "lsmeans", "lsmestimate", "output", "random", "slice", "store", "test", "format", "label", "attrib", "array", "if", "do", "end", "else", "call", "select", "when", "otherwise", "goto", "link", "return" };
const gap_model_options = [_][]const u8{ "alpha", "best", "corrb", "covb", "details", "entrytime", "entry", "eventcode", "failcode", "fconv", "firth", "gconv", "hierarchy", "include", "itprint", "maxiter", "maxstep", "nofit", "offset", "pevent", "rl", "risklimits", "selection", "sequential", "singular", "slentry", "sle", "slstay", "sls", "start", "stop", "stopres", "sr", "type1", "type3", "xconv", "absfconv", "absgconv", "absxconv", "ridging", "ridgeinit" };

fn eq(x: []const u8, y: []const u8) bool {
    return std.ascii.eqlIgnoreCase(x, y);
}
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn oneOf(name: []const u8, set: []const []const u8) bool {
    for (set) |candidate| if (eq(name, candidate)) return true;
    return false;
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC PHREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, t: []const lex.Token, i: usize, comptime what: []const u8) diag.Error {
    return proc.failGap(cx.diags, line(t, i), "PROC PHREG: " ++ what ++ " ({s}) is not implemented", .{if (i < t.len) t[i].text else "<end>"});
}
fn stmtEnd(t: []const lex.Token, start: usize) usize {
    var i = start;
    while (i < t.len and t[i].tag != .semicolon and t[i].tag != .eof) i += 1;
    return i;
}
fn numericCol(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const ci = ds.indexOf(t[i].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, t[i].text)});
    if (ds.columns.items[ci].type != .num)
        return cx.diags.fail(error.ParseError, t[i].line, "PROC PHREG: {s} variable {s} must be numeric", .{ role, ds.columns.items[ci].name });
    return ci;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "data") and at(t, i + 1, .eq)) {
            i += 2;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            if (at(t, i + 1, .dot) and at(t, i + 2, .name)) {
                qualified = i;
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[i].text, t[i + 2].text });
                i += 2;
            }
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (kw(t, i, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (kw(t, i, "nosummary")) {
            s.nosummary = true;
            i += 1;
        } else if (kw(t, i, "alpha") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            s.alpha = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(s.alpha > 0 and s.alpha < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PHREG: ALPHA= must be between 0 and 1", .{});
            i += 3;
        } else if (at(t, i, .name) and oneOf(t[i].text, &gap_proc_options)) {
            return gap(cx, t, i, "PROC statement option");
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    i += 1;

    var bys: by.Statements = .{};
    var model: ?[]const lex.Token = null;
    var freq: ?[]const lex.Token = null;
    var weight: ?[]const lex.Token = null;
    var strata: ?[]const lex.Token = null;
    var ids: std.ArrayList([]const lex.Token) = .empty;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        if (kw(t, i, "run") or kw(t, i, "quit")) break;
        const end = stmtEnd(t, i);
        const body = t[i + 1 .. end];
        if (at(t, i, .name) and at(t, i + 1, .eq)) return gap(cx, t, i, "programming statement");
        if (kw(t, i, "where")) {
            // Applied by proc.procInputObs.
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "model")) {
            if (model != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC PHREG: only one MODEL statement is allowed", .{});
            model = body;
        } else if (kw(t, i, "freq")) {
            if (freq != null) return gap(cx, t, i, "repeated statement");
            freq = body;
        } else if (kw(t, i, "weight")) {
            if (weight != null) return gap(cx, t, i, "repeated statement");
            weight = body;
        } else if (kw(t, i, "strata")) {
            if (strata != null) return gap(cx, t, i, "repeated statement");
            strata = body;
        } else if (kw(t, i, "id")) {
            try ids.append(a, body);
        } else if (at(t, i, .name) and oneOf(t[i].text, &gap_statements)) {
            return gap(cx, t, i, "statement");
        } else return invalid(cx, t, i);
        i = end;
    }

    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC PHREG: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    const m = model orelse return cx.diags.fail(error.ParseError, 0, "PROC PHREG: a MODEL statement is required", .{});
    var j: usize = 0;
    if (at(m, j, .lparen)) return gap(cx, m, j, "counting-process MODEL input");
    s.time = try numericCol(cx, ds, m, j, "failure time");
    j += 1;
    if (at(m, j, .star)) {
        s.censor = try numericCol(cx, ds, m, j + 1, "censoring");
        j += 2;
        if (!at(m, j, .lparen)) return invalid(cx, m, j);
        j += 1;
        var values: std.ArrayList(f64) = .empty;
        while (j < m.len and !at(m, j, .rparen)) {
            if (at(m, j, .comma)) {
                j += 1;
                continue;
            }
            const negative = at(m, j, .minus);
            if (negative) j += 1;
            if (kw(m, j, "to")) return gap(cx, m, j, "censoring value range");
            if (!at(m, j, .number)) return invalid(cx, m, j);
            const v = std.fmt.parseFloat(f64, m[j].text) catch return invalid(cx, m, j);
            try values.append(a, if (negative) -v else v);
            j += 1;
        }
        if (!at(m, j, .rparen) or values.items.len == 0) return invalid(cx, m, j);
        j += 1;
        s.censor_values = values.items;
    }
    if (!at(m, j, .eq)) return invalid(cx, m, j);
    j += 1;
    var covariates: std.ArrayList(usize) = .empty;
    while (j < m.len and !at(m, j, .slash)) {
        if (!at(m, j, .name)) return invalid(cx, m, j);
        if (at(m, j + 1, .star) or at(m, j + 1, .pipe) or at(m, j + 1, .lparen) or at(m, j + 1, .at)) return gap(cx, m, j, "MODEL effect");
        const start = j;
        const selected = try lists.next(a, ds, m, &j, cx.diags);
        for (selected) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, m[start].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, m[start].line, "PROC PHREG: covariate {s} must be numeric (CLASS is not implemented)", .{n});
            for (covariates.items) |seen| if (seen == ci) return gap(cx, m, start, "repeated MODEL covariate");
            try covariates.append(a, ci);
        }
    }
    if (at(m, j, .slash)) {
        j += 1;
        while (j < m.len) {
            if (kw(m, j, "ties") and at(m, j + 1, .eq) and kw(m, j + 2, "breslow")) {
                j += 3;
            } else if (kw(m, j, "ties") or (at(m, j, .name) and oneOf(m[j].text, &gap_model_options))) {
                return gap(cx, m, j, "MODEL option");
            } else return invalid(cx, m, j);
        }
    }
    if (covariates.items.len == 0) return proc.failGap(cx.diags, 0, "PROC PHREG: a MODEL without covariates is not implemented", .{});
    s.covariates = covariates.items;

    if (freq) |f| {
        s.frequency = try numericCol(cx, ds, f, 0, "FREQ");
        if (f.len == 3 and at(f, 1, .slash) and kw(f, 2, "notruncate")) s.notruncate = true else if (f.len != 1) return invalid(cx, f, 1);
    }
    if (weight) |w| {
        s.weight = try numericCol(cx, ds, w, 0, "WEIGHT");
        if (w.len == 3 and at(w, 1, .slash) and kw(w, 2, "normalize")) return gap(cx, w, 2, "WEIGHT option");
        if (w.len != 1) return invalid(cx, w, 1);
    }
    if (strata) |st| {
        var cols: std.ArrayList(usize) = .empty;
        var k: usize = 0;
        while (k < st.len and !at(st, k, .slash)) {
            if (!at(st, k, .name)) return invalid(cx, st, k);
            if (at(st, k + 1, .lparen)) return gap(cx, st, k, "STRATA interval list");
            const start = k;
            for (try lists.next(a, ds, st, &k, cx.diags)) |n|
                try cols.append(a, ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, st[start].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)}));
        }
        if (cols.items.len == 0) return invalid(cx, st, k);
        if (at(st, k, .slash)) {
            if (k + 2 == st.len and kw(st, k + 1, "missing")) s.strata_missing = true else return invalid(cx, st, k + 1);
        }
        s.strata = cols.items;
    }
    var id_cols: std.ArrayList(usize) = .empty;
    for (ids.items) |idt| {
        var k: usize = 0;
        if (idt.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC PHREG: ID requires a variable", .{});
        while (k < idt.len) {
            const start = k;
            for (try lists.next(a, ds, idt, &k, cx.diags)) |n|
                try id_cols.append(a, ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, idt[start].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)}));
        }
    }
    s.id = id_cols.items;

    const pb = try bys.resolve(a, ds, cx.diags);
    const by_cols = try a.alloc(usize, pb.names.len);
    for (pb.names, by_cols) |n, *c| c.* = ds.indexOf(n).?;
    s.by_cols = by_cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// The observations of one BY group that enter the fit. `x` is row-major
/// used×p. Strata are numbered in ascending order of their values.
pub const Selected = struct {
    time: []const f64,
    event: []const bool,
    x: []const f64,
    freq: []const f64,
    weight: []const f64,
    stratum: []const usize,
    n_strata: usize,
    read: usize,
    p: usize,

    pub fn used(self: Selected) usize {
        return self.time.len;
    }
    pub fn events(self: Selected) f64 {
        var n: f64 = 0;
        for (self.event, self.freq) |e, f| {
            if (e) n += f;
        }
        return n;
    }
    pub fn total(self: Selected) f64 {
        var n: f64 = 0;
        for (self.freq) |f| n += f;
        return n;
    }
};

fn strataLess(cols: []const usize, lhs: []const Value, rhs: []const Value) bool {
    for (cols) |ci| switch (proc.cmpValue(lhs[ci], rhs[ci])) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    };
    return false;
}
fn strataSame(cols: []const usize, lhs: []const Value, rhs: []const Value) bool {
    for (cols) |ci| if (proc.cmpValue(lhs[ci], rhs[ci]) != .eq) return false;
    return true;
}

/// PHREG observation selection: a row is dropped when the time, censoring
/// variable, any covariate or (without MISSING) any STRATA variable is missing;
/// when FREQ is missing or below 1 (truncated to an integer unless NOTRUNCATE,
/// where a nonpositive value drops the row); or when WEIGHT is missing or
/// nonpositive.
pub fn prepare(a: A, s: Spec, rows: []const []const Value) !Selected {
    var time: std.ArrayList(f64) = .empty;
    var event: std.ArrayList(bool) = .empty;
    var x: std.ArrayList(f64) = .empty;
    var freq: std.ArrayList(f64) = .empty;
    var weight: std.ArrayList(f64) = .empty;
    var kept: std.ArrayList([]const Value) = .empty;
    next: for (rows) |row| {
        if (missing(row[s.time])) continue;
        if (s.censor) |c| if (missing(row[c])) continue;
        for (s.covariates) |c| if (missing(row[c])) continue :next;
        if (!s.strata_missing) for (s.strata) |c| if (missing(row[c])) continue :next;
        var f: f64 = 1;
        if (s.frequency) |c| {
            f = row[c].num;
            if (!std.math.isFinite(f)) continue;
            if (s.notruncate) {
                if (f <= 0) continue;
            } else {
                if (f < 1) continue;
                f = @trunc(f);
            }
        }
        var w: f64 = 1;
        if (s.weight) |c| {
            w = row[c].num;
            if (!std.math.isFinite(w) or w <= 0) continue;
        }
        var is_event = true;
        if (s.censor) |c| for (s.censor_values) |v| {
            if (row[c].num == v) is_event = false;
        };
        try time.append(a, row[s.time].num);
        try event.append(a, is_event);
        for (s.covariates) |c| try x.append(a, row[c].num);
        try freq.append(a, f);
        try weight.append(a, w);
        try kept.append(a, row);
    }
    const stratum = try a.alloc(usize, kept.items.len);
    @memset(stratum, 0);
    var n_strata: usize = if (kept.items.len > 0) 1 else 0;
    if (s.strata.len > 0) {
        var reps: std.ArrayList([]const Value) = .empty;
        for (kept.items) |row| {
            var found = false;
            for (reps.items) |rep| if (strataSame(s.strata, rep, row)) {
                found = true;
                break;
            };
            if (!found) try reps.append(a, row);
        }
        std.mem.sort([]const Value, reps.items, s.strata, strataLess);
        for (kept.items, stratum) |row, *level| {
            for (reps.items, 0..) |rep, k| if (strataSame(s.strata, rep, row)) {
                level.* = k;
                break;
            };
        }
        n_strata = reps.items.len;
    }
    return .{ .time = time.items, .event = event.items, .x = x.items, .freq = freq.items, .weight = weight.items, .stratum = stratum, .n_strata = n_strata, .read = rows.len, .p = s.covariates.len };
}

pub const Fit = struct {
    beta: []f64,
    cov: []f64, // p×p inverse observed information at beta
    ll0: f64,
    ll: f64,
    score: f64,
    wald: f64,
    iterations: usize,
    converged: bool,
};

const OrderCtx = struct { sel: Selected };
fn orderLess(ctx: OrderCtx, lhs: usize, rhs: usize) bool {
    if (ctx.sel.stratum[lhs] != ctx.sel.stratum[rhs]) return ctx.sel.stratum[lhs] < ctx.sel.stratum[rhs];
    return ctx.sel.time[lhs] > ctx.sel.time[rhs];
}

/// Breslow log partial likelihood with FREQ f and WEIGHT w:
///   l(b) = sum over events i of f_i w_i [x_i'b - log S0_i],
///   S0_i = sum over j in the same stratum with t_j >= t_i of f_j w_j exp(x_j'b).
/// Writes the score into `u` and the observed information into `info`.
/// `order` lists observations by stratum, then by decreasing time.
pub fn evaluate(sel: Selected, order: []const usize, beta: []const f64, u: []f64, info: []f64, s1: []f64, s2: []f64) f64 {
    const p = sel.p;
    @memset(u, 0);
    @memset(info, 0);
    var ll: f64 = 0;
    var k: usize = 0;
    while (k < order.len) {
        const stratum = sel.stratum[order[k]];
        var s0: f64 = 0;
        @memset(s1, 0);
        @memset(s2, 0);
        while (k < order.len and sel.stratum[order[k]] == stratum) {
            const t = sel.time[order[k]];
            var block_end = k;
            while (block_end < order.len and sel.stratum[order[block_end]] == stratum and sel.time[order[block_end]] == t) block_end += 1;
            for (order[k..block_end]) |o| {
                const xs = sel.x[o * p .. (o + 1) * p];
                var eta: f64 = 0;
                for (xs, beta) |xv, b| eta += xv * b;
                const r = sel.freq[o] * sel.weight[o] * @exp(eta);
                s0 += r;
                for (0..p) |c| {
                    s1[c] += r * xs[c];
                    for (0..p) |c2| s2[c * p + c2] += r * xs[c] * xs[c2];
                }
            }
            var d: f64 = 0;
            for (order[k..block_end]) |o| if (sel.event[o]) {
                const xs = sel.x[o * p .. (o + 1) * p];
                const wt = sel.freq[o] * sel.weight[o];
                var eta: f64 = 0;
                for (xs, beta) |xv, b| eta += xv * b;
                ll += wt * eta;
                for (0..p) |c| u[c] += wt * xs[c];
                d += wt;
            };
            if (d > 0) {
                ll -= d * @log(s0);
                for (0..p) |c| {
                    u[c] -= d * s1[c] / s0;
                    for (0..p) |c2| info[c * p + c2] += d * (s2[c * p + c2] / s0 - s1[c] * s1[c2] / (s0 * s0));
                }
            }
            k = block_end;
        }
    }
    return ll;
}

/// Gauss-Jordan inverse with partial pivoting; error.Singular when a pivot
/// vanishes relative to the largest diagonal.
fn invert(a: A, m: []const f64, p: usize) ![]f64 {
    const w = try a.dupe(f64, m);
    const inv = try a.alloc(f64, p * p);
    @memset(inv, 0);
    var scale: f64 = 0;
    for (0..p) |c| {
        inv[c * p + c] = 1;
        scale = @max(scale, @abs(m[c * p + c]));
    }
    for (0..p) |c| {
        var pivot = c;
        for (c + 1..p) |r| if (@abs(w[r * p + c]) > @abs(w[pivot * p + c])) {
            pivot = r;
        };
        if (!(@abs(w[pivot * p + c]) > 1e-12 * scale)) return error.Singular;
        if (pivot != c) for (0..p) |q| {
            std.mem.swap(f64, &w[c * p + q], &w[pivot * p + q]);
            std.mem.swap(f64, &inv[c * p + q], &inv[pivot * p + q]);
        };
        const dv = w[c * p + c];
        for (0..p) |q| {
            w[c * p + q] /= dv;
            inv[c * p + q] /= dv;
        }
        for (0..p) |r| if (r != c) {
            const factor = w[r * p + c];
            if (factor == 0) continue;
            for (0..p) |q| {
                w[r * p + q] -= factor * w[c * p + q];
                inv[r * p + q] -= factor * inv[c * p + q];
            }
        };
    }
    return inv;
}

fn quad(m: []const f64, v: []const f64) f64 {
    const p = v.len;
    var total: f64 = 0;
    for (0..p) |r| for (0..p) |c| {
        total += v[r] * m[r * p + c] * v[c];
    };
    return total;
}

pub fn sortedOrder(a: A, sel: Selected) ![]usize {
    const order = try a.alloc(usize, sel.used());
    for (order, 0..) |*o, k| o.* = k;
    std.mem.sort(usize, order, OrderCtx{ .sel = sel }, orderLess);
    return order;
}

/// Newton-Raphson from beta=0 with step halving; stops on the relative
/// gradient criterion g'H^-1 g / (|l| + 1e-6) < 1e-8 (the documented GCONV default).
pub fn fit(a: A, sel: Selected) !Fit {
    const p = sel.p;
    const order = try sortedOrder(a, sel);
    const beta = try a.alloc(f64, p);
    @memset(beta, 0);
    const u = try a.alloc(f64, p);
    const info = try a.alloc(f64, p * p);
    const s1 = try a.alloc(f64, p);
    const s2 = try a.alloc(f64, p * p);
    const trial = try a.alloc(f64, p);
    const step = try a.alloc(f64, p);
    var ll = evaluate(sel, order, beta, u, info, s1, s2);
    const ll0 = ll;
    var cov = try invert(a, info, p);
    const score = quad(cov, u);
    var converged = false;
    var iterations: usize = 0;
    while (iterations < 25) : (iterations += 1) {
        cov = try invert(a, info, p);
        for (0..p) |r| {
            step[r] = 0;
            for (0..p) |c| step[r] += cov[r * p + c] * u[c];
        }
        var crit: f64 = 0;
        for (step, u) |sv, uv| crit += sv * uv;
        if (crit / (@abs(ll) + 1e-6) < 1e-8) {
            converged = true;
            break;
        }
        var scale: f64 = 1;
        var halvings: usize = 0;
        while (true) : (halvings += 1) {
            for (trial, beta, step) |*tv, b, sv| tv.* = b + scale * sv;
            const next = evaluate(sel, order, trial, u, info, s1, s2);
            if (next >= ll or halvings >= 20) {
                ll = next;
                break;
            }
            scale /= 2;
        }
        @memcpy(beta, trial);
    }
    return .{ .beta = beta, .cov = cov, .ll0 = ll0, .ll = ll, .score = score, .wald = quad(info, beta), .iterations = iterations, .converged = converged };
}

fn num(a: A, x: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try fmt.apply(a, .{ .num = x }, spec), " ");
}

fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, sel: Selected, f: Fit, rep: ?[]const Value) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    const cols = ds.columns.items;
    if (rep) |row| if (s.by_cols.len > 0) try by.appendLine(a, out, ds, row, s.by_cols);
    try out.appendSlice(a, "\nThe PHREG Procedure\n\nModel Information\n\n");
    const upper = try std.ascii.allocUpperString(a, ds.name);
    try out.print(a, "Data Set {s}{s}\n", .{ if (std.mem.indexOfScalar(u8, upper, '.') == null) @as([]const u8, "WORK.") else "", upper });
    try out.print(a, "Dependent Variable {s} {s}\n", .{ cols[s.time].name, cols[s.time].label orelse "" });
    const c = s.censor.?;
    try out.print(a, "Censoring Variable {s} {s}\n", .{ cols[c].name, cols[c].label orelse "" });
    try out.print(a, "Censoring Value(s) {s}\nTies Handling BRESLOW\n\n", .{try num(a, s.censor_values[0], "best12.")});
    try out.print(a, "Number of Observations Read {d}\nNumber of Observations Used {d}\n\n", .{ sel.read, sel.used() });
    const total = sel.total();
    const events = sel.events();
    if (!s.nosummary) {
        try out.appendSlice(a, "Summary of the Number of Event and Censored Values\n\nPercent\nTotal Event Censored Censored\n\n");
        try out.print(a, "{d} {d} {d} {s}\n\n", .{ total, events, total - events, try num(a, 100 * (total - events) / total, "10.2") });
    }
    try out.appendSlice(a, "Convergence Status\n\nConvergence criterion (GCONV=1E-8) satisfied.\n\n");
    const p: f64 = @floatFromInt(sel.p);
    const m0 = -2 * f.ll0;
    const m1 = -2 * f.ll;
    try out.appendSlice(a, "Model Fit Statistics\n\nWithout With\nCriterion Covariates Covariates\n\n");
    try out.print(a, "-2 LOG L {s} {s}\n", .{ try num(a, m0, "12.3"), try num(a, m1, "12.3") });
    try out.print(a, "AIC {s} {s}\n", .{ try num(a, m0, "12.3"), try num(a, m1 + 2 * p, "12.3") });
    try out.print(a, "SBC {s} {s}\n\n", .{ try num(a, m0, "12.3"), try num(a, m1 + p * @log(events), "12.3") });
    try out.appendSlice(a, "Testing Global Null Hypothesis: BETA=0\n\nTest Chi-Square DF Pr > ChiSq\n\n");
    for ([_][]const u8{ "Likelihood Ratio", "Score", "Wald" }, [_]f64{ m0 - m1, f.score, f.wald }) |label, value|
        try out.print(a, "{s} {s} {d} {s}\n", .{ label, try num(a, value, "12.4"), sel.p, try num(a, chiTail(value, sel.p), "pvalue6.4") });
    try out.appendSlice(a, "\nAnalysis of Maximum Likelihood Estimates\n\nParameter Standard Hazard\nParameter DF Estimate Error Chi-Square Pr > ChiSq Ratio\n\n");
    for (s.covariates, 0..) |ci, k| {
        const se = @sqrt(f.cov[k * sel.p + k]);
        const chi = (f.beta[k] / se) * (f.beta[k] / se);
        try out.print(a, "{s} 1 {s} {s} {s} {s} {s}\n", .{ cols[ci].name, try num(a, f.beta[k], "12.5"), try num(a, se, "12.5"), try num(a, chi, "12.4"), try num(a, chiTail(chi, 1), "pvalue6.4"), try num(a, @exp(f.beta[k]), "12.3") });
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    if (!s.noprint) {
        if (s.frequency != null or s.weight != null or s.strata.len > 0)
            return proc.failGap(cx.diags, 0, "PROC PHREG: the listing with FREQ, WEIGHT or STRATA is not implemented", .{});
        if (s.censor == null or s.censor_values.len != 1)
            return proc.failGap(cx.diags, 0, "PROC PHREG: the listing without exactly one censoring value is not implemented", .{});
        for (s.covariates) |ci| if (ds.columns.items[ci].label != null)
            return proc.failGap(cx.diags, 0, "PROC PHREG: the listing with labelled covariates is not implemented", .{});
    }
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    var body: std.ArrayList(u8) = .empty;
    for (slices) |slice| {
        const sel = try prepare(a, s, slice.rows);
        if (sel.used() == 0) return cx.diags.fail(error.ExecError, 0, "PROC PHREG: there are no valid observations", .{});
        if (sel.events() == 0) return proc.failGap(cx.diags, 0, "PROC PHREG: input without events is not implemented", .{});
        const f = fit(a, sel) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return proc.failGap(cx.diags, 0, "PROC PHREG: linearly dependent covariates are not implemented", .{}),
        };
        if (!f.converged or !std.math.isFinite(f.ll)) return proc.failGap(cx.diags, 0, "PROC PHREG: nonconverged fits are not implemented", .{});
        if (!s.noprint) try render(cx, &body, s, sel, f, slice.rep);
    }
    try out.appendSlice(a, body.items);
}

// ---------------------------------------------------------------- tests

const nan = std.math.nan(f64);

fn testLib(a: A, rows: []const [7]f64) !*@import("../exec.zig").Library {
    const lib = try a.create(@import("../exec.zig").Library);
    lib.* = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "t", "c", "x", "f", "w", "g", "b" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("text", .char);
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .num = r[6] }, .{ .str = "a" } });
    try lib.put("sample", ds);
    return lib;
}

// Invented data: t, c (0 = censored), x, f, w, g (stratum), b (BY group).
const base_rows = [_][7]f64{
    .{ 1, 1, 1, 1, 1, 2, 1 },
    .{ 2, 1, 0, 1, 1, 2, 1 },
    .{ 3, 1, 1, 1, 1, 1, 1 },
    .{ 4, 1, 0, 1, 1, 1, 1 },
    .{ 5, 0, 1, 2.9, 2, 1, 2 },
    .{ 6, 1, 0, 0.9, 1, 1, 2 }, // FREQ < 1
    .{ 7, 1, 1, nan, 1, 2, 2 }, // FREQ missing
    .{ 8, 1, 0, 1, 0, 2, 2 }, // WEIGHT zero
    .{ 9, 1, 1, 1, nan, 2, 2 }, // WEIGHT missing
    .{ nan, 1, 1, 1, 1, 1, 2 }, // time missing
    .{ 11, nan, 1, 1, 1, 1, 2 }, // censor missing
    .{ 12, 1, nan, 1, 1, 1, 2 }, // covariate missing
    .{ 13, 1, 0, 1, 1, nan, 2 }, // stratum missing
};

test "STAT-PHREG-001 parse defaults, explicit options and variable roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a, &base_rows);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = &d };
    const plain = try parse(cx, try lex.tokenize(a, "proc phreg data=sample; model t*c(0)=x; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), plain.time);
    try std.testing.expectEqual(@as(?usize, 1), plain.censor);
    try std.testing.expectEqualSlices(f64, &.{0}, plain.censor_values);
    try std.testing.expectEqualSlices(usize, &.{2}, plain.covariates);
    try std.testing.expect(!plain.noprint and !plain.nosummary and !plain.notruncate and !plain.strata_missing);
    try std.testing.expectEqual(@as(f64, 0.05), plain.alpha);
    try std.testing.expect(plain.frequency == null and plain.weight == null);
    try std.testing.expectEqual(@as(usize, 0), plain.by_cols.len + plain.strata.len + plain.id.len);

    const full = try parse(cx, try lex.tokenize(a, "proc phreg noprint nosummary alpha=0.1; model t*c(0, -1 2)=x g / ties=breslow; by descending t; by b; freq f / notruncate; weight w; strata g / missing; id text; id b; run;", &d));
    try std.testing.expect(full.noprint and full.nosummary and full.notruncate and full.strata_missing);
    try std.testing.expectEqual(@as(f64, 0.1), full.alpha);
    try std.testing.expectEqualSlices(f64, &.{ 0, -1, 2 }, full.censor_values);
    try std.testing.expectEqualSlices(usize, &.{ 2, 5 }, full.covariates);
    try std.testing.expectEqualSlices(usize, &.{6}, full.by_cols); // the last BY statement wins
    try std.testing.expectEqual(@as(?usize, 3), full.frequency);
    try std.testing.expectEqual(@as(?usize, 4), full.weight);
    try std.testing.expectEqualSlices(usize, &.{5}, full.strata);
    try std.testing.expectEqualSlices(usize, &.{ 7, 6 }, full.id);
    const no_censor = try parse(cx, try lex.tokenize(a, "proc phreg; model t=x; run;", &d));
    try std.testing.expect(no_censor.censor == null);
    try std.testing.expect(!d.hasErrors());
}

test "STAT-PHREG-001 observation selection: missing roles, FREQ, WEIGHT, STRATA order, BY groups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a, &base_rows);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = &d };
    const rows = lib.find("sample").?.rows.items;

    const plain = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 13), plain.read);
    try std.testing.expectEqual(@as(usize, 10), plain.used()); // time, censor, covariate missing dropped
    try std.testing.expectEqual(@as(f64, 9), plain.events());
    try std.testing.expectEqual(@as(usize, 1), plain.n_strata);

    const fr = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; freq f; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 8), fr.used()); // also FREQ<1 and FREQ missing
    try std.testing.expectEqual(@as(f64, 2), fr.freq[4]); // 2.9 truncates
    try std.testing.expectEqual(@as(f64, 9), fr.total());
    const nt = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; freq f / notruncate; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 9), nt.used()); // 0.9 kept, missing dropped
    try std.testing.expectEqual(@as(f64, 2.9), nt.freq[4]);
    try std.testing.expectEqual(@as(f64, 0.9), nt.freq[5]);

    const wt = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; weight w; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 8), wt.used()); // zero and missing WEIGHT dropped
    try std.testing.expectEqual(@as(f64, 2), wt.weight[4]);
    try std.testing.expectEqual(@as(f64, 8), wt.total()); // WEIGHT never changes counts

    const st = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; strata g; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 9), st.used());
    try std.testing.expectEqual(@as(usize, 2), st.n_strata);
    try std.testing.expectEqualSlices(usize, &.{ 1, 1, 0, 0, 0, 0, 1, 1, 1 }, st.stratum); // levels ascend by value, not by first appearance
    const sm = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; strata g / missing; run;", &d)), rows);
    try std.testing.expectEqual(@as(usize, 10), sm.used());
    try std.testing.expectEqual(@as(usize, 3), sm.n_strata);
    try std.testing.expectEqual(@as(usize, 0), sm.stratum[9]); // missing sorts first

    const multi = try prepare(a, try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0 1)=x; run;", &d)), rows);
    try std.testing.expectEqual(@as(f64, 0), multi.events());

    const bs = try parse(cx, try lex.tokenize(a, "proc phreg; model t*c(0)=x; by b; run;", &d));
    const groups = try by.checkedSlices(a, bs.input.ds, bs.by_cols, bs.by_desc, bs.notsorted, &d);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    try std.testing.expectEqual(@as(usize, 4), (try prepare(a, bs, groups[0].rows)).used());
    try std.testing.expectEqual(@as(usize, 6), (try prepare(a, bs, groups[1].rows)).used());
    const empty = try prepare(a, bs, rows[0..0]);
    try std.testing.expectEqual(@as(usize, 0), empty.used() + empty.n_strata + empty.read);
    try std.testing.expectEqual(@as(usize, 13), rows.len); // the source is never rewritten
}

fn selOf(a: A, t: []const f64, e: []const bool, x: []const f64, f: ?[]const f64, st: ?[]const usize, n_strata: usize) !Selected {
    const ones = try a.alloc(f64, t.len);
    @memset(ones, 1);
    const zeros = try a.alloc(usize, t.len);
    @memset(zeros, 0);
    return .{ .time = t, .event = e, .x = x, .freq = f orelse ones, .weight = ones, .stratum = st orelse zeros, .n_strata = n_strata, .read = t.len, .p = x.len / t.len };
}

test "STAT-PHREG-001 Breslow fit: closed-form null likelihood/score/information and FREQ/STRATA identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Four untied events, x = 1,0,1,0. By hand at beta=0:
    //   l = -log(4*3*2*1); U = (1-1/2)+(0-1/3)+(1-1/2)+0 = 2/3;
    //   I = 1/4 + 2/9 + 1/4 + 0 = 13/18; score chi-square = U^2/I = 8/13.
    const t4 = [_]f64{ 1, 2, 3, 4 };
    const e4 = [_]bool{ true, true, true, true };
    const x4 = [_]f64{ 1, 0, 1, 0 };
    const s4 = try selOf(a, &t4, &e4, &x4, null, null, 1);
    var u: [1]f64 = undefined;
    var info: [1]f64 = undefined;
    var w1: [1]f64 = undefined;
    var w2: [1]f64 = undefined;
    const order = try sortedOrder(a, s4);
    const l0 = evaluate(s4, order, &.{0}, &u, &info, &w1, &w2);
    try std.testing.expectApproxEqAbs(-@log(24.0), l0, 1e-14);
    try std.testing.expectApproxEqAbs(2.0 / 3.0, u[0], 1e-14);
    try std.testing.expectApproxEqAbs(13.0 / 18.0, info[0], 1e-14);
    const f4 = try fit(a, s4);
    try std.testing.expect(f4.converged);
    try std.testing.expectApproxEqAbs(-@log(24.0), f4.ll0, 1e-14);
    try std.testing.expectApproxEqAbs(8.0 / 13.0, f4.score, 1e-13);
    // At the reported estimate the score meets the documented GCONV rule
    // g'H^-1 g / (|l| + 1e-6) < 1e-8, and the variance is 1/I(beta).
    const l1 = evaluate(s4, order, f4.beta, &u, &info, &w1, &w2);
    try std.testing.expect(u[0] * u[0] / info[0] / (@abs(l1) + 1e-6) < 1e-8);
    try std.testing.expectApproxEqAbs(1 / info[0], f4.cov[0], 1e-12);
    try std.testing.expectApproxEqAbs(f4.ll, l1, 1e-12);
    try std.testing.expect(l1 > l0);
    // Central differences of the likelihood reproduce score and information.
    const h = 1e-4;
    const b = f4.beta[0] + 0.3;
    var up: [1]f64 = undefined;
    var um: [1]f64 = undefined;
    var scratch: [1]f64 = undefined;
    const lp = evaluate(s4, order, &.{b + h}, &up, &scratch, &w1, &w2);
    const lm = evaluate(s4, order, &.{b - h}, &um, &scratch, &w1, &w2);
    _ = evaluate(s4, order, &.{b}, &u, &info, &w1, &w2);
    try std.testing.expectApproxEqAbs((lp - lm) / (2 * h), u[0], 1e-7);
    try std.testing.expectApproxEqAbs(-(up[0] - um[0]) / (2 * h), info[0], 1e-7);

    // Tied and censored rows: Breslow null likelihood is -sum over events of
    // log(size of the risk set), computed here by brute force.
    const t = [_]f64{ 5, 5, 3, 3, 3, 8, 1, 9 };
    const e = [_]bool{ true, false, true, true, false, true, true, false };
    const x = [_]f64{ 0.5, 1, 2, 0, 1, 3, 1, 0, 0, 1, 2, 2, 1, 0, 0, 3 }; // p = 2
    const s = try selOf(a, &t, &e, &x, null, null, 1);
    const fs = try fit(a, s);
    var brute: f64 = 0;
    for (t, e) |ti, ei| if (ei) {
        var at_risk: f64 = 0;
        for (t) |tj| {
            if (tj >= ti) at_risk += 1;
        }
        brute -= @log(at_risk);
    };
    try std.testing.expectApproxEqAbs(brute, fs.ll0, 1e-13);
    try std.testing.expect(fs.converged and fs.ll >= fs.ll0);

    // FREQ=2 on every row is the same Breslow problem as writing each row twice.
    const twos = [_]f64{2} ** 8;
    const sf = try selOf(a, &t, &e, &x, &twos, null, 1);
    const ff = try fit(a, sf);
    const sd = try selOf(a, &(t ++ t), &(e ++ e), &(x ++ x), null, null, 1);
    const fd = try fit(a, sd);
    try std.testing.expectApproxEqAbs(fd.ll0, ff.ll0, 1e-12);
    try std.testing.expectApproxEqAbs(fd.ll, ff.ll, 1e-10);
    for (fd.beta, ff.beta) |lhs, rhs| try std.testing.expectApproxEqAbs(lhs, rhs, 1e-9);
    try std.testing.expectApproxEqAbs(fd.score, ff.score, 1e-10);
    try std.testing.expectEqual(@as(f64, 10), sf.events());

    // Two strata holding the same rows: the stratified likelihood is the sum
    // of the per-stratum likelihoods, so l doubles, beta is unchanged and
    // (unlike the pooled duplicate above) risk sets do not mix.
    const strata = [_]usize{0} ** 8 ++ [_]usize{1} ** 8;
    const ss = try selOf(a, &(t ++ t), &(e ++ e), &(x ++ x), null, &strata, 2);
    const fst = try fit(a, ss);
    try std.testing.expectApproxEqAbs(2 * fs.ll0, fst.ll0, 1e-12);
    try std.testing.expectApproxEqAbs(2 * fs.ll, fst.ll, 1e-10);
    for (fs.beta, fst.beta) |lhs, rhs| try std.testing.expectApproxEqAbs(lhs, rhs, 1e-9);
    try std.testing.expectApproxEqAbs(fs.cov[0] / 2, fst.cov[0], 1e-9);
    try std.testing.expect(@abs(fst.ll0 - fd.ll0) > 1);
}

test "STAT-PHREG-001 invalid input is a user error and later-ticket features gap loudly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a, &base_rows);
    const cases = [_]struct { src: []const u8, rc: u8 }{
        // user errors (rc 1)
        .{ .src = "proc phreg; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; model t*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c()=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0) x; run;", .rc = 1 },
        .{ .src = "proc phreg; model nope*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=nope; run;", .rc = 1 },
        .{ .src = "proc phreg; model text*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=text; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x / bogus; run;", .rc = 1 },
        .{ .src = "proc phreg bogus; model t*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg alpha=2; model t*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg data=missing; model t*c(0)=x; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; freq text; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; freq f g; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; weight nope; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; strata nope; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; strata g / bogus; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; id nope; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; by nope; run;", .rc = 1 },
        .{ .src = "proc phreg; model t*c(0)=x; by descending t; run;", .rc = 1 }, // not sorted
        .{ .src = "proc phreg; model t*c(0)=x; bogus x; run;", .rc = 1 },
        // gaps (rc 2)
        .{ .src = "proc phreg plots(overlay)=survival; model t*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg outest=e; model t*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg covs; model t*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg simple; model t*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; baseline out=_null_; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; bayes seed=1; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x z; z=x*log(t); run;", .rc = 2 },
        .{ .src = "proc phreg; class g; model t*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg; model (t,g)*c(0)=x; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x*g; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x / ties=efron; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x / selection=forward; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x x; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; freq f; freq f; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; weight w; weight w; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; weight w / normalize; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; strata g(1 2); run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; output out=o; run;", .rc = 2 },
        // valid roles whose listing has no reference layout yet
        .{ .src = "proc phreg; model t*c(0)=x; freq f; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; weight w; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0)=x; strata g; run;", .rc = 2 },
        .{ .src = "proc phreg; model t=x; run;", .rc = 2 },
        .{ .src = "proc phreg; model t*c(0 1)=x; run;", .rc = 2 },
        // every x equal: singular information
        .{ .src = "proc phreg noprint; model t*c(0)=b; by b; run;", .rc = 2 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = run(.{ .arena = a, .lib = lib, .diags = &d }, &output, try lex.tokenize(a, case.src, &d));
        if (result) |_| {
            std.debug.print("unexpected success: {s}\n", .{case.src});
            return error.TestUnexpectedResult;
        } else |_| {}
        std.testing.expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("wrong exit class: {s}\n", .{case.src});
            return err;
        };
        try std.testing.expectEqual(@as(usize, 0), output.items.len);
    }
}

test "STAT-PHREG-001 NOPRINT, ID, BY groups and empty selections execute without rewriting input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a, &base_rows);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, "proc phreg noprint; model t*c(0)=x; freq f; weight w; strata g; id text; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(!d.hasErrors() and !diag.gapHit());
    try run(cx, &out, try lex.tokenize(a, "proc phreg nosummary; model t*c(0)=x; id text; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Number of Observations Read 13\nNumber of Observations Used 10\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Summary of the Number") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Data Set WORK.SAMPLE\n") != null);
    // WHERE leaves no usable row: a visible user error, no output.
    out.clearRetainingCapacity();
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ExecError, run(.{ .arena = a, .lib = lib, .diags = &d2 }, &out, try lex.tokenize(a, "proc phreg; model t*c(0)=x; where x=.; run;", &d2)));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d2.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 13), lib.find("sample").?.rows.items.len);
}
