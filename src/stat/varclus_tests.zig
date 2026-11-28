//! STAT-VARCLUS-001 permanent tests: PROC statement options, variable roles,
//! observation selection, the clustering kernel on hand-computable
//! correlation matrices, OUTSTAT= rows and loud execution boundaries. All
//! data are invented (D-011). Expected values are hand mathematics stated
//! next to each check, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const varclus = @import("varclus.zig");
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// columns: 0 g, 1 id, 2 x, 3 y, 4 z, 5 f, 6 w
fn build(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("id", .char);
    for ([_][]const u8{ "x", "y", "z", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
    const rows = [_][7]f64{
        .{ 1, 0, 1, 2, 5, 1, 1 },
        .{ 1, 0, 2, 1, 3, 2, 0.5 },
        .{ 1, 0, 3, 4, 1, 0.5, 1 }, // FREQ < 1: dropped
        .{ 1, 0, 4, 3, 2, 2.7, 1 }, // FREQ integer part 2
        .{ 1, 0, nan, 5, 1, 1, 1 }, // missing VAR value: dropped
        .{ 1, 0, 5, 6, 0, 1, 0 }, // WEIGHT 0: dropped when WEIGHT is used
        .{ 2, 0, 1, 1, 1, 1, 1 },
        .{ 2, 0, 2, 3, 2, 1, 1 },
        .{ 2, 0, 3, 2, 4, 1, 1 },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .str = "a" }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .num = r[6] } });
    try lib.put("sample", ds);
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
    fn parse(self: *Env, source: []const u8) !varclus.Spec {
        return varclus.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return varclus.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-VARCLUS-001 PROC statement defaults, explicit options and aliases" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Defaults (pp.10689-10695): last data set, MAXITER=10, VARDEF=DF,
    // MAXCLUSTERS/MAXEIGEN/PROPORTION/MAXSEARCH unset (resolved at run time).
    const d = try e.parse("proc varclus; run;");
    try expect(d.maxc == null and d.maxeigen == null and d.proportion == null and d.maxsearch == null);
    try expectEqual(@as(usize, 10), d.maxiter);
    try expectEqual(princomp.VarDef.df, d.vardef);
    try expect(!d.noprint and !d.plots and d.outstat == null and d.unsupported == null);
    // p.10696: without VAR, every numeric variable not in another statement.
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 3, 4, 5, 6 }, d.vars);

    const s = try e.parse("proc varclus data=work.sample outstat=st maxc=2 maxeigen=0.5 percent=75 maxiter=3 maxsearch=4 vardef=wgt noprint plots=none; var x--z; by g; freq f; weight w; run;");
    try expectEqual(@as(?usize, 2), s.maxc);
    try expectEqual(@as(?f64, 0.5), s.maxeigen);
    try expectEqual(@as(?f64, 0.75), s.proportion); // p.10694: >1 is a percentage
    try expectEqual(@as(usize, 3), s.maxiter);
    try expectEqual(@as(?usize, 4), s.maxsearch);
    try expectEqual(princomp.VarDef.weight, s.vardef);
    try expect(s.noprint and !s.plots);
    try std.testing.expectEqualStrings("st", s.outstat.?);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4 }, s.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(?usize, 5), s.freq);
    try expectEqual(@as(?usize, 6), s.weight);
    try expectEqual(@as(?f64, 0.4), (try e.parse("proc varclus data=sample proportion=0.4; run;")).proportion);
    try expectEqual(@as(?usize, 3), (try e.parse("proc varclus data=sample maxclusters=3; run;")).maxc);
    // Defaults without VAR exclude BY/FREQ/WEIGHT variables.
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4 }, (try e.parse("proc varclus data=sample; by g; freq f; weight w; run;")).vars);
    // p.10695: only the last BY statement is used.
    const last = try e.parse("proc varclus data=sample; by x; by descending g notsorted; var x y; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, last.by_cols);
    try expect(last.by_desc[0] and last.notsorted);
    // Options owned by later tickets parse and are recorded for a loud gap.
    try expect((try e.parse("proc varclus data=sample centroid; run;")).unsupported != null);
    try expect((try e.parse("proc varclus data=sample initial=random random=5; run;")).unsupported != null);
    try expect((try e.parse("proc varclus data=sample minc=1; run;")).unsupported == null);
}

