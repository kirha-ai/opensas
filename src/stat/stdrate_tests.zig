//! STAT-STDRATE-001 permanent checks: declarations, variable roles,
//! observation selection, BY boundaries, execution boundaries, and the
//! hand-derived direct rate standardization behind the default listing.
//! Data are invented.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const by = @import("by_groups.zig");
const stdrate = @import("stdrate.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// study: age event total grp r b n; reference: age total event n.
fn pair(a: A, lib: *Library) !void {
    const study = try a.create(Dataset);
    study.* = Dataset.init(a, "study");
    _ = try study.addColumn("age", .char);
    _ = try study.addColumn("event", .num);
    _ = try study.addColumn("total", .num);
    _ = try study.addColumn("grp", .char);
    for ([_][]const u8{ "r", "b", "n" }) |name| _ = try study.addColumn(name, .num);
    try study.appendRow(&.{ .{ .str = "young" }, .{ .num = 10 }, .{ .num = 1000 }, .{ .str = "A" }, .{ .num = 0.01 }, .{ .num = 2 }, .{ .num = 1 } });
    try study.appendRow(&.{ .{ .str = "old" }, .{ .num = 30 }, .{ .num = 1500 }, .{ .str = "A" }, .{ .num = 0.02 }, .{ .num = 1 }, .{ .num = 2 } });
    try lib.put(study.name, study);
    const ref = try a.create(Dataset);
    ref.* = Dataset.init(a, "reference");
    _ = try ref.addColumn("age", .char);
    _ = try ref.addColumn("total", .num);
    _ = try ref.addColumn("event", .num);
    _ = try ref.addColumn("n", .num);
    try ref.appendRow(&.{ .{ .str = "young" }, .{ .num = 20000 }, .{ .num = 5 }, .{ .num = 1 } });
    try ref.appendRow(&.{ .{ .str = "old" }, .{ .num = 10000 }, .{ .num = 7 }, .{ .num = 2 } });
    try lib.put(ref.name, ref);
    // A reference without the study's STRATA variable `b`, and an empty study.
    const none = try a.create(Dataset);
    none.* = Dataset.init(a, "none");
    _ = try none.addColumn("age", .char);
    _ = try none.addColumn("event", .num);
    _ = try none.addColumn("total", .num);
    try lib.put(none.name, none);
}

/// cohort: n event total; standard: n total. Row comments name the rule.
fn missings(a: A, lib: *Library) !void {
    const study = try a.create(Dataset);
    study.* = Dataset.init(a, "cohort");
    for ([_][]const u8{ "n", "event", "total" }) |name| _ = try study.addColumn(name, .num);
    for ([_][3]f64{
        .{ 2, 30, 3000 },
        .{ nan, 5, 500 }, // missing stratum: excluded unless MISSING
        .{ 1, 12, 2000 },
        .{ 3, 40, 4000 },
    }) |r| try study.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    try lib.put(study.name, study);
    const ref = try a.create(Dataset);
    ref.* = Dataset.init(a, "standard");
    for ([_][]const u8{ "n", "total" }) |name| _ = try ref.addColumn(name, .num);
    for ([_][2]f64{ .{ 1, 10000 }, .{ 2, 20000 }, .{ 3, 10000 }, .{ nan, 7000 } }) |r| try ref.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
    try lib.put(ref.name, ref);
}

const Outcome = struct { rc: u8, out: []const u8 };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture, comptime build: fn (A, *Library) anyerror!void) !void {
        self.lib = Library.init(self.a());
        try build(self.a(), &self.lib);
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
        stdrate.run(self.cx(&d), &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !stdrate.Spec {
        return stdrate.parse(self.cx(d), try lex.tokenize(self.a(), source, d));
    }
    fn selected(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !stdrate.Selected {
        const s = try self.spec(d, source);
        const slices = try by.checkedSlices(self.a(), s.study, &.{}, &.{}, false, d);
        return stdrate.select(self.cx(d), s, slices[0].rows);
    }
};

test "STAT-STDRATE-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(pair);
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc stdrate data=study refdata=reference method=direct; population event=event total=total; reference total=total;");
    try expectEqual(stdrate.Method.direct, plain.method);
    try expectEqual(stdrate.Stat.rate, plain.stat);
    try expectEqual(@as(f64, 100000), plain.mult);
    try expectEqual(@as(f64, 0.05), plain.alpha);
    try expectEqual(stdrate.Cl.normal, plain.cl);
    try expectEqual(stdrate.GammaType.average, plain.gamma_type);
    try expectEqual(stdrate.Order.internal, plain.order);
    try expectEqual(stdrate.Order.internal, plain.group_order);
    try expect(plain.effect == null and plain.group == null and plain.stats == null and plain.smr == null and plain.popevent == null);
    try expect(!plain.af and !plain.plots and !plain.missing and !plain.strata_effect and !plain.strata_statement and !plain.where and !plain.notsorted);
    try expectEqual(@as(usize, 0), plain.strata.len + plain.ref_strata.len + plain.by_cols.len);
    try expectEqual(@as(?usize, 1), plain.population.event);
    try expectEqual(@as(?usize, 2), plain.population.total);
    try expectEqual(@as(?usize, 1), plain.ref.total);
    try expect(plain.population.rate == null and plain.population.risk == null and plain.ref.event == null);

    const full = try fx.spec(&d, "proc stdrate data=work.study refdata=reference m=indirect(af) stat=rate(mult=1000) effect=diff alpha=0.1 cl=gamma(type=conservative) plots(only)=(rate dist);" ++
        " population event=event total=total rate(mult=100)=r group(order=data exposed='A')=grp popevent=40;" ++
        " reference total=total event=event refevent=12 reftotal=30000 refrate(mult=10)=0.4;" ++
        " strata age n / missing effect order=data stats(cl=poisson) smr; by n; by descending b notsorted; where total > 0;");
    try expectEqual(stdrate.Method.indirect, full.method);
    try expect(full.af and full.plots and !full.plots_none and full.missing and full.strata_effect and full.strata_statement and full.where and full.notsorted);
    try expectEqual(@as(f64, 1000), full.mult);
    try expectEqual(@as(f64, 0.1), full.alpha);
    try expectEqual(stdrate.Cl.gamma, full.cl);
    try expectEqual(stdrate.GammaType.conservative, full.gamma_type);
    try expectEqual(@as(?stdrate.Effect, .diff), full.effect);
    try expectEqual(@as(?usize, 4), full.population.rate);
    try expectEqual(@as(?f64, 100), full.population.rate_mult);
    try expectEqual(@as(?usize, 3), full.group);
    try expectEqual(stdrate.Order.data, full.group_order);
    try std.testing.expectEqualStrings("A", full.exposed.?);
    try expectEqual(@as(?f64, 40), full.popevent);
    try expectEqual(@as(?usize, 2), full.ref.event);
    try expectEqual(@as(?f64, 12), full.refevent);
    try expectEqual(@as(?f64, 30000), full.reftotal);
    try expectEqual(@as(?f64, 0.4), full.refrate);
    try expectEqual(@as(?f64, 10), full.refrate_mult);
    try std.testing.expectEqualSlices(usize, &.{ 0, 6 }, full.strata);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3 }, full.ref_strata);
    try expectEqual(stdrate.Order.data, full.order);
    try expectEqual(@as(?stdrate.StrataCl, .poisson), full.stats);
    try expectEqual(@as(?stdrate.StrataCl, .normal), full.smr);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{5}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);

    const mh = try fx.spec(&d, "proc stdrate data=study method=mh(af) stat=risk effect cl=none plots=none; population event=event total=total group=grp; strata;");
    try expectEqual(stdrate.Method.mh, mh.method);
    try expectEqual(stdrate.Stat.risk, mh.stat);
    try expectEqual(@as(?stdrate.Effect, .ratio), mh.effect);
    try expect(mh.af and mh.plots_none and mh.reference == null and mh.strata_statement and mh.strata.len == 0);
    try expect(!d.hasErrors());
}

