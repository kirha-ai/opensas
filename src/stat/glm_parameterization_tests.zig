//! GLM004: independent basis/parameter checks from S154 physical pp.4110–4115.
//! Full indicator arrays below are reference data, not a design generator.
//! GLM's computational contrasts are not claimed to be its public SOLUTION coding.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const selection = @import("data_selection.zig");
const ranks = @import("reg_diagnostics.zig");
const full_design = @import("design_matrix.zig");
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;

fn parse(cx: proc.ProcCtx, source: []const u8) !glm.Spec {
    return glm.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, source, cx.diags));
}
fn design(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design {
    return glm.design.build(cx, spec, try selection.View.init(cx.arena, spec.input, .{}), spec.responses[0]);
}
fn close(reference: f64, actual: f64, n: usize, columns: usize, condition: f64) !void {
    // Dimension-derived operation envelope for scaled two-pass projections;
    // condition is an independently computed upper bound for the compared
    // bases' retained normal matrices.
    const u = std.math.floatEps(f64) / 2;
    const ku = @as(f64, @floatFromInt(32 * n * columns * columns)) * u;
    try std.testing.expectApproxEqAbs(reference, actual, condition * ku / (1 - ku) * @max(1, @abs(reference)));
}
fn meanVariance(fit: Fit, row: []const f64) f64 {
    var value: f64 = 0;
    for (row, 0..) |left, i| for (row, 0..) |right, j| {
        // Zeroed g2-inverse rows express fixed aliased coefficients; displayed
        // SEs for those aliases remain missing, not silently turned into zeros.
        value += left * fit.covariance_unscaled[i * row.len + j] * right;
    };
    return fit.mse * value;
}
fn factorial(a: A, lib: *Library, reverse_first: bool) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("Y", .num);
    const cells = [_]usize{ 0, 0, 1, 1, 2, 2, 3 };
    const values = [_]f64{ 12, 14, 11, 9, 20, 18, 17 };
    for (0..7) |r| {
        const i = if (reverse_first) 6 - r else r;
        const cell = cells[i];
        try ds.appendRow(&.{ .{ .str = if (cell < 2) "A1" else "A2" }, .{ .str = if (cell % 2 == 0) "B1" else "B2" }, .{ .num = values[i] } });
    }
    try lib.put("sample", ds);
    return ds;
}

