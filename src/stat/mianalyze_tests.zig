//! STAT-MIANALYZE-001 permanent checks: declarations, input data set forms,
//! variable roles, BY boundaries, execution boundaries, and the combining
//! rules behind the default listing. Data are invented; the published
//! SAS/STAT 15.4 reference listing is cited where its printed values are used.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const inference = @import("univ_inference.zig");
const mianalyze = @import("mianalyze.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const close = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const b0 = [_]f64{ 90.5, 94.0, 96.5, 89.0 };
const s0 = [_]f64{ 9.0, 8.5, 9.5, 8.0 };
const b1 = [_]f64{ -3.10, -2.80, -3.30, -2.90 };
const s1 = [_]f64{ 0.36, 0.34, 0.38, 0.32 };

/// One observation per imputation: b0 s0 b1 s1 g c. The first four rows are
/// the invented estimates; BY group g=2 repeats two of them shifted by one.
fn plain(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "plain");
    for ([_][]const u8{ "b0", "s0", "b1", "s1", "g" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("c", .char);
    for (0..4) |r| try ds.appendRow(&.{ .{ .num = b0[r] }, .{ .num = s0[r] }, .{ .num = b1[r] }, .{ .num = s1[r] }, .{ .num = 1 }, .{ .str = "x" } });
    for (0..2) |r| try ds.appendRow(&.{ .{ .num = b0[r] + 1 }, .{ .num = s0[r] }, .{ .num = b1[r] + 1 }, .{ .num = s1[r] }, .{ .num = 2 }, .{ .str = "x" } });
    return ds;
}

/// The same four imputations in the EST form: _Imputation_ _TYPE_ _NAME_ b0
/// b1 other. Type and name case, an ignored _TYPE_ and the alternative
/// PARM/COVB spellings are exercised.
fn structured(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "est");
    _ = try ds.addColumn("_Imputation_", .num);
    _ = try ds.addColumn("_TYPE_", .char);
    _ = try ds.addColumn("_NAME_", .char);
    for ([_][]const u8{ "b0", "b1", "other" }) |name| _ = try ds.addColumn(name, .num);
    for (0..4) |r| {
        const id: f64 = @floatFromInt(r + 1);
        const even = r % 2 == 0;
        try ds.appendRow(&.{ .{ .num = id }, .{ .str = if (even) "PARMS" else "parm" }, .{ .str = "" }, .{ .num = b0[r] }, .{ .num = b1[r] }, .{ .num = nan } });
        try ds.appendRow(&.{ .{ .num = id }, .{ .str = if (even) "COV" else "covb" }, .{ .str = "B0" }, .{ .num = s0[r] * s0[r] }, .{ .num = -0.5 }, .{ .num = nan } });
        try ds.appendRow(&.{ .{ .num = id }, .{ .str = "COV" }, .{ .str = "b1" }, .{ .num = -0.5 }, .{ .num = s1[r] * s1[r] }, .{ .num = nan } });
        try ds.appendRow(&.{ .{ .num = id }, .{ .str = "RIDGE" }, .{ .str = "" }, .{ .num = 1e9 }, .{ .num = 1e9 }, .{ .num = nan } });
    }
    return ds;
}

/// Problem inputs, one data set each.
fn problems(a: A, lib: *Library) !void {
    const Row = struct { f64, []const u8, []const u8, f64 };
    const Case = struct { []const u8, []const Row };
    for ([_]Case{
        .{ "empty", &.{} },
        .{ "single", &.{ .{ 1, "PARMS", "", 1 }, .{ 1, "COV", "b0", 1 } } },
        .{ "noparm", &.{ .{ 1, "PARMS", "", 1 }, .{ 1, "COV", "b0", 1 }, .{ 2, "COV", "b0", 1 } } },
        .{ "nocov", &.{ .{ 1, "PARMS", "", 1 }, .{ 1, "COV", "b0", 1 }, .{ 2, "PARMS", "", 2 } } },
        .{ "twoparm", &.{ .{ 1, "PARMS", "", 1 }, .{ 1, "PARMS", "", 1 }, .{ 1, "COV", "b0", 1 } } },
        .{ "moments", &.{ .{ 1, "MEAN", "", 1 }, .{ 1, "N", "", 9 }, .{ 1, "COV", "b0", 1 } } },
        .{ "missing", &.{ .{ 1, "PARMS", "", nan }, .{ 1, "COV", "b0", 1 }, .{ 2, "PARMS", "", 2 }, .{ 2, "COV", "b0", 1 } } },
        .{ "negative", &.{ .{ 1, "PARMS", "", 1 }, .{ 1, "COV", "b0", -1 }, .{ 2, "PARMS", "", 2 }, .{ 2, "COV", "b0", 1 } } },
        .{ "constant", &.{ .{ 1, "PARMS", "", 2 }, .{ 1, "COV", "b0", 1 }, .{ 2, "PARMS", "", 2 }, .{ 2, "COV", "b0", 1 } } },
    }) |case| {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, case[0]);
        _ = try ds.addColumn("_Imputation_", .num);
        _ = try ds.addColumn("_TYPE_", .char);
        _ = try ds.addColumn("_NAME_", .char);
        _ = try ds.addColumn("b0", .num);
        for (case[1]) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .str = r[1] }, .{ .str = r[2] }, .{ .num = r[3] } });
        try lib.put(ds.name, ds);
    }
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
        try problems(self.a(), &self.lib);
        for ([_]*Dataset{ try structured(self.a()), try plain(self.a()) }) |ds| try self.lib.put(ds.name, ds);
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
        mianalyze.run(self.cx(&d), &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !mianalyze.Spec {
        return mianalyze.parse(self.cx(d), try lex.tokenize(self.a(), source, d));
    }
    fn plan(self: *Fixture, d: *diag.Diagnostics, source: []const u8) ![]mianalyze.Analysis {
        return mianalyze.plan(self.cx(d), try self.spec(d, source));
    }
};

