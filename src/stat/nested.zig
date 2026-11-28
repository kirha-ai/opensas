//! PROC NESTED statements, roles and the balanced default listing, SAS/STAT
//! 15.4 Chapter 87 (PROC NESTED statement pp.6969-6970, BY p.6970, CLASS
//! pp.6970-6971, VAR p.6971, Missing Values p.6971, Computational Method and
//! Displayed Output pp.6973-6975). `parse` records every documented
//! declaration; whatever has not been proven against a SAS reference listing
//! (unbalanced designs, the analysis of covariation, long names) is a D-009
//! gap (rc 2) raised before any listing text is produced.
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
fn columns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, what: []const u8) diag.Error![]const usize {
    const a = cx.arena;
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        const line = t[j].line;
        const names = try lists.next(a, ds, t[0..end], &j, cx.diags);
        for (names) |n| {
            const c = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
            for (cols.items) |prev| if (prev == c) return user(cx, line, "variable {s} appears more than once in the {s} statement", .{ ds.columns.items[c].name, what });
            try cols.append(a, c);
        }
    }
    return cols.items;
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
            if (class_seen) return gap(cx, t[i].line, "more than one CLASS statement is not implemented", .{});
            class_seen = true;
            var slash = end;
            for (i + 1..end) |j| if (at(t, j, .slash)) {
                slash = j;
                break;
            };
            if (slash == i + 1) return invalid(cx, t, slash);
            s.class = try columns(cx, s.ds, t, i + 1, slash, "CLASS");
            if (slash < end) {
                var j = slash + 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "truncate")) s.truncate = true else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "var")) {
            if (s.var_given) return gap(cx, t[i].line, "more than one VAR statement is not implemented", .{});
            s.var_given = true;
            if (end == i + 1) return invalid(cx, t, end);
            s.vars = try columns(cx, s.ds, t, i + 1, end, "VAR");
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
        } else if (kw(t, i, "label") or kw(t, i, "attrib")) {
            return gap(cx, t[i].line, "the {s} statement is not implemented", .{try std.ascii.allocUpperString(a, t[i].text)});
        } else return invalid(cx, t, i);
        i = end + 1;
    }
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
            if (std.mem.indexOfScalar(usize, s.by_cols, k) != null)
                return gap(cx, 0, "a default VAR list containing the numeric BY variable {s} is not verified", .{c.name});
            try vs.append(a, k);
        }
        if (vs.items.len == 0) return user(cx, 0, "there are no numeric analysis variables (no VAR statement and no numeric non-CLASS variables)", .{});
        s.vars = vs.items;
    }
    return s;
}

/// Execution boundary: only what the SAS reference listings prove.
fn boundary(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    if (s.vars.len > 1 and !s.aov) return gap(cx, 0, "the analysis of covariation for more than one dependent variable is not implemented (STAT-NESTED-003); specify AOV or one VAR variable", .{});
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
    coef: []const f64, // C_jj = n / levels[j]
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
    const coef = try a.alloc(f64, k);
    for (coef, d.levels) |*c, l| c.* = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(l));
    return .{ .n = n, .levels = d.levels, .df = df, .ss = ss, .total_ss = total_ss, .mean = mean, .coef = coef };
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
    for (ms, r.ss, r.df) |*m, s, d| m.* = s / @as(f64, @floatFromInt(d));
    const comp = try a.alloc(f64, k + 1);
    comp[k] = ms[k];
    var i = k;
    while (i > 0) {
        i -= 1;
        comp[i] = (ms[i] - ms[i + 1]) / r.coef[i];
    }
    var total: f64 = 0;
    for (comp) |c| if (c > 0) {
        total += c;
    };
    const f = try a.alloc(f64, k);
    const p = try a.alloc(f64, k);
    for (0..k) |j| {
        f[j] = ms[j] / ms[j + 1];
        p[j] = reg_fit.fProbability(f[j], r.df[j], r.df[j + 1]);
    }
    return .{ .ms = ms, .comp = comp, .total_comp = total, .f = f, .p = p, .se_mean = @sqrt(ms[0] / @as(f64, @floatFromInt(r.n))) };
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

