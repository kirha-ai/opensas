//! SAS numerical OUTKERNEL lattice and finite Fourier convolution. No graphics.
const std = @import("std");
const diag = @import("../diag.zig");
const kernel = @import("univ_kernel.zig");
pub const Report = struct { point_count: usize = 0, compact_cutoff_unverified: bool = false };
pub const Options = struct {
    report: ?*Report = null,
    automatic: bool = false,
    windowed: bool = false,
    bin_width: ?f64 = null,
    right: bool = false,
    clip_lower: bool = true,
    clip_upper: bool = true,
    shared_axis_padding: ?f64 = null,
    shared_fft_padding: ?f64 = null,
    shared_fft_period: ?f64 = null,
    max_axis_steps: usize = 1000000,
};
pub const Padding = struct { axis: f64 = 0, fft: f64 = 0 };
pub fn padding(estimates: []const kernel.Estimate) Padding {
    var result: Padding = .{};
    for (estimates) |e| {
        result.axis = @max(result.axis, e.bandwidth * (if (e.request.kind == .normal) @as(f64, 3) else 1));
        result.fft = @max(result.fft, e.bandwidth * (if (e.request.kind == .normal) @as(f64, 3) else 1));
    }
    return result;
}
pub const Plan = struct {
    points: []const f64,
    origin: f64,
    step: f64,
    length: usize,
    bin_width: f64,
    /// Origin of the 128-interval data lattice, before FFT padding.
    data_origin: f64,
    sample_min: f64,
    sample_max: f64,
};

