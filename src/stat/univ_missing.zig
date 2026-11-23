//! Frequency of each SAS missing code for one UNIVARIATE variable and group.
const std = @import("std");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const ods = @import("ods_univariate.zig");
const b = @import("ods_table.zig");
const Tables = @import("../ods_listing.zig").Tables;

pub const Counts = struct {
    by_code: [28]usize = @splat(0),
    missing: usize = 0,
    eligible: usize = 0,

    pub fn collect(ds: *Dataset, col: usize, weight: ?usize) Counts {
        var result = Counts{};
        for (ds.rows.items) |r| {
            if (weight) |wc| if (r[wc].isMissing()) continue;
            result.eligible += 1;
            const x = r[col].num;
            if (std.math.isNan(x)) {
                result.by_code[Value.missingRank(x)] += 1;
                result.missing += 1;
            }
        }
        return result;
    }
    pub fn emit(self: Counts, a: std.mem.Allocator, out: *std.ArrayList(u8), ctx: ?ods.Context, listing: Tables) !void {
        if (self.missing == 0) return;
        const start = out.items.len;
        try out.appendSlice(a, "\nMissing Values\nMissing Value  Count  Percent of All Obs  Percent of Missing Obs\n");
        var table = try ods.Context.start(ctx, "MissingValues", "Missing Values");
        if (table) |*t| {
            try t.num("MissValue", "5.", "Missing Value");
            try t.num("Count", "8.", "Frequency of Missing Value");
            try t.num("CountNobs", "8.2", "Percent of Total Observations");
            try t.num("CountNMiss", "8.2", "Percent of Missing Observations");
        }
        var distinct: usize = 0;
        for (self.by_code, 0..) |count, rank| {
            if (count == 0) continue;
            distinct += 1;
            const code: u8 = switch (rank) {
                0 => '_',
                1 => '.',
                else => @as(u8, @intCast(rank - 2)) + 'A',
            };
            try self.row(a, out, &table, &.{code}, Value.specialMissing(code), count);
        }
        // M9 encodes the labeled total as numeric zero in the output dataset.
        if (distinct > 1) try self.row(a, out, &table, "Total", b.n(0), self.missing);
        if (table) |*t| try t.finish();
        try listing.finish(a, out, start, "MissingValues");
    }
    fn row(self: Counts, a: std.mem.Allocator, out: *std.ArrayList(u8), table: *?ods.Table, label: []const u8, code: Value, count: usize) !void {
        const n: f64 = @floatFromInt(count);
        const total = 100 * n / @as(f64, @floatFromInt(self.eligible));
        const miss = 100 * n / @as(f64, @floatFromInt(self.missing));
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}  {d}  {d:.2}  {d:.2}\n", .{ label, count, total, miss }));
        if (table.*) |*t| try t.row(&.{ code, b.n(n), b.n(total), b.n(miss) });
    }
};
