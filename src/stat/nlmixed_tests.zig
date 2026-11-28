//! STAT-NLMIXED-001 permanent tests. The table layouts are the SAS 9.4
//! reference listing of the chapter's nested-variance program (Specifications
//! and Dimensions do not depend on the random response values, only on the
//! 100 x 5 x 2 design, which the invented data below reproduces). Counts in
//! the other tests are hand-computed. No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const nlmixed = @import("nlmixed.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const by = @import("by_groups.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// A = 1..100, B = 1..5, rep = 1..2 (1000 rows), resp invented; with
/// `groups` = 2 every row is repeated for g = 1 and g = 2 (sorted by g).
fn nested(a: A, name: []const u8, groups: usize) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for ([_][]const u8{ "g", "A", "B", "rep", "resp" }) |n| _ = try ds.addColumn(n, .num);
    for (1..groups + 1) |g| for (1..101) |ia| for (1..6) |ib| for (1..3) |r| {
        const v: f64 = 10 + @as(f64, @floatFromInt((ia * 7 + ib * 3 + r) % 11)) / 4;
        try ds.appendRow(&.{ .{ .num = @floatFromInt(g) }, .{ .num = @floatFromInt(ia) }, .{ .num = @floatFromInt(ib) }, .{ .num = @floatFromInt(r) }, .{ .num = v } });
    };
    return ds;
}

/// Small invented data: subjects out of order (s = 2 1 2 3 1 3 2), a
/// character column, a missing response in row 4 of `miss`.
fn small(a: A, name: []const u8, with_missing: bool) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for ([_][]const u8{ "s", "c", "x", "y" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("t", .char);
    const rows = [_][4]f64{ .{ 2, 1, 1, 3.2 }, .{ 1, 1, 2, 4.1 }, .{ 2, 2, 3, 5.0 }, .{ 3, 1, 4, 6.3 }, .{ 1, 2, 5, 6.9 }, .{ 3, 2, 6, 8.2 }, .{ 2, 1, 7, 9.0 } };
    for (rows, 0..) |r, k| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = if (with_missing and k == 3) nan else r[3] }, .{ .str = "u" } });
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
        for ([_]*Dataset{ try nested(self.a(), "nested", 1), try nested(self.a(), "twice", 2), try small(self.a(), "obs", false), try small(self.a(), "miss", true) }) |ds| try self.lib.put(ds.name, ds);
        const empty = try self.a().create(Dataset);
        empty.* = Dataset.init(self.a(), "none");
        for ([_][]const u8{ "s", "y" }) |n| _ = try empty.addColumn(n, .num);
        try self.lib.put(empty.name, empty);
    }
    fn cx(self: *Fixture, d: *diag.Diagnostics) proc.ProcCtx {
        return .{ .arena = self.a(), .lib = &self.lib, .diags = d };
    }
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        nlmixed.run(self.cx(&d), &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expect(failed);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !nlmixed.Spec {
        return nlmixed.parse(self.cx(d), try lex.tokenize(self.a(), source, d));
    }
};

const nested_step =
    \\bounds vara >=0, varb_a >=0;
    \\mean = intercept + aeffect + beffect;
    \\model resp ~ normal (mean, s2);
    \\random aeffect ~ normal(0,vara) subject = A;
    \\random beffect ~ normal(0,varb_a) subject = B(A);
    \\run;
;

