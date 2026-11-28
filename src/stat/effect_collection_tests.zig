//! STAT-COMMON-021 permanent tests: EFFECT COLLECTION / LAG parsing,
//! defaults, applicability classes and hand-computed design columns.
//! Expected values are written by hand from S154 Chapter 20 (physical
//! pp.426-429) or are the SAS listing's printed estimates; nothing here reads
//! tests/STAT15.4-oracle/.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const ce = @import("effect_collection.zig");
const t_ = std.testing;
const A = std.mem.Allocator;
const nan = std.math.nan(f64);

fn parseSrc(a: A, d: *diag.Diagnostics, ds: *const Dataset, classes: []const usize, src: []const u8) !ce.Spec {
    const toks = try lex.tokenize(a, src, d);
    return ce.parse(a, d, ds, classes, &.{"earlier"}, toks[1..], 1);
}
fn expectNames(want: []const []const u8, got: []const []const u8) !void {
    try t_.expectEqual(want.len, got.len);
    for (want, got) |w, g| try t_.expectEqualStrings(w, g);
}
fn expectMatrix(want: []const f64, b: ce.Built) !void {
    try t_.expectEqual(want.len, b.n * b.p);
    for (want, b.x) |w, g| {
        if (std.math.isNan(w)) try t_.expect(std.math.isNan(g)) else try t_.expectEqual(w, g);
    }
}

/// The 12 invented observations of the COMMON-021 reference case:
/// x z y group weight freq.
fn sample(a: A) !Dataset {
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("z", .num);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("group", .char);
    const r = [_][4]f64{ .{ 1, 1, 4, 0 }, .{ 2, 1, 6, 0 }, .{ 3, 2, 7, 0 }, .{ 4, 1, 9, 0 }, .{ 5, 3, 13, 0 }, .{ 6, 2, 12, 0 }, .{ 7, 4, 17, 1 }, .{ 8, 3, 19, 1 }, .{ 9, 5, 20, 1 }, .{ 10, 3, 23, 1 }, .{ 11, 5, 25, 1 }, .{ 12, 4, 24, 1 } };
    for (r) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .str = if (row[3] == 0) "A" else "B" } });
    return ds;
}

test "STAT-COMMON-021 collection: names, dimensions, values, CLASS constituents, missing rows" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, &ds, &.{}, "effect both=collection(x z);");
    try t_.expectEqualStrings("both", s.name);
    try t_.expect(!s.body.collection.details); // DETAILS defaults off
    const b = try ce.buildCollection(a, &ds, ds.rows.items, &.{}, s.name, s.body.collection);
    // Two columns in definition order (SAS: "both x", "both z"; 3 parameters with Intercept).
    try expectNames(&.{ "x", "z" }, b.names);
    try expectNames(&.{ "both", "both" }, b.effects);
    try t_.expectEqual(@as(usize, 12), b.n);
    try t_.expectEqual(@as(usize, 2), b.p);
    try t_.expectEqualSlices(f64, &.{ 1, 1, 2, 1, 3, 2 }, b.x[0..6]);
    // Reverse order reverses the columns.
    const r = try ce.buildCollection(a, &ds, ds.rows.items, &.{}, "rz", (try parseSrc(a, &d, &ds, &.{}, "effect rz=COLLECTION(z x / details);")).body.collection);
    try expectNames(&.{ "z", "x" }, r.names);
    try t_.expectEqualSlices(f64, &.{ 1, 1, 1, 2 }, r.x[0..4]);
    // A CLASS constituent contributes its GLM indicator columns (all levels).
    // SAS 15.4 (GLMSELECT OUTDESIGN=/DETAILS probe) puts continuous
    // constituents first: collection(treatment x) -> x treatment:A ... .
    const cs = try parseSrc(a, &d, &ds, &.{3}, "effect cg=collection(group x);");
    const c = try ce.buildCollection(a, &ds, ds.rows.items[5..8], &.{3}, cs.name, cs.body.collection);
    try expectNames(&.{ "x", "group:A", "group:B" }, c.names);
    try expectMatrix(&.{ 6, 1, 0, 7, 0, 1, 8, 0, 1 }, c);
    // collection(z group x): continuous z, x in definition order, then group.
    const c3 = try ce.buildCollection(a, &ds, ds.rows.items[0..1], &.{3}, "c1", .{ .vars = &.{ 1, 3, 0 } });
    try expectNames(&.{ "z", "x", "group:A" }, c3.names);
    try expectMatrix(&.{ 1, 1, 1 }, c3);
    // A missing constituent makes the whole row missing.
    var m = Dataset.init(a, "m");
    _ = try m.addColumn("x", .num);
    _ = try m.addColumn("z", .num);
    try m.appendRow(&.{ .{ .num = 2 }, .{ .num = nan } });
    try m.appendRow(&.{ .{ .num = 3 }, .{ .num = 4 } });
    const mb = try ce.buildCollection(a, &m, m.rows.items, &.{}, "e", .{ .vars = &.{ 0, 1 } });
    try expectMatrix(&.{ nan, nan, 3, 4 }, mb);
}

