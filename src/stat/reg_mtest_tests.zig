//! Independent E/H and distribution references for STAT-REG-009.
const std = @import("std");
const mtest = @import("reg_mtest.zig");
const reg = @import("reg.zig");
const qr = @import("reg_fit.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const x = [_]f64{ 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1 };
const y1 = [_]f64{ 8, 10, 8, 14, 8, 10, 8, 14 };
const y2 = [_]f64{ 15, 17, 21, 23, 17, 19, 23, 25 };
const weights = [_]f64{1} ** 8;
fn close(want: f64, got: f64) !void {
    const nu = 4096 * 0x1p-53;
    try std.testing.expectApproxEqAbs(want, got, nu / (1 - nu) * @max(1, @abs(want)));
}
fn setup(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y1", "y2" }) |name| _ = try ds.addColumn(name, .num);
    for (y1, y2, 0..) |left, right, i| try ds.appendRow(&.{ .{ .num = x[3 * i + 1] }, .{ .num = x[3 * i + 2] }, .{ .num = left }, .{ .num = right } });
    try lib.put("sample", ds);
}
fn specification(a: A, d: *diag.Diagnostics, source: []const u8) !mtest.Spec {
    const tokens = try lex.tokenize(a, source, d);
    return mtest.parse(.{ .arena = a, .lib = undefined, .diags = d }, tokens[0 .. tokens.len - 1], &.{ "Intercept", "x", "z" }, &.{ "y1", "y2" }, true, 1, 1, null);
}
fn run(a: A, lib: *Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var listing: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &listing, try lex.tokenize(a, source, d));
    return listing.items;
}

test "REG009 independent orthogonal E H roots and all four F probability formulas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const fits = [_]qr.Fit{ try qr.fit(a, &x, &y1, 8, 3, null), try qr.fit(a, &x, &y2, 8, 3, null) };
    const spec = try specification(a, &d, "x=0,z=0 / print");
    const result = try mtest.evaluate(a, &fits, &weights, spec);
    // y1=10+2x+z+xz, y2=20+x+3z+w. Walsh x,z,xz,w are
    // pairwise orthogonal with norm²8; E=8I and H=[[40,40],[40,80]].
    for ([_]f64{ 8, 0, 0, 8 }, result.error_matrix) |want, got| try close(want, got);
    for ([_]f64{ 40, 40, 40, 80 }, result.hypothesis) |want, got| try close(want, got);
    const greatest = (15 + 5 * @sqrt(@as(f64, 5))) / 2;
    const least = (15 - 5 * @sqrt(@as(f64, 5))) / 2;
    try close(greatest, result.roots[0]);
    try close(least, result.roots[1]);
    try std.testing.expectEqual(@as(usize, 2), result.s);
    try close(-0.5, result.m);
    try close(1, result.n);
    const values = [_]f64{ 1.0 / 41.0, 65.0 / 41.0, 15, greatest };
    const f_values = [_]f64{ 2 * (@sqrt(@as(f64, 41)) - 1), 325.0 / 34.0, 15, greatest * 2.5 };
    const d1 = [_]f64{ 4, 4, 4, 2 };
    const d2 = [_]f64{ 8, 10, 4, 5 };
    for (result.statistics, values, f_values, d1, d2, 0..) |row, value, f, numerator, denominator, i| {
        try close(value, row.value);
        try close(f, row.f);
        try close(numerator, row.numerator_df);
        try close(denominator, row.denominator_df);
        const z = denominator / (denominator + numerator * f);
        // I_z(a,2)=(a+1)z^a-a*z^(a+1), I_z(a,1)=z^a.
        // These integrate the beta density exactly; no production beta call.
        const exponent = denominator / 2;
        const probability = if (i == 3) std.math.pow(f64, z, exponent) else (exponent + 1) * std.math.pow(f64, z, exponent) - exponent * std.math.pow(f64, z, exponent + 1);
        try close(probability, row.probability);
    }
}

