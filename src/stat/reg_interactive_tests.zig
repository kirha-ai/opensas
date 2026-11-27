//! REG-004 interactive contracts, derived from a four-corner orthogonal design.
const std = @import("std");
const reg = @import("reg.zig");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;

fn sample(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "corners");
    for ([_][]const u8{ "x", "z", "y", "v", "spare" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ -1, -1, 12, -7.5 }, .{ -1, 1, 4, -1.5 }, .{ 1, -1, 14, -10.5 }, .{ 1, 1, 10, 3.5 } }) |row| {
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] }, .{ .num = 99 } });
    }
    // This observation must stay excluded after DELETE z: the first-RUN
    // crossproducts pool and its missingness policy do not change interactively.
    try ds.appendRow(&.{ .{ .num = 0 }, @import("../value.zig").Value.missing, .{ .num = 1000 }, .{ .num = 1000 }, .{ .num = 99 } });
    try lib.put("corners", ds);
    return ds;
}
fn send(session: *reg.Session, cx: proc.ProcCtx, out: *std.ArrayList(u8), source: []const u8) !bool {
    return session.continuation(cx, out, try lex.tokenize(cx.arena, source, cx.diags));
}
fn fitIs(session: reg.Session, index: usize, beta: []const f64, sse: f64, df: usize) !void {
    const f = session.fitted[index].diagnostics.fit;
    try std.testing.expectEqualSlices(f64, beta, f.coefficients);
    try std.testing.expectEqual(sse, f.sse);
    try std.testing.expectEqual(df, f.df_error);
    try std.testing.expectEqual(@as(usize, 4), f.n_used);
}

test "REG-004 DELETE ADD REFIT preserve pool and produce successive PRINT results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=corners;model y=x z;run;", &d)) };
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expect(try send(&session, cx, &out, "refit;"));
    try fitIs(session, 0, &.{ 10, 2, -3 }, 4, 1);
    const full = session.fitted[0].diagnostics.fit.modelStats(true);
    try std.testing.expectEqual(@as(f64, 6.5), full.f_value);
    // F(2,1) survival at 6.5 = 1/sqrt(1+2*6.5).
    try std.testing.expectApproxEqAbs(1 / @sqrt(@as(f64, 14)), full.p_value, 32 * std.math.floatEps(f64));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(try send(&session, cx, &out, "delete z;run;"));
    try fitIs(session, 0, &.{ 10, 2 }, 40, 2);
    const reduced = session.fitted[0].diagnostics.fit.modelStats(true);
    try std.testing.expectEqual(@as(f64, 0.8), reduced.f_value);
    // F(1,2) survival at .8 = 1-sqrt(.8/(.8+2)).
    try std.testing.expectApproxEqAbs(1 - @sqrt(@as(f64, 2.0 / 7.0)), reduced.p_value, 32 * std.math.floatEps(f64));
    try std.testing.expectEqualStrings("MODEL1.1", session.fitted[0].model.label);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(try send(&session, cx, &out, "print;delete x;refit;print;run;"));
    try fitIs(session, 0, &.{10}, 56, 3); // mean-only is a valid boundary model
    const mean_only = session.fitted[0].diagnostics.fit.modelStats(true);
    try std.testing.expectEqual(@as(usize, 0), mean_only.df_model);
    try std.testing.expect(std.math.isNan(mean_only.f_value) and std.math.isNan(mean_only.p_value));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Analysis of Variance"));
    const first = std.mem.indexOf(u8, out.items, "Model: MODEL1.1").?;
    const second = std.mem.indexOf(u8, out.items, "Model: MODEL1.2").?;
    try std.testing.expect(first < second);
    const count = out.items.len;
    try std.testing.expect(try send(&session, cx, &out, "add z x;refit;run;"));
    try fitIs(session, 0, &.{ 10, -3, 2 }, 4, 1);
    try std.testing.expectEqualStrings("MODEL1.3", session.fitted[0].model.label);
    try std.testing.expectEqual(count, out.items.len);
    try std.testing.expect(!try send(&session, cx, &out, "quit;"));
    try std.testing.expect(!d.hasErrors());
}

