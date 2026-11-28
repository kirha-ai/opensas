//! PROC GLIMMIX fixed-effects model structure (STAT-GLIMMIX-003).
//! S154 physical pp.3875-3881: intercept/NOINT, interaction and nested effects,
//! the non-full-rank parameterization (a solution is 0 whenever its design
//! column is a linear combination of previous columns), deletion of missing
//! level combinations from X, and positional/nonpositional contrast
//! coefficients. Columns come from the shared GLM-coded builder
//! (design_matrix.zig, STAT-COMMON-007), used read-only.
//! ponytail: the bar operator, `@`, the EFFECT statement (constructed effects)
//! and the Z matrix are not interpreted here; callers keep them as loud gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const dm = @import("design_matrix.zig");
pub const Effect = dm.Effect;
const levels = @import("class_levels.zig");
const A = std.mem.Allocator;

fn user(cx: proc.ProcCtx, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC GLIMMIX: " ++ fmt, args);
}
fn isClass(class_columns: []const usize, ci: usize) bool {
    return std.mem.indexOfScalar(usize, class_columns, ci) != null;
}

/// MODEL effect list (the tokens between `=` and the option slash) into shared
/// effect descriptions. `a`, `a*b`, `b(a)`, `a*b(c d)` and continuous factors.
/// Invalid structure is a user error; undocumented-here syntax is a D-009 gap.
pub fn parseEffects(cx: proc.ProcCtx, ds: *const Dataset, class_columns: []const usize, t: []const lex.Token, line: usize) diag.Error![]const dm.Effect {
    var out: std.ArrayList(dm.Effect) = .empty;
    var k: usize = 0;
    while (k < t.len) {
        if (t[k].tag == .pipe) return proc.failGap(cx.diags, line, "PROC GLIMMIX: the bar operator in MODEL effects is not implemented", .{});
        if (t[k].tag == .at) return proc.failGap(cx.diags, line, "PROC GLIMMIX: the @ operator in MODEL effects is not implemented", .{});
        var factors: std.ArrayList(usize) = .empty;
        var nested: std.ArrayList(usize) = .empty;
        while (true) {
            if (k >= t.len or t[k].tag != .name) return user(cx, line, "malformed MODEL effect", .{});
            const ci = ds.indexOf(t[k].text) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{t[k].text});
            if (!isClass(class_columns, ci) and ds.columns.items[ci].type != .num)
                return user(cx, line, "character variable {s} in a MODEL effect must be listed in the CLASS statement", .{t[k].text});
            try factors.append(cx.arena, ci);
            k += 1;
            if (k < t.len and t[k].tag == .lparen) {
                if (nested.items.len > 0) return user(cx, line, "malformed nesting in MODEL effect", .{});
                k += 1;
                while (k < t.len and t[k].tag == .name) : (k += 1) {
                    const ni = ds.indexOf(t[k].text) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{t[k].text});
                    if (!isClass(class_columns, ni)) return user(cx, line, "nesting variable {s} must be listed in the CLASS statement", .{t[k].text});
                    try nested.append(cx.arena, ni);
                }
                if (nested.items.len == 0 or k >= t.len or t[k].tag != .rparen) return user(cx, line, "malformed nesting in MODEL effect", .{});
                k += 1;
            }
            if (k < t.len and t[k].tag == .star) {
                k += 1;
                continue;
            }
            break;
        }
        for (nested.items) |ni| if (std.mem.indexOfScalar(usize, factors.items, ni) != null)
            return user(cx, line, "variable {s} cannot be nested within itself", .{ds.columns.items[ni].name});
        try out.append(cx.arena, .{ .factors = factors.items, .nested = nested.items });
    }
    return out.items;
}

pub const EffectInfo = struct {
    /// Canonical label: continuous factors, CLASS factors in CLASS statement
    /// order (p.3875: B*A becomes A*B), then the nesting list.
    name: []const u8,
    /// First and one-past-last X column of the effect (missing cells deleted).
    first: usize,
    end: usize,
    continuous: []const usize,
    /// Positions in Design.full.classes of the crossed CLASS factors, name order.
    crossed: []const usize,
    nested: []const usize,
};