test "STAT-COMMON-021 collection columns reproduce the SAS least-squares estimates" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    const b = try ce.buildCollection(a, &ds, ds.rows.items, &.{}, "both", .{ .vars = &.{ 0, 1 } });
    // Independent normal equations X'X beta = X'y with X = [1, both x, both z],
    // solved by Cramer's rule.
    var m: [3][3]f64 = @splat(@splat(0));
    var v: [3]f64 = @splat(0);
    for (0..b.n) |i| {
        const row = [3]f64{ 1, b.at(i, 0), b.at(i, 1) };
        for (0..3) |j| {
            for (0..3) |k| m[j][k] += row[j] * row[k];
            v[j] += row[j] * ds.rows.items[i][2].num;
        }
    }
    const det = struct {
        fn of(q: [3][3]f64) f64 {
            return q[0][0] * (q[1][1] * q[2][2] - q[1][2] * q[2][1]) - q[0][1] * (q[1][0] * q[2][2] - q[1][2] * q[2][0]) + q[0][2] * (q[1][0] * q[2][1] - q[1][1] * q[2][0]);
        }
    }.of;
    const full = det(m);
    const sas = [3]f64{ 1.333898, 1.817627, 0.624068 }; // SAS Parameter Estimates
    for (0..3) |j| {
        var q = m;
        for (0..3) |k| q[k][j] = v[k];
        try t_.expectApproxEqAbs(sas[j], det(q) / full, 5.1e-7);
    }
}

/// The p.427 lag design (subject, period, treatment); "" is a missing treatment.
fn lagData(a: A) !Dataset {
    var ds = Dataset.init(a, "lag");
    _ = try ds.addColumn("subject", .char);
    _ = try ds.addColumn("period", .num);
    _ = try ds.addColumn("treatment", .char);
    _ = try ds.addColumn("role", .num);
    const rows = [_]struct { []const u8, f64, []const u8 }{
        .{ "Sheila", 1, "B" }, .{ "Joey", 1, "A" }, .{ "Athena", 1, "A" }, .{ "Gelindo", 1, "A" },
        .{ "Sheila", 2, "C" }, .{ "Joey", 2, "A" }, .{ "Athena", 2, "" },  .{ "Gelindo", 2, "B" },
        .{ "Sheila", 3, "B" }, .{ "Joey", 3, "C" }, .{ "Athena", 3, "A" }, .{ "Gelindo", 3, "B" },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .str = r[2] }, .{ .num = 1 } });
    return ds;
}
fn lag(a: A, ds: *const Dataset, src: []const u8) !ce.LagBuilt {
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, ds, &.{2}, src);
    return ce.buildLag(a, &d, ds, ds.rows.items, s.name, s.body.lag, 1);
}

