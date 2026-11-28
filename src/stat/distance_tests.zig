//! STAT-DISTANCE-001 permanent tests: PROC statement options, VAR levels and
//! options, BY / FREQ / WEIGHT / ID / COPY roles, missing values, the OUT=
//! layout and loud boundaries. Data are invented (D-011). Expected values are
//! from SAS 9.4 listings of these same invented inputs (stated per check) or
//! hand mathematics, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const distance = @import("distance.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const nan = std.math.nan(f64);
// columns: 0 id, 1 g, 2 x, 3 z, 4 c, 5 f, 6 w
const Row = struct { id: []const u8, g: []const u8, x: f64, z: f64, c: []const u8, f: f64, w: f64 };
const sample = [_]Row{
    .{ .id = "a", .g = "A", .x = 1, .z = 1, .c = "p", .f = 1, .w = 1 },
    .{ .id = "b", .g = "A", .x = 2, .z = nan, .c = "q", .f = 2, .w = 2 },
    .{ .id = "c", .g = "A", .x = 4, .z = 3, .c = "r", .f = 0, .w = 1 },
    .{ .id = "d", .g = "A", .x = 7, .z = 2, .c = "s", .f = 1, .w = 0.5 },
    .{ .id = "a", .g = "B", .x = 3, .z = 5, .c = "t", .f = 1, .w = 1 },
    .{ .id = "b", .g = "B", .x = nan, .z = nan, .c = "u", .f = 1, .w = 1 },
    .{ .id = "c", .g = "B", .x = 6, .z = 1, .c = "v", .f = 1.7, .w = 2 },
    .{ .id = "d", .g = "B", .x = 8, .z = 4, .c = "w", .f = nan, .w = 1 },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "s");
        _ = try ds.addColumn("id", .char);
        _ = try ds.addColumn("g", .char);
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("z", .num);
        _ = try ds.addColumn("c", .char);
        _ = try ds.addColumn("f", .num);
        _ = try ds.addColumn("w", .num);
        for (sample) |r| try ds.appendRow(&.{ .{ .str = r.id }, .{ .str = r.g }, .{ .num = r.x }, .{ .num = r.z }, .{ .str = r.c }, .{ .num = r.f }, .{ .num = r.w } });
        try self.lib.put("s", ds);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !distance.Spec {
        return distance.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, source: []const u8) !*Dataset {
        var out: std.ArrayList(u8) = .empty;
        try distance.run(self.cx(), &out, try lex.tokenize(self.arena.allocator(), source, &self.diags));
        try expectEqual(@as(usize, 0), out.items.len); // PROC DISTANCE prints nothing
        return self.lib.find("o").?;
    }
    fn fails(self: *Env, source: []const u8) !void {
        self.diags = diag.Diagnostics.init(self.arena.allocator());
        if (self.parse(source)) |_| {
            var out: std.ArrayList(u8) = .empty;
            if (distance.run(self.cx(), &out, try lex.tokenize(self.arena.allocator(), source, &self.diags))) |_| return error.TestExpectedError else |_| {}
        } else |_| {}
        try expect(self.diags.hasErrors());
    }
};

/// Lower-triangular reference matrix (row-major, `.` = nan) to 5 decimals.
fn check(o: *const Dataset, first: usize, want: []const []const f64) !void {
    try expectEqual(want.len, o.rows.items.len);
    for (want, o.rows.items) |w, row| for (w, 0..) |v, k| {
        const got = row[first + k].num;
        if (std.math.isNan(v)) try expect(std.math.isNan(got)) else try std.testing.expectApproxEqAbs(v, got, 6e-6);
    };
}

