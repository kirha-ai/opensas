//! STAT-KDE-001 permanent tests: PROC KDE statement parsing, UNIVAR / BIVAR /
//! BY / FREQ / WEIGHT roles, observation rules, closed-form bandwidths,
//! default grid limits, the Inputs/Controls listing and loud gaps. All data
//! are invented (D-011). Expected numbers come from SAS 9.4 listings of the
//! same invented data (recorded next to each check) or hand mathematics.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const kde = @import("kde.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// s: x y f w (8 rows, SAS-checked); t: x = 0..19,100 with y and group g.
fn build(a: A, lib: *Library) !void {
    const s = try a.create(Dataset);
    s.* = Dataset.init(a, "s");
    for ([_][]const u8{ "x", "y", "f", "w" }) |n| _ = try s.addColumn(n, .num);
    _ = try s.addColumn("id", .char);
    const rows = [_][4]f64{
        .{ 1, 2, 1, 1 },   .{ 2, 3, 2, 0.5 }, .{ 4, 1, 1, 2 }, .{ 7, 5, 3, 1 },
        .{ 3, nan, 1, 1 }, .{ nan, 4, 1, 1 }, .{ 5, 6, 0, 1 }, .{ 6, 2, 1, -1 },
    };
    for (rows) |r| try s.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .str = "a" } });
    try lib.put("s", s);
    const t = try a.create(Dataset);
    t.* = Dataset.init(a, "t");
    for ([_][]const u8{ "x", "y", "g" }) |n| _ = try t.addColumn(n, .num);
    const xs = [_]f64{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 100 };
    const ys = [_]f64{ 0, 1, 3, 2, 4, 5, 7, 6, 8, 9, 10, 12, 11, 13, 14, 15, 17, 16, 18, 19, 100 };
    for (xs, ys, 0..) |x, y, k| try t.appendRow(&.{ .{ .num = x }, .{ .num = y }, .{ .num = if (k < 10) 1 else 2 } });
    try lib.put("t", t);
    const c = try a.create(Dataset);
    c.* = Dataset.init(a, "c");
    _ = try c.addColumn("x", .num);
    try c.appendRow(&.{.{ .num = 1 }});
    try c.appendRow(&.{.{ .num = 1 }});
    try lib.put("c", c);
    const e = try a.create(Dataset);
    e.* = Dataset.init(a, "e");
    _ = try e.addColumn("x", .num);
    try lib.put("e", e);
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
    fn parse(self: *Env, source: []const u8) !kde.Spec {
        return kde.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return kde.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn lastError(self: *Env) []const u8 {
        var k = self.diags.list.items.len;
        while (k > 0) {
            k -= 1;
            if (self.diags.list.items[k].severity == .err) return self.diags.list.items[k].message;
        }
        return "";
    }
};

fn fresh() Env {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "STAT-KDE-001 statement parsing: defaults, v-options, pairs, roles" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const d = try e.parse("proc kde data=s; bivar x y; run;");
    try expectEqual(@as(usize, 1), d.stmts.len);
    try expect(d.stmts[0].bivar and d.stmts[0].pairs.len == 1 and d.freq == null and d.weight == null);
    // p.5382: bivar x y f -> (x,y) (x,f) (y,f); explicit pairs keep their order.
    const p3 = try e.parse("proc kde data=s; bivar x y f; run;");
    try expectEqual(@as(usize, 3), p3.stmts[0].pairs.len);
    try expectEqual([2]usize{ 1, 2 }, p3.stmts[0].pairs[2]);
    const pp = try e.parse("proc kde data=s; bivar (x y) (y x) / bw=1; run;");
    try expectEqual([2]usize{ 1, 0 }, pp.stmts[0].pairs[1]);
    // p.5393 example shape: v-options override the global options.
    const u = try e.parse("proc kde data=s; univar x (bwm=2) y (bwm=0.5 ngrid=100) w / ngrid=200 method=snr; freq f; weight w; by id; run;");
    const st = u.stmts[0];
    try expectEqual(kde.Method.snr, st.method.?);
    try expect(st.opts(0).bwm.? == 2 and st.opts(0).ngrid.? == 200);
    try expect(st.opts(1).bwm.? == 0.5 and st.opts(1).ngrid.? == 100);
    try expect(st.opts(3).bwm == null);
    try expect(u.freq.? == 2 and u.weight.? == 3 and u.by_cols.len == 1 and u.by_cols[0] == 4);
    // UNIVAR x x analyses x once; NG= aliases NGRID=.
    const dup = try e.parse("proc kde data=s; univar x x / ng=5; run;");
    try expect(dup.stmts[0].vars.len == 1 and dup.stmts[0].global.ngrid.? == 5);
    // Two FREQ statements: SAS uses the first; only the last BY is used.
    const f2 = try e.parse("proc kde data=s; univar x / bw=1; freq f; freq w; by x; by y; run;");
    try expect(f2.freq.? == 2 and f2.by_cols[0] == 1);
}

