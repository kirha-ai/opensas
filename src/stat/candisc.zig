//! PROC CANDISC declarations, roles and the default listing, SAS/STAT 15.4
//! Chapter 35 (PROC CANDISC statement pp.2156-2159, BY p.2159, CLASS
//! pp.2159-2160, FREQ/VAR p.2160, WEIGHT pp.2160-2161, Missing Values p.2161,
//! Computational Details pp.2161-2162). The canonical analysis is the
//! generalized eigenproblem E^-1 H of the within (E) and between (H = T - E)
//! SSCP matrices, solved by the shared reg_mtest kernel; raw coefficients are
//! scaled to unit pooled within-class variance. Everything not verified
//! against the SAS reference is a D-009 gap (rc 2) raised before any listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const varlist = @import("variable_lists.zig");
const mtest = @import("reg_mtest.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    out: ?[]const u8 = null,
    ncan: ?usize = null,
    prefix: []const u8 = "Can",
    noprint: bool = false,
    short: bool = false,
    class: usize = 0,
    vars: []const usize = &.{},
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
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC CANDISC: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC CANDISC: " ++ text, args);
}

fn dataName(a: A, t: []const lex.Token, i: *usize) !?[]const u8 {
    if (!at(t, i.*, .name)) return null;
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot) and at(t, i.* + 1, .name)) {
        name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    return name;
}

/// Display options documented in Table 35.1 that this ticket does not render.
const display_gaps = [_][]const u8{ "all", "anova", "bcorr", "bcov", "bsscp", "distance", "mahalanobis", "pcorr", "pcov", "psscp", "simple", "stdmean", "tcorr", "tcov", "tsscp", "wcorr", "wcov", "wsscp" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, tok: lex.Token) diag.Error!usize {
    return ds.indexOf(tok.text) orelse user(cx, tok.line, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, tok.text)});
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            data = (try dataName(a, t, &i)) orelse return invalid(cx, t, i);
            if (at(t, i, .lparen)) {
                // Data set options are applied by procInput from the PROC tokens.
                var depth: usize = 0;
                while (i < t.len) : (i += 1) {
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                i += 1;
            }
        } else if (eq(word, "out") and valued) {
            i += 2;
            s.out = (try dataName(a, t, &i)) orelse return invalid(cx, t, i);
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on OUT= are not implemented", .{});
        } else if (eq(word, "outstat") and valued) {
            return gap(cx, t[i].line, "OUTSTAT= is not implemented (owned by a later CANDISC ticket)", .{});
        } else if (eq(word, "ncan") and valued) {
            var j = i + 2;
            const negative = at(t, j, .minus);
            if (negative) j += 1;
            if (!at(t, j, .number)) return invalid(cx, t, j);
            const x = std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j);
            if (negative or x == 0) return gap(cx, t[i].line, "NCAN= zero or negative (canonical analysis suppressed) is not implemented", .{});
            if (x != @floor(x)) return invalid(cx, t, j);
            s.ncan = @intFromFloat(x);
            i = j + 1;
        } else if (eq(word, "prefix") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            s.prefix = t[i + 2].text;
            i += 3;
        } else if (eq(word, "singular") and valued) {
            return gap(cx, t[i].line, "SINGULAR= is not implemented (owned by a later CANDISC ticket)", .{});
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "short")) {
            s.short = true;
            i += 1;
        } else {
            for (display_gaps) |g| if (eq(word, g)) return gap(cx, t[i].line, "the {s} option is not implemented (owned by a later CANDISC ticket)", .{word});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const name = data orelse return gap(cx, lineOf(t, 0), "DATA= omitted (most recently created data set) is not implemented", .{});
    const raw = cx.lib.find(name) orelse return user(cx, lineOf(t, 0), "File {s} does not exist.", .{try std.ascii.allocUpperString(a, name)});
    s.ds = try proc.procInput(a, raw, t[0..@min(t.len, i + 1)], cx.diags);
    // Input Data Set (pp.2162-2163): TYPE=CORR/COV/CSSCP/SSCP input is read by _TYPE_.
    if (s.ds.indexOf("_type_") != null) return gap(cx, lineOf(t, 0), "input data sets with a _TYPE_ variable (TYPE=CORR, COV, CSSCP, SSCP) are not implemented", .{});

    var bys: ?by.Statements = null;
    var class: ?usize = null;
    var var_names: ?std.ArrayList([]const u8) = null;
    var freq_seen = false;
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
        if (kw(t, i, "class")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return user(cx, lineOf(t, i + 2), "Expecting ;.", .{});
            // Reference (SAS 9.4): with two CLASS statements the first is used.
            if (class == null) class = try column(cx, s.ds, t[i + 1]);
        } else if (kw(t, i, "var")) {
            if (var_names != null) return gap(cx, t[i].line, "more than one VAR statement is not verified", .{});
            var names: std.ArrayList([]const u8) = .empty;
            try varlist.append(a, s.ds, t[i + 1 .. end], &names, cx.diags);
            if (names.items.len == 0) return invalid(cx, t, end);
            var_names = names;
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.2159).
            var fresh: by.Statements = .{};
            var j = i;
            try fresh.read(a, t, &j);
            bys = fresh;
        } else if (kw(t, i, "freq")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const c = try column(cx, s.ds, t[i + 1]);
            if (s.ds.columns.items[c].type != .num) return user(cx, t[i + 1].line, "Variable {s} in list does not match type prescribed for this list.", .{t[i + 1].text});
            // Reference (SAS 9.4): with two FREQ statements the first is used.
            if (!freq_seen) s.freq = c;
            freq_seen = true;
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return gap(cx, t[i].line, "more than one WEIGHT statement is not verified", .{});
            weight_seen = true;
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const c = try column(cx, s.ds, t[i + 1]);
            if (s.ds.columns.items[c].type != .num) return user(cx, t[i + 1].line, "Variable {s} in list does not match type prescribed for this list.", .{t[i + 1].text});
            s.weight = c;
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where") or (at(t, i, .name) and @import("../parser.zig").isMidStepSkippable(t[i].text))) {
            // Step boundaries; WHERE is applied by procInput; mid-step global
            // statements (ODS, TITLE, OPTIONS) were executed before the step.
        } else return invalid(cx, t, i);
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
    s.class = class orelse return user(cx, lineOf(t, 0), "A CLASS statement must be specified.", .{});
    if (s.ds.columns.items[s.class].format != null) return gap(cx, lineOf(t, 0), "a formatted CLASS variable is not implemented", .{});
    var vars: std.ArrayList(usize) = .empty;
    if (var_names) |names| {
        for (names.items) |n| {
            const c = s.ds.indexOf(n) orelse return user(cx, lineOf(t, 0), "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
            if (s.ds.columns.items[c].type != .num) return user(cx, lineOf(t, 0), "Variable {s} in list does not match type prescribed for this list.", .{n});
            if (std.mem.indexOfScalar(usize, vars.items, c) != null) return gap(cx, lineOf(t, 0), "a variable listed twice in the VAR statement is not verified", .{});
            try vars.append(a, c);
        }
    } else {
        // "If you do not use a VAR statement, the analysis includes all
        // numeric variables not listed in other statements" (p.2160).
        for (s.ds.columns.items, 0..) |col, c| {
            if (col.type != .num or c == s.class or c == s.freq or c == s.weight) continue;
            if (std.mem.indexOfScalar(usize, s.by_cols, c) != null) continue;
            try vars.append(a, c);
        }
    }
    if (vars.items.len == 0) return gap(cx, lineOf(t, 0), "an analysis without quantitative variables is not verified", .{});
    if (vars.items.len > 16) return gap(cx, lineOf(t, 0), "more than 16 quantitative variables are not implemented", .{});
    if (std.mem.indexOfScalar(usize, vars.items, s.class) != null) return gap(cx, lineOf(t, 0), "the CLASS variable in the VAR list is not verified", .{});
    s.vars = vars.items;
    return s;
}

