//! STAT-COMMON-011: containment-aware Type II hypotheses, not Type III aliases.
const std = @import("std");
const testing = std.testing;
const A = std.mem.Allocator;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const math = @import("glm_fit.zig");
const render = @import("glm_render.zig");
const Analysis = struct { spec: glm.Spec, data: glm.design.Design, result: math.Result };
fn analyze(cx: proc.ProcCtx, source: []const u8) !Analysis {
    const spec = try glm.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try @import("data_selection.zig").View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    const data = try glm.design.build(cx, spec, view, spec.responses[0]);
    return .{ .spec = spec, .data = data, .result = try glm.fitDesign(cx, spec, data) };
}
fn cells(a: A, lib: *Library, values: []const f64) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cells");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    for (values, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 4) "A1" else "A2" }, .{ .str = if ((i / 2) % 2 == 0) "B1" else "B2" }, .{ .num = y } });
    try lib.put("cells", ds);
}

test "COMMON011 containment follows CLASS supersets and continuous multiplicities" {
    try testing.expect(math.contains(.{ .classes = &.{ 1, 2 } }, .{ .classes = &.{1} }));
    try testing.expect(!math.contains(.{ .classes = &.{1} }, .{ .classes = &.{ 1, 2 } }));
    try testing.expect(!math.contains(.{ .classes = &.{ 1, 2 } }, .{ .classes = &.{3} }));
    try testing.expect(math.contains(.{ .classes = &.{1} }, .{})); // intercept
    try testing.expect(!math.contains(.{ .continuous = &.{1} }, .{}));
    try testing.expect(!math.contains(.{ .continuous = &.{ 1, 1 } }, .{ .continuous = &.{1} }));
    try testing.expect(math.contains(.{ .classes = &.{ 2, 3 }, .continuous = &.{ 0, 1, 0 } }, .{ .classes = &.{3}, .continuous = &.{ 0, 0, 1 } }));
    try testing.expect(!math.contains(.{ .classes = &.{ 2, 3 }, .continuous = &.{ 0, 1, 1 } }, .{ .classes = &.{3}, .continuous = &.{ 0, 0, 1 } }));
    try testing.expect(!math.contains(.{ .classes = &.{ 2, 3 }, .continuous = &.{0} }, .{ .classes = &.{3} }));
}

