//! PROC RSREG: declarations, roles and the default quadratic response-surface
//! listing (STAT-RSREG-001). S154 physical pp.8870-8874 (PROC RSREG
//! statement, BY, ID), pp.8878-8879 (WEIGHT), pp.8881-8882 (coding, missing
//! values); listing layout from the SAS reference listing of the chapter's
//! Getting Started data. Least squares reuses reg_fit (read-only) and the
//! symmetric eigen-decomposition reuses princomp.eigenSym (read-only).
//! Everything owned by later RSREG tickets (OUT=, RIDGE, COVAR=, NOCODE,
//! PRESS, BYOUT, output statistics, PLOTS under ODS GRAPHICS, ODS routing,
//! several responses) is a loud rc 2 gap, never a silent no-op.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const lists = @import("variable_lists.zig");
const by = @import("by_groups.zig");
const reg_fit = @import("reg_fit.zig");
const princomp = @import("princomp.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Spec = struct {
    input: proc.ProcInput,
    response: usize = 0,
    factors: []const usize = &.{},
    weight: ?usize = null,
    ids: []const usize = &.{},
    lackfit: bool = false,
    noanova: bool = false,
    nooptimal: bool = false,
    noprint: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    line: usize = 0,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC RSREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC RSREG: " ++ fmt, args);
}
fn member(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        i.* += 1;
        if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i.*].text });
        i.* += 1;
    }
    return name;
}
fn numericList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, role: []const u8, line: usize) diag.Error![]const usize {
    var names: std.ArrayList([]const u8) = .empty;
    try lists.append(cx.arena, ds, t, &names, cx.diags);
    var cols: std.ArrayList(usize) = .empty;
    for (names.items) |nm| {
        const ci = ds.indexOf(nm) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{nm});
        if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, line, "Variable {s} in list does not match type prescribed for this list.", .{nm});
        _ = role;
        try cols.append(cx.arena, ci);
    }
    return cols.items;
}

