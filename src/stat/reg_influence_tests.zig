//! REG012 independent hand fits, explicit deletion refits and eigen identities.
const std = @import("std");
const influence = @import("reg_influence.zig");
const collin = @import("reg_collinearity.zig");
const qr = @import("reg_fit.zig");
const reg = @import("reg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;
const A = std.mem.Allocator;
fn close(w: f64, g: f64) !void {
    try std.testing.expectApproxEqAbs(w, g, 1e-11 * @max(1, @abs(w)));
}
const x = [_]f64{ 1, 0, 1, 1, 1, 2, 1, 3, 1, 4 };
const y = [_]f64{ 1, 2, 2, 4, 8 };

test "REG012 hand influence quantities and size-adjusted thresholds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try qr.fit(a, &x, &y, 5, 2, null);
    const result = try influence.compute(a, &x, &y, null, fit);
    const row = result.rows[4];
    // Full beta=(.2,1.6), SSE28/5; deleting last row gives beta=(.9,.9),
    // SSE7/10 and MSE7/20. G diagonal=(3/5,1/10), h5=3/5.
    try close(1.4, row.residual);
    try close(0.6, row.leverage);
    try close(@sqrt(@as(f64, 21.0 / 8.0)), row.student);
    try close(@sqrt(@as(f64, 14)), row.rstudent);
    try close(@sqrt(@as(f64, 21)), row.dffits);
    try close(63.0 / 32.0, row.cookd);
    try close(45.0 / 512.0, row.covratio);
    try close(3.5, row.press_residual);
    try close(0.35, row.deleted_mse);
    try close(-7 / @sqrt(@as(f64, 21)), row.dfbetas[0]);
    try close(@sqrt(@as(f64, 14)), row.dfbetas[1]);
    for (row.deleted_coefficients) |v| try close(0.9, v);
    try close(16805.0 / 784.0, result.press.?);
    try close(0.8, result.leverage_cutoff);
    try close(2 * @sqrt(@as(f64, 2.0 / 5.0)), result.dffits_cutoff);
    try close(2 / @sqrt(@as(f64, 5)), result.dfbetas_cutoff);
    try close(1.2, result.covratio_cutoff);
}

test "REG012 precision-weight influence matches every explicit deleted fit and determinant ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const weights = [_]f64{ 1, 2, 1, 0.5, 3 };
    const full = try qr.fit(a, &x, &y, 5, 2, &weights);
    const result = try influence.compute(a, &x, &y, &weights, full);
    const determinant = full.covariance[0] * full.covariance[3] - full.covariance[1] * full.covariance[2];
    for (result.rows, 0..) |row, omit| {
        var reduced_x: [8]f64 = undefined;
        var reduced_y: [4]f64 = undefined;
        var reduced_w: [4]f64 = undefined;
        var next: usize = 0;
        for (0..5) |i| {
            if (i == omit) continue;
            @memcpy(reduced_x[next * 2 ..][0..2], x[i * 2 ..][0..2]);
            reduced_y[next] = y[i];
            reduced_w[next] = weights[i];
            next += 1;
        }
        const deleted = try qr.fit(a, &reduced_x, &reduced_y, 4, 2, &reduced_w);
        for (row.deleted_coefficients, deleted.coefficients) |actual, want| try close(want, actual);
        try close(deleted.mse, row.deleted_mse);
        const deleted_prediction = deleted.coefficients[0] + deleted.coefficients[1] * x[omit * 2 + 1];
        try close(y[omit] - deleted_prediction, row.press_residual);
        try close((full.fitted[omit] - deleted_prediction) / @sqrt(deleted.mse * full.leverage[omit] / weights[omit]), row.dffits);
        const deleted_determinant = deleted.covariance[0] * deleted.covariance[3] - deleted.covariance[1] * deleted.covariance[2];
        try close(deleted_determinant / determinant, row.covratio);
        for (row.dfbetas, 0..) |value, j| try close((full.coefficients[j] - deleted.coefficients[j]) / @sqrt(deleted.mse * full.covariance_unscaled[j * 2 + j]), value);
    }
}

