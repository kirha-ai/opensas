//! TTEST declarations and input selection. S154 physical pp.10604-10619.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const Dataset = @import("../dataset.zig").Dataset;
const lists = @import("variable_lists.zig");
const groups = @import("by_groups.zig");
const selection = @import("data_selection.zig");
const eq = std.ascii.eqlIgnoreCase;

pub const Sides = enum { two, lower, upper };
pub const Distribution = enum { normal, lognormal };
pub const Order = enum { data, formatted, freq, internal, mixed };
pub const Options = struct {
    alpha: f64 = 0.05,
    h0: f64 = 0,
    h0_explicit: bool = false,
    distribution: Distribution = .normal,
    sides: Sides = .two,
    sides_explicit: bool = false,
    tost: ?@import("ttest_tost.zig").Bounds = null,
    order: Order = .mixed,
    ci: bool = true,
    plots_none: bool = false,
    plots: @import("ttest_plots.zig").Options = .{},
    cochran: bool = false,
};
pub const Pair = struct { left: usize, right: usize };
pub const Spec = struct {
    bootstrap: ?@import("ttest_bootstrap.zig").Options = null,
    crossover: ?[2]usize = null,
    ignore_period: bool = false,
    paired: bool = false,
    pairs: []const Pair = &.{},
    input: proc.ProcInput,
    roles: selection.Roles,
    class: ?usize,
    summary: ?usize,
    by_desc: []const bool,
    notsorted: bool,
    options: Options,
    line: usize,
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return i < t.len and proc.tkKw(t[i], name);
}
fn invalid(cx: proc.ProcCtx, t: lex.Token) diag.Error {
    return cx.diags.fail(error.ParseError, t.line, "PROC TTEST: unexpected token {s}", .{t.text});
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t[@min(i.*, t.len - 1)]);
    const value = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t[i.*]);
    i.* += 1;
    if (!std.math.isFinite(value)) return invalid(cx, t[i.* - 1]);
    return sign * value;
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, token: lex.Token) diag.Error!usize {
    return ds.indexOf(token.text) orelse cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{token.text});
}
fn contains(cols: []const usize, ci: usize) bool {
    return std.mem.indexOfScalar(usize, cols, ci) != null;
}

// Parentheses delimit a variable list. Outside parentheses, a single list
// expression (including numbered ranges) forms each side. A bare colon between
// sides is the pairing operator, not the variable-list prefix operator.
fn pairSide(cx: proc.ProcCtx, ds: *const Dataset, tokens: []const lex.Token, pos: *usize, left: bool) diag.Error![]const usize {
    if (pos.* >= tokens.len) return cx.diags.fail(error.ParseError, if (tokens.len > 0) tokens[tokens.len - 1].line else 0, "PAIRED requires variables on both sides", .{});
    var result: std.ArrayList(usize) = .empty;
    const parenthesized = at(tokens, pos.*, .lparen);
    var end = tokens.len;
    if (parenthesized) {
        pos.* += 1;
        end = pos.*;
        while (end < tokens.len and tokens[end].tag != .rparen) : (end += 1) {}
        if (end == tokens.len) return cx.diags.fail(error.ParseError, tokens[pos.* - 1].line, "PAIRED variable list has no closing parenthesis", .{});
    } else if (left) {
        end = pos.*;
        while (end < tokens.len and tokens[end].tag != .star and tokens[end].tag != .colon) : (end += 1) {}
    }
    while (pos.* < end) {
        const line = tokens[pos.*].line;
        for (try lists.next(cx.arena, ds, tokens[0..end], pos, cx.diags)) |name| {
            const ci = (try selection.Roles.numeric(ds, name, "PAIRED", cx.diags, line)).?;
            try result.append(cx.arena, ci);
        }
        if (!parenthesized) break;
    }
    if (result.items.len == 0) return cx.diags.fail(error.ParseError, tokens[@min(pos.*, tokens.len - 1)].line, "PAIRED variable list is empty", .{});
    if (parenthesized) pos.* = end + 1;
    return result.items;
}

