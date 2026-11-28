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

pub fn class(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
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

const bb = @import("sashelp_baseball.zig");

/// SASHELP.BASEBALL (provenance and verification in sashelp_baseball.zig).
/// Descriptor per Figure B.1: creation order, lengths and labels; no formats.
/// Div and logSalary are derived exactly as SASHELP stores them (league and
/// division initials; natural log of Salary, missing when Salary is missing).
pub fn baseball(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.baseball");
    ds.label = "1986 Baseball Data";
    const Col = struct { []const u8, ?usize, []const u8 };
    const cols = [_]Col{
        .{ "Name", 18, "Player's Name" },                 .{ "Team", 14, "Team at the End of 1986" },
        .{ "nAtBat", null, "Times at Bat in 1986" },      .{ "nHits", null, "Hits in 1986" },
        .{ "nHome", null, "Home Runs in 1986" },          .{ "nRuns", null, "Runs in 1986" },
        .{ "nRBI", null, "RBIs in 1986" },                .{ "nBB", null, "Walks in 1986" },
        .{ "YrMajor", null, "Years in the Major Leagues" }, .{ "CrAtBat", null, "Career Times at Bat" },
        .{ "CrHits", null, "Career Hits" },               .{ "CrHome", null, "Career Home Runs" },
        .{ "CrRuns", null, "Career Runs" },               .{ "CrRbi", null, "Career RBIs" },
        .{ "CrBB", null, "Career Walks" },                .{ "League", 8, "League at the End of 1986" },
        .{ "Division", 8, "Division at the End of 1986" }, .{ "Position", 8, "Position(s) in 1986" },
        .{ "nOuts", null, "Put Outs in 1986" },           .{ "nAssts", null, "Assists in 1986" },
        .{ "nError", null, "Errors in 1986" },            .{ "Salary", null, "1987 Salary in $ Thousands" },
        .{ "Div", 16, "League and Division" },            .{ "logSalary", null, "Log Salary" },
    };
    for (cols) |c| {
        _ = try ds.addColumn(c[0], if (c[1] == null) .num else .char);
        ds.setLen(c[0], c[1] orelse 8);
        ds.setLabel(c[0], c[2]);
    }
    for (bb.rows) |r| {
        var v: [24]Value = undefined;
        v[0] = .{ .str = r[0] };
        v[1] = .{ .str = r[1] };
        for (0..13) |k| v[2 + k] = .{ .num = r[5][k] };
        v[15] = .{ .str = r[2] };
        v[16] = .{ .str = r[3] };
        v[17] = .{ .str = r[4] };
        for (0..3) |k| v[18 + k] = .{ .num = r[5][13 + k] };
        v[21] = if (r[6]) |s| .{ .num = s } else Value.missing;
        v[22] = .{ .str = try std.mem.concat(a, u8, &.{ r[2][0..1], r[3][0..1] }) };
        v[23] = if (r[6]) |s| .{ .num = @log(s) } else Value.missing;
        try ds.appendRow(&v);
    }
    return ds;
}

const Builtin = struct { member: []const u8, full: []const u8, build: *const fn (std.mem.Allocator) error{OutOfMemory}!*Dataset };
const builtins = [_]Builtin{
    .{ .member = "class", .full = "sashelp.class", .build = class },
    .{ .member = "baseball", .full = "sashelp.baseball", .build = baseball },
};

/// True when `member` names a built-in SASHELP sample table.
pub fn isBuiltin(member: []const u8) bool {
    for (builtins) |b| if (std.ascii.eqlIgnoreCase(b.member, member)) return true;
    return false;
}

/// Install a built-in table only when the source actually refers to it. This
/// avoids changing implicit DATA=_LAST_ for programs that do not use a sample.
/// Call after Library.init and before interpreting the first DATA/PROC step.
/// ponytail: other SASHELP members stay absent, so referring to one is the
/// ordinary loud "does not exist" error, never substitute data.
pub fn loadReferenced(a: std.mem.Allocator, lib: *Library, source: []const @import("lexer.zig").Token) !void {
    for (builtins) |b| {
        for (source, 0..) |tok, i| {
            const qualified = tok.tag == .name and std.ascii.eqlIgnoreCase(tok.text, b.full);
            const split = tok.tag == .name and std.ascii.eqlIgnoreCase(tok.text, "sashelp") and i + 2 < source.len and source[i + 1].tag == .dot and source[i + 2].tag == .name and std.ascii.eqlIgnoreCase(source[i + 2].text, b.member);
            if (!qualified and !split) continue;
            if (lib.find(b.full) == null) {
                const previous_count = lib.sets.items.len;
                try lib.putInput(b.full, try b.build(a));
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
            break;
        }
    }
}

test "STAT-SASHELP-001 BASEBALL descriptor and totals from the SAS 9.4 dump" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try baseball(a);
    try std.testing.expectEqual(@as(usize, 322), ds.rows.items.len);
    try std.testing.expectEqual(@as(usize, 24), ds.columns.items.len);
    try std.testing.expectEqual(@as(?usize, 14), ds.columns.items[1].len);
    try std.testing.expectEqual(@as(?usize, 16), ds.columns.items[22].len);
    try std.testing.expectEqualStrings("logSalary", ds.columns.items[23].name);
    // Independent totals computed from the field dump of SASHELP.BASEBALL.
    var n_sal: usize = 0;
    var sal: f64 = 0;
    var hits: f64 = 0;
    var cr_at_bat: f64 = 0;
    for (ds.rows.items) |row| {
        hits += row[3].num;
        cr_at_bat += row[9].num;
        if (!std.math.isNan(row[21].num)) {
            n_sal += 1;
            sal += row[21].num;
        } else try std.testing.expect(std.math.isNan(row[23].num));
    }
    try std.testing.expectEqual(@as(usize, 263), n_sal);
    try std.testing.expectApproxEqAbs(@as(f64, 140948.507), sal, 1e-6);
    try std.testing.expectEqual(@as(f64, 33294), hits);
    try std.testing.expectEqual(@as(f64, 889711), cr_at_bat);
    // logSalary bits as SAS stores them (hex16. of rows 2..5).
    const bits = [_]u64{ 0x4018A73BFEF92030, 0x4018B1F4FC030845, 0x4018DBC239B0B862, 0x401210BB29DE6592 };
    for (bits, 1..) |want, r| try std.testing.expectEqual(want, @as(u64, @bitCast(ds.rows.items[r][23].num)));
    try std.testing.expectEqualStrings("NW", ds.rows.items[1][22].str);
    var sf: usize = 0;
    for (ds.rows.items) |row| {
        if (std.mem.eql(u8, row[1].str, "San Francisco")) sf += 1;
    }
    try std.testing.expectEqual(@as(usize, 14), sf);
    var lib = Library.init(a);
    var d = @import("diag.zig").Diagnostics.init(a);
    const tokens = try @import("lexer.zig").tokenize(a, "proc print data=sashelp.baseball;run;", &d);
    try loadReferenced(a, &lib, tokens);
    try std.testing.expectEqual(@as(usize, 322), lib.find("SASHELP.BASEBALL").?.rows.items.len);
    try std.testing.expect(lib.find("SASHELP.CLASS") == null);
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