const later_model_options = [_][]const u8{ "byout", "nocode", "press", "actual", "predict", "residual", "l95", "u95", "l95m", "u95m", "d" };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var i: usize = 2;
    var name: ?[]const u8 = null;
    var qualified_start: ?usize = null;
    var result: Spec = .{ .input = undefined, .line = lineOf(t, 0) };
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "noprint")) {
            result.noprint = true;
            i += 1;
            continue;
        }
        if (kw(t, i, "plots") or kw(t, i, "plot")) {
            // p.8858: graphs need ODS GRAPHICS; with it off PLOTS= draws nothing.
            const line = t[i].line;
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
            if (!at(t, i, .eq)) return invalid(cx, t, i);
            i += 1;
            const none = kw(t, i, "none");
            if (at(t, i, .lparen)) i = proc.skipParen(t, i) else {
                if (!at(t, i, .name)) return invalid(cx, t, i);
                i += 1;
                if (at(t, i, .lparen)) i = proc.skipParen(t, i);
            }
            if (!none) if (cx.graphics) |g| if (g.enabled == true)
                return gap(cx, line, "PLOTS= graphs under ODS GRAPHICS are not implemented (STAT-RSREG-008)", .{});
            continue;
        }
        if (!at(t, i, .name) or !at(t, i + 1, .eq)) return invalid(cx, t, i);
        const option = t[i];
        i += 2;
        if (eq(option.text, "data")) {
            const start = i;
            name = try member(cx, t, &i);
            if (i - start == 3) qualified_start = start;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(option.text, "out")) {
            return gap(cx, option.line, "OUT= data sets are not implemented (STAT-RSREG-006)", .{});
        } else return invalid(cx, t, i - 2);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const ds = (if (name) |nm| cx.lib.find(nm) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, lineOf(t, 0), "File {s} does not exist.", .{if (name) |nm| nm else "_LAST_"});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified_start) |start| {
        try folded.appendSlice(cx.arena, t[0..start]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[start].line });
        try folded.appendSlice(cx.arena, t[start + 3 ..]);
    }
    result.input = try proc.procInputObs(cx.arena, ds, if (qualified_start != null) folded.items else t, cx.diags);
    const data = result.input.ds;
    var model_seen = false;
    var bys: by.Statements = .{};
    var ids: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const line = t[i].line;
        if (kw(t, i, "model")) {
            // p.8862: one MODEL statement per step in this slice.
            if (model_seen) return gap(cx, line, "multiple MODEL statements are not implemented (STAT-RSREG-003)", .{});
            model_seen = true;
            var e = i + 1;
            while (e < end and !at(t, e, .eq)) e += 1;
            if (e == end) return cx.diags.fail(error.ParseError, line, "PROC RSREG: MODEL statement requires responses = independents", .{});
            var slash = e + 1;
            while (slash < end and !at(t, slash, .slash)) slash += 1;
            const responses = try numericList(cx, data, t[i + 1 .. e], "response", line);
            if (responses.len == 0) return cx.diags.fail(error.ParseError, line, "PROC RSREG: MODEL statement requires a response variable", .{});
            if (responses.len > 1) return gap(cx, line, "several response variables are not implemented (STAT-RSREG-003)", .{});
            result.response = responses[0];
            const factors = try numericList(cx, data, t[e + 1 .. slash], "independent", line);
            if (factors.len == 0) return cx.diags.fail(error.ParseError, line, "PROC RSREG: MODEL statement requires at least one independent variable", .{});
            for (factors, 0..) |f, k| {
                if (f == result.response) return cx.diags.fail(error.ParseError, line, "PROC RSREG: variable {s} is both a response and an independent variable", .{data.columns.items[f].name});
                if (std.mem.indexOfScalar(usize, factors[0..k], f) != null) return cx.diags.fail(error.ParseError, line, "PROC RSREG: independent variable {s} is listed more than once", .{data.columns.items[f].name});
            }
            result.factors = factors;
            var j = slash + 1;
            while (j < end) : (j += 1) {
                if (kw(t, j, "lackfit")) result.lackfit = true else if (kw(t, j, "noanova") or kw(t, j, "noaov")) result.noanova = true else if (kw(t, j, "nooptimal") or kw(t, j, "noopt")) result.nooptimal = true else if (kw(t, j, "noprint")) result.noprint = true else if (kw(t, j, "covar")) {
                    return gap(cx, t[j].line, "MODEL COVAR= is not implemented (STAT-RSREG-005)", .{});
                } else if (at(t, j, .name) and later(t[j].text)) {
                    return gap(cx, t[j].line, "MODEL option {s} is not implemented (STAT-RSREG-003/006)", .{t[j].text});
                } else return invalid(cx, t, j);
            }
        } else if (kw(t, i, "by")) {
            // p.8862: only the last BY statement is used.
            bys = .{};
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "weight")) {
            if (end != i + 2) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const cols = try numericList(cx, data, t[i + 1 .. end], "weight", line);
            if (result.weight != null) return gap(cx, line, "more than one WEIGHT statement is not implemented", .{});
            result.weight = cols[0];
        } else if (kw(t, i, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, data, t[i + 1 .. end], &names, cx.diags);
            for (names.items) |nm| try ids.append(cx.arena, data.indexOf(nm).?);
        } else if (kw(t, i, "ridge")) {
            return gap(cx, line, "RIDGE statement is not implemented (STAT-RSREG-004)", .{});
        } else if (kw(t, i, "ods")) {
            return gap(cx, line, "ODS statements inside the step are not implemented (STAT-RSREG-007)", .{});
        } else if (!kw(t, i, "run") and !kw(t, i, "quit") and !kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, lineOf(t, 0), "No MODEL statement.", .{});
    if (result.weight) |w| {
        if (w == result.response or std.mem.indexOfScalar(usize, result.factors, w) != null)
            return gap(cx, result.line, "a WEIGHT variable that is also a MODEL variable is not implemented", .{});
    }
    result.ids = ids.items;
    const pb = try bys.resolve(cx.arena, data, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = data.indexOf(n).?;
    result.by_cols = cols;
    result.by_desc = pb.desc;
    result.notsorted = pb.notsorted;
    return result;
}

fn later(text: []const u8) bool {
    for (later_model_options) |o| if (eq(text, o)) return true;
    return false;
}

/// One fitted response surface for one BY group.
pub const Surface = struct {
    k: usize,
    n: usize,
    names: []const []const u8,
    labels: []const ?[]const u8,
    center: []f64,
    scale: []f64,
    mean: f64,
    root_mse: f64,
    r_square: f64,
    sst: f64,
    sse: f64,
    df_error: usize,
    /// Linear, Quadratic, Crossproduct, Total Model.
    type1_df: [4]usize,
    type1_ss: [4]f64,
    lackfit: ?struct { df_lof: usize, ss_lof: f64, df_pe: usize, ss_pe: f64 } = null,
    estimate: []f64,
    se: []f64,
    coded: []f64,
    factor_df: []usize,
    factor_ss: []f64,
    critical_coded: []f64,
    critical_uncoded: []f64,
    stationary: f64,
    eigen: princomp.Eigen,
};

fn termCount(k: usize) usize {
    return 1 + k + k * (k + 1) / 2;
}

