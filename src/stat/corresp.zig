//! PROC CORRESP (SAS/STAT 15.4 ch.41): PROC statement options, VAR / ID /
//! BY / WEIGHT roles (negative weights: supplementary rows), VAR-statement
//! input and its missing/invalid-data rules, and the simple correspondence analysis of that table: the inertia and
//! chi-square decomposition, row and column coordinates, the point statistics
//! (unless SHORT) and the OUTC= data set (STAT-CORRESP-001). Every documented
//! option or statement this file does not compute is a loud D-009 gap.
//!
//! Computation (pp.2597-2604): P = F/n, r and c its margins, S =
//! Dr^-1/2 (P - rc') Dc^-1/2. The eigen-decomposition of S'S (PROC PRINCOMP's
//! Jacobi kernel, called read-only) gives the principal inertias and V; each
//! column of V is oriented to a nonnegative element sum, which reproduces the
//! signs of every SAS listing checked. Row principal coordinates are
//! Dr^-1/2 S V, column coordinates Dc^-1/2 V Du. The listing layout is taken
//! from SAS 9.4 listings of the chapter's Ph.D. example and invented tables.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fns = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const pc = @import("princomp.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Spec = struct {
    input: proc.ProcInput,
    out: ?[]const u8 = null,
    dimens: usize = 2,
    short: bool = false,
    chi2p: bool = false,
    noprint: bool = false,
    mininertia: f64 = 0.8,
    singular: f64 = 1e-8,
    plots_none: bool = false,
    vars: []const usize = &.{},
    id: ?usize = null,
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
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC CORRESP: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) j = proc.skipParen(t, j);
    into.* = name;
    return j;
}

/// Every PROC CORRESP option (Table 41.1). p.2567: all of them except OUTF=
/// can be abbreviated to their first three letters; any longer prefix of the
/// full name is accepted too. OUT= is the documented alias of OUTC=.
const options = [_][]const u8{
    "all",        "benzecri",  "binary",   "cellchi2", "chi2p",   "column",    "cp",           "cross",
    "data",       "deviation", "dimens",   "expected", "freqout", "greenacre", "inertiatable", "mca",
    "mininertia", "missing",   "nocolumn", "noprint",  "norow",   "nvars",     "observed",     "outc",
    "plots",      "print",     "profile",  "row",      "rp",      "short",     "singular",     "source",
    "unadjusted",
};
fn canonical(word: []const u8) ?[]const u8 {
    if (eq(word, "out") or eq(word, "outc")) return "outc";
    if (eq(word, "outf")) return "outf";
    for (options) |o| if (eq(word, o)) return o;
    if (word.len < 3) return null;
    for (options) |o| if (word.len <= o.len and std.ascii.startsWithIgnoreCase(o, word)) return o;
    return null;
}

