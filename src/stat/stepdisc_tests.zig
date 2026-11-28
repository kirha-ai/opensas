//! STAT-STEPDISC-001 unit tests (see stepdisc.zig). Expected values are the
//! SAS 9.4 reference listing of PROC STEPDISC on SASHELP.FISH (recorded in
//! tests/corpus/stat_stepdisc_fish.txt) or hand arithmetic; nothing here is
//! regenerated from opensas output.
const std = @import("std");
const stepdisc = @import("stepdisc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;

fn plants(a: std.mem.Allocator) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "plants");
    _ = try ds.addColumn("grp", .char);
    for ([_][]const u8{ "x1", "x2", "x3", "f" }) |n| _ = try ds.addColumn(n, .num);
    const rows = [_]struct { []const u8, [3]f64 }{
        .{ "A", .{ 2.1, 3.5, 1.0 } }, .{ "A", .{ 2.5, 3.1, 1.4 } }, .{ "A", .{ 1.9, 3.9, 0.8 } }, .{ "A", .{ 2.8, 3.3, 1.9 } },
        .{ "B", .{ 3.9, 2.2, 2.5 } }, .{ "B", .{ 4.4, 2.0, 2.9 } }, .{ "B", .{ 3.6, 2.9, 2.1 } }, .{ "B", .{ 4.1, 2.4, 3.3 } },
        .{ "C", .{ 5.2, 4.1, 1.2 } }, .{ "C", .{ 5.9, 4.6, 0.7 } }, .{ "C", .{ 6.3, 3.8, 1.6 } }, .{ "C", .{ 5.5, 4.9, 1.1 } },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1][0] }, .{ .num = r[1][1] }, .{ .num = r[1][2] }, .{ .num = 1 } });
    return ds;
}

fn setup(a: std.mem.Allocator, d: *diag.Diagnostics, lib: *Library) !proc.ProcCtx {
    try lib.put("plants", try plants(a));
    return .{ .arena = a, .lib = lib, .diags = d };
}

test "STAT-STEPDISC-001 options: defaults, explicit settings and range checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const cx = try setup(a, &d, &lib);
    const def = try stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants; class grp; var x1 x2; run;", &d));
    try std.testing.expectEqual(@as(f64, 0.15), def.slentry);
    try std.testing.expectEqual(@as(f64, 0.15), def.slstay);
    try std.testing.expectEqual(@as(f64, 1e-8), def.singular);
    try std.testing.expectEqual(@as(usize, 2), def.base.vars.len);
    const set = try stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants sle=0.05 slstay=0.1 method=sw singular=1e-6 maxstep=3; class grp; run;", &d));
    try std.testing.expectEqual(@as(f64, 0.05), set.slentry);
    try std.testing.expectEqual(@as(f64, 0.1), set.slstay);
    try std.testing.expectEqual(@as(f64, 1e-6), set.singular);
    try std.testing.expectEqual(@as(usize, 3), set.maxstep.?);
    // Either significance level alone sets both (SAS 9.4 reference); SHORT.
    const sle = try stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants sle=0.05 short; class grp; run;", &d));
    try std.testing.expectEqual(@as(f64, 0.05), sle.slstay);
    try std.testing.expect(sle.short);
    const sls = try stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants sls=0.3; class grp; run;", &d));
    try std.testing.expectEqual(@as(f64, 0.3), sls.slentry);
    // Without VAR: every numeric variable not in another role (FREQ f excluded).
    const roles = try stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants; class grp; freq f; run;", &d));
    try std.testing.expectEqual(@as(usize, 3), roles.base.vars.len);
    try std.testing.expect(!d.hasErrors());
    diag.resetGap();
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants slentry=1.5; class grp; run;", &d)));
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants singular=0; class grp; run;", &d)));
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants method=lasso; class grp; run;", &d)));
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants ncan=2; class grp; run;", &d)));
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants; var x1; run;", &d)));
    try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, "proc stepdisc data=plants; class grp; freq grp; run;", &d)));
    try std.testing.expect(d.hasErrors());
    // User errors are rc 1, not gaps.
    try std.testing.expect(!diag.gapHit());
}

