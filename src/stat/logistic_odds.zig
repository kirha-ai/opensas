//! Log-odds contrasts and binary-logit profile likelihood intervals.
//! S154 physical pp.5889–5891,5903–5904,5921–5925. Contrasts, including
//! negative units and CLASS coding, are formed before exponentiation.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const design = @import("logistic_design.zig");
const kernel = @import("logistic_fit.zig");
const reg = @import("reg_fit.zig");
const fns = @import("../functions.zig");
const plots = @import("logistic_plots.zig");
const A = std.mem.Allocator;
pub const Confidence = enum { wald, pl, both };
pub const Request = struct { variable: usize, at_variable: ?usize = null, values: []const f64 = &.{}, label: ?[]const u8 = null, reference_only: bool = false, confidence: Confidence = .wald };
pub const Units = struct { variable: usize, values: []const f64 };
pub const Contrast = struct { label: []const u8, coefficients: []const f64 };

pub fn contrasts(a: A, ds: *const Dataset, d: design.Design, parameter_count: usize, request: Request, units: []const f64) diag.Error![]const Contrast {
    if (parameter_count < d.p or request.variable >= ds.columns.items.len or units.len == 0) return error.ExecError;
    const shift = parameter_count - d.p;
    var found: ?design.Effect = null;
    var class_index: ?usize = null;
    for (d.effects) |effect| if (std.mem.indexOfScalar(usize, effect.variables, request.variable) != null) {
        found = effect;
        if (effect.class_index) |ci| class_index = ci;
    };
    if (found == null) return error.ExecError;
    if (request.at_variable) |at_variable| {
        var interacts = false;
        for (d.effects) |effect| if (std.mem.indexOfScalar(usize, effect.variables, request.variable) != null and std.mem.indexOfScalar(usize, effect.variables, at_variable) != null and at_variable != request.variable) {
            interacts = true;
        };
        if (!interacts) return error.ExecError;
    }
    var results: std.ArrayList(Contrast) = .empty;
    if (class_index) |ci| {
        if (request.at_variable != null) return error.ExecError;
        const c = d.classes[ci];
        const effect = found.?;
        if (effect.variables.len != 1) return error.ExecError;
        for (0..c.map.levels.len) |first| for (0..c.map.levels.len) |second| {
            if (request.reference_only) {
                if (second != c.reference or first == second) continue;
            } else if (first >= second) continue;
            const contrast = try a.alloc(f64, parameter_count);
            @memset(contrast, 0);
            var parameter = effect.start + shift;
            for (0..c.map.levels.len) |level| if (level != c.reference) {
                contrast[parameter] = design.code(first, c.reference, level, c.coding) - design.code(second, c.reference, level, c.coding);
                parameter += 1;
            };
            try results.append(a, .{ .label = try std.fmt.allocPrint(a, "{s} {s} vs {s}", .{ ds.columns.items[request.variable].name, c.map.levels[first].label, c.map.levels[second].label }), .coefficients = contrast });
        };
    } else {
        const values: []const f64 = if (request.at_variable != null) request.values else &.{0};
        if (values.len == 0) return error.ExecError;
        for (units) |unit| for (values) |value| {
            if (unit == 0 or !std.math.isFinite(unit) or !std.math.isFinite(value)) return error.ExecError;
            const contrast = try a.alloc(f64, parameter_count);
            @memset(contrast, 0);
            for (d.effects) |effect| {
                if (std.mem.indexOfScalar(usize, effect.variables, request.variable) == null) continue;
                if (effect.class_index != null) return error.ExecError;
                var coefficient = unit;
                var occurrences: usize = 0;
                for (effect.variables) |variable| {
                    if (variable == request.variable) {
                        occurrences += 1;
                        continue;
                    }
                    if (request.at_variable == null or variable != request.at_variable.?) return error.ExecError;
                    coefficient *= value;
                }
                // Polynomial increments depend on the target's evaluation
                // point; do not silently treat a squared effect as linear.
                if (occurrences != 1) return error.ExecError;
                contrast[effect.start + shift] = coefficient;
            }
            var label = ds.columns.items[request.variable].name;
            if (unit != 1) label = try std.fmt.allocPrint(a, "{s} Units={s}", .{ label, try @import("../format.zig").bestNum(a, unit) });
            if (request.at_variable) |ci| label = try std.fmt.allocPrint(a, "{s} at {s}={s}", .{ label, ds.columns.items[ci].name, try @import("../format.zig").bestNum(a, value) });
            try results.append(a, .{ .label = label, .coefficients = contrast });
        };
    }
    if (request.label) |label| for (results.items, 0..) |*row, i| {
        row.label = if (i == 0) label else try std.fmt.allocPrint(a, "{s} {d}", .{ label, i + 1 });
    };
    return results.items;
}