test "STAT-NLMIXED-001 declarations, defaults and variable roles" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, "proc nlmixed data = nested;\n" ++ nested_step);
    try std.testing.expectEqualStrings("WORK.NESTED", s.data_name);
    try expect(s.alpha == 0.05 and s.df == null and s.distribution == .normal);
    try expectEqual(@as(usize, 4), s.response);
    // Parameters in order of first appearance; unlisted ones start at 1.
    try expectEqual(@as(usize, 4), s.params.len);
    for (s.params, [_][]const u8{ "vara", "varb_a", "intercept", "s2" }) |p, n| {
        try std.testing.expectEqualStrings(n, p.name);
        try expect(p.start == 1);
    }
    try expectEqual(@as(usize, 2), s.randoms.len);
    try expectEqual(@as(usize, 1), s.randoms[0].subject);
    try expectEqual(@as(usize, 2), s.randoms[1].subject);
    try std.testing.expectEqualSlices(usize, &.{1}, s.randoms[1].within);
    try std.testing.expectEqualSlices(usize, &.{}, s.data_cols);
    try expectEqual(@as(usize, 2), s.bounds.len);
    try expect(s.bounds[0].lower.? == 0 and s.bounds[0].upper == null);
    // Explicit settings: PARMS starts, ALPHA=, DF=, ID, last BY wins (p.7117),
    // a data variable in the program and a two-sided bound.
    const e = try fx.spec(&d,
        \\proc nlmixed data=obs alpha=0.1 df=20;
        \\parms b0 b1 = 0.5, s2u = 2 s2e=3;
        \\bounds 0 <= s2u <= 10;
        \\eta = b0 + b1*x + u;
        \\model y ~ normal(eta, s2e);
        \\random u ~ normal(0, s2u) subject=s;
        \\id eta;
        \\by x;
        \\by descending c notsorted;
        \\run;
    );
    try expect(e.alpha == 0.1 and e.df.? == 20);
    for (e.params, [_][]const u8{ "b0", "b1", "s2u", "s2e" }, [_]f64{ 0.5, 0.5, 2, 3 }) |p, n, v| {
        try std.testing.expectEqualStrings(n, p.name);
        try expect(p.start == v);
    }
    try std.testing.expectEqualSlices(usize, &.{2}, e.data_cols);
    try expect(e.bounds[0].lower.? == 0 and e.bounds[0].upper.? == 10);
    try std.testing.expectEqualStrings("eta", e.ids[0]);
    try std.testing.expectEqualSlices(usize, &.{1}, e.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, e.by_desc);
    try expect(e.notsorted);
    try expect(!d.hasErrors());
}

test "STAT-NLMIXED-001 Specifications and Dimensions match the SAS reference layout" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, "proc nlmixed data = nested;\n" ++ nested_step);
    var out: std.ArrayList(u8) = .empty;
    try nlmixed.renderSpecifications(fx.cx(&d), &out, s);
    const an = try nlmixed.analyze(fx.cx(&d), s, s.input.ds.rows.items);
    try nlmixed.renderGroupHeader(fx.cx(&d), &out, s, s.input.ds.rows.items[0]);
    // Quadrature Points comes from STAT-NLMIXED-002's adaptive selection; the
    // reference value 1 is passed in.
    try nlmixed.renderDimensions(fx.cx(&d), &out, s, an, 1);
    const expected =
        "\n" ++
        "The NLMIXED Procedure\n" ++
        "\n" ++
        "                         Specifications\n" ++
        "\n" ++
        "Data Set                                    WORK.NESTED         \n" ++
        "Dependent Variable                          resp                \n" ++
        "Distribution for Dependent Variable         Normal              \n" ++
        "Random Effects                              aeffect, beffect    \n" ++
        "Distribution for Random Effects             Normal, Normal      \n" ++
        "Subject Variables                           A, B                \n" ++
        "Optimization Technique                      Dual Quasi-Newton   \n" ++
        "Integration Method                          Adaptive Gaussian   \n" ++
        "                                            Quadrature          \n" ++
        "\n" ++
        "\n" ++
        "               Dimensions\n" ++
        "\n" ++
        "Observations Used                   1000\n" ++
        "Observations Not Used                  0\n" ++
        "Total Observations                  1000\n" ++
        "Subjects [A]                         100\n" ++
        "Max Obs per Subject                   10\n" ++
        "Subjects [B]                         500\n" ++
        "Max Obs per Subject                    2\n" ++
        "Parameters                             4\n" ++
        "Quadrature Points                      1\n";
    try std.testing.expectEqualStrings(expected, out.items);
}