test "STAT-MIANALYZE-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    // No DATA=: the most recently created data set (plain) is the input.
    const default = try fx.spec(&d, "proc mianalyze; modeleffects b0 b1; stderr s0 s1;");
    try std.testing.expectEqualStrings("WORK.PLAIN", default.data_name);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, default.effects);
    try std.testing.expectEqualSlices(usize, &.{ 1, 3 }, default.stderr);
    try expectEqual(@as(f64, 0.05), default.alpha);
    try expect(default.edf == null and default.theta0.len == 0 and default.by_cols.len == 0 and !default.notsorted);
    const full = try fx.spec(&d, "proc mianalyze data=work.plain alpha=.1 edf=28 theta0=90 -3; modeleffects b1 b0; stderr s1 s0; by c; by descending g notsorted;");
    try std.testing.expectEqualStrings("WORK.PLAIN", full.data_name);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0 }, full.effects);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1 }, full.stderr);
    try expectEqual(@as(f64, 0.1), full.alpha);
    try expectEqual(@as(?f64, 28), full.edf);
    try std.testing.expectEqualSlices(f64, &.{ 90, -3 }, full.theta0);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{4}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(full.notsorted);
    const est = try fx.spec(&d, "proc mianalyze data=est mu0=1; modeleffects b0;");
    try std.testing.expectEqualStrings("WORK.EST", est.data_name);
    try expectEqual(@as(usize, 0), est.stderr.len);
    try std.testing.expectEqualSlices(f64, &.{1}, est.theta0);
    try expect(!d.hasErrors());
}

