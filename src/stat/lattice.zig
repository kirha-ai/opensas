//! PROC LATTICE statements, roles and the balanced square lattice default
//! listing, SAS/STAT 15.4 Chapter 75 (PROC LATTICE statement p.5514, BY
//! pp.5514-5515, VAR p.5515, Input Data Set pp.5515-5516, Missing Values
//! p.5516, Displayed Output pp.5516-5517). `parse` records every documented
//! declaration; whatever has not been proven against a SAS reference listing
//! (rectangular lattices, repeated partially balanced plans, number formats
//! outside the verified magnitudes, response names longer than 11 characters)
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
            // Several VAR statements accumulate (SAS 15.4 reference run:
            // `var Weight; var W2;` analyzes both, in order).
            const again = s.var_given;
            s.var_given = true;
            if (!again) var_line = t[i].line;
            if (end == i + 1) return invalid(cx, t, end);
            var cols: std.ArrayList(usize) = .empty;
            try cols.appendSlice(a, s.vars);
            var j = i + 1;
            while (j < end) {
                const line = t[j].line;
                const names = try lists.next(a, s.ds, t[0..end], &j, cx.diags);
                for (names) |n| {
                    const c = s.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                    // A repeated variable is analyzed again, within one VAR
                    // statement or across several (SAS 15.4 reference run).
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
        } else if (kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib")) {
            // ponytail: the listing shows variable names and its own number
            // formats whatever LABEL/FORMAT/ATTRIB say (SAS 15.4 reference
            // run), so they are accepted and have no effect.
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            // Not LATTICE statements: SAS 15.4 stops the step with ERROR
            // 180-322 (reference run).
            return user(cx, t[i].line, "Statement is not valid or it is used out of proper order ({s}).", .{try std.ascii.allocUpperString(a, t[i].text)});
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
    // Both Treatment and Treatmnt present: SAS 15.4 reads Treatmnt
    // (reference run with the two differing).
    s.treatment = tm orelse tr orelse return user(cx, line0, "the input data set must contain the numeric design variable Treatment (or Treatmnt)", .{});
    s.rep = s.ds.indexOf("rep");
    for ([_]?usize{ s.group, s.block, s.treatment, s.rep }) |maybe| if (maybe) |c| {
        if (cols[c].type != .num) return user(cx, line0, "design variable {s} must be numeric", .{cols[c].name});
    };
    if (s.var_given) {
        var kept: std.ArrayList(usize) = .empty;
        var design_listed = false;
        for (s.vars) |v| {
            if (cols[v].type != .num) return user(cx, var_line, "VAR variable {s} must be numeric", .{cols[v].name});
            if (isDesign(cols[v].name)) design_listed = true else try kept.append(a, v);
        }
        if (design_listed) {
            // SAS 15.4 reference run: a NOTE, and the design variable is not
            // analyzed; with nothing left the step stops.
            try cx.diags.note(var_line, "Variables GROUP, BLOCK, TREATMENT or REP are listed on the VAR Statement. They are keywords for special variables and will not be analyzed as response variables.", .{});
            if (kept.items.len == 0) return user(cx, var_line, "No numeric response variables on VAR Statement.", .{});
            s.vars = kept.items;
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
    const cols = s.ds.columns.items;
    // "Means for <name>" fits the 22-wide wrapped title up to 11 characters
    // (SAS 15.4 reference run with an 11-character name).
    for (s.vars) |v| if (cols[v].name.len > 11) return gap(cx, 0, "listing layout for response names longer than 11 characters ({s}) is not verified", .{cols[v].name});
}

/// A balanced square lattice: k*k treatments in k+1 orthogonal groups of k
/// blocks with k units, each treatment pair sharing exactly one block; the
/// basic plan may be repeated p times through Rep (p.5515), every repetition
/// using the same blocks (Component A compares blocks that contain the same
/// treatments, p.5516).
pub const Design = struct {
    k: usize,
    /// Repetitions of the basic plan (1 without Rep or with Rep all 1).
    p: usize = 1,
    /// Replicates (groups) of the basic plan: k+1 for a balanced square
    /// lattice, 2..k for a partially balanced one (Overview p.5511).
    m: usize = 0,
    /// Simple (m = 2) or triple (m = 3) rectangular lattice: k(k+1)
    /// treatments in k+1 blocks of k per replicate (Overview p.5511).
    rect: bool = false,
    /// Per observation, zero-based group, block-within-group and treatment.
    group: []const usize,
    block: []const usize,
    treatment: []const usize,
    /// Per observation, zero-based repetition (all 0 when p = 1).
    rep: []const usize = &.{},

    fn repOf(d: Design, i: usize) usize {
        return if (d.p == 1) 0 else d.rep[i];
    }
};

pub const DesignError = error{ MissingDesignValue, InvalidDesignValue, NotBalancedSquare, RepeatedCellMissing, RepeatedCellConflict, OutOfMemory };

/// One-based group, treatment and repetition of the cell behind a
/// RepeatedCell* error.
pub const Cell = struct { group: usize = 0, treatment: usize = 0, rep: usize = 0 };

fn index(v: Value) DesignError!usize {
    const x = v.num;
    if (std.math.isNan(x)) return error.MissingDesignValue;
    if (x < 1 or x != @floor(x) or x > 1e6) return error.InvalidDesignValue;
    return @intFromFloat(x - 1);
}

/// Classify the design; values must be 1, 2, ... (p.5515).
pub fn design(a: A, g: []const Value, b: []const Value, tr: []const Value) DesignError!Design {
    return designRep(a, g, b, tr, null, null);
}

/// `design` with an optional Rep column (repetitions of the basic plan).
pub fn designRep(a: A, g: []const Value, b: []const Value, tr: []const Value, rp: ?[]const Value, cell: ?*Cell) DesignError!Design {
    const n = g.len;
    const gi = try a.alloc(usize, n);
    const bi = try a.alloc(usize, n);
    const ti = try a.alloc(usize, n);
    const ri = try a.alloc(usize, n);
    var ng: usize = 0;
    var nb: usize = 0;
    var nt: usize = 0;
    var np: usize = 1;
    for (0..n) |r| {
        gi[r] = try index(g[r]);
        bi[r] = try index(b[r]);
        ti[r] = try index(tr[r]);
        ri[r] = if (rp) |v| try index(v[r]) else 0;
        ng = @max(ng, gi[r] + 1);
        nb = @max(nb, bi[r] + 1);
        nt = @max(nt, ti[r] + 1);
        np = @max(np, ri[r] + 1);
    }
    if (np > 1) {
        // A repeated plan needs one observation per group, treatment and
        // repetition, and each treatment in the same block of its group in
        // every repetition; SAS 15.4 stops with an ERROR otherwise
        // (reference runs: an emptied group of Rep 2, relabelled blocks).
        const count = try a.alloc(usize, np * ng * nt);
        @memset(count, 0);
        for (0..n) |r| count[(ri[r] * ng + gi[r]) * nt + ti[r]] += 1;
        for (count, 0..) |c, key| if (c == 0) {
            if (cell) |o| o.* = .{ .rep = key / (ng * nt) + 1, .group = key / nt % ng + 1, .treatment = key % nt + 1 };
            return error.RepeatedCellMissing;
        };
        const home0 = try a.alloc(usize, ng * nt);
        @memset(home0, std.math.maxInt(usize));
        for (0..n) |r| if (ri[r] == 0) {
            home0[gi[r] * nt + ti[r]] = bi[r];
        };
        for (0..n) |r| if (home0[gi[r] * nt + ti[r]] != bi[r]) {
            if (cell) |o| o.* = .{ .rep = ri[r] + 1, .group = gi[r] + 1, .treatment = ti[r] + 1 };
            return error.RepeatedCellConflict;
        };
    }
    // Rectangular lattice (Overview p.5511): k+1 blocks of k units per
    // replicate, k(k+1) treatments, two or three replicates, unrepeated.
    const rect = np == 1 and (ng == 2 or ng == 3) and nb >= 3 and (nb - 1) * nb == nt;
    const k = if (rect) nb - 1 else std.math.sqrt(nt);
    // Partially balanced square lattice (Overview p.5511): only some of the
    // k+1 orthogonal replicates, unrepeated. ponytail: a partially balanced
    // plan repeated through Rep is not verified and stays a gap.
    const partial = !rect and np == 1 and ng >= 2 and ng < k + 1;
    if (rect) {
        if (n != ng * nt) return error.NotBalancedSquare;
    } else if (k < 2 or k * k != nt or nb != k or (ng != k + 1 and !partial) or n != np * ng * nt) return error.NotBalancedSquare;
    // Each treatment once per group of every repetition; each block k units;
    // a treatment sits in the same block of its group in every repetition.
    const seen = try a.alloc(bool, np * ng * nt);
    @memset(seen, false);
    const size = try a.alloc(usize, np * ng * nb);
    @memset(size, 0);
    const home = try a.alloc(usize, ng * nt);
    @memset(home, std.math.maxInt(usize));
    for (0..n) |r| {
        const key = (ri[r] * ng + gi[r]) * nt + ti[r];
        if (seen[key]) return error.NotBalancedSquare;
        seen[key] = true;
        size[(ri[r] * ng + gi[r]) * nb + bi[r]] += 1;
        const h = &home[gi[r] * nt + ti[r]];
        if (h.* == std.math.maxInt(usize)) h.* = bi[r] else if (h.* != bi[r]) return error.NotBalancedSquare;
    }
    for (size) |c| if (c != k) return error.NotBalancedSquare;
    // Every pair of treatments together in exactly one block of the plan.
    const pair = try a.alloc(u8, nt * nt);
    @memset(pair, 0);
    for (0..n) |r| for (0..n) |q| {
        if (ri[r] == 0 and ri[q] == 0 and ti[r] < ti[q] and gi[r] == gi[q] and bi[r] == bi[q]) {
            pair[ti[r] * nt + ti[q]] += 1;
            if (pair[ti[r] * nt + ti[q]] > 1) return error.NotBalancedSquare;
        }
    };
    return .{ .k = k, .p = np, .m = ng, .rect = rect, .group = gi, .block = bi, .treatment = ti, .rep = ri };
}

pub const Result = struct {
    k: usize,
    p: usize = 1,
    df: [7]usize, // reps, blocks(adj), component B, treatments, intra, rcbd, total
    ss: [7]f64,
    ms: [7]f64,
    /// Component A (repetitions only, p.5516): df, SS, MS.
    df_a: usize = 0,
    ss_a: f64 = 0,
    ms_a: f64 = 0,
    var_same: f64,
    /// Partially balanced lattices (p.5516): Variance of Means in Different
    /// Blocks and Average of Variance, printed when `partial` and adjusted.
    partial: bool = false,
    var_diff: f64 = 0,
    var_avg: f64 = 0,
    /// A rectangular lattice with Eb > Ee: the recovery of inter-block
    /// information is not verified and the caller raises a gap.
    unverified: bool = false,
    lsd01: f64,
    lsd05: f64,
    efficiency: f64,
    means: []const f64,
    adjusted: bool,
};

/// Balanced lattice closed form (Cochran and Cox 1957, sec. 10.3), the basic
/// plan repeated p >= 1 times: r = p(k+1) replicates, lambda = p.
/// Blocks within replications (adj.) = SS(blocks | reps) + SS(trt adj) -
/// SS(trt unadj); Component A = SS among the p blocks holding the same
/// treatments after replications; Component B = Blocks - A.
/// Recovery: E[Eb] = s2 + (k(r-1)/r) sb2 for this resolvable BIBD, so the
/// inter-block weight is w' = 1/(Ee + r(Eb - Ee)/(r - 1)) and the effective
/// error (precision factor k/(k+1) intra, 1/(k+1) inter) is
/// Ee' = (k+1) / (k/Ee + w') = Ee(1 + k mu); for p = 1 this is Cochran and
/// Cox's mu = (Eb - Ee)/(k^2 Eb). Adjusted totals T + (mu/p) W with
/// W_t = sum over the blocks holding t of C_b, C_b = (sum of the treatment
/// totals in b) - r B_b. SAS 15.4 reference run (Rep 1 and 2) reproduces
/// every printed value.
pub fn analyze(a: A, d: Design, y: []const f64) !Result {
    if (d.rect) return analyzeRect(a, d, y);
    if (d.m != 0 and d.m != d.k + 1) return analyzePartial(a, d, y);
    const k = d.k;
    const kf: f64 = @floatFromInt(k);
    const np = d.p;
    const pf: f64 = @floatFromInt(np);
    const ng = k + 1;
    const r = np * ng;
    const rf: f64 = @floatFromInt(r);
    const nt = k * k;
    const n = y.len;
    const nf: f64 = @floatFromInt(n);
    var total: f64 = 0;
    const rep = try a.alloc(f64, r); // replicate (repetition, group) totals
    const blk = try a.alloc(f64, r * k);
    const set = try a.alloc(f64, ng * k); // block totals summed over repetitions
    const grp = try a.alloc(f64, ng);
    const trt = try a.alloc(f64, nt);
    for ([_][]f64{ rep, blk, set, grp, trt }) |x| @memset(x, 0);
    for (y, 0..) |v, i| {
        const rg = d.repOf(i) * ng + d.group[i];
        total += v;
        rep[rg] += v;
        blk[rg * k + d.block[i]] += v;
        set[d.group[i] * k + d.block[i]] += v;
        grp[d.group[i]] += v;
        trt[d.treatment[i]] += v;
    }
    const cf = total * total / nf;
    // Corrected sums of squares around the mean avoid cancellation.
    const mean = total / nf;
    var ss_total: f64 = 0;
    for (y) |v| ss_total += (v - mean) * (v - mean);
    var rep_sq: f64 = 0;
    for (rep) |x| rep_sq += x * x;
    const ss_rep = rep_sq / (kf * kf) - cf;
    var ss_trt: f64 = 0;
    for (trt) |x| ss_trt += x * x;
    ss_trt = ss_trt / rf - cf;
    const c = try a.alloc(f64, r * k);
    for (c, blk) |*x, b| x.* = -rf * b;
    for (0..n) |i| c[(d.repOf(i) * ng + d.group[i]) * k + d.block[i]] += trt[d.treatment[i]];
    // Blocks within replications adjusted for treatments (intrablock
    // analysis of a resolvable BIBD with lambda = p): SS(blocks | reps) +
    // SS(treatments adj) - SS(treatments unadj), with Q_t = T_t - (sum of
    // the totals of the blocks containing t) / k and SS(treatments adj) =
    // k sum Q_t^2 / (lambda k^2).
    var ss_bu: f64 = 0;
    for (blk) |x| ss_bu += x * x;
    ss_bu = ss_bu / kf - rep_sq / (kf * kf);
    const q = try a.alloc(f64, nt);
    @memcpy(q, trt);
    for (0..n) |i| q[d.treatment[i]] -= blk[(d.repOf(i) * ng + d.group[i]) * k + d.block[i]] / kf;
    var ss_ta: f64 = 0;
    for (q) |x| ss_ta += x * x;
    ss_ta /= pf * kf;
    const ss_blk = ss_bu + ss_ta - ss_trt;
    // Component A: blocks within replications minus the block sets within
    // groups (both unadjusted; a set holds the same treatments).
    var ss_a: f64 = 0;
    if (np > 1) {
        var set_sq: f64 = 0;
        for (set) |x| set_sq += x * x;
        var grp_sq: f64 = 0;
        for (grp) |x| grp_sq += x * x;
        ss_a = ss_bu - (set_sq / (pf * kf) - grp_sq / (pf * kf * kf));
    }
    const ss_intra = ss_total - ss_rep - ss_trt - ss_blk;
    var res: Result = undefined;
    res.k = k;
    res.p = np;
    const df_blk = r * (k - 1);
    const df_rep = r - 1;
    const df_e = n - 1 - df_rep - df_blk - (nt - 1);
    res.df_a = (np - 1) * (nt - 1);
    res.ss_a = ss_a;
    res.ms_a = if (res.df_a > 0) ss_a / @as(f64, @floatFromInt(res.df_a)) else 0;
    res.df = .{ df_rep, df_blk, nt - 1, nt - 1, df_e, df_blk + df_e, n - 1 };
    res.ss = .{ ss_rep, ss_blk, ss_blk - ss_a, ss_trt, ss_intra, ss_blk + ss_intra, ss_total };
    for (&res.ms, res.ss, res.df) |*m, sv, df| m.* = sv / @as(f64, @floatFromInt(df));
    const eb = res.ms[1];
    const ee = res.ms[4];
    const eff_err = if (eb > ee) (kf + 1) / (kf / ee + 1 / (ee + rf * (eb - ee) / (rf - 1))) else ee;
    const mu = (eff_err / ee - 1) / kf;
    res.efficiency = 100 * res.ms[5] / eff_err;
    // Means are adjusted for blocks when the relative precision exceeds 105%
    // (p.5517). Otherwise the variance is labelled Variance of Difference
    // and the LSDs use the randomized complete block error df (SAS 15.4
    // reference run with Eb < Ee: 2 Ee / r, t on 24 df for the 3x3 plan).
    res.adjusted = res.efficiency > 105;
    // Without adjustment the variance ignores recovery: 2 Ee / r (SAS 15.4
    // reference runs with Eb < Ee and with Eb > Ee at efficiency 103.88).
    res.var_same = 2 * (if (res.adjusted) eff_err else ee) / rf;
    const dfe: f64 = @floatFromInt(if (res.adjusted) df_e else df_blk + df_e);
    res.lsd01 = inference.tQuantile(0.995, dfe) * @sqrt(res.var_same);
    res.lsd05 = inference.tQuantile(0.975, dfe) * @sqrt(res.var_same);
    const w = try a.alloc(f64, nt);
    @memset(w, 0);
    for (0..n) |i| w[d.treatment[i]] += c[(d.repOf(i) * ng + d.group[i]) * k + d.block[i]];
    const means = try a.alloc(f64, nt);
    for (means, trt, w) |*m, x, wt| m.* = (if (res.adjusted) x + mu / pf * wt else x) / rf;
    res.means = means;
    return res;
}

/// Partially balanced square lattice with m replicates (2 <= m <= k, basic
/// plan not repeated), Cochran and Cox (1957, ch. 10): C_b = (sum of the
/// treatment totals in b) - m B_b; Blocks within replications (adj.) =
/// sum C_b^2 / (k m (m-1)) - sum_j (sum of C_b in replicate j)^2 /
/// (k^2 m (m-1)); intra-block error by subtraction. Weights w = 1/Ee,
/// w' = (m-1)/(m Eb - Ee), mu = (w - w') / (k((m-1)w + w')); adjusted
/// totals T + mu sum_{b holding t} C_b; variances of a difference of means
/// 2Ee/m (1 + (m-1)mu) in the same block, 2Ee/m (1 + m mu) otherwise, and
/// on average 2Ee/m (1 + m k mu/(k+1)); LSDs from the average on the
/// intra-block df; efficiency = RCBD MS / (m/2 average). Without recovery
/// (Eb <= Ee or efficiency <= 105) the balanced rules apply. Every printed
/// value matches Example 75.1 (p.5506) and SAS 15.4 reference runs (triple
/// and simple 3x3 subsets of the Getting Started data).
fn analyzePartial(a: A, d: Design, y: []const f64) !Result {
    const k = d.k;
    const kf: f64 = @floatFromInt(k);
    const m = d.m;
    const mf: f64 = @floatFromInt(m);
    const nt = k * k;
    const n = y.len;
    const nf: f64 = @floatFromInt(n);
    const rep = try a.alloc(f64, m);
    const blk = try a.alloc(f64, m * k);
    const trt = try a.alloc(f64, nt);
    for ([_][]f64{ rep, blk, trt }) |x| @memset(x, 0);
    var total: f64 = 0;
    for (y, 0..) |v, i| {
        total += v;
        rep[d.group[i]] += v;
        blk[d.group[i] * k + d.block[i]] += v;
        trt[d.treatment[i]] += v;
    }
    const cf = total * total / nf;
    // Corrected sum of squares around the mean, as in the balanced path.
    // ponytail: printed values that are exact decimal ties can round either
    // way against SAS (a derived response with SS 411.305 and MS 4.04375).
    const mean = total / nf;
    var ss_total: f64 = 0;
    for (y) |v| ss_total += (v - mean) * (v - mean);
    var rep_sq: f64 = 0;
    for (rep) |x| rep_sq += x * x;
    const ss_rep = rep_sq / (kf * kf) - cf;
    var ss_trt: f64 = 0;
    for (trt) |x| ss_trt += x * x;
    ss_trt = ss_trt / mf - cf;
    const c = try a.alloc(f64, m * k);
    for (c, blk) |*x, b| x.* = -mf * b;
    for (0..n) |i| c[d.group[i] * k + d.block[i]] += trt[d.treatment[i]];
    var c_sq: f64 = 0;
    for (c) |x| c_sq += x * x;
    var cr_sq: f64 = 0;
    for (0..m) |j| {
        var sj: f64 = 0;
        for (c[j * k .. (j + 1) * k]) |x| sj += x;
        cr_sq += sj * sj;
    }
    const ss_blk = c_sq / (kf * mf * (mf - 1)) - cr_sq / (kf * kf * mf * (mf - 1));
    const ss_intra = ss_total - ss_rep - ss_trt - ss_blk;
    const df_rep = m - 1;
    const df_blk = m * (k - 1);
    const df_e = n - 1 - df_rep - df_blk - (nt - 1);
    var res: Result = undefined;
    res.k = k;
    res.p = 1;
    res.df_a = 0;
    res.ss_a = 0;
    res.ms_a = 0;
    res.partial = true;
    res.df = .{ df_rep, df_blk, df_blk, nt - 1, df_e, df_blk + df_e, n - 1 };
    res.ss = .{ ss_rep, ss_blk, ss_blk, ss_trt, ss_intra, ss_blk + ss_intra, ss_total };
    for (&res.ms, res.ss, res.df) |*x, sv, df| x.* = sv / @as(f64, @floatFromInt(df));
    const eb = res.ms[1];
    const ee = res.ms[4];
    const mu: f64 = if (eb > ee) blk: {
        const w = 1 / ee;
        const w2 = (mf - 1) / (mf * eb - ee);
        break :blk (w - w2) / (kf * ((mf - 1) * w + w2));
    } else 0;
    const base = 2 * ee / mf;
    res.var_avg = base * (1 + mf * kf * mu / (kf + 1));
    res.efficiency = 100 * res.ms[5] / (mf / 2 * res.var_avg);
    res.adjusted = eb > ee and res.efficiency > 105;
    // SAS 15.4 reference run (simple 3x3, Eb < Ee): Variance of Difference
    // 2Ee/m, LSDs on the RCBD df, unadjusted means.
    res.var_same = if (res.adjusted) base * (1 + (mf - 1) * mu) else base;
    res.var_diff = base * (1 + mf * mu);
    if (!res.adjusted) res.var_avg = base;
    const dfe: f64 = @floatFromInt(if (res.adjusted) df_e else df_blk + df_e);
    res.lsd01 = inference.tQuantile(0.995, dfe) * @sqrt(res.var_avg);
    res.lsd05 = inference.tQuantile(0.975, dfe) * @sqrt(res.var_avg);
    const w = try a.alloc(f64, nt);
    @memset(w, 0);
    for (0..n) |i| w[d.treatment[i]] += c[d.group[i] * k + d.block[i]];
    const means = try a.alloc(f64, nt);
    for (means, trt, w) |*x, t, wt| x.* = (if (res.adjusted) t + mu * wt else t) / mf;
    res.means = means;
    return res;
}

/// Rectangular lattice, m = 2 or 3 replicates of k+1 blocks with k units
/// and k(k+1) treatments: blocks within replications adjusted for
/// treatments by the general intrablock analysis, SS(blocks | reps) +
/// SS(treatments adj) - SS(treatments unadj), with SS(treatments adj) =
/// tau'Q from C tau = Q, C = m I - N N'/k, Q_t = T_t - (sum of the totals
/// of the blocks holding t)/k (solved with C + J, Q summing to zero).
/// Only the no-recovery path (Eb <= Ee) is verified (SAS 15.4 reference
/// run, simple k = 3 lattice): Variance of Difference 2Ee/m, LSDs on the
/// RCBD df, efficiency RCBD MS / Ee, unadjusted means T/m. ponytail: with
/// Eb > Ee the rectangular recovery (Robinson and Watson 1949) is not
/// verified; `unverified` makes the caller raise a gap.
fn analyzeRect(a: A, d: Design, y: []const f64) !Result {
    const k = d.k;
    const kf: f64 = @floatFromInt(k);
    const nb = k + 1;
    const m = d.m;
    const mf: f64 = @floatFromInt(m);
    const nt = k * nb;
    const ntf: f64 = @floatFromInt(nt);
    const n = y.len;
    const nf: f64 = @floatFromInt(n);
    var res: Result = undefined;
    res.k = k;
    res.p = 1;
    res.df_a = 0;
    res.ss_a = 0;
    res.ms_a = 0;
    res.partial = false;
    res.var_diff = 0;
    res.var_avg = 0;
    res.unverified = false;
    // ponytail: the dense solve is O(nt^3); larger plans are not verified.
    if (nt > 420) {
        res.unverified = true;
        return res;
    }
    const rep = try a.alloc(f64, m);
    const blk = try a.alloc(f64, m * nb);
    const trt = try a.alloc(f64, nt);
    for ([_][]f64{ rep, blk, trt }) |x| @memset(x, 0);
    var total: f64 = 0;
    for (y, 0..) |v, i| {
        total += v;
        rep[d.group[i]] += v;
        blk[d.group[i] * nb + d.block[i]] += v;
        trt[d.treatment[i]] += v;
    }
    const cf = total * total / nf;
    const mean = total / nf;
    var ss_total: f64 = 0;
    for (y) |v| ss_total += (v - mean) * (v - mean);
    var rep_sq: f64 = 0;
    for (rep) |x| rep_sq += x * x;
    const ss_rep = rep_sq / ntf - cf;
    var ss_trt: f64 = 0;
    for (trt) |x| ss_trt += x * x;
    ss_trt = ss_trt / mf - cf;
    var blk_sq: f64 = 0;
    for (blk) |x| blk_sq += x * x;
    const ss_bu = blk_sq / kf - rep_sq / ntf;
    // Reduced normal equations (C + J) tau = Q.
    const q = try a.alloc(f64, nt);
    @memcpy(q, trt);
    for (0..n) |i| q[d.treatment[i]] -= blk[d.group[i] * nb + d.block[i]] / kf;
    const cm = try a.alloc(f64, nt * (nt + 1));
    @memset(cm, 1);
    for (0..nt) |t| {
        cm[t * (nt + 1) + t] += mf;
        cm[t * (nt + 1) + nt] = q[t];
    }
    for (0..n) |i| for (0..n) |j| {
        if (d.group[i] == d.group[j] and d.block[i] == d.block[j])
            cm[d.treatment[i] * (nt + 1) + d.treatment[j]] -= 1 / kf;
    };
    for (0..nt) |col| {
        var piv = col;
        for (col + 1..nt) |r| if (@abs(cm[r * (nt + 1) + col]) > @abs(cm[piv * (nt + 1) + col])) {
            piv = r;
        };
        if (piv != col) for (0..nt + 1) |c| std.mem.swap(f64, &cm[piv * (nt + 1) + c], &cm[col * (nt + 1) + c]);
        const pv = cm[col * (nt + 1) + col];
        for (0..nt) |r| if (r != col) {
            const f = cm[r * (nt + 1) + col] / pv;
            if (f != 0) for (col..nt + 1) |c| {
                cm[r * (nt + 1) + c] -= f * cm[col * (nt + 1) + c];
            };
        };
    }
    var ss_ta: f64 = 0;
    for (0..nt) |t| ss_ta += cm[t * (nt + 1) + nt] / cm[t * (nt + 1) + t] * q[t];
    const ss_blk = ss_bu + ss_ta - ss_trt;
    const ss_intra = ss_total - ss_rep - ss_trt - ss_blk;
    const df_rep = m - 1;
    const df_blk = m * k;
    const df_e = n - 1 - df_rep - df_blk - (nt - 1);
    res.df = .{ df_rep, df_blk, df_blk, nt - 1, df_e, df_blk + df_e, n - 1 };
    res.ss = .{ ss_rep, ss_blk, ss_blk, ss_trt, ss_intra, ss_blk + ss_intra, ss_total };
    for (&res.ms, res.ss, res.df) |*x, sv, df| x.* = sv / @as(f64, @floatFromInt(df));
    const ee = res.ms[4];
    res.adjusted = false;
    res.unverified = res.ms[1] > ee;
    res.efficiency = 100 * res.ms[5] / ee;
    res.var_same = 2 * ee / mf;
    const dfe: f64 = @floatFromInt(df_blk + df_e);
    res.lsd01 = inference.tQuantile(0.995, dfe) * @sqrt(res.var_same);
    res.lsd05 = inference.tQuantile(0.975, dfe) * @sqrt(res.var_same);
    const means = try a.alloc(f64, nt);
    for (means, trt) |*x, t| x.* = t / mf;
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
    // Below 0.001 SAS prints six decimals (SAS 15.4 reference runs: 0.000200,
    // 0.000446, 0.000019, 0.000011). ponytail: below 0.00001 SAS switches to
    // E notation (2E-6, 3.151E-6), which stays a gap.
    if (x < 0.001) return if (x >= 0.00001) 6 else null;
    const lead: f64 = -@floor(std.math.log10(x)); // 1 for 0.1..1
    return 3 + @as(usize, @intFromFloat(lead));
}

fn num(a: A, x: f64) ![]const u8 {
    const p = places(x) orelse return error.UnverifiedValue;
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, p });
}

/// Treatment means and sums of products may be negative: the same places as
/// |x| with a sign (SAS 15.4 reference runs, -1.1965, -0.05159, -14.6078).
fn meanPlaces(x: f64) ?usize {
    return places(@abs(x));
}

fn meanNum(a: A, x: f64) ![]const u8 {
    const p = meanPlaces(x) orelse return error.UnverifiedValue;
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
    for (sources, r.df, r.ss, r.ms, 0..) |name, df, ss, ms, i| {
        // Component A precedes Component B when the basic plan is repeated
        // (SAS 15.4 reference run with Rep 1 and 2).
        if (i == 2 and r.p > 1) {
            try pad(a, out, "   Component A", 37, true);
            try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{r.df_a}), 6, false);
            try pad(a, out, try num(a, r.ss_a), 12, false);
            try pad(a, out, try num(a, r.ms_a), 12, false);
            try out.append(a, '\n');
        }
        try pad(a, out, name, 37, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{df}), 6, false);
        try pad(a, out, try num(a, ss), 12, false);
        try pad(a, out, try num(a, ms), 12, false);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try centered(a, out, try std.fmt.allocPrint(a, "Additional Statistics for {s}", .{dep}), 49);
    try out.append(a, '\n');
    const labels = [_][]const u8{ if (r.adjusted) "Variance of Means in Same Block" else "Variance of Difference", "LSD at .01 Level", "LSD at .05 Level", "Efficiency Relative to RCBD" };
    const values = [_]f64{ r.var_same, r.lsd01, r.lsd05, r.efficiency };
    // Partially balanced and adjusted: two variances of means and their
    // average before the LSDs (Example 75.1, p.5506).
    const pl = [_][]const u8{ "Variance of Means in Same Block", "Variance of Means in Different Blocks", "Average of Variance", "LSD at .01 Level", "LSD at .05 Level", "Efficiency Relative to RCBD" };
    const pv = [_]f64{ r.var_same, r.var_diff, r.var_avg, r.lsd01, r.lsd05, r.efficiency };
    const both = r.partial and r.adjusted;
    for (if (both) &pl else labels[0..], if (both) &pv else values[0..]) |l, v| {
        try pad(a, out, l, 37, true);
        try pad(a, out, try num(a, v), 12, false);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    // The 21-wide table title wraps after "Treatment"; centering as in the
    // reference listing (one extra column on the right half).
    if (r.adjusted) {
        try centered(a, out, "Adjusted Treatment", 22);
        try centered(a, out, try std.fmt.allocPrint(a, "Means for {s}", .{dep}), 22);
    } else {
        // Unadjusted means: "Treatment Means" / "for <name>" (SAS 15.4
        // reference run).
        // A one-character name fits the 21-wide title on one line (SAS 15.4
        // reference run: "Treatment Means for Y").
        if (dep.len == 1) {
            try centered(a, out, try std.fmt.allocPrint(a, "Treatment Means for {s}", .{dep}), 22);
        } else {
            try centered(a, out, "Treatment Means", 22);
            try centered(a, out, try std.fmt.allocPrint(a, "for {s}", .{dep}), 22);
        }
    }
    try out.appendSlice(a, " \nTreatment        Mean\n\n");
    for (r.means, 1..) |m, t| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{t}), 9, false);
        try pad(a, out, try meanNum(a, m), 12, false);
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
/// One COVARIANCE table: responses i < j (indexes into Spec.vars), sums of
/// products per source and for Component A.
const Pair = struct { i: usize, j: usize, sp: [7]f64, sp_a: f64 };
const Group = struct { results: []const ?Result, pairs: []const Pair = &.{} };

