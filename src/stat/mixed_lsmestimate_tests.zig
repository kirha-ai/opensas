//! Complete consumer/reference and independent K*L1 inference contracts.
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const math = @import("mixed_fit.zig");
const lsm = @import("mixed_lsmestimate.zig");
const Harness = struct {
    cx: proc.ProcCtx,
    ds: *@import("../dataset.zig").Dataset,
    fn init(a: std.mem.Allocator) !Harness {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/stat_common027_lsmestimate.sas", "sample", &.{ "x", "z", "y", "group", "weight", "freq" }, &.{3}, 0);
        const lib = try a.create(Library);
        lib.* = .init(a);
        try lib.put("sample", ds);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        return .{ .cx = .{ .arena = a, .lib = lib, .diags = d }, .ds = ds };
    }
    fn prepare(h: Harness, body: []const u8) !struct { m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fit: math.Fit, requests: []const lsm.Request } {
        const source = try std.fmt.allocPrint(h.cx.arena, "proc mixed data=sample;class group;model y=group x;{s}run;", .{body});
        const s = try @import("mixed_parse.zig").parse(h.cx, try lex.tokenize(h.cx.arena, source, h.cx.diags));
        const m = try model.parse(h.cx, h.ds, s.statements, .formatted, 0.05);
        const r = try random.parse(h.cx, h.ds, m.matrix, s.statements);
        const view = try @import("data_selection.zig").View.init(h.cx.arena, s.input, .{});
        const x = try fixed.build(h.cx, m, view);
        const z = try random.build(h.cx, r, view);
        const fit = try math.fit(h.cx.arena, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .singular = m.options.singular }, .{});
        return .{ .m = m, .r = r, .x = x, .z = z, .fit = fit, .requests = try lsm.parse(h.cx, m, s.statements) };
    }
};
test "STAT-COMMON-027 complete original consumer preserves every SAS listing token" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const helper = @import("glm_persistence_tests.zig");
    const source = try helper.read(a, "tests/corpus/stat_common027_lsmestimate.sas");
    const start = std.mem.indexOf(u8, source, "proc mixed data=sample;").?;
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, source[start..], h.cx.diags));
    const contract = try helper.read(a, "tests/corpus/stat_common027_lsmestimate.txt");
    const begin = std.mem.indexOf(u8, contract, "words ").? + 6;
    const end = std.mem.indexOfScalarPos(u8, contract, begin, '\n').?;
    var want = std.mem.tokenizeAny(u8, contract[begin..end], " \r\n\t");
    var got = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (want.next()) |word| try t.expectEqualStrings(word, got.next() orelse return error.TestUnexpectedResult);
    try t.expect(got.next() == null);
    try t.expectEqual(@as(usize, 0), h.cx.diags.list.items.len);
}

test "STAT-COMMON-027 additive ANCOVA Type III and LSmean coefficients follow independent algebra" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group 'B minus A' -1 1 /cl;");
    const group = try fixed.type3(h.cx, p.m, p.x, 0);
    const slope = try fixed.type3(h.cx, p.m, p.x, 1);
    try t.expectEqualSlices(f64, &.{ 0, 1, -1, 0 }, group.coefficients);
    try t.expectEqualSlices(f64, &.{ 0, 0, 0, 1 }, slope.coefficients);
    const result = try lsm.compute(h.cx, p.m, p.r, p.x, p.z, p.fit, p.requests[0]);
    const row = result.rows[0];
    try t.expectEqualSlices(f64, &.{ -1, 1 }, row.k);
    try t.expectEqualSlices(f64, &.{ 0, -1, 1, 0 }, row.l);
    // Within-group Sxx35,Sxy119/2 -> slope17/10; adjustedB-A=79/30.
    // MSE581/540, difference variance=(143/105)*MSE=11869/8100.
    try t.expectApproxEqAbs(@as(f64, 79.0 / 30.0), row.inference.estimate.?, 1e-10);
    try t.expectApproxEqAbs(@as(f64, 11869.0 / 8100.0), row.inference.se.? * row.inference.se.?, 1e-10);
    try t.expectEqual(@as(f64, 9), row.inference.df);
    const fg = try math.testContrast(a, p.fit, group.coefficients, 1, 9);
    const fx = try math.testContrast(a, p.fit, slope.coefficients, 1, 9);
    try t.expectApproxEqAbs(@as(f64, 56169.0 / 11869.0), fg.f, 1e-9);
    try t.expectApproxEqAbs(@as(f64, 54621.0 / 581.0), fx.f, 1e-9);
    const radius = 2.2621571627409915 * @sqrt(@as(f64, 11869.0 / 8100.0));
    try t.expectApproxEqAbs(79.0 / 30.0 - radius, row.inference.lower.?, 1e-9);
    try t.expectApproxEqAbs(79.0 / 30.0 + radius, row.inference.upper.?, 1e-9);
}

