//! Unconditional two-binomial inference, SAS/STAT pp.189–194,205–206.
//! Row totals are fixed; columns vary. At RD=d, p1=p2+d and
//! p2 in [max(0,-d),min(1,1-d)]; at RR=r, p1=r*p2 and
//! p2 in [0,min(1,1/r)]. Tail mass is maximized over the WHOLE interval.
//! Risk score/constraint algorithms belong to freq_risk, never duplicated here.
const std = @import("std");
const math = @import("../functions.zig");
const risk = @import("freq_risk.zig");
const exact = @import("freq_exact.zig");
const dist = @import("freq_exact_distribution.zig");
const polynomial = @import("freq_exact_polynomial.zig");
pub const Error = exact.Error;
pub const Family = enum { difference, relative_risk };
pub const Method = enum { noscore, score, score2 };
pub const Side = enum { left, right, two_sided };
pub const Bounds = struct { lower: f64, upper: f64 };
pub const TailResult = union(enum) { complete: Bounds, exhausted };
pub const LimitsResult = union(enum) { complete: exact.Interval, exhausted };
pub const Options = struct {
    /// Caller workspace for allocation-backed large tails. Small tails keep
    /// the original stack path. A missing allocator returns exhausted when
    /// dynamic workspace is required; no implicit global allocator is used.
    allocator: ?std.mem.Allocator = null,
    /// Expose endpoints whose numerical inversions have already completed
    /// if the caller's deadline interrupts the remaining search.
    completed_limits: ?*risk.Interval = null,
    budget: dist.Budget = .{},
    /// Absolute bound width for the nuisance supremum (floating roundoff aside).
    tolerance: f64 = 1e-10,
    /// Endpoint bracket width: absolute RD, log(RR) (approximately relative RR).
    /// This is separate from the nuisance p-value bound above. Used by the
    /// certified inversion; riskLimitsSas uses the documented profile p-stop.
    inversion_tolerance: f64 = 1e-11,
};
// Storage threshold only, never an upper limit on a supplied-workspace domain.
const stack_degree = 128;
const Work = struct {
    options: Options,
    used: u64 = 0,
    stopped: bool = false,
    fn tick(self: *Work) bool {
        if (self.stopped) return false;
        if (self.used == self.options.budget.max_tables or self.options.budget.stopped()) {
            self.stopped = true;
            return false;
        }
        self.used += 1;
        return true;
    }
};
fn choose(n: u32, k: u32) f64 {
    return @exp(math.lgammaOf(@as(f64, @floatFromInt(n)) + 1) - math.lgammaOf(@as(f64, @floatFromInt(k)) + 1) - math.lgammaOf(@as(f64, @floatFromInt(n - k)) + 1));
}
fn canonical(table: risk.Table2x2, column: risk.Column) Error![4]u32 {
    try table.validate();
    var c: [4]u32 = undefined;
    for (table.cells, 0..) |v, i| c[i] = try exact.integerCount(v);
    if (column == .second) {
        std.mem.swap(u32, &c[0], &c[1]);
        std.mem.swap(u32, &c[2], &c[3]);
    }
    return c;
}
fn tableOf(c: [4]u32) risk.Table2x2 {
    var v: [4]f64 = undefined;
    for (c, 0..) |x, i| v[i] = @floatFromInt(x);
    return .{ .cells = v };
}
fn statistic(c: [4]u32, family: Family, method: Method, null_value: f64) Error!f64 {
    const table = tableOf(c);
    if (method == .noscore) {
        const s = table.samples(.first);
        return switch (family) {
            .difference => s[0].proportion() - s[1].proportion(),
            // Documented modified RR (Gart-Nam), not raw division by zero.
            .relative_risk => (s[0].success + 0.5) / (s[0].total + 0.5) / ((s[1].success + 0.5) / (s[1].total + 0.5)),
        };
    }
    const value = switch (family) {
        .difference => try risk.differenceScore(table, .first, null_value, false),
        // z_r(x,y) = -z_(1/r)(y,x). Evaluate with r <= 1 so
        // the shared variance does not form r*r above floatMax. Overflow
        // previously turned finite ordered scores into zero (or NaN), making
        // a rare tail contain every table. Keep the shared constrained fit.
        .relative_risk => if (null_value > 1)
            -(try risk.relativeRiskScore(tableOf(.{ c[2], c[3], c[0], c[1] }), .first, 1 / null_value, false))
        else
            try risk.relativeRiskScore(table, .first, null_value, false),
    };
    if (std.math.isNan(value)) return error.ExecError;
    return value; // Infinite scores are valid at degenerate candidate tables.
}
fn selected(value: f64, observed: f64, side: Side) bool {
    const x = if (side == .two_sided) @abs(value) else value;
    const y = if (side == .two_sided) @abs(observed) else observed;
    if (x == y) return true;
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return if (side == .left) x < y else x > y;
    const eps = 64 * std.math.floatEps(f64) * @max(1, @max(@abs(x), @abs(y)));
    return if (side == .left) x < y + eps else x > y - eps;
}
/// Multiply a degree-d Bernstein polynomial by affine p(t) with endpoints l,h.
fn multiply(coeff: *[stack_degree + 1]f64, d: usize, l: f64, h: f64) void {
    var j = d + 2;
    while (j > 0) {
        j -= 1;
        const den: @TypeOf(l) = @floatFromInt(d + 1);
        coeff[j] = (if (j <= d) @as(f64, @floatFromInt(d + 1 - j)) / den * coeff[j] * l else 0) + (if (j > 0) @as(f64, @floatFromInt(j)) / den * coeff[j - 1] * h else 0);
    }
}
/// Bernstein convex hull bounds certify the maximum; recursive subdivision
/// narrows the upper/lower gap instead of assuming a coarse grid found it.
fn maximize(coeff: []const f64, best: *f64, work: *Work, depth: usize) f64 {
    if (!work.tick()) return 1;
    var upper: f64 = 0;
    for (coeff) |v| upper = @max(upper, v);
    best.* = @max(best.*, @max(coeff[0], coeff[coeff.len - 1]));
    if (upper - best.* <= work.options.tolerance) return upper;
    if (depth == 64) {
        work.stopped = true;
        return 1;
    }
    var temp: [stack_degree + 1]f64 = undefined;
    var left: [stack_degree + 1]f64 = undefined;
    var right: [stack_degree + 1]f64 = undefined;
    @memcpy(temp[0..coeff.len], coeff);
    left[0] = temp[0];
    right[coeff.len - 1] = temp[coeff.len - 1];
    for (1..coeff.len) |level| {
        for (0..coeff.len - level) |j| temp[j] = (temp[j] + temp[j + 1]) / 2;
        left[level] = temp[0];
        right[coeff.len - level - 1] = temp[coeff.len - level - 1];
    }
    best.* = @max(best.*, left[coeff.len - 1]);
    const lu = maximize(left[0..coeff.len], best, work, depth + 1);
    if (work.stopped) return 1;
    const ru = maximize(right[0..coeff.len], best, work, depth + 1);
    return @max(lu, ru);
}

fn tail(c: [4]u32, family: Family, method: Method, null_value: f64, side: Side, work: *Work) Error!TailResult {
    const n1wide = @as(u64, c[0]) + c[1];
    const n2wide = @as(u64, c[2]) + c[3];
    if (n1wide > std.math.maxInt(u32) or n2wide > std.math.maxInt(u32)) return .exhausted;
    const n1: u32 = @intCast(n1wide);
    const n2: u32 = @intCast(n2wide);
    if (n1 == 0 or n2 == 0) return error.ExecError;
    if (!std.math.isFinite(null_value) or (family == .difference and @abs(null_value) > 1) or (family == .relative_risk and null_value <= 0)) return error.ExecError;
    if (!std.math.isFinite(work.options.tolerance) or work.options.tolerance <= 0 or work.options.tolerance >= 1) return error.ExecError;
    if (family == .relative_risk and method == .score2 and side == .two_sided) {
        // At (0,n2) and r <= 1/(2*n1), p2=1 puts all mass on (x,n2).
        // For each such x the constrained MLE is min(1,(x+n2)/(r*N))=1.
        // The score denominator is common, and |x/n1-r| >= r for every x.
        // Interchanging rows gives the reciprocal plateau at the other corner.
        // The wider product compares a binary64 null with the rational cutoff
        // exactly, including immediately adjacent representable null values.
        const zero_first = c[0] == 0 and c[3] == 0 and @as(f128, null_value) * @as(f128, @floatFromInt(2 * n1wide)) <= 1;
        const zero_second = c[1] == 0 and c[2] == 0 and null_value >= @as(f64, @floatFromInt(2 * n2wide));
        if (zero_first or zero_second) {
            if (!work.tick()) return .exhausted;
            return .{ .complete = pointBounds(1) };
        }
    }
    const p2lo = if (family == .difference) @max(0, -null_value) else 0;
    const p2hi = if (family == .difference) @min(1, 1 - null_value) else @min(1, 1 / null_value);
    const p1lo = if (family == .difference) p2lo + null_value else p2lo * null_value;
    const p1hi = if (family == .difference) p2hi + null_value else p2hi * null_value;
    const observed = try statistic(c, family, method, null_value);
    if (n1wide + n2wide > stack_degree) return allocatedTail(n1, n2, family, method, null_value, side, observed, .{ .lower = p1lo, .upper = p1hi }, .{ .lower = p2lo, .upper = p2hi }, null, work);
    const n = n1 + n2;
    var sum: [stack_degree + 1]f64 = @splat(0);
    for (0..n1 + 1) |xx| for (0..n2 + 1) |yy| {
        if (!work.tick()) return .exhausted;
        const x: u32 = @intCast(xx);
        const y: u32 = @intCast(yy);
        const s = try statistic(.{ x, n1 - x, y, n2 - y }, family, method, null_value);
        if (!selected(s, observed, side)) continue;
        var coeff: [stack_degree + 1]f64 = @splat(0);
        coeff[0] = choose(n1, x) * choose(n2, y);
        var d: usize = 0;
        for (0..n1) |i| {
            multiply(&coeff, d, if (i < x) p1lo else 1 - p1lo, if (i < x) p1hi else 1 - p1hi);
            d += 1;
        }
        for (0..n2) |i| {
            multiply(&coeff, d, if (i < y) p2lo else 1 - p2lo, if (i < y) p2hi else 1 - p2hi);
            d += 1;
        }
        for (0..n + 1) |i| sum[i] += coeff[i];
    };
    var best: f64 = 0;
    const upper = maximize(sum[0 .. n + 1], &best, work, 0);
    if (work.stopped) return .exhausted;
    return .{ .complete = .{ .lower = @min(1, best), .upper = @min(1, upper) } };
}
fn polynomialTick(context: ?*anyopaque) bool {
    const work: *Work = @ptrCast(@alignCast(context.?));
    return work.tick();
}
const GridValue = struct { index: u32, reported: f64 };