/// Column order of the SAS listing: intercept, linear terms, then for each
/// factor j the products x_j*x_i for i <= j (T*T, R*T, R*R, H*T, ...).
fn designRow(row: []f64, x: []const f64) void {
    const k = x.len;
    row[0] = 1;
    for (x, 0..) |v, j| row[1 + j] = v;
    var c = 1 + k;
    for (0..k) |j| for (0..j + 1) |i| {
        row[c] = x[j] * x[i];
        c += 1;
    };
}
fn termKind(k: usize, c: usize) enum { intercept, linear, quadratic, cross } {
    if (c == 0) return .intercept;
    if (c <= k) return .linear;
    var idx = 1 + k;
    for (0..k) |j| for (0..j + 1) |i| {
        if (idx == c) return if (i == j) .quadratic else .cross;
        idx += 1;
    };
    unreachable;
}
fn termInvolves(k: usize, c: usize, f: usize) bool {
    if (c == 0) return false;
    if (c <= k) return c - 1 == f;
    var idx = 1 + k;
    for (0..k) |j| for (0..j + 1) |i| {
        if (idx == c) return i == f or j == f;
        idx += 1;
    };
    unreachable;
}

const SubFit = struct { sse: f64, rank: usize };
fn subFit(a: A, x: []const f64, y: []const f64, w: []const f64, n: usize, p: usize, keep: []const bool) FitError!SubFit {
    var q: usize = 0;
    for (keep) |b| q += @intFromBool(b);
    const sub = try a.alloc(f64, n * q);
    for (0..n) |r| {
        var c: usize = 0;
        for (0..p) |j| if (keep[j]) {
            sub[r * q + c] = x[r * p + j];
            c += 1;
        };
    }
    const f = reg_fit.fit(a, sub, y, n, q, w) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ExecError;
    return .{ .sse = f.sse, .rank = f.rank };
}

/// Solve the k*k system m*z = rhs by Gaussian elimination with partial
/// pivoting; null when m is numerically singular.
fn solve(a: A, m: []const f64, rhs: []const f64, k: usize) !?[]f64 {
    const w = try a.dupe(f64, m);
    const z = try a.dupe(f64, rhs);
    var scale: f64 = 0;
    for (m) |v| scale = @max(scale, @abs(v));
    if (!(scale > 0)) return null;
    for (0..k) |c| {
        var piv = c;
        for (c + 1..k) |r| if (@abs(w[r * k + c]) > @abs(w[piv * k + c])) {
            piv = r;
        };
        if (@abs(w[piv * k + c]) <= 1e-12 * scale) return null;
        if (piv != c) {
            for (0..k) |j| std.mem.swap(f64, &w[c * k + j], &w[piv * k + j]);
            std.mem.swap(f64, &z[c], &z[piv]);
        }
        for (c + 1..k) |r| {
            const f = w[r * k + c] / w[c * k + c];
            for (c..k) |j| w[r * k + j] -= f * w[c * k + j];
            z[r] -= f * z[c];
        }
    }
    var c = k;
    while (c > 0) {
        c -= 1;
        var s = z[c];
        for (c + 1..k) |j| s -= w[c * k + j] * z[j];
        z[c] = s / w[c * k + c];
    }
    return z;
}

pub const FitError = error{ OutOfMemory, ExecError, NoObservations, Singular, NoErrorDf, ConstantFactor, NoPureError, NoLackOfFitDf, FlatSurface };

