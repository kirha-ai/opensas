//! A Dataset — an ordered list of observations with a named column schema.
//!
//! Where the PDV (pdv.zig) is the *one* row the executor is currently building,
//! a `Dataset` is the persisted result: the rows an `output` produced, or the
//! prior table a `set` reads back. The schema is an ordered `Column` list (name
//! + type); every row is a `[]Value` aligned to that schema by index.
//!
//! Ownership is the point of this type. A row snapshotted from a PDV must not
//! alias the PDV's cells — the next iteration overwrites them. So `appendRow`
//! copies: numerics by value, char bytes duped into the Dataset's arena. After
//! `appendRow` the row is fully independent of whatever produced it.
//!
//! Arena-backed and read-mostly: build it by adding columns then appending
//! rows; read it via `columns`/`rows` (or the `indexOf`/`row` accessors). A
//! *library* of named datasets (for `set a b;`) is the executor's map, not this
//! type — one `Dataset` is one table.

const std = @import("std");
const Value = @import("value.zig").Value;
const VarType = @import("pdv.zig").VarType;

/// `format` is the display format a `format` statement attached to this
/// variable (null = default rendering); PROC PRINT applies it. Optional +
/// defaulted so it's backward-compatible with the frozen M0.3 contract.
pub const Column = struct { name: []const u8, type: VarType, format: ?[]const u8 = null, informat: ?[]const u8 = null, label: ?[]const u8 = null, len: ?usize = null };

pub const Dataset = struct {
    arena: std.mem.Allocator,
    name: []const u8,
    columns: std.ArrayList(Column),
    rows: std.ArrayList([]const Value),
    label: ?[]const u8 = null, // dataset label (PROC DATASETS MODIFY (LABEL=)) — BUG-datasetsstrip

    pub fn init(arena: std.mem.Allocator, name: []const u8) Dataset {
        return .{ .arena = arena, .name = name, .columns = .empty, .rows = .empty };
    }

    /// Append a column to the schema (order = column order). Returns its index.
    pub fn addColumn(self: *Dataset, name: []const u8, t: VarType) !usize {
        const owned = try self.arena.dupe(u8, name);
        try self.columns.append(self.arena, .{ .name = owned, .type = t });
        return self.columns.items.len - 1;
    }

    /// Append a column copying `src`'s attributes (format/informat/label/len)
    /// under `name` — which may differ from `src.name` (e.g. a SQL join
    /// requalification). Keeps an output column's attached format alive across
    /// the copy (GH#49). Returns its index.
    pub fn addColumnLike(self: *Dataset, name: []const u8, src: Column) !usize {
        const idx = try self.addColumn(name, src.type);
        self.columns.items[idx].format = src.format;
        self.columns.items[idx].informat = src.informat;
        self.columns.items[idx].label = src.label;
        self.columns.items[idx].len = src.len;
        return idx;
    }

    /// Attach a display `format` to a column by name (no-op if absent).
    pub fn setFormat(self: *Dataset, name: []const u8, fmt: []const u8) void {
        if (self.indexOf(name)) |i| self.columns.items[i].format = fmt;
    }

    /// Attach a read `informat` to a column by name (no-op if absent).
    pub fn setInformat(self: *Dataset, name: []const u8, inf: []const u8) void {
        if (self.indexOf(name)) |i| self.columns.items[i].informat = inf;
    }

    /// Attach a variable `label` to a column by name (no-op if absent).
    pub fn setLabel(self: *Dataset, name: []const u8, label: []const u8) void {
        if (self.indexOf(name)) |i| self.columns.items[i].label = label;
    }

    /// Record a char column's declared length (LENGTH statement) by name.
    pub fn setLen(self: *Dataset, name: []const u8, len: usize) void {
        if (self.indexOf(name)) |i| self.columns.items[i].len = len;
    }

    /// Index of a column by case-insensitive name, or null.
    pub fn indexOf(self: *const Dataset, name: []const u8) ?usize {
        for (self.columns.items, 0..) |c, i| {
            if (std.ascii.eqlIgnoreCase(c.name, name)) return i;
        }
        return null;
    }

    /// Append one observation. `values` must align to the schema (one per
    /// column, in order); char bytes are duped so the row outlives its source.
    pub fn appendRow(self: *Dataset, values: []const Value) !void {
        std.debug.assert(values.len == self.columns.items.len);
        const cells = try self.arena.alloc(Value, values.len);
        for (values, 0..) |v, i| {
            cells[i] = switch (v) {
                .num => v,
                .str => |s| .{ .str = try self.arena.dupe(u8, s) },
            };
        }
        try self.rows.append(self.arena, cells);
    }

    pub fn rowCount(self: *const Dataset) usize {
        return self.rows.items.len;
    }

    /// The i-th observation, aligned to `columns`.
    pub fn row(self: *const Dataset, i: usize) []const Value {
        return self.rows.items[i];
    }
};

test "build schema, append rows, read back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var ds = Dataset.init(arena.allocator(), "work.people");

    _ = try ds.addColumn("Name", .char);
    _ = try ds.addColumn("Age", .num);
    try std.testing.expectEqual(@as(usize, 1), ds.indexOf("age").?); // case-insensitive

    try ds.appendRow(&.{ .{ .str = "Ann" }, .{ .num = 30 } });
    try ds.appendRow(&.{ .{ .str = "Bo" }, Value.missing });

    try std.testing.expectEqual(@as(usize, 2), ds.rowCount());
    try std.testing.expectEqualStrings("Ann", ds.row(0)[ds.indexOf("Name").?].str);
    try std.testing.expectEqual(@as(f64, 30), ds.row(0)[1].num);
    try std.testing.expect(ds.row(1)[1].isMissing());
}

test "appended row owns its char bytes (survives source mutation)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "work.t");
    _ = try ds.addColumn("s", .char);

    // a mutable buffer standing in for a PDV cell that gets overwritten
    var buf = [_]u8{ 'h', 'i' };
    try ds.appendRow(&.{.{ .str = &buf }});
    buf = [_]u8{ 'y', 'o' }; // clobber the source after snapshotting

    try std.testing.expectEqualStrings("hi", ds.row(0)[0].str); // dataset kept its own copy
}
