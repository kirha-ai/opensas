//! STAT-FASTCLUS-001 permanent tests: PROC statement options and defaults,
//! VAR / ID / FREQ / WEIGHT / BY roles, missing values, duplicate and
//! conflicting declarations, user errors and loud gaps (asserted through the
//! captured diagnostics), and a hand-calculated k-means case. Data are
//! invented (D-011). Expected values are hand mathematics or SAS 9.4 messages
//! (stated per check), never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const fastclus = @import("fastclus.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
// columns: 0 g, 1 x, 2 y, 3 f, 4 w, 5 id
const Row = struct { g: []const u8, x: f64, y: f64, f: f64, w: f64, id: []const u8 };
const sample = [_]Row{
    .{ .g = "A", .x = 0, .y = 1, .f = 1, .w = 1, .id = "p" },
    .{ .g = "A", .x = 1, .y = 2, .f = 1, .w = 1, .id = "q" },
    .{ .g = "A", .x = 10, .y = 3, .f = 1, .w = 1, .id = "r" },
    .{ .g = "A", .x = 11, .y = 4, .f = 1, .w = 1, .id = "s" },
    .{ .g = "A", .x = nan, .y = nan, .f = 1, .w = 1, .id = "t" },
    .{ .g = "B", .x = 0, .y = 5, .f = 2, .w = 1, .id = "u" },
    .{ .g = "B", .x = 2, .y = 6, .f = 1, .w = 1, .id = "v" },
    .{ .g = "B", .x = 20, .y = 7, .f = 1, .w = 1, .id = "w" },
    .{ .g = "B", .x = 22, .y = 8, .f = 2, .w = 1, .id = "x" },
    .{ .g = "B", .x = 5, .y = 9, .f = 0, .w = 1, .id = "y" },
};

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "s");
        _ = try ds.addColumn("g", .char);
        _ = try ds.addColumn("x", .num);
        _ = try ds.addColumn("y", .num);
        _ = try ds.addColumn("f", .num);
        _ = try ds.addColumn("w", .num);
        _ = try ds.addColumn("id", .char);
        for (sample) |r| try ds.appendRow(&.{ .{ .str = r.g }, .{ .num = r.x }, .{ .num = r.y }, .{ .num = r.f }, .{ .num = r.w }, .{ .str = r.id } });
        try self.lib.put("s", ds);
        const e = try a.create(Dataset);
        e.* = Dataset.init(a, "e");
        _ = try e.addColumn("x", .num);
        try self.lib.put("e", e);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn toks(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !fastclus.Spec {
        return fastclus.parse(self.cx(), try self.toks(source));
    }
    fn run(self: *Env, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try fastclus.run(self.cx(), &out, try self.toks(source));
        return out.items;
    }
    /// The step fails; `gap` tells whether it must be a D-009 gap (rc 2) or
    /// a user error (rc 1).
    fn fails(self: *Env, source: []const u8, gap: bool) !void {
        self.diags = diag.Diagnostics.init(self.arena.allocator());
        diag.resetGap();
        if (self.run(source)) |_| return error.TestExpectedError else |_| {}
        try expect(self.diags.hasErrors());
        try expectEqual(gap, diag.gapHit());
    }
};

test "STAT-FASTCLUS-001 PROC options, aliases and defaults" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // pp.2891-2897 defaults: MAXITER=1, CONVERGE=0.02, REPLACE=FULL, CLUSTER
    // name CLUSTER; p.2900: without VAR all numeric variables not in another role.
    const d = try env.parse("proc fastclus data=s maxc=2; freq f; weight w; run;");
    try expectEqual(@as(?usize, 2), d.maxc);
    try expectEqual(@as(usize, 1), d.maxiter);
    try approx(@as(f64, 0.02), d.converge, 0);
    try expectEqual(fastclus.Replace.full, d.replace);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, d.vars);
    try std.testing.expectEqualStrings("CLUSTER", d.cluster_name);
    const e = try env.parse("proc fastclus data=s r=3 maxiter=7 conv=0.5 replace=part cluster=k nomiss short noprint variablesareuncorrelated; var y x; id id; by g; run;");
    try expectEqual(@as(?usize, null), e.maxc);
    try approx(@as(f64, 3), e.radius.?, 0);
    try expectEqual(@as(usize, 7), e.maxiter);
    try approx(@as(f64, 0.5), e.converge, 0);
    try expectEqual(fastclus.Replace.part, e.replace);
    try std.testing.expectEqualStrings("k", e.cluster_name);
    try expect(e.nomiss and e.short and e.noprint and e.uncorrelated);
    try std.testing.expectEqualSlices(usize, &.{ 2, 1 }, e.vars);
    try expectEqual(@as(?usize, 5), e.id);
    try std.testing.expectEqualSlices(usize, &.{0}, e.by_cols);
    // p.2898: only the last BY statement is used.
    const b = try env.parse("proc fastclus data=s maxclusters=2; var x; by id; by g; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, b.by_cols);
}

