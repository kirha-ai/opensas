//! SAS numerical OUTKERNEL lattice and finite Fourier convolution. No graphics.
const std = @import("std");
const diag = @import("../diag.zig");
const kernel = @import("univ_kernel.zig");
// Retain the status field for existing adapters. The connected-component cutoff
// is now oracle-validated; this is not a claim about other distribution fitting.
pub const Report = struct { point_count: usize = 0, compact_cutoff_unverified: bool = false };
pub const Options = struct {
    report: ?*Report = null,
    note_prefix: ?[]const u8 = null,
    automatic: bool = false,
    endpoint_labels: bool = false,
    comparative: bool = false,
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
    ignore_bounds: bool,
};

/// M9 emits the Fourier lattice in groups of four. Rounding affects whether a
/// regular point exactly on a histogram boundary produces an extra output row.
/// Odd sample sizes have two leading points and a shorter final vector group.
fn outputLattice(points: []f64, lo: f64, hi: f64, odd_count: bool, constant_center: ?f64) void {
    const span = hi - lo;
    const extra = if (points.len == 512) span else 0;
    const first = if (constant_center) |center| center - @as(f64, @floatFromInt(points.len)) / 256 else (lo - span / 2) - extra;
    const limit = (hi + span / 2) + extra;
    const step = if (constant_center != null) @as(f64, 1) / 128 else (limit - first) / @as(f64, @floatFromInt(points.len));
    const four_steps: @Vector(4, f64) = @splat(4 * step);
    const eight_steps: @Vector(4, f64) = @splat(8 * step);
    const offsets: @Vector(4, f64) = .{ 0, step, 2 * step, 3 * step };
    const preceding = first - step;
    var at: usize = 0;
    var scalar = preceding;
    if (odd_count) {
        points[0] = first;
        points[1] = first + step;
        scalar = ((preceding + step) + step) + step;
        at = 2;
    }
    const start = if (odd_count) @mulAdd(f64, 3, step, preceding) else first;
    var lanes = @as(@Vector(4, f64), @splat(start)) + offsets;
    while (at + 16 <= points.len) {
        for (0..2) |_| {
            points[at..][0..4].* = lanes;
            points[at + 4 ..][0..4].* = lanes + four_steps;
            lanes += eight_steps;
            at += 8;
        }
        scalar += 16 * step;
    }
    if (!odd_count) return;
    const tail = @mulAdd(f64, @as(f64, @floatFromInt(at + 1)), step, preceding);
    lanes = @as(@Vector(4, f64), @splat(tail)) + offsets;
    while (at + 4 <= points.len) : (at += 4) {
        points[at..][0..4].* = lanes;
        lanes += four_steps;
        scalar += 4 * step;
    }
    points[at] = scalar;
    points[at + 1] = scalar + step;
}

const BoundaryStatus = enum { valid, wraps_around, interval_too_small };

fn reportEstimate(d: *diag.Diagnostics, note_prefix: ?[]const u8, estimate: kernel.Estimate, status: BoundaryStatus) diag.Error!void {
    if (note_prefix == null and status == .valid) return;
    const fmt = @import("../format.zig");
    const prefix = note_prefix orelse "";
    const article = if (prefix.len == 0) "The" else "the";
    const kind = @tagName(estimate.request.kind);
    const c = try fmt.bestNumW(d.arena, estimate.c, 6);
    const bandwidth = try fmt.bestNumW(d.arena, estimate.bandwidth, 6);
    const bounded = estimate.request.lower != null or estimate.request.upper != null;
    if (status == .wraps_around) {
        try d.warn(0, "{s}{s} {s} kernel estimate for c={s} has a large bandwidth of {s}, which results in the wrap-around effect at the ends of the horizontal axis.", .{ prefix, article, kind, c, bandwidth });
        if (bounded) try d.warn(0, "{s}{s} LOWER= and UPPER= options are not used in the {s} kernel estimate for c={s} because of the wrap-around effect at the ends of the horizontal axis.", .{ prefix, article, kind, c });
    } else if (status == .interval_too_small) {
        try d.warn(0, "{s}{s} interval specified with the LOWER= and UPPER= options is too small to compute the {s} kernel estimate for c={s}. The LOWER= and UPPER= options are not used.", .{ prefix, article, kind, c });
    }
    if (note_prefix == null) return;
    if (bounded and status == .valid) {
        try d.note(0, "{s}{s} bounded {s} kernel estimate for c={s} has a bandwidth of {s}.", .{ prefix, article, kind, c, bandwidth });
    } else {
        const amise = try fmt.bestNumW(d.arena, estimate.amise, 6);
        try d.note(0, "{s}{s} {s} kernel estimate for c={s} has a bandwidth of {s} and an AMISE of {s}.", .{ prefix, article, kind, c, bandwidth, amise });
    }
}

