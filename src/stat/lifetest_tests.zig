//! STAT-LIFETEST-001 permanent checks: declarations, roles, observation
//! selection, BY boundaries, execution boundaries, and the hand-derived
//! product-limit and homogeneity numbers behind the default stratified listing.
//! Data are invented, except the published guide sample named where used.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const lifetest = @import("lifetest.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns t c g f w b n id. Row comments name the rule each row exercises.
fn roles(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("t", .num);
    _ = try ds.addColumn("c", .num);
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "f", "w", "b", "n" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("id", .char);
    const rows = [_]struct { f64, f64, []const u8, f64, f64, f64, f64 }{
        .{ 1, 1, "B", 2.9, 1, 1, 2 }, // FREQ truncates to 2
        .{ 2, 0, "A", 1, 0.5, 1, 1 }, // censored
        .{ nan, 1, "A", 1, 1, 1, 1 }, // missing time
        .{ 3, nan, "A", 1, 1, 1, 1 }, // missing censoring value
        .{ 4, 1, "", 1, 1, 2, nan }, // missing stratum
        .{ 5, 1, "A", 0.9, 1, 2, 1 }, // FREQ truncates to 0
        .{ 6, 0, "B", nan, -1, 2, 2 }, // missing FREQ, negative WEIGHT
        .{ 7, 1, "B", 0, 0, 2, 2 }, // zero FREQ, zero WEIGHT
        .{ 8, 1, "A", -1, nan, 2, 1 }, // negative FREQ, missing WEIGHT
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .num = r[6] }, .{ .str = "" } });
    return ds;
}

/// Two strata of five subjects; the same shape as the default stratified case.
fn twoGroups(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "survival");
    _ = try ds.addColumn("time", .num);
    _ = try ds.addColumn("status", .num);
    _ = try ds.addColumn("group", .char);
    const rows = [_]struct { f64, f64, []const u8 }{ .{ 1, 1, "A" }, .{ 2, 0, "A" }, .{ 2, 1, "A" }, .{ 4, 1, "A" }, .{ 5, 0, "A" }, .{ 1, 0, "B" }, .{ 3, 1, "B" }, .{ 4, 1, "B" }, .{ 6, 0, "B" }, .{ 7, 1, "B" } };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = r[2] } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8 };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture, comptime build: fn (A) anyerror!*Dataset) !void {
        self.lib = Library.init(self.a());
        const ds = try build(self.a());
        try self.lib.put(ds.name, ds);
    }
    /// Exit code under D-009 and the listing, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        lifetest.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !lifetest.Spec {
        return lifetest.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
};

test "STAT-LIFETEST-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc lifetest; time t;");
    try expectEqual(@as(usize, 0), plain.time);
    try expect(plain.censor == null and plain.frequency == null and plain.weight == null);
    try expect(!plain.missing and !plain.noprint and !plain.notable and !plain.notruncate and !plain.notsorted);
    try expectEqual(@as(usize, 0), plain.strata.len + plain.ids.len + plain.by_cols.len + plain.censor_values.len);
    const full = try fx.spec(&d, "proc lifetest data=sample missing noprint notable method=KM conftype=loglog; time t*c(0, -1 2); strata g n; freq f / notrunc; weight w; id id g; id b; by n; by descending b notsorted;");
    try expectEqual(@as(?usize, 1), full.censor);
    try std.testing.expectEqualSlices(f64, &.{ 0, -1, 2 }, full.censor_values);
    try std.testing.expectEqualSlices(usize, &.{ 2, 6 }, full.strata);
    try std.testing.expectEqualSlices(usize, &.{ 7, 2, 5 }, full.ids);
    try expectEqual(@as(?usize, 3), full.frequency);
    try expectEqual(@as(?usize, 4), full.weight);
    try expect(full.missing and full.noprint and full.notable and full.notruncate and full.notsorted);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{5}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect((try fx.spec(&d, "proc lifetest method=pl; time t; freq f / notruncate;")).notruncate);
    try expect(!d.hasErrors());
}

test "STAT-LIFETEST-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc lifetest; strata g;", 1 }, // TIME required
        .{ "proc lifetest bogus; time t;", 1 },
        .{ "proc lifetest data=nosuch; time t;", 1 },
        .{ "proc lifetest method=xx; time t;", 1 },
        .{ "proc lifetest conftype=xx; time t;", 1 },
        .{ "proc lifetest; time nosuch;", 1 },
        .{ "proc lifetest; time g;", 1 }, // character time
        .{ "proc lifetest; time t*g(0);", 1 }, // character censoring variable
        .{ "proc lifetest; time t*c;", 1 },
        .{ "proc lifetest; time t*c();", 1 },
        .{ "proc lifetest; time t*c(a);", 1 },
        .{ "proc lifetest; time t; strata;", 1 },
        .{ "proc lifetest; time t; strata nosuch;", 1 },
        .{ "proc lifetest; time t; freq g;", 1 },
        .{ "proc lifetest; time t; freq f / bogus;", 1 },
        .{ "proc lifetest; time t; weight g;", 1 },
        .{ "proc lifetest; time t; weight w w;", 1 },
        .{ "proc lifetest; time t; id;", 1 },
        .{ "proc lifetest; time t; id nosuch;", 1 },
        .{ "proc lifetest; time t; by nosuch;", 1 },
        .{ "proc lifetest; time t; bogus t;", 1 },
        .{ "proc lifetest; time t*c(0); strata g; by descending b;", 1 }, // not sorted descending
        .{ "proc lifetest method=lt; time t;", 2 },
        .{ "proc lifetest method=breslow; time t;", 2 },
        .{ "proc lifetest conftype=linear; time t;", 2 },
        .{ "proc lifetest outsurv=o; time t;", 2 },
        .{ "proc lifetest alphaqt=0.1; time t;", 2 },
        .{ "proc lifetest plots=none; time t;", 2 },
        .{ "proc lifetest timelist=1 2; time t;", 2 },
        .{ "proc lifetest; time t*c(0 to 2);", 2 },
        .{ "proc lifetest; time t; strata g / test=logrank;", 2 },
        .{ "proc lifetest; time t; strata n(1 2);", 2 },
        .{ "proc lifetest; time t; strata g g;", 2 },
        .{ "proc lifetest; time t; test w;", 2 },
        .{ "proc lifetest; time t; format g $1.;", 2 },
        .{ "proc lifetest; time t; time t;", 2 },
        .{ "proc lifetest; time t; strata g; strata g;", 2 },
        .{ "proc lifetest; time t; freq f; freq f;", 2 },
        .{ "proc lifetest; time t; weight w; weight w;", 2 },
        // Execution boundaries: valid roles whose results are not implemented.
        .{ "proc lifetest; time t*c(0);", 2 },
        .{ "proc lifetest; time t*c(0); strata n;", 2 },
        .{ "proc lifetest; time t*c(0); strata g n;", 2 },
        // BY, FREQ, WEIGHT, ID and MISSING each execute (corpus fixtures
        // stat_lifetest_{by,freq,weight,id,missing_level}); their
        // combinations and shapes without a SAS listing stay loud.
        .{ "proc lifetest; time t*c(0); strata g; freq f; id id;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; freq f; weight w;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; weight w; id id;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; id id g;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; id n;", 2 }, // numeric ID
        .{ "proc lifetest; time t*c(0); strata g; freq f / notruncate;", 2 }, // fractional FREQ
        .{ "proc lifetest; time t*c(0, 1); strata g;", 2 }, // every stratum fully censored
    }) |case| {
        const result = try fx.outcome(case[0]);
        std.testing.expectEqual(case[1], result.rc) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
        try expectEqual(@as(usize, 0), result.out.len);
    }
    // NOPRINT validates the declarations and produces no listing.
    const quiet = try fx.outcome("proc lifetest noprint; time t*c(0); strata g; freq f; by b;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
}

