//! Standalone beta/power endpoint and generalized Pareto fitting support.
//! SAS convention: Pareto alpha is minus the usual extreme-value shape xi.
const std = @import("std");
const f = @import("../functions.zig");
pub const Family = enum { beta, power, pareto };
pub const Parameters = struct { theta: f64 = 0, sigma: f64 = 1, alpha: f64 = 1, beta: f64 = 1 };
/// Null requests estimation. Caller applies SAS defaults before entering.
pub const Fixed = struct { theta: ?f64 = 0, sigma: ?f64 = null, alpha: ?f64 = null, beta: ?f64 = null };
pub const Method = enum { mle, epm };
/// Internal solver budget, not the accepted-but-ineffective SAS beta MAXITER.
pub const Controls = struct { maxiter: usize = 1000, tolerance: f64 = 1e-9, method: Method = .mle };
pub const Reason = enum { invalid_sample, invalid_parameters, invalid_controls, unsupported_combination, unsupported_method, outside_support, no_local_maximum, iteration_limit, boundary_solution };
pub const Curve = struct { parameters: Parameters, log_likelihood: f64, iterations: usize = 0 };
pub const Result = union(enum) { converged: Curve, nonconverged: struct { reason: Reason, best: ?Curve = null } };
fn fail(reason: Reason) Result {
    return .{ .nonconverged = .{ .reason = reason } };
}

pub fn logLikelihood(family: Family, x: []const f64, p: Parameters) f64 {
    if (!(p.sigma > 0) or !std.math.isFinite(p.sigma) or !std.math.isFinite(p.theta) or !std.math.isFinite(p.alpha)) return -std.math.inf(f64);
    if (family != .pareto and (!(p.alpha > 0) or !(p.beta > 0) or !std.math.isFinite(p.beta))) return -std.math.inf(f64);
    var sum: f64 = 0;
    const beta = if (family == .power) 1 else p.beta;
    const lb = if (family == .beta) f.lgammaOf(p.alpha) + f.lgammaOf(beta) - f.lgammaOf(p.alpha + beta) else if (family == .power) -@log(p.alpha) else 0;
    for (x) |v| {
        const y = (v - p.theta) / p.sigma;
        if (!(y > 0)) return -std.math.inf(f64);
        if (family == .pareto) {
            if (p.alpha == 1 and y <= 1) {
                sum -= @log(p.sigma);
                continue;
            }
            if (p.alpha * y >= 1) return -std.math.inf(f64);
            // Stable through alpha=0, including finite-difference derivatives.
            const a = p.alpha * y;
            const ratio = if (@abs(a) < 1e-5) -y * (1 + a * (0.5 + a * (1.0 / 3.0 + a / 4))) else std.math.log1p(-a) / p.alpha;
            sum += -@log(p.sigma) + (1 - p.alpha) * ratio;
        } else {
            if (family == .power and y == 1) {
                sum += @log(p.alpha / p.sigma);
                continue;
            }
            if (!(y < 1)) return -std.math.inf(f64);
            sum += -@log(p.sigma) - lb + (p.alpha - 1) * @log(y) + (beta - 1) * std.math.log1p(-y);
        }
    }
    return if (std.math.isFinite(sum)) sum else -std.math.inf(f64);
}

