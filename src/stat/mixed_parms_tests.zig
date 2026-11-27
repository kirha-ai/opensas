//! PARMS contracts from S154 physical pp.6668-6671 and the profiled
//! likelihood grid in Example84.3 (physical pp.6755-6757).
const std = @import("std");
const t = std.testing;
const p = @import("mixed_parms.zig");
const f = @import("mixed_fit.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Harness = struct {
    cx: @import("../proc.zig").ProcCtx,
    fn init(a: std.mem.Allocator) !Harness {
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = .init(a);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        return .{ .cx = .{ .arena = a, .lib = lib, .diags = d } };
    }
    fn parse(h: Harness, source: []const u8) !p.Spec {
        const tokens = try lex.tokenize(h.cx.arena, source, h.cx.diags);
        const statements = [_]@import("mixed_parse.zig").Statement{.{ .kind = .parms, .tokens = tokens[0 .. tokens.len - 1], .line = 1 }};
        return (try p.parse(h.cx, &statements)).?;
    }
};
const simple = f.Model{ .x = &.{ 1, 1, 1, 1 }, .y = &.{ 0, 2, 2, 4 }, .n = 4, .p = 1 };
test "MIXED005 PARMS Cartesian ranges aliases bounds and dataset parameter order" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const s = try h.parse("(17 to 20 by .1) (.3 to .4 by .005) (1) / noprint noiter lowerb=0,.,0 upperb=.,2,. hold=1,3");
    const g = try p.grid(h.cx, s, 3);
    try t.expectEqual(@as(usize, 651), g.len);
    try t.expectEqualSlices(f64, &.{ 17, 0.3, 1 }, g[0]);
    try t.expectEqualSlices(f64, &.{ 20, 0.4, 1 }, g[g.len - 1]);
    try t.expectEqualSlices(usize, &.{ 0, 2 }, s.hold);
    try t.expect(s.noprint and s.noiter and s.lower[1] == null and s.upper[0] == null);
    const descending = try p.grid(h.cx, try h.parse("(3 to 1 by -1, 7) / noiter"), 1);
    try t.expectEqual(@as(usize, 4), descending.len);
    try t.expectEqual(@as(f64, 1), descending[2][0]);
    try t.expectEqual(@as(f64, 7), descending[3][0]);
    const data = try a.create(Dataset);
    data.* = .init(a, "initial");
    _ = try data.addColumn("Est", .num);
    try data.appendRow(&.{.{ .num = 3 }});
    try data.appendRow(&.{.{ .num = 2 }});
    try h.cx.lib.put("initial", data);
    const from_est = try p.grid(h.cx, try h.parse("/ pdata=initial noiter"), 2);
    try t.expectEqualSlices(f64, &.{ 3, 2 }, from_est[0]);
    const search = try a.create(Dataset);
    search.* = .init(a, "grid");
    _ = try search.addColumn("CovP1", .num);
    _ = try search.addColumn("CovP2", .num);
    try search.appendRow(&.{ .{ .num = 4 }, .{ .num = 1 } });
    try search.appendRow(&.{ .{ .num = 2 }, .{ .num = 3 } });
    try h.cx.lib.put("grid", search);
    const from_rows = try p.grid(h.cx, try h.parse("/ parmsdata=grid noiter"), 2);
    try t.expectEqual(@as(usize, 2), from_rows.len);
    try t.expectEqualSlices(f64, &.{ 2, 3 }, from_rows[1]);
}
test "MIXED005 real raw and profiled grid objectives known covariance and constraints" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const raw = try p.execute(h.cx, simple, try h.parse("(1,4) / noiter noprofile"), .{}, false);
    try t.expectEqual(f.Status.evaluated, raw.fit.status);
    try t.expect(!raw.fit.converged);
    try t.expectEqual(@as(usize, 0), raw.fit.iterations.len);
    try t.expect(!raw.profile);
    // Intercept2, SSE8, X'X=4. Known sigma²1 vs4: -2REML=3ln(2pi*v)+ln4+8/v.
    for (raw.rows, [_]f64{ 1, 4 }) |r, v| try t.expectApproxEqAbs(3 * @log(2 * std.math.pi * v) + @log(@as(f64, 4)) + 8 / v, r.objective.?, 1e-12);
    try t.expectEqual(@as(f64, 4), raw.fit.residual_variance);
    try t.expectApproxEqAbs(@as(f64, 1), raw.fit.covariance[0], 1e-14);
    const profiled = try p.execute(h.cx, simple, try h.parse("(1,4) / noiter"), .{}, false);
    try t.expect(profiled.profile);
    try t.expectApproxEqAbs(@as(f64, 8.0 / 3.0), profiled.fit.residual_variance, 1e-12);
    try t.expectApproxEqAbs(profiled.rows[0].objective.?, profiled.rows[1].objective.?, 1e-12);
    const bounded = try p.execute(h.cx, simple, try h.parse("(1,4) / noiter noprofile lowerb=2 upperb=4 hold=1"), .{}, false);
    try t.expect(bounded.rows[0].objective == null);
    try t.expectEqual(@as(f64, 4), bounded.fit.variances[0]);
    var out: std.ArrayList(u8) = .empty;
    try p.renderSearch(a, &out, raw, try h.parse("(1,4) / noiter noprofile"));
    try t.expect(std.mem.indexOf(u8, out.items, "CovP1 Res Log Like -2 Res Log Like") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Variance") == null);
    out.clearRetainingCapacity();
    try p.renderSearch(a, &out, profiled, try h.parse("(1,4) / noiter noprint"));
    try t.expectEqual(@as(usize, 0), out.items.len);
}
test "MIXED005 explicit starts and OLS preserve convergence and never substitute MIVQUE0" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const kernel = [_]f64{ 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1 };
    const model = f.Model{ .x = &.{ 1, 1, 1, 1, 1, 1 }, .y = &.{ -1, 1, 1, 3, 3, 5 }, .n = 6, .p = 1, .components = &.{.{ .name = "group", .kernel = &kernel, .columns = 3 }} };
    // Balanced profile Hessian in ratio r=tau²/sigma² is0.3 at r=1.5;
    // the 1e-16 relative criterion bounds the component error below1e-6.
    const explicit = try p.execute(h.cx, model, try h.parse("(1,2) (1) / noprint"), .{ .convergence = 1e-16 }, false);
    try t.expect(explicit.fit.converged);
    try t.expectEqual(@as(usize, 1), explicit.fit.iterations[0].iteration);
    try t.expectApproxEqAbs(@as(f64, 3), explicit.fit.variances[0], 1e-6);
    try t.expectApproxEqAbs(@as(f64, 2), explicit.fit.variances[1], 1e-6);
    const ols = try p.execute(h.cx, model, try h.parse("/ ols"), .{ .convergence = 1e-16 }, false);
    try t.expect(ols.fit.converged);
    try t.expectEqual(@as(usize, 0), ols.rows.len);
    try t.expectApproxEqAbs(@as(f64, 3), ols.fit.variances[0], 1e-6);
    const negative = try p.execute(h.cx, model, try h.parse("(-.1) (2) / nobound noiter noprofile"), .{}, false);
    try t.expectEqual(@as(f64, -0.1), negative.fit.variances[0]);
}
test "MIXED005 invalid and unimplemented requests are captured not silently ignored" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "(1 to 4 by 0)", "(4 to 1)", "(1) / hold=0", "(1) / banana", "()" }) |source| {
        const h = try Harness.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, h.parse(source));
        try t.expect(h.cx.diags.hasErrors());
        try t.expect(!diag.gapHit());
    }
    for ([_][]const u8{ "(1) / noiter noprofile lowerb=5 upperb=2", "(1) / noiter noprofile hold=2" }) |source| {
        const h = try Harness.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, p.execute(h.cx, simple, try h.parse(source), .{}, false));
        try t.expect(!diag.gapHit());
    }
    const empty = try Harness.init(a);
    try t.expectError(error.ExecError, p.execute(empty.cx, simple, try empty.parse("(0,1) / noiter noprofile lowerb=2"), .{}, false));
    for ([_][]const u8{ "(1) / logdeth", "(1) / hold=1", "(1) / lowerb=.1", "(1) / noiter lowerb=.1" }) |source| {
        const h = try Harness.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, p.execute(h.cx, simple, try h.parse(source), .{}, false));
        try t.expect(diag.gapHit());
    }
}
test "MIXED005 known dense covariance does not invent a residual parameter" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = f.Model{ .x = &.{ 1, 1 }, .y = &.{ 2, 4 }, .n = 2, .p = 1 };
    const gls = try f.knownCovarianceMatrix(a, model, &.{ 2, -0.5, -0.5, 2 });
    try t.expectApproxEqAbs(@as(f64, 3), gls.coefficients[0], 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.75), gls.covariance[0], 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.8), gls.quadratic, 1e-14);
    try t.expectError(error.NotPositiveDefinite, f.knownCovarianceMatrix(a, model, &.{ 1, 2, 2, 1 }));
}

