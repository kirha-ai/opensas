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

const iris_rows = @import("sashelp_iris.zig").rows;

/// SASHELP.IRIS (provenance and verification in sashelp_iris.zig).
pub fn iris(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.iris");
    ds.label = "Fisher's Iris Data (1936)";
    _ = try ds.addColumn("Species", .char);
    ds.setLen("Species", 10);
    ds.setLabel("Species", "Iris Species");
    const nums = [_][2][]const u8{ .{ "SepalLength", "Sepal Length (mm)" }, .{ "SepalWidth", "Sepal Width (mm)" }, .{ "PetalLength", "Petal Length (mm)" }, .{ "PetalWidth", "Petal Width (mm)" } };
    for (nums) |c| {
        _ = try ds.addColumn(c[0], .num);
        ds.setLen(c[0], 8);
        ds.setLabel(c[0], c[1]);
    }
    for (iris_rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1][0] }, .{ .num = r[1][1] }, .{ .num = r[1][2] }, .{ .num = r[1][3] } });
    return ds;
}

const enso_rows = @import("sashelp_enso.zig").rows;

/// SASHELP.ENSO (provenance and verification in sashelp_enso.zig).
pub fn enso(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.enso");
    ds.label = "El Nino Southern Oscillation";
    for ([_][]const u8{ "Month", "Year", "Pressure" }) |name| {
        _ = try ds.addColumn(name, .num);
        ds.setLen(name, 8);
    }
    for (enso_rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    return ds;
}

const fish_rows = @import("sashelp_fish.zig").rows;

/// SASHELP.FISH (provenance and verification in sashelp_fish.zig).
pub fn fish(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.fish");
    ds.label = "Measurements of 159 Fish Caught in Lake Laengelmavesi, Finland";
    _ = try ds.addColumn("Species", .char);
    ds.setLen("Species", 9);
    for ([_][]const u8{ "Weight", "Length1", "Length2", "Length3", "Height", "Width" }) |name| {
        _ = try ds.addColumn(name, .num);
        ds.setLen(name, 8);
    }
    for (fish_rows) |r| {
        var v: [7]Value = undefined;
        v[0] = .{ .str = r[0] };
        for (r[1], 1..) |x, k| v[k] = if (x) |n| .{ .num = n } else Value.missing;
        try ds.appendRow(&v);
    }
    return ds;
}

const gas_rows = @import("sashelp_gas.zig").rows;

/// SASHELP.GAS (provenance and verification in sashelp_gas.zig).
pub fn gas(a: std.mem.Allocator) error{OutOfMemory}!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sashelp.gas");
    ds.label = "Nitrogen Oxide Emissions from a Single Cylinder Engine";
    _ = try ds.addColumn("Fuel", .char);
    ds.setLen("Fuel", 8);
    const nums = [_][2][]const u8{ .{ "CpRatio", "Compression Ratio" }, .{ "EqRatio", "Equivalence Ratio" }, .{ "NOx", "Nitrogen Oxide" } };
    for (nums) |c| {
        _ = try ds.addColumn(c[0], .num);
        ds.setLen(c[0], 8);
        ds.setLabel(c[0], c[1]);
    }
    for (gas_rows) |r| {
        var v: [4]Value = undefined;
        v[0] = .{ .str = r[0] };
        for (r[1], 1..) |x, k| v[k] = if (x) |n| .{ .num = n } else Value.missing;
        try ds.appendRow(&v);
    }
    return ds;
}

/// SASHELP.MARGARIN/MILEAGES/QUAKES/SPRINGS (provenance in sashelp_tsv.zig).
const tsv = @import("sashelp_tsv.zig");