fn readPairs(cx: proc.ProcCtx, ds: *const Dataset, tokens: []const lex.Token, out: *std.ArrayList(Pair)) diag.Error!void {
    if (tokens.len == 0) return cx.diags.fail(error.ParseError, 0, "PAIRED requires a pair-list", .{});
    var i: usize = 0;
    while (i < tokens.len) {
        const lhs = try pairSide(cx, ds, tokens, &i, true);
        if (!at(tokens, i, .star) and !at(tokens, i, .colon)) return cx.diags.fail(error.ParseError, tokens[@min(i, tokens.len - 1)].line, "PAIRED requires * or : between variable lists", .{});
        const positional = at(tokens, i, .colon);
        const line = tokens[i].line;
        i += 1;
        const rhs = try pairSide(cx, ds, tokens, &i, false);
        if (positional and lhs.len != rhs.len) return cx.diags.fail(error.ParseError, line, "PAIRED colon lists must contain the same number of variables", .{});
        for (lhs, 0..) |l, j| {
            if (positional) {
                if (l != rhs[j]) try out.append(cx.arena, .{ .left = l, .right = rhs[j] });
            } else for (rhs) |r| {
                if (l != r) try out.append(cx.arena, .{ .left = l, .right = r });
            }
        }
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    if (t.len < 3) return cx.diags.fail(error.ParseError, 0, "Incomplete PROC TTEST statement", .{});
    var options: Options = .{};
    var tost_raw: ?@import("ttest_tost.zig").RawBounds = null;
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and t[i].tag != .semicolon and t[i].tag != .eof) {
        const token = t[i];
        if (kw(t, i, "plots")) {
            options.plots = try @import("ttest_plots.zig").parse(cx.arena, cx.diags, t, &i);
            options.plots_none = options.plots.none;
            continue;
        }
        if (kw(t, i, "tost")) {
            tost_raw = try @import("ttest_tost.zig").parseOption(t, &i, cx.diags);
            continue;
        }
        if (kw(t, i, "cochran")) {
            options.cochran = true;
            i += 1;
            continue;
        }
        if (kw(t, i, "byvar")) {
            i += 1;
            continue;
        }
        if (kw(t, i, "nobyvar"))
            return proc.failGap(cx.diags, token.line, "PROC TTEST: {s} is not implemented", .{token.text});
        if (!at(t, i + 1, .eq)) return invalid(cx, token);
        i += 2;
        if (eq(token.text, "data")) {
            if (!at(t, i, .name)) return invalid(cx, t[@min(i, t.len - 1)]);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t[i]);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
            }
            if (at(t, i, .lparen)) {
                const end = proc.skipParen(t, i);
                if (end <= i or !at(t, end - 1, .rparen)) return invalid(cx, t[i]);
                i = end;
            }
        } else if (eq(token.text, "alpha") or eq(token.text, "h0")) {
            const value = try number(cx, t, &i);
            if (eq(token.text, "alpha")) {
                if (!(value > 0 and value < 1)) return cx.diags.fail(error.ParseError, token.line, "PROC TTEST: ALPHA must be between 0 and 1", .{});
                options.alpha = value;
            } else {
                options.h0 = value;
                options.h0_explicit = true;
            }
        } else {
            if (i >= t.len) return invalid(cx, token);
            const value = t[i];
            i += 1;
            if (eq(token.text, "sides") or eq(token.text, "sided") or eq(token.text, "side")) {
                options.sides_explicit = true;
                options.sides = if (eq(value.text, "2")) .two else if (eq(value.text, "l")) .lower else if (eq(value.text, "u")) .upper else return invalid(cx, value);
            } else if (eq(token.text, "order")) {
                options.order = if (eq(value.text, "data")) .data else if (eq(value.text, "formatted")) .formatted else if (eq(value.text, "freq")) .freq else if (eq(value.text, "internal")) .internal else if (eq(value.text, "mixed")) .mixed else return invalid(cx, value);
            } else if (eq(token.text, "dist")) {
                options.distribution = if (eq(value.text, "lognormal")) .lognormal else if (eq(value.text, "normal")) .normal else return invalid(cx, value);
            } else if (eq(token.text, "test")) {
                if (eq(value.text, "ratio")) return proc.failGap(cx.diags, token.line, "PROC TTEST: TEST=RATIO is not implemented", .{});
                if (!eq(value.text, "diff")) return invalid(cx, value);
            } else if (eq(token.text, "ci") or eq(token.text, "cl")) {
                if (eq(value.text, "umpu")) return proc.failGap(cx.diags, token.line, "PROC TTEST: CI=UMPU is not implemented", .{});
                options.ci = if (eq(value.text, "equal")) true else if (eq(value.text, "none")) false else return invalid(cx, value);
            } else return invalid(cx, token);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t[@min(i, t.len - 1)]);
    // Resolve the default after all header options: H0 and DIST are order-independent.
    if (!options.h0_explicit) options.h0 = if (options.distribution == .lognormal) 1 else 0;
    if (options.distribution == .lognormal and options.h0 <= 0)
        return cx.diags.fail(error.ParseError, t[0].line, "H0 must be greater than zero for a test of a mean ratio or when lognormal data is assumed.", .{});
    if (tost_raw) |bounds| {
        options.tost = try @import("ttest_tost.zig").resolveBounds(bounds, options.h0, if (options.distribution == .lognormal) .log_ratio else .difference, cx.diags);
        if (options.sides_explicit) try cx.diags.report(.warning, bounds.line, "The SIDES option is ignored when using the TOST option.", .{});
        options.sides = .two;
        if (options.cochran) return proc.failGap(cx.diags, bounds.line, "PROC TTEST: Cochran TOST inference is not implemented", .{});
    }
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, t[0].line, "File {s} does not exist.", .{name orelse "_last_"});
    var input = try proc.procInputObs(cx.arena, raw, t, cx.diags);
    var ds = input.ds;
    var vars: std.ArrayList(usize) = .empty;
    var var_seen = false;
    var bootstrap: ?@import("ttest_bootstrap.zig").Options = null;
    var var_occurrences: std.ArrayList(usize) = .empty;
    var crossover: ?[2]usize = null;
    var ignore_period = false;
    var paired = false;
    var pairs: std.ArrayList(Pair) = .empty;
    var by: groups.Statements = .{};
    var freq: lists.NumericRole = .{};
    var weight: lists.NumericRole = .{};
    var class: ?usize = null;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    i += 1;
    while (i < t.len and t[i].tag != .eof) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        const token = t[i];
        var end = i + 1;
        while (end < t.len and t[end].tag != .semicolon and t[end].tag != .eof) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, token);
        if (kw(t, i, "var")) {
            var_seen = true;
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) {
                const start = j;
                for (try lists.next(cx.arena, ds, t[0..end], &j, cx.diags)) |n| {
                    const ci = (try selection.Roles.numeric(ds, n, "VAR", cx.diags, t[start].line)).?;
                    try var_occurrences.append(cx.arena, ci);
                    if (!contains(vars.items, ci)) try vars.append(cx.arena, ci);
                }
            }
            if (j < end) {
                j += 1; // VAR slash options.
                while (j < end) {
                    if (kw(t, j, "ignoreperiod")) {
                        ignore_period = true;
                        j += 1;
                    } else if (kw(t, j, "crossover")) {
                        const line = t[j].line;
                        if (!at(t, j + 1, .eq) or !at(t, j + 2, .lparen)) return invalid(cx, t[j]);
                        j += 3;
                        if (!at(t, j, .name)) return cx.diags.fail(error.ParseError, line, "CROSSOVER requires two treatment variables", .{});
                        const first = try column(cx, ds, t[j]);
                        j += 1;
                        if (at(t, j, .comma)) j += 1;
                        if (!at(t, j, .name)) return cx.diags.fail(error.ParseError, line, "CROSSOVER requires two treatment variables", .{});
                        const second = try column(cx, ds, t[j]);
                        j += 1;
                        if (!at(t, j, .rparen)) return cx.diags.fail(error.ParseError, line, "CROSSOVER requires exactly two treatment variables in parentheses", .{});
                        j += 1;
                        crossover = .{ first, second };
                    } else return invalid(cx, t[j]);
                }
            }
        } else if (kw(t, i, "by")) {
            try by.read(cx.arena, t, &i);
        } else if (kw(t, i, "class")) {
            const variable = try lists.roleVariable(t[0..end], i + 1, false, cx.diags);
            class = try column(cx, ds, variable);
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            const role = if (kw(t, i, "freq")) &freq else &weight;
            try role.add(cx.arena, ds, try lists.roleVariable(t[0..end], i + 1, false, cx.diags), cx.diags);
        } else if (kw(t, i, "format")) {
            try proc.parseProcFormat(cx.arena, t, &i, &formats);
        } else if (kw(t, i, "paired")) {
            if (paired) return cx.diags.fail(error.ParseError, token.line, "PAIRED statement cannot be used more than once", .{});
            paired = true;
            if (i + 1 == end) return cx.diags.fail(error.ParseError, token.line, "PAIRED requires a pair-list", .{});
            try readPairs(cx, ds, t[i + 1 .. end], &pairs);
        } else if (kw(t, i, "bootstrap")) {
            if (bootstrap != null) return cx.diags.fail(error.ParseError, token.line, "BOOTSTRAP statement cannot be used more than once", .{});
            bootstrap = try @import("ttest_bootstrap.zig").parse(cx.arena, t[i..end], cx.diags);
        } else if (!kw(t, i, "where") and !kw(t, i, "run") and !kw(t, i, "quit") and !(token.tag == .name and parser.isMidStepSkippable(token.text))) return invalid(cx, token);
        i = end + 1;
    }
    if (crossover != null) {
        if (paired or class != null) return cx.diags.fail(error.ParseError, t[0].line, "CROSSOVER cannot be used with CLASS or PAIRED", .{});
        vars = var_occurrences; // Response pairs retain their declared order, including repeats.
        if (vars.items.len == 0 or vars.items.len % 2 != 0) return cx.diags.fail(error.ParseError, t[0].line, "CROSSOVER requires an even number of response variables", .{});
    }
    if (ignore_period and crossover == null) return cx.diags.fail(error.ParseError, t[0].line, "IGNOREPERIOD requires CROSSOVER", .{});
    if (paired and (var_seen or class != null)) return cx.diags.fail(error.ParseError, t[0].line, "PAIRED cannot be used with CLASS or VAR", .{});
    if (paired and options.distribution == .lognormal) return proc.failGap(cx.diags, t[0].line, "PROC TTEST: lognormal paired ratios are not implemented", .{});
    for (formats.items) |f| if (ds.indexOf(f.name) == null) return cx.diags.fail(error.ParseError, t[0].line, "Variable {s} not found.", .{f.name});
    ds = try groups.withFormats(cx.arena, ds, formats.items);
    input.ds = ds;
    const by_spec = try by.resolve(cx.arena, ds, cx.diags);
    var bcols: std.ArrayList(usize) = .empty;
    for (by_spec.names) |n| try bcols.append(cx.arena, ds.indexOf(n).?);
    var summary: ?usize = null;
    for ([_][]const u8{ "_TYPE_", "_STAT_" }) |n| {
        if (ds.indexOf(n)) |ci| if (ds.columns.items[ci].type == .char) {
            summary = ci;
            break;
        };
    }
    if (bootstrap) |boot| {
        if (options.distribution != .normal or options.tost != null or crossover != null or weight.first() != null or summary != null)
            return cx.diags.fail(error.ParseError, boot.line, "BOOTSTRAP is unavailable with lognormal data, TOST, CROSSOVER, WEIGHT or summary input", .{});
        if (boot.bootdata != null and (paired or bcols.items.len > 0))
            return proc.failGap(cx.diags, boot.line, "BOOTDATA for paired or BY analyses is not implemented", .{});
    }
    if (summary != null and crossover != null) return cx.diags.fail(error.ParseError, t[0].line, "CROSSOVER requires observation values, not summary statistics", .{});
    if (summary != null and paired) return cx.diags.fail(error.ParseError, t[0].line, "PAIRED requires observation values, not summary statistics", .{});
    if (summary != null and options.distribution == .lognormal)
        return cx.diags.fail(error.ParseError, t[0].line, "PROC TTEST: DIST=LOGNORMAL requires observation values, not summary statistics", .{});
    if (summary != null and (freq.first() != null or weight.first() != null))
        return cx.diags.fail(error.ParseError, t[0].line, "PROC TTEST: FREQ and WEIGHT cannot be used with summary statistics", .{});
    if (!var_seen and !paired) for (ds.columns.items, 0..) |c, ci| {
        if (c.type == .num and class != ci and !contains(bcols.items, ci) and !freq.contains(ci) and !weight.contains(ci)) try vars.append(cx.arena, ci);
    };
    if (!paired and vars.items.len == 0) return cx.diags.fail(error.ParseError, t[0].line, "PROC TTEST: variable list is empty", .{});
    if (paired) for (pairs.items) |pair| {
        if (!contains(vars.items, pair.left)) try vars.append(cx.arena, pair.left);
        if (!contains(vars.items, pair.right)) try vars.append(cx.arena, pair.right);
    };
    return .{ .bootstrap = bootstrap, .crossover = crossover, .ignore_period = ignore_period, .paired = paired, .pairs = pairs.items, .input = input, .roles = .{ .analysis = vars.items, .by = bcols.items, .frequency = freq.first(), .weight = weight.first() }, .class = class, .summary = summary, .by_desc = by_spec.desc, .notsorted = by_spec.notsorted, .options = options, .line = t[0].line };
}

