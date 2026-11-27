//! Minimal POWER consumer of the shared numerical inversion contract.
//! Scalar ONESAMPLEMEANS TEST=T and balanced TWOSAMPLEMEANS TEST=DIFF.
//! S154 physical pp.7780-7786 and 7820-7830 define their defaults/options.
//! Other analyses, list scenarios and allocation specifications remain loud gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const means = @import("power_means.zig");
const parser = @import("../parser.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Scenario = struct { kind: means.Kind = .two_sample, line: usize = 0, difference: ?f64 = null, effect_seen: bool = false, sigma: ?f64 = null, sigma_seen: bool = false, alpha: f64 = 0.05, alpha_explicit: bool = false, sides_explicit: bool = false, null_explicit: bool = false, null_difference: f64 = 0, power: ?f64 = null, n: ?f64 = null, power_seen: bool = false, n_seen: bool = false };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, name);
}
fn invalid(cx: proc.ProcCtx, line: usize, comptime text: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC POWER: " ++ text, .{});
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!?f64 {
    if (at(t, i.*, .dot)) {
        i.* += 1;
        return null;
    }
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, 0, "expected a numeric scalar or missing value");
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t[i.*].line, "invalid number");
    i.* += 1;
    return sign * v;
}
fn listed(name: []const u8, names: []const []const u8) bool {
    for (names) |candidate| if (eq(name, candidate)) return true;
    return false;
}
// Documented POWER/TWOSAMPLEMEANS vocabulary (S154 physical pp.7744-7745,
// 7820-7827). Unknown spellings are user errors; recognized gaps remain rc 2.
fn unsupportedOption(kind: means.Kind, name: []const u8) bool {
    if (kind == .one_sample) return listed(name, &.{ "ci", "cv", "halfwidth", "lower", "nfractional", "nfrac", "outputorder", "probtype", "probwidth", "upper" });
    return listed(name, &.{ "ci", "cv", "groupmeans", "gmeans", "groupns", "gns", "groupstddevs", "gstddevs", "groupstds", "gstds", "groupweights", "gweights", "halfwidth", "lower", "meanratio", "nfractional", "nfrac", "npergroup", "nperg", "nullratio", "nullr", "outputorder", "probtype", "probwidth", "upper" });
}
pub const Options = struct { plotonly: bool = false };
pub const Result = struct { sample_size: f64, power: f64 };
/// PROC POWER has no DATA= contract: scenarios are supplied by analysis
/// statements, and never implicitly consume the latest WORK dataset.
/// The sole PROC option, PLOTONLY, controls presentation, not computation.
pub fn declaration(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!Options {
    var options: Options = .{};
    while (i.* < t.len and !at(t, i.*, .semicolon) and !at(t, i.*, .eof)) {
        if (!kw(t, i.*, "plotonly")) return invalid(cx, t[i.*].line, "unknown procedure option");
        options.plotonly = true;
        i.* += 1;
    }
    if (!at(t, i.*, .semicolon)) return invalid(cx, if (t.len > 0) t[0].line else 0, "missing PROC POWER semicolon");
    i.* += 1;
    return options;
}
/// Typed result contract for subsequent analysis/output consumers. Unsupported
/// requests return captured diagnostics rather than plausible missing rows.
pub fn compute(cx: proc.ProcCtx, s: Scenario) diag.Error!Result {
    const unknowns = @as(u8, @intFromBool(s.difference == null)) + @as(u8, @intFromBool(s.sigma == null)) + @as(u8, @intFromBool(s.power == null)) + @as(u8, @intFromBool(s.n == null));
    if (unknowns == 1 and s.power_seen and s.n_seen and ((s.difference == null and s.effect_seen) or (s.sigma == null and s.sigma_seen))) return proc.failGap(cx.diags, s.line, "PROC POWER: solving for the effect or standard deviation is not implemented", .{});
    if (s.difference == null or s.sigma == null or !s.power_seen or !s.n_seen or (s.power == null) == (s.n == null)) return invalid(cx, s.line, "MEAN (one sample) or MEANDIFF (two samples), STDDEV, POWER and NTOTAL are required; exactly one of POWER or NTOTAL must be missing");
    const d: means.Design = .{ .kind = s.kind, .difference = s.difference.? - s.null_difference, .sigma = s.sigma.?, .alpha = s.alpha };
    if (!d.valid()) return invalid(cx, s.line, "STDDEV must be positive and ALPHA must lie strictly between zero and one");
    var n: f64 = undefined;
    var power: f64 = undefined;
    if (s.n) |given| {
        if (given < d.minimumN() or @floor(given) != given) return invalid(cx, s.line, "NTOTAL must be an integer with at least two observations per group");
        if (s.kind == .two_sample and @mod(given, 2) != 0) return proc.failGap(cx.diags, s.line, "PROC POWER: odd NTOTAL allocation adjustment is not implemented", .{});
        n = given;
        power = d.power(n);
    } else {
        if (s.power.? <= 0 or s.power.? >= 1) return invalid(cx, s.line, "POWER must lie strictly between zero and one");
        const result = d.sampleSize(s.power.?);
        if (result.status != .converged) return proc.failGap(cx.diags, s.line, "PROC POWER: sample-size inversion did not converge ({s})", .{@tagName(result.status)});
        n = d.executable(result.x);
        power = d.power(n);
    }
    if (!std.math.isFinite(power)) return proc.failGap(cx.diags, s.line, "PROC POWER: exact power is outside the implemented numerical domain", .{});
    return .{ .sample_size = n, .power = power };
}
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Scenario, result: Result) diag.Error!void {
    const n = result.sample_size;
    const power = result.power;
    try out.appendSlice(cx.arena, "The POWER Procedure\n");
    try out.appendSlice(cx.arena, if (s.kind == .one_sample) "One-Sample t Test for Mean\n" else "Two-Sample t Test for Mean Difference\n");
    try out.appendSlice(cx.arena, "\nFixed Scenario Elements\n\nDistribution Normal\nMethod Exact\n");
    const mean_label = if (s.kind == .one_sample) "Mean" else "Mean Difference";
    const null_label = if (s.kind == .one_sample) "Null Mean" else "Null Difference";
    // Fixed elements list supplied parameters before defaults, each in the
    // documented internal order (S154 physical pp.7824 and 7855).
    if (s.sides_explicit) try out.appendSlice(cx.arena, "Number of Sides 2\n");
    if (s.null_explicit) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ null_label, s.null_difference }));
    if (s.alpha_explicit) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Alpha {d}\n", .{s.alpha}));
    const fixed = try std.fmt.allocPrint(cx.arena, "{s} {d}\nStandard Deviation {d}\n", .{ mean_label, s.difference.?, s.sigma.? });
    try out.appendSlice(cx.arena, fixed);
    try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ if (s.n == null) "Nominal Power" else "Total Sample Size", if (s.n == null) s.power.? else n }));
    if (!s.sides_explicit) try out.appendSlice(cx.arena, "Number of Sides 2\n");
    if (!s.null_explicit) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ null_label, s.null_difference }));
    if (!s.alpha_explicit) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Alpha {d}\n", .{s.alpha}));
    if (s.kind == .two_sample) try out.appendSlice(cx.arena, "Group 1 Weight 1\nGroup 2 Weight 1\n");
    try out.appendSlice(cx.arena, "\n");
    if (s.n == null) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed N Total\n\nActual N\nPower Total\n\n{d:.3} {d:.0}\n\n", .{ power, n })) else try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed Power\n\nPower\n\n{d:.3}\n", .{power}));
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    var i: usize = 2;
    const options = try declaration(cx, t, &i);
    var analyses: usize = 0;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        if (kw(t, i, "run") or kw(t, i, "quit")) break;
        if (at(t, i, .name) and parser.isMidStepSkippable(t[i].text)) {
            const start = i;
            while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) i += 1;
            try parser.noteUnexecuted(cx.diags, t[start..i]);
            if (at(t, i, .semicolon)) i += 1;
            continue;
        }
        if (!kw(t, i, "twosamplemeans") and !kw(t, i, "onesamplemeans")) {
            if (listed(t[i].text, &.{ "coxreg", "custom", "logistic", "multreg", "onecorr", "onesamplefreq", "onesamplemeans", "onewayanova", "pairedfreq", "pairedmeans", "plot", "twosamplefreq", "twosamplesurvival", "twosamplewilcoxon" })) return proc.failGap(cx.diags, t[i].line, "PROC POWER: statement {s} is not implemented", .{t[i].text});
            return invalid(cx, t[i].line, "unknown analysis statement");
        }
        var s: Scenario = .{ .kind = if (kw(t, i, "onesamplemeans")) .one_sample else .two_sample, .line = t[i].line };
        i += 1;
        while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
            if (!at(t, i, .name)) return proc.failGap(cx.diags, 0, "PROC POWER: scenario lists are not implemented", .{});
            const name = t[i].text;
            const line = t[i].line;
            i += 1;
            if (eq(name, "test") and !at(t, i, .eq)) continue;
            if (!at(t, i, .eq)) {
                if (unsupportedOption(s.kind, name)) return proc.failGap(cx.diags, line, "PROC POWER: option {s} is not implemented", .{name});
                return invalid(cx, line, "expected option=value");
            }
            i += 1;
            if (eq(name, "test") or eq(name, "dist")) {
                if (!kw(t, i, if (eq(name, "test")) (if (s.kind == .one_sample) "t" else "diff") else "normal")) {
                    if (i < t.len and listed(t[i].text, if (eq(name, "test")) (if (s.kind == .one_sample) &.{"equiv"} else &.{ "diff_satt", "equiv_diff", "equiv_ratio", "ratio" }) else &.{"lognormal"})) return proc.failGap(cx.diags, line, "PROC POWER: only the default normal two-sided t test is implemented", .{});
                    return invalid(cx, line, "unknown TEST or DIST value");
                }
                i += 1;
                continue;
            }
            const mean_option = if (s.kind == .one_sample) "mean" else "meandiff";
            const null_option = if (s.kind == .one_sample) "nullmean" else "nulldiff";
            const null_alias = if (s.kind == .one_sample) "nullm" else "nulld";
            if (!eq(name, mean_option) and !eq(name, "stddev") and !eq(name, "std") and !eq(name, "alpha") and !eq(name, "power") and !eq(name, "ntotal") and !eq(name, "sides") and !eq(name, null_option) and !eq(name, null_alias)) {
                if (unsupportedOption(s.kind, name)) return proc.failGap(cx.diags, line, "PROC POWER: option {s} is not implemented", .{name});
                return invalid(cx, line, "unknown mean-analysis option");
            }
            if (eq(name, "sides") and (kw(t, i, "u") or kw(t, i, "l"))) return proc.failGap(cx.diags, line, "PROC POWER: only SIDES=2 is implemented", .{});
            const v = try number(cx, t, &i);
            if (eq(name, mean_option)) {
                s.difference = v;
                s.effect_seen = true;
            } else if (eq(name, "stddev") or eq(name, "std")) {
                s.sigma = v;
                s.sigma_seen = true;
            } else if (eq(name, "alpha")) {
                s.alpha = v orelse return proc.failGap(cx.diags, line, "PROC POWER: solving for ALPHA is not implemented", .{});
                s.alpha_explicit = true;
            } else if (eq(name, "power")) {
                s.power = v;
                s.power_seen = true;
            } else if (eq(name, "ntotal")) {
                s.n = v;
                s.n_seen = true;
            } else if (eq(name, "sides")) {
                s.sides_explicit = true;
                if (v == null or (v.? != 1 and v.? != 2)) return invalid(cx, line, "invalid SIDES value");
                if (v.? == 1) return proc.failGap(cx.diags, line, "PROC POWER: only SIDES=2 is implemented", .{});
            } else {
                s.null_difference = v orelse return invalid(cx, line, "null mean or difference must be nonmissing");
                s.null_explicit = true;
            }
        }
        if (!at(t, i, .semicolon)) return invalid(cx, 0, "missing statement semicolon");
        i += 1;
        const result = try compute(cx, s);
        if (!options.plotonly) try render(cx, out, s, result);
        analyses += 1;
    }
    if (analyses == 0) return invalid(cx, if (t.len > 0) t[0].line else 0, "at least one analysis statement is required");
}

