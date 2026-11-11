//! Allocator-backed Bernstein helpers for unconditional two-binomial tails.
//! The event indicator grid is a bivariate Bernstein polynomial. Restrict its
//! two axes to affine probability ranges, then substitute the same parameter
//! into both axes using normalized hypergeometric weights. Every intermediate
//! coefficient is a probability; no large binomial coefficients are formed.
//! This module neither selects tail tables nor owns a separate search budget.
const std = @import("std");
pub const Error = @import("../diag.zig").Error;
const A = std.mem.Allocator;

/// Pass the SAME caller-owned counter/deadline to construction, maximization,
/// and successive null-value inversions. false is sticky for this operation.
/// consume is called per tensor scan row, restriction/de Casteljau level,
/// diagonal, and subdivision node; enumeration remains the caller's charge.
pub const Control = struct {
    context: ?*anyopaque = null,
    consume: ?*const fn (?*anyopaque) bool = null,
    fn take(self: Control) bool {
        return if (self.consume) |f| f(self.context) else true;
    }
};
pub const Range = struct {
    lower: f64,
    upper: f64,
    fn valid(self: Range) bool {
        return std.math.isFinite(self.lower) and std.math.isFinite(self.upper) and self.lower >= 0 and self.upper <= 1 and self.lower <= self.upper;
    }
};
pub const Polynomial = struct {
    coefficients: []f64,
    pub fn deinit(self: Polynomial, a: A) void {
        a.free(self.coefficients);
    }
};
pub const BuildResult = union(enum) { complete: Polynomial, exhausted };
pub const Bounds = struct { lower: f64, upper: f64 };
pub const MaximumResult = union(enum) { complete: Bounds, exhausted };

