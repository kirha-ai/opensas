//! STAT-PRINCOMP-001 permanent tests: PROC statement options, variable roles,
//! observation selection (missing values, FREQ, WEIGHT), BY boundaries, the
//! symmetric eigen kernel, OUT= scores and loud execution boundaries. All
//! data are invented (D-011). Expected values are hand mathematics (stated
//! next to each check) or documented properties of the cited pages, never
//! opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
const Row = struct { g: f64, id: []const u8, x: f64, y: f64, f: f64, w: f64 };
// columns: 0 g, 1 id, 2 x, 3 y, 4 f, 5 w.        row: reason it can drop out
const sample = [_]Row{
    .{ .g = 1, .id = "a", .x = 1, .y = 2, .f = 1, .w = 1 }, // 0
    .{ .g = 1, .id = "b", .x = 2, .y = 1, .f = 2, .w = 0.5 }, // 1
    .{ .g = 1, .id = "c", .x = 3, .y = 4, .f = 0.5, .w = 0 }, // 2: FREQ < 1, WEIGHT = 0
    .{ .g = 1, .id = "d", .x = 4, .y = 3, .f = 2.7, .w = 1 }, // 3: FREQ integer portion 2
    .{ .g = 1, .id = "e", .x = nan, .y = 5, .f = 1, .w = 1 }, // 4: missing VAR value
    .{ .g = 2, .id = "f", .x = 5, .y = 5, .f = 1, .w = -1 }, // 5: WEIGHT < 0
    .{ .g = 2, .id = "h", .x = 6, .y = 7, .f = nan, .w = 1 }, // 6: missing FREQ
    .{ .g = 2, .id = "i", .x = 7, .y = 6, .f = 1, .w = nan }, // 7: missing WEIGHT
};
// x = 1..4, y = 2,1,4,3 in each of two BY groups: means 2.5, CSS 5,
// cross product 3, so StD = sqrt(5/3) and r = 0.6.
const four_x = [_]f64{ 1, 2, 3, 4 };
const four_y = [_]f64{ 2, 1, 4, 3 };

