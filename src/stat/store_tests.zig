//! Permanent COMMON030 proof: invented original 12-row example is retained
//! inline; no temporary oracle read occurs. Source: S154 physical543–545.
//! For X=(1, g, x), g=+1 for A and -1 for B, exact normal equations are
//! X'X=[[12,0,78],[0,12,-36],[78,-36,650]], X'y=[179,-77,1454].
//! Rational elimination gives beta=(58/15,-79/60,17/10), SSE=581/60,
//! MSE=581/540. The covariance fractions below are MSE*(X'X)^-1.
//! Error bounds are 4096 binary64 eps times the exact quantity's scale; the
//! original normal matrix has kappa_inf=764*(427/210)<1600. The fixed
//! 4096-epsilon budget exceeds twice that amplification; exact rational targets
//! and covariance structure require no SAS rounding golden.
const std = @import("std");
const t = std.testing;
const store = @import("store.zig");
const glm = @import("glm.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
fn close(expected: f64, actual: f64) !void {
    try t.expectApproxEqAbs(expected, actual, 4096 * std.math.floatEps(f64) * @max(1, @abs(expected)));
}
fn sample(a: std.mem.Allocator) !Dataset {
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("y", .num);
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    for (y, 0..) |v, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .str = if (i < 6) "A" else "B" }, .{ .num = v } });
    return ds;
}
fn run(cx: proc.ProcCtx, source: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    try glm.run(cx, &out, try lex.tokenize(cx.arena, source, cx.diags));
}
fn fitted(cx: proc.ProcCtx) !store.Model {
    try run(cx, "proc glm data=sample noprint; class group; model y=group x; store fitted / label='A stored fit'; run;");
    return store.restore(cx, "WORK.FITTED");
}

test "STAT-COMMON-030 GLM permanent file restores in a new session with independent covariance and predictions" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(dir);
    const refs = [_]@import("../dsfns.zig").Libref{.{ .name = "saved", .dir = dir }};
    @import("../dsfns.zig").bindLibrefs(&refs);
    defer @import("../dsfns.zig").bindLibrefs(&.{});
    // End the entire fitting arena/Library lifetime before restore. There is no
    // training data, retained fit pointer or global model cache in session two.
    {
        var first = std.heap.ArenaAllocator.init(t.allocator);
        defer first.deinit();
        const a = first.allocator();
        var ds = try sample(a);
        var lib = Library.init(a);
        try lib.put("sample", &ds);
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try run(cx, "proc glm data=sample noprint; class group; model y=group x; store out=saved.fitted / label='Independent sessions'; run;");
        try t.expectEqual(@as(usize, 0), lib.item_stores.count());
        try t.expect(!d.hasErrors());
    }
    var second = std.heap.ArenaAllocator.init(t.allocator);
    defer second.deinit();
    const a = second.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const m = try store.restore(cx, "SAVED.FITTED");
    try t.expectEqual(@as(usize, 0), lib.sets.items.len);
    try t.expectEqualStrings("GLM", m.procedure);
    try t.expectEqualStrings("sample", m.input);
    try t.expectEqualStrings("y", m.response);
    try t.expectEqualStrings("Independent sessions", m.label);
    try t.expect(m.created_unix_seconds > 0);
    try t.expect(m.intercept);
    try t.expectEqual(@as(usize, 2), m.effects.len);
    try t.expectEqualStrings("group", m.effects[0].name);
    try t.expectEqual(@as(usize, 1), m.effects[0].start);
    try t.expectEqual(@as(usize, 1), m.effects[0].len);
    try t.expectEqual(@as(?usize, 0), m.effects[0].factors[0].class_index);
    try t.expectEqualStrings("x", m.effects[1].name);
    try t.expectEqual(@as(usize, 2), m.effects[1].start);
    try t.expectEqual(@as(usize, 1), m.classes.len);
    try t.expectEqualStrings("group", m.classes[0].name);
    try t.expectEqualStrings("A", m.classes[0].levels[0].text.?);
    try t.expectEqualStrings("B", m.classes[0].levels[1].label);
    try t.expectEqual(@as(usize, 1), m.covariates.len);
    try close(6.5, m.covariates[0].mean);
    try t.expectEqual(@as(usize, 9), m.df_error);
    try t.expectEqual(@as(usize, 12), m.n_used);
    try close(581.0 / 540.0, m.mse);
    for ([_]f64{ 58.0 / 15.0, -79.0 / 60.0, 17.0 / 10.0 }, m.coefficients) |expected, actual| try close(expected, actual);
    for ([_]f64{ 22493.0 / 16200.0, -1079.0 / 1800.0, -1079.0 / 5400.0, -1079.0 / 1800.0, 11869.0 / 32400.0, 83.0 / 900.0, -1079.0 / 5400.0, 83.0 / 900.0, 83.0 / 2700.0 }, m.covariance) |expected, actual| try close(expected, actual);
    // A fresh scoring table deliberately reverses predictor order and contains
    // no response. All 12 original predictions are checked plus extrapolation.
    var score = Dataset.init(a, "incoming");
    _ = try score.addColumn("GROUP", .char);
    _ = try score.addColumn("X", .num);
    for (0..13) |i| {
        const x: f64 = @floatFromInt(i + 1);
        const cells = [_]Value{ .{ .str = if (i < 6) "A " else "B" }, .{ .num = x } };
        const row = (try store.row(a, m, &score, &cells)).?;
        const pred = try store.evaluate(m, row);
        try close((if (i < 6) @as(f64, 51.0 / 20.0) else 311.0 / 60.0) + 1.7 * x, pred.estimate);
    }
    const lsa = try store.evaluate(m, &.{ 1, 1, 6.5 });
    const lsb = try store.evaluate(m, &.{ 1, -1, 6.5 });
    const diff = try store.evaluate(m, &.{ 0, 2, 0 });
    try close(13.6, lsa.estimate);
    try close(487.0 / 30.0, lsb.estimate);
    try close(7387.0 / 16200.0, lsa.variance);
    try close(lsa.variance, lsb.variance);
    try close(-79.0 / 30.0, diff.estimate);
    try close(11869.0 / 8100.0, diff.variance);
    try t.expect((try store.row(a, m, &score, &.{ .{ .str = "C" }, .{ .num = 1 } })) == null);
    try t.expect((try store.row(a, m, &score, &.{ .{ .str = "A" }, Value.missing })) == null);
    try t.expectError(error.InvalidFunction, store.evaluate(m, &.{1}));
}