test "STAT-COMMON-021 lag: the documented p.428 design matrix, NLAG, WITHIN list, DESIGNROLE" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try lagData(a);
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, &ds, &.{2}, "EFFECT Lag = LAG( treatment / WITHIN=subject PERIOD=period);");
    try t_.expectEqual(@as(usize, 1), s.body.lag.nlag); // NLAG=1 by default
    try t_.expect(s.body.lag.designrole == null and !s.body.lag.details);
    const b = (try lag(a, &ds, "EFFECT Lag = LAG( treatment / WITHIN=subject PERIOD=period);")).built;
    try expectNames(&.{ "Lag_A", "Lag_B", "Lag_C" }, b.names);
    try t_.expectEqual(@as(usize, 12), b.n);
    try t_.expectEqual(@as(usize, 3), b.p);
    // Rows in input order; the p.428 table lists the same rows by subject.
    try expectMatrix(&.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // period 1: all 0
        0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, // Sheila(B) Joey(A) Athena(A) Gelindo(A)
        0, 0, 1, 1, 0, 0, nan, nan, nan, 0, 1, 0, // Sheila(C) Joey(A) Athena(missing) Gelindo(B)
    }, b);
    // NLAG=2: period 3 takes the period 1 treatment; options in any order.
    const two = (try lag(a, &ds, "effect L2 = lag(treatment / period=period nlag=2 within=(subject) details);")).built;
    try expectMatrix(&.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0,
    }, two);
    // NLAG beyond the number of periods: every row is 0.
    const far = (try lag(a, &ds, "effect L5 = lag(treatment / within=subject period=period nlag=5);")).built;
    for (far.x) |v| try t_.expectEqual(@as(f64, 0), v);
    // DESIGNROLE=: Gelindo's period-2 row moves to the scoring design, so in
    // the fitting design Gelindo period 3 has no lagged observation (missing)
    // and the scoring-design row itself is at period 2 with no period 1 (missing).
    @constCast(ds.rows.items[7])[3] = .{ .num = 0 }; // test-owned row
    const role = try lag(a, &ds, "effect R = lag(treatment / within=subject period=period designrole=role);");
    try t_.expect(!role.fit_row[7] and role.fit_row[11] and role.fit_row[0]);
    try t_.expect(std.math.isNan(role.built.at(7, 0)) and std.math.isNan(role.built.at(11, 0)));
    try t_.expectEqual(@as(f64, 1), role.built.at(5, 0)); // Joey p2 <- A
    // A two-variable WITHIN= list: (subject role) splits subjects by role too.
    const wl = (try lag(a, &ds, "effect W = lag(treatment / within=(subject role) period=period);")).built;
    try t_.expect(std.math.isNan(wl.at(7, 0)) and std.math.isNan(wl.at(11, 0)));
}

