//! Standalone UNIVARIATE EDF inference. No dependency on distribution fitting,
//! rendering, or ODS. Table 4.31 (Statistical Procedures pp.447–448) controls
//! availability; an unavailable test is distinct from a missing implementation.
const std = @import("std");
const diag = @import("../diag.zig");
pub const Family = enum { normal, lognormal, exponential, gamma, weibull, beta, power, gumbel, igauss, pareto, rayleigh, sb, su };
pub const Sign = enum { exact, less, greater };
pub const Probability = struct { value: f64, sign: Sign = .exact };
pub const Statistics = struct { d: f64, w2: f64, a2: f64 };
pub const Result = struct { d: ?Probability = null, w2: ?Probability = null, a2: ?Probability = null };
pub const Available = struct { d: bool = false, w2: bool = false, a2: bool = false };
const all: Available = .{ .d = true, .w2 = true, .a2 = true };
const quadratic: Available = .{ .w2 = true, .a2 = true };
/// True means estimated. Names match SAS option names, including lognormal
/// ZETA (scale) and SIGMA (shape), rather than a generic location/scale mapping.
pub const Estimated = struct {
    theta: bool = false,
    sigma: bool = false,
    mu: bool = false,
    zeta: bool = false,
    alpha: bool = false,
    beta: bool = false,
    c: bool = false,
    lambda: bool = false,
};
pub const Request = struct {
    family: Family,
    estimated: Estimated = .{},
    alpha: f64 = 1,
    beta: f64 = 1,
    sigma: f64 = 1,
    c: f64 = 1,
};

/// Availability is not permission to substitute a complete-parameter null law.
/// Shapes here are the fitted shapes when estimated, supplied shapes otherwise.
pub fn availability(r: Request) Available {
    const e = r.estimated;
    return switch (r.family) {
        .normal => if (e.mu != e.sigma) quadratic else all,
        .lognormal => if (e.theta) (if (r.sigma < 3) all else .{}) else if (e.zeta != e.sigma) quadratic else all,
        .exponential, .gumbel, .igauss, .pareto, .rayleigh => all,
        .gamma => if (e.theta or e.sigma or e.alpha) (if (r.alpha > 1) all else .{}) else all,
        .weibull => if (e.theta) (if (r.c > 2) all else .{}) else if (e.sigma or e.c) quadratic else all,
        .beta => if (e.theta or e.sigma) .{} else if (!e.alpha and !e.beta) all else if (e.alpha and e.beta and r.alpha < 5 and r.beta < 5) all else .{},
        .power => if (e.theta or e.sigma) .{} else if (!e.alpha or r.alpha < 5) all else .{},
        .sb, .su => .{},
    };
}

/// Linear probability interpolation, retaining the table's endpoint AND sign.
/// This is also useful for shape-specific critical tables supplied by callers.
pub fn interpolate(value: f64, critical: []const f64, probabilities: []const f64) Probability {
    std.debug.assert(critical.len == probabilities.len and critical.len > 1);
    if (value < critical[0]) return .{ .value = probabilities[0], .sign = .greater };
    for (1..critical.len) |i| {
        if (value <= critical[i]) return .{ .value = probabilities[i - 1] + (value - critical[i - 1]) / (critical[i] - critical[i - 1]) * (probabilities[i] - probabilities[i - 1]) };
    }
    return .{ .value = probabilities[probabilities.len - 1], .sign = .less };
}

fn validate(d: *diag.Diagnostics, s: Statistics, n: usize) diag.Error!void {
    if (n < 2 or !std.math.isFinite(s.d) or s.d < 0 or s.d > 1 or
        std.math.isNan(s.w2) or s.w2 < 0 or std.math.isNan(s.a2) or s.a2 < 0)
        return d.fail(error.ParseError, 0, "UNIVARIATE: invalid EDF statistics or sample size", .{});
}

