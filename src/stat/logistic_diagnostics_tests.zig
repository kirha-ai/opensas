//! STAT-LOGISTIC-017; source equations S154 physical pp.5914–5918,5938–5941.
//! Published Example79.6 rows are independently rounded SAS results. Bounds
//! are half the final printed unit, not fitted to observed discrepancies.
const std = @import("std");
const t = std.testing;
const g = @import("logistic_diagnostics.zig");
const l = @import("logistic.zig");
const fit = @import("logistic_fit.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;

test "LOGISTIC017 hand intercept deletion and standardized residual identities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // Eight independent Bernoulli observations, three events: p=3/8,
    // information=15/8, covariance=8/15, h=1/8. Deletion is one event.
    const row = try g.observation(arena.allocator(), &.{1}, &.{8.0 / 15.0}, 1, 1, 1, 3.0 / 8.0);
    try t.expectApproxEqAbs(@sqrt(@as(f64, 5.0 / 3.0)), row.pearson, 1e-14);
    try t.expectApproxEqAbs(@sqrt(-2 * @log(@as(f64, 3.0 / 8.0))), row.deviance, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 8.0), row.leverage, 1e-15);
    try t.expectApproxEqAbs(@as(f64, 8.0 / 21.0), row.change[0], 1e-14);
    try t.expectApproxEqAbs((8.0 / 21.0) / @sqrt(@as(f64, 8.0 / 15.0)), row.dfbetas[0], 1e-14);
    try t.expectApproxEqAbs(@as(f64, 40.0 / 147.0), row.c, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 5.0 / 21.0), row.cbar, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 40.0 / 21.0), row.difchisq, 1e-14);
    try t.expectApproxEqAbs(row.deviance * row.deviance + 5.0 / 21.0, row.difdev, 1e-14);
    try t.expectApproxEqAbs(row.difdev, row.likelihood * row.likelihood, 1e-14);
    try t.expectApproxEqAbs(row.difchisq, row.standardized_pearson * row.standardized_pearson, 1e-14);
    // Independently take a Newton step for the seven-observation deleted
    // likelihood at the full MLE. Its score is -5/8, information=105/64.
    const deleted_step = (-5.0 / 8.0) / (105.0 / 64.0);
    try t.expectApproxEqAbs(-deleted_step, row.change[0], 1e-14);
    // Exact leave-one-out differs: LOGISTIC deliberately uses a one-step
    // estimate, not log(2/5), the deleted-sample intercept MLE.
    try t.expect(@abs((@log(@as(f64, 3.0 / 5.0)) - @log(@as(f64, 2.0 / 5.0))) - row.change[0]) > 0.02);
}

test "LOGISTIC017 binomial weights zero events saturated and invalid boundaries" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const row = try g.observation(a, &.{1}, &.{0.1}, 0, 4, 2, 0.25);
    try t.expectApproxEqAbs(-@sqrt(@as(f64, 8.0 / 3.0)), row.pearson, 1e-14);
    try t.expectApproxEqAbs(-@sqrt(-16 * @log(@as(f64, 0.75))), row.deviance, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.15), row.leverage, 1e-15);
    const saturated = try g.observation(a, &.{1}, &.{4}, 1, 1, 1, 0.5);
    try t.expectEqual(@as(f64, 1), saturated.leverage);
    try t.expectEqual(@as(f64, 1), saturated.pearson);
    for ([_]f64{ saturated.change[0], saturated.dfbetas[0], saturated.c, saturated.cbar, saturated.difdev, saturated.difchisq, saturated.likelihood }) |value| try t.expect(std.math.isNan(value));
    try t.expectError(error.ExecError, g.observation(a, &.{1}, &.{4}, 1, 1, 1, 0));
    try t.expectError(error.ExecError, g.observation(a, &.{1}, &.{4}, 1, 1, 1, 1));
    try t.expectError(error.ExecError, g.observation(a, &.{1}, &.{8}, 1, 1, 1, 0.5));
    try t.expectError(error.ExecError, g.observation(a, &.{1}, &.{-1}, 1, 1, 1, 0.5));
}

