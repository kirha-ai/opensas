//! Published SASHELP sample data. These are input observations, not fitted
//! results. CLASS is the fictitious classroom in SAS/STAT 15.4 Figure B.8,
//! physical PDF pp.10907–10908 (printed pp.10895–10896).
const std = @import("std");
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;
const Library = @import("exec.zig").Library;

const Student = struct { name: []const u8, sex: []const u8, age: f64, height: f64, weight: f64 };
const students = [_]Student{
    .{ .name = "Alfred", .sex = "M", .age = 14, .height = 69, .weight = 112.5 },
    .{ .name = "Alice", .sex = "F", .age = 13, .height = 56.5, .weight = 84 },
    .{ .name = "Barbara", .sex = "F", .age = 13, .height = 65.3, .weight = 98 },
    .{ .name = "Carol", .sex = "F", .age = 14, .height = 62.8, .weight = 102.5 },
    .{ .name = "Henry", .sex = "M", .age = 14, .height = 63.5, .weight = 102.5 },
    .{ .name = "James", .sex = "M", .age = 12, .height = 57.3, .weight = 83 },
    .{ .name = "Jane", .sex = "F", .age = 12, .height = 59.8, .weight = 84.5 },
    .{ .name = "Janet", .sex = "F", .age = 15, .height = 62.5, .weight = 112.5 },
    .{ .name = "Jeffrey", .sex = "M", .age = 13, .height = 62.5, .weight = 84 },
    .{ .name = "John", .sex = "M", .age = 12, .height = 59, .weight = 99.5 },
    .{ .name = "Joyce", .sex = "F", .age = 11, .height = 51.3, .weight = 50.5 },
    .{ .name = "Judy", .sex = "F", .age = 14, .height = 64.3, .weight = 90 },
    .{ .name = "Louise", .sex = "F", .age = 12, .height = 56.3, .weight = 77 },
    .{ .name = "Mary", .sex = "F", .age = 15, .height = 66.5, .weight = 112 },
    .{ .name = "Philip", .sex = "M", .age = 16, .height = 72, .weight = 150 },
    .{ .name = "Robert", .sex = "M", .age = 12, .height = 64.8, .weight = 128 },
    .{ .name = "Ronald", .sex = "M", .age = 15, .height = 67, .weight = 133 },
    .{ .name = "Thomas", .sex = "M", .age = 11, .height = 57.5, .weight = 85 },
    .{ .name = "William", .sex = "M", .age = 15, .height = 66.5, .weight = 112 },
};

pub fn class(a: std.mem.Allocator) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.class");
    _ = try ds.addColumn("Name", .char);
    ds.setLen("Name", 8);
    _ = try ds.addColumn("Sex", .char);
    ds.setLen("Sex", 1);
    for ([_][]const u8{ "Age", "Height", "Weight" }) |name| {
        _ = try ds.addColumn(name, .num);
        ds.setLen(name, 8);
    }
    for (students) |s| try ds.appendRow(&.{ .{ .str = s.name }, .{ .str = s.sex }, .{ .num = s.age }, .{ .num = s.height }, .{ .num = s.weight } });
    return ds;
}

/// Install only when the source actually refers to SASHELP.CLASS. This avoids
/// changing implicit DATA=_LAST_ for programs that do not use a sample table.
/// Call after Library.init and before interpreting the first DATA/PROC step.
pub fn loadReferenced(a: std.mem.Allocator, lib: *Library, source: []const @import("lexer.zig").Token) !void {
    for (source, 0..) |tok, i| {
        const qualified = tok.tag == .name and std.ascii.eqlIgnoreCase(tok.text, "sashelp.class");
        const split = tok.tag == .name and std.ascii.eqlIgnoreCase(tok.text, "sashelp") and i + 2 < source.len and source[i + 1].tag == .dot and source[i + 2].tag == .name and std.ascii.eqlIgnoreCase(source[i + 2].text, "class");
        if (!qualified and !split) continue;
        if (lib.find("sashelp.class") == null) {
            const previous_count = lib.sets.items.len;
            try lib.putInput("sashelp.class", try class(a));
            // Loading a system input does not replace an existing implicit
            // DATA=_LAST_ target. The Library's index is rebuilt on next lookup.
            if (previous_count > 0) {
                const loaded = lib.sets.pop().?;
                const name = lib.names.pop().?;
                try lib.sets.insert(a, 0, loaded);
                try lib.names.insert(a, 0, name);
                lib.index.clearRetainingCapacity();
            }
        }
        return;
    }
}

test "SASHELP CLASS input descriptor and independent regression totals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try class(a);
    try std.testing.expectEqual(@as(usize, 19), ds.rows.items.len);
    try std.testing.expectEqual(@as(?usize, 8), ds.columns.items[0].len);
    try std.testing.expectEqual(@as(?usize, 1), ds.columns.items[1].len);
    var weights: f64 = 0;
    var heights: f64 = 0;
    for (ds.rows.items) |row| {
        heights += row[3].num;
        weights += row[4].num;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1184.4), heights, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 1900.5), weights, 1e-10);
    var lib = Library.init(a);
    var d = @import("diag.zig").Diagnostics.init(a);
    const tokens = try @import("lexer.zig").tokenize(a, "data work.copy;set sashelp.class;run;", &d);
    try loadReferenced(a, &lib, tokens);
    try std.testing.expectEqual(@as(usize, 19), lib.find("SASHELP.CLASS").?.rows.items.len);
    try std.testing.expect(lib.macroVar("syslast") == null);
}
