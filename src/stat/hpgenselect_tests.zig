//! STAT-HPGENSELECT-001 permanent tests. Expected numbers are the SAS 9.4
//! listing of the invented data below (the same rows as
//! tests/corpus/stat_hpgenselect001_roles.sas), compared to the displayed
//! precision. No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const hpg = @import("hpgenselect.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns: id (char), g x y f w (numeric). Rows m..r carry the missing,
/// zero-frequency and zero-weight cases of the corpus fixture.
fn sample(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cnt");
    _ = try ds.addColumn("id", .char);
    for ([_][]const u8{ "g", "x", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_][5]f64{
        .{ 1, 0.5, 2, 1, 1.0 }, .{ 1, 1.2, 3, 2, 0.5 }, .{ 1, 2.0, 5, 1, 2.0 }, .{ 2, 0.3, 0, 3, 1.0 },
        .{ 2, 1.1, 1, 1, 1.5 }, .{ 2, 1.9, 4, 2, 1.0 }, .{ 3, 0.4, 1, 1, 0.8 }, .{ 3, 1.4, 2, 1, 1.2 },
        .{ 3, 2.2, 6, 2, 1.0 }, .{ 1, 0.9, 2, 1, 1.0 }, .{ 2, 1.6, 3, 1, 0.7 }, .{ 3, 1.0, 3, 1, 1.3 },
        .{ 1, nan, 2, 1, 1.0 }, .{ 2, 1.0, nan, 1, 1.0 }, .{ 3, 1.0, 2, 0, 1.0 }, .{ 1, 1.0, 2, 1, 0 },
        .{ nan, 1.0, 2, 1, 1.0 }, .{ 2, 1.0, 2, nan, nan },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = "r" }, .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] } });
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
        hpg.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !hpg.Spec {
        return hpg.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
    fn analysis(self: *Fixture, source: []const u8) !hpg.Analysis {
        var d = diag.Diagnostics.init(self.a());
        const cx: @import("../proc.zig").ProcCtx = .{ .arena = self.a(), .lib = &self.lib, .diags = &d };
        const s = try hpg.parse(cx, try lex.tokenize(self.a(), source, &d));
        return hpg.analyze(cx, s, s.input.ds.rows.items);
    }
};

/// Agreement to the listing's displayed decimals.
fn shown(expected: f64, actual: f64, decimals: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.5 * std.math.pow(f64, 10, -decimals) + 1e-12);
}

test "STAT-HPGENSELECT-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc hpgenselect; model y = x / dist=poisson;");
    try std.testing.expectEqualStrings("WORK.CNT", plain.data_name);
    try expectEqual(@as(usize, 3), plain.response);
    try std.testing.expectEqualSlices(usize, &.{2}, plain.effects);
    try expectEqual(@as(f64, 0.05), plain.alpha);
    try expect(!plain.noprint and plain.frequency == null and plain.weight == null and plain.link == null);
    const full = try fx.spec(&d, "proc hpgenselect data=work.cnt alpha=0.1 noprint; class g; class g; model y = g x / distribution=poisson link=log; freq f; id id x; by g;");
    try expectEqual(@as(f64, 0.1), full.alpha);
    try expect(full.noprint);
    try std.testing.expectEqualSlices(usize, &.{1}, full.classes);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, full.effects);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, full.ids);
    try std.testing.expectEqualSlices(usize, &.{1}, full.by_cols);
    try expectEqual(@as(?usize, 4), full.frequency);
    try std.testing.expectEqualStrings("poisson", full.distribution.?);
    try std.testing.expectEqualStrings("log", full.link.?);
}

test "STAT-HPGENSELECT-001 FREQ selection, counts and fit against the SAS listing" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const an = try fx.analysis("proc hpgenselect data=cnt; class g; model y = g x / distribution=poisson link=log; freq f; id id; run;");
    // Rows m (x), n (y), o (f=0), q (g) and r (f missing) are not used.
    try expectEqual(@as(usize, 18), an.read);
    try expectEqual(@as(usize, 13), an.used);
    try expectEqual(@as(f64, 21), an.freq_read);
    try expectEqual(@as(f64, 18), an.freq_used);
    const f = an.fit.?;
    try expectEqual(@as(usize, 4), f.rank);
    try std.testing.expectEqualSlices(bool, &.{ false, false, false, true, false }, f.aliased);
    try shown(49.5665, f.neg2ll, 4);
    try shown(4.3435, f.pearson, 4);
    for ([_]f64{ -0.552237, 0.220332, -0.336098, 0, 1.092485 }, f.beta) |e, b| try shown(e, b, 6);
    for ([_]f64{ 0.566723, 0.363761, 0.385334, 0, 0.274379 }, f.se) |e, se| try shown(e, se, 6);
}

test "STAT-HPGENSELECT-001 WEIGHT selection and weighted likelihood against the SAS listing" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const an = try fx.analysis("proc hpgenselect data=cnt; class g; model y = g x / dist=poisson; weight w; run;");
    // Rows m, n, p (w=0), q and r (w missing) are not used; o (f=0) is.
    try expectEqual(@as(usize, 13), an.used);
    try expectEqual(@as(f64, 13), an.n);
    const f = an.fit.?;
    try shown(40.2902, f.neg2ll, 4);
    try shown(2.7278, f.pearson, 4);
    for ([_]f64{ -0.217828, 0.073847, -0.406351, 0, 0.917528 }, f.beta) |e, b| try shown(e, b, 6);
    for ([_]f64{ 0.518762, 0.363384, 0.445392, 0, 0.293138 }, f.se) |e, se| try shown(e, se, 6);
}

