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
pub const Result = union(enum) {
    exact_test: dist.Probabilities,
    fisher: struct { table_probability: f64, first_cell: ?u32, cell_tails: ?exact.Tails, probabilities: dist.Probabilities },
    monte_carlo: dist.MonteCarlo,
    binomial: exact.Binomial,
    interval: exact.Interval,
    risk_intervals: struct { first: ?exact.Interval = null, second: ?exact.Interval = null },
    barnard: struct { one: unconditional.Bounds, two: unconditional.Bounds },
    exhausted,
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
            // Existing contingency also computes automatic Fisher on 2x2;
            // asymptotic statistics are reused rather than reimplemented.
            const r = try tests.contingency(self.allocator, matrix, null);
            return if (self.family == .pchi) r.pearson.statistic else r.likelihood_ratio.statistic;
        }
        const r = try tests.association(self.allocator, matrix, 0.05);
        return switch (self.family) {
            .pcorr => r.pearson.estimate,
            .scorr => r.spearman.estimate,
            .kentb => r.tau_b.estimate,
            .stutc => r.tau_c.estimate,
            .smdcr => r.somers_cr.estimate,
            .smdrc => r.somers_rc.estimate,
            else => null,
        } orelse error.ExecError;
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
/// Group options must be expanded by Options.expanded before calling this.
pub fn run(a: std.mem.Allocator, m: tests.CountMatrix, f: parse.Family, c: Config) Error!Result {
    if (f == .comor or f == .eqor) return .requires_strata;
    if (!c.numeric_table_scores_valid and (f == .pcorr or f == .mhchi)) return .not_applicable;
    if (f == .agree or f == .chisq or f == .measures) return error.ExecError;
    if (!applicable(f, m)) return .not_applicable;
    if (f == .mcnem and m.counts.len == 4 and m.counts[1] + m.counts[2] == 0) return .not_applicable;
    if (m.counts.len > 256) return .exhausted;
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
            const delta = m.counts[0] / (m.counts[0] + m.counts[1]) - m.counts[2] / (m.counts[2] + m.counts[3]);
            const one = try unconditional.riskTail(table, .first, .difference, .score, 0, if (delta > 0) .right else .left, .{ .budget = c.budget });
            const two = try unconditional.riskTail(table, .first, .difference, .score, 0, .two_sided, .{ .budget = c.budget });
            if (one == .exhausted or two == .exhausted) return .exhausted;
            return .{ .barnard = .{ .one = one.complete, .two = two.complete } };
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
        .pcorr, .scorr, .kentb, .stutc, .smdcr, .smdrc => true,
        else => false,
    } };
    var sc: adapters.Context = undefined;
    var weights: ?[]f64 = null;
    defer if (weights) |w| a.free(w);
    const sf: ?adapters.Family = switch (f) {
        .jt => .jonckheere,
        .trend => .trend,
        .kappa => .kappa,
        .wtkappa => .weighted_kappa,
        .mhchi => .mhchi,
        .mcnem => .mcnemar,
        .symmetry => .symmetry,
        else => null,
    };
    if (sf) |family| {
        const sm = stratified.Matrix{ .rows = m.rows, .cols = m.cols, .counts = m.counts, .row_scores = m.row_scores, .col_scores = m.col_scores };
        if (f == .wtkappa) weights = try stratified.kappaWeights(a, sm, c.kappa_weight);
        sc = try adapters.Context.init(sm, family, weights, c.null_ratio);
        callback = adapters.Adapters(dist).statistic(&sc);
    } else if (f == .fisher) callback = .{ .evaluate = dist.fisherStatistic };
    const simulation = dist.Simulation{ .seed = c.effective_seed, .samples = c.options.samples, .alpha = c.options.alpha };
    const mc = c.options.mc and parse.supportsMonteCarlo(f, m.rows, m.cols);
    if (m.rows == 1) {
        var total: f64 = 0;
        for (m.counts) |v| total += v;
        const factor = try tests.expectedFactor(m.cols, total, c.expected);
        const probabilities = try a.alloc(f64, m.cols);
        defer a.free(probabilities);
        for (probabilities, 0..) |*p, i| p.* = switch (c.expected) {
            .equal => 1 / @as(f64, @floatFromInt(m.cols)),
            .proportions, .frequencies => |v| v[i] * factor / total,
        };
        if (mc) return .{ .monte_carlo = try reference.multinomialMonteCarlo(a, integers.cells, probabilities, callback, simulation, c.budget) };
        return finish(try reference.multinomial(a, integers.cells, probabilities, callback, c.budget));
    }
    if (f == .symmetry or f == .mcnem) {
        if (mc) return .{ .monte_carlo = try reference.symmetryMonteCarlo(a, integers, callback, simulation, c.budget) };
        return finish(try reference.symmetry(a, integers, if (f == .mcnem) c.null_ratio else 1, callback, c.budget));
    }
    if (mc) return .{ .monte_carlo = try dist.monteCarlo(a, integers, callback, simulation, c.budget) };
    const enumerated = try dist.enumerate(a, integers, callback, c.budget);
    if (f == .fisher) {
        if (enumerated == .exhausted) return .exhausted;
        const two = m.rows == 2 and m.cols == 2;
        return .{ .fisher = .{ .table_probability = try dist.tableProbability(integers), .first_cell = if (two) integers.cells[0] else null, .cell_tails = if (two) try (try exact.OddsDistribution.init(integers.cells[0..4].*)).tails(0, c.budget.max_tables) else null, .probabilities = enumerated.complete } };
    }
    return finish(enumerated);
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