fn renderEms(a: A, out: *Out, names: []const []const u8, coef: []const f64) !void {
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
        for (0..k) |j| {
            const c: f64 = if (i <= j) coef[j] else 0;
            try pad(a, out, try std.fmt.allocPrint(a, "{d:.0}", .{c}), @max(names[j].len, 2) + 6, false);
        }
        try pad(a, out, "1", 11, false);
        try out.append(a, '\n');
    }
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
    const total_ms = r.total_ss / @as(f64, @floatFromInt(r.n - 1));
    try row(a, out, term, "Total", r.n - 1, r.total_ss, null, null, total_ms, d.total_comp, 100);
    for (0..k + 1) |i| {
        const pct = if (d.comp[i] > 0) 100 * d.comp[i] / d.total_comp else 0;
        const test_: ?Test = if (i < k) .{ .f = d.f[i], .p = d.p[i] } else null;
        try row(a, out, term, if (i < k) names[i] else "Error", r.df[i], r.ss[i], test_, if (i < k) (if (i + 1 < k) names[i + 1] else "Error") else null, d.ms[i], d.comp[i], pct);
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
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{ss}), 16, false);
    if (t) |x| {
        try pad(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{x.f}), 11, false);
        try pad(a, out, try pvalue(a, x.p), 10, false);
    } else try out.appendNTimes(a, ' ', 21);
    try out.appendSlice(a, "    ");
    try pad(a, out, term orelse "", term_width, true);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{ms}), 13, false);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{comp}), 16, false);
    try pad(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{pct}), 12, false);
    try out.append(a, '\n');
}

const Group = struct { design: Design, results: []const Anova, derived: []const Derived };

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
    if (rows.items.len == 0) return gap(cx, 0, "the result for a BY group or data set without usable observations is not verified", .{});
    const keys = try a.alloc([]Value, rows.items.len);
    for (rows.items, keys) |r, *kk| {
        kk.* = try a.alloc(Value, s.class.len);
        for (s.class, kk.*) |c, *v| v.* = try levelKey(a, s.ds, c, r[c], s.truncate);
    }
    const d = try design(a, @ptrCast(keys));
    if (!d.balanced) return gap(cx, 0, "unbalanced nested designs are not implemented (STAT-NESTED-003)", .{});
    var prev: usize = 1;
    for (d.levels) |l| {
        if (l <= prev) return gap(cx, 0, "a classification factor with zero degrees of freedom is not implemented", .{});
        prev = l;
    }
    if (d.n <= prev) return gap(cx, 0, "a design with zero error degrees of freedom is not implemented", .{});
    const results = try a.alloc(Anova, s.vars.len);
    const derived = try a.alloc(Derived, s.vars.len);
    for (s.vars, results, derived) |v, *res, *der| {
        const y = try a.alloc(f64, d.n);
        for (rows.items, y) |r, *x| x.* = r[v].num;
        res.* = try anova(a, d, y);
        der.* = try derive(a, res.*);
        for (der.ms[1..]) |m| if (!(m > 0)) return gap(cx, 0, "an F test with a zero denominator mean square is not implemented", .{});
        if (!(der.total_comp > 0)) return gap(cx, 0, "a zero total variance component is not implemented", .{});
    }
    return .{ .design = d, .results = results, .derived = derived };
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
    for (slices, groups) |slice, *g| g.* = try analyze(cx, s, slice.rows);
    const cols = s.ds.columns.items;
    const names = try a.alloc([]const u8, s.class.len);
    for (s.class, names) |c, *nm| nm.* = cols[c].name;
    for (slices, groups) |slice, g| {
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
        try renderEms(a, out, names, g.results[0].coef);
        for (s.vars, g.results, g.derived) |v, r, d| try renderAnova(a, out, names, cols[v].name, r, d);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    }
}

test {
    _ = @import("nested_tests.zig");
}
