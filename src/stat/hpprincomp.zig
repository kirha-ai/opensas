//! PROC HPPRINCOMP (SAS/STAT 15.4 ch.65): PROC statement options, VAR / BY /
//! FREQ / WEIGHT / ID roles, missing-value and observation selection rules,
//! and the default METHOD=EIG correlation analysis with its listing
//! (STAT-HPPRINCOMP-001). Everything the cited pages define but this file does
//! not compute or has not verified against a SAS listing is a loud D-009 gap,
//! checked before anything prints.
//!
//! The statistics reuse the PROC PRINCOMP kernels (selection divisor, moments,
//! Jacobi eigen-decomposition) read-only; only the HP listing, the HP
//! observation counting and the HP log messages live here. Layout widths and
//! log texts come from SAS 9.4 / STAT 15.4 listings of the chapter's crime
//! example and of invented data (FREQ, WEIGHT, BY, N=, VARDEF=WDF).
const std = @import("std");
const proc = @import("../proc.zig");
const hp = @import("hp_shared.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const gap = proc.failGap;

pub const Method = enum { eig, itergs, nipals };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    // PROC statement (pp.4950-4954). Defaults: METHOD=EIG, correlation
    // matrix, intercept, N = number of variables, PREFIX=Prin, PARPREFIX=R_,
    // SINGULAR=1E-8, VARDEF=DF. A repeated option: the last one wins
    // (SAS 9.4 listing of `n=1 n=2`).
    out: ?[]const u8 = null,
    outstat: ?[]const u8 = null,
    cov: bool = false,
    noint: bool = false,
    standard: bool = false,
    noprint: bool = false,
    method: Method = .eig,
    n: ?usize = null,
    prefix: []const u8 = "Prin",
    parprefix: []const u8 = "R_",
    singular: f64 = 1e-8,
    vardef: princomp.VarDef = .df,
    // Roles.
    vars: []const usize = &.{},
    ids: []const usize = &.{},
    partial: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    // Statements owned by later tickets (recorded, then a loud gap).
    code: bool = false,
    output: bool = false,
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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC HPPRINCOMP: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
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
    if (at(t, j, .lparen)) j = proc.skipParen(t, j);
    into.* = name;
    return j;
}
fn canonical(lower: []const u8) []const u8 {
    const pairs = [_][2][]const u8{ .{ "covariance", "cov" }, .{ "standard", "std" }, .{ "pprefix", "parprefix" }, .{ "rprefix", "parprefix" }, .{ "sing", "singular" } };
    for (pairs) |p| if (eq(lower, p[0])) return p[1];
    return lower;
}
/// SAS: "Variable cc in list does not match type prescribed for this list."
fn typeError(cx: proc.ProcCtx, l: usize, name: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, l, "Variable {s} in list does not match type prescribed for this list.", .{name});
}
fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
    _ = role;
    if (ds.columns.items[ci].type != .num) return typeError(cx, t[i].line, t[i + 1].text);
    return ci;
}
fn columnList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, numeric: bool, into: *std.ArrayList(usize)) diag.Error!void {
    if (end == i + 1) return invalid(cx, t, end);
    const body = t[i + 1 .. end];
    var j: usize = 0;
    while (j < body.len) {
        const l = body[j].line;
        const names = try lists.next(cx.arena, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "Variable {s} not found.", .{n});
            if (numeric and ds.columns.items[ci].type != .num) return typeError(cx, l, n);
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = canonical(try std.ascii.allocLowerString(a, t[i].text));
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name);
            qualified = if (at(t, first + 1, .dot)) first else null;
            i = after;
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &s.out);
        } else if (eq(option, "outstat") and valued) {
            i = try memberName(cx, t, i + 2, &s.outstat);
        } else if (eq(option, "n") and valued) {
            // p.4952: "must be an integer greater than or equal to 0".
            s.n = (if (at(t, i + 2, .number)) std.fmt.parseInt(usize, t[i + 2].text, 10) catch null else null) orelse
                return cx.diags.fail(error.ParseError, t[i].line, "PROC HPPRINCOMP: N= must be an integer greater than or equal to 0", .{});
            i += 3;
        } else if ((eq(option, "prefix") or eq(option, "parprefix")) and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPPRINCOMP: {s}= must be a name", .{t[i].text});
            if (eq(option, "prefix")) s.prefix = t[i + 2].text else s.parprefix = t[i + 2].text;
            i += 3;
        } else if (eq(option, "singular") and valued) {
            const v = if (at(t, i + 2, .number)) std.fmt.parseFloat(f64, t[i + 2].text) catch null else null;
            // p.4953: 0 < p < 1.
            if (v == null or !(v.? > 0 and v.? < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPPRINCOMP: SINGULAR= must be a number between 0 and 1", .{});
            s.singular = v.?;
            i += 3;
        } else if (eq(option, "vardef") and valued) {
            s.vardef = if (kw(t, i + 2, "df")) .df else if (kw(t, i + 2, "n")) .n else if (kw(t, i + 2, "wdf")) .wdf else if (kw(t, i + 2, "weight") or kw(t, i + 2, "wgt")) .weight else return cx.diags.fail(error.ParseError, t[i].line, "PROC HPPRINCOMP: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            i += 3;
        } else if (eq(option, "method") and valued) {
            s.method = if (kw(t, i + 2, "eig")) .eig else if (kw(t, i + 2, "itergs")) .itergs else if (kw(t, i + 2, "nipals")) .nipals else return cx.diags.fail(error.ParseError, t[i].line, "PROC HPPRINCOMP: METHOD= must be EIG, ITERGS or NIPALS", .{});
            i += 3;
            if (at(t, i, .lparen)) {
                if (s.method == .eig) return invalid(cx, t, i);
                i = proc.skipParen(t, i);
            }
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
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC HPPRINCOMP: input data set not found", .{});
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
            // p.4954: "If you specify more than one BY statement, only the last one specified is used."
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            // SAS 9.4: "ERROR: Only one VAR statement can be specified."
            if (var_seen) return cx.diags.fail(error.ParseError, t[i].line, "Only one VAR statement can be specified.", .{});
            var_seen = true;
            try columnList(cx, ds, t, i, end, true, &vars);
        } else if (eq(word, "partial")) {
            if (partial_seen) return gap(cx.diags, t[i].line, "PROC HPPRINCOMP: more than one PARTIAL statement is not verified", .{});
            partial_seen = true;
            try columnList(cx, ds, t, i, end, true, &partial);
        } else if (eq(word, "id")) {
            try columnList(cx, ds, t, i, end, false, &ids);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC HPPRINCOMP: more than one FREQ statement is not verified", .{});
            s.freq = try oneNumeric(cx, ds, t, i, end, "FREQ");
        } else if (eq(word, "weight")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC HPPRINCOMP: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
        } else if (eq(word, "code")) {
            s.code = true;
        } else if (eq(word, "output")) {
            s.output = true;
        } else if (eq(word, "performance")) {
            // Shared single-machine PERFORMANCE contract (STAT-HP-001).
            var perf: hp.Performance = .{};
            try hp.parsePerformance(cx.diags, "HPPRINCOMP", t, i, end, &perf);
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (eq(word, "format")) {
            return gap(cx.diags, t[i].line, "PROC HPPRINCOMP: a FORMAT statement inside the step is not implemented (STAT-HP-001)", .{});
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
        // p.4958: "If you omit the VAR statement, all numeric variables that
        // are not specified in other statements are analyzed."
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or has(ids.items, ci) or has(partial.items, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC HPPRINCOMP: no numeric variables to analyze", .{});
    return s;
}

/// Observation counts of one BY group for the "Number of Observations" table
/// and the omission warnings.
pub const Counts = struct {
    read: usize = 0,
    used: usize = 0,
    freq_read: f64 = 0,
    freq_used: f64 = 0,
    weight_read: f64 = 0,
    weight_used: f64 = 0,
    missing: usize = 0,
    nonpositive: usize = 0,
};

/// HP observation selection (pp.4955-4960): an observation with a missing
/// VAR or PARTIAL value is omitted as missing; otherwise a missing FREQ or a
/// FREQ value whose integer portion is below 1, or a missing or nonpositive
/// WEIGHT, omits it as "nonpositive weight or truncated frequency" (that is
/// how the SAS 9.4 log counts a missing WEIGHT). The Read sums take the
/// truncated FREQ value of every observation where it is at least 1 and
/// FREQ*WEIGHT where WEIGHT is also positive, whether or not the analysis
/// variables are missing (SAS 9.4 listings of invented data).
pub fn select(a: A, s: Spec, rows: []const []const Value, c: *Counts) !princomp.Selection {
    var used: std.ArrayList(usize) = .empty;
    var freq: std.ArrayList(f64) = .empty;
    var weight: std.ArrayList(f64) = .empty;
    var n: f64 = 0;
    var sw: f64 = 0;
    c.* = .{ .read = rows.len };
    for (rows, 0..) |row, ri| {
        var f: f64 = 1;
        var f_ok = true;
        if (s.freq) |ci| {
            f = @floor(row[ci].num);
            f_ok = f >= 1; // false for missing too
            if (f_ok) c.freq_read += f;
        }
        var w: f64 = 1;
        var w_ok = true;
        if (s.weight) |ci| {
            w = row[ci].num;
            w_ok = w > 0;
            if (w_ok and f_ok) c.weight_read += f * w;
        }
        var missing = false;
        for (s.vars) |ci| missing = missing or std.math.isNan(row[ci].num);
        for (s.partial) |ci| missing = missing or std.math.isNan(row[ci].num);
        if (missing) {
            c.missing += 1;
            continue;
        }
        if (!f_ok or !w_ok) {
            c.nonpositive += 1;
            continue;
        }
        try used.append(a, ri);
        try freq.append(a, f);
        try weight.append(a, w);
        n += f;
        sw += f * w;
    }
    c.used = used.items.len;
    c.freq_used = n;
    c.weight_used = sw;
    return .{ .rows = used.items, .freq = freq.items, .weight = weight.items, .n = n, .sum_weight = sw };
}

/// The PRINCOMP kernel view of this specification (read-only reuse).
fn kernelSpec(s: Spec) princomp.Spec {
    return .{ .input = s.input, .vars = s.vars, .partial = s.partial, .freq = s.freq, .weight = s.weight, .vardef = s.vardef };
}

/// Orientation of each eigenvector: the PRINCOMP kernel makes the element
/// sum nonnegative; when the sum is zero (every two-variable analysis) the
/// SAS listing shows the first nonzero element positive.
fn orient(e: princomp.Eigen, p: usize) void {
    const v = @constCast(e.vectors);
    for (0..p) |k| {
        var sum: f64 = 0;
        for (0..p) |j| sum += v[j * p + k];
        if (@abs(sum) > 1e-9) continue;
        for (0..p) |j| if (@abs(v[j * p + k]) > 1e-12) {
            if (v[j * p + k] < 0) for (0..p) |r| {
                v[r * p + k] = -v[r * p + k];
            };
            break;
        };
    }
}

const Group = struct {
    rep: usize,
    counts: Counts,
    sel: princomp.Selection,
    m: ?princomp.Moments = null,
    e: ?princomp.Eigen = null,
};

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
fn fixed(a: A, value: f64, decimals: usize) ![]const u8 {
    var text: []const u8 = try std.fmt.allocPrint(a, "{d:.[1]}", .{ value, decimals });
    if (std.mem.startsWith(u8, text, "-") and std.mem.indexOfAny(u8, text, "123456789") == null) text = text[1..];
    return text;
}
/// Centered table title (floor of the free width) and the blank or one-space
/// line SAS writes under it (one space when column headers follow).
fn title(a: A, out: *Out, text: []const u8, width: usize, headers: bool) !void {
    try pad(a, out, if (width > text.len) (width - text.len) / 2 else 0);
    try out.appendSlice(a, text);
    try out.appendSlice(a, if (headers) "\n \n" else "\n\n");
}
/// Label/value rows: label column `lw`, four spaces, value column `vw`.
fn pair(a: A, out: *Out, label: []const u8, lw: usize, value: []const u8, vw: usize, left_value: bool) !void {
    try left(a, out, label, lw + 4);
    if (left_value) try left(a, out, value, vw) else try right(a, out, value, vw);
    try out.appendSlice(a, "\n");
}
fn best(a: A, v: f64) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{v});
}

fn upperName(a: A, s: Spec) ![]const u8 {
    const upper = try std.ascii.allocUpperString(a, s.data_name);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    return if (std.mem.indexOfScalar(u8, upper, '.') == null) std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
}

fn header(a: A, out: *Out, data: []const u8) !void {
    try out.appendSlice(a, "\nThe HPPRINCOMP Procedure\n\n");
    try title(a, out, "Performance Information", 35, false);
    // ponytail: opensas computes on one thread. SAS reports one thread per
    // CPU of the host (p.4962); the honest value here is 1 (STAT-HP-002).
    try pair(a, out, "Execution Mode", 17, "Single-Machine", 14, true);
    try pair(a, out, "Number of Threads", 17, "1", 14, true);
    try out.appendSlice(a, "\n\n");
    const dw = @max(4, data.len);
    try title(a, out, "Data Access Information", dw + 4 + 6 + 4 + 5 + 4 + 9, true);
    try left(a, out, "Data", dw + 4);
    try out.appendSlice(a, "Engine    Role     Path\n\n");
    try left(a, out, data, dw + 4);
    try out.appendSlice(a, "V9        Input    On Client\n");
}

const Layout = struct {
    label: usize,
    upper: []const []const u8,
    lower: []const []const u8,
    width: []const usize,
};

/// Everything the verified listing shape depends on, checked before printing.
fn layout(cx: proc.ProcCtx, l0: usize, s: Spec, names: []const []const u8, groups: []const Group, ncomp: usize) diag.Error!Layout {
    const a = cx.arena;
    const p = names.len;
    const upper = try a.alloc([]const u8, p);
    const lower = try a.alloc([]const u8, p);
    const width = try a.alloc(usize, p);
    var label: usize = 8;
    var corr: usize = 0;
    for (names, 0..) |n, j| {
        label = @max(label, n.len);
        upper[j] = "";
        lower[j] = n;
        if (n.len > 8) {
            // Verified shape: "Auto_Theft" prints as "Auto_" over "Theft".
            // Other long names split elsewhere ("LongNameXY" as "Long" over
            // "NameXY"); that rule is not derived, so it is a gap.
            const u = std.mem.indexOfScalar(u8, n, '_') orelse
                return gap(cx.diags, l0, "PROC HPPRINCOMP: the correlation matrix column header for variable {s} is not verified against SAS output (STAT-HPPRINCOMP-007)", .{n});
            if (u + 1 > 7 or n.len - u - 1 > 7 or n.len - u - 1 == 0 or std.mem.indexOfScalarPos(u8, n, u + 1, '_') != null)
                return gap(cx.diags, l0, "PROC HPPRINCOMP: the correlation matrix column header for variable {s} is not verified against SAS output (STAT-HPPRINCOMP-007)", .{n});
            upper[j] = n[0 .. u + 1];
            lower[j] = n[u + 1 ..];
        }
        width[j] = @max(7, @max(upper[j].len, lower[j].len)) + 4;
        corr += width[j];
    }
    const ls: usize = if (io.global_linesize == 0) 132 else io.global_linesize;
    const widest = @max(label + corr, label + 15 * ncomp);
    // ponytail: no panel wrapping; a table wider than the line size is a gap.
    if (widest > ls) return gap(cx.diags, l0, "PROC HPPRINCOMP: tables wider than the line size ({d} > {d}) are not implemented (STAT-HPPRINCOMP-007)", .{ widest, ls });
    if (std.fmt.count("{s}{d}", .{ s.prefix, ncomp }) > 14) return gap(cx.diags, l0, "PROC HPPRINCOMP: the Eigenvectors header for a long PREFIX= is not verified against SAS output (STAT-HPPRINCOMP-007)", .{});
    // Number shapes verified against SAS: fixed decimals; SAS prints exact
    // zeros as "0" and reduces decimals for wide means ("1000006"), neither
    // of which is reproduced here.
    for (groups) |g| {
        const m = g.m.?;
        const e = g.e.?;
        for (m.mean, m.std, names) |mean, sd, n| {
            for ([_]f64{ mean, sd }) |v| {
                const text = try fixed(a, v, 5);
                if (@abs(v) < 1e-3 or text.len > 10) return gap(cx.diags, l0, "PROC HPPRINCOMP: the Simple Statistics number layout for variable {s} (magnitude below 0.001 or wider than 10 characters) is not verified against SAS output (STAT-HPPRINCOMP-007)", .{n});
            }
        }
        for (e.values[0..ncomp]) |v| if (!(v >= 5e-7) or v >= 1000) return gap(cx.diags, l0, "PROC HPPRINCOMP: an eigenvalue that is zero, negative or at least 1000 is not verified against SAS output (STAT-HPPRINCOMP-007)", .{});
        for (0..p) |j| for (0..ncomp) |k| if (@abs(e.vectors[j * p + k]) < 0.01) return gap(cx.diags, l0, "PROC HPPRINCOMP: an eigenvector element below 0.01 in magnitude (SAS widens its digits, \"0.00028496\") is not verified against SAS output (STAT-HPPRINCOMP-007)", .{});
    }
    return .{ .label = label, .upper = upper, .lower = lower, .width = width };
}

fn render(a: A, out: *Out, s: Spec, data: []const u8, names: []const []const u8, lay: Layout, g: Group, ncomp: usize) !void {
    const p = names.len;
    const m = g.m.?;
    const e = g.e.?;
    const c = g.counts;
    const mw = @max(24, data.len);
    try title(a, out, "Model Information", 27 + 4 + mw, false);
    try pair(a, out, "Data Source", 27, data, mw, true);
    try pair(a, out, "Component Extraction Method", 27, "Eigenvalue Decomposition", mw, true);
    try out.appendSlice(a, "\n\n");
    try pair(a, out, "Number of Observations Read", 27, try std.fmt.allocPrint(a, "{d}", .{c.read}), 11, false);
    try pair(a, out, "Number of Observations Used", 27, try std.fmt.allocPrint(a, "{d}", .{c.used}), 11, false);
    if (s.freq != null) {
        try pair(a, out, "Sum of Frequencies Read", 27, try best(a, c.freq_read), 11, false);
        try pair(a, out, "Sum of Frequencies Used", 27, try best(a, c.freq_used), 11, false);
    }
    if (s.weight != null) {
        try pair(a, out, "Sum of Weights Read", 27, try best(a, c.weight_read), 11, false);
        try pair(a, out, "Sum of Weights Used", 27, try best(a, c.weight_used), 11, false);
    }
    try out.appendSlice(a, "\n\n");
    try pair(a, out, "Number of Variables", 30, try std.fmt.allocPrint(a, "{d}", .{p}), 6, false);
    try pair(a, out, "Number of Principal Components", 30, try std.fmt.allocPrint(a, "{d}", .{ncomp}), 6, false);

    try out.appendSlice(a, "\n\n");
    try title(a, out, "Simple Statistics", lay.label + 30, true);
    try pad(a, out, lay.label + 22);
    try out.appendSlice(a, "Standard\n");
    try left(a, out, "Variable", lay.label);
    try out.appendSlice(a, "           Mean      Deviation\n\n");
    for (names, m.mean, m.std) |n, mean, sd| {
        try left(a, out, n, lay.label);
        try right(a, out, try fixed(a, mean, 5), 15);
        try right(a, out, try fixed(a, sd, 5), 15);
        try out.appendSlice(a, "\n");
    }

    var corr = lay.label;
    var split = false;
    for (lay.width, lay.upper) |w, u| {
        corr += w;
        if (u.len > 0) split = true;
    }
    try out.appendSlice(a, "\n\n");
    try title(a, out, "Correlation Matrix", corr, true);
    if (split) {
        var head: Out = .empty;
        try pad(a, &head, lay.label);
        for (lay.upper, lay.width) |u, w| try right(a, &head, u, w);
        try out.appendSlice(a, std.mem.trimEnd(u8, head.items, " "));
        try out.appendSlice(a, "\n");
    }
    try left(a, out, "Variable", lay.label);
    for (lay.lower, lay.width) |text, w| try right(a, out, text, w);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |n, j| {
        try left(a, out, n, lay.label);
        for (lay.width, 0..) |w, k| try right(a, out, try fixed(a, m.corr[j * p + k], 4), w);
        try out.appendSlice(a, "\n");
    }

    // Fixed 64-column table; SAS indents this heading by 14.
    try out.appendSlice(a, "\n\n");
    try pad(a, out, 14);
    try out.appendSlice(a, "Eigenvalues of the Correlation Matrix\n \n");
    try out.appendSlice(a, "          Eigenvalue      Difference    Proportion    Cumulative\n\n");
    var total: f64 = 0;
    for (e.values) |v| total += v;
    var cumulative: f64 = 0;
    for (e.values[0..ncomp], 0..) |v, k| {
        cumulative += v;
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 4);
        try right(a, out, try fixed(a, v, 6), 16);
        try right(a, out, if (k + 1 < ncomp) try fixed(a, v - e.values[k + 1], 6) else "", 16);
        try right(a, out, try fixed(a, v / total, 4), 14);
        try right(a, out, try fixed(a, cumulative / total, 4), 14);
        try out.appendSlice(a, "\n");
    }

    try out.appendSlice(a, "\n\n");
    try title(a, out, "Eigenvectors", lay.label + 15 * ncomp, true);
    try left(a, out, "Variable", lay.label);
    for (0..ncomp) |k| try right(a, out, try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, k + 1 }), 15);
    try out.appendSlice(a, "\n\n");
    for (names, 0..) |n, j| {
        try left(a, out, n, lay.label);
        for (0..ncomp) |k| try right(a, out, try fixed(a, e.vectors[j * p + k], 5), 15);
        try out.appendSlice(a, "\n");
    }
}

