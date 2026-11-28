//! STAT-HPMIXED-001 permanent tests. Expected counts are the SAS 9.4 listing
//! (run 2026-11-28) of the invented rows below, the same rows as
//! tests/corpus/stat_hpmixed001_nofit.sas. No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const hpmixed = @import("hpmixed.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

const Row = struct { []const u8, f64, f64, f64, f64 };
/// g (char), a, b, y, w.
const rows = [_]Row{
    .{ "x", 1, 1, 2.5, 1 },   .{ "x", 1, 2, 3.1, 2 }, .{ "x", 2, 1, 4.0, 1 },
    .{ "x", 2, 2, nan, 1 },   .{ "x", 3, 1, 5.2, 0 }, .{ "x", 3, 2, 6.1, nan },
    .{ "x", nan, 1, 6.3, 1 }, .{ "y", 1, 1, 2.9, 1 }, .{ "y", 1, 2, 3.3, 2 },
    .{ "y", 2, 1, 4.4, 1 },   .{ "y", 2, 2, 4.9, 3 }, .{ "y", 3, 1, 5.0, 1 },
    .{ "y", 3, 2, 6.6, 1 },
};
const Outcome = struct { rc: u8, out: []const u8, log: []const u8 };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        const ds = try self.a().create(Dataset);
        ds.* = Dataset.init(self.a(), "d");
        _ = try ds.addColumn("g", .char);
        for ([_][]const u8{ "a", "b", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
        for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] } });
        try self.lib.put(ds.name, ds);
    }
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        hpmixed.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            try expectEqual(@as(usize, 0), out.items.len);
        };
        return .{ .rc = diag.exitCode(diag.gapHit(), d.hasErrors()), .out = out.items, .log = try d.render() };
    }
    fn spec(self: *Fixture, source: []const u8) !hpmixed.Spec {
        var d = diag.Diagnostics.init(self.a());
        return hpmixed.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, try lex.tokenize(self.a(), source, &d));
    }
};
/// Whitespace-insensitive containment (the corpus `words` convention).
fn has(text: []const u8, part: []const u8) bool {
    var buf: [2][16384]u8 = undefined;
    const sides = [2][]const u8{ text, part };
    var lens: [2]usize = .{ 0, 0 };
    for (sides, 0..) |side, k| {
        var space = false;
        for (side) |c| {
            if (std.ascii.isWhitespace(c)) {
                space = true;
                continue;
            }
            if (space and lens[k] > 0 and lens[k] < buf[k].len) {
                buf[k][lens[k]] = ' ';
                lens[k] += 1;
            }
            space = false;
            if (lens[k] < buf[k].len) {
                buf[k][lens[k]] = c;
                lens[k] += 1;
            }
        }
    }
    return std.mem.indexOf(u8, buf[0][0..lens[0]], buf[1][0..lens[1]]) != null;
}

test "STAT-HPMIXED-001 declarations defaults and explicit settings" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const d = try fx.spec("proc hpmixed data=d; class a b; model y = a b a*b; random a; run;");
    try expectEqual(@as(usize, 20), d.maxclprint);
    try expect(d.intercept and !d.nofit and !d.noinfo and !d.noclprint and d.weight == null);
    try expectEqual(@as(usize, 3), d.fixed.len);
    try std.testing.expectEqualStrings("a*b", d.fixed[2].name);
    const e = try fx.spec("proc hpmixed data=d method=reml nofit noclprint maxclprint=0 namelen=30; by g; class a b; id g a; weight w; model y = a / noint; random b a*b; run;");
    try expect(e.nofit and e.noclprint and !e.intercept);
    try expectEqual(@as(usize, 30), e.namelen);
    try expectEqual(@as(?usize, 4), e.weight);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, e.ids);
    try std.testing.expectEqualSlices(usize, &.{0}, e.by_cols);
    try expectEqual(@as(usize, 2), e.random.len);
}

test "STAT-HPMIXED-001 observation selection BY groups and SAS-verified dimensions" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const o = try fx.outcome("proc hpmixed data=d nofit; by g; class a b; id g; weight w; model y = a; random b a*b; run;");
    try expectEqual(@as(u8, 0), o.rc);
    try expect(has(o.out, "g=x\n\nThe HPMIXED Procedure"));
    try expect(has(o.out, "Weight Variable              w"));
    try expect(has(o.out, "Number of Observations Read           7\nNumber of Observations Used           3"));
    try expect(has(o.out, "Columns in X                       3\nColumns in Z                       8"));
    try expect(has(o.out, "Number of Observations Read           6\nNumber of Observations Used           6"));
    try expect(has(o.out, "Columns in X                       4"));
    try expect(!has(o.out, "Not Used") and !has(o.out, "Optimization Information"));
    const f = try fx.outcome("proc hpmixed data=d nofit; class a; model y = a; run;");
    try expect(has(f.out, "G-side Cov. Parameters             0") and has(f.out, "Columns in Z                       0"));
    try expect(has(f.out, "Number of Observations Used          11"));
    const quiet = try fx.outcome("proc hpmixed data=d nofit noinfo; class a b; model y = a; random b; run;");
    try expectEqual(@as(usize, 0), quiet.out.len);
    try expectEqual(@as(u8, 0), quiet.rc);
}

test "STAT-HPMIXED-001 fit is a loud gap after the verified tables; invalid input fails" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const fit = try fx.outcome("proc hpmixed data=d; class a b; model y = a; random b; test a; run;");
    try expectEqual(@as(u8, 2), fit.rc);
    try expect(has(fit.out, "Optimization Technique        Dual Quasi-Newton"));
    try expect(has(fit.log, "REML estimation"));
    for ([_][]const u8{
        "proc hpmixed data=d method=ml; class a; model y = a; random a; run;",
        "proc hpmixed data=d namelen=19; class a; model y = a; random a; run;",
        "proc hpmixed data=d maxclprint=-1; class a; model y = a; random a; run;",
        "proc hpmixed data=d; model y = a; class a; random a; run;",
        "proc hpmixed data=d; class a; random a; run;",
        "proc hpmixed data=d; class a; model g = a; run;",
        "proc hpmixed data=d; class a; weight g; model y = a; run;",
        "proc hpmixed data=d; class a; weight w; weight w; model y = a; run;",
        "proc hpmixed data=d; class a; model y = a nothere; run;",
        "proc hpmixed data=d; class a; model y = a; random; run;",
    }) |source| {
        const bad = try fx.outcome(source);
        try expectEqual(@as(u8, 1), bad.rc);
        try expectEqual(@as(usize, 0), bad.out.len);
    }
    for ([_][]const u8{
        "proc hpmixed data=d ic=pq; class a; model y = a; random a; run;",
        "proc hpmixed data=d; class a; model y = a / solution; random a; run;",
        "proc hpmixed data=d; class a b; model y = a; random a / subject=b; run;",
        "proc hpmixed data=d; class a; model y = a; repeated / type=ar(1); run;",
        "proc hpmixed data=d nofit; class a; model y = a; random a; contrast 'c' a 1 -1; run;",
        "proc hpmixed data=d; class a; model y = a; run;",
        "proc hpmixed data=d noinfo; class a; model y = a; random a; run;",
    }) |source| {
        const gapped = try fx.outcome(source);
        try expectEqual(@as(u8, 2), gapped.rc);
        try expectEqual(@as(usize, 0), gapped.out.len);
    }
}
