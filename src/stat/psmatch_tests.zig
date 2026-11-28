//! STAT-PSMATCH-001 unit tests: greedy matching and support region on hand
//! computed propensity scores (independent of the logistic fit).
const std = @import("std");
const ps = @import("psmatch.zig");

fn logit(p: f64) f64 {
    return @log(p / (1 - p));
}

test "STAT-PSMATCH-001 greedy descending matching, region and caliper by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Treated 0.6, 0.5, 0.4; controls 0.55, 0.45.
    var p = [_]f64{ 0.6, 0.55, 0.5, 0.45, 0.4 };
    const treated = [_]bool{ true, false, true, false, true };
    const used = [_]bool{ true, true, true, true, true };
    var g: ps.Group = undefined;
    try ps.matchGreedy(a, &p, &treated, &used, 100, .descending, &g);
    // Pooled SD of logits: treated sample var of {l(.6),l(.5),l(.4)} and
    // control var of {l(.55),l(.45)}.
    const lt = [_]f64{ logit(0.6), 0, logit(0.4) };
    const vt = (lt[0] * lt[0] + lt[2] * lt[2]) / 2;
    const d = logit(0.55) - logit(0.45);
    const vc = d * d / 2;
    const sd = @sqrt((vt + vc) / 2);
    try std.testing.expectApproxEqAbs(100 * sd, g.caliper, 1e-12);
    // CS = [max(l(.4), l(.45)), min(l(.6), l(.55))] extended by 0.25 sd.
    try std.testing.expectApproxEqAbs(1 / (1 + @exp(-(logit(0.45) - 0.25 * sd))), g.lower, 1e-12);
    // sd = 0.3035, so the extended region is [l(.45), l(.55)] -/+ 0.0759:
    // 0.6 and 0.4 (logits +/-0.405) fall outside. 0.5 is equidistant from the
    // two controls (up to rounding).
    try std.testing.expect(!g.in_region[0] and !g.in_region[4]);
    try std.testing.expect(g.in_region[1] and g.in_region[2] and g.in_region[3]);
    try std.testing.expectEqual(@as(usize, 1), g.n_sets);
    try std.testing.expectEqual(@as(usize, 1), g.match_id[2]);
    // l(.55) - 0 and 0 - l(.45) agree only to rounding: exactly one of the
    // two controls is taken.
    try std.testing.expect(g.matched[1] != g.matched[3]);
    try std.testing.expect(!g.matched[0]);
    try std.testing.expect(!g.short_controls);
    try std.testing.expectApproxEqAbs(@abs(logit(0.5) - logit(0.55)), g.total_diff, 1e-12);
}

test "STAT-PSMATCH-001 greedy ascending order and tie on data order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Treated 0.5 (row 0) and 0.4 (row 2); controls 0.45 twice (rows 1, 3),
    // 0.4 (row 4) and 0.6 (row 5). CS = [l(.4), l(.5)], so every treated
    // unit is in the region.
    var p = [_]f64{ 0.5, 0.45, 0.4, 0.45, 0.4, 0.6 };
    const treated = [_]bool{ true, false, true, false, false, false };
    const used = [_]bool{ true, true, true, true, true, true };
    var g: ps.Group = undefined;
    try ps.matchGreedy(a, &p, &treated, &used, 100, .ascending, &g);
    // Ascending: 0.4 first -> control 0.4 (row 4, set 1); 0.5 -> the 0.45
    // tie resolves to the first in data order (row 1, set 2).
    try std.testing.expect(g.in_region[0] and g.in_region[2]);
    try std.testing.expectEqual(@as(usize, 1), g.match_id[2]);
    try std.testing.expectEqual(@as(usize, 1), g.match_id[4]);
    try std.testing.expectEqual(@as(usize, 2), g.match_id[0]);
    try std.testing.expectEqual(@as(usize, 2), g.match_id[1]);
    try std.testing.expect(!g.matched[3] and !g.matched[5]);
    try std.testing.expect(!g.short_controls);
}

test "STAT-PSMATCH-001 caliper leaves a distant treated unit unmatched" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Treated 0.5, 0.45, 0.4 (rows 0-2); controls 0.5, 0.4, 0.4 (rows 3-5).
    // All lie inside the common support [l(.4), l(.5)]. A tiny caliper admits
    // only exact ties: 0.5 -> row 3 (set 1); 0.45 misses (nearest 0.4 is
    // 0.2007 away); 0.4 -> first 0.4 control, row 4 (set 2); row 5 is left.
    var p = [_]f64{ 0.5, 0.45, 0.4, 0.5, 0.4, 0.4 };
    const treated = [_]bool{ true, true, true, false, false, false };
    const used = [_]bool{ true, true, true, true, true, true };
    var g: ps.Group = undefined;
    try ps.matchGreedy(a, &p, &treated, &used, 1e-9, .descending, &g);
    for (g.in_region) |b| try std.testing.expect(b);
    try std.testing.expectEqual(@as(usize, 1), g.caliper_unmatched);
    try std.testing.expect(!g.short_controls);
    try std.testing.expectEqual(@as(usize, 2), g.n_sets);
    try std.testing.expectEqual(@as(usize, 1), g.match_id[3]);
    try std.testing.expectEqual(@as(usize, 2), g.match_id[4]);
    try std.testing.expect(!g.matched[1] and !g.matched[5]);
    try std.testing.expectApproxEqAbs(@as(f64, 0), g.total_diff, 1e-15);
}
