//! NPAR1WAY default computation over selected, frequency-expanded observations.
//! SAS/STAT 15.4 physical PDF pp.7206-7215, 7236-7249. The caller owns
//! input selection, class ordering, BY groups and diagnostics. Scores for ties
//! are averages of the individual ordinal scores, NOT transforms of midranks.
const std = @import("std");
const ranks = @import("ranks.zig");
const exact = @import("npar1way_exact.zig");
const math = @import("../functions.zig");
const A = std.mem.Allocator;
pub const Options = struct {
    anova: bool = true,
    wilcoxon: bool = true,
    median: bool = true,
    vw: bool = true,
    savage: bool = true,
    edf: bool = true,
    ab: bool = false,
    st: bool = false,
    klotz: bool = false,
    mood: bool = false,
    conover: bool = false,
    data: bool = false,
    exact_wilcoxon: bool = false,
    exact_scores: [10]bool = @splat(false),
    continuity: bool = true,
};
pub const Kind = enum { wilcoxon, median, vw, savage, ab, st, klotz, mood, conover, data };
pub const GroupScore = struct { sum: f64, expected: f64, stddev: f64, mean: f64 };
pub const TwoSample = struct {
    selected: usize,
    statistic: f64,
    z: ?f64,
    p_one: ?f64,
    p_two: ?f64,
    p_t_one: ?f64 = null,
    p_t_two: ?f64 = null,
    exact: ?ranks.Exact = null,
};
pub const ScoreAnalysis = struct {
    kind: Kind,
    values: []f64,
    groups: []GroupScore,
    chi_square: ?f64,
    df: usize,
    p: ?f64,
    two_sample: ?TwoSample,
    has_ties: bool = false,
    conditional: ?exact.Result = null,
};
pub const Anova = struct {
    among_ss: f64,
    within_ss: f64,
    among_ms: f64,
    within_ms: f64,
    among_df: usize,
    within_df: usize,
    f: ?f64,
    p: ?f64,
};
pub const Edf = struct {
    at_max: []f64,
    deviations: []f64,
    pooled_at_max: f64,
    /// Zero-based first input observation attaining the maximum's value.
    max_index: usize,
    max_value: f64,
    ks: f64,
    ksa: f64,
    cm: f64,
    cma: f64,
    cm_components: []f64,
    d: ?f64,
    d_plus: ?f64 = null,
    d_minus: ?f64 = null,
    d_plus_p: ?f64 = null,
    d_minus_p: ?f64 = null,
    ks_p: ?f64,
    kuiper: ?f64,
    kuiper_scaled: ?f64,
    kuiper_p: ?f64,
    kuiper_deviations: [2]f64,
};
pub const Result = struct {
    n: usize,
    counts: []usize,
    means: []f64,
    has_ties: bool,
    anova: ?Anova,
    scores: []ScoreAnalysis,
    edf: ?Edf,
};
fn num(n: usize) f64 {
    return @floatFromInt(n);
}
fn square(x: f64) f64 {
    return x * x;
}

/// All arrays use the caller's arena. Class indices must be contiguous and
/// nonempty; nonfinite responses are rejected instead of silently filtered.
pub fn compute(a: A, values: []const f64, groups: []const usize, group_count: usize, options: Options) !Result {
    if (values.len != groups.len or group_count < 2 or values.len < group_count) return error.InvalidInput;
    const counts = try a.alloc(usize, group_count);
    const means = try a.alloc(f64, group_count);
    @memset(counts, 0);
    @memset(means, 0);
    for (values, groups) |v, g| {
        if (!std.math.isFinite(v) or g >= group_count) return error.InvalidInput;
        counts[g] += 1;
        means[g] += v;
    }
    for (counts, means) |count, *mean| {
        if (count == 0) return error.InvalidInput;
        mean.* /= num(count);
    }
    const ranked = try ranks.rank(a, values, false, .mean);
    var out = Result{ .n = values.len, .counts = counts, .means = means, .has_ties = ranked.tie_correction > 0, .anova = null, .scores = &.{}, .edf = null };
    if (options.anova) {
        var grand: f64 = 0;
        for (counts, means) |count, mean| grand += num(count) * mean / num(values.len);
        var among: f64 = 0;
        var within: f64 = 0;
        for (counts, means) |count, mean| among += num(count) * square(mean - grand);
        for (values, groups) |v, g| within += square(v - means[g]);
        const df1 = group_count - 1;
        const df2 = values.len - group_count;
        const ms1 = among / num(df1);
        const ms2 = if (df2 > 0) within / num(df2) else std.math.nan(f64);
        const f: ?f64 = if (ms2 > 0) ms1 / ms2 else null;
        out.anova = .{ .among_ss = among, .within_ss = within, .among_ms = ms1, .within_ms = ms2, .among_df = df1, .within_df = df2, .f = f, .p = if (f) |v| math.betaI(num(df2) / (num(df2) + num(df1) * v), num(df2) / 2, num(df1) / 2) else null };
    }
    var analyses: std.ArrayList(ScoreAnalysis) = .empty;
    for ([_]Kind{ .wilcoxon, .median, .vw, .savage, .ab, .st, .klotz, .mood, .conover, .data }, [_]bool{ options.wilcoxon, options.median, options.vw, options.savage, options.ab, options.st, options.klotz, options.mood, options.conover, options.data }) |kind, requested| {
        if (requested or options.exact_scores[@intFromEnum(kind)] or (kind == .wilcoxon and options.exact_wilcoxon)) try analyses.append(a, try scores(a, values, groups, counts, ranked, kind, options));
    }
    out.scores = try analyses.toOwnedSlice(a);
    if (options.edf) out.edf = try edf(a, values, groups, counts, ranked);
    return out;
}