const TestInput = struct {
    fn dataset(a: std.mem.Allocator) !*Dataset {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "sample");
        for ([_][]const u8{ "x", "y", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
        _ = try ds.addColumn("g", .char);
        _ = try ds.addColumn("b", .num);
        try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 2.9 }, .{ .num = 0.5 }, .{ .str = "A" }, .{ .num = 1 } });
        try ds.appendRow(&.{ .{ .num = 3 }, @import("../value.zig").Value.missing, .{ .num = 1 }, .{ .num = 2 }, .{ .str = "B" }, .{ .num = 2 } });
        return ds;
    }
};

test "STAT-TTEST-001 defaults, roles, WHERE and per-variable selection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try TestInput.dataset(a);
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc ttest; by b; class g; freq f; weight w; run;", &d));
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, s.roles.analysis);
    try std.testing.expectEqual(@as(?usize, 4), s.class);
    try std.testing.expectEqual(@as(f64, 0.05), s.options.alpha);
    try std.testing.expectEqual(@as(f64, 0), s.options.h0);
    try std.testing.expectEqual(Sides.two, s.options.sides);
    const view = try selection.View.init(a, s.input, s.roles);
    const xs = try view.select(a, .{ .missing_columns = &.{0}, .frequency = .truncate_positive, .weight = .positive_only });
    const ys = try view.select(a, .{ .missing_columns = &.{1}, .frequency = .truncate_positive, .weight = .positive_only });
    try std.testing.expectEqual(@as(usize, 2), xs.observations.len);
    try std.testing.expectEqual(@as(usize, 1), ys.observations.len);
    try std.testing.expectEqual(@as(f64, 2), xs.observations[0].frequency.num);
    try std.testing.expectEqual(@as(f64, 0.5), xs.observations[0].weight.num);
    const filtered = try parse(cx, try lex.tokenize(a, "proc ttest data=sample alpha=.1 h0=-2 side=u order=data; by b; by g notsorted; var x y; where x>1; run;", &d));
    try std.testing.expectEqual(@as(f64, -2), filtered.options.h0);
    try std.testing.expectEqual(@as(f64, 0.1), filtered.options.alpha);
    try std.testing.expectEqual(Sides.upper, filtered.options.sides);
    try std.testing.expectEqualSlices(usize, &.{4}, filtered.roles.by);
    try std.testing.expect(filtered.notsorted);
    try std.testing.expectEqual(@as(usize, 1), filtered.input.ds.rows.items.len);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-001 invalid declarations have captured locations; valid unsupported options are gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    for ([_][]const u8{
        "proc ttest alpha=0; run;",        "proc ttest sides=both; run;",
        "proc ttest order=wrong; run;",    "proc ttest plots=wrong; run;",
        "proc ttest; var g; run;",         "proc ttest; freq g; run;",
        "proc ttest; weight absent; run;", "proc ttest; class g b; run;",
        "proc ttest; var; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(d.list.items[0].line > 0);
    }
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest ci=umpu; var x; run;", &d)));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(diag.gapHit());
}

