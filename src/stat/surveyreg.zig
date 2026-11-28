//! PROC SURVEYREG declarations, variable roles, observation selection and the
//! default listing (Data Summary, Design Summary, Fit Statistics, Class Level
//! Information, Stratum Information, Tests of Model Effects, Estimated
//! Regression Coefficients), SAS/STAT 15.4 chapter 123, physical
//! pp.10113-10143. Weighted least squares with a sweep generalized inverse and
//! the Taylor-series (linearization) sandwich variance of survey_design.zig.
//! Every documented feature whose result or layout has not been checked
//! against a reference is a D-009 gap (rc 2) raised before any listing text.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const ods_table = @import("ods_table.zig");
const design = @import("survey_design.zig");
const means = @import("surveymeans.zig");
const reg_fit = @import("reg_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    dependent: usize = 0,
    /// MODEL effects in order: each a single variable (main effects only).
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    solution: bool = false,
    weight: ?usize = null,
    strata: []const usize = &.{},
    clusters: []const usize = &.{},
    list: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    missing: bool = false,
    alpha: f64 = 0.05,
    population: means.Population = .none,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// PROC statement options owned by later SURVEYREG tickets (physical
/// pp.10113-10124).
const later_options = [_][]const u8{ "nomcar", "plots", "plot", "order", "varmethod", "df", "nosparse" };
/// Statements documented for SURVEYREG that later tickets implement.
const later_statements = [_][]const u8{ "domain", "repweights", "contrast", "effect", "estimate", "lsmeans", "lsmestimate", "output", "slice", "store", "test", "freq" };
/// MODEL options (physical pp.10130-10136) owned by later tickets.
const later_model_options = [_][]const u8{ "adjrsq", "anova", "clparm", "covb", "deff", "df", "i", "inverse", "noint", "parmlabel", "vadjust", "xpx", "corrb", "clm" };

fn number(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!f64 {
    if (!at(t, i, .number)) return invalid(cx, t, i);
    return std.fmt.parseFloat(f64, t[i].text) catch invalid(cx, t, i);
}

fn columns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, stop: *usize) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end and !at(t, j, .slash)) : (j += 1) {
        if (!at(t, j, .name)) {
            if (at(t, j, .minus) or at(t, j, .colon)) return gap(cx, t[j].line, "variable list shorthand is not implemented", .{});
            if (at(t, j, .star) or at(t, j, .lparen) or at(t, j, .at) or at(t, j, .pipe)) return gap(cx, t[j].line, "crossed, nested or bar effects are not implemented", .{});
            return invalid(cx, t, j);
        }
        if (oneOf(t[j].text, &.{ "_numeric_", "_character_", "_all_" })) return gap(cx, t[j].line, "variable list shorthand is not implemented", .{});
        const c = ds.indexOf(t[j].text) orelse return cx.diags.fail(error.ParseError, t[j].line, "Variable {s} not found.", .{t[j].text});
        if (std.mem.indexOfScalar(usize, cols.items, c) == null) try cols.append(cx.arena, c);
    }
    stop.* = j;
    return cols.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var total_name: ?[]const u8 = null;
    var total_line: usize = 0;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (name != null) return invalid(cx, t, i);
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if ((eq(word, "total") or eq(word, "n")) and at(t, i + 1, .eq)) {
            if (s.population != .none or total_name != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: only one of TOTAL= and RATE= may be specified", .{});
            if (at(t, i + 2, .name)) {
                total_name = t[i + 2].text;
                total_line = t[i].line;
                i += 3;
                if (at(t, i, .dot)) {
                    if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                    total_name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ total_name.?, t[i + 1].text });
                    i += 2;
                }
            } else {
                if (at(t, i + 3, .number)) return gap(cx, t[i].line, "TOTAL= value list for strata is not implemented", .{});
                const x = try number(cx, t, i + 2);
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: TOTAL= must be positive", .{});
                s.population = .{ .total = x };
                i += 3;
            }
        } else if ((eq(word, "rate") or eq(word, "r")) and at(t, i + 1, .eq)) {
            if (s.population != .none or total_name != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: only one of TOTAL= and RATE= may be specified", .{});
            if (at(t, i + 2, .name)) return gap(cx, t[i].line, "RATE= data set is not implemented", .{});
            if (at(t, i + 3, .number)) return gap(cx, t[i].line, "RATE= value list for strata is not implemented", .{});
            const x = try number(cx, t, i + 2);
            // A proportion in (0,1), or a percentage in [1,100].
            if (!(x > 0 and x <= 100)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: RATE= must be a positive proportion or percentage", .{});
            s.population = .{ .rate = if (x < 1) x else x / 100 };
            i += 3;
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            const x = try number(cx, t, i + 2);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
            i += 3;
        } else if (eq(word, "missing")) {
            s.missing = true;
            i += 1;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: input dataset not found", .{});
    if (total_name) |n| s.population = .{ .total_data = cx.lib.find(n) orelse return cx.diags.fail(error.ParseError, total_line, "PROC SURVEYREG: TOTAL= data set {s} not found", .{n}) };
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        var stop: usize = end;
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "more than one MODEL statement is not implemented", .{});
            model_seen = true;
            if (!at(t, i + 1, .name) or !at(t, i + 2, .eq)) return invalid(cx, t, i + 1);
            const dep = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[dep].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: the dependent variable {s} must be numeric", .{t[i + 1].text});
            s.dependent = dep;
            s.effects = try columns(cx, ds, t, i + 3, end, &stop);
            if (s.effects.len == 0) return gap(cx, t[i].line, "an intercept-only MODEL is not implemented", .{});
            if (stop != end) {
                var j = stop + 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "solution") or kw(t, j, "s")) {
                        s.solution = true;
                    } else if (at(t, j, .name) and oneOf(t[j].text, &later_model_options)) {
                        return gap(cx, t[j].line, "MODEL option {s} is not implemented", .{t[j].text});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "class")) {
            const cols = try columns(cx, ds, t, i + 1, end, &stop);
            if (stop != end) return gap(cx, t[stop].line, "CLASS statement options are not implemented", .{});
            if (cols.len == 0) return invalid(cx, t, stop);
            for (cols) |c| if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            const c = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYREG: WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.weight = c;
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            if (s.strata.len > 0) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            s.strata = try columns(cx, ds, t, i + 1, end, &stop);
            if (s.strata.len == 0) return invalid(cx, t, stop);
            if (stop != end) {
                var j = stop + 1;
                if (j == end) return invalid(cx, t, j);
                while (j < end) : (j += 1) {
                    if (kw(t, j, "list")) s.list = true else if (kw(t, j, "nocollapse")) return gap(cx, t[j].line, "STRATA option NOCOLLAPSE is not implemented", .{}) else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            if (s.clusters.len > 0) return gap(cx, t[i].line, "duplicate CLUSTER statement policy is not verified", .{});
            s.clusters = try columns(cx, ds, t, i + 1, end, &stop);
            if (stop != end or s.clusters.len == 0) return invalid(cx, t, stop);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: a MODEL statement is required", .{});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const by_cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| by_cols[k] = ds.indexOf(n).?;
    s.by_cols = by_cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    for (classes.items) |c| if (ds.columns.items[c].format != null) return gap(cx, 0, "formatted CLASS levels are not implemented", .{});
    s.classes = classes.items;
    for (s.effects) |c| {
        if (std.mem.indexOfScalar(usize, s.classes, c) == null and ds.columns.items[c].type != .num)
            return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: variable {s} in the MODEL statement must be numeric or a CLASS variable", .{ds.columns.items[c].name});
    }
    return s;
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// Sweep generalized inverse (in column order) of a symmetric p x p matrix,
/// in place. A pivot at most 1e-9 times its original diagonal marks the
/// column as aliased: its row and column become zero (the G2 inverse GLM uses).
pub fn sweepInverse(a: A, m: []f64, p: usize, aliased: []bool) !void {
    const orig = try a.alloc(f64, p);
    defer a.free(orig);
    for (0..p) |k| orig[k] = m[k * p + k];
    for (0..p) |k| {
        const d = m[k * p + k];
        if (!(@abs(d) > 1e-9 * @abs(orig[k])) or orig[k] == 0) {
            aliased[k] = true;
            for (0..p) |j| {
                m[k * p + j] = 0;
                m[j * p + k] = 0;
            }
            continue;
        }
        aliased[k] = false;
        for (0..p) |j| if (j != k) {
            m[k * p + j] /= d;
        };
        for (0..p) |i| {
            if (i == k) continue;
            const b = m[i * p + k];
            if (b == 0) continue;
            for (0..p) |j| if (j != k) {
                m[i * p + j] -= b * m[k * p + j];
            };
            m[i * p + k] = -b / d;
        }
        m[k * p + k] = 1 / d;
    }
}

const Column = struct {
    /// Model effect index; null is the intercept.
    effect: ?usize,
    label: []const u8,
    /// CLASS level value for a dummy column.
    level: ?Value = null,
};

/// Decimals of the Estimate column: every estimate fits 10 characters, so
/// the widest integer part (plus its sign) fixes the decimals for the whole
/// column: -26.084677 (6) and 0.73333333 (8) in the SAS listings.
/// ponytail: verified for widths 1 and 2+sign; |b| >= 1000 is gapped upstream.
fn estimateDecimals(b: []const f64, aliased: []const bool) usize {
    var need: usize = 1;
    for (b, aliased) |x, al| {
        if (al) continue;
        var digits: usize = 1;
        var m = @floor(@abs(x));
        while (m >= 10) : (m = @floor(m / 10)) digits += 1;
        need = @max(need, digits + @intFromBool(x < 0));
    }
    return 9 - need;
}

test "STAT-SURVEYREG-001 estimate column decimals follow the widest estimate" {
    try std.testing.expectEqual(@as(usize, 6), estimateDecimals(&.{ -26.08, 0.77, 0 }, &.{ false, false, true }));
    try std.testing.expectEqual(@as(usize, 8), estimateDecimals(&.{ 0.73, 1.17 }, &.{ false, false }));
}

const Test = struct { label: []const u8, df: usize, f: f64 };

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn count(a: A, n: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{n});
}
fn levelText(a: A, v: Value) ![]const u8 {
    return std.mem.trim(u8, try proc.cellText(a, v), " ");
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = p }, "PVALUE6.4"), " ");
}
/// Two-column label/value table (Data, Design Summary, Fit Statistics).
fn summary(a: A, out: *Out, title: []const u8, labels: []const []const u8, values: []const []const u8, value_width: usize) !void {
    var lw: usize = 0;
    for (labels) |l| lw = @max(lw, l.len);
    try out.appendSlice(a, "\n\n");
    try centered(a, out, title, lw + value_width);
    try out.append(a, '\n');
    for (labels, values) |l, v| {
        try left(a, out, l, lw);
        try right(a, out, v, value_width);
        try out.append(a, '\n');
    }
}