test "GLM004 documented full indicator basis and contrast basis have the same fitted space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try factorial(a, &lib, false);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; class A B; model Y=A B A*B; run;");
    const contrast = try design(cx, spec);
    // Physical p.4111: I,A1,A2,B1,B2,A1B1,A1B2,A2B1,A2B2;
    // all CLASS levels are retained, rightmost crossed factor varies fastest.
    const reference = [_][9]f64{
        .{ 1, 1, 0, 1, 0, 1, 0, 0, 0 },
        .{ 1, 1, 0, 0, 1, 0, 1, 0, 0 },
        .{ 1, 0, 1, 1, 0, 0, 0, 1, 0 },
        .{ 1, 0, 1, 0, 1, 0, 0, 0, 1 },
    };
    const transform = [_][9]f64{
        .{ 1, 0.5, 0.5, 0.5, 0.5, 0.25, 0.25, 0.25, 0.25 },
        .{ 0, 0.5, -0.5, 0, 0, 0.25, 0.25, -0.25, -0.25 },
        .{ 0, 0, 0, 0.5, -0.5, 0.25, -0.25, 0.25, -0.25 },
        .{ 0, 0, 0, 0, 0, 0.25, -0.25, -0.25, 0.25 },
    };
    var full: [63]f64 = undefined;
    for ([_]usize{ 0, 0, 1, 1, 2, 2, 3 }, 0..) |cell, i| {
        @memcpy(full[i * 9 ..][0..9], &reference[cell]);
        for (0..9) |j| {
            var value: f64 = 0;
            for (0..4) |k| value += contrast.x[i * 4 + k] * transform[k][j];
            try std.testing.expectEqual(reference[cell][j], value); // exact dyadics
        }
        const f = reference[cell];
        try std.testing.expectEqualSlices(f64, &.{ f[0], f[1] - f[2], f[3] - f[4], f[5] - f[6] - f[7] + f[8] }, contrast.x[i * 4 ..][0..4]);
    }
    const supplied = try full_design.build(a, spec.input.ds, spec.input.ds.rows.items, .{
        .response = 2,
        .classes = &.{ 0, 1 },
        .effects = &.{ .{ .factors = &.{0} }, .{ .factors = &.{1} }, .{ .factors = &.{ 0, 1 } } },
    });
    try std.testing.expectEqual(@as(usize, 7), supplied.n);
    try std.testing.expectEqual(@as(usize, 9), supplied.p);
    try std.testing.expectEqualSlices(f64, &full, supplied.x);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4, 5, 6 }, supplied.source_rows);
    const effect_names = [_][]const u8{ "Intercept", "A", "A", "B", "B", "A*B", "A*B", "A*B", "A*B" };
    const memberships = [_][2]?usize{ .{ null, null }, .{ 0, null }, .{ 1, null }, .{ null, 0 }, .{ null, 1 }, .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
    for (supplied.columns, effect_names, memberships) |column, name, membership| {
        try std.testing.expectEqualStrings(name, column.effect_name);
        try std.testing.expectEqualSlices(?usize, &membership, column.class_values);
    }
    var coded = try ranks.fit(a, &full, contrast.y, 7, 9, null, true, spec.singular);
    defer coded.deinit(a);
    var fitted = try glm.fitDesign(cx, spec, contrast);
    defer fitted.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), coded.fit.rank);
    try std.testing.expectEqual(@as(usize, 4), fitted.model.fit.rank);
    try std.testing.expectEqual(@as(usize, 3), coded.fit.df_error);
    try std.testing.expectEqualSlices(bool, &.{ false, false, true, false, true, false, true, true, true }, coded.fit.aliased);
    // The retained I,A1,B1,A1B1 normal matrix has infinity norm 17;
    // its inverse has norm 13/2, giving condition 221/2 independently.
    for ([_]f64{ 17, -7, 0, 2, 0, 1, 0, 0, 0 }, coded.fit.coefficients) |expected, actual| try close(expected, actual, 7, 9, 221.0 / 2.0);
    for (coded.fit.aliased, coded.fit.coefficients, coded.fit.se) |alias, coefficient, se| if (alias) {
        try std.testing.expectEqual(@as(f64, 0), coefficient);
        try std.testing.expect(std.math.isNan(se));
    };
    for ([_]f64{ 13, 13, 10, 10, 19, 19, 17 }, 0..) |expected, i| {
        try close(expected, coded.fit.fitted[i], 7, 9, 221.0 / 2.0);
        try close(expected, fitted.model.fit.fitted[i], 7, 4, 221.0 / 2.0);
        // Cell-mean variance is MSE/count: 1 for replicated cells, 2 for last.
        const variance: f64 = if (i < 6) 1 else 2;
        try close(variance, meanVariance(coded.fit, full[i * 9 ..][0..9]), 7, 9, 221.0 / 2.0);
        try close(variance, meanVariance(fitted.model.fit, contrast.x[i * 4 ..][0..4]), 7, 4, 221.0 / 2.0);
    }
    // The Type III tests are estimable functions of the full parameter
    // vector, not deletion of its redundant dummy blocks. Equal-cell marginal
    // A/B differences and the difference-of-differences give these L rows.
    const hypotheses = [_][9]f64{
        .{ 0, 1, -1, 0, 0, 0.5, 0.5, -0.5, -0.5 },
        .{ 0, 0, 0, 1, -1, 0.5, -0.5, 0.5, -0.5 },
        .{ 0, 0, 0, 0, 0, 1, -1, -1, 1 },
    };
    for (hypotheses, [_]f64{ -6.5, 2.5, 1 }, [_]f64{ 0.625, 0.625, 2.5 }, [_]f64{ 67.6, 10, 0.4 }, 0..) |l, value, variance, ss, effect| {
        var estimate: f64 = 0;
        var unscaled_variance: f64 = 0;
        for (l, 0..) |left, j| {
            estimate += left * coded.fit.coefficients[j];
            for (l, 0..) |right, k| unscaled_variance += left * coded.fit.covariance_unscaled[j * 9 + k] * right;
        }
        try close(value, estimate, 7, 9, 221.0 / 2.0);
        try close(variance, unscaled_variance, 7, 9, 221.0 / 2.0);
        try close(ss, estimate * estimate / unscaled_variance, 7, 9, 221.0 / 2.0);
        try close(ss, fitted.type_iii[effect].ss, 7, 4, 221.0 / 2.0);
        try std.testing.expectEqual(@as(usize, 1), fitted.type_iii[effect].df);
    }
    try close(6, coded.fit.sse, 7, 9, 221.0 / 2.0);
    try close(6, fitted.model.fit.sse, 7, 4, 221.0 / 2.0);
}