pub const Design = struct {
    /// Non-full-rank X exactly as parameterized: n rows, p columns, row-major.
    full: dm.Design,
    /// Intercept first when present, then each distinct effect in MODEL order.
    effects: []const EffectInfo,
    intercept: bool,
    /// p.3876: true when the column is a linear combination of previous columns;
    /// its solution is 0.
    aliased: []const bool,
    rank: usize,
    /// Indices of the non-aliased columns, ascending; `x_full_rank` holds them
    /// (n by rank, row-major) for the estimation kernel.
    kept: []const usize,
    x_full_rank: []const f64,

    pub fn effectOf(d: Design, a: A, ds: *const Dataset, class_columns: []const usize, e: dm.Effect) !?usize {
        const q = dm.normalize(a, ds, class_columns, e) catch return null;
        const sorted = try a.dupe(usize, q.continuous);
        std.mem.sort(usize, sorted, {}, std.sort.asc(usize));
        for (d.effects, 0..) |info, i| {
            if (i == 0 and d.intercept) continue;
            if (info.continuous.len != sorted.len or info.crossed.len != q.crossed.len or info.nested.len != q.nested.len) continue;
            const mine = try a.dupe(usize, info.continuous);
            std.mem.sort(usize, mine, {}, std.sort.asc(usize));
            if (!std.mem.eql(usize, mine, sorted)) continue;
            var same = true;
            for (info.crossed, q.crossed) |pos, ci| same = same and d.full.classes[pos].column == ci;
            for (info.nested, q.nested) |pos, ci| same = same and d.full.classes[pos].column == ci;
            if (same) return i;
        }
        return null;
    }
};

pub const Terms = struct { effects: []const dm.Effect, intercept: bool = true };

/// `rows` are the used observations of one BY group (no missing values in any
/// model variable). `singular` is the PROC SINGULAR= value: a column whose
/// residual sum of squares after regression on the previous columns is at most
/// singular times its own sum of squares is declared dependent (the pivot test
/// of the sweep operator, stated on the column itself).
pub fn build(a: A, ds: *const Dataset, rows: []const []const Value, response: usize, class_columns: []const usize, order: levels.Order, terms: Terms, singular: f64) diag.Error!Design {
    const full = try dm.build(a, ds, rows, .{ .response = response, .classes = class_columns, .effects = terms.effects, .intercept = terms.intercept, .order = order });
    const n = full.n;
    const p = full.p;
    var infos: std.ArrayList(EffectInfo) = .empty;
    var j: usize = 0;
    if (terms.intercept) {
        try infos.append(a, .{ .name = "Intercept", .first = 0, .end = 1, .continuous = &.{}, .crossed = &.{}, .nested = &.{} });
        j = 1;
    }
    while (j < p) {
        const source = full.columns[j].effect_index orelse return error.ExecError;
        var end = j;
        while (end < p and full.columns[end].effect_index == source) end += 1;
        const q = try dm.normalize(a, ds, class_columns, terms.effects[source]);
        const crossed = try a.alloc(usize, q.crossed.len);
        for (q.crossed, crossed) |ci, *pos| pos.* = std.mem.indexOfScalar(usize, class_columns, ci).?;
        const nested = try a.alloc(usize, q.nested.len);
        for (q.nested, nested) |ci, *pos| pos.* = std.mem.indexOfScalar(usize, class_columns, ci).?;
        try infos.append(a, .{ .name = full.columns[j].effect_name, .first = j, .end = end, .continuous = q.continuous, .crossed = crossed, .nested = nested });
        j = end;
    }
    // Columns in order; modified Gram-Schmidt (two passes) against kept ones.
    const aliased = try a.alloc(bool, p);
    var kept: std.ArrayList(usize) = .empty;
    const basis = try a.alloc(f64, n * p);
    const v = try a.alloc(f64, n);
    for (0..p) |c| {
        var own: f64 = 0;
        for (0..n) |i| {
            v[i] = full.x[i * p + c];
            own += v[i] * v[i];
        }
        for (0..2) |_| for (0..kept.items.len) |b| {
            const qv = basis[b * n ..][0..n];
            var dot: f64 = 0;
            for (qv, v) |x, y| dot += x * y;
            for (qv, v) |x, *y| y.* -= dot * x;
        };
        var rest: f64 = 0;
        for (v) |x| rest += x * x;
        aliased[c] = own == 0 or rest <= singular * own;
        if (!aliased[c]) {
            const scale = 1.0 / @sqrt(rest);
            for (basis[kept.items.len * n ..][0..n], v) |*x, y| x.* = y * scale;
            try kept.append(a, c);
        }
    }
    const rank = kept.items.len;
    const reduced = try a.alloc(f64, n * rank);
    for (0..n) |i| for (kept.items, 0..) |c, r| {
        reduced[i * rank + r] = full.x[i * p + c];
    };
    return .{ .full = full, .effects = infos.items, .intercept = terms.intercept, .aliased = aliased, .rank = rank, .kept = kept.items, .x_full_rank = reduced };
}

