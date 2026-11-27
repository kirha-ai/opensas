//! Multivariate REG hypotheses, S154 physical pp.8588–8589,8644–8647.
//! F transformations are exactly the formulas on physical pp.113–114.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const Constraint = @import("reg_restrict.zig").Constraint;
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;
pub const Spec = struct {
    statement_index: usize,
    number: usize,
    label: ?[]const u8,
    linear: []const Constraint,
    transform: []const []const f64, // one transformed response per column
    print: bool = false,
    exact: bool = false,
};
pub const Inference = enum { exact_f, approximate_f, upper_bound_f };
pub const Statistic = struct { inference: Inference = .approximate_f, value: f64, f: f64, numerator_df: f64, denominator_df: f64, probability: f64 };
pub const Result = struct { error_matrix: []const f64, hypothesis: []const f64, roots: []const f64, p: usize, q: usize, s: usize, m: f64, n: f64, statistics: [4]Statistic };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token, parameters: []const []const u8, responses: []const []const u8, intercept: bool, statement_index: usize, number: usize, label: ?[]const u8) diag.Error!Spec {
    const names = try cx.arena.alloc([]const u8, parameters.len + responses.len);
    @memcpy(names[0..parameters.len], parameters);
    @memcpy(names[parameters.len..], responses);
    for (parameters) |parameter| for (responses) |response| {
        if (std.ascii.eqlIgnoreCase(parameter, response)) return proc.failGap(cx.diags, 0, "PROC REG MTEST: a name shared by parameter and response roles is not implemented", .{});
    };
    var slash: usize = 0;
    while (slash < t.len and t[slash].tag != .slash) slash += 1;
    var linear: std.ArrayList(Constraint) = .empty;
    var transform: std.ArrayList([]const f64) = .empty;
    if (slash > 0) {
        const equations = try @import("reg_restrict.zig").parse(cx, t[0..slash], names);
        for (equations) |equation| {
            const lhs = equation.coefficients[0..parameters.len];
            const rhs = equation.coefficients[parameters.len..];
            const has_l = for (lhs) |v| {
                if (v != 0) break true;
            } else false;
            const has_m = for (rhs) |v| {
                if (v != 0) break true;
            } else false;
            if (has_l and has_m) return cx.diags.fail(error.ParseError, 0, "PROC REG MTEST: an equation cannot mix response and regressor roles", .{});
            if (has_m) {
                if (equation.rhs != 0) return cx.diags.fail(error.ParseError, 0, "PROC REG MTEST: response equations require a zero constant", .{});
                try transform.append(cx.arena, rhs);
            } else if (has_l) try linear.append(cx.arena, .{ .coefficients = lhs, .rhs = equation.rhs }) else return proc.failGap(cx.diags, 0, "PROC REG MTEST: zero-rank hypotheses are not implemented", .{});
        }
    }
    if (linear.items.len == 0) {
        for (@as(usize, if (intercept) 1 else 0)..parameters.len) |j| {
            const row = try cx.arena.alloc(f64, parameters.len);
            @memset(row, 0);
            row[j] = 1;
            try linear.append(cx.arena, .{ .coefficients = row, .rhs = 0 });
        }
    }
    if (transform.items.len == 0) {
        for (0..responses.len) |j| {
            const column = try cx.arena.alloc(f64, responses.len);
            @memset(column, 0);
            column[j] = 1;
            try transform.append(cx.arena, column);
        }
    }
    var result = Spec{ .statement_index = statement_index, .number = number, .label = label, .linear = linear.items, .transform = transform.items };
    var i = slash + 1;
    while (i < t.len) {
        if (t[i].tag != .name) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MTEST: invalid option", .{});
        if (std.ascii.eqlIgnoreCase(t[i].text, "print")) {
            result.print = true;
            i += 1;
        } else if (std.ascii.eqlIgnoreCase(t[i].text, "mstat")) {
            if (i + 2 >= t.len or t[i + 1].tag != .eq or t[i + 2].tag != .name) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MTEST: MSTAT requires FAPPROX or EXACT", .{});
            if (std.ascii.eqlIgnoreCase(t[i + 2].text, "exact")) result.exact = true else if (!std.ascii.eqlIgnoreCase(t[i + 2].text, "fapprox")) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MTEST: invalid MSTAT method", .{});
            i += 3;
        } else if (std.ascii.eqlIgnoreCase(t[i].text, "details") or std.ascii.eqlIgnoreCase(t[i].text, "canprint")) return proc.failGap(cx.diags, t[i].line, "PROC REG MTEST: {s} is not implemented", .{t[i].text}) else return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MTEST: unknown option {s}", .{t[i].text});
    }
    if (result.exact) return proc.failGap(cx.diags, 0, "PROC REG MTEST: MSTAT=EXACT output and general exact tails are not implemented", .{});
    return result;
}