test "STAT-LIFETEST-001 empty input is a visible gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "none");
    _ = try ds.addColumn("t", .num);
    _ = try ds.addColumn("g", .char);
    try lib.put("none", ds);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, lifetest.run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc lifetest data=none; time t; strata g;", &d)));
    try expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-LIFETEST-001 observation selection for missing values FREQ WEIGHT and STRATA levels" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
    const Case = struct { source: []const u8, times: []const f64 };
    for ([_]Case{
        .{ .source = "proc lifetest; time t;", .times = &.{ 1, 2, 3, 4, 5, 6, 7, 8 } },
        .{ .source = "proc lifetest; time t*c(0);", .times = &.{ 1, 2, 4, 5, 6, 7, 8 } },
        .{ .source = "proc lifetest; time t*c(0); strata g;", .times = &.{ 1, 2, 5, 6, 7, 8 } },
        .{ .source = "proc lifetest; time t*c(0); strata n;", .times = &.{ 1, 2, 5, 6, 7, 8 } },
        .{ .source = "proc lifetest missing; time t*c(0); strata g;", .times = &.{ 1, 2, 4, 5, 6, 7, 8 } },
        .{ .source = "proc lifetest; time t*c(0); freq f;", .times = &.{ 1, 2, 4 } },
        .{ .source = "proc lifetest; time t*c(0); freq f / notruncate;", .times = &.{ 1, 2, 4, 5 } },
        .{ .source = "proc lifetest; time t*c(0); weight w;", .times = &.{ 1, 2, 4, 5 } },
        .{ .source = "proc lifetest; time t*c(0); id id;", .times = &.{ 1, 2, 4, 5, 6, 7, 8 } },
    }) |case| {
        const groups = try lifetest.plan(cx, try fx.spec(&d, case.source));
        try expectEqual(@as(usize, 1), groups.len);
        try expectEqual(@as(usize, 9), groups[0].read);
        try expectEqual(case.times.len, groups[0].obs.len);
        for (case.times, groups[0].obs) |time, o| try expectEqual(time, o.time);
    }
    // Censoring values and roles.
    const censored = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0);")))[0].obs;
    for ([_]bool{ true, false, true, true, false, true, true }, censored) |event, o| try expectEqual(event, o.event);
    for ((try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t;")))[0].obs) |o| try expect(o.event);
    const truncated = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0); freq f;")))[0].obs;
    try expectEqual(@as(f64, 2), truncated[0].freq);
    const exact = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0); freq f / notrunc;")))[0].obs;
    try expectEqual(@as(f64, 2.9), exact[0].freq);
    try expectEqual(@as(f64, 0.9), exact[3].freq);
    const weighted = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0); weight w;")))[0].obs;
    try expectEqual(@as(f64, 0.5), weighted[1].weight);
    // Levels ascend by value although B is met first; MISSING adds the
    // missing level, which sorts lowest.
    const by_group = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0); strata g;")))[0];
    try expectEqual(@as(usize, 2), by_group.levels.len);
    try std.testing.expectEqualStrings("A", by_group.levels[0][2].str);
    for ([_]usize{ 1, 0, 0, 1, 1, 0 }, by_group.obs) |stratum, o| try expectEqual(stratum, o.stratum);
    const with_missing = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest missing; time t*c(0); strata g;")))[0];
    try expectEqual(@as(usize, 3), with_missing.levels.len);
    try expectEqual(@as(usize, 0), with_missing.obs[2].stratum);
    const crossed = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest missing; time t*c(0); strata n g;")))[0];
    try expectEqual(@as(usize, 3), crossed.levels.len);
    try expect(std.math.isNan(crossed.levels[0][6].num));
    // BY boundaries: b=1 holds four rows (two usable), b=2 five.
    const groups = try lifetest.plan(cx, try fx.spec(&d, "proc lifetest; time t*c(0); by b;"));
    try expectEqual(@as(usize, 2), groups.len);
    try expectEqual(@as(usize, 4), groups[0].read);
    try expectEqual(@as(usize, 2), groups[0].obs.len);
    try expectEqual(@as(usize, 5), groups[1].read);
    try expectEqual(@as(usize, 5), groups[1].obs.len);
    try expect(!d.hasErrors());
}

fn close(expected: f64, actual: f64) !void {
    // Each expected value is an exact rational or elementary function of the
    // data; 1e-12 relative exceeds the accumulated rounding of the few dozen
    // floating-point operations involved by three orders of magnitude.
    try std.testing.expectApproxEqRel(expected, actual, 1e-12);
}

