//! STAT-STDIZE-001 permanent tests: PROC statement options, VAR / BY / FREQ /
//! WEIGHT roles, missing-value rules, the closed-form location and scale
//! measures, the OUT= data set and loud gaps. All data are invented (D-011);
//! expected values are hand mathematics stated next to each check.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const stdize = @import("stdize.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// grp 1: x = 1,2,3,6 (f = 1,1,2,1; w = 1,2,1,1); y = 4,.,8,0.
// grp 2: x = 10,10,10,20; y = 1,2,3,4.
fn build(a: A, lib: *Library) !void {
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    for ([_][]const u8{ "grp", "x", "y", "f", "w" }) |n| _ = try d.addColumn(n, .num);
    _ = try d.addColumn("id", .char);
    const rows = [_][5]f64{
        .{ 1, 1, 4, 1, 1 },  .{ 1, 2, nan, 1, 2 }, .{ 1, 3, 8, 2, 1 },  .{ 1, 6, 0, 1, 1 },
        .{ 2, 10, 1, 1, 1 }, .{ 2, 10, 2, 1, 1 },  .{ 2, 10, 3, 1, 1 }, .{ 2, 20, 4, 1, 1 },
    };
    for (rows) |r| try d.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = "a" } });
    try lib.put("d", d);
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
    fn parse(self: *Env, source: []const u8) !stdize.Spec {
        return stdize.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return stdize.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn col(self: *Env, member: []const u8, name: []const u8) ![]f64 {
        const o = self.lib.find(member).?;
        const ci = o.indexOf(name).?;
        const v = try self.arena.allocator().alloc(f64, o.rows.items.len);
        for (o.rows.items, v) |r, *x| x.* = r[ci].num;
        return v;
    }
};

fn fresh() Env {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "STAT-STDIZE-001 PROC statement defaults, explicit options and roles" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    // Defaults (pp.9445-9448): METHOD=STD, ADD=0, MULT=1, FUZZ=1E-14,
    // VARDEF=DF; without VAR all numeric variables not in BY/FREQ/WEIGHT.
    const d = try e.parse("proc stdize; run;");
    try expectEqual(stdize.Method.std, d.method);
    try expect(d.add == 0 and d.mult == 1 and d.fuzz == 1e-14 and d.vardef == .df and d.out == null);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4 }, d.vars);
    const s = try e.parse("proc stdize data=work.d out=o method=range add=-2 mult=.5 fuzz=0 vardef=wgt nomiss replace pstat pctlmtd=ord_stat; by grp; freq f; weight w; run;");
    try expectEqual(stdize.Method.range, s.method);
    try expect(s.add == -2 and s.mult == 0.5 and s.fuzz == 0 and s.vardef == .weight and s.nomiss and s.replace and s.pstat);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, s.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(?usize, 3), s.freq);
    try expectEqual(@as(?usize, 4), s.weight);
    // p.9449: only the last BY statement is used.
    const b = try e.parse("proc stdize data=d; by grp; by f; var x; run;");
    try std.testing.expectEqualSlices(usize, &.{3}, b.by_cols);
    try expectEqual(@as(?f64, 7), (try e.parse("proc stdize data=d missing=7 reponly; run;")).missing);
}