fn advanceConstantTicks(d: *diag.Diagnostics, center: f64, increment: f64, count: f64, budget: usize) diag.Error!f64 {
    if (count > @as(f64, @floatFromInt(budget))) return d.fail(error.ParseError, 0, "UNIVARIATE: constant kernel axis exceeds its stepping budget", .{});
    var value = center;
    for (0..@as(usize, @intFromFloat(count))) |_| {
        const next = value + increment;
        if (next == value) return d.fail(error.ParseError, 0, "UNIVARIATE: constant kernel axis cannot advance", .{});
        value = next;
    }
    return value;
}

pub fn make(a: std.mem.Allocator, d: *diag.Diagnostics, x: []const f64, estimate: kernel.Estimate, endpoints: []const f64, options: Options) diag.Error!Plan {
    if (x.len == 0 or endpoints.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL requires sample and histogram boundaries", .{});
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL requires sorted finite observations", .{});
    const width = options.bin_width orelse (endpoints[1] - endpoints[0]);
    if (!(width > 0) or !std.math.isFinite(width)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid OUTKERNEL bin width", .{});
    const constant = x[0] == x[x.len - 1];
    const lo = if (constant) x[0] - 0.5 else x[0];
    const hi = if (constant) x[0] + 0.5 else x[x.len - 1];
    const range = if (constant) @as(f64, 1) else hi - lo;
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
    // The constant-sample grid starts with a unit reference span around
    // its single distinct value, leaving two full spans for padding.
    const wrap_limit = if (constant) 2 * range else 1.5 * range;
    var status: BoundaryStatus = .valid;
    if (own.fft > wrap_limit) {
        status = .wraps_around;
    } else if (estimate.request.lower) |lower| if (estimate.request.upper) |upper| {
        // A single reflection from either boundary must stay inside the
        // opposite boundary. Compare the reflected data tails in input units.
        const lower_tail = x[0] - own.fft;
        const upper_tail = x[x.len - 1] + own.fft;
        if (lower + (lower - lower_tail) > upper or upper - (upper_tail - upper) < lower) status = .interval_too_small;
    };
    try reportEstimate(d, options.note_prefix, estimate, status);
    const origin = if (constant) x[0] - @as(f64, @floatFromInt(length)) / 256 else lo - @as(f64, @floatFromInt((length - 128) / 2)) * step;
    var storage: [512]f64 = undefined;
    const lattice = storage[0..length];
    outputLattice(lattice, lo, hi, x.len % 2 == 1, if (constant) x[0] else null);
    if (!std.math.isFinite(origin) or !std.math.isFinite(lattice[0]) or !std.math.isFinite(lattice[length - 1]) or !std.math.isFinite(@as(f64, @floatFromInt(length)) * step) or !(origin + step > origin)) return d.fail(error.ParseError, 0, "UNIVARIATE: kernel lattice exceeds floating-point resolution", .{});
    var first = endpoints[0];
    var last = endpoints[endpoints.len - 1];
    // Supplied endpoints are lattice values; an observation on the open side
    // requires an additional interval, including for an explicit endpoint list.
    if (!options.windowed and options.right and x[0] == first) first -= width;
    if (!options.windowed and !options.right and x[x.len - 1] == last) last += width;
    // A single constant cell is centered on its observation. Comparative
    // endpoint labels are anchored to the histogram's common bin boundaries.
    const automatic_constant = options.automatic and !options.windowed and constant and (!options.endpoint_labels or !options.comparative);
    if (automatic_constant) {
        // Extend centers by the kernel padding on the Fourier lattice. Leave
        // the last node available for interpolation. A tail on a bin edge is
        // covered without taking an additional step.
        const padding_limit = @as(f64, @floatFromInt((length - 128) / 2 - 1)) * step;
        const increments = @ceil(@min(axis_pad, padding_limit) / width - 0.5);
        var left_steps = increments;
        var right_steps = increments;
        if (options.endpoint_labels) {
            if (options.clip_lower) if (estimate.request.lower) |bound| {
                left_steps = @min(left_steps, -@floor((bound - x[0]) / width + 0.5));
            };
            if (options.clip_upper) if (estimate.request.upper) |bound| {
                right_steps = @min(right_steps, @floor((bound - x[0]) / width + 0.5));
            };
            left_steps = @max(left_steps, @as(f64, @floatFromInt(@intFromBool(options.right))));
            right_steps = @max(right_steps, 1);
        }
        const left = try advanceConstantTicks(d, x[0], -width, left_steps, options.max_axis_steps);
        const right = try advanceConstantTicks(d, x[0], width, right_steps, options.max_axis_steps);
        if (options.endpoint_labels) {
            first = if (options.clip_lower and estimate.request.lower != null) left else @min(first, left);
            last = if (options.clip_upper and estimate.request.upper != null) right else @max(last, right);
        } else {
            first = left - width / 2;
            last = right + width / 2;
        }
    } else if (options.automatic and !options.windowed and options.endpoint_labels) {
        const raw_pad = options.shared_axis_padding orelse own.axis;
        const constant_limit = @as(f64, @floatFromInt((length - 128) / 2 - 1)) * step;
        const pad = if (constant) @min(raw_pad, constant_limit) else raw_pad;
        const lower = (if (constant) x[0] else lo) - pad;
        const upper = (if (constant) x[0] else hi) + pad;
        first = @min(first, endpoints[0] + @round((lower - endpoints[0]) / width) * width);
        last = @max(last, endpoints[0] + @round((upper - endpoints[0]) / width) * width);
        if (constant and last <= x[0]) last += width;
    } else if (options.automatic and !options.windowed) {
        if (lo - axis_pad < first) first -= @ceil((first - (lo - axis_pad)) / width) * width;
        if (hi + axis_pad > last) last += @ceil(((hi + axis_pad) - last) / width) * width;
    }
    if (!(automatic_constant and options.endpoint_labels)) {
        if (options.clip_lower) if (estimate.request.lower) |bound| {
            first = @max(first, endpoints[0] + @floor((bound - endpoints[0]) / width) * width);
        };
        if (options.clip_upper) if (estimate.request.upper) |bound| {
            last = @min(last, endpoints[0] + @ceil((bound - endpoints[0]) / width) * width);
        };
    }
    if (!std.math.isFinite(first) or !std.math.isFinite(last) or !(last > first)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid kernel output extent", .{});
    var points: std.ArrayList(f64) = .empty;
    // SAS retains requested boundaries even when they duplicate a lattice row.
    if (first >= lattice[0] and first <= lattice[length - 1] and !(constant and first == lattice[0])) try points.append(a, first);
    for (lattice) |point| {
        if (point >= first and point <= last) try points.append(a, point);
    }
    if (last >= lattice[0] and last <= lattice[length - 1]) try points.append(a, last);
    if (options.report) |report| {
        report.point_count += points.items.len;
    }
    return .{ .points = try points.toOwnedSlice(a), .origin = origin, .step = step, .length = length, .bin_width = width, .data_origin = lo, .sample_min = x[0], .sample_max = x[x.len - 1], .ignore_bounds = status != .valid };
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
        // M9 applies this bandwidth/index guard before interpolation. A retained
        // spectral run can extend past the nominal support by another node;
        // interpolating first and then clipping changes reflected edge values.
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
        // Bound the Fourier nodes before interpolating an output boundary.
        // The last segment can have a positive ordinate just outside a bound.
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
/// FFT dependency. For compact kernels, retain positive spectral components
/// connected to deposited data mass and remove disconnected ringing. M9 probes
/// distinguish this from a bandwidth-radius mask and from trimming outer tails
/// only: disconnected ringing also occurs between separated sample clusters.
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
    for (ordinates, 0..) |*value, index| {
        const i = @as(i64, @intCast(index));
        var sum: f64 = 0;
        for (mass[0..length], 0..) |weight, j| {
            if (weight == 0) continue;
            const delta = i - @as(i64, @intCast(j));
            const k: usize = @intCast(@mod(delta, @as(i64, @intCast(length))));
            sum += weight * response[k];
        }
        value.* = @max(@as(f64, 0), sum / @as(f64, @floatFromInt(x.len)));
    }
    if (estimate.request.kind != .normal) {
        // Work on the native finite lattice, before boundary interpolation and
        // reflection. Do not join runs across the two ends of the output grid.
        var first: usize = 0;
        while (first < length) {
            if (ordinates[first] <= 0) {
                first += 1;
                continue;
            }
            var last = first;
            var occupied = false;
            while (last < length and ordinates[last] > 0) : (last += 1) occupied = occupied or mass[last] > 0;
            if (!occupied) @memset(ordinates[first..last], 0);
            first = last;
        }
    }
    // Bounds still set the output extent when circular wrap-around or an
    // overlapping reflection requires the unreflected periodic density.
    var fitted = estimate;
    if (plan.ignore_bounds) {
        fitted.request.lower = null;
        fitted.request.upper = null;
    }
    return .{ .plan = plan, .estimate = fitted, .ordinates = ordinates };
}

test "kernel bounds crossing the opposite reflected tail use the ordinary density" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const x = [_]f64{4} ** 8;
    const fit: kernel.Estimate = .{
        .request = .{ .kind = .triangular, .lower = 3.75, .upper = 4.11 },
        .c = 1.38,
        .bandwidth = 1.38 * std.math.pow(f64, 8, -0.2),
        .amise = 0,
    };
    const plan = try make(a, &d, &x, fit, &.{ 2, 6 }, .{ .automatic = true, .bin_width = 4, .note_prefix = "" });
    try std.testing.expect(plan.ignore_bounds);
    try std.testing.expectEqualStrings("The interval specified with the LOWER= and UPPER= options is too small to compute the triangular kernel estimate for c=1.38. The LOWER= and UPPER= options are not used.", d.list.items[0].message);
    const density = try evaluate(a, &d, &x, fit, plan);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6836565694821494), density.at(3.65625), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7119339898422231), density.at(4.3203125), 1e-13);

    var nearby = fit;
    nearby.request = .{ .kind = .triangular, .lower = 3.75, .upper = 4.5 };
    const valid = try make(a, &d, &x, nearby, &.{ 2, 6 }, .{ .automatic = true, .bin_width = 4 });
    try std.testing.expect(!valid.ignore_bounds);
    const reflected = try evaluate(a, &d, &x, nearby, valid);
    try std.testing.expectEqual(@as(f64, 0), reflected.at(3.65625));
}

