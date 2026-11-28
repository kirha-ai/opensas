//! PROC STEPDISC declarations, roles and the default stepwise listing,
//! SAS/STAT 15.4 Chapter 117 (PROC STEPDISC statement pp.9559-9563, BY
//! pp.9563-9564, CLASS/FREQ/VAR p.9564, WEIGHT pp.9564-9565, Missing Values
//! p.9565, Input Data Sets pp.9565-9566). Class summaries and the within (E)
//! and total (T) SSCP matrices come from the PROC CANDISC kernel (read-only
//! reuse). Stepwise selection is by partial F of the ANCOVA of each candidate
//! on the class, given the variables already in the model:
//!   partial R2 = 1 - E_xx.S / T_xx.S,  F = (R2/(c-1)) / ((1-R2)/(n-c-|S|)).
//! Everything not verified against the SAS reference is a D-009 gap (rc 2)
//! raised before any listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const varlist = @import("variable_lists.zig");
const candisc = @import("candisc.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    base: candisc.Spec,
    slentry: f64 = 0.15,
    slstay: f64 = 0.15,
    singular: f64 = 1e-8,
    maxstep: ?usize = null,
    short: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC STEPDISC: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC STEPDISC: " ++ text, args);
}

/// Documented PROC STEPDISC options (Table 117.1) that this ticket does not implement.
const option_gaps = [_][]const u8{ "maxmacro", "pr2entry", "pr2e", "pr2stay", "pr2s", "include", "start", "stop", "all", "bcorr", "bcov", "bsscp", "pcorr", "pcov", "psscp", "simple", "stdmean", "tcorr", "tcov", "tsscp", "wcorr", "wcov", "wsscp" };

/// A probability-valued option: 0 <= p <= 1 (SLENTRY=, SLSTAY=), or
/// 0 < p < 1 (SINGULAR=, `open`).
fn probability(cx: proc.ProcCtx, t: []const lex.Token, i: usize, open: bool) diag.Error!f64 {
    if (!at(t, i, .number)) return invalid(cx, t, i);
    const x = std.fmt.parseFloat(f64, t[i].text) catch return invalid(cx, t, i);
    const ok = if (open) x > 0 and x < 1 else x >= 0 and x <= 1;
    if (!ok) return user(cx, t[i].line, "PROC STEPDISC: the value {s} is out of range for {s}=.", .{ t[i].text, try std.ascii.allocUpperString(cx.arena, t[i - 2].text) });
    return x;
}

/// Splits the PROC statement: STEPDISC options are consumed here and the
/// remaining tokens (DATA= and the role statements) go to the CANDISC parser,
/// which owns the shared CLASS/VAR/BY/FREQ/WEIGHT/missing-value rules.
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .base = undefined };
    var kept: std.ArrayList(lex.Token) = .empty;
    try kept.appendSlice(a, t[0..@min(t.len, 2)]);
    var i: usize = 2;
    var depth: usize = 0;
    var sle_seen = false;
    var sls_seen = false;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (depth > 0 or !at(t, i, .name)) {
            if (at(t, i, .lparen)) depth += 1;
            if (at(t, i, .rparen) and depth > 0) depth -= 1;
            try kept.append(a, t[i]);
            i += 1;
            continue;
        }
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (valued and (eq(word, "slentry") or eq(word, "sle"))) {
            s.slentry = try probability(cx, t, i + 2, false);
            sle_seen = true;
            i += 3;
        } else if (valued and (eq(word, "slstay") or eq(word, "sls"))) {
            s.slstay = try probability(cx, t, i + 2, false);
            sls_seen = true;
            i += 3;
        } else if (valued and eq(word, "singular")) {
            s.singular = try probability(cx, t, i + 2, true);
            i += 3;
        } else if (valued and eq(word, "maxstep")) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const x = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (x != @floor(x) or x < 0) return invalid(cx, t, i + 2);
            s.maxstep = @intFromFloat(x);
            i += 3;
        } else if (!valued and eq(word, "short")) {
            s.short = true;
            i += 1;
        } else if (valued and eq(word, "method")) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const m = t[i + 2].text;
            if (eq(m, "backward") or eq(m, "bw") or eq(m, "forward") or eq(m, "fw"))
                return gap(cx, t[i].line, "METHOD={s} is not implemented (owned by a later STEPDISC ticket)", .{m});
            if (!(eq(m, "stepwise") or eq(m, "sw"))) return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "data") and valued) {
            try kept.appendSlice(a, t[i .. i + 2]);
            i += 2;
        } else if (eq(word, "out") or eq(word, "outstat") or eq(word, "ncan") or eq(word, "prefix") or eq(word, "noprint")) {
            // CANDISC-only options are not STEPDISC syntax.
            return invalid(cx, t, i);
        } else {
            for (option_gaps) |g| if (eq(word, g)) return gap(cx, t[i].line, "the {s} option is not implemented (owned by a later STEPDISC ticket)", .{try std.ascii.allocUpperString(a, word)});
            // DATA= member names (and dotted librefs) pass through.
            if (kept.items.len > 0 and kept.items[kept.items.len - 1].tag == .eq or (kept.items.len > 0 and kept.items[kept.items.len - 1].tag == .dot)) {
                try kept.append(a, t[i]);
                i += 1;
                continue;
            }
            return invalid(cx, t, i);
        }
    }
    // SAS 9.4 reference: either significance level alone sets both.
    if (sle_seen and !sls_seen) s.slstay = s.slentry;
    if (sls_seen and !sle_seen) s.slentry = s.slstay;
    try kept.appendSlice(a, t[i..]);
    const sub = proc.ProcCtx{ .arena = a, .lib = cx.lib, .diags = cx.diags, .listing = cx.listing, .listing_titles = cx.listing_titles };
    s.base = candisc.parse(sub, kept.items) catch |e| return e;
    return s;
}