test "STAT-STDIZE-001 invalid input is a user error and documented unimplemented features are loud gaps" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const user = [_][]const u8{
        "proc stdize data=d replace reponly; run;", // pp.9447-9448
        "proc stdize data=d method=bogus; run;",
        "proc stdize data=d; var id; run;", // character VAR
        "proc stdize data=d; var nope; run;",
        "proc stdize data=d; freq f w; run;",
        "proc stdize data=nosuch; run;",
        "proc stdize data=d vardef=xx; run;",
        "proc stdize data=d nonsense; run;",
        "proc stdize data=d initial=abw; run;", // p.9445, SAS ERROR 79-322
        "proc stdize data=d initial=in; run;", // SAS ERROR 22-322
        "proc stdize data=d initial=bogus; run;",
        "proc stdize data=d missing=bogus; run;",
        "proc stdize data=d; freq f / bogus; run;",
    };
    for (user) |src| try std.testing.expectError(error.ParseError, e.parse(src));
    const gaps = [_][]const u8{
        "proc stdize data=d method=l(1.5); run;",
        "proc stdize data=d method=in(x); run;",
        "proc stdize data=d outstat=st; run;",
        "proc stdize data=d oprefix sprefix=s_; run;",
        "proc stdize data=d pctlmtd=onepass; run;",
        "proc stdize data=d missing=abw; run;",
        "proc stdize data=d out=o(keep=x); run;",
        "proc stdize data=d method=abw(4) initial=l(2); run;",
        "proc stdize data=d; location x; run;",
        "proc stdize data=d pctlpts=10 to 90 by 10; run;",
    };
    for (gaps) |src| try std.testing.expectError(error.ParseError, e.parse(src));
    var out: std.ArrayList(u8) = .empty;
    // Weighted percentiles, the remaining PSTAT labels and constant data
    // are implemented under STAT-STDIZE-004 (tests below).
    const run_gaps = [_][]const u8{
        "proc stdize data=d pstat out=o; var x; weight w; run;", // Sum of Weights column
    };
    for (run_gaps) |src| {
        try std.testing.expectError(error.ParseError, e.run(&out, src));
        try expect(e.lib.find("o") == null);
    }
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-STDIZE-001 METHOD=STD with BY, missing values and FREQ" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    // grp 1 y: 4, ., 8, 0 -> mean 4, CSS 32, n-1 = 2, std 4.
    // grp 2 y: 1..4 -> mean 2.5, CSS 5, std sqrt(5/3).
    try e.run(&out, "proc stdize data=d out=o pstat; by grp; var y; run;");
    const y = try e.col("o", "y");
    try approx(@as(f64, 0), y[0], 1e-15);
    try expect(std.math.isNan(y[1]));
    try approx(@as(f64, 1), y[2], 1e-15);
    try approx(@as(f64, -1), y[3], 1e-15);
    try approx(-1.5 / @sqrt(5.0 / 3.0), y[4], 1e-14);
    // OUT= keeps every variable; non-analysis variables are copied.
    try expectEqual(@as(usize, 6), e.lib.find("o").?.columns.items.len);
    try approx(@as(f64, 1), (try e.col("o", "x"))[0], 0);
    const text = out.items;
    try expect(std.mem.indexOf(u8, text, "grp=1") != null);
    try expect(std.mem.indexOf(u8, text, "Location = mean     Scale = standard deviation") != null);
    try expect(std.mem.indexOf(u8, text, "y           4.000000        4.000000           3\n") != null);
    try expect(std.mem.indexOf(u8, text, "y           2.500000        1.290994           4\n") != null);

    // FREQ f in grp 1 x: values 1,2,3,3,6 -> n 5, mean 3, CSS 4+1+0+0+9 = 14,
    // std sqrt(14/4). REPLACE: a missing y becomes 0.
    try e.run(&out, "proc stdize data=d out=o2 replace; by grp; var x y; freq f; run;");
    try approx(-2.0 / @sqrt(3.5), (try e.col("o2", "x"))[0], 1e-14);
    try approx(@as(f64, 0), (try e.col("o2", "y"))[1], 0);
    // NOMISS drops row 2 for every variable: grp 1 x = 1,3,6 -> mean 10/3.
    try e.run(&out, "proc stdize data=d out=o3 method=mean nomiss; by grp; var x y; run;");
    try approx(1 - 10.0 / 3.0, (try e.col("o3", "x"))[0], 1e-14);
}