test "LOGISTIC017 information criteria small sample correction and likelihood R square" {
    const r = try g.information(-3, -5, 0, 2, 10, 10, 10);
    try t.expectEqual(@as(f64, 6), r.minus2logl);
    try t.expectEqual(@as(f64, 10), r.aic);
    try t.expectApproxEqAbs(6 + 2 * @log(@as(f64, 10)), r.sc, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 6.0 + 40.0 / 7.0), r.aicc, 1e-14);
    try t.expectApproxEqAbs(1 - @exp(@as(f64, -0.4)), r.rsquare, 1e-14);
    try t.expectApproxEqAbs(r.rsquare / (1 - @exp(@as(f64, -1))), r.max_rescaled, 1e-14);
    try t.expectEqual(@as(f64, 22), (try g.information(-3, -5, 0, 2, 4, 4, 4)).aicc);
    try t.expectEqual(@as(f64, 0), (try g.information(-5, -5, 0, 1, 10, 10, 10)).rsquare);
    try t.expectError(error.ExecError, g.information(-3, -5, 0, 2, 0, 0, 0));
}

fn vaso(a: A) !Dataset {
    const source = @embedFile("testdata/logistic017_original.sas");
    const start = std.mem.indexOf(u8, source, "datalines;").? + "datalines;".len;
    const end = start + std.mem.indexOfScalar(u8, source[start..], ';').?;
    var words = std.mem.tokenizeAny(u8, source[start..end], " \r\n\t");
    var ds = Dataset.init(a, "vaso");
    _ = try ds.addColumn("Response", .char);
    _ = try ds.addColumn("LogRate", .num);
    _ = try ds.addColumn("LogVolume", .num);
    while (words.next()) |volume| {
        const rate = words.next().?;
        const response = words.next().?;
        try ds.appendRow(&.{ .{ .str = response }, .{ .num = @log(try std.fmt.parseFloat(f64, rate)) }, .{ .num = @log(try std.fmt.parseFloat(f64, volume)) } });
    }
    return ds;
}
fn printed(token: []const u8, actual: f64) !void {
    const e = std.mem.indexOfAny(u8, token, "Ee") orelse token.len;
    const point = std.mem.indexOfScalar(u8, token[0..e], '.') orelse e;
    const digits: i32 = if (point < e) @intCast(e - point - 1) else 0;
    const exponent: i32 = if (e < token.len) try std.fmt.parseInt(i32, token[e + 1 ..], 10) else 0;
    const tolerance = 0.5 * std.math.pow(f64, 10, @floatFromInt(exponent - digits));
    try t.expectApproxEqAbs(try std.fmt.parseFloat(f64, token), actual, tolerance);
}

test "LOGISTIC017 all39 published diagnostic rows and source fitted coefficients" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try vaso(a);
    var lib = Library.init(a);
    try lib.put("vaso", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try l.parse(cx, try lex.tokenize(a, "proc logistic data=vaso; model Response=LogRate LogVolume / influence(stdres) rsquare; run;", &diagnostics));
    const result = try l.analyze(cx, spec);
    try t.expectEqual(@as(usize, 39), result.influence.len);
    try t.expect(result.fit.converged);
    try printed("-2.8754", result.fit.coefficients[0]);
    try printed("4.5617", result.fit.coefficients[1]);
    try printed("5.1793", result.fit.coefficients[2]);
    try printed("29.227", -2 * result.fit.log_likelihood);
    var rows = std.mem.tokenizeScalar(u8, @embedFile("testdata/logistic017_diagnostics.txt"), '\n');
    for (result.influence, 0..) |row, index| {
        var words = std.mem.tokenizeAny(u8, rows.next().?, " \t");
        try t.expectEqual(index + 1, try std.fmt.parseInt(usize, words.next().?, 10));
        try t.expectEqual(index, row.source);
        for (row.x[1..]) |value| try printed(words.next().?, value);
        for ([_]f64{ row.pearson, row.deviance, row.leverage }) |value| try printed(words.next().?, value);
        for (row.dfbetas) |value| try printed(words.next().?, value);
        for ([_]f64{ row.c, row.cbar, row.difdev, row.difchisq }) |value| try printed(words.next().?, value);
        try t.expect(words.next() == null);
    }
    try t.expect(rows.next() == null);
    try t.expectEqualStrings("", try diagnostics.render());
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic data=vaso; model Response=LogRate LogVolume / influence(stdres) rsquare; run;", &diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "Regression Diagnostics") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Standardized Pearson Residual") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "R-Square") != null);
}

