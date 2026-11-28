//! PROC MODECLUS statements, roles and the fixed-radius default path, SAS/STAT
//! 15.4 Chapter 85 (PROC MODECLUS statement pp.6818-6825, BY p.6825, FREQ
//! pp.6825-6826, ID p.6826, VAR p.6826, Density Estimation pp.6826-6829,
//! Clustering Methods METHOD=0/1 pp.6829-6830, Missing Values pp.6837-6838).
//! `parse` records every documented declaration; what has not been proven
//! against a SAS reference run (k-nearest-neighbour smoothing, cascading,
//! METHOD=2..6, TEST/JOIN, the optional tables, OUTCLUS=/OUTSUM=, TYPE=DISTANCE
//! input) is a D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    out: ?[]const u8 = null,
    cluster_name: []const u8 = "CLUSTER",
    density_name: []const u8 = "DENSITY",
    methods: []const f64 = &.{},
    r: []const f64 = &.{},
    dr: []const f64 = &.{},
    cr: []const f64 = &.{},
    noprint: bool = false,
    nosummary: bool = false,
    short: bool = false,
    vars: []const usize = &.{},
    var_given: bool = false,
    id: ?usize = null,
    freq: ?usize = null,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC MODECLUS: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC MODECLUS: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC MODECLUS: " ++ text, args);
}

/// Documented PROC MODECLUS options (Table 85.1) that are not implemented.
const unimplemented = [_][]const u8{
    "all",       "am",          "boundary", "cascade", "casc",   "ck",        "core",  "cross",
    "crosslist", "dimension",   "dim",      "dk",      "dock",   "early",     "hm",    "join",
    "k",         "list",        "local",    "maxclusters", "maxc", "mode",    "neighbor", "outclus",
    "outc",      "outsum",      "outs",     "outlength", "outl", "power",     "pow",   "simple",
    "s",         "standard",    "std",      "sum",     "test",   "threshold", "thr",   "trace",
};

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

