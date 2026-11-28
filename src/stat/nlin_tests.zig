//! STAT-NLIN-001 permanent tests: PROC statement options, PARAMETERS/MODEL/
//! BY/ID roles, missing-value selection, the Marquardt kernel and loud
//! execution boundaries. The enzyme data are the published Getting Started
//! sample of the chapter; its expected values are the published SAS listing.
//! The other data are invented (D-011) and their expected values are
//! closed-form least squares done by hand, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const nlin = @import("nlin.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const enzyme = [_][2]f64{ .{ 0.26, 124.7 }, .{ 0.30, 126.9 }, .{ 0.48, 135.9 }, .{ 0.50, 137.6 }, .{ 0.54, 139.6 }, .{ 0.68, 141.1 }, .{ 0.82, 142.8 }, .{ 1.14, 147.6 }, .{ 1.28, 149.8 }, .{ 1.38, 149.4 }, .{ 1.80, 153.9 }, .{ 2.30, 152.5 }, .{ 2.44, 154.5 }, .{ 2.48, 154.7 } };
// columns: 0 g, 1 x, 2 y, 3 c (character). Group 1 keeps (1,2) (2,3) (3,7).
const Row = struct { g: f64, x: f64, y: f64 };
const sample = [_]Row{
    .{ .g = 1, .x = 1, .y = 2 },
    .{ .g = 1, .x = nan, .y = 5 }, // missing model variable
    .{ .g = 1, .x = 2, .y = 3 },
    .{ .g = 1, .x = 4, .y = nan }, // missing dependent variable
    .{ .g = 1, .x = 3, .y = 7 },
    .{ .g = 2, .x = 1, .y = 1 },
    .{ .g = 2, .x = 2, .y = 5 },
    .{ .g = 2, .x = 3, .y = 6 },
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
        _ = try e.addColumn("Concentration", .num);
        _ = try e.addColumn("Velocity", .num);
        for (enzyme) |r| try e.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
        try self.lib.put("enzyme", e);
        const s = try a.create(Dataset);
        s.* = Dataset.init(a, "sample");
        for ([_][]const u8{ "g", "x", "y" }) |n| _ = try s.addColumn(n, .num);
        _ = try s.addColumn("c", .char);
        for (sample) |r| try s.appendRow(&.{ .{ .num = r.g }, .{ .num = r.x }, .{ .num = r.y }, .{ .str = "a" } });
        try self.lib.put("sample", s);
        diag.resetGap();
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn tokens(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !nlin.Spec {
        return nlin.parse(self.cx(), try self.tokens(source));
    }
};

test "STAT-NLIN-001 PROC statement defaults, explicit options and statement roles" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Defaults: METHOD=GAUSS, CONVERGE=1E-5, MAXITER=100, ALPHA=0.05, most recent data set.
    const d = try e.parse("proc nlin; parms b=1; model y = b*x; run;");
    try expectEqual(nlin.Method.gauss, d.method);
    try expect(!d.hougaard);
    try expectEqual(@as(f64, 1e-5), d.converge);
    try expectEqual(@as(usize, 100), d.maxiter);
    try expectEqual(@as(f64, 0.05), d.alpha);
    try expectEqual(@as(usize, 2), d.dependent);
    try std.testing.expectEqualSlices(usize, &.{1}, d.model_cols);
    try expectEqual(@as(usize, 0), d.by_cols.len + d.id_cols.len + d.later.len + d.gap_options.len);
    try std.testing.expectEqualStrings("sample", d.input.ds.name);

    const s = try e.parse("proc nlin data=work.sample method=marquardt hougaard converge=1e-8 maxiter=20 alpha=0.1 best=5 noitprint; parameters a=-2 b=0 to 1 by 0.25; model y = a*exp(b*x); by g; id c x; output out=o p=p; run;");
    try expectEqual(nlin.Method.marquardt, s.method);
    try expect(s.hougaard);
    try expectEqual(@as(f64, 1e-8), s.converge);
    try expectEqual(@as(usize, 20), s.maxiter);
    try expectEqual(@as(f64, 0.1), s.alpha);
    try expectEqual(@as(usize, 2), s.gap_options.len);
    try std.testing.expectEqualStrings("best", s.gap_options[0]);
    try expectEqual(@as(usize, 2), s.params.len);
    try std.testing.expectEqualStrings("a", s.params[0].name);
    try std.testing.expectEqualSlices(f64, &.{-2}, s.params[0].values);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0.25, 0.5, 0.75, 1 }, s.params[1].values);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1 }, s.id_cols);
    try std.testing.expectEqualStrings("output", s.later[0]);
    try expectEqual(nlin.Method.newton, (try e.parse("proc nlin data=enzyme method=newton; parms t=1; model Velocity = t*Concentration; run;")).method);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
}