// ── Selection ───────────────────────────────────────────────────────────────

/// M_xx - M_xS M_SS^-1 M_Sx for the index set `set` (Gaussian elimination
/// with partial pivoting; p <= 16).
fn resid(m: []const f64, p: usize, set: []const usize, x: usize) f64 {
    const k = set.len;
    if (k == 0) return m[x * p + x];
    var g: [16 * 17]f64 = undefined;
    const w = k + 1;
    for (set, 0..) |si, r| {
        for (set, 0..) |sj, c| g[r * w + c] = m[si * p + sj];
        g[r * w + k] = m[si * p + x];
    }
    for (0..k) |col| {
        var piv = col;
        for (col + 1..k) |r| if (@abs(g[r * w + col]) > @abs(g[piv * w + col])) {
            piv = r;
        };
        if (g[piv * w + col] == 0) return 0;
        if (piv != col) for (0..w) |c| std.mem.swap(f64, &g[col * w + c], &g[piv * w + c]);
        for (col + 1..k) |r| {
            const f = g[r * w + col] / g[col * w + col];
            for (col..w) |c| g[r * w + c] -= f * g[col * w + c];
        }
    }
    var y: [16]f64 = undefined;
    var r: usize = k;
    while (r > 0) {
        r -= 1;
        var v = g[r * w + k];
        for (r + 1..k) |c| v -= g[r * w + c] * y[c];
        y[r] = v / g[r * w + r];
    }
    var out = m[x * p + x];
    for (set, 0..) |si, j| out -= m[x * p + si] * y[j];
    return out;
}

fn without(buf: []usize, set: []const usize, drop: usize) []usize {
    var n: usize = 0;
    for (set) |v| if (v != drop) {
        buf[n] = v;
        n += 1;
    };
    return buf[0..n];
}

fn sortedWith(buf: []usize, set: []const usize, add: usize) []usize {
    var n: usize = 0;
    var placed = false;
    for (set) |v| {
        if (!placed and add < v) {
            buf[n] = add;
            n += 1;
            placed = true;
        }
        buf[n] = v;
        n += 1;
    }
    if (!placed) {
        buf[n] = add;
        n += 1;
    }
    return buf[0..n];
}

pub const Partial = struct { v: usize, rsq: f64, f: f64, prob: f64, tol: f64 = 1 };

fn fTail(f: f64, d1: f64, d2: f64) f64 {
    if (!(f >= 0)) return std.math.nan(f64);
    return proc.betai(d2 / 2, d1 / 2, d2 / (d2 + d1 * f));
}

