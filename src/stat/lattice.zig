//! PROC LATTICE statements, roles and the balanced square lattice default
//! listing, SAS/STAT 15.4 Chapter 75 (PROC LATTICE statement p.5514, BY
//! pp.5514-5515, VAR p.5515, Input Data Set pp.5515-5516, Missing Values
//! p.5516, Displayed Output pp.5516-5517). `parse` records every documented
//! declaration; whatever has not been proven against a SAS reference listing
//! (partially balanced and rectangular lattices, repetitions of the basic
//! plan through Rep > 1, COVARIANCE beyond two responses, no-recovery cases)
//! is a D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const inference = @import("univ_inference.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    covariance: bool = false,
    group: usize = 0,
    block: usize = 0,
    /// Treatment, or its older name Treatmnt (p.5515).
    treatment: usize = 0,
    rep: ?usize = null,
    /// Response variables; defaulted by `parse` when VAR is omitted.
    vars: []const usize = &.{},
    var_given: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC LATTICE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC LATTICE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC LATTICE: " ++ text, args);
}

fn isDesign(name: []const u8) bool {
    for ([_][]const u8{ "group", "block", "treatment", "treatmnt", "rep" }) |d| if (eq(name, d)) return true;
    return false;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return user(cx, t[i].line, "DATA= is specified more than once", .{});
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            var name = t[i + 2].text;
            i += 3;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i + 1].text });
                i += 2;
            }
            data = name;
            // Data set options are applied by procInput below.
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
        } else if (eq(word, "covariance") or eq(word, "cov")) {
            s.covariance = true;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = if (data) |name|
        cx.lib.find(name) orelse return user(cx, lineOf(t, 0), "input data set {s} not found", .{name})
    else
        proc.lastDataset(cx.lib) orelse return user(cx, lineOf(t, 0), "there is no default input data set (_LAST_ is _NULL_)", .{});
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
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.5514).
            by_seen = true;
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            // Step boundary tokens may reach the body.
        } else if (kw(t, i, "where")) {
            // WHERE is applied by procInput.
        } else if (kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib") or kw(t, i, "freq") or kw(t, i, "weight")) {
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
    // Design variables (p.5515): Group, Block and Treatment (or Treatmnt) are
    // required and numeric; Rep is optional.
    const cols = s.ds.columns.items;
    const line0 = lineOf(t, 0);
    s.group = s.ds.indexOf("group") orelse return user(cx, line0, "the input data set must contain the numeric design variable Group", .{});
    s.block = s.ds.indexOf("block") orelse return user(cx, line0, "the input data set must contain the numeric design variable Block", .{});
    const tr = s.ds.indexOf("treatment");
    const tm = s.ds.indexOf("treatmnt");
    if (tr != null and tm != null) return gap(cx, line0, "a data set containing both Treatment and Treatmnt is not verified", .{});
    s.treatment = tr orelse tm orelse return user(cx, line0, "the input data set must contain the numeric design variable Treatment (or Treatmnt)", .{});
    s.rep = s.ds.indexOf("rep");
    for ([_]?usize{ s.group, s.block, s.treatment, s.rep }) |maybe| if (maybe) |c| {
        if (cols[c].type != .num) return user(cx, line0, "design variable {s} must be numeric", .{cols[c].name});
    };
    if (s.var_given) {
        for (s.vars) |v| {
            if (cols[v].type != .num) return user(cx, var_line, "VAR variable {s} must be numeric", .{cols[v].name});
            if (isDesign(cols[v].name)) return gap(cx, var_line, "design variable {s} as a response variable is not verified", .{cols[v].name});
        }
    } else {
        // No VAR statement: every numeric variable except Group, Block,
        // Treatment and Rep (p.5515).
        var vs: std.ArrayList(usize) = .empty;
        for (cols, 0..) |c, k| {
            if (c.type != .num or isDesign(c.name)) continue;
            // BY variables are not responses (SAS 15.4 reference run).
            if (std.mem.indexOfScalar(usize, s.by_cols, k) != null) continue;
            try vs.append(a, k);
        }
        if (vs.items.len == 0) return user(cx, line0, "there are no numeric response variables", .{});
        s.vars = vs.items;
    }
    return s;
}

/// Execution boundary: only what the SAS reference listings prove.
fn boundary(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    if (s.covariance and s.vars.len > 2) return gap(cx, 0, "the COVARIANCE option with more than two response variables is not verified", .{});
    const cols = s.ds.columns.items;
    for (s.vars) |v| if (cols[v].name.len > 8) return gap(cx, 0, "listing layout for response names longer than 8 characters ({s}) is not verified", .{cols[v].name});
}

