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
    };
    for (user) |src| try std.testing.expectError(error.ParseError, e.parse(src));
    const gaps = [_][]const u8{
        "proc stdize data=d method=abw(4); run;",
        "proc stdize data=d method=in(x); run;",
        "proc stdize data=d outstat=st; run;",
        "proc stdize data=d oprefix sprefix=s_; run;",
        "proc stdize data=d pctlmtd=onepass; run;",
        "proc stdize data=d missing=mean; run;",
        "proc stdize data=d out=o(keep=x); run;",
        "proc stdize data=d method=std method=std; run;",
        "proc stdize data=d; location x; run;",
        "proc stdize data=d norm; run;",
    };
    for (gaps) |src| try std.testing.expectError(error.ParseError, e.parse(src));
    var out: std.ArrayList(u8) = .empty;
    const run_gaps = [_][]const u8{
        "proc stdize data=d method=iqr out=o; var x; weight w; run;",
        "proc stdize data=d method=mean pstat out=o; var x; run;", // label not verified
        "proc stdize data=d pstat out=o; var x; weight w; run;", // Sum of Weights column
    };
    for (run_gaps) |src| {
        try std.testing.expectError(error.ParseError, e.run(&out, src));
        try expect(e.lib.find("o") == null);
    }
    // Constant data (zero scale) stays a gap: f is constant (1) in grp 2.
    try std.testing.expectError(error.ParseError, e.run(&out, "proc stdize data=d out=o; by grp; var f; run;"));
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
        .{ .m = .ustd, .loc = 0, .scale = @sqrt(50.0 / 3.0) }, .{ .m = .std, .loc = 3, .scale = @sqrt(14.0 / 3.0) },
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