pub const Multi = struct { wilks: f64, wf: f64, wd1: f64, wd2: f64, wprob: f64, pillai: f64, pf: f64, pd1: f64, pd2: f64, pprob: f64, ascc: f64 };

pub const Ctx = struct {
    e: []const f64,
    t: []const f64,
    p: usize,
    q: f64, // c - 1
    dfe: f64, // n - c

    pub fn partial(c: Ctx, set: []const usize, x: usize) Partial {
        const e = resid(c.e, c.p, set, x);
        const t = resid(c.t, c.p, set, x);
        const rsq = 1 - e / t;
        const d2 = c.dfe - @as(f64, @floatFromInt(set.len));
        const f = (rsq / c.q) / ((1 - rsq) / d2);
        return .{ .v = x, .rsq = rsq, .f = f, .prob = fTail(f, c.q, d2) };
    }

    /// Entry tolerance (SINGULAR=, p.9562): the smallest of 1 - R2 of x on the
    /// model and of each model variable on the others plus x. ponytail: the
    /// SAS 9.4 reference listing computes these squared multiple correlations
    /// from the total-sample SSCP (the pooled-within values do not match).
    pub fn tolerance(c: Ctx, set: []const usize, x: usize) f64 {
        var tol = resid(c.t, c.p, set, x) / c.t[x * c.p + x];
        var b1: [16]usize = undefined;
        var b2: [16]usize = undefined;
        const with = sortedWith(&b1, set, x);
        for (set) |v| tol = @min(tol, resid(c.t, c.p, without(&b2, with, v), v) / c.t[v * c.p + v]);
        return tol;
    }

    pub fn multi(c: Ctx, set: []const usize) Multi {
        var lambda: f64 = 1;
        var b: [16]usize = undefined;
        for (set, 0..) |v, k| {
            const prev = b[0..k];
            lambda *= resid(c.e, c.p, prev, v) / resid(c.t, c.p, prev, v);
            b[k] = v;
        }
        // Pillai's trace V = tr(H T^-1) = |S| - tr(E T^-1), from the sweep
        // identity tr(E_S T_S^-1) computed column by column.
        const k = set.len;
        var et: f64 = 0;
        for (0..k) |j| {
            // (T^-1)_jj-weighted: tr(E T^-1) = sum_ij E_ij (T^-1)_ji.
            for (0..k) |i| et += c.e[set[i] * c.p + set[j]] * inverseEntry(c.t, c.p, set, j, i);
        }
        const pp: f64 = @floatFromInt(k);
        const v = pp - et;
        const q = c.q;
        // Rao's F for Wilks' lambda.
        const den = pp * pp + q * q - 5;
        const tt = if (den > 0) @sqrt((pp * pp * q * q - 4) / den) else 1;
        const rr = c.dfe - (pp - q + 1) / 2;
        const u = (pp * q - 2) / 4;
        const pw = std.math.pow(f64, lambda, 1 / tt);
        const wd1 = pp * q;
        const wd2 = rr * tt - 2 * u;
        const wf = (1 - pw) / pw * wd2 / wd1;
        const s = @min(pp, q);
        const m = (@abs(pp - q) - 1) / 2;
        const n = (c.dfe - pp - 1) / 2;
        const pf = (2 * n + s + 1) / (2 * m + s + 1) * v / (s - v);
        const pd1 = s * (2 * m + s + 1);
        const pd2 = s * (2 * n + s + 1);
        return .{ .wilks = lambda, .wf = wf, .wd1 = wd1, .wd2 = wd2, .wprob = fTail(wf, wd1, wd2), .pillai = v, .pf = pf, .pd1 = pd1, .pd2 = pd2, .pprob = fTail(pf, pd1, pd2), .ascc = v / q };
    }
};