test "STAT-COMMON-027 row divisors multiply global divisors and joint rows use actual rank" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group 'A minus B' 8 -8 divisor=2, 'B minus A' -3 3 divisor=3 /divisor=4,. cl adjust=bon joint(label='both');");
    const result = try lsm.compute(h.cx, p.m, p.r, p.x, p.z, p.fit, p.requests[0]);
    try t.expectEqualSlices(f64, &.{ 1, -1 }, result.rows[0].k);
    try t.expectEqualSlices(f64, &.{ -1, 1 }, result.rows[1].k);
    try t.expectApproxEqAbs(-result.rows[0].inference.estimate.?, result.rows[1].inference.estimate.?, 1e-12);
    for (result.rows) |row| try t.expectApproxEqAbs(@min(1, 2 * row.inference.p.?), row.adjusted_p.?, 1e-14);
    try t.expectEqual(@as(usize, 1), result.joint.?.num_df);
    try t.expectApproxEqAbs(@as(f64, 56169.0 / 11869.0), result.joint.?.f.?, 1e-9);
    // ADJUST uses estimate-row count2, not the one pair among two LS-means.
    try t.expect(result.rows[0].adjusted_p.? > result.rows[0].inference.p.?);
}

test "STAT-COMMON-027 positional row order follows displayed class order and zero coefficients stay typed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group 'comparison' -1 1, 'zero' 0 0 /cl;");
    std.mem.reverse([]const @import("../value.zig").Value, h.ds.rows.items);
    var m = p.m;
    m.matrix.order = .data;
    const view = try @import("data_selection.zig").View.init(a, .{ .ds = h.ds }, .{});
    const x = try fixed.build(h.cx, m, view);
    const z = try random.build(h.cx, p.r, view);
    const fitted = try math.fit(a, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights }, .{});
    const result = try lsm.compute(h.cx, m, p.r, x, z, fitted, p.requests[0]);
    try t.expectEqualStrings("B", x.matrix.classes[0].map.levels[0].label);
    try t.expectApproxEqAbs(@as(f64, -79.0 / 30.0), result.rows[0].inference.estimate.?, 1e-10);
    const zero = result.rows[1].inference;
    try t.expect(zero.estimable and zero.estimate.? == 0 and zero.se.? == 0 and zero.t == null and zero.p == null);
    try t.expectEqual(@as(?f64, 0), zero.lower);
    try t.expectEqual(@as(?f64, 0), zero.upper);
}

