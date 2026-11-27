//! Profile REML/ML variance-component fits for MIXED. SAS/STAT15.4 physical
//! pp.6701-6702: V=sum(theta_k Z_k Z_k')+sigma²R0; profile sigma², retain
//! log|X'V^-1X| in REML, initialize by MIVQUE0 and use safeguarded Newton.
//! The ordered independent columns of the original full GLM-coded X define
//! the likelihood normalization. Alternative effect coding must not replace it.
const std = @import("std");
const A = std.mem.Allocator;
const matrix = @import("mixed_fit_matrix.zig");
const ranker = @import("reg_diagnostics.zig");
const reg = @import("reg_fit.zig");
pub const Component = struct { name: []const u8, kernel: []const f64, columns: usize = 0 };
pub const Model = struct { x: []const f64, y: []const f64, n: usize, p: usize, weights: ?[]const f64 = null, components: []const Component = &.{}, has_intercept: bool = true, singular: f64 = 1e-10 };
pub const Method = enum { reml, ml };
pub const Convergence = enum { hessian, gradient, function };
pub const Options = struct { method: Method = .reml, maxiter: usize = 50, maxfunc: usize = 150, convergence: f64 = 1e-8, bic_n: ?f64 = null, start: ?[]const f64 = null, ols_start: bool = false, criterion: Convergence = .hessian, absolute: bool = false };
pub const Status = enum { converged, evaluated, max_iterations, max_evaluations, line_search_failed };
pub fn statusReason(status: Status) []const u8 {
    return switch (status) {
        .converged => "Convergence criteria met.",
        .evaluated => "Covariance parameters evaluated without iteration.",
        .max_iterations => "Maximum number of iterations reached.",
        .max_evaluations => "Maximum number of likelihood evaluations reached.",
        .line_search_failed => "No improving feasible likelihood step was found.",
    };
}
pub const Iteration = struct { iteration: usize, evaluations: usize, objective: f64, criterion: ?f64, parameters: []f64 };
pub const Fit = struct {
    n: usize,
    p: usize,
    rank: usize,
    independent: []usize,
    coefficients: []f64,
    covariance: []f64,
    alias_coefficients: []f64,
    variances: []f64,
    residual_variance: f64,
    minus2loglik: f64,
    aic: f64,
    aicc: ?f64,
    bic: ?f64,
    iterations: []Iteration,
    converged: bool,
    status: Status,
    method: Method,
    df_error: usize,
    pd_h: ?bool = null,
    evaluation_count: usize = 0,
    rejected_evaluations: usize = 0,
    last_iteration: usize = 0,
};
const Evaluation = struct { objective: f64, q: f64, sigma: f64, beta: []f64, cov_unit: []f64, pmat: []f64, py: []f64, hinv: []f64 };
fn num(i: usize) f64 {
    return @floatFromInt(i);
}
fn evaluate(a: A, x: []const f64, y: []const f64, n: usize, p: usize, components: []const Component, ratios: []const f64, weights: ?[]const f64, method: Method) !Evaluation {
    const h = try a.alloc(f64, n * n);
    @memset(h, 0);
    for (0..n) |i| h[i * n + i] = if (weights) |w| 1 / w[i] else 1;
    for (components, ratios) |component, ratio| for (h, component.kernel) |*v, k| {
        v.* += ratio * k;
    };
    const hi = try matrix.inverse(a, h, n);
    const b = try a.alloc(f64, n * p);
    @memset(b, 0);
    for (0..n) |i| for (0..n) |j| for (0..p) |k| {
        b[i * p + k] += hi.values[i * n + j] * x[j * p + k];
    };
    const gram = try a.alloc(f64, p * p);
    @memset(gram, 0);
    for (0..p) |i| for (0..p) |j| for (0..n) |k| {
        gram[i * p + j] += x[k * p + i] * b[k * p + j];
    };
    const gi = try matrix.inverse(a, gram, p);
    const rhs = try a.alloc(f64, p);
    @memset(rhs, 0);
    for (0..p) |i| for (0..n) |j| {
        rhs[i] += b[j * p + i] * y[j];
    };
    const beta = try matrix.vector(a, gi.values, rhs, p);
    const residual = try a.dupe(f64, y);
    for (0..n) |i| for (0..p) |j| {
        residual[i] -= x[i * p + j] * beta[j];
    };
    const py = try matrix.vector(a, hi.values, residual, n);
    const q = matrix.dot(residual, py);
    if (!(q > 0) or !std.math.isFinite(q)) return error.DegenerateResponse;
    const df = num(if (method == .reml) n - p else n);
    const sigma = q / df;
    const proj = try a.dupe(f64, hi.values);
    const bc = try a.alloc(f64, n * p);
    @memset(bc, 0);
    for (0..n) |i| for (0..p) |j| for (0..p) |k| {
        bc[i * p + j] += b[i * p + k] * gi.values[k * p + j];
    };
    for (0..n) |i| for (0..n) |j| for (0..p) |k| {
        proj[i * n + j] -= bc[i * p + k] * b[j * p + k];
    };
    return .{ .objective = df * (1 + @log(2 * std.math.pi) + @log(sigma)) + hi.logdet + (if (method == .reml) gi.logdet else @as(f64, 0)), .q = q, .sigma = sigma, .beta = beta, .cov_unit = gi.values, .pmat = proj, .py = py, .hinv = hi.values };
}
const Derivatives = struct { gradient: []f64, hessian: []f64 };
fn derivatives(a: A, e: Evaluation, components: []const Component, n: usize, df: f64, method: Method) !Derivatives {
    const m = components.len;
    const gradient = try a.alloc(f64, m);
    const hessian = try a.alloc(f64, m * m);
    const products = try a.alloc([]f64, m);
    const vectors = try a.alloc([]f64, m);
    const quadratic = try a.alloc(f64, m);
    const normalized = try a.alloc(f64, e.py.len);
    const root_q = @sqrt(e.q);
    for (e.py, normalized) |v, *dest| dest.* = v / root_q;
    for (components, 0..) |component, i| {
        products[i] = try matrix.multiply(a, if (method == .reml) e.pmat else e.hinv, component.kernel, n);
        vectors[i] = try matrix.vector(a, component.kernel, normalized, n);
        quadratic[i] = matrix.dot(normalized, vectors[i]);
        var trace: f64 = 0;
        for (0..n) |j| trace += products[i][j * n + j];
        gradient[i] = trace - df * quadratic[i];
    }
    for (0..m) |i| for (0..m) |j| {
        const v = try matrix.vector(a, e.pmat, vectors[j], n);
        hessian[i * m + j] = -matrix.traceProduct(products[i], products[j], n) + df * (2 * matrix.dot(vectors[i], v) - quadratic[i] * quadratic[j]);
    };
    return .{ .gradient = gradient, .hessian = hessian };
}
const Initial = struct { ratios: []f64, sigma: f64, null_objective: f64, null_sigma: f64 };
fn initial(a: A, model: Model, x: []const f64, p: usize, method: Method, supplied: ?[]const f64, ols: bool) !Initial {
    const m = model.components.len;
    const ratios = try a.alloc(f64, m);
    @memset(ratios, 0);
    if (m == 0) return .{ .ratios = ratios, .sigma = std.math.nan(f64), .null_objective = std.math.nan(f64), .null_sigma = std.math.nan(f64) };
    const e = try evaluate(a, x, model.y, model.n, p, model.components, ratios, model.weights, method);
    if (supplied) |values| {
        for (ratios, 0..) |*r, i| r.* = values[i] / values[m];
        return .{ .ratios = ratios, .sigma = values[m], .null_objective = e.objective, .null_sigma = e.sigma };
    }
    if (ols) return .{ .ratios = ratios, .sigma = e.sigma, .null_objective = e.objective, .null_sigma = e.sigma };
    const ks = try a.alloc([]const f64, m + 1);
    for (model.components, 0..) |c, i| ks[i] = c.kernel;
    const residual = try a.alloc(f64, model.n * model.n);
    @memset(residual, 0);
    for (0..model.n) |i| residual[i * model.n + i] = if (model.weights) |w| 1 / w[i] else 1;
    ks[m] = residual;
    const products = try a.alloc([]f64, m + 1);
    const rhs = try a.alloc(f64, m + 1);
    const info = try a.alloc(f64, (m + 1) * (m + 1));
    for (ks, 0..) |k, i| {
        products[i] = try matrix.multiply(a, e.pmat, k, model.n);
        rhs[i] = matrix.dot(e.py, try matrix.vector(a, k, e.py, model.n));
    }
    for (0..m + 1) |i| for (0..m + 1) |j| {
        info[i * (m + 1) + j] = matrix.traceProduct(products[i], products[j], model.n);
    };
    const inv = try matrix.inverse(a, info, m + 1);
    const theta = try matrix.vector(a, inv.values, rhs, m + 1);
    if (!(theta[m] > 0)) return error.InvalidInitialVariance;
    for (ratios, 0..) |*r, i| r.* = @max(0, theta[i]) / theta[m];
    return .{ .ratios = ratios, .sigma = theta[m], .null_objective = e.objective, .null_sigma = e.sigma };
}
fn parameters(a: A, ratios: []const f64, sigma: f64) ![]f64 {
    const result = try a.alloc(f64, ratios.len + 1);
    for (ratios, 0..) |r, i| result[i] = r * sigma;
    result[ratios.len] = sigma;
    return result;
}
pub fn fit(a: A, model: Model, options: Options) !Fit {
    if (model.n == 0 or model.p == 0 or model.n > 512 or model.p > 1024 or model.components.len > 8 or model.x.len != model.n * model.p or model.y.len != model.n) return error.InvalidInput;
    if (options.convergence <= 0 or !std.math.isFinite(options.convergence)) return error.InvalidInput;
    if (model.weights) |w| {
        if (w.len != model.n) return error.InvalidInput;
        for (w) |v| if (!(v > 0) or !std.math.isFinite(v)) return error.InvalidInput;
    }
    for (model.components) |c| {
        if (c.kernel.len != model.n * model.n) return error.InvalidInput;
        for (0..model.n) |i| for (0..model.n) |j| {
            if (!std.math.isFinite(c.kernel[i * model.n + j]) or @abs(c.kernel[i * model.n + j] - c.kernel[j * model.n + i]) > 1e-12) return error.InvalidInput;
        };
    }
    if (options.start) |values| {
        if (values.len != model.components.len + 1 or options.ols_start) return error.InvalidInput;
        for (values) |v| if (!std.math.isFinite(v) or v < 0) return error.InvalidInput;
        if (!(values[values.len - 1] > 0)) return error.InvalidInput;
    }
    if (model.has_intercept) {
        const constant = for (model.y) |v| {
            if (v != model.y[0]) break false;
        } else true;
        if (constant) return error.DegenerateResponse;
    }
    var ranked = try ranker.fit(a, model.x, model.y, model.n, model.p, model.weights, model.has_intercept, model.singular);
    defer ranked.deinit(a);
    const p = ranked.fit.rank;
    if (p >= model.n or p == 0) return error.InvalidInput;
    const independent = try a.alloc(usize, p);
    var at: usize = 0;
    for (ranked.fit.aliased, 0..) |alias, j| if (!alias) {
        independent[at] = j;
        at += 1;
    };
    const x = try a.alloc(f64, model.n * p);
    for (0..model.n) |i| for (independent, 0..) |j, k| {
        x[i * p + k] = model.x[i * model.p + j];
    };
    var init_arena = std.heap.ArenaAllocator.init(a);
    defer init_arena.deinit();
    const starting = try initial(init_arena.allocator(), model, x, p, options.method, options.start, options.ols_start);
    const ratios = try a.dupe(f64, starting.ratios);
    const m = ratios.len;
    if (m > 0 and options.maxfunc < 2) return error.EvaluationLimit;
    var history: std.ArrayList(Iteration) = .empty;
    var status: Status = if (m == 0) .converged else .max_iterations;
    const explicit_start = options.start != null or options.ols_start;
    var evaluations: usize = if (m == 0 or explicit_start) 1 else 2;
    var state_arena = std.heap.ArenaAllocator.init(a);
    defer state_arena.deinit();
    var current = try evaluate(state_arena.allocator(), x, model.y, model.n, p, model.components, ratios, model.weights, options.method);
    const df = num(if (options.method == .reml) model.n - p else model.n);
    var pd_h: ?bool = null;
    var rejected: usize = 0;
    var previous_objective: ?f64 = null;
    const previous_bound = try a.alloc(bool, m);
    @memset(previous_bound, false);
    var i: usize = 0;
    while (i <= options.maxiter) : (i += 1) {
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        const tmp = scratch.allocator();
        const e = current;
        if (m == 0) {
            try history.append(a, .{ .iteration = 0, .evaluations = 1, .objective = e.objective, .criterion = null, .parameters = try parameters(a, ratios, e.sigma) });
            break;
        }
        const d = try derivatives(tmp, e, model.components, model.n, df, options.method);
        pd_h = if (matrix.inverse(tmp, d.hessian, m)) |_| true else |err| switch (err) {
            error.NotPositiveDefinite => false,
            else => return err,
        };
        var released = false;
        for (ratios, previous_bound) |ratio, on_bound| if (on_bound and ratio > 0) {
            released = true;
        };
        // Active lower bounds satisfy the one-sided KKT condition; freeze only
        // coordinates whose gradient points out of the nonnegative domain.
        for (0..m) |j| if (ratios[j] == 0 and d.gradient[j] >= 0) {
            for (0..m) |k| {
                d.hessian[j * m + k] = 0;
                d.hessian[k * m + j] = 0;
            }
            d.hessian[j * m + j] = 1;
            d.gradient[j] = 0;
        };
        const unregularized = matrix.inverse(tmp, d.hessian, m) catch |err| switch (err) {
            error.NotPositiveDefinite => null,
            else => return err,
        };
        var scale: f64 = 1;
        for (0..m) |j| scale = @max(scale, @abs(d.hessian[j * m + j]));
        var inverse: ?matrix.Inverse = null;
        var ridge: f64 = 0;
        for (0..16) |attempt| {
            const h = try tmp.dupe(f64, d.hessian);
            for (0..m) |j| h[j * m + j] += ridge;
            inverse = matrix.inverse(tmp, h, m) catch |err| switch (err) {
                error.NotPositiveDefinite => null,
                else => return err,
            };
            if (inverse != null) break;
            ridge = scale * std.math.pow(f64, 10, @as(f64, @floatFromInt(attempt)) - 8);
        }
        if (inverse == null) return error.IndefiniteHessian;
        const step = try matrix.vector(tmp, inverse.?.values, d.gradient, m);
        for (step) |*v| v.* = -v.*;
        // The optimization objective omits the Gaussian additive constant.
        // Reporting -2 log likelihood includes it; CONVH uses the optimized
        // objective (physical p.6629), so its denominator excludes that constant.
        const objective = e.objective - df * @log(2 * std.math.pi);
        const numerator: ?f64 = switch (options.criterion) {
            .hessian => if (unregularized) |u| @max(0, matrix.dot(d.gradient, try matrix.vector(tmp, u.values, d.gradient, m))) else matrix.dot(d.gradient, d.gradient),
            .gradient => blk: {
                var largest: f64 = 0;
                for (d.gradient) |g| largest = @max(largest, @abs(g));
                break :blk largest;
            },
            .function => if (previous_objective) |last| @abs(objective - last) else null,
        };
        const criterion: ?f64 = if (numerator) |v| v / (if (options.absolute) @as(f64, 1) else @max(1e-100, @abs(objective))) else null;
        // Iteration zero is the independently evaluated homogeneous residual
        // baseline (the same fixed X), not the MIVQUE0 starting point. This
        // convention reproduces physical p.6622 Figure84.11 from its data.
        // First iteration evaluates the MIVQUE0 residual profile and its Newton
        // candidate. Accepted factorizations are cached for later derivatives.
        const reported_parameters = try parameters(a, ratios, e.sigma);
        if (i == 0) {
            @memset(reported_parameters[0..m], 0);
            reported_parameters[m] = starting.null_sigma;
        }
        if (i > 0 or !explicit_start) try history.append(a, .{ .iteration = i, .evaluations = if (i == 0) 1 else evaluations, .objective = if (i == 0) starting.null_objective else e.objective, .criterion = if (i == 0 or released) null else criterion, .parameters = reported_parameters });
        if (criterion != null and criterion.? <= options.convergence) {
            if (i == 0 and (explicit_start or @abs(starting.null_objective - e.objective) > 1e-12)) try history.append(a, .{ .iteration = 1, .evaluations = evaluations, .objective = e.objective, .criterion = criterion, .parameters = try parameters(a, ratios, e.sigma) });
            status = .converged;
            break;
        }
        if (i == options.maxiter) break;
        var length: f64 = 1;
        for (ratios, step) |r, s| {
            if (s < 0) length = @min(length, if (r > 0) -r / s else @as(f64, 0));
        }
        if (length <= 0) {
            status = .line_search_failed;
            break;
        }
        for (ratios, previous_bound) |ratio, *bound| bound.* = ratio == 0;
        const trial = try tmp.alloc(f64, m);
        var accepted = false;
        for (0..30) |_| {
            if (evaluations >= options.maxfunc) {
                status = .max_evaluations;
                break;
            }
            for (ratios, step, trial) |r, s, *v| {
                // A step mathematically landing on the lower bound is exactly
                // zero, not a positive cancellation residual counted as a free
                // variance component in information criteria.
                v.* = if (s < 0 and length >= -r / s) 0 else @max(0, r + length * s);
            }
            var trial_arena = std.heap.ArenaAllocator.init(a);
            var transferred = false;
            defer if (!transferred) trial_arena.deinit();
            evaluations += 1;
            const candidate = evaluate(trial_arena.allocator(), x, model.y, model.n, p, model.components, trial, model.weights, options.method) catch |err| switch (err) {
                error.NotPositiveDefinite, error.DegenerateResponse => {
                    rejected += 1;
                    length *= 0.5;
                    continue;
                },
                else => return err,
            };
            const reaches_bound = for (ratios, trial) |old, next| {
                if (old > 0 and next == 0) break true;
            } else false;
            var equal_objective_progress = false;
            if (candidate.objective == e.objective) {
                const moved = for (ratios, trial) |old, next| {
                    if (old != next) break true;
                } else false;
                if (moved) {
                    const next_d = try derivatives(trial_arena.allocator(), candidate, model.components, model.n, df, options.method);
                    var old_norm: f64 = 0;
                    var next_norm: f64 = 0;
                    for (d.gradient, next_d.gradient, trial) |old, g, r| {
                        old_norm = @max(old_norm, @abs(old));
                        const projected = if (r == 0 and g >= 0) @as(f64, 0) else g;
                        next_norm = @max(next_norm, @abs(projected));
                    }
                    equal_objective_progress = next_norm < old_norm;
                }
            }
            // Near the optimum, objective changes can be below one ULP while
            // the gradient still improves. Accept equality only with measured
            // stationarity progress (or an actual step onto a lower bound).
            if (candidate.objective < e.objective or (candidate.objective == e.objective and (reaches_bound or equal_objective_progress))) {
                previous_objective = objective;
                @memcpy(ratios, trial);
                state_arena.deinit();
                state_arena = trial_arena;
                transferred = true;
                current = candidate;
                accepted = true;
                break;
            }
            length *= 0.5;
        }
        if (!accepted) {
            if (status != .max_evaluations) status = .line_search_failed;
            break;
        }
    }
    var previous: usize = 0;
    for (history.items) |*row| {
        const cumulative = row.evaluations;
        row.evaluations = cumulative - previous;
        previous = cumulative;
    }
    const final = current;
    const coefficients = try a.alloc(f64, model.p);
    @memset(coefficients, 0);
    const covariance = try a.alloc(f64, model.p * model.p);
    @memset(covariance, 0);
    for (independent, 0..) |j, k| {
        coefficients[j] = final.beta[k];
        for (independent, 0..) |h, l| covariance[j * model.p + h] = final.sigma * final.cov_unit[k * p + l];
    }
    var positive_components: usize = 1;
    for (ratios) |ratio| {
        if (ratio > 0) positive_components += 1;
    }
    const count = num(positive_components + (if (options.method == .ml) p else @as(usize, 0)));
    const effective = num(if (options.method == .reml) model.n - p else model.n);
    const aic = final.objective + 2 * count;
    const denominator = @max(effective, count + 2) - count - 1;
    const bic_n = options.bic_n orelse if (m == 0) effective else std.math.nan(f64);
    return .{ .n = model.n, .p = model.p, .rank = p, .independent = independent, .coefficients = coefficients, .covariance = covariance, .alias_coefficients = try a.dupe(f64, ranked.alias_coefficients), .variances = try parameters(a, ratios, final.sigma), .residual_variance = final.sigma, .minus2loglik = final.objective, .aic = aic, .aicc = if (denominator > 0) aic + 2 * count * (count + 1) / denominator else null, .bic = if (bic_n > 0) final.objective + count * @log(bic_n) else if (bic_n == 0) final.objective else null, .iterations = try history.toOwnedSlice(a), .converged = status == .converged, .status = status, .method = options.method, .df_error = model.n - p, .pd_h = pd_h, .evaluation_count = evaluations, .rejected_evaluations = rejected, .last_iteration = i };
}
pub const Test = struct { num_df: usize, den_df: usize, f: f64, p: f64 };
pub fn testContrast(a: A, fitted: anytype, l: []const f64, q: usize, den_df: usize) !Test {
    if (q == 0 or l.len != q * fitted.p or den_df == 0) return error.InvalidInput;
    const p = fitted.p;
    for (0..q) |i| for (0..p) |j| {
        var projected: f64 = 0;
        for (0..p) |k| projected += l[i * p + k] * fitted.alias_coefficients[j * p + k];
        if (@abs(projected - l[i * p + j]) > 1e-7 * @max(1, @abs(l[i * p + j]))) return error.Nonestimable;
    };
    const effects = try a.alloc(f64, q);
    @memset(effects, 0);
    const covariance = try a.alloc(f64, q * q);
    @memset(covariance, 0);
    for (0..q) |i| {
        for (0..p) |j| effects[i] += l[i * p + j] * fitted.coefficients[j];
        for (0..q) |j| for (0..p) |k| for (0..p) |h| {
            covariance[i * q + j] += l[i * p + k] * fitted.covariance[k * p + h] * l[j * p + h];
        };
    }
    const inv = try matrix.inverse(a, covariance, q);
    const f = matrix.dot(effects, try matrix.vector(a, inv.values, effects, q)) / num(q);
    return .{ .num_df = q, .den_df = den_df, .f = f, .p = reg.fProbability(f, q, den_df) };
}

