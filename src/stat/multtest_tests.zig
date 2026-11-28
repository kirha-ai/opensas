//! STAT-MULTTEST-001 permanent checks: declarations, roles, observation
//! selection, execution boundaries, and the hand-derived Cochran-Armitage and
//! closed-form adjustment numbers behind the default listing. Data are
//! invented; expected numbers were derived independently of this code.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const multtest = @import("multtest.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns g s f y1 y2 b c. Row comments name the rule each row exercises.
fn roles(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "s", "f", "y1", "y2", "b" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("c", .char);
    const rows = [_]struct { []const u8, f64, f64, f64, f64, f64 }{
        .{ "A", 1, 2.9, 1, 0, 1 }, // FREQ truncates to 2
        .{ "A", 1, 1, 0, nan, 1 }, // missing y2 only
        .{ "", 1, 1, 1, 1, 1 }, // missing CLASS
        .{ "B", nan, 1, 1, 1, 1 }, // missing STRATA
        .{ "B", 1, 0.5, 1, 1, 2 }, // FREQ below 1
        .{ "B", 1, nan, 0, 1, 2 }, // missing FREQ
        .{ "C", 1, 3, 1, 1, 2 },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .str = "x" } });
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
        const ds = try roles(self.a());
        try self.lib.put(ds.name, ds);
    }
    /// Exit code under D-009 and the listing, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        multtest.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !multtest.Spec {
        return multtest.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
};

test "STAT-MULTTEST-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc multtest; class g; test ca(y1);");
    try expectEqual(@as(usize, 0), plain.class);
    try std.testing.expectEqualSlices(usize, &.{3}, plain.tests);
    try expect(plain.strata == null and plain.frequency == null and plain.seed == null and plain.nsample == null);
    try expect(!plain.noprint and !plain.notables and !plain.notsorted);
    try expectEqual(@as(usize, 0), plain.contrasts.len + plain.adjustments.len + plain.by_cols.len);
    const full = try fx.spec(&d, "proc multtest data=sample noprint notables bon SIDAK hoc bonferroni seed=7 nsample=20; class c; test ca(y1-y2 y1); contrast 'Trend' 0 1 2; contrast 'Rev' 1.5 -1 +0; strata s / weight=harmonic; freq f; by s; by descending b notsorted;");
    try expectEqual(@as(usize, 6), full.class);
    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 3 }, full.tests);
    // A repeated adjustment keyword is requested once, in first-seen order.
    try std.testing.expectEqualSlices(multtest.Adjustment, &.{ .bonferroni, .sidak, .hochberg }, full.adjustments);
    try expectEqual(@as(usize, 2), full.contrasts.len);
    try std.testing.expectEqualStrings("Trend", full.contrasts[0].label);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 2 }, full.contrasts[0].values);
    try std.testing.expectEqualSlices(f64, &.{ 1.5, -1, 0 }, full.contrasts[1].values);
    try expectEqual(@as(?usize, 1), full.strata);
    try expectEqual(multtest.StrataWeight.harmonic, full.strata_weight);
    try expectEqual(@as(?usize, 2), full.frequency);
    try expectEqual(@as(?f64, 7), full.seed);
    try expectEqual(@as(?f64, 20), full.nsample);
    try expect(full.noprint and full.notables and full.notsorted);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{5}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(!d.hasErrors());
}

