//! PROC NESTED statements, roles and the balanced default listing, SAS/STAT
//! 15.4 Chapter 87 (PROC NESTED statement pp.6969-6970, BY p.6970, CLASS
//! pp.6970-6971, VAR p.6971, Missing Values p.6971, Computational Method and
//! Displayed Output pp.6973-6975). `parse` records every documented
//! declaration; whatever has not been proven against a SAS reference listing
//! (long names; STAT-NESTED-003 added unbalanced designs and the analysis of
//! covariation, STAT-NESTED-004 the error terms and degenerate designs, all
//! verified against SAS 15.4 runs) is a D-009 gap (rc 2) raised before any
//! listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const reg_fit = @import("reg_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    aov: bool = false,
    /// CLASS variables in nesting order (dataset columns).
    class: []const usize = &.{},
    truncate: bool = false,
    /// VAR variables; empty until defaulted by `parse`.
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC NESTED: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC NESTED: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC NESTED: " ++ text, args);
}

/// Variables of a CLASS/VAR list between `start` and `end` (ranges allowed).
fn columns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize) diag.Error![]const usize {
    const a = cx.arena;
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        const line = t[j].line;
        const names = try lists.next(a, ds, t[0..end], &j, cx.diags);
        for (names) |n| {
            const c = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
            // Repeated names are accepted by SAS 15.4 (reference run); the
            // CLASS boundary is checked after every CLASS statement is read.
            try cols.append(a, c);
        }
    }
    return cols.items;
}

/// LABEL var='text' ... : labels do not appear in the NESTED listing (SAS
/// 15.4 reference run); an unknown variable is a WARNING, as in SAS.
fn labelStmt(cx: proc.ProcCtx, ds: *const Dataset, raw: *const Dataset, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    var j = start;
    if (j == end) return invalid(cx, t, j);
    while (j < end) {
        if (!at(t, j, .name)) return invalid(cx, t, j);
        if (!at(t, j + 1, .eq)) return invalid(cx, t, j + 1);
        if (ds.indexOf(t[j].text) == null)
            try cx.diags.warnStatus(t[j].line, "Variable {s} not found in data set {s}.", .{ try std.ascii.allocUpperString(cx.arena, t[j].text), try memberName(cx.arena, raw.name) });
        // Quoted or unquoted text (reference run: `label y=Yield of plot`)
        // runs to the next `name =` pair.
        j += 2;
        if (j >= end) return invalid(cx, t, j);
        j += 1;
        while (j < end and !(at(t, j, .name) and at(t, j + 1, .eq))) j += 1;
    }
}

fn memberName(a: A, name: []const u8) ![]const u8 {
    const up = try std.ascii.allocUpperString(a, name);
    return if (std.mem.indexOfScalar(u8, up, '.') != null) up else std.fmt.allocPrint(a, "WORK.{s}", .{up});
}