/// Included observations: response, every factor and the weight nonmissing,
/// weight > 0 (pp.8878-8879, 8881-8882). Coding uses the included rows.
pub fn fitSurface(a: A, s: Spec, ds: *const Dataset, rows: []const []const Value) FitError!Surface {
    const k = s.factors.len;
    const p = termCount(k);
    var used: std.ArrayList([]const Value) = .empty;
    for (rows) |row| {
        if (!finite(row[s.response])) continue;
        var ok = true;
        for (s.factors) |f| ok = ok and finite(row[f]);
        if (s.weight) |wc| ok = ok and finite(row[wc]) and row[wc].num > 0;
        if (ok) try used.append(a, row);
    }
    const n = used.items.len;
    if (n == 0) return error.NoObservations;
    const center = try a.alloc(f64, k);
    const scale = try a.alloc(f64, k);
    for (s.factors, 0..) |f, j| {
        var lo = std.math.inf(f64);
        var hi = -std.math.inf(f64);
        for (used.items) |row| {
            lo = @min(lo, row[f].num);
            hi = @max(hi, row[f].num);
        }
        center[j] = (hi + lo) / 2;
        scale[j] = (hi - lo) / 2;
        if (!(scale[j] > 0)) return error.ConstantFactor;
    }
    const x = try a.alloc(f64, n * p);
    const xc = try a.alloc(f64, n * p);
    const y = try a.alloc(f64, n);
    const w = try a.alloc(f64, n);
    const raw = try a.alloc(f64, k);
    const coded_row = try a.alloc(f64, k);
    for (used.items, 0..) |row, r| {
        for (s.factors, 0..) |f, j| {
            raw[j] = row[f].num;
            coded_row[j] = (raw[j] - center[j]) / scale[j];
        }
        designRow(x[r * p ..][0..p], raw);
        designRow(xc[r * p ..][0..p], coded_row);
        y[r] = row[s.response].num;
        w[r] = if (s.weight) |wc| row[wc].num else 1;
    }
    const full = reg_fit.fit(a, x, y, n, p, w) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ExecError;
    if (full.rank < p) return error.Singular;
    if (full.df_error == 0) return error.NoErrorDf;
    const coded = reg_fit.fit(a, xc, y, n, p, w) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ExecError;
    if (coded.rank < p) return error.Singular;

    // Type I: intercept, + linear, + quadratic, + crossproduct (p.8875).
    const keep = try a.alloc(bool, p);
    var type1_ss: [4]f64 = undefined;
    var type1_df: [4]usize = undefined;
    var previous = SubFit{ .sse = full.sst, .rank = 1 };
    const stages = [_]@TypeOf(termKind(0, 0)){ .linear, .quadratic, .cross };
    for (stages, 0..) |stage, st| {
        for (keep, 0..) |*b, c| {
            const kind = termKind(k, c);
            b.* = @intFromEnum(kind) <= @intFromEnum(stage);
        }
        const sf = if (st == 2) SubFit{ .sse = full.sse, .rank = full.rank } else try subFit(a, x, y, w, n, p, keep);
        type1_ss[st] = @max(0, previous.sse - sf.sse);
        type1_df[st] = sf.rank - previous.rank;
        previous = sf;
    }
    type1_ss[3] = @max(0, full.sst - full.sse);
    type1_df[3] = full.rank - 1;

    // Factor tests: joint test of every term involving the factor (p.8876).
    const factor_df = try a.alloc(usize, k);
    const factor_ss = try a.alloc(f64, k);
    for (0..k) |f| {
        for (keep, 0..) |*b, c| b.* = !termInvolves(k, c, f);
        const sf = try subFit(a, x, y, w, n, p, keep);
        factor_ss[f] = @max(0, sf.sse - full.sse);
        factor_df[f] = full.rank - sf.rank;
    }

    var surface: Surface = .{
        .k = k,
        .n = n,
        .names = try a.alloc([]const u8, k),
        .labels = try a.alloc(?[]const u8, k),
        .center = center,
        .scale = scale,
        .mean = full.y_mean,
        .root_mse = @sqrt(full.mse),
        .r_square = if (full.sst > 0) 1 - full.sse / full.sst else nan,
        .sst = full.sst,
        .sse = full.sse,
        .df_error = full.df_error,
        .type1_df = type1_df,
        .type1_ss = type1_ss,
        .estimate = full.coefficients,
        .se = full.se,
        .coded = coded.coefficients,
        .factor_df = factor_df,
        .factor_ss = factor_ss,
        .critical_coded = undefined,
        .critical_uncoded = undefined,
        .stationary = nan,
        .eigen = undefined,
    };
    for (s.factors, 0..) |f, j| {
        @constCast(surface.names)[j] = ds.columns.items[f].name;
        @constCast(surface.labels)[j] = ds.columns.items[f].label;
    }

    if (s.lackfit) {
        // Pure error: weighted spread of replicates sharing all factor values.
        const seen = try a.alloc(bool, n);
        @memset(seen, false);
        var ss_pe: f64 = 0;
        var df_pe: usize = 0;
        for (0..n) |r| {
            if (seen[r]) continue;
            var sw: f64 = 0;
            var swy: f64 = 0;
            var count: usize = 0;
            var members: std.ArrayList(usize) = .empty;
            for (r..n) |q| if (!seen[q] and sameFactors(x[r * p ..][0..p], x[q * p ..][0..p], k)) {
                seen[q] = true;
                try members.append(a, q);
                sw += w[q];
                swy += w[q] * y[q];
                count += 1;
            };
            const m = swy / sw;
            for (members.items) |q| ss_pe += w[q] * (y[q] - m) * (y[q] - m);
            df_pe += count - 1;
        }
        if (df_pe == 0) return error.NoPureError;
        if (df_pe >= full.df_error) return error.NoLackOfFitDf;
        surface.lackfit = .{ .df_lof = full.df_error - df_pe, .ss_lof = @max(0, full.sse - ss_pe), .df_pe = df_pe, .ss_pe = ss_pe };
    }

    // Canonical analysis on the coded fit (p.8873): x_s = -A^{-1} b / 2.
    const am = try a.alloc(f64, k * k);
    var c = 1 + k;
    for (0..k) |j| for (0..j + 1) |i| {
        const v = coded.coefficients[c];
        if (i == j) am[j * k + j] = v else {
            am[j * k + i] = v / 2;
            am[i * k + j] = v / 2;
        }
        c += 1;
    };
    const rhs = try a.alloc(f64, k);
    for (0..k) |j| rhs[j] = -coded.coefficients[1 + j] / 2;
    const xs = (try solve(a, am, rhs, k)) orelse return error.FlatSurface;
    surface.critical_coded = xs;
    surface.critical_uncoded = try a.alloc(f64, k);
    var pred = coded.coefficients[0];
    for (0..k) |j| {
        surface.critical_uncoded[j] = center[j] + scale[j] * xs[j];
        pred += coded.coefficients[1 + j] * xs[j] / 2;
    }
    surface.stationary = pred;
    surface.eigen = try princomp.eigenSym(a, am, k);
    var biggest: f64 = 0;
    for (surface.eigen.values) |v| biggest = @max(biggest, @abs(v));
    for (surface.eigen.values) |v| if (@abs(v) <= 1e-10 * biggest) return error.FlatSurface;
    return surface;
}

