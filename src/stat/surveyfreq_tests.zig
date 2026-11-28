//! STAT-SURVEYFREQ-001 permanent checks: declarations, roles, observation
//! selection, execution boundaries, and hand-derived Taylor-series numbers
//! behind the crosstabulation. Data are invented; expected numbers were
//! derived by hand, independently of this code.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const surveyfreq = @import("surveyfreq.zig");
const design = surveyfreq.design;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const close = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const Row = struct { f64, f64, f64, f64, f64 };
/// Columns h (stratum) c (cluster) w a b s(char). Two strata of two PSUs,
/// two observations each; N^ = 20.
const clean = [_]Row{
    .{ 1, 1, 2, 1, 1 }, .{ 1, 1, 2, 1, 2 },
    .{ 1, 2, 3, 2, 1 }, .{ 1, 2, 3, 1, 1 },
    .{ 2, 1, 1, 2, 2 }, .{ 2, 1, 1, 1, 1 },
    .{ 2, 2, 4, 2, 2 }, .{ 2, 2, 4, 2, 1 },
};
/// `clean` plus one row per exclusion rule.
const dirty = clean ++ [_]Row{
    .{ 1, 1, nan, 1, 1 }, // missing WEIGHT
    .{ 1, 1, 0, 1, 1 }, // zero WEIGHT
    .{ 1, 1, -2, 1, 1 }, // negative WEIGHT
    .{ nan, 1, 5, 1, 1 }, // missing STRATA
    .{ 1, nan, 5, 1, 1 }, // missing CLUSTER
};

/// `clean` plus one observation with a missing TABLES value (MCAR exclusion).
const holes = clean ++ [_]Row{.{ 1, 1, 5, nan, 1 }};
/// `clean` plus one observation excluded only for a missing CLUSTER value.
const cluster_hole = clean ++ [_]Row{.{ 1, nan, 5, 1, 1 }};
/// `clean` plus one with a missing TABLES value, under MISSING a new level.
const level_hole = clean ++ [_]Row{.{ 1, 1, 5, 1, nan }};

fn dataset(a: A, name: []const u8, rows: []const Row) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for ([_][]const u8{ "h", "c", "w", "a", "b" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("s", .char);
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = "x" } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8, notes: usize };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        for ([_]*Dataset{ try dataset(self.a(), "dirty", &dirty), try dataset(self.a(), "clean", &clean), try dataset(self.a(), "holes", &holes), try dataset(self.a(), "cluster_hole", &cluster_hole), try dataset(self.a(), "level_hole", &level_hole) }) |ds| try self.lib.put(ds.name, ds);
    }
    fn cx(self: *Fixture, d: *diag.Diagnostics) proc.ProcCtx {
        return .{ .arena = self.a(), .lib = &self.lib, .diags = d };
    }
    /// Exit code under D-009 and the listing, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        surveyfreq.run(self.cx(&d), &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        var notes: usize = 0;
        for (d.list.items) |item| {
            if (item.severity == .note) notes += 1;
        }
        return .{ .rc = rc, .out = out.items, .notes = notes };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !surveyfreq.Spec {
        return surveyfreq.parse(self.cx(d), try lex.tokenize(self.a(), source, d));
    }
    fn expectRc(self: *Fixture, rc: u8, sources: []const []const u8) !void {
        for (sources) |source| {
            const o = try self.outcome(source);
            expectEqual(rc, o.rc) catch |err| {
                std.debug.print("expected rc {d}: {s}\n", .{ rc, source });
                return err;
            };
            // No listing text may precede an error or a gap.
            try expectEqual(@as(usize, 0), o.out.len);
        }
    }
};

