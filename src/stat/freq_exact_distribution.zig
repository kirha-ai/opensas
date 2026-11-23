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
    /// The conditional network compares raw linear scores in their own units.
    absolute_tolerance: ?f64 = null,
    /// An integer numerator with a fixed positive denominator and null zero.
    /// Only its sign is needed in floating point to select the one-sided tail.
    centered_integer: ?CenteredInteger = null,

    fn tied(self: Statistic, a: f64, b: f64) bool {
        if (self.absolute_tolerance) |tolerance| return @abs(a - b) <= tolerance;
        return close(a, b);
    }

    fn observedValue(self: Statistic, m: Matrix, law: ?*const FixedLaw) Error!f64 {
        if (self.centered_integer) |integer| return @floatFromInt(integer.observed);
        if (law) |fixed| return -fixed.logProbability(m.cells);
        return self.evaluate(self.context, m);
    }
};
pub const Budget = struct {
    max_tables: u64 = 1_000_000,
    /// Caller owns the clock; true means MAXTIME elapsed or cancellation.
    /// Checked at every search node, not just at complete tables.
    context: ?*const anyopaque = null,
    expired: ?*const fn (?*const anyopaque) bool = null,
    pub fn stopped(self: Budget) bool {
        return if (self.expired) |f| f(self.context) else false;
    }
};
pub const Probabilities = struct {
    point: f64,
    left: f64,
    right: f64,
    two_sided: f64,
    one_sided: f64,
    /// Chosen from the observed statistic and its null expectation, including
    /// when both inclusive tails have the same mass.
    right_sided: bool = false,
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

// Numerical equality at the scale of the statistic (manual p.231).
pub const statistic_tolerance = 64 * std.math.floatEps(f64);
fn close(x: f64, y: f64) bool {
    return @abs(x - y) <= statistic_tolerance * @max(1, @max(@abs(x), @abs(y)));
}
const Events = struct { point: bool, left: bool, right: bool, two: bool };
pub const CenteredInteger = struct {
    observed: i128,
    score: *const fn (?*const anyopaque, Matrix) i128,

    fn compare(self: CenteredInteger, context: ?*const anyopaque, m: Matrix) Events {
        const value = self.score(context, m);
        return .{ .point = value == self.observed, .left = value <= self.observed, .right = value >= self.observed, .two = @abs(value) >= @abs(self.observed) };
    }
};
fn events(value: f64, observed: f64, s: Statistic) Events {
    const tied = s.tied(value, observed);
    const distance = @abs(value - s.expected);
    const observed_distance = @abs(observed - s.expected);
    return .{
        .point = tied,
        .left = value < observed or tied,
        .right = value > observed or tied,
        .two = if (s.directional) distance > observed_distance or s.tied(distance, observed_distance) else value > observed or tied,
    };
}

/// Shared tail summation; reference-set generators own their probability law.
pub const Accumulator = struct {
    statistic: Statistic,
    observed: f64,
    peak: f64 = -std.math.inf(f64),
    sums: [5]f64 = @splat(0),
    pub fn add(self: *Accumulator, log_weight: f64, value: f64) Error!void {
        if (!std.math.isFinite(value)) return error.ExecError;
        return self.addEvents(log_weight, events(value, self.observed, self.statistic));
    }
    fn addEvents(self: *Accumulator, log_weight: f64, e: Events) Error!void {
        if (!std.math.isFinite(self.observed) or !std.math.isFinite(self.statistic.expected)) return error.ExecError;
        if (log_weight == -std.math.inf(f64)) return;
        if (!std.math.isFinite(log_weight)) return error.ExecError;
        if (log_weight > self.peak) {
            const scale = @exp(self.peak - log_weight);
            for (&self.sums) |*v| v.* *= scale;
            self.peak = log_weight;
        }
        const w = @exp(log_weight - self.peak);
        self.sums[0] += w;
        if (e.point) self.sums[1] += w;
        if (e.left) self.sums[2] += w;
        if (e.right) self.sums[3] += w;
        if (e.two) self.sums[4] += w;
    }
    pub fn result(self: Accumulator, count: u64) Error!Probabilities {
        const s = self.sums;
        if (s[0] <= 0) return error.ExecError;
        const right = self.observed > self.statistic.expected;
        return .{ .point = s[1] / s[0], .left = s[2] / s[0], .right = s[3] / s[0], .two_sided = s[4] / s[0], .one_sided = (if (self.statistic.directional and !right) s[2] else s[3]) / s[0], .right_sided = right, .tables = count };
    }
};

pub const Visitor = struct { context: ?*anyopaque, visit: *const fn (?*anyopaque, Matrix, f64) Error!void };

/// Conditional table probabilities have the factorial ratio prod(R!)*prod(C!)
/// / (N!*prod(X!)). Collect its entropy terms as cell deviances about R*C/N.
/// The remaining log-factorial corrections grow only logarithmically.
const FixedLaw = struct {
    n: u32,
    products: [256]u64 = undefined,
    correction: f64,
    fn init(rows: []const u32, cols: []const u32, n: u32) FixedLaw {
        const exact = @import("freq_exact.zig");
        var law = FixedLaw{ .n = n, .correction = -exact.logFactorialCorrection(n) };
        for (rows, 0..) |r, i| {
            law.correction += exact.logFactorialCorrection(r);
            for (cols, 0..) |c, j| law.products[i * cols.len + j] = @as(u64, r) * c;
        }
        for (cols) |c| law.correction += exact.logFactorialCorrection(c);
        return law;
    }
    fn logProbability(self: *const FixedLaw, cells: []const u32) f64 {
        const exact = @import("freq_exact.zig");
        const total: f64 = @floatFromInt(self.n);
        var log_mass = self.correction;
        var compensation: f64 = 0;
        for (cells, self.products[0..cells.len]) |x, expected_product| {
            if (expected_product == 0) continue;
            const mean = @as(f64, @floatFromInt(expected_product)) / total;
            // Compute X*N-R*C in integers before conversion; these products
            // can be almost equal even when neither fits exactly in a double.
            const delta_n = @as(i128, x) * self.n - expected_product;
            const delta = @as(f64, @floatFromInt(delta_n)) / total;
            const decrement = exact.logFactorialCorrection(x) + exact.poissonDeviance(@floatFromInt(x), mean, delta);
            const corrected = -decrement - compensation;
            const next = log_mass + corrected;
            compensation = (next - log_mass) - corrected;
            log_mass = next;
        }
        return @min(0, log_mass);
    }
    // Only use this floating-point window to select the exact integer
    // comparator. A logarithm close to zero can lose digits relative to the
    // margin correction and the nonnegative terms subtracted from it.
    fn overlaps(self: *const FixedLaw, x: f64, y: f64) bool {
        return @abs(x - y) <= statistic_tolerance * (1 + 2 * @abs(self.correction) + @abs(x) + @abs(y));
    }
    fn fromMatrix(m: Matrix) Error!FixedLaw {
        if (m.rows == 0 or m.cols == 0 or m.rows > 256 or m.cols > 256 / m.rows or m.cells.len != m.rows * m.cols) return error.ExecError;
        var rows: [256]u32 = @splat(0);
        var cols: [256]u32 = @splat(0);
        var total: u64 = 0;
        for (m.cells, 0..) |v, i| {
            total += v;
            if (total > std.math.maxInt(u32)) return error.ExecError;
            rows[i / m.cols] += v;
            cols[i % m.cols] += v;
        }
        if (total == 0) return error.ExecError;
        return init(rows[0..m.rows], cols[0..m.cols], @intCast(total));
    }
};

const BigInt = std.math.big.int.Managed;

/// Product of (lo,hi]. Small intervals fit a machine word. Larger ones use
/// a balanced product tree, with the procedure deadline checked at each node.
fn factorialRange(comptime Count: type, a: std.mem.Allocator, lo: Count, hi: Count, budget: Budget) Error!?BigInt {
    if (budget.stopped()) return null;
    if (lo == hi) return try BigInt.initSet(a, 1);
    if (hi - lo == 1) return try BigInt.initSet(a, hi);
    var product: u64 = 1;
    var x = lo;
    while (x < hi and hi <= std.math.maxInt(u64)) {
        x += 1;
        const next = @mulWithOverflow(product, @as(u64, @intCast(x)));
        if (next[1] != 0) break;
        product = next[0];
        if (x == hi) return try BigInt.initSet(a, product);
    }
    const mid = lo + (hi - lo) / 2;
    var left = (try factorialRange(Count, a, lo, mid, budget)) orelse return null;
    defer left.deinit();
    var right = (try factorialRange(Count, a, mid, hi, budget)) orelse return null;
    defer right.deinit();
    var result = try BigInt.init(a);
    errdefer result.deinit();
    try result.mul(&left, &right);
    return result;
}

/// Fixed margins make Fisher ordering an integer comparison of products of
/// cell factorials. Use it when log probabilities cannot separate two tables.
/// Sorting cancels common factorials and minimizes the remaining factor count.
pub fn fisherFactorialOrder(comptime Count: type, comptime max_cells: usize, a: std.mem.Allocator, sampled: []const Count, observed: []const Count, budget: Budget) Error!?std.math.Order {
    if (sampled.len != observed.len or sampled.len > max_cells) return error.ExecError;
    if (std.mem.eql(Count, sampled, observed)) return .eq;
    var samples: [max_cells]Count = undefined;
    var observations: [max_cells]Count = undefined;
    const lhs = samples[0..sampled.len];
    const rhs = observations[0..observed.len];
    @memcpy(lhs, sampled);
    @memcpy(rhs, observed);
    std.mem.sort(Count, lhs, {}, std.sort.asc(Count));
    std.mem.sort(Count, rhs, {}, std.sort.asc(Count));
    if (std.mem.eql(Count, lhs, rhs)) return .eq;

    var temp = std.heap.stackFallback(2048, a);
    const scratch = temp.get();
    var left = try BigInt.initSet(scratch, 1);
    defer left.deinit();
    var right = try BigInt.initSet(scratch, 1);
    defer right.deinit();
    for (lhs, rhs) |x, y| {
        if (x == y) continue;
        var factor = (try factorialRange(Count, scratch, @min(x, y), @max(x, y), budget)) orelse return null;
        defer factor.deinit();
        const side = if (x > y) &left else &right;
        try side.mul(side, &factor);
    }
    return BigInt.order(left, right);
}
fn fisherTie(a: std.mem.Allocator, sampled: []const u32, observed: []const u32, budget: Budget) Error!?Events {
    const order = (try fisherFactorialOrder(u32, 256, a, sampled, observed, budget)) orelse return null;
    return .{ .point = order == .eq, .left = order != .gt, .right = order != .lt, .two = order != .lt };
}

const Search = struct {
    allocator: std.mem.Allocator,
    m: Matrix,
    law: FixedLaw,
    cells: []u32,
    r: []u32,
    c: []u32,
    s: Statistic,
    observed: f64,
    budget: Budget,
    count: u64 = 0,
    stopped: bool = false,
    accumulator: Accumulator,
    visitor: ?Visitor = null,
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
            const sampled = Matrix{ .rows = self.m.rows, .cols = self.m.cols, .cells = self.cells };
            const log_weight = self.law.logProbability(self.cells);
            if (self.visitor) |v| {
                try v.visit(v.context, sampled, log_weight);
                return;
            }
            if (self.s.centered_integer) |integer| {
                try self.accumulator.addEvents(log_weight, integer.compare(self.s.context, sampled));
                return;
            }
            if (self.s.evaluate == fisherStatistic and self.law.overlaps(-log_weight, self.observed)) {
                // Fixed-margin tables are connected by unit 2x2 moves. Each
                // move covers L1 distance at most four. This pair alone can
                // prove that enumeration exceeds its table budget, before a
                // potentially large exact factorial comparison is attempted.
                var distance: u64 = 0;
                for (self.cells, self.m.cells) |x, y| distance += @max(x, y) - @min(x, y);
                if ((distance + 3) / 4 >= self.budget.max_tables) {
                    self.stopped = true;
                    return;
                }
                const e = (try fisherTie(self.allocator, self.cells, self.m.cells, self.budget)) orelse {
                    self.stopped = true;
                    return;
                };
                try self.accumulator.addEvents(log_weight, e);
            } else {
                const value = if (self.s.evaluate == fisherStatistic) -log_weight else try self.s.evaluate(self.s.context, sampled);
                try self.accumulator.add(log_weight, value);
            }
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

/// Streams each conditional table to a joint-stratum consumer. Borrowed cells
/// are valid only during visit. False reports resource exhaustion.
pub fn visitFixed(a: std.mem.Allocator, m: Matrix, budget: Budget, visitor: Visitor) Error!bool {
    if (m.rows > 256 or m.cols > 256 or (m.rows > 0 and m.cols > 256 / m.rows)) return false;
    var empty = true;
    for (m.cells) |v| {
        if (v != 0) empty = false;
    }
    if (empty) {
        if (m.rows == 0 or m.cols == 0 or m.cells.len != m.rows * m.cols) return error.ExecError;
        if (budget.max_tables == 0 or budget.stopped()) return false;
        try visitor.visit(visitor.context, m, 0);
        return true;
    }
    const shape = try Shape.init(a, m);
    defer shape.deinit(a);
    const cells = try a.alloc(u32, m.cells.len);
    defer a.free(cells);
    const stat = Statistic{ .evaluate = fisherStatistic };
    var search = Search{ .allocator = a, .m = m, .law = FixedLaw.init(shape.rows, shape.cols, shape.total), .cells = cells, .r = shape.rows, .c = shape.cols, .s = stat, .observed = 0, .budget = budget, .accumulator = .{ .statistic = stat, .observed = 0 }, .visitor = visitor };
    try search.visit(0);
    return !search.stopped;
}

pub fn enumerate(a: std.mem.Allocator, m: Matrix, statistic: Statistic, budget: Budget) Error!Enumeration {
    if (m.rows > 256 or m.cols > 256 or (m.rows > 0 and m.cols > 256 / m.rows)) return .exhausted;
    const shape = try Shape.init(a, m);
    defer shape.deinit(a);
    if (!std.math.isFinite(statistic.expected)) return error.ExecError;
    const law = FixedLaw.init(shape.rows, shape.cols, shape.total);
    const observed = try statistic.observedValue(m, if (statistic.evaluate == fisherStatistic) &law else null);
    if (!std.math.isFinite(observed)) return error.ExecError;
    const cells = try a.alloc(u32, m.cells.len);
    defer a.free(cells);
    var search = Search{ .allocator = a, .m = m, .law = law, .cells = cells, .r = shape.rows, .c = shape.cols, .s = statistic, .observed = observed, .budget = budget, .accumulator = .{ .statistic = statistic, .observed = observed } };
    try search.visit(0);
    if (search.stopped) return .exhausted;
    return .{ .complete = try search.accumulator.result(search.count) };
}

/// Higher negative log conditional probability is more extreme in the
/// Fisher/Freeman-Halton ordering. Keep the observed and sampled scale identical.
pub fn fisherStatistic(_: ?*const anyopaque, m: Matrix) Error!f64 {
    const law = try FixedLaw.fromMatrix(m);
    return -law.logProbability(m.cells);
}

pub const Estimate = struct { p: f64, standard_error: f64, lower: f64, upper: f64 };
/// SAS/STAT p.234: variance denominator N-1, boundary confidence bounds
/// alpha^(1/N), not Clopper-Pearson and not a zero-width Wald interval.
pub fn estimate(hits: u64, n: u64, alpha: f64) Error!Estimate {
    if (n == 0 or hits > n or !std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1) return error.ExecError;
    const nf: f64 = @floatFromInt(n);
    const p = @as(f64, @floatFromInt(hits)) / nf;
    const se = if (n == 1) @as(f64, 0) else @sqrt(p * (1 - p) / (nf - 1));
    const z = -(math.distQuantile(.normal, alpha / 2, &.{}) orelse return error.ExecError);
    return .{
        .p = p,
        .standard_error = se,
        .lower = if (hits == 0) 0 else if (hits == n) @exp(@log(alpha) / nf) else @max(0, p - z * se),
        .upper = if (hits == n) 1 else if (hits == 0) -std.math.expm1(@log(alpha) / nf) else @min(1, p + z * se),
    };
}
pub const SampleReport = struct {
    one_sided: ?Estimate = null,
    two_sided: ?Estimate = null,
    samples: u64,
    right_sided: bool,
};
pub const MonteCarlo = union(enum) {
    complete: struct { point: Estimate, left: Estimate, right: Estimate, two_sided: Estimate, one_sided: Estimate, samples: u64, final_seed: u64, right_sided: bool },
    timed_out: struct { right_sided: bool, final_seed: u64 },
    exhausted,
};
pub const Simulation = struct {
    samples: u64 = 10_000,
    seed: u64,
    alpha: f64 = 0.01,
    max_observations: u32 = 1_000_000,
    // The trend test codes the first binary response as 1 and the second
    // as 0. Sorted response codes therefore visit that margin in reverse.
    binary_response: enum { none, rows, columns } = .none,
};

/// Uniformly shuffle column labels into fixed row slots: every table has its
/// conditional hypergeometric probability. M9 reinitializes the sorted column
/// labels for each draw, then takes one forward-selection variate per observation.
pub fn monteCarlo(a: std.mem.Allocator, m: Matrix, statistic: Statistic, options: Simulation, budget: Budget) Error!MonteCarlo {
    if (options.samples == 0 or options.seed == 0 or !std.math.isFinite(statistic.expected)) return error.ExecError;
    _ = try estimate(0, options.samples, options.alpha);
    if (m.rows > 256 or m.cols > 256 or (m.rows > 0 and m.cols > 256 / m.rows)) return .exhausted;
    const shape = try Shape.init(a, m);
    defer shape.deinit(a);
    if (shape.total > options.max_observations) return .exhausted;
    const labels = try a.alloc(u8, shape.total);
    defer a.free(labels);
    var pos: usize = 0;
    for (0..m.cols) |position| {
        const j = if (options.binary_response == .columns) m.cols - position - 1 else position;
        const count = shape.cols[j];
        @memset(labels[pos..][0..count], @intCast(j));
        pos += count;
    }
    const shuffled = try a.alloc(u8, shape.total);
    defer a.free(shuffled);
    var context = FixedSampler{ .labels = labels, .shuffled = shuffled, .rows = shape.rows, .cols = m.cols, .reverse_rows = options.binary_response == .rows };
    return simulate(a, m, statistic, options, budget, .{ .context = &context, .draw = FixedSampler.draw });
}

pub const Generator = struct {
    state: u64,
    const modulus: u64 = 2147483647;
    pub fn init(seed: u64) Generator {
        return .{ .state = (seed - 1) % (modulus - 1) + 1 };
    }
    fn next(self: *Generator) u64 {
        self.state = self.state * 397204094 % modulus;
        return self.state;
    }
    pub fn uniform(self: *Generator) f64 {
        return @as(f64, @floatFromInt(self.next())) / @as(f64, @floatFromInt(modulus));
    }
};
pub const FixedSampler = struct {
    labels: []const u8,
    shuffled: []u8,
    reverse_rows: bool = false,
    rows: []const u32,
    cols: usize,
    pub fn draw(raw: ?*anyopaque, random: *Generator, cells: []u32, budget: Budget) Error!bool {
        const self: *FixedSampler = @ptrCast(@alignCast(raw.?));
        @memcpy(self.shuffled, self.labels);
        @memset(cells, 0);
        var pos: usize = 0;
        for (0..self.rows.len) |position| {
            const row = if (self.reverse_rows) self.rows.len - position - 1 else position;
            for (0..self.rows[row]) |_| {
                if (pos % 1024 == 0 and budget.stopped()) return false;
                const remaining = self.shuffled.len - pos;
                const offset: usize = @intCast((random.next() * remaining) / Generator.modulus);
                std.mem.swap(u8, &self.shuffled[pos], &self.shuffled[pos + offset]);
                cells[row * self.cols + self.shuffled[pos]] += 1;
                pos += 1;
            }
        }
        return true;
    }
};
/// Generator owns its law. False is an interrupted draw, never a usable table.
pub const Sampler = struct { context: ?*anyopaque, draw: *const fn (?*anyopaque, *Generator, []u32, Budget) Error!bool };
pub fn simulate(a: std.mem.Allocator, m: Matrix, statistic: Statistic, options: Simulation, budget: Budget, sampler: Sampler) Error!MonteCarlo {
    if (options.samples == 0 or options.seed == 0 or !std.math.isFinite(statistic.expected)) return error.ExecError;
    _ = try estimate(0, options.samples, options.alpha);
    const law: ?FixedLaw = if (statistic.evaluate == fisherStatistic) try FixedLaw.fromMatrix(m) else null;
    const observed = try statistic.observedValue(m, if (law) |*l| l else null);
    if (!std.math.isFinite(observed)) return error.ExecError;
    const cells = try a.alloc(u32, m.cells.len);
    defer a.free(cells);
    var random = Generator.init(options.seed);
    var hits: [5]u64 = @splat(0);
    var sample: u64 = 0;
    // A time limit discards all estimates. The next statistic resumes the
    // generator after the last fully scored table, never mid-permutation.
    var stopped: MonteCarlo = .{ .timed_out = .{ .right_sided = observed > statistic.expected, .final_seed = random.state } };
    while (sample < options.samples) : (sample += 1) {
        if (budget.stopped()) return stopped;
        if (sample == budget.max_tables) return .exhausted;
        if (!try sampler.draw(sampler.context, &random, cells, budget)) return if (budget.stopped()) stopped else .exhausted;
        const sampled = Matrix{ .rows = m.rows, .cols = m.cols, .cells = cells };
        const e = if (statistic.centered_integer) |integer| integer.compare(statistic.context, sampled) else blk: {
            const value = if (law) |*l| -l.logProbability(cells) else try statistic.evaluate(statistic.context, sampled);
            if (!std.math.isFinite(value)) return error.ExecError;
            if (law) |*fixed| {
                if (fixed.overlaps(value, observed)) break :blk (try fisherTie(a, cells, m.cells, budget)) orelse return if (budget.stopped()) stopped else .exhausted;
            }
            break :blk events(value, observed, statistic);
        };
        if (e.point) hits[0] += 1;
        if (e.left) hits[1] += 1;
        if (e.right) hits[2] += 1;
        if (e.two) hits[3] += 1;
        if (if (statistic.directional and observed <= statistic.expected) e.left else e.right) hits[4] += 1;
        stopped.timed_out.final_seed = random.state;
    }
    return .{ .complete = .{ .point = try estimate(hits[0], sample, options.alpha), .left = try estimate(hits[1], sample, options.alpha), .right = try estimate(hits[2], sample, options.alpha), .two_sided = try estimate(hits[3], sample, options.alpha), .one_sided = try estimate(hits[4], sample, options.alpha), .samples = sample, .final_seed = random.state, .right_sided = observed > statistic.expected } };
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
test "Freeman-Halton probabilities separate neighboring integer weights on wide margins" {
    const t = std.testing;
    // For two draws the independent labeled-allocation weight is C(c,2)
    // in a single column and c_i*c_j in distinct columns. All ten possible
    // allocations fit in u64, including N² versus (N-1)*(N+1) = N²-1.
    const margins = [_]u32{ 500_000_000, 500_000_001, 499_999_999, 500_000_000 };
    const total: u64 = 2_000_000_000;
    const denominator: f64 = @floatFromInt(total * (total - 1) / 2);
    var weights: [10]u64 = undefined;
    var splits: [10][4]u32 = @splat(@splat(0));
    var index: usize = 0;
    for (margins, 0..) |a, i| for (i..margins.len) |j| {
        weights[index] = if (i == j) @as(u64, a) * (a - 1) / 2 else @as(u64, a) * margins[j];
        splits[index][i] += 1;
        splits[index][j] += 1;
        index += 1;
    };
    for (weights, splits) |observed, split| {
        const cells = split ++ [4]u32{ margins[0] - split[0], margins[1] - split[1], margins[2] - split[2], margins[3] - split[3] };
        const m = Matrix{ .rows = 2, .cols = 4, .cells = &cells };
        const result = (try enumerate(t.allocator, m, .{ .evaluate = fisherStatistic }, .{})).complete;
        var tail: u64 = 0;
        var point: u64 = 0;
        for (weights) |weight| {
            if (weight <= observed) tail += weight;
            if (weight == observed) point += weight;
        }
        try t.expectEqual(@as(u64, 10), result.tables);
        try t.expectApproxEqRel(@as(f64, @floatFromInt(observed)) / denominator, try tableProbability(m), 5e-14);
        try t.expectApproxEqRel(@as(f64, @floatFromInt(point)) / denominator, result.point, 5e-14);
        try t.expectApproxEqRel(@as(f64, @floatFromInt(tail)) / denominator, result.two_sided, 5e-14);
    }
}

test "Fisher simulation distinguishes unit gaps in integer allocation weights" {
    const t = std.testing;
    const target = [_]u32{ 0, 1, 1, 0, 500_000_000, 500_000_000, 499_999_998, 500_000_000 };
    const greater_mass = [_]u32{ 1, 0, 0, 1, 499_999_999, 500_000_001, 499_999_999, 499_999_999 };
    const Draw = struct {
        index: usize = 0,
        fn sample(raw: ?*anyopaque, _: *Generator, cells: []u32, _: Budget) Error!bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            @memcpy(cells, if (self.index == 0) &target else &greater_mass);
            self.index += 1;
            return true;
        }
    };
    var draws = Draw{};
    const result = (try simulate(t.allocator, .{ .rows = 2, .cols = 4, .cells = &target }, .{ .evaluate = fisherStatistic }, .{ .seed = 1, .samples = 3 }, .{}, .{ .context = &draws, .draw = Draw.sample })).complete;
    try t.expectEqual(@as(f64, 1.0 / 3.0), result.point.p);
    try t.expectEqual(result.point.p, result.two_sided.p);
}

test "Freeman-Halton absolute and tied probabilities survive wide table transposition" {
    const t = std.testing;
    // Two then three draws without replacement give 60 joint tables.
    // Products of binomial coefficients evaluated as exact integers.
    const rows = [_]u32{ 2, 0, 0, 0, 2, 1, 999_999_998, 999_999_999, 6 };
    const cols = [_]u32{ 2, 0, 999_999_998, 0, 2, 999_999_999, 0, 1, 6 };
    for ([_][]const u32{ &rows, &cols }) |cells| {
        const m = Matrix{ .rows = 3, .cols = 3, .cells = cells };
        const result = (try enumerate(t.allocator, m, .{ .evaluate = fisherStatistic }, .{})).complete;
        try t.expectEqual(@as(u64, 60), result.tables);
        try t.expectApproxEqRel(@as(f64, 6.562499901562500888e-10), try tableProbability(m), 5e-14);
        try t.expectApproxEqRel(@as(f64, 1.312499980312500178e-9), result.point, 5e-14);
        try t.expectApproxEqRel(@as(f64, 4.375000029749999437e-9), result.two_sided, 5e-14);
    }
    const tied = (try fisherTie(t.allocator, &.{ 4, 1, 1, 1 }, &.{ 3, 2, 2, 0 }, .{})).?;
    try t.expect(tied.point and tied.left and tied.right);
    var hundred = (try factorialRange(u32, t.allocator, 0, 100, .{})).?;
    defer hundred.deinit();
    try t.expectEqual(@as(usize, 525), hundred.bitCountAbs());
    try t.expect((try factorialRange(u32, t.allocator, 0, 100, .{ .expired = expired })) == null);
}

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

test "Monte Carlo deadline discards an incomplete draw and resumes at the last scored table" {
    const Probe = struct {
        draws: u32 = 0,
        fn stopped(raw: ?*const anyopaque) bool {
            const self: *const @This() = @ptrCast(@alignCast(raw.?));
            return self.draws == 3;
        }
        fn draw(raw: ?*anyopaque, random: *Generator, cells: []u32, _: Budget) Error!bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = random.uniform();
            self.draws += 1;
            cells[0] = 1;
            return self.draws < 3;
        }
    };
    var probe: Probe = .{};
    const result = try simulate(std.testing.allocator, .{ .rows = 1, .cols = 1, .cells = &.{1} }, .{ .evaluate = firstCell, .directional = true }, .{ .seed = 713, .samples = 8 }, .{ .context = &probe, .expired = Probe.stopped }, .{ .context = &probe, .draw = Probe.draw });
    // Independent two-step modular recurrence from the initial seed 713.
    const expected: u64 = (713 * @as(u64, 397204094) % 2147483647) * 397204094 % 2147483647;
    try std.testing.expect(result == .timed_out);
    try std.testing.expectEqual(expected, result.timed_out.final_seed);
    try std.testing.expect(result.timed_out.right_sided);
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

// SAS generators-mc.sas: SYMMETRY N=1 gives p=0 and 99% CI [0,.99].
test "single Monte Carlo draw uses boundary confidence formula" {
    const zero = try estimate(0, 1, 0.01);
    const one = try estimate(1, 1, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.99), zero.upper, 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), one.lower, 1e-15);
}

/// Probability of THIS table, distinct from the mass of all tables tied in
/// Fisher's ordering (Probabilities.point). Marginal factorials are required.
pub fn tableProbability(m: Matrix) Error!f64 {
    return @exp(-try fisherStatistic(null, m));
}
