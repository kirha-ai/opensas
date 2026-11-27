//! NPAR1WAY variable/tie counts, SAS/STAT15.4 physical pp.7223,7236,7259.
//! Count selected source records separately from frequency-expanded scores.
//! CLASS levels use the procedure's formatted membership; response ties use
//! internal numeric identity (including equality of positive/negative zero).
const std = @import("std");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
pub const Info = struct { used: usize = 0, missing: usize = 0, frequency: usize = 0, classes: usize = 0, empty_classes: usize = 0, levels: usize = 0, tied: usize = 0 };
pub fn collect(a: A, ds: *const Dataset, rows: []const []const Value, class: usize, variable: usize, frequency: ?usize, include_missing: bool) !Info {
    const levels = try classes.build(a, ds, rows, class, .{ .order = .data, .missing = if (include_missing) .include else .exclude });
    const used = try a.alloc(bool, levels.levels.len);
    @memset(used, false);
    var counts: std.AutoHashMapUnmanaged(u64, usize) = .empty;
    defer counts.deinit(a);
    var result = Info{};
    for (rows, 0..) |row, i| {
        const f = if (frequency) |column| row[column].num else 1;
        if (levels.row_to_level[i] == null or selection.missing(row[variable]) or !std.math.isFinite(f) or f < 1) {
            result.missing += 1;
            continue;
        }
        if (@floor(f) > 1_000_000) return error.ExecError;
        const weight: usize = @intFromFloat(@floor(f));
        result.used += 1;
        result.frequency += weight;
        used[levels.row_to_level[i].?] = true;
        const x = row[variable].num;
        const key: u64 = if (x == 0) 0 else @bitCast(x);
        const entry = try counts.getOrPut(a, key);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += weight;
    }
    for (used) |yes| {
        if (yes) result.classes += 1 else result.empty_classes += 1;
    }
    result.levels = counts.count();
    var iter = counts.valueIterator();
    while (iter.next()) |count| {
        if (count.* > 1) result.tied += count.*;
    }
    return result;
}
pub fn render(a: A, out: *std.ArrayList(u8), variable: []const u8, info: Info, frequency: bool, ties: bool) !void {
    try out.print(a, "\nVariable Information for Variable {s}\n\nNumber of Observations Used {d}\nNumber of Missing Observations {d}\n", .{ variable, info.used, info.missing });
    if (frequency) try out.print(a, "Sum of Frequencies Used {d}\n", .{info.frequency});
    try out.print(a, "Number of Class Levels Used {d}\nNumber of Empty Class Levels Excluded {d}\n", .{ info.classes, info.empty_classes });
    if (ties) try out.print(a, "Number of Variable Levels {d}\nNumber of Tied Observations {d}\n", .{ info.levels, info.tied });
}