test "STAT-MIANALYZE-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc mianalyze data=plain; stderr s0;", 1 }, // MODELEFFECTS required
        .{ "proc mianalyze data=plain bogus; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=nosuch; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain data=plain; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain alpha=0; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain alpha=1; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain alpha=x; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain edf=0; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain edf=-3; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain theta0=; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain theta0=1 mu0=2; modeleffects b0; stderr s0;", 1 },
        .{ "proc mianalyze data=plain; modeleffects; stderr s0;", 1 },
        .{ "proc mianalyze data=plain; modeleffects nosuch; stderr s0;", 1 },
        .{ "proc mianalyze data=plain; modeleffects c; stderr s0;", 1 }, // character effect
        .{ "proc mianalyze data=plain; modeleffects b0; stderr;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0; stderr nosuch;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0; stderr c;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0 b1; stderr s0;", 1 }, // count mismatch
        .{ "proc mianalyze data=plain; modeleffects b0; stderr s0 s1;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0; stderr s0; by nosuch;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0; stderr s0; by descending g;", 1 }, // not sorted descending
        .{ "proc mianalyze data=plain; modeleffects b0; stderr s0; bogus b0;", 1 },
        .{ "proc mianalyze data=plain; modeleffects b0;", 1 }, // not specially structured, STDERR required
        .{ "proc mianalyze data=empty; modeleffects b0;", 1 }, // no imputations
        .{ "proc mianalyze data=noparm; modeleffects b0;", 1 },
        .{ "proc mianalyze data=nocov; modeleffects b0;", 1 },
        .{ "proc mianalyze data=twoparm; modeleffects b0;", 1 },
        .{ "proc mianalyze data=negative; modeleffects b0;", 1 },
        .{ "proc mianalyze parms=plain; modeleffects b0;", 2 },
        .{ "proc mianalyze data=plain covb=plain; modeleffects b0;", 2 },
        .{ "proc mianalyze data=plain xpxi=plain; modeleffects b0;", 2 },
        .{ "proc mianalyze data=plain parminfo=plain; modeleffects b0;", 2 },
        .{ "proc mianalyze data=est wcov; modeleffects b0;", 2 },
        .{ "proc mianalyze data=est bcov; modeleffects b0;", 2 },
        .{ "proc mianalyze data=est tcov; modeleffects b0;", 2 },
        .{ "proc mianalyze data=est mult; modeleffects b0;", 2 },
        .{ "proc mianalyze data=est multivariate; modeleffects b0;", 2 },
        .{ "proc mianalyze data=plain; class c; modeleffects b0; stderr s0;", 2 },
        .{ "proc mianalyze data=est; modeleffects b0 b1; test b0=b1;", 2 },
        .{ "proc mianalyze data=est; modeleffects b0*b1;", 2 },
        .{ "proc mianalyze data=est; modeleffects b0 b0;", 2 },
        .{ "proc mianalyze data=est; modeleffects b0; modeleffects b1;", 2 },
        .{ "proc mianalyze data=plain; modeleffects b0; stderr s0; stderr s0;", 2 },
        .{ "proc mianalyze data=est theta0=1 2 3; modeleffects b0 b1;", 2 },
        .{ "proc mianalyze data=single; modeleffects b0;", 2 }, // one imputation
        .{ "proc mianalyze data=moments; modeleffects b0;", 2 }, // TYPE=COV/CORR
        .{ "proc mianalyze data=missing; modeleffects b0;", 2 },
        .{ "proc mianalyze data=constant; modeleffects b0;", 2 }, // zero between variance
        .{ "proc mianalyze data=plain; modeleffects b0 b1; stderr s0 s1; by g;", 2 }, // BY listing
        .{ "proc mianalyze data=est alpha=.025; modeleffects b0 b1;", 2 }, // 97.5% heading
        .{ "proc mianalyze data=est; modeleffects b1;", 2 }, // limit columns outside the verified shape
    }) |case| {
        const result = try fx.outcome(case[0]);
        if (result.rc != case[1]) std.debug.print("case {s}: rc {d}\n", .{ case[0], result.rc });
        try expectEqual(case[1], result.rc);
        // A failed step never leaves a partial listing.
        try expectEqual(@as(usize, 0), result.out.len);
    }
}

