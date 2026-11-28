//! Permanent GLM010 checks. Mathematical anchors: S154 physical pp.4151–4156
//! (L beta M, orthogonal trace SS, GG/HF/HFL/CM); Mauchly (1940), Annals of
//! Mathematical Statistics 11,204–209, W=det(E)/(tr(E)/b)^b and Bartlett's
//! first-order chi-square correction. No test reads the temporary baseline.
const std = @import("std");
const t = std.testing;
const glm = @import("glm.zig");
const repeated = @import("glm_repeated.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
fn close(expected: f64, actual: f64) !void {
    // Small orthogonal designs below: dimensions<=8, condition<=4. 4096
    // unit roundoffs covers two-pass QR, transforms and matrix products.
    try t.expectApproxEqAbs(expected, actual, 4096 * std.math.floatEps(f64) * @max(1, @abs(expected)));
}
fn parse(cx: proc.ProcCtx, source: []const u8) !glm.Spec {
    return glm.parse(cx, try @import("../lexer.zig").tokenize(cx.arena, source, cx.diags));
}
fn compute(cx: proc.ProcCtx, spec: glm.Spec) !repeated.Analysis {
    return repeated.compute(cx, spec, try selection.View.init(cx.arena, spec.input, .{}));
}
fn dataset(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "y1", "y2", "y3" }) |name| _ = try ds.addColumn(name, .num);
    // Four independent sign patterns per group, zero cell sums. Residual
    // vectors in response coordinates have E=diag(8,32,72), no off-diagonals.
    for (0..2) |group| for ([_][3]f64{ .{ 1, 2, 3 }, .{ 1, -2, -3 }, .{ -1, 2, -3 }, .{ -1, -2, 3 } }) |residual| {
        const g: f64 = @floatFromInt(group);
        try ds.appendRow(&.{ .{ .num = g }, .{ .num = 1 + g + residual[0] }, .{ .num = 2 + 2 * g + residual[1] }, .{ .num = 4 + 3 * g + residual[2] } });
    };
    try lib.put("sample", ds);
    return ds;
}
test "GLM010 polynomial rows are orthonormal zero-sum with independent unequal spacing anchors" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rows = try repeated.transformation(arena.allocator(), .{ .name = "time", .levels = &.{ 0, 1, 3, 5 }, .reference = 3, .transformation = .polynomial });
    // Center9/4, squared centered norm59/4. Linear=(-9,-5,3,11)/sqrt236.
    for (rows[0], [_]f64{ -9, -5, 3, 11 }) |value, numerator| try close(numerator / @sqrt(@as(f64, 236)), value);
    for (rows, 0..) |left, i| {
        var sum: f64 = 0;
        for (left) |value| sum += value;
        try close(0, sum);
        for (rows, 0..) |right, j| {
            var dot: f64 = 0;
            for (left, right) |x, y| dot += x * y;
            try close(if (i == j) 1 else 0, dot);
        }
    }
    try t.expectError(error.ExecError, repeated.transformation(arena.allocator(), .{ .name = "time", .levels = &.{ 0, 1, 1 }, .reference = 2, .transformation = .polynomial }));
}
test "GLM010 complete subjects E H and between-subject scaled sum have independent exact values" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try dataset(a, &lib);
    // One missing response excludes this whole subject, even y1 is observed.
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 999 }, .{ .num = std.math.nan(f64) }, .{ .num = 999 } });
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; class g; model y1-y3=g / nouni; repeated time 3 polynomial / summary printe; run;");
    const result = try compute(cx, spec);
    try t.expectEqual(@as(usize, 9), result.design.read);
    try t.expectEqual(@as(usize, 8), result.design.n);
    try t.expectEqual(@as(usize, 6), result.error_df);
    for (0..3) |i| for (0..3) |j| try close(if (i == j) @as(f64, @floatFromInt(8 * (i + 1) * (i + 1))) else 0, result.error_matrix[i * 3 + j]);
    // Linear=(-1,0,1)/sqrt2; quadratic=(1,-2,1)/sqrt6.
    const e = [_]f64{ 40, 64 / @sqrt(@as(f64, 12)), 64 / @sqrt(@as(f64, 12)), 104.0 / 3.0 };
    for (e, result.tests[0].error_matrix) |want, actual| try close(want, actual);
    // Average cell means=(1.5,3,5.5): L beta M=(4/sqrt2,1/sqrt6).
    // Var of equal-weight cell mean=1/8, so Hmean=8*z'z.
    const mean = [_]f64{ 4 / @sqrt(@as(f64, 2)), 1 / @sqrt(@as(f64, 6)) };
    const difference = [_]f64{ 2 / @sqrt(@as(f64, 2)), 0 };
    for (0..2) |i| for (0..2) |j| {
        try close(8 * mean[i] * mean[j], result.tests[0].hypothesis[i * 2 + j]);
        try close(2 * difference[i] * difference[j], result.tests[1].hypothesis[i * 2 + j]);
    };
    try close(24, result.between.type_iii[0].ss);
    try close(112.0 / 3.0, result.between.model.fit.sse);
    // GG=tr²/(b tr E²), here (224/3)^2/[2*(1600+10816/9+2048/3)].
    const gg: f64 = (224.0 / 3.0) * (224.0 / 3.0) / (2 * (1600 + 10816.0 / 9.0 + 2048.0 / 3.0));
    try close(gg, result.sphere.gg);
    try close((7 * 2 * gg - 2) / (2 * (6 - 2 * gg)), result.sphere.adjusted);
    try t.expectEqual(@as(usize, 1), result.tests[0].q);
    try t.expectEqual(@as(f64, 2), result.tests[0].statistics[0].numerator_df);
    try t.expectEqual(@as(f64, 5), result.tests[0].statistics[0].denominator_df);
    // For F(2,5), survival=(5/(5+2F))^(5/2), independent beta-CDF check.
    for (result.tests) |test_result| {
        const stat = test_result.statistics[0];
        const ratio = 5 / (5 + 2 * stat.f);
        try close(ratio * ratio * @sqrt(ratio), stat.probability);
    }
    try t.expect(!diagnostics.hasErrors());
}
test "GLM010 transformations preserve omnibus SS while SUMMARY remains transformation-specific" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try dataset(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var reference: ?repeated.Analysis = null;
    for ([_][]const u8{ "polynomial", "contrast(1)", "helmert", "mean(2)", "profile" }) |transform| {
        const spec = try parse(cx, try std.fmt.allocPrint(a, "proc glm; class g; model y1-y3=g / nouni; repeated time 3 {s} / summary; run;", .{transform}));
        const result = try compute(cx, spec);
        if (reference) |first| {
            try close(first.sphere.gg, result.sphere.gg);
            for (first.tests, result.tests) |left, right| for (left.statistics, right.statistics) |l, r| {
                try close(l.value, r.value);
                try close(l.probability, r.probability);
            };
            for (first.orthogonal_tests, result.orthogonal_tests) |left, right| for (left.hypothesis, right.hypothesis) |l, r| try close(l, r);
        } else reference = result;
    }
}
test "GLM010 sphericity compound symmetry anisotropy HF HFL CM and boundaries" {
    const isotropic = try repeated.sphericity(&.{ 4, 0, 0, 4 }, 2, 10, 12, .hfl);
    try close(1, isotropic.gg);
    try close(1, isotropic.criterion);
    try close(0, isotropic.chi_square);
    try close(1, isotropic.probability);
    const e = [_]f64{ 1, 0, 0, 9 };
    const gg: f64 = 25.0 / 41.0;
    const hfl = try repeated.sphericity(&e, 2, 10, 12, .hfl);
    const hf = try repeated.sphericity(&e, 2, 10, 12, .hf);
    const cm = try repeated.sphericity(&e, 2, 10, 12, .cm);
    try close(gg, hfl.gg);
    try close(0.36, hfl.criterion);
    try close(-9 * @log(@as(f64, 0.36)), hfl.chi_square); // rho=.9
    try close((11 * 2 * gg - 2) / (2 * (10 - 2 * gg)), hfl.adjusted);
    try close((12 * 2 * gg - 2) / (2 * (10 - 2 * gg)), hf.adjusted);
    try close(hfl.adjusted * 52 * 50 / (54 * 54), cm.adjusted);
    try t.expectError(error.ExecError, repeated.sphericity(&.{ 1, 1, 1, 1 }, 2, 10, 12, .hfl));
    try t.expectError(error.ExecError, repeated.sphericity(&.{0}, 1, 10, 12, .hfl));
    const one = try repeated.sphericity(&.{4}, 1, 5, 6, .hfl);
    try close(1, one.gg);
    try close(1, one.adjusted);
    try t.expectEqual(@as(usize, 0), one.df);
}
test "GLM010 malformed syntax and unsupported domains report captured diagnostics" {
    defer diag.resetGap();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try dataset(a, &lib);
    for ([_][]const u8{ "repeated time 2;", "repeated time 3 (0 1);", "repeated time 3 contrast(0);", "repeated y1 3;", "repeated time 3 / nonsense;" }) |statement| {
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        diag.resetGap();
        try t.expectError(error.ParseError, parse(cx, try std.fmt.allocPrint(a, "proc glm; model y1-y3= / nouni; {s} run;", .{statement})));
        try t.expect(diagnostics.hasErrors());
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    }
    for ([_][]const u8{ "repeated time 3 identity;", "repeated time 3 / canonical;", "repeated time 3 / htype=2;", "repeated time 3, trial 1;" }) |statement| {
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        diag.resetGap();
        try t.expectError(error.ParseError, parse(cx, try std.fmt.allocPrint(a, "proc glm; model y1-y3= / nouni; {s} run;", .{statement})));
        try t.expect(std.mem.indexOf(u8, try diagnostics.render(), "not implemented") != null);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    }
}
test "GLM010 original dogs complete listing and all original multivariate quantities persist" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    const source = try helper.read(a, "tests/corpus/stat_glm_repeated_dogs.sas");
    const begin = std.mem.indexOf(u8, source, "input Drug").?;
    const end = std.mem.indexOfPos(u8, source, begin, "proc glm;").?;
    var lib = Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    var pdv = @import("../pdv.zig").Pdv.init(a);
    var evaluator: @import("../eval.zig").Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diagnostics, .call_fn = &@import("../functions.zig").dispatch };
    var executor = @import("../exec.zig").Executor.init(a, &pdv, &diagnostics, &evaluator, &lib);
    var ds = Dataset.init(a, "dogs");
    try executor.run(try @import("../parser.zig").parse(a, source[begin..end], &diagnostics), &ds);
    try lib.put("dogs", &ds);
    try t.expectEqual(@as(usize, 16), ds.rows.items.len);
    try close(0.04, ds.rows.items[0][ds.indexOf("Histamine0").?].num);
    try close(@log(@as(f64, 0.04)), ds.rows.items[0][ds.indexOf("LogHistamine0").?].num);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, source[end..]);
    const result = try compute(cx, spec);
    try t.expectEqual(@as(usize, 16), result.design.read);
    try t.expectEqual(@as(usize, 15), result.design.n);
    try t.expectEqual(@as(usize, 11), result.error_df);
    // Published rounded values: tolerance is half of the last decimal unit,
    // NOT an observed discrepancy. These cover every H diagonal and E entry.
    const h = [_][3]f64{ .{ 2.00963483, 5.40988418, 4.63946776 }, .{ 1.18069076, 0.59173192, 0.07187246 }, .{ 1.36172504, 5.94945506, 4.77860547 }, .{ 2.04346848, 0.67031587, 0.21699504 } };
    for (result.tests, h) |test_result, expected| for (expected, 0..) |want, j| try t.expectApproxEqAbs(want, test_result.hypothesis[j * 3 + j], 5e-9);
    for ([_]f64{ 0.63171161, 1.04118707, 0.80949018 }, 0..) |want, j| try t.expectApproxEqAbs(want, result.tests[0].error_matrix[j * 3 + j], 5e-9);
    for ([_]f64{ 8.01087137, 1.92774470, 7.10373567, 4.15915732 }, result.tests) |want, test_result| try t.expectApproxEqAbs(want, test_result.statistics[2].value, 5e-9);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, spec);
    const expected = try helper.read(a, "tests/corpus/stat_glm_repeated_dogs.txt");
    const start = std.mem.indexOf(u8, expected, "words ").? + 6;
    const stop = std.mem.indexOfScalarPos(u8, expected, start, '\n').?;
    var want = std.mem.tokenizeAny(u8, expected[start..stop], " \t\r\n");
    var actual = std.mem.tokenizeAny(u8, output.items, " \t\r\n");
    while (want.next()) |word| try t.expectEqualStrings(word, actual.next() orelse "");
    try t.expect(actual.next() == null);
}

