//! STAT-MI-001 permanent checks: declarations, roles, observation selection,
//! missing data patterns, descriptive statistics, EM maximum likelihood and
//! execution boundaries. Data are invented, except the Fitness1 sample
//! published in the SAS/STAT 15.4 guide (chapter 82), named where used.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const mi = @import("mi.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const close = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

/// Columns Height Weight n g tag. Row comments name the rule each row exercises.
fn roles(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "Height", "Weight", "n", "g" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("tag", .char);
    const rows = [_][4]f64{
        .{ 10, 20, 2, 1 },
        .{ 12, nan, 1, 1 }, // Weight missing
        .{ nan, 30, 1, 1 }, // Height missing
        .{ 14, 28, 2.7, 2 }, // FREQ truncates to 2
        .{ 11, 25, 0, 2 }, // FREQ below 1
        .{ 16, nan, nan, 2 }, // missing FREQ
        .{ 13, 26, 0.9, 2 }, // FREQ below 1 before truncation
        .{ 15, 21, -3, 2 }, // negative FREQ
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .str = "a" } });
    return ds;
}

/// The Fitness1 sample of the SAS/STAT 15.4 guide, chapter 82.
const fitness = [_][3]f64{
    .{ 44.609, 11.37, 178 }, .{ 45.313, 10.07, 185 }, .{ 54.297, 8.65, 156 }, .{ 59.571, nan, nan },
    .{ 49.874, 9.22, nan },  .{ 44.811, 11.63, 176 }, .{ nan, 11.95, 176 },   .{ nan, 10.85, nan },
    .{ 39.442, 13.08, 174 }, .{ 60.055, 8.63, 170 },  .{ 50.541, nan, nan },  .{ 37.388, 14.03, 186 },
    .{ 44.754, 11.12, 176 }, .{ 47.273, nan, nan },   .{ 51.855, 10.33, 166 }, .{ 49.156, 8.95, 180 },
    .{ 40.836, 10.95, 168 }, .{ 46.672, 10.00, nan }, .{ 46.774, 10.25, nan }, .{ 50.388, 10.08, 168 },
    .{ 39.407, 12.63, 174 }, .{ 46.080, 11.17, 156 }, .{ 45.441, 9.63, 164 }, .{ nan, 8.92, nan },
    .{ 45.118, 11.08, nan }, .{ 39.203, 12.88, 168 }, .{ 45.790, 10.47, 186 }, .{ 50.545, 9.93, 148 },
    .{ 48.673, 9.40, 186 },  .{ 47.920, 11.50, 170 }, .{ 47.467, 10.50, 170 },
};
fn fitness1(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "Fitness1");
    for ([_][]const u8{ "Oxygen", "RunTime", "RunPulse" }) |name| _ = try ds.addColumn(name, .num);
    for (fitness) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    return ds;
}

fn selection(a: A, comptime p: usize, rows: []const [p]f64, w: ?[]const f64) !mi.Selected {
    const x = try a.alloc([]const f64, rows.len);
    const f = try a.alloc(f64, rows.len);
    for (rows, x, 0..) |*r, *slot, i| {
        slot.* = try a.dupe(f64, r);
        f[i] = if (w) |weights| weights[i] else 1;
    }
    return .{ .x = x, .w = f, .empty = 0 };
}

const Outcome = struct { rc: u8, out: []const u8, message: []const u8 };
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
        mi.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items, .message = "" };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !mi.Spec {
        return mi.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
};

