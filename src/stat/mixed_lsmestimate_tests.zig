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
    const h = try Harness.init(a);
    const Case = struct { body: []const u8, rc: u8 };
    for ([_]Case{ .{ .body = "lsmestimate group 1 -1 /divisor=0;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /adjust=tukey;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /ilink;", .rc = 1 }, .{ .body = "lsmestimate group 1 -1 /adjust=simulate;", .rc = 2 }, .{ .body = "lsmestimate group 1 -1 /joint upper;", .rc = 2 }, .{ .body = "lsmestimate group 1 -1 /testvalue=1;", .rc = 2 }, .{ .body = "lsmestimate group 1 -1 /plots=none;", .rc = 2 } }) |c| {
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
