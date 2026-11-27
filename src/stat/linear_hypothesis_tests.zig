//! Shared TEST mathematics verified on actual fitted designs, never stubs.
const std = @import("std");
const h = @import("linear_hypothesis.zig");
const ranks = @import("reg_diagnostics.zig");
const reg = @import("reg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const A = std.mem.Allocator;
fn close(want: f64, got: f64) !void {
    try std.testing.expectApproxEqAbs(want, got, 1e-12 * @max(1, @abs(want)));
}
const x = [_]f64{ 1, -2, -1, 1, -1, -2, 1, 1, 2, 1, 2, 1 };
const y = [_]f64{ 6, 8, 10, 16 };
fn model(a: A) !ranks.Result {
    return ranks.fit(a, &x, &y, 4, 3, null, true, 1e-9);
}

test "COMMON031 joint linear TEST actual covariance F chi-square and fractional denominator DF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fitted = try model(a);
    const geometry = h.fromRegression(fitted, 1e-9);
    const rows = [_]h.Row{ .{ .coefficients = &.{ 0, 1, 0 } }, .{ .coefficients = &.{ 0, 0, 1 } } };
    const result = try h.evaluate(a, geometry, &rows, null);
    // beta=(10,3,-1), SSE=4, SST=56, MSE=4. Joint slope SS=52.
    try std.testing.expectEqual(h.Status.estimable, result.status);
    try std.testing.expectEqual(@as(usize, 2), result.rank);
    try close(52, result.numerator_ss.?);
    try close(13, result.wald.?);
    try close(6.5, result.f.?);
    try close(1, result.denominator_df.?);
    try close(@sqrt(@as(f64, 1.0 / 14.0)), result.f_probability.?);
    try close(@exp(@as(f64, -6.5)), result.chi_square_probability.?); // chi-square2 exact tail
    const override = try h.evaluate(a, geometry, &rows, 4.7);
    try close(6.5, override.f.?);
    try close(std.math.pow(f64, 4.7 / (4.7 + 13), 4.7 / 2.0), override.f_probability.?);
    try close(result.chi_square_probability.?, override.chi_square_probability.?);
}

test "COMMON031 complex coefficients row scaling and dependent consistent constraints preserve rank" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const geometry = h.fromRegression(try model(a), 1e-9);
    const row = h.Row{ .coefficients = &.{ 0, 2, -3 }, .rhs = 5 };
    const result = try h.evaluate(a, geometry, &.{row}, null);
    // L beta-c=4; L G L'=113/18, hence SS=288/113, F=72/113.
    try close(288.0 / 113.0, result.numerator_ss.?);
    try close(72.0 / 113.0, result.f.?);
    try close(1 - 2 * std.math.atan(@sqrt(@as(f64, 72.0 / 113.0))) / std.math.pi, result.f_probability.?);
    for ([_]f64{ 1e-12, 1e12 }) |factor| {
        const values = [_]f64{ 0, 2 * factor, -3 * factor };
        const changed = try h.evaluate(a, geometry, &.{.{ .coefficients = &values, .rhs = 5 * factor }}, null);
        try close(result.f.?, changed.f.?);
        try std.testing.expectEqual(@as(usize, 1), changed.rank);
    }
    const dependent = try h.evaluate(a, geometry, &.{ .{ .coefficients = &.{ 0, 1, 0 } }, .{ .coefficients = &.{ 0, 0, 1 } }, .{ .coefficients = &.{ 0, 2, 3 } } }, null);
    try std.testing.expectEqual(@as(usize, 2), dependent.rank);
    try close(52, dependent.numerator_ss.?);
    const transformed = try h.evaluate(a, geometry, &.{ .{ .coefficients = &.{ 0, 2, -3 } }, .{ .coefficients = &.{ 0, 1, 1 } } }, null);
    try close(dependent.f.?, transformed.f.?);
    const inconsistent = try h.evaluate(a, geometry, &.{ .{ .coefficients = &.{ 0, 1, 0 } }, .{ .coefficients = &.{ 0, 2, 0 }, .rhs = 1 } }, null);
    try std.testing.expectEqual(h.Status.inconsistent, inconsistent.status);
    try std.testing.expect(inconsistent.f == null and inconsistent.numerator_ss == null);
}

