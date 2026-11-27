//! S154 Computational Method, physical pp.4163–4164: reflexive generalized
//! inverses, ordered zero pivots and SS=(Lb)'(LGL')^-1(Lb).
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const estimability = @import("glm_estimability.zig");
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    // Retained normal matrix has infinity norm 10, inverse norm 2: kappa=20.
    // A 32*n*p² operation envelope (n=6,p=4) bounds projection/product error.
    const ku = 32 * 6 * 4 * 4 * (std.math.floatEps(f64) / 2);
    try t.expectApproxEqAbs(expected, actual, 20 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn multiply(left: [16]f64, right: [16]f64) [16]f64 {
    var result: [16]f64 = @splat(0);
    for (0..4) |i| for (0..4) |j| for (0..4) |k| {
        result[i * 4 + j] += left[i * 4 + k] * right[k * 4 + j];
    };
    return result;
}

test "GLM008 ordered g2 inverse and joint two-row hypothesis agree in both CLASS bases" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const labels = [_][]const u8{ "A", "B", "C" };
    const responses = [_]f64{ 1, 3, 3, 7, 5, 9 };
    const means = [_]f64{ 2, 5, 7 };
    const first_inverse = [_]f64{
        0.5, -0.5, -0.5, 0,
        -0.5, 1, 0.5, 0,
        -0.5, 0.5, 1, 0,
        0, 0, 0, 0,
    };
    const reversed_inverse = [_]f64{
        0.5, 0, -0.5, -0.5,
        0, 0, 0, 0,
        -0.5, 0, 1, 0.5,
        -0.5, 0, 0.5, 1,
    };
    for ([_]bool{ false, true }) |reverse| {
        var ds = Dataset.init(a, "sample");
        _ = try ds.addColumn("group", .char);
        _ = try ds.addColumn("y", .num);
        for (0..6) |i| {
            const row = if (reverse) 5 - i else i;
            try ds.appendRow(&.{ .{ .str = labels[row / 2] }, .{ .num = responses[row] } });
        }
        var lib = Library.init(a);
        try lib.put("sample", &ds);
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        const spec = try glm.parse(cx, try @import("../lexer.zig").tokenize(a, "proc glm order=data; class group; model y=group; run;", &diagnostics));
        const d = try glm.design.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
        var contrast_fit = try glm.fitDesign(cx, spec, d);
        defer contrast_fit.deinit(a);
        const matrix = try estimability.codedDesign(cx, spec, d);
        try t.expectEqual(@as(usize, 4), matrix.p); // I,A,B,C, with an exact alias
        var model = try estimability.fitCoded(cx, spec, d, matrix, contrast_fit.model.fit.mse, contrast_fit.model.fit.df_error);
        defer model.deinit(a);
        try t.expectEqual(@as(usize, 3), model.fit.rank);
        try t.expectEqual(@as(usize, 3), model.fit.df_error);
        try t.expectEqualSlices(bool, &.{ false, false, false, true }, model.fit.aliased);
        try t.expectEqual(@as(f64, 0), model.fit.coefficients[3]);
        try t.expect(std.math.isNan(model.fit.se[3]));
        for (0..4) |j| {
            try t.expectEqual(@as(f64, 0), model.fit.covariance_unscaled[3 * 4 + j]);
            try t.expectEqual(@as(f64, 0), model.fit.covariance_unscaled[j * 4 + 3]);
        }
        // Re-express both g2 inverses in the SAME canonical I,A,B,C order.
        // They differ because the last swept CLASS level has a zeroed slot;
        // neither is being falsely required to be a unique Moore-Penrose inverse.
        var canonical: [4]usize = .{ 0, 0, 0, 0 };
        for (matrix.columns[1..], 1..) |column, j| {
            const label = matrix.classes[0].map.levels[column.class_values[0].?].label;
            canonical[j] = if (std.mem.eql(u8, label, "A")) 1 else if (std.mem.eql(u8, label, "B")) 2 else blk: {
                try t.expectEqualStrings("C", label);
                break :blk 3;
            };
            try t.expect(std.mem.indexOfScalar(usize, canonical[0..j], canonical[j]) == null);
        }
        var g: [16]f64 = undefined;
        @memcpy(&g, model.fit.covariance_unscaled);
        var mapped_g: [16]f64 = undefined;
        for (0..4) |i| for (0..4) |j| {
            mapped_g[canonical[i] * 4 + canonical[j]] = g[i * 4 + j];
        };
        for (if (reverse) reversed_inverse else first_inverse, mapped_g) |expected, actual| try close(expected, actual);
        // Independently form X'X and X'Y, then check both reflexive identities
        // and the reported solution b=G X'Y on the actual GLM-coded design.
        var normal: [16]f64 = @splat(0);
        var cross: [4]f64 = @splat(0);
        for (0..6) |row| for (0..4) |i| {
            cross[i] += matrix.x[row * 4 + i] * d.y[row];
            for (0..4) |j| normal[i * 4 + j] += matrix.x[row * 4 + i] * matrix.x[row * 4 + j];
        };
        const aga = multiply(multiply(normal, g), normal);
        const gag = multiply(multiply(g, normal), g);
        for (normal, aga) |expected, actual| try close(expected, actual);
        for (g, gag) |expected, actual| try close(expected, actual);
        for (0..4) |i| {
            var coefficient: f64 = 0;
            for (0..4) |j| coefficient += g[i * 4 + j] * cross[j];
            try close(coefficient, model.fit.coefficients[i]);
        }
        // L jointly tests mean(A)=mean(C) and mean(B)=mean(C). These are
        // two estimable rows even though individual CLASS coefficients are not.
        var l: [2][4]f64 = @splat(@splat(0));
        for (canonical, 0..) |label, j| {
            if (label == 1) l[0][j] = 1;
            if (label == 2) l[1][j] = 1;
            if (label == 3) { l[0][j] = -1; l[1][j] = -1; }
        }
        var u: [2]f64 = @splat(0);
        var v: [4]f64 = @splat(0);
        for (l, 0..) |row, i| {
            try t.expectEqual(estimability.Status.estimable, try estimability.check(model, &row, 1e-4));
            for (0..4) |j| u[i] += row[j] * model.fit.coefficients[j];
            for (l, 0..) |other, k| for (0..4) |j| for (0..4) |h| { v[i * 2 + k] += row[j] * g[j * 4 + h] * other[h]; };
        }
        for ([_]f64{ -5, -2 }, u) |expected, actual| try close(expected, actual);
        for ([_]f64{ 1, 0.5, 0.5, 1 }, v) |expected, actual| try close(expected, actual);
        // Closed-form 2x2 inverse; the off-diagonal covariance matters.
        const determinant = v[0] * v[3] - v[1] * v[2];
        try close(0.75, determinant);
        const ss = (u[0] * u[0] * v[3] - u[0] * u[1] * (v[1] + v[2]) + u[1] * u[1] * v[0]) / determinant;
        try close(76.0 / 3.0, ss);
        try close(ss, contrast_fit.type_iii[0].ss);
        try t.expectEqual(@as(usize, 2), contrast_fit.type_iii[0].df);
        try close(18, model.fit.sse);
        try close(6, model.fit.mse);
        try close(19.0 / 9.0, contrast_fit.type_iii[0].f_value);
        // F(2,3) survival at 19/9 is (27/65)^(3/2), independent of betaI.
        const fraction: f64 = 27.0 / 65.0;
        try close(fraction * @sqrt(fraction), contrast_fit.type_iii[0].p_value);
        for (model.fit.fitted, 0..) |predicted, row| try close(means[(if (reverse) 5 - row else row) / 2], predicted);
        try t.expectEqualStrings("", try diagnostics.render());
    }
}
