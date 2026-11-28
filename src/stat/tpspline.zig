//! PROC TPSPLINE statements, roles and the default GCV path, SAS/STAT 15.4
//! Chapter 125 (PROC TPSPLINE statement pp.10298-10302, BY pp.10302-10303,
//! FREQ p.10303, ID p.10303, MODEL pp.10303-10306, OUTPUT pp.10306-10307,
//! Computational Formulas pp.10308-10312). The fit is the penalized
//! thin-plate smoothing spline of Wahba: with X = (1 x) = (Q1 Q2)(R;0) and
//! B = Q2'KQ2 = U diag(l) U', I - A(lambda) = n lambda Q2 U diag(1/(l+n lambda)) U'Q2',
//! so the GCV function, residuals, trace and hat diagonal are closed-form in
//! the eigen-decomposition of B. What has not been proven against a SAS
//! reference run (regression variables, d != 2, M= other than 2, LAMBDA0=,
//! LOGNLAMBDA0=, DF=, DISTANCE>0, RANGE=, LAMBDA= lists, several dependent
//! variables, SCORE, the COEF output keyword, PLOTS=) is a
//! D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const functions = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const pc = @import("princomp.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    dep: usize = 0,
    smooth: []const usize = &.{},
    lognl: []const f64 = &.{},
    alpha: f64 = 0.05,
    m: usize = 2,
    out: ?[]const u8 = null,
    pred: bool = false,
    std: bool = false,
    resid: bool = false,
    lclm: bool = false,
    uclm: bool = false,
    adiag: bool = false,
    freq: ?usize = null,
    ids: []const usize = &.{},
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC TPSPLINE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC TPSPLINE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC TPSPLINE: " ++ text, args);
}

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

/// A signed numeric literal.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * v;
}

fn startsNumber(t: []const lex.Token, i: usize) bool {
    return at(t, i, .number) or ((at(t, i, .minus) or at(t, i, .plus)) and at(t, i + 1, .number));
}

/// A list of values: numbers separated by blanks or commas and `start TO stop
/// <BY increment>` items, enclosed in parentheses (SAS 15.4 reference run:
/// `LOGNL=-2` is "ERROR 79-322: Expecting a (.").
pub fn valueList(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const f64 {
    const a = cx.arena;
    if (!at(t, i.*, .lparen)) return user(cx, lineOf(t, i.*), "expecting a ( to start the list of values", .{});
    i.* += 1;
    var vals: std.ArrayList(f64) = .empty;
    while (startsNumber(t, i.*)) {
        const start = try number(cx, t, i);
        if (kw(t, i.*, "to")) {
            i.* += 1;
            const stop = try number(cx, t, i);
            var inc: f64 = 1;
            if (kw(t, i.*, "by")) {
                i.* += 1;
                inc = try number(cx, t, i);
            }
            if (!(inc > 0) or stop < start) return gap(cx, lineOf(t, i.*), "a TO list that is decreasing or has a non-positive BY increment is not verified", .{});
            var k: f64 = 0;
            while (start + k * inc <= stop + 1e-9 * @abs(inc)) : (k += 1) try vals.append(a, start + k * inc);
        } else try vals.append(a, start);
        if (at(t, i.*, .comma)) i.* += 1;
    }
    if (!at(t, i.*, .rparen)) return invalid(cx, t, i.*);
    i.* += 1;
    if (vals.items.len == 0) return invalid(cx, t, i.*);
    return vals.items;
}

fn column(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, t[i].text)});
}

fn numeric(cx: proc.ProcCtx, ds: *Dataset, c: usize, line: usize, role: []const u8) diag.Error!void {
    if (ds.columns.items[c].type != .num) return user(cx, line, "{s} variable {s} must be numeric", .{ role, ds.columns.items[c].name });
}