test "REG009 response contrasts nonzero shared constants and rank-one exact F equivalence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const fits = [_]qr.Fit{ try qr.fit(a, &x, &y1, 8, 3, null), try qr.fit(a, &x, &y2, 8, 3, null) };
    const contrast = try mtest.evaluate(a, &fits, &weights, try specification(a, &d, "y1-y2"));
    try close(16, contrast.error_matrix[0]);
    try close(40, contrast.hypothesis[0]);
    try std.testing.expectEqual(@as(usize, 1), contrast.s);
    for (contrast.statistics, [_]f64{ 2.0 / 7.0, 5.0 / 7.0, 2.5, 2.5 }) |row, value| {
        try close(value, row.value);
        try close(6.25, row.f);
        try close(2, row.numerator_df);
        try close(5, row.denominator_df);
        try close(std.math.pow(f64, 2.0 / 7.0, 2.5), row.probability);
    }
    const centered_contrast = try mtest.evaluate(a, &fits, &weights, try specification(a, &d, "x=1,y1-y2"));
    try close(8, centered_contrast.hypothesis[0]); // shared constant cancels through M
    try close(16, centered_contrast.error_matrix[0]);
    try close(2.5, centered_contrast.statistics[0].f);
    const nonzero = try mtest.evaluate(a, &fits, &weights, try specification(a, &d, "x=1"));
    for (nonzero.hypothesis, [_]f64{ 8, 0, 0, 0 }) |got, want| try close(want, got);
    for (nonzero.statistics) |row| {
        try close(2, row.f);
        try close(2, row.numerator_df);
        try close(4, row.denominator_df);
        try close(0.25, row.probability);
    }
}

test "REG009 published Morrison matrices reproduce rational traces and fractional HL degrees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // S154 physical pp.8646–8647, Figure105.52 (Morrison1976 public example).
    const result = try mtest.statistics(arena.allocator(), &.{ 94.5, 76.5, 76.5, 114 }, &.{ 301, 97.5, 97.5, 109.0 / 3.0 }, 2, 2, 18, false);
    const trace = 30440.0 / 6561.0;
    const determinant = 17161.0 / 59049.0;
    const roy = (trace + @sqrt(trace * trace - 4 * determinant)) / 2.0;
    const lambda = 59049.0 / 350170.0;
    const pillai = 154141.0 / 175085.0;
    for (result.statistics, [_]f64{ lambda, pillai, trace, roy }) |row, value| try close(value, row.value);
    try std.testing.expectEqual(mtest.Inference.exact_f, result.statistics[0].inference);
    try std.testing.expectEqual(mtest.Inference.upper_bound_f, result.statistics[3].inference);
    try close(34, result.statistics[0].denominator_df);
    try close(36, result.statistics[1].denominator_df);
    try close(524.0 / 27.0, result.statistics[2].denominator_df);
    try close(trace * 393.0 / 94.0, result.statistics[2].f);
    try close(18, result.statistics[3].denominator_df);
    // Check the actual published rounding without deriving a tolerance from
    // implementation discrepancies: half a unit at eight printed decimals.
    for (result.statistics, [_]f64{ 0.16862952, 0.88037810, 4.63953666, 4.57602675 }) |row, printed| try std.testing.expectApproxEqAbs(printed, row.value, 0.000000005);
}

test "REG009 MTEST default matrices labels numbering and model output order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const source = "proc reg data=sample; model y1 y2=x z; mtest / print; contrast: mtest y1=y2; next: model y1=x z; mtest x; run;";
    const spec = try reg.parse(.{ .arena = a, .lib = &lib, .diags = &d }, try lex.tokenize(a, source, &d));
    try std.testing.expectEqual(@as(usize, 3), spec.mtests.len);
    try std.testing.expectEqual(@as(usize, 2), spec.mtests[0].linear.len);
    try std.testing.expectEqual(@as(usize, 2), spec.mtests[0].transform.len);
    try std.testing.expectEqual(@as(usize, 1), spec.mtests[0].number);
    try std.testing.expectEqual(@as(usize, 2), spec.mtests[1].number);
    try std.testing.expectEqual(@as(usize, 1), spec.mtests[2].number);
    const listing = try run(a, &lib, &d, source);
    const first_test = std.mem.indexOf(u8, listing, "Multivariate Test 1").?;
    const labelled = std.mem.indexOf(u8, listing, "Multivariate Test: contrast").?;
    const next_model = std.mem.indexOf(u8, listing, "Model: next").?;
    try std.testing.expect(first_test < labelled and labelled < next_model);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Error Matrix (E)"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Hypothesis Matrix (H)"));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, listing, "\nWilks' Lambda "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Roy's Greatest Root is an upper bound"));
    try std.testing.expect(!d.hasErrors());
}

