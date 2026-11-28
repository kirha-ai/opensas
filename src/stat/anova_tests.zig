//! STAT-ANOVA-001 and STAT-ANOVA-003 permanent checks: PROC ANOVA declarations, defaults, loud
//! boundaries, BY/FREQ and missing-value rules (S154 physical pp.1115–1119,
//! 1138–1139). All data are invented; every expected number is hand-derived
//! from group means in the comment beside it, never copied from a run.
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const anova = @import("anova.zig");
const glm = @import("glm.zig");
const selection = @import("data_selection.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const M = std.math.nan(f64);

// Sums of squares below are small integers/halves; the bound is the usual
// backward-error envelope for a QR/Cholesky solve on O(10) well-scaled rows.
fn close(expected: f64, actual: f64) !void {
    const ku = 4096 * std.math.floatEps(f64);
    try t.expectApproxEqAbs(expected, actual, 32 * ku / (1 - ku) * @max(1, @abs(expected)));
}
fn table(a: std.mem.Allocator, name: []const u8, comptime names: []const []const u8, rows: []const [names.len]f64) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for (names) |column| _ = try ds.addColumn(column, .num);
    for (rows) |values| {
        var cells: [names.len]Value = undefined;
        for (values, &cells) |v, *cell| cell.* = .{ .num = v };
        try ds.appendRow(&cells);
    }
    return ds;
}
const Env = struct {
    lib: Library,
    diags: diag.Diagnostics,
    fn cx(self: *Env, a: std.mem.Allocator) proc.ProcCtx {
        return .{ .arena = a, .lib = &self.lib, .diags = &self.diags };
    }
};
fn env(a: std.mem.Allocator, ds: *Dataset) !*Env {
    const e = try a.create(Env);
    e.* = .{ .lib = Library.init(a), .diags = diag.Diagnostics.init(a) };
    try e.lib.put(ds.name, ds);
    return e;
}
/// Exit class of a program under the captured reporter: 0 clean, 1 user
/// error, 2 D-009 gap. Never spawns a process.
fn exitOf(a: std.mem.Allocator, ds: *Dataset, text: []const u8) !u8 {
    const e = try env(a, ds);
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    const failed = if (anova.run(e.cx(a), &out, try lex.tokenize(a, text, &e.diags))) |_| false else |_| true;
    const code = diag.exitCode(diag.gapHit(), e.diags.hasErrors());
    if (failed) try t.expect(code != 0);
    return code;
}
fn listing(a: std.mem.Allocator, ds: *Dataset, text: []const u8) ![]const u8 {
    const e = try env(a, ds);
    var out: std.ArrayList(u8) = .empty;
    try anova.run(e.cx(a), &out, try lex.tokenize(a, text, &e.diags));
    try t.expect(!e.diags.hasErrors());
    return out.items;
}
fn has(text: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, text, needle) == null) {
        std.debug.print("missing <{s}> in:\n{s}\n", .{ needle, text });
        return error.TestExpectedEqual;
    }
}
const oneway = [_][2]f64{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 5 }, .{ 2, 7 } };

test "ANOVA001 PROC statement defaults and explicit basic options" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "g", "y" }, &oneway);
    const e = try env(a, ds);
    const cx = e.cx(a);
    const d = try anova.parse(cx, try lex.tokenize(a, "proc anova; class g; model y=g; run;", &e.diags));
    try t.expectEqual(@as(usize, 20), d.namelen);
    try t.expectEqual(glm.parsing.Order.formatted, d.order);
    try t.expect(!d.manova and !d.multipass and !d.noprint and !d.plots_none);
    try t.expect(d.freq == null and d.by.len == 0 and d.weight == null);
    try t.expectEqualSlices(usize, &.{0}, d.classes);
    try t.expectEqualSlices(usize, &.{1}, d.responses);
    const x = try anova.parse(cx, try lex.tokenize(a, "proc anova data=s manova multipass namelen=200 order=data noprint plots=none; class g; model y=g; run;", &e.diags));
    try t.expectEqual(@as(usize, 200), x.namelen);
    try t.expectEqual(glm.parsing.Order.data, x.order);
    try t.expect(x.manova and x.multipass and x.noprint and x.plots_none);
    for ([_][]const u8{ "freq", "internal", "FORMATTED" }) |order| {
        _ = try anova.parse(cx, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc anova order={s} namelen=20; class g; model y=g; run;", .{order}), &e.diags));
    }
    try t.expect(!e.diags.hasErrors());
    // NOPRINT suppresses every table.
    try t.expectEqualStrings("", try listing(a, ds, "proc anova noprint; class g; model y=g; run;"));
}

test "ANOVA001 invalid declarations are user errors, not gaps" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "g", "y", "f" }, &.{ .{ 1, 1, 1 }, .{ 1, 3, 1 }, .{ 2, 5, 1 }, .{ 2, 7, 1 } });
    for ([_][]const u8{
        "proc anova alpha=0.1; class g; model y=g; run;", // GLM-only option
        "proc anova bogus; class g; model y=g; run;",
        "proc anova namelen=19; class g; model y=g; run;",
        "proc anova namelen=201; class g; model y=g; run;",
        "proc anova namelen=abc; class g; model y=g; run;",
        "proc anova order=bogus; class g; model y=g; run;",
        "proc anova data=; class g; model y=g; run;",
        "proc anova data=nosuch; class g; model y=g; run;",
        "proc anova; class g; run;", // MODEL required
        "proc anova; model y=g; class g; run;", // CLASS must precede MODEL
        "proc anova; class g; model y=g; model y=g; run;", // one MODEL only
        "proc anova; class g; model y=g / ss3; run;", // GLM-only MODEL option
        "proc anova; class g; model y=g x; run;", // SAS: No continuous effects allowed
        "proc anova; class g; model y=g; weight f; run;", // no WEIGHT in ANOVA
        "proc anova; class g; model y=g; lsmeans g; run;",
        "proc anova; class g; model y=g; freq f y; run;",
        "proc anova; class g; model y=g; freq; run;",
        "proc anova; class g; model y=g; freq nosuch; run;",
        "proc anova; class nosuch; model y=g; run;",
        "proc anova; class g; model y=g; run; model y=g; run;", // no redeclare after RUN
    }) |text| {
        const code = exitOf(a, ds, text) catch |err| {
            std.debug.print("program: {s}\n", .{text});
            return err;
        };
        if (code != 1) std.debug.print("program: {s}\n", .{text});
        try t.expectEqual(@as(u8, 1), code);
    }
}

test "ANOVA001 valid features owned by later tickets fail loudly as gaps" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "g", "y", "x" }, &.{ .{ 1, 1, 1 }, .{ 1, 3, 2 }, .{ 2, 5, 3 }, .{ 2, 7, 5 } });
    for ([_][]const u8{
        "proc anova outstat=o; class g; model y=g; run;",
        "proc anova plots; class g; model y=g; run;",
        "proc anova plots(maxpoints=none); class g; model y=g; run;",
        // STAT-ANOVA-007 implemented plain MEANS; these MEANS shapes remain gaps.
        "proc anova; class g; model y=g; means g / bon; run;",
        "proc anova; class g; model y=g; means g / tukey; run;",
        "proc anova; class g; model y x=g; manova h=g; run;",
        "proc anova; class g; model y x=g; repeated t 2; run;",
        "proc anova; class g; model y=g; test h=g e=g; run;",
        "proc anova; absorb g; class g; model y=g; run;",
        "proc anova; class g; model y x=g; run; manova h=g; run;", // interactive (MEANS is implemented)
        "proc anova; class g; model y=g / effectsize; run;", // STAT-ANOVA-003 remainder
    }) |text| {
        const code = try exitOf(a, ds, text);
        if (code != 2) std.debug.print("program: {s}\n", .{text});
        try t.expectEqual(@as(u8, 2), code);
    }
}

