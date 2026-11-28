//! STAT-LIFEREG-001 permanent checks: declarations, variable roles,
//! observation selection, CLASS level ordering, BY boundaries and the
//! execution boundary (no fit, loud gap). Data are invented, except the two
//! published guide samples (headache relief times, engine fan lifetimes)
//! whose observation counts are those of the SAS reference listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const lifereg = @import("lifereg.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

/// Columns t c g x w b lo hi. Row comments name the rule each row exercises.
fn roles(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("t", .num);
    _ = try ds.addColumn("c", .num);
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "x", "w", "b", "lo", "hi" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_]struct { f64, f64, []const u8, f64, f64, f64 }{
        .{ 5, 0, "B", 1, 1, 1 }, // event
        .{ 6, 1, "A", 2, 0.5, 1 }, // right censored, fractional weight
        .{ nan, 0, "A", 1, 1, 1 }, // missing response
        .{ 7, nan, "A", 1, 1, 1 }, // missing censoring value
        .{ 8, 0, "", 1, 1, 2 }, // missing CLASS value
        .{ 9, 0, "A", nan, 1, 2 }, // missing continuous explanatory value
        .{ 10, 1, "B", 3, 0, 2 }, // zero weight
        .{ 11, 0, "B", 3, -1, 2 }, // negative weight
        .{ 12, 0, "C", 4, nan, 2 }, // missing weight
        .{ 13, 0, "A", 5, 2.5, 2 }, // event, nonintegral weight
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[5] }, .{ .num = r[0] }, .{ .num = r[0] + 1 } });
    return ds;
}

/// Published sample: headache relief times, SAS/STAT 15.4 chapter 76.
fn headache(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "headache");
    for ([_][]const u8{ "Minutes", "Group", "Censor" }) |name| _ = try ds.addColumn(name, .num);
    const v = [_]f64{ 11, 1, 0, 12, 1, 0, 19, 1, 0, 19, 1, 0, 19, 1, 0, 19, 1, 0, 21, 1, 0, 20, 1, 0, 21, 1, 0, 21, 1, 0, 20, 1, 0, 21, 1, 0, 20, 1, 0, 21, 1, 0, 25, 1, 0, 27, 1, 0, 30, 1, 0, 21, 1, 1, 24, 1, 1, 14, 2, 0, 16, 2, 0, 16, 2, 0, 21, 2, 0, 21, 2, 0, 23, 2, 0, 23, 2, 0, 23, 2, 0, 23, 2, 0, 25, 2, 1, 23, 2, 0, 24, 2, 0, 24, 2, 0, 26, 2, 1, 32, 2, 1, 30, 2, 1, 30, 2, 0, 32, 2, 1, 20, 2, 1 };
    var i: usize = 0;
    while (i < v.len) : (i += 3) try ds.appendRow(&.{ .{ .num = v[i] }, .{ .num = v[i + 1] }, .{ .num = v[i + 2] } });
    return ds;
}

/// Published sample: engine fan lifetimes, SAS/STAT 15.4 chapter 76.
fn fan(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "fan");
    for ([_][]const u8{ "Lifetime", "Censor" }) |name| _ = try ds.addColumn(name, .num);
    const v = [_]f64{ 450, 0, 460, 1, 1150, 0, 1150, 0, 1560, 1, 1600, 0, 1660, 1, 1850, 1, 1850, 1, 1850, 1, 1850, 1, 1850, 1, 2030, 1, 2030, 1, 2030, 1, 2070, 0, 2070, 0, 2080, 0, 2200, 1, 3000, 1, 3000, 1, 3000, 1, 3000, 1, 3100, 0, 3200, 1, 3450, 0, 3750, 1, 3750, 1, 4150, 1, 4150, 1, 4150, 1, 4150, 1, 4300, 1, 4300, 1, 4300, 1, 4300, 1, 4600, 0, 4850, 1, 4850, 1, 4850, 1, 4850, 1, 5000, 1, 5000, 1, 5000, 1, 6100, 1, 6100, 0, 6100, 1, 6100, 1, 6300, 1, 6450, 1, 6450, 1, 6700, 1, 7450, 1, 7800, 1, 7800, 1, 8100, 1, 8100, 1, 8200, 1, 8500, 1, 8500, 1, 8500, 1, 8750, 1, 8750, 0, 8750, 1, 9400, 1, 9900, 1, 10100, 1, 10100, 1, 10100, 1, 11500, 1 };
    var i: usize = 0;
    while (i < v.len) : (i += 2) try ds.appendRow(&.{ .{ .num = v[i] }, .{ .num = v[i + 1] } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8, log: []const u8 };
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
    /// Exit code under D-009, the listing and the log, via the captured reporter.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        lifereg.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const rc = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, rc != 0);
        return .{ .rc = rc, .out = out.items, .log = try d.render() };
    }
    fn spec(self: *Fixture, d: *diag.Diagnostics, source: []const u8) !lifereg.Spec {
        return lifereg.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = d }, try lex.tokenize(self.a(), source, d));
    }
    fn groups(self: *Fixture, d: *diag.Diagnostics, source: []const u8) ![]lifereg.Selected {
        const cx: proc.ProcCtx = .{ .arena = self.a(), .lib = &self.lib, .diags = d };
        return lifereg.plan(cx, try lifereg.parse(cx, try lex.tokenize(self.a(), source, d)));
    }
};