/// One `[multiplier <,> level-values]` entry (p.3878).
pub const Bracket = struct { multiplier: f64, values: []const f64 };
/// p.3880: the two forms cannot be mixed for one effect, hence a union.
pub const Coefficients = union(enum) { positional: []const f64, nonpositional: []const Bracket };
pub const CoefficientError = error{
    /// More positional values than the effect has X columns.
    TooManyCoefficients,
    /// Entry count differs from the number of terms in the effect name.
    WrongValueCount,
    /// A level indicator is not an ordinal level 1..k of its CLASS variable.
    InvalidLevel,
    /// The level combination is a missing cell, deleted from X (p.3876).
    MissingCell,
    /// Nested effects: the entry order is not stated on the cited pages.
    NotDocumented,
};

/// Adds the coefficients of one effect to `l` (one element per X column of the
/// non-full-rank design). Positional values fill the effect's columns in order,
/// omitted trailing values are 0. A nonpositional entry lists continuous values
/// first, then the ordinal level of every CLASS variable in effect-name order;
/// the product of the continuous values times the multiplier lands on the
/// column of that level combination.
pub fn addCoefficients(d: Design, effect: usize, c: Coefficients, l: []f64) CoefficientError!void {
    std.debug.assert(l.len == d.full.p);
    const e = d.effects[effect];
    switch (c) {
        .positional => |values| {
            if (values.len > e.end - e.first) return error.TooManyCoefficients;
            for (values, 0..) |x, i| l[e.first + i] += x;
        },
        .nonpositional => |entries| {
            if (e.nested.len > 0) return error.NotDocumented;
            // Validate everything before touching `l`.
            const targets_max = 64;
            if (entries.len > targets_max) return error.NotDocumented;
            var cols: [targets_max]usize = undefined;
            var adds: [targets_max]f64 = undefined;
            for (entries, 0..) |entry, k| {
                if (entry.values.len != e.continuous.len + e.crossed.len) return error.WrongValueCount;
                var product = entry.multiplier;
                for (entry.values[0..e.continuous.len]) |x| product *= x;
                var found: ?usize = null;
                for (e.crossed, entry.values[e.continuous.len..]) |pos, raw| {
                    const count: f64 = @floatFromInt(d.full.classes[pos].map.levels.len);
                    if (raw != @trunc(raw) or raw < 1 or raw > count) return error.InvalidLevel;
                }
                search: for (e.first..e.end) |col| {
                    for (e.crossed, entry.values[e.continuous.len..]) |pos, raw| {
                        const level: usize = @intFromFloat(raw - 1);
                        if (d.full.columns[col].class_values[pos] != level) continue :search;
                    }
                    found = col;
                    break;
                }
                cols[k] = found orelse return error.MissingCell;
                adds[k] = product;
            }
            for (cols[0..entries.len], adds[0..entries.len]) |col, x| l[col] += x;
        },
    }
}

const t_ = std.testing;
/// Invented data. Columns a b x y z; cell (A3, 2) is empty and cell (A2, 2)
/// holds two observations.
fn sample(a: A) !Dataset {
    var ds = Dataset.init(a, "cells");
    _ = try ds.addColumn("a", .char);
    for ([_][]const u8{ "b", "x", "y", "z" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_]struct { []const u8, f64 }{ .{ "A1", 1 }, .{ "A1", 2 }, .{ "A2", 1 }, .{ "A2", 2 }, .{ "A3", 1 }, .{ "A2", 2 } };
    for (rows, 0..) |r, i| {
        const x: f64 = @floatFromInt(i + 1);
        try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .num = x }, .{ .num = 10 + x }, .{ .num = 2 * x + 1 } });
    }
    return ds;
}
fn eff(comptime factors: []const usize, comptime nested: []const usize) dm.Effect {
    return .{ .factors = factors, .nested = nested };
}
const sing = 1e4 * std.math.floatEps(f64) / 2.0;

