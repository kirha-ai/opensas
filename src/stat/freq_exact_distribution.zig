//! Conditional reference-set enumeration and Monte Carlo for FREQ exact tests.
//! Statistic callbacks permit integration without coupling the reference-set
//! algorithm to risk, association, agreement, or stratified renderers.
const std = @import("std");
const math = @import("../functions.zig");
pub const Error = @import("../diag.zig").Error;

pub const Matrix = struct {
    rows: usize,
    cols: usize,
    cells: []const u32,

    /// Allocates converted counts; caller frees cells. Validates every count
    /// before casting and bounds the total required by the sampling engine.
    pub fn fromCounts(a: std.mem.Allocator, rows: usize, cols: usize, counts: []const f64) Error!Matrix {
        const size = std.math.mul(usize, rows, cols) catch return error.ExecError;
        if (rows == 0 or cols == 0 or size != counts.len) return error.ExecError;
        const cells = try a.alloc(u32, size);
        errdefer a.free(cells);
        var total: u64 = 0;
        for (counts, cells) |value, *cell| {
            cell.* = try @import("freq_exact.zig").integerCount(value);
            total += cell.*;
            if (total > std.math.maxInt(u32)) return error.ExecError;
        }
        if (total == 0) return error.ExecError;
        return .{ .rows = rows, .cols = cols, .cells = cells };
    }
};
pub const Statistic = struct {
    context: ?*const anyopaque = null,
    evaluate: *const fn (?*const anyopaque, Matrix) Error!f64,
    /// Null expectation for directional distance-from-null two-sided tests.
    expected: f64 = 0,
    directional: bool = false,
};
pub const Budget = struct {
    max_tables: u64 = 1_000_000,
    /// Caller owns the clock; true means MAXTIME elapsed or cancellation.
    /// Checked at every search node, not just at complete tables.
    context: ?*const anyopaque = null,
    expired: ?*const fn (?*const anyopaque) bool = null,
    fn stopped(self: Budget) bool {
        return if (self.expired) |f| f(self.context) else false;
    }
};
pub const Probabilities = struct {
    point: f64,
    left: f64,
    right: f64,
    two_sided: f64,
    one_sided: f64,
    tables: u64,
};
/// A resource stop never returns a renormalized partial p-value.
pub const Enumeration = union(enum) { complete: Probabilities, exhausted };

const Shape = struct {
    rows: []u32,
    cols: []u32,
    total: u32,
    fn init(a: std.mem.Allocator, m: Matrix) Error!Shape {
        if (m.rows == 0 or m.cols == 0 or m.rows > 256 or m.cols > 256 or m.rows * m.cols > 256 or m.cells.len != m.rows * m.cols) return error.ExecError;
        const r = try a.alloc(u32, m.rows);
        errdefer a.free(r);
        const c = try a.alloc(u32, m.cols);
        errdefer a.free(c);
        @memset(r, 0);
        @memset(c, 0);
        var n: u64 = 0;
        for (m.cells, 0..) |v, i| {
            n += v;
            if (n > std.math.maxInt(u32)) return error.ExecError;
            r[i / m.cols] += v;
            c[i % m.cols] += v;
        }
        if (n == 0) return error.ExecError;
        return .{ .rows = r, .cols = c, .total = @intCast(n) };
    }
    fn deinit(self: Shape, a: std.mem.Allocator) void {
        a.free(self.rows);
        a.free(self.cols);
    }
};

fn close(x: f64, y: f64) bool {
    // 64 ulps at the scale of the statistic: only numerical equality, never
    // rounding statistics to decimal buckets (manual p.231).
    return @abs(x - y) <= 64 * std.math.floatEps(f64) * @max(1, @max(@abs(x), @abs(y)));
}
const Events = struct { point: bool, left: bool, right: bool, two: bool };
fn events(value: f64, observed: f64, s: Statistic) Events {
    const tied = close(value, observed);
    const distance = @abs(value - s.expected);
    const observed_distance = @abs(observed - s.expected);
    return .{
        .point = tied,
        .left = value < observed or tied,
        .right = value > observed or tied,
        .two = if (s.directional) distance > observed_distance or close(distance, observed_distance) else value > observed or tied,
    };
}