fn allocatedTail(n1: u32, n2: u32, family: Family, method: Method, null_value: f64, side: Side, observed: f64, p1: polynomial.Range, p2: polynomial.Range, grid: ?*GridValue, work: *Work) Error!TailResult {
    const rows = std.math.add(usize, n1, 1) catch return .exhausted;
    const cols = std.math.add(usize, n2, 1) catch return .exhausted;
    const count = std.math.mul(usize, rows, cols) catch return .exhausted;
    _ = std.math.add(usize, n1, n2) catch return .exhausted;
    // Enumeration itself costs at least one tick per table. Refuse hopeless
    // work before allocation, while retaining the shared deadline everywhere.
    if (count > work.options.budget.max_tables - work.used or !work.tick()) return .exhausted;
    const a = work.options.allocator orelse return .exhausted;
    const events = try a.alloc(bool, count);
    defer a.free(events);
    for (0..rows) |xx| for (0..cols) |yy| {
        if (!work.tick()) return .exhausted;
        const x: u32 = @intCast(xx);
        const y: u32 = @intCast(yy);
        const value = try statistic(.{ x, n1 - x, y, n2 - y }, family, method, null_value);
        events[xx * cols + yy] = selected(value, observed, side);
    };
    const control = polynomial.Control{ .context = work, .consume = polynomialTick };
    const built = try polynomial.build(a, n1, n2, events, p1, p2, control);
    if (built == .exhausted) return .exhausted;
    defer built.complete.deinit(a);
    const maximum = if (grid != null)
        try polynomial.maximizeGrid(a, built.complete.coefficients, nuisance_divisions, control)
    else
        try polynomial.maximize(a, built.complete.coefficients, work.options.tolerance, control);
    if (maximum == .exhausted) return .exhausted;
    const bounds = maximum.complete;
    if (grid) |point| {
        point.index = bounds.grid_index.?;
        point.reported = bounds.lower;
        if (point.index > 1 and point.index < nuisance_divisions - 1 and 1 - bounds.lower != 1) {
            const q = @as(f64, @floatFromInt(point.index)) / @as(f64, @floatFromInt(nuisance_divisions));
            point.reported = (try barnardComplement(a, n1, n2, events, q, bounds.lower, work)) orelse return .exhausted;
        }
    }
    return .{ .complete = .{ .lower = bounds.lower, .upper = bounds.upper } };
}

/// M9's raw small-tail probabilities are multiples of the spacing produced
/// by subtracting the probability of the omitted tables from one.
/// Retain the separately computed stable probability for a subtraction
/// outside the supplied numerical tolerance or outside the probability domain.
fn barnardComplement(a: std.mem.Allocator, n1: u32, n2: u32, events: []const bool, q: f64, stable: f64, work: *Work) Error!?f64 {
    const columns = try a.alloc(f64, @as(usize, n2) + 1);
    defer a.free(columns);
    for (columns, 0..) |*mass, y| {
        if (!work.tick()) return null;
        mass.* = @exp(exact.binomialLogPoint(@intCast(y), n2, q));
    }
    var inside: f64 = 0;
    for (0..@as(usize, n1) + 1) |x| {
        if (!work.tick()) return null;
        const row = @exp(exact.binomialLogPoint(@intCast(x), n1, q));
        for (columns, 0..) |mass, y| {
            if (!events[x * columns.len + y]) inside += row * mass;
        }
    }
    const p = 1 - inside;
    return if (p > 0 and p <= 1 and @abs(p - stable) <= work.options.tolerance) p else stable;
}

pub fn riskTail(table: risk.Table2x2, column: risk.Column, family: Family, method: Method, null_value: f64, side: Side, options: Options) Error!TailResult {
    var work = Work{ .options = options };
    return tail(try canonical(table, column), family, method, null_value, side, &work);
}

const nuisance_divisions: u32 = 10_000;
const BarnardProfile = struct { one: f64, two: f64 };
pub const BarnardTails = union(enum) {
    complete: struct { one: Bounds, two: Bounds, profile: ?BarnardProfile = null },
    exhausted,
};

/// Under H0 the Barnard score is the signed square root of Pearson X².
/// |Z|=sqrt(N) only under perfect association: a directional tail contains
/// the observed extreme allocation, and the absolute tail also its reverse.
pub fn barnardTails(table: risk.Table2x2, side: Side, options: Options) Error!BarnardTails {
    const c = try canonical(table, .first);
    var work = Work{ .options = options };
    if (!std.math.isFinite(options.tolerance) or options.tolerance <= 0 or options.tolerance >= 1) return error.ExecError;
    if (@as(u64, c[0]) + c[1] > std.math.maxInt(u32) or @as(u64, c[2]) + c[3] > std.math.maxInt(u32)) return .exhausted;
    // With equal observed risks, every absolute score is at least zero.
    // Either inclusive directional tail has mass one at nuisance p=0.
    // Integer cross-products distinguish equality from a one-count
    // determinant that rounds away when subtracting two row proportions.
    if (@as(u64, c[0]) * c[3] == @as(u64, c[1]) * c[2]) {
        if (!work.tick()) return .exhausted;
        return .{ .complete = .{ .one = pointBounds(1), .two = pointBounds(1) } };
    }
    const negative = c[0] == 0 and c[3] == 0;
    const positive = c[1] == 0 and c[2] == 0;
    if ((negative and side == .left) or (positive and side == .right)) {
        const n1 = if (negative) c[1] else c[0];
        const n2 = if (negative) c[2] else c[3];
        return opposingBarnard(@min(n1, n2), @max(n1, n2), &work);
    }
    const one = try tail(c, .difference, .score, 0, side, &work);
    if (one == .exhausted) return .exhausted;
    work = .{ .options = options };
    const two = try tail(c, .difference, .score, 0, .two_sided, &work);
    if (two == .exhausted) return .exhausted;
    var result = BarnardTails{ .complete = .{ .one = one.complete, .two = two.complete } };
    if (options.allocator == null) return result;
    const n1 = c[0] + c[1];
    const n2 = c[2] + c[3];
    const observed = try statistic(c, .difference, .score, 0);
    const range = polynomial.Range{ .lower = 0, .upper = 1 };
    var reported: BarnardProfile = undefined;
    for ([_]Side{ side, .two_sided }, [_]*f64{ &reported.one, &reported.two }) |tail_side, p| {
        work = .{ .options = options };
        var point: GridValue = undefined;
        const fit = try allocatedTail(n1, n2, .difference, .score, 0, tail_side, observed, range, range, &point, &work);
        if (fit == .exhausted) {
            if (options.budget.stopped()) return .exhausted;
            return result;
        }
        const index = point.index;
        // The first/last interior grid point cannot bracket a peak with
        // positive mass on both sides. Observed native searches can skip
        // one of the two reflected maxima in that unresolved boundary cell.
        if (index == 1 or index == nuisance_divisions - 1 or
            1 - fit.complete.lower == 1) return result;
        p.* = point.reported;
    }
    result.complete.profile = reported;
    return result;
}

fn pointBounds(value: f64) Bounds {
    return .{ .lower = value, .upper = value };
}

// Independent M9 raw cells recover the nuisance grid at increments of
// .0001. At a resolved peak, unimodality restricts the discrete maximum
// to the two enclosing grid points. When the peak falls inside the very
// first cell, M9 can miss an entire reflected tail; retain the continuous
// bounds for this numerically unresolved profile.
fn opposingBarnardProfile(a: f64, b: f64, two_mode: f64) ?BarnardProfile {
    const divisions: f64 = @floatFromInt(nuisance_divisions);
    const one_mode = a / (a + b);
    if (one_mode * divisions < 1) return null;
    var profile: BarnardProfile = undefined;
    for ([_]f64{ one_mode, two_mode }, [_]*f64{ &profile.one, &profile.two }, [_]bool{ false, true }) |mode, field, two| {
        const lo = @floor(mode * divisions);
        var high: f64 = 0;
        for ([_]f64{ lo, @min(divisions / 2, lo + 1) }) |index| {
            const q = index / divisions;
            if (q == 0.5) {
                const exponent = if (two) 1 - (a + b) else -(a + b);
                high = @max(high, @exp2(exponent));
                continue;
            }
            const log_q = @log(q);
            const log_complement = std.math.log1p(-q);
            const log_mass = a * log_q + b * log_complement;
            const log_ratio = (b - a) * (log_q - log_complement);
            high = @max(high, @exp(if (two) log_mass + std.math.log1p(@exp(log_ratio)) else log_mass));
        }
        field.* = high;
    }
    return profile;
}

/// For ordered row totals a<=b, g(q)=q^a(1-q)^b has its peak at a/N.
/// Its reflected sum g(q)+g(1-q) is symmetric. With u=log((1-q)/q)/2
/// its log derivative is d*tanh(d*u)-N*tanh(u), d=b-a. On u>0 with
/// d>1, tanh(d*u)/tanh(u) decreases from d to 1, since its log derivative
/// is 2*d/sinh(2*d*u)-2/sinh(2*u)<0. The maximum is at 1/2 when d²<=N.
/// Otherwise there is one maximum on [a/N,1/2] and its reflection.
fn opposingBarnard(small: u32, large: u32, work: *Work) BarnardTails {
    if (!work.tick()) return .exhausted;
    const a: f64 = @floatFromInt(small);
    const b: f64 = @floatFromInt(large);
    const n = a + b;
    const one = pointBounds(@exp(a * logRowShare(a, b) + b * logRowShare(b, a)));
    const d: u64 = large - small;
    if (d * d <= @as(u64, small) + large) {
        return .{ .complete = .{ .one = one, .two = pointBounds(@exp2(1 - n)), .profile = opposingBarnardProfile(a, b, 0.5) } };
    }

    var lo = a / n;
    var hi: f64 = 0.5;
    while (true) {
        if (!work.tick()) return .exhausted;
        const q = (lo + hi) / 2;
        if (q == lo or q == hi) break;
        // The sign of the derivative after factoring out g(q)/(q*(1-q)).
        const ratio = std.math.pow(f64, q / (1 - q), @floatFromInt(d));
        const derivative = @mulAdd(f64, -n, q, a) + ratio * @mulAdd(f64, -n, q, b);
        if (derivative > 0) lo = q else hi = q;
    }
    // Within the final bracket g(q) decreases and g(1-q) increases. Form
    // the sum in log space in case each probability underflows separately.
    const large_log = a * @log(lo) + b * std.math.log1p(-lo);
    const small_log = b * @log(hi) + a * std.math.log1p(-hi);
    const upper = @max(one.upper, @exp(large_log + std.math.log1p(@exp(small_log - large_log))));
    const at_hi = a * @log(hi) + b * std.math.log1p(-hi);
    const lower = @exp(at_hi + std.math.log1p(@exp(small_log - at_hi)));
    return .{ .complete = .{ .one = one, .two = .{ .lower = @max(one.lower, @min(lower, upper)), .upper = upper }, .profile = opposingBarnardProfile(a, b, (lo + hi) / 2) } };
}

