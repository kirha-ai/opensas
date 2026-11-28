//! PROC FASTCLUS (SAS/STAT 15.4 ch.45, STAT-FASTCLUS-001): PROC statement
//! options, VAR / ID / FREQ / WEIGHT / BY roles, missing values, the least
//! squares (k-means) path with REPLACE=FULL|PART|NONE seed selection and
//! nearest-centroid iteration, the default listing and the OUT= data set.
//!
//! Algorithm (pp.2895-2897, 2903-2913):
//! - Seeds: the first complete observation; later complete observations become
//!   new seeds when their minimum distance to the seeds exceeds RADIUS= while
//!   fewer than MAXCLUSTERS= seeds exist; otherwise the two replacement tests.
//! - Each iteration assigns every observation to the nearest seed, reports the
//!   criterion sqrt(SSE / (sum of weights * nvar)) and replaces the seeds by
//!   the cluster means; the relative change is the seed move divided by the
//!   minimum distance between the initial seeds; stop when <= CONVERGE=.
//! - CCC / approximate expected R-square: Sarle (1983) with the total STDs as
//!   the (uncorrelated) dimension scales; verified against the SAS listing.
//! Everything else the cited pages define is a loud D-009 gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Replace = enum { full, part, none };

pub const Spec = struct {
    input: proc.ProcInput,
    maxc: ?usize = null,
    radius: ?f64 = null,
    maxiter: usize = 1,
    converge: f64 = 0.02,
    replace: Replace = .full,
    out: ?[]const u8 = null,
    cluster_name: []const u8 = "CLUSTER",
    noprint: bool = false,
    short: bool = false,
    uncorrelated: bool = false,
    nomiss: bool = false,
    vars: []const usize = &.{},
    id: ?usize = null,
    freq: ?usize = null,
    weight: ?usize = null,
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
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC FASTCLUS: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn number(t: []const lex.Token, i: usize, into: *f64) ?usize {
    var j = i;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    } else if (at(t, j, .plus)) j += 1;
    if (!at(t, j, .number)) return null;
    into.* = sign * (std.fmt.parseFloat(f64, t[j].text) catch return null);
    return j + 1;
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
    if (at(t, j, .lparen)) return proc.failGap(cx.diags, t[i].line, "PROC FASTCLUS: data set options on an output data set are not implemented", .{});
    into.* = name;
    return j;
}
fn oneVar(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, numeric: bool) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC FASTCLUS: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC FASTCLUS: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}

const gap_valued = [_][]const u8{ "seed", "instat", "vardef", "clusterlabel", "outseed", "outs", "mean", "outstat", "random", "delete", "least", "l", "strict", "bins", "hc", "hp" };
const gap_flags = [_][]const u8{ "outiter", "drift", "strict", "irls", "impute", "distance", "dist", "list", "summary" };