test "STAT-LIFETEST-001 product-limit quartiles mean and homogeneity match hand calculation" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(twoGroups);
    var d = diag.Diagnostics.init(fx.a());
    const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
    const sel = (try lifetest.plan(cx, try fx.spec(&d, "proc lifetest data=survival; time time*status(0); strata group;")))[0];
    try expectEqual(@as(usize, 10), sel.obs.len);
    var members: [2]std.ArrayList(lifetest.Obs) = .{ .empty, .empty };
    for (sel.obs) |o| try members[o.stratum].append(fx.a(), o);
    // Stratum A: risk sets 5, 4, 2 at event times 1, 2, 4.
    const first = try lifetest.productLimit(fx.a(), members[0].items);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 4 }, first.event_times);
    try std.testing.expectEqualSlices(f64, &.{ 5, 4, 2 }, first.at_risk);
    for ([_]f64{ 0.8, 0.6, 0.3 }, first.survival) |e, x| try close(e, x);
    for ([_]f64{ 0.8 * @sqrt(1.0 / 20.0), 0.6 * @sqrt(1.0 / 20.0 + 1.0 / 12.0), 0.3 * @sqrt(1.0 / 20.0 + 1.0 / 12.0 + 0.5) }, first.se) |e, x| try close(e, x.?);
    try expectEqual(@as(usize, 3), first.failed);
    try expectEqual(@as(usize, 5), first.rows.len); // one row per subject; the time-0 row is listing-only
    try expect(first.rows[2].censored and first.rows[2].time == 2 and !first.rows[1].censored); // event before tied censoring
    try expectEqual(@as(usize, 2), first.rows[2].left);
    try expect(first.last_censored and first.unverified == null and !first.tied_events);
    try expect(first.quartiles[0].estimate == null);
    try expectEqual(@as(?f64, 4), first.quartiles[1].estimate);
    try expectEqual(@as(?f64, 2), first.quartiles[2].estimate);
    try expectEqual(@as(?f64, 1), first.quartiles[2].lower);
    try expectEqual(@as(?f64, 4), first.quartiles[2].upper);
    try expect(first.quartiles[1].upper == null and first.quartiles[1].lower.? == 1);
    try close(3, first.mean); // 1*1 + 0.8*1 + 0.6*2
    try close(@sqrt(0.48), first.mean_se.?); // (3/2)*(2^2/20 + 1.2^2/12)
    // Stratum B: risk sets 4, 3, 1 at event times 3, 4, 7; survival reaches 0.
    const second = try lifetest.productLimit(fx.a(), members[1].items);
    for ([_]f64{ 0.75, 0.5 }, second.survival[0..2]) |e, x| try close(e, x);
    try expectEqual(@as(f64, 0), second.survival[2]);
    try expect(second.se[2] == null);
    try close(0.5 * @sqrt(1.0 / 12.0 + 1.0 / 6.0), second.se[1].?);
    // Plateaus exactly at 1-p average the bounding event times.
    try close(7, second.quartiles[0].estimate.?);
    try close(5.5, second.quartiles[1].estimate.?);
    try close(3.5, second.quartiles[2].estimate.?);
    for (second.quartiles) |q| try expect(q.lower.? == 3 and q.upper == null);
    try close(5.25, second.mean); // 3 + 0.75 + 0.5*3
    try close(@sqrt(1.5 * (2.25 * 2.25 / 12.0 + 1.5 * 1.5 / 6.0)), second.mean_se.?);
    try expect(!second.last_censored);
    // Pooled event times 1,2,3,4 with (n, nA, d, dA) = (10,5,1,1), (8,4,1,1),
    // (6,2,1,0), (5,2,2,1); time 7 has no A subject at risk.
    const h = try lifetest.homogeneity(fx.a(), sel.obs, 2);
    try close(13.0 / 15.0, h.logrank[0]);
    try close(-13.0 / 15.0, h.logrank[1]);
    try close(487.0 / 450.0, h.logrank_cov[0]);
    try close(-487.0 / 450.0, h.logrank_cov[1]);
    try close(8, h.wilcoxon[0]);
    try close(58, h.wilcoxon_cov[3]);
    try close(-58, h.wilcoxon_cov[2]);
    // Exponential model: 3 events in 14 and 3 in 21 time units, 6 in 35 pooled.
    try close(2 * (3 * @log(3.0 / 14.0) + 3 * @log(3.0 / 21.0) - 6 * @log(6.0 / 35.0)), h.lr);
}

test "STAT-LIFETEST-001 default stratified listing NOTABLE and all-censored product limit" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(twoGroups);
    const listing = try fx.outcome("proc lifetest data=survival; time time*status(0); strata group;");
    try expectEqual(@as(u8, 0), listing.rc);
    for ([_][]const u8{
        "Stratum 2: group = B\n",
        " 2.00000*           .           .           .      2         2   \n",
        " 7.00000            0      1.0000           .      3         0   \n",
        "     50     5.50000    LOGLOG        3.00000      .     \n",
        " 3.00000     0.69282\n",
        "  Total                      10       6           4       40.00\n",
        "A            0.86667      8.0000\n",
        "B          -58.0000       58.0000\n",
        "Log-Rank      0.6940       1      0.4048  \n",
        "Wilcoxon      1.1034       1      0.2935  \n",
        "-2Log(LR)     0.2449       1      0.6207  \n",
    }) |line| try expect(std.mem.indexOf(u8, listing.out, line) != null);
    try expectEqual(@as(usize, 2), std.mem.count(u8, listing.out, "Product-Limit Survival Estimates"));
    const short = try fx.outcome("proc lifetest data=survival notable; time time*status(0); strata group;");
    try expectEqual(@as(u8, 0), short.rc);
    try expectEqual(@as(usize, 0), std.mem.count(u8, short.out, "Product-Limit"));
    try expectEqual(@as(usize, 0), std.mem.count(u8, short.out, "marked survival times"));
    // NOTABLE drops each stratum's page entirely (SAS reference listing):
    // the output opens with the censoring summary.
    try expectEqual(@as(usize, 0), std.mem.count(u8, short.out, "Stratum 1:") + std.mem.count(u8, short.out, "Quartile Estimates") + std.mem.count(u8, short.out, "Mean"));
    try expect(std.mem.startsWith(u8, short.out, "\nThe LIFETEST Procedure\n\n    Summary of the Number of Censored and Uncensored Values\n"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, short.out, "The LIFETEST Procedure"));
    try expectEqual(@as(usize, 3), std.mem.count(u8, listing.out, "The LIFETEST Procedure"));
    try expect(std.mem.indexOf(u8, short.out, "Log-Rank      0.6940       1      0.4048  \n") != null);
    // A sample without events keeps the estimate at 1 and is flagged rather
    // than summarised.
    const censored = try lifetest.productLimit(fx.a(), &.{ .{ .time = 1, .event = false, .stratum = 0 }, .{ .time = 2, .event = false, .stratum = 0 } });
    try expectEqual(@as(usize, 0), censored.event_times.len + censored.failed);
    try expectEqual(@as(usize, 2), censored.rows.len);
    try expect(censored.unverified != null);
    // Tied events share one estimate, carried by the last tied row.
    const tied = try lifetest.productLimit(fx.a(), &.{ .{ .time = 1, .event = true, .stratum = 0 }, .{ .time = 1, .event = true, .stratum = 0 }, .{ .time = 2, .event = false, .stratum = 0 }, .{ .time = 3, .event = true, .stratum = 0 } });
    try expect(tied.tied_events and tied.rows[0].survival == null);
    try close(0.5, tied.rows[1].survival.?); // (4 - 2) / 4
}

// ---------------------------------------------------------------------------
// STAT-LIFETEST-002: generalised estimator and K-sample comparison checks.

fn ob(time: f64, event: bool, stratum: usize) lifetest.Obs {
    return .{ .time = time, .event = event, .stratum = stratum };
}

/// Three invented strata with tied events within and across strata.
/// Pooled event times 1, 2, 3, 4 with (n; n_k; d; d_k):
///   t=1: 9; 3,3,3; 2; 1,1,0     t=2: 7; 2,2,3; 3; 1,0,2
///   t=3: 4; 1,2,1; 1; 0,1,0     t=4: 2; 0,1,1; 1; 0,1,0
const three = [_]lifetest.Obs{
    ob(1, true, 0), ob(2, true, 0), ob(3, false, 0),
    ob(1, true, 1), ob(3, true, 1), ob(4, true, 1),
    ob(2, true, 2), ob(2, true, 2), ob(5, false, 2),
};