/// At (0,n2), both NOSCORE and the directional score have a singleton left
/// tail. For the score, write the constrained null as p=a+b*q, b>0,
/// V=p*(1-p), W=q*(1-q), and t=x-n1*p. At an interior MLE, y-n2*q
/// equals -b*t*W/V. For t<0, the count bounds therefore give
/// -t <= min(n1*p, n2*V/(b*q)). The squared score is
/// t^2*(1/(n1*V) + b^2*W/(n2*V^2)).
/// Put A=n1*b/n2. On the first branch, A*q<=1-p and the derivative of
/// the squared bound has the sign of (1-p)*(1+A*(1-2*q))+2*A*b*q*(1-q),
/// which is positive. On the second branch, A*q>=1-p and the derivative
/// has the sign of -1+(1-2*p)/A-2*V/(A*b*q), which is negative.
/// Their meeting point, clipped to the legal nuisance range, is the fit
/// at (0,n2). At a clipped boundary the remaining count is monotone.
/// Absolute score ordering in SCORE2 also includes the opposite tail.
///
/// For the risk difference write A=1-p1 and B=p2, so A+B=1-d. The interior
/// maximum of A^n1 B^n2 assigns A:B=n1:n2. When the larger factor reaches 1 the
/// probability becomes (-d)^min(n1,n2). Invert the two regions at alpha/2.
fn opposingDifferenceUpper(n1: f64, n2: f64, alpha: f64) f64 {
    const small = @min(n1, n2);
    const large = @max(n1, n2);
    const log_target = @log(alpha) - @log(@as(f64, 2));
    const boundary = small * @log(small / large);
    if (log_target >= boundary) return -@exp(log_target / small);
    const n = small + large;
    const p = small / n;
    const entropy = -p * @log(p) - (large / n) * std.math.log1p(-p);
    return -std.math.expm1(log_target / n + entropy);
}

/// For (0,n2), the RR tail is (1-r)^n1 up to r=n2/N; above that point
/// it is (n1/N)^n1 * (n2/(N*r))^n2. Return the log upper root so row
/// reversal can yield a representable lower endpoint even for large ratios.
fn opposingRatioLogUpper(n1: f64, n2: f64, alpha: f64) f64 {
    const log_target = @log(alpha) - @log(@as(f64, 2));
    const at_transition = n1 * logRowShare(n1, n2);
    if (log_target >= at_transition) return @log(-std.math.expm1(log_target / n1));
    return logRowShare(n2, n1) + (at_transition - log_target) / n2;
}

fn logRowShare(row: f64, other: f64) f64 {
    const total = row + other;
    return if (row >= other) std.math.log1p(-other / total) else @log(row / total);
}

/// Equal-tailed NOSCORE/SCORE inversion or absolute-score SCORE2 inversion.
/// Returns bracketed numerical endpoints; no fixed-margin shortcut is valid.
pub fn riskLimits(table: risk.Table2x2, column: risk.Column, family: Family, method: Method, alpha: f64, options: Options) Error!LimitsResult {
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1 or !std.math.isFinite(options.inversion_tolerance) or options.inversion_tolerance <= 0 or options.inversion_tolerance >= 1) return error.ExecError;
    const c = try canonical(table, column);
    if (@as(u64, c[0]) + c[1] > std.math.maxInt(u32) or @as(u64, c[2]) + c[3] > std.math.maxInt(u32)) return .exhausted;
    const s = tableOf(c).samples(.first);
    const estimate = if (family == .difference) s[0].proportion() - s[1].proportion() else if (c[2] == 0) std.math.inf(f64) else s[0].proportion() / s[1].proportion();
    const opposing = (c[0] == 0 and c[3] == 0) or (c[1] == 0 and c[2] == 0);
    if (opposing and (method == .score or (method == .noscore and family == .difference))) {
        if (!std.math.isFinite(options.tolerance) or options.tolerance <= 0 or options.tolerance >= 1) return error.ExecError;
        if (options.budget.max_tables == 0 or options.budget.stopped()) return .exhausted;
        if (family == .difference) {
            const upper = opposingDifferenceUpper(s[0].total, s[1].total, alpha);
            return .{ .complete = if (c[0] == 0) .{ .lower = -1, .upper = upper } else .{ .lower = -upper, .upper = 1 } };
        }
        const zero_first = c[0] == 0;
        const zero_row: usize = @intFromBool(!zero_first);
        const log_upper = opposingRatioLogUpper(s[zero_row].total, s[1 - zero_row].total, alpha);
        const finite = @exp(if (zero_first) log_upper else -log_upper);
        if (finite == 0 or !std.math.isFinite(finite)) return .exhausted;
        return .{ .complete = if (zero_first) .{ .lower = 0, .upper = finite } else .{ .lower = finite, .upper = std.math.inf(f64) } };
    }
    const target = if (method == .score2) alpha else alpha / 2;
    var out = exact.Interval{ .lower = if (family == .difference) -1 else 0, .upper = if (family == .difference) 1 else std.math.inf(f64) };
    var work = Work{ .options = options };
    for ([_]bool{ true, false }) |lower| {
        // RR structural endpoints; all-zero event rows require their own
        // modified-statistic inversion and are not silently declared [0,inf].
        if (family == .relative_risk and ((lower and c[0] == 0) or (!lower and c[2] == 0))) continue;
        if (family == .difference and ((lower and estimate == -1) or (!lower and estimate == 1))) continue;
        var center: f64 = if (family == .difference) estimate else if (estimate == 0) -2 else if (std.math.isInf(estimate)) 2 else @log(estimate);
        if (family == .relative_risk and (estimate == 0 or std.math.isInf(estimate))) {
            // Establish an accepted finite inner bracket near a structural MLE.
            // log(floatMin) is not a useful center and can exhaust the bracket
            // before testing any finite upper bound for an observed zero risk.
            while (true) {
                const inner = try tail(c, family, method, @exp(center), if (method == .score2) .two_sided else if (lower) .right else .left, &work);
                if (inner == .exhausted) return .exhausted;
                if (inner.complete.lower > target) break;
                center *= 2;
                if (@abs(center) > 700) return .exhausted;
            }
        }
        var width: f64 = 2;
        var lo: f64 = if (lower) (if (family == .difference) -1 else center - width) else center;
        var hi: f64 = if (lower) center else if (family == .difference) 1 else center + width;
        if (family == .relative_risk and method == .noscore) {
            // The nuisance endpoint p2=0 makes both successes zero. If that
            // table is in the ordered tail, its probability is 1 for EVERY RR:
            // this proves the structural 0/infinity endpoint, without treating
            // an arbitrary finite log-RR cutoff as infinity.
            const zero_score = try statistic(.{ 0, @intFromFloat(s[0].total), 0, @intFromFloat(s[1].total) }, family, method, 1);
            const observed_score = try statistic(c, family, method, 1);
            if (selected(zero_score, observed_score, if (lower) .right else .left)) continue;
        }
        while (true) {
            const boundary = if (lower) lo else hi;
            if (family == .relative_risk and @abs(boundary) > 700) return .exhausted;
            const boundary_result = try tail(c, family, method, if (family == .difference) boundary else @exp(boundary), if (method == .score2) .two_sided else if (lower) .right else .left, &work);
            if (boundary_result == .exhausted) return .exhausted;
            if (boundary_result.complete.upper <= target) break;
            if (family == .difference) break;
            width *= 2;
            if (lower) lo = center - width else hi = center + width;
        }
        for (0..100) |_| {
            if (hi - lo <= options.inversion_tolerance) break;
            const mid = (lo + hi) / 2;
            const null_value = if (family == .difference) mid else @exp(mid);
            const result = try tail(c, family, method, null_value, if (method == .score2) .two_sided else if (lower) .right else .left, &work);
            if (result == .exhausted) return .exhausted;
            // Use the certified upper bound, conservatively including nuisance
            // uncertainty. p-error is at most Options.tolerance.
            const accepted = result.complete.upper > target;
            if (accepted == lower) hi = mid else lo = mid;
        }
        if (hi - lo > options.inversion_tolerance) return .exhausted;
        const endpoint = if (family == .difference) (lo + hi) / 2 else @exp((lo + hi) / 2);
        if (lower) out.lower = endpoint else out.upper = endpoint;
        if (options.completed_limits) |completed| {
            if (lower) completed.lower = endpoint else completed.upper = endpoint;
        }
    }
    return .{ .complete = out };
}

/// SAS-compatible OUTER search profile for RR NOSCORE. The certified
/// mathematical inversion above remains the independent reference and default.
/// Other families/methods retain that implementation unchanged.
///
/// Verified with transition-b0..b3.sas under /tmp/opensas-stat-batch2/EXACT-RR-support:
/// start at modified RR, seed with UNMODIFIED Wald upper, double its distance
/// from the modified point, then stop at the first rejected-tail bisection point
/// within 1e-6 in probability. A crossed Wald bracket returns the modified point.
/// Lower limits use the reciprocal, row-reversed search. No fitted endpoints.
///
/// This reproduces observed outer-search behavior, NOT all undocumented SAS
/// boundary behavior: certified nuisance maximization is still used. In
/// particular structural limits remain exactly 0/infinity, and sparse boundary
/// cases can differ from SAS beyond listing precision (documented in tests).
/// The crossed-bracket fallback does not retain the certified interval's
/// nominal-coverage guarantee (see the complete sample-space counterexample).
/// Do not claim full NOSCORE SAS parity from this profile alone.
pub fn riskLimitsSas(table: risk.Table2x2, column: risk.Column, family: Family, method: Method, alpha: f64, options: Options) Error!LimitsResult {
    if (family != .relative_risk or method != .noscore) return riskLimits(table, column, family, method, alpha, options);
    if (!std.math.isFinite(alpha) or alpha <= 0 or alpha >= 1 or
        !std.math.isFinite(options.tolerance) or options.tolerance <= 0 or options.tolerance >= 1 or
        !std.math.isFinite(options.inversion_tolerance) or options.inversion_tolerance <= 0 or options.inversion_tolerance >= 1) return error.ExecError;
    const c = try canonical(table, column);
    if (@as(u64, c[0]) + c[1] > std.math.maxInt(u32) or @as(u64, c[2]) + c[3] > std.math.maxInt(u32)) return .exhausted;
    var work = Work{ .options = options };
    if (!work.tick()) return .exhausted;
    // SAS suppresses the exact output object for a constant response column.
    // Keep the mathematical reference interval for finite-n coverage callers;
    // public table eligibility remains the public adapter's responsibility.
    if ((c[0] == 0 and c[2] == 0) or (c[1] == 0 and c[3] == 0)) {
        var remaining = options;
        remaining.budget.max_tables -= work.used;
        return riskLimits(table, column, family, method, alpha, remaining);
    }
    // A SAS stopping rule in p must not be satisfied merely because a loose
    // nuisance bound straddles it. Refinement never loosens the caller's bound.
    work.options.tolerance = @min(options.tolerance, 1e-12);
    const upper = try sasNoscoreUpper(c, alpha, &work);
    if (upper == null) return .exhausted;
    if (options.completed_limits) |completed| {
        if (std.math.isFinite(upper.?)) completed.upper = upper.?;
    }
    const reciprocal = try sasNoscoreUpper(.{ c[2], c[3], c[0], c[1] }, alpha, &work);
    if (reciprocal == null) return .exhausted;
    return .{ .complete = .{ .lower = 1 / reciprocal.?, .upper = upper.? } };
}