fn isOne(list: []const []const u8, w: []const u8) bool {
    for (list) |x| if (eq(x, w)) return true;
    return false;
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
        const l = t[i].line;
        var option: []const u8 = try std.ascii.allocLowerString(a, t[i].text);
        // Documented aliases share one duplicate key.
        if (std.mem.eql(u8, option, "maxc")) option = "maxclusters";
        if (std.mem.eql(u8, option, "r")) option = "radius";
        if (std.mem.eql(u8, option, "conv")) option = "converge";
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, l, "PROC FASTCLUS: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            name = t[first].text;
            var j = first + 1;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[first].text, t[j + 1].text });
                qualified = first;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &s.out);
        } else if (eq(option, "cluster") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: CLUSTER= must be a variable name", .{});
            s.cluster_name = t[i + 2].text;
            i += 3;
        } else if ((eq(option, "maxclusters") or eq(option, "maxiter")) and valued) {
            var v: f64 = 0;
            i = number(t, i + 2, &v) orelse return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: {s}= must be a number", .{t[i].text});
            if (v != @floor(v) or v > 1e9) return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: {s}= must be an integer", .{t[i - 3].text});
            if (eq(option, "maxclusters")) {
                if (!(v >= 1)) return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: MAXCLUSTERS= must be a positive integer", .{});
                s.maxc = @intFromFloat(v);
            } else {
                if (!(v >= 0)) return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: MAXITER= must be a nonnegative integer", .{});
                s.maxiter = @intFromFloat(v);
            }
        } else if ((eq(option, "radius") or eq(option, "converge")) and valued) {
            var v: f64 = 0;
            i = number(t, i + 2, &v) orelse return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: {s}= must be a number", .{t[i].text});
            if (!(v >= 0)) return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: {s} must be nonnegative", .{option});
            if (eq(option, "radius")) s.radius = v else s.converge = v;
        } else if (eq(option, "replace") and valued) {
            if (kw(t, i + 2, "full")) s.replace = .full else if (kw(t, i + 2, "part")) s.replace = .part else if (kw(t, i + 2, "none")) s.replace = .none else if (kw(t, i + 2, "random")) {
                return gap(cx.diags, l, "PROC FASTCLUS: REPLACE=RANDOM (SAS pseudo-random seed sample) is not implemented", .{});
            } else return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: REPLACE= must be FULL, PART, NONE or RANDOM", .{});
            i += 3;
        } else if (valued and isOne(&gap_valued, option)) {
            return gap(cx.diags, l, "PROC FASTCLUS: the {s}= option is not implemented (STAT-FASTCLUS-002..006)", .{t[i].text});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "short")) {
            s.short = true;
            i += 1;
        } else if (eq(option, "nomiss")) {
            s.nomiss = true;
            i += 1;
        } else if (eq(option, "variablesareuncorrelated")) {
            s.uncorrelated = true;
            i += 1;
        } else if (isOne(&gap_flags, option)) {
            return gap(cx.diags, l, "PROC FASTCLUS: the {s} option is not implemented (STAT-FASTCLUS-002..006)", .{t[i].text});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.2891: MAXCLUSTERS= or RADIUS= (or both) is required.
    if (s.maxc == null and s.radius == null) return cx.diags.fail(error.ParseError, line(t, 0), "You must specify either RADIUS= or MAXCLUSTERS=", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC FASTCLUS: input data set not found", .{});
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
            // p.2898: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx.diags, t[i].line, "PROC FASTCLUS: more than one VAR statement is not verified", .{});
            var_seen = true;
            if (end == i + 1) return invalid(cx, t, end);
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                for (try lists.next(a, ds, body, &j, cx.diags)) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC FASTCLUS: variable {s} in the VAR statement is not on the input data set", .{n});
                    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "Variable {s} in list does not match type prescribed for this list.", .{n});
                    if (has(vars.items, ci)) return gap(cx.diags, l, "PROC FASTCLUS: variable {s} listed twice in the VAR statement is not verified", .{n});
                    try vars.append(a, ci);
                }
            }
        } else if (eq(word, "id")) {
            if (s.id != null) return gap(cx.diags, t[i].line, "PROC FASTCLUS: more than one ID statement is not verified", .{});
            s.id = try oneVar(cx, ds, t, i, end, "ID", false);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC FASTCLUS: more than one FREQ statement is not verified", .{});
            s.freq = try oneVar(cx, ds, t, i, end, "FREQ", true);
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC FASTCLUS: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneVar(cx, ds, t, i, end, "WEIGHT", true);
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
    // p.2900: without VAR, all numeric variables not listed in other statements.
    if (!var_seen) {
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or s.freq == ci or s.weight == ci or s.id == ci) continue;
            try vars.append(a, ci);
        }
    }
    if (vars.items.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC FASTCLUS: no numeric variables to cluster", .{});
    for (vars.items) |ci| if (s.freq == ci or s.weight == ci or has(cols, ci))
        return gap(cx.diags, line(t, 0), "PROC FASTCLUS: variable {s} in both the VAR statement and another role is not verified", .{ds.columns.items[ci].name});
    s.vars = vars.items;
    return s;
}

/// One analysed observation: its row index, coordinates and weight (FREQ*WEIGHT).
const Obs = struct { row: usize, x: []const f64, w: f64, f: f64, complete: bool = true };

/// Squared distance over the variables present in both; p.2901: scaled by
/// nvar / nonmissing so a partially missing observation stays comparable.
fn dist2(x: []const f64, y: []const f64) f64 {
    var d: f64 = 0;
    var m: usize = 0;
    for (x, y) |u, v| if (!std.math.isNan(u) and !std.math.isNan(v)) {
        d += (u - v) * (u - v);
        m += 1;
    };
    return if (m == x.len) d else d * @as(f64, @floatFromInt(x.len)) / @as(f64, @floatFromInt(m));
}
/// Unscaled squared deviations over the nonmissing values (criterion).
fn raw2(x: []const f64, y: []const f64) f64 {
    var d: f64 = 0;
    for (x, y) |u, v| if (!std.math.isNan(u) and !std.math.isNan(v)) {
        d += (u - v) * (u - v);
    };
    return d;
}

fn nearest(seeds: []const []f64, x: []const f64) struct { k: usize, d2: f64 } {
    var best: usize = 0;
    var bd: f64 = std.math.inf(f64);
    for (seeds, 0..) |sd, k| {
        const d = dist2(sd, x);
        if (d < bd) {
            bd = d;
            best = k;
        }
    }
    return .{ .k = best, .d2 = bd };
}