fn finite(v: Value) bool {
    return v == .num and std.math.isFinite(v.num);
}
fn sameFactors(l: []const f64, r: []const f64, k: usize) bool {
    for (1..k + 1) |j| if (l[j] != r[j]) return false;
    return true;
}

/// Six-decimal statistic column (SAS Dw. style in the reference listings):
/// zero prints as `0`, six decimals when they fit `w`, else the rounded integer.
/// ponytail: the width-overflow rule is pinned only by the reference values
/// (11444.708333 -> 11445 at w=11); exponent-sized values fail loud.
fn d6(a: A, x: f64, w: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    if (x == 0) return "0";
    const text = try std.fmt.allocPrint(a, "{d:.6}", .{x});
    if (text.len <= w) return text;
    const whole = try std.fmt.allocPrint(a, "{d:.0}", .{x});
    if (whole.len <= w) return whole;
    return error.Unsupported;
}
fn fixed(a: A, x: f64, spec: []const u8) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}
fn pvalue(a: A, x: f64) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    if (x < 0.0001) return "<.0001";
    return std.fmt.allocPrint(a, "{d:.4}", .{x});
}

/// p.8875 coding table; SAS prints it even under NOANOVA (reference run),
/// and with M=0, S=1 when a group has no usable observation.
fn coding(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, names: []const []const u8, center: []const f64, scale: []const f64, first: []const Value) !void {
    const a = cx.arena;
    try heading(cx, out, s, first);
    try out.appendSlice(a, "\nCoding Coefficients for the Independent Variables\n\nFactor Subtracted off Divided by\n\n");
    for (names, 0..) |nm, j| try out.print(a, "{s} {s} {s}\n", .{ nm, try d6(a, center[j], 12), try d6(a, scale[j], 12) });
}

fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, first: []const Value) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out);
    if (s.by_cols.len > 0 and first.len > 0) try by.appendLine(cx.arena, out, s.input.ds, first, s.by_cols);
    try out.appendSlice(cx.arena, "\nThe RSREG Procedure\n");
}

