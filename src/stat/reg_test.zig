//! PROC REG's linear TEST consumer (S154 physical pp.8598–8599).
//! This is not Chapter20's effect-based TEST syntax (pp.545–546).
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const hypothesis = @import("linear_hypothesis.zig");
const A = std.mem.Allocator;
pub const Spec = struct { statement_index: usize, number: usize, label: ?[]const u8, rows: []const hypothesis.Row, print: bool = false };
pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token, names: []const []const u8, statement_index: usize, number: usize, label: ?[]const u8) diag.Error!Spec {
    var end: usize = 0;
    while (end < tokens.len and tokens[end].tag != .slash) end += 1;
    if (end < tokens.len) {
        if (end + 2 != tokens.len or tokens[end + 1].tag != .name or !std.ascii.eqlIgnoreCase(tokens[end + 1].text, "print")) return cx.diags.fail(error.ParseError, tokens[end].line, "PROC REG TEST supports only PRINT; Chapter20 effect TEST options do not apply to REG", .{});
    }
    const equations = try @import("reg_restrict.zig").parseFor(cx, tokens[0..end], names, "TEST");
    const rows = try cx.arena.alloc(hypothesis.Row, equations.len);
    for (equations, rows) |equation, *row| row.* = .{ .coefficients = equation.coefficients, .rhs = equation.rhs };
    return .{ .statement_index = statement_index, .number = number, .label = label, .rows = rows, .print = end < tokens.len };
}
fn statistic(a: A, value: f64) ![]const u8 {
    if (!std.math.isFinite(value)) return ".";
    if (@abs(value) >= 10000) return std.fmt.allocPrint(a, "{d:.0}", .{value});
    if (value != 0 and @abs(value) < 0.001) return std.fmt.allocPrint(a, "{d:.8}", .{value});
    return std.fmt.allocPrint(a, "{d:.5}", .{value});
}
pub fn render(a: A, out: *std.ArrayList(u8), model: []const u8, response: []const u8, spec: Spec, result: hypothesis.Result, mse: f64) !void {
    const name = spec.label orelse try std.fmt.allocPrint(a, "{d}", .{spec.number});
    try out.print(a, "\nThe REG Procedure\nModel: {s}\n\nTest {s} Results for Dependent Variable {s}\n\nMean\nSource DF Square F Value Pr > F\n\nNumerator {d} {s} {d:.2} {s}\nDenominator {d:.0} {s}\n", .{ model, name, response, result.rank, try statistic(a, result.numerator_ss.? / @as(f64, @floatFromInt(result.rank))), result.f.?, if (result.f_probability.? < 0.0001) @as([]const u8, "<.0001") else try std.fmt.allocPrint(a, "{d:.4}", .{result.f_probability.?}), result.denominator_df.?, try statistic(a, mse) });
}