fn inverse(a: A, matrix: []const f128, p: usize) ![]const f128 {
    const m = try a.dupe(f128, matrix);
    const inv = try a.alloc(f128, p * p);
    @memset(inv, 0);
    var scale: f128 = 0;
    for (m) |v| scale = @max(scale, @abs(v));
    if (!(scale > 0)) return error.ExecError;
    for (0..p) |j| inv[j * p + j] = 1;
    for (0..p) |j| {
        var pivot = j;
        for (j + 1..p) |i| if (@abs(m[i * p + j]) > @abs(m[pivot * p + j])) {
            pivot = i;
        };
        if (@abs(m[pivot * p + j]) <= scale * 0x1p-44) return error.ExecError;
        for (0..p) |k| {
            std.mem.swap(f128, &m[j * p + k], &m[pivot * p + k]);
            std.mem.swap(f128, &inv[j * p + k], &inv[pivot * p + k]);
        }
        const divisor = m[j * p + j];
        for (0..p) |k| {
            m[j * p + k] /= divisor;
            inv[j * p + k] /= divisor;
        }
        for (0..p) |i| {
            if (i == j) continue;
            const factor = m[i * p + j];
            for (0..p) |k| {
                m[i * p + k] -= factor * m[j * p + k];
                inv[i * p + k] -= factor * inv[j * p + k];
            }
        }
    }
    return inv;
}

fn stat(value: f64, f: f64, d1: f64, d2: f64) diag.Error!Statistic {
    if (!std.math.isFinite(value) or !std.math.isFinite(f) or f < 0 or !(d1 > 0 and d2 > 0)) return error.ExecError;
    const probability = @import("../functions.zig").betaI(d2 / (d2 + d1 * f), d2 / 2, d1 / 2);
    if (!std.math.isFinite(probability)) return error.ExecError;
    return .{ .value = value, .f = f, .numerator_df = d1, .denominator_df = d2, .probability = probability };
}

fn largerRoots(a: A, e: []const f64, h: []const f64, p: usize) diag.Error![]f64 {
    const lower = try a.alloc(f128, p * p);
    const inverse_lower = try a.alloc(f128, p * p);
    const symmetric = try a.alloc(f128, p * p);
    @memset(lower, 0);
    @memset(inverse_lower, 0);
    var scale: f128 = 0;
    for (e) |v| {
        if (!std.math.isFinite(v)) return error.ExecError;
        scale = @max(scale, @abs(@as(f128, v)));
    }
    for (h) |v| if (!std.math.isFinite(v)) return error.ExecError;
    for (0..p) |i| for (0..i + 1) |j| {
        if (@abs(e[i * p + j] - e[j * p + i]) > 1e-12 * @max(1, @abs(e[i * p + j])) or @abs(h[i * p + j] - h[j * p + i]) > 1e-12 * @max(1, @abs(h[i * p + j]))) return error.ExecError;
        var sum: f128 = e[i * p + j];
        for (0..j) |k| sum -= lower[i * p + k] * lower[j * p + k];
        if (i == j) {
            if (!(sum > scale * 0x1p-44)) return error.ExecError;
            lower[i * p + j] = @sqrt(sum);
        } else lower[i * p + j] = sum / lower[j * p + j];
    };
    for (0..p) |j| for (0..p) |i| {
        var sum: f128 = if (i == j) 1 else 0;
        for (0..i) |k| sum -= lower[i * p + k] * inverse_lower[k * p + j];
        inverse_lower[i * p + j] = sum / lower[i * p + i];
    };
    var whitened_scale: f128 = 0;
    for (0..p) |i| for (0..p) |j| {
        var sum: f128 = 0;
        for (0..p) |l| for (0..p) |m| {
            sum += inverse_lower[i * p + l] * @as(f128, h[l * p + m]) * inverse_lower[j * p + m];
        };
        symmetric[i * p + j] = sum;
        whitened_scale = @max(whitened_scale, @abs(sum));
    };
    var converged = false;
    for (0..100 * p * p) |_| {
        var r: usize = 0;
        var c: usize = 0;
        var largest: f128 = 0;
        for (0..p) |i| for (i + 1..p) |j| {
            if (@abs(symmetric[i * p + j]) > largest) {
                largest = @abs(symmetric[i * p + j]);
                r = i;
                c = j;
            }
        };
        if (largest <= @max(1, whitened_scale) * 0x1p-100) {
            converged = true;
            break;
        }
        const off = symmetric[r * p + c];
        const tau = (symmetric[c * p + c] - symmetric[r * p + r]) / (2 * off);
        const t = (if (tau >= 0) @as(f128, 1) else -1) / (@abs(tau) + @sqrt(1 + tau * tau));
        const cosine = 1 / @sqrt(1 + t * t);
        const sine = t * cosine;
        symmetric[r * p + r] -= t * off;
        symmetric[c * p + c] += t * off;
        symmetric[r * p + c] = 0;
        symmetric[c * p + r] = 0;
        for (0..p) |j| {
            if (j == r or j == c) continue;
            const jr = symmetric[j * p + r];
            const jc = symmetric[j * p + c];
            symmetric[j * p + r] = cosine * jr - sine * jc;
            symmetric[r * p + j] = symmetric[j * p + r];
            symmetric[j * p + c] = sine * jr + cosine * jc;
            symmetric[c * p + j] = symmetric[j * p + c];
        }
    }
    if (!converged) return error.ExecError;
    const roots = try a.alloc(f64, p);
    for (roots, 0..) |*root, j| {
        const value = symmetric[j * p + j];
        if (value < -@max(1, whitened_scale) * 0x1p-44) return error.ExecError;
        root.* = @floatCast(@max(0, value));
    }
    std.mem.sort(f64, roots, {}, std.sort.desc(f64));
    return roots;
}

