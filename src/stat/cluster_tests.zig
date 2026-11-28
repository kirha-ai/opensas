//! STAT-CLUSTER-001 unit checks against hand mathematics.
const std = @import("std");
const cluster = @import("cluster.zig");

// Four points on a line at 0, 1, 3, 7: distances are |i - j|.
const pts = [_]f64{ 0, 1, 3, 7 };
fn matrix() [16]f64 {
    var d: [16]f64 = undefined;
    for (0..4) |i| for (0..4) |j| {
        d[i * 4 + j] = @abs(pts[i] - pts[j]);
    };
    return d;
}

test "STAT-CLUSTER-001 average linkage history matches hand calculation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = matrix();
    const h = try cluster.agglomerate(a, .average, &d, &.{ 1, 1, 1, 1 }, &.{ "a", "b", "c", "d" });
    // Pairs: 1,3,7,2,6,4 -> sum of squares 1+9+49+4+36+16 = 115, RMS = sqrt(115/6).
    try std.testing.expectApproxEqAbs(@sqrt(115.0 / 6.0), h.norm, 1e-12);
    try std.testing.expectEqual(@as(usize, 3), h.merges.len);
    // Level 3: a+b at d^2 = 1. T = 115/4; W_ab = 1/2.
    const m3 = h.merges[0];
    try std.testing.expectEqualStrings("a", m3.left);
    try std.testing.expectEqualStrings("b", m3.right);
    try std.testing.expectApproxEqAbs(1.0 / @sqrt(115.0 / 6.0), m3.dist, 1e-12);
    // Pseudo F at G=3: ((T - P)/(G-1)) / (P/(n-G)) = ((28.75-0.5)/2)/(0.5/1) = 28.25.
    try std.testing.expectApproxEqAbs(28.25, m3.f, 1e-10);
    try std.testing.expect(std.math.isNan(m3.t2));
    // Level 2: average squared distance CL3-c = (9+4)/2 = 6.5 < c-d 16, CL3-d (49+36)/2.
    const m2 = h.merges[1];
    try std.testing.expectEqualStrings("CL3", m2.left);
    try std.testing.expectEqualStrings("c", m2.right);
    try std.testing.expectApproxEqAbs(@sqrt(6.5) / @sqrt(115.0 / 6.0), m2.dist, 1e-12);
    // W_abc = (1+9+4)/3 = 14/3; B = 14/3 - 1/2; t2 = B / ((1/2 + 0)/1).
    try std.testing.expectApproxEqAbs((14.0 / 3.0 - 0.5) / 0.5, m2.t2, 1e-10);
    try std.testing.expectEqual(@as(f64, 3), m2.freq);
    try std.testing.expect(std.math.isNan(h.merges[2].f));
}

test "STAT-CLUSTER-001 single, centroid and ward criteria by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = matrix();
    const w = [_]f64{ 1, 1, 1, 1 };
    const labels = [_][]const u8{ "a", "b", "c", "d" };
    const s = try cluster.agglomerate(a, .single, &d, &w, &labels);
    // Mean distance (1+3+7+2+6+4)/6 = 23/6; single joins at 1, 2, 4.
    try std.testing.expectApproxEqAbs(23.0 / 6.0, s.norm, 1e-12);
    for (s.merges, [_]f64{ 1, 2, 4 }) |m, want| try std.testing.expectApproxEqAbs(want / (23.0 / 6.0), m.dist, 1e-12);
    const c = try cluster.agglomerate(a, .centroid, &d, &w, &labels);
    // Centroid of a,b = 0.5; distance to c (3) is 2.5 -> squared 6.25.
    try std.testing.expectApproxEqAbs(2.5 / @sqrt(115.0 / 6.0), c.merges[1].dist, 1e-12);
    const wd = try cluster.agglomerate(a, .ward, &d, &w, &labels);
    // Ward: B(ab) = 0.5, B(abc) = 14/3 - 1/2, total R-square at G=1 is 0.
    try std.testing.expectApproxEqAbs(0.5 / (115.0 / 4.0), wd.merges[0].sprsq, 1e-12);
    try std.testing.expectApproxEqAbs((14.0 / 3.0 - 0.5) / (115.0 / 4.0), wd.merges[1].sprsq, 1e-12);
    try std.testing.expectApproxEqAbs(0, wd.merges[2].rsq, 1e-12);
}

test "STAT-CLUSTER-001 ties merge the pair with the minimum larger identification number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Points 0, 1, 2: pairs (1,2) and (2,3) tie at distance 1; (1,2) has larger id 2 < 3.
    var d: [9]f64 = undefined;
    for (0..3) |i| for (0..3) |j| {
        d[i * 3 + j] = @abs(@as(f64, @floatFromInt(i)) - @as(f64, @floatFromInt(j)));
    };
    const h = try cluster.agglomerate(a, .single, &d, &.{ 1, 1, 1 }, &.{ "p", "q", "r" });
    try std.testing.expectEqualStrings("p", h.merges[0].left);
    try std.testing.expectEqualStrings("q", h.merges[0].right);
    try std.testing.expect(h.merges[0].tie);
    try std.testing.expect(!h.merges[1].tie);
    try std.testing.expectEqual(@as(usize, 1), h.ties);
}

const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;