test "STAT-COMMON-027 nonestimable LSmeans can form an estimable row and invalid options remain loud" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "A", "B", "Y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 0 }, .{ 1, 1, 2 }, .{ 2, 1, 2 }, .{ 2, 1, 4 }, .{ 3, 2, 9 }, .{ 3, 2, 11 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = Library.init(a);
    try lib.put("d", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = "proc mixed;class A B;model Y=A B /notest;lsmestimate A 'difference' 1 -1 0, 'margin' 1 0 0 /cl;run;";
    const s = try @import("mixed_parse.zig").parse(cx, try lex.tokenize(a, source, &diagnostics));
    const m = try model.parse(cx, &ds, s.statements, .formatted, 0.05);
    const r = try random.parse(cx, &ds, m.matrix, s.statements);
    const view = try @import("data_selection.zig").View.init(a, s.input, .{});
    const x = try fixed.build(cx, m, view);
    const z = try random.build(cx, r, view);
    const f = try math.knownCovariance(a, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p }, &.{1});
    const requests = try lsm.parse(cx, m, s.statements);
    const result = try lsm.compute(cx, m, r, x, z, f, requests[0]);
    try t.expect(result.rows[0].inference.estimable);
    try t.expectApproxEqAbs(@as(f64, -2), result.rows[0].inference.estimate.?, 1e-12);
    try t.expect(!result.rows[1].inference.estimable);
    try t.expect(result.rows[1].inference.estimate == null);
    // Nonzero nulls must not turn a nonestimable margin into a number.
    var shifted = requests[0];
    shifted.test_values = &.{1};
    shifted.joint = true;
    const shifted_result = try lsm.compute(cx, m, r, x, z, f, shifted);
    try t.expect(shifted_result.rows[0].inference.estimable);
    try t.expect(!shifted_result.rows[1].inference.estimable);
    try t.expect(shifted_result.rows[1].inference.estimate == null and shifted_result.rows[1].inference.se == null and shifted_result.rows[1].inference.p == null);
    try t.expect(!shifted_result.joint.?.estimable);
    const h = try Harness.init(a);
    const Case = struct { body: []const u8, rc: u8 };
    for ([_]Case{ .{ .body = "lsmestimate group 1 -1 /divisor=0;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /adjust=tukey;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /ilink;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /adjust=simulate;", .rc = 2 }, .{ .body = "lsmestimate group 1 -1 /joint upper;", .rc = 2 }, .{ .body = "lsmestimate group 1 -1 /testvalue=;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /plots=none;", .rc = 2 } }) |c| {
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, h.prepare(c.body));
        try t.expectEqual(c.rc, diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors()));
    }
}

test "STAT-COMMON-027 default no-CL does not compute an unrequested extreme quantile" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group -1 1 /df=.01;");
    const result = try lsm.compute(h.cx, p.m, p.r, p.x, p.z, p.fit, p.requests[0]);
    try t.expect(result.rows[0].inference.p != null);
    try t.expect(result.rows[0].inference.lower == null and result.rows[0].inference.upper == null);
    const ci = try h.prepare("lsmestimate group -1 1 /df=.01 cl;");
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, lsm.compute(h.cx, ci.m, ci.r, ci.x, ci.z, ci.fit, ci.requests[0]));
    try t.expect(diag.gapHit());
}

test "STAT-COMMON-027 divisor carry-forward Sidak family count and one-sided direction are independent" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group 'forward' -2 2, 'reverse' 2 -2, 'again' -2 2 /divisor=2 cl adjust=sidak;");
    const result = try lsm.compute(h.cx, p.m, p.r, p.x, p.z, p.fit, p.requests[0]);
    for (result.rows) |row| {
        const raw = row.inference.p.?;
        try t.expectApproxEqAbs(3 * raw - 3 * raw * raw + raw * raw * raw, row.adjusted_p.?, 1e-14);
        try t.expect(row.adjusted_lower.? < row.inference.lower.? and row.adjusted_upper.? > row.inference.upper.?);
    }
    try t.expectApproxEqAbs(@as(f64, 79.0 / 30.0), result.rows[2].inference.estimate.?, 1e-10);
    const up = try h.prepare("lsmestimate group -1 1 /upper cl;");
    const down = try h.prepare("lsmestimate group 1 -1 /lower cl;");
    const u = (try lsm.compute(h.cx, up.m, up.r, up.x, up.z, up.fit, up.requests[0])).rows[0];
    const l = (try lsm.compute(h.cx, down.m, down.r, down.x, down.z, down.fit, down.requests[0])).rows[0];
    try t.expectApproxEqAbs(u.inference.p.?, l.inference.p.?, 1e-14);
    try t.expect(u.inference.upper == null and l.inference.lower == null);
    try t.expectApproxEqAbs(-u.inference.lower.?, l.inference.upper.?, 1e-10);
    const low_confidence = try h.prepare("lsmestimate group -1 1 /upper alpha=.75 adjust=bon;");
    const bounded = (try lsm.compute(h.cx, low_confidence.m, low_confidence.r, low_confidence.x, low_confidence.z, low_confidence.fit, low_confidence.requests[0])).rows[0];
    try t.expectEqual(bounded.inference.lower, bounded.adjusted_lower);
    try t.expect(bounded.adjusted_lower.? > bounded.inference.estimate.?);
}

