//! Permanent STAT-PLM-001 checks, S154 physical pp.7628–7632. No temporary
//! oracle file is read. The listing contract uses the published PLM "Getting
//! Started" block design (classes block/a/b, model y = block a b a*b); the
//! expected text is the SAS listing shape for that store, with the creation
//! instant fixed at 1795525564 s = 24NOV2026 13:06:04 UTC
//! (20781 days * 86400 + 13*3600 + 6*60 + 4) so the test is deterministic.
//! Coefficients/covariance are placeholders: nothing in this ticket reads them.
const std = @import("std");
const t = std.testing;
const plm = @import("plm.zig");
const store = @import("store.zig");
const glm = @import("glm.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const Library = @import("../exec.zig").Library;
const Dataset = @import("../dataset.zig").Dataset;

fn levels(a: std.mem.Allocator, n: usize) ![]const store.Level {
    const out = try a.alloc(store.Level, n);
    for (out, 0..) |*l, i| l.* = .{ .number = @floatFromInt(i + 1), .label = try std.fmt.allocPrint(a, "{d}", .{i + 1}) };
    return out;
}
fn blockModel(a: std.mem.Allocator, label: []const u8) !store.Model {
    const p = 9;
    const covariance = try a.alloc(f64, p * p);
    @memset(covariance, 0);
    for (0..p) |i| covariance[i * p + i] = 1;
    const coefficients = try a.alloc(f64, p);
    @memset(coefficients, 1);
    const classes = try a.dupe(store.Class, &.{ .{ .name = "block", .levels = try levels(a, 4) }, .{ .name = "a", .levels = try levels(a, 3) }, .{ .name = "b", .levels = try levels(a, 2) } });
    const effects = try a.dupe(store.Effect, &.{
        .{ .name = "block", .start = 1, .len = 3, .factors = &.{.{ .name = "block", .class_index = 0 }} },
        .{ .name = "a", .start = 4, .len = 2, .factors = &.{.{ .name = "a", .class_index = 1 }} },
        .{ .name = "b", .start = 6, .len = 1, .factors = &.{.{ .name = "b", .class_index = 2 }} },
        .{ .name = "a*b", .start = 7, .len = 2, .factors = &.{ .{ .name = "a", .class_index = 1 }, .{ .name = "b", .class_index = 2 } } },
    });
    return .{ .procedure = "GLM", .input = "BlockDesign", .response = "y", .label = label, .created_unix_seconds = 1795525564, .intercept = true, .effects = effects, .classes = classes, .covariates = &.{}, .coefficients = coefficients, .covariance = covariance, .df_error = 15, .mse = 21.666666666666668, .n_used = 24 };
}
const Session = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    d: diag.Diagnostics = undefined,
    fn init(self: *Session) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.d = diag.Diagnostics.init(a);
        try store.save(self.cx(), .{ .name = "work.BlockAnalysis", .label = "PLM: Getting Started" }, try blockModel(a, "PLM: Getting Started"));
    }
    fn cx(self: *Session) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.d };
    }
    fn run(self: *Session, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        const c = self.cx();
        try plm.run(c, &out, try lex.tokenize(c.arena, source, c.diags));
        return out.items;
    }
    fn options(self: *Session, source: []const u8) !plm.Options {
        const c = self.cx();
        return plm.parse(c, try lex.tokenize(c.arena, source, c.diags));
    }
};
/// Compares complete listings line by line with only trailing blanks removed
/// (SAS pads table cells), so indentation and column positions stay checked.
fn sameListing(expected: []const u8, actual: []const u8) !void {
    var trimmed: [2]std.ArrayList(u8) = .{ .empty, .empty };
    defer for (&trimmed) |*list| list.deinit(t.allocator);
    for ([_][]const u8{ expected, actual }, &trimmed) |text, *list| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            try list.appendSlice(t.allocator, std.mem.trimEnd(u8, line, " "));
            try list.append(t.allocator, '\n');
        }
    }
    try t.expectEqualStrings(trimmed[0].items, trimmed[1].items);
}
const store_information =
    \\                Store Information
    \\
    \\Item Store               WORK.BLOCKANALYSIS
    \\Label                    PLM: Getting Started
    \\Data Set Created From    WORK.BLOCKDESIGN
    \\Created By               PROC GLM
    \\Date Created             24NOV26:13:06:04
    \\Response Variable        y
    \\Class Variables          block a b
    \\Model Effects            Intercept block a b a*b
    \\
    \\
