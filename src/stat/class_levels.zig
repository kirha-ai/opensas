//! Shared CLASS levelization (STAT-COMMON-006).
//! S154 physical pp.411-413: formatted membership, raw numeric membership when
//! no explicit format exists, ORDER=, and caller-controlled missing levels.
//! One build call is one analysis/BY slice: no global level state is retained.
//! Live SAS GLM probes (2026-11-25) verify minimum-raw representatives, internal
//! tie order for ORDER=FREQ, significant leading label blanks, and raw missing
//! exclusion even when a user format maps a missing value to a nonblank label.
const std = @import("std");
const diag = @import("../diag.zig");
const data = @import("../dataset.zig");
const Value = @import("../value.zig").Value;
const proc = @import("../proc.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;

pub const Order = enum { data, internal, formatted, freq };
pub const Missing = enum { exclude, include };
pub const Options = struct {
    order: Order = .formatted,
    missing: Missing = .exclude,
    /// Optional per-input-row selection mask, established by the caller.
    include_rows: ?[]const bool = null,
    /// Nonnegative frequency counts, not analysis/precision weights. Zero
    /// excludes a row. Caller performs PROC-specific FREQ truncation/exclusion;
    /// this helper deliberately does not truncate or normalize these counts.
    frequencies: ?[]const f64 = null,
};
pub const Level = struct {
    /// Minimum internal value of this formatted group (owned if character).
    value: Value,
    /// Full formatted label with trailing padding removed; leading blanks are
    /// significant. Numeric display padding may be removed by a renderer, but
    /// must not be removed from level identity or ORDER=FORMATTED comparisons.
    label: []const u8,
    frequency: f64,
    /// Zero-based index in the supplied slice, independent of the sort order.
    first_row: usize,
};
pub const Reference = union(enum) { first, last, label: []const u8 };
pub const Levels = struct {
    levels: []const Level,
    /// Zero-based sorted level index for each input row; null means excluded.
    row_to_level: []const ?usize,
    storage: std.heap.ArenaAllocator,

    /// No caller input is borrowed. Arena callers may let the parent arena
    /// reclaim storage; general-allocator callers must use deinit().
    pub fn deinit(self: *Levels) void {
        self.storage.deinit();
        self.* = undefined;
    }

    /// REF= parsing/defaults are procedure-specific. Labels here are exact
    /// formatted values under SAS trailing-blank equality; no case folding,
    /// numeric coercion, leading-blank removal, or implicit default is applied.
    pub fn reference(self: Levels, choice: Reference) ?usize {
        if (self.levels.len == 0) return null;
        return switch (choice) {
            .first => 0,
            .last => self.levels.len - 1,
            .label => |label| blk: {
                for (self.levels, 0..) |level, i| if (proc.cmpValue(.{ .str = level.label }, .{ .str = label }) == .eq) break :blk i;
                break :blk null;
            },
        };
    }
};

fn included(o: Options, i: usize) bool {
    return if (o.include_rows) |mask| mask[i] else true;
}
fn validateDimensions(o: Options, n: usize) diag.Error!void {
    if (o.include_rows) |mask| if (mask.len != n) return error.ExecError;
    if (o.frequencies) |frequencies| if (frequencies.len != n) return error.ExecError;
}
fn explicitFormat(column: data.Column) ?[]const u8 {
    const spec = column.format orelse return null;
    if (spec.len == 0 or std.mem.eql(u8, spec, ".") or std.mem.eql(u8, spec, "$.")) return null;
    return spec;
}
fn missing(value: Value) bool {
    return switch (value) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}
fn copyValue(a: A, value: Value) !Value {
    return switch (value) {
        .num => value,
        .str => |s| .{ .str = try a.dupe(u8, std.mem.trimEnd(u8, s, " ")) },
    };
}
fn numericKey(value: f64) u64 {
    if (value == 0) return 0; // +0 and -0 are one SAS value
    if (std.math.isNan(value)) return @as(u64, 0x7ff8000000000000) + Value.missingRank(value);
    return @bitCast(value);
}
fn labelFor(a: A, column: data.Column, value: Value) diag.Error![]const u8 {
    const text = if (explicitFormat(column)) |spec| try format.apply(a, value, spec) else switch (value) {
        .str => |s| s,
        .num => |x| try format.bestNum(a, x),
    };
    return std.mem.trimEnd(u8, text, " ");
}

/// Dataset wrapper: rows may be ds.rows.items, one BY slice, or a caller-built
/// complete-case view. This function does not determine analysis eligibility.
/// In particular, callers must exclude missing values in ALL declared CLASS
/// variables (even unused ones, physical p.413), plus their own response/effects.
/// The returned row map is aligned to rows, not to the original dataset indices.
pub fn build(a: A, ds: *const data.Dataset, rows: []const []const Value, column_index: usize, o: Options) diag.Error!Levels {
    if (column_index >= ds.columns.items.len) return error.ExecError;
    try validateDimensions(o, rows.len);
    const values = try a.alloc(Value, rows.len);
    defer a.free(values);
    for (rows, 0..) |row, i| {
        values[i] = Value.missing;
        if (!included(o, i)) continue;
        if (o.frequencies) |frequencies| if (frequencies[i] == 0) continue;
        if (column_index >= row.len) return error.ExecError;
        values[i] = row[column_index];
    }
    return buildValues(a, values, ds.columns.items[column_index], o);
}

/// Lower-level single-column entry point for callers with column vectors.
/// Values, masks, and frequencies share one row index. No mutable input or
/// global format/catalog ownership is taken; all output values/labels are copied.
pub fn buildValues(a: A, values: []const Value, column: data.Column, o: Options) diag.Error!Levels {
    try validateDimensions(o, values.len);
    var storage = std.heap.ArenaAllocator.init(a);
    errdefer storage.deinit();
    const owned = storage.allocator();
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    var text_scratch = std.heap.ArenaAllocator.init(a);
    defer text_scratch.deinit();
    var numeric: std.AutoHashMapUnmanaged(u64, usize) = .empty;
    var labels: std.StringHashMapUnmanaged(usize) = .empty;
    var discovered: std.ArrayList(Level) = .empty;
    const row_map = try owned.alloc(?usize, values.len);
    @memset(row_map, null);
    const raw_numeric = column.type == .num and explicitFormat(column) == null;
    for (values, 0..) |original, i| {
        if (!included(o, i)) continue;
        const frequency = if (o.frequencies) |fs| fs[i] else 1;
        if (!std.math.isFinite(frequency) or frequency < 0) return error.ExecError;
        if (frequency == 0) continue;
        if ((column.type == .num and original != .num) or (column.type == .char and original != .str)) return error.ExecError;
        if (o.missing == .exclude and missing(original)) continue;
        if (original == .num and !std.math.isNan(original.num) and !std.math.isFinite(original.num)) return error.ExecError;
        const value: Value = if (original == .num and original.num == 0) .{ .num = 0 } else original;
        _ = text_scratch.reset(.retain_capacity);
        const label = try labelFor(text_scratch.allocator(), column, value);
        const found = if (raw_numeric) numeric.get(numericKey(value.num)) else labels.get(label);
        if (found) |index| {
            const level = &discovered.items[index];
            level.frequency += frequency;
            if (!std.math.isFinite(level.frequency)) return error.ExecError;
            if (proc.cmpValue(value, level.value) == .lt) level.value = try copyValue(owned, value);
            row_map[i] = index;
        } else {
            const index = discovered.items.len;
            const owned_label = try owned.dupe(u8, label);
            try discovered.append(tmp, .{ .value = try copyValue(owned, value), .label = owned_label, .frequency = frequency, .first_row = i });
            if (raw_numeric) try numeric.put(tmp, numericKey(value.num), index) else try labels.put(tmp, owned_label, index);
            row_map[i] = index;
        }
    }
    const order = try tmp.alloc(usize, discovered.items.len);
    for (order, 0..) |*entry, i| entry.* = i;
    const Context = struct {
        levels: []const Level,
        order: Order,
        raw_numeric: bool,
        fn less(c: @This(), left: usize, right: usize) bool {
            const x = c.levels[left];
            const y = c.levels[right];
            if (c.order == .data) return x.first_row < y.first_row;
            if (c.order == .freq and x.frequency != y.frequency) return x.frequency > y.frequency;
            // FREQ ties use internal order even when labels/values disagree.
            const comparison = if (c.order == .internal or c.order == .freq or c.raw_numeric)
                proc.cmpValue(x.value, y.value)
            else
                proc.cmpValue(.{ .str = x.label }, .{ .str = y.label });
            if (comparison != .eq) return comparison == .lt;
            return x.first_row < y.first_row;
        }
    };
    std.mem.sort(usize, order, Context{ .levels = discovered.items, .order = o.order, .raw_numeric = raw_numeric }, Context.less);
    const sorted = try owned.alloc(Level, order.len);
    const inverse = try tmp.alloc(usize, order.len);
    for (order, 0..) |old, new| {
        sorted[new] = discovered.items[old];
        inverse[old] = new;
    }
    for (row_map) |*entry| if (entry.*) |old| {
        entry.* = inverse[old];
    };
    return .{ .levels = sorted, .row_to_level = row_map, .storage = storage };
}

const num_column: data.Column = .{ .name = "x", .type = .num };
const char_column: data.Column = .{ .name = "group", .type = .char };
fn expectLabels(want: []const []const u8, result: Levels) !void {
    try std.testing.expectEqual(want.len, result.levels.len);
    for (want, result.levels) |text, level| try std.testing.expectEqualStrings(text, level.label);
}

test "CLASS_LEVELS original COMMON006 data and internal mapping" {
    const values = [_]Value{ .{ .str = "A" }, .{ .str = "A" }, .{ .str = "A" }, .{ .str = "A" }, .{ .str = "A" }, .{ .str = "A" }, .{ .str = "B" }, .{ .str = "B" }, .{ .str = "B" }, .{ .str = "B" }, .{ .str = "B" }, .{ .str = "B" } };
    for ([_]Order{ .data, .internal }) |order| {
        var levels = try buildValues(std.testing.allocator, &values, char_column, .{ .order = order });
        defer levels.deinit();
        try expectLabels(&.{ "A", "B" }, levels);
        for (levels.row_to_level, 0..) |index, i| try std.testing.expectEqual(@as(?usize, if (i < 6) 0 else 1), index);
        try std.testing.expectEqual(@as(f64, 6), levels.levels[0].frequency);
        try std.testing.expectEqual(@as(f64, 6), levels.levels[1].frequency);
        try std.testing.expectEqual(@as(?usize, 1), levels.reference(.last));
        try std.testing.expectEqual(@as(?usize, 0), levels.reference(.{ .label = "A  " }));
        try std.testing.expectEqual(@as(?usize, null), levels.reference(.{ .label = "a" }));
    }
}

test "CLASS_LEVELS manual Tables20_2 and20_4 formatted missing row maps" {
    const values = [_]Value{ .{ .num = 1.09 }, .{ .num = 1.13 }, .{ .num = 1.27 }, Value.missing, .{ .num = 2.26 }, .{ .num = 2.48 }, .{ .num = 3.34 }, .{ .num = 3.34 }, .{ .num = 3.14 } };
    const raw_map = [_]?usize{ 0, 1, 2, null, 3, 4, 6, 6, 5 };
    const integer_map = [_]?usize{ 0, 0, 0, null, 1, 1, 2, 2, 2 };
    const tenth_map = [_]?usize{ 0, 0, 1, null, 2, 3, 5, 5, 4 };
    const specs = [_]?[]const u8{ null, "3.0", "3.1" };
    for (specs, [_][]const ?usize{ &raw_map, &integer_map, &tenth_map }) |spec, want| {
        var col = num_column;
        col.format = spec;
        var excluded = try buildValues(std.testing.allocator, &values, col, .{});
        defer excluded.deinit();
        try std.testing.expectEqualSlices(?usize, want, excluded.row_to_level);
        var included_missing = try buildValues(std.testing.allocator, &values, col, .{ .missing = .include });
        defer included_missing.deinit();
        for (want, included_missing.row_to_level) |old, index| try std.testing.expectEqual(@as(?usize, if (old) |v| v + 1 else 0), index);
    }
}

test "CLASS_LEVELS exact numeric keys special missings and zero canonicalization" {
    const values = [_]Value{ .{ .num = 1.0000000000001 }, .{ .num = 1.0000000000002 }, .{ .num = -0.0 }, .{ .num = 0.0 }, Value.specialMissing('Z'), Value.missing, Value.specialMissing('_'), Value.specialMissing('A') };
    var r = try buildValues(std.testing.allocator, &values, num_column, .{ .missing = .include });
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 7), r.levels.len);
    try std.testing.expectEqualSlices(?usize, &.{ 5, 6, 4, 4, 3, 1, 0, 2 }, r.row_to_level);
    // Both nearby numbers can share a display label, but must not share a level.
    try std.testing.expect(r.row_to_level[0].? != r.row_to_level[1].?);
    try std.testing.expectEqualStrings(r.levels[5].label, r.levels[6].label);
    var formatted_column = num_column;
    formatted_column.format = "best12.";
    var formatted = try buildValues(std.testing.allocator, values[0..2], formatted_column, .{});
    defer formatted.deinit();
    try std.testing.expectEqual(@as(usize, 1), formatted.levels.len);
    try std.testing.expectEqual(@as(f64, 0), r.levels[4].value.num);
    try std.testing.expectEqual(@as(u8, 0), Value.missingRank(r.levels[0].value.num));
}

