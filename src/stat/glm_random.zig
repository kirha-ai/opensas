//! Post-hoc GLM random-effects ANOVA, S154 physical pp.4157–4160.
//! Supported model: complete crossed A B A*B, RANDOM B A*B, Type III EMS.
//! Random-effect columns are FULL indicators, never sum-to-zero random effects.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");
const reg = @import("reg_fit.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { effects: []const usize, tests: bool = false, next: ?*Request = null };
pub const Test = struct { interaction_weight: f64, error_weight: f64, denominator_ms: f64, denominator_df: f64, f_value: f64, p_value: f64 };
/// For one_way results only row0/column0 and tests[0] apply; fixed/interaction
/// are unused. Existing two-way coefficient indexing is unchanged.
pub const SumOfSquares = enum { iii, iv };
pub const Result = struct { ss_kind: SumOfSquares = .iii, one_way: bool = false, fixed: usize, random_main: usize, interaction: usize, coefficients: [3][2]f64, tests: [3]Test };

pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    var selected: std.ArrayList(usize) = .empty;
    var i: usize = 1;
    while (i < tokens.len and tokens[i].tag != .slash) {
        var variables: std.ArrayList(usize) = .empty;
        while (true) {
            if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: RANDOM requires a model effect", .{});
            const col = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: RANDOM variable not found", .{});
            try variables.append(cx.arena, col);
            i += 1;
            if (i == tokens.len or tokens[i].tag != .star) break;
            i += 1;
        }
        const found = for (effects, 0..) |effect, index| {
            if (effect.variables.len != variables.items.len) continue;
            var matches = true;
            for (effect.variables) |v| if (std.mem.count(usize, effect.variables, &.{v}) != std.mem.count(usize, variables.items, &.{v})) { matches = false; };
            if (matches) break index;
        } else return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: RANDOM effect is not in MODEL", .{});
        if (std.mem.indexOfScalar(usize, selected.items, found) != null) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: duplicate RANDOM effect", .{});
        try selected.append(cx.arena, found);
    }
    if (selected.items.len == 0) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: RANDOM requires effects", .{});
    var result: Request = .{ .effects = selected.items };
    if (i < tokens.len) i += 1;
    while (i < tokens.len) : (i += 1) {
        if (eq(tokens[i].text, "test")) result.tests = true else return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: RANDOM option {s} is not implemented", .{tokens[i].text});
    }
    return result;
}

pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, fitted: math.Result) diag.Error!Result {
    const request = spec.random.?;
    if (spec.absorb.len > 0 or spec.weight != null or spec.freq != null or !spec.intercept or spec.ss2 or (!spec.defaultSumsOfSquares() and !spec.ss3 and !spec.ss4)) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM supports unweighted Type III models without ABSORB", .{});
    // For complete factorials, and one-way effects without containing terms,
    // III and IV define the same hypothesis space (S154 physical pp.289–293).
    // Require the existing validated basis; never infer IV from rank alone.
    if (spec.ss4 and fitted.type_iv_basis == null) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM Type IV requires validated complete-model hypotheses", .{});
    if (fitted.model.fit.rank != d.p or fitted.model.fit.df_error == 0 or !(fitted.model.fit.mse > 0)) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM requires full rank and positive residual variation", .{});
    if (spec.effects.len == 1 and spec.classes.len == 1 and request.effects.len == 1) return oneWay(cx, spec, d, fitted);
    if (spec.classes.len != 2 or spec.effects.len != 3 or request.effects.len != 2) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM supports one-way or complete two-way mixed models", .{});
    var main: ?usize = null;
    var interaction: ?usize = null;
    for (request.effects) |index| {
        if (spec.effects[index].variables.len == 1) main = index else if (spec.effects[index].variables.len == 2) interaction = index;
    }
    if (main == null or interaction == null) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM requires one random main effect and the crossed interaction", .{});
    const fixed = 3 - main.? - interaction.?;
    const fixed_vars = spec.effects[fixed].variables;
    const random_vars = spec.effects[main.?].variables;
    const cross = spec.effects[interaction.?].variables;
    if (fixed_vars.len != 1 or random_vars.len != 1 or fixed_vars[0] == random_vars[0] or cross.len != 2 or std.mem.indexOfScalar(usize, cross, fixed_vars[0]) == null or std.mem.indexOfScalar(usize, cross, random_vars[0]) == null) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM requires the A B A*B model", .{});
    for ([_]usize{ fixed_vars[0], random_vars[0] }) |col| if (std.mem.indexOfScalar(usize, spec.classes, col) == null) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM effects must be CLASS factors", .{});
    const full = try @import("glm_estimability.zig").codedDesign(cx, spec, d);
    var coefficients: [3][2]f64 = @splat(@splat(0));
    const y = try cx.arena.alloc(f64, d.n);
    for (d.effects, 0..) |effect, tested| {
        const q = d.p - effect.len;
        if (effect.len == 0 or fitted.type_iii[tested].df != effect.len) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM empty-cell hypotheses are not implemented", .{});
        const reduced = try cx.arena.alloc(f64, d.n * q);
        for (0..d.n) |row| {
            var out: usize = 0;
            for (0..d.p) |col| if (col < effect.start or col >= effect.start + effect.len) {
                reduced[row * q + out] = d.x[row * d.p + col];
                out += 1;
            };
        }
        for (full.columns, 0..) |column, col| {
            const source = column.effect_index orelse continue;
            const slot: usize = if (source == main.?) 0 else if (source == interaction.?) 1 else continue;
            for (0..d.n) |row| y[row] = full.x[row * full.p + col];
            var projected = try reg.fit(cx.arena, reduced, y, d.n, q, null);
            defer projected.deinit(cx.arena);
            if (projected.rank != q) return error.ExecError;
            // P_full Z=Z for these complete fixed-effect indicator spaces.
            // tr[(P_full-P_reduced) ZZ'] = sum of reduced-fit residual SS.
            coefficients[tested][slot] += projected.sse / @as(f64, @floatFromInt(effect.len));
        }
    }
    // Other tested effects annihilate the random main-effect columns.
    const orthogonality_budget = 4096 * std.math.floatEps(f64) * @as(f64, @floatFromInt(d.n));
    for ([_]usize{ fixed, interaction.? }) |index| {
        if (coefficients[index][0] > orthogonality_budget) return error.ExecError;
        coefficients[index][0] = 0;
    }
    const c = coefficients[interaction.?][1];
    if (!(c > 0)) return error.ExecError;
    var tests: [3]Test = undefined;
    for (&tests, 0..) |*test_value, index| {
        var weight = if (index == interaction.?) @as(f64, 0) else coefficients[index][1] / c;
        if (weight < -orthogonality_budget or weight > 1 + orthogonality_budget) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM negative denominator combinations are not implemented", .{});
        weight = if (@abs(weight - 1) <= orthogonality_budget) 1 else if (@abs(weight) <= orthogonality_budget) 0 else weight;
        const error_weight = 1 - weight;
        const interaction_test = fitted.type_iii[interaction.?];
        const mse = fitted.model.fit.mse;
        const denominator_ms = weight * interaction_test.ms + error_weight * mse;
        const variance = weight * weight * interaction_test.ms * interaction_test.ms / @as(f64, @floatFromInt(interaction_test.df)) + error_weight * error_weight * mse * mse / @as(f64, @floatFromInt(fitted.model.fit.df_error));
        if (!(denominator_ms > 0) or !(variance > 0)) return error.ExecError;
        const denominator_df = denominator_ms * denominator_ms / variance;
        const statistic = fitted.type_iii[index].ms / denominator_ms;
        const numerator_df: f64 = @floatFromInt(fitted.type_iii[index].df);
        test_value.* = .{ .interaction_weight = weight, .error_weight = error_weight, .denominator_ms = denominator_ms, .denominator_df = denominator_df, .f_value = statistic, .p_value = @import("../functions.zig").betaI(1 / (1 + statistic * numerator_df / denominator_df), denominator_df / 2, numerator_df / 2) };
    }
    return .{ .ss_kind = if (spec.ss4 and !spec.ss3) .iv else .iii, .fixed = fixed, .random_main = main.?, .interaction = interaction.?, .coefficients = coefficients, .tests = tests };
}
fn oneWay(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, fitted: math.Result) diag.Error!Result {
    if (spec.effects[0].variables.len != 1 or spec.effects[0].variables[0] != spec.classes[0] or spec.random.?.effects[0] != 0) return proc.failGap(cx.diags, 0, "PROC GLM: one-way RANDOM requires the MODEL CLASS factor", .{});
    const k = d.classes[0].levels.len;
    if (k < 2 or fitted.type_iii[0].df != k - 1) return proc.failGap(cx.diags, 0, "PROC GLM: one-way RANDOM variance is not identifiable", .{});
    const counts = try cx.arena.alloc(usize, k);
    @memset(counts, 0);
    for (d.classes[0].row_levels) |level| counts[level.?] += 1;
    const n: f64 = @floatFromInt(d.n);
    var squares: f64 = 0;
    for (counts) |count| { const value: f64 = @floatFromInt(count); squares += value * value; }
    // tr[(I-11'/N)ZZ']/(k-1): full IID level indicators Z, with no
    // sum-to-zero constraint on random coefficients (S154 pp.4099,4157).
    const coefficient = (n - squares / n) / @as(f64, @floatFromInt(k - 1));
    if (!(coefficient > 0) or !std.math.isFinite(coefficient)) return error.ExecError;
    var coefficients: [3][2]f64 = @splat(@splat(0));
    coefficients[0][0] = coefficient;
    const nan = std.math.nan(f64);
    var tests: [3]Test = @splat(.{ .interaction_weight = nan, .error_weight = nan, .denominator_ms = nan, .denominator_df = nan, .f_value = nan, .p_value = nan });
    const statistic = fitted.type_iii[0].ms / fitted.model.fit.mse;
    tests[0] = .{ .interaction_weight = 0, .error_weight = 1, .denominator_ms = fitted.model.fit.mse, .denominator_df = @floatFromInt(fitted.model.fit.df_error), .f_value = statistic, .p_value = reg.fProbability(statistic, k - 1, fitted.model.fit.df_error) };
    return .{ .ss_kind = if (spec.ss4 and !spec.ss3) .iv else .iii, .one_way = true, .fixed = 0, .random_main = 0, .interaction = 0, .coefficients = coefficients, .tests = tests };
}