fn blend(x: f64, y: f64, t: f64) f64 {
    // Preserve constants exactly and keep convex combinations in their hull.
    if (x == y) return x;
    return @min(@max(x, y), @max(@min(x, y), (1 - t) * x + t * y));
}
/// Restriction to [lower,upper], with degree unchanged. Right diagonal from
/// the lower split, then left diagonal from the rescaled upper split.
fn restrict(coeff: []f64, range: Range, scratch: []f64, control: Control) bool {
    const n = coeff.len - 1;
    if (range.lower == range.upper) {
        if (range.lower == 0 or range.lower == 1) {
            @memset(coeff, coeff[if (range.lower == 0) 0 else n]);
            return true;
        }
        @memcpy(scratch[0..coeff.len], coeff);
        for (1..coeff.len) |level| {
            if (!control.take()) return false;
            for (0..coeff.len - level) |i| scratch[i] = blend(scratch[i], scratch[i + 1], range.lower);
        }
        @memset(coeff, scratch[0]);
        return true;
    }
    if (range.lower > 0) {
        @memcpy(scratch[0..coeff.len], coeff);
        for (1..coeff.len) |level| {
            if (!control.take()) return false;
            for (0..coeff.len - level) |i| scratch[i] = blend(scratch[i], scratch[i + 1], range.lower);
            coeff[n - level] = scratch[n - level];
        }
    }
    if (range.upper < 1) {
        const t = (range.upper - range.lower) / (1 - range.lower);
        @memcpy(scratch[0..coeff.len], coeff);
        for (1..coeff.len) |level| {
            if (!control.take()) return false;
            for (0..coeff.len - level) |i| scratch[i] = blend(scratch[i], scratch[i + 1], t);
            coeff[level] = scratch[0];
        }
    }
    return true;
}
const Sum = struct {
    value: f64 = 0,
    correction: f64 = 0,
    fn add(self: *Sum, x: f64) void {
        const y = x - self.correction;
        const next = self.value + y;
        self.correction = (next - self.value) - y;
        self.value = next;
    }
};
fn real(n: usize) f64 {
    return @floatFromInt(n);
}
/// selected[x*(n2+1)+y] indicates membership in the requested tail. n1/n2
/// may be zero (constant binomial); the risk caller enforces its own margins.
/// Exhaustion discards all workspace; no partial polynomial is returned.
pub fn build(a: A, n1: usize, n2: usize, selected: []const bool, p1: Range, p2: Range, control: Control) Error!BuildResult {
    if (!p1.valid() or !p2.valid()) return error.ExecError;
    const rows = std.math.add(usize, n1, 1) catch return error.ExecError;
    const cols = std.math.add(usize, n2, 1) catch return error.ExecError;
    const count = std.math.mul(usize, rows, cols) catch return error.ExecError;
    const degree = std.math.add(usize, n1, n2) catch return error.ExecError;
    const length = std.math.add(usize, degree, 1) catch return error.ExecError;
    if (selected.len != count) return error.ExecError;
    if (!control.take()) return .exhausted;
    const tensor = try a.alloc(f64, count);
    defer a.free(tensor);
    for (0..rows) |x| {
        if (!control.take()) return .exhausted;
        for (0..cols) |y| tensor[x * cols + y] = if (selected[x * cols + y]) 1 else 0;
    }
    const scratch = try a.alloc(f64, @max(rows, cols));
    defer a.free(scratch);
    const line = try a.alloc(f64, rows);
    defer a.free(line);
    for (0..cols) |y| {
        if (!control.take()) return .exhausted;
        for (0..rows) |x| line[x] = tensor[x * cols + y];
        if (!restrict(line, p1, scratch, control)) return .exhausted;
        for (0..rows) |x| tensor[x * cols + y] = line[x];
    }
    for (0..rows) |x| {
        if (!control.take()) return .exhausted;
        if (!restrict(tensor[x * cols ..][0..cols], p2, scratch, control)) return .exhausted;
    }
    const coeff = try a.alloc(f64, length);
    var transferred = false;
    defer if (!transferred) a.free(coeff);
    for (0..length) |k| {
        if (!control.take()) return .exhausted;
        const lo = k -| n2;
        const hi = @min(k, n1);
        // Mode of Hypergeometric(N,n1,k); use floating products to avoid
        // integer overflow. Starting at a mode prevents exponential weights.
        const mode: usize = @intFromFloat(@max(real(lo), @min(real(hi), @floor((real(k) + 1) / (real(degree) + 2) * (real(n1) + 1)))));
        var mass = Sum{};
        var value = Sum{};
        mass.add(1);
        value.add(tensor[mode * cols + k - mode]);
        var weight: f64 = 1;
        var i = mode;
        while (i < hi) : (i += 1) {
            weight *= (real(n1 - i) / real(i + 1)) * (real(k - i) / real(n2 - (k - i) + 1));
            mass.add(weight);
            value.add(weight * tensor[(i + 1) * cols + k - i - 1]);
        }
        weight = 1;
        i = mode;
        while (i > lo) : (i -= 1) {
            weight *= (real(i) / real(n1 - i + 1)) * (real(n2 - (k - i)) / real(k - i + 1));
            mass.add(weight);
            value.add(weight * tensor[(i - 1) * cols + k - i + 1]);
        }
        coeff[k] = @max(0, @min(1, value.value / mass.value));
    }
    transferred = true;
    return .{ .complete = .{ .coefficients = coeff } };
}