fn fixture() !Fixture {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "STAT-SURVEYFREQ-001 declarations defaults and explicit settings" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc surveyfreq; tables a*b;");
    try expectEqual(@as(usize, 1), plain.requests.len);
    try expectEqual(@as(usize, 3), plain.requests[0].row);
    try expectEqual(@as(?usize, 4), plain.requests[0].col);
    try expect(plain.roles.weight == null and plain.roles.fpc == .none and !plain.roles.missing);
    try expect(!plain.row_percent and !plain.chisq and !plain.nosummary);
    try expectEqual(@as(usize, 0), plain.roles.strata.len + plain.roles.clusters.len + plain.by_cols.len);
    const full = try fx.spec(&d, "proc surveyfreq data=dirty MISSING nosummary order=internal varheader=name varmethod=taylor rate=25; strata h s; cluster c; weight w; weight a; table a / row chisq; by h; by descending b notsorted;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 5 }, full.roles.strata);
    try std.testing.expectEqualSlices(usize, &.{1}, full.roles.clusters);
    // Only the first WEIGHT statement is used; only the last BY statement.
    try expectEqual(@as(?usize, 2), full.roles.weight);
    try std.testing.expectEqualSlices(usize, &.{4}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(full.roles.missing and full.nosummary and full.row_percent and full.chisq and full.notsorted);
    try expectEqual(@as(?usize, null), full.requests[0].col);
    // RATE= percentages become proportions and 1 means 100%.
    try close(@as(f64, 0.25), full.roles.fpc.rate, 1e-15);
    try close(@as(f64, 1), (try fx.spec(&d, "proc surveyfreq r=1; tables a*b;")).roles.fpc.rate, 0);
    try close(@as(f64, 0.4), (try fx.spec(&d, "proc surveyfreq rate=.4; tables a*b;")).roles.fpc.rate, 0);
    try close(@as(f64, 12), (try fx.spec(&d, "proc surveyfreq n=12; tables a*b;")).roles.fpc.total, 0);
    try expect(!d.hasErrors());
}

test "STAT-SURVEYFREQ-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    try fx.expectRc(1, &.{
        "proc surveyfreq data=absent; tables a*b;",
        "proc surveyfreq bogus; tables a*b;",
        "proc surveyfreq data=clean rate=.5 total=10; tables a*b;", // mutually exclusive
        "proc surveyfreq data=clean rate=0; tables a*b;",
        "proc surveyfreq data=clean rate=101; tables a*b;",
        "proc surveyfreq data=clean total=0; tables a*b;",
        "proc surveyfreq data=clean order=sideways; tables a*b;",
        "proc surveyfreq data=clean varmethod=magic; tables a*b;",
        "proc surveyfreq data=clean; tables nope*b;",
        "proc surveyfreq data=clean; tables a*;",
        "proc surveyfreq data=clean; tables a*b / bogus;",
        "proc surveyfreq data=clean; tables a*b /;",
        "proc surveyfreq data=clean; weight s; tables a*b;", // character WEIGHT
        "proc surveyfreq data=clean; weight w a; tables a*b;",
        "proc surveyfreq data=clean; strata nope; tables a*b;",
        "proc surveyfreq data=clean; cluster; tables a*b;",
        "proc surveyfreq data=clean; nonsense a;",
        // TOTAL= below the two sampled clusters of a stratum.
        "proc surveyfreq data=clean total=1; strata h; cluster c; weight w; tables a*b / row;",
    });
    try fx.expectRc(2, &.{
        "proc surveyfreq data=clean nomcar; tables a*b;",
        "proc surveyfreq data=clean page; tables a*b;",
        "proc surveyfreq data=clean order=freq; tables a*b;",
        "proc surveyfreq data=clean varheader=label; tables a*b;",
        "proc surveyfreq data=clean varmethod=brr; tables a*b;",
        "proc surveyfreq data=clean varmethod=jackknife; tables a*b;",
        "proc surveyfreq data=clean varmethod=bootstrap; tables a*b;",
        "proc surveyfreq data=clean varmethod=taylor(x); tables a*b;",
        "proc surveyfreq data=clean rate=rates; tables a*b;",
        "proc surveyfreq data=clean total=totals; tables a*b;",
        "proc surveyfreq data=clean; repweights w; tables a*b;",
        "proc surveyfreq data=clean; strata h / list; weight w; tables a*b;",
        "proc surveyfreq data=clean; weight w; tables a*b; tables a*b;",
        "proc surveyfreq data=clean; weight w; tables a*b b*a;",
        "proc surveyfreq data=clean; weight w; tables a*(b h);",
        "proc surveyfreq data=clean; weight w; tables h*a*b;",
        "proc surveyfreq data=clean; weight w; tables a;", // one-way
        "proc surveyfreq data=clean; weight w;", // default one-way tables
        "proc surveyfreq data=clean; weight w; tables a*s;", // character variable
        "proc surveyfreq data=clean; weight w; tables a*b / cl;",
        "proc surveyfreq data=clean; weight w; tables a*b / chisq(secondorder);",
        "proc surveyfreq data=clean; weight w; tables a*b / alpha=.1;",
        "proc surveyfreq data=clean rate=.5; weight w; tables a*b / chisq;",
        // The Rao-Scott test proper (positive correction) is a later ticket.
        "proc surveyfreq data=clean; strata h; cluster c; weight w; tables a*b / chisq;",
        // ROW percentages with a zero-frequency cell (BY group h=2 of `clean`
        // has no a=1, b=2 observation): not verified.
        "proc surveyfreq data=clean; weight w; by h; tables a*b / row;",
        "proc surveyfreq data=level_hole missing; strata h; cluster c; weight w; tables a*b / row;",
        // Observations excluded only by a missing CLUSTER value: Data Summary
        // layout not verified.
        "proc surveyfreq data=cluster_hole; strata h; cluster c; weight w; tables a*b;",
        // CHISQ with excluded observations or single-cluster strata.
        "proc surveyfreq data=holes; strata h; cluster c; weight w; tables a*b / chisq;",
        "proc surveyfreq data=clean; strata h c; cluster c; weight w; tables a*b / chisq;",
    });
}

