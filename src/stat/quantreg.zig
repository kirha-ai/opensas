//! PROC QUANTREG declarations, variable roles, observation selection and the
//! default listing (STAT-QUANTREG-001), SAS/STAT 15.4 physical pp.8372-8378
//! (PROC statement), 8378 (BY), 8385-8386 (ID), 8393 (WEIGHT); the default
//! simplex fit and the rank-inversion confidence limits follow the chapter's
//! "Inversion of Rank Tests" section (p.8403).
//!
//! Implemented: ALGORITHM=SIMPLEX (exact vertex solution of the quantile LP),
//! CI=RANK (the default for <= 5000 observations and <= 20 variables) and
//! CI=NONE, one quantile level, BY groups, NOSUMMARY, ALPHA=. Every other
//! valid feature is a D-009 gap (rc 2) raised before any listing text.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fns = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const class_levels = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Algorithm = enum { simplex, interior, smooth };
pub const CiMethod = enum { default, none, rank, sparsity, resampling };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    algorithm: Algorithm = .simplex,
    /// ALGORITHM= suboptions are present (none is implemented).
    algorithm_suboptions: bool = false,
    ci: CiMethod = .default,
    /// CI= suboptions (BF/HS, /IID, NREP=) are present.
    ci_suboptions: bool = false,
    alpha: f64 = 0.05,
    order: class_levels.Order = .formatted,
    namelen: usize = 20,
    inest: ?[]const u8 = null,
    outest: ?[]const u8 = null,
    plots: bool = false,
    response: usize = 0,
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    /// QUANTILE= values in MODEL order; empty means the default median.
    quantiles: []const f64 = &.{},
    seed: ?f64 = null,
    nosummary: bool = false,
    itprint: bool = false,
    noint: bool = false,
    /// MODEL options owned by later QUANTREG tickets.
    model_later: []const []const u8 = &.{},
    weight: ?usize = null,
    ids: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    /// Statements owned by later QUANTREG tickets, lower-cased.
    later: []const []const u8 = &.{},
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
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC QUANTREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, l: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, l, "PROC QUANTREG: " ++ text, args);
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC QUANTREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    if (at(t, i + 1, .dot) and at(t, i + 2, .name)) {
        into.* = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ t[i].text, t[i + 2].text });
        return i + 3;
    }
    into.* = t[i].text;
    return i + 1;
}
fn number(t: []const lex.Token, i: usize) ?f64 {
    var sign: f64 = 1;
    var j = i;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return null;
    return sign * (std.fmt.parseFloat(f64, t[j].text) catch return null);
}