pub fn wald(a: A, fit: kernel.Fit, contrasts_: []const Contrast, alpha: f64) diag.Error![]plots.Row {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    const q = fit.coefficients.len;
    const z = fns.distQuantile(.normal, 1 - alpha / 2, &.{}).?;
    const rows = try a.alloc(plots.Row, contrasts_.len);
    for (contrasts_, rows) |contrast, *row| {
        if (contrast.coefficients.len != q or fit.covariance.len != q * q) return error.ExecError;
        var estimate: f64 = 0;
        var variance: f64 = 0;
        for (0..q) |i| {
            estimate += contrast.coefficients[i] * fit.coefficients[i];
            for (0..q) |j| variance += contrast.coefficients[i] * fit.covariance[i * q + j] * contrast.coefficients[j];
        }
        if (!std.math.isFinite(estimate) or !std.math.isFinite(variance) or variance < 0) return error.ExecError;
        const margin = z * @sqrt(variance);
        row.* = .{ .label = contrast.label, .log_estimate = estimate, .log_lower = estimate - margin, .log_upper = estimate + margin };
    }
    return rows;
}
fn softplus(x: f64) f64 {
    return @max(0, x) + std.math.log1p(@exp(-@abs(x)));
}
fn likelihood(x: []const f64, y: []const f64, multiplicity: []const f64, b: []const f64, offset: []const f64) f64 {
    var sum: f64 = 0;
    for (y, 0..) |value, i| {
        var eta = offset[i];
        for (b, 0..) |coefficient, j| eta += x[i * b.len + j] * coefficient;
        sum += multiplicity[i] * (if (value == 1) -softplus(-eta) else -softplus(eta));
    }
    return sum;
}

