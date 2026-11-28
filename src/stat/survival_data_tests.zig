//! STAT-COMMON-015 permanent checks for the shared survival-data contract.
//! All data are invented; every expected count below was enumerated by hand
//! from the listed rows (number at risk at t = total FREQ of the stratum's
//! used observations with time >= t).
const std = @import("std");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const sd = @import("survival_data.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

fn n(x: f64) Value {
    return .{ .num = x };
}
fn s(x: []const u8) Value {
    return .{ .str = x };
}
/// time, at risk, events, censored.
const Counts = struct { f64, f64, f64, f64 };
fn expectCounts(table: sd.RiskTable, expected: []const Counts) !void {
    try expectEqual(expected.len, table.rows.len);
    for (table.rows, expected) |row, e| {
        try expectEqual(e[0], row.time);
        try expectEqual(e[1], row.at_risk);
        try expectEqual(e[2], row.events);
        try expectEqual(e[3], row.censored);
    }
}
fn expectTotals(table: sd.RiskTable, total: f64, events: f64, censored: f64) !void {
    try expectEqual(total, table.total);
    try expectEqual(events, table.events);
    try expectEqual(censored, table.censored);
}

test "STAT-COMMON-015 coincident event and censoring within strata: censoring follows the event" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    // time status group; group B is listed first and with trailing blanks to
    // show that level order is by value, not by appearance or padding.
    const rows = [_][]const Value{
        &.{ n(1), n(0), s("B  ") }, &.{ n(3), n(1), s("B") }, &.{ n(4), n(1), s("B") }, &.{ n(6), n(0), s("B") }, &.{ n(7), n(1), s("B ") },
        &.{ n(1), n(1), s("A") },   &.{ n(2), n(0), s("A") }, &.{ n(2), n(1), s("A") }, &.{ n(4), n(1), s("A") }, &.{ n(5), n(0), s("A") },
    };
    const c = try sd.classify(a, &d, 0, .lifetest, .{ .response = .{ .right = .{ .time = 0, .censor = 1, .censor_values = &.{0} } }, .strata = &.{2} }, &rows);
    try expect(!d.hasErrors());
    try expectEqual(@as(usize, 2), c.strataCount());
    try expectEqual(@as(usize, 10), c.obs.len);
    try expect(std.mem.eql(u8, "A", c.levels[0][2].str));
    try expect(c.status[0] == .right_censored and c.status[1] == .event);
    try expectEqual(@as(usize, 1), c.obs[0].stratum);
    try expectEqual(@as(usize, 0), c.obs[5].stratum);
    const t = try sd.riskTables(a, c);
    // A: at time 2 one event and one censoring coincide; both are among the
    // 4 at risk, and only 2 remain at time 4.
    try expectCounts(t[0], &.{ .{ 1, 5, 1, 0 }, .{ 2, 4, 1, 1 }, .{ 4, 2, 1, 0 }, .{ 5, 1, 0, 1 } });
    try expectCounts(t[1], &.{ .{ 1, 5, 0, 1 }, .{ 3, 4, 1, 0 }, .{ 4, 3, 1, 0 }, .{ 6, 2, 0, 1 }, .{ 7, 1, 1, 0 } });
    // The SAS censoring summary for this sample: 5 total, 3 failed, 2 censored in each stratum.
    try expectTotals(t[0], 5, 3, 2);
    try expectTotals(t[1], 5, 3, 2);
}

