//! PROC ORTHOREG statements, roles and the default listing, SAS/STAT 15.4
//! Chapter 91 (PROC ORTHOREG statement pp.7288-7289, BY pp.7289-7290, WEIGHT
//! pp.7297-7298, Missing Values p.7298). The fit is Gentleman's square-root
//! free Givens update of the triangular factor R (Overview p.7284), never the
//! normal equations: each observation is rotated into a unit upper triangular
//! R-bar with row scales D, carried in f128 so that ill-conditioned designs
//! such as the quadratic Longley model keep the digits the listing prints.
//! Everything not verified against the SAS reference is a D-009 gap (rc 2)
//! raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Order = enum { formatted, data, freq, internal };

/// One continuous MODEL effect: the product of `vars` (dataset columns, with
/// repeats, in statement order).
pub const Effect = struct { vars: []const usize, name: []const u8 };

pub const Spec = struct {
    ds: *Dataset,
    noprint: bool = false,
    singular: f64 = 1e-12,
    namelen: usize = 20,
    order: Order = .formatted,
    dependent: usize = 0,
    effects: []const Effect = &.{},
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
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC ORTHOREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC ORTHOREG: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC ORTHOREG: " ++ text, args);
}

fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.* + 1, .eq)) return invalid(cx, t, i.* + 1);
    var j = i.* + 2;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return invalid(cx, t, j);
    const x = std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j);
    i.* = j + 1;
    return sign * x;
}

fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const c = ds.indexOf(t[i].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
    if (ds.columns.items[c].type != .num) {
        if (eq(role, "effect")) return gap(cx, t[i].line, "character effect variable {s} needs CLASS, which is not implemented (owned by STAT-ORTHOREG-003)", .{t[i].text});
        return user(cx, t[i].line, "{s} variable {s} must be numeric", .{ role, t[i].text });
    }
    return c;
}

/// Effect label as the listing prints it: `X*X` → `X**2`, distinct
/// variables joined by `*`.
fn effectName(a: A, ds: *const Dataset, vars: []const usize) !?[]const u8 {
    const first = ds.columns.items[vars[0]].name;
    var all_same = true;
    for (vars) |v| if (v != vars[0]) {
        all_same = false;
    };
    if (all_same) return if (vars.len == 1) first else try std.fmt.allocPrint(a, "{s}**{d}", .{ first, vars.len });
    for (vars, 0..) |v, k| for (vars[0..k]) |p| if (p == v) return null;
    var out: Out = .empty;
    for (vars, 0..) |v, k| {
        if (k > 0) try out.append(a, '*');
        try out.appendSlice(a, ds.columns.items[v].name);
    }
    return out.items;
}

fn sameVars(a: A, x: []const usize, y: []const usize) !bool {
    if (x.len != y.len) return false;
    const xs = try a.dupe(usize, x);
    const ys = try a.dupe(usize, y);
    std.mem.sort(usize, xs, {}, std.sort.asc(usize));
    std.mem.sort(usize, ys, {}, std.sort.asc(usize));
    return std.mem.eql(usize, xs, ys);
}