const Node = struct { coefficients: []f64, upper: f64 };
fn push(a: A, heap: *std.ArrayList(Node), node: Node) Error!void {
    try heap.append(a, node);
    var i = heap.items.len - 1;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (heap.items[parent].upper >= heap.items[i].upper) break;
        std.mem.swap(Node, &heap.items[parent], &heap.items[i]);
        i = parent;
    }
}
fn pop(heap: *std.ArrayList(Node)) Node {
    const result = heap.items[0];
    const last = heap.pop().?;
    if (heap.items.len == 0) return result;
    heap.items[0] = last;
    var i: usize = 0;
    while (i < heap.items.len / 2) {
        var next = i * 2 + 1;
        if (next + 1 < heap.items.len and heap.items[next + 1].upper > heap.items[next].upper) next += 1;
        if (heap.items[i].upper >= heap.items[next].upper) break;
        std.mem.swap(Node, &heap.items[i], &heap.items[next]);
        i = next;
    }
    return result;
}
fn largest(coeff: []const f64) f64 {
    var result: f64 = 0;
    for (coeff) |c| result = @max(result, c);
    return result;
}
/// Convex-hull subdivision bounds the maximum on [0,1], apart from floating
/// roundoff. Coefficients stay bounded throughout. The dynamic priority queue
/// replaces recursion and fixed degree/depth arrays; caller work/deadline and
/// allocator failures are the resource limits. No partial p-value on exhaustion.
pub fn maximize(a: A, coefficients: []const f64, tolerance: f64, control: Control) Error!MaximumResult {
    if (coefficients.len == 0 or !(tolerance > 0 and tolerance < 1)) return error.ExecError;
    for (coefficients) |c| if (!std.math.isFinite(c) or c < 0 or c > 1) return error.ExecError;
    if (!control.take()) return .exhausted;
    var heap: std.ArrayList(Node) = .empty;
    defer {
        for (heap.items) |node| a.free(node.coefficients);
        heap.deinit(a);
    }
    const copy = try a.dupe(f64, coefficients);
    push(a, &heap, .{ .coefficients = copy, .upper = largest(copy) }) catch |err| {
        a.free(copy);
        return err;
    };
    const scratch = try a.alloc(f64, coefficients.len);
    defer a.free(scratch);
    var best = @max(coefficients[0], coefficients[coefficients.len - 1]);
    while (heap.items.len > 0) {
        if (!control.take()) return .exhausted;
        const node = pop(&heap);
        defer a.free(node.coefficients);
        if (node.upper - best <= tolerance) return .{ .complete = .{ .lower = best, .upper = @max(best, node.upper) } };
        const left = try a.alloc(f64, coefficients.len);
        var left_owned = true;
        defer if (left_owned) a.free(left);
        const right = try a.alloc(f64, coefficients.len);
        var right_owned = true;
        defer if (right_owned) a.free(right);
        @memcpy(scratch, node.coefficients);
        left[0] = scratch[0];
        right[right.len - 1] = scratch[scratch.len - 1];
        for (1..coefficients.len) |level| {
            if (!control.take()) return .exhausted;
            for (0..coefficients.len - level) |i| scratch[i] = blend(scratch[i], scratch[i + 1], 0.5);
            left[level] = scratch[0];
            right[right.len - level - 1] = scratch[right.len - level - 1];
        }
        best = @max(best, left[left.len - 1]);
        const upper_left = largest(left);
        const upper_right = largest(right);
        if (upper_left > best) {
            try push(a, &heap, .{ .coefficients = left, .upper = upper_left });
            left_owned = false;
        }
        if (upper_right > best) {
            try push(a, &heap, .{ .coefficients = right, .upper = upper_right });
            right_owned = false;
        }
    }
    return .{ .complete = .{ .lower = best, .upper = best } };
}

// Test-only direct evaluation, independent of the diagonal construction.
fn evaluate(a: A, coefficients: []const f64, t: f64) !f64 {
    const scratch = try a.dupe(f64, coefficients);
    defer a.free(scratch);
    for (1..coefficients.len) |level| for (0..coefficients.len - level) |i| {
        scratch[i] = (1 - t) * scratch[i] + t * scratch[i + 1];
    };
    return scratch[0];
}
fn smallPmf(n: usize, k: usize, p: f64) f64 {
    var choose: f64 = 1;
    for (0..k) |i| choose *= real(n - i) / real(i + 1);
    return choose * std.math.pow(f64, p, real(k)) * std.math.pow(f64, 1 - p, real(n - k));
}