/// Entry (r, col) of (M_SS)^-1, by solving M_SS y = e_col.
fn inverseEntry(m: []const f64, p: usize, set: []const usize, r: usize, col: usize) f64 {
    const k = set.len;
    var g: [16 * 17]f64 = undefined;
    const w = k + 1;
    for (0..k) |i| {
        for (0..k) |j| g[i * w + j] = m[set[i] * p + set[j]];
        g[i * w + k] = if (i == col) 1 else 0;
    }
    for (0..k) |c| {
        var piv = c;
        for (c + 1..k) |i| if (@abs(g[i * w + c]) > @abs(g[piv * w + c])) {
            piv = i;
        };
        if (piv != c) for (0..w) |j| std.mem.swap(f64, &g[c * w + j], &g[piv * w + j]);
        for (c + 1..k) |i| {
            const f = g[i * w + c] / g[c * w + c];
            for (c..w) |j| g[i * w + j] -= f * g[c * w + j];
        }
    }
    var y: [16]f64 = undefined;
    var i: usize = k;
    while (i > 0) {
        i -= 1;
        var v = g[i * w + k];
        for (i + 1..k) |j| v -= g[i * w + j] * y[j];
        y[i] = v / g[i * w + i];
    }
    return y[r];
}

pub const StepKind = enum { entered, removed };
pub const Step = struct {
    removal: ?[]Partial, // null at step 1 (empty model)
    removed: ?usize = null,
    entry: ?[]Partial = null, // null when no candidate remains
    entered: ?usize = null,
    set: []usize, // model after the step, in VAR order
    multi: ?Multi = null,
    chosen: ?Partial = null,
};

pub const Selection = struct { steps: []Step, done: bool };

pub const SelectError = error{ OutOfMemory, MaxStep, Removal };

/// METHOD=STEPWISE (p.9561): each step first tries to remove the weakest model
/// variable (largest Pr > F above SLSTAY), otherwise enters the strongest
/// candidate (largest partial F, tolerance above SINGULAR) if its Pr > F is
/// at most SLENTRY.
pub fn select(a: A, c: Ctx, s: Spec) SelectError!Selection {
    var steps: std.ArrayList(Step) = .empty;
    var set: std.ArrayList(usize) = .empty;
    const maxstep = s.maxstep orelse 2 * c.p;
    var b: [16]usize = undefined;
    var last_entered: ?usize = null;
    while (true) {
        if (steps.items.len >= maxstep) return error.MaxStep;
        var st: Step = .{ .removal = null, .set = &.{} };
        if (set.items.len > 0) {
            const rows = try a.alloc(Partial, set.items.len);
            var worst: ?usize = null;
            for (set.items, rows, 0..) |v, *row, k| {
                row.* = c.partial(without(&b, set.items, v), v);
                if (row.prob > s.slstay and (worst == null or row.f < rows[worst.?].f)) worst = k;
            }
            st.removal = rows;
            if (worst) |k| {
                // Verified against SAS 9.4 only for removing the variable just
                // entered when it leaves an empty model: SAS then stops ("No
                // further steps are possible."). Any other removal is a gap.
                if (rows[k].v != last_entered or set.items.len != 1) return error.Removal;
                st.removed = rows[k].v;
                st.chosen = rows[k];
                _ = set.orderedRemove(k);
                st.set = try a.dupe(usize, set.items);
                try steps.append(a, st);
                return .{ .steps = steps.items, .done = true };
            }
        }
        var cands: std.ArrayList(Partial) = .empty;
        for (0..c.p) |v| {
            if (std.mem.indexOfScalar(usize, set.items, v) != null) continue;
            const tol = c.tolerance(set.items, v);
            if (!(tol > s.singular)) continue;
            var row = c.partial(set.items, v);
            row.tol = tol;
            try cands.append(a, row);
        }
        if (cands.items.len > 0) {
            st.entry = cands.items;
            var best: usize = 0;
            for (cands.items, 0..) |row, k| if (row.f > cands.items[best].f) {
                best = k;
            };
            if (cands.items[best].prob <= s.slentry) {
                const v = cands.items[best].v;
                st.entered = v;
                st.chosen = cands.items[best];
                st.set = try a.dupe(usize, sortedWith(&b, set.items, v));
                set.clearRetainingCapacity();
                try set.appendSlice(a, st.set);
                st.multi = c.multi(set.items);
                last_entered = v;
                try steps.append(a, st);
                continue;
            }
        }
        st.set = try a.dupe(usize, set.items);
        try steps.append(a, st);
        return .{ .steps = steps.items, .done = true };
    }
}

