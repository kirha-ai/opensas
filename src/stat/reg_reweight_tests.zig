//! REG011 uses real weighted fits, immutable DATA and stale-fit selector checks.
const std = @import("std");
const reg = @import("reg.zig");
const rw = @import("reg_reweight.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const proc = @import("../proc.zig");
const A = std.mem.Allocator;
fn close(w: f64, g: f64) !void {
    try std.testing.expectApproxEqAbs(w, g, 1e-12 * @max(1, @abs(w)));
}
fn setup(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y", "basew", "freq" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("tag", .char);
    for ([_]f64{ 1, 2, 2, 4, 8 }, [_][]const u8{ "A ", "a", "B", "B", "C" }, 0..) |y, tag, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y }, .{ .num = if (i == 1) 2 else 1 }, .{ .num = 2 }, .{ .str = tag } });
    try lib.put("sample", ds);
}
fn init(cx: proc.ProcCtx, source: []const u8) !reg.Session {
    return .{ .spec = try reg.parse(cx, try lex.tokenize(cx.arena, source, cx.diags)) };
}
fn call(s: *reg.Session, cx: proc.ProcCtx, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    _ = try s.continuation(cx, &out, try lex.tokenize(cx.arena, source, cx.diags));
    return out.items;
}
fn expectWeights(s: reg.Session, expected: []const f64) !void {
    try std.testing.expectEqualSlices(f64, expected, s.reweight_state.?.current);
}

test "REG011 zero weights exclude analysis rows without DATA mutation and REFIT is silent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try init(cx, "proc reg data=sample; model y=x; run;");
    try std.testing.expectEqual(@as(usize, 0), (try call(&s, cx, "reweight obs. le 1 / weight=1 nolist;")).len);
    // Independent all-row line: beta=(1/5,8/5), SSE=28/5, residual DF3.
    try close(0.2, s.fitted[0].diagnostics.fit.coefficients[0]);
    try close(1.6, s.fitted[0].diagnostics.fit.coefficients[1]);
    try close(5.6, s.fitted[0].diagnostics.fit.sse);
    _ = try call(&s, cx, "reweight obs.=5 / nolist;");
    try expectWeights(s, &.{ 1, 1, 1, 1, 0 });
    try close(0.2, s.fitted[0].diagnostics.fit.coefficients[0]);
    try std.testing.expectEqual(@as(usize, 0), (try call(&s, cx, "refit; run;")).len);
    // Remaining four rows give beta=(0.9,0.9), SSE=0.7, DF2.
    try close(0.9, s.fitted[0].diagnostics.fit.coefficients[0]);
    try close(0.9, s.fitted[0].diagnostics.fit.coefficients[1]);
    try close(0.7, s.fitted[0].diagnostics.fit.sse);
    try std.testing.expectEqual(@as(usize, 2), s.fitted[0].diagnostics.fit.df_error);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3, 4 }, s.fitted[0].input.source_rows);
    try std.testing.expectEqual(@as(usize, 5), lib.find("sample").?.rows.items.len);
    try close(8, lib.find("sample").?.rows.items[4][1].num);
    _ = try call(&s, cx, "reweight allobs / reset; refit;");
    try expectWeights(s, &.{ 1, 1, 1, 1, 1 });
    try close(0.2, s.fitted[0].diagnostics.fit.coefficients[0]);
    try close(5.6, s.fitted[0].diagnostics.fit.sse);
    try std.testing.expectEqualStrings("MODEL1.3", s.spec.models[0].label);
}

test "REG011 diagnostic conditions stay on the last fit until REFIT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var frozen = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&frozen, cx, "reweight obs.=5 / nolist; reweight r. lt -1.2 / weight=0.5 nolist;");
    // Original residual at row3=-1.4; deleting row5 must not recompute it.
    try expectWeights(frozen, &.{ 1, 1, 0.5, 1, 0 });
    var refreshed = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&refreshed, cx, "reweight obs.=5 / nolist; refit; reweight r. lt -1.2 / weight=0.5 nolist;");
    // Refitted row3 residual=-0.7, so it no longer satisfies the condition.
    try expectWeights(refreshed, &.{ 1, 1, 1, 1, 0 });
}