fn number(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!f64 {
    if (!at(t, i, .number)) return invalid(cx, t, i);
    return std.fmt.parseFloat(f64, t[i].text) catch invalid(cx, t, i);
}

/// A value list: numbers separated by blanks or commas, with `start TO stop
/// BY increment` items (p.6819).
fn valueList(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const f64 {
    const a = cx.arena;
    var vals: std.ArrayList(f64) = .empty;
    while (at(t, i.*, .number)) {
        const start = try number(cx, t, i.*);
        i.* += 1;
        if (kw(t, i.*, "to")) {
            const stop = try number(cx, t, i.* + 1);
            i.* += 2;
            var inc: f64 = 1;
            if (kw(t, i.*, "by")) {
                inc = try number(cx, t, i.* + 1);
                i.* += 2;
            }
            if (!(inc > 0)) return gap(cx, lineOf(t, i.*), "a TO list with a non-positive BY increment is not verified", .{});
            var k: f64 = 0;
            while (start + k * inc <= stop + 1e-9 * @abs(inc)) : (k += 1) try vals.append(a, start + k * inc);
        } else try vals.append(a, start);
        if (at(t, i.*, .comma)) i.* += 1;
    }
    if (vals.items.len == 0) return invalid(cx, t, i.*);
    return vals.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var i: usize = 2;
    const l0 = lineOf(t, 0);
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            if (data != null) return user(cx, t[i].line, "DATA= is specified more than once", .{});
            i += 2;
            data = try dsName(a, cx, t, &i);
            // Data set options are applied by procInput below.
            if (at(t, i, .lparen)) {
                var depth: usize = 0;
                while (i < t.len and !at(t, i, .eof)) : (i += 1) {
                    if (kw(t, i, "type") and at(t, i + 1, .eq)) return gap(cx, t[i].line, "the TYPE= data set option (TYPE=DISTANCE input) is not implemented", .{});
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (eq(word, "out") and valued) {
            i += 2;
            s.out = try dsName(a, cx, t, &i);
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on OUT= are not implemented", .{});
        } else if ((eq(word, "cluster") or eq(word, "density")) and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            if (eq(word, "cluster")) s.cluster_name = t[i + 2].text else s.density_name = t[i + 2].text;
            i += 3;
        } else if ((eq(word, "method") or eq(word, "met") or eq(word, "m")) and valued) {
            i += 2;
            s.methods = try valueList(cx, t, &i);
            for (s.methods) |m| {
                if (m != @floor(m) or m < 0 or m > 6) return user(cx, l0, "METHOD= must be an integer from 0 to 6", .{});
                if (m > 1) return gap(cx, l0, "METHOD={d} is not implemented (STAT-MODECLUS-003); only METHOD=0 and METHOD=1 are", .{m});
            }
        } else if ((eq(word, "r") or eq(word, "dr") or eq(word, "cr")) and valued) {
            i += 2;
            const vals = try valueList(cx, t, &i);
            for (vals) |v| if (!(v > 0)) return user(cx, l0, "the {s}= radius must be positive", .{try std.ascii.allocUpperString(a, word)});
            if (eq(word, "r")) s.r = vals else if (eq(word, "dr")) s.dr = vals else s.cr = vals;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "nosummary")) {
            s.nosummary = true;
            i += 1;
        } else if (eq(word, "short")) {
            s.short = true;
            i += 1;
        } else {
            for (unimplemented) |u| if (eq(word, u))
                return gap(cx, t[i].line, "the {s} option is not implemented (STAT-MODECLUS-003/-004/-005)", .{try std.ascii.allocUpperString(a, word)});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = if (data) |name|
        cx.lib.find(name) orelse return user(cx, l0, "input data set {s} not found", .{name})
    else
        proc.lastDataset(cx.lib) orelse return user(cx, l0, "there is no default input data set (_LAST_ is _NULL_)", .{});
    s.ds = try proc.procInput(a, raw, t, cx.diags);

    var bys: by.Statements = .{};
    var by_seen = false;
    var var_line: usize = 0;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "var")) {
            if (s.var_given) return gap(cx, t[i].line, "more than one VAR statement is not implemented", .{});
            s.var_given = true;
            var_line = t[i].line;
            if (end == i + 1) return invalid(cx, t, end);
            var cols: std.ArrayList(usize) = .empty;
            var j = i + 1;
            while (j < end) {
                const line = t[j].line;
                const names = try lists.next(a, s.ds, t[0..end], &j, cx.diags);
                for (names) |n| {
                    const c = s.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                    for (cols.items) |prev| if (prev == c) return user(cx, line, "variable {s} appears more than once in the VAR statement", .{s.ds.columns.items[c].name});
                    try cols.append(a, c);
                }
            }
            s.vars = cols.items;
        } else if (kw(t, i, "id") or kw(t, i, "freq")) {
            const is_id = kw(t, i, "id");
            if (end != i + 2 or !at(t, i + 1, .name)) return user(cx, t[i].line, "the {s} statement takes exactly one variable", .{if (is_id) @as([]const u8, "ID") else "FREQ"});
            if ((if (is_id) s.id else s.freq) != null) return gap(cx, t[i].line, "more than one {s} statement is not verified", .{if (is_id) @as([]const u8, "ID") else "FREQ"});
            const c = s.ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i + 1].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, t[i + 1].text)});
            if (is_id) s.id = c else {
                if (s.ds.columns.items[c].type != .num) return user(cx, t[i].line, "FREQ variable {s} must be numeric", .{s.ds.columns.items[c].name});
                s.freq = c;
            }
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.6825).
            by_seen = true;
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            // Step boundary tokens may reach the body.
        } else if (kw(t, i, "where")) {
            // WHERE is applied by procInput.
        } else if (kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib") or kw(t, i, "weight")) {
            return gap(cx, t[i].line, "the {s} statement is not implemented", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    const cols = s.ds.columns.items;
    if (s.var_given) {
        for (s.vars) |v| if (cols[v].type != .num) return user(cx, var_line, "VAR variable {s} must be numeric", .{cols[v].name});
    } else {
        // "If you omit the VAR statement, all numeric variables not specified
        // in other statements are used" (p.6826).
        try cx.diags.note(l0, "No VAR statement is given. All numerical variables not named elsewhere make up the first set of variables.", .{});
        var vs: std.ArrayList(usize) = .empty;
        for (cols, 0..) |c, k| {
            if (c.type != .num) continue;
            if (std.mem.indexOfScalar(usize, s.by_cols, k) != null) continue;
            if (s.id == k or s.freq == k) continue;
            try vs.append(a, k);
        }
        s.vars = vs.items;
    }
    if (s.vars.len == 0) return user(cx, l0, "there are no numeric variables to cluster", .{});
    // STAT-COMMON-019: a TYPE=DISTANCE member (e.g. PROC DISTANCE OUT=) must
    // not be clustered as coordinates; distance input is not implemented.
    if (s.ds.ds_type) |ty| if (!eq(ty, "data"))
        return gap(cx, l0, "an input data set of TYPE={s} is not implemented (distance input)", .{ty});
    return s;
}

/// One analysis: density radius, clustering radius and method.
pub const Analysis = struct { dr: f64, cr: f64, method: u8 };

pub const Plan = struct {
    analyses: []const Analysis,
    /// Which smoothing option the user named (header, summary and OUT=).
    form: enum { r, drcr, default },
    multi_method: bool,
};

fn listAt(l: []const f64, k: usize) ?f64 {
    if (l.len == 0) return null;
    return if (l.len == 1) l[0] else l[k];
}

pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error!Plan {
    const a = cx.arena;
    if (s.methods.len == 0) return gap(cx, 0, "density estimation without METHOD= (no cluster analysis) is not implemented", .{});
    if (s.r.len > 0 and (s.dr.len > 0 or s.cr.len > 0)) return gap(cx, 0, "R= combined with DR= or CR= is not verified", .{});
    if (s.r.len == 0 and (s.dr.len > 0) != (s.cr.len > 0)) return gap(cx, 0, "DR= without CR= (or CR= without DR=) is not implemented", .{});
    var len: usize = 1;
    for ([_][]const f64{ s.r, s.dr, s.cr }) |l| if (l.len > 1) {
        if (len > 1 and l.len != len) return user(cx, 0, "lists of smoothing parameters must have one value or the same number of values", .{});
        len = l.len;
    };
    if (len > 1 and s.methods.len > 1) return gap(cx, 0, "a METHOD= list combined with a smoothing-parameter list is not verified", .{});
    const form: @TypeOf(@as(Plan, undefined).form) = if (s.r.len > 0) .r else if (s.dr.len > 0) .drcr else .default;
    var out: std.ArrayList(Analysis) = .empty;
    for (0..len) |k| for (s.methods) |m| {
        const dr = listAt(s.r, k) orelse listAt(s.dr, k) orelse 0;
        const cr = listAt(s.r, k) orelse listAt(s.cr, k) orelse 0;
        try out.append(a, .{ .dr = dr, .cr = cr, .method = @intFromFloat(m) });
    };
    return .{ .analyses = out.items, .form = form, .multi_method = s.methods.len > 1 };
}

/// "A reasonable first guess for the R= option" (p.6827), used when no
/// smoothing parameter is given:
/// [2^(v+2) (v+2) Gamma(v/2+1) / (n v^2)]^(1/(v+4)) * sqrt(sum s_l^2).
pub fn defaultRadius(x: []const f64, w: []const f64, v: usize) f64 {
    const vf: f64 = @floatFromInt(v);
    const n = x.len / v;
    var nw: f64 = 0;
    for (w) |f| nw += f;
    var ss: f64 = 0;
    for (0..v) |l| {
        var m: f64 = 0;
        for (0..n) |r| m += w[r] * x[r * v + l];
        m /= nw;
        var q: f64 = 0;
        for (0..n) |r| q += w[r] * (x[r * v + l] - m) * (x[r * v + l] - m);
        ss += q / (nw - 1);
    }
    const c = std.math.pow(f64, 2, vf + 2) * (vf + 2) * std.math.gamma(f64, vf / 2 + 1) / (nw * vf * vf);
    return std.math.pow(f64, c, 1 / (vf + 4)) * @sqrt(ss);
}

pub const ClusterStat = struct { freq: f64, mode: f64, bfreq: f64, saddle: ?f64 };

pub const Solution = struct {
    density: []const f64,
    /// One-based cluster per point, ordered by decreasing maximum density.
    cluster: []const usize,
    stats: []const ClusterStat,
};

fn dist2(x: []const f64, v: usize, i: usize, j: usize) f64 {
    var d: f64 = 0;
    for (0..v) |l| {
        const e = x[i * v + l] - x[j * v + l];
        d += e * e;
    }
    return d;
}

fn find(p: []usize, i: usize) usize {
    var r = i;
    while (p[r] != r) r = p[r];
    var k = i;
    while (p[k] != r) {
        const nx = p[k];
        p[k] = r;
        k = nx;
    }
    return r;
}

/// Uniform-kernel density estimate (p.6827): f_i = n_i / (n v_i), with n_i
/// the frequency within distance r of x_i (itself included) and v_i the
/// volume pi^(v/2) r^v / Gamma(v/2+1).
pub fn densities(a: A, x: []const f64, w: []const f64, v: usize, r: f64) ![]f64 {
    const n = w.len;
    var nw: f64 = 0;
    for (w) |f| nw += f;
    const vf: f64 = @floatFromInt(v);
    const vol = std.math.pow(f64, std.math.pi, vf / 2) * std.math.pow(f64, r, vf) / std.math.gamma(f64, vf / 2 + 1);
    const f = try a.alloc(f64, n);
    for (0..n) |i| {
        var c: f64 = 0;
        for (0..n) |j| if (dist2(x, v, i, j) <= r * r) {
            c += w[j];
        };
        f[i] = c / (nw * vol);
    }
    return f;
}

/// METHOD=0 and METHOD=1 (pp.6829-6830) on fixed clustering neighbourhoods
/// (an observation is not its own neighbour).
pub fn cluster(a: A, x: []const f64, w: []const f64, v: usize, f: []const f64, cr: f64, method: u8) !Solution {
    const n = w.len;
    const p = try a.alloc(usize, n);
    for (p, 0..) |*q, k| q.* = k;
    const nb = try a.alloc([]usize, n);
    for (0..n) |i| {
        var l: std.ArrayList(usize) = .empty;
        for (0..n) |j| if (j != i and dist2(x, v, i, j) <= cr * cr) try l.append(a, j);
        nb[i] = l.items;
    }
    // Maximum density of each union-find root.
    const top = try a.alloc(f64, n);
    @memcpy(top, f);
    const Join = struct {
        fn run(pp: []usize, tt: []f64, i: usize, j: usize) void {
            const ri = find(pp, i);
            const rj = find(pp, j);
            if (ri == rj) return;
            pp[ri] = rj;
            tt[rj] = @max(tt[rj], tt[ri]);
        }
    };
    if (method == 0) {
        for (0..n) |i| for (nb[i]) |j| Join.run(p, top, i, j);
    } else {
        // Nearest neighbour with a greater estimated density.
        const peak = try a.alloc(bool, n);
        for (0..n) |i| {
            var best: ?usize = null;
            var bd: f64 = 0;
            var any_eq = false;
            var any_gt = false;
            for (nb[i]) |j| {
                if (f[j] == f[i]) any_eq = true;
                if (f[j] > f[i]) {
                    any_gt = true;
                    const d = dist2(x, v, i, j);
                    if (best == null or d < bd) {
                        best = j;
                        bd = d;
                    }
                }
            }
            if (best) |j| Join.run(p, top, i, j);
            peak[i] = any_eq and !any_gt;
        }
        // Plateaus: join (1) neighbours' clusters whose maximum equals f_i and
        // (2) the nearest neighbour's cluster whose maximum exceeds f_i.
        for (0..n) |i| if (peak[i]) {
            var best: ?usize = null;
            var bd: f64 = 0;
            for (nb[i]) |j| {
                const mx = top[find(p, j)];
                if (mx == f[i]) Join.run(p, top, i, j) else if (mx > f[i]) {
                    const d = dist2(x, v, i, j);
                    if (best == null or d < bd) {
                        best = j;
                        bd = d;
                    }
                }
            }
            if (best) |j| Join.run(p, top, i, j);
        };
    }
    // Number clusters by decreasing maximum density; ties by first member.
    var roots: std.ArrayList(usize) = .empty;
    const root_of = try a.alloc(usize, n);
    for (0..n) |i| {
        root_of[i] = find(p, i);
        if (std.mem.indexOfScalar(usize, roots.items, root_of[i]) == null) try roots.append(a, root_of[i]);
    }
    const Ctx = struct {
        t: []const f64,
        fn less(c: @This(), l: usize, r: usize) bool {
            return c.t[l] > c.t[r];
        }
    };
    std.sort.insertion(usize, roots.items, Ctx{ .t = top }, Ctx.less);
    const cl = try a.alloc(usize, n);
    for (0..n) |i| cl[i] = std.mem.indexOfScalar(usize, roots.items, root_of[i]).? + 1;
    const stats = try a.alloc(ClusterStat, roots.items.len);
    for (stats, roots.items) |*st, rt| st.* = .{ .freq = 0, .mode = top[rt], .bfreq = 0, .saddle = null };
    // Boundary members and the estimated saddle point (p.6834):
    // s(k) maximises 0.2 f_i n_i + sum of f_j over neighbours in other clusters.
    const score = try a.alloc(f64, stats.len);
    @memset(score, -1);
    for (0..n) |i| {
        const k = cl[i] - 1;
        stats[k].freq += w[i];
        var other: f64 = 0;
        var boundary = false;
        var ni: f64 = 1;
        for (nb[i]) |j| {
            ni += 1;
            if (cl[j] != cl[i]) {
                boundary = true;
                other += f[j];
            }
        }
        if (!boundary) continue;
        stats[k].bfreq += w[i];
        const sc = 0.2 * f[i] * ni + other;
        if (sc > score[k]) {
            score[k] = sc;
            stats[k].saddle = f[i];
        }
    }
    return .{ .density = f, .cluster = cl, .stats = stats };
}

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn bestw(a: A, x: f64, w: usize) ![]const u8 {
    return format.bestNumW(a, x, w) catch return error.OutOfMemory;
}

/// Density column text: the reference listings show fixed notation with ten
/// significant columns and trailing zeros dropped (0.00106103, 0.0001061).
/// ponytail: magnitudes outside [7E-5, 1E5) are not verified and gap (the
/// smallest reference value is 0.00007895).
pub fn densityText(a: A, x: f64) !?[]const u8 {
    if (!(x >= 7e-5 and x < 1e5)) return null;
    var places: usize = 8;
    var m = x;
    while (m >= 10) : (m /= 10) places -= 1;
    var text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, places });
    while (text[text.len - 1] == '0') text = text[0 .. text.len - 1];
    if (text[text.len - 1] == '.') text = text[0 .. text.len - 1];
    return text;
}

