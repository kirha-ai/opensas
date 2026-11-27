//! MIXED fixed X generation. Reuse full GLM indicators, never full-rank contrast
//! coding: S154 physical pp.6707-6712 explicitly retains redundant parameters.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const Dataset = @import("../dataset.zig").Dataset;
const selection = @import("data_selection.zig");
const model = @import("mixed_model.zig");
const coded = @import("design_matrix.zig");
pub const Design = struct { matrix: coded.Design, y: []const f64, weights: []const f64, source_rows: []const usize };
pub fn build(cx: proc.ProcCtx, s: model.Spec, view: selection.View) diag.Error!Design {
    if (!s.matrix.intercept and s.matrix.effects.len == 0) return proc.failGap(cx.diags, s.line, "PROC MIXED: models with no fixed-effect columns are not implemented", .{});
    const rows = try cx.arena.alloc([]const Value, view.observations.len);
    for (view.observations, 0..) |observation, i| {
        if (observation.weight != .num or !std.math.isFinite(observation.weight.num) or observation.weight.num <= 0) return cx.diags.fail(error.ExecError, s.line, "PROC MIXED: model design requires finite positive selected weights", .{});
        rows[i] = observation.cells;
    }
    const matrix = coded.build(cx.arena, view.source, rows, s.matrix) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return cx.diags.fail(error.ExecError, s.line, "PROC MIXED: no usable model observations or invalid CLASS reference/design", .{}),
    };
    const y = try cx.arena.alloc(f64, matrix.n);
    const weights = try cx.arena.alloc(f64, matrix.n);
    const sources = try cx.arena.alloc(usize, matrix.n);
    for (matrix.source_rows, 0..) |index, i| {
        const observation = view.observations[index];
        y[i] = observation.cells[s.matrix.response].num;
        weights[i] = observation.weight.num;
        sources[i] = observation.source_number;
    }
    return .{ .matrix = matrix, .y = y, .weights = weights, .source_rows = sources };
}
fn tokens(a: std.mem.Allocator, d: *diag.Diagnostics, text: []const u8) ![]const @import("../lexer.zig").Token {
    const t = try @import("../lexer.zig").tokenize(a, text, d);
    return t[0 .. t.len - 1];
}
fn parseSample(cx: proc.ProcCtx, ds: *const Dataset, class: []const u8, effect: []const u8) !model.Spec {
    return model.parse(cx, ds, &[_]model.Statement{ .{ .kind = .class, .tokens = try tokens(cx.arena, cx.diags, class), .line = 1 }, .{ .kind = .model, .tokens = try tokens(cx.arena, cx.diags, effect), .line = 2 } }, .formatted, 0.05);
}
fn heights(a: std.mem.Allocator) !Dataset {
    var ds = Dataset.init(a, "heights");
    _ = try ds.addColumn("Family", .num);
    _ = try ds.addColumn("Gender", .char);
    _ = try ds.addColumn("Height", .num);
    // Complete public Getting Started sample, S154 MIXED chapter. F=0,M=1.
    const data = [_][3]f64{ .{ 1, 0, 67 }, .{ 1, 0, 66 }, .{ 1, 0, 64 }, .{ 1, 1, 71 }, .{ 1, 1, 72 }, .{ 2, 0, 63 }, .{ 2, 0, 63 }, .{ 2, 0, 67 }, .{ 2, 1, 69 }, .{ 2, 1, 68 }, .{ 2, 1, 70 }, .{ 3, 0, 63 }, .{ 3, 1, 64 }, .{ 4, 0, 67 }, .{ 4, 0, 66 }, .{ 4, 1, 67 }, .{ 4, 1, 67 }, .{ 4, 1, 69 } };
    for (data) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .str = if (row[1] == 0) "F" else "M" }, .{ .num = row[2] } });
    return ds;
}
test "STAT-MIXED-003 complete reference fixed designs retain 15 columns rank 8 and cell means" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try heights(a);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parseSample(cx, &ds, "Family Gender", "Height=Gender Family Family*Gender");
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const result = try build(cx, spec, view);
    const x = result.matrix;
    try std.testing.expectEqual(@as(usize, 18), x.n);
    try std.testing.expectEqual(@as(usize, 15), x.p);
    for (ds.rows.items, 0..) |cells, i| {
        const family: usize = @intFromFloat(cells[0].num - 1);
        const gender: usize = if (std.mem.eql(u8, cells[1].str, "F")) 0 else 1;
        const row = x.x[i * x.p ..][0..x.p];
        try std.testing.expectEqual(@as(f64, 1), row[0]);
        for (0..2) |j| try std.testing.expectEqual(@as(f64, if (j == gender) 1 else 0), row[1 + j]);
        for (0..4) |j| try std.testing.expectEqual(@as(f64, if (j == family) 1 else 0), row[3 + j]);
        for (0..8) |j| try std.testing.expectEqual(@as(f64, if (j == family * 2 + gender) 1 else 0), row[7 + j]);
    }
    const fitted = try @import("reg_fit.zig").fit(a, x.x, result.y, x.n, x.p, result.weights);
    try std.testing.expectEqual(@as(usize, 8), fitted.rank);
    // Cell residual sums are 14/3 + 1/2 + 32/3 + 2 + 0 + 0 + 1/2 + 8/3=21.
    try std.testing.expectApproxEqAbs(@as(f64, 21), fitted.sse, 1e-9);
    const simple = try parseSample(cx, &ds, "Family Gender", "Height=Gender");
    const second = try build(cx, simple, view);
    try std.testing.expectEqual(@as(usize, 3), second.matrix.p);
    const fit2 = try @import("reg_fit.zig").fit(a, second.matrix.x, second.y, second.matrix.n, second.matrix.p, second.weights);
    try std.testing.expectEqual(@as(usize, 2), fit2.rank);
}