pub const Analysis = struct { request: Request, result: Result };
/// Separate RANDOM statements request separate post-hoc analyses. They never
/// alter the fixed-effect fit or silently union random-effect declarations.
pub fn computeAll(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, fitted: math.Result) diag.Error![]const Analysis {
    var results: std.ArrayList(Analysis) = .empty;
    var current = spec.random;
    while (current) |request| {
        var one = spec;
        one.random = request;
        const value = try compute(cx, one, d, fitted);
        try results.append(cx.arena, .{ .request = request, .result = value });
        if (spec.ss3 and spec.ss4) {
            var fourth = value;
            fourth.ss_kind = .iv;
            try results.append(cx.arena, .{ .request = request, .result = fourth });
        }
        current = if (request.next) |next| next.* else null;
    }
    return results.items;
}

fn number(a: std.mem.Allocator, x: f64, decimals: usize) ![]const u8 {
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
fn compact(a: std.mem.Allocator, x: f64) ![]const u8 {
    const text = try number(a, x, 4);
    return std.mem.trimEnd(u8, std.mem.trimEnd(u8, text, "0"), ".");
}
fn probability(a: std.mem.Allocator, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else number(a, p, 4);
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, fitted: math.Result, random: Result) diag.Error!void {
    const a = cx.arena;
    if ((spec.defaultSumsOfSquares() or spec.ss1) and (random.ss_kind == .iii or !spec.ss3)) try cx.diags.report(.note, 0, "TYPE I EMS not available without the E1 option.", .{});
    if (spec.noprint) return;
    const kind: []const u8 = if (random.ss_kind == .iv) "IV" else "III";
    try out.print(a, "\nThe GLM Procedure\n\nSource Type {s} Expected Mean Square\n\n", .{kind});
    for (spec.effects, 0..) |effect, index| {
        try out.print(a, "{s} Var(Error)", .{effect.name});
        if (!random.one_way) try out.print(a, " + {s} Var({s})", .{ try compact(a, random.coefficients[index][1]), spec.effects[random.interaction].name });
        if (index == random.random_main) try out.print(a, " + {s} Var({s})", .{ try compact(a, random.coefficients[index][0]), spec.effects[random.random_main].name });
        if (!random.one_way and index == random.fixed) try out.print(a, " + Q({s})", .{spec.effects[index].name});
        try out.append(a, '\n');
    }
    if (!spec.random.?.tests) return;
    try out.print(a, "\nThe GLM Procedure\nTests of Hypotheses for Mixed Model Analysis of Variance\n\nDependent Variable: {s}\n", .{spec.input.ds.columns.items[d.response].name});
    for (spec.effects, random.tests[0..spec.effects.len], fitted.type_iii, 0..) |effect, test_value, hypothesis, index| {
        try out.print(a, "\nSource DF Type {s} SS Mean Square F Value Pr > F\n\n", .{kind});
        try out.print(a, "{s} {d} {s} {s} {s} {s}\n\n", .{ effect.name, hypothesis.df, try number(a, hypothesis.ss, 6), try number(a, hypothesis.ms, 6), try number(a, test_value.f_value, 2), try probability(a, test_value.p_value) });
        if (random.one_way or index == random.interaction) {
            try out.print(a, "Error: MS(Error) {d} {s} {s}\n", .{ fitted.model.fit.df_error, try number(a, fitted.model.fit.sse, 6), try number(a, fitted.model.fit.mse, 6) });
        } else if (test_value.error_weight == 0) {
            const denominator = fitted.type_iii[random.interaction];
            try out.print(a, "Error: MS({s}) {d} {s} {s}\n", .{ spec.effects[random.interaction].name, denominator.df, try number(a, denominator.ss, 6), try number(a, denominator.ms, 6) });
        } else {
            try out.print(a, "Error {s} {s} {s}\nError: {s}*MS({s}) + {s}*MS(Error)\n", .{ try number(a, test_value.denominator_df, 3), try number(a, test_value.denominator_df * test_value.denominator_ms, 6), try number(a, test_value.denominator_ms, 6), try number(a, test_value.interaction_weight, 4), spec.effects[random.interaction].name, try number(a, test_value.error_weight, 4) });
        }
    }
}

test { _ = @import("glm_random_tests.zig"); }
