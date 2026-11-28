//! REG013 independent formulas and actual producer boundaries. All invented data.
//! Small integer/rational matrices have condition numbers below 50. The 1e-11
//! bound exceeds 32*n*p*epsilon*condition*max(1,quantity) for these fixtures;
//! it is fixed from arithmetic scale, never fitted to an OpenSAS discrepancy.
const std = @import("std");
const k = @import("reg_specification.zig");
const qr = @import("reg_fit.zig");
const reg = @import("reg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;
const A = std.mem.Allocator;
fn close(expected: f64, actual: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 1e-11 * @max(1, @abs(expected)));
}
const x = [_]f64{ 1, 0, 1, 1, 1, 2, 1, 3, 1, 4 };
const y = [_]f64{ 1, 2, 2, 4, 8 };

test "REG013 HC0 HC1 HC2 HC3 complete rational sandwich matrices and parameter order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try qr.fit(a, &x, &y, 5, 2, null);
    // beta=(1/5,8/5), e=(4,1,-7,-5,7)/5, G=(6,-2;-2,1)/10,
    // h=(6,3,2,3,6)/10. Exact rational outer products give all cells below.
    const expected = [_][4]f64{
        .{ 246.0 / 625.0, -98.0 / 625.0, -98.0 / 625.0, 143.0 / 1250.0 },
        .{ 82.0 / 125.0, -98.0 / 375.0, -98.0 / 375.0, 143.0 / 750.0 },
        .{ 3077.0 / 3500.0, -683.0 / 1750.0, -683.0 / 1750.0, 481.0 / 1750.0 },
        .{ 8097.0 / 3920.0, -4769.0 / 4900.0, -4769.0 / 4900.0, 3289.0 / 4900.0 },
    };
    for (expected, 0..) |matrix, method| {
        const result = try k.hetero(a, &x, fit, @intCast(method));
        try std.testing.expectEqual(@as(usize, 4), result.covariance.len);
        for (matrix, result.covariance) |want, got| try close(want, got);
        try std.testing.expectEqual(result.covariance[1], result.covariance[2]);
        for (result.errors, 0..) |se, i| try close(@sqrt(matrix[i * 2 + i]), se);
        var swapped: [10]f64 = undefined;
        for (0..5) |i| {
            swapped[2 * i] = x[2 * i + 1];
            swapped[2 * i + 1] = 1;
        }
        const reverse = try k.hetero(a, &swapped, try qr.fit(a, &swapped, &y, 5, 2, null), @intCast(method));
        for (0..2) |i| for (0..2) |j| try close(matrix[(1 - i) * 2 + 1 - j], reverse.covariance[i * 2 + j]);
    }
}

test "REG013 HC response and design scaling and intercept-only identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scaled_x: [10]f64 = undefined;
    var scaled_y: [5]f64 = undefined;
    for (0..5) |i| {
        scaled_x[2 * i] = 1;
        scaled_x[2 * i + 1] = x[2 * i + 1] * 10;
        scaled_y[i] = y[i] * 3;
    }
    const original = try k.hetero(a, &x, try qr.fit(a, &x, &y, 5, 2, null), 3);
    const scaled = try k.hetero(a, &scaled_x, try qr.fit(a, &scaled_x, &scaled_y, 5, 2, null), 3);
    for (0..2) |i| for (0..2) |j| try close(original.covariance[i * 2 + j] * 9 / ((if (i == 0) @as(f64, 1) else 10) * (if (j == 0) @as(f64, 1) else 10)), scaled.covariance[i * 2 + j]);
    const one = [_]f64{ 1, 1, 1, 1 };
    const fit = try qr.fit(a, &one, &.{ 1, 2, 3, 4 }, 4, 1, null);
    for ([_]f64{ 5.0 / 16.0, 5.0 / 12.0, 5.0 / 12.0, 5.0 / 9.0 }, 0..) |want, method| try close(want, (try k.hetero(a, &one, fit, @intCast(method))).covariance[0]);
}

