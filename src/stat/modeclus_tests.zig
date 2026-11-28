//! STAT-MODECLUS-001 unit tests: density, METHOD=0/1 clustering and the
//! default radius against the SAS 15.4 reference values.
const std = @import("std");
const m = @import("modeclus.zig");

const example = [_]f64{ 18, 18, 20, 22, 21, 20, 12, 23, 17, 12, 23, 25, 25, 20, 16, 27, 20, 13, 28, 22, 80, 20, 75, 19, 77, 23, 81, 26, 55, 21, 64, 24, 72, 26, 70, 35, 75, 30, 78, 42, 18, 52, 27, 57, 41, 61, 48, 64, 59, 72, 69, 72, 80, 80, 31, 53, 51, 69, 72, 81 };

test "STAT-MODECLUS-001 uniform-kernel density matches n_i / (n pi r^2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w = [_]f64{1} ** 30;
    const f = try m.densities(a, &example, &w, 2, 10);
    // Observation 3 (21,20) has 10 points within radius 10: 10/(30*100*pi).
    try std.testing.expectApproxEqRel(10.0 / (30.0 * 100.0 * std.math.pi), f[2], 1e-12);
    // SAS 15.4 OUT= listing: obs 1 .000954930, obs 4 .000530516, obs 5 .000424413.
    try std.testing.expectApproxEqAbs(0.000954930, f[0], 5e-10);
    try std.testing.expectApproxEqAbs(0.000530516, f[3], 5e-10);
    try std.testing.expectApproxEqAbs(0.000424413, f[4], 5e-10);
}

test "STAT-MODECLUS-001 METHOD=1 cluster statistics for R=10 15 35" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w = [_]f64{1} ** 30;
    const expected = [_][]const f64{ &.{ 10, 9, 7, 2, 1, 1 }, &.{ 10, 10, 10 }, &.{30} };
    for ([_]f64{ 10, 15, 35 }, expected) |r, freqs| {
        const f = try m.densities(a, &example, &w, 2, r);
        const sol = try m.cluster(a, &example, &w, 2, f, r, 1);
        try std.testing.expectEqual(freqs.len, sol.stats.len);
        for (sol.stats, freqs) |st, q| {
            try std.testing.expectEqual(q, st.freq);
            try std.testing.expectEqual(@as(f64, 0), st.bfreq);
            try std.testing.expect(st.saddle == null);
        }
    }
}

test "STAT-MODECLUS-001 METHOD=0 is single linkage cut at the radius" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Hand example: points 0,1,3 on a line and 10; radius 1.5 links 0-1 only,
    // radius 2 links 0-1-3.
    const x = [_]f64{ 0, 1, 3, 10 };
    const w = [_]f64{ 1, 1, 1, 1 };
    const f = try m.densities(a, &x, &w, 1, 1.5);
    const s1 = try m.cluster(a, &x, &w, 1, f, 1.5, 0);
    try std.testing.expectEqual(@as(usize, 3), s1.stats.len);
    const s2 = try m.cluster(a, &x, &w, 1, f, 2, 0);
    try std.testing.expectEqual(@as(usize, 2), s2.stats.len);
    try std.testing.expectEqual(s2.cluster[0], s2.cluster[2]);
    // Density at 0 with r=1.5 in one dimension: 2/(4*3).
    try std.testing.expectApproxEqRel(2.0 / 12.0, f[0], 1e-12);
}

test "STAT-MODECLUS-001 default radius matches the SAS 15.4 reference" {
    const w = [_]f64{1} ** 30;
    // SAS 15.4 reference run without smoothing options: R=30.177636356.
    try std.testing.expectApproxEqAbs(30.177636356, m.defaultRadius(&example, &w, 2), 5e-9);
}
