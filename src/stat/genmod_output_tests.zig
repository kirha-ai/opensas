//! STAT-GENMOD-018 permanent tests: the OUTPUT OUT= data set is read back from
//! the library and every value is checked against hand calculations written
//! here, independently of genmod_output.zig. Data: invented (identity link) and
//! the published ch.51 Normal/log-link example data (log link).
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const genmod = @import("genmod.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const nan = std.math.nan(f64);
const z95: f64 = 1.959963984540054; // probit(0.975)

fn near(expected: f64, actual: f64, tol: f64) !void {
    if (std.math.isNan(expected)) {
        if (!std.math.isNan(actual)) {
            std.debug.print("expected missing, got {d}\n", .{actual});
            return error.TestExpectedEqual;
        }
        return;
    }
    if (!(@abs(expected - actual) <= tol * @max(1, @abs(expected)))) {
        std.debug.print("expected {d}, got {d}\n", .{ expected, actual });
        return error.TestExpectedEqual;
    }
}

const Step = struct { rc: u8, text: []const u8, d: diag.Diagnostics };

fn noted(step: Step, text: []const u8) bool {
    for (step.d.list.items) |m| if (m.severity == .note and std.mem.indexOf(u8, m.message, text) != null) return true;
    return false;
}

fn runStep(a: A, lib: *Library, source: []const u8) !Step {
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var text: std.ArrayList(u8) = .empty;
    genmod.run(.{ .arena = a, .lib = lib, .diags = &d }, &text, try lex.tokenize(a, source, &d)) catch |err| switch (err) {
        error.ParseError => {},
        else => return err,
    };
    return .{ .rc = diag.exitCode(diag.gapHit(), d.hasErrors()), .text = text.items, .d = d };
}

// Identity link, x = -2..2 (n = 5 used), plus one row with a missing response
// (x = 3) and one with a missing covariate. For the 5 used rows:
//   xbar = 0, Sxx = 10, ybar = 3, Sxy = 8  =>  b0 = 3, b1 = 0.8
//   fitted 1.4 2.2 3 3.8 4.6; raw residuals -0.4 0.8 -1 1.2 -0.6; SSE = 3.6
//   phi = SSE/n = 0.72 (ML scale^2);  h = 1/5 + x^2/10 = .6 .3 .2 .3 .6 (OLS hat)
//   Cov(b) = phi (X'X)^-1 = diag(0.144, 0.072)  =>  stdxbeta = sqrt(0.144 + 0.072 x^2)
const ix = [_]f64{ -2, -1, 0, 1, 2, 3, nan };
const iy = [_]f64{ 1, 3, 2, 5, 4, nan, 7 };
const ifit = [_]f64{ 1.4, 2.2, 3, 3.8, 4.6, 5.4, nan };
const iraw = [_]f64{ -0.4, 0.8, -1, 1.2, -0.6, nan, nan };
const ih = [_]f64{ 0.6, 0.3, 0.2, 0.3, 0.6, nan, nan };

fn identityData(a: A, lib: *Library, shift: []const f64) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "lin");
    _ = try ds.addColumn("g", .num);
    const id = try ds.addColumn("id", .char);
    ds.columns.items[id].len = 3;
    ds.columns.items[id].label = "Identifier";
    const xi = try ds.addColumn("x", .num);
    ds.columns.items[xi].format = "8.2";
    _ = try ds.addColumn("y", .num);
    for (shift, 1..) |sv, g| for (ix, iy) |xv, yv|
        try ds.appendRow(&.{ .{ .num = @floatFromInt(g) }, .{ .str = "abc" }, .{ .num = xv }, .{ .num = yv + sv } });
    try lib.put("lin", ds);
}

