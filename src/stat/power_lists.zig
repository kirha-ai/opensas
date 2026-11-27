//! POWER scalar scenario lists: S154 physical p.7850. Number lists are DATA
//! step DOLISTs or a single missing result indicator, not a mixed list.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const maximum_scenarios: usize = 10000;
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, name);
}
fn numeric(t: []const lex.Token, i: usize) bool {
    return at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus);
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize, comptime message: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC POWER: " ++ message, .{});
}
fn scalar(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*, "expected a number");
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*, "invalid numeric literal");
    if (!std.math.isFinite(x)) return invalid(cx, t, i.*, "numeric list values must be finite");
    i.* += 1;
    return sign * x;
}
pub fn numbers(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const ?f64 {
    var result: std.ArrayList(?f64) = .empty;
    if (at(t, i.*, .dot)) {
        i.* += 1;
        if (numeric(t, i.*) or at(t, i.*, .dot) or kw(t, i.*, "to") or kw(t, i.*, "by")) return invalid(cx, t, i.*, "a missing result indicator cannot be mixed with numeric values");
        return &.{null};
    }
    while (numeric(t, i.*)) {
        const start = try scalar(cx, t, i);
        if (kw(t, i.*, "to")) {
            i.* += 1;
            const end = try scalar(cx, t, i);
            var step: f64 = 1;
            if (kw(t, i.*, "by")) {
                i.* += 1;
                step = try scalar(cx, t, i);
            }
            if (step == 0) return invalid(cx, t, i.*, "DOLIST BY increment cannot be zero");
            const quotient = (end - start) / step;
            if (!std.math.isFinite(quotient) or quotient > @as(f64, maximum_scenarios)) return proc.failGap(cx.diags, 0, "PROC POWER: scenario list exceeds the implemented size limit", .{});
            if (quotient >= 0) {
                // Integer-index construction avoids accumulating binary error;
                // only an ulp-scale slack includes a decimal endpoint.
                const slack = 8 * std.math.floatEps(f64) * @max(1, @abs(quotient));
                const count: usize = @intFromFloat(@floor(quotient + slack) + 1);
                if (count > maximum_scenarios - result.items.len) return proc.failGap(cx.diags, 0, "PROC POWER: scenario list exceeds the implemented size limit", .{});
                for (0..count) |k| try result.append(cx.arena, @mulAdd(f64, @as(f64, @floatFromInt(k)), step, start));
            }
        } else {
            if (result.items.len == maximum_scenarios) return proc.failGap(cx.diags, 0, "PROC POWER: scenario list exceeds the implemented size limit", .{});
            try result.append(cx.arena, start);
        }
    }
    if (at(t, i.*, .dot)) return invalid(cx, t, i.*, "a missing result indicator cannot be mixed with numeric values");
    if (result.items.len == 0) return invalid(cx, t, i.*, "number list has no values");
    return result.toOwnedSlice(cx.arena);
}
/// Stop at the next option assignment; preserve keyword spelling/order for the
/// analysis decoder, which distinguishes known unsupported choices from typos.
pub fn keywords(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    while (i.* < t.len and (at(t, i.*, .name) or at(t, i.*, .number)) and !at(t, i.* + 1, .eq)) {
        if (result.items.len > 0 and (kw(t, i.*, "test") or kw(t, i.*, "ci") or kw(t, i.*, "nfractional") or kw(t, i.*, "nfrac"))) break;
        if (result.items.len == maximum_scenarios) return proc.failGap(cx.diags, 0, "PROC POWER: keyword list exceeds the implemented size limit", .{});
        try result.append(cx.arena, t[i.*].text);
        i.* += 1;
    }
    if (result.items.len == 0) return invalid(cx, t, i.*, "keyword list has no values");
    return result.toOwnedSlice(cx.arena);
}

pub const Dimension = enum(usize) { sides, null_value, alpha, effect, sigma, n, power };
pub const dimension_count = 7;
pub const Grid = struct {
    axes: [dimension_count][]const ?f64 = .{ &.{2}, &.{0}, &.{0.05}, &.{null}, &.{null}, &.{null}, &.{null} },
    pub fn size(g: Grid, cx: proc.ProcCtx) diag.Error!usize {
        var n: usize = 1;
        for (g.axes) |axis| {
            if (axis.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC POWER: empty scenario axis", .{});
            if (axis.len > maximum_scenarios / n) return proc.failGap(cx.diags, 0, "PROC POWER: Cartesian scenario count exceeds the implemented size limit", .{});
            n *= axis.len;
        }
        return n;
    }
    /// Internal option order; rightmost axis varies fastest, independent of the
    /// option order in source. Duplicates are retained as distinct scenarios.
    pub fn row(g: Grid, index: usize) [dimension_count]?f64 {
        var result: [dimension_count]?f64 = undefined;
        var n = index;
        var j: usize = dimension_count;
        while (j > 0) {
            j -= 1;
            result[j] = g.axes[j][n % g.axes[j].len];
            n /= g.axes[j].len;
        }
        return result;
    }
    pub fn varying(g: Grid) [dimension_count]bool {
        var result: [dimension_count]bool = undefined;
        for (g.axes, 0..) |axis, j| result[j] = axis.len > 1;
        return result;
    }
};

test "STAT-POWER-008 DOLIST endpoints ordering missing and keyword boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const Case = struct { source: []const u8, expected: []const ?f64 };
    for ([_]Case{ .{ .source = "30 to 70 by 20 100 power=.", .expected = &.{ 30, 50, 70, 100 } }, .{ .source = "3 to 1 by -1 4", .expected = &.{ 3, 2, 1, 4 } }, .{ .source = "1 to 2 by .5", .expected = &.{ 1, 1.5, 2 } }, .{ .source = "-2 to 1", .expected = &.{ -2, -1, 0, 1 } }, .{ .source = ". alpha=.05", .expected = &.{null} }, .{ .source = "2 2", .expected = &.{ 2, 2 } } }) |c| {
        const tokens = try lex.tokenize(a, c.source, &d);
        var i: usize = 0;
        try std.testing.expectEqualSlices(?f64, c.expected, try numbers(cx, tokens, &i));
    }
    const fractional = try lex.tokenize(a, ".1 to .3 by .1", &d);
    var fi: usize = 0;
    const generated = try numbers(cx, fractional, &fi);
    try std.testing.expectEqual(@as(usize, 3), generated.len);
    for ([_]f64{ 0.1, 0.2, 0.3 }, generated) |exact, actual| try std.testing.expectApproxEqAbs(exact, actual.?, 8 * std.math.floatEps(f64));
    const tokens = try lex.tokenize(a, "2 U L alpha=.05", &d);
    var i: usize = 0;
    const words = try keywords(cx, tokens, &i);
    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("U", words[1]);
    try std.testing.expect(kw(tokens, i, "alpha"));
}

test "STAT-POWER-008 Cartesian rows match independent nested loops and retain duplicates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var grid: Grid = .{};
    grid.axes[@intFromEnum(Dimension.effect)] = &.{ 5, 10 };
    grid.axes[@intFromEnum(Dimension.sigma)] = &.{ 30, 50 };
    grid.axes[@intFromEnum(Dimension.n)] = &.{ 100, 150 };
    try std.testing.expectEqual(@as(usize, 8), try grid.size(cx));
    var index: usize = 0;
    for ([_]f64{ 5, 10 }) |mean| for ([_]f64{ 30, 50 }) |sigma| for ([_]f64{ 100, 150 }) |n| {
        const row = grid.row(index);
        index += 1;
        try std.testing.expectEqual(mean, row[@intFromEnum(Dimension.effect)].?);
        try std.testing.expectEqual(sigma, row[@intFromEnum(Dimension.sigma)].?);
        try std.testing.expectEqual(n, row[@intFromEnum(Dimension.n)].?);
    };
}

test "STAT-POWER-008 invalid lists and excessive expansion fail through diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    for ([_][]const u8{ "1 to 3 by 0", ". 1", "1 .", "1 to", "power=.", "3 to 1" }, 0..) |source, index| {
        _ = index;
        var d = diag.Diagnostics.init(a);
        const t = try lex.tokenize(a, source, &d);
        var i: usize = 0;
        try std.testing.expectError(error.ParseError, numbers(.{ .arena = a, .lib = &lib, .diags = &d }, t, &i));
        try std.testing.expect(d.hasErrors());
    }
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const t = try lex.tokenize(a, "1 to 10001", &d);
    var i: usize = 0;
    try std.testing.expectError(error.ParseError, numbers(.{ .arena = a, .lib = &lib, .diags = &d }, t, &i));
    try std.testing.expect(diag.gapHit());
    diag.resetGap();
    const axis = [_]?f64{1} ** 101;
    var grid: Grid = .{};
    grid.axes[@intFromEnum(Dimension.effect)] = &axis;
    grid.axes[@intFromEnum(Dimension.sigma)] = &axis;
    try std.testing.expectError(error.ParseError, grid.size(.{ .arena = a, .lib = &lib, .diags = &d }));
    try std.testing.expect(diag.gapHit());
}
