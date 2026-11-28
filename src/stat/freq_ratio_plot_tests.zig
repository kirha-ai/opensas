//! STAT-FREQ-019: RELRISKPLOT / ODDSRATIOPLOT for h x 2 x 2 tables (S154
//! Table 47.23, physical p.3257; plot options Table 47.17). Every expected
//! value is hand-derived from the invented 2-stratum table below; nothing is
//! read from a temporary oracle directory.
//!
//!   stratum 1: 3 1 / 1 3 (n=8)      stratum 2: 2 1 / 1 2 (n=6)
//!   RR col1: 3, 2      log variance 1/3-1/4+1-1/4 = 5/6 and 1/2-1/3+1-1/3 = 5/6
//!   RR col2: 1/3, 1/2  log variance 5/6 and 5/6
//!   OR: 9, 4           log variance 1/3+1+1+1/3 = 8/3 and 1/2+1+1+1/2 = 3
//!   MH RR col1: (3*4/8+2*3/6)/(1*4/8+1*3/6) = 2.5/1
//!     variance numerator (4*4*4-3*1*8)/64 + (3*3*3-2*1*6)/36 = 5/8+5/12 = 25/24
//!     log variance (25/24)/(2.5*1) = 5/12; col2 is 1/2.5 with the same 5/12
//!   MH OR: R = 9/8+4/6 = 43/24, S = 1/8+1/6 = 7/24, OR = 43/7
//!     sum PR = (3/4)(9/8)+(2/3)(2/3) = 371/288
//!     sum PS+QR = (3/4)(1/8)+(1/4)(9/8)+(2/3)(1/6)+(1/3)(2/3) = 17/24
//!     sum QS = (1/4)(1/8)+(1/3)(1/6) = 25/288
const std = @import("std");
const t = std.testing;
const diag = @import("../diag.zig");
const plots = @import("freq_plots.zig");
const svg = @import("graphics_svg.zig");

// Upper 2.5% standard normal point, a published constant.
const z = 1.959963984540054;
const Expect = struct { label: []const u8, value: f64, log_variance: f64 };
const rr1 = [_]Expect{ .{ .label = "1", .value = 3, .log_variance = 5.0 / 6.0 }, .{ .label = "2", .value = 2, .log_variance = 5.0 / 6.0 }, .{ .label = "Common", .value = 2.5, .log_variance = 5.0 / 12.0 } };
const rr2 = [_]Expect{ .{ .label = "1", .value = 1.0 / 3.0, .log_variance = 5.0 / 6.0 }, .{ .label = "2", .value = 0.5, .log_variance = 5.0 / 6.0 }, .{ .label = "Common", .value = 0.4, .log_variance = 5.0 / 12.0 } };
const or_r = 43.0 / 24.0;
const or_s = 7.0 / 24.0;
const odds = [_]Expect{ .{ .label = "1", .value = 9, .log_variance = 8.0 / 3.0 }, .{ .label = "2", .value = 4, .log_variance = 3 }, .{ .label = "Common", .value = 43.0 / 7.0, .log_variance = (371.0 / 288.0) / (2 * or_r * or_r) + (17.0 / 24.0) / (2 * or_r * or_s) + (25.0 / 288.0) / (2 * or_s * or_s) } };

