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
    total: f64,
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
            const exact = @import("freq_exact.zig");
            const observed: f64 = @floatFromInt(x);
            const p = self.probabilities[k];
            const delta = @mulAdd(f64, -self.total, p, observed);
            const deviance = exact.poissonDeviance(observed, self.total * p, delta);
            self.counts[k] = @intCast(x);
            try self.visit(k + 1, remaining - @as(u32, @intCast(x)), log_weight - (exact.logFactorialCorrection(@intCast(x)) + deviance));
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
    var search = MultinomialSearch{ .counts = cells, .probabilities = probabilities, .total = @floatFromInt(n), .statistic = statistic, .accumulator = .{ .statistic = statistic, .observed = value }, .budget = budget };
    // Combine the multinomial factorial ratio and its cell weights as
    // log-factorial corrections minus deviances about N*p. Any residual
    // from a rounded sum(p) is identical for all allocations.
    try search.visit(0, @intCast(n), @import("freq_exact.zig").logFactorialCorrection(@intCast(n)));
    if (search.stopped) return .exhausted;
    return .{ .complete = try search.accumulator.result(search.count) };
}

/// Under discordant odds r, X has law Binomial(D,r/(1+r)) and the statistic
/// is (X-Dp)^2/(Dp(1-p)). Its upper tail consists of two disjoint binomial
/// tails, cut at the observation and its reflection about Dp (FREQ pp.212–213).
pub fn mcnemar(upper: u32, lower: u32, null_ratio: f64, budget: Budget) Error!Enumeration {
    const exact = @import("freq_exact.zig");
    if (!std.math.isFinite(null_ratio) or null_ratio <= 0) return error.ExecError;
    const sum = @as(u64, upper) + lower;
    if (sum == 0 or sum > std.math.maxInt(u32)) return error.ExecError;
    if (sum + 1 > budget.max_tables or budget.stopped()) return .exhausted;
    // Express the law using its less likely outcome, so p cannot round to 1.
    const ratio = if (null_ratio <= 1) null_ratio else 1 / null_ratio;
    const p = ratio / (1 + ratio);
    const k = if (null_ratio <= 1) upper else lower;
    const n: u32 = @intCast(sum);
    const control = exact.Control{ .context = budget.context, .expired = budget.expired };
    const observed = (try exact.binomialTailsControlled(k, n, p, control)) orelse return .exhausted;
    const total: f64 = @floatFromInt(n);
    const x: f64 = @floatFromInt(k);
    const delta = @mulAdd(f64, -total, p, x);
    const mirror = @mulAdd(f64, 2 * total, p, -x);
    const nearest = @round(mirror);
    const other_delta = @mulAdd(f64, -total, p, nearest);
    // Apply the reference enumerator's statistic tie tolerance. Factoring
    // the difference of squares keeps the test accurate near an integer cut.
    const difference = (nearest - x) * @mulAdd(f64, -2 * total, p, nearest + x);
    const scale = @max(total * p * (1 - p), @max(delta * delta, other_delta * other_delta));
    const tied = @abs(difference) <= dist.statistic_tolerance * scale;
    const below = delta <= 0;
    const cut: i64 = @intFromFloat(if (tied) nearest else if (below) @ceil(mirror) else @floor(mirror));
    const adjacent = @as(i64, k) + @as(i64, if (below) 1 else -1);
    const opposite = if (below) @max(cut, adjacent) else @min(cut, adjacent);
    var point = observed.point;
    var tail = if (below) observed.left else observed.right;
    if (opposite >= 0 and opposite <= n) {
        const other = (try exact.binomialTailsControlled(@intCast(opposite), n, p, control)) orelse return .exhausted;
        tail += if (below) other.right else other.left;
        if (tied and opposite == cut) point += other.point;
    }
    tail = if (opposite == adjacent) 1 else @min(1, tail);
    point = @min(1, point);
    return .{ .complete = .{
        .point = point,
        .left = @min(1, (1 - tail) + point),
        .right = tail,
        .two_sided = tail,
        .one_sided = tail,
        .tables = sum + 1,
    } };
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

test "McNemar tail and point reductions match integer enumeration at every split" {
    const t = std.testing;
    // Count labeled Bernoulli allocations with small integer odds a:b.
    // The ordering uses integer distance from the rational null expectation.
    for (1..13) |size| {
        const n: u32 = @intCast(size);
        for ([_][2]u32{ .{ 1, 1 }, .{ 1, 2 }, .{ 3, 2 }, .{ 2, 1 }, .{ 1, 4 } }) |odds| {
            const a = odds[0];
            const b = odds[1];
            const denominator: f64 = @floatFromInt(std.math.pow(u64, a + b, n));
            for (0..size + 1) |observation| {
                const k: u32 = @intCast(observation);
                const d = @abs(@as(i64, k * (a + b)) - n * a);
                var choose: u64 = 1;
                var point: u64 = 0;
                var left: u64 = 0;
                var right: u64 = 0;
                for (0..size + 1) |i| {
                    const x: u32 = @intCast(i);
                    const mass = choose * std.math.pow(u64, a, x) * std.math.pow(u64, b, n - x);
                    const distance = @abs(@as(i64, x * (a + b)) - n * a);
                    if (distance == d) point += mass;
                    if (distance <= d) left += mass;
                    if (distance >= d) right += mass;
                    if (x < n) choose = @divExact(choose * (n - x), x + 1);
                }
                const ratio = @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
                const result = (try mcnemar(k, n - k, ratio, .{})).complete;
                try t.expectEqual(size + 1, result.tables);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(point)) / denominator, result.point, 4e-14);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(left)) / denominator, result.left, 4e-14);
                try t.expectApproxEqRel(@as(f64, @floatFromInt(right)) / denominator, result.right, 4e-14);
                try t.expectEqual(result.right, result.two_sided);
                try t.expectEqual(result.right, result.one_sided);
            }
        }
    }
}