/// A balanced square lattice: k*k treatments in k+1 orthogonal groups of k
/// blocks with k units, each treatment pair sharing exactly one block.
pub const Design = struct {
    k: usize,
    /// Per observation, zero-based group, block-within-group and treatment.
    group: []const usize,
    block: []const usize,
    treatment: []const usize,
};

pub const DesignError = error{ MissingDesignValue, InvalidDesignValue, NotBalancedSquare, OutOfMemory };

fn index(v: Value) DesignError!usize {
    const x = v.num;
    if (std.math.isNan(x)) return error.MissingDesignValue;
    if (x < 1 or x != @floor(x) or x > 1e6) return error.InvalidDesignValue;
    return @intFromFloat(x - 1);
}

/// Classify the design; values must be 1, 2, ... (p.5515).
pub fn design(a: A, g: []const Value, b: []const Value, tr: []const Value) DesignError!Design {
    const n = g.len;
    const gi = try a.alloc(usize, n);
    const bi = try a.alloc(usize, n);
    const ti = try a.alloc(usize, n);
    var ng: usize = 0;
    var nb: usize = 0;
    var nt: usize = 0;
    for (0..n) |r| {
        gi[r] = try index(g[r]);
        bi[r] = try index(b[r]);
        ti[r] = try index(tr[r]);
        ng = @max(ng, gi[r] + 1);
        nb = @max(nb, bi[r] + 1);
        nt = @max(nt, ti[r] + 1);
    }
    const k = std.math.sqrt(nt);
    if (k < 2 or k * k != nt or nb != k or ng != k + 1 or n != ng * nt) return error.NotBalancedSquare;
    // Each treatment once per group; each block k units.
    const seen = try a.alloc(bool, ng * nt);
    @memset(seen, false);
    const size = try a.alloc(usize, ng * nb);
    @memset(size, 0);
    for (0..n) |r| {
        if (seen[gi[r] * nt + ti[r]]) return error.NotBalancedSquare;
        seen[gi[r] * nt + ti[r]] = true;
        size[gi[r] * nb + bi[r]] += 1;
    }
    for (size) |c| if (c != k) return error.NotBalancedSquare;
    // Every pair of treatments together in exactly one block.
    const pair = try a.alloc(u8, nt * nt);
    @memset(pair, 0);
    for (0..n) |r| for (0..n) |q| {
        if (ti[r] < ti[q] and gi[r] == gi[q] and bi[r] == bi[q]) {
            pair[ti[r] * nt + ti[q]] += 1;
            if (pair[ti[r] * nt + ti[q]] > 1) return error.NotBalancedSquare;
        }
    };
    return .{ .k = k, .group = gi, .block = bi, .treatment = ti };
}

pub const Result = struct {
    k: usize,
    df: [7]usize, // reps, blocks(adj), component B, treatments, intra, rcbd, total
    ss: [7]f64,
    ms: [7]f64,
    var_same: f64,
    lsd01: f64,
    lsd05: f64,
    efficiency: f64,
    means: []const f64,
    adjusted: bool,
};

