//! SASHELP members stored as tab-separated rows in src/sashelp_data/
//! (STAT-SASHELP-006): MARGARIN, MILEAGES, QUAKES and SPRINGS, the public
//! sample data SAS ships in SASHELP (SAS/STAT 15.4 "Sashelp Data Sets",
//! physical PDF pp.10918–10923).
//!
//! Provenance and verification: exported 2026-11-28 from SAS 9.4 (release
//! 9.0401M9, Linux) by a DATA _NULL_ PUT of every observation of the SASHELP
//! member (numerics as HEX16., missing values as their PUT 1. letter,
//! characters as $CHAR.), converted to the shortest decimal that parses back to
//! the identical IEEE double (checked for every field), trailing blanks of
//! character fields dropped. Descriptors (creation order, type, length, member
//! label; no variable labels or formats) are copied from PROC CONTENTS VARNUM of
//! the same session. None of the four members has a Data Set Type attribute
//! (SASHELP.MILEAGES is not TYPE=DISTANCE: callers supply MILEAGES(TYPE=DISTANCE)).
//! Row counts, NMISS, and sequential f64 sums (bit patterns) are pinned by the
//! test below against SAS output of that session.
//! File format: one observation per line, fields in creation order separated
//! by a tab; `.` plain missing, `.A`–`.Z`/`._` special missing.
const std = @import("std");
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;

/// A column: name and char length (null = numeric, length 8).
pub const Col = struct { []const u8, ?usize };

/// Build `full` (e.g. "sashelp.quakes") from embedded `text` with `cols`.
/// ponytail: a malformed embedded file is a build-time asset bug, so it panics
/// rather than threading a new error through every SASHELP builder.
pub fn build(a: std.mem.Allocator, full: []const u8, label: []const u8, cols: []const Col, text: []const u8) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, full);
    ds.label = label;
    for (cols) |c| {
        _ = try ds.addColumn(c[0], if (c[1] == null) .num else .char);
        ds.setLen(c[0], c[1] orelse 8);
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const v = try a.alloc(Value, cols.len);
        var fields = std.mem.splitScalar(u8, line, '\t');
        for (cols, 0..) |c, k| {
            const f = fields.next() orelse @panic("sashelp_data: short row");
            v[k] = if (c[1] != null)
                .{ .str = f }
            else if (std.mem.eql(u8, f, "."))
                Value.missing
            else if (Value.parseSpecialMissing(f)) |m|
                m
            else
                .{ .num = std.fmt.parseFloat(f64, f) catch @panic("sashelp_data: bad number") };
        }
        if (fields.next() != null) @panic("sashelp_data: long row");
        try ds.rows.append(a, v);
    }
    return ds;
}

pub fn margarin(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    return build(a, "sashelp.margarin", "Margarine Purchase Data", &.{
        .{ "HouseID", null }, .{ "Set", null }, .{ "Choice", null }, .{ "Brand", 8 },
        .{ "LogPrice", null }, .{ "LogInc", null }, .{ "FamSize", null },
    }, @embedFile("sashelp_data/margarin.tsv"));
}

pub fn mileages(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    return build(a, "sashelp.mileages", "Flying Mileages Between Ten US Cities", &.{
        .{ "Atlanta", null },      .{ "Chicago", null }, .{ "Denver", null },
        .{ "Houston", null },      .{ "LosAngeles", null }, .{ "Miami", null },
        .{ "NewYork", null },      .{ "SanFrancisco", null }, .{ "Seattle", null },
        .{ "WashingtonDC", null }, .{ "City", 15 },
    }, @embedFile("sashelp_data/mileages.tsv"));
}

pub fn quakes(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    return build(a, "sashelp.quakes", "Earthquake locations in the United States", &.{
        .{ "Latitude", null },        .{ "Longitude", null }, .{ "Depth", null }, .{ "Magnitude", null },
        .{ "dNearestStation", null }, .{ "RootMeanSquareTime", null }, .{ "Type", 10 },
    }, @embedFile("sashelp_data/quakes.tsv"));
}

pub fn springs(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    return build(a, "sashelp.springs", "Hot Spring locations in the United States", &.{
        .{ "Latitude", null }, .{ "Longitude", null }, .{ "Name", 34 }, .{ "Area", 14 },
        .{ "Type", 9 },        .{ "Farenheit", null }, .{ "Celsius", null },
    }, @embedFile("sashelp_data/springs.tsv"));
}

const Expect = struct { n: usize, nmiss: []const usize, sums: []const u64 = &.{} };

fn check(ds: *const Dataset, e: Expect) !void {
    try std.testing.expectEqual(e.n, ds.rows.items.len);
    var k: usize = 0;
    var s: usize = 0;
    for (ds.columns.items, 0..) |c, j| {
        if (c.type != .num) continue;
        var miss: usize = 0;
        var sum: f64 = 0;
        for (ds.rows.items) |row| {
            if (std.math.isNan(row[j].num)) miss += 1 else sum += row[j].num;
        }
        try std.testing.expectEqual(e.nmiss[k], miss);
        if (s < e.sums.len) {
            try std.testing.expectEqual(e.sums[s], @as(u64, @bitCast(sum)));
            s += 1;
        }
        k += 1;
    }
    try std.testing.expectEqual(e.nmiss.len, k);
}