/// At fixed row totals the modified RR increases strictly in first-row
/// successes and decreases strictly in second-row successes. At its minimum,
/// the left tail contains just the observed (0, n2) allocation. Its probability
/// is (1-r*q)^n1 * q^n2, maximized at q=min(1, n2/(r*(n1+n2))).
fn noscoreUpperTail(c: [4]u32, r: f64, work: *Work) Error!TailResult {
    if (c[0] != 0 or c[3] != 0) return tail(c, .relative_risk, .noscore, r, .left, work);
    if (!work.tick()) return .exhausted;
    const n1: f64 = @floatFromInt(c[1]);
    const n2: f64 = @floatFromInt(c[2]);
    const n = n1 + n2;
    const share = n2 / n;
    const log_mass = if (r <= share) n1 * std.math.log1p(-r) else blk: {
        const q = share / r;
        // Avoid subtracting nearly equal values before multiplying their
        // logarithms by a potentially large row total.
        const log_failure = logRowShare(n1, n2);
        const log_success = if (q > 0.5) std.math.log1p(@mulAdd(f64, -r, n, n2) / (r * n)) else @log(q);
        break :blk n1 * log_failure + n2 * log_success;
    };
    const p = @exp(log_mass);
    return .{ .complete = .{ .lower = p, .upper = p } };
}

/// Null is a numerical/resource stop, never an approximate partial result.
fn sasNoscoreUpper(c: [4]u32, alpha: f64, work: *Work) Error!?f64 {
    if (!work.tick()) return null;
    const n1: f64 = @floatFromInt(@as(u64, c[0]) + c[1]);
    const n2: f64 = @floatFromInt(@as(u64, c[2]) + c[3]);
    if (c[2] == 0) return std.math.inf(f64);
    const point = try statistic(c, .relative_risk, .noscore, 1);
    const ordinary = try risk.ratio(tableOf(c), .first, .relative_risk, alpha, .wald, false);
    // Zero numerator: ordinary Wald is undefined. Bounded seed-comparison
    // probes distinguish twice the modified point from modified-Wald limits.
    const initial = ordinary.limits.upper orelse 2 * point;
    // The order matters: SAS's crossed-bracket fallback can occur even when
    // the documented zero-event tail proves an unbounded side.
    if (initial <= point) return point;
    const zero = try statistic(.{ 0, @intFromFloat(n1), 0, @intFromFloat(n2) }, .relative_risk, .noscore, 1);
    if (selected(zero, point, .left)) return std.math.inf(f64);
    var lo = point;
    var hi = initial;
    const target = alpha / 2;
    while (true) {
        if (!std.math.isFinite(hi)) return null;
        const bound = try noscoreUpperTail(c, hi, work);
        if (bound == .exhausted) return null;
        if (bound.complete.upper <= target) break;
        const next = point + 2 * (hi - point);
        if (next <= hi) return null;
        hi = next;
    }
    for (0..256) |_| {
        const mid = lo + (hi - lo) / 2;
        if (mid == lo or mid == hi) return null;
        const value = try noscoreUpperTail(c, mid, work);
        if (value == .exhausted) return null;
        // One-sided residual: an equally close accepted point is not returned.
        if (value.complete.upper <= target and target - value.complete.lower <= 1e-6) return mid;
        if (value.complete.upper > target) lo = mid else hi = mid;
    }
    return null;
}

// SAS generators.sas [0,3;2,1], Barnard two=.2188/one=.1094 vs
// Fisher=.4000. Exact tail polynomial is u^2(6-10u), u=p(1-p), maximized
// at p=.5: 7/32. This checks the generator AND nuisance supremum.
test "unconditional Barnard supremum is not Fisher conditioning" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 0, 3, 2, 1 } };
    const two = (try riskTail(table, .first, .difference, .score, 0, .two_sided, .{})).complete;
    try t.expect(two.lower <= 0.21875 + 1e-12 and two.upper >= 0.21875 - 1e-12);
    try t.expect(two.upper - two.lower <= 1e-10);
    const one = (try riskTail(table, .first, .difference, .score, 0, .left, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.109375), one.upper, 1e-10);
    try t.expect((try riskTail(table, .first, .difference, .score, 0, .left, .{ .budget = .{ .max_tables = 1 } })) == .exhausted);
}

test "risk interval method oracle and column orientation" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 3, 3, 1 } };
    const ci = (try riskLimits(table, .first, .difference, .noscore, 0.05, .{})).complete;
    const reverse = (try riskLimits(table, .second, .difference, .noscore, 0.05, .{})).complete;
    try t.expectApproxEqAbs(-ci.upper, reverse.lower, 1e-8);
    try t.expectApproxEqAbs(-ci.lower, reverse.upper, 1e-8);
    try t.expectApproxEqAbs(@as(f64, -0.9363), ci.lower, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 0.3017), ci.upper, 0.00005);
    const methods = [_]Method{ .noscore, .score, .score2 };
    const rd_lower = [_]f64{ -0.9363, -0.9363, -0.9072 };
    const rd_upper = [_]f64{ 0.3017, 0.3017, 0.2500 };
    for (methods, rd_lower, rd_upper) |method, lower, upper| {
        const rd = (try riskLimits(table, .first, .difference, method, 0.05, .{})).complete;
        try t.expectApproxEqAbs(lower, rd.lower, 0.00005);
        try t.expectApproxEqAbs(upper, rd.upper, 0.00005);
    }
    const rr_lower = [_]f64{ 0, 0.0118, 0.0238 };
    // Independently maximize the explicit 25-table polynomial. SAS prints
    // 12.8095; its tail at that rounded value is .02499938057535682.
    // The exact root is 12.809175283792893; public SAS parity is pending,
    // not hidden by widening the four-decimal oracle tolerance.
    const rr_upper = [_]f64{ 12.809175283792893, 1.7874, 1.6859 };
    for (methods, rr_lower, rr_upper) |method, lower, upper| {
        const rr = (try riskLimits(table, .first, .relative_risk, method, 0.05, .{})).complete;
        try t.expectApproxEqAbs(lower, rr.lower, 0.00005);
        try t.expectApproxEqAbs(upper, rr.upper, if (method == .noscore) @as(f64, 5e-8) else 0.00005);
    }
}

// This tests numerical inversion accuracy, not agreement with SAS's coarser
// internal search. Independent direct 25-table polynomial root below; the SAS
// BEST32 oracle remains 12.8094895576158 and is tracked separately.
test "RR NOSCORE inversion accuracy separates endpoint and nuisance tolerances" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 3, 3, 1 } };
    const precise = (try riskLimits(table, .first, .relative_risk, .noscore, 0.05, .{ .tolerance = 1e-13, .inversion_tolerance = 1e-13, .budget = .{ .max_tables = 5000000 } })).complete;
    try t.expectApproxEqAbs(@as(f64, 12.809175283792893), precise.upper, 1e-9);
    try t.expectEqual(@as(f64, 0), precise.lower);
    const inside = (try riskTail(table, .first, .relative_risk, .noscore, precise.upper * (1 - 1e-7), .left, .{ .tolerance = 1e-13 })).complete;
    const outside = (try riskTail(table, .first, .relative_risk, .noscore, precise.upper * (1 + 1e-7), .left, .{ .tolerance = 1e-13 })).complete;
    try t.expect(inside.lower > 0.025 and outside.upper < 0.025);
    const reverse = (try riskLimits(.{ .cells = .{ 3, 1, 1, 3 } }, .first, .relative_risk, .noscore, 0.05, .{ .tolerance = 1e-13, .inversion_tolerance = 1e-13 })).complete;
    try t.expectApproxEqRel(1 / precise.upper, reverse.lower, 1e-9);
    try t.expect(std.math.isInf(reverse.upper));
}

test "unconditional zero and infinite observed risks retain finite opposite bounds" {
    const t = std.testing;
    for ([_]Method{ .noscore, .score, .score2 }) |method| {
        const zero = (try riskLimits(.{ .cells = .{ 0, 4, 2, 2 } }, .first, .relative_risk, method, 0.05, .{})).complete;
        const infinite = (try riskLimits(.{ .cells = .{ 2, 2, 0, 4 } }, .first, .relative_risk, method, 0.05, .{})).complete;
        try t.expectEqual(@as(f64, 0), zero.lower);
        try t.expect(std.math.isFinite(zero.upper) and zero.upper > 0);
        try t.expect(std.math.isInf(infinite.upper));
        try t.expectApproxEqRel(1 / zero.upper, infinite.lower, 1e-7);
    }
}

test "unconditional small-table interval coverage includes boundary outcomes" {
    const t = std.testing;
    for ([_]Family{ .difference, .relative_risk }) |family| for ([_]Method{ .noscore, .score, .score2 }) |method| {
        var intervals: [9]exact.Interval = undefined;
        for (0..3) |x| for (0..3) |y| {
            intervals[x * 3 + y] = (try riskLimits(.{ .cells = .{ @floatFromInt(x), @floatFromInt(2 - x), @floatFromInt(y), @floatFromInt(2 - y) } }, .first, family, method, 0.05, .{})).complete;
        };
        for ([_]f64{ 0.05, 0.2, 0.5, 0.8, 0.95 }) |p1| for ([_]f64{ 0.05, 0.2, 0.5, 0.8, 0.95 }) |p2| {
            const truth = if (family == .difference) p1 - p2 else p1 / p2;
            const pmf1 = [_]f64{ (1 - p1) * (1 - p1), 2 * p1 * (1 - p1), p1 * p1 };
            const pmf2 = [_]f64{ (1 - p2) * (1 - p2), 2 * p2 * (1 - p2), p2 * p2 };
            var coverage: f64 = 0;
            for (0..3) |x| for (0..3) |y| {
                const ci = intervals[x * 3 + y];
                if (truth >= ci.lower - 1e-10 and truth <= ci.upper + 1e-10) coverage += pmf1[x] * pmf2[y];
            };
            try t.expect(coverage >= 0.95 - 1e-10);
        };
    };
}