const owned = [_]struct { []const u8, []const u8 }{
    .{ "class", "STAT-ORTHOREG-003" },       .{ "effect", "STAT-ORTHOREG-003" },
    .{ "estimate", "STAT-ORTHOREG-004" },    .{ "test", "STAT-ORTHOREG-004" },
    .{ "lsmeans", "STAT-ORTHOREG-005" },     .{ "lsmestimate", "STAT-ORTHOREG-005" },
    .{ "slice", "STAT-ORTHOREG-005" },       .{ "store", "STAT-ORTHOREG-006" },
    .{ "effectplot", "a later ORTHOREG ticket" },
};

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return invalid(cx, t, i);
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            var name = t[i + 2].text;
            i += 3;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i + 1].text });
                i += 2;
            }
            data = name;
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on DATA= are not implemented", .{});
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "singular")) {
            s.singular = try number(cx, t, &i);
            if (!(s.singular >= 0)) return user(cx, t[i - 1].line, "SINGULAR= must be nonnegative", .{});
        } else if (eq(word, "namelen")) {
            const x = try number(cx, t, &i);
            if (!(x >= 20 and x <= 2000) or x != @floor(x)) return user(cx, t[i - 1].line, "NAMELEN= must be an integer between 20 and 2000", .{});
            s.namelen = @intFromFloat(x);
        } else if (eq(word, "order") and at(t, i + 1, .eq)) {
            const m = t[i + 2 ..];
            s.order = if (kw(m, 0, "formatted")) .formatted else if (kw(m, 0, "data")) .data else if (kw(m, 0, "freq")) .freq else if (kw(m, 0, "internal")) .internal else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "outest") and at(t, i + 1, .eq)) {
            return gap(cx, t[i].line, "OUTEST= is not implemented (owned by STAT-ORTHOREG-007)", .{});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const name = data orelse return gap(cx, lineOf(t, 0), "DATA= omitted (most recently created data set) is not implemented", .{});
    const raw = cx.lib.find(name) orelse return user(cx, lineOf(t, 0), "input data set {s} not found", .{name});
    s.ds = try proc.procInput(a, raw, t[0..2], cx.diags);

    var bys: ?by.Statements = null;
    var model: ?usize = null;
    var weight_seen = false;
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
            if (model != null) return user(cx, t[i].line, "only one MODEL statement is allowed", .{});
            model = i;
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.7289).
            var fresh: by.Statements = .{};
            var j = i;
            try fresh.read(a, t, &j);
            bys = fresh;
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return user(cx, t[i].line, "only one WEIGHT statement is allowed", .{});
            weight_seen = true;
            if (end != i + 2) return invalid(cx, t, if (end == i + 1) end else i + 2);
            s.weight = try numericColumn(cx, s.ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where")) {
            // Step boundaries; WHERE is applied by procInput.
        } else {
            for (owned) |o| if (kw(t, i, o[0])) return gap(cx, t[i].line, "the {s} statement is not implemented (owned by {s})", .{ o[0], o[1] });
            return invalid(cx, t, i);
        }
        i = end + 1;
    }
    if (bys) |b| {
        const resolved = try b.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    const m = model orelse return user(cx, 0, "a MODEL statement is required", .{});
    var end = m;
    while (!at(t, end, .semicolon)) end += 1;
    var slash = end;
    for (m..end) |j| if (at(t, j, .slash)) {
        slash = j;
        break;
    };
    if (!at(t, m + 2, .eq)) return if (at(t, m + 1, .name) and at(t, m + 2, .name))
        gap(cx, t[m].line, "more than one dependent variable is not implemented", .{})
    else
        invalid(cx, t, m + 2);
    s.dependent = try numericColumn(cx, s.ds, t, m + 1, "dependent");
    var list: std.ArrayList(Effect) = .empty;
    var j = m + 3;
    while (j < slash) {
        var vars: std.ArrayList(usize) = .empty;
        try vars.append(a, try numericColumn(cx, s.ds, t, j, "effect"));
        j += 1;
        while (j < slash and at(t, j, .star)) {
            try vars.append(a, try numericColumn(cx, s.ds, t, j + 1, "effect"));
            j += 2;
        }
        if (j < slash and (at(t, j, .pipe) or at(t, j, .lparen) or at(t, j, .at)))
            return gap(cx, t[j].line, "bar, nested and @ effect notation is not implemented (owned by STAT-ORTHOREG-003)", .{});
        const label = (try effectName(a, s.ds, vars.items)) orelse
            return gap(cx, t[m].line, "effects mixing a repeated and a distinct variable are not implemented (owned by STAT-ORTHOREG-003)", .{});
        for (list.items) |prev| if (try sameVars(a, prev.vars, vars.items))
            return user(cx, t[m].line, "effect {s} appears more than once in the MODEL statement", .{label});
        try list.append(a, .{ .vars = vars.items, .name = if (label.len > s.namelen) label[0..s.namelen] else label });
    }
    s.effects = list.items;
    j = slash + 1;
    while (j < end) : (j += 1) {
        if (kw(t, j, "noint")) return gap(cx, t[j].line, "the MODEL NOINT option is not implemented (owned by STAT-ORTHOREG-003)", .{});
        return invalid(cx, t, j);
    }
    return s;
}

// ── Gentleman square-root-free Givens (AS 75 "includ") in f128 ──────────────

pub const Fit = struct {
    n: usize,
    sumw: f64,
    p: usize,
    beta: []f64,
    se: []f64,
    sse: f64,
    ssm: f64,
    df_error: usize,
};

pub const FitError = error{ OutOfMemory, Singular, NoDf };