test "GLM010 two-level paired hypothesis equals exact squared t and excludes incomplete subjects" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "paired");
    _ = try ds.addColumn("before", .num);
    _ = try ds.addColumn("after", .num);
    // Differences1,2,3,4: mean2.5, centered SS5, t²=n*mean²/(SS/3)=15.
    for ([_][2]f64{ .{ 1, 2 }, .{ 2, 4 }, .{ 3, 6 }, .{ 4, 8 } }) |values| try ds.appendRow(&.{ .{ .num = values[0] }, .{ .num = values[1] } });
    try ds.appendRow(&.{ .{ .num = 99 }, .{ .num = std.math.nan(f64) } });
    var lib = Library.init(a);
    try lib.put("paired", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try parse(cx, "proc glm; model before after= / nouni; repeated visit; run;");
    const result = try compute(cx, spec);
    try t.expectEqual(@as(usize, 4), result.design.n);
    try t.expectEqual(@as(usize, 3), result.error_df);
    try close(5, result.tests[0].error_matrix[0]);
    try close(25, result.tests[0].hypothesis[0]);
    try close(15, result.tests[0].statistics[0].f);
    try close(2.5, result.orthogonal_tests[0].error_matrix[0]);
    try close(12.5, result.orthogonal_tests[0].hypothesis[0]);
    try close(1, result.sphere.gg);
    try close(1, result.sphere.adjusted);
}

