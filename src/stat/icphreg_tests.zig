//! STAT-ICPHREG-001 permanent checks: declarations, variable roles,
//! observation selection (Missing Values, p.5246; response table, p.5212),
//! CLASS level ordering, the likelihood kernel against a closed-form
//! maximiser, user errors and the loud gaps. Data are invented.
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const icphreg = @import("icphreg.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns lo hi g x f s. Row comments name the rule each row exercises.
fn roles(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("lo", .num);
    _ = try ds.addColumn("hi", .num);
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "x", "f", "s" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_]struct { f64, f64, []const u8, f64, f64, f64 }{
        .{ nan, 4, "B", 1, 1, 1 }, // left censored
        .{ 3, nan, "A", 2, 2, 1 }, // right censored
        .{ 2, 5, "A", 1, 1, 2 }, // interval censored
        .{ nan, nan, "A", 1, 1, 1 }, // both bounds missing: not used
        .{ 6, 5, "A", 1, 1, 1 }, // lower > upper: not used
        .{ 1, 2, "", 1, 1, 1 }, // missing CLASS value in the model
        .{ 1, 2, "A", nan, 1, 1 }, // missing continuous explanatory value
        .{ 1, 2, "C", 1, 0, 1 }, // zero frequency
        .{ 1, 2, "C", 1, nan, 1 }, // missing frequency
        .{ 1, 2, "C", 1, 1, nan }, // missing stratum
        .{ 4, 4, "B", 1, 1, 1 }, // lower = upper: exact
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8, log: []const u8 };
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
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        icphreg.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items, .log = try d.render() };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !icphreg.Spec {
        return icphreg.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
    fn expectFails(self: *Fixture, source: []const u8, rc: u8, text: []const u8) !void {
        const o = try self.outcome(source);
        try expectEqual(@as(usize, 0), o.out.len);
        if (o.rc != rc or std.mem.indexOf(u8, o.log, text) == null) {
            std.debug.print("rc {d} (want {d}); missing '{s}' in log:\n{s}\n", .{ o.rc, rc, text, o.log });
            return error.TestUnexpectedResult;
        }
    }
};

test "STAT-ICPHREG-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc icphreg; model (lo, hi) = x;");
    try expectEqual(@as(usize, 0), plain.lower);
    try expectEqual(@as(usize, 1), plain.upper);
    try expect(plain.intervals == null and plain.freq == null and !plain.noprint and !plain.ithistory and !plain.class_desc);
    try expectEqual(@as(f64, 0.05), plain.alpha);
    try expectEqual(@as(usize, 20), plain.namelen);
    try expectEqual(@as(usize, 0), plain.classes.len + plain.by_cols.len + plain.strata.len + plain.ids.len + plain.hazard_ratios.len);

    const full = try fx.spec(&d, "proc icphreg data=sample alpha=0.1 namelen=40 noprint ithistory nothreads threads=2; class g / desc; model (lo hi) = g x / basehaz=pch(intervals=(2, 4.5)); freq f; strata s / missing; id x g; hazardratio g; by x;");
    try std.testing.expectEqualSlices(usize, &.{ 2, 3 }, full.effects);
    try std.testing.expectEqualSlices(usize, &.{2}, full.classes);
    try std.testing.expectEqualSlices(f64, &.{ 2, 4.5 }, full.intervals.?);
    try expectEqual(@as(?usize, 4), full.freq);
    try std.testing.expectEqualSlices(usize, &.{5}, full.strata);
    try std.testing.expectEqualSlices(usize, &.{ 3, 2 }, full.ids);
    try std.testing.expectEqualSlices(usize, &.{2}, full.hazard_ratios);
    try std.testing.expectEqualSlices(usize, &.{3}, full.by_cols);
    try expect(full.noprint and full.ithistory and full.class_desc and full.strata_missing);
    try expectEqual(@as(f64, 0.1), full.alpha);
    try expectEqual(@as(usize, 40), full.namelen);
    // Documented aliases B= / BASE= and PIECEWISE / INTERVAL=.
    const alias = try fx.spec(&d, "proc icphreg; model (lo,hi) = x / b=piecewise(interval=(3));");
    try std.testing.expectEqualSlices(f64, &.{3}, alias.intervals.?);
}

