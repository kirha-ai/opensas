//! Typed EXACT execution, independent of shared PROC glue. Explicit family to
//! reference-set dispatch prevents callbacks from accidentally changing H0.
const std = @import("std");
const dist = @import("freq_exact_distribution.zig");
const reference = @import("freq_exact_reference.zig");
const exact = @import("freq_exact.zig");
const unconditional = @import("freq_exact_unconditional.zig");
const parse = @import("freq_exact_parse.zig");
const tests = @import("freq_tests.zig");
const stratified = @import("freq_stratified.zig");
const adapters = @import("freq_stratified_exact.zig");
pub const Error = dist.Error;
pub const Config = struct {
    numeric_table_scores_valid: bool = true,
    options: parse.Options = .{},
    budget: dist.Budget = .{},
    /// Resolved once per PROC by caller; <=0 SEED uses caller's clock.
    effective_seed: u64 = 1,
    alpha: f64 = 0.05,
    midp_limits: bool = false,
    expected: tests.Expected = .equal,
    binomial_p: f64 = 0.5,
    event_index: usize = 0,
    null_ratio: f64 = 1,
    kappa_weight: stratified.KappaWeight = .cicchetti_allison,
    norisks: bool = false,
};
pub const Barnard = struct {
    difference: f64,
    se: f64,
    z: f64,
    tails: unconditional.BarnardTails,

    pub fn oneSided(self: Barnard) ?f64 {
        return switch (self.tails) {
            .exhausted => null,
            .complete => |v| if (v.profile) |profile| profile.one else v.one.upper,
        };
    }
    pub fn twoSided(self: Barnard) ?f64 {
        return switch (self.tails) {
            .exhausted => null,
            .complete => |v| if (v.profile) |profile| profile.two else v.two.upper,
        };
    }

    /// M9 reports the observed score one square root of unit roundoff closer
    /// to zero. Preserve the analytical score and independently enumerated tails.
    pub fn reportedZ(self: Barnard) f64 {
        const tolerance = @sqrt(std.math.floatEps(f64) / 2);
        return std.math.copysign(@max(0, @abs(self.z) - tolerance), self.z);
    }
};
pub const Result = union(enum) {
    exact_test: dist.Probabilities,
    fisher: struct { table_probability: f64, first_cell: ?f64, cell_tails: ?exact.Tails, probabilities: dist.Probabilities },
    monte_carlo: struct { estimates: dist.MonteCarlo, table_probability: ?f64 = null },
    binomial: exact.Binomial,
    interval: exact.Interval,
    risk_intervals: struct { first: ?exact.Interval = null, second: ?exact.Interval = null },
    barnard: Barnard,
    exhausted,
    score_too_small: bool, // sign of the observed directional statistic
    /// Valid family, but not defined for this table's dimensions/zero variance.
    not_applicable,
    /// Joint strata must be dispatched through their dedicated adapter.
    requires_strata,
};
const Context = struct {
    allocator: std.mem.Allocator,
    family: parse.Family,
    row_scores: ?[]const f64,
    col_scores: ?[]const f64,
    expected: tests.Expected,
    fn evaluate(raw: ?*const anyopaque, m: dist.Matrix) Error!f64 {
        const self: *const Context = @ptrCast(@alignCast(raw.?));
        var cells: [256]f64 = undefined;
        if (m.cells.len > cells.len) return error.ExecError;
        for (m.cells, 0..) |v, i| cells[i] = @floatFromInt(v);
        const counts = cells[0..m.cells.len];
        if (m.rows == 1) {
            const r = try tests.goodnessOfFit(counts, self.expected, null);
            return if (self.family == .pchi) r.pearson.statistic else r.likelihood_ratio.statistic;
        }
        const matrix = tests.CountMatrix{ .rows = m.rows, .cols = m.cols, .counts = counts, .row_scores = self.row_scores, .col_scores = self.col_scores };
        if (self.family == .pchi or self.family == .lrchi) {
            // Only the sampled statistic is needed. contingency() additionally
            // enumerates automatic 2x2 Fisher, which would perform an unbounded
            // support scan inside every Monte Carlo draw without MAXTIME checks.
            var rows = [_]f64{0} ** 256;
            var cols = [_]f64{0} ** 256;
            var total: f64 = 0;
            for (counts, 0..) |v, i| {
                rows[i / m.cols] += v;
                cols[i % m.cols] += v;
                total += v;
            }
            var statistic: f64 = 0;
            for (counts, 0..) |v, i| {
                const cell = tests.independenceCell(v, rows[i / m.cols], cols[i % m.cols], total);
                if (cell.mean == 0) continue;
                statistic += if (self.family == .pchi)
                    cell.delta * cell.delta / cell.mean
                else
                    2 * exact.poissonDeviance(v, cell.mean, cell.delta);
            }
            return statistic;
        }
        if (self.family != .pcorr) return error.ExecError;
        const r = try tests.association(self.allocator, matrix, 0.05);
        return r.pearson.estimate orelse error.ExecError;
    }
};

