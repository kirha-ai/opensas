//! MIXED METHOD=TYPE3 covariance moments. S154 physical pp.6631,6701-6702:
//! for variance components (no SUBJECT/REPEATED), equate Type III expected mean
//! squares to observed values, then use these estimates in GLS. Reuse the proved
//! GLM two-way Type III projection/trace kernel; never reuse GLM post-hoc F as
//! the MIXED fixed-effect GLS test.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const selection = @import("data_selection.zig");
const glm = @import("glm.zig");
const glm_parse = @import("glm_parse.zig");
const glm_design = @import("glm_design.zig");
const glm_random = @import("glm_random.zig");
const coded = @import("design_matrix.zig");
pub const Row = struct { name: []const u8, df: usize, ss: f64, ms: f64, ems: []const f64, random: bool, anova_test: glm_random.Test };
pub const Result = struct {
    /// Component order matches random.Design.components; residual is last.
    variances: []const f64,
    rows: []const Row,
    residual_df: usize,
    residual_ss: f64,
    residual_ms: f64,
    /// These are post-hoc ANOVA tests for the Type3 table, NOT final MIXED GLS.
    anova: glm_random.Result,
};
fn gap(cx: proc.ProcCtx, line: usize, comptime message: []const u8) diag.Error {
    return proc.failGap(cx.diags, line, "PROC MIXED METHOD=TYPE3: " ++ message, .{});
}
/// Supported concrete domain: one fixed CLASS main effect A, random B and A*B,
/// complete crossed cells, unweighted observations, one variance-component
/// RANDOM statement. Other domains remain explicit rather than approximate.
pub fn estimate(cx: proc.ProcCtx, s: model.Spec, rs: random.Spec, rd: random.Design, view: selection.View) diag.Error!Result {
    if (s.has_repeated) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: METHOD=TYPE3 does not permit a REPEATED statement", .{});
    if (!s.matrix.intercept or s.matrix.classes.len != 2 or s.matrix.effects.len != 1 or rs.requests.len != 1 or rd.components.len != 2) return gap(cx, s.line, "requires complete two-way A fixed and B A*B random VC models");
    const request = rs.requests[0];
    if (request.subject.len > 0) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: METHOD=TYPE3 does not permit SUBJECT effects", .{});
    if (request.intercept or request.group.len > 0 or request.nofullz or request.effects.len != 2) return gap(cx, s.line, "GROUP/intercept or alternate RANDOM layouts are not implemented");
    for (view.observations) |observation| if (observation.weight != .num or observation.frequency != .num or observation.weight.num != 1 or observation.frequency.num != 1) return gap(cx, s.line, "weighted or frequency-replicated moment equations are not implemented");
    const combined = try cx.arena.alloc(coded.Effect, 3);
    combined[0] = s.matrix.effects[0];
    @memcpy(combined[1..], request.effects);
    const effects = try cx.arena.alloc(glm_parse.Effect, 3);
    for (combined, 0..) |effect, i| {
        const normalized = try coded.normalize(cx.arena, s.source, s.matrix.classes, effect);
        if (normalized.continuous.len > 0 or normalized.nested.len > 0) return gap(cx, s.line, "continuous or nested moment equations are not implemented");
        effects[i] = .{ .name = normalized.name, .variables = normalized.crossed };
    }
    if (effects[0].variables.len != 1) return gap(cx, s.line, "requires one fixed CLASS main effect");
    const spec: glm_parse.Spec = .{ .input = .{ .ds = @constCast(view.source) }, .classes = s.matrix.classes, .responses = &.{s.matrix.response}, .effects = effects, .random = .{ .effects = &.{ 1, 2 }, .tests = true }, .order = s.matrix.order, .singular = s.options.singular, .ss3 = true };
    const design = try glm_design.build(cx, spec, view, s.matrix.response);
    const fitted = try glm.fitDesign(cx, spec, design);
    const anova = try glm_random.compute(cx, spec, design, fitted);
    const full = try @import("glm_estimability.zig").codedDesign(cx, spec, design);
    if (rd.n != full.n or rd.z.len != rd.n * rd.q or rd.columns.len != rd.q) return gap(cx, s.line, "RANDOM and fixed analysis row contracts differ");
    // Verify that the actual supplied Z/K structure is precisely the full
    // random-indicator design whose EMS the shared kernel computed.
    var seen_components = [_]bool{ false, false };
    var total_columns: usize = 0;
    for (rd.components) |component| {
        if (component.request_index != 0 or component.group_index != 0 or component.effect_index >= 2 or component.kernel.len != rd.n * rd.n) return gap(cx, s.line, "unsupported component metadata");
        if (seen_components[component.effect_index]) return gap(cx, s.line, "duplicate RANDOM component metadata");
        seen_components[component.effect_index] = true;
        total_columns += component.columns;
        const effect = 1 + component.effect_index;
        if (!std.ascii.eqlIgnoreCase(component.name, effects[effect].name)) return gap(cx, s.line, "component names do not match the ANOVA model");
        var columns: usize = 0;
        for (full.columns) |column| if (column.effect_index == effect) {
            columns += 1;
        };
        if (columns != component.columns) return gap(cx, s.line, "RANDOM column count does not match the moment model");
        for (0..rd.n) |i| for (0..rd.n) |j| {
            var expected: f64 = 0;
            var actual_z: f64 = 0;
            for (full.columns, 0..) |column, k| if (column.effect_index == effect) {
                expected += full.x[i * full.p + k] * full.x[j * full.p + k];
            };
            for (rd.columns, 0..) |column, k| if (column.request_index == 0 and column.effect_index == component.effect_index) {
                actual_z += rd.z[i * rd.q + k] * rd.z[j * rd.q + k];
            };
            if (component.kernel[i * rd.n + j] != expected or actual_z != expected) return gap(cx, s.line, "RANDOM kernel does not match the verified Type III indicator space");
        };
    }
    if (total_columns != rd.q) return gap(cx, s.line, "RANDOM total columns do not match the verified components");
    const residual = fitted.model.fit.mse;
    const interaction = (fitted.type_iii[anova.interaction].ms - residual) / anova.coefficients[anova.interaction][1];
    const main = (fitted.type_iii[anova.random_main].ms - residual - anova.coefficients[anova.random_main][1] * interaction) / anova.coefficients[anova.random_main][0];
    if (!std.math.isFinite(main) or !std.math.isFinite(interaction) or !std.math.isFinite(residual) or residual <= 0) return gap(cx, s.line, "moment equations are degenerate or nonfinite");
    // PARMS NOBOUND (physical p.6670) documents the usual zero lower bound,
    // but not how TYPE3 reconciles negative moment equations with that bound
    // (truncate versus re-solve). No unverified clipping policy is substituted.
    if (main < 0 or interaction < 0) return gap(cx, s.line, "negative variance-component moment estimates require a verified boundary policy");
    const variances = try cx.arena.alloc(f64, 3);
    for (rd.components, 0..) |component, i| variances[i] = if (1 + component.effect_index == anova.random_main) main else interaction;
    variances[2] = residual;
    const rows = try cx.arena.alloc(Row, 3);
    for (effects, 0..) |effect, i| {
        const ems = try cx.arena.alloc(f64, 3);
        for (rd.components, 0..) |component, j| ems[j] = anova.coefficients[i][if (1 + component.effect_index == anova.random_main) @as(usize, 0) else 1];
        ems[2] = 1;
        const test_value = fitted.type_iii[i];
        rows[i] = .{ .name = effect.name, .df = test_value.df, .ss = test_value.ss, .ms = test_value.ms, .ems = ems, .random = i != anova.fixed, .anova_test = anova.tests[i] };
    }
    return .{ .variances = variances, .rows = rows, .residual_df = fitted.model.fit.df_error, .residual_ss = fitted.model.fit.sse, .residual_ms = residual, .anova = anova };
}