test "STAT-STDIZE-001 closed-form measures, WEIGHT, VARDEF, ADD/MULT and REPONLY" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const xs = [_]stdize.Obs{ .{ .x = 1, .f = 1, .w = 1 }, .{ .x = 2, .f = 1, .w = 1 }, .{ .x = 3, .f = 1, .w = 1 }, .{ .x = 6, .f = 1, .w = 1 } };
    const Case = struct { m: stdize.Method, loc: f64, scale: f64 };
    // x = 1,2,3,6: sum 12, SS 50, mean 3, CSS 14; median (2+3)/2 = 2.5;
    // Q1 (np = 1, g = 0) = (1+2)/2 = 1.5, Q3 (np = 3) = (3+6)/2 = 4.5;
    // |x - 2.5| = 1.5,.5,.5,3.5 -> MAD (0.5+1.5)/2 = 1.
    const cases = [_]Case{
        .{ .m = .mean, .loc = 3, .scale = 1 },                 .{ .m = .median, .loc = 2.5, .scale = 1 },
        .{ .m = .sum, .loc = 0, .scale = 12 },                 .{ .m = .euclen, .loc = 0, .scale = @sqrt(50.0) },
        .{ .m = .ustd, .loc = 0, .scale = @sqrt(50.0 / 4.0) }, .{ .m = .std, .loc = 3, .scale = @sqrt(14.0 / 3.0) },
        .{ .m = .range, .loc = 1, .scale = 5 },                .{ .m = .midrange, .loc = 3.5, .scale = 2.5 },
        .{ .m = .maxabs, .loc = 0, .scale = 6 },               .{ .m = .iqr, .loc = 2.5, .scale = 3 },
        .{ .m = .mad, .loc = 2.5, .scale = 1 },
    };
    var s = try e.parse("proc stdize data=d; run;");
    for (cases) |c| {
        s.method = c.m;
        const m = (try stdize.measures(a, s, &xs)).?;
        try approx(c.loc, m.location, 1e-14);
        try approx(c.scale, m.scale, 1e-14);
        try approx(@as(f64, 4), m.n, 0);
    }
    // VARDEF=N: std sqrt(14/4).
    s.method = .std;
    s.vardef = .n;
    try approx(@sqrt(3.5), (try stdize.measures(a, s, &xs)).?.scale, 1e-14);
    // Weights 1,2,1,1 (p.9451): sum w 5, mean (1+4+3+6)/5 = 2.8,
    // CSS 1*3.24 + 2*.64 + .04 + 10.24 = 14.8; VARDEF=DF divisor n-1 = 3,
    // VARDEF=WDF divisor 4.
    const ws = [_]stdize.Obs{ .{ .x = 1, .f = 1, .w = 1 }, .{ .x = 2, .f = 1, .w = 2 }, .{ .x = 3, .f = 1, .w = 1 }, .{ .x = 6, .f = 1, .w = 1 } };
    s.vardef = .df;
    const wm = (try stdize.measures(a, s, &ws)).?;
    try approx(@as(f64, 2.8), wm.location, 1e-14);
    try approx(@sqrt(14.8 / 3.0), wm.scale, 1e-14);
    s.vardef = .wdf;
    try approx(@sqrt(14.8 / 4.0), (try stdize.measures(a, s, &ws)).?.scale, 1e-14);
    // Result = add + mult * (x - location) / scale (p.9448).
    s.add = 10;
    s.mult = 2;
    try approx(@as(f64, 14), stdize.standardize(s, .{ .location = 3, .scale = 1, .n = 4 }, 5), 0);

    var out: std.ArrayList(u8) = .empty;
    // REPONLY: grp 1 y missing -> location 4 (mean of 4,8,0); others unchanged.
    try e.run(&out, "proc stdize data=d out=r reponly; by grp; var y; run;");
    const y = try e.col("r", "y");
    try approx(@as(f64, 4), y[1], 0);
    try approx(@as(f64, 8), y[2], 0);
    // MISSING=-1 replaces after standardizing; WEIGHT with METHOD=SUM:
    // grp 1 x weighted sum 1+4+3+6 = 14 -> 1/14.
    try e.run(&out, "proc stdize data=d out=m method=sum missing=-1; by grp; var x y; weight w; run;");
    try approx(@as(f64, -1), (try e.col("m", "y"))[1], 0);
    try approx(@as(f64, 1.0 / 14.0), (try e.col("m", "x"))[0], 1e-15);
    // Without OUT= the DATAn convention names the output.
    try e.run(&out, "proc stdize data=d method=maxabs; var x; run;");
    try approx(@as(f64, 1.0 / 20.0), (try e.col("data1", "x"))[0], 1e-15);
}

