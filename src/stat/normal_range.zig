//! Range of r independent standard normals: studentized range with infinite
//! denominator degrees of freedom. This is NOT finite-df Tukey inference.
//! Conditioning on the minimum X yields
//!   P(R>q)=r integral phi(x)[SF(x)^(r-1)-(SF(x)-SF(x+q))^(r-1)] dx.
//! Evaluate the positive difference with log1p/expm1, avoiding 1-CDF cancellation.
const std = @import("std");
const f = @import("../functions.zig");
pub const Probability = struct { value: f64, estimated_error: f64, evaluations: usize };
fn sf(x: f64) f64 {
    return @exp(f.logStdNormTail(x));
}
const Integrator = struct {
    q: f64,
    r: usize,
    evaluations: usize = 0,
    fn value(self: *Integrator, x: f64) !f64 {
        self.evaluations += 1;
        if (self.evaluations > 300_000) return error.NumericalLimit;
        const a = sf(x);
        if (a == 0) return 0;
        const b = sf(x + self.q);
        if (b == 0) return 0;
        const ratio = @min(1, b / a);
        const power = @as(f64, @floatFromInt(self.r - 1));
        const difference = if (ratio == 1) std.math.pow(f64, a, power) else std.math.pow(f64, a, power) * (-std.math.expm1(power * std.math.log1p(-ratio)));
        return @as(f64, @floatFromInt(self.r)) * @exp(-x * x / 2) / @sqrt(2 * std.math.pi) * difference;
    }
    fn refine(self: *Integrator, a: f64, b: f64, fa: f64, fm: f64, fb: f64, whole: f64, tolerance: f64, depth: usize) anyerror!struct { sum: f64, err: f64 } {
        const m = (a + b) / 2;
        const fl = try self.value((a + m) / 2);
        const fr = try self.value((m + b) / 2);
        const left = (m - a) * (fa + 4 * fl + fm) / 6;
        const right = (b - m) * (fm + 4 * fr + fb) / 6;
        const delta = left + right - whole;
        if (@abs(delta) <= 15 * tolerance or b - a < 1e-10) return .{ .sum = @max(0, left + right + delta / 15), .err = @abs(delta) / 15 };
        if (depth == 0) return error.NumericalLimit;
        const l = try self.refine(a, m, fa, fl, fm, left, tolerance / 2, depth - 1);
        const r = try self.refine(m, b, fm, fr, fb, right, tolerance / 2, depth - 1);
        return .{ .sum = l.sum + r.sum, .err = l.err + r.err };
    }
};
pub fn survival(q: f64, levels: usize) !Probability {
    if (std.math.isNan(q) or q < 0 or levels < 2 or levels > 256) return error.InvalidInput;
    if (q == 0) return .{ .value = 1, .estimated_error = 0, .evaluations = 0 };
    if (std.math.isInf(q)) return .{ .value = 0, .estimated_error = 0, .evaluations = 0 };
    if (levels == 2) return .{ .value = 2 * sf(q / @sqrt(@as(f64, 2))), .estimated_error = @max(std.math.floatTrueMin(f64), 8 * std.math.floatEps(f64) * sf(q / @sqrt(@as(f64, 2)))), .evaluations = 0 };
    // Union bound r(r-1) SF(q/sqrt2), Mills' inequality and r<=256 imply
    // q>=60 is below the smallest representable f64 probability.
    if (q >= 60) return .{ .value = 0, .estimated_error = std.math.floatTrueMin(f64), .evaluations = 0 };
    const left = -(q / 2 + 12);
    const right: f64 = 12;
    const panels: usize = @intFromFloat(@ceil((right - left) * 2));
    const r = @as(f64, @floatFromInt(levels));
    const pair_union = @exp(@log(r * (r - 1)) + f.distLogCdfSdf(.normal, q / @sqrt(@as(f64, 2)), &.{}, true).?);
    const panel_floor = @max(64 * std.math.floatTrueMin(f64), @min(1, pair_union) * 1e-13 / @as(f64, @floatFromInt(panels)));
    const h = (right - left) / @as(f64, @floatFromInt(panels));
    var integrator: Integrator = .{ .q = q, .r = levels };
    var sum: f64 = 0;
    var error_sum: f64 = 0;
    // Half-unit panels bracket the peak even in remote tails; adaptive
    // Simpson error control is relative to each positive panel, with no
    // absolute 1e-12 floor that could erase a genuine small probability.
    for (0..panels) |i| {
        const a = left + h * @as(f64, @floatFromInt(i));
        const b = left + h * @as(f64, @floatFromInt(i + 1));
        const m = (a + b) / 2;
        const fa = try integrator.value(a);
        const fm = try integrator.value(m);
        const fb = try integrator.value(b);
        const whole = (b - a) * (fa + 4 * fm + fb) / 6;
        const part = try integrator.refine(a, b, fa, fm, fb, whole, @max(panel_floor, @abs(whole) * 2e-12), 24);
        sum += part.sum;
        error_sum += part.err;
    }

    // For the omitted left tail split the independent normal difference at
    // q+12 and its independent mean at-6. The direct minimum-tail bound is
    // tighter near q=0. The right bound follows SF(x+q)<=SF(12+q).
    const left_bound = @min(r * sf(-left), r * (r - 1) * (sf(q / @sqrt(@as(f64, 2))) * sf(12 / @sqrt(@as(f64, 2))) + sf((q + 12) / @sqrt(@as(f64, 2)))));
    const right_bound = r * (r - 1) * sf(12) * sf(12 + q);
    const roundoff = 8 * std.math.floatEps(f64) * r * (r - 1) * @max(sum, std.math.floatTrueMin(f64));
    const error_bound = error_sum + left_bound + right_bound + roundoff + panel_floor * @as(f64, @floatFromInt(panels));
    if (!std.math.isFinite(sum) or sum > 1 + error_bound or sum > pair_union + error_bound) return error.NumericalLimit;
    return .{ .value = @max(0, @min(1, sum)), .estimated_error = error_bound, .evaluations = integrator.evaluations };
}