/// ATTRIB vars LABEL='text' FORMAT=fmt LENGTH=n INFORMAT=fmt ... : LABEL,
/// LENGTH and INFORMAT have no listing effect and FORMAT= groups CLASS levels
/// like the FORMAT statement; an unknown variable is a WARNING (SAS 15.4
/// reference runs). TRANSCODE= is not verified.
fn attribStmt(cx: proc.ProcCtx, ds: *const Dataset, raw: *const Dataset, t: []const lex.Token, start: usize, end: usize, formats: *std.ArrayList(proc.VarSpec)) diag.Error!void {
    const a = cx.arena;
    var j = start;
    var names: std.ArrayList([]const u8) = .empty;
    var attrs: usize = 0;
    while (j < end) {
        if (at(t, j, .name) and at(t, j + 1, .eq)) {
            if (names.items.len == 0) return invalid(cx, t, j);
            attrs += 1;
            if (kw(t, j, "label")) {
                if (!at(t, j + 2, .string)) return invalid(cx, t, j + 2);
                j += 3;
            } else if (kw(t, j, "length")) {
                var n: usize = 2;
                if (at(t, j + n, .dollar)) n += 1;
                if (!at(t, j + n, .number)) return invalid(cx, t, j + n);
                j += n + 1;
            } else if (kw(t, j, "format") or kw(t, j, "informat")) {
                var n: usize = 2;
                if (at(t, j + n, .dollar)) n += 1;
                if (at(t, j + n, .name) or at(t, j + n, .number)) n += 1;
                if (at(t, j + n, .dot)) n += 1;
                if (at(t, j + n, .number) and at(t, j + n - 1, .dot)) n += 1;
                var spec: std.ArrayList(u8) = .empty;
                for (t[j + 2 .. j + n]) |tk| switch (tk.tag) {
                    .dot => try spec.append(a, '.'),
                    .dollar => try spec.append(a, '$'),
                    else => try spec.appendSlice(a, tk.text),
                };
                if (std.mem.indexOfScalar(u8, spec.items, '.') == null) return invalid(cx, t, j + 2);
                if (kw(t, j, "format")) for (names.items) |nm| if (ds.indexOf(nm) != null)
                    try formats.append(a, .{ .name = nm, .spec = spec.items });
                j += n;
            } else return gap(cx, t[j].line, "the ATTRIB attribute {s}= is not implemented", .{try std.ascii.allocUpperString(a, t[j].text)});
        } else if (at(t, j, .name)) {
            if (attrs > 0) {
                names.clearRetainingCapacity();
                attrs = 0;
            }
            if (ds.indexOf(t[j].text) == null)
                try cx.diags.warnStatus(t[j].line, "Variable {s} not found in data set {s}.", .{ try std.ascii.allocUpperString(a, t[j].text), try memberName(a, raw.name) });
            try names.append(a, t[j].text);
            j += 1;
        } else return invalid(cx, t, j);
    }
    if (names.items.len > 0 and attrs == 0) return invalid(cx, t, end);
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
        } else if (eq(word, "aov")) {
            s.aov = true;
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
    var class_seen = false;
    var class_list: std.ArrayList(usize) = .empty;
    var var_list: std.ArrayList(usize) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
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
            // Several CLASS statements concatenate in order (SAS 15.4
            // reference run: `class a; class b;` lists as `class a b;`).
            class_seen = true;
            var slash = end;
            for (i + 1..end) |j| if (at(t, j, .slash)) {
                slash = j;
                break;
            };
            if (slash == i + 1) return invalid(cx, t, slash);
            try class_list.appendSlice(a, try columns(cx, s.ds, t, i + 1, slash));
            if (slash < end) {
                var j = slash + 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "truncate")) s.truncate = true else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "var")) {
            // Several VAR statements concatenate (SAS 15.4 reference run).
            s.var_given = true;
            if (end == i + 1) return invalid(cx, t, end);
            try var_list.appendSlice(a, try columns(cx, s.ds, t, i + 1, end));
        } else if (kw(t, i, "by")) {
            by_seen = true;
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            // Step boundary tokens may reach the body.
        } else if (kw(t, i, "where")) {
            // WHERE is applied by procInput.
        } else if (kw(t, i, "format")) {
            var j = i;
            try proc.parseProcFormat(a, t, &j, &formats);
        } else if (kw(t, i, "label")) {
            try labelStmt(cx, s.ds, raw, t, i + 1, end);
        } else if (kw(t, i, "attrib")) {
            try attribStmt(cx, s.ds, raw, t, i + 1, end, &formats);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    s.class = class_list.items;
    s.vars = var_list.items;
    // TRUNCATE on any CLASS statement applies to every CLASS variable (SAS
    // 15.4 reference run with the option on the first or the second one).
    // A CLASS variable listed again is a factor with zero degrees of
    // freedom (SAS 15.4 reference runs, STAT-NESTED-004).
    for (formats.items) |spec| if (s.ds.indexOf(spec.name) == null) return cx.diags.fail(error.ParseError, 0, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, spec.name)});
    s.ds = try by.withFormats(a, s.ds, formats.items);
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    // "You must include a CLASS statement" (p.6970).
    if (!class_seen) return user(cx, lineOf(t, 0), "a CLASS statement is required", .{});
    const cols = s.ds.columns.items;
    if (s.var_given) {
        for (s.vars) |v| {
            if (cols[v].type != .num) return user(cx, 0, "VAR variable {s} must be numeric", .{cols[v].name});
            for (s.class) |c| if (c == v) return user(cx, 0, "variable {s} cannot be both a CLASS and a VAR variable", .{cols[v].name});
        }
    } else {
        // No VAR statement: every numeric variable not in CLASS (p.6971).
        var vs: std.ArrayList(usize) = .empty;
        for (cols, 0..) |c, k| {
            if (c.type != .num) continue;
            if (std.mem.indexOfScalar(usize, s.class, k) != null) continue;
            // A numeric BY variable stays in the default list (SAS 15.4
            // reference run: it is analysed with zero variation).
            try vs.append(a, k);
        }
        if (vs.items.len == 0) return user(cx, 0, "there are no numeric analysis variables (no VAR statement and no numeric non-CLASS variables)", .{});
        s.vars = vs.items;
    }
    return s;
}

