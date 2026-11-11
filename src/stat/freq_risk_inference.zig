//! FREQ asymptotic hypothesis tests. Parser resolves proportions, defaults,
//! and NI/SUP margins into numeric null values; kernels preserve test tails.
const std = @import("std");
const risk = @import("freq_risk.zig");
const fns = @import("../functions.zig");
const Error = risk.Error;
pub const Variance = enum { sample, null_value };
pub const Hypothesis = union(enum) {
    equality: f64,
    /// NI and SUP both have a right-sided alternative after margin resolution.
    greater: f64,
    equivalence: struct { lower: f64, upper: f64 },
};
pub const Test = struct { chi_square: ?f64 = null, z: ?f64 = null, se: ?f64 = null, left: ?f64 = null, right: ?f64 = null, two_sided: ?f64 = null };
pub const Analysis = struct { lower: Test, upper: ?Test = null, p: ?f64, limits: risk.Interval };
fn wald(delta: f64, se: f64, correction: f64) Test {
    if (!std.math.isFinite(se) or se <= 0) return .{ .se = if (std.math.isFinite(se)) se else null };
    // SAS correction is signed, including +c at an exactly zero numerator.
    const z = (delta + (if (delta > 0) -correction else correction)) / se;
    return fromZ(z, se);
}
fn fromZ(z: f64, se: ?f64) Test {
    if (!std.math.isFinite(z)) return .{ .se = se };
    const left = fns.distCdf(.normal, z, &.{}).?;
    const right = fns.distCdf(.normal, -z, &.{}).?;
    return .{ .z = z, .se = se, .left = left, .right = right, .two_sided = 2 * @min(left, right) };
}
fn nulls(h: Hypothesis) Error![2]f64 {
    const values: [2]f64 = switch (h) {
        .equality, .greater => |v| .{ v, v },
        .equivalence => |v| .{ v.lower, v.upper },
    };
    for (values) |v| if (!std.math.isFinite(v)) return error.ExecError;
    if (h == .equivalence and values[0] >= values[1]) return error.ExecError;
    return values;
}
fn assemble(h: Hypothesis, tests: [2]Test, limits: risk.Interval) Analysis {
    return .{ .lower = tests[0], .upper = if (h == .equivalence) tests[1] else null, .p = switch (h) {
        .equality => tests[0].two_sided,
        .greater => tests[0].right,
        .equivalence => if (tests[0].right != null and tests[1].left != null) @max(tests[0].right.?, tests[1].left.?) else null,
    }, .limits = limits };
}
fn testLimits(estimate: f64, tests: [2]Test, alpha: f64, correction: f64, lo: f64, hi: f64) Error!risk.Interval {
    if (!(alpha > 0 and alpha < 0.5)) return error.ExecError;
    if (tests[0].se == null or tests[1].se == null) return .{};
    const width = -fns.distQuantile(.normal, alpha, &.{}).? * @max(tests[0].se.?, tests[1].se.?) + correction;
    return .{ .lower = @max(lo, estimate - width), .upper = @min(hi, estimate + width) };
}
pub fn binomial(s: risk.Binomial, h: Hypothesis, variance: Variance, alpha: f64, correct: bool) Error!Analysis {
    try s.validate();
    const values = try nulls(h);
    const c: f64 = if (correct) 0.5 / s.total else 0;
    var tests: [2]Test = undefined;
    for (values, &tests) |v, *t| {
        if (!(v > 0 and v < 1)) return error.ExecError;
        const p = if (variance == .sample) s.proportion() else v;
        t.* = wald(s.proportion() - v, @sqrt(p * (1 - p) / s.total), c);
    }
    // Equality accompanies the ordinary 1-alpha proportion interval, whose
    // variance is sample-based even when the equality test uses VAR=NULL.
    // Do not construct the NI/TOST interval (or apply its alpha restriction).
    const limits = if (h == .equality)
        (try risk.proportion(s, alpha, correct)).limits
    else
        try testLimits(s.proportion(), tests, alpha, c, 0, 1);
    return assemble(h, tests, limits);
}
pub const DifferenceMethod = enum { wald, hauck_anderson, farrington_manning, newcombe };
pub fn difference(table: risk.Table2x2, column: risk.Column, h: Hypothesis, method: DifferenceMethod, variance: Variance, alpha: f64, correct: bool) Error!Analysis {
    try table.validate();
    const values = try nulls(h);
    for (values) |v| if (@abs(v) >= 1) return error.ExecError;
    if (method == .newcombe) {
        if (h == .equality) return error.ExecError;
        return assemble(h, .{ .{}, .{} }, try risk.differenceLimits(table, column, 2 * alpha, .newcombe, correct, false));
    }
    const s = table.samples(column);
    const d = s[0].proportion() - s[1].proportion();
    const c: f64 = if (method == .hauck_anderson) 1 / (2 * @min(s[0].total, s[1].total)) else if (method == .wald and correct) (1 / s[0].total + 1 / s[1].total) / 2 else 0;
    var tests: [2]Test = undefined;
    for (values, &tests) |v, *t| {
        var p1 = s[0].proportion();
        var p2 = s[1].proportion();
        if (method == .farrington_manning) {
            const fit = try risk.constrainedFit(table, column, .{ .difference = v });
            p1 = fit.p1;
            p2 = fit.p2;
        } else if (method == .wald and variance == .null_value) {
            // Dunnett-Gent null variance is NOT the constrained MLE (p191).
            p2 = (s[0].success + s[1].success - v * s[0].total) / (s[0].total + s[1].total);
            p1 = p2 + v;
        }
        const adjust: f64 = if (method == .hauck_anderson) 1 else 0;
        const var_est = p1 * (1 - p1) / (s[0].total - adjust) + p2 * (1 - p2) / (s[1].total - adjust);
        t.* = wald(d - v, @sqrt(var_est), c);
    }
    const limits = if (h == .equality)
        (try risk.difference(table, column, alpha, correct)).limits
    else
        try testLimits(d, tests, alpha, c, -1, 1);
    return assemble(h, tests, limits);
}
pub fn relativeRisk(table: risk.Table2x2, column: risk.Column, h: Hypothesis, method: risk.RatioMethod, alpha: f64) Error!Analysis {
    const values = try nulls(h);
    if (!(alpha > 0 and alpha < (if (h == .equality) @as(f64, 1) else 0.5))) return error.ExecError;
    // SAS uses bias-corrected score confidence limits even though the FM
    // test itself uses the uncorrected variance (tests.sas: 1.7774,7.6072).
    const estimate = try risk.ratio(table, column, .relative_risk, if (h == .equality) alpha else 2 * alpha, method, true);
    var tests: [2]Test = undefined;
    for (values, &tests) |v, *t| {
        if (v <= 0) return error.ExecError;
        t.* = switch (method) {
            .wald, .wald_modified => if (estimate.estimate != null and estimate.log_se != null) wald(@log(estimate.estimate.?) - @log(v), estimate.log_se.?, 0) else .{},
            .score => blk: {
                const fit = try risk.constrainedFit(table, column, .{ .relative_risk = v });
                const samples = table.samples(column);
                const se = @sqrt(fit.p1 * (1 - fit.p1) / samples[0].total + v * v * fit.p2 * (1 - fit.p2) / samples[1].total);
                break :blk fromZ(try risk.relativeRiskScore(table, column, v, false), se);
            },
            .likelihood_ratio => blk: {
                const g2 = try risk.ratioStatistic(table, column, .relative_risk, v, .likelihood_ratio, false);
                const s = table.samples(column);
                const sign: f64 = if (s[0].proportion() >= v * s[1].proportion()) 1 else -1;
                var result = fromZ(sign * @sqrt(g2), null);
                if (h == .equality) result.chi_square = g2;
                break :blk result;
            },
        };
    }
    return assemble(h, tests, estimate.limits);
}