/// Raw statistics are not overwritten by the finite-sample corrections used
/// for inference. Null means SAS does not supply that test, not p=missing due
/// to an unfinished implementation. Missing tables produce a diagnostic.
pub fn tabulated(d: *diag.Diagnostics, r: Request, s: Statistics, n: usize) diag.Error!Result {
    try validate(d, s, n);
    if (!(r.alpha > 0) or !(r.beta > 0) or !(r.sigma > 0) or !(r.c > 0) or
        !std.math.isFinite(r.alpha) or !std.math.isFinite(r.beta) or !std.math.isFinite(r.sigma) or !std.math.isFinite(r.c))
        return d.fail(error.ParseError, 0, "UNIVARIATE: invalid EDF inference shape", .{});
    const available = availability(r);
    if (!available.a2) return .{};
    const e = r.estimated;
    const nf: f64 = @floatFromInt(n);
    const fixed = switch (r.family) {
        .normal => !e.mu and !e.sigma,
        .lognormal => !e.theta and !e.zeta and !e.sigma,
        .exponential => !e.theta and !e.sigma,
        .gamma, .power => !e.theta and !e.sigma and !e.alpha,
        .weibull => !e.theta and !e.sigma and !e.c,
        .beta => !e.theta and !e.sigma and !e.alpha and !e.beta,
        else => false,
    };
    if (fixed) {
        const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.001 };
        return .{
            .d = interpolate(s.d * (@sqrt(nf) + 0.12 + 0.11 / @sqrt(nf)), &.{ 1.019, 1.138, 1.224, 1.358, 1.480, 1.628, 1.731, 1.950 }, &levels),
            .w2 = interpolate((s.w2 - 0.4 / nf + 0.6 / (nf * nf)) * (1 + 1 / nf), &.{ 0.209, 0.284, 0.347, 0.461, 0.581, 0.743, 0.869, 1.167 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.248, 1.610, 1.933, 2.492, 3.070, 3.880, 4.500, 6.000 }, &levels),
        };
    }
    if (r.family == .exponential) return exponentialEstimated(s, n, e);
    if (r.family == .gamma and !e.theta) return gammaFixedThreshold(s, n, e, r.alpha);
    if (r.family == .normal or (r.family == .lognormal and !e.theta)) {
        const location = if (r.family == .normal) e.mu else e.zeta;
        if (location and e.sigma) {
            const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005 };
            return .{
                .d = interpolate(s.d * (@sqrt(nf) - 0.01 + 0.85 / @sqrt(nf)), &.{ 0.775, 0.819, 0.895, 0.955, 1.035 }, &.{ 0.15, 0.10, 0.05, 0.025, 0.01 }),
                .w2 = interpolate(s.w2 * (1 + 0.5 / nf), &.{ 0.074, 0.091, 0.104, 0.126, 0.148, 0.178, 0.201 }, &levels),
                .a2 = interpolate(s.a2 * (1 + 0.75 / nf + 2.25 / (nf * nf)), &.{ 0.470, 0.561, 0.631, 0.752, 0.873, 1.035, 1.159 }, &levels),
            };
        }
        const levels = [_]f64{ 0.25, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.0025 };
        // SAS applies no sample correction in either partial-normal case.
        return if (location) .{
            .w2 = interpolate(s.w2, &.{ 0.094, 0.117, 0.134, 0.165, 0.197, 0.238, 0.270, 0.302 }, &levels),
            .a2 = interpolate(s.a2, &.{ 0.644, 0.782, 0.894, 1.087, 1.285, 1.551, 1.756, 1.964 }, &levels),
        } else .{
            .w2 = interpolate(s.w2, &.{ 0.190, 0.263, 0.327, 0.442, 0.562, 0.725, 0.851, 0.978 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.072, 1.430, 1.743, 2.308, 2.898, 3.702, 4.324, 4.954 }, &levels),
        };
    }
    if (r.family == .weibull and !e.theta) {
        const levels = [_]f64{ 0.25, 0.10, 0.05, 0.025, 0.01 };
        if (e.sigma and e.c) {
            const correction = 1 + 0.2 / @sqrt(nf);
            return .{
                .w2 = interpolate(s.w2 * correction, &.{ 0.073, 0.102, 0.124, 0.146, 0.175 }, &levels),
                .a2 = interpolate(s.a2 * correction, &.{ 0.474, 0.637, 0.757, 0.877, 1.038 }, &levels),
            };
        }
        return if (e.sigma) .{
            .w2 = interpolate(s.w2 * (1 + 0.16 / nf), &.{ 0.116, 0.175, 0.222, 0.271, 0.338 }, &levels),
            .a2 = interpolate(s.a2 * (1 + 0.3 / nf), &.{ 0.736, 1.062, 1.321, 1.591, 1.959 }, &levels),
        } else .{
            .w2 = interpolate(s.w2, &.{ 0.186, 0.320, 0.431, 0.547, 0.705 }, &levels),
            .a2 = interpolate(s.a2, &.{ 1.060, 1.725, 2.277, 2.854, 3.640 }, &levels),
        };
    }
    return d.fail(error.ParseError, 0, "UNIVARIATE: EDF inference requires unimplemented parameter-dependent tables or a simulation callback for {s}", .{@tagName(r.family)});
}