pub const Intermediate = struct { dimension: usize, covariance: []const f64, difference: []const f64, inverse: []const f64, solution: []const f64 };
/// PRINT exposes the actual unscaled hypothesis covariance and both bordering
/// vectors. The inverse here is required only when the tested rows are full rank.
pub fn intermediate(a: A, model: hypothesis.Model, rows: []const hypothesis.Row) !Intermediate {
    const p = model.estimates.len;
    const q = rows.len;
    if (q == 0 or model.covariance_kernel.len != p * p) return error.ExecError;
    for (model.estimates) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (model.covariance_kernel) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (rows) |row| {
        if (!std.math.isFinite(row.rhs)) return error.ExecError;
        for (row.coefficients) |v| if (!std.math.isFinite(v)) return error.ExecError;
    }
    const covariance = try a.alloc(f64, q * q);
    const difference = try a.alloc(f64, q);
    const scaled = try a.alloc(f128, q * q);
    const inverse_scaled = try a.alloc(f128, q * q);
    const scales = try a.alloc(f128, q);
    @memset(inverse_scaled, 0);
    for (rows, 0..) |row, i| {
        if (row.coefficients.len != p) return error.ExecError;
        var delta: f128 = -@as(f128, row.rhs);
        for (row.coefficients, model.estimates) |v, beta| delta += @as(f128, v) * beta;
        difference[i] = @floatCast(delta);
        for (rows, 0..) |other, j| {
            if (other.coefficients.len != p) return error.ExecError;
            var value: f128 = 0;
            for (0..p) |l| for (0..p) |k| {
                value += @as(f128, row.coefficients[l]) * model.covariance_kernel[l * p + k] * other.coefficients[k];
            };
            covariance[i * q + j] = @floatCast(value);
            scaled[i * q + j] = value;
        }
        if (!(scaled[i * q + i] > 0)) return error.ExecError;
        scales[i] = @sqrt(scaled[i * q + i]);
        inverse_scaled[i * q + i] = 1;
    }
    for (0..q) |i| for (0..q) |j| {
        scaled[i * q + j] /= scales[i] * scales[j];
    };
    for (0..q) |j| {
        var pivot = j;
        for (j + 1..q) |i| if (@abs(scaled[i * q + j]) > @abs(scaled[pivot * q + j])) {
            pivot = i;
        };
        if (@abs(scaled[pivot * q + j]) <= model.rank_tolerance) return error.ExecError;
        for (0..q) |k| {
            std.mem.swap(f128, &scaled[j * q + k], &scaled[pivot * q + k]);
            std.mem.swap(f128, &inverse_scaled[j * q + k], &inverse_scaled[pivot * q + k]);
        }
        const divisor = scaled[j * q + j];
        for (0..q) |k| {
            scaled[j * q + k] /= divisor;
            inverse_scaled[j * q + k] /= divisor;
        }
        for (0..q) |i| {
            if (i == j) continue;
            const factor = scaled[i * q + j];
            for (0..q) |k| {
                scaled[i * q + k] -= factor * scaled[j * q + k];
                inverse_scaled[i * q + k] -= factor * inverse_scaled[j * q + k];
            }
        }
    }
    const inverse = try a.alloc(f64, q * q);
    const solution = try a.alloc(f64, q);
    for (0..q) |i| {
        var value: f128 = 0;
        for (0..q) |j| {
            inverse[i * q + j] = @floatCast(inverse_scaled[i * q + j] / (scales[i] * scales[j]));
            value += @as(f128, inverse[i * q + j]) * difference[j];
        }
        solution[i] = @floatCast(value);
    }
    return .{ .dimension = q, .covariance = covariance, .difference = difference, .inverse = inverse, .solution = solution };
}
fn renderIntermediate(a: A, out: *std.ArrayList(u8), model: []const u8, response: []const u8, spec: Spec, values: Intermediate) !void {
    const name = spec.label orelse try std.fmt.allocPrint(a, "{d}", .{spec.number});
    try out.print(a, "\nThe REG Procedure\nModel: {s}\nTest {s} Intermediate Calculations for Dependent Variable {s}\n", .{ model, name, response });
    for ([_][]const u8{ "TestCov", "InvTestCov" }, [_][]const f64{ values.covariance, values.inverse }, [_][]const f64{ values.difference, values.solution }, [_][]const u8{ "Lb-c", "InvCov*(Lb-c)" }) |table, matrix, border, last| {
        try out.print(a, "\n{s}\nRow", .{table});
        for (0..values.dimension) |j| try out.print(a, " Col{d}", .{j + 1});
        try out.print(a, " {s}\n", .{last});
        for (0..values.dimension) |i| {
            try out.print(a, "{d}", .{i + 1});
            for (0..values.dimension) |j| try out.print(a, " {e:.12}", .{matrix[i * values.dimension + j]});
            try out.print(a, " {e:.12}\n", .{border[i]});
        }
    }
}
pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), model_label: []const u8, response: []const u8, spec: Spec, model: @import("reg_diagnostics.zig").Result, noprint: bool) diag.Error!void {
    // A residual variance below the energy of64 binary64 rounding errors
    // cannot certify inference for an exactly/near-exactly fitted response.
    const u = std.math.floatEps(f64);
    if (model.fit.sse <= 4096 * u * u * model.fit.sst_uncorrected) return proc.failGap(cx.diags, 0, "PROC REG TEST: zero or numerically unresolved residual variance is not implemented", .{});
    const geometry = hypothesis.fromRegression(model, model.singular);
    const result = hypothesis.evaluate(cx.arena, geometry, spec.rows, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC REG TEST: unsupported hypothesis covariance or rank calculation", .{});
    };
    if (result.status != .estimable or result.f == null) return proc.failGap(cx.diags, 0, "PROC REG TEST: nonestimable, inconsistent, zero-rank, or missing-inference hypothesis output is not implemented", .{});
    if (spec.print) {
        if (result.rank != spec.rows.len) return proc.failGap(cx.diags, 0, "PROC REG TEST: PRINT for dependent hypothesis rows is not implemented", .{});
        const values = intermediate(cx.arena, geometry, spec.rows) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC REG TEST: PRINT inverse is numerically unavailable", .{});
        };
        if (!noprint) try renderIntermediate(cx.arena, out, model_label, response, spec, values);
    }
    if (!noprint) try render(cx.arena, out, model_label, response, spec, result, model.fit.mse);
}