test "GLM010 compound-symmetric subject covariance projects out arbitrary shared variance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const m = try repeated.transformation(arena.allocator(), .{ .name = "time", .levels = &.{ 0, 1, 2 }, .reference = 2, .transformation = .polynomial });
    // Covariance2I+tau*J. tau=-2/3 is the PSD boundary (zero variance
    // of subject means); its contrast covariance remains2I. tau=3 adds
    // correlated subject offsets without changing any within-subject test.
    for ([_]f64{ -2.0 / 3.0, 0, 3 }) |tau| {
        var transformed: [4]f64 = undefined;
        for (m, 0..) |left, i| for (m, 0..) |right, j| {
            var sum: f64 = 0;
            for (left, 0..) |x, r| for (right, 0..) |y, c| {
                sum += x * y * (tau + @as(f64, if (r == c) 2 else 0));
            };
            transformed[i * 2 + j] = sum;
            try close(if (i == j) 2 else 0, sum);
        };
        const sphere = try repeated.sphericity(&transformed, 2, 9, 10, .hfl);
        try close(1, sphere.gg);
        try close(1, sphere.criterion);
    }
}

test "GLM010 unbalanced between-subject hypothesis uses equal cell means and harmonic covariance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "unequal");
    for ([_][]const u8{ "g", "a", "b" }) |name| _ = try ds.addColumn(name, .num);
    // Cell sizes2,3; response differences1,3 and2,4,6. Equal-cell mean3
    // (not observation-weighted16/5); its variance multiplier(1/2+1/3)/4=5/24.
    for ([_][3]f64{ .{ 0, 0, 1 }, .{ 0, 0, 3 }, .{ 1, 0, 2 }, .{ 1, 0, 4 }, .{ 1, 0, 6 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    var lib = Library.init(a);
    try lib.put("unequal", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const result = try compute(cx, try parse(cx, "proc glm; class g; model a b=g / nouni; repeated visit; run;"));
    try close(10, result.tests[0].error_matrix[0]);
    try close(216.0 / 5.0, result.tests[0].hypothesis[0]);
    try close(24.0 / 5.0, result.tests[1].hypothesis[0]);
    try close(324.0 / 25.0, result.tests[0].statistics[0].f);
    try close(36.0 / 25.0, result.tests[1].statistics[0].f);
}

test "GLM010 singular residuals low DF and unsupported combinations fail visibly without output" {
    defer diag.resetGap();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try dataset(a, &lib);
    for ([_][]const u8{
        "proc glm; class g; model y1-y3=g; repeated time; run;",
        "proc glm; weight g; model y1-y3= / nouni; repeated time; run;",
        "proc glm; model y1-y3= / nouni; repeated time 3 (0 1 1) polynomial; run;",
    }) |source| {
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        const spec = try parse(cx, source);
        var output: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, glm.execute(cx, &output, spec));
        try t.expectEqual(@as(usize, 0), output.items.len);
        try t.expect(diagnostics.hasErrors());
    }
    var graphics_diagnostics = diag.Diagnostics.init(a);
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = t.io, .diags = &graphics_diagnostics, .enabled = true };
    const graphics_cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &graphics_diagnostics, .graphics = &graphics };
    try t.expectError(error.ParseError, compute(graphics_cx, try parse(graphics_cx, "proc glm; class g; model y1-y3=g / nouni; repeated time; run;")));
    try t.expect(std.mem.indexOf(u8, try graphics_diagnostics.render(), "PLOTS=NONE") != null);
    _ = try compute(graphics_cx, try parse(graphics_cx, "proc glm plots=none; class g; model y1-y3=g / nouni; repeated time; run;"));
    // All responses identical: within-subject covariance has zero rank.
    for (ds.rows.items) |*r| {
        const replacement = try a.dupe(@import("../value.zig").Value, r.*);
        replacement[2] = replacement[1];
        replacement[3] = replacement[1];
        r.* = replacement;
    }
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var output: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, glm.execute(cx, &output, try parse(cx, "proc glm; class g; model y1-y3=g / nouni; repeated time; run;")));
    try t.expectEqual(@as(usize, 0), output.items.len);
    try t.expect(std.mem.indexOf(u8, try diagnostics.render(), "singular covariance") != null);
    ds.rows.items = ds.rows.items[0..2];
    var low_diagnostics = diag.Diagnostics.init(a);
    const low_cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &low_diagnostics };
    try t.expectError(error.ParseError, compute(low_cx, try parse(low_cx, "proc glm; model y1-y3= / nouni; repeated time; run;")));
    try t.expect(std.mem.indexOf(u8, try low_diagnostics.render(), "sufficient residual degrees of freedom") != null);
    try t.expectError(error.ExecError, repeated.sphericity(&.{ 1, 2, 0, 1 }, 2, 5, 6, .hfl));
    try t.expectError(error.ExecError, repeated.sphericity(&.{std.math.nan(f64)}, 1, 5, 6, .hfl));
}