test "interpolated output boundaries retain the final segment of a bounded kernel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const x = [_]f64{0} ** 5;
    const fit: kernel.Estimate = .{
        .request = .{ .lower = -0.125 },
        .c = 0.18,
        .bandwidth = 0.18 * std.math.pow(f64, 5, -0.2),
        .amise = 0,
    };
    const plan = try make(a, &d, &x, fit, &.{ -0.12890625, 0.165 }, .{});
    const density = try evaluate(a, &d, &x, fit, plan);
    try std.testing.expectApproxEqAbs(@as(f64, 1.9323289468917175), density.at(-0.12890625), 1e-13);
    try std.testing.expectEqual(@as(f64, 0), density.at(-0.134375));
}

test "constant midpoint kernel limits match M9 at interior and saturated Fourier bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const Case = struct { center: f64, tail: f64, rows: usize, first: f64, last: f64 };
    for ([_]Case{
        .{ .center = 1, .tail = 0.3211 * 3, .rows = 131, .first = 0.5, .last = 1.5 },
        .{ .center = 1, .tail = 0.7225 * 3, .rows = 387, .first = -0.5, .last = 2.5 },
        .{ .center = 0.01, .tail = 3 * 0.5 * std.math.pow(f64, 3, -0.2), .rows = 313, .first = -1.2050000000000007, .last = 1.2250000000000008 },
        .{ .center = 2, .tail = 0.24, .rows = 256, .first = 1, .last = 2.9921875 },
        .{ .center = 0.9, .tail = 2, .rows = 512, .first = -1.1, .last = 2.8921875 },
        .{ .center = 0.03, .tail = 0.36792797332519894, .rows = 99, .first = -0.3450000000000001, .last = 0.40500000000000014 },
    }) |case| {
        const x = [_]f64{case.center} ** 3;
        const endpoints = [_]f64{ case.center / 2, case.center + case.center / 2 };
        const fitted: kernel.Estimate = .{ .request = .{ .kind = .quadratic }, .bandwidth = case.tail, .c = 1, .amise = 0 };
        const plan = try make(a, &d, &x, fitted, &endpoints, .{ .automatic = true, .bin_width = case.center });
        try std.testing.expectEqual(case.rows, plan.points.len);
        try std.testing.expectEqual(case.first, plan.points[0]);
        try std.testing.expectEqual(case.last, plan.points[plan.points.len - 1]);
    }
}

