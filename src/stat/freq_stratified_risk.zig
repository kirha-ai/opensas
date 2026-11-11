//! Common risk difference and logit adapters, SAS/STAT FREQ pp.195–199,223–225.
//! No public parser/renderer dependencies. Preserve the caller's stratum slots.
const std = @import("std");
const math = @import("../functions.zig");
const risk = @import("freq_risk.zig");
const strat = @import("freq_stratified.zig");
pub const Error = risk.Error;
pub const Table = risk.Table2x2;
pub const Method = enum { mantel_haenszel, klingenberg, minimum_risk, summary_score, newcombe, newcombe_mr };
pub const Options = struct { column: risk.Column = .first, alpha: f64 = 0.05, correct: bool = true, sample_variance: bool = false };
pub const Result = struct {
    value: f64,
    variance: ?f64,
    limits: risk.Interval,
    z: ?f64,
    p_two: ?f64,
    weights: []f64,
    /// Summary-score interval midpoints; otherwise stratum risk differences.
    components: []f64,
    used: usize,
    pub fn deinit(self: Result, a: std.mem.Allocator) void {
        a.free(self.weights);
        a.free(self.components);
    }
};
fn sq(x: f64) f64 {
    return x * x;
}
fn active(t: Table) Error!bool {
    for (t.cells) |x| if (!std.math.isFinite(x) or x < 0) return error.ExecError;
    const samples = t.samples(.first);
    if (samples[0].total == 0 or samples[1].total == 0) return false;
    try t.validate();
    return true;
}
/// One result per requested method, independently nullable for degeneracy.
/// Caller renders the returned normalized weights for PRINTWTS; no recomputation.
pub fn commonDifference(a: std.mem.Allocator, tables: []const Table, method: Method, opts: Options) Error!?Result {
    if (!(opts.alpha > 0 and opts.alpha < 1)) return error.ExecError;
    const zcrit = -math.distQuantile(.normal, opts.alpha / 2, &.{}).?;
    const weights = try a.alloc(f64, tables.len);
    @memset(weights, 0);
    const differences = a.alloc(f64, tables.len) catch |err| {
        a.free(weights);
        return err;
    };
    @memset(differences, 0);
    var transferred = false;
    defer if (!transferred) {
        a.free(weights);
        a.free(differences);
    };
    const variances = try a.alloc(f64, tables.len);
    defer a.free(variances);
    @memset(variances, 0);
    const null_variances = try a.alloc(f64, tables.len);
    defer a.free(null_variances);
    @memset(null_variances, 0);
    var used: usize = 0;
    var total: f64 = 0;
    var wsum: f64 = 0;
    var psum: f64 = 0;
    var qsum: f64 = 0;
    for (tables, 0..) |t, i| {
        if (!try active(t)) continue;
        used += 1;
        const s = t.samples(opts.column);
        const n1 = s[0].total;
        const n2 = s[1].total;
        const n = n1 + n2;
        const x = s[0].success;
        const y = s[1].success;
        const d = try risk.difference(t, opts.column, opts.alpha, false);
        differences[i] = d.estimate.?;
        variances[i] = sq(d.se.?);
        if (method == .minimum_risk or method == .newcombe_mr) {
            // SAS common_edges.sas: MR variance substitutes .5/n at a
            // boundary proportion, without changing the observed difference.
            variances[i] = 0;
            for (s) |sample| {
                const p = if (sample.success == 0) 0.5 / sample.total else if (sample.success == sample.total) 1 - 0.5 / sample.total else sample.proportion();
                variances[i] += p * (1 - p) / sample.total;
            }
        }
        const pooled = (x + y) / n;
        null_variances[i] = pooled * (1 - pooled) * (1 / n1 + 1 / n2);
        weights[i] = n1 * n2 / n;
        wsum += weights[i];
        total += n;
        psum += (n1 * n1 * y - n2 * n2 * x + n1 * n2 * (n2 - n1) / 2) / (n * n);
        qsum += (x * (n2 - y) + y * (n1 - x)) / (2 * n);
    }
    if (used == 0) return null;
    if (!std.math.isFinite(total) or !std.math.isFinite(wsum)) return error.ExecError;
    var value: f64 = 0;
    for (weights, differences) |*w, d| {
        w.* /= wsum;
        value += w.* * d;
    }
    const mh = value;
    const mr = method == .minimum_risk or method == .newcombe_mr;
    if (mr) {
        var precision: f64 = 0;
        var weighted: f64 = 0;
        var target: f64 = 0;
        for (tables, weights, differences, variances) |t, w, d, v| if (w > 0) {
            if (v <= 0) return null;
            precision += 1 / v;
            weighted += d / v;
            target += (t.cells[0] + t.cells[1] + t.cells[2] + t.cells[3]) / total * d;
        };
        const center = weighted / precision;
        var dispersion: f64 = 0;
        for (weights, differences, variances) |w, d, v| if (w > 0) {
            dispersion += sq(d - center) / v;
        };
        // Equivalent to Mehrotra–Railkar's alpha/beta formula (p.197),
        // solving the quadratic minimum-MSE weights with sum(weights)=1.
        const shift = (target - center) / (1 + dispersion);
        value = 0;
        for (weights, differences, variances) |*w, d, v| if (w.* > 0) {
            w.* = (1 / precision + (d - center) * shift) / v;
            value += w.* * d;
        };
    }
    if (method == .summary_score) {
        var precision: f64 = 0;
        value = 0;
        for (tables, weights, differences, variances) |t, *w, *d, *v| if (w.* > 0) {
            const ci = try risk.differenceLimits(t, opts.column, opts.alpha, .miettinen_nurminen, false, true);
            d.* = (ci.lower.? + ci.upper.?) / 2;
            v.* = sq((ci.upper.? - ci.lower.?) / (2 * zcrit));
            if (v.* <= 0) return null;
            w.* = 1 / v.*;
            precision += w.*;
        };
        for (weights, differences) |*w, d| {
            w.* /= precision;
            value += w.* * d;
        }
    }
    var variance: f64 = 0;
    var test_variance: f64 = 0;
    for (weights, variances, null_variances) |w, v, v0| {
        variance += w * w * v;
        test_variance += w * w * v0;
    }
    if (method == .mantel_haenszel or method == .klingenberg) {
        variance = (mh * psum + qsum) / (wsum * wsum);
        test_variance = variance;
    }
    if (method == .summary_score or opts.sample_variance) test_variance = variance;
    const correction = if (method == .minimum_risk and opts.correct and 0.1875 / wsum < @abs(value)) 0.1875 / wsum else @as(f64, 0);
    var limits = risk.Interval{ .lower = value - zcrit * @sqrt(@max(0, variance)) - correction, .upper = value + zcrit * @sqrt(@max(0, variance)) + correction };
    if (method == .klingenberg) {
        const midpoint = mh + 0.5 * zcrit * zcrit * psum / (wsum * wsum);
        const width = @sqrt(@max(0, midpoint * midpoint - mh * mh + zcrit * zcrit * qsum / (wsum * wsum)));
        limits = .{ .lower = midpoint - width, .upper = midpoint + width };
    }
    if (method == .newcombe or method == .newcombe_mr) limits = try newcombe(tables, weights, value, opts);
    if (limits.lower) |l| limits.lower = @max(-1, l);
    if (limits.upper) |u| limits.upper = @min(1, u);
    const has_test = method == .mantel_haenszel or method == .minimum_risk or method == .summary_score;
    const z: ?f64 = if (has_test and test_variance > 0) (value - std.math.sign(value) * correction) / @sqrt(test_variance) else null;
    transferred = true;
    return .{ .value = value, .variance = if (has_test) variance else null, .limits = limits, .z = z, .p_two = if (z) |v| 2 * @exp(math.logStdNormTail(@abs(v))) else null, .weights = weights, .components = differences, .used = used };
}
fn newcombe(tables: []const Table, weights: []const f64, difference: f64, opts: Options) Error!risk.Interval {
    const z = -math.distQuantile(.normal, opts.alpha / 2, &.{}).?;
    var gamma = [_]f64{ 0, 0 };
    var lower = [_]f64{ 0, 0 };
    var upper = [_]f64{ 0, 0 };
    var variance = [_]f64{ 0, 0 };
    var se_sum = [_]f64{ 0, 0 };
    for (tables, weights) |t, w| if (w != 0) {
        const s = t.samples(opts.column);
        for (0..2) |j| {
            gamma[j] += w * w / s[j].total;
            const v = s[j].proportion() * (1 - s[j].proportion()) / s[j].total;
            variance[j] += w * w * v;
            se_sum[j] += w * @sqrt(v);
        }
    };
    for (tables, weights) |t, w| if (w != 0) {
        const s = t.samples(opts.column);
        for (0..2) |j| {
            if (se_sum[j] == 0) return .{};
            // Yan–Su stratum level (also Tang, arXiv:2110.12636, Lemma 2.2): z_gamma = z_alpha sqrt(sum(w² v)) /
            // sum(w sqrt(v)), separately for each response row (SAS p.198).
            const adjusted_alpha = 2 * @exp(math.logStdNormTail(z * @sqrt(variance[j]) / se_sum[j]));
            const ci = try risk.binomialLimits(s[j], adjusted_alpha, .wilson, false);
            lower[j] += w * ci.lower.?;
            upper[j] += w * ci.upper.?;
        }
    };
    return .{ .lower = difference - z * @sqrt(@max(0, gamma[0] * lower[0] * (1 - lower[0]) + gamma[1] * upper[1] * (1 - upper[1]))), .upper = difference + z * @sqrt(@max(0, gamma[1] * lower[1] * (1 - lower[1]) + gamma[0] * upper[0] * (1 - upper[0]))) };
}