test "STAT-KDE-001 invalid declarations are user errors with the SAS messages" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const cases = [_][2][]const u8{
        .{ "proc kde data=s; run;", "You must specify at least one UNIVAR or BIVAR statement." },
        .{ "proc kde data=s; bivar x y z; run;", "Variable Z not found." },
        .{ "proc kde data=s; univar x / ngrid=1; run;", "The parameter value 1 is less than the minimum allowed value of 2." },
        .{ "proc kde data=s; univar x / bwm=-1; run;", "The parameter value -1 is less than the minimum allowed value of 0." },
        .{ "proc kde data=s; univar x / bwm=0; run;", "Bandwidth multipliers must be greater than 0." },
        .{ "proc kde data=s; univar x / bw=0; run;", "User-specified bandwidth must be greater than 0." },
        .{ "proc kde data=s; univar id / bw=1; run;", "Variable id in list does not match type prescribed for this list." },
        .{ "proc kde data=s; bivar x; run;", "PROC KDE: the BIVAR statement requires at least two variables" },
        .{ "proc kde data=s; bivar x y / method=snr; run;", "PROC KDE: method is not a valid BIVAR option" },
        .{ "proc kde data=s; univar x / method=bogus; run;", "PROC KDE: METHOD=bogus is not a valid bandwidth method" },
        .{ "proc kde data=s; freq f w; univar x; run;", "PROC KDE: the FREQ statement takes exactly one variable" },
        .{ "proc kde data=s outc=o; univar x; run;", "PROC KDE: outc is not a valid PROC KDE option (only DATA= is documented)" },
        .{ "proc kde data=nosuch; univar x; run;", "PROC KDE: input data set not found" },
    };
    for (cases) |c| {
        try std.testing.expectError(error.ParseError, e.parse(c[0]));
        try std.testing.expectEqualStrings(c[1], e.lastError());
    }
    var out: std.ArrayList(u8) = .empty;
    const run_cases = [_][2][]const u8{
        // SAS: GRIDL=50 GRIDU=40 -> invalid; constant data; one or no rows.
        .{ "proc kde data=t; univar x / gridl=50 gridu=40 bw=1; run;", "Invalid grid limits." },
        .{ "proc kde data=c; univar x / bw=1; run;", "x has too small of a range or the grid size is too large." },
        .{ "proc kde data=e; univar x / bw=1; run;", "Insufficient data." },
        .{ "proc kde data=s; where x = 7; univar x / bw=1; run;", "Insufficient data." },
    };
    for (run_cases) |c| {
        try std.testing.expectError(error.ParseError, e.run(&out, c[0]));
        try std.testing.expectEqualStrings(c[1], e.lastError());
    }
    // SAS 9.4 prints the Inputs table of the constant-data estimate only.
    try expect(std.mem.indexOf(u8, out.items, "WORK.C") != null and std.mem.indexOf(u8, out.items, "Controls") == null);
}