test "automatic constant ENDPOINTS uses the native bin offsets and bounded ticks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const Case = struct {
        n: usize,
        center: f64,
        kind: kernel.Kind,
        c: f64,
        right: bool = false,
        lower: ?f64 = null,
        upper: ?f64 = null,
        rows: usize,
        first: f64,
        last: f64,
    };
    for ([_]Case{
        .{ .n = 73, .center = 0.3, .kind = .triangular, .c = 2.472, .rows = 309, .first = -0.8999999999999999, .last = 1.5 },
        .{ .n = 73, .center = 0.3, .kind = .triangular, .c = 2.472, .lower = 0.04999999999999999, .rows = 194, .first = 0, .last = 1.5 },
        .{ .n = 7, .center = -0.01, .kind = .triangular, .c = 4.056, .lower = -0.26, .upper = 4.99, .rows = 225, .first = -0.26000000000000006, .last = 1.480000000000001 },
        .{ .n = 8, .center = 0.01, .kind = .quadratic, .c = 2.737, .right = true, .lower = -0.24, .upper = 0.12, .rows = 49, .first = -0.24000000000000007, .last = 0.11999999999999998 },
        .{ .n = 73, .center = 0, .kind = .normal, .c = 3.662, .right = true, .lower = -1, .upper = 0.5, .rows = 259, .first = -1, .last = 1 },
    }) |case| {
        const x = try a.alloc(f64, case.n);
        @memset(x, case.center);
        const width = if (case.center == 0) 1 else @abs(case.center);
        const first = if (case.right) case.center - width else case.center;
        const endpoints = [_]f64{ first, first + width };
        const estimate: kernel.Estimate = .{ .request = .{ .kind = case.kind, .lower = case.lower, .upper = case.upper }, .bandwidth = case.c * std.math.pow(f64, @as(f64, @floatFromInt(case.n)), -0.2), .c = case.c, .amise = 0 };
        const plan = try make(a, &d, x, estimate, &endpoints, .{ .automatic = true, .endpoint_labels = true, .right = case.right, .clip_lower = true, .clip_upper = true, .bin_width = width });
        try std.testing.expectEqual(case.rows, plan.points.len);
        try std.testing.expectEqual(case.first, plan.points[0]);
        try std.testing.expectEqual(case.last, plan.points[plan.points.len - 1]);
    }
}