test "STAT-LIFEREG-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const plain = try fx.spec(&d, "proc lifereg; model t = ;");
    try expectEqual(@as(usize, 0), plain.response.right.time);
    try expect(plain.response.right.censor == null and plain.weight == null and plain.model_label == null);
    try expect(!plain.noprint and !plain.nolog and !plain.noint and !plain.notsorted);
    try expectEqual(lifereg.Distribution.weibull, plain.distribution);
    try expectEqual(@as(usize, 20), plain.namelen);
    try expect(plain.order == .formatted);
    try expectEqual(@as(usize, 0), plain.effects.len + plain.classes.len + plain.by_cols.len);

    const full = try fx.spec(&d, "proc lifereg data=sample noprint order=data namelen=40; class g b; class g; m1: model t*c(1, -1 2) = g x / dist=lnormal nolog noint; weight w; by x; by descending b notsorted;");
    try expectEqual(@as(?usize, 1), full.response.right.censor);
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, 2 }, full.response.right.censor_values);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3 }, full.effects);
    // A CLASS variable named twice is one CLASS variable.
    try std.testing.expectEqualSlices(usize, &.{ 2, 5 }, full.classes);
    try expectEqual(@as(?usize, 4), full.weight);
    try expect(full.noprint and full.nolog and full.noint and full.notsorted);
    try expect(full.order == .data);
    try expectEqual(@as(usize, 40), full.namelen);
    try expectEqual(lifereg.Distribution.lognormal, full.distribution);
    try std.testing.expectEqualStrings("m1", full.model_label.?);
    // Only the last BY statement is used.
    try std.testing.expectEqualSlices(usize, &.{5}, full.by_cols);
    try std.testing.expectEqualSlices(bool, &.{true}, full.by_desc);

    // "If multiple MODEL statements are present, only the last is used":
    // nothing of the first one survives.
    const last = try fx.spec(&d, "proc lifereg; a: model t*c(1) = x / d=normal nolog; model b = w / distribution=llogistic;");
    try expectEqual(@as(usize, 5), last.response.right.time);
    try expect(last.response.right.censor == null and last.model_label == null and !last.nolog);
    try std.testing.expectEqualSlices(usize, &.{4}, last.effects);
    try expectEqual(lifereg.Distribution.llogistic, last.distribution);

    const interval = try fx.spec(&d, "proc lifereg; model (lo, hi) = x;");
    try expectEqual(@as(usize, 6), interval.response.interval.lower);
    try expectEqual(@as(usize, 7), interval.response.interval.upper);
    const counts = try fx.spec(&d, "proc lifereg; model lo/hi = x;");
    try expectEqual(@as(usize, 6), counts.response.events_trials.events);
    try expectEqual(@as(usize, 7), counts.response.events_trials.trials);
    inline for (.{ .{ "weibull", .weibull }, .{ "exponential", .exponential }, .{ "gamma", .gamma }, .{ "logistic", .logistic }, .{ "lognormal", .lognormal }, .{ "NORMAL", .normal } }) |pair| {
        const s = try fx.spec(&d, "proc lifereg; model t = / dist=" ++ pair[0] ++ ";");
        try expectEqual(@as(lifereg.Distribution, pair[1]), s.distribution);
    }
    try expect(!d.hasErrors());
}

