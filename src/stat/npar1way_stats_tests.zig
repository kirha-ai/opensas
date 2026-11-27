//! Public Halverson/Sherwood Gossypol data from SAS/STAT 15.4 physical
//! pp.7206-7214. Every default numerical summary is checked at the source's
//! displayed precision; small synthetic cases independently prove definitions.
//! No reference file is read at runtime, and no golden derives from OpenSAS.
const std = @import("std");
const t = std.testing;
const k = @import("npar1way_stats.zig");
pub const gains = [_]f64{
    228, 229, 218, 216, 224, 208, 235, 229, 233, 219, 224, 220, 232, 200, 208, 232,
    186, 229, 220, 208, 228, 198, 222, 273, 216, 198, 213, 179, 193, 183, 180, 143,
    204, 114, 188, 178, 134, 208, 196, 130, 87,  135, 116, 118, 165, 151, 59,  126,
    64,  78,  94,  150, 160, 122, 110, 178, 154, 130, 130, 118, 118, 104, 112, 134,
    98,  100, 104,
};
pub fn groups() [67]usize {
    var result: [67]usize = undefined;
    var i: usize = 0;
    for ([_]usize{ 16, 11, 12, 17, 11 }, 0..) |count, g| {
        @memset(result[i..][0..count], g);
        i += count;
    }
    return result;
}
fn six(want: f64, got: f64) !void {
    try t.expectApproxEqAbs(want, got, 0.0000005);
}
fn four(want: f64, got: f64) !void {
    try t.expectApproxEqAbs(want, got, 0.00005);
}

test "NPAR002 complete Gossypol multisample default numerical contract" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const g = groups();
    const r = try k.compute(arena.allocator(), &gains, &g, 5, .{});
    try t.expectEqual(@as(usize, 67), r.n);
    try t.expectEqualSlices(usize, &.{ 16, 11, 12, 17, 11 }, r.counts);
    try t.expect(r.has_ties);
    for ([_]f64{ 222.187500, 217.363636, 175.000000, 120.176471, 118.363636 }, r.means) |want, got| try six(want, got);
    const an = r.anova.?;
    try t.expectEqual(@as(usize, 4), an.among_df);
    try t.expectEqual(@as(usize, 62), an.within_df);
    try six(140082.986077, an.among_ss);
    try six(38901.998997, an.within_ss);
    try t.expectApproxEqAbs(@as(f64, 35020.74652), an.among_ms, 0.000005);
    try t.expectApproxEqAbs(@as(f64, 627.45160), an.within_ms, 0.000005);
    try four(55.8143, an.f.?);
    try t.expect(an.p.? < 0.0001);
    const sums = [4][5]f64{ .{ 890.5, 555, 395.5, 275.5, 161.5 }, .{ 16, 11, 6, 0, 0 }, .{ 16.116474, 8.340899, -0.576674, -14.688921, -9.191777 }, .{ 16.074391, 7.693099, -3.584958, -11.979488, -8.203044 } };
    const expecteds = [4][5]f64{ .{ 544, 374, 408, 578, 374 }, .{ 7.880597, 5.417910, 5.910448, 8.373134, 5.417910 }, .{ 0, 0, 0, 0, 0 }, .{ 0, 0, 0, 0, 0 } };
    const deviations = [4][5]f64{ .{ 67.978966, 59.063588, 61.136622, 69.380741, 59.063588 }, .{ 1.757902, 1.527355, 1.580963, 1.794152, 1.527355 }, .{ 3.325957, 2.889761, 2.991186, 3.394540, 2.889761 }, .{ 3.385275, 2.941300, 3.044534, 3.455082, 2.941300 } };
    const means = [4][5]f64{ .{ 55.656250, 50.454545, 32.958333, 16.205882, 14.681818 }, .{ 1, 1, 0.5, 0, 0 }, .{ 1.007280, 0.758264, -0.048056, -0.864054, -0.835616 }, .{ 1.004649, 0.699373, -0.298746, -0.704676, -0.745731 } };
    try t.expectEqual(@as(usize, 4), r.scores.len);
    for (r.scores, 0..) |s, i| {
        try t.expectEqual(@as(k.Kind, @enumFromInt(i)), s.kind);
        try t.expectEqual(@as(usize, 4), s.df);
        try t.expect(s.two_sample == null);
        for (s.groups, 0..) |summary, j| {
            try six(sums[i][j], summary.sum);
            try six(expecteds[i][j], summary.expected);
            try six(deviations[i][j], summary.stddev);
            try six(means[i][j], summary.mean);
        }
        try four(([_]f64{ 52.6656, 54.1765, 47.2972, 39.4908 })[i], s.chi_square.?);
        try t.expect(s.p.? < 0.0001);
        // df=4 chi-square survival has an independent elementary formula.
        const half = s.chi_square.? / 2;
        try t.expectApproxEqAbs(@exp(-half) * (1 + half), s.p.?, 1e-14);
    }
    const e = r.edf.?;
    try t.expectEqual(@as(usize, 35), e.max_index);
    try t.expectEqual(@as(f64, 178), e.max_value);
    for ([_]f64{ 0, 0, 1.0 / 3.0, 1, 1 }, e.at_max) |want, got| try t.expectApproxEqAbs(want, got, 1e-14);
    for ([_]f64{ -1.910448, -1.584060, -0.499796, 2.153861, 1.732565 }, e.deviations) |want, got| try six(want, got);
    for ([_]f64{ 2.165210, 0.918280, 0.348227, 1.497542, 1.335745 }, e.cm_components) |want, got| try six(want, got);
    try six(0.477612, e.pooled_at_max);
    try six(0.457928, e.ks);
    try six(3.748300, e.ksa);
    try six(0.093508, e.cm);
    try six(6.265003, e.cma);
    try t.expect(e.d == null and e.ks_p == null and e.kuiper == null and e.kuiper_p == null);
}