/// Default listing (layout from the SAS reference listing): coding, fit
/// summary, Type I regression ANOVA, residual ANOVA, estimates, factor ANOVA,
/// then a new page with the canonical analysis.
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, f: Surface, first: []const Value) !void {
    const a = cx.arena;
    const rname = s.input.ds.columns.items[s.response].name;
    const mse = f.sse / @as(f64, @floatFromInt(f.df_error));
    var labelled = false;
    for (f.labels) |l| labelled = labelled or l != null;
    try coding(cx, out, s, f.names, f.center, f.scale, first);
    if (!s.noanova) {
        try out.print(a, "\n\nResponse Surface for Variable {s}\n\n", .{rname});
        try out.print(a, "Response Mean {s}\nRoot MSE {s}\nR-Square {s}\nCoefficient of Variation {s}\n", .{
            try d6(a, f.mean, 12), try d6(a, f.root_mse, 12), try fixed(a, f.r_square, "6.4"), try fixed(a, 100 * f.root_mse / f.mean, "8.4"),
        });
        try out.appendSlice(a, "\n\nType I Sum\nRegression DF of Squares R-Square F Value Pr > F\n\n");
        const row_names = [_][]const u8{ "Linear", "Quadratic", "Crossproduct", "Total Model" };
        for (row_names, 0..) |label, r| {
            const df: f64 = @floatFromInt(f.type1_df[r]);
            const fv = (f.type1_ss[r] / df) / mse;
            try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ label, f.type1_df[r], try d6(a, f.type1_ss[r], 11), try fixed(a, f.type1_ss[r] / f.sst, "6.4"), try fixed(a, fv, "7.2"), try pvalue(a, reg_fit.fProbability(fv, f.type1_df[r], f.df_error)) });
        }
        try out.appendSlice(a, "\n\nSum of\nResidual DF Squares Mean Square");
        if (f.lackfit) |lf| {
            try out.appendSlice(a, " F Value Pr > F\n\n");
            const ms_lof = lf.ss_lof / @as(f64, @floatFromInt(lf.df_lof));
            const ms_pe = lf.ss_pe / @as(f64, @floatFromInt(lf.df_pe));
            const fv = ms_lof / ms_pe;
            try out.print(a, "Lack of Fit {d} {s} {s} {s} {s}\n", .{ lf.df_lof, try d6(a, lf.ss_lof, 11), try d6(a, ms_lof, 11), try fixed(a, fv, "7.2"), try pvalue(a, reg_fit.fProbability(fv, lf.df_lof, lf.df_pe)) });
            try out.print(a, "Pure Error {d} {s} {s}\n", .{ lf.df_pe, try d6(a, lf.ss_pe, 11), try d6(a, ms_pe, 11) });
        } else try out.appendSlice(a, "\n\n");
        try out.print(a, "Total Error {d} {s} {s}\n", .{ f.df_error, try d6(a, f.sse, 11), try d6(a, mse, 11) });
        try out.appendSlice(a, "\n\nParameter\nEstimate\nStandard from Coded\nParameter DF Estimate Error t Value Pr > |t| Data\n\n");
        for (0..termCount(f.k)) |c| {
            const t = f.estimate[c] / f.se[c];
            try out.print(a, "{s} 1 {s} {s} {s} {s} {s}\n", .{ try termName(a, f, c), try d6(a, f.estimate[c], 12), try d6(a, f.se[c], 12), try fixed(a, t, "7.2"), try pvalue(a, reg_fit.tProbability(t, f.df_error)), try d6(a, f.coded[c], 12) });
        }
        try out.appendSlice(a, "\n\nSum of\nFactor DF Squares Mean Square F Value Pr > F");
        try out.appendSlice(a, if (labelled) " Label\n\n" else "\n\n");
        for (0..f.k) |j| {
            const df: f64 = @floatFromInt(f.factor_df[j]);
            const ms = f.factor_ss[j] / df;
            const fv = ms / mse;
            try out.print(a, "{s} {d} {s} {s} {s} {s}", .{ f.names[j], f.factor_df[j], try d6(a, f.factor_ss[j], 11), try d6(a, ms, 11), try fixed(a, fv, "7.2"), try pvalue(a, reg_fit.fProbability(fv, f.factor_df[j], f.df_error)) });
            if (labelled) try out.print(a, " {s}", .{f.labels[j] orelse ""});
            try out.append(a, '\n');
        }
    }
    if (!s.nooptimal) {
        try heading(cx, out, s, first);
        try out.appendSlice(a, "Canonical Analysis of Response Surface Based on Coded Data\n\nCritical Value\nFactor Coded Uncoded");
        try out.appendSlice(a, if (labelled) " Label\n\n" else "\n\n");
        for (0..f.k) |j| {
            try out.print(a, "{s} {s} {s}", .{ f.names[j], try d6(a, f.critical_coded[j], 12), try d6(a, f.critical_uncoded[j], 12) });
            if (labelled) try out.print(a, " {s}", .{f.labels[j] orelse ""});
            try out.append(a, '\n');
        }
        try out.print(a, "\nPredicted value at stationary point: {s}\n\n\nEigenvectors\nEigenvalues", .{try d6(a, f.stationary, 12)});
        for (f.names) |nm| try out.print(a, " {s}", .{nm});
        try out.appendSlice(a, "\n\n");
        var pos = false;
        var neg = false;
        for (f.eigen.values, 0..) |v, r| {
            pos = pos or v > 0;
            neg = neg or v < 0;
            try out.print(a, "{s}", .{try d6(a, v, 12)});
            for (0..f.k) |j| try out.print(a, " {s}", .{try d6(a, f.eigen.vectors[j * f.k + r], 12)});
            try out.append(a, '\n');
        }
        try out.print(a, "\nStationary point is a {s}.\n", .{if (pos and neg) @as([]const u8, "saddle point") else if (pos) "minimum" else "maximum"});
    }
}