// ── Analysis ────────────────────────────────────────────────────────────────

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

pub const Level = struct { key: Value, text: []const u8, freq: f64 = 0, weight: f64 = 0, mean: []f64 };

pub const Result = struct {
    p: usize,
    levels: []Level,
    n_read: usize,
    n_used: usize,
    freq_read: f64,
    freq_used: f64,
    wt_read: f64,
    wt_used: f64,
    n_missing_vars: usize,
    n_missing_class: usize,
    n_invalid: usize,
    nfreq: f64,
    grand: []f64,
    e: []f64,
    t: []f64,
    h: []f64,
    stats: mtest.Result,
    roots: []f64,
    ncomp: usize,
    raw: []f64, // p x ncomp, column-major by component: raw[k*p + j]
};

pub const AnalysisError = error{ OutOfMemory, Empty, OneLevel, NoDf, Singular };

fn levelText(a: A, v: Value) ![]const u8 {
    return switch (v) {
        .str => |x| std.mem.trimEnd(u8, x, " "),
        .num => std.mem.trim(u8, try format.apply(a, v, "best12."), " "),
    };
}

fn lessValue(_: void, x: Level, y: Level) bool {
    return switch (x.key) {
        .num => |u| u < y.key.num,
        .str => std.mem.order(u8, x.text, y.text) == .lt,
    };
}