fn build(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("id", .char);
    for ([_][]const u8{ "x", "y", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
    for (sample) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .str = r.id }, .{ .num = r.x }, .{ .num = r.y }, .{ .num = r.f }, .{ .num = r.w } });
    try lib.put("sample", ds);
    const four = try a.create(Dataset);
    four.* = Dataset.init(a, "four");
    for ([_][]const u8{ "grp", "x", "y" }) |n| _ = try four.addColumn(n, .num);
    for (0..2) |g| for (four_x, four_y) |x, y| try four.appendRow(&.{ .{ .num = @floatFromInt(g + 1) }, .{ .num = x }, .{ .num = y } });
    // One observation with a missing VAR value at the end of the last group.
    try four.appendRow(&.{ .{ .num = 2 }, .{ .num = nan }, .{ .num = 9 } });
    try lib.put("four", four);
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
    fn parse(self: *Env, source: []const u8) !princomp.Spec {
        return princomp.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return princomp.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-PRINCOMP-001 PROC statement defaults, explicit options and aliases" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Documented defaults (pp.7999-8004): most recent data set (FOUR),
    // correlation matrix, intercept, N unset (= number of variables),
    // PREFIX=Prin, PARPREFIX=R_, SINGULAR=1E-8, VARDEF=DF.
    const d = try e.parse("proc princomp; run;");
    try expect(!d.cov and !d.noint and !d.standard and !d.noprint and !d.plots);
    try expect(d.out == null and d.outstat == null and d.n == null and d.freq == null and d.weight == null);
    try std.testing.expectEqualStrings("Prin", d.prefix);
    try std.testing.expectEqualStrings("R_", d.parprefix);
    try expectEqual(@as(f64, 1e-8), d.singular);
    try expectEqual(princomp.VarDef.df, d.vardef);
    try std.testing.expectEqualStrings("four", d.data_name);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, d.vars);

    const s = try e.parse("proc princomp data=work.sample out=work.o outstat=st cov noint n=2 std prefix=Abc parprefix=Q singular=0.001 vardef=wdf noprint plots(ncomp=3 flip)=(pattern(circles=0.5 1.0) score); var x y; by g; freq f; weight w; id id; run;");
    try expect(s.cov and s.noint and s.standard and s.noprint and s.plots);
    try std.testing.expectEqualStrings("work.o", s.out.?);
    try std.testing.expectEqualStrings("st", s.outstat.?);
    try expectEqual(@as(?usize, 2), s.n);
    try std.testing.expectEqualStrings("Abc", s.prefix);
    try std.testing.expectEqualStrings("Q", s.parprefix);
    try expectEqual(@as(f64, 0.001), s.singular);
    try expectEqual(princomp.VarDef.wdf, s.vardef);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3 }, s.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try std.testing.expectEqualSlices(usize, &.{1}, s.ids);
    try expectEqual(@as(?usize, 4), s.freq);
    try expectEqual(@as(?usize, 5), s.weight);

    // Aliases: COVARIANCE, STANDARD, PPREFIX/RPREFIX, SING, PLOT, WGT;
    // PLOTS=NONE requests no graph; N=0 is a documented value.
    const alias = try e.parse("proc princomp data=sample covariance standard rprefix=Z sing=0.5 plot=none vardef=wgt n=0; run;");
    try expect(alias.cov and alias.standard and !alias.plots);
    try std.testing.expectEqualStrings("Z", alias.parprefix);
    try expectEqual(@as(f64, 0.5), alias.singular);
    try expectEqual(princomp.VarDef.weight, alias.vardef);
    try expectEqual(@as(?usize, 0), alias.n);
    try std.testing.expectEqualStrings("Y", (try e.parse("proc princomp data=sample pprefix=Y; run;")).parprefix);
    try expectEqual(princomp.VarDef.n, (try e.parse("proc princomp data=sample vardef=n; run;")).vardef);
    try expect(!(try e.parse("proc princomp data=sample plots=(none); run;")).plots);
    try expect((try e.parse("proc princomp data=sample plots; run;")).plots);
}

test "STAT-PRINCOMP-001 variable roles: default VAR list and the last BY statement" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.8006: without VAR, all numeric variables not in other statements.
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 3, 4, 5 }, (try e.parse("proc princomp data=sample; id id; run;")).vars);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3 }, (try e.parse("proc princomp data=sample; by g; freq f; weight w; run;")).vars);
    try std.testing.expectEqualSlices(usize, &.{ 3, 5 }, (try e.parse("proc princomp data=sample; partial x; by g; freq f; run;")).vars);
    try std.testing.expectEqualSlices(usize, &.{2}, (try e.parse("proc princomp data=sample; partial x; run;")).partial);
    // p.8005: only the last BY statement is used.
    const last = try e.parse("proc princomp data=sample; by x; by descending g notsorted; var x y; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, last.by_cols);
    try expect(last.by_desc[0] and last.notsorted);
    // A VAR variable may repeat; it is analyzed once.
    try std.testing.expectEqualSlices(usize, &.{ 3, 2 }, (try e.parse("proc princomp data=sample; var y x y; run;")).vars);
}