test "STAT-TTEST-003 DIST sets H0 default only when omitted; option order does not change explicit H0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const defaults = try parse(cx, try lex.tokenize(a, "proc ttest dist=lognormal; var x; run;", &d));
    try std.testing.expectEqual(@as(f64, 1), defaults.options.h0);
    try std.testing.expect(!defaults.options.h0_explicit);
    for ([_][]const u8{ "h0=2 dist=lognormal", "dist=lognormal h0=2" }) |header| {
        const source = try std.fmt.allocPrint(a, "proc ttest {s}; var x; run;", .{header});
        const s = try parse(cx, try lex.tokenize(a, source, &d));
        try std.testing.expectEqual(@as(f64, 2), s.options.h0);
        try std.testing.expect(s.options.h0_explicit);
    }
    const normal = try parse(cx, try lex.tokenize(a, "proc ttest dist=normal; var x; run;", &d));
    try std.testing.expectEqual(@as(f64, 0), normal.options.h0);
    try std.testing.expectEqual(Distribution.normal, normal.options.distribution);
    for ([_][]const u8{ "proc ttest dist=lognormal h0=0; var x; run;", "proc ttest h0=-1 dist=lognormal; var x; run;", "proc ttest dist=wrong; var x; run;" }) |source| {
        var bad = diag.Diagnostics.init(a);
        const badcx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &bad };
        try std.testing.expectError(error.ParseError, parse(badcx, try lex.tokenize(a, source, &bad)));
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, bad.hasErrors()));
        try std.testing.expect(bad.list.items[0].line > 0);
    }
    var summary = Dataset.init(a, "summary");
    _ = try summary.addColumn("_STAT_", .char);
    _ = try summary.addColumn("x", .num);
    try lib.put("summary", &summary);
    var bad = diag.Diagnostics.init(a);
    const badcx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &bad };
    try std.testing.expectError(error.ParseError, parse(badcx, try lex.tokenize(a, "proc ttest data=summary dist=lognormal; var x; run;", &bad)));
    try std.testing.expect(std.mem.indexOf(u8, try bad.render(), "requires observation values") != null);
}