/// The "Cluster Statistics" table (SAS 15.4 reference listing).
/// Densities must have been screened with `densityText` first.
pub fn renderStats(a: A, out: *Out, stats: []const ClusterStat) !void {
    try out.appendSlice(a, "                      Cluster Statistics\n");
    try out.appendSlice(a, "                            Maximum                   Estimated\n");
    try out.appendSlice(a, "                          Estimated      Boundary        Saddle\n");
    try out.appendSlice(a, "Cluster     Frequency       Density     Frequency       Density\n");
    try out.appendNTimes(a, '-', 63);
    try out.append(a, '\n');
    for (stats, 1..) |st, k| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k}), 7, true);
        try pad(a, out, try bestw(a, st.freq, 12), 14, false);
        try pad(a, out, (try densityText(a, st.mode)).?, 14, false);
        try pad(a, out, try bestw(a, st.bfreq, 12), 14, false);
        try pad(a, out, if (st.saddle) |sd| (try densityText(a, sd)).? else ".", 14, false);
        try out.append(a, '\n');
    }
}

pub const SummaryRow = struct { r: f64, method: u8, nclus: usize, uncl: f64 };

/// The "Cluster Summary" table (SAS 15.4 reference runs, R= form).
pub fn renderSummary(a: A, out: *Out, rows: []const SummaryRow, multi_method: bool) !void {
    if (multi_method) {
        try out.appendSlice(a, "                Cluster Summary\n");
        try out.appendSlice(a, "                                  Frequency of\n");
        try out.appendSlice(a, "                     Number of    Unclassified\n");
        try out.appendSlice(a, "      R    Method     Clusters         Objects\n");
        try out.appendNTimes(a, '-', 46);
    } else {
        try out.appendSlice(a, "           Cluster Summary\n");
        try out.appendSlice(a, "                        Frequency of\n");
        try out.appendSlice(a, "           Number of    Unclassified\n");
        try out.appendSlice(a, "      R     Clusters         Objects\n");
        try out.appendNTimes(a, '-', 36);
    }
    try out.append(a, '\n');
    for (rows) |r| {
        try pad(a, out, try bestw(a, r.r, 7), 7, false);
        if (multi_method) try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{r.method}), 10, false);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{r.nclus}), 13, false);
        try pad(a, out, try bestw(a, r.uncl, 12), 16, false);
        try out.append(a, '\n');
    }
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => false,
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const pl = try plan(cx, s);
    if (!s.nosummary and !s.noprint and pl.form == .drcr) return gap(cx, 0, "the Cluster Summary layout for DR=/CR= is not verified; specify NOSUMMARY", .{});
    if (s.out != null and pl.form == .default) return gap(cx, 0, "OUT= with the default smoothing parameter is not verified", .{});
    if (s.out != null and s.id == null and s.by_cols.len > 0) return gap(cx, 0, "_OBS_ numbering with BY groups is not verified; add an ID statement", .{});
    if (s.out != null and s.id == null) for (t) |tok| if (tok.tag == .name and (eq(tok.text, "where") or eq(tok.text, "firstobs") or eq(tok.text, "obs")))
        return gap(cx, 0, "_OBS_ numbering with WHERE or FIRSTOBS=/OBS= selection is not verified; add an ID statement", .{});
    if (s.ds.rows.items.len == 0) return gap(cx, 0, "an input data set with no observations is not verified", .{});
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const v = s.vars.len;
    const cols = s.ds.columns.items;

    // OUT= layout (SAS 15.4 reference run): input variables, _R_ or _DR_ and
    // _CR_, _METHOD_, _OBS_ (no ID statement), DENSITY, CLUSTER.
    var o: ?*Dataset = null;
    if (s.out) |member| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, member);
        for (cols) |c| _ = try d.addColumnLike(c.name, c);
        const extra: []const []const u8 = if (pl.form == .r) &.{"_R_"} else &.{ "_DR_", "_CR_" };
        var names: std.ArrayList([]const u8) = .empty;
        try names.appendSlice(a, extra);
        try names.append(a, "_METHOD_");
        if (s.id == null) try names.append(a, "_OBS_");
        try names.append(a, s.density_name);
        try names.append(a, s.cluster_name);
        for (names.items) |nm| {
            if (d.indexOf(nm) != null) return gap(cx, 0, "output variable {s} collides with an input variable; the rule is not verified", .{nm});
            _ = try d.addColumn(nm, .num);
        }
        d.setLabel("_METHOD_", "Clustering Method");
        d.setLabel("_OBS_", "Observation Number from Input Data");
        d.setLabel(s.density_name, "Estimated Density");
        o = d;
    }

    var obs_base: usize = 0;
    for (slices) |slice| {
        const rows = slice.rows;
        // Coordinates with a missing value are excluded (p.6837).
        var keep: std.ArrayList(usize) = .empty;
        var excluded: usize = 0;
        for (rows, 0..) |row, r| {
            var miss = false;
            for (s.vars) |c| if (missing(row[c])) {
                miss = true;
            };
            if (s.freq) |fc| {
                const fv = row[fc].num;
                if (std.math.isNan(fv) or fv < 1) return gap(cx, 0, "a missing or less-than-one FREQ value is not verified", .{});
            }
            if (miss) excluded += 1 else try keep.append(a, r);
        }
        const n = keep.items.len;
        if (n < 2) return gap(cx, 0, "a BY group with fewer than two usable observations is not verified", .{});
        const x = try a.alloc(f64, n * v);
        const w = try a.alloc(f64, n);
        for (keep.items, 0..) |r, k| {
            for (s.vars, 0..) |c, l| x[k * v + l] = rows[r][c].num;
            // Nonintegral frequencies are truncated (p.6826).
            w[k] = if (s.freq) |fc| @floor(rows[r][fc].num) else 1;
        }
        const r0 = if (pl.form == .default) defaultRadius(x, w, v) else 0;
        var summary: std.ArrayList(SummaryRow) = .empty;
        for (pl.analyses) |an| {
            const dr = if (pl.form == .default) r0 else an.dr;
            const cr = if (pl.form == .default) r0 else an.cr;
            const f = try densities(a, x, w, v, dr);
            const sol = try cluster(a, x, w, v, f, cr, an.method);
            for (sol.stats) |st| {
                for ([_]?f64{ st.mode, st.saddle }) |maybe| if (maybe) |d| if ((try densityText(a, d)) == null)
                    return gap(cx, 0, "the listing format of density {d} is not verified", .{d});
            }
            try summary.append(a, .{ .r = dr, .method = an.method, .nclus = sol.stats.len, .uncl = 0 });
            if (!s.noprint and !s.short) {
                try pageStart(cx, out);
                try byLine(a, out, s, slice);
                try out.appendSlice(a, "\nThe MODECLUS Procedure\n");
                if (pl.form == .drcr)
                    try out.print(a, "  DR={s}  CR={s}  METHOD={d}\n\n", .{ try bestw(a, dr, 12), try bestw(a, cr, 12), an.method })
                else
                    try out.print(a, "  R={s}  METHOD={d}\n\n", .{ try bestw(a, dr, 12), an.method });
                try renderStats(a, out, sol.stats);
                // SAS 15.4 reference run: excluded (missing) observations.
                if (excluded > 0) try out.print(a, "\n{d} observations with frequency 0 were unassigned.\n", .{excluded});
                if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
            }
            if (o) |d| {
                var k: usize = 0;
                for (rows, 0..) |row, r| {
                    const vals = try a.alloc(Value, d.columns.items.len);
                    @memcpy(vals[0..cols.len], row);
                    var c = cols.len;
                    if (pl.form == .r) {
                        vals[c] = .{ .num = dr };
                        c += 1;
                    } else {
                        vals[c] = .{ .num = dr };
                        vals[c + 1] = .{ .num = cr };
                        c += 2;
                    }
                    vals[c] = .{ .num = @floatFromInt(an.method) };
                    c += 1;
                    if (s.id == null) {
                        vals[c] = .{ .num = @floatFromInt(obs_base + r + 1) };
                        c += 1;
                    }
                    if (k < n and keep.items[k] == r) {
                        vals[c] = .{ .num = sol.density[k] };
                        vals[c + 1] = .{ .num = @floatFromInt(sol.cluster[k]) };
                        k += 1;
                    } else {
                        vals[c] = Value.missing;
                        vals[c + 1] = Value.missing;
                    }
                    try d.appendRow(vals);
                }
            }
        }
        if (!s.noprint and !s.nosummary) {
            try pageStart(cx, out);
            try byLine(a, out, s, slice);
            try out.appendSlice(a, "\nThe MODECLUS Procedure\n\n");
            try renderSummary(a, out, summary.items, pl.multi_method);
            if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
        }
        obs_base += rows.len;
    }
    if (o) |d| {
        const member = s.out.?;
        try cx.lib.put(member, d);
        const upper = try std.ascii.allocUpperString(a, member);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, d.rows.items.len, d.columns.items.len });
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
    _ = @import("modeclus_tests.zig");
}