pub fn analyze(a: A, s: Spec, rows: []const []const Value) AnalysisError!Result {
    const p = s.vars.len;
    var r: Result = undefined;
    r.p = p;
    r.n_read = rows.len;
    r.n_used = 0;
    r.freq_read = 0;
    r.freq_used = 0;
    r.wt_read = 0;
    r.wt_used = 0;
    r.n_missing_vars = 0;
    r.n_missing_class = 0;
    r.n_invalid = 0;
    var levels: std.ArrayList(Level) = .empty;
    const row_level = try a.alloc(?usize, rows.len);
    const fw = try a.alloc(f64, rows.len);
    const ff = try a.alloc(f64, rows.len);
    for (rows, 0..) |row, o| {
        row_level[o] = null;
        // FREQ (p.2160): missing or below 1 → not used; truncated. WEIGHT:
        // the documentation says missing or negative counts as 0, but the
        // SAS 9.4 reference excludes such observations ("excluded due to
        // invalid WEIGHT or FREQ variable values"); this follows SAS.
        var f: f64 = 1;
        var f_raw: f64 = 1;
        var valid = true;
        if (s.freq) |fc| {
            const x = row[fc].num;
            f_raw = if (std.math.isNan(x)) 0 else x;
            valid = !std.math.isNan(x) and x >= 1;
            f = if (valid) @trunc(x) else 1;
        }
        var w: f64 = 1;
        if (s.weight) |wc| {
            const x = row[wc].num;
            const ok = !std.math.isNan(x) and x >= 0;
            w = if (ok) x else 0;
            valid = valid and ok;
        }
        ff[o] = f;
        fw[o] = f * w;
        const class_missing = missing(row[s.class]);
        if (!class_missing) {
            // Reference "Read" sums: raw FREQ values; FREQ*WEIGHT with an
            // invalid FREQ read as 1 and an invalid WEIGHT as 0.
            r.freq_read += f_raw;
            r.wt_read += f * w;
        }
        var vars_missing = false;
        for (s.vars) |c| if (missing(row[c])) {
            vars_missing = true;
        };
        if (vars_missing) {
            r.n_missing_vars += 1;
            continue;
        }
        if (class_missing) {
            r.n_missing_class += 1;
            continue;
        }
        if (!valid) {
            r.n_invalid += 1;
            continue;
        }
        const text = try levelText(a, row[s.class]);
        var li: ?usize = null;
        for (levels.items, 0..) |l, k| if (std.mem.eql(u8, l.text, text)) {
            li = k;
        };
        if (li == null) {
            const mean = try a.alloc(f64, p);
            @memset(mean, 0);
            try levels.append(a, .{ .key = row[s.class], .text = text, .mean = mean });
            li = levels.items.len - 1;
        }
        row_level[o] = li;
        r.n_used += 1;
        r.freq_used += f;
        r.wt_used += f * w;
    }
    if (r.n_used == 0) return error.Empty;
    // Level order: sorted (text for character, value for numeric) — the
    // reference listings are in ascending order of the levels.
    const order = try a.alloc(usize, levels.items.len);
    const sorted = try a.dupe(Level, levels.items);
    std.mem.sort(Level, sorted, {}, lessValue);
    for (levels.items, 0..) |l, k| {
        for (sorted, 0..) |m, j| if (std.mem.eql(u8, m.text, l.text)) {
            order[k] = j;
        };
    }
    for (row_level) |*rl| if (rl.*) |k| {
        rl.* = order[k];
    };
    r.levels = sorted;
    const c = sorted.len;
    if (c < 2) return error.OneLevel;
    r.nfreq = r.freq_used;
    if (!(r.nfreq - @as(f64, @floatFromInt(c)) >= 1)) return error.NoDf;
    // Weighted class and grand means (f128 accumulation).
    const F = f128;
    const sums = try a.alloc(F, c * p);
    const wsum = try a.alloc(F, c);
    @memset(sums, 0);
    @memset(wsum, 0);
    for (rows, 0..) |row, o| if (row_level[o]) |k| {
        r.levels[k].freq += ff[o];
        r.levels[k].weight += fw[o];
        wsum[k] += fw[o];
        for (s.vars, 0..) |col, j| sums[k * p + j] += @as(F, fw[o]) * row[col].num;
    };
    var wtot: F = 0;
    for (wsum) |w| wtot += w;
    if (!(wtot > 0)) return error.Singular;
    r.grand = try a.alloc(f64, p);
    for (0..p) |j| {
        var g: F = 0;
        for (0..c) |k| g += sums[k * p + j];
        r.grand[j] = @floatCast(g / wtot);
    }
    for (r.levels, 0..) |*l, k| {
        if (!(wsum[k] > 0)) return error.Singular;
        for (0..p) |j| l.mean[j] = @floatCast(sums[k * p + j] / wsum[k]);
    }
    const e = try a.alloc(F, p * p);
    const tt = try a.alloc(F, p * p);
    @memset(e, 0);
    @memset(tt, 0);
    for (rows, 0..) |row, o| if (row_level[o]) |k| {
        const w: F = fw[o];
        for (0..p) |i| {
            const di: F = @as(F, row[s.vars[i]].num) - r.levels[k].mean[i];
            const ti: F = @as(F, row[s.vars[i]].num) - r.grand[i];
            for (0..p) |j| {
                e[i * p + j] += w * di * (@as(F, row[s.vars[j]].num) - r.levels[k].mean[j]);
                tt[i * p + j] += w * ti * (@as(F, row[s.vars[j]].num) - r.grand[j]);
            }
        }
    };
    r.e = try a.alloc(f64, p * p);
    r.t = try a.alloc(f64, p * p);
    r.h = try a.alloc(f64, p * p);
    for (0..p * p) |k| {
        r.e[k] = @floatCast(e[k]);
        r.t[k] = @floatCast(tt[k]);
    }
    // Symmetrize exactly so the kernel's symmetry check holds.
    for (0..p) |i| for (0..p) |j| {
        if (j < i) {
            r.e[i * p + j] = r.e[j * p + i];
            r.t[i * p + j] = r.t[j * p + i];
        }
    };
    for (0..p * p) |k| r.h[k] = @floatCast(tt[k] - e[k]);
    for (0..p) |i| for (0..p) |j| {
        if (j < i) r.h[i * p + j] = r.h[j * p + i];
    };
    const dfe: usize = @intFromFloat(r.nfreq - @as(f64, @floatFromInt(c)));
    const ch = mtest.characteristic(a, r.e, r.h, p) catch return error.Singular;
    r.stats = mtest.statistics(a, r.e, r.h, p, c - 1, dfe, false) catch return error.Singular;
    r.roots = ch.roots;
    r.ncomp = @min(p, c - 1);
    r.raw = try a.alloc(f64, p * p);
    const scale = @sqrt(@as(f64, @floatFromInt(dfe)));
    for (0..p) |k| {
        // Sign: see signOf.
        var col = try a.alloc(f64, p);
        for (0..p) |j| col[j] = ch.vectors[j * p + k] * scale;
        const sg = signOf(r, col);
        for (0..p) |j| r.raw[k * p + j] = sg * col[j];
        col = undefined;
    }
    return r;
}

