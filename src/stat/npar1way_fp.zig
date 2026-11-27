//! Fligner-Policello placements and normal approximation.
//! SAS/STAT15.4 physical pp.7244-7246 define cross-sample placements (half
//! credit for ties), Vx/Vy and z=(sumPy-sumPx)/(2 sqrt(Vx+Vy+meanPx*meanPy)).
const std = @import("std");
const math = @import("../functions.zig");
const A = std.mem.Allocator;
pub const Summary = struct { n: usize, sum: f64, mean: f64, stddev: ?f64, centered_ss: f64 };
pub const Result = struct { placements: []f64, groups: [2]Summary, reference: usize, difference: f64, scale: f64, z: ?f64, p_one: ?f64, p_two: ?f64 };
fn number(n: usize) f64 {
    return @floatFromInt(n);
}
fn lower(sorted: []const f64, value: f64) usize {
    var lo: usize = 0;
    var hi = sorted.len;
    while (lo < hi) {
        const m = lo + (hi - lo) / 2;
        if (sorted[m] < value) lo = m + 1 else hi = m;
    }
    return lo;
}
fn upper(sorted: []const f64, value: f64) usize {
    var lo: usize = 0;
    var hi = sorted.len;
    while (lo < hi) {
        const m = lo + (hi - lo) / 2;
        if (sorted[m] <= value) lo = m + 1 else hi = m;
    }
    return lo;
}
pub fn compute(a: A, values: []const f64, groups: []const usize, reference: ?usize) !Result {
    if (values.len != groups.len or (reference != null and reference.? > 1)) return error.InvalidInput;
    var samples = [_]std.ArrayList(f64){ .empty, .empty };
    for (values, groups) |v, g| {
        if (g > 1 or !std.math.isFinite(v)) return error.InvalidInput;
        try samples[g].append(a, v);
    }
    for (&samples) |*sample| {
        if (sample.items.len == 0) return error.InvalidInput;
        std.mem.sort(f64, sample.items, {}, std.sort.asc(f64));
    }
    const ref = reference orelse (if (samples[0].items.len > samples[1].items.len) @as(usize, 0) else 1);
    const placements = try a.alloc(f64, values.len);
    var summaries = [_]Summary{ .{ .n = samples[0].items.len, .sum = 0, .mean = 0, .stddev = null, .centered_ss = 0 }, .{ .n = samples[1].items.len, .sum = 0, .mean = 0, .stddev = null, .centered_ss = 0 } };
    for (values, groups, placements) |v, g, *p| {
        const other = samples[1 - g].items;
        const lo = lower(other, v);
        const hi = upper(other, v);
        p.* = number(lo) + number(hi - lo) / 2;
        summaries[g].sum += p.*;
    }
    for (&summaries) |*g| g.mean = g.sum / number(g.n);
    for (placements, groups) |p, g| summaries[g].centered_ss += (p - summaries[g].mean) * (p - summaries[g].mean);
    for (&summaries) |*g| if (g.n > 1) {
        g.stddev = @sqrt(g.centered_ss / number(g.n - 1));
    };
    const difference = summaries[1 - ref].sum - summaries[ref].sum;
    const scale = 2 * @sqrt(summaries[0].centered_ss + summaries[1].centered_ss + summaries[0].mean * summaries[1].mean);
    const z = if (scale > 0) difference / scale else null;
    const p = if (z) |zz| math.distCdf(.normal, -@abs(zz), &.{}).? else null;
    return .{ .placements = placements, .groups = summaries, .reference = ref, .difference = difference, .scale = scale, .z = z, .p_one = p, .p_two = if (p) |pp| 2 * pp else null };
}