test "STAT-COMMON-027 actual JOINT ONLY output and GLM applicability remain distinct" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    var out: std.ArrayList(u8) = .empty;
    const source = "proc mixed data=sample;class group;model y=group x;lsmestimate group 'forward' -1 1, 'reverse' 1 -1 /joint(only label='joint comparison');run;";
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, source, h.cx.diags));
    try t.expect(std.mem.indexOf(u8, out.items, "Least Squares Means Estimate") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "joint comparison 1 9 4.73 0.0576") != null);
    diag.resetGap();
    defer diag.resetGap();
    var invalid: std.ArrayList(u8) = .empty;
    try t.expectError(error.ParseError, @import("glm.zig").run(h.cx, &invalid, try lex.tokenize(a, "proc glm data=sample;class group;model y=group x;lsmestimate group -1 1 /cl;run;", h.cx.diags)));
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), h.cx.diags.hasErrors()));
}

test "STAT-COMMON-027 lower-tail presentation names the probability it reports" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(a, "proc mixed data=sample;class group;model y=group x;lsmestimate group 'lower' 1 -1 /lower cl;run;", h.cx.diags));
    try t.expect(std.mem.indexOf(u8, out.items, "Tails Pr < t") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Lower 0.0288") != null);
}

test "STAT-MIXED-011 TESTVALUE and TESTMEAN affect tests but never estimates or intervals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const base = try h.prepare("lsmestimate group -2 2, -2 2, -2 2 /divisor=2 cl df=1 adjust=sidak;");
    const changed = try h.prepare("lsmestimate group -2 2, -2 2, -2 2 /divisor=2 cl df=1 adjust=sidak testvalue=.,2;");
    const b = try lsm.compute(h.cx, base.m, base.r, base.x, base.z, base.fit, base.requests[0]);
    const c = try lsm.compute(h.cx, changed.m, changed.r, changed.x, changed.z, changed.fit, changed.requests[0]);
    // S154 physical p.520: missing nulls become0, last value carries
    // forward; divisor scales coefficients but not nulls. df1 has the exact
    // Cauchy CDF, so tail probabilities here do not reuse the beta kernel.
    for (b.rows, c.rows, 0..) |before, after, i| {
        const null_value: f64 = if (i == 0) 0 else 2;
        const statistic = (79.0 / 30.0 - null_value) / @sqrt(@as(f64, 11869.0 / 8100.0));
        const probability = 1 - 2 * std.math.atan(statistic) / std.math.pi;
        try t.expectApproxEqAbs(statistic, after.inference.t.?, 1e-10);
        try t.expectApproxEqAbs(probability, after.inference.p.?, 1e-11);
        try t.expectApproxEqAbs(1 - std.math.pow(f64, 1 - probability, 3), after.adjusted_p.?, 1e-11);
        try t.expectEqual(before.inference.estimate, after.inference.estimate);
        try t.expectEqual(before.inference.se, after.inference.se);
        try t.expectEqual(before.inference.lower, after.inference.lower);
        try t.expectEqual(before.inference.upper, after.inference.upper);
        try t.expectEqual(before.adjusted_lower, after.adjusted_lower);
        try t.expectEqual(before.adjusted_upper, after.adjusted_upper);
        try t.expectEqual(@as(f64, 1), after.inference.df);
    }
    const synonym = try h.prepare("lsmestimate group -1 1 /df=1 testmean=2,999;");
    const row = (try lsm.compute(h.cx, synonym.m, synonym.r, synonym.x, synonym.z, synonym.fit, synonym.requests[0])).rows[0];
    try t.expectEqual(c.rows[1].inference.p, row.inference.p);
    for ([_][]const u8{ "lsmestimate group -1 1 /testvalue=;", "lsmestimate group -1 1 /testmean=1,;", "lsmestimate group -1 1 /testvalue=1e999;" }) |body| {
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, h.prepare(body));
        try t.expect(!diag.gapHit());
    }
}