const Testing = struct {
    const Bundle = struct { spec: model.Spec, random_spec: random.Spec, random_design: random.Design, view: selection.View, design: fixed.Design };
    fn body(a: std.mem.Allocator, d: *diag.Diagnostics, text: []const u8) ![]const @import("../lexer.zig").Token {
        const t = try @import("../lexer.zig").tokenize(a, text, d);
        return t[0 .. t.len - 1];
    }
    fn prepare(cx: proc.ProcCtx, ds: *const @import("../dataset.zig").Dataset, classes: []const u8, effects: []const u8, random_effects: []const u8) !Bundle {
        const statements = [_]model.Statement{ .{ .kind = .class, .tokens = try body(cx.arena, cx.diags, classes), .line = 1 }, .{ .kind = .model, .tokens = try body(cx.arena, cx.diags, effects), .line = 2 }, .{ .kind = .random, .tokens = try body(cx.arena, cx.diags, random_effects), .line = 3 } };
        const spec = try model.parse(cx, ds, &statements, .formatted, 0.05);
        const rs = try random.parse(cx, ds, spec.matrix, &statements);
        const raw = try selection.View.init(cx.arena, .{ .ds = @constCast(ds) }, .{});
        const view = try raw.select(cx.arena, .{ .missing_columns = spec.required_columns, .weight = .positive_only });
        return .{ .spec = spec, .random_spec = rs, .random_design = try random.build(cx, rs, view), .view = view, .design = try fixed.build(cx, spec, view) };
    }
    fn balanced(a: std.mem.Allocator, interaction: f64) !@import("../dataset.zig").Dataset {
        var ds = @import("../dataset.zig").Dataset.init(a, "balanced");
        for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
        for (1..4) |ai| for (1..3) |bi| for ([_]f64{ -1, 1 }) |error_value| {
            const av: f64 = @floatFromInt(ai);
            const bv: f64 = @floatFromInt(bi);
            try ds.appendRow(&.{ .{ .num = av }, .{ .num = bv }, .{ .num = 10 * av + 4 * bv + interaction * av * bv + error_value } });
        };
        return ds;
    }
    fn close(expected: f64, actual: f64) !void {
        // Independent conservative roundoff budget for tiny complete full-rank
        // contrast projections: gamma(4096)*64 times the quantity scale.
        const ku = 4096 * std.math.floatEps(f64);
        try std.testing.expectApproxEqAbs(expected, actual, 64 * ku / (1 - ku) * @max(1, @abs(expected)));
    }
};

