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
        "proc plm restore=BlockAnalysis; show fit parms; run;",
        "proc plm restore=BlockAnalysis; test a b a*b; run;",
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