fn termName(a: A, f: Surface, c: usize) ![]const u8 {
    if (c == 0) return "Intercept";
    if (c <= f.k) return f.names[c - 1];
    var idx = 1 + f.k;
    for (0..f.k) |j| for (0..j + 1) |i| {
        if (idx == c) return std.fmt.allocPrint(a, "{s}*{s}", .{ f.names[j], f.names[i] });
        idx += 1;
    };
    unreachable;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const a = cx.arena;
    if (cx.listing) |selected| if (selected.open and (selected.filtered() or selected.trace != null))
        return gap(cx, s.line, "ODS SELECT/EXCLUDE/TRACE routing of RSREG tables is not implemented (STAT-RSREG-007)", .{});
    const ds = s.input.ds;
    var body: std.ArrayList(u8) = .empty;
    const names = try a.alloc([]const u8, s.factors.len);
    for (s.factors, names) |c, *nm| nm.* = ds.columns.items[c].name;
    const zeros = try a.alloc(f64, s.factors.len);
    @memset(zeros, 0);
    const ones = try a.alloc(f64, s.factors.len);
    @memset(ones, 1);
    if (ds.rows.items.len == 0) {
        // Reference run: an empty input prints the default coding page, then errors.
        if (!s.noprint) coding(cx, &body, s, names, zeros, ones, &.{}) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else gap(cx, s.line, "coding listing failed", .{});
        try out.appendSlice(a, body.items);
        return cx.diags.fail(error.ExecError, s.line, "No non-missing observations to process.", .{});
    }
    // Reference run: SAS prints the groups before an out-of-order BY value,
    // then stops, so the sort check runs group by group.
    const groups = try proc.bySlices(a, ds.rows.items, s.by_cols);
    for (groups, 0..) |group, gi| {
        if (gi > 0 and !s.notsorted) if (proc.byOrderViolation(group.rep.?, groups[gi - 1].rep.?, s.by_cols, s.by_desc, ds.sortseq_linguistic orelse @import("../io.zig").global_sortseq_linguistic)) |k| {
            try out.appendSlice(a, body.items);
            return cx.diags.fail(error.ExecError, s.line, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (s.by_desc[k]) @as([]const u8, "descending") else "ascending" });
        };
        const surface = fitSurface(a, s, ds, group.rows) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoObservations => {
                // Reference run: the group's page shows the default coding, then
                // the step stops with this ERROR and the BY-group NOTE.
                if (!s.noprint) coding(cx, &body, s, names, zeros, ones, group.rows[0]) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else gap(cx, s.line, "coding listing failed", .{});
                try out.appendSlice(a, body.items);
                const e = cx.diags.fail(error.ExecError, s.line, "No non-missing observations to process.", .{});
                if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
                return e;
            },
            error.Singular => return gap(cx, s.line, "a response surface with nonestimable (aliased) parameters is not implemented (STAT-RSREG-002)", .{}),
            error.NoErrorDf => return gap(cx, s.line, "a saturated response surface with no error degrees of freedom is not implemented (STAT-RSREG-002)", .{}),
            error.ConstantFactor => return gap(cx, s.line, "a factor with a single value (zero coding range) is not implemented (STAT-RSREG-004)", .{}),
            error.NoPureError => return gap(cx, s.line, "LACKFIT without replicated design points is not implemented (STAT-RSREG-002)", .{}),
            error.NoLackOfFitDf => return gap(cx, s.line, "LACKFIT with no lack-of-fit degrees of freedom is not implemented (STAT-RSREG-002)", .{}),
            error.FlatSurface => return gap(cx, s.line, "canonical analysis of a flat or singular quadratic surface is not implemented (STAT-RSREG-002)", .{}),
            error.ExecError => return cx.diags.fail(error.ExecError, s.line, "PROC RSREG: the regression could not be computed", .{}),
        };
        if (!s.noprint) render(cx, &body, s, surface, group.rows[0]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return gap(cx, s.line, "statistics too large for the fixed-decimal listing are not implemented (STAT-RSREG-007)", .{}),
        };
    }
    try out.appendSlice(a, body.items);
}

fn testLib(a: A) !*@import("../exec.zig").Library {
    const lib = try a.create(@import("../exec.zig").Library);
    lib.* = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "s");
    for ([_][]const u8{ "y", "x1", "x2", "g", "w" }) |nm| _ = try ds.addColumn(nm, .num);
    const y = [_]f64{ 5, 9, 8, 2, 6, 7, 4, 3, 9, 6 };
    const x1 = [_]f64{ -1, -1, 1, 1, 0, 0, 0, 1, -1, 0 };
    const x2 = [_]f64{ -1, 1, -1, 1, 0, 0, 1, 0, 0, -1 };
    for (0..10) |i| try ds.appendRow(&.{ .{ .num = y[i] }, .{ .num = x1[i] }, .{ .num = x2[i] }, .{ .num = if (i < 5) 2 else 1 }, .{ .num = 0 } });
    try lib.put("s", ds);
    // Two complete copies with BY value 2 then 1 (out of ascending order).
    const two = try a.create(Dataset);
    two.* = Dataset.init(a, "s2");
    for ([_][]const u8{ "y", "x1", "x2", "g" }) |nm| _ = try two.addColumn(nm, .num);
    for ([_]f64{ 2, 1 }) |g| for (0..10) |i| try two.appendRow(&.{ .{ .num = y[i] }, .{ .num = x1[i] }, .{ .num = x2[i] }, .{ .num = g } });
    try lib.put("s2", two);
    return lib;
}

fn expectRun(a: A, lib: *@import("../exec.zig").Library, src: []const u8, gap_expected: bool, message: []const u8) !void {
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    const toks = try lex.tokenize(a, src, &d);
    if (run(cx, &sink, toks)) |_| return error.TestUnexpectedResult else |_| {}
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(gap_expected, diag.gapHit());
    const text = try d.render();
    if (std.mem.indexOf(u8, text, message) == null) {
        std.debug.print("missing '{s}' in:\n{s}\n", .{ message, text });
        return error.TestUnexpectedResult;
    }
}

