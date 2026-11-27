//! Chapter20 effect TEST contract, S154 physical pp.545–546. REG/GLM own
//! different TEST grammars; this module never silently applies this one there.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const hypothesis = @import("linear_hypothesis.zig");
const A = std.mem.Allocator;
pub const Options = struct { effects: []const []const u8 = &.{}, types: [3]bool = .{ false, false, true }, coefficients: [3]bool = .{ false, false, false }, denominator_df: []const ?f64 = &.{}, chisq: bool = false, intercept: bool = false };
pub fn appliesTo(procedure: []const u8) bool {
    inline for (.{ "ICPHREG", "LIFEREG", "ORTHOREG", "PLM", "PROBIT", "SURVEYPHREG", "SURVEYREG", "RELIABILITY" }) |name| if (std.ascii.eqlIgnoreCase(procedure, name)) return true;
    return false;
}
pub fn parse(cx: proc.ProcCtx, procedure: []const u8, tokens: []const lex.Token) diag.Error!Options {
    if (!appliesTo(procedure)) return cx.diags.fail(error.ParseError, 0, "Shared effect TEST syntax does not apply to PROC {s}", .{procedure});
    var result: Options = .{};
    var effects: std.ArrayList([]const u8) = .empty;
    var ddf: std.ArrayList(?f64) = .empty;
    var i: usize = 0;
    while (i < tokens.len and tokens[i].tag != .slash) {
        if (tokens[i].tag == .eq or tokens[i].tag == .number or tokens[i].tag == .comma) return cx.diags.fail(error.ParseError, tokens[i].line, "Shared TEST expects model effects, not linear equations", .{});
        if (tokens[i].tag != .name) return proc.failGap(cx.diags, tokens[i].line, "TEST: this model-effect syntax is not implemented", .{});
        var effect: std.ArrayList(u8) = .empty;
        try effect.appendSlice(cx.arena, tokens[i].text);
        i += 1;
        while (i < tokens.len and tokens[i].tag == .star) {
            i += 1;
            if (i == tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, 0, "TEST: expected a factor after *", .{});
            try effect.append(cx.arena, '*');
            try effect.appendSlice(cx.arena, tokens[i].text);
            i += 1;
        }
        if (i < tokens.len and tokens[i].tag == .lparen) {
            try effect.append(cx.arena, '(');
            i += 1;
            var count: usize = 0;
            while (i < tokens.len and tokens[i].tag == .name) {
                if (count > 0) try effect.append(cx.arena, ' ');
                try effect.appendSlice(cx.arena, tokens[i].text);
                count += 1;
                i += 1;
            }
            if (count == 0 or i == tokens.len or tokens[i].tag != .rparen) return cx.diags.fail(error.ParseError, 0, "TEST: invalid nesting reference", .{});
            try effect.append(cx.arena, ')');
            i += 1;
        }
        try effects.append(cx.arena, effect.items);
    }
    if (i < tokens.len) i += 1;
    while (i < tokens.len) {
        const token = tokens[i];
        if (token.tag != .name) return cx.diags.fail(error.ParseError, token.line, "TEST: expected an option", .{});
        const name = token.text;
        i += 1;
        if (std.ascii.eqlIgnoreCase(name, "chisq")) result.chisq = true else if (std.ascii.eqlIgnoreCase(name, "intercept") or std.ascii.eqlIgnoreCase(name, "int")) result.intercept = true else if (std.ascii.eqlIgnoreCase(name, "e")) result.coefficients = .{ true, true, true } else if (std.ascii.eqlIgnoreCase(name, "e1") or std.ascii.eqlIgnoreCase(name, "ei")) result.coefficients[0] = true else if (std.ascii.eqlIgnoreCase(name, "e2") or std.ascii.eqlIgnoreCase(name, "eii")) result.coefficients[1] = true else if (std.ascii.eqlIgnoreCase(name, "e3") or std.ascii.eqlIgnoreCase(name, "eiii")) result.coefficients[2] = true else if (std.ascii.eqlIgnoreCase(name, "htype")) {
            if (i == tokens.len or tokens[i].tag != .eq) return cx.diags.fail(error.ParseError, token.line, "TEST HTYPE requires =", .{});
            i += 1;
            result.types = .{ false, false, false };
            var count: usize = 0;
            while (i < tokens.len and tokens[i].tag == .number) {
                const value = std.fmt.parseFloat(f64, tokens[i].text) catch return error.ParseError;
                if (value != @trunc(value) or value < 1 or value > 3) return cx.diags.fail(error.ParseError, token.line, "TEST HTYPE accepts only 1,2,3", .{});
                result.types[@as(usize, @intFromFloat(value)) - 1] = true;
                count += 1;
                i += 1;
                if (i < tokens.len and tokens[i].tag == .comma) {
                    i += 1;
                    if (i == tokens.len or tokens[i].tag != .number) return cx.diags.fail(error.ParseError, token.line, "TEST HTYPE: missing type after comma", .{});
                }
            }
            if (count == 0) return cx.diags.fail(error.ParseError, token.line, "TEST HTYPE requires a type", .{});
        } else if (std.ascii.eqlIgnoreCase(name, "ddf") or std.ascii.eqlIgnoreCase(name, "df")) {
            if (i == tokens.len or tokens[i].tag != .eq) return cx.diags.fail(error.ParseError, token.line, "TEST DDF requires =", .{});
            i += 1;
            ddf.clearRetainingCapacity();
            while (true) {
                if (i == tokens.len or (tokens[i].tag != .number and tokens[i].tag != .dot)) return cx.diags.fail(error.ParseError, token.line, "TEST DDF requires positive degrees of freedom or missing", .{});
                const value: ?f64 = if (tokens[i].tag == .dot) null else std.fmt.parseFloat(f64, tokens[i].text) catch return error.ParseError;
                if (value) |v| if (!std.math.isFinite(v) or v <= 0) return cx.diags.fail(error.ParseError, token.line, "TEST DDF must be positive", .{});
                try ddf.append(cx.arena, value);
                i += 1;
                if (i == tokens.len or tokens[i].tag != .comma) break;
                i += 1;
            }
        } else return cx.diags.fail(error.ParseError, token.line, "TEST: unknown shared option {s}", .{name});
    }
    result.effects = effects.items;
    result.denominator_df = ddf.items;
    return result;
}
pub const Effect = struct {
    name: []const u8,
    /// Null is unavailable, distinct from an available zero-rank effect.
    rows: [3]?[]const hypothesis.Row,
    intercept: bool = false,
    denominator_df: ?f64 = null,
};
pub const NativeStatistic = enum { f, chi_square };
pub const Test = struct { effect: []const u8, table_name: []const u8, hypothesis_type: u2, result: hypothesis.Result, show_f: bool, show_chisq: bool };
pub const Coefficients = struct { effect: []const u8, table_name: []const u8 = "Coef", hypothesis_type: u2, rows: []const hypothesis.Row };
pub const Report = struct { tests: []const Test, coefficients: []const Coefficients };
fn sameFactors(left: []const u8, right: []const u8, delimiters: []const u8) bool {
    var l = std.mem.tokenizeAny(u8, left, delimiters);
    var nl: usize = 0;
    while (l.next()) |factor| {
        nl += 1;
        var lc: usize = 0;
        var rc: usize = 0;
        var ll = std.mem.tokenizeAny(u8, left, delimiters);
        var rr = std.mem.tokenizeAny(u8, right, delimiters);
        while (ll.next()) |v| if (std.ascii.eqlIgnoreCase(factor, v)) {
            lc += 1;
        };
        while (rr.next()) |v| if (std.ascii.eqlIgnoreCase(factor, v)) {
            rc += 1;
        };
        if (lc != rc) return false;
    }
    var r = std.mem.tokenizeAny(u8, right, delimiters);
    var nr: usize = 0;
    while (r.next() != null) nr += 1;
    return nl == nr;
}
fn sameEffect(left: []const u8, right: []const u8) bool {
    const l = std.mem.indexOfScalar(u8, left, '(');
    const r = std.mem.indexOfScalar(u8, right, '(');
    if ((l == null) != (r == null)) return false;
    if (l) |begin| {
        if (!std.mem.endsWith(u8, left, ")") or !std.mem.endsWith(u8, right, ")")) return false;
        return sameFactors(left[0..begin], right[0..r.?], "*") and sameFactors(left[begin + 1 .. left.len - 1], right[r.? + 1 .. right.len - 1], " *");
    }
    return sameFactors(left, right, "*");
}
pub fn evaluate(a: A, model: hypothesis.Model, catalog: []const Effect, options: Options, native: NativeStatistic) diag.Error!Report {
    if (options.intercept) {
        const present = for (catalog) |effect| {
            if (effect.intercept) break true;
        } else false;
        if (!present) return error.ExecError;
    }
    const Selection = struct { effect: usize, ddf_index: ?usize };
    var selected: std.ArrayList(Selection) = .empty;
    if (options.effects.len == 0) {
        for (catalog, 0..) |effect, i| if (!effect.intercept or options.intercept) {
            try selected.append(a, .{ .effect = i, .ddf_index = selected.items.len });
        };
    } else {
        if (options.intercept) for (catalog, 0..) |effect, i| if (effect.intercept) {
            try selected.append(a, .{ .effect = i, .ddf_index = null });
        };
        for (options.effects, 0..) |name, j| {
            const index = for (catalog, 0..) |effect, i| {
                if (sameEffect(name, effect.name)) break i;
            } else return error.ExecError;
            try selected.append(a, .{ .effect = index, .ddf_index = j });
        }
    }
    const ddf_slots = if (options.effects.len == 0) selected.items.len else options.effects.len;
    if (options.denominator_df.len > ddf_slots) return error.ExecError;
    var tests: std.ArrayList(Test) = .empty;
    var coefficients: std.ArrayList(Coefficients) = .empty;
    for (0..3) |kind| {
        for (selected.items) |selection| {
            const effect = catalog[selection.effect];
            if (!options.types[kind] and !options.coefficients[kind]) continue;
            const rows = effect.rows[kind] orelse return error.ExecError;
            if (options.coefficients[kind]) try coefficients.append(a, .{ .effect = effect.name, .hypothesis_type = @intCast(kind + 1), .rows = rows });
            if (!options.types[kind]) continue;
            var view = model;
            if (effect.denominator_df) |df| view.denominator_df = df;
            const override = if (selection.ddf_index) |j| (if (j < options.denominator_df.len) options.denominator_df[j] else null) else null;
            try tests.append(a, .{ .effect = effect.name, .table_name = ([_][]const u8{ "Tests1", "Tests2", "Tests3" })[kind], .hypothesis_type = @intCast(kind + 1), .result = try hypothesis.evaluate(a, view, rows, override), .show_f = native == .f, .show_chisq = native == .chi_square or options.chisq });
        }
    }
    return .{ .tests = tests.items, .coefficients = coefficients.items };
}

test "COMMON031 effect identity preserves crossing nesting and repeated covariates" {
    try std.testing.expect(sameEffect("A*B(C D)", "b*a(d c)"));
    try std.testing.expect(!sameEffect("A*B(C)", "A(B C)"));
    try std.testing.expect(!sameEffect("x*x", "x"));
    try std.testing.expect(sameEffect("x*x*B(A)", "b*x*x(a)"));
}