test "McNemar inverse odds, wide boundary probabilities and resources" {
    const t = std.testing;
    const n: u32 = 999_998;
    // The observed zero and all X >= 2 satisfy Q(X) >= Q(0), so the
    // tail is 1-P(1). The point is P(0). Evaluated at 90 decimal digits.
    const r = (try mcnemar(0, n, 1e-6, .{})).complete;
    try t.expectApproxEqRel(@as(f64, 0.63212037489001737380633), r.two_sided, 2e-15);
    try t.expectApproxEqRel(@as(f64, 0.36788036087070436760240), r.point, 2e-15);
    try t.expectEqual(r, (try mcnemar(n, 0, 1e6, .{})).complete);
    try t.expect((try mcnemar(n, 0, 1, .{ .max_tables = n })) == .exhausted);
    try t.expectError(error.ExecError, mcnemar(0, 0, 1, .{}));
    try t.expectError(error.ExecError, mcnemar(1, 2, 0, .{}));
    const Timer = struct {
        calls: usize = 0,
        fn expired(raw: ?*const anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(@constCast(raw.?)));
            self.calls += 1;
            return self.calls >= 16;
        }
    };
    var timer = Timer{};
    try t.expect((try mcnemar(500_000, 499_998, 1, .{ .context = &timer, .expired = Timer.expired })) == .exhausted);
    try t.expectEqual(@as(usize, 16), timer.calls);
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