test "STAT-PRINCOMP-001 observation selection: missing values, FREQ and WEIGHT rules" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const rows = e.lib.find("sample").?.rows.items;
    // p.8007: an observation with a missing VAR value is omitted (row 4).
    const plain = try princomp.select(a, try e.parse("proc princomp data=sample; var x y; run;"), rows);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 5, 6, 7 }, plain.rows);
    try expectEqual(@as(f64, 7), plain.n);
    try expectEqual(@as(f64, 7), plain.sum_weight);
    // pp.8005-8006: FREQ missing or < 1 omits (rows 2, 6); 2.7 counts as 2.
    // n = 1 + 2 + 2 + 1 + 1 = 7.
    const freq = try princomp.select(a, try e.parse("proc princomp data=sample; var x y; freq f; run;"), rows);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 5, 7 }, freq.rows);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 2, 1, 1 }, freq.freq);
    try expectEqual(@as(f64, 7), freq.n);
    // p.8007: WEIGHT must be nonmissing and > 0 (rows 2, 5, 7 omitted).
    // Sum of weights = 1 + 0.5 + 1 + 1 = 3.5.
    const weight = try princomp.select(a, try e.parse("proc princomp data=sample; var x y; weight w; run;"), rows);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 6 }, weight.rows);
    try expectEqual(@as(f64, 4), weight.n);
    try expectEqual(@as(f64, 3.5), weight.sum_weight);
    // Both: rows 0, 1, 3; n = 1 + 2 + 2 = 5; sum f*w = 1 + 1 + 2 = 4.
    const both = try princomp.select(a, try e.parse("proc princomp data=sample; var x y; freq f; weight w; run;"), rows);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3 }, both.rows);
    try expectEqual(@as(f64, 5), both.n);
    try expectEqual(@as(f64, 4), both.sum_weight);
    // p.8004 divisors: DF n-1, N n, WEIGHT sum w, WDF sum w - 1.
    try expectEqual(@as(f64, 4), princomp.divisor(.df, both));
    try expectEqual(@as(f64, 5), princomp.divisor(.n, both));
    try expectEqual(@as(f64, 4), princomp.divisor(.weight, both));
    try expectEqual(@as(f64, 3), princomp.divisor(.wdf, both));
    // An empty selection: every observation of a group can drop out.
    const none = try princomp.select(a, try e.parse("proc princomp data=sample; var x y; freq f; run;"), rows[2..3]);
    try expectEqual(@as(usize, 0), none.rows.len);
    try expectEqual(@as(f64, 0), none.n);
}

test "STAT-PRINCOMP-001 symmetric eigen kernel against hand mathematics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = @sqrt(0.5);
    // [[2,1],[1,2]]: eigenvalues 3 and 1; first eigenvector (1,1)/sqrt(2).
    const two = try princomp.eigenSym(a, &.{ 2, 1, 1, 2 }, 2);
    try approx(@as(f64, 3), two.values[0], 1e-12);
    try approx(@as(f64, 1), two.values[1], 1e-12);
    try approx(h, two.vectors[0], 1e-12);
    try approx(h, two.vectors[2], 1e-12);
    try approx(h, @abs(two.vectors[1]), 1e-12);
    try approx(@as(f64, 0), two.vectors[1] + two.vectors[3], 1e-12);
    // Equicorrelation 0.5 in three variables: 1 + 2r = 2, then 1 - r twice;
    // first eigenvector (1,1,1)/sqrt(3).
    const three = try princomp.eigenSym(a, &.{ 1, 0.5, 0.5, 0.5, 1, 0.5, 0.5, 0.5, 1 }, 3);
    try approx(@as(f64, 2), three.values[0], 1e-12);
    try approx(@as(f64, 0.5), three.values[1], 1e-12);
    try approx(@as(f64, 0.5), three.values[2], 1e-12);
    for (0..3) |j| try approx(@sqrt(1.0 / 3.0), three.vectors[j * 3], 1e-12);
    // Diagonal input: eigenvalues sort descending and the sign rule makes a
    // lone negative element positive. [[1,0],[0,4]] -> 4 (0,1), 1 (1,0).
    const diagonal = try princomp.eigenSym(a, &.{ 1, 0, 0, 4 }, 2);
    try std.testing.expectEqualSlices(f64, &.{ 4, 1 }, diagonal.values);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 1, 0 }, diagonal.vectors);
    // Orientation: [[1,-0.8],[-0.8,1]] has eigenvalue 1.8 for (1,-1)/sqrt(2)
    // (element sum 0) and 0.2 for (1,1)/sqrt(2), which must come out positive.
    const negative = try princomp.eigenSym(a, &.{ 1, -0.8, -0.8, 1 }, 2);
    try approx(@as(f64, 1.8), negative.values[0], 1e-12);
    try approx(h, negative.vectors[1], 1e-12);
    try approx(h, negative.vectors[3], 1e-12);
}