/// Balanced lattice closed form (Cochran and Cox 1957, sec. 10.3): with
/// r = k+1 replicates, C_b = sum of treatment totals in block b - r B_b,
/// mu = (Eb - Ee) / (k^2 Eb),
/// effective error Ee(1 + k mu), adjusted totals T + mu sum_{b>t} C_b.
pub fn analyze(a: A, d: Design, y: []const f64) !Result {
    const k = d.k;
    const kf: f64 = @floatFromInt(k);
    const r = k + 1;
    const rf: f64 = @floatFromInt(r);
    const nt = k * k;
    const n = y.len;
    const nf: f64 = @floatFromInt(n);
    var total: f64 = 0;
    const rep = try a.alloc(f64, r);
    const blk = try a.alloc(f64, r * k);
    const trt = try a.alloc(f64, nt);
    @memset(rep, 0);
    @memset(blk, 0);
    @memset(trt, 0);
    for (y, 0..) |v, i| {
        total += v;
        rep[d.group[i]] += v;
        blk[d.group[i] * k + d.block[i]] += v;
        trt[d.treatment[i]] += v;
    }
    const cf = total * total / nf;
    // Corrected sums of squares around the mean avoid cancellation.
    const mean = total / nf;
    var ss_total: f64 = 0;
    for (y) |v| ss_total += (v - mean) * (v - mean);
    var ss_rep: f64 = 0;
    for (rep) |x| ss_rep += x * x;
    ss_rep = ss_rep / (kf * kf) - cf;
    var ss_trt: f64 = 0;
    for (trt) |x| ss_trt += x * x;
    ss_trt = ss_trt / rf - cf;
    const c = try a.alloc(f64, r * k);
    for (c, blk) |*x, b| x.* = -rf * b;
    for (0..n) |i| c[d.group[i] * k + d.block[i]] += trt[d.treatment[i]];
    // Blocks within replications adjusted for treatments (intrablock
    // analysis of a resolvable BIBD with lambda = 1): SS(blocks | reps) +
    // SS(treatments adj) - SS(treatments unadj), with Q_t = T_t - (sum of
    // the totals of the blocks containing t) / k and SS(treatments adj) =
    // k sum Q_t^2 / (lambda k^2).
    var ss_bu: f64 = 0;
    for (blk) |x| ss_bu += x * x;
    var rep_sq: f64 = 0;
    for (rep) |x| rep_sq += x * x;
    ss_bu = ss_bu / kf - rep_sq / (kf * kf);
    const q = try a.alloc(f64, nt);
    @memcpy(q, trt);
    for (0..n) |i| q[d.treatment[i]] -= blk[d.group[i] * k + d.block[i]] / kf;
    var ss_ta: f64 = 0;
    for (q) |x| ss_ta += x * x;
    ss_ta /= kf;
    const ss_blk = ss_bu + ss_ta - ss_trt;
    const ss_intra = ss_total - ss_rep - ss_trt - ss_blk;
    var res: Result = undefined;
    res.k = k;
    res.df = .{ k, nt - 1, nt - 1, nt - 1, (k - 1) * (nt - 1), (k - 1) * (nt - 1) + nt - 1, n - 1 };
    res.ss = .{ ss_rep, ss_blk, ss_blk, ss_trt, ss_intra, ss_blk + ss_intra, ss_total };
    for (&res.ms, res.ss, res.df) |*m, s, df| m.* = s / @as(f64, @floatFromInt(df));
    const eb = res.ms[1];
    const ee = res.ms[4];
    const mu = if (eb > ee) (eb - ee) / (kf * kf * eb) else 0;
    const eff_err = ee * (1 + kf * mu);
    res.var_same = 2 * eff_err / rf;
    const df_e: f64 = @floatFromInt(res.df[4]);
    res.lsd01 = inference.tQuantile(0.995, df_e) * @sqrt(res.var_same);
    res.lsd05 = inference.tQuantile(0.975, df_e) * @sqrt(res.var_same);
    res.efficiency = 100 * res.ms[5] / eff_err;
    // Means are adjusted for blocks when the relative precision exceeds 105%
    // (p.5517).
    res.adjusted = res.efficiency > 105;
    const w = try a.alloc(f64, nt);
    @memset(w, 0);
    for (0..n) |i| w[d.treatment[i]] += c[d.group[i] * k + d.block[i]];
    const means = try a.alloc(f64, nt);
    for (means, trt, w) |*m, x, wt| m.* = (if (res.adjusted) x + mu * wt else x) / rf;
    res.means = means;
    return res;
}

/// Decimal places of the reference listings' numeric columns: four
/// significant digits below 1 (0.07739, 0.02580, 0.1776), four decimals for
/// one or two integer digits (1.4206, 62.7300), two for three or four
/// (212.18, 1491.78). ponytail: other magnitudes are not verified and gap.
fn places(x: f64) ?usize {
    if (!(x > 0) or x >= 10000) return null;
    if (x >= 100) return 2;
    if (x >= 1) return 4;
    if (x < 0.0001) return null;
    const lead: f64 = -@floor(std.math.log10(x)); // 1 for 0.1..1
    return 3 + @as(usize, @intFromFloat(lead));
}

fn num(a: A, x: f64) ![]const u8 {
    const p = places(x) orelse return error.UnverifiedValue;
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, p });
}

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

const sources = [_][]const u8{
    "Replications",
    "Blocks within Replications (Adj.)",
    "   Component B",
    "Treatments (Unadj.)",
    "Intra Block Error",
    "Randomized Complete Block Error",
    "Total",
};