test "GLM010 PRINTM PRINTH SUMMARY NOM and NOU affect only requested presentation" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try dataset(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var univariate: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &univariate, try parse(cx, "proc glm; class g; model y1-y3=g / nouni; repeated time polynomial / printm printh summary nom; run;"));
    try t.expect(std.mem.indexOf(u8, univariate.items, "MANOVA Test Criteria") == null);
    try t.expect(std.mem.indexOf(u8, univariate.items, "Tests of Hypotheses for Between Subjects Effects") != null);
    try t.expect(std.mem.indexOf(u8, univariate.items, "M = Transformation Matrix\n y1 y2 y3\ntime_1 -0.70711 0.00000 0.70711\ntime_2 0.40825 -0.81650 0.40825") != null);
    try t.expect(std.mem.indexOf(u8, univariate.items, "H = Type III SSCP Matrix for time*g\n time_1 time_2\ntime_1 4.00000 0.00000\ntime_2 0.00000 0.00000") != null);
    try t.expect(std.mem.indexOf(u8, univariate.items, "Contrast Variable: time_1") != null);
    try t.expect(std.mem.indexOf(u8, univariate.items, "Contrast Variable: time_2") != null);
    var multivariate: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &multivariate, try parse(cx, "proc glm; class g; model y1-y3=g / nouni; repeated time polynomial / nou mstat=exact; run;"));
    try t.expect(std.mem.indexOf(u8, multivariate.items, "MANOVA Test Criteria and Exact F Statistics") != null);
    try t.expect(std.mem.indexOf(u8, multivariate.items, "Between Subjects Effects") == null);
    try t.expect(std.mem.indexOf(u8, multivariate.items, "Within Subject Effects") == null);
    try t.expect(!diagnostics.hasErrors());
}