test "GLIMMIX003 non-full-rank X: order, deleted missing cell, later dependent columns aliased" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    // model y = a b a*b x;  class a b;
    const effects = [_]dm.Effect{ eff(&.{0}, &.{}), eff(&.{1}, &.{}), eff(&.{ 1, 0 }, &.{}), eff(&.{2}, &.{}) };
    const d = try build(a, &ds, ds.rows.items, 3, &.{ 0, 1 }, .formatted, .{ .effects = &effects }, sing);
    // Hand-written: Int | A1 A2 A3 | b1 b2 | A1b1 A1b2 A2b1 A2b2 A3b1 | x
    const expected = [_]f64{
        1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1,
        1, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 2,
        1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 3,
        1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 4,
        1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 5,
        1, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 6,
    };
    try t_.expectEqual(@as(usize, 6), d.full.n);
    try t_.expectEqual(@as(usize, 12), d.full.p);
    try t_.expectEqualSlices(f64, &expected, d.full.x);
    const names = [_][]const u8{ "Intercept", "a", "b", "a*b", "x" };
    const bounds = [_][2]usize{ .{ 0, 1 }, .{ 1, 4 }, .{ 4, 6 }, .{ 6, 11 }, .{ 11, 12 } };
    try t_.expectEqual(names.len, d.effects.len);
    for (names, bounds, d.effects) |name, range, info| {
        try t_.expectEqualStrings(name, info.name);
        try t_.expectEqual(range[0], info.first);
        try t_.expectEqual(range[1], info.end);
    }
    // The five observed cells span a 5-dimensional space: Int, A1, A2, b1 and
    // A1b1 exhaust it, so every later CLASS column is dependent; x is not
    // constant within cell (A2, 2), so it adds one dimension.
    try t_.expectEqualSlices(bool, &.{ false, false, false, true, false, true, false, true, true, true, true, false }, d.aliased);
    try t_.expectEqual(@as(usize, 6), d.rank);
    try t_.expectEqualSlices(usize, &.{ 0, 1, 2, 4, 6, 11 }, d.kept);
    try t_.expectEqualSlices(f64, &.{
        1, 1, 0, 1, 1, 1,
        1, 1, 0, 0, 0, 2,
        1, 0, 1, 1, 0, 3,
        1, 0, 1, 0, 0, 4,
        1, 0, 0, 1, 0, 5,
        1, 0, 1, 0, 0, 6,
    }, d.x_full_rank);
    // Interaction columns carry their level combination: (A2, b=2) is column 9.
    try t_.expectEqualSlices(?usize, &.{ 1, 1 }, d.full.columns[9].class_values);
    try t_.expectEqualStrings("A3", d.full.classes[0].map.levels[2].label);
}

test "GLIMMIX003 CLASS order reorders interactions; nested effect differs only in column order; NOINT" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    // class b a; model y = a*b;  -> effect b*a, b slowest, cell (2, A3) deleted.
    const crossed = try build(a, &ds, ds.rows.items, 3, &.{ 1, 0 }, .formatted, .{ .effects = &.{eff(&.{ 0, 1 }, &.{})} }, sing);
    try t_.expectEqualStrings("b*a", crossed.effects[1].name);
    // Int | b1A1 b1A2 b1A3 b2A1 b2A2
    try t_.expectEqualSlices(f64, &.{
        1, 1, 0, 0, 0, 0,
        1, 0, 0, 0, 1, 0,
        1, 0, 1, 0, 0, 0,
        1, 0, 0, 0, 0, 1,
        1, 0, 0, 1, 0, 0,
        1, 0, 0, 0, 0, 1,
    }, crossed.full.x);
    try t_.expectEqualSlices(bool, &.{ false, false, false, false, false, true }, crossed.aliased);
    try t_.expectEqual(@as(usize, 5), crossed.rank);
    // class b a; model y = b(a) / noint;  same columns, a (nesting) slowest:
    // A1b1 A1b2 A2b1 A2b2 A3b1. Without the intercept nothing is dependent.
    const nested = try build(a, &ds, ds.rows.items, 3, &.{ 1, 0 }, .formatted, .{ .effects = &.{eff(&.{1}, &.{0})}, .intercept = false }, sing);
    try t_.expectEqualStrings("b(a)", nested.effects[0].name);
    try t_.expectEqualSlices(f64, &.{
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
        0, 0, 0, 0, 1,
        0, 0, 0, 1, 0,
    }, nested.full.x);
    try t_.expectEqual(@as(usize, 5), nested.rank);
    for (nested.aliased) |flag| try t_.expect(!flag);
    try t_.expectEqualSlices(f64, nested.full.x, nested.x_full_rank);
    // model y = a / noint: cell-mean columns, full rank.
    const means = try build(a, &ds, ds.rows.items, 3, &.{ 0, 1 }, .formatted, .{ .effects = &.{eff(&.{0}, &.{})}, .intercept = false }, sing);
    try t_.expectEqualSlices(f64, &.{ 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0 }, means.full.x);
    try t_.expectEqual(@as(usize, 3), means.rank);
    try t_.expect(!means.intercept);
    // A covariate that is an exact linear function of an earlier one is aliased
    // (z = 2x + 1), the earlier column is kept.
    const collinear = try build(a, &ds, ds.rows.items, 3, &.{}, .formatted, .{ .effects = &.{ eff(&.{2}, &.{}), eff(&.{4}, &.{}) } }, sing);
    try t_.expectEqualSlices(bool, &.{ false, false, true }, collinear.aliased);
    try t_.expectEqualSlices(usize, &.{ 0, 1 }, collinear.kept);
}

