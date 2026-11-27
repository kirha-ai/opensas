//! EDF formulas: SAS/STAT15.4 physical pp.7247-7249. Synthetic CDF jumps
//! are counted directly, independently of the sorted-tie production traversal.
const std = @import("std");
const k = @import("npar1way_stats.zig");
const t = std.testing;
const edf_only: k.Options = .{ .anova = false, .wilcoxon = false, .median = false, .vw = false, .savage = false, .edf = true };
test "NPAR005 EDF complete ties CDF deviations and one-sided probabilities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 1, 4, 2, 3, 3 };
    const g = [_]usize{ 0, 0, 0, 1, 1, 1 };
    const r = (try k.compute(a, &x, &g, 2, edf_only)).edf.?;
    const f0 = [_]f64{ 2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1 };
    const f1 = [_]f64{ 0, 1.0 / 3.0, 1, 1 };
    const tied = [_]f64{ 2, 1, 2, 1 };
    var max_deviation: f64 = 0;
    var cm: f64 = 0;
    for (f0, f1, tied) |p, q, count| {
        const pooled = (p + q) / 2;
        const deviation = 3 * ((p - pooled) * (p - pooled) + (q - pooled) * (q - pooled));
        max_deviation = @max(max_deviation, deviation);
        cm += count * deviation / 6;
    }
    try t.expectApproxEqAbs(@sqrt(max_deviation / 6), r.ks, 1e-15);
    try t.expectApproxEqAbs(cm, r.cma, 1e-15);
    try t.expectApproxEqAbs(cm / 6, r.cm, 1e-15);
    try t.expectApproxEqAbs(@as(f64, 2.0 / 3.0), r.d_plus.?, 1e-15);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 3.0), r.d_minus.?, 1e-15);
    try t.expectApproxEqAbs(@exp(-@as(f64, 4.0 / 3.0)), r.d_plus_p.?, 1e-15);
    try t.expectApproxEqAbs(@exp(-@as(f64, 1.0 / 3.0)), r.d_minus_p.?, 1e-15);
    try t.expectApproxEqAbs(@as(f64, 1), r.kuiper.?, 1e-15);
    try t.expectEqualSlices(f64, &.{ 2.0 / 3.0, 0 }, r.at_max);
    try t.expectEqual(@as(f64, 1.0 / 3.0), r.pooled_at_max);
    for (r.deviations, [_]f64{ 1 / @sqrt(@as(f64, 3)), -1 / @sqrt(@as(f64, 3)) }) |actual, want| try t.expectApproxEqAbs(want, actual, 1e-15);
    for (r.cm_components) |component| try t.expectApproxEqAbs(@as(f64, 11.0 / 72.0), component, 1e-15);
    try t.expectEqual(@as(usize, 0), r.max_index);
    try t.expectEqual(@as(f64, 1), r.max_value);
    const swapped = (try k.compute(a, &x, &.{ 1, 1, 1, 0, 0, 0 }, 2, edf_only)).edf.?;
    try t.expectEqual(r.d_plus, swapped.d_minus);
    try t.expectEqual(r.d_minus, swapped.d_plus);
    try t.expectEqual(r.ks_p, swapped.ks_p);
    try t.expectEqual(r.kuiper_p, swapped.kuiper_p);
}
test "NPAR005 EDF constant multisample and limiting tail boundaries" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = (try k.compute(a, &.{ 2, 2, 2, 2, 2, 2 }, &.{ 0, 0, 1, 1, 2, 2 }, 3, edf_only)).edf.?;
    try t.expectEqual(@as(f64, 0), r.ks);
    try t.expectEqual(@as(f64, 0), r.cma);
    try t.expect(r.ks_p == null and r.d_plus == null);
    try t.expectEqualSlices(f64, &.{ 1, 1, 1 }, r.at_max);
    const two = (try k.compute(a, &.{ 2, 2, 2, 2 }, &.{ 0, 0, 1, 1 }, 2, edf_only)).edf.?;
    try t.expectEqual(@as(?f64, 1), two.ks_p);
    try t.expectEqual(@as(?f64, 1), two.kuiper_p);
    const unequal = (try k.compute(a, &.{ 1, 2, 3, 4, 5 }, &.{ 0, 0, 1, 1, 1 }, 2, edf_only)).edf.?;
    try t.expectEqual(@as(?f64, 1), unequal.d_plus);
    try t.expectApproxEqAbs(@exp(-@as(f64, 12.0 / 5.0)), unequal.d_plus_p.?, 1e-15);
    try t.expectEqual(@as(?f64, 1), unequal.d_minus_p);
    var previous_k: f64 = 1;
    var previous_u: f64 = 1;
    for ([_]f64{ 0, 1e-8, 0.1, 0.5, 0.999999, 1, 1.000001, 2, 4, 10, 100 }) |z| {
        const ks = k.kolmogorovTail(z);
        const kuiper = k.kuiperTail(z);
        try t.expect(ks >= 0 and ks <= previous_k);
        try t.expect(kuiper >= 0 and kuiper <= previous_u);
        previous_k = ks;
        previous_u = kuiper;
    }
    // Kolmogorov's alternating exponential formula, independently tabulated
    // in high precision, bounds comparison by floating-point arithmetic error.
    try t.expectApproxEqAbs(@as(f64, 0.26999967167735456), k.kolmogorovTail(1), 2e-15);
    try t.expectApproxEqAbs(@as(f64, 0.9639452436648751), k.kolmogorovTail(0.5), 2e-15);
    try t.expectApproxEqAbs(@as(f64, 0.0006709252557796953), k.kolmogorovTail(2), 2e-18);
}

test "NPAR005 Kuiper limiting tail independent high precision constants" {
    // Limiting exponential sum in Paltani's author notes (Kuiper distribution):
    // https://www.isdc.unige.ch/~paltani/Courses/robust_paltani.pdf
    // Use the limiting argument Ka, as S154 specifies, with no finite-N
    // correction. Constants computed with80-digit decimal arithmetic,200terms
    // in 2 sum (4m²z²-1) exp(-2m²z²). Omitted tail at z>=.5 is <1e-8000;
    // tolerances cover f64 exp/summation rounding, not a statistical allowance.
    try t.expectApproxEqAbs(@as(f64, 0.99999947051921186556), k.kuiperTail(0.5), 2e-15);
    try t.expectApproxEqAbs(@as(f64, 0.82207664435692932131), k.kuiperTail(1), 2e-15);
    try t.expectApproxEqAbs(@as(f64, 0.010063878838671040024), k.kuiperTail(2), 2e-17);
}