/// Sums of products by polarization of the quadratic forms:
/// SP = (SS(x+y) - SS(x) - SS(y)) / 2 for every source.
pub fn products(a: A, d: Design, x: []const f64, y: []const f64, rx: Result, ry: Result) ![7]f64 {
    return (try productsFull(a, d, x, y, rx, ry)).sp;
}

pub fn productsFull(a: A, d: Design, x: []const f64, y: []const f64, rx: Result, ry: Result) !struct { sp: [7]f64, sp_a: f64 } {
    const z = try a.alloc(f64, x.len);
    for (z, x, y) |*v, p, q| v.* = p + q;
    const rz = try analyze(a, d, z);
    var sp: [7]f64 = undefined;
    for (&sp, rz.ss, rx.ss, ry.ss) |*o, sz, sx, sy| o.* = (sz - sx - sy) / 2;
    return .{ .sp = sp, .sp_a = (rz.ss_a - rx.ss_a - ry.ss_a) / 2 };
}

fn group(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Group {
    const a = cx.arena;
    if (rows.len == 0) return user(cx, 0, "the input data set has no observations", .{});
    // Rep (p.5515): values 1, ..., p number the repetitions of the basic
    // plan; a constant Rep of 1 is the basic plan itself (SAS 15.4 reference
    // run lists it exactly as without Rep).
    const rp: ?[]Value = if (s.rep) |c| blk: {
        const v = try a.alloc(Value, rows.len);
        for (rows, v) |row, *x| {
            const val = row[c].num;
            if (std.math.isNan(val)) return cx.diags.fail(error.ParseError, 0, "Missing value(s) encountered for REP variable.", .{});
            if (val < 1 or val != @floor(val)) return user(cx, 0, "values of Rep must be 1, 2, ..., p", .{});
            x.* = row[c];
        }
        break :blk v;
    } else null;
    const g = try a.alloc(Value, rows.len);
    const b = try a.alloc(Value, rows.len);
    const tr = try a.alloc(Value, rows.len);
    for (rows, g, b, tr) |row, *x, *y, *z| {
        x.* = row[s.group];
        y.* = row[s.block];
        z.* = row[s.treatment];
    }
    var cell: Cell = .{};
    const d = designRep(a, g, b, tr, rp, &cell) catch |e| switch (e) {
        error.RepeatedCellMissing => return user(cx, 0, "There are 0 observations in the GROUP {d} TREATMENT {d} REP {d} Cell. There should be one.", .{ cell.group, cell.treatment, cell.rep }),
        error.RepeatedCellConflict => return user(cx, 0, "TREATMENT {d} has been placed into two different cells in GROUP {d} REP {d}.", .{ cell.treatment, cell.group, cell.rep }),
        error.OutOfMemory => return error.OutOfMemory,
        // "If a value of Group, Block, Treatment, or Rep is missing, the
        // analysis is not performed and an appropriate error message is
        // displayed" (p.5516).
        error.MissingDesignValue => return cx.diags.fail(error.ParseError, 0, "Missing value(s) encountered for {s} variable.", .{missingDesign(s, rows)}),
        error.InvalidDesignValue => return user(cx, 0, "values of Group, Block and Treatment must be 1, 2, ..., n", .{}),
        error.NotBalancedSquare => return gap(cx, 0, "only balanced square lattices (optionally repeated through Rep with the same blocks in every repetition), unrepeated partially balanced square lattices and unrepeated simple or triple rectangular lattices are implemented; repeated partially balanced or rectangular plans and other designs are not", .{}),
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
        const r = try analyze(a, d, y);
        if (r.unverified) return gap(cx, 0, "the recovery of inter-block information for rectangular lattices (block mean square above the intra-block error, or more than 420 treatments) is not verified", .{});
        // A partially balanced lattice with recovery writes no design NOTE
        // (SAS 15.4 reference log); without recovery the efficiency NOTE.
        if (r.partial and r.adjusted) {} else if (r.adjusted)
            try cx.diags.note(0, "The design specified is a balanced square lattice. With this design only one variance term, Variance of Means in Same Block, is appropriate.", .{})
        else
            try cx.diags.note(0, "Since the efficiency of the lattice design compared to a randomized complete block design is less than 105 percent, the Variance of Difference and LSD's are appropriate for the randomized complete block design.", .{});
        if (r.p > 1) for ([_]f64{ r.ss_a, r.ms_a }) |x| if (places(x) == null) return gap(cx, 0, "listing format for value {d} is not verified", .{x});
        for (r.ss ++ r.ms) |x| if (places(x) == null) return gap(cx, 0, "listing format for value {d} is not verified", .{x});
        for ([_]f64{ r.var_same, r.lsd01, r.lsd05, r.efficiency, if (r.partial and r.adjusted) r.var_diff else 1, if (r.partial and r.adjusted) r.var_avg else 1 }) |x| if (places(x) == null) return gap(cx, 0, "listing format for value {d} is not verified", .{x});
        for (r.means) |x| if (meanPlaces(x) == null) return gap(cx, 0, "listing format for adjusted mean {d} is not verified", .{x});
        res.* = r;
    }
    if (!s.covariance) return .{ .results = results };
    // Every pair of analyzed responses, the later one the covariable
    // (p.5514); pairs with a dropped response are omitted (SAS 15.4
    // reference runs with three responses and with a dropped one).
    var pairs: std.ArrayList(Pair) = .empty;
    for (results, 0..) |ri, i| if (ri) |rx| for (results[i + 1 ..], i + 1..) |rj, j| if (rj) |ry| {
        const f = try productsFull(a, d, ys[i], ys[j], rx, ry);
        for (f.sp, rx.df) |x, df| if (meanPlaces(x) == null or meanPlaces(x / @as(f64, @floatFromInt(df))) == null)
            return gap(cx, 0, "listing format for sum of products {d} is not verified", .{x});
        if (d.p > 1) if (meanPlaces(f.sp_a) == null or meanPlaces(f.sp_a / @as(f64, @floatFromInt(rx.df_a))) == null)
            return gap(cx, 0, "listing format for sum of products {d} is not verified", .{f.sp_a});
        try pairs.append(a, .{ .i = i, .j = j, .sp = f.sp, .sp_a = f.sp_a });
    };
    return .{ .results = results, .pairs = pairs.items };
}

/// The COVARIANCE table: sums of products and mean products per source,
/// after the first response's listing (SAS 15.4 reference run).
pub fn renderProducts(a: A, out: *Out, x: []const u8, y: []const u8, df: [7]usize, sp: [7]f64) !void {
    return renderProductsA(a, out, x, y, df, sp, 0, 0);
}

/// `renderProducts` with the Component A row when df_a > 0 (SAS 15.4
/// reference run, Rep 1 and 2).
fn renderProductsA(a: A, out: *Out, x: []const u8, y: []const u8, df: [7]usize, sp: [7]f64, df_a: usize, sp_a: f64) !void {
    try centered(a, out, try std.fmt.allocPrint(a, "Analysis of Covariance for {s} and {s}", .{ x, y }), 67);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "                                                 Sum of        Mean\n");
    try out.appendSlice(a, "Source                                   DF    Products     Product\n\n");
    for (sources, df, sp, 0..) |name, d, v, i| {
        if (i == 2 and df_a > 0) {
            try pad(a, out, "   Component A", 37, true);
            try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{df_a}), 6, false);
            try pad(a, out, try meanNum(a, sp_a), 12, false);
            try pad(a, out, try meanNum(a, sp_a / @as(f64, @floatFromInt(df_a))), 12, false);
            try out.append(a, '\n');
        }
        try pad(a, out, name, 37, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{d}), 6, false);
        try pad(a, out, try meanNum(a, v), 12, false);
        try pad(a, out, try meanNum(a, v / @as(f64, @floatFromInt(d))), 12, false);
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
            for (grp.pairs) |pr| if (pr.i == vi) {
                try out.appendSlice(a, "\n\n");
                renderProductsA(a, out, cols[s.vars[pr.i]].name, cols[s.vars[pr.j]].name, r.df, pr.sp, r.df_a, pr.sp_a) catch |e| switch (e) {
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
