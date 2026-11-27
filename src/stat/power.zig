//! Minimal POWER consumer of the shared numerical inversion contract.
//! TWOSAMPLEMEANS scalar equal-allocation TEST=DIFF: S154 physical pp.7820-7830.
//! Other analyses, list scenarios and allocation specifications remain loud gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const means = @import("power_means.zig");
const eq = std.ascii.eqlIgnoreCase;
const Scenario = struct { difference: ?f64 = null, sigma: ?f64 = null, alpha: f64 = 0.05, null_difference: f64 = 0, power: ?f64 = null, n: ?f64 = null, power_seen: bool = false, n_seen: bool = false };
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
fn unsupportedOption(name: []const u8) bool {
    return listed(name, &.{ "ci", "cv", "groupmeans", "gmeans", "groupns", "gns", "groupstddevs", "gstddevs", "groupstds", "gstds", "groupweights", "gweights", "halfwidth", "lower", "meanratio", "nfractional", "nfrac", "npergroup", "nperg", "nullratio", "nullr", "outputorder", "probtype", "probwidth", "upper" });
}
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Scenario) diag.Error!void {
    if (s.difference == null or s.sigma == null or !s.power_seen or !s.n_seen or (s.power == null) == (s.n == null)) return invalid(cx, 0, "MEANDIFF, STDDEV, POWER and NTOTAL are required; exactly one of POWER or NTOTAL must be missing");
    const d: means.Design = .{ .difference = s.difference.? - s.null_difference, .sigma = s.sigma.?, .alpha = s.alpha };
    if (!d.valid()) return invalid(cx, 0, "STDDEV must be positive and ALPHA must lie strictly between zero and one");
    var n: f64 = undefined;
    var power: f64 = undefined;
    if (s.n) |given| {
        if (given < 4 or @floor(given) != given) return invalid(cx, 0, "NTOTAL must be an integer of at least four");
        if (@mod(given, 2) != 0) return proc.failGap(cx.diags, 0, "PROC POWER: odd NTOTAL allocation adjustment is not implemented", .{});
        n = given;
        power = d.power(n);
    } else {
        if (s.power.? <= 0 or s.power.? >= 1) return invalid(cx, 0, "POWER must lie strictly between zero and one");
        const result = d.sampleSize(s.power.?);
        if (result.status != .converged) return proc.failGap(cx.diags, 0, "PROC POWER: sample-size inversion did not converge ({s})", .{@tagName(result.status)});
        n = means.executableN(result.x);
        power = d.power(n);
    }
    if (!std.math.isFinite(power)) return proc.failGap(cx.diags, 0, "PROC POWER: exact power is outside the implemented numerical domain", .{});
    try out.appendSlice(cx.arena, "The POWER Procedure\nTwo-Sample t Test for Mean Difference\n\nFixed Scenario Elements\n\nDistribution Normal\nMethod Exact\n");
    const fixed = try std.fmt.allocPrint(cx.arena, "Alpha {d}\nMean Difference {d}\nStandard Deviation {d}\n", .{ s.alpha, s.difference.?, s.sigma.? });
    try out.appendSlice(cx.arena, fixed);
    try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "{s} {d}\n", .{ if (s.n == null) "Nominal Power" else "Total Sample Size", if (s.n == null) s.power.? else n }));
    try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Number of Sides 2\nNull Difference {d}\nGroup 1 Weight 1\nGroup 2 Weight 1\n\n", .{s.null_difference}));
    if (s.n == null) try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed N Total\n\nActual N\nPower Total\n\n{d:.3} {d:.0}\n\n", .{ power, n })) else try out.appendSlice(cx.arena, try std.fmt.allocPrint(cx.arena, "Computed Power\n\nPower\n\n{d:.3}\n", .{power}));
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    var i: usize = 2;
    if (!at(t, i, .semicolon)) {
        if (kw(t, i, "plotonly")) return proc.failGap(cx.diags, 0, "PROC POWER: PLOTONLY is not implemented", .{});
        return invalid(cx, 0, "unknown procedure option");
    }
    i += 1;
    var analyses: usize = 0;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        if (kw(t, i, "run") or kw(t, i, "quit")) break;
        if (!kw(t, i, "twosamplemeans")) {
            if (listed(t[i].text, &.{ "coxreg", "custom", "logistic", "multreg", "onecorr", "onesamplefreq", "onesamplemeans", "onewayanova", "pairedfreq", "pairedmeans", "plot", "twosamplefreq", "twosamplesurvival", "twosamplewilcoxon" })) return proc.failGap(cx.diags, t[i].line, "PROC POWER: statement {s} is not implemented", .{t[i].text});
            return invalid(cx, t[i].line, "unknown analysis statement");
        }
        i += 1;
        var s: Scenario = .{};
        while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
            if (!at(t, i, .name)) return proc.failGap(cx.diags, 0, "PROC POWER: scenario lists are not implemented", .{});
            const name = t[i].text;
            const line = t[i].line;
            i += 1;
            if (eq(name, "test") and !at(t, i, .eq)) continue;
            if (!at(t, i, .eq)) {
                if (unsupportedOption(name)) return proc.failGap(cx.diags, line, "PROC POWER: option {s} is not implemented", .{name});
                return invalid(cx, line, "expected option=value");
            }
            i += 1;
            if (eq(name, "test") or eq(name, "dist")) {
                if (!kw(t, i, if (eq(name, "test")) "diff" else "normal")) {
                    if (i < t.len and listed(t[i].text, if (eq(name, "test")) &.{ "diff_satt", "equiv_diff", "equiv_ratio", "ratio" } else &.{"lognormal"})) return proc.failGap(cx.diags, line, "PROC POWER: only TEST=DIFF DIST=NORMAL is implemented", .{});
                    return invalid(cx, line, "unknown TEST or DIST value");
                }
                i += 1;
                continue;
            }
            if (!eq(name, "meandiff") and !eq(name, "stddev") and !eq(name, "std") and !eq(name, "alpha") and !eq(name, "power") and !eq(name, "ntotal") and !eq(name, "sides") and !eq(name, "nulldiff") and !eq(name, "nulld")) {
                if (unsupportedOption(name)) return proc.failGap(cx.diags, line, "PROC POWER: option {s} is not implemented", .{name});
                return invalid(cx, line, "unknown TWOSAMPLEMEANS option");
            }
            if (eq(name, "sides") and (kw(t, i, "u") or kw(t, i, "l"))) return proc.failGap(cx.diags, line, "PROC POWER: only SIDES=2 is implemented", .{});
            const v = try number(cx, t, &i);
            if (eq(name, "meandiff")) s.difference = v else if (eq(name, "stddev") or eq(name, "std")) s.sigma = v else if (eq(name, "alpha")) s.alpha = v orelse return proc.failGap(cx.diags, line, "PROC POWER: solving for ALPHA is not implemented", .{}) else if (eq(name, "power")) {
                s.power = v;
                s.power_seen = true;
            } else if (eq(name, "ntotal")) {
                s.n = v;
                s.n_seen = true;
            } else if (eq(name, "sides")) {
                if (v == null or (v.? != 1 and v.? != 2)) return invalid(cx, line, "invalid SIDES value");
                if (v.? == 1) return proc.failGap(cx.diags, line, "PROC POWER: only SIDES=2 is implemented", .{});
            } else s.null_difference = v orelse return invalid(cx, line, "NULLDIFF must be nonmissing");
        }
        if (!at(t, i, .semicolon)) return invalid(cx, 0, "missing statement semicolon");
        i += 1;
        try render(cx, out, s);
        analyses += 1;
    }
    if (analyses == 0) return invalid(cx, 0, "at least one analysis statement is required");
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