/// `rows[o]` is the design row (intercept first), `y[o]` the response and
/// `w[o]` the positive weight. Returns estimates and standard errors.
pub fn fitGivens(a: A, rows: []const []const f64, y: []const f64, w: []const f64, singular: f64) FitError!Fit {
    const n = rows.len;
    const p = rows[0].len;
    const F = f128;
    const d = try a.alloc(F, p);
    const rbar = try a.alloc(F, p * p); // upper part only, unit diagonal implied
    const theta = try a.alloc(F, p);
    const colss = try a.alloc(F, p);
    @memset(d, 0);
    @memset(rbar, 0);
    @memset(theta, 0);
    @memset(colss, 0);
    var sserr: F = 0;
    var sumw: F = 0;
    const x = try a.alloc(F, p);
    for (rows, y, w) |row, yo, wo| {
        for (row, x) |v, *xv| xv.* = v;
        var ww: F = wo;
        var yy: F = yo;
        sumw += ww;
        for (0..p) |k| colss[k] += ww * x[k] * x[k];
        for (0..p) |i| {
            if (ww == 0) break;
            const xi = x[i];
            if (xi == 0) continue;
            const di = d[i];
            const dpi = di + ww * xi * xi;
            const cbar = di / dpi;
            const sbar = ww * xi / dpi;
            ww = cbar * ww;
            d[i] = dpi;
            for (i + 1..p) |k| {
                const xk = x[k];
                x[k] = xk - xi * rbar[i * p + k];
                rbar[i * p + k] = cbar * rbar[i * p + k] + sbar * xk;
            }
            const yk = yy;
            yy = yk - xi * theta[i];
            theta[i] = cbar * theta[i] + sbar * yk;
        }
        sserr += ww * yy * yy;
    }
    // ponytail: a column is aliased when |R_ii| / ||x_i||_w (sqrt of d_i over
    // its weighted sum of squares) is not above SINGULAR= — the quadratic
    // Longley design (ratio 3.6E-7) is full rank in the SAS reference; rank-deficient fits (DF 0 rows)
    // are STAT-ORTHOREG-002's, so they are reported as Singular here.
    for (0..p) |i| {
        if (d[i] == 0) return error.Singular;
        const rel: f64 = @floatCast(d[i] / colss[i]);
        if (!(@sqrt(rel) > singular)) return error.Singular;
    }
    if (n <= p) return error.NoDf;
    const beta = try a.alloc(F, p);
    var i = p;
    while (i > 0) {
        i -= 1;
        var v = theta[i];
        for (i + 1..p) |k| v -= rbar[i * p + k] * beta[k];
        beta[i] = v;
    }
    // (X'WX)^-1 = U^-1 D^-1 U^-T with U = R-bar (unit upper). Column k of
    // U^-1 by back substitution; var_i = sum_k (U^-1)_{ik}^2 / d_k.
    const uinv = try a.alloc(F, p * p);
    @memset(uinv, 0);
    for (0..p) |k| {
        uinv[k * p + k] = 1;
        var r = k;
        while (r > 0) {
            r -= 1;
            var v: F = 0;
            for (r + 1..k + 1) |c| v -= rbar[r * p + c] * uinv[c * p + k];
            uinv[r * p + k] = v;
        }
    }
    const df_error = n - p;
    const sse: f64 = @floatCast(sserr);
    const mse = sserr / @as(F, @floatFromInt(df_error));
    const out_beta = try a.alloc(f64, p);
    const out_se = try a.alloc(f64, p);
    for (0..p) |r| {
        var v: F = 0;
        for (r..p) |k| v += uinv[r * p + k] * uinv[r * p + k] / d[k];
        out_beta[r] = @floatCast(beta[r]);
        out_se[r] = @sqrt(@as(f64, @floatCast(v * mse)));
    }
    // Model SS about the weighted mean: everything the triangle explains
    // beyond the intercept row.
    // ponytail: SSM is accumulated in f64 from the f128 triangle, as the
    // SAS reference's Corrected Total (printed 185008826.0, not the exact
    // integer) indicates a double-precision sum of the rotated components.
    var ssm: f64 = 0;
    for (1..p) |k| {
        const dk: f64 = @floatCast(d[k]);
        const tk: f64 = @floatCast(theta[k]);
        ssm += dk * tk * tk;
    }
    return .{ .n = n, .sumw = @floatCast(sumw), .p = p, .beta = out_beta, .se = out_se, .sse = sse, .ssm = ssm, .df_error = df_error };
}

// ── BESTDw.p cells (the ORTHOREG templates: Estimate BESTD18.9, StdErr / SS /
// MS BESTD12.9). opensas has no general BESTD renderer; these two widths are
// calibrated on SAS 9.4 PUT output over magnitudes 1E-9..1E11 (both signs).
// ponytail: only the two widths the ORTHOREG templates use.