// SAS-verified rules (real SAS 9.4 runs on the sample of the corpus fixture
// tests/corpus/stat_stdize001_rules.sas; here on grp 1 of the test data,
// x = 1, 2, 3, 6 with f = 1, 1, 2, 1, w = 1, 2, 1, 1, y = 4, ., 8, 0).
test "STAT-STDIZE-001 repeated declarations, NORM, MISSING=method, NOTRUNCATE and ignored options" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    // Last repeated PROC option wins; VAR statements accumulate; the first
    // FREQ and the first WEIGHT statement are used.
    const s = try e.parse("proc stdize data=d method=mean method=range add=1 add=5 unstd nmarkers=3 pctlpts=10, 150; var x; var y; freq f; freq w; weight w; weight f; run;");
    try expectEqual(stdize.Method.range, s.method);
    try expectEqual(@as(f64, 5), s.add);
    try expectEqual(@as(usize, 2), s.vars.len);
    try expectEqual(@as(?usize, 3), s.freq);
    try expectEqual(@as(?usize, 4), s.weight);
    var out: std.ArrayList(u8) = .empty;
    // NORM: IQR / (2 z.75), MAD / z.75. grp 1 x: median 2.5, IQR 3 -> 2.2239;
    // MAD 1 -> 1.482602.
    try e.run(&out, "proc stdize data=d out=n1 method=mad norm; where grp = 1; var x; run;");
    const n1 = try e.col("n1", "x");
    try approx(@as(f64, -1.5 * 0.6744897501960817), n1[0], 1e-12);
    try e.run(&out, "proc stdize data=d out=n2 method=iqr norm; where grp = 1; var x; run;");
    try approx(@as(f64, (6.0 - 2.5) / (3.0 / (2.0 * 0.6744897501960817))), (try e.col("n2", "x"))[3], 1e-12);
    // NORM with STD: SAS WARNING, ignored.
    try e.run(&out, "proc stdize data=d out=n3 method=std norm; where grp = 1; var x; run;");
    try approx(@as(f64, -2.0 / @sqrt(14.0 / 3.0)), (try e.col("n3", "x"))[0], 1e-12);
    try expect(e.diags.warning_status);
    // MISSING=RANGE with METHOD=STD and REPLACE: y = 4, 8, 0, mean 4, std 4,
    // minimum 0 -> the missing y becomes (0 - 4) / 4 = -1 (MISSING= wins over
    // REPLACE); with REPONLY it becomes the minimum 0.
    try e.run(&out, "proc stdize data=d out=m1 replace missing=range; where grp = 1; var y; run;");
    try approx(@as(f64, -1), (try e.col("m1", "y"))[1], 1e-12);
    try e.run(&out, "proc stdize data=d out=m2 reponly missing=range; where grp = 1; var y; run;");
    try approx(@as(f64, 0), (try e.col("m2", "y"))[1], 1e-12);
    // REPLACE with ADD=10: a missing value still becomes 0.
    try e.run(&out, "proc stdize data=d out=m3 replace add=10; where grp = 1; var y; run;");
    try approx(@as(f64, 0), (try e.col("m3", "y"))[1], 1e-12);
    try approx(@as(f64, 10), (try e.col("m3", "y"))[0], 1e-12);
    // REPLACE with MISSING=99: 99.
    try e.run(&out, "proc stdize data=d out=m4 replace missing=99; where grp = 1; var y; run;");
    try approx(@as(f64, 99), (try e.col("m4", "y"))[1], 1e-12);
    // WEIGHT with RANGE is ignored: (x - 1) / 5.
    try e.run(&out, "proc stdize data=d out=w1 method=range; where grp = 1; var x; weight w; run;");
    try approx(@as(f64, 0.2), (try e.col("w1", "x"))[1], 1e-12);
}

