//! PROC PRINCOMP (SAS/STAT 15.4 ch.98): PROC statement options, VAR / BY /
//! FREQ / WEIGHT / ID / PARTIAL roles, observation selection, and the default
//! correlation-matrix analysis with its listing and OUT= scores
//! (STAT-PRINCOMP-001). Everything the cited pages define but this file does
//! not compute or has not verified against a SAS listing is a loud D-009 gap;
//! nothing is printed and no data set is created for a step that hits one.
//!
//! Listing layout and the eigenvector sign convention (each eigenvector is
//! oriented so that the sum of its elements is nonnegative) are taken from the
//! SAS listing of the chapter's crime-rates example.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const VarDef = enum { df, n, wdf, weight };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    // PROC statement (pp.7999-8004). Defaults: correlation matrix, intercept,
    // N = number of variables, PREFIX=Prin, PARPREFIX=R_, SINGULAR=1E-8,
    // VARDEF=DF, unstandardized scores.
    out: ?[]const u8 = null,
    outstat: ?[]const u8 = null,
    cov: bool = false,
    noint: bool = false,
    standard: bool = false,
    noprint: bool = false,
    plots: bool = false,
    n: ?usize = null,
    prefix: []const u8 = "Prin",
    parprefix: []const u8 = "R_",
    singular: f64 = 1e-8,
    vardef: VarDef = .df,
    // Roles.
    vars: []const usize = &.{},
    ids: []const usize = &.{},
    partial: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

/// Observations of one BY group that enter the analysis (pp.8005-8007).
pub const Selection = struct {
    /// Indices into the group's rows, in row order.
    rows: []const usize,
    /// Integer FREQ value of each used row (1 without a FREQ statement).
    freq: []const f64,
    /// WEIGHT value of each used row (1 without a WEIGHT statement).
    weight: []const f64,
    /// Sum of frequencies: the number of observations of the analysis.
    n: f64,
    /// Sum of frequency * weight.
    sum_weight: f64,
};

pub const Moments = struct {
    mean: []const f64,
    std: []const f64,
    /// Row-major p*p correlation matrix.
    corr: []const f64,
};