pub fn make(a: std.mem.Allocator, d: *diag.Diagnostics, x: []const f64, estimate: kernel.Estimate, endpoints: []const f64, options: Options) diag.Error!Plan {
    if (x.len == 0 or endpoints.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL requires sample and histogram boundaries", .{});
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL requires sorted finite observations", .{});
    const width = options.bin_width orelse (endpoints[1] - endpoints[0]);
    if (!(width > 0) or !std.math.isFinite(width)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid OUTKERNEL bin width", .{});
    const constant = x[0] == x[x.len - 1];
    const lo = if (constant) x[0] - 0.5 else x[0];
    const hi = if (constant) x[0] + 0.5 else x[x.len - 1];
    const range = hi - lo;
    const step = range / 128;
    if (!(step > 0) or !std.math.isFinite(step)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel grid range is not representable", .{});
    const own = padding(&.{estimate});
    const axis_pad = @ceil((options.shared_axis_padding orelse own.axis) / step) * step;
    const fft_pad = options.shared_fft_padding orelse own.fft;
    const period_hint = options.shared_fft_period orelse estimate.request.fft_period;
    const length: usize = if (period_hint) |period| blk: {
        if (period == 2 * range) break :blk 256;
        if (period == 4 * range) break :blk 512;
        return d.fail(error.ParseError, 0, "UNIVARIATE: output FFT period must span two or four data ranges", .{});
    } else if (fft_pad <= (if (constant) range else range / 2)) 256 else 512;
    if (own.fft > 1.5 * range) try d.warn(0, "UNIVARIATE: kernel bandwidth produces wrap-around at the finite output grid ends", .{});
    const origin = lo - @as(f64, @floatFromInt((length - 128) / 2)) * step;
    const grid_last = origin + @as(f64, @floatFromInt(length - 1)) * step;
    if (!std.math.isFinite(origin) or !std.math.isFinite(grid_last) or !std.math.isFinite(@as(f64, @floatFromInt(length)) * step) or !(origin + step > origin)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel lattice exceeds floating-point resolution", .{});
    var first = endpoints[0];
    var last = endpoints[endpoints.len - 1];
    // Supplied endpoints are lattice values; an observation on the open side
    // requires an additional interval, including for an explicit endpoint list.
    if (!options.windowed and options.right and x[0] == first) first -= width;
    if (!options.windowed and !options.right and x[x.len - 1] == last) last += width;
    if (options.automatic and !options.windowed and constant) {
        // The constant plot extends its center lattice over a unit range.
        // Retain iterative endpoint rounding: M9 includes eleven centers for
        // width .1 but ninety-nine for .01 on the retained heldouts.
        if (1 / width > @as(f64, @floatFromInt(options.max_axis_steps))) return d.fail(error.ParseError, 0, "UNIVARIATE: constant kernel axis exceeds its stepping budget", .{});
        var left = x[0];
        var right = x[0];
        while (left - width >= lo) {
            const next = left - width;
            if (!(next < left)) return d.fail(error.ParseError, 0, "UNIVARIATE: constant kernel axis cannot advance", .{});
            left = next;
        }
        while (right + width <= hi) {
            const next = right + width;
            if (!(next > right)) return d.fail(error.ParseError, 0, "UNIVARIATE: constant kernel axis cannot advance", .{});
            right = next;
        }
        first = left - width / 2;
        last = right + width / 2;
    } else if (options.automatic and !options.windowed) {
        if (lo - axis_pad < first) first -= @ceil((first - (lo - axis_pad)) / width) * width;
        if (hi + axis_pad > last) last += @ceil(((hi + axis_pad) - last) / width) * width;
    }
    if (options.clip_lower) {
        if (estimate.request.lower) |bound| first = @max(first, endpoints[0] + @floor((bound - endpoints[0]) / width) * width);
    }
    if (options.clip_upper) {
        if (estimate.request.upper) |bound| last = @min(last, endpoints[0] + @ceil((bound - endpoints[0]) / width) * width);
    }
    if (!std.math.isFinite(first) or !std.math.isFinite(last) or !(last > first)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid kernel output extent", .{});
    var points: std.ArrayList(f64) = .empty;
    // SAS retains requested boundaries even when they duplicate a lattice row.
    if (first >= origin and first <= grid_last) try points.append(a, first);
    for (0..length) |i| {
        const point = origin + @as(f64, @floatFromInt(i)) * step;
        if (point >= first and point <= last) try points.append(a, point);
    }
    if (last >= origin and last <= grid_last) try points.append(a, last);
    if (options.report) |report| {
        report.point_count += points.items.len;
        report.compact_cutoff_unverified = report.compact_cutoff_unverified or estimate.request.kind != .normal;
    }
    return .{ .points = try points.toOwnedSlice(a), .origin = origin, .step = step, .length = length, .bin_width = width, .data_origin = lo, .sample_min = x[0], .sample_max = x[x.len - 1] };
}

pub const Density = struct {
    plan: Plan,
    estimate: kernel.Estimate,
    ordinates: []const f64,
    fn raw(self: Density, point: f64) f64 {
        const pos = (point - self.plan.origin) / self.plan.step;
        if (!std.math.isFinite(pos)) return 0;
        const low = @floor(pos);
        const fraction = pos - low;
        const a = if (low >= 0 and low < @as(f64, @floatFromInt(self.ordinates.len))) self.ordinates[@intFromFloat(low)] else 0;
        const b = if (low + 1 >= 0 and low + 1 < @as(f64, @floatFromInt(self.ordinates.len))) self.ordinates[@intFromFloat(low + 1)] else 0;
        return (1 - fraction) * a + fraction * b;
    }
    fn reflection(self: Density, point: f64) f64 {
        const tail = self.estimate.bandwidth * (if (self.estimate.request.kind == .normal) @as(f64, 3) else 1);
        const index = @floor((point - self.plan.data_origin) / self.plan.step);
        if (index < @floor((self.plan.sample_min - self.plan.data_origin - tail) / self.plan.step) or index > @ceil((self.plan.sample_max - self.plan.data_origin + tail) / self.plan.step)) return 0;
        return self.raw(point);
    }
    fn lattice(self: Density, point: f64) f64 {
        if (self.estimate.request.lower) |b| if (point < b) return 0;
        if (self.estimate.request.upper) |b| if (point > b) return 0;
        var result = self.raw(point);
        if (self.estimate.request.lower) |b| result += self.reflection(2 * b - point);
        if (self.estimate.request.upper) |b| result += self.reflection(2 * b - point);
        return result;
    }
    pub fn at(self: Density, point: f64) f64 {
        if (self.estimate.request.lower) |b| if (point < b) return 0;
        if (self.estimate.request.upper) |b| if (point > b) return 0;
        const position = (point - self.plan.data_origin) / self.plan.step;
        const low = @floor(position);
        const fraction = position - low;
        const a = self.plan.data_origin + low * self.plan.step;
        return (1 - fraction) * self.lattice(a) + fraction * self.lattice(a + self.plan.step);
    }
};

fn characteristic(kind: kernel.Kind, t: f64) f64 {
    if (!std.math.isFinite(t)) return 0;
    const t2 = t * t;
    return switch (kind) {
        .normal => @exp(-t2 / 2),
        .quadratic => if (@abs(t) < 0.001) 1 - t2 / 10 + t2 * t2 / 280 - t2 * t2 * t2 / 15120 else 3 * (@sin(t) - t * @cos(t)) / (t * t2),
        .triangular => if (@abs(t) < 0.001) 1 - t2 / 12 + t2 * t2 / 360 - t2 * t2 * t2 / 20160 else std.math.pow(f64, @sin(t / 2) / (t / 2), 2),
    };
}

/// Evaluate the real finite Fourier series directly (at most 512 ordinates).
/// This is algebraically the same circular convolution as the FFT, without an
/// FFT dependency. Compact-kernel gaps suppress finite-series ringing outside
/// the rounded occupied-bin support. Three heldout cutoff disagreements are
/// retained explicitly; Report marks compact cutoff parity as unverified.
pub fn evaluate(a: std.mem.Allocator, d: *diag.Diagnostics, x: []const f64, estimate: kernel.Estimate, plan: Plan) diag.Error!Density {
    if ((plan.length != 256 and plan.length != 512) or !(plan.step > 0) or !std.math.isFinite(plan.step)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid spectral kernel plan", .{});
    if (x.len == 0 or !(estimate.bandwidth > 0) or !std.math.isFinite(estimate.bandwidth)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid kernel estimate for output", .{});
    var mass = [_]f64{0} ** 512;
    for (x) |v| {
        const position = (v - plan.origin) / plan.step;
        if (!(position >= 0 and position < @as(f64, @floatFromInt(plan.length - 1)))) return d.fail(error.ParseError, 0, "UNIVARIATE: observation outside kernel data lattice", .{});
        const at = position;
        const low: usize = @intFromFloat(@floor(at));
        const fraction = at - @as(f64, @floatFromInt(low));
        mass[low] += 1 - fraction;
        mass[low + 1] += fraction;
    }
    const length = plan.length;
    const period = @as(f64, @floatFromInt(length)) * plan.step;
    var phi: [257]f64 = undefined;
    for (0..length / 2 + 1) |k| phi[k] = characteristic(estimate.request.kind, 2 * std.math.pi * @as(f64, @floatFromInt(k)) * estimate.bandwidth / period);
    var response: [512]f64 = undefined;
    for (0..length) |j| {
        var sum = phi[0] + phi[length / 2] * (if (j % 2 == 0) @as(f64, 1) else -1);
        for (1..length / 2) |k| sum += 2 * phi[k] * @cos(2 * std.math.pi * @as(f64, @floatFromInt(k * j)) / @as(f64, @floatFromInt(length)));
        response[j] = sum / period;
    }
    const ordinates = try a.alloc(f64, length);
    const radius = @ceil(estimate.bandwidth / plan.step);
    for (ordinates, 0..) |*value, index| {
        const i = @as(i64, @intCast(index));
        var sum: f64 = 0;
        var occupied = false;
        for (mass[0..length], 0..) |weight, j| {
            if (weight == 0) continue;
            const delta = i - @as(i64, @intCast(j));
            const k: usize = @intCast(@mod(delta, @as(i64, @intCast(length))));
            sum += weight * response[k];
            if (@as(f64, @floatFromInt(@abs(delta))) <= radius) occupied = true;
        }
        value.* = if (estimate.request.kind != .normal and !occupied) 0 else @max(@as(f64, 0), sum / @as(f64, @floatFromInt(x.len)));
    }
    return .{ .plan = plan, .estimate = estimate, .ordinates = ordinates };
}