test "STAT-STDIZE-002 default path: METHOD=STD location, scale, N and standardized values" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // Getting Started (pp.9449-9455), published High School Scores urban
    // totals: Figure 115.3 reports mean 153.300000, std 30.066768, N 20;
    // removing the outlier 64 gives Figure 115.7: 158.000000, 22.088207, 19.
    const urban = [_]f64{ 192, 186, 64, 159, 133, 163, 130, 163, 189, 144, 154, 198, 150, 151, 152, 151, 127, 167, 170, 123 };
    var obs: [urban.len]stdize.Obs = undefined;
    for (urban, &obs) |v, *o| o.* = .{ .x = v, .f = 1, .w = 1 };
    const s = try e.parse("proc stdize data=d; run;");
    try expectEqual(stdize.Method.std, s.method);
    const m = (try stdize.measures(a, s, &obs)).?;
    try approx(@as(f64, 153.3), m.location, 1e-12);
    try approx(@as(f64, 30.066768), m.scale, 5e-7);
    try approx(@as(f64, 20), m.n, 0);
    var kept: [urban.len - 1]stdize.Obs = undefined;
    @memcpy(kept[0..2], obs[0..2]);
    @memcpy(kept[2..], obs[3..]);
    const m2 = (try stdize.measures(a, s, &kept)).?;
    try approx(@as(f64, 158), m2.location, 1e-12);
    try approx(@as(f64, 22.088207), m2.scale, 5e-7);
    try approx(@as(f64, 19), m2.n, 0);

    // Default run (no METHOD=) on the invented d, BY grp, VAR x:
    // grp 1 x = 1,2,3,6 -> mean 3, CSS 14, std sqrt(14/3);
    // grp 2 x = 10,10,10,20 -> mean 12.5, CSS 75, std 5 -> -0.5 and 1.5.
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc stdize data=d out=o pstat; by grp; var x; run;");
    const x = try e.col("o", "x");
    try approx(-2.0 / @sqrt(14.0 / 3.0), x[0], 1e-14);
    try approx(3.0 / @sqrt(14.0 / 3.0), x[3], 1e-14);
    try approx(@as(f64, -0.5), x[4], 1e-14);
    try approx(@as(f64, 1.5), x[7], 1e-14);
    try expect(std.mem.indexOf(u8, out.items, "Location = mean     Scale = standard deviation") != null);
    try expect(std.mem.indexOf(u8, out.items, "x          12.500000        5.000000           4\n") != null);
    try expect(!e.diags.hasErrors());
}

// STAT-STDIZE-003. Independent values (Python double precision, formulas in
// stdize.zig): Getting Started High School Scores, METHOD=ABW(4) by Type =
// SAS Figure values 162.889603 / 56.662855 and 156.014608 / 28.615980.
fn sample(a: A, lib: *Library, name: []const u8, xs: []const f64) !void {
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, name);
    _ = try d.addColumn("x", .num);
    for (xs) |v| try d.appendRow(&.{.{ .num = v }});
    try lib.put(name, d);
}
fn measuresOf(e: *Env, name: []const u8, source: []const u8) !stdize.Measures {
    const a = e.arena.allocator();
    const s = try e.parse(source);
    const obs = try stdize.usable(a, s, e.lib.find(name).?.rows.items, 0);
    return (try stdize.measures(a, s, obs)).?;
}