fn intDigits(ax: f64) usize {
    if (ax < 1) return 0;
    var m: usize = 1;
    var lo: f64 = 10;
    while (ax >= lo) : (lo *= 10) m += 1;
    return m;
}

fn fixed(a: A, x: f64, d: usize, m: usize) ![]const u8 {
    // At most 15 significant digits, then zero-padded to d decimals.
    const sig_room: usize = if (m >= 15) 0 else 15 - @max(m, 1);
    const keep = @min(d, if (m == 0) d else sig_room);
    if (keep == d) return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, keep });
    // Capped: SAS truncates (not rounds) at the 15th significant digit —
    // PUT(1234.5678901234567, BESTD18.9) is 1234.567890123450.
    const long = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, keep + 4 });
    const text = long[0 .. long.len - 4 - (if (keep == 0) @as(usize, 1) else 0)];
    const zeros = try a.alloc(u8, d - keep);
    @memset(zeros, '0');
    return std.mem.concat(a, u8, &.{ text, if (keep == 0) "." else "", zeros });
}

fn expo(a: A, x: f64, w: usize) ![]const u8 {
    const ax = @abs(x);
    var e: i32 = @intFromFloat(@floor(std.math.log10(ax)));
    var dec: usize = 0;
    var mant: f64 = 0;
    var tries: usize = 0;
    while (tries < 2) : (tries += 1) {
        const etxt_len: usize = 1 + (if (e < 0) @as(usize, 1) else 0) + (if (@abs(e) >= 10) @as(usize, 2) else 1);
        const used = (if (x < 0) @as(usize, 1) else 0) + 2 + etxt_len;
        dec = if (w > used) w - used else 0;
        mant = x / std.math.pow(f64, 10, @floatFromInt(e));
        const scale = std.math.pow(f64, 10, @floatFromInt(dec));
        if (@abs(@round(mant * scale) / scale) >= 10) {
            e += 1;
            continue;
        }
        break;
    }
    return std.fmt.allocPrint(a, "{d:.[1]}E{2s}{3d}", .{ mant, dec, if (e < 0) "-" else "", @abs(e) });
}

pub fn bestd(a: A, x: f64, w: usize) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    if (x == 0) return "0";
    const ax = @abs(x);
    if (x == @round(x) and ax < 1e15) return std.fmt.allocPrint(a, "{d:.0}", .{x});
    const m = intDigits(ax);
    if (w == 18) {
        if (ax < 1e-7) return expo(a, x, 18);
        if (ax < 1e-4) return fixed(a, x, 15, m);
        if (m <= 4) return fixed(a, x, 12, m);
        if (m <= 11) return fixed(a, x, 5, m);
        return expo(a, x, 18);
    }
    std.debug.assert(w == 12);
    if (ax < 1e-5) return expo(a, x, 12);
    if (m == 0) return fixed(a, x, if (x < 0 or ax >= 0.1) 9 else 10, 0);
    if (m <= 11) return fixed(a, x, if (m >= 10) 0 else 10 - m, m);
    return expo(a, x, 12);
}

// ── Listing ──────────────────────────────────────────────────────────────────

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn fmt(a: A, x: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}

fn fTail(f: f64, df1: usize, df2: usize) f64 {
    const d1: f64 = @floatFromInt(df1);
    const d2: f64 = @floatFromInt(df2);
    return proc.betai(d2 / 2, d1 / 2, d2 / (d2 + d1 * f));
}

fn tTail2(t: f64, df: usize) f64 {
    const v: f64 = @floatFromInt(df);
    return proc.betai(v / 2, 0.5, v / (v + t * t));
}