test "STAT-MIXED-004 TYPE3 moments solve independent balanced expected mean squares" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.balanced(a, 2);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const b = try Testing.prepare(cx, &ds, "A B", "Y=A", "B A*B");
    const result = try estimate(cx, b.spec, b.random_spec, b.random_design, b.view);
    // a=3,b=2,r=2: MSE=12/6=2, MSAB=8/2=4, MSB=192.
    // VarAB=(4-2)/2=1; VarB=(192-2-2*1)/6=94/3.
    try Testing.close(94.0 / 3.0, result.variances[0]);
    try Testing.close(1, result.variances[1]);
    try Testing.close(2, result.variances[2]);
    try std.testing.expectEqual(@as(usize, 6), result.residual_df);
    try Testing.close(12, result.residual_ss);
    try std.testing.expectEqual(@as(usize, 1), result.rows[1].df);
    try std.testing.expectEqual(@as(usize, 2), result.rows[2].df);
    for ([_]f64{ 1352, 192, 8 }, result.rows) |ss, row| try Testing.close(ss, row.ss);
    try Testing.close(6, result.rows[1].ems[0]);
    try Testing.close(2, result.rows[1].ems[1]);
    try Testing.close(1, result.rows[1].ems[2]);
    // Actual V=ZGZ'+R, not a diagonal stand-in: equal B/different A share
    // 94/3, same cell adds1, and observation diagonal adds residual2.
    for (ds.rows.items, 0..) |left, i| for (ds.rows.items, 0..) |right, j| {
        const expected: f64 = (if (left[1].num == right[1].num) @as(f64, 94.0 / 3.0) else 0) + (if (left[0].num == right[0].num and left[1].num == right[1].num) @as(f64, 1) else 0) + (if (i == j) @as(f64, 2) else 0);
        const actual = b.random_design.components[0].kernel[i * 12 + j] * result.variances[0] + b.random_design.components[1].kernel[i * 12 + j] * result.variances[1] + (if (i == j) result.variances[2] else 0);
        try Testing.close(expected, actual);
    };
    const reverse = try Testing.prepare(cx, &ds, "A B", "Y=A", "A*B B");
    const reordered = try estimate(cx, reverse.spec, reverse.random_spec, reverse.random_design, reverse.view);
    try Testing.close(1, reordered.variances[0]);
    try Testing.close(94.0 / 3.0, reordered.variances[1]);
}