pub const Logit = struct {
    ratio: strat.Ratio,
    homogeneity: ?strat.Chi,
    corrected: []bool,
    pub fn deinit(self: Logit, a: std.mem.Allocator) void {
        a.free(self.corrected);
    }
};
/// SAS logit correction adds 0.5 to EVERY cell only in affected strata. This
/// deliberately does not use risk.ratio(.wald_modified), whose RR denominator
/// has a different definition (row total +0.5 instead of corrected total +1).
pub fn logit(a: std.mem.Allocator, tables: []const Table, column: risk.Column, kind: risk.RatioKind, alpha: f64) Error!?Logit {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    const corrected = try a.alloc(bool, tables.len);
    @memset(corrected, false);
    var transferred = false;
    defer if (!transferred) a.free(corrected);
    var estimates: std.ArrayList(strat.Estimate) = .empty;
    defer estimates.deinit(a);
    for (tables, 0..) |raw, i| {
        if (!try active(raw)) continue;
        var t = raw;
        const s = t.samples(column);
        var adjust = s[0].success == 0 or s[1].success == 0;
        if (kind == .odds_ratio) for (t.cells) |v| {
            adjust = adjust or v == 0;
        };
        if (adjust) {
            for (&t.cells) |*v| v.* += 0.5;
            corrected[i] = true;
        }
        const result = try risk.ratio(t, column, kind, alpha, .wald, false);
        if (result.estimate == null or result.log_se == null or result.log_se.? <= 0) return null;
        try estimates.append(a, .{ .value = @log(result.estimate.?), .variance = sq(result.log_se.?), .lower = 0, .upper = 0 });
    }
    const pooled = try strat.pool(estimates.items, alpha) orelse return null;
    const e = pooled.coefficient;
    transferred = true;
    return .{ .ratio = .{ .value = @exp(e.value), .log_variance = e.variance, .lower = @exp(e.lower), .upper = @exp(e.upper) }, .homogeneity = pooled.homogeneity, .corrected = corrected };
}
pub fn gailSimon(a: std.mem.Allocator, tables: []const Table, column: risk.Column) Error!?strat.GailSimon {
    var estimates: std.ArrayList(strat.Estimate) = .empty;
    defer estimates.deinit(a);
    for (tables) |t| {
        if (!try active(t)) continue;
        const d = try risk.difference(t, column, 0.05, false);
        try estimates.append(a, .{ .value = d.estimate.?, .variance = sq(d.se.?), .lower = 0, .upper = 0 });
    }
    return strat.gailSimon(estimates.items);
}