fn parseModel(cx: proc.ProcCtx, s: *Spec, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    const a = cx.arena;
    const line = t[start].line;
    var i = start + 1;
    var deps: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .eq)) : (i += 1) {
        const c = try column(cx, s.ds, t, i);
        try numeric(cx, s.ds, c, line, "Dependent");
        try deps.append(a, c);
    }
    if (deps.items.len == 0 or !at(t, i, .eq)) return user(cx, line, "the MODEL statement needs dependent-variables = (smoothing-variables)", .{});
    i += 1;
    var smooth: std.ArrayList(usize) = .empty;
    var regression = false;
    while (i < end and !at(t, i, .slash)) {
        if (at(t, i, .lparen)) {
            if (smooth.items.len > 0) return gap(cx, line, "more than one smoothing-variable list is not verified", .{});
            i += 1;
            while (i < end and !at(t, i, .rparen)) : (i += 1) {
                const c = try column(cx, s.ds, t, i);
                try numeric(cx, s.ds, c, line, "Smoothing");
                for (smooth.items) |p| if (p == c) return user(cx, line, "smoothing variable {s} is listed more than once", .{s.ds.columns.items[c].name});
                try smooth.append(a, c);
            }
            if (!at(t, i, .rparen)) return invalid(cx, t, i);
            i += 1;
        } else if (at(t, i, .name)) {
            // "At least one smoothing variable is required, and it must be
            // listed after the regression variables" (p.10303).
            if (smooth.items.len > 0) return user(cx, line, "regression variables must be listed before the smoothing variables", .{});
            _ = try column(cx, s.ds, t, i);
            regression = true;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (smooth.items.len == 0) return user(cx, line, "at least one smoothing variable, in parentheses, is required", .{});
    var lognl_given = false;
    if (at(t, i, .slash)) {
        i += 1;
        while (i < end) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            const w = t[i].text;
            if (!at(t, i + 1, .eq)) return invalid(cx, t, i);
            i += 2;
            if (eq(w, "lognlambda") or eq(w, "lognl")) {
                s.lognl = try valueList(cx, t, &i);
                lognl_given = true;
            } else if (eq(w, "lambda")) {
                const vals = try valueList(cx, t, &i);
                for (vals) |v| if (!(v > 0)) return user(cx, line, "all LAMBDA= values must be positive", .{});
                // LOGNL= takes precedence over LAMBDA= (p.10305).
                if (!lognl_given) return gap(cx, line, "the GCV table for a LAMBDA= list is not verified (STAT-TPSPLINE-003); use LOGNLAMBDA=", .{});
            } else if (eq(w, "alpha")) {
                const v = try number(cx, t, &i);
                if (!(v > 0 and v < 1)) return user(cx, line, "ALPHA= must be between 0 and 1", .{});
                s.alpha = v;
            } else if (eq(w, "m")) {
                const v = try number(cx, t, &i);
                if (!(v >= 1) or v != @floor(v)) return user(cx, line, "M= must be a positive integer", .{});
                if (v != 2) return gap(cx, line, "M={d} is not implemented (STAT-TPSPLINE-004); only M=2 is", .{v});
            } else if (eq(w, "distance") or eq(w, "d")) {
                const v = try number(cx, t, &i);
                if (v < 0) return user(cx, line, "DISTANCE= must be nonnegative", .{});
                if (v > 0) return gap(cx, line, "DISTANCE= greater than 0 is not implemented (STAT-TPSPLINE-003)", .{});
            } else if (eq(w, "lambda0") or eq(w, "lognlambda0") or eq(w, "lognl0") or eq(w, "df") or eq(w, "range")) {
                return gap(cx, line, "the {s}= option is not implemented (STAT-TPSPLINE-003)", .{try std.ascii.allocUpperString(a, w)});
            } else return invalid(cx, t, i - 2);
        }
    }
    if (regression) return gap(cx, line, "regression variables (semiparametric models) are not implemented (STAT-TPSPLINE-003)", .{});
    for (deps.items) |d| for (smooth.items) |c| if (c == d) return user(cx, line, "variable {s} is both a dependent and a smoothing variable", .{s.ds.columns.items[c].name});
    if (deps.items.len > 1) return gap(cx, line, "more than one dependent variable is not verified (STAT-TPSPLINE-003)", .{});
    if (smooth.items.len != 2) return gap(cx, line, "{d} smoothing variables are not verified; only two are", .{smooth.items.len});
    s.dep = deps.items[0];
    s.smooth = smooth.items;
}

