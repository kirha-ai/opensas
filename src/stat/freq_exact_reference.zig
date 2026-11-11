//! EXACT reference sets other than fixed row/column margins (FREQ pp.180,
//! 212–213,230–234). The statistic callback never determines the sampling law.
//! One-way CHISQ/PCHI/LRCHI use Multinomial(N,p0), fixing only total N.
//! MCNEM fixes D=n12+n21 and uses Binomial(D,r/(1+r)). SYMMETRY/BOWKER
//! fixes each n_ij+n_ji and uses independent Binomial(D_ij,1/2) splits.
//! Diagonals stay observed; neither symmetry law fixes row/column margins.
const std = @import("std");
const math = @import("../functions.zig");
const dist = @import("freq_exact_distribution.zig");
pub const Error = dist.Error;
const Matrix = dist.Matrix;
const Statistic = dist.Statistic;
const Budget = dist.Budget;
const Enumeration = dist.Enumeration;
fn lf(x: u32) f64 {
    return math.lgammaOf(@as(f64, @floatFromInt(x)) + 1);
}

const MultinomialSearch = struct {
    counts: []u32,
    probabilities: []const f64,
    statistic: Statistic,
    accumulator: dist.Accumulator,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    fn visit(self: *MultinomialSearch, k: usize, remaining: u32, log_weight: f64) Error!void {
        if (self.stopped) return;
        if (self.budget.stopped()) {
            self.stopped = true;
            return;
        }
        if (k == self.counts.len) {
            if (self.count == self.budget.max_tables) {
                self.stopped = true;
                return;
            }
            self.count += 1;
            const value = try self.statistic.evaluate(self.statistic.context, .{ .rows = 1, .cols = self.counts.len, .cells = self.counts });
            try self.accumulator.add(log_weight, value);
            return;
        }
        var x: u64 = if (k + 1 == self.counts.len) remaining else 0;
        while (x <= remaining) : (x += 1) {
            self.counts[k] = @intCast(x);
            try self.visit(k + 1, remaining - @as(u32, @intCast(x)), log_weight + @as(f64, @floatFromInt(x)) * @log(self.probabilities[k]) - lf(@intCast(x)));
            if (self.stopped) return;
        }
    }
};

pub fn multinomial(a: std.mem.Allocator, observed: []const u32, probabilities: []const f64, statistic: Statistic, budget: Budget) Error!Enumeration {
    if (observed.len == 0 or observed.len != probabilities.len) return error.ExecError;
    if (observed.len > 256) return .exhausted;
    var n: u64 = 0;
    var p: f64 = 0;
    for (observed, probabilities) |v, q| {
        n += v;
        if (n > std.math.maxInt(u32) or !std.math.isFinite(q) or q <= 0 or q > 1) return error.ExecError;
        p += q;
    }
    if (n == 0 or @abs(p - 1) > 1e-12) return error.ExecError;
    const value = try statistic.evaluate(statistic.context, .{ .rows = 1, .cols = observed.len, .cells = observed });
    if (!std.math.isFinite(value) or !std.math.isFinite(statistic.expected)) return error.ExecError;
    const cells = try a.alloc(u32, observed.len);
    defer a.free(cells);
    var search = MultinomialSearch{ .counts = cells, .probabilities = probabilities, .statistic = statistic, .accumulator = .{ .statistic = statistic, .observed = value }, .budget = budget };
    try search.visit(0, @intCast(n), 0); // N! is constant and cancels in normalization.
    if (search.stopped) return .exhausted;
    return .{ .complete = try search.accumulator.result(search.count) };
}

const Pair = struct { upper: usize, lower: usize, total: u32 };
const PairSearch = struct {
    cells: []u32,
    dimension: usize,
    pairs: []const Pair,
    log_p: f64,
    log_q: f64,
    statistic: Statistic,
    accumulator: dist.Accumulator,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    fn visit(self: *PairSearch, k: usize, log_weight: f64) Error!void {
        if (self.stopped) return;
        if (self.budget.stopped()) {
            self.stopped = true;
            return;
        }
        if (k == self.pairs.len) {
            if (self.count == self.budget.max_tables) {
                self.stopped = true;
                return;
            }
            self.count += 1;
            const value = try self.statistic.evaluate(self.statistic.context, .{ .rows = self.dimension, .cols = self.dimension, .cells = self.cells });
            try self.accumulator.add(log_weight, value);
            return;
        }
        const pair = self.pairs[k];
        var x: u64 = 0;
        while (x <= pair.total) : (x += 1) {
            const up: u32 = @intCast(x);
            const down = pair.total - up;
            self.cells[pair.upper] = up;
            self.cells[pair.lower] = down;
            const log_mass = lf(pair.total) - lf(up) - lf(down) + @as(f64, @floatFromInt(up)) * self.log_p + @as(f64, @floatFromInt(down)) * self.log_q;
            try self.visit(k + 1, log_weight + log_mass);
            if (self.stopped) return;
        }
    }
};

