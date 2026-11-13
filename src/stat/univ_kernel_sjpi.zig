//! SJPI solve-the-equation core for an already assigned 201-point histogram.
//! This does NOT implement SAS UNIVARIATE's raw-sample bin assignment: its
//! half-grid rounding is still unresolved. Keep the caller's SJPI guard until
//! that separate step is verified. See docs/findings/univ-sjpi-dev2/README.md.
//! Independently implemented from the Gaussian derivative identities and the
//! retained SAS M9 oracle; no third-party implementation is incorporated.
const std = @import("std");
const diag = @import("../diag.zig");

pub const grid_points = 201;

pub const BinnedSample = struct {
    counts: [grid_points]usize,
    /// Distance between adjacent bin centers, in original measurement units.
    step: f64,
    /// ORIGINAL observations' standard deviation, with divisor n-1. The pilot
    /// instead uses the population variance of the binned observations.
    sample_stddev: f64,
    iqr: f64,
};

pub const Result = struct {
    bandwidth: f64,
    c: f64,
    selection: enum { root, maximum_fallback } = .root,
};

/// Select a normal-kernel bandwidth from caller-supplied bin counts. This API
/// deliberately makes no raw-observation nearest-bin decisions. It is not a
/// replacement for univ_kernel.fit or a claim of complete C=SJPI acceptance.
pub fn fromBins(d: *diag.Diagnostics, sample: BinnedSample) diag.Error!Result {
    if (!positiveFinite(sample.step) or !positiveFinite(sample.sample_stddev) or !positiveFinite(sample.iqr))
        return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: bin spacing, sample standard deviation and IQR must be finite and positive", .{});
    var count: usize = 0;
    for (sample.counts) |v| {
        const sum = @addWithOverflow(count, v);
        if (sum[1] != 0) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: bin count overflow", .{});
        count = sum[0];
    }
    if (count < 2) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: at least two binned observations are required", .{});
    const n: f64 = @floatFromInt(count);
    var p: [grid_points]f64 = undefined;
    var mean: f64 = 0;
    for (sample.counts, 0..) |v, i| {
        p[i] = @as(f64, @floatFromInt(v)) / n;
        mean += p[i] * @as(f64, @floatFromInt(i));
    }
    var variance: f64 = 0;
    for (p, 0..) |w, i| {
        const delta = @as(f64, @floatFromInt(i)) - mean;
        variance += w * delta * delta;
    }
    if (!positiveFinite(variance)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: binned observations have zero variance", .{});

    // Work in bin-spacing units for the derivative estimates. This avoids
    // fifth/seventh powers of the user's physical measurement scale.
    const sigma = @sqrt(variance);
    const a = pow(32 / (5 * @sqrt(@as(f64, 2))), 1.0 / 7.0) * sigma * pow(n, -1.0 / 7.0);
    const b = pow(64 / (7 * @sqrt(@as(f64, 2))), 1.0 / 9.0) * sigma * pow(n, -1.0 / 9.0);
    const ratio = derivativeFunctional(&p, a, .four) / -derivativeFunctional(&p, b, .six);
    if (!positiveFinite(ratio)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: invalid pilot derivative ratio", .{});
    const equation = Equation{ .p = &p, .n = n, .alpha = pow(6 * @sqrt(@as(f64, 2)) * ratio, 1.0 / 7.0), .step = sample.step };

    // SAS searches the largest sign-change interval on 21 logarithmic points,
    // between twice the oversmoothed bandwidth and that upper bound / 18.
    // The ORIGINAL sample SD sets this grid, not the binned population SD.
    const upper = 6 * sample.sample_stddev * pow(1 / (70 * @sqrt(std.math.pi) * n), 0.2);
    if (!positiveFinite(upper)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: invalid bandwidth search scale", .{});
    var hi = upper;
    var fhi = equation.at(hi);
    var j: usize = 20;
    while (j > 0) {
        j -= 1;
        var lo = upper / 18 * pow(18, @as(f64, @floatFromInt(j)) / 20);
        var flo = equation.at(lo);
        if (!std.math.isFinite(flo) or !std.math.isFinite(fhi))
            return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: nonfinite bandwidth equation", .{});
        if (opposite(flo, fhi)) {
            // The absolute 0.001 stopping width is in ORIGINAL data units.
            // Return the last trial, not the midpoint of the final bracket.
            for (0..256) |_| {
                const mid = lo + (hi - lo) / 2;
                const fm = equation.at(mid);
                if (!std.math.isFinite(fm)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: nonfinite bandwidth equation", .{});
                if (opposite(flo, fm)) {
                    hi = mid;
                } else {
                    lo = mid;
                    flo = fm;
                }
                if (hi - lo < 0.001) {
                    const c = mid / (sample.iqr * pow(n, -0.2));
                    if (!positiveFinite(mid) or !positiveFinite(c)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: invalid selected bandwidth", .{});
                    return .{ .bandwidth = mid, .c = c };
                }
                if (mid == lo and mid == hi) break;
            }
            return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: bandwidth bisection did not converge", .{});
        }
        hi = lo;
        fhi = flo;
    }
    // SAS M9: repeated point masses can have a root below the search minimum.
    // It warns and uses the MAXIMUM, not the nearest end or a widened search.
    // Ten FREQ samples (n=100..1,000,000) establish this fallback independently.
    const c = upper / (sample.iqr * pow(n, -0.2));
    if (!positiveFinite(c)) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: invalid maximum bandwidth", .{});
    try d.warn(0, "Algorithm for Sheather-Jones Plug In did not converge; using maximum bandwidth value.", .{});
    return .{ .bandwidth = upper, .c = c, .selection = .maximum_fallback };
}

fn pow(x: f64, y: f64) f64 {
    return std.math.pow(f64, x, y);
}

fn positiveFinite(x: f64) bool {
    return x > 0 and std.math.isFinite(x);
}

fn opposite(a: f64, b: f64) bool {
    return a == 0 or b == 0 or (a < 0) != (b < 0);
}

const Order = enum { four, six };

fn derivativeFunctional(p: *const [grid_points]f64, h: f64, order: Order) f64 {
    var sum: f64 = 0;
    for (p, 0..) |wi, i| {
        if (wi == 0) continue;
        for (p[0 .. i + 1], 0..) |wj, j| {
            if (wj == 0) continue;
            const z = @as(f64, @floatFromInt(i - j)) / h;
            // Beyond 40, even the degree-six polynomial times exp(-z²/2)
            // is below the smallest representable f64, not a density cutoff.
            if (z > 40) continue;
            const t = z * z;
            const polynomial = switch (order) {
                .four => (t - 6) * t + 3,
                .six => ((t - 15) * t + 45) * t - 15,
            };
            const symmetry: f64 = if (i == j) 1 else 2;
            sum += symmetry * wi * wj * polynomial * @exp(-t / 2) / @sqrt(2 * std.math.pi);
        }
    }
    return sum / pow(h, if (order == .four) 5 else 7);
}

const Equation = struct {
    p: *const [grid_points]f64,
    n: f64,
    alpha: f64,
    step: f64,

    fn at(self: Equation, h: f64) f64 {
        const units = h / self.step;
        const roughness = derivativeFunctional(self.p, self.alpha * pow(units, 5.0 / 7.0), .four);
        if (!positiveFinite(roughness)) return std.math.nan(f64);
        return pow(1 / (2 * @sqrt(std.math.pi) * self.n * roughness), 0.2) - units;
    }
};

// Bin indices below are explicit test INPUT, not a raw-observation assignment
// algorithm. Expected C values come from dev2-sjpi-cases.{sas,txt,log}.
fn oracleInput(x: []const f64, indices: []const usize, iqr: f64) BinnedSample {
    var counts = [_]usize{0} ** grid_points;
    for (indices) |i| counts[i] += 1;
    var mean: f64 = 0;
    for (x) |v| mean += v;
    mean /= @as(f64, @floatFromInt(x.len));
    var ss: f64 = 0;
    for (x) |v| ss += (v - mean) * (v - mean);
    return .{ .counts = counts, .step = (x[x.len - 1] - x[0]) / 200, .sample_stddev = @sqrt(ss / @as(f64, @floatFromInt(x.len - 1))), .iqr = iqr };
}

test "UNIV SJPI binned core SAS M9 n8 and original-unit stopping rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const indices = [_]usize{ 0, 14, 29, 43, 71, 100, 129, 200 };
    const x = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const result = try fromBins(&d, oracleInput(&x, &indices, 6.5));
    try std.testing.expectApproxEqAbs(@as(f64, 0.71482864776055), result.c, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0654716805931934), result.bandwidth, 1e-10);
    var transformed: [8]f64 = undefined;
    for (x, 0..) |v, i| transformed[i] = 3 * v + 17;
    const shifted = try fromBins(&d, oracleInput(&transformed, &indices, 19.5));
    try std.testing.expectApproxEqAbs(@as(f64, 0.71498707792873), shifted.c, 1e-10);
    for (x, 0..) |v, i| transformed[i] = v * 0.001;
    const tiny = try fromBins(&d, oracleInput(&transformed, &indices, 0.0065));
    try std.testing.expectApproxEqAbs(@as(f64, 0.74968328476011), tiny.c, 1e-10);
}

test "UNIV SJPI binned core SAS M9 small samples and ties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const two = try fromBins(&d, oracleInput(&.{ 0, 1 }, &.{ 0, 200 }, 1));
    try std.testing.expectApproxEqAbs(@as(f64, 0.25376288518391), two.c, 1e-10);
    const three = try fromBins(&d, oracleInput(&.{ 0, 1, 2 }, &.{ 0, 100, 200 }, 2));
    try std.testing.expectApproxEqAbs(@as(f64, 0.62449804948675), three.c, 1e-10);
    const four = try fromBins(&d, oracleInput(&.{ 0, 1, 2, 3 }, &.{ 0, 67, 133, 200 }, 2));
    try std.testing.expectApproxEqAbs(@as(f64, 0.84805432729355), four.c, 1e-10);
    const ties = try fromBins(&d, oracleInput(&.{ 0, 0, 1, 1, 2, 2, 3, 3 }, &.{ 0, 0, 67, 67, 133, 133, 200, 200 }, 2));
    try std.testing.expectApproxEqAbs(@as(f64, 0.75851233156542), ties.c, 1e-10);
}

test "UNIV SJPI binned core SAS M9 outliers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const first = try fromBins(&d, oracleInput(&.{ 0, 1, 2, 3, 4, 5, 6, 100 }, &.{ 0, 2, 4, 6, 8, 10, 12, 200 }, 4));
    try std.testing.expectApproxEqAbs(@as(f64, 2.07375048030641), first.c, 1e-10);
    const second = try fromBins(&d, oracleInput(&.{ 1, 2, 3, 4, 6, 8, 10, 150 }, &.{ 0, 1, 3, 4, 7, 9, 12, 200 }, 6.5));
    try std.testing.expectApproxEqAbs(@as(f64, 1.91304525506011), second.c, 1e-10);
}

test "UNIV SJPI binned core independent translated scaled SAS M9 heldouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    {
        // halfgrid-heldout.sas case 0: caller supplies the oracle-established bin.
        const input = oracleInput(&.{ -100.125, -99.7402, -99.1186, -98.71900000000001, -98.497, -96.9874, -95.6258, -94.205 }, &.{ 0, 13, 34, 47, 55, 106, 152, 200 }, 3.12279999999999);
        const result = try fromBins(&d, input);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0848848621419624), result.bandwidth, 1e-10);
    }
    {
        // halfgrid-heldout.sas case 4: caller supplies the oracle-established bin.
        const input = oracleInput(&.{ 2.75, 11.07, 24.51, 33.15, 37.95, 70.59, 100.03, 130.75 }, &.{ 0, 13, 34, 48, 55, 106, 152, 200 }, 67.52);
        const result = try fromBins(&d, input);
        try std.testing.expectApproxEqAbs(@as(f64, 23.672629324784147), result.bandwidth, 1e-10);
    }
    {
        // halfgrid-heldout.sas case 6: caller supplies the oracle-established bin.
        const input = oracleInput(&.{ -100.125, -99.7402, -99.1186, -98.497, -96.9874, -96.46940000000001, -95.6258, -94.205 }, &.{ 0, 13, 34, 55, 106, 123, 152, 200 }, 3.38179999999999);
        const result = try fromBins(&d, input);
        try std.testing.expectApproxEqAbs(@as(f64, 1.4879863832227713), result.bandwidth, 1e-10);
    }
    {
        // halfgrid-heldout.sas case 10: caller supplies the oracle-established bin.
        const input = oracleInput(&.{ 2.75, 11.07, 24.51, 37.95, 70.59, 81.79, 100.03, 130.75 }, &.{ 0, 13, 34, 55, 106, 124, 152, 200 }, 73.12);
        const result = try fromBins(&d, input);
        try std.testing.expectApproxEqAbs(@as(f64, 31.892163703618543), result.bandwidth, 1e-10);
    }
}