test "COMMON031 reflexive g2 estimability orientation and missing inference differ from true zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try ranks.fit(a, &.{ 1, -1, -2, 1, 0, 0, 1, 1, 2, 1, 2, 4 }, &.{ 1, 2, 4, 4 }, 4, 3, null, true, 1e-9);
    const reordered = try ranks.fit(a, &.{ 1, -2, -1, 1, 0, 0, 1, 2, 1, 1, 4, 2 }, &.{ 1, 2, 4, 4 }, 4, 3, null, true, 1e-9);
    try std.testing.expectEqual(@as(usize, 2), original.fit.rank);
    const good = try h.evaluate(a, h.fromRegression(original, 1e-9), &.{.{ .coefficients = &.{ 0, 1, 2 } }}, null);
    const changed = try h.evaluate(a, h.fromRegression(reordered, 1e-9), &.{.{ .coefficients = &.{ 0, 2, 1 } }}, null);
    try close(6.05, good.numerator_ss.?);
    try close(121.0 / 7.0, good.f.?);
    try close(good.f.?, changed.f.?);
    try close(1 - 11 / @sqrt(@as(f64, 135)), good.f_probability.?);
    const bad = try h.evaluate(a, h.fromRegression(original, 1e-9), &.{.{ .coefficients = &.{ 0, 1, 0 } }}, null);
    try std.testing.expectEqual(h.Status.nonestimable, bad.status);
    try std.testing.expect(bad.numerator_ss == null and bad.wald == null and bad.f_probability == null);
    var exact = h.fromRegression(try model(a), 1e-9);
    exact.estimates = &.{ 10, 3, -1 }; // independently exact OLS estimates for the fixed design
    const zero = try h.evaluate(a, exact, &.{.{ .coefficients = &.{ 0, 1, 0 }, .rhs = 3 }}, null);
    try std.testing.expectEqual(h.Status.estimable, zero.status);
    try close(0, zero.f.?);
    try close(1, zero.f_probability.?);
    const rank_zero = try h.evaluate(a, exact, &.{.{ .coefficients = &.{ 0, 0, 0 } }}, null);
    try std.testing.expectEqual(h.Status.zero_rank, rank_zero.status);
    try std.testing.expect(rank_zero.f == null);
    try close(0, rank_zero.numerator_ss.?);
    exact.scale = null;
    const unavailable = try h.evaluate(a, exact, &.{.{ .coefficients = &.{ 0, 1, 0 } }}, null);
    try std.testing.expectEqual(h.Status.estimable, unavailable.status);
    try std.testing.expect(unavailable.numerator_ss != null and unavailable.f == null and unavailable.chi_square_probability == null);
}

fn setup(a: A, lib: *@import("../exec.zig").Library) !void {
    const ds = try a.create(@import("../dataset.zig").Dataset);
    ds.* = @import("../dataset.zig").Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (y, 0..) |value, i| try ds.appendRow(&.{ .{ .num = x[3 * i + 1] }, .{ .num = x[3 * i + 2] }, .{ .num = value } });
    try lib.put("sample", ds);
}
fn run(a: A, lib: *@import("../exec.zig").Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var listing: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &listing, try lex.tokenize(a, source, d));
    return listing.items;
}
test "COMMON031 REG consumer labels multiple TEST defaults and procedure-specific applicability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const listing = try run(a, &lib, &d, "proc reg data=sample; model y=x z; test x,z; complex: test 2*x-3*z=5; run;");
    try std.testing.expect(std.mem.indexOf(u8, listing, "Test 1 Results for Dependent Variable y") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Test complex Results for Dependent Variable y") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Numerator 2 26.00000 6.50 0.2673") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Denominator 1 4.00000") != null);
    for ([_][]const u8{ "proc reg data=sample; test x; model y=x z; run;", "proc reg data=sample; model y=x z; test absent; run;", "proc reg data=sample; model y=x z; test x / chisq; run;", "proc reg data=sample; model y=x z; test x / ddf=3; run;" }) |source| {
        var errors = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &errors, source));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), errors.hasErrors()));
    }
    var errors = diag.Diagnostics.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(a, &lib, &errors, "proc reg data=sample; model y=x z; test x / print; run;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), errors.hasErrors()));
}