/// Documented statements owned by later QUANTREG tickets (Table 103.x).
const later_statements = [_][]const u8{ "conddist", "effect", "estimate", "output", "performance", "test", "code" };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const lower = try std.ascii.allocLowerString(a, t[i].text);
        const option: []const u8 = if (eq(lower, "plot")) "plots" else lower;
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx, t[i].line, "repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "algorithm") and valued) {
            const j = i + 2;
            s.algorithm = if (kw(t, j, "simplex")) .simplex else if (kw(t, j, "interior") or kw(t, j, "ipm")) .interior else if (kw(t, j, "smooth")) .smooth else return cx.diags.fail(error.ParseError, line(t, j), "PROC QUANTREG: ALGORITHM= must be SIMPLEX, INTERIOR or SMOOTH", .{});
            i = j + 1;
            if (at(t, i, .lparen)) {
                s.algorithm_suboptions = true;
                i = proc.skipParen(t, i);
            }
        } else if (eq(option, "ci") and valued) {
            const j = i + 2;
            s.ci = if (kw(t, j, "none")) .none else if (kw(t, j, "rank")) .rank else if (kw(t, j, "sparsity")) .sparsity else if (kw(t, j, "resampling")) .resampling else return cx.diags.fail(error.ParseError, line(t, j), "PROC QUANTREG: CI= must be NONE, RANK, SPARSITY or RESAMPLING", .{});
            i = j + 1;
            if (at(t, i, .lparen)) {
                s.ci_suboptions = true;
                i = proc.skipParen(t, i);
            }
            if (at(t, i, .slash) and kw(t, i + 1, "iid")) {
                s.ci_suboptions = true;
                i += 2;
            }
        } else if (eq(option, "alpha") and valued) {
            const v = number(t, i + 2);
            // p.8377: "The value must be between 0 and 1."
            if (v == null or !(v.? > 0 and v.? < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC QUANTREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = v.?;
            i += if (at(t, i + 2, .minus)) 4 else 3;
        } else if (eq(option, "namelen") and valued) {
            const n = if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null;
            if (n == null or n.? < 20 or n.? > 200) return cx.diags.fail(error.ParseError, t[i].line, "PROC QUANTREG: NAMELEN= must be an integer between 20 and 200", .{});
            s.namelen = n.?;
            i += 3;
        } else if (eq(option, "order") and valued) {
            s.order = if (kw(t, i + 2, "data")) .data else if (kw(t, i + 2, "formatted")) .formatted else if (kw(t, i + 2, "freq")) .freq else if (kw(t, i + 2, "internal")) .internal else return cx.diags.fail(error.ParseError, t[i].line, "PROC QUANTREG: ORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
            i += 3;
        } else if (eq(option, "inest") and valued) {
            i = try memberName(cx, t, i + 2, &s.inest);
        } else if (eq(option, "outest") and valued) {
            i = try memberName(cx, t, i + 2, &s.outest);
        } else if (eq(option, "plots")) {
            // PLOTS=NONE draws nothing; any other request is a later ticket.
            i += 1;
            var none = false;
            if (at(t, i, .eq)) {
                i += 1;
                if (at(t, i, .lparen)) {
                    none = kw(t, i + 1, "none") and at(t, i + 2, .rparen);
                    i = proc.skipParen(t, i);
                } else if (at(t, i, .name)) {
                    none = eq(t[i].text, "none");
                    i += 1;
                    if (at(t, i, .lparen)) i = proc.skipParen(t, i);
                } else return invalid(cx, t, i);
            }
            s.plots = !none;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC QUANTREG: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.data_name = name orelse raw.name;
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var classes: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var quantiles: std.ArrayList(f64) = .empty;
    var model_later: std.ArrayList([]const u8) = .empty;
    var later: std.ArrayList([]const u8) = .empty;
    var model_seen = false;
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
        } else if (eq(word, "class")) {
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC QUANTREG: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .lparen) or at(t, j, .slash)) return gap(cx, t[j].line, "CLASS options are not implemented (STAT-QUANTREG-003)", .{});
                const ci = try column(cx, ds, t, j);
                if (!has(classes.items, ci)) try classes.append(a, ci);
            }
        } else if (eq(word, "model")) {
            if (model_seen) return gap(cx, t[i].line, "more than one MODEL statement is not verified", .{});
            model_seen = true;
            var j = i + 1;
            if (at(t, j, .name) and at(t, j + 1, .colon)) return gap(cx, t[j].line, "MODEL statement labels are not implemented (STAT-QUANTREG-003)", .{});
            s.response = try numericColumn(cx, ds, t, j, "response");
            j += 1;
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) {
                    if (at(t, j, .star) or at(t, j, .pipe) or at(t, j, .lparen) or at(t, j, .rparen) or at(t, j, .at))
                        return gap(cx, t[j].line, "crossed, nested, bar and constructed effects are not implemented (STAT-QUANTREG-003)", .{});
                    return invalid(cx, t, j);
                }
                const ci = try column(cx, ds, t, j);
                if (ds.columns.items[ci].type != .num and !has(classes.items, ci))
                    return cx.diags.fail(error.ParseError, t[j].line, "PROC QUANTREG: character variable {s} in the MODEL statement must be a CLASS variable", .{t[j].text});
                try effects.append(a, ci);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const opt = t[j].text;
                    j += 1;
                    if (eq(opt, "quantile") or eq(opt, "quantiles")) {
                        if (!at(t, j, .eq)) return invalid(cx, t, j);
                        j += 1;
                        if (kw(t, j, "process") or kw(t, j, "fqpr")) return gap(cx, t[j].line, "QUANTILE=PROCESS/FQPR is not implemented (STAT-QUANTREG-002)", .{});
                        while (j < end and (at(t, j, .number) or at(t, j, .comma))) : (j += 1) {
                            if (at(t, j, .comma)) continue;
                            const q = std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j);
                            try quantiles.append(a, q);
                        }
                        if (at(t, j, .lparen)) return gap(cx, t[j].line, "QUANTILE= suboptions are not implemented (STAT-QUANTREG-002)", .{});
                    } else if (eq(opt, "seed")) {
                        if (!at(t, j, .eq) or !at(t, j + 1, .number)) return invalid(cx, t, j);
                        s.seed = std.fmt.parseFloat(f64, t[j + 1].text) catch return invalid(cx, t, j + 1);
                        j += 2;
                    } else if (eq(opt, "nosummary")) {
                        s.nosummary = true;
                    } else if (eq(opt, "itprint")) {
                        s.itprint = true;
                    } else if (eq(opt, "noint")) {
                        s.noint = true;
                    } else {
                        try model_later.append(a, opt);
                        if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                        if (at(t, j, .eq)) {
                            j += 1;
                            if (j >= end) return invalid(cx, t, j);
                            if (at(t, j, .lparen)) j = proc.skipParen(t, j) else {
                                j += 1;
                                if (at(t, j, .lparen)) j = proc.skipParen(t, j);
                            }
                        }
                    }
                }
            }
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "more than one WEIGHT statement is not verified", .{});
            if (end != i + 2) return invalid(cx, t, @min(i + 2, end));
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (eq(word, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) : (j += 1) {
                const ci = try column(cx, ds, t, j);
                if (!has(ids.items, ci)) try ids.append(a, ci);
            }
        } else if (oneOf(word, &later_statements)) {
            try later.append(a, try std.ascii.allocLowerString(a, word));
        } else if (eq(word, "format")) {
            return gap(cx, t[i].line, "a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, line(t, 0), "PROC QUANTREG: a MODEL statement is required", .{});
    s.classes = classes.items;
    s.effects = effects.items;
    s.ids = ids.items;
    s.quantiles = quantiles.items;
    s.model_later = model_later.items;
    s.later = later.items;
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Observation selection for one BY group: an observation with a missing
/// response, explanatory or CLASS value is not used; with WEIGHT, a missing
/// or nonpositive weight is not used.
pub const Selection = struct { read: usize, rows: []const usize, missing: usize, bad_weight: usize };

pub fn prepare(a: A, s: Spec, rows: []const []const Value) !Selection {
    var kept: std.ArrayList(usize) = .empty;
    var out: Selection = .{ .read = rows.len, .rows = &.{}, .missing = 0, .bad_weight = 0 };
    for (rows, 0..) |row, k| {
        var miss = selection.missing(row[s.response]);
        for (s.effects) |ci| miss = miss or selection.missing(row[ci]);
        for (s.classes) |ci| miss = miss or selection.missing(row[ci]);
        var w_ok = true;
        if (s.weight) |ci| w_ok = !std.math.isNan(row[ci].num) and row[ci].num > 0;
        if (miss) out.missing += 1;
        if (!w_ok) out.bad_weight += 1;
        if (miss or !w_ok) continue;
        try kept.append(a, k);
    }
    out.rows = kept.items;
    return out;
}

// ---------------------------------------------------------------- estimation

pub const FitError = error{ OutOfMemory, Singular, NotConverged };

/// Solve the p x p row-major system `m x = rhs` in place (rhs becomes x).
fn solve(m: []f64, rhs: []f64, p: usize) error{Singular}!void {
    for (0..p) |c| {
        var piv = c;
        for (c + 1..p) |r| if (@abs(m[r * p + c]) > @abs(m[piv * p + c])) {
            piv = r;
        };
        if (@abs(m[piv * p + c]) < 1e-13) return error.Singular;
        if (piv != c) {
            for (0..p) |k| std.mem.swap(f64, &m[c * p + k], &m[piv * p + k]);
            std.mem.swap(f64, &rhs[c], &rhs[piv]);
        }
        for (c + 1..p) |r| {
            const f = m[r * p + c] / m[c * p + c];
            if (f == 0) continue;
            for (c..p) |k| m[r * p + k] -= f * m[c * p + k];
            rhs[r] -= f * rhs[c];
        }
    }
    var c = p;
    while (c > 0) {
        c -= 1;
        var v = rhs[c];
        for (c + 1..p) |k| v -= m[c * p + k] * rhs[k];
        rhs[c] = v / m[c * p + c];
    }
}

/// The design: n rows of p columns, row-major.
pub const Design = struct { x: []const f64, n: usize, p: usize };

fn basisMatrix(a: A, d: Design, basis: []const usize, transpose: bool) ![]f64 {
    const p = d.p;
    const m = try a.alloc(f64, p * p);
    for (basis, 0..) |obs, r| for (0..p) |c| {
        if (transpose) m[c * p + r] = d.x[obs * p + c] else m[r * p + c] = d.x[obs * p + c];
    };
    return m;
}

pub const Vertex = struct { beta: []f64, basis: []usize };

/// Exact tau-quantile regression: minimise sum rho_tau(y - X beta) by
/// descending along the edges of the LP polytope (a Barrodale-Roberts style
/// simplex with a full weighted-median line search). `start` is a warm-start
/// basis (any p observations with a nonsingular X_h), or null.
pub fn fitVertex(a: A, d: Design, y: []const f64, tau: f64, start: ?[]const usize) FitError!Vertex {
    const n = d.n;
    const p = d.p;
    const basis = try a.alloc(usize, p);
    if (start) |st| @memcpy(basis, st) else {
        // Greedy nonsingular start: add rows whose Gram-Schmidt residual is not 0.
        const q = try a.alloc(f64, p * p);
        var k: usize = 0;
        var obs: usize = 0;
        while (k < p and obs < n) : (obs += 1) {
            var v = try a.alloc(f64, p);
            for (0..p) |c| v[c] = d.x[obs * p + c];
            for (0..k) |r| {
                var dot: f64 = 0;
                for (0..p) |c| dot += v[c] * q[r * p + c];
                for (0..p) |c| v[c] -= dot * q[r * p + c];
            }
            var norm: f64 = 0;
            for (v) |e| norm += e * e;
            norm = @sqrt(norm);
            if (norm < 1e-8) continue;
            for (0..p) |c| q[k * p + c] = v[c] / norm;
            basis[k] = obs;
            k += 1;
        }
        if (k < p) return error.Singular;
    }
    const beta = try a.alloc(f64, p);
    const r = try a.alloc(f64, n);
    const in_basis = try a.alloc(bool, n);
    const g = try a.alloc(f64, p);
    const delta = try a.alloc(f64, p);
    const z = try a.alloc(f64, n);
    const Cross = struct { t: f64, obs: usize, w: f64 };
    var crosses: std.ArrayList(Cross) = .empty;
    var iter: usize = 0;
    while (iter < 50 * n + 1000) : (iter += 1) {
        for (basis, 0..) |obs, k| beta[k] = y[obs];
        try solve(try basisMatrix(a, d, basis, false), beta, p);
        @memset(in_basis, false);
        for (basis) |obs| in_basis[obs] = true;
        @memset(g, 0);
        for (0..n) |i| {
            if (in_basis[i]) {
                r[i] = 0;
                continue;
            }
            var fit: f64 = 0;
            for (0..p) |c| fit += d.x[i * p + c] * beta[c];
            r[i] = y[i] - fit;
            const psi = if (r[i] < 0) tau - 1 else tau;
            for (0..p) |c| g[c] += d.x[i * p + c] * psi;
        }
        // u = X_h^{-T} g; the vertex is optimal iff -tau <= u_k <= 1 - tau.
        try solve(try basisMatrix(a, d, basis, true), g, p);
        var best: f64 = -1e-11;
        var leave: ?usize = null;
        var sign: f64 = 0;
        for (g, 0..) |u, k| {
            const up = 1 - tau - u;
            const down = u + tau;
            if (up < best) {
                best = up;
                leave = k;
                sign = 1;
            }
            if (down < best) {
                best = down;
                leave = k;
                sign = -1;
            }
        }
        const k = leave orelse return .{ .beta = beta, .basis = basis };
        @memset(delta, 0);
        delta[k] = sign;
        try solve(try basisMatrix(a, d, basis, false), delta, p);
        crosses.clearRetainingCapacity();
        for (0..n) |i| {
            if (in_basis[i]) continue;
            var zi: f64 = 0;
            for (0..p) |c| zi += d.x[i * p + c] * delta[c];
            z[i] = zi;
            if ((zi > 0 and r[i] >= 0) or (zi < 0 and r[i] < 0)) try crosses.append(a, .{ .t = r[i] / zi, .obs = i, .w = @abs(zi) });
        }
        std.mem.sort(Cross, crosses.items, {}, struct {
            fn lt(_: void, l: Cross, rr: Cross) bool {
                return l.t < rr.t;
            }
        }.lt);
        var slope = best;
        var enter: ?usize = null;
        for (crosses.items) |c| {
            slope += c.w;
            if (slope >= 0) {
                enter = c.obs;
                break;
            }
        }
        basis[k] = enter orelse return error.Singular;
    }
    return error.NotConverged;
}

/// Sum of rho_tau over the residuals of `beta`.
pub fn objective(d: Design, y: []const f64, tau: f64, beta: []const f64) f64 {
    var sum: f64 = 0;
    for (0..d.n) |i| {
        var fit: f64 = 0;
        for (0..d.p) |c| fit += d.x[i * d.p + c] * beta[c];
        const res = y[i] - fit;
        sum += if (res < 0) (tau - 1) * res else tau * res;
    }
    return sum;
}

/// Regression rank scores of the vertex: a_i = 1 (r > 0), 0 (r < 0), and
/// the basic ones from X1' a = (1 - tau) X1' 1.
fn rankScores(a: A, d: Design, y: []const f64, tau: f64, v: Vertex) FitError![]f64 {
    const n = d.n;
    const p = d.p;
    const scores = try a.alloc(f64, n);
    const rhs = try a.alloc(f64, p);
    @memset(rhs, 0);
    const in_basis = try a.alloc(bool, n);
    @memset(in_basis, false);
    for (v.basis) |obs| in_basis[obs] = true;
    for (0..n) |i| {
        for (0..p) |c| rhs[c] += (1 - tau) * d.x[i * p + c];
        if (in_basis[i]) continue;
        var fit: f64 = 0;
        for (0..p) |c| fit += d.x[i * p + c] * v.beta[c];
        scores[i] = if (y[i] - fit > 0) 1 else 0;
        for (0..p) |c| rhs[c] -= scores[i] * d.x[i * p + c];
    }
    try solve(try basisMatrix(a, d, v.basis, true), rhs, p);
    for (v.basis, 0..) |obs, k| scores[obs] = rhs[k];
    return scores;
}

/// The next breakpoint beyond b (direction dir) at which a nonbasic residual
/// of the reduced fit `v` changes sign: r_i(b') = r_i(b) - (b' - b) s_i with
/// s_i = x_ji - x1_i' X1_h^{-1} x_jh.
fn nextBreak(a: A, red: Design, x1: []const f64, xj: []const f64, yb: []const f64, v: Vertex, b: f64, dir: f64) FitError!f64 {
    const p1 = red.p;
    const gamma = try a.alloc(f64, p1);
    for (v.basis, 0..) |obs, k| gamma[k] = xj[obs];
    try solve(try basisMatrix(a, red, v.basis, false), gamma, p1);
    var step: f64 = std.math.inf(f64);
    for (0..red.n) |i| {
        if (std.mem.indexOfScalar(usize, v.basis, i) != null) continue;
        var fit: f64 = 0;
        var dfit: f64 = 0;
        for (0..p1) |c| {
            fit += x1[i * p1 + c] * v.beta[c];
            dfit += x1[i * p1 + c] * gamma[c];
        }
        const rate = dir * (xj[i] - dfit);
        if (rate == 0) continue;
        const h = (yb[i] - fit) / rate;
        if (h > 0 and h < step) step = h;
    }
    if (!std.math.isFinite(step)) return error.NotConverged;
    return b + dir * step;
}

pub const Limits = struct { lower: f64, upper: f64 };

/// Confidence limits for coefficient `j` by inverting the rank-score test
/// (p.8403; Koenker and d'Orey 1994): T_n(b) is piecewise constant in b; the
/// path follows the breakpoints where a residual of the reduced fit changes
/// sign until |T_n| exceeds the critical value, then interpolates linearly
/// between the last accepted and the first rejected breakpoint.
pub fn rankLimits(a: A, d: Design, y: []const f64, tau: f64, j: usize, estimate: f64, full_basis: []const usize, cutoff: f64) FitError!Limits {
    const n = d.n;
    const p1 = d.p - 1;
    const x1 = try a.alloc(f64, n * p1);
    const xj = try a.alloc(f64, n);
    for (0..n) |i| {
        var c1: usize = 0;
        for (0..d.p) |c| {
            if (c == j) {
                xj[i] = d.x[i * d.p + c];
            } else {
                x1[i * p1 + c1] = d.x[i * d.p + c];
                c1 += 1;
            }
        }
    }
    const red: Design = .{ .x = x1, .n = n, .p = p1 };
    // q = x_j' (I - P_1) x_j through the normal equations of x_j on X1.
    const q = blk: {
        const m = try a.alloc(f64, p1 * p1);
        const rhs = try a.alloc(f64, p1);
        @memset(m, 0);
        @memset(rhs, 0);
        for (0..n) |i| for (0..p1) |r| {
            rhs[r] += x1[i * p1 + r] * xj[i];
            for (0..p1) |c| m[r * p1 + c] += x1[i * p1 + r] * x1[i * p1 + c];
        };
        try solve(m, rhs, p1);
        var sum: f64 = 0;
        for (0..n) |i| {
            var fit: f64 = 0;
            for (0..p1) |c| fit += x1[i * p1 + c] * rhs[c];
            sum += (xj[i] - fit) * (xj[i] - fit);
        }
        break :blk sum;
    };
    const scale = @sqrt(tau * (1 - tau) * q);
    const yb = try a.alloc(f64, n);
    const shifted = struct {
        fn set(out: []f64, yy: []const f64, xx: []const f64, b: f64) void {
            for (out, yy, xx) |*o, v, w| o.* = v - w * b;
        }
    }.set;
    const stat = struct {
        fn of(al: A, dd: Design, yy: []const f64, t: f64, xx: []const f64, v: Vertex, sc: f64) FitError!f64 {
            const s = try rankScores(al, dd, yy, t, v);
            var sum: f64 = 0;
            for (s, xx) |sv, w| sum += w * (sv - (1 - t));
            return sum / sc;
        }
    }.of;
    var out: Limits = undefined;
    // Warm start: the full fit's basis without one observation, chosen so
    // that the reduced basis matrix is nonsingular.
    const warm = try a.alloc(usize, p1);
    var found = false;
    for (0..d.p) |drop| {
        var k: usize = 0;
        for (full_basis, 0..) |obs, m| if (m != drop) {
            warm[k] = obs;
            k += 1;
        };
        const probe = try a.alloc(f64, p1);
        @memset(probe, 1);
        solve(try basisMatrix(a, red, warm, false), probe, p1) catch continue;
        found = true;
        break;
    }
    if (!found) return error.Singular;
    for ([_]f64{ 1, -1 }) |dir| {
        // At b = estimate the reduced problem is degenerate (p zero
        // residuals); the first interval is evaluated just beside it.
        const eps0 = 1e-9 * @max(1.0, @abs(estimate));
        var b = estimate + dir * eps0;
        shifted(yb, y, xj, b);
        var v = try fitVertex(a, red, yb, tau, warm);
        const t_first = try stat(a, red, yb, tau, xj, v, scale);
        if (@abs(t_first) > cutoff) {
            if (dir > 0) out.upper = estimate else out.lower = estimate;
            continue;
        }
        // Interval k is (b_{k-1}, b_k) with statistic T_k, b_0 = estimate.
        // The limit interpolates linearly between (b_{k-2}, T_{k-1}) of the
        // last accepted and (b_{k-1}, T_k) of the first rejected interval:
        // each statistic is attached to the breakpoint that starts its
        // interval (matches the reference listing; attaching it to the end
        // misses in the 4th decimal).
        var b_end_prev = estimate;
        var t_prev: f64 = t_first;
        var b_end = try nextBreak(a, red, x1, xj, yb, v, b, dir);
        var steps: usize = 0;
        while (true) : (steps += 1) {
            if (steps > 10 * n) return error.NotConverged;
            // Re-solve just past the breakpoint (one pivot from the warm basis).
            const eps = 1e-9 * @max(1.0, @abs(b_end));
            b = b_end + dir * eps;
            shifted(yb, y, xj, b);
            v = try fitVertex(a, red, yb, tau, v.basis);
            const t_next = try stat(a, red, yb, tau, xj, v, scale);
            const b_next_end = try nextBreak(a, red, x1, xj, yb, v, b, dir);
            if (@abs(t_next) > cutoff) {
                const bound = b_end_prev + dir * @abs(b_end - b_end_prev) * (cutoff - @abs(t_prev)) / @abs(t_next - t_prev);
                if (dir > 0) out.upper = bound else out.lower = bound;
                break;
            }
            b_end_prev = b_end;
            t_prev = t_next;
            b_end = b_next_end;
        }
    }
    return out;
}

// ------------------------------------------------------- summary statistics

/// Percentile definition 5 (the PROC MEANS/UNIVARIATE default) of sorted x.
fn pctl5(sorted: []const f64, pct: f64) f64 {
    const np = @as(f64, @floatFromInt(sorted.len)) * pct;
    const j = @floor(np);
    const ji: usize = @intFromFloat(j);
    if (np > j) return sorted[ji];
    if (ji == 0) return sorted[0];
    return (sorted[ji - 1] + sorted[ji]) / 2;
}

pub const Summary = struct { q1: f64, median: f64, q3: f64, mean: f64, sd: f64, mad: f64 };

/// Q1, median, Q3 (definition 5), mean, standard deviation (n - 1) and MAD
/// scaled by 1.4826 (published table, p.8414: MAD 5.9304 = 1.4826 * 4).
pub fn summarize(a: A, values: []const f64) !Summary {
    const n = values.len;
    const sorted = try a.dupe(f64, values);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    var mean: f64 = 0;
    for (values) |v| mean += v;
    mean /= @floatFromInt(n);
    var ss: f64 = 0;
    for (values) |v| ss += (v - mean) * (v - mean);
    const median = pctl5(sorted, 0.5);
    const dev = try a.alloc(f64, n);
    for (sorted, dev) |v, *o| o.* = @abs(v - median);
    std.mem.sort(f64, dev, {}, std.sort.asc(f64));
    return .{
        .q1 = pctl5(sorted, 0.25),
        .median = median,
        .q3 = pctl5(sorted, 0.75),
        .mean = mean,
        .sd = if (n > 1) @sqrt(ss / @as(f64, @floatFromInt(n - 1))) else std.math.nan(f64),
        .mad = 1.4826 * pctl5(dev, 0.5),
    };
}

// ----------------------------------------------------------------- rendering

fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn fixed(a: A, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    // ponytail: the summary table prints 0 bare and keeps 4 decimals
    // otherwise (published tables, pp.8411-8424); smaller magnitudes that
    // SAS shows with more decimals are a later formatting ticket.
    if (x == 0) return "0";
    const s = try std.fmt.allocPrint(a, "{d:.4}", .{x});
    return if (std.mem.eql(u8, s, "-0.0000")) "0.0000" else s;
}
fn centered(a: A, out: *Out, title: []const u8, width: usize) !void {
    if (title.len < width) try out.appendNTimes(a, ' ', (width - title.len) / 2);
    try out.appendSlice(a, title);
    try out.append(a, '\n');
}

pub const Group = struct {
    used: usize,
    read: usize,
    tau: f64,
    objective: f64,
    at_mean: f64,
    names: []const []const u8,
    beta: []const f64,
    limits: ?[]const Limits,
    summary: ?[]const Summary,
    summary_names: []const []const u8,
};

const algorithm_names = [_][]const u8{ "Simplex", "Interior", "Smooth" };

/// One fit's listing (reference: the chapter's default simplex listing,
/// Output 103.1.1-103.1.3).
fn render(a: A, out: *Out, s: Spec, g: Group) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe QUANTREG Procedure\n\n");
    const data_name = blk: {
        const upper = try std.ascii.allocUpperString(a, s.data_name);
        break :blk if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    };
    var info: std.ArrayList([2][]const u8) = .empty;
    try info.append(a, .{ "Data Set", data_name });
    try info.append(a, .{ "Dependent Variable", ds.columns.items[s.response].name });
    try info.append(a, .{ "Number of Independent Variables", try std.fmt.allocPrint(a, "{d}", .{s.effects.len}) });
    try info.append(a, .{ "Number of Observations", try std.fmt.allocPrint(a, "{d}", .{g.used}) });
    try info.append(a, .{ "Optimization Algorithm", algorithm_names[@intFromEnum(s.algorithm)] });
    if (g.limits != null) try info.append(a, .{ "Method for Confidence Limits", "Inv_Rank" });
    // ponytail: the value column is at least 8 wide, 10 with the CI method
    // row (reference listings); longer values widen it.
    var value_width: usize = if (g.limits != null) 10 else 8;
    for (info.items) |row| value_width = @max(value_width, row[1].len);
    try centered(a, out, "Model Information", 35 + value_width);
    try out.append(a, '\n');
    for (info.items) |row| {
        try padRight(a, out, row[0], 31);
        try padLeft(a, out, row[1], value_width + 4);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n", .{ g.read, g.used });

    if (g.summary) |sum| {
        var name_width: usize = 8;
        for (g.summary_names) |nm| name_width = @max(name_width, nm.len);
        name_width += 1;
        const total = name_width + 12 * 5 + 13;
        try out.appendSlice(a, "\n\n");
        try centered(a, out, "Summary Statistics", total);
        try out.appendSlice(a, " \n");
        try padLeft(a, out, "Standard", name_width + 12 * 4 + 13);
        try out.append(a, '\n');
        try padRight(a, out, "Variable", name_width);
        try out.appendSlice(a, "          Q1      Median          Q3        Mean    Deviation         MAD\n\n");
        for (sum, g.summary_names) |row, nm| {
            try padRight(a, out, nm, name_width);
            for ([_]f64{ row.q1, row.median, row.q3, row.mean }) |v| try padLeft(a, out, try fixed(a, v), 12);
            try padLeft(a, out, try fixed(a, row.sd), 13);
            try padLeft(a, out, try fixed(a, row.mad), 12);
            try out.append(a, '\n');
        }
    }

    try out.appendSlice(a, "\n\n");
    const qrows = [_][2][]const u8{
        .{ "Quantile Level", try std.fmt.allocPrint(a, "{d}", .{g.tau}) },
        .{ "Objective Function", try std.fmt.allocPrint(a, "{d:.4}", .{g.objective}) },
        .{ "Predicted Value at Mean", try std.fmt.allocPrint(a, "{d:.4}", .{g.at_mean}) },
    };
    var qw: usize = 12;
    for (qrows) |row| qw = @max(qw, row[1].len);
    try centered(a, out, "Quantile Level and Objective Function", 27 + qw);
    try out.append(a, '\n');
    for (qrows) |row| {
        try padRight(a, out, row[0], 23);
        try padLeft(a, out, row[1], qw + 4);
        try out.append(a, '\n');
    }

    var name_width: usize = 9;
    for (g.names) |nm| name_width = @max(name_width, nm.len);
    const left = name_width + 12;
    try out.appendSlice(a, "\n\n");
    if (g.limits) |lim| {
        try centered(a, out, "Parameter Estimates", left + 20);
        try out.appendSlice(a, " \n");
        const conf = try std.fmt.allocPrint(a, "{d}% Confidence", .{@round((1 - s.alpha) * 1000) / 10});
        try out.appendNTimes(a, ' ', left + (22 - @min(22, conf.len)) / 2);
        try out.appendSlice(a, conf);
        try out.append(a, '\n');
        try padRight(a, out, "Parameter", name_width);
        try out.appendSlice(a, " DF Estimate        Limits\n\n");
        for (g.names, g.beta, lim) |nm, b, l| {
            try padRight(a, out, nm, name_width);
            try out.appendSlice(a, "  1");
            try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{b}), 9);
            try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{l.lower}), 10);
            try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{l.upper}), 10);
            try out.append(a, '\n');
        }
    } else {
        try centered(a, out, "Parameter Estimates", left);
        try out.appendSlice(a, " \n");
        try padRight(a, out, "Parameter", name_width);
        try out.appendSlice(a, " DF Estimate\n\n");
        for (g.names, g.beta) |nm, b| {
            try padRight(a, out, nm, name_width);
            try out.appendSlice(a, "  1");
            try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{b}), 9);
            try out.append(a, '\n');
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    for (s.quantiles) |q| if (!(q > 0 and q < 1)) return gap(cx, l0, "QUANTILE= values outside (0,1) are not verified (STAT-QUANTREG-002)", .{});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const selections = try a.alloc(Selection, groups.len);
    for (groups, selections) |group, *sel| sel.* = try prepare(a, s, group.rows);

    // Boundaries owned by later QUANTREG tickets: fail visibly, print nothing.
    if (s.later.len > 0) return gap(cx, l0, "the {s} statement is not implemented (STAT-QUANTREG-002..012)", .{s.later[0]});
    if (s.model_later.len > 0) return gap(cx, l0, "MODEL option {s} is not implemented (STAT-QUANTREG-002..008)", .{s.model_later[0]});
    if (s.plots) return gap(cx, l0, "PLOTS= graphs are not implemented (STAT-QUANTREG-011)", .{});
    if (s.inest != null) return gap(cx, l0, "INEST= is not implemented (STAT-QUANTREG-006)", .{});
    if (s.outest != null) return gap(cx, l0, "OUTEST= is not implemented (STAT-QUANTREG-009)", .{});
    if (s.algorithm != .simplex) return gap(cx, l0, "ALGORITHM={s} is not implemented (STAT-QUANTREG-004)", .{if (s.algorithm == .interior) "INTERIOR" else "SMOOTH"});
    if (s.algorithm_suboptions) return gap(cx, l0, "ALGORITHM= suboptions are not implemented (STAT-QUANTREG-004)", .{});
    if (s.itprint) return gap(cx, l0, "ITPRINT iteration history is not implemented (STAT-QUANTREG-004)", .{});
    if (s.ci == .sparsity or s.ci == .resampling) return gap(cx, l0, "CI={s} is not implemented (STAT-QUANTREG-007)", .{if (s.ci == .sparsity) "SPARSITY" else "RESAMPLING"});
    if (s.ci_suboptions) return gap(cx, l0, "CI= suboptions are not implemented (STAT-QUANTREG-007)", .{});
    if (s.classes.len > 0) return gap(cx, l0, "CLASS variables are not implemented (STAT-QUANTREG-003)", .{});
    if (s.noint) return gap(cx, l0, "NOINT is not implemented (STAT-QUANTREG-003)", .{});
    if (s.weight != null) return gap(cx, l0, "the weighted listing is not verified against SAS output (WEIGHT is parsed; STAT-QUANTREG-002)", .{});
    if (s.quantiles.len > 1) return gap(cx, l0, "more than one QUANTILE= level is not implemented (STAT-QUANTREG-002)", .{});
    if (s.effects.len == 0) return gap(cx, l0, "an intercept-only model is not implemented (STAT-QUANTREG-002)", .{});
    const p = s.effects.len + 1;
    const tau: f64 = if (s.quantiles.len == 1) s.quantiles[0] else 0.5;
    for (groups, selections) |group, sel| {
        if (sel.missing > 0 or sel.bad_weight > 0) return gap(cx, l0, "the listing counts with observations excluded for missing values are not verified (STAT-QUANTREG-002)", .{});
        if (sel.rows.len <= p) return gap(cx, l0, "a fit with {d} observations for {d} parameters is not verified", .{ sel.rows.len, p });
        _ = group;
    }
    // p.8403: the rank method for <= 5000 observations and <= 20 variables,
    // MCMB resampling (a SAS random stream) otherwise.
    var ci = s.ci;
    if (ci == .default) {
        for (selections) |sel| if (sel.rows.len > 5000 or p > 20) return gap(cx, l0, "the default CI=RESAMPLING (more than 5000 observations or 20 variables) is not implemented (STAT-QUANTREG-007)", .{});
        ci = .rank;
    }
    if (s.quantiles.len == 0) try cx.diags.note(0, "No valid quantiles are specified. PROC QUANTREG computes median regression.", .{});

    var body: Out = .empty;
    const names = try a.alloc([]const u8, p);
    names[0] = "Intercept";
    for (s.effects, 1..) |ci_col, k| names[k] = ds.columns.items[ci_col].name;
    const summary_names = try a.alloc([]const u8, s.effects.len + 1);
    for (s.effects, 0..) |ci_col, k| summary_names[k] = ds.columns.items[ci_col].name;
    summary_names[s.effects.len] = ds.columns.items[s.response].name;
    for (groups, selections) |group, sel| {
        const n = sel.rows.len;
        const x = try a.alloc(f64, n * p);
        const y = try a.alloc(f64, n);
        const means = try a.alloc(f64, p);
        @memset(means, 0);
        for (sel.rows, 0..) |ri, i| {
            const row = group.rows[ri];
            x[i * p] = 1;
            for (s.effects, 1..) |c, k| x[i * p + k] = row[c].num;
            y[i] = row[s.response].num;
            for (0..p) |k| means[k] += x[i * p + k] / @as(f64, @floatFromInt(n));
        }
        const d: Design = .{ .x = x, .n = n, .p = p };
        const v = fitVertex(a, d, y, tau, null) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx, l0, "a singular design is not implemented (STAT-QUANTREG-002)", .{}),
            error.NotConverged => return gap(cx, l0, "the simplex did not terminate; nonconvergence reporting is not implemented (STAT-QUANTREG-004)", .{}),
        };
        var at_mean: f64 = 0;
        for (means, v.beta) |m, b| at_mean += m * b;
        var limits: ?[]Limits = null;
        if (ci == .rank) {
            // Critical value of the rank-score statistic: Student t with
            // n - p degrees of freedom (Koenker and d'Orey 1994 as in the
            // reference listing; the normal quantile misses it in the 4th decimal).
            const cutoff = fns.distQuantile(.t, 1 - s.alpha / 2, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = @floatFromInt(n - p) } }).?;
            const lim = try a.alloc(Limits, p);
            for (0..p) |j| lim[j] = rankLimits(a, d, y, tau, j, v.beta[j], v.basis, cutoff) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return gap(cx, l0, "the rank-inversion confidence limits could not be computed for this design ({s}; STAT-QUANTREG-007)", .{@errorName(err)}),
            };
            limits = lim;
        }
        var summary: ?[]Summary = null;
        if (!s.nosummary) {
            const sum = try a.alloc(Summary, p);
            const col = try a.alloc(f64, n);
            for (0..p) |k| {
                for (0..n) |i| col[i] = if (k < s.effects.len) x[i * p + k + 1] else y[i];
                sum[k] = try summarize(a, col);
            }
            summary = sum;
        }
        if (s.by_cols.len > 0) try by.appendLine(a, &body, ds, group.rows[0], s.by_cols);
        try render(a, &body, s, .{ .used = n, .read = sel.read, .tau = tau, .objective = objective(d, y, tau, v.beta), .at_mean = at_mean, .names = names, .beta = v.beta, .limits = limits, .summary = summary, .summary_names = summary_names });
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("quantreg_tests.zig");
}