test "REG013 DW exact residual ratios boundary scaling and endpoint identity" {
    const e = [_]f64{ 1, -2, 1, 0 };
    const result = try k.serial(&e);
    try close(19.0 / 6.0, result.d);
    try close(-2.0 / 3.0, result.correlation);
    // d = 2(1-r) - (first²+last²)/SSE; endpoint terms cannot be dropped.
    try close(2 * (1 - result.correlation) - 1.0 / 6.0, result.d);
    const huge = try k.serial(&.{ 1e300, -2e300, 1e300, 0 });
    const tiny = try k.serial(&.{ 1e-300, -2e-300, 1e-300, 0 });
    try close(result.d, huge.d);
    try close(result.correlation, tiny.correlation);
    try close(result.d, (try k.serial(&.{ 0, 1, -2, 1 })).d);
    try std.testing.expect(std.math.isNan((try k.serial(&.{ 0, 0 })).d));
    try close(0, (try k.serial(&.{2})).d);
    try std.testing.expectError(error.ExecError, k.serial(&.{}));
    try std.testing.expectError(error.ExecError, k.serial(&.{std.math.nan(f64)}));
}

const rx = [_]f64{ 1, 0, 1, 0, 1, 1, 1, 1, 1, 2, 1, 2 };
const ry = [_]f64{ 1, 3, 2, 4, 7, 9 };
test "REG013 lack fit exact pure error decomposition degrees of freedom and F tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try qr.fit(a, &rx, &ry, 6, 2, null);
    const result = try k.lackFit(a, &rx, &ry, fit);
    // Replicate means2,3,8; beta=(4/3,3); within SS=2+2+2;
    // lack SS=2*((2/3)^2+(-4/3)^2+(2/3)^2)=16/3.
    try std.testing.expectEqual(@as(usize, 3), result.groups);
    try std.testing.expectEqual(@as(usize, 3), result.pure_df);
    try std.testing.expectEqual(@as(usize, 1), result.lack_df);
    try close(6, result.pure_ss);
    try close(16.0 / 3.0, result.lack_ss);
    try close(fit.sse, result.pure_ss + result.lack_ss);
    try close(2, result.pure_ms);
    try close(8.0 / 3.0, result.f);
    // Independent t_3 tail: for F=t², beta(3/2,1/2) integral is
    // (2/pi)*(theta-sin(theta)cos(theta)), sin²(theta)=3/(3+F).
    const theta = std.math.asin(@sqrt(@as(f64, 9.0 / 17.0)));
    try close(2.0 / std.math.pi * (theta - @sin(theta) * @cos(theta)), result.probability);
    const serial = try k.serial(fit.residuals);
    try close(42.0 / 17.0, serial.d);
    try close(-37.0 / 102.0, serial.correlation);
    const unique_fit = try qr.fit(a, &x, &y, 5, 2, null);
    const unique = try k.lackFit(a, &x, &y, unique_fit);
    try std.testing.expectEqual(@as(usize, 0), unique.pure_df);
    try std.testing.expect(std.math.isNan(unique.f) and std.math.isNan(unique.probability));
    const one = [_]f64{ 1, 1, 1, 1 };
    const intercept_fit = try qr.fit(a, &one, &.{ 1, 2, 3, 4 }, 4, 1, null);
    const intercept = try k.lackFit(a, &one, &.{ 1, 2, 3, 4 }, intercept_fit);
    try std.testing.expectEqual(@as(usize, 0), intercept.lack_df);
    try close(5, intercept.pure_ss);
    try std.testing.expect(std.math.isNan(intercept.f));
}

