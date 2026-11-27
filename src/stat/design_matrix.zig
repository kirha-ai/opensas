//! Full GLM-coded model matrices, not inference contrasts (STAT-COMMON-007).
//! S154 physical pp.414-418: retain every observed CLASS level/combination,
//! including linearly dependent columns. Nested factors vary slower than crossed
//! factors; within each CLASS list the rightmost factor varies fastest.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const levels = @import("class_levels.zig");
const A = std.mem.Allocator;
pub const Effect = struct { factors: []const usize, nested: []const usize = &.{} };
pub const Spec = struct { response: usize, classes: []const usize = &.{}, effects: []const Effect, intercept: bool = true, order: levels.Order = .formatted, references: []const ?levels.Reference = &.{} };
pub const Class = struct { column: usize, map: levels.Levels };
pub const Column = struct {
    effect_name: []const u8,
    /// Index of the first canonical occurrence in Spec.effects; null for intercept.
    effect_index: ?usize,
    /// Level index in each CLASS map, or null when that CLASS is not in the effect.
    class_values: []const ?usize,
};
pub const Design = struct { x: []f64, n: usize, p: usize, source_rows: []const usize, columns: []const Column, classes: []const Class };
pub const Normalized = struct { continuous: []const usize, crossed: []const usize, nested: []const usize, name: []const u8 };
fn position(classes: []const usize, column: usize) ?usize {
    return std.mem.indexOfScalar(usize, classes, column);
}
fn addUnique(a: A, list: *std.ArrayList(usize), value: usize) !void {
    if (std.mem.indexOfScalar(usize, list.items, value) == null) try list.append(a, value);
}
fn lessClass(classes: []const usize, x: usize, y: usize) bool {
    return position(classes, x).? < position(classes, y).?;
}

pub fn normalize(a: A, ds: *const Dataset, classes: []const usize, e: Effect) diag.Error!Normalized {
    return normalizeOrdered(a, ds, classes, e, &.{});
}
fn normalizeOrdered(a: A, ds: *const Dataset, classes: []const usize, e: Effect, continuous_order: []const usize) diag.Error!Normalized {
    if (e.factors.len == 0) return error.ExecError;
    var continuous: std.ArrayList(usize) = .empty;
    var crossed: std.ArrayList(usize) = .empty;
    var nested: std.ArrayList(usize) = .empty;
    for (e.factors) |ci| {
        if (ci >= ds.columns.items.len) return error.ExecError;
        if (position(classes, ci) != null) try addUnique(a, &crossed, ci) else {
            if (ds.columns.items[ci].type != .num) return error.ExecError;
            try continuous.append(a, ci); // repeated covariates produce powers
        }
    }
    for (e.nested) |ci| {
        if (ci >= ds.columns.items.len or position(classes, ci) == null) return error.ExecError;
        if (std.mem.indexOfScalar(usize, crossed.items, ci) != null) return error.ExecError;
        try addUnique(a, &nested, ci);
    }
    if (continuous_order.len > 0) std.mem.sort(usize, continuous.items, continuous_order, lessClass);
    std.mem.sort(usize, crossed.items, classes, lessClass);
    std.mem.sort(usize, nested.items, classes, lessClass);
    var name: std.ArrayList(u8) = .empty;
    for (continuous.items) |ci| {
        if (name.items.len > 0) try name.append(a, '*');
        try name.appendSlice(a, ds.columns.items[ci].name);
    }
    for (crossed.items) |ci| {
        if (name.items.len > 0) try name.append(a, '*');
        try name.appendSlice(a, ds.columns.items[ci].name);
    }
    if (nested.items.len > 0) {
        try name.append(a, '(');
        for (nested.items, 0..) |ci, i| {
            if (i > 0) try name.append(a, ' ');
            try name.appendSlice(a, ds.columns.items[ci].name);
        }
        try name.append(a, ')');
    }
    return .{ .continuous = continuous.items, .crossed = crossed.items, .nested = nested.items, .name = name.items };
}
fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}
fn ascending(_: void, x: usize, y: usize) bool {
    return x < y;
}