test "exact polynomial affine restriction agrees with independent two-binomial sum" {
    const a = std.testing.allocator;
    const n1 = 3;
    const n2 = 5;
    var selected: [24]bool = undefined;
    for (0..4) |x| for (0..6) |y| {
        selected[x * 6 + y] = 5 * x >= 3 * y + 2;
    };
    const ranges = [_][2]Range{
        .{ .{ .lower = 0, .upper = 1 }, .{ .lower = 0, .upper = 1 } },
        .{ .{ .lower = 0.2, .upper = 1 }, .{ .lower = 0, .upper = 0.8 } },
        .{ .{ .lower = 0, .upper = 1 }, .{ .lower = 0, .upper = 0.5 } },
        .{ .{ .lower = 0.125, .upper = 0.75 }, .{ .lower = 0.25, .upper = 0.875 } },
        .{ .{ .lower = 0.3, .upper = 0.3 }, .{ .lower = 0.6, .upper = 0.6 } },
    };
    for (ranges) |range| {
        const polynomial = (try build(a, n1, n2, &selected, range[0], range[1], .{})).complete;
        defer polynomial.deinit(a);
        for ([_]f64{ 0, 0.01, 0.2, 0.5, 0.9, 1 }) |t| {
            const p1 = range[0].lower + t * (range[0].upper - range[0].lower);
            const p2 = range[1].lower + t * (range[1].upper - range[1].lower);
            var expected: f64 = 0;
            for (0..n1 + 1) |x| for (0..n2 + 1) |y| {
                if (selected[x * (n2 + 1) + y]) expected += smallPmf(n1, x, p1) * smallPmf(n2, y, p2);
            };
            try std.testing.expectApproxEqAbs(expected, try evaluate(a, polynomial.coefficients, t), 2e-14);
        }
    }
}

test "exact polynomial maximum preserves certified small-case risk tail precision" {
    const old = @import("freq_exact_unconditional.zig");
    const risk = @import("freq_risk.zig");
    const a = std.testing.allocator;
    const cases = [_]struct { cells: [4]f64, family: old.Family, null_value: f64, side: old.Side }{
        .{ .cells = .{ 0, 3, 2, 1 }, .family = .difference, .null_value = 0, .side = .two_sided },
        .{ .cells = .{ 1, 3, 3, 1 }, .family = .difference, .null_value = 0.2, .side = .left },
        .{ .cells = .{ 2, 3, 1, 4 }, .family = .relative_risk, .null_value = 2, .side = .right },
    };
    for (cases) |c| {
        const table = risk.Table2x2{ .cells = c.cells };
        const n1: usize = @intFromFloat(c.cells[0] + c.cells[1]);
        const n2: usize = @intFromFloat(c.cells[2] + c.cells[3]);
        const observed = if (c.family == .difference) try risk.differenceScore(table, .first, c.null_value, false) else try risk.relativeRiskScore(table, .first, c.null_value, false);
        const selected = try a.alloc(bool, (n1 + 1) * (n2 + 1));
        defer a.free(selected);
        for (0..n1 + 1) |x| for (0..n2 + 1) |y| {
            const candidate = risk.Table2x2{ .cells = .{ real(x), real(n1 - x), real(y), real(n2 - y) } };
            const score = if (c.family == .difference) try risk.differenceScore(candidate, .first, c.null_value, false) else try risk.relativeRiskScore(candidate, .first, c.null_value, false);
            selected[x * (n2 + 1) + y] = switch (c.side) {
                .left => score <= observed + 1e-12,
                .right => score >= observed - 1e-12,
                .two_sided => @abs(score) >= @abs(observed) - 1e-12,
            };
        };
        const p2 = if (c.family == .difference) Range{ .lower = @max(0, -c.null_value), .upper = @min(1, 1 - c.null_value) } else Range{ .lower = 0, .upper = @min(1, 1 / c.null_value) };
        const p1 = if (c.family == .difference) Range{ .lower = p2.lower + c.null_value, .upper = p2.upper + c.null_value } else Range{ .lower = 0, .upper = p2.upper * c.null_value };
        const polynomial = (try build(a, n1, n2, selected, p1, p2, .{})).complete;
        defer polynomial.deinit(a);
        const result = (try maximize(a, polynomial.coefficients, 1e-12, .{})).complete;
        const reference = (try old.riskTail(table, .first, c.family, .score, c.null_value, c.side, .{ .tolerance = 1e-12 })).complete;
        try std.testing.expect(result.upper - result.lower <= 1e-12);
        try std.testing.expectApproxEqAbs(reference.lower, result.lower, 2e-12);
        try std.testing.expectApproxEqAbs(reference.upper, result.upper, 2e-12);
        if (c.null_value == 0) {
            // SAS/STAT p194: [0,3;2,1] Barnard's two-sided p=7/32.
            try std.testing.expectApproxEqAbs(@as(f64, 0.21875), result.lower, 1e-13);
        }
    }
}