test "STAT-STDIZE-003 ABW/AHUBER/AWAVE one-step M and A estimates, INITIAL=, fallback" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    try sample(a, &e.lib, "rural", &.{ 135, 125, 223, 224, 133, 253, 144, 193, 152, 178, 120, 180, 154, 184, 187, 111, 190, 128, 110, 217 });
    try sample(a, &e.lib, "urban", &.{ 192, 186, 64, 159, 133, 163, 130, 163, 189, 144, 154, 198, 150, 151, 152, 151, 127, 167, 170, 123 });
    try sample(a, &e.lib, "q", &.{ 1, 2, 3, 4, 5, 7, 9, 12, 20, 6 });
    const cases = [_]struct { []const u8, []const u8, f64, f64 }{
        .{ "rural", "proc stdize data=rural method=abw(4); run;", 162.88960266660072, 56.66285509704131 },
        .{ "urban", "proc stdize data=urban method=abw(4); run;", 156.0146076037435, 28.61598005998426 },
        .{ "q", "proc stdize data=q method=abw(4); run;", 5.071408874698923, 4.214243872240831 },
        .{ "q", "proc stdize data=q method=ahuber(1.5); run;", 5.75, 4.093100563414271 },
        .{ "q", "proc stdize data=q method=awave(2); run;", 4.157533702259344, 5.631540598176874 },
        .{ "q", "proc stdize data=q method=abw(4) initial=std; run;", 6.034944708146367, 5.270738112216381 },
        .{ "q", "proc stdize data=q method=ahuber(1.5) initial=iqr; run;", 6.444444444444445, 4.958676977405883 },
        .{ "q", "proc stdize data=q method=abw(3) initial=agk(0.3); run;", 2.979695884661954, 14.57040803412282 },
        .{ "q", "proc stdize data=q method=ahuber(2) initial=spacing(0.4); run;", 6.571428571428571, 5.866040473692818 },
        .{ "q", "proc stdize data=q method=abw(0.5); run;", 5.5, 2.357022603955158 },
        // No accepted value: median and raw MAD, flagged for the SAS NOTE.
        .{ "q", "proc stdize data=q method=ahuber(0.1); run;", 5.5, 3 },
        // Hand: SPACING(0.5), k = 4: min x(i+4) - x(i) = 5 - 1, mid 3.
        .{ "q", "proc stdize data=q method=spacing(0.5); run;", 3, 4 },
        // k = ceil(5.5) - 1 = 5: 6 - 1 = 5, mid 3.5.
        .{ "q", "proc stdize data=q method=spacing(0.55); run;", 3.5, 5 },
        // k = ceil(3) - 1 = 2 (3 = 0.3 * 10 despite rounding): 3 - 1, mid 2.
        .{ "q", "proc stdize data=q method=spacing(0.3); run;", 2, 2 },
        // Hand: AGK(0.2): m = 9 of 45 pairs, threshold 2, the 12 pairs with
        // d <= 2 (6 ones, 6 twos): sqrt(30 / 24) = sqrt(1.25).
        .{ "q", "proc stdize data=q method=agk(0.2); run;", 6.9, @sqrt(1.25) },
        // AGK(1): all pairs, sum d^2 = n * CSS = 2889; sqrt(2889 / 90) = std.
        .{ "q", "proc stdize data=q method=agk(1); run;", 6.9, @sqrt(32.1) },
    };
    for (cases) |c| {
        const m = try measuresOf(&e, c[0], c[1]);
        try approx(c[2], m.location, 1e-12);
        try approx(c[3], m.scale, 1e-12);
    }
    try expect((try measuresOf(&e, "q", "proc stdize data=q method=ahuber(0.1); run;")).fallback);
    try expect(!(try measuresOf(&e, "q", "proc stdize data=q method=ahuber(1.5); run;")).fallback);
    // SPACING NORM: 2 / (2 z(0.65)) = 2.595242 (SAS PSTAT).
    try approx(2.595242, (try measuresOf(&e, "q", "proc stdize data=q method=spacing(0.3) norm; run;")).norm.?, 5e-7);
    // Boundary arguments are user errors (SAS-verified texts) or loud gaps.
    const user = [_][]const u8{
        "proc stdize data=q method=abw(-1); run;",
        "proc stdize data=q method=ahuber(0); run;",
        "proc stdize data=q method=spacing(0); run;",
        "proc stdize data=q method=agk(0); run;",
        "proc stdize data=q method=awave; run;",
        "proc stdize data=q method=in(nosuch); run;",
        "proc stdize data=q method=std; location x; run;",
    };
    for (user) |src| try std.testing.expectError(error.ParseError, e.parse(src));
}

test "STAT-STDIZE-003 METHOD=IN(ds): _TYPE_ rows, LOCATION/SCALE, ADD/MULT and UNSTD" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    try sample(a, &e.lib, "q", &.{ 1, 6 });
    const ins = try a.create(Dataset);
    ins.* = Dataset.init(a, "ins");
    _ = try ins.addColumn("_type_", .char);
    _ = try ins.addColumn("x", .num);
    for ([_][]const u8{ "LOCATION", "SCALE", "ADD", "MULT" }, [_]f64{ 2, 4, 1, 2 }) |k, v| try ins.appendRow(&.{ .{ .str = k }, .{ .num = v } });
    try e.lib.put("ins", ins);
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc stdize data=q method=in(ins) out=o; var x; run;");
    // Hand: 1 + 2 (x - 2) / 4 -> 0.5, 3.
    const z = try e.col("o", "x");
    try approx(0.5, z[0], 1e-15);
    try approx(3.0, z[1], 1e-15);
    try e.run(&out, "proc stdize data=o method=in(ins) unstd out=back; var x; run;");
    const b = try e.col("back", "x");
    try approx(1.0, b[0], 1e-15);
    try approx(6.0, b[1], 1e-15);
    const ls = try a.create(Dataset);
    ls.* = Dataset.init(a, "ls");
    for ([_][]const u8{ "lx", "sx" }) |n| _ = try ls.addColumn(n, .num);
    try ls.appendRow(&.{ .{ .num = 2 }, .{ .num = 4 } });
    try e.lib.put("ls", ls);
    try e.run(&out, "proc stdize data=q method=in(ls) out=o3; var x; location lx; scale sx; run;");
    const c = try e.col("o3", "x");
    try approx(-0.25, c[0], 1e-15);
    try approx(1.0, c[1], 1e-15);
    try std.testing.expectError(error.ParseError, e.run(&out, "proc stdize data=q method=in(ls) out=o4; var x; run;"));
}