test "NPAR007 normal range two-level identity limits and family dependence" {
    const t = std.testing;
    for ([_]f64{ 0, 0.5, 2, 4, 8, 20 }) |q| {
        const r = try survival(q, 2);
        try t.expectEqual(2 * sf(q / @sqrt(@as(f64, 2))), r.value);
    }
    try t.expectApproxEqAbs(@as(f64, 0.0455002638963584144), (try survival(2 * @sqrt(@as(f64, 2)), 2)).value, 2e-16);
    try t.expectEqual(@as(f64, 1), (try survival(0, 5)).value);
    try t.expectEqual(@as(f64, 0), (try survival(std.math.inf(f64), 5)).value);
    const three = try survival(3, 3);
    const five = try survival(3, 5);
    const ten = try survival(3, 10);
    try t.expect(three.value < five.value and five.value < ten.value);
    const unadjusted = 2 * sf(3 / @sqrt(@as(f64, 2)));
    try t.expect(three.value > unadjusted and three.value < 3 * unadjusted);
    try t.expectError(error.InvalidInput, survival(3, 1));
    try t.expectError(error.InvalidInput, survival(-1, 3));
}

test "NPAR007 Gaussian range matches independent40-digit order-statistic quadrature" {
    const t = std.testing;
    // Independent mpmath40-digit tanh-sinh integral of the CDF, then high-
    // precision complementation (not production's positive-tail integrand).
    // Panels(-inf,-12,-6,-3,0,3,6,12,inf), r*phi(x)*(Phi(x+q)-Phi(x))^(r-1).
    const cases = [_]struct { r: usize, q: f64, p: f64 }{
        .{ .r = 3, .q = 1, .p = 0.75928735877066122591746878260633215 },
        .{ .r = 3, .q = 3, .p = 0.085542571654958003039367931769949674 },
        .{ .r = 5, .q = 3, .p = 0.21087650496353781447446374562204701 },
        .{ .r = 10, .q = 3, .p = 0.51218407397080661515953775546357419 },
        .{ .r = 3, .q = 0.6504, .p = 0.88997702515469878317397072110498374 },
        .{ .r = 5, .q = 8, .p = 0.00000015380313803521567617284375424919735 },
        // Independently85-digit integrated r3 positive tail, algebraically
        // expanded2*a*b-b², retains the small probability instead of1-CDF.
        .{ .r = 3, .q = 20, .p = 6.2654627512876327637044270108915302633787564504e-45 },
    };
    for (cases) |case| {
        const result = try survival(case.q, case.r);
        // 1e-10 relative covers the2e-12 per-panel integration target plus
        // normal-tail/power roundoff; independent of observed discrepancies.
        try t.expectApproxEqRel(case.p, result.value, 1e-10);
        try t.expect(@abs(case.p - result.value) <= result.estimated_error + 32 * std.math.floatEps(f64) * case.p);
    }
    // SAS published Figure21 (Cody, Biostatistics byExampleUsingSASStudio):
    // q=.6504,r=3 displays adjustedp=.8900. Half-unit4decimal quantization in
    // q and p, plus density<=r(r-1)/(2sqrt(pi)), bounds disagreement by.00015.
    try t.expectApproxEqAbs(@as(f64, 0.8900), (try survival(0.6504, 3)).value, 0.00015);
}