/// Columns t c g f w.
const mixed = [_][]const Value{
    &.{ n(3), n(1), n(2), n(2.7), n(0.5) }, // 0 event, FREQ truncates to 2
    &.{ n(3), n(0), n(2), n(1), n(2) }, // 1 censored at the event time
    &.{ n(3), n(2), n(2), n(1), n(1) }, // 2 censored by the second listed value
    &.{ n(5), n(1), n(2), n(3), n(1) }, // 3 event
    &.{ n(1), n(0), n(1), n(1), n(1) }, // 4 stratum 1 holds censored times only
    &.{ n(4), n(0), n(1), n(2), n(1.5) }, // 5
    &.{ n(9), n(1), n(3), n(1), n(4) }, // 6 single-observation stratum
    &.{ n(nan), n(1), n(2), n(1), n(1) }, // 7 missing time
    &.{ n(2), n(nan), n(2), n(1), n(1) }, // 8 missing censoring value
    &.{ n(2), n(1), n(nan), n(1), n(1) }, // 9 missing stratum
    &.{ n(2), n(1), n(2), n(nan), n(1) }, // 10 missing FREQ
    &.{ n(2), n(1), n(2), n(0.9), n(1) }, // 11 FREQ truncates to 0
    &.{ n(2), n(1), n(2), n(1), n(0) }, // 12 zero WEIGHT
    &.{ n(2), n(1), n(2), n(1), n(nan) }, // 13 missing WEIGHT
};
const mixed_roles: sd.Roles = .{ .response = .{ .right = .{ .time = 0, .censor = 1, .censor_values = &.{ 0, 2 } } }, .strata = &.{2}, .frequency = 3, .weight = 4 };

test "STAT-COMMON-015 all-censored and single-observation strata, exclusions, FREQ and WEIGHT totals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const c = try sd.classify(a, &d, 0, .lifetest, mixed_roles, &mixed);
    const reasons = [_]sd.Exclusion{ .missing_time, .missing_censor, .missing_stratum, .missing_frequency, .nonpositive_frequency, .nonpositive_weight, .nonpositive_weight };
    for (reasons, 7..) |reason, k| try expectEqual(sd.Status{ .excluded = reason }, c.status[k]);
    try expectEqual(@as(usize, 2), c.excluded(.nonpositive_weight));
    try expectEqual(@as(usize, 1), c.excluded(.missing_stratum));
    try expectEqual(@as(usize, 7), c.obs.len);
    try expect(c.status[0] == .event and c.status[1] == .right_censored and c.status[2] == .right_censored);
    try expectEqual(@as(usize, 3), c.strataCount());
    try expectEqual(@as(f64, 1), c.levels[0][2].num);
    try expectEqual(@as(f64, 3), c.levels[2][2].num);
    const t = try sd.riskTables(a, c);
    // Stratum g=1: FREQ 1 censored at 1, FREQ 2 censored at 4; no event.
    try expectCounts(t[0], &.{ .{ 1, 3, 0, 1 }, .{ 4, 2, 0, 2 } });
    try expectTotals(t[0], 3, 0, 3);
    try expectEqual(@as(f64, 4), t[0].rows[0].weighted_at_risk); // 1*1 + 2*1.5
    try expectEqual(@as(f64, 3), t[0].rows[1].weighted_censored);
    // Stratum g=2: FREQ 2+1+1 at time 3 (2 events, 2 censored), FREQ 3 at 5.
    try expectCounts(t[1], &.{ .{ 3, 7, 2, 2 }, .{ 5, 3, 3, 0 } });
    try expectTotals(t[1], 7, 5, 2);
    try expectEqual(@as(f64, 7), t[1].rows[0].weighted_at_risk); // 2*.5 + 1*2 + 1*1 + 3*1
    try expectEqual(@as(f64, 1), t[1].rows[0].weighted_events);
    try expectEqual(@as(f64, 3), t[1].rows[0].weighted_censored);
    try expectEqual(@as(f64, 3), t[1].rows[1].weighted_events);
    // Stratum g=3: one event.
    try expectCounts(t[2], &.{.{ 9, 1, 1, 0 }});
    try expectTotals(t[2], 1, 1, 0);
    try expectEqual(@as(f64, 4), t[2].rows[0].weighted_at_risk);
}