test "STAT-STDRATE-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(pair);
    const head = "proc stdrate data=study refdata=reference method=direct";
    const body = "; population event=event total=total; reference total=total; strata age";
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc stdrate data=study refdata=reference" ++ body ++ ";", 1 }, // METHOD= required
        .{ head ++ " bogus" ++ body ++ ";", 1 },
        .{ head ++ " method=mh" ++ body ++ ";", 1 }, // METHOD= twice
        .{ head ++ " data=study" ++ body ++ ";", 1 },
        .{ head ++ " refdata=reference" ++ body ++ ";", 1 },
        .{ "proc stdrate data=study refdata=reference method=xx" ++ body ++ ";", 1 },
        .{ "proc stdrate data=study refdata=reference method=direct(af)" ++ body ++ ";", 1 },
        .{ "proc stdrate data=nosuch refdata=reference method=direct" ++ body ++ ";", 1 },
        .{ "proc stdrate data=study refdata=nosuch method=direct" ++ body ++ ";", 1 },
        .{ head ++ " stat=odds" ++ body ++ ";", 1 },
        .{ head ++ " stat=risk(mult=10)" ++ body ++ ";", 1 },
        .{ head ++ " stat=rate(mult=250)" ++ body ++ ";", 1 }, // not a power of 10
        .{ head ++ " alpha=0" ++ body ++ ";", 1 },
        .{ head ++ " alpha=1.5" ++ body ++ ";", 1 },
        .{ head ++ " cl=exact" ++ body ++ ";", 1 },
        .{ head ++ " cl=normal(type=average)" ++ body ++ ";", 1 },
        .{ head ++ " effect=odds" ++ body ++ ";", 1 },
        .{ head ++ "; reference total=total; strata age;", 1 }, // POPULATION required
        .{ head ++ "; population event=event total=total; strata age;", 1 }, // REFERENCE required
        .{ "proc stdrate data=study method=mh; population event=event total=total; strata age;", 1 }, // GROUP= required
        .{ "proc stdrate data=study method=direct; population event=event total=total; reference total=total; strata age;", 1 }, // no REFDATA=
        .{ head ++ "; population event=nosuch total=total; reference total=total;", 1 },
        .{ head ++ "; population event=age total=total; reference total=total;", 1 }, // character EVENT=
        .{ head ++ "; population event=event event=event total=total; reference total=total;", 1 },
        .{ head ++ "; population event=event total=total bogus=1; reference total=total;", 1 },
        .{ head ++ "; population event=event total=total popevent=-1; reference total=total;", 1 },
        .{ head ++ "; population event=event total=total group(order=xx)=grp; reference total=total;", 1 },
        .{ head ++ "; population event=event total=total; reference total=nosuch;", 1 },
        .{ head ++ "; population event=event total=total; reference total=total reftotal=0;", 1 },
        .{ head ++ "; population event=event total=total; reference total=total refrisk=2;", 1 },
        .{ head ++ body ++ " nosuch;", 1 },
        .{ head ++ body ++ " b;", 1 }, // STRATA variable absent from the reference
        .{ head ++ body ++ " / bogus;", 1 },
        .{ head ++ body ++ " / order=xx;", 1 },
        .{ head ++ body ++ " / stats(cl=gamma);", 1 },
        .{ head ++ body ++ "; by nosuch;", 1 },
        .{ head ++ body ++ "; bogus age;", 1 },
        // Valid declarations whose results are not implemented.
        .{ "proc stdrate refdata=reference method=direct" ++ body ++ ";", 2 }, // DATA= omitted
        .{ "proc stdrate data=study(obs=1) refdata=reference method=direct" ++ body ++ ";", 2 },
        .{ "proc stdrate data=study refdata=reference method=indirect" ++ body ++ ";", 2 },
        .{ "proc stdrate data=study refdata=reference method=indirect(af)" ++ body ++ ";", 2 },
        .{ "proc stdrate data=study method=mh; population event=event total=total group=grp; strata age;", 2 },
        .{ head ++ " stat=risk" ++ body ++ ";", 2 },
        .{ head ++ " stat=rate(mult=1000)" ++ body ++ ";", 2 },
        .{ head ++ " alpha=0.1" ++ body ++ ";", 2 },
        .{ head ++ " cl=lognormal" ++ body ++ ";", 2 },
        .{ head ++ " cl=gamma" ++ body ++ ";", 2 },
        .{ head ++ " cl=none" ++ body ++ ";", 2 },
        .{ head ++ " effect" ++ body ++ ";", 2 },
        .{ head ++ " plots=all" ++ body ++ ";", 2 },
        .{ head ++ " plots(only)=(rate dist)" ++ body ++ ";", 2 },
        .{ head ++ "; population event=event total=total group=grp; reference total=total; strata age;", 2 },
        .{ head ++ "; population event=event total=total popevent=40; reference total=total; strata age;", 2 },
        .{ head ++ "; population rate=r total=total; reference total=total; strata age;", 2 },
        .{ head ++ "; population event=event; reference total=total; strata age;", 2 },
        .{ head ++ "; population event=event total=total; reference event=event total=total; strata age;", 2 },
        .{ head ++ "; population event=event total=total; reference total=total reftotal=30000; strata age;", 2 },
        .{ head ++ "; population event=event total=total; reference refevent=12; strata age;", 2 },
        .{ head ++ "; population event=event total=total; population event=event total=total; reference total=total;", 2 },
        .{ head ++ "; population event=event total=total; reference total=total; reference total=total;", 2 },
        .{ head ++ body ++ "; strata age;", 2 },
        .{ head ++ body ++ " age;", 2 },
        .{ head ++ body ++ " / effect;", 2 },
        .{ head ++ body ++ " / stats;", 2 },
        .{ head ++ body ++ " / smr(cl=none);", 2 },
        .{ head ++ body ++ " / order=formatted;", 2 },
        .{ head ++ body ++ "; format age $3.;", 2 },
        .{ head ++ body ++ "; where total > 0;", 2 },
        .{ head ++ body ++ "; by n;", 2 }, // sorted ascending by n: the BY listing is a gap
        .{ head ++ body ++ "; by n notsorted;", 2 },
        // Execution boundaries on data.
        .{ head ++ "; population event=event total=total; reference total=total;", 2 }, // no STRATA
        .{ head ++ "; population event=event total=total; reference total=total; strata;", 2 },
        .{ "proc stdrate data=none refdata=reference method=direct" ++ body ++ ";", 2 }, // empty study
        .{ "proc stdrate data=study refdata=study method=direct; population event=event total=total; reference total=total; strata grp;", 2 }, // two observations in one stratum
    }) |case| {
        const result = try fx.outcome(case[0]);
        std.testing.expectEqual(case[1], result.rc) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
        try expectEqual(@as(usize, 0), result.out.len);
    }
    // BY boundary: the study is in descending order of b, so ascending BY b
    // is the documented sort error (rc 1), not a gap.
    try expectEqual(@as(u8, 1), (try fx.outcome(head ++ body ++ "; by b;")).rc);
}