test "STAT-LIFETEST-002 three strata with ties match exact rational scores covariances and K-1 df tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try lifetest.homogeneity(a, &three, 3);
    // Observed minus expected d*n_k/n summed over the four event times.
    const u = [_]f64{ 19.0 / 84.0, 40.0 / 84.0, -59.0 / 84.0 };
    for (u, h.logrank) |e, x| try close(e, x);
    // Weighted by n = 9, 7, 4, 2: (3+1-1, 3-6+2+1, -6+5-1-1).
    try close(3, h.wilcoxon[0]);
    try std.testing.expectApproxEqAbs(@as(f64, 0), h.wilcoxon[1], 1e-12); // exact cancellation; absolute bound of a few ulps of the summands (<= 6)
    try close(-3, h.wilcoxon[2]);
    // d(n-d)/(n-1) = 7/4, 2, 1, 1 times (n_k/n)(delta - n_h/n).
    const v = [_]f64{
        7.0 / 18.0 + 20.0 / 49.0 + 3.0 / 16.0,  -7.0 / 36.0 - 8.0 / 49.0 - 1.0 / 8.0,              -7.0 / 36.0 - 12.0 / 49.0 - 1.0 / 16.0,
        -7.0 / 36.0 - 8.0 / 49.0 - 1.0 / 8.0,   7.0 / 18.0 + 20.0 / 49.0 + 1.0 / 4.0 + 1.0 / 4.0,  -7.0 / 36.0 - 12.0 / 49.0 - 1.0 / 8.0 - 1.0 / 4.0,
        -7.0 / 36.0 - 12.0 / 49.0 - 1.0 / 16.0, -7.0 / 36.0 - 12.0 / 49.0 - 1.0 / 8.0 - 1.0 / 4.0, 7.0 / 18.0 + 24.0 / 49.0 + 3.0 / 16.0 + 1.0 / 4.0,
    };
    for (v, h.logrank_cov) |e, x| try close(e, x);
    // Squared weights 81, 49, 16, 4.
    const w = [_]f64{ 54.5, -25.75, -28.75, -25.75, 56.5, -30.75, -28.75, -30.75, 59.5 };
    for (w, h.wilcoxon_cov) |e, x| try close(e, x);
    // Rank 2: the statistic equals the closed-form 2x2 quadratic form on any
    // two groups; the hand value uses groups 1 and 2.
    const lr = try lifetest.quadraticForm(a, h.logrank, h.logrank_cov, 3);
    try expectEqual(@as(usize, 2), lr.df);
    try close((u[0] * u[0] * v[4] - 2 * u[0] * u[1] * v[1] + u[1] * u[1] * v[0]) / (v[0] * v[4] - v[1] * v[1]), lr.chi);
    const wx = try lifetest.quadraticForm(a, h.wilcoxon, h.wilcoxon_cov, 3);
    try expectEqual(@as(usize, 2), wx.df);
    // 9 * 56.5 / (54.5 * 56.5 - 25.75^2); 1e-12 relative still exceeds the
    // rounding of the residual 0 score by three orders of magnitude.
    try close(508.5 / 2416.1875, wx.chi);
    // Exponential model: events 2, 3, 2 in 6, 8 and 9 time units.
    try close(2 * 7 * @log(23.0 / 7.0) - 2 * (2 * @log(6.0 / 2.0) + 3 * @log(8.0 / 3.0) + 2 * @log(9.0 / 2.0)), h.lr);

    // Relabelling the strata permutes scores and leaves the statistics alone.
    var relabelled = three;
    const map = [_]usize{ 2, 0, 1 };
    for (&relabelled) |*o| o.stratum = map[o.stratum];
    const hp = try lifetest.homogeneity(a, &relabelled, 3);
    for (0..3) |g| {
        try close(h.logrank[g], hp.logrank[map[g]]);
        for (0..3) |l| try close(h.wilcoxon_cov[g * 3 + l], hp.wilcoxon_cov[map[g] * 3 + map[l]]);
    }
    const lrp = try lifetest.quadraticForm(a, hp.logrank, hp.logrank_cov, 3);
    try expectEqual(@as(usize, 2), lrp.df);
    // Different elimination order: agreement to 1e-9 follows from the
    // condition number of the 2x2 blocks (below 10) times f64 rounding.
    try std.testing.expectApproxEqRel(lr.chi, lrp.chi, 1e-9);
    try close(h.lr, hp.lr);

    // A stratum never at risk at an event time has a zero covariance row: the
    // rank, and so the degrees of freedom, drops to that of the other strata.
    var with_idle: [10]lifetest.Obs = undefined;
    @memcpy(with_idle[0..9], &three);
    with_idle[9] = ob(0.5, false, 3);
    const hi = try lifetest.homogeneity(a, &with_idle, 4);
    try expectEqual(@as(f64, 0), hi.logrank[3]);
    try expectEqual(@as(f64, 0), hi.logrank_cov[15]);
    const lri = try lifetest.quadraticForm(a, hi.logrank, hi.logrank_cov, 4);
    try expectEqual(@as(usize, 2), lri.df);
    try close(lr.chi, lri.chi);

    // Tied events in one stratum: S = 1/3 after 2 of 3 fail at t=2.
    const tied = try lifetest.productLimit(a, three[6..9]);
    try expect(tied.tied_events);
    try close(1.0 / 3.0, tied.survival[0]);
    try close(1.0 / 3.0 * @sqrt(2.0 / 3.0), tied.se[0].?); // Greenwood d/(n(n-d)) = 2/(3*1)
}

/// Published sample: the rat carcinogen trial of the SAS/STAT 15.4 LIFETEST
/// "Getting Started" section (Days, Status; 0 = censored).
const drug_x = [_][2]f64{ .{ 179, 1 }, .{ 378, 0 }, .{ 256, 1 }, .{ 355, 1 }, .{ 262, 1 }, .{ 319, 1 }, .{ 256, 1 }, .{ 256, 1 }, .{ 255, 1 }, .{ 171, 1 }, .{ 224, 0 }, .{ 325, 1 }, .{ 225, 1 }, .{ 325, 1 }, .{ 287, 1 }, .{ 217, 1 }, .{ 319, 1 }, .{ 255, 1 }, .{ 264, 1 }, .{ 256, 1 } };
const placebo = [_][2]f64{ .{ 237, 0 }, .{ 291, 1 }, .{ 156, 1 }, .{ 323, 1 }, .{ 270, 1 }, .{ 253, 1 }, .{ 257, 1 }, .{ 206, 1 }, .{ 242, 1 }, .{ 206, 1 }, .{ 157, 1 }, .{ 237, 1 }, .{ 249, 1 }, .{ 211, 1 }, .{ 180, 1 }, .{ 229, 1 }, .{ 226, 1 }, .{ 234, 1 }, .{ 268, 0 }, .{ 209, 1 } };

/// A published figure rounded to `decimals` places bounds the true value to
/// half a unit of the last printed place.
fn printed(expected: f64, actual: f64, decimals: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.5 * std.math.pow(f64, 10, -decimals) * (1 + 1e-9));
}