test "ANOVA001 one-way listing: counts, level order and hand-derived sums of squares" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Unbalanced one-way is valid ANOVA input: g=1 {1,3}, g=2 {5,7,9}.
    // Means 2 and 7, grand mean 5: SSB = 2*9 + 3*4 = 30, SSE = 2 + 8 = 10,
    // F = 30 / (10/3) = 9.00.
    const ds = try table(a, "s", &.{ "g", "y" }, &.{ .{ 2, 5 }, .{ 1, 1 }, .{ 2, 7 }, .{ 1, 3 }, .{ 2, 9 } });
    const text = try listing(a, ds, "proc anova; class g; model y=g; run;");
    try has(text, "\nThe ANOVA Procedure\n\nClass Level Information\n\nClass Levels Values\n\ng 2 1 2\n\nNumber of Observations Read 5\nNumber of Observations Used 5\n");
    try has(text, "\nDependent Variable: y\n");
    try has(text, "Source DF Anova SS Mean Square F Value Pr > F\n\ng 1 ");
    try t.expect(std.mem.indexOf(u8, text, "Type I") == null and std.mem.indexOf(u8, text, "GLM") == null);
    try has(text, "9.00");
    // ORDER=DATA keeps first-appearance order; BY/FREQ after RUN are ignored.
    try has(try listing(a, ds, "proc anova order=data; class g; model y=g; run; by y; freq y; run;"), "\ng 2 2 1\n");
    const e = try env(a, ds);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova; class g; model y=g; run;", &e.diags));
    const d = try anova.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try close(30, fit.type_i[0].ss);
    try close(10, fit.model.fit.sse);
    try close(40, fit.model.fit.sst);
    try close(9, fit.type_i[0].f_value);
    try t.expectEqual(@as(usize, 1), fit.type_i[0].df);
}

test "ANOVA001 FREQ truncates, drops missing or below-one counts and equals row expansion" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Usable expansion: g=1 {1,1,4}, g=2 {5,8,8}. Means 2 and 7, grand 4.5:
    // SSB = 6*2.5^2 = 37.5, SSE = 6 + 6 = 12, SST = 49.5, error DF = 6-2 = 4.
    const ds = try table(a, "s", &.{ "g", "y", "f" }, &.{ .{ 1, 1, 2.9 }, .{ 1, 4, 1 }, .{ 2, 5, 1 }, .{ 2, 8, 2 }, .{ 1, 100, M }, .{ 2, 100, 0 }, .{ 1, 100, -1 }, .{ 2, 100, 0.5 } });
    const expanded = try table(a, "x", &.{ "g", "y" }, &.{ .{ 1, 1 }, .{ 1, 1 }, .{ 1, 4 }, .{ 2, 5 }, .{ 2, 8 }, .{ 2, 8 } });
    const e = try env(a, ds);
    try e.lib.put("x", expanded);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova data=s; class g; model y=g; freq f; run;", &e.diags));
    try t.expectEqual(@as(?usize, 2), spec.freq);
    const d = try anova.build(cx, spec, try selection.View.init(a, spec.input, .{ .frequency = spec.freq }), spec.responses[0]);
    try t.expectEqual(@as(usize, 8), d.read);
    try t.expectEqual(@as(usize, 4), d.n);
    try t.expectEqualSlices(f64, &.{ 2, 1, 1, 2 }, d.frequencies);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    const plain = try anova.parse(cx, try lex.tokenize(a, "proc anova data=x; class g; model y=g; run;", &e.diags));
    var literal = try glm.fitDesign(cx, plain, try anova.build(cx, plain, try selection.View.init(a, plain.input, .{}), plain.responses[0]));
    defer literal.deinit(a);
    try close(37.5, fit.type_i[0].ss);
    try close(12, fit.model.fit.sse);
    try close(49.5, fit.model.fit.sst);
    try close(4.5, fit.model.fit.y_mean);
    try t.expectEqual(@as(usize, 4), fit.model.fit.df_error);
    try close(literal.type_i[0].ss, fit.type_i[0].ss);
    try close(literal.model.fit.sse, fit.model.fit.sse);
    try t.expectEqual(literal.model.fit.df_error, fit.model.fit.df_error);
    try t.expect(!e.diags.hasErrors());
    // Every FREQ value unusable: loud user error, never an empty success.
    const none = try table(a, "z", &.{ "g", "y", "f" }, &.{ .{ 1, 1, 0 }, .{ 2, 2, M } });
    try t.expectEqual(@as(u8, 1), try exitOf(a, none, "proc anova; class g; model y=g; freq f; run;"));
}

test "ANOVA001 missing values: per-response selection, CLASS exclusion and MANOVA listwise mode" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_][3]f64{ .{ 1, 1, 10 }, .{ 1, 2, 11 }, .{ 2, 3, M }, .{ 2, 5, 13 }, .{ M, 9, 9 }, .{ 1, M, 12 }, .{ 2, 4, 15 } };
    const ds = try table(a, "s", &.{ "g", "y1", "y2" }, &rows);
    const e = try env(a, ds);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova; class g; model y1 y2=g; run;", &e.diags));
    const view = try selection.View.init(a, spec.input, .{});
    const d1 = try anova.build(cx, spec, view, spec.responses[0]);
    const d2 = try anova.build(cx, spec, view, spec.responses[1]);
    try t.expectEqual(@as(usize, 7), d1.read);
    try t.expectEqualSlices(usize, &.{ 1, 2, 3, 4, 7 }, d1.source_rows);
    try t.expectEqualSlices(usize, &.{ 1, 2, 4, 6, 7 }, d2.source_rows);
    const listwise = try anova.parse(cx, try lex.tokenize(a, "proc anova manova; class g; model y1 y2=g; run;", &e.diags));
    for (listwise.responses) |response| {
        const d = try anova.build(cx, listwise, view, response);
        try t.expectEqualSlices(usize, &.{ 1, 2, 4, 7 }, d.source_rows);
    }
    try t.expect(!e.diags.hasErrors());
    // Listwise y1: g=1 {1,2}, g=2 {5,4}; means 1.5, 4.5: SSB = 4*1.5^2 = 9, SSE = 1.
    const d = try anova.build(cx, listwise, view, listwise.responses[0]);
    var fit = try glm.fitDesign(cx, listwise, d);
    defer fit.deinit(a);
    try close(9, fit.type_i[0].ss);
    try close(1, fit.model.fit.sse);
    try has(try listing(a, ds, "proc anova manova; class g; model y1 y2=g; run;"), "Number of Observations Read 7\nNumber of Observations Used 4\n");
    // Different patterns: one "Data for Analysis" block per pattern (close-out test below).
    try t.expectEqual(@as(u8, 0), try exitOf(a, ds, "proc anova; class g; model y1 y2=g; run;"));
    // SAS reference: an empty data set is a NOTE, no tables, no error.
    const empty = try table(a, "z", &.{ "g", "y" }, &.{});
    try t.expectEqual(@as(u8, 0), try exitOf(a, empty, "proc anova; class g; model y=g; run;"));
    const blank = try table(a, "m", &.{ "g", "y" }, &.{ .{ 1, M }, .{ M, 2 } });
    try t.expectEqual(@as(u8, 1), try exitOf(a, blank, "proc anova; class g; model y=g; run;"));
}