const Builtin = struct { member: []const u8, full: []const u8, build: *const fn (std.mem.Allocator) error{OutOfMemory}!*Dataset };
const builtins = [_]Builtin{
    .{ .member = "class", .full = "sashelp.class", .build = class },
    .{ .member = "baseball", .full = "sashelp.baseball", .build = baseball },
    .{ .member = "iris", .full = "sashelp.iris", .build = iris },
    .{ .member = "enso", .full = "sashelp.enso", .build = enso },
    .{ .member = "fish", .full = "sashelp.fish", .build = fish },
    .{ .member = "gas", .full = "sashelp.gas", .build = gas },
    .{ .member = "margarin", .full = "sashelp.margarin", .build = tsv.margarin },
    .{ .member = "mileages", .full = "sashelp.mileages", .build = tsv.mileages },
    .{ .member = "quakes", .full = "sashelp.quakes", .build = tsv.quakes },
    .{ .member = "springs", .full = "sashelp.springs", .build = tsv.springs },
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

test "STAT-SASHELP-004 ENSO, FISH and GAS descriptors, counts and sums from the SAS 9.4 export" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const T = std.testing;
    const Sum = struct {
        fn col(ds: *Dataset, c: usize, n: *usize) f64 {
            var t: f64 = 0;
            n.* = 0;
            for (ds.rows.items) |row| if (!std.math.isNan(row[c].num)) {
                n.* += 1;
                t += row[c].num;
            };
            return t;
        }
    };
    var n: usize = 0;
    const e = try enso(a);
    try T.expectEqual(@as(usize, 168), e.rows.items.len);
    try T.expectEqual(@as(usize, 3), e.columns.items.len);
    try T.expectApproxEqAbs(@as(f64, 1787.8), Sum.col(e, 2, &n), 1e-9);
    try T.expectEqual(@as(u64, 0x3FB5555555555555), @as(u64, @bitCast(e.rows.items[0][1].num)));
    const f = try fish(a);
    try T.expectEqual(@as(usize, 159), f.rows.items.len);
    try T.expectEqual(@as(?usize, 9), f.columns.items[0].len);
    try T.expectEqualStrings("Width", f.columns.items[6].name);
    // Independent totals from the HEX16. export (one missing Weight).
    try T.expectApproxEqAbs(@as(f64, 62993.9), Sum.col(f, 1, &n), 1e-9);
    try T.expectEqual(@as(usize, 158), n);
    try T.expectApproxEqAbs(@as(f64, 4173.3), Sum.col(f, 2, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 4518.1), Sum.col(f, 3, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 4965.1), Sum.col(f, 4, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 1426.388), Sum.col(f, 5, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 702.3802), Sum.col(f, 6, &n), 1e-9);
    try T.expectEqual(@as(u64, 0x4010147AE147AE14), @as(u64, @bitCast(f.rows.items[0][6].num)));
    try T.expect(std.math.isNan(f.rows.items[13][1].num));
    const species = [_]struct { []const u8, usize }{ .{ "Bream", 35 }, .{ "Parkki", 11 }, .{ "Perch", 56 }, .{ "Pike", 17 }, .{ "Roach", 20 }, .{ "Smelt", 14 }, .{ "Whitefish", 6 } };
    for (species) |sp| {
        var k: usize = 0;
        for (f.rows.items) |row| if (std.mem.eql(u8, row[0].str, sp[0])) {
            k += 1;
        };
        try T.expectEqual(sp[1], k);
    }
    const g = try gas(a);
    try T.expectEqual(@as(usize, 171), g.rows.items.len);
    try T.expectEqual(@as(?usize, 8), g.columns.items[0].len);
    try T.expectApproxEqAbs(@as(f64, 1744.5), Sum.col(g, 1, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 158.492), Sum.col(g, 2, &n), 1e-9);
    try T.expectApproxEqAbs(@as(f64, 396.462), Sum.col(g, 3, &n), 1e-9);
    try T.expectEqual(@as(usize, 169), n);
    try T.expectEqual(@as(u64, 0x3FED0624DD2F1AA0), @as(u64, @bitCast(g.rows.items[0][2].num)));
    var lib = Library.init(a);
    var d = @import("diag.zig").Diagnostics.init(a);
    const tokens = try @import("lexer.zig").tokenize(a, "proc candisc data=sashelp.fish;run;", &d);
    try loadReferenced(a, &lib, tokens);
    try T.expectEqual(@as(usize, 159), lib.find("SASHELP.FISH").?.rows.items.len);
    try T.expect(lib.find("SASHELP.GAS") == null);
    try T.expectEqualStrings("El Nino Southern Oscillation", e.label.?);
    try T.expectEqualStrings("Nitrogen Oxide Emissions from a Single Cylinder Engine", g.label.?);
}