test "exact polynomial supports 260 outcomes above former total N128 ceiling" {
    const a = std.testing.allocator;
    var selected: [260]bool = @splat(false);
    // Under RD=0 the extreme right-tail event is X=1,Y=0; F=p(1-p)^129.
    // Its maximum occurs at p=1/130. No enumeration or degree cutoff.
    selected[130] = true;
    const range = Range{ .lower = 0, .upper = 1 };
    var work = TestWork{};
    const polynomial = (try build(a, 1, 129, &selected, range, range, work.control())).complete;
    defer polynomial.deinit(a);
    try std.testing.expectEqual(@as(usize, 131), polynomial.coefficients.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 130.0), polynomial.coefficients[1], 1e-17);
    for (polynomial.coefficients, 0..) |v, i| if (i != 1) try std.testing.expectEqual(@as(f64, 0), v);
    const result = (try maximize(a, polynomial.coefficients, 1e-13, work.control())).complete;
    // SAS/STAT p194, independent command:
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-risk/polynomial/large-tail.sas
    // -f text -o sibling.txt -l sibling.log. N=130, one/two-sided p=.0028.
    // SAS BEST32 maximization gives .00284077351313, about 1.43e-9 below
    // the analytic supremum; do not weaken the independent bound check.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0028), result.lower, 0.00005);
    // Independent Python (1/130)*(129/130)**129 = .0028407749435880154.
    try std.testing.expect(result.lower <= 0.0028407749435880154 + 2e-16);
    try std.testing.expect(result.upper >= 0.0028407749435880154 - 2e-16);
    try std.testing.expect(result.upper - result.lower <= 1e-13);
    // RR=2: p1=t,p2=t/2. The maximizer is inside the restricted range,
    // and the supremum is twice that of the RD=0 event above.
    const rr = (try build(a, 1, 129, &selected, range, .{ .lower = 0, .upper = 0.5 }, work.control())).complete;
    defer rr.deinit(a);
    const rr_max = (try maximize(a, rr.coefficients, 1e-13, work.control())).complete;
    try std.testing.expectApproxEqAbs(@as(f64, 0.005681549887176031), rr_max.lower, 1e-13);
    try std.testing.expect(rr_max.upper - rr_max.lower <= 1e-13);
    // Barnard's two-sided event adds the reflected extreme outcome. Both
    // maxima must be retained by the global queue, not just one local branch.
    selected[129] = true;
    const two = (try build(a, 1, 129, &selected, range, range, work.control())).complete;
    defer two.deinit(a);
    const two_max = (try maximize(a, two.coefficients, 1e-13, work.control())).complete;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0028407749435880154), two_max.lower, 1e-13);
    try std.testing.expect(two_max.upper - two_max.lower <= 1e-13);
}

test "exact polynomial avoids overflowing central binomial coefficients" {
    const a = std.testing.allocator;
    const selected = try a.alloc(bool, 2 * 2049);
    defer a.free(selected);
    @memset(selected, false);
    selected[1024] = true;
    // C(2048,1024) cannot be represented in f64. The restricted event
    // probability is nevertheless ordinary-sized and must remain finite.
    const polynomial = (try build(a, 1, 2048, selected, .{ .lower = 0.25, .upper = 0.25 }, .{ .lower = 0.5, .upper = 0.5 }, .{})).complete;
    defer polynomial.deinit(a);
    const result = (try maximize(a, polynomial.coefficients, 1e-13, .{})).complete;
    // Python exact integers: .75 * math.comb(2048,1024)/(1<<2048).
    try std.testing.expectApproxEqAbs(@as(f64, 0.013221579303634889), result.lower, 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.013221579303634889), result.upper, 1e-15);
}