test "REG012 zero weights unit leverage deleted DF and alias domains are explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const highx = [_]f64{ 1, 0, 1, 0, 1, 1 };
    const highy = [_]f64{ 1, 3, 5 };
    const high = try qr.fit(a, &highx, &highy, 3, 2, null);
    const result = try influence.compute(a, &highx, &highy, null, high);
    try std.testing.expectEqual(influence.Status.unit_leverage, result.rows[2].status);
    try std.testing.expect(result.press == null);
    try std.testing.expect(std.math.isNan(result.rows[2].rstudent) and std.math.isNan(result.rows[2].covratio));
    try std.testing.expectEqual(influence.Status.no_deleted_variance, result.rows[0].status);
    try std.testing.expect(std.math.isFinite(result.rows[0].press_residual));
    const weights = [_]f64{ 1, 1, 1, 1, 0 };
    const fit = try qr.fit(a, &x, &y, 5, 2, &weights);
    const excluded = try influence.compute(a, &x, &y, &weights, fit);
    try std.testing.expectEqual(influence.Status.excluded, excluded.rows[4].status);
    try std.testing.expect(std.math.isNan(excluded.rows[4].dffits));
    const aliasx = [_]f64{ 1, 0, 0, 1, 1, 2, 1, 2, 4, 1, 3, 6, 1, 4, 8 };
    const alias = try qr.fit(a, &aliasx, &y, 5, 3, null);
    try std.testing.expectError(error.ExecError, influence.compute(a, &aliasx, &y, null, alias));
    var frequency = fit;
    frequency.n_used = 8;
    try std.testing.expectError(error.ExecError, influence.compute(a, &x, &y, &weights, frequency));
}

test "REG012 centered collinearity eigenvalues proportions and near-dependency have hand solutions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const matrix = [_]f64{ 1, -2, -1, 1, -1, -2, 1, 1, 2, 1, 2, 1 };
    const centered = try collin.compute(a, &matrix, 4, 3, null, true, true);
    try std.testing.expectEqual(@as(usize, 2), centered.columns);
    for (centered.eigenvalues, [_]f64{ 1.8, 0.2 }) |actual, want| try close(want, actual);
    try close(3, centered.condition_indices[1]);
    for (centered.variance_proportions, [_]f64{ 0.1, 0.1, 0.9, 0.9 }) |actual, want| try close(want, actual);
    const raw = try collin.compute(a, &matrix, 4, 3, null, true, false);
    for (raw.eigenvalues, [_]f64{ 1.8, 1, 0.2 }) |actual, want| try close(want, actual);
    try close(1, raw.variance_proportions[3]);
    try close(0, raw.variance_proportions[0]);
    try close(0, raw.variance_proportions[6]);
    var shifted = matrix;
    for (0..4) |i| {
        shifted[3 * i + 1] += 1000;
        shifted[3 * i + 2] -= 7;
    }
    const invariant = try collin.compute(a, &shifted, 4, 3, null, true, true);
    for (invariant.eigenvalues, centered.eigenvalues) |v, w| try close(w, v);
    const uncentered = try collin.compute(a, &shifted, 4, 3, null, true, false);
    try std.testing.expect(uncentered.condition_indices[2] > 100);
    var near: [12]f64 = undefined;
    for ([_]f64{ -1, -1, 1, 1 }, [_]f64{ -1, 1, -1, 1 }, 0..) |u, v, i| {
        @memcpy(near[3 * i ..][0..3], &[_]f64{ 1, 128 * u + v, 128 * u - v });
    }
    const weak = try collin.compute(a, &near, 4, 3, null, true, true);
    // rho=(128²-1)/(128²+1), roots2*128²/(128²+1),2/(128²+1), CI128.
    try close(32768.0 / 16385.0, weak.eigenvalues[0]);
    try close(2.0 / 16385.0, weak.eigenvalues[1]);
    try close(128, weak.condition_indices[1]);
    try close(16384.0 / 16385.0, weak.variance_proportions[2]);
    try close(16384.0 / 16385.0, weak.variance_proportions[3]);
}