const Run = struct { rc: u8, errors: bool, files: usize, first: []const u8, d: diag.Diagnostics, listing: []const u8 };
fn run(a: std.mem.Allocator, enabled: bool, options: []const u8) !Run {
    const ds = try a.create(@import("../dataset.zig").Dataset);
    ds.* = .init(a, "t");
    for ([_][]const u8{ "s", "r", "c", "n" }) |name| _ = try ds.addColumn(name, .num);
    const cells = [_][4]f64{ .{ 1, 1, 1, 3 }, .{ 1, 1, 2, 1 }, .{ 1, 2, 1, 1 }, .{ 1, 2, 2, 3 }, .{ 2, 1, 1, 2 }, .{ 2, 1, 2, 1 }, .{ 2, 2, 1, 1 }, .{ 2, 2, 2, 2 } };
    for (cells) |c| try ds.appendRow(&.{ .{ .num = c[0] }, .{ .num = c[1] }, .{ .num = c[2] }, .{ .num = c[3] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("t", ds);
    var d = diag.Diagnostics.init(a);
    var dir = t.tmpDir(.{ .iterate = true });
    defer dir.cleanup();
    var listing = @import("../ods_listing.zig").Listing{ .trace = &d };
    var graphs = svg.Session{ .arena = a, .io = t.io, .diags = &d, .enabled = enabled, .listing = &listing, .gpath = try dir.dir.realPathFileAlloc(t.io, ".", a) };
    var output: std.ArrayList(u8) = .empty;
    const program = try std.fmt.allocPrint(a, "proc freq data=t; weight n; tables s*r*c / {s}; run;", .{options});
    diag.resetGap();
    defer diag.resetGap();
    const failed = if (@import("freq.zig").runFreq(.{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphs, .listing = &listing }, &output, try @import("../lexer.zig").tokenize(a, program, &d))) |_| false else |_| true;
    if (!failed) try graphs.flush();
    var files: usize = 0;
    var first: []const u8 = "";
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.dir.iterate();
    while (try it.next(t.io)) |entry| try names.append(a, try a.dupe(u8, entry.name));
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lt);
    for (names.items) |name| {
        if (!std.mem.endsWith(u8, name, ".svg")) continue;
        if (files == 0) first = try a.dupe(u8, name);
        files += 1;
    }
    var bytes: []const u8 = "";
    if (files > 0) bytes = try dir.dir.readFileAlloc(t.io, first, a, .limited(1 << 20));
    return .{ .rc = diag.exitCode(diag.gapHit(), d.hasErrors() or failed), .errors = d.hasErrors(), .files = files, .first = try std.fmt.allocPrint(a, "{s}\n{s}", .{ first, bytes }), .d = d, .listing = output.items };
}
fn attr(node: []const u8, name: []const u8) !f64 {
    const key = try std.fmt.allocPrint(t.allocator, " {s}=\"", .{name});
    defer t.allocator.free(key);
    const start = (std.mem.indexOf(u8, node, key) orelse return error.MissingSvgAttribute) + key.len;
    return std.fmt.parseFloat(f64, node[start .. start + std.mem.indexOfScalar(u8, node[start..], '"').?]);
}
fn logged(d: diag.Diagnostics, needle: []const u8) bool {
    for (d.list.items) |entry| if (std.mem.indexOf(u8, entry.message, needle) != null) return true;
    return false;
}
/// Each estimate group carries the value and limits; marker and error-bar
/// pixels must equal the documented axis mapping of those numbers.
fn expectGraph(a: std.mem.Allocator, graph: []const u8, expected: []const Expect, base: plots.LogBase, lo: f64, hi: f64, width: f64) !void {
    var groups = std.mem.splitSequence(u8, graph, "<g class=\"estimate");
    _ = groups.next();
    var i: usize = 0;
    while (groups.next()) |group| : (i += 1) {
        const e = expected[i];
        const node = group[0..std.mem.indexOf(u8, group, "</g>").?];
        try t.expect(std.mem.indexOf(u8, node, try std.fmt.allocPrint(a, "data-label=\"{s}\"", .{e.label})) != null);
        try t.expectEqual(std.mem.eql(u8, e.label, "Common"), std.mem.startsWith(u8, node, " common\""));
        const half = z * @sqrt(e.log_variance);
        const want = [3]f64{ e.value, e.value * @exp(-half), e.value * @exp(half) };
        try t.expectApproxEqRel(want[0], try attr(node, "data-value"), 1e-12);
        try t.expectApproxEqRel(want[1], try attr(node, "data-lower"), 1e-9);
        try t.expectApproxEqRel(want[2], try attr(node, "data-upper"), 1e-9);
        var px: [3]f64 = undefined;
        for (want, &px) |v, *x| {
            const u = switch (base) {
                .none => v,
                .two => @log(v) / @log(2.0),
                .e => @log(v),
                .ten => @log(v) / @log(10.0),
            };
            x.* = 150 + width * (u - lo) / (hi - lo);
        }
        const y = 62 + 34 * (@as(f64, @floatFromInt(i)) + 0.5);
        const bar = try std.fmt.allocPrint(a, "d=\"M{d:.2} {d:.2}H{d:.2}M", .{ px[1], y, px[2] });
        try t.expect(std.mem.indexOf(u8, node, bar) != null);
        const marker = if (std.mem.eql(u8, e.label, "Common")) try std.fmt.allocPrint(a, "class=\"diamond\" d=\"M{d:.2} {d:.2}l", .{ px[0], y - 6 }) else try std.fmt.allocPrint(a, "class=\"dot\" cx=\"{d:.2}\" cy=\"{d:.2}\"", .{ px[0], y });
        try t.expect(std.mem.indexOf(u8, node, marker) != null);
    }
    try t.expectEqual(expected.len, i);
}

test "FREQ019 RELRISKPLOT plots hand-derived stratum and Mantel-Haenszel relative risks with STATS text" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(stats)");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expectEqual(@as(usize, 1), r.files);
    try t.expect(std.mem.startsWith(u8, r.first, "opensas-0001-relriskplot.svg\n"));
    try t.expect(std.mem.indexOf(u8, r.first, "data-kind=\"relriskplot\"") != null);
    try t.expect(std.mem.indexOf(u8, r.first, "<title>Relative Risks with 95% Wald Confidence Limits</title>") != null);
    try t.expect(std.mem.indexOf(u8, r.first, ">Relative Risk (Column 1)</text>") != null);
    try t.expect(std.mem.indexOf(u8, r.first, "data-scale=\"linear\"") != null);
    // Largest upper limit 3*exp(z*sqrt(5/6)) = 17.96, so the linear axis is 0..20.
    try expectGraph(a, r.first, &rr1, .none, 0, 20, 300);
    // Reference line at the null value one: 150 + 300*1/20.
    try t.expect(std.mem.indexOf(u8, r.first, "class=\"reference\" data-value=\"1\" x1=\"165.00\"") != null);
    // STATS column: value and limits to four decimals, right of the plot.
    // exp(z*sqrt(5/6)) = exp(1.789194) = 5.98463: 3 -> 0.5013, 17.9539; 2 -> 0.3342, 11.9693.
    // exp(z*sqrt(5/12)) = exp(1.265151) = 3.54363: 2.5 -> 0.7055, 8.8591.
    for ([_][]const u8{ ">3.0000<", ">0.5013<", ">17.9539<", ">2.0000<", ">0.3342<", ">11.9693<", ">2.5000<", ">0.7055<", ">8.8591<" }) |cell| try t.expect(std.mem.indexOf(u8, r.first, cell) != null);
    try t.expectEqual(@as(usize, 9), std.mem.count(u8, r.first, "class=\"stat\""));
    try t.expect(std.mem.indexOf(u8, r.first, ">95% Confidence Limits</text>") != null);
    // Identity: documented graph name, label and table path; no invented template.
    try t.expect(logged(r.d, "Name:       RelRiskPlot\nLabel:      Relative Risk Plot\nPath:       Freq.Table1.RelRiskPlot"));
    try t.expect(!logged(r.d, "ORPlot"));
}

test "FREQ019 RELRISKPLOT COLUMN=2 LOGBASE= ORDER= and COMMON=NO mapping" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Column 2 limits: 1/3*exp(-z*sqrt(5/6)) = 0.0557 -> log2 -4.17; 0.5*exp(+) = 2.99 -> log2 1.58.
    // The base-2 axis therefore spans exponents -5..2, without STATS 490 px wide.
    var r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(column=2 logbase=2)");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expect(std.mem.indexOf(u8, r.first, "data-scale=\"two\"") != null);
    try t.expect(std.mem.indexOf(u8, r.first, ">Relative Risk (Column 2)</text>") != null);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, r.first, "class=\"stat\""));
    try expectGraph(a, r.first, &rr2, .two, -5, 2, 490);
    // Tick labels are ratios at integer exponents: 2^-5 .. 2^2; one sits at 150+490*5/7.
    for ([_][]const u8{ ">0.0313<", ">0.0625<", ">0.125<", ">0.25<", ">0.5<", ">1<", ">2<", ">4<" }) |label| try t.expect(std.mem.indexOf(u8, r.first, label) != null);
    try t.expect(std.mem.indexOf(u8, r.first, "class=\"reference\" data-value=\"1\" x1=\"500.00\"") != null);
    // Base 10: col1 limits 0.3341..17.96 -> exponents -1..2.
    r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(logbase=10)");
    try expectGraph(a, r.first, &rr1, .ten, -1, 2, 490);
    // Natural log: ln(0.3341) = -1.10, ln(17.96) = 2.89 -> exponents -2..3.
    r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(logbase=e)");
    try expectGraph(a, r.first, &rr1, .e, -2, 3, 490);
    // ORDER=ASCENDING sorts strata by value (2 before 3); the common row stays last.
    r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(order=ascending)");
    try expectGraph(a, r.first, &.{ rr1[1], rr1[0], rr1[2] }, .none, 0, 20, 490);
    r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(order=descending column=2)");
    try expectGraph(a, r.first, &.{ rr2[1], rr2[0], rr2[2] }, .none, 0, 3, 490);
    // COMMON=NO, and no CMH, both leave only the stratum rows.
    r = try run(a, true, "relrisk cmh noprint plots(only)=relriskplot(common=no)");
    try expectGraph(a, r.first, rr1[0..2], .none, 0, 20, 490);
    r = try run(a, true, "relrisk noprint plots(only)=relriskplot");
    try expectGraph(a, r.first, rr1[0..2], .none, 0, 20, 490);
}