const Search = struct {
    m: Matrix,
    cells: []u32,
    r: []u32,
    c: []u32,
    s: Statistic,
    observed: f64,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    peak: f64 = -std.math.inf(f64),
    sums: [5]f64 = @splat(0), // total, point, left, right, two-sided
    fn visit(self: *Search, k: usize) Error!void {
        if (self.stopped) return;
        if (self.budget.stopped()) {
            self.stopped = true;
            return;
        }
        if (k == self.cells.len) {
            if (self.count == self.budget.max_tables) {
                self.stopped = true;
                return;
            }
            self.count += 1;
            const value = try self.s.evaluate(self.s.context, .{ .rows = self.m.rows, .cols = self.m.cols, .cells = self.cells });
            if (!std.math.isFinite(value)) return error.ExecError;
            var log_weight: f64 = 0;
            for (self.cells) |v| log_weight -= math.lgammaOf(@as(f64, @floatFromInt(v)) + 1);
            if (log_weight > self.peak) {
                const scale = @exp(self.peak - log_weight);
                for (&self.sums) |*v| v.* *= scale;
                self.peak = log_weight;
            }
            const weight = @exp(log_weight - self.peak);
            const e = events(value, self.observed, self.s);
            self.sums[0] += weight;
            if (e.point) self.sums[1] += weight;
            if (e.left) self.sums[2] += weight;
            if (e.right) self.sums[3] += weight;
            if (e.two) self.sums[4] += weight;
            return;
        }
        const i = k / self.m.cols;
        const j = k % self.m.cols;
        var remaining_cols: u64 = 0;
        for (self.c[j + 1 ..]) |v| remaining_cols += v;
        const lo: u32 = @intCast(@as(u64, self.r[i]) -| remaining_cols);
        const hi = @min(self.r[i], self.c[j]);
        if (lo > hi) return;
        // Last row is fixed; last column is already forced by lo==hi.
        var x: u64 = if (i + 1 == self.m.rows) self.c[j] else lo;
        while (x <= hi) : (x += 1) {
            const v: u32 = @intCast(x);
            self.cells[k] = v;
            self.r[i] -= v;
            self.c[j] -= v;
            try self.visit(k + 1);
            self.r[i] += v;
            self.c[j] += v;
            if (self.stopped or i + 1 == self.m.rows) return;
        }
    }
};

pub fn enumerate(a: std.mem.Allocator, m: Matrix, statistic: Statistic, budget: Budget) Error!Enumeration {
    if (m.rows > 256 or m.cols > 256 or (m.rows > 0 and m.cols > 256 / m.rows)) return .exhausted;
    const shape = try Shape.init(a, m);
    defer shape.deinit(a);
    if (!std.math.isFinite(statistic.expected)) return error.ExecError;
    const observed = try statistic.evaluate(statistic.context, m);
    if (!std.math.isFinite(observed)) return error.ExecError;
    const cells = try a.alloc(u32, m.cells.len);
    defer a.free(cells);
    var search = Search{ .m = m, .cells = cells, .r = shape.rows, .c = shape.cols, .s = statistic, .observed = observed, .budget = budget };
    try search.visit(0);
    if (search.stopped) return .exhausted;
    const sums = search.sums;
    if (sums[0] == 0) return error.ExecError;
    return .{ .complete = .{
        .point = sums[1] / sums[0],
        .left = sums[2] / sums[0],
        .right = sums[3] / sums[0],
        .two_sided = sums[4] / sums[0],
        .one_sided = (if (statistic.directional and observed <= statistic.expected) sums[2] else sums[3]) / sums[0],
        .tables = search.count,
    } };
}

/// Higher negative log probability is more extreme: fixed margins make the
/// factorial product sufficient for Fisher/Freeman-Halton probability ordering.
pub fn fisherStatistic(_: ?*const anyopaque, m: Matrix) Error!f64 {
    var value: f64 = 0;
    for (m.cells) |v| value += math.lgammaOf(@as(f64, @floatFromInt(v)) + 1);
    return value;
}