test "REG013 HC singular saturated and unit leverage domains stay explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const highx = [_]f64{ 1, 0, 1, 0, 1, 1 };
    const high = try qr.fit(a, &highx, &.{ 1, 3, 5 }, 3, 2, null);
    _ = try k.hetero(a, &highx, high, 0);
    try std.testing.expectError(error.ExecError, k.hetero(a, &highx, high, 2));
    try std.testing.expectError(error.ExecError, k.hetero(a, &highx, high, 3));
    const sx = [_]f64{ 1, 0, 1, 1 };
    const saturated = try qr.fit(a, &sx, &.{ 1, 3 }, 2, 2, null);
    try std.testing.expectError(error.ExecError, k.hetero(a, &sx, saturated, 0));
    const ax = [_]f64{ 1, 1, 1, 1, 1, 1 };
    const alias = try qr.fit(a, &ax, &.{ 1, 3, 5 }, 3, 2, null);
    try std.testing.expectError(error.ExecError, k.hetero(a, &ax, alias, 0));
    var frequency = high;
    frequency.n_used = 5;
    try std.testing.expectError(error.ExecError, k.hetero(a, &highx, frequency, 0));
    try std.testing.expectError(error.ExecError, k.lackFit(a, &highx, &.{ 1, 3, 5 }, frequency));
}

fn setup(a: A, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    for (ry, 0..) |v, i| try ds.appendRow(&.{ .{ .num = rx[2 * i + 1] }, .{ .num = v }, .{ .num = 1 } });
    try lib.put("sample", ds);
    return ds;
}
fn run(a: A, lib: *Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &out, try lex.tokenize(a, source, d));
    return out.items;
}
test "REG013 native DW LACKFIT HC producers and missing-row adjacency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try setup(a, &lib);
    const listing = try run(a, &lib, &d, "proc reg data=sample; model y=x / dw lackfit acov hccmethod=3; run;");
    try std.testing.expect(std.mem.indexOf(u8, listing, "Durbin-Watson D 2.471\nNumber of Observations 6\n1st Order Autocorrelation -0.363\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Lack of Fit 1 5.33333 5.33333 2.67 0.2010\nPure Error 3 6.00000 2.00000\n") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Heteroscedasticity Consistent Standard Error"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "Heteroscedasticity Consistent Covariance Matrix"));
    const hcc = try run(a, &lib, &d, "proc reg data=sample; model y=x / hcc; run;");
    const white = try run(a, &lib, &d, "proc reg data=sample; model y=x / white; run;");
    try std.testing.expectEqualStrings(hcc, white);
    try std.testing.expectEqualStrings(hcc, try run(a, &lib, &d, "proc reg data=sample; model y=x / hcc acovmethod=0; run;"));
    try std.testing.expect(std.mem.indexOf(u8, hcc, "Covariance Matrix") == null);
    try std.testing.expectEqual(@as(usize, 0), (try run(a, &lib, &d, "proc reg data=sample noprint; model y=x / dw lackfit acov; run;")).len);
    // Append a missing record, then move it into the middle of input order.
    try ds.appendRow(&.{ .{ .num = std.math.nan(f64) }, .{ .num = 100 }, .{ .num = 1 } });
    const last = ds.rows.items[6];
    std.mem.copyBackwards([]const @import("../value.zig").Value, ds.rows.items[3..7], ds.rows.items[2..6]);
    ds.rows.items[2] = last;
    const missing = try run(a, &lib, &d, "proc reg data=sample; model y=x / dw; run;");
    try std.testing.expect(std.mem.indexOf(u8, missing, "Durbin-Watson D 2.471\nNumber of Observations 6\n1st Order Autocorrelation -0.363\n") != null);
}

