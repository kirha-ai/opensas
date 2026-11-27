//! Linear equality restrictions for REG, SAS/STAT 15.4 physical pp.8593–8595.
//! For R beta=r, G=(X'WX)^-1 and H=R G R', beta_R=beta-G R'H^-1(R beta-r).
//! The covariance kernel is G-G R'H^-1 R G. Lagrange multipliers use the
//! same sign convention as the augmented normal equations [A R'; R 0].
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;
pub const Constraint = struct { coefficients: []const f64, rhs: f64 };
pub const Multiplier = struct { estimate: f64, se: f64, t: f64, probability: f64 };
const Expression = struct { coefficients: []f64, constant: f64 };

fn expression(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, names: []const []const u8, statement: []const u8) diag.Error!Expression {
    const coefficients = try cx.arena.alloc(f64, names.len);
    @memset(coefficients, 0);
    var constant: f64 = 0;
    var terms: usize = 0;
    while (i.* < t.len and t[i.*].tag != .comma and t[i.*].tag != .eq) {
        var sign: f64 = 1;
        if (t[i.*].tag == .minus or t[i.*].tag == .plus) {
            if (t[i.*].tag == .minus) sign = -1;
            i.* += 1;
        } else if (terms > 0) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG {s}: expected + or - between terms", .{statement});
        if (i.* == t.len) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: missing term", .{statement});
        var coefficient: f64 = sign;
        if (t[i.*].tag == .number) {
            coefficient *= std.fmt.parseFloat(f64, t[i.*].text) catch return error.ParseError;
            i.* += 1;
            if (i.* < t.len and t[i.*].tag == .star) {
                i.* += 1;
                if (i.* == t.len or t[i.*].tag != .name) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: expected a parameter after *", .{statement});
            } else {
                constant += coefficient;
                terms += 1;
                continue;
            }
        }
        if (t[i.*].tag != .name) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG {s}: expected a linear parameter term", .{statement});
        const index = for (names, 0..) |name, j| {
            if (std.ascii.eqlIgnoreCase(name, t[i.*].text)) break j;
        } else return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG {s}: {s} is not a parameter in the current MODEL", .{ statement, t[i.*].text });
        coefficients[index] += coefficient;
        i.* += 1;
        terms += 1;
    }
    if (terms == 0) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: empty equation", .{statement});
    if (!std.math.isFinite(constant)) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: nonfinite constant", .{statement});
    for (coefficients) |v| if (!std.math.isFinite(v)) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: nonfinite coefficient", .{statement});
    return .{ .coefficients = coefficients, .constant = constant };
}