/// Execution boundary: only what the SAS reference listings prove.
fn boundary(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    const cols = s.ds.columns.items;
    for (s.class) |c| if (cols[c].name.len > 8) return gap(cx, 0, "listing layout for CLASS variable names longer than 8 characters ({s}) is not verified", .{cols[c].name});
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

/// Level key of a CLASS value: the full formatted value (first 16 characters
/// under TRUNCATE); unformatted numeric values compare raw.
fn levelKey(a: A, ds: *const Dataset, c: usize, v: Value, truncate: bool) !Value {
    const info = ds.columns.items[c];
    var text: []const u8 = undefined;
    if (info.format) |spec| {
        text = std.mem.trimEnd(u8, try format.apply(a, v, spec), " ");
    } else switch (v) {
        .num => return v,
        .str => |str| text = std.mem.trimEnd(u8, str, " "),
    }
    if (truncate and text.len > 16) text = text[0..16];
    return .{ .str = text };
}

/// One BY group, balanced nested design, per dependent variable results.
pub const Anova = struct {
    n: usize,
    /// Levels per factor (cumulative distinct runs), length k.
    levels: []const usize,
    df: []const usize, // k factors then error; total = n - 1
    ss: []const f64, // k factors then error
    total_ss: f64,
    mean: f64,
    coef: []const f64, // C_jj (diagonal of ems)
    /// Full EMS coefficient matrix: ems[i][j] is the coefficient of factor
    /// j's component in the expected mean square of factor i (0 for j < i).
    ems: []const []const f64 = &.{},
    balanced: bool = true,
    /// Sum over the cells of factor j of the squared cell size.
    sumsq: []const f64 = &.{},
};

pub const Design = struct {
    n: usize,
    levels: []const usize,
    /// cell[j][row] = cell index of factor j for the row.
    cell: []const []const u32,
    balanced: bool,
};

/// Levels are contiguous runs of the CLASS keys in data order, as the
/// one-pass algorithm of p.6973 accumulates them (a key that reappears after
/// a different key starts a new level, which SAS 15.4 also does).
pub fn design(a: A, keys: []const []const Value) !Design {
    const n = keys.len;
    const k = if (n == 0) 0 else keys[0].len;
    const cell = try a.alloc([]u32, k);
    const levels = try a.alloc(usize, k);
    for (cell) |*c| c.* = try a.alloc(u32, n);
    @memset(levels, 0);
    for (0..n) |r| {
        var changed = r == 0;
        for (0..k) |j| {
            if (!changed and proc.cmpValue(keys[r][j], keys[r - 1][j]) != .eq) changed = true;
            if (changed) levels[j] += 1;
            cell[j][r] = @intCast(levels[j] - 1);
        }
    }
    var balanced = true;
    for (0..k) |j| {
        const counts = try a.alloc(usize, levels[j]);
        @memset(counts, 0);
        for (cell[j]) |c| counts[c] += 1;
        for (counts) |x| if (x != counts[0]) {
            balanced = false;
        };
    }
    return .{ .n = n, .levels = levels, .cell = @ptrCast(cell), .balanced = balanced };
}

pub fn anova(a: A, d: Design, y: []const f64) !Anova {
    const k = d.levels.len;
    const n = d.n;
    var total: f64 = 0;
    for (y) |v| total += v;
    const mean = total / @as(f64, @floatFromInt(n));
    // Cell means per factor.
    const means = try a.alloc([]f64, k);
    for (0..k) |j| {
        const sums = try a.alloc(f64, d.levels[j]);
        const counts = try a.alloc(f64, d.levels[j]);
        @memset(sums, 0);
        @memset(counts, 0);
        for (y, d.cell[j]) |v, c| {
            sums[c] += v;
            counts[c] += 1;
        }
        for (sums, counts) |*s, c| s.* /= c;
        means[j] = sums;
    }
    const ss = try a.alloc(f64, k + 1);
    @memset(ss, 0);
    var total_ss: f64 = 0;
    for (y, 0..) |v, r| {
        total_ss += (v - mean) * (v - mean);
        var parent = mean;
        for (0..k) |j| {
            const m = means[j][d.cell[j][r]];
            ss[j] += (m - parent) * (m - parent);
            parent = m;
        }
        ss[k] += (v - parent) * (v - parent);
    }
    const df = try a.alloc(usize, k + 1);
    var prev: usize = 1;
    for (0..k) |j| {
        df[j] = d.levels[j] -| prev;
        prev = d.levels[j];
    }
    df[k] = n -| prev;
    const ems = try emsCoefficients(a, d, df);
    const coef = try a.alloc(f64, k);
    for (coef, 0..) |*c, j| c.* = ems[j][j];
    const sumsq = try a.alloc(f64, k);
    for (0..k) |j| {
        const cnt = try a.alloc(f64, d.levels[j]);
        @memset(cnt, 0);
        for (d.cell[j]) |c| cnt[c] += 1;
        sumsq[j] = 0;
        for (cnt) |x| sumsq[j] += x * x;
    }
    return .{ .sumsq = sumsq, .n = n, .levels = d.levels, .df = df, .ss = ss, .total_ss = total_ss, .mean = mean, .coef = coef, .ems = ems, .balanced = d.balanced };
}

/// General (unbalanced) EMS coefficients (Computational Method, p.6973):
/// E[SS_i] = sum_{j>=i} (S(i,j) - S(i-1,j)) s2_j + df_i s2, where
/// S(i,j) = sum over level-i cells c of (sum over level-j cells d in c of
/// n_d^2) / n_c and S(-1,j) = sum_d n_d^2 / n. Dividing by df_i gives the
/// coefficient of the mean square; balanced designs reduce to n / levels[j].
pub fn emsCoefficients(a: A, d: Design, df: []const usize) ![]const []const f64 {
    const k = d.levels.len;
    const counts = try a.alloc([]f64, k);
    const rep = try a.alloc([]usize, k);
    for (0..k) |j| {
        counts[j] = try a.alloc(f64, d.levels[j]);
        rep[j] = try a.alloc(usize, d.levels[j]);
        @memset(counts[j], 0);
        for (d.cell[j], 0..) |c, r| {
            if (counts[j][c] == 0) rep[j][c] = r;
            counts[j][c] += 1;
        }
    }
    const nf: f64 = @floatFromInt(d.n);
    const ems = try a.alloc([]f64, k);
    for (0..k) |i| {
        ems[i] = try a.alloc(f64, k);
        @memset(ems[i], 0);
    }
    for (0..k) |j| {
        // s_prev = S(i-1, j), starting at the whole sample.
        var sq: f64 = 0;
        for (counts[j]) |x| sq += x * x;
        var s_prev = sq / nf;
        for (0..j + 1) |i| {
            const acc = try a.alloc(f64, d.levels[i]);
            @memset(acc, 0);
            for (counts[j], rep[j]) |x, r| acc[d.cell[i][r]] += x * x;
            var s_cur: f64 = 0;
            for (acc, counts[i]) |x, nc| s_cur += x / nc;
            ems[i][j] = if (df[i] == 0) 0 else (s_cur - s_prev) / @as(f64, @floatFromInt(df[i]));
            s_prev = s_cur;
        }
    }
    return @ptrCast(ems);
}

pub const Derived = struct {
    ms: []const f64, // k factors then error
    comp: []const f64, // variance components, k factors then error
    total_comp: f64,
    f: []const f64, // k factors
    p: []const f64,
    se_mean: f64,
};

/// Balanced closed form: EMS of factor i is sum_{j>=i} C_jj s2_j + s2_e, so
/// s2_i = (MS_i - MS_{i+1}) / C_ii; F_i = MS_i / MS_{i+1} (p.6972). The total
/// component sums the nonnegative components (SAS 15.4 reference listings
/// print negative components with 0 percent).
pub fn derive(a: A, r: Anova) !Derived {
    const k = r.coef.len;
    const ms = try a.alloc(f64, k + 1);
    for (ms, r.ss, r.df) |*m, s, d| m.* = meanSquare(s, d);
    const comp = try components(a, r, ms);
    var total: f64 = 0;
    for (comp) |c| if (c > 0) {
        total += c;
    };
    // Error Terms in F Tests (p.6972): factor i is tested against the mean
    // square of factor i+1 (the last factor against Error), never skipping
    // a degenerate denominator. SAS 15.4 reference runs (STAT-NESTED-004)
    // print `.` when the factor or its denominator has zero degrees of
    // freedom or the denominator mean square is not positive.
    const f = try a.alloc(f64, k);
    const p = try a.alloc(f64, k);
    for (0..k) |j| {
        if (r.df[j] > 0 and r.df[j + 1] > 0 and ms[j + 1] > 0) {
            f[j] = ms[j] / ms[j + 1];
            p[j] = reg_fit.fProbability(f[j], r.df[j], r.df[j + 1]);
        } else {
            f[j] = std.math.nan(f64);
            p[j] = std.math.nan(f64);
        }
    }
    const nf: f64 = @floatFromInt(r.n);
    var se = @sqrt(ms[0] / nf);
    if (!r.balanced or degenerate(r)) {
        // Var(mean) = sum_j s2_j sum_d n_d^2 / n^2 + s2 / n with the signed
        // component estimates (zero for zero-df rows); reduces to MS_1 / n
        // when balanced. A negative estimate prints 0 (SAS 15.4 reference
        // runs, unbalanced one-factor design with equal group means).
        var v = comp[k] / nf;
        for (0..k) |j| v += comp[j] * r.sumsq[j] / (nf * nf);
        se = @sqrt(@max(v, 0));
    }
    return .{ .ms = ms, .comp = comp, .total_comp = total, .f = f, .p = p, .se_mean = se };
}

/// Mean square, missing (NaN, printed `.`) with zero degrees of freedom.
fn meanSquare(s: f64, df: usize) f64 {
    if (df == 0) return std.math.nan(f64);
    return s / @as(f64, @floatFromInt(df));
}

/// A factor or the error with zero degrees of freedom (a repeated CLASS
/// variable, one level per parent level, or one observation per cell).
pub fn degenerate(r: Anova) bool {
    for (r.df) |d| if (d == 0) return true;
    return false;
}

/// Components from mean squares (or mean products): balanced closed form
/// s2_i = (MS_i - MS_{i+1}) / C_ii; otherwise back substitution of
/// MS_i = sum_{j>=i} C_ij s2_j + s2 (p.6973).
pub fn components(a: A, r: Anova, ms: []const f64) ![]f64 {
    const k = r.coef.len;
    const comp = try a.alloc(f64, k + 1);
    // A row with zero degrees of freedom has component 0 and the others
    // are solved from the full EMS matrix (SAS 15.4 reference runs).
    const closed = (r.balanced and !degenerate(r)) or r.ems.len == 0;
    comp[k] = if (r.df[k] == 0) 0 else ms[k];
    var i = k;
    while (i > 0) {
        i -= 1;
        if (r.df[i] == 0) {
            comp[i] = 0;
        } else if (closed) {
            comp[i] = (ms[i] - ms[i + 1]) / r.coef[i];
        } else {
            var rest = ms[i] - comp[k];
            for (i + 1..k) |j| rest -= r.ems[i][j] * comp[j];
            comp[i] = rest / r.ems[i][i];
        }
    }
    return comp;
}

/// Analysis of covariation for one (y, z) pair (p.6972, p.6975).
pub const Covariation = struct {
    total_sp: f64,
    sp: []const f64, // k factors then error
    mp: []const f64,
    comp: []const f64,
    total_comp: f64, // signed sum of the covariance components
    vc_corr: []const f64, // k factors then error
    total_vc_corr: f64,
    ms_corr: []const f64,
    total_ms_corr: f64,
};

/// Sums of crossproducts with the same partition as the sums of squares of
/// `anova` (cell-mean deviations from the parent cell mean).
pub fn crossproducts(a: A, d: Design, y: []const f64, z: []const f64) !struct { total: f64, sp: []f64 } {
    const k = d.levels.len;
    const ym = try cellMeans(a, d, y);
    const zm = try cellMeans(a, d, z);
    var my: f64 = 0;
    var mz: f64 = 0;
    for (y, z) |u, v| {
        my += u;
        mz += v;
    }
    const nf: f64 = @floatFromInt(d.n);
    my /= nf;
    mz /= nf;
    const sp = try a.alloc(f64, k + 1);
    @memset(sp, 0);
    var total: f64 = 0;
    for (y, z, 0..) |u, v, r| {
        total += (u - my) * (v - mz);
        var py = my;
        var pz = mz;
        for (0..k) |j| {
            const cy = ym[j][d.cell[j][r]];
            const cz = zm[j][d.cell[j][r]];
            sp[j] += (cy - py) * (cz - pz);
            py = cy;
            pz = cz;
        }
        sp[k] += (u - py) * (v - pz);
    }
    return .{ .total = total, .sp = sp };
}

fn cellMeans(a: A, d: Design, y: []const f64) ![]const []const f64 {
    const means = try a.alloc([]f64, d.levels.len);
    for (0..d.levels.len) |j| {
        const sums = try a.alloc(f64, d.levels[j]);
        const counts = try a.alloc(f64, d.levels[j]);
        @memset(sums, 0);
        @memset(counts, 0);
        for (y, d.cell[j]) |v, c| {
            sums[c] += v;
            counts[c] += 1;
        }
        for (sums, counts) |*x, c| x.* /= c;
        means[j] = sums;
    }
    return @ptrCast(means);
}

/// Covariance components from mean products under the same EMS
/// coefficients; the variance-component correlation is 0 when either
/// variance component is not positive, and the Total row uses the signed
/// sums of all components (SAS 15.4 reference runs).
pub fn covariation(a: A, d: Design, ry: Anova, dy: Derived, rz: Anova, dz: Derived, y: []const f64, z: []const f64) !Covariation {
    const k = d.levels.len;
    const x = try crossproducts(a, d, y, z);
    const mp = try a.alloc(f64, k + 1);
    for (mp, x.sp, ry.df) |*m, s, df| m.* = meanSquare(s, df);
    const comp = try components(a, ry, mp);
    var total_comp: f64 = 0;
    var ty: f64 = 0;
    var tz: f64 = 0;
    for (comp, dy.comp, dz.comp) |c, cy, cz| {
        total_comp += c;
        ty += cy;
        tz += cz;
    }
    const vc = try a.alloc(f64, k + 1);
    const msc = try a.alloc(f64, k + 1);
    for (0..k + 1) |i| {
        // Zero-df rows print `.` for both correlations (reference runs).
        if (ry.df[i] == 0) {
            vc[i] = std.math.nan(f64);
            msc[i] = std.math.nan(f64);
            continue;
        }
        vc[i] = vcCorr(comp[i], dy.comp[i], dz.comp[i]);
        msc[i] = if (dy.ms[i] * dz.ms[i] > 0) mp[i] / @sqrt(dy.ms[i] * dz.ms[i]) else 0;
    }
    const nm1: f64 = @floatFromInt(d.n -| 1);
    const tvar = ry.total_ss / nm1 * (rz.total_ss / nm1);
    return .{
        .total_sp = x.total,
        .sp = x.sp,
        .mp = mp,
        .comp = comp,
        .total_comp = total_comp,
        .vc_corr = vc,
        // One observation: the Total row is missing too (reference run).
        .total_vc_corr = if (d.n < 2) std.math.nan(f64) else vcCorr(total_comp, ty, tz),
        .ms_corr = msc,
        .total_ms_corr = if (d.n < 2) std.math.nan(f64) else if (tvar > 0) (x.total / nm1) / @sqrt(tvar) else 0,
    };
}

fn vcCorr(c: f64, vy: f64, vz: f64) f64 {
    if (!(vy > 0) or !(vz > 0)) return 0;
    return c / @sqrt(vy * vz);
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

fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return std.fmt.allocPrint(a, "{d:.4}", .{p});
}

fn renderEms(a: A, out: *Out, names: []const []const u8, r: Anova) !void {
    if (!r.balanced) return renderEmsGeneral(a, out, names, r.ems, r.df);
    const coef = r.coef;
    // Column widths inferred from the SAS 15.4 reference listings: the
    // Source column is at least 6 wide; each coefficient column is the name
    // (at least 2) plus 6.
    // ponytail: widths for names of 7-8 characters are extrapolated.
    var src: usize = 6;
    for (names) |nm| src = @max(src, nm.len);
    var width = src;
    for (names) |nm| width += @max(nm.len, 2) + 6;
    width += 11;
    const title = "Coefficients of Expected Mean Squares";
    if (width >= title.len) {
        try centered(a, out, title, width);
    } else {
        // The reference listings break this title after "Expected".
        try centered(a, out, "Coefficients of Expected", width);
        try centered(a, out, "Mean Squares", width);
    }
    try out.appendSlice(a, " \n");
    try pad(a, out, "Source", src, true);
    for (names) |nm| try pad(a, out, nm, @max(nm.len, 2) + 6, false);
    try pad(a, out, "Error", 11, false);
    try out.appendSlice(a, "\n\n");
    const k = names.len;
    for (0..k + 1) |i| {
        try pad(a, out, if (i < k) names[i] else "Error", src, true);
        // A zero-df factor's row is all 0 (Error column included); its
        // column keeps the coefficients of the factors above it (SAS 15.4
        // reference runs).
        const zero = i < k and r.df[i] == 0;
        for (0..k) |j| {
            const c: f64 = if (zero or i > j) 0 else if (r.ems.len > 0) r.ems[i][j] else coef[j];
            try pad(a, out, try std.fmt.allocPrint(a, "{d:.0}", .{c}), @max(names[j].len, 2) + 6, false);
        }
        try pad(a, out, if (zero) "0" else "1", 11, false);
        try out.append(a, '\n');
    }
}

/// Unbalanced EMS table (SAS 15.4 reference runs): every value uses the
/// fewest decimals d <= 8 that show all coefficients exactly (8 otherwise);
/// with w the widest value, factor columns are max(w + 7, name + 6) wide, the
/// Error column max(w + 7, 11), the Source column max(6, longest name).
fn renderEmsGeneral(a: A, out: *Out, names: []const []const u8, ems: []const []const f64, df: []const usize) !void {
    var src: usize = 6;
    for (names) |nm| src = @max(src, nm.len);
    const k = names.len;
    var d: usize = 0;
    while (d < 8) : (d += 1) {
        const scale = std.math.pow(f64, 10, @floatFromInt(d));
        var exact = true;
        for (0..k) |i| for (i..k) |j| {
            const x = ems[i][j] * scale;
            if (@abs(x - @round(x)) > 1e-6) exact = false;
        };
        if (exact) break;
    }
    var w: usize = 0;
    for (0..k) |i| for (i..k) |j| {
        w = @max(w, (try std.fmt.allocPrint(a, "{[0]d:.[1]}", .{ ems[i][j], d })).len);
    };
    w = @max(w, (try std.fmt.allocPrint(a, "{[0]d:.[1]}", .{ @as(f64, 1), d })).len);
    const widths = try a.alloc(usize, k);
    var total = src;
    for (names, widths) |nm, *x| {
        x.* = @max(w + 7, nm.len + 6);
        total += x.*;
    }
    const ew = @max(w + 7, 11);
    total += ew;
    const title = "Coefficients of Expected Mean Squares";
    if (total >= title.len) {
        try centered(a, out, title, total);
    } else {
        // Narrow tables break the title as the balanced layout does (SAS
        // 15.4 reference run, unbalanced one-factor design).
        try centered(a, out, "Coefficients of Expected", total);
        try centered(a, out, "Mean Squares", total);
    }
    try out.appendSlice(a, " \n");
    try pad(a, out, "Source", src, true);
    for (names, widths) |nm, x| try pad(a, out, nm, x, false);
    try pad(a, out, "Error", ew, false);
    try out.appendSlice(a, "\n\n");
    for (0..k + 1) |i| {
        try pad(a, out, if (i < k) names[i] else "Error", src, true);
        for (0..k) |j| {
            const c: f64 = if (i < k and i <= j) ems[i][j] else 0;
            try pad(a, out, try std.fmt.allocPrint(a, "{[0]d:.[1]}", .{ c, d }), widths[j], false);
        }
        const one: f64 = if (i < k and df[i] == 0) 0 else 1;
        try pad(a, out, try std.fmt.allocPrint(a, "{[0]d:.[1]}", .{ one, d }), ew, false);
        try out.append(a, '\n');
    }
}

/// Six-decimal listing cell; an exact zero prints as `0` (SAS 15.4
/// reference runs of unbalanced designs with a zero sum of squares).
/// ponytail: exact float zero only, no fuzz.
fn six(a: A, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    if (x == 0) return "0";
    return std.fmt.allocPrint(a, "{d:.6}", .{x});
}

fn renderCovariation(a: A, out: *Out, names: []const []const u8, ny: []const u8, nz: []const u8, df: []const usize, n: usize, c: Covariation) !void {
    try out.appendSlice(a, "\n\n");
    try centered(a, out, try std.fmt.allocPrint(a, "Covariance of Variable {s} with {s}", .{ ny, nz }), 98);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "                                                                           Variance\n");
    try out.appendSlice(a, "Covariance                    Sum of                      Covariance      Component    Mean Square\n");
    try out.appendSlice(a, "Source            DF        Products    Mean Product       Component    Correlation    Correlation\n\n");
    const k = names.len;
    const tdf = n - 1;
    try covRow(a, out, "Total", tdf, if (tdf == 0) std.math.nan(f64) else c.total_sp, meanSquare(c.total_sp, tdf), c.total_comp, c.total_vc_corr, c.total_ms_corr);
    for (0..k + 1) |i| try covRow(a, out, if (i < k) names[i] else "Error", df[i], if (df[i] == 0) std.math.nan(f64) else c.sp[i], c.mp[i], c.comp[i], c.vc_corr[i], c.ms_corr[i]);
}