// Unequal row totals and high ALPHA stress different test-ordering breakpoints.
// Probability weights below are independent explicit Bin(2,p1)*Bin(3,p2)
// formulas, not the engine's Bernstein polynomial or score implementation.
test "unconditional unequal-row coverage across confidence levels" {
    const t = std.testing;
    for ([_]f64{ 0.05, 0.2, 0.8 }) |alpha| for ([_]Family{ .difference, .relative_risk }) |family| for ([_]Method{ .noscore, .score, .score2 }) |method| {
        var intervals: [12]exact.Interval = undefined;
        for (0..3) |x| for (0..4) |y| {
            const result = try riskLimits(.{ .cells = .{ @floatFromInt(x), @floatFromInt(2 - x), @floatFromInt(y), @floatFromInt(3 - y) } }, .first, family, method, alpha, .{});
            try t.expect(result == .complete);
            intervals[x * 4 + y] = result.complete;
        };
        for ([_]f64{ 0.1, 0.35, 0.65, 0.9 }) |p1| for ([_]f64{ 0.1, 0.35, 0.65, 0.9 }) |p2| {
            const truth = if (family == .difference) p1 - p2 else p1 / p2;
            const pmf1 = [_]f64{ (1 - p1) * (1 - p1), 2 * p1 * (1 - p1), p1 * p1 };
            const pmf2 = [_]f64{ (1 - p2) * (1 - p2) * (1 - p2), 3 * p2 * (1 - p2) * (1 - p2), 3 * p2 * p2 * (1 - p2), p2 * p2 * p2 };
            var coverage: f64 = 0;
            for (0..3) |x| for (0..4) |y| {
                const ci = intervals[x * 4 + y];
                if (truth >= ci.lower - 1e-10 and truth <= ci.upper + 1e-10) coverage += pmf1[x] * pmf2[y];
            };
            try t.expect(coverage >= 1 - alpha - 1e-10);
        };
    };
}

// Independent rational polynomial/Sturm oracle:
// python3 /tmp/opensas-stat-batch2/FEAT-freq-exact/rr-noscore-sturm.py
// Root bracket width1.22e-20, all nuisance stationary points isolated to1e-25.
// Isolated real SAS gives upper=.84 at alpha=.95 and .99 (zero errors/warnings),
// so this is a documented unresolved behavioral difference, not a relaxed SAS
// tolerance. At .84 the documented tail supremum is .5547206220161103>.475.
test "RR NOSCORE high alpha follows independently inverted unconditional tail" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 1, 2, 1 } };
    const options = Options{ .tolerance = 1e-13, .inversion_tolerance = 1e-13 };
    const ci = (try riskLimits(table, .first, .relative_risk, .noscore, 0.95, options)).complete;
    try t.expectEqual(@as(f64, 0), ci.lower);
    try t.expectApproxEqAbs(@as(f64, 0.9884657555036446), ci.upper, 1e-10);
    const at_sas = (try riskTail(table, .first, .relative_risk, .noscore, 0.84, .left, options)).complete;
    try t.expectApproxEqAbs(@as(f64, 0.5547206220161103), at_sas.lower, 1e-12);
    try t.expect(at_sas.lower > 0.475);
}

// Support evidence lives only in /tmp/opensas-stat-batch2/EXACT-RR-support/.
// Command: /Users/thomas/sas/bin/sasrun .../transition-b0.sas -f text
// -o .../transition-b0.txt -l .../transition-b0.log (likewise b1..b3).
// ODS nValue1 BEST32 and the plain listing independently identify column1.
// Near-crossing runtime stops are excluded, never treated as numerical endpoints.
test "SAS RR NOSCORE outer profile predicts transitions and held-out reversals" {
    const t = std.testing;
    const Case = struct { cells: [4]f64, alpha: f64, upper: f64 };
    const cases = [_]Case{
        .{ .cells = .{ 1, 3, 3, 1 }, .alpha = 0.05, .upper = 12.8094895576158 },
        .{ .cells = .{ 1, 1, 2, 1 }, .alpha = 0.05, .upper = 17.7808683506476 },
        .{ .cells = .{ 1, 1, 2, 1 }, .alpha = 0.8, .upper = 1.1675528861718 },
        .{ .cells = .{ 1, 1, 2, 1 }, .alpha = 0.8796092006578684, .upper = 1.06625389901566 },
        .{ .cells = .{ 1, 1, 2, 1 }, .alpha = 0.8906092006578684, .upper = 0.84 },
        .{ .cells = .{ 1, 1, 2, 1 }, .alpha = 0.95, .upper = 0.84 },
        .{ .cells = .{ 1, 2, 3, 2 }, .alpha = 0.05, .upper = 20.5983265675433 },
        .{ .cells = .{ 1, 2, 3, 2 }, .alpha = 0.8196173209341815, .upper = 0.86181651050978 },
        .{ .cells = .{ 1, 2, 3, 2 }, .alpha = 0.8306173209341815, .upper = 0.673469387755102 },
        .{ .cells = .{ 2, 2, 4, 1 }, .alpha = 0.05, .upper = 15.9881522579346 },
        .{ .cells = .{ 2, 2, 4, 1 }, .alpha = 0.8697142456361451, .upper = 0.7520951445411 },
        .{ .cells = .{ 2, 2, 4, 1 }, .alpha = 0.8807142456361451, .upper = 0.6790123456790124 },
        // Held out when the initialization/stopping hypothesis was specified:
        .{ .cells = .{ 2, 3, 3, 1 }, .alpha = 0.05, .upper = 10.7188445173933 },
        .{ .cells = .{ 2, 3, 3, 1 }, .alpha = 0.8, .upper = 0.74112782324656 },
        .{ .cells = .{ 2, 3, 3, 1 }, .alpha = 0.8725554785429677, .upper = 0.69031739711824 },
        .{ .cells = .{ 2, 3, 3, 1 }, .alpha = 0.8835554785429677, .upper = 0.5844155844155844 },
    };
    for (cases) |c| {
        const result = try riskLimitsSas(.{ .cells = c.cells }, .first, .relative_risk, .noscore, c.alpha, .{});
        try t.expect(result == .complete);
        try t.expectApproxEqAbs(c.upper, result.complete.upper, 1e-10);
        const reversed = [4]f64{ c.cells[2], c.cells[3], c.cells[0], c.cells[1] };
        const reverse = (try riskLimitsSas(.{ .cells = reversed }, .first, .relative_risk, .noscore, c.alpha, .{})).complete;
        try t.expectApproxEqAbs(1 / c.upper, reverse.lower, 1e-10);
        const columns = [4]f64{ c.cells[1], c.cells[0], c.cells[3], c.cells[2] };
        const column2 = (try riskLimitsSas(.{ .cells = columns }, .second, .relative_risk, .noscore, c.alpha, .{})).complete;
        try t.expectEqual(result.complete.upper, column2.upper);
    }
    // The certified root proof must remain a different result, not be replaced
    // or weakened to accommodate a SAS runtime initialization rule.
    const certified = (try riskLimits(.{ .cells = .{ 1, 1, 2, 1 } }, .first, .relative_risk, .noscore, 0.95, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 0.9884657555036446), certified.upper, 1e-9);
}

test "NOSCORE opposing outcomes have a single-allocation tail on either side of the nuisance maximum" {
    const t = std.testing;
    for (1..6) |i| for (1..6) |j| {
        const cells = [4]u32{ 0, @intCast(i), @intCast(j), 0 };
        for ([_]f64{ 0.125, 0.5, 0.75, 1, 3, 12 }) |r| {
            var work = Work{ .options = .{} };
            const direct = (try noscoreUpperTail(cells, r, &work)).complete;
            const reference = (try riskTail(tableOf(cells), .first, .relative_risk, .noscore, r, .left, .{ .tolerance = 1e-13 })).complete;
            try t.expect(direct.lower >= reference.lower - 3e-14 and direct.upper <= reference.upper + 3e-14);
        }
    };
    // At r=1 either orientation has maximum (1/(N+1))*(N/(N+1))^N.
    // An 85-digit evaluation with N=4e9 distinguishes cancellation of 1-q.
    for ([_][4]u32{ .{ 0, 1, 4_000_000_000, 0 }, .{ 0, 4_000_000_000, 1, 0 } }) |cells| {
        var work = Work{ .options = .{} };
        const mass = (try noscoreUpperTail(cells, 1, &work)).complete.lower;
        try t.expectApproxEqRel(@as(f64, 9.19698602813643478639499e-11), mass, 1e-14);
    }
    // Four million candidate tables exceed the enumeration budget. The finite
    // endpoint lies in the q=1 regime, where (1-r)^2000=alpha/2.
    const table = risk.Table2x2{ .cells = .{ 0, 2000, 2000, 0 } };
    const upper = -std.math.expm1(@log(@as(f64, 0.025)) / 2000);
    const options = Options{ .budget = .{ .max_tables = 100 } };
    const first = (try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.05, options)).complete;
    const second = (try riskLimitsSas(table, .second, .relative_risk, .noscore, 0.05, options)).complete;
    try t.expectEqual(@as(f64, 0), first.lower);
    try t.expectApproxEqAbs(upper, first.upper, 3e-8);
    try t.expectEqual(1 / first.upper, second.lower);
    try t.expectEqual(std.math.inf(f64), second.upper);
    var stopped = Work{ .options = .{ .budget = .{ .max_tables = 0 } } };
    try t.expect((try noscoreUpperTail(.{ 0, 2000, 2000, 0 }, 1, &stopped)) == .exhausted);
}

test "NOSCORE boundary risk differences invert the constrained maximum for both response columns" {
    const t = std.testing;
    for (1..6) |i| for (1..6) |j| {
        const c = [4]u32{ 0, @intCast(i), @intCast(j), 0 };
        for ([_]f64{ 0.01, 0.1, 0.48, 0.95 }) |alpha| {
            const first = (try riskLimits(tableOf(c), .first, .difference, .noscore, alpha, .{})).complete;
            const second = (try riskLimits(tableOf(c), .second, .difference, .noscore, alpha, .{})).complete;
            try t.expectEqual(@as(f64, -1), first.lower);
            try t.expectEqual(@as(f64, 1), second.upper);
            try t.expectEqual(-first.upper, second.lower);
            const bounds = (try riskTail(tableOf(c), .first, .difference, .noscore, first.upper, .left, .{ .tolerance = 1e-13 })).complete;
            try t.expect(bounds.lower <= alpha / 2 + 2e-14 and bounds.upper >= alpha / 2 - 2e-14);
        }
    };
    const table = risk.Table2x2{ .cells = .{ 0, 2_000_000_000, 2_000_000_000, 0 } };
    const interval = (try riskLimitsSas(table, .first, .difference, .noscore, 0.05, .{ .budget = .{ .max_tables = 1 } })).complete;
    const reference = -1 - 2 * std.math.expm1(@log(@as(f64, 0.025)) / 4_000_000_000);
    try t.expectApproxEqAbs(reference, interval.upper, 5e-16);
    try t.expect((try riskLimitsSas(table, .first, .difference, .noscore, 0.05, .{ .budget = .{ .max_tables = 0 } })) == .exhausted);
}