const shared = @import("test_statement.zig");
fn options(a: A, d: *diag.Diagnostics, procedure: []const u8, source: []const u8) !shared.Options {
    const tokens = try lex.tokenize(a, source, d);
    return shared.parse(.{ .arena = a, .lib = undefined, .diags = d }, procedure, tokens[0 .. tokens.len - 1]);
}
test "COMMON031 shared effect TEST grammar defaults aliases and procedure applicability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const defaults = try options(a, &d, "ORTHOREG", "");
    try std.testing.expectEqualSlices(bool, &.{ false, false, true }, &defaults.types);
    try std.testing.expect(!defaults.chisq and !defaults.intercept);
    const explicit = try options(a, &d, "PLM", "B A A*B / htype=1,3 df=3,.,4.7 chisq ei eii eiii int");
    try std.testing.expectEqualStrings("A*B", explicit.effects[2]);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true }, &explicit.types);
    try std.testing.expectEqualSlices(bool, &.{ true, true, true }, &explicit.coefficients);
    try close(3, explicit.denominator_df[0].?);
    try std.testing.expect(explicit.denominator_df[1] == null);
    try close(4.7, explicit.denominator_df[2].?);
    try std.testing.expect(explicit.chisq and explicit.intercept);
    for ([_][]const u8{ "ICPHREG", "LIFEREG", "ORTHOREG", "PLM", "PROBIT", "SURVEYPHREG", "SURVEYREG", "RELIABILITY" }) |name| try std.testing.expect(shared.appliesTo(name));
    try std.testing.expect(!shared.appliesTo("REG") and !shared.appliesTo("GLM"));
    for ([_][]const u8{ "/ htype=4", "/ htype=1,", "/ ddf=0", "/ ddf=3,", "/ ddf=-1", "/ adjust=tukey", "x=0" }) |source| {
        var errors = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, options(a, &errors, "PLM", source));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), errors.hasErrors()));
    }
    var errors = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, options(a, &errors, "REG", "x / chisq"));
}

test "COMMON031 real Type I versus Type III hypotheses coefficient tables and DDF ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const geometry = h.fromRegression(try model(a), 1e-9);
    const first = [_]h.Row{.{ .coefficients = &.{ 0, 1, 0.8 } }}; // residualize response on x before adding z
    const partial = [_]h.Row{.{ .coefficients = &.{ 0, 1, 0 } }};
    const z = [_]h.Row{.{ .coefficients = &.{ 0, 0, 1 } }};
    const catalog = [_]shared.Effect{ .{ .name = "x", .rows = .{ &first, &partial, &partial } }, .{ .name = "z", .rows = .{ &z, &z, &z } } };
    const report = try shared.evaluate(a, geometry, &catalog, try options(a, &d, "ORTHOREG", "z x / htype=1,3 ddf=.,4.7 e chisq"), .f);
    try std.testing.expectEqual(@as(usize, 4), report.tests.len);
    try std.testing.expectEqual(@as(usize, 6), report.coefficients.len);
    try std.testing.expectEqualStrings("Tests1", report.tests[0].table_name);
    try std.testing.expectEqualStrings("Tests3", report.tests[2].table_name);
    try std.testing.expectEqualStrings("z", report.tests[0].effect);
    try std.testing.expectEqualStrings("x", report.tests[1].effect);
    try close(1, report.tests[0].result.denominator_df.?);
    try close(4.7, report.tests[1].result.denominator_df.?);
    try close(48.4, report.tests[1].result.numerator_ss.?);
    try close(32.4, report.tests[3].result.numerator_ss.?);
    for (report.coefficients) |table| {
        try std.testing.expectEqualStrings("Coef", table.table_name);
        try std.testing.expectEqual(@as(usize, 1), table.rows.len);
    }
    for (report.tests) |row| try std.testing.expect(row.show_f and row.show_chisq);
    var asymptotic = geometry;
    asymptotic.denominator_df = null;
    const native = try shared.evaluate(a, asymptotic, &catalog, try options(a, &d, "LIFEREG", "/ chisq"), .chi_square);
    try std.testing.expectEqual(@as(usize, 2), native.tests.len);
    for (native.tests) |row| {
        try std.testing.expect(!row.show_f and row.show_chisq);
        try std.testing.expect(row.result.f == null and row.result.chi_square_probability != null);
    }
}

