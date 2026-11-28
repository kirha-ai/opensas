//! STAT-PRINQUAL-001 permanent tests: PROC statement options and aliases,
//! the TRANSFORM / BY / FREQ / ID / WEIGHT roles, observation selection,
//! the MTV criterion, the OUT= data set and loud execution boundaries. All
//! data are invented (D-011). Expected values come from a SAS 9.4 run of the
//! same programs on the same data (stated next to each check) or from hand
//! mathematics, never from opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const prinqual = @import("prinqual.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
const Row = struct { g: f64, id: []const u8, x: f64, y: f64, z: f64, f: f64, w: f64 };
// columns: 0 g, 1 id, 2 x, 3 y, 4 z, 5 f, 6 w.
const sample = [_]Row{
    .{ .g = 1, .id = "a", .x = 1, .y = 2, .z = 3, .f = 1, .w = 1 },
    .{ .g = 1, .id = "b", .x = 2, .y = 1, .z = 5, .f = 2, .w = 0.5 },
    .{ .g = 1, .id = "c", .x = 3, .y = 4, .z = 4, .f = 0.5, .w = 1 }, // FREQ < 1
    .{ .g = 1, .id = "d", .x = 4, .y = 3, .z = 7, .f = 2.7, .w = 1 }, // FREQ integer portion 2
    .{ .g = 1, .id = "e", .x = nan, .y = 5, .z = 1, .f = 1, .w = 1 }, // missing IDENTITY value
    .{ .g = 1, .id = "k", .x = 5, .y = 6, .z = 6, .f = 1, .w = 0 }, // WEIGHT = 0
    .{ .g = 2, .id = "f", .x = 5, .y = 5, .z = 2, .f = 1, .w = 1 },
    .{ .g = 2, .id = "h", .x = 6, .y = 7, .z = 9, .f = 1, .w = 1 },
    .{ .g = 2, .id = "i", .x = 7, .y = 6, .z = 4, .f = 1, .w = 2 },
    .{ .g = 2, .id = "j", .x = 8, .y = 9, .z = 8, .f = 1, .w = 1 },
};

fn build(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "a");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("id", .char);
    for ([_][]const u8{ "x", "y", "z", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
    for (sample) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .str = r.id }, .{ .num = r.x }, .{ .num = r.y }, .{ .num = r.z }, .{ .num = r.f }, .{ .num = r.w } });
    try lib.put("a", ds);
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        try build(a, &self.lib);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !prinqual.Spec {
        return prinqual.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return prinqual.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

fn columnNames(a: A, ds: *const Dataset) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    for (ds.columns.items, 0..) |c, k| {
        if (k > 0) try list.append(a, ' ');
        try list.appendSlice(a, c.name);
    }
    return list.items;
}

test "STAT-PRINQUAL-001 PROC statement defaults, explicit options and aliases" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Documented defaults (pp.8040-8048): most recent data set, MTV, N=2,
    // MAXITER=30, CONVERGE=0.00001, CCONVERGE=0, TSTANDARD=ORIGINAL,
    // TPREFIX=T, PREFIX=Prin, TYPE='SCORE', SINGULAR=1E-8, REFRESH=5.
    const d = try e.parse("proc prinqual; transform identity(x y);");
    try expectEqual(prinqual.Method.mtv, d.method);
    try expectEqual(@as(usize, 2), d.n);
    try expectEqual(@as(usize, 30), d.maxiter);
    try approx(@as(f64, 0.00001), d.converge, 0);
    try approx(@as(f64, 0), d.cconverge, 0);
    try expectEqual(prinqual.TStandard.original, d.tstandard);
    try expectEqualStrings("T", d.tprefix);
    try expectEqualStrings("Prin", d.prefix);
    try expectEqualStrings("SCORE", d.type_value);
    try approx(@as(f64, 1e-8), d.singular, 0);
    try expectEqual(@as(usize, 5), d.refresh);
    try expect(!d.cov and !d.replace and !d.nomiss and !d.noprint and d.out == null);
    try expectEqual(@as(usize, 2), d.vars.len);
    // Explicit settings and the documented aliases.
    const x = try e.parse("proc prinqual data=a out=o met=mac n=1 max=5 con=0.001 cco=-2 tst=cen tpr=Q_ pre=P typ='CORR' sin=1e-6 ref=3 cov rep nom nop noc dum rei mon=AD unt=EF; transform ide(x y z); id id; freq f; weight w; by g;");
    try expectEqual(prinqual.Method.mac, x.method);
    try expectEqual(@as(usize, 1), x.n);
    try expectEqual(@as(usize, 5), x.maxiter);
    try approx(@as(f64, 0.001), x.converge, 0);
    try approx(@as(f64, -2), x.cconverge, 0);
    try expectEqual(prinqual.TStandard.center, x.tstandard);
    try expectEqualStrings("Q_", x.tprefix);
    try expectEqualStrings("P", x.prefix);
    try expectEqualStrings("CORR", x.type_value);
    try approx(@as(f64, 1e-6), x.singular, 0);
    try expectEqual(@as(usize, 3), x.refresh);
    try expect(x.cov and x.replace and x.nomiss and x.noprint and x.nocheck and x.dummy and x.reiterate);
    try expectEqual([2]u8{ 'A', 'D' }, x.monotone.?);
    try expectEqual([2]u8{ 'E', 'F' }, x.untie.?);
    try expectEqualStrings("o", x.out.?);
    try expectEqual(@as(usize, 3), x.vars.len);
    try expectEqual(@as(usize, 1), x.ids.len);
    try expectEqual(@as(?usize, 5), x.freq);
    try expectEqual(@as(?usize, 6), x.weight);
    try expectEqual(@as(usize, 1), x.by_cols.len);
    // Several IDENTITY lists in one statement; variable lists; BY: the last one is used.
    const l = try e.parse("proc prinqual data=a; transform identity(x) identity(y--z); by id; by g;");
    try expectEqual(@as(usize, 3), l.vars.len);
    try expectEqual(@as(usize, 0), l.by_cols[0]);
}