test "NPAR002 complete Gossypol two-sample default numerical contract" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const g = groups();
    const r = try k.compute(arena.allocator(), gains[0..27], g[0..27], 2, .{});
    try t.expectEqual(@as(usize, 27), r.n);
    try t.expectEqualSlices(usize, &.{ 16, 11 }, r.counts);
    const an = r.anova.?;
    try six(151.683712, an.among_ss);
    try six(6786.982955, an.within_ss);
    try six(151.683712, an.among_ms);
    try six(271.479318, an.within_ms);
    try t.expectEqual(@as(usize, 1), an.among_df);
    try t.expectEqual(@as(usize, 25), an.within_df);
    try four(0.5587, an.f.?);
    try four(0.4617, an.p.?);
    const sums = [4][2]f64{ .{ 253.5, 124.5 }, .{ 9, 4 }, .{ 3.346520, -3.346520 }, .{ 1.834554, -1.834554 } };
    const expectations = [4][2]f64{ .{ 224, 154 }, .{ 7.703704, 5.296296 }, .{ 0, 0 }, .{ 0, 0 } };
    const means = [4][2]f64{ .{ 15.843750, 11.318182 }, .{ 0.562500, 0.363636 }, .{ 0.209157, -0.304229 }, .{ 0.114660, -0.166778 } };
    const sd = [_]f64{ 20.221565, 1.299995, 2.320336, 2.401839 };
    for (r.scores, 0..) |s, i| {
        for (s.groups, 0..) |v, j| {
            try six(sums[i][j], v.sum);
            try six(expectations[i][j], v.expected);
            try six(sd[i], v.stddev);
            try six(means[i][j], v.mean);
        }
        try four(([_]f64{ 2.1282, 0.9943, 2.0801, 0.5834 })[i], s.chi_square.?);
        try four(([_]f64{ 0.1446, 0.3187, 0.1492, 0.4450 })[i], s.p.?);
        const two = s.two_sample.?;
        try t.expectEqual(@as(usize, 1), two.selected);
        try six(sums[i][1], two.statistic);
        try four(([_]f64{ -1.4341, -0.9972, -1.4423, -0.7638 })[i], two.z.?);
        try four(([_]f64{ 0.0758, 0.1593, 0.0746, 0.2225 })[i], two.p_one.?);
        try four(([_]f64{ 0.1515, 0.3187, 0.1492, 0.4450 })[i], two.p_two.?);
        try t.expect(two.exact == null);
        if (i == 0) {
            try four(0.0817, two.p_t_one.?);
            try four(0.1635, two.p_t_two.?);
        } else try t.expect(two.p_t_one == null and two.p_t_two == null);
    }
    const e = r.edf.?;
    try t.expectEqual(@as(usize, 3), e.max_index);
    try t.expectEqual(@as(f64, 216), e.max_value);
    try six(0.25, e.at_max[0]);
    try six(0.545455, e.at_max[1]);
    try six(0.370370, e.pooled_at_max);
    try six(-0.481481, e.deviations[0]);
    try six(0.580689, e.deviations[1]);
    try six(0.145172, e.ks);
    try six(0.754337, e.ksa);
    try six(0.295455, e.d.?);
    try four(0.6199, e.ks_p.?);
    try six(0.098638, e.cm_components[0]);
    try six(0.143474, e.cm_components[1]);
    try six(0.008967, e.cm);
    try six(0.242112, e.cma);
    try six(0.090909, e.kuiper_deviations[0]);
    try six(0.295455, e.kuiper_deviations[1]);
    try six(0.386364, e.kuiper.?);
    try six(0.986440, e.kuiper_scaled.?);
    try four(0.8383, e.kuiper_p.?);
}

