//! Public Heights data, SAS/STAT15.4 physical pp.6618-6623. Independent
//! cell-mean/rational variance tests fix likelihood normalization and inference.
const std = @import("std");
const t = std.testing;
const mixed = @import("mixed_fit.zig");
const y = [_]f64{ 67, 66, 64, 71, 72, 63, 63, 67, 69, 68, 70, 63, 64, 67, 66, 67, 67, 69 };
const family = [_]usize{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3 };
const gender = [_]usize{ 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 1, 0, 0, 1, 1, 1 };
fn fixed(a: std.mem.Allocator) ![]f64 {
    const x = try a.alloc(f64, 18 * 15);
    @memset(x, 0);
    for (family, gender, 0..) |f, g, i| {
        x[i * 15] = 1;
        x[i * 15 + 1 + g] = 1;
        x[i * 15 + 3 + f] = 1;
        x[i * 15 + 7 + f * 2 + g] = 1;
    }
    return x;
}
fn random(a: std.mem.Allocator) !mixed.Model {
    const x = try a.alloc(f64, 18 * 3);
    @memset(x, 0);
    for (gender, 0..) |g, i| {
        x[i * 3] = 1;
        x[i * 3 + 1 + g] = 1;
    }
    const k1 = try a.alloc(f64, 18 * 18);
    const k2 = try a.alloc(f64, 18 * 18);
    for (0..18) |i| for (0..18) |j| {
        k1[i * 18 + j] = if (family[i] == family[j]) 1 else 0;
        k2[i * 18 + j] = if (family[i] == family[j] and gender[i] == gender[j]) 1 else 0;
    };
    const c = try a.alloc(mixed.Component, 2);
    c[0] = .{ .name = "Family", .kernel = k1, .columns = 4 };
    c[1] = .{ .name = "Family*Gender", .kernel = k2, .columns = 8 };
    return .{ .x = x, .y = &y, .n = 18, .p = 3, .components = c };
}
test "MIXED002 fixed Heights REML determinant and equal-cell TypeIII contrasts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try mixed.fit(a, .{ .x = try fixed(a), .y = &y, .n = 18, .p = 15 }, .{});
    try t.expectEqual(@as(usize, 8), fit.rank);
    try t.expectEqual(@as(usize, 10), fit.df_error);
    try t.expect(fit.converged);
    try t.expectApproxEqAbs(@as(f64, 2.1), fit.residual_variance, 2e-9);
    // Eight cell sizes3,2,3,3,1,1,2,3 have product324. The retained
    // GLM-coded basis is an integer determinant-one transform of cell means.
    const ll = 10 * (1 + @log(2 * std.math.pi) + @log(@as(f64, 2.1))) + @log(@as(f64, 324));
    try t.expectApproxEqAbs(ll, fit.minus2loglik, 2e-8);
    try t.expectApproxEqAbs(ll + 2, fit.aic, 2e-8);
    try t.expectApproxEqAbs(ll + 2.5, fit.aicc.?, 2e-8);
    try t.expectApproxEqAbs(ll + @log(@as(f64, 10)), fit.bic.?, 2e-8);
    var l = [_]f64{0} ** 15;
    l[1] = 1;
    l[2] = -1;
    for (0..4) |f| {
        l[7 + f * 2] = 0.25;
        l[8 + f * 2] = -0.25;
    }
    const gender_test = try mixed.testContrast(a, fit, &l, 1, 10);
    // Gender mean difference=-19/6; variance=(2.1/16)*sum(1/cell_n)=91/160.
    try t.expectApproxEqAbs(@as(f64, (19.0 / 6.0) * (19.0 / 6.0) / (91.0 / 160.0)), gender_test.f, 2e-8);
    try t.expectApproxEqAbs(@as(f64, 0.0018), gender_test.p, 0.00005);
    var family_l = [_]f64{0} ** 45;
    var interaction_l = [_]f64{0} ** 45;
    for (0..3) |f| {
        family_l[f * 15 + 3 + f] = 1;
        family_l[f * 15 + 6] = -1;
        for (0..2) |g| {
            family_l[f * 15 + 7 + f * 2 + g] = 0.5;
            family_l[f * 15 + 13 + g] = -0.5;
        }
        interaction_l[f * 15 + 7 + f * 2] = 1;
        interaction_l[f * 15 + 8 + f * 2] = -1;
        interaction_l[f * 15 + 13] = -1;
        interaction_l[f * 15 + 14] = 1;
    }
    const ft = try mixed.testContrast(a, fit, &family_l, 3, 10);
    const it = try mixed.testContrast(a, fit, &interaction_l, 3, 10);
    try t.expectApproxEqAbs(@as(f64, 5.90), ft.f, 0.005);
    try t.expectApproxEqAbs(@as(f64, 0.0139), ft.p, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 2.89), it.f, 0.005);
    try t.expectApproxEqAbs(@as(f64, 0.0889), it.p, 0.00005);
}
test "MIXED002 random Heights profiled REML covariance estimates and fixed inference" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try mixed.fit(a, try random(a), .{ .bic_n = 4, .convergence = 1e-12 });
    try t.expect(fit.converged);
    try t.expectEqual(@as(usize, 2), fit.rank);
    for ([_]f64{ 2.4010, 1.7657, 2.1668 }, fit.variances) |want, got| try t.expectApproxEqAbs(want, got, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 71.02245869), fit.minus2loglik, 0.00000005);
    try t.expectApproxEqAbs(fit.minus2loglik + 6, fit.aic, 1e-12);
    try t.expectApproxEqAbs(fit.minus2loglik + 8, fit.aicc.?, 1e-12);
    try t.expectApproxEqAbs(fit.minus2loglik + 3 * @log(@as(f64, 4)), fit.bic.?, 1e-12);
    const test_result = try mixed.testContrast(a, fit, &.{ 0, 1, -1 }, 1, 3);
    try t.expectApproxEqAbs(@as(f64, 7.95), test_result.f, 0.005);
    try t.expectApproxEqAbs(@as(f64, 0.0667), test_result.p, 0.00005);
    var previous = std.math.inf(f64);
    for (fit.iterations) |row| {
        try t.expect(row.objective <= previous + 1e-10);
        try t.expect(row.evaluations > 0);
        previous = row.objective;
    }
    // Every displayed iteration quantity from Figure84.11 is checked. The
    // computation uses only data/design derivatives; no iteration row is stored
    // in the production estimator. The first row is the residual-only baseline.
    const objectives = [_]f64{ 74.11074833, 71.51614003, 71.13845990, 71.03613556, 71.02281757, 71.02245904, 71.02245869 };
    const criteria = [_]f64{ 0, 0.01441208, 0.00412226, 0.00058188, 0.00001689, 0.00000002, 0 };
    try t.expectEqual(@as(usize, 7), fit.iterations.len);
    for (fit.iterations, 0..) |row, i| {
        try t.expectEqual(i, row.iteration);
        try t.expectEqual(@as(usize, if (i == 1) 2 else 1), row.evaluations);
        try t.expectApproxEqAbs(objectives[i], row.objective, 0.000000005);
        if (i > 0) try t.expectApproxEqAbs(criteria[i], row.criterion.?, 0.000000005) else try t.expect(row.criterion == null);
    }
}
test "MIXED002 independent variance boundary and nonconvergence status" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const kernel = [_]f64{ 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1 };
    const model = mixed.Model{ .x = &.{ 1, 1, 1, 1, 1, 1 }, .y = &.{ 1, -1, 1, -1, 1, -1 }, .n = 6, .p = 1, .components = &.{.{ .name = "group", .kernel = &kernel, .columns = 3 }} };
    const fit = try mixed.fit(a, model, .{ .bic_n = 3 });
    try t.expect(fit.converged);
    try t.expectApproxEqAbs(@as(f64, 0), fit.variances[0], 1e-12);
    try t.expectApproxEqAbs(@as(f64, 1.2), fit.residual_variance, 1e-12);
    const limited = try mixed.fit(a, try random(a), .{ .maxiter = 0 });
    try t.expect(!limited.converged);
    try t.expectEqual(mixed.Status.max_iterations, limited.status);
}