pub const Estimate = struct { p: f64, standard_error: f64, lower: f64, upper: f64 };
/// SAS/STAT p.234: variance denominator N-1, boundary confidence bounds
/// alpha^(1/N), not Clopper-Pearson and not a zero-width Wald interval.
pub fn estimate(hits: u64, n: u64, alpha: f64) Error!Estimate {
    if (n < 2 or hits > n or !std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.ExecError;
    const nf: f64 = @floatFromInt(n);
    const p = @as(f64, @floatFromInt(hits)) / nf;
    const se = @sqrt(p * (1 - p) / (nf - 1));
    const z = -(math.distQuantile(.normal, alpha / 2, &.{}) orelse return error.ExecError);
    return .{
        .p = p,
        .standard_error = se,
        .lower = if (hits == 0) 0 else if (hits == n) @exp(@log(alpha) / nf) else @max(0, p - z * se),
        .upper = if (hits == n) 1 else if (hits == 0) -std.math.expm1(@log(alpha) / nf) else @min(1, p + z * se),
    };
}
pub const MonteCarlo = union(enum) { complete: struct { point: Estimate, left: Estimate, right: Estimate, two_sided: Estimate, one_sided: Estimate, samples: u64 }, exhausted };
pub const Simulation = struct { samples: u64 = 10_000, seed: u64, alpha: f64 = 0.01, max_observations: u32 = 1_000_000 };

/// Uniformly shuffle column labels into fixed row slots: every table has its
/// conditional hypergeometric probability. Reproducible within this engine;
/// SAS's RNG stream is not claimed to match. Caller resolves nonpositive SAS
/// seeds from its clock and records the effective positive seed.
pub fn monteCarlo(a: std.mem.Allocator, m: Matrix, statistic: Statistic, options: Simulation, budget: Budget) Error!MonteCarlo {
    if (options.samples < 2 or options.seed == 0 or !std.math.isFinite(statistic.expected)) return error.ExecError;
    _ = try estimate(0, options.samples, options.alpha);
    if (m.rows > 256 or m.cols > 256 or (m.rows > 0 and m.cols > 256 / m.rows)) return .exhausted;
    const shape = try Shape.init(a, m);
    defer shape.deinit(a);
    if (shape.total > options.max_observations) return .exhausted;
    const observed = try statistic.evaluate(statistic.context, m);
    if (!std.math.isFinite(observed)) return error.ExecError;
    const labels = try a.alloc(u8, shape.total);
    defer a.free(labels);
    var pos: usize = 0;
    for (shape.cols, 0..) |v, j| {
        @memset(labels[pos..][0..v], @intCast(j));
        pos += v;
    }
    const cells = try a.alloc(u32, m.cells.len);
    defer a.free(cells);
    var prng = std.Random.DefaultPrng.init(options.seed);
    const random = prng.random();
    var hits: [5]u64 = @splat(0);
    var sample: u64 = 0;
    while (sample < options.samples) : (sample += 1) {
        if (sample == budget.max_tables or budget.stopped()) return .exhausted;
        // Explicit shuffle permits deadline checks even for large N.
        var remaining = labels.len;
        while (remaining > 1) {
            if (remaining % 1024 == 0 and budget.stopped()) return .exhausted;
            const j = random.uintLessThan(usize, remaining);
            remaining -= 1;
            std.mem.swap(u8, &labels[remaining], &labels[j]);
        }
        @memset(cells, 0);
        pos = 0;
        for (shape.rows, 0..) |v, i| {
            for (labels[pos..][0..v]) |j| cells[i * m.cols + j] += 1;
            pos += v;
        }
        const value = try statistic.evaluate(statistic.context, .{ .rows = m.rows, .cols = m.cols, .cells = cells });
        if (!std.math.isFinite(value)) return error.ExecError;
        const e = events(value, observed, statistic);
        if (e.point) hits[0] += 1;
        if (e.left) hits[1] += 1;
        if (e.right) hits[2] += 1;
        if (e.two) hits[3] += 1;
        if (if (statistic.directional and observed <= statistic.expected) e.left else e.right) hits[4] += 1;
    }
    return .{ .complete = .{ .point = try estimate(hits[0], sample, options.alpha), .left = try estimate(hits[1], sample, options.alpha), .right = try estimate(hits[2], sample, options.alpha), .two_sided = try estimate(hits[3], sample, options.alpha), .one_sided = try estimate(hits[4], sample, options.alpha), .samples = sample } };
}

fn firstCell(_: ?*const anyopaque, m: Matrix) Error!f64 {
    return @floatFromInt(m.cells[0]);
}
fn expired(_: ?*const anyopaque) bool {
    return true;
}

// Oracle: /tmp/opensas-stat-batch2/FEAT-freq-exact/primitives-v2.sas
// sasrun <absolute probe> -f text -o <output.txt> -l <output.log>.
// Fisher POINT=0.0027 includes both tied tables, not just observed mass 0.0013.
// reference-sets.sas: 2x3 Fisher p=0.6000, POINT=0.6000, mid-p=0.3000.
test "fixed-margin Fisher enumeration includes ties, sparse cells and stop status" {
    const t = std.testing;
    const m = Matrix{ .rows = 2, .cols = 2, .cells = &.{ 1, 9, 11, 3 } };
    const s = Statistic{ .evaluate = fisherStatistic };
    const result = (try enumerate(t.allocator, m, s, .{})).complete;
    try t.expectEqual(@as(u64, 11), result.tables);
    try t.expectApproxEqAbs(@as(f64, 0.002759456185220), result.two_sided, 1e-12);
    // Swapped rows have the same probability; POINT includes both tied tables.
    try t.expectApproxEqAbs(@as(f64, 2 * 0.001346076187912), result.point, 1e-12);
    try t.expect((try enumerate(t.allocator, m, s, .{ .max_tables = 10 })) == .exhausted);
    try t.expect((try enumerate(t.allocator, m, s, .{ .expired = expired })) == .exhausted);
    const sparse = Matrix{ .rows = 2, .cols = 3, .cells = &.{ 0, 1, 2, 2, 1, 0 } };
    const r = (try enumerate(t.allocator, sparse, s, .{})).complete;
    try t.expectEqual(@as(u64, 7), r.tables);
    try t.expectApproxEqAbs(@as(f64, 0.6), r.two_sided, 1e-12);
}

test "directional two-sided exact statistic uses distance from null" {
    const t = std.testing;
    const m = Matrix{ .rows = 2, .cols = 2, .cells = &.{ 1, 9, 11, 3 } };
    const r = (try enumerate(t.allocator, m, .{ .evaluate = firstCell, .expected = 5, .directional = true }, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.001379728092610), r.one_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.002759456185220), r.two_sided, 1e-12);
    const skew = (try enumerate(t.allocator, .{ .rows = 2, .cols = 2, .cells = &.{ 0, 2, 2, 3 } }, .{ .evaluate = firstCell, .expected = 4.0 / 7.0, .directional = true }, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 10.0 / 21.0), skew.one_sided, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 11.0 / 21.0), skew.two_sided, 1e-12);
}

