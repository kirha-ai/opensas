//! Estimable linear functions and missing inference contracts (COMMON009).
//! S154 physical pp.278–284 and 4081: L = LH, H=(X'WX)-X'WX.
//! reg_diagnostics supplies H transposed as its ordered alias equations.
const std = @import("std");
const diag = @import("../diag.zig");
const ranks = @import("reg_diagnostics.zig");
const A = std.mem.Allocator;
pub const Status = enum { estimable, nonestimable };
pub const Result = struct {
    status: Status,
    /// Null means unavailable, never a fabricated zero. An estimable zero is 0.
    estimate: ?f64 = null,
    variance_factor: ?f64 = null,
    standard_error: ?f64 = null,
    t_value: ?f64 = null,
    p_value: ?f64 = null,
};

const proc = @import("../proc.zig");
const parsing = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const coded = @import("design_matrix.zig");

/// Shared full-parameter basis for LSMEANS and ESTIMATE; empty interaction
/// columns, formatted levels and parameter order come from the coded designer.
pub fn codedDesign(cx: proc.ProcCtx, spec: parsing.Spec, d: design.Design) diag.Error!coded.Design {
    if (spec.order == .freq and spec.freq != null) return proc.failGap(cx.diags, 0, "PROC GLM: coefficient statements with ORDER=FREQ and FREQ are not implemented", .{});
    const effects = try cx.arena.alloc(coded.Effect, spec.effects.len);
    for (effects, spec.effects) |*dest, source| dest.* = .{ .factors = source.variables };
    const rows = try cx.arena.alloc([]const @import("../value.zig").Value, d.n);
    for (d.observations, rows) |row, *dest| dest.* = row.cells;
    const matrix = try coded.build(cx.arena, spec.input.ds, rows, .{ .response = d.response, .classes = spec.classes, .effects = effects, .intercept = spec.intercept, .order = spec.order });
    if (matrix.n != d.n) return cx.diags.fail(error.ExecError, 0, "PROC GLM: coefficient statement analysis rows disagree", .{});
    return matrix;
}

/// Retain the full model's FREQ-adjusted error DF/MSE. The two equivalent
/// parameter bases must agree in numerical rank; otherwise fail visibly.
pub fn fitCoded(cx: proc.ProcCtx, spec: parsing.Spec, d: design.Design, matrix: coded.Design, mse: f64, df_error: usize) diag.Error!ranks.Result {
    const weights = try cx.arena.alloc(f64, d.n);
    for (weights, d.weights, d.frequencies) |*w, precision, frequency| w.* = precision * frequency;
    var model = try ranks.fit(cx.arena, matrix.x, d.y, matrix.n, matrix.p, weights, spec.intercept, spec.singular);
    errdefer model.deinit(cx.arena);
    var total_frequency: f64 = 0;
    for (d.frequencies) |frequency| total_frequency += frequency;
    if (total_frequency - @as(f64, @floatFromInt(df_error)) != @as(f64, @floatFromInt(model.fit.rank))) return cx.diags.fail(error.ExecError, 0, "PROC GLM: coded design and MODEL rank disagree", .{});
    model.fit.mse = mse;
    model.fit.df_error = df_error;
    return model;
}

/// The tolerance belongs to the consumer (LSMEANS defaults to 1e-4), not
/// MODEL's numerical rank cutoff. Invalid inputs fail rather than mean Non-est.
pub fn check(model: ranks.Result, l: []const f64, tolerance: f64) diag.Error!Status {
    const p = model.fit.coefficients.len;
    if (l.len != p or model.alias_coefficients.len != p * p or !std.math.isFinite(tolerance) or tolerance <= 0 or tolerance >= 1) return error.ExecError;
    for (l) |v| if (!std.math.isFinite(v)) return error.ExecError;
    var status: Status = .estimable;
    for (l, 0..) |v, j| {
        var projected: f64 = 0;
        for (l, 0..) |u, k| projected += u * model.alias_coefficients[j * p + k];
        if (!std.math.isFinite(projected)) return error.ExecError;
        const scale = if (v == 0) 1 else @abs(v);
        if (@abs(v - projected) > scale * tolerance) status = .nonestimable;
    }
    return status;
}

pub fn evaluate(model: ranks.Result, l: []const f64, tolerance: f64) diag.Error!Result {
    const status = try check(model, l, tolerance);
    if (status == .nonestimable) return .{ .status = status };
    const fit = model.fit;
    const p = l.len;
    var estimate: f64 = 0;
    var variance: f64 = 0;
    for (l, 0..) |v, j| {
        estimate += v * fit.coefficients[j];
        for (l, 0..) |u, k| variance += v * fit.covariance_unscaled[j * p + k] * u;
    }
    if (!std.math.isFinite(estimate) or !std.math.isFinite(variance) or variance < -1e-12) return error.ExecError;
    var result: Result = .{ .status = status, .estimate = estimate, .variance_factor = @max(0, variance) };
    if (fit.df_error > 0 and std.math.isFinite(fit.mse) and fit.mse >= 0) {
        const se = @sqrt(result.variance_factor.? * fit.mse);
        if (!std.math.isFinite(se)) return error.ExecError;
        result.standard_error = se;
        if (se > 0) {
            result.t_value = estimate / se;
            result.p_value = @import("reg_fit.zig").tProbability(result.t_value.?, fit.df_error);
        }
    }
    return result;
}

/// Independent rows of H, in retained parameter order. Setting each free
/// L symbol to one reconstructs this generating set (S154 pp.279–280).
pub fn generatingSet(a: A, model: ranks.Result) diag.Error![]f64 {
    const p = model.fit.coefficients.len;
    const rows = try a.alloc(f64, model.fit.rank * p);
    var i: usize = 0;
    for (model.fit.aliased, 0..) |aliased, k| if (!aliased) {
        for (0..p) |j| rows[i * p + j] = model.alias_coefficients[j * p + k];
        i += 1;
    };
    return rows;
}

