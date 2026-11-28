//! STAT-GLMSELECT-001 permanent tests. Expected numbers come from an exact
//! rational least-squares calculation of the invented data below and the
//! documented criteria formulas (SAS/STAT 15.4 physical pp.4365-4366), not
//! from this implementation. No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const glmselect = @import("glmselect.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// x3 is close to x1 + x2, so x3 enters first and leaves once both are in.
/// Three trailing observations are unusable: missing response, missing
/// regressor, blank CLASS level.
fn sample(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "trial");
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "x1", "x2", "x3", "y", "f", "w", "b" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_][4]f64{ .{ 5, 2, 6, 5 }, .{ 6, 4, 8, 10 }, .{ 7, 8, 15, 15 }, .{ 4, 5, 10, 6 }, .{ 3, 3, 5, 4 }, .{ 2, 9, 11, 11 }, .{ 0, 0, 1, 2 }, .{ 3, 0, 4, 0 }, .{ 5, 8, 14, 14 }, .{ 1, 2, 2, 1 }, .{ 8, 7, 17, 16 }, .{ 8, 4, 14, 9 }, .{ 2, 8, 8, 9 }, .{ 2, 0, 3, -1 }, .{ 1, 1, 1, nan }, .{ 1, nan, 1, 1 }, .{ 1, 1, 1, 1 } };
    for (rows, 0..) |r, k| try ds.appendRow(&.{ .{ .str = if (k == 16) " " else if (k % 2 == 0) "West" else "East" }, .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 } });
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
        const ds = try sample(self.a());
        try self.lib.put(ds.name, ds);
    }
    /// Exit code under D-009 and the listing, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        glmselect.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !glmselect.Spec {
        return glmselect.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
};

fn close(expected: f64, actual: f64) !void {
    try std.testing.expectApproxEqRel(expected, actual, 1e-9);
}

test "STAT-GLMSELECT-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc glmselect; model y = x1;");
    try std.testing.expectEqualStrings("WORK.TRIAL", plain.data_name);
    try expectEqual(@as(usize, 4), plain.response);
    try std.testing.expectEqualSlices(usize, &.{1}, plain.effects);
    try expect(plain.frequency == null and plain.weight == null and plain.seed == null);
    try expect(!plain.noprint and !plain.details_all and !plain.stats_all and !plain.notsorted);
    try expectEqual(@as(usize, 0), plain.classes.len + plain.by_cols.len);
    const full = try fx.spec(&d, "proc glmselect data=trial seed=314159 noprint; class g; class g; by f; by descending b notsorted; freq f; weight w; model Y = X3 g x1 / selection=stepwise details=all stats=all;");
    try std.testing.expectEqualSlices(usize, &.{ 3, 0, 1 }, full.effects);
    try std.testing.expectEqualSlices(usize, &.{0}, full.classes);
    try expect(full.isClass(0) and !full.isClass(1));
    try expectEqual(@as(?usize, 5), full.frequency);
    try expectEqual(@as(?usize, 6), full.weight);
    try expectEqual(@as(?f64, 314159), full.seed);
    try expect(full.noprint and full.details_all and full.stats_all and full.notsorted);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{7}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);
    try expect(!d.hasErrors());
}