test "LOGISTIC017 high leverage and near collinearity preserve deletion geometry" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Balanced outcomes at each design point give exact beta=0. The extreme
    // covariate pair has h=1532/4928 from inverse([[12,4],[4,412]]).
    const x = [_]f64{ 1, -1, 1, -1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 10, 1, 10, 1, -10, 1, -10, 1, 2, 1, 2 };
    const y = [_]f64{ 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1 };
    const r = try fit.fit(a, &x, &y, y.len, 2, .{});
    var sum: f64 = 0;
    for (y, 0..) |v, i| {
        const row = try g.observation(a, x[i * 2 ..][0..2], r.covariance, v, 1, 1, r.probabilities[i]);
        sum += row.leverage;
        // Independently invert the deleted observed information (2x2) at
        // beta=0. Its Newton step solves I_deleted * step = -x*(y-1/2).
        const covariate = x[i * 2 + 1];
        const aa: f64 = 11.0 / 4.0;
        const bb = (4 - covariate) / 4;
        const cc = (412 - covariate * covariate) / 4;
        const det = aa * cc - bb * bb;
        const score0 = -(v - 0.5);
        const score1 = score0 * covariate;
        try t.expectApproxEqAbs(-(cc * score0 - bb * score1) / det, row.change[0], 1e-14);
        try t.expectApproxEqAbs(-(-bb * score0 + aa * score1) / det, row.change[1], 1e-14);
        if (i == 6) try t.expectApproxEqAbs(@as(f64, 1532.0 / 4928.0), row.leverage, 1e-14);
    }
    try t.expectApproxEqAbs(@as(f64, 2), sum, 1e-13);
    // Add a nearly collinear column x+epsilon*z. An invertible coordinate
    // transformation must preserve hat diagonals and scalar displacements.
    var z: [36]f64 = undefined;
    for (0..12) |i| {
        z[i * 3] = 1;
        z[i * 3 + 1] = x[i * 2 + 1];
        z[i * 3 + 2] = x[i * 2 + 1] + 0.001 * @as(f64, @floatFromInt(i / 2 % 3));
    }
    const near = try fit.fit(a, &z, &y, 12, 3, .{});
    var orthogonal = z;
    for (0..12) |i| orthogonal[i * 3 + 2] = @floatFromInt(i / 2 % 3);
    const clean = try fit.fit(a, &orthogonal, &y, 12, 3, .{});
    for (y, 0..) |v, i| {
        const lhs = try g.observation(a, z[i * 3 ..][0..3], near.covariance, v, 1, 1, near.probabilities[i]);
        const rhs = try g.observation(a, orthogonal[i * 3 ..][0..3], clean.covariance, v, 1, 1, clean.probabilities[i]);
        // Covariance quadratic forms cancel O(1/epsilon^2) terms. This
        // absolute forward bound uses epsilon and design norm, not outputs.
        const bound = 128 * std.math.floatEps(f64) * 100 / (0.001 * 0.001);
        try t.expectApproxEqAbs(rhs.leverage, lhs.leverage, bound);
        try t.expectApproxEqAbs(rhs.c, lhs.c, 8 * bound);
    }
}