test "CLASS_LEVELS formatted groups minimum representatives and FREQ internal ties" {
    const entries = [_]format.UserFmtEntry{ .{ .lo = 1, .hi = 1, .label = "Z" }, .{ .lo = 3, .hi = 3, .label = "Z" }, .{ .lo = 2, .hi = 2, .label = "A" }, .{ .lo = 4, .hi = 4, .label = "A" } };
    const formats = [_]format.UserFmt{.{ .name = "classgrp", .is_char = false, .entries = &entries }};
    const previous = format.userFormats();
    format.setUserFormats(&formats);
    defer format.setUserFormats(previous);
    var col = num_column;
    col.format = "classgrp.";
    const values = [_]Value{ .{ .num = 3 }, .{ .num = 2 }, .{ .num = 1 }, .{ .num = 4 } };
    for ([_]Order{ .data, .internal, .formatted, .freq }, [_][]const []const u8{ &.{ "Z", "A" }, &.{ "Z", "A" }, &.{ "A", "Z" }, &.{ "Z", "A" } }) |order, want| {
        var r = try buildValues(std.testing.allocator, &values, col, .{ .order = order });
        defer r.deinit();
        try expectLabels(want, r);
        const z = r.reference(.{ .label = "Z" }).?;
        try std.testing.expectEqual(@as(f64, 1), r.levels[z].value.num);
        try std.testing.expectEqual(@as(usize, 0), r.levels[z].first_row);
        try std.testing.expectEqual(r.row_to_level[0], r.row_to_level[2]);
    }
    var freq = try buildValues(std.testing.allocator, &values, col, .{ .order = .freq, .frequencies = &.{ 1, 3, 1, 1 } });
    defer freq.deinit();
    try expectLabels(&.{ "A", "Z" }, freq);
    try std.testing.expectEqual(@as(f64, 4), freq.levels[0].frequency);
}