/// A fixed-margin permutation changes neither the normalizing denominator of
/// a rank coefficient nor the null mean of J. C-D orders the four concordance
/// coefficients and is twice the centered Jonckheere-Terpstra statistic.
const Ordinal = struct {
    spearman: bool,
    row_rank: [256]i64 = undefined,
    col_rank: [256]i64 = undefined,

    fn init(m: dist.Matrix, spearman: bool) Ordinal {
        var self = Ordinal{ .spearman = spearman };
        if (!spearman) return self;
        const rows = self.row_rank[0..m.rows];
        const cols = self.col_rank[0..m.cols];
        @memset(rows, 0);
        @memset(cols, 0);
        var n: i64 = 0;
        for (m.cells, 0..) |x, k| {
            rows[k / m.cols] += x;
            cols[k % m.cols] += x;
            n += x;
        }
        // Twice the centered midrank is integral, even with ties.
        for ([_][]i64{ rows, cols }) |ranks| {
            var preceding: i64 = 0;
            for (ranks) |*rank| {
                const count = rank.*;
                rank.* = 2 * preceding + count - n;
                preceding += count;
            }
        }
        return self;
    }

    fn score(raw: ?*const anyopaque, m: dist.Matrix) i128 {
        const self: *const Ordinal = @ptrCast(@alignCast(raw.?));
        var sum: i128 = 0;
        if (self.spearman) {
            for (m.cells, 0..) |x, k| sum += @as(i128, x) * self.row_rank[k / m.cols] * self.col_rank[k % m.cols];
            return sum;
        }
        var above: [256]i128 = undefined;
        return stratified.concordanceSurplus(i128, m.cells, m.cols, above[0..m.cols]);
    }

    fn asFloat(raw: ?*const anyopaque, m: dist.Matrix) Error!f64 {
        return @floatFromInt(score(raw, m));
    }
};

/// The trend statistic has fixed variance in its permutation distribution.
/// For integral explanatory scores the centered numerator can be ordered
/// exactly, including when the scores all share a large offset.
const IntegralTrend = struct {
    scores: [256]i128 = undefined,
    total: i128 = 0,
    successes: i128 = 0,
    marginal_score: i128 = 0,

    fn init(m: dist.Matrix, scores: ?[]const f64) ?IntegralTrend {
        const by_row = m.cols == 2;
        const len = if (by_row) m.rows else m.cols;
        var self = IntegralTrend{};
        for (m.cells) |x| self.total += x;
        // Both terms in N*sum(x*s) - D*sum(margin*s) are bounded by
        // N squared times the largest translated absolute score.
        const bound = @divTrunc(std.math.maxInt(i128), 2 * self.total * self.total);
        var origin: i128 = 0;
        for (0..len) |i| {
            const supplied = if (scores) |s| s[i] else @as(f64, @floatFromInt(i + 1));
            if (supplied != @trunc(supplied) or @abs(supplied) >= 0x1p127) return null;
            const value: i128 = @intFromFloat(supplied);
            if (i == 0) origin = value;
            const translated = std.math.sub(i128, value, origin) catch return null;
            if (@abs(translated) > @as(u128, @intCast(bound))) return null;
            self.scores[i] = translated;
            const x = if (by_row) m.cells[i * 2] else m.cells[i];
            const y = if (by_row) m.cells[i * 2 + 1] else m.cells[m.cols + i];
            self.successes += x;
            self.marginal_score += (@as(i128, x) + y) * translated;
        }
        return self;
    }

    fn score(raw: ?*const anyopaque, m: dist.Matrix) i128 {
        const self: *const IntegralTrend = @ptrCast(@alignCast(raw.?));
        const by_row = m.cols == 2;
        const len = if (by_row) m.rows else m.cols;
        var weighted: i128 = 0;
        for (self.scores[0..len], 0..) |s, i| weighted += s * @as(i128, if (by_row) m.cells[i * 2] else m.cells[i]);
        return self.total * weighted - self.successes * self.marginal_score;
    }

    fn asFloat(raw: ?*const anyopaque, m: dist.Matrix) Error!f64 {
        return @floatFromInt(score(raw, m));
    }
};
const network_tolerance = @sqrt(std.math.floatEps(f64) / 2);

/// At fixed margins the raw linear score has a constant mean and variance.
/// Network near-ties are measured before normalization. For MHCHI, the
/// nondirectional ordering is by absolute distance from the fixed null mean.
const NetworkScore = struct {
    row: [256]f64 = undefined,
    col: [256]f64 = undefined,
    mean: f64 = 0,
    absolute: bool,

    fn init(m: tests.CountMatrix, family: parse.Family) ?NetworkScore {
        var self = NetworkScore{ .absolute = family == .mhchi };
        var row_counts = [_]f64{0} ** 256;
        var col_counts = [_]f64{0} ** 256;
        var n: f64 = 0;
        for (m.counts, 0..) |count, i| {
            row_counts[i / m.cols] += count;
            col_counts[i % m.cols] += count;
            n += count;
        }
        var sums: [2]f64 = @splat(0);
        var bound = n;
        for ([_][]f64{ self.row[0..m.rows], self.col[0..m.cols] }, [_]?[]const f64{ m.row_scores, m.col_scores }, [_][]const f64{ row_counts[0..m.rows], col_counts[0..m.cols] }, 0..) |weights, scores, margins, axis| {
            // TREND counts the first response category. When both axes are
            // binary the columns supply the response.
            const response = family == .trend and axis == @intFromBool(m.cols == 2);
            var largest: f64 = 0;
            for (weights, margins, 0..) |*w, count, i| {
                w.* = if (response) @floatFromInt(@intFromBool(i == 0)) else if (scores) |v| v[i] else @floatFromInt(i + 1);
                sums[axis] += count * w.*;
                largest = @max(largest, @abs(w.*));
            }
            bound *= largest;
        }
        // Once adjacent possible binary64 values are farther apart than the
        // tie window, raw subtraction cannot resolve its endpoints reliably.
        // Retain the existing standardized statistic in that range.
        if (!std.math.isFinite(bound) or std.math.nextAfter(f64, bound, std.math.inf(f64)) - bound > network_tolerance) return null;
        self.mean = sums[0] * sums[1] / n;
        return self;
    }

    fn evaluate(raw: ?*const anyopaque, m: dist.Matrix) Error!f64 {
        const self: *const NetworkScore = @ptrCast(@alignCast(raw.?));
        var value: f64 = 0;
        for (m.cells, 0..) |x, i| value += @as(f64, @floatFromInt(x)) * self.row[i / m.cols] * self.col[i % m.cols];
        return if (self.absolute) @abs(value - self.mean) else value;
    }
};

