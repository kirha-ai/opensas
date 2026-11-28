//! STAT-CORRESP-001 permanent tests: PROC statement options, aliases and
//! defaults, VAR / ID / BY / WEIGHT roles, the VAR-input exclusion rules, the
//! correspondence analysis kernel and the OUTC= data set, and loud execution
//! boundaries. All data are invented (D-011). Expected values are hand
//! mathematics or SAS 9.4 (SAS/STAT 15.4) output for the same invented table,
//! stated next to each check; never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const corresp = @import("corresp.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

/// Two BY groups. g=2 is the 3x3 table [[3,5,7],[4,1,2],[9,2,5]]; g=1 holds
/// the exclusion cases (missing cell, negative cell, missing weight, all-zero
/// row, zero weight) around rows r1, r4 (weight 2) and r7 (weight 0.5).
fn build(a: std.mem.Allocator, lib: *Library) !void {
    const s = try a.create(Dataset);
    s.* = Dataset.init(a, "s");
    for ([_][]const u8{ "g", "a", "b", "c", "w" }) |n| _ = try s.addColumn(n, .num);
    _ = try s.addColumn("nm", .char);
    const rows = [_][5]f64{
        .{ 1, 10, 20, 30, 1 }, .{ 1, 5, nan, 9, 1 }, .{ 1, 8, 4, -1, 1 },  .{ 1, 2, 9, 6, 2 },
        .{ 1, 7, 3, 3, nan },  .{ 1, 0, 0, 0, 1 },   .{ 1, 6, 6, 1, 0.5 }, .{ 1, 1, 2, 3, 0 },
        .{ 2, 3, 5, 7, 1 },    .{ 2, 4, 1, 2, 1 },   .{ 2, 9, 2, 5, 1 },
    };
    const names = [_][]const u8{ "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "x1", "x2", "x3" };
    for (rows, names) |r, n| try s.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = n } });
    try lib.put("s", s);
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
    fn parse(self: *Env, source: []const u8) !corresp.Spec {
        return corresp.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return corresp.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

fn col(ds: *const Dataset, name: []const u8) usize {
    return ds.indexOf(name).?;
}

test "STAT-CORRESP-001 PROC statement defaults, three-letter aliases and roles" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const d = try env.parse("proc corresp data=s; var a b c; run;");
    // pp.2570-2576: DIMENS=2, MININERTIA=0.8, SINGULAR=1E-8 by default.
    try expectEqual(@as(usize, 2), d.dimens);
    try approx(0.8, d.mininertia, 0);
    try approx(1e-8, d.singular, 0);
    try expect(!d.short and !d.chi2p and !d.noprint and d.out == null and d.id == null and d.weight == null);
    try expectEqual(@as(usize, 3), d.vars.len);
    const x = try env.parse("proc corresp dat=s dim=1 sho chi nop min=0.5 sin=1e-10 out=o; var a b c; id nm; weight w; by g; run;");
    try expectEqual(@as(usize, 1), x.dimens);
    try expect(x.short and x.chi2p and x.noprint);
    try approx(0.5, x.mininertia, 0);
    try approx(1e-10, x.singular, 0);
    try expect(std.mem.eql(u8, x.out.?, "o"));
    try expectEqual(@as(usize, 5), x.id.?);
    try expectEqual(@as(usize, 4), x.weight.?);
    try expectEqual(@as(usize, 1), x.by_cols.len);
    const full = try env.parse("proc corresp data=s outc=o dimens=1 short chi2p mininertia=1; var a b c; run;");
    try expect(full.short and full.chi2p and full.dimens == 1);
}

test "STAT-CORRESP-001 kernel: 2x2 inertia equals chi-square over n" {
    // p.2588 Ages table [[2,2],[4,3]]: n=11, chi2 = 11*(2*3-2*4)^2/(4*7*6*5)
    // = 44/840, so the single principal inertia is 4/840 = 1/210.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const res = try corresp.analyze(arena.allocator(), &.{ 2, 2, 4, 3 }, 2, 2);
    try expectEqual(@as(usize, 1), res.inertias.len);
    try approx(1.0 / 210.0, res.inertias[0], 1e-14);
    try approx(11, res.n, 0);
    // Row masses 4/11 and 7/11; the mass-weighted row coordinates centre on 0
    // and their weighted sum of squares is the inertia.
    try approx(4.0 / 11.0, res.r[0], 1e-15);
    try approx(0, res.r[0] * res.f[0] + res.r[1] * res.f[1], 1e-15);
    try approx(1.0 / 210.0, res.r[0] * res.f[0] * res.f[0] + res.r[1] * res.f[1] * res.f[1], 1e-15);
}