;
const class_levels =
    \\  Class Level Information
    \\
    \\Class    Levels    Values
    \\
    \\block         4    1 2 3 4
    \\a             3    1 2 3
    \\b             2    1 2
    \\
    \\
;

test "STAT-PLM-001 default listing: Store Information and Class Level Information from a native store" {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    try sameListing("The PLM Procedure\n\n" ++ store_information ++ "\n" ++ class_levels, try s.run("proc plm restore=work.BlockAnalysis; run;"));
    // One-level names default to WORK; names are case-insensitive.
    try sameListing("The PLM Procedure\n\n" ++ store_information ++ "\n" ++ class_levels, try s.run("PROC PLM RESTORE=blockanalysis;"));
    try t.expect(!s.d.hasErrors());
}

test "STAT-PLM-001 NOINFO, NOCLPRINT and NOPRINT select the displayed tables" {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    try sameListing("The PLM Procedure\n\n" ++ class_levels, try s.run("proc plm restore=BlockAnalysis noinfo; run;"));
    try sameListing("The PLM Procedure\n\n" ++ store_information, try s.run("proc plm noclprint restore=BlockAnalysis; run;"));
    try t.expectEqualStrings("", try s.run("proc plm restore=BlockAnalysis noprint; run;"));
    try t.expectEqualStrings("", try s.run("proc plm restore=BlockAnalysis noinfo noclprint; run;"));
    // Options that only steer later statements leave the default listing unchanged.
    try sameListing("The PLM Procedure\n\n" ++ store_information ++ "\n" ++ class_levels, try s.run("proc plm restore=BlockAnalysis seed=3 alpha=0.1 ddfmethod=none stmtorder=group format=noload plots=none maxlen=64; run;"));
    try t.expect(!s.d.hasErrors());
}

test "STAT-PLM-001 a store without CLASS effects or label omits those rows and the class table" {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    const a = s.arena.allocator();
    const m: store.Model = .{ .procedure = "GLM", .input = "lines", .response = "y", .label = "", .created_unix_seconds = 0, .intercept = true, .effects = &.{.{ .name = "x", .start = 1, .len = 1, .factors = &.{.{ .name = "x" }} }}, .classes = &.{}, .covariates = &.{.{ .name = "x", .mean = 2 }}, .coefficients = &.{ 1, 2 }, .covariance = &.{ 1, 0, 0, 1 }, .df_error = 3, .mse = 1, .n_used = 5 };
    try store.save(s.cx(), .{ .name = "work.line" }, m);
    const out = try s.run("proc plm restore=line; run;");
    var words: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, out, " \n");
    while (it.next()) |w| {
        try words.appendSlice(a, w);
        try words.append(a, ' ');
    }
    try t.expectEqualStrings("The PLM Procedure Store Information Item Store WORK.LINE Data Set Created From WORK.LINES Created By PROC GLM Date Created 01JAN70:00:00:00 Response Variable y Model Effects Intercept x ", words.items);
}