// ── Listing ─────────────────────────────────────────────────────────────────

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn fmt(a: A, x: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}
fn fixed(a: A, x: f64, d: usize) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, d });
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn pvalue(a: A, x: f64) ![]const u8 {
    return fmt(a, x, "pvalue6.4");
}
/// Step messages are centered in a 72-column field (reference listing).
fn message(a: A, out: *Out, text: []const u8) !void {
    try centered(a, out, text, 72);
}

fn name(s: Spec, v: usize) []const u8 {
    return s.base.ds.columns.items[s.base.vars[v]].name;
}
fn varWidth(s: Spec) usize {
    var w: usize = "Variable".len;
    for (0..s.base.vars.len) |v| w = @max(w, name(s, v).len);
    return w;
}

fn counts(a: A, out: *Out, s: Spec, r: candisc.Result) !void {
    try centered(a, out, "The Method for Selecting Variables is STEPWISE", 106);
    try out.append(a, '\n');
    const left = [_]?struct { []const u8, []const u8 }{ .{ "Total Sample Size", try fmt(a, r.nfreq, "best12.") }, .{ "Class Levels", try fmt(a, @floatFromInt(r.levels.len), "best12.") }, null, null };
    const right = [_]struct { []const u8, []const u8 }{
        .{ "Variable(s) in the Analysis", try fmt(a, @floatFromInt(r.p), "best12.") },
        .{ "Variable(s) Will Be Included", "0" },
        .{ "Significance Level to Enter", try fmt(a, s.slentry, "best12.") },
        .{ "Significance Level to Stay", try fmt(a, s.slstay, "best12.") },
    };
    for (left, right) |l, rr| {
        if (l) |x| {
            try pad(a, out, x[0], 48 - x[1].len, true);
            try out.appendSlice(a, x[1]);
        } else try out.appendNTimes(a, ' ', 48);
        try out.appendNTimes(a, ' ', 10);
        try pad(a, out, rr[0], 48 - rr[1].len, true);
        try out.appendSlice(a, rr[1]);
        try out.append(a, '\n');
    }
}

fn nobs(a: A, out: *Out, s: Spec, r: candisc.Result) !void {
    var rows: std.ArrayList(struct { []const u8, f64 }) = .empty;
    try rows.append(a, .{ "Number of Observations Read", @floatFromInt(r.n_read) });
    try rows.append(a, .{ "Number of Observations Used", @floatFromInt(r.n_used) });
    if (s.base.freq != null) {
        try rows.append(a, .{ "Sum of Frequencies Read", r.freq_read });
        try rows.append(a, .{ "Sum of Frequencies Used", r.freq_used });
    }
    if (s.base.weight != null) {
        try rows.append(a, .{ "Sum of Weights Read", r.wt_read });
        try rows.append(a, .{ "Sum of Weights Used", r.wt_used });
    }
    for (rows.items) |row| {
        const v = try fmt(a, row[1], "best12.");
        try pad(a, out, row[0], 42 - v.len, true);
        try out.appendSlice(a, v);
        try out.append(a, '\n');
    }
}

fn levelsTable(a: A, out: *Out, s: Spec, r: candisc.Result) !void {
    const col = s.base.ds.columns.items[s.base.class];
    const numeric = col.type == .num;
    var w1: usize = col.name.len;
    if (numeric) {
        w1 = @max(6, w1);
    } else {
        for (r.levels) |l| w1 = @max(w1, l.text.len);
    }
    var w2: usize = "Variable".len;
    for (r.levels) |l| w2 = @max(w2, l.text.len);
    try centered(a, out, "Class Level Information", w1 + 4 + w2 + 40 + @as(usize, if (numeric) 1 else 0));
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', w1 + 4);
    try out.appendSlice(a, "Variable\n");
    try pad(a, out, col.name, w1, !numeric);
    try out.appendNTimes(a, ' ', 4);
    try pad(a, out, "Name", w2, true);
    try pad(a, out, "Frequency", 13, false);
    try pad(a, out, "Weight", 13, false);
    try pad(a, out, "Proportion", 14, false);
    try out.appendSlice(a, "\n\n");
    for (r.levels) |l| {
        try pad(a, out, l.text, w1, !numeric);
        try out.appendNTimes(a, ' ', 4);
        try pad(a, out, l.text, w2, true);
        try pad(a, out, try fmt(a, l.freq, "best12."), 13, false);
        try pad(a, out, try fixed(a, l.weight, 4), 13, false);
        try pad(a, out, try fixed(a, l.freq / r.nfreq, 6), 14, false);
        try out.append(a, '\n');
    }
}

