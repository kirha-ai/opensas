//! Automatic histogram intervals: Terrell–Scott initial count and SAS's
//! preferred decimal widths. Explicit interval counting is in values.zig.
const std = @import("std");
const diag = @import("../diag.zig");

pub const Mode = enum { key, uniform };
pub const Cell = struct { sorted: []const f64 };
pub const Request = struct {
    endpoints: bool = false,
    right: bool = false,
    mode: Mode = .key,
    key_index: usize = 0,
    key_move: bool = true,
    /// NMIDPOINTS/NENDPOINTS is a target for nice axis values, not a promise
    /// that the final occupied output has exactly this many intervals.
    target_count: ?usize = null,
    max_nbin: ?usize = null,
    max_sigmas: ?f64 = null,
    /// Resource budget, independently configurable by the owning caller.
    max_intervals: usize = 100000,
};
pub const Plan = struct {
    endpoints: []const f64,
    width: f64,
    mode: Mode,
    empty_key_fallback: bool = false,
    constant: ?f64 = null,
    clipped: bool = false,
    cell_order: []const usize = &.{},
};

/// Backward-compatible single-cell entry point. The returned values are bin
/// boundaries even when the caller requests midpoint labels.
pub fn automatic(a: std.mem.Allocator, d: *diag.Diagnostics, sorted: []const f64, endpoints: bool, right: bool) diag.Error![]f64 {
    const result = try determine(a, d, &.{.{ .sorted = sorted }}, .{ .endpoints = endpoints, .right = right });
    return @constCast(result.endpoints);
}

