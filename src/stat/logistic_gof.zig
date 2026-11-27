//! Binary LOGISTIC diagnostic contracts, S154 physical pp.5926–5934.
//! Classification uses one-step leave-one-Bernoulli predictions; HL grouping
//! uses fitted probabilities and the documented frequency/tie algorithm.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const design = @import("logistic_design.zig");
const kernel = @import("logistic_fit.zig");
const A = std.mem.Allocator;
pub const Scale = enum { unspecified, none, pearson, deviance, constant };
pub const Group = struct { representative: usize, trials: f64 = 0, events: f64 = 0, expected: f64 = 0, minimum: f64 = 0, maximum: f64 = 0 };
pub const Goodness = struct { profiles: usize, df: usize, pearson: f64, deviance: f64, grouped: bool };
pub const ClassRow = struct { cutpoint: f64, prior: f64, true_positive: f64, true_negative: f64, false_positive: f64, false_negative: f64, correct: f64, sensitivity: f64, specificity: f64, positive_predictive: f64, negative_predictive: f64 };
pub const HlOptions = struct { groups: usize = 10, df: ?usize = null, reduce: usize = 2 };
pub const Hosmer = struct { groups: []const Group, statistic: f64, df: usize };
pub const Report = struct { goodness: ?Goodness = null, classification: []const ClassRow = &.{}, explicit_prior: bool = false, hosmer: ?Hosmer = null };

pub fn goodness(groups: []const Group, parameters: usize, grouped: bool) diag.Error!Goodness {
    if (groups.len == 0 or groups.len < parameters) return error.ExecError;
    var pearson: f64 = 0;
    var deviance: f64 = 0;
    for (groups) |g| {
        if (!std.math.isFinite(g.trials) or !std.math.isFinite(g.events) or !std.math.isFinite(g.expected)) return error.ExecError;
        if (!(g.trials > 0 and g.events >= 0 and g.events <= g.trials and g.expected > 0 and g.expected < g.trials)) return error.ExecError;
        const probability = g.expected / g.trials;
        pearson += (g.events - g.expected) * (g.events - g.expected) / (g.trials * probability * (1 - probability));
        if (g.events > 0) deviance += 2 * g.events * @log(g.events / g.expected);
        if (g.events < g.trials) deviance += 2 * (g.trials - g.events) * @log((g.trials - g.events) / (g.trials - g.expected));
    }
    if (!std.math.isFinite(pearson) or !std.math.isFinite(deviance)) return error.ExecError;
    return .{ .profiles = groups.len, .df = groups.len - parameters, .pearson = @max(0, pearson), .deviance = @max(0, deviance), .grouped = grouped };
}
/// Physical p.5933 defines dispersion as Pearson/df, deviance/df or c².
/// This numerical contract does not decide how PROC-specific inference tables
/// change when a dispersion correction is requested.
pub fn dispersion(g: Goodness, mode: Scale, constant: f64) diag.Error!f64 {
    return switch (mode) {
        .unspecified, .none => 1,
        .constant => if (constant > 0 and std.math.isFinite(constant * constant)) constant * constant else error.ExecError,
        .pearson, .deviance => if (g.df > 0) (if (mode == .pearson) g.pearson else g.deviance) / @as(f64, @floatFromInt(g.df)) else error.ExecError,
    };
}