test "STAT-SURVEYFREQ-001 observation selection under the WEIGHT STRATA CLUSTER rules" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    const rows = fx.lib.find("dirty").?.rows.items;
    const d = try design.build(fx.a(), rows, .{ .strata = &.{0}, .clusters = &.{1}, .weight = 2 });
    try expectEqual(@as(usize, 13), d.read);
    try expectEqual(@as(usize, 3), d.bad_weight);
    try expectEqual(@as(usize, 2), d.bad_design);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, d.kept);
    try expectEqual(@as(usize, 2), d.strata());
    // Clusters are nested within strata: cluster 1 of stratum 1 and of 2 differ.
    try expectEqual(@as(usize, 4), d.clusters());
    try close(@as(f64, 20), d.sum_weights, 1e-12);
    try expect(!d.singlePsuStratum());
    // MISSING keeps the missing STRATA / CLUSTER categories; bad weights still go.
    const m = try design.build(fx.a(), rows, .{ .strata = &.{0}, .clusters = &.{1}, .weight = 2, .missing = true });
    try expectEqual(@as(usize, 3), m.bad_weight);
    try expectEqual(@as(usize, 0), m.bad_design);
    try expectEqual(@as(usize, 10), m.kept.len);
    try expectEqual(@as(usize, 3), m.strata());
    try expectEqual(@as(usize, 6), m.clusters());
    try close(@as(f64, 30), m.sum_weights, 1e-12);
    try expect(m.singlePsuStratum());
    // Without WEIGHT every observation weighs one; without CLUSTER each is a
    // PSU; without STRATA there is one stratum.
    const bare = try design.build(fx.a(), rows, .{});
    try expectEqual(@as(usize, 13), bare.kept.len);
    try expectEqual(@as(usize, 1), bare.strata());
    try expectEqual(@as(usize, 13), bare.clusters());
    try close(@as(f64, 13), bare.sum_weights, 0);
}