test "stratified common risk all six interval methods independent SAS" {
    // common.sas / common.txt, SAS/STAT pp195–199; alpha=0.1. sasrun command
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-stratified/common.sas -f text -o /tmp/opensas-stat-batch2/FEAT-freq-stratified/common.txt -l /tmp/opensas-stat-batch2/FEAT-freq-stratified/common.log
    const a = std.testing.allocator;
    const tables = [_]Table{ .{ .cells = .{ 16, 11, 5, 20 } }, .{ .cells = .{ 12, 16, 7, 19 } } };
    const methods = [_]Method{ .mantel_haenszel, .klingenberg, .minimum_risk, .summary_score, .newcombe, .newcombe_mr };
    const values = [_]f64{ 0.2738, 0.2738, 0.2759, 0.2664, 0.2738, 0.2759 };
    const lo = [_]f64{ 0.1250, 0.1176, 0.1225, 0.1210, 0.1195, 0.1216 };
    const hi = [_]f64{ 0.4225, 0.4155, 0.4293, 0.4118, 0.4098, 0.4118 };
    for (methods, values, lo, hi) |method, v, l, u| {
        const result = (try commonDifference(a, &tables, method, .{ .alpha = 0.1 })).?;
        defer result.deinit(a);
        try std.testing.expectApproxEqAbs(v, result.value, 0.00005);
        try std.testing.expectApproxEqAbs(l, result.limits.lower.?, 0.00005);
        try std.testing.expectApproxEqAbs(u, result.limits.upper.?, 0.00005);
        switch (method) {
            .mantel_haenszel => {
                try std.testing.expectApproxEqAbs(@as(f64, 3.0270), result.z.?, 0.00005);
                try std.testing.expectApproxEqAbs(@as(f64, 0.4905), result.weights[0], 0.00005);
            },
            .minimum_risk => try std.testing.expectApproxEqAbs(@as(f64, 2.8549), result.z.?, 0.00005),
            .summary_score => {
                try std.testing.expectApproxEqAbs(@as(f64, 3.0139), result.z.?, 0.00005);
                try std.testing.expectApproxEqAbs(@as(f64, 0.3738), result.components[0], 0.00005);
                try std.testing.expectApproxEqAbs(@as(f64, 0.5158), result.weights[0], 0.00005);
            },
            else => {},
        }
    }
    const result = (try commonDifference(a, &tables, .minimum_risk, .{ .alpha = 0.1, .column = .second, .correct = false, .sample_variance = true })).?;
    defer result.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f64, -3.1013), result.z.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -0.4222), result.limits.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4997), result.weights[0], 0.00005);
}