fn sameWords(want: []const u8, got: []const u8) !void {
    var left = std.mem.tokenizeAny(u8, want, " \r\n\t");
    var right = std.mem.tokenizeAny(u8, got, " \r\n\t");
    while (left.next()) |word| try t.expectEqualStrings(word, right.next() orelse return error.MissingField);
    try t.expect(right.next() == null);
}
test "MIXED005 public PARMS runs complete known variance grid and hides only requested tables" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const data = try a.create(Dataset);
    data.* = .init(a, "sample");
    _ = try data.addColumn("y", .num);
    for ([_]f64{ 0, 2, 2, 4 }) |v| try data.appendRow(&.{.{ .num = v }});
    try h.cx.lib.put("sample", data);
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=sample noprofile noinfo;model y= /notest;parms (1,4) /noiter;run;", h.cx.diags));
    const first = 3 * @log(2 * std.math.pi) + @log(@as(f64, 4)) + 8;
    const second = 3 * @log(8 * std.math.pi) + @log(@as(f64, 4)) + 2;
    const expected = try std.fmt.allocPrint(a, "The Mixed Procedure Parameter Search CovP1 Res Log Like -2 Res Log Like 1.0000 {d:.4} {d:.4} 4.0000 {d:.4} {d:.4} Covariance Parameter Estimates Cov Parm Estimate Residual 4.0000", .{ -first / 2, first, -second / 2, second });
    try sameWords(expected, out.items);
    try t.expect(!h.cx.diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, out.items, "Convergence criteria met") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Fit Statistics") == null);
    out.clearRetainingCapacity();
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=sample noinfo;model y= /notest;parms (1,4) /noiter noprint;run;", h.cx.diags));
    try sameWords("The Mixed Procedure Covariance Parameter Estimates Cov Parm Estimate Residual 2.6667", out.items);
    out.clearRetainingCapacity();
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=sample noprofile;model y= /notest;parms (4) /noiter noprint;run;", h.cx.diags));
    try t.expect(std.mem.indexOf(u8, out.items, "Residual Variance Method Parameter") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Parameter Search") == null);
}

