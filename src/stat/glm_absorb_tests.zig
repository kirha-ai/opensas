const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const absorb = @import("glm_absorb.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
fn parse(cx: proc.ProcCtx, source: []const u8) !glm.Spec {
    return glm.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, source, cx.diags));
}
fn build(cx: proc.ProcCtx, spec: glm.Spec) !glm.design.Design {
    const view = try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    try absorb.validate(cx, spec, view);
    return glm.design.build(cx, spec, view, spec.responses[0]);
}
fn dataset(a: A, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "block", "unit", "x", "y", "w", "f" }) |name| _ = try ds.addColumn(name, .num);
    try lib.put("sample", ds);
    return ds;
}
fn row(ds: *Dataset, values: [6]f64) !void {
    var cells: [6]Value = undefined;
    for (values, 0..) |v, i| cells[i] = .{ .num = v };
    try ds.appendRow(&cells);
}
fn close(expected: f64, actual: f64) !void {
    // Small exact rational fixtures; 1024 compensated arithmetic operations
    // with a conservative retained-normal conditioning bound of 32.
    const ku = 1024 * (std.math.floatEps(f64) / 2);
    try std.testing.expectApproxEqAbs(expected, actual, 32 * ku / (1 - ku) * @max(1, @abs(expected)));
}

test "GLM005 absorption agrees with explicit nuisance projection and independent covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try dataset(a, &lib);
    var full: [18]f64 = undefined;
    var y: [6]f64 = undefined;
    for (0..2) |block| for ([_]f64{ 1, 2, 2 }, 0..) |value, j| {
        const i = block * 3 + j;
        const xi: f64 = @floatFromInt(j);
        y[i] = value + 10 * @as(f64, @floatFromInt(block));
        try row(ds, .{ @floatFromInt(block + 1), 1, xi, y[i], 1, 1 });
        @memcpy(full[i * 3 ..][0..3], &[_]f64{ if (block == 0) 1 else 0, if (block == 1) 1 else 0, xi });
    };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; absorb block; model y=x; run;");
    const data = try build(cx, spec);
    var result = try absorb.fit(cx, spec, data);
    defer result.deinit(a);
    var reference = try @import("reg_diagnostics.zig").fit(a, &full, &y, 6, 3, null, false, 1e-9);
    defer reference.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), result.absorbed_rank);
    try std.testing.expectEqual(@as(usize, 3), result.rank);
    try std.testing.expectEqual(@as(usize, 3), result.df_error);
    try close(1.0 / 3.0, result.sse);
    try close(1.0 / 9.0, result.mse);
    try close(454.0 / 3.0, result.sst);
    try close(20.0 / 3.0, result.y_mean);
    const conditional = result.conditional.?.model.fit;
    try close(0.5, conditional.coefficients[0]);
    try close(1.0 / 36.0, conditional.covariance[0]);
    try close(reference.fit.coefficients[2], conditional.coefficients[0]);
    try close(reference.fit.covariance[8], conditional.covariance[0]);
    for (conditional.residuals, reference.fit.residuals) |left, right| try close(right, left);
    try close(150, result.absorbed[0].test_value.ss);
    try std.testing.expectEqual(@as(usize, 1), result.absorbed[0].test_value.df);
    try close(1, result.conditional.?.type_i[0].ss);
    try close(9, result.conditional.?.type_i[0].f_value);
    try close(@as(f64, 1.0 / 3.0) - @sqrt(@as(f64, 3.0)) / (2 * std.math.pi), result.conditional.?.type_i[0].p_value);
    for (0..2) |block| {
        var sx: f64 = 0;
        var sy: f64 = 0;
        for (0..3) |j| {
            sx += result.within_x[block * 3 + j];
            sy += result.within_y[block * 3 + j];
        }
        try close(0, sx);
        try close(0, sy);
    }
}

test "GLM005 weighted absorption uses FREQ for DF and precision weights for projection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try dataset(a, &lib);
    for (0..2) |block| for ([_]f64{ 1, 2, 2 }, 0..) |y, j| try row(ds, .{ @floatFromInt(block + 1), 1, @floatFromInt(j), y + 10 * @as(f64, @floatFromInt(block)), if (j == 1) 2 else 1, if (j == 1) 2.9 else 1 });
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; absorb block; model y=x; freq f; weight w; run;");
    const data = try build(cx, spec);
    var result = try absorb.fit(cx, spec, data);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 8), result.n_used);
    try std.testing.expectEqual(@as(usize, 5), result.df_error);
    try close(2.0 / 3.0, result.sse);
    try close(2.0 / 15.0, result.mse);
    try close(0.5, result.conditional.?.model.fit.coefficients[0]);
    try close(1.0 / 30.0, result.conditional.?.model.fit.covariance[0]);
    var scaled = data;
    const weights = try a.alloc(f64, data.weights.len);
    for (data.weights, weights) |old, *dest| dest.* = 10 * old;
    scaled.weights = weights;
    var ten = try absorb.fit(cx, spec, scaled);
    defer ten.deinit(a);
    try close(10 * result.sse, ten.sse);
    try close(10 * result.mse, ten.mse);
    try close(result.conditional.?.model.fit.covariance[0], ten.conditional.?.model.fit.covariance[0]);
    try std.testing.expectEqual(@as(usize, 6), ds.rows.items.len);
    try std.testing.expectEqual(@as(f64, 2.9), ds.rows.items[1][5].num);
}

