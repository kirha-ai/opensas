//! PROC CATMOD (STAT-CATMOD-001): data input, variable roles and basic
//! options — PROC CATMOD DATA=/ORDER=DATA|INTERNAL, WEIGHT, POPULATION, BY,
//! RESPONSE MEANS (weighted least squares) or the default generalized logits
//! (maximum likelihood), MODEL response = class effects (main effects and
//! crossings, deviation-from-the-mean coding) with / DESIGN, and interactive
//! RUN groups (S154 Chapter 36, PDF pp. 2191–2193, 2208–2211, 2220–2224).
//! Everything else is a loud D-009 gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lifetest = @import("lifetest.zig");
const matrix = @import("mixed_fit_matrix.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);
const Token = lex.Token;

fn at(t: []const Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC CATMOD: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC CATMOD: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Statements in effect for the open procedure (each without its `;`). A later
/// statement of the same kind replaces the earlier one (interactive RUN groups).
pub const State = struct {
    proc_stmt: []const Token = &.{},
    weight: ?[]const Token = null,
    response: ?[]const Token = null,
    population: ?[]const Token = null,
    by_stmt: ?[]const Token = null,
    model: ?[]const Token = null,
};

pub const Effect = struct { name: []const u8, vars: []const usize };

pub const Spec = struct {
    ds: *Dataset,
    order_data: bool = false,
    noprint: bool = false,
    weight: ?usize = null,
    response: usize = 0,
    means: bool = false,
    pop_vars: []const usize = &.{},
    effects: []const Effect = &.{},
    design: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    by_notsorted: bool = false,
    model_line: usize = 0,
};

/// Later CATMOD statements owned by other tickets.
const later_statements = [_][]const u8{ "contrast", "direct", "factors", "loglin", "repeated", "restrict" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}

fn parseProc(cx: proc.ProcCtx, s: *Spec, t: []const Token) diag.Error!void {
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
            }
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on DATA= are not implemented", .{});
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            // FORMATTED equals INTERNAL here: formatted classification
            // variables are a gap, and unformatted values sort by value.
            if (eq(v, "data")) s.order_data = true else if (eq(v, "internal") or eq(v, "formatted")) s.order_data = false else if (eq(v, "freq")) {
                return gap(cx, t[i].line, "ORDER={s} is not implemented", .{v});
            } else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "namelen") and valued) {
            // NAMELEN=n, 24 <= n <= 200; effect names longer than 24 are a gap
            // below, so the value changes no listing here.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const n = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (n < 24 or n > 200 or n != @floor(n)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: NAMELEN= must be an integer between 24 and 200", .{});
            i += 3;
        } else return invalid(cx, t, i);
    }
    const ds = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC CATMOD: input data set not found", .{});
    s.ds = ds;
}

fn varList(cx: proc.ProcCtx, ds: *const Dataset, t: []const Token, start: usize) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < t.len) : (j += 1) {
        if (!at(t, j, .name)) {
            if (at(t, j, .slash)) return gap(cx, t[j].line, "{s} statement options are not implemented", .{t[0].text});
            return gap(cx, t[j].line, "variable lists other than plain names in {s} are not implemented", .{t[0].text});
        }
        const c = try column(cx, ds, t, j);
        for (cols.items) |o| if (o == c) return cx.diags.fail(error.ParseError, t[j].line, "PROC CATMOD: variable {s} appears twice in the {s} statement", .{ t[j].text, t[0].text });
        try cols.append(cx.arena, c);
    }
    if (cols.items.len == 0) return invalid(cx, t, start);
    return cols.items;
}

fn parseModel(cx: proc.ProcCtx, s: *Spec, t: []const Token) diag.Error!void {
    const ds = s.ds;
    s.model_line = t[0].line;
    if (!at(t, 1, .name)) return invalid(cx, t, 1);
    if (at(t, 2, .star) or at(t, 2, .lparen) or kw(t, 1, "_response_")) return gap(cx, t[1].line, "multiple response variables and _RESPONSE_ are not implemented", .{});
    s.response = try column(cx, ds, t, 1);
    if (!at(t, 2, .eq)) return invalid(cx, t, 2);
    var i: usize = 3;
    if (at(t, i, .lparen)) return gap(cx, t[i].line, "a direct design matrix in MODEL is not implemented", .{});
    var effects: std.ArrayList(Effect) = .empty;
    while (i < t.len and !at(t, i, .slash)) {
        var vars: std.ArrayList(usize) = .empty;
        const first = i;
        while (true) {
            if (!at(t, i, .name)) {
                if (i < t.len and (t[i].tag == .lparen or t[i].tag == .pipe or t[i].tag == .at)) return gap(cx, t[i].line, "nested, bar and @ effects are not implemented", .{});
                return invalid(cx, t, i);
            }
            if (kw(t, i, "_response_")) return gap(cx, t[i].line, "_RESPONSE_ effects are not implemented", .{});
            const c = try column(cx, ds, t, i);
            for (vars.items) |o| if (o == c) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: variable {s} appears twice in an effect", .{t[i].text});
            try vars.append(cx.arena, c);
            i += 1;
            if (at(t, i, .star)) {
                i += 1;
                continue;
            }
            break;
        }
        if (at(t, i, .lparen) or at(t, i, .pipe) or at(t, i, .at)) return gap(cx, t[i].line, "nested, bar and @ effects are not implemented", .{});
        var nm: Out = .empty;
        for (vars.items, 0..) |c, k| {
            if (k > 0) try nm.append(cx.arena, '*');
            try nm.appendSlice(cx.arena, ds.columns.items[c].name);
        }
        for (effects.items) |e| if (eq(e.name, nm.items)) return cx.diags.fail(error.ParseError, t[first].line, "PROC CATMOD: effect {s} is specified twice", .{nm.items});
        try effects.append(cx.arena, .{ .name = nm.items, .vars = vars.items });
    }
    if (effects.items.len == 0) return gap(cx, lineOf(t, i), "an intercept-only MODEL is not implemented", .{});
    s.effects = effects.items;
    for (s.effects) |e| if (e.name.len > 24) return gap(cx, s.model_line, "effect names longer than 24 characters (NAMELEN=) are not implemented", .{});
    if (at(t, i, .slash)) {
        i += 1;
        while (i < t.len) : (i += 1) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            if (eq(t[i].text, "design")) {
                s.design = true;
            } else if (oneOf(t[i].text, &.{ "addcell", "alpha", "avgdesign", "clparm", "corrb", "covb", "epsilon", "freq", "maxiter", "ml", "gls", "wls", "noiter", "noint", "noprofile", "noresponse", "nodesign", "noparm", "nogls", "noprint", "onefactor", "oneway", "pred", "predict", "prob", "pcov", "profile", "title", "xpx", "zero" })) {
                return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{t[i].text});
            } else return invalid(cx, t, i);
        }
    }
}

