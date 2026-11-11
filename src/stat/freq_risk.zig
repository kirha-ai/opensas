//! FREQ risk kernels (SAS/STAT pp176-209). No parsing or listing dependencies.
//! Counts arrive in table order after table-layer weight/missing policy.
//! Public FREQ integration and exact inversion are separate, pending stages.
const std = @import("std");
const fns = @import("../functions.zig");
pub const Error = @import("../diag.zig").Error;
pub const Column = enum { first, second };
pub const Interval = struct { lower: ?f64 = null, upper: ?f64 = null };
pub const Estimate = struct { estimate: ?f64 = null, se: ?f64 = null, limits: Interval = .{} };
pub const Binomial = struct {
    success: f64,
    total: f64,
    pub fn validate(self: Binomial) Error!void {
        if (!std.math.isFinite(self.total) or !std.math.isFinite(self.success) or self.total <= 0 or self.success < 0 or self.success > self.total) return error.ExecError;
    }
    pub fn proportion(self: Binomial) f64 {
        return self.success / self.total;
    }
};
pub const Table2x2 = struct {
    cells: [4]f64,
    pub fn validate(self: Table2x2) Error!void {
        for (self.cells) |v| if (!std.math.isFinite(v) or v < 0) return error.ExecError;
        const rows = self.samples(.first);
        try rows[0].validate();
        try rows[1].validate();
        if (!std.math.isFinite(rows[0].total + rows[1].total)) return error.ExecError;
    }
    pub fn samples(self: Table2x2, column: Column) [2]Binomial {
        const c: usize = if (column == .first) 0 else 1;
        return .{ .{ .success = self.cells[c], .total = self.cells[0] + self.cells[1] }, .{ .success = self.cells[c + 2], .total = self.cells[2] + self.cells[3] } };
    }
};
fn square(x: f64) f64 {
    return x * x;
}
fn critical(alpha: f64) Error!f64 {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    // Lower-tail evaluation avoids rounding 1-alpha/2 to one.
    return -fns.distQuantile(.normal, alpha / 2, &.{}).?;
}
fn bounded(center: f64, width: f64, lo: f64, hi: f64) Interval {
    return .{ .lower = @max(lo, center - width), .upper = @min(hi, center + width) };
}
pub fn proportion(sample: Binomial, alpha: f64, correct: bool) Error!Estimate {
    try sample.validate();
    const z = try critical(alpha);
    const p = sample.proportion();
    const se = @sqrt(p * (1 - p) / sample.total);
    return .{ .estimate = p, .se = se, .limits = bounded(p, z * se + (if (correct) 0.5 / sample.total else @as(f64, 0)), 0, 1) };
}
pub const BinomialMethod = enum { wald, clopper_pearson, agresti_coull, jeffreys, likelihood_ratio, logit, wilson };
fn betaQuantile(p: f64, a: f64, b: f64) f64 {
    return fns.bisectCdf(.beta, p, a, b, 0, 1);
}
fn deviance(s: Binomial, p: f64) f64 {
    const observed = s.proportion();
    var d: f64 = 0;
    if (s.success > 0) d += s.success * @log(observed / p);
    if (s.success < s.total) d += (s.total - s.success) * @log((1 - observed) / (1 - p));
    return 2 * d;
}
pub fn binomialLimits(s: Binomial, alpha: f64, method: BinomialMethod, correct: bool) Error!Interval {
    const base = try proportion(s, alpha, correct);
    const p = base.estimate.?;
    const z = try critical(alpha);
    const z2 = z * z;
    const n = s.total;
    const x = s.success;
    switch (method) {
        .wald => return base.limits,
        .clopper_pearson => return .{ .lower = if (x == 0) 0 else betaQuantile(alpha / 2, x, n - x + 1), .upper = if (x == n) 1 else 1 - betaQuantile(alpha / 2, n - x, x + 1) },
        .jeffreys => return .{ .lower = if (x == 0) 0 else betaQuantile(alpha / 2, x + 0.5, n - x + 0.5), .upper = if (x == n) 1 else 1 - betaQuantile(alpha / 2, n - x + 0.5, x + 0.5) },
        .agresti_coull => {
            const nn = n + z2;
            const pp = (x + z2 / 2) / nn;
            return bounded(pp, z * @sqrt(pp * (1 - pp) / nn), 0, 1);
        },
        .logit => {
            if (x == 0) return .{ .lower = 0 };
            if (x == n) return .{ .upper = 1 };
            const logit = @log(p / (1 - p));
            const width = z * @sqrt(n / (x * (n - x)));
            return .{ .lower = 1 / (1 + @exp(-logit + width)), .upper = 1 / (1 + @exp(-logit - width)) };
        },
        .wilson => {
            // Inverting |p-phat|-c=z*sqrt(p(1-p)/n) gives Wilson
            // limits with shifted observed proportions on each side.
            const c: f64 = if (correct) 0.5 / n else 0;
            const pl = @max(0, p - c);
            const pu = @min(1, p + c);
            const den = 1 + z2 / n;
            return .{ .lower = if (x == 0) 0 else @max(0, (pl + z2 / (2 * n) - z * @sqrt(pl * (1 - pl) / n + z2 / (4 * n * n))) / den), .upper = if (x == n) 1 else @min(1, (pu + z2 / (2 * n) + z * @sqrt(pu * (1 - pu) / n + z2 / (4 * n * n))) / den) };
        },
        .likelihood_ratio => {
            var limits = Interval{};
            inline for (.{ false, true }) |upper| {
                var lo: f64 = if (upper) p else 0;
                var hi: f64 = if (upper) 1 else p;
                for (0..100) |_| {
                    const mid = (lo + hi) / 2;
                    if ((deviance(s, mid) > z2) == upper) hi = mid else lo = mid;
                }
                if (upper) limits.upper = (lo + hi) / 2 else limits.lower = (lo + hi) / 2;
            }
            return limits;
        },
    }
}
pub const Sensitivity = struct { sensitivity: Estimate, specificity: Estimate, positive_predictive: Estimate, negative_predictive: Estimate };
pub fn sensitivity(table: Table2x2, alpha: f64) Error!Sensitivity {
    try table.validate();
    _ = try critical(alpha);
    const c = table.cells;
    return .{
        .sensitivity = if (c[0] + c[2] == 0) .{} else try proportion(.{ .success = c[0], .total = c[0] + c[2] }, alpha, false),
        .specificity = if (c[1] + c[3] == 0) .{} else try proportion(.{ .success = c[3], .total = c[1] + c[3] }, alpha, false),
        .positive_predictive = try proportion(table.samples(.first)[0], alpha, false),
        .negative_predictive = try proportion(table.samples(.second)[1], alpha, false),
    };
}
pub const Constraint = union(enum) { difference: f64, relative_risk: f64, odds_ratio: f64 };
pub const Fit = struct { p1: f64, p2: f64 };
fn derivative(s: Binomial, p: f64) f64 {
    return (if (s.success == 0) @as(f64, 0) else s.success / p) - (if (s.success == s.total) @as(f64, 0) else (s.total - s.success) / (1 - p));
}
/// Constrained binomial MLE, shared with score tests and exact tail ordering.
/// Bisection of the monotone score avoids cubic cancellation for RD near 0.
pub fn constrainedFit(table: Table2x2, column: Column, constraint: Constraint) Error!Fit {
    try table.validate();
    const s = table.samples(column);
    var lo: f64 = 0;
    var hi: f64 = 1;
    switch (constraint) {
        .difference => |d| {
            if (!std.math.isFinite(d) or @abs(d) > 1) return error.ExecError;
            lo = @max(0, -d);
            hi = @min(1, 1 - d);
        },
        .relative_risk => |r| {
            if (!std.math.isFinite(r) or r <= 0) return error.ExecError;
            hi = @min(1, 1 / r);
        },
        .odds_ratio => |r| if (!std.math.isFinite(r) or r <= 0) return error.ExecError,
    }
    // OR uses the logistic intercept score n1*p1+n2*p2=successes.
    for (0..100) |_| {
        const p2 = (lo + hi) / 2;
        const p1 = constrainedP1(p2, constraint);
        const score = switch (constraint) {
            .difference => derivative(s[0], p1) + derivative(s[1], p2),
            .relative_risk => |r| r * derivative(s[0], p1) + derivative(s[1], p2),
            .odds_ratio => s[0].success + s[1].success - s[0].total * p1 - s[1].total * p2,
        };
        if (score > 0) lo = p2 else hi = p2;
    }
    const p2 = (lo + hi) / 2;
    return .{ .p1 = constrainedP1(p2, constraint), .p2 = p2 };
}
fn constrainedP1(p2: f64, constraint: Constraint) f64 {
    return switch (constraint) {
        .difference => |d| @max(0, @min(1, p2 + d)),
        .relative_risk => |r| @min(1, r * p2),
        .odds_ratio => |r| r * p2 / (1 - p2 + r * p2),
    };
}
pub fn differenceScore(table: Table2x2, column: Column, null_value: f64, bias_correct: bool) Error!f64 {
    const fit = try constrainedFit(table, column, .{ .difference = null_value });
    const s = table.samples(column);
    const n = s[0].total + s[1].total;
    const v = (fit.p1 * (1 - fit.p1) / s[0].total + fit.p2 * (1 - fit.p2) / s[1].total) * (if (bias_correct) n / (n - 1) else @as(f64, 1));
    const delta = s[0].proportion() - s[1].proportion() - null_value;
    if (delta == 0 and v == 0) return 0;
    return delta / @sqrt(v);
}
pub const DifferenceMethod = enum { wald, agresti_caffo, hauck_anderson, newcombe, miettinen_nurminen };
pub fn difference(table: Table2x2, column: Column, alpha: f64, correct: bool) Error!Estimate {
    try table.validate();
    const z = try critical(alpha);
    const s = table.samples(column);
    const p1 = s[0].proportion();
    const p2 = s[1].proportion();
    const se = @sqrt(p1 * (1 - p1) / s[0].total + p2 * (1 - p2) / s[1].total);
    const c: f64 = if (correct) (1 / s[0].total + 1 / s[1].total) / 2 else 0;
    return .{ .estimate = p1 - p2, .se = se, .limits = bounded(p1 - p2, z * se + c, -1, 1) };
}
pub fn differenceLimits(table: Table2x2, column: Column, alpha: f64, method: DifferenceMethod, correct: bool, bias_correct: bool) Error!Interval {
    const base = try difference(table, column, alpha, correct);
    const s = table.samples(column);
    const d = base.estimate.?;
    const z = try critical(alpha);
    switch (method) {
        .wald => return base.limits,
        .agresti_caffo => {
            var adjusted = table;
            for (&adjusted.cells) |*v| v.* += 1;
            return (try difference(adjusted, column, alpha, false)).limits;
        },
        .hauck_anderson => {
            if (s[0].total <= 1 or s[1].total <= 1) return .{};
            const p1 = s[0].proportion();
            const p2 = s[1].proportion();
            const se = @sqrt(p1 * (1 - p1) / (s[0].total - 1) + p2 * (1 - p2) / (s[1].total - 1));
            return bounded(d, 1 / (2 * @min(s[0].total, s[1].total)) + z * se, -1, 1);
        },
        .newcombe => {
            const a = try binomialLimits(s[0], alpha, .wilson, correct);
            const b = try binomialLimits(s[1], alpha, .wilson, correct);
            return .{ .lower = d - @sqrt(square(s[0].proportion() - a.lower.?) + square(b.upper.? - s[1].proportion())), .upper = d + @sqrt(square(a.upper.? - s[0].proportion()) + square(s[1].proportion() - b.lower.?)) };
        },
        .miettinen_nurminen => {
            var limits = Interval{};
            inline for (.{ false, true }) |upper| {
                var lo: f64 = if (upper) d else -1;
                var hi: f64 = if (upper) 1 else d;
                for (0..80) |_| {
                    const mid = (lo + hi) / 2;
                    const score = try differenceScore(table, column, mid, bias_correct);
                    if (score > (if (upper) -z else z)) lo = mid else hi = mid;
                }
                if (upper) limits.upper = (lo + hi) / 2 else limits.lower = (lo + hi) / 2;
            }
            return limits;
        },
    }
}