test "STAT-MIXED-011 shifted one-sided nulls reverse tails and retain confidence endpoints" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    // Null4 exceeds estimate79/30, changing the sign of t. The mirror
    // comparison has null-4 and must have the identical opposite-tail p.
    const up = try h.prepare("lsmestimate group -1 1 /df=1 testvalue=4 upper cl adjust=bon;");
    const down = try h.prepare("lsmestimate group 1 -1 /df=1 testvalue=-4 lower cl adjust=bon;");
    const u = (try lsm.compute(h.cx, up.m, up.r, up.x, up.z, up.fit, up.requests[0])).rows[0];
    const d = (try lsm.compute(h.cx, down.m, down.r, down.x, down.z, down.fit, down.requests[0])).rows[0];
    const statistic = (79.0 / 30.0 - 4) / @sqrt(@as(f64, 11869.0 / 8100.0));
    const probability = 0.5 - std.math.atan(statistic) / std.math.pi;
    try t.expectApproxEqAbs(probability, u.inference.p.?, 1e-11);
    try t.expectApproxEqAbs(probability, d.inference.p.?, 1e-11);
    try t.expectApproxEqAbs(-u.inference.t.?, d.inference.t.?, 1e-12);
    try t.expectEqual(u.inference.p, u.adjusted_p);
    try t.expect(u.inference.upper == null and d.inference.lower == null);
    // Cauchy95% one-sided critical value cot(pi/20).
    const lower = 79.0 / 30.0 - @sqrt(@as(f64, 11869.0 / 8100.0)) / @tan(std.math.pi / 20.0);
    try t.expectApproxEqAbs(lower, u.inference.lower.?, 1e-9);
    try t.expectApproxEqAbs(-lower, d.inference.upper.?, 1e-9);
}

test "STAT-MIXED-011 dependent JOINT nulls use rank and reject inconsistent constraints visibly" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a);
    const p = try h.prepare("lsmestimate group -1 1, -2 2 /testvalue=1,2 joint cl df=1;");
    const result = try lsm.compute(h.cx, p.m, p.r, p.x, p.z, p.fit, p.requests[0]);
    try t.expect(result.joint.?.estimable);
    try t.expectEqual(@as(usize, 1), result.joint.?.num_df);
    try t.expectEqual(@as(f64, 1), result.joint.?.den_df);
    // (79/30-1)^2 / (11869/8100) = 21609/11869.
    try t.expectApproxEqAbs(@as(f64, 21609.0 / 11869.0), result.joint.?.f.?, 1e-10);
    try t.expectApproxEqAbs(result.rows[0].inference.p.?, result.joint.?.p.?, 1e-11);
    const invalid = try h.prepare("lsmestimate group -1 1, -2 2 /testvalue=1,3 joint;");
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, lsm.compute(h.cx, invalid.m, invalid.r, invalid.x, invalid.z, invalid.fit, invalid.requests[0]));
    try t.expect(diag.gapHit());
    try t.expect(std.mem.indexOf(u8, h.cx.diags.list.items[h.cx.diags.list.items.len - 1].message, "inconsistent") != null);
}

const OneWay = struct {
    h: Harness,
    fn init(a: std.mem.Allocator, groups: []const []const f64) !OneWay {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = .init(a, "sample");
        _ = try ds.addColumn("group", .num);
        _ = try ds.addColumn("y", .num);
        for (groups, 0..) |group, i| for (group) |y| {
            try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = y } });
        };
        const lib = try a.create(Library);
        lib.* = .init(a);
        try lib.put("sample", ds);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        return .{ .h = .{ .cx = .{ .arena = a, .lib = lib, .diags = d }, .ds = ds } };
    }
    fn compute(self: OneWay, body: []const u8) !lsm.Result {
        const h = self.h;
        const source = try std.fmt.allocPrint(h.cx.arena, "proc mixed data=sample;class group;model y=group;{s}run;", .{body});
        const s = try @import("mixed_parse.zig").parse(h.cx, try lex.tokenize(h.cx.arena, source, h.cx.diags));
        const m = try model.parse(h.cx, h.ds, s.statements, .formatted, 0.05);
        const r = try random.parse(h.cx, h.ds, m.matrix, s.statements);
        const view = try @import("data_selection.zig").View.init(h.cx.arena, s.input, .{});
        const x = try fixed.build(h.cx, m, view);
        const z = try random.build(h.cx, r, view);
        const fit = try math.fit(h.cx.arena, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .singular = m.options.singular }, .{});
        const requests = try lsm.parse(h.cx, m, s.statements);
        return lsm.compute(h.cx, m, r, x, z, fit, requests[0]);
    }
};

