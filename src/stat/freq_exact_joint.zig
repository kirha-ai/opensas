//! Joint conditional reference sets preserve each stratum's margins and slot.
//! The probability is the product of stratum hypergeometrics. Empty strata
//! contribute one all-zero draw of mass 1; never pool or reorder strata.
const std = @import("std");
const dist = @import("freq_exact_distribution.zig");
pub const Error = dist.Error;
pub const Statistic = struct {
    context: ?*const anyopaque = null,
    evaluate: *const fn (?*const anyopaque, []const dist.Matrix) Error!f64,
    expected: f64 = 0,
    directional: bool = false,
};
fn unused(_: ?*const anyopaque, _: dist.Matrix) Error!f64 {
    return error.ExecError;
}
const Search = struct {
    a: std.mem.Allocator,
    original: []const dist.Matrix,
    sampled: []dist.Matrix,
    statistic: Statistic,
    accumulator: dist.Accumulator,
    budget: dist.Budget,
    count: u64 = 0,
    stopped: bool = false,
    const Frame = struct { search: *Search, index: usize, log_weight: f64 };
    fn expired(raw: ?*const anyopaque) bool {
        const self: *const Search = @ptrCast(@alignCast(raw.?));
        return self.stopped or self.budget.stopped();
    }
    fn accept(raw: ?*anyopaque, m: dist.Matrix, log_weight: f64) Error!void {
        const frame: *Frame = @ptrCast(@alignCast(raw.?));
        frame.search.sampled[frame.index] = m;
        try frame.search.visit(frame.index + 1, frame.log_weight + log_weight);
    }
    fn visit(self: *Search, index: usize, log_weight: f64) Error!void {
        if (self.stopped) return;
        if (self.budget.stopped()) {
            self.stopped = true;
            return;
        }
        if (index == self.original.len) {
            if (self.count == self.budget.max_tables) {
                self.stopped = true;
                return;
            }
            self.count += 1;
            try self.accumulator.add(log_weight, try self.statistic.evaluate(self.statistic.context, self.sampled));
            return;
        }
        var frame = Frame{ .search = self, .index = index, .log_weight = log_weight };
        const complete = try dist.visitFixed(self.a, self.original[index], .{ .max_tables = self.budget.max_tables, .context = self, .expired = expired }, .{ .context = &frame, .visit = accept });
        if (!complete) self.stopped = true;
    }
};
pub fn enumerate(a: std.mem.Allocator, strata: []const dist.Matrix, statistic: Statistic, budget: dist.Budget) Error!dist.Enumeration {
    if (strata.len == 0) return error.ExecError;
    if (strata.len > 64) return .exhausted;
    const observed = try statistic.evaluate(statistic.context, strata);
    if (!std.math.isFinite(observed) or !std.math.isFinite(statistic.expected)) return error.ExecError;
    const sampled = try a.alloc(dist.Matrix, strata.len);
    defer a.free(sampled);
    var search = Search{ .a = a, .original = strata, .sampled = sampled, .statistic = statistic, .budget = budget, .accumulator = .{ .statistic = .{ .evaluate = unused, .expected = statistic.expected, .directional = statistic.directional }, .observed = observed } };
    try search.visit(0, 0);
    if (search.stopped) return .exhausted;
    return .{ .complete = try search.accumulator.result(search.count) };
}

const adapters = @import("freq_stratified_exact.zig");
pub const CmhContext = struct {
    strata: []const adapters.Context,
    pub fn statistic(self: *const CmhContext) Statistic {
        return .{ .context = self, .evaluate = evaluate };
    }
    fn evaluate(raw: ?*const anyopaque, m: []const dist.Matrix) Error!f64 {
        const self: *const CmhContext = @ptrCast(@alignCast(raw.?));
        return adapters.Adapters(dist).cmhCorrelation(self.strata, m);
    }
};
test "joint CMH visits product law and preserves empty middle stratum" {
    const t = std.testing;
    const contexts = [_]adapters.Context{
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 2, 0, 0, 2 } }, .mhchi, null, 1),
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } }, .mhchi, null, 1),
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 2, 0, 0, 2 } }, .mhchi, null, 1),
    };
    const context = CmhContext{ .strata = &contexts };
    const matrices = [_]dist.Matrix{
        .{ .rows = 2, .cols = 2, .cells = &.{ 2, 0, 0, 2 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 0, 0, 0, 0 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 2, 0, 0, 2 } },
    };
    const r = (try enumerate(t.allocator, &matrices, context.statistic(), .{})).complete;
    try t.expectEqual(@as(u64, 9), r.tables);
    // Two extreme sums among [1,8,18,8,1]/36: 1/18.
    try t.expectApproxEqAbs(@as(f64, 1.0 / 18.0), r.two_sided, 1e-12);
    try t.expect((try enumerate(t.allocator, &matrices, context.statistic(), .{ .max_tables = 8 })) == .exhausted);
}