const TestWork = struct {
    budget: @import("freq_exact_distribution.zig").Budget = .{},
    used: u64 = 0,
    fn consume(raw: ?*anyopaque) bool {
        const self: *TestWork = @ptrCast(@alignCast(raw.?));
        if (self.used >= self.budget.max_tables or self.budget.stopped()) return false;
        self.used += 1;
        return true;
    }
    fn control(self: *TestWork) Control {
        return .{ .context = self, .consume = consume };
    }
};
fn expired(_: ?*const anyopaque) bool {
    return true;
}
test "exact polynomial shares work budget and cancellation without partial results" {
    const a = std.testing.allocator;
    const range = Range{ .lower = 0, .upper = 1 };
    var work = TestWork{ .budget = .{ .max_tables = 2 } };
    try std.testing.expect((try build(a, 1, 1, &.{ false, false, true, false }, range, range, work.control())) == .exhausted);
    work = .{ .budget = .{ .max_tables = 10 } };
    try std.testing.expect((try build(a, 2, 2, &.{ false, false, true, false, true, true, true, true, false }, .{ .lower = 0.1, .upper = 0.8 }, .{ .lower = 0.2, .upper = 0.9 }, work.control())) == .exhausted);
    work = .{};
    const polynomial = (try build(a, 1, 1, &.{ false, false, true, false }, range, range, work.control())).complete;
    defer polynomial.deinit(a);
    work.budget.max_tables = work.used; // maximum must not reset construction's work
    try std.testing.expect((try maximize(a, polynomial.coefficients, 1e-12, work.control())) == .exhausted);
    work = .{ .budget = .{ .max_tables = 3 } };
    try std.testing.expect((try maximize(a, polynomial.coefficients, 1e-12, work.control())) == .exhausted);
    work = .{ .budget = .{ .expired = expired } };
    try std.testing.expect((try build(a, 1, 1, &.{ false, false, true, false }, range, range, work.control())) == .exhausted);
    try std.testing.expect((try maximize(a, polynomial.coefficients, 1e-12, work.control())) == .exhausted);
}
fn allocationProbe(a: A) !void {
    const polynomial = (try build(a, 2, 2, &.{ false, false, true, false, true, true, true, true, false }, .{ .lower = 0.1, .upper = 0.8 }, .{ .lower = 0.2, .upper = 0.9 }, .{})).complete;
    defer polynomial.deinit(a);
    try std.testing.expect((try maximize(a, polynomial.coefficients, 1e-10, .{})) == .complete);
}
test "exact polynomial allocation failure paths release construction and search workspace" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "exact polynomial validates shape and probability domains" {
    const a = std.testing.allocator;
    const range = Range{ .lower = 0, .upper = 1 };
    try std.testing.expectError(error.ExecError, build(a, 1, 1, &.{true}, range, range, .{}));
    try std.testing.expectError(error.ExecError, build(a, 0, 0, &.{true}, .{ .lower = 0.9, .upper = 0.1 }, range, .{}));
    try std.testing.expectError(error.ExecError, maximize(a, &.{ 0, std.math.nan(f64) }, 1e-10, .{}));
    try std.testing.expectError(error.ExecError, maximize(a, &.{ 0, 1 }, 0, .{}));
    const constant = (try build(a, 0, 0, &.{true}, range, range, .{})).complete;
    defer constant.deinit(a);
    const result = (try maximize(a, constant.coefficients, 1e-13, .{})).complete;
    try std.testing.expectEqual(@as(f64, 1), result.lower);
    try std.testing.expectEqual(@as(f64, 1), result.upper);
}