test "STAT-DISTANCE-001 PROC statement defaults, explicit options and VAR lists" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const d = try e.parse("proc distance; var interval(x z); run;");
    try expectEqual(distance.Method.euclid, d.method);
    try expect(!d.square and !d.nostd and !d.nomiss and d.undef == null and d.out == null);
    try expect(d.prefix == null);
    try expectEqual(distance.VarDef.df, d.vardef);
    try expectEqual(@as(usize, 2), d.vars.len);
    // One level, no STD=: no standardization (p.2744).
    try expectEqual(distance.Std.none, d.vars[0].std);

    const s = try e.parse("proc distance data=s out=o method=cityblock shape=squ prefix=Q undef=-1 vardef=wgt mult=2 add=1 nomiss; var interval(x / std=range) ratio(z / std=maxabs weights=2, 3); id id; copy c g; by g; freq f; weight w; run;");
    try expectEqual(distance.Method.cityblock, s.method);
    try expect(s.square and s.nomiss);
    try expectEqual(@as(?f64, -1), s.undef);
    try expectEqual(distance.VarDef.weight, s.vardef);
    try expectEqual(@as(f64, 2), s.mult);
    try expectEqual(distance.Std.range, s.vars[0].std);
    try expectEqual(distance.Level.ratio, s.vars[1].level);
    try expectEqual(@as(f64, 2), s.vars[1].weight); // extra weights discarded
    try expectEqual(@as(?usize, 0), s.id);
    try std.testing.expectEqualSlices(usize, &.{ 4, 1 }, s.copy);
    try expectEqual(@as(?usize, 5), s.freq);
    try expectEqual(@as(?usize, 6), s.weight);
    // Mixed levels make standardization mandatory: default STD (p.2744).
    const m = try e.parse("proc distance data=s; var interval(x) ratio(z); run;");
    try expectEqual(distance.Std.std, m.vars[0].std);
    try expectEqual(distance.Std.std, m.vars[1].std);
    const n = try e.parse("proc distance data=s nostd; var interval(x) ratio(z/std=sum); run;");
    try expectEqual(distance.Std.none, n.vars[1].std);
    const l = try e.parse("proc distance data=s method=power(3,2); var interval(x z / weights=.5); run;");
    try expectEqual(distance.Method.power, l.method);
    try expectEqual(@as(f64, 0.5), l.vars[1].weight); // last weight reused
}

test "STAT-DISTANCE-001 BY ID COPY FREQ WEIGHT layout and selection (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const o = try e.run("proc distance data=s method=euclid out=o prefix=D; var interval(x z / std=std); id id; by g; copy c; freq f; weight w; run;");
    const names = [_][]const u8{ "g", "c", "id", "f", "w", "Da", "Db", "Dc", "Dd" };
    try expectEqual(names.len, o.columns.items.len);
    for (names, o.columns.items) |want, col| try expectEqualStrings(want, col.name);
    try check(o, 5, &.{
        &.{0.0},                    &.{ 0.67700, 0.0 },
        &.{ 3.75000, 1.35401, 0.0 }, &.{ 3.35410, 3.38502, 2.25000, 0 },
        &.{0.0},                    &.{ nan, nan },
        &.{ 1.73205, nan, 0.0 },     &.{ 2.06408, nan, 1.22899, 0 },
    });
    try expect(std.math.isNan(o.rows.items[0][6].num)); // upper triangle missing
}