test "ANOVA001 BY groups: boundaries, per-group levels and counts, sort checking" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // b=1: g=1 {1,3}, g=2 {5,7}: SSB = 4*2^2 = 16, SSE = 4, F = 16/(4/2) = 8.00.
    // b=2: g=1 {2,2}, g=2 {2,4}, g=3 {9,.}: one missing response, three levels.
    const rows = [_][3]f64{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 1, 2, 7 }, .{ 2, 1, 2 }, .{ 2, 1, 2 }, .{ 2, 2, 2 }, .{ 2, 2, 4 }, .{ 2, 3, 9 }, .{ 2, 3, M } };
    const ds = try table(a, "s", &.{ "b", "g", "y" }, &rows);
    const text = try listing(a, ds, "proc anova; by b; class g; model y=g; run;");
    try has(text, "b=1");
    try has(text, "b=2");
    try has(text, "\ng 2 1 2\n\nNumber of Observations Read 4\nNumber of Observations Used 4\n");
    try has(text, "\ng 3 1 2 3\n\nNumber of Observations Read 6\nNumber of Observations Used 5\n");
    try t.expect(std.mem.indexOf(u8, text, "b=1").? < std.mem.indexOf(u8, text, "g 2 1 2").?);
    try t.expect(std.mem.indexOf(u8, text, "g 2 1 2").? < std.mem.indexOf(u8, text, "b=2").?);
    try has(text, " 8.00 ");
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, text, "The ANOVA Procedure"));
    const e = try env(a, ds);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova; by b; class g; model y=g; run;", &e.diags));
    const groups = try (try selection.View.init(a, spec.input, .{ .by = spec.by })).groups(a, spec.descending, spec.notsorted, &e.diags);
    try t.expectEqual(@as(usize, 2), groups.len);
    const d = try anova.build(cx, spec, groups[0], spec.responses[0]);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try close(16, fit.type_i[0].ss);
    try close(4, fit.model.fit.sse);
    // Unsorted BY input is a user error; NOTSORTED and DESCENDING accept it.
    const unsorted = try table(a, "u", &.{ "b", "g", "y" }, &.{ .{ 2, 1, 1 }, .{ 2, 2, 3 }, .{ 2, 2, 4 }, .{ 1, 1, 1 }, .{ 1, 2, 3 }, .{ 1, 2, 5 } });
    try t.expectEqual(@as(u8, 1), try exitOf(a, unsorted, "proc anova; by b; class g; model y=g; run;"));
    const loose = try listing(a, unsorted, "proc anova; by b notsorted; class g; model y=g; run;");
    try t.expect(std.mem.indexOf(u8, loose, "b=2").? < std.mem.indexOf(u8, loose, "b=1").?);
    _ = try listing(a, unsorted, "proc anova; by descending b; class g; model y=g; run;");
    try t.expectEqual(@as(u8, 1), try exitOf(a, unsorted, "proc anova; by nosuch; class g; model y=g; run;"));
}

test "ANOVA001 balanced crossing uses ANOVA SS; unbalanced multi-effect designs run with the SAS warning (STAT-ANOVA-003)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 2x2, one per cell: y(1,1)=1 y(1,2)=2 y(2,1)=4 y(2,2)=7, grand 3.5.
    // a means 1.5, 5.5: SSA = 2*(4+4) = 16; b means 2.5, 4.5: SSB = 4;
    // SST = 6.25+2.25+0.25+12.25 = 21; SSE = 1.
    const ds = try table(a, "s", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 7 } });
    const e = try env(a, ds);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova; class a b; model y=a b; run;", &e.diags));
    const d = try anova.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
    const ss = try anova.ssTable(cx, spec, d);
    try t.expect(!ss.unequal);
    try close(16, ss.effects[0].ss);
    try close(4, ss.effects[1].ss);
    try close(1, ss.sse);
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try close(16, fit.type_i[0].ss);
    try close(4, fit.type_i[1].ss);
    try close(1, fit.model.fit.sse);
    try close(21, fit.model.fit.sst);
    const text = try listing(a, ds, "proc anova; class b a; model y=b a; run;");
    try has(text, "\nb 2 1 2\n\na 2 1 2\n");
    const lopsided = try table(a, "u", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 1, 2 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 7 }, .{ 2, 2, 9 }, .{ 1, 2, 3 } });
    // SAS 9.4 reference: unequal cells print the tables after a WARNING.
    try t.expectEqual(@as(u8, 0), try exitOf(a, lopsided, "proc anova; class a b; model y=a b; run;"));
    const hole = try table(a, "h", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 2, 1, 6 } });
    try t.expectEqual(@as(u8, 0), try exitOf(a, hole, "proc anova; class a b; model y=a b; run;"));
}

// ---- STAT-ANOVA-007: MEANS statement (S154 physical pp.1123–1129) ----
// Invented balanced data: g=1 {1,3}, g=2 {5,7}, g=3 {12,14}.
// Means 2, 6, 13; every SD = sqrt(((-1)^2+1^2)/1) = sqrt(2) = 1.41421356.
// SSE = 3*2 = 6, dfe = 6-3 = 3, MSE = 2, n = 2, so sqrt(MSE/n) = 1.
const means_rows = [_][2]f64{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 5 }, .{ 2, 7 }, .{ 3, 12 }, .{ 3, 14 } };

test "ANOVA007 plain MEANS table: hand-derived N, means and standard deviations" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "g", "y" }, &means_rows);
    const text = try listing(a, ds, "proc anova; class g; model y=g; means g; run;");
    try has(text, "Level of --------------y--------------\ng N Mean Std Dev\n\n1 2 2.0000000 1.41421356\n2 2 6.0000000 1.41421356\n3 2 13.0000000 1.41421356\n");
    // The table follows the ANOVA tables and is printed once.
    try t.expect(std.mem.indexOf(u8, text, "Anova SS").? < std.mem.indexOf(u8, text, "Level of").?);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, text, "Level of"));
    // ALPHA= alone is accepted; NOPRINT suppresses the table.
    try has(try listing(a, ds, "proc anova; class g; model y=g; means g / alpha=0.1; run;"), "3 2 13.0000000 1.41421356");
    try t.expectEqualStrings("", try listing(a, ds, "proc anova noprint; class g; model y=g; means g; run;"));
}

test "ANOVA007 MEANS with two dependent variables and two effects" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Balanced 2x2, one row per cell. a=1: y {1,2} mean 1.5 SD sqrt(.5);
    // a=2: y {5,8} mean 6.5 SD sqrt(4.5)=2.12132034. z = 10*y.
    const ds = try table(a, "s", &.{ "a", "b", "y", "z" }, &.{ .{ 1, 1, 1, 10 }, .{ 1, 2, 2, 20 }, .{ 2, 1, 5, 50 }, .{ 2, 2, 8, 80 } });
    const text = try listing(a, ds, "proc anova; class a b; model y z=a b; means a b; run;");
    try has(text, "Level of --------------y-------------- --------------z--------------\na N Mean Std Dev Mean Std Dev\n\n1 2 1.50000000 0.70710678 15.0000000 7.0710678\n2 2 6.50000000 2.12132034 65.0000000 21.2132034\n");
    // b=1: y {1,5} mean 3 SD sqrt(8)=2.82842712; b=2: y {2,8} mean 5 SD sqrt(18)=4.24264069.
    try has(text, "b N Mean Std Dev Mean Std Dev\n\n1 2 3.00000000 2.82842712 30.0000000 28.2842712\n2 2 5.00000000 4.24264069 50.0000000 42.4264069\n");
}

test "ANOVA007 Tukey HSD: MSD = q*sqrt(MSE/n), grouping letters and the information table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const range = @import("studentized_range.zig");
    // Hand example above: sqrt(MSE/n) = 1, so MSD is the critical value itself.
    const info = try anova.tukeyInfo(0.05, 3, 3, 2, 2);
    try t.expectEqual(try range.critical(0.05, 3, 3), info.critical);
    try t.expectEqual(info.critical * @sqrt(2.0 / 2.0), info.msd);
    try t.expectApproxEqAbs(5.910, info.critical, 5e-4); // Harter table q(.05;3,3), rounding 0.0005
    // 13-6 = 7 > 5.91 separates the top mean; 6-2 = 4 <= 5.91 joins the rest.
    try t.expectEqualSlices(u32, &.{ 1, 2, 2 }, try anova.tukeyGroups(a, &.{ 13, 6, 2 }, info.msd));
    // Published Clover sample (S154 ch.29 Getting Started): strain means
    // 28.82 23.98 19.92 18.70 14.64 13.26, MSE = 282.928/24, n = 5.
    // 28.82-23.98=4.84 (A); 23.98-18.70=5.28, -14.64=9.34 (B); 19.92-13.26=6.66 (C).
    const clover = try anova.tukeyInfo(0.05, 6, 24, 282.928 / 24.0, 5);
    try t.expectEqualSlices(u32, &.{ 1, 3, 6, 6, 4, 4 }, try anova.tukeyGroups(a, &.{ 28.82, 23.98, 19.92, 18.70, 14.64, 13.26 }, clover.msd));
    var out: std.ArrayList(u8) = .empty;
    try anova.renderTukeyInfo(a, &out, "Nitrogen", clover);
    try has(out.items, "Tukey's Studentized Range (HSD) Test for Nitrogen\n");
    try has(out.items, "Alpha 0.05\nError Degrees of Freedom 24\nError Mean Square 11.78867\nCritical Value of Studentized Range 4.37265\nMinimum Significant Difference 6.7142\n");
    // A larger alpha gives a smaller range; ties within MSD form one group.
    try t.expect((try anova.tukeyInfo(0.1, 3, 3, 2, 2)).msd < info.msd);
    try t.expectEqualSlices(u32, &.{ 1, 1, 1 }, try anova.tukeyGroups(a, &.{ 3, 2, 1 }, 2));
    try t.expectEqualSlices(u32, &.{ 1, 2, 4 }, try anova.tukeyGroups(a, &.{ 9, 5, 1 }, 2));
}