pub fn resolve(cx: proc.ProcCtx, st: State) diag.Error!Spec {
    var s: Spec = .{ .ds = undefined };
    try parseProc(cx, &s, st.proc_stmt);
    const ds = s.ds;
    // Without WEIGHT every observation is one subject (raw data, p. 2220).
    if (st.weight) |weight| {
        if (weight.len != 2) return invalid(cx, weight, 2);
        const wc = try column(cx, ds, weight, 1);
        if (ds.columns.items[wc].type != .num) return cx.diags.fail(error.ParseError, weight[0].line, "PROC CATMOD: WEIGHT variable {s} must be numeric", .{weight[1].text});
        s.weight = wc;
    }
    if (st.response) |r| {
        if (r.len == 1) {
            s.means = false;
        } else if (r.len == 2 and kw(r, 1, "means")) {
            s.means = true;
        } else if (r.len >= 2 and at(r, 1, .name) and oneOf(r[1].text, &.{ "logits", "logit", "clogits", "alogits", "joint", "marginals", "marginal", "mean", "readcell", "exp", "log", "identity" })) {
            return gap(cx, r[1].line, "RESPONSE {s} is not implemented", .{r[1].text});
        } else return gap(cx, r[0].line, "RESPONSE functions other than MEANS are not implemented", .{});
    }
    try parseModel(cx, &s, st.model.?);
    if (st.population) |p| {
        s.pop_vars = try varList(cx, ds, p, 1);
        for (s.effects) |e| for (e.vars) |v| {
            for (s.pop_vars) |pv| {
                if (pv == v) break;
            } else return gap(cx, s.model_line, "model effect variables outside the POPULATION statement are not implemented", .{});
        };
    } else {
        var pv: std.ArrayList(usize) = .empty;
        for (s.effects) |e| for (e.vars) |v| {
            for (pv.items) |o| {
                if (o == v) break;
            } else try pv.append(cx.arena, v);
        };
        s.pop_vars = pv.items;
    }
    for (s.pop_vars) |v| if (v == s.response) return cx.diags.fail(error.ParseError, s.model_line, "PROC CATMOD: the response variable cannot also be an explanatory variable", .{});
    for (s.pop_vars) |v| if (ds.columns.items[v].format != null) return gap(cx, s.model_line, "formatted classification variables are not implemented", .{});
    if (ds.columns.items[s.response].format != null) return gap(cx, s.model_line, "a formatted response variable is not implemented", .{});
    if (s.means and ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, s.model_line, "PROC CATMOD: RESPONSE MEANS requires a numeric response variable", .{});
    if (s.design and !s.means) return gap(cx, s.model_line, "MODEL / DESIGN with maximum likelihood is not implemented", .{});
    if (st.by_stmt) |b| {
        var bys: by.Statements = .{};
        var j: usize = 0;
        var full: std.ArrayList(Token) = .empty;
        try full.appendSlice(cx.arena, b);
        try full.append(cx.arena, .{ .tag = .semicolon, .text = ";", .line = b[0].line });
        try bys.read(cx.arena, full.items, &j);
        const pb = try bys.resolve(cx.arena, ds, cx.diags);
        const cols = try cx.arena.alloc(usize, pb.names.len);
        for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = pb.desc;
        s.by_notsorted = pb.notsorted;
    }
    return s;
}

// ── Contingency table ─────────────────────────────────────────────────────

fn lessValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a < y.num,
        .str => |a| std.mem.lessThan(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}
fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a == y.num,
        .str => |a| std.mem.eql(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}

/// Levels of one variable: order of appearance (ORDER=DATA) or ascending
/// unformatted value (ORDER=INTERNAL, the default; p.2180).
fn levels(a: A, rows: []const []const Value, c: usize, order_data: bool) ![]Value {
    var out: std.ArrayList(Value) = .empty;
    for (rows) |r| {
        for (out.items) |v| {
            if (sameValue(v, r[c])) break;
        } else try out.append(a, r[c]);
    }
    if (!order_data) std.mem.sort(Value, out.items, {}, struct {
        fn f(_: void, x: Value, y: Value) bool {
            return lessValue(x, y);
        }
    }.f);
    return out.items;
}
fn levelIndex(ls: []const Value, v: Value) usize {
    for (ls, 0..) |l, k| if (sameValue(l, v)) return k;
    unreachable;
}

pub const Table = struct {
    /// Levels per population variable (parallel to Spec.pop_vars).
    pop_levels: []const []const Value,
    /// Level index tuple of each population, in population order.
    pops: []const []const usize,
    resp_levels: []const Value,
    /// counts[i * J + j]: weighted count of response j in population i.
    counts: []const f64,
    n_obs: usize,
    total: f64,
    freq_missing: f64 = 0,
};