/// Four-decimal cell; missing prints `.` where the decimal point would be.
fn four(a: A, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return ".    ";
    return std.fmt.allocPrint(a, "{d:.4}", .{x});
}

fn covRow(a: A, out: *Out, name: []const u8, df: usize, sp: f64, mp: f64, comp: f64, vc: f64, msc: f64) !void {
    try pad(a, out, name, 12, true);
    try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{df}), 8, false);
    try pad(a, out, try six(a, sp), 16, false);
    try pad(a, out, try six(a, mp), 16, false);
    try pad(a, out, try six(a, comp), 16, false);
    try pad(a, out, try four(a, vc), 15, false);
    try pad(a, out, try four(a, msc), 15, false);
    try out.append(a, '\n');
}

fn renderAnova(a: A, out: *Out, names: []const []const u8, dep: []const u8, r: Anova, d: Derived) !void {
    const k = names.len;
    // The Error Term column is the longest CLASS name (at least 5) plus 3
    // wide, as in the SAS 15.4 reference listings.
    var term: usize = 5;
    for (names) |nm| term = @max(term, nm.len);
    term += 3;
    try out.appendSlice(a, "\n\n");
    try centered(a, out, try std.fmt.allocPrint(a, "Nested Random Effects Analysis of Variance for Variable {s}", .{dep}), 100 + term);
    try out.appendSlice(a, " \n");
    try out.appendSlice(a, "Variance                    Sum of                         Error   ");
    try out.appendNTimes(a, ' ', term);
    try out.appendSlice(a, "             Variance     Percent\n");
    try out.appendSlice(a, "Source          DF         Squares    F Value    Pr > F    ");
    try pad(a, out, "Term", term, true);
    try out.appendSlice(a, "  Mean Square       Component    of Total\n\n");
    const nan = std.math.nan(f64);
    const tdf = r.n - 1;
    try row(a, out, term, "Total", tdf, if (tdf == 0) nan else r.total_ss, null, null, meanSquare(r.total_ss, tdf), d.total_comp, if (d.total_comp > 0) 100 else 0);
    for (0..k + 1) |i| {
        const pct = if (d.comp[i] > 0) 100 * d.comp[i] / d.total_comp else 0;
        // Unbalanced Data (p.6971): the F test columns are left blank;
        // balanced rows without a valid test print `.` (derive).
        const shown = i < k and r.balanced;
        const tested = shown and !std.math.isNan(d.f[i]);
        const test_: ?Test = if (shown) .{ .f = d.f[i], .p = d.p[i] } else null;
        try row(a, out, term, if (i < k) names[i] else "Error", r.df[i], if (r.df[i] == 0) nan else r.ss[i], test_, if (tested) (if (i + 1 < k) names[i + 1] else "Error") else null, d.ms[i], d.comp[i], pct);
    }
    try out.appendSlice(a, "\n\n");
    const se_label = try std.fmt.allocPrint(a, "Standard Error of {s} Mean", .{dep});
    const mean_label = try std.fmt.allocPrint(a, "{s} Mean", .{dep});
    const lw = se_label.len;
    // The value field is 18 wide after the longer label (reference listings).
    const field = 18;
    try pad(a, out, mean_label, lw, true);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.8}", .{r.mean}), field, false);
    try out.append(a, '\n');
    try pad(a, out, se_label, lw, true);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.8}", .{d.se_mean}), field, false);
    try out.append(a, '\n');
}

