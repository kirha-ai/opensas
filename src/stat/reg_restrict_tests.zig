//! Independent small constrained least-squares cases for STAT-REG-007.
const std = @import("std");
const reg = @import("reg.zig");
const restrictions = @import("reg_restrict.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;

fn fixture(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y" }) |name| _ = try ds.addColumn(name, .num);
    const x = [_]f64{ -2, -1, 1, 2 };
    const z = [_]f64{ -1, -2, 2, 1 };
    const y = [_]f64{ 6, 8, 10, 16 };
    for (x, z, y) |u, v, response| try ds.appendRow(&.{ .{ .num = u }, .{ .num = v }, .{ .num = response } });
    try lib.put("sample", ds);
}
fn parse(cx: proc.ProcCtx, source: []const u8) !reg.Spec {
    return reg.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
}
fn run(cx: proc.ProcCtx, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try reg.run(cx, &out, try lex.tokenize(cx.arena, source, cx.diags));
    return out.items;
}
fn number(ds: *Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}

test "REG007 restriction parser linear equations chains replacement and model scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, "proc reg data=sample; first: model y=x z; restrict 2*x-z=intercept+3, x=z=0; second: model y=x z; restrict x; restrict z=1; third: model y=x; run;");
    try std.testing.expectEqual(@as(usize, 3), spec.models.len);
    const first = spec.models[0].restrictions;
    try std.testing.expectEqual(@as(usize, 3), first.len);
    try std.testing.expectEqualSlices(f64, &.{ -1, 2, -1 }, first[0].coefficients);
    try std.testing.expectEqual(@as(f64, 3), first[0].rhs);
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, -1 }, first[1].coefficients);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 1 }, first[2].coefficients);
    const second = spec.models[1].restrictions;
    try std.testing.expectEqual(@as(usize, 1), second.len);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 1 }, second[0].coefficients);
    try std.testing.expectEqual(@as(f64, 1), second[0].rhs);
    try std.testing.expectEqual(@as(usize, 0), spec.models[2].restrictions.len);
    try std.testing.expect(!d.hasErrors());
}

test "REG007 constrained projection covariance objective and beta multiplier inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, -2, -1, 1, -1, -2, 1, 1, 2, 1, 2, 1 };
    const y = [_]f64{ 6, 8, 10, 16 };
    var fit = try @import("reg_fit.zig").fit(a, &x, &y, 4, 3, null);
    const result = try restrictions.apply(a, &fit, &x, &y, &.{ 1, 1, 1, 1 }, &.{.{ .coefficients = &.{ 0, 0, 1 }, .rhs = 0 }});
    // G slopes=[[5/18,-2/9],[-2/9,5/18]], beta=(10,3,-1).
    // With z=0, beta=(10,11/5,0), SSE=38/5, DF=2, MSE=19/5.
    for (fit.coefficients, [_]f64{ 10, 11.0 / 5.0, 0 }) |actual, expected| try std.testing.expectApproxEqAbs(expected, actual, 1e-13);
    try std.testing.expectEqual(@as(f64, 0), fit.coefficients[2]);
    try std.testing.expectEqual(@as(f64, 0), fit.se[2]);
    try std.testing.expect(std.math.isNan(fit.coefficientT(2)));
    try std.testing.expectEqual(@as(usize, 2), fit.rank);
    try std.testing.expectEqual(@as(usize, 2), fit.df_error);
    try std.testing.expectApproxEqAbs(@as(f64, 38.0 / 5.0), fit.sse, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 19.0 / 5.0), fit.mse, 1e-13);
    const kernel = [_]f64{ 0.25, 0, 0, 0, 0.1, 0, 0, 0, 0 };
    for (fit.covariance_unscaled, fit.covariance, kernel) |base, cov, expected| {
        try std.testing.expectApproxEqAbs(expected, base, 1e-13);
        try std.testing.expectApproxEqAbs(expected * 19.0 / 5.0, cov, 1e-13);
    }
    for (fit.leverage, [_]f64{ 0.65, 0.35, 0.35, 0.65 }) |h, expected| try std.testing.expectApproxEqAbs(expected, h, 1e-13);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    const multiplier = result[0];
    try std.testing.expectApproxEqAbs(@as(f64, -18.0 / 5.0), multiplier.estimate, 1e-13);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 342)) / 5, multiplier.se, 1e-13);
    try std.testing.expectApproxEqAbs(-@sqrt(@as(f64, 18.0 / 19.0)), multiplier.t, 1e-13);
    // For DF_R=2, Beta(1/2,1/2) has CDF 2 asin(sqrt(z))/pi.
    const probability = 1 - 2 * std.math.asin(@sqrt(@as(f64, 9.0 / 19.0))) / std.math.pi;
    try std.testing.expectApproxEqAbs(probability, multiplier.probability, 1e-13);
    // Among all z=0 vectors, perturbing either free coefficient increases SSE.
    for ([_][3]f64{ .{ 10.25, 2.2, 0 }, .{ 10, 2.45, 0 }, .{ 9.75, 1.95, 0 } }) |candidate| {
        var sse: f64 = 0;
        for (y, 0..) |response, i| {
            const residual = response - candidate[0] - candidate[1] * x[3 * i + 1];
            sse += residual * residual;
        }
        try std.testing.expect(sse > fit.sse);
    }
}