test "GLM010 published transformation matrices preserve signs scaling reference and degree" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // S154 physical p.4155: nineteen printed polynomial coefficients lie
    // within half their last displayed decimal. The printed quartic entry
    // 0.3743 is inconsistent with that rounding contract; preserve/disclose
    // it below rather than widening tolerance or pinning the incorrect value.
    const polynomial = try repeated.transformation(a, .{ .name = "dose", .levels = &.{ 1, 2, 5, 10, 20 }, .reference = 4, .transformation = .polynomial });
    const expected = [_][5]f64{ .{ -0.4250, -0.3606, -0.1674, 0.1545, 0.7984 }, .{ 0.4349, 0.2073, -0.3252, -0.7116, 0.3946 }, .{ -0.4331, 0.1366, 0.7253, -0.5108, 0.0821 }, .{ 0.4926, -0.7800, 0.3743, -0.0936, 0.0066 } };
    for (expected, polynomial, 0..) |want, actual, i| for (want, actual, 0..) |w, v, j| {
        if (i == 3 and j == 2) {
            try t.expect(@abs(w - v) > 0.00005);
        } else try t.expectApproxEqAbs(w, v, 0.00005);
    };
    // Independent exact degree-four construction: barycentric weights
    // 1/product_{j!=i}(x_i-x_j) are orthogonal to degrees0..3. Normalizing
    // (1/684,-1/432,1/900,-1/3600,1/51300) fixes all five coefficients;
    // the disputed entry is0.374387769563..., whose rounded value is0.3744.
    const barycentric = [_]f64{ 1.0 / 684.0, -1.0 / 432.0, 1.0 / 900.0, -1.0 / 3600.0, 1.0 / 51300.0 };
    var norm: f64 = 0;
    for (barycentric) |w| norm += w * w;
    for (barycentric, polynomial[3]) |w, v| try close(w / @sqrt(norm), v);
    const contrast = try repeated.transformation(a, .{ .name = "drug", .levels = &.{ 1, 2, 3, 4, 5 }, .reference = 0 });
    for ([_][5]f64{ .{ -1, 1, 0, 0, 0 }, .{ -1, 0, 1, 0, 0 }, .{ -1, 0, 0, 1, 0 }, .{ -1, 0, 0, 0, 1 } }, contrast) |want, actual| try t.expectEqualSlices(f64, &want, actual);
    // S154 physical p.4156: exact HELMERT, MEAN and PROFILE matrices.
    const helmert = try repeated.transformation(a, .{ .name = "trtmnt", .levels = &.{ 1, 2, 3, 4 }, .reference = 3, .transformation = .helmert });
    for ([_][4]f64{ .{ 1, -1.0 / 3.0, -1.0 / 3.0, -1.0 / 3.0 }, .{ 0, 1, -0.5, -0.5 }, .{ 0, 0, 1, -1 } }, helmert) |want, actual| for (want, actual) |w, v| try close(w, v);
    const mean = try repeated.transformation(a, .{ .name = "drug", .levels = &.{ 1, 2, 3, 4, 5 }, .reference = 4, .transformation = .mean });
    for ([_][5]f64{ .{ 1, -0.25, -0.25, -0.25, -0.25 }, .{ -0.25, 1, -0.25, -0.25, -0.25 }, .{ -0.25, -0.25, 1, -0.25, -0.25 }, .{ -0.25, -0.25, -0.25, 1, -0.25 } }, mean) |want, actual| try t.expectEqualSlices(f64, &want, actual);
    const profile = try repeated.transformation(a, .{ .name = "method", .levels = &.{ 1, 2, 3, 4 }, .reference = 3, .transformation = .profile });
    for ([_][4]f64{ .{ 1, -1, 0, 0 }, .{ 0, 1, -1, 0 }, .{ 0, 0, 1, -1 } }, profile) |want, actual| try t.expectEqualSlices(f64, &want, actual);
}