test "LOGISTIC017 grouped trial identity and frequency weight deletion semantics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "counts");
    for ([_][]const u8{ "r", "n", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = std.math.nan(f64) }, .{ .num = 8 }, .{ .num = 1 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 8 }, .{ .num = 2 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 4 }, .{ .num = 3 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 4 }, .{ .num = 0 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 4 }, .{ .num = 1 }, .{ .num = 0 } });
    var lib = Library.init(a);
    try lib.put("counts", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const spec = try l.parse(cx, try lex.tokenize(a, "proc logistic; freq f; weight w; model r/n= / influence; run;", &diagnostics));
    const result = try l.analyze(cx, spec);
    try t.expectEqual(@as(usize, 2), result.influence.len);
    try t.expectEqual(@as(usize, 1), result.influence[0].source);
    try t.expectEqual(@as(usize, 2), result.influence[1].source);
    try t.expectApproxEqAbs(@as(f64, 2.0 / 21.0), result.fit.covariance[0], 1e-14);
    try t.expectApproxEqAbs(@as(f64, 2.0 / 7.0), result.influence[0].leverage, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 1.0 / 7.0), result.influence[1].leverage, 1e-14);
    for (result.influence) |row| {
        try t.expectApproxEqAbs(@as(f64, 0), row.pearson, 1e-14);
        try t.expectApproxEqAbs(@as(f64, 0), row.change[0], 1e-14);
    }
    try t.expectEqualStrings("", try diagnostics.render());
}