test "GLM005 nested absorption rank increments and conditional covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try dataset(a, &lib);
    for ([_]f64{ 1, 2, 1, 0 }, 0..) |delta, cell| for (0..2) |rep| {
        const block = cell / 2 + 1;
        const unit = cell % 2 + 1;
        try row(ds, .{ @floatFromInt(block), @floatFromInt(unit), @floatFromInt(rep), 10 * @as(f64, @floatFromInt(block)) + 3 * @as(f64, @floatFromInt(unit)) + @as(f64, @floatFromInt(rep)) * delta, 1, 1 });
    };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; absorb block unit; model y=x; run;");
    const data = try build(cx, spec);
    var result = try absorb.fit(cx, spec, data);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), result.absorbed_rank);
    try std.testing.expectEqual(@as(usize, 5), result.rank);
    try std.testing.expectEqual(@as(usize, 3), result.df_error);
    try std.testing.expectEqual(@as(usize, 1), result.absorbed[0].test_value.df);
    try std.testing.expectEqual(@as(usize, 2), result.absorbed[1].test_value.df);
    try std.testing.expectEqualStrings("unit(block)", result.absorbed[1].name);
    try close(1, result.sse);
    try close(1, result.conditional.?.model.fit.coefficients[0]);
    try close(1.0 / 6.0, result.conditional.?.model.fit.covariance[0]);
}

test "GLM005 missing keys exclusions sorted input and saturated absorbed-only boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try dataset(a, &lib);
    try row(ds, .{ std.math.nan(f64), 1, 0, 99, 1, 1 });
    try row(ds, .{ 1, 1, 0, 1, 1, 1 });
    try row(ds, .{ 1, 1, 0, 3, 1, 1 });
    try row(ds, .{ 2, 1, 0, 10, 0, 1 });
    try row(ds, .{ 2, 1, 0, 14, 1, 1 });
    try row(ds, .{ 2, 1, 0, std.math.nan(f64), 1, 1 });
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; absorb block; model y= / noint; weight w; run;");
    try std.testing.expect(spec.intercept);
    const data = try build(cx, spec);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 5 }, data.source_rows);
    var result = try absorb.fit(cx, spec, data);
    defer result.deinit(a);
    try std.testing.expect(result.conditional == null);
    try std.testing.expectEqual(@as(usize, 2), result.rank);
    try std.testing.expectEqual(@as(usize, 1), result.df_error);
    try close(2, result.sse);
    try close(2, result.mse);
    try row(ds, .{ 1, 1, 0, 5, 1, 1 });
    try std.testing.expectError(error.ParseError, build(cx, spec));
    try std.testing.expect(d.hasErrors());
    var singleton = Dataset.init(a, "single");
    for ([_][]const u8{ "block", "y" }) |name| _ = try singleton.addColumn(name, .num);
    for ([_]f64{ 1, 2, 4 }, 0..) |y, i| try singleton.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y } });
    try lib.put("single", &singleton);
    const one = try parse(cx, "proc glm data=single; absorb block; model y=; run;");
    const one_data = try build(cx, one);
    var saturated = try absorb.fit(cx, one, one_data);
    defer saturated.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), saturated.df_error);
    try std.testing.expect(std.math.isNan(saturated.mse));
    try close(0, saturated.sse);
}

test "GLM005 confounded predictor has zero effect DF without fabricated inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try dataset(a, &lib);
    for ([_]f64{ 1, 2, 3, 4 }, 0..) |y, i| try row(ds, .{ @floatFromInt(i / 2 + 1), 1, 10 * @as(f64, @floatFromInt(i / 2 + 1)), y, 1, 1 });
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc glm; absorb block; model y=x; run;");
    var result = try absorb.fit(cx, spec, try build(cx, spec));
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), result.rank);
    try std.testing.expectEqual(@as(usize, 2), result.df_error);
    try close(1, result.sse);
    try std.testing.expectEqual(@as(usize, 0), result.conditional.?.type_iii[0].df);
    try std.testing.expect(std.math.isNan(result.conditional.?.type_iii[0].f_value));
    try std.testing.expect(std.math.isNan(result.conditional.?.model.fit.se[0]));
}

test "GLM005 interactivity disables for unequal response missing patterns and BY" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "z", "g" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 0, 1, std.math.nan(f64), 1 }, .{ 1, std.math.nan(f64), 3, 1 }, .{ 2, 5, 5, 2 }, .{ 3, 7, 7, 2 } }) |values| {
        var cells: [4]Value = undefined;
        for (values, 0..) |v, i| cells[i] = .{ .num = v };
        try ds.appendRow(&cells);
    }
    try lib.put("sample", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const separate = try parse(cx, "proc glm; model y z=x; run;");
    try std.testing.expect(!try glm.canContinue(cx, separate));
    const common = try parse(cx, "proc glm manova; model y z=x; run;");
    try std.testing.expect(try glm.canContinue(cx, common));
    const by = try parse(cx, "proc glm; by g; model y=; run;");
    try std.testing.expect(!try glm.canContinue(cx, by));
}