test "STAT-KDE-001 valid but unimplemented features are loud gaps" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const parse_gaps = [_][]const u8{
        "proc kde data=s; univar x / out=o; run;",
        "proc kde data=s; bivar x y / cdf; run;",
        "proc kde data=s; bivar x y / levels; run;",
        "proc kde data=s; univar x / percentiles; run;",
        "proc kde data=s; univar x / unistats; run;",
        "proc kde data=s; bivar x y / bivstats; run;",
        "proc kde data=s; univar x / method=sjpi; run;",
        "proc kde data=s; univar x / method=srot; run;",
        "proc kde data=s; univar x / method=snrq; run;",
        "proc kde data=s; univar x / sjpitol=0.01; run;",
        "proc kde data=s; univar x / bw=1; score data=s out=o; run;",
        "proc kde data=s; var x; run;",
        "proc kde data=s; univar x / bw=1 bw=2; run;",
        "proc kde data=s; univar x / bw=1; weight w; weight f; run;",
        "proc kde data=s; univar x / bw=1; bivar x y; run;",
    };
    for (parse_gaps) |src| try std.testing.expectError(error.ParseError, e.parse(src));
    var out: std.ArrayList(u8) = .empty;
    const run_gaps = [_][]const u8{
        "proc kde data=s; univar x; run;", // default METHOD=SJPI
        "proc kde data=s; univar x (bw=1) y; run;",
        "proc kde data=s; bivar x (bw=1) y; run;",
    };
    for (run_gaps) |src| try std.testing.expectError(error.ParseError, e.run(&out, src));
    try expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-KDE-001 bandwidths, FREQ/WEIGHT rules and default grid limits match SAS" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const s = try e.parse("proc kde data=s; bivar x y; run;");
    const rows = try kde.usableRows(a, s, s.input.ds.rows.items, &.{ 0, 1 });
    try expectEqual(@as(usize, 6), rows.len);
    // Hand: x = 1,2,4,7,5,6 -> sd 2.3166 (df 5); h = sd * 6^(-1/6) (SAS 1.72).
    const mx = kde.moments(s, rows, 0);
    try approx(2.31661, mx.sigma, 1e-5);
    const gx = try kde.grid(mx, .{}, true, .snr, false);
    try approx(1.72, gx.h, 0.005);
    // Capped at R/2 (SAS: -2 and 10; y: -1.5 and 8.5).
    try approx(-2, gx.lower, 1e-12);
    try approx(10, gx.upper, 1e-12);
    // FREQ: 5 rows used, n = 8, variance 46/7 (SAS 6.57, bandwidth 1.81).
    const f = try e.parse("proc kde data=s; freq f; bivar x y; run;");
    const fr = try kde.usableRows(a, f, f.input.ds.rows.items, &.{ 0, 1 });
    try expectEqual(@as(usize, 5), fr.len);
    const fm = kde.moments(f, fr, 0);
    try approx(8, fm.n, 0);
    try approx(46.0 / 7.0, fm.sigma * fm.sigma, 1e-12);
    // WEIGHT: weighted variance 21/5.5 (SAS 3.82, bandwidth 1.49).
    const w = try e.parse("proc kde data=s; weight w; bivar x y; run;");
    const wr = try kde.usableRows(a, w, w.input.ds.rows.items, &.{ 0, 1 });
    const wm = kde.moments(w, wr, 0);
    try approx(4, wm.mean, 1e-12);
    try approx(21.0 / 5.5, wm.sigma * wm.sigma, 1e-12);
    try approx(1.49, (try kde.grid(wm, .{}, true, .snr, false)).h, 0.005);
    // t (n=21, sd 20.573): SAS univariate SNR grid -35.94/135.94 (bw 11.85),
    // bivariate -37.5/137.5, OS -39.06, BW=1 -3.125/103.125, BW=1 BWM=2 -6.25,
    // BW=1 GRIDL=-5 -> upper 103.28 (R = 105), SNR GRIDU=50 -> lower -25.
    const t = try e.parse("proc kde data=t; univar x / bw=1; run;");
    const tm = kde.moments(t, t.input.ds.rows.items, 0);
    const snr = try kde.grid(tm, .{}, false, .snr, false);
    try approx(11.85, snr.h, 0.005);
    try approx(-35.9375, snr.lower, 1e-9);
    try approx(-37.5, (try kde.grid(tm, .{}, true, .snr, false)).lower, 1e-9);
    try approx(-39.0625, (try kde.grid(tm, .{}, false, .os, false)).lower, 1e-9);
    try approx(103.125, (try kde.grid(tm, .{ .bw = 1 }, false, .snr, false)).upper, 1e-9);
    try approx(-6.25, (try kde.grid(tm, .{ .bw = 1, .bwm = 2 }, false, .snr, false)).lower, 1e-9);
    try approx(100 + 4 * 105.0 / 128.0, (try kde.grid(tm, .{ .bw = 1, .gridl = -5 }, false, .snr, false)).upper, 1e-9);
    try approx(-25, (try kde.grid(tm, .{ .gridu = 50 }, false, .snr, false)).lower, 1e-9);
    // TRUNCATE: observed extremes; GRIDL= takes precedence (SAS 0 and 7).
    const tr = try kde.grid(mx, .{ .gridl = 0 }, true, .snr, true);
    try expect(tr.lower == 0 and tr.upper == 7);
}

