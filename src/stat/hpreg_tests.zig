//! STAT-HPREG-001 permanent tests. Expected numbers are the SAS 9.4 listing
//! of the invented data below (the same rows as tests/corpus/stat_hpreg_fit.sas),
//! compared to the displayed precision. No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const hpreg = @import("hpreg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns: b y x1 x2 f w (numeric), g id (character). Row 8 has a missing
/// response.
fn sample(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "inv");
    for ([_][]const u8{ "b", "y", "x1", "x2" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("id", .char);
    const rows = [_][6]f64{
        .{ 1, 3.1, 1, 4, 1, 1.0 }, .{ 1, 4.0, 2, 3, 2, 2.0 }, .{ 1, 5.2, 3, 5, 1, 0.5 }, .{ 1, 5.9, 4, 2, 3, 1.5 },
        .{ 1, 7.4, 5, 6, 1, 1.0 }, .{ 1, 7.8, 6, 1, 2, 2.5 }, .{ 1, 9.6, 7, 7, 1, 1.0 }, .{ 1, nan, 8, 3, 1, 1.0 },
        .{ 2, 2.2, 1, 2, 1, 1.0 }, .{ 2, 3.9, 2, 6, 1, 3.0 }, .{ 2, 4.1, 3, 1, 2, 1.0 }, .{ 2, 6.3, 4, 5, 1, 0.5 },
        .{ 2, 6.8, 5, 3, 1, 1.0 }, .{ 2, 8.5, 6, 8, 2, 2.0 }, .{ 2, 9.1, 7, 4, 1, 1.0 },
    };
    for (rows, 0..) |r, k| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .str = if (k % 2 == 0) "A" else "B" }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .str = "r" } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8 };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        const ds = try sample(self.a());
        try self.lib.put(ds.name, ds);
    }
    /// Exit code under D-009 and the listing, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        hpreg.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !hpreg.Spec {
        return hpreg.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
};

/// Agreement to the listing's displayed decimals.
fn shown(expected: f64, actual: f64, decimals: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.5 * std.math.pow(f64, 10, -decimals) + 1e-12);
}

test "STAT-HPREG-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc hpreg; model y = x1;");
    try std.testing.expectEqualStrings("WORK.INV", plain.data_name);
    try expectEqual(@as(usize, 1), plain.response);
    try std.testing.expectEqualSlices(usize, &.{2}, plain.effects);
    try expect(plain.frequency == null and plain.weight == null and plain.seed == null);
    try expect(!plain.noprint and !plain.notsorted and plain.alpha == 0.05);
    try expectEqual(@as(usize, 0), plain.classes.len + plain.by_cols.len + plain.ids.len);
    const full = try fx.spec(&d, "proc hpreg data=inv alpha=0.1 seed=271 noprint; class g; class g; by f; by descending b notsorted; id id b; freq f; weight w; model Y = X2 g x1;");
    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 2 }, full.effects);
    try std.testing.expectEqualSlices(usize, &.{4}, full.classes);
    try std.testing.expectEqualSlices(usize, &.{ 7, 0 }, full.ids);
    try expectEqual(@as(?usize, 5), full.frequency);
    try expectEqual(@as(?usize, 6), full.weight);
    try expectEqual(@as(?f64, 271), full.seed);
    try expect(full.noprint and full.notsorted and full.alpha == 0.1);
    // p.5029: only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{0}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(!d.hasErrors());
}