fn obsOf(a: A, xs: []const f64, ws: ?[]const f64, fs: ?[]const f64) ![]stdize.Obs {
    const o = try a.alloc(stdize.Obs, xs.len);
    for (o, 0..) |*e, i| e.* = .{ .x = xs[i], .w = if (ws) |w| w[i] else 1, .f = if (fs) |f| f[i] else 1 };
    return o;
}

test "STAT-STDIZE-004 PCTLDEF=1..5 and weighted percentiles" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // Ten values (pp.9455-9456), hand: median np = 5 (g = 0), quartiles
    // np = 2.5 / 7.5; 4: (n+1)p = 5.5, 2.75, 8.25.
    const a10 = try obsOf(a, &.{ 144, 2, 3, 5, 8, 13, 21, 34, 55, 89 }, null, null);
    const med = [_]f64{ 13, 13, 13, 17, 17 };
    const q1 = [_]f64{ 4, 3, 5, 4.5, 5 };
    const q3 = [_]f64{ 44.5, 55, 55, 63.5, 55 };
    for (1..6) |d| {
        try approx(med[d - 1], try stdize.percentile(a, a10, 0.5, @intCast(d), false), 1e-12);
        try approx(q1[d - 1], try stdize.percentile(a, a10, 0.25, @intCast(d), false), 1e-12);
        try approx(q3[d - 1], try stdize.percentile(a, a10, 0.75, @intCast(d), false), 1e-12);
    }
    // Seven values: PCTLDEF=2 q3 i = int(5.25 + .5) = 5 -> 25, q1 -> 4;
    // PCTLDEF=1 q1 .25*1 + .75*4 = 3.25. Six values, PCTLDEF=2, g = 1/2:
    // q1 j = 1 odd -> x_2 = 20, q3 j = 4 even -> x_4 = 40.
    const a7 = try obsOf(a, &.{ 49, 1, 36, 4, 25, 9, 16 }, null, null);
    try approx(@as(f64, 25), try stdize.percentile(a, a7, 0.75, 2, false), 0);
    try approx(@as(f64, 4), try stdize.percentile(a, a7, 0.25, 2, false), 0);
    try approx(@as(f64, 3.25), try stdize.percentile(a, a7, 0.25, 1, false), 1e-12);
    const a6 = try obsOf(a, &.{ 10, 20, 30, 40, 50, 60 }, null, null);
    try approx(@as(f64, 20), try stdize.percentile(a, a6, 0.25, 2, false), 0);
    try approx(@as(f64, 40), try stdize.percentile(a, a6, 0.75, 2, false), 0);
    // Weighted (SAS 15.4 rule): weights 1,2,.5,3,1,2.5 (W = 10): median
    // pW = 5 -> x_4 = 4; q3 pW = 7.5 equals the cumulative weight of x_5 ->
    // x_5 = 5 (the guide's average would give 5.5); q1 pW = 2.5 -> 2.
    const w = try obsOf(a, &.{ 1, 2, 3, 4, 5, 6 }, &.{ 1, 2, 0.5, 3, 1, 2.5 }, null);
    try approx(@as(f64, 4), try stdize.percentile(a, w, 0.5, 5, true), 0);
    try approx(@as(f64, 5), try stdize.percentile(a, w, 0.75, 5, true), 0);
    try approx(@as(f64, 2), try stdize.percentile(a, w, 0.25, 5, true), 0);
    // Equal weights 2 on the ten values: median x_5 = 13 (SAS), not 17.
    for (a10) |*o| o.w = 2;
    try approx(@as(f64, 13), try stdize.percentile(a, a10, 0.5, 5, true), 0);
    // WEIGHT with FREQ uses w f: 2,2,.5,3,2 (W 9.5), pW 4.75 -> x_4 = 4.
    const wf = try obsOf(a, &.{ 1, 2, 3, 4, 5 }, &.{ 1, 2, 0.5, 3, 1 }, &.{ 2, 1, 1, 1, 2 });
    try approx(@as(f64, 4), try stdize.percentile(a, wf, 0.5, 5, true), 0);
    // MAD with PCTLDEF=4 on the ten values: median 17, |x - 17| median 14.5.
    var s = try e.parse("proc stdize data=d method=mad pctldef=4; run;");
    for (a10) |*o| o.w = 1;
    const m = (try stdize.measures(a, s, a10)).?;
    try approx(@as(f64, 17), m.location, 0);
    try approx(@as(f64, 14.5), m.scale, 1e-12);
    s.pctldef = 1;
    try approx(@as(f64, 10), (try stdize.measures(a, s, a10)).?.scale, 1e-12);
    try std.testing.expectError(error.ParseError, e.parse("proc stdize data=d pctldef=6; run;"));
    try std.testing.expectError(error.ParseError, e.parse("proc stdize data=d pctldef=0; run;"));
}