test "NPAR005 FP complete placement and variance contract independently from pair indicators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [_]f64{ 1, 2, 3, 2, 4, 5 };
    const groups = [_]usize{ 0, 0, 0, 1, 1, 1 };
    const r = try compute(a, &values, &groups, 0);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0.5, 1, 1.5, 3, 3 }, r.placements);
    try std.testing.expectEqual(@as(usize, 3), r.groups[0].n);
    try std.testing.expectEqual(@as(usize, 3), r.groups[1].n);
    try std.testing.expectEqual(@as(f64, 0.5), r.groups[0].mean);
    try std.testing.expectEqual(@as(f64, 2.5), r.groups[1].mean);
    try std.testing.expectEqual(@as(f64, 1.5), r.groups[0].sum);
    try std.testing.expectEqual(@as(f64, 7.5), r.groups[1].sum);
    try std.testing.expectEqual(@as(f64, 0.5), r.groups[0].centered_ss);
    try std.testing.expectEqual(@as(f64, 1.5), r.groups[1].centered_ss);
    try std.testing.expectEqual(@as(?f64, 0.5), r.groups[0].stddev);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.75)), r.groups[1].stddev.?, 1e-15);
    try std.testing.expectEqual(@as(f64, 6), r.difference);
    try std.testing.expectApproxEqAbs(@as(f64, 6) / @sqrt(@as(f64, 13)), r.z.?, 1e-15);
    // Independent normal tail via a composite Simpson integral of exp(-t²/2),
    // step<=0.0002: fourth derivative bound gives integral error below1e-13.
    const n = 10000;
    const end = @abs(r.z.?);
    const h = end / n;
    var integral: f64 = 0;
    for (0..n + 1) |i| {
        const x = h * number(i);
        integral += (if (i == 0 or i == n) @as(f64, 1) else if (i % 2 == 1) @as(f64, 4) else @as(f64, 2)) * @exp(-x * x / 2);
    }
    const tail = 0.5 - integral * h / (3 * @sqrt(2 * std.math.pi));
    try std.testing.expectApproxEqAbs(tail, r.p_one.?, 2e-13);
    try std.testing.expectApproxEqAbs(2 * tail, r.p_two.?, 4e-13);
    const reverse = try compute(a, &values, &groups, 1);
    try std.testing.expectEqual(-r.z.?, reverse.z.?);
    try std.testing.expectEqual(r.p_two, reverse.p_two);
    const default = try compute(a, &values, &groups, null);
    try std.testing.expectEqual(@as(usize, 1), default.reference);
}
test "NPAR005 FP ties reverse ordering unequal classes and zero scale" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = [_]f64{ 4, 1, 2, 2, 3, 1, 8 };
    const groups = [_]usize{ 0, 0, 0, 0, 1, 1, 1 };
    const r = try compute(a, &values, &groups, null);
    try std.testing.expectEqual(@as(usize, 0), r.reference);
    for (values, groups, 0..) |v, g, i| {
        var placement: f64 = 0;
        for (values, groups) |other, og| if (og != g) {
            placement += if (other < v) @as(f64, 1) else if (other == v) @as(f64, 0.5) else 0;
        };
        try std.testing.expectEqual(placement, r.placements[i]);
    }
    try std.testing.expectEqual(@as(f64, 12), r.groups[0].sum + r.groups[1].sum);
    const constant = try compute(a, &.{ 2, 2, 2, 2 }, &.{ 0, 0, 1, 1 }, null);
    try std.testing.expectEqual(@as(?f64, 0), constant.z);
    try std.testing.expectEqual(@as(?f64, 1), constant.p_two);
    const separated = try compute(a, &.{ 1, 1, 5, 5 }, &.{ 0, 0, 1, 1 }, null);
    try std.testing.expectEqual(@as(f64, 0), separated.scale);
    try std.testing.expect(separated.z == null and separated.p_two == null);
    const singleton = try compute(a, &.{ 2, 1, 3 }, &.{ 0, 1, 1 }, null);
    try std.testing.expect(singleton.groups[0].stddev == null);
    try std.testing.expectError(error.InvalidInput, compute(a, &.{1}, &.{0}, null));
}

test "NPAR005 FP graph retains every placement box summary and plotted coordinate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try compute(a, &.{ 1, 2, 3, 2, 4, 5 }, &.{ 0, 0, 0, 1, 1, 1 }, 0);
    const plots = @import("npar1way_plots.zig");
    const boxes = try plots.summarize(a, result.placements, &.{ 0, 0, 0, 1, 1, 1 }, 2);
    try std.testing.expectEqual(@as(f64, 0), boxes[0].q1);
    try std.testing.expectEqual(@as(f64, 0.5), boxes[0].median);
    try std.testing.expectEqual(@as(f64, 1), boxes[0].q3);
    try std.testing.expectEqual(@as(f64, 1.5), boxes[1].q1);
    try std.testing.expectEqual(@as(f64, 3), boxes[1].median);
    try std.testing.expectEqual(@as(f64, 3), boxes[1].q3);
    const bytes = try plots.renderNamed(a, result.placements, &.{ 0, 0, 0, 1, 1, 1 }, &.{ "A", "B" }, "x", "g", result.p_two, "", "fpboxplot", "Distribution of Fligner-Policello Placements", "Placement", "Pr > |Z|");
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, bytes, "class=\"score-data\""));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "class=\"score-box\""));
    for (result.placements, 0..) |placement, i| {
        const group: usize = if (i < 3) 0 else 1;
        const needle = try std.fmt.allocPrint(a, "data-index=\"{d}\" data-group=\"{d}\" data-score=\"{d}\" cx=\"{d}\" cy=\"{d}\"", .{ i, group, placement, 90 + 570 * (@as(f64, @floatFromInt(group)) + 0.5) / 2, 390 - 320 * placement / 3 });
        try std.testing.expect(std.mem.indexOf(u8, bytes, needle) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Pr &gt; |Z|") != null);
}