/// A blank character value is missing (SAS character missing).
fn isMissing(v: Value) bool {
    return switch (v) {
        .num => v.isMissing(),
        .str => |t| std.mem.trim(u8, t, " ").len == 0,
    };
}

pub fn tabulate(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Table {
    const a = cx.arena;
    // Missing Values (p. 2220): an observation with a missing MODEL or
    // POPULATION variable, a missing weight or a nonpositive weight is
    // omitted. "Frequency Missing" sums the weights of the observations
    // omitted for missing variable values (SAS reference run: weights 7 and
    // 2 omitted that way give 9; a missing or zero weight adds nothing);
    // "Observations" counts the observations used.
    for (rows) |r| if (s.weight) |wc| {
        if (!r[wc].isMissing() and r[wc].num < 0) return cx.diags.fail(error.ParseError, s.model_line, "The data contain negative weights, which imply negative frequencies.", .{});
    };
    var kept: std.ArrayList([]const Value) = .empty;
    var freq_missing: f64 = 0;
    for (rows) |r| {
        const w: f64 = if (s.weight) |wc| (if (r[wc].isMissing()) continue else r[wc].num) else 1;
        var missing = isMissing(r[s.response]);
        for (s.pop_vars) |c| missing = missing or isMissing(r[c]);
        if (missing) {
            freq_missing += w;
            continue;
        }
        if (w <= 0) continue;
        try kept.append(a, r);
    }
    const used = kept.items;
    if (used.len == 0) return gap(cx, s.model_line, "an input with no usable observations is not implemented", .{});
    return tabulateUsed(cx, s, used, freq_missing);
}

fn tabulateUsed(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, freq_missing: f64) diag.Error!Table {
    const a = cx.arena;
    const pl = try a.alloc([]const Value, s.pop_vars.len);
    for (s.pop_vars, pl) |c, *l| l.* = try levels(a, rows, c, s.order_data);
    const rl = try levels(a, rows, s.response, s.order_data);
    // Populations that occur, ordered lexicographically by level index.
    var pops: std.ArrayList([]const usize) = .empty;
    var keys: std.ArrayList([]usize) = .empty;
    for (rows) |r| {
        const key = try a.alloc(usize, s.pop_vars.len);
        for (s.pop_vars, pl, key) |c, l, *k| k.* = levelIndex(l, r[c]);
        for (keys.items) |o| {
            if (std.mem.eql(usize, o, key)) break;
        } else try keys.append(a, key);
    }
    std.mem.sort([]usize, keys.items, {}, struct {
        fn f(_: void, x: []usize, y: []usize) bool {
            return std.mem.order(usize, x, y) == .lt;
        }
    }.f);
    for (keys.items) |k| try pops.append(a, k);
    const J = rl.len;
    const counts = try a.alloc(f64, pops.items.len * J);
    @memset(counts, 0);
    var total: f64 = 0;
    for (rows) |r| {
        const key = try a.alloc(usize, s.pop_vars.len);
        for (s.pop_vars, pl, key) |c, l, *k| k.* = levelIndex(l, r[c]);
        const i = for (pops.items, 0..) |p, ix| {
            if (std.mem.eql(usize, p, key)) break ix;
        } else unreachable;
        const w: f64 = if (s.weight) |wc| r[wc].num else 1;
        counts[i * J + levelIndex(rl, r[s.response])] += w;
        total += w;
    }
    return .{ .pop_levels = pl, .pops = pops.items, .resp_levels = rl, .counts = counts, .n_obs = rows.len, .total = total, .freq_missing = freq_missing };
}

/// Deviation-from-the-mean design (the last level is coded -1; crossings
/// are products with the first variable varying slowest). Returns the row-
/// major matrix (populations x q) and each effect's column count.
pub const Design = struct { x: []f64, q: usize, cols: []const usize };

pub fn designMatrix(a: A, s: Spec, tb: Table) !Design {
    const cols = try a.alloc(usize, s.effects.len);
    var q: usize = 1;
    for (s.effects, cols) |e, *c| {
        var n: usize = 1;
        for (e.vars) |v| n *= tb.pop_levels[popPos(s, v)].len - 1;
        c.* = n;
        q += n;
    }
    const r = tb.pops.len;
    const x = try a.alloc(f64, r * q);
    for (tb.pops, 0..) |pop, i| {
        x[i * q] = 1;
        var off: usize = 1;
        for (s.effects, cols) |e, n| {
            for (0..n) |k| {
                var rem = k;
                var value: f64 = 1;
                var vi = e.vars.len;
                while (vi > 0) {
                    vi -= 1;
                    const pp = popPos(s, e.vars[vi]);
                    const m = tb.pop_levels[pp].len - 1;
                    const level = rem % m;
                    rem /= m;
                    const have = pop[pp];
                    value *= if (have == level) 1 else if (have == m) -1 else 0;
                }
                x[i * q + off + k] = value;
            }
            off += n;
        }
    }
    return .{ .x = x, .q = q, .cols = cols };
}
fn popPos(s: Spec, v: usize) usize {
    for (s.pop_vars, 0..) |p, k| if (p == v) return k;
    unreachable;
}

// ── Estimation ────────────────────────────────────────────────────────────

pub const Fit = struct {
    beta: []f64,
    cov: []f64,
    /// Functions per population (1 for MEANS, J-1 generalized logits).
    nf: usize,
    /// Residual chi-square (WLS) or likelihood ratio (ML) and its DF.
    resid: f64,
    resid_df: usize,
    /// WLS response functions per population.
    funcs: []const f64 = &.{},
};

fn invert(cx: proc.ProcCtx, m: []const f64, n: usize) diag.Error![]f64 {
    const inv = matrix.inverse(cx.arena, m, n) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return gap(cx, 0, "a singular or ill-conditioned covariance matrix is not implemented", .{}),
    };
    return inv.values;
}