test "COMMON011 unbalanced interaction tests match manual frequency-dependent hypotheses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try cells(a, &lib, &.{ 12, 14, 11, 9, 20, 18, 17 });
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const r = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss2; run;");
    // S154 Table 16.7: .6/.4 weights are frequency dependent, not Type III's
    // equal-cell .5/.5. Cell means=(13,10,19,17), counts=(2,2,2,1), MSE=2.
    const contrast = [_][4]f64{ .{ 0.6, 0.4, -0.6, -0.4 }, .{ 0.6, -0.6, 0.4, -0.4 }, .{ 1, -1, -1, 1 } };
    const means = [_]f64{ 13, 10, 19, 17 };
    const counts = [_]f64{ 2, 2, 2, 1 };
    const cell_x = [_][4]f64{ .{ 1, 1, 1, 1 }, .{ 1, 1, -1, -1 }, .{ 1, -1, 1, -1 }, .{ 1, -1, -1, 1 } };
    const expected_l = [_][4]f64{ .{ 0, 2, 0, 0.4 }, .{ 0, 0, 2, 0.4 }, .{ 0, 0, 0, 4 } };
    for (contrast, expected_l, 0..) |c, expected, e| {
        var estimate: f64 = 0;
        var variance: f64 = 0;
        var l: [4]f64 = @splat(0);
        for (c, means, counts, cell_x) |value, mean, n, row| {
            estimate += value * mean;
            variance += value * value / n;
            for (0..4) |j| l[j] += value * row[j];
        }
        var lbeta: f64 = 0;
        var lgl: f64 = 0;
        for (l, expected, 0..) |value, target, j| {
            try testing.expectApproxEqAbs(target, value, 1e-12);
            lbeta += value * r.result.model.fit.coefficients[j];
            for (l, 0..) |other, k| lgl += value * r.result.model.fit.covariance_unscaled[j * 4 + k] * other;
        }
        const ss = estimate * estimate / variance;
        try testing.expectApproxEqAbs(estimate, lbeta, 1e-11);
        try testing.expectApproxEqAbs(variance, lgl, 1e-11);
        try testing.expectApproxEqAbs(ss, r.result.type_ii[e].ss, 1e-10);
        try testing.expectApproxEqAbs(ss / 2, r.result.type_ii[e].f_value, 1e-10);
        try testing.expectEqual(@as(usize, 1), r.result.type_ii[e].df);
        try testing.expectEqual(@as(usize, if (e == 2) 4 else 3), r.result.type_ii[e].rank_full);
        // Independent closed form for F(1,3) survival, from the t3 integral.
        const f = ss / 2;
        const probability = 1 - (2.0 / std.math.pi) * (std.math.atan(@sqrt(f / 3)) + @sqrt(3 * f) / (f + 3));
        try testing.expectApproxEqAbs(probability, r.result.type_ii[e].p_value, 1e-12);
    }
    try testing.expect(@abs(r.result.type_ii[0].ss - r.result.type_iii[0].ss) > 0.5);
    try testing.expect(@abs(r.result.type_ii[1].ss - r.result.type_iii[1].ss) > 1);
    const reversed = try analyze(cx, "proc glm plots=none; class B A; model y=B A A*B / ss2 ss1; run;");
    for ([_]usize{ 1, 0, 2 }, 0..) |j, k| try testing.expectApproxEqAbs(r.result.type_ii[j].ss, reversed.result.type_ii[k].ss, 1e-10);
    var output: std.ArrayList(u8) = .empty;
    try render.render(cx, &output, r.spec, r.data, r.result);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type II SS") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type I SS") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type III SS") == null);
    output.clearRetainingCapacity();
    try render.render(cx, &output, reversed.spec, reversed.data, reversed.result);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type I SS") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type II SS") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type III SS") == null);
    try testing.expect(!d.hasErrors());
}

test "COMMON011 balanced and missing-cell Type II retain correct estimable ranks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |missing| {
        var lib = Library.init(a);
        try cells(a, &lib, if (missing) &.{ 1, 3, 5, 7, 9, 11 } else &.{ 12, 14, 11, 9, 20, 18, 16, 18 });
        var d = diag.Diagnostics.init(a);
        const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
        const r = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss2; run;");
        const expected = if (missing) [_]f64{ 64, 16, 0 } else [_]f64{ 84.5, 12.5, 0.5 };
        for (r.result.type_ii, expected, 0..) |effect, ss, i| {
            try testing.expectApproxEqAbs(ss, effect.ss, 1e-10);
            try testing.expectEqual(@as(usize, if (missing and i == 2) 0 else 1), effect.df);
            if (!missing) try testing.expectApproxEqAbs(r.result.type_iii[i].ss, effect.ss, 1e-10);
        }
        if (missing) {
            // Within B1, A means 2 vs 10; within A1, B means 2 vs 6.
            // Variance of each mean difference is sigma²(1/2+1/2).
            try testing.expectEqual(@as(usize, 3), r.result.model.fit.rank);
            try testing.expectApproxEqAbs(@as(f64, 2), r.result.model.fit.mse, 1e-12);
            const rows = [_][4]f64{ .{ 0, 2, 0, 2 }, .{ 0, 0, 2, 2 } };
            for (rows, [_]f64{ -8, -4 }) |l, estimate| {
                var beta: f64 = 0;
                var variance: f64 = 0;
                var alias_dot: f64 = 0;
                for (l, [_]f64{ 1, -1, -1, 1 }, 0..) |v, null_value, j| {
                    beta += v * r.result.model.fit.coefficients[j];
                    alias_dot += v * null_value;
                    for (l, 0..) |u, k| variance += v * r.result.model.fit.covariance_unscaled[j * 4 + k] * u;
                }
                try testing.expectApproxEqAbs(@as(f64, 0), alias_dot, 1e-12);
                try testing.expectApproxEqAbs(estimate, beta, 1e-11);
                try testing.expectApproxEqAbs(@as(f64, 1), variance, 1e-11);
            }
        }
        var output: std.ArrayList(u8) = .empty;
        try glm.execute(cx, &output, r.spec);
        try testing.expect(!d.hasErrors());
    }
}

