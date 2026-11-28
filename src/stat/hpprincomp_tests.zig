//! STAT-HPPRINCOMP-001 permanent tests: PROC statement options, variable
//! roles, HP observation selection and counting (missing values, FREQ,
//! WEIGHT), BY boundaries, documented invalid input and loud boundaries.
//! All data are invented (D-011). Expected values are hand mathematics
//! (stated next to each check) or SAS 9.4 listings of the same invented data,
//! never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const hp = @import("hpprincomp.zig");
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
// columns: 0 g, 1 x, 2 y, 3 f, 4 w, 5 cc (char)
const Row = struct { g: f64, x: f64, y: f64, f: f64, w: f64 };
const sample = [_]Row{
    .{ .g = 1, .x = 1, .y = 2, .f = 1, .w = 1 },
    .{ .g = 1, .x = 2, .y = 1, .f = 2, .w = 0.5 },
    .{ .g = 1, .x = 3, .y = 4, .f = 0.5, .w = 0 }, // truncated FREQ 0, WEIGHT 0
    .{ .g = 1, .x = 4, .y = 3, .f = 2.7, .w = 1 }, // FREQ integer portion 2
    .{ .g = 1, .x = nan, .y = 5, .f = 1, .w = 1 }, // missing VAR value
    .{ .g = 1, .x = 5, .y = 2, .f = 1, .w = 2 },
    .{ .g = 2, .x = 5, .y = 5, .f = 1, .w = -1 }, // negative WEIGHT
    .{ .g = 2, .x = 6, .y = 7, .f = 1, .w = 1 },
    .{ .g = 2, .x = 7, .y = 6, .f = 1, .w = nan }, // missing WEIGHT: nonpositive class
    .{ .g = 2, .x = 8, .y = 9, .f = 1, .w = 1 },
};

fn build(a: A, lib: *Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "y", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
    _ = try ds.addColumn("cc", .char);
    for (sample) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .num = r.x }, .{ .num = r.y }, .{ .num = r.f }, .{ .num = r.w }, .{ .str = "a" } });
    try lib.put("sample", ds);
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        try build(a, &self.lib);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !hp.Spec {
        return hp.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return hp.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn logHas(self: *Env, text: []const u8) !bool {
        return std.mem.indexOf(u8, try self.diags.render(), text) != null;
    }
};

test "STAT-HPPRINCOMP-001 PROC statement defaults, explicit options, aliases and last-wins repeats" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // pp.4950-4954 defaults: last data set, METHOD=EIG, correlation, intercept,
    // N unset, PREFIX=Prin, PARPREFIX=R_, SINGULAR=1E-8, VARDEF=DF.
    const d = try e.parse("proc hpprincomp; run;");
    try expect(!d.cov and !d.noint and !d.standard and !d.noprint and d.method == .eig);
    try expect(d.out == null and d.outstat == null and d.n == null and d.freq == null and d.weight == null);
    try std.testing.expectEqualStrings("Prin", d.prefix);
    try std.testing.expectEqualStrings("R_", d.parprefix);
    try expectEqual(@as(f64, 1e-8), d.singular);
    try expectEqual(princomp.VarDef.df, d.vardef);
    // Without VAR: every numeric variable not in another statement (p.4958).
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4 }, d.vars);

    const s = try e.parse("proc hpprincomp data=work.sample out=o outstat=st covariance noint n=2 standard prefix=Abc rprefix=Q sing=0.001 vardef=wgt noprint method=nipals(maxiter=10); by g; var x y; freq f; weight w; id g; run;");
    try expect(s.cov and s.noint and s.standard and s.noprint and s.method == .nipals);
    try expectEqual(@as(?usize, 2), s.n);
    try std.testing.expectEqualStrings("Abc", s.prefix);
    try std.testing.expectEqualStrings("Q", s.parprefix);
    try expectEqual(princomp.VarDef.weight, s.vardef);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, s.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(?usize, 3), s.freq);
    try expectEqual(@as(?usize, 4), s.weight);
    try std.testing.expectEqualStrings("Y", (try e.parse("proc hpprincomp data=sample pprefix=Y; run;")).parprefix);
    try expect((try e.parse("proc hpprincomp data=sample method=itergs; run;")).method == .itergs);
    // SAS 9.4: `n=1 n=2` analyses with two components (the last one wins).
    try expectEqual(@as(?usize, 2), (try e.parse("proc hpprincomp data=sample n=1 n=2; run;")).n);
    // Default VAR list excludes BY, FREQ, WEIGHT and ID variables.
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, (try e.parse("proc hpprincomp data=sample; by g; freq f; weight w; run;")).vars);
}

test "STAT-HPPRINCOMP-001 invalid input is a user error (rc 1), not a gap" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const cases = [_][2][]const u8{
        .{ "proc hpprincomp data=sample; var x cc; run;", "Variable cc in list does not match type prescribed for this list." },
        .{ "proc hpprincomp data=sample; var x; var y; run;", "Only one VAR statement can be specified." },
        .{ "proc hpprincomp data=sample; freq cc; run;", "Variable cc in list does not match type prescribed for this list." },
        .{ "proc hpprincomp data=sample n=-1; run;", "N= must be an integer" },
        .{ "proc hpprincomp data=sample singular=1; run;", "SINGULAR= must be a number between 0 and 1" },
        .{ "proc hpprincomp data=sample vardef=xx; run;", "VARDEF= must be" },
        .{ "proc hpprincomp data=sample method=pca; run;", "METHOD= must be" },
        .{ "proc hpprincomp data=nosuch; run;", "input data set not found" },
        .{ "proc hpprincomp data=sample; var nosuch; run;", "Variable nosuch not found." },
        .{ "proc hpprincomp data=sample bogus; run;", "invalid statement or token bogus" },
    };
    for (cases) |c| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, e.parse(c[0]));
        try expect(try e.logHas(c[1]));
        try expect(!diag.gapHit());
    }
}