/// Weighted least squares on response means (p.2208 WLS): F_i = sum_j s_j p_ij,
/// V_i = (sum_j s_j^2 p_ij - F_i^2) / n_i, b = (X'V^-1 X)^-1 X'V^-1 F.
pub fn fitMeans(cx: proc.ProcCtx, tb: Table, d: Design) diag.Error!Fit {
    const a = cx.arena;
    const r = tb.pops.len;
    const J = tb.resp_levels.len;
    const q = d.q;
    const f = try a.alloc(f64, r);
    const v = try a.alloc(f64, r);
    for (0..r) |i| {
        var n: f64 = 0;
        var m1: f64 = 0;
        var m2: f64 = 0;
        for (0..J) |j| {
            const c = tb.counts[i * J + j];
            const sc = tb.resp_levels[j].num;
            n += c;
            m1 += c * sc;
            m2 += c * sc * sc;
        }
        f[i] = m1 / n;
        v[i] = (m2 / n - f[i] * f[i]) / n;
        if (!(v[i] > 0)) return gap(cx, 0, "a population with zero response-function variance is not implemented", .{});
    }
    if (q > r) return gap(cx, 0, "models with more parameters than response functions are not implemented", .{});
    const xtx = try a.alloc(f64, q * q);
    const xty = try a.alloc(f64, q);
    @memset(xtx, 0);
    @memset(xty, 0);
    for (0..r) |i| for (0..q) |k| {
        xty[k] += d.x[i * q + k] * f[i] / v[i];
        for (0..q) |l| xtx[k * q + l] += d.x[i * q + k] * d.x[i * q + l] / v[i];
    };
    const cov = try invert(cx, xtx, q);
    const b = try a.alloc(f64, q);
    for (0..q) |k| {
        b[k] = 0;
        for (0..q) |l| b[k] += cov[k * q + l] * xty[l];
    }
    var resid: f64 = 0;
    for (0..r) |i| {
        var fit: f64 = 0;
        for (0..q) |k| fit += d.x[i * q + k] * b[k];
        resid += (f[i] - fit) * (f[i] - fit) / v[i];
    }
    return .{ .beta = b, .cov = cov, .nf = 1, .resid = resid, .resid_df = r - q, .funcs = f };
}

const Logits = struct {
    tb: Table,
    d: Design,
    nf: usize,
    prob: []f64,

    fn probabilities(self: Logits, b: []const f64, i: usize) void {
        const q = self.d.q;
        var denom: f64 = 1;
        for (0..self.nf) |j| {
            var eta: f64 = 0;
            for (0..q) |k| eta += self.d.x[i * q + k] * b[k * self.nf + j];
            self.prob[j] = @exp(eta);
            denom += self.prob[j];
        }
        self.prob[self.nf] = 1;
        for (self.prob) |*v| v.* /= denom;
    }

    /// Log likelihood sum n_ij log p_ij; fills the score g and information h.
    fn evaluate(self: Logits, b: []const f64, g: []f64, h: []f64) f64 {
        const q = self.d.q;
        const nf = self.nf;
        const p = q * nf;
        const J = nf + 1;
        const x = self.d.x;
        const prob = self.prob;
        @memset(g, 0);
        @memset(h, 0);
        var ll: f64 = 0;
        for (0..self.tb.pops.len) |i| {
            self.probabilities(b, i);
            var n: f64 = 0;
            for (0..J) |j| {
                const c = self.tb.counts[i * J + j];
                n += c;
                if (c > 0) ll += c * @log(prob[j]);
            }
            for (0..q) |k| {
                const xk = x[i * q + k];
                if (xk == 0) continue;
                for (0..nf) |j| {
                    g[k * nf + j] += xk * (self.tb.counts[i * J + j] - n * prob[j]);
                    for (0..q) |l| {
                        const xl = x[i * q + l];
                        if (xl == 0) continue;
                        for (0..nf) |m| {
                            const dd: f64 = if (j == m) 1 else 0;
                            h[(k * nf + j) * p + l * nf + m] += n * xk * xl * prob[j] * (dd - prob[m]);
                        }
                    }
                }
            }
        }
        return ll;
    }
};

/// Maximum likelihood for generalized logits log(p_ij / p_iJ) = x_i' b_j by
/// Newton-Raphson. Parameter (k, j) sits at index k * (J-1) + j, the order of
/// the estimates table. The likelihood ratio is 2 sum n_ij log(n_ij / m_ij).
pub fn fitLogits(cx: proc.ProcCtx, tb: Table, d: Design) diag.Error!Fit {
    const a = cx.arena;
    const r = tb.pops.len;
    const J = tb.resp_levels.len;
    if (J < 2) return gap(cx, 0, "a response with a single level is not implemented", .{});
    const nf = J - 1;
    const q = d.q;
    const p = q * nf;
    if (p > r * nf) return gap(cx, 0, "models with more parameters than response functions are not implemented", .{});
    const b = try a.alloc(f64, p);
    @memset(b, 0);
    const trial = try a.alloc(f64, p);
    const g = try a.alloc(f64, p);
    const h = try a.alloc(f64, p * p);
    const g2 = try a.alloc(f64, p);
    const h2 = try a.alloc(f64, p * p);
    const prob = try a.alloc(f64, J);
    const lg = Logits{ .tb = tb, .d = d, .nf = nf, .prob = prob };
    // Newton-Raphson from 0 with step halving; stop when the proportional
    // change in the log likelihood is below EPSILON=1E-8 (MODEL EPSILON=,
    // "Maximum Likelihood Method", S154 Chapter 36).
    var ll = lg.evaluate(b, g, h);
    var converged = false;
    var last_inv: []f64 = &.{};
    var iter: usize = 0;
    while (iter < 20) : (iter += 1) {
        const inv = try invert(cx, h, p);
        last_inv = inv;
        var dir = try a.alloc(f64, p);
        for (0..p) |k| {
            dir[k] = 0;
            for (0..p) |l| dir[k] += inv[k * p + l] * g[l];
        }
        var lambda: f64 = 1;
        var ll_new: f64 = 0;
        var halvings: usize = 0;
        while (true) {
            for (0..p) |k| trial[k] = b[k] + lambda * dir[k];
            ll_new = lg.evaluate(trial, g2, h2);
            if (ll_new >= ll or halvings == 10) break;
            lambda /= 2;
            halvings += 1;
        }
        if (halvings == 10) return gap(cx, 0, "maximum likelihood step-halving failure is not implemented", .{});
        @memcpy(b, trial);
        @memcpy(g, g2);
        @memcpy(h, h2);
        const change = @abs(ll_new - ll) / @abs(ll_new);
        ll = ll_new;
        if (change < 1e-8) {
            converged = true;
            break;
        }
    }
    // MAXITER=20 is the documented default (MODEL MAXITER=).
    if (!converged) return gap(cx, 0, "maximum likelihood that does not converge is not implemented", .{});
    // The covariance is the inverse information at the start of the last
    // iteration: the reference listing (school data, saturated model) shows
    // 23.25 / 0.2277 from it, against 23.24 / 0.2278 at the final estimates.
    const cov = last_inv;
    var lr: f64 = 0;
    for (0..r) |i| {
        var n: f64 = 0;
        lg.probabilities(b, i);
        for (0..J) |j| n += tb.counts[i * J + j];
        for (0..J) |j| {
            const c = tb.counts[i * J + j];
            if (c > 0) lr += 2 * c * @log(c / (n * prob[j]));
        }
    }
    return .{ .beta = b, .cov = cov, .nf = nf, .resid = @max(lr, 0), .resid_df = r * nf - p };
}