test "COMMON011 polynomial x and x*x adjust for each other rather than containment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "polynomial");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ -2, -1, 0, 1, 2 }, [_]f64{ 1, -2, 0, 2, -1 }) |x, noise| try ds.appendRow(&.{ .{ .num = x }, .{ .num = 3 + 2 * x + x * x + noise } });
    try lib.put("polynomial", &ds);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const r = try analyze(cx, "proc glm plots=none; model y=x x*x / ss2; run;");
    // Centered x and x²-2 are orthogonal, with squared norms 10 and 14.
    try testing.expectApproxEqAbs(@as(f64, 40), r.result.type_ii[0].ss, 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 14), r.result.type_ii[1].ss, 1e-10);
    for (r.result.type_ii, r.result.type_iii) |ii, iii| try testing.expectApproxEqAbs(iii.ss, ii.ss, 1e-10);
    try testing.expectApproxEqAbs(@as(f64, 5), r.result.model.fit.mse, 1e-10);
}

test "COMMON011 Type II exact and near aliases keep the declared numerical rank" {
    const t = [_]f64{ -2, -1, 0, 1, 2 };
    const z = [_]f64{ 1, -2, 2, -2, 1 };
    const noise = [_]f64{ 1, -2, 0, 2, -1 };
    const effects = [_]math.Effect{ .{ .start = 1, .len = 1 }, .{ .start = 2, .len = 1 } };
    const factors = [_]math.Factors{ .{ .continuous = &.{0} }, .{ .continuous = &.{1} } };
    for ([_]f64{ 0, 1e-6, 1e-3 }) |delta| {
        var x: [15]f64 = undefined;
        var y: [5]f64 = undefined;
        for (t, z, noise, 0..) |v, orthogonal, residual, i| {
            @memcpy(x[i * 3 ..][0..3], &[_]f64{ 1, v, v + delta * orthogonal });
            y[i] = 3 + 2 * v + orthogonal + residual;
        }
        var result = try math.fit(testing.allocator, &x, &y, 5, 3, &effects, .{ .type_ii = &factors });
        defer result.deinit(testing.allocator);
        if (delta < 1e-3) {
            try testing.expectEqual(@as(usize, 2), result.model.fit.rank);
            for (result.type_ii) |effect| {
                try testing.expectEqual(@as(usize, 0), effect.df);
                try testing.expectEqual(@as(f64, 0), effect.ss);
                try testing.expect(std.math.isNan(effect.f_value));
            }
        } else {
            // Centered orthogonal t,z,noise have norm² 10,14,10. The
            // conditional t norm² is 140*delta²/(10+14*delta²), beta=2-1/delta.
            const ss = (2 - 1 / delta) * (2 - 1 / delta) * 140 * delta * delta / (10 + 14 * delta * delta);
            try testing.expectEqual(@as(usize, 3), result.model.fit.rank);
            try testing.expectApproxEqAbs(ss, result.type_ii[0].ss, 1e-8);
            try testing.expectApproxEqAbs(@as(f64, 14), result.type_ii[1].ss, 1e-8);
            try testing.expectApproxEqAbs(ss / 5, result.type_ii[0].f_value, 1e-8);
        }
    }
}