test "REG007 typed OUTEST preserves restricted estimates covariance and multiple models" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const listing = try run(cx, "proc reg data=sample outest=est covout; first: model y=x z; restrict z=0; second: model y=x z; run;");
    const est = lib.find("est").?;
    try std.testing.expectEqual(@as(usize, 8), est.rows.items.len);
    for ([_][]const u8{ "Intercept", "x", "z" }, [_]f64{ 10, 2.2, 0 }) |name, expected| try std.testing.expectApproxEqAbs(expected, number(est, 0, name), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), number(est, 1, "Intercept"), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0.38), number(est, 2, "x"), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 0), number(est, 3, "z"), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 3), number(est, 4, "x"), 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, -1), number(est, 4, "z"), 1e-13);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "NOTE: Restrictions have been applied to parameter estimates."));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, listing, "RESTRICT -1"));
    try std.testing.expect(std.mem.indexOf(u8, listing, "* Probability computed using beta distribution.") != null);
    try std.testing.expect(!d.hasErrors());
}

test "REG007 nonzero and multiple constraints satisfy KKT and constrained covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = [_]f64{ 1, -2, -1, 1, -1, -2, 1, 1, 2, 1, 2, 1 };
    const y = [_]f64{ 6, 8, 10, 16 };
    const constraint = [_]restrictions.Constraint{
        .{ .coefficients = &.{ 1, 0, 0 }, .rhs = 10 },
        .{ .coefficients = &.{ 0, 1, -1 }, .rhs = 0 },
    };
    var fit = try @import("reg_fit.zig").fit(a, &x, &y, 4, 3, null);
    const result = try restrictions.apply(a, &fit, &x, &y, &.{ 1, 1, 1, 1 }, &constraint);
    for (fit.coefficients, [_]f64{ 10, 1, 1 }) |actual, expected| try std.testing.expectApproxEqAbs(expected, actual, 1e-13);
    try std.testing.expectApproxEqAbs(@as(f64, 20), fit.sse, 1e-12);
    try std.testing.expectEqual(@as(usize, 3), fit.df_error);
    for (constraint) |r| {
        var actual: f64 = 0;
        for (fit.coefficients, r.coefficients) |beta, coefficient| actual += beta * coefficient;
        try std.testing.expectApproxEqAbs(r.rhs, actual, 1e-13);
        for (0..3) |j| {
            var covariance: f64 = 0;
            for (r.coefficients, 0..) |coefficient, k| covariance += coefficient * fit.covariance[k * 3 + j];
            try std.testing.expectApproxEqAbs(@as(f64, 0), covariance, 1e-13);
        }
    }
    // Stationarity: X'(y-X beta_R)=R'lambda. Check every coefficient.
    for (0..3) |j| {
        var left: f64 = 0;
        var right: f64 = 0;
        for (fit.residuals, 0..) |residual, i| left += x[i * 3 + j] * residual;
        for (constraint, result) |r, multiplier| right += r.coefficients[j] * multiplier.estimate;
        try std.testing.expectApproxEqAbs(left, right, 1e-12);
    }
}