/// ponytail: the eigenvector sign. SAS's convention is not documented; this
/// rule is calibrated on the SAS 9.4 reference listings recorded in the
/// CANDISC fixtures: whiten the total-sample standardized coefficients by
/// the Cholesky factor of the total correlation matrix (u = L't, R = LL') and
/// make the components of u sum to a positive value.
fn signOf(r: Result, v: []const f64) f64 {
    const p = r.p;
    var l: [16 * 16]f64 = undefined;
    var d: [16]f64 = undefined;
    for (0..p) |i| d[i] = @sqrt(r.t[i * p + i]);
    for (0..p) |i| for (0..i + 1) |j| {
        var x = r.t[i * p + j] / (d[i] * d[j]);
        for (0..j) |k| x -= l[i * 16 + k] * l[j * 16 + k];
        l[i * 16 + j] = if (i == j) @sqrt(@max(x, 0)) else if (l[j * 16 + j] > 0) x / l[j * 16 + j] else 0;
    };
    var sum: f64 = 0;
    for (0..p) |i| for (i..p) |j| {
        sum += l[j * 16 + i] * v[j] * d[j];
    };
    return if (sum < 0) -1 else 1;
}

// ── Listing ─────────────────────────────────────────────────────────────────

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn fmt(a: A, x: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}

fn fixed(a: A, x: f64, d: usize) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, d });
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

fn fTail(f: f64, d1: f64, d2: f64) f64 {
    if (!(f >= 0)) return std.math.nan(f64);
    return proc.betai(d2 / 2, d1 / 2, d2 / (d2 + d1 * f));
}

fn pvalue(a: A, x: f64) ![]const u8 {
    return fmt(a, x, "pvalue6.4");
}

fn levelWidth(s: Spec, r: Result) usize {
    const col = s.ds.columns.items[s.class];
    if (col.type == .num) return @max(6, col.name.len);
    var w: usize = col.name.len;
    for (r.levels) |l| w = @max(w, l.text.len);
    return w;
}

fn levelCell(a: A, out: *Out, s: Spec, text: []const u8, width: usize) !void {
    try pad(a, out, text, width, s.ds.columns.items[s.class].type != .num);
}

fn counts(a: A, out: *Out, s: Spec, r: Result) !void {
    const c = r.levels.len;
    const n: f64 = r.nfreq;
    const left = [_]struct { []const u8, f64 }{ .{ "Total Sample Size", n }, .{ "Variables", @floatFromInt(r.p) }, .{ "Classes", @floatFromInt(c) } };
    const right = [_]struct { []const u8, f64 }{ .{ "DF Total", n - 1 }, .{ "DF Within Classes", n - @as(f64, @floatFromInt(c)) }, .{ "DF Between Classes", @floatFromInt(c - 1) } };
    for (left, right) |l, rr| {
        const lv = try fmt(a, l[1], "best12.");
        const rv = try fmt(a, rr[1], "best12.");
        try pad(a, out, l[0], 38 - lv.len, true);
        try out.appendSlice(a, lv);
        try out.appendNTimes(a, ' ', 10);
        try pad(a, out, rr[0], 38 - rv.len, true);
        try out.appendSlice(a, rv);
        try out.append(a, '\n');
    }
    _ = s;
}