test "COMMON011 Type II NOINT frequency and precision roles match explicit replication" {
    const effects = [_]math.Effect{ .{ .start = 0, .len = 1 }, .{ .start = 1, .len = 1 } };
    const factors = [_]math.Factors{ .{ .continuous = &.{0} }, .{ .continuous = &.{1} } };
    const a = testing.allocator;
    var grouped = try math.fit(a, &.{ 1, 0, 0, 1, 1, 1 }, &.{ 1, 2, 4 }, 3, 2, &effects, .{ .has_intercept = false, .type_ii = &factors, .frequencies = &.{ 2, 1, 3 }, .weights = &.{ 1, 2, 0.5 } });
    defer grouped.deinit(a);
    var expanded = try math.fit(a, &.{ 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 2, 4, 4, 4 }, 6, 2, &effects, .{ .has_intercept = false, .type_ii = &factors, .weights = &.{ 1, 1, 2, 0.5, 0.5, 0.5 } });
    defer expanded.deinit(a);
    try testing.expectEqual(@as(usize, 4), grouped.model.fit.df_error);
    for (grouped.type_ii, expanded.type_ii) |g, e| {
        try testing.expectEqual(e.df, g.df);
        try testing.expectApproxEqAbs(e.ss, g.ss, 1e-11);
        try testing.expectApproxEqAbs(e.f_value, g.f_value, 1e-10);
        try testing.expectApproxEqAbs(e.p_value, g.p_value, 1e-12);
    }
    // A one-effect NOINT model has a zero-column adjustment model.
    var one = try math.fit(a, &.{ 1, 2, 3 }, &.{ 1, 2, 2 }, 3, 1, effects[0..1], .{ .has_intercept = false, .type_ii = factors[0..1] });
    defer one.deinit(a);
    try testing.expectApproxEqAbs(@as(f64, 121.0 / 14.0), one.type_ii[0].ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 242.0 / 5.0), one.type_ii[0].f_value, 1e-10);
}

test "COMMON011 grouped multi-column Type II has actual numerator rank and F tail" {
    const a = testing.allocator;
    const x = [_]f64{ 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, -1, -1 };
    var result = try math.fit(a, &x, &.{ 1, 3, 4, 6, 8 }, 5, 3, &.{.{ .start = 1, .len = 2 }}, .{ .type_ii = &.{.{ .classes = &.{0} }} });
    defer result.deinit(a);
    // Means (2,5,8), n=(2,2,1), grand mean=4.4, between SS=25.2, SSE=4.
    const effect = result.type_ii[0];
    try testing.expectEqual(@as(usize, 2), effect.df);
    try testing.expectEqual(@as(usize, 3), effect.rank_full);
    try testing.expectEqual(@as(usize, 1), effect.rank_reduced);
    try testing.expectApproxEqAbs(@as(f64, 25.2), effect.ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 6.3), effect.f_value, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 7.3), effect.p_value, 1e-12); // F(2,2)
}

fn allocationCheck(a: A) !void {
    var result = try math.fit(a, &.{ 1, 1, 1, 1, 1, -1, 1, -1, 1 }, &.{ 1, 2, 4 }, 3, 3, &.{ .{ .start = 1, .len = 1 }, .{ .start = 2, .len = 1 } }, .{ .type_ii = &.{ .{ .classes = &.{0} }, .{ .classes = &.{1} } }, .frequencies = &.{ 2, 1, 2 } });
    defer result.deinit(a);
}

test "COMMON011 Type II allocation failure paths and malformed metadata" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationCheck, .{});
    const a = testing.allocator;
    const effects = [_]math.Effect{.{ .start = 1, .len = 1 }};
    try testing.expectError(error.ExecError, math.fit(a, &.{ 1, 1 }, &.{1}, 1, 2, &effects, .{ .type_ii = &.{} }));
    try testing.expectError(error.ExecError, math.fit(a, &.{ 1, 1 }, &.{1}, 1, 2, &effects, .{ .type_ii = &.{.{ .classes = &.{ 1, 1 } }} }));
    try testing.expectError(error.ExecError, math.fit(a, &.{ 1, 1 }, &.{1}, 1, 2, &effects, .{ .type_ii = &.{.{ .classes = &.{1}, .continuous = &.{1} }} }));
}