pub fn fit(family: Family, x: []const f64, fixed: Fixed, controls: Controls) Result {
    if (controls.method != .mle) return fail(.unsupported_method);
    if (x.len < 2) return fail(.invalid_sample);
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return fail(.invalid_sample);
    inline for (std.meta.fields(Fixed)) |field| if (@field(fixed, field.name)) |v| {
        if (!std.math.isFinite(v)) return fail(.invalid_parameters);
    };
    if (fixed.sigma != null and fixed.sigma.? <= 0) return fail(.invalid_parameters);
    if (family != .pareto and ((fixed.alpha != null and fixed.alpha.? <= 0) or (fixed.beta != null and fixed.beta.? <= 0))) return fail(.invalid_parameters);
    if (controls.maxiter == 0 or !(controls.tolerance > 0) or !std.math.isFinite(controls.tolerance)) return fail(.invalid_controls);
    if (family == .pareto and fixed.theta == null) return fail(.unsupported_combination); // M9 syntax rejects EST.
    if (fixed.theta != null and x[0] <= fixed.theta.?) return fail(.outside_support);
    if (family != .pareto and fixed.theta != null and fixed.sigma != null and x[x.len - 1] >= fixed.theta.? + fixed.sigma.?) return fail(.outside_support);
    if (fixed.theta != null and fixed.sigma != null and fixed.alpha != null and (family != .beta or fixed.beta != null)) {
        const p: Parameters = .{ .theta = fixed.theta.?, .sigma = fixed.sigma.?, .alpha = fixed.alpha.?, .beta = fixed.beta orelse 1 };
        const ll = logLikelihood(family, x, p);
        return if (std.math.isFinite(ll)) .{ .converged = .{ .parameters = p, .log_likelihood = ll } } else fail(.outside_support);
    }
    if (x[0] == x[x.len - 1]) return fail(.invalid_sample);
    if (family == .power and fixed.theta != null) {
        const sigma = fixed.sigma orelse (x[x.len - 1] - fixed.theta.?);
        var sum: f64 = 0;
        for (x) |v| sum += @log((v - fixed.theta.?) / sigma);
        const p: Parameters = .{ .theta = fixed.theta.?, .sigma = sigma, .alpha = fixed.alpha orelse (-@as(f64, @floatFromInt(x.len)) / sum) };
        const curve: Curve = .{ .parameters = p, .log_likelihood = logLikelihood(family, x, p) };
        return if (fixed.sigma == null) .{ .nonconverged = .{ .reason = .boundary_solution, .best = curve } } else .{ .converged = curve };
    }
    if (family == .pareto and fixed.alpha != null and fixed.sigma == null and (fixed.alpha.? == 0 or fixed.alpha.? == 1)) {
        var scale: f64 = 0;
        for (x) |v| scale += (v - fixed.theta.?) / @as(f64, @floatFromInt(x.len));
        if (fixed.alpha.? == 1) scale = x[x.len - 1] - fixed.theta.?;
        const p: Parameters = .{ .theta = fixed.theta.?, .sigma = scale, .alpha = fixed.alpha.? };
        return .{ .converged = .{ .parameters = p, .log_likelihood = logLikelihood(.pareto, x, p) } };
    }
    if (family == .pareto and fixed.alpha == null and fixed.sigma == null) return paretoProfile(x, fixed.theta.?, controls);
    return optimize(family, x, fixed, controls);
}

const Problem = struct {
    family: Family,
    x: []const f64,
    fixed: Fixed,
    range: f64,
    fn decode(self: Problem, q: [4]f64) Parameters {
        const lo = self.x[0];
        const hi = self.x[self.x.len - 1];
        var p: Parameters = .{};
        if (self.family != .pareto) {
            p.theta = self.fixed.theta orelse (if (self.fixed.sigma) |s| (hi - s) + (lo - (hi - s)) / (1 + @exp(-q[0])) else lo - self.range * @exp(q[0]));
            p.sigma = self.fixed.sigma orelse (hi + self.range * @exp(q[1]) - p.theta);
            p.alpha = self.fixed.alpha orelse @exp(q[2]);
            p.beta = if (self.family == .power) 1 else self.fixed.beta orelse @exp(q[3]);
        } else {
            p.theta = self.fixed.theta.?;
            // Grimshaw's regular search region is alpha<=1. Beyond it,
            // the endpoint likelihood is unbounded; never call a rounded
            // spike at an observed maximum a converged MLE.
            p.alpha = self.fixed.alpha orelse (1 - @exp(q[2]));
            p.sigma = self.fixed.sigma orelse (@max(@as(f64, 0), p.alpha * (hi - p.theta)) + self.range * @exp(q[1]));
        }
        return p;
    }
    fn value(self: Problem, q: [4]f64) f64 {
        return -logLikelihood(self.family, self.x, self.decode(q)) / @as(f64, @floatFromInt(self.x.len));
    }
};
const Point = struct { q: [4]f64, value: f64 };
fn less(_: void, a: Point, b: Point) bool {
    return a.value < b.value;
}