fn scores(a: A, values: []const f64, groups: []const usize, counts: []const usize, ranked: ranks.Ranked, kind: Kind, options: Options) !ScoreAnalysis {
    const n = values.len;
    const nf = num(n);
    const transformed = try a.alloc(f64, n);
    var score_ties = ranked.tie_correction > 0;
    if (kind == .data) {
        @memcpy(transformed, values);
    } else if (kind == .conover) {
        const means = try a.alloc(f64, counts.len);
        @memset(means, 0);
        for (values, groups) |v, g| means[g] += v / num(counts[g]);
        const deviations = try a.alloc(f64, n);
        for (values, groups, deviations) |v, g, *d| {
            d.* = @abs(v - means[g]);
            if (!std.math.isFinite(d.*)) return error.InvalidInput;
        }
        const deviation_ranks = try ranks.rank(a, deviations, false, .mean);
        score_ties = deviation_ranks.tie_correction > 0;
        // Conover specifically squares the AVERAGED rank of tied deviations.
        for (deviation_ranks.values, transformed) |r, *v| v.* = square(r);
    } else {
        const ordinal = try a.alloc(f64, n);
        var harmonic: f64 = 0;
        for (ordinal, 0..) |*v, i| {
            const r = num(i + 1);
            harmonic += 1 / num(n - i);
            v.* = switch (kind) {
                .wilcoxon => r,
                .median => if (r > (nf + 1) / 2) 1 else 0,
                .vw => math.distQuantile(.normal, r / (nf + 1), &.{}).?,
                .savage => harmonic - 1,
                .ab => @min(r, nf + 1 - r),
                .mood => square(r - (nf + 1) / 2),
                .klotz => square(math.distQuantile(.normal, r / (nf + 1), &.{}).?),
                .st => 0,
                .conover, .data => unreachable,
            };
        }
        if (kind == .st) {
            var lo: usize = 0;
            var hi: usize = n - 1;
            for (0..n) |j| {
                if (j % 4 == 0 or j % 4 == 3) {
                    ordinal[lo] = num(j + 1);
                    lo += 1;
                } else {
                    ordinal[hi] = num(j + 1);
                    hi -|= 1;
                }
            }
        }
        for (ranked.groups) |tie| {
            var total: f64 = 0;
            for (ordinal[tie.first - 1 ..][0..tie.count]) |v| total += v;
            const average = if (ranked.groups.len == 1 and (kind == .vw or kind == .savage)) @as(f64, 0) else total / num(tie.count);
            for (values, transformed) |v, *score| if (v == tie.value) {
                score.* = average;
            };
        }
    }
    var total: f64 = 0;
    for (transformed) |score| total += score;
    if (!std.math.isFinite(total)) return error.InvalidInput;
    // Normal and Savage score populations have exact zero mean. Enforce the
    // mathematical identity rather than letting summation noise choose a tail.
    const mean: f64 = if (kind == .vw or kind == .savage) 0 else total / nf;
    var ss: f64 = 0;
    for (transformed) |score| ss += square(score - mean);
    if (!std.math.isFinite(ss)) return error.InvalidInput;
    const summary = try a.alloc(GroupScore, counts.len);
    for (summary, counts) |*g, count| g.* = .{ .sum = 0, .expected = num(count) * mean, .stddev = @sqrt(num(count) * (nf - num(count)) * ss / (nf * (nf - 1))), .mean = 0 };
    for (transformed, groups) |v, g| summary[g].sum += v;
    var between: f64 = 0;
    for (summary, counts) |*g, count| {
        g.mean = g.sum / num(count);
        between += square(g.sum - g.expected) / num(count);
    }
    const chi: ?f64 = if (ss > 0) between * (nf - 1) / ss else null;
    var result = ScoreAnalysis{ .kind = kind, .values = transformed, .groups = summary, .chi_square = chi, .df = counts.len - 1, .p = if (chi) |v| 1 - math.distCdf(.chisq, v, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = num(counts.len - 1) } }).? else null, .two_sample = null, .has_ties = score_ties };
    if (counts.len == 2) {
        const chosen: usize = if (counts[0] <= counts[1]) 0 else 1;
        const selected = try a.alloc(bool, n);
        for (groups, selected) |g, *p| p.* = g == chosen;
        const linear = try ranks.linearRank(transformed, selected, options.continuity and (kind == .wilcoxon or kind == .st));
        var test_result = TwoSample{ .selected = chosen, .statistic = summary[chosen].sum, .z = linear.z, .p_one = null, .p_two = null };
        if (linear.z) |z| {
            const tail = math.distCdf(.normal, -@abs(z), &.{}).?;
            test_result.p_one = tail;
            test_result.p_two = 2 * tail;
            if (kind == .wilcoxon) {
                // SAS 9.4 uses t(N-1) on the same corrected Z. Independent
                // reference: GW DOOR technical doc (2025):
                // https://extapps.bsc.gwu.edu/shinypub/arlg/DOOR_Shiny/tech_doc_20250505.pdf
                const t_tail = math.distCdf(.t, -@abs(z), &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = nf - 1 } }).?;
                test_result.p_t_one = t_tail;
                test_result.p_t_two = 2 * t_tail;
            }
        }

        result.two_sample = test_result;
    }
    if (options.exact_scores[@intFromEnum(kind)] or (kind == .wilcoxon and options.exact_wilcoxon)) {
        if (kind == .wilcoxon and counts.len == 2) {
            const selected = try a.alloc(bool, n);
            const chosen: usize = if (counts[0] <= counts[1]) 0 else 1;
            for (groups, selected) |g, *p| p.* = g == chosen;
            const distribution = try ranks.exactRankSum(a, ranked.values, selected);
            result.conditional = .{ .right = summary[chosen].sum > summary[chosen].expected, .allocations = distribution.allocations, .lower_count = distribution.lower_count, .upper_count = distribution.upper_count, .two_sided_count = distribution.two_sided_count, .point_count = distribution.lower_count + distribution.upper_count - distribution.allocations };
            result.two_sample.?.exact = distribution;
        } else {
            if (counts.len > 2 and result.chi_square == null) return error.DegenerateExact;
            const weights = try exact.scoreWeights(a, values, kind, transformed);
            result.conditional = try exact.testScores(a, weights, groups, counts);
            if (result.two_sample) |*test_result| test_result.exact = result.conditional.?.asRanks();
        }
    }
    return result;
}