test "GLIMMIX003 positional and nonpositional coefficients give the documented L vectors" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // p.3878: A has three levels, B two, all six cells observed.
    var ds = Dataset.init(a, "full");
    for ([_][]const u8{ "a", "b", "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (0..6) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 2 + 1) }, .{ .num = @floatFromInt(i % 2 + 1) }, .{ .num = @floatFromInt(i) }, .{ .num = 1 } });
    const effects = [_]dm.Effect{ eff(&.{0}, &.{}), eff(&.{1}, &.{}), eff(&.{ 0, 1 }, &.{}) };
    // class a b; model y = a b a*b;  X: Int | a1 a2 a3 | b1 b2 | a1b1 .. a3b2
    const ab = try build(a, &ds, ds.rows.items, 3, &.{ 0, 1 }, .formatted, .{ .effects = &effects }, sing);
    const b_effect = (try ab.effectOf(a, &ds, &.{ 0, 1 }, eff(&.{1}, &.{}))).?;
    const int_effect = (try ab.effectOf(a, &ds, &.{ 0, 1 }, eff(&.{ 1, 0 }, &.{}))).?; // written b*a
    try t_.expectEqual(@as(usize, 2), b_effect);
    try t_.expectEqual(@as(usize, 3), int_effect);
    try t_.expectEqual(@as(?usize, null), try ab.effectOf(a, &ds, &.{ 0, 1 }, eff(&.{2}, &.{})));
    // contrast 'B at A2' b 1 -1 a*b 0 0 1 -1;
    const hand = [_]f64{ 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 0, 0 };
    var l = [_]f64{0} ** 12;
    try addCoefficients(ab, b_effect, .{ .positional = &.{ 1, -1 } }, &l);
    try addCoefficients(ab, int_effect, .{ .positional = &.{ 0, 0, 1, -1 } }, &l);
    try t_.expectEqualSlices(f64, &hand, &l);
    // contrast 'B at A2' b 1 -1 a*b [1 2 1] [-1 2 2];
    l = [_]f64{0} ** 12;
    try addCoefficients(ab, b_effect, .{ .positional = &.{ 1, -1 } }, &l);
    try addCoefficients(ab, int_effect, .{ .nonpositional = &.{ .{ .multiplier = 1, .values = &.{ 2, 1 } }, .{ .multiplier = -1, .values = &.{ 2, 2 } } } }, &l);
    try t_.expectEqualSlices(f64, &hand, &l);
    // class b a;  same model: positional a*b 0 1 0 0 -1 equals [1 1 2] [-1 2 2].
    const ba = try build(a, &ds, ds.rows.items, 3, &.{ 1, 0 }, .formatted, .{ .effects = &effects }, sing);
    try t_.expectEqualStrings("b*a", ba.effects[3].name);
    // X: Int | a1 a2 a3 | b1 b2 | b1a1 b1a2 b1a3 b2a1 b2a2 b2a3 (effects in MODEL order)
    try t_.expectEqualStrings("a", ba.effects[1].name);
    const hand_ba = [_]f64{ 0, 0, 0, 0, 1, -1, 0, 1, 0, 0, -1, 0 };
    var m = [_]f64{0} ** 12;
    try addCoefficients(ba, 2, .{ .positional = &.{ 1, -1 } }, &m);
    try addCoefficients(ba, 3, .{ .positional = &.{ 0, 1, 0, 0, -1 } }, &m);
    try t_.expectEqualSlices(f64, &hand_ba, &m);
    m = [_]f64{0} ** 12;
    try addCoefficients(ba, 2, .{ .positional = &.{ 1, -1 } }, &m);
    try addCoefficients(ba, 3, .{ .nonpositional = &.{ .{ .multiplier = 1, .values = &.{ 1, 2 } }, .{ .multiplier = -1, .values = &.{ 2, 2 } } } }, &m);
    try t_.expectEqualSlices(f64, &hand_ba, &m);
    // p.3879: class a; model y = a a*x;
    //   estimate 'A2 at x=0.4' intercept 1 a 0 1 a*x [1,0.4 2];
    // X: Int | a1 a2 a3 | x*a1 x*a2 x*a3 ; L = 1 | 0 1 0 | 0 0.4 0.
    const ax = try build(a, &ds, ds.rows.items, 3, &.{0}, .formatted, .{ .effects = &.{ eff(&.{0}, &.{}), eff(&.{ 0, 2 }, &.{}) } }, sing);
    const hand_ax = [_]f64{ 1, 0, 1, 0, 0, 0.4, 0 };
    for ([_]Bracket{ .{ .multiplier = 1, .values = &.{ 0.4, 2 } }, .{ .multiplier = 4, .values = &.{ 0.1, 2 } }, .{ .multiplier = 2, .values = &.{ 0.2, 2 } }, .{ .multiplier = -1, .values = &.{ -0.4, 2 } } }) |entry| {
        var e = [_]f64{0} ** 7;
        try addCoefficients(ax, 0, .{ .positional = &.{1} }, &e);
        try addCoefficients(ax, 1, .{ .positional = &.{ 0, 1 } }, &e);
        try addCoefficients(ax, 2, .{ .nonpositional = &.{entry} }, &e);
        try t_.expectEqualSlices(f64, &hand_ax, &e);
    }
    // Invalid requests leave L untouched.
    var z = [_]f64{0} ** 12;
    try t_.expectError(error.TooManyCoefficients, addCoefficients(ab, b_effect, .{ .positional = &.{ 1, -1, 0 } }, &z));
    try t_.expectError(error.WrongValueCount, addCoefficients(ab, int_effect, .{ .nonpositional = &.{.{ .multiplier = 1, .values = &.{2} }} }, &z));
    try t_.expectError(error.InvalidLevel, addCoefficients(ab, int_effect, .{ .nonpositional = &.{ .{ .multiplier = 1, .values = &.{ 1, 1 } }, .{ .multiplier = 1, .values = &.{ 4, 1 } } } }, &z));
    try t_.expectError(error.InvalidLevel, addCoefficients(ab, int_effect, .{ .nonpositional = &.{.{ .multiplier = 1, .values = &.{ 1.5, 1 } }} }, &z));
    for (z) |value| try t_.expectEqual(@as(f64, 0), value);
    // Missing cell (A3, 2) has no column; a nested effect is not resolved.
    var cells = try sample(a);
    const holes = try build(a, &cells, cells.rows.items, 3, &.{ 0, 1 }, .formatted, .{ .effects = &.{ eff(&.{ 0, 1 }, &.{}), eff(&.{1}, &.{0}) } }, sing);
    var w = [_]f64{0} ** 11;
    try t_.expectError(error.MissingCell, addCoefficients(holes, 1, .{ .nonpositional = &.{.{ .multiplier = 1, .values = &.{ 3, 2 } }} }, &w));
    try t_.expectError(error.NotDocumented, addCoefficients(holes, 2, .{ .nonpositional = &.{.{ .multiplier = 1, .values = &.{ 1, 1 } }} }, &w));
    try addCoefficients(holes, 1, .{ .nonpositional = &.{.{ .multiplier = 2, .values = &.{ 3, 1 } }} }, &w);
    try t_.expectEqualSlices(f64, &.{ 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0 }, &w);
}
