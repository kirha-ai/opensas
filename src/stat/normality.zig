//! Default UNIVARIATE OUTTABLE normality fields, independent of PROC parsing.
//! SAS Statistical Procedures pp.444–447,461: Shapiro–Wilk through n=2000,
//! then fitted-normal Kolmogorov–Smirnov. See docs/findings/univ-normality.md.
const std = @import("std");
const functions = @import("../functions.zig");

pub const Method = enum { shapiro_wilk, kolmogorov_smirnov };
pub const Result = struct {
    statistic: f64,
    /// SAS stored probability: KS is bounded to [0.01,0.15], not an uncensored
    /// tail probability. A consumer must preserve that convention.
    p: f64,
    method: Method,
};

/// Input is finite, sorted ascending, and already excludes missing values.
/// FREQ expansion belongs to the caller; WEIGHT callers must not request these
/// fields. Does not mutate input. null means SAS's undefined/missing result.
pub fn compute(allocator: std.mem.Allocator, sorted_nonmissing: []const f64) error{OutOfMemory}!?Result {
    const x = sorted_nonmissing;
    for (x, 0..) |v, i| {
        std.debug.assert(std.math.isFinite(v));
        if (i > 0) std.debug.assert(x[i - 1] <= v);
    }
    if (x.len < 2 or x[0] == x[x.len - 1]) return null;
    // This midpoint/radius avoids overflow across opposite extreme endpoints.
    // Compute centered, scaled moments so neither huge nor tiny units overflow
    // or underflow the corrected sum of squares.
    const center = x[0] / 2 + x[x.len - 1] / 2;
    const radius = @max(@abs(x[0] - center), @abs(x[x.len - 1] - center));
    const nf: f64 = @floatFromInt(x.len);
    var mean_sum: Sum = .{};
    for (x) |v| mean_sum.add((v - center) / radius);
    const mean = mean_sum.value / nf;
    var css_sum: Sum = .{};
    for (x) |v| {
        const d = (v - center) / radius - mean;
        css_sum.add(d * d);
    }
    const css = css_sum.value;
    if (!(css > 0)) return null;
    // SAS suppresses numerically near-constant samples as well as exact
    // constants. The retained scale/translation probes identify its relative
    // population-variance cutoff at 500 machine epsilons. Evaluate the ratio
    // without squaring large original values. At the cutoff itself SAS's
    // accumulation order can change the last-bit classification.
    const original_mean = center + radius * mean;
    if (original_mean != 0) {
        const relative_radius = radius / @abs(original_mean);
        if (relative_radius < 1 and (css / nf) * relative_radius * relative_radius <= 500 * std.math.floatEps(f64)) return null;
    }
    if (x.len > 2000) {
        const sd = @sqrt(css / (nf - 1));
        var d: f64 = 0;
        for (x, 0..) |v, i| {
            const z = ((v - center) / radius - mean) / sd;
            const f = functions.distCdf(.normal, z, &.{}).?;
            const before: f64 = @floatFromInt(i);
            d = @max(d, @max(f - before / nf, (before + 1) / nf - f));
        }
        return .{ .statistic = d, .p = fittedNormalProbability(d, nf), .method = .kolmogorov_smirnov };
    }
    // SAS OUTTABLE returns (1,1) for two distinct observations, although the
    // published Shapiro–Wilk distribution starts at three. Oracle pinned.
    if (x.len == 2) return .{ .statistic = 1, .p = 1, .method = .shapiro_wilk };
    const a = try coefficients(allocator, x.len);
    defer allocator.free(a);
    var numerator: Sum = .{};
    var norm: Sum = .{};
    for (a, 0..) |ai, i| {
        const difference = (x[x.len - 1 - i] - center) / radius - (x[i] - center) / radius;
        numerator.add(ai * difference);
        norm.add(2 * ai * ai);
    }
    // Form 1-W as a product to retain precision near perfect normal scores.
    const den = @sqrt(norm.value * css);
    const b = numerator.value;
    const one_minus_w = std.math.clamp(((den - b) / den) * ((den + b) / den), 0, 1);
    const w = 1 - one_minus_w;
    return .{ .statistic = w, .p = shapiroProbability(w, one_minus_w, nf), .method = .shapiro_wilk };
}