test "STAT-HPPRINCOMP-001 observation selection and Read/Used counts" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const s = try e.parse("proc hpprincomp data=sample; var x y; freq f; weight w; run;");
    const ds = s.input.ds;
    var c: hp.Counts = .{};
    const g1 = ds.rows.items[0..6];
    const sel = try hp.select(a, s, g1, &c);
    // Group 1: rows 0,1,3,5 used (row 2 truncated FREQ / zero WEIGHT, row 4
    // missing x). Read FREQ = 1+2+2+1+1 (row 2 truncates to 0) = 7; used
    // 1+2+2+1 = 6. Read FREQ*WEIGHT over positive weights 1+1+2+1+2 = 7;
    // used 1+1+2+2 = 6 (the same as the SAS listing of this shape).
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 5 }, sel.rows);
    try expectEqual(@as(usize, 6), c.read);
    try expectEqual(@as(usize, 4), c.used);
    try expectEqual(@as(f64, 7), c.freq_read);
    try expectEqual(@as(f64, 6), c.freq_used);
    try expectEqual(@as(f64, 7), c.weight_read);
    try expectEqual(@as(f64, 6), c.weight_used);
    try expectEqual(@as(usize, 1), c.missing);
    try expectEqual(@as(usize, 1), c.nonpositive);
    // Group 2: row 6 negative WEIGHT and row 8 missing WEIGHT are both
    // "nonpositive weight or truncated frequency" (SAS 9.4 log of this shape).
    _ = try hp.select(a, s, ds.rows.items[6..10], &c);
    try expectEqual(@as(usize, 2), c.used);
    try expectEqual(@as(usize, 0), c.missing);
    try expectEqual(@as(usize, 2), c.nonpositive);
    try expectEqual(@as(f64, 4), c.freq_read);
    try expectEqual(@as(f64, 2), c.weight_read);
    // Weighted moments through the shared kernel, VARDEF=WDF: group 1 x
    // with FREQ*WEIGHT 1,1,2,2: mean (1+2+8+10)/6 = 3.5, CSS 13.5, divisor 5,
    // StD sqrt(2.7) = 1.64317 (SAS listing value).
    var k = princomp.Spec{ .input = s.input, .vars = s.vars, .freq = s.freq, .weight = s.weight, .vardef = .wdf };
    const m = (try princomp.moments(a, k, g1, sel)).?;
    try approx(@as(f64, 3.5), m.mean[0], 1e-12);
    try approx(@sqrt(2.7), m.std[0], 1e-12);
    k.vardef = .weight;
    try approx(@sqrt(13.5 / 6.0), (try princomp.moments(a, k, g1, sel)).?.std[0], 1e-12);
}

test "STAT-HPPRINCOMP-001 log: omission warnings, BY note and all-missing error" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc hpprincomp data=sample noprint; by g; var x y; freq f; weight w; run;");
    try expect(out.items.len == 0);
    try expect(try e.logHas("The HPPRINCOMP procedure is executing in single-machine mode."));
    try expect(try e.logHas("1 observations omitted due to missing values."));
    try expect(try e.logHas("1 observations omitted due to nonpositive weight or truncated frequency."));
    try expect(try e.logHas("2 observations omitted due to nonpositive weight or truncated frequency."));
    try expect(try e.logHas("The above message was for the following BY group:\n      g=2"));
    try expect(e.diags.warning_status and !e.diags.hasErrors());

    // Every observation unusable: SAS prints the information tables, then errors.
    var e2: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e2.arena.deinit();
    try e2.init();
    var out2: std.ArrayList(u8) = .empty;
    diag.resetGap();
    try std.testing.expectError(error.ParseError, e2.run(&out2, "proc hpprincomp data=sample; var x y; where x > 100; run;"));
    try expect(try e2.logHas("All observations in the data set have missing values, or the sum of weights or frequencies is nonpositive."));
    try expect(std.mem.indexOf(u8, out2.items, "Data Access Information") != null);
    try expect(!diag.gapHit());
}

test "STAT-HPPRINCOMP-001 loud gaps for valid but unimplemented requests" {
    const cases = [_][]const u8{
        "proc hpprincomp data=sample cov; var x y; run;",
        "proc hpprincomp data=sample noint; var x y; run;",
        "proc hpprincomp data=sample out=o; var x y; run;",
        "proc hpprincomp data=sample outstat=o; var x y; run;",
        "proc hpprincomp data=sample method=itergs; var x y; run;",
        "proc hpprincomp data=sample n=0; var x y; run;",
        "proc hpprincomp data=sample; var x; partial y; run;",
        "proc hpprincomp data=sample; var x y; code file='a.sas'; run;",
        "proc hpprincomp data=sample; var x y; output out=o; run;",
        "proc hpprincomp data=sample; var x y; performance nthreads=1; run;",
        "proc hpprincomp data=sample; var x g; where g = 1; run;", // zero variance
    };
    for (cases) |c| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try std.testing.expectError(error.ParseError, e.run(&out, c));
        try expect(diag.gapHit());
        try expect(out.items.len == 0);
    }
}