pub fn profiles(a: A, ds: *const Dataset, d: design.Design, fit: kernel.Fit, originals: []const usize, aggregate: ?[]const usize) diag.Error![]const Group {
    if (originals.len != d.n or fit.probabilities.len != d.n) return error.ExecError;
    var groups: std.ArrayList(Group) = .empty;
    for (d.source_rows, originals, d.y, d.frequencies, d.weights, fit.probabilities) |source, original, y, frequency, weight, probability| {
        if (weight != 1) return error.ExecError; // weighted GOF semantics require a separate verified contract
        const row = ds.rows.items[source];
        var found: ?usize = null;
        for (groups.items, 0..) |group, i| {
            var equal = if (aggregate == null) group.representative == original else true;
            if (aggregate) |columns| for (columns) |column| {
                if (proc.cmpValue(row[column], ds.rows.items[group.representative][column]) != .eq) {
                    equal = false;
                    break;
                }
            };
            if (equal) {
                found = i;
                break;
            }
        }
        const index = found orelse blk: {
            try groups.append(a, .{ .representative = if (aggregate != null) source else original, .minimum = probability, .maximum = probability });
            break :blk groups.items.len - 1;
        };
        const g = &groups.items[index];
        // A profile with varying model probabilities is not a replicated
        // binomial profile. Do not replace its variance by n*pbar*(1-pbar).
        if (@abs(probability - g.minimum) > 32 * std.math.floatEps(f64)) return error.ExecError;
        g.trials += frequency;
        g.events += frequency * y;
        g.expected += frequency * probability;
    }
    return groups.items;
}

pub fn crossvalidated(a: A, d: design.Design, fit: kernel.Fit) diag.Error![]const f64 {
    if (fit.probabilities.len != d.n or fit.coefficients.len != d.p or fit.covariance.len != d.p * d.p) return error.ExecError;
    if (d.x.len != d.n * d.p or d.y.len != d.n or d.weights.len != d.n) return error.ExecError;
    const result = try a.alloc(f64, d.n);
    for (d.y, fit.probabilities, d.weights, 0..) |response, probability, weight, i| {
        if ((response != 0 and response != 1) or !(probability > 0 and probability < 1) or !(weight > 0) or !std.math.isFinite(weight)) return error.ExecError;
        var variance: f64 = 0;
        var eta: f64 = 0;
        for (0..d.p) |j| {
            eta += d.x[i * d.p + j] * fit.coefficients[j];
            for (0..d.p) |k| variance += d.x[i * d.p + j] * fit.covariance[j * d.p + k] * d.x[i * d.p + k];
        }
        const leverage = weight * probability * (1 - probability) * variance;
        if (!(leverage >= 0 and leverage < 1) or !std.math.isFinite(variance)) return error.ExecError;
        // One frequency replicate is deleted, not the whole compressed row.
        // For grouped trials the existing producer supplies separate y=1/0
        // rows, so event and nonevent predictions have different corrections.
        const adjusted = eta - weight * (response - probability) * variance / (1 - leverage);
        result[i] = kernel.probability(adjusted);
    }
    return result;
}
/// Outward0.02 grid rounding (S154 physical p.5883), for supplied probabilities.
pub fn cutpoints(a: A, predictions: []const f64) diag.Error![]const f64 {
    if (predictions.len == 0) return error.ExecError;
    var low: f64 = 1;
    var high: f64 = 0;
    for (predictions) |p| {
        if (!(p >= 0 and p <= 1)) return error.ExecError;
        low = @min(low, p);
        high = @max(high, p);
    }
    const first: usize = @intFromFloat(@floor(low * 50));
    const last: usize = @intFromFloat(@ceil(high * 50));
    const result = try a.alloc(f64, last - first + 1);
    for (result, first..) |*value, i| value.* = @as(f64, @floatFromInt(i)) / 50;
    return result;
}
fn divide(numerator: f64, denominator: f64) f64 {
    return if (denominator > 0) numerator / denominator else std.math.nan(f64);
}
pub fn classification(a: A, d: design.Design, predictions: []const f64, thresholds: []const f64, priors: []const f64) diag.Error![]const ClassRow {
    if (predictions.len != d.n or d.y.len != d.n or d.frequencies.len != d.n or thresholds.len == 0) return error.ExecError;
    var events: f64 = 0;
    var total: f64 = 0;
    for (d.y, d.frequencies, predictions) |y, f, prediction| {
        if ((y != 0 and y != 1) or !(f > 0) or !std.math.isFinite(f) or !(prediction >= 0 and prediction <= 1)) return error.ExecError;
        total += f;
        events += y * f;
    }
    if (!(events > 0 and events < total) or !std.math.isFinite(total)) return error.ExecError;
    const defaults = [_]f64{events / total};
    const prevalences: []const f64 = if (priors.len == 0) &defaults else priors;
    const rows = try a.alloc(ClassRow, thresholds.len * prevalences.len);
    var index: usize = 0;
    for (prevalences) |prior| for (thresholds) |threshold| {
        if (!(prior >= 0 and prior <= 1 and threshold >= 0 and threshold <= 1)) return error.ExecError;
        var tp: f64 = 0;
        var tn: f64 = 0;
        var fp: f64 = 0;
        var fn_: f64 = 0;
        for (d.y, d.frequencies, predictions) |y, f, prediction| {
            if (prediction >= threshold) {
                if (y == 1) tp += f else fp += f;
            } else {
                if (y == 1) fn_ += f else tn += f;
            }
        }
        const sensitivity = tp / events;
        const specificity = tn / (total - events);
        rows[index] = .{ .cutpoint = threshold, .prior = prior, .true_positive = tp, .true_negative = tn, .false_positive = fp, .false_negative = fn_, .correct = prior * sensitivity + (1 - prior) * specificity, .sensitivity = sensitivity, .specificity = specificity, .positive_predictive = divide(prior * sensitivity, prior * sensitivity + (1 - prior) * (1 - specificity)), .negative_predictive = divide((1 - prior) * specificity, (1 - prior) * specificity + prior * (1 - sensitivity)) };
        index += 1;
    };
    return rows;
}