test "ANOVA007 MEANS option boundaries: user errors exit 1, unimplemented comparisons exit 2" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 5 }, .{ 2, 2, 8 } });
    for ([_]struct { code: u8, text: []const u8 }{
        .{ .code = 0, .text = "proc anova; class a b; model y=a b; means a; run;" },
        .{ .code = 0, .text = "proc anova; class a b; model y=a b; run; means a b; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means a / bogus; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means a / alpha=2; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means a / alpha; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means y; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means nosuch; run;" },
        .{ .code = 1, .text = "proc anova; class a b; model y=a b; means; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / tukey; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / tukey alpha=0.1; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a*b; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a; means b; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / bon; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / duncan; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / dunnett; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / scheffe; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / snk; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / waller; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / hovtest; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / welch; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / e=b; run;" },
        .{ .code = 2, .text = "proc anova; class a b; model y=a b; means a / lsd cldiff; run;" },
    }) |c| {
        const code = try exitOf(a, ds, c.text);
        if (code != c.code) std.debug.print("program: {s}\n", .{c.text});
        try t.expectEqual(c.code, code);
    }
}

test "ANOVA007 interactive MEANS after RUN uses the retained model and prints only the means" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "g", "y" }, &means_rows);
    const e = try env(a, ds);
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try anova.runStep(e.cx(a), &out, try lex.tokenize(a, "proc anova data=s; class g; model y=g; run;", &e.diags));
    try t.expect(std.mem.indexOf(u8, out.items, "Level of") == null);
    const before = out.items.len;
    try t.expect(try anova.continuation(e.cx(a), &out, try lex.tokenize(a, "means g; run;", &e.diags)));
    const added = out.items[before..];
    try has(added, "The ANOVA Procedure\n\nLevel of --------------y--------------\ng N Mean Std Dev\n\n1 2 2.0000000 1.41421356\n2 2 6.0000000 1.41421356\n3 2 13.0000000 1.41421356\n");
    try t.expect(std.mem.indexOf(u8, added, "Dependent Variable") == null);
    try t.expect(std.mem.indexOf(u8, added, "Class Level") == null);
    // Still open: a second request works; a gap request reports exit 2 and
    // leaves the listing untouched; QUIT closes the procedure.
    try t.expect(try anova.continuation(e.cx(a), &out, try lex.tokenize(a, "means g;", &e.diags)));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Level of"));
    try t.expect(!e.diags.hasErrors());
    const size = out.items.len;
    try t.expectError(error.ParseError, anova.continuation(e.cx(a), &out, try lex.tokenize(a, "means g / tukey; run;", &e.diags)));
    try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
    try t.expectEqual(size, out.items.len);
    try t.expect(try anova.continuation(e.cx(a), &out, try lex.tokenize(a, "quit;", &e.diags)));
    try t.expect(!try anova.continuation(e.cx(a), &out, try lex.tokenize(a, "means g; run;", &e.diags)));
    // BY closes the procedure at RUN (p.1118): no interactive MEANS.
    try anova.runStep(e.cx(a), &out, try lex.tokenize(a, "proc anova data=s; by g; class g; model y=g; run;", &e.diags));
    try t.expect(!try anova.continuation(e.cx(a), &out, try lex.tokenize(a, "means g; run;", &e.diags)));
}

// ---- STAT-ANOVA-010: ODS Graphics (S154 physical pp.1115–1117, 1143–1144) ----
const anova_plots = @import("anova_plots.zig");
// Published Clover sample (S154 ch.29 Getting Started), levels in formatted
// order 3DOK1, 3DOK13, 3DOK4, 3DOK5, 3DOK7, COMPOS.
const clover_labels = [_][]const u8{ "3DOK1", "3DOK13", "3DOK4", "3DOK5", "3DOK7", "COMPOS" };
const clover_values = [_]f64{ 19.4, 32.6, 27.0, 32.1, 33.0, 17.7, 24.8, 27.9, 25.2, 24.3, 17.0, 19.4, 9.1, 11.9, 15.8, 20.7, 21.0, 20.5, 18.8, 18.6, 14.3, 14.4, 11.8, 11.6, 14.2, 17.3, 19.4, 19.1, 16.9, 20.8 };
const clover_groups = [_]usize{ 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 1, 1, 1, 1, 1, 5, 5, 5, 5, 5 };

fn graphEnv(a: std.mem.Allocator, ds: *Dataset, enabled: ?bool) !struct { e: *Env, session: *proc.native_graphics.Session } {
    const e = try env(a, ds);
    const session = try a.create(proc.native_graphics.Session);
    session.* = .{ .arena = a, .io = t.io, .diags = &e.diags, .enabled = enabled };
    return .{ .e = e, .session = session };
}
/// Kinds of the graphs a program queues, in order, joined by spaces.
fn queued(a: std.mem.Allocator, ds: *Dataset, enabled: ?bool, text: []const u8) ![]const u8 {
    const g = try graphEnv(a, ds, enabled);
    var cx = g.e.cx(a);
    cx.graphics = g.session;
    var out: std.ArrayList(u8) = .empty;
    try anova.run(cx, &out, try lex.tokenize(a, text, &g.e.diags));
    try t.expect(!g.e.diags.hasErrors());
    var kinds: std.ArrayList(u8) = .empty;
    for (g.session.prepared.items, 0..) |artifact, i| {
        try t.expectEqual(i, artifact.order);
        if (i != 0) try kinds.append(a, ' ');
        try kinds.appendSlice(a, artifact.kind);
    }
    return kinds.items;
}

test "ANOVA010 box plot statistics, plotted coordinates and inset for the published Clover data" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const image = try anova_plots.boxSvg(a, .model, &clover_values, &clover_groups, &clover_labels, "Nitrogen", "Strain", .{ .f = 14.37, .p = 0.00000128 });
    try has(image, "data-kind=\"anova-boxplot\"><title>Distribution of Nitrogen</title>");
    try t.expectEqual(@as(usize, 6), std.mem.count(u8, image, "class=\"anova-box\""));
    try t.expectEqual(@as(usize, 30), std.mem.count(u8, image, "class=\"anova-data\""));
    // QNTLDEF=5 on five sorted values: Q1 = 2nd, median = 3rd, Q3 = 4th.
    // 3DOK1 sorted 19.4 27.0 32.1 32.6 33.0; fences 27-1.5*5.6 .. 32.6+8.4.
    try has(image, "data-group=\"0\" data-n=\"5\" data-q1=\"27\" data-median=\"32.1\" data-q3=\"32.6\"");
    try has(image, "data-lower=\"19.4\" data-upper=\"33\"><title>3DOK1</title>");
    try has(image, "data-group=\"1\" data-n=\"5\" data-q1=\"11.8\" data-median=\"14.2\" data-q3=\"14.3\"");
    try has(image, "data-group=\"2\" data-n=\"5\" data-q1=\"11.9\" data-median=\"15.8\" data-q3=\"17\"");
    // 3DOK5 sorted 17.7 24.3 24.8 25.2 27.9: IQR 0.9, fences 22.95..26.55,
    // so 17.7 and 27.9 are outliers and the whiskers stop at the quartiles.
    try has(image, "data-group=\"3\" data-n=\"5\" data-q1=\"24.3\" data-median=\"24.8\" data-q3=\"25.2\"");
    try has(image, "data-lower=\"24.3\" data-upper=\"25.2\"><title>3DOK5</title>");
    try has(image, "class=\"outlier\" data-value=\"17.7\"");
    try has(image, "class=\"outlier\" data-value=\"27.9\"");
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, image, "class=\"outlier\""));
    try has(image, "data-group=\"4\" data-n=\"5\" data-q1=\"18.8\" data-median=\"20.5\" data-q3=\"20.7\"");
    try has(image, "data-group=\"5\" data-n=\"5\" data-q1=\"17.3\" data-median=\"19.1\" data-q3=\"19.4\"");
    // Means 144.1/5, 66.3/5, 73.2/5, 119.9/5, 99.6/5, 93.5/5.
    const summary = try @import("npar1way_plots.zig").summarize(a, &clover_values, &clover_groups, 6);
    for ([_]f64{ 28.82, 13.26, 14.64, 23.98, 19.92, 18.7 }, summary) |mean, box| try t.expectApproxEqAbs(mean, box.mean, 1e-12);
    // Axis: data range 9.1..33.0 padded by 5% = 7.905..34.195 on y 420..60;
    // level i sits at x = 88 + 572*(i+0.5)/6, box half-width 28.
    // 3DOK1 median 32.1: y = 420 - 360*(32.1-7.905)/26.29 = 88.69; x = 135.67.
    try has(image, "<line class=\"median\" x1=\"107.67\" x2=\"163.67\" y1=\"88.69\" y2=\"88.69\"/>");
    // 3DOK5 outlier 17.7 at x = 88 + 572*3.5/6 = 421.67, y = 420 - 360*9.795/26.29 = 285.87.
    try has(image, "data-value=\"17.7\" cx=\"421.67\" cy=\"285.87\"");
    try has(image, "<text x=\"374\" y=\"465\" text-anchor=\"middle\">Strain</text>");
    try has(image, "data-f=\"14.37\"><text x=\"650\" y=\"76\" text-anchor=\"end\">F 14.37</text>");
    try has(image, "Prob &gt; F &lt;.0001</text>");
    // The MEANS graph has its own kind and no model inset.
    const means = try anova_plots.boxSvg(a, .means, &clover_values, &clover_groups, &clover_labels, "Nitrogen", "Strain", null);
    try has(means, "data-kind=\"anova-means-boxplot\"");
    try t.expect(std.mem.indexOf(u8, means, "anova-inset") == null);
    try t.expectError(error.InvalidInput, anova_plots.boxSvg(a, .model, &.{ 1, 2 }, &.{ 0, 0 }, &.{ "a", "b" }, "y", "g", null));
}