// SAS M9 exponential response surfaces, extracted from piecewise-linear
// probability segments at ten sample sizes, independently checked at nine more.
// Order: median, 0.25, 0.20, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.0025, 0.001.
// The median and 0.25 are TWO separate upper bounds; no interpolation between
// them. Coefficients parameterize log critical values (sqrt(n)*D for D).
const exponential_levels = [_]f64{ 0.5, 0.25, 0.20, 0.15, 0.10, 0.05, 0.025, 0.01, 0.005, 0.0025, 0.001 };
const exp_d = [_][3]f64{
    .{ -0.34884625, -0.2237514, 0.17486795 },
    .{ -0.16567106, -0.21533671, 0.0811213 },
    .{ -0.12109459, -0.2053766, -0.04688748 },
    .{ -0.06896504, -0.19554437, -0.19590888 },
    .{ -0.00260487, -0.20086635, -0.19138697 },
    .{ 0.09382164, -0.21179441, -0.22651095 },
    .{ 0.1753938, -0.22531372, -0.27868198 },
    .{ 0.26713071, -0.23995834, -0.43034813 },
    .{ 0.32615868, -0.24779166, -0.76755233 },
    .{ 0.37922604, -0.24382217, -1.2217659 },
    .{ 0.43764642, -0.22806409, -1.81134551 },
};
const exp_w = [_][2]f64{
    .{ -2.6056895, 0.18479393 },
    .{ -2.1568413, 0.04187505 },
    .{ -2.04413, 0.02149181 },
    .{ -1.9123271, -0.01537821 },
    .{ -1.7469892, -0.09140959 },
    .{ -1.5067391, -0.24603488 },
    .{ -1.3066812, -0.37657834 },
    .{ -1.0831492, -0.58328568 },
    .{ -0.93636232, -0.8041545 },
    .{ -0.8055666, -0.95564045 },
    .{ -0.65283933, -1.192646 },
};
const exp_a = [_][2]f64{
    .{ -0.70180186, -0.2147402 },
    .{ -0.30653442, -0.30192468 },
    .{ -0.20555538, -0.31465587 },
    .{ -0.08816246, -0.33593033 },
    .{ 0.05996144, -0.38303162 },
    .{ 0.27846455, -0.45957353 },
    .{ 0.46388675, -0.45493574 },
    .{ 0.67090395, -0.36978474 },
    .{ 0.8078886, -0.21808416 },
    .{ 0.92997681, 0.00896518 },
    .{ 1.0763137, 0.26815749 },
};
const exptheta_d = [_][3]f64{
    .{ -0.1880318, -0.20652846, 0.18711928 },
    .{ 0.01898755, -0.16679491, -0.26921778 },
    .{ 0.0711226, -0.16755907, -0.26471205 },
    .{ 0.13006802, -0.16454187, -0.16196104 },
    .{ 0.20267903, -0.15293427, -0.26803949 },
    .{ 0.30668926, -0.14267496, -0.53471849 },
    .{ 0.39336034, -0.13646324, -0.79360973 },
    .{ 0.49029461, -0.14551843, -0.85934334 },
    .{ 0.5533429, -0.01604847, -0.86389918 },
    .{ 0.60357367, -0.1259946, -1.4966097 },
    .{ 0.66971909, -0.13547152, -2.0135789 },
};
const exptheta_w = [_][2]f64{
    .{ -2.1308363, 0.21272455 },
    .{ -1.5618844, 0.04205112 },
    .{ -1.4203776, 0.01837406 },
    .{ -1.2582052, -0.01466264 },
    .{ -1.0567643, -0.07569159 },
    .{ -0.77417375, -0.21282362 },
    .{ -0.54428916, -0.3561997 },
    .{ -0.30102612, -0.4572686 },
    .{ -0.1401565, -0.63000387 },
    .{ -0.00324516, -0.80758823 },
    .{ 0.1517132, -1.0320772 },
};
const exptheta_a = [_][2]f64{
    .{ -0.2555143, -0.07775099 },
    .{ 0.22181459, -0.01800514 },
    .{ 0.34317831, -0.00545342 },
    .{ 0.48201135, 0.04086803 },
    .{ 0.65800011, 0.07632829 },
    .{ 0.91253926, 0.10267162 },
    .{ 1.12219051, 0.13559866 },
    .{ 1.3517246, 0.18626199 },
    .{ 1.50407819, 0.15393238 },
    .{ 1.64011453, 0.105906 },
    .{ 1.79272159, 0.12212243 },
};
const expboth_d = [_][4]f64{
    .{ -0.348134, -0.23732181, -0.43764886, -0.94529455 },
    .{ -0.16995139, -0.16266977, -0.64539379, -0.3113225 },
    .{ -0.12199367, -0.19751486, -0.52355559, -0.63246777 },
    .{ -0.0690534, -0.20376548, -0.48039334, -0.91170047 },
    .{ -0.00235169, -0.21865553, -0.40470909, -1.3508482 },
    .{ 0.09381459, -0.22891231, -0.38984819, -1.4857804 },
    .{ 0.17697729, -0.26783961, -0.23664388, -2.2226247 },
    .{ 0.26510385, -0.22159365, -0.42923785, -2.2670288 },
    .{ 0.32672117, -0.29924764, -0.12438271, -3.3586959 },
    .{ 0.3866408, -0.40324334, 0.22997952, -4.5193242 },
    .{ 0.43334322, -0.14035849, -0.76510682, -2.1654585 },
};
const expboth_w = [_][3]f64{
    .{ -2.5823807, -0.40159718, -0.41659897 },
    .{ -2.1384254, -0.2658554, -1.1064228 },
    .{ -2.0310676, -0.18536061, -1.3705747 },
    .{ -1.9065991, -0.0958071, -1.6719008 },
    .{ -1.7492204, 0.02456784, -2.0779952 },
    .{ -1.5101355, 0.06148346, -2.3695116 },
    .{ -1.3149815, 0.13385682, -2.6999987 },
    .{ -1.0920466, 0.19236082, -3.1117203 },
    .{ -0.95338453, 0.30120114, -3.5821639 },
    .{ -0.83692236, 0.4330389, -3.9851576 },
    .{ -0.6960093, 0.51963659, -4.2926435 },
};
const expboth_a = [_][4]f64{
    .{ -0.71940969, -4.3586614, 26.7976435, -65.225476 },
    .{ -0.317372, -4.9944919, 29.3455876, -76.490117 },
    .{ -0.21629039, -5.0192176, 28.2869663, -73.443849 },
    .{ -0.100039, -4.8589883, 24.4478564, -61.67257 },
    .{ 0.0488662, -4.8582838, 22.7715691, -57.88102 },
    .{ 0.26948285, -5.0615871, 23.0002786, -60.74452 },
    .{ 0.45296004, -4.8844429, 18.7644176, -49.035546 },
    .{ 0.65739, -4.4492338, 11.5929654, -29.918027 },
    .{ 0.79209856, -4.2458822, 8.99352021, -25.56038 },
    .{ 0.91671452, -4.1969881, 6.07805512, -11.966731 },
    .{ 1.067331, -3.116039, -2.77214797, 13.19961773 },
};

fn exponentialProbability(value: f64, critical: []const f64) Probability {
    if (value < critical[0]) return .{ .value = 0.5, .sign = .greater };
    return interpolate(value, critical[1..], exponential_levels[1..]);
}

/// n is the ORIGINAL sample size. When only theta is estimated, SAS excludes
/// one fitted minimum from the EDF sample: the caller must compute raw D/W2/A2
/// on those n-1 observations. The probability correction also uses n-1.
fn exponentialEstimated(s: Statistics, n: usize, e: Estimated) Result {
    const effective_n = n - @as(usize, if (e.theta and !e.sigma) 1 else 0);
    // M9 emits no EDF table with fewer than five effective observations.
    if (effective_n < 5) return .{};
    const nf: f64 = @floatFromInt(effective_n);
    const inv = 1 / nf;
    const root_inv = @sqrt(inv);
    var d: [11]f64 = undefined;
    var w: [11]f64 = undefined;
    var a: [11]f64 = undefined;
    for (0..11) |i| {
        if (e.theta and e.sigma) {
            const dc = expboth_d[i];
            const wc = expboth_w[i];
            const ac = expboth_a[i];
            d[i] = @exp(dc[0] + dc[1] * root_inv + dc[2] * inv + dc[3] * inv * inv) * root_inv;
            w[i] = @exp(wc[0] + wc[1] * root_inv + wc[2] * inv);
            a[i] = @exp(ac[0] + inv * (ac[1] + inv * (ac[2] + inv * ac[3])));
        } else {
            const dc = if (e.theta) exptheta_d[i] else exp_d[i];
            const wc = if (e.theta) exptheta_w[i] else exp_w[i];
            const ac = if (e.theta) exptheta_a[i] else exp_a[i];
            d[i] = @exp(dc[0] + dc[1] * root_inv + dc[2] * inv * inv) * root_inv;
            w[i] = @exp(wc[0] + wc[1] * inv);
            a[i] = @exp(ac[0] + ac[1] * inv);
        }
    }
    return .{ .d = exponentialProbability(s.d, &d), .w2 = exponentialProbability(s.w2, &w), .a2 = exponentialProbability(s.a2, &a) };
}