pub fn hosmerGroups(a: A, y: []const f64, probabilities: []const f64, frequency: []const f64, requested: usize) diag.Error![]const Group {
    if (requested < 5 or y.len == 0 or probabilities.len != y.len or frequency.len != y.len) return error.ExecError;
    const order = try a.alloc(usize, y.len);
    defer a.free(order);
    var total: f64 = 0;
    for (y, probabilities, frequency, 0..) |response, probability, f, i| {
        if ((response != 0 and response != 1) or !(probability > 0 and probability < 1) or !(f > 0) or !std.math.isFinite(f) or @trunc(f) != f) return error.ExecError;
        total += f;
        order[i] = i;
    }
    const Sort = struct {
        fn less(p: []const f64, i: usize, j: usize) bool {
            return p[i] < p[j];
        }
    };
    std.mem.sort(usize, order, probabilities, Sort.less);
    const target = @floor(total / @as(f64, @floatFromInt(requested)) + 0.5);
    var groups: std.ArrayList(Group) = .empty;
    var start: usize = 0;
    while (start < order.len) {
        const p = probabilities[order[start]];
        var next = start;
        var f: f64 = 0;
        var events: f64 = 0;
        while (next < order.len and probabilities[order[next]] == p) : (next += 1) {
            const i = order[next];
            f += frequency[i];
            events += frequency[i] * y[i];
        }
        const add = groups.items.len > 0 and (groups.items.len == requested or (groups.items[groups.items.len - 1].trials < target and groups.items[groups.items.len - 1].trials + @floor(f / 2) <= target));
        if (!add) try groups.append(a, .{ .representative = order[start], .minimum = p, .maximum = p });
        const group = &groups.items[groups.items.len - 1];
        group.trials += f;
        group.events += events;
        group.expected += f * p;
        group.maximum = p;
        start = next;
    }
    if (groups.items.len > 1 and groups.items[groups.items.len - 1].trials < total / (2 * @as(f64, @floatFromInt(requested)))) {
        const last = groups.pop().?;
        const previous = &groups.items[groups.items.len - 1];
        previous.trials += last.trials;
        previous.events += last.events;
        previous.expected += last.expected;
        previous.maximum = last.maximum;
    }
    return groups.items;
}
pub fn hosmer(a: A, d: design.Design, fit: kernel.Fit, options: HlOptions) diag.Error!Hosmer {
    const groups = try hosmerGroups(a, d.y, fit.probabilities, d.frequencies, options.groups);
    return hosmerStatistic(groups, options);
}
pub fn hosmerStatistic(groups: []const Group, options: HlOptions) diag.Error!Hosmer {
    if (groups.len < 3 or (options.df == null and groups.len <= options.reduce)) return error.ExecError;
    const statistics = try goodness(groups, 0, false);
    return .{ .groups = groups, .statistic = statistics.pearson, .df = options.df orelse (groups.len - options.reduce) };
}