fn finish(result: dist.Enumeration) Result {
    return switch (result) {
        .complete => |p| .{ .exact_test = p },
        .exhausted => .exhausted,
    };
}
fn applicable(f: parse.Family, m: tests.CountMatrix) bool {
    if (m.rows == 1) return f == .binomial or f == .pchi or f == .lrchi;
    return switch (f) {
        .binomial => false,
        .mcnem, .oddsratio, .riskdiff, .relrisk, .barnard => m.rows == 2 and m.cols == 2,
        .symmetry => m.rows == m.cols and m.rows > 2,
        .kappa, .wtkappa => m.rows == m.cols and m.rows > 1,
        .trend => m.rows == 2 or m.cols == 2,
        else => m.rows > 1 and m.cols > 1,
    };
}

fn smallNetworkScore(scores: ?[]const f64) bool {
    // Adjacent binary64 M9 probes straddle sqrt(unit roundoff). Zero is a
    // valid score. This check belongs to the network algorithm, not simulation.
    for (scores orelse return false) |s| {
        if (s != 0 and @abs(s) <= network_tolerance) return true;
    }
    return false;
}
/// Group options must be expanded by Options.expanded before calling this.
pub fn run(a: std.mem.Allocator, m: tests.CountMatrix, f: parse.Family, c: Config) Error!Result {
    if (f == .comor or f == .eqor) return .requires_strata;
    if (!c.numeric_table_scores_valid and (f == .pcorr or f == .mhchi)) return .not_applicable;
    if (f == .agree or f == .chisq or f == .measures) return error.ExecError;
    if (!applicable(f, m)) return .not_applicable;
    if (f == .mcnem and m.counts.len == 4 and m.counts[1] + m.counts[2] == 0) return .not_applicable;
    if (m.counts.len > 256) return .exhausted;
    if (f == .fisher and m.rows == 2 and m.cols == 2 and m.counts.len == 4) {
        const result = (try tests.fisherWithAllocator(a, m.counts, c.budget)) orelse return .exhausted;
        if (result.tables == 1) return .not_applicable;
        const cell = result.cell;
        return .{ .fisher = .{
            .table_probability = cell.probability,
            .first_cell = m.counts[0],
            .cell_tails = .{ .point = cell.probability, .left = cell.left, .right = cell.right },
            .probabilities = .{ .point = result.point, .left = result.more_likely, .right = cell.two_sided, .two_sided = cell.two_sided, .one_sided = cell.two_sided, .tables = result.tables },
        } };
    }
    const integers = try dist.Matrix.fromCounts(a, m.rows, m.cols, m.counts);
    defer a.free(integers.cells);
    // SAS sparse.sas: zero margins suppress all but AGREE statistics, even
    // with WEIGHT / ZEROS. Preserve the full square matrix for agreement.
    if (m.rows > 1 and f != .mcnem and f != .symmetry and f != .kappa and f != .wtkappa) {
        for (0..m.rows) |i| {
            var sum: u64 = 0;
            for (integers.cells[i * m.cols ..][0..m.cols]) |v| sum += v;
            if (sum == 0) return .not_applicable;
        }
        for (0..m.cols) |j| {
            var sum: u64 = 0;
            for (0..m.rows) |i| sum += integers.cells[i * m.cols + j];
            if (sum == 0) return .not_applicable;
        }
    }
    if (f == .binomial) {
        if (c.event_index >= integers.cells.len) return error.ExecError;
        var n: u32 = 0;
        for (integers.cells) |v| n += v;
        const result = try exact.binomialControlled(integers.cells[c.event_index], n, c.binomial_p, c.alpha, c.midp_limits, .{ .context = c.budget.context, .expired = c.budget.expired });
        return switch (result) {
            .complete => |b| .{ .binomial = b },
            .exhausted => .exhausted,
        };
    }
    if (f == .mcnem) return finish(try reference.mcnemar(integers.cells[1], integers.cells[2], c.null_ratio, c.budget));
    if (f == .oddsratio) {
        const r = try exact.oddsRatioControlled(integers.cells[0..4].*, c.alpha, c.midp_limits, c.budget.max_tables, .{ .context = c.budget.context, .expired = c.budget.expired });
        return switch (r) {
            .complete => |ci| .{ .interval = ci },
            .exhausted => .exhausted,
        };
    }
    if (f == .riskdiff or f == .relrisk or f == .barnard) {
        const table = @import("freq_risk.zig").Table2x2{ .cells = m.counts[0..4].* };
        if (f == .barnard) {
            const n1 = m.counts[0] + m.counts[1];
            const n2 = m.counts[2] + m.counts[3];
            const delta = m.counts[0] / n1 - m.counts[2] / n2;
            const tails = try unconditional.barnardTails(table, if (delta > 0) .right else .left, .{ .budget = c.budget, .allocator = a });
            if (tails == .exhausted and !c.budget.stopped()) return .exhausted;
            const p = (m.counts[0] + m.counts[2]) / (n1 + n2);
            const q = (m.counts[1] + m.counts[3]) / (n1 + n2);
            const se = @sqrt(p * q * (1 / n1 + 1 / n2));
            return .{ .barnard = .{ .difference = delta, .se = se, .z = delta / se, .tails = tails } };
        }
        const options = if (f == .riskdiff) c.options.riskdiff else c.options.relrisk;
        const column = options.column orelse if (f == .riskdiff and !c.norisks) parse.Column.both else .first;
        var result: Result = .{ .risk_intervals = .{} };
        for ([_]bool{ true, false }) |first| {
            if ((first and column == .second) or (!first and column == .first)) continue;
            const interval = try unconditional.riskLimitsSas(table, if (first) .first else .second, if (f == .riskdiff) .difference else .relative_risk, options.method, c.alpha, .{ .budget = c.budget, .allocator = a });
            if (interval == .exhausted) return .exhausted;
            if (first) result.risk_intervals.first = interval.complete else result.risk_intervals.second = interval.complete;
        }
        return result;
    }
    var context = Context{ .allocator = a, .family = f, .row_scores = m.row_scores, .col_scores = m.col_scores, .expected = c.expected };
    var callback = dist.Statistic{ .context = &context, .evaluate = Context.evaluate, .directional = switch (f) {
        .pcorr => true,
        else => false,
    } };
    var sc: adapters.Context = undefined;
    var ordinal: Ordinal = undefined;
    var trend_order: ?IntegralTrend = null;
    var weights: ?[]f64 = null;
    defer if (weights) |w| a.free(w);
    const sf: ?adapters.Family = switch (f) {
        .trend => .trend,
        .kappa => .kappa,
        .wtkappa => .weighted_kappa,
        .mhchi => .mhchi,
        .symmetry => .symmetry,
        else => null,
    };
    if (sf) |family| {
        const sm = stratified.Matrix{ .rows = m.rows, .cols = m.cols, .counts = m.counts, .row_scores = m.row_scores, .col_scores = m.col_scores };
        if (f == .wtkappa) weights = try stratified.kappaWeights(a, sm, c.kappa_weight);
        sc = try adapters.Context.init(sm, family, weights, c.null_ratio);
        callback = adapters.Adapters(dist).statistic(&sc);
        if (f == .trend) {
            trend_order = IntegralTrend.init(integers, if (m.cols == 2) m.row_scores else m.col_scores);
            if (trend_order) |*order| callback = .{ .context = order, .evaluate = IntegralTrend.asFloat, .directional = true, .centered_integer = .{ .observed = IntegralTrend.score(order, integers), .score = IntegralTrend.score } };
        }
    } else switch (f) {
        .fisher => callback = .{ .evaluate = dist.fisherStatistic },
        .jt, .kentb, .stutc, .smdcr, .smdrc, .scorr => {
            ordinal = Ordinal.init(integers, f == .scorr);
            callback = .{ .context = &ordinal, .evaluate = Ordinal.asFloat, .directional = true, .centered_integer = .{ .observed = Ordinal.score(&ordinal, integers), .score = Ordinal.score } };
        },
        else => {},
    }
    const simulation = dist.Simulation{
        .seed = c.effective_seed,
        .samples = c.options.samples,
        .alpha = c.options.alpha,
        .binary_response = if (f != .trend) .none else if (m.cols == 2) .columns else .rows,
    };
    const mc = c.options.mc and parse.supportsMonteCarlo(f, m.rows, m.cols);
    if (!mc and switch (f) {
        .mhchi, .pcorr => smallNetworkScore(m.row_scores) or smallNetworkScore(m.col_scores),
        .trend => smallNetworkScore(if (m.cols == 2) m.row_scores else m.col_scores),
        else => false,
    }) {
        const value = callback.evaluate(callback.context, integers) catch |err| {
            if (err == error.OutOfMemory) return err;
            return .not_applicable;
        };
        if (!std.math.isFinite(value)) return .not_applicable;
        return .{ .score_too_small = value > callback.expected };
    }
    if (m.rows == 1) {
        var total: f64 = 0;
        for (m.counts) |v| total += v;
        const factor = try tests.expectedFactor(m.cols, total, c.expected);
        const probabilities = try a.alloc(f64, m.cols);
        defer a.free(probabilities);
        for (probabilities, 0..) |*p, i| p.* = switch (c.expected) {
            .equal => 1 / @as(f64, @floatFromInt(m.cols)),
            .proportions => |v| if (factor == total) v[i] else v[i] / 100,
            .frequencies => |v| v[i] / total,
        };
        if (mc) return .{ .monte_carlo = .{ .estimates = try reference.multinomialMonteCarlo(a, integers.cells, probabilities, callback, simulation, c.budget) } };
        return finish(try reference.multinomial(a, integers.cells, probabilities, callback, c.budget));
    }
    if (f == .symmetry) {
        if (mc) return .{ .monte_carlo = .{ .estimates = try reference.symmetryMonteCarlo(a, integers, callback, simulation, c.budget) } };
        return finish(try reference.symmetry(a, integers, 1, callback, c.budget));
    }
    if (mc) return .{ .monte_carlo = .{
        .estimates = try dist.monteCarlo(a, integers, callback, simulation, c.budget),
        .table_probability = if (f == .fisher) try dist.tableProbability(integers) else null,
    } };
    var network: ?NetworkScore = null;
    if (f == .pcorr or f == .mhchi or (f == .trend and trend_order == null)) {
        // Keep the statistic's usual check for zero variance and invalid scores.
        if (!std.math.isFinite(try callback.evaluate(callback.context, integers))) return error.ExecError;
        network = NetworkScore.init(m, f);
        if (network) |*score| callback = .{
            .context = score,
            .evaluate = NetworkScore.evaluate,
            .directional = !score.absolute,
            .expected = if (score.absolute) 0 else score.mean,
            .absolute_tolerance = network_tolerance,
        };
    }
    const enumerated = try dist.enumerate(a, integers, callback, c.budget);
    if (f == .fisher) {
        if (enumerated == .exhausted) return .exhausted;
        return .{ .fisher = .{ .table_probability = try dist.tableProbability(integers), .first_cell = null, .cell_tails = null, .probabilities = enumerated.complete } };
    }
    return finish(enumerated);
}