test "STAT-MIANALYZE-001 combining rules reproduce the SAS reference variance table" {
    // SAS/STAT 15.4 reference listing for the fitness regression (25
    // imputations): Between, Within -> Total, DF, relative increase, fraction
    // missing, relative efficiency. The inputs carry six printed decimals, so
    // each output is checked to the precision its propagated rounding allows.
    const Row = struct { between: f64, within: f64, total: f64, df: f64, increase: f64, fraction: f64, efficiency: f64 };
    for ([_]Row{
        .{ .between = 22.485821, .within = 75.413875, .total = 98.799129, .df = 428.38, .increase = 0.310092, .fraction = 0.240234, .efficiency = 0.990482 },
        .{ .between = 0.021126, .within = 0.124930, .total = 0.146902, .df = 1072.9, .increase = 0.175870, .fraction = 0.151147, .efficiency = 0.993990 },
        .{ .between = 0.000656, .within = 0.002622, .total = 0.003304, .df = 562.35, .increase = 0.260376, .fraction = 0.209393, .efficiency = 0.991694 },
    }) |row| {
        const c = mianalyze.derive(25, 0, row.within, row.between, null);
        // Relative input rounding: half a unit in the sixth decimal of B and W.
        const relative = 0.5e-6 / row.between + 0.5e-6 / row.within;
        try close(row.total, c.total, 2e-6);
        try close(row.increase, c.increase, row.increase * relative + 0.5e-6);
        // d(df)/df = -2 dr / (r (1+r)); allow the display half-unit as well.
        try close(row.df, c.df, row.df * 2 * relative / (1 + row.increase) + 0.05);
        try close(row.fraction, c.fraction, row.increase * relative + 1e-6);
        try close(row.efficiency, c.efficiency, row.increase * relative + 1e-6);
    }
    // Reference estimates row: Intercept 92.700420, Std Error 9.939775,
    // DF 428.38 -> limits 73.16362 and 112.2372, t 9.33.
    const margin = -inference.tQuantile(0.025, 428.38) * 9.939775;
    try close(@as(f64, 73.16362), 92.700420 - margin, 5e-5);
    try close(@as(f64, 112.2372), 92.700420 + margin, 5e-5);
    try close(@as(f64, 9.33), 92.700420 / 9.939775, 5e-3);
    // RunPulse: t -1.39 with 562.35 DF has Pr > |t| = 0.1666.
    try close(@as(f64, 0.1666), inference.tProbability(-0.079621 / 0.057482, 562.35), 2e-4);
}

test "STAT-MIANALYZE-001 combining rules by hand, with and without EDF" {
    // q = 1,2,3 with unit variances: Qbar 2, W 1, B 1, T = 1 + 4/3,
    // r = 4/3, v_m = 2 (7/4)^2 = 49/8, lambda = (4/3 + 2/(49/8+3))/(7/3).
    const c = mianalyze.combine(&.{ 1, 2, 3 }, &.{ 1, 1, 1 }, null);
    try close(@as(f64, 2), c.estimate, 1e-12);
    try close(@as(f64, 1), c.within, 1e-12);
    try close(@as(f64, 1), c.between, 1e-12);
    try close(@as(f64, 7.0 / 3.0), c.total, 1e-12);
    try close(@as(f64, 4.0 / 3.0), c.increase, 1e-12);
    try close(@as(f64, 49.0 / 8.0), c.df, 1e-12);
    const lambda: f64 = (4.0 / 3.0 + 2.0 / (49.0 / 8.0 + 3.0)) / (7.0 / 3.0);
    try close(lambda, c.fraction, 1e-12);
    try close(1.0 / (1.0 + lambda / 3.0), c.efficiency, 1e-12);
    // EDF=10: gamma = (4/3)/(7/3) = 4/7, v_obs = (3/7)(10)(11)/13 = 330/91,
    // adjusted DF = 1/(8/49 + 91/330) = 16170/7099. Only the DF changes.
    const adjusted = mianalyze.combine(&.{ 1, 2, 3 }, &.{ 1, 1, 1 }, 10);
    try close(@as(f64, 16170.0 / 7099.0), adjusted.df, 1e-12);
    try close(lambda, adjusted.fraction, 1e-12);
    try close(c.total, adjusted.total, 1e-12);
}