/// Nelder-Mead in support-preserving coordinates, followed by an explicit
/// boundary check. Finite stopped candidates remain tagged nonconverged.
fn optimize(family: Family, x: []const f64, fixed: Fixed, controls: Controls) Result {
    const problem: Problem = .{ .family = family, .x = x, .fixed = fixed, .range = x[x.len - 1] - x[0] };
    if (family != .pareto and fixed.theta == null and fixed.sigma != null and fixed.sigma.? <= problem.range) return fail(.outside_support);
    var axes: [4]usize = undefined;
    var dim: usize = 0;
    const free = [_]bool{ fixed.theta == null, fixed.sigma == null, fixed.alpha == null, family == .beta and fixed.beta == null };
    for (free, 0..) |yes, j| if (yes) {
        axes[dim] = j;
        dim += 1;
    };
    var global: ?Curve = null;
    var any_converged = false;
    var boundary = false;
    var total: usize = 0;
    for (0..3) |start| {
        var initial: [4]f64 = .{ -2 + @as(f64, @floatFromInt(start)), -2 + @as(f64, @floatFromInt(start)), @log(@as(f64, 2)), @log(@as(f64, 3)) };
        if (family != .pareto and fixed.theta == null and fixed.sigma != null) initial[0] = 0;
        if (family == .pareto) {
            var mean: f64 = 0;
            for (x) |v| mean += (v - fixed.theta.?) / @as(f64, @floatFromInt(x.len));
            initial[2] = @log(1.3 - 0.3 * @as(f64, @floatFromInt(start)));
            initial[1] = @log(mean / problem.range);
        }
        var simplex: [5]Point = undefined;
        simplex[0] = .{ .q = initial, .value = problem.value(initial) };
        for (0..dim) |j| {
            var q = initial;
            q[axes[j]] += 0.2;
            simplex[j + 1] = .{ .q = q, .value = problem.value(q) };
        }
        var converged = false;
        for (0..controls.maxiter) |_| {
            total += 1;
            std.mem.sort(Point, simplex[0 .. dim + 1], {}, less);
            var diameter: f64 = 0;
            for (simplex[1 .. dim + 1]) |p| for (axes[0..dim]) |j| {
                diameter = @max(diameter, @abs(p.q[j] - simplex[0].q[j]));
            };
            if (diameter < @sqrt(controls.tolerance) and simplex[dim].value - simplex[0].value < controls.tolerance and std.math.isFinite(simplex[0].value)) {
                converged = true;
                break;
            }
            var center = simplex[0].q;
            for (axes[0..dim]) |j| {
                center[j] = 0;
                for (simplex[0..dim]) |p| center[j] += p.q[j] / @as(f64, @floatFromInt(dim));
            }
            var reflected = center;
            for (axes[0..dim]) |j| reflected[j] = 2 * center[j] - simplex[dim].q[j];
            const vr = problem.value(reflected);
            if (vr < simplex[0].value) {
                var expanded = center;
                for (axes[0..dim]) |j| expanded[j] = center[j] + 2 * (reflected[j] - center[j]);
                const ve = problem.value(expanded);
                simplex[dim] = if (ve < vr) .{ .q = expanded, .value = ve } else .{ .q = reflected, .value = vr };
            } else if (vr < simplex[dim - 1].value) {
                simplex[dim] = .{ .q = reflected, .value = vr };
            } else {
                var contracted = center;
                for (axes[0..dim]) |j| contracted[j] = center[j] + 0.5 * ((if (vr < simplex[dim].value) reflected[j] else simplex[dim].q[j]) - center[j]);
                const vc = problem.value(contracted);
                if (vc < @min(vr, simplex[dim].value)) simplex[dim] = .{ .q = contracted, .value = vc } else {
                    for (simplex[1 .. dim + 1]) |*p| {
                        for (axes[0..dim]) |j| p.q[j] = (p.q[j] + simplex[0].q[j]) / 2;
                        p.value = problem.value(p.q);
                    }
                }
            }
        }
        std.mem.sort(Point, simplex[0 .. dim + 1], {}, less);
        const p = problem.decode(simplex[0].q);
        const ll = logLikelihood(family, x, p);
        const edge = if (family != .pareto) ((fixed.theta == null and (x[0] - p.theta) / problem.range < 1e-8) or (fixed.sigma == null and (p.theta + p.sigma - x[x.len - 1]) / problem.range < 1e-8)) else p.alpha > 0 and (p.sigma / p.alpha - (x[x.len - 1] - p.theta)) / problem.range < 1e-8;
        if (std.math.isFinite(ll) and (global == null or ll > global.?.log_likelihood)) {
            global = .{ .parameters = p, .log_likelihood = ll };
            any_converged = converged and stationary(problem, simplex[0].q, axes[0..dim]);
            boundary = edge;
        }
    }
    if (global) |*g| {
        g.iterations = total;
        if (any_converged and !boundary) return .{ .converged = g.* };
        // SAS emits no beta curve when endpoint estimation fails. Retain
        // Pareto's finite boundary candidates explicitly as warned fits.
        return .{ .nonconverged = .{ .reason = if (boundary) .boundary_solution else .iteration_limit, .best = if (family != .beta) g.* else null } };
    }
    return fail(.no_local_maximum);
}

