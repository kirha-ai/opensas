//! STAT-SURVEYLOGISTIC-001 permanent checks: declarations, user errors and
//! D-009 gaps via the captured reporter. The verified listing lives in
//! tests/corpus/stat_surveylogistic_taylor.sas. Data are invented.
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const sl = @import("surveylogistic.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

/// Columns y st cl w x g; two strata of two clusters, a non-separated response.
fn sample(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "y", "st", "cl", "w", "x" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("g", .char);
    const rows = [_][5]f64{
        .{ 0, 1, 1, 1, 1 }, .{ 1, 1, 1, 2, 2 }, .{ 0, 1, 1, 1, 5 }, .{ 1, 1, 2, 2, 3 },
        .{ 0, 1, 2, 1, 4 }, .{ 1, 1, 2, 1, 1 }, .{ 0, 2, 1, 3, 2 }, .{ 1, 2, 1, 1, 6 },
        .{ 0, 2, 1, 2, 3 }, .{ 1, 2, 2, 1, 4 }, .{ 0, 2, 2, 2, 6 }, .{ 0, 2, 2, 1, 2 },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = "a" } });
    return ds;
}

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        const ds = try sample(self.a());
        try self.lib.put(ds.name, ds);
    }
    fn rc(self: *Fixture, source: []const u8) !struct { u8, usize } {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        var failed = false;
        sl.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            failed = true;
        };
        const code = diag.exitCode(diag.gapHit(), d.hasErrors());
        try expectEqual(failed, code != 0);
        return .{ code, out.items.len };
    }
};

test "STAT-SURVEYLOGISTIC-001 declarations and roles" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    var d = diag.Diagnostics.init(fx.a());
    const src = "proc surveylogistic data=sample alpha=0.1 total=1000 varmethod=taylor; strata st; cluster cl; weight w; model y(descending)=x / link=logit;";
    const s = try sl.parse(.{ .arena = fx.a(), .lib = &fx.lib, .diags = &d }, try lex.tokenize(fx.a(), src, &d));
    try expectEqual(@as(?usize, 0), s.response);
    try std.testing.expectEqualSlices(usize, &.{4}, s.covariates);
    try std.testing.expectEqualSlices(usize, &.{1}, s.roles.strata);
    try std.testing.expectEqualSlices(usize, &.{2}, s.roles.clusters);
    try expectEqual(@as(?usize, 3), s.roles.weight);
    try expect(s.alpha == 0.1 and s.event == .descending and s.roles.fpc.total == 1000);
    const e = try sl.parse(.{ .arena = fx.a(), .lib = &fx.lib, .diags = &d }, try lex.tokenize(fx.a(), "proc surveylogistic rate=5; model y(event='1')=x;", &d));
    try expect(std.mem.eql(u8, e.event.value, "1") and e.roles.fpc.rate == 0.05);
    try expect(!d.hasErrors());
}

test "STAT-SURVEYLOGISTIC-001 user errors are rc 1 and unimplemented features rc 2" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const Case = struct { []const u8, u8 };
    for ([_]Case{
        .{ "proc surveylogistic; strata st;", 1 }, // MODEL required
        .{ "proc surveylogistic bogus; model y=x;", 1 },
        .{ "proc surveylogistic data=nosuch; model y=x;", 1 },
        .{ "proc surveylogistic alpha=2; model y=x;", 1 },
        .{ "proc surveylogistic rate=0.1 total=5; model y=x;", 1 },
        .{ "proc surveylogistic; model nosuch=x;", 1 },
        .{ "proc surveylogistic; model y=x; model y=x;", 1 },
        .{ "proc surveylogistic; model y(descending event='1')=x;", 1 },
        .{ "proc surveylogistic; model y=x; weight g;", 1 },
        .{ "proc surveylogistic; model y(event='7')=x; strata st; weight w;", 1 },
        .{ "proc surveylogistic varmethod=brr; model y=x;", 2 },
        .{ "proc surveylogistic nomcar; model y=x;", 2 },
        .{ "proc surveylogistic; model y=x / link=probit;", 2 },
        .{ "proc surveylogistic; model y=x / clodds;", 2 },
        .{ "proc surveylogistic; class g; model y=g;", 2 },
        .{ "proc surveylogistic; model y=x; freq w;", 2 }, // FREQ without CLUSTER
        .{ "proc surveylogistic; model y=x; cluster cl; freq g;", 1 }, // character FREQ
        .{ "proc surveylogistic; model y=x; cluster cl; freq w; freq x;", 1 },
        .{ "proc surveylogistic; model y=x; domain st;", 2 },
        .{ "proc surveylogistic; model y=x*x;", 2 },
        .{ "proc surveylogistic; model y=x w; strata st; weight w;", 2 }, // two restrictions
        .{ "proc surveylogistic missing; model y=x; strata st;", 2 },
        .{ "proc surveylogistic; model y=x; cluster st cl;", 2 }, // several CLUSTER variables
        .{ "proc surveylogistic; model y=x; repweights w;", 2 },
    }) |case| {
        const r = try fx.rc(case[0]);
        std.testing.expectEqual(case[1], r[0]) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
        try expectEqual(@as(usize, 0), r[1]);
    }
    for ([_][]const u8{
        "proc surveylogistic; strata st; cluster cl; weight w; model y(event='1')=x;",
        "proc surveylogistic; model y=x; strata st;", // no WEIGHT
        "proc surveylogistic; model y=x; weight w;", // no STRATA/CLUSTER
        "proc surveylogistic; model y=x; strata st; weight w; by st;", // BY groups
        "proc surveylogistic; model y=x; strata st cl; weight w;", // several STRATA variables
        "proc surveylogistic; strata st; cluster cl; weight w; freq w; model y(event='1')=x;", // FREQ
        "proc surveylogistic; strata st; cluster cl; weight w; weight x; model y(event='1')=x;", // first WEIGHT used (p.9827)
    }) |src| {
        const ok = try fx.rc(src);
        try expectEqual(@as(u8, 0), ok[0]);
        try expect(ok[1] > 0);
    }
    // NOPRINT fits (every check runs) but prints nothing.
    const quiet = try fx.rc("proc surveylogistic noprint; strata st; cluster cl; weight w; model y(event='1')=x;");
    try expectEqual(@as(u8, 0), quiet[0]);
    try expectEqual(@as(usize, 0), quiet[1]);
}
