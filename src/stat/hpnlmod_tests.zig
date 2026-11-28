//! STAT-HPNLMOD-001 permanent tests: PROC statement options, PARAMETERS/MODEL/
//! BY roles, missing-value selection, the undamped Levenberg-Marquardt path
//! and loud execution boundaries. The enzyme data are the published sample of
//! the NLIN/HPNLMOD chapters; expected values are SAS 9.4 / STAT 15.4 listings
//! of these programs (the ticket reference and a BY-group run of the same
//! published rows), never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const hp = @import("hpnlmod.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const enzyme = [_][2]f64{ .{ 0.26, 124.7 }, .{ 0.30, 126.9 }, .{ 0.48, 135.9 }, .{ 0.50, 137.6 }, .{ 0.54, 139.6 }, .{ 0.68, 141.1 }, .{ 0.82, 142.8 }, .{ 1.14, 147.6 }, .{ 1.28, 149.8 }, .{ 1.38, 149.4 }, .{ 1.80, 153.9 }, .{ 2.30, 152.5 }, .{ 2.44, 154.5 }, .{ 2.48, 154.7 } };
// BY data of the SAS-verified run: group a = 7 rows, group b = 9 rows of which
// one has a missing response and one a missing conc.
const ByRow = struct { g: []const u8, x: f64, y: f64 };
const by_rows = [_]ByRow{
    .{ .g = "a", .x = 1.38, .y = 149.4 }, .{ .g = "a", .x = 1.80, .y = 153.9 }, .{ .g = "a", .x = 2.30, .y = 152.5 },
    .{ .g = "a", .x = 2.44, .y = 154.5 }, .{ .g = "a", .x = 2.48, .y = 154.7 }, .{ .g = "a", .x = 0.26, .y = 124.7 },
    .{ .g = "a", .x = 0.50, .y = 137.6 }, .{ .g = "b", .x = 0.26, .y = 124.7 }, .{ .g = "b", .x = 0.30, .y = 126.9 },
    .{ .g = "b", .x = 0.48, .y = 135.9 }, .{ .g = "b", .x = 0.50, .y = nan }, .{ .g = "b", .x = 0.54, .y = 139.6 },
    .{ .g = "b", .x = 0.68, .y = 141.1 }, .{ .g = "b", .x = 0.82, .y = 142.8 }, .{ .g = "b", .x = 1.14, .y = 147.6 },
    .{ .g = "b", .x = nan, .y = 149.8 },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const e = try a.create(Dataset);
        e.* = Dataset.init(a, "enzyme");
        _ = try e.addColumn("conc", .num);
        _ = try e.addColumn("rate", .num);
        _ = try e.addColumn("c", .char);
        for (enzyme) |r| try e.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = "x" } });
        try self.lib.put("enzyme", e);
        const b = try a.create(Dataset);
        b.* = Dataset.init(a, "e2");
        _ = try b.addColumn("g", .char);
        _ = try b.addColumn("conc", .num);
        _ = try b.addColumn("rate", .num);
        for (by_rows) |r| try b.appendRow(&.{ .{ .str = r.g }, .{ .num = r.x }, .{ .num = r.y } });
        try self.lib.put("e2", b);
        diag.resetGap();
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn tokens(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !hp.Spec {
        return hp.parse(self.cx(), try self.tokens(source));
    }
};

test "STAT-HPNLMOD-001 PROC statement defaults, explicit options and statement roles" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Defaults: ALPHA=0.05, GCONV=1E-8, most recent data set (e2 was put last).
    const d = try e.parse("proc hpnlmod; parms t1=160 t2=0.1; model rate ~ residual(t1*conc/(t2+conc)); run;");
    try expectEqual(@as(f64, 0.05), d.alpha);
    try expectEqual(@as(f64, 1e-8), d.gconv);
    try std.testing.expectEqualStrings("WORK.E2", d.data_name);
    try std.testing.expectEqualStrings("E2", d.member);
    try expectEqual(@as(usize, 2), d.dependent);
    try std.testing.expectEqualSlices(usize, &.{1}, d.model_cols);
    try expectEqual(@as(usize, 0), d.by_cols.len);

    // Explicit settings, PARAMETERS spelling with commas, a repeated parameter
    // keeps its last starting value (SAS reference), the last BY statement wins.
    const s = try e.parse("proc hpnlmod data=work.e2 alpha=0.1 gtol=1e-6; parameters t1=1, t2=-0.5 t1=160; by conc; by g; model rate ~ residual(t1*conc/(t2+conc)); run;");
    try expectEqual(@as(f64, 0.1), s.alpha);
    try expectEqual(@as(f64, 1e-6), s.gconv);
    try expectEqual(@as(usize, 2), s.params.len);
    try std.testing.expectEqualStrings("t1", s.params[0].name);
    try expectEqual(@as(f64, 160), s.params[0].start);
    try expectEqual(@as(f64, -0.5), s.params[1].start);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
}