fn nobs(a: A, out: *Out, s: Spec, r: Result) !void {
    var rows: std.ArrayList(struct { []const u8, f64 }) = .empty;
    try rows.append(a, .{ "Number of Observations Read", @floatFromInt(r.n_read) });
    try rows.append(a, .{ "Number of Observations Used", @floatFromInt(r.n_used) });
    if (s.freq != null) {
        try rows.append(a, .{ "Sum of Frequencies Read", r.freq_read });
        try rows.append(a, .{ "Sum of Frequencies Used", r.freq_used });
    }
    if (s.weight != null) {
        try rows.append(a, .{ "Sum of Weights Read", r.wt_read });
        try rows.append(a, .{ "Sum of Weights Used", r.wt_used });
    }
    for (rows.items) |row| {
        const v = try fmt(a, row[1], "best12.");
        try pad(a, out, row[0], 42 - v.len, true);
        try out.appendSlice(a, v);
        try out.append(a, '\n');
    }
}

fn levelsTable(a: A, out: *Out, s: Spec, r: Result) !void {
    const w1 = levelWidth(s, r);
    var w2: usize = "Variable".len;
    for (r.levels) |l| w2 = @max(w2, l.text.len);
    // ponytail: a numeric CLASS column centers the title one column further
    // right in the reference listing (calibrated, SAS 9.4).
    const total = w1 + 4 + w2 + 40 + @as(usize, if (s.ds.columns.items[s.class].type == .num) 1 else 0);
    try centered(a, out, "Class Level Information", total);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', w1 + 4);
    try out.appendSlice(a, "Variable\n");
    try levelCell(a, out, s, s.ds.columns.items[s.class].name, w1);
    try out.appendNTimes(a, ' ', 4);
    try pad(a, out, "Name", w2, true);
    try pad(a, out, "Frequency", 13, false);
    try pad(a, out, "Weight", 13, false);
    try pad(a, out, "Proportion", 14, false);
    try out.appendSlice(a, "\n\n");
    for (r.levels) |l| {
        try levelCell(a, out, s, l.text, w1);
        try out.appendNTimes(a, ' ', 4);
        try pad(a, out, l.text, w2, true);
        try pad(a, out, try fmt(a, l.freq, "best12."), 13, false);
        try pad(a, out, try fixed(a, l.weight, 4), 13, false);
        try pad(a, out, try fixed(a, l.freq / r.nfreq, 6), 14, false);
        try out.append(a, '\n');
    }
}

fn multStat(a: A, out: *Out, r: Result) !void {
    const st = r.stats;
    const exact = st.s == 1;
    try centered(a, out, if (exact) "Multivariate Statistics and Exact F Statistics" else "Multivariate Statistics and F Approximations", 79);
    try out.appendSlice(a, " \n");
    try centered(a, out, try std.fmt.allocPrint(a, "S={d}    M={s}    N={s}", .{ st.s, try fmt(a, st.m, "best12."), try fmt(a, st.n, "best12.") }), 79);
    try out.appendSlice(a, " \nStatistic                        Value    F Value    Num DF    Den DF    Pr > F\n\n");
    const names = [_][]const u8{ "Wilks' Lambda", "Pillai's Trace", "Hotelling-Lawley Trace", "Roy's Greatest Root" };
    for (names, st.statistics) |name, row| {
        try pad(a, out, name, 22, true);
        try pad(a, out, try fixed(a, row.value, 8), 16, false);
        try pad(a, out, try fixed(a, row.f, 2), 11, false);
        try pad(a, out, try fmt(a, row.numerator_df, "best6."), 10, false);
        try pad(a, out, try fmt(a, row.denominator_df, "best6."), 10, false);
        try pad(a, out, try pvalue(a, row.probability), 10, false);
        try out.append(a, '\n');
    }
    if (!exact) {
        try out.append(a, '\n');
        try centered(a, out, "NOTE: F Statistic for Roy's Greatest Root is an upper bound.", 79);
        if (st.statistics[0].inference == .exact_f) try centered(a, out, "NOTE: F Statistic for Wilks' Lambda is exact.", 79);
    }
}

const cancorr_header =
    "                                                                                                                 Test of H0: The canonical correlations in the\n" ++
    "                                                                          Eigenvalues of Inv(E)*H                  current row and all that follow are zero\n" ++
    "                          Adjusted  Approximate      Squared                = CanRsq/(1-CanRsq)\n" ++
    "            Canonical    Canonical     Standard    Canonical                                                  Likelihood  Approximate\n" ++
    "          Correlation  Correlation        Error  Correlation  Eigenvalue  Difference  Proportion  Cumulative       Ratio      F Value  Num DF  Den DF  Pr > F\n\n";