test "STAT-MIXED-003 nesting polynomial noint missing provenance and reference levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "example");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .str = "a" }, .{ .num = 2 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .str = "b" }, .{ .num = 3 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .str = "a" }, .{ .num = 4 }, Value.missing });
    try ds.appendRow(&.{ .{ .str = "" }, .{ .num = 5 }, .{ .num = 3 } });
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parseSample(cx, &ds, "A(ref=first)", "y=A x(A) x|x /noint");
    const view = try selection.View.init(a, .{ .ds = &ds, .srcobs = &.{ 10, 20, 30, 40 } }, .{});
    const result = try build(cx, spec, view);
    try std.testing.expectEqualSlices(usize, &.{ 10, 20 }, result.source_rows);
    try std.testing.expectEqual(@as(usize, 6), result.matrix.p);
    try std.testing.expectEqualStrings("b", result.matrix.classes[0].map.levels[0].label);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 0, 2, 2, 4, 1, 0, 3, 0, 3, 9 }, result.matrix.x);
}

pub const Contrast = struct { coefficients: []const f64, rows: usize, name: []const u8 };
/// Equal-cell marginal hypotheses over full singular X. This construction is
/// valid for complete hierarchical CLASS effects with additive continuous
/// regressors and an intercept. It rejects missing cells, crossed covariates and nesting rather than
/// substituting column-deletion tests for Type III hypotheses (S154 ch.16).
pub fn type3(cx: proc.ProcCtx, s: model.Spec, d: Design, effect_index: usize) diag.Error!Contrast {
    if (!s.matrix.intercept or effect_index >= s.matrix.effects.len) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III contract requires an intercept and a valid effect", .{});
    const classes = d.matrix.classes;
    if (classes.len > 12) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III factorial expansion exceeds the implemented bound", .{});
    const masks = try cx.arena.alloc(usize, s.matrix.effects.len);
    const continuous = try cx.arena.alloc(bool, s.matrix.effects.len);
    var used: usize = 0;
    var name: []const u8 = "";
    for (s.matrix.effects, 0..) |effect, index| {
        const normal = try coded.normalize(cx.arena, s.source, s.matrix.classes, effect);
        if (normal.nested.len > 0 or (normal.continuous.len > 0 and normal.crossed.len > 0)) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III crossed-covariate or nested-effect contrasts are not implemented", .{});
        continuous[index] = normal.continuous.len > 0;
        var mask: usize = 0;
        for (normal.crossed) |ci| {
            const position = std.mem.indexOfScalar(usize, s.matrix.classes, ci) orelse return error.ExecError;
            mask |= @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(position));
        }
        masks[index] = mask;
        used |= mask;
        if (index == effect_index) name = normal.name;
    }
    if (continuous[effect_index]) {
        var selected: ?usize = null;
        for (d.matrix.columns, 0..) |column, index| if (column.effect_index == effect_index) {
            if (selected != null) return proc.failGap(cx.diags, s.line, "PROC MIXED: multi-column continuous Type III effect is not implemented", .{});
            selected = index;
        };
        const column = selected orelse return proc.failGap(cx.diags, s.line, "PROC MIXED: aliased duplicate continuous effect is not implemented", .{});
        const coefficients = try cx.arena.alloc(f64, d.matrix.p);
        @memset(coefficients, 0);
        coefficients[column] = 1;
        return .{ .coefficients = coefficients, .rows = 1, .name = name };
    }
    for (masks) |mask| {
        var subset = mask;
        while (subset > 0) : (subset = (subset - 1) & mask) {
            if (std.mem.indexOfScalar(usize, masks, subset) == null) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III nonhierarchical CLASS model is not implemented", .{});
        }
    }
    var cells: usize = 1;
    for (classes, 0..) |class, j| if (used & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(j))) != 0) {
        cells = std.math.mul(usize, cells, class.map.levels.len) catch return error.ExecError;
        if (cells > d.matrix.n) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III missing-cell model is not implemented", .{});
    };
    const representatives = try cx.arena.alloc(?usize, cells);
    @memset(representatives, null);
    for (0..d.matrix.n) |row| {
        var cell: usize = 0;
        for (classes, 0..) |class, j| if (used & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(j))) != 0) {
            cell = cell * class.map.levels.len + class.map.row_to_level[row].?;
        };
        if (representatives[cell] == null) representatives[cell] = row;
    }
    for (representatives) |row| if (row == null) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III missing-cell model is not implemented", .{});
    const target = masks[effect_index];
    var q: usize = 1;
    for (classes, 0..) |class, j| if (target & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(j))) != 0) {
        if (class.map.levels.len < 2) return proc.failGap(cx.diags, s.line, "PROC MIXED: Type III single-level CLASS effect is not implemented", .{});
        q = std.math.mul(usize, q, class.map.levels.len - 1) catch return error.ExecError;
    };
    const coefficients = try cx.arena.alloc(f64, std.math.mul(usize, q, d.matrix.p) catch return error.ExecError);
    @memset(coefficients, 0);
    const contrast_levels = try cx.arena.alloc(usize, classes.len);
    for (0..q) |contrast| {
        var remainder = contrast;
        var j = classes.len;
        while (j > 0) {
            j -= 1;
            contrast_levels[j] = 0;
            if (target & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(j))) != 0) {
                contrast_levels[j] = remainder % (classes[j].map.levels.len - 1);
                remainder /= classes[j].map.levels.len - 1;
            }
        }
        for (representatives) |representative| {
            const row = representative.?;
            var weight: f64 = 1;
            for (classes, 0..) |class, k| {
                const bit = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k));
                if (used & bit == 0) continue;
                if (target & bit != 0) {
                    const level = class.map.row_to_level[row].?;
                    weight *= if (level == contrast_levels[k]) @as(f64, 1) else if (level + 1 == class.map.levels.len) -1 else 0;
                } else weight /= @as(f64, @floatFromInt(class.map.levels.len));
            }
            for (0..d.matrix.p) |column| {
                // Additive covariates cancel from equal-margin CLASS contrasts;
                // never insert a representative cell's observed covariate value.
                if (d.matrix.columns[column].effect_index) |effect| if (continuous[effect]) continue;
                coefficients[contrast * d.matrix.p + column] += weight * d.matrix.x[row * d.matrix.p + column];
            }
        }
    }
    return .{ .coefficients = coefficients, .rows = q, .name = name };
}