test "STAT-STDRATE-001 observation selection, level matching and ordering" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(missings);
    var d = diag.Diagnostics.init(fx.a());
    const head = "proc stdrate data=cohort refdata=standard method=direct; population event=event total=total; reference total=total; strata n";
    // Default: the missing-stratum observation of each data set is excluded;
    // levels come back in ORDER=INTERNAL order.
    const plain = try fx.selected(&d, head ++ ";");
    try expectEqual(@as(usize, 4), plain.study_read);
    try expectEqual(@as(usize, 3), plain.study_used);
    try expectEqual(@as(usize, 4), plain.reference_read);
    try expectEqual(@as(usize, 3), plain.reference_used);
    try expectEqual(@as(usize, 3), plain.strata.len);
    for (plain.strata, [_]f64{ 1, 2, 3 }, [_]f64{ 12, 30, 40 }, [_]f64{ 2000, 3000, 4000 }, [_]f64{ 10000, 20000, 10000 }) |st, level, events, time, ref_time| {
        try expectEqual(level, st.key[0].num);
        try expectEqual(events, st.events);
        try expectEqual(time, st.time);
        try expectEqual(ref_time, st.ref_time);
    }
    // ORDER=DATA keeps the study data order.
    const data = try fx.selected(&d, head ++ " / order=data;");
    for (data.strata, [_]f64{ 2, 1, 3 }) |st, level| try expectEqual(level, st.key[0].num);
    // MISSING makes the missing value a level, sorted first.
    const missing = try fx.selected(&d, head ++ " / missing;");
    try expectEqual(@as(usize, 4), missing.study_used);
    try expectEqual(@as(usize, 4), missing.reference_used);
    try expectEqual(@as(usize, 4), missing.strata.len);
    try expect(std.math.isNan(missing.strata[0].key[0].num));
    try expectEqual(@as(f64, 5), missing.strata[0].events);
    try expectEqual(@as(f64, 7000), missing.strata[0].ref_time);
    try expect(!d.hasErrors());
}