test "REG013 unsupported source conventions and malformed options use captured D009 severity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try setup(a, &lib);
    for ([_][]const u8{
        "proc reg data=sample;model y=x / spec;run;",
        "proc reg data=sample;model y=x / dwprob;run;",
        "proc reg data=sample;model y=x / dw;weight w;run;",
        "proc reg data=sample;model y=x / lackfit;freq w;run;",
        "proc reg data=sample;model y=x / acov;weight w;run;",
        "proc reg data=sample;model y=x / hcc;mtest x=0;run;",
        "proc reg data=sample;model y=x / lackfit;restrict x=0;run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    for ([_][]const u8{ "4", "1.5", "-1" }) |value| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        const source = try std.fmt.allocPrint(a, "proc reg data=sample;model y=x / hccmethod={s};run;", .{value});
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
}

test "REG013 robust TEST uses exact Wald quadratic and asymptotic tail not ordinary F" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fit = try @import("reg_diagnostics.zig").fit(a, &rx, &ry, 6, 2, null, true, 1e-9);
    const hc = try k.hetero(a, &rx, fit.fit, 3);
    const testmod = @import("reg_test.zig");
    const hypothesis = @import("linear_hypothesis.zig");
    const geometry = testmod.heteroGeometry(fit, hc.covariance);
    const result = try hypothesis.evaluate(a, geometry, &.{.{ .coefficients = &.{ 0, 1 } }}, null);
    // beta_x=3, HC3_xx=52/49: Wald=441/52. Chi1 tail=erfc(sqrt(W/2)).
    try close(441.0 / 52.0, result.wald.?);
    // Independently evaluated by Python stdlib math.erfc(sqrt(441/104)).
    try close(0.0035892030425683863, result.chi_square_probability.?);
    try std.testing.expect(result.f == null and result.denominator_df == null);
    const duplicate = try hypothesis.evaluate(a, geometry, &.{ .{ .coefficients = &.{ 0, 1 } }, .{ .coefficients = &.{ 0, 2 } } }, null);
    try std.testing.expectEqual(@as(usize, 1), duplicate.rank);
    try close(result.wald.?, duplicate.wald.?);
    const intermediate = try testmod.intermediate(a, geometry, &.{.{ .coefficients = &.{ 0, 1 } }});
    try close(52.0 / 49.0, intermediate.covariance[0]);
    try close(49.0 / 52.0, intermediate.inverse[0]);
    try close(3, intermediate.difference[0]);
    try close(147.0 / 52.0, intermediate.solution[0]);
    var lib = Library.init(a);
    _ = try setup(a, &lib);
    var d = diag.Diagnostics.init(a);
    const listing = try run(a, &lib, &d, "proc reg data=sample; model y=x / hcc hccmethod=3; slope: test x=0;run;");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, listing, "Test slope Results"));
    try std.testing.expect(std.mem.indexOf(u8, listing, "Numerator 1 36.00000 12.71 0.0235") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "DF Chi-Square Pr > ChiSq\n1 8.48 0.0036") != null);
    const printed = try run(a, &lib, &d, "proc reg data=sample; model y=x / acov hccmethod=3;test x=0 / print;run;");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, printed, "Heteroscedasticity Consistent Intermediate Calculations"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, printed, "\nTestCov\nRow"));
    try std.testing.expectEqual(@as(usize, 0), (try run(a, &lib, &d, "proc reg data=sample noprint;model y=x / hcc;test x=0 / print;run;")).len);
}

test "REG013 interactive robust TEST and REWEIGHT boundary preserve actual session semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try setup(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=sample;model y=x / hcc hccmethod=3;run;", &d)) };
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expect(try session.continuation(cx, &out, try lex.tokenize(a, "slope: test x=0;run;", &d)));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Test slope Results"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1 8.48 0.0036") != null);
    const oldlen = out.items.len;
    try std.testing.expect(try session.continuation(cx, &out, try lex.tokenize(a, "run;", &d)));
    try std.testing.expectEqual(oldlen, out.items.len);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expect(try session.continuation(cx, &out, try lex.tokenize(a, "reweight x=0 / weight=2;run;", &d)));
    try std.testing.expectError(error.ParseError, session.continuation(cx, &out, try lex.tokenize(a, "test x=0;run;", &d)));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(oldlen, out.items.len);
}