/// Wald chi-square for parameters [lo, hi): b' (Cov_sub)^-1 b.
pub fn wald(cx: proc.ProcCtx, f: Fit, lo: usize, hi: usize) diag.Error!f64 {
    const a = cx.arena;
    const n = hi - lo;
    const p = f.beta.len;
    const sub = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        sub[i * n + j] = f.cov[(lo + i) * p + lo + j];
    };
    const inv = try invert(cx, sub, n);
    var w: f64 = 0;
    for (0..n) |i| for (0..n) |j| {
        w += f.beta[lo + i] * inv[i * n + j] * f.beta[lo + j];
    };
    return w;
}

// ── Listing ───────────────────────────────────────────────────────────────

fn fixed(a: A, x: f64, comptime decimals: u8) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return fixed(a, p, 4);
}
/// Estimates and standard errors: four decimals, more for |x| < 0.01 so that
/// three significant digits show (reference: -0.00749 beside 1.0491).
// ponytail: the template's D10.4-like rule, verified only for |x| >= 0.001.
fn estimate(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    const ax = @abs(x);
    if (ax != 0 and ax < 0.001) return gap(cx, 0, "displaying estimates below 0.001 in magnitude is not implemented", .{});
    if (ax >= 10000) return gap(cx, 0, "displaying estimates of 10000 or more is not implemented", .{});
    if (ax != 0 and ax < 0.01) return fixed(cx.arena, x, 5);
    return fixed(cx.arena, x, 4);
}
fn chisq(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    if (x >= 1e8) return gap(cx, 0, "chi-square values of 1E8 or more are not implemented", .{});
    return fixed(cx.arena, x, 2);
}
fn levelText(a: A, v: Value) ![]const u8 {
    return std.mem.trim(u8, try proc.cellText(a, v), " ");
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn emit(a: A, out: *Out, b: []const u8) !void {
    try out.appendSlice(a, std.mem.trimEnd(u8, b, " "));
    try out.append(a, '\n');
}
fn dashes(a: A, out: *Out, w: usize) !void {
    try out.appendNTimes(a, '-', w);
    try out.append(a, '\n');
}

fn dataSummary(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table) !void {
    const a = cx.arena;
    const cols = s.ds.columns.items;
    const upper = try std.ascii.allocUpperString(a, s.ds.name);
    const dsname = if (std.mem.indexOfScalar(u8, upper, '.')) |k| (if (std.mem.startsWith(u8, upper, "WORK.")) upper[k + 1 ..] else upper) else upper;
    // ponytail: the Data Summary column widths are verified for whole-number
    // frequencies only; a fractional total changes the template's widths.
    if (tb.total != @floor(tb.total) or tb.freq_missing != @floor(tb.freq_missing)) return gap(cx, s.model_line, "the Data Summary for fractional frequencies is not implemented", .{});
    const v1 = [_][]const u8{ cols[s.response].name, if (s.weight) |wc| cols[wc].name else "None", dsname, try format.bestNum(a, tb.freq_missing) };
    var w1: usize = 0;
    for (v1) |v| w1 = @max(w1, v.len);
    w1 += 5;
    const n2 = [_][]const u8{
        try std.fmt.allocPrint(a, "{d}", .{tb.resp_levels.len}),
        try std.fmt.allocPrint(a, "{d}", .{tb.pops.len}),
        try format.bestNum(a, tb.total),
        try std.fmt.allocPrint(a, "{d}", .{tb.n_obs}),
    };
    var nw: usize = 0;
    for (n2) |v| nw = @max(nw, v.len);
    const l1 = [_][]const u8{ "Response", "Weight Variable", "Data Set", "Frequency Missing" };
    const l2 = [_][]const u8{ "Response Levels", "Populations", "Total Frequency", "Observations" };
    const width = 19 + w1 + 17 + nw;
    try centered(a, out, "Data Summary", width);
    try out.append(a, '\n');
    for (0..4) |k| {
        const b = try proc.line(a, width);
        proc.putLeft(b, 1, l1[k]);
        proc.putLeft(b, 20, v1[k]);
        proc.putLeft(b, 20 + w1, l2[k]);
        proc.putRight(b, width, n2[k]);
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

fn profiles(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table) !void {
    const a = cx.arena;
    const cols = s.ds.columns.items;
    const widths = try a.alloc(usize, s.pop_vars.len);
    var width: usize = 10;
    for (s.pop_vars, tb.pop_levels, widths) |c, ls, *w| {
        w.* = cols[c].name.len;
        for (ls) |l| w.* = @max(w.*, (try levelText(a, l)).len);
        width += w.* + 4;
    }
    width += 11;
    try centered(a, out, "Population Profiles", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putLeft(b, 1, "Sample");
    var col: usize = 11;
    for (s.pop_vars, widths) |c, w| {
        proc.putLeft(b, col, cols[c].name);
        col += w + 4;
    }
    proc.putLeft(b, col, "Sample Size");
    try emit(a, out, b);
    try dashes(a, out, width);
    for (tb.pops, 0..) |pop, i| {
        b = try proc.line(a, width);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{i + 1}));
        col = 11;
        for (pop, tb.pop_levels, widths) |k, ls, w| {
            proc.putLeft(b, col, try levelText(a, ls[k]));
            col += w + 4;
        }
        var n: f64 = 0;
        for (0..tb.resp_levels.len) |j| n += tb.counts[i * tb.resp_levels.len + j];
        proc.putRight(b, width, try format.bestNum(a, n));
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
    // Response Profiles.
    var rw: usize = cols[s.response].name.len;
    for (tb.resp_levels) |l| rw = @max(rw, (try levelText(a, l)).len);
    const width2 = 12 + rw;
    try centered(a, out, "Response Profiles", width2);
    try out.appendSlice(a, " \n");
    b = try proc.line(a, width2);
    proc.putLeft(b, 1, "Response");
    proc.putLeft(b, 13, cols[s.response].name);
    try emit(a, out, b);
    try dashes(a, out, width2);
    for (tb.resp_levels, 0..) |l, j| {
        b = try proc.line(a, width2);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{j + 1}));
        proc.putLeft(b, 13, try levelText(a, l));
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

fn designTable(cx: proc.ProcCtx, out: *Out, tb: Table, d: Design, f: Fit) !void {
    const a = cx.arena;
    const width = 20 + 9 * d.q;
    try centered(a, out, "Response Functions and Design Matrix", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putRight(b, 20, "Response");
    const span = 9 * d.q - 2;
    proc.putLeft(b, 22 + (span - 12) / 2 + 2, "Design Matrix");
    try emit(a, out, b);
    b = try proc.line(a, width);
    proc.putLeft(b, 1, "Sample");
    proc.putRight(b, 20, "Function");
    for (0..d.q) |k| proc.putRight(b, 20 + 9 * (k + 1), try std.fmt.allocPrint(a, "{d}", .{k + 1}));
    try emit(a, out, b);
    try dashes(a, out, width);
    for (0..tb.pops.len) |i| {
        b = try proc.line(a, width);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{i + 1}));
        proc.putRight(b, 20, try fixed(a, f.funcs[i], 5));
        for (0..d.q) |k| proc.putRight(b, 20 + 9 * (k + 1), try fixed(a, d.x[i * d.q + k], 0));
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

fn anovaTable(cx: proc.ProcCtx, out: *Out, s: Spec, d: Design, f: Fit) diag.Error!void {
    const a = cx.arena;
    const last = if (s.means) "Residual" else "Likelihood Ratio";
    var sw: usize = @max(9, last.len);
    for (s.effects) |e| sw = @max(sw, e.name.len);
    const width = sw + 7 + 13 + 14;
    try centered(a, out, if (s.means) "Analysis of Variance" else "Maximum Likelihood Analysis of Variance", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putLeft(b, 1, "Source");
    proc.putRight(b, sw + 7, "DF");
    proc.putRight(b, sw + 20, "Chi-Square");
    proc.putRight(b, width, "Pr > ChiSq");
    try emit(a, out, b);
    try dashes(a, out, width);
    var lo: usize = 0;
    for (0..s.effects.len + 1) |e| {
        const n = (if (e == 0) 1 else d.cols[e - 1]) * f.nf;
        const w = try wald(cx, f, lo, lo + n);
        lo += n;
        b = try proc.line(a, width);
        proc.putLeft(b, 1, if (e == 0) "Intercept" else s.effects[e - 1].name);
        proc.putRight(b, sw + 7, try std.fmt.allocPrint(a, "{d}", .{n}));
        proc.putRight(b, sw + 20, try chisq(cx, w));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(w, @floatFromInt(n))));
        try emit(a, out, b);
    }
    try out.append(a, '\n');
    b = try proc.line(a, width);
    proc.putLeft(b, 1, last);
    proc.putRight(b, sw + 7, try std.fmt.allocPrint(a, "{d}", .{f.resid_df}));
    if (f.resid_df == 0) {
        proc.putRight(b, sw + 18, ".");
        proc.putRight(b, width - 4, ".");
    } else {
        proc.putRight(b, sw + 20, try chisq(cx, f.resid));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(f.resid, @floatFromInt(f.resid_df))));
    }
    try emit(a, out, b);
    try out.appendSlice(a, "\n\n");
}

const Param = struct { effect: []const u8, level: []const u8 };

fn paramLabels(a: A, s: Spec, tb: Table, d: Design) ![]Param {
    const out = try a.alloc(Param, d.q);
    out[0] = .{ .effect = "Intercept", .level = "" };
    var off: usize = 1;
    for (s.effects, d.cols) |e, n| {
        for (0..n) |k| {
            var parts: std.ArrayList([]const u8) = .empty;
            var rem = k;
            var vi = e.vars.len;
            while (vi > 0) {
                vi -= 1;
                const pp = popPos(s, e.vars[vi]);
                const m = tb.pop_levels[pp].len - 1;
                try parts.insert(a, 0, try levelText(a, tb.pop_levels[pp][rem % m]));
                rem /= m;
            }
            out[off + k] = .{ .effect = e.name, .level = try std.mem.join(a, " ", parts.items) };
        }
        off += n;
    }
    return out;
}

fn estimatesTable(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table, d: Design, f: Fit) diag.Error!void {
    const a = cx.arena;
    const labels = try paramLabels(a, s, tb, d);
    var ew: usize = 9;
    var lw: usize = 0;
    for (labels) |l| {
        ew = @max(ew, l.effect.len);
        lw = @max(lw, l.level.len);
    }
    const pw = ew + 1 + lw;
    const fn_w: usize = if (s.means) 0 else 9;
    const width = pw + fn_w + 12 + 11 + 12 + 14;
    const est = pw + fn_w + 12;
    try centered(a, out, if (s.means) "Analysis of Weighted Least Squares Estimates" else "Analysis of Maximum Likelihood Estimates", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    if (!s.means) proc.putRight(b, pw + 9, "Function");
    proc.putRight(b, est + 11, "Standard");
    proc.putRight(b, est + 23, "Chi-");
    try emit(a, out, b);
    b = try proc.line(a, width);
    proc.putLeft(b, 1, "Parameter");
    if (!s.means) proc.putLeft(b, pw + 3, "Number");
    proc.putRight(b, est, "Estimate");
    proc.putRight(b, est + 11, "Error");
    proc.putRight(b, est + 23, "Square");
    proc.putRight(b, width, "Pr > ChiSq");
    try emit(a, out, b);
    try dashes(a, out, width);
    const p = f.beta.len;
    for (labels, 0..) |l, k| for (0..f.nf) |j| {
        const ix = k * f.nf + j;
        const se = @sqrt(f.cov[ix * p + ix]);
        const w = f.beta[ix] * f.beta[ix] / (se * se);
        b = try proc.line(a, width);
        const first_of_effect = j == 0 and (k == 0 or !std.mem.eql(u8, labels[k - 1].effect, l.effect));
        if (first_of_effect) proc.putLeft(b, 1, l.effect);
        if (l.level.len > 0) proc.putLeft(b, ew + 2, l.level);
        if (!s.means) proc.putLeft(b, pw + 5, try std.fmt.allocPrint(a, "{d}", .{j + 1}));
        proc.putRight(b, est, try estimate(cx, f.beta[ix]));
        proc.putRight(b, est + 11, try estimate(cx, se));
        proc.putRight(b, est + 23, try chisq(cx, w));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(w, 1)));
        try emit(a, out, b);
    };
}