test "STAT-NLMIXED-001 BY groups: one Specifications table, then per-group BY line and Dimensions" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, "proc nlmixed data = twice;\nby g;\n" ++ nested_step);
    const slices = try by.checkedSlices(fx.a(), s.input.ds, s.by_cols, s.by_desc, s.notsorted, &d);
    try expectEqual(@as(usize, 2), slices.len);
    var out: std.ArrayList(u8) = .empty;
    try nlmixed.renderSpecifications(fx.cx(&d), &out, s);
    for (slices) |slice| {
        const an = try nlmixed.analyze(fx.cx(&d), s, slice.rows);
        try expectEqual(@as(usize, 1000), an.total);
        try nlmixed.renderGroupHeader(fx.cx(&d), &out, s, slice.rows[0]);
        try nlmixed.renderDimensions(fx.cx(&d), &out, s, an, 1);
    }
    const text = out.items;
    try expect(std.mem.startsWith(u8, text, "\nThe NLMIXED Procedure\n\n                         Specifications\n\nData Set                                    WORK.TWICE          \n"));
    try expect(std.mem.indexOf(u8, text, "                                            Quadrature          \n\ng=1\n\nThe NLMIXED Procedure\n\n               Dimensions\n\nObservations Used                   1000\n") != null);
    try expect(std.mem.indexOf(u8, text, "Quadrature Points                      1\n\ng=2\n\nThe NLMIXED Procedure\n\n               Dimensions\n") != null);
    try expectEqual(@as(usize, 1), std.mem.count(u8, text, "Specifications"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, text, "Subjects [B]                         500\n"));
}

test "STAT-NLMIXED-001 subject clusters use unique values, not runs, and nest" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    // s = 2 1 2 3 1 3 2: 3 subjects (p.7112, unique values since 13.1), the
    // largest (s=2) has 3 observations. c(s) nested: (2,1) (1,1) (2,2) (3,1)
    // (1,2) (3,2) (2,1): 6 clusters, at most 2 observations.
    const s = try fx.spec(&d,
        \\proc nlmixed data=obs;
        \\eta = b0 + u + v;
        \\model y ~ normal(eta, s2);
        \\random u ~ normal(0, g1) subject=s;
        \\random v ~ normal(0, g2) subject=c(s);
    );
    const an = try nlmixed.analyze(fx.cx(&d), s, s.input.ds.rows.items);
    try expectEqual(@as(usize, 7), an.used);
    try expectEqual(@as(usize, 3), an.clusters[0].subjects);
    try expectEqual(@as(usize, 3), an.clusters[0].max_obs);
    try expectEqual(@as(usize, 6), an.clusters[1].subjects);
    try expectEqual(@as(usize, 2), an.clusters[1].max_obs);
    // WHERE selects observations before the accounting.
    const w = try fx.spec(&d, "proc nlmixed data=obs; where x > 2; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;");
    const wa = try nlmixed.analyze(fx.cx(&d), w, w.input.ds.rows.items);
    try expectEqual(@as(usize, 5), wa.total);
    try expectEqual(@as(usize, 3), wa.clusters[0].subjects);
    try expectEqual(@as(usize, 2), wa.clusters[0].max_obs);
}

test "STAT-NLMIXED-001 invalid declarations are user errors (rc 1) and print nothing" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const tail = " eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;";
    for ([_][]const u8{
        "proc nlmixed data=absent;" ++ tail,
        "proc nlmixed bogus;" ++ tail,
        "proc nlmixed bogus=3;" ++ tail,
        "proc nlmixed alpha=0;" ++ tail,
        "proc nlmixed alpha=1;" ++ tail,
        "proc nlmixed df=0;" ++ tail,
        "proc nlmixed data=obs; eta = b0 + u; random u ~ normal(0, g) subject=s;",
        "proc nlmixed data=obs;" ++ tail ++ " model y ~ normal(eta, s2);",
        "proc nlmixed data=obs; eta = b0; model nosuch ~ normal(eta, s2);",
        "proc nlmixed data=obs; eta = b0; model t ~ normal(eta, s2);",
        "proc nlmixed data=obs; eta = b0; model y = normal(eta, s2);",
        "proc nlmixed data=obs; eta = b0; model y ~ normal(eta);",
        "proc nlmixed data=obs; eta = b0; model y ~ poisson(eta, s2);",
        "proc nlmixed data=obs; eta = b0; model y ~ cauchy(eta, s2);",
        "proc nlmixed data=obs; model y ~ normal(eta, s2); eta = b0;",
        "proc nlmixed data=obs; eta = b0 + u; model y ~ normal(eta, s2); random u ~ gamma(0, g) subject=s;",
        "proc nlmixed data=obs; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g);",
        "proc nlmixed data=obs; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=nosuch;",
        "proc nlmixed data=obs; eta = b0 + x; model y ~ normal(eta, s2); random x ~ normal(0, g) subject=s;",
        "proc nlmixed data=obs; parms u = 1;" ++ tail,
        "proc nlmixed data=obs; parms b0 = 1, b0 = 2;" ++ tail,
        "proc nlmixed data=obs; parms x = 1;" ++ tail,
        "proc nlmixed data=obs; parms b0;" ++ tail,
        "proc nlmixed data=obs; bounds x >= 0;" ++ tail,
        "proc nlmixed data=obs; bounds g;" ++ tail,
        "proc nlmixed data=obs; bounds g >= 0,;" ++ tail,
        "proc nlmixed data=obs; id;" ++ tail,
        "proc nlmixed data=obs; by nosuch;" ++ tail,
        "proc nlmixed data=obs; bogus y;" ++ tail,
        // p.7117: BY input must be sorted (x descends within this order).
        "proc nlmixed data=obs; by s;" ++ tail,
    }) |source| {
        const r = try fx.outcome(source);
        expectEqual(@as(u8, 1), r.rc) catch |err| {
            std.debug.print("expected rc 1 for: {s}\n", .{source});
            return err;
        };
        try expectEqual(@as(usize, 0), r.out.len);
    }
}