test "REG007 restrictions are ignored for RIDGE and PCOMIT as documented" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    _ = try run(cx, "proc reg data=sample ridge=0 outest=r noprint; model y=x z; restrict z=0; run;");
    _ = try run(cx, "proc reg data=sample pcomit=0 outest=p noprint; model y=x z; restrict z=0; run;");
    for ([_][]const u8{ "r", "p" }) |name| {
        const ds = lib.find(name).?;
        try std.testing.expectApproxEqAbs(@as(f64, 3), number(ds, 1, "x"), 1e-13);
        try std.testing.expectApproxEqAbs(@as(f64, -1), number(ds, 1, "z"), 1e-13);
    }
    try std.testing.expect(!d.hasErrors());
}

test "REG007 malformed restrictions and unsupported singular systems fail visibly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try fixture(a, &lib);
    for ([_][]const u8{
        "proc reg data=sample; restrict x=0; model y=x z; run;",
        "proc reg data=sample; model y=x z; restrict unknown=0; run;",
        "proc reg data=sample; model y=x z; restrict x*z=0; run;",
        "proc reg data=sample; model y=x z; restrict x=; run;",
        "proc reg data=sample; model y=x z; restrict x=0,; run;",
        "proc reg data=sample; model y=x z; restrict ; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &d }, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    for ([_][]const u8{
        "proc reg data=sample outest=bad; model y=x z; restrict x=0,x=0; run;",
        "proc reg data=sample outest=bad; model y=x z; restrict x=0,x=1; run;",
        "proc reg data=sample outest=bad; model y=x z; restrict intercept=0,x=0,z=0; run;",
        "proc reg data=sample outest=bad; model y=x z; restrict intercept=100; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &d }, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expect(lib.find("bad") == null);
    }
}

test "REG007 precision weights and replicated frequencies rescale restricted covariance correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib);
    const ds = lib.find("sample").?;
    _ = try ds.addColumn("two", .num);
    for (ds.rows.items, 0..) |old, i| {
        const row = try a.alloc(@import("../value.zig").Value, 4);
        @memcpy(row[0..3], old);
        row[3] = .{ .num = 2 };
        ds.rows.items[i] = row;
    }
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    _ = try run(cx, "proc reg data=sample outest=w covout noprint; model y=x z; restrict z=0; weight two; run;");
    _ = try run(cx, "proc reg data=sample outest=f covout noprint; model y=x z; restrict z=0; freq two; run;");
    const weight = lib.find("w").?;
    const freq = lib.find("f").?;
    // WEIGHT doubles SSE and halves G, but keeps N=4/DF=2. FREQ doubles
    // N to 8, giving restricted DF=6 and one-third the weighted covariance.
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 38.0 / 5.0)), number(weight, 0, "_RMSE_"), 1e-13);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 38.0 / 15.0)), number(freq, 0, "_RMSE_"), 1e-13);
    for ([_][]const u8{ "Intercept", "x", "z" }, [_]f64{ 0.95, 0.38, 0 }, 0..) |name, expected, i| {
        try std.testing.expectApproxEqAbs(expected, number(weight, i + 1, name), 1e-13);
        try std.testing.expectApproxEqAbs(expected / 3, number(freq, i + 1, name), 1e-13);
    }
    try std.testing.expect(!d.hasErrors());
}
