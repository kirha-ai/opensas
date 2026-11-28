//! STAT-FACTOR-001 permanent tests: PROC statement options and aliases,
//! variable roles, observation selection and BY boundaries, the PRIORS=ONE
//! principal-component solution, and loud execution boundaries. All data are
//! invented (D-011). Expected values are hand mathematics stated next to each
//! check, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const factor = @import("factor.zig");
const princomp = @import("princomp.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const contains = struct {
    fn f(hay: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, hay, needle) != null;
    }
}.f;

const nan = std.math.nan(f64);
// x = 1..4, y = 2,1,4,3 in each of two BY groups: means 2.5, CSS 5 and
// cross product 3, so r = 0.6. R = [[1,.6],[.6,1]] has eigenvalues 1.6 and
// 0.4 with eigenvectors (1,1)/sqrt2 and (1,-1)/sqrt2.
const four_x = [_]f64{ 1, 2, 3, 4 };
const four_y = [_]f64{ 2, 1, 4, 3 };

fn build(a: A, lib: *Library) !void {
    const four = try a.create(Dataset);
    four.* = Dataset.init(a, "four");
    for ([_][]const u8{ "grp", "x", "y", "f", "w" }) |n| _ = try four.addColumn(n, .num);
    _ = try four.addColumn("id", .char);
    for (0..2) |g| for (four_x, four_y) |x, y| try four.appendRow(&.{ .{ .num = @floatFromInt(g + 1) }, .{ .num = x }, .{ .num = y }, .{ .num = 1 }, .{ .num = 1 }, .{ .str = "a" } });
    // A missing VAR value at the end of the last group: read, not used.
    try four.appendRow(&.{ .{ .num = 2 }, .{ .num = nan }, .{ .num = 9 }, .{ .num = 1 }, .{ .num = 1 }, .{ .str = "b" } });
    try lib.put("four", four);
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
    fn parse(self: *Env, source: []const u8) !factor.Spec {
        return factor.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return factor.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-FACTOR-001 PROC statement defaults, explicit options and aliases" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Defaults: most recent data set, no SIMPLE/CORR/SCORE, no N=/MINEIGEN=;
    // without VAR all numeric variables are analyzed (p.2823).
    const d = try e.parse("proc factor; run;");
    try expect(!d.simple and !d.corr and !d.score and !d.noprint);
    try expect(d.nfactors == null and d.mineigen == null);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4 }, d.vars);
    // Explicit implemented values and aliases S, C, M=, PRIOR/PRIORS=O, R=N,
    // NFACT=, N=, MIN=.
    const s = try e.parse("proc factor data=work.four s c score noprint method=prin priors=o rotate=none nfact=2; var x y; by grp; run;");
    try expect(s.simple and s.corr and s.score and s.noprint);
    try expectEqual(@as(?usize, 2), s.nfactors);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, s.vars);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(?usize, 1), (try e.parse("proc factor data=four m=p prior=one r=n n=1; run;")).nfactors);
    try expectEqual(@as(?f64, 0.5), (try e.parse("proc factor data=four min=0.5; run;")).mineigen);
    // FREQ/WEIGHT variables leave the default VAR list.
    const roles = try e.parse("proc factor data=four; freq f; weight w; run;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, roles.vars);
    try expectEqual(@as(?usize, 3), roles.freq);
    try expectEqual(@as(?usize, 4), roles.weight);
}

