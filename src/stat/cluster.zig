//! PROC CLUSTER (SAS/STAT 15.4 ch.40): PROC statement options, BY / COPY /
//! FREQ / ID / RMSSTD / VAR roles, missing-value rules and the default
//! cluster-history listing for TYPE=DISTANCE input (STAT-CLUSTER-001).
//!
//! Implemented methods: AVERAGE, CENTROID, SINGLE and WARD on a TYPE=DISTANCE
//! data set (the chapter's flying-mileage example), with PSEUDO, NOTIE,
//! NOPRINT and PLOTS=NONE. Rules verified against SAS listings:
//! - AVERAGE, CENTROID and WARD square the input distances; SINGLE does not.
//! - AVERAGE/CENTROID distances are normalized by the root-mean-square
//!   distance between observations, SINGLE by the mean distance.
//! - The two clusters joined are listed by their smallest observation number;
//!   a merged cluster at level G is named CLG.
//! - Pseudo F / t-squared come from the within-cluster sums of squares
//!   W_K = sum_{i<j in K} f_i f_j d_ij^2 / N_K (p.2499); WARD's W and B follow
//!   its Lance-Williams recurrence (see agglomerate).
//! - FREQ / _FREQ_ (truncated, >= 1) weight the clusters; the normalizers
//!   average over all N(N-1)/2 pairs (verified with a SAS 9.4 run of invented
//!   data, tests/corpus/stat_cluster001_freq.sas). Without ID: OB1, OB2, ...
//! - Ties (p.2509): the tied pair with the minimum larger identification
//!   number, then the minimum smaller one, is merged; the level is flagged T and
//!   one WARNING counts the tied levels.
//! Everything else the cited pages define is a loud D-009 gap: coordinate
//! input (the eigenvalue/RMS-STD listing of STAT-CLUSTER-002), the other
//! methods and RMSSTD (STAT-CLUSTER-003), OUTTREE= (STAT-CLUSTER-006), the
//! dendrogram (STAT-CLUSTER-008) and the display options of STAT-CLUSTER-007.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { average, centroid, single, ward };

pub const Spec = struct {
    input: proc.ProcInput,
    method: Method = .average,
    distance: bool = false,
    pseudo: bool = false,
    notie: bool = false,
    noprint: bool = false,
    plots_none: bool = false,
    vars: []const usize = &.{},
    id: ?usize = null,
    copy: []const usize = &.{},
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
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC CLUSTER: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, l: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, l, "PROC CLUSTER: " ++ fmt, args);
}

