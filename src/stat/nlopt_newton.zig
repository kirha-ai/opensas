//! NRRIDG minimization and TECH=NONE evaluation, S154 physical pp.524–536.
//! Newton steps use the objective's actual gradient and symmetric Hessian.
//! Ridging is spectral (orthogonal Jacobi decomposition), not a line-search
//! optimizer relabeled NRRIDG. Box constraints use a projected active set.
//! General linear/nonlinear constraints and other techniques are unavailable.
const std = @import("std");
const diag = @import("../diag.zig");
const opt = @import("nloptions.zig");
const A = std.mem.Allocator;
pub const Objective = struct {
    context: ?*anyopaque = null,
    /// Return NaN/infinity for an undefined objective. Null derivative buffers
    /// request function evaluation only. Never evaluate outside supplied bounds.
    evaluate: *const fn (?*anyopaque, []const f64, ?[]f64, ?[]f64) f64,
    least_squares: bool = false,
};
pub const Bounds = struct { lower: []const f64 = &.{}, upper: []const f64 = &.{} };
pub const Status = enum { converged, evaluation_only, iteration_limit, evaluation_limit, infeasible, numerical_failure };
pub const Iteration = struct { parameters: []const f64, value: f64, gradient_max: f64, ridge: f64 };
pub const Result = struct {
    status: Status,
    criterion: ?opt.Reason = null,
    parameters: []const f64,
    value: ?f64 = null,
    gradient: ?[]const f64 = null,
    hessian: ?[]const f64 = null,
    iterations: usize = 0,
    evaluations: usize = 0,
    derivative_evaluations: usize = 0,
    ridge_trials: usize = 0,
    history: []const Iteration = &.{},
};
pub const Metrics = struct {
    value: f64,
    gradient_max: f64,
    absolute_function: ?f64 = null,
    absolute_parameter: ?f64 = null,
    relative_function: ?f64 = null,
    relative_parameter: ?f64 = null,
    predicted_reduction: ?f64 = null,
    relative_gradient: ?f64 = null,
    least_squares_gradient: ?f64 = null,
};
fn ratio(numerator: f64, denominator: f64) f64 {
    return if (denominator > 0) numerator / denominator else if (numerator == 0) 0 else std.math.inf(f64);
}
pub fn metrics(o: opt.Options, f: f64, x: []const f64, projected_gradient: []const f64, old_f: ?f64, old_x: ?[]const f64, newton_reduction: ?f64, least_squares_gradient: ?f64) Metrics {
    var m = Metrics{ .value = f, .gradient_max = 0, .least_squares_gradient = least_squares_gradient };
    for (projected_gradient) |v| m.gradient_max = @max(m.gradient_max, @abs(v));
    if (old_f) |previous| {
        m.absolute_function = @abs(f - previous);
        m.relative_function = ratio(m.absolute_function.?, @max(@abs(previous), o.fsize));
    }
    if (old_x) |previous| {
        var squared: f64 = 0;
        var relative: f64 = 0;
        for (x, previous) |v, w| {
            squared += (v - w) * (v - w);
            relative = @max(relative, ratio(@abs(v - w), @max(o.xsize, @max(@abs(v), @abs(w)))));
        }
        m.absolute_parameter = @sqrt(squared);
        m.relative_parameter = relative;
    }
    if (newton_reduction) |reduction| {
        m.predicted_reduction = reduction * 0.5;
        m.relative_gradient = ratio(reduction, @max(@abs(f), o.fsize));
    }
    return m;
}
pub const Stopping = struct {
    runs: [9]usize = @splat(0),
    pub fn check(s: *Stopping, o: opt.Options, m: Metrics, iteration: usize) ?opt.Reason {
        const criteria = [_]opt.Criterion{ .{ .threshold = o.absconv }, o.absfconv, o.absgconv, o.absoluteX(), o.fconv, o.secondFunction(), o.gconv, o.gconv2, o.relativeX() };
        const values = [_]?f64{ m.value, m.absolute_function, m.gradient_max, m.absolute_parameter, m.relative_function, m.predicted_reduction, m.relative_gradient, m.least_squares_gradient, m.relative_parameter };
        var selected: ?opt.Reason = null;
        for (criteria, values, 0..) |c, value, i| {
            if (value != null and std.math.isFinite(value.?) and value.? <= c.threshold) {
                s.runs[i] +|= 1;
                if (s.runs[i] >= c.consecutive and selected == null) selected = @enumFromInt(i);
            } else s.runs[i] = 0;
        }
        return if (iteration >= o.min_iterations) selected else null;
    }
};
fn finite(values: []const f64) bool {
    for (values) |v| if (!std.math.isFinite(v)) return false;
    return true;
}
fn lower(b: Bounds, i: usize) f64 {
    return if (b.lower.len == 0) -std.math.inf(f64) else b.lower[i];
}
fn upper(b: Bounds, i: usize) f64 {
    return if (b.upper.len == 0) std.math.inf(f64) else b.upper[i];
}
fn symmetric(h: []const f64, n: usize) bool {
    if (!finite(h)) return false;
    for (0..n) |i| for (0..i) |j| {
        if (@abs(h[i * n + j] - h[j * n + i]) > 64 * std.math.floatEps(f64) * @max(1, @max(@abs(h[i * n + j]), @abs(h[j * n + i])))) return false;
    };
    return true;
}
const Spectrum = struct { values: []f64, vectors: []f64 };
/// Signed eigenvalues are retained: indefinite objective Hessians must be
/// repaired, never converted into an unrelated positive semidefinite matrix.
fn spectrum(a: A, h: []const f64, n: usize) diag.Error!?Spectrum {
    const matrix = try a.dupe(f64, h);
    const vectors = try a.alloc(f64, n * n);
    @memset(vectors, 0);
    var scale: f64 = 0;
    for (h) |v| scale = @max(scale, @abs(v));
    for (0..n) |i| vectors[i * n + i] = 1;
    for (0..100 * n * n) |_| {
        var r: usize = 0;
        var c: usize = 0;
        var largest: f64 = 0;
        for (0..n) |i| for (i + 1..n) |j| {
            if (@abs(matrix[i * n + j]) > largest) {
                largest = @abs(matrix[i * n + j]);
                r = i;
                c = j;
            }
        };
        if (largest <= @max(std.math.floatMin(f64), scale) * (8 * std.math.floatEps(f64))) {
            const values = try a.alloc(f64, n);
            for (values, 0..) |*v, i| v.* = matrix[i * n + i];
            return .{ .values = values, .vectors = vectors };
        }
        const off = matrix[r * n + c];
        const tau = (matrix[c * n + c] - matrix[r * n + r]) / (2 * off);
        const tangent = (if (tau >= 0) @as(f64, 1) else -1) / (@abs(tau) + std.math.hypot(tau, 1));
        const cosine = 1 / @sqrt(1 + tangent * tangent);
        const sine = tangent * cosine;
        for (0..n) |i| {
            const left = vectors[i * n + r];
            const right = vectors[i * n + c];
            vectors[i * n + r] = cosine * left - sine * right;
            vectors[i * n + c] = sine * left + cosine * right;
        }
        matrix[r * n + r] -= tangent * off;
        matrix[c * n + c] += tangent * off;
        matrix[r * n + c] = 0;
        matrix[c * n + r] = 0;
        for (0..n) |j| {
            if (j == r or j == c) continue;
            const jr = matrix[j * n + r];
            const jc = matrix[j * n + c];
            matrix[j * n + r] = cosine * jr - sine * jc;
            matrix[r * n + j] = matrix[j * n + r];
            matrix[j * n + c] = sine * jr + cosine * jc;
            matrix[c * n + j] = matrix[j * n + c];
        }
    }
    return null;
}
fn step(e: Spectrum, g: []const f64, ridge: f64, out: []f64) void {
    @memset(out, 0);
    const n = g.len;
    for (0..n) |j| {
        var projection: f64 = 0;
        for (g, 0..) |v, i| projection += e.vectors[i * n + j] * v;
        const multiplier = -projection / (e.values[j] + ridge);
        for (out, 0..) |*v, i| v.* += e.vectors[i * n + j] * multiplier;
    }
}
fn dot(x: []const f64, y: []const f64) f64 {
    var out: f64 = 0;
    for (x, y) |v, w| out += v * w;
    return out;
}