/// Computes and renders one analysis of one BY group.
pub fn analyze(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value) diag.Error!void {
    const a = cx.arena;
    const tb = try tabulate(cx, s, rows);
    for (s.effects) |e| for (e.vars) |v| if (tb.pop_levels[popPos(s, v)].len < 2) return gap(cx, s.model_line, "an effect variable with a single level is not implemented", .{});
    const d = try designMatrix(a, s, tb);
    const f = if (s.means) try fitMeans(cx, tb, d) else try fitLogits(cx, tb, d);
    var b: Out = .empty;
    try b.appendSlice(a, "\nThe CATMOD Procedure\n\n");
    try dataSummary(cx, &b, s, tb);
    try profiles(cx, &b, s, tb);
    if (s.design) try designTable(cx, &b, tb, d, f);
    if (!s.means) {
        try b.appendSlice(a, "                   Maximum Likelihood Analysis\n\n           Maximum likelihood computations converged.\n\n\n");
    }
    try anovaTable(cx, &b, s, d, f);
    try estimatesTable(cx, &b, s, tb, d, f);
    if (!s.noprint) try out.appendSlice(a, b.items);
}

fn execute(cx: proc.ProcCtx, out: *Out, st: State) diag.Error!void {
    const s = try resolve(cx, st);
    const input = try proc.procInputObs(cx.arena, s.ds, st.proc_stmt, cx.diags);
    var sp = s;
    sp.ds = input.ds;
    const slices = try by.checkedSlices(cx.arena, sp.ds, sp.by_cols, sp.by_desc, sp.by_notsorted, cx.diags);
    // Every group is computed before any text exists (fail loud, no partial listing).
    var groups: std.ArrayList(Out) = .empty;
    for (slices) |slice| {
        var g: Out = .empty;
        if (sp.by_cols.len > 0) try by.appendLine(cx.arena, &g, sp.ds, slice.rep.?, sp.by_cols);
        try analyze(cx, &g, sp, slice.rows);
        try groups.append(cx.arena, g);
    }
    for (groups.items) |g| try out.appendSlice(cx.arena, g.items);
}