/// Minimum distance from seed `k` to every other seed, the seed at index
/// `swap` being replaced by `x` (swap == null: no replacement).
fn minOther(seeds: []const []f64, k: usize, swap: ?usize, x: []const f64) f64 {
    var m: f64 = std.math.inf(f64);
    for (seeds, 0..) |sd, j| {
        if (j == k) continue;
        const other = if (swap != null and swap.? == j) x else sd;
        m = @min(m, dist2(seeds[k], other));
    }
    return m;
}

/// Initial seed selection (pp.2884-2885). Returns the seeds in slot order.
pub fn selectSeeds(a: A, obs: []const Obs, p: usize, maxc: usize, radius: f64, replace: Replace) ![][]f64 {
    var seeds: std.ArrayList([]f64) = .empty;
    const r2 = radius * radius;
    for (obs) |o| {
        if (!o.complete) continue; // p.2901: seeds have no missing values.
        if (seeds.items.len == 0) {
            try seeds.append(a, try a.dupe(f64, o.x));
            continue;
        }
        const nr = nearest(seeds.items, o.x);
        if (seeds.items.len < maxc and nr.d2 > r2) {
            try seeds.append(a, try a.dupe(f64, o.x));
            continue;
        }
        if (replace == .none or seeds.items.len < 2) continue;
        // Test 1: farther from every seed than the two closest seeds are apart.
        var pi: usize = 0;
        var pj: usize = 1;
        var pd: f64 = std.math.inf(f64);
        for (seeds.items, 0..) |si, ii| for (seeds.items[ii + 1 ..], ii + 1..) |sj, jj| {
            const d = dist2(si, sj);
            if (d < pd) {
                pd = d;
                pi = ii;
                pj = jj;
            }
        };
        if (nr.d2 > pd) {
            // Replace the one of the pair closer to the remaining seeds when the
            // other is replaced by the observation.
            const di = minOther(seeds.items, pi, pj, o.x);
            const dj = minOther(seeds.items, pj, pi, o.x);
            const victim = if (di < dj) pi else pj; // verified: a tie replaces the later seed
            @memcpy(seeds.items[victim], o.x);
            continue;
        }
        if (replace == .part) continue;
        // Test 2: nearest seed replaced when the observation is farther from
        // the other seeds than the nearest seed is.
        var second: f64 = std.math.inf(f64);
        for (seeds.items, 0..) |sd, k| if (k != nr.k) {
            second = @min(second, dist2(sd, o.x));
        };
        if (second > minOther(seeds.items, nr.k, null, o.x)) @memcpy(seeds.items[nr.k], o.x);
    }
    _ = p;
    return seeds.items;
}

pub const Group = struct {
    initial: [][]f64,
    min_seed_dist: f64,
    history: []const []const f64, // per iteration: criterion, then changes
    converged: bool,
    seeds: [][]f64,
    final_crit: f64,
    assign: []usize,
    dist: []f64,
    freq: []f64,
    means: [][]f64,
    stds: [][]f64,
    rms: []f64,
    maxdist: []f64,
    near: []usize,
    gapd: []f64,
    total_std: []f64,
    within_std: []f64,
    rsq: []f64,
    over: [3]f64,
    pseudo_f: f64,
    ersq: f64,
    ccc: f64,
    n: f64,
};

pub const Fail = error{ OutOfMemory, EmptyCluster, OneCluster, Degenerate };