/// Arena-owned result. Row indices refer to the supplied slice. Missing values
/// in any declared CLASS, response, or used covariate exclude that observation.
/// Empty interaction cells generate no column; an observed cell whose continuous
/// multiplier is always zero still generates a legitimate all-zero column.
pub fn build(a: A, ds: *const Dataset, rows: []const []const Value, s: Spec) diag.Error!Design {
    if (s.response >= ds.columns.items.len or ds.columns.items[s.response].type != .num) return error.ExecError;
    var required: std.ArrayList(usize) = .empty;
    try addUnique(a, &required, s.response);
    for (s.classes) |ci| {
        if (ci >= ds.columns.items.len) return error.ExecError;
        try addUnique(a, &required, ci);
    }
    // Regression variables have a model-wide first-appearance order. Thus
    // z*x followed by x*z is one effect named z*x, as in SAS GLMMOD.
    var continuous_order: std.ArrayList(usize) = .empty;
    for (s.effects) |e| for (e.factors) |ci| {
        if (position(s.classes, ci) == null) try addUnique(a, &continuous_order, ci);
    };
    var effects: std.ArrayList(Normalized) = .empty;
    var effect_sources: std.ArrayList(usize) = .empty;
    for (s.effects, 0..) |e, source_index| {
        const normalized = try normalizeOrdered(a, ds, s.classes, e, continuous_order.items);
        var duplicate = false;
        for (effects.items) |old| if (std.mem.eql(u8, old.name, normalized.name)) {
            duplicate = true;
            break;
        };
        if (duplicate) continue;
        try effects.append(a, normalized);
        try effect_sources.append(a, source_index);
        for (normalized.continuous) |ci| try addUnique(a, &required, ci);
    }
    var source: std.ArrayList(usize) = .empty;
    var selected: std.ArrayList([]const Value) = .empty;
    for (rows, 0..) |row, i| {
        var valid = true;
        for (required.items) |ci| {
            if (ci >= row.len) return error.ExecError;
            const v = row[ci];
            if ((ds.columns.items[ci].type == .num and v != .num) or (ds.columns.items[ci].type == .char and v != .str)) return error.ExecError;
            if (missing(v)) valid = false else if (v == .num and !std.math.isFinite(v.num)) return error.ExecError;
        }
        if (valid) {
            try source.append(a, i);
            try selected.append(a, row);
        }
    }
    if (selected.items.len == 0) return error.ExecError;
    const classes = try a.alloc(Class, s.classes.len);
    if (s.references.len != 0 and s.references.len != s.classes.len) return error.ExecError;
    for (s.classes, 0..) |ci, i| {
        var map = try levels.build(a, ds, selected.items, ci, .{ .order = s.order });
        // MIXED REF= reorders a full-level singular design, never drops a
        // column. Empty references preserves every existing caller's order.
        if (s.references.len != 0) if (s.references[i]) |reference| {
            const ref = map.reference(reference) orelse return error.ExecError;
            if (ref + 1 != map.levels.len) {
                const ordered = try a.alloc(levels.Level, map.levels.len);
                const remap = try a.alloc(usize, map.levels.len);
                var next: usize = 0;
                for (map.levels, 0..) |level, old| if (old != ref) {
                    ordered[next] = level;
                    remap[old] = next;
                    next += 1;
                };
                ordered[next] = map.levels[ref];
                remap[ref] = next;
                const rows_reordered = try a.alloc(?usize, map.row_to_level.len);
                for (map.row_to_level, 0..) |old, row| rows_reordered[row] = if (old) |index| remap[index] else null;
                map.levels = ordered;
                map.row_to_level = rows_reordered;
            }
        };
        classes[i] = .{ .column = ci, .map = map };
    }
    var columns: std.ArrayList(Column) = .empty;
    var vectors: std.ArrayList([]const f64) = .empty;
    if (s.intercept) {
        const indicators = try a.alloc(?usize, classes.len);
        @memset(indicators, null);
        const ones = try a.alloc(f64, selected.items.len);
        @memset(ones, 1);
        try columns.append(a, .{ .effect_name = "Intercept", .effect_index = null, .class_values = indicators });
        try vectors.append(a, ones);
    }
    for (effects.items, 0..) |e, effect_index| {
        // Slowest-to-fastest radix sequence: nested list, then crossed list.
        var factors: std.ArrayList(usize) = .empty;
        try factors.appendSlice(a, e.nested);
        try factors.appendSlice(a, e.crossed);
        var dimension: usize = 1;
        for (factors.items) |ci| dimension = std.math.mul(usize, dimension, classes[position(s.classes, ci).?].map.levels.len) catch return error.ExecError;
        const codes = try a.alloc(usize, selected.items.len);
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var observed: std.ArrayList(usize) = .empty;
        for (selected.items, 0..) |_, r| {
            var code: usize = 0;
            for (factors.items) |ci| {
                const c = classes[position(s.classes, ci).?];
                code = code * c.map.levels.len + c.map.row_to_level[r].?;
            }
            codes[r] = code;
            const entry = try seen.getOrPut(a, code);
            if (!entry.found_existing) try observed.append(a, code);
        }
        std.mem.sort(usize, observed.items, {}, ascending);
        for (observed.items) |code| {
            const indicators = try a.alloc(?usize, classes.len);
            @memset(indicators, null);
            var remainder = code;
            var k = factors.items.len;
            while (k > 0) {
                k -= 1;
                const c = position(s.classes, factors.items[k]).?;
                const size = classes[c].map.levels.len;
                indicators[c] = remainder % size;
                remainder /= size;
            }
            const vector = try a.alloc(f64, selected.items.len);
            for (selected.items, 0..) |row, r| {
                var product: f64 = 1;
                for (e.continuous) |ci| {
                    product *= row[ci].num;
                    if (!std.math.isFinite(product)) return error.ExecError;
                }
                vector[r] = if (codes[r] == code) product else 0;
            }
            try columns.append(a, .{ .effect_name = e.name, .effect_index = effect_sources.items[effect_index], .class_values = indicators });
            try vectors.append(a, vector);
        }
    }
    const p = columns.items.len;
    if (p == 0) return error.ExecError;
    const np = std.math.mul(usize, selected.items.len, p) catch return error.ExecError;
    const x = try a.alloc(f64, np);
    for (vectors.items, 0..) |vector, j| for (vector, 0..) |v, i| {
        x[i * p + j] = v;
    };
    return .{ .x = x, .n = selected.items.len, .p = p, .source_rows = source.items, .columns = columns.items, .classes = classes };
}