test "Barnard opposing limits match elementary polynomial extrema and exhaustive unsigned score tails" {
    const t = std.testing;
    for (1..9) |i| for (1..10) |j| {
        const corner = tableOf(.{ 0, @intCast(i), @intCast(j), 0 });
        const actual = (try barnardTails(corner, .left, .{})).complete;
        const one = (try riskTail(corner, .first, .difference, .score, 0, .left, .{ .tolerance = 1e-13 })).complete;
        const two = (try riskTail(corner, .first, .difference, .score, 0, .two_sided, .{ .tolerance = 1e-13 })).complete;
        try t.expect(actual.one.lower >= one.lower - 2e-14 and actual.one.upper <= one.upper + 2e-14);
        try t.expect(actual.two.lower >= two.lower - 2e-14 and actual.two.upper <= two.upper + 2e-14);
    };
    // At (1,3) the central mode is flat; at (1,4), putting s=q*(1-q)
    // gives s*(1-3*s) with a maximum of 1/12 at either off-center root.
    inline for (.{ .{ 3, 0.125 }, .{ 4, 1.0 / 12.0 } }) |pair| {
        const x = (try barnardTails(tableOf(.{ 0, 1, pair[0], 0 }), .left, .{})).complete;
        try t.expectApproxEqAbs(@as(f64, pair[1]), x.two.upper, 1e-15);
    }
    const rare = tableOf(.{ 4_000_000_000, 0, 0, 1 });
    const x = (try barnardTails(rare, .right, .{})).complete;
    try t.expectApproxEqRel(@as(f64, 9.19698602813643478639499e-11), x.two.upper, 2e-14);
    try t.expect(x.profile == null);
    try t.expect((try barnardTails(rare, .right, .{ .budget = .{ .max_tables = 1 } })) == .exhausted);
    const subnormal = (try barnardTails(tableOf(.{ 0, 537, 538, 0 }), .left, .{})).complete;
    try t.expectEqual(std.math.floatTrueMin(f64), subnormal.two.upper);
    try t.expectEqual(std.math.floatTrueMin(f64), subnormal.profile.?.two);
}

test "M9 Barnard profiles on ordinary tables retain the separate continuous bound" {
    const t = std.testing;
    const cases = [_]struct { c: [4]u32, one: f64, two: f64 }{
        .{ .c = .{ 1, 3, 4, 3 }, .one = 0.21658011851414, .two = 0.41796875 },
        .{ .c = .{ 1, 1, 5, 2 }, .one = 0.5073778468994397, .two = 0.8384121939729534 },
        .{ .c = .{ 0, 2, 9, 1 }, .one = 0.01545338756716, .two = 0.01546160858111 },
    };
    for (cases) |v| {
        const r = (try barnardTails(tableOf(v.c), .left, .{ .allocator = t.allocator })).complete;
        try t.expectApproxEqAbs(v.one, r.profile.?.one, 2e-14);
        try t.expectApproxEqAbs(v.two, r.profile.?.two, 2e-14);
        try t.expect(r.one.upper >= r.profile.?.one - 1e-14);
        try t.expect(r.two.upper >= r.profile.?.two - 1e-14);
    }
}

test "directional SCORE orders fully opposing outcomes strictly first and inverts their probability" {
    const t = std.testing;
    for (1..6) |n1| for (1..6) |n2| {
        const corner = [4]u32{ 0, @intCast(n1), @intCast(n2), 0 };
        for ([_]Family{ .relative_risk, .difference }) |family| {
            const nulls: []const f64 = if (family == .relative_risk) &.{ 0.001, 0.25, 1, 2, 64 } else &.{ -0.95, -0.5, 0, 0.375, 0.9 };
            for (nulls) |null_value| {
                const observed = try statistic(corner, family, .score, null_value);
                for (0..n1 + 1) |x| for (0..n2 + 1) |y| {
                    if (x == 0 and y == n2) continue;
                    const other = [4]u32{ @intCast(x), @intCast(n1 - x), @intCast(y), @intCast(n2 - y) };
                    try t.expect(try statistic(other, family, .score, null_value) > observed);
                };
            }
            for ([_]f64{ 0.05, 0.55, 0.95 }) |alpha| {
                const ci = (try riskLimits(tableOf(corner), .first, family, .score, alpha, .{})).complete;
                const bounds = (try riskTail(tableOf(corner), .first, family, .score, ci.upper, .left, .{ .tolerance = 1e-13 })).complete;
                try t.expect(bounds.lower <= alpha / 2 + 3e-14 and bounds.upper >= alpha / 2 - 3e-14);
            }
        }
    };
    // For row sizes 1 and 1 at alpha=.05 the stationary point is interior.
    const paired = risk.Table2x2{ .cells = .{ 0, 1, 1, 0 } };
    const low = (try riskLimitsSas(paired, .second, .relative_risk, .score, 0.05, .{})).complete.lower;
    try t.expectApproxEqAbs(@as(f64, 0.1), low, 2e-16);
    // Reversing the unequal rows gives a different clipped root. A single
    // budget unit suffices even though the support has 1,204,301 cells.
    const wide = risk.Table2x2{ .cells = .{ 0, 300, 4000, 0 } };
    const options = Options{ .budget = .{ .max_tables = 1 } };
    const upper = (try riskLimitsSas(wide, .first, .relative_risk, .score, 0.05, options)).complete.upper;
    const lower = (try riskLimitsSas(wide, .second, .relative_risk, .score, 0.05, options)).complete.lower;
    try t.expectApproxEqRel(@as(f64, 0.012220974694293554), upper, 1e-14);
    try t.expectApproxEqRel(@as(f64, 1084.8401995789214), lower, 1e-14);
}

test "SAS outer profile preserves budgets and default methods" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 1, 1, 2, 1 } };
    try t.expect((try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.95, .{ .budget = .{ .max_tables = 1 } })) == .exhausted);
    try t.expect((try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.05, .{ .budget = .{ .max_tables = 10 } })) == .exhausted);
    const Stop = struct {
        fn expired(_: ?*const anyopaque) bool {
            return true;
        }
    };
    try t.expect((try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.95, .{ .budget = .{ .expired = Stop.expired } })) == .exhausted);
    try t.expect((try riskLimitsSas(.{ .cells = .{ 0, 2, 0, 3 } }, .first, .relative_risk, .noscore, 0.95, .{ .budget = .{ .expired = Stop.expired } })) == .exhausted);
    try t.expectError(error.ExecError, riskLimitsSas(table, .first, .relative_risk, .noscore, 0, .{}));
    try t.expectError(error.ExecError, riskLimitsSas(table, .first, .relative_risk, .noscore, 0.05, .{ .tolerance = 0 }));
    const reference = (try riskLimits(table, .first, .relative_risk, .score, 0.05, .{})).complete;
    const profile = (try riskLimitsSas(table, .first, .relative_risk, .score, 0.05, .{})).complete;
    try t.expectEqual(reference, profile);
}

test "SAS outer profile coverage is distinguished from the certified guarantee" {
    const t = std.testing;
    var saw_counterexample = false;
    for ([_]f64{ 0.05, 0.2, 0.8, 0.95 }) |alpha| {
        var intervals: [12]exact.Interval = undefined;
        var certified: [12]exact.Interval = undefined;
        for (0..3) |x| for (0..4) |y| {
            const table = risk.Table2x2{ .cells = .{ @floatFromInt(x), @floatFromInt(2 - x), @floatFromInt(y), @floatFromInt(3 - y) } };
            const result = try riskLimitsSas(table, .first, .relative_risk, .noscore, alpha, .{});
            try t.expect(result == .complete);
            intervals[x * 4 + y] = result.complete;
            certified[x * 4 + y] = (try riskLimits(table, .first, .relative_risk, .noscore, alpha, .{})).complete;
        };
        for ([_]f64{ 0.01, 0.1, 0.35, 0.65, 0.9, 0.99 }) |p1| for ([_]f64{ 0.01, 0.1, 0.35, 0.65, 0.9, 0.99 }) |p2| {
            const truth = p1 / p2;
            // Independent Bin(2,p1)*Bin(3,p2), not Bernstein engine weights.
            const p = [_]f64{ (1 - p1) * (1 - p1), 2 * p1 * (1 - p1), p1 * p1 };
            const q = [_]f64{ (1 - p2) * (1 - p2) * (1 - p2), 3 * p2 * (1 - p2) * (1 - p2), 3 * p2 * p2 * (1 - p2), p2 * p2 * p2 };
            var coverage: f64 = 0;
            var mathematical_coverage: f64 = 0;
            for (0..3) |x| for (0..4) |y| {
                const ci = intervals[x * 4 + y];
                if (truth >= ci.lower - 1e-10 and truth <= ci.upper + 1e-10) coverage += p[x] * q[y];
                const reference = certified[x * 4 + y];
                if (truth >= reference.lower - 1e-10 and truth <= reference.upper + 1e-10) mathematical_coverage += p[x] * q[y];
            };
            // Never relax the exact mathematical coverage test to fit SAS.
            try t.expect(mathematical_coverage >= 1 - alpha - 1e-10);
            if (alpha <= 0.8) try t.expect(coverage >= 1 - alpha - 1e-10);
            if (alpha == 0.95 and p1 == 0.9 and p2 == 0.65) {
                saw_counterexample = true;
                try t.expectApproxEqAbs(@as(f64, 0.00042875), coverage, 1e-12);
                try t.expectApproxEqAbs(@as(f64, 0.4027625), mathematical_coverage, 1e-12);
                try t.expect(coverage < 1 - alpha);
            }
        };
    }
    try t.expect(saw_counterexample);
}

test "SAS NOSCORE sparse-boundary residual is not hidden by outer-profile tolerance" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 0, 2, 3, 0 } };
    // small-b2.sas / boundary-columns.sas: SAS .31043853759765 at alpha.95.
    // Only (x=0,y=3) belongs to this left tail. For r<.6 its maximum is at
    // p2=1, so the exact tail is (1-r)^2 and root is 1-sqrt(.475).
    const sas_upper: f64 = 0.31043853759765;
    const at_sas = (try riskTail(table, .first, .relative_risk, .noscore, sas_upper, .left, .{ .tolerance = 1e-13 })).complete;
    try t.expectApproxEqAbs((1 - sas_upper) * (1 - sas_upper), at_sas.lower, 1e-12);
    try t.expect(at_sas.lower > 0.475 + 0.0004);
    const certified = (try riskLimits(table, .first, .relative_risk, .noscore, 0.95, .{})).complete;
    try t.expectApproxEqAbs(1 - @sqrt(@as(f64, 0.475)), certified.upper, 1e-9);
    const profile = (try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.95, .{})).complete;
    try t.expect(@abs(profile.upper - sas_upper) > 0.0003);
    try t.expect((try riskTail(table, .first, .relative_risk, .noscore, profile.upper, .left, .{})).complete.upper <= 0.475);
}