fn check(expected: Parameters, result: Result, tolerance: f64) !void {
    const curve = switch (result) {
        .converged => |c| c,
        .nonconverged => |n| {
            std.debug.print("endpoint failure {s}\n", .{@tagName(n.reason)});
            return error.TestUnexpectedResult;
        },
    };
    inline for (std.meta.fields(Parameters)) |field| try std.testing.expectApproxEqAbs(@field(expected, field.name), @field(curve.parameters, field.name), tolerance);
}

test "endpoint beta SAS M9 all fixed estimated combinations" {
    var x: [101]f64 = undefined;
    for (&x, 0..) |*v, i| v.* = f.distQuantile(.beta, (@as(f64, @floatFromInt(i + 1)) - 0.375) / 101.25, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 2 }, .{ .num = 3 } }).?;
    const expected = [_]Parameters{
        .{ .theta = 0, .sigma = 1, .alpha = 2, .beta = 3 },
        .{ .theta = 0.003474, .sigma = 1, .alpha = 2, .beta = 3 },
        .{ .theta = 0, .sigma = 0.990724, .alpha = 2, .beta = 3 },
        .{ .theta = 0.008588, .sigma = 0.977054, .alpha = 2, .beta = 3 },
        .{ .theta = 0, .sigma = 1, .alpha = 2.009625, .beta = 3 },
        .{ .theta = 0.011914, .sigma = 1, .alpha = 1.90133, .beta = 3 },
        .{ .theta = 0, .sigma = 0.98363, .alpha = 2.049554, .beta = 3 },
        .{ .theta = 0.012588, .sigma = 0.979395, .alpha = 1.940936, .beta = 3 },
        .{ .theta = 0, .sigma = 1, .alpha = 2, .beta = 3.016591 },
        .{ .theta = 0.008123, .sigma = 1, .alpha = 2, .beta = 3.111371 },
        .{ .theta = 0, .sigma = 0.96286, .alpha = 2, .beta = 2.803269 },
        .{ .theta = 0.007139, .sigma = 0.964088, .alpha = 2, .beta = 2.891322 },
        .{ .theta = 0, .sigma = 1, .alpha = 2.05622, .beta = 3.088703 },
        .{ .theta = 0.011111, .sigma = 1, .alpha = 1.944047, .beta = 3.071715 },
        .{ .theta = 0, .sigma = 0.957832, .alpha = 1.970388, .beta = 2.739213 },
        .{ .theta = 0.021695, .sigma = 0.910261, .alpha = 1.669283, .beta = 2.349019 },
    };
    for (expected, 0..) |p, mask| {
        const fixed: Fixed = .{ .theta = if (mask & 1 == 0) 0 else null, .sigma = if (mask & 2 == 0) 1 else null, .alpha = if (mask & 4 == 0) 2 else null, .beta = if (mask & 8 == 0) 3 else null };
        const result = fit(.beta, &x, fixed, .{});
        try check(p, result, 1e-4);
    }
}

test "endpoint Pareto SAS M9 negative shape fixed and estimated" {
    var x: [101]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 101.25;
        v.* = 2 * (std.math.pow(f64, 1 - q, -0.3) - 1) / 0.3;
    }
    try check(.{ .theta = 0, .sigma = 2.043369, .alpha = -0.26684 }, fit(.pareto, &x, .{}, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 1.991393, .alpha = -0.3 }, fit(.pareto, &x, .{ .alpha = -0.3 }, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 2, .alpha = -0.27802 }, fit(.pareto, &x, .{ .sigma = 2 }, .{}), 5e-5);
    try check(.{ .theta = 0, .sigma = 2.764319, .alpha = 0 }, fit(.pareto, &x, .{ .alpha = 0 }, .{}), 5e-5);
}