test "STAT-NLMIXED-001 valid but unimplemented features are loud gaps (rc 2)" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const tail = " eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;";
    for ([_][]const u8{
        // The default estimation itself (STAT-NLMIXED-002), with and without BY.
        "proc nlmixed data=nested;" ++ nested_step,
        "proc nlmixed data=twice; by g;" ++ nested_step,
        "proc nlmixed data=obs; parms b0 = 0.5; bounds g >= 0; id eta;" ++ tail,
        "proc nlmixed data=obs method=firo;" ++ tail,
        "proc nlmixed data=obs tech=newrap;" ++ tail,
        "proc nlmixed data=obs qpoints=5;" ++ tail,
        "proc nlmixed data=obs nosortsub;" ++ tail,
        "proc nlmixed data=obs cov corr;" ++ tail,
        "proc nlmixed data=obs noprint;" ++ tail,
        "proc nlmixed data=obs alpha=0.1 alpha=0.2;" ++ tail,
        "proc nlmixed data=obs;" ++ tail ++ " predict eta out=p;",
        "proc nlmixed data=obs;" ++ tail ++ " estimate 'b' b0;",
        "proc nlmixed data=obs;" ++ tail ++ " replicate c;",
        "proc nlmixed data=obs; array b{2} b1 b2;" ++ tail,
        "proc nlmixed data=obs; if x > 2 then w = 1; else w = 0;" ++ tail,
        "proc nlmixed data=obs; parms b0 = 1 to 3 by 1;" ++ tail,
        "proc nlmixed data=obs; parms b0 = 1 / best=2;" ++ tail,
        "proc nlmixed data=obs; bounds g > 0;" ++ tail,
        "proc nlmixed data=obs; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s out=r;",
        "proc nlmixed data=obs; eta = b0 + u + v; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s; random v ~ normal(0, h) subject=c;",
        "proc nlmixed data=obs; eta = b0; model y ~ poisson(exp(eta));",
        "proc nlmixed data=obs; eta = b0; model y ~ normal(eta, s2);",
        "proc nlmixed data=obs; id nosuch;" ++ tail,
        "proc nlmixed data=obs; x = 2;" ++ tail,
        "proc nlmixed data=obs; eta = b0 + u + (t = 'a'); model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;",
        "proc nlmixed data=miss;" ++ tail,
        "proc nlmixed data=none; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;",
    }) |source| {
        const r = try fx.outcome(source);
        expectEqual(@as(u8, 2), r.rc) catch |err| {
            std.debug.print("expected rc 2 for: {s}\n", .{source});
            return err;
        };
        try expectEqual(@as(usize, 0), r.out.len);
    }
}