test "STAT-LIFETEST-002 published two-treatment sample reproduces the documented estimates and tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var all: std.ArrayList(lifetest.Obs) = .empty;
    for (drug_x) |r| try all.append(a, ob(r[0], r[1] == 1, 0));
    for (placebo) |r| try all.append(a, ob(r[0], r[1] == 1, 1));
    const x = try lifetest.productLimit(a, all.items[0..20]);
    try std.testing.expectEqualSlices(f64, &.{ 171, 179, 217, 225, 255, 256, 262, 264, 287, 319, 325, 355 }, x.event_times);
    for ([_]f64{ 0.95, 0.9, 0.85, 0.7969, 0.6906, 0.4781, 0.425, 0.3719, 0.3187, 0.2125, 0.1062, 0.0531 }, x.survival) |e, s| try printed(e, s, 4);
    for ([_]f64{ 0.0487, 0.0671, 0.0798, 0.0908, 0.1053, 0.1146, 0.1135, 0.1111, 0.1071, 0.0942, 0.0710, 0.0517 }, x.se) |e, s| try printed(e, s.?, 4);
    try expectEqual(@as(usize, 18), x.failed);
    try expect(x.last_censored and x.tied_events and x.unverified == null);
    // Row counters of the tied block at 256 (Figure 77.1): failed 7..10,
    // left 12..9; these are the 8th to 11th rows after the time-0 line.
    try expect(x.rows[7].time == 256 and x.rows[7].survival == null and x.rows[7].failed == 7 and x.rows[7].left == 12);
    try expect(x.rows[10].time == 256 and x.rows[10].survival != null and x.rows[10].failed == 10 and x.rows[10].left == 9);
    try expect(x.rows[3].censored and x.rows[3].time == 224 and x.rows[3].failed == 3 and x.rows[3].left == 16);
    for ([_][3]f64{ .{ 319, 256, 355 }, .{ 256, 255, 319 }, .{ 255, 171, 256 } }, x.quartiles) |e, q| {
        try expectEqual(@as(?f64, e[0]), q.estimate);
        try expectEqual(@as(?f64, e[1]), q.lower);
        try expectEqual(@as(?f64, e[2]), q.upper);
    }
    try printed(271.131, x.mean, 3);
    try printed(11.877, x.mean_se.?, 3);

    const p = try lifetest.productLimit(a, all.items[20..40]);
    for ([_]f64{ 0.95, 0.9, 0.85, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5, 0.45, 0.3938, 0.3375, 0.2813, 0.225, 0.15, 0.075 }, p.survival[0..16]) |e, s| try printed(e, s, 4);
    try expectEqual(@as(f64, 0), p.survival[16]);
    try expect(p.se[16] == null and !p.last_censored);
    for ([_]f64{ 0.0487, 0.0671, 0.0798, 0.0968, 0.1025, 0.1067, 0.1095, 0.1112, 0.1118, 0.1112, 0.1106, 0.1082, 0.1038, 0.0971, 0.0891, 0.0693 }, p.se[0..16]) |e, s| try printed(e, s.?, 4);
    // The upper limit of the 75th percentile is deliberately not asserted:
    // the guide prints 323 (the event time where the estimate reaches 0)
    // while the SAS listing behind the default stratified fixture leaves the
    // limit missing in the same configuration.
    for ([_][2]f64{ .{ 257, 237 }, .{ 235.5, 206 }, .{ 207.5, 156 } }, p.quartiles) |e, q| {
        try expectEqual(@as(?f64, e[0]), q.estimate);
        try expectEqual(@as(?f64, e[1]), q.lower);
    }
    try expectEqual(@as(?f64, 253), p.quartiles[1].upper);
    try expectEqual(@as(?f64, 229), p.quartiles[2].upper);
    try printed(235.156, p.mean, 3);
    try printed(10.211, p.mean_se.?, 3);

    const h = try lifetest.homogeneity(a, all.items, 2);
    const lr = try lifetest.quadraticForm(a, h.logrank, h.logrank_cov, 2);
    const wx = try lifetest.quadraticForm(a, h.wilcoxon, h.wilcoxon_cov, 2);
    try expectEqual(@as(usize, 1), lr.df);
    try expectEqual(@as(usize, 1), wx.df);
    try printed(5.6485, lr.chi, 4);
    try printed(5.0312, wx.chi, 4);
    try printed(0.1983, h.lr, 4);
    try printed(0.0175, lifetest.chiProbability(lr.chi, 1), 4);
    try printed(0.0249, lifetest.chiProbability(wx.chi, 1), 4);
    try printed(0.6561, lifetest.chiProbability(h.lr, 1), 4);
}

/// Invented two-stratum data with tied events in each stratum.
fn tiedGroups(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "tied");
    _ = try ds.addColumn("time", .num);
    _ = try ds.addColumn("status", .num);
    _ = try ds.addColumn("group", .char);
    const rows = [_]struct { f64, f64, []const u8 }{ .{ 1, 1, "A" }, .{ 1, 1, "A" }, .{ 3, 1, "A" }, .{ 4, 1, "A" }, .{ 5, 0, "A" }, .{ 2, 1, "B" }, .{ 2, 1, "B" }, .{ 4, 1, "B" }, .{ 6, 1, "B" }, .{ 7, 0, "B" } };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = r[2] } });
    return ds;
}

test "STAT-LIFETEST-002 tied event rows in the listing and still-unsupported shapes stay loud" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(tiedGroups);
    const listing = try fx.outcome("proc lifetest data=tied; time time*status(0); strata group;");
    try expectEqual(@as(u8, 0), listing.rc);
    // Stratum A: S(1) = 3/5 with Greenwood 2/(5*3); only the last tied row
    // carries the estimate (Figure 77.1 of the guide shows the same rows).
    for ([_][]const u8{
        " 1.00000            .           .           .      1         4   \n",
        " 1.00000       0.6000      0.4000      0.2191      2         3   \n",
        " 2.00000            .           .           .      1         4   \n",
        " 2.00000       0.6000      0.4000      0.2191      2         3   \n",
    }) |line| try expect(std.mem.indexOf(u8, listing.out, line) != null);
    // No STRATA, numeric STRATA and several STRATA variables have no listing
    // reference and remain visible gaps.
    for ([_][]const u8{
        "proc lifetest data=tied; time time*status(0);",
        "proc lifetest data=tied; time time*status(0); strata status;",
        "proc lifetest data=tied; time time*status(0); strata group status;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 2), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
}

// ---- STAT-LIFETEST-003: life table, Breslow and Fleming-Harrington ----
const lt = @import("lifetest_lt.zig");
const survival_data = @import("survival_data.zig");

fn near(expected: f64, actual: ?f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual.?, 1e-12);
}

/// Columns t c f g. Ten usable units (FREQ) plus two rows that are deleted.
fn grouped(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "grouped");
    for ([_][]const u8{ "t", "c", "f" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("g", .char);
    const rows = [_]struct { f64, f64, f64 }{
        .{ 0.5, 1, 2 }, .{ 1, 0, 2 }, .{ 2, 1, 1 }, .{ 3, 1, 2 },
        .{ 4, 1, 1 },   .{ 4, 0, 1 }, .{ 9, 0, 1 },
        .{ 5, 1, 0 }, // zero frequency: deleted
        .{ nan, 1, 1 }, // missing time: deleted
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .str = "A" } });
    return ds;
}