pub fn render(a: A, out: *Out, dep: []const u8, r: Result) !void {
    try centered(a, out, try std.fmt.allocPrint(a, "Analysis of Variance for {s}", .{dep}), 67);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "                                                 Sum of        Mean\n");
    try out.appendSlice(a, "Source                                   DF     Squares      Square\n\n");
    for (sources, r.df, r.ss, r.ms) |name, df, ss, ms| {
        try pad(a, out, name, 37, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{df}), 6, false);
        try pad(a, out, try num(a, ss), 12, false);
        try pad(a, out, try num(a, ms), 12, false);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try centered(a, out, try std.fmt.allocPrint(a, "Additional Statistics for {s}", .{dep}), 49);
    try out.append(a, '\n');
    const labels = [_][]const u8{ "Variance of Means in Same Block", "LSD at .01 Level", "LSD at .05 Level", "Efficiency Relative to RCBD" };
    const values = [_]f64{ r.var_same, r.lsd01, r.lsd05, r.efficiency };
    for (labels, values) |l, v| {
        try pad(a, out, l, 37, true);
        try pad(a, out, try num(a, v), 12, false);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    // The 21-wide table title wraps after "Treatment"; centering as in the
    // reference listing (one extra column on the right half).
    try centered(a, out, "Adjusted Treatment", 22);
    try centered(a, out, try std.fmt.allocPrint(a, "Means for {s}", .{dep}), 22);
    try out.appendSlice(a, " \nTreatment        Mean\n\n");
    for (r.means, 1..) |m, t| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{t}), 9, false);
        try pad(a, out, try num(a, m), 12, false);
        try out.append(a, '\n');
    }
}