test "network tests enforce the native score precision boundary only on their scoring axes" {
    const t = std.testing;
    // M9 score-floor-m9.sas: hexadecimal BCC and BCD report missing exact
    // rows; BCE proceeds. The Monte Carlo estimators remain available.
    const last: f64 = @bitCast(@as(u64, 0x3e46a09e667f3bcd));
    const first: f64 = @bitCast(@as(u64, 0x3e46a09e667f3bce));
    for ([_]f64{ std.math.nextAfter(f64, last, 0), last, -last, first, 0 }) |s| {
        const m = tests.CountMatrix{ .rows = 3, .cols = 2, .counts = &.{ 1, 5, 3, 2, 2, 4 }, .row_scores = &.{ 0, s, 1 }, .col_scores = &.{ 1, 2 } };
        for ([_]parse.Family{ .trend, .pcorr, .mhchi }) |f| {
            const r = try run(t.allocator, m, f, .{});
            try t.expect((r == .score_too_small) == (s != 0 and @abs(s) <= last));
            const mc = try run(t.allocator, m, f, .{ .options = .{ .mc = true, .samples = 31 }, .effective_seed = 71 });
            try t.expect(mc.monte_carlo.estimates == .complete);
        }
    }
    const response = tests.CountMatrix{ .rows = 3, .cols = 2, .counts = &.{ 1, 5, 3, 2, 2, 4 }, .row_scores = &.{ 1, 2, 3 }, .col_scores = &.{ last, 1 } };
    try t.expect((try run(t.allocator, response, .trend, .{})) == .exact_test);
    try t.expect((try run(t.allocator, response, .pcorr, .{})) == .score_too_small);
    try t.expect((try run(t.allocator, response, .mhchi, .{})) == .score_too_small);
}