test "STAT-FASTCLUS-001 user errors and loud gaps via captured diagnostics" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // User errors (rc 1). SAS 9.4: "You must specify either RADIUS= or
    // MAXCLUSTERS=." and "Variable g in list does not match type prescribed".
    const user = [_][]const u8{
        "proc fastclus data=s; var x; run;",
        "proc fastclus data=s maxc=2; var g; run;",
        "proc fastclus data=s maxc=0; var x; run;",
        "proc fastclus data=s maxc=2.5; var x; run;",
        "proc fastclus data=s radius=-1; var x; run;",
        "proc fastclus data=s maxc=2 maxiter=-1; var x; run;",
        "proc fastclus data=s maxc=2 replace=bogus; var x; run;",
        "proc fastclus data=s maxc=2; var nosuch; run;",
        "proc fastclus data=s maxc=2; var x; freq g; run;",
        "proc fastclus data=s maxc=2; var x; freq f w; run;",
        "proc fastclus data=s maxc=2 bogus; var x; run;",
        "proc fastclus data=nosuch maxc=2; var x; run;",
    };
    for (user) |src| try env.fails(src, false);
    // Valid but unimplemented or unverified (rc 2).
    const gaps = [_][]const u8{
        "proc fastclus data=s maxc=2 maxc=3; var x; run;",
        "proc fastclus data=s maxc=2 maxclusters=3; var x; run;",
        "proc fastclus data=s maxc=2; var x; var y; run;",
        "proc fastclus data=s maxc=2; var x; freq f; freq f; run;",
        "proc fastclus data=s maxc=2; var x; weight w; weight w; run;",
        "proc fastclus data=s maxc=2; var x; id id; id id; run;",
        "proc fastclus data=s maxc=2; var x x; run;",
        "proc fastclus data=s maxc=2; var x f; freq f; run;",
        "proc fastclus data=s maxc=2 least=1; var x; run;",
        "proc fastclus data=s maxc=2 drift; var x; run;",
        "proc fastclus data=s maxc=2 list; var x; run;",
        "proc fastclus data=s maxc=2 replace=random; var x; run;",
        "proc fastclus data=s maxc=2 outseed=m; var x; run;",
        "proc fastclus data=s maxc=2 maxiter=0; var x; run;",
        "proc fastclus data=s maxc=2 maxiter=5; var x; weight w; run;",
        "proc fastclus data=s maxc=2 radius=1 maxiter=5; var x; run;",
        // A single cluster and an empty input data set.
        "proc fastclus data=s maxc=1 maxiter=5; var x; run;",
        "proc fastclus data=e maxc=2 maxiter=5; var x; run;",
    };
    for (gaps) |src| try env.fails(src, true);
}

test "STAT-FASTCLUS-001 hand-calculated two-cluster solution, BY groups, FREQ and OUT=" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const text = try env.run("proc fastclus data=s maxc=2 maxiter=10 out=o; var x; freq f; by g; run;");
    // Group A by hand: seeds 0 then 1; obs 10 replaces seed 1 (test 1: the
    // pair 0/1 is 1 apart, the obs is 9 away; seed 1 is the one closer to the
    // remaining seeds), obs 11 replaces 10 (test 2: 11 > 10). Initial seeds
    // 0 and 11. Iteration 1: SSE = 2 over 4 obs -> sqrt(1/2) = 0.7071;
    // seeds move 0.5 / 11 = 0.0455. Iteration 2: SSE = 1 -> 0.5; no change.
    try expect(std.mem.indexOf(u8, text, "Minimum Distance Between Initial Seeds =       11") != null);
    try expect(std.mem.indexOf(u8, text, "        1       0.7071      0.0455      0.0455") != null);
    try expect(std.mem.indexOf(u8, text, "        2       0.5000           0           0") != null);
    try expect(std.mem.indexOf(u8, text, "Convergence criterion is satisfied.") != null);
    // Means 0.5 / 10.5; RMS std sqrt(0.5) = 0.7071; max distance 0.5;
    // nearest cluster distance 10.
    try expect(std.mem.indexOf(u8, text, "   1                2       0.7071              0.5000                      2              10.0000") != null);
    // x: total STD sqrt(101/3) = 5.80230, within sqrt(1/2) = 0.70711,
    // R-square 100/101 = 0.990099, ratio 100.
    try expect(std.mem.indexOf(u8, text, "x              5.80230       0.70711      0.990099      100.000000") != null);
    // One all-missing observation omitted in group A; c = 2 > n/5 makes the
    // expected R-square and CCC missing.
    try expect(std.mem.indexOf(u8, text, "1 Observation(s) were omitted due to missing values.") != null);
    try expect(std.mem.indexOf(u8, text, "Cubic Clustering Criterion =     .") != null);
    // Group B with FREQ: u (f=2) at 0, v at 2, w at 20, x (f=2) at 22;
    // cluster means 2/3 and 64/3, frequencies 3 and 3. The f=0 row is not
    // used but is still assigned in OUT= (verified against SAS).
    try expect(std.mem.indexOf(u8, text, "   1                3") != null);
    const o = env.lib.find("o").?;
    try expectEqual(@as(usize, 10), o.rows.items.len);
    try expectEqual(@as(usize, 8), o.columns.items.len);
    const cl = o.indexOf("CLUSTER").?;
    const dist = o.indexOf("DISTANCE").?;
    const want_cl = [_]f64{ 1, 1, 2, 2, nan, 1, 1, 2, 2, 1 };
    const want_d = [_]f64{ 0.5, 0.5, 0.5, 0.5, nan, 2.0 / 3.0, 4.0 / 3.0, 4.0 / 3.0, 2.0 / 3.0, 5 - 2.0 / 3.0 };
    for (o.rows.items, want_cl, want_d) |row, c, dv| {
        if (std.math.isNan(c)) {
            try expect(std.math.isNan(row[cl].num) and std.math.isNan(row[dist].num));
        } else {
            try approx(c, row[cl].num, 0);
            try approx(dv, row[dist].num, 1e-9);
        }
    }
}