/// METHOD= names and their documented abbreviations (p.2487).
fn parseMethod(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!Method {
    const l = line(t, i);
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const w = t[i].text;
    const done = [_]struct { []const u8, []const u8, Method }{ .{ "average", "ave", .average }, .{ "centroid", "cen", .centroid }, .{ "single", "sin", .single }, .{ "ward", "war", .ward } };
    for (done) |m| if (eq(w, m[0]) or eq(w, m[1])) return m[2];
    const later = [_][2][]const u8{ .{ "complete", "com" }, .{ "density", "den" }, .{ "eml", "eml" }, .{ "flexible", "fle" }, .{ "mcquitty", "mcq" }, .{ "median", "med" }, .{ "twostage", "two" } };
    for (later) |m| if (eq(w, m[0]) or eq(w, m[1])) return gap(cx, l, "METHOD={s} is not implemented (STAT-CLUSTER-003)", .{w});
    return cx.diags.fail(error.ParseError, l, "PROC CLUSTER: METHOD={s} is not a valid clustering method", .{w});
}

fn oneVar(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, numeric: bool) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CLUSTER: the {s} statement takes exactly one variable", .{role});
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC CLUSTER: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC CLUSTER: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var name_at: ?usize = null; // first token of DATA=name
    var name_end: usize = 0; // after name and its option list
    var method_seen = false;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const l = t[i].line;
        const option = try std.ascii.allocLowerString(a, t[i].text);
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx, l, "repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            name = t[first].text;
            name_at = first;
            var j = first + 1;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[first].text, t[j + 1].text });
                j += 2;
            }
            if (at(t, j, .lparen)) {
                const close = proc.skipParen(t, j);
                var k = j + 1;
                while (k + 2 < close) : (k += 1) if (kw(t, k, "type") and at(t, k + 1, .eq)) {
                    if (kw(t, k + 2, "distance")) s.distance = true else if (!kw(t, k + 2, "data"))
                        return gap(cx, l, "an input data set of TYPE={s} is not implemented", .{t[k + 2].text});
                };
                j = close;
            }
            name_end = j;
            i = j;
        } else if (eq(option, "method") and valued) {
            s.method = try parseMethod(cx, t, i + 2);
            method_seen = true;
            i += 3;
        } else if (eq(option, "outtree") and valued) {
            if (!kw(t, i + 2, "_null_")) return gap(cx, l, "the OUTTREE= data set is not implemented (STAT-CLUSTER-006); use OUTTREE=_NULL_", .{});
            i += 3;
        } else if (eq(option, "plots")) {
            var j = i + 1;
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            if (!at(t, j, .eq) or !kw(t, j + 1, "none") or j != i + 1) return gap(cx, l, "PLOTS= other than PLOTS=NONE is not implemented (STAT-CLUSTER-008)", .{});
            s.plots_none = true;
            i = j + 2;
        } else if (valued and (eq(option, "beta") or eq(option, "mode") or eq(option, "penalty") or eq(option, "trim") or eq(option, "k") or eq(option, "r"))) {
            return gap(cx, l, "the {s}= option is not implemented (STAT-CLUSTER-003)", .{t[i].text});
        } else if (valued and eq(option, "print")) {
            return gap(cx, l, "the PRINT= option is not implemented (STAT-CLUSTER-007)", .{});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "pseudo")) {
            s.pseudo = true;
            i += 1;
        } else if (eq(option, "notie")) {
            s.notie = true;
            i += 1;
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "noeigen")) {
            i += 1; // only suppresses the eigenvalues of coordinate data
        } else if (eq(option, "nosquare") or eq(option, "nonorm") or eq(option, "standard") or eq(option, "std") or eq(option, "hybrid")) {
            return gap(cx, l, "the {s} option is not implemented (STAT-CLUSTER-003)", .{t[i].text});
        } else if (eq(option, "ccc") or eq(option, "rsquare") or eq(option, "rsq") or eq(option, "rmsstd") or eq(option, "simple") or eq(option, "noid")) {
            return gap(cx, l, "the {s} option is not implemented (STAT-CLUSTER-007)", .{t[i].text});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.2486: METHOD= is required.
    if (!method_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CLUSTER: the METHOD= option must be specified", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC CLUSTER: input data set not found", .{});
    // Fold DATA=lib.member to one token and drop TYPE= (a member attribute,
    // handled above) so the shared selection code sees only selection options.
    var folded: std.ArrayList(lex.Token) = .empty;
    if (name_at) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        var k = q + 1;
        if (at(t, k, .dot)) k += 2;
        while (k < name_end) : (k += 1) {
            if (kw(t, k, "type") and at(t, k + 1, .eq)) {
                k += 2;
                continue;
            }
            try folded.append(a, t[k]);
        }
        // An option list emptied by dropping TYPE= becomes no list at all.
        const n = folded.items.len;
        if (n >= 2 and folded.items[n - 2].tag == .lparen and folded.items[n - 1].tag == .rparen) folded.items.len -= 2;
        try folded.appendSlice(a, t[name_end..]);
    }
    s.input = try proc.procInputObs(a, raw, if (name_at != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var copy: std.ArrayList(usize) = .empty;
    var var_seen = false;
    var rmsstd = false;
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
        const l = t[i].line;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.2496: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx, l, "more than one VAR statement is not verified", .{});
            var_seen = true;
            if (end == i + 1) return cx.diags.fail(error.ParseError, l, "PROC CLUSTER: the VAR statement needs at least one variable", .{});
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const vl = body[j].line;
                for (try lists.next(a, ds, body, &j, cx.diags)) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, vl, "PROC CLUSTER: variable {s} in the VAR statement is not on the input data set", .{n});
                    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, vl, "PROC CLUSTER: variable {s} in the VAR statement must be numeric", .{n});
                    if (has(vars.items, ci)) return gap(cx, vl, "variable {s} listed more than once in the VAR statement is not verified", .{n});
                    try vars.append(a, ci);
                }
            }
        } else if (eq(word, "id")) {
            if (s.id != null) return gap(cx, l, "more than one ID statement is not verified", .{});
            s.id = try oneVar(cx, ds, t, i, end, "ID", false);
        } else if (eq(word, "copy")) {
            if (end == i + 1) return cx.diags.fail(error.ParseError, l, "PROC CLUSTER: the COPY statement needs at least one variable", .{});
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const cl = body[j].line;
                for (try lists.next(a, ds, body, &j, cx.diags)) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, cl, "PROC CLUSTER: variable {s} in the COPY statement is not on the input data set", .{n});
                    if (!has(copy.items, ci)) try copy.append(a, ci);
                }
            }
        } else if (eq(word, "freq") or eq(word, "frequency")) {
            if (s.freq != null) return gap(cx, l, "more than one FREQ statement is not verified", .{});
            s.freq = try oneVar(cx, ds, t, i, end, "FREQ", true);
        } else if (eq(word, "rmsstd")) {
            _ = try oneVar(cx, ds, t, i, end, "RMSSTD", true);
            rmsstd = true;
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (eq(word, "format") or eq(word, "label") or eq(word, "attrib")) {
            return gap(cx, l, "a {s} statement inside the step is not implemented", .{word});
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // p.2497: the RMSSTD statement requires a FREQ statement.
    if (rmsstd and s.freq == null) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CLUSTER: the RMSSTD statement requires a FREQ statement", .{});
    if (rmsstd or ds.indexOf("_rmsstd_") != null) return gap(cx, line(t, 0), "RMSSTD values (RMSSTD statement or _RMSSTD_ variable) are not implemented (STAT-CLUSTER-003)", .{});
    // p.2497: without a FREQ statement a variable named _FREQ_ supplies frequencies.
    if (s.freq == null) if (ds.indexOf("_freq_")) |ci| {
        if (ds.columns.items[ci].type == .num) s.freq = ci;
    };
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.copy = copy.items;
    if (s.freq) |f| if (has(s.by_cols, f)) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CLUSTER: the FREQ variable cannot also be a BY variable", .{});
    // p.2498: without VAR, every numeric variable not listed in another statement.
    if (!var_seen) {
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(s.by_cols, ci) or has(s.copy, ci) or s.id == ci or s.freq == ci) continue;
            try vars.append(a, ci);
        }
        if (vars.items.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC CLUSTER: there are no numeric variables to analyze", .{});
    }
    s.vars = vars.items;
    return s;
}