test "STAT-CORRESP-001 OUTC= data set matches the SAS listing of the same table" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc corresp data=s(where=(g=2)) out=r3 short; var a b c; run;");
    const r = env.lib.find("r3").?;
    // SAS: 7 observations, 14 variables (_TYPE_ _NAME_ Quality Mass Inertia
    // Dim1-2 Contr1-2 SqCos1-2 Best1-2 Best).
    try expectEqual(@as(usize, 7), r.rows.items.len);
    try expectEqual(@as(usize, 14), r.columns.items.len);
    try expect(std.mem.eql(u8, r.columns.items[1].name, "_NAME_"));
    const rows = r.rows.items;
    try expect(std.mem.eql(u8, rows[0][0].str, "INERTIA"));
    try approx(0.13996067176871, rows[0][col(r, "Inertia")].num, 1e-12);
    try approx(0.1394939550091, rows[0][col(r, "Contr1")].num, 1e-12);
    try approx(0.00046671675961, rows[0][col(r, "Contr2")].num, 1e-12);
    try expect(rows[0][col(r, "Dim1")].isMissing());
    try expect(std.mem.eql(u8, rows[2][1].str, "Row2"));
    try approx(-0.3037517644328, rows[2][col(r, "Dim1")].num, 1e-11);
    try approx(0.04193076697523, rows[2][col(r, "Dim2")].num, 1e-11);
    try approx(0.69394757045202, rows[2][col(r, "Contr2")].num, 1e-11);
    try approx(0.18421052631579, rows[2][col(r, "Mass")].num, 1e-12);
    try approx(0.2730107021874, rows[3][col(r, "Inertia")].num, 1e-11);
    try expect(std.mem.eql(u8, rows[5][0].str, "VAR") and std.mem.eql(u8, rows[5][1].str, "b"));
    try approx(0.47099287026405, rows[5][col(r, "Dim1")].num, 1e-11);
    try approx(0.00452328053297, rows[5][col(r, "SqCos2")].num, 1e-11);
    // Best indicators (pp.2603-2604) as SAS printed them.
    const best = [_][3]f64{ .{ 1, 0, 1 }, .{ 0, 2, 2 }, .{ 2, 2, 2 }, .{ 1, 0, 1 }, .{ 2, 2, 2 }, .{ 0, 2, 2 } };
    for (best, 1..) |b, i| {
        try approx(b[0], rows[i][col(r, "Best1")].num, 0);
        try approx(b[1], rows[i][col(r, "Best2")].num, 0);
        try approx(b[2], rows[i][col(r, "Best")].num, 0);
    }
}

test "STAT-CORRESP-001 BY groups, WEIGHT and excluded observations" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc corresp data=s out=r2 short dimens=1 noprint; by g; var a b c; weight w; run;");
    try expectEqual(@as(usize, 0), out.items.len);
    const r = env.lib.find("r2").?;
    // SAS: 14 observations, 11 variables (g first); group 1 keeps Row1, Row4,
    // Row7 only.
    try expectEqual(@as(usize, 14), r.rows.items.len);
    try expectEqual(@as(usize, 11), r.columns.items.len);
    try expect(std.mem.eql(u8, r.columns.items[0].name, "g"));
    const rows = r.rows.items;
    for ([_][]const u8{ "Row1", "Row4", "Row7" }, 1..) |n, i| try expect(std.mem.eql(u8, rows[i][2].str, n));
    // Weighted mass of r4: 2*17/100.5 (n = 60 + 34 + 6.5).
    try approx(34.0 / 100.5, rows[2][col(r, "Mass")].num, 1e-14);
    try approx(0.08946638361779, rows[0][col(r, "Inertia")].num, 1e-12);
    try approx(0.86658450168917, rows[3][col(r, "Dim1")].num, 1e-11);
    try approx(2, rows[7][0].num, 0);
    try approx(0.46248122416466, rows[8][col(r, "Dim1")].num, 1e-11);
}

test "STAT-CORRESP-001 user errors and loud gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    const cases = [_]struct { source: []const u8, rc: u8 }{
        .{ .source = "proc corresp data=s; run;", .rc = 1 }, // VAR or TABLES required
        .{ .source = "proc corresp data=s; var a nm; run;", .rc = 1 }, // character VAR
        .{ .source = "proc corresp data=s; var a zz; run;", .rc = 1 },
        .{ .source = "proc corresp data=s; var a b; weight nm; run;", .rc = 1 },
        .{ .source = "proc corresp data=s; var a b; weight w; weight w; run;", .rc = 1 },
        .{ .source = "proc corresp data=s; var a b; id zz; run;", .rc = 1 },
        .{ .source = "proc corresp data=s bogus; var a b; run;", .rc = 1 },
        .{ .source = "proc corresp data=s no; var a b; run;", .rc = 1 }, // two letters: no alias
        .{ .source = "proc corresp data=s dimens=0; var a b; run;", .rc = 1 },
        .{ .source = "proc corresp data=s mininertia=2; var a b; run;", .rc = 1 },
        .{ .source = "proc corresp data=nosuch; var a b; run;", .rc = 1 },
        .{ .source = "proc corresp data=s rp; var a b c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s norow=sideways; var a b c; run;", .rc = 1 },
        .{ .source = "proc corresp data=s mca nvars=3; var a b c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s observed; var a b c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s outf=f; var a b c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s short short; var a b c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s; tables a, b; run;", .rc = 2 },
        .{ .source = "proc corresp data=s; var a b c; supplementary c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s(where=(g=2)) dimens=3; var a b c; run;", .rc = 2 }, // above min(nr,nc)-1
        .{ .source = "proc corresp data=s(where=(g=2)); var a b; var c; run;", .rc = 2 },
        .{ .source = "proc corresp data=s(where=(g=1 and a=2)); var a b c; run;", .rc = 2 }, // one usable row
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = corresp.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expectEqual(@as(usize, 0), output.items.len);
    }
}