/// Adjusted canonical correlation (Lawley 1959): the first-order bias of r_i
/// removed, with p variables, q = c-1 hypothesis df and n = N-1. Missing when
/// the correction does not shrink r_i (near-equal or near-zero roots) or the
/// result exceeds the previous adjusted value (p.2167).
fn adjusted(a: A, rho: []const f64, p: usize, q: usize, n: f64) ![]f64 {
    const out = try a.alloc(f64, rho.len);
    var prev: f64 = std.math.inf(f64);
    for (rho, 0..) |ri, i| {
        var sum: f64 = 0;
        for (rho, 0..) |rj, j| if (j != i) {
            sum += rj * rj / (ri * ri - rj * rj);
        };
        const bracket = @as(f64, @floatFromInt(p + q)) - 2 - ri * ri + 2 * (1 - ri * ri) * sum;
        const v = ri - (1 - ri * ri) / (2 * n * ri) * bracket;
        if (!std.math.isFinite(v) or v > ri or v > prev) {
            out[i] = std.math.nan(f64);
        } else {
            out[i] = v;
            prev = v;
        }
    }
    return out;
}

fn canCorr(a: A, out: *Out, r: Result) !void {
    const p = r.p;
    const q = r.levels.len - 1;
    const m = @min(p, q);
    const dfe = r.nfreq - @as(f64, @floatFromInt(q + 1));
    const rho = try a.alloc(f64, m);
    var total: f64 = 0;
    for (0..m) |k| {
        rho[k] = @sqrt(r.roots[k] / (1 + r.roots[k]));
        total += r.roots[k];
    }
    const adj = try adjusted(a, rho, p, q, r.nfreq - 1);
    try out.appendSlice(a, cancorr_header);
    var cum: f64 = 0;
    for (0..m) |k| {
        const l = r.roots[k];
        const rsq = l / (1 + l);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 8, false);
        try pad(a, out, try fixed(a, rho[k], 6), 13, false);
        if (std.math.isNan(adj[k])) try out.appendSlice(a, "      .      ") else try pad(a, out, try fixed(a, adj[k], 6), 13, false);
        try pad(a, out, try fixed(a, (1 - rsq) / @sqrt(r.nfreq - 1), 6), 13, false);
        try pad(a, out, try fixed(a, rsq, 6), 13, false);
        try pad(a, out, try fixed(a, l, 4), 12, false);
        if (k + 1 < m) try pad(a, out, try fixed(a, l - r.roots[k + 1], 4), 12, false) else try out.appendNTimes(a, ' ', 12);
        cum += l / total;
        try pad(a, out, try fixed(a, l / total, 4), 12, false);
        try pad(a, out, try fixed(a, cum, 4), 12, false);
        // Likelihood ratio of rows k.. and Rao's F (p' = p-k, q' = q-k).
        var lambda: f64 = 1;
        for (k..m) |j| lambda /= 1 + r.roots[j];
        const pp: f64 = @floatFromInt(p - k);
        const qq: f64 = @floatFromInt(q - k);
        const rr = dfe - (pp - qq + 1) / 2;
        const u = (pp * qq - 2) / 4;
        const den = pp * pp + qq * qq - 5;
        const t = if (den > 0) @sqrt((pp * pp * qq * qq - 4) / den) else 1;
        const pw = std.math.pow(f64, lambda, 1 / t);
        const d1 = pp * qq;
        const d2 = rr * t - 2 * u;
        const f = (1 - pw) / pw * d2 / d1;
        try pad(a, out, try fixed(a, lambda, 8), 12, false);
        try pad(a, out, try fixed(a, f, 2), 13, false);
        try pad(a, out, try fmt(a, d1, "best6."), 8, false);
        try pad(a, out, try fmt(a, d2, "best6."), 8, false);
        try pad(a, out, try pvalue(a, fTail(f, d1, d2)), 8, false);
        try out.append(a, '\n');
    }
    if (r.stats.s == 1) try out.appendSlice(a, "\nNOTE: The F statistic is exact.\n");
}

fn varWidth(s: Spec) usize {
    var w: usize = "Variable".len;
    for (s.vars) |c| w = @max(w, s.ds.columns.items[c].name.len);
    return w;
}

fn canHeader(a: A, out: *Out, s: Spec, first: []const u8, w: usize, left: bool, ncan: usize) !void {
    try pad(a, out, first, w, left);
    for (0..ncan) |k| try pad(a, out, try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, k + 1 }), 18, false);
    try out.appendSlice(a, "\n\n");
}

/// Coefficient tables print 12 significant characters: the decimals are
/// shared by the whole table and leave room for a sign and the largest
/// integer part (calibrated on the reference listings).
fn sharedDecimals(values: []const f64) usize {
    var big: f64 = 0;
    for (values) |v| big = @max(big, @abs(v));
    var digits: usize = 1;
    var lim: f64 = 10;
    while (big >= lim and digits < 10) : (lim *= 10) digits += 1;
    return 10 - digits;
}