test "STAT-RSREG-001 documented invalid inputs fail with SAS messages (rc 1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a);
    try expectRun(a, lib, "proc rsreg data=s; run;", false, "No MODEL statement.");
    try expectRun(a, lib, "proc rsreg data=s; model y = nosuch; run;", false, "not found");
    try expectRun(a, lib, "proc rsreg data=nosuch; model y = x1 x2; run;", false, "does not exist");
    try expectRun(a, lib, "proc rsreg data=s bogus=1; model y = x1 x2; run;", false, "invalid statement or token");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2 / bogus; run;", false, "invalid statement or token");
    try expectRun(a, lib, "proc rsreg data=s; model y x1; run;", false, "responses = independents");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x1; run;", false, "listed more than once");
    try expectRun(a, lib, "proc rsreg data=s; model y = y x1; run;", false, "both a response");
    // WEIGHT all zero: no usable observation (SAS wording from a reference run).
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2; weight w; run;", false, "No non-missing observations to process.");
    // BY g is 2 then 1: the first group prints, then the sort ERROR.
    try expectRun(a, lib, "proc rsreg data=s2; by g; model y = x1 x2; run;", false, "is not sorted in ascending sequence");
}

test "STAT-RSREG-001 valid but unimplemented features are loud gaps (rc 2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a);
    try expectRun(a, lib, "proc rsreg data=s out=o; model y = x1 x2; run;", true, "OUT=");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2; ridge max; run;", true, "RIDGE");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2 / covar=1; run;", true, "COVAR=");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2 / press; run;", true, "press");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2 / predict; run;", true, "predict");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2 / nocode; run;", true, "nocode");
    try expectRun(a, lib, "proc rsreg data=s; model y g = x1 x2; run;", true, "several response");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2; model y = x2 x1; run;", true, "multiple MODEL");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2; weight g; weight w; run;", true, "more than one WEIGHT");
    try expectRun(a, lib, "proc rsreg data=s; model y = x1 x2; weight x1; run;", true, "WEIGHT variable that is also");
    // BY on a factor leaves it constant within a group: zero coding range.
    try expectRun(a, lib, "proc rsreg data=s; by x1 notsorted; model y = x1 x2; run;", true, "zero coding range");
}

test "STAT-RSREG-001 surface fit: coded/uncoded estimates and canonical analysis by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testLib(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc rsreg data=s; model y = x1 x2; id g; by x2; by g; run;", &d));
    // p.8874: only the last BY statement is used.
    try std.testing.expectEqual(@as(usize, 1), s.by_cols.len);
    try std.testing.expectEqual(@as(usize, 3), s.by_cols[0]);
    try std.testing.expectEqual(@as(usize, 3), s.ids[0]);
    const ds = lib.find("s").?;
    const f = try fitSurface(a, s, ds, ds.rows.items);
    // Factors already span -1..1, so coding is identity and coded == uncoded.
    try std.testing.expectEqual(@as(f64, 0), f.center[0]);
    try std.testing.expectEqual(@as(f64, 1), f.scale[1]);
    for (f.estimate, f.coded) |e, c| try std.testing.expectApproxEqAbs(e, c, 1e-10);
    // Stationary point solves A x = -b/2 (A = [[q11, c/2],[c/2, q22]]).
    const b1 = f.coded[1];
    const b2 = f.coded[2];
    const q11 = f.coded[3];
    const c12 = f.coded[4] / 2;
    const q22 = f.coded[5];
    try std.testing.expectApproxEqAbs(-b1 / 2, q11 * f.critical_coded[0] + c12 * f.critical_coded[1], 1e-10);
    try std.testing.expectApproxEqAbs(-b2 / 2, c12 * f.critical_coded[0] + q22 * f.critical_coded[1], 1e-10);
    // Eigenvalues of the 2x2 symmetric A: trace and determinant identities.
    try std.testing.expectApproxEqAbs(q11 + q22, f.eigen.values[0] + f.eigen.values[1], 1e-10);
    try std.testing.expectApproxEqAbs(q11 * q22 - c12 * c12, f.eigen.values[0] * f.eigen.values[1], 1e-10);
    // Reference-run values for this design (saddle point).
    try std.testing.expectApproxEqAbs(@as(f64, 1.203434), f.eigen.values[0], 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 6.231966), f.stationary, 5e-7);
    // Type I pieces add to the model SS; factor tests have 3 DF each.
    try std.testing.expectApproxEqAbs(f.type1_ss[3], f.type1_ss[0] + f.type1_ss[1] + f.type1_ss[2], 1e-9);
    try std.testing.expectEqual(@as(usize, 3), f.factor_df[0]);
}