test "STAT-NLIN-001 Marquardt fit reproduces the published enzyme listing" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc nlin data=Enzyme method=marquardt hougaard; parms theta1=155 theta2=0 to 0.07 by 0.01; model Velocity = theta1*Concentration / (theta2 + Concentration); run;");
    const f = try nlin.fit(e.cx(), s, s.input.ds.rows.items);
    // Reference listing values (printed precision).
    try expectEqual(@as(usize, 8 * 3), f.grid.len);
    try approx(@as(f64, 3075.4), f.grid[2], 0.05);
    try approx(@as(f64, 58.1130), f.grid[6 * 3 + 2], 5e-5);
    try approx(@as(f64, 87.9662), f.grid[7 * 3 + 2], 5e-5);
    try expectEqual(@as(usize, 3), f.iterations);
    try approx(@as(f64, 0.06), f.history[1], 1e-12); // best grid point starts the fit
    try approx(@as(f64, 19.7017), f.history[5], 5e-5);
    try approx(@as(f64, 5.861e-6), f.r, 5e-10);
    try approx(@as(f64, 8.569e-7), f.ppc, 5e-11);
    try approx(@as(f64, 0.000078), f.rpc, 5e-7);
    try expectEqual(@as(usize, 1), f.ppc_i);
    try expectEqual(@as(usize, 1), f.rpc_i);
    try approx(@as(f64, 2.902e-7), f.object, 5e-11);
    try approx(@as(f64, 19.66059), f.sse, 5e-6);
    try expectEqual(@as(usize, 14), f.read);
    try expectEqual(@as(usize, 14), f.used);
    try expectEqual(@as(usize, 0), f.missing);
    try approx(@as(f64, 290135), f.total_ss, 0.5);
    try approx(@as(f64, 1.6384), f.mse, 5e-5);
    try approx(@as(f64, 158.1), f.theta[0], 0.05);
    try approx(@as(f64, 0.0741), f.theta[1], 5e-5);
    try approx(@as(f64, 0.6737), f.se[0], 5e-5);
    try approx(@as(f64, 0.00313), f.se[1], 5e-6);
    try approx(@as(f64, 156.6), f.lower[0], 0.05);
    try approx(@as(f64, 159.6), f.upper[0], 0.05);
    try approx(@as(f64, 0.0673), f.lower[1], 5e-5);
    try approx(@as(f64, 0.0809), f.upper[1], 5e-5);
    try approx(@as(f64, 0.0152), f.skew[0], 5e-5);
    try approx(@as(f64, 0.0362), f.skew[1], 5e-5);
    try approx(@as(f64, 0.8300538), f.corr[1], 5e-8);
    try approx(@as(f64, 1), f.corr[3], 0);
    try expectEqual(@as(usize, 6), (try nlin.cell(e.arena.allocator(), 290116.4)).len);
    try std.testing.expectEqualStrings("0.00313", try nlin.cell(e.arena.allocator(), 0.0031288));
    try std.testing.expectEqualStrings("0", try nlin.cell(e.arena.allocator(), 0));
}