fn dfText(a: A, c: Ctx, k: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "DF = {s}, {s}", .{ try fmt(a, c.q, "best12."), try fmt(a, c.dfe - @as(f64, @floatFromInt(k)), "best12.") });
}

fn partialTable(a: A, out: *Out, s: Spec, title: []const u8, rows: []const Partial, others: usize, tol: bool) !void {
    const w = varWidth(s);
    try centered(a, out, title, w + 33 + @as(usize, if (tol) 13 else 0));
    try out.appendSlice(a, " \n");
    if (others > 0) {
        try out.appendNTimes(a, ' ', w + 5);
        try out.appendSlice(a, "Partial\n");
    }
    try pad(a, out, "Variable", w, true);
    try out.appendSlice(a, "    R-Square    F Value    Pr > F");
    if (tol) try out.appendSlice(a, "    Tolerance");
    try out.appendSlice(a, "\n\n");
    // Rows in VAR order.
    for (0..s.base.vars.len) |v| {
        for (rows) |row| {
            if (row.v != v) continue;
            try pad(a, out, name(s, v), w, true);
            try pad(a, out, try fixed(a, row.rsq, 4), 12, false);
            try pad(a, out, try fixed(a, row.f, 2), 11, false);
            try pad(a, out, try pvalue(a, row.prob), 10, false);
            if (tol) try pad(a, out, try fixed(a, row.tol, 4), 13, false);
            try out.append(a, '\n');
        }
    }
}

fn multiTable(a: A, out: *Out, m: Multi) !void {
    try centered(a, out, "Multivariate Statistics", 93);
    try out.appendSlice(a, " \n");
    try pad(a, out, "Statistic", 37, true);
    try out.appendSlice(a, "           Value    F Value    Num DF    Den DF    Pr > F\n\n");
    const rows = [_]struct { []const u8, f64, f64, f64, f64, f64 }{
        .{ "Wilks' Lambda", m.wilks, m.wf, m.wd1, m.wd2, m.wprob },
        .{ "Pillai's Trace", m.pillai, m.pf, m.pd1, m.pd2, m.pprob },
    };
    for (rows) |r| {
        try pad(a, out, r[0], 37, true);
        try pad(a, out, try fixed(a, r[1], 6), 16, false);
        try pad(a, out, try fixed(a, r[2], 2), 11, false);
        try pad(a, out, try fmt(a, r[3], "best6."), 10, false);
        try pad(a, out, try fmt(a, r[4], "best6."), 10, false);
        try pad(a, out, try pvalue(a, r[5]), 10, false);
        try out.append(a, '\n');
    }
    try pad(a, out, "Average Squared Canonical Correlation", 37, true);
    try pad(a, out, try fixed(a, m.ascc, 6), 16, false);
    try out.append(a, '\n');
}