fn checkIdentityRows(o: *const Dataset, first: usize, shift: f64, group: f64) !void {
    const tol = 1e-9;
    for (0..7) |k| {
        const row = o.rows.items[first + k];
        // Input variables are copied unchanged, in order.
        try near(group, row[0].num, 0);
        try expectEqualStrings("abc", row[1].str);
        try near(ix[k], row[2].num, 0);
        try near(iy[k] + shift, row[3].num, 0);
        const se = @sqrt(0.144 + 0.072 * ix[k] * ix[k]);
        const std_res = iraw[k] / @sqrt(0.72 * (1 - ih[k]));
        const expected = [_]f64{
            ifit[k] + shift, // P
            ifit[k] + shift, // XB (identity link)
            se, // SXB
            ifit[k] + shift - z95 * se, // LO
            ifit[k] + shift + z95 * se, // UP
            iraw[k], // RR
            iraw[k], // RC: (y-mu) sqrt(w/V), w = V = 1
            iraw[k], // RD: sign(r) sqrt((y-mu)^2)
            std_res, // SC
            std_res, // SD
            std_res, // RL: sign(r) sqrt((1-h) SD^2 + h SC^2), SD = SC
            ih[k], // LEV
        };
        for (expected, 4..) |e, ci| near(e, row[ci].num, tol) catch |err| {
            std.debug.print("row {d} column {s}\n", .{ first + k, o.columns.items[ci].name });
            return err;
        };
    }
}

const all_keywords = "p=P xbeta=XB stdxbeta=SXB lower=LO upper=UP resraw=RR reschi=RC resdev=RD stdreschi=SC stdresdev=SD reslik=RL leverage=LEV";
const all_names = [_][]const u8{ "g", "id", "x", "y", "P", "XB", "SXB", "LO", "UP", "RR", "RC", "RD", "SC", "SD", "RL", "LEV" };

test "STAT-GENMOD-018 identity link: OUT= variables, types and every value match the OLS closed form" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try identityData(a, &lib, &.{0});
    // An existing member of the same name is replaced.
    const old = try a.create(Dataset);
    old.* = Dataset.init(a, "o");
    _ = try old.addColumn("stale", .num);
    try lib.put("o", old);
    const step = try runStep(a, &lib, "proc genmod data=lin; model y = x; output out=o " ++ all_keywords ++ "; run;");
    try expectEqual(@as(u8, 0), step.rc);
    // The OUTPUT statement produces no tabular output: same tables as without it.
    try expectEqual(@as(usize, 1), std.mem.count(u8, step.text, "Analysis Of Maximum Likelihood Parameter Estimates"));
    try expect(std.mem.indexOf(u8, step.text, "Number of Observations Used           5") != null);
    const o = lib.find("o").?;
    try expectEqual(all_names.len, o.columns.items.len);
    for (all_names, o.columns.items, 0..) |name, c, ci| {
        try expectEqualStrings(name, c.name);
        try expect((c.type == .char) == (ci == 1));
    }
    // Input attributes carry over.
    try expectEqual(@as(?usize, 3), o.columns.items[1].len);
    try expectEqualStrings("Identifier", o.columns.items[1].label.?);
    try expectEqualStrings("8.2", o.columns.items[2].format.?);
    // One row per input observation, including the two not used in the fit.
    try expectEqual(@as(usize, 7), o.rows.items.len);
    try expect(noted(step, "The data set WORK.O has 7 observations and 16 variables."));
    try checkIdentityRows(o, 0, 0, 1);
}

test "STAT-GENMOD-018 BY groups stack in input order; two-level OUT= name; OUT= alone copies the input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    // Group 2 is group 1 with y + 10: same residuals and leverages, fitted + 10.
    try identityData(a, &lib, &.{ 0, 10 });
    const step = try runStep(a, &lib, "proc genmod data=lin; by g; model y = x; output out=work.o2 " ++ all_keywords ++ "; run;");
    try expectEqual(@as(u8, 0), step.rc);
    const o = lib.find("work.o2").?;
    try expectEqual(all_names.len, o.columns.items.len);
    try expect(noted(step, "The data set WORK.O2 has 14 observations and 16 variables."));
    try expectEqual(@as(usize, 14), o.rows.items.len);
    try checkIdentityRows(o, 0, 0, 1);
    try checkIdentityRows(o, 7, 10, 2);

    const plain = try runStep(a, &lib, "proc genmod data=lin; model y = x; output out=copy; run;");
    try expectEqual(@as(u8, 0), plain.rc);
    const c = lib.find("copy").?;
    try expectEqual(@as(usize, 4), c.columns.items.len);
    try expectEqual(@as(usize, 14), c.rows.items.len);
    try expectEqualStrings("y", c.columns.items[3].name);
    try near(14, c.rows.items[11][3].num, 0);
}