test "conditional network ties use the raw linear score before normalization" {
    const t = std.testing;
    // M9 score-order-heldout.sas, h05. Fixed margins give 35 equally
    // likely labeled draws. The response scores scale the correlation only.
    const m = tests.CountMatrix{ .rows = 3, .cols = 2, .counts = &.{ 3, 0, 0, 2, 1, 1 }, .row_scores = &.{ 0.25, 0.25000000790253407, 1 }, .col_scores = &.{ 0, 0.375 } };
    const pcorr = (try run(t.allocator, m, .pcorr, .{})).exact_test;
    const mhchi = (try run(t.allocator, m, .mhchi, .{})).exact_test;
    const trend = (try run(t.allocator, m, .trend, .{})).exact_test;
    try t.expectApproxEqAbs(@as(f64, 25.0 / 35.0), pcorr.one_sided, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 20.0 / 35.0), pcorr.point, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 1), pcorr.two_sided, 2e-15);
    try t.expectApproxEqAbs(pcorr.point, mhchi.point, 2e-15);
    try t.expectApproxEqAbs(pcorr.two_sided, mhchi.two_sided, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 19.0 / 35.0), trend.one_sided, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 14.0 / 35.0), trend.point, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 29.0 / 35.0), trend.two_sided, 2e-15);

    // h03 is 2 x 3. The first row supplies the binary response, and the
    // explanatory scores differ by less than the network tolerance.
    const transposed = tests.CountMatrix{ .rows = 2, .cols = 3, .counts = &.{ 4, 0, 1, 0, 3, 1 }, .row_scores = &.{ 0, 1 }, .col_scores = &.{ 0.5, 0.50000000705959713, 3 } };
    const other = (try run(t.allocator, transposed, .trend, .{})).exact_test;
    try t.expectApproxEqAbs(@as(f64, 47.0 / 126.0), other.one_sided, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 26.0 / 126.0), other.point, 2e-15);
    try t.expectApproxEqAbs(@as(f64, 82.0 / 126.0), other.two_sided, 2e-15);
}

test "2x2 Fisher matches exhaustive integer weights, ties, and both cell tails" {
    const choose = struct {
        fn small(n: u64, k: u64) u64 {
            var result: u64 = 1;
            for (0..@min(k, n - k)) |j| result = result * (n - j) / (j + 1);
            return result;
        }
    }.small;
    for (1..8) |r1| for (1..8) |r2| for (1..r1 + r2) |c1| {
        const lo = c1 -| r2;
        const hi = @min(r1, c1);
        const den: f64 = @floatFromInt(choose(r1 + r2, c1));
        for (lo..hi + 1) |a| {
            const observed = choose(r1, a) * choose(r2, c1 - a);
            var totals = [_]u64{0} ** 4;
            for (lo..hi + 1) |x| {
                const w = choose(r1, x) * choose(r2, c1 - x);
                if (w == observed) totals[0] += w;
                if (x <= a) totals[1] += w;
                if (x >= a) totals[2] += w;
                if (w <= observed) totals[3] += w;
            }
            const counts = [_]f64{ @floatFromInt(a), @floatFromInt(r1 - a), @floatFromInt(c1 - a), @floatFromInt(r2 - (c1 - a)) };
            const result = (try run(std.testing.allocator, .{ .rows = 2, .cols = 2, .counts = &counts }, .fisher, .{})).fisher;
            try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(observed)) / den, result.table_probability, 2e-15);
            for (totals, [_]f64{ result.probabilities.point, result.cell_tails.?.left, result.cell_tails.?.right, result.probabilities.two_sided }) |total, actual| {
                try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(total)) / den, actual, 2e-15);
            }
        }
    };
}