const Sum = struct {
    value: f64 = 0,
    correction: f64 = 0,
    fn add(self: *Sum, v: f64) void {
        const y = v - self.correction;
        const t = self.value + y;
        self.correction = (t - self.value) - y;
        self.value = t;
    }
};
fn polynomial(c: []const f64, x: f64) f64 {
    var y: f64 = 0;
    var i = c.len;
    while (i > 0) {
        i -= 1;
        y = y * x + c[i];
    }
    return y;
}
/// Royston (1992), pp.117–119. In particular the second extreme coefficient
/// uses -3.582663, NOT the later AS R94 transcription's -3.582633. SAS matches
/// the 1992 value; replacing it changes small-sample W and p observably.
fn coefficients(a: std.mem.Allocator, n: usize) ![]f64 {
    const half = n / 2;
    const weights = try a.alloc(f64, half);
    if (n == 3) {
        weights[0] = @sqrt(0.5);
        return weights;
    }
    const nf: f64 = @floatFromInt(n);
    var ss: Sum = .{};
    for (weights, 0..) |*w, i| {
        const rank: f64 = @floatFromInt(i + 1);
        w.* = functions.distQuantile(.normal, (rank - 0.375) / (nf + 0.25), &.{}).?;
        ss.add(2 * w.* * w.*);
    }
    const root = @sqrt(ss.value);
    const t = 1 / @sqrt(nf);
    const first = -weights[0] / root + polynomial(&.{ 0, 0.221157, -0.147981, -2.071190, 4.434685, -2.706056 }, t);
    var removed = 2 * weights[0] * weights[0];
    var remaining = 1 - 2 * first * first;
    weights[0] = first;
    var start: usize = 1;
    if (n > 5) {
        const second = -weights[1] / root + polynomial(&.{ 0, 0.042981, -0.293762, -1.752461, 5.682633, -3.582663 }, t);
        removed += 2 * weights[1] * weights[1];
        remaining -= 2 * second * second;
        weights[1] = second;
        start = 2;
    }
    const rescale = @sqrt((ss.value - removed) / remaining);
    for (weights[start..]) |*w| w.* = -w.* / rescale;
    return weights;
}
fn shapiroProbability(w: f64, one_minus_w: f64, n: f64) f64 {
    if (n == 3) return std.math.clamp((6.0 / std.math.pi) * (std.math.asin(@sqrt(w)) - std.math.pi / 3.0), 0, 1);
    if (one_minus_w <= 0) return 1;
    var y = @log(one_minus_w);
    var mu: f64 = undefined;
    var sigma: f64 = undefined;
    if (n <= 11) {
        const gamma = -2.273 + 0.459 * n;
        if (y >= gamma) return 0;
        y = -@log(gamma - y);
        mu = polynomial(&.{ 0.5440, -0.39978, 0.025054, -0.0006714 }, n);
        sigma = @exp(polynomial(&.{ 1.3822, -0.77857, 0.062767, -0.0020322 }, n));
    } else {
        const ln = @log(n);
        mu = polynomial(&.{ -1.5861, -0.31082, -0.083751, 0.0038915 }, ln);
        sigma = @exp(polynomial(&.{ -0.4803, -0.082676, 0.0030302 }, ln));
    }
    // SAS stores zero once the normal CDF rounds to one; preserve OUTTABLE's
    // stored convention instead of substituting an uncensored survival tail.
    return 1 - functions.distCdf(.normal, (y - mu) / sigma, &.{}).?;
}
/// Stephens fitted-normal (mean AND variance estimated) modification/table.
/// SAS OUTTABLE stores the bounding probabilities 0.15 and 0.01 outside the
/// table, and linearly interpolates within it. The 0.025 critical value is 0.955.
fn fittedNormalProbability(d: f64, n: f64) f64 {
    const root = @sqrt(n);
    const modified = d * (root - 0.01 + 0.85 / root);
    const critical = [_]f64{ 0.775, 0.819, 0.895, 0.955, 1.035 };
    const probabilities = [_]f64{ 0.15, 0.10, 0.05, 0.025, 0.01 };
    if (modified <= critical[0]) return probabilities[0];
    for (1..critical.len) |i| {
        if (modified <= critical[i]) {
            const fraction = (modified - critical[i - 1]) / (critical[i] - critical[i - 1]);
            return probabilities[i - 1] + fraction * (probabilities[i] - probabilities[i - 1]);
        }
    }
    return probabilities[probabilities.len - 1];
}