pub fn analyze(a: A, obs: []const Obs, p: usize, s: Spec) Fail!Group {
    const maxc = s.maxc orelse 100;
    const initial = try selectSeeds(a, obs, p, maxc, s.radius orelse 0, s.replace);
    const c = initial.len;
    if (c < 2) return error.OneCluster;
    var g: Group = undefined;
    g.initial = try a.alloc([]f64, c);
    for (initial, 0..) |sd, k| g.initial[k] = try a.dupe(f64, sd);
    var md: f64 = std.math.inf(f64);
    for (initial, 0..) |si, ii| for (initial[ii + 1 ..]) |sj| {
        md = @min(md, dist2(si, sj));
    };
    g.min_seed_dist = @sqrt(md);
    if (!(g.min_seed_dist > 0)) return error.Degenerate;
    var sw: f64 = 0; // sum of weights over nonmissing values (criterion divisor)
    var nf: f64 = 0;
    for (obs) |o| {
        for (o.x) |v| if (!std.math.isNan(v)) {
            sw += o.w;
        };
        nf += o.f;
    }
    g.n = nf;
    const pf: f64 = @floatFromInt(p);
    const seeds = initial;
    var hist: std.ArrayList([]const f64) = .empty;
    g.converged = false;
    const sums = try a.alloc(f64, c * p);
    const wts = try a.alloc(f64, c * p);
    for (0..s.maxiter) |_| {
        @memset(sums, 0);
        @memset(wts, 0);
        var sse: f64 = 0;
        for (obs) |o| {
            const nr = nearest(seeds, o.x);
            sse += o.w * raw2(o.x, seeds[nr.k]);
            for (o.x, 0..) |v, j| if (!std.math.isNan(v)) {
                sums[nr.k * p + j] += o.w * v;
                wts[nr.k * p + j] += o.w;
            };
        }
        const row = try a.alloc(f64, c + 1);
        row[0] = @sqrt(sse / sw);
        var maxch: f64 = 0;
        for (0..c) |k| {
            var d: f64 = 0;
            for (0..p) |j| {
                if (!(wts[k * p + j] > 0)) return error.EmptyCluster;
                const nv = sums[k * p + j] / wts[k * p + j];
                d += (nv - seeds[k][j]) * (nv - seeds[k][j]);
                seeds[k][j] = nv;
            }
            row[k + 1] = @sqrt(d) / g.min_seed_dist;
            maxch = @max(maxch, row[k + 1]);
        }
        try hist.append(a, row);
        if (maxch <= s.converge) {
            g.converged = true;
            break;
        }
    }
    g.history = hist.items;
    g.seeds = seeds;
    // Final assignment to the final seeds.
    g.assign = try a.alloc(usize, obs.len);
    g.dist = try a.alloc(f64, obs.len);
    var sse: f64 = 0;
    @memset(sums, 0);
    @memset(wts, 0);
    g.freq = try a.alloc(f64, c);
    @memset(g.freq, 0);
    g.maxdist = try a.alloc(f64, c);
    @memset(g.maxdist, 0);
    for (obs, 0..) |o, r| {
        const nr = nearest(seeds, o.x);
        g.assign[r] = nr.k;
        g.dist[r] = @sqrt(nr.d2);
        sse += o.w * raw2(o.x, seeds[nr.k]);
        g.freq[nr.k] += o.f;
        g.maxdist[nr.k] = @max(g.maxdist[nr.k], g.dist[r]);
        for (o.x, 0..) |v, j| if (!std.math.isNan(v)) {
            sums[nr.k * p + j] += o.w * v;
            wts[nr.k * p + j] += o.w;
        };
    }
    g.final_crit = @sqrt(sse / sw);
    g.means = try a.alloc([]f64, c);
    for (0..c) |k| {
        g.means[k] = try a.alloc(f64, p);
        for (0..p) |j| {
            if (!(wts[k * p + j] > 0)) return error.EmptyCluster;
            g.means[k][j] = sums[k * p + j] / wts[k * p + j];
        }
    }
    // Dispersion: cluster, within and total sums of squares.
    const ssk = try a.alloc(f64, c * p);
    @memset(ssk, 0);
    const tmean = try a.alloc(f64, p);
    @memset(tmean, 0);
    // Per-variable weight and frequency totals over nonmissing values
    // (verified: the OVER-ALL rows pool these per-variable divisors).
    const tw = try a.alloc(f64, p);
    @memset(tw, 0);
    const nj = try a.alloc(f64, p);
    @memset(nj, 0);
    const nkj = try a.alloc(f64, c * p);
    @memset(nkj, 0);
    for (obs, 0..) |o, r| for (o.x, 0..) |v, j| if (!std.math.isNan(v)) {
        tmean[j] += o.w * v;
        tw[j] += o.w;
        nj[j] += o.f;
        nkj[g.assign[r] * p + j] += o.f;
    };
    for (tmean, tw) |*m, w| m.* /= w;
    const sst = try a.alloc(f64, p);
    @memset(sst, 0);
    for (obs, 0..) |o, r| for (o.x, 0..) |v, j| if (!std.math.isNan(v)) {
        const k = g.assign[r];
        ssk[k * p + j] += o.w * (v - g.means[k][j]) * (v - g.means[k][j]);
        sst[j] += o.w * (v - tmean[j]) * (v - tmean[j]);
    };
    const cf: f64 = @floatFromInt(c);
    if (!(nf - cf > 0) or !(nf > 1)) return error.Degenerate;
    g.stds = try a.alloc([]f64, c);
    g.rms = try a.alloc(f64, c);
    for (0..c) |k| {
        g.stds[k] = try a.alloc(f64, p);
        var acc: f64 = 0;
        for (0..p) |j| {
            if (!(nkj[k * p + j] > 1)) return error.Degenerate;
            const v = ssk[k * p + j] / (nkj[k * p + j] - 1);
            g.stds[k][j] = @sqrt(v);
            acc += v;
        }
        g.rms[k] = @sqrt(acc / pf);
    }
    g.near = try a.alloc(usize, c);
    g.gapd = try a.alloc(f64, c);
    for (0..c) |k| {
        var bd: f64 = std.math.inf(f64);
        var bk: usize = 0;
        for (0..c) |m| if (m != k) {
            const d = dist2(g.means[k], g.means[m]);
            if (d < bd) {
                bd = d;
                bk = m;
            }
        };
        g.near[k] = bk;
        g.gapd[k] = @sqrt(bd);
    }
    g.total_std = try a.alloc(f64, p);
    g.within_std = try a.alloc(f64, p);
    g.rsq = try a.alloc(f64, p);
    var ssw_all: f64 = 0;
    var sst_all: f64 = 0;
    var dfw: f64 = 0;
    var dft: f64 = 0;
    for (0..p) |j| {
        var ssw: f64 = 0;
        for (0..c) |k| ssw += ssk[k * p + j];
        if (!(sst[j] > 0)) return error.Degenerate;
        if (!(nj[j] - cf > 0)) return error.Degenerate;
        g.total_std[j] = @sqrt(sst[j] / (nj[j] - 1));
        g.within_std[j] = @sqrt(ssw / (nj[j] - cf));
        dft += nj[j] - 1;
        dfw += nj[j] - cf;
        g.rsq[j] = 1 - ssw / sst[j];
        ssw_all += ssw;
        sst_all += sst[j];
    }
    g.over = .{ @sqrt(sst_all / dft), @sqrt(ssw_all / dfw), 1 - ssw_all / sst_all };
    const r2 = g.over[2];
    g.pseudo_f = (r2 / (cf - 1)) / ((1 - r2) / (nf - cf));
    // Sarle (1983) with uncorrelated dimensions; missing when c > n/5.
    g.ersq = std.math.nan(f64);
    g.ccc = std.math.nan(f64);
    if (cf <= nf / 5) {
        const sv = try a.dupe(f64, g.total_std);
        std.mem.sort(f64, sv, {}, std.sort.desc(f64));
        var lv: f64 = 0;
        for (sv) |x| lv += @log(x);
        var cs = @exp((lv - @log(cf)) / pf);
        var p1: usize = 0;
        for (sv) |x| if (x / cs >= 1) {
            p1 += 1;
        };
        p1 = @min(p1, c - 1);
        if (p1 == 0) return error.Degenerate;
        if (p1 < p) {
            var l1: f64 = 0;
            for (sv[0..p1]) |x| l1 += @log(x);
            cs = @exp((l1 - @log(cf)) / @as(f64, @floatFromInt(p1)));
        }
        var num: f64 = 0;
        var den: f64 = 0;
        for (sv, 0..) |x, j| {
            const u = x / cs;
            num += if (j < p1) 1 / (nf + u) else u * u / (nf + u);
            den += u * u;
        }
        const e = 1 - (num / den) * ((nf - cf) * (nf - cf) / nf) * (1 + 4 / nf);
        g.ersq = e;
        g.ccc = @log((1 - e) / (1 - r2)) * @sqrt(nf * @as(f64, @floatFromInt(p1)) / 2) / std.math.pow(f64, 0.001 + e, 1.2);
    }
    return g;
}