test "STAT-DISTANCE-001 methods, SHAPE=SQUARE, WEIGHTS=, UNDEF=, VARDEF=, NOMISS (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var o = try e.run("proc distance data=s method=cityblock out=o shape=square; var interval(x / std=range) interval(z / std=midrange weights=2); run;");
    try expectEqual(@as(usize, 8), o.columns.items.len);
    try check(o, 0, &.{
        &.{ 0, 0.42857, 2.42857, 1.85714, 4.28571, nan, 0.71429, 4.00000 },
        &.{ 0.42857, 0, 0.85714, 2.14286, 0.42857, nan, 1.71429, 2.57143 },
        &.{ 2.42857, 0.85714, 0, 1.42857, 2.14286, nan, 2.28571, 1.57143 },
        &.{ 1.85714, 2.14286, 1.42857, 0, 3.57143, nan, 1.14286, 2.14286 },
        &.{ 4.28571, 0.42857, 2.14286, 3.57143, 0, nan, 4.42857, 1.71429 },
        &.{ nan, nan, nan, nan, nan, nan, nan, nan },
        &.{ 0.71429, 1.71429, 2.28571, 1.14286, 4.42857, nan, 0, 3.28571 },
        &.{ 4.00000, 2.57143, 1.57143, 2.14286, 1.71429, nan, 3.28571, 0 },
    });
    o = try e.run("proc distance data=s method=sqeuclid out=o nostd; var interval(x z); run;");
    try check(o, 0, &.{ &.{0}, &.{ 2, 0 }, &.{ 13, 8, 0 }, &.{ 37, 50, 10, 0 }, &.{ 20, 2, 5, 25, 0 }, &.{ nan, nan, nan, nan, nan, nan }, &.{ 25, 32, 8, 2, 25, nan, 0 }, &.{ 58, 72, 17, 5, 26, nan, 13, 0 } });
    o = try e.run("proc distance data=s method=chebychev out=o undef=-1; var ratio(x z / std=maxabs); run;");
    try check(o, 0, &.{ &.{0}, &.{ 0.125, 0 }, &.{ 0.4, 0.25, 0 }, &.{ 0.75, 0.625, 0.375, 0 }, &.{ 0.8, 0.125, 0.4, 0.6, 0 }, &.{ -1, -1, -1, -1, -1, -1 }, &.{ 0.625, 0.5, 0.4, 0.2, 0.8, -1, 0 }, &.{ 0.875, 0.75, 0.5, 0.4, 0.625, -1, 0.6, 0 } });
    o = try e.run("proc distance data=s method=size out=o vardef=n; var interval(x z / std=std); weight w; run;");
    try expectEqualStrings("w", o.columns.items[0].name);
    try check(o, 1, &.{ &.{0}, &.{ 0.55027, 0 }, &.{ 1.70203, 1.10054, 0 }, &.{ 2.08913, 2.75136, 0.38709, 0 }, &.{ 2.30352, 0.55027, 0.60149, 0.21440, 0 }, &.{ nan, nan, nan, nan, nan, nan }, &.{ 1.37568, 2.20109, 0.32635, 0.71345, 0.92784, nan, 0 }, &.{ 3.24089, 3.30163, 1.53886, 1.15176, 0.93737, nan, 1.86521, 0 } });
    o = try e.run("proc distance data=s method=euclid out=o nomiss; var interval(x z / std=std); run;");
    try check(o, 0, &.{ &.{0}, &.{ nan, nan }, &.{ 1.67089, nan, 0 }, &.{ 2.35424, nan, 1.29107, 0 }, &.{ 2.56401, nan, 1.28201, 2.38152, 0 }, &.{ nan, nan, nan, nan, nan, nan }, &.{ 1.89434, nan, 1.44020, 0.72010, 2.70035, nan, 0 }, &.{ 3.22622, nan, 1.63452, 1.28201, 1.99086, nan, 1.98725, 0 } });
    // Mixed levels: mandatory STD standardization equals STD=STD.
    const base = [_][]const f64{ &.{0}, &.{ 0.53635, 0 }, &.{ 1.67168, 1.07270, 0 }, &.{ 2.35650, 2.68175, 1.29210, 0 }, &.{ 2.56424, 0.53635, 1.28212, 2.38251, 0 }, &.{ nan, nan, nan, nan, nan, nan }, &.{ 1.89628, 2.14540, 1.44060, 0.72030, 2.70084, nan, 0 }, &.{ 3.22846, 3.21810, 1.63596, 1.28212, 1.99271, nan, 1.98755, 0 } };
    try check(try e.run("proc distance data=s method=euclid out=o; var interval(x) ratio(z); run;"), 0, &base);
    try check(try e.run("proc distance data=s method=l(2) out=o; var interval(x z / std=std); run;"), 0, &base);
    // MULT=2 doubles every distance; ADD= cancels.
    o = try e.run("proc distance data=s method=euclid out=o mult=2 add=1; var interval(x z / std=std); run;");
    try std.testing.expectApproxEqAbs(@as(f64, 6.45692), o.rows.items[7][0].num, 6e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 3.97509), o.rows.items[7][6].num, 6e-6);
}