test "normality exact n=3 and SAS n=2 convention" {
    const a = std.testing.allocator;
    const two = (try compute(a, &.{ 1, 2 })).?;
    try std.testing.expectEqual(@as(f64, 1), two.statistic);
    try std.testing.expectEqual(@as(f64, 1), two.p);
    const three = (try compute(a, &.{ 1, 2, 3 })).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1), three.statistic, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), three.p, 1e-7);
    const ties = (try compute(a, &.{ 0, 0, 1 })).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), ties.statistic, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0), ties.p, 3e-12);
}
test "normality Royston 1992 small sample uniform oracle" {
    const a = std.testing.allocator;
    const ns = [_]usize{ 4, 8, 11, 12, 2000 };
    const ws = [_]f64{ 0.99291200679915, 0.97485827830837, 0.96839129408103, 0.96689637488075, 0.95486626118544 };
    const ps = [_]f64{ 0.97187705761393, 0.93316533637933, 0.86984247309256, 0.87573158321121, 0 };
    for (ns, ws, ps) |n, w, p| {
        const x = try a.alloc(f64, n);
        defer a.free(x);
        for (x, 0..) |*v, i| v.* = @floatFromInt(i + 1);
        const got = (try compute(a, x)).?;
        try std.testing.expectEqual(Method.shapiro_wilk, got.method);
        try std.testing.expectApproxEqAbs(w, got.statistic, 1e-10);
        try std.testing.expectApproxEqAbs(p, got.p, 1e-9);
    }
}
test "normality KS fitted-normal table and stored bounds" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.10823681941023), fittedNormalProbability(0.01814313036837, 2001), 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04776392936703), fittedNormalProbability(0.02012372759334, 2001), 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01864761026227), fittedNormalProbability(0.02210204219273, 2001), 1e-10);
    try std.testing.expectEqual(@as(f64, 0.15), fittedNormalProbability(0.00042345452319, 2001));
    try std.testing.expectEqual(@as(f64, 0.01), fittedNormalProbability(0.05739853073458, 2001));
}