/// Invented 3 x 3 TYPE=DISTANCE matrix (points 0, 1, 3) with an ID, a
/// frequency, an RMSSTD candidate, a BY key and a character variable.
const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "m");
        _ = try ds.addColumn("name", .char);
        ds.setLen("name", 8);
        for ([_][]const u8{ "d1", "d2", "d3", "n", "s", "g" }) |c| _ = try ds.addColumn(c, .num);
        const nan = std.math.nan(f64);
        const rows = [_][3]f64{ .{ 0, nan, nan }, .{ 1, 0, nan }, .{ 3, 2, 0 } };
        for (rows, [_][]const u8{ "x", "y", "z" }) |r, nm| try ds.appendRow(&.{ .{ .str = nm }, .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = 2 }, .{ .num = 0.5 }, .{ .num = 1 } });
        try self.lib.put("m", ds);
    }
    fn run(self: *Env, source: []const u8) !std.ArrayList(u8) {
        var out: std.ArrayList(u8) = .empty;
        const cx: proc.ProcCtx = .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
        try cluster.run(cx, &out, try lex.tokenize(self.arena.allocator(), source, &self.diags));
        return out;
    }
    fn expectFailure(self: *Env, source: []const u8, message: []const u8) !void {
        if (self.run(source)) |_| return error.TestExpectedError else |e| try std.testing.expectEqual(error.ParseError, e);
        const items = self.diags.list.items;
        try std.testing.expect(items.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, items[items.len - 1].message, message) != null);
    }
};

test "STAT-CLUSTER-001 valid but unimplemented requests are loud gaps" {
    const cases = [_][2][]const u8{
        .{ "proc cluster data=m method=average; id name; run;", "coordinate input" },
        .{ "proc cluster data=m(type=distance) method=complete; id name; run;", "METHOD=complete is not implemented (STAT-CLUSTER-003)" },
        .{ "proc cluster data=m(type=distance) method=eml; id name; run;", "METHOD=eml is not implemented" },
        .{ "proc cluster data=m(type=distance) method=average outtree=t; id name; run;", "OUTTREE= data set is not implemented (STAT-CLUSTER-006)" },
        .{ "proc cluster data=m(type=distance) method=average nosquare; id name; run;", "nosquare option is not implemented" },
        .{ "proc cluster data=m(type=distance) method=average rsquare; id name; run;", "rsquare option is not implemented (STAT-CLUSTER-007)" },
        .{ "proc cluster data=m(type=distance) method=average plots=dendrogram; id name; run;", "PLOTS= other than PLOTS=NONE" },
        .{ "proc cluster data=m(type=distance) method=average print=3; id name; run;", "PRINT= option is not implemented" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; freq n; rmsstd s; id name; run;", "RMSSTD values" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; freq s; id name; run;", "FREQ value that is missing or less than 1" },
        .{ "proc cluster data=m(type=corr) method=average; id name; run;", "TYPE=corr is not implemented" },
        .{ "proc cluster data=m(type=distance) method=average pseudo pseudo; id name; run;", "repeated PROC statement option" },
    };
    for (cases) |c| {
        var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer env.arena.deinit();
        try env.init();
        diag.resetGap();
        try env.expectFailure(c[0], c[1]);
    }
}

test "STAT-CLUSTER-001 invalid input is rejected with an ERROR" {
    const cases = [_][2][]const u8{
        .{ "proc cluster data=m(type=distance); id name; run;", "METHOD= option must be specified" },
        .{ "proc cluster data=m(type=distance) method=bogus; id name; run;", "METHOD=bogus is not a valid clustering method" },
        .{ "proc cluster data=m(type=distance) method=average; var d1 name; id name; run;", "variable name in the VAR statement must be numeric" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; id nope; run;", "variable nope in the ID statement is not on the input data set" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; freq name; id name; run;", "FREQ statement must be numeric" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; rmsstd s; id name; run;", "RMSSTD statement requires a FREQ statement" },
        .{ "proc cluster data=m(type=distance) method=average; var d1 d2; id name; run;", "as many rows as distance variables (3 rows, 2 variables)" },
        .{ "proc cluster data=m(type=distance) method=average; var d1-d3; copy nope; id name; run;", "variable nope in the COPY statement" },
        .{ "proc cluster data=nothere method=average; run;", "input data set not found" },
        .{ "proc cluster data=m(type=distance) method=average bogus; id name; run;", "invalid statement or token bogus" },
    };
    for (cases) |c| {
        var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer env.arena.deinit();
        try env.init();
        try env.expectFailure(c[0], c[1]);
    }
}

test "STAT-CLUSTER-001 default VAR list, COPY, BY and NOPRINT roles" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const a = env.arena.allocator();
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &env.lib, .diags = &env.diags };
    // Without VAR: every numeric variable not in BY/COPY/ID/FREQ (p.2498).
    const s = try cluster.parse(cx, try lex.tokenize(a, "proc cluster data=m(type=distance) method=ward; by g; copy s; freq n; id name; run;", &env.diags));
    try std.testing.expectEqual(@as(usize, 3), s.vars.len);
    try std.testing.expect(s.distance);
    try std.testing.expectEqual(cluster.Method.ward, s.method);
    try std.testing.expectEqual(@as(usize, 1), s.copy.len);
    try std.testing.expectEqual(@as(usize, 1), s.by_cols.len);
    // Abbreviations (p.2487) and NOPRINT: the history is computed, nothing printed.
    const out = try env.run("proc cluster data=m(type=distance) method=sin noprint; var d1-d3; id name; run;");
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    // Printed single-linkage history: x+y at 1, then CL2+z at 2; mean distance 2.
    const shown = try env.run("proc cluster data=m(type=distance) method=single; var d1-d3; copy s; id name; run;");
    try std.testing.expect(std.mem.indexOf(u8, shown.items, "Mean Distance Between Observations           2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, shown.items, "       2    x               y                       2         0.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, shown.items, "       1    CL2             z                       3           1") != null);
}