test "STAT-LIFETEST-003 life table matches hand calculation with endpoint ties and coincident censoring" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Intervals [0,2) [2,4) [4,inf). The event at 2 belongs to [2,4); an
    // event and a censoring coincide at 4.
    const obs = [_]lifetest.Obs{
        .{ .time = 0.5, .event = true, .freq = 2 }, .{ .time = 1, .event = false, .freq = 2 },
        .{ .time = 2, .event = true },              .{ .time = 3, .event = true, .freq = 2 },
        .{ .time = 4, .event = true },              .{ .time = 4, .event = false },
        .{ .time = 9, .event = false },
    };
    const table = try lt.lifeTable(a, &obs, &.{ 0, 2, 4 });
    try expect(table.unverified == null);
    try expectEqual(@as(f64, 10), table.total);
    try expectEqual(@as(f64, 6), table.failed);
    try expectEqual(@as(f64, 4), table.censored);
    const r = table.rows;
    try expectEqual(@as(usize, 3), r.len);
    // n = 10, 6, 3; d = 2, 3, 1; w = 2, 0, 2; n' = 9, 6, 2.
    try std.testing.expectEqualSlices(f64, &.{ 10, 6, 3 }, &.{ r[0].entering, r[1].entering, r[2].entering });
    try std.testing.expectEqualSlices(f64, &.{ 2, 3, 1 }, &.{ r[0].failed, r[1].failed, r[2].failed });
    try std.testing.expectEqualSlices(f64, &.{ 2, 0, 2 }, &.{ r[0].censored, r[1].censored, r[2].censored });
    try std.testing.expectEqualSlices(f64, &.{ 9, 6, 2 }, &.{ r[0].effective, r[1].effective, r[2].effective });
    // q = 2/9, 1/2, 1/2 with se sqrt(q p / n').
    try near(2.0 / 9.0, r[0].q);
    try near(0.5, r[1].q);
    try near(0.5, r[2].q);
    try near(@sqrt(14.0) / 27.0, r[0].q_se);
    try near(@sqrt(0.25 / 6.0), r[1].q_se);
    try near(@sqrt(0.25 / 2.0), r[2].q_se);
    // S = 1, 7/9, 7/18; se = S sqrt(sum q/(n' p)): terms 2/63 and 1/6.
    try near(1, r[0].survival);
    try near(7.0 / 9.0, r[1].survival);
    try near(7.0 / 18.0, r[2].survival);
    try near(0, r[0].survival_se);
    try near(7.0 / 9.0 * @sqrt(2.0 / 63.0), r[1].survival_se);
    try near(7.0 / 18.0 * @sqrt(2.0 / 63.0 + 1.0 / 6.0), r[2].survival_se);
    // f = S q / b; se = f sqrt(sum + p/(n' q)).
    try near(1.0 / 9.0, r[0].pdf);
    try near(1.0 / 9.0 * @sqrt(7.0 / 18.0), r[0].pdf_se);
    try near(7.0 / 36.0, r[1].pdf);
    try near(7.0 / 36.0 * @sqrt(2.0 / 63.0 + 1.0 / 6.0), r[1].pdf_se);
    // h = 2q/(b(1+p)); se = h sqrt((1-(bh/2)^2)/(n' q)).
    try near(1.0 / 8.0, r[0].hazard);
    try near(1.0 / 8.0 * @sqrt(63.0 / 64.0 / 2.0), r[0].hazard_se);
    try near(1.0 / 3.0, r[1].hazard);
    try near(1.0 / 3.0 * @sqrt(8.0 / 9.0 / 3.0), r[1].hazard_se);
    // The open interval has no width: density and hazard are undefined.
    try expect(r[2].upper == null and r[2].pdf == null and r[2].pdf_se == null and r[2].hazard == null and r[2].hazard_se == null);
    // Median residual lifetime at 0: S(2) = 7/9 >= 1/2 > S(4) = 7/18, so
    // M = 2 - 0 + 2 (7/9 - 1/2)/(7/9 - 7/18) = 24/7, se = 1/(2 (7/36) sqrt 9) = 6/7.
    try near(24.0 / 7.0, r[0].median);
    try near(6.0 / 7.0, r[0].median_se);
    // At 2 the half value 7/18 is not strictly above S(4); no later interval.
    try expect(r[1].median == null and r[1].median_se == null and r[2].median == null);
}

test "STAT-LIFETEST-003 entirely censored and degenerate life tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const censored = [_]lifetest.Obs{ .{ .time = 1, .event = false, .freq = 3 }, .{ .time = 2, .event = false }, .{ .time = 5, .event = false, .freq = 2 } };
    const table = try lt.lifeTable(a, &censored, &.{ 0, 2, 4 });
    try expectEqual(@as(f64, 6), table.total);
    try expectEqual(@as(f64, 0), table.failed);
    // n' = 6 - 3/2, 3 - 1/2, 2 - 2/2; no failure anywhere.
    try std.testing.expectEqualSlices(f64, &.{ 4.5, 2.5, 1 }, &.{ table.rows[0].effective, table.rows[1].effective, table.rows[2].effective });
    for (table.rows) |r| {
        try near(0, r.q);
        try near(0, r.q_se);
        try near(1, r.survival);
        try near(0, r.survival_se);
        // The standard errors divide by q = 0 and the median is never bracketed.
        try expect(r.pdf_se == null and r.hazard_se == null and r.median == null);
    }
    try near(0, table.rows[0].pdf);
    try near(0, table.rows[0].hazard);
    // Every unit of an interval fails: the survival estimate is 0 afterwards
    // and its standard error (division by p = 0) is undefined, not 0.
    const all = [_]lifetest.Obs{ .{ .time = 1, .event = true, .freq = 2 }, .{ .time = 3, .event = true } };
    const dead = try lt.lifeTable(a, &all, &.{ 0, 2, 4 });
    try near(2.0 / 3.0, dead.rows[0].q);
    try near(1, dead.rows[1].q);
    try near(0, dead.rows[2].survival);
    try expect(dead.rows[2].survival_se == null);
    // No unit enters the last interval: flagged, not silently estimated.
    try expect(dead.unverified != null and dead.rows[2].q == null);
    // A time below the first interval is flagged.
    try expect((try lt.lifeTable(a, &.{.{ .time = 1, .event = true }}, &.{ 2, 4 })).unverified != null);
}

test "STAT-LIFETEST-003 default interval width rule" {
    // c = log10(max/n), b = floor(c), d = 10^(c-b): 2 if d <= 2, 5 if d <= 5, else 10.
    try near(2, lt.defaultWidth(15.5, 10)); // d = 1.55
    try near(5, lt.defaultWidth(40, 10)); // d = 4
    try near(10, lt.defaultWidth(70, 10)); // d = 7
    try near(2, lt.defaultWidth(20, 10)); // d = 2 exactly
    try near(5, lt.defaultWidth(50, 10)); // d = 5 exactly
    try near(0.05, lt.defaultWidth(0.3, 10)); // b = -2, d = 3
    try near(200, lt.defaultWidth(600, 4)); // b = 2, d = 1.5
}