test "STAT-PLM-001 PROC statement options: defaults and explicit settings" {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    const d = try s.options("proc plm restore=lib1.fit; run;");
    try t.expectEqualStrings("lib1.fit", d.restore);
    try t.expectEqual(@as(?f64, null), d.seed);
    try t.expectEqual(@as(?f64, null), d.alpha);
    try t.expectEqual(@as(?plm.DdfMethod, null), d.ddfmethod);
    try t.expectEqual(@as(?plm.StatementOrder, null), d.statement_order);
    try t.expectEqual(@as(?plm.Plots, null), d.plots);
    try t.expectEqual(@as(usize, 100), d.maxlen);
    try t.expectEqual(@as(usize, 0), d.percentiles.len);
    try t.expect(d.format_reload and !d.whereformat and !d.noclprint and !d.noinfo and !d.noprint and !d.unpack);
    try t.expect(d.esteps == null and d.singchol == null and d.singres == null and d.singular == null and d.zeta == null);
    try t.expect(!s.d.hasErrors());
}

test "STAT-PLM-001 explicit option values and aliases" {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    const e = try s.options("proc plm seed=42 stmt=syntax format=NoLoad whereformat alpha=.01 ddfmethod=error percentile=2.5, 50 97.5 maxlen=20 noclprint noinfo noprint plots(unpack)=(all) esteps=1e-5 singchol=1e-11 singres=1e-10 singular=1e-9 zeta=1e-7 restore=Fit; run;");
    try t.expectEqualStrings("Fit", e.restore);
    try t.expectEqual(@as(?f64, 42), e.seed);
    try t.expectEqual(@as(?plm.StatementOrder, .syntax), e.statement_order);
    try t.expectEqual(@as(?f64, 0.01), e.alpha);
    try t.expectEqual(@as(?plm.DdfMethod, .residual), e.ddfmethod);
    try t.expectEqualSlices(f64, &.{ 2.5, 50, 97.5 }, e.percentiles);
    try t.expectEqual(@as(usize, 20), e.maxlen);
    try t.expect(!e.format_reload and e.whereformat and e.noclprint and e.noinfo and e.noprint and e.unpack);
    try t.expectEqual(@as(?plm.Plots, .all), e.plots);
    try t.expectEqual(@as(?f64, 1e-5), e.esteps);
    try t.expectEqual(@as(?f64, 1e-11), e.singchol);
    try t.expectEqual(@as(?f64, 1e-10), e.singres);
    try t.expectEqual(@as(?f64, 1e-9), e.singular);
    try t.expectEqual(@as(?f64, 1e-7), e.zeta);
    inline for (.{ .{ "kr", plm.DdfMethod.kenward_roger }, .{ "KenwardRoger", plm.DdfMethod.kenward_roger }, .{ "kenrog", plm.DdfMethod.kenward_roger }, .{ "sat", plm.DdfMethod.satterthwaite }, .{ "satterth", plm.DdfMethod.satterthwaite }, .{ "satterthwaite", plm.DdfMethod.satterthwaite }, .{ "res", plm.DdfMethod.residual }, .{ "residual", plm.DdfMethod.residual }, .{ "none", plm.DdfMethod.none } }) |case| {
        const o = try s.options("proc plm restore=f ddfmethod=" ++ case[0] ++ " stmtorder=group format=reload plot=none;");
        try t.expectEqual(@as(?plm.DdfMethod, case[1]), o.ddfmethod);
        try t.expectEqual(@as(?plm.StatementOrder, .group), o.statement_order);
    }
    try t.expect(!s.d.hasErrors());
}

fn expectFailure(source: []const u8, expected: anyerror, rc: u8) !void {
    var s: Session = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try s.init();
    diag.resetGap();
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    const c = s.cx();
    const result = plm.run(c, &out, try lex.tokenize(c.arena, source, c.diags));
    t.expectError(expected, result) catch |err| {
        std.debug.print("unexpected result for: {s}\n", .{source});
        return err;
    };
    // Fail loud and never leave a partial listing behind.
    try t.expect(s.d.hasErrors());
    try t.expectEqual(@as(usize, 0), out.items.len);
    t.expectEqual(rc, diag.exitCode(diag.gapHit(), s.d.hasErrors())) catch |err| {
        std.debug.print("unexpected exit class for: {s}\n", .{source});
        return err;
    };
}