// SAS/STAT pp179-183,190-194,206-209. Independent oracle command:
// /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-risk/tests.sas
// -f text -o /tmp/opensas-stat-batch2/FEAT-freq-risk/tests.txt
// -l /tmp/opensas-stat-batch2/FEAT-freq-risk/tests.log
// Printed values have four decimals; tolerate only half of the last digit.
fn near(expected: f64, actual: ?f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual.?, 0.00005);
}
test "FEAT-freq-risk SAS binomial NI SUP TOST and equality variance" {
    const s = risk.Binomial{ .success = 7, .total = 20 };
    const equal = try binomial(s, .{ .equality = 0.5 }, .null_value, 0.05, false);
    try near(-1.3416, equal.lower.z);
    try near(0.1797, equal.p);
    const ni = try binomial(s, .{ .greater = 0.3 }, .sample, 0.05, false);
    try near(0.4688, ni.lower.z);
    try near(0.3196, ni.p);
    try near(0.1746, ni.limits.lower);
    try near(0.5254, ni.limits.upper);
    const sup = try binomial(s, .{ .greater = 0.3 }, .null_value, 0.05, false);
    try near(0.4880, sup.lower.z);
    try near(0.3128, sup.p);
    try near(0.1815, sup.limits.lower);
    try near(0.5185, sup.limits.upper);
    const eq = try binomial(s, .{ .equivalence = .{ .lower = 0.2, .upper = 0.6 } }, .null_value, 0.05, true);
    try near(1.3975, eq.lower.z);
    try near(-2.0540, eq.upper.?.z);
    try near(0.0811, eq.p);
    try near(0.1448, eq.limits.lower);
    try near(0.5552, eq.limits.upper);
}
test "FEAT-freq-risk SAS difference TOST Wald HA FM and Newcombe" {
    const table = risk.Table2x2{ .cells = .{ 12, 8, 5, 25 } };
    const hypothesis = Hypothesis{ .equivalence = .{ .lower = -0.1, .upper = 0.6 } };
    const methods = [_]DifferenceMethod{ .wald, .hauck_anderson, .farrington_manning };
    const expected = [_][5]f64{ .{ 4.1358, -1.2924, 0.0981, 0.2212, 0.6454 }, .{ 3.8514, -1.0733, 0.1416, 0.1912, 0.6754 }, .{ 3.9279, -1.4287, 0.0765, 0.2100, 0.6567 } };
    for (methods, expected) |m, e| {
        const r = try difference(table, .first, hypothesis, m, .sample, 0.05, false);
        try near(e[0], r.lower.z);
        try near(e[1], r.upper.?.z);
        try near(e[2], r.p);
        try near(e[3], r.limits.lower);
        try near(e[4], r.limits.upper);
    }
    const nc = try difference(table, .first, hypothesis, .newcombe, .sample, 0.05, false);
    try std.testing.expect(nc.p == null and nc.lower.z == null);
    try near(0.2052, nc.limits.lower);
    try near(0.6115, nc.limits.upper);
}
test "FEAT-freq-risk SAS relative risk TOST four methods" {
    const table = risk.Table2x2{ .cells = .{ 12, 8, 5, 25 } };
    const hypothesis = Hypothesis{ .equivalence = .{ .lower = 0.8, .upper = 5 } };
    const methods = [_]risk.RatioMethod{ .wald, .wald_modified, .score, .likelihood_ratio };
    const expected = [_][5]f64{ .{ 3.3632, -0.7346, 0.2313, 1.7252, 7.5122 }, .{ 3.3951, -0.9213, 0.1784, 1.6819, 6.7979 }, .{ 3.8010, -0.7269, 0.2336, 1.7774, 7.6072 }, .{ 3.7260, -0.7000, 0.2420, 1.8283, 8.2652 } };
    for (methods, expected) |m, e| {
        const r = try relativeRisk(table, .first, hypothesis, m, 0.05);
        try near(e[0], r.lower.z);
        try near(e[1], r.upper.?.z);
        try near(e[2], r.p);
        try near(e[3], r.limits.lower);
        try near(e[4], r.limits.upper);
    }
}