// Published data of the ch.51 Normal regression / log link example.
const nx = [_]f64{ 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5 };
const ny = [_]f64{ 5, 7, 9, 7, 10, 8, 11, 9, 16, 13, 14, 25, 24, 34, 32, 30 };

test "STAT-GENMOD-018 log link: residuals, leverage and limits match independent weighted formulas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "nor");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for (nx, ny) |xv, yv| try ds.appendRow(&.{ .{ .num = xv }, .{ .num = yv } });
    try ds.appendRow(&.{ .{ .num = 6 }, Value.missing }); // prediction-only row
    try lib.put("nor", ds);
    const step = try runStep(a, &lib, "proc genmod data=nor; model y = x / dist=normal link=log; output out=Residuals pred=Pred resraw=Resraw reschi=Reschi resdev=Resdev stdreschi=Stdreschi stdresdev=Stdresdev reslik=Reslik h=Lev xbeta=Xb stdxbeta=Se l=Lo u=Up; run;");
    try expectEqual(@as(u8, 0), step.rc);
    const o = lib.find("Residuals").?;
    const names = [_][]const u8{ "x", "y", "Pred", "Resraw", "Reschi", "Resdev", "Stdreschi", "Stdresdev", "Reslik", "Lev", "Xb", "Se", "Lo", "Up" };
    try expectEqual(names.len, o.columns.items.len);
    for (names, o.columns.items) |name, c| {
        try expectEqualStrings(name, c.name);
        try expect(c.type == .num);
    }
    try expectEqual(@as(usize, 17), o.rows.items.len);
    const rows = o.rows.items;

    // 1. Pred is the ML mean: the score equations sum (y-mu) mu x_j = 0 hold,
    //    and Xb = log(Pred) is linear in x (b0 = Xb at x=0, b1 from x=5).
    const b0 = rows[0][10].num;
    const b1 = (rows[13][10].num - b0) / 5;
    var s0: f64 = 0;
    var s1: f64 = 0;
    var sse: f64 = 0;
    // Expected weights W = 1/g'(mu)^2 = mu^2 (phi cancels in h); observed
    // information for the covariance: sum (mu^2 - (y-mu) mu) x x' / phi.
    var w = [_]f64{ 0, 0, 0 }; // X'WX: [00, 01, 11]
    var ob = [_]f64{ 0, 0, 0 };
    for (nx, ny, 0..) |xv, yv, k| {
        const mu = @exp(b0 + b1 * xv);
        try near(mu, rows[k][2].num, 1e-12);
        try near(b0 + b1 * xv, rows[k][10].num, 1e-12);
        const r = yv - mu;
        s0 += r * mu;
        s1 += r * mu * xv;
        sse += r * r;
        const ow = mu * mu - r * mu;
        for ([_]f64{ 1, xv, xv * xv }, 0..) |q, j| {
            w[j] += mu * mu * q;
            ob[j] += ow * q;
        }
    }
    try near(0, s0, 1e-6);
    try near(0, s1, 1e-6);
    // Published listing: Intercept 1.7214, x 0.3496, Deviance 52.3000, Scale 1.8080.
    try near(1.7214, b0, 5e-5);
    try near(0.3496, b1, 5e-5 / 0.3496);
    try near(52.3, sse, 5e-5 / 52.3);
    const phi = sse / 16;
    try near(1.8080, @sqrt(phi), 5e-5);
    const wdet = w[0] * w[2] - w[1] * w[1];
    const odet = ob[0] * ob[2] - ob[1] * ob[1];
    var trace: f64 = 0;
    for (nx, ny, 0..) |xv, yv, k| {
        const mu = @exp(b0 + b1 * xv);
        const r = yv - mu;
        // h = W x'(X'WX)^-1 x with the 2x2 inverse written out.
        const h = mu * mu * (w[2] - 2 * w[1] * xv + w[0] * xv * xv) / wdet;
        trace += h;
        const sr = r / @sqrt(phi * (1 - h));
        const lik = std.math.sign(r) * @sqrt((1 - h) * sr * sr + h * sr * sr);
        for ([_]f64{ r, r, r, sr, sr, lik, h }, 3..) |e, ci| near(e, rows[k][ci].num, 1e-7) catch |err| {
            std.debug.print("row {d} column {s}\n", .{ k, o.columns.items[ci].name });
            return err;
        };
        const se = @sqrt(phi * (ob[2] - 2 * ob[1] * xv + ob[0] * xv * xv) / odet);
        try near(se, rows[k][11].num, 1e-7);
        try near(@exp(b0 + b1 * xv - z95 * se), rows[k][12].num, 1e-7);
        try near(@exp(b0 + b1 * xv + z95 * se), rows[k][13].num, 1e-7);
    }
    try near(2, trace, 1e-9); // trace of the hat matrix = number of parameters
    // Published listing: standard errors 0.0894 and 0.0206.
    try near(0.0894, rows[0][11].num, 5e-5 / 0.0894);
    // Missing response: predicted value, XBETA, STDXBETA and limits are
    // computed; residuals and leverage are missing.
    const last = rows[16];
    try near(@exp(b0 + 6 * b1), last[2].num, 1e-12);
    for (3..10) |ci| try expect(std.math.isNan(last[ci].num));
    const se6 = @sqrt(phi * (ob[2] - 12 * ob[1] + 36 * ob[0]) / odet);
    try near(se6, last[11].num, 1e-7);
    try near(@exp(b0 + 6 * b1 - z95 * se6), last[12].num, 1e-7);
    try near(@exp(b0 + 6 * b1 + z95 * se6), last[13].num, 1e-7);
}

