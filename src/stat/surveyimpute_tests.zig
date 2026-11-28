//! STAT-SURVEYIMPUTE-001 permanent checks: the FEFI EM-by-weighting and the
//! jackknife replicate EM against the users-guide worked example (Figures
//! 119.9 and 119.10, physical pp.9728-9730: nine units, items X and Y), plus
//! declarations, user errors (rc 1) and loud gaps (rc 2) through the
//! captured diagnostics reporter. Data are the published example or invented.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const si = @import("surveyimpute.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const close = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

// Figure 119.8: key = 2 X + Y over the complete respondents' cells.
const donors = [_][]const u64{ &.{0}, &.{ 0, 1 }, &.{1}, &.{0}, &.{ 1, 3 }, &.{2}, &.{3}, &.{3}, &.{ 0, 1, 2, 3 } };
const complete = [_]bool{ true, false, true, true, false, true, true, true, false };

fn expectRow(actual: []const f64, expected: []const f64, scale: f64) !void {
    for (actual, expected) |x, y| try close(y, x * scale, 0.000006);
}

test "STAT-SURVEYIMPUTE-001 FEFI initial and converged fractional weights (Figures 119.9, 119.10)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w = [_]f64{1} ** 9;
    const init = try si.em(a, &donors, &complete, &w, null, 0.00001, 0.001, 0);
    try expectRow(init.fractions[1], &.{ 0.66667, 0.33333 }, 1);
    try expectRow(init.fractions[4], &.{ 0.33333, 0.66667 }, 1);
    try expectRow(init.fractions[8], &.{ 0.33333, 0.16667, 0.16667, 0.33333 }, 1);
    const fit = try si.em(a, &donors, &complete, &w, null, 0.00001, 0.001, 100);
    try expect(fit.converged);
    try expectRow(fit.fractions[1], &.{ 0.58601, 0.41399 }, 1);
    try expectRow(fit.fractions[4], &.{ 0.41399, 0.58601 }, 1);
    try expectRow(fit.fractions[8], &.{ 0.32330, 0.22840, 0.12500, 0.32330 }, 1);
    try expectRow(fit.fractions[0], &.{1}, 1);
}

// Kernel regression only: starting each replicate EM from the full-sample
// INITIAL fractions (Figure 119.9) reproduces these Figure 119.10 cells to
// 5 decimals, but not replicate 2 unit 5 (0.37510/0.74990 vs 0.375/0.75)
// nor replicate 6 unit 9; the SAS start rule is unresolved, so ImpRepWt_r
// output is a loud gap.
test "STAT-SURVEYIMPUTE-001 jackknife replicate EM kernel (Figure 119.10 cells)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w = [_]f64{1} ** 9;
    const fit = try si.em(a, &donors, &complete, &w, null, 0.00001, 0.001, 0);
    const Case = struct { rep: usize, unit: usize, want: []const f64 };
    const cases = [_]Case{
        .{ .rep = 0, .unit = 1, .want = &.{ 0.46072, 0.66428 } },
        .{ .rep = 0, .unit = 8, .want = &.{ 0.22659, 0.32669, 0.16071, 0.41101 } },
        .{ .rep = 2, .unit = 1, .want = &.{ 1.12498, 0.00002 } },
        .{ .rep = 2, .unit = 8, .want = &.{ 0.48214, 0.00001, 0.16071, 0.48214 } },
    };
    for (cases) |c| {
        var wr: [9]f64 = undefined;
        for (&wr, 0..) |*x, k| x.* = if (k == c.rep) 0 else 1.125;
        const rep = try si.em(a, &donors, &complete, &wr, fit.fractions, 0.00001, 0.001, 100);
        try expect(rep.converged);
        expectRow(rep.fractions[c.unit], c.want, 1.125) catch |err| {
            std.debug.print("replicate {d} unit {d}: {any}\n", .{ c.rep + 1, c.unit + 1, rep.fractions[c.unit] });
            return err;
        };
    }
}

// ---------------------------------------------------------------------------
// Statement-level checks on invented data: h stratum, c cluster, w weight,
// x and y items with missing values.

const Row = struct { f64, f64, f64, f64, f64 };
const rows = [_]Row{
    .{ 1, 1, 2, 0, 0 },   .{ 1, 1, 2, 0, nan }, .{ 1, 2, 3, 0, 1 }, .{ 1, 2, 3, 1, 1 },
    .{ 2, 3, 1, nan, 1 }, .{ 2, 3, 1, 1, 0 },   .{ 2, 4, 4, 1, 1 }, .{ 2, 4, 4, nan, nan },
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        const ds = try self.a().create(Dataset);
        ds.* = Dataset.init(self.a(), "d");
        for ([_][]const u8{ "h", "c", "w", "x", "y" }) |n| _ = try ds.addColumn(n, .num);
        _ = try ds.addColumn("s", .char);
        for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = "a" } });
        try self.lib.put(ds.name, ds);
    }
    fn rc(self: *Fixture, source: []const u8) !u8 {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        si.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const code = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, code != 0);
        if (code != 0) try expectEqual(@as(usize, 0), out.items.len);
        return code;
    }
    fn expectRc(self: *Fixture, want: u8, sources: []const []const u8) !void {
        for (sources) |source| {
            const got = try self.rc(source);
            expectEqual(want, got) catch |err| {
                std.debug.print("expected rc {d}: {s}\n", .{ want, source });
                return err;
            };
        }
    }
};