test "STAT-MIXED-004 original machine TYPE3 variances retain complete permanent input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Reuse all44 rows already permanently owned by GLM007; no oracle read.
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/stat_glm_random_two_way.sas", "machine", &.{ "machine", "person", "rating" }, &.{}, 0);
    try std.testing.expectEqual(@as(usize, 44), ds.rows.items.len);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const b = try Testing.prepare(cx, &ds, "machine person", "rating=machine", "person machine*person");
    const result = try estimate(cx, b.spec, b.random_spec, b.random_design, b.view);
    for ([_]f64{ 24.2571, 17.0791, 0.8726 }, result.variances) |reference, actual| try std.testing.expect(@abs(reference - actual) < 0.00005);
    for ([_]f64{ 1238.197626, 1011.053834, 404.315028 }, result.rows) |reference, row| try std.testing.expect(@abs(reference - row.ss) < 0.0000005);
    try std.testing.expectEqual(@as(usize, 26), result.residual_df);
    try std.testing.expect(@abs(result.residual_ss - 22.686667) < 0.0000005);
    // This is not the final MIXED GLS F test: source GLM TypeIII F=16.57,
    // whereas MIXED with estimatedV gives16.72. Backend must recompute GLS.
    try std.testing.expect(@abs(result.rows[0].anova_test.f_value - 16.57) < 0.005);
    try std.testing.expectEqual(@as(usize, 4), b.design.matrix.p);
    try std.testing.expectEqual(@as(usize, 24), b.random_design.q);
}

test "STAT-MIXED-004 negative moments and incompatible covariance structures stay visible" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.balanced(a, 1);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const b = try Testing.prepare(cx, &ds, "A B", "Y=A", "B A*B");
    // MSAB=1,MSE=2 gives exactly-1/2; no clipping or positive substitute.
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, estimate(cx, b.spec, b.random_spec, b.random_design, b.view));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.list.items[diagnostics.list.items.len - 1].message, "negative variance") != null);
    var valid = try Testing.balanced(a, 2);
    const good = try Testing.prepare(cx, &valid, "A B", "Y=A", "B A*B");
    var bad = good.random_design;
    const components = try a.dupe(random.Component, bad.components);
    const kernel = try a.dupe(f64, components[0].kernel);
    kernel[0] += 1;
    components[0].kernel = kernel;
    bad.components = components;
    diag.resetGap();
    try std.testing.expectError(error.ParseError, estimate(cx, good.spec, good.random_spec, bad, good.view));
    try std.testing.expect(diag.gapHit());
    var repeated = good.spec;
    repeated.has_repeated = true;
    diag.resetGap();
    try std.testing.expectError(error.ParseError, estimate(cx, repeated, good.random_spec, good.random_design, good.view));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    var with_subject = good.random_spec;
    const requests = try a.dupe(random.Request, with_subject.requests);
    requests[0].subject = &.{1};
    with_subject.requests = requests;
    diag.resetGap();
    try std.testing.expectError(error.ParseError, estimate(cx, good.spec, with_subject, good.random_design, good.view));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
}