test "STAT-PLM-001 invalid declarations are user errors (rc 1) through the captured reporter" {
    for ([_][]const u8{
        "proc plm; run;",
        "proc plm noinfo; run;",
        "proc plm restore; run;",
        "proc plm restore=; run;",
        "proc plm restore='x'; run;",
        "proc plm restore=work.; run;",
        "proc plm restore=BlockAnalysis bogus; run;",
        "proc plm restore=BlockAnalysis data=x; run;",
        "proc plm restore=BlockAnalysis alpha=0; run;",
        "proc plm restore=BlockAnalysis alpha=1; run;",
        "proc plm restore=BlockAnalysis alpha=-0.5; run;",
        "proc plm restore=BlockAnalysis alpha; run;",
        "proc plm restore=BlockAnalysis alpha=x; run;",
        "proc plm restore=BlockAnalysis seed=1.5; run;",
        "proc plm restore=BlockAnalysis ddfmethod=between; run;",
        "proc plm restore=BlockAnalysis stmtorder=random; run;",
        "proc plm restore=BlockAnalysis format=keep; run;",
        "proc plm restore=BlockAnalysis percentiles=0; run;",
        "proc plm restore=BlockAnalysis percentiles=50 100; run;",
        "proc plm restore=BlockAnalysis percentiles=; run;",
        "proc plm restore=BlockAnalysis maxlen=30.5; run;",
        "proc plm restore=BlockAnalysis plots=residuals; run;",
        "proc plm restore=BlockAnalysis plots(only)=all; run;",
        "proc plm restore=BlockAnalysis; model y=a; run;",
        "proc plm restore=BlockAnalysis; class a; run;",
    }) |source| try expectFailure(source, error.ParseError, 1);
    // Execution prerequisites: a missing store or unassigned library.
    try expectFailure("proc plm restore=NoSuchStore; run;", error.ExecError, 1);
    try expectFailure("proc plm restore=nolib.BlockAnalysis; run;", error.ExecError, 1);
}

test "STAT-PLM-001 valid but unimplemented requests are loud gaps (rc 2) with no listing" {
    for ([_][]const u8{
        "proc plm restore=BlockAnalysis; show all; run;",
        "proc plm restore=BlockAnalysis; show parms fit; run;",
        "proc plm restore=BlockAnalysis; show; run;",
        "proc plm restore=BlockAnalysis; test; run;",
        "proc plm restore=BlockAnalysis; test a / chisq; run;",
        "proc plm restore=BlockAnalysis stmtorder=group; test a; run;",
        "proc plm restore=BlockAnalysis noprint; show fit; run;",
        "proc plm restore=BlockAnalysis; lsmeans a / diff; run;",
        "proc plm restore=BlockAnalysis; lsmestimate a -1 1; run;",
        "proc plm restore=BlockAnalysis; slice a*b / sliceby(b='1') diff; run;",
        "proc plm restore=BlockAnalysis; estimate 'a1' a 1 -1; run;",
        "proc plm restore=BlockAnalysis; score data=x out=y; run;",
        "proc plm restore=BlockAnalysis; effectplot; run;",
        "proc plm restore=BlockAnalysis; code; run;",
        "proc plm restore=BlockAnalysis; filter a=1; run;",
        "proc plm restore=BlockAnalysis; where a=1; run;",
        "proc plm restore=BlockAnalysis; by a; run;",
        "proc plm restore=BlockAnalysis noprint; show all; run;",
        "proc plm restore=BlockAnalysis seed=0; run;",
        "proc plm restore=BlockAnalysis seed=-7; run;",
        "proc plm restore=BlockAnalysis noclprint=3; run;",
        "proc plm restore=BlockAnalysis maxlen=19; run;",
        "proc plm restore=BlockAnalysis maxlen=257; run;",
        // "Intercept block a b a*b" is 23 characters: truncated display is unverified.
        "proc plm restore=BlockAnalysis maxlen=20; run;",
        "proc plm restore=BlockAnalysis ddfmethod=kr; run;",
        "proc plm restore=BlockAnalysis ddfmethod=satterthwaite; run;",
        "proc plm restore=BlockAnalysis restore=BlockAnalysis; run;",
        "proc plm restore=BlockAnalysis alpha=0.1 alpha=0.2; run;",
        "proc plm restore=BlockAnalysis noinfo noinfo; run;",
        "proc plm restore=BlockAnalysis stmt=group stmtorder=syntax; run;",
    }) |source| try expectFailure(source, error.ParseError, 2);
}