test "STAT-MI-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc mi;");
    // No VAR statement: every numeric variable.
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, plain.vars);
    try expect(plain.frequency == null and plain.em == null and plain.nimpute == null and plain.seed == null);
    try expect(!plain.simple and !plain.noprint and !plain.notsorted);
    try expectEqual(@as(usize, 0), plain.by_cols.len);
    // Without VAR the BY and FREQ variables are not analysis variables.
    const implied = try fx.spec(&d, "proc mi data=sample; freq n; by g;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, implied.vars);
    const full = try fx.spec(&d, "proc mi data=work.sample seed=42 nimpute=0 simple noprint; var Weight Height; freq n; by n; by descending g notsorted; em itprint outem=work.est maxiter=50 converge=1e-6;");
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, full.vars);
    try expectEqual(@as(?usize, 2), full.frequency);
    try expectEqual(@as(?usize, 0), full.nimpute);
    try expectEqual(@as(?i64, 42), full.seed);
    try expect(full.simple and full.noprint and full.notsorted);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{3}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(full.em.?.itprint);
    try std.testing.expectEqualStrings("work.est", full.em.?.outem.?);
    try expectEqual(@as(usize, 50), full.em.?.maxiter);
    try expectEqual(@as(f64, 1e-6), full.em.?.converge);
    const defaults = (try fx.spec(&d, "proc mi; em;")).em.?;
    try expect(!defaults.itprint and defaults.outem == null);
    try expectEqual(@as(usize, 200), defaults.maxiter);
    try expectEqual(@as(f64, 1e-4), defaults.converge);
    try expectEqual(@as(f64, 0.5), (try fx.spec(&d, "proc mi; em xconv=0.5;")).em.?.converge);
    try expect(!d.hasErrors());
}

test "STAT-MI-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc mi bogus seed=1 nimpute=0;", 1 },
        .{ "proc mi data=nosuch seed=1 nimpute=0;", 1 },
        .{ "proc mi seed=1 nimpute=0; var nosuch;", 1 },
        .{ "proc mi seed=1 nimpute=0; var;", 1 },
        .{ "proc mi seed=1 nimpute=0; var Height tag;", 1 }, // character without CLASS
        .{ "proc mi seed=1 nimpute=0; freq tag;", 1 },
        .{ "proc mi seed=1 nimpute=0; freq nosuch;", 1 },
        .{ "proc mi seed=1 nimpute=0; freq n g;", 1 },
        .{ "proc mi seed=1 nimpute=0; by nosuch;", 1 },
        .{ "proc mi seed=1 nimpute=1.5;", 1 },
        .{ "proc mi seed=x nimpute=0;", 1 },
        .{ "proc mi seed=1 nimpute=0; em converge=2;", 1 },
        .{ "proc mi seed=1 nimpute=0; em maxiter=0;", 1 },
        .{ "proc mi seed=1 nimpute=0; em bogus;", 1 },
        .{ "proc mi seed=1 nimpute=0; bogus Height;", 1 },
        .{ "proc mi seed=1 nimpute=0; var Height Weight; by descending g;", 1 }, // not sorted descending
        // Valid SAS that is not implemented must fail as a gap.
        .{ "proc mi seed=1; var Height Weight;", 2 }, // default NIMPUTE imputes
        .{ "proc mi seed=1 nimpute=5; var Height Weight;", 2 },
        .{ "proc mi nimpute=0; var Height Weight;", 2 }, // clock seed
        .{ "proc mi seed=0 nimpute=0; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 out=imputed; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 alpha=0.1; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 mu0=1 2; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 minimum=0; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 maximum=9; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 round=1; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0 singular=1e-8; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; class tag; var Height tag;", 2 },
        .{ "proc mi seed=1 nimpute=0; mcmc nbiter=10; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; monotone reg; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; fcs; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; transform log(Height); var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; mnar adjust(Height); var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; em initial=cc; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; em outiter=it; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; em outem=e(keep=Height); var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; var Height Weight; var g;", 2 },
        .{ "proc mi seed=1 nimpute=0; var Height Height;", 2 },
        .{ "proc mi seed=1 nimpute=0; freq n; freq g;", 2 },
        .{ "proc mi seed=1 nimpute=0; em; em;", 2 },
        .{ "proc mi seed=1 nimpute=0; var Height n; freq n;", 2 },
        // The group mean of n over the complete rows is 0.52, outside the
        // verified display range.
        .{ "proc mi seed=1 nimpute=0; var Height Weight n;", 2 },
        // SIMPLE and EM column widths are verified for 8-character names only.
        .{ "proc mi seed=1 nimpute=0 simple; var Height Weight;", 2 },
        .{ "proc mi seed=1 nimpute=0; em; var Height Weight;", 2 },
    }) |case| {
        const got = try fx.outcome(case[0]);
        if (got.rc != case[1]) std.debug.print("unexpected rc {d} for: {s}\n", .{ got.rc, case[0] });
        try expectEqual(case[1], got.rc);
        // Nothing is printed for a failed step.
        try expectEqual(@as(usize, 0), got.out.len);
    }
}