const Class = enum { user, gap };
fn expectFail(a: A, ds: *const Dataset, classes: []const usize, src: []const u8, want: Class, needle: []const u8) !void {
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const r = parseSrc(a, &d, ds, classes, src);
    try t_.expectError(error.ParseError, r);
    try t_.expect(d.hasErrors());
    // D-009: user error -> exit class 1, loud gap -> exit class 2.
    try t_.expectEqual(@as(u8, if (want == .gap) 2 else 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    const rendered = try d.render();
    if (std.mem.indexOf(u8, rendered, needle) == null) {
        std.debug.print("missing '{s}' in: {s}\n", .{ needle, rendered });
        return error.TestExpectedEqual;
    }
}

test "STAT-COMMON-021 EFFECT applicability: user errors are class 1, unverified forms are class 2" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try lagData(a);
    const cls = &[_]usize{2};
    const users = [_]struct { []const u8, []const u8 }{
        .{ "effect subject=collection(period);", "cannot be the name of a variable" },
        .{ "effect earlier=collection(period);", "can appear in only one EFFECT statement" },
        .{ "effect e=collection period;", "expected EFFECT effect-name" },
        .{ "effect e=poly(period);", "is not a COLLECTION or LAG effect type" },
        .{ "effect e=collection(nosuch);", "Variable nosuch not found" },
        .{ "effect e=collection(period / nlag=2);", "only DETAILS is allowed" },
        .{ "effect e=collection(subject);", "must appear in the CLASS statement" },
        .{ "effect e=lag(treatment period / within=subject period=period);", "exactly one variable" },
        .{ "effect e=lag(treatment / period=period);", "WITHIN= option is required" },
        .{ "effect e=lag(treatment / within=subject);", "PERIOD= option is required" },
        .{ "effect e=lag(treatment / within=subject period=period nlag=0);", "NLAG= requires a positive integer" },
        .{ "effect e=lag(treatment / within=subject period=period nlag=1.5);", "NLAG= requires a positive integer" },
        .{ "effect e=lag(treatment / within=subject period=period designrole=subject);", "must be numeric" },
        .{ "effect e=lag(treatment / within=nosuch period=period);", "Variable nosuch not found" },
        .{ "effect e=lag(treatment / within=(subject period=period);", "is not closed" },
        .{ "effect e=lag(treatment / within=subject period=period bogus);", "invalid lag effect option bogus" },
    };
    for (users) |c| try expectFail(a, &ds, cls, c[0], .user, c[1]);
    const gaps = [_]struct { []const u8, []const u8 }{
        .{ "effect e=collection(period period);", "listed more than once" },
        .{ "effect e=collection(period / details details);", "DETAILS option is repeated" },
        .{ "effect e=lag(period / within=subject period=period);", "continuous lagged variable is not verified" },
        .{ "effect e=lag(treatment / within=subject period=period nlag=1 nlag=2);", "NLAG= option is repeated" },
    };
    for (gaps) |c| try expectFail(a, &ds, cls, c[0], .gap, c[1]);
}

test "STAT-COMMON-021 lag build: invalid design is class 1, unverified data shapes are class 2" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try lagData(a);
    const Case = struct { mutate: *const fn (*Dataset) void, want: Class, needle: []const u8 };
    const cases = [_]Case{
        .{
            .mutate = struct {
                fn f(x: *Dataset) void {
                    @constCast(x.rows.items[1])[0] = .{ .str = "Sheila" }; // Sheila twice in period 1
                }
            }.f,
            .want = .user,
            .needle = "more than one observation in period 1",
        },
        .{ .mutate = struct {
            fn f(x: *Dataset) void {
                @constCast(x.rows.items[0])[1] = .{ .num = nan };
            }
        }.f, .want = .gap, .needle = "missing PERIOD= value" },
        .{ .mutate = struct {
            fn f(x: *Dataset) void {
                @constCast(x.rows.items[0])[0] = .{ .str = "" };
            }
        }.f, .want = .gap, .needle = "missing WITHIN= value" },
        .{ .mutate = struct {
            fn f(x: *Dataset) void {
                @constCast(x.rows.items[0])[3] = .{ .num = nan };
            }
        }.f, .want = .gap, .needle = "missing DESIGNROLE= value" },
    };
    for (cases) |c| {
        var copy = Dataset.init(a, "lag");
        for (ds.columns.items) |col| _ = try copy.addColumn(col.name, col.type);
        for (ds.rows.items) |row| try copy.appendRow(row);
        c.mutate(&copy);
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const s = try parseSrc(a, &d, &copy, &.{2}, "effect e=lag(treatment / within=subject period=period designrole=role);");
        try t_.expectError(error.ParseError, ce.buildLag(a, &d, &copy, copy.rows.items, s.name, s.body.lag, 1));
        try t_.expectEqual(@as(u8, if (c.want == .gap) 2 else 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        const rendered = try d.render();
        if (std.mem.indexOf(u8, rendered, c.needle) == null) {
            std.debug.print("missing '{s}' in: {s}\n", .{ c.needle, rendered });
            return error.TestExpectedEqual;
        }
    }
    // A numeric PERIOD= sorts by value (formatted order of an unformatted
    // number): Sheila at period 10 follows her period 3 (B), not period 1.
    var copy = Dataset.init(a, "lag");
    for (ds.columns.items) |col| _ = try copy.addColumn(col.name, col.type);
    for (ds.rows.items) |row| try copy.appendRow(row);
    @constCast(copy.rows.items[0])[1] = .{ .num = 10 };
    const ten = (try lag(a, &copy, "effect e=lag(treatment / within=subject period=period);")).built;
    try t_.expectEqualSlices(f64, &.{ 0, 1, 0 }, ten.x[0..3]);
    // Periods are global (1, 2, 3, 10): Sheila's period 2 is not an initial
    // period and her period 1 entry of the lag design is absent -> missing.
    for (ten.x[12..15]) |v| try t_.expect(std.math.isNan(v));
}

test "STAT-COMMON-021 DESIGNROLE: a zero role with a nonmissing response is a user error" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try lagData(a);
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, &ds, &.{2}, "effect L2 = lag(treatment / within=subject period=period designrole=role);");
    // Every role is 1: nothing to check. Column 1 (period) stands in for the response.
    try ce.checkDesignRole(&d, &ds, ds.rows.items, s.body.lag, 1, s.name, 1);
    try t_.expect(!d.hasErrors());
    @constCast(ds.rows.items[7])[3] = .{ .num = 0 };
    diag.resetGap();
    defer diag.resetGap();
    try t_.expectError(error.ParseError, ce.checkDesignRole(&d, &ds, ds.rows.items, s.body.lag, 1, s.name, 1));
    try t_.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    const r = try d.render();
    // SAS/STAT 15.4 log text (GLMSELECT probe).
    try t_.expect(std.mem.indexOf(u8, r, "In the EFFECT L2 = LAG statement, zero values of the DESIGNROLE variable role must correspond to observations where the response value is missing.") != null);
}
