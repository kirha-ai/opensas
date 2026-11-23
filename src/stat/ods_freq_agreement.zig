//! Ordered and agreement tests use the statistics already computed for an
//! individual stratum, including its original score order and null hypothesis.
const std = @import("std");
const A = std.mem.Allocator;
const diag = @import("../diag.zig");
const ods = @import("../ods.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const Rows = @import("ods_freq_exact_rows.zig").Rows;
const parse = @import("freq_exact_parse.zig");
const public = @import("freq_exact_public.zig");
const Probabilities = @import("freq_exact_distribution.zig").Probabilities;
const k = @import("freq_stratified.zig");
const strat = @import("freq_stratified_execute.zig");
const config = @import("freq_stratified_parse.zig");
const render = @import("freq_exact_render.zig");

fn val(x: ?f64) Value {
    return if (x) |v| b.n(v) else Value.missing;
}
fn id(a: A, prefix: []const u8, suffix: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}_{s}", .{ prefix, suffix });
}
fn asymptotic(rows: *Rows, name: []const u8, label: []const u8, p: ?f64) !void {
    try rows.add(name, label, try render.probability(rows.a, p, .default), p);
}
fn formatted(rows: *Rows, name: []const u8, label: []const u8, v: ?f64, format: []const u8) !void {
    if (v) |x| try rows.number(name, label, x, format) else try rows.add(name, label, ".", null);
}
fn exactProbability(rows: *Rows, name: []const u8, label: []const u8, p: ?f64) !void {
    try rows.add(name, label, try render.probability(rows.a, p, rows.style), p);
}
fn sided(rows: *Rows, suffix: []const u8, symbol: []const u8, right: bool, v: ?k.Normal) !void {
    try asymptotic(rows, try id(rows.a, if (right) "PR" else "PL", suffix), if (right) "One-sided Pr >  Z" else "One-sided Pr <  Z", if (v) |x| x.p_one else null);
    try asymptotic(rows, try id(rows.a, "P2", suffix), try std.fmt.allocPrint(rows.a, "Two-sided Pr > |{s}|", .{symbol}), if (v) |x| x.p_two else null);
}
fn exactSided(rows: *Rows, suffix: []const u8, short: []const u8, point_suffix: []const u8, symbol: []const u8, distance: []const u8, right: bool, p: ?Probabilities, opt: parse.Options) !void {
    try rows.add("", "", "", null);
    try rows.add("", "Exact Test", "", null);
    try exactProbability(rows, try id(rows.a, if (right) "XPR" else "XPL", short), try std.fmt.allocPrint(rows.a, "One-sided Pr {s}  {s}", .{ if (right) ">=" else "<=", symbol }), if (p) |v| v.one_sided else null);
    if (opt.point) try exactProbability(rows, try id(rows.a, "XPT", point_suffix), try std.fmt.allocPrint(rows.a, "Point     Pr  =  {s}", .{symbol}), if (p) |v| v.point else null);
    if (opt.midp) try exactProbability(rows, try id(rows.a, "XMP", suffix), "Mid p-Value", if (p) |v| @max(0, v.one_sided - v.point / 2) else null);
    try exactProbability(rows, try id(rows.a, "XP2", short), try std.fmt.allocPrint(rows.a, "Two-sided Pr >= |{s}|", .{distance}), if (p) |v| v.two_sided else null);
}
fn ordered(a: A, t: *b.Builder, title: []const u8, jt: bool, v: ?k.Normal, p: ?Probabilities, opt: parse.Options) !void {
    const suffix = if (jt) "JT" else "TREND";
    const short = if (jt) "JT" else "TREN";
    const requested = opt.families.contains(if (jt) .jt else .trend);
    const has_exact = requested and !opt.mc;
    const right = if (v) |x| x.z > 0 else false;
    var rows = try Rows.init(a, t, title, opt.pformat, 1);
    if (jt) {
        try formatted(&rows, "_JT_", if (requested) "Statistic (JT)" else "Statistic", if (v) |x| x.statistic else null, "10.4");
        try formatted(&rows, "Z_JT", "Z", if (v) |x| x.z else null, "10.4");
    } else try formatted(&rows, "_TREND_", "Statistic (Z)", if (v) |x| x.z else null, "10.4");
    if (has_exact) {
        try rows.add("", "", "", null);
        try rows.add("", "Asymptotic Test", "", null);
    }
    try sided(&rows, suffix, "Z", right, v);
    if (has_exact) try exactSided(&rows, suffix, short, short, if (jt) "JT" else "Z", if (jt) "JT - Mean" else "Z", right, p, opt);
    rows.finish();
}
fn numColumn(t: *b.Builder, name: []const u8, label: []const u8, format: []const u8) !void {
    try t.num(name, format);
    if (label.len != 0) t.ds.setLabel(name, label);
}
fn probColumn(a: A, t: *b.Builder, values: *std.ArrayList(Value), name: []const u8, label: []const u8, format: []const u8, p: ?f64) !void {
    try numColumn(t, name, label, format);
    try values.append(a, val(p));
}
fn kappa(a: A, t: *b.Builder, title: []const u8, weighted: bool, result: ?k.Kappa, null_value: f64, requested: bool, opt: parse.Options, p: ?Probabilities, restore: bool) !void {
    const v = if (result) |r| r.test_result else null;
    const right = if (v) |r| r.z > 0 else false;
    const se = if (result) |r| @sqrt(if (null_value == 0) r.null_variance else r.coefficient.variance) else null;
    const has_exact = requested and !opt.mc;
    if (restore) {
        const suffix = if (weighted) "WTKAP" else "KAPPA";
        const short = if (weighted) "WTKA" else "KAPP";
        var rows = try Rows.init(a, t, title, opt.pformat, if (has_exact) 11 else 12);
        if (null_value == 0) try formatted(&rows, try id(a, "E0", suffix), "ASE under H0", se, "8.4") else try rows.number(try id(a, "NULL", suffix), "Null Kappa", null_value, "8.4");
        try formatted(&rows, try id(a, "Z", suffix), "Z", if (v) |x| x.z else null, "8.4");
        try sided(&rows, suffix, "Z", right, v);
        if (has_exact) try exactSided(&rows, suffix, short, if (weighted) suffix else short, "K", "K", right, p, opt);
        rows.finish();
        return;
    }
    var values: std.ArrayList(Value) = .empty;
    try values.append(a, b.s(title));
    try probColumn(a, t, &values, "Estimate", if (requested) "Estimate (K)" else "", "8.4", if (result) |r| r.coefficient.value else null);
    try probColumn(a, t, &values, "Null", "Null Value", "8.4", null_value);
    try probColumn(a, t, &values, "StdErr", if (null_value == 0) "H0 Std Err" else "Standard Error", "8.4", se);
    try probColumn(a, t, &values, "Z", "", "8.4", if (v) |x| x.z else null);
    try probColumn(a, t, &values, "Prob1", if (right) "Pr > Z" else "Pr < Z", "PVALUE6.4", if (v) |x| x.p_one else null);
    try probColumn(a, t, &values, "Prob2", "Pr > |Z|", "PVALUE6.4", if (v) |x| x.p_two else null);
    if (has_exact) {
        const pf = try @import("ods_freq_exact_rows.zig").probabilityFormat(a, opt.pformat);
        try probColumn(a, t, &values, "ExactProb1", if (right) "Exact Pr >= K" else "Exact Pr <= K", pf, if (p) |x| x.one_sided else null);
        if (opt.point) try probColumn(a, t, &values, "ExactPointProb", "Exact Point Pr = K", pf, if (p) |x| x.point else null);
        if (opt.midp) try probColumn(a, t, &values, "ExactMidp", "Exact Mid p-Value", pf, if (p) |x| @max(0, x.one_sided - x.point / 2) else null);
        try probColumn(a, t, &values, "ExactProb2", "Exact Pr >= |K|", pf, if (p) |x| x.two_sided else null);
    }
    try t.row(values.items);
}
fn symmetry(a: A, t: *b.Builder, title: []const u8, two: bool, result: ?k.Chi, agreement: config.Agreement, opts: parse.Options, p: ?Probabilities) !void {
    const requested = opts.families.contains(if (two) .mcnem else .symmetry);
    const has_exact = requested and (two or !opts.mc);
    const x = if (result) |chi| chi.statistic else null;
    const df = if (result) |chi| chi.df else if (two) @as(?f64, 1) else null;
    const prob = if (result) |chi| chi.p else null;
    if (agreement.restore) {
        const suffix = if (two) "MCNEM" else "TSYMM";
        var rows = try Rows.init(a, t, title, opts.pformat, 8);
        if (two and agreement.null_ratio != 1) try rows.number("NULLR_MCNEM", "Null Ratio", agreement.null_ratio, "8.4");
        try formatted(&rows, if (two) "_MCNEM_" else "_TSYMM_", "Statistic (S)", x, "10.4");
        try formatted(&rows, try id(a, "DF", suffix), "DF", df, "best12.");
        try asymptotic(&rows, try id(a, "P", suffix), if (has_exact) "Asymptotic Pr >  S" else "Pr > S", prob);
        if (has_exact) {
            try exactProbability(&rows, try id(a, "XP", suffix), "Exact      Pr >= S", if (p) |v| v.two_sided else null);
            if (opts.point) try exactProbability(&rows, if (two) "XPT_MCNE" else "XPT_TSYMM", "Exact      Pr  = S", if (p) |v| v.point else null);
            if (opts.midp) try exactProbability(&rows, try id(a, "XMP", suffix), "Exact Mid p-Value", if (p) |v| @max(0, v.two_sided - v.point / 2) else null);
        }
        rows.finish();
        return;
    }
    var values: std.ArrayList(Value) = .empty;
    try values.append(a, b.s(title));
    if (two and agreement.null_ratio != 1) try probColumn(a, t, &values, "Null", "Null Ratio", "10.4", agreement.null_ratio);
    try probColumn(a, t, &values, "ChiSquare", "Chi-Square", "10.4", x);
    try probColumn(a, t, &values, "DF", "Degrees of Freedom", "BEST6.", df);
    try probColumn(a, t, &values, "Prob", "Pr > Chi-Square", "PVALUE6.4", prob);
    if (has_exact) {
        const pf = try @import("ods_freq_exact_rows.zig").probabilityFormat(a, opts.pformat);
        try probColumn(a, t, &values, "ExactProb", "Exact Pr >= Chi-Square", pf, if (p) |v| v.two_sided else null);
        if (opts.point) try probColumn(a, t, &values, "ExactPointProb", "Exact Point Pr = Chi-Square", pf, if (p) |v| v.point else null);
        if (opts.midp) try probColumn(a, t, &values, "ExactMidp", "Exact Mid p-Value", pf, if (p) |v| @max(0, v.two_sided - v.point / 2) else null);
    }
    try t.row(values.items);
}

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, title: []const u8, s: strat.Stratum, cfg: config.Options, scope: strat.Scope, opts: parse.Options, exact: public.Tables) diag.Error!void {
    if (s.total <= 0) return;
    const m = s.scored.matrix;
    const ag = cfg.agreement;
    const two = m.rows == 2 and m.cols == 2;
    for ([_]parse.Family{ .jt, .trend }, [_][]const u8{ "JTTest", "TrendTest" }, [_]bool{ cfg.jt, cfg.trend and s.trend_eligible }, [_]?k.Normal{ s.jt, s.trend }) |f, name, needed, value| {
        if (!needed or !capture.wants(name)) continue;
        var t = try b.Builder.init(a, source, by, rep);
        try t.char("Table", 256);
        try ordered(a, &t, title, f == .jt, value, exact.exact_tests.get(f), opts);
        try capture.publish(a, d, name, &t.ds);
    }
    if (!ag.enabled or m.rows < 2 or m.rows != m.cols) return;
    const sym_name = if (two) "McNemarsTest" else "SymmetryTest";
    if (capture.wants(sym_name)) {
        var t = try b.Builder.init(a, source, by, rep);
        try t.char("Table", 256);
        try symmetry(a, &t, title, two, s.symmetry, ag, opts, exact.exact_tests.get(if (two) .mcnem else .symmetry));
        try capture.publish(a, d, sym_name, &t.ds);
    }
    const needs_simple = scope.tests.kappa or (two and opts.families.contains(.wtkappa)) or ag.null_kappa != null;
    for ([_]parse.Family{ .kappa, .wtkappa }, [_][]const u8{ "KappaTest", "WtKappaTest" }, [_]bool{ needs_simple, !two and (scope.tests.weighted_kappa or ag.null_weighted != null) }, [_]?k.Kappa{ s.simple, s.weighted }, [_]?f64{ ag.null_kappa, ag.null_weighted }) |family, name, needed, value, null_kappa| {
        if (!needed or !capture.wants(name)) continue;
        var t = try b.Builder.init(a, source, by, rep);
        try t.char("Table", 256);
        const requested = opts.families.contains(family) or (two and opts.families.contains(.wtkappa));
        try kappa(a, &t, title, family == .wtkappa, value, null_kappa orelse 0, requested, opts, exact.exact_tests.get(family), ag.restore);
        try capture.publish(a, d, name, &t.ds);
    }
}