test "STAT-GLMSELECT-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const saved = io.global_linesize;
    defer io.global_linesize = saved;
    io.global_linesize = 160;
    for ([_][]const u8{
        "proc glmselect data=absent; model y = x1;",
        "proc glmselect bogus; model y = x1;",
        "proc glmselect seed=abc; model y = x1;",
        "proc glmselect; class g;",
        "proc glmselect; model y = nosuch;",
        "proc glmselect; model g = x1;",
        "proc glmselect; model y = x1 g;",
        "proc glmselect; class g; model y = x1 y;",
        "proc glmselect; model y = x1; model y = x2;",
        "proc glmselect; model y = x1 / bogus;",
        "proc glmselect; model y = x1 / details=bogus;",
        "proc glmselect; model y = x1 / selection=bogus;",
        "proc glmselect; freq g; model y = x1;",
        "proc glmselect; weight g; model y = x1;",
        "proc glmselect; freq f extra; model y = x1;",
        "proc glmselect; by nosuch; model y = x1;",
        "proc glmselect; bogus y; model y = x1;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 1), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
    for ([_][]const u8{
        "proc glmselect plots=all; model y = x1;",
        "proc glmselect outdesign=d; model y = x1;",
        "proc glmselect valdata=trial; model y = x1;",
        "proc glmselect; class g / param=ref; model y = x1;",
        "proc glmselect; class g(ref='East'); model y = x1;",
        "proc glmselect; model y = x1*x2;",
        "proc glmselect; model y = x1|x2;",
        "proc glmselect; model y = x1-x3;",
        "proc glmselect; model y = x1 x1;",
        "proc glmselect; model y = ;",
        "proc glmselect; model y = x1 / selection=lasso;",
        "proc glmselect; model y = x1 / selection=stepwise(select=sl);",
        "proc glmselect; model y = x1 / details=steps;",
        "proc glmselect; model y = x1 / stats=(aic sbc);",
        "proc glmselect; model y = x1 / noint;",
        "proc glmselect; model y = x1 / choose=aic;",
        "proc glmselect; partition fraction(validate=0.3); model y = x1;",
        "proc glmselect; effect s = spline(x1); model y = x1;",
        "proc glmselect; model y = x1; output out=o;",
        "proc glmselect; freq f; freq f; model y = x1;",
        "proc glmselect; freq f; model y = x1 x2 / details=all stats=all;",
        "proc glmselect; weight w; model y = x1 x2 / details=all stats=all;",
        // The default listing belongs to STAT-GLMSELECT-002.
        "proc glmselect; model y = x1 x2 x3;",
        // Fewer than 10 entry candidates: the candidate table is unverified.
        "proc glmselect; model y = x1 x2 x3 / details=all stats=all;",
        // f and w are constant columns: a linear dependency with the intercept.
        "proc glmselect; model y = x1 f w / details=all stats=all;",
    }) |source| {
        const r = try fx.outcome(source);
        try expectEqual(@as(u8, 2), r.rc);
        try expectEqual(@as(usize, 0), r.out.len);
    }
    // NOPRINT runs the selection and prints nothing.
    const quiet = try fx.outcome("proc glmselect noprint; model y = x1 x2 x3;");
    try expectEqual(@as(u8, 0), quiet.rc);
    try expectEqual(@as(usize, 0), quiet.out.len);
}

test "STAT-GLMSELECT-001 observation selection BY boundaries and CLASS levels" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
    const rows = fx.lib.find("trial").?.rows.items;
    // Missing response and missing regressor are dropped; the blank g is
    // only a missing value once g is a CLASS variable, used or not.
    const plain = try glmselect.prepare(cx, try fx.spec(&d, "proc glmselect; model y = x1 x2;"), rows);
    try expectEqual(@as(usize, 17), plain.read);
    try expectEqual(@as(usize, 15), plain.n);
    try expectEqual(@as(usize, 3), plain.parameters);
    // A regressor outside the MODEL statement does not select.
    try expectEqual(@as(usize, 16), (try glmselect.prepare(cx, try fx.spec(&d, "proc glmselect; model y = x1;"), rows)).n);
    const classed = try glmselect.prepare(cx, try fx.spec(&d, "proc glmselect; class g; model y = x1 g x2;"), rows);
    try expectEqual(@as(usize, 14), classed.n);
    try expectEqual(@as(usize, 2), classed.levels[0].len);
    try std.testing.expectEqualStrings("East", classed.levels[0][0]);
    try std.testing.expectEqualStrings("West", classed.levels[0][1]);
    // Intercept + x1 + two g levels + x2; g carries one design column.
    try expectEqual(@as(usize, 5), classed.parameters);
    try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1 }, classed.df);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, classed.first);
    try close(7.214285714285714, classed.ybar);
    try close(414.35714285714283, classed.sst);
    // A BY slice is an analysis of its own.
    const half = try glmselect.prepare(cx, try fx.spec(&d, "proc glmselect; model y = x1 x2;"), rows[0..7]);
    try expectEqual(@as(usize, 7), half.read);
    try expectEqual(@as(usize, 7), half.n);
    try expect(!d.hasErrors());
}