// Fixed-threshold gamma log-critical response surfaces. SAS M9 requires
// alpha>1 whenever any parameter is estimated, and n>=10. This is stricter
// than Table 4.31's rows for one estimated parameter; see retained M9 probes.
// Rows are D/W2/A2, then probability levels as in exponential_levels.
// D basis: 1,n^-1/2,n^-1,alpha^-1,(n*alpha)^-1,alpha^-2,(n*alpha^2)^-1.
// W2/A2 basis: 1,n^-1,n^-2,alpha^-1,(n*alpha)^-1,0,0.
const gscale_surface = [3][11][7]f64{
    .{
        .{ -0.41806574, -0.25558052, -0.02935096, 0.09792528, 0.39725016, -0.02695806, -0.35937054 },
        .{ -0.25885287, -0.21025327, -0.12744954, 0.1318541, 0.39725016, -0.0422842, -0.35937054 },
        .{ -0.21977984, -0.20126905, -0.15448613, 0.14439614, 0.39725016, -0.05273168, -0.35937054 },
        .{ -0.175025, -0.18747205, -0.19293132, 0.15776797, 0.39725016, -0.06142538, -0.35937054 },
        .{ -0.11951437, -0.16774307, -0.25132321, 0.17333165, 0.39725016, -0.06856306, -0.35937054 },
        .{ -0.03868108, -0.14928126, -0.32457796, 0.20351088, 0.39725016, -0.09106016, -0.35937054 },
        .{ 0.03025134, -0.14493949, -0.37072055, 0.23117563, 0.39725016, -0.11627067, -0.35937054 },
        .{ 0.1046898, -0.11630817, -0.48523375, 0.27563625, 0.39725016, -0.16738301, -0.35937054 },
        .{ 0.15410558, -0.09574718, -0.57276223, 0.29521635, 0.39725016, -0.18302255, -0.35937054 },
        .{ 0.20129523, -0.07860098, -0.65859822, 0.29043533, 0.39725016, -0.16104759, -0.35937054 },
        .{ 0.25511228, -0.04511254, -0.79708847, 0.31515902, 0.39725016, -0.19717926, -0.35937054 },
    },
    .{
        .{ -2.768275, 0.21572783, 0.06193114, 0.19410876, -0.20421511, 0, 0 },
        .{ -2.3651537, 0.10126179, 0.00467011, 0.24408579, -0.20421511, 0, 0 },
        .{ -2.2655394, 0.0888004, -0.09295156, 0.25814757, -0.20421511, 0, 0 },
        .{ -2.1494069, 0.04952774, -0.05432884, 0.27313641, -0.20421511, 0, 0 },
        .{ -2.0051869, -0.0117441, 0.02892244, 0.29283895, -0.20421511, 0, 0 },
        .{ -1.7981286, -0.07730201, -0.14512687, 0.32766376, -0.20421511, 0, 0 },
        .{ -1.6260447, -0.15304478, -0.31845866, 0.36313161, -0.20421511, 0, 0 },
        .{ -1.4335153, -0.24841281, -0.48812655, 0.39535862, -0.20421511, 0, 0 },
        .{ -1.3092456, -0.29547346, -0.73528453, 0.415166, -0.20421511, 0, 0 },
        .{ -1.1941367, -0.40022102, -0.89173773, 0.4306441, -0.20421511, 0, 0 },
        .{ -1.0640466, 0.41628284, -1.5819102, 0.44921383, -0.20421511, 0, 0 },
    },
    .{
        .{ -0.80505361, -0.27342138, 0.01288268, 0.11974688, 0.0, 0, 0 },
        .{ -0.44278365, -0.27943846, -0.14846148, 0.14947942, 0.0, 0, 0 },
        .{ -0.35120361, -0.28304674, -0.13601252, 0.1570875, 0.0, 0, 0 },
        .{ -0.24431231, -0.28731901, -0.14272555, 0.16788358, -0.0, 0, 0 },
        .{ -0.11074541, -0.28161655, -0.24415972, 0.18336498, -0.0, 0, 0 },
        .{ 0.08599266, -0.27215571, -0.34638547, 0.20522587, -0.0, 0, 0 },
        .{ 0.25378057, -0.26721711, -0.21232372, 0.222501, 0.0, 0, 0 },
        .{ 0.4411769, -0.1693966, -0.11762032, 0.24636185, 0.0, 0, 0 },
        .{ 0.56312381, -0.0590569, 0.15081989, 0.27523914, -0.0, 0, 0 },
        .{ 0.67363494, 0.19029051, -0.10210693, 0.2859269, 0.0, 0, 0 },
        .{ 0.80094459, 0.65632249, -1.3789016, 0.31779391, 0.0, 0, 0 },
    },
};
const gshape_surface = [3][11][7]f64{
    .{
        .{ -0.41900596, -0.25789663, -0.0145315, 0.0381218, 0.10853573, 0, 0 },
        .{ -0.25939334, -0.21289797, -0.11765792, 0.04824401, 0.10853573, 0, 0 },
        .{ -0.22024028, -0.20296944, -0.14720563, 0.05104662, 0.10853573, 0, 0 },
        .{ -0.1752691, -0.18794812, -0.19013894, 0.05422283, 0.10853573, 0, 0 },
        .{ -0.11940792, -0.17246234, -0.24476001, 0.05916906, 0.10853573, 0, 0 },
        .{ -0.0391391, -0.14603795, -0.33836735, 0.06776371, 0.10853573, 0, 0 },
        .{ 0.02942676, -0.13431939, -0.40323075, 0.07439481, 0.10853573, 0, 0 },
        .{ 0.10611188, -0.11499872, -0.50589068, 0.08374191, 0.10853573, 0, 0 },
        .{ 0.15757368, -0.11374341, -0.5619276, 0.08953413, 0.10853573, 0, 0 },
        .{ 0.20305841, -0.09893703, -0.65005944, 0.09742546, 0.10853573, 0, 0 },
        .{ 0.25845561, -0.09459385, -0.72899296, 0.10337094, 0.10853573, 0, 0 },
    },
    .{
        .{ -2.7690406, 0.18447905, 0.05665255, 0.08339567, -0.0, 0, 0 },
        .{ -2.3651244, 0.06966296, 0.06265214, 0.09681226, -0.0, 0, 0 },
        .{ -2.2651169, 0.04956761, 0.00226343, 0.10113406, -0.0, 0, 0 },
        .{ -2.1497304, 0.01748451, -0.00860014, 0.10631375, 0.0, 0, 0 },
        .{ -2.005559, -0.04512578, 0.08889375, 0.110332, 0.0, 0, 0 },
        .{ -1.7997689, -0.08286507, -0.18214949, 0.12088634, -0.0, 0, 0 },
        .{ -1.6275728, -0.16194708, -0.32947411, 0.13203464, -0.0, 0, 0 },
        .{ -1.4355316, -0.25645687, -0.58998271, 0.13898769, -0.0, 0, 0 },
        .{ -1.309466, -0.38326488, -0.46664686, 0.14486614, 0.0, 0, 0 },
        .{ -1.1984314, -0.44991708, -0.65582382, 0.14907985, -0.0, 0, 0 },
        .{ -1.0681269, -0.56988401, -0.93135329, 0.16020614, -0.0, 0, 0 },
    },
    .{
        .{ -0.80719616, -0.25320482, -0.09059234, 0.05448675, -0.11544682, 0, 0 },
        .{ -0.44492391, -0.25503362, -0.21366238, 0.06466653, -0.11544682, 0, 0 },
        .{ -0.35364127, -0.25736032, -0.19718816, 0.06601163, -0.11544682, 0, 0 },
        .{ -0.24673535, -0.27638059, -0.10397087, 0.06890039, -0.11544682, 0, 0 },
        .{ -0.11304634, -0.27734506, -0.09515638, 0.07390672, -0.11544682, 0, 0 },
        .{ 0.08202942, -0.25352807, -0.19979744, 0.08309512, -0.11544682, 0, 0 },
        .{ 0.24923779, -0.24515511, -0.0764443, 0.08502343, -0.11544682, 0, 0 },
        .{ 0.43758404, -0.17596952, 0.07605047, 0.09097594, -0.11544682, 0, 0 },
        .{ 0.56183994, -0.12237287, 0.5912348, 0.09354629, -0.11544682, 0, 0 },
        .{ 0.67534211, -0.06534017, 1.14268417, 0.1016653, -0.11544682, 0, 0 },
        .{ 0.80836522, 0.21186622, 0.75187746, 0.10748242, -0.11544682, 0, 0 },
    },
};
const gboth_surface = [3][11][7]f64{
    .{
        .{ -0.48106181, -0.26482598, 0.04590848, 0.02128007, -0.04047523, 0, 0 },
        .{ -0.32384107, -0.20315362, -0.11379026, 0.0265602, -0.04047523, 0, 0 },
        .{ -0.28293809, -0.21602491, -0.07429426, 0.02711929, -0.04047523, 0, 0 },
        .{ -0.23585869, -0.22014227, -0.07069849, 0.02881089, -0.04047523, 0, 0 },
        .{ -0.17895269, -0.20084127, -0.13694199, 0.03048643, -0.04047523, 0, 0 },
        .{ -0.09758354, -0.14819414, -0.31322962, 0.03348917, -0.04047523, 0, 0 },
        .{ -0.02973419, -0.09248657, -0.49096845, 0.03669027, -0.04047523, 0, 0 },
        .{ 0.05215498, -0.11017626, -0.48405276, 0.04246472, -0.04047523, 0, 0 },
        .{ 0.10484144, -0.0970201, -0.5524165, 0.04285903, -0.04047523, 0, 0 },
        .{ 0.15096632, -0.05939652, -0.70495629, 0.04244515, -0.04047523, 0, 0 },
        .{ 0.20509498, 0.01010174, -0.96945025, 0.04487058, -0.04047523, 0, 0 },
    },
    .{
        .{ -2.9790245, 0.33056138, -0.26991348, 0.05364978, -0.21988415, 0, 0 },
        .{ -2.6057451, 0.14353195, -0.28714404, 0.06255916, -0.21988415, 0, 0 },
        .{ -2.5126046, 0.09428078, -0.28129041, 0.06526373, -0.21988415, 0, 0 },
        .{ -2.403744, 0.03502364, -0.3314299, 0.06779929, -0.21988415, 0, 0 },
        .{ -2.2681564, -0.034768, -0.56183287, 0.07132154, -0.21988415, 0, 0 },
        .{ -2.0727623, -0.10476579, -1.1854955, 0.07841807, -0.21988415, 0, 0 },
        .{ -1.9080225, -0.19002607, -1.5336761, 0.08908393, -0.21988415, 0, 0 },
        .{ -1.7232027, -0.3480029, -1.1542061, 0.09797826, -0.21988415, 0, 0 },
        .{ -1.6007444, -0.48003655, -0.98002611, 0.10062886, -0.21988415, 0, 0 },
        .{ -1.4924231, -0.47122441, -1.6828265, 0.09999803, -0.21988415, 0, 0 },
        .{ -1.3637859, -0.43996235, -3.1104455, 0.10684229, -0.21988415, 0, 0 },
    },
    .{
        .{ -1.0776703, 0.09157167, -0.06760912, 0.02690504, -0.1328685, 0, 0 },
        .{ -0.75626027, -0.05204429, -0.4096316, 0.03344328, -0.1328685, 0, 0 },
        .{ -0.67504987, -0.09198125, -0.46141622, 0.03579301, -0.1328685, 0, 0 },
        .{ -0.58008627, -0.14442724, -0.52185598, 0.03739042, -0.1328685, 0, 0 },
        .{ -0.46092461, -0.19397346, -0.72029496, 0.0391661, -0.1328685, 0, 0 },
        .{ -0.28659085, -0.23686371, -1.3293136, 0.04456556, -0.1328685, 0, 0 },
        .{ -0.1381183, -0.29726543, -1.7300038, 0.05027529, -0.1328685, 0, 0 },
        .{ 0.0316945, -0.37843917, -2.1456895, 0.05538609, -0.1328685, 0, 0 },
        .{ 0.14467348, -0.42739248, -2.4920157, 0.05468226, -0.1328685, 0, 0 },
        .{ 0.24531701, -0.44714936, -3.1608039, 0.06148775, -0.1328685, 0, 0 },
        .{ 0.36702609, -0.44257409, -4.4750451, 0.06374178, -0.1328685, 0, 0 },
    },
};