test "endpoint heldout shifted scaled beta Pareto and power" {
    var b: [77]f64 = undefined;
    var g: [77]f64 = undefined;
    var p: [77]f64 = undefined;
    for (&b, &g, &p, 0..) |*bv, *gv, *pv, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 77.25;
        bv.* = -3 + 7 * f.distQuantile(.beta, q, &.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 3 }, .{ .num = 4 } }).?;
        gv.* = 5 + 3 * (1 - std.math.pow(f64, 1 - q, 0.2)) / 0.2;
        pv.* = std.math.pow(f64, q, 0.2);
    }
    try check(.{ .theta = -2.64712, .sigma = 5.940861, .alpha = 2.161829, .beta = 2.691863 }, fit(.beta, &b, .{ .theta = null }, .{}), 2e-4);
    try check(.{ .theta = -3, .sigma = 6.63445, .alpha = 2.945211, .beta = 3.560869 }, fit(.beta, &b, .{ .theta = -3 }, .{}), 2e-4);
    try check(.{ .theta = -2.92361, .sigma = 7, .alpha = 3, .beta = 4.19181 }, fit(.beta, &b, .{ .theta = null, .sigma = 7, .alpha = 3 }, .{}), 2e-4);
    try check(.{ .theta = 5, .sigma = 3.099691, .alpha = 0.242724 }, fit(.pareto, &g, .{ .theta = 5 }, .{}), 1e-4);
    try check(.{ .theta = 5, .sigma = 2.952003, .alpha = 0.2 }, fit(.pareto, &g, .{ .theta = 5, .alpha = 0.2 }, .{}), 1e-4);
    try check(.{ .theta = 5, .sigma = 3, .alpha = 0.22375 }, fit(.pareto, &g, .{ .theta = 5, .sigma = 3 }, .{}), 1e-4);
    try check(.{ .theta = 0, .sigma = 1, .alpha = 5.055881 }, fit(.power, &p, .{ .sigma = 1 }, .{}), 1e-6);
}

test "endpoint SAS degeneracy, uniform boundary and failed endpoint fits" {
    const x = &[_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const beta = fit(.beta, x, .{ .theta = null }, .{});
    try std.testing.expect(beta == .nonconverged);
    try std.testing.expect(beta.nonconverged.best == null);
    try std.testing.expect(fit(.beta, x, .{ .theta = null, .alpha = 1, .beta = 1 }, .{}) == .nonconverged);
    try std.testing.expect(fit(.beta, x, .{ .theta = 0, .alpha = 0.5, .beta = 0.5 }, .{}) == .nonconverged);
    try std.testing.expect(fit(.power, x, .{ .theta = null }, .{}) == .nonconverged);
    try check(.{ .theta = 0, .sigma = 15, .alpha = 1 }, fit(.pareto, x, .{ .alpha = 1 }, .{}), 1e-12);
    try check(.{ .theta = 0, .sigma = 10.99992, .alpha = 0.6815 }, fit(.pareto, x, .{}, .{}), 2e-4);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.beta, &.{ 1, 1, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.outside_support, fit(.beta, &.{ 0, 0.5, 1 }, .{ .sigma = 1 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.unsupported_combination, fit(.pareto, x, .{ .theta = null }, .{}).nonconverged.reason);
}

test "endpoint boundary power curves remain warned and Pareto absent roots remain loud" {
    var x: [41]f64 = undefined;
    for (&x, 0..) |*v, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 41.25;
        v.* = q * q;
    }
    const r = fit(.power, &x, .{}, .{});
    try std.testing.expectEqual(Reason.boundary_solution, r.nonconverged.reason);
    const p = r.nonconverged.best.?.parameters;
    try std.testing.expectEqual(x[40], p.sigma);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5176533456070203), p.alpha, 1e-12);
    // SAS finite-stopped curve: sigma=.971697, alpha=.517165. This exact
    // boundary optimum is within .002 scale and .0005 shape, never labelled
    // an interior optimum or exact SAS optimizer replication.
    try std.testing.expectApproxEqAbs(@as(f64, 0.971697), p.sigma, 0.002);
    try std.testing.expectApproxEqAbs(@as(f64, 0.517165), p.alpha, 0.0005);
    try std.testing.expect(std.math.isFinite(r.nonconverged.best.?.log_likelihood));
    for ([_]f64{ 1, 3, 4 }) |shift| {
        var y = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
        for (&y) |*v| v.* += shift;
        const absent = fit(.pareto, &y, .{}, .{});
        try std.testing.expectEqual(Reason.no_local_maximum, absent.nonconverged.reason);
        try std.testing.expect(absent.nonconverged.best == null);
    }
}

