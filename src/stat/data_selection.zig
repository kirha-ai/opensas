//! Statistical input views retain physical observation numbers and typed cells.
//! FREQ and WEIGHT are independent roles; exclusion is a caller policy, not a
//! global statistical rule. Views never write to their source dataset.
const std = @import("std");
const diag = @import("../diag.zig");
const data = @import("../dataset.zig");
const Value = @import("../value.zig").Value;
const proc = @import("../proc.zig");
const by = @import("by_groups.zig");
const A = std.mem.Allocator;

pub const Roles = struct {
    analysis: []const usize = &.{},
    by: []const usize = &.{},
    id: []const usize = &.{},
    frequency: ?usize = null,
    weight: ?usize = null,

    pub fn numeric(ds: *const data.Dataset, name: ?[]const u8, role: []const u8, d: *diag.Diagnostics, line: usize) diag.Error!?usize {
        const nm = name orelse return null;
        const ci = ds.indexOf(nm) orelse return d.fail(error.ParseError, line, "Variable {s} in the {s} statement is not on the input data set", .{ nm, role });
        if (ds.columns.items[ci].type != .num)
            return d.fail(error.ParseError, line, "Variable {s} in the {s} statement must be numeric", .{ nm, role });
        return ci;
    }
};

pub fn missing(value: Value) bool {
    return switch (value) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

pub const Observation = struct {
    source_number: usize, // 1-based in the physical input, before WHERE/OBS
    cells: []const Value,
    frequency: Value, // raw value: truncation/exclusion is procedure-specific
    weight: Value,

    pub fn isMissing(self: Observation, column: usize) bool {
        return missing(self.cells[column]);
    }
};

pub const Policy = struct {
    missing_columns: []const usize = &.{}, // per-variable or listwise, caller chosen
    frequency: enum { preserve, truncate_positive } = .preserve,
    weight: enum { preserve, exclude_missing, positive_only } = .preserve,
};

pub const View = struct {
    source: *const data.Dataset,
    roles: Roles,
    observations: []const Observation,

    pub fn init(a: A, input: proc.ProcInput, roles: Roles) !View {
        const rows = try a.alloc(Observation, input.ds.rows.items.len);
        for (input.ds.rows.items, 0..) |cells, i| rows[i] = .{
            .source_number = if (input.srcobs) |ids| ids[i] else i + 1,
            .cells = cells,
            .frequency = if (roles.frequency) |ci| cells[ci] else .{ .num = 1 },
            .weight = if (roles.weight) |ci| cells[ci] else .{ .num = 1 },
        };
        return .{ .source = input.ds, .roles = roles, .observations = rows };
    }

    pub fn select(self: View, a: A, policy: Policy) !View {
        var rows: std.ArrayList(Observation) = .empty;
        next: for (self.observations) |original| {
            var row = original;
            for (policy.missing_columns) |ci| if (row.isMissing(ci)) continue :next;
            if (policy.frequency == .truncate_positive) {
                const f = row.frequency.num;
                if (!std.math.isFinite(f) or f < 1) continue;
                row.frequency = .{ .num = @trunc(f) };
            }
            switch (policy.weight) {
                .preserve => {},
                .exclude_missing => if (missing(row.weight)) continue,
                .positive_only => if (missing(row.weight) or row.weight.num <= 0) continue,
            }
            try rows.append(a, row);
        }
        var result = self;
        result.observations = rows.items;
        return result;
    }

    /// Contiguous BY groups with the existing formatted-key/sort contract.
    /// Slice the observation records alongside the row slices: no provenance loss.
    pub fn groups(self: View, a: A, desc: []const bool, notsorted: bool, d: *diag.Diagnostics) diag.Error![]View {
        const ds = try self.dataset(a, false, d);
        const slices = try by.checkedSlices(a, ds, self.roles.by, desc, notsorted, d);
        const result = try a.alloc(View, slices.len);
        var offset: usize = 0;
        for (slices, result) |slice, *group| {
            group.* = self;
            group.observations = self.observations[offset .. offset + slice.rows.len];
            offset += slice.rows.len;
        }
        return result;
    }

    /// Adapter for existing MEANS kernels. Only row pointers are replicated;
    /// the view retains one record per source row and separate FREQ/WEIGHT.
    /// ponytail: bounded O(sum FREQ) pointers until all MEANS kernels accept counts.
    pub fn dataset(self: View, a: A, expand_frequency: bool, d: *diag.Diagnostics) diag.Error!*data.Dataset {
        const ds = try a.create(data.Dataset);
        ds.* = data.Dataset.init(a, self.source.name);
        ds.label = self.source.label;
        ds.sortseq_linguistic = self.source.sortseq_linguistic;
        try ds.columns.appendSlice(a, self.source.columns.items);
        for (self.observations) |row| {
            const f = if (expand_frequency) row.frequency.num else 1;
            if (!std.math.isFinite(f) or f < 1) continue;
            if (f > 10_000_000 or ds.rows.items.len > 10_000_000 - @as(usize, @intFromFloat(f))) {
                diag.markGap();
                return d.fail(error.ExecError, 0, "Statistical FREQ expansion exceeds the supported 10000000 observations", .{});
            }
            const count: usize = @intFromFloat(f);
            for (0..count) |_| try ds.rows.append(a, row.cells);
        }
        return ds;
    }
};

test "STAT-COMMON-002 WHERE/BY provenance, types, ID and missing policies are independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = data.Dataset.init(a, "sample");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("id", .char);
    for ([_][]const u8{ "x", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .str = "skip" }, .{ .num = 0 }, .{ .num = 0 }, .{ .num = 1 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .str = "one" }, .{ .num = 1 }, Value.specialMissing('A'), .{ .num = 2.9 }, .{ .num = 0 } });
    try ds.appendRow(&.{ .{ .str = "B" }, .{ .str = " " }, .{ .num = 2 }, .{ .num = 9 }, .{ .num = 3 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .str = "B" }, .{ .str = "end" }, .{ .num = 3 }, .{ .num = 8 }, Value.missing, Value.missing });
    var d = diag.Diagnostics.init(a);
    const toks = try @import("../lexer.zig").tokenize(a, "proc means data=sample; where x > 0; run;", &d);
    const input = try proc.procInputObs(a, &ds, toks, &d);
    const view = try View.init(a, input, .{ .analysis = &.{ 2, 3 }, .by = &.{0}, .id = &.{1}, .frequency = 4, .weight = 5 });
    const groups = try view.groups(a, &.{false}, false, &d);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    try std.testing.expectEqual(@as(usize, 2), groups[0].observations[0].source_number);
    try std.testing.expectEqual(@as(usize, 3), groups[1].observations[0].source_number);
    try std.testing.expectEqual(.char, view.source.columns.items[1].type);
    try std.testing.expect(groups[0].observations[0].isMissing(3));
    try std.testing.expectEqual(@as(u8, 'A'), Value.missingChar(groups[0].observations[0].cells[3].num));
    try std.testing.expect(groups[1].observations[0].isMissing(1));
    const per_variable = try view.select(a, .{ .missing_columns = &.{2}, .frequency = .truncate_positive, .weight = .exclude_missing });
    try std.testing.expectEqual(@as(usize, 2), per_variable.observations.len);
    try std.testing.expectEqual(@as(f64, 2), per_variable.observations[0].frequency.num);
    try std.testing.expectEqual(@as(f64, 0), per_variable.observations[0].weight.num);
    const listwise = try view.select(a, .{ .missing_columns = &.{ 2, 3 }, .frequency = .truncate_positive, .weight = .positive_only });
    try std.testing.expectEqual(@as(usize, 1), listwise.observations.len);
    try std.testing.expectEqual(@as(usize, 3), listwise.observations[0].source_number);
    const expanded = try per_variable.dataset(a, true, &d);
    try std.testing.expectEqual(@as(usize, 5), expanded.rows.items.len);
    try std.testing.expectEqual(@as(usize, 4), ds.rows.items.len);
    try std.testing.expectEqual(@as(f64, 2.9), ds.rows.items[1][4].num);
    try std.testing.expectEqual(@as(f64, 2.9), view.observations[0].frequency.num);
    try std.testing.expectEqual(@as(f64, 2), expanded.rows.items[2][5].num);
}