test "Monte Carlo reproducibility, enumeration agreement and confidence endpoints" {
    const t = std.testing;
    const m = Matrix{ .rows = 2, .cols = 3, .cells = &.{ 0, 1, 2, 2, 1, 0 } };
    const s = Statistic{ .evaluate = fisherStatistic };
    const opts = Simulation{ .seed = 12345, .samples = 20_000 };
    const x = (try monteCarlo(t.allocator, m, s, opts, .{})).complete;
    const y = (try monteCarlo(t.allocator, m, s, opts, .{})).complete;
    try t.expectEqualDeep(x, y);
    // SAS reference-sets.sas with the same seed/N gives 0.5965, 99% CI
    // [0.5876, 0.6054]. Streams differ; the target is exact enumeration 0.6.
    // Six standard errors is a statistical tolerance, not exact SAS RNG parity.
    try t.expect(@abs(x.two_sided.p - 0.6) < 6 * @sqrt(@as(f64, 0.6 * 0.4 / 20_000.0)));
    const z = try estimate(0, 10_000, 0.01);
    const one = try estimate(10_000, 10_000, 0.01);
    try t.expectApproxEqAbs(@as(f64, 0.000460410996912), z.upper, 1e-15);
    try t.expectApproxEqAbs(1 - z.upper, one.lower, 1e-15);
    const half = try estimate(50, 100, 0.01);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 0.25 / 99.0)), half.standard_error, 1e-15);
    try t.expect((try monteCarlo(t.allocator, m, s, opts, .{ .max_tables = 1 })) == .exhausted);
}

test "public matrix conversion checks fractional counts and aggregate overflow" {
    const t = std.testing;
    const m = try Matrix.fromCounts(t.allocator, 2, 2, &.{ 0, 2, 3, 4 });
    defer t.allocator.free(m.cells);
    try t.expectEqualSlices(u32, &.{ 0, 2, 3, 4 }, m.cells);
    try t.expectError(error.ExecError, Matrix.fromCounts(t.allocator, 2, 2, &.{ 0, 2.5, 3, 4 }));
    try t.expectError(error.ExecError, Matrix.fromCounts(t.allocator, 1, 2, &.{ 4294967295, 1 }));
    try t.expectError(error.ExecError, Matrix.fromCounts(t.allocator, 2, 2, &.{ 1, 2 }));
}