fn stepBody(a: A, out: *Out, s: Spec, c: Ctx, st: Step, prev: []const usize) !void {
    if (st.removal) |rows| {
        try partialTable(a, out, s, try std.fmt.allocPrint(a, "Statistics for Removal, {s}", .{try dfText(a, c, prev.len - 1)}), rows, prev.len - 1, false);
        try out.append(a, '\n');
        if (st.removed) |v| {
            try message(a, out, try std.fmt.allocPrint(a, "Variable {s} will be removed.", .{name(s, v)}));
            try out.append(a, '\n');
            try message(a, out, "No further steps are possible.");
            return;
        }
        try message(a, out, "No variables can be removed.");
        try out.append(a, '\n');
    }
    const rows = st.entry orelse {
        try message(a, out, "No further steps are possible.");
        return;
    };
    if (st.removal != null) try out.append(a, '\n');
    try partialTable(a, out, s, try std.fmt.allocPrint(a, "Statistics for Entry, {s}", .{try dfText(a, c, prev.len)}), rows, prev.len, true);
    try out.append(a, '\n');
    const v = st.entered orelse {
        try message(a, out, "No variables can be entered.");
        try out.append(a, '\n');
        try message(a, out, "No further steps are possible.");
        return;
    };
    try message(a, out, try std.fmt.allocPrint(a, "Variable {s} will be entered.", .{name(s, v)}));
    try out.append(a, '\n');
    if (st.set.len == c.p) {
        try message(a, out, "All variables have been entered.");
    } else {
        try out.appendSlice(a, "Variable(s) That Have Been Entered\n\n");
        for (st.set, 0..) |x, k| {
            if (k > 0) try out.append(a, ' ');
            try out.appendSlice(a, name(s, x));
        }
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try multiTable(a, out, st.multi.?);
}

fn summary(a: A, out: *Out, s: Spec, sel: Selection) !void {
    var wn: usize = 7;
    for (0..s.base.vars.len) |v| wn = @max(wn, name(s, v).len);
    const total = 5 + 10 + 2 * (4 + wn) + 12 + 11 + 10 + 14 + 10 + 15 + 10;
    // ponytail: the reference centers this title one column right of the
    // other tables' rule (calibrated, SAS 9.4).
    try centered(a, out, "Stepwise Selection Summary", total + 1);
    try out.appendSlice(a, " \n");
    const lead = 5 + 10 + 2 * (4 + wn);
    try out.appendNTimes(a, ' ', lead + 12 + 11 + 10 + 14 + 10 + 15 - 7);
    try out.appendSlice(a, "Average\n");
    try out.appendNTimes(a, ' ', lead + 12 + 11 + 10 + 14 + 10 + 15 - 7);
    try out.appendSlice(a, "Squared\n");
    try pad(a, out, "Number", 15, false);
    try out.appendNTimes(a, ' ', 2 * (4 + wn));
    try pad(a, out, "Partial", 12, false);
    try out.appendNTimes(a, ' ', 21);
    try pad(a, out, "Wilks'", 14, false);
    try pad(a, out, "Pr <", 10, false);
    try pad(a, out, "Canonical", 15, false);
    try pad(a, out, "Pr >", 10, false);
    try out.append(a, '\n');
    try out.appendSlice(a, " Step        In    ");
    try pad(a, out, "Entered", wn, true);
    try out.appendSlice(a, "    ");
    try pad(a, out, "Removed", wn, true);
    try out.appendSlice(a, "    R-Square    F Value    Pr > F        Lambda    Lambda    Correlation      ASCC\n\n");
    for (sel.steps, 0..) |st, k| {
        const ch = st.chosen orelse continue;
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 5, false);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{st.set.len}), 10, false);
        try out.appendSlice(a, "    ");
        try pad(a, out, if (st.entered) |v| name(s, v) else "", wn, true);
        try out.appendSlice(a, "    ");
        try pad(a, out, if (st.removed) |v| name(s, v) else "", wn, true);
        try pad(a, out, try fixed(a, ch.rsq, 4), 12, false);
        try pad(a, out, try fixed(a, ch.f, 2), 11, false);
        try pad(a, out, try pvalue(a, ch.prob), 10, false);
        const m = st.multi orelse {
            // An empty model after a removal has no multivariate statistics.
            try out.append(a, '\n');
            continue;
        };
        try pad(a, out, try fixed(a, m.wilks, 8), 14, false);
        try pad(a, out, try pvalue(a, m.wprob), 10, false);
        try pad(a, out, try fixed(a, m.ascc, 8), 15, false);
        try pad(a, out, try pvalue(a, m.pprob), 10, false);
        try out.append(a, '\n');
    }
}

fn page(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, rep: ?[]const Value, step: ?usize) !void {
    // SAS opens every page with a blank line; opensas omits it on the first.
    if (out.items.len > 0) try out.append(a, '\n');
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
    if (s.base.by_cols.len > 0) {
        var line: Out = .empty;
        try by.appendLine(a, &line, s.base.ds, rep.?, s.base.by_cols);
        if (line.items.len > 0) {
            try out.append(a, '\n');
            try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
        }
    }
    try out.appendSlice(a, "\nThe STEPDISC Procedure\n");
    if (step) |k| try out.print(a, "Stepwise Selection: Step {d}\n", .{k});
    try out.append(a, '\n');
}