fn num(a: A, value: f64, specification: []const u8) diag.Error![]const u8 {
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, specification), " ");
}
pub fn renderGoodness(a: A, out: *std.ArrayList(u8), g: Goodness) diag.Error!void {
    try out.appendSlice(a, "Deviance and Pearson Goodness-of-Fit Statistics\n\nCriterion Value DF Value/DF Pr > ChiSq\n\n");
    for ([_][]const u8{ "Deviance", "Pearson" }, [_]f64{ g.deviance, g.pearson }) |label, statistic| try out.print(a, "{s} {s} {d} {s} {s}\n", .{ label, try num(a, statistic, "10.4"), g.df, try num(a, if (g.df > 0) statistic / @as(f64, @floatFromInt(g.df)) else std.math.nan(f64), "10.4"), try num(a, kernel.chiTail(statistic, g.df), "pvalue6.4") });
    try out.print(a, "\nNumber of {s}: {d}\n\n", .{ if (g.grouped) "events/trials observations" else "unique profiles", g.profiles });
}
pub fn renderExtras(a: A, out: *std.ArrayList(u8), report: Report, response: []const u8, event: []const u8, nonevent: []const u8) diag.Error!void {
    if (report.hosmer) |hl| {
        if (hl.groups.len <= 50) {
            try out.print(a, "\nPartition for the Hosmer and Lemeshow Test\n\n{s} = {s} {s} = {s}\nGroup Total Observed Expected Observed Expected\n\n", .{ response, event, response, nonevent });
            for (hl.groups, 0..) |group, i| try out.print(a, "{d} {s} {s} {s} {s} {s}\n", .{ i + 1, try num(a, group.trials, "best12."), try num(a, group.events, "best12."), try num(a, group.expected, "10.2"), try num(a, group.trials - group.events, "best12."), try num(a, group.trials - group.expected, "10.2") });
        }
        try out.print(a, "\nHosmer and Lemeshow Goodness-of-Fit Test\n\nChi-Square DF Pr > ChiSq\n\n{s} {d} {s}\n", .{ try num(a, hl.statistic, "10.4"), hl.df, try num(a, kernel.chiTail(hl.statistic, hl.df), "pvalue6.4") });
    }
    if (report.classification.len > 0) {
        try out.appendSlice(a, "\nClassification Table\n\nCorrect Incorrect Percentages\n");
        try out.print(a, "{s}Prob Non- Non- Sensi- Speci- Pos Neg\n{s}Level Event Event Event Event Correct tivity ficity Pred Pred\n\n", .{ if (report.explicit_prior) "Prob " else "", if (report.explicit_prior) "Event " else "" });
        for (report.classification) |row| {
            if (report.explicit_prior) try out.print(a, "{s} ", .{try num(a, row.prior, "8.3")});
            try out.print(a, "{s} {s} {s} {s} {s} {s} {s} {s} {s} {s}\n", .{ try num(a, row.cutpoint, "8.3"), try num(a, row.true_positive, "best12."), try num(a, row.true_negative, "best12."), try num(a, row.false_positive, "best12."), try num(a, row.false_negative, "best12."), try num(a, 100 * row.correct, "6.1"), try num(a, 100 * row.sensitivity, "6.1"), try num(a, 100 * row.specificity, "6.1"), try num(a, 100 * row.positive_predictive, "6.1"), try num(a, 100 * row.negative_predictive, "6.1") });
        }
    }
}