test "STAT-DISTANCE-001 user errors and loud gaps via captured diagnostics" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const user = [_][]const u8{
        "proc distance data=s out=o; run;", // VAR required
        "proc distance data=s out=o; var interval(x / std=sum); run;", // SAS ERROR: SUM invalid for interval
        "proc distance data=s out=o; var interval(x / std=euclen); run;",
        "proc distance data=s out=o; var interval(c); run;", // character interval
        "proc distance data=s out=o; var interval(x) ratio(x); run;", // duplicate
        "proc distance data=s out=o; var interval(nosuch); run;",
        "proc distance data=s out=o; var foo(x); run;",
        "proc distance data=s out=o method=bogus; var interval(x); run;",
        "proc distance data=s out=o shape=round; var interval(x); run;",
        "proc distance data=s out=o; var interval(x / std=bogus); run;",
        "proc distance data=s out=o; var interval(x); id x; run;", // ID must be character
        "proc distance data=s out=o; var interval(x); freq c; run;",
        "proc distance data=s out=o method=l(0); var interval(x); run;",
    };
    for (user) |src| {
        diag.resetGap();
        try e.fails(src);
        try expect(!diag.gapHit());
    }
    const gaps = [_][]const u8{
        "proc distance data=s out=o stdonly; var interval(x); run;",
        "proc distance data=s out=o method=gower; var interval(x); run;",
        "proc distance data=s out=o method=djaccard; var interval(x); run;",
        "proc distance data=s out=o; var ordinal(x); run;",
        "proc distance data=s out=o; var nominal(c); run;",
        "proc distance data=s out=o; var interval(x / std=mad); run;",
        "proc distance data=s out=o; var interval(x / missing=0); run;",
        "proc distance data=s out=o replace; var interval(x); run;",
        "proc distance data=s out=o outsdz=z; var interval(x); run;",
        "proc distance data=s(where=(g='B' or x=1)) out=o; var interval(x); by g; id id; run;", // ID with a later BY group larger than the first
        "proc distance data=s(where=(x=1 or g='B')) out=o; var interval(x / std=std); by g; run;", // undefined scale inside a BY group (group A has one obs)
        "proc distance data=s out=o; var interval(x / std=std weights=2 to 1 by 1); run;", // non-increasing TO/BY list
        "proc distance data=s out=o rankscore=index; var interval(x); run;",
        "proc distance data=s out=o; var interval(x / order=desc); run;",
        "proc distance data=s out=o absent=0; var interval(x); run;",
        "proc distance data=s out=o; var anominal(c / absent='NA'); run;",
        "proc distance data=s out=o reponly; var interval(x); run;",
        "proc distance data=s out=o initial=mad; var interval(x); run;",
        "proc distance data=s out=o; var interval(x); format id $8.; run;", // FORMAT statement in the step
        "proc distance data=s out=o; var interval(x); freq f; freq w; run;", // repeated FREQ
        "proc distance data=s out=o; var interval(x); weight w; weight f; run;", // repeated WEIGHT
        "proc distance data=s out=o; var interval(x); id id; id c; run;", // repeated ID
        "proc distance data=s out=o; var interval(x z / weights=-1 2); run;", // negative WEIGHTS=
        "proc distance data=s out=o nostd nostd; var interval(x); run;", // repeated PROC option other than METHOD=/PREFIX=
        "proc distance data=s(where=(x>100)) out=o; var interval(x); by g; copy c; run;", // empty BY input with COPY
    };
    for (gaps) |src| {
        diag.resetGap();
        try e.fails(src);
        try expect(diag.gapHit());
    }
}