test "ANOVA010 Tukey lines: sorted means, groups and bar coordinates (Clover and an invented balanced set)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Clover: MSE = 282.928/24, n = 5; MSD = 6.7142 (SAS listing). Sorted
    // 28.82 23.98 19.92 18.70 14.64 13.26: A = {1,2} (4.84), B = {2,3,4}
    // (5.28; 28.82-19.92 = 8.90 > MSD), C = {3,4,5,6} (6.66; 23.98-14.64 = 9.34 > MSD).
    const lines = (try anova.tukeyLines(a, &clover_labels, &.{ 28.82, 13.26, 14.64, 23.98, 19.92, 18.70 }, &.{ 5, 5, 5, 5, 5, 5 }, 0.05, 24, 282.928 / 24.0)).?;
    for ([_][]const u8{ "3DOK1", "3DOK5", "3DOK7", "COMPOS", "3DOK4", "3DOK13" }, lines.labels) |expected, label| try t.expectEqualStrings(expected, label);
    try t.expectEqualSlices(f64, &.{ 28.82, 23.98, 19.92, 18.70, 14.64, 13.26 }, lines.means);
    try t.expectEqualSlices(u32, &.{ 1, 3, 6, 6, 4, 4 }, lines.masks);
    try t.expectApproxEqAbs(@as(f64, 6.7142), lines.info.msd, 5e-5);
    const image = try anova_plots.linesSvg(a, lines.labels, lines.means, lines.masks, "Nitrogen", "Strain", 0.05);
    try has(image, "data-kind=\"anova-linesplot\"><title>Nitrogen Tukey Grouping for Means of Strain (Alpha = 0.05)</title>");
    try has(image, "Means covered by the same bar are not significantly different.");
    try has(image, "data-row=\"0\" data-mean=\"28.82\" data-groups=\"A\"");
    try has(image, "data-row=\"1\" data-mean=\"23.98\" data-groups=\"AB\"");
    try has(image, "data-row=\"3\" data-mean=\"18.7\" data-groups=\"BC\"");
    try has(image, "data-row=\"5\" data-mean=\"13.26\" data-groups=\"C\"");
    try has(image, ">3DOK13</text>");
    // Row i is centred at y = 110 + 44*i; a bar spans first-9 .. last+9 at x = 340 + 26*group.
    try has(image, "<line class=\"lines-bar\" data-group=\"A\" data-first=\"0\" data-last=\"1\" x1=\"340\" x2=\"340\" y1=\"101.00\" y2=\"163.00\"/>");
    try has(image, "<line class=\"lines-bar\" data-group=\"B\" data-first=\"1\" data-last=\"3\" x1=\"366\" x2=\"366\" y1=\"145.00\" y2=\"251.00\"/>");
    try has(image, "<line class=\"lines-bar\" data-group=\"C\" data-first=\"2\" data-last=\"5\" x1=\"392\" x2=\"392\" y1=\"189.00\" y2=\"339.00\"/>");
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, image, "class=\"lines-bar\""));
    // Invented balanced set: level means 2, 13, 6 with n = 2, MSE = 2, df = 3:
    // MSD = q(.05;3,3)*sqrt(2/2) = 5.91 (ANOVA007 test); 13-6 = 7 > MSD, 6-2 = 4 <= MSD.
    const tiny = (try anova.tukeyLines(a, &.{ "a", "b", "c" }, &.{ 2, 13, 6 }, &.{ 2, 2, 2 }, 0.05, 3, 2)).?;
    for ([_][]const u8{ "b", "c", "a" }, tiny.labels) |expected, label| try t.expectEqualStrings(expected, label);
    try t.expectEqualSlices(u32, &.{ 1, 2, 2 }, tiny.masks);
    // Unequal cells need the harmonic-mean form: not produced.
    try t.expect((try anova.tukeyLines(a, &.{ "a", "b", "c" }, &.{ 2, 13, 6 }, &.{ 2, 3, 2 }, 0.05, 3, 2)) == null);
    try t.expectError(error.InvalidInput, anova_plots.linesSvg(a, &.{"a"}, &.{ 1, 2 }, &.{1}, "y", "g", 0.05));
}

test "ANOVA010 graph identities follow the SAS ODS trace of the Getting Started program" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = try anova_plots.boxObject(a, .model, null, "Nitrogen", "Strain");
    try t.expectEqualStrings("BoxPlot", model.name);
    try t.expectEqualStrings("Box Plot", model.label.?);
    try t.expectEqualStrings("Stat.GLM.Graphics.BoxPlot", model.template);
    try t.expectEqualStrings("ANOVA.ANOVA.Nitrogen.BoxPlot", model.path);
    const means = try anova_plots.boxObject(a, .means, null, "Yield", "Treatment");
    try t.expectEqualStrings("BoxPlot", means.name);
    try t.expectEqualStrings("Distribution of Yield by Treatment", means.label.?);
    try t.expectEqualStrings("Stat.GLM.Graphics.MeansBoxPlot", means.template);
    try t.expectEqualStrings("ANOVA.Means.Treatment.Yield.BoxPlot", means.path);
    const lines = try anova_plots.linesObject(a, null, "Nitrogen", "Strain");
    try t.expectEqualStrings("LinesPlot", lines.name);
    try t.expect(lines.label == null);
    try t.expectEqualStrings("Stat.GLM.Graphics.MeanLinesPlot", lines.template);
    try t.expectEqualStrings("ANOVA.Means.Strain.Nitrogen.MCLines.Tukey.LinesPlot", lines.path);
    try t.expect(@import("graph_ods.zig").known("BoxPlot") and @import("graph_ods.zig").known("LinesPlot"));
}