test "STAT-COMMON-002 numeric role rejects character and absent variables with captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = data.Dataset.init(a, "sample");
    _ = try ds.addColumn("id", .char);
    _ = try ds.addColumn("count", .num);
    var d = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, Roles.numeric(&ds, "id", "FREQ", &d, 7));
    try std.testing.expectError(error.ParseError, Roles.numeric(&ds, "absent", "WEIGHT", &d, 8));
    try std.testing.expectEqual(@as(?usize, 1), try Roles.numeric(&ds, "COUNT", "FREQ", &d, 9));
    try std.testing.expectEqual(@as(?usize, null), try Roles.numeric(&ds, null, "WEIGHT", &d, 9));
    try std.testing.expectEqual(@as(usize, 2), d.count());
}

test "STAT-COMMON-002 FREQ rejection and weight policies do not conflate multiplicity with precision" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = data.Dataset.init(a, "sample");
    _ = try ds.addColumn("f", .num);
    _ = try ds.addColumn("w", .num);
    for ([_]f64{ -2, 0, 0.9, 2.9, 3 }) |f| try ds.appendRow(&.{ .{ .num = f }, .{ .num = -1 } });
    try ds.appendRow(&.{ .{ .num = 4 }, Value.specialMissing('_') });
    const view = try View.init(a, .{ .ds = &ds }, .{ .frequency = 0, .weight = 1 });
    const means = try view.select(a, .{ .frequency = .truncate_positive, .weight = .exclude_missing });
    try std.testing.expectEqual(@as(usize, 2), means.observations.len);
    try std.testing.expectEqual(@as(usize, 4), means.observations[0].source_number);
    try std.testing.expectEqual(@as(f64, 2), means.observations[0].frequency.num);
    try std.testing.expectEqual(@as(f64, -1), means.observations[0].weight.num);
    const positive = try view.select(a, .{ .frequency = .truncate_positive, .weight = .positive_only });
    try std.testing.expectEqual(@as(usize, 0), positive.observations.len);
    try std.testing.expectEqual(@as(usize, 6), view.observations.len);
    const ordinary = try View.init(a, .{ .ds = &ds }, .{});
    try std.testing.expectEqual(@as(f64, 1), ordinary.observations[0].frequency.num);
    try std.testing.expectEqual(@as(f64, 1), ordinary.observations[0].weight.num);
}