test "STAT-CORRESP-001 negative weights mark supplementary rows" {
    // p.2579: a negative WEIGHT makes the observation a supplementary row.
    // Active rows are the g=2 table; SAS 9.4 placed s1 = (1,1,1) at
    // (0.23421042371128, 0.1959577650387) and s2 = (2,6,1) (weight -2) at
    // (0.65252366859104, 0.91439467618382), with squared cosines
    // 0.58822722080442 / 0.4117727791957 and 0.3374162226227 / 0.66258377737734.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const t = try a.create(Dataset);
    t.* = Dataset.init(a, "t");
    for ([_][]const u8{ "a", "b", "c", "w" }) |n| _ = try t.addColumn(n, .num);
    for ([_][4]f64{ .{ 3, 5, 7, 1 }, .{ 4, 1, 2, 1 }, .{ 1, 1, 1, -1 }, .{ 9, 2, 5, 1 }, .{ 2, 6, 1, -2 } }) |r| try t.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
    try lib.put("t", t);
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    try corresp.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, "proc corresp data=t out=o short; var a b c; weight w; run;", &d));
    const o = lib.find("o").?;
    const rows = o.rows.items;
    // INERTIA, 3 OBS, 2 SUPOBS, 3 VAR; inertia of the active table only.
    try expectEqual(@as(usize, 9), rows.len);
    try approx(0.13996067176871, rows[0][col(o, "Inertia")].num, 1e-12);
    try expect(std.mem.eql(u8, rows[4][0].str, "SUPOBS") and std.mem.eql(u8, rows[4][1].str, "Row3"));
    try expect(std.mem.eql(u8, rows[5][1].str, "Row5"));
    try approx(0.23421042371128, rows[4][col(o, "Dim1")].num, 1e-11);
    try approx(0.1959577650387, rows[4][col(o, "Dim2")].num, 1e-11);
    try approx(0.58822722080442, rows[4][col(o, "SqCos1")].num, 1e-11);
    try approx(0.65252366859104, rows[5][col(o, "Dim1")].num, 1e-11);
    try approx(0.91439467618382, rows[5][col(o, "Dim2")].num, 1e-11);
    try approx(0.66258377737734, rows[5][col(o, "SqCos2")].num, 1e-11);
    try approx(1, rows[5][col(o, "Quality")].num, 1e-12);
    try expect(rows[4][col(o, "Mass")].isMissing() and rows[4][col(o, "Contr1")].isMissing() and rows[4][col(o, "Best")].isMissing());
    try expect(std.mem.indexOf(u8, output.items, "Supplementary Row Coordinates") != null);
}

test "STAT-CORRESP-001 NOROW= and NOCOLUMN= suppress listing and OUTC= points" {
    // p.2572: DATA drops the points from OUTC=, PRINT from the listing, BOTH
    // (the bare option) from both.
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc corresp data=s(where=(g=2)) out=o nocol=dat short; var a b c; run;");
    try expectEqual(@as(usize, 4), env.lib.find("o").?.rows.items.len); // INERTIA + 3 OBS
    try expect(std.mem.indexOf(u8, out.items, "Column Coordinates") != null);
    out.clearRetainingCapacity();
    try env.run(&out, "proc corresp data=s(where=(g=2)) out=o2 norow=print short; var a b c; run;");
    try expectEqual(@as(usize, 7), env.lib.find("o2").?.rows.items.len);
    try expect(std.mem.indexOf(u8, out.items, "Row Coordinates") == null);
    out.clearRetainingCapacity();
    try env.run(&out, "proc corresp data=s(where=(g=2)) out=o3 norow short; var a b c; run;");
    try expectEqual(@as(usize, 4), env.lib.find("o3").?.rows.items.len); // INERTIA + 3 VAR
    try expect(std.mem.indexOf(u8, out.items, "Row Coordinates") == null);
}
