//! Dwass-Steel-Critchlow-Fligner pairwise rank comparisons.
//! SAS/STAT15.4 physical p7247: re-rank each pair, no continuity correction,
//! DSCF=sqrt(2)*abs(Z), two-sided tail of the range of r independent normals.
//! Signed Z follows the listed first class. SAS's published Figure21 confirms
//! both conventions (Bream vsRoach positiveZ; Roach vsPike negativeZ/positiveDSCF):
//! https://www.sas.com/content/dam/SAS/support/en/books/biostatistics-by-example-using-sas-studio/69328_excerpt.pdf
//! Class counts35/20/17 are documented in SASHELP Fish (sashelpug.pdf).
const std = @import("std");
const ranks = @import("ranks.zig");
const range = @import("normal_range.zig");
const A = std.mem.Allocator;
pub const Status = enum { ok, empty_group, zero_variance };
pub const Pair = struct { first: usize, second: usize, n_first: usize, n_second: usize, selected: usize, status: Status, sum: ?f64 = null, expected: ?f64 = null, variance: ?f64 = null, z: ?f64 = null, dscf: ?f64 = null, p: ?f64 = null, numerical_error: ?f64 = null };
pub const Result = struct { family_size: usize, pairs: []Pair };
pub fn compute(a: A, values: []const f64, groups: []const usize, group_count: usize) !Result {
    if (values.len != groups.len or group_count < 3) return error.InvalidInput;
    if (group_count > 64 or values.len > 100_000 or values.len > 1_000_000 / group_count) return error.ResourceLimit;
    const counts = try a.alloc(usize, group_count);
    @memset(counts, 0);
    for (values, groups) |v, g| {
        if (!std.math.isFinite(v) or g >= group_count) return error.InvalidInput;
        counts[g] += 1;
    }
    var active: usize = 0;
    for (counts) |n| if (n > 0) {
        active += 1;
    };
    if (active < 3) return error.InvalidInput;
    const pairs = try a.alloc(Pair, group_count * (group_count - 1) / 2);
    var at: usize = 0;
    for (0..group_count) |i| for (i + 1..group_count) |j| {
        const selected = i;
        var pair: Pair = .{ .first = i, .second = j, .n_first = counts[i], .n_second = counts[j], .selected = selected, .status = .empty_group };
        if (counts[i] > 0 and counts[j] > 0) {
            const n = counts[i] + counts[j];
            const x = try a.alloc(f64, n);
            const picks = try a.alloc(bool, n);
            var row: usize = 0;
            for (values, groups) |v, g| if (g == i or g == j) {
                x[row] = v;
                picks[row] = g == selected;
                row += 1;
            };
            const r = try ranks.rank(a, x, false, .mean);
            const linear = try ranks.linearRank(r.values, picks, false);
            pair.sum = linear.sum;
            pair.expected = linear.expected;
            pair.variance = linear.variance;
            pair.z = linear.z;
            if (linear.z) |z| {
                const q = @sqrt(@as(f64, 2)) * z;
                const p = try range.survival(@abs(q), active);
                pair.dscf = @abs(q);
                pair.p = p.value;
                pair.numerical_error = p.estimated_error;
                pair.status = .ok;
            } else pair.status = .zero_variance;
        }
        pairs[at] = pair;
        at += 1;
    };
    return .{ .family_size = active, .pairs = pairs };
}

test "NPAR007 pairwise reranking tied variance and no continuity correction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Pair A/B pools[1,1,3,2,4]: ranks[1.5,1.5,4,3,5].
    // Listed A uses S=7,E=9 despite B being smaller. Var=(3*2)/(5*4)*9.5=2.85.
    const values = [_]f64{ 1, 1, 3, 2, 4, 50, 60 };
    const groups = [_]usize{ 0, 0, 0, 1, 1, 2, 2 };
    const r = try compute(a, &values, &groups, 3);
    try std.testing.expectEqual(@as(usize, 3), r.pairs.len);
    const pair = r.pairs[0];
    try std.testing.expectEqual(@as(usize, 0), pair.selected);
    try std.testing.expectEqual(@as(?f64, 7), pair.sum);
    try std.testing.expectEqual(@as(?f64, 9), pair.expected);
    try std.testing.expectApproxEqAbs(@as(f64, 2.85), pair.variance.?, 1e-14);
    try std.testing.expectApproxEqAbs(-2 / @sqrt(@as(f64, 2.85)), pair.z.?, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2)) * @abs(pair.z.?), pair.dscf.?, 1e-14);
    // Moving unrelated C values cannot affect pair A/B's ranks or statistic.
    const changed = try compute(a, &.{ 1, 1, 3, 2, 4, -100, -90 }, &groups, 3);
    try std.testing.expectEqual(pair.z, changed.pairs[0].z);
    try std.testing.expectEqual(pair.p, changed.pairs[0].p);
    // Adding a fourth family changes the adjustment, not the pair statistic.
    const larger = try compute(a, &.{ 1, 1, 3, 2, 4, 50, 60, 80 }, &.{ 0, 0, 0, 1, 1, 2, 2, 3 }, 4);
    try std.testing.expectEqual(pair.z, larger.pairs[0].z);
    try std.testing.expect(larger.pairs[0].p.? > pair.p.?);
}
test "NPAR007 direction empty comparisons and constant ranks stay typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 2, 4, 5, 7, 8 };
    const g = [_]usize{ 0, 0, 1, 1, 2, 2 };
    const r = try compute(a, &x, &g, 4);
    try std.testing.expectEqual(@as(usize, 3), r.family_size);
    try std.testing.expectEqual(@as(usize, 6), r.pairs.len);
    const reversed = try compute(a, &x, &.{ 1, 1, 0, 0, 2, 2 }, 3);
    try std.testing.expectEqual(-r.pairs[0].z.?, reversed.pairs[0].z.?);
    try std.testing.expectEqual(r.pairs[0].p, reversed.pairs[0].p);
    try std.testing.expectEqual(Status.empty_group, r.pairs[2].status);
    try std.testing.expect(r.pairs[2].p == null);
    const constant = try compute(a, &.{ 1, 1, 1, 1, 2, 3 }, &g, 3);
    try std.testing.expectEqual(Status.zero_variance, constant.pairs[0].status);
    try std.testing.expect(constant.pairs[0].z == null and constant.pairs[0].p == null);
    try std.testing.expectError(error.InvalidInput, compute(a, &.{ 1, 2, 3 }, &.{ 0, 1, 1 }, 3));
}

test {
    _ = range;
}