test "STAT-KDE-001 listing: Inputs/Controls layout, BY groups, NOPRINT" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc kde data=s; weight w; freq f; univar x / method=snr; run;");
    // SAS 9.4 listing of the same step (trailing blanks as SAS writes them).
    const expected =
        "\nThe KDE Procedure\n\n                      Inputs\n\n" ++
        "Data Set                          WORK.S           \n" ++
        "Number of Observations Used       5                \n" ++
        "Variable                          x                \n" ++
        "Weight                            w                \n" ++
        "Freq                              f                \n" ++
        "Bandwidth Method                  Simple Normal    \n" ++
        "                                  Reference        \n" ++
        "\n\n             Controls\n \n                                  x\n\n" ++
        "Grid Points                     401\n" ++
        "Lower Grid Limit                 -2\n" ++
        "Upper Grid Limit                 10\n" ++
        "Bandwidth Multiplier              1\n";
    try std.testing.expectEqualStrings(expected, out.items);
    out.clearRetainingCapacity();
    try e.run(&out, "proc kde data=t; by g; bivar x y; univar x / bw=1; run;");
    // SAS: g=1 then g=2 for BIVAR, then both groups for UNIVAR.
    const text = out.items;
    const first = std.mem.indexOf(u8, text, "Number of Observations Used       10").?;
    const second = std.mem.indexOf(u8, text, "Number of Observations Used       11").?;
    try expect(first < second);
    try expect(std.mem.indexOf(u8, text, "Lower Grid Limit               -4.5      -4.5") != null);
    try expect(std.mem.indexOf(u8, text, "Lower Grid Limit                -35       -35") != null);
    try expect(std.mem.indexOf(u8, text, "Lower Grid Limit             -3.023") != null);
    try expect(std.mem.indexOf(u8, text, "Lower Grid Limit             6.4844") != null);
    try expectEqual(@as(usize, 4), std.mem.count(u8, text, "The KDE Procedure"));
    try expect(std.mem.startsWith(u8, text, "\ng=1\n\nThe KDE Procedure"));
    out.clearRetainingCapacity();
    try e.run(&out, "proc kde data=t; bivar x y / bw=1 noprint; run;");
    try expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-KDE-001 BY order, NOTSORTED, FREQ truncation and missing FREQ/WEIGHT rows" {
    var e = fresh();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // p.5386: unsorted BY input is an error unless NOTSORTED; NOTSORTED keeps
    // the groups in data order. s.f = 1,2,1,3,1,1,0,1 is not sorted.
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, e.run(&out, "proc kde data=s; by f; univar x / bw=1; run;"));
    try std.testing.expect(std.mem.indexOf(u8, e.lastError(), "not sorted") != null);
    // DESCENDING g on t (1..1 then 2..2) is out of order as well.
    try std.testing.expectError(error.ParseError, e.run(&out, "proc kde data=t; by descending g; univar x / bw=1; run;"));
    try expectEqual(@as(usize, 0), out.items.len);
    try e.run(&out, "proc kde data=t; by g notsorted; univar x / bw=1; run;");
    try expect(std.mem.indexOf(u8, out.items, "\ng=1\n").? < std.mem.indexOf(u8, out.items, "\ng=2\n").?);
    // p.5386: a FREQ value that is not an integer is truncated; missing or
    // < 1 drops the row. p.5393: a missing or nonpositive WEIGHT drops it.
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    for ([_][]const u8{ "x", "f", "w" }) |n| _ = try d.addColumn(n, .num);
    const rows = [_][3]f64{ .{ 1, 2.9, 1 }, .{ 3, 1, nan }, .{ 4, nan, 1 }, .{ 5, 0.5, 1 }, .{ 7, 1, 0 }, .{ 2, 1, 3 } };
    for (rows) |r| try d.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    try e.lib.put("d", d);
    const f = try e.parse("proc kde data=d; freq f; univar x / bw=1; run;");
    const fr = try kde.usableRows(a, f, d.rows.items, &.{0});
    // Rows x=1 (f=2), 3, 7, 2 remain; n = 2+1+1+1 = 5, mean 14/5.
    try expectEqual(@as(usize, 4), fr.len);
    const fm = kde.moments(f, fr, 0);
    try approx(5, fm.n, 0);
    try approx(14.0 / 5.0, fm.mean, 1e-12);
    const fw = try e.parse("proc kde data=d; freq f; weight w; univar x / bw=1; run;");
    const wr = try kde.usableRows(a, fw, d.rows.items, &.{0});
    // Rows x=1 (f=2, w=1) and x=2 (w=3): weighted mean (2+6)/5 = 1.6.
    try expectEqual(@as(usize, 2), wr.len);
    try approx(1.6, kde.moments(fw, wr, 0).mean, 1e-12);
}