fn parseOutput(cx: proc.ProcCtx, s: *Spec, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    const a = cx.arena;
    const line = t[start].line;
    var i = start + 1;
    var any = false;
    while (i < end) {
        if (kw(t, i, "out") and at(t, i + 1, .eq)) {
            i += 2;
            s.out = try dsName(a, cx, t, &i);
            if (at(t, i, .lparen)) return gap(cx, line, "data set options on OUT= are not implemented", .{});
        } else if (kw(t, i, "pred")) {
            s.pred = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "std")) {
            s.std = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "resid") or kw(t, i, "r")) {
            s.resid = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "adiag")) {
            s.adiag = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "lclm")) {
            s.lclm = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "uclm")) {
            s.uclm = true;
            any = true;
            i += 1;
        } else if (kw(t, i, "coef")) {
            return gap(cx, line, "the OUTPUT keyword {s} is not implemented (STAT-TPSPLINE-006)", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
    }
    if (s.out == null) return user(cx, line, "OUT= is required in the OUTPUT statement", .{});
    // "If no keyword is present, the data set contains only the original data
    // set and predicted values" (p.10306).
    if (!any) s.pred = true;
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
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return user(cx, t[i].line, "DATA= is specified more than once", .{});
            i += 2;
            data = try dsName(a, cx, t, &i);
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
        } else if (eq(word, "plots") or eq(word, "plot")) {
            // PLOTS=NONE suppresses plots; plot requests need ODS Graphics
            // (STAT-TPSPLINE-008).
            if (at(t, i + 1, .eq) and kw(t, i + 2, "none")) {
                i += 3;
            } else return gap(cx, t[i].line, "PLOTS= requests are not implemented (STAT-TPSPLINE-008)", .{});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = if (data) |name|
        cx.lib.find(name) orelse return user(cx, l0, "input data set {s} not found", .{name})
    else
        proc.lastDataset(cx.lib) orelse return user(cx, l0, "there is no default input data set (_LAST_ is _NULL_)", .{});
    s.ds = try proc.procInput(a, raw, t, cx.diags);

    var bys: by.Statements = .{};
    var by_seen = false;
    var model_seen = false;
    var output_seen = false;
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
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "more than one MODEL statement is not verified", .{});
            model_seen = true;
            try parseModel(cx, &s, t, i, end);
        } else if (kw(t, i, "output")) {
            if (output_seen) return gap(cx, t[i].line, "more than one OUTPUT statement is not verified", .{});
            output_seen = true;
            try parseOutput(cx, &s, t, i, end);
        } else if (kw(t, i, "freq")) {
            if (end != i + 2) return user(cx, t[i].line, "the FREQ statement takes exactly one variable", .{});
            if (s.freq != null) return gap(cx, t[i].line, "more than one FREQ statement is not verified", .{});
            const c = try column(cx, s.ds, t, i + 1);
            try numeric(cx, s.ds, c, t[i].line, "FREQ");
            s.freq = c;
        } else if (kw(t, i, "id")) {
            // "more than one ID statement can be used"; the values only label
            // plot tooltips (p.10303).
            if (end == i + 1) return invalid(cx, t, end);
            var j = i + 1;
            while (j < end) {
                const line = t[j].line;
                const names = try lists.next(a, s.ds, t[0..end], &j, cx.diags);
                for (names) |n| {
                    const c = s.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                    try ids.append(a, c);
                }
            }
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.10302).
            by_seen = true;
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "score")) {
            return gap(cx, t[i].line, "the SCORE statement is not implemented (STAT-TPSPLINE-005)", .{});
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where")) {
            // Step boundaries; WHERE is applied by procInput.
        } else if (kw(t, i, "weight") or kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib")) {
            return gap(cx, t[i].line, "the {s} statement is not implemented", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return user(cx, l0, "a MODEL statement is required", .{});
    s.ids = ids.items;
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    return s;
}

/// Thin-plate kernel E2(s) = ||s||^2 log||s|| / (2^3 pi) for d = 2 (p.10309).
fn kernel(r: f64) f64 {
    if (r == 0) return 0;
    return r * r * @log(r) / (8 * std.math.pi);
}

/// The lambda-independent part of the fit.
pub const Basis = struct {
    n: usize,
    k: usize,
    /// W = Q2 U, n*k row-major.
    w: []f64,
    lam: []f64,
    /// z = W'y.
    z: []f64,
};

pub const Stats = struct { gcv: f64, rss: f64, tr: f64, penalty: f64 };

/// Householder QR of X = (1 x) (n*(d+1)); returns Q2 (n*(n-p)), an
/// orthonormal basis of the null space of X'.
fn nullBasis(a: A, x: []const f64, n: usize, d: usize) ![]f64 {
    const p = d + 1;
    const r = try a.alloc(f64, n * p);
    for (0..n) |i| {
        r[i * p] = 1;
        for (0..d) |j| r[i * p + 1 + j] = x[i * d + j];
    }
    const q = try a.alloc(f64, n * n);
    @memset(q, 0);
    for (0..n) |i| q[i * n + i] = 1;
    const v = try a.alloc(f64, n);
    for (0..p) |j| {
        var norm: f64 = 0;
        for (j..n) |i| norm += r[i * p + j] * r[i * p + j];
        norm = @sqrt(norm);
        if (norm == 0) continue;
        const alpha = if (r[j * p + j] > 0) -norm else norm;
        @memset(v, 0);
        for (j..n) |i| v[i] = r[i * p + j];
        v[j] -= alpha;
        var vv: f64 = 0;
        for (j..n) |i| vv += v[i] * v[i];
        if (vv == 0) continue;
        for (0..p) |c| {
            var dot: f64 = 0;
            for (j..n) |i| dot += v[i] * r[i * p + c];
            const f = 2 * dot / vv;
            for (j..n) |i| r[i * p + c] -= f * v[i];
        }
        // Q <- Q H.
        for (0..n) |row| {
            var dot: f64 = 0;
            for (j..n) |i| dot += q[row * n + i] * v[i];
            const f = 2 * dot / vv;
            for (j..n) |i| q[row * n + i] -= f * v[i];
        }
    }
    const k = n - p;
    const q2 = try a.alloc(f64, n * k);
    for (0..n) |i| for (0..k) |c| {
        q2[i * k + c] = q[i * n + p + c];
    };
    return q2;
}

/// x: n*d smoothing coordinates, y: n responses.
pub fn basis(a: A, x: []const f64, y: []const f64, d: usize) !Basis {
    const n = y.len;
    const p = d + 1;
    const k = n - p;
    const q2 = try nullBasis(a, x, n, d);
    const kq = try a.alloc(f64, n * k);
    const krow = try a.alloc(f64, n);
    for (0..n) |i| {
        for (0..n) |j| {
            var ss: f64 = 0;
            for (0..d) |l| {
                const diff = x[i * d + l] - x[j * d + l];
                ss += diff * diff;
            }
            krow[j] = kernel(@sqrt(ss));
        }
        for (0..k) |c| {
            var acc: f64 = 0;
            for (0..n) |j| acc += krow[j] * q2[j * k + c];
            kq[i * k + c] = acc;
        }
    }
    const b = try a.alloc(f64, k * k);
    for (0..k) |r| for (0..k) |c| {
        var acc: f64 = 0;
        for (0..n) |i| acc += q2[i * k + r] * kq[i * k + c];
        b[r * k + c] = acc;
    };
    for (0..k) |r| for (0..r) |c| {
        const avg = 0.5 * (b[r * k + c] + b[c * k + r]);
        b[r * k + c] = avg;
        b[c * k + r] = avg;
    };
    const e = try pc.eigenSym(a, b, k);
    const w = try a.alloc(f64, n * k);
    for (0..n) |i| for (0..k) |c| {
        var acc: f64 = 0;
        for (0..k) |r| acc += q2[i * k + r] * e.vectors[r * k + c];
        w[i * k + c] = acc;
    };
    const lam = try a.alloc(f64, k);
    const z = try a.alloc(f64, k);
    for (0..k) |c| {
        // B is positive semidefinite; rounding can leave tiny negatives.
        lam[c] = @max(e.values[c], 0);
        var acc: f64 = 0;
        for (0..n) |i| acc += w[i * k + c] * y[i];
        z[c] = acc;
    }
    return .{ .n = n, .k = k, .w = w, .lam = lam, .z = z };
}

/// GCV(lambda) = (1/n)||(I-A)y||^2 / [(1/n)tr(I-A)]^2 at log10(n lambda) = l
/// (p.10311); the penalty is delta'K delta.
pub fn stats(b: Basis, l: f64) Stats {
    const nl = std.math.pow(f64, 10, l);
    var tr: f64 = 0;
    var rss: f64 = 0;
    var pen: f64 = 0;
    for (b.lam, b.z) |lk, zk| {
        const wk = nl / (lk + nl);
        tr += wk;
        rss += wk * wk * zk * zk;
        pen += lk * zk * zk / ((lk + nl) * (lk + nl));
    }
    const nf: f64 = @floatFromInt(b.n);
    return .{ .gcv = nf * rss / (tr * tr), .rss = rss, .tr = tr, .penalty = pen };
}

/// The GCV minimizer on the log10(n lambda) scale: a grid over [-10, 5]
/// followed by golden-section refinement of the best bracket.
pub fn minimize(b: Basis) f64 {
    const lo: f64 = -10;
    const step: f64 = 0.05;
    const steps: usize = 300;
    var best: usize = 0;
    var best_v = std.math.inf(f64);
    for (0..steps + 1) |s| {
        const v = stats(b, lo + step * @as(f64, @floatFromInt(s))).gcv;
        if (v < best_v) {
            best_v = v;
            best = s;
        }
    }
    var x0 = lo + step * @as(f64, @floatFromInt(if (best == 0) 0 else best - 1));
    var x1 = lo + step * @as(f64, @floatFromInt(@min(best + 1, steps)));
    const g: f64 = (@sqrt(@as(f64, 5.0)) - 1) / 2;
    var c = x1 - g * (x1 - x0);
    var d = x0 + g * (x1 - x0);
    var fc = stats(b, c).gcv;
    var fd = stats(b, d).gcv;
    while (x1 - x0 > 1e-10) {
        if (fc < fd) {
            x1 = d;
            d = c;
            fd = fc;
            c = x1 - g * (x1 - x0);
            fc = stats(b, c).gcv;
        } else {
            x0 = c;
            c = d;
            fc = fd;
            d = x0 + g * (x1 - x0);
            fd = stats(b, d).gcv;
        }
    }
    return 0.5 * (x0 + x1);
}

/// Fitted values and hat diagonal at log10(n lambda) = l.
pub fn fitted(a: A, b: Basis, y: []const f64, l: f64) !struct { f: []f64, adiag: []f64 } {
    const nl = std.math.pow(f64, 10, l);
    const f = try a.alloc(f64, b.n);
    const ad = try a.alloc(f64, b.n);
    for (0..b.n) |i| {
        var res: f64 = 0;
        var off: f64 = 0;
        for (0..b.k) |c| {
            const wic = b.w[i * b.k + c];
            const wk = nl / (b.lam[c] + nl);
            res += wic * wk * b.z[c];
            off += wic * wic * wk;
        }
        f[i] = y[i] - res;
        ad[i] = 1 - off;
    }
    return .{ .f = f, .adiag = ad };
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => false,
    };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try pad(a, out, (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

const Row = struct { label: []const u8, value: []const u8 };

/// A two-column label/value table (SAS 15.4 reference layout).
fn table(a: A, out: *Out, titles: []const []const u8, rows: []const Row, gap_w: usize, blanks: usize) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (rows) |r| {
        lw = @max(lw, r.label.len);
        vw = @max(vw, r.value.len);
    }
    const width = lw + gap_w + vw;
    try out.appendNTimes(a, '\n', blanks);
    for (titles) |tt| try centered(a, out, tt, width);
    try out.append(a, '\n');
    for (rows) |r| {
        try out.appendSlice(a, r.label);
        try pad(a, out, width - r.label.len - r.value.len);
        try out.appendSlice(a, r.value);
        try out.append(a, '\n');
    }
}

pub const OutVar = struct { name: []const u8, label: []const u8 };

/// OUTPUT variables: SAS 15.4 reference run order P_, StD_, R_, LCLM_,
/// UCLM_, Adiag_ whatever the keyword order, with these labels.
pub fn outputVars(a: A, s: Spec, dname: []const u8) ![]const OutVar {
    const pct = try std.fmt.allocPrint(a, "{d}", .{@round(1e6 * 100 * (1 - s.alpha)) / 1e6});
    var vars: std.ArrayList(OutVar) = .empty;
    for ([_]struct { on: bool, prefix: []const u8, label: []const u8 }{
        .{ .on = s.pred, .prefix = "P_", .label = "Predicted Value of " },
        .{ .on = s.std, .prefix = "StD_", .label = "Standard Deviation of " },
        .{ .on = s.resid, .prefix = "R_", .label = "Residual of " },
        .{ .on = s.lclm, .prefix = "LCLM_", .label = try std.fmt.allocPrint(a, "Lower {s}% Confidence Limit for Mean of ", .{pct}) },
        .{ .on = s.uclm, .prefix = "UCLM_", .label = try std.fmt.allocPrint(a, "Upper {s}% Confidence Limit for Mean of ", .{pct}) },
        .{ .on = s.adiag, .prefix = "Adiag_", .label = "Diagonal Elements of Matrix A for " },
    }) |kwd| if (kwd.on) try vars.append(a, .{
        .name = try std.fmt.allocPrint(a, "{s}{s}", .{ kwd.prefix, dname }),
        .label = try std.fmt.allocPrint(a, "{s}{s}", .{ kwd.label, dname }),
    });
    return vars.items;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (s.ds.rows.items.len == 0) return gap(cx, 0, "an input data set with no observations is not verified", .{});
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const cols = s.ds.columns.items;
    const dname = cols[s.dep].name;
    const d = s.smooth.len;
    const z = functions.distQuantile(.normal, 1 - s.alpha / 2, &.{}).?;

    var o: ?*Dataset = null;
    if (s.out) |member| {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, member);
        for (cols) |c| _ = try ds.addColumnLike(c.name, c);
        for (try outputVars(a, s, dname)) |ov| {
            if (ds.indexOf(ov.name) != null) return gap(cx, 0, "output variable {s} collides with an input variable; the rule is not verified", .{ov.name});
            _ = try ds.addColumn(ov.name, .num);
            ds.setLabel(ov.name, ov.label);
        }
        o = ds;
    }

    // Validate every group before any listing text.
    var truncated = false;
    const Group = struct { keep: []usize, x: []f64, y: []f64, owner: []usize, missing: usize, unique: usize };
    const groups = try a.alloc(Group, slices.len);
    for (slices, groups) |slice, *g| {
        var keep: std.ArrayList(usize) = .empty;
        var miss: usize = 0;
        for (slice.rows, 0..) |row, r| {
            var bad = isMissing(row[s.dep]);
            for (s.smooth) |c| if (isMissing(row[c])) {
                bad = true;
            };
            if (s.freq) |fc| {
                const fv = row[fc].num;
                if (std.math.isNan(fv) or fv < 1) return gap(cx, 0, "a missing or less-than-one FREQ value is not verified", .{});
                if (fv != @floor(fv)) truncated = true;
            }
            if (bad) miss += 1 else try keep.append(a, r);
        }
        if (miss > 0 and o != null) return gap(cx, 0, "OUTPUT values for observations with missing values are not verified", .{});
        // FREQ: "treats the data as if each observation appears n times"
        // (p.10303); only the integer portion is used.
        var xs: std.ArrayList(f64) = .empty;
        var ys: std.ArrayList(f64) = .empty;
        var owner: std.ArrayList(usize) = .empty;
        for (keep.items, 0..) |r, k| {
            const row = slice.rows[r];
            const times: usize = if (s.freq) |fc| @intFromFloat(@floor(row[fc].num)) else 1;
            for (0..times) |_| {
                for (s.smooth) |c| try xs.append(a, row[c].num);
                try ys.append(a, row[s.dep].num);
                try owner.append(a, k);
            }
        }
        var unique: usize = 0;
        for (keep.items, 0..) |r, k| {
            var seen = false;
            for (keep.items[0..k]) |q| {
                var same = true;
                for (s.smooth) |c| if (slice.rows[q][c].num != slice.rows[r][c].num) {
                    same = false;
                };
                if (same) {
                    seen = true;
                    break;
                }
            }
            if (!seen) unique += 1;
        }
        // The polynomial space has dimension d+1; the spline needs more
        // unique design points than that.
        if (unique <= d + 1) return gap(cx, 0, "fewer than {d} unique smoothing design points is not verified", .{d + 2});
        g.* = .{ .keep = keep.items, .x = xs.items, .y = ys.items, .owner = owner.items, .missing = miss, .unique = unique };
    }

    if (truncated) try cx.diags.note(0, "At least one frequency has been truncated because of a non-integer value.", .{});
    for (slices, groups) |slice, g| {
        const b = try basis(a, g.x, g.y, d);
        const lfin = minimize(b);
        const st = stats(b, lfin);
        const fit = try fitted(a, b, g.y, lfin);
        const sigma = @sqrt(st.rss / st.tr);

        try pageStart(cx, out);
        try byLine(a, out, s, slice);
        try out.print(a, "\nThe TPSPLINE Procedure\nDependent Variable:  {s}\n", .{dname});
        if (s.freq) |fc| try out.print(a, "Frequency Variable:  {s}\n", .{cols[fc].name});
        try table(a, out, &.{"Summary of Input Data Set"}, &.{
            .{ .label = "Number of Non-Missing Observations", .value = try std.fmt.allocPrint(a, "{d}", .{g.y.len}) },
            .{ .label = "Number of Missing Observations", .value = try std.fmt.allocPrint(a, "{d}", .{g.missing}) },
            .{ .label = "Unique Smoothing Design Points", .value = try std.fmt.allocPrint(a, "{d}", .{g.unique}) },
        }, 4, 1);
        try table(a, out, &.{"Summary of Final Model"}, &.{
            .{ .label = "Number of Regression Variables", .value = "0" },
            .{ .label = "Number of Smoothing Variables", .value = try std.fmt.allocPrint(a, "{d}", .{d}) },
            .{ .label = "Order of Derivative in the Penalty", .value = try std.fmt.allocPrint(a, "{d}", .{s.m}) },
            .{ .label = "Dimension of Polynomial Space", .value = try std.fmt.allocPrint(a, "{d}", .{d + 1}) },
        }, 4, 2);
        if (s.lognl.len > 0) {
            var bi: usize = 0;
            const vals = try a.alloc(f64, s.lognl.len);
            for (s.lognl, vals, 0..) |l, *v, k| {
                v.* = stats(b, l).gcv;
                if (v.* < vals[bi]) bi = k;
            }
            try out.appendSlice(a, "\n\n          GCV Function\n \nlog10(n*Lambda)             GCV\n\n");
            for (s.lognl, vals, 0..) |l, v, k| {
                const lt = try std.fmt.allocPrint(a, "{d:.6}", .{l});
                const vt = try std.fmt.allocPrint(a, "{d:.6}", .{v});
                try pad(a, out, 15 -| lt.len);
                try out.appendSlice(a, lt);
                try pad(a, out, 16 -| vt.len);
                try out.appendSlice(a, vt);
                try out.appendSlice(a, if (k == bi) "*\n" else " \n");
            }
            try out.appendSlice(a, "\nNote: * indicates minimum GCV value.\n");
        }
        const f4 = struct {
            fn f(al: A, v: f64) ![]const u8 {
                return std.fmt.allocPrint(al, "{d:.4}", .{v});
            }
        }.f;
        const nf: f64 = @floatFromInt(g.y.len);
        try table(a, out, &.{ "Summary Statistics", "of Final Estimation" }, &.{
            .{ .label = "log10(n*Lambda)", .value = try f4(a, lfin) },
            .{ .label = "Smoothing Penalty", .value = try f4(a, st.penalty) },
            .{ .label = "Residual SS", .value = try f4(a, st.rss) },
            .{ .label = "Tr(I-A)", .value = try f4(a, st.tr) },
            .{ .label = "Model DF", .value = try f4(a, nf - st.tr) },
            .{ .label = "Standard Deviation", .value = try f4(a, sigma) },
            .{ .label = "GCV", .value = try f4(a, st.gcv) },
        }, 9, 2);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);

        if (o) |ds| {
            // The first expanded copy of each kept observation carries its fit.
            const first = try a.alloc(usize, g.keep.len);
            var k: usize = g.owner.len;
            while (k > 0) {
                k -= 1;
                first[g.owner[k]] = k;
            }
            for (g.keep, 0..) |r, q| {
                const vals = try a.alloc(Value, ds.columns.items.len);
                @memcpy(vals[0..cols.len], slice.rows[r]);
                var c = cols.len;
                const e = first[q];
                const half = z * sigma * @sqrt(@max(fit.adiag[e], 0));
                const y = slice.rows[r][s.dep].num;
                for ([_]struct { on: bool, v: f64 }{
                    .{ .on = s.pred, .v = fit.f[e] },
                    .{ .on = s.std, .v = sigma * @sqrt(@max(fit.adiag[e], 0)) },
                    .{ .on = s.resid, .v = y - fit.f[e] },
                }) |item| if (item.on) {
                    vals[c] = .{ .num = item.v };
                    c += 1;
                };
                if (s.lclm) {
                    vals[c] = .{ .num = fit.f[e] - half };
                    c += 1;
                }
                if (s.uclm) {
                    vals[c] = .{ .num = fit.f[e] + half };
                    c += 1;
                }
                if (s.adiag) {
                    vals[c] = .{ .num = fit.adiag[e] };
                    c += 1;
                }
                try ds.appendRow(vals);
            }
        }
    }
    if (o) |ds| {
        const member = s.out.?;
        try cx.lib.put(member, ds);
        const upper = try std.ascii.allocUpperString(a, member);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, ds.rows.items.len, ds.columns.items.len });
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
    _ = @import("tpspline_tests.zig");
}