test "MIXED002 balanced random intercept ML REML closed forms and information dimensions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const kernel = [_]f64{ 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1 };
    const model = mixed.Model{ .x = &.{ 1, 1, 1, 1, 1, 1 }, .y = &.{ -1, 1, 1, 3, 3, 5 }, .n = 6, .p = 1, .components = &.{.{ .name = "group", .kernel = &kernel, .columns = 3 }} };
    // Within SS=6 on3 dimensions ->sigma²=2. Between SS=16 on
    // two REML dimensions / three ML dimensions. lambda=sigma²+2*tau².
    const reml = try mixed.fit(a, model, .{ .bic_n = 3, .convergence = 1e-12 });
    const ml = try mixed.fit(a, model, .{ .method = .ml, .bic_n = 3, .convergence = 1e-12 });
    try t.expect(reml.converged and ml.converged);
    try t.expectApproxEqAbs(@as(f64, 2), reml.variances[1], 1e-7);
    try t.expectApproxEqAbs(@as(f64, 3), reml.variances[0], 1e-7);
    try t.expectApproxEqAbs(@as(f64, 2), ml.variances[1], 1e-6);
    try t.expectApproxEqAbs(@as(f64, 5.0 / 3.0), ml.variances[0], 1e-6);
    const ml_likelihood = 6 * (1 + @log(2 * std.math.pi)) + 3 * @log(@as(f64, 2)) + 3 * @log(@as(f64, 16.0 / 3.0));
    try t.expectApproxEqAbs(ml_likelihood, ml.minus2loglik, 1e-10);
    const boundary = try mixed.fit(a, .{ .x = model.x, .y = &.{ 1, -1, 1, -1, 1, -1 }, .n = 6, .p = 1, .components = model.components }, .{ .bic_n = 3 });
    // A variance at its zero constraint is not counted in modern SAS IC d.
    try t.expectApproxEqAbs(boundary.minus2loglik + 2, boundary.aic, 1e-12);
    try t.expectApproxEqAbs(boundary.minus2loglik + @log(@as(f64, 3)), boundary.bic.?, 1e-12);
    const small = try mixed.fit(a, .{ .x = &.{ 1, 1, 1 }, .y = &.{ -1, 0, 1 }, .n = 3, .p = 1 }, .{});
    // SAS AICC clamps n*=max(N-rank,d+2), here max(2,3)=3.
    try t.expectApproxEqAbs(small.minus2loglik + 6, small.aicc.?, 1e-12);
}