const MultinomialSampler = struct {
    n: u32,
    probabilities: []const f64,
    fn draw(raw: ?*anyopaque, random: *dist.Generator, cells: []u32, budget: Budget) Error!bool {
        const self: *MultinomialSampler = @ptrCast(@alignCast(raw.?));
        @memset(cells, 0);
        for (0..self.n) |i| {
            if (i % 1024 == 0 and budget.stopped()) return false;
            const u = random.uniform();
            var cumulative: f64 = 0;
            for (self.probabilities, 0..) |p, j| {
                cumulative += p;
                if (u < cumulative or j + 1 == cells.len) {
                    cells[j] += 1;
                    break;
                }
            }
        }
        return true;
    }
};
pub fn multinomialMonteCarlo(a: std.mem.Allocator, observed: []const u32, probabilities: []const f64, statistic: Statistic, options: dist.Simulation, budget: Budget) Error!dist.MonteCarlo {
    if (observed.len == 0 or observed.len != probabilities.len) return error.ExecError;
    var n: u64 = 0;
    var p: f64 = 0;
    for (observed, probabilities) |v, q| {
        n += v;
        if (!std.math.isFinite(q) or q <= 0 or q > 1) return error.ExecError;
        p += q;
    }
    if (n == 0 or @abs(p - 1) > 1e-12) return error.ExecError;
    if (n > options.max_observations) return .exhausted;
    var context = MultinomialSampler{ .n = @intCast(n), .probabilities = probabilities };
    return dist.simulate(a, .{ .rows = 1, .cols = observed.len, .cells = observed }, statistic, options, budget, .{ .context = &context, .draw = MultinomialSampler.draw });
}
const SymmetryPair = struct { upper: usize, lower: usize, cdf: []f64 };
const SymmetrySampler = struct {
    observed: Matrix,
    pairs: []const SymmetryPair,
    fn draw(raw: ?*anyopaque, random: *dist.Generator, cells: []u32, budget: Budget) Error!bool {
        const self: *SymmetrySampler = @ptrCast(@alignCast(raw.?));
        @memcpy(cells, self.observed.cells);
        for (self.pairs) |pair| {
            if (budget.stopped()) return false;
            const u = random.uniform();
            var lo: usize = 0;
            var hi = pair.cdf.len - 1;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (u <= pair.cdf[mid]) hi = mid else lo = mid + 1;
            }
            cells[pair.upper] = @intCast(lo);
            cells[pair.lower] = @intCast(pair.cdf.len - 1 - lo);
        }
        return true;
    }
};

/// Normalize Binomial(n,1/2) around its mode. The actual mass at zero can
/// underflow for large pairs; centered weights never overflow.
fn symmetricBinomialCdf(cdf: []f64, budget: Budget) bool {
    const n = cdf.len - 1;
    const mode = n / 2;
    cdf[mode] = 1;
    var i = mode;
    while (i != 0) : (i -= 1) {
        if (i % 1024 == 0 and budget.stopped()) return false;
        cdf[i - 1] = cdf[i] * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - i + 1));
    }
    for (mode..n) |k| {
        if (k % 1024 == 0 and budget.stopped()) return false;
        cdf[k + 1] = cdf[k] * @as(f64, @floatFromInt(n - k)) / @as(f64, @floatFromInt(k + 1));
    }
    var sum: f64 = 0;
    for (cdf) |*x| {
        sum += x.*;
        x.* = sum;
    }
    for (cdf) |*x| x.* /= sum;
    return true;
}
/// MC is documented for SYMMETRY (R>2), not MCNEM. Same independent
/// complementary-pair Binomial(D_ij,.5) law as exact symmetry enumeration.
pub fn symmetryMonteCarlo(a: std.mem.Allocator, observed: Matrix, statistic: Statistic, options: dist.Simulation, budget: Budget) Error!dist.MonteCarlo {
    if (observed.rows != observed.cols or observed.rows < 3) return error.ExecError;
    const size = std.math.mul(usize, observed.rows, observed.cols) catch return error.ExecError;
    if (observed.cells.len != size) return error.ExecError;
    var total: u64 = 0;
    for (observed.cells) |v| {
        total += v;
        if (total > options.max_observations) return .exhausted;
    }
    const count = observed.rows * (observed.rows - 1) / 2;
    const pairs = try a.alloc(SymmetryPair, count);
    defer a.free(pairs);
    var used: usize = 0;
    defer for (pairs[0..used]) |pair| a.free(pair.cdf);
    // M9 visits all upper-triangular pairs in row order. Even an empty
    // pair advances the stream once. The diagonal remains fixed.
    for (0..observed.rows) |i| for (i + 1..observed.cols) |j| {
        if (budget.stopped()) return .exhausted;
        const upper = i * observed.cols + j;
        const lower = j * observed.cols + i;
        const n = observed.cells[upper] + observed.cells[lower];
        const cdf = try a.alloc(f64, @as(usize, n) + 1);
        pairs[used] = .{ .upper = upper, .lower = lower, .cdf = cdf };
        used += 1;
        if (!symmetricBinomialCdf(cdf, budget)) return .exhausted;
    };
    var context = SymmetrySampler{ .observed = observed, .pairs = pairs };
    return dist.simulate(a, observed, statistic, options, budget, .{ .context = &context, .draw = SymmetrySampler.draw });
}