test "NPAR002 independent tied rank ANOVA exact allocation and EDF identities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const r = try k.compute(arena.allocator(), &.{ 1, 2, 2, 3, 4, 4 }, &.{ 0, 0, 0, 1, 1, 1 }, 2, .{ .exact_wilcoxon = true });
    const w = r.scores[0];
    try t.expectEqualSlices(f64, &.{ 1, 2.5, 2.5, 4, 5.5, 5.5 }, w.values);
    try t.expectApproxEqAbs(@as(f64, 45.0 / 11.0), w.chi_square.?, 1e-13);
    try t.expectApproxEqAbs(-4 / @sqrt(@as(f64, 4.95)), w.two_sample.?.z.?, 1e-13);
    try t.expectEqual(@as(usize, 0), w.two_sample.?.selected);
    const ex = w.two_sample.?.exact.?;
    try t.expectEqual(@as(u64, 20), ex.allocations);
    try t.expectEqual(@as(u64, 1), ex.lower_count);
    try t.expectEqual(@as(u64, 2), ex.two_sided_count);
    const e = r.edf.?;
    try t.expectApproxEqAbs(@as(f64, 0.5), e.ks, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 1), e.d.?, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 1.5), e.ksa * e.ksa, 1e-13);
    // At pooled values 1,2,3,4 the (F1-F2)^2 values are 1/9,1,4/9,0;
    // their multiplicities are 1,2,1,2, and n1*n2/n^2=1/4.
    try t.expectApproxEqAbs(@as(f64, 23.0 / 36.0), e.cma, 1e-13);
    const constant = try k.compute(arena.allocator(), &.{ 7, 7, 7, 7 }, &.{ 0, 0, 1, 1 }, 2, .{ .exact_wilcoxon = true });
    for (constant.scores) |s| {
        try t.expect(s.chi_square == null);
        try t.expect(s.two_sample.?.z == null);
    }
    try t.expectEqual(@as(f64, 1), constant.scores[0].two_sample.?.exact.?.two_sided);
    try t.expectEqual(@as(f64, 1), constant.edf.?.ks_p.?);
    try t.expectEqual(@as(f64, 1), constant.edf.?.kuiper_p.?);
    try t.expectError(error.InvalidInput, k.compute(arena.allocator(), &.{ 1, 2 }, &.{ 0, 0 }, 1, .{}));
    try t.expectError(error.InvalidInput, k.compute(arena.allocator(), &.{ 1, std.math.nan(f64), 3 }, &.{ 0, 0, 1 }, 2, .{}));
}

test "NPAR002 transform ordinal scores before averaging ties and explicit selection" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const r = try k.compute(arena.allocator(), &.{ 0, 1, 1, 2 }, &.{ 0, 0, 1, 1 }, 2, .{});
    try t.expectEqualSlices(f64, &.{ 0, 0.5, 0.5, 1 }, r.scores[1].values);
    // Standard-normal fifth quantiles, independently tabulated; the tied
    // .4/.6 quantiles cancel by symmetry. This detects transforming midranks.
    for ([_]f64{ -0.8416212335729143, 0, 0, 0.8416212335729143 }, r.scores[2].values) |want, got|
        try t.expectApproxEqAbs(want, got, 2e-14);
    for ([_]f64{ -0.75, -1.0 / 6.0, -1.0 / 6.0, 13.0 / 12.0 }, r.scores[3].values) |want, got|
        try t.expectApproxEqAbs(want, got, 2e-14);
    const singleton = try k.compute(arena.allocator(), &.{ 3, 9 }, &.{ 0, 1 }, 2, .{ .anova = false, .wilcoxon = false, .median = false, .vw = false, .savage = false, .edf = false, .exact_wilcoxon = true });
    try t.expect(singleton.anova == null and singleton.edf == null);
    try t.expectEqual(@as(usize, 1), singleton.scores.len);
    try t.expectEqual(k.Kind.wilcoxon, singleton.scores[0].kind);
    try t.expectEqual(@as(u64, 2), singleton.scores[0].two_sample.?.exact.?.allocations);
    try t.expectError(error.ExactLimit, k.compute(arena.allocator(), &.{ 1, 2, 3 }, &.{ 0, 1, 2 }, 3, .{ .exact_wilcoxon = true }));
}