test "STAT-PRINQUAL-001 BY, FREQ, WEIGHT, ID selection and OUT= layout (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc prinqual data=a out=o1 n=1; transform identity(x y z); id id; by g; freq f; weight w; run;");
    try expect(!e.diags.hasErrors());
    // SAS 9.4: Proportion of Variance 0.86470 (g=1) and 0.78284 (g=2); the
    // g=1 group (3 active observations, 3 variables) adds two warnings.
    try expect(std.mem.indexOf(u8, out.items, "0.86470") != null);
    try expect(std.mem.indexOf(u8, out.items, "0.78284") != null);
    try expect(std.mem.indexOf(u8, out.items, "g=1") != null and std.mem.indexOf(u8, out.items, "g=2") != null);
    try expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "WARNING: Multiple optimal solutions may exist."));
    const o = e.lib.find("o1").?;
    // SAS 9.4 PROC CONTENTS VARNUM of the same step.
    try expectEqualStrings("g _TYPE_ _NAME_ f w x y z Tx Ty Tz id", try columnNames(e.arena.allocator(), o));
    try expectEqualStrings("x Transformation", o.columns.items[8].label.?);
    try expectEqual(@as(usize, 10), o.rows.items.len);
    // Passive rows c (FREQ 0.5), e (missing x), k (WEIGHT 0) have a blank
    // _TYPE_; _NAME_ is the ID value; T values equal the IDENTITY values.
    const types = [_][]const u8{ "SCORE", "SCORE", "", "SCORE", "", "", "SCORE", "SCORE", "SCORE", "SCORE" };
    for (o.rows.items, types, sample) |row, ty, r| {
        try expectEqualStrings(ty, row[1].str);
        try expectEqualStrings(r.id, row[2].str);
        try expect(std.math.isNan(r.x) == std.math.isNan(row[8].num));
        if (!std.math.isNan(r.x)) try approx(r.x, row[8].num, 0);
        try approx(r.f, row[3].num, 0); // FREQ kept untruncated in OUT=
    }
}

