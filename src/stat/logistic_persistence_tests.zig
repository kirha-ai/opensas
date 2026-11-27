//! Independent grouped-binomial reference for the original LOGISTIC SVG data.
//! Gaussian elimination on four information equations is deliberately distinct
//! from the production compact Bernoulli representation and augmented QR.
const std = @import("std");
const t = std.testing;
const helper = @import("glm_persistence_tests.zig");
const Dataset = @import("../dataset.zig").Dataset;

fn solve(matrix: [4][4]f64, rhs: [4]f64) ![4]f64 {
    var m = matrix;
    var b = rhs;
    for (0..4) |j| {
        var pivot = j;
        for (j + 1..4) |i| if (@abs(m[i][j]) > @abs(m[pivot][j])) {
            pivot = i;
        };
        try t.expect(@abs(m[pivot][j]) > 1e-12);
        std.mem.swap([4]f64, &m[j], &m[pivot]);
        std.mem.swap(f64, &b[j], &b[pivot]);
        const scale = m[j][j];
        for (j..4) |k| m[j][k] /= scale;
        b[j] /= scale;
        for (0..4) |i| if (i != j) {
            const factor = m[i][j];
            for (j..4) |k| m[i][k] -= factor * m[j][k];
            b[i] -= factor * b[j];
        };
    }
    return b;
}

fn likelihood(ds: Dataset, b: [4]f64) f64 {
    var ll: f64 = 0;
    for (ds.rows.items) |row| {
        const eta = b[0] + row[0].num * b[1] + row[1].num * b[2] + row[0].num * row[1].num * b[3];
        ll += row[2].num * eta - row[3].num * @log(1 + @exp(eta));
    }
    return ll;
}

const Reference = struct { beta: [4]f64, covariance: [4][4]f64 };
pub fn reference(ds: Dataset) !Reference {
    var b = [4]f64{ @log(@as(f64, 12.0 / 375.0)), 0, 0, 0 };
    for (0..100) |iteration| {
        var information: [4][4]f64 = @splat(@splat(0));
        var score: [4]f64 = @splat(0);
        for (ds.rows.items) |row| {
            const x = [4]f64{ 1, row[0].num, row[1].num, row[0].num * row[1].num };
            var eta: f64 = 0;
            for (x, b) |v, coef| eta += v * coef;
            const p = 1 / (1 + @exp(-eta));
            for (0..4) |j| {
                score[j] += x[j] * (row[2].num - row[3].num * p);
                for (0..4) |k| information[j][k] += row[3].num * p * (1 - p) * x[j] * x[k];
            }
        }
        const step = try solve(information, score);
        var norm: f64 = 0;
        for (score, step) |s, v| norm += s * v;
        const ll = likelihood(ds, b);
        // S154 physical p.5877 GCONV denominator; same stopping criterion
        // as the independent original NumPy verifier, not convergence to a
        // different final iterate hidden behind a loose plotting tolerance.
        if (norm / (@abs(ll) + 1e-6) <= 1e-8) {
            var cov: [4][4]f64 = undefined;
            for (0..4) |j| {
                var unit: [4]f64 = @splat(0);
                unit[j] = 1;
                const column = try solve(information, unit);
                for (0..4) |i| cov[i][j] = column[i];
            }
            return .{ .beta = b, .covariance = cov };
        }
        var candidate: [4]f64 = undefined;
        for (0..4) |j| candidate[j] = b[j] + step[j];
        if (likelihood(ds, candidate) < ll) {
            var ridge: f64 = 0.0001;
            var accepted = false;
            for (0..40) |_| {
                var penalized = information;
                for (0..4) |j| penalized[j][j] *= 1 + ridge;
                const adjusted = try solve(penalized, score);
                for (0..4) |j| candidate[j] = b[j] + adjusted[j];
                if (likelihood(ds, candidate) >= ll) {
                    // SAS ITPRINT independently established the first ridge.
                    if (iteration == 0) try t.expectApproxEqAbs(@as(f64, 0.0064), ridge, 1e-15);
                    accepted = true;
                    break;
                }
                ridge *= 2;
            }
            try t.expect(accepted);
        }
        b = candidate;
    }
    return error.ReferenceDidNotConverge;
}
