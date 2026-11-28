//! STAT-FREQ-015: hand-calculated Gail-Simon checks (SAS/STAT 15.4 PROC FREQ,
//! "Gail-Simon Test for Qualitative Interactions"). Statistics are exact
//! rationals derived in the comments; p-values use the documented mixture
//!   P(Q+-) = sum_{h=1..q} B(h; q, 1/2) (1 - F_h(Q+-)),
//!   P(Q)   = sum_{h=1..q-1} B(h; q-1, 1/2) (1 - F_h(Q)),
//! with chi-square tails computed HERE from closed forms, independently of the
//! production incomplete-gamma code. Nothing is copied from OpenSAS output.
//!
//! Orientation: the displayed "Q+ (Positive Risk Differences)" row sums
//! (d_h/s_h)^2 over strata with d_h > 0 and "Q- (Negative Risk Differences)"
//! over d_h < 0. That follows the documented display labels and prose ("a
//! small p-value for Q+ indicates positive risk differences") and the SAS
//! listings pinned in tests/corpus/freq_stratified_weights.txt; the printed
//! formula on the same page attaches the opposite indicator to each symbol.
//!
//! Bounds: statistics are O(10) operations on O(1) rationals, so 1e-12
//! absolute. The independent tails are accurate to < 1e-13 (see chi1Tail);
//! p-values are compared at 1e-10, an a-priori bound five orders below the
//! printed 4-decimal unit, not a value fitted to an observed difference.
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const k = @import("freq_stratified.zig");
const common = @import("freq_stratified_risk.zig");
const parse = @import("freq_stratified_parse.zig");
const execute = @import("freq_stratified_execute.zig");
const model = @import("freq_table.zig");
const Table = common.Table;
const tol = 1e-12;
const ptol = 1e-10;

/// chi-square(1) upper tail erfc(sqrt(q/2)) by the Maclaurin series of erf.
/// For x = sqrt(q/2) <= 2 the largest term is < 3 and 80 terms leave a
/// remainder far below 1e-15; cancellation is bounded by 3 * 80 * 2^-52.
fn chi1Tail(q: f64) f64 {
    const x = @sqrt(q / 2);
    std.debug.assert(x <= 2);
    var term = x;
    var sum = x;
    var n: f64 = 1;
    while (n < 80) : (n += 1) {
        term *= -x * x / n;
        sum += term / (2 * n + 1);
    }
    return 1 - 2.0 / @sqrt(@as(f64, std.math.pi)) * sum;
}
/// Closed-form chi-square upper tails for 1..4 degrees of freedom:
/// h=2: e^(-q/2); h=3: tail_1 + sqrt(2q/pi) e^(-q/2); h=4: e^(-q/2)(1 + q/2).
fn chiTail(q: f64, h: usize) f64 {
    if (q == 0) return 1;
    return switch (h) {
        1 => chi1Tail(q),
        2 => @exp(-q / 2),
        3 => chi1Tail(q) + @sqrt(2 * q / std.math.pi) * @exp(-q / 2),
        4 => @exp(-q / 2) * (1 + q / 2),
        else => unreachable,
    };
}
/// sum_{h=1..n} C(n,h) 2^-n tail_h(q), binomial coefficients as exact integers.
fn mixture(q: f64, comptime n: usize) f64 {
    const rows = [_][]const f64{ &.{}, &.{1}, &.{ 2, 1 }, &.{ 3, 3, 1 }, &.{ 4, 6, 4, 1 } };
    var p: f64 = 0;
    for (rows[n], 1..) |c, h| p += c / @as(f64, @floatFromInt(@as(usize, 1) << n)) * chiTail(q, h);
    return p;
}
fn expectGs(pos: f64, neg: f64, comptime q: usize, actual: ?k.GailSimon) !void {
    const got = actual orelse return error.TestExpectedEqual;
    const two = @min(pos, neg);
    try std.testing.expectApproxEqAbs(pos, got.positive, tol);
    try std.testing.expectApproxEqAbs(neg, got.negative, tol);
    try std.testing.expectApproxEqAbs(two, got.two_sided, tol);
    try std.testing.expectApproxEqAbs(mixture(pos, q), got.p_positive, ptol);
    try std.testing.expectApproxEqAbs(mixture(neg, q), got.p_negative, ptol);
    try std.testing.expectApproxEqAbs(mixture(two, q - 1), got.p_two, ptol);
}