test "ANOVA010 graph triggers and suppression: one-way model, MEANS, PLOTS=NONE, NOPRINT, ODS GRAPHICS OFF" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one = try table(a, "s", &.{ "g", "y" }, &.{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 5 }, .{ 2, 7 }, .{ 3, 12 }, .{ 3, 14 } });
    try t.expectEqualStrings("anova-boxplot", try queued(a, one, true, "proc anova; class g; model y=g; run;"));
    try t.expectEqualStrings("anova-boxplot anova-means-boxplot", try queued(a, one, true, "proc anova; class g; model y=g; means g; run;"));
    try t.expectEqualStrings("anova-boxplot anova-means-boxplot anova-linesplot", try queued(a, one, true, "proc anova; class g; model y=g; means g / tukey; run;"));
    try t.expectEqualStrings("", try queued(a, one, true, "proc anova plots=none; class g; model y=g; means g; run;"));
    try t.expectEqualStrings("", try queued(a, one, true, "proc anova noprint; class g; model y=g; means g / tukey; run;"));
    try t.expectEqualStrings("", try queued(a, one, false, "proc anova; class g; model y=g; means g; run;"));
    try t.expectEqualStrings("", try queued(a, one, null, "proc anova; class g; model y=g; means g; run;"));
    // Two-way main-effects model: no default plot; MEANS draws one per response.
    const two = try table(a, "s", &.{ "a", "b", "y", "z" }, &.{ .{ 1, 1, 1, 2 }, .{ 1, 2, 2, 5 }, .{ 2, 1, 5, 4 }, .{ 2, 2, 8, 9 } });
    try t.expectEqualStrings("", try queued(a, two, true, "proc anova; class a b; model y=a b; run;"));
    try t.expectEqualStrings("anova-means-boxplot anova-means-boxplot", try queued(a, two, true, "proc anova; class a b; model y z=a b; means a; run;"));
    // The Tukey page under ODS Graphics: information table, no Means table.
    const g = try graphEnv(a, one, true);
    var cx = g.e.cx(a);
    cx.graphics = g.session;
    var out: std.ArrayList(u8) = .empty;
    try anova.run(cx, &out, try lex.tokenize(a, "proc anova; class g; model y=g; means g / tukey; run;", &g.e.diags));
    try has(out.items, "Tukey's Studentized Range (HSD) Test for y\n");
    try has(out.items, "Error Degrees of Freedom 3\nError Mean Square 2.000000\n");
    try t.expect(std.mem.indexOf(u8, out.items, "Level of") == null);
    // Loud gaps (exit 2): LINES table without graphics, other comparison
    // options, FREQ-weighted box plots; unknown options stay user errors.
    for ([_]struct { code: u8, enabled: ?bool, text: []const u8 }{
        .{ .code = 2, .enabled = false, .text = "proc anova; class g; model y=g; means g / tukey; run;" },
        .{ .code = 2, .enabled = true, .text = "proc anova plots=none; class g; model y=g; means g / tukey; run;" },
        .{ .code = 2, .enabled = true, .text = "proc anova; class g; model y=g; means g / tukey lines; run;" },
        .{ .code = 2, .enabled = true, .text = "proc anova; class g; model y=g; means g / tukey cldiff; run;" },
        .{ .code = 2, .enabled = true, .text = "proc anova plots(maxpoints=none); class g; model y=g; run;" },
        .{ .code = 2, .enabled = true, .text = "proc anova; class g; model x=g; freq y; run;" },
        .{ .code = 1, .enabled = true, .text = "proc anova plots=bogus; class g; model y=g; run;" },
        .{ .code = 1, .enabled = true, .text = "proc anova; class g; model y=g; means g / tukeyplot; run;" },
    }) |case| {
        const three = try table(a, "s", &.{ "g", "y", "x" }, &.{ .{ 1, 1, 1 }, .{ 1, 3, 2 }, .{ 2, 5, 3 }, .{ 2, 7, 5 } });
        const ge = try graphEnv(a, three, case.enabled);
        var gcx = ge.e.cx(a);
        gcx.graphics = ge.session;
        diag.resetGap();
        defer diag.resetGap();
        var sink: std.ArrayList(u8) = .empty;
        try t.expect(if (anova.run(gcx, &sink, try lex.tokenize(a, case.text, &ge.e.diags))) |_| false else |_| true);
        const code = diag.exitCode(diag.gapHit(), ge.e.diags.hasErrors());
        if (code != case.code) std.debug.print("exit {d} for: {s}\n", .{ code, case.text });
        try t.expectEqual(case.code, code);
        try t.expectEqual(@as(usize, 0), ge.session.prepared.items.len);
    }
}

// ---- STAT-ANOVA-001 close-out: layouts checked against SAS 9.4 listings of
// the same invented data (see tests/corpus/stat_anova_missing.sas). ----

test "ANOVA001 different missing patterns: per-pattern groups, union class levels, interactivity disabled" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // y1 and y3 miss row 5 only; y2 misses rows 3, 8, 9 (all of level 3).
    const ds = try table(a, "s", &.{ "g", "y1", "y2", "y3" }, &.{ .{ 1, 1, 10, 4 }, .{ 1, 2, 11, 5 }, .{ 2, 3, M, 6 }, .{ 2, 5, 13, 7 }, .{ 1, M, 12, M }, .{ 2, 4, 15, 8 }, .{ 1, 6, 14, 2 }, .{ 3, 8, M, 1 }, .{ 3, 9, M, 3 } });
    const text = try listing(a, ds, "proc anova; class g; model y1 y2 y3=g; run;");
    try has(text, "\ng 3 1 2 3\n\nData for Analysis of y1 y3\n\nNumber of Observations Read 9\nNumber of Observations Used 8\n\nData for Analysis of y2\n\nNumber of Observations Read 9\nNumber of Observations Used 6\n\nNOTE: Variables in each group are consistent with respect to the presence or absence of missing values.\n");
    // Pages follow the groups: y1, y3, then y2.
    const y1 = std.mem.indexOf(u8, text, "Dependent Variable: y1").?;
    const y3 = std.mem.indexOf(u8, text, "Dependent Variable: y3").?;
    const y2 = std.mem.indexOf(u8, text, "Dependent Variable: y2").?;
    try t.expect(y1 < y3 and y3 < y2);
    // y2 sees only levels 1 and 2: g=1 {10,11,12,14} mean 11.75, g=2 {13,15}
    // mean 14, grand 12.5: SS = 4*0.75^2 + 2*1.5^2 = 6.75 on 1 DF.
    try has(text[y2..], "\ng 1 ");
    try has(text[y2..], " 6.75000000 ");
    // p.1139: interactivity is disabled; a later MEANS is not consumed.
    const e = try env(a, ds);
    const cx = e.cx(a);
    var out: std.ArrayList(u8) = .empty;
    try anova.runStep(cx, &out, try lex.tokenize(a, "proc anova; class g; model y1 y2=g; run;", &e.diags));
    try t.expect(!try anova.continuation(cx, &out, try lex.tokenize(a, "means g; run;", &e.diags)));
    // Same pattern everywhere keeps the single counts block and interactivity.
    const same = try listing(a, ds, "proc anova; class g; model y1 y3=g; run;");
    try t.expect(std.mem.indexOf(u8, same, "Data for Analysis") == null);
}

test "ANOVA001 FREQ prints frequencies read and used and names the FREQ variable" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Frequencies read add the truncated values >= 1 of every row:
    // 1 + 1 (1.5) + 1 + 3 = 6. Used rows also need y and FREQ >= 1:
    // rows 1, 5 and 6 -> 3 observations, 1 + 1 + 3 = 5 frequencies.
    const ds = try table(a, "s", &.{ "g", "y", "f" }, &.{ .{ 1, 4, 1 }, .{ 1, 5, -2 }, .{ 2, 6, M }, .{ 2, M, 1.5 }, .{ 1, 7, 1 }, .{ 2, 8, 3 }, .{ 1, 2, 0 } });
    const text = try listing(a, ds, "proc anova; class g; model y=g; freq f; run;");
    try has(text, "Number of Observations Read 7\nNumber of Observations Used 3\nSum of Frequencies Read 6\nSum of Frequencies Used 5\n");
    try has(text, "\nDependent Variable: y\n\nFrequency: f\n");
}