test {
    _ = @import("mixed_issues_tests.zig");
    _ = @import("mixed_slice_tests.zig");
    _ = @import("mixed_fit_tests.zig");
    _ = @import("mixed_parms_tests.zig");
    _ = @import("mixed_ods_tests.zig");
}

/// GLS at supplied covariance components, without optimization/profiling.
/// TYPE1-3 callers own estimation/boundary policy. Signed component values are
/// not clipped here; their actual V must be SPD and residual variance positive.
pub const GLS = struct {
    n: usize,
    p: usize,
    rank: usize,
    independent: []usize,
    coefficients: []f64,
    covariance: []f64,
    alias_coefficients: []f64,
    df_error: usize,
    /// Evaluated likelihoods, never claimed to be optimized fits.
    minus2reml: f64,
    minus2ml: f64,
    quadratic: f64,
};
pub fn knownCovariance(a: A, model: Model, variances: []const f64) !GLS {
    if (model.n == 0 or model.p == 0 or model.n > 512 or model.p > 1024 or model.components.len > 8 or variances.len != model.components.len + 1) return error.InvalidInput;
    if (model.weights) |w| if (w.len != model.n) return error.InvalidInput;
    const sigma = variances[variances.len - 1];
    if (!(sigma > 0) or !std.math.isFinite(sigma)) return error.InvalidInput;
    const n = model.n;
    const v = try a.alloc(f64, n * n);
    @memset(v, 0);
    for (0..n) |i| {
        const w = if (model.weights) |weights| weights[i] else 1;
        if (!(w > 0) or !std.math.isFinite(w)) return error.InvalidInput;
        v[i * n + i] = sigma / w;
    }
    for (model.components, variances[0..model.components.len]) |component, value| {
        if (component.kernel.len != n * n or !std.math.isFinite(value)) return error.InvalidInput;
        for (0..n) |i| for (0..n) |j| {
            const k = component.kernel[i * n + j];
            if (!std.math.isFinite(k) or @abs(k - component.kernel[j * n + i]) > 1e-12) return error.InvalidInput;
            v[i * n + j] += value * k;
        };
    }
    return knownCovarianceMatrix(a, model, v);
}
/// GLS for an actual supplied observation covariance (for REPEATED UN/CS/etc).
/// No fictitious residual parameter or positive-component decomposition.
pub fn knownCovarianceMatrix(a: A, model: Model, v: []const f64) !GLS {
    if (model.n == 0 or model.p == 0 or model.n > 512 or model.p > 1024 or v.len != model.n * model.n) return error.InvalidInput;
    const n = model.n;
    for (0..n) |i| for (0..n) |j| {
        if (!std.math.isFinite(v[i * n + j]) or @abs(v[i * n + j] - v[j * n + i]) > 1e-12) return error.InvalidInput;
    };
    var ranked = try ranker.fit(a, model.x, model.y, model.n, model.p, model.weights, model.has_intercept, model.singular);
    defer ranked.deinit(a);
    const p = ranked.fit.rank;
    if (p == 0) return error.InvalidInput;
    const independent = try a.alloc(usize, p);
    var at: usize = 0;
    for (ranked.fit.aliased, 0..) |alias, j| if (!alias) {
        independent[at] = j;
        at += 1;
    };
    const vi = try matrix.inverse(a, v, n);
    const x = try a.alloc(f64, n * p);
    for (0..n) |i| for (independent, 0..) |j, k| {
        x[i * p + k] = model.x[i * model.p + j];
    };
    const b = try a.alloc(f64, n * p);
    @memset(b, 0);
    for (0..n) |i| for (0..n) |j| for (0..p) |k| {
        b[i * p + k] += vi.values[i * n + j] * x[j * p + k];
    };
    const gram = try a.alloc(f64, p * p);
    @memset(gram, 0);
    for (0..p) |i| for (0..p) |j| for (0..n) |k| {
        gram[i * p + j] += x[k * p + i] * b[k * p + j];
    };
    const ci = try matrix.inverse(a, gram, p);
    const rhs = try a.alloc(f64, p);
    @memset(rhs, 0);
    for (0..p) |i| for (0..n) |j| {
        rhs[i] += b[j * p + i] * model.y[j];
    };
    const beta = try matrix.vector(a, ci.values, rhs, p);
    const residual = try a.dupe(f64, model.y);
    for (0..n) |i| for (0..p) |j| {
        residual[i] -= x[i * p + j] * beta[j];
    };
    const q = matrix.dot(residual, try matrix.vector(a, vi.values, residual, n));
    const coefficients = try a.alloc(f64, model.p);
    @memset(coefficients, 0);
    const covariance = try a.alloc(f64, model.p * model.p);
    @memset(covariance, 0);
    for (independent, 0..) |j, k| {
        coefficients[j] = beta[k];
        for (independent, 0..) |h, l| covariance[j * model.p + h] = ci.values[k * p + l];
    }
    return .{ .n = n, .p = model.p, .rank = p, .independent = independent, .coefficients = coefficients, .covariance = covariance, .alias_coefficients = try a.dupe(f64, ranked.alias_coefficients), .df_error = n - p, .minus2reml = vi.logdet + ci.logdet + q + num(n - p) * @log(2 * std.math.pi), .minus2ml = vi.logdet + q + num(n) * @log(2 * std.math.pi), .quadratic = q };
}