test "STAT-COMMON-030 WORK lifecycle replacement names and separate DATA namespace" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    try lib.put("fitted", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const m = try fitted(cx);
    try t.expectEqualStrings("A stored fit", m.label);
    try t.expectEqual(&ds, lib.find("fitted").?);
    try t.expectEqualStrings("WORK.FITTED", lib.macroVar("syslast").?);
    try run(cx, "proc glm data=sample noprint; model y=x; store WORK.FITTED / label='replacement'; run;");
    const replaced = try store.restore(cx, "fitted");
    try t.expectEqualStrings("replacement", replaced.label);
    try t.expectEqual(@as(usize, 0), replaced.classes.len);
    try t.expectEqual(@as(usize, 1), lib.item_stores.count());
    var fresh = Library.init(a);
    var fresh_d = diag.Diagnostics.init(a);
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ExecError, store.restore(.{ .arena = a, .lib = &fresh, .diags = &fresh_d }, "fitted"));
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), fresh_d.hasErrors()));
}

test "STAT-COMMON-030 version incompatible and corrupt native stores report captured severity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const m = try fitted(cx);
    const bytes = try store.encode(a, m);
    const bad_version = try a.dupe(u8, bytes);
    bad_version[17] = 2;
    const bad_magic = try a.dupe(u8, bytes);
    bad_magic[0] = 'S';
    const bad_hash = try a.dupe(u8, bytes);
    bad_hash[bad_hash.len - 1] ^= 1;
    const bad_length = try a.dupe(u8, bytes);
    bad_length[21] ^= 1;
    for ([_][]const u8{ bad_version, bad_magic, bad_hash, bad_length, bytes[0..20] }, [_]u8{ 2, 2, 1, 1, 1 }, [_][]const u8{ "VersionMismatch", "IncompatibleStore", "corrupt", "corrupt", "corrupt" }) |bad, rc, message| {
        try lib.item_stores.put(a, "work.bad", bad);
        var reporter = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(if (rc == 2) error.ParseError else error.ExecError, store.restore(.{ .arena = a, .lib = &lib, .diags = &reporter }, "bad"));
        try t.expectEqual(rc, diag.exitCode(diag.gapHit(), reporter.hasErrors()));
        try t.expect(std.mem.indexOf(u8, reporter.list.items[0].message, message) != null);
    }
    var invalid = m;
    invalid.coding = "unknown-basis";
    try t.expectError(error.IncompatibleModel, store.encode(a, invalid));
    invalid = m;
    invalid.covariance = &.{1};
    try t.expectError(error.CorruptStore, store.encode(a, invalid));
    invalid = m;
    invalid.df_error = std.math.maxInt(usize);
    try t.expectError(error.CorruptStore, store.encode(a, invalid));
    invalid = m;
    invalid.df_error = 0;
    try t.expectError(error.CorruptStore, store.encode(a, invalid));
    // Recompute the checksum on a structurally invalid payload to exercise the
    // schema validator independently of envelope integrity checks.
    const altered = try a.dupe(u8, bytes);
    const marker = "\"df_error\":9";
    const at = std.mem.indexOf(u8, altered, marker).?;
    altered[at + marker.len - 1] = '0';
    std.crypto.hash.sha2.Sha256.hash(altered[61..], altered[29..61], .{});
    try t.expectError(error.CorruptStore, store.decode(a, altered));
}