test "STAT-SURVEYFREQ-001 Taylor-series table estimates match hand calculation" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    const rows = fx.lib.find("clean").?.rows.items;
    const roles: design.Roles = .{ .strata = &.{0}, .clusters = &.{1}, .weight = 2 };
    const d = try design.build(fx.a(), rows, roles);
    const tb = try surveyfreq.tabulate(fx.a(), d, rows, 3, 4, false);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, tb.row_levels);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, tb.col_levels);
    try expectEqual(@as(usize, 0), tb.missing);
    // Cell (1,1): PSU totals 2, 3 | 1, 0 -> V = 2(0.5) + 2(0.5) = 2.
    const c11 = tb.at(0, 0);
    try expectEqual(@as(usize, 3), c11.count);
    try close(@as(f64, 6), c11.wfreq, 1e-12);
    try close(@as(f64, 1.4142135623730951), c11.sd_wfreq, 1e-12);
    // P = 0.3; PSU sums of w(d - P)/20: .04, .06 | .02, -.12 -> V = .0004 + .0196.
    try close(@as(f64, 30), c11.pct, 1e-12);
    try close(@as(f64, 14.142135623730951), c11.se_pct, 1e-10);
    // Row share 6/8; PSU sums of w(d - .75 d_r)/8: -.125, .09375 | .03125, 0
    // -> V = .0478515625 + .0009765625 = .048828125.
    try close(@as(f64, 75), c11.row_pct, 1e-12);
    try close(@as(f64, 22.097086912079607), c11.se_row_pct, 1e-10);
    // Margins: rows 8 and 12, columns 13 and 7.
    try close(@as(f64, 8), tb.at(0, 2).wfreq, 1e-12);
    try close(@as(f64, 12), tb.at(1, 2).wfreq, 1e-12);
    try close(@as(f64, 13), tb.at(2, 0).wfreq, 1e-12);
    try close(@as(f64, 7), tb.at(2, 1).wfreq, 1e-12);
    try close(@as(f64, 100), tb.at(0, 2).row_pct, 1e-12);
    // Grand total: PSU totals 4, 6 | 2, 8 -> V = 4 + 36.
    const all = tb.at(2, 2);
    try expectEqual(@as(usize, 8), all.count);
    try close(@as(f64, 20), all.wfreq, 1e-12);
    try close(@as(f64, 6.324555320336759), all.sd_wfreq, 1e-12);
    try close(@as(f64, 100), all.pct, 1e-12);
    // Pearson: E = 5.2, 2.8, 7.8, 4.2; every |N - E| = 0.8;
    // Q_P = (8/20) 0.64 (1/5.2 + 1/2.8 + 1/7.8 + 1/4.2) = 0.2344322...
    const rs = surveyfreq.raoScott(d, tb).?;
    try close(@as(f64, 0.23443223443223443), rs.pearson, 1e-12);
    try expectEqual(@as(usize, 1), rs.df);
    // (R-1)(C-1) (clusters - strata) = 1 * (4 - 2).
    try expectEqual(@as(usize, 2), rs.den_df);

    // Finite population correction: (1 - f_h) scales each stratum's term.
    const z = [_]f64{ 2, 0, 0, 3, 0, 1, 0, 0 };
    try close(@as(f64, 2), try design.variance(fx.a(), d, &z), 1e-12);
    var with = roles;
    with.fpc = .{ .rate = 0.5 };
    try close(@as(f64, 1), try design.variance(fx.a(), try design.build(fx.a(), rows, with), &z), 1e-12);
    with.fpc = .{ .total = 8 }; // f_h = 2/8
    try close(@as(f64, 1.5), try design.variance(fx.a(), try design.build(fx.a(), rows, with), &z), 1e-12);
}

test "STAT-SURVEYFREQ-001 listing blocks follow the requested options" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    const o = try fx.outcome("proc surveyfreq data=clean; strata h; cluster c; weight w; tables a*b / row;");
    try expectEqual(@as(u8, 0), o.rc);
    try expectEqual(@as(usize, 0), o.notes);
    try expect(std.mem.startsWith(u8, o.out, "\nThe SURVEYFREQ Procedure\n\n            Data Summary\n\nNumber of Strata                   2\nNumber of Clusters                 4\nNumber of Observations             8\nSum of Weights                    20\n\n\n"));
    try expect(std.mem.indexOf(u8, o.out, "Table of a by b\n") != null);
    try expect(std.mem.indexOf(u8, o.out, "         1           1             3       6.00000       1.41421     30.0000       14.1421     75.0000        22.0971\n") != null);
    try expect(std.mem.indexOf(u8, o.out, "Rao-Scott") == null);
    // No STRATA / CLUSTER statement: their Data Summary rows are not shown.
    const bare = try fx.outcome("proc surveyfreq data=clean; weight w; tables a*b / row;");
    try expectEqual(@as(u8, 0), bare.rc);
    try expect(std.mem.indexOf(u8, bare.out, "Number of Strata") == null and std.mem.indexOf(u8, bare.out, "Number of Clusters") == null);
    try expect(std.mem.indexOf(u8, bare.out, "Number of Observations             8\nSum of Weights                    20\n") != null);
    const quiet = try fx.outcome("proc surveyfreq data=clean nosummary; strata h; cluster c; weight w; tables a*b / row;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expect(std.mem.indexOf(u8, quiet.out, "Data Summary") == null and std.mem.indexOf(u8, quiet.out, "Table of a by b") != null);
}