/// One BY group's history.
pub const Merge = struct { ncl: usize, left: []const u8, right: []const u8, freq: f64, f: f64, t2: f64, dist: f64, sprsq: f64, rsq: f64, tie: bool };
pub const History = struct { norm: f64, merges: []const Merge, ties: usize };

/// Agglomerate one group. `d` is the n x n symmetric distance matrix (row
/// major, unsquared), `w` the frequencies, `labels` the singleton names.
pub fn agglomerate(a: A, method: Method, d: []const f64, w: []const f64, labels: []const []const u8) error{OutOfMemory}!History {
    const n = w.len;
    // Cross sums C_KL = sum_{i in K, j in L} f_i f_j d_ij^2; S_K the within sums.
    const c = try a.alloc(f64, n * n);
    const mind = try a.dupe(f64, d); // single linkage
    // Verified (SAS 9.4, invented FREQ data): WARD starts every pair at
    // d_ij^2 / 2 whatever the frequencies, updates by the Lance-Williams
    // formula with the cluster frequencies, and W_M = W_K + W_L + B_KL.
    const ward = try a.alloc(f64, n * n);
    for (ward, d) |*x, y| x.* = y * y / 2;
    const ward_w = try a.alloc(f64, n);
    @memset(ward_w, 0);
    var pairs: f64 = 0;
    var sum_d: f64 = 0;
    var sum_d2: f64 = 0;
    var ntot: f64 = 0;
    for (0..n) |i| {
        ntot += w[i];
        for (0..n) |j| {
            c[i * n + j] = w[i] * w[j] * d[i * n + j] * d[i * n + j];
            if (j < i) {
                pairs += w[i] * w[j];
                sum_d += w[i] * w[j] * d[i * n + j];
                sum_d2 += w[i] * w[j] * d[i * n + j] * d[i * n + j];
            }
        }
    }
    // Verified (SAS 9.4, invented FREQ data): the normalizers average over all
    // N(N-1)/2 pairs of the N = sum f_i observations, so the copies of one
    // observation count as zero-distance pairs.
    pairs = ntot * (ntot - 1) / 2;
    const rms = @sqrt(sum_d2 / pairs);
    const mean = sum_d / pairs;
    const total = sum_d2 / ntot; // T
    const s_within = try a.alloc(f64, n);
    @memset(s_within, 0);
    const size = try a.dupe(f64, w);
    const ident = try a.alloc(usize, n); // smallest observation number
    for (ident, 0..) |*x, k| x.* = k;
    const name = try a.dupe([]const u8, labels);
    const alive = try a.alloc(bool, n);
    @memset(alive, true);
    var pg: f64 = 0; // P_G
    var merges: std.ArrayList(Merge) = .empty;
    var ties: usize = 0;
    var g = n;
    const crit = struct {
        fn f(m: Method, cc: []const f64, sw: []const f64, sz: []const f64, md: []const f64, nn: usize, k: usize, l: usize) f64 {
            const nk = sz[k];
            const nl = sz[l];
            const ckl = cc[k * nn + l];
            return switch (m) {
                .average => ckl / (nk * nl),
                .centroid => ckl / (nk * nl) - sw[k] / (nk * nk) - sw[l] / (nl * nl),
                .ward => md[k * nn + l],
                .single => md[k * nn + l],
            };
        }
    }.f;
    while (g > 1) {
        var best: ?[2]usize = null;
        var best_v: f64 = 0;
        var tie = false;
        for (0..n) |k| {
            if (!alive[k]) continue;
            for (k + 1..n) |l| {
                if (!alive[l]) continue;
                const v = crit(method, c, s_within, size, if (method == .ward) ward else mind, n, k, l);
                const lo = @min(ident[k], ident[l]);
                const hi = @max(ident[k], ident[l]);
                if (best) |b| {
                    const tol = 1e-12 * @max(@abs(v), @abs(best_v));
                    if (v < best_v - tol) {
                        best = .{ k, l };
                        best_v = v;
                        tie = false;
                    } else if (@abs(v - best_v) <= tol) {
                        tie = true;
                        const blo = @min(ident[b[0]], ident[b[1]]);
                        const bhi = @max(ident[b[0]], ident[b[1]]);
                        if (hi < bhi or (hi == bhi and lo < blo)) best = .{ k, l };
                    }
                } else {
                    best = .{ k, l };
                    best_v = v;
                }
            }
        }
        var k = best.?[0];
        var l = best.?[1];
        if (ident[l] < ident[k]) std.mem.swap(usize, &k, &l);
        if (tie) ties += 1;
        const nk = size[k];
        const nl = size[l];
        const sm = s_within[k] + s_within[l] + c[k * n + l];
        const wk = if (method == .ward) ward_w[k] else s_within[k] / nk;
        const wl = if (method == .ward) ward_w[l] else s_within[l] / nl;
        const bkl = if (method == .ward) best_v else sm / (nk + nl) - wk - wl;
        ward_w[k] = wk + wl + bkl;
        pg += bkl;
        g -= 1;
        const gf: f64 = @floatFromInt(g);
        const pseudo_f: f64 = if (g > 1 and pg > 0) ((total - pg) / (gf - 1)) / (pg / (ntot - gf)) else std.math.nan(f64);
        const dfw = nk + nl - 2;
        const t2: f64 = if (dfw > 0 and wk + wl > 0) bkl / ((wk + wl) / dfw) else std.math.nan(f64);
        const shown: f64 = switch (method) {
            .single => best_v / mean,
            .average, .centroid => @sqrt(@max(best_v, 0)) / rms,
            .ward => std.math.nan(f64),
        };
        try merges.append(a, .{ .ncl = g, .left = name[k], .right = name[l], .freq = nk + nl, .f = pseudo_f, .t2 = t2, .dist = shown, .sprsq = bkl / total, .rsq = 1 - pg / total, .tie = tie });
        // Merge l into k.
        for (0..n) |j| {
            if (!alive[j] or j == k or j == l) continue;
            c[k * n + j] += c[l * n + j];
            c[j * n + k] = c[k * n + j];
            mind[k * n + j] = @min(mind[k * n + j], mind[l * n + j]);
            mind[j * n + k] = mind[k * n + j];
            const nj = size[j];
            ward[k * n + j] = ((nj + nk) * ward[k * n + j] + (nj + nl) * ward[l * n + j] - nj * best_v) / (nj + nk + nl);
            ward[j * n + k] = ward[k * n + j];
        }
        s_within[k] = sm;
        size[k] = nk + nl;
        alive[l] = false;
        name[k] = try std.fmt.allocPrint(a, "CL{d}", .{g});
    }
    return .{ .norm = if (method == .single) mean else rms, .merges = merges.items, .ties = ties };
}

