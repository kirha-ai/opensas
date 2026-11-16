//! SJPI raw assignment and solve-the-equation core on a 201-point histogram.
//! Raw sorted/FREQ-expanded samples use the oracle-validated stored cell edge.
//! See docs/findings/univ-sjpi-dev3/cell-edge for frozen and prospective evidence.
//! Public statement dispatch remains a separate integration responsibility.
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

pub const RawSample = struct {
    /// Finite, sorted, missing-filtered observations, with FREQ expanded by the
    /// caller. Original statistics must use that same effective sample.
    sorted: []const f64,
    sample_stddev: f64,
    iqr: f64,
};

/// Return no estimate (and a captured warning) for empty/singleton/constant
/// samples. Native M9 reports errors for nonconstant zero-IQR SJPI; do not
/// silently replace its scale by the range or substitute another estimator.
pub fn fromRaw(d: *diag.Diagnostics, sample: RawSample) diag.Error!?Result {
    const binned = try binRaw(d, sample) orelse return null;
    return try fromBins(d, binned);
}

/// Raw assignment is separate from bandwidth selection for adapters that need
/// the histogram. Empty padded bins are removed only after integer assignment.
pub fn binRaw(d: *diag.Diagnostics, sample: RawSample) diag.Error!?BinnedSample {
    @setFloatMode(.strict);
    const x = sample.sorted;
    for (x, 0..) |v, i| {
        if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1]))
            return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: raw observations must be sorted and finite", .{});
    }
    if (x.len < 2 or x[0] == x[x.len - 1]) {
        try d.warn(0, "UNIVARIATE SJPI: no estimate for fewer than two distinct nonmissing observations", .{});
        return null;
    }
    if (!positiveFinite(sample.sample_stddev) or !positiveFinite(sample.iqr))
        return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: nonconstant samples require finite positive original SD and IQR", .{});
    const range = x[x.len - 1] - x[0];
    const step = range / 200;
    // Preserve these stored operations. Direct min-range/2 is not equivalent
    // at half-grid values in translated domains.
    const lower_pad = x[0] - range;
    const upper_pad = x[x.len - 1] + range;
    const lower = (lower_pad + x[0]) / 2;
    const upper = (upper_pad + x[x.len - 1]) / 2;
    if (!positiveFinite(step) or !std.math.isFinite(lower) or !std.math.isFinite(upper))
        return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: padded grid is not representable", .{});
    var result = BinnedSample{ .counts = [_]usize{0} ** grid_points, .step = step, .sample_stddev = sample.sample_stddev, .iqr = sample.iqr };
    for (x) |v| {
        const at = try cellIndex(d, v, lower, upper, 401);
        if (at < 100 or at > 300)
            return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: nonempty padding cannot be removed", .{});
        result.counts[at - 100] += 1;
    }
    return result;
}

fn cellIndex(d: *diag.Diagnostics, x: f64, lower: f64, upper: f64, points: usize) diag.Error!usize {
    @setFloatMode(.strict);
    if (points < 2) return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: invalid grid size", .{});
    const span = upper - lower;
    const h = span / @as(f64, @floatFromInt(points - 1));
    const half = h / 2;
    const edge = lower - half;
    if (!positiveFinite(h) or !std.math.isFinite(edge) or !(edge < lower))
        return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: cell edge exceeds floating-point resolution", .{});
    // Do not rewrite this as (x-lower)/h+.5 or (x-lower+half)/h.
    const offset = x - edge;
    const at = @floor(offset / h);
    if (!std.math.isFinite(at) or at < 0 or at >= @as(f64, @floatFromInt(points)))
        return d.fail(error.ParseError, 0, "UNIVARIATE SJPI: observation outside padded grid", .{});
    return @intFromFloat(at);
}

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

fn parseRawTestValues(a: std.mem.Allocator, text: []const u8) ![]f64 {
    var list: std.ArrayList(f64) = .empty;
    var fields = std.mem.splitScalar(u8, text, ',');
    while (fields.next()) |v| try list.append(a, try std.fmt.parseFloat(f64, v));
    return list.toOwnedSlice(a);
}

fn parseRawTestCounts(text: []const u8, counts: []usize) !void {
    @memset(counts, 0);
    var fields = std.mem.splitScalar(u8, text, ',');
    while (fields.next()) |v| {
        var pair = std.mem.splitScalar(u8, v, ':');
        const at = try std.fmt.parseInt(usize, pair.next().?, 10);
        counts[at] = try std.fmt.parseInt(usize, pair.next().?, 10);
    }
}