test "STAT-FACTOR-001 PRIORS=ONE solution and retention by hand mathematics" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const s = try e.parse("proc factor data=four; var x y; run;");
    const rows = e.lib.find("four").?.rows.items[0..4];
    const ks: princomp.Spec = .{ .input = s.input, .vars = s.vars };
    const sel = try princomp.select(a, ks, rows);
    const m = (try princomp.moments(a, ks, rows, sel)).?;
    try approx(@as(f64, 0.6), m.corr[1], 1e-12);
    const eig = try princomp.eigenSym(a, m.corr, 2);
    try approx(@as(f64, 1.6), eig.values[0], 1e-12);
    try approx(@as(f64, 0.4), eig.values[1], 1e-12);
    // Default MINEIGEN=1 keeps 1.6 only; N=2 keeps both; MINEIGEN=0.39
    // keeps both (eigenvalue >= p).
    const r = factor.retained(s, eig.values).?;
    try expectEqual(@as(usize, 1), r.count);
    try std.testing.expectEqualStrings("MINEIGEN", r.criterion);
    try expectEqual(@as(usize, 2), factor.retained(.{ .input = s.input, .nfactors = 2 }, eig.values).?.count);
    try std.testing.expectEqualStrings("NFACTOR", factor.retained(.{ .input = s.input, .nfactors = 2 }, eig.values).?.criterion);
    try expectEqual(@as(usize, 2), factor.retained(.{ .input = s.input, .mineigen = 0.39 }, eig.values).?.count);
    try expect(factor.retained(.{ .input = s.input, .nfactors = 2, .mineigen = 1 }, eig.values) == null);
    try expect(factor.retained(.{ .input = s.input, .nfactors = 3 }, eig.values) == null);
    // Loading = sqrt(1.6)/sqrt2 = sqrt(0.8); communality 0.8 each;
    // scoring coefficient = (1/sqrt2)/sqrt(1.6) = 0.5590170.
    const sol = try factor.solve(a, eig, 2, 1);
    for (0..2) |j| {
        try approx(@sqrt(0.8), sol.pattern[j], 1e-12);
        try approx(@as(f64, 0.8), sol.communality[j], 1e-12);
        try approx(@as(f64, 0.5590169943749474), sol.scoring[j], 1e-12);
    }
    // All factors: communalities 1, second loadings sqrt(0.2) with opposite signs.
    const full = try factor.solve(a, eig, 2, 2);
    try approx(@as(f64, 1), full.communality[0], 1e-12);
    try approx(@sqrt(0.2), @abs(full.pattern[1]), 1e-12);
    try approx(@as(f64, 0), full.pattern[1] + full.pattern[3], 1e-12);
}

test "STAT-FACTOR-001 listing with BY groups, missing values and SCORE" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    var out: std.ArrayList(u8) = .empty;
    try e.run(&out, "proc factor data=four simple corr score; var x y; by grp; run;");
    const text = out.items;
    // Group 2 reads 5 records and uses 4 (missing x).
    try expect(contains(text, "Number of Records Read                 4\n"));
    try expect(contains(text, "Number of Records Read                 5\nNumber of Records Used                 4\n"));
    try expect(contains(text, "Means and Standard Deviations from 4 Observations"));
    // Mean 2.5; StD sqrt(5/3) = 1.2910.
    try expect(contains(text, "x                2.500        1.2910\n"));
    try expect(contains(text, "x         1.00000         0.60000\n"));
    try expect(contains(text, "Eigenvalues of the Correlation Matrix: Total = 2  Average = 1"));
    try expect(contains(text, "   1    1.60000000    1.20000000        0.8000        0.8000\n"));
    try expect(contains(text, "1 factor will be retained by the MINEIGEN criterion."));
    try expect(contains(text, "x         0.89443\n"));
    try expect(contains(text, "Final Communality Estimates: Total = 1.600000"));
    try expect(contains(text, "0.80000000      0.80000000\n"));
    try expect(contains(text, "x         0.55902\n"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, text, "Number of Records Read"));
    try expectEqual(@as(usize, 2), std.mem.count(u8, text, "Standardized Scoring Coefficients"));
    try expect(contains(text, "grp=2"));
}