pub const Eigen = struct {
    /// Descending.
    values: []const f64,
    /// Row-major p*p; column k is the unit eigenvector of values[k].
    vectors: []const f64,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC PRINCOMP: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
/// `name` or `libref.name` after `OPTION=`; returns the index after it.
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
/// Canonical spelling of a PROC statement option (aliases of pp.7999-8004).
fn canonical(lower: []const u8) []const u8 {
    const pairs = [_][2][]const u8{ .{ "covariance", "cov" }, .{ "standard", "std" }, .{ "pprefix", "parprefix" }, .{ "rprefix", "parprefix" }, .{ "sing", "singular" }, .{ "plot", "plots" } };
    for (pairs) |p| if (eq(lower, p[0])) return p[1];
    return lower;
}

/// One numeric variable of a single-variable statement (FREQ, WEIGHT).
fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}
/// A variable list statement body t[i+1..end] resolved to column indices.
fn columnList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, numeric: bool, into: *std.ArrayList(usize)) diag.Error!void {
    if (end == i + 1) return invalid(cx, t, end);
    const body = t[i + 1 .. end];
    var j: usize = 0;
    while (j < body.len) {
        const l = body[j].line;
        const names = try lists.next(cx.arena, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC PRINCOMP: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC PRINCOMP: variable {s} in the {s} statement must be numeric", .{ n, role });
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
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
        const option = canonical(try std.ascii.allocLowerString(a, t[i].text));
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, t[i].line, "PROC PRINCOMP: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &s.out);
        } else if (eq(option, "outstat") and valued) {
            i = try memberName(cx, t, i + 2, &s.outstat);
        } else if (eq(option, "n") and valued) {
            // p.8000: "must be an integer greater than or equal to 0".
            s.n = (if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null) orelse
                return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: N= must be an integer greater than or equal to 0", .{});
            i += 3;
        } else if ((eq(option, "prefix") or eq(option, "parprefix")) and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: {s}= must be a name", .{t[i].text});
            if (eq(option, "prefix")) s.prefix = t[i + 2].text else s.parprefix = t[i + 2].text;
            i += 3;
        } else if (eq(option, "singular") and valued) {
            const v = if (at(t, i + 2, .number)) std.fmt.parseFloat(f64, t[i + 2].text) catch null else null;
            // p.8004: 0 < p < 1.
            if (v == null or !(v.? > 0 and v.? < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: SINGULAR= must be a number between 0 and 1", .{});
            s.singular = v.?;
            i += 3;
        } else if (eq(option, "vardef") and valued) {
            s.vardef = if (kw(t, i + 2, "df")) .df else if (kw(t, i + 2, "n")) .n else if (kw(t, i + 2, "wdf")) .wdf else if (kw(t, i + 2, "weight") or kw(t, i + 2, "wgt")) .weight else return cx.diags.fail(error.ParseError, t[i].line, "PROC PRINCOMP: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            i += 3;
        } else if (eq(option, "plots")) {
            // PLOTS=NONE suppresses all graphics (p.8002): nothing to draw.
            i += 1;
            var none = false;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
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
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "cov")) {
            s.cov = true;
            i += 1;
        } else if (eq(option, "noint")) {
            s.noint = true;
            i += 1;
        } else if (eq(option, "std")) {
            s.standard = true;
            i += 1;
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC PRINCOMP: input data set not found", .{});
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
    var vars: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var partial: std.ArrayList(usize) = .empty;
    var var_seen = false;
    var partial_seen = false;
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
            // p.8005: "If you specify more than one BY statement, only the last one specified is used."
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx.diags, t[i].line, "PROC PRINCOMP: more than one VAR statement is not verified", .{});
            var_seen = true;
            try columnList(cx, ds, t, i, end, "VAR", true, &vars);
        } else if (eq(word, "partial")) {
            if (partial_seen) return gap(cx.diags, t[i].line, "PROC PRINCOMP: more than one PARTIAL statement is not verified", .{});
            partial_seen = true;
            try columnList(cx, ds, t, i, end, "PARTIAL", true, &partial);
        } else if (eq(word, "id")) {
            try columnList(cx, ds, t, i, end, "ID", false, &ids);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC PRINCOMP: more than one FREQ statement is not verified", .{});
            s.freq = try oneNumeric(cx, ds, t, i, end, "FREQ");
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC PRINCOMP: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
        } else if (eq(word, "format")) {
            return gap(cx.diags, t[i].line, "PROC PRINCOMP: a FORMAT statement inside the step is not implemented", .{});
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
    s.ids = ids.items;
    s.partial = partial.items;
    if (!var_seen) {
        // p.8006: "If you omit the VAR statement, all numeric variables not
        // specified in other statements are analyzed."
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or has(ids.items, ci) or has(partial.items, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC PRINCOMP: no numeric variables to analyze", .{});
    return s;
}

/// Observation selection for one BY group. pp.8005-8007: an observation with
/// a missing VAR, PARTIAL, FREQ or WEIGHT value is omitted; a FREQ value less
/// than 1 omits it and only the integer portion is used; a WEIGHT value must
/// be greater than 0.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selection {
    var used: std.ArrayList(usize) = .empty;
    var freq: std.ArrayList(f64) = .empty;
    var weight: std.ArrayList(f64) = .empty;
    var n: f64 = 0;
    var sw: f64 = 0;
    rows: for (rows, 0..) |row, ri| {
        for (s.vars) |ci| if (std.math.isNan(row[ci].num)) continue :rows;
        for (s.partial) |ci| if (std.math.isNan(row[ci].num)) continue :rows;
        var f: f64 = 1;
        if (s.freq) |ci| {
            f = @floor(row[ci].num);
            if (!(f >= 1)) continue;
        }
        var w: f64 = 1;
        if (s.weight) |ci| {
            w = row[ci].num;
            if (!(w > 0)) continue;
        }
        try used.append(a, ri);
        try freq.append(a, f);
        try weight.append(a, w);
        n += f;
        sw += f * w;
    }
    return .{ .rows = used.items, .freq = freq.items, .weight = weight.items, .n = n, .sum_weight = sw };
}

/// VARDEF= divisor before partialing with an intercept (p.8004).
pub fn divisor(vardef: VarDef, sel: Selection) f64 {
    return switch (vardef) {
        .df => sel.n - 1,
        .n => sel.n,
        .weight => sel.sum_weight,
        .wdf => sel.sum_weight - 1,
    };
}

/// Weighted means, standard deviations and the correlation matrix.
/// Returns null when a variable has no variance (correlation undefined).
pub fn moments(a: A, s: Spec, rows: []const []const Value, sel: Selection) !?Moments {
    const p = s.vars.len;
    const mean = try a.alloc(f64, p);
    const sd = try a.alloc(f64, p);
    const css = try a.alloc(f64, p * p);
    @memset(mean, 0);
    @memset(css, 0);
    for (sel.rows, sel.freq, sel.weight) |ri, f, w| {
        for (s.vars, mean) |ci, *m| m.* += f * w * rows[ri][ci].num;
    }
    for (mean) |*m| m.* /= sel.sum_weight;
    for (sel.rows, sel.freq, sel.weight) |ri, f, w| {
        for (s.vars, 0..) |ci, j| {
            const dj = rows[ri][ci].num - mean[j];
            for (s.vars[0 .. j + 1], 0..) |ck, k| css[j * p + k] += f * w * dj * (rows[ri][ck].num - mean[k]);
        }
    }
    const div = divisor(s.vardef, sel);
    for (0..p) |j| {
        if (!(css[j * p + j] > 0)) return null;
        sd[j] = @sqrt(css[j * p + j] / div);
    }
    const corr = try a.alloc(f64, p * p);
    for (0..p) |j| for (0..j + 1) |k| {
        const r = if (j == k) 1.0 else css[j * p + k] / @sqrt(css[j * p + j] * css[k * p + k]);
        corr[j * p + k] = r;
        corr[k * p + j] = r;
    };
    return .{ .mean = mean, .std = sd, .corr = corr };
}

/// Cyclic Jacobi eigen-decomposition of a symmetric p*p matrix. Eigenvalues
/// descend; each eigenvector has unit length and a nonnegative element sum
/// (the orientation of the SAS listing).
pub fn eigenSym(a: A, matrix: []const f64, p: usize) !Eigen {
    const m = try a.dupe(f64, matrix);
    const v = try a.alloc(f64, p * p);
    @memset(v, 0);
    for (0..p) |j| v[j * p + j] = 1;
    var sweep: usize = 0;
    while (sweep < 100) : (sweep += 1) {
        var off: f64 = 0;
        for (0..p) |j| for (0..j) |k| {
            off += m[j * p + k] * m[j * p + k];
        };
        if (off < 1e-30) break;
        for (0..p) |q| for (0..q) |r| {
            const apq = m[r * p + q];
            if (@abs(apq) < 1e-300) continue;
            const theta = (m[q * p + q] - m[r * p + r]) / (2 * apq);
            const tt = (if (theta >= 0) @as(f64, 1) else -1) / (@abs(theta) + @sqrt(theta * theta + 1));
            const c = 1 / @sqrt(tt * tt + 1);
            const sn = tt * c;
            for (0..p) |k| {
                const mkr = m[k * p + r];
                const mkq = m[k * p + q];
                m[k * p + r] = c * mkr - sn * mkq;
                m[k * p + q] = sn * mkr + c * mkq;
            }
            for (0..p) |k| {
                const mrk = m[r * p + k];
                const mqk = m[q * p + k];
                m[r * p + k] = c * mrk - sn * mqk;
                m[q * p + k] = sn * mrk + c * mqk;
            }
            for (0..p) |k| {
                const vkr = v[k * p + r];
                const vkq = v[k * p + q];
                v[k * p + r] = c * vkr - sn * vkq;
                v[k * p + q] = sn * vkr + c * vkq;
            }
        };
    }
    const order = try a.alloc(usize, p);
    for (order, 0..) |*o, j| o.* = j;
    const Ctx = struct {
        m: []const f64,
        p: usize,
        fn gt(self: @This(), x: usize, y: usize) bool {
            return self.m[x * self.p + x] > self.m[y * self.p + y];
        }
    };
    std.mem.sort(usize, order, Ctx{ .m = m, .p = p }, Ctx.gt);
    const values = try a.alloc(f64, p);
    const vectors = try a.alloc(f64, p * p);
    for (order, 0..) |src, k| {
        values[k] = m[src * p + src];
        var sum: f64 = 0;
        for (0..p) |j| sum += v[j * p + src];
        const sign: f64 = if (sum < 0) -1 else 1;
        for (0..p) |j| vectors[j * p + k] = sign * v[j * p + src];
    }
    return .{ .values = values, .vectors = vectors };
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
/// Fixed-decimal text that fits `width`: a leading zero is dropped for
/// negative fractions ("-.629174") and decimals are reduced when the integer
/// part needs the room.
fn fixed(a: A, value: f64, width: usize, decimals: usize) ![]const u8 {
    var d = decimals;
    while (true) : (d -= 1) {
        var text: []const u8 = try std.fmt.allocPrint(a, "{d:.[1]}", .{ value, d });
        if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) text = text[1..];
        if (text.len > width and std.mem.startsWith(u8, text, "-0.")) text = try std.fmt.allocPrint(a, "-{s}", .{text[2..]});
        if (text.len <= width or d == 0) return text;
    }
}
fn title(a: A, out: *Out, text: []const u8, indent: usize) !void {
    try out.appendSlice(a, "\n\n");
    try pad(a, out, indent);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}

const Layout = struct {
    /// Correlation-matrix column header parts (upper may be empty) and width.
    upper: []const []const u8,
    lower: []const []const u8,
    width: []const usize,
    decimals: []const usize,
    label: usize,
};

/// Checks everything the verified layout depends on before anything prints.
fn layout(cx: proc.ProcCtx, l0: usize, names: []const []const u8, m: Moments, ncomp: usize, prefix: []const u8) diag.Error!Layout {
    const a = cx.arena;
    const gap = proc.failGap;
    const p = names.len;
    const upper = try a.alloc([]const u8, p);
    const lower = try a.alloc([]const u8, p);
    const width = try a.alloc(usize, p);
    const decimals = try a.alloc(usize, p);
    var label: usize = 0;
    var corr_width: usize = 0;
    for (names, 0..) |n, j| {
        label = @max(label, n.len);
        upper[j] = "";
        lower[j] = n;
        if (n.len > 6 and std.mem.indexOfScalar(u8, n, '_') != null) {
            // Verified shape: "Auto_Theft" prints as "Auto_" over "Theft".
            const u = std.mem.indexOfScalar(u8, n, '_').?;
            if (n.len <= 8 or u == 0 or u + 1 == n.len or std.mem.indexOfScalarPos(u8, n, u + 1, '_') != null)
                return gap(cx.diags, l0, "PROC PRINCOMP: the correlation matrix column header for variable {s} is not verified against SAS output (STAT-PRINCOMP-005)", .{n});
            upper[j] = n[0 .. u + 1];
            lower[j] = n[u + 1 ..];
        }
        width[j] = @max(6, @max(upper[j].len, lower[j].len)) + 6;
        corr_width += width[j];
        // Simple Statistics: Mean and StD of a variable share the decimals
        // that give the larger of the two ten significant digits.
        const big = @max(@abs(m.mean[j]), m.std[j]);
        if (!(big >= 1 and big < 1e9)) return gap(cx.diags, l0, "PROC PRINCOMP: the Simple Statistics number layout for variable {s} (magnitude below 1 or at least 1E9) is not verified against SAS output (STAT-PRINCOMP-005)", .{n});
        decimals[j] = 9 - @as(usize, @intFromFloat(@floor(@log10(big))));
    }
    // ponytail: the listing does not wrap wide tables into panels; a table
    // wider than the line size is a gap, never a silently overlong line.
    const ls: usize = if (io.global_linesize == 0) 132 else io.global_linesize;
    const widest = @max(4 + 18 * p, @max(label + corr_width, label + 14 * ncomp));
    if (widest > ls) return gap(cx.diags, l0, "PROC PRINCOMP: tables wider than the line size ({d} > {d}) are not implemented (STAT-PRINCOMP-005)", .{ widest, ls });
    if (prefix.len + 3 > 13) return gap(cx.diags, l0, "PROC PRINCOMP: the Eigenvectors header for a long PREFIX= is not verified against SAS output (STAT-PRINCOMP-005)", .{});
    return .{ .upper = upper, .lower = lower, .width = width, .decimals = decimals, .label = label };
}

fn render(a: A, out: *Out, names: []const []const u8, lay: Layout, n: usize, m: Moments, e: Eigen, prefix: []const u8) !void {
    const p = names.len;
    try out.appendSlice(a, "\nThe PRINCOMP Procedure\n\n");
    try left(a, out, "Observations", 12);
    try right(a, out, try std.fmt.allocPrint(a, "{d}", .{n}), 12);
    try out.appendSlice(a, "\n");
    try left(a, out, "Variables", 12);
    try right(a, out, try std.fmt.allocPrint(a, "{d}", .{p}), 12);
    try out.appendSlice(a, "\n");

    const simple = 4 + 18 * p;
    try title(a, out, "Simple Statistics", (simple - 17) / 2);
    try pad(a, out, 4);
    for (names) |name| try right(a, out, name, 18);
    try out.appendSlice(a, "\n\n");
    for ([_][]const u8{ "Mean", "StD" }, [_][]const f64{ m.mean, m.std }) |label, values| {
        try left(a, out, label, 4);
        for (values, lay.decimals) |v, d| try right(a, out, try std.fmt.allocPrint(a, "{d:.[1]}", .{ v, d }), 18);
        try out.appendSlice(a, "\n");
    }

    var corr_width = lay.label;
    var split = false;
    for (lay.width, lay.upper) |w, u| {
        corr_width += w;
        if (u.len > 0) split = true;
    }
    try title(a, out, "Correlation Matrix", (corr_width - 18) / 2);
    if (split) {
        var header: Out = .empty;
        try pad(a, &header, lay.label);
        for (lay.upper, lay.width) |u, w| try right(a, &header, u, w);
        try out.appendSlice(a, std.mem.trimEnd(u8, header.items, " "));
        try out.appendSlice(a, "\n");
    }
    try pad(a, out, lay.label);
    for (lay.lower, lay.width) |text, w| try right(a, out, text, w);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |name, j| {
        try left(a, out, name, lay.label);
        for (lay.width, 0..) |w, k| try right(a, out, try fixed(a, m.corr[j * p + k], 6, 4), w);
        try out.appendSlice(a, "\n");
    }

    // Verified indent of this heading over the 60-column table.
    try title(a, out, "Eigenvalues of the Correlation Matrix", 12);
    try out.appendSlice(a, "        Eigenvalue    Difference    Proportion    Cumulative\n\n");
    var total: f64 = 0;
    for (e.values) |v| total += v;
    var cumulative: f64 = 0;
    for (e.values, 0..) |v, k| {
        cumulative += v;
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 4);
        try right(a, out, try fixed(a, v, 10, 8), 14);
        try right(a, out, if (k + 1 < p) try fixed(a, v - e.values[k + 1], 10, 8) else "", 14);
        try right(a, out, try fixed(a, v / total, 6, 4), 14);
        try right(a, out, try fixed(a, cumulative / total, 6, 4), 14);
        try out.appendSlice(a, "\n");
    }

    try title(a, out, "Eigenvectors", (lay.label + 14 * p - 12) / 2);
    try pad(a, out, lay.label);
    for (0..p) |k| try right(a, out, try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, k + 1 }), 14);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |name, j| {
        try left(a, out, name, lay.label);
        for (0..p) |k| try right(a, out, try fixed(a, e.vectors[j * p + k], 8, 6), 14);
        try out.appendSlice(a, "\n");
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;

    // Boundaries owned by later PRINCOMP tickets: fail visibly, print nothing.
    if (s.plots) return gap(cx.diags, l0, "PROC PRINCOMP: PLOTS= graphs are not implemented (STAT-PRINCOMP-006)", .{});
    if (!s.noprint) if (cx.graphics) |g| if (g.enabled == true) return gap(cx.diags, l0, "PROC PRINCOMP: the default scree plot under ODS GRAPHICS is not implemented (STAT-PRINCOMP-006)", .{});
    if (s.partial.len > 0) return gap(cx.diags, l0, "PROC PRINCOMP: the PARTIAL statement is not implemented (STAT-PRINCOMP-003)", .{});
    if (s.outstat != null) return gap(cx.diags, l0, "PROC PRINCOMP: the OUTSTAT= data set is not implemented (STAT-PRINCOMP-004)", .{});
    if (s.cov) return gap(cx.diags, l0, "PROC PRINCOMP: the COV analysis and its listing are not verified against SAS output (STAT-PRINCOMP-002)", .{});
    if (s.noint) return gap(cx.diags, l0, "PROC PRINCOMP: the NOINT analysis and its listing are not verified against SAS output (STAT-PRINCOMP-002)", .{});
    if (s.freq != null or s.weight != null) return gap(cx.diags, l0, "PROC PRINCOMP: the FREQ/WEIGHT analysis and its listing are not verified against SAS output (STAT-PRINCOMP-002)", .{});
    if (s.vardef != .df) return gap(cx.diags, l0, "PROC PRINCOMP: VARDEF= other than DF is not verified against SAS output (STAT-PRINCOMP-002)", .{});
    if (s.n) |n| if (n < p) return gap(cx.diags, l0, "PROC PRINCOMP: N= fewer components than variables is not verified against SAS output (STAT-PRINCOMP-002)", .{});

    const names = try a.alloc([]const u8, p);
    for (s.vars, names) |ci, *n| n.* = ds.columns.items[ci].name;
    var created: ?*Dataset = null;
    if (s.out) |member| {
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        for (ds.columns.items) |c| _ = try o.addColumnLike(c.name, c);
        for (0..p) |k| {
            const score = try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, k + 1 });
            if (ds.indexOf(score) != null) return gap(cx.diags, l0, "PROC PRINCOMP: component name {s} already exists on the input data set; the replacement rule is not verified (STAT-PRINCOMP-004)", .{score});
            _ = try o.addColumn(score, .num);
        }
        created = o;
    }

    var body: Out = .empty;
    for (groups) |group| {
        const sel = try select(a, s, group.rows);
        if (sel.n < 2) return gap(cx.diags, l0, "PROC PRINCOMP: an analysis with fewer than two usable observations is not verified against SAS output", .{});
        const m = (try moments(a, s, group.rows, sel)) orelse return gap(cx.diags, l0, "PROC PRINCOMP: a variable with zero variance is not verified against SAS output", .{});
        const e = try eigenSym(a, m.corr, p);
        if (!s.noprint) {
            const lay = try layout(cx, l0, names, m, p, s.prefix);
            if (s.by_cols.len > 0) try by.appendLine(a, &body, ds, group.rows[0], s.by_cols);
            try render(a, &body, names, lay, @intFromFloat(sel.n), m, e, s.prefix);
        }
        if (created) |o| {
            // p.8007: scores of the standardized variables; omitted
            // observations get missing scores. STD scales to unit variance.
            const values = try a.alloc(Value, ds.columns.items.len + p);
            for (group.rows, 0..) |row, ri| {
                @memcpy(values[0..row.len], row);
                const used = has(sel.rows, ri);
                for (0..p) |k| {
                    var score: f64 = 0;
                    if (used) {
                        for (s.vars, 0..) |ci, j| score += (row[ci].num - m.mean[j]) / m.std[j] * e.vectors[j * p + k];
                        if (s.standard) score /= @sqrt(e.values[k]);
                    }
                    values[row.len + k] = if (used) .{ .num = score } else Value.missing;
                }
                try o.appendRow(values);
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
}

test {
    _ = @import("princomp_tests.zig");
}