test "REG009 multivariate role errors unsupported exact options and singular ranks fail visibly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try setup(a, &lib);
    for ([_][]const u8{
        "proc reg data=sample; mtest x; model y1 y2=x z; run;",
        "proc reg data=sample; model y1 y2=x z; mtest x+y1; run;",
        "proc reg data=sample; model y1 y2=x z; mtest y1-y2=1; run;",
        "proc reg data=sample; model y1 y2=x z; mtest unknown; run;",
        "proc reg data=sample; model y1 y2=x z; mtest / mstat=typo; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    for ([_][]const u8{
        "proc reg data=sample; model y1 y2=x z; mtest / mstat=exact; run;",
        "proc reg data=sample; model y1 y2=x z; mtest / canprint; run;",
        "proc reg data=sample; model y1 y2=x z; mtest / details; run;",
        "proc reg data=sample; model y1 y2=x z; mtest x,2*x; run;",
        "proc reg data=sample; model y1 y2=x z; mtest y1,2*y1; run;",
        "proc reg data=sample; model y1 y2=x z; mtest y1,y2,y1+y2; run;",
        "proc reg data=sample; model y1 y2=x z; restrict z=0; mtest x; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
}

test "REG009 response missingness shares one estimation sample and NOPRINT suppresses only display" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    try lib.find("sample").?.appendRow(&.{ .{ .num = 100 }, .{ .num = 100 }, .{ .num = 1e9 }, .{ .num = std.math.nan(f64) } });
    const text = try run(a, &lib, &d, "proc reg data=sample; model y1 y2=x z; mtest / print; run;");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "Number of Observations Read 9"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "Number of Observations Used 8"));
    try std.testing.expect(std.mem.indexOf(u8, text, "0.02439024") != null);
    const hidden = try run(a, &lib, &d, "proc reg data=sample noprint; model y1 y2=x z; mtest / print; run;");
    try std.testing.expectEqual(@as(usize, 0), hidden.len);
    try std.testing.expect(!d.hasErrors());
}

test "REG009 weight scaling preserves roots while replication changes inference DF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const spec = try specification(a, &d, "x,z");
    const doubled = [_]f64{2} ** 8;
    var fits = [_]qr.Fit{ try qr.fit(a, &x, &y1, 8, 3, &doubled), try qr.fit(a, &x, &y2, 8, 3, &doubled) };
    const weighted = try mtest.evaluate(a, &fits, &doubled, spec);
    for (weighted.error_matrix, [_]f64{ 16, 0, 0, 16 }) |got, want| try close(want, got);
    for (weighted.hypothesis, [_]f64{ 80, 80, 80, 160 }) |got, want| try close(want, got);
    try close(1.0 / 41.0, weighted.statistics[0].value);
    for (&fits) |*fit| {
        fit.n_used = 16;
        fit.df_error = 13;
    }
    const replicated = try mtest.evaluate(a, &fits, &doubled, spec);
    try close(weighted.statistics[0].value, replicated.statistics[0].value);
    try close(24, replicated.statistics[0].denominator_df);
    try close(26, replicated.statistics[1].denominator_df);
    try std.testing.expect(replicated.statistics[0].probability < weighted.statistics[0].probability);
}