/// Upper-case name of the first design variable with a missing value.
fn missingDesign(s: Spec, rows: []const []const Value) []const u8 {
    for ([_]struct { c: usize, n: []const u8 }{ .{ .c = s.group, .n = "GROUP" }, .{ .c = s.block, .n = "BLOCK" }, .{ .c = s.treatment, .n = "TREATMENT" } }) |d| {
        for (rows) |r| if (missing(r[d.c])) return d.n;
    }
    return "GROUP";
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

/// One BY group: validate the design, drop response variables with missing
/// values (p.5516) and compute each remaining analysis.
const Group = struct { results: []const ?Result, products: ?[7]f64 = null };

/// Sums of products by polarization of the quadratic forms:
/// SP = (SS(x+y) - SS(x) - SS(y)) / 2 for every source.
pub fn products(a: A, d: Design, x: []const f64, y: []const f64, rx: Result, ry: Result) ![7]f64 {
    const z = try a.alloc(f64, x.len);
    for (z, x, y) |*v, p, q| v.* = p + q;
    const rz = try analyze(a, d, z);
    var sp: [7]f64 = undefined;
    for (&sp, rz.ss, rx.ss, ry.ss) |*o, sz, sx, sy| o.* = (sz - sx - sy) / 2;
    return sp;
}

fn group(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Group {
    const a = cx.arena;
    if (rows.len == 0) return user(cx, 0, "the input data set has no observations", .{});
    // Rep (p.5515): a constant Rep of 1 is the basic plan itself (SAS 15.4
    // reference run lists it exactly as without Rep).
    if (s.rep) |c| for (rows) |row| {
        const x = row[c].num;
        if (std.math.isNan(x)) return cx.diags.fail(error.ParseError, 0, "Missing value(s) encountered for REP variable.", .{});
        if (x < 1 or x != @floor(x)) return user(cx, 0, "values of Rep must be 1, 2, ..., p", .{});
        if (x != 1) return gap(cx, 0, "repetitions of the basic plan (Rep values above 1, Component A) are not implemented", .{});
    };
    const g = try a.alloc(Value, rows.len);
    const b = try a.alloc(Value, rows.len);
    const tr = try a.alloc(Value, rows.len);
    for (rows, g, b, tr) |row, *x, *y, *z| {
        x.* = row[s.group];
        y.* = row[s.block];
        z.* = row[s.treatment];
    }
    const d = design(a, g, b, tr) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // "If a value of Group, Block, Treatment, or Rep is missing, the
        // analysis is not performed and an appropriate error message is
        // displayed" (p.5516).
        error.MissingDesignValue => return cx.diags.fail(error.ParseError, 0, "Missing value(s) encountered for {s} variable.", .{missingDesign(s, rows)}),
        error.InvalidDesignValue => return user(cx, 0, "values of Group, Block and Treatment must be 1, 2, ..., n", .{}),
        error.NotBalancedSquare => return gap(cx, 0, "only balanced square lattices are implemented; partially balanced, rectangular and other designs are not (STAT-LATTICE-002)", .{}),
    };
    const results = try a.alloc(?Result, s.vars.len);
    const ys = try a.alloc([]f64, s.vars.len);
    const cols = s.ds.columns.items;
    for (s.vars, results, ys) |v, *res, *yv| {
        const y = try a.alloc(f64, rows.len);
        yv.* = y;
        var drop = false;
        for (rows, y) |row, *x| {
            if (missing(row[v])) drop = true else x.* = row[v].num;
        }
        if (drop) {
            // A response with a missing value is dropped from the analysis
            // (p.5516; message text of the SAS 15.4 reference run).
            try cx.diags.warnStatus(0, "One (or more) missing values have been encountered for the response variable {s}. This variable will be dropped from the analysis.", .{cols[v].name});
            res.* = null;
            continue;
        }
        try cx.diags.note(0, "The design specified is a balanced square lattice. With this design only one variance term, Variance of Means in Same Block, is appropriate.", .{});
        const r = try analyze(a, d, y);
        if (!(r.ms[1] > r.ms[4])) return gap(cx, 0, "a lattice whose adjusted block mean square does not exceed the intra-block error is not verified", .{});
        if (!r.adjusted) return gap(cx, 0, "unadjusted treatment means (efficiency at most 105%) are not verified", .{});
        for (r.ss ++ r.ms) |x| if (places(x) == null) return gap(cx, 0, "listing format for value {d} is not verified", .{x});
        for ([_]f64{ r.var_same, r.lsd01, r.lsd05, r.efficiency }) |x| if (places(x) == null) return gap(cx, 0, "listing format for value {d} is not verified", .{x});
        for (r.means) |x| if (places(x) == null) return gap(cx, 0, "listing format for adjusted mean {d} is not verified", .{x});
        res.* = r;
    }
    if (!s.covariance or s.vars.len < 2) return .{ .results = results };
    if (results[0] == null or results[1] == null) return gap(cx, 0, "the COVARIANCE option with a dropped response variable is not verified", .{});
    const sp = try products(a, d, ys[0], ys[1], results[0].?, results[1].?);
    for (sp, results[0].?.df) |x, df| if (places(x) == null or places(x / @as(f64, @floatFromInt(df))) == null)
        return gap(cx, 0, "listing format for sum of products {d} is not verified", .{x});
    return .{ .results = results, .products = sp };
}

/// The COVARIANCE table: sums of products and mean products per source,
/// after the first response's listing (SAS 15.4 reference run).
pub fn renderProducts(a: A, out: *Out, x: []const u8, y: []const u8, df: [7]usize, sp: [7]f64) !void {
    try centered(a, out, try std.fmt.allocPrint(a, "Analysis of Covariance for {s} and {s}", .{ x, y }), 67);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "                                                 Sum of        Mean\n");
    try out.appendSlice(a, "Source                                   DF    Products     Product\n\n");
    for (sources, df, sp) |name, d, v| {
        try pad(a, out, name, 37, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{d}), 6, false);
        try pad(a, out, try num(a, v), 12, false);
        try pad(a, out, try num(a, v / @as(f64, @floatFromInt(d))), 12, false);
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    try boundary(cx, s);
    // SAS 15.4 stops with an internal exception on an empty data set.
    if (s.ds.rows.items.len == 0) return user(cx, 0, "the input data set has no observations", .{});
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    for (slices, groups) |slice, *g| g.* = try group(cx, s, slice.rows);
    const cols = s.ds.columns.items;
    for (slices, groups) |slice, grp| {
        const g = grp.results;
        // A BY group whose responses were all dropped prints nothing
        // (SAS 15.4 reference run: warnings only).
        var any = false;
        for (g) |r| if (r != null) {
            any = true;
        };
        if (!any) continue;
        if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
        if (s.by_cols.len > 0) {
            var line: Out = .empty;
            try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
            }
        }
        try out.appendSlice(a, "\nThe Lattice Procedure\n\n");
        var first = true;
        for (s.vars, g, 0..) |v, maybe, vi| if (maybe) |r| {
            // Later responses follow after two blank lines, without a new
            // procedure title (SAS 15.4 reference run).
            if (!first) try out.appendSlice(a, "\n\n");
            first = false;
            render(a, out, cols[v].name, r) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnverifiedValue => unreachable, // screened in `group`
            };
            if (vi == 0) if (grp.products) |sp| {
                try out.appendSlice(a, "\n\n");
                renderProducts(a, out, cols[s.vars[0]].name, cols[s.vars[1]].name, r.df, sp) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.UnverifiedValue => unreachable, // screened in `group`
                };
            };
        };
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    }
}

test {
    _ = @import("lattice_tests.zig");
}