fn gammaFixedThreshold(s: Statistics, n: usize, e: Estimated, alpha: f64) Result {
    if (n < 10) return .{};
    const table = if (e.alpha and e.sigma) &gboth_surface else if (e.alpha) &gshape_surface else &gscale_surface;
    const inv = 1 / @as(f64, @floatFromInt(n));
    const root_inv = @sqrt(inv);
    const ia = 1 / alpha;
    const db = [_]f64{ 1, root_inv, inv, ia, ia * inv, ia * ia, ia * ia * inv };
    const qb = [_]f64{ 1, inv, inv * inv, ia, ia * inv, 0, 0 };
    var probabilities: [3]Probability = undefined;
    const stats = [_]f64{ s.d, s.w2, s.a2 };
    for (0..3) |t| {
        var criticals: [11]f64 = undefined;
        for (table[t], 0..) |row, i| {
            var log_critical: f64 = 0;
            for (row, if (t == 0) db else qb) |coefficient, term| log_critical += coefficient * term;
            criticals[i] = @exp(log_critical) * (if (t == 0) root_inv else 1);
        }
        probabilities[t] = exponentialProbability(stats[t], &criticals);
    }
    return .{ .d = probabilities[0], .w2 = probabilities[1], .a2 = probabilities[2] };
}