test "STAT-SURVEYFREQ-001 BY groups, no WEIGHT, duplicate roles, exclusions and single clusters" {
    var fx = try fixture();
    defer fx.arena.deinit();
    try fx.init();
    // Several STRATA / CLUSTER statements accumulate (SAS-verified).
    var d = diag.Diagnostics.init(fx.a());
    const dup = try fx.spec(&d, "proc surveyfreq data=clean; strata h; strata s; cluster c; cluster a; tables a*b;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 5 }, dup.roles.strata);
    try std.testing.expectEqualSlices(usize, &.{ 1, 3 }, dup.roles.clusters);
    // No WEIGHT: unit weights, no Sum of Weights, no weighted columns. With
    // every observation a PSU and P(1,1) = 3/8: z_i = d_i - 3/8 (n = 8), so
    // V = 8/7 * (3 (5/8)^2 + 5 (3/8)^2) / 64 = 15/448 -> 18.2981%.
    const bare = try fx.outcome("proc surveyfreq data=clean; tables a*b / row;");
    try expectEqual(@as(u8, 0), bare.rc);
    try expect(std.mem.indexOf(u8, bare.out, "Sum of Weights") == null and std.mem.indexOf(u8, bare.out, "Weighted") == null);
    try expect(std.mem.indexOf(u8, bare.out, "Number of Observations             8\n\n\n") != null);
    try expect(std.mem.indexOf(u8, bare.out, "         1           1             3     37.5000       18.2981") != null);
    // Missing TABLES value: excluded from the table and its variances (MCAR),
    // still a valid observation of the Data Summary; the table equals `clean`.
    const mcar = try fx.outcome("proc surveyfreq data=holes; strata h; cluster c; weight w; tables a*b / row;");
    try expectEqual(@as(u8, 0), mcar.rc);
    try expect(std.mem.indexOf(u8, mcar.out, "Number of Observations             9\nSum of Weights                    25\n") != null);
    try expect(std.mem.indexOf(u8, mcar.out, "         1           1             3       6.00000       1.41421     30.0000       14.1421     75.0000        22.0971\n") != null);
    try expect(std.mem.indexOf(u8, mcar.out, "Frequency Missing = 1\n") != null);
    // Nonpositive weights and a missing STRATA / CLUSTER value: Used and
    // Nonpositive rows, one NOTE; the remaining design is `clean`.
    const excl = try fx.outcome("proc surveyfreq data=dirty; strata h; cluster c; weight w; tables a*b / row;");
    try expectEqual(@as(u8, 0), excl.rc);
    try expectEqual(@as(usize, 1), excl.notes);
    try expect(std.mem.indexOf(u8, excl.out, "Number of Observations                            13\nNumber of Observations Used                        8\nNumber of Obs with Nonpositive Weights             3\nSum of Weights                                    20\n") != null);
    try expect(std.mem.indexOf(u8, excl.out, "         1           1             3       6.00000       1.41421     30.0000       14.1421") != null);
    // One cluster per stratum everywhere: variances missing, with a NOTE.
    const single = try fx.outcome("proc surveyfreq data=clean; strata h c; cluster c; weight w; tables a*b;");
    try expectEqual(@as(u8, 0), single.rc);
    try expectEqual(@as(usize, 1), single.notes);
    try expect(std.mem.indexOf(u8, single.out, "         1           1             3       6.00000             .     30.0000         .    \n") != null);
    // BY groups: one Data Summary per group with its own counts, one BY NOTE.
    // A zero-frequency cell is shown with missing estimates (BY h=2: a=1, b=2).
    const grouped = try fx.outcome("proc surveyfreq data=clean; by h; cluster c; weight w; tables a*b;");
    try expectEqual(@as(u8, 0), grouped.rc);
    try expect(std.mem.indexOf(u8, grouped.out, "                     2             0             .             .       .             .    \n") != null);
    // MISSING: the missing TABLES value is a level, ordered first; w = 5 of 25.
    const level = try fx.outcome("proc surveyfreq data=level_hole missing; strata h; cluster c; weight w; tables a*b;");
    try expectEqual(@as(u8, 0), level.rc);
    try expect(std.mem.indexOf(u8, level.out, "         1           .             1       5.00000") != null);
    try expect(std.mem.indexOf(u8, level.out, "     20.0000") != null);
    const by_ok = try fx.outcome("proc surveyfreq data=clean; by h; weight w; tables c*h;");
    try expectEqual(@as(u8, 0), by_ok.rc);
    try expectEqual(@as(usize, 1), by_ok.notes);
    try expect(std.mem.indexOf(u8, by_ok.out, "\nh=1\n\nThe SURVEYFREQ Procedure\n") != null and std.mem.indexOf(u8, by_ok.out, "\nh=2\n\nThe SURVEYFREQ Procedure\n") != null);
    try expectEqual(@as(usize, 2), std.mem.count(u8, by_ok.out, "Data Summary"));
}