test "STAT-HPNLMOD-001 iteration history and estimates match the SAS enzyme listing" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc hpnlmod data=enzyme; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;");
    const f = try hp.fit(e.cx(), s, s.input.ds.rows.items);
    const ref = [_][4]f64{
        .{ 5, 13.940105522, nan, 1214.657 },
        .{ 2, 1.4437568364, 12.49634869, 74.98021 },
        .{ 2, 1.4043329995, 0.03942384, 0.593933 },
        .{ 2, 1.4043280406, 0.00000496, 0.005261 },
        .{ 2, 1.4043280401, 0, 0.000057 },
    };
    try expectEqual(ref.len, f.history.len);
    for (ref, f.history) |r, h| {
        try expectEqual(@as(usize, @intFromFloat(r[0])), h.evals);
        try approx(r[1], h.f, 5e-10);
        if (!std.math.isNan(r[2])) try approx(r[2], h.change, 5e-9);
        try approx(r[3], h.maxgrad, 5e-7 * @max(1, r[3]));
    }
    try approx(@as(f64, 13.9401055), f.f0, 5e-8);
    try approx(@as(f64, 19.6606), f.sse, 5e-5);
    try approx(@as(f64, 1.6384), f.mse, 5e-5);
    try approx(@as(f64, 290135), f.total_ss, 0.5);
    try approx(@as(f64, 158.1), f.theta[0], 0.05);
    try approx(@as(f64, 0.0741), f.theta[1], 5e-5);
    try approx(@as(f64, 0.6737), f.se[0], 5e-5);
    try approx(@as(f64, 0.00313), f.se[1], 5e-6);
    try approx(@as(f64, 156.6), f.lower[0], 0.05);
    try approx(@as(f64, 0.0809), f.upper[1], 5e-5);
    const a = e.arena.allocator();
    try std.testing.expectEqualStrings("0.000057", try hp.gradText(a, 0.0000573801));
    try std.testing.expectEqualStrings("0.00002", try hp.gradText(a, 0.0000200002));
    try std.testing.expectEqualStrings("9458.2818377", try hp.changeText(a, 9458.28183771));
    try std.testing.expectEqualStrings("0.00000000", try hp.changeText(a, 5.8e-10));
}

test "STAT-HPNLMOD-001 BY groups and missing values match the SAS listing" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try hp.run(e.cx(), &out, try e.tokens("proc hpnlmod data=e2; by g; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;"));
    const o = out.items;
    // Header once, one block per BY group in order, 7 of 7 and 9 read / 7 used.
    try expectEqual(@as(usize, 1), std.mem.count(u8, o, "Performance Information"));
    try expectEqual(@as(usize, 3), std.mem.count(u8, o, "The HPNLMOD Procedure"));
    const ia = std.mem.indexOf(u8, o, "g=a").?;
    const ib = std.mem.indexOf(u8, o, "g=b").?;
    try expect(ia < ib);
    try expect(std.mem.indexOf(u8, o, "Number of Observations Read               7\nNumber of Observations Used               7") != null);
    try expect(std.mem.indexOf(u8, o, "Number of Observations Read               9\nNumber of Observations Used               7") != null);
    try expect(std.mem.indexOf(u8, o, "        1              2     1.104183431     14.52481849    97.86435\n") != null);
    try expect(std.mem.indexOf(u8, o, "        4              2    0.6230493461      0.00000000     9.72E-6\n") != null);
    try expect(std.mem.indexOf(u8, o, "theta1          155.1      1.0046       1     154.40      <.0001       152.5       157.7\n") != null);
    try expect(std.mem.indexOf(u8, o, "theta2         0.0651     0.00347       1      18.77      <.0001      0.0561      0.0740\n") != null);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
}