test "wide 2x2 counts retain exact representable tail probabilities independent of orientation" {
    // For A=2^32 the opposing margins both equal 3. The denominator is
    // C(A+4,3); the observed mass is 3*(A+1)/C(A+4,3), and one still
    // rarer table contributes 1/C(A+4,3). These rational values distinguish
    // cancellation in log-gamma subtraction from SAS's own wide P_TABLE.
    const a: f64 = 4_294_967_296;
    const denominator = (a + 4) * (a + 3) * (a + 2) / 6;
    const observed = 3 * (a + 1) / denominator;
    const tail = (3 * (a + 1) + 1) / denominator;
    for ([_][4]f64{ .{ a, 1, 1, 2 }, .{ 1, a, 2, 1 }, .{ 1, 2, a, 1 }, .{ 2, 1, 1, a } }, [_]bool{ false, true, true, false }) |counts, reversed| {
        const m = tests.CountMatrix{ .rows = 2, .cols = 2, .counts = &counts };
        const f = (try run(std.testing.allocator, m, .fisher, .{})).fisher;
        try std.testing.expectApproxEqRel(observed, f.table_probability, 1e-14);
        try std.testing.expectApproxEqRel(observed, f.probabilities.point, 1e-14);
        try std.testing.expectApproxEqRel(tail, f.probabilities.two_sided, 1e-14);
        try std.testing.expectApproxEqRel(tail, if (reversed) f.cell_tails.?.left else f.cell_tails.?.right, 1e-14);
        try std.testing.expectEqual(@as(f64, 1), if (reversed) f.cell_tails.?.right else f.cell_tails.?.left);
        try std.testing.expectEqual(@as(u64, 4), f.probabilities.tables);
    }
}

test "two adjacent Fisher modes with unequal labeled multiplicity keep separate point probabilities" {
    const t = std.testing;
    // For the first pair (R+1)(C+1) mod (N+2) = 1. The adjacent
    // probability ratio differs from 1 by only 8.215e-15. Independent
    // 70-digit hypergeometric recurrence gives each mass and ordered tail.
    const n: u32 = 2_000_000_001;
    const r: u32 = 600_000;
    const c: u32 = 1_770_793_717;
    for ([_]u32{ 531_238, 531_239 }, [_]f64{ 0.99838292021760708595, 1.0 }, [_]f64{ 0.0016170797823929007618, 0.0016170797823929140463 }) |k, tail, mass| {
        const counts = [4]f64{ @floatFromInt(k), @floatFromInt(r - k), @floatFromInt(c - k), @floatFromInt(n - r - c + k) };
        const swapped = [4]f64{ counts[1], counts[0], counts[3], counts[2] };
        for ([_][]const f64{ &counts, &swapped }) |cells| {
            const result = (try run(t.allocator, .{ .rows = 2, .cols = 2, .counts = cells }, .fisher, .{})).fisher;
            try t.expectApproxEqRel(mass, result.probabilities.point, 2e-14);
            try t.expectApproxEqAbs(tail, result.probabilities.two_sided, 2e-14);
        }
    }
    // Each raw frequency is exactly representable as binary64. A feasible
    // neighbor moves it by one, far below an ulp of the large counts.
    for ([_]i32{ 85, 970 }) |exponent| {
        const m = std.math.ldexp(@as(f64, 1), exponent);
        const next = std.math.nextAfter(f64, m, std.math.inf(f64));
        const result = (try run(t.allocator, .{ .rows = 2, .cols = 2, .counts = &.{ 2, 1, m, next } }, .fisher, .{})).fisher;
        try t.expectApproxEqRel(@as(f64, 0.375), result.probabilities.point, 2e-15);
        try t.expectApproxEqRel(@as(f64, 0.625), result.probabilities.two_sided, 2e-15);
    }
}

test "exact conditional likelihood ratio includes all tables with the same cell multiset" {
    const t = std.testing;
    const counts = [_]f64{ 1, 0, 2, 1_000_001, 1_000_000, 999_999 };
    const other = [_]f64{ 2, 1, 0, 1_000_000, 999_999, 1_000_001 };
    for ([_][]const f64{ &counts, &other }) |cells| {
        const m = tests.CountMatrix{ .rows = 2, .cols = 3, .counts = cells };
        const result = (try run(t.allocator, m, .lrchi, .{})).exact_test;
        // Both tables have identical sum(X*log(X)) at fixed margins.
        // Three labeled draws give ten allocations and two tied tables.
        try t.expectEqual(@as(u64, 10), result.tables);
        try t.expectApproxEqRel(@as(f64, 0.22222244444417284), result.point, 3e-14);
        try t.expectApproxEqRel(@as(f64, 0.66666622222251852), result.two_sided, 3e-14);
    }
}