// Strata (row1 = a b, row2 = c d), column 1 risk difference d = a/(a+b) - c/(c+d),
// s^2 = p1(1-p1)/n1 + p2(1-p2)/n2:
//   A = 3 1 / 1 3: d = 3/4 - 1/4 = 1/2,  s^2 = 3/64 + 3/64 = 3/32, (d/s)^2 = 8/3
//   B = 1 4 / 3 2: d = 1/5 - 3/5 = -2/5, s^2 = 4/125 + 6/125 = 2/25, (d/s)^2 = 2
//   C = 2 2 / 1 3: d = 1/2 - 1/4 = 1/4,  s^2 = 1/16 + 3/64 = 7/64, (d/s)^2 = 4/7
//   D = 4 1 / 2 3: d = 4/5 - 2/5 = 2/5,  s^2 = 4/125 + 6/125 = 2/25, (d/s)^2 = 2
const sA = Table{ .cells = .{ 3, 1, 1, 3 } };
const sB = Table{ .cells = .{ 1, 4, 3, 2 } };
const sC = Table{ .cells = .{ 2, 2, 1, 3 } };
const sD = Table{ .cells = .{ 4, 1, 2, 3 } };

test "STAT-FREQ-015 Gail-Simon exact rational strata and mixture p-values" {
    const a = std.testing.allocator;
    // The independent tail itself: chi-square(1) at 1.96^2 is the two-sided
    // normal 5% point, P = 0.0500 (4 printed decimals of 0.04999579...).
    try std.testing.expectApproxEqAbs(@as(f64, 0.04999579029644087), chi1Tail(1.96 * 1.96), 1e-13);
    // q = 3: Q+ = 8/3 + 4/7 = 68/21, Q- = 2, Q = 2.
    //   P(Q) = 1/2 tail_1(2) + 1/4 e^-1 = 0.170619...
    //   P(Q-) = 3/8 tail_1(2) + 3/8 e^-1 + 1/8 tail_3(2) = 0.268492...
    const abc = [_]Table{ sA, sB, sC };
    const first = try common.gailSimon(a, &abc, .first);
    try expectGs(68.0 / 21.0, 2, 3, first);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1706194638), first.?.p_two, 5e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2684928311), first.?.p_negative, 5e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1458058102), first.?.p_positive, 5e-11);
    // COLUMN=2 risks are the complements, so every d_h changes sign with the
    // same s_h: Q+ and Q- exchange, Q is unchanged.
    try expectGs(2, 68.0 / 21.0, 3, try common.gailSimon(a, &abc, .second));
    // q = 4 exercises the 4- and 3-trial binomial weights (1 4 6 4 1)/16 and
    // (1 3 3 1)/8: Q+ = 68/21 + 2 = 110/21, Q- = 2.
    try expectGs(110.0 / 21.0, 2, 4, try common.gailSimon(a, &.{ sA, sB, sC, sD }, .first));
    // The kernel receives (d, s^2) pairs directly; same rationals.
    const direct = [_]k.Estimate{
        .{ .value = 0.5, .variance = 3.0 / 32.0, .lower = 0, .upper = 0 },
        .{ .value = -0.4, .variance = 2.0 / 25.0, .lower = 0, .upper = 0 },
        .{ .value = 0.25, .variance = 7.0 / 64.0, .lower = 0, .upper = 0 },
    };
    try expectGs(68.0 / 21.0, 2, 3, try k.gailSimon(&direct));
}