test "REG-004 targets the last MODEL statement and all its responses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg;old: model y=x;pair: model y v=x z;run;", &d)) };
    var out: std.ArrayList(u8) = .empty;
    _ = try send(&session, cx, &out, "delete z;refit;print;run;");
    try std.testing.expectEqual(@as(usize, 2), session.fitted.len);
    try fitIs(session, 0, &.{ 10, 2 }, 40, 2);
    try fitIs(session, 1, &.{ -4, 0.5 }, 116, 2);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Model: pair.1"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Model: old") == null);
    try std.testing.expect(!d.hasErrors());
}

test "REG-004 invalid ADD is atomic and REFIT cannot silently skip a failed fit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    var session = reg.Session{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg;var z;model y=x;run;", &d)) };
    _ = try send(&session, cx, &out, "refit;");
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, send(&session, cx, &out, "add z spare;"));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), session.revision);
    try std.testing.expectEqualStrings("MODEL1", session.spec.models[0].label);
    try fitIs(session, 0, &.{ 10, 2 }, 40, 2);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    // Exercise the computational failure path directly. REFIT must invoke the
    // same validated fitter as normal execution, not just accept its keyword.
    ds.rows.clearRetainingCapacity();
    try std.testing.expectError(error.ExecError, send(&session, cx, &out, "refit;"));
    try fitIs(session, 0, &.{ 10, 2 }, 40, 2); // last valid fit is not replaced on error
}

test "REG-004 REFIT is silent and PRINT options distinguish gaps from typos" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    const spec = try reg.parse(cx, try lex.tokenize(a, "proc reg outest=est;model y=x z;run;", &d));
    try reg.execute(cx, &out, spec);
    const stored = lib.find("est").?;
    const listed = out.items.len;
    var session = reg.Session{ .spec = spec };
    _ = try send(&session, cx, &out, "refit;run;");
    try std.testing.expectEqual(listed, out.items.len);
    try std.testing.expect(stored == lib.find("est").?);
    // REWEIGHT is implemented: y>10 selects source observations1,3,5,
    // including the already-unusable missing-z row. It must preserve DATA,
    // the last fit and published OUTEST until an explicit output-producing step.
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expect(try send(&session, cx, &out, "reweight y>10;"));
    try std.testing.expectEqualSlices(f64, &.{ 0, 1, 0, 1, 0 }, session.reweight_state.?.current);
    try fitIs(session, 0, &.{ 10, 2, -3 }, 4, 1);
    try std.testing.expectEqual(listed, out.items.len);
    try std.testing.expect(stored == lib.find("est").?);
    try std.testing.expectEqual(@as(usize, 5), spec.ds.rows.items.len);
    try std.testing.expectEqual(@as(f64, 12), spec.ds.rows.items[0][2].num);
    try std.testing.expectEqual(@as(f64, 14), spec.ds.rows.items[2][2].num);
    try std.testing.expectEqual(@as(f64, 1000), spec.ds.rows.items[4][2].num);
    try std.testing.expect(try send(&session, cx, &out, "refit;run;"));
    // The two retained points (-1,4),(1,10) give intercept7, slope3;
    // z=1 is aliased with the intercept and residual DF is zero.
    try std.testing.expectEqualSlices(usize, &.{ 2, 4 }, session.fitted[0].input.source_rows);
    // Small two-point QR rounding does not change the independent(7,3)
    // solution. Budget64 binary64 rounding units; the aliased z remains zero.
    for (session.fitted[0].diagnostics.fit.coefficients[0..2], [_]f64{ 7, 3 }) |actual, expected|
        try std.testing.expectApproxEqAbs(expected, actual, 64 * std.math.floatEps(f64) * @max(1, @abs(expected)));
    try std.testing.expectEqual(@as(f64, 0), session.fitted[0].diagnostics.fit.coefficients[2]);
    try std.testing.expectEqual(@as(usize, 0), session.fitted[0].diagnostics.fit.df_error);
    try std.testing.expectEqual(listed, out.items.len);
    try std.testing.expect(stored == lib.find("est").?);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    for ([_]struct { source: []const u8, gap: bool }{ .{ .source = "refit x;", .gap = false }, .{ .source = "delete;", .gap = false }, .{ .source = "print nonsense;", .gap = false }, .{ .source = "print modeldata;", .gap = true }, .{ .source = "prnt;", .gap = false } }) |check| {
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, send(&session, cx, &out, check.source));
        try std.testing.expectEqual(check.gap, diag.gapHit());
    }
}