fn edf(a: A, values: []const f64, groups: []const usize, counts: []const usize, ranked: ranks.Ranked) !Edf {
    const n = num(values.len);
    const cumulative = try a.alloc(usize, counts.len);
    @memset(cumulative, 0);
    const components = try a.alloc(f64, counts.len);
    @memset(components, 0);
    const at_max = try a.alloc(f64, counts.len);
    @memset(at_max, 0);
    const deviations = try a.alloc(f64, counts.len);
    @memset(deviations, 0);
    var maximum: f64 = -1;
    var pooled_at_max: f64 = 0;
    var max_index: usize = 0;
    var max_value: f64 = values[0];
    var plus: f64 = 0;
    var minus: f64 = 0;
    var pooled_count: usize = 0;
    const Entry = struct { value: f64, group: usize, index: usize };
    const entries = try a.alloc(Entry, values.len);
    for (values, groups, 0..) |value, group, index| entries[index] = .{ .value = value, .group = group, .index = index };
    std.mem.sort(Entry, entries, {}, struct {
        fn less(_: void, l: Entry, r: Entry) bool {
            return l.value < r.value or (l.value == r.value and l.index < r.index);
        }
    }.less);
    var cursor: usize = 0;
    for (ranked.groups) |tie| {
        var first_index: ?usize = null;
        while (cursor < entries.len and entries[cursor].value == tie.value) : (cursor += 1) {
            const entry = entries[cursor];
            cumulative[entry.group] += 1;
            if (first_index == null) first_index = entry.index;
        }
        pooled_count += tie.count;
        const pooled = num(pooled_count) / n;
        var squared: f64 = 0;
        for (counts, cumulative, components) |count, cum, *component| {
            const deviation = num(cum) / num(count) - pooled;
            squared += num(count) * square(deviation);
            component.* += num(tie.count) * num(count) / n * square(deviation);
        }
        if (squared > maximum) {
            maximum = squared;
            pooled_at_max = pooled;
            max_index = first_index.?;
            max_value = tie.value;
            for (counts, cumulative, at_max, deviations) |count, cum, *f, *d| {
                f.* = num(cum) / num(count);
                d.* = @sqrt(num(count)) * (f.* - pooled);
            }
        }
        if (counts.len == 2) {
            const delta = num(cumulative[0]) / num(counts[0]) - num(cumulative[1]) / num(counts[1]);
            plus = @max(plus, delta);
            minus = @max(minus, -delta);
        }
    }
    var cma: f64 = 0;
    for (components) |v| cma += v;
    var result = Edf{ .at_max = at_max, .deviations = deviations, .pooled_at_max = pooled_at_max, .max_index = max_index, .max_value = max_value, .ks = @sqrt(maximum / n), .ksa = @sqrt(maximum), .cm = cma / n, .cma = cma, .cm_components = components, .d = null, .ks_p = null, .kuiper = null, .kuiper_scaled = null, .kuiper_p = null, .kuiper_deviations = .{ plus, minus } };
    if (counts.len == 2) {
        result.d = @max(plus, minus);
        result.d_plus = plus;
        result.d_minus = minus;
        const effective = num(counts[0]) * num(counts[1]) / n;
        result.d_plus_p = @exp(-2 * plus * plus * effective);
        result.d_minus_p = @exp(-2 * minus * minus * effective);
        result.ks_p = kolmogorovTail(result.ksa);
        result.kuiper = plus + minus;
        result.kuiper_scaled = (plus + minus) * @sqrt(num(counts[0]) * num(counts[1]) / n);
        result.kuiper_p = kuiperTail(result.kuiper_scaled.?);
    }
    return result;
}