test "STAT-HPGENSELECT-001 listing layout, BY boundaries and level order" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const r = try fx.outcome("proc hpgenselect data=cnt; class g; model y = g x / distribution=poisson; freq f; run;");
    try expectEqual(@as(u8, 0), r.rc);
    for ([_][]const u8{
        "Number of Threads    1             \n",
        "Frequency Variable        f                          \n",
        "Number of Observations Read              18\nNumber of Observations Used              13\nSum of Frequencies Read                  21\nSum of Frequencies Used                  18\n",
        "g             3    1 2 3 \n",
        "Number of Effects              3\nNumber of Parameters           4\nColumns in X                   5\n",
        "AICC (smaller is better)           60.6435\n",
        "g 3           0               0               .         .             .    \n",
        "x             1        1.092485        0.274379       15.8537        <.0001\n",
    }) |piece| try expect(std.mem.indexOf(u8, r.out, piece) != null);
    // Two sorted BY groups of six rows, each with one missing value: one
    // header, two group pages in BY order with their own counts.
    const srt = try fx.a().create(Dataset);
    srt.* = Dataset.init(fx.a(), "srt");
    for ([_][]const u8{ "g", "x", "y" }) |name| _ = try srt.addColumn(name, .num);
    for ([_][3]f64{
        .{ 1, 0.5, 4 }, .{ 1, 1.2, 1 }, .{ 1, 2.0, 5 }, .{ 1, 0.9, 2 }, .{ 1, nan, 2 }, .{ 1, 1.0, 0 },
        .{ 2, 0.3, 0 }, .{ 2, 1.1, 1 }, .{ 2, 1.9, 4 }, .{ 2, 1.6, 3 }, .{ 2, 1.0, nan }, .{ 2, 1.0, 2 },
    }) |row| try srt.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    try fx.lib.put(srt.name, srt);
    const b = try fx.outcome("proc hpgenselect data=srt; by g; model y = x / dist=poisson; run;");
    try expectEqual(@as(u8, 0), b.rc);
    try expectEqual(@as(usize, 1), std.mem.count(u8, b.out, "Performance Information"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, b.out, "Model Information"));
    const one = std.mem.indexOf(u8, b.out, "\ng=1\n").?;
    const two = std.mem.indexOf(u8, b.out, "\ng=2\n").?;
    try expect(one < two);
    const counts = "Number of Observations Read               6\nNumber of Observations Used               5\n";
    try expect(std.mem.indexOf(u8, b.out[one..two], counts) != null);
    try expect(std.mem.indexOf(u8, b.out[two..], counts) != null);
    // The g=2 page is the analysis of that group alone.
    const alone = try fx.outcome("proc hpgenselect data=srt; where g = 2; model y = x / dist=poisson; run;");
    const model = std.mem.indexOf(u8, alone.out, "Model Information").?;
    try expect(std.mem.endsWith(u8, b.out, alone.out[model..]));
    // An unsorted BY variable is a user error.
    try expectEqual(@as(u8, 1), (try fx.outcome("proc hpgenselect data=cnt; by g; model y = x / dist=poisson; run;")).rc);
}

test "STAT-HPGENSELECT-001 invalid declarations are user errors and gaps are loud" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    for ([_][]const u8{
        "proc hpgenselect bogus; model y = x / dist=poisson; run;",
        "proc hpgenselect alpha=0; model y = x / dist=poisson; run;",
        "proc hpgenselect; class g; run;",
        "proc hpgenselect; model y = x / dist=poisson; class g; run;",
        "proc hpgenselect; model id = x / dist=poisson; run;",
        "proc hpgenselect; model y = id / dist=poisson; run;",
        "proc hpgenselect; model y = x / dist=poisson; freq id; run;",
        "proc hpgenselect; model y = x / dist=poisson; id nosuch; run;",
        "proc hpgenselect; model y = x / dist=wobbly; run;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 1), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
    for ([_][]const u8{
        "proc hpgenselect; model y = x; run;",
        "proc hpgenselect; model y = x / dist=gamma; run;",
        "proc hpgenselect; model y = x / dist=poisson link=identity; run;",
        "proc hpgenselect; model y = x / dist=poisson; selection method=forward; run;",
        "proc hpgenselect; model y = x / dist=poisson; output out=o; run;",
        "proc hpgenselect; model y = x / dist=poisson; performance nthreads=2; run;",
        "proc hpgenselect gconv=1e-6; model y = x / dist=poisson; run;",
        "proc hpgenselect; class g(ref=first); model y = g / dist=poisson; run;",
        "proc hpgenselect; class g; model y = g*x / dist=poisson; run;",
        "proc hpgenselect; model y = x / dist=poisson offset=w; run;",
        "proc hpgenselect; model y = x / dist=poisson; freq f; weight w; run;",
        "proc hpgenselect; class g; model g = x / dist=poisson; run;",
        "proc hpgenselect; model y = / dist=poisson; run;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 2), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
}
