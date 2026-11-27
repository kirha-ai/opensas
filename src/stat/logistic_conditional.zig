//! Exact stratum-conditional likelihood for asymptotic logistic inference.
//! S154 physical pp.5946–5947. Intercepts are conditioned out, not estimated.
//! Log-domain elementary-symmetric DP carries conditional means/covariances
//! of selected covariate sums, including multicase strata and tied predictors.
const std = @import("std");
const diag = @import("../diag.zig");
const reg = @import("reg_fit.zig");
const A = std.mem.Allocator;
pub const Stratum = struct { rows: []const usize, events: usize };
pub const Evaluation = struct { log_likelihood: f64, gradient: []const f64, information: []const f64 };
pub const Status = enum { converged, iteration_limit, evaluation_limit };
pub const Options = struct { gconv: f64 = 1e-8, max_iterations: usize = 50, max_evaluations: usize = 125 };
pub const Fit = struct { coefficients: []const f64, covariance: []const f64, log_likelihood: f64, null_log_likelihood: f64, score_test: f64, iterations: usize, evaluations: usize, status: Status };
fn dot(x: []const f64, y: []const f64) f64 {
    var sum: f64 = 0;
    for (x, y) |a, b| sum += a * b;
    return sum;
}

pub fn evaluate(a: A, x: []const f64, y: []const f64, p: usize, strata: []const Stratum, beta: []const f64) diag.Error!Evaluation {
    if (p == 0 or p > 39 or beta.len != p or x.len != y.len * p) return error.ExecError;
    for (beta) |value| if (!std.math.isFinite(value)) return error.ExecError;
    const gradient = try a.alloc(f64, p);
    @memset(gradient, 0);
    const information = try a.alloc(f64, p * p);
    @memset(information, 0);
    var ll: f64 = 0;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    for (strata) |stratum| {
        const n = stratum.rows.len;
        const m = stratum.events;
        if (m > n or n == 0) return error.ExecError;
        var cases: usize = 0;
        for (stratum.rows) |row| {
            if (row >= y.len or (y[row] != 0 and y[row] != 1)) return error.ExecError;
            if (y[row] == 1) cases += 1;
        }
        if (cases != m) return error.ExecError;
        if (m == 0 or m == n) continue;
        // Bound real DP work before allocation; no enumeration or approximate
        // denominator is substituted for an oversized conditional problem.
        if (n > 4096 or p > 39 or n * m > 4_000_000 / (p * p)) return error.ExecError;
        _ = scratch.reset(.retain_capacity);
        const tmp = scratch.allocator();
        const logz = try tmp.alloc(f64, m + 1);
        @memset(logz, -std.math.inf(f64));
        logz[0] = 0;
        const mean = try tmp.alloc(f64, (m + 1) * p);
        @memset(mean, 0);
        const covariance = try tmp.alloc(f64, (m + 1) * p * p);
        @memset(covariance, 0);
        const centered = try tmp.alloc(f64, p);
        const added_mean = try tmp.alloc(f64, p);
        const origin = stratum.rows[0];
        if (origin >= y.len) return error.ExecError;
        var observed_events: usize = 0;
        for (stratum.rows, 0..) |row, ordinal| {
            if (row >= y.len or (y[row] != 0 and y[row] != 1)) return error.ExecError;
            for (0..p) |j| {
                centered[j] = x[row * p + j] - x[origin * p + j];
                if (!std.math.isFinite(centered[j])) return error.ExecError;
                if (y[row] == 1) gradient[j] += centered[j];
            }
            const eta = dot(centered, beta);
            if (!std.math.isFinite(eta)) return error.ExecError;
            if (y[row] == 1) {
                ll += eta;
                observed_events += 1;
            }
            var selected = @min(m, ordinal + 1);
            while (selected > 0) : (selected -= 1) {
                const old_log = logz[selected];
                const added_log = logz[selected - 1] + eta;
                if (std.math.isInf(added_log) and added_log < 0) continue;
                const mean_current = mean[selected * p ..][0..p];
                const mean_previous = mean[(selected - 1) * p ..][0..p];
                const cov_current = covariance[selected * p * p ..][0 .. p * p];
                const cov_previous = covariance[(selected - 1) * p * p ..][0 .. p * p];
                for (0..p) |j| added_mean[j] = mean_previous[j] + centered[j];
                if (std.math.isInf(old_log) and old_log < 0) {
                    logz[selected] = added_log;
                    @memcpy(mean_current, added_mean);
                    @memcpy(cov_current, cov_previous);
                    continue;
                }
                const maximum = @max(old_log, added_log);
                const combined = maximum + std.math.log1p(@exp(-@abs(old_log - added_log)));
                const left = @exp(old_log - combined);
                const right = @exp(added_log - combined);
                if (right == 0) continue;
                if (left == 0) {
                    logz[selected] = combined;
                    @memcpy(mean_current, added_mean);
                    @memcpy(cov_current, cov_previous);
                    continue;
                }
                for (0..p) |j| for (0..p) |k| {
                    const delta_j = mean_current[j] - added_mean[j];
                    const delta_k = mean_current[k] - added_mean[k];
                    cov_current[j * p + k] = left * cov_current[j * p + k] + right * cov_previous[j * p + k] + left * right * delta_j * delta_k;
                };
                for (0..p) |j| mean_current[j] = left * mean_current[j] + right * added_mean[j];
                logz[selected] = combined;
            }
        }
        if (observed_events != m or !std.math.isFinite(logz[m])) return error.ExecError;
        ll -= logz[m];
        for (0..p) |j| gradient[j] -= mean[m * p + j];
        for (0..p * p) |j| information[j] += covariance[m * p * p + j];
    }
    if (!std.math.isFinite(ll)) return error.ExecError;
    for (gradient) |value| if (!std.math.isFinite(value)) return error.ExecError;
    for (information) |value| if (!std.math.isFinite(value)) return error.ExecError;
    return .{ .log_likelihood = ll, .gradient = gradient, .information = information };
}
fn solve(a: A, matrix: []const f64, rhs: []const f64) diag.Error![]const f64 {
    var solution = try reg.fit(a, matrix, rhs, rhs.len, rhs.len, null);
    defer solution.deinit(a);
    if (solution.rank != rhs.len) return error.ExecError;
    return a.dupe(f64, solution.coefficients);
}
fn inverse(a: A, information: []const f64, p: usize) diag.Error![]const f64 {
    const result = try a.alloc(f64, p * p);
    const rhs = try a.alloc(f64, p);
    defer a.free(rhs);
    for (0..p) |j| {
        @memset(rhs, 0);
        rhs[j] = 1;
        const column = try solve(a, information, rhs);
        defer a.free(column);
        for (0..p) |i| result[i * p + j] = column[i];
    }
    return result;
}
pub fn fit(a: A, x: []const f64, y: []const f64, p: usize, strata: []const Stratum, options: Options) diag.Error!Fit {
    if (p == 0 or p > 39 or options.max_iterations == 0 or options.max_evaluations == 0 or !(options.gconv > 0) or !std.math.isFinite(options.gconv)) return error.ExecError;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    const beta = try tmp.alloc(f64, p);
    @memset(beta, 0);
    var null_ll: f64 = 0;
    var score: f64 = 0;
    var calls: usize = 0;
    var iteration = std.heap.ArenaAllocator.init(tmp);
    defer iteration.deinit();
    for (0..options.max_iterations + 1) |index| {
        _ = iteration.reset(.retain_capacity);
        const ia = iteration.allocator();
        const current = try evaluate(ia, x, y, p, strata, beta);
        calls += 1;
        const step = try solve(ia, current.information, current.gradient);
        const norm = dot(current.gradient, step);
        if (index == 0) {
            null_ll = current.log_likelihood;
            score = @max(0, norm);
        }
        // NLOPTIONS GCONV uses max(|f|,FSIZE), with default FSIZE=0;
        // it is not the unconditional MODEL denominator |f|+1e-6.
        const converged = norm >= 0 and norm / @abs(current.log_likelihood) <= options.gconv;
        if (converged or index == options.max_iterations or calls >= options.max_evaluations) return .{ .coefficients = try a.dupe(f64, beta), .covariance = try inverse(a, current.information, p), .log_likelihood = current.log_likelihood, .null_log_likelihood = null_ll, .score_test = score, .iterations = index, .evaluations = calls, .status = if (converged) .converged else if (calls >= options.max_evaluations) .evaluation_limit else .iteration_limit };
        var accepted = false;
        var ridge: f64 = 0;
        const candidate = try ia.alloc(f64, p);
        for (0..40) |_| {
            const adjustment = if (ridge == 0) step else blk: {
                const penalized = try ia.dupe(f64, current.information);
                for (0..p) |j| penalized[j * p + j] *= 1 + ridge;
                break :blk try solve(ia, penalized, current.gradient);
            };
            for (0..p) |j| candidate[j] = beta[j] + adjustment[j];
            const next = try evaluate(ia, x, y, p, strata, candidate);
            calls += 1;
            if (next.log_likelihood >= current.log_likelihood) {
                accepted = true;
                break;
            }
            ridge = if (ridge == 0) 0.0001 else ridge * 2;
        }
        if (!accepted) return error.ExecError;
        @memcpy(beta, candidate);
    }
    return error.ExecError;
}