test "STAT-FREQ-015 Gail-Simon degenerate and boundary strata" {
    const a = std.testing.allocator;
    // A stratum with an empty row has no risk difference and is not counted in
    // q (SAS listing pinned in tests/corpus/freq_stratified_weights.txt: three
    // strata, one empty row, P(Q-=0) = 0.75 = 1 - 2^-2). Results equal q = 3.
    const empty_row = Table{ .cells = .{ 2, 2, 0, 0 } };
    const all_zero = Table{ .cells = .{ 0, 0, 0, 0 } };
    try expectGs(68.0 / 21.0, 2, 3, try common.gailSimon(a, &.{ sA, empty_row, sB, all_zero, sC }, .first));
    // d_h = 0 (2 2 / 3 3: 1/2 - 1/2, s^2 = 1/16 + 1/24 > 0) enters neither sum
    // but still counts in q. With B: Q+ = 0, Q- = 2, Q = 0;
    // P(Q+) = 1/2 + 1/4 = 3/4 and P(Q) = 1/2 because every tail at 0 is 1.
    const tie = Table{ .cells = .{ 2, 2, 3, 3 } };
    const two = (try common.gailSimon(a, &.{ tie, sB }, .first)).?;
    try expectGs(0, 2, 2, two);
    // (Weights come from exp/lgamma in production, so 1e-12, not bit equality.)
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), two.p_positive, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), two.p_two, tol);
    // Three tied strata: P(Q+-) = 1 - 2^-3 = 7/8, P(Q) = 1 - 2^-2 = 3/4.
    const ties = (try common.gailSimon(a, &.{ tie, .{ .cells = .{ 1, 1, 2, 2 } }, .{ .cells = .{ 3, 3, 1, 1 } } }, .first)).?;
    try std.testing.expectEqual(@as(f64, 0), ties.two_sided);
    try std.testing.expectApproxEqAbs(@as(f64, 0.875), ties.p_positive, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 0.875), ties.p_negative, tol);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), ties.p_two, tol);
    // Fewer than two usable strata: no qualitative interaction test exists.
    try std.testing.expect((try common.gailSimon(a, &.{sA}, .first)) == null);
    try std.testing.expect((try common.gailSimon(a, &.{ sA, empty_row }, .first)) == null);
    try std.testing.expect((try common.gailSimon(a, &.{}, .first)) == null);
    // A stratum whose risks are both 0 or 1 has s_h = 0, so d_h/s_h is
    // undefined and the whole test is undefined (status null, never a number).
    // SAS prints no Gail-Simon table for this shape: see the 9 0 / 0 6 stratum
    // in the SAS listing pinned by tests/corpus/freq_stratified_scores.txt.
    try std.testing.expect((try common.gailSimon(a, &.{ .{ .cells = .{ 9, 0, 0, 6 } }, sB }, .first)) == null);
    try std.testing.expect((try common.gailSimon(a, &.{ sA, .{ .cells = .{ 5, 0, 5, 0 } }, sB }, .second)) == null);
    // Invalid inputs are errors, not statistics.
    try std.testing.expectError(error.ExecError, common.gailSimon(a, &.{ sA, .{ .cells = .{ -1, 2, 1, 3 } } }, .first));
    const bad = [_]k.Estimate{ .{ .value = std.math.nan(f64), .variance = 1, .lower = 0, .upper = 0 }, .{ .value = 1, .variance = 1, .lower = 0, .upper = 0 } };
    try std.testing.expectError(error.ExecError, k.gailSimon(&bad));
}

/// s (strata levels) x r (2) x c (2) frequency table as the FREQ driver builds it.
fn stratifiedTable(a: std.mem.Allocator, strata: usize) !model.Table {
    const dims = try a.alloc(model.Dimension, 3);
    for (dims, 0..) |*dimension, i| {
        const levels = try a.alloc(model.Level, if (i == 0) strata else 2);
        for (levels, 0..) |*level, j| {
            const v: f64 = @floatFromInt(j + 1);
            level.* = .{ .value = .{ .num = v }, .raw = .{ .num = v }, .missing = false, .frequency = 0 };
        }
        dimension.* = .{ .name = try std.fmt.allocPrint(a, "v{d}", .{i}), .levels = levels };
    }
    return model.Table.init(a, dims, false);
}