pub const SimulationOptions = struct {
    /// Caller resolves omitted/time-of-day seed once, and can retain it in ODS.
    seed: u64,
    samples: usize = 500,
};
pub const SimulationResult = struct {
    probabilities: Result,
    exceedances: [3]usize,
    samples: usize,
    seed: u64,
    /// Binomial standard errors, in D/W2/A2 order. These describe Monte Carlo
    /// uncertainty, not uncertainty about the model or its fitted parameters.
    standard_errors: [3]f64,
};
pub const Simulator = struct {
    context: ?*anyopaque = null,
    /// Generate n observations from the fitted null, refit the estimated
    /// parameters with the same constraints, and return raw EDF statistics.
    /// Preserve fixed parameters. Errors propagate; never discard failed fits.
    draw: *const fn (?*anyopaque, std.Random, usize, *diag.Diagnostics) diag.Error!Statistics,
};

/// Parametric bootstrap for the four simulation families (manual p.446).
/// A fixed seed is reproducible with this implementation; SAS does not promise
/// its random stream, so cross-engine comparisons must allow Monte Carlo error.
pub fn simulate(d: *diag.Diagnostics, r: Request, observed: Statistics, n: usize, options: SimulationOptions, sampler: Simulator) diag.Error!SimulationResult {
    try validate(d, observed, n);
    switch (r.family) {
        .gumbel, .igauss, .pareto, .rayleigh => {},
        else => return d.fail(error.ParseError, 0, "UNIVARIATE: this family requires tabulated EDF probabilities", .{}),
    }
    if (options.samples == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: EDFNSAMPLES must be positive", .{});
    var generator = std.Random.DefaultPrng.init(options.seed);
    var counts = [_]usize{0} ** 3;
    for (0..options.samples) |_| {
        const s = try sampler.draw(sampler.context, generator.random(), n, d);
        try validate(d, s, n);
        if (s.d >= observed.d) counts[0] += 1;
        if (s.w2 >= observed.w2) counts[1] += 1;
        if (s.a2 >= observed.a2) counts[2] += 1;
    }
    const m: f64 = @floatFromInt(options.samples);
    var p: [3]Probability = undefined;
    var se: [3]f64 = undefined;
    for (counts, 0..) |k, i| {
        p[i] = .{ .value = @as(f64, @floatFromInt(k)) / m };
        se[i] = @sqrt(p[i].value * (1 - p[i].value) / m);
    }
    return .{ .probabilities = .{ .d = p[0], .w2 = p[1], .a2 = p[2] }, .exceedances = counts, .standard_errors = se, .samples = options.samples, .seed = options.seed };
}

test "dev5 EDF Table 4.31 estimation masks and strict shape boundaries" {
    try std.testing.expect(!availability(.{ .family = .normal, .estimated = .{ .mu = true } }).d);
    try std.testing.expect(availability(.{ .family = .normal, .estimated = .{ .mu = true } }).a2);
    try std.testing.expect(!availability(.{ .family = .lognormal, .estimated = .{ .theta = true }, .sigma = 3 }).a2);
    try std.testing.expect(availability(.{ .family = .lognormal, .estimated = .{ .theta = true }, .sigma = 2.99 }).d);
    try std.testing.expect(!availability(.{ .family = .gamma, .estimated = .{ .alpha = true, .sigma = true } }).a2);
    try std.testing.expect(!availability(.{ .family = .gamma, .estimated = .{ .alpha = true } }).a2);
    try std.testing.expect(!availability(.{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2 }).a2);
    try std.testing.expect(availability(.{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2.01 }).d);
    try std.testing.expect(!availability(.{ .family = .weibull, .estimated = .{ .c = true } }).d);
    try std.testing.expect(!availability(.{ .family = .power, .estimated = .{ .alpha = true }, .alpha = 5 }).a2);
    try std.testing.expect(!availability(.{ .family = .beta, .estimated = .{ .alpha = true } }).a2);
    try std.testing.expect(availability(.{ .family = .beta, .estimated = .{ .alpha = true, .beta = true }, .alpha = 4.99 }).a2);
    try std.testing.expect(!availability(.{ .family = .beta, .estimated = .{ .alpha = true, .beta = true }, .beta = 5 }).a2);
    for ([_]Family{ .sb, .su }) |f| try std.testing.expectEqual(Available{}, availability(.{ .family = f }));
}

test "dev5 EDF interpolation preserves exact knots and endpoint signs" {
    const knots = [_]f64{ 1, 2, 3 };
    const levels = [_]f64{ 0.25, 0.05, 0.01 };
    try std.testing.expectEqual(Sign.exact, interpolate(1, &knots, &levels).sign);
    try std.testing.expectEqual(Sign.exact, interpolate(3, &knots, &levels).sign);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), interpolate(1.5, &knots, &levels).value, 1e-15);
    try std.testing.expectEqual(Probability{ .value = 0.25, .sign = .greater }, interpolate(0, &knots, &levels));
    try std.testing.expectEqual(Probability{ .value = 0.01, .sign = .less }, interpolate(4, &knots, &levels));
}