test "STAT-MI-001 FREQ selection and missing data patterns" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, "proc mi; var Height Weight; freq n;");
    const sel = try mi.select(fx.a(), s, s.input.ds.rows.items);
    // Integer part of FREQ; values below 1 and missing drop the observation.
    try std.testing.expectEqualSlices(f64, &.{ 2, 1, 1, 2 }, sel.w);
    try expectEqual(@as(usize, 0), sel.empty);
    const groups = try mi.patterns(fx.a(), 2, sel);
    try expectEqual(@as(usize, 3), groups.len);
    // Observed before missing, in variable order: XX, X., .X
    try expectEqual(@as(u64, 0b11), groups[0].mask);
    try expectEqual(@as(u64, 0b01), groups[1].mask);
    try expectEqual(@as(u64, 0b10), groups[2].mask);
    try expectEqual(@as(f64, 4), groups[0].freq);
    try expectEqual(@as(f64, 12), groups[0].means[0]); // (2*10 + 2*14)/4
    try expectEqual(@as(f64, 24), groups[0].means[1]); // (2*20 + 2*28)/4
    try expectEqual(@as(f64, 1), groups[1].freq);
    try expectEqual(@as(f64, 12), groups[1].means[0]);
    try expectEqual(@as(f64, 30), groups[2].means[1]);
    // Without FREQ every observation counts once; all-missing rows are counted.
    const plain = try fx.spec(&d, "proc mi; var Height Weight;");
    try expectEqual(@as(usize, 8), (try mi.select(fx.a(), plain, plain.input.ds.rows.items)).x.len);
}

test "STAT-MI-001 available-case statistics and pairwise correlations by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // x observed {1,2,3,6}: mean 3, SS 14, sd sqrt(14/3). Pairs (1,2),(2,4),(6,3):
    // means 3 and 3, Sxx 14, Syy 2, Sxy 1 -> r = 1/sqrt(28).
    const sel = try selection(a, 2, &.{ .{ 1, 2 }, .{ 2, 4 }, .{ 3, nan }, .{ 6, 3 }, .{ nan, 9 } }, null);
    const u = mi.univariate(sel, 0);
    try expectEqual(@as(f64, 4), u.n);
    try close(@as(f64, 3), u.mean, 1e-14);
    try close(@sqrt(14.0 / 3.0), u.sd, 1e-14);
    try expectEqual(@as(f64, 1), u.min);
    try expectEqual(@as(f64, 6), u.max);
    try close(1.0 / @sqrt(28.0), mi.pairwise(sel, 0, 1).?, 1e-14);
    // A frequency of 2 equals the observation listed twice: x {1,1,5}, mean 7/3.
    const weighted = try selection(a, 1, &.{ .{1}, .{5} }, &.{ 2, 1 });
    const w = mi.univariate(weighted, 0);
    try expectEqual(@as(f64, 3), w.n);
    try close(7.0 / 3.0, w.mean, 1e-14);
    try close(@sqrt((2.0 * 16.0 / 9.0 + 64.0 / 9.0) / 2.0), w.sd, 1e-14);
    // Undefined correlations are reported as such.
    try expect(mi.pairwise(try selection(a, 2, &.{ .{ 1, nan }, .{ nan, 2 }, .{ 3, 4 } }, null), 0, 1) == null);
    try expect(mi.pairwise(try selection(a, 2, &.{ .{ 1, 5 }, .{ 1, 6 } }, null), 0, 1) == null);
}