test "STAT-LIFEREG-001 invalid declarations are user errors and unimplemented ones are gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc lifereg; class g;", 1 }, // MODEL required
        .{ "proc lifereg bogus; model t = ;", 1 },
        .{ "proc lifereg data=nosuch; model t = ;", 1 },
        .{ "proc lifereg data=sample data=sample; model t = ;", 1 },
        .{ "proc lifereg order=bogus; model t = ;", 1 },
        .{ "proc lifereg namelen=19; model t = ;", 1 },
        .{ "proc lifereg namelen=201; model t = ;", 1 },
        .{ "proc lifereg namelen=abc; model t = ;", 1 },
        .{ "proc lifereg; model nosuch = ;", 1 },
        .{ "proc lifereg; model g = ;", 1 }, // character response
        .{ "proc lifereg; model t;", 1 }, // no equal sign
        .{ "proc lifereg; model t*g(0) = ;", 1 }, // character censoring variable
        .{ "proc lifereg; model t*c = ;", 1 },
        .{ "proc lifereg; model t*c() = ;", 1 },
        .{ "proc lifereg; model t*c(a) = ;", 1 },
        .{ "proc lifereg; model (lo hi = ;", 1 },
        .{ "proc lifereg; model (lo, g) = ;", 1 },
        .{ "proc lifereg; model lo/g = ;", 1 },
        .{ "proc lifereg; model t = nosuch;", 1 },
        .{ "proc lifereg; model t = g;", 1 }, // character effect outside CLASS
        .{ "proc lifereg; model t = / dist=bogus;", 1 },
        .{ "proc lifereg; model t = / bogus;", 1 },
        .{ "proc lifereg; class; model t = ;", 1 },
        .{ "proc lifereg; class nosuch; model t = ;", 1 },
        .{ "proc lifereg; model t = ; weight g;", 1 },
        .{ "proc lifereg; model t = ; weight w w;", 1 },
        .{ "proc lifereg; model t = ; by nosuch;", 1 },
        .{ "proc lifereg; model t = ; bogus t;", 1 },
        .{ "proc lifereg; model t = ; by descending b;", 1 }, // not sorted descending
        // Documented options and statements owned by later LIFEREG tickets.
        .{ "proc lifereg covout; model t = ;", 2 },
        .{ "proc lifereg inest=i; model t = ;", 2 },
        .{ "proc lifereg outest=o; model t = ;", 2 },
        .{ "proc lifereg plots=none; model t = ;", 2 },
        .{ "proc lifereg xdata=x; model t = ;", 2 },
        .{ "proc lifereg; model t*c(0 to 2) = ;", 2 },
        .{ "proc lifereg; class g; model t = g*x;", 2 },
        .{ "proc lifereg; class g; model t = g|x;", 2 },
        .{ "proc lifereg; class g; model t = x(g);", 2 },
        .{ "proc lifereg; model t = x x;", 2 },
        .{ "proc lifereg; model t = x / covb;", 2 },
        .{ "proc lifereg; model t = x / scale=1 noscale;", 2 },
        .{ "proc lifereg; model t = x / maxiter=5;", 2 },
        .{ "proc lifereg; class g / param=ref; model t = g;", 2 },
        .{ "proc lifereg; model t = x; weight w; weight w;", 2 },
        .{ "proc lifereg; class g; model t = g; format g $1.;", 2 },
        .{ "proc lifereg; model t = x; output out=o cdf=p;", 2 },
        .{ "proc lifereg; model t = x; bayes seed=1;", 2 },
        .{ "proc lifereg; model t = x; probplot;", 2 },
        .{ "proc lifereg; model t = x; test x;", 2 },
        .{ "proc lifereg; model t = x; estimate 'x' x 1;", 2 },
        .{ "proc lifereg; class g; model t = g; lsmeans g;", 2 },
        .{ "proc lifereg; model t = x; store s;", 2 },
        // Execution boundary: every valid model is an unfitted, loud gap.
        .{ "proc lifereg; model t = ;", 2 },
        .{ "proc lifereg; class g; model t*c(1) = g x; weight w; by b;", 2 },
        .{ "proc lifereg noprint; model t*c(1) = x;", 2 },
        .{ "proc lifereg; model (lo, hi) = x;", 2 },
        .{ "proc lifereg; model lo/hi = x;", 2 },
    }) |case| {
        const result = try fx.outcome(case[0]);
        std.testing.expectEqual(case[1], result.rc) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
        try expectEqual(@as(usize, 0), result.out.len);
    }
    // Each gap names what is missing.
    try expect(std.mem.indexOf(u8, (try fx.outcome("proc lifereg; model t*c(1) = x;")).log, "PROC LIFEREG: maximum-likelihood estimation and the listing are not implemented") != null);
    // The interval form is refused by the shared survival-data contract.
    try expect(std.mem.indexOf(u8, (try fx.outcome("proc lifereg; model (lo, hi) = x;")).log, "PROC LIFEREG: interval-censored response is not implemented") != null);
    try expect(std.mem.indexOf(u8, (try fx.outcome("proc lifereg; model lo/hi = x;")).log, "PROC LIFEREG: events/trials response is not implemented") != null);
    try expect(std.mem.indexOf(u8, (try fx.outcome("proc lifereg; model t = x; output out=o;")).log, "PROC LIFEREG: output statement is not implemented") != null);
}