test "STAT-COMMON-015 MISSING stratum level, NOTRUNCATE frequencies, no censoring variable, no strata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var roles = mixed_roles;
    roles.missing = true;
    roles.notruncate = true;
    const c = try sd.classify(a, &d, 0, .phreg, roles, &mixed);
    try expect(c.status[9] == .event and c.status[11] == .event);
    try expectEqual(@as(usize, 4), c.strataCount());
    try expect(std.math.isNan(c.levels[0][2].num)); // the missing level sorts first
    const t = try sd.riskTables(a, c);
    try expectCounts(t[0], &.{.{ 2, 1, 1, 0 }});
    // g=2 now holds FREQ 0.9 at time 2 and 2.7, 1, 1 at time 3, 3 at time 5.
    const g2 = t[2];
    try expectEqual(@as(usize, 3), g2.rows.len);
    const expected = [_]Counts{ .{ 2, 8.6, 0.9, 0 }, .{ 3, 7.7, 2.7, 2 }, .{ 5, 3, 3, 0 } };
    for (g2.rows, expected) |row, e| {
        try expectEqual(e[0], row.time);
        // Sums of at most five such terms are within a few ulp of the exact value.
        try std.testing.expectApproxEqAbs(e[1], row.at_risk, 1e-12);
        try std.testing.expectApproxEqAbs(e[2], row.events, 1e-12);
        try expectEqual(e[3], row.censored);
    }
    // Without a censoring variable every used observation is an event, and
    // without strata there is one stratum.
    const plain = try sd.classify(a, &d, 0, .lifetest, .{ .response = .{ .right = .{ .time = 0 } } }, &mixed);
    try expectEqual(@as(usize, 1), plain.strataCount());
    try expectEqual(@as(usize, 0), plain.levels.len);
    try expectEqual(@as(usize, 13), plain.obs.len);
    try expectEqual(@as(usize, 1), plain.excluded(.missing_time));
    const all = try sd.riskTable(a, plain.obs, 0);
    // Times: 1 | 2 x6 | 3 x3 | 4 | 5 | 9.
    try expectCounts(all, &.{ .{ 1, 13, 1, 0 }, .{ 2, 12, 6, 0 }, .{ 3, 6, 3, 0 }, .{ 4, 3, 1, 0 }, .{ 5, 2, 1, 0 }, .{ 9, 1, 1, 0 } });
    try expectTotals(all, 13, 13, 0);
    // No usable observation: one empty table, never a fabricated row.
    const none = try sd.classify(a, &d, 0, .lifetest, .{ .response = .{ .right = .{ .time = 0 } } }, mixed[7..8]);
    const empty = try sd.riskTables(a, none);
    try expectEqual(@as(usize, 1), empty.len);
    try expectEqual(@as(usize, 0), empty[0].rows.len);
    try expectTotals(empty[0], 0, 0, 0);
    try expect(!d.hasErrors());
}

fn rejection(procedure: sd.Procedure, response: sd.Response, text: []const u8) !u8 {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    // classify refuses the encoding before reading any row.
    try std.testing.expectError(error.ParseError, sd.classify(a, &d, 7, procedure, .{ .response = response }, &mixed));
    try expect(std.mem.indexOf(u8, try d.render(), text) != null);
    return diag.exitCode(diag.gapHit(), d.hasErrors());
}

test "STAT-COMMON-015 incompatible encodings are user errors and unimplemented ones are gaps" {
    const counting: sd.Response = .{ .counting = .{ .start = 0, .stop = 1, .censor = 2, .censor_values = &.{0} } };
    const interval: sd.Response = .{ .interval = .{ .lower = 0, .upper = 1 } };
    const right: sd.Response = .{ .right = .{ .time = 0, .censor = 1, .censor_values = &.{0} } };
    // LIFETEST handles right-censored data only; PHREG has no interval censoring.
    try expectEqual(@as(u8, 1), try rejection(.lifetest, counting, "PROC LIFETEST: counting-process (left-truncated) response is not valid"));
    try expectEqual(@as(u8, 1), try rejection(.lifetest, interval, "PROC LIFETEST: interval-censored response is not valid"));
    try expectEqual(@as(u8, 1), try rejection(.phreg, interval, "PROC PHREG: interval-censored response is not valid"));
    // Valid SAS that no landed ticket executes.
    try expectEqual(@as(u8, 2), try rejection(.phreg, counting, "PROC PHREG: counting-process (left-truncated) response is not implemented"));
    try expectEqual(@as(u8, 2), try rejection(.iclifetest, interval, "is not implemented"));
    try expectEqual(@as(u8, 2), try rejection(.icphreg, interval, "is not implemented"));
    try expectEqual(@as(u8, 2), try rejection(.lifereg, right, "is not implemented"));
    try expectEqual(sd.Support.supported, sd.support(.lifetest, right));
    try expectEqual(sd.Support.supported, sd.support(.phreg, right));
    // A supported encoding raises nothing.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(arena.allocator());
    try sd.check(&d, 0, .phreg, right);
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
}