fn matrixTable(a: A, out: *Out, s: Spec, title: []const u8, values: []const f64, ncan: usize, dec: usize) !void {
    const w = varWidth(s);
    try centered(a, out, title, w + 18 * ncan);
    try out.appendSlice(a, " \n");
    try canHeader(a, out, s, "Variable", w, true, ncan);
    const p = s.vars.len;
    for (s.vars, 0..) |c, j| {
        try pad(a, out, s.ds.columns.items[c].name, w, true);
        for (0..ncan) |k| try pad(a, out, try fixed(a, values[k * p + j], dec), 18, false);
        try out.append(a, '\n');
    }
}

fn structure(a: A, r: Result, m: []const f64, ncan: usize) ![]f64 {
    // corr(x_j, z_k) under the SSCP matrix m: (M v)_j / sqrt(M_jj v'Mv).
    const p = r.p;
    const out = try a.alloc(f64, p * ncan);
    for (0..ncan) |k| {
        const v = r.raw[k * p .. k * p + p];
        const mv = try a.alloc(f64, p);
        var vmv: f64 = 0;
        for (0..p) |j| {
            var x: f64 = 0;
            for (0..p) |i| x += m[j * p + i] * v[i];
            mv[j] = x;
            vmv += v[j] * x;
        }
        for (0..p) |j| out[k * p + j] = mv[j] / @sqrt(m[j * p + j] * vmv);
    }
    return out;
}

fn accepts(cx: proc.ProcCtx, name: []const u8) bool {
    const l = cx.listing orelse return true;
    var buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "Candisc.{s}", .{name}) catch return true;
    return l.accepts(path);
}

fn page(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, rep: ?[]const Value) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
    if (s.by_cols.len > 0) {
        var line: Out = .empty;
        try by.appendLine(a, &line, s.ds, rep.?, s.by_cols);
        if (line.items.len > 0) {
            try out.append(a, '\n');
            try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
        }
    }
    try out.appendSlice(a, "\nThe CANDISC Procedure\n\n");
}

pub fn render(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, r: Result, rep: ?[]const Value) !void {
    const p = r.p;
    const ncan = @min(s.ncan orelse r.ncomp, r.ncomp);
    // Page 1: Counts, NObs, Levels.
    var body: Out = .empty;
    if (accepts(cx, "Counts")) try counts(a, &body, s, r);
    if (accepts(cx, "NObs")) {
        if (body.items.len > 0) try body.appendSlice(a, "\n\n");
        try nobs(a, &body, s, r);
    }
    if (accepts(cx, "Levels")) {
        if (body.items.len > 0) try body.appendSlice(a, "\n\n");
        try levelsTable(a, &body, s, r);
    }
    const pages = try a.alloc(Out, 5);
    for (pages) |*pg| pg.* = .empty;
    pages[0] = body;
    if (accepts(cx, "MultStat")) try multStat(a, &pages[1], r);
    if (accepts(cx, "CanCorr")) try canCorr(a, &pages[2], r);
    if (!s.short) {
        const sp = try a.alloc(f64, p * p);
        for (sp, r.e) |*x, e| x.* = e;
        const structs = [_]struct { []const u8, []const u8, []const f64 }{
            .{ "TStruc", "Total Canonical Structure", r.t },
            .{ "BStruc", "Between Canonical Structure", r.h },
            .{ "PStruc", "Pooled Within Canonical Structure", r.e },
        };
        for (structs) |st| if (accepts(cx, st[0])) {
            if (pages[3].items.len > 0) try pages[3].appendSlice(a, "\n\n");
            try matrixTable(a, &pages[3], s, st[1], try structure(a, r, st[2], ncan), ncan, 6);
        };
        const dfe = r.nfreq - @as(f64, @floatFromInt(r.levels.len));
        const tcoef = try a.alloc(f64, p * ncan);
        const pcoef = try a.alloc(f64, p * ncan);
        for (0..ncan) |k| for (0..p) |j| {
            tcoef[k * p + j] = r.raw[k * p + j] * @sqrt(r.t[j * p + j] / (r.nfreq - 1));
            pcoef[k * p + j] = r.raw[k * p + j] * @sqrt(r.e[j * p + j] / dfe);
        };
        const raw = r.raw[0 .. p * ncan];
        const coefs = [_]struct { []const u8, []const u8, []const f64 }{
            .{ "TCoef", "Total-Sample Standardized Canonical Coefficients", tcoef },
            .{ "PCoef", "Pooled Within-Class Standardized Canonical Coefficients", pcoef },
            .{ "RCoef", "Raw Canonical Coefficients", raw },
        };
        for (coefs) |co| if (accepts(cx, co[0])) {
            if (pages[4].items.len > 0) try pages[4].appendSlice(a, "\n\n");
            try matrixTable(a, &pages[4], s, co[1], co[2], ncan, sharedDecimals(co[2]));
        };
        if (accepts(cx, "CanonicalMeans")) {
            const means = try a.alloc(f64, r.levels.len * ncan);
            for (r.levels, 0..) |l, li| for (0..ncan) |k| {
                var z: f64 = 0;
                for (0..p) |j| z += (l.mean[j] - r.grand[j]) * r.raw[k * p + j];
                means[li * ncan + k] = z;
            };
            const dec = sharedDecimals(means);
            const pg = &pages[4];
            if (pg.items.len > 0) try pg.appendSlice(a, "\n\n");
            const w = levelWidth(s, r);
            try centered(a, pg, "Class Means on Canonical Variables", w + 18 * ncan);
            try pg.appendSlice(a, " \n");
            try canHeader(a, pg, s, s.ds.columns.items[s.class].name, w, s.ds.columns.items[s.class].type != .num, ncan);
            for (r.levels, 0..) |l, li| {
                try levelCell(a, pg, s, l.text, w);
                for (0..ncan) |k| try pad(a, pg, try fixed(a, means[li * ncan + k], dec), 18, false);
                try pg.append(a, '\n');
            }
        }
    }
    for (pages) |pg| if (pg.items.len > 0) {
        try page(a, cx, out, s, rep);
        try out.appendSlice(a, pg.items);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    };
}