pub fn statistics(a: A, e: []const f64, h: []const f64, p: usize, q: usize, error_df: usize, exact: bool) diag.Error!Result {
    if (p == 0 or p > 16 or q == 0 or e.len != p * p or h.len != p * p or error_df == 0) return error.ExecError;
    const s = @min(p, q);
    if (exact and s > 1) return error.ExecError;
    const roots = if (p > 2) try largerRoots(a, e, h, p) else try a.alloc(f64, p);
    if (p == 1) {
        if (!(e[0] > 0) or h[0] < 0) return error.ExecError;
        roots[0] = h[0] / e[0];
    } else if (p == 2) {
        if (!(e[0] > 0) or @abs(e[1] - e[2]) > 1e-12 * @max(1, @abs(e[1])) or @abs(h[1] - h[2]) > 1e-12 * @max(1, @abs(h[1]))) return error.ExecError;
        const aa = @sqrt(@as(f128, e[0]));
        const bb = @as(f128, e[1]) / aa;
        const remainder = @as(f128, e[3]) - bb * bb;
        if (!(remainder > @abs(@as(f128, e[3])) * 0x1p-44)) return error.ExecError;
        const cc = @sqrt(remainder);
        const u = 1 / aa;
        const v = -bb / (aa * cc);
        const w = 1 / cc;
        const a00 = u * u * h[0];
        const a01 = u * (v * h[0] + w * h[1]);
        const a11 = v * v * h[0] + 2 * v * w * h[1] + w * w * h[3];
        const center = (a00 + a11) / 2;
        const half_difference = (a00 - a11) / 2;
        const high = center + @sqrt(half_difference * half_difference + a01 * a01);
        var low = if (high > 0) (a00 * a11 - a01 * a01) / high else @as(f128, 0);
        if (high < 0 or low < -0x1p-44 * @max(1, high)) return error.ExecError;
        low = @max(0, low);
        roots[0] = @floatCast(high);
        roots[1] = @floatCast(low);
    }
    var lambda: f64 = 1;
    var pillai: f64 = 0;
    var hotelling: f64 = 0;
    for (roots) |root| {
        lambda /= 1 + root;
        pillai += root / (1 + root);
        hotelling += root;
    }
    const pf: f64 = @floatFromInt(p);
    const qf: f64 = @floatFromInt(q);
    const vf: f64 = @floatFromInt(error_df);
    const sf: f64 = @floatFromInt(s);
    const m = (@abs(pf - qf) - 1) / 2;
    const n = (vf - pf - 1) / 2;
    var table: [4]Statistic = undefined;
    const values = [_]f64{ lambda, pillai, hotelling, roots[0] };
    if (s == 1) {
        const d1 = @max(pf, qf);
        const d2 = vf - d1 + qf;
        const f = roots[0] * d2 / d1;
        for (&table, values) |*row, value| {
            row.* = try stat(value, f, d1, d2);
            row.inference = .exact_f;
        }
    } else {
        const r = vf - (pf - qf + 1) / 2;
        const u = (pf * qf - 2) / 4;
        const t = if (pf * pf + qf * qf - 5 > 0) @sqrt((pf * pf * qf * qf - 4) / (pf * pf + qf * qf - 5)) else 1;
        const power = std.math.pow(f64, lambda, 1 / t);
        table[0] = try stat(lambda, (1 - power) / power * (r * t - 2 * u) / (pf * qf), pf * qf, r * t - 2 * u);
        const pd1 = sf * (2 * m + sf + 1);
        const pd2 = sf * (2 * n + sf + 1);
        table[1] = try stat(pillai, (pd2 / pd1) * pillai / (sf - pillai), pd1, pd2);
        if (n > 0) {
            // Evaluate 1/(b-1) directly: this also handles the n=1 limit
            // without dividing by zero in the published intermediate b.
            const denominator = 2 * (2 * n + 1) * (n - 1);
            const reciprocal = denominator / ((pf + 2 * n) * (qf + 2 * n) - denominator);
            const hd2 = 4 + (pf * qf + 2) * reciprocal;
            const c = (2 + (pf * qf + 2) * reciprocal) / (2 * n);
            table[2] = try stat(hotelling, (hotelling / c) * hd2 / (pf * qf), pf * qf, hd2);
        } else {
            const hd1 = sf * (2 * m + sf + 1);
            const hd2 = 2 * (sf * n + 1);
            table[2] = try stat(hotelling, hd2 * hotelling / (sf * hd1), hd1, hd2);
        }
        const rd1 = @max(pf, qf);
        const rd2 = vf - rd1 + qf;
        table[3] = try stat(roots[0], roots[0] * rd2 / rd1, rd1, rd2);
        table[3].inference = .upper_bound_f;
        if (s <= 2) table[0].inference = .exact_f;
    }
    return .{ .error_matrix = e, .hypothesis = h, .roots = roots, .p = p, .q = q, .s = s, .m = m, .n = n, .statistics = table };
}

