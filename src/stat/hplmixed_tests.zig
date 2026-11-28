//! STAT-HPLMIXED-001 permanent tests. Expected numbers are the SAS 9.4
//! listing (run 2026-11-28) of the invented rows below, the same rows as
//! tests/corpus/stat_hplmixed001_small.sas, compared to displayed precision.
//! No test reads tests/STAT15.4-oracle/.
const std = @import("std");
const hplmixed = @import("hplmixed.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const nan = std.math.nan(f64);

const Row = struct { []const u8, f64, f64, f64, []const u8 };
/// subj (char), num, t, y, tag (char). Subject G has only missing responses;
/// the last row has a missing subject.
const rows = [_]Row{
    .{ "A", 1, 1, 1.80, "obs1" },
    .{ "A", 1, 2, 1.80, "obs2" },
    .{ "A", 1, 3, 2.60, "obs3" },
    .{ "A", 1, 1, 1.10, "obs4" },
    .{ "A", 1, 2, 2.25, "obs5" },
    .{ "A", 1, 3, 2.45, "obs6" },
    .{ "B", 2, 1, 5.10, "obs7" },
    .{ "B", 2, 2, 7.25, "obs8" },
    .{ "B", 2, 3, 8.45, "obs9" },
    .{ "B", 2, 1, 5.65, "obs10" },
    .{ "B", 2, 2, 6.70, "obs11" },
    .{ "B", 2, 3, 8.80, "obs12" },
    .{ "C", 3, 1, 3.15, "obs13" },
    .{ "C", 3, 2, 3.70, "obs14" },
    .{ "C", 3, 3, 5.30, "obs15" },
    .{ "C", 3, 1, 2.80, "obs16" },
    .{ "C", 3, 2, 4.10, "obs17" },
    .{ "C", 3, 3, 4.60, "obs18" },
    .{ "D", 4, 1, 8.30, "obs19" },
    .{ "D", 4, 2, 11.10, "obs20" },
    .{ "D", 4, 3, 13.10, "obs21" },
    .{ "D", 4, 1, 8.75, "obs22" },
    .{ "D", 4, 2, 10.95, "obs23" },
    .{ "D", 4, 3, 13.65, "obs24" },
    .{ "E", 5, 1, 3.45, "obs25" },
    .{ "E", 5, 2, 3.35, "obs26" },
    .{ "E", 5, 3, 3.75, "obs27" },
    .{ "E", 5, 1, 2.90, "obs28" },
    .{ "E", 5, 2, 3.70, "obs29" },
    .{ "E", 5, 3, 3.40, "obs30" },
    .{ "F", 6, 1, 6.50, "obs31" },
    .{ "F", 6, 2, 8.90, "obs32" },
    .{ "F", 6, 3, 10.20, "obs33" },
    .{ "F", 6, 1, 6.90, "obs34" },
    .{ "F", 6, 2, 8.20, "obs35" },
    .{ "F", 6, 3, 10.65, "obs36" },
    .{ "G", 7, 1, nan, "obs37" },
    .{ "G", 7, 2, nan, "obs38" },
    .{ "", 8, 1, 5.5, "obs39" },
};
fn growth(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "growth");
    _ = try ds.addColumn("subj", .char);
    for ([_][]const u8{ "num", "t", "y" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("tag", .char);
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .str = r[4] } });
    return ds;
}

const Outcome = struct { rc: u8, out: []const u8, log: []const u8 };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    fn a(self: *Fixture) A {
        return self.arena.allocator();
    }
    fn init(self: *Fixture) !void {
        self.lib = Library.init(self.a());
        const ds = try growth(self.a());
        try self.lib.put(ds.name, ds);
    }
    /// Exit code under D-009, listing and captured diagnostics.
    fn outcome(self: *Fixture, source: []const u8) !Outcome {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(self.a());
        var out: std.ArrayList(u8) = .empty;
        hplmixed.run(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, &out, try lex.tokenize(self.a(), source, &d)) catch |err| {
            try expectEqual(error.ParseError, err);
            try expectEqual(@as(usize, 0), out.items.len);
        };
        return .{ .rc = diag.exitCode(diag.gapHit(), d.hasErrors()), .out = out.items, .log = try d.render() };
    }
    fn spec(self: *Fixture, source: []const u8) !hplmixed.Spec {
        var d = diag.Diagnostics.init(self.a());
        return hplmixed.parse(.{ .arena = self.a(), .lib = &self.lib, .diags = &d }, try lex.tokenize(self.a(), source, &d));
    }
};
fn shown(expected: f64, actual: f64, decimals: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.5 * std.math.pow(f64, 10, -decimals) + 1e-12);
}
const base = "proc hplmixed data=growth; class subj; model y = t / s; random int t / sub=subj type=un; run;";