fn sample(a: A) !Dataset {
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("a", .char);
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][]const u8{ "A", "A", "A", "B", "B", "B" }, 0..) |v, i|
        try ds.appendRow(&.{ .{ .str = v }, .{ .num = @floatFromInt(i % 3) }, .{ .num = @floatFromInt(i + 2) }, .{ .num = @floatFromInt(i + 10) } });
    return ds;
}
test "DESIGN_MATRIX manual full-level main and interaction columns retain aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    const effects = [_]Effect{ .{ .factors = &.{0} }, .{ .factors = &.{1} }, .{ .factors = &.{ 1, 0 } }, .{ .factors = &.{2} }, .{ .factors = &.{ 0, 2 } } };
    const r = try build(a, &ds, ds.rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &effects });
    try std.testing.expectEqual(@as(usize, 15), r.p);
    try std.testing.expectEqualStrings("a*b", r.columns[6].effect_name);
    try std.testing.expectEqualStrings("x*a", r.columns[13].effect_name);
    for (0..6) |i| {
        const row = r.x[i * r.p ..][0..r.p];
        try std.testing.expectEqual(@as(f64, 1), row[0]);
        try std.testing.expectEqual(@as(f64, 1), row[1] + row[2]);
        try std.testing.expectEqual(@as(f64, 1), row[3] + row[4] + row[5]);
        for (0..6) |j| try std.testing.expectEqual(@as(f64, if (i == j) 1 else 0), row[6 + j]);
        try std.testing.expectEqual(@as(f64, @floatFromInt(i + 2)), row[12]);
        try std.testing.expectEqual(row[12], row[13] + row[14]);
    }
}
test "DESIGN_MATRIX nested ordering noint empty cells missing rows and powers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    // Retain A0,A1,B1; B0 and all level2 cells are absent after exclusion.
    var rows: std.ArrayList([]const Value) = .empty;
    for ([_]usize{ 0, 1, 4 }) |i| try rows.append(a, ds.rows.items[i]);
    const effects = [_]Effect{ .{ .factors = &.{1}, .nested = &.{0} }, .{ .factors = &.{2}, .nested = &.{0} }, .{ .factors = &.{ 2, 2 } } };
    const r = try build(a, &ds, rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &effects, .intercept = false });
    try std.testing.expectEqual(@as(usize, 6), r.p);
    try std.testing.expectEqualStrings("b(a)", r.columns[0].effect_name);
    try std.testing.expectEqualStrings("x(a)", r.columns[3].effect_name);
    try std.testing.expectEqualStrings("x*x", r.columns[5].effect_name);
    try std.testing.expectEqualSlices(f64, &.{ 1, 0, 0, 2, 0, 4, 0, 1, 0, 3, 0, 9, 0, 0, 1, 0, 6, 36 }, r.x);
    try ds.appendRow(&.{ .{ .str = "C" }, .{ .num = 9 }, .{ .num = 1 }, Value.missing });
    try ds.appendRow(&.{ .{ .str = "" }, .{ .num = 9 }, .{ .num = 1 }, .{ .num = 9 } });
    const filtered = try build(a, &ds, ds.rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &.{.{ .factors = &.{2} }} });
    try std.testing.expectEqual(@as(usize, 6), filtered.n);
    try std.testing.expectEqual(@as(usize, 2), filtered.classes[0].map.levels.len);
}