test "STAT-LIFETEST-003 Breslow and Fleming-Harrington estimates match hand calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Two tied events at 1 (Y = 5), censoring at 2, an event tied with a
    // censoring at 3 (Y = 2), censoring only afterwards.
    const obs = [_]lifetest.Obs{ .{ .time = 1, .event = true }, .{ .time = 1, .event = true }, .{ .time = 2, .event = false }, .{ .time = 3, .event = true }, .{ .time = 3, .event = false } };
    const risk = try survival_data.riskTable(a, &obs, 0);
    const b = try lt.breslow(a, risk);
    try expectEqual(@as(usize, 2), b.len);
    try expectEqual(@as(f64, 1), b[0].time);
    try expectEqual(@as(f64, 3), b[1].time);
    try near(@exp(-2.0 / 5.0), b[0].survival);
    try near(@exp(-(2.0 / 5.0 + 1.0 / 2.0)), b[1].survival);
    const fh = (try lt.flemingHarrington(a, risk)).?;
    try expectEqual(@as(usize, 2), fh.len);
    try near(@exp(-(1.0 / 5.0 + 1.0 / 4.0)), fh[0].survival);
    try near(@exp(-(1.0 / 5.0 + 1.0 / 4.0 + 1.0 / 2.0)), fh[1].survival);
    // Without ties the two estimates coincide.
    const plain = [_]lifetest.Obs{ .{ .time = 1, .event = true }, .{ .time = 2, .event = true }, .{ .time = 4, .event = false } };
    const risk2 = try survival_data.riskTable(a, &plain, 0);
    const b2 = try lt.breslow(a, risk2);
    const fh2 = (try lt.flemingHarrington(a, risk2)).?;
    try near(@exp(-(1.0 / 3.0 + 1.0 / 2.0)), b2[1].survival);
    try near(b2[1].survival, fh2[1].survival);
    // Entirely censored: no event time, no estimate rows.
    const none = [_]lifetest.Obs{ .{ .time = 1, .event = false }, .{ .time = 2, .event = false } };
    try expectEqual(@as(usize, 0), (try lt.breslow(a, try survival_data.riskTable(a, &none, 0))).len);
    // Noninteger frequencies: Fleming-Harrington cannot be computed.
    const frac = [_]lifetest.Obs{ .{ .time = 1, .event = true, .freq = 1.5 }, .{ .time = 2, .event = false } };
    try expect((try lt.flemingHarrington(a, try survival_data.riskTable(a, &frac, 0))) == null);
}

test "STAT-LIFETEST-003 METHOD INTERVALS WIDTH NINTERVAL and TIME declarations" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(grouped);
    var d = diag.Diagnostics.init(fx.a());
    try expectEqual(lifetest.Method.km, (try fx.spec(&d, "proc lifetest; time t*c(0);")).method);
    for ([_][]const u8{ "lt", "LIFE", "act" }) |m| {
        const s = try fx.spec(&d, try std.fmt.allocPrint(fx.a(), "proc lifetest method={s} intervals=(0 to 15 by 1); time t*c(0);", .{m}));
        try expectEqual(lifetest.Method.lt, s.method);
        try expectEqual(@as(usize, 16), s.intervals.?.len);
        try expectEqual(@as(f64, 15), s.intervals.?[15]);
    }
    // The first interval always starts at 0; lists, commas and ranges mix.
    try std.testing.expectEqualSlices(f64, &.{ 0, 5, 10, 20, 30 }, (try fx.spec(&d, "proc lifetest method=lt intervals=5,10 to 30 by 10; time t;")).intervals.?);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 3, 5, 7 }, (try fx.spec(&d, "proc lifetest intervals=7 1 3 5 3 method=lt; time t;")).intervals.?);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 2, 3 }, (try fx.spec(&d, "proc lifetest method=lt intervals=1 to 3; time t;")).intervals.?);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0.5, 1, 1.5 }, (try fx.spec(&d, "proc lifetest method=lt intervals=(0.5 to 1.5 by 0.5); time t;")).intervals.?);
    const w = try fx.spec(&d, "proc lifetest method=lt width=2 ninterval=4; time t;");
    try expect(w.width.? == 2 and w.ninterval.? == 4 and w.intervals == null);
    try expect(!d.hasErrors());
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc lifetest method=lt intervals=(-1 2); time t;", 1 },
        .{ "proc lifetest method=lt intervals=(1 to 5 by 0); time t;", 1 },
        .{ "proc lifetest method=lt intervals=(1 2; time t;", 1 },
        .{ "proc lifetest method=lt intervals=; time t;", 1 },
        .{ "proc lifetest method=lt width=0; time t;", 1 },
        .{ "proc lifetest method=lt ninterval=x; time t;", 1 },
        .{ "proc lifetest; time t*c(0) / bogus;", 1 },
        // Valid SAS that stays a visible gap.
        .{ "proc lifetest method=breslow; time t*c(0);", 2 },
        .{ "proc lifetest method=fh; time t*c(0);", 2 },
        .{ "proc lifetest intervals=(0 to 4 by 2); time t*c(0); strata g;", 2 }, // display thinning with KM
        .{ "proc lifetest width=2; time t*c(0); strata g;", 2 },
        .{ "proc lifetest ninterval=3; time t*c(0); strata g;", 2 },
        .{ "proc lifetest; time t*c(0) / failcode=1;", 2 },
        .{ "proc lifetest; time t*c(0) / eventcode;", 2 },
        .{ "proc lifetest method=lt; time t*c(0); freq f;", 2 }, // default intervals
        .{ "proc lifetest method=lt width=2; time t*c(0); freq f;", 2 },
        .{ "proc lifetest method=lt ninterval=3; time t*c(0); freq f;", 2 },
        .{ "proc lifetest method=lt intervals=(0 to 4 by 2); time t*c(0); strata g;", 2 },
        .{ "proc lifetest method=lt intervals=(0 to 4 by 2) notable; time t*c(0);", 2 },
        .{ "proc lifetest method=lt intervals=(0 to 4 by 2) plots=(s); time t*c(0);", 2 },
        // Small-sample standard errors (>= 0.1) and noninteger endpoints
        // have no SAS display reference: no partial listing.
        .{ "proc lifetest method=lt intervals=(0 to 4 by 2); time t*c(0); freq f;", 2 },
        .{ "proc lifetest method=lt intervals=(0.5 4); time t*c(0); freq f;", 2 },
    }) |case| {
        const result = try fx.outcome(case[0]);
        std.testing.expectEqual(case[1], result.rc) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
        try expectEqual(@as(usize, 0), result.out.len);
    }
    // NOPRINT validates the life-table request and prints nothing.
    const quiet = try fx.outcome("proc lifetest method=lt intervals=(0 to 4 by 2) noprint; time t*c(0); freq f;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
}