test "STAT-TTEST-006 documented pair-lists retain direction, cross order, positional matching and self omission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "a1", "a2", "b1", "b2" }) |name| _ = try ds.addColumn(name, .num);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const Case = struct { statement: []const u8, expected: []const Pair };
    for ([_]Case{
        .{ .statement = "a1*b1 a2*b2", .expected = &.{ .{ .left = 0, .right = 2 }, .{ .left = 1, .right = 3 } } },
        .{ .statement = "(a1 a2)*(b1 b2)", .expected = &.{ .{ .left = 0, .right = 2 }, .{ .left = 0, .right = 3 }, .{ .left = 1, .right = 2 }, .{ .left = 1, .right = 3 } } },
        .{ .statement = "(a1 a2)*(b1 a2)", .expected = &.{ .{ .left = 0, .right = 2 }, .{ .left = 0, .right = 1 }, .{ .left = 1, .right = 2 } } },
        .{ .statement = "(a1-a2):(b1-b2)", .expected = &.{ .{ .left = 0, .right = 2 }, .{ .left = 1, .right = 3 } } },
        .{ .statement = "(b:):(a:)", .expected = &.{ .{ .left = 2, .right = 0 }, .{ .left = 3, .right = 1 } } },
        .{ .statement = "a1:a2", .expected = &.{.{ .left = 0, .right = 1 }} },
        .{ .statement = "a1*a1", .expected = &.{} },
    }) |case| {
        const source = try std.fmt.allocPrint(a, "proc ttest; paired {s}; run;", .{case.statement});
        const spec = try parse(cx, try lex.tokenize(a, source, &d));
        try std.testing.expect(spec.paired);
        try std.testing.expectEqual(case.expected.len, spec.pairs.len);
        for (case.expected, spec.pairs) |want, actual| try std.testing.expectEqual(want, actual);
    }
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-006 malformed and conflicting pair declarations fail with captured locations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    for ([_][]const u8{
        "paired x*y; var x;", "var x; paired x*y;", "class g; paired x*y;",
        "paired (x y):f;",    "paired (x y)*();",   "paired x*;",
        "paired x y;",        "paired (x y*f;",     "paired g*x;",
        "paired missing*x;",  "paired;",            "paired x*y; paired y*x;",
    }) |body| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const source = try std.fmt.allocPrint(a, "proc ttest;\n{s} run;", .{body});
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(d.list.items[0].line > 0);
    }
    var summary = Dataset.init(a, "summary");
    _ = try summary.addColumn("_STAT_", .char);
    _ = try summary.addColumn("x", .num);
    _ = try summary.addColumn("y", .num);
    try lib.put("summary", &summary);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest data=summary; paired x*y; run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "requires observation values") != null);
}

