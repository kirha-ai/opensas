//! UNIVARIATE kernel estimates. Mathematical density and SAS's binned output
//! approximation are separate, so plotting never changes the fitted bandwidth.
const std = @import("std");
const diag = @import("../diag.zig");
pub const Kind = enum { normal, quadratic, triangular };
pub const Bandwidth = union(enum) { numeric: f64, mise, sjpi };
pub const Request = struct { kind: Kind = .normal, bandwidth: Bandwidth = .mise, lower: ?f64 = null, upper: ?f64 = null, fft_period: ?f64 = null };
pub const Estimate = struct {
    request: Request,
    c: f64,
    bandwidth: f64,
    amise: f64,

    pub fn density(self: Estimate, x: []const f64, value: f64) f64 {
        if (self.request.lower) |v| if (value < v) return 0;
        if (self.request.upper) |v| if (value > v) return 0;
        var sum: f64 = 0;
        for (x) |v| {
            sum += kernel(self.request.kind, (value - v) / self.bandwidth);
            if (self.request.lower) |bound| sum += kernel(self.request.kind, (value + v - 2 * bound) / self.bandwidth);
            if (self.request.upper) |bound| sum += kernel(self.request.kind, (2 * bound - value - v) / self.bandwidth);
        }
        return sum / (@as(f64, @floatFromInt(x.len)) * self.bandwidth);
    }

    /// SAS OUTKERNEL approximation: bin sample mass linearly on 128 intervals,
    /// evaluate at lattice points, then linearly interpolate requested points.
    pub fn binnedDensity(self: Estimate, x: []const f64, value: f64, d: *diag.Diagnostics) diag.Error!f64 {
        if (self.request.lower) |bound| if (value < bound) return 0;
        if (self.request.upper) |bound| if (value > bound) return 0;
        if (x.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: degenerate kernel grid", .{});
        const step = (x[x.len - 1] - x[0]) / 128;
        if (!(step > 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: degenerate kernel grid", .{});
        const period = self.fftPeriod(step * 128) orelse return d.fail(error.ParseError, 0, "UNIVARIATE: kernel FFT grid is not finite", .{});
        const pos = (value - x[0]) / step;
        if (!std.math.isFinite(pos)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel point exceeds grid resolution", .{});
        const low = @floor(pos);
        const frac = pos - low;
        var result: f64 = 0;
        for (x) |v| {
            const at = (v - x[0]) / step;
            const left = @floor(at);
            const w = at - left;
            const a = x[0] + low * step;
            const b = x[0] + left * step;
            const k00 = self.reflected(a, b, x[0], step, period);
            const k01 = self.reflected(a, b + step, x[0], step, period);
            const k10 = self.reflected(a + step, b, x[0], step, period);
            const k11 = self.reflected(a + step, b + step, x[0], step, period);
            result += (1 - frac) * ((1 - w) * k00 + w * k01) + frac * ((1 - w) * k10 + w * k11);
        }
        return result / @as(f64, @floatFromInt(x.len));
    }

    /// Period of the padded power-of-two FFT lattice. Shared with output-grid
    /// adapters so density periodicity and available ordinates cannot disagree.
    pub fn fftPeriod(self: Estimate, range: f64) ?f64 {
        if (!(range > 0)) return null;
        if (self.request.fft_period) |period| return if (period > 0 and std.math.isFinite(period)) period else null;
        const cutoff: f64 = if (self.request.kind == .normal) 3 else 1;
        const period = if (2 * cutoff * self.bandwidth > range) 4 * range else 2 * range;
        return if (std.math.isFinite(period)) period else null;
    }

    fn fftKernel(self: Estimate, displacement: f64, period: f64) f64 {
        if (self.request.kind != .normal) return kernel(self.request.kind, displacement / self.bandwidth) / self.bandwidth;
        const centered = displacement - @round(displacement / period) * period;
        const ratio = self.bandwidth / period;
        if (ratio >= 0.25) {
            // Dual Fourier series converges rapidly for broad bandwidths and
            // avoids a number of image terms proportional to h/period.
            var sum: f64 = 1;
            var k: f64 = 1;
            while (true) : (k += 1) {
                const amplitude = 2 * @exp(-2 * std.math.pi * std.math.pi * ratio * ratio * k * k);
                sum += amplitude * @cos(2 * std.math.pi * k * centered / period);
                if (amplitude < 1e-17) return sum / period;
            }
        }
        // Adjacent Gaussian images reproduce the periodic FFT convolution.
        // SAS caps padding and warns when bandwidth is large. Sum images to
        // numerical convergence rather than dropping the resulting wraparound.
        var sum = kernel(.normal, centered / self.bandwidth);
        var j: f64 = 1;
        while (true) : (j += 1) {
            const term = kernel(.normal, (centered - j * period) / self.bandwidth) + kernel(.normal, (centered + j * period) / self.bandwidth);
            sum += term;
            if (term <= 1e-17 * sum) return sum / self.bandwidth;
        }
    }

    fn reflected(self: Estimate, point: f64, observation: f64, origin: f64, step: f64, period: f64) f64 {
        if (self.request.lower) |bound| if (point < bound) return 0;
        if (self.request.upper) |bound| if (point > bound) return 0;
        var value = self.fftKernel(point - observation, period);
        if (self.request.lower) |bound| value += self.latticeKernel(2 * bound - point, observation, origin, step, period);
        if (self.request.upper) |bound| value += self.latticeKernel(2 * bound - point, observation, origin, step, period);
        return value;
    }

    fn latticeKernel(self: Estimate, point: f64, observation: f64, origin: f64, step: f64, period: f64) f64 {
        const first = origin - (period - 128 * step) / 2;
        const last = first + period - step;
        if (point < first or point > last) return 0;
        const position = (point - origin) / step;
        const low = @floor(position);
        const fraction = position - low;
        const at = origin + low * step;
        return (1 - fraction) * self.fftKernel(at - observation, period) + fraction * self.fftKernel(at + step - observation, period);
    }
};

pub fn kernel(kind: Kind, value: f64) f64 {
    return switch (kind) {
        .normal => @exp(-value * value / 2) / @sqrt(2 * std.math.pi),
        .quadratic => if (@abs(value) > 1) 0 else 0.75 * (1 - value * value),
        .triangular => @max(0, 1 - @abs(value)),
    };
}

pub fn fit(d: *diag.Diagnostics, x: []const f64, iqr: f64, request: Request) diag.Error!Estimate {
    if (x.len < 2 or !(iqr > 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel requires a positive interquartile range and at least two observations", .{});
    for (x, 0..) |v, i| {
        if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel sample must be sorted and finite", .{});
    }
    if (request.lower) |b| if (!std.math.isFinite(b) or b > x[0]) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel lower bound excludes observations", .{});
    if (request.upper) |b| if (!std.math.isFinite(b) or b < x[x.len - 1]) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel upper bound excludes observations", .{});
    const n: f64 = @floatFromInt(x.len);
    // SAS's normal-reference pilot uses the normal-equivalent IQR, not the
    // sample standard deviation. The M9 three-kernel oracle distinguishes it.
    // SAS uses the rounded normal IQR constant 1.34898.
    const sd = iqr / 1.34898;
    const r: f64 = switch (request.kind) {
        .normal => 1.0 / (2.0 * @sqrt(std.math.pi)),
        .quadratic => 0.6,
        .triangular => 2.0 / 3.0,
    };
    const m2: f64 = switch (request.kind) {
        .normal => 1,
        .quadratic => 0.2,
        .triangular => 1.0 / 6.0,
    };
    const roughness = 3 / (8 * @sqrt(std.math.pi) * std.math.pow(f64, sd, 5));
    const scale = iqr * std.math.pow(f64, n, -0.2);
    const h = switch (request.bandwidth) {
        .numeric => |c| c * scale,
        .mise => std.math.pow(f64, r / (m2 * m2 * roughness * n), 0.2),
        .sjpi => return d.fail(error.ParseError, 0, "UNIVARIATE: SJPI bandwidth selection is not implemented", .{}),
    };
    if (!(h > 0) or !std.math.isFinite(h)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel bandwidth must be finite and positive", .{});
    return .{ .request = request, .c = h / scale, .bandwidth = h, .amise = std.math.pow(f64, h, 4) * m2 * m2 * roughness / 4 + r / (n * h) };
}

pub const VScale = enum { percent, proportion, count };
pub fn scaleDensity(density: f64, binwidth: f64, n: usize, scale: VScale) f64 {
    return density * binwidth * switch (scale) {
        .percent => @as(f64, 100),
        .proportion => @as(f64, 1),
        .count => @as(f64, @floatFromInt(n)),
    };
}

test "UNIVARIATE kernel MISE bandwidth and binned OUTKERNEL SAS M9" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const x = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    const normal = try fit(&d, &x, 6.5, .{ .bandwidth = .{ .numeric = 0.5 } });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0492280549), try normal.binnedDensity(&x, 0, &d), 5e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0495552913), try normal.binnedDensity(&x, 0.015625, &d), 5e-10);
    const auto = try fit(&d, &x, 6.5, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 0.78520352), auto.c, 5e-8);
    const q = try fit(&d, &x, 6.5, .{ .kind = .quadratic });
    try std.testing.expectApproxEqAbs(@as(f64, 1.738287), q.c, 5e-7);
    const t = try fit(&d, &x, 6.5, .{ .kind = .triangular });
    try std.testing.expectApproxEqAbs(@as(f64, 1.9096135), t.c, 5e-8);
    const bounded = try fit(&d, &x, 6.5, .{ .lower = 0, .bandwidth = .{ .numeric = 0.5 } });
    try std.testing.expectEqual(@as(f64, 0), bounded.density(&x, -1));
    try std.testing.expectApproxEqAbs(2 * normal.density(&x, 0), bounded.density(&x, 0), 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.084391), try bounded.binnedDensity(&x, 0, &d), 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.098456), try bounded.binnedDensity(&x, 0.015625, &d), 5e-7);
    try std.testing.expectError(error.ParseError, fit(&d, &x, 6.5, .{ .bandwidth = .sjpi }));
}

test "UNIVARIATE normal FFT periodic density matches independent M9 bandwidth heldouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const x = [_]f64{ 0, 0.3, 0.8, 1 };
    const cases = [_][3]f64{
        .{ 0.2, 0.00011050570727, 0.21404575878347 },
        .{ 0.5, 0.08135287831555, 0.62430481294114 },
        .{ 1, 0.20258005097361, 0.55592464996715 },
        .{ 2, 0.24602365145292, 0.33294504741228 },
    };
    for (cases) |row| {
        const estimate = try fit(&d, &x, 0.75, .{ .bandwidth = .{ .numeric = row[0] } });
        try std.testing.expectApproxEqAbs(row[1], try estimate.binnedDensity(&x, -0.5, &d), 1e-12);
        try std.testing.expectApproxEqAbs(row[2], try estimate.binnedDensity(&x, 0.5, &d), 1e-12);
    }
    // Multiple bandwidths in one statement share the largest padded lattice.
    const shared = try fit(&d, &x, 0.75, .{ .bandwidth = .{ .numeric = 0.2 }, .fft_period = 4 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0000552502448), try shared.binnedDensity(&x, -0.5, &d), 1e-12);
}