test "ANOVA001 duplicate declarations, empty BY groups and ANOVA-labelled reader diagnostics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "u", "g", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 3 }, .{ 1, 1, 2 }, .{ 1, 2, 6 }, .{ 2, 1, M }, .{ 2, 2, M }, .{ 3, 1, 5 }, .{ 3, 2, 9 } });
    const other = try table(a, "b", &.{"x"}, &.{.{1}});
    const e = try env(a, ds);
    try e.lib.put("b", other);
    const cx = e.cx(a);
    // A second DATA= is ignored with a WARNING; the first data set is used.
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova data=s data=b; class g; model y=g; run;", &e.diags));
    try t.expectEqualStrings("s", spec.input.ds.name);
    try t.expectEqualStrings("Ignoring second data set reference.", e.diags.list.items[e.diags.list.items.len - 1].message);
    // A second CLASS statement adds its variables to the first.
    const merged = try anova.parse(cx, try lex.tokenize(a, "proc anova data=s; class u; class g; model y=g; run;", &e.diags));
    try t.expectEqualSlices(usize, &.{ 0, 1 }, merged.classes);
    // p.1117: only the last BY statement is used.
    const by = try anova.parse(cx, try lex.tokenize(a, "proc anova data=s; by g; by u; class g; model y=g; run;", &e.diags));
    try t.expectEqualSlices(usize, &.{0}, by.by);
    try t.expect(!e.diags.hasErrors());
    // Errors raised by the shared CLASS/MODEL reader name PROC ANOVA.
    const before = e.diags.list.items.len;
    try t.expectError(error.ParseError, anova.parse(cx, try lex.tokenize(a, "proc anova data=s; class g; model y=g nosuch; run;", &e.diags)));
    for (e.diags.list.items[before..]) |item| try t.expect(std.mem.indexOf(u8, item.message, "PROC GLM") == null);
    // STAT-ANOVA-003: ANOVA reads its own effects with the SAS 9.4 wording.
    try t.expectEqualStrings("Variable nosuch not found.", e.diags.list.items[e.diags.list.items.len - 1].message);
    // A BY group without valid observations is an ERROR for that group only:
    // u=1 and u=3 still print (SAS reference), and the exit class is 1.
    const e2 = try env(a, ds);
    var out: std.ArrayList(u8) = .empty;
    try anova.run(e2.cx(a), &out, try lex.tokenize(a, "proc anova; by u; class g; model y=g; run;", &e2.diags));
    try has(out.items, "u=1");
    try has(out.items, "u=3");
    try t.expect(std.mem.indexOf(u8, out.items, "u=2") == null);
    try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), e2.diags.hasErrors()));
    // Without BY the same condition is a user error.
    const blank = try table(a, "m", &.{ "g", "y" }, &.{ .{ 1, M }, .{ 2, M } });
    try t.expectEqual(@as(u8, 1), try exitOf(a, blank, "proc anova; class g; model y=g; run;"));
}

test "ANOVA001 NAMELEN shortens effect names as SAS does; unverified shapes stay loud" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "averyveryverylongname_aa", "anotherverylongname_bbb", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 7 }, .{ 1, 1, 2 }, .{ 1, 2, 3 }, .{ 2, 1, 5 }, .{ 2, 2, 9 } });
    const short = try listing(a, ds, "proc anova; class averyveryverylongname_aa anotherverylongname_bbb; model y=averyveryverylongname_aa|anotherverylongname_bbb; run;");
    try has(short, "\naveryveryverylongnam 1 ");
    try has(short, "\nanotherverylongname_ 1 ");
    try has(short, "\naveryvery*anotherver 1 ");
    const long = try listing(a, ds, "proc anova namelen=40; class averyveryverylongname_aa anotherverylongname_bbb; model y=averyveryverylongname_aa|anotherverylongname_bbb; run;");
    try has(long, "\naveryveryverylongna*anotherverylongname_ 1 ");
    try has(long, "\naveryveryverylongname_aa 1 ");
    // A short name keeps its length; the other takes the rest (SAS reference).
    const mixed = try table(a, "m", &.{ "g", "anotherveryveryverylongname_bbb", "abcdefghijkl", "y" }, &.{ .{ 1, 1, 1, 1 }, .{ 1, 2, 1, 2 }, .{ 2, 1, 2, 4 }, .{ 2, 2, 2, 7 }, .{ 1, 1, 1, 2 }, .{ 1, 2, 1, 3 }, .{ 2, 1, 2, 5 }, .{ 2, 2, 2, 9 } });
    try has(try listing(a, mixed, "proc anova; class g anotherveryveryverylongname_bbb; model y=g|anotherveryveryverylongname_bbb; run;"), "\ng*anotherveryveryver 1 ");
    try has(try listing(a, mixed, "proc anova; class abcdefghijkl anotherveryveryverylongname_bbb; model y=abcdefghijkl|anotherveryveryverylongname_bbb; run;"), "\nabcdefghi*anotherver 1 ");
    // Crossed factors are named in CLASS order, also when shortened.
    try has(try listing(a, mixed, "proc anova; class g anotherveryveryverylongname_bbb; model y=anotherveryveryverylongname_bbb|g; run;"), "\ng*anotherveryveryver 1 ");
    const small = try table(a, "q", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 7 }, .{ 1, 1, 2 }, .{ 1, 2, 3 }, .{ 2, 1, 5 }, .{ 2, 2, 9 } });
    try has(try listing(a, small, "proc anova; class a b; model y=b|a; run;"), "\na*b 1 ");
    // Nested effects with long names are not SAS-verified: loud gap.
    try t.expectEqual(@as(u8, 2), try exitOf(a, mixed, "proc anova; class g anotherveryveryverylongname_bbb; model y=g anotherveryveryverylongname_bbb(g); run;"));
}

// ---- STAT-ANOVA-003: CLASS / MODEL / Specification of Effects (S154 physical pp.1118–1119, 1129, 1135–1138) ----

/// Listing with runs of blanks collapsed, for token-level assertions.
fn squeezed(a: std.mem.Allocator, ds: *Dataset, text: []const u8) ![]const u8 {
    const raw = try listing(a, ds, text);
    var out: std.ArrayList(u8) = .empty;
    for (raw) |c| {
        if (c == ' ' and out.items.len > 0 and (out.items[out.items.len - 1] == ' ' or out.items[out.items.len - 1] == '\n')) continue;
        if (c == '\n' and out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items[out.items.len - 1] = '\n' else try out.append(a, c);
    }
    return out.items;
}

fn effectNames(a: std.mem.Allocator, ds: *Dataset, text: []const u8) ![]const u8 {
    const e = try env(a, ds);
    const spec = try anova.parse(e.cx(a), try lex.tokenize(a, text, &e.diags));
    var names: std.ArrayList(u8) = .empty;
    for (spec.effects, 0..) |effect, k| {
        if (k > 0) try names.append(a, ' ');
        try names.appendSlice(a, effect.name);
    }
    return names.items;
}

test "STAT-ANOVA-003 effect grammar: crossed, nested, bar and @ expand as the guide's table" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "s", &.{ "A", "B", "C", "D", "E", "y" }, &.{.{ 1, 1, 1, 1, 1, 1 }});
    // p.1124 table of bar/at examples, verbatim.
    try t.expectEqualStrings("A C(B) A*C(B)", try effectNames(a, ds, "proc anova; class A B C; model y=A | C(B); run;"));
    try t.expectEqualStrings("A(B) C(B) A*C(B)", try effectNames(a, ds, "proc anova; class A B C; model y=A(B) | C(B); run;"));
    try t.expectEqualStrings("A(B) B(D E)", try effectNames(a, ds, "proc anova; class A B D E; model y=A(B) | B(D E); run;"));
    try t.expectEqualStrings("A B(A) C A*C B*C(A)", try effectNames(a, ds, "proc anova; class A B C; model y=A | B(A) | C; run;"));
    try t.expectEqualStrings("A B(A) C A*C", try effectNames(a, ds, "proc anova; class A B C; model y=A | B(A) | C@2; run;"));
    try t.expectEqualStrings("A B A*B C A*C B*C D A*D B*D C*D", try effectNames(a, ds, "proc anova; class A B C D; model y=A | B | C | D@2; run;"));
    try t.expectEqualStrings("A B A*B C A*C B*C A*B*C", try effectNames(a, ds, "proc anova; class A B C; model y=A|B|C; run;"));
    // p.1123: crossed list first, nesting list in parentheses, CLASS order names.
    try t.expectEqualStrings("A B(A) C*D(A B)", try effectNames(a, ds, "proc anova; class A B C D; model y=A B(A) D*C(B A); run;"));
    // SAS 9.4 reference: A A and A*A are one effect A; A(A) is accepted.
    try t.expectEqualStrings("A", try effectNames(a, ds, "proc anova; class A; model y=A A; run;"));
    try t.expectEqualStrings("A", try effectNames(a, ds, "proc anova; class A; model y=A*A; run;"));
    try t.expectEqualStrings("A(A)", try effectNames(a, ds, "proc anova; class A; model y=A(A); run;"));
    try t.expectEqualStrings("", try effectNames(a, ds, "proc anova; class A; model y=; run;"));
    // Variables of an effect are its crossed and nesting columns in CLASS order.
    const e = try env(a, ds);
    const spec = try anova.parse(e.cx(a), try lex.tokenize(a, "proc anova; class A B C; model y=C*B(A); run;", &e.diags));
    try t.expectEqualSlices(usize, &.{ 0, 1, 2 }, spec.effects[0].variables);
}