/// Returned buffers/history are arena-owned. A convergence criterion alone
/// does not establish a procedure-specific covariance or inferential solution.
pub fn minimize(a: A, objective: Objective, initial: []const f64, bounds: Bounds, o: opt.Options) diag.Error!Result {
    const n = initial.len;
    if (!o.valid() or !opt.implemented(o.technique) or n == 0 or n > 64 or (bounds.lower.len != 0 and bounds.lower.len != n) or (bounds.upper.len != 0 and bounds.upper.len != n)) return error.ExecError;
    const x = try a.dupe(f64, initial);
    var result = Result{ .status = .numerical_failure, .parameters = x };
    if (!finite(x)) return result;
    for (x, 0..) |v, i| {
        const lo = lower(bounds, i);
        const hi = upper(bounds, i);
        if (std.math.isNan(lo) or std.math.isNan(hi) or lo > hi or v < lo or v > hi) {
            result.status = .infeasible;
            return result;
        }
    }
    const gradient = try a.alloc(f64, n);
    const hessian = try a.alloc(f64, n * n);
    @memset(gradient, std.math.nan(f64));
    @memset(hessian, std.math.nan(f64));
    var f = objective.evaluate(objective.context, x, gradient, hessian);
    result.evaluations = 1;
    result.derivative_evaluations = 1;
    if (!std.math.isFinite(f) or !finite(gradient) or !symmetric(hessian, n)) return result;
    result.value = f;
    result.gradient = gradient;
    result.hessian = hessian;
    if (o.technique == .none) {
        result.status = .evaluation_only;
        return result;
    }
    var history: std.ArrayList(Iteration) = .empty;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var stopping = Stopping{};
    var previous_x: ?[]const f64 = null;
    var previous_f: ?f64 = null;
    var previous_ridge: f64 = 0;
    while (true) {
        _ = scratch.reset(.retain_capacity);
        const tmp = scratch.allocator();
        const projected = try tmp.dupe(f64, gradient);
        const reduced = try tmp.dupe(f64, hessian);
        for (0..n) |i| {
            const lo = lower(bounds, i);
            const hi = upper(bounds, i);
            const at_lower = std.math.isFinite(lo) and x[i] - lo <= o.lcepsilon * (1 + @abs(lo));
            const at_upper = std.math.isFinite(hi) and hi - x[i] <= o.lcepsilon * (1 + @abs(hi));
            if (lo == hi or (at_lower and gradient[i] >= 0) or (at_upper and gradient[i] <= 0)) {
                projected[i] = 0;
                for (0..n) |j| {
                    reduced[i * n + j] = 0;
                    reduced[j * n + i] = 0;
                }
                reduced[i * n + i] = 1;
            }
        }
        const eig = (try spectrum(tmp, reduced, n)) orelse break;
        var minimum = std.math.inf(f64);
        var scale: f64 = 0;
        for (eig.values) |v| {
            minimum = @min(minimum, v);
            scale = @max(scale, @abs(v));
        }
        if (!finite(eig.values) or !finite(eig.vectors)) break;
        const pd = minimum > scale * o.singular;
        const direction = try tmp.alloc(f64, n);
        var reduction: ?f64 = null;
        if (pd) {
            step(eig, projected, 0, direction);
            reduction = @max(0, -dot(projected, direction));
        }
        var ls_metric: ?f64 = null;
        if (objective.least_squares and f > 0) {
            var largest: f64 = 0;
            var valid = true;
            for (projected, 0..) |v, i| {
                const denominator = f * reduced[i * n + i];
                if (!(denominator > 0)) {
                    valid = false;
                    break;
                }
                largest = @max(largest, @abs(v) / @sqrt(denominator));
            }
            if (valid) ls_metric = largest;
        }
        const m = metrics(o, f, x, projected, previous_f, previous_x, reduction, ls_metric);
        try history.append(a, .{ .parameters = try a.dupe(f64, x), .value = f, .gradient_max = m.gradient_max, .ridge = previous_ridge });
        result.history = history.items;
        if (stopping.check(o, m, result.iterations)) |criterion| {
            result.status = .converged;
            result.criterion = criterion;
            return result;
        }
        if (result.iterations >= o.maxIterations()) {
            result.status = .iteration_limit;
            return result;
        }
        // MAXFUNC is checked only after an entire iteration. Function and
        // derivative calls made inside the iteration may exceed the limit.
        if (result.evaluations >= o.maxEvaluations()) {
            result.status = .evaluation_limit;
            return result;
        }
        var ridge: f64 = if (pd) 0 else @max(1e-8, -minimum + @max(1, scale) * 1e-6);
        const candidate = try tmp.alloc(f64, n);
        const next_g = try tmp.alloc(f64, n);
        const next_h = try tmp.alloc(f64, n * n);
        var accepted = false;
        for (0..80) |_| {
            step(eig, projected, ridge, direction);
            for (x, direction, 0..) |v, delta, i| candidate[i] = @max(lower(bounds, i), @min(upper(bounds, i), v + delta));
            if (ridge > 0) result.ridge_trials += 1;
            if (finite(candidate)) {
                const trial_f = objective.evaluate(objective.context, candidate, null, null);
                result.evaluations += 1;
                if (std.math.isFinite(trial_f) and (trial_f < f or (trial_f == f and m.gradient_max == 0))) {
                    @memset(next_g, std.math.nan(f64));
                    @memset(next_h, std.math.nan(f64));
                    const next_f = objective.evaluate(objective.context, candidate, next_g, next_h);
                    result.evaluations += 1;
                    result.derivative_evaluations += 1;
                    if (!std.math.isFinite(next_f) or !finite(next_g) or !symmetric(next_h, n) or !(next_f < f or (next_f == f and m.gradient_max == 0))) break;
                    previous_x = history.items[history.items.len - 1].parameters;
                    previous_f = f;
                    previous_ridge = ridge;
                    @memcpy(x, candidate);
                    @memcpy(gradient, next_g);
                    @memcpy(hessian, next_h);
                    f = next_f;
                    result.value = f;
                    result.iterations += 1;
                    accepted = true;
                    break;
                }
            }
            ridge = if (ridge == 0) @max(1e-8, scale * 1e-6) else ridge * 4;
            if (!std.math.isFinite(ridge)) break;
        }
        if (!accepted) break;
    }
    // Retain the last valid objective/derivatives; an invalid candidate never
    // overwrites them or becomes a fabricated convergence result.
    result.status = .numerical_failure;
    return result;
}