test "STAT-MI-001 EM equals the closed-form maximum likelihood estimates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Complete data: the MLE is the mean and the covariance with divisor n.
    // x {1,2,3,6}, y {2,4,3,3}: means 3, 3; Sxx 14, Syy 2, Sxy 1; n = 4.
    const complete = try mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 2, 4 }, .{ 3, 3 }, .{ 6, 3 } }, null), 200, 1e-4);
    try expect(complete.converged);
    try close(@as(f64, 3), complete.mean[0], 1e-12);
    try close(@as(f64, 3), complete.mean[1], 1e-12);
    try close(@as(f64, 3.5), complete.cov[0], 1e-12);
    try close(@as(f64, 0.25), complete.cov[1], 1e-12);
    try close(@as(f64, 0.25), complete.cov[2], 1e-12);
    try close(@as(f64, 0.5), complete.cov[3], 1e-12);
    // Start: available-case means, variances with divisor n - 1, no covariance.
    try close(14.0 / 3.0, complete.initial_cov[0], 1e-12);
    try expectEqual(@as(f64, 0), complete.initial_cov[1]);
    // -2 log L without the constant at the start: 4 log(14/3 * 2/3) + 3 + 3.
    try close(4 * @log(14.0 / 3.0 * 2.0 / 3.0) + 6, complete.history[0].neg2ll, 1e-12);

    // Monotone pattern (x always observed, y missing in the last two rows):
    // the factored likelihood gives the MLE in closed form.
    //   x {1,2,3,4,6,8}: mean 4, SS 9+4+1+0+4+16 = 34, variance (divisor 6) 34/6.
    //   y on x over the four complete rows (x 1,2,3,4; y 2,3,5,4):
    //   means 2.5 and 3.5, Sxx 5, Sxy 4, Syy 5 -> slope 0.8,
    //   intercept 1.5, residual variance (5 - 0.8*4)/4 = 0.45.
    //   mu_y = 1.5 + 0.8*4 = 4.7; cov = 0.8*34/6; var_y = 0.45 + 0.64*34/6.
    const monotone = try mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 4 }, .{ 6, nan }, .{ 8, nan } }, null), 5000, 1e-12);
    try expect(monotone.converged);
    try close(@as(f64, 4), monotone.mean[0], 1e-9);
    try close(@as(f64, 4.7), monotone.mean[1], 1e-8);
    try close(34.0 / 6.0, monotone.cov[0], 1e-8);
    try close(0.8 * 34.0 / 6.0, monotone.cov[1], 1e-8);
    try close(0.45 + 0.64 * 34.0 / 6.0, monotone.cov[3], 1e-8);
    // The likelihood never decreases (-2 log L never increases).
    for (monotone.history[1..], monotone.history[0 .. monotone.history.len - 1]) |next, previous| try expect(next.neg2ll <= previous.neg2ll + 1e-9);

    // A frequency of 2 equals the observation listed twice.
    const listed = try mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 4 }, .{ 6, nan } }, null), 200, 1e-4);
    const counted = try mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 4 }, .{ 6, nan } }, &.{ 2, 1, 1, 1, 1 }), 200, 1e-4);
    try expectEqual(listed.iterations, counted.iterations);
    for (listed.mean, counted.mean) |l, c| try close(l, c, 1e-12);
    for (listed.cov, counted.cov) |l, c| try close(l, c, 1e-12);

    // A constant variable has no positive starting variance.
    try std.testing.expectError(error.Singular, mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 1, 5 } }, null), 200, 1e-4));
    // MAXITER reached before convergence is reported, not hidden.
    const short = try mi.em(a, 2, try selection(a, 2, &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 4 }, .{ 6, nan }, .{ 8, nan } }, null), 2, 1e-12);
    try expect(!short.converged);
    try expectEqual(@as(usize, 2), short.iterations);
}