pub fn render(a: A, out: *Out, s: Spec, f: Fit) !void {
    const df_model = f.p - 1;
    const ctss = f.ssm + f.sse;
    try out.print(a, "\nThe ORTHOREG Procedure\n \nDependent Variable: {s}\n\n", .{s.ds.columns.items[s.dependent].name});
    try out.appendSlice(a, "                                   Sum of\nSource                 DF         Squares     Mean Square    F Value    Pr > F\n\n");
    const msm = f.ssm / @as(f64, @floatFromInt(df_model));
    const mse = f.sse / @as(f64, @floatFromInt(f.df_error));
    const fv = msm / mse;
    const rows = [_]struct { []const u8, usize, f64, ?f64 }{
        .{ "Model", df_model, f.ssm, msm },
        .{ "Error", f.df_error, f.sse, mse },
        .{ "Corrected Total", f.n - 1, ctss, null },
    };
    for (rows, 0..) |r, k| {
        try pad(a, out, r[0], 15, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{r[1]}), 10, false);
        try pad(a, out, try bestd(a, r[2], 12), 16, false);
        if (r[3]) |ms| try pad(a, out, try bestd(a, ms, 12), 16, false) else try out.appendNTimes(a, ' ', 16);
        if (k == 0) {
            try pad(a, out, try fmt(a, fv, "7.2"), 11, false);
            try pad(a, out, try fmt(a, fTail(fv, df_model, f.df_error), "pvalue6.4"), 10, false);
        } else try out.appendNTimes(a, ' ', 21);
        try out.append(a, '\n');
    }
    const rsq = f.ssm / ctss;
    try out.print(a, "\n\nRoot MSE    {s}\nR-Square    {s}\n\n\n", .{ try fmt(a, @sqrt(mse), "best12."), try fmt(a, rsq, "best12.") });
    var nw: usize = "Parameter".len;
    nw = @max(nw, "Intercept".len);
    for (s.effects) |e| nw = @max(nw, e.name.len);
    try out.appendNTimes(a, ' ', nw + 6 + 22 + 16 - "Standard".len);
    try out.appendSlice(a, "Standard\n");
    try pad(a, out, "Parameter", nw, true);
    try out.appendSlice(a, "    DF    Parameter Estimate           Error    t Value    Pr > |t|\n\n");
    for (0..f.p) |k| {
        try pad(a, out, if (k == 0) "Intercept" else s.effects[k - 1].name, nw, true);
        try pad(a, out, "1", 6, false);
        try pad(a, out, try bestd(a, f.beta[k], 18), 22, false);
        try pad(a, out, try bestd(a, f.se[k], 12), 16, false);
        const tv = f.beta[k] / f.se[k];
        try pad(a, out, try fmt(a, tv, "7.2"), 11, false);
        try pad(a, out, try fmt(a, tTail2(tv, f.df_error), "pvalue6.4"), 12, false);
        try out.append(a, '\n');
    }
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

const Group = struct { rows: []const []const f64, y: []const f64, w: []const f64 };

/// Missing Values (p.7298): an observation with a missing value for any model
/// variable is dropped; WEIGHT (GLM rules, Ch.53): used only when nonmissing
/// and greater than zero.
pub fn prepare(a: A, s: Spec, rows_in: []const []const Value) !Group {
    var rows: std.ArrayList([]const f64) = .empty;
    var ys: std.ArrayList(f64) = .empty;
    var ws: std.ArrayList(f64) = .empty;
    outer: for (rows_in) |row| {
        if (missing(row[s.dependent])) continue;
        for (s.effects) |e| for (e.vars) |v| if (missing(row[v])) continue :outer;
        var wt: f64 = 1;
        if (s.weight) |wc| {
            if (missing(row[wc])) continue;
            wt = row[wc].num;
            if (!(wt > 0)) continue;
        }
        const x = try a.alloc(f64, s.effects.len + 1);
        x[0] = 1;
        for (s.effects, 1..) |e, k| {
            var v: f64 = 1;
            for (e.vars) |c| v *= row[c].num;
            x[k] = v;
        }
        try rows.append(a, x);
        try ys.append(a, row[s.dependent].num);
        try ws.append(a, wt);
    }
    return .{ .rows = rows.items, .y = ys.items, .w = ws.items };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0 or s.ds.rows.items.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    if (s.effects.len == 0) return gap(cx, 0, "an intercept-only model is not implemented (owned by STAT-ORTHOREG-002)", .{});
    const fits = try a.alloc(Fit, slices.len);
    for (slices, fits) |slice, *f| {
        const g = try prepare(a, s, slice.rows);
        if (g.rows.len == 0) return gap(cx, 0, "a BY group or data set without usable observations is not implemented", .{});
        f.* = fitGivens(a, g.rows, g.y, g.w, s.singular) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Singular => return gap(cx, 0, "a rank-deficient (singular) design is not implemented (owned by STAT-ORTHOREG-002)", .{}),
            error.NoDf => return gap(cx, 0, "a fit with no error degrees of freedom is not implemented (owned by STAT-ORTHOREG-002)", .{}),
        };
    }
    if (s.noprint) return;
    for (slices, fits) |slice, f| {
        if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
        if (s.by_cols.len > 0) {
            var line: Out = .empty;
            try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
            }
        }
        try render(a, out, s, f);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    }
}

test {
    _ = @import("orthoreg_tests.zig");
}
