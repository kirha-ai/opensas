//! Public PROC integration regressions. Oracle commands and values are retained
//! under /tmp/opensas-stat-batch2/FEAT-univ-inference (never committed).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;
fn data(a: A, n: usize) !*Library {
    const lib = try a.create(Library);
    lib.* = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "w", "f", "g" }) |name| {
        _ = try ds.addColumn(name, .num);
    }
    for (0..n) |i| {
        const x: f64 = @floatFromInt(i + 1);
        try ds.appendRow(&.{ .{ .num = x }, .{ .num = 2 * x }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 } });
    }
    try lib.put("d", ds);
    return lib;
}
fn run(a: A, lib: *Library, source: []const u8) ![]const u8 {
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = lib, .diags = &d }, &out, try lex.tokenize(a, source, &d));
    try std.testing.expect(!d.hasErrors());
    return out.items;
}
fn cell(ds: *Dataset, row: usize, key: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(key).?].num;
}
fn near(want: f64, got: f64, tolerance: f64) !void {
    try std.testing.expectApproxEqAbs(want, got, tolerance);
}
test "univ inference OUTPUT normal robust location and CI metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 8);
    _ = try run(a, lib, "proc univariate data=d noprint forceqn forcesn; var x y; output out=o normaltest=w probn=p gini=g mad=mad sn=sn qn=qn std_gini=sg std_mad=sm std_sn=ss std_qn=sq std_qrange=si t=t probt=pt msign=m probm=pm signrank=s probs=ps; run;");
    const o = lib.find("o").?;
    try std.testing.expectEqualStrings("the normality test statistic, x", o.columns.items[o.indexOf("w").?].label.?);
    try std.testing.expectEqualStrings("p-value of normality test stat, x", o.columns.items[o.indexOf("p").?].label.?);
    // core.sas/core.txt, rank.sas/rank.txt; manual pp.416–421.
    for ([_][]const u8{ "w", "p", "g", "mad", "sn", "qn", "ss", "sq", "m", "s", "pm", "ps" }, [_]f64{ 0.97485827830837, 0.93316533637933, 3, 2, 2.3852, 4.4438, 2.397126, 2.9729022, 4, 18, 0.0078125, 0.0078125 }) |key, want| try near(want, cell(o, 0, key), 1e-8);
    try near(0.001258320233936, cell(o, 0, "pt"), 1e-12);
    _ = try run(a, lib, "proc univariate data=d noprint alpha=.1; var x y; output out=c pctlpts=25 50 pctlpre=x y ciquantdf=(lowerpre=l m upperpre=u v lowername=a b uppername=c d) ciquantnormal=(lowerpre=nl nm upperpre=nu nv); run;");
    const c = lib.find("c").?;
    const names = [_][]const u8{ "x25", "y25", "x50", "y50", "nl25", "nm25", "nl50", "nm50", "nu25", "nv25", "nu50", "nv50", "la", "ma", "lb", "mb", "uc", "vc", "ud", "vd" };
    for (names, c.columns.items) |name, column| {
        try std.testing.expectEqualStrings(name, column.name);
        try std.testing.expectEqual(@import("../pdv.zig").VarType.num, column.type);
    }
    try std.testing.expectEqualStrings("the  25.0000 percentile, x", c.columns.items[4].label.?);
    try near(0.53715562203088, cell(c, 0, "nl25"), 1e-8);
    try near(2 * 0.53715562203088, cell(c, 0, "nm25"), 1e-8);
    try near(2, cell(c, 0, "lb"), 0);
    try near(7, cell(c, 0, "ud"), 0);
}
test "univ inference listing aliases sides alpha and qualifications" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 8);
    const listing = try run(a, lib, "proc univariate data=d normaltest alpha=.1 cibasic(type=lower alpha=.05) ciquantdf(type=asymmetric) ciquantnormal(type=upper) robustscale loccount trim=.1 to .25 by .15(type=lower) winsor=2(type=upper); ; var x; run;");
    for ([_][]const u8{ "Shapiro-Wilk  W  0.974858", "Kolmogorov-Smirnov  D  0.104854  >0.1500", "Cramer-von Mises  W-Sq  0.017355  >0.2500", "Anderson-Darling  A-Sq  0.134000  >0.2500", "95% Lower Confidence Bound", "90% Upper Confidence Bound", "Trimmed Means", "Winsorized Means", "Robust Measures of Scale", "Num Obs > Mu0  8.000000" }) |needle| try std.testing.expect(std.mem.indexOf(u8, listing, needle) != null);
    const weighted = try run(a, lib, "proc univariate data=d normal robustscale loccount cibasic cipctldf cipctlnormal trimmed=.1 winsorized=.1; weight w; var x; output out=c pctlpts=50 pctlpre=p cipctldf=(lowerpre=l upperpre=u); run;");
    try std.testing.expect(std.mem.indexOf(u8, weighted, "Basic Confidence Limits") != null);
    try std.testing.expect(std.mem.indexOf(u8, weighted, "Tests for Normality") == null);
    try std.testing.expectEqual(@as(usize, 1), lib.find("c").?.columns.items.len);
    const v = try run(a, lib, "proc univariate data=d vardef=n cibasic trim=.1 winsor=.1; var x; run;");
    try std.testing.expect(std.mem.indexOf(u8, v, "Basic Confidence Limits") == null);
}
test "univ inference FREQ BY CLASS and per-variable location" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 8);
    _ = try run(a, lib, "proc univariate data=d noprint location=4.5 9; by g; class w; freq f; var x y; output out=o t=t ty probt=p py signrank=s sy probs=ps psy pctlpts=50 pctlpre=x y cipctldf=(lowerpre=l m upperpre=u v); run;");
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(usize, 1), o.rows.items.len);
    for ([_][]const u8{ "t", "ty", "s", "sy" }) |key| try near(0, cell(o, 0, key), 0);
    for ([_][]const u8{ "p", "py", "ps", "psy" }) |key| try near(1, cell(o, 0, key), 1e-12);
    try near(2, cell(o, 0, "l50"), 0);
    try near(8, cell(o, 0, "u50"), 0);
}
test "univ inference signed rank exact-to-t boundary and ties SAS" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]usize{ 20, 21, 30 }, [_]f64{ 1.9073486328125e-6, 9.1830084743323e-8, 1.4935469986375e-10 }, [_]f64{ 0.18364524841308, 0.30436006249704, 0.33264603859423 }) |n, p, ptie| {
        const lib = try data(a, n);
        _ = try run(a, lib, "proc univariate data=d noprint;var x;output out=o probs=p;run;");
        try near(p, cell(lib.find("o").?, 0, "p"), 1e-13);
        const ds = lib.find("d").?;
        for (ds.rows.items, 0..) |r, i| {
            const copy = try a.dupe(Value, r);
            copy[0] = .{ .num = @as(f64, @floatFromInt((i + 1) % 7)) - 2.5 };
            ds.rows.items[i] = copy;
        }
        _ = try run(a, lib, "proc univariate data=d noprint;var x;output out=o probs=p;run;");
        try near(ptie, cell(lib.find("o").?, 0, "p"), 1e-10);
    }
}
test "univ inference malformed syntax captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 8);
    for ([_][]const u8{ "alpha=0", "alpha=1", "cibasic(type=asymmetric)", "cipctldf(type=twosided)", "cibasic(foo=1)", "cibasic()", "trimmed=", "mu0=1 2 3" }) |option| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const text = try std.fmt.allocPrint(a, "proc univariate data=d {s};var x;run;", .{option});
        try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = lib, .diags = &d }, &out, try lex.tokenize(a, text, &d)));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
}
test "univ inference FORCEQN computes beyond documented default cutoff" {
    // force.sas: x=1..65527, FORCEQN/FORCESN;
    // Qn=19508.282; corrected Qn=19507.8652098021.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 65527);
    _ = try run(a, lib, "proc univariate data=d noprint forceqn forcesn;var x;output out=o qn=q std_qn=sq sn=s std_sn=ss;run;");
    const o = lib.find("o").?;
    try near(19508.282, cell(o, 0, "q"), 1e-8);
    try near(19507.8652098021, cell(o, 0, "sq"), 1e-8);
    try near(19537.1732, cell(o, 0, "s"), 1e-8);
    try near(19537.4415427806, cell(o, 0, "ss"), 1e-8);
}

test "univ inference all observations equal MU0 have missing rank statistics" {
    // small.sas: n=1,2,3,8 all x=0 -> MSIGN/SIGNRANK/PROBM/PROBS missing.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try data(a, 8);
    const ds = lib.find("d").?;
    for (ds.rows.items, 0..) |r, i| {
        const copy = try a.dupe(Value, r);
        copy[0] = .{ .num = 0 };
        ds.rows.items[i] = copy;
    }
    _ = try run(a, lib, "proc univariate data=d noprint;var x;output out=o msign=m signrank=s probm=pm probs=ps;run;");
    for ([_][]const u8{ "m", "s", "pm", "ps" }) |key| try std.testing.expect(std.math.isNan(cell(lib.find("o").?, 0, key)));
    const listing = try run(a, lib, "proc univariate data=d normal;var x;run;");
    try std.testing.expect(std.mem.indexOf(u8, listing, "Shapiro-Wilk  W  .  .") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "Anderson-Darling  A-Sq  .  .") != null);
}