fn fixed(a: A, x: f64, comptime digits: usize) ![]const u8 {
    if (std.math.isNan(x)) {
        // Missing sits at the decimal point (verified layout).
        const s = try a.alloc(u8, digits + 1);
        @memset(s, ' ');
        s[0] = '.';
        return s;
    }
    return std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{digits}) ++ "}", .{x});
}

fn best6(a: A, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    return std.mem.trim(u8, format.apply(a, .{ .num = x }, "best6.") catch return error.OutOfMemory, " ");
}

fn pad(a: A, o: *Out, text: []const u8, width: usize, right: bool) !void {
    if (right) try o.appendNTimes(a, ' ', width -| text.len);
    try o.appendSlice(a, text);
    if (!right) try o.appendNTimes(a, ' ', width -| text.len);
}

const Col = struct { head: [3][]const u8, width: usize };

pub fn render(a: A, out: *Out, method: Method, pseudo: bool, h: History, id_width: usize) !void {
    const title = switch (method) {
        .average => "Average Linkage Cluster Analysis",
        .centroid => "Centroid Hierarchical Cluster Analysis",
        .single => "Single Linkage Cluster Analysis",
        .ward => "Ward's Minimum Variance Cluster Analysis",
    };
    try out.print(a, "\nThe CLUSTER Procedure\n{s}\n\n", .{title});
    const norm_label = if (method == .single) "Mean Distance Between Observations" else "Root-Mean-Square Distance Between Observations";
    try out.print(a, "{s}    ", .{norm_label});
    try pad(a, out, try best8(a, h.norm), 8, true);
    try out.appendSlice(a, "\n\n\n");
    // Verified: the joined-cluster columns are 12 wide for a $3 ID and for the
    // OBn labels, 15 wide for a $15 ID. ponytail: max(12, ID length).
    const w = @max(id_width, 12);
    var cols: std.ArrayList(Col) = .empty;
    try cols.append(a, .{ .head = .{ "", "", "Freq" }, .width = 9 });
    if (method == .ward) {
        try cols.append(a, .{ .head = .{ "", "Semipartial", "R-Square" }, .width = 11 });
        try cols.append(a, .{ .head = .{ "", "", "R-Square" }, .width = 8 });
    }
    if (pseudo) {
        try cols.append(a, .{ .head = .{ "", "Pseudo F", "Statistic" }, .width = 9 });
        try cols.append(a, .{ .head = .{ "", "Pseudo", "t-Squared" }, .width = 9 });
    }
    switch (method) {
        .average => try cols.append(a, .{ .head = .{ "", "Norm RMS", "Distance" }, .width = 8 }),
        .centroid => try cols.append(a, .{ .head = .{ "Norm", "Centroid", "Distance" }, .width = 8 }),
        .single => try cols.append(a, .{ .head = .{ "Norm", "Minimum", "Distance" }, .width = 8 }),
        .ward => {},
    }
    var total: usize = 8 + 4 + 2 * w + 4 + 4 + 3;
    for (cols.items) |cdef| total += 4 + cdef.width;
    try out.appendNTimes(a, ' ', (total - 15 + 1) / 2);
    try out.appendSlice(a, "Cluster History\n");
    // Header: three lines, bottom aligned; the stub reads Number / of / Clusters.
    const stub = [3][]const u8{ "Number", "of", "Clusters" };
    for (0..3) |r| {
        var ln: Out = .empty;
        try pad(a, &ln, stub[r], 8, true);
        if (r == 2) {
            const span = 2 * w + 4;
            const text = "Clusters Joined";
            const left = (span - text.len) / 2;
            try ln.appendNTimes(a, ' ', 4);
            try ln.appendNTimes(a, '-', left);
            try ln.appendSlice(a, text);
            try ln.appendNTimes(a, '-', span - text.len - left);
        } else try ln.appendNTimes(a, ' ', 4 + 2 * w + 4);
        for (cols.items) |cdef| {
            try ln.appendNTimes(a, ' ', 4);
            try pad(a, &ln, cdef.head[r], cdef.width, true);
        }
        if (r == 2) try ln.appendSlice(a, "    Tie");
        try out.appendSlice(a, std.mem.trimEnd(u8, ln.items, " "));
        try out.append(a, '\n');
    }
    try out.append(a, '\n');
    for (h.merges) |m| {
        var ln: Out = .empty;
        try pad(a, &ln, try std.fmt.allocPrint(a, "{d}", .{m.ncl}), 8, true);
        try ln.appendNTimes(a, ' ', 4);
        try pad(a, &ln, m.left, w, false);
        try ln.appendNTimes(a, ' ', 4);
        try pad(a, &ln, m.right, w, false);
        try ln.appendNTimes(a, ' ', 4);
        try pad(a, &ln, try std.fmt.allocPrint(a, "{d}", .{m.freq}), 9, true);
        if (method == .ward) {
            try ln.appendNTimes(a, ' ', 4);
            try pad(a, &ln, try fixed(a, m.sprsq, 4), 11, true);
            try ln.appendNTimes(a, ' ', 4);
            const r3 = try fixed(a, @max(m.rsq, 0), 3);
            try pad(a, &ln, if (std.mem.startsWith(u8, r3, "0.")) r3[1..] else r3, 8, true);
        }
        if (pseudo) {
            try ln.appendNTimes(a, ' ', 4);
            try pad(a, &ln, try w41(a, m.f), 9, true);
            try ln.appendNTimes(a, ' ', 4);
            try pad(a, &ln, try w41(a, m.t2), 9, true);
        }
        if (method != .ward) {
            try ln.appendNTimes(a, ' ', 4);
            try pad(a, &ln, try best6(a, m.dist), 8, true);
        }
        try ln.appendNTimes(a, ' ', 4);
        try pad(a, &ln, if (m.tie) "T" else "", 3, false);
        try out.appendSlice(a, ln.items);
        try out.append(a, '\n');
    }
}