test "stratified risk adapters pooled logit corrections and Gail Simon column" {
    const a = std.testing.allocator;
    const tables = [_]Table{ .{ .cells = .{ 16, 11, 5, 20 } }, .{ .cells = .{ 12, 16, 7, 19 } } };
    const odds = (try logit(a, &tables, .first, .odds_ratio, 0.05)).?;
    defer odds.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f64, 3.2941), odds.ratio.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.4182), odds.ratio.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 7.6515), odds.ratio.upper.?, 0.00005);
    const first = (try logit(a, &tables, .first, .relative_risk, 0.05)).?;
    defer first.deinit(a);
    const second = (try logit(a, &tables, .second, .relative_risk, 0.05)).?;
    defer second.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f64, 2.1059), first.ratio.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6613), second.ratio.value, 0.00005);
    const edge = [_]Table{.{ .cells = .{ 9, 0, 0, 6 } }};
    const rr = (try logit(a, &edge, .first, .relative_risk, 0.05)).?;
    defer rr.deinit(a);
    try std.testing.expect(rr.corrected[0]);
    try std.testing.expectApproxEqAbs(@as(f64, 13.3), rr.ratio.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9167), rr.ratio.lower.?, 0.00005);
    const gs1 = (try gailSimon(a, &tables, .first)).?;
    const gs2 = (try gailSimon(a, &tables, .second)).?;
    try std.testing.expectApproxEqAbs(gs1.positive, gs2.negative, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 11.6027), gs2.negative, 0.00005);
}