test "MC multinomial and symmetry retain their distinct reference laws" {
    const t = std.testing;
    const options = dist.Simulation{ .samples = 20000, .seed = 12345 };
    const one = (try multinomialMonteCarlo(t.allocator, &.{ 0, 1, 3 }, &.{ 0.2, 0.3, 0.5 }, .{ .evaluate = testPearson }, options, .{})).complete;
    try t.expect(@abs(one.two_sided.p - 0.712) < 6 * @sqrt(@as(f64, 0.712 * 0.288 / 20000.0)));
    const square = Matrix{ .rows = 3, .cols = 3, .cells = &.{ 2, 3, 0, 0, 2, 2, 1, 0, 2 } };
    const context = try adapters.Context.init(.{ .rows = 3, .cols = 3, .counts = &.{ 2, 3, 0, 0, 2, 2, 1, 0, 2 } }, .symmetry, null, 1);
    const callback = adapters.Adapters(dist).statistic(&context);
    const sym = (try symmetryMonteCarlo(t.allocator, square, callback, options, .{})).complete;
    const again = (try symmetryMonteCarlo(t.allocator, square, callback, options, .{})).complete;
    try t.expectEqualDeep(sym, again);
    try t.expect(@abs(sym.two_sided.p - 0.125) < 6 * @sqrt(@as(f64, 0.125 * 0.875 / 20000.0)));
    try t.expect((try symmetryMonteCarlo(t.allocator, square, callback, options, .{ .max_tables = 1 })) == .exhausted);
}

test "symmetry row-ordered binomial pair draws preserve follow-on seed even for empty pairs" {
    const a = std.testing.allocator;
    const Case = struct { n: usize, cells: []const u32, seed: u64, samples: u64, hits: u64, final_seed: u64 };
    const cases = [_]Case{
        .{ .n = 4, .cells = &.{ 2, 4, 0, 2, 2, 1, 3, 0, 3, 1, 1, 1, 0, 2, 1, 3 }, .seed = 293, .samples = 367, .hits = 82, .final_seed = 466985135 },
        .{ .n = 4, .cells = &.{ 2, 4, 0, 0, 2, 1, 3, 0, 3, 1, 1, 1, 0, 2, 1, 3 }, .seed = 119, .samples = 389, .hits = 103, .final_seed = 1188982109 },
        .{ .n = 3, .cells = &.{ 2, 0, 1, 0, 1, 4, 5, 2, 1 }, .seed = 39, .samples = 319, .hits = 83, .final_seed = 19471677 },
    };
    for (cases) |c| {
        var counts: [16]f64 = undefined;
        for (c.cells, 0..) |value, i| counts[i] = @floatFromInt(value);
        const context = try adapters.Context.init(.{ .rows = c.n, .cols = c.n, .counts = counts[0..c.cells.len] }, .symmetry, null, 1);
        const callback = adapters.Adapters(dist).statistic(&context);
        const sampled = (try symmetryMonteCarlo(a, .{ .rows = c.n, .cols = c.n, .cells = c.cells }, callback, .{ .seed = c.seed, .samples = c.samples }, .{})).complete;
        try std.testing.expectEqual(c.final_seed, sampled.final_seed);
        try std.testing.expectEqual(@as(f64, @floatFromInt(c.hits)) / @as(f64, @floatFromInt(c.samples)), sampled.two_sided.p);
    }
}