test "STAT-FREQ-015 Gail-Simon options, listing rows and undefined status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Documented spellings: GAILSIMON / GS, optional (COLUMN=1|2), as a TABLES
    // option or a CMH suboption with the same effect.
    const cases = [_]struct { src: []const u8, column: @TypeOf(@as(parse.Options, .{}).gail_column), cmh: u2 }{
        .{ .src = "gailsimon", .column = .first, .cmh = 0 },
        .{ .src = "GS", .column = .first, .cmh = 0 },
        .{ .src = "gailsimon(column=1)", .column = .first, .cmh = 0 },
        .{ .src = "gs(column=2)", .column = .second, .cmh = 0 },
        .{ .src = "cmh(gailsimon(column=2))", .column = .second, .cmh = 3 },
        .{ .src = "cmh1(gs)", .column = .first, .cmh = 1 },
    };
    for (cases) |c| {
        var d = diag.Diagnostics.init(a);
        const tokens = try lex.tokenize(a, c.src, &d);
        var i: usize = 0;
        var opts = parse.Options{};
        try std.testing.expect(try parse.consumeTableOption(tokens, &i, &opts, &d));
        try std.testing.expect(opts.gail_simon and !d.hasErrors());
        try std.testing.expectEqual(c.column, opts.gail_column);
        try std.testing.expectEqual(c.cmh, opts.cmh);
    }
    // Undocumented values/suboptions are captured errors, never ignored.
    for ([_][]const u8{ "gailsimon(column=3)", "gailsimon(column=0)", "gs(column)", "gailsimon(row=1)", "cmh(gailsimon(column=1.5))", "gailsimon(column=2" }) |src| {
        var d = diag.Diagnostics.init(a);
        const tokens = try lex.tokenize(a, src, &d);
        var i: usize = 0;
        var opts = parse.Options{};
        try std.testing.expectError(error.ParseError, parse.consumeTableOption(tokens, &i, &opts, &d));
        try std.testing.expect(d.hasErrors() and !opts.gail_simon);
    }
    // Strata A, B, C through the execution boundary (cells in s, r, c order).
    var d = diag.Diagnostics.init(a);
    var table = try stratifiedTable(a, 3);
    for ([_]f64{ 3, 1, 1, 3, 1, 4, 3, 2, 2, 2, 1, 3 }, 0..) |v, i| try table.add(a, i, v);
    var options = parse.Options{ .gail_simon = true };
    const report = try execute.compute(a, &d, &table, options, .{});
    try std.testing.expect(!d.hasErrors());
    try expectGs(68.0 / 21.0, 2, 3, report.gail_simon);
    var out: std.ArrayList(u8) = .empty;
    try execute.listing(a, &out, report, options, .{}, .table, false);
    // 68/21 = 3.2381, P = 0.1458; 2.0000 with P(q=3) = 0.2685 and P(Q) = 0.1706.
    for ([_][]const u8{ "Gail-Simon Test for Qualitative Interactions", "Q+ (Positive Risk Differences)          3.2381    0.1458", "Q- (Negative Risk Differences)          2.0000    0.2685", "Q (Two-Sided)                           2.0000    0.1706" }) |line| {
        try std.testing.expect(std.mem.indexOf(u8, out.items, line) != null);
    }
    options.gail_column = .second;
    const second = try execute.compute(a, &d, &table, options, .{});
    try expectGs(2, 68.0 / 21.0, 3, second.gail_simon);
    out.clearRetainingCapacity();
    try execute.listing(a, &out, second, options, .{}, .table, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Q+ (Positive Risk Differences)          2.0000    0.2685") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Q- (Negative Risk Differences)          3.2381    0.1458") != null);
    // Zero standard error stratum (9 0 / 0 6) with a regular one: the result
    // status is undefined, no table and no fabricated values are listed, and
    // no diagnostic is raised (SAS listing: freq_stratified_scores.txt).
    var undefined_table = try stratifiedTable(a, 2);
    for ([_]f64{ 9, 0, 0, 6, 1, 4, 3, 2 }, 0..) |v, i| try undefined_table.add(a, i, v);
    options.gail_column = .first;
    const none = try execute.compute(a, &d, &undefined_table, options, .{});
    try std.testing.expect(none.gail_simon == null and !d.hasErrors());
    out.clearRetainingCapacity();
    try execute.listing(a, &out, none, options, .{}, .table, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Gail-Simon") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Q+") == null);
}