test "STAT-HPLMIXED-001 declarations defaults explicit settings and ID roles" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const d = try fx.spec(base);
    try expectEqual(@as(usize, 20), d.namelen);
    try expectEqual(@as(usize, 20), d.maxclprint);
    try expect(!d.noclprint and !d.noprint and d.solution and d.type_un and d.random_intercept);
    try expectEqual(@as(usize, 0), d.ids.len);
    try std.testing.expectEqualStrings("subj", d.subject_name);
    const e = try fx.spec("proc hplmixed data=growth method=reml namelen=32 maxclprint=0 noclprint noprint; class num subj; id tag subj; model y = t; random intercept t / subject=num(subj) type=un; run;");
    try expectEqual(@as(usize, 32), e.namelen);
    try expectEqual(@as(usize, 0), e.maxclprint);
    try expect(e.noclprint and e.noprint and !e.solution);
    try std.testing.expectEqualSlices(usize, &.{ 4, 0 }, e.ids);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, e.subject);
    try std.testing.expectEqualStrings("num(subj)", e.subject_name);
}

test "STAT-HPLMIXED-001 missing values levels subjects and SAS-verified estimates" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    const s = try fx.spec(base);
    const used = try hplmixed.usedRows(fx.a(), s, false);
    const levels = try hplmixed.usedRows(fx.a(), s, true);
    try expectEqual(@as(usize, 36), used.len);
    try expectEqual(@as(usize, 38), levels.len);
    try expectEqual(@as(usize, 7), try hplmixed.subjectCount(fx.a(), s, levels));
    const f = try hplmixed.fit(fx.a(), s, used);
    try expectEqual(@as(usize, 6), f.m);
    try expectEqual(@as(usize, 6), f.k);
    try shown(3.4790, f.g[0], 4);
    try shown(1.3914, f.g[2], 4);
    try shown(0.6924, f.g[3], 4);
    try shown(0.08820, f.sigma2, 5);
    try shown(59.38641, f.minus2, 5);
    try shown(3.4361, f.beta[0], 4);
    try shown(1.2729, f.beta[1], 4);
    try shown(0.7727, f.se[0], 4);
    try shown(0.3451, f.se[1], 4);
    const o = try fx.outcome("proc hplmixed data=growth maxclprint=2; class subj; id tag; model y = t / s; random int t / sub=subj type=un; run;");
    try expectEqual(@as(u8, 2), o.rc); // Iteration History is a loud gap
    try expect(std.mem.indexOf(u8, o.out, "subj          7    A B ...") != null);
    try expect(std.mem.indexOf(u8, o.out, "Iteration History") == null);
    try expect(std.mem.indexOf(u8, o.out, "67.17005") != null);
    try expect(std.mem.indexOf(u8, o.out, "0.0008") != null);
    try expect(std.mem.indexOf(u8, o.log, "Iteration History table") != null);
    const quiet = try fx.outcome("proc hplmixed data=growth noclprint; class num subj; model y = t; random intercept t / subject=num type=un; run;");
    try expect(std.mem.indexOf(u8, quiet.out, "Class Level Information") == null);
    try expect(std.mem.indexOf(u8, quiet.out, "Solution for Fixed Effects") == null);
    const none = try fx.outcome("proc hplmixed data=growth noprint; class subj; model y = t; random int t / sub=subj type=un; run;");
    try expectEqual(@as(u8, 0), none.rc);
    try expectEqual(@as(usize, 0), none.out.len);
}

test "STAT-HPLMIXED-001 invalid input is a user error and valid unimplemented features are loud gaps" {
    var fx: Fixture = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer fx.arena.deinit();
    try fx.init();
    for ([_][]const u8{
        "proc hplmixed data=growth method=bad; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth namelen=19; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth maxclprint=-1; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth bogus; model y = t; run;",
        "proc hplmixed data=absent; model y = t; run;",
        "proc hplmixed data=growth; model y = t; class subj; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model tag = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model subj = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; id; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; id nothere; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = tag; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t / bogus; random int t / sub=subj type=un; run;",
    }) |code| {
        const o = try fx.outcome(code);
        try expectEqual(@as(u8, 1), o.rc);
    }
    for ([_][]const u8{
        "proc hplmixed data=growth method=ml; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth technique=newrap; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth noclprint=3; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int t / sub=subj type=vc; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int t; run;",
        "proc hplmixed data=growth; class subj; model y = t; run;",
        "proc hplmixed data=growth; class subj; model y = subj; random int / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int t / sub=subj type=un; repeated / sub=subj; run;",
        "proc hplmixed data=growth; by num; class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t / cl; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int t / sub=subj type=un solution; run;",
        "proc hplmixed data=growth(where=(tag ne 'obs1')); class subj; model y = t; random int t / sub=subj type=un; run;",
        "proc hplmixed data=growth; class subj; model y = t; random int t / sub=num type=un; run;",
    }) |code| {
        const o = try fx.outcome(code);
        try expectEqual(@as(u8, 2), o.rc);
        try expectEqual(@as(usize, 0), o.out.len);
    }
}