test "REG011 option-only selection reuse differs from recomputation and UNDO restores the last change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&s, cx, "reweight r.<0 / weight=0.1 nolist; refit;");
    try expectWeights(s, &.{ 1, 1, 0.1, 0.1, 1 });
    // After refit row2 is now negative too; option-only reuse must not select it.
    try std.testing.expect(2 - s.fitted[0].diagnostics.fit.coefficients[0] - s.fitted[0].diagnostics.fit.coefficients[1] < 0);
    _ = try call(&s, cx, "reweight / weight=0.25 nolist;");
    try expectWeights(s, &.{ 1, 1, 0.25, 0.25, 1 });
    _ = try call(&s, cx, "reweight undo;");
    try expectWeights(s, &.{ 1, 1, 0.1, 0.1, 1 });
    try std.testing.expectEqualStrings("MODEL1.3", s.spec.models[0].label);
    _ = try call(&s, cx, "reweight allobs / reset; refit;");
    try close(0.2, s.fitted[0].diagnostics.fit.coefficients[0]);
}

test "REG011 character conditions are case sensitive and precision weights are absolute" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&s, cx, "reweight tag='A' / weight=0.5 nolist;");
    try expectWeights(s, &.{ 0.5, 1, 1, 1, 1 });
    _ = try call(&s, cx, "reweight allobs / reset; reweight obs. ge 2 and obs. le 4 / weight=0.5 nolist;");
    try expectWeights(s, &.{ 1, 0.5, 0.5, 0.5, 1 });
    var weighted = try init(cx, "proc reg data=sample; model y=x; weight basew; run;");
    _ = try call(&weighted, cx, "reweight obs.=2 / weight=0.25 nolist;");
    try expectWeights(weighted, &.{ 1, 0.25, 1, 1, 1 });
    _ = try call(&weighted, cx, "reweight / reset;");
    try expectWeights(weighted, &.{ 1, 2, 1, 1, 1 });
    try close(2, lib.find("sample").?.rows.items[1][2].num);
    var half = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&half, cx, "reweight obs.=5 / weight=0.5 nolist; refit;");
    try close(0.4, half.fitted[0].diagnostics.fit.coefficients[0]);
    try close(1.4, half.fitted[0].diagnostics.fit.coefficients[1]);
    try close(4.2, half.fitted[0].diagnostics.fit.sse);
}

test "REG011 statistical selectors use actual studentized influence and unit-leverage missing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "reweight student.>1.5 / nolist;", "reweight rstudent.>3 / nolist;", "reweight cookd.>1 / nolist;" }) |source| {
        var s = try init(cx, "proc reg data=sample; model y=x; run;");
        _ = try call(&s, cx, source);
        try expectWeights(s, &.{ 1, 1, 1, 1, 0 });
    }
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "leverage");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 5 } });
    try lib.put("leverage", ds);
    var s = try init(cx, "proc reg data=leverage; model y=x; run;");
    _ = try call(&s, cx, "reweight student.>0.5 / nolist;");
    try expectWeights(s, &.{ 1, 0, 1 });
    // Numeric missing compares below ordinary numbers in SAS, not as false NaN.
    var missing = try init(cx, "proc reg data=leverage; model y=x; run;");
    _ = try call(&missing, cx, "reweight student.<0 / nolist;");
    try expectWeights(missing, &.{ 0, 1, 0 });
}