// ── Interactive procedure state ───────────────────────────────────────────

var open = false;
var retained_arena: ?std.heap.ArenaAllocator = null;
var retained: State = .{};

fn forget() void {
    open = false;
    retained = .{};
    if (retained_arena) |*arena| arena.deinit();
    retained_arena = null;
}

fn keep(slice: []const Token) ![]const Token {
    const k = retained_arena.?.allocator();
    const copy = try k.alloc(Token, slice.len);
    for (slice, copy) |t, *c| {
        c.* = t;
        c.text = try k.dupe(u8, t.text);
    }
    return copy;
}

/// Applies statements to `st`; a RUN with a MODEL in effect runs the analysis.
/// Returns false when the procedure closes (QUIT or BY processing).
fn statements(cx: proc.ProcCtx, out: *Out, st: *State, t: []const Token, start: usize) diag.Error!bool {
    var i = start;
    var pending = false;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const stmt = t[i..end];
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "run") or eq(word, "quit")) {
            if (stmt.len != 1) return invalid(cx, t, i + 1);
            if (pending) {
                try execute(cx, out, st.*);
                pending = false;
                if (st.by_stmt != null) {
                    try cx.diags.note(t[i].line, "Interactivity disabled with BY processing.", .{});
                    return false;
                }
            }
            if (eq(word, "quit")) return false;
        } else if (eq(word, "model")) {
            st.model = try keep(stmt);
            pending = true;
        } else if (eq(word, "weight")) {
            st.weight = try keep(stmt);
        } else if (eq(word, "response")) {
            st.response = try keep(stmt);
        } else if (eq(word, "population")) {
            st.population = try keep(stmt);
        } else if (eq(word, "by")) {
            if (st.model != null and !pending) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: a BY statement must precede the first RUN", .{});
            st.by_stmt = try keep(stmt);
        } else if (oneOf(word, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{word});
        } else if (eq(word, "where")) {
            return gap(cx, t[i].line, "the WHERE statement is not implemented", .{});
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // ponytail: a MODEL waiting for a RUN at end of input runs as SAS does
    // at step end.
    if (pending) try execute(cx, out, st.*);
    return true;
}

