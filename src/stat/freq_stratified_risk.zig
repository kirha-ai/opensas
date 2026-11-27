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
    // S154 physical p.3203: a single stratum is exactly the unstratified
    // Newcombe interval. Use that identity also at p=0 or p=1, where the
    // generic Yan-Su level expression below would otherwise evaluate 0/0.
    // Empty-row strata have zero weight and do not create another stratum.
    var single: ?Table = null;
    var used: usize = 0;
    for (tables) |table| if (try active(table)) {
        single = table;
        used += 1;
    };
    if (used == 1) return risk.differenceLimits(single.?, opts.column, opts.alpha, .newcombe, false, true);
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
    // common.sas / common.txt, SAS/STAT pp195–199; alpha=0.1.
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

// STAT-FREQ-010, S154 physical pp.3199-3203. Exact rational arithmetic
// on the three unbalanced tables below gives W=404/21, P=3029/3675,
// Q=1127/150, d=-179/2020 and Sato variance=165699117/8242408000.
// These contracts supplement four-decimal SAS references with independent
// algebra and orientation checks. 2e-12 allows ordinary double arithmetic
// and the documented numerical inversions, not changes in displayed values.
test "FREQ010 exact Sato rational variance and Klingenberg inversion" {
    const a = std.testing.allocator;
    const tables = [_]Table{ .{ .cells = .{ 2, 18, 9, 1 } }, .{ .cells = .{ 12, 3, 1, 19 } }, .{ .cells = .{ 1, 4, 18, 2 } } };
    const mh = (try commonDifference(a, &tables, .mantel_haenszel, .{})).?;
    defer mh.deinit(a);
    const k = (try commonDifference(a, &tables, .klingenberg, .{})).?;
    defer k.deinit(a);
    const expected: f64 = -179.0 / 2020.0;
    const variance: f64 = 165699117.0 / 8242408000.0;
    try std.testing.expectApproxEqAbs(expected, mh.value, 2e-15);
    try std.testing.expectApproxEqAbs(variance, mh.variance.?, 2e-15);
    try std.testing.expectApproxEqAbs(expected / @sqrt(variance), mh.z.?, 2e-14);
    const z: f64 = 1.95996398454005423552;
    try std.testing.expectApproxEqAbs(expected - z * @sqrt(variance), mh.limits.lower.?, 2e-12);
    try std.testing.expectApproxEqAbs(expected + z * @sqrt(variance), mh.limits.upper.?, 2e-12);
    for ([_]f64{ k.limits.lower.?, k.limits.upper.? }) |delta| {
        // Klingenberg inverts (d-delta)^2 = z^2 (delta P + Q)/W^2.
        // Checking the equation avoids regenerating endpoints from production.
        const null_variance = (delta * (3029.0 / 3675.0) + 1127.0 / 150.0) / sq(404.0 / 21.0);
        try std.testing.expectApproxEqAbs(sq(expected - delta), z * z * null_variance, 2e-13);
    }
    try std.testing.expectEqual(@as(?f64, null), k.variance);
    try std.testing.expectEqual(@as(?f64, null), k.z);
    try std.testing.expectEqual(@as(?f64, null), k.p_two);
}

test "FREQ010 minimum risk independently minimizes quadratic MSE" {
    const a = std.testing.allocator;
    const tables = [_]Table{ .{ .cells = .{ 2, 18, 9, 1 } }, .{ .cells = .{ 12, 3, 1, 19 } }, .{ .cells = .{ 1, 4, 18, 2 } } };
    const d = [_]f64{ -0.8, 0.75, -0.7 };
    const v = [_]f64{ 0.1 * 0.9 / 20.0 + 0.9 * 0.1 / 10.0, 0.8 * 0.2 / 15.0 + 0.05 * 0.95 / 20.0, 0.2 * 0.8 / 5.0 + 0.9 * 0.1 / 20.0 };
    const target: f64 = (30 * d[0] + 35 * d[1] + 25 * d[2]) / 90;
    const mr = (try commonDifference(a, &tables, .minimum_risk, .{ .correct = false, .sample_variance = true })).?;
    defer mr.deinit(a);
    var estimate: f64 = 0;
    var variance: f64 = 0;
    var sum: f64 = 0;
    for (mr.weights, d, v) |w, delta, variance_h| {
        sum += w;
        estimate += w * delta;
        variance += w * w * variance_h;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1), sum, 2e-14);
    try std.testing.expectApproxEqAbs(estimate, mr.value, 2e-14);
    try std.testing.expectApproxEqAbs(variance, mr.variance.?, 2e-14);
    // Objective: sum(v_h*w_h^2) + (sum(d_h*w_h)-target)^2.
    // Positive v_h makes it strictly convex. With sum(w)=1, all gradient
    // components must equal the same Lagrange multiplier: sufficient AND
    // necessary for the unique minimum, independently of alpha/beta algebra.
    const gradient = v[0] * mr.weights[0] + d[0] * (estimate - target);
    for (mr.weights, d, v) |w, delta, variance_h|
        try std.testing.expectApproxEqAbs(gradient, variance_h * w + delta * (estimate - target), 2e-14);
    try std.testing.expectApproxEqAbs(estimate / @sqrt(variance), mr.z.?, 2e-13);
    const corrected = (try commonDifference(a, &tables, .minimum_risk, .{ .sample_variance = true })).?;
    defer corrected.deinit(a);
    const correction: f64 = 0.1875 / (404.0 / 21.0);
    try std.testing.expectApproxEqAbs(mr.limits.lower.? - correction, corrected.limits.lower.?, 2e-14);
    try std.testing.expectApproxEqAbs(mr.limits.upper.? + correction, corrected.limits.upper.?, 2e-14);
    try std.testing.expectApproxEqAbs((estimate + correction) / @sqrt(variance), corrected.z.?, 2e-13);
}