test "COMMON009 one-way generating rules and true nonestimable missing fields" {
    const t = std.testing;
    var m = try ranks.fit(t.allocator, &.{ 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1 }, &.{ 1, 3, 4, 6, 7, 9 }, 6, 4, null, true, 1e-9);
    defer m.deinit(t.allocator);
    const basis = try generatingSet(t.allocator, m);
    defer t.allocator.free(basis);
    try t.expectEqual(@as(usize, 3), m.fit.rank);
    const expected = [_]f64{ 1, 0, 0, 1, 0, 1, 0, -1, 0, 0, 1, -1 };
    for (basis, expected) |v, e| try t.expectApproxEqAbs(e, v, 1e-12);
    const good = try evaluate(m, &.{ 0, 1, 0, -1 }, 1e-4);
    try t.expectEqual(Status.estimable, good.status);
    try t.expectApproxEqAbs(@as(f64, -6), good.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1), good.variance_factor.?, 1e-12);
    const bad = try evaluate(m, &.{ 0, 1, 0, 0 }, 1e-4);
    try t.expectEqual(Status.nonestimable, bad.status);
    inline for (.{ "estimate", "variance_factor", "standard_error", "t_value", "p_value" }) |field| try t.expect(@field(bad, field) == null);
    const zero = try evaluate(m, &.{ 0, 0, 0, 0 }, 1e-4);
    try t.expectEqual(@as(?f64, 0), zero.estimate);
    try t.expectEqual(@as(?f64, 0), zero.standard_error);
    try t.expect(zero.t_value == null and zero.p_value == null);
    try t.expectError(error.ExecError, check(m, &.{1}, 1e-4));
    try t.expectError(error.ExecError, check(m, &.{ 0, 0, 0, std.math.nan(f64) }, 1e-4));
    try t.expectError(error.ExecError, check(m, &.{ 0, 0, 0, 0 }, 0));
}

test "COMMON009 dependent regression relation and saturated inference" {
    const t = std.testing;
    // S154 Table16.4: x3=2*x1+3*x2, so L4=2*L2+3*L3.
    var m = try ranks.fit(t.allocator, &.{ 1, 0, 0, 0, 1, 1, 0, 2, 1, 0, 1, 3 }, &.{ 1, 2, 4 }, 3, 4, null, true, 1e-9);
    defer m.deinit(t.allocator);
    const good = try evaluate(m, &.{ 0, 1, 1, 5 }, 1e-4);
    try t.expectEqual(Status.estimable, good.status);
    try t.expectApproxEqAbs(@as(f64, 4), good.estimate.?, 1e-12);
    try t.expect(good.standard_error == null and good.p_value == null);
    for ([_][4]f64{ .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } }) |l| try t.expectEqual(Status.nonestimable, try check(m, &l, 1e-4));
    try t.expectEqual(Status.estimable, try check(m, &.{ 0, 1, 1, 5.00001 }, 1e-4));
    try t.expectEqual(Status.nonestimable, try check(m, &.{ 0, 1, 1, 5.00001 }, 1e-8));
}

test "COMMON009 three-factor source example and reduction notation R(C given intercept A B)" {
    const t = std.testing;
    // Table16.1–16.2, physical pp.282–283. Replicated final cell permits
    // inference. A1-A2 and B1-B2 cannot be tested alone; C1-2C2+C3 can.
    const x = [_]f64{
        1, 1, 0, 0, 1, 1, 0, 0,
        1, 1, 0, 1, 0, 0, 1, 0,
        1, 0, 1, 1, 0, 0, 0, 1,
        1, 0, 1, 0, 1, 0, 1, 0,
        1, 0, 1, 0, 1, 0, 1, 0,
    };
    const glm = @import("glm_fit.zig");
    var result = try glm.fit(t.allocator, &x, &.{ 1, 2, 3, 4, 6 }, 5, 8, &.{ .{ .start = 1, .len = 2 }, .{ .start = 3, .len = 2 }, .{ .start = 5, .len = 3 } }, .{});
    defer result.deinit(t.allocator);
    try t.expectEqual(@as(usize, 4), result.model.fit.rank);
    const a = try evaluate(result.model, &.{ 0, 1, -1, 0, 0, 0, 0, 0 }, 1e-4);
    const b = try evaluate(result.model, &.{ 0, 0, 0, 1, -1, 0, 0, 0 }, 1e-4);
    const c = try evaluate(result.model, &.{ 0, 0, 0, 0, 0, 1, -2, 1 }, 1e-4);
    try t.expectEqual(Status.nonestimable, a.status);
    try t.expectEqual(Status.nonestimable, b.status);
    try t.expectEqual(Status.estimable, c.status);
    try t.expectApproxEqAbs(@as(f64, -3), c.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 3.5), c.variance_factor.?, 1e-12);
    for (result.type_iii[0..2]) |reduction| {
        try t.expectEqual(@as(usize, 0), reduction.df);
        try t.expectEqual(@as(f64, 0), reduction.ss);
        try t.expect(std.math.isNan(reduction.ms) and std.math.isNan(reduction.f_value) and std.math.isNan(reduction.p_value));
    }
    try t.expectEqual(@as(usize, 1), result.type_iii[2].df);
    try t.expectApproxEqAbs(@as(f64, 18.0 / 7.0), result.type_iii[2].ss, 1e-12);
    try t.expectApproxEqAbs(c.estimate.? * c.estimate.? / c.variance_factor.?, result.type_iii[2].ss, 1e-12);
}