fn warnings(cx: proc.ProcCtx, r: Result) !void {
    if (r.n_missing_vars > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group will not be included in the analysis due to missing values.", .{r.n_missing_vars});
    if (r.n_missing_class > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group are excluded from the development of the classification criterion due to missing values on CLASS variable.", .{r.n_missing_class});
    if (r.n_invalid > 0) try cx.diags.warnStatus(0, "{d} observations excluded due to invalid WEIGHT or FREQ variable values.", .{r.n_invalid});
    const excluded = r.n_missing_vars + r.n_missing_class + r.n_invalid;
    if (excluded > 0) try cx.diags.warnStatus(0, "A total of {d} of the {d} observations in the DATA= data set were excluded (frequency sum = {s}).", .{ excluded, r.n_read, std.mem.trim(u8, try format.apply(cx.arena, .{ .num = r.freq_used }, "best12."), " ") });
    for (r.levels) |l| if (l.freq == 1) {
        try cx.diags.warnStatus(0, "{s}={s} has only 1 value in DATA= data set or BY group.", .{ "CLASS", l.text });
        try cx.diags.warnStatus(0, "Within-class covariance matrix cannot be evaluated for CLASS={s} in DATA= data set or BY group.", .{l.text});
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (s.ds.rows.items.len == 0) {
        if (s.out != null) return gap(cx, 0, "OUT= for an empty input data set is not verified", .{});
        return cx.diags.note(0, "No observations in data set {s}.", .{try varlist.datasetName(a, s.ds)});
    }
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const results = try a.alloc(Result, slices.len);
    for (slices, results) |slice, *r| {
        r.* = analyze(a, s, slice.rows) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Empty => return gap(cx, 0, "a BY group or data set without usable observations is not verified", .{}),
            error.OneLevel => return gap(cx, 0, "a CLASS variable with fewer than two levels is not verified", .{}),
            error.NoDf => return gap(cx, 0, "an analysis without within-class degrees of freedom is not verified", .{}),
            error.Singular => return gap(cx, 0, "a singular within-class SSCP matrix (or zero weights) is not implemented", .{}),
        };
    }
    for (slices, results) |slice, r| {
        try warnings(cx, r);
        if (!s.noprint) try render(a, cx, out, s, r, slice.rep);
    }
    if (s.out) |member| {
        // OUT= (p.2163): input variables plus the canonical scores; without
        // NCAN= there are v score variables and the last v-(c-1) are missing.
        const p = s.vars.len;
        const nscore = if (s.ncan) |n| @min(n, p) else p;
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, member);
        for (s.ds.columns.items) |c| _ = try o.addColumnLike(c.name, c);
        for (0..nscore) |k| {
            const name = try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, k + 1 });
            if (s.ds.indexOf(name) != null) return gap(cx, 0, "canonical variable name {s} already exists on the input data set", .{name});
            _ = try o.addColumn(name, .num);
        }
        for (slices, results) |slice, r| for (slice.rows) |row| {
            const values = try a.alloc(Value, row.len + nscore);
            @memcpy(values[0..row.len], row);
            var complete = true;
            for (s.vars) |c| if (missing(row[c])) {
                complete = false;
            };
            for (0..nscore) |k| {
                if (!complete or k >= r.ncomp) {
                    values[row.len + k] = Value.missing;
                    continue;
                }
                var z: f64 = 0;
                for (s.vars, 0..) |c, j| z += (row[c].num - r.grand[j]) * r.raw[k * p + j];
                values[row.len + k] = .{ .num = z };
            }
            try o.appendRow(values);
        };
        try cx.lib.put(member, o);
        const upper = try std.ascii.allocUpperString(a, member);
        const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
    }
}

test {
    _ = @import("candisc_tests.zig");
}