test "STAT-PRINCOMP-001 default listing rows per BY group from hand-computed moments" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try e.run(&output, "proc princomp data=four; by grp; var x y; run;");
    try expect(!e.diags.hasErrors() and !diag.gapHit());
    // Means 2.5, StD sqrt(5/3) = 1.290994449, r = 3/5; eigenvalues 1 +- r,
    // difference 1.2, proportions 0.8 and 0.2; Prin1 = (1,1)/sqrt(2).
    // The missing observation of group 2 is omitted: 4 observations in both.
    const rows = [_][]const u8{
        "Observations           4\nVariables              2\n",
        "Mean       2.500000000       2.500000000\nStD        1.290994449       1.290994449\n",
        "x      1.0000      0.6000\ny      0.6000      1.0000\n",
        "   1    1.60000000    1.20000000        0.8000        0.8000\n   2    0.40000000                      0.2000        1.0000\n",
        "x      0.707107",
        "y      0.707107",
        "            Eigenvalues of the Correlation Matrix\n \n        Eigenvalue    Difference    Proportion    Cumulative\n",
        "The PRINCOMP Procedure\n",
    };
    for (rows) |row| {
        expectEqual(@as(usize, 2), std.mem.count(u8, output.items, row)) catch |err| {
            std.debug.print("row not printed twice: {s}\n{s}\n", .{ row, output.items });
            return err;
        };
    }
    try expect(std.mem.indexOf(u8, output.items, "grp=1") != null and std.mem.indexOf(u8, output.items, "grp=2") != null);
    try expectEqual(@as(usize, 2), std.mem.count(u8, output.items, "-.707107"));
}

test "STAT-PRINCOMP-001 OUT= scores: mean 0, variance = eigenvalue, STD unit variance, missing for omitted rows" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try e.run(&output, "proc princomp data=four out=scores noprint; var x y; where grp = 2; run;");
    try e.run(&output, "proc princomp data=four out=unit prefix=pc std noprint; var x y; where grp = 2; run;");
    try expect(!e.diags.hasErrors());
    try expectEqual(@as(usize, 0), output.items.len); // NOPRINT
    const scores = e.lib.find("scores").?;
    // p.8007: all original variables plus Prin1..Prinp; every input row kept.
    try expectEqual(@as(usize, 5), scores.columns.items.len);
    try std.testing.expectEqualStrings("Prin1", scores.columns.items[3].name);
    try std.testing.expectEqualStrings("Prin2", scores.columns.items[4].name);
    try expectEqual(@as(usize, 5), scores.rows.items.len);
    // Row 1: z = (-1.5, -0.5) / sqrt(5/3); Prin1 = (zx + zy) / sqrt(2).
    try approx(-2.0 / @sqrt(5.0 / 3.0) / @sqrt(2.0), scores.rows.items[0][3].num, 1e-12);
    // Mean 0 and variance (divisor n-1 = 3) equal to the eigenvalues 1.6, 0.4.
    for ([_]usize{ 3, 4 }, [_]f64{ 1.6, 0.4 }) |ci, eigenvalue| {
        var sum: f64 = 0;
        var ss: f64 = 0;
        for (scores.rows.items[0..4]) |row| {
            sum += row[ci].num;
            ss += row[ci].num * row[ci].num;
        }
        try approx(@as(f64, 0), sum, 1e-12);
        try approx(eigenvalue, ss / 3, 1e-12);
    }
    // The observation with a missing VAR value keeps its data, scores missing.
    try expectEqual(@as(f64, 9), scores.rows.items[4][2].num);
    try expect(std.math.isNan(scores.rows.items[4][3].num) and std.math.isNan(scores.rows.items[4][4].num));
    // STD: unit variance; PREFIX= names the components.
    const unit = e.lib.find("unit").?;
    try std.testing.expectEqualStrings("pc1", unit.columns.items[3].name);
    for ([_]usize{ 3, 4 }) |ci| {
        var ss: f64 = 0;
        for (unit.rows.items[0..4]) |row| ss += row[ci].num * row[ci].num;
        try approx(@as(f64, 1), ss / 3, 1e-12);
    }
}