test "STAT-MI-001 EM on the published Fitness1 sample matches the SAS listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try mi.em(a, 3, try selection(a, 3, &fitness, null), 200, 1e-4);
    // SAS: "The EM algorithm (MLE) converges in 12 iterations."
    try expect(r.converged);
    try expectEqual(@as(usize, 12), r.iterations);
    try expectEqual(@as(usize, 13), r.history.len);
    // The listing prints six decimals: half a unit of the last place.
    const tol = 0.5e-6;
    for ([_]f64{ 289.544782, 263.549489, 255.851312, 254.616428, 254.494971, 254.483973, 254.482920, 254.482813, 254.482801, 254.482800, 254.482800, 254.482800, 254.482800 }, r.history) |expected, it| try close(expected, it.neg2ll, tol);
    for ([_]f64{ 47.139089, 10.603506, 171.538203 }, r.history[2].mean) |expected, actual| try close(expected, actual, tol);
    for ([_]f64{ 47.104077, 10.554858, 171.381669 }, r.mean) |expected, actual| try close(expected, actual, tol);
    for ([_]f64{ 27.797931, -6.457975, -18.031298, -6.457975, 2.015514, 3.516287, -18.031298, 3.516287, 97.766857 }, r.cov) |expected, actual| try close(expected, actual, tol);
    for ([_]f64{ 29.301078, 0, 0, 0, 1.904067, 0, 0, 0, 102.885281 }, r.initial_cov) |expected, actual| try close(expected, actual, tol);
    const sel = try selection(a, 3, &fitness, null);
    try close(@as(f64, -0.849118562), mi.pairwise(sel, 0, 1).?, 0.5e-9);
    try close(@as(f64, -0.343961742), mi.pairwise(sel, 0, 2).?, 0.5e-9);
    try close(@as(f64, 0.247258191), mi.pairwise(sel, 1, 2).?, 0.5e-9);
}

test "STAT-MI-001 OUTEM data set, NOPRINT and BY boundaries" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(fitness1);
    const quiet = try fx.outcome("proc mi data=Fitness1 seed=7 nimpute=0 noprint; em outem=est; var Oxygen RunTime RunPulse;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
    const est = fx.lib.find("est").?;
    try expectEqual(@as(usize, 5), est.columns.items.len);
    try expectEqual(@as(usize, 4), est.rows.items.len);
    for ([_][]const u8{ "_TYPE_", "_NAME_", "Oxygen", "RunTime", "RunPulse" }, est.columns.items) |name, column| try std.testing.expectEqualStrings(name, column.name);
    try std.testing.expectEqualStrings("MEAN", est.rows.items[0][0].str);
    try std.testing.expectEqualStrings("", est.rows.items[0][1].str);
    try close(@as(f64, 47.104077), est.rows.items[0][2].num, 0.5e-6);
    try std.testing.expectEqualStrings("COV", est.rows.items[3][0].str);
    try std.testing.expectEqualStrings("RunPulse", est.rows.items[3][1].str);
    try close(@as(f64, 97.766857), est.rows.items[3][4].num, 0.5e-6);
    try close(@as(f64, -18.031298), est.rows.items[3][2].num, 0.5e-6);
    // The seed is shown as given and the listing starts with the procedure title.
    const shown = try fx.outcome("proc mi data=Fitness1 seed=7 nimpute=0; var Oxygen RunTime RunPulse;");
    try expectEqual(@as(u8, 0), shown.rc);
    try expect(std.mem.startsWith(u8, shown.out, "\nThe MI Procedure\n\n                     Model Information\n\nData Set                             WORK.FITNESS1          \n"));
    try expect(std.mem.indexOf(u8, shown.out, "Seed for random number generator     7                      \n") != null);
    // Neither SIMPLE nor EM was requested.
    try expect(std.mem.indexOf(u8, shown.out, "Univariate") == null and std.mem.indexOf(u8, shown.out, "EM (MLE)") == null);
    try expect(std.mem.endsWith(u8, shown.out, "    5    .         X       .               2        6.45               .        9.885000               .\n"));
}