fn wordsEqual(expected: []const u8, actual: []const u8) !void {
    var left = std.mem.tokenizeAny(u8, expected, " \t\r\n");
    var right = std.mem.tokenizeAny(u8, actual, " \t\r\n");
    while (left.next()) |word| try t.expectEqualStrings(word, right.next() orelse return error.MissingOutputField);
    try t.expect(right.next() == null);
}
test "MIXED002 complete original numerical tables and actual iteration listing" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const render = @import("mixed_render.zig");
    const fitted = try mixed.fit(a, .{ .x = try fixed(a), .y = &y, .n = 18, .p = 15 }, .{});
    var gender_l = [_]f64{0} ** 15;
    gender_l[1] = 1;
    gender_l[2] = -1;
    for (0..4) |f| {
        gender_l[7 + f * 2] = 0.25;
        gender_l[8 + f * 2] = -0.25;
    }
    var family_l = [_]f64{0} ** 45;
    var interaction_l = [_]f64{0} ** 45;
    for (0..3) |f| {
        family_l[f * 15 + 3 + f] = 1;
        family_l[f * 15 + 6] = -1;
        for (0..2) |g| {
            family_l[f * 15 + 7 + f * 2 + g] = 0.5;
            family_l[f * 15 + 13 + g] = -0.5;
        }
        interaction_l[f * 15 + 7 + f * 2] = 1;
        interaction_l[f * 15 + 8 + f * 2] = -1;
        interaction_l[f * 15 + 13] = -1;
        interaction_l[f * 15 + 14] = 1;
    }
    var tests: [3]render.NamedTest = undefined;
    for ([_][]const f64{ &gender_l, &family_l, &interaction_l }, [_][]const u8{ "Gender", "Family", "Family*Gender" }, &tests) |l, name, *dest| {
        const result = try mixed.testContrast(a, fitted, l, l.len / 15, 10);
        dest.* = .{ .name = name, .num_df = result.num_df, .den_df = result.den_df, .f = result.f, .p = result.p };
    }
    var out: std.ArrayList(u8) = .empty;
    try render.render(a, &out, fitted, &.{"Residual"}, &tests, .{});
    const fixed_expected = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/fixtures/stat/mixed/heights_fixed_tables.txt", a, .limited(1 << 20));
    try wordsEqual(fixed_expected, out.items);
    out.clearRetainingCapacity();
    const random_fit = try mixed.fit(a, try random(a), .{ .bic_n = 4 });
    const result = try mixed.testContrast(a, random_fit, &.{ 0, 1, -1 }, 1, 3);
    const random_tests = [_]render.NamedTest{.{ .name = "Gender", .num_df = 1, .den_df = 3, .f = result.f, .p = result.p }};
    try render.render(a, &out, random_fit, &.{ "Family", "Family*Gender", "Residual" }, &random_tests, .{});
    const random_expected = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/fixtures/stat/mixed/heights_random_tables.txt", a, .limited(1 << 20));
    try wordsEqual(random_expected, out.items);
    out.clearRetainingCapacity();
    try render.render(a, &out, random_fit, &.{ "Family", "Family*Gender", "Residual" }, &random_tests, .{ .noitprint = true, .notest = true });
    try t.expect(std.mem.indexOf(u8, out.items, "Iteration History") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Type 3 Tests") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Covariance Parameter Estimates") != null);
}