test "STAT-MIXED-003 Type III full-X hypotheses equal independent cell-margin contrasts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try heights(a);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parseSample(cx, &ds, "Family Gender", "Height=Gender Family Family*Gender");
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const d = try build(cx, spec, view);
    const gender = try type3(cx, spec, d, 0);
    try std.testing.expectEqual(@as(usize, 1), gender.rows);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, -1, 0, 0, 0, 0, 0.25, -0.25, 0.25, -0.25, 0.25, -0.25, 0.25, -0.25 }, gender.coefficients);
    const family = try type3(cx, spec, d, 1);
    const interaction = try type3(cx, spec, d, 2);
    try std.testing.expectEqual(@as(usize, 3), family.rows);
    try std.testing.expectEqual(@as(usize, 3), interaction.rows);
    for (0..3) |r| for (0..15) |c| {
        const f: f64 = if (c == 3 + r) 1 else if (c == 6) -1 else if (c == 7 + 2 * r or c == 8 + 2 * r) 0.5 else if (c == 13 or c == 14) -0.5 else 0;
        const ab: f64 = if (c == 7 + 2 * r or c == 14) 1 else if (c == 8 + 2 * r or c == 13) -1 else 0;
        try std.testing.expectEqual(f, family.coefficients[r * 15 + c]);
        try std.testing.expectEqual(ab, interaction.coefficients[r * 15 + c]);
    };
    const fitted = try @import("reg_diagnostics.zig").fit(a, d.matrix.x, d.y, d.matrix.n, d.matrix.p, d.weights, true, spec.options.singular);
    for ([_]Contrast{ gender, family, interaction }) |hypothesis| for (0..hypothesis.rows) |r| {
        try std.testing.expectEqual(@import("glm_estimability.zig").Status.estimable, try @import("glm_estimability.zig").check(fitted, hypothesis.coefficients[r * 15 ..][0..15], 1e-10));
    };
    // Dropping one observed cell changes X legitimately, but must not silently
    // reuse the complete-cell hypothesis formula.
    var missing_view = view;
    const kept = try a.alloc(selection.Observation, 17);
    var k: usize = 0;
    for (view.observations, 0..) |observation, index| if (index != 12) {
        kept[k] = observation;
        k += 1;
    };
    missing_view.observations = kept;
    const missing = try build(cx, spec, missing_view);
    try std.testing.expectEqual(@as(usize, 14), missing.matrix.p);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, type3(cx, spec, missing, 0));
    try std.testing.expect(diag.gapHit());
}

test "STAT-MIXED-003 absent references and unsupported Type III domains fail visibly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try heights(a);
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const empty_x = try parseSample(cx, &ds, "Family Gender", "Height= /noint");
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, build(cx, empty_x, view));
    try std.testing.expect(diag.gapHit());
    diag.resetGap();
    const invalid = try parseSample(cx, &ds, "Family Gender(ref='not present')", "Height=Gender");
    try std.testing.expectError(error.ExecError, build(cx, invalid, view));
    try std.testing.expect(diagnostics.hasErrors());
    const Case = struct { class: []const u8, effects: []const u8 };
    for ([_]Case{ .{ .class = "Family Gender", .effects = "Height=Family*Gender" }, .{ .class = "Gender", .effects = "Height=Family Gender Family*Gender" }, .{ .class = "Family Gender", .effects = "Height=Family Gender(Family)" }, .{ .class = "Gender", .effects = "Height=Gender /noint" } }) |c| {
        diag.resetGap();
        defer diag.resetGap();
        const spec = try parseSample(cx, &ds, c.class, c.effects);
        const d = try build(cx, spec, view);
        try std.testing.expectError(error.ParseError, type3(cx, spec, d, 0));
        try std.testing.expect(diag.gapHit());
    }
}