fn number(t: []const lex.Token, i: usize) ?f64 {
    if (!at(t, i, .number)) return null;
    return std.fmt.parseFloat(f64, t[i].text) catch null;
}

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
        const option = canonical(t[i].text) orelse return invalid(cx, t, i);
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, t[i].line, "PROC CORRESP: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        const o = option;
        if (eq(o, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(o, "outc") and valued) {
            var member: ?[]const u8 = null;
            const after = try memberName(cx, t, i + 2, &member);
            if (at(t, i + 3, .lparen) or (at(t, i + 3, .dot) and at(t, i + 5, .lparen))) return gap(cx.diags, t[i].line, "PROC CORRESP: data set options on OUTC= are not implemented", .{});
            s.out = member;
            i = after;
        } else if (eq(o, "dimens") and valued) {
            const v = number(t, i + 2) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: DIMENS= must be a positive integer", .{});
            if (v < 1 or v != @floor(v)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: DIMENS= must be a positive integer", .{});
            s.dimens = @intFromFloat(v);
            i += 3;
        } else if (eq(o, "mininertia") and valued) {
            const v = number(t, i + 2) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: MININERTIA= must be a number between 0 and 1", .{});
            // p.2571: 0 <= n <= 1.
            if (v < 0 or v > 1) return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: MININERTIA= must be a number between 0 and 1", .{});
            s.mininertia = v;
            i += 3;
        } else if (eq(o, "singular") and valued) {
            const v = number(t, i + 2) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: SINGULAR= must be a positive number", .{});
            if (!(v > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: SINGULAR= must be a positive number", .{});
            s.singular = v;
            i += 3;
        } else if (eq(o, "plots")) {
            // Plots exist only under ODS Graphics; PLOTS=NONE is the one
            // request this ticket honours (the inertia table is then printed).
            var j = i + 1;
            var global = false;
            if (at(t, j, .lparen)) {
                global = true;
                j = proc.skipParen(t, j);
            }
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            if (!global and at(t, j, .name) and (eq(t[j].text, "none") or eq(t[j].text, "non"))) {
                s.plots_none = true;
                j += 1;
            } else if (at(t, j, .lparen)) {
                j = proc.skipParen(t, j);
            } else if (at(t, j, .name)) {
                j += 1;
                if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            } else return invalid(cx, t, j);
            i = j;
        } else if (eq(o, "short") and !valued) {
            s.short = true;
            i += 1;
        } else if (eq(o, "chi2p") and !valued) {
            s.chi2p = true;
            i += 1;
        } else if (eq(o, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(o, "data") or eq(o, "outc") or eq(o, "dimens") or eq(o, "mininertia") or eq(o, "singular")) {
            return invalid(cx, t, i + 1);
        } else {
            const owner: []const u8 = if (eq(o, "mca") or eq(o, "benzecri") or eq(o, "greenacre") or eq(o, "unadjusted") or eq(o, "nvars"))
                " (multiple correspondence analysis)"
            else if (eq(o, "binary") or eq(o, "cross") or eq(o, "freqout") or eq(o, "missing") or eq(o, "source"))
                " (TABLES statement input, STAT-CORRESP-003)"
            else
                "";
            return gap(cx.diags, t[i].line, "PROC CORRESP: the {s} option is not implemented{s}", .{ t[i].text, owner });
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC CORRESP: input data set not found", .{});
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
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx.diags, t[i].line, "PROC CORRESP: more than one VAR statement is not verified", .{});
            var_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                const names = try lists.next(a, ds, body, &j, cx.diags);
                for (names) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC CORRESP: variable {s} in the VAR statement is not on the input data set", .{n});
                    // p.2579: the VAR variables must be numeric.
                    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC CORRESP: variable {s} in the VAR statement must be numeric", .{n});
                    if (std.mem.indexOfScalar(usize, vars.items, ci) != null) return gap(cx.diags, l, "PROC CORRESP: a variable listed twice in the VAR statement is not verified", .{});
                    try vars.append(a, ci);
                }
            }
        } else if (eq(word, "id")) {
            if (s.id != null) return gap(cx.diags, t[i].line, "PROC CORRESP: more than one ID statement is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
            s.id = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: variable {s} in the ID statement is not on the input data set", .{t[i + 1].text});
        } else if (eq(word, "weight")) {
            // p.2579: you can include only one WEIGHT statement.
            if (s.weight != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: only one WEIGHT statement is allowed", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
            const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: variable {s} in the WEIGHT statement is not on the input data set", .{t[i + 1].text});
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC CORRESP: variable {s} in the WEIGHT statement must be numeric", .{t[i + 1].text});
            s.weight = ci;
        } else if (eq(word, "tables") or eq(word, "table")) {
            return gap(cx.diags, t[i].line, "PROC CORRESP: TABLES statement input is not implemented (STAT-CORRESP-003)", .{});
        } else if (eq(word, "supplementary") or eq(word, "sup")) {
            return gap(cx.diags, t[i].line, "PROC CORRESP: the SUPPLEMENTARY statement is not implemented (STAT-CORRESP-003)", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (eq(word, "format") or eq(word, "label")) {
            return gap(cx.diags, t[i].line, "PROC CORRESP: a {s} statement inside the step is not implemented", .{word});
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!var_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CORRESP: a VAR or TABLES statement is required", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.vars = vars.items;
    if (s.vars.len < 2) return gap(cx.diags, line(t, 0), "PROC CORRESP: a table with fewer than two columns is not verified", .{});
    return s;
}

/// The correspondence analysis of one table (all dimensions).
pub const Result = struct {
    nr: usize,
    nc: usize,
    n: f64,
    /// Principal inertias (descending), one per nonzero dimension.
    inertias: []const f64,
    r: []const f64,
    c: []const f64,
    /// Row-major nr*nd and nc*nd principal coordinates.
    f: []const f64,
    g: []const f64,
    /// Squared distances of each profile to the centroid (sum over all dims).
    dr: []const f64,
    dc: []const f64,
};

/// Simple correspondence analysis of the row-major nr*nc table `table`
/// (nonnegative, no zero row or column).
pub fn analyze(a: A, cells: []const f64, nr: usize, nc: usize) !Result {
    var n: f64 = 0;
    for (cells) |v| n += v;
    const r = try a.alloc(f64, nr);
    const c = try a.alloc(f64, nc);
    @memset(r, 0);
    @memset(c, 0);
    for (0..nr) |i| for (0..nc) |j| {
        r[i] += cells[i * nc + j] / n;
        c[j] += cells[i * nc + j] / n;
    };
    const sm = try a.alloc(f64, nr * nc);
    for (0..nr) |i| for (0..nc) |j| {
        sm[i * nc + j] = (cells[i * nc + j] / n - r[i] * c[j]) / @sqrt(r[i] * c[j]);
    };
    const sts = try a.alloc(f64, nc * nc);
    for (0..nc) |j| for (0..nc) |k| {
        var acc: f64 = 0;
        for (0..nr) |i| acc += sm[i * nc + j] * sm[i * nc + k];
        sts[j * nc + k] = acc;
    };
    const e = try pc.eigenSym(a, sts, nc);
    const nd = @min(nr, nc) - 1;
    const inertias = try a.alloc(f64, nd);
    const v = try a.alloc(f64, nc * nd);
    for (0..nd) |k| {
        inertias[k] = @max(e.values[k], 0);
        var sum: f64 = 0;
        for (0..nc) |j| sum += e.vectors[j * nc + k];
        const sign: f64 = if (sum < 0) -1 else 1;
        for (0..nc) |j| v[j * nd + k] = sign * e.vectors[j * nc + k];
    }
    const f = try a.alloc(f64, nr * nd);
    const g = try a.alloc(f64, nc * nd);
    for (0..nr) |i| for (0..nd) |k| {
        var acc: f64 = 0;
        for (0..nc) |j| acc += sm[i * nc + j] * v[j * nd + k];
        f[i * nd + k] = acc / @sqrt(r[i]);
    };
    for (0..nc) |j| for (0..nd) |k| {
        g[j * nd + k] = v[j * nd + k] * @sqrt(inertias[k]) / @sqrt(c[j]);
    };
    const dr = try a.alloc(f64, nr);
    const dc = try a.alloc(f64, nc);
    @memset(dr, 0);
    @memset(dc, 0);
    for (0..nr) |i| for (0..nc) |j| {
        const p = cells[i * nc + j] / n;
        dr[i] += std.math.pow(f64, p / r[i] - c[j], 2) / c[j];
        dc[j] += std.math.pow(f64, p / c[j] - r[i], 2) / r[i];
    };
    return .{ .nr = nr, .nc = nc, .n = n, .inertias = inertias, .r = r, .c = c, .f = f, .g = g, .dr = dr, .dc = dc };
}

/// Point statistics for the first `dims` dimensions (Table 41.5).
pub const Points = struct {
    quality: []f64,
    mass: []const f64,
    inertia: []f64,
    coord: []f64,
    contr: []f64,
    sqcos: []f64,
    best_k: []f64,
    best: []f64,
};

pub fn points(a: A, res: Result, rows: bool, dims: usize, mininertia: f64) !Points {
    const np = if (rows) res.nr else res.nc;
    const nd = res.inertias.len;
    const coords = if (rows) res.f else res.g;
    const mass = if (rows) res.r else res.c;
    const d2 = if (rows) res.dr else res.dc;
    var total: f64 = 0;
    for (res.inertias) |x| total += x;
    const p: Points = .{
        .quality = try a.alloc(f64, np),
        .mass = mass,
        .inertia = try a.alloc(f64, np),
        .coord = try a.alloc(f64, np * dims),
        .contr = try a.alloc(f64, np * dims),
        .sqcos = try a.alloc(f64, np * dims),
        .best_k = try a.alloc(f64, np * dims),
        .best = try a.alloc(f64, np),
    };
    for (0..np) |i| {
        p.quality[i] = 0;
        p.inertia[i] = mass[i] * d2[i] / total;
        var top: usize = 0;
        for (0..dims) |k| {
            const x = coords[i * nd + k];
            p.coord[i * dims + k] = x;
            p.contr[i * dims + k] = mass[i] * x * x / res.inertias[k];
            p.sqcos[i * dims + k] = if (d2[i] > 0) x * x / d2[i] else 0;
            p.quality[i] += p.sqcos[i * dims + k];
            if (p.contr[i * dims + k] > p.contr[i * dims + top]) top = k;
        }
        p.best[i] = @floatFromInt(top + 1);
    }
    // pp.2603-2604: per dimension, the largest contributors are flagged until
    // their cumulative contribution reaches MININERTIA=.
    const order = try a.alloc(usize, np);
    for (0..dims) |k| {
        for (order, 0..) |*o, i| o.* = i;
        const Ctx = struct {
            c: []const f64,
            d: usize,
            k: usize,
            fn gt(self: @This(), x: usize, y: usize) bool {
                return self.c[x * self.d + self.k] > self.c[y * self.d + self.k];
            }
        };
        std.mem.sort(usize, order, Ctx{ .c = p.contr, .d = dims, .k = k }, Ctx.gt);
        for (0..np) |i| p.best_k[i * dims + k] = 0;
        var sum: f64 = 0;
        for (order) |i| {
            if (sum >= mininertia) break;
            p.best_k[i * dims + k] = p.best[i];
            sum += p.contr[i * dims + k];
        }
    }
    return p;
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
fn fixed(a: A, value: f64, decimals: usize) ![]const u8 {
    var text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ value, decimals });
    if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) text = text[1..];
    return text;
}
/// Verified: the row-label column is the longest label rounded up to a
/// multiple of 8 (at least 8): lengths 1/4 -> 8, 10/12 -> 16, 19 -> 24.
fn labelWidth(names: []const []const u8) usize {
    var w: usize = 1;
    for (names) |n| w = @max(w, n.len);
    return (w + 7) / 8 * 8;
}
fn heading(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, "\n\n");
    if (width > text.len) try pad(a, out, (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}
fn table(a: A, out: *Out, title: []const u8, names: []const []const u8, heads: []const []const u8, values: []const f64, decimals: ?usize) !void {
    const lw = labelWidth(names);
    const nc = heads.len;
    try heading(a, out, title, lw + 11 * nc);
    try pad(a, out, lw);
    for (heads) |h| try right(a, out, h, 11);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |n, i| {
        try left(a, out, n, lw);
        for (0..nc) |k| {
            const v = values[i * nc + k];
            try right(a, out, if (decimals) |d| try fixed(a, v, d) else try std.fmt.allocPrint(a, "{d}", .{@as(i64, @intFromFloat(v))}), 11);
        }
        try out.appendSlice(a, "\n");
    }
}

fn inertiaTable(a: A, out: *Out, res: Result, chi2p: bool) !void {
    const nd = res.inertias.len;
    var total: f64 = 0;
    for (res.inertias) |x| total += x;
    const width = 89;
    const title = "Inertia and Chi-Square Decomposition";
    try out.appendSlice(a, "\n");
    try pad(a, out, (width - title.len + 1) / 2);
    try out.appendSlice(a, title);
    try out.appendSlice(a, "\n \n");
    // Verified: chi-squares share six significant digits set by the total.
    const chi_total = total * res.n;
    const digits: usize = if (chi_total < 1) 1 else @as(usize, @intFromFloat(@floor(@log10(chi_total)))) + 1;
    const cd: usize = if (digits >= 6) 0 else 6 - digits;
    var maxpct: f64 = 0;
    for (res.inertias) |x| maxpct = @max(maxpct, 100 * x / total);
    const tick = @round(maxpct / 5);
    try out.appendSlice(a, "Singular    Principal       Chi-               Cumulative\n");
    try out.appendSlice(a, "   Value      Inertia     Square    Percent       Percent    ");
    for (1..6) |m| try right(a, out, try std.fmt.allocPrint(a, "{d}", .{@as(i64, @intFromFloat(tick)) * @as(i64, @intCast(m))}), 5);
    try out.appendSlice(a, "   \n");
    try pad(a, out, 61);
    try out.appendSlice(a, "----+----+----+----+----+---\n");
    var cum: f64 = 0;
    for (0..nd) |k| {
        const x = res.inertias[k];
        const pct = 100 * x / total;
        cum += pct;
        try right(a, out, try fixed(a, @sqrt(x), 5), 8);
        try right(a, out, try fixed(a, x, 5), 13);
        try right(a, out, try fixed(a, x * res.n, cd), 11);
        try right(a, out, try fixed(a, pct, 2), 11);
        try right(a, out, try fixed(a, cum, 2), 14);
        try pad(a, out, 4);
        const stars: usize = if (tick > 0) @intFromFloat(@min(25, @round(pct * 5 / tick))) else 0;
        try out.appendNTimes(a, '*', stars);
        try pad(a, out, 28 - stars);
        try out.appendSlice(a, "\n");
    }
    try out.appendSlice(a, "\n   Total");
    try right(a, out, try fixed(a, total, 5), 13);
    try right(a, out, try fixed(a, chi_total, cd), 11);
    try right(a, out, "100.00", 11);
    try pad(a, out, width - 43);
    const df = (res.nr - 1) * (res.nc - 1);
    try out.print(a, "\n\nDegrees of Freedom = {d}\n", .{df});
    if (chi2p) {
        const p = 1 - fns.gammaP(@as(f64, @floatFromInt(df)) / 2, chi_total / 2);
        if (p < 0.0001) {
            try out.appendSlice(a, "Pr > ChiSq         < .0001\n");
        } else {
            const text = try std.fmt.allocPrint(a, "{d:.4}", .{p});
            try out.print(a, "Pr > ChiSq         = {s}\n", .{if (std.mem.startsWith(u8, text, "0.")) text[1..] else text});
        }
    }
}

/// Supplementary rows (negative WEIGHT values, p.2579): projected onto the
/// active solution by the transition formula Fs = Rs G Du^-1, where Rs holds
/// the supplementary row profiles; squared cosines use each profile's
/// chi-square distance to the centroid (Table 41.5).
pub const Supplementary = struct {
    names: []const []const u8,
    coord: []f64,
    sqcos: []f64,
    quality: []f64,
};

pub fn supplementary(a: A, res: Result, cells: []const f64, names: []const []const u8, dims: usize) !Supplementary {
    const ns = names.len;
    const nc = res.nc;
    const nd = res.inertias.len;
    const sp: Supplementary = .{ .names = names, .coord = try a.alloc(f64, ns * dims), .sqcos = try a.alloc(f64, ns * dims), .quality = try a.alloc(f64, ns) };
    for (0..ns) |i| {
        var total: f64 = 0;
        for (0..nc) |j| total += cells[i * nc + j];
        var d2: f64 = 0;
        for (0..nc) |j| d2 += std.math.pow(f64, cells[i * nc + j] / total - res.c[j], 2) / res.c[j];
        sp.quality[i] = 0;
        for (0..dims) |k| {
            var acc: f64 = 0;
            for (0..nc) |j| acc += cells[i * nc + j] / total * res.g[j * nd + k];
            const x = acc / @sqrt(res.inertias[k]);
            sp.coord[i * dims + k] = x;
            sp.sqcos[i * dims + k] = if (d2 > 0) x * x / d2 else 0;
            sp.quality[i] += sp.sqcos[i * dims + k];
        }
    }
    return sp;
}

fn pointTables(a: A, out: *Out, names: []const []const u8, p: Points, dims: usize, kind: []const u8, short: bool, dim_heads: []const []const u8, sup: ?Supplementary) !void {
    try table(a, out, try std.fmt.allocPrint(a, "{s} Coordinates", .{if (eq(kind, "Row")) "Row" else "Column"}), names, dim_heads, p.coord, 4);
    if (sup) |sp| try table(a, out, "Supplementary Row Coordinates", sp.names, dim_heads, sp.coord, 4);
    if (short) return;
    const np = names.len;
    const summary = try a.alloc(f64, np * 3);
    for (0..np) |i| {
        summary[i * 3] = p.quality[i];
        summary[i * 3 + 1] = p.mass[i];
        summary[i * 3 + 2] = p.inertia[i];
    }
    try table(a, out, try std.fmt.allocPrint(a, "Summary Statistics for the {s} Points", .{kind}), names, &.{ "Quality", "Mass", "Inertia" }, summary, 4);
    if (sup) |sp| {
        // Verified: this table has no column heading and an empty line (not
        // one blank) under its title.
        const title = "Quality of Representation for the Supplementary Row Points";
        const lw = labelWidth(sp.names);
        try out.appendSlice(a, "\n\n");
        if (lw + 11 > title.len) try pad(a, out, (lw + 11 - title.len) / 2);
        try out.appendSlice(a, title);
        try out.appendSlice(a, "\n\n");
        for (sp.names, sp.quality) |n, q| {
            try left(a, out, n, lw);
            try right(a, out, try fixed(a, q, 4), 11);
            try out.appendSlice(a, "\n");
        }
    }
    try table(a, out, try std.fmt.allocPrint(a, "Partial Contributions to Inertia for the {s} Points", .{kind}), names, dim_heads, p.contr, 4);
    const best = try a.alloc(f64, np * (dims + 1));
    const best_heads = try a.alloc([]const u8, dims + 1);
    @memcpy(best_heads[0..dims], dim_heads);
    best_heads[dims] = "Best";
    for (0..np) |i| {
        for (0..dims) |k| best[i * (dims + 1) + k] = p.best_k[i * dims + k];
        best[i * (dims + 1) + dims] = p.best[i];
    }
    try table(a, out, try std.fmt.allocPrint(a, "Indices of the Coordinates That Contribute Most to Inertia for the {s} Points", .{kind}), names, best_heads, best, null);
    try table(a, out, try std.fmt.allocPrint(a, "Squared Cosines for the {s} Points", .{kind}), names, dim_heads, p.sqcos, 4);
    if (sup) |sp| try table(a, out, "Squared Cosines for the Supplementary Row Points", sp.names, dim_heads, sp.sqcos, 4);
}

fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

fn idText(a: A, row: []const Value, ci: usize) ![]const u8 {
    const v = row[ci];
    return switch (v) {
        .str => |x| std.mem.trimEnd(u8, x, " "),
        .num => std.mem.trim(u8, try proc.cellText(a, v), " "),
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const nc = s.vars.len;
    if (cx.capture) |c| for ([_][]const u8{ "Burt", "BurtPct", "CellChiSq", "CellChiSqPct", "ColBest", "ColContr", "ColCoors", "ColProfiles", "ColProfilesPct", "ColQualMassIn", "ColSqCos", "DF", "Deviations", "DeviationsPct", "Expected", "ExpectedPct", "Inertias", "Observed", "ObservedPct", "RowBest", "RowContr", "RowCoors", "RowProfiles", "RowProfilesPct", "RowQualMassIn", "RowSqCos", "SupColCoors", "SupColProfiles", "SupColProfilesPct", "SupColQuality", "SupCols", "SupColsPct", "SupColSqCos", "SupRows", "SupRowCoors", "SupRowProfiles", "SupRowProfilesPct", "SupRowQuality", "SupRowsPct", "SupRowSqCos" }) |tbl| {
        if (c.wants(tbl)) return gap(cx.diags, l0, "PROC CORRESP: ODS OUTPUT {s}= is not implemented", .{tbl});
    };
    if (s.id) |ci| if (ds.columns.items[ci].type != .char and s.out != null) return gap(cx.diags, l0, "PROC CORRESP: OUTC= with a numeric ID variable is not verified", .{});
    const graphs = !s.noprint and !s.plots_none and if (cx.graphics) |g| g.enabled == true else false;

    const col_names = try a.alloc([]const u8, nc);
    for (s.vars, col_names) |ci, *n| {
        const c = ds.columns.items[ci];
        n.* = c.label orelse c.name;
    }
    var created: ?*Dataset = null;
    var id_len: usize = 8;
    if (s.out) |member| {
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        for (s.by_cols) |ci| _ = try o.addColumnLike(ds.columns.items[ci].name, ds.columns.items[ci]);
        const ti = try o.addColumn("_TYPE_", .char);
        o.columns.items[ti].len = 8;
        if (s.id) |ci| {
            const src = ds.columns.items[ci];
            _ = try o.addColumnLike(src.name, src);
            id_len = src.len orelse std.math.maxInt(usize);
        } else {
            const ni = try o.addColumn("_NAME_", .char);
            o.columns.items[ni].len = 8;
        }
        for ([_][]const u8{ "Quality", "Mass", "Inertia" }) |n| _ = try o.addColumn(n, .num);
        for ([_][]const u8{ "Dim", "Contr", "SqCos", "Best" }) |prefix| for (0..s.dimens) |k| {
            _ = try o.addColumn(try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, k + 1 }), .num);
        };
        _ = try o.addColumn("Best", .num);
        created = o;
    }
    const dim_heads = try a.alloc([]const u8, s.dimens);
    for (dim_heads, 0..) |*h, k| h.* = try std.fmt.allocPrint(a, "Dim{d}", .{k + 1});

    var body: Out = .empty;
    for (groups, 0..) |group, gi| {
        // pp.2592, 2601: observations with a missing or negative VAR value or
        // a missing weight are excluded; negative weights mark supplementary
        // rows; all-zero rows are excluded.
        var cells: std.ArrayList(f64) = .empty;
        var names: std.ArrayList([]const u8) = .empty;
        var sup_cells: std.ArrayList(f64) = .empty;
        var sup_names: std.ArrayList([]const u8) = .empty;
        for (group.rows, 0..) |row, ri| {
            var w: f64 = 1;
            var is_sup = false;
            if (s.weight) |wi| {
                if (row[wi].isMissing()) continue;
                w = row[wi].num;
                if (w < 0) {
                    is_sup = true;
                    w = -w;
                }
            }
            var ok = true;
            var sum: f64 = 0;
            for (s.vars) |ci| {
                if (row[ci].isMissing() or row[ci].num < 0) ok = false else sum += row[ci].num;
            }
            if (!ok or sum * w <= s.singular) continue;
            for (s.vars) |ci| try (if (is_sup) &sup_cells else &cells).append(a, row[ci].num * w);
            try (if (is_sup) &sup_names else &names).append(a, if (s.id) |ci| try idText(a, row, ci) else try std.fmt.allocPrint(a, "Row{d}", .{ri + 1}));
        }
        const nr = names.items.len;
        if (nr < 2) return gap(cx.diags, l0, "PROC CORRESP: a table with fewer than two usable rows is not verified", .{});
        for (0..nc) |j| {
            var sum: f64 = 0;
            for (0..nr) |i| sum += cells.items[i * nc + j];
            if (sum <= s.singular) return gap(cx.diags, l0, "PROC CORRESP: a table with an all-zero column is not verified", .{});
        }
        // p.2570: the maximum DIMENS= is min(nr, nc) - 1.
        if (s.dimens > @min(nr, nc) - 1) return gap(cx.diags, l0, "PROC CORRESP: DIMENS={d} above the {d} available dimensions is not verified", .{ s.dimens, @min(nr, nc) - 1 });
        const res = try analyze(a, cells.items, nr, nc);
        for (res.inertias[0..s.dimens]) |x| if (!(x > s.singular)) return gap(cx.diags, l0, "PROC CORRESP: a requested dimension with zero inertia is not verified", .{});
        const rp = try points(a, res, true, s.dimens, s.mininertia);
        const cp = try points(a, res, false, s.dimens, s.mininertia);
        const sup: ?Supplementary = if (sup_names.items.len > 0) try supplementary(a, res, sup_cells.items, sup_names.items, s.dimens) else null;
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);

        if (!s.noprint) {
            if (gi > 0) if (cx.listing_titles) |titles| try titles.emitTitles(a, &body);
            if (s.by_cols.len > 0) {
                try byLine(a, &body, ds, group.rows[0], s.by_cols);
            }
            try body.appendSlice(a, "\nThe CORRESP Procedure\n");
            // p.2571: under ODS Graphics the inertia chart replaces the table.
            if (!graphs) try inertiaTable(a, &body, res, s.chi2p);
            try pointTables(a, &body, names.items, rp, s.dimens, "Row", s.short, dim_heads, sup);
            try pointTables(a, &body, col_names, cp, s.dimens, "Column", s.short, dim_heads, null);
        }
        if (created) |o| {
            const d = s.dimens;
            const width = o.columns.items.len;
            const nb = s.by_cols.len;
            const values = try a.alloc(Value, width);
            for (values) |*v| v.* = Value.missing;
            for (s.by_cols, 0..) |ci, k| values[k] = group.rows[0][ci];
            values[nb] = .{ .str = "INERTIA" };
            values[nb + 1] = .{ .str = "" };
            var total: f64 = 0;
            for (res.inertias) |x| total += x;
            values[nb + 4] = .{ .num = total };
            for (0..d) |k| values[nb + 5 + d + k] = .{ .num = res.inertias[k] };
            try o.appendRow(values);
            for ([_]bool{ true, false }) |is_row| {
                const p = if (is_row) rp else cp;
                const pn = if (is_row) names.items else col_names;
                for (pn, 0..) |n, i| {
                    values[nb] = .{ .str = if (is_row) "OBS" else "VAR" };
                    values[nb + 1] = .{ .str = n[0..@min(n.len, id_len)] };
                    values[nb + 2] = .{ .num = p.quality[i] };
                    values[nb + 3] = .{ .num = p.mass[i] };
                    values[nb + 4] = .{ .num = p.inertia[i] };
                    for (0..d) |k| {
                        values[nb + 5 + k] = .{ .num = p.coord[i * d + k] };
                        values[nb + 5 + d + k] = .{ .num = p.contr[i * d + k] };
                        values[nb + 5 + 2 * d + k] = .{ .num = p.sqcos[i * d + k] };
                        values[nb + 5 + 3 * d + k] = .{ .num = p.best_k[i * d + k] };
                    }
                    values[nb + 5 + 4 * d] = .{ .num = p.best[i] };
                    try o.appendRow(values);
                }
                // SAS: SUPOBS rows follow the OBS rows; mass, inertia,
                // contributions and best indicators are not defined (p.2603).
                if (is_row) if (sup) |sp| for (sp.names, 0..) |n, i| {
                    for (values[nb + 2 ..]) |*v| v.* = Value.missing;
                    values[nb] = .{ .str = "SUPOBS" };
                    values[nb + 1] = .{ .str = n[0..@min(n.len, id_len)] };
                    values[nb + 2] = .{ .num = sp.quality[i] };
                    for (0..d) |k| {
                        values[nb + 5 + k] = .{ .num = sp.coord[i * d + k] };
                        values[nb + 5 + 2 * d + k] = .{ .num = sp.sqcos[i * d + k] };
                    }
                    try o.appendRow(values);
                };
            }
        }
    }
    if (created) |o| {
        const member = s.out.?;
        try cx.lib.put(member, o);
        // ponytail: a one-level name is reported under WORK (no USER libref lookup).
        const upper = try std.ascii.allocUpperString(a, member);
        const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
    }
    try out.appendSlice(a, body.items);
    if (graphs) {
        // The tables above are complete; the plots that SAS adds to them are
        // not, so the step still ends with a visible D-009 gap.
        diag.markGap();
        try cx.diags.recoverableErr(l0, "PROC CORRESP: the ODS Graphics inertia chart and configuration plot are not implemented (STAT-CORRESP-008); specify PLOTS=NONE or ODS GRAPHICS OFF", .{});
    }
}

test {
    _ = @import("corresp_tests.zig");
}