test "STAT-GLMSELECT-001 stepwise SBC entry and removal match exact rational calculation" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
    const s = try fx.spec(&d, "proc glmselect; class g; model y = x1 x2 x3;");
    const sel = try glmselect.select(cx, try glmselect.prepare(cx, s, fx.lib.find("trial").?.rows.items));
    try expectEqual(@as(usize, 5), sel.steps.len);
    // effect index entered / removed, parameters, SSE, SBC, PRESS, F, Pr > F
    const E = struct { ent: ?usize, rem: ?usize, p: usize, sse: f64, sbc: f64, press: f64, f: f64, pf: f64 };
    const expected = [_]E{
        .{ .ent = null, .rem = null, .p = 1, .sse = 414.35714285714283, .sbc = 50.066450436912916, .press = 480.5562130177515, .f = 0, .pf = 1 },
        .{ .ent = 2, .rem = null, .p = 2, .sse = 62.35691056910569, .sbc = 26.191555059936306, .press = 82.84250912468895, .f = 67.73912865319532, .pf = 2.8082278648571172e-06 },
        .{ .ent = 1, .rem = null, .p = 3, .sse = 37.97497470738709, .sbc = 21.88735272850917, .press = 57.60564381928084, .f = 7.062579937063993, .pf = 0.02228391282789682 },
        .{ .ent = 0, .rem = null, .p = 4, .sse = 31.246665563733366, .sbc = 21.79620406325088, .press = 71.0632920046745, .f = 2.1532886860935894, .pf = 0.17299863826227602 },
        .{ .ent = null, .rem = 2, .p = 3, .sse = 31.57399963198347, .sbc = 19.30304517058608, .press = 56.304333234126595, .f = 0.10475807973252174, .pf = 0.7528601378709491 },
    };
    for (expected, sel.steps) |e, st| {
        try expectEqual(e.ent, st.entered);
        try expectEqual(e.rem, st.removed);
        try expectEqual(e.p, st.fit.p);
        try expectEqual(e.p, st.effects_in);
        try close(e.sse, st.fit.sse);
        try close(e.sbc, st.stats.sbc);
        try close(e.press, st.stats.press);
        if (e.p > 1) try std.testing.expectApproxEqRel(e.f, st.f, 1e-8);
        try std.testing.expectApproxEqRel(e.pf, st.pf, 1e-7);
    }
    // Step 2 (x2 x3) criteria; the full model has C(p) = p exactly at step 3.
    const two = sel.steps[2].stats;
    try close(3.452270427944281, two.mse);
    try close(0.9083520693150458, two.rsq);
    try close(0.8916888091905086, two.adj);
    try close(35.9701807396634, two.aic);
    try close(40.41462518410784, two.aicc);
    try close(22.83571160812865, two.bic);
    try close(4.153288686093589, two.cp);
    try close(2.7124981933847923, two.ase);
    try close(4.0, sel.steps[3].stats.cp);
    // Final model y on x1 x2: slopes in MODEL order.
    const last = sel.steps[4];
    try std.testing.expectEqualSlices(bool, &.{ true, true, false }, last.in);
    try close(0.8984840549760081, last.fit.beta[0]);
    try close(1.2495435179549605, last.fit.beta[1]);
    var intercept = sel.group.ybar;
    for (last.fit.cols, last.fit.beta) |c, b| intercept -= b * sel.group.means[c];
    try close(-1.7348370111395774, intercept);
    // Removal candidates of step 4 are ranked best first.
    try expectEqual(@as(usize, 3), last.candidates.len);
    try expectEqual(@as(usize, 2), last.candidates[0].effect);
    // Stop details: re-entering x3 or removing x1 would both raise the SBC.
    try expectEqual(@as(usize, 2), sel.stop_entry.?.effect);
    try close(21.79620406325088, sel.stop_entry.?.sbc);
    try expectEqual(@as(usize, 0), sel.stop_removal.?.effect);
    try close(31.36748240559876, sel.stop_removal.?.sbc);
    try expect(!d.hasErrors());
}