pub fn determine(a: std.mem.Allocator, d: *diag.Diagnostics, cells: []const Cell, request: Request) diag.Error!Plan {
    if (request.max_nbin != null and request.max_sigmas != null) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXNBIN and MAXSIGMAS are alternatives", .{});
    if (request.max_nbin != null and request.max_nbin.? == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXNBIN must be positive", .{});
    if (request.max_sigmas) |v| if (!(v > 0) or !std.math.isFinite(v)) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXSIGMAS must be finite and positive", .{});
    var total: usize = 0;
    var minimum = std.math.inf(f64);
    var maximum = -std.math.inf(f64);
    for (cells) |cell| {
        for (cell.sorted, 0..) |v, i| {
            if (!std.math.isFinite(v) or (i > 0 and v < cell.sorted[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: automatic bins require sorted finite cells", .{});
        }
        total = std.math.add(usize, total, cell.sorted.len) catch return error.OutOfMemory;
        if (cell.sorted.len > 0) {
            minimum = @min(minimum, cell.sorted[0]);
            maximum = @max(maximum, cell.sorted[cell.sorted.len - 1]);
        }
    }
    if (total == 0) return .{ .endpoints = &.{}, .width = 0, .mode = request.mode };
    if (request.key_index >= cells.len) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid resolved key cell index", .{});
    var target = request.target_count;
    if (target != null and target.? < 2) {
        try d.warn(0, "UNIVARIATE: histogram count control must be at least 2; ignoring the specified value", .{});
        target = null;
    }
    const key = cells[request.key_index].sorted;
    const pooled = request.mode == .uniform or key.len == 0 or target != null;
    if (request.mode == .key and key.len == 0 and target == null) try d.warn(0, "UNIVARIATE: empty key cell; using UNIFORM bin selection", .{});
    const lo = if (pooled) minimum else key[0];
    const hi = if (pooled) maximum else key[key.len - 1];
    const n = if (pooled) total else key.len;
    var width: f64 = undefined;
    if (lo == hi) {
        width = if (lo == 0) 1 else @abs(lo);
    } else if (target) |count| {
        width = try controlledWidth(d, minimum, maximum, count);
    } else {
        const count = @ceil(std.math.cbrt(2 * @as(f64, @floatFromInt(n))));
        width = preferred((hi - lo) / count, false);
    }
    if (!(width > 0) or !std.math.isFinite(width)) return d.fail(error.ParseError, 0, "UNIVARIATE: automatic bin width is not representable", .{});
    var first: f64 = undefined;
    var last: f64 = undefined;
    if (lo == hi) {
        first = if (!request.endpoints) lo - width / 2 else if (request.right) lo - width else lo;
        last = first + width;
    } else if (request.endpoints) {
        first = if (request.right) (ceilNear(lo / width) - 1) * width else floorNear(lo / width) * width;
        last = if (request.right) ceilNear(hi / width) * width else (floorNear(hi / width) + 1) * width;
    } else if (target != null) {
        first = floorNear(lo / width) * width - width / 2;
        last = ceilNear(hi / width) * width + width / 2;
    } else {
        const zero_first = floorNear(lo / width + 0.5) * width;
        const zero_last = floorNear(hi / width + 0.5) * width;
        const half_first = (floorNear(lo / width) + 0.5) * width;
        const half_last = (floorNear(hi / width) + 0.5) * width;
        const zero_count = @round((zero_last - zero_first) / width) + 1;
        const half_count = @round((half_last - half_first) / width) + 1;
        const center = lo / 2 + hi / 2;
        const zero_error = @abs((zero_first / 2 + zero_last / 2) - center);
        const half_error = @abs((half_first / 2 + half_last / 2) - center);
        const use_half = half_count < zero_count or (half_count == zero_count and half_error < zero_error - 16 * std.math.floatEps(f64) * @max(@as(f64, 1), @abs(center)));
        first = (if (use_half) half_first else zero_first) - width / 2;
        last = (if (use_half) half_last else zero_last) + width / 2;
    }
    // Extend the key's existing lattice in caller-supplied cell order. Window
    // limits never remove the key's initial intervals. ENDPOINTS controls count
    // their endpoint list (including its final point), not midpoint intervals.
    var slots = @round((last - first) / width) + (if (request.endpoints) @as(f64, 1) else 0);
    const max_slots = if (request.max_nbin) |v| @max(slots, @as(f64, @floatFromInt(v))) else std.math.inf(f64);
    var lower_limit = -std.math.inf(f64);
    var upper_limit = std.math.inf(f64);
    if (request.max_sigmas) |sigmas| {
        const norm = if (hi > lo) hi - lo else 1;
        var sum: f64 = 0;
        var nn: usize = 0;
        for (cells, 0..) |cell, idx| if (pooled or idx == request.key_index) {
            for (cell.sorted) |v| {
                sum += (v - lo) / norm;
                nn += 1;
            }
        };
        const scaled_mean = sum / @as(f64, @floatFromInt(nn));
        const mean = lo + norm * scaled_mean;
        var ss: f64 = 0;
        for (cells, 0..) |cell, idx| if (pooled or idx == request.key_index) {
            for (cell.sorted) |v| {
                const delta = (v - lo) / norm - scaled_mean;
                ss += delta * delta;
            }
        };
        const sd = if (nn > 1) norm * @sqrt(ss / @as(f64, @floatFromInt(nn - 1))) else 0;
        lower_limit = mean - sigmas * sd;
        upper_limit = mean + sigmas * sd;
    }
    for (cells) |cell| {
        if (cell.sorted.len == 0) continue;
        const cell_min = cell.sorted[0];
        const cell_max = cell.sorted[cell.sorted.len - 1];
        const first_label = if (request.endpoints) first else first + width / 2;
        const last_label = if (request.endpoints) last else last - width / 2;
        var below = if (cell_min < first or (request.right and cell_min == first)) @max(@as(f64, 1), @ceil((first - cell_min) / width)) else 0;
        below = @min(below, @max(@as(f64, 0), max_slots - slots));
        if (std.math.isFinite(lower_limit)) below = @min(below, @max(@as(f64, 0), @floor((first_label - lower_limit) / width + 1e-12)));
        first -= below * width;
        slots += below;
        var above = if (cell_max > last or (!request.right and cell_max == last)) @max(@as(f64, 1), @ceil((cell_max - last) / width)) else 0;
        above = @min(above, @max(@as(f64, 0), max_slots - slots));
        if (std.math.isFinite(upper_limit)) above = @min(above, @max(@as(f64, 0), @floor((upper_limit - last_label) / width + 1e-12)));
        last += above * width;
        slots += above;
    }

    const order = try a.alloc(usize, cells.len);
    var at: usize = 0;
    if (request.key_move) {
        order[0] = request.key_index;
        at = 1;
    }
    for (0..cells.len) |index| {
        if (request.key_move and index == request.key_index) continue;
        order[at] = index;
        at += 1;
    }
    return .{ .cell_order = order, .endpoints = try lattice(a, d, first, last, width, request.max_intervals), .width = width, .mode = if (pooled) .uniform else .key, .empty_key_fallback = request.mode == .key and key.len == 0 and target == null, .clipped = (request.max_nbin != null or request.max_sigmas != null) and (minimum < first or maximum > last or (request.right and minimum == first) or (!request.right and maximum == last)), .constant = if (minimum == maximum) minimum else null };
}

fn floorNear(value: f64) f64 {
    const integer = @round(value);
    return @floor(if (@abs(value - integer) <= 16 * std.math.floatEps(f64) * @max(@as(f64, 1), @abs(value))) integer else value);
}
fn ceilNear(value: f64) f64 {
    return -floorNear(-value);
}

fn preferred(initial: f64, ceiling: bool) f64 {
    if (!(initial > 0) or !std.math.isFinite(initial)) return std.math.nan(f64);
    const unit = std.math.pow(f64, 10, @floor(@log10(initial)));
    if (ceiling) {
        for ([_]f64{ 1, 2, 2.5, 5, 10 }) |factor| if (factor * unit >= initial * (1 - 1e-14)) return factor * unit;
        return 10 * unit;
    }
    var width = unit;
    for ([_]f64{ 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8 }) |factor| if (factor * unit <= initial * (1 + 1e-14)) {
        width = factor * unit;
    };
    return width;
}
fn controlledWidth(d: *diag.Diagnostics, lo: f64, hi: f64, count: usize) diag.Error!f64 {
    var width = preferred((hi - lo) / @as(f64, @floatFromInt(count - 1)), true);
    for (0..32) |_| {
        if (!(width > 0) or !std.math.isFinite(width)) break;
        const ticks = @round(ceilNear(hi / width) - floorNear(lo / width)) + 1;
        if (ticks <= @as(f64, @floatFromInt(count))) return width;
        width = preferred(width * (1 + 1e-10), true);
    }
    return d.fail(error.ParseError, 0, "UNIVARIATE: count-controlled bin width is not representable", .{});
}
fn lattice(a: std.mem.Allocator, d: *diag.Diagnostics, first: f64, last: f64, width: f64, limit: usize) diag.Error![]f64 {
    const count = @round((last - first) / width);
    if (!std.math.isFinite(first) or !std.math.isFinite(last) or !(count >= 1) or count > @as(f64, @floatFromInt(limit))) return d.fail(error.ParseError, 0, "UNIVARIATE: bin grid exceeds its numeric or allocation limit", .{});
    const intervals: usize = @intFromFloat(count);
    const result = try a.alloc(f64, intervals + 1);
    for (result, 0..) |*v, i| {
        v.* = first + @as(f64, @floatFromInt(i)) * width;
        if (i > 0 and !(v.* > result[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: bin grid exceeds floating-point resolution", .{});
    }
    return result;
}

test "UNIVARIATE automatic bin widths and midpoint phase SAS M9" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    for ([_]usize{ 2, 3, 8, 20, 100, 1000 }, [_]f64{ 0.5, 0.5, 0.3, 0.25, 0.15, 0.06 }, [_]f64{ 0, 0, 0, 0, 0.075, 0.03 }) |n, width, midpoint| {
        const x = try a.alloc(f64, n);
        for (x, 0..) |*v, i| v.* = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        const bins = try automatic(a, &d, x, false, false);
        try std.testing.expectApproxEqAbs(width, bins[1] - bins[0], 1e-12);
        try std.testing.expectApproxEqAbs(midpoint, (bins[0] + bins[1]) / 2, 1e-12);
        const ends = try automatic(a, &d, x, true, false);
        try std.testing.expectApproxEqAbs(@as(f64, 0), ends[0], 1e-12);
    }
    const bins = try automatic(a, &d, &.{ 1, 2, 3, 4, 6, 8, 10, 15 }, false, false);
    try std.testing.expectEqualSlices(f64, &.{ 0, 4, 8, 12, 16 }, bins);
}

/// Validate and extend an explicit boundary lattice using its supplied phase.
/// M9 warns, rather than dropping the boundary observations, when a supplied
/// endpoint list needs extension (including its open endpoint).
pub fn cover(a: std.mem.Allocator, d: *diag.Diagnostics, sorted: []const f64, supplied: []const f64, right: bool) diag.Error![]const f64 {
    if (supplied.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram needs two boundary values", .{});
    const width = supplied[1] - supplied[0];
    if (!(width > 0) or !std.math.isFinite(width) or !std.math.isFinite(supplied[0])) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid histogram boundary lattice", .{});
    for (supplied[1..], 1..) |v, i| if (!std.math.isFinite(v) or @abs((v - supplied[i - 1]) - width) > 1e-10 * width) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram boundaries must be equally spaced", .{});
    if (sorted.len == 0) return supplied;
    var first = supplied[0];
    var last = supplied[supplied.len - 1];
    if (sorted[0] < first or (right and sorted[0] == first)) first -= @max(@as(f64, 1), @ceil((first - sorted[0]) / width)) * width;
    if (sorted[sorted.len - 1] > last or (!right and sorted[sorted.len - 1] == last)) last += @max(@as(f64, 1), @ceil((sorted[sorted.len - 1] - last) / width)) * width;
    if (first == supplied[0] and last == supplied[supplied.len - 1]) return supplied;
    try d.warn(0, "UNIVARIATE: histogram interval list extended to accommodate the data", .{});
    return lattice(a, d, first, last, width, 100000);
}

test "dev3 constant and shared bin plans preserve KEY UNIFORM counts and windows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    for ([_]f64{ 0, 0.01, 1, -1, 10, 1234, 12.345 }) |value| {
        for ([_]bool{ false, true }) |endpoints| for ([_]bool{ false, true }) |right| {
            const plan = try determine(a, &d, &.{.{ .sorted = &.{ value, value } }}, .{ .endpoints = endpoints, .right = right });
            const at = if (!endpoints) (plan.endpoints[0] + plan.endpoints[1]) / 2 else if (right) plan.endpoints[1] else plan.endpoints[0];
            try std.testing.expectApproxEqAbs(value, at, 1e-12);
            try std.testing.expectEqual(if (value == 0) @as(f64, 1) else @abs(value), plan.width);
        };
    }
    const first = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    var second: [100]f64 = undefined;
    for (&second, 0..) |*v, i| v.* = 20 + @as(f64, @floatFromInt(i)) / 99;
    const cells = [_]Cell{ .{ .sorted = &first }, .{ .sorted = &second } };
    const key = try determine(a, &d, &cells, .{});
    try std.testing.expectEqual(@as(f64, 4), key.width);
    try std.testing.expectEqualSlices(f64, &.{ 0, 4, 8, 12, 16, 20, 24 }, key.endpoints);
    const uniform = try determine(a, &d, &cells, .{ .mode = .uniform });
    try std.testing.expectEqual(@as(f64, 3), uniform.width);
    const alternate = try determine(a, &d, &cells, .{ .key_index = 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), alternate.width, 1e-14);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, alternate.cell_order);
    const empty = try determine(a, &d, &.{ .{ .sorted = &.{} }, .{ .sorted = &first } }, .{});
    try std.testing.expect(empty.empty_key_fallback and empty.mode == .uniform);
    const controlled = try determine(a, &d, &cells, .{ .target_count = 5 });
    try std.testing.expectEqual(@as(f64, 10), controlled.width);
    var key_sample: [21]f64 = undefined;
    for (&key_sample, 0..) |*v, i| v.* = -1 + @as(f64, @floatFromInt(i)) / 10;
    const window = try determine(a, &d, &.{ .{ .sorted = &key_sample }, .{ .sorted = &.{ 3, 4 } }, .{ .sorted = &.{ -4, -3 } } }, .{ .max_nbin = 7 });
    try std.testing.expect(window.clipped);
    try std.testing.expectApproxEqAbs(@as(f64, -1.25), window.endpoints[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.25), window.endpoints[window.endpoints.len - 1], 1e-12);
    const sigmas = try determine(a, &d, &.{ .{ .sorted = &key_sample }, .{ .sorted = &.{ -4, 4 } } }, .{ .max_sigmas = 3 });
    try std.testing.expectApproxEqAbs(@as(f64, -1.75), sigmas.endpoints[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.75), sigmas.endpoints[sigmas.endpoints.len - 1], 1e-12);
    try std.testing.expectError(error.ParseError, determine(a, &d, &cells, .{ .max_nbin = 5, .max_sigmas = 2 }));
    try std.testing.expectError(error.ParseError, determine(a, &d, &cells, .{ .max_nbin = 0 }));
    try std.testing.expectError(error.ParseError, determine(a, &d, &.{.{ .sorted = &.{ 2, 1 } }}, .{}));
    try std.testing.expectError(error.ParseError, cover(a, &d, &first, &.{ 0, 5, 12 }, false));
}