test "STAT-PLM-001 restores a store written by PROC GLM STORE in the same session" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Invented 12-row design: two-level CLASS plus a covariate.
    var ds = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("y", .num);
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    for (y, 0..) |v, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .str = if (i < 6) "A" else "B" }, .{ .num = v } });
    var lib = Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var glm_out: std.ArrayList(u8) = .empty;
    try glm.run(cx, &glm_out, try lex.tokenize(a, "proc glm data=sample noprint; class group; model y=group x; store fitted / label='A stored fit'; run;", &d));
    var out: std.ArrayList(u8) = .empty;
    try plm.run(cx, &out, try lex.tokenize(a, "proc plm restore=work.fitted; run;", &d));
    try t.expect(!d.hasErrors());
    var words: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, out.items, " \n");
    var index: usize = 0;
    while (it.next()) |w| : (index += 1) {
        // The creation instant is the wall clock; check its shape only.
        if (index == 23) {
            try t.expectEqual(@as(usize, 16), w.len);
            try t.expect(w[7] == ':' and w[10] == ':' and w[13] == ':');
            continue;
        }
        try words.appendSlice(a, w);
        try words.append(a, ' ');
    }
    try t.expectEqualStrings("The PLM Procedure Store Information Item Store WORK.FITTED Label A stored fit Data Set Created From WORK.SAMPLE Created By PROC GLM Date Created Response Variable y Class Variables group Model Effects Intercept group x Class Level Information Class Levels Values group 2 A B ", words.items);
}

// ---- STAT-PLM-002: stored-model inference (S154 physical pp.7620–7623) ----
// Expected block-design text is the SAS listing of the published Getting
// Started example (SHOW FIT PARMS; TEST a b a*b;), held here verbatim; the
// fixture never reads the temporary reference directory.
const block_y = [_]f64{ 56, 41, 50, 36, 39, 35, 30, 25, 36, 28, 33, 30, 32, 24, 31, 27, 15, 19, 30, 25, 35, 30, 17, 18 };
const block_inference =
    \\
    \\   Fit Statistics
    \\
    \\MSE         21.66667
    \\Error df          15
    \\
    \\
    \\                Parameter Estimates
    \\
    \\                                            Standard
    \\Effect       block    a    b    Estimate       Error
    \\
    \\Intercept                        20.4167      2.8504
    \\block        1                   17.0000      2.6874
    \\block        2                    4.5000      2.6874
    \\block        3                   -1.1667      2.6874
    \\block        4                         0           .
    \\a                     1           3.2500      3.2914
    \\a                     2           4.7500      3.2914
    \\a                     3                0           .
    \\b                          1      0.5000      3.2914
    \\b                          2           0           .
    \\a*b                   1    1      7.7500      4.6547
    \\a*b                   1    2           0           .
    \\a*b                   2    1      7.2500      4.6547
    \\a*b                   2    2           0           .
    \\a*b                   3    1           0           .
    \\a*b                   3    2           0           .
    \\
    \\
    \\        Type III Tests of Model Effects
    \\
    \\              Num      Den
    \\Effect         DF       DF    F Value    Pr > F
    \\
    \\a               2       15       7.54    0.0054
    \\b               1       15       8.38    0.0111
    \\a*b             2       15       1.74    0.2097
    \\
    \\