test "CLASS_LEVELS leading blanks and raw missing policy survive user formats" {
    const entries = [_]format.UserFmtEntry{ .{ .lo = 0, .hi = 0, .label = "" }, .{ .lo = 1, .hi = 1, .label = " A" }, .{ .lo = 2, .hi = 2, .label = "A" }, .{ .lo = std.math.nan(f64), .hi = std.math.nan(f64), .label = "M" } };
    const formats = [_]format.UserFmt{.{ .name = "classlead", .is_char = false, .entries = &entries }};
    const previous = format.userFormats();
    format.setUserFormats(&formats);
    defer format.setUserFormats(previous);
    var col = num_column;
    col.format = "classlead.";
    var r = try buildValues(std.testing.allocator, &.{ .{ .num = 1 }, .{ .num = 2 }, Value.missing, .{ .num = 0 } }, col, .{});
    defer r.deinit();
    try expectLabels(&.{ "", " A", "A" }, r);
    try std.testing.expectEqualSlices(?usize, &.{ 1, 2, null, 0 }, r.row_to_level);
    var included_missing = try buildValues(std.testing.allocator, &.{ Value.missing, .{ .num = 2 } }, col, .{ .missing = .include });
    defer included_missing.deinit();
    try expectLabels(&.{ "A", "M" }, included_missing);
    var chars = try buildValues(std.testing.allocator, &.{ .{ .str = " A" }, .{ .str = "A" }, .{ .str = "A  " }, .{ .str = "   " } }, char_column, .{});
    defer chars.deinit();
    try expectLabels(&.{ " A", "A" }, chars);
    try std.testing.expectEqualSlices(?usize, &.{ 0, 1, 1, null }, chars.row_to_level);
}