test "STAT-COMMON-018 unsupported options and invalid inputs remain captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    for ([_][]const u8{
        "proc power; twosamplemeans meandiff=2 stddev=0 power=. ntotal=100; run;",
        "proc power; twosamplemeans meandiff=2 stddev=3 power=. ntotal=.; run;",
        "proc power; twosamplemeans meandiff=2 stddev=3 power=. ntotal=100 sides=1; run;",
        "proc power; twosamplemeans meandiff=2 stddev=3 power=. ntotal=100 groupweights=(1 2); run;",
        "proc power; twosamplemeans meandif=2 stddev=3 power=. ntotal=100; run;",
        "proc power; twosampelmeans; run;",
        "proc power; twosamplemeans test=typo meandiff=2 stddev=3 power=. ntotal=100; run;",
        "proc power; twosamplemeans meandiff=0 stddev=3 power=0.01 ntotal=.; run;",
    }, 0..) |source, index| {
        diag.resetGap();
        defer diag.resetGap();
        var diagnostics = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const tokens = try lex.tokenize(a, source, &diagnostics);
        const result = run(.{ .arena = a, .lib = &lib, .diags = &diagnostics }, &out, tokens);
        try std.testing.expectError(error.ParseError, result);
        try std.testing.expect(diagnostics.list.items.len > 0);
        try std.testing.expectEqual(@as(u8, if (index == 2 or index == 3 or index == 7) 2 else 1), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "STAT-POWER-001 declarations default to listing and PLOTONLY only suppresses presentation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{ "proc power;", "proc power plotonly;", "proc power PlOtOnLy plotonly;" }, 0..) |source, index| {
        const tokens = try lex.tokenize(a, source, &diagnostics);
        var i: usize = 2;
        const options = try declaration(cx, tokens, &i);
        try std.testing.expectEqual(index != 0, options.plotonly);
        try std.testing.expect(at(tokens, i, .eof));
    }
    const body = "twosamplemeans test meandiff=2 stddev=3 ntotal=100 power=.; run;";
    var shown: std.ArrayList(u8) = .empty;
    var hidden: std.ArrayList(u8) = .empty;
    try run(cx, &shown, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc power; {s}", .{body}), &diagnostics));
    try run(cx, &hidden, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc power plotonly; {s}", .{body}), &diagnostics));
    try std.testing.expect(shown.items.len > 0);
    try std.testing.expectEqual(@as(usize, 0), hidden.items.len);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
    // A default analysis never reads the latest dataset, even when it has a
    // missing observation and no variable matching any scenario parameter.
    var input = @import("../dataset.zig").Dataset.init(a, "irrelevant");
    _ = try input.addColumn("unrelated", .num);
    try input.appendRow(&.{@import("../value.zig").Value.missing});
    try lib.put("irrelevant", &input);
    var again: std.ArrayList(u8) = .empty;
    try run(cx, &again, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc power; {s}", .{body}), &diagnostics));
    try std.testing.expectEqualStrings(shown.items, again.items);
    const numeric = try compute(cx, .{ .difference = 2, .sigma = 3, .power_seen = true, .n_seen = true, .n = 100 });
    try std.testing.expectEqual(@as(f64, 100), numeric.sample_size);
    try std.testing.expect(@abs(numeric.power - 0.910) < 0.0005);
}

test "STAT-POWER-001 prerequisites and locations stay visible under PLOTONLY" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const Case = struct { source: []const u8, line: usize, code: u8 };
    for ([_]Case{
        .{ .source = "proc power; run;", .line = 1, .code = 1 },
        .{ .source = "proc power\n data=missing; run;", .line = 2, .code = 1 },
        .{ .source = "proc power plotonly;\n twosamplemeans meandiff=2 stddev=. ntotal=100 power=.; run;", .line = 2, .code = 1 },
        .{ .source = "proc power plotonly;\n onewayanova test=overall; run;", .line = 2, .code = 2 },
        .{ .source = "proc power plotonly;\n twosamplemeans meandiff=2 stddev=3 ntotal=100 power=.;\n plot x=n; run;", .line = 3, .code = 2 },
    }) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var diagnostics = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const tokens = try lex.tokenize(a, case.source, &diagnostics);
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &diagnostics }, &out, tokens));
        try std.testing.expectEqual(case.code, diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try std.testing.expectEqual(case.line, diagnostics.list.items[0].line);
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "STAT-POWER-001 multiple analyses and mid-step inert globals preserve boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const tokens = try lex.tokenize(a, "proc power; goptions reset=all; twosamplemeans meandiff=2 stddev=3 ntotal=100 power=.; dm 'log;clear'; twosamplemeans meandiff=2 stddev=3 ntotal=100 power=.; run;", &diagnostics);
    try run(.{ .arena = a, .lib = &lib, .diags = &diagnostics }, &out, tokens);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "The POWER Procedure"));
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-POWER-002 one-sample default agrees with explicit settings and remains distinct from two-sample" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const original = try compute(cx, .{ .kind = .one_sample, .difference = 8, .sigma = 40, .power_seen = true, .n_seen = true, .n = 150 });
    const shifted = try compute(cx, .{ .kind = .one_sample, .difference = 12, .null_difference = 4, .sigma = 40, .power_seen = true, .n_seen = true, .n = 150 });
    try std.testing.expectEqual(original, shifted);
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, "proc power; onesamplemeans test=t dist=normal mean=8 stddev=40 ntotal=150 power=. sides=2 nullmean=0 alpha=.05; run;", &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "One-Sample t Test for Mean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.682") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Group 1 Weight") == null);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
    const cases = [_][]const u8{
        "proc power; onesamplemeans meandiff=8 stddev=40 ntotal=150 power=.; run;",
        "proc power; twosamplemeans mean=8 stddev=40 ntotal=150 power=.; run;",
        "proc power; onesamplemeans test=diff mean=8 stddev=40 ntotal=150 power=.; run;",
        "proc power; onesamplemeans mean=8 stddev=40 ntotal=1 power=.; run;",
    };
    for (cases) |source| {
        diag.resetGap();
        defer diag.resetGap();
        var bad = diag.Diagnostics.init(a);
        var rejected: std.ArrayList(u8) = .empty;
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &bad }, &rejected, try lex.tokenize(a, source, &bad)));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), bad.hasErrors()));
    }
}

test "STAT-POWER-002 valid missing effect and scale solutions remain unsupported not user errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    for ([_][]const u8{
        "proc power; onesamplemeans mean=. stddev=40 ntotal=150 power=.8; run;",
        "proc power; onesamplemeans mean=8 stddev=. ntotal=150 power=.8; run;",
        "proc power; twosamplemeans meandiff=. stddev=40 ntotal=150 power=.8; run;",
    }) |source| {
        diag.resetGap();
        defer diag.resetGap();
        var diagnostics = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &diagnostics }, &out, try lex.tokenize(a, source, &diagnostics)));
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}