test "STAT-MIXED-011 unbalanced independent means joint null covariance and equal weighting" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try OneWay.init(a, &.{ &.{ 1, 3 }, &.{ 4, 6, 8 } });
    const result = try h.compute("lsmestimate group 'A' 1 0, 'B' 0 1 /testvalue=0,1 joint cl;");
    // Independent cell means2 and6, SSE=10, errorDF=3, MSE=10/3.
    // Var(meanA)=5/3, Var(meanB)=10/9; H0:(A,B)=(0,1).
    try t.expectApproxEqAbs(@as(f64, 2), result.rows[0].inference.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 6), result.rows[1].inference.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 5.0 / 3.0), std.math.pow(f64, result.rows[0].inference.se.?, 2), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 10.0 / 9.0), std.math.pow(f64, result.rows[1].inference.se.?, 2), 1e-12);
    try t.expectEqual(@as(usize, 2), result.joint.?.num_df);
    try t.expectEqual(@as(f64, 3), result.joint.?.den_df);
    try t.expectApproxEqAbs(@as(f64, 12.45), result.joint.?.f.?, 1e-11);
    // F(2,3) survival is (3/(3+2F))^(3/2).
    try t.expectApproxEqAbs(std.math.pow(f64, 3.0 / (3 + 2 * 12.45), 1.5), result.joint.?.p.?, 1e-12);
    const average = try h.compute("lsmestimate group 'equal average' 1 1 /divisor=2 cl;");
    try t.expectApproxEqAbs(@as(f64, 4), average.rows[0].inference.estimate.?, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 5.0 / 6.0), average.rows[0].inference.se.?, 1e-12);
    std.mem.reverse([]const @import("../value.zig").Value, h.h.ds.rows.items);
    const reversed = try h.compute("lsmestimate group 'A' 1 0, 'B' 0 1 /testvalue=0,1 joint cl;");
    try t.expectApproxEqAbs(result.joint.?.f.?, reversed.joint.?.f.?, 1e-11);
}

test "STAT-MIXED-011 full FerriteCores original data has independent isotonic estimates and DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Complete public Example84.10 data, not a runtime oracle dependency.
    // Cell means103/10,54/5,113/10,56/5; SSE109/50, MSE109/800.
    const h = try OneWay.init(a, &.{ &.{ 10.8, 9.9, 10.7, 10.4, 9.7 }, &.{ 10.7, 10.6, 11.0, 10.8, 10.9 }, &.{ 11.9, 11.2, 11.0, 11.1, 11.3 }, &.{ 11.4, 10.7, 10.9, 11.3, 11.7 } });
    const rows = "lsmestimate group 'avg(1:1)<avg(2:4)' -3 1 1 1 divisor=3, 'avg(1:2)<avg(3:4)' -1 -1 1 1 divisor=2, 'avg(1:3)<avg(4:4)' -1 -1 -1 3 divisor=3";
    const result = try h.compute(try std.fmt.allocPrint(a, "{s}/cl upper;", .{rows}));
    // Student-t95% one-sided quantile16df (independent tabulation).
    const critical: f64 = 1.74588367627624;
    for (result.rows, [_]f64{ 0.8, 0.7, 0.4 }, [_]f64{ 109.0 / 3000.0, 109.0 / 4000.0, 109.0 / 3000.0 }) |row, mean, variance| {
        try t.expectApproxEqAbs(mean, row.inference.estimate.?, 1e-11);
        try t.expectApproxEqAbs(@sqrt(variance), row.inference.se.?, 1e-11);
        try t.expectEqual(@as(f64, 16), row.inference.df);
        try t.expectApproxEqAbs(mean / @sqrt(variance), row.inference.t.?, 1e-10);
        try t.expectApproxEqAbs(mean - critical * @sqrt(variance), row.inference.lower.?, 1e-10);
        try t.expect(row.inference.upper == null);
    }
    // The original simulated adjustment still fails explicitly. This test is
    // only the exact deterministic subproblem, not acceptance of its RNG.
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, h.compute(try std.fmt.allocPrint(a, "{s}/adjust=simulate(seed=1) cl upper;", .{rows})));
    try t.expect(diag.gapHit());
}