fn footnotes(a: A, cx: proc.ProcCtx, out: *Out) !void {
    if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
}

pub fn render(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, r: candisc.Result, c: Ctx, sel: Selection, rep: ?[]const Value) !void {
    try page(a, cx, out, s, rep, null);
    try counts(a, out, s, r);
    try out.appendSlice(a, "\n\n");
    try nobs(a, out, s, r);
    try out.appendSlice(a, "\n\n");
    try levelsTable(a, out, s, r);
    try footnotes(a, cx, out);
    var prev: []const usize = &.{};
    // SHORT (p.9562): the first page and the summary only (SAS 9.4 reference).
    if (!s.short) for (sel.steps, 0..) |st, k| {
        try page(a, cx, out, s, rep, k + 1);
        try stepBody(a, out, s, c, st, prev);
        try footnotes(a, cx, out);
        prev = st.set;
    };
    var any = false;
    for (sel.steps) |st| any = any or st.chosen != null;
    if (any) {
        try page(a, cx, out, s, rep, null);
        try summary(a, out, s, sel);
        try footnotes(a, cx, out);
    }
}

fn warnings(cx: proc.ProcCtx, r: candisc.Result) !void {
    if (r.n_missing_vars > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group will not be included in the analysis due to missing values.", .{r.n_missing_vars});
    if (r.n_missing_class > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group are excluded from the development of the classification criterion due to missing values on CLASS variable.", .{r.n_missing_class});
    if (r.n_invalid > 0) try cx.diags.warnStatus(0, "{d} observations excluded due to invalid WEIGHT or FREQ variable values.", .{r.n_invalid});
    const excluded = r.n_missing_vars + r.n_missing_class + r.n_invalid;
    if (excluded > 0) try cx.diags.warnStatus(0, "A total of {d} of the {d} observations in the DATA= data set were excluded (frequency sum = {s}).", .{ excluded, r.n_read, std.mem.trim(u8, try format.apply(cx.arena, .{ .num = r.freq_used }, "best12."), " ") });
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (s.base.vars.len > 16) return gap(cx, 0, "more than 16 quantitative variables are not implemented", .{});
    if (s.base.ds.rows.items.len == 0) return gap(cx, 0, "an empty input data set ({s}) is not verified", .{try varlist.datasetName(a, s.base.ds)});
    const slices = try by.checkedSlices(a, s.base.ds, s.base.by_cols, s.base.by_desc, s.base.notsorted, cx.diags);
    const results = try a.alloc(candisc.Result, slices.len);
    const sels = try a.alloc(Selection, slices.len);
    const ctxs = try a.alloc(Ctx, slices.len);
    for (slices, results, sels, ctxs) |slice, *r, *sel, *c| {
        r.* = candisc.analyze(a, s.base, slice.rows) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Empty => return gap(cx, 0, "a BY group or data set without usable observations is not verified", .{}),
            error.OneLevel => return gap(cx, 0, "a CLASS variable with fewer than two levels is not verified", .{}),
            error.NoDf => return gap(cx, 0, "an analysis without within-class degrees of freedom is not verified", .{}),
            error.Singular => return gap(cx, 0, "a singular within-class SSCP matrix (or zero weights) is not implemented", .{}),
        };
        for (r.levels) |l| if (l.freq == 1) return gap(cx, 0, "a CLASS level with a single observation is not verified", .{});
        c.* = .{ .e = r.e, .t = r.t, .p = r.p, .q = @floatFromInt(r.levels.len - 1), .dfe = r.nfreq - @as(f64, @floatFromInt(r.levels.len)) };
        sel.* = select(a, c.*, s) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.MaxStep => return gap(cx, 0, "stopping at MAXSTEP= before the selection ends is not verified", .{}),
            error.Removal => return gap(cx, 0, "a stepwise removal step that keeps variables in the model is not verified against the SAS reference", .{}),
        };
    }
    for (slices, results, sels, ctxs) |slice, r, sel, c| {
        try warnings(cx, r);
        try render(a, cx, out, s, r, c, sel, slice.rep);
    }
}

test {
    _ = @import("stepdisc_tests.zig");
}
