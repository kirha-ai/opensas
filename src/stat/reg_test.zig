//! PROC REG's linear TEST consumer (S154 physical pp.8598–8599).
//! This is not Chapter20's effect-based TEST syntax (pp.545–546).
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const hypothesis = @import("linear_hypothesis.zig");
const A = std.mem.Allocator;
pub const Spec = struct { statement_index: usize, number: usize, label: ?[]const u8, rows: []const hypothesis.Row };
pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token, names: []const []const u8, statement_index: usize, number: usize, label: ?[]const u8) diag.Error!Spec {
    var end: usize = 0;
    while (end < tokens.len and tokens[end].tag != .slash) end += 1;
    if (end < tokens.len) {
        if (end + 1 < tokens.len and tokens[end + 1].tag == .name and std.ascii.eqlIgnoreCase(tokens[end + 1].text, "print")) return proc.failGap(cx.diags, tokens[end + 1].line, "PROC REG TEST: PRINT intermediate-matrix presentation is not implemented", .{});
        return cx.diags.fail(error.ParseError, tokens[end].line, "PROC REG TEST supports only PRINT; Chapter20 effect TEST options do not apply to REG", .{});
    }
    const equations = try @import("reg_restrict.zig").parse(cx, tokens[0..end], names);
    const rows = try cx.arena.alloc(hypothesis.Row, equations.len);
    for (equations, rows) |equation, *row| row.* = .{ .coefficients = equation.coefficients, .rhs = equation.rhs };
    return .{ .statement_index = statement_index, .number = number, .label = label, .rows = rows };
}
fn statistic(a: A, value: f64) ![]const u8 {
    if (!std.math.isFinite(value)) return ".";
    if (@abs(value) >= 10000) return std.fmt.allocPrint(a, "{d:.0}", .{value});
    if (value != 0 and @abs(value) < 0.001) return std.fmt.allocPrint(a, "{d:.8}", .{value});
    return std.fmt.allocPrint(a, "{d:.5}", .{value});
}
pub fn render(a: A, out: *std.ArrayList(u8), model: []const u8, response: []const u8, spec: Spec, result: hypothesis.Result, mse: f64) !void {
    const name = spec.label orelse try std.fmt.allocPrint(a, "{d}", .{spec.number});
    try out.print(a, "\nThe REG Procedure\nModel: {s}\n\nTest {s} Results for Dependent Variable {s}\n\nMean\nSource DF Square F Value Pr > F\n\nNumerator {d} {s} {d:.2} {s}\nDenominator {d:.0} {s}\n", .{ model, name, response, result.rank, try statistic(a, result.numerator_ss.? / @as(f64, @floatFromInt(result.rank))), result.f.?, if (result.f_probability.? < 0.0001) @as([]const u8, "<.0001") else try std.fmt.allocPrint(a, "{d:.4}", .{result.f_probability.?}), result.denominator_df.?, try statistic(a, mse) });
}