test "STAT-STDRATE-001 direct standardization matches hand calculation" {
    // Reference case: rates 10/1000 and 30/1500, reference times 20000 and
    // 10000. Expected = 20000*0.01 + 10000*0.02 = 400; estimate = 400/30000;
    // variance = (2/3)^2*10/1000^2 + (1/3)^2*30/1500^2 = 16/2700000.
    const r = stdrate.direct(&.{
        .{ .key = &.{}, .events = 10, .time = 1000, .ref_time = 20000 },
        .{ .key = &.{}, .events = 30, .time = 1500, .ref_time = 10000 },
    });
    const tol = 1e-12;
    try std.testing.expectApproxEqRel(@as(f64, 40), r.events, tol);
    try std.testing.expectApproxEqRel(@as(f64, 2500), r.time, tol);
    try std.testing.expectApproxEqRel(@as(f64, 0.016), r.crude, tol);
    try std.testing.expectApproxEqRel(@as(f64, 400), r.expected, tol);
    try std.testing.expectApproxEqRel(@as(f64, 30000), r.ref_time, tol);
    try std.testing.expectApproxEqRel(@as(f64, 4.0 / 300.0), r.estimate, tol);
    try std.testing.expectApproxEqRel(@sqrt(@as(f64, 16.0 / 2700000.0)), r.se, tol);
    try std.testing.expectApproxEqRel(4.0 / 300.0 - 1.959963984540054 * @sqrt(@as(f64, 16.0 / 2700000.0)), r.lower, tol);
    try std.testing.expectApproxEqRel(4.0 / 300.0 + 1.959963984540054 * @sqrt(@as(f64, 16.0 / 2700000.0)), r.upper, tol);
    // Three strata: weights 1/4, 1/2, 1/4; rates 0.006, 0.01, 0.01.
    // Expected = 60 + 200 + 100 = 360; estimate = 0.009;
    // variance = 12/64e6 + 30/36e6 + 40/256e6 = 1.875e-7 + 8.3333e-7 + 1.5625e-7.
    const three = stdrate.direct(&.{
        .{ .key = &.{}, .events = 12, .time = 2000, .ref_time = 10000 },
        .{ .key = &.{}, .events = 30, .time = 3000, .ref_time = 20000 },
        .{ .key = &.{}, .events = 40, .time = 4000, .ref_time = 10000 },
    });
    try std.testing.expectApproxEqRel(@as(f64, 360), three.expected, tol);
    try std.testing.expectApproxEqRel(@as(f64, 0.009), three.estimate, tol);
    try std.testing.expectApproxEqRel(@as(f64, 82.0 / 9000.0), three.crude, tol);
    try std.testing.expectApproxEqRel(@as(f64, 1.0849347), three.se * 1000, 1e-6);
}