test "STAT-MULTTEST-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const user_errors = [_][]const u8{
        "proc multtest; test ca(y1);", // CLASS required
        "proc multtest; class g;", // TEST required
        "proc multtest; class g s; test ca(y1);", // one CLASS variable
        "proc multtest; class nope; test ca(y1);",
        "proc multtest; class g; test ca(c);", // character test variable
        "proc multtest; class g; test ca();",
        "proc multtest; class g; test zz(y1);",
        "proc multtest; class g; test ca(y1); contrast 0 1 2;", // label required
        "proc multtest; class g; test ca(y1); contrast 'T';",
        "proc multtest; class g; test ca(y1); freq c;",
        "proc multtest; class g; test ca(y1); freq f f;",
        "proc multtest; class g; test ca(y1); strata s / weight=other;",
        "proc multtest seed=-1; class g; test ca(y1);",
        "proc multtest bogus; class g; test ca(y1);",
        "proc multtest data=absent; class g; test ca(y1);",
        "proc multtest bon notables; class g; test ca(y1); contrast 'T' 0 1;", // 2 coefficients, 3 levels
    };
    for (user_errors) |source| {
        const o = try fx.outcome(source);
        expectEqual(@as(u8, 1), o.rc) catch |err| {
            std.debug.print("expected rc 1: {s}\n", .{source});
            return err;
        };
        try expectEqual(@as(usize, 0), o.out.len);
    }
    const gaps = [_][]const u8{
        "proc multtest bootstrap nsample=199 seed=41287 notables; class g; test ca(y1); contrast 'T' 0 1 2;",
        "proc multtest permutation; class g; test ca(y1);",
        "proc multtest stepboot; class g; test ca(y1);",
        "proc multtest bon plots=PByTest(vref=0.05 0.1); class g; test ca(y1);",
        "proc multtest inpvalues=sample bon;",
        "proc multtest holm; class g; test ca(y1);",
        "proc multtest fdr; class g; test ca(y1);",
        "proc multtest order=data bon; class g; test ca(y1);",
        "proc multtest out=o bon; class g; test ca(y1);",
        "proc multtest bon; class g / truncate; test ca(y1);",
        "proc multtest bon; class g; class g; test ca(y1);",
        "proc multtest bon; class g; test fisher(y1);",
        "proc multtest bon; class g; test mean(y1);",
        "proc multtest bon; class g; test ca(y1 / permutation=10);",
        "proc multtest bon; class g; test ca(y1); test ca(y2);",
        "proc multtest bon; class g; test ca(y1); id c;",
        "proc multtest bon notables; class g; test ca(y1); contrast 'T' 0 1 2; strata s;",
        "proc multtest bon notables; class g; test ca(y1);", // default contrast
        "proc multtest bon notables; class g; test ca(y1); contrast 'T' 0 1 2; contrast 'U' 0 1 3;",
        "proc multtest notables; class g; test ca(y1); contrast 'T' 0 1 2;", // no adjustment
        "proc multtest bon sidak notables; class g; test ca(y1); contrast 'T' 0 1 2;",
        "proc multtest bon; class g; test ca(y1); contrast 'T' 0 1 2;", // tabulations
        "proc multtest bon notables; class g; test ca(y1); contrast 'T' 0 1 2; by b;",
        "proc multtest bon notables; class g; test ca(y1); contrast 'T' 0 1 2.5;",
        "proc multtest bon notables; class g; test ca(y1); contrast 'Long label' 0 1 2;",
        "proc multtest bon notables; class s; test ca(y1); contrast 'T' 1;", // numeric CLASS
        "proc multtest bon notables; class g; test ca(f); contrast 'T' 0 1 2;", // non-binary response
    };
    for (gaps) |source| {
        const o = try fx.outcome(source);
        expectEqual(@as(u8, 2), o.rc) catch |err| {
            std.debug.print("expected rc 2: {s}\n", .{source});
            return err;
        };
        try expectEqual(@as(usize, 0), o.out.len);
    }
    // NOPRINT computes and prints nothing.
    const quiet = try fx.outcome("proc multtest bon notables noprint; class g; test ca(y1); contrast 'T' 0 1 3;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
}