test "STAT-COMMON-030 syntax read-only unassigned and unsupported producer contexts stay loud" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    for ([_][]const u8{ "", "out=", "a.b.c", "out='path'", "f / label=2", "f / label='x' extra", "f / unknown='x'" }) |source| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const tokens = try lex.tokenize(a, source, &d);
        try t.expectError(error.ParseError, store.parse(cx, tokens[0 .. tokens.len - 1]));
        try t.expect(d.hasErrors());
    }
    for ([_][]const u8{
        "proc glm data=sample noprint; class group; model y=group x; store nowhere.f; run;",
        "proc glm data=sample noprint; class group; model y=group x; store ro.f; run;",
        "proc glm data=sample noprint; class group; model y=group x; store a; store b; run;",
        "proc glm data=sample noprint; class group; model y=group x; random group; store a; run;",
        "proc glm data=sample noprint; class group; model y=group x; by group; store a; run;",
    }, [_]u8{ 1, 1, 2, 2, 2 }) |source, rc| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        lib.readonly_refs = &.{"ro"};
        diag.resetGap();
        defer diag.resetGap();
        _ = run(cx, source) catch {};
        try t.expect(d.hasErrors());
        try t.expectEqual(rc, diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqual(@as(usize, 0), lib.item_stores.count());
    }
}

// Balanced 2x2 invented factorial, three observations per cell with errors
// (-1,0,1): X'X=12I, beta=(10,2,-3,4), SSE=8, DF=8, Cov(beta)=I/12.
// Numeric CLASS identities and punctuation in character levels survive the
// payload. The interaction must use both saved factors in the original order.
test "STAT-COMMON-030 restored interaction basis numeric and quoted CLASS levels" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "cells");
    _ = try ds.addColumn("A", .num);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    for (0..2) |i| for (0..2) |j| {
        const ga: f64 = if (i == 0) 1 else -1;
        const gb: f64 = if (j == 0) 1 else -1;
        for ([_]f64{ -1, 0, 1 }) |e| try ds.appendRow(&.{ .{ .num = if (i == 0) 10 else 20 }, .{ .str = if (j == 0) "O'Brien" else "z" }, .{ .num = 10 + 2 * ga - 3 * gb + 4 * ga * gb + e } });
    };
    var lib = Library.init(a);
    try lib.put("cells", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, "proc glm data=cells noprint; class A B; model y=A B A*B; store cross; run;");
    const m = try store.restore(cx, "cross");
    try t.expectEqual(@as(usize, 2), m.classes.len);
    try t.expectEqual(@as(f64, 10), m.classes[0].levels[0].number.?);
    try t.expectEqual(@as(f64, 20), m.classes[0].levels[1].number.?);
    try t.expectEqualStrings("O'Brien", m.classes[1].levels[0].text.?);
    try t.expectEqual(@as(usize, 2), m.effects[2].factors.len);
    for ([_]f64{ 10, 2, -3, 4 }, m.coefficients) |expected, actual| try close(expected, actual);
    for (m.covariance, 0..) |value, i| try close(if (i / 4 == i % 4) 1.0 / 12.0 else 0, value);
    for (ds.rows.items, 0..) |cells, i| {
        const prediction = try store.evaluate(m, (try store.row(a, m, &ds, cells)).?);
        try close(cells[2].num - @as(f64, @floatFromInt(i % 3)) + 1, prediction.estimate);
        try close(1.0 / 3.0, prediction.variance);
    }
    try t.expectError(error.VariableTypeMismatch, store.row(a, m, &ds, &.{ .{ .str = "10" }, .{ .str = "z" }, .{ .num = 0 } }));
    try t.expectError(error.InvalidRow, store.row(a, m, &ds, &.{.{ .num = 10 }}));
}

