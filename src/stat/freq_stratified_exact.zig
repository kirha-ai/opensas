//! Pure statistic adapters for dev3's conditional-distribution interface.
//! Instantiate Adapters(@import("freq_exact_distribution.zig")) after landing
//! that module. Generic binding avoids copying the other agent's nominal types.
//! Context and score/weight slices must outlive enumeration; evaluation allocates
//! nothing and never changes scores, margins, row order, or stratum order.
const std = @import("std");
const k = @import("freq_stratified.zig");
const Error = k.Error;
pub const Family = enum { trend, jonckheere, kappa, weighted_kappa, mcnemar, symmetry, mhchi };
pub const Context = struct {
    family: Family,
    rows: usize,
    cols: usize,
    row_scores: ?[]const f64 = null,
    col_scores: ?[]const f64 = null,
    weights: ?[]const f64 = null,
    null_ratio: f64 = 1,
    /// Fixed-margin chance-expected agreement for kappa, null J mean for JT.
    expected: f64 = 0,
    total: f64,
    /// Raw linear score expectation and conditional variance for MHCHI.
    mh_mean: f64 = 0,
    mh_variance: f64 = 0,

    pub fn init(m: k.Matrix, family: Family, weights: ?[]const f64, null_ratio: f64) Error!Context {
        // The exact engine currently caps the reference set shape at 256 cells.
        if (m.rows == 0 or m.cols == 0 or m.counts.len > 256 or m.rows > 256 or m.cols > 256 / m.rows or m.counts.len != m.rows * m.cols) return error.ExecError;
        var row: [256]f64 = @splat(0);
        var col: [256]f64 = @splat(0);
        var total: f64 = 0;
        for (m.counts, 0..) |x, i| {
            if (!std.math.isFinite(x) or x < 0 or x != @floor(x)) return error.ExecError;
            row[i / m.cols] += x;
            col[i % m.cols] += x;
            total += x;
        }
        if ((total == 0 and family != .mhchi) or total > std.math.maxInt(u32)) return error.ExecError;
        if (m.row_scores) |s| {
            if (s.len != m.rows) return error.ExecError;
            for (s) |v| {
                if (!std.math.isFinite(v)) return error.ExecError;
            }
        }
        if (m.col_scores) |s| {
            if (s.len != m.cols) return error.ExecError;
            for (s) |v| {
                if (!std.math.isFinite(v)) return error.ExecError;
            }
        }
        var context = Context{ .family = family, .rows = m.rows, .cols = m.cols, .row_scores = m.row_scores, .col_scores = m.col_scores, .weights = weights, .null_ratio = null_ratio, .total = total };
        switch (family) {
            .trend => {
                if (try k.trend(m) == null) return error.ExecError;
            },
            .jonckheere => {
                if (m.rows < 2 or m.cols < 2) return error.ExecError;
                context.expected = total * total;
                for (row[0..m.rows]) |r| {
                    context.expected -= r * r;
                }
                context.expected /= 4;
            },
            .kappa, .weighted_kappa => {
                if (m.rows != m.cols or m.rows < 2) return error.ExecError;
                if (family == .weighted_kappa and weights == null) return error.ExecError;
                if (weights) |w| {
                    if (w.len != m.counts.len) return error.ExecError;
                    for (w) |v| {
                        if (!std.math.isFinite(v) or v < 0 or v > 1) return error.ExecError;
                    }
                }
                for (0..m.rows) |i| for (0..m.cols) |j| {
                    const w = if (family == .kappa) (if (i == j) @as(f64, 1) else 0) else weights.?[i * m.cols + j];
                    context.expected += w * (row[i] / total) * (col[j] / total);
                };
                if (context.expected >= 1) return error.ExecError;
            },
            .mcnemar => {
                if (try k.mcnemar(m, null_ratio) == null) return error.ExecError;
            },
            .symmetry => {
                if (m.rows != m.cols or m.rows < 2) return error.ExecError;
            },
            .mhchi => {
                if (total <= 1) {
                    for (m.counts, 0..) |x, i| context.mh_mean += x * score(m.row_scores, i / m.cols) * score(m.col_scores, i % m.cols);
                    return context;
                }
                var rmean: f64 = 0;
                var cmean: f64 = 0;
                for (row[0..m.rows], 0..) |v, i| {
                    rmean += v / total * score(m.row_scores, i);
                }
                for (col[0..m.cols], 0..) |v, i| {
                    cmean += v / total * score(m.col_scores, i);
                }
                var vr: f64 = 0;
                var vc: f64 = 0;
                for (row[0..m.rows], 0..) |v, i| {
                    vr += v / total * square(score(m.row_scores, i) - rmean);
                }
                for (col[0..m.cols], 0..) |v, i| {
                    vc += v / total * square(score(m.col_scores, i) - cmean);
                }
                context.mh_mean = total * rmean * cmean;
                context.mh_variance = total * total / (total - 1) * vr * vc;
            },
        }
        return context;
    }
};
fn square(x: f64) f64 {
    return x * x;
}
fn score(values: ?[]const f64, i: usize) f64 {
    return if (values) |v| v[i] else @floatFromInt(i + 1);
}