test "STAT-HPNLMOD-001 ALPHA, NOITPRINT, NOPRINT and GCONV follow the SAS listings" {
    const src_tail = "parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;";
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // SAS: ALPHA=0.1 leaves the 95% Parameter Estimates limits unchanged;
    // NOITPRINT drops only the Iteration History table.
    var out: std.ArrayList(u8) = .empty;
    try hp.run(e.cx(), &out, try e.tokens("proc hpnlmod data=enzyme alpha=0.1 noitprint; " ++ src_tail));
    try expect(std.mem.indexOf(u8, out.items, "Iteration History") == null);
    try expect(std.mem.indexOf(u8, out.items, "     160         0.1    13.9401055\n\n         Convergence criterion (GCONV=1E-8) satisfied.          \n\n\n              Fit Statistics\n") != null);
    try expect(std.mem.indexOf(u8, out.items, "Approximate 95% Confidence Limits\n\ntheta1          158.1      0.6737       1     234.67      <.0001       156.6       159.6\n") != null);
    // NOPRINT: no listing.
    var quiet: std.ArrayList(u8) = .empty;
    try hp.run(e.cx(), &quiet, try e.tokens("proc hpnlmod data=enzyme noprint; " ++ src_tail));
    try expectEqual(@as(usize, 0), quiet.items.len);
    // GCONV=1E-9 stops at the same iteration 4 and names its value.
    var tight: std.ArrayList(u8) = .empty;
    try hp.run(e.cx(), &tight, try e.tokens("proc hpnlmod data=enzyme gconv=1e-9; " ++ src_tail));
    try expect(std.mem.indexOf(u8, tight.items, "        4              2    1.4043280401      0.00000000    0.000057\n\n         Convergence criterion (GCONV=1E-9) satisfied.          \n") != null);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
}

test "STAT-HPNLMOD-001 invalid input and unimplemented features fail loudly" {
    const Case = struct { src: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors (rc 1); messages follow the SAS log where SAS gives one.
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; run;", .rc = 1 }, // no MODEL
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(t*conc); model rate ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme alpha=1.5; parms t=1; model rate ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme alpha=0; parms t=1; model rate ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model nosuch ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model c ~ residual(t*conc); run;", .rc = 1 }, // character response
        .{ .src = "proc hpnlmod data=nosuch; parms t=1; model rate ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme bogus; parms t=1; model rate ~ residual(t*conc); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate = t*conc; run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(t*c); run;", .rc = 1 }, // character model variable
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(t*conc); by nosuch; run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(t*conc); frobnicate; run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=e2; by conc; parms t=1; model rate ~ residual(t*conc); run;", .rc = 1 }, // BY data not sorted
        // Valid but not implemented (rc 2, nothing printed).
        .{ .src = "proc hpnlmod data=enzyme gconv=1e-5; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 }, // Gradient column
        .{ .src = "proc hpnlmod data=enzyme gconv=1e-8 2; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme gconv=-1; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 1 },
        .{ .src = "proc hpnlmod data=enzyme tech=newrap; parms t=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme maxiter=10; parms t=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme corr; parms t=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme alpha=0.05 alpha=0.05; parms t=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1 u=2; p = t*conc/(u+conc); model rate ~ residual(p); run;", .rc = 2 }, // programming statement
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ normal(t*conc, 1); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ binary(t); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; bounds t>0; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; estimate 'x' t; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; predict 'x' t out=o; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; performance nthreads=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1 / bestx=1; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms t=1 to 3; model rate ~ residual(t*conc); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 }, // default starting value 1
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(t*conc/(u+conc)); run;", .rc = 2 }, // undeclared parameter
        .{ .src = "proc hpnlmod data=enzyme; parms t=1; model rate ~ residual(sin(t*conc)); run;", .rc = 2 },
        .{ .src = "proc hpnlmod data=enzyme; parms theta1=100 theta2=3; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 }, // damped LM steps
        .{ .src = "proc hpnlmod data=enzyme; parms a=160 b=0.1 c=1; model rate ~ residual(a*conc/(b+conc) + c); run;", .rc = 2 }, // damped / intercept
        .{ .src = "proc hpnlmod data=enzyme; parms t=160; model rate ~ residual(t*conc/(0.1+conc)); run;", .rc = 2 }, // one-parameter layout
        .{ .src = "proc hpnlmod data=enzyme; where conc > 99; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 }, // empty input
        .{ .src = "proc hpnlmod data=enzyme; where conc > 2.4; parms theta1=160 theta2=0.1; model rate ~ residual(theta1*conc/(theta2+conc)); run;", .rc = 2 }, // n <= p + 1
    };
    for (cases) |case| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        var out: std.ArrayList(u8) = .empty;
        const result = hp.run(e.cx(), &out, try e.tokens(case.src));
        const rc = diag.exitCode(diag.gapHit(), e.diags.hasErrors());
        if (result) |_| {
            std.debug.print("unexpected success: {s}\n", .{case.src});
            return error.TestUnexpectedResult;
        } else |_| {}
        expectEqual(case.rc, rc) catch |err| {
            std.debug.print("wrong rc for: {s}\n", .{case.src});
            return err;
        };
        try expectEqual(@as(usize, 0), out.items.len);
    }
    diag.resetGap();
}