test "STAT-STDIZE-004 constant data, empty samples, USTD divisor and FUZZ" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    var s = try e.parse("proc stdize data=d; run;");
    // No usable value: location missing except EUCLEN/MAXABS (0), scale
    // missing except MEDIAN (1) -- SAS-verified for every method.
    const none = [_]stdize.Obs{};
    for ([_]stdize.Method{ .mean, .median, .sum, .euclen, .ustd, .std, .range, .midrange, .maxabs, .iqr, .mad, .spacing }) |meth| {
        s.method = meth;
        const m = (try stdize.measures(a, s, &none)).?;
        try expect(m.empty and m.n == 0);
        try expect(std.math.isNan(m.location) == (meth != .euclen and meth != .maxabs));
        try expect(std.math.isNan(m.scale) == (meth != .median));
    }
    // One value, VARDEF=DF: STD keeps the mean, scale missing; USTD uses
    // n (x = 4, 6: sqrt(26), SAS-verified).
    s.method = .std;
    const one = [_]stdize.Obs{.{ .x = 7, .f = 1, .w = 1 }};
    const m1 = (try stdize.measures(a, s, &one)).?;
    try expect(m1.location == 7 and std.math.isNan(m1.scale));
    s.method = .ustd;
    const two = [_]stdize.Obs{ .{ .x = 4, .f = 1, .w = 1 }, .{ .x = 6, .f = 1, .w = 1 } };
    try approx(@sqrt(26.0), (try stdize.measures(a, s, &two)).?.scale, 1e-14);
    // FUZZ=0.2 on 3,3,3,4: std 0.5 < 3.25 * 0.2 is reported 0 but kept.
    s.method = .std;
    s.fuzz = 0.2;
    const f0 = [_]stdize.Obs{ .{ .x = 3, .f = 1, .w = 1 }, .{ .x = 3, .f = 1, .w = 1 }, .{ .x = 3, .f = 1, .w = 1 }, .{ .x = 4, .f = 1, .w = 1 } };
    const mf = (try stdize.measures(a, s, &f0)).?;
    try expect(mf.fuzzed);
    try approx(@as(f64, 0.5), mf.scale, 1e-14);
    // Run: f is constant (1) in grp 2 -> WARNING, copied unstandardized.
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc stdize data=d out=o pstat; by grp; var f; run;");
    const v = try e.col("o", "f");
    for (v[4..]) |x| try expectEqual(@as(f64, 1), x);
    try expect(std.mem.indexOf(u8, out.items, "f           1.000000               .           4") != null);
    var warned = false;
    for (e.diags.list.items) |d| if (std.mem.startsWith(u8, d.message, "The scale estimator for variable f is less than or equal to 0.")) {
        warned = true;
    };
    try expect(warned);
}