const ParetoProfile = struct {
    x: []const f64,
    theta: f64,
    maximum: f64,
    fn score(self: @This(), u: f64) f64 {
        const n: f64 = @floatFromInt(self.x.len);
        if (@abs(u) < 0.001) {
            // Divide Grimshaw's score by its spurious u^2 zero. The series
            // remains continuous through the exponential limit at u=0.
            var m = [_]f64{0} ** 9;
            m[0] = 1;
            for (self.x) |v| {
                const z = (v - self.theta) / self.maximum;
                var power = z;
                for (1..9) |k| {
                    m[k] += power / n;
                    power *= z;
                }
            }
            var sum: f64 = 0;
            var power: f64 = 1;
            for (2..9) |k| {
                var coefficient = m[k];
                for (1..k + 1) |j| coefficient -= m[j] * m[k - j] / @as(f64, @floatFromInt(j));
                sum += coefficient * power;
                power *= u;
            }
            return sum;
        }
        var logarithm: f64 = 0;
        var reciprocal: f64 = 0;
        for (self.x) |v| {
            const z = u * (v - self.theta) / self.maximum;
            logarithm += std.math.log1p(-z) / n;
            reciprocal += 1 / (1 - z) / n;
        }
        return ((1 + logarithm) * reciprocal - 1) / (u * u);
    }
    fn curve(self: @This(), u: f64) ?Curve {
        const n: f64 = @floatFromInt(self.x.len);
        var sigma: f64 = 0;
        for (self.x) |v| {
            const z = (v - self.theta) / self.maximum;
            sigma += self.maximum * (if (@abs(u * z) < 1e-5) z * (1 + u * z * (0.5 + u * z / 3)) else -std.math.log1p(-u * z) / u) / n;
        }
        const p: Parameters = .{ .theta = self.theta, .sigma = sigma, .alpha = u * sigma / self.maximum };
        if (p.alpha > 1) return null;
        const ll = logLikelihood(.pareto, self.x, p);
        return if (std.math.isFinite(ll)) .{ .parameters = p, .log_likelihood = ll } else null;
    }
};

fn paretoProfile(x: []const f64, theta: f64, controls: Controls) Result {
    const problem: ParetoProfile = .{ .x = x, .theta = theta, .maximum = x[x.len - 1] - theta };
    var previous = -@exp(@as(f64, 16));
    var fs = problem.score(previous);
    var best: ?Curve = null;
    var total: usize = 0;
    // Logarithmic coverage on both sides of the exponential limit, and
    // increasingly fine resolution toward the finite upper support endpoint.
    for (0..321) |i| {
        const fi: f64 = @floatFromInt(i);
        const next = if (i < 160) -@exp(16 - (fi + 1) * 0.2) else if (i == 160) @as(f64, 0) else -std.math.expm1(-@exp(-16 + (fi - 160) * 0.12));
        const fnx = problem.score(next);
        if (fs * fnx < 0 or fnx == 0) {
            var lo = previous;
            var hi = next;
            var fl = fs;
            var resolved = false;
            for (0..controls.maxiter) |_| {
                total += 1;
                const mid = lo / 2 + hi / 2;
                const fm = problem.score(mid);
                if (fm == 0 or hi - lo < controls.tolerance * (1 + @abs(mid))) {
                    lo = mid;
                    hi = mid;
                    resolved = true;
                    break;
                }
                if (fl * fm <= 0) hi = mid else {
                    lo = mid;
                    fl = fm;
                }
            }
            const u = lo / 2 + hi / 2;
            if (problem.curve(u)) |candidate| {
                if (!resolved) return .{ .nonconverged = .{ .reason = .iteration_limit, .best = .{ .parameters = candidate.parameters, .log_likelihood = candidate.log_likelihood, .iterations = total } } };
                const h = @min(1e-4 * (1 + @abs(u)), (1 - u) / 4);
                const left = problem.curve(u - h);
                const right = problem.curve(u + h);
                if (left != null and right != null and candidate.log_likelihood >= left.?.log_likelihood and candidate.log_likelihood >= right.?.log_likelihood and (best == null or candidate.log_likelihood > best.?.log_likelihood)) best = candidate;
            }
        }
        previous = next;
        fs = fnx;
    }
    if (best) |*curve| {
        curve.iterations = total;
        return .{ .converged = curve.* };
    }
    // No interior root is not permission to publish an arbitrary endpoint
    // spike. SAS likewise suppresses most no-MLE cases (retained shift probe).
    return fail(.no_local_maximum);
}