test "CLASS_LEVELS BY slices caller masks row mapping and input permutation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ds = data.Dataset.init(arena.allocator(), "groups");
    _ = try ds.addColumn("by", .char);
    _ = try ds.addColumn("class", .char);
    for ([_][]const u8{ "B", "A", "C", "C", "A", "B" }, 0..) |v, i| try ds.appendRow(&.{ .{ .str = if (i < 3) "g1" else "g2" }, .{ .str = v } });
    var first = try build(std.testing.allocator, &ds, ds.rows.items[0..3], 1, .{ .order = .data, .include_rows = &.{ true, true, false } });
    defer first.deinit();
    var second = try build(std.testing.allocator, &ds, ds.rows.items[3..6], 1, .{ .order = .data });
    defer second.deinit();
    try expectLabels(&.{ "B", "A" }, first);
    try expectLabels(&.{ "C", "A", "B" }, second);
    try std.testing.expectEqualSlices(?usize, &.{ 0, 1, null }, first.row_to_level);
    try std.testing.expectEqualSlices(?usize, &.{ 0, 1, 2 }, second.row_to_level);
    for ([_]Order{ .internal, .formatted, .freq }) |order| {
        var x = try buildValues(std.testing.allocator, &.{ .{ .str = "B" }, .{ .str = "A" }, .{ .str = "B" } }, char_column, .{ .order = order });
        defer x.deinit();
        var y = try buildValues(std.testing.allocator, &.{ .{ .str = "B" }, .{ .str = "B" }, .{ .str = "A" } }, char_column, .{ .order = order });
        defer y.deinit();
        for (x.levels, y.levels) |left, right| try std.testing.expectEqualStrings(left.label, right.label);
        try std.testing.expectEqual(x.row_to_level[1], y.row_to_level[2]);
    }
}