test "STAT-ICPHREG-001 observation selection and level ordering" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const s = try fx.spec(&d, "proc icphreg; class g / descending; model (lo, hi) = g x; freq f; strata s;");
    const sel = try icphreg.select(fx.a(), s.input.ds, s, s.input.ds.rows.items);
    try expectEqual(@as(usize, 11), sel.read);
    try expectEqual(@as(usize, 4), sel.used);
    try expectEqual(@as(usize, 1), sel.left);
    try expectEqual(@as(usize, 1), sel.right);
    try expectEqual(@as(usize, 1), sel.interval);
    try expectEqual(@as(usize, 1), sel.exact);
    const E = icphreg.Exclusion;
    const want = [_]?E{ null, null, null, .missing_bounds, .lower_above_upper, .missing_explanatory, .missing_explanatory, .nonpositive_frequency, .missing_frequency, .missing_strata, null };
    for (sel.status, want) |st, w| {
        if (w) |why| {
            try expect(st == .excluded);
            try expectEqual(why, st.excluded);
        } else try expect(st != .excluded);
    }
    // Levels over the used observations only (the C rows are excluded), DESC.
    try expectEqual(@as(usize, 1), sel.classes.len);
    try expectEqual(@as(usize, 2), sel.classes[0].labels.len);
    try std.testing.expectEqualStrings("B", sel.classes[0].labels[0]);
    try std.testing.expectEqualStrings("A", sel.classes[0].labels[1]);
    // STRATA / MISSING keeps a missing stratum.
    const m = try fx.spec(&d, "proc icphreg; model (lo, hi) = x; strata s / missing;");
    const ms = try icphreg.select(fx.a(), m.input.ds, m, m.input.ds.rows.items);
    try expect(ms.status[9] != .excluded);
}

test "STAT-ICPHREG-001 likelihood kernel matches a closed-form maximiser" {
    // One interval, no covariates; 1 left-censored and 3 right-censored at
    // T=2: L = (1-S)S^3 with S = exp(-2h), maximised at S = 3/4, so
    // h = ln(4/3)/2 and l''(h) = -4S/(1-S)^2 = -48.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cuts: []const f64 = &.{};
    const d2 = try icphreg.exposures(a, cuts, 2);
    const zero = try icphreg.exposures(a, cuts, 0);
    const obs = [_]icphreg.Obs{
        .{ .lower = zero, .upper = d2, .x = &.{} },
        .{ .lower = d2, .upper = null, .x = &.{} },
        .{ .lower = d2, .upper = null, .x = &.{} },
        .{ .lower = d2, .upper = null, .x = &.{} },
    };
    const f = try icphreg.fit(a, &obs, 1, 1, 0.5);
    try std.testing.expectApproxEqAbs(@log(4.0 / 3.0) / 2.0, f.theta[0], 1e-10);
    try std.testing.expectApproxEqAbs(1.0 / 48.0, f.cov[0], 1e-9);
    try std.testing.expectApproxEqAbs(@log(0.25) + 3 * @log(0.75), f.ll, 1e-10);

    // Analytic gradient/Hessian against central differences: two intervals,
    // one covariate, left-, right- and interval-censored observations.
    const c2: []const f64 = &.{1.5};
    const o2 = [_]icphreg.Obs{
        .{ .lower = try icphreg.exposures(a, c2, 0), .upper = try icphreg.exposures(a, c2, 2), .x = &.{1} },
        .{ .lower = try icphreg.exposures(a, c2, 1), .upper = null, .x = &.{0} },
        .{ .lower = try icphreg.exposures(a, c2, 0.5), .upper = try icphreg.exposures(a, c2, 3), .x = &.{-1} },
    };
    const theta = [_]f64{ 0.3, 0.7, 0.4 };
    var g: [3]f64 = undefined;
    var h: [9]f64 = undefined;
    var g2: [3]f64 = undefined;
    var h2: [9]f64 = undefined;
    _ = icphreg.evaluate(&o2, 2, &theta, &g, &h);
    for (0..3) |j| {
        var tp = theta;
        var tm = theta;
        tp[j] += 1e-6;
        tm[j] -= 1e-6;
        const lp = icphreg.evaluate(&o2, 2, &tp, &g2, &h2);
        const gp = g2;
        const lm = icphreg.evaluate(&o2, 2, &tm, &g2, &h2);
        try std.testing.expectApproxEqAbs((lp - lm) / 2e-6, g[j], 1e-6);
        for (0..3) |q| try std.testing.expectApproxEqAbs((gp[q] - g2[q]) / 2e-6, h[q * 3 + j], 1e-5);
    }
    try std.testing.expectApproxEqAbs(1.959963984540054, icphreg.zQuantile(0.05), 1e-9);
}