test "STAT-TTEST-009 resolves bounds after H0 and warns for explicit ignored SIDES" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    for ([_][]const u8{ "tost(20) h0=1 sides=2", "h0=1 tost(20) sides=u" }) |header| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const source = try std.fmt.allocPrint(a, "proc ttest {s}; var x; run;", .{header});
        const s = try parse(cx, try lex.tokenize(a, source, &d));
        try std.testing.expectEqual(@as(f64, -18), s.options.tost.?.lower);
        try std.testing.expectEqual(@as(f64, 20), s.options.tost.?.upper);
        try std.testing.expectEqual(Sides.two, s.options.sides);
        try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
        try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
        try std.testing.expectEqualStrings("The SIDES option is ignored when using the TOST option.", d.list.items[0].message);
    }
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const ratio = try parse(cx, try lex.tokenize(a, "proc ttest tost(1.5) h0=1.2 dist=lognormal; var x; run;", &d));
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), ratio.options.tost.?.lower, 1e-14);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest tost(2,1); var x; run;", &d)));
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest cochran tost(-1,1); var x; run;", &d)));
    try std.testing.expect(diag.gapHit());
}

test "CROSSOVER parser binds treatment columns and preserves ordered response pairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc ttest; var x y x w / crossover=(g,b); run;", &d));
    try std.testing.expectEqual(@as(?[2]usize, .{ 4, 5 }), s.crossover);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 0, 3 }, s.roles.analysis);
    try std.testing.expect(!s.ignore_period);
    const ignored = try parse(cx, try lex.tokenize(a, "proc ttest; var x y / ignoreperiod crossover=(g b); run;", &d));
    try std.testing.expect(ignored.ignore_period);
    try std.testing.expectEqualStrings("", try d.render());
}