test "STAT-NLIN-001 missing values are excluded per BY group and BY groups fit separately" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc nlin data=sample method=marquardt; parms b=1; model y = b*x; by g; run;");
    const rows = s.input.ds.rows.items;
    // Group 1 (hand least squares through the origin on (1,2) (2,3) (3,7)):
    // b = Sxy/Sxx = 29/14, SSE = Syy - Sxy^2/Sxx = 62 - 841/14, df = 2.
    const f = try nlin.fit(e.cx(), s, rows[0..5]);
    try expectEqual(@as(usize, 5), f.read);
    try expectEqual(@as(usize, 3), f.used);
    try expectEqual(@as(usize, 2), f.missing);
    try approx(@as(f64, 29.0 / 14.0), f.theta[0], 1e-6);
    try approx(@as(f64, 62.0 - 841.0 / 14.0), f.sse, 1e-6);
    try approx(@as(f64, 62), f.total_ss, 1e-12);
    try approx(@sqrt((62.0 - 841.0 / 14.0) / 2.0 / 14.0), f.se[0], 1e-6);
    try expectEqual(@as(usize, 0), f.skew.len);
    // Group 2: (1,1) (2,5) (3,6): b = 29/14 as well, SSE = 62 - 841/14.
    const g = try nlin.fit(e.cx(), s, rows[5..8]);
    try expectEqual(@as(usize, 3), g.used);
    try expectEqual(@as(usize, 0), g.missing);
    try approx(@as(f64, 29.0 / 14.0), g.theta[0], 1e-6);

    var out: std.ArrayList(u8) = .empty;
    try nlin.run(e.cx(), &out, try e.tokens("proc nlin data=sample method=marquardt; parms b=1; model y = b*x; by g; run;"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Estimation Summary"));
    try expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "Observations Missing            2"));
    try expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "Observations Missing            0"));
    try expect(std.mem.indexOf(u8, out.items, "Grid Search") == null);
    try expect(std.mem.indexOf(u8, out.items, "Skewness") == null);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
}

test "STAT-NLIN-001 user errors are rc 1 and unimplemented documented features are loud rc 2 gaps" {
    const Case = struct { src: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors.
        .{ .src = "proc nlin data=sample method=marquardt; model y = b*x; run;", .rc = 1 }, // no PARAMETERS
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; run;", .rc = 1 }, // no MODEL
        .{ .src = "proc nlin data=sample method=simplex; parms b=1; model y = b*x; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample bogus; parms b=1; model y = b*x; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample alpha=2; parms b=1; model y = b*x; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample maxiter=-1; parms b=1; model y = b*x; run;", .rc = 1 },
        .{ .src = "proc nlin data=nosuch; parms b=1; model y = b*x; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample; parms b=1 b=2; model y = b*x; run;", .rc = 1 }, // duplicate parameter
        .{ .src = "proc nlin data=sample; parms x=1; model y = x; run;", .rc = 1 }, // parameter named like a variable
        .{ .src = "proc nlin data=sample; parms b=1; model z = b*x; run;", .rc = 1 }, // unknown dependent
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*q; run;", .rc = 1 }, // unknown model variable
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*c; run;", .rc = 1 }, // character model variable
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*x; model y = b; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*x; id nosuch; run;", .rc = 1 },
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*x; by nosuch; run;", .rc = 1 },
        // Documented but not implemented: gaps.
        .{ .src = "proc nlin data=sample; parms b=1; model y = b*x; run;", .rc = 2 }, // default METHOD=GAUSS
        .{ .src = "proc nlin data=sample method=newton; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=gradient; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt noitprint; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt plots=all; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt outest=e; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt hougaard hougaard; parms b=1; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; model y = b*x; output out=o p=p; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; bounds b>0; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; z = b*x; model y = z; run;", .rc = 2 }, // programming statement
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; model y = b*x; der.b = x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1,2; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1 / pdata=p; model y = b*x; run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms a=0 to 1 b=0 to 1; model y = a + b*x; run;", .rc = 2 }, // two-parameter grid
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; model y = sin(b*x); run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; parms b=1; model y = b*(x>1); run;", .rc = 2 },
        .{ .src = "proc nlin data=sample method=marquardt; where g=1; parms a=1 b=1; model y = a + b*x; run;", .rc = 2 }, // intercept: corrected total
        .{ .src = "proc nlin data=sample method=marquardt maxiter=0; parms b=1; model y = b*x; by g; run;", .rc = 2 }, // nonconvergence
        .{ .src = "proc nlin data=sample method=marquardt; where g=1 and x=1; parms b=1; model y = b*x; run;", .rc = 2 }, // n <= p
    };
    for (cases) |case| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        var out: std.ArrayList(u8) = .empty;
        const result = nlin.run(e.cx(), &out, try e.tokens(case.src));
        const rc = diag.exitCode(diag.gapHit(), e.diags.hasErrors());
        if (result) |_| {
            std.debug.print("unexpected success: {s}\n", .{case.src});
            return error.TestUnexpectedResult;
        } else |_| {}
        expectEqual(case.rc, rc) catch |err| {
            std.debug.print("wrong rc for: {s}\n", .{case.src});
            return err;
        };
        // Nothing is printed for a failed step.
        try expectEqual(@as(usize, 0), out.items.len);
    }
    diag.resetGap();
}