test "STAT-LIFEREG-001 empty input is a visible gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "none");
    _ = try ds.addColumn("t", .num);
    try lib.put("none", ds);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const tokens = try lex.tokenize(a, "proc lifereg data=none; model t = ;", &d);
    // Without BY an empty input is one group with nothing read or used.
    const groups = try lifereg.plan(cx, try lifereg.parse(cx, tokens));
    try expectEqual(@as(usize, 1), groups.len);
    try expectEqual(@as(usize, 0), groups[0].read + groups[0].used);
    try std.testing.expectError(error.ParseError, lifereg.run(cx, &out, tokens));
    try expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-LIFEREG-001 observation selection for missing values and WEIGHT" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    const E = lifereg.Exclusion;
    const Case = struct { source: []const u8, used: usize, events: usize, censored: usize, dropped: [4]usize };
    for ([_]Case{
        // No censoring variable: every nonmissing response is an event.
        .{ .source = "proc lifereg; model t = ;", .used = 9, .events = 9, .censored = 0, .dropped = .{ 1, 0, 0, 0 } },
        .{ .source = "proc lifereg; model t*c(1) = ;", .used = 8, .events = 6, .censored = 2, .dropped = .{ 1, 1, 0, 0 } },
        // Several censoring values.
        .{ .source = "proc lifereg; model t*c(0, 1) = ;", .used = 8, .events = 0, .censored = 8, .dropped = .{ 1, 1, 0, 0 } },
        .{ .source = "proc lifereg; model t*c(1) = x;", .used = 7, .events = 5, .censored = 2, .dropped = .{ 1, 1, 1, 0 } },
        // A CLASS variable outside the model is not needed and does not select.
        .{ .source = "proc lifereg; class g; model t*c(1) = x;", .used = 7, .events = 5, .censored = 2, .dropped = .{ 1, 1, 1, 0 } },
        .{ .source = "proc lifereg; class g; model t*c(1) = g x;", .used = 6, .events = 4, .censored = 2, .dropped = .{ 1, 1, 2, 0 } },
        // Missing, zero and negative weights drop; fractional weights stay.
        .{ .source = "proc lifereg; model t*c(1) = ; weight w;", .used = 5, .events = 4, .censored = 1, .dropped = .{ 1, 1, 0, 3 } },
        .{ .source = "proc lifereg; class g; model t*c(1) = g x; weight w;", .used = 3, .events = 2, .censored = 1, .dropped = .{ 1, 1, 2, 3 } },
    }) |case| {
        const groups = try fx.groups(&d, case.source);
        try expectEqual(@as(usize, 1), groups.len);
        const g = groups[0];
        errdefer std.debug.print("case: {s}\n", .{case.source});
        try expectEqual(@as(usize, 10), g.read);
        try expectEqual(case.used, g.used);
        try expectEqual(case.events, g.noncensored);
        try expectEqual(case.censored, g.right_censored);
        for ([_]E{ .missing_response, .missing_censor, .missing_explanatory, .nonpositive_weight }, case.dropped) |reason, n| try expectEqual(n, g.excluded(reason));
        try expectEqual(g.read, g.used + case.dropped[0] + case.dropped[1] + case.dropped[2] + case.dropped[3]);
    }
    // Per-row status with every rule active.
    const all = (try fx.groups(&d, "proc lifereg; class g; model t*c(1) = g x; weight w;"))[0];
    const expected = [_]lifereg.Status{ .event, .right_censored, .{ .excluded = .missing_response }, .{ .excluded = .missing_censor }, .{ .excluded = .missing_explanatory }, .{ .excluded = .missing_explanatory }, .{ .excluded = .nonpositive_weight }, .{ .excluded = .nonpositive_weight }, .{ .excluded = .nonpositive_weight }, .event };
    for (expected, all.status) |want, got| try expect(std.meta.eql(want, got));
    try expect(!d.hasErrors());
}

fn expectLabels(want: []const []const u8, got: []const []const u8) !void {
    try expectEqual(want.len, got.len);
    for (want, got) |w, g| try std.testing.expectEqualStrings(w, std.mem.trim(u8, g, " "));
}