pub fn evaluate(a: A, fits: []const Fit, weights: []const f64, spec: Spec) diag.Error!Result {
    const responses = fits.len;
    const q = spec.linear.len;
    const k = spec.transform.len;
    if (responses == 0 or q == 0 or k == 0 or k > 16) return error.ExecError;
    const p = fits[0].coefficients.len;
    const n = fits[0].residuals.len;
    if (q > p or weights.len != n) return error.ExecError;
    for (fits) |fit| if (fit.rank != p or fit.coefficients.len != p or fit.residuals.len != n or fit.df_error != fits[0].df_error) return error.ExecError;
    for (spec.transform) |column| if (column.len != responses) return error.ExecError;
    for (spec.linear) |row| if (row.coefficients.len != p) return error.ExecError;
    const covariance = try a.alloc(f128, q * q);
    @memset(covariance, 0);
    const effect = try a.alloc(f128, q * k);
    @memset(effect, 0);
    for (spec.linear, 0..) |row, i| {
        if (row.coefficients.len != p) return error.ExecError;
        for (spec.linear, 0..) |other, j| for (0..p) |l| for (0..p) |m| {
            covariance[i * q + j] += @as(f128, row.coefficients[l]) * fits[0].covariance_unscaled[l * p + m] * other.coefficients[m];
        };
        for (spec.transform, 0..) |column, j| for (fits, column) |fit, coefficient| {
            var raw: f128 = -@as(f128, row.rhs);
            for (row.coefficients, fit.coefficients) |l, beta| raw += @as(f128, l) * beta;
            effect[i * k + j] += raw * coefficient;
        };
    }
    const inverse_covariance = try inverse(a, covariance, q);
    const h = try a.alloc(f64, k * k);
    const e = try a.alloc(f64, k * k);
    for (0..k) |i| for (0..k) |j| {
        var hs: f128 = 0;
        for (0..q) |l| for (0..q) |m| {
            hs += effect[l * k + i] * inverse_covariance[l * q + m] * effect[m * k + j];
        };
        var es: f128 = 0;
        for (weights, 0..) |weight, observation| {
            var left: f128 = 0;
            var right: f128 = 0;
            for (fits, 0..) |fit, response| {
                left += @as(f128, spec.transform[i][response]) * fit.residuals[observation];
                right += @as(f128, spec.transform[j][response]) * fit.residuals[observation];
            }
            es += weight * left * right;
        }
        h[i * k + j] = @floatCast(hs);
        e[i * k + j] = @floatCast(es);
    };
    return statistics(a, e, h, k, q, fits[0].df_error, spec.exact);
}