test "UNIV SJPI raw cell edge matches all 163 old and 72 native query counts and bandwidths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_sjpi_raw_retained_dev3.txt"), '\n');
    var compared: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '|');
        const name = fields.next().?;
        const sd = try std.fmt.parseFloat(f64, fields.next().?);
        const iqr = try std.fmt.parseFloat(f64, fields.next().?);
        const expected_h = try std.fmt.parseFloat(f64, fields.next().?);
        const x = try parseRawTestValues(a, fields.next().?);
        var expected: [grid_points]usize = undefined;
        try parseRawTestCounts(fields.next().?, &expected);
        const input = RawSample{ .sorted = x, .sample_stddev = sd, .iqr = iqr };
        const sample = (try binRaw(&d, input)).?;
        if (!std.mem.eql(usize, &expected, &sample.counts)) {
            std.debug.print("SJPI raw count discrepancy {s}\n", .{name});
            return error.TestUnexpectedResult;
        }
        var total: usize = 0;
        for (sample.counts) |n| total += n;
        try std.testing.expectEqual(x.len, total);
        const estimate = (try fromRaw(&d, input)).?;
        if (@abs(estimate.bandwidth - expected_h) > 1e-10) {
            std.debug.print("SJPI retained bandwidth discrepancy {s}: {d} vs {d}\n", .{ name, estimate.bandwidth, expected_h });
            return error.TestUnexpectedResult;
        }
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 235), compared);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
}

test "UNIV SJPI cell edge preserves all 60 native binary midpoint controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_sjpi_binary_controls_dev3.txt"), '\n');
    var compared: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '|');
        _ = fields.next();
        const points = try std.fmt.parseInt(usize, fields.next().?, 10);
        const lower = try std.fmt.parseFloat(f64, fields.next().?);
        const upper = try std.fmt.parseFloat(f64, fields.next().?);
        const x = try parseRawTestValues(a, fields.next().?);
        var expected: [401]usize = undefined;
        try parseRawTestCounts(fields.next().?, &expected);
        var actual = [_]usize{0} ** 401;
        for (x) |v| actual[try cellIndex(&d, v, lower, upper, points)] += 1;
        try std.testing.expectEqualSlices(usize, expected[0..points], actual[0..points]);
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 60), compared);
}

test "UNIV SJPI raw adapter prospective counts bandwidth transforms ties and FREQ" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_sjpi_raw_fresh_dev3.txt"), '\n');
    var compared: usize = 0;
    var fallbacks: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '|');
        const name = fields.next().?;
        const sd = try std.fmt.parseFloat(f64, fields.next().?);
        const iqr = try std.fmt.parseFloat(f64, fields.next().?);
        const expected_c = try std.fmt.parseFloat(f64, fields.next().?);
        const expected_h = try std.fmt.parseFloat(f64, fields.next().?);
        const selection = fields.next().?;
        const x = try parseRawTestValues(a, fields.next().?);
        var expected: [grid_points]usize = undefined;
        try parseRawTestCounts(fields.next().?, &expected);
        const input = RawSample{ .sorted = x, .sample_stddev = sd, .iqr = iqr };
        const binned = (try binRaw(&d, input)).?;
        try std.testing.expectEqualSlices(usize, &expected, &binned.counts);
        const result = (try fromRaw(&d, input)).?;
        if (@abs(result.bandwidth - expected_h) > 1e-10 or @abs(result.c - expected_c) > 1e-10) {
            std.debug.print("SJPI raw bandwidth discrepancy {s}: h {d} vs {d}, c {d} vs {d}\n", .{ name, result.bandwidth, expected_h, result.c, expected_c });
            return error.TestUnexpectedResult;
        }
        const fallback = std.mem.eql(u8, selection, "maximum_fallback");
        try std.testing.expectEqual(fallback, result.selection == .maximum_fallback);
        if (fallback) fallbacks += 1;
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 22), compared);
    try std.testing.expectEqual(@as(usize, 4), fallbacks);
    try std.testing.expectEqual(fallbacks, d.list.items.len);
    for (d.list.items) |message| try std.testing.expectEqual(.warning, message.severity);
}

test "UNIV SJPI raw degeneracy and invalid input use captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    for ([_][]const f64{ &.{}, &.{2.75}, &.{ 2.75, 2.75, 2.75, 2.75, 2.75 } }) |x| {
        try std.testing.expect((try fromRaw(&d, .{ .sorted = x, .sample_stddev = std.math.nan(f64), .iqr = 0 })) == null);
    }
    try std.testing.expectEqual(@as(usize, 3), d.list.items.len);
    for (d.list.items) |message| try std.testing.expectEqual(.warning, message.severity);
    var zeroiqr = [_]f64{0} ** 21;
    zeroiqr[20] = 10;
    try std.testing.expectError(error.ParseError, fromRaw(&d, .{ .sorted = &zeroiqr, .sample_stddev = 1, .iqr = 0 }));
    try std.testing.expectError(error.ParseError, fromRaw(&d, .{ .sorted = &.{ 2, 1 }, .sample_stddev = 1, .iqr = 1 }));
    try std.testing.expectError(error.ParseError, fromRaw(&d, .{ .sorted = &.{ 0, std.math.inf(f64) }, .sample_stddev = 1, .iqr = 1 }));
    try std.testing.expectError(error.ParseError, fromRaw(&d, .{ .sorted = &.{ -1e308, 1e308 }, .sample_stddev = 1, .iqr = 1 }));
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 7), d.list.items.len);
}