test "DESIGN_MATRIX continuous ordering deduplicates commutative effects without dropping GLM aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "continuous");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("g", .char);
    for (0..3) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = @floatFromInt(i + 2) }, .{ .num = @floatFromInt(2 * i + 3) }, .{ .str = if (i == 1) "B" else "A" } });
    const effects = [_]Effect{ .{ .factors = &.{ 1, 0 } }, .{ .factors = &.{ 0, 1 } }, .{ .factors = &.{ 3, 1, 0 } }, .{ .factors = &.{ 0, 0, 0 } } };
    const r = try build(a, &ds, ds.rows.items, .{ .response = 2, .classes = &.{3}, .effects = &effects });
    try std.testing.expectEqual(@as(usize, 5), r.p);
    try std.testing.expectEqualStrings("z*x", r.columns[1].effect_name);
    try std.testing.expectEqualStrings("z*x*g", r.columns[2].effect_name);
    try std.testing.expectEqualStrings("x*x*x", r.columns[4].effect_name);
    try std.testing.expectEqual(@as(?usize, 2), r.columns[2].effect_index);
    try std.testing.expectEqual(@as(?usize, 3), r.columns[4].effect_index);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 2, 0, 1, 1, 6, 0, 6, 8, 1, 12, 12, 0, 27 }, r.x);
}

test "DESIGN_MATRIX general crossed factors vary faster than nested factors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "general");
    for ([_][]const u8{ "A", "B", "C", "D", "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (0..16) |i| try ds.appendRow(&.{
        .{ .num = @floatFromInt((i / 2) % 2) }, .{ .num = @floatFromInt(i % 2) },
        .{ .num = @floatFromInt(i / 8) },       .{ .num = @floatFromInt((i / 4) % 2) },
        .{ .num = 2 },                          .{ .num = 3 },
        .{ .num = 1 },
    });
    const r = try build(a, &ds, ds.rows.items, .{ .response = 6, .classes = &.{ 0, 1, 2, 3 }, .effects = &.{.{ .factors = &.{ 5, 1, 4, 0 }, .nested = &.{ 3, 2 } }}, .intercept = false });
    try std.testing.expectEqual(@as(usize, 16), r.p);
    try std.testing.expectEqualStrings("z*x*A*B(C D)", r.columns[0].effect_name);
    for (0..16) |i| {
        const column = r.columns[i];
        try std.testing.expectEqualSlices(?usize, &.{ (i / 2) % 2, i % 2, i / 8, (i / 4) % 2 }, column.class_values);
        for (0..16) |j| try std.testing.expectEqual(@as(f64, if (i == j) 6 else 0), r.x[i * 16 + j]);
    }
}

test "STAT-MIXED-003 CLASS references reorder full indicators before interactions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    const effects = [_]Effect{ .{ .factors = &.{0} }, .{ .factors = &.{1} }, .{ .factors = &.{ 0, 1 } } };
    const design = try build(a, &ds, ds.rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &effects, .references = &.{ .first, .{ .label = "1" } } });
    try std.testing.expectEqual(@as(usize, 12), design.p);
    try std.testing.expectEqualStrings("B", design.classes[0].map.levels[0].label);
    try std.testing.expectEqualStrings("A", design.classes[0].map.levels[1].label);
    try std.testing.expectEqualStrings("1", design.classes[1].map.levels[2].label);
    const b_order = [_]usize{ 0, 2, 1 };
    for (0..6) |row| {
        const ai: usize = if (row < 3) 1 else 0;
        const bi = b_order[row % 3];
        const x = design.x[row * design.p ..][0..design.p];
        try std.testing.expectEqual(@as(f64, 1), x[0]);
        for (0..2) |j| try std.testing.expectEqual(@as(f64, if (ai == j) 1 else 0), x[1 + j]);
        for (0..3) |j| try std.testing.expectEqual(@as(f64, if (bi == j) 1 else 0), x[3 + j]);
        for (0..6) |j| try std.testing.expectEqual(@as(f64, if (ai * 3 + bi == j) 1 else 0), x[6 + j]);
    }
    const original = try build(a, &ds, ds.rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &effects });
    const explicit_last = try build(a, &ds, ds.rows.items, .{ .response = 3, .classes = &.{ 0, 1 }, .effects = &effects, .references = &.{ .last, .last } });
    try std.testing.expectEqualSlices(f64, original.x, explicit_last.x);
}