test "STAT-STDRATE-001 default direct rate listing" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(pair);
    const result = try fx.outcome("proc stdrate data=study refdata=reference method=direct stat=rate; population event=event total=total; reference total=total; strata age;");
    try expectEqual(@as(u8, 0), result.rc);
    try std.testing.expectEqualStrings(
        \\
        \\The STDRATE Procedure
        \\
        \\          Standardization Information
        \\
        \\Data Set                             WORK.STUDY
        \\Reference Data Set               WORK.REFERENCE
        \\Method                   Direct Standardization
        \\Statistic                                  Rate
        \\Number of Strata                              2
        \\Rate Multiplier                          100000
        \\
        \\The STDRATE Procedure
        \\
        \\
    ++ "                             Directly Standardized Rate Estimates \n" ++ // the reference has these trailing blanks
        "                                    Rate Multiplier = 100000\n \n" ++
        \\--------Study Population-------  -Reference Population-  -----------Standardized Rate----------
        \\Observed  Population-     Crude  Expected   Population-            Standard      95% Normal
        \\  Events         Time      Rate    Events          Time  Estimate     Error   Confidence Limits
        \\
        \\      40         2500    1600.0   400.000         30000    1333.3     243.4     856.2    1810.5
        \\
    , result.out);
    // A numeric STRATA variable with the same levels gives the same analysis.
    const numeric = try fx.outcome("proc stdrate data=study refdata=reference method=direct; population event=event total=total; reference total=total; strata n;");
    try expectEqual(@as(u8, 0), numeric.rc);
    try std.testing.expectEqualStrings(result.out, numeric.out);
    // PLOTS=NONE is the same analysis without graphs.
    const none = try fx.outcome("proc stdrate data=study refdata=reference method=direct plots=none; population event=event total=total; reference total=total; strata age;");
    try expectEqual(@as(u8, 0), none.rc);
    try std.testing.expectEqualStrings(result.out, none.out);
}