test "GLM004 class reference order transforms interaction coefficients and covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try factorial(a, &lib, true); // A2/B2 occur first, A1/B1 last.
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const first_spec = try parse(cx, "proc glm order=data; class A B; model Y=A B A*B; run;");
    const second_spec = try parse(cx, "proc glm order=internal; class A B; model Y=A B A*B; run;");
    const first = try design(cx, first_spec);
    const second = try design(cx, second_spec);
    try std.testing.expectEqualStrings("A2", first.classes[0].levels[0].label);
    try std.testing.expectEqualStrings("B2", first.classes[1].levels[0].label);
    try std.testing.expectEqualStrings("A1", second.classes[0].levels[0].label);
    const signs = [_]f64{ 1, -1, -1, 1 };
    for (0..first.n) |i| for (signs, 0..) |sign, j| try std.testing.expectEqual(sign * first.x[i * 4 + j], second.x[i * 4 + j]);
    var left = try glm.fitDesign(cx, first_spec, first);
    defer left.deinit(a);
    var right = try glm.fitDesign(cx, second_spec, second);
    defer right.deinit(a);
    for (signs, 0..) |sign, j| {
        try close(sign * left.model.fit.coefficients[j], right.model.fit.coefficients[j], 7, 4, 221.0 / 2.0);
        for (signs, 0..) |other, k| try close(sign * other * left.model.fit.covariance[j * 4 + k], right.model.fit.covariance[j * 4 + k], 7, 4, 221.0 / 2.0);
    }
    for (left.model.fit.fitted, right.model.fit.fitted) |l, r| try close(l, r, 7, 4, 221.0 / 2.0);
}

test "GLM004 polynomial change of origin preserves estimates predictions and covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "t", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 0.875, 4.375, 8.625, 16.125 }, 0..) |y, i| {
        const x: f64 = @floatFromInt(i);
        try ds.appendRow(&.{ .{ .num = x }, .{ .num = x - 1.5 }, .{ .num = y } });
    }
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const raw_spec = try parse(cx, "proc glm; model y=x x*x; run;");
    const centered_spec = try parse(cx, "proc glm; model y=t t*t; run;");
    const raw = try design(cx, raw_spec);
    const centered = try design(cx, centered_spec);
    const transform = [_][3]f64{ .{ 1, 1.5, 2.25 }, .{ 0, 1, 3 }, .{ 0, 0, 1 } };
    for (0..4) |i| for (0..3) |j| {
        var value: f64 = 0;
        for (0..3) |k| value += centered.x[i * 3 + k] * transform[k][j];
        try std.testing.expectEqual(raw.x[i * 3 + j], value);
    };
    var r = try glm.fitDesign(cx, raw_spec, raw);
    defer r.deinit(a);
    var c = try glm.fitDesign(cx, centered_spec, centered);
    defer c.deinit(a);
    // Residuals (-1,3,-3,1)/8 are exactly orthogonal to 1,x,x².
    // Raw normal matrix norm=148, inverse norm=17/4, condition=629.
    for ([_]f64{ 1, 2, 1 }, r.model.fit.coefficients) |expected, actual| try close(expected, actual, 4, 3, 629);
    for ([_]f64{ 6.25, 5, 1 }, c.model.fit.coefficients) |expected, actual| try close(expected, actual, 4, 3, 629);
    try close(5.0 / 16.0, r.model.fit.sse, 4, 3, 629);
    try std.testing.expectEqual(@as(usize, 1), r.model.fit.df_error);
    const covariance = [_]f64{ 19.0 / 64.0, -21.0 / 64.0, 5.0 / 64.0, -21.0 / 64.0, 49.0 / 64.0, -15.0 / 64.0, 5.0 / 64.0, -15.0 / 64.0, 5.0 / 64.0 };
    for (covariance, r.model.fit.covariance) |expected, actual| try close(expected, actual, 4, 3, 629);
    for (0..3) |i| for (0..3) |j| {
        var value: f64 = 0;
        for (0..3) |k| for (0..3) |l| {
            value += transform[i][k] * covariance[k * 3 + l] * transform[j][l];
        };
        try close(value, c.model.fit.covariance[i * 3 + j], 4, 3, 629);
    };
    for ([_]f64{ 1, 4, 9, 16 }, r.model.fit.fitted, c.model.fit.fitted) |expected, left, right| {
        try close(expected, left, 4, 3, 629);
        try close(expected, right, 4, 3, 629);
    }
}