test "STAT-ANOVA-003 nested and pooled sums of squares follow the cell-total rules, independent of order" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A=1: B=1 {1,3}, B=2 {5,7}; A=2: B=1 {2,2}, B=2 {8,12}. N=8, sum 40,
    // CF=200, USS=300, SST=100. A totals 16,24 (n=4): 64+144-200 = 8.
    // A*B cells 4,12,4,20 (n=2): 8+72+8+200-200 = 88, so B(A) = 88-8 = 80,
    // DF 4-1-1 = 2. SSE = 100-88 = 12 on 8-1-3 = 4 DF.
    const ds = try table(a, "n", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 1, 2, 7 }, .{ 2, 1, 2 }, .{ 2, 1, 2 }, .{ 2, 2, 8 }, .{ 2, 2, 12 } });
    for ([_][]const u8{ "model y=a b(a);", "model y=b(a) a;", "model y=a a*b;", "model y=a*b a;" }) |model| {
        const e = try env(a, ds);
        const cx = e.cx(a);
        const spec = try anova.parse(cx, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc anova; class a b; {s} run;", .{model}), &e.diags));
        const d = try anova.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]);
        const s = try anova.ssTable(cx, spec, d);
        const ia: usize = if (spec.effects[0].variables.len == 1) 0 else 1;
        try close(8, s.effects[ia].ss);
        try close(1, s.effects[ia].df);
        try close(80, s.effects[1 - ia].ss);
        try close(2, s.effects[1 - ia].df);
        try close(88, s.model_ss);
        try close(12, s.sse);
        try close(4, s.error_df);
        try t.expect(!s.unequal);
    }
    // Without the main effect A the nested effect takes all 88 on 3 DF (p.1125).
    const e = try env(a, ds);
    const cx = e.cx(a);
    const spec = try anova.parse(cx, try lex.tokenize(a, "proc anova; class a b; model y=b(a); run;", &e.diags));
    const s = try anova.ssTable(cx, spec, try anova.build(cx, spec, try selection.View.init(a, spec.input, .{}), spec.responses[0]));
    try close(88, s.effects[0].ss);
    try close(3, s.effects[0].df);
    // Listing order is the MODEL order; F = 40/3 = 13.33, 8/3 = 2.67.
    const text = try squeezed(a, ds, "proc anova; class a b; model y=b(a) a; run;");
    try has(text, "\nb(a) 2 80.00000000 40.00000000 13.33 ");
    try has(text, "\na 1 8.00000000 8.00000000 2.67 ");
}

test "STAT-ANOVA-003 INT, intercept-only, NOUNI and the zero-error displays" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Same data: CF = 200 on 1 DF, USS = 300 on N = 8 DF.
    const ds = try table(a, "n", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 1, 2, 7 }, .{ 2, 1, 2 }, .{ 2, 1, 2 }, .{ 2, 2, 8 }, .{ 2, 2, 12 } });
    // INT: Model = 200+8 on 2 DF; error 92 on 6 DF (MSE 15.333); F(Int) = 200/15.333 = 13.04.
    const int = try squeezed(a, ds, "proc anova; class a; model y=a / int; run;");
    try has(int, "\nModel 2 208.0000000 104.0000000 6.78 ");
    try has(int, "\nUncorrected Total 8 300.0000000\n");
    try has(int, "\nIntercept 1 200.0000000 200.0000000 13.04 ");
    // R-Square stays corrected: 8/100.
    try has(int, "\n0.080000 ");
    // No effects: the intercept alone, R-Square 0 (SAS reference shape).
    const only = try squeezed(a, ds, "proc anova; class a; model y=; run;");
    try has(only, "\nModel 1 200.0000000 200.0000000 14.00 ");
    try has(only, "\nIntercept 1 ");
    try has(only, "\n0.000000 ");
    // NOUNI: Class Level Information and counts only.
    const quiet = try squeezed(a, ds, "proc anova; class a; model y=a / nouni; run;");
    try t.expect(std.mem.indexOf(u8, quiet, "Number of Observations Used 8") != null);
    try t.expect(std.mem.indexOf(u8, quiet, "Dependent Variable") == null);
}

test "STAT-ANOVA-003 REF= moves the reference level last; TRUNCATE merges on 16 characters" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "n", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 3 }, .{ 1, 3, 5 }, .{ 2, 1, 7 }, .{ 2, 2, 2 }, .{ 2, 3, 2 } });
    try has(try squeezed(a, ds, "proc anova; class a(ref='1') b / ref=first; model y=a b; run;"), "\na 2 2 1\n\nb 3 2 3 1\n");
    try has(try squeezed(a, ds, "proc anova; class a(ref=last) b(ref='2'); model y=a b; run;"), "\na 2 1 2\n\nb 3 1 3 2\n");
    // MEANS follows the reordered levels (SAS reference r1).
    const means = try squeezed(a, ds, "proc anova; class b(ref=first); model y=b; means b; run;");
    try t.expect(std.mem.indexOf(u8, means, "\n2 2 ").? < std.mem.indexOf(u8, means, "\n1 2 ").?);
    // Unknown reference level: SAS 9.4 message, user error.
    try t.expectEqual(@as(u8, 1), try exitOf(a, ds, "proc anova; class a(ref='9'); model y=a; run;"));
}

test "STAT-ANOVA-003 invalid models are user errors with SAS wording; EFFECTSIZE stays a loud gap" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try table(a, "n", &.{ "a", "b", "x", "y" }, &.{ .{ 1, 1, 1, 1 }, .{ 1, 2, 2, 3 }, .{ 2, 1, 3, 5 }, .{ 2, 2, 4, 6 } });
    for ([_][2][]const u8{
        .{ "proc anova; class a; model y=a x; run;", "No continuous effects allowed in PROC ANOVA." },
        .{ "proc anova; class b; model y=b(a); run;", "Nesting of continuous variable not allowed." },
        .{ "proc anova; class a; model y=a / solution; run;", "Syntax error, expecting one of the following: ;, EFFECTSIZE, INTERCEPT, NOUNI." },
        .{ "proc anova; class a(ref='9'); model y=a; run;", "Invalid reference value for a." },
        .{ "proc anova; class a; model y=nosuch; run;", "Variable nosuch not found." },
        .{ "proc anova; class a b; model y=a|b@0; run;", "@ degree must be positive" },
        .{ "proc anova; class a b; model y=a b(); run;", "invalid nested effect" },
        .{ "proc anova; class a b; model y=a*; run;", "invalid effect specification" },
        .{ "proc anova; class a(ref=2); model y=a; run;", "CLASS REF= requires a quoted level, FIRST or LAST" },
        .{ "proc anova; class a / ref='1'; model y=a; run;", "CLASS global options are REF=FIRST | LAST and TRUNCATE" },
    }) |case| {
        const e = try env(a, ds);
        diag.resetGap();
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        if (anova.run(e.cx(a), &out, try lex.tokenize(a, case[0], &e.diags))) |_| return error.TestExpectedError else |_| {}
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), e.diags.hasErrors()));
        var found = false;
        for (e.diags.list.items) |item| if (std.mem.indexOf(u8, item.message, case[1]) != null) {
            found = true;
        };
        if (!found) std.debug.print("program: {s}\n", .{case[0]});
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    try t.expectEqual(@as(u8, 2), try exitOf(a, ds, "proc anova; class a; model y=a / effectsize; run;"));
    // Same variables through two different effects: loud, not double-counted.
    try t.expectEqual(@as(u8, 2), try exitOf(a, ds, "proc anova; class a b; model y=a*b b(a); run;"));
}