test "UNIV SJPI binned core rejects degenerate and invalid requests via diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    var sample = BinnedSample{ .counts = [_]usize{0} ** grid_points, .step = 0.1, .sample_stddev = 1, .iqr = 1 };
    try std.testing.expectError(error.ParseError, fromBins(&d, sample));
    sample.counts[0] = 8;
    try std.testing.expectError(error.ParseError, fromBins(&d, sample));
    sample.counts[200] = 8;
    sample.step = 0;
    try std.testing.expectError(error.ParseError, fromBins(&d, sample));
    sample.step = 0.1;
    sample.iqr = std.math.nan(f64);
    try std.testing.expectError(error.ParseError, fromBins(&d, sample));
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 4), d.list.items.len);
}

test "UNIV SJPI binned core SAS M9 no-bracket maximum fallback and warning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const ns = [_]usize{ 100, 1000, 10000, 100000, 1000000 };
    const expected_two = [_]f64{ 1.14965904936093, 1.1444686885445, 1.14395351017559, 1.14390203059452, 1.14389688301865 };
    const expected_four = [_]f64{ 146.800971953133, 146.13821022994, 146.072426652341, 146.065853179501, 146.065195881025 };
    for (ns, expected_two, expected_four) |count, c_two, c_four| {
        const n: f64 = @floatFromInt(count);
        var sample = BinnedSample{ .counts = [_]usize{0} ** grid_points, .step = 0.005, .sample_stddev = @sqrt(0.25 * n / (n - 1)), .iqr = 1 };
        sample.counts[0] = count / 2;
        sample.counts[200] = count / 2;
        const two = try fromBins(&d, sample);
        try std.testing.expectEqual(.maximum_fallback, two.selection);
        try std.testing.expectApproxEqAbs(c_two, two.c, 1e-10);
        // Masses (.4,.4,.1,.1) at (0,.005,.5,1), mean .152.
        sample.counts = [_]usize{0} ** grid_points;
        sample.counts[0] = count * 4 / 10;
        sample.counts[1] = count * 4 / 10;
        sample.counts[100] = count / 10;
        sample.counts[200] = count / 10;
        sample.sample_stddev = @sqrt((0.4 * 0.005 * 0.005 + 0.1 * 0.5 * 0.5 + 0.1 - 0.152 * 0.152) * n / (n - 1));
        sample.iqr = 0.005;
        const four = try fromBins(&d, sample);
        try std.testing.expectEqual(.maximum_fallback, four.selection);
        try std.testing.expectApproxEqAbs(c_four, four.c, 1e-10);
    }
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 10), d.list.items.len);
    for (d.list.items) |message| {
        try std.testing.expectEqual(.warning, message.severity);
        try std.testing.expect(std.mem.indexOf(u8, message.message, "using maximum bandwidth value") != null);
    }
}