test "EXACT family dispatch binds actual callbacks to correct null distributions" {
    const t = std.testing;
    const paired = tests.CountMatrix{ .rows = 2, .cols = 2, .counts = &.{ 4, 0, 3, 1 } };
    const m = (try run(t.allocator, paired, .mcnem, .{})).exact_test;
    const f = (try run(t.allocator, paired, .fisher, .{})).fisher;
    try t.expectApproxEqAbs(@as(f64, 0.25), m.two_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), f.probabilities.two_sided, 1e-12);
    const one = tests.CountMatrix{ .rows = 1, .cols = 3, .counts = &.{ 0, 1, 3 } };
    const p = (try run(t.allocator, one, .lrchi, .{ .expected = .{ .proportions = &.{ 0.2, 0.3, 0.5 } } })).exact_test;
    try t.expectApproxEqAbs(@as(f64, 0.505), p.two_sided, 1e-12);
    const sparse = tests.CountMatrix{ .rows = 2, .cols = 3, .counts = &.{ 0, 1, 2, 2, 1, 0 } };
    const corr = (try run(t.allocator, sparse, .pcorr, .{})).exact_test;
    try t.expectApproxEqAbs(@as(f64, 0.1), corr.one_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.2), corr.two_sided, 1e-12);
    const trend = (try run(t.allocator, sparse, .trend, .{})).exact_test;
    try t.expectApproxEqAbs(@as(f64, 0.2), trend.two_sided, 1e-12);
    try t.expectError(error.ExecError, run(t.allocator, .{ .rows = 2, .cols = 2, .counts = &.{ 1, 2.5, 3, 4 } }, .fisher, .{}));
}

// Independent SAS family-callbacks.sas, fixed row/column margins on the
// synthetic 3x3 table below. Rounded listing oracle tolerance is 0.00005.
// This pins every conditional-family adapter, not just Fisher infrastructure.
test "all conditional EXACT family callbacks match SAS one two and point probabilities" {
    const t = std.testing;
    const m = tests.CountMatrix{ .rows = 3, .cols = 3, .counts = &.{ 3, 0, 1, 0, 2, 1, 1, 0, 2 } };
    const Case = struct { family: parse.Family, one: f64, two: f64, point: f64 };
    const cases = [_]Case{
        .{ .family = .pchi, .one = 0.1010, .two = 0.1010, .point = 0.0457 },
        .{ .family = .lrchi, .one = 0.2229, .two = 0.2229, .point = 0.1371 },
        .{ .family = .mhchi, .one = 0.3295, .two = 0.3295, .point = 0.1714 },
        .{ .family = .fisher, .one = 0.2229, .two = 0.2229, .point = 0.1371 },
        .{ .family = .pcorr, .one = 0.1648, .two = 0.3295, .point = 0.0857 },
        .{ .family = .scorr, .one = 0.1267, .two = 0.2533, .point = 0.0400 },
        .{ .family = .kentb, .one = 0.0905, .two = 0.1810, .point = 0.0114 },
        .{ .family = .stutc, .one = 0.0905, .two = 0.1810, .point = 0.0114 },
        .{ .family = .smdcr, .one = 0.0905, .two = 0.1810, .point = 0.0114 },
        .{ .family = .smdrc, .one = 0.0905, .two = 0.1810, .point = 0.0114 },
        .{ .family = .jt, .one = 0.0905, .two = 0.1810, .point = 0.0114 },
        .{ .family = .kappa, .one = 0.0267, .two = 0.0267, .point = 0.0219 },
        .{ .family = .wtkappa, .one = 0.0905, .two = 0.1200, .point = 0.0752 },
    };
    for (cases) |case| {
        const result = try run(t.allocator, m, case.family, .{});
        const p = if (case.family == .fisher) result.fisher.probabilities else result.exact_test;
        try t.expectApproxEqAbs(case.one, p.one_sided, 0.00005);
        try t.expectApproxEqAbs(case.two, p.two_sided, 0.00005);
        try t.expectApproxEqAbs(case.point, p.point, 0.00005);
    }
}

pub const StrataResult = union(enum) {
    common_odds: @import("freq_exact_strata.zig").Common,
    zelen: @import("freq_exact_strata.zig").Zelen,
    exhausted,
};
pub fn runStrata(a: std.mem.Allocator, strata: []const tests.CountMatrix, f: parse.Family, c: Config) Error!StrataResult {
    if (f != .comor and f != .eqor) return error.ExecError;
    if (strata.len == 0) return error.ExecError;
    const cells = try a.alloc([4]u32, strata.len);
    defer a.free(cells);
    for (strata, cells) |m, *out| {
        if (m.rows != 2 or m.cols != 2 or m.counts.len != 4) return error.ExecError;
        for (m.counts, 0..) |v, i| out[i] = try exact.integerCount(v);
    }
    const kernel = @import("freq_exact_strata.zig");
    if (f == .comor) {
        const result = try kernel.commonOdds(a, cells, c.alpha, c.budget);
        return switch (result) {
            .complete => |v| .{ .common_odds = v },
            .exhausted => .exhausted,
        };
    }
    const result = try kernel.zelen(a, cells, c.budget);
    return switch (result) {
        .complete => |v| .{ .zelen = v },
        .exhausted => .exhausted,
    };
}

test "public strata adapter keeps COMOR and Zelen distinct" {
    const t = std.testing;
    const strata = [_]tests.CountMatrix{ .{ .rows = 2, .cols = 2, .counts = &.{ 2, 0, 0, 2 } }, .{ .rows = 2, .cols = 2, .counts = &.{ 0, 2, 2, 0 } } };
    const common = (try runStrata(t.allocator, &strata, .comor, .{})).common_odds;
    const zelen = (try runStrata(t.allocator, &strata, .eqor, .{})).zelen;
    try t.expectApproxEqAbs(@as(f64, 0.5), common.point, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 9.0), zelen.p, 1e-12);
}

