//! SAS 9.4 M9 Hoeffding probability, for SAS's 30-times-original D.
//! See docs/findings/corr-hoeffding-probability-dev5 for the independently
//! recovered piecewise polynomial calibration and held-out oracle validation.
//! This is NOT the exact spectral BKR CDF or the Hmisc table approximation.
const std = @import("std");

/// Pairwise effective frequency N. N <= 5 has missing inference in SAS, even
/// though D itself exists at N=5. Nonfinite/invalid inputs return missing (NaN),
/// following corr_advanced's numerical-kernel convention. Tied D may be < -0.5.
pub fn probability(d: f64, n: f64) f64 {
    if (!std.math.isFinite(d) or !std.math.isFinite(n) or n < 6 or @floor(n) != n or d > 1)
        return std.math.nan(f64);
    if (d == 1) return 0;
    const pi4 = std.math.pi * std.math.pi * std.math.pi * std.math.pi;
    const z = pi4 * ((n - 1) * d / 60 + 1.0 / 72.0);
    // Branch selection uses the rounded centering constant 1.3529, not
    // pi^4/72. Keep z in the recovered coefficient basis for evaluation.
    const branch_z = pi4 * ((n - 1) * d / 60) + 1.3529;
    // SAS's calibrated range has hard endpoints, not an exponential extension.
    if (branch_z < 0.3) return 1;
    if (branch_z > 10.3) return 0.00001;
    if (branch_z < 0.55) return 1 - @exp(chebyshev(z, 0.38, 0.55, &low));
    if (branch_z < 1.1) return chebyshev(z, 0.55, 1.1, &lower);
    if (branch_z < 2.95) return chebyshev(z, 1.1, 2.95, &middle);
    return @exp(chebyshev(z, 2.95, 10.3, &upper));
}

// Clenshaw evaluation avoids cancellation in the original power basis.
fn chebyshev(z: f64, lo: f64, hi: f64, coefficients: []const f64) f64 {
    const x = (2 * z - lo - hi) / (hi - lo);
    var b1: f64 = 0;
    var b2: f64 = 0;
    var i = coefficients.len;
    while (i > 1) {
        i -= 1;
        const b0 = 2 * x * b1 - b2 + coefficients[i];
        b2 = b1;
        b1 = b0;
    }
    return x * b1 - b2 + coefficients[0];
}

// Distribution polynomial coefficients, not per-N or per-D lookup values.
// Degrees: log(CDF) 4, survival 7 and 8, log(survival) 8. Coefficients were
// determined from the discovery sweep only; none use the held-out cases.
const low = [_]f64{ -5.4577831497784635, 2.058913670875947, -0.27522440082496263, 0.03328749814169981, -0.003046557360999455 };
const lower = [_]f64{ 0.7627634825216704, -0.2276994983322827, -0.011507469470051292, 0.008285988780776922, -0.0008155029325341527, -0.00020755551913124702, 8.600551178853317e-05, -1.1720786687608636e-05 };
const middle = [_]f64{ 0.21108122030684665, -0.22553738431322082, 0.07343346941404134, -0.017752100758370994, 0.0031359839966982046, -0.00020675104003992897, -0.00013124903468688756, 8.229857702289095e-05, -2.8277509921318844e-05 };
const upper = [_]f64{ -7.183000717088426, -3.991675053572864, 0.05270155704751924, -0.012032576329682132, 0.003284017064785503, -0.0009739391777788688, 0.00030119792248771426, -9.930803357990308e-05, 2.6816442679172787e-05 };

test "Hoeffding probability discriminating SAS M9 grid" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.27035003097535), probability(1.0 / 56.0, 8), 5e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00421936667347), probability(9.0 / 28.0, 8), 5e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.19028121558348), probability(5.0 / 198.0, 12), 5e-13);
    try std.testing.expectEqual(@as(f64, 0), probability(1, 12));
    try std.testing.expectEqual(@as(f64, 0), probability(1, 20));
    try std.testing.expectEqual(@as(f64, 1), probability(-0.625, 6));
    try std.testing.expectEqual(@as(f64, 1), probability(-1.171875, 6));
    try std.testing.expectEqual(@as(f64, 1), probability(-1.0 / 7.0, 9));
}

test "Hoeffding probability 500 independent SAS M9 cases including branch neighbors" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("corr_hoeffding_probability_dev5.csv"), '\n');
    _ = lines.next();
    var count: usize = 0;
    while (lines.next()) |line| {
        var cells = std.mem.splitScalar(u8, line, ',');
        const n = try std.fmt.parseFloat(f64, cells.next().?);
        const d = try std.fmt.parseFloat(f64, cells.next().?);
        const p = cells.next().?;
        const actual = probability(d, n);
        if (std.mem.eql(u8, p, ".")) {
            try std.testing.expect(std.math.isNan(actual));
        } else {
            const expected = try std.fmt.parseFloat(f64, p);
            try std.testing.expectApproxEqAbs(expected, actual, 5e-13);
        }
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 500), count);
}

test "Hoeffding probability invalid inputs and finite endpoints" {
    for ([_]f64{ 0, 4, 5, 6.5, std.math.nan(f64), std.math.inf(f64) }) |n|
        try std.testing.expect(std.math.isNan(probability(0, n)));
    for ([_]f64{ std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64), 1.01 }) |d|
        try std.testing.expect(std.math.isNan(probability(d, 12)));
    try std.testing.expectEqual(@as(f64, 0.00001), probability(0.999999, 1e300));
    try std.testing.expectEqual(@as(f64, 1), probability(-1e300, 1e300));
    try std.testing.expectEqual(@as(f64, 0), probability(1, 6));
    try std.testing.expectApproxEqAbs(@as(f64, 0.97700651510051), probability(-1.0 / 14.0, 8), 5e-13);
}

test "Hoeffding probability preserves independently observed SAS calibration jumps" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("corr_hoeffding_probability_boundaries_dev5.csv"), '\n');
    _ = lines.next();
    var actual: [10]f64 = undefined;
    var count: usize = 0;
    while (lines.next()) |line| {
        try std.testing.expect(count < actual.len);
        var cells = std.mem.splitScalar(u8, line, ',');
        const n = try std.fmt.parseFloat(f64, cells.next().?);
        const d = try std.fmt.parseFloat(f64, cells.next().?);
        const expected = try std.fmt.parseFloat(f64, cells.next().?);
        actual[count] = probability(d, n);
        try std.testing.expectApproxEqAbs(expected, actual[count], 5e-13);
        count += 1;
    }
    try std.testing.expectEqual(actual.len, count);
    for (0..5) |i| {
        // The upward jump at 1.1 is in SAS too; imposing monotonicity would
        // silently change the calibration. All four other jumps go down.
        if (i == 2) try std.testing.expect(actual[2 * i + 1] > actual[2 * i]) else try std.testing.expect(actual[2 * i + 1] < actual[2 * i]);
    }
}