test "SAS outer profile zero-event initialization ordinary-alpha oracle" {
    // small-b0.sas: all12 row-fixed outcomes, separate uniquely named ODS
    // datasets; constant-response suppression is not recycled stale evidence.
    const t = std.testing;
    for ([_][4]f64{ .{ 0, 2, 1, 2 }, .{ 0, 2, 2, 1 }, .{ 0, 2, 3, 0 }, .{ 0, 4, 2, 2 } }, [_]f64{ 17.4425781249999, 2.557529296875, 1.1139892578125, 2.05859375 }) |cells, upper| {
        const result = (try riskLimitsSas(.{ .cells = cells }, .first, .relative_risk, .noscore, 0.05, .{})).complete;
        try t.expectEqual(@as(f64, 0), result.lower);
        try t.expectApproxEqAbs(upper, result.upper, 1e-10);
    }
    // boundary-columns.sas: explicit COLUMN=2 maps [1,1;2,1] to[1,1;1,2].
    const column2 = (try riskLimitsSas(.{ .cells = .{ 1, 1, 2, 1 } }, .second, .relative_risk, .noscore, 0.95, .{})).complete;
    try t.expectApproxEqAbs(@as(f64, 1.4), column2.lower, 1e-12);
    try t.expect(std.math.isInf(column2.upper));
}

test "RR boundary tail targets distinguish directional methods and SCORE2" {
    // boundary-methods-b0/b1.sas: fresh ODS objects plus plain listing;
    // zero numerator/denominator and reversals. No OR-style alpha switch for
    // directional RR tests. 1e-6 is the independently observed SAS p-search
    // resolution, not a relaxation of certified-tail accuracy (1e-13 here).
    const t = std.testing;
    const Directional = struct { cells: [4]f64, method: Method, side: Side, endpoint: f64 };
    const cases = [_]Directional{
        .{ .cells = .{ 0, 2, 3, 0 }, .method = .noscore, .side = .left, .endpoint = 1.1139892578125 },
        .{ .cells = .{ 0, 2, 3, 0 }, .method = .score, .side = .left, .endpoint = 1.1139892578125 },
        .{ .cells = .{ 3, 0, 0, 2 }, .method = .noscore, .side = .right, .endpoint = 0.89767472440772 },
        .{ .cells = .{ 3, 0, 0, 2 }, .method = .score, .side = .right, .endpoint = 0.89767456054687 },
        .{ .cells = .{ 0, 4, 2, 2 }, .method = .noscore, .side = .left, .endpoint = 2.05859375 },
        .{ .cells = .{ 0, 4, 2, 2 }, .method = .score, .side = .left, .endpoint = 2.31240234375 },
        .{ .cells = .{ 2, 2, 0, 4 }, .method = .noscore, .side = .right, .endpoint = 0.48576850094876 },
        .{ .cells = .{ 2, 2, 0, 4 }, .method = .score, .side = .right, .endpoint = 0.43245315551757 },
    };
    for (cases) |c| {
        const tail_at = (try riskTail(.{ .cells = c.cells }, .first, .relative_risk, c.method, c.endpoint, c.side, .{ .tolerance = 1e-13 })).complete;
        try t.expect(tail_at.upper - tail_at.lower <= 1e-13);
        try t.expectApproxEqAbs(@as(f64, 0.025), tail_at.lower, 1e-6);
        try t.expect(@abs(tail_at.lower - 0.05) > 0.02);
    }
    // SCORE2 endpoints can lie at reference-ordering jumps instead of roots.
    // At alpha .05 the tail jumps from .0625 to .03456: crosses alpha, but
    // both sides remain above alpha/2. Reversal exchanges the neighborhood.
    for ([_]bool{ false, true }) |reverse| {
        const table = risk.Table2x2{ .cells = if (reverse) .{ 3, 0, 0, 2 } else .{ 0, 2, 3, 0 } };
        const endpoint: f64 = if (reverse) 0.99999994039535 else 1.0000003814697;
        const inside = (try riskTail(table, .first, .relative_risk, .score2, endpoint * (if (reverse) @as(f64, 1.00001) else 0.99999), .two_sided, .{ .tolerance = 1e-13 })).complete;
        const outside = (try riskTail(table, .first, .relative_risk, .score2, endpoint * (if (reverse) @as(f64, 0.99999) else 1.00001), .two_sided, .{ .tolerance = 1e-13 })).complete;
        try t.expect(inside.lower > 0.05 and outside.upper < 0.05);
        try t.expect(outside.lower > 0.025);
    }
    // High-alpha boundary discrepancy is not fixed by using alpha instead of
    // alpha/2, and appears in SCORE as well as NOSCORE for this zero numerator.
    for ([_]Method{ .noscore, .score }) |method| {
        const tail_at = (try riskTail(.{ .cells = .{ 0, 2, 3, 0 } }, .first, .relative_risk, method, 0.31043853759765, .left, .{ .tolerance = 1e-13 })).complete;
        try t.expectApproxEqAbs(@as(f64, 0.47549501043047), tail_at.lower, 1e-12);
        try t.expect(tail_at.lower > 0.475 + 0.0004 and tail_at.upper < 0.95 - 0.4);
    }
}

test "RR boundary regimes cannot be reproduced by one clipped nuisance endpoint" {
    // nuisance-regime-0..5.sas: six opposing-zero-cell shapes, seven alpha
    // levels, all three methods; all126 outputs returned without timeout.
    // nuisance-repeat.sas independently repeats both discriminating cases3x.
    // For these directional tails the sole table is(0,n2), so the polynomial
    // is (1-r*p2)^n1*p2^n2. The maximum is atp2=1 for r<n2/(n1+n2).
    const t = std.testing;
    const Case = struct { cells: [4]f64, r: f64, alpha: f64 };
    const cases = [_]Case{
        .{ .cells = .{ 0, 2, 3, 0 }, .r = 0.499728775024, .alpha = 0.5 },
        .{ .cells = .{ 0, 2, 3, 0 }, .r = 0.31043853759765, .alpha = 0.95 },
        .{ .cells = .{ 0, 3, 2, 0 }, .r = 0.218744822911, .alpha = 0.95 },
        .{ .cells = .{ 0, 2, 5, 0 }, .r = 0.31875, .alpha = 0.94 },
    };
    for (cases) |c| for ([_]Method{ .noscore, .score }) |method| {
        const tail_at = (try riskTail(.{ .cells = c.cells }, .first, .relative_risk, method, c.r, .left, .{ .tolerance = 1e-13 })).complete;
        const closed = std.math.pow(f64, 1 - c.r, c.cells[1]);
        try t.expectApproxEqAbs(closed, tail_at.lower, 1e-12);
        try t.expect(@abs(tail_at.lower - c.alpha / 2) > 0.0002);
    };
    // A fixed .9995 matches neither all regimes nor the observed stopping
    // window. Atalpha.8 the true boundary matches the SAS endpoint, while
    // .9995 undershoots the target by more than .0003.
    const r: f64 = 0.36754455566406;
    const at_boundary = (1 - r) * (1 - r);
    const clipped = std.math.pow(f64, 1 - r * 0.9995, 2) * std.math.pow(f64, 0.9995, 3);
    try t.expectApproxEqAbs(@as(f64, 0.4), at_boundary, 1e-6);
    try t.expect(clipped < 0.4 - 0.0003);
    // Conversely, at [0,2;5,0],alpha.94 even the true maximum is .4641015625
    // < .47. No legal nuisance point can hit the target there, so an open-
    // interval maximizer alone cannot explain the returned SAS endpoint.
    const below = (try riskTail(.{ .cells = .{ 0, 2, 5, 0 } }, .first, .relative_risk, .noscore, 0.31875, .left, .{ .tolerance = 1e-13 })).complete;
    try t.expectApproxEqAbs(@as(f64, 0.4641015625), below.upper, 1e-12);
    try t.expect(below.upper < 0.47 - 0.005);
}

test "high-alpha SCORE2 boundary discrepancies retain the exact acceptance certificate" {
    // nuisance-regime-2/3/4.sas atalpha.99: SAS bounds below1/(2*n1).
    // With p2=1 and r<1/(2*n1), every possible row1 count has absolute score
    // >= the observed zero-success score, so the two-sided tail is exactly1.
    // These are genuine unresolved SCORE2 runtime differences, not alpha
    // splitting or a permissible1e-6 endpoint tolerance. Keep them in scope.
    const t = std.testing;
    for ([_][4]f64{ .{ 0, 2, 5, 0 }, .{ 0, 3, 5, 0 }, .{ 0, 4, 3, 0 } }, [_]f64{ 0.249913109375, 0.1666030883789, 0.11966864267985 }) |cells, sas_upper| {
        const table = risk.Table2x2{ .cells = cells };
        const probability = (try riskTail(table, .first, .relative_risk, .score2, sas_upper, .two_sided, .{ .tolerance = 1e-13 })).complete;
        try t.expectEqual(@as(f64, 1), probability.lower);
        try t.expectEqual(@as(f64, 1), probability.upper);
        const reference = (try riskLimits(table, .first, .relative_risk, .score2, 0.99, .{})).complete;
        try t.expectApproxEqAbs(1 / (2 * cells[1]), reference.upper, 1e-9);
        try t.expect(reference.upper > sas_upper + 0.00005);
        const profile = (try riskLimitsSas(table, .first, .relative_risk, .score2, 0.99, .{})).complete;
        try t.expectEqual(reference, profile); // no unverified SCORE2 emulation
    }
}