test "STAT-MULTTEST-001 observation selection, level order and frequency rules" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const rows = fx.lib.find("sample").?.rows.items;
    // Only a missing CLASS value removes a whole observation by default; a
    // missing test value removes it for that variable only.
    const plain = try multtest.select(fx.a(), try fx.spec(&d, "proc multtest; class g; test ca(y1 y2);"), rows);
    try expectEqual(@as(usize, 7), plain.read);
    try expectEqual(@as(usize, 6), plain.used);
    try expectEqual(@as(usize, 3), plain.levels.len);
    try std.testing.expectEqualStrings("A", plain.levels[0].str);
    try std.testing.expectEqualStrings("C", plain.levels[2].str);
    try std.testing.expectEqualSlices(f64, &.{ 2, 3, 1 }, plain.totals[0]);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 1 }, plain.successes[0]);
    try std.testing.expectEqualSlices(f64, &.{ 1, 3, 1 }, plain.totals[1]);
    try std.testing.expectEqualSlices(f64, &.{ 0, 3, 1 }, plain.successes[1]);
    try expect(!plain.nonbinary);
    // Hand calculation with scores 0, 1, 3.
    try std.testing.expectApproxEqAbs(@as(f64, 0.4291953004403493), multtest.cochranArmitage(plain.totals[0], plain.successes[0], &.{ 0, 1, 3 }), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.22067136191984688), multtest.cochranArmitage(plain.totals[1], plain.successes[1], &.{ 0, 1, 3 }), 1e-12);
    // STRATA and FREQ rules: missing STRATA, missing FREQ and FREQ below 1
    // remove the observation; 2.9 counts twice. Level B disappears.
    const full = try multtest.select(fx.a(), try fx.spec(&d, "proc multtest; class g; test ca(y1 y2); strata s; freq f;"), rows);
    try expectEqual(@as(usize, 3), full.used);
    try expectEqual(@as(usize, 2), full.levels.len);
    try std.testing.expectEqualStrings("C", full.levels[1].str);
    try std.testing.expectEqualSlices(f64, &.{ 3, 3 }, full.totals[0]);
    try std.testing.expectEqualSlices(f64, &.{ 2, 3 }, full.successes[0]);
    try std.testing.expectEqualSlices(f64, &.{ 2, 3 }, full.totals[1]);
    try std.testing.expectEqualSlices(f64, &.{ 0, 3 }, full.successes[1]);
    try std.testing.expectApproxEqAbs(@as(f64, 0.317310507862914), multtest.cochranArmitage(full.totals[0], full.successes[0], &.{ 0, 1 }), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04550026389635843), multtest.cochranArmitage(full.totals[1], full.successes[1], &.{ 0, 1 }), 1e-12);
    try expect(!d.hasErrors());
}

test "STAT-MULTTEST-001 Cochran-Armitage p-value and closed-form adjustments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Three groups of five with 0, 2, 3 events, scores 0 1 2: p = 1/3, N = 3,
    // V = (15/14)(2/9)(10) = 50/21, Z = 1.94422, two-tailed p = 0.05187
    // (the SAS reference prints 0.0519 for this table).
    try std.testing.expectApproxEqAbs(@as(f64, 0.05186866065193838), multtest.cochranArmitage(&.{ 5, 5, 5 }, &.{ 0, 2, 3 }, &.{ 0, 1, 2 }), 1e-12);
    // Zero denominator: no variation in the response, constant scores, m <= 1.
    try expectEqual(@as(f64, 1), multtest.cochranArmitage(&.{ 5, 5 }, &.{ 5, 5 }, &.{ 0, 1 }));
    try expectEqual(@as(f64, 1), multtest.cochranArmitage(&.{ 5, 5 }, &.{ 1, 4 }, &.{ 2, 2 }));
    try expectEqual(@as(f64, 1), multtest.cochranArmitage(&.{ 1, 0 }, &.{ 1, 0 }, &.{ 0, 1 }));
    const raw = [_]f64{ 0.01, 0.04, 0.03, 0.5 };
    const bon = try multtest.adjust(arena.allocator(), .bonferroni, &raw);
    const sid = try multtest.adjust(arena.allocator(), .sidak, &raw);
    const hoc = try multtest.adjust(arena.allocator(), .hochberg, &raw);
    for ([_]f64{ 0.04, 0.16, 0.12, 1 }, bon) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-14);
    // 1 - 0.99^4, 1 - 0.96^4, 1 - 0.97^4, 1 - 0.5^4.
    for ([_]f64{ 0.03940399, 0.15065344, 0.11470719, 0.9375 }, sid) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-14);
    // Ordered 0.01 0.03 0.04 0.5: 0.5; min(0.5, 2*0.04); min(0.08, 3*0.03); min(0.08, 4*0.01).
    for ([_]f64{ 0.04, 0.08, 0.08, 0.5 }, hoc) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-14);
}