test "STAT-LIFEREG-001 CLASS level ordering and BY boundaries" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init(roles);
    var d = diag.Diagnostics.init(fx.a());
    // Levels come from the used observations only: the blank level is a
    // missing value, and level C survives only without the WEIGHT rule.
    const sorted = (try fx.groups(&d, "proc lifereg; class g; model t*c(1) = g;"))[0];
    try expectEqual(@as(usize, 1), sorted.classes.len);
    try expectEqual(@as(usize, 2), sorted.classes[0].column);
    try expectLabels(&.{ "A", "B", "C" }, sorted.classes[0].labels);
    try expectLabels(&.{ "B", "A", "C" }, (try fx.groups(&d, "proc lifereg order=data; class g; model t*c(1) = g;"))[0].classes[0].labels);
    try expectLabels(&.{ "A", "B" }, (try fx.groups(&d, "proc lifereg; class g; model t*c(1) = g; weight w;"))[0].classes[0].labels);
    // A CLASS variable outside the model builds no levels.
    try expectEqual(@as(usize, 0), (try fx.groups(&d, "proc lifereg; class g; model t*c(1) = x;"))[0].classes.len);

    // BY b: rows 1-4 and rows 5-10 are selected independently.
    const by_groups = try fx.groups(&d, "proc lifereg; class g; model t*c(1) = g x; by b;");
    try expectEqual(@as(usize, 2), by_groups.len);
    try expectEqual(@as(usize, 4), by_groups[0].read);
    try expectEqual(@as(usize, 2), by_groups[0].used);
    try expectEqual(@as(usize, 1), by_groups[0].noncensored);
    try expectEqual(@as(usize, 1), by_groups[0].right_censored);
    try expectLabels(&.{ "A", "B" }, by_groups[0].classes[0].labels);
    try expectEqual(@as(usize, 6), by_groups[1].read);
    try expectEqual(@as(usize, 4), by_groups[1].used);
    try expectEqual(@as(usize, 3), by_groups[1].noncensored);
    try expectEqual(@as(usize, 1), by_groups[1].right_censored);
    try expectLabels(&.{ "A", "B", "C" }, by_groups[1].classes[0].labels);
    // NOTSORTED keeps unsorted groups apart instead of failing.
    try expectEqual(@as(usize, 2), (try fx.groups(&d, "proc lifereg; model t = ; by descending b notsorted;")).len);
    try expect(!d.hasErrors());
}

test "STAT-LIFEREG-001 published samples reproduce the reference Model Information counts" {
    {
        var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer fx.arena.deinit();
        try fx.init(headache);
        var d = diag.Diagnostics.init(fx.a());
        const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
        const s = try lifereg.parse(cx, try lex.tokenize(fx.a(), "proc lifereg data=Headache; class Group; model Minutes*Censor(1)=Group;", &d));
        const g = (try lifereg.plan(cx, s))[0];
        // Reference listing: 38 read and used, 30 noncensored, 8 right
        // censored, Group levels "1 2", 3 parameters, Weibull.
        try expectEqual(@as(usize, 38), g.read);
        try expectEqual(@as(usize, 38), g.used);
        try expectEqual(@as(usize, 30), g.noncensored);
        try expectEqual(@as(usize, 8), g.right_censored);
        try expectLabels(&.{ "1", "2" }, g.classes[0].labels);
        try expectEqual(@as(?usize, 3), lifereg.parameterCount(s, g));
        try expectEqual(lifereg.Distribution.weibull, s.distribution);
        try expect(!d.hasErrors());
    }
    {
        var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer fx.arena.deinit();
        try fx.init(fan);
        var d = diag.Diagnostics.init(fx.a());
        const cx: proc.ProcCtx = .{ .arena = fx.a(), .lib = &fx.lib, .diags = &d };
        const s = try lifereg.parse(cx, try lex.tokenize(fx.a(), "proc lifereg data=Fan; model Lifetime*Censor( 1 )= / dist=lognormal;", &d));
        const g = (try lifereg.plan(cx, s))[0];
        // Reference listing: 70 read and used, 12 noncensored, 58 right
        // censored, 2 parameters, Lognormal.
        try expectEqual(@as(usize, 70), g.read);
        try expectEqual(@as(usize, 70), g.used);
        try expectEqual(@as(usize, 12), g.noncensored);
        try expectEqual(@as(usize, 58), g.right_censored);
        try expectEqual(@as(?usize, 2), lifereg.parameterCount(s, g));
        try expect(!d.hasErrors());
    }
}