test "STAT-PRINCOMP-001 invalid input is a user error and unimplemented valid syntax is a loud gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors (rc 1): documented value ranges, unknown names, roles.
        .{ .source = "proc princomp data=nosuch; run;", .rc = 1 },
        .{ .source = "proc princomp data=four n=-1; run;", .rc = 1 },
        .{ .source = "proc princomp data=four n=1.5; run;", .rc = 1 },
        .{ .source = "proc princomp data=four singular=2; run;", .rc = 1 },
        .{ .source = "proc princomp data=four singular=0; run;", .rc = 1 },
        .{ .source = "proc princomp data=four vardef=wrong; run;", .rc = 1 },
        .{ .source = "proc princomp data=four nosuchoption; run;", .rc = 1 },
        .{ .source = "proc princomp data=four prefix=3; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; var id; run;", .rc = 1 }, // character VAR
        .{ .source = "proc princomp data=sample; var nosuch; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; freq id; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; freq f w; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; weight; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; var; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; model x = y; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; by nosuch; run;", .rc = 1 },
        .{ .source = "proc princomp data=sample; var x y; by descending g; run;", .rc = 1 }, // not sorted descending
        // Valid SAS owned by later tickets or not verified (D-009 gap, rc 2).
        .{ .source = "proc princomp data=four plots=score(ellipse ncomp=3); run;", .rc = 2 },
        .{ .source = "proc princomp data=four plots; run;", .rc = 2 },
        .{ .source = "proc princomp data=four; partial grp; run;", .rc = 2 },
        .{ .source = "proc princomp data=four outstat=st; run;", .rc = 2 },
        .{ .source = "proc princomp data=four cov; run;", .rc = 2 },
        .{ .source = "proc princomp data=four noint; run;", .rc = 2 },
        .{ .source = "proc princomp data=four vardef=n; run;", .rc = 2 },
        .{ .source = "proc princomp data=four n=1; var x y; run;", .rc = 2 },
        .{ .source = "proc princomp data=four n=0; var x y; run;", .rc = 2 },
        .{ .source = "proc princomp data=sample; var x y; freq f; run;", .rc = 2 },
        .{ .source = "proc princomp data=sample; var x y; weight w; run;", .rc = 2 },
        .{ .source = "proc princomp data=four std std; run;", .rc = 2 },
        .{ .source = "proc princomp data=four cov covariance; run;", .rc = 2 },
        .{ .source = "proc princomp data=four; var x; var y; run;", .rc = 2 },
        .{ .source = "proc princomp data=four; var x y; format x 8.2; run;", .rc = 2 },
        .{ .source = "proc princomp data=four out=o prefix=x; var x y; run;", .rc = 2 }, // x1? no: see below
        // Degenerate analyses whose SAS listing is not verified.
        .{ .source = "proc princomp data=four; var x grp; by grp; run;", .rc = 2 }, // zero variance in a group
        .{ .source = "proc princomp data=sample; var x y; where g = 1 and x > 3; run;", .rc = 2 }, // one usable observation
    };
    for (cases) |case| {
        // The OUT= name-collision case needs a variable named like a component.
        if (std.mem.indexOf(u8, case.source, "prefix=x") != null) {
            const ds = lib.find("four").?;
            if (ds.indexOf("x1") == null) {
                const widened = try a.create(Dataset);
                widened.* = Dataset.init(a, "clash");
                for ([_][]const u8{ "x", "y", "x1" }) |n| _ = try widened.addColumn(n, .num);
                for (four_x, four_y) |x, y| try widened.appendRow(&.{ .{ .num = x }, .{ .num = y }, .{ .num = x * y } });
                try lib.put("clash", widened);
            }
        }
        const source = if (std.mem.indexOf(u8, case.source, "prefix=x") != null) "proc princomp data=clash out=o prefix=x; var x y; run;" else case.source;
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = princomp.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{source});
            return err;
        };
        try expect(d.hasErrors());
        try expectEqual(@as(usize, 0), output.items.len); // never a partial or fake table
        try expect(lib.find("o") == null and lib.find("st") == null); // nor a data set
    }
}