test "STAT-PRINQUAL-001 criterion, COVARIANCE, TSTANDARD= and REPLACE (SAS reference and hand math)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    // Two variables, N=1: proportion = (1 + |r|) / 2. Active rows exclude e:
    // x = 1,2,3,4,5,5,6,7,8; y = 2,1,4,3,6,5,7,6,9 (hand: Sxx = 42.2222,
    // Syy = 51.5556, Sxy = 43.1111, r = 0.924019).
    const m = try e.parse("proc prinqual data=a n=1; transform identity(x y);");
    const rows = e.lib.find("a").?.rows.items;
    const sel = try prinqual.select(e.arena.allocator(), m, e.lib.find("a").?, rows);
    try expectEqual(@as(usize, 9), sel.rows);
    try expectEqual(@as(usize, 1), sel.missing);
    const mm = (try prinqual.moments(e.arena.allocator(), m, rows, sel)).?;
    const r: f64 = 43.1111111111 / @sqrt(42.2222222222 * 51.5555555556);
    try approx(r, mm.matrix[1], 1e-9);
    try approx((1 + r) / 2, try prinqual.proportion(e.arena.allocator(), mm, 2, 1), 1e-9);
    // SAS 9.4: COV TSTANDARD=Z REPLACE, criterion 0.97452; Z values of row a.
    try e.run(&out, "proc prinqual data=a out=o2 cov tstandard=z replace; transform identity(x y z); id id g; run;");
    try expect(std.mem.indexOf(u8, out.items, "0.97452") != null);
    const o2 = e.lib.find("o2").?;
    try expectEqualStrings("_TYPE_ _NAME_ x y z id g", try columnNames(e.arena.allocator(), o2));
    try approx(@as(f64, -1.54768), o2.rows.items[0][2].num, 5e-6);
    try approx(@as(f64, -1.09422), o2.rows.items[0][3].num, 5e-6);
    try approx(@as(f64, 0.08754), o2.rows.items[4][3].num, 5e-6); // passive row standardized too
    try expect(std.math.isNan(o2.rows.items[4][2].num));
    // SAS 9.4: TSTANDARD=CENTER TPREFIX=Q_, criterion 0.97483; Q_x = x - 41/9.
    out.clearRetainingCapacity();
    try e.run(&out, "proc prinqual data=a out=o3 tstandard=center tprefix=Q_; transform identity(x y z); run;");
    try expect(std.mem.indexOf(u8, out.items, "0.97483") != null);
    const o3 = e.lib.find("o3").?;
    try expectEqualStrings("_TYPE_ _NAME_ x y z Q_x Q_y Q_z", try columnNames(e.arena.allocator(), o3));
    try approx(1 - 41.0 / 9.0, o3.rows.items[0][5].num, 1e-12);
    try expectEqualStrings("ROW10", o3.rows.items[9][1].str);
    // SAS 9.4: N equal to the number of variables accounts for all variance.
    out.clearRetainingCapacity();
    try e.run(&out, "proc prinqual data=a n=3 noprint; transform identity(x y z); run;");
    try expectEqual(@as(usize, 0), out.items.len); // NOPRINT: no listing, data set DATA1 still created
    try expect(e.lib.find("DATA1") != null);
}

test "STAT-PRINQUAL-001 TYPE= selection excludes nonmatching rows from analysis and OUT= (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc prinqual data=a out=b; transform identity(x y z); run;");
    // Mark the second row as a CORR row, as SAS's DATA step test did.
    const b = e.lib.find("b").?;
    const second = try e.arena.allocator().dupe(@import("../value.zig").Value, b.rows.items[1]);
    second[0] = .{ .str = "CORR" };
    b.rows.items[1] = second;
    out.clearRetainingCapacity();
    try e.run(&out, "proc prinqual data=b out=o4 noprint; transform identity(x y); run;");
    const o4 = e.lib.find("o4").?;
    // SAS 9.4: 9 observations and 6 variables; the passive row is ROW4.
    try expectEqual(@as(usize, 9), o4.rows.items.len);
    try expectEqualStrings("_TYPE_ _NAME_ x y Tx Ty", try columnNames(e.arena.allocator(), o4));
    try expectEqualStrings("", o4.rows.items[3][0].str);
    try expectEqualStrings("ROW4", o4.rows.items[3][1].str);
    try approx(@as(f64, 3), o4.rows.items[1][2].num, 0);
}