// SAS public/missing-scores.sas: TABLE fallback scores are for display only;
// SCORR/KENTB remain valid, PCORR/MHCHI are suppressed before any sampling.
test "exact adapter retains numeric score validity and undefined discordant tests" {
    const t = std.testing;
    const m = tests.CountMatrix{ .rows = 3, .cols = 2, .counts = &.{ 2, 1, 1, 3, 2, 2 }, .row_scores = &.{ 1, 2, 3 }, .col_scores = &.{ 1, 2 } };
    const config = Config{ .numeric_table_scores_valid = false };
    try t.expect((try run(t.allocator, m, .pcorr, config)) == .not_applicable);
    try t.expect((try run(t.allocator, m, .mhchi, config)) == .not_applicable);
    const rank = (try run(t.allocator, m, .scorr, config)).exact_test;
    try t.expectApproxEqAbs(@as(f64, 0.5087), rank.one_sided, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 1), rank.two_sided, 1e-12);
    // SAS degenerate-agreement.sas: missing McNemar, not p=1 or rc2.
    try t.expect((try run(t.allocator, .{ .rows = 2, .cols = 2, .counts = &.{ 5, 0, 0, 5 } }, .mcnem, .{})) == .not_applicable);
}

test "Barnard maximizes the opposing tail above the stack cutoff and keeps ordinary table budgets" {
    const m = tests.CountMatrix{ .rows = 2, .cols = 2, .counts = &.{ 0, 1, 129, 0 } };
    const result = try run(std.testing.allocator, m, .barnard, .{});
    // The one-sided event contains only the observed table. Its likelihood is
    // (1-p)*p^129, with an interior maximum at p=129/130.
    const one = 0.002840774943588005242286090151658295;
    try std.testing.expectApproxEqRel(@as(f64, one), result.barnard.tails.complete.one.upper, 2e-14);
    // M9 BY capture under full separation: the maximum on its grid is at
    // q=.0077. The continuous maximum is retained above.
    try std.testing.expectApproxEqAbs(@as(f64, 0.00284077351313), result.barnard.oneSided().?, 1e-14);
    try std.testing.expect(result.barnard.twoSided().? >= result.barnard.oneSided().?);
    try std.testing.expect((try run(std.testing.allocator, m, .barnard, .{ .budget = .{ .max_tables = 100 } })) == .barnard);
    const near = tests.CountMatrix{ .rows = 2, .cols = 2, .counts = &.{ 0, 2, 128, 1 } };
    try std.testing.expect((try run(std.testing.allocator, near, .barnard, .{ .budget = .{ .max_tables = 100 } })) == .exhausted);
}

test "native fixed-margin multinomial and symmetry MC use the same seeded uniform stream" {
    const a = std.testing.allocator;
    const m = tests.CountMatrix{ .rows = 3, .cols = 3, .counts = &.{ 1, 3, 1, 4, 3, 2, 3, 3, 3 } };
    const c = Config{ .effective_seed = 12, .options = .{ .mc = true, .samples = 500 } };
    const cases = [_]struct { family: parse.Family, table: tests.CountMatrix, hits: u64, final_seed: u64 }{
        .{ .family = .fisher, .table = m, .hits = 417, .final_seed = 534628942 },
        .{ .family = .symmetry, .table = m, .hits = 440, .final_seed = 1647258914 },
        .{ .family = .pchi, .table = .{ .rows = 1, .cols = 3, .counts = &.{ 5, 9, 9 } }, .hits = 274, .final_seed = 534628942 },
        .{ .family = .pchi, .table = .{ .rows = 2, .cols = 2, .counts = &.{ 1, 3, 4, 3 } }, .hits = 283, .final_seed = 1671574333 },
    };
    for (cases) |case| {
        const estimates = (try run(a, case.table, case.family, c)).monte_carlo.estimates.complete;
        try std.testing.expectEqual(@as(f64, @floatFromInt(case.hits)) / 500, estimates.two_sided.p);
        try std.testing.expectEqual(case.final_seed, estimates.final_seed);
    }
}

test "Barnard reported score respects equal risks and signed near-null row/column permutations" {
    // M9 null and permutation capture: [30,31;31,32] and its row, column,
    // and double swaps. The elementary pooled score also stays accessible.
    for ([_]f64{ 0, -0.002897613511751, 0.002897613511751 }, [_]f64{ 0, -0.00289760297503, 0.00289760297503 }) |z, native| {
        const r: Barnard = .{ .difference = z, .se = 1, .z = z, .tails = .exhausted };
        try std.testing.expectApproxEqAbs(native, r.reportedZ(), 1e-14);
    }
}

test "trend simulation sorts the binary response in either table dimension" {
    const a = std.testing.allocator;
    const config = Config{ .effective_seed = 51, .options = .{ .mc = true, .samples = 431 } };
    for ([_]tests.CountMatrix{
        .{ .rows = 2, .cols = 3, .counts = &.{ 1, 2, 0, 2, 1, 4 } },
        .{ .rows = 3, .cols = 2, .counts = &.{ 1, 2, 2, 1, 0, 4 } },
    }, [_]u64{ 113, 101 }, [_]u64{ 194, 179 }) |m, one, two| {
        const r = (try run(a, m, .trend, config)).monte_carlo.estimates.complete;
        try std.testing.expectEqual(@as(f64, @floatFromInt(one)) / 431, r.one_sided.p);
        try std.testing.expectEqual(@as(f64, @floatFromInt(two)) / 431, r.two_sided.p);
    }
}