test "UNIVARIATE native Fourier coordinate rounding covers both sample parities and grid lengths" {
    // M9 OUTKERNEL _VALUE_ HEX16. on [-2.5, 0.8] with 8 or 9 observations.
    const cases = [_]struct { length: usize, odd: bool, bits: [6]u64 }{
        .{ .length = 256, .odd = true, .bits = .{ 0xc01064cccccccccd, 0xbfeb33333333333f, 0x4000b66666666668, 0x4002fb3333333334, 0x40032fffffffffff, 0x400364cccccccccc } },
        .{ .length = 512, .odd = true, .bits = .{ 0xc01d980000000000, 0xbfeb333333333357, 0x40158e6666666666, 0x4016b0cccccccccd, 0x4016cb3333333330, 0x4016e59999999996 } },
        .{ .length = 256, .odd = false, .bits = .{ 0xc01064cccccccccd, 0xbfeb333333333344, 0x4000b66666666663, 0x4002fb333333332e, 0x40032ffffffffffc, 0x400364ccccccccc8 } },
        .{ .length = 512, .odd = false, .bits = .{ 0xc01d980000000000, 0xbfeb33333333335c, 0x40158e666666665f, 0x4016b0ccccccccc5, 0x4016cb333333332c, 0x4016e59999999992 } },
    };
    var grid: [512]f64 = undefined;
    for (cases) |case| {
        const n = case.length;
        outputLattice(grid[0..n], -2.5, 0.8, case.odd, null);
        for ([_]usize{ 2, n / 2, n - 14, n - 3, n - 2, n - 1 }, case.bits) |i, expected| try std.testing.expectEqual(expected, @as(u64, @bitCast(grid[i])));
    }
}