/// Published guide sample (SAS/STAT 15.4 Example 77.3): yearly failures and
/// withdrawals, expanded as the example's DATA step does (Years = k + 0.5).
fn angina(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "males");
    for ([_][]const u8{ "years", "censored", "freq" }) |name| _ = try ds.addColumn(name, .num);
    const counts = [_][2]f64{ .{ 456, 0 }, .{ 226, 39 }, .{ 152, 22 }, .{ 171, 23 }, .{ 135, 24 }, .{ 125, 107 }, .{ 83, 133 }, .{ 74, 102 }, .{ 51, 68 }, .{ 42, 64 }, .{ 43, 45 }, .{ 34, 53 }, .{ 18, 33 }, .{ 9, 27 }, .{ 6, 23 }, .{ 0, 30 } };
    for (counts, 0..) |c, k| {
        const years = @as(f64, @floatFromInt(k)) + 0.5;
        try ds.appendRow(&.{ .{ .num = years }, .{ .num = 0 }, .{ .num = c[0] } });
        try ds.appendRow(&.{ .{ .num = years }, .{ .num = 1 }, .{ .num = c[1] } });
    }
    return ds;
}

test "STAT-LIFETEST-003 life-table listing layout for the published sample matches the SAS listing lines" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(angina);
    const listing = try fx.outcome("proc lifetest data=males method=lt intervals=(0 to 15 by 1); time years*censored(1); freq freq;");
    try expectEqual(@as(u8, 0), listing.rc);
    // Lines copied from the SAS reference listing of the example.
    for ([_][]const u8{
        "\nThe LIFETEST Procedure\n\n                                                     Life Table Survival Estimates\n",
        " [Lower,     Upper)   Failed   Censored      Size     of Failure        Error     Survival   Failure     Error     Lifetime    Error\n",
        "       0          1     456         0      2418.0        0.1886       0.00796       1.0000          0          0     5.3313     0.1749\n",
        "       4          5     135        24      1317.0        0.1025       0.00836       0.5786     0.4214     0.0101     6.2185     0.1853\n",
        "      10         11      43        45       298.5        0.1441        0.0203       0.2987     0.7013     0.0109     4.6888     0.4183\n",
        "      11         12      34        53       206.5        0.1646        0.0258       0.2557     0.7443     0.0111          .          .\n",
        "      15          .       0        30        15.0             0             0       0.1429     0.8571     0.0133          .          .\n",
        " [Lower,     Upper)     PDF       Error      Hazard     Error\n",
        "       0          1     0.1886    0.00796   0.208219   0.009698\n",
        "       6          7     0.0439    0.00469        0.1   0.010963\n",
        "      12         13     0.0297    0.00668   0.149378    0.03511\n",
        "      15          .          .          .          .          .\n",
        "   Total  Failed    Censored    Censored\n\n    2418    1625         793       32.80\n",
        "\nNOTE: 2 observations with invalid time, censoring, or frequency values were deleted.\n",
    }) |line| std.testing.expect(std.mem.indexOf(u8, listing.out, line) != null) catch |err| {
        std.debug.print("missing: {s}\n", .{line});
        return err;
    };
}

test "STAT-LIFETEST-001 WEIGHT kernels FREQ replication and final-plateau quartile match hand calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tight = struct {
        fn f(want: f64, got: f64) !void {
            try std.testing.expectApproxEqAbs(want, got, 1e-12 * @max(1, @abs(want)));
        }
    }.f;
    // Invented weighted sample (corpus stat_lifetest_weight): stratum 0 and 1.
    const obs = [_]lifetest.Obs{
        .{ .time = 1, .event = true, .weight = 1.5 },              .{ .time = 2, .event = false, .weight = 1 },
        .{ .time = 2, .event = true, .weight = 2 },                .{ .time = 4, .event = true, .weight = 0.5 },
        .{ .time = 5, .event = false, .weight = 1 },               .{ .time = 1, .event = false, .stratum = 1, .weight = 1 },
        .{ .time = 3, .event = true, .stratum = 1, .weight = 1 },  .{ .time = 4, .event = true, .stratum = 1, .weight = 2.5 },
        .{ .time = 6, .event = false, .stratum = 1, .weight = 1 }, .{ .time = 7, .event = true, .stratum = 1, .weight = 1 },
    };
    // AKME, physical p.5673. At t=1: Y=6, d=1.5, sum w^2 = 8.5, M = 36/8.5.
    const st = try lifetest.productLimitWeighted(a, obs[0..5]);
    try tight(0.75, st.survival[0]);
    const v1 = 0.25 / ((36.0 / 8.5) * 0.75);
    try tight(0.75 * @sqrt(v1), st.se[0].?);
    // At t=2: Y = 4.5, d = 2, sum w^2 = 6.25, M = 4.5^2/6.25.
    const s2 = 0.75 * (1 - 2.0 / 4.5);
    try tight(s2, st.survival[1]);
    const v2 = (2.0 / 4.5) / ((4.5 * 4.5 / 6.25) * (1 - 2.0 / 4.5));
    try tight(s2 * @sqrt(v1 + v2), st.se[1].?);
    // Restricted mean 1 + 0.75 + 2 s2 = 31/12; weighted failed/left columns.
    try tight(31.0 / 12.0, st.mean);
    try tight(3.5, st.rows[1].failed_w);
    try tight(2.5, st.rows[1].left_w);
    // Weighted log-rank and Wilcoxon (physical p.5682) by hand over the four
    // distinct event times 1, 2, 3, 4, 7 (exact rational sum 991/700).
    const h = try lifetest.weightedHomogeneity(a, &obs, 2);
    try tight(991.0 / 700.0, h.logrank[0]);
    try tight(-991.0 / 700.0, h.logrank[1]);
    try tight(17.75, h.wilcoxon[0]);
    try tight(h.logrank_cov[0], -h.logrank_cov[1]);
    try tight(1.501498511904762, h.logrank_cov[0]);
    try tight(142.79270833333334, h.wilcoxon_cov[0]);
    // FREQ replicates: a frequency-3 event equals three unit events.
    const freq = [_]lifetest.Obs{ .{ .time = 1, .event = true }, .{ .time = 2, .event = true, .freq = 3 }, .{ .time = 3, .event = false } };
    const unit = [_]lifetest.Obs{ .{ .time = 1, .event = true }, .{ .time = 2, .event = true }, .{ .time = 2, .event = true }, .{ .time = 2, .event = true }, .{ .time = 3, .event = false } };
    const fs = try lifetest.productLimit(a, &freq);
    const us = try lifetest.productLimit(a, &unit);
    try expectEqual(@as(usize, 5), fs.total);
    try expectEqual(@as(usize, 3), fs.rows.len);
    try expectEqual(@as(usize, 4), fs.rows[1].failed);
    try std.testing.expectEqualSlices(f64, us.survival, fs.survival);
    try tight(us.mean_se.?, fs.mean_se.?);
    // Survival equal to 1-p on the plateau after the last event time (the
    // last observation censored): the estimate is missing (SAS listing).
    const plateau = [_]lifetest.Obs{ .{ .time = 1, .event = true }, .{ .time = 2, .event = true }, .{ .time = 4, .event = true }, .{ .time = 5, .event = false } };
    const ps = try lifetest.productLimit(a, &plateau);
    try expect(ps.unverified == null);
    try expectEqual(@as(?f64, null), ps.quartiles[0].estimate);
    try tight(1.5, ps.quartiles[2].estimate.?);
}