test "agreement output preserves undefined McNemar tails and rejects incompatible kappa null options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    var library = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const input = try a.create(Dataset);
    input.* = Dataset.init(a, "pairs");
    for ([_][]const u8{ "r", "c", "w" }) |name| _ = try input.addColumn(name, .num);
    for ([_]u32{ 3, 0, 0, 3 }, 0..) |w, i| try input.appendRow(&.{ b.n(@floatFromInt(i / 2 + 1)), b.n(@floatFromInt(i % 2 + 1)), b.n(@floatFromInt(w)) });
    try library.put(input.name, input);
    var capture: ods.Capture = .{};
    var listing: std.ArrayList(u8) = .empty;
    try capture.parse(a, &diagnostics, try lex.tokenize(a, "ods output McNemarsTest=mc;", &diagnostics));
    const context = @import("../proc.zig").ProcCtx{ .arena = a, .lib = &library, .diags = &diagnostics, .capture = &capture };
    try @import("freq.zig").runFreq(context, &listing, try lex.tokenize(a, "proc freq data=pairs;tables r*c / agree;weight w / zeros;exact mcnem / point midp;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    const mc = library.find("mc").?;
    try std.testing.expectEqual(@as(usize, 1), mc.rowCount());
    try std.testing.expectEqual(@as(f64, 1), mc.row(0)[mc.indexOf("DF").?].num);
    for ([_][]const u8{ "ChiSquare", "Prob", "ExactProb", "ExactPointProb", "ExactMidp" }) |name| try std.testing.expect(std.math.isNan(mc.row(0)[mc.indexOf(name).?].num));
    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expectError(error.ParseError, @import("freq.zig").runFreq(context, &listing, try lex.tokenize(a, "proc freq data=pairs;tables r*c / agree(nullkappa=.2 nullwtkappa=.15);exact kappa wtkappa;run;", &diagnostics)));
    const text = try diagnostics.render();
    try std.testing.expect(std.mem.indexOf(u8, text, "NULLKAPPA= option is not available") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "NULLWTKAPPA= option is not available") != null);
}