test "FREQ019 ODDSRATIOPLOT plots hand-derived stratum and Mantel-Haenszel odds ratios as ORPlot" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Largest upper limit 9*exp(z*sqrt(8/3)) = 221.0 -> tick step 50, linear axis 0..250.
    var r = try run(a, true, "relrisk cmh noprint plots(only)=oddsratioplot(stats)");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expectEqual(@as(usize, 1), r.files);
    try t.expect(std.mem.startsWith(u8, r.first, "opensas-0001-oddsratioplot.svg\n"));
    try t.expect(std.mem.indexOf(u8, r.first, "<title>Odds Ratios with 95% Wald Confidence Limits</title>") != null);
    try expectGraph(a, r.first, &odds, .none, 0, 250, 300);
    try t.expect(logged(r.d, "Name:       ORPlot\nLabel:      Odds Ratio Plot\nPath:       Freq.Table1.ORPlot"));
    // OR and MEASURES are the other documented triggers; log base 10 spans 10^-1..10^3.
    r = try run(a, true, "or cmh noprint plots(only)=oddsratioplot(logbase=10)");
    try t.expectEqual(@as(usize, 1), r.files);
    try expectGraph(a, r.first, &odds, .ten, -1, 3, 490);
    r = try run(a, true, "measures cmh noprint plots(only)=(oddsratioplot relriskplot)");
    try t.expectEqual(@as(usize, 2), r.files);
    // ALPHA= reaches the title; the 90% limits are narrower than the 95% ones.
    r = try run(a, true, "relrisk cmh alpha=0.1 noprint plots(only)=oddsratioplot");
    try t.expect(std.mem.indexOf(u8, r.first, "Odds Ratios with 90% Wald Confidence Limits") != null);
    const node = r.first[std.mem.indexOf(u8, r.first, "<g class=\"estimate\"").?..];
    // z(0.05) = 1.6448536269514722.
    try t.expectApproxEqRel(9 * @exp(1.6448536269514722 * @sqrt(8.0 / 3.0)), try attr(node, "data-upper"), 1e-9);
}