pub fn Adapters(comptime exact: type) type {
    return struct {
        /// McNemar and symmetry REQUIRE dev3's discordant-pair/binomial
        /// reference set, NOT enumerate()'s fixed-row/column reference set.
        /// Kappa, weighted kappa, JT, TREND and MHCHI use fixed margins.
        pub fn statistic(context: *const Context) exact.Statistic {
            return .{
                .context = context,
                .evaluate = evaluate,
                .expected = if (context.family == .jonckheere) context.expected else 0,
                .directional = switch (context.family) {
                    .trend, .jonckheere, .kappa, .weighted_kappa => true,
                    else => false,
                },
            };
        }
        pub fn evaluate(opaque_context: ?*const anyopaque, sampled: exact.Matrix) Error!f64 {
            const context: *const Context = @ptrCast(@alignCast(opaque_context orelse return error.ExecError));
            if (sampled.rows != context.rows or sampled.cols != context.cols or sampled.cells.len != context.rows * context.cols or sampled.cells.len > 256) return error.ExecError;
            var cells: [256]f64 = undefined;
            var total: f64 = 0;
            for (sampled.cells, 0..) |x, i| {
                cells[i] = @floatFromInt(x);
                total += cells[i];
            }
            if (total != context.total) return error.ExecError;
            const m = k.Matrix{ .rows = sampled.rows, .cols = sampled.cols, .counts = cells[0..sampled.cells.len], .row_scores = context.row_scores, .col_scores = context.col_scores };
            return switch (context.family) {
                .trend => (try k.trend(m) orelse return error.ExecError).z,
                .jonckheere => try k.jonckheereStatistic(m),
                .mcnemar => (try k.mcnemar(m, context.null_ratio) orelse return error.ExecError).statistic,
                .symmetry => (try k.bowker(m, .default) orelse return error.ExecError).statistic,
                .kappa, .weighted_kappa => blk: {
                    var observed: f64 = 0;
                    for (m.counts, 0..) |x, i| {
                        const weight = if (context.family == .kappa) (if (i / m.cols == i % m.cols) @as(f64, 1) else 0) else context.weights.?[i];
                        observed += x / context.total * weight;
                    }
                    break :blk (observed - context.expected) / (1 - context.expected);
                },
                .mhchi => if (context.mh_variance > 0) square(try linearScore(context, sampled) - context.mh_mean) / context.mh_variance else error.ExecError,
            };
        }
        fn linearScore(context: *const Context, m: exact.Matrix) Error!f64 {
            if (m.rows != context.rows or m.cols != context.cols or m.cells.len != context.rows * context.cols) return error.ExecError;
            var sum: f64 = 0;
            var total: f64 = 0;
            for (m.cells, 0..) |x, i| {
                total += @floatFromInt(x);
                sum += @as(f64, @floatFromInt(x)) * score(context.row_scores, i / m.cols) * score(context.col_scores, i % m.cols);
            }
            if (total != context.total) return error.ExecError;
            return sum;
        }
        /// Proposed joint-stratum callback: generator fixes margins separately
        /// in each stratum, visits strata in the original table order, and calls
        /// this only on a complete joint draw. Never flatten across strata.
        pub fn cmhCorrelation(contexts: []const Context, sampled: []const exact.Matrix) Error!f64 {
            if (contexts.len == 0 or contexts.len != sampled.len) return error.ExecError;
            var g: f64 = 0;
            var variance: f64 = 0;
            for (contexts, sampled) |*c, m| {
                if (c.family != .mhchi) return error.ExecError;
                g += try linearScore(c, m) - c.mh_mean;
                variance += c.mh_variance;
            }
            if (variance <= 0) return error.ExecError;
            return g * g / variance;
        }
    };
}