test "NPAR002 original WilcoxonBoxPlot five quartiles every rank coordinate and ODS identity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = groups();
    const r = try k.compute(a, &gains, &g, 5, .{});
    const plots = @import("npar1way_plots.zig");
    const boxes = try plots.summarize(a, r.scores[0].values, &g, 5);
    // Independently count every smaller/equal raw value for each rank, then
    // sort by class and use empirical definition5 quartiles. Figure90.7 shows
    // exactly one outlier (rank12, Dose.07), and these five box summaries.
    const expected = [_][5]f64{ .{ 50.25, 56.5, 62.25, 42, 66 }, .{ 40.5, 49.5, 58.5, 36, 67 }, .{ 28.25, 34.5, 38.5, 22.5, 45.5 }, .{ 5, 17, 26, 1, 31.5 }, .{ 8.5, 15, 20, 6, 28 } };
    for (boxes, expected, 0..) |b, e, i| {
        try t.expectEqualSlices(f64, &e, &.{ b.q1, b.median, b.q3, b.lower, b.upper });
        try t.expectEqual(r.counts[i], b.n);
        try t.expectApproxEqAbs(r.scores[0].groups[i].mean, b.mean, 1e-14);
        try t.expectEqual(@as(usize, if (i == 2) 1 else 0), b.outliers.len);
    }
    try t.expectEqual(@as(f64, 12), boxes[2].outliers[0]);
    const bytes = try plots.render(a, r.scores[0].values, &g, &.{ "0", "0.04", "0.07", "0.1", "0.13" }, "Gain", "Dose", r.scores[0].p, "");
    try t.expect(std.mem.indexOf(u8, bytes, "data-kind=\"wilcoxonboxplot\"") != null);
    try t.expect(std.mem.indexOf(u8, bytes, ">Score</text>") != null);
    try t.expect(std.mem.indexOf(u8, bytes, ">Dose</text>") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "Pr &gt; ChiSq &lt;.0001") != null);
    try t.expectEqual(@as(usize, 67), std.mem.count(u8, bytes, "class=\"score-data\""));
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, bytes, "class=\"score-box\""));
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "class=\"outlier\""));
    for (gains, g, 0..) |gain, group, i| {
        var less: usize = 0;
        var equal: usize = 0;
        for (gains) |v| {
            if (v < gain) less += 1;
            if (v == gain) equal += 1;
        }
        const rank = @as(f64, @floatFromInt(less)) + @as(f64, @floatFromInt(equal + 1)) / 2;
        const xx = 90 + 570 * (@as(f64, @floatFromInt(group)) + 0.5) / 5;
        const yy = 390 - 320 * rank / 70;
        const exact = try std.fmt.allocPrint(a, "data-index=\"{d}\" data-group=\"{d}\" data-score=\"{d}\" cx=\"{d}\" cy=\"{d}\"", .{ i, group, rank, xx, yy });
        try t.expect(std.mem.indexOf(u8, bytes, exact) != null);
    }
    const object = try plots.object(a, null, "Gain");
    try t.expectEqual(@import("graph_ods.zig").Name.WilcoxonBoxPlot, object.name);
    // NPAR010 original SAS TRACE verifies the analysis section in this path.
    try t.expectEqualStrings("Npar1way.Gain.Wilcoxon.WilcoxonBoxPlot", object.path);
    const by = try plots.object(a, 2, "Gain");
    try t.expectEqualStrings("Npar1way.ByGroup2.Gain.Wilcoxon.WilcoxonBoxPlot", by.path);
    const no_stats = try plots.render(a, &.{ 1, 2 }, &.{ 0, 1 }, &.{ "A&B", "<B>" }, "R&x", "Group", null, "site=1");
    try t.expect(std.mem.indexOf(u8, no_stats, "Pr &gt;") == null);
    try t.expect(std.mem.indexOf(u8, no_stats, "A&amp;B") != null);
    try t.expect(std.mem.indexOf(u8, no_stats, "&lt;B&gt;") != null);
}
