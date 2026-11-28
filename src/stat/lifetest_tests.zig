//! STAT-LIFETEST-001 permanent checks: declarations, roles, observation
//! selection, BY boundaries, execution boundaries, and the hand-derived
//! product-limit and homogeneity numbers behind the default stratified listing.
//! All data are invented.
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
        .{ "proc lifetest missing; time t*c(0); strata g;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; by b;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; freq f;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; weight w;", 2 },
        .{ "proc lifetest; time t*c(0); strata g; id id;", 2 },
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