test "MIXED002 precision weights preserve GLS mean likelihood and scale identity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, 1, 1, 1 };
    const response = [_]f64{ 0, 1, 2, 3 };
    const fit = try mixed.fit(a, .{ .x = &x, .y = &response, .n = 4, .p = 1, .weights = &.{ 1, 2, 1, 2 } }, .{});
    // Weighted mean10/6=5/3, weighted SSE22/3, REMLdf3, det(R0)=1/4,
    // and X'R0^-1X=6. No values are taken from the fitted output.
    const variance: f64 = 22.0 / 9.0;
    const objective = 3 * (1 + @log(2 * std.math.pi) + @log(variance)) + @log(@as(f64, 1.5));
    try t.expectApproxEqAbs(@as(f64, 5.0 / 3.0), fit.coefficients[0], 1e-13);
    try t.expectApproxEqAbs(variance, fit.residual_variance, 1e-13);
    try t.expectApproxEqAbs(@as(f64, 11.0 / 27.0), fit.covariance[0], 1e-13);
    try t.expectApproxEqAbs(objective, fit.minus2loglik, 1e-12);
    const scaled = try mixed.fit(a, .{ .x = &x, .y = &response, .n = 4, .p = 1, .weights = &.{ 3, 6, 3, 6 } }, .{});
    try t.expectApproxEqAbs(3 * variance, scaled.residual_variance, 1e-12);
    try t.expectApproxEqAbs(fit.covariance[0], scaled.covariance[0], 1e-13);
    try t.expectApproxEqAbs(objective, scaled.minus2loglik, 1e-12);
    try t.expectError(error.EvaluationLimit, mixed.fit(a, try random(a), .{ .maxfunc = 1 }));
}

test "MIXED002 known covariance GLS matches fitted likelihood without reprofiling" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = try random(a);
    const optimized = try mixed.fit(a, model, .{ .bic_n = 4 });
    const evaluated = try mixed.knownCovariance(a, model, optimized.variances);
    for (optimized.coefficients, evaluated.coefficients) |x, y0| try t.expectApproxEqAbs(x, y0, 1e-9);
    for (optimized.covariance, evaluated.covariance) |x, y0| try t.expectApproxEqAbs(x, y0, 1e-10);
    try t.expectApproxEqAbs(optimized.minus2loglik, evaluated.minus2reml, 1e-8);
    const result = try mixed.testContrast(a, evaluated, &.{ 0, 1, -1 }, 1, 3);
    try t.expectApproxEqAbs(@as(f64, 7.95), result.f, 0.005);
    // A known residual variance remains exactly4 despite a different data SSE.
    const known = try mixed.knownCovariance(a, .{ .x = &.{ 1, 1, 1 }, .y = &.{ 0, 1, 2 }, .n = 3, .p = 1 }, &.{4});
    try t.expectApproxEqAbs(@as(f64, 1), known.coefficients[0], 1e-14);
    try t.expectApproxEqAbs(@as(f64, 4.0 / 3.0), known.covariance[0], 1e-14);
    try t.expectApproxEqAbs(3 * @log(@as(f64, 4)) + @log(@as(f64, 0.75)) + 0.5 + 2 * @log(2 * std.math.pi), known.minus2reml, 1e-12);
}
