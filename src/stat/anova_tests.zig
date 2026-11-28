//! STAT-ANOVA-001 permanent checks: PROC ANOVA declarations, defaults, loud
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
        "proc anova; class g; model y=g; means g; run;",
        "proc anova; class g; model y=g; means g / tukey; run;",
        "proc anova; class g; model y x=g; manova h=g; run;",
        "proc anova; class g; model y x=g; repeated t 2; run;",
        "proc anova; class g; model y=g; test h=g e=g; run;",
        "proc anova; absorb g; class g; model y=g; run;",
        "proc anova; class g / truncate; model y=g; run;",
        "proc anova; class g(ref=first); model y=g; run;",
        "proc anova; class g; model y=g / nouni; run;",
        "proc anova; class g; model y=g / int; run;",
        "proc anova; class g; model y=g x; run;", // continuous effect
        "proc anova; class g; model y=g; run; means g; run;", // interactive
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
    // The per-pattern dependent-variable group display is not implemented.
    try t.expectEqual(@as(u8, 2), try exitOf(a, ds, "proc anova; class g; model y1 y2=g; run;"));
    // Nothing usable: user error.
    const empty = try table(a, "z", &.{ "g", "y" }, &.{});
    try t.expectEqual(@as(u8, 1), try exitOf(a, empty, "proc anova; class g; model y=g; run;"));
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

test "ANOVA001 balanced crossing uses ANOVA SS; unbalanced multi-effect designs stay loud" {
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
    try t.expect(try anova.balanced(a, spec, d));
    var fit = try glm.fitDesign(cx, spec, d);
    defer fit.deinit(a);
    try close(16, fit.type_i[0].ss);
    try close(4, fit.type_i[1].ss);
    try close(1, fit.model.fit.sse);
    try close(21, fit.model.fit.sst);
    const text = try listing(a, ds, "proc anova; class b a; model y=b a; run;");
    try has(text, "\nb 2 1 2\n\na 2 1 2\n");
    const lopsided = try table(a, "u", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 1, 2 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 2, 2, 7 }, .{ 2, 2, 9 }, .{ 1, 2, 3 } });
    try t.expectEqual(@as(u8, 2), try exitOf(a, lopsided, "proc anova; class a b; model y=a b; run;"));
    const hole = try table(a, "h", &.{ "a", "b", "y" }, &.{ .{ 1, 1, 1 }, .{ 1, 2, 2 }, .{ 2, 1, 4 }, .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 2, 1, 6 } });
    try t.expectEqual(@as(u8, 2), try exitOf(a, hole, "proc anova; class a b; model y=a b; run;"));
}