test "MIXED005 published 651 point likelihood surface and best-grid Newton transition" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    // Public Hemmerle-Hartley oven data, S154 physical pp.6754-6757.
    const factor_a = [_]usize{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 };
    const factor_b = [_]usize{ 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1 };
    const response = [_]f64{ 237, 254, 246, 178, 179, 208, 178, 187, 146, 145, 141, 186, 183, 142, 125, 136 };
    const x = try a.alloc(f64, 16 * 4);
    @memset(x, 0);
    const kb = try a.alloc(f64, 16 * 16);
    const kab = try a.alloc(f64, 16 * 16);
    for (0..16) |i| {
        x[i * 4] = 1;
        x[i * 4 + 1 + factor_a[i]] = 1;
        for (0..16) |j| {
            kb[i * 16 + j] = if (factor_b[i] == factor_b[j]) 1 else 0;
            kab[i * 16 + j] = if (factor_a[i] == factor_a[j] and factor_b[i] == factor_b[j]) 1 else 0;
        }
    }
    const model = f.Model{ .x = x, .y = &response, .n = 16, .p = 4, .components = &.{ .{ .name = "b", .kernel = kb, .columns = 2 }, .{ .name = "a*b", .kernel = kab, .columns = 6 } } };
    const spec = try h.parse("(17 to 20 by .1) (.3 to .4 by .005) (1.0)");
    const result = try p.execute(h.cx, model, spec, .{ .bic_n = 2 }, false);
    try t.expectEqual(@as(usize, 651), result.rows.len);
    // Published four-decimal endpoints: half a final displayed unit, not a
    // tolerance inferred from the OpenSAS discrepancy.
    try t.expectApproxEqAbs(@as(f64, 80.1400), result.rows[0].residual.?, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 104.9399), result.rows[0].objective.?, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 77.5148), result.rows[650].residual.?, 0.00005);
    try t.expectApproxEqAbs(@as(f64, 104.9406), result.rows[650].objective.?, 0.00005);
    try t.expect(result.fit.converged);
    try t.expectEqual(@as(usize, 1), result.fit.iterations.len);
    try t.expectEqual(@as(usize, 1), result.fit.iterations[0].iteration);
    try t.expectEqual(@as(usize, 2), result.fit.iterations[0].evaluations);
    try t.expectApproxEqAbs(@as(f64, 104.93416367), result.fit.minus2loglik, 0.000000005);
    try t.expectApproxEqAbs(@as(f64, 1464.36), result.fit.variances[0], 0.005);
    try t.expectApproxEqAbs(@as(f64, 26.9581), result.fit.variances[1], 0.00005);
    try t.expectApproxEqAbs(@as(f64, 78.8426), result.fit.variances[2], 0.00005);
    const lrt = result.likelihood_ratio.?;
    try t.expectEqual(@as(usize, 2), lrt.df);
    var minimum = std.math.inf(f64);
    for (result.rows) |row| minimum = @min(minimum, row.objective.?);
    try t.expectApproxEqAbs(minimum - result.fit.minus2loglik, lrt.statistic, 1e-12);
    // Chi-square2 survival has the elementary form exp(-x/2).
    try t.expectApproxEqAbs(@exp(-lrt.statistic / 2), lrt.p, 1e-14);
}