test "STAT-PRINQUAL-001 empty input, N= above the variable count, formatted ID and BY row names (SAS reference)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // num carries format Z5.1; groups 1 and 3 of a SAS 9.4 run (D-011: invented).
    const q = try a.create(Dataset);
    q.* = Dataset.init(a, "q");
    for ([_][]const u8{ "g", "num", "x", "y", "z" }) |n| _ = try q.addColumn(n, .num);
    q.setFormat("num", "z5.1");
    const data = [_][5]f64{ .{ 1, 1, 1, 2, 3 }, .{ 1, 2, 2, 1, 5 }, .{ 1, 3, 3, 4, 4 }, .{ 3, 6, 5, 5, 2 }, .{ 3, 7, 6, 7, 9 }, .{ 3, 8, 7, 6, 4 }, .{ 3, 9, 8, 9, 8 } };
    for (data) |r| try q.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] } });
    try e.lib.put("q", q);
    const empty = try a.create(Dataset);
    empty.* = Dataset.init(a, "empty");
    for ([_][]const u8{ "x", "y", "z" }) |n| _ = try empty.addColumn(n, .num);
    try e.lib.put("empty", empty);
    var out: std.ArrayList(u8) = .empty;
    // SAS 9.4: "NOTE: No observations in data set WORK.E.", no listing, and
    // WORK.OE with 0 observations and 6 variables.
    try e.run(&out, "proc prinqual data=empty out=oe; transform identity(x y); run;");
    try expectEqual(@as(usize, 0), out.items.len);
    const oe = e.lib.find("oe").?;
    try expectEqual(@as(usize, 0), oe.rows.items.len);
    try expectEqual(@as(usize, 6), oe.columns.items.len);
    // SAS 9.4: N=5 for 3 variables warns "N=3 assumed." and reports 1.00000.
    try e.run(&out, "proc prinqual data=q out=on n=5; transform identity(x y z); run;");
    try expect(std.mem.indexOf(u8, out.items, "1.00000") != null);
    var assumed = false;
    for (e.diags.list.items) |d| {
        if (d.severity == .warning and std.mem.indexOf(u8, d.message, "N=3 assumed.") != null) assumed = true;
    }
    try expect(assumed);
    // SAS 9.4: _NAME_ is the formatted ID value ("001.0"); the ID column is last.
    try e.run(&out, "proc prinqual data=q out=oid nomiss; transform identity(x y z); id num; run;");
    const oid = e.lib.find("oid").?;
    try expectEqualStrings("_TYPE_ _NAME_ x y z Tx Ty Tz num", try columnNames(a, oid));
    try expectEqualStrings("001.0", oid.rows.items[0][1].str);
    // SAS 9.4: BY groups restart ROW1, ROW2, ... and the g=1 group (3
    // observations, 3 variables) gets the two warnings; g=3 reports 0.97868.
    out.clearRetainingCapacity();
    try e.run(&out, "proc prinqual data=q out=oby; transform identity(x y z); by g; run;");
    try expect(std.mem.indexOf(u8, out.items, "0.97868") != null);
    try expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "WARNING: Multiple optimal solutions may exist."));
    const oby = e.lib.find("oby").?;
    try expectEqualStrings("g _TYPE_ _NAME_ x y z Tx Ty Tz", try columnNames(a, oby));
    try expectEqualStrings("ROW3", oby.rows.items[2][2].str);
    try expectEqualStrings("ROW1", oby.rows.items[3][2].str);
    try expectEqualStrings("ROW4", oby.rows.items[6][2].str);
}

test "STAT-PRINQUAL-001 invalid input is a user error and unimplemented valid syntax is a loud gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors (rc 1). The TRANSFORM and N= messages are SAS's (verified).
        .{ .source = "proc prinqual data=a; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x) identity(y z); transform identity(x); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a n=0; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=nosuch; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a method=xyz; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a tstandard=q; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a monotone=FA; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a untie=A; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a nosuchoption; transform identity(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x id); run;", .rc = 1 }, // character IDENTITY
        .{ .source = "proc prinqual data=a; transform identity(x nosuch); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform nosuch(x y); run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity x y; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x y); freq id; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x y); weight; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x y); id nosuch; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x y); by nosuch; run;", .rc = 1 },
        .{ .source = "proc prinqual data=a; transform identity(x y); by descending g; run;", .rc = 1 }, // not sorted
        .{ .source = "proc prinqual data=a; transform identity(x y); model x = y; run;", .rc = 1 },
        // Valid SAS owned by later tickets or not verified (D-009 gap, rc 2).
        .{ .source = "proc prinqual data=a out=o; transform spline(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform opscore(id) identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform identity(x y / reflect); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform identity(x x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o scores; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o approximations; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o aprefix=B; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o correlations; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o mdpref; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o standard; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o plots=all; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o method=mgv; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o converge=-1; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o change=2; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o inititer=1; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o n=1 n=2; transform identity(x y); run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o tstandard=z; transform identity(x y); weight w; run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform identity(x y); freq f; freq f; run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform identity(x y); format x 8.2; run;", .rc = 2 },
        .{ .source = "proc prinqual data=a out=o; transform identity(x g); by g; run;", .rc = 2 }, // constant in a group
        .{ .source = "proc prinqual data=a out=o; transform identity(x y); where g = 2 and x > 7; run;", .rc = 2 }, // one active row
        .{ .source = "proc prinqual data=a out=o method=mac; transform identity(x y z); by g; freq f; weight w; run;", .rc = 2 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = prinqual.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expect(d.hasErrors());
        try expectEqual(@as(usize, 0), output.items.len); // never a partial or fake table
        try expect(lib.find("o") == null and lib.find("DATA1") == null); // nor a data set
    }
}