test "FEAT-freq-risk SAS equality alpha and sample CI independent of null variance" {
    // SAS/STAT pp176,179-180,185-186,190,203,206. Independent command:
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-risk/equality-alpha.sas
    // -f text -o /tmp/opensas-stat-batch2/FEAT-freq-risk/equality-alpha.txt
    // -l /tmp/opensas-stat-batch2/FEAT-freq-risk/equality-alpha.log
    // Zero errors/warnings: ALPHA=.6 is valid for equality (40% CI).
    // P=.2 distinguishes test SE=.0894 from sample CI SE=.1067.
    const sample = risk.Binomial{ .success = 7, .total = 20 };
    const wide = try binomial(sample, .{ .equality = 0.2 }, .null_value, 0.05, false);
    const narrow = try binomial(sample, .{ .equality = 0.2 }, .null_value, 0.6, false);
    try near(0.1410, wide.limits.lower);
    try near(0.5590, wide.limits.upper);
    try near(0.2941, narrow.limits.lower);
    try near(0.4059, narrow.limits.upper);
    try near(0.0894, narrow.lower.se);
    try near(1.6771, narrow.lower.z);
    try near(0.0935, narrow.p);
    try std.testing.expectEqual(wide.p, narrow.p);
    // All otherwise-valid table alphas remain legal, including .5 itself.
    _ = try binomial(sample, .{ .equality = 0.2 }, .null_value, 0.5, false);
    _ = try binomial(sample, .{ .equality = 0.2 }, .null_value, 0.99, false);
    const table = risk.Table2x2{ .cells = .{ 12, 8, 5, 25 } };
    const rd = try difference(table, .first, .{ .equality = 0.1 }, .wald, .null_value, 0.6, false);
    try near(0.3657, rd.limits.lower);
    try near(0.5010, rd.limits.upper);
    try near(0.1378, rd.lower.se);
    try near(2.4183, rd.lower.z);
    try near(0.0156, rd.p);
    const rr = try relativeRisk(table, .first, .{ .equality = 2 }, .wald, 0.6);
    try near(2.8474, rr.limits.lower);
    try near(4.5515, rr.limits.upper);
    try near(1.3143, rr.lower.z);
    try near(0.1887, rr.p);
    for ([_]f64{ 0, 1, std.math.nan(f64) }) |alpha| {
        try std.testing.expectError(error.ExecError, binomial(sample, .{ .equality = 0.2 }, .null_value, alpha, false));
        try std.testing.expectError(error.ExecError, difference(table, .first, .{ .equality = 0.1 }, .wald, .null_value, alpha, false));
        try std.testing.expectError(error.ExecError, relativeRisk(table, .first, .{ .equality = 2 }, .wald, alpha));
    }
}