test "allocator-backed unconditional path admits n1=1 n2=129" {
    const t = std.testing;
    const table = risk.Table2x2{ .cells = .{ 0, 1, 129, 0 } };
    const options = Options{ .allocator = t.allocator };
    const value = try riskTail(table, .first, .relative_risk, .noscore, 1, .left, options);
    try t.expect(value == .complete);
    const closed = (1.0 / 130.0) * std.math.pow(f64, 129.0 / 130.0, 129);
    try t.expect(value.complete.lower <= closed + 1e-14 and value.complete.upper >= closed - 1e-14);
    try t.expect(value.complete.upper - value.complete.lower <= options.tolerance);
    const rr = (try riskLimits(table, .first, .relative_risk, .noscore, 0.05, options)).complete;
    try t.expectEqual(@as(f64, 0), rr.lower);
    try t.expectApproxEqAbs(@as(f64, 0.975), rr.upper, 1e-9);
    const rd = (try riskLimits(table, .first, .difference, .noscore, 0.05, options)).complete;
    try t.expectEqual(@as(f64, -1), rd.lower);
    try t.expectApproxEqAbs(@as(f64, -0.025), rd.upper, 1e-9);
    const profile = (try riskLimitsSas(table, .first, .relative_risk, .noscore, 0.05, options)).complete;
    try t.expectApproxEqAbs(@as(f64, 0.975), profile.upper, 2e-6);
    try t.expect((try riskTail(table, .first, .relative_risk, .noscore, 1, .left, .{ .allocator = t.allocator, .budget = .{ .max_tables = 100 } })) == .exhausted);
    const Stop = struct {
        fn expired(_: ?*const anyopaque) bool {
            return true;
        }
    };
    try t.expect((try riskTail(table, .first, .relative_risk, .noscore, 1, .left, .{ .allocator = t.allocator, .budget = .{ .expired = Stop.expired } })) == .exhausted);
}
test "allocator-backed unconditional coefficients avoid combinatorial overflow" {
    const result = (try riskTail(.{ .cells = .{ 0, 600, 0, 600 } }, .first, .relative_risk, .noscore, 1, .right, .{ .allocator = std.testing.allocator })).complete;
    try std.testing.expectEqual(@as(f64, 1), result.lower);
    try std.testing.expectEqual(@as(f64, 1), result.upper);
}

test "allocator-backed unconditional construction and search share cancellation" {
    const t = std.testing;
    const Stop = struct {
        polls: usize = 0,
        after: usize,
        fn expired(raw: ?*const anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(@constCast(raw.?)));
            self.polls += 1;
            return self.polls > self.after;
        }
    };
    const table = risk.Table2x2{ .cells = .{ 0, 1, 129, 0 } };
    //260 event decisions precede helper construction; the later stop occurs
    // during subdivision. Each returns only exhausted, never partial bounds.
    for ([_]usize{ 270, 800 }) |limit| {
        var stop = Stop{ .after = limit };
        const result = try riskTail(table, .first, .relative_risk, .noscore, 1, .left, .{ .allocator = t.allocator, .budget = .{ .context = &stop, .expired = Stop.expired } });
        try t.expect(result == .exhausted);
        try t.expectEqual(limit + 1, stop.polls);
    }
    try t.expect((try riskTail(table, .first, .relative_risk, .noscore, 1, .left, .{})) == .exhausted);
    // Even a complete individual tail must not reset work in an inversion.
    try t.expect((try riskLimits(table, .first, .relative_risk, .noscore, 0.05, .{ .allocator = t.allocator, .budget = .{ .max_tables = 2500 } })) == .exhausted);
    try t.expect((try riskTail(.{ .cells = .{ 4294967295, 0, 4294967295, 0 } }, .first, .relative_risk, .noscore, 1, .left, .{ .allocator = t.allocator })) == .exhausted);
}
fn unconditionalAllocationProbe(a: std.mem.Allocator) !void {
    const result = try riskTail(.{ .cells = .{ 0, 1, 129, 0 } }, .first, .relative_risk, .noscore, 1, .left, .{ .allocator = a, .tolerance = 1e-8 });
    if (result != .complete) return error.ExecError;
}
test "allocator-backed unconditional failure paths release caller workspace" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, unconditionalAllocationProbe, .{});
}

test "dev2 exact boundary reciprocal score preserves rare tails beyond squared RR range" {
    const t = std.testing;
    const cells = [4]u32{ 1, 1, 1, 1 };
    // Same score definition, independently evaluated in the safe orientation.
    // This is an algebraic/overflow regression, not a fitted SAS endpoint.
    for ([_]f64{ 2, 1e100, 1e160, 1e200, 1e300 }) |r| {
        const score = try statistic(cells, .relative_risk, .score, r);
        const reverse = try risk.relativeRiskScore(tableOf(cells), .first, 1 / r, false);
        try t.expect(std.math.isFinite(score));
        try t.expect(score < 0);
        try t.expectApproxEqRel(-reverse, score, 2e-15);
    }
    for ([_]Method{ .score, .score2 }) |method| {
        const side: Side = if (method == .score2) .two_sided else .left;
        const value = (try riskTail(tableOf(cells), .first, .relative_risk, method, 1e200, side, .{ .tolerance = 1e-213 })).complete;
        // Any selected table has at least one row-2 success; its probability
        // is at most P(Y>=1)<=2/r, uniformly over p2 in [0,1/r].
        try t.expect(value.lower > 0);
        try t.expect(value.upper <= 2.000000000001e-200);
        const reverse = (try riskTail(tableOf(cells), .first, .relative_risk, method, 1e-200, if (method == .score2) .two_sided else .right, .{ .tolerance = 1e-213 })).complete;
        try t.expectApproxEqRel(reverse.lower, value.lower, 1e-13);
        try t.expectApproxEqRel(reverse.upper, value.upper, 1e-13);
    }
}


test "dev2 exact boundary SAS FM ordering confirms SCORE2 nuisance endpoint certificate" {
    const t = std.testing;
    // Fresh SAS 9.04.01M9P06052025 ordering.sas. Four-decimal score
    // precision only; the probability-one certificate below is exact.
    const cases = [_]struct { n1: u32, n2: u32, r: f64, scores: []const f64 }{
        .{ .n1 = 2, .n2 = 5, .r = 0.249913109375, .scores = &.{ -0.8163, 0.8169 } },
        .{ .n1 = 4, .n2 = 3, .r = 0.11966864267985, .scores = &.{ -0.7374, 0.8031, 2.3436, 3.8841 } },
    };
    for (cases) |c| {
        const observed = try statistic(.{ 0, c.n1, c.n2, 0 }, .relative_risk, .score2, c.r);
        for (0..c.n1 + 1) |i| {
            const x: u32 = @intCast(i);
            const z = try statistic(.{ x, c.n1 - x, c.n2, 0 }, .relative_risk, .score2, c.r);
            if (i < c.scores.len) try t.expectApproxEqAbs(c.scores[i], z, 0.00005);
            try t.expect(selected(z, observed, .two_sided));
        }
        const result = (try riskTail(tableOf(.{ 0, c.n1, c.n2, 0 }), .first, .relative_risk, .score2, c.r, .two_sided, .{ .tolerance = 1e-13 })).complete;
        try t.expectEqual(@as(f64, 1), result.lower);
        try t.expectEqual(@as(f64, 1), result.upper);
    }
}


test "deadline during second risk endpoint retains only the completed inversion" {
    const Stop = struct {
        fn afterEndpoint(raw: ?*const anyopaque) bool {
            const completed: *const risk.Interval = @ptrCast(@alignCast(raw.?));
            return completed.lower != null or completed.upper != null;
        }
    };
    const table = risk.Table2x2{ .cells = .{ 1, 3, 3, 1 } };
    for ([_]Family{ .difference, .relative_risk }, [_]Method{ .score2, .noscore }) |family, method| {
        const full = (try riskLimitsSas(table, .first, family, method, 0.05, .{})).complete;
        var completed: risk.Interval = .{};
        const stopped = try riskLimitsSas(table, .first, family, method, 0.05, .{
            .completed_limits = &completed,
            .budget = .{ .context = &completed, .expired = Stop.afterEndpoint },
        });
        try std.testing.expect(stopped == .exhausted);
        if (family == .difference) {
            try std.testing.expectEqual(full.lower, completed.lower.?);
            try std.testing.expect(completed.upper == null);
        } else {
            try std.testing.expectEqual(full.upper, completed.upper.?);
            try std.testing.expect(completed.lower == null);
        }
    }
}


test "Barnard equal risks have probability one across unequal row margins" {
    const t = std.testing;
    // The first two small count ratios have native M9 raw p=1 for both
    // tails. The proof also applies when enumeration exceeds its work limit.
    for ([_][4]u32{
        .{ 2, 2, 2, 2 }, .{ 2, 3, 4, 6 }, .{ 250, 750, 750, 2250 },
        .{ 400_000_000, 600_000_000, 1_200_000_000, 1_800_000_000 },
    }) |cells| {
        for ([_]Side{ .left, .right, .two_sided }) |side| {
            const result = try barnardTails(tableOf(cells), side, .{ .budget = .{ .max_tables = 1 } });
            try t.expectEqual(pointBounds(1), result.complete.one);
            try t.expectEqual(pointBounds(1), result.complete.two);
        }
    }
    const m = 800_000_000;
    for ([_][4]u32{ .{ m, m + 1, m + 1, m + 2 }, .{ m + 1, m + 2, m, m + 1 } }) |cells| {
        const table = tableOf(cells);
        const rows = table.samples(.first);
        try t.expectEqual(rows[0].proportion(), rows[1].proportion());
        try t.expect((try barnardTails(table, .left, .{ .budget = .{ .max_tables = 1 } })) == .exhausted);
    }
    const equal = tableOf(.{ 1, 1, 1, 1 });
    try t.expect((try barnardTails(equal, .left, .{ .budget = .{ .max_tables = 0 } })) == .exhausted);
    try t.expectError(error.ExecError, barnardTails(equal, .left, .{ .tolerance = 0 }));
}


test "opposing SCORE2 relative-risk plateau includes the rational cutoff in either direction" {
    const t = std.testing;
    const minimal = Options{ .budget = .{ .max_tables = 1 } };
    for ([_]u32{ 1, 2, 3, 17, 1_000_003 }) |a| {
        const b: u32 = 2_000_003;
        const fraction = 1 / @as(f64, @floatFromInt(2 * a));
        const cutoff = if (@as(f128, fraction) * @as(f128, @floatFromInt(2 * a)) > 1)
            std.math.nextAfter(f64, fraction, 0)
        else
            fraction;
        const first = tableOf(.{ 0, a, b, 0 });
        const second = tableOf(.{ b, 0, 0, a });
        try t.expectEqual(pointBounds(1), (try riskTail(first, .first, .relative_risk, .score2, cutoff, .two_sided, minimal)).complete);
        try t.expect((try riskTail(first, .first, .relative_risk, .score2, std.math.nextAfter(f64, cutoff, 1), .two_sided, minimal)) == .exhausted);
        const reciprocal: f64 = @floatFromInt(2 * a);
        try t.expectEqual(pointBounds(1), (try riskTail(second, .first, .relative_risk, .score2, reciprocal, .two_sided, minimal)).complete);
        try t.expect((try riskTail(second, .first, .relative_risk, .score2, std.math.nextAfter(f64, reciprocal, 0), .two_sided, minimal)) == .exhausted);
    }
    const table = tableOf(.{ 0, 3, 7, 0 });
    try t.expect((try riskTail(table, .first, .relative_risk, .score2, 0.1, .two_sided, .{ .budget = .{ .max_tables = 0 } })) == .exhausted);
    try t.expect((try riskTail(table, .first, .relative_risk, .score2, 0.1, .left, minimal)) == .exhausted);
}