test "STAT-ICPHREG-001 user errors fail with rc 1" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    try fx.expectFails("proc icphreg alpha=1.5; model (lo,hi) = x;", 1, "ALPHA= must be between 0 and 1");
    try fx.expectFails("proc icphreg namelen=5; model (lo,hi) = x;", 1, "NAMELEN=5 is outside");
    try fx.expectFails("proc icphreg; class g;", 1, "MODEL statement required");
    try fx.expectFails("proc icphreg; model (lo,nope) = x;", 1, "Variable nope not found.");
    try fx.expectFails("proc icphreg; model (lo,g) = x;", 1, "upper-bound variable g must be numeric");
    try fx.expectFails("proc icphreg; model (lo,hi) = g;", 1, "character variable g in the MODEL statement must be a CLASS variable");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(intervals=(0));", 1, "INTERVALS= values must be positive");
    try fx.expectFails("proc icphreg; model (lo,hi) = x; hazardratio f;", 1, "HAZARDRATIO variable f is not a MODEL effect");
    try fx.expectFails("proc icphreg; model (lo,hi) = x; frobnicate;", 1, "invalid statement");
    try fx.expectFails("proc icphreg; model (lo,hi) = x; freq g;", 1, "FREQ variable g must be numeric");
}

test "STAT-ICPHREG-001 unimplemented features are loud rc 2 gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const where = " where lo ne 4 or hi ne 4;";
    try fx.expectFails("proc icphreg; model (lo,hi) = x;" ++ where, 2, "default BASEHAZ=");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(nintervals=3);", 2, "NINTERVAL=");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=splines;", 2, "BASEHAZ=splines is not implemented");
    try fx.expectFails("proc icphreg ithistory; model (lo,hi) = x / basehaz=pch(intervals=(3));" ++ where, 2, "ITHISTORY is not implemented");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(intervals=(3)); freq f;" ++ where, 2, "FREQ statement listing");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(intervals=(3)); strata s;" ++ where, 2, "STRATA statement");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(intervals=(3));", 2, "exact (lower = upper) responses");
    try fx.expectFails("proc icphreg plots=all; model (lo,hi) = x;", 2, "option plots is not implemented");
    try fx.expectFails("proc icphreg; model (lo,hi) = x*g;", 2, "interaction, nested and bar effects");
    try fx.expectFails("proc icphreg; model lo = x;", 2, "time*censor(list) response form");
    try fx.expectFails("proc icphreg; model (lo,hi) = x; output out=o;", 2, "output statement is not implemented");
    try fx.expectFails("proc icphreg; class g(ref='A'); model (lo,hi) = g;", 2, "CLASS variable options");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / covb;", 2, "MODEL option covb is not implemented");
    try fx.expectFails("proc icphreg; model (lo,hi) = x / basehaz=pch(intervals=(3)); hazardratio x / diff=ref;", 2, "HAZARDRATIO options");
}