/// Tokens exclude RESTRICT and its semicolon. A comma starts a new equation;
/// a=b=c expands to a-b=0 and b-c=0 in the same constraint system.
pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token, names: []const []const u8) diag.Error![]const Constraint {
    return parseFor(cx, tokens, names, "RESTRICT");
}
pub fn parseFor(cx: proc.ProcCtx, tokens: []const lex.Token, names: []const []const u8, statement: []const u8) diag.Error![]const Constraint {
    var result: std.ArrayList(Constraint) = .empty;
    var i: usize = 0;
    while (i < tokens.len) {
        var left = try expression(cx, tokens, &i, names, statement);
        var equality = false;
        while (i < tokens.len and tokens[i].tag == .eq) {
            equality = true;
            i += 1;
            const right = try expression(cx, tokens, &i, names, statement);
            const row = try cx.arena.alloc(f64, names.len);
            for (row, left.coefficients, right.coefficients) |*v, l, r| v.* = l - r;
            try result.append(cx.arena, .{ .coefficients = row, .rhs = right.constant - left.constant });
            left = right;
        }
        if (!equality) try result.append(cx.arena, .{ .coefficients = left.coefficients, .rhs = -left.constant });
        if (i < tokens.len) {
            if (tokens[i].tag != .comma) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC REG {s}: expected comma", .{statement});
            i += 1;
            if (i == tokens.len) return cx.diags.fail(error.ParseError, 0, "PROC REG {s}: missing equation after comma", .{statement});
        }
    }
    if (result.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC REG {s} requires an equation", .{statement});
    return result.items;
}

pub fn apply(a: A, fit: *Fit, x: []const f64, y: []const f64, weights: []const f64, constraints: []const Constraint) diag.Error![]const Multiplier {
    const p = fit.coefficients.len;
    const q = constraints.len;
    if (q == 0) return &.{};
    // Redundant/inconsistent and aliased systems require SAS's ordered
    // zero-DF restriction handling; don't silently drop a supplied equation.
    if (fit.rank != p or q >= p or x.len != y.len * p or weights.len != y.len) return error.ExecError;
    const rg = try a.alloc(f128, q * p);
    const h = try a.alloc(f128, q * q);
    const inv = try a.alloc(f128, q * q);
    const discrepancy = try a.alloc(f128, q);
    @memset(rg, 0);
    @memset(h, 0);
    @memset(inv, 0);
    for (constraints, 0..) |restriction, i| {
        if (restriction.coefficients.len != p) return error.ExecError;
        discrepancy[i] = -@as(f128, restriction.rhs);
        for (0..p) |j| {
            discrepancy[i] += @as(f128, restriction.coefficients[j]) * fit.coefficients[j];
            for (0..p) |k| rg[i * p + j] += @as(f128, restriction.coefficients[k]) * fit.covariance_unscaled[k * p + j];
        }
        inv[i * q + i] = 1;
    }
    for (0..q) |i| for (0..q) |j| for (0..p) |k| {
        h[i * q + j] += rg[i * p + k] * constraints[j].coefficients[k];
    };
    var maximum: f128 = 0;
    for (h) |v| maximum = @max(maximum, @abs(v));
    if (!(maximum > 0)) return error.ExecError;
    for (0..q) |j| {
        var pivot = j;
        for (j + 1..q) |i| if (@abs(h[i * q + j]) > @abs(h[pivot * q + j])) {
            pivot = i;
        };
        if (@abs(h[pivot * q + j]) <= maximum * 0x1p-44) return error.ExecError;
        for (0..q) |k| {
            std.mem.swap(f128, &h[j * q + k], &h[pivot * q + k]);
            std.mem.swap(f128, &inv[j * q + k], &inv[pivot * q + k]);
        }
        const scale = h[j * q + j];
        for (0..q) |k| {
            h[j * q + k] /= scale;
            inv[j * q + k] /= scale;
        }
        for (0..q) |i| {
            if (i == j) continue;
            const factor = h[i * q + j];
            for (0..q) |k| {
                h[i * q + k] -= factor * h[j * q + k];
                inv[i * q + k] -= factor * inv[j * q + k];
            }
        }
    }
    const lambda = try a.alloc(f128, q);
    @memset(lambda, 0);
    for (0..q) |i| for (0..q) |j| {
        lambda[i] += inv[i * q + j] * discrepancy[j];
    };
    for (fit.coefficients, 0..) |*b, j| {
        var v: f128 = b.*;
        for (0..q) |i| v -= rg[i * p + j] * lambda[i];
        b.* = @floatCast(v);
    }
    for (0..p) |j| for (0..p) |k| {
        var change: f128 = 0;
        for (0..q) |l| for (0..q) |m| {
            change += rg[l * p + j] * inv[l * q + m] * rg[m * p + k];
        };
        const old = fit.covariance_unscaled[j * p + k];
        const value: f64 = @floatCast(@as(f128, old) - change);
        if (j == k and value < -@abs(old) * 1e-12) return error.ExecError;
        fit.covariance_unscaled[j * p + k] = if (j == k) @max(0, value) else value;
    };
    // An explicitly fixed parameter is a constant, not an estimated random
    // quantity. Enforce that exact identity after projection rather than
    // assigning spurious finite t statistics to cancellation remnants.
    for (constraints) |restriction| {
        var fixed: ?usize = null;
        var terms: usize = 0;
        for (restriction.coefficients, 0..) |coefficient, j| if (coefficient != 0) {
            terms += 1;
            fixed = j;
        };
        if (terms == 1) {
            const j = fixed.?;
            fit.coefficients[j] = restriction.rhs / restriction.coefficients[j];
            for (0..p) |k| {
                fit.covariance_unscaled[j * p + k] = 0;
                fit.covariance_unscaled[k * p + j] = 0;
            }
        }
    }
    var sse: f128 = 0;
    for (y, weights, 0..) |value, w, i| {
        var prediction: f128 = 0;
        var leverage: f128 = 0;
        for (0..p) |j| {
            prediction += @as(f128, x[i * p + j]) * fit.coefficients[j];
            for (0..p) |k| leverage += @as(f128, x[i * p + j]) * fit.covariance_unscaled[j * p + k] * x[i * p + k];
        }
        fit.fitted[i] = @floatCast(prediction);
        fit.residuals[i] = value - fit.fitted[i];
        fit.leverage[i] = @floatCast(@max(0, @min(1, leverage * w)));
        sse += @as(f128, w) * fit.residuals[i] * fit.residuals[i];
    }
    fit.rank -= q;
    fit.df_error += q;
    fit.sse = @floatCast(sse);
    fit.mse = fit.sse / @as(f64, @floatFromInt(fit.df_error));
    for (fit.covariance, fit.covariance_unscaled) |*v, base| v.* = base * fit.mse;
    for (fit.se, 0..) |*v, j| v.* = @sqrt(fit.covariance[j * p + j]);
    const result = try a.alloc(Multiplier, q);
    for (result, 0..) |*v, i| {
        const estimate: f64 = @floatCast(lambda[i]);
        const se: f64 = @floatCast(@sqrt(@as(f128, fit.mse) * inv[i * q + i]));
        const t = if (se > 0) estimate / se else std.math.nan(f64);
        // Releasing one restriction gives independent extra SS and residual SS.
        // Thus t²/df_R=extraSS/SSE_R ~ Beta(1/2,(df_R-1)/2), not Student t.
        const z = t * t / @as(f64, @floatFromInt(fit.df_error));
        const probability = if (std.math.isFinite(z) and z >= 0 and z <= 1 and fit.df_error > 1) @import("../functions.zig").betaI(1 - z, @as(f64, @floatFromInt(fit.df_error - 1)) / 2, 0.5) else std.math.nan(f64);
        v.* = .{ .estimate = estimate, .se = se, .t = t, .probability = probability };
    }
    return result;
}