test "STAT-FACTOR-001 invalid input is a user error and unimplemented valid syntax is a loud gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors (rc 1).
        .{ .source = "proc factor data=nosuch; run;", .rc = 1 },
        .{ .source = "proc factor data=four nosuchoption; run;", .rc = 1 },
        .{ .source = "proc factor data=four method=wrong; run;", .rc = 1 },
        .{ .source = "proc factor data=four priors=wrong; run;", .rc = 1 },
        .{ .source = "proc factor data=four n=1.5; run;", .rc = 1 },
        .{ .source = "proc factor data=four mineigen=-1; var x y; run;", .rc = 1 },
        .{ .source = "proc factor data=four; var id; run;", .rc = 1 },
        .{ .source = "proc factor data=four; var nosuch; run;", .rc = 1 },
        .{ .source = "proc factor data=four; freq id; run;", .rc = 1 },
        .{ .source = "proc factor data=four; weight; run;", .rc = 1 },
        .{ .source = "proc factor data=four; model x = y; run;", .rc = 1 },
        .{ .source = "proc factor data=four; by nosuch; run;", .rc = 1 },
        .{ .source = "proc factor data=four; var x y; by descending grp; run;", .rc = 1 },
        // Valid SAS owned by later tickets or not verified (rc 2).
        .{ .source = "proc factor data=four method=ml; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four priors=smc; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four rotate=varimax; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four n=0; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four nfactors=parallel; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four proportion=0.9; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four n=1 mineigen=1; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four n=3; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four mineigen=2; var x y; run;", .rc = 2 }, // no factor retained
        .{ .source = "proc factor data=four all; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four cov; var x y; run;", .rc = 2 },
        // STAT-DATASET-001: OUTSTAT= is written for the verified default layout;
        // SCORE rows, BY groups and OUTSTAT= data set options stay loud gaps.
        .{ .source = "proc factor data=four outstat=st score; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four outstat=st; var x y; by grp; run;", .rc = 2 },
        .{ .source = "proc factor data=four outstat=st(type=corr); var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four plots=scree; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four simple simple; var x y; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x y; partial grp; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x y; priors 1 1; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x y; freq f; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x y; weight w; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x; var y; run;", .rc = 2 },
        .{ .source = "proc factor data=four; var x grp; by grp; run;", .rc = 2 }, // zero variance in a group
        .{ .source = "proc factor data=four; var x y; where grp = 1 and x > 2; run;", .rc = 2 }, // n <= p
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = factor.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expectEqual(@as(usize, 0), output.items.len);
    }
}

test "STAT-DATASET-001: OUTSTAT= TYPE=FACTOR layout (hand mathematics)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    // Group 1 only: x = 1..4, y = 2,1,4,3 -> means 2.5, STD sqrt(5/3), r = 0.6,
    // eigenvalues 1.6 / 0.4, one factor: pattern sqrt(1.6)/sqrt(2) = sqrt(0.8),
    // communality 0.8.
    try factor.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, "proc factor data=four noprint n=1 outstat=st; var x y; where grp = 1; run;", &d));
    const st = lib.find("st").?;
    try std.testing.expectEqualStrings("FACTOR", st.ds_type.?);
    try expectEqual(@as(usize, 4), st.columns.items.len);
    try std.testing.expectEqualStrings("_TYPE_", st.columns.items[0].name);
    try std.testing.expectEqualStrings("Type of Observation", st.columns.items[0].label.?);
    try std.testing.expectEqualStrings("Row Variable Name", st.columns.items[1].label.?);
    try expectEqual(@as(usize, 8), st.columns.items[1].len.?);
    const types = [_][]const u8{ "MEAN", "STD", "N", "CORR", "CORR", "COMMUNAL", "PRIORS", "EIGENVAL", "PATTERN" };
    const rows_names = [_][]const u8{ "", "", "", "x", "y", "", "", "", "Factor1" };
    const want = [_][2]f64{ .{ 2.5, 2.5 }, .{ @sqrt(5.0 / 3.0), @sqrt(5.0 / 3.0) }, .{ 4, 4 }, .{ 1, 0.6 }, .{ 0.6, 1 }, .{ 0.8, 0.8 }, .{ 1, 1 }, .{ 1.6, 0.4 }, .{ @sqrt(0.8), @sqrt(0.8) } };
    try expectEqual(types.len, st.rows.items.len);
    for (st.rows.items, types, rows_names, want) |row, ty, nm, w| {
        try std.testing.expectEqualStrings(ty, row[0].str);
        try std.testing.expectEqualStrings(nm, row[1].str);
        try approx(w[0], row[2].num, 1e-12);
        try approx(w[1], row[3].num, 1e-12);
    }
}