// Equivalent Jacobi-theta forms avoid cancellation in the small-statistic
// tail. For the direct series, remaining terms decrease geometrically; stopping
// after a term below 1e-16 gives below 1e-14 absolute error in this range.
pub fn kolmogorovTail(z: f64) f64 {
    if (z <= 0) return 1;
    var sum: f64 = 0;
    if (z < 1) {
        for (1..1000) |i| {
            const k = num(2 * i - 1);
            const term = @exp(-k * k * std.math.pi * std.math.pi / (8 * z * z));
            sum += term;
            if (term < 1e-16) break;
        }
        return @max(0, @min(1, 1 - @sqrt(2 * std.math.pi) / z * sum));
    }
    for (1..1000) |i| {
        const k = num(i);
        const term = @exp(-2 * k * k * z * z);
        sum += (if (i % 2 == 1) @as(f64, 1) else -1) * term;
        if (term < 1e-16) break;
    }
    return @max(0, @min(1, 2 * sum));
}
pub fn kuiperTail(z: f64) f64 {
    if (z <= 0) return 1;
    var sum: f64 = 0;
    if (z < 1) {
        for (1..1000) |i| {
            const k = num(i);
            const term = k * k * @exp(-k * k * std.math.pi * std.math.pi / (2 * z * z));
            sum += term;
            if (term < 1e-16) break;
        }
        return @max(0, @min(1, 1 - @sqrt(2 * std.math.pi) * std.math.pi * std.math.pi / (z * z * z) * sum));
    }
    for (1..1000) |i| {
        const k = num(i);
        const term = (4 * k * k * z * z - 1) * @exp(-2 * k * k * z * z);
        sum += term;
        if (term < 1e-16) break;
    }
    return @max(0, @min(1, 2 * sum));
}

test {
    _ = @import("npar1way_stats_tests.zig");
    _ = @import("npar1way_ties_tests.zig");
    _ = @import("npar1way_scale_tests.zig");
    _ = exact;
    _ = @import("npar1way_edf_tests.zig");
}