test "STAT-COMMON-030 stored polynomial factors and single-level CLASS missing semantics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "curve");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ -2, -1, 0, 1, 2 }) |x| for ([_]f64{ -1, 1 }) |e| try ds.appendRow(&.{ .{ .num = x }, .{ .str = "only" }, .{ .num = 3 + 2 * x + 0.5 * x * x + e } });
    var lib = Library.init(a);
    try lib.put("curve", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, "proc glm data=curve noprint; class g; model y=g x x*x; store curvefit; run;");
    const m = try store.restore(cx, "curvefit");
    try t.expectEqual(@as(usize, 0), m.effects[0].len);
    try t.expectEqual(@as(usize, 2), m.effects[2].factors.len);
    for ([_]f64{ 3, 2, 0.5 }, m.coefficients) |expected, actual| try close(expected, actual);
    try close(10.0 / 7.0, m.mse);
    try close(13.5, (try store.evaluate(m, (try store.row(a, m, &ds, &.{ .{ .num = 3 }, .{ .str = "only" }, Value.missing })).?)).estimate);
    try t.expect((try store.row(a, m, &ds, &.{ .{ .num = 3 }, .{ .str = "other" }, Value.missing })) == null);
    try t.expect((try store.row(a, m, &ds, &.{ .{ .num = 3 }, .{ .str = " " }, Value.missing })) == null);
}

test "STAT-COMMON-030 permanent replacement and failed writes retain prior valid state" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(dir);
    const refs = [_]@import("../dsfns.zig").Libref{.{ .name = "saved", .dir = dir }};
    @import("../dsfns.zig").bindLibrefs(&refs);
    defer @import("../dsfns.zig").bindLibrefs(&.{});
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var m = try fitted(cx);
    const request: store.Request = .{ .name = "saved.fitted" };
    try store.save(cx, request, m);
    m.label = "replacement on disk";
    try store.save(cx, request, m);
    try t.expectEqualStrings(m.label, (try store.restore(cx, "saved.fitted")).label);
    const original = try tmp.dir.readFileAlloc(t.io, "fitted.opensasitem", a, .limited(1 << 20));
    m.covariance = &.{1};
    try t.expectError(error.ExecError, store.save(cx, request, m));
    const after = try tmp.dir.readFileAlloc(t.io, "fitted.opensasitem", a, .limited(1 << 20));
    try t.expectEqualSlices(u8, original, after);
    for (0..original.len) |n| try t.expectError(error.CorruptStore, store.decode(a, original[0..n]));
    const excess = try std.mem.concat(a, u8, &.{ original, "x" });
    try t.expectError(error.CorruptStore, store.decode(a, excess));
}

// One slope without an intercept. Frequency replicates (2,1,3), precision
// weights (1,2,1): X'WX=37, X'Wy=69, SSE=160/37, DF=6-1, MSE=32/37.
test "STAT-COMMON-030 NOINT frequency and precision weights survive restoration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "weighted");
    for ([_][]const u8{ "x", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 2, 2, 1 }, .{ 2, 5, 1, 2 }, .{ 3, 5, 3, 1 } }) |numbers| {
        var values: [4]Value = undefined;
        for (&values, numbers) |*v, n| v.* = .{ .num = n };
        try ds.appendRow(&values);
    }
    var lib = Library.init(a);
    try lib.put("weighted", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, "proc glm data=weighted noprint; model y=x / noint; freq f; weight w; store weights; run;");
    const m = try store.restore(cx, "weights");
    try t.expect(!m.intercept);
    try t.expectEqual(@as(usize, 6), m.n_used);
    try t.expectEqual(@as(usize, 5), m.df_error);
    try close(69.0 / 37.0, m.coefficients[0]);
    try close(32.0 / 37.0, m.mse);
    try close(32.0 / 1369.0, m.covariance[0]);
    const prediction = try store.evaluate(m, &.{4});
    try close(276.0 / 37.0, prediction.estimate);
    try close(512.0 / 1369.0, prediction.variance);
}