// A standalone test callback: the complete-parameter probability integral
// transform is uniform for each of the four families. Estimated Rayleigh scale
// is sqrt(mean(x^2)/2), equivalently mean of exponential transformed values.
const TestSampler = struct {
    refit_rayleigh: bool = false,
    fn draw(raw: ?*anyopaque, random: std.Random, n: usize, diagnostics: *diag.Diagnostics) diag.Error!Statistics {
        const self: *TestSampler = @ptrCast(@alignCast(raw.?));
        const u = try diagnostics.arena.alloc(f64, n);
        defer diagnostics.arena.free(u);
        var mean: f64 = 0;
        for (u) |*v| {
            v.* = -@log(1 - random.float(f64));
            mean += v.* / @as(f64, @floatFromInt(n));
        }
        for (u) |*v| v.* = -std.math.expm1(-v.* / (if (self.refit_rayleigh) mean else 1));
        std.mem.sort(f64, u, {}, std.sort.asc(f64));
        const nf: f64 = @floatFromInt(n);
        var s: Statistics = .{ .d = 0, .w2 = 1 / (12 * nf), .a2 = -nf };
        for (u, 0..) |v, i| {
            const fi: f64 = @floatFromInt(i);
            s.d = @max(s.d, @max((fi + 1) / nf - v, v - fi / nf));
            const delta = v - (fi + 0.5) / nf;
            s.w2 += delta * delta;
            s.a2 -= (2 * fi + 1) / nf * (@log(v) + std.math.log1p(-u[n - i - 1]));
        }
        return s;
    }
};

test "dev5 EDF simulations agree with independent SAS M9 within binomial uncertainty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sampler: TestSampler = .{};
    const cases = [_]struct { family: Family, stats: Statistics, p: [3]f64, refit: bool = false }{
        .{ .family = .rayleigh, .stats = .{ .d = 0.16062095035231, .w2 = 0.47827512405361, .a2 = 2.93957796590725 }, .p = .{ 0.2269, 0.0462, 0.0305 } },
        .{ .family = .rayleigh, .stats = .{ .d = 0.10001215220679, .w2 = 0.11990472112324, .a2 = 0.96463236078575 }, .p = .{ 0.6012, 0.2315, 0.1294 }, .refit = true },
        .{ .family = .gumbel, .stats = .{ .d = 0.38732655154844, .w2 = 1.94483849079829, .a2 = 9.05693013472377 }, .p = .{ 0, 0.0001, 0.0001 } },
        .{ .family = .igauss, .stats = .{ .d = 0.16728255176424, .w2 = 0.38546561039003, .a2 = 1.95835761620976 }, .p = .{ 0.188, 0.077, 0.095 } },
        .{ .family = .pareto, .stats = .{ .d = 0.18132138066867, .w2 = 0.40966827227087, .a2 = 2.59352817496381 }, .p = .{ 0.1288, 0.0704, 0.0454 } },
    };
    for (cases) |c| {
        sampler.refit_rayleigh = c.refit;
        const result = try simulate(&d, .{ .family = c.family }, c.stats, 40, .{ .seed = 86531, .samples = 10000 }, .{ .context = &sampler, .draw = TestSampler.draw });
        const ps = [_]f64{ result.probabilities.d.?.value, result.probabilities.w2.?.value, result.probabilities.a2.?.value };
        for (ps, c.p) |actual, reference| {
            // Independent 10,000-replicate experiments: five pooled binomial
            // standard errors plus one count. Continuity floor handles zero.
            const pooled = @max((actual + reference) / 2, 1.0 / 10000.0);
            const tolerance = 5 * @sqrt(2 * pooled * (1 - pooled) / 10000) + 1.0 / 10000.0;
            try std.testing.expectApproxEqAbs(reference, actual, tolerance);
        }
    }
}

test "dev5 EDF seed reproducibility, sample counts, and loud callback failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sampler: TestSampler = .{};
    const callback: Simulator = .{ .context = &sampler, .draw = TestSampler.draw };
    const stats: Statistics = .{ .d = 0.15, .w2 = 0.2, .a2 = 1 };
    const r: Request = .{ .family = .rayleigh };
    const a = try simulate(&d, r, stats, 20, .{ .seed = 42 }, callback);
    const b = try simulate(&d, r, stats, 20, .{ .seed = 42 }, callback);
    try std.testing.expectEqualDeep(a, b);
    try std.testing.expectEqual(@as(usize, 500), a.samples);
    const c = try simulate(&d, r, stats, 20, .{ .seed = 43 }, callback);
    try std.testing.expect(!std.meta.eql(a.exceedances, c.exceedances));
    try std.testing.expectError(error.ParseError, simulate(&d, r, stats, 20, .{ .seed = 42, .samples = 0 }, callback));
    try std.testing.expectError(error.ParseError, simulate(&d, .{ .family = .normal }, stats, 20, .{ .seed = 42 }, callback));
    const Failure = struct {
        fn draw(_: ?*anyopaque, _: std.Random, _: usize, diagnostics: *diag.Diagnostics) diag.Error!Statistics {
            return diagnostics.fail(error.ExecError, 0, "test bootstrap fit did not converge", .{});
        }
    };
    try std.testing.expectError(error.ExecError, simulate(&d, r, stats, 20, .{ .seed = 42 }, .{ .draw = Failure.draw }));
    try std.testing.expect(d.hasErrors());
}