;
const Fitted = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    d: diag.Diagnostics = undefined,
    fn cx(self: *Fitted) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.d };
    }
    fn exec(self: *Fitted, comptime which: enum { glm, plm }, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        const c = self.cx();
        const tokens = try lex.tokenize(c.arena, source, c.diags);
        if (which == .glm) try glm.run(c, &out, tokens) else try plm.run(c, &out, tokens);
        return out.items;
    }
};
fn blockFit(s: *Fitted) !void {
    const a = s.arena.allocator();
    s.lib = Library.init(a);
    s.d = diag.Diagnostics.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "BlockDesign");
    for ([_][]const u8{ "block", "a", "b", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (block_y, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 6 + 1) }, .{ .num = @floatFromInt(i / 2 % 3 + 1) }, .{ .num = @floatFromInt(i % 2 + 1) }, .{ .num = y } });
    try s.lib.put("BlockDesign", ds);
    _ = try s.exec(.glm, "proc glm data=BlockDesign noprint; class block a b; model y = block a b a*b; store work.BlockAnalysis; run;");
}

test "STAT-PLM-002 Getting Started: SHOW FIT PARMS and TEST from a GLM store match the SAS listing" {
    var s: Fitted = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try blockFit(&s);
    const out = try s.exec(.plm, "proc plm restore=work.BlockAnalysis noinfo; show fit parms; test a b a*b; run;");
    try t.expect(!s.d.hasErrors());
    try sameListing("The PLM Procedure\n\n" ++ class_levels ++ block_inference, out);
    // PARAMETERS is the documented alias; one table per request, syntax order.
    const split = try s.exec(.plm, "proc plm restore=BlockAnalysis noinfo noclprint; test a*b; show parameters; run;");
    try t.expect(std.mem.indexOf(u8, split, "Type III Tests").? < std.mem.indexOf(u8, split, "Parameter Estimates").?);
    try t.expect(std.mem.indexOf(u8, split, "Fit Statistics") == null);
    try t.expect(std.mem.indexOf(u8, split, "a*b             2       15       1.74    0.2097") != null);
}

test "STAT-PLM-002 block design: unrounded estimates and F statistics against exact rational values" {
    // Balanced design, so every quantity is a closed form of cell/marginal
    // means: MSE = 325/15; SE(block i) = sqrt(2 MSE/6); F = SS/df/MSE with
    // SS(a)=326.58333.., SS(b)=181.5, SS(a*b)=75.25 (hand ANOVA of the data).
    var s: Fitted = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    try blockFit(&s);
    const infer = @import("plm_infer.zig");
    const m = try store.restore(s.cx(), "work.BlockAnalysis");
    const mse = 325.0 / 15.0;
    const parms = try infer.parameters(s.arena.allocator(), m);
    try t.expectEqual(@as(usize, 16), parms.len);
    // 1e-9 absolute: values are O(10..100) from a 9-parameter least-squares
    // solve with condition number < 1e3; double rounding is ~1e-13.
    const tol = 1e-9;
    try t.expectApproxEqAbs(@as(f64, 245.0 / 12.0), parms[0].estimate, tol);
    try t.expectApproxEqAbs(@as(f64, 17), parms[1].estimate, tol);
    try t.expectApproxEqAbs(@sqrt(2.0 * mse / 6.0), parms[1].stderr.?, tol);
    try t.expectApproxEqAbs(@as(f64, -7.0 / 6.0), parms[3].estimate, tol);
    try t.expect(parms[4].stderr == null and parms[4].estimate == 0);
    try t.expectApproxEqAbs(@as(f64, 7.75), parms[10].estimate, tol);
    try t.expectApproxEqAbs(@sqrt(4.0 * mse / 4.0), parms[10].stderr.?, tol);
    const expected = [_]struct { usize, f64 }{ .{ 1, 3919.0 / 12.0 / 2.0 / mse }, .{ 2, 181.5 / mse }, .{ 3, 75.25 / 2.0 / mse } };
    for (expected) |e| {
        const r = try infer.type3(s.arena.allocator(), m, e[0]);
        try t.expectEqual(@as(usize, 15), r.den_df);
        try t.expectApproxEqAbs(e[1], r.f, tol);
    }
}