test "STAT-STEPDISC-001 documented options owned by later tickets are loud gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const cx = try setup(a, &d, &lib);
    const srcs = [_][]const u8{
        "proc stepdisc data=plants method=forward; class grp; run;",
        "proc stepdisc data=plants method=bw; class grp; run;",
        "proc stepdisc data=plants include=1; class grp; run;",
        "proc stepdisc data=plants start=1; class grp; run;",
        "proc stepdisc data=plants maxmacro=5; class grp; run;",
        "proc stepdisc data=plants pr2entry=0.2; class grp; run;",
        "proc stepdisc data=plants simple; class grp; run;",
    };
    for (srcs) |src| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, stepdisc.parse(cx, try lex.tokenize(a, src, &d)));
        try std.testing.expect(diag.gapHit());
    }
}

test "STAT-STEPDISC-001 partial F, tolerance and Wilks match hand arithmetic" {
    // Two variables, three classes. E and T chosen by hand: with an empty
    // model R2_x = 1 - E_xx/T_xx; Wilks for {0,1} = det(E)/det(T).
    const e = [_]f64{ 4, 1, 1, 2 };
    const t = [_]f64{ 10, 3, 3, 5 };
    const c: stepdisc.Ctx = .{ .e = &e, .t = &t, .p = 2, .q = 2, .dfe = 20 };
    const p0 = c.partial(&.{}, 0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), p0.rsq, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), p0.f, 1e-9);
    // Given x0: E_11.0 = 2 - 1/4 = 1.75, T_11.0 = 5 - 9/10 = 4.1.
    const p1 = c.partial(&.{0}, 1);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 - 1.75 / 4.1), p1.rsq, 1e-12);
    // Tolerance from the total-sample SSCP (as the SAS listing): 4.1 / 5.
    try std.testing.expectApproxEqAbs(@as(f64, 4.1 / 5.0), c.tolerance(&.{0}, 1), 1e-12);
    const m = c.multi(&.{ 0, 1 });
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 41.0), m.wilks, 1e-12);
    // Pillai: tr((T-E) T^-1) = 2 - tr(E T^-1); T^-1 = [5 -3; -3 10]/41.
    const tr_et: f64 = (4.0 * 5 - 1 * 3 - 1 * 3 + 2 * 10) / 41.0;
    try std.testing.expectApproxEqAbs(@as(f64, 2 - tr_et), m.pillai, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, (2 - tr_et) / 2), m.ascc, 1e-12);
}

test "STAT-STEPDISC-001 selection: entry by partial F, stop at SLENTRY, removal of the just-entered variable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = [_]f64{ 4, 1, 1, 2 };
    const t = [_]f64{ 10, 3, 3, 5 };
    const c: stepdisc.Ctx = .{ .e = &e, .t = &t, .p = 2, .q = 2, .dfe = 20 };
    // x0 and x1 tie at R2 = 0.6 (4/10 and 2/5): the first in VAR order
    // enters, then x1 given x0, and no candidate remains.
    const sel = try stepdisc.select(a, c, .{ .base = undefined });
    try std.testing.expectEqual(@as(usize, 3), sel.steps.len);
    try std.testing.expectEqual(@as(?usize, 0), sel.steps[0].entered);
    try std.testing.expectEqual(@as(?usize, 1), sel.steps[1].entered);
    try std.testing.expect(sel.steps[2].entry == null);
    // SLENTRY=0: nothing enters.
    const none = try stepdisc.select(a, c, .{ .base = undefined, .slentry = 0, .slstay = 0 });
    try std.testing.expectEqual(@as(usize, 1), none.steps.len);
    try std.testing.expect(none.steps[0].entered == null);
    // SLENTRY=1, SLSTAY=0: x0 enters, is removed at step 2, and SAS stops.
    const rm = try stepdisc.select(a, c, .{ .base = undefined, .slentry = 1, .slstay = 0 });
    try std.testing.expectEqual(@as(usize, 2), rm.steps.len);
    try std.testing.expectEqual(@as(?usize, 0), rm.steps[1].removed);
    try std.testing.expectEqual(@as(usize, 0), rm.steps[1].set.len);
    // MAXSTEP=1 stops before the selection ends: a gap in run().
    try std.testing.expectError(error.MaxStep, stepdisc.select(a, c, .{ .base = undefined, .maxstep = 1 }));
}