/// Pseudo F and t-squared print with the 4.1 format (verified: 66.7, 16.0,
/// and 201 for 201.1); missing sits at the decimal point.
fn w41(a: A, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return ".  "[0..2];
    return std.mem.trim(u8, format.apply(a, .{ .num = x }, "4.1") catch return error.OutOfMemory, " ");
}

fn best8(a: A, x: f64) ![]const u8 {
    return std.mem.trim(u8, format.apply(a, .{ .num = x }, "best8.") catch return error.OutOfMemory, " ");
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    if (!s.distance) return gap(cx, l0, "coordinate input (a data set that is not TYPE=DISTANCE) is not implemented (STAT-CLUSTER-002)", .{});
    if (!s.noprint and !s.plots_none) if (cx.graphics) |g| if (g.enabled == true) return gap(cx, l0, "the default dendrogram under ODS GRAPHICS is not implemented (STAT-CLUSTER-008); use ODS GRAPHICS OFF or PLOTS=NONE", .{});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return gap(cx, l0, "an input data set without observations is not verified against SAS output", .{});
    try cx.diags.note(l0, "The input data set is a TYPE=DISTANCE data set. For such a data set, the procedure requires that the order of the rows match the order of the variables.", .{});
    const p = s.vars.len;
    var histories: std.ArrayList(History) = .empty;
    var id_width: usize = 0;
    if (s.id) |ci| {
        if (ds.columns.items[ci].type == .char) id_width = ds.columns.items[ci].len orelse 8 else return gap(cx, l0, "a numeric ID variable is not verified against SAS output", .{});
    }
    for (groups) |grp| {
        const n = grp.rows.len;
        // p.2509: distances need as many variables as rows; the lower triangle
        // may not contain missing values; the upper triangle is ignored.
        if (n != p) return cx.diags.fail(error.ParseError, l0, "PROC CLUSTER: a TYPE=DISTANCE data set needs as many rows as distance variables ({d} rows, {d} variables)", .{ n, p });
        if (n < 2) return gap(cx, l0, "a distance matrix with fewer than two observations is not verified against SAS output", .{});
        const d = try a.alloc(f64, n * n);
        const f = try a.alloc(f64, n);
        for (grp.rows, 0..) |row, i| {
            d[i * n + i] = 0;
            for (0..i) |j| {
                const x = row[s.vars[j]].num;
                if (std.math.isNan(x)) return cx.diags.fail(error.ParseError, l0, "PROC CLUSTER: missing values are not permitted in the lower triangle of a TYPE=DISTANCE data set (row {d}, variable {s})", .{ i + 1, ds.columns.items[s.vars[j]].name });
                if (x < 0) return gap(cx, l0, "a negative distance is not verified against SAS output", .{});
                d[i * n + j] = x;
                d[j * n + i] = x;
            }
            f[i] = if (s.freq) |ci| @floor(row[ci].num) else 1;
            if (!(f[i] >= 1)) return gap(cx, l0, "a FREQ value that is missing or less than 1 in a TYPE=DISTANCE data set is not verified against SAS output", .{});
        }
        const labels = try a.alloc([]const u8, n);
        for (grp.rows, 0..) |row, i| {
            labels[i] = if (s.id) |ci| std.mem.trimEnd(u8, row[ci].str, " ") else try std.fmt.allocPrint(a, "OB{d}", .{i + 1});
            id_width = @max(id_width, labels[i].len);
        }
        const h = try agglomerate(a, s.method, d, f, labels);
        id_width = @max(id_width, std.fmt.count("CL{d}", .{n}));
        try histories.append(a, h);
    }
    if (s.method != .single) try cx.diags.note(l0, "Input distances have been squared.", .{});
    if (!s.noprint) for (groups, histories.items) |grp, h| {
        if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
        if (s.by_cols.len > 0) {
            var ln: Out = .empty;
            try by.appendLine(a, &ln, ds, grp.rep.?, s.by_cols);
            if (ln.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, ln.items[1..], " "));
                if (!std.mem.endsWith(u8, ln.items, "\n")) try out.append(a, '\n');
            }
        }
        var hh = h;
        if (s.notie) {
            const ms = try a.dupe(Merge, h.merges);
            for (ms) |*m| m.tie = false;
            hh.merges = ms;
        }
        try render(a, out, s.method, s.pseudo, hh, id_width);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    };
    for (histories.items, groups) |h, grp| if (h.ties > 0 and !s.notie) {
        try cx.diags.warnStatus(l0, "Ties for minimum distance between clusters have been detected at {d} level(s) in the cluster history.", .{h.ties});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, grp.rows[0], s.by_cols);
    };
    // ponytail: SAS also writes the history to a WORK.DATAn OUTTREE= data set
    // by default (p.2493); that data set is STAT-CLUSTER-006 and is not created.
}

test {
    _ = @import("cluster_tests.zig");
}