test "STAT-PLM-002 smaller case with an independent manual calculation" {
    // y = {1,3} in group 1 and {4,8} in group 2. Means 2 and 6; SSE = 2 + 8 =
    // 10 on 2 df, MSE = 5. GLM parameters: Intercept = mean(2) = 6 with
    // SE sqrt(5/2) = 1.5811; g 1 = 2 - 6 = -4 with SE sqrt(5/2 + 5/2) = 2.2361;
    // g 2 = 0. SS(g) = 2*(2-4)^2 + 2*(6-4)^2 = 16, F = 16/5 = 3.20 on (1,2) df;
    // t = sqrt(3.2), Pr = 1 - t/sqrt(t^2 + 2) = 1 - sqrt(3.2/5.2) = 0.2155.
    var s: Fitted = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer s.arena.deinit();
    const a = s.arena.allocator();
    s.lib = Library.init(a);
    s.d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "two");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 4 }, .{ 2, 8 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
    try s.lib.put("two", &ds);
    _ = try s.exec(.glm, "proc glm data=two noprint; class g; model y = g; store small; run;");
    const out = try s.exec(.plm, "proc plm restore=small noinfo noclprint; show fit parms; test g; run;");
    try t.expect(!s.d.hasErrors());
    var words: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, out, " \n");
    while (it.next()) |w| {
        try words.appendSlice(a, w);
        try words.append(a, ' ');
    }
    try t.expectEqualStrings("The PLM Procedure Fit Statistics MSE 5 Error df 2 Parameter Estimates Standard Effect g Estimate Error Intercept 6.0000 1.5811 g 1 -4.0000 2.2361 g 2 0 . Type III Tests of Model Effects Num Den Effect DF DF F Value Pr > F g 1 2 3.20 0.2155 ", words.items);
    const r = try @import("plm_infer.zig").type3(a, try store.restore(s.cx(), "small"), 0);
    try t.expectApproxEqAbs(@as(f64, 3.2), r.f, 1e-12);
    try t.expectApproxEqAbs(1.0 - @sqrt(3.2 / 5.2), r.p, 1e-12);
}

test "STAT-PLM-002 unsupported stored-model inference is a loud gap with no listing" {
    // Covariate store: the CLASS-grid mapping does not apply. Unknown TEST
    // effect: user error. Both go through the captured reporter.
    for ([_]struct { []const u8, u8 }{
        .{ "proc plm restore=cov; show parms; run;", 2 },
        .{ "proc plm restore=cov; test g; run;", 2 },
        .{ "proc plm restore=cov; test nosuch; run;", 1 },
    }) |case| {
        var s: Fitted = .{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
        defer s.arena.deinit();
        const a = s.arena.allocator();
        s.lib = Library.init(a);
        s.d = diag.Diagnostics.init(a);
        var ds = Dataset.init(a, "lines");
        _ = try ds.addColumn("g", .num);
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("y", .num);
        for ([_][3]f64{ .{ 1, 1, 4 }, .{ 1, 2, 6 }, .{ 1, 3, 7 }, .{ 2, 1, 9 }, .{ 2, 2, 13 }, .{ 2, 3, 12 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
        try s.lib.put("lines", &ds);
        _ = try s.exec(.glm, "proc glm data=lines noprint; class g; model y = g x; store cov; run;");
        diag.resetGap();
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const c = s.cx();
        const result = plm.run(c, &out, try lex.tokenize(a, case[0], c.diags));
        try t.expect(std.meta.isError(result));
        try t.expect(s.d.hasErrors());
        try t.expectEqual(@as(usize, 0), out.items.len);
        try t.expectEqual(case[1], diag.exitCode(diag.gapHit(), s.d.hasErrors()));
    }
}