// Nominal mock verifies the exact contract without requiring dev3's unlanded
// file. A /tmp harness additionally instantiates the actual dev3 module.
const Contract = struct {
    pub const Matrix = struct { rows: usize, cols: usize, cells: []const u32 };
    pub const Statistic = struct { context: ?*const anyopaque = null, evaluate: *const fn (?*const anyopaque, Matrix) Error!f64, expected: f64 = 0, directional: bool = false };
};
test "stratified exact callbacks preserve signed scores ties and margins" {
    const api = Adapters(Contract);
    const m: k.Matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 8, 17, 12, 11, 20, 4 }, .row_scores = &.{ 1, 3, 8 } };
    const sampled: Contract.Matrix = .{ .rows = 3, .cols = 2, .cells = &.{ 8, 17, 12, 11, 20, 4 } };
    var ctx = try Context.init(m, .trend, null, 1);
    var s = api.statistic(&ctx);
    try std.testing.expect(s.directional);
    try std.testing.expectApproxEqAbs(@as(f64, 3.6114), try s.evaluate(s.context, sampled), 0.00005);
    ctx = try Context.init(m, .jonckheere, null, 1);
    s = api.statistic(&ctx);
    try std.testing.expectEqual(@as(f64, 565.5), try s.evaluate(s.context, sampled));
    try std.testing.expectEqual(@as(f64, 863.5), s.expected);
    const agreement: k.Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 6, 16, 2, 4 } };
    ctx = try Context.init(agreement, .kappa, null, 1);
    s = api.statistic(&ctx);
    try std.testing.expectApproxEqAbs(@as(f64, -0.0328), try s.evaluate(s.context, .{ .rows = 2, .cols = 2, .cells = &.{ 6, 16, 2, 4 } }), 0.00005);
    ctx = try Context.init(agreement, .mcnemar, null, 2);
    s = api.statistic(&ctx);
    try std.testing.expectEqual(@as(f64, 4), try s.evaluate(s.context, .{ .rows = 2, .cols = 2, .cells = &.{ 6, 16, 2, 4 } }));
    try std.testing.expectError(error.ExecError, s.evaluate(s.context, .{ .rows = 1, .cols = 4, .cells = &.{ 6, 16, 2, 4 } }));
}
test "stratified exact joint CMH retains stratum boundaries" {
    const contexts = [_]Context{
        try Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } }, .mhchi, null, 1),
        try Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } }, .mhchi, null, 1),
    };
    const sampled = [_]Contract.Matrix{
        .{ .rows = 2, .cols = 2, .cells = &.{ 16, 11, 5, 20 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 12, 16, 7, 19 } },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 8.3052), try Adapters(Contract).cmhCorrelation(&contexts, &sampled), 0.00005);
}

test "stratified exact CMH empty stratum occupies its original slot" {
    const contexts = [_]Context{
        try Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } }, .mhchi, null, 1),
        try Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } }, .mhchi, null, 1),
        try Context.init(.{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } }, .mhchi, null, 1),
    };
    const sampled = [_]Contract.Matrix{
        .{ .rows = 2, .cols = 2, .cells = &.{ 16, 11, 5, 20 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 0, 0, 0, 0 } }, .{ .rows = 2, .cols = 2, .cells = &.{ 12, 16, 7, 19 } },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 8.3052), try Adapters(Contract).cmhCorrelation(&contexts, &sampled), 0.00005);
}