/// Maximize the binary log likelihood subject to c'beta=target. Eliminate
/// the largest contrast coefficient and retain all other nuisance parameters;
/// Constraint elimination and bracketed endpoint roots solve the likelihood-
/// ratio level-set definition on physical p.5921.
pub fn constrainedLikelihood(a: A, d: design.Design, fit: kernel.Fit, contrast: []const f64, target: f64) diag.Error!f64 {
    const p = d.p;
    if (contrast.len != p or fit.coefficients.len != p or p == 0 or d.n == 0 or !std.math.isFinite(target)) return error.ExecError;
    // The PROC producer expands events/trials into binary rows with trial
    // frequencies. Enforce that contract before using Bernoulli likelihoods;
    // a compact fractional response must never be treated as a nonevent.
    if (d.x.len != (std.math.mul(usize, d.n, p) catch return error.ExecError) or d.y.len != d.n or d.frequencies.len != d.n or d.weights.len != d.n) return error.ExecError;
    for (d.y, d.frequencies, d.weights) |value, frequency, weight| {
        if (value != 0 and value != 1) return error.ExecError;
        if (!(frequency > 0) or !(weight > 0) or !std.math.isFinite(frequency * weight)) return error.ExecError;
    }
    for (d.x) |value| if (!std.math.isFinite(value)) return error.ExecError;
    for (contrast, fit.coefficients) |coefficient, estimate| if (!std.math.isFinite(coefficient) or !std.math.isFinite(estimate)) return error.ExecError;
    var pivot: usize = 0;
    for (contrast, 0..) |coefficient, j| if (@abs(coefficient) > @abs(contrast[pivot])) {
        pivot = j;
    };
    if (contrast[pivot] == 0) return error.ExecError;
    var storage = std.heap.ArenaAllocator.init(a);
    defer storage.deinit();
    const tmp = storage.allocator();
    const q = p - 1;
    const x = try tmp.alloc(f64, d.n * q);
    const b = try tmp.alloc(f64, q);
    const offset = try tmp.alloc(f64, d.n);
    const multiplicity = try tmp.alloc(f64, d.n);
    for (0..d.n) |i| {
        offset[i] = d.x[i * p + pivot] * target / contrast[pivot];
        multiplicity[i] = d.frequencies[i] * d.weights[i];
        var j: usize = 0;
        for (0..p) |column| if (column != pivot) {
            x[i * q + j] = d.x[i * p + column] - d.x[i * p + pivot] * contrast[column] / contrast[pivot];
            b[j] = fit.coefficients[column];
            j += 1;
        };
    }
    if (q == 0) return likelihood(x, d.y, multiplicity, b, offset);
    const weights = try tmp.alloc(f64, d.n);
    const working = try tmp.alloc(f64, d.n);
    const gradient = try tmp.alloc(f64, q);
    const candidate = try tmp.alloc(f64, q);
    var iteration = std.heap.ArenaAllocator.init(tmp);
    defer iteration.deinit();
    for (0..100) |_| {
        _ = iteration.reset(.retain_capacity);
        const ia = iteration.allocator();
        const ll = likelihood(x, d.y, multiplicity, b, offset);
        @memset(gradient, 0);
        for (d.y, 0..) |value, i| {
            var eta = offset[i];
            for (b, 0..) |coefficient, j| eta += x[i * q + j] * coefficient;
            const e = @exp(-@abs(eta));
            const probability = kernel.probability(eta);
            weights[i] = multiplicity[i] * e / ((1 + e) * (1 + e));
            if (!(weights[i] > 0)) return error.ExecError;
            const residual = multiplicity[i] * (value - probability);
            working[i] = residual / weights[i];
            for (0..q) |j| gradient[j] += x[i * q + j] * residual;
        }
        var step = try reg.fit(ia, x, working, d.n, q, weights);
        defer step.deinit(ia);
        if (step.rank != q) return error.ExecError;
        var norm: f64 = 0;
        for (gradient, step.coefficients) |g, v| norm += g * v;
        if (norm >= 0 and norm / (@abs(ll) + 1e-6) < 1e-13) return ll;
        var factor: f64 = 1;
        var accepted = false;
        for (0..40) |_| {
            for (0..q) |j| candidate[j] = b[j] + factor * step.coefficients[j];
            if (likelihood(x, d.y, multiplicity, candidate, offset) >= ll) {
                accepted = true;
                break;
            }
            factor /= 2;
        }
        if (!accepted) return error.ExecError;
        @memcpy(b, candidate);
    }
    return error.ExecError;
}
pub fn profile(a: A, d: design.Design, fit: kernel.Fit, contrasts_: []const Contrast, alpha: f64) diag.Error![]const plots.Row {
    const rows = try wald(a, fit, contrasts_, alpha);
    const cutoff = fns.distQuantile(.chisq, 1 - alpha, &.{.{ .num = 1 }}).? / 2;
    for (rows, contrasts_) |*row, contrast| {
        const target = fit.log_likelihood - cutoff;
        const radius = @max(1e-3, row.log_upper - row.log_estimate);
        for ([_]f64{ -1, 1 }) |direction| {
            var inside = row.log_estimate;
            var step = radius;
            var outside = inside + direction * step;
            var bracketed = false;
            for (0..40) |_| {
                if (try constrainedLikelihood(a, d, fit, contrast.coefficients, outside) <= target) {
                    bracketed = true;
                    break;
                }
                step *= 2;
                outside = row.log_estimate + direction * step;
            }
            if (!bracketed) return error.ExecError;
            for (0..70) |_| {
                const midpoint = (inside + outside) / 2;
                const ll = try constrainedLikelihood(a, d, fit, contrast.coefficients, midpoint);
                if (ll > target) inside = midpoint else outside = midpoint;
                if (@abs(outside - inside) <= 1e-10 * (1 + @abs(midpoint))) break;
            }
            if (direction < 0) row.log_lower = (inside + outside) / 2 else row.log_upper = (inside + outside) / 2;
        }
    }
    return rows;
}