test "REG009 null H low residual DF and exact-tail boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const zero = try mtest.statistics(a, &.{ 1, 0, 0, 1 }, &.{ 0, 0, 0, 0 }, 2, 2, 5, false);
    for (zero.statistics) |row| {
        try close(0, row.f);
        try close(1, row.probability);
    }
    const low = try mtest.statistics(a, &.{ 1, 0, 0, 1 }, &.{ 2, 0, 0, 1 }, 2, 2, 3, false);
    try close(4, low.statistics[2].numerator_df);
    try close(2, low.statistics[2].denominator_df);
    try close(0.75, low.statistics[2].f);
    try std.testing.expectError(error.ExecError, mtest.statistics(a, &.{ 1, 0, 0, 1 }, &.{ 2, 0, 0, 1 }, 2, 2, 2, false));
    try std.testing.expectError(error.ExecError, mtest.statistics(a, &.{ 1, 1, 1, 1 }, &.{ 2, 0, 0, 1 }, 2, 2, 5, false));
    try std.testing.expectError(error.ExecError, mtest.statistics(a, &.{ 1, 0, 0, 1 }, &.{ 2, 0, 0, 1 }, 2, 2, 5, true));
}

fn integerBetaTail(z: f64, a: f64, b: usize) f64 {
    // Exact finite integral of t^(a-1)(1-t)^(b-1), b positive integer.
    var normalizer: f64 = a;
    for (1..b) |j| normalizer *= (a + @as(f64, @floatFromInt(j))) / @as(f64, @floatFromInt(j));
    var sum: f64 = 0;
    var binomial: f64 = 1;
    for (0..b) |j| {
        if (j > 0) binomial *= @as(f64, @floatFromInt(b - j)) / @as(f64, @floatFromInt(j));
        const power = a + @as(f64, @floatFromInt(j));
        sum += (if (j % 2 == 0) binomial else -binomial) * std.math.pow(f64, z, power) / power;
    }
    return normalizer * sum;
}

test "REG009 three responses generalized roots and fractional-degree probabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var y3: [8]f64 = undefined;
    for (&y3, 0..) |*value, i| {
        const u = x[i * 3 + 1];
        const v = x[i * 3 + 2];
        const w = y2[i] - 20 - u - 3 * v;
        value.* = 30 + 3 * u + 2 * v + u * w;
    }
    const fits = [_]qr.Fit{ try qr.fit(a, &x, &y1, 8, 3, null), try qr.fit(a, &x, &y2, 8, 3, null), try qr.fit(a, &x, &y3, 8, 3, null) };
    const spec = mtest.Spec{ .statement_index = 1, .number = 1, .label = null, .linear = &.{ .{ .coefficients = &.{ 0, 1, 0 }, .rhs = 0 }, .{ .coefficients = &.{ 0, 0, 1 }, .rhs = 0 } }, .transform = &.{ &.{ 1, 0, 0 }, &.{ 0, 1, 0 }, &.{ 0, 0, 1 } } };
    const result = try mtest.evaluate(a, &fits, &weights, spec);
    for (result.error_matrix, [_]f64{ 8, 0, 0, 0, 8, 0, 0, 0, 8 }) |got, want| try close(want, got);
    for (result.hypothesis, [_]f64{ 40, 40, 64, 40, 80, 72, 64, 72, 104 }) |got, want| try close(want, got);
    // E^-1 H has trace28, sum of principal two-minors75 and det0,
    // hence characteristic polynomial lambda*(lambda-25)*(lambda-3).
    for (result.roots, [_]f64{ 25, 3, 0 }) |got, want| try close(want, got);
    const values = [_]f64{ 1.0 / 104.0, 89.0 / 52.0, 28, 25 };
    const fs = [_]f64{ @sqrt(@as(f64, 104)) - 1, 356.0 / 45.0, 140.0 / 9.0, 100.0 / 3.0 };
    const df1 = [_]f64{ 6, 6, 6, 3 };
    const df2 = [_]f64{ 6, 8, 20.0 / 7.0, 4 };
    for (result.statistics, values, fs, df1, df2, 0..) |row, value, f, numerator, denominator, i| {
        try close(value, row.value);
        try close(f, row.f);
        try close(numerator, row.numerator_df);
        try close(denominator, row.denominator_df);
        const z = denominator / (denominator + numerator * f);
        const probability = if (i < 3) integerBetaTail(z, denominator / 2, 3) else 1 - 2.5 * std.math.pow(f64, 1 - z, 1.5) + 1.5 * std.math.pow(f64, 1 - z, 2.5);
        try close(probability, row.probability);
    }
}