/// null_ratio is n12/n21 under H0 for 2x2; larger symmetry tables require 1.
/// Statistic should be dev5 mcnemar/bowker's unstandardized chi-square value.
pub fn symmetry(a: std.mem.Allocator, observed: Matrix, null_ratio: f64, statistic: Statistic, budget: Budget) Error!Enumeration {
    if (observed.rows != observed.cols or observed.rows < 2 or !std.math.isFinite(null_ratio) or null_ratio <= 0 or (observed.rows > 2 and null_ratio != 1)) return error.ExecError;
    if (observed.rows > 16) return .exhausted;
    if (observed.cells.len != observed.rows * observed.cols) return error.ExecError;
    const pairs = try a.alloc(Pair, observed.rows * (observed.rows - 1) / 2);
    defer a.free(pairs);
    var k: usize = 0;
    for (0..observed.rows) |i| for (i + 1..observed.cols) |j| {
        const up = i * observed.cols + j;
        const down = j * observed.cols + i;
        const total = @as(u64, observed.cells[up]) + observed.cells[down];
        if (total > std.math.maxInt(u32)) return error.ExecError;
        pairs[k] = .{ .upper = up, .lower = down, .total = @intCast(total) };
        k += 1;
    };
    const value = try statistic.evaluate(statistic.context, observed);
    if (!std.math.isFinite(value) or !std.math.isFinite(statistic.expected)) return error.ExecError;
    const cells = try a.dupe(u32, observed.cells);
    defer a.free(cells);
    // Avoid rounding p to 1 for a large but finite discordant odds ratio.
    const log_p = if (null_ratio < 1) @log(null_ratio) - std.math.log1p(null_ratio) else -std.math.log1p(1 / null_ratio);
    var search = PairSearch{ .cells = cells, .dimension = observed.rows, .pairs = pairs, .log_p = log_p, .log_q = -std.math.log1p(null_ratio), .statistic = statistic, .accumulator = .{ .statistic = statistic, .observed = value }, .budget = budget };
    try search.visit(0, 0);
    if (search.stopped) return .exhausted;
    return .{ .complete = try search.accumulator.result(search.count) };
}

// Production callback bindings come from the landed statistic owners.
const adapters = @import("freq_stratified_exact.zig");
const tests = @import("freq_tests.zig");
fn testPearson(_: ?*const anyopaque, m: Matrix) Error!f64 {
    var counts: [3]f64 = undefined;
    for (m.cells, 0..) |v, i| counts[i] = @floatFromInt(v);
    return (try tests.goodnessOfFit(&counts, .{ .proportions = &.{ 0.2, 0.3, 0.5 } }, null)).pearson.statistic;
}

// SAS generators.sas, manual pp.180,213,231; evidence under
// /tmp/opensas-stat-batch2/FEAT-freq-exact/. One-way is 15 multinomial
// outcomes, not one degenerate table obtained by fixing its column margins.
test "multinomial exact goodness of fit and budget" {
    const t = std.testing;
    const r = (try multinomial(t.allocator, &.{ 0, 1, 3 }, &.{ 0.2, 0.3, 0.5 }, .{ .evaluate = testPearson }, .{})).complete;
    try t.expectEqual(@as(u64, 15), r.tables);
    try t.expectApproxEqAbs(@as(f64, 0.712), r.two_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.285), r.point, 1e-12);
    try t.expect((try multinomial(t.allocator, &.{ 0, 1, 3 }, &.{ 0.2, 0.3, 0.5 }, .{ .evaluate = testPearson }, .{ .max_tables = 14 })) == .exhausted);
}

test "discordant pair laws discriminate from conditional independence" {
    const t = std.testing;
    const paired = Matrix{ .rows = 2, .cols = 2, .cells = &.{ 4, 0, 3, 1 } };
    const paired_context = try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 4, 0, 3, 1 } }, .mcnemar, null, 1);
    const m = (try symmetry(t.allocator, paired, 1, adapters.Adapters(dist).statistic(&paired_context), .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.25), m.two_sided, 1e-12); // Fisher = 1.
    const ratio: f64 = 2;
    const ratio_context = try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 4, 0, 3, 1 } }, .mcnemar, null, ratio);
    const m2 = (try symmetry(t.allocator, paired, ratio, adapters.Adapters(dist).statistic(&ratio_context), .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 1.0 / 27.0), m2.two_sided, 1e-12); // NOT twice smaller binomial tail.
    const square = Matrix{ .rows = 3, .cols = 3, .cells = &.{ 2, 3, 0, 0, 2, 2, 1, 0, 2 } };
    const square_context = try adapters.Context.init(.{ .rows = 3, .cols = 3, .counts = &.{ 2, 3, 0, 0, 2, 2, 1, 0, 2 } }, .symmetry, null, 1);
    const callback = adapters.Adapters(dist).statistic(&square_context);
    const r = (try symmetry(t.allocator, square, 1, callback, .{})).complete;
    try t.expectEqual(@as(u64, 24), r.tables);
    try t.expectApproxEqAbs(@as(f64, 0.125), r.two_sided, 1e-12);
    const wrong = (try dist.enumerate(t.allocator, square, callback, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 229.0 / 13860.0), wrong.two_sided, 1e-12);
    try t.expect((try symmetry(t.allocator, square, 1, callback, .{ .max_tables = 23 })) == .exhausted);
}