test "STAT-MIXED-011 actual consumer TESTVALUE listing agrees with independent Cauchy contract" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    const ds = try a.create(@import("../dataset.zig").Dataset);
    ds.* = try helper.data(a, "tests/corpus/stat_mixed_lsmestimate_null.sas", "sample", &.{ "group", "y" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("sample", ds);
    var diagnostics = diag.Diagnostics.init(a);
    var listing = @import("../ods_listing.zig").Listing{};
    _ = try listing.parse(a, &diagnostics, try lex.tokenize(a, "ods select LSMEstimates Contrasts;", &diagnostics));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics, .listing = &listing };
    const source = try helper.read(a, "tests/corpus/stat_mixed_lsmestimate_null.sas");
    const start = std.mem.indexOf(u8, source, "proc mixed data=sample;").?;
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source[start..], &diagnostics));
    const expected = try helper.read(a, "tests/corpus/stat_mixed_lsmestimate_null.txt");
    const begin = std.mem.indexOf(u8, expected, "words ").? + 6;
    const end = std.mem.indexOfScalarPos(u8, expected, begin, '\n').?;
    var want = std.mem.tokenizeAny(u8, expected[begin..end], " \r\n\t");
    var got = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (want.next()) |word| try t.expectEqualStrings(word, got.next() orelse return error.TestUnexpectedResult);
    try t.expect(got.next() == null);
    try t.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-MIXED-011 mixed split plot null uses GLS covariance and containment source DF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    var lib = Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = "proc mixed data=sp;class A B Block;model Y=A B A*B;random Block A*Block;lsmestimate A 1 -1 0 /testvalue=1 cl joint;run;";
    const s = try @import("mixed_parse.zig").parse(cx, try lex.tokenize(a, source, &diagnostics));
    const m = try model.parse(cx, &ds, s.statements, .formatted, 0.05);
    const r = try random.parse(cx, &ds, m.matrix, s.statements);
    const view = try @import("data_selection.zig").View.init(a, s.input, .{});
    const x = try fixed.build(cx, m, view);
    const z = try random.build(cx, r, view);
    const components = try a.alloc(math.Component, z.components.len);
    for (z.components, components) |src, *dst| dst.* = .{ .name = src.name, .kernel = src.kernel, .columns = src.columns };
    // Reuse the permanent split-plot data and variance-component algebra of
    // MIXED010: A1-A2=-5/4; Var(A1-A2)=321/32; containment DF6.
    const fit = try math.knownCovariance(a, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components, .singular = m.options.singular }, &.{ 2995.0 / 48.0, 2215.0 / 144.0, 337.0 / 36.0 });
    const request = (try lsm.parse(cx, m, s.statements))[0];
    const result = try lsm.compute(cx, m, r, x, z, fit, request);
    const row = result.rows[0].inference;
    try t.expectApproxEqAbs(@as(f64, -1.25), row.estimate.?, 1e-9);
    try t.expectApproxEqAbs(@as(f64, 321.0 / 32.0), row.se.? * row.se.?, 1e-8);
    try t.expectEqual(@as(f64, 6), row.df);
    const statistic = -2.25 / @sqrt(@as(f64, 321.0 / 32.0));
    const u = -statistic / @sqrt(6 + statistic * statistic);
    const probability = 1 - 15.0 / 8.0 * (u - 2 * u * u * u / 3 + u * u * u * u * u / 5);
    try t.expectApproxEqAbs(statistic, row.t.?, 1e-9);
    try t.expectApproxEqAbs(probability, row.p.?, 1e-10);
    try t.expectApproxEqAbs(statistic * statistic, result.joint.?.f.?, 1e-9);
    try t.expectEqual(@as(f64, 6), result.joint.?.den_df);
    const radius = 2.44691185114497 * @sqrt(@as(f64, 321.0 / 32.0));
    try t.expectApproxEqAbs(-1.25 - radius, row.lower.?, 1e-8);
    try t.expectApproxEqAbs(-1.25 + radius, row.upper.?, 1e-8);
}