/// CLI entry: the PROC CATMOD step through its first RUN. The procedure
/// stays open for later RUN groups unless QUIT or BY closed it (p.2180).
pub fn runStep(cx: proc.ProcCtx, out: *Out, t: []const Token) diag.Error!void {
    forget();
    var end: usize = 0;
    while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
    if (!at(t, end, .semicolon)) return invalid(cx, t, end);
    retained_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var st: State = .{ .proc_stmt = try keep(t[0..end]) };
    // Validate the PROC statement before any statement runs.
    var probe: Spec = .{ .ds = undefined };
    try parseProc(cx, &probe, st.proc_stmt);
    const stays = try statements(cx, out, &st, t, end + 1);
    if (!stays) {
        forget();
        return;
    }
    retained = st;
    open = true;
}

/// Statement group arriving after an open PROC CATMOD step. Returns true when
/// consumed here; any other step closes the procedure.
pub fn continuation(cx: proc.ProcCtx, out: *Out, t: []const Token) diag.Error!bool {
    if (!open) return false;
    if (t.len == 0 or t[0].tag != .name) return false;
    if (!oneOf(t[0].text, &.{ "model", "weight", "response", "population", "run", "quit", "by", "where", "contrast", "direct", "factors", "loglin", "repeated", "restrict" })) {
        forget();
        return false;
    }
    var st = retained;
    const stays = statements(cx, out, &st, t, 0) catch |e| {
        retained = st;
        return e;
    };
    if (!stays) {
        forget();
        return true;
    }
    retained = st;
    return true;
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "STAT-CATMOD-001 deviation coding of a crossed effect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "t");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    const lv = [_]Value{ .{ .num = 1 }, .{ .num = 2 } };
    const lw = [_]Value{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 3 } };
    const effects = [_]Effect{ .{ .name = "a", .vars = &.{0} }, .{ .name = "b", .vars = &.{1} }, .{ .name = "a*b", .vars = &.{ 0, 1 } } };
    const s: Spec = .{ .ds = &ds, .pop_vars = &.{ 0, 1 }, .effects = &effects };
    const pops = [_][]const usize{ &.{ 0, 0 }, &.{ 0, 2 }, &.{ 1, 1 } };
    const tb: Table = .{ .pop_levels = &.{ &lv, &lw }, .pops = &pops, .resp_levels = &.{}, .counts = &.{}, .n_obs = 0, .total = 0 };
    const d = try designMatrix(a, s, tb);
    try std.testing.expectEqual(@as(usize, 6), d.q);
    // (a=1, b=1): 1 | 1 | 1 0 | 1 0
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 1, 0, 1, 0 }, d.x[0..6]);
    // (a=1, b=3): 1 | 1 | -1 -1 | -1 -1
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, -1, -1, -1, -1 }, d.x[6..12]);
    // (a=2, b=2): 1 | -1 | 0 1 | 0 -1
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, 0, 1, 0, -1 }, d.x[12..18]);
}

test "STAT-CATMOD-001 WLS means and ML logits by hand on a saturated two-population table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d0 = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = undefined, .diags = &d0 };
    // Two populations, responses 0/1 with counts (10, 30) and (20, 20).
    const lv = [_]Value{ .{ .num = 1 }, .{ .num = 2 } };
    const rl = [_]Value{ .{ .num = 0 }, .{ .num = 1 } };
    const pops = [_][]const usize{ &.{0}, &.{1} };
    const tb: Table = .{ .pop_levels = &.{&lv}, .pops = &pops, .resp_levels = &rl, .counts = &.{ 10, 30, 20, 20 }, .n_obs = 4, .total = 80 };
    const d: Design = .{ .x = @constCast(&[_]f64{ 1, 1, 1, -1 }), .q = 2, .cols = &.{1} };
    const m = try fitMeans(cx, tb, d);
    // F = 0.75, 0.5: b0 = 0.625, b1 = 0.125; saturated residual 0.
    try std.testing.expectApproxEqAbs(@as(f64, 0.625), m.beta[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.125), m.beta[1], 1e-12);
    try std.testing.expectEqual(@as(usize, 0), m.resid_df);
    // Var(b1) = (V1 + V2) / 4 with V1 = .75*.25/40, V2 = .25/40.
    try std.testing.expectApproxEqAbs((0.1875 / 40.0 + 0.25 / 40.0) / 4.0, m.cov[3], 1e-15);
    const l = try fitLogits(cx, tb, d);
    // logit(p_0 / p_1) = log(1/3), log(1): b0 = -log(3)/2, b1 = -log(3)/2.
    try std.testing.expectApproxEqAbs(-@log(3.0) / 2.0, l.beta[0], 1e-9);
    try std.testing.expectApproxEqAbs(-@log(3.0) / 2.0, l.beta[1], 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0), l.resid, 1e-9);
}