test "STAT-COMMON-030 unused CLASS declaration does not become a scoring prerequisite" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, "proc glm data=sample noprint; class group; model y=x; store unused; run;");
    const m = try store.restore(cx, "unused");
    var incoming = Dataset.init(a, "incoming");
    _ = try incoming.addColumn("x", .num);
    const x = (try store.row(a, m, &incoming, &.{.{ .num = 2 }})).?;
    try t.expectEqualSlices(f64, &.{ 1, 2 }, x);
}

// Base SAS Procedures Guide physical631–632,651,675: KILL/CHANGE default
// ALL; DELETE defaults DATA. Only the member operations that could touch an
// existing native store are blocked; DATA-only operations still take effect.
test "STAT-COMMON-030 DATASETS guards native WORK management and preserves DATA-only semantics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    _ = try fitted(cx);
    try lib.put("fitted", &ds);
    for ([_][]const u8{
        "proc datasets nolist kill; quit;",
        "proc datasets library=work nolist; change fitted=renamed; quit;",
        "proc datasets nolist; delete fitted / memtype=all; quit;",
        "proc datasets nolist; delete fitted / memtype=itemstor; quit;",
        "proc datasets memtype=itemstor nolist; delete fitted; quit;",
    }) |source| {
        var reporter = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const local: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &reporter };
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, proc.runDatasets(local, &out, try lex.tokenize(a, source, &reporter)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), reporter.hasErrors()));
        try t.expect(lib.find("fitted") != null);
        try t.expectEqual(@as(usize, 1), lib.item_stores.count());
        try t.expect(std.mem.indexOf(u8, reporter.list.items[0].message, "not implemented") != null);
    }
    var out: std.ArrayList(u8) = .empty;
    // Default DELETE removes DATA only even though the native store shares its name.
    try proc.runDatasets(cx, &out, try lex.tokenize(a, "proc datasets nolist; delete fitted; quit;", &d));
    try t.expect(lib.find("fitted") == null);
    _ = try store.restore(cx, "fitted");
    try lib.put("fitted", &ds);
    try proc.runDatasets(cx, &out, try lex.tokenize(a, "proc datasets memtype=data nolist; change fitted=renamed; quit;", &d));
    try t.expect(lib.find("renamed") != null);
    _ = try store.restore(cx, "fitted");
    // A default CHANGE of an unrelated DATA member remains allowed.
    try proc.runDatasets(cx, &out, try lex.tokenize(a, "proc datasets nolist; change renamed=other; quit;", &d));
    try t.expect(lib.find("other") != null);
    try proc.runDatasets(cx, &out, try lex.tokenize(a, "proc datasets memtype=data kill nolist; quit;", &d));
    try t.expectEqual(@as(usize, 0), lib.sets.items.len);
    _ = try store.restore(cx, "fitted");
}

test "STAT-COMMON-030 DATASETS detects native disk stores across sessions without deleting files" {
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(dir);
    const refs = [_]@import("../dsfns.zig").Libref{.{ .name = "saved", .dir = dir }};
    @import("../dsfns.zig").bindLibrefs(&refs);
    defer @import("../dsfns.zig").bindLibrefs(&.{});
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try sample(a);
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const m = try fitted(cx);
    try store.save(cx, .{ .name = "saved.fitted" }, m);
    var fresh = Library.init(a);
    try fresh.put("saved.data", &ds);
    for ([_][]const u8{ "proc datasets library=saved kill nolist; quit;", "proc datasets library=saved nolist; change fitted=other; quit;" }) |source| {
        var reporter = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        defer diag.resetGap();
        try t.expectError(error.ParseError, proc.runDatasets(.{ .arena = a, .lib = &fresh, .diags = &reporter }, &out, try lex.tokenize(a, source, &reporter)));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), reporter.hasErrors()));
        try t.expect(fresh.find("saved.data") != null);
    }
    var out: std.ArrayList(u8) = .empty;
    try proc.runDatasets(.{ .arena = a, .lib = &fresh, .diags = &d }, &out, try lex.tokenize(a, "proc datasets library=saved memtype=data kill nolist; quit;", &d));
    try t.expect(fresh.find("saved.data") == null);
    const restored = try store.restore(.{ .arena = a, .lib = &fresh, .diags = &d }, "saved.fitted");
    try close(m.coefficients[0], restored.coefficients[0]);
}