fn pad(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try out.appendNTimes(a, ' ', w - text.len);
    try out.appendSlice(a, text);
}
fn fixed(a: A, x: f64, d: usize) ![]const u8 {
    return switch (d) {
        2 => std.fmt.allocPrint(a, "{d:.2}", .{x}),
        3 => std.fmt.allocPrint(a, "{d:.3}", .{x}),
        4 => std.fmt.allocPrint(a, "{d:.4}", .{x}),
        5 => std.fmt.allocPrint(a, "{d:.5}", .{x}),
        6 => std.fmt.allocPrint(a, "{d:.6}", .{x}),
        7 => std.fmt.allocPrint(a, "{d:.7}", .{x}),
        8 => std.fmt.allocPrint(a, "{d:.8}", .{x}),
        9 => std.fmt.allocPrint(a, "{d:.9}", .{x}),
        10 => std.fmt.allocPrint(a, "{d:.10}", .{x}),
        1 => std.fmt.allocPrint(a, "{d:.1}", .{x}),
        else => std.fmt.allocPrint(a, "{d:.0}", .{x}),
    };
}
fn centered(a: A, out: *Out, text: []const u8, w: usize) !void {
    if (text.len < w) try out.appendNTimes(a, ' ', (w - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}

/// Cluster-by-variable matrix (seeds, means, standard deviations): one
/// decimal count per column, 10 significant digits for the column's largest
/// magnitude (verified: 77.00000000, 2.46000000, 4.941550255).
fn matrix(a: A, out: *Out, ds: *const Dataset, s: Spec, title: []const u8, m: []const []const f64) !void {
    const p = s.vars.len;
    try centered(a, out, title, 7 + 18 * p);
    try out.appendSlice(a, "Cluster");
    for (s.vars) |ci| try pad(a, out, ds.columns.items[ci].name, 18);
    try out.append(a, '\n');
    try out.appendNTimes(a, '-', 7 + 18 * p);
    try out.append(a, '\n');
    // Verified: one decimal count for the whole table, 10 minus the integer
    // digits of its largest magnitude (0.577.. -> 10, 9 -> 9, 77 -> 8).
    var mx: f64 = 0;
    for (m) |r| for (r) |v| {
        mx = @max(mx, @abs(v));
    };
    var digits: usize = 0;
    var lim: f64 = 1;
    while (mx >= lim and digits < 10) : (lim *= 10) digits += 1;
    const dec = 10 - digits;
    for (m, 0..) |r, k| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 4);
        try out.appendNTimes(a, ' ', 3);
        for (r) |v| try pad(a, out, try fixed(a, v, dec), 18);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
}

fn change(a: A, x: f64) ![]const u8 {
    return if (x == 0) "0" else fixed(a, x, 4);
}

fn render(a: A, out: *Out, ds: *const Dataset, s: Spec, g: Group, omitted: usize) !void {
    const p = s.vars.len;
    const c = g.seeds.len;
    try out.appendSlice(a, "\nThe FASTCLUS Procedure\n");
    const rep: []const u8 = switch (s.replace) {
        .full => "FULL",
        .part => "PART",
        .none => "NONE",
    };
    const fmt = @import("../format.zig");
    try out.print(a, "Replace={s}  Radius={s}  Maxclusters={d}{s} Maxiter={d}", .{ rep, try fmt.bestNum(a, s.radius orelse 0), s.maxc orelse 100, if (s.nomiss) @as([]const u8, "  Nomiss") else "", s.maxiter });
    // Verified: Converge=, the minimum seed distance and the iteration
    // history appear only for MAXITER= > 1; SHORT drops seeds and history.
    if (s.maxiter > 1) try out.print(a, "  Converge={s}", .{try fmt.bestNum(a, s.converge)});
    try out.appendSlice(a, "\n\n");
    if (!s.short) try matrix(a, out, ds, s, "Initial Seeds", g.initial);
    if (!s.short and s.maxiter > 1) try out.print(a, "Minimum Distance Between Initial Seeds = {s}\n\n", .{try padded(a, try fmt.bestNumW(a, g.min_seed_dist, 8), 8)});
    if (!s.short and s.maxiter > 1) {
        const w = 22 + 12 * c;
        try centered(a, out, "Iteration History", w + 1); // verified: rounds up
        try out.appendNTimes(a, ' ', 22);
        const head = "Relative Change in Cluster Seeds";
        const cw = 12 * c;
        // Verified: centred at column 24 + cw/2 (rounding up); narrow
        // tables split the heading over two lines.
        if (head.len < cw) {
            try out.appendNTimes(a, ' ', 2 + (cw - head.len + 1) / 2);
            try out.appendSlice(a, head);
        } else {
            try out.appendNTimes(a, ' ', 2 + (cw - 15 + 1) / 2);
            try out.appendSlice(a, "Relative Change\n");
            try out.appendNTimes(a, ' ', 24 + (cw - 16 + 1) / 2);
            try out.appendSlice(a, "in Cluster Seeds");
        }
        try out.appendSlice(a, "\nIteration    Criterion");
        for (0..c) |k| try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 12);
        try out.append(a, '\n');
        try out.appendNTimes(a, '-', w);
        try out.append(a, '\n');
        for (g.history, 0..) |row, it| {
            try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{it + 1}), 9);
            try pad(a, out, try fixed(a, row[0], 4), 13);
            for (row[1..]) |v| try pad(a, out, try change(a, v), 12);
            try out.append(a, '\n');
        }
        try out.appendSlice(a, "\n\n");
    }
    if (s.maxiter > 1) try out.appendSlice(a, if (g.converged) "Convergence criterion is satisfied.                             \n\n\n" else "WARNING: Iteration limit reached without convergence.           \n\n\n");
    try out.print(a, "Criterion Based on Final Seeds = {s}\n\n\n", .{try padded(a, try fixed(a, g.final_crit, 4), 8)});
    try centered(a, out, "Cluster Summary", 98);
    try out.appendSlice(a, "                                      Maximum Distance\n");
    try out.appendSlice(a, "                           RMS Std           from Seed     Radius     Nearest     Distance Between\n");
    try out.appendSlice(a, "Cluster     Frequency    Deviation      to Observation    Exceeded    Cluster    Cluster Centroids\n");
    try out.appendNTimes(a, '-', 98);
    try out.append(a, '\n');
    for (0..c) |k| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 4);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{g.freq[k]}), 17);
        try pad(a, out, try fixed(a, g.rms[k], 4), 13);
        try pad(a, out, try fixed(a, g.maxdist[k], 4), 20);
        try out.appendNTimes(a, ' ', 12);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{g.near[k] + 1}), 11);
        try pad(a, out, try fixed(a, g.gapd[k], 4), 21);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    if (omitted > 0) try out.print(a, "{d} Observation(s) were omitted due to missing values.\n\n\n", .{omitted});
    // Verified: the name column is the longest name (at least 8) plus 2.
    var nw: usize = 8;
    for (s.vars) |ci| nw = @max(nw, ds.columns.items[ci].name.len);
    nw += 2;
    try centered(a, out, "Statistics for Variables", nw + 56);
    try out.appendSlice(a, "Variable");
    try out.appendNTimes(a, ' ', nw - 8);
    try out.appendSlice(a, "   Total STD    Within STD      R-Square     RSQ/(1-RSQ)\n");
    try out.appendNTimes(a, '-', nw + 56);
    try out.append(a, '\n');
    for (0..p + 1) |j| {
        const nm = if (j < p) ds.columns.items[s.vars[j]].name else "OVER-ALL";
        const tv = if (j < p) g.total_std[j] else g.over[0];
        const wv = if (j < p) g.within_std[j] else g.over[1];
        const rv = if (j < p) g.rsq[j] else g.over[2];
        try out.appendSlice(a, nm);
        try out.appendNTimes(a, ' ', nw - nm.len);
        try pad(a, out, try fixed(a, tv, 5), 12);
        try pad(a, out, try fixed(a, wv, 5), 14);
        try pad(a, out, try fixed(a, rv, 6), 14);
        try pad(a, out, try fixed(a, rv / (1 - rv), 6), 16);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nPseudo F Statistic = {s}\n\n\n", .{try padded(a, try fixed(a, g.pseudo_f, 2), 8)});
    // Verified: both are missing (".") when there are more clusters than n/5.
    try out.print(a, "Approximate Expected Over-All R-Squared = {s}\n\n\n", .{if (std.math.isNan(g.ersq)) "   .     " else try padded(a, try fixed(a, g.ersq, 5), 9)});
    try out.print(a, "Cubic Clustering Criterion = {s}\n\n", .{if (std.math.isNan(g.ccc)) "    .   " else try padded(a, try fixed(a, g.ccc, 3), 8)});
    // Verified: one blank line less when the warning is not printed.
    if (p >= 2 and !s.uncorrelated) try out.appendSlice(a, "WARNING: The two values above are invalid for correlated variables.\n\n\n") else try out.appendSlice(a, "\n");
    if (!s.short) {
        try matrix(a, out, ds, s, "Cluster Means", g.means);
        try matrix(a, out, ds, s, "Cluster Standard Deviations", g.stds);
    }
}