fn levels(ds: *const Dataset, col: usize, want: []const struct { []const u8, usize }) !void {
    for (want) |w| {
        var n: usize = 0;
        for (ds.rows.items) |row| {
            if (std.mem.eql(u8, row[col].str, w[0])) n += 1;
        }
        try std.testing.expectEqual(w[1], n);
    }
}

test "STAT-SASHELP-006 MARGARIN MILEAGES QUAKES SPRINGS match the SAS 9.4M9 export" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Sequential f64 sums in row order: SAS `s[i] + x` (sum statement, missing
    // skipped) printed HEX16. in the export session.
    const m = try margarin(a);
    try check(m, .{ .n = 20430, .nmiss = &.{ 0, 0, 0, 0, 0, 0 }, .sums = &.{
        0x42243A12CAB00000, 0x4180971B10000000, 0x40AA9A0000000000,
        0xC0C7360CD551D6C8, 0x40EF406CD6777284, 0x40F02A8000000000,
    } });
    try levels(m, 3, &.{ .{ "PBB", 3405 }, .{ "PFl", 3405 }, .{ "PGen", 3405 }, .{ "PHse", 3405 }, .{ "PPk", 3405 }, .{ "PSS", 3405 } });
    const q = try quakes(a);
    try check(q, .{ .n = 15578, .nmiss = &.{ 0, 0, 0, 0, 11914, 9289 }, .sums = &.{
        0x412185DB38861CCA, 0xC13A950506E210F9, 0x40FADD2D7DBF4885,
        0x40E758ECCCCCCCEE, 0x40923B890EAD41CF, 0x40AA0C74BC6A7F02,
    } });
    try levels(q, 6, &.{ .{ "earthquake", 15359 }, .{ "explosion", 3 }, .{ "landslide", 1 }, .{ "mining_exp", 186 }, .{ "quarry", 17 }, .{ "rock_burst", 12 } });
    // MILEAGES: lower-triangular distance matrix; PROC MEANS N/SUM per city.
    const d = try mileages(a);
    try check(d, .{ .n = 10, .nmiss = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } });
    const col_sums = [_]f64{ 10652, 9698, 8531, 8518, 8396, 7343, 5184, 3120, 2329, 0 };
    for (col_sums, 0..) |want, j| {
        var t: f64 = 0;
        for (d.rows.items, 0..) |row, i| {
            try std.testing.expectEqual(i < j, std.math.isNan(row[j].num));
            if (i >= j) t += row[j].num;
        }
        try std.testing.expectEqual(want, t);
    }
    try std.testing.expectEqualStrings("Los Angeles", d.rows.items[4][10].str);
    try std.testing.expectEqual(@as(f64, 1936), d.rows.items[4][0].num);
    // SPRINGS: 172 missing per temperature column; over both, 4 plain, .B 4, .H 214, .W 122.
    const s = try springs(a);
    try check(s, .{ .n = 1587, .nmiss = &.{ 0, 0, 172, 172 } });
    var special = [_]usize{0} ** 128;
    for (s.rows.items) |row| for ([_]usize{ 5, 6 }) |j| {
        if (std.math.isNan(row[j].num)) special[Value.missingChar(row[j].num)] += 1;
    };
    try std.testing.expectEqual(@as(usize, 4), special['.']);
    try std.testing.expectEqual(@as(usize, 4), special['B']);
    try std.testing.expectEqual(@as(usize, 214), special['H']);
    try std.testing.expectEqual(@as(usize, 122), special['W']);
    var t: f64 = 0;
    for (s.rows.items) |row| if (!std.math.isNan(row[5].num)) {
        t += row[5].num;
    };
    try std.testing.expectEqual(@as(f64, 163338), t);
    try std.testing.expectEqualStrings("Hot Springs Near Makushin Volcano", s.rows.items[2][2].str);
    // Descriptors per PROC CONTENTS VARNUM.
    try std.testing.expectEqualStrings("Margarine Purchase Data", m.label.?);
    try std.testing.expectEqualStrings("Flying Mileages Between Ten US Cities", d.label.?);
    try std.testing.expectEqualStrings("Earthquake locations in the United States", q.label.?);
    try std.testing.expectEqualStrings("Hot Spring locations in the United States", s.label.?);
    try std.testing.expectEqual(@as(?usize, 15), d.columns.items[10].len);
    try std.testing.expectEqualStrings("RootMeanSquareTime", q.columns.items[5].name);
    try std.testing.expectEqual(@as(?usize, 34), s.columns.items[2].len);
    for ([_]*const Dataset{ m, d, q, s }) |x| for (x.columns.items) |c| try std.testing.expect(c.label == null and c.format == null);
}