test "COMMON031 actual aliased class design supplies multirow effect and intercept tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const fit = try ranks.fit(a, &.{ 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1 }, &.{ 1, 3, 4, 6, 7, 9 }, 6, 4, null, true, 1e-9);
    const effect = [_]h.Row{ .{ .coefficients = &.{ 0, 1, 0, -1 } }, .{ .coefficients = &.{ 0, 0, 1, -1 } } };
    const intercept = [_]h.Row{.{ .coefficients = &.{ 1, 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 } }};
    const catalog = [_]shared.Effect{ .{ .name = "Intercept", .rows = .{ &intercept, &intercept, &intercept }, .intercept = true }, .{ .name = "A", .rows = .{ &effect, &effect, &effect } } };
    const report = try shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", "A / ddf=4.7 intercept e3"), .f);
    try std.testing.expectEqual(@as(usize, 2), report.tests.len);
    try std.testing.expectEqualStrings("Intercept", report.tests[0].effect);
    try close(3, report.tests[0].result.denominator_df.?);
    try close(150, report.tests[0].result.numerator_ss.?);
    const result = report.tests[1].result;
    try std.testing.expectEqual(@as(usize, 2), result.rank);
    try close(36, result.numerator_ss.?);
    try close(9, result.f.?);
    try close(std.math.pow(f64, 4.7 / (4.7 + 18), 4.7 / 2.0), result.f_probability.?);
    try std.testing.expectEqual(@as(usize, 2), report.coefficients[1].rows.len);
    const no_intercept = try shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", ""), .f);
    try std.testing.expectEqual(@as(usize, 1), no_intercept.tests.len);
    try close(std.math.pow(f64, 1.0 / 7.0, 1.5), no_intercept.tests[0].result.f_probability.?);
}

test "COMMON031 interaction metadata resolves factor order and never substitutes unavailable hypotheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var design: [32]f64 = undefined;
    var response: [8]f64 = undefined;
    for (0..8) |i| {
        const left: f64 = if (i & 1 == 0) -1 else 1;
        const right: f64 = if (i & 2 == 0) -1 else 1;
        const noise: f64 = if (i & 4 == 0) -1 else 1;
        design[4 * i] = 1;
        design[4 * i + 1] = left;
        design[4 * i + 2] = right;
        design[4 * i + 3] = left * right;
        response[i] = 10 + 2 * left + 3 * right + 4 * left * right + noise;
    }
    const fit = try ranks.fit(a, &design, &response, 8, 4, null, true, 1e-9);
    const rows = [_]h.Row{.{ .coefficients = &.{ 0, 0, 0, 1 } }};
    const catalog = [_]shared.Effect{.{ .name = "A*B", .rows = .{ &rows, &rows, &rows } }};
    const result = try shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", "b*a / e3"), .f);
    try std.testing.expectEqualStrings("A*B", result.tests[0].effect);
    try close(128, result.tests[0].result.numerator_ss.?);
    try close(64, result.tests[0].result.f.?);
    try close(1 - 70 / (17 * @sqrt(@as(f64, 17))), result.tests[0].result.f_probability.?);
    const absent = [_]shared.Effect{.{ .name = "A*B", .rows = .{ null, null, &rows } }};
    try std.testing.expectError(error.ExecError, shared.evaluate(a, h.fromRegression(fit, 1e-9), &absent, try options(a, &d, "ORTHOREG", "/ htype=1"), .f));
    try std.testing.expectError(error.ExecError, shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", "C"), .f));
    try std.testing.expectError(error.ExecError, shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", "/ intercept"), .f));
    try std.testing.expectError(error.ExecError, shared.evaluate(a, h.fromRegression(fit, 1e-9), &catalog, try options(a, &d, "ORTHOREG", "/ ddf=1,2"), .f));
}

test "COMMON031 malformed geometry is not hidden by a nonestimable first row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try ranks.fit(a, &.{ 1, -1, -2, 1, 0, 0, 1, 1, 2, 1, 2, 4 }, &.{ 1, 2, 4, 4 }, 4, 3, null, true, 1e-9);
    const geometry = h.fromRegression(fit, 1e-9);
    try std.testing.expectError(error.ExecError, h.evaluate(a, geometry, &.{ .{ .coefficients = &.{ 0, 1, 0 } }, .{ .coefficients = &.{1} } }, null));
    try std.testing.expectError(error.ExecError, h.evaluate(a, geometry, &.{.{ .coefficients = &.{ 0, 1, 2 } }}, -1));
    var invalid = geometry;
    invalid.covariance_kernel = &.{ 1, 1, 0, 0, 1, 0, 0, 0, 1 };
    try std.testing.expectError(error.ExecError, h.evaluate(a, invalid, &.{.{ .coefficients = &.{ 1, 0, 0 } }}, null));
}
