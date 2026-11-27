//! GLM positional multirow CONTRAST, S154 physical pp.4068–4070.
//! Row construction is GLM-coded; inference uses the shared real-fit Lβ kernel.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const estimate = @import("glm_estimate.zig");
const estimability = @import("glm_estimability.zig");
const kernel = @import("linear_hypothesis.zig");
pub const Request = struct { label: []const u8, rows: []const estimate.Request, singular: f64 = 1e-4 };
pub const Table = struct { request: Request, matrix: @import("design_matrix.zig").Design, rows: []const kernel.Row, result: kernel.Result };
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    if (tokens.len < 3 or tokens[1].tag != .string) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: CONTRAST requires a quoted label and coefficients", .{});
    var slash: usize = 2;
    while (slash < tokens.len and tokens[slash].tag != .slash) slash += 1;
    var rows: std.ArrayList(estimate.Request) = .empty;
    var start: usize = 2;
    while (start < slash) {
        var end = start;
        while (end < slash and tokens[end].tag != .comma) end += 1;
        if (end == start) return cx.diags.fail(error.ParseError, tokens[start].line, "PROC GLM: empty CONTRAST row", .{});
        var row: std.ArrayList(lex.Token) = .empty;
        try row.appendSlice(cx.arena, tokens[0..2]);
        try row.appendSlice(cx.arena, tokens[start..end]);
        try rows.append(cx.arena, try estimate.readFor("CONTRAST", cx, row.items, spec, effects));
        if (end < slash and end + 1 == slash) return cx.diags.fail(error.ParseError, tokens[end].line, "PROC GLM: empty final CONTRAST row", .{});
        start = end + 1;
    }
    if (rows.items.len == 0) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: CONTRAST requires a coefficient row", .{});
    var result: Request = .{ .label = tokens[1].text, .rows = rows.items };
    var i = slash + 1;
    while (i < tokens.len) {
        if (std.ascii.eqlIgnoreCase(tokens[i].text, "singular")) {
            if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or tokens[i + 2].tag != .number) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: CONTRAST SINGULAR requires a number", .{});
            result.singular = std.fmt.parseFloat(f64, tokens[i + 2].text) catch return error.ParseError;
            if (!(result.singular > 0 and result.singular < 1)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: CONTRAST SINGULAR must be between zero and one", .{});
            i += 3;
        } else if (std.ascii.eqlIgnoreCase(tokens[i].text, "e") or std.ascii.eqlIgnoreCase(tokens[i].text, "etype")) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: CONTRAST E/ETYPE output and alternate errors are not implemented", .{}) else return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: unknown CONTRAST option {s}", .{tokens[i].text});
    }
    return result;
}
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, mse: f64, df_error: usize) diag.Error![]const Table {
    if (spec.contrasts.len == 0) return &.{};
    const matrix = try estimability.codedDesign(cx, spec, d);
    var model = try estimability.fitCoded(cx, spec, d, matrix, mse, df_error);
    defer model.deinit(cx.arena);
    const tables = try cx.arena.alloc(Table, spec.contrasts.len);
    for (spec.contrasts, tables) |request, *table| {
        const rows = try cx.arena.alloc(kernel.Row, request.rows.len);
        for (request.rows, rows) |source, *target| target.* = .{ .coefficients = try estimate.map(cx, spec, matrix, source) };
        const result = try kernel.evaluate(cx.arena, kernel.fromRegression(model, request.singular), rows, null);
        if (result.status == .inconsistent) return proc.failGap(cx.diags, 0, "PROC GLM: numerically inconsistent CONTRAST rows are not implemented", .{});
        table.* = .{ .request = request, .matrix = matrix, .rows = rows, .result = result };
    }
    return tables;
}
fn number(a: std.mem.Allocator, value: ?f64, decimals: usize) ![]const u8 {
    const x = value orelse return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), tables: []const Table) diag.Error!void {
    if (tables.len == 0) return;
    var maximum: f64 = 0;
    for (tables) |table| if (table.result.numerator_ss) |ss| { maximum = @max(maximum, ss); };
    const exponent: i32 = if (maximum > 0) @intFromFloat(@floor(@log10(maximum))) else 0;
    const decimals: usize = @intCast(@max(0, @min(8, 9 - exponent)));
    try out.appendSlice(cx.arena, "\nContrast DF Contrast SS Mean Square F Value Pr > F\n\n");
    for (tables) |table| {
        const result = table.result;
        const ms: ?f64 = if (result.numerator_ss != null and result.rank > 0) result.numerator_ss.? / @as(f64, @floatFromInt(result.rank)) else null;
        try out.print(cx.arena, "{s} {d} {s} {s} {s} {s}\n", .{ table.request.label, result.rank, if (result.status == .nonestimable) "Non-est" else try number(cx.arena, result.numerator_ss, decimals), try number(cx.arena, ms, decimals), try number(cx.arena, result.f, 2), if (result.f_probability != null and result.f_probability.? < 0.0001) "<.0001" else try number(cx.arena, result.f_probability, 4) });
    }
}

test { _ = @import("glm_contrast_tests.zig"); }