test "FREQ010 every common interval reverses columns and retains sparse stratum slots" {
    const a = std.testing.allocator;
    // Includes a zero cell, unbalanced margins, and an unusable all-zero row.
    const tables = [_]Table{ .{ .cells = .{ 0, 10, 3, 17 } }, .{ .cells = .{ 0, 0, 6, 8 } }, .{ .cells = .{ 12, 8, 5, 25 } } };
    for (std.enums.values(Method)) |method| {
        const first = (try commonDifference(a, &tables, method, .{})).?;
        defer first.deinit(a);
        const second = (try commonDifference(a, &tables, method, .{ .column = .second })).?;
        defer second.deinit(a);
        try std.testing.expectEqual(@as(usize, 2), first.used);
        try std.testing.expectEqual(@as(usize, tables.len), first.weights.len);
        try std.testing.expectEqual(@as(f64, 0), first.weights[1]);
        try std.testing.expectApproxEqAbs(@as(f64, 1), first.weights[0] + first.weights[2], 2e-14);
        try std.testing.expectApproxEqAbs(-first.value, second.value, 2e-12);
        try std.testing.expectApproxEqAbs(-first.limits.upper.?, second.limits.lower.?, 2e-12);
        try std.testing.expectApproxEqAbs(-first.limits.lower.?, second.limits.upper.?, 2e-12);
        for (first.weights, second.weights) |w1, w2| try std.testing.expectApproxEqAbs(w1, w2, 2e-12);
        if (first.variance) |v1| try std.testing.expectApproxEqAbs(v1, second.variance.?, 2e-12);
        if (first.z) |z1| try std.testing.expectApproxEqAbs(-z1, second.z.?, 2e-12);
        if (first.p_two) |p1| try std.testing.expectApproxEqAbs(p1, second.p_two.?, 2e-12);
    }
}

test "FREQ010 single stratum score and Newcombe reduce to unstratified intervals" {
    const a = std.testing.allocator;
    const table = Table{ .cells = .{ 16, 11, 5, 20 } };
    for ([_]risk.Column{ .first, .second }) |column| {
        const options = Options{ .column = column, .alpha = 0.1 };
        const score = (try commonDifference(a, &.{table}, .summary_score, options)).?;
        defer score.deinit(a);
        const mn = try risk.differenceLimits(table, column, 0.1, .miettinen_nurminen, false, true);
        try std.testing.expectApproxEqAbs(mn.lower.?, score.limits.lower.?, 2e-13);
        try std.testing.expectApproxEqAbs(mn.upper.?, score.limits.upper.?, 2e-13);
        try std.testing.expectApproxEqAbs((mn.lower.? + mn.upper.?) / 2, score.value, 2e-13);
        const nc = try risk.differenceLimits(table, column, 0.1, .newcombe, false, true);
        for ([_]Method{ .newcombe, .newcombe_mr }) |method| {
            const common = (try commonDifference(a, &.{table}, method, options)).?;
            defer common.deinit(a);
            try std.testing.expectApproxEqAbs(nc.lower.?, common.limits.lower.?, 2e-13);
            try std.testing.expectApproxEqAbs(nc.upper.?, common.limits.upper.?, 2e-13);
            try std.testing.expectApproxEqAbs(@as(f64, 1), common.weights[0], 2e-14);
        }
    }
}

test "FREQ010 single-stratum Newcombe boundary has Wilson-derived finite limits" {
    const a = std.testing.allocator;
    const table = Table{ .cells = .{ 0, 10, 5, 5 } };
    const z: f64 = 1.95996398454005423552;
    // Wilson for 0/10: [0,z²/(10+z²)]; for 5/10: [1/2-h,1/2+h]
    // where h=z/(2sqrt(10+z²)). Unstratified Newcombe combines the
    // corresponding Wilson distances in quadrature (S154 pp.3190,3203).
    const upper_zero = z * z / (10 + z * z);
    const h = z / (2 * @sqrt(10 + z * z));
    const lower = -0.5 - h;
    const upper = -0.5 + @sqrt(upper_zero * upper_zero + h * h);
    for ([_]Method{ .newcombe, .newcombe_mr }) |method| {
        for ([_]risk.Column{ .first, .second }) |column| {
            const result = (try commonDifference(a, &.{ .{ .cells = .{ 0, 0, 2, 3 } }, table }, method, .{ .column = column })).?;
            defer result.deinit(a);
            try std.testing.expectEqual(@as(usize, 1), result.used);
            try std.testing.expectEqual(@as(f64, 0), result.weights[0]);
            try std.testing.expectApproxEqAbs(if (column == .first) lower else -upper, result.limits.lower.?, 2e-12);
            try std.testing.expectApproxEqAbs(if (column == .first) upper else -lower, result.limits.upper.?, 2e-12);
        }
    }
}