// Independent oracle: /Users/thomas/sas/bin/sasrun
// /tmp/opensas-stat-batch2/FEAT-freq-risk/kernels.sas -f text
// -o /tmp/opensas-stat-batch2/FEAT-freq-risk/kernels.txt
// -l /tmp/opensas-stat-batch2/FEAT-freq-risk/kernels.log
// SAS/STAT pp176-179,184-189. 4-decimal listing -> half-unit 0.00005.
fn expectLimits(actual: Interval, lo: f64, hi: f64) !void {
    try std.testing.expectApproxEqAbs(lo, actual.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(hi, actual.upper.?, 0.00005);
}
test "FEAT-freq-risk SAS seven binomial intervals and continuity correction" {
    const s = Binomial{ .success = 7, .total = 20 };
    const methods = [_]BinomialMethod{ .agresti_coull, .clopper_pearson, .jeffreys, .likelihood_ratio, .logit, .wald, .wilson };
    const limits = [_][2]f64{ .{ 0.2014, 0.5343 }, .{ 0.1773, 0.5580 }, .{ 0.1970, 0.5332 }, .{ 0.1931, 0.5329 }, .{ 0.1994, 0.5379 }, .{ 0.1746, 0.5254 }, .{ 0.2023, 0.5335 } };
    for (methods, limits) |m, ci| try expectLimits(try binomialLimits(s, 0.1, m, false), ci[0], ci[1]);
    try expectLimits(try binomialLimits(s, 0.1, .wald, true), 0.1496, 0.5504);
    try expectLimits(try binomialLimits(s, 0.1, .wilson, true), 0.1828, 0.5577);
}
test "FEAT-freq-risk SAS binomial zero boundary" {
    const s = Binomial{ .success = 0, .total = 10 };
    const methods = [_]BinomialMethod{ .agresti_coull, .clopper_pearson, .jeffreys, .likelihood_ratio, .wald, .wilson };
    const uppers = [_]f64{ 0.3209, 0.3085, 0.2172, 0.1748, 0, 0.2775 };
    for (methods, uppers) |m, upper| {
        try expectLimits(try binomialLimits(s, 0.05, m, false), 0, upper);
        const complement = try binomialLimits(.{ .success = 10, .total = 10 }, 0.05, m, false);
        try expectLimits(complement, 1 - upper, 1);
    }
    const logit = try binomialLimits(s, 0.05, .logit, false);
    try std.testing.expectEqual(@as(?f64, 0), logit.lower);
    try std.testing.expect(logit.upper == null);
}
test "FEAT-freq-risk SAS SENSPEC distinguishes row and column orientation" {
    const r = try sensitivity(.{ .cells = .{ 12, 8, 5, 25 } }, 0.05);
    const measures = [_]Estimate{ r.sensitivity, r.specificity, r.positive_predictive, r.negative_predictive };
    const expected = [_][4]f64{ .{ 0.7059, 0.1105, 0.4893, 0.9225 }, .{ 0.7576, 0.0746, 0.6114, 0.9038 }, .{ 0.6000, 0.1095, 0.3853, 0.8147 }, .{ 0.8333, 0.0680, 0.7000, 0.9667 } };
    for (measures, expected) |m, e| {
        try std.testing.expectApproxEqAbs(e[0], m.estimate.?, 0.00005);
        try std.testing.expectApproxEqAbs(e[1], m.se.?, 0.00005);
        try expectLimits(m.limits, e[2], e[3]);
    }
}
test "FEAT-freq-risk SAS difference interval methods and column reversal" {
    const table = Table2x2{ .cells = .{ 12, 8, 5, 25 } };
    const methods = [_]DifferenceMethod{ .agresti_caffo, .hauck_anderson, .miettinen_nurminen, .newcombe, .wald };
    const expected = [_][2]f64{ .{ 0.1574, 0.6494 }, .{ 0.1496, 0.7170 }, .{ 0.1632, 0.6530 }, .{ 0.1611, 0.6371 }, .{ 0.1806, 0.6861 } };
    for (methods, expected) |m, e| {
        try expectLimits(try differenceLimits(table, .first, 0.05, m, false, true), e[0], e[1]);
        try expectLimits(try differenceLimits(table, .second, 0.05, m, false, true), -e[1], -e[0]);
    }
    try expectLimits(try differenceLimits(table, .second, 0.05, .miettinen_nurminen, false, false), -0.6512, -0.1660);
    try expectLimits(try differenceLimits(table, .second, 0.05, .newcombe, true, true), -0.6588, -0.1318);
    try expectLimits(try differenceLimits(table, .second, 0.05, .wald, true, true), -0.7277, -0.1389);
}
test "FEAT-freq-risk validates finite counts and confidence levels" {
    try std.testing.expectError(error.ExecError, proportion(.{ .success = 2, .total = 1 }, 0.05, false));
    try std.testing.expectError(error.ExecError, proportion(.{ .success = 0, .total = 0 }, 0.05, false));
    try std.testing.expectError(error.ExecError, proportion(.{ .success = 1, .total = 2 }, 1, false));
    try std.testing.expectError(error.ExecError, sensitivity(.{ .cells = .{ -1, 2, 3, 4 } }, 0.05));
    try std.testing.expectError(error.ExecError, difference(.{ .cells = .{ 0, 0, 3, 4 } }, .first, 0.05, false));
    try std.testing.expectError(error.ExecError, difference(.{ .cells = .{ std.math.inf(f64), 2, 3, 4 } }, .first, 0.05, false));
}

pub const RatioKind = enum { odds_ratio, relative_risk };
pub const RatioMethod = enum { wald, wald_modified, score, likelihood_ratio };
pub const Ratio = struct { estimate: ?f64, log_se: ?f64, limits: Interval };
/// Signed score for FM tests / exact unconditional RR tail ordering. The
/// finite-sample bias factor applies to score CLs, not FM tests (pp204,209).
pub fn relativeRiskScore(table: Table2x2, column: Column, null_value: f64, bias_correct: bool) Error!f64 {
    const fit = try constrainedFit(table, column, .{ .relative_risk = null_value });
    const s = table.samples(column);
    const n = s[0].total + s[1].total;
    const v = (fit.p1 * (1 - fit.p1) / s[0].total + square(null_value) * fit.p2 * (1 - fit.p2) / s[1].total) * (if (bias_correct) n / (n - 1) else @as(f64, 1));
    const delta = s[0].proportion() - null_value * s[1].proportion();
    if (delta == 0 and v == 0) return 0;
    return delta / @sqrt(v);
}
pub fn ratioStatistic(table: Table2x2, column: Column, kind: RatioKind, value: f64, method: RatioMethod, bias_correct: bool) Error!f64 {
    if (method != .score and method != .likelihood_ratio) return error.ExecError;
    const fit = try constrainedFit(table, column, if (kind == .odds_ratio) .{ .odds_ratio = value } else .{ .relative_risk = value });
    const s = table.samples(column);
    if (method == .likelihood_ratio) return @max(0, deviance(s[0], fit.p1) + deviance(s[1], fit.p2));
    if (kind == .relative_risk) return square(try relativeRiskScore(table, column, value, bias_correct));
    const n = s[0].total + s[1].total;
    const delta = s[0].success - s[0].total * fit.p1;
    if (delta == 0) return 0;
    const inv_var = 1 / (s[0].total * fit.p1 * (1 - fit.p1)) + 1 / (s[1].total * fit.p2 * (1 - fit.p2));
    return square(delta) * inv_var / (if (bias_correct) n / (n - 1) else @as(f64, 1));
}
pub fn ratio(table: Table2x2, column: Column, kind: RatioKind, alpha: f64, method: RatioMethod, bias_correct: bool) Error!Ratio {
    try table.validate();
    const z = try critical(alpha);
    const s = table.samples(column);
    const add: f64 = if (method == .wald_modified) 0.5 else 0;
    const a = s[0].success + add;
    const b = s[0].total - s[0].success + add;
    const c = s[1].success + add;
    const d = s[1].total - s[1].success + add;
    const value = if (kind == .odds_ratio) (a / b) * (d / c) else (a / (s[0].total + add)) / (c / (s[1].total + add));
    const variance = if (kind == .odds_ratio) 1 / a + 1 / b + 1 / c + 1 / d else 1 / a - 1 / (s[0].total + add) + 1 / c - 1 / (s[1].total + add);
    const log_se: ?f64 = if (std.math.isFinite(variance) and variance >= 0) @sqrt(variance) else null;
    var result = Ratio{ .estimate = if (std.math.isNan(value)) null else value, .log_se = log_se, .limits = .{} };
    if (method == .wald or method == .wald_modified) {
        if (value > 0 and std.math.isFinite(value) and log_se != null) result.limits = .{ .lower = value * @exp(-z * log_se.?), .upper = value * @exp(z * log_se.?) };
        return result;
    }
    if (result.estimate == null) return result;
    // Search in log space; never substitute a finite sentinel for an
    // unbounded CI. Zero/infinite estimates retain their boundary endpoint.
    const center = if (value == 0) @as(f64, -36) else if (std.math.isInf(value)) @as(f64, 36) else @log(value);
    inline for (.{ false, true }) |upper| {
        if ((!upper and value == 0) or (upper and std.math.isInf(value))) {
            if (upper) result.limits.upper = std.math.inf(f64) else result.limits.lower = 0;
        } else {
            var inside = center;
            var outside = center;
            var step: f64 = 1;
            var bracketed = false;
            for (0..10) |_| {
                outside = center + (if (upper) step else -step);
                const statistic = try ratioStatistic(table, column, kind, @exp(outside), method, bias_correct);
                if (statistic > z * z) {
                    bracketed = true;
                    break;
                }
                step *= 2;
            }
            if (!bracketed) return error.ExecError;
            for (0..90) |_| {
                const mid = (inside + outside) / 2;
                if (try ratioStatistic(table, column, kind, @exp(mid), method, bias_correct) > z * z) outside = mid else inside = mid;
            }
            const limit = @exp((inside + outside) / 2);
            if (upper) result.limits.upper = limit else result.limits.lower = limit;
        }
    }
    return result;
}

test "FEAT-freq-risk SAS OR and RR four asymptotic CI methods" {
    // kernels.sas/kernels.txt, same independent sasrun command above;
    // SAS/STAT pp199-205. Modified RR row totals add .5, not 1.
    const table = Table2x2{ .cells = .{ 12, 8, 5, 25 } };
    const methods = [_]RatioMethod{ .wald, .wald_modified, .score, .likelihood_ratio };
    const odds = [_][2]f64{ .{ 2.0189, 27.8616 }, .{ 1.9182, 24.2350 }, .{ 2.0479, 27.3817 }, .{ 2.1287, 30.3010 } };
    const risk = [_][2]f64{ .{ 1.4984, 8.6491 }, .{ 1.4713, 7.7710 }, .{ 1.5667, 8.7378 }, .{ 1.6179, 9.9526 } };
    for (methods, odds, risk) |m, o, r| {
        try expectLimits((try ratio(table, .first, .odds_ratio, 0.05, m, true)).limits, o[0], o[1]);
        try expectLimits((try ratio(table, .first, .relative_risk, 0.05, m, true)).limits, r[0], r[1]);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 3.3814), (try ratio(table, .first, .relative_risk, 0.05, .wald_modified, true)).estimate.?, 0.00005);
    try expectLimits((try ratio(table, .second, .relative_risk, 0.05, .score, false)).limits, 0.2583, 0.7753);
    try expectLimits((try ratio(table, .second, .relative_risk, 0.05, .likelihood_ratio, false)).limits, 0.2450, 0.7747);
    try expectLimits((try ratio(table, .second, .relative_risk, 0.05, .wald_modified, false)).limits, 0.2896, 0.8492);
}

test "FEAT-freq-risk SAS zero cell OR RR intervals" {
    // tests.sas/tests.txt, command in freq_risk_inference.zig. Wald limits
    // are missing but the estimate is zero; score/LR have a zero lower bound.
    const table = Table2x2{ .cells = .{ 0, 10, 5, 5 } };
    const methods = [_]RatioMethod{ .wald_modified, .score, .likelihood_ratio };
    const odds = [_][2]f64{ .{ 0.0022, 1.0293 }, .{ 0, 0.5238 }, .{ 0, 0.2903 } };
    const risks = [_][2]f64{ .{ 0.0057, 1.4447 }, .{ 0, 0.6412 }, .{ 0, 0.3949 } };
    for (methods, odds, risks) |m, o, r| {
        try expectLimits((try ratio(table, .first, .odds_ratio, 0.05, m, true)).limits, o[0], o[1]);
        try expectLimits((try ratio(table, .first, .relative_risk, 0.05, m, true)).limits, r[0], r[1]);
    }
    const w = try ratio(table, .first, .relative_risk, 0.05, .wald, true);
    try std.testing.expectEqual(@as(?f64, 0), w.estimate);
    try std.testing.expect(w.limits.lower == null and w.limits.upper == null);
}