fn stationary(problem: Problem, q: [4]f64, axes: []const usize) bool {
    const base = problem.value(q);
    var hess: [4][4]f64 = std.mem.zeroes([4][4]f64);
    var steps: [4]f64 = undefined;
    for (axes, 0..) |axis, i| {
        const h = 1e-4 * (1 + @abs(q[axis]));
        steps[i] = h;
        var plus = q;
        var minus = q;
        plus[axis] += h;
        minus[axis] -= h;
        const vp = problem.value(plus);
        const vm = problem.value(minus);
        const gradient = (vp - vm) / (2 * h);
        if (!std.math.isFinite(gradient) or @abs(gradient) > 1e-4) return false;
        hess[i][i] = (vp - 2 * base + vm) / (h * h);
        for (0..i) |j| {
            const other = axes[j];
            plus[other] += steps[j];
            minus[other] += steps[j];
            const pp = problem.value(plus);
            const mp = problem.value(minus);
            plus[other] -= 2 * steps[j];
            minus[other] -= 2 * steps[j];
            hess[i][j] = (pp - mp - problem.value(plus) + problem.value(minus)) / (4 * h * steps[j]);
            hess[j][i] = hess[i][j];
        }
    }
    // Cholesky rejects saddles and numerically flat infinite-parameter limits.
    for (0..axes.len) |i| {
        for (0..i + 1) |j| {
            var v = hess[i][j];
            for (0..j) |k| v -= hess[i][k] * hess[j][k];
            if (i == j) {
                if (!(v > 1e-10) or !std.math.isFinite(v)) return false;
                hess[i][j] = @sqrt(v);
            } else hess[i][j] = v / hess[j][j];
        }
    }
    return true;
}

test "endpoint affine invariance and explicit unsupported method and budget status" {
    var x: [51]f64 = undefined;
    var y: [51]f64 = undefined;
    for (&x, &y, 0..) |*v, *w, i| {
        const q = (@as(f64, @floatFromInt(i + 1)) - 0.375) / 51.25;
        v.* = 2 * (std.math.pow(f64, 1 - q, -0.25) - 1) / 0.25;
        w.* = -20 + 7 * v.*;
    }
    const a = fit(.pareto, &x, .{}, .{}).converged;
    const b = fit(.pareto, &y, .{ .theta = -20 }, .{}).converged;
    try std.testing.expectApproxEqAbs(a.parameters.alpha, b.parameters.alpha, 1e-8);
    try std.testing.expectApproxEqAbs(7 * a.parameters.sigma, b.parameters.sigma, 1e-7);
    try std.testing.expectApproxEqAbs(a.log_likelihood - 51 * @log(@as(f64, 7)), b.log_likelihood, 1e-9);
    try std.testing.expectEqual(Reason.unsupported_method, fit(.pareto, &x, .{}, .{ .method = .epm }).nonconverged.reason);
    const limited = fit(.pareto, &x, .{}, .{ .maxiter = 1 });
    try std.testing.expectEqual(Reason.iteration_limit, limited.nonconverged.reason);
    try std.testing.expect(limited.nonconverged.best != null);
    try std.testing.expectEqual(@as(usize, 1), limited.nonconverged.best.?.iterations);
    try std.testing.expectEqual(Reason.invalid_controls, fit(.pareto, &x, .{}, .{ .maxiter = 0 }).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.beta, &.{ 2, 1 }, .{}, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_parameters, fit(.beta, &.{ 0.1, 0.2 }, .{ .sigma = -1 }, .{}).nonconverged.reason);
    try std.testing.expectEqual(Reason.invalid_sample, fit(.pareto, &.{ 1, std.math.nan(f64) }, .{}, .{}).nonconverged.reason);
}