const Family = enum { constant, outlier, quantile, scale, skew, ties, translate, uniform };
const Oracle = struct { family: Family, n: usize, w: ?f64, p: ?f64 };
fn sample(a: std.mem.Allocator, family: Family, n: usize) ![]f64 {
    const x = try a.alloc(f64, n);
    const nf: f64 = @floatFromInt(n);
    for (x, 0..) |*v, j| {
        const i: f64 = @floatFromInt(j + 1);
        v.* = switch (family) {
            .constant => 7,
            .uniform => i,
            .outlier => if (j + 1 == n) 1e6 else i,
            .quantile => functions.distQuantile(.normal, (i - 0.375) / (nf + 0.25), &.{}).?,
            .scale => i * 1e100,
            .skew => @log(i) + @sin(i),
            .ties => @floor(i / 3),
            .translate => 1e12 + i / 1024,
        };
    }
    std.mem.sort(f64, x, {}, std.sort.asc(f64));
    return x;
}
test "normality full SAS OUTTABLE oracle families and method boundary" {
    const a = std.testing.allocator;
    const cases = [_]Oracle{
        .{ .family = .constant, .n = 1, .w = null, .p = null },
        .{ .family = .constant, .n = 2, .w = null, .p = null },
        .{ .family = .constant, .n = 2001, .w = null, .p = null },
        .{ .family = .constant, .n = 3, .w = null, .p = null },
        .{ .family = .constant, .n = 4, .w = null, .p = null },
        .{ .family = .constant, .n = 8, .w = null, .p = null },
        .{ .family = .outlier, .n = 11, .w = 0.34500012633519, .p = 2.2439353042358E-8 },
        .{ .family = .outlier, .n = 12, .w = 0.3269376578006, .p = 1.2074583105037E-6 },
        .{ .family = .outlier, .n = 2000, .w = 0.01136095132154, .p = 0 },
        .{ .family = .outlier, .n = 2001, .w = 0.49056773071353, .p = 0.01 },
        .{ .family = .outlier, .n = 3, .w = 0.7500007500017, .p = 1.6539912837457E-6 },
        .{ .family = .outlier, .n = 4, .w = 0.62977782931332, .p = 0.00124079937968 },
        .{ .family = .outlier, .n = 8, .w = 0.41840394914607, .p = 1.0473948728328E-6 },
        .{ .family = .quantile, .n = 11, .w = 0.99653551571843, .p = 0.99998193959262 },
        .{ .family = .quantile, .n = 12, .w = 0.99658682893489, .p = 0.99999998802778 },
        .{ .family = .quantile, .n = 2000, .w = 0.99995091384286, .p = 0.99999999999976 },
        .{ .family = .quantile, .n = 2001, .w = 0.00042345452319, .p = 0.15 },
        .{ .family = .quantile, .n = 3, .w = 1, .p = 1 },
        .{ .family = .quantile, .n = 4, .w = 0.9983649336838, .p = 0.9949562187787 },
        .{ .family = .quantile, .n = 8, .w = 0.99656042911162, .p = 0.99986495699643 },
        .{ .family = .scale, .n = 8, .w = 0.97485827830837, .p = 0.93316533637933 },
        .{ .family = .skew, .n = 11, .w = 0.92133372918538, .p = 0.32990551092573 },
        .{ .family = .skew, .n = 12, .w = 0.94284540091487, .p = 0.53578954657815 },
        .{ .family = .skew, .n = 2000, .w = 0.94671908997977, .p = 0 },
        .{ .family = .skew, .n = 2001, .w = 0.06006284818515, .p = 0.01 },
        .{ .family = .skew, .n = 3, .w = 0.99927309352131, .p = 0.94850165447808 },
        .{ .family = .skew, .n = 4, .w = 0.96740890424409, .p = 0.82537808264437 },
        .{ .family = .skew, .n = 8, .w = 0.88720635952787, .p = 0.22038016747652 },
        .{ .family = .ties, .n = 11, .w = 0.88902758742146, .p = 0.13522941600455 },
        .{ .family = .ties, .n = 12, .w = 0.93610752087497, .p = 0.44934894935759 },
        .{ .family = .ties, .n = 2000, .w = 0.95486285321659, .p = 0 },
        .{ .family = .ties, .n = 2001, .w = 0.05789776247977, .p = 0.01 },
        .{ .family = .ties, .n = 3, .w = 0.75000000000096, .p = 2.1169771959821E-12 },
        .{ .family = .ties, .n = 4, .w = 0.72863414817241, .p = 0.02385679440154 },
        .{ .family = .ties, .n = 8, .w = 0.83521350693678, .p = 0.06723576241538 },
        .{ .family = .translate, .n = 8, .w = null, .p = null },
        .{ .family = .uniform, .n = 11, .w = 0.96839129408103, .p = 0.86984247309256 },
        .{ .family = .uniform, .n = 12, .w = 0.96689637488075, .p = 0.87573158321121 },
        .{ .family = .uniform, .n = 2000, .w = 0.95486626118544, .p = 0 },
        .{ .family = .uniform, .n = 2001, .w = 0.05739853073458, .p = 0.01 },
        .{ .family = .uniform, .n = 3, .w = 1, .p = 1 },
        .{ .family = .uniform, .n = 4, .w = 0.99291200679915, .p = 0.97187705761393 },
        .{ .family = .uniform, .n = 8, .w = 0.97485827830837, .p = 0.93316533637933 },
    };
    for (cases) |c| {
        const x = try sample(a, c.family, c.n);
        defer a.free(x);
        const actual = try compute(a, x);
        if (c.w) |w| {
            const got = actual orelse {
                std.debug.print("missing normality: {s} {d}\n", .{ @tagName(c.family), c.n });
                return error.TestUnexpectedResult;
            };
            try std.testing.expectEqual(if (c.n > 2000) Method.kolmogorov_smirnov else Method.shapiro_wilk, got.method);
            try std.testing.expectApproxEqAbs(w, got.statistic, 1e-10);
            try std.testing.expectApproxEqAbs(c.p.?, got.p, 1e-8);
        } else try std.testing.expectEqual(@as(?Result, null), actual);
    }
}
test "normality degenerate, near-constant, translated and scaled inputs" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(?Result, null), try compute(a, &.{}));
    try std.testing.expectEqual(@as(?Result, null), try compute(a, &.{1}));
    try std.testing.expectEqual(@as(?Result, null), try compute(a, &.{ 1, 1 }));
    const plain = try sample(a, .uniform, 8);
    defer a.free(plain);
    const baseline = (try compute(a, plain)).?;
    var tiny: [8]f64 = undefined;
    var translated: [8]f64 = undefined;
    var near_constant: [8]f64 = undefined;
    for (plain, 0..) |v, i| {
        tiny[i] = v * 1e-100;
        translated[i] = 10000 + v * 0.01;
        near_constant[i] = 10000 + v * 0.001;
    }
    const t = (try compute(a, &tiny)).?;
    try std.testing.expectApproxEqAbs(baseline.statistic, t.statistic, 1e-12);
    try std.testing.expectApproxEqAbs(baseline.p, t.p, 1e-12);
    const tr = (try compute(a, &translated)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.97485827827918), tr.statistic, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.93316533618736), tr.p, 1e-8);
    try std.testing.expectEqual(@as(?Result, null), try compute(a, &near_constant));
    // Oracle precision sweep: test the clearly defined sides, not the
    // last-bit boundary whose classification depends on summation order.
    for ([_]usize{ 2, 8, 12, 2000, 2001 }) |n| {
        const x = try a.alloc(f64, n);
        defer a.free(x);
        for ([_]f64{ 0.99, 1.01 }) |factor| {
            for (x, 0..) |*v, i| v.* = 1 + (if (i < n / 2) @as(f64, -1) else 1) * @sqrt(500 * std.math.floatEps(f64)) * factor;
            const got = try compute(a, x);
            try std.testing.expectEqual(factor > 1, got != null);
        }
    }
}