test "REG012 collinearity precision and frequency crossproducts match explicit row replication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const matrix = [_]f64{ 1, 1, 2, 1, 2, 1, 1, 3, 4, 1, 4, 2 };
    const weights = [_]f64{ 1, 2, 1, 2 };
    const weighted = try collin.compute(a, &matrix, 4, 3, &weights, true, true);
    const repeated = [_]f64{ 1, 1, 2, 1, 2, 1, 1, 2, 1, 1, 3, 4, 1, 4, 2, 1, 4, 2 };
    const expanded = try collin.compute(a, &repeated, 6, 3, null, true, true);
    for (weighted.crossproduct, expanded.crossproduct) |v, w| try close(w, v);
    for (weighted.eigenvalues, expanded.eigenvalues) |v, w| try close(w, v);
    try std.testing.expectError(error.ExecError, collin.compute(a, &.{ 1, 1, 2, 1, 2, 4, 1, 3, 6 }, 3, 3, null, true, true));
    try std.testing.expectError(error.ExecError, collin.compute(a, &matrix, 4, 3, null, false, true));
}

fn setup(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    const xs = [_]f64{ -2, -1, 1, 2, -2, -1, 1, 2 };
    const zs = [_]f64{ -1, -2, 2, 1, -1, -2, 2, 1 };
    const ys = [_]f64{ 6, 8, 10, 16, 4, 10, 12, 14 };
    for (xs, zs, ys) |xx, z, yv| try ds.appendRow(&.{ .{ .num = xx }, .{ .num = z }, .{ .num = yv }, .{ .num = 1 } });
    try lib.put("sample", ds);
}
fn run(a: A, lib: *Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &out, try lex.tokenize(a, source, d));
    return out.items;
}
test "REG012 producers emit actual requested tables and reject unsupported conventions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const listing = try run(a, &lib, &d, "proc reg data=sample; model y=x z / influence collinoint; run;");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Collinearity Diagnostics"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Output Statistics"));
    try std.testing.expect(std.mem.indexOf(u8, listing, "DFBETAS") != null and std.mem.indexOf(u8, listing, "20.48000") != null);
    try std.testing.expectEqual(@as(usize, 0), (try run(a, &lib, &d, "proc reg data=sample noprint; model y=x z / influence collinoint; run;")).len);
    for ([_][]const u8{ "proc reg data=sample; model y=x z / influence; weight w; run;", "proc reg data=sample; model y=x z / influence; freq w; run;", "proc reg data=sample; model y=x z / collin collinoint; run;", "proc reg data=sample; model y=x z / collinoint noint; run;", "proc reg data=sample; model y=x z / influence r clm cli; run;" }) |source| {
        var errors = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &errors, source));
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), errors.hasErrors()));
    }
    var errors = diag.Diagnostics.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &errors, "proc reg data=sample; model y=x z / influenc; run;"));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), errors.hasErrors()));
}

test "REG012 whole listing permits only independently bounded zero residual sum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_reg_influence.txt", a, .limited(1 << 20));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, "~"));
    const anchor = "Sum of Residuals 0~";
    const begin = std.mem.indexOf(u8, source, anchor).? + anchor.len;
    const end = std.mem.indexOfScalarPos(u8, source, begin, ' ').?;
    const declared = try std.fmt.parseFloat(f128, source[begin..end]);
    const u: f128 = 0x1p-53;
    const e = (8 * u / (1 - 8 * u)) * 208;
    const expected = e + (7 * u / (1 - 7 * u)) * (8 + e);
    try std.testing.expectApproxEqRel(expected, declared, 1e-30);
    try std.testing.expect(1e-9 > declared);
}