test "REG009 canonical roots invariant under nonsingular response mixing and generic Wilks remains approximate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const diagonal = try mtest.statistics(a, &.{ 1, 0, 0, 0, 1, 0, 0, 0, 1 }, &.{ 1, 0, 0, 0, 2, 0, 0, 0, 3 }, 3, 4, 12, false);
    // Congruence T' E T, T' H T for T=[[1,1,0],[0,2,1],[1,0,1]].
    const mixed = try mtest.statistics(a, &.{ 2, 1, 1, 1, 5, 2, 1, 2, 2 }, &.{ 4, 1, 3, 1, 9, 4, 3, 4, 5 }, 3, 4, 12, false);
    try std.testing.expectEqual(mtest.Inference.approximate_f, mixed.statistics[0].inference);
    for (mixed.roots, [_]f64{ 3, 2, 1 }) |got, want| try close(want, got);
    for (mixed.statistics, diagonal.statistics) |row, original| {
        try close(original.value, row.value);
        try close(original.f, row.f);
        try close(original.probability, row.probability);
        const z = row.denominator_df / (row.denominator_df + row.numerator_df * row.f);
        try close(integerBetaTail(z, row.denominator_df / 2, @intFromFloat(row.numerator_df / 2)), row.probability);
    }
    var listing: std.ArrayList(u8) = .empty;
    try @import("reg_mtest_render.zig").render(a, &listing, "MODEL1", .{ .statement_index = 1, .number = 1, .label = null, .linear = &.{}, .transform = &.{} }, mixed);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Roy's Greatest Root is an upper bound") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Wilks' Lambda is exact") == null);
}

test "REG009 full listing permits only two independently bounded zero cross-error cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const specification_text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_reg_mtest.txt", a, .limited(1 << 20));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, specification_text, "~"));
    const anchor = "Error Matrix (E) 8 ";
    const begin = (std.mem.indexOf(u8, specification_text, anchor) orelse return error.TestUnexpectedResult) + anchor.len;
    var fields = std.mem.tokenizeScalar(u8, specification_text[begin..], ' ');
    const u: f128 = 0x1p-53;
    const g192 = 192 * u / (1 - 192 * u);
    const g8 = 8 * u / (1 - 8 * u);
    const g32 = 32 * u / (1 - 32 * u);
    const r = g192 * 24 + g8 * 49;
    const expected = 8 * (2 * r + r * r) + g32 * (8 + 8 * (2 * r + r * r));
    for (0..2) |_| {
        const cell = fields.next() orelse return error.TestUnexpectedResult;
        try std.testing.expect(std.mem.startsWith(u8, cell, "0~"));
        const declared = try std.fmt.parseFloat(f128, cell[2..]);
        try std.testing.expectApproxEqRel(expected, declared, 1e-30);
        try std.testing.expect(@abs(@as(f128, 1e-8)) > declared);
    }
    try std.testing.expectEqualStrings("8", fields.next().?);
    try std.testing.expectEqualStrings("Hypothesis", fields.next().?);
}

test "REG009 sixteen-response boundary retains all canonical roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var e = [_]f64{0} ** 256;
    var h = [_]f64{0} ** 256;
    for (0..16) |j| {
        e[j * 16 + j] = 1;
        h[j * 16 + j] = @floatFromInt(j + 1);
    }
    const result = try mtest.statistics(a, &e, &h, 16, 16, 40, false);
    try std.testing.expectEqual(@as(usize, 16), result.roots.len);
    for (result.roots, 0..) |root, j| try close(@floatFromInt(16 - j), root);
    try close(136, result.statistics[2].value); // 1+...+16
    try std.testing.expectApproxEqRel(@as(f64, 1.0 / 355687428096000.0), result.statistics[0].value, 1e-13); // 1/17!
    try std.testing.expectEqual(mtest.Inference.approximate_f, result.statistics[0].inference);
    try std.testing.expectError(error.ExecError, mtest.statistics(a, &.{}, &.{}, 17, 17, 40, false));
}