test "LOGISTIC017 option guards suppression and incomplete fit status are captured" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try vaso(a);
    var lib = Library.init(a);
    try lib.put("vaso", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic noprint; model Response=LogRate LogVolume / influence rsq; run;", &diagnostics));
    try t.expectEqual(@as(usize, 0), out.items.len);
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic; model Response=LogRate LogVolume; run;", &diagnostics));
    try t.expect(std.mem.indexOf(u8, out.items, "Regression Diagnostics") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "R-Square") == null);
    out.clearRetainingCapacity();
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic; model Response=LogRate LogVolume / influence maxiter=1; run;", &diagnostics));
    try t.expect(diagnostics.warning_status);
    try t.expect(!diagnostics.hasErrors());
    try t.expect(std.mem.indexOf(u8, out.items, "Regression Diagnostics") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Iteration limit reached") != null);
    defer diag.resetGap();
    for ([_][]const u8{
        "proc logistic; model Response=LogRate LogVolume / influence link=probit; run;",
        "proc logistic; model Response=LogRate LogVolume / influence nofit; run;",
        "proc logistic; model Response=LogRate LogVolume / influence scale=2; run;",
        "proc logistic; model Response=LogRate LogVolume / influence(other); run;",
        "proc logistic plots(only label)=(phat leverage dpc); model Response=LogRate LogVolume; run;",
    }) |source| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var context = cx;
        context.diags = &d;
        out.clearRetainingCapacity();
        const outcome = l.run(context, &out, try lex.tokenize(a, source, &d));
        try t.expectError(error.ParseError, outcome);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "LOGISTIC017 implicit influence graphics never silently disappear" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try vaso(a);
    var lib = Library.init(a);
    try lib.put("vaso", &ds);
    var d = diag.Diagnostics.init(a);
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = t.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, l.run(cx, &out, try lex.tokenize(a, "proc logistic; model Response=LogRate LogVolume / influence; run;", &d)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try t.expect(std.mem.indexOf(u8, try d.render(), "INFLUENCE plots are not implemented") != null);
    try t.expectEqual(@as(usize, 0), out.items.len);
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic plots=none; model Response=LogRate LogVolume / influence; run;", &d));
    try t.expect(std.mem.indexOf(u8, out.items, "Regression Diagnostics") != null);
    try t.expectEqual(@as(usize, 0), graphics.prepared.items.len);
}

test "LOGISTIC017 original grouped likelihood R square uses trial mass" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "Data1");
    for ([_][]const u8{ "disease", "n", "age" }) |name| _ = try ds.addColumn(name, .num);
    const source = @embedFile("testdata/logistic017_original.sas");
    const start = std.mem.indexOf(u8, source, "input disease n age id $;\ndatalines;").? + "input disease n age id $;\ndatalines;".len;
    const end = start + std.mem.indexOfScalar(u8, source[start..], ';').?;
    var words = std.mem.tokenizeAny(u8, source[start..end], " \r\n\t");
    while (words.next()) |events| {
        const trials = words.next().?;
        const age = words.next().?;
        _ = words.next().?;
        try ds.appendRow(&.{ .{ .num = try std.fmt.parseFloat(f64, events) }, .{ .num = try std.fmt.parseFloat(f64, trials) }, .{ .num = try std.fmt.parseFloat(f64, age) } });
    }
    var lib = Library.init(a);
    try lib.put("Data1", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try l.parse(cx, try lex.tokenize(a, "proc logistic plots=none; model disease/n=age / rsquare; run;", &d));
    const result = try l.analyze(cx, spec);
    const info = try g.information(result.fit.log_likelihood, result.fit.null_log_likelihood, result.counts.full_constant, 2, 100, 6, 100);
    try printed("0.5215", info.rsquare);
    try printed("0.8925", info.max_rescaled);
    try printed("52.468", info.aic);
    try printed("57.678", info.sc);
    try printed("48.468", info.minus2logl);
    try printed("14.075", info.minus2logl - 2 * result.counts.full_constant);
    // Reweighting every trial scales both log likelihoods and denominator,
    // leaving both generalized R squares invariant.
    const rescaled = try g.information(7 * result.fit.log_likelihood, 7 * result.fit.null_log_likelihood, 7 * result.counts.full_constant, 2, 100, 6, 700);
    try t.expectApproxEqAbs(info.rsquare, rescaled.rsquare, 1e-14);
    try t.expectApproxEqAbs(info.max_rescaled, rescaled.max_rescaled, 1e-14);
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic plots=none; model disease/n=age / rsq; run;", &d));
    try t.expect(std.mem.indexOf(u8, out.items, "R-Square 0.5215 Max-rescaled R-Square 0.8925") != null);
    try t.expectEqualStrings("", try d.render());
}

test "LOGISTIC017 complete numeric diagnostic listing preserves all row fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try vaso(a);
    var lib = Library.init(a);
    try lib.put("vaso", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try l.run(cx, &out, try lex.tokenize(a, "proc logistic plots=none; model Response=LogRate LogVolume / influence; run;", &d));
    const start = std.mem.indexOf(u8, out.items, "Regression Diagnostics\n\n").? + "Regression Diagnostics\n\n".len;
    const split = start + std.mem.indexOf(u8, out.items[start..], "\n\n").?;
    try t.expectEqualStrings("Case Number LogRate LogVolume Pearson Residual Deviance Residual Hat Matrix Diagonal Intercept  DfBeta LogRate  DfBeta LogVolume  DfBeta Confidence Interval Displacement C Confidence Interval Displacement CBar Delta Deviance Delta Chi-Square", out.items[start..split]);
    var actual = std.mem.tokenizeAny(u8, out.items[split..], " \r\n\t");
    var reference = std.mem.tokenizeAny(u8, @embedFile("testdata/logistic017_diagnostics.txt"), " \r\n\t");
    var fields: usize = 0;
    while (reference.next()) |token| {
        try printed(token, try std.fmt.parseFloat(f64, actual.next().?));
        fields += 1;
    }
    try t.expectEqual(@as(usize, 39 * 13), fields);
    try t.expect(actual.next() == null);
}