test "FREQ019 ratio plot triggering, suppression, gaps and user errors" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // ODS GRAPHICS OFF and PLOTS=NONE write nothing and are not errors.
    var r = try run(a, false, "relrisk cmh noprint plots(only)=relriskplot(stats)");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expectEqual(@as(usize, 0), r.files);
    r = try run(a, true, "relrisk cmh noprint plots=none");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expectEqual(@as(usize, 0), r.files);
    // Without the TABLES option that computes the ratios there is no graph;
    // the OR option computes odds ratios only.
    r = try run(a, true, "cmh noprint plots(only)=(relriskplot oddsratioplot)");
    try t.expectEqual(@as(u8, 0), r.rc);
    try t.expectEqual(@as(usize, 0), r.files);
    r = try run(a, true, "or cmh noprint plots(only)=(relriskplot oddsratioplot)");
    try t.expectEqual(@as(usize, 1), r.files);
    try t.expect(std.mem.startsWith(u8, r.first, "opensas-0001-oddsratioplot.svg\n"));
    // PLOTS(ONLY) keeps exactly the requested graph next to another request.
    r = try run(a, true, "relrisk cmh plots(only)=freqplot(twoway=cluster)");
    try t.expectEqual(@as(usize, 2), r.files);
    try t.expect(!logged(r.d, "RelRiskPlot") and !logged(r.d, "ORPlot"));
    // Documented but unrendered requests are loud gaps (rc 2) ...
    for ([_][]const u8{ "relriskplot(cl=score)", "oddsratioplot(cl=exact)", "relriskplot(exact)", "relriskplot(range=clip)", "oddsratioplot(npanelpos=2)", "relriskplot(cldisplay=line)", "riskdiffplot", "kappaplot", "wtkappaplot", "all" }) |request| {
        r = try run(a, true, try std.fmt.allocPrint(a, "relrisk cmh noprint plots(only)={s}", .{request}));
        try t.expectEqual(@as(u8, 2), r.rc);
        try t.expect(logged(r.d, "PROC FREQ: unsupported"));
        try t.expectEqual(@as(usize, 0), r.files);
    }
    // ... undocumented names and values are the user's errors (rc 1).
    for ([_][]const u8{ "bogusplot", "relriskplot(column=3)", "oddsratioplot(column=2)", "relriskplot(logbase=3)", "relriskplot(order=data)", "relriskplot(cl=midp)", "relriskplot(nonsense)", "relriskplot(common=maybe)" }) |request| {
        r = try run(a, true, try std.fmt.allocPrint(a, "relrisk cmh noprint plots(only)={s}", .{request}));
        try t.expectEqual(@as(u8, 1), r.rc);
        try t.expectEqual(@as(usize, 0), r.files);
    }
}

test "FREQ019 ratio axis helpers: range always contains one and log positions are exponents" {
    const rows = [_]plots.RatioRow{.{ .label = "a", .value = 4, .lower = 2, .upper = 8 }};
    const linear = plots.ratioRange(&rows, .none);
    try t.expectEqual(@as(f64, 0), linear.lo);
    try t.expectEqual(@as(f64, 8), linear.hi);
    const log2 = plots.ratioRange(&rows, .two);
    try t.expectEqual(@as(f64, 0), log2.lo); // log2(1): the null value stays visible
    try t.expectEqual(@as(f64, 3), log2.hi);
    try t.expectApproxEqAbs(@as(f64, 2.0 / 3.0), plots.ratioPosition(4, log2, .two), 1e-15);
    try t.expectApproxEqAbs(@as(f64, 0.5), plots.ratioPosition(4, linear, .none), 1e-15);
    // An undefined stratum estimate keeps its row but contributes no extent.
    const missing = [_]plots.RatioRow{.{ .label = "a" }};
    const empty = plots.ratioRange(&missing, .ten);
    try t.expectEqual(@as(f64, 0), empty.lo);
    try t.expectEqual(@as(f64, 1), empty.hi);
}