test "STAT-MIANALYZE-001 both DATA= forms, variable roles and BY boundaries" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    // Hand arithmetic for the four invented imputations:
    // b0: mean 92.5, B = (4+2.25+16+12.25)/3 = 11.5, W = (81+72.25+90.25+64)/4 = 76.875,
    //     T = 76.875 + 1.25*11.5 = 91.25.
    // b1: mean -3.025, B = (0.005625+0.050625+0.075625+0.015625)/3 = 0.1475/3,
    //     W = (0.1296+0.1156+0.1444+0.1024)/4 = 0.123.
    const est = try fx.plan(&d, "proc mianalyze data=est; modeleffects b0 b1;");
    const first = (try fx.plan(&d, "proc mianalyze data=plain(obs=4); modeleffects b0 b1; stderr s0 s1;"))[0];
    try expectEqual(@as(usize, 1), est.len);
    for ([_]mianalyze.Analysis{ est[0], first }) |an| {
        try expectEqual(@as(usize, 4), an.imputations);
        try std.testing.expectEqualStrings("b0", an.parameters[0].name);
        try close(@as(f64, 92.5), an.parameters[0].c.estimate, 1e-12);
        try close(@as(f64, 11.5), an.parameters[0].c.between, 1e-12);
        try close(@as(f64, 76.875), an.parameters[0].c.within, 1e-12);
        try close(@as(f64, 91.25), an.parameters[0].c.total, 1e-12);
        try close(@as(f64, 89), an.parameters[0].minimum, 0);
        try close(@as(f64, 96.5), an.parameters[0].maximum, 0);
        try close(@as(f64, -3.025), an.parameters[1].c.estimate, 1e-12);
        try close(@as(f64, 0.1475 / 3.0), an.parameters[1].c.between, 1e-12);
        try close(@as(f64, 0.123), an.parameters[1].c.within, 1e-12);
        try close(@as(f64, 0), an.parameters[1].theta0, 0);
    }
    // WHERE selects observations like the OBS= data set option.
    const where = try fx.plan(&d, "proc mianalyze data=plain; where g=1; modeleffects b0; stderr s0;");
    try expectEqual(@as(usize, 4), where[0].imputations);
    // BY g: 4 imputations then 2. Group 2 holds b0 = 91.5, 95 with
    // B = 2*(1.75^2) = 6.125 and W = (81+72.25)/2 = 76.625.
    const groups = try fx.plan(&d, "proc mianalyze data=plain theta0=90 -3; modeleffects b0 b1; stderr s0 s1; by g;");
    try expectEqual(@as(usize, 2), groups.len);
    try expectEqual(@as(usize, 4), groups[0].imputations);
    try expectEqual(@as(usize, 2), groups[1].imputations);
    try close(@as(f64, 11.5), groups[0].parameters[0].c.between, 1e-12);
    try close(@as(f64, 93.25), groups[1].parameters[0].c.estimate, 1e-12);
    try close(@as(f64, 6.125), groups[1].parameters[0].c.between, 1e-12);
    try close(@as(f64, 76.625), groups[1].parameters[0].c.within, 1e-12);
    try close(@as(f64, 2), groups[1].rep.?[4].num, 0);
    try close(@as(f64, 90), groups[1].parameters[0].theta0, 0);
    try close(@as(f64, -3), groups[1].parameters[1].theta0, 0);
    // One THETA0= number applies to every effect.
    const one = try fx.plan(&d, "proc mianalyze data=est theta0=5; modeleffects b0 b1;");
    try close(@as(f64, 5), one[0].parameters[1].theta0, 0);
    try expect(!d.hasErrors());
}