const JointSampler = struct {
    generators: []dist.FixedSampler,
    lengths: []const usize,
    fn draw(raw: ?*anyopaque, random: std.Random, cells: []u32, budget: dist.Budget) Error!bool {
        const self: *JointSampler = @ptrCast(@alignCast(raw.?));
        var pos: usize = 0;
        for (self.generators, self.lengths) |*generator, len| {
            if (!try dist.FixedSampler.draw(generator, random, cells[pos..][0..len], budget)) return false;
            pos += len;
        }
        return true;
    }
};
const JointEvaluation = struct {
    matrices: []dist.Matrix,
    lengths: []const usize,
    statistic: Statistic,
    fn evaluate(raw: ?*const anyopaque, flat: dist.Matrix) Error!f64 {
        const self: *const JointEvaluation = @ptrCast(@alignCast(raw.?));
        var pos: usize = 0;
        for (self.matrices, self.lengths) |*m, len| {
            m.cells = flat.cells[pos..][0..len];
            pos += len;
        }
        return self.statistic.evaluate(self.statistic.context, self.matrices);
    }
};
pub fn monteCarlo(a: std.mem.Allocator, strata: []const dist.Matrix, statistic: Statistic, options: dist.Simulation, budget: dist.Budget) Error!dist.MonteCarlo {
    if (strata.len == 0) return error.ExecError;
    if (strata.len > 64) return .exhausted;
    const generators = try a.alloc(dist.FixedSampler, strata.len);
    defer a.free(generators);
    var initialized: usize = 0;
    defer for (generators[0..initialized]) |g| {
        a.free(g.rows);
        a.free(g.labels);
    };
    const lengths = try a.alloc(usize, strata.len);
    defer a.free(lengths);
    const matrices = try a.dupe(dist.Matrix, strata);
    defer a.free(matrices);
    var cell_count: usize = 0;
    var observations: u64 = 0;
    for (strata, 0..) |m, index| {
        if (m.rows == 0 or m.cols == 0 or m.rows > 256 or m.cols > 256 / m.rows or m.cells.len != m.rows * m.cols) return error.ExecError;
        var n: u64 = 0;
        for (m.cells) |v| n += v;
        observations += n;
        if (observations > options.max_observations) return .exhausted;
        const rows = try a.alloc(u32, m.rows);
        errdefer a.free(rows);
        @memset(rows, 0);
        const labels = try a.alloc(u8, @intCast(n));
        var pos: usize = 0;
        for (m.cells, 0..) |v, k| {
            rows[k / m.cols] += v;
            @memset(labels[pos..][0..v], @intCast(k % m.cols));
            pos += v;
        }
        generators[index] = .{ .rows = rows, .labels = labels, .cols = m.cols };
        initialized += 1;
        lengths[index] = m.cells.len;
        cell_count += m.cells.len;
    }
    const cells = try a.alloc(u32, cell_count);
    defer a.free(cells);
    var pos: usize = 0;
    for (strata) |m| {
        @memcpy(cells[pos..][0..m.cells.len], m.cells);
        pos += m.cells.len;
    }
    var sampler = JointSampler{ .generators = generators, .lengths = lengths };
    var evaluation = JointEvaluation{ .matrices = matrices, .lengths = lengths, .statistic = statistic };
    return dist.simulate(a, .{ .rows = 1, .cols = cell_count, .cells = cells }, .{ .context = &evaluation, .evaluate = JointEvaluation.evaluate, .expected = statistic.expected, .directional = statistic.directional }, options, budget, .{ .context = &sampler, .draw = JointSampler.draw });
}

test "joint Monte Carlo preserves per-stratum margins and seed" {
    const t = std.testing;
    const contexts = [_]adapters.Context{
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 2, 0, 0, 2 } }, .mhchi, null, 1),
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } }, .mhchi, null, 1),
        try adapters.Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 2, 0, 0, 2 } }, .mhchi, null, 1),
    };
    const context = CmhContext{ .strata = &contexts };
    const matrices = [_]dist.Matrix{ .{ .rows = 2, .cols = 2, .cells = &.{ 2, 0, 0, 2 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 0, 0, 0, 0 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 2, 0, 0, 2 } } };
    const options = dist.Simulation{ .seed = 12345, .samples = 20000 };
    const x = (try monteCarlo(t.allocator, &matrices, context.statistic(), options, .{})).complete;
    const y = (try monteCarlo(t.allocator, &matrices, context.statistic(), options, .{})).complete;
    try t.expectEqualDeep(x, y);
    const p: f64 = 1.0 / 18.0;
    try t.expect(@abs(x.two_sided.p - p) < 6 * @sqrt(p * (1 - p) / 20000));
}