test "STAT-VARCLUS-001 two variables: one cluster, then two singletons (hand mathematics)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // r = 0.6: eigenvalues 1.6 and 0.4, first eigenvector (1,1)/sqrt2,
    // standardized score (1/sqrt2)/sqrt(1.6) = 0.559017, structure sqrt(0.8).
    const r = [_]f64{ 1, 0.6, 0.6, 1 };
    const h = try varclus.cluster(a, &r, 2, .{ .maxc = 2, .maxeigen = 0, .proportion = null, .maxiter = 10, .maxsearch = 500 });
    try expectEqual(@as(usize, 2), h.levels.len);
    const one = h.levels[0];
    try approx(1.6, one.comps[0].explained, 1e-12);
    try approx(0.4, one.comps[0].second, 1e-12);
    try approx(0.5590169943749474, one.comps[0].score[0], 1e-12);
    try approx(@sqrt(0.8), one.structure[0], 1e-12);
    try approx(0.4, h.split_second[0], 1e-12);
    const two = h.levels[1];
    try expect(two.group[0] != two.group[1]);
    try approx(1, two.comps[0].explained, 1e-12);
    try expect(std.math.isNan(two.comps[1].second)); // one member: no second eigenvalue
    // Each singleton component is its variable; their correlation is r.
    try approx(0.6, two.ccorr[1], 1e-12);
    // Tied split: the first variable moves to the new cluster 2 (as SAS does
    // for PetalLength/PetalWidth with PROPORTION=1, stat_varclus001_criteria).
    try expectEqual(@as(usize, 1), two.group[0]);
    try approx(0.6, two.structure[0], 1e-12);
    try approx(1, two.structure[1], 1e-12);
    // MAXEIGEN=0.5 > 0.4: no cluster qualifies, splitting stops at one cluster.
    const stop = try varclus.cluster(a, &r, 2, .{ .maxc = 2, .maxeigen = 0.5, .proportion = null, .maxiter = 10, .maxsearch = 500 });
    try expectEqual(@as(usize, 1), stop.levels.len);
    try expectEqual(varclus.Stop.criterion, stop.stop);
}

test "STAT-VARCLUS-001 block correlation matrix splits into its blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Variables 0,2 correlate 0.8; 1,3 correlate 0.5; across blocks 0.
    // Whole set: eigenvalues 1.8, 1.5, 0.5, 0.2. Two clusters: {0,2}, {1,3}
    // explaining 1.8 + 1.5 = 3.3 with zero inter-cluster correlation.
    const r = [_]f64{
        1,   0,   0.8, 0,
        0,   1,   0,   0.5,
        0.8, 0,   1,   0,
        0,   0.5, 0,   1,
    };
    const h = try varclus.cluster(a, &r, 4, .{ .maxc = 2, .maxeigen = 0, .proportion = null, .maxiter = 10, .maxsearch = 250 });
    try expectEqual(@as(usize, 2), h.levels.len);
    try approx(1.8, h.levels[0].comps[0].explained, 1e-12);
    try approx(1.5, h.levels[0].comps[0].second, 1e-12);
    const two = h.levels[1];
    try expectEqual(two.group[0], two.group[2]);
    try expectEqual(two.group[1], two.group[3]);
    try expectEqual(@as(usize, 0), two.group[0]); // first variable keeps cluster 1
    try approx(1.8, two.comps[0].explained, 1e-12);
    try approx(1.5, two.comps[1].explained, 1e-12);
    try approx(0, two.ccorr[1], 1e-12);
    try approx(0.2, two.comps[0].second, 1e-12);
}