test "REG011 preserves other MODEL output and REFIT never publishes OUTEST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=sample outest=est noprint; first: model y=x; second: model y=x; run;", &d));
    var original_listing: std.ArrayList(u8) = .empty;
    try reg.execute(cx, &original_listing, spec);
    const old = lib.find("est").?;
    var s = reg.Session{ .spec = spec };
    _ = try call(&s, cx, "reweight obs.=5 / nolist; refit;");
    try std.testing.expect(lib.find("est").? == old);
    try std.testing.expectEqual(@as(usize, 2), old.rows.items.len);
    try std.testing.expectEqualStrings("first", spec.models[0].label);
    try std.testing.expectEqualStrings("second", spec.models[1].label);
    try std.testing.expectEqualStrings("second.1", s.spec.models[0].label);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, call(&s, cx, "print;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expect(lib.find("est").? == old);
}

test "REG011 compound diagnostic conditions are evaluated within each response then unioned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "responses");
    for ([_][]const u8{ "x", "y", "yb" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 2, 4, 8 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = y }, .{ .num = -y } });
    try lib.put("responses", ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var unioned = try init(cx, "proc reg data=responses; model y yb=x; run;");
    _ = try call(&unioned, cx, "reweight r.>1 / nolist;");
    try expectWeights(unioned, &.{ 1, 1, 0, 1, 0 });
    var paired = try init(cx, "proc reg data=responses; model y yb=x; run;");
    _ = try call(&paired, cx, "reweight r.>1 and p.>0 / nolist;");
    try expectWeights(paired, &.{ 1, 1, 1, 1, 0 });
}

test "REG011 frequency replication keeps separate sample size and guards unsupported influence semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try init(cx, "proc reg data=sample; model y=x; freq freq; run;");
    _ = try call(&s, cx, "reweight obs.=5 / nolist; refit;");
    try close(0.9, s.fitted[0].diagnostics.fit.coefficients[0]);
    try close(1.4, s.fitted[0].diagnostics.fit.sse);
    try std.testing.expectEqual(@as(usize, 6), s.fitted[0].diagnostics.fit.df_error);
    try std.testing.expectEqual(@as(usize, 8), s.fitted[0].diagnostics.fit.n_used);
    const before = s.reweight_state.?.current;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, call(&s, cx, "reweight student.>2;"));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqualSlices(f64, before, s.reweight_state.?.current);
}

test "REG011 STATUS preserves weights and snapshots while invalid commands preserve revision" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try setup(a, &lib);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try init(cx, "proc reg data=sample; model y=x; run;");
    _ = try call(&s, cx, "reweight obs.=2 / weight=0.5 nolist;");
    const revision = s.revision;
    const fit = s.fitted[0].diagnostics.fit.coefficients;
    _ = try call(&s, cx, "reweight status;");
    try std.testing.expectEqual(revision + 1, s.revision);
    try std.testing.expectEqualSlices(f64, fit, s.fitted[0].diagnostics.fit.coefficients);
    try std.testing.expect(std.mem.eql(u8, d.list.items[d.list.items.len - 2].message, "Observation 2 has weight 0.5."));
    for ([_][]const u8{ "reweight obs.<=1 / weight=-1;", "reweight tag='123456789';", "reweight x='A';", "reweight typo.>2;", "reweight status / reset;", "reweight allobs /;", "reweight obs.>1 and obs.<5 or obs.=2;" }) |source| {
        var errors = diag.Diagnostics.init(a);
        const badcx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, call(&s, badcx, source));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), errors.hasErrors()));
        try std.testing.expectEqual(revision + 1, s.revision);
        try expectWeights(s, &.{ 1, 0.5, 1, 1, 1 });
    }
    _ = try call(&s, cx, "reweight allobs / nolist;");
    try expectWeights(s, &.{ 0, 0, 0, 0, 0 });
    try std.testing.expectError(error.ExecError, call(&s, cx, "refit;"));
    _ = try call(&s, cx, "reweight allobs / reset; refit;");
    try close(0.2, s.fitted[0].diagnostics.fit.coefficients[0]);
    try std.testing.expectEqual(@as(usize, 5), lib.find("sample").?.rows.items.len);
}