/// Solve the q x q system by a full inverse; null when L V L' is singular.
fn waldF(a: A, lrows: []const []const f64, b: []const f64, v: []const f64, p: usize) !?f64 {
    const q = lrows.len;
    const lb = try a.alloc(f64, q);
    for (lrows, lb) |l, *x| {
        x.* = 0;
        for (l, b) |c, bb| x.* += c * bb;
    }
    const m = try a.alloc(f64, q * q);
    for (lrows, 0..) |li, r| for (lrows, 0..) |lj, c| {
        var acc: f64 = 0;
        for (0..p) |x| for (0..p) |y| {
            acc += li[x] * v[x * p + y] * lj[y];
        };
        m[r * q + c] = acc;
    };
    const al = try a.alloc(bool, q);
    try sweepInverse(a, m, q, al);
    for (al) |x| if (x) return null;
    var stat: f64 = 0;
    for (0..q) |r| for (0..q) |c| {
        stat += lb[r] * m[r * q + c] * lb[c];
    };
    return stat / @as(f64, @floatFromInt(q));
}

/// One BY group (or the whole input): design, fit, listing, ODS.
fn analyze(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value, rep: ?[]const Value) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const sel = try means.select(a, .{ .input = s.input, .weight = s.weight, .strata = s.strata, .clusters = s.clusters, .missing = s.missing }, rows);
    if (sel.rows.len != sel.read) return gap(cx, 0, "the listing for input with observations excluded by missing or nonpositive WEIGHT, STRATA or CLUSTER values is not verified", .{});
    for (sel.rows) |row| {
        if (isMissing(row[s.dependent])) return gap(cx, 0, "observations with missing model variables are not implemented", .{});
        for (s.effects) |c| if (isMissing(row[c])) return gap(cx, 0, "observations with missing model variables are not implemented", .{});
    }
    const n = sel.rows.len;
    if (n == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});

    // Design: strata ascending, sampling units inside strata.
    const order = try a.alloc(usize, n);
    for (order, 0..) |*o, k| o.* = k;
    const Keys = struct {
        rows: []const []const Value,
        strata: []const usize,
        clusters: []const usize,
        fn compare(self: @This(), x: usize, y: usize, with_clusters: bool) std.math.Order {
            for (self.strata) |c| {
                const o = proc.cmpValue(self.rows[x][c], self.rows[y][c]);
                if (o != .eq) return o;
            }
            if (with_clusters) for (self.clusters) |c| {
                const o = proc.cmpValue(self.rows[x][c], self.rows[y][c]);
                if (o != .eq) return o;
            };
            return .eq;
        }
        fn less(self: @This(), x: usize, y: usize) bool {
            return self.compare(x, y, true) == .lt;
        }
    };
    const keys: Keys = .{ .rows = sel.rows, .strata = s.strata, .clusters = s.clusters };
    std.mem.sort(usize, order, keys, Keys.less);
    const stratum = try a.alloc(usize, n);
    const cluster = try a.alloc(usize, n);
    const weight = try a.alloc(f64, n);
    var stratum_rep: std.ArrayList(usize) = .empty;
    var n_clusters: usize = 0;
    for (order, 0..) |row_ix, k| {
        const new_stratum = k == 0 or keys.compare(order[k - 1], row_ix, false) != .eq;
        if (new_stratum) try stratum_rep.append(a, row_ix);
        if (s.clusters.len == 0 or new_stratum or keys.compare(order[k - 1], row_ix, true) != .eq) n_clusters += 1;
        stratum[row_ix] = stratum_rep.items.len - 1;
        cluster[row_ix] = n_clusters - 1;
        weight[row_ix] = if (s.weight) |w| sel.rows[row_ix][w].num else 1;
    }
    const n_strata = stratum_rep.items.len;
    const units = try a.alloc(usize, n_strata);
    const obs = try a.alloc(usize, n_strata);
    @memset(units, 0);
    @memset(obs, 0);
    {
        const seen = try a.alloc(bool, n_clusters);
        @memset(seen, false);
        for (stratum, cluster) |h, c| {
            obs[h] += 1;
            if (!seen[c]) {
                seen[c] = true;
                units[h] += 1;
            }
        }
    }
    for (units) |u| if (u < 2) return gap(cx, 0, "variance estimation with a single sampling unit in a stratum is not implemented", .{});

    var totals: ?[]f64 = null;
    var rates: ?[]f64 = null;
    switch (s.population) {
        .none => {},
        .rate => |r| {
            rates = try a.alloc(f64, n_strata);
            @memset(rates.?, r);
        },
        .total => |x| {
            totals = try a.alloc(f64, n_strata);
            @memset(totals.?, x);
        },
        .total_data => |td| {
            const total_col = td.indexOf("_total_") orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: TOTAL= data set {s} has no _TOTAL_ variable", .{td.name});
            if (td.columns.items[total_col].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: _TOTAL_ must be numeric", .{});
            if (s.strata.len == 0) return gap(cx, 0, "TOTAL= data set without a STRATA statement is not implemented", .{});
            const match = try a.alloc(usize, s.strata.len);
            for (s.strata, match) |c, *m| {
                const nm = ds.columns.items[c].name;
                m.* = td.indexOf(nm) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: TOTAL= data set {s} has no stratum variable {s}", .{ td.name, nm });
            }
            totals = try a.alloc(f64, n_strata);
            for (stratum_rep.items, totals.?) |row_ix, *slot| {
                var found: ?f64 = null;
                for (td.rows.items) |trow| {
                    var same = true;
                    for (s.strata, match) |c, m| same = same and proc.cmpValue(sel.rows[row_ix][c], trow[m]) == .eq;
                    if (same) {
                        found = trow[total_col].num;
                        break;
                    }
                }
                slot.* = found orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: the TOTAL= data set {s} has no total for a stratum of the input data", .{td.name});
            }
        },
    }
    if (totals) |list| {
        rates = try a.alloc(f64, n_strata);
        for (list, units, rates.?) |x, u, *r| {
            const sample: f64 = @floatFromInt(u);
            if (!(x >= sample)) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYREG: a population total is missing or less than the number of sampling units", .{});
            r.* = sample / x;
        }
    }
    const d: design.Design = .{ .stratum = stratum, .cluster = cluster, .weight = weight, .n_strata = n_strata, .n_clusters = n_clusters, .rate = rates };
    const df_f = d.df();
    if (!(df_f > 0)) return gap(cx, 0, "tests without positive design degrees of freedom are not implemented", .{});
    const df: usize = @intFromFloat(df_f);

    // Design columns: intercept, then per effect one numeric column or one
    // dummy per CLASS level (levels ascending, unformatted).
    var cols: std.ArrayList(Column) = .empty;
    try cols.append(a, .{ .effect = null, .label = "Intercept" });
    const ClassInfo = struct { col: usize, levels: []const []const u8 };
    var class_info: std.ArrayList(ClassInfo) = .empty;
    for (s.effects, 0..) |c, e| {
        const cname = ds.columns.items[c].name;
        if (std.mem.indexOfScalar(usize, s.classes, c) == null) {
            try cols.append(a, .{ .effect = e, .label = cname });
            continue;
        }
        const sorted = try a.alloc(usize, n);
        for (sorted, 0..) |*o, k| o.* = k;
        const one: Keys = .{ .rows = sel.rows, .strata = &.{c}, .clusters = &.{} };
        std.mem.sort(usize, sorted, one, Keys.less);
        var names: std.ArrayList([]const u8) = .empty;
        for (sorted, 0..) |row_ix, k| {
            if (k > 0 and one.compare(sorted[k - 1], row_ix, false) == .eq) continue;
            const text = try levelText(a, sel.rows[row_ix][c]);
            try names.append(a, text);
            try cols.append(a, .{ .effect = e, .label = try std.fmt.allocPrint(a, "{s} {s}", .{ cname, text }), .level = sel.rows[row_ix][c] });
        }
        try class_info.append(a, .{ .col = c, .levels = names.items });
    }
    // CLASS variables that are not model effects still get a level table in
    // SAS; that layout is not verified.
    for (s.classes) |c| if (std.mem.indexOfScalar(usize, s.effects, c) == null) return gap(cx, 0, "a CLASS variable that is not a MODEL effect is not verified", .{});
    const p = cols.items.len;
    const x = try a.alloc(f64, n * p);
    const y = try a.alloc(f64, n);
    for (sel.rows, 0..) |row, k| {
        y[k] = row[s.dependent].num;
        for (cols.items, 0..) |col, j| {
            x[k * p + j] = if (col.effect) |e| blk: {
                const c = s.effects[e];
                if (col.level) |lv| break :blk if (proc.cmpValue(row[c], lv) == .eq) 1 else 0;
                break :blk row[c].num;
            } else 1;
        }
    }
    const ginv = try a.alloc(f64, p * p);
    @memset(ginv, 0);
    const xwy = try a.alloc(f64, p);
    @memset(xwy, 0);
    for (0..n) |k| for (0..p) |i| {
        xwy[i] += weight[k] * x[k * p + i] * y[k];
        for (0..p) |j| ginv[i * p + j] += weight[k] * x[k * p + i] * x[k * p + j];
    };
    const aliased = try a.alloc(bool, p);
    try sweepInverse(a, ginv, p, aliased);
    // Only the reference-level aliasing of main-effect CLASS dummies (the last
    // level of each CLASS effect) has a verified Type III test layout.
    var rank: usize = 0;
    for (cols.items, aliased, 0..) |col, al, j| {
        if (!al) {
            rank += 1;
            continue;
        }
        const last_level = col.level != null and (j + 1 == p or cols.items[j + 1].effect != col.effect);
        if (!last_level) return gap(cx, 0, "a model with aliased parameters other than the last CLASS level is not implemented", .{});
    }
    if (n <= rank) return gap(cx, 0, "a model with no fewer parameters than observations is not implemented", .{});
    const b = try a.alloc(f64, p);
    for (0..p) |i| {
        b[i] = 0;
        for (0..p) |j| b[i] += ginv[i * p + j] * xwy[j];
    }
    const resid = try a.alloc(f64, n);
    var sum_w: f64 = 0;
    var sum_wy: f64 = 0;
    var sum_y: f64 = 0;
    for (0..n) |k| {
        var fit: f64 = 0;
        for (0..p) |j| fit += x[k * p + j] * b[j];
        resid[k] = y[k] - fit;
        sum_w += weight[k];
        sum_wy += weight[k] * y[k];
        sum_y += y[k];
    }
    const ybar = sum_wy / sum_w;
    var sse: f64 = 0;
    var sst: f64 = 0;
    for (0..n) |k| {
        sse += weight[k] * resid[k] * resid[k];
        sst += weight[k] * (y[k] - ybar) * (y[k] - ybar);
    }
    const nf: f64 = @floatFromInt(n);
    const rf: f64 = @floatFromInt(rank);
    const r_square = 1 - sse / sst;
    // MSE = n/(n-p) * sum(w r^2) / sum(w) (chapter 123, Fit Statistics); for
    // unit weights this is the ordinary SSE/(n-p).
    const root_mse = @sqrt(nf / (nf - rf) * sse / sum_w);

    // Sandwich: V = (n-1)/(n-p) (X'WX)^- G (X'WX)^-.
    const meat = try design.taylorRegressionMeat(a, d, x, resid, p);
    const adjust = (nf - 1) / (nf - rf);
    const tmp = try a.alloc(f64, p * p);
    const v = try a.alloc(f64, p * p);
    for (0..p) |i| for (0..p) |j| {
        var acc: f64 = 0;
        for (0..p) |k| acc += ginv[i * p + k] * meat[k * p + j];
        tmp[i * p + j] = acc;
    };
    for (0..p) |i| for (0..p) |j| {
        var acc: f64 = 0;
        for (0..p) |k| acc += tmp[i * p + k] * ginv[k * p + j];
        v[i * p + j] = adjust * acc;
    };

    // Type III Wald F tests for main effects: the intercept averages over
    // CLASS levels; a CLASS effect contrasts each level with the last.
    var tests: std.ArrayList(Test) = .empty;
    var model_rows: std.ArrayList([]const f64) = .empty;
    var effect_rows: std.ArrayList([]const []const f64) = .empty;
    {
        const l = try a.alloc(f64, p);
        @memset(l, 0);
        l[0] = 1;
        for (s.effects, 0..) |c, e| {
            if (std.mem.indexOfScalar(usize, s.classes, c) == null) continue;
            var levels: f64 = 0;
            for (cols.items) |col| if (col.effect == e) {
                levels += 1;
            };
            for (cols.items, 0..) |col, j| if (col.effect == e) {
                l[j] = 1 / levels;
            };
        }
        try effect_rows.append(a, try a.dupe([]const f64, &.{l}));
    }
    for (s.effects, 0..) |c, e| {
        var rows_e: std.ArrayList([]const f64) = .empty;
        if (std.mem.indexOfScalar(usize, s.classes, c) == null) {
            const l = try a.alloc(f64, p);
            @memset(l, 0);
            for (cols.items, 0..) |col, j| if (col.effect == e) {
                l[j] = 1;
            };
            try rows_e.append(a, l);
        } else {
            var last: usize = 0;
            for (cols.items, 0..) |col, j| if (col.effect == e) {
                last = j;
            };
            for (cols.items, 0..) |col, j| if (col.effect == e and j != last) {
                const l = try a.alloc(f64, p);
                @memset(l, 0);
                l[j] = 1;
                l[last] = -1;
                try rows_e.append(a, l);
            };
        }
        if (rows_e.items.len == 0) return gap(cx, 0, "a CLASS effect with a single level is not implemented", .{});
        try model_rows.appendSlice(a, rows_e.items);
        try effect_rows.append(a, rows_e.items);
    }
    {
        const f = (try waldF(a, model_rows.items, b, v, p)) orelse return gap(cx, 0, "a singular Wald test covariance is not implemented", .{});
        try tests.append(a, .{ .label = "Model", .df = model_rows.items.len, .f = f });
    }
    for (effect_rows.items, 0..) |rows_e, k| {
        const f = (try waldF(a, rows_e, b, v, p)) orelse return gap(cx, 0, "a singular Wald test covariance is not implemented", .{});
        try tests.append(a, .{ .label = if (k == 0) "Intercept" else ds.columns.items[s.effects[k - 1]].name, .df = rows_e.len, .f = f });
    }
    // ponytail: the 10.6 / 10.8 / 7.2 displays are verified for moderate
    // magnitudes only.
    for (b, 0..) |bb, j| {
        if (!std.math.isFinite(bb) or !std.math.isFinite(v[j * p + j])) return gap(cx, 0, "non-finite estimates are not verified", .{});
        if (@abs(bb) >= 1000 or @sqrt(v[j * p + j]) >= 10) return gap(cx, 0, "display of estimates of this magnitude is not verified", .{});
    }
    if (@abs(ybar) >= 1e5 or sum_w >= 1e7 or @abs(sum_wy) >= 1e7 or @abs(sum_y) >= 1e5) return gap(cx, 0, "display of Data Summary values of this magnitude is not verified", .{});
    if (s.list) {
        if (totals == null) return gap(cx, 0, "STRATA / LIST without TOTAL= is not implemented", .{});
        if (s.strata.len != 1 or ds.columns.items[s.strata[0]].type != .num or ds.columns.items[s.strata[0]].format != null) return gap(cx, 0, "STRATA / LIST for other than one unformatted numeric stratum variable is not implemented", .{});
        if (s.clusters.len > 0) return gap(cx, 0, "STRATA / LIST with CLUSTER is not implemented", .{});
        if (ds.columns.items[s.strata[0]].name.len > 12) return gap(cx, 0, "STRATA / LIST with a long stratum variable name is not verified", .{});
        for (totals.?) |tot| if (tot != @round(tot)) return gap(cx, 0, "display of a fractional population total is not verified", .{});
    }
    const show_coefficients = s.solution or s.classes.len == 0;
    const est_decimals = estimateDecimals(b, aliased);

    var body: Out = .empty;
    try body.appendSlice(a, "\nThe SURVEYREG Procedure\n \n");
    if (rep != null) try body.appendSlice(a, " \n \n");
    try body.print(a, "Regression Analysis for Dependent Variable {s}\n", .{ds.columns.items[s.dependent].name});
    const dep_name = ds.columns.items[s.dependent].name;
    {
        // ponytail: decimals fitted to the reference listing (the ODS
        // template's D-style column): unweighted mean and sum with 5
        // decimals; weighted sum of weights and weighted sum with 1, the
        // weighted mean with 5.
        var labels: std.ArrayList([]const u8) = .empty;
        var values: std.ArrayList([]const u8) = .empty;
        try labels.append(a, "Number of Observations");
        try values.append(a, try count(a, n));
        if (s.weight != null) {
            try labels.append(a, "Sum of Weights");
            try values.append(a, try fixed(a, sum_w, 1));
            try labels.append(a, try std.fmt.allocPrint(a, "Weighted Mean of {s}", .{dep_name}));
            try values.append(a, try fixed(a, ybar, 5));
            try labels.append(a, try std.fmt.allocPrint(a, "Weighted Sum of {s}", .{dep_name}));
            try values.append(a, try fixed(a, sum_wy, 1));
        } else {
            try labels.append(a, try std.fmt.allocPrint(a, "Mean of {s}", .{dep_name}));
            try values.append(a, try fixed(a, ybar, 5));
            try labels.append(a, try std.fmt.allocPrint(a, "Sum of {s}", .{dep_name}));
            try values.append(a, try fixed(a, sum_y, 5));
        }
        // The first table follows the heading with one blank line only.
        try body.appendSlice(a, "\n");
        var lw: usize = 0;
        for (labels.items) |l| lw = @max(lw, l.len);
        try centered(a, &body, "Data Summary", lw + 14);
        try body.append(a, '\n');
        for (labels.items, values.items) |l, val| {
            try left(a, &body, l, lw);
            try right(a, &body, val, 14);
            try body.append(a, '\n');
        }
    }
    if (s.strata.len > 0 or s.clusters.len > 0) {
        var labels: std.ArrayList([]const u8) = .empty;
        var values: std.ArrayList([]const u8) = .empty;
        if (s.strata.len > 0) {
            try labels.append(a, "Number of Strata");
            try values.append(a, try count(a, n_strata));
        }
        if (s.clusters.len > 0) {
            try labels.append(a, "Number of Clusters");
            try values.append(a, try count(a, n_clusters));
        }
        try summary(a, &body, "Design Summary", labels.items, values.items, 14);
    }
    try summary(a, &body, "Fit Statistics", &.{ "R-Square", "Root MSE", "Denominator DF" }, &.{ try fixed(a, r_square, 4), try fixed(a, root_mse, 4), try count(a, df) }, 12);
    if (class_info.items.len > 0) {
        var vw: usize = 8;
        var widest: usize = 0;
        for (class_info.items) |ci| {
            vw = @max(vw, ds.columns.items[ci.col].name.len);
            var len: usize = 0;
            for (ci.levels) |text| len += text.len + 1;
            widest = @max(widest, len);
        }
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Class Level Information", vw + 16 + widest);
        try body.appendSlice(a, " \nCLASS\n");
        try left(a, &body, "Variable", vw);
        try body.appendSlice(a, "      Levels    Values\n\n");
        for (class_info.items) |ci| {
            try left(a, &body, ds.columns.items[ci.col].name, vw);
            try right(a, &body, try count(a, ci.levels.len), 12);
            try body.appendSlice(a, "    ");
            for (ci.levels) |text| try body.print(a, "{s} ", .{text});
            try body.append(a, '\n');
        }
    }
    if (s.list) {
        const sc = s.strata[0];
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Stratum Information", 59);
        try body.appendSlice(a, " \nStratum                              Population    Sampling\n Index ");
        try right(a, &body, ds.columns.items[sc].name, 12);
        try body.appendSlice(a, "       N Obs           Total        Rate\n\n");
        for (stratum_rep.items, 0..) |row_ix, h| {
            try right(a, &body, try count(a, h + 1), 4);
            try body.appendSlice(a, "   ");
            try right(a, &body, try levelText(a, sel.rows[row_ix][sc]), 12);
            try right(a, &body, try count(a, obs[h]), 12);
            try right(a, &body, try fixed(a, totals.?[h], 0), 16);
            try right(a, &body, try std.fmt.allocPrint(a, "{d:.2}%", .{100 * rates.?[h]}), 11);
            try body.appendSlice(a, " \n");
        }
    }
    {
        var ew: usize = 9;
        for (tests.items) |tt| ew = @max(ew, tt.label.len);
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Tests of Model Effects", ew + 31);
        try body.appendSlice(a, " \n");
        try left(a, &body, "Effect", ew);
        try body.appendSlice(a, "    Num DF    F Value    Pr > F\n\n");
        for (tests.items) |tt| {
            try left(a, &body, tt.label, ew);
            try right(a, &body, try count(a, tt.df), 10);
            try right(a, &body, try fixed(a, tt.f, 2), 11);
            try right(a, &body, try pvalue(a, reg_fit.fProbability(tt.f, tt.df, df)), 10);
            try body.append(a, '\n');
        }
        try body.print(a, "\nNOTE: The denominator degrees of freedom for the F tests is {d}.\n", .{df});
    }
    var any_aliased = false;
    for (aliased) |al| any_aliased = any_aliased or al;
    if (show_coefficients) {
        var pw: usize = 9;
        for (cols.items) |col| pw = @max(pw, col.label.len);
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Estimated Regression Coefficients", pw + 51);
        try body.appendSlice(a, " \n");
        try body.appendNTimes(a, ' ', pw + 20);
        try body.appendSlice(a, "Standard\n");
        try left(a, &body, "Parameter", pw);
        try body.appendSlice(a, "      Estimate         Error    t Value    Pr > |t|\n\n");
        for (cols.items, aliased, 0..) |col, al, j| {
            try left(a, &body, col.label, pw);
            if (al) {
                try right(a, &body, try fixed(a, 0, est_decimals), 14);
                try right(a, &body, try fixed(a, 0, 8), 14);
                try body.appendSlice(a, "        .           .    \n");
                continue;
            }
            const se = @sqrt(v[j * p + j]);
            const tv = b[j] / se;
            try right(a, &body, try fixed(a, b[j], est_decimals), 14);
            try right(a, &body, try fixed(a, se, 8), 14);
            try right(a, &body, try fixed(a, tv, 2), 11);
            try right(a, &body, try pvalue(a, reg_fit.tProbability(tv, df)), 12);
            try body.append(a, '\n');
        }
        try body.print(a, "\nNOTE: The degrees of freedom for the t tests is {d}.\n", .{df});
        if (any_aliased) try body.appendSlice(a, "      Matrix X'X is singular and a generalized inverse was used to solve the normal equations.  Estimates are not unique.\n");
    }
    if (rep) |r| try by.appendLine(a, out, ds, r, s.by_cols);
    try out.appendSlice(a, body.items);

    if (cx.capture) |capture| if (capture.wants("ParameterEstimates")) {
        var pw: usize = 1;
        for (cols.items) |col| pw = @max(pw, col.label.len);
        var table = try ods_table.Builder.init(a, ds, s.by_cols, rep);
        try table.char("Parameter", pw);
        try table.num("Estimate", "12.6");
        try table.num("StdErr", "12.8");
        try table.num("DenDF", "8.");
        try table.num("tValue", "9.2");
        try table.num("Probt", "PVALUE8.4");
        const nan = std.math.nan(f64);
        for (cols.items, aliased, 0..) |col, al, j| {
            const se = if (al) 0 else @sqrt(v[j * p + j]);
            const tv = if (al) nan else b[j] / se;
            try table.row(&.{ ods_table.s(col.label), ods_table.n(if (al) 0 else b[j]), ods_table.n(se), ods_table.n(@floatFromInt(df)), ods_table.n(tv), ods_table.n(if (al) nan else reg_fit.tProbability(tv, df)) });
        }
        try capture.publish(a, cx.diags, "ParameterEstimates", &table.ds);
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const ds = s.input.ds;
    if (s.by_cols.len == 0) return analyze(cx, out, s, ds.rows.items, null);
    const groups = try by.checkedSlices(cx.arena, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    // Nothing is printed unless every BY group can be analysed.
    var body: Out = .empty;
    for (groups, 0..) |group, k| {
        if (k > 0) {
            try body.append(cx.arena, '\n');
            if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, &body);
        }
        try analyze(cx, &body, s, group.rows, group.rep.?);
    }
    try out.appendSlice(cx.arena, body.items);
}

test "STAT-SURVEYREG-001 sweep generalized inverse zeroes an aliased column" {
    // X'X of columns 1, x, x (third aliased): [[3,6,6],[6,14,14],[6,14,14]].
    var m = [_]f64{ 3, 6, 6, 6, 14, 14, 6, 14, 14 };
    var al = [_]bool{ false, false, false };
    try sweepInverse(std.testing.allocator, &m, 3, &al);
    try std.testing.expect(!al[0] and !al[1] and al[2]);
    // Inverse of [[3,6],[6,14]] = [[14,-6],[-6,3]] / 6.
    try std.testing.expectApproxEqAbs(@as(f64, 14.0 / 6.0), m[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1), m[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), m[4], 1e-12);
    for ([_]usize{ 2, 5, 6, 7, 8 }) |k| try std.testing.expectEqual(@as(f64, 0), m[k]);
}

test {
    _ = design;
}