fn padded(a: A, text: []const u8, w: usize) ![]const u8 {
    var o: Out = .empty;
    try pad(a, &o, text, w);
    return o.items;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const gap = proc.failGap;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const p = s.vars.len;
    if (s.weight != null and !s.noprint) return gap(cx.diags, l0, "PROC FASTCLUS: the Weight column of the listing with a WEIGHT statement is not verified; use NOPRINT", .{});
    if (s.maxiter == 0) return gap(cx.diags, l0, "PROC FASTCLUS: MAXITER=0 (final assignment to the initial seeds) is not verified (STAT-FASTCLUS-002)", .{});
    if (s.radius != null and s.radius.? > 0 and !s.noprint) return gap(cx.diags, l0, "PROC FASTCLUS: the Radius Exceeded column for RADIUS= > 0 is not verified", .{});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return gap(cx.diags, l0, "PROC FASTCLUS: an input data set with no observations is not verified against SAS output", .{});
    var o: ?*Dataset = null;
    if (s.out) |_| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, s.out.?);
        for (ds.columns.items) |col| _ = try d.addColumnLike(col.name, col);
        if (d.indexOf(s.cluster_name) != null or d.indexOf("DISTANCE") != null) return gap(cx.diags, l0, "PROC FASTCLUS: an input variable named like the CLUSTER or DISTANCE output variable is not verified", .{});
        _ = try d.addColumn(s.cluster_name, .num);
        d.setLabel(s.cluster_name, "Cluster");
        _ = try d.addColumn("DISTANCE", .num);
        d.setLabel("DISTANCE", "Distance to Cluster Seed");
        o = d;
    }
    for (groups) |grp| {
        var obs: std.ArrayList(Obs) = .empty;
        const slot = try a.alloc(?usize, grp.rows.len);
        // Complete observations excluded by FREQ/WEIGHT: assigned in OUT= only.
        const unused = try a.alloc(bool, grp.rows.len);
        var omitted: usize = 0;
        for (grp.rows, 0..) |row, r| {
            slot[r] = null;
            unused[r] = false;
            var nmiss: usize = 0;
            for (s.vars) |ci| {
                if (std.math.isNan(row[ci].num)) nmiss += 1;
            }
            if (nmiss == p) { // p.2901: all missing: excluded.
                omitted += 1;
                continue;
            }
            if (nmiss > 0) {
                if (s.nomiss) {
                    omitted += 1;
                    continue;
                }
            }
            const f: f64 = if (s.freq) |ci| row[ci].num else 1;
            const w: f64 = if (s.weight) |ci| row[ci].num else 1;
            // pp.2899-2900: FREQ missing or <= 0, WEIGHT not > 0: not used.
            if (!(f > 0) or !(w > 0)) {
                unused[r] = true;
                continue;
            }
            if (f != @floor(f) and !s.noprint) return gap(cx.diags, l0, "PROC FASTCLUS: the listing of a noninteger FREQ value is not verified", .{});
            const x = try a.alloc(f64, p);
            for (s.vars, 0..) |ci, j| x[j] = row[ci].num;
            slot[r] = obs.items.len;
            try obs.append(a, .{ .row = r, .x = x, .w = f * w, .f = f, .complete = nmiss == 0 });
        }
        if (obs.items.len == 0) return gap(cx.diags, l0, "PROC FASTCLUS: a BY group with no usable observations is not verified against SAS output", .{});
        const g = analyze(a, obs.items, p, s) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.OneCluster => return gap(cx.diags, l0, "PROC FASTCLUS: a single-cluster solution is not verified against SAS output", .{}),
            error.EmptyCluster => return gap(cx.diags, l0, "PROC FASTCLUS: a cluster losing all observations during iteration is not verified", .{}),
            error.Degenerate => return gap(cx.diags, l0, "PROC FASTCLUS: a degenerate solution (cluster of one, constant variable, too few observations) is not verified", .{}),
        };
        if (!g.converged and s.maxiter > 1) try cx.diags.report(.warning, l0, "Iteration limit reached without convergence.", .{});
        if (!s.noprint) {
            if (s.by_cols.len > 0) try by.appendLine(a, out, @constCast(ds), grp.rows[0], s.by_cols);
            try render(a, out, ds, s, g, omitted);
        }
        if (o) |d| for (grp.rows, 0..) |row, r| {
            const values = try a.alloc(Value, d.columns.items.len);
            @memcpy(values[0..row.len], row);
            if (slot[r]) |k| {
                values[row.len] = .{ .num = @floatFromInt(g.assign[k] + 1) };
                values[row.len + 1] = .{ .num = g.dist[k] };
            } else if (unused[r]) {
                // Verified: a complete observation with FREQ <= 0 is still
                // assigned to the nearest final seed.
                const x = try a.alloc(f64, p);
                for (s.vars, 0..) |ci, j| x[j] = row[ci].num;
                const nr = nearest(g.seeds, x);
                values[row.len] = .{ .num = @floatFromInt(nr.k + 1) };
                values[row.len + 1] = .{ .num = @sqrt(nr.d2) };
            } else {
                // Verified: all-missing (and NOMISS-excluded) rows get missing
                // CLUSTER and DISTANCE.
                values[row.len] = Value.missing;
                values[row.len + 1] = Value.missing;
            }
            try d.appendRow(values);
        };
    }
    if (o) |d| {
        try cx.lib.put(s.out.?, d);
        const upper = try std.ascii.allocUpperString(a, s.out.?);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, s.out.?, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, d.rows.items.len, d.columns.items.len });
    }
}

test {
    _ = @import("fastclus_tests.zig");
}