/// The invented rows of tests/corpus/stat_nlmixed001_missing.sas without its
/// missing-subject row: row 8 has x missing, row 10 has y missing.
fn holes(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "holes");
    for ([_][]const u8{ "s", "c", "x", "y" }) |n| _ = try ds.addColumn(n, .num);
    const rows = [_][4]f64{ .{ 2, 1, 1, 3.2 }, .{ 1, 1, 2, 4.1 }, .{ 2, 2, 3, 5.0 }, .{ 3, 1, 4, 6.3 }, .{ 1, 2, 5, 6.9 }, .{ 3, 2, 6, 8.2 }, .{ 2, 1, 7, 9.0 }, .{ 1, 1, nan, 5.5 }, .{ 3, 1, 3, nan }, .{ 4, 2, 5, 7.7 }, .{ 4, 1, 6, 7.1 } };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
    return ds;
}

fn dimensions(fx: *Fixture, source: []const u8) ![]const u8 {
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, source);
    const an = try nlmixed.analyze(fx.cx(&d), s, s.input.ds.rows.items);
    var out: std.ArrayList(u8) = .empty;
    try nlmixed.renderDimensions(fx.cx(&d), &out, s, an, 1);
    return out.items;
}

test "STAT-NLMIXED-001 missing values, one RANDOM statement and NOSORTSUB match SAS" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    try fx.lib.put("holes", try holes(fx.a()));
    // Expected tables: SAS 9.4 listing of these invented rows (ODS SELECT
    // Dimensions; Quadrature Points from the reference passed in).
    try std.testing.expectEqualStrings("               Dimensions\n\n" ++
        "Observations Used                      9\n" ++
        "Observations Not Used                  2\n" ++
        "Total Observations                    11\n" ++
        "Subjects                               4\n" ++
        "Max Obs per Subject                    3\n" ++
        "Parameters                             4\n" ++
        "Quadrature Points                      1\n", try dimensions(&fx, "proc nlmixed data=holes; eta = b0 + b1*x + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;"));
    // x is not read: its missing value does not exclude row 8.
    try std.testing.expectEqualStrings("               Dimensions\n\n" ++
        "Observations Used                     10\n" ++
        "Observations Not Used                  1\n" ++
        "Total Observations                    11\n" ++
        "Subjects                               4\n" ++
        "Max Obs per Subject                    3\n" ++
        "Parameters                             3\n" ++
        "Quadrature Points                      1\n", try dimensions(&fx, "proc nlmixed data=holes; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;"));
    // NOSORTSUB: used s = 2 1 2 3 1 3 2 4 4 forms 8 runs, the longest 2.
    // (Unused rows sit between 2 and 4 and cannot join a run here.)
    var d = diag.Diagnostics.init(fx.a());
    diag.resetGap();
    defer diag.resetGap();
    const s = try fx.spec(&d, "proc nlmixed data=holes nosortsub; eta = b0 + b1*x + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;");
    try expect(s.nosortsub);
    // With unused observations NOSORTSUB is a gap (where they break runs is
    // not verified); the run count itself is checked on the used rows.
    try std.testing.expectError(error.ParseError, nlmixed.analyze(fx.cx(&d), s, s.input.ds.rows.items));
    try expect(diag.gapHit());
    diag.resetGap();
    const kept = try fx.spec(&d, "proc nlmixed data=holes nosortsub; where x ne . and y ne .; eta = b0 + b1*x + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;");
    const an = try nlmixed.analyze(fx.cx(&d), kept, kept.input.ds.rows.items);
    try expectEqual(@as(usize, 9), an.used);
    try expectEqual(@as(usize, 8), an.clusters[0].subjects);
    try expectEqual(@as(usize, 2), an.clusters[0].max_obs);
}

test "STAT-NLMIXED-001 a missing SUBJECT= value is an error naming the observation" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const ds = try holes(fx.a());
    ds.rows.items[8] = &.{ .{ .num = nan }, .{ .num = 2 }, .{ .num = 2 }, .{ .num = 4.4 } };
    try fx.lib.put("holes", ds);
    const s = try fx.spec(&d, "proc nlmixed data=holes; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;");
    try std.testing.expectError(error.ParseError, nlmixed.checkSubjects(fx.cx(&d), s));
    try expect(d.hasErrors());
    const r = try fx.outcome("proc nlmixed data=holes; eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;");
    try expectEqual(@as(u8, 1), r.rc);
}