const Test = struct { f: f64, p: f64 };

fn row(a: A, out: *Out, term_width: usize, name: []const u8, df: usize, ss: f64, t: ?Test, term: ?[]const u8, ms: f64, comp: f64, pct: f64) !void {
    try pad(a, out, name, 12, true);
    try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{df}), 6, false);
    try pad(a, out, try six(a, ss), 16, false);
    if (t) |x| {
        if (std.math.isNan(x.f)) {
            try pad(a, out, ".  ", 11, false);
            try pad(a, out, ".    ", 10, false);
        } else {
            try pad(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{x.f}), 11, false);
            try pad(a, out, try pvalue(a, x.p), 10, false);
        }
    } else try out.appendNTimes(a, ' ', 21);
    try out.appendSlice(a, "    ");
    try pad(a, out, term orelse "", term_width, true);
    try pad(a, out, try six(a, ms), 13, false);
    try pad(a, out, try six(a, comp), 16, false);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{pct}), 12, false);
    try out.append(a, '\n');
}

const Group = struct { design: Design, results: []const Anova, derived: []const Derived, ys: []const []const f64 = &.{}, empty: bool = false };

fn analyze(cx: proc.ProcCtx, s: Spec, rows_in: []const []const Value) diag.Error!Group {
    const a = cx.arena;
    var rows: std.ArrayList([]const Value) = .empty;
    // Missing Values (p.6971): any CLASS or VAR variable missing omits the
    // observation; blank character CLASS values are missing.
    for (rows_in) |r| {
        var skip = false;
        for (s.class) |c| if (missing(r[c])) {
            skip = true;
        };
        for (s.vars) |v| if (missing(r[v])) {
            skip = true;
        };
        if (!skip) try rows.append(a, r);
    }
    // Every observation omitted: SAS 15.4 warns, lists nothing for this
    // BY group or data set, and goes on (reference run).
    if (rows.items.len == 0) return .{ .design = undefined, .results = &.{}, .derived = &.{}, .empty = true };
    const keys = try a.alloc([]Value, rows.items.len);
    for (rows.items, keys) |r, *kk| {
        kk.* = try a.alloc(Value, s.class.len);
        for (s.class, kk.*) |c, *v| v.* = try levelKey(a, s.ds, c, r[c], s.truncate);
    }
    const d = try design(a, @ptrCast(keys));
    // Unbalanced Data (p.6971): warn in the log, estimate the components,
    // leave the F test columns blank.
    // (The WARNING itself is issued by `run`, with the BY-group NOTE.)

    // Degenerate designs (STAT-NESTED-004): a factor or the error with zero
    // degrees of freedom, zero mean squares, a zero total, are listed with
    // `.` cells and zero components as SAS 15.4 does (derive, renderAnova).
    const results = try a.alloc(Anova, s.vars.len);
    const derived = try a.alloc(Derived, s.vars.len);
    const ys = try a.alloc([]f64, s.vars.len);
    for (s.vars, results, derived, ys) |v, *res, *der, *yv| {
        const y = try a.alloc(f64, d.n);
        yv.* = y;
        for (rows.items, y) |r, *x| x.* = r[v].num;
        res.* = try anova(a, d, y);
        der.* = try derive(a, res.*);
    }
    return .{ .design = d, .results = results, .derived = derived, .ys = @ptrCast(ys) };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    try boundary(cx, s);
    // An input data set without observations produces no listing and no
    // diagnostic in SAS 15.4 (reference run).
    if (s.ds.rows.items.len == 0) return;
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    for (slices, groups) |slice, *g| {
        g.* = try analyze(cx, s, slice.rows);
        if (g.empty) {
            try cx.diags.warnStatus(0, "All observations contain missing data.", .{});
            if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, s.ds, slice.rep.?, s.by_cols);
        } else if (!g.design.balanced) {
            try cx.diags.warnStatus(0, "The design is not balanced--F tests cannot be computed.", .{});
            if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, s.ds, slice.rep.?, s.by_cols);
        }
    }
    const cols = s.ds.columns.items;
    const names = try a.alloc([]const u8, s.class.len);
    for (s.class, names) |c, *nm| nm.* = cols[c].name;
    for (slices, groups) |slice, g| {
        if (g.empty) continue;
        if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
        if (s.by_cols.len > 0) {
            var line: Out = .empty;
            try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
            }
        }
        try out.appendSlice(a, "\nThe NESTED Procedure\n\n");
        try renderEms(a, out, names, g.results[0]);
        for (s.vars, g.results, g.derived) |v, r, d| try renderAnova(a, out, names, cols[v].name, r, d);
        // Analysis of Covariation (p.6972): every pair in VAR order, unless AOV.
        if (!s.aov) for (0..s.vars.len) |i| for (i + 1..s.vars.len) |j| {
            const c = try covariation(a, g.design, g.results[i], g.derived[i], g.results[j], g.derived[j], g.ys[i], g.ys[j]);
            try renderCovariation(a, out, names, cols[s.vars[i]].name, cols[s.vars[j]].name, g.results[i].df, g.design.n, c);
        };
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    }
}

test {
    _ = @import("nested_tests.zig");
}