test "STAT-SURVEYIMPUTE-001 declarations, user errors and loud gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    try fx.expectRc(0, &.{
        "proc surveyimpute data=d method=fefi varmethod=jackknife; class x y; var x y; strata h; cluster c; weight w;",
        "proc surveyimpute data=d; class x y; var x y; weight w;", // default FEFI, no replicates
        "proc surveyimpute data=d noprint method=fefi(maxemiter=50 relemwtconv=0.0001 absemwtconv=1e-6 maxdonorcells=10); class x y; var x y; strata h; cluster c; output fractionalweights=fw impadjweights=iw impindex=ii obsid=u;",
        "proc surveyimpute data=d varmethod=jk; class x y; var x y; strata h; cluster c; weight w;",
        "proc surveyimpute data=d varmethod=jackknife; class x y; var x y; strata h;", // each observation a PSU
        "proc surveyimpute data=d order=internal seed=5; class x; class y; var x y; cluster c; cluster h; id c; output out=o2 out=o3; output out=o4;",
    });
    try fx.expectRc(1, &.{
        "proc surveyimpute data=d; class x y;", // VAR is required
        "proc surveyimpute data=nosuch; class x y; var x y;",
        "proc surveyimpute data=d; class x y; var x zz;",
        "proc surveyimpute data=d method=bogus; class x y; var x y;",
        "proc surveyimpute data=d varmethod=bogus; class x y; var x y;",
        "proc surveyimpute data=d order=bogus; class x y; var x y;",
        "proc surveyimpute data=d method=fefi(maxemiter=0); class x y; var x y;",
        "proc surveyimpute data=d method=fefi(relemwtconv=-1); class x y; var x y;",
        "proc surveyimpute data=d method=fefi(bogus=1); class x y; var x y;",
        "proc surveyimpute data=d; class x y; var x y; output out=o bogus=1;",
        "proc surveyimpute data=d; class x y; var x y; weight s;",
        "proc surveyimpute data=d; class x y; var x y; id;",
        "proc surveyimpute data=d; class x y; var x y; output fractionalweights;",
        "proc surveyimpute data=d bogus; class x y; var x y;",
        "proc surveyimpute data=d; class x y; var x y; bogus x;",
    });
    try fx.expectRc(2, &.{
        "proc surveyimpute data=d method=hotdeck; class x y; var x y;",
        "proc surveyimpute data=d method=fhdi; class x y; var x y;",
        "proc surveyimpute data=d; var x y;", // default HOTDECK
        "proc surveyimpute data=d method=fefi; class x; var x y;", // continuous item
        "proc surveyimpute data=d varmethod=brr; class x y; var x y;",
        "proc surveyimpute data=d varmethod=bootstrap; class x y; var x y;",
        "proc surveyimpute data=d varmethod=jackknife(dfadjust); class x y; var x y;",
        "proc surveyimpute data=d ndonors=2; class x y; var x y;",
        "proc surveyimpute data=d order=freq; class x y; var x y;",
        "proc surveyimpute data=d rate=0.1; class x y; var x y;",
        "proc surveyimpute data=d; class x y; var x y; repweights w;",
        "proc surveyimpute data=d; class x y; var x y; cells h;",
        "proc surveyimpute data=d; class x y; var x y; impjoint x y;",
        "proc surveyimpute data=d; class x y h; var x y;", // auxiliary CLASS
        "proc surveyimpute data=d; class x y; var x y; strata h / list;",
        "proc surveyimpute data=d; class x y; var x y; output impstatus=st;",
        "proc surveyimpute data=d; class x y; var x y; output donorid=di;",
        "proc surveyimpute data=d; class x y; var x y; output outjkcoefs=j;", // no jackknife
        "proc surveyimpute data=d varmethod=jackknife; class x y; var x y; strata h; cluster c; output out=o outjkcoefs=j;",
        "proc surveyimpute data=d; class x y; var x y; weight x;", // zero weights excluded
    });
    // Single-PSU stratum under the jackknife.
    try fx.expectRc(2, &.{"proc surveyimpute data=d varmethod=jackknife; class x y; var x y; strata h; cluster h;"});
}

test "STAT-SURVEYIMPUTE-001 output data set rows and imputation-adjusted weights" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    try expectEqual(@as(u8, 0), try fx.rc("proc surveyimpute data=d; class x y; var x y; strata h; cluster c; weight w; output out=o fractionalweights=fw;"));
    const o = fx.lib.find("o").?;
    const names = [_][]const u8{ "UnitID", "ImpIndex", "ImpWt", "fw", "h", "c", "w", "x", "y", "s" };
    try expectEqual(names.len, o.columns.items.len);
    for (names, o.columns.items) |n, c| try expect(std.ascii.eqlIgnoreCase(n, c.name));
    // Complete cells (x,y): (0,0) (0,1) (1,1) (1,0). Unit 2 (x=0) has donors
    // y=0,1; unit 5 (y=1) x=0,1; unit 8 all four: 5 complete rows + 2 + 2 + 4.
    try expectEqual(@as(usize, 13), o.rows.items.len);
    const index = [_]f64{ 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 3, 4 };
    const unit = [_]f64{ 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 8, 8, 8 };
    const xs = [_]f64{ 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1 };
    const ys = [_]f64{ 0, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1 };
    var sums = [_]f64{0} ** 8;
    for (o.rows.items, index, unit, xs, ys) |r, ii, u, x, y| {
        try close(u, r[0].num, 0);
        try close(ii, r[1].num, 0);
        try close(x, r[7].num, 0);
        try close(y, r[8].num, 0);
        try close(r[2].num, r[3].num * r[6].num, 1e-12);
        sums[@intFromFloat(u - 1)] += r[2].num;
    }
    // Every unit's ImpWt rows sum to its sampling weight.
    try expectRow(&sums, &.{ 2, 2, 3, 3, 1, 1, 4, 4 }, 1);
    // Complete respondents keep fractional weight 1.
    try close(1, o.rows.items[0][3].num, 0);
}