test "STAT-DISTANCE-001 empty input, DATAn naming, repeated ID and padded BY groups (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const q = try a.create(Dataset);
    q.* = Dataset.init(a, "q");
    _ = try q.addColumn("id", .char);
    _ = try q.addColumn("g", .char);
    _ = try q.addColumn("x", .num);
    _ = try q.addColumn("z", .num);
    const rows = [_]struct { []const u8, []const u8, f64, f64 }{ .{ "a", "A", 1, 1 }, .{ "b", "A", 2, 3 }, .{ "c", "A", 4, 3 }, .{ "a", "B", 3, 5 }, .{ "b", "B", 5, 2 } };
    for (rows) |r| try q.appendRow(&.{ .{ .str = r[0] }, .{ .str = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
    try e.lib.put("q", q);
    const empty = try a.create(Dataset);
    empty.* = Dataset.init(a, "empty");
    _ = try empty.addColumn("x", .num);
    try e.lib.put("empty", empty);
    // SAS: WORK.Q4 has 0 observations and 0 variables.
    var o = try e.run("proc distance data=empty out=o; var interval(x); run;");
    try expectEqual(@as(usize, 0), o.columns.items.len);
    try expectEqual(@as(usize, 0), o.rows.items.len);
    // SAS: DATA1 then DATA2.
    var out: std.ArrayList(u8) = .empty;
    for (0..2) |_| try distance.run(e.cx(), &out, try lex.tokenize(a, "proc distance data=q; var interval(x z); run;", &e.diags));
    try expect(e.lib.find("DATA1") != null and e.lib.find("DATA2") != null);
    // SAS: names a b c a2 b2 (no PREFIX= with ID: the bare ID values).
    o = try e.run("proc distance data=q out=o; var interval(x z); id id; run;");
    for ([_][]const u8{ "id", "a", "b", "c", "a2", "b2" }, o.columns.items) |want, col| try expectEqualStrings(want, col.name);
    try check(o, 1, &.{ &.{0}, &.{ 2.23607, 0 }, &.{ 3.60555, 2, 0 }, &.{ 4.47214, 2.23607, 2.23607, 0 }, &.{ 4.12311, 3.16228, 1.41421, 3.60555, 0 } });
    // SAS: width of the first BY group; group B padded with a missing row
    // carrying the first group's third ID value.
    o = try e.run("proc distance data=q out=o; var interval(x z); by g; id id; run;");
    try expectEqual(@as(usize, 6), o.rows.items.len);
    try check(o, 2, &.{ &.{0}, &.{ 2.23607, 0 }, &.{ 3.60555, 2, 0 }, &.{0}, &.{ 3.60555, 0 }, &.{ nan, nan, nan } });
    try expectEqualStrings("B", o.rows.items[5][0].str);
    try expectEqualStrings("c", o.rows.items[5][1].str);
    try expect(std.math.isNan(o.rows.items[3][3].num) and std.math.isNan(o.rows.items[3][4].num));
}

test "STAT-DISTANCE-001 rules settled by a SAS 9.4 run: ID errors, zero scale, empty BY input" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // SAS: "ERROR: The ID variable must have the same values in the same order
    // in each BY group." -- a user error (rc 1), no data set.
    diag.resetGap();
    try e.fails("proc distance data=s out=o; var interval(x / std=std); by g; id c; run;");
    try expect(!diag.gapHit());
    try expect(e.lib.find("o") == null);
    // SAS: "ERROR: The ID variable contains at least one missing value. No
    // distance matrix will be created."
    const b = try a.create(Dataset);
    b.* = Dataset.init(a, "b");
    _ = try b.addColumn("id", .char);
    _ = try b.addColumn("x", .num);
    for ([_][]const u8{ "", "u", "v" }, [_]f64{ 1, 2, 4 }) |id, x| try b.appendRow(&.{ .{ .str = id }, .{ .num = x } });
    try e.lib.put("b", b);
    diag.resetGap();
    try e.fails("proc distance data=b out=o; var interval(x / std=std); id id; run;");
    try expect(!diag.gapHit());
    // SAS: STD=STD of a constant variable gives two WARNINGs, the NOTE "OUT=
    // data set is not created." and no data set (not an ERROR).
    const zc = try a.create(Dataset);
    zc.* = Dataset.init(a, "zc");
    _ = try zc.addColumn("x", .num);
    _ = try zc.addColumn("z", .num);
    for ([_]f64{ 1, 2, 4 }) |x| try zc.appendRow(&.{ .{ .num = x }, .{ .num = 5 } });
    try e.lib.put("zc", zc);
    e.diags = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try distance.run(e.cx(), &out, try lex.tokenize(a, "proc distance data=zc out=o; var interval(x z / std=std); run;", &e.diags));
    try expect(!e.diags.hasErrors());
    try expect(e.lib.find("o") == null);
    var warnings: usize = 0;
    for (e.diags.list.items) |d| if (d.severity == .warning) {
        warnings += 1;
    };
    try expectEqual(@as(usize, 2), warnings);
    try expectEqualStrings("The scale estimator for variable z is less than or equal to 0.  z will not be standardized.", e.diags.list.items[0].message);
    // SAS: an empty input with BY g gives 0 observations and 1 variable (g).
    const em = try a.create(Dataset);
    em.* = Dataset.init(a, "em");
    _ = try em.addColumn("g", .char);
    _ = try em.addColumn("x", .num);
    try e.lib.put("em", em);
    const o = try e.run("proc distance data=em out=o; var interval(x); by g; run;");
    try expectEqual(@as(usize, 1), o.columns.items.len);
    try expectEqualStrings("g", o.columns.items[0].name);
    try expectEqual(@as(usize, 0), o.rows.items.len);
}
