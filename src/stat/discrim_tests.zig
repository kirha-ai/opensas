//! STAT-DISCRIM-001 unit tests (see discrim.zig). Expected values are hand
//! mathematics on an invented two-class data set; nothing here is
//! regenerated from opensas output.
const std = @import("std");
const discrim = @import("discrim.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const proc = @import("../proc.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;

/// Two classes, one variable: A = {1, 2, 3}, B = {5, 6, 7, 10}.
fn tiny(a: std.mem.Allocator) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "tiny");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("tag", .num);
    const rows = [_]struct { []const u8, f64 }{ .{ "A", 1 }, .{ "A", 2 }, .{ "A", 3 }, .{ "B", 5 }, .{ "B", 6 }, .{ "B", 7 }, .{ "B", 10 } };
    for (rows, 0..) |r, k| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .num = @floatFromInt(k) } });
    return ds;
}

fn ctx(a: std.mem.Allocator, d: *diag.Diagnostics, lib: *Library) proc.ProcCtx {
    return .{ .arena = a, .lib = lib, .diags = d };
}

test "STAT-DISCRIM-001 pooled covariance, distance, linear function and resubstitution by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try tiny(a);
    const s: discrim.Spec = .{ .ds = ds, .class = 0, .vars = &.{1} };
    const r = try discrim.analyze(a, s, ds.rows.items);
    // Means 2 and 7; within SS = 2 + (4+1+0+9) = 16; DF = 7-2 = 5; COV = 3.2.
    try std.testing.expectApproxEqAbs(@as(f64, @log(3.2)), r.log_det, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.2), r.cov_inv[0], 1e-12);
    // D^2(A|B) = 25 / 3.2 = 7.8125, symmetric, zero diagonal.
    try std.testing.expectApproxEqAbs(@as(f64, 7.8125), r.dist[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.8125), r.dist[2], 1e-12);
    try std.testing.expectEqual(@as(f64, 0), r.dist[0]);
    // Constant -.5 * 4/3.2 = -0.625 (A), -.5*49/3.2 = -7.65625 (B); slope 2/3.2, 7/3.2.
    try std.testing.expectApproxEqAbs(@as(f64, -0.625), r.constant[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -7.65625), r.constant[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.625), r.coef[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.1875), r.coef[1], 1e-12);
    // Midpoint 4.5: every observation is classified into its own class.
    try std.testing.expectEqualSlices(f64, &.{ 3, 0, 0, 4 }, r.classified);
}

test "STAT-DISCRIM-001 FREQ multiplies the classification counts and degrees of freedom" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try tiny(a);
    _ = try ds.addColumn("f", .num);
    for (ds.rows.items) |*row| {
        const values = try a.alloc(@TypeOf(row.*[0]), row.len + 1);
        @memcpy(values[0..row.len], row.*);
        values[row.len] = .{ .num = 2 };
        row.* = values;
    }
    const s: discrim.Spec = .{ .ds = ds, .class = 0, .vars = &.{1}, .freq = 3 };
    const r = try discrim.analyze(a, s, ds.rows.items);
    // Within SS doubles (32), DF = 14 - 2 = 12: COV = 32/12.
    try std.testing.expectApproxEqAbs(@as(f64, @log(32.0 / 12.0)), r.log_det, 1e-12);
    try std.testing.expectEqualSlices(f64, &.{ 6, 0, 0, 8 }, r.classified);
}

test "STAT-DISCRIM-001 roles and options: CLASS required, VAR default, ID excluded, gaps loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try lib.put("tiny", try tiny(a));
    const cx = ctx(a, &d, &lib);
    // Missing CLASS statement: user error (rc 1, no gap).
    diag.resetGap();
    try std.testing.expectError(error.ParseError, discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny; var x; run;", &d)));
    // Character FREQ variable: user error.
    try std.testing.expectError(error.ParseError, discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny; class g; freq g; run;", &d)));
    // Unknown variable: user error.
    try std.testing.expectError(error.ParseError, discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny; class g; var nope; run;", &d)));
    // Without VAR: all numeric variables not named elsewhere (ID excluded).
    const s = try discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny method=normal pool=yes; class g; id tag; priors equal; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), s.vars.len);
    try std.testing.expectEqual(@as(usize, 1), s.vars[0]);
    try std.testing.expectEqual(@as(?usize, 2), s.id);
    try std.testing.expect(!diag.gapHit());
    const all = try discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny; class g; run;", &d));
    try std.testing.expectEqual(@as(usize, 2), all.vars.len);
    // Valid but unimplemented: D-009 gaps, never silent success.
    const gaps = [_][]const u8{
        "proc discrim data=tiny pool=no; class g; run;",
        "proc discrim data=tiny method=npar; class g; run;",
        "proc discrim data=tiny crossvalidate; class g; run;",
        "proc discrim data=tiny out=o; class g; run;",
        "proc discrim data=tiny; class g; priors proportional; run;",
        "proc discrim data=tiny; class g; class g; run;",
        "proc discrim data=tiny; class g; testclass g; run;",
    };
    for (gaps) |src| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, discrim.parse(cx, try lex.tokenize(a, src, &d)));
        try std.testing.expect(diag.gapHit());
    }
    // A misspelled option stays a user error (rc 1), not a gap.
    diag.resetGap();
    try std.testing.expectError(error.ParseError, discrim.parse(cx, try lex.tokenize(a, "proc discrim data=tiny bogus; class g; run;", &d)));
    try std.testing.expect(!diag.gapHit());
    diag.resetGap();
}