test "CROSSOVER parser rejects malformed dimensions conflicts and summary input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    for ([_][]const u8{
        "var x / crossover=(g b);",            "var x y / crossover=(g);",               "var x y / crossover=(g b x);",
        "var x y / crossover=(g absent);",     "var x y / crossover=g b;",               "var x y / ignoreperiod;",
        "class g; var x y / crossover=(g b);", "paired x*y; var x y / crossover=(g b);",
    }) |body| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const source = try std.fmt.allocPrint(a, "proc ttest;\n{s} run;", .{body});
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(d.list.items[0].line > 0);
    }
    var ds = Dataset.init(a, "summary");
    _ = try ds.addColumn("_STAT_", .char);
    for ([_][]const u8{ "x", "y", "a", "b" }) |name| _ = try ds.addColumn(name, .num);
    try lib.put("summary", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest data=summary; var x y / crossover=(a b); run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "requires observation values") != null);
}

test "BOOTSTRAP parser defaults, explicit options and documented invalid combinations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try TestInput.dataset(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const default = try parse(cx, try lex.tokenize(a, "proc ttest; var x; bootstrap; run;", &d));
    try std.testing.expectEqual(@as(usize, 10000), default.bootstrap.?.samples);
    try std.testing.expectEqual(@import("ttest_bootstrap.zig").Method.bc, default.bootstrap.?.method);
    const spec = try parse(cx, try lex.tokenize(a, "proc ttest; class g; var x; bootstrap / nsamples=199 seed=314159 bootci=percentile bootdata=work.draws; run;", &d));
    try std.testing.expectEqual(@as(usize, 199), spec.bootstrap.?.samples);
    try std.testing.expectEqual(@as(?u32, 314159), spec.bootstrap.?.seed);
    try std.testing.expectEqualStrings("work.draws", spec.bootstrap.?.bootdata.?);
    for ([_][]const u8{
        "proc ttest; var x; bootstrap / nsamples=1; run;",
        "proc ttest; var x; bootstrap / nsamples=2.5; run;",
        "proc ttest; var x; bootstrap / bootci=wrong; run;",
        "proc ttest; var x; bootstrap; bootstrap; run;",
        "proc ttest; var x; weight w; bootstrap; run;",
        "proc ttest dist=lognormal; var x; bootstrap; run;",
        "proc ttest tost(-1,1); var x; bootstrap; run;",
    }) |source| {
        var bad = diag.Diagnostics.init(a);
        const badcx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &bad };
        try std.testing.expectError(error.ParseError, parse(badcx, try lex.tokenize(a, source, &bad)));
        try std.testing.expect(bad.hasErrors());
    }
}