test "CLASS_LEVELS empty exclusions owned values and invalid inputs" {
    var buffer = [_]u8{ 'B', ' ' };
    var r = try buildValues(std.testing.allocator, &.{.{ .str = &buffer }}, char_column, .{});
    defer r.deinit();
    buffer[0] = 'X';
    try std.testing.expectEqualStrings("B", r.levels[0].label);
    try std.testing.expectEqualStrings("B", r.levels[0].value.str);
    var empty = try buildValues(std.testing.allocator, &.{ .{ .num = 1 }, .{ .num = 2 } }, num_column, .{ .frequencies = &.{ 0, 0 } });
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.levels.len);
    try std.testing.expectEqualSlices(?usize, &.{ null, null }, empty.row_to_level);
    try std.testing.expect(empty.reference(.first) == null);
    try std.testing.expectError(error.ExecError, buildValues(std.testing.allocator, &.{.{ .num = 1 }}, char_column, .{}));
    try std.testing.expectError(error.ExecError, buildValues(std.testing.allocator, &.{.{ .num = std.math.inf(f64) }}, num_column, .{}));
    try std.testing.expectError(error.ExecError, buildValues(std.testing.allocator, &.{.{ .num = 1 }}, num_column, .{ .frequencies = &.{-1} }));
    try std.testing.expectError(error.ExecError, buildValues(std.testing.allocator, &.{.{ .num = 1 }}, num_column, .{ .include_rows = &.{} }));
}

fn allocationCheck(a: A) !void {
    var result = try buildValues(a, &.{ .{ .str = "B" }, .{ .str = "A" }, .{ .str = "B" } }, char_column, .{ .order = .freq });
    defer result.deinit();
}
test "CLASS_LEVELS allocation failures release all owned and scratch storage" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCheck, .{});
}

test "CLASS_LEVELS formatted character frequency ties use raw order" {
    const entries = [_]format.UserFmtEntry{ .{ .skey = "z", .label = "A" }, .{ .skey = "a", .label = "Z" } };
    const formats = [_]format.UserFmt{.{ .name = "classrev", .is_char = true, .entries = &entries }};
    const previous = format.userFormats();
    format.setUserFormats(&formats);
    defer format.setUserFormats(previous);
    var col = char_column;
    col.format = "$classrev.";
    const values = [_]Value{ .{ .str = "z" }, .{ .str = "a" }, .{ .str = "z" }, .{ .str = "a" } };
    var r = try buildValues(std.testing.allocator, &values, col, .{ .order = .freq });
    defer r.deinit();
    try expectLabels(&.{ "Z", "A" }, r);
    try std.testing.expectEqualSlices(?usize, &.{ 1, 0, 1, 0 }, r.row_to_level);
    var formatted = try buildValues(std.testing.allocator, &values, col, .{ .order = .formatted });
    defer formatted.deinit();
    try expectLabels(&.{ "A", "Z" }, formatted);
}
