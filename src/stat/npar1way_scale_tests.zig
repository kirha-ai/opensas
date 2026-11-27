//! Executable S154 physical pp.7239-7241 score definitions, independent of
//! engine-generated goldens. Defaults remain the original four score families.
const std = @import("std");
const k = @import("npar1way_stats.zig");
const t = std.testing;
fn only(kind: k.Kind) k.Options {
    var o: k.Options = .{ .anova = false, .wilcoxon = false, .median = false, .vw = false, .savage = false, .edf = false };
    switch (kind) {
        .ab => o.ab = true,
        .st => o.st = true,
        .klotz => o.klotz = true,
        .mood => o.mood = true,
        .conover => o.conover = true,
        .data => o.data = true,
        else => unreachable,
    }
    return o;
}
test "NPAR004 scale score definitions and transform-before-tie contracts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 2, 3, 8 };
    const groups = [_]usize{ 0, 0, 1, 1 };
    const cases = [_]struct { kind: k.Kind, want: [4]f64 }{
        .{ .kind = .ab, .want = .{ 1, 2, 2, 1 } },
        .{ .kind = .st, .want = .{ 1, 4, 3, 2 } },
        .{ .kind = .mood, .want = .{ 2.25, 0.25, 0.25, 2.25 } },
        .{ .kind = .conover, .want = .{ 2.25, 2.25, 12.25, 12.25 } },
        .{ .kind = .data, .want = .{ 1, 2, 3, 8 } },
    };
    for (cases) |case| {
        const r = try k.compute(a, &x, &groups, 2, only(case.kind));
        try t.expectEqual(@as(usize, 1), r.scores.len);
        try t.expectEqualSlices(f64, &case.want, r.scores[0].values);
    }
    const conover = (try k.compute(a, &x, &groups, 2, only(.conover))).scores[0];
    try t.expect(conover.has_ties);
    try t.expectApproxEqAbs(@as(f64, 3), conover.chi_square.?, 1e-14);
    // Klotz is squared ordinal normal scores; known quantiles at1/5 and2/5.
    const klotz = (try k.compute(a, &x, &groups, 2, only(.klotz))).scores[0];
    const q1 = 0.8416212335729143;
    const q2 = 0.2533471031357997;
    for (klotz.values, [_]f64{ q1 * q1, q2 * q2, q2 * q2, q1 * q1 }) |actual, want| try t.expectApproxEqAbs(want, actual, 2e-14);
    const tied = (try k.compute(a, &.{ 1, 1, 2, 3 }, &groups, 2, only(.mood))).scores[0];
    try t.expectEqualSlices(f64, &.{ 1.25, 1.25, 0.25, 2.25 }, tied.values); // average2.25,0.25, not square(meanrank-2.5)
}
test "NPAR004 Siegel Tukey odd sizes and correction applies only to requested rank tests" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 2, 3, 4, 5, 6, 7 };
    const g = [_]usize{ 0, 0, 0, 1, 1, 1, 1 };
    const corrected = (try k.compute(a, &x, &g, 2, only(.st))).scores[0];
    try t.expectEqualSlices(f64, &.{ 1, 4, 5, 7, 6, 3, 2 }, corrected.values);
    var no = only(.st);
    no.continuity = false;
    const uncorrected = (try k.compute(a, &x, &g, 2, no)).scores[0];
    const sd = uncorrected.groups[0].stddev;
    try t.expectApproxEqAbs(0.5 / sd, corrected.two_sample.?.z.? - uncorrected.two_sample.?.z.?, 1e-14);
    const constant = try k.compute(a, &.{ 1, 1, 1, 1 }, &.{ 0, 0, 1, 1 }, 2, only(.conover));
    try t.expect(constant.scores[0].two_sample.?.z == null);
}