test "STAT-HPREG-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    for ([_][]const u8{
        "proc hpreg data=absent; model y = x1;",
        "proc hpreg bogus; model y = x1;",
        "proc hpreg alpha=0; model y = x1;",
        "proc hpreg alpha=1.5; model y = x1;",
        "proc hpreg seed=abc; model y = x1;",
        "proc hpreg; class g;",
        "proc hpreg; model y = nosuch;",
        "proc hpreg; model g = x1;",
        "proc hpreg; model y = x1 g;",
        "proc hpreg; model y = x1 y;",
        "proc hpreg; class g; model g = x1;",
        "proc hpreg; model y = x1; model y = x2;",
        "proc hpreg; model y = x1; class g;",
        "proc hpreg; model y = x1 / bogus;",
        "proc hpreg; freq g; model y = x1;",
        "proc hpreg; weight id; model y = x1;",
        "proc hpreg; freq f extra; model y = x1;",
        "proc hpreg; id nosuch; model y = x1;",
        "proc hpreg; by nosuch; model y = x1;",
        "proc hpreg; bogus y; model y = x1;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 1), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
    for ([_][]const u8{
        "proc hpreg namelen=30; model y = x1;",
        "proc hpreg noclprint; class g; model y = x1 g;",
        "proc hpreg; class g / upcase; model y = x1 g;",
        "proc hpreg; class g(ref='A'); model y = x1 g;",
        "proc hpreg; model y = x1*x2;",
        "proc hpreg; model y = x1 x1;",
        "proc hpreg; model y = ;",
        "proc hpreg; model y = x1 / clb;",
        "proc hpreg; model y = x1 / vif;",
        "proc hpreg; model y = x1 / noint;",
        "proc hpreg; model y = x1; selection method=stepwise;",
        "proc hpreg; model y = x1; output out=o p=pred;",
        "proc hpreg; model y = x1; partition fraction(validate=0.3);",
        "proc hpreg; model y = x1; performance nthreads=2;",
        "proc hpreg; model y = x1; performance details;",
        "proc hpreg; model y = x1; performance nodes=4;",
        "proc hpreg; model y = x1; code file='x.sas';",
        "proc hpreg; freq f; freq f; model y = x1;",
        "proc hpreg; format g $1.; class g; model y = x1 g;",
        // Mean squares below 0.01 switch display format in SAS: unverified.
        "proc hpreg; by b; freq f; weight w; model y = x1 x2;",
        // A constant regressor is a linear dependency with the intercept.
        "proc hpreg; by b; model y = x1 b;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 2), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
    // NOPRINT fits and prints nothing; ID is accepted.
    const quiet = try fx.outcome("proc hpreg noprint; id id; model y = x1;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
}

test "STAT-HPREG-001 observation selection, frequency and weight rules match SAS" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
    const rows = fx.lib.find("inv").?.rows.items;
    const plain = try hpreg.analyze(cx, try fx.spec(&d, "proc hpreg; model y = x1 x2;"), rows);
    try expectEqual(@as(usize, 15), plain.read);
    try expectEqual(@as(usize, 14), plain.used);
    const f = plain.fit.?;
    try shown(0.63899, f.sse, 5);
    try shown(70.26929, f.sst, 5);
    try shown(1.166281, f.coefficients[0], 6);
    try shown(1.058609, f.coefficients[1], 6);
    try shown(0.145438, f.coefficients[2], 6);
    try shown(0.031884, f.se[2], 6);
    // CLASS g: GLM parameterization, last level aliased (DF 0, estimate 0).
    const classed = try hpreg.analyze(cx, try fx.spec(&d, "proc hpreg; class g; model y = x1 g x2;"), rows);
    try std.testing.expectEqualStrings("A", classed.levels[0][0]);
    try std.testing.expectEqualStrings("B", classed.levels[0][1]);
    try expectEqual(@as(usize, 5), classed.labels.len);
    try std.testing.expectEqualStrings("g B", classed.labels[3]);
    const cf = classed.fit.?;
    try expect(cf.aliased[3] and !cf.aliased[2]);
    try shown(-0.105102, cf.coefficients[2], 6);
    try shown(0.132528, cf.se[2], 6);
    try shown(0.60118, cf.sse, 5);
    // BY b=1 with FREQ f and WEIGHT w: 8 read, 7 used, frequencies 12 / 11.
    const weighted = try hpreg.analyze(cx, try fx.spec(&d, "proc hpreg; freq f; weight w; model y = x1 x2;"), rows[0..8]);
    try expectEqual(@as(usize, 8), weighted.read);
    try expectEqual(@as(usize, 7), weighted.used);
    try expectEqual(@as(f64, 12), weighted.freq_read);
    try expectEqual(@as(f64, 11), weighted.freq_used);
    try expectEqual(@as(f64, 11), weighted.n);
    try expectEqual(@as(f64, 17), weighted.sum_fw);
    const wf = weighted.fit.?;
    try expectEqual(@as(usize, 8), wf.df_error);
    try shown(55.59721, wf.sst, 5);
    try shown(0.00305, wf.sse, 5);
    try shown(1.582211, wf.coefficients[0], 6);
    try shown(0.002663, wf.se[1], 6);
    try expect(!d.hasErrors());
}
