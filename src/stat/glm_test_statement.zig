//! GLM TEST H=/E=, not the shared chapter-20 parameter-equation syntax.
//! S154 physical pp.4105–4106 and 4115–4120: each H effect is tested separately
//! against the selected E mean square, using that effect's actual error DF.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const math = @import("glm_fit.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Kind = enum(u3) { i = 1, ii = 2, iii = 3, iv = 4 };
pub const Request = struct { hypotheses: []const usize, error_effect: usize, hypothesis_kind: Kind, error_kind: Kind };
pub const Row = struct { effect: usize, numerator: math.EffectTest, error_df: usize, f_value: f64, p_value: f64 };
pub const Table = struct { request: Request, denominator: math.EffectTest, rows: []const Row };
fn available(spec: parse.Spec, kind: Kind) bool {
    return switch (kind) { .i => spec.ss1 or spec.defaultSumsOfSquares(), .ii => spec.ss2, .iii => spec.ss3 or spec.defaultSumsOfSquares(), .iv => spec.ss4 };
}
fn highest(spec: parse.Spec) Kind {
    if (spec.ss4) return .iv;
    if (spec.ss3 or spec.defaultSumsOfSquares()) return .iii;
    if (spec.ss2) return .ii;
    return .i;
}
fn effect(cx: proc.ProcCtx, tokens: []const lex.Token, i: *usize, spec: parse.Spec, effects: []const parse.Effect) diag.Error!usize {
    var columns: std.ArrayList(usize) = .empty;
    while (true) {
        if (i.* == tokens.len or tokens[i.*].tag != .name) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: TEST requires a model effect", .{});
        if (eq(tokens[i.*].text, "intercept")) return proc.failGap(cx.diags, tokens[i.*].line, "PROC GLM: TEST INTERCEPT hypotheses are not implemented", .{});
        const column = spec.input.ds.indexOf(tokens[i.*].text) orelse return cx.diags.fail(error.ParseError, tokens[i.*].line, "PROC GLM: TEST variable {s} not found", .{tokens[i.*].text});
        try columns.append(cx.arena, column);
        i.* += 1;
        if (i.* == tokens.len or tokens[i.*].tag != .star) break;
        i.* += 1;
    }
    for (effects, 0..) |candidate, index| {
        if (candidate.variables.len != columns.items.len) continue;
        var matches = true;
        for (candidate.variables) |column| if (std.mem.count(usize, candidate.variables, &.{column}) != std.mem.count(usize, columns.items, &.{column})) { matches = false; };
        if (matches) return index;
    }
    return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: TEST effect is not in MODEL", .{});
}
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    var hypotheses: std.ArrayList(usize) = .empty;
    var error_effect: ?usize = null;
    var h_seen = false;
    var e_seen = false;
    var i: usize = 1;
    while (i < tokens.len and tokens[i].tag != .slash) {
        if (tokens[i].tag != .name or i + 1 == tokens.len or tokens[i + 1].tag != .eq or (!eq(tokens[i].text, "h") and !eq(tokens[i].text, "e"))) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: TEST requires H=effects and E=effect", .{});
        const is_h = eq(tokens[i].text, "h");
        if ((is_h and h_seen) or (!is_h and e_seen)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: repeated TEST H= or E= specification", .{});
        if (is_h) h_seen = true else e_seen = true;
        i += 2;
        var count: usize = 0;
        while (i < tokens.len and tokens[i].tag != .slash and !(i + 1 < tokens.len and tokens[i].tag == .name and tokens[i + 1].tag == .eq)) {
            const index = try effect(cx, tokens, &i, spec, effects);
            count += 1;
            if (is_h) {
                if (std.mem.indexOfScalar(usize, hypotheses.items, index) != null) return proc.failGap(cx.diags, tokens[0].line, "PROC GLM: repeated TEST hypothesis effects are not implemented", .{});
                try hypotheses.append(cx.arena, index);
            } else {
                if (error_effect != null) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: TEST E= requires exactly one effect", .{});
                error_effect = index;
            }
        }
        if (count == 0) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: TEST H= and E= require effects", .{});
    }
    if (!h_seen or !e_seen) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: TEST requires both H= and E=", .{});
    var htype: ?Kind = null;
    var etype: ?Kind = null;
    if (i < tokens.len) i += 1;
    while (i < tokens.len) {
        const token = tokens[i];
        const is_h = eq(token.text, "htype");
        if (token.tag != .name or (!is_h and !eq(token.text, "etype"))) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: unknown TEST option {s}", .{token.text});
        if ((is_h and htype != null) or (!is_h and etype != null)) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: duplicate TEST type option", .{});
        i += 1;
        if (i == tokens.len or tokens[i].tag != .eq) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: TEST type requires =1,2,3,or4", .{});
        i += 1;
        if (i < tokens.len and tokens[i].tag == .plus) i += 1;
        if (i == tokens.len or tokens[i].tag != .number) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: TEST type must be an integer from 1 to 4", .{});
        const type_value = std.fmt.parseFloat(f64, tokens[i].text) catch return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid TEST type", .{});
        if (!std.math.isFinite(type_value) or type_value < 1 or type_value > 4 or @floor(type_value) != type_value) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: TEST type must be an integer from 1 to 4", .{});
        const kind: Kind = @enumFromInt(@as(u3, @intFromFloat(type_value)));
        if (!available(spec, kind)) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: TEST type {d} was not requested in MODEL", .{@intFromEnum(kind)});
        if (is_h) htype = kind else etype = kind;
        i += 1;
    }
    return .{ .hypotheses = hypotheses.items, .error_effect = error_effect.?, .hypothesis_kind = htype orelse highest(spec), .error_kind = etype orelse highest(spec) };
}
fn values(fit: math.Result, kind: Kind) []const math.EffectTest {
    return switch (kind) { .i => fit.type_i, .ii => fit.type_ii, .iii => fit.type_iii, .iv => fit.type_iv };
}
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, fit: math.Result) diag.Error![]const Table {
    const tables = try cx.arena.alloc(Table, spec.test_requests.len);
    for (spec.test_requests, tables) |request, *table| {
        const denominators = values(fit, request.error_kind);
        const numerators = values(fit, request.hypothesis_kind);
        if (denominators.len != spec.effects.len or numerators.len != spec.effects.len) return cx.diags.fail(error.ExecError, 0, "PROC GLM: requested TEST sum-of-squares table is unavailable", .{});
        const denominator = denominators[request.error_effect];
        if (denominator.df == 0 or !std.math.isFinite(denominator.ms) or !(denominator.ms > 0)) return proc.failGap(cx.diags, 0, "PROC GLM: TEST with a degenerate error effect is not implemented", .{});
        // A custom denominator is unsafe when its SS is below the resolution
        // of the fitted-space projections. Use a dimension-derived arithmetic
        // budget (32*n*p² unit roundoffs) and the relevant response energy.
        // This is a supported-domain check, NEVER a substitute denominator or
        // an alteration of the effect SS. Centered models use corrected energy
        // so a harmless response offset does not alone trip the check.
        const n: f64 = @floatFromInt(fit.model.fit.fitted.len);
        const p: f64 = @floatFromInt(fit.model.fit.coefficients.len);
        const ku = 32 * n * p * p * (std.math.floatEps(f64) / 2);
        const energy = if (spec.intercept) fit.model.fit.sst else fit.model.fit.sst_uncorrected;
        if (ku >= 1 or !std.math.isFinite(energy)) return proc.failGap(cx.diags, 0, "PROC GLM: TEST numerical resolution is not supported for this model", .{});
        const gamma = ku / (1 - ku);
        if (denominator.ss <= gamma * gamma * energy) return proc.failGap(cx.diags, 0, "PROC GLM: TEST error effect is below the supported numerical resolution", .{});
        const rows = try cx.arena.alloc(Row, request.hypotheses.len);
        for (request.hypotheses, rows) |index, *row| {
            const numerator = numerators[index];
            if (numerator.df == 0 or !std.math.isFinite(numerator.ms)) return proc.failGap(cx.diags, 0, "PROC GLM: TEST with a nonestimable hypothesis effect is not implemented", .{});
            const statistic = numerator.ms / denominator.ms;
            if (!std.math.isFinite(statistic)) return proc.failGap(cx.diags, 0, "PROC GLM: TEST F value exceeds the supported finite range", .{});
            row.* = .{ .effect = index, .numerator = numerator, .error_df = denominator.df, .f_value = statistic, .p_value = @import("reg_fit.zig").fProbability(statistic, numerator.df, denominator.df) };
        }
        table.* = .{ .request = request, .denominator = denominator, .rows = rows };
    }
    return tables;
}
fn label(kind: Kind) []const u8 { return switch (kind) { .i => "I", .ii => "II", .iii => "III", .iv => "IV" }; }
fn number(a: std.mem.Allocator, x: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, tables: []const Table) diag.Error!void {
    if (spec.noprint) return;
    const a = cx.arena;
    for (tables) |table| {
        const request = table.request;
        var maximum: f64 = 0;
        for (table.rows) |row| maximum = @max(maximum, @abs(row.numerator.ss));
        const exponent: i32 = if (maximum > 0) @intFromFloat(@floor(@log10(maximum))) else 0;
        const decimals: usize = @intCast(@max(0, @min(12, 9 - exponent)));
        try out.print(a, "\nTests of Hypotheses Using the Type {s} MS for {s} as an Error Term\n\nSource DF Type {s} SS Mean Square F Value Pr > F\n\n", .{ label(request.error_kind), spec.effects[request.error_effect].name, label(request.hypothesis_kind) });
        for (table.rows) |row| try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ spec.effects[row.effect].name, row.numerator.df, try number(a, row.numerator.ss, decimals), try number(a, row.numerator.ms, decimals), try number(a, row.f_value, 2), if (row.p_value < 0.0001) "<.0001" else try number(a, row.p_value, 4) });
    }
}

test { _ = @import("glm_test_statement_tests.zig"); }