test "dev5 EDF independent heldout SAS partial normal lognormal and Weibull tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var lines = std.mem.splitScalar(u8, @embedFile("testdata/univ_edf_dev5_heldout.txt"), '\n');
    var checked: usize = 0;
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \r").len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next().?;
        const n = try std.fmt.parseInt(usize, std.mem.trim(u8, fields.next().?, " "), 10);
        _ = fields.next().?; // independent perturbation index, retained for replay
        const statistic = std.mem.trim(u8, fields.next().?, " ");
        const value = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
        const expected = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
        const sign = std.mem.trim(u8, fields.next().?, " \r");
        const eq = std.mem.eql;
        const r: Request = if (eq(u8, id, "nmu")) .{ .family = .normal, .estimated = .{ .sigma = true } } else if (eq(u8, id, "nsig")) .{ .family = .normal, .estimated = .{ .mu = true } } else if (eq(u8, id, "lz")) .{ .family = .lognormal, .estimated = .{ .sigma = true } } else if (eq(u8, id, "ls")) .{ .family = .lognormal, .estimated = .{ .zeta = true } } else if (eq(u8, id, "wboth")) .{ .family = .weibull, .estimated = .{ .sigma = true, .c = true } } else if (eq(u8, id, "wc")) .{ .family = .weibull, .estimated = .{ .sigma = true }, .c = 4 } else if (eq(u8, id, "wsig")) .{ .family = .weibull, .estimated = .{ .c = true } } else unreachable;
        const w = eq(u8, statistic, "W-Sq");
        const result = try tabulated(&d, r, .{ .d = 0, .w2 = if (w) value else 0, .a2 = if (w) 0 else value }, n);
        try std.testing.expect(result.d == null);
        const p = if (w) result.w2.? else result.a2.?;
        try std.testing.expectApproxEqAbs(expected, p.value, 1e-10);
        const expected_sign: Sign = if (eq(u8, sign, ">")) .greater else if (eq(u8, sign, "<")) .less else .exact;
        try std.testing.expectEqual(expected_sign, p.sign);
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 1708), checked);
}

test "dev5 EDF unimplemented inference differs from documented unavailability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const s: Statistics = .{ .d = 0.1, .w2 = 0.1, .a2 = 0.5 };
    const unavailable = try tabulated(&d, .{ .family = .weibull, .estimated = .{ .theta = true }, .c = 2 }, s, 30);
    try std.testing.expectEqual(Result{}, unavailable);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectError(error.ParseError, tabulated(&d, .{ .family = .gamma, .estimated = .{ .theta = true }, .alpha = 2 }, s, 30));
    try std.testing.expect((try tabulated(&d, .{ .family = .exponential, .estimated = .{ .sigma = true } }, s, 30)).d != null);
    try std.testing.expectError(error.ParseError, tabulated(&d, .{ .family = .normal }, s, 0));
    try std.testing.expect(d.hasErrors());
}

test "dev5 EDF exponential all estimation masks independent M9 holdouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var lines = std.mem.splitScalar(u8, @embedFile("testdata/univ_edf_dev5_exponential.txt"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next().?;
        const n = try std.fmt.parseInt(usize, fields.next().?, 10);
        _ = fields.next().?;
        const statistic = fields.next().?;
        const value = try std.fmt.parseFloat(f64, fields.next().?);
        const expected = try std.fmt.parseFloat(f64, fields.next().?);
        const sign = fields.next().?;
        const e: Estimated = if (std.mem.eql(u8, id, "exp")) .{ .sigma = true } else if (std.mem.eql(u8, id, "exptheta")) .{ .theta = true } else .{ .theta = true, .sigma = true };
        var s: Statistics = .{ .d = 0, .w2 = 0, .a2 = 0 };
        const test_d = std.mem.eql(u8, statistic, "D");
        const test_w = std.mem.eql(u8, statistic, "W-Sq");
        if (test_d) s.d = value else if (test_w) s.w2 = value else s.a2 = value;
        const result = try tabulated(&d, .{ .family = .exponential, .estimated = e }, s, n);
        const p = if (test_d) result.d.? else if (test_w) result.w2.? else result.a2.?;
        try std.testing.expectApproxEqAbs(expected, p.value, 2e-10);
        const expected_sign: Sign = if (std.mem.eql(u8, sign, ">")) .greater else if (std.mem.eql(u8, sign, "<")) .less else .exact;
        try std.testing.expectEqual(expected_sign, p.sign);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 9438), count);
    const s: Statistics = .{ .d = 0.2, .w2 = 0.1, .a2 = 0.5 };
    for (2..5) |n| {
        try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .exponential, .estimated = .{ .sigma = true } }, s, n));
        try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .exponential, .estimated = .{ .sigma = true, .theta = true } }, s, n));
    }
    try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .exponential, .estimated = .{ .theta = true } }, s, 5));
}

test "dev5 EDF fixed-threshold gamma three estimation masks independent M9 holdouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var lines = std.mem.splitScalar(u8, @embedFile("testdata/univ_edf_dev5_gamma.txt"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next().?;
        const n = try std.fmt.parseInt(usize, fields.next().?, 10);
        _ = fields.next().?;
        const statistic = fields.next().?;
        const value = try std.fmt.parseFloat(f64, fields.next().?);
        const expected = try std.fmt.parseFloat(f64, fields.next().?);
        const sign = fields.next().?;
        const alpha = try std.fmt.parseFloat(f64, fields.next().?);
        const e: Estimated = if (std.mem.startsWith(u8, id, "gscale")) .{ .sigma = true } else if (std.mem.startsWith(u8, id, "gshape")) .{ .alpha = true } else .{ .alpha = true, .sigma = true };
        var s: Statistics = .{ .d = 0, .w2 = 0, .a2 = 0 };
        const test_d = std.mem.eql(u8, statistic, "D");
        const test_w = std.mem.eql(u8, statistic, "W-Sq");
        if (test_d) s.d = value else if (test_w) s.w2 = value else s.a2 = value;
        const result = try tabulated(&d, .{ .family = .gamma, .estimated = e, .alpha = alpha }, s, n);
        const p = if (test_d) result.d.? else if (test_w) result.w2.? else result.a2.?;
        try std.testing.expectApproxEqAbs(expected, p.value, 1e-10);
        const expected_sign: Sign = if (std.mem.eql(u8, sign, ">")) .greater else if (std.mem.eql(u8, sign, "<")) .less else .exact;
        try std.testing.expectEqual(expected_sign, p.sign);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 23184), count);
    const s: Statistics = .{ .d = 0.2, .w2 = 0.1, .a2 = 0.5 };
    try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .gamma, .estimated = .{ .sigma = true }, .alpha = 2 }, s, 9));
    try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .gamma, .estimated = .{ .sigma = true }, .alpha = 1 }, s, 20));
    try std.testing.expectEqual(Result{}, try tabulated(&d, .{ .family = .gamma, .estimated = .{ .alpha = true }, .alpha = 0.99 }, s, 20));
}