test "STAT-GENMOD-018 OUTPUT boundaries: user errors exit 1, unfinished shapes are loud gaps, nothing is written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try identityData(a, &lib, &.{0});
    const Case = struct { statement: []const u8, rc: u8 };
    const cases = [_]Case{
        .{ .statement = "output out=bad nosuch=v;", .rc = 1 }, // unknown keyword
        .{ .statement = "output out=bad pred;", .rc = 1 }, // keyword without =name
        .{ .statement = "output out=bad pred=;", .rc = 1 },
        .{ .statement = "output out=bad pred=(a b);", .rc = 1 }, // a list is only for the DFBETA family
        .{ .statement = "output out=;", .rc = 1 },
        .{ .statement = "output out=bad. pred=v;", .rc = 1 },
        .{ .statement = "output pred=v;", .rc = 2 }, // DATAn naming
        .{ .statement = "output out=bad(keep=x) pred=v;", .rc = 2 },
        .{ .statement = "output out=bad hesswgt=v;", .rc = 2 },
        .{ .statement = "output out=bad dfbeta=_all_;", .rc = 2 },
        .{ .statement = "output out=bad dfbetas=(a b);", .rc = 2 },
        .{ .statement = "output out=bad cookd=v;", .rc = 2 },
        .{ .statement = "output out=bad pzero=v;", .rc = 2 },
        .{ .statement = "output out=bad clusterh=v;", .rc = 2 },
        .{ .statement = "output out=bad pred=v p=w;", .rc = 2 }, // repeated statistic
        .{ .statement = "output out=bad pred=v xbeta=V;", .rc = 2 }, // duplicate name
        .{ .statement = "output out=bad pred=X;", .rc = 2 }, // input variable name
        .{ .statement = "output out=bad pred=v; output out=bad2 pred=v;", .rc = 2 },
        .{ .statement = "output out=_null_ pred=v;", .rc = 2 },
    };
    for (cases) |case| {
        const step = try runStep(a, &lib, try std.fmt.allocPrint(a, "proc genmod data=lin; model y = x; {s} run;", .{case.statement}));
        expectEqual(case.rc, step.rc) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.statement});
            return err;
        };
        try expectEqual(@as(usize, 0), step.text.len);
        try expect(lib.find("bad") == null and lib.find("bad2") == null);
    }
}