test "STAT-VARCLUS-001 observation selection and OUTSTAT= rows" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    // Group 1 with FREQ f: rows x=1 (f1), x=2 (f2), x=4 (f2.7 -> 2), x=5 (f1);
    // FREQ 0.5 and a missing x drop out; N = 6. Mean x = (1+4+8+5)/6 = 3.
    try e.run(&out, "proc varclus data=sample outstat=st maxc=2 noprint; var x y; where g = 1; freq f; run;");
    try expect(!e.diags.hasErrors() and !diag.gapHit());
    try expectEqual(@as(usize, 0), out.items.len);
    const st = e.lib.find("st").?;
    // 4 + 2 rows (MEAN, STD, N, CORR x2), then per level: MEMBERS VAREXP
    // PROPOR GROUP RSQUARED + 3k (SCORE, STRUCTUR, CCORR): 8 + 11.
    try expectEqual(@as(usize, 5 + 8 + 11), st.rows.items.len);
    try expectEqual(@as(usize, 5), st.columns.items.len);
    try std.testing.expectEqualStrings("MEAN", st.rows.items[0][1].str);
    try approx(3, st.rows.items[0][3].num, 1e-12);
    try approx(6, st.rows.items[2][3].num, 1e-12);
    try expect(std.math.isNan(st.rows.items[0][0].num));
    try std.testing.expectEqualStrings("CORR", st.rows.items[3][1].str);
    try std.testing.expectEqualStrings("x", st.rows.items[3][2].str);
    try std.testing.expectEqualStrings("MEMBERS", st.rows.items[5][1].str);
    try approx(1, st.rows.items[5][0].num, 0);
    try approx(2, st.rows.items[5][3].num, 0);
    try std.testing.expectEqualStrings("CCORR", st.rows.items[st.rows.items.len - 1][1].str);
    try std.testing.expectEqualStrings("Clus2", st.rows.items[st.rows.items.len - 1][2].str);

    // BY groups: one block of statistics per group with the BY value first.
    try e.run(&out, "proc varclus data=sample outstat=sb maxc=1 noprint; var x y; by g; run;");
    const sb = e.lib.find("sb").?;
    try expectEqual(@as(usize, 2 * (5 + 8)), sb.rows.items.len);
    try approx(1, sb.rows.items[0][0].num, 0);
    try approx(2, sb.rows.items[13][0].num, 0);
    // Group 2 x = 1,2,3: mean 2.
    try approx(2, sb.rows.items[13][4].num, 1e-12);
}

test "STAT-VARCLUS-001 invalid input is a user error and unimplemented valid syntax is a loud gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    {
        // A _TYPE_ variable marks TYPE=CORR-like matrix input (not implemented).
        const typed = try a.create(Dataset);
        typed.* = Dataset.init(a, "typed");
        _ = try typed.addColumn("_TYPE_", .char);
        _ = try typed.addColumn("x", .num);
        _ = try typed.addColumn("y", .num);
        for ([_][2]f64{ .{ 1, 2 }, .{ 2, 1 }, .{ 3, 4 } }) |xy| try typed.appendRow(&.{ .{ .str = "CORR" }, .{ .num = xy[0] }, .{ .num = xy[1] } });
        try lib.put("typed", typed);
    }
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        .{ .source = "proc varclus data=nosuch; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample maxc=0; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample maxc=1.5; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample maxeigen=-1; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample proportion=-0.5; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample maxiter=-2; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample vardef=wrong; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample initial=bogus; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample centroid maxeigen=1; run;", .rc = 1 }, // p.10689
        .{ .source = "proc varclus data=sample nosuchoption; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; var id; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; var nosuch; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; freq id; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; weight f w; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; var; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; model x = y; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; by nosuch; run;", .rc = 1 },
        .{ .source = "proc varclus data=sample; var x y; by descending g; run;", .rc = 1 },
        // Valid SAS owned by later tickets or not verified (D-009 gap, rc 2).
        .{ .source = "proc varclus data=sample centroid; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample cov; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample hierarchy; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample outtree=tr; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample short; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample minc=2; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample plots=dendrogram; var x y; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample; var x y; partial z; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample; var x y; seed x; run;", .rc = 2 },
        .{ .source = "proc varclus data=sample maxeigen=0.5 proportion=0.9; var x y z; run;", .rc = 2 },
        .{ .source = "proc varclus data=typed; var x y; run;", .rc = 2 },
        // SAS 9.4: one observation is an error (verified with a one-row data set).
        .{ .source = "proc varclus data=sample outstat=st maxc=2 noprint; var x y; where g = 1 and x > 4; run;", .rc = 1 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = varclus.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expectEqual(@as(usize, 0), output.items.len);
        try expect(lib.find("st") == null and lib.find("tr") == null);
    }
}

test "STAT-VARCLUS-001 repeated options and statements follow SAS" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // SAS 9.4 (tests/corpus/stat_varclus001_criteria.sas, _statements.sas):
    // the last repeated PROC option wins, VAR statements accumulate, the
    // first FREQ and the first WEIGHT statement are used.
    const s = try e.parse("proc varclus data=sample maxc=2 maxc=3 maxeigen=0.4 maxeigen=0.2; var x; var y z; freq f; freq w; weight w; weight f; run;");
    try expectEqual(@as(?usize, 3), s.maxc);
    try expectEqual(@as(?f64, 0.2), s.maxeigen);
    try expectEqual(@as(usize, 3), s.vars.len);
    const ds = s.input.ds;
    try std.testing.expectEqualStrings("f", ds.columns.items[s.freq.?].name);
    try std.testing.expectEqualStrings("w", ds.columns.items[s.weight.?].name);
}
