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
pub const Order = enum { data, formatted, freq, internal, mixed };
pub const Options = struct {
    alpha: f64 = 0.05,
    h0: f64 = 0,
    sides: Sides = .two,
    order: Order = .mixed,
    ci: bool = true,
    plots_none: bool = false,
};
pub const Spec = struct {
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

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    if (t.len < 3) return cx.diags.fail(error.ParseError, 0, "Incomplete PROC TTEST statement", .{});
    var options: Options = .{};
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and t[i].tag != .semicolon and t[i].tag != .eof) {
        const token = t[i];
        if (kw(t, i, "byvar")) {
            i += 1;
            continue;
        }
        if (kw(t, i, "nobyvar") or kw(t, i, "cochran") or kw(t, i, "tost"))
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
            } else options.h0 = value;
        } else {
            if (i >= t.len) return invalid(cx, token);
            const value = t[i];
            i += 1;
            if (eq(token.text, "sides") or eq(token.text, "sided") or eq(token.text, "side")) {
                options.sides = if (eq(value.text, "2")) .two else if (eq(value.text, "l")) .lower else if (eq(value.text, "u")) .upper else return invalid(cx, value);
            } else if (eq(token.text, "order")) {
                options.order = if (eq(value.text, "data")) .data else if (eq(value.text, "formatted")) .formatted else if (eq(value.text, "freq")) .freq else if (eq(value.text, "internal")) .internal else if (eq(value.text, "mixed")) .mixed else return invalid(cx, value);
            } else if (eq(token.text, "dist")) {
                if (eq(value.text, "lognormal")) return proc.failGap(cx.diags, token.line, "PROC TTEST: DIST=LOGNORMAL is not implemented", .{});
                if (!eq(value.text, "normal")) return invalid(cx, value);
            } else if (eq(token.text, "test")) {
                if (eq(value.text, "ratio")) return proc.failGap(cx.diags, token.line, "PROC TTEST: TEST=RATIO is not implemented", .{});
                if (!eq(value.text, "diff")) return invalid(cx, value);
            } else if (eq(token.text, "ci") or eq(token.text, "cl")) {
                if (eq(value.text, "umpu")) return proc.failGap(cx.diags, token.line, "PROC TTEST: CI=UMPU is not implemented", .{});
                options.ci = if (eq(value.text, "equal")) true else if (eq(value.text, "none")) false else return invalid(cx, value);
            } else if (eq(token.text, "plots")) {
                if (!eq(value.text, "none")) return proc.failGap(cx.diags, token.line, "PROC TTEST: plots are not implemented", .{});
                options.plots_none = true;
            } else return invalid(cx, token);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t[@min(i, t.len - 1)]);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, t[0].line, "File {s} does not exist.", .{name orelse "_last_"});
    var input = try proc.procInputObs(cx.arena, raw, t, cx.diags);
    var ds = input.ds;
    var vars: std.ArrayList(usize) = .empty;
    var var_seen = false;
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
            while (j < end) {
                if (at(t, j, .slash)) return proc.failGap(cx.diags, t[j].line, "PROC TTEST: VAR crossover options are not implemented", .{});
                const start = j;
                for (try lists.next(cx.arena, ds, t[0..end], &j, cx.diags)) |n| {
                    const ci = (try selection.Roles.numeric(ds, n, "VAR", cx.diags, t[start].line)).?;
                    if (!contains(vars.items, ci)) try vars.append(cx.arena, ci);
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
        } else if (kw(t, i, "paired") or kw(t, i, "bootstrap")) {
            return proc.failGap(cx.diags, token.line, "PROC TTEST: {s} is not implemented", .{token.text});
        } else if (!kw(t, i, "where") and !kw(t, i, "run") and !kw(t, i, "quit") and !(token.tag == .name and parser.isMidStepSkippable(token.text))) return invalid(cx, token);
        i = end + 1;
    }
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
    if (summary != null and (freq.first() != null or weight.first() != null))
        return cx.diags.fail(error.ParseError, t[0].line, "PROC TTEST: FREQ and WEIGHT cannot be used with summary statistics", .{});
    if (!var_seen) for (ds.columns.items, 0..) |c, ci| {
        if (c.type == .num and class != ci and !contains(bcols.items, ci) and !freq.contains(ci) and !weight.contains(ci)) try vars.append(cx.arena, ci);
    };
    if (vars.items.len == 0) return cx.diags.fail(error.ParseError, t[0].line, "PROC TTEST: variable list is empty", .{});
    return .{ .input = input, .roles = .{ .analysis = vars.items, .by = bcols.items, .frequency = freq.first(), .weight = weight.first() }, .class = class, .summary = summary, .by_desc = by_spec.desc, .notsorted = by_spec.notsorted, .options = options, .line = t[0].line };
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
        "proc ttest alpha=0; run;",     "proc ttest sides=both; run;",
        "proc ttest order=wrong; run;", "proc ttest; var g; run;",
        "proc ttest; freq g; run;",     "proc ttest; weight absent; run;",
        "proc ttest; class g b; run;",  "proc ttest; var; run;",
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
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc ttest dist=lognormal; var x; run;", &d)));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(diag.gapHit());
}