test "normality fitted-normal KS full statistic and every probability interval" {
    const a = std.testing.allocator;
    const cases = [_]struct { n: usize, shape: f64, d: f64, p: f64 }{
        .{ .n = 2001, .shape = 0.025, .d = 0.01020251204568, .p = 0.15 },
        .{ .n = 2001, .shape = 0.03, .d = 0.01218990672147, .p = 0.15 },
        .{ .n = 2001, .shape = 0.035, .d = 0.01417597718525, .p = 0.15 },
        .{ .n = 2001, .shape = 0.04, .d = 0.01616046306645, .p = 0.15 },
        .{ .n = 2001, .shape = 0.043, .d = 0.01735029874996, .p = 0.14854648739026 },
        .{ .n = 2001, .shape = 0.045, .d = 0.01814313036837, .p = 0.10823681941023 },
        .{ .n = 2001, .shape = 0.0475, .d = 0.0191336979268, .p = 0.07561110705591 },
        .{ .n = 2001, .shape = 0.05, .d = 0.02012372759334, .p = 0.04776392936703 },
        .{ .n = 2001, .shape = 0.052, .d = 0.02091533630483, .p = 0.03300651558229 },
        .{ .n = 2001, .shape = 0.055, .d = 0.02210204219273, .p = 0.01864761026227 },
        .{ .n = 2001, .shape = 0.057, .d = 0.02289267046756, .p = 0.01201499898035 },
        .{ .n = 2001, .shape = 0.06, .d = 0.02407782387224, .p = 0.01 },
        .{ .n = 5000, .shape = 0.025, .d = 0.01006127371848, .p = 0.15 },
        .{ .n = 5000, .shape = 0.03, .d = 0.01205082496601, .p = 0.07819318570585 },
        .{ .n = 5000, .shape = 0.035, .d = 0.01403898641543, .p = 0.0179247588002 },
        .{ .n = 5000, .shape = 0.04, .d = 0.01602552014611, .p = 0.01 },
        .{ .n = 5000, .shape = 0.043, .d = 0.01721656079158, .p = 0.01 },
        .{ .n = 5000, .shape = 0.045, .d = 0.01801019130027, .p = 0.01 },
        .{ .n = 5000, .shape = 0.0475, .d = 0.01900175490338, .p = 0.01 },
        .{ .n = 5000, .shape = 0.05, .d = 0.01999276722657, .p = 0.01 },
        .{ .n = 5000, .shape = 0.052, .d = 0.02078515914505, .p = 0.01 },
        .{ .n = 5000, .shape = 0.055, .d = 0.02197302080502, .p = 0.01 },
        .{ .n = 5000, .shape = 0.057, .d = 0.02276442113461, .p = 0.01 },
        .{ .n = 5000, .shape = 0.06, .d = 0.02395072434455, .p = 0.01 },
    };
    for (cases) |c| {
        const x = try sample(a, .quantile, c.n);
        defer a.free(x);
        for (x) |*v| {
            const z = v.*;
            v.* = z + c.shape * (z * z - 1);
        }
        std.mem.sort(f64, x, {}, std.sort.asc(f64));
        const before = try a.dupe(f64, x);
        defer a.free(before);
        const got = (try compute(a, x)).?;
        try std.testing.expectEqual(Method.kolmogorov_smirnov, got.method);
        try std.testing.expectApproxEqAbs(c.d, got.statistic, 1e-10);
        try std.testing.expectApproxEqAbs(c.p, got.p, 1e-8);
        try std.testing.expectEqualSlices(f64, before, x);
    }
}