fn emitTitles(cx: proc.ProcCtx, out: *Out) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out);
}
fn emitFootnotes(cx: proc.ProcCtx, out: *Out) !void {
    if (cx.listing_titles) |titles| try titles.emitFootnotes(cx.arena, out);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const p = s.vars.len;

    // Boundaries owned by later tickets: fail visibly before any output.
    if (s.method != .eig) return gap(cx.diags, l0, "PROC HPPRINCOMP: METHOD=ITERGS and METHOD=NIPALS are not implemented (STAT-HPPRINCOMP-003, STAT-HPPRINCOMP-004)", .{});
    if (s.partial.len > 0) return gap(cx.diags, l0, "PROC HPPRINCOMP: the PARTIAL statement is not implemented (STAT-HPPRINCOMP-003)", .{});
    if (s.code) return gap(cx.diags, l0, "PROC HPPRINCOMP: the CODE statement is not implemented (STAT-HPPRINCOMP-005)", .{});
    if (s.output) return gap(cx.diags, l0, "PROC HPPRINCOMP: the OUTPUT statement is not implemented (STAT-HPPRINCOMP-006)", .{});
    if (s.out != null) return gap(cx.diags, l0, "PROC HPPRINCOMP: the OUT= data set is not implemented (STAT-HPPRINCOMP-006)", .{});
    if (s.outstat != null) return gap(cx.diags, l0, "PROC HPPRINCOMP: the OUTSTAT= data set is not implemented (STAT-HPPRINCOMP-006)", .{});
    if (s.cov) return gap(cx.diags, l0, "PROC HPPRINCOMP: the COV analysis and its listing are not implemented (STAT-HPPRINCOMP-002)", .{});
    if (s.noint) return gap(cx.diags, l0, "PROC HPPRINCOMP: the NOINT analysis and its listing are not implemented (STAT-HPPRINCOMP-002)", .{});
    if (s.n) |n| if (n == 0 or n > p) return gap(cx.diags, l0, "PROC HPPRINCOMP: N={d} outside 1 to the number of variables is not verified against SAS output (STAT-HPPRINCOMP-002)", .{n});
    const ncomp = s.n orelse p;

    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    var all_missing = false;
    for (slices, groups) |slice, *g| {
        g.* = .{ .rep = 0, .counts = .{}, .sel = undefined };
        g.sel = try select(a, s, slice.rows, &g.counts);
        if (g.sel.rows.len == 0 or !(g.sel.sum_weight > 0)) {
            if (s.by_cols.len > 0) return gap(cx.diags, l0, "PROC HPPRINCOMP: a BY group without usable observations is not verified against SAS output", .{});
            all_missing = true;
            continue;
        }
        if (g.sel.n < 2) return gap(cx.diags, l0, "PROC HPPRINCOMP: an analysis with fewer than two usable observations is not verified against SAS output", .{});
        if (!(princomp.divisor(s.vardef, g.sel) > 0)) return gap(cx.diags, l0, "PROC HPPRINCOMP: a nonpositive VARDEF= divisor is not verified against SAS output", .{});
        g.m = (try princomp.moments(a, kernelSpec(s), slice.rows, g.sel)) orelse
            return gap(cx.diags, l0, "PROC HPPRINCOMP: a constant variable (zero variance) is not verified against SAS output", .{});
        const e = try princomp.eigenSym(a, g.m.?.corr, p);
        orient(e, p);
        g.e = e;
    }
    const names = try a.alloc([]const u8, p);
    for (s.vars, names) |ci, *n| n.* = ds.columns.items[ci].name;
    const data = try upperName(a, s);
    const lay: ?Layout = if (s.noprint or all_missing) null else try layout(cx, l0, s, names, groups, ncomp);

    try cx.diags.note(l0, "The HPPRINCOMP procedure is executing in single-machine mode.", .{});
    if (!s.noprint) {
        try emitTitles(cx, out);
        try header(a, out, data);
        if (s.by_cols.len > 0) try emitFootnotes(cx, out);
    }
    for (slices, groups) |slice, g| {
        if (g.counts.missing > 0) try cx.diags.warnStatus(l0, "{d} observations omitted due to missing values.", .{g.counts.missing});
        if (g.counts.nonpositive > 0) try cx.diags.warnStatus(l0, "{d} observations omitted due to nonpositive weight or truncated frequency.", .{g.counts.nonpositive});
        if (s.by_cols.len > 0 and g.counts.missing + g.counts.nonpositive > 0) try by.reportNote(a, cx.diags, ds, slice.rows[0], s.by_cols);
        if (all_missing) return cx.diags.fail(error.ParseError, l0, "All observations in the data set have missing values, or the sum of weights or frequencies is nonpositive.", .{});
        if (s.noprint) continue;
        if (s.by_cols.len > 0) {
            try emitTitles(cx, out);
            var ln: Out = .empty;
            try by.appendLine(a, &ln, ds, slice.rows[0], s.by_cols);
            if (ln.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, ln.items[1..], " "));
                if (!std.mem.endsWith(u8, ln.items, "\n")) try out.append(a, '\n');
            }
            try out.appendSlice(a, "\nThe HPPRINCOMP Procedure\n\n");
        } else try out.appendSlice(a, "\n\n");
        try render(a, out, s, data, names, lay.?, g, ncomp);
        try emitFootnotes(cx, out);
    }
}

test {
    _ = @import("hpprincomp_tests.zig");
}