test "stratified common risk asymmetric strata oracle and weight order" {
    const a = std.testing.allocator;
    const tables = [_]Table{ .{ .cells = .{ 2, 18, 9, 1 } }, .{ .cells = .{ 12, 3, 1, 19 } }, .{ .cells = .{ 1, 4, 18, 2 } } };
    const methods = [_]Method{ .mantel_haenszel, .klingenberg, .minimum_risk, .summary_score, .newcombe, .newcombe_mr };
    const values = [_]f64{ -0.0886, -0.0886, -0.1689, -0.0678, -0.0886, -0.1689 };
    const lo = [_]f64{ -0.3665, -0.3623, -0.3259, -0.2147, -0.3023, -0.3823 };
    const hi = [_]f64{ 0.1893, 0.1936, -0.0120, 0.0791, 0.1326, 0.0584 };
    for (methods, values, lo, hi) |method, v, l, u| {
        const result = (try commonDifference(a, &tables, method, .{})).?;
        defer result.deinit(a);
        try std.testing.expectApproxEqAbs(v, result.value, 0.00005);
        try std.testing.expectApproxEqAbs(l, result.limits.lower.?, 0.00005);
        try std.testing.expectApproxEqAbs(u, result.limits.upper.?, 0.00005);
        const reordered = [_]Table{ tables[2], .{ .cells = .{ 0, 0, 0, 0 } }, tables[0], tables[1] };
        const reverse = (try commonDifference(a, &reordered, method, .{})).?;
        defer reverse.deinit(a);
        try std.testing.expectApproxEqAbs(result.value, reverse.value, 1e-12);
        try std.testing.expectEqual(@as(f64, 0), reverse.weights[1]);
        try std.testing.expectApproxEqAbs(result.weights[2], reverse.weights[0], 1e-12);
    }
}

test "stratified common risk boundary variances and undefined Newcombe SAS" {
    const a = std.testing.allocator;
    const first = [_]Table{ .{ .cells = .{ 0, 10, 5, 5 } }, .{ .cells = .{ 0, 20, 8, 12 } } };
    const mr = (try commonDifference(a, &first, .minimum_risk, .{})).?;
    defer mr.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f64, -0.4312), mr.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3125), mr.weights[0], 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0957), @sqrt(mr.variance.?), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -3.9525), mr.z.?, 0.00005);
    const nc = (try commonDifference(a, &first, .newcombe, .{})).?;
    defer nc.deinit(a);
    try std.testing.expectEqual(@as(?f64, null), nc.limits.lower);
    const boundary = [_]Table{ .{ .cells = .{ 10, 0, 0, 10 } }, .{ .cells = .{ 8, 0, 0, 12 } } };
    const perfect = (try commonDifference(a, &boundary, .minimum_risk, .{})).?;
    defer perfect.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5286), perfect.weights[0], 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0709), @sqrt(perfect.variance.?), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8420), perfect.limits.lower.?, 0.00005);
    try std.testing.expectEqual(@as(?f64, 1), perfect.limits.upper);
    try std.testing.expectApproxEqAbs(@as(f64, 6.1934), perfect.z.?, 0.00005);
    try std.testing.expectError(error.ExecError, commonDifference(a, &first, .minimum_risk, .{ .alpha = 0 }));
    const invalid = [_]Table{.{ .cells = .{ 1, -1, 2, 3 } }};
    try std.testing.expectError(error.ExecError, commonDifference(a, &invalid, .minimum_risk, .{}));
}
