//! NPAR1WAY input roles and listing, SAS/STAT 15.4 physical pp.7215-7236.
//! Numerical analyses live in npar1way_stats.zig. Unsupported requests are
//! diagnosed before any partial listing can be mistaken for a full analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fmt = @import("../format.zig");
const by = @import("by_groups.zig");
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const lists = @import("variable_lists.zig");
const stats = @import("npar1way_stats.zig");
const hl = @import("npar1way_hl.zig");
const fp = @import("npar1way_fp.zig");
const edf_plot = @import("npar1way_edf_plot.zig");
const stratified = @import("npar1way_strata.zig");
const plots = @import("npar1way_plots.zig");
const varinfo = @import("npar1way_varinfo.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Spec = struct {
    input: proc.ProcInput,
    class: usize,
    variables: []const usize,
    frequency: ?usize = null,
    by_cols: []const usize,
    by_desc: []const bool,
    notsorted: bool = false,
    missing: bool = false,
    noprint: bool = false,
    variable_info: bool = false,
    variable_ties: bool = false,
    plots_none: bool = false,
    plots_only: bool = false,
    plots_wilcoxon: bool = false,
    plots_fp: bool = false,
    plots_edf: bool = false,
    plot_stats: bool = true,
    wilcoxon_plot_stats: ?bool = null,
    fp_plot_stats: ?bool = null,
    edf_plot_stats: ?bool = null,
    options: stats.Options = .{},
    fp_test: bool = false,
    fp_reference: ?union(enum) { index: usize, label: []const u8 } = null,
    edf_one_sided: bool = false,
    hodges: bool = false,
    exact_hl: bool = false,
    alpha: f64 = 0.05,
    reference: ?union(enum) { index: usize, label: []const u8 } = null,
    by_number: ?usize = null,
    strata: []const usize = &.{},
    strata_kinds: []const stratified.Kind = &.{.wilcoxon},
    strata_options: stratified.Options = .{},
    stratified_selection: bool = false,
    descriptor_only: bool = false,
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC NPAR1WAY: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn member(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        i.* += 1;
        if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i.*].text });
        i.* += 1;
    }
    return name;
}
fn analysis(o: *stats.Options, name: []const u8) bool {
    if (eq(name, "wilcoxon")) o.wilcoxon = true else if (eq(name, "median")) o.median = true else if (eq(name, "vw") or eq(name, "normal")) o.vw = true else if (eq(name, "savage")) o.savage = true else if (eq(name, "ab")) o.ab = true else if (eq(name, "st")) o.st = true else if (eq(name, "klotz")) o.klotz = true else if (eq(name, "mood")) o.mood = true else if (eq(name, "conover")) o.conover = true else if (eq(name, "perm")) o.data = true else if (eq(name, "anova")) o.anova = true else if (eq(name, "edf") or eq(name, "ks")) o.edf = true else return false;
    return true;
}
fn documentedGap(name: []const u8) bool {
    for ([_][]const u8{ "ab", "conover", "d", "dscf", "fp", "hl", "klotz", "mood", "rmd", "scores", "perm", "st", "adjust", "align", "alpha", "tables", "varinfo" }) |v| if (eq(name, v)) return true;
    return false;
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .class = undefined, .variables = &.{}, .by_cols = &.{}, .by_desc = &.{}, .options = .{ .anova = false, .wilcoxon = false, .median = false, .vw = false, .savage = false, .edf = false } };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var chosen = false;
    var plot_stats_seen: ?bool = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "data") and at(t, i + 1, .eq)) {
            i += 2;
            const first = i;
            name = try member(cx, t, &i);
            if (i - first == 3) qualified = first;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (kw(t, i, "fp")) {
            s.fp_test = true;
            chosen = true;
            i += 1;
            if (at(t, i, .lparen)) {
                i += 1;
                if (!kw(t, i, "refclass") or !at(t, i + 1, .eq)) return invalid(cx, t, i);
                i += 2;
                if (at(t, i, .string)) s.fp_reference = .{ .label = t[i].text } else if (at(t, i, .number)) {
                    const ref = std.fmt.parseInt(usize, t[i].text, 10) catch return invalid(cx, t, i);
                    if (ref != 1 and ref != 2) return invalid(cx, t, i);
                    s.fp_reference = .{ .index = ref - 1 };
                } else return invalid(cx, t, i);
                i += 1;
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (kw(t, i, "d")) {
            s.edf_one_sided = true;
            s.options.edf = true;
            chosen = true;
            i += 1;
        } else if (kw(t, i, "hl")) {
            s.hodges = true;
            s.options.wilcoxon = true;
            chosen = true;
            i += 1;
            if (at(t, i, .lparen)) {
                i += 1;
                if (!kw(t, i, "refclass") or !at(t, i + 1, .eq)) return invalid(cx, t, i);
                i += 2;
                if (at(t, i, .string)) s.reference = .{ .label = t[i].text } else if (at(t, i, .number)) {
                    const ref = std.fmt.parseInt(usize, t[i].text, 10) catch return invalid(cx, t, i);
                    if (ref != 1 and ref != 2) return invalid(cx, t, i);
                    s.reference = .{ .index = ref - 1 };
                } else return invalid(cx, t, i);
                i += 1;
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (kw(t, i, "alpha") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            s.alpha = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(s.alpha > 0 and s.alpha < 1)) return invalid(cx, t, i + 2);
            i += 3;
        } else if (kw(t, i, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (kw(t, i, "varinfo")) {
            s.variable_info = true;
            i += 1;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "ties") or !at(t, i + 2, .rparen)) return invalid(cx, t, i);
                s.variable_ties = true;
                i += 3;
            }
        } else if (kw(t, i, "missing")) {
            s.missing = true;
            i += 1;
        } else if (at(t, i, .name) and analysis(&s.options, t[i].text)) {
            chosen = true;
            i += 1;
            if (at(t, i, .lparen)) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: per-analysis adjustment is not implemented", .{});
        } else if (kw(t, i, "scores") and at(t, i + 1, .eq)) {
            if (!kw(t, i + 2, "data")) return invalid(cx, t, i + 2);
            s.options.data = true;
            chosen = true;
            i += 3;
            if (at(t, i, .lparen)) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: SCORES=DATA adjustment is not implemented", .{});
        } else if (kw(t, i, "correct") and at(t, i + 1, .eq)) {
            if (!kw(t, i + 2, "no")) return invalid(cx, t, i + 2);
            s.options.continuity = false;
            i += 3;
        } else if (kw(t, i, "plots")) {
            i += 1;
            if (at(t, i, .lparen)) {
                i += 1;
                while (i < t.len and !at(t, i, .rparen)) : (i += 1) {
                    if (kw(t, i, "only")) s.plots_only = true else if (kw(t, i, "nostats") or kw(t, i, "stats")) {
                        const show = kw(t, i, "stats");
                        if (plot_stats_seen) |old| if (old != show) return invalid(cx, t, i);
                        plot_stats_seen = show;
                        s.plot_stats = show;
                    } else return invalid(cx, t, i);
                }
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
            if (!at(t, i, .eq)) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: default PLOTS requests are not implemented", .{});
            i += 1;
            const paren = at(t, i, .lparen);
            if (paren) i += 1;
            while (i < t.len) {
                if (kw(t, i, "none")) s.plots_none = true else if (kw(t, i, "wilcoxonboxplot") or kw(t, i, "wilcoxon")) s.plots_wilcoxon = true else if (kw(t, i, "fpboxplot") or kw(t, i, "fp")) s.plots_fp = true else if (kw(t, i, "edfplot") or kw(t, i, "edf")) s.plots_edf = true else return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: plot {s} is not implemented", .{t[i].text});
                const request = t[i].text;
                i += 1;
                if (at(t, i, .lparen)) {
                    if (eq(request, "none")) return invalid(cx, t, i);
                    i += 1;
                    var show: ?bool = null;
                    while (i < t.len and !at(t, i, .rparen)) : (i += 1) {
                        if (!kw(t, i, "stats") and !kw(t, i, "nostats")) return invalid(cx, t, i);
                        const value = kw(t, i, "stats");
                        if (show) |old| if (old != value) return invalid(cx, t, i);
                        show = value;
                    }
                    if (show == null or !at(t, i, .rparen)) return invalid(cx, t, i);
                    if (eq(request, "fp") or eq(request, "fpboxplot")) s.fp_plot_stats = show else if (eq(request, "edf") or eq(request, "edfplot")) s.edf_plot_stats = show else s.wilcoxon_plot_stats = show;
                    i += 1;
                }
                if (!paren) break;
                if (at(t, i, .rparen)) {
                    i += 1;
                    break;
                }
            }
        } else if (at(t, i, .name) and documentedGap(t[i].text)) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: option {s} is not implemented", .{t[i].text}) else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var class_col: ?usize = null;
    var var_names: std.ArrayList([]const u8) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var bys: by.Statements = .{};
    var exact_seen = false;
    var strata_weights_seen = false;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "class") or kw(t, i, "freq")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            const col = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i + 1].line, "Variable {s} not found.", .{t[i + 1].text});
            if (kw(t, i, "class")) {
                if (class_col != null) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: duplicate CLASS statement policy is not verified", .{});
                class_col = col;
            } else {
                if (s.frequency != null) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: duplicate FREQ statement policy is not verified", .{});
                if (ds.columns.items[col].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC NPAR1WAY: FREQ variable must be numeric", .{});
                s.frequency = col;
            }
        } else if (kw(t, i, "var")) {
            if (end == i + 1) return invalid(cx, t, i);
            try lists.append(cx.arena, ds, t[i + 1 .. end], &var_names, cx.diags);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            var j = i;
            try proc.parseProcFormat(cx.arena, t, &j, &formats);
        } else if (kw(t, i, "exact")) {
            exact_seen = true;
            for (t[i + 1 .. end]) |token| {
                if (token.tag == .name and eq(token.text, "wilcoxon")) s.options.exact_wilcoxon = true else if (token.tag == .name and eq(token.text, "hl")) {
                    s.hodges = true;
                    s.exact_hl = true;
                    s.options.wilcoxon = true;
                } else return proc.failGap(cx.diags, token.line, "PROC NPAR1WAY: EXACT {s} is not implemented", .{token.text});
            }
        } else if (kw(t, i, "strata")) {
            if (s.strata.len > 0) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: duplicate STRATA policy is not verified", .{});
            var slash = i + 1;
            while (slash < end and !at(t, slash, .slash)) slash += 1;
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, ds, t[i + 1 .. slash], &names, cx.diags);
            if (names.items.len == 0) return invalid(cx, t, i);
            const columns = try cx.arena.alloc(usize, names.items.len);
            for (names.items, 0..) |n, k| columns[k] = ds.indexOf(n).?;
            s.strata = columns;
            var kinds: std.ArrayList(stratified.Kind) = .empty;
            var j = slash + 1;
            while (j < end) {
                if (kw(t, j, "ranks") or kw(t, j, "weights")) {
                    if (!at(t, j + 1, .eq)) return invalid(cx, t, j + 1);
                    if (kw(t, j, "ranks")) {
                        if (!kw(t, j + 2, "stratum") and !kw(t, j + 2, "overall")) return invalid(cx, t, j + 2);
                        s.strata_options.overall = kw(t, j + 2, "overall");
                    } else {
                        if (!kw(t, j + 2, "stratum") and !kw(t, j + 2, "equal")) return invalid(cx, t, j + 2);
                        s.strata_options.equal = kw(t, j + 2, "equal");
                        strata_weights_seen = true;
                    }
                    j += 3;
                    continue;
                }
                const kind: stratified.Kind = if (kw(t, j, "wilcoxon")) .wilcoxon else if (kw(t, j, "median")) .median else if (kw(t, j, "vw") or kw(t, j, "normal")) .vw else if (kw(t, j, "savage")) .savage else if (kw(t, j, "perm")) .data else if (kw(t, j, "scores") and at(t, j + 1, .eq) and kw(t, j + 2, "data")) blk: {
                    j += 2;
                    break :blk .data;
                } else return invalid(cx, t, j);
                if (std.mem.indexOfScalar(stratified.Kind, kinds.items, kind) == null) try kinds.append(cx.arena, kind);
                j += 1;
            }
            if (kinds.items.len > 0) s.strata_kinds = kinds.items;
        } else if (kw(t, i, "output")) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: OUTPUT is not implemented", .{}) else if (kw(t, i, "x")) {
            // X is deliberately outside the generic mid-step skip predicate.
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (at(t, i, .name) and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    s.class = class_col orelse return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: CLASS statement required", .{});
    s.input.ds = try by.withFormats(cx.arena, ds, formats.items);
    const pb = try bys.resolve(cx.arena, s.input.ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = s.input.ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    var variables: std.ArrayList(usize) = .empty;
    if (var_names.items.len == 0) {
        for (ds.columns.items, 0..) |col, k| if (col.type == .num and k != s.class and (s.frequency == null or k != s.frequency.?) and std.mem.indexOfScalar(usize, cols, k) == null and std.mem.indexOfScalar(usize, s.strata, k) == null) try variables.append(cx.arena, k);
    } else for (var_names.items) |n| {
        const col = ds.indexOf(n).?;
        if (ds.columns.items[col].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: VAR variable {s} must be numeric", .{n});
        if (std.mem.indexOfScalar(usize, variables.items, col) == null) try variables.append(cx.arena, col);
    }
    if (variables.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: no numeric analysis variables", .{});
    s.variables = variables.items;
    if (!strata_weights_seen) s.strata_options.equal = s.strata_options.overall;
    if (!chosen and s.strata.len == 0) {
        const correction = s.options.continuity;
        const exact = s.options.exact_wilcoxon;
        s.options = .{};
        s.options.continuity = correction;
        s.options.exact_wilcoxon = exact;
    }
    if (exact_seen and !s.options.exact_wilcoxon and !s.exact_hl) {
        if (s.options.wilcoxon and !s.options.anova and !s.options.median and !s.options.vw and !s.options.savage and !s.options.edf and !s.options.ab and !s.options.st and !s.options.klotz and !s.options.mood and !s.options.conover and !s.options.data) s.options.exact_wilcoxon = true else return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: default EXACT analyses other than WILCOXON are not implemented", .{});
    }
    if (s.options.exact_wilcoxon or s.plots_wilcoxon) s.options.wilcoxon = true;
    if (s.plots_fp) s.fp_test = true;
    if (s.plots_edf) s.options.edf = true;
    return s;
}

pub const Input = struct { values: []const f64, groups: []const usize, labels: []const []const u8, reference_labels: []const []const u8, observations: []const usize, strata: []const usize, strata_labels: []const []const u8 };
/// Expand truncated positive FREQ after per-VAR missing selection. CLASS
/// membership uses formatted values and levels retain first-observation order.
pub fn prepare(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, variable: usize) diag.Error!Input {
    const a = cx.arena;
    const valid = try a.alloc(bool, rows.len);
    const freqs = try a.alloc(f64, rows.len);
    for (rows, 0..) |row, k| {
        const f = if (s.frequency) |c| row[c].num else 1;
        freqs[k] = if (std.math.isFinite(f) and f >= 1) @floor(f) else 0;
        valid[k] = freqs[k] > 0 and (s.descriptor_only or !selection.missing(row[variable]));
        if (s.stratified_selection and !s.missing) for (s.strata) |col| {
            if (selection.missing(row[col])) valid[k] = false;
        };
    }
    const levels = try classes.build(a, s.input.ds, rows, s.class, .{ .order = .data, .missing = if (s.missing) .include else .exclude, .include_rows = valid, .frequencies = freqs });
    var values: std.ArrayList(f64) = .empty;
    var groups: std.ArrayList(usize) = .empty;
    var observations: std.ArrayList(usize) = .empty;
    var strata_ids: std.ArrayList(usize) = .empty;
    var strata_keys: std.ArrayList([]const u8) = .empty;
    var strata_labels: std.ArrayList([]const u8) = .empty;
    for (rows, 0..) |row, k| if (levels.row_to_level[k]) |level| {
        if (!valid[k]) continue;
        // Avoid a huge materialization without silently reducing the FREQ.
        if (freqs[k] > 1_000_000 or @as(f64, @floatFromInt(values.items.len)) + freqs[k] > 1_000_000) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: expanded frequency above one million is not implemented", .{});
        var key: std.ArrayList(u8) = .empty;
        var label: std.ArrayList(u8) = .empty;
        for (s.strata, 0..) |col, part| {
            const info = s.input.ds.columns.items[col];
            const shown = if (info.format) |format| try fmt.apply(a, row[col], format) else try proc.cellText(a, row[col]);
            const identity = if (info.format != null or info.type == .char or selection.missing(row[col])) std.mem.trimEnd(u8, shown, " ") else try std.fmt.allocPrint(a, "{x}", .{@as(u64, @bitCast(if (row[col].num == 0) @as(f64, 0) else row[col].num))});
            try key.print(a, "{d}:{s};", .{ identity.len, identity });
            if (part > 0) try label.append(a, ' ');
            try label.print(a, "{s}={s}", .{ info.name, std.mem.trim(u8, shown, " ") });
        }
        const stratum = for (strata_keys.items, 0..) |old, id| {
            if (std.mem.eql(u8, old, key.items)) break id;
        } else blk: {
            try strata_keys.append(a, key.items);
            try strata_labels.append(a, label.items);
            break :blk strata_keys.items.len - 1;
        };
        const n: usize = @intFromFloat(freqs[k]);
        for (0..n) |_| {
            try values.append(a, if (s.descriptor_only and selection.missing(row[variable])) 0 else row[variable].num);
            try groups.append(a, level);
            try observations.append(a, k + 1);
            try strata_ids.append(a, stratum);
        }
    };
    const labels = try a.alloc([]const u8, levels.levels.len);
    const reference_labels = try a.alloc([]const u8, levels.levels.len);
    for (levels.levels, 0..) |l, k| {
        labels[k] = std.mem.trim(u8, l.label, " ");
        reference_labels[k] = l.label;
    }
    return .{ .values = values.items, .groups = groups.items, .labels = labels, .reference_labels = reference_labels, .observations = observations.items, .strata = strata_ids.items, .strata_labels = strata_labels.items };
}

fn num(a: A, x: ?f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try fmt.apply(a, .{ .num = x orelse std.math.nan(f64) }, spec), " ");
}
fn scoreNum(a: A, x: f64) ![]const u8 {
    // SAS score tables retain a decimal for exact integral small scores and
    // two decimals for larger rank sums; nonintegral statistics retain six.
    return num(a, x, if (@abs(x) >= 100) "12.2" else if (x == @round(x)) "12.1" else "12.6");
}
fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, rep: ?[]const Value) !void {
    if (rep) |row| if (s.by_cols.len > 0) try by.appendLine(cx.arena, out, s.input.ds, row, s.by_cols);
    try out.appendSlice(cx.arena, "\nThe NPAR1WAY Procedure\n\n");
}
fn finishTable(cx: proc.ProcCtx, out: *std.ArrayList(u8), start: usize, s: Spec, v: usize, name: []const u8) !void {
    const listing = cx.listing orelse return;
    if (out.items.len == start) return;
    const prefix = if (s.by_number) |n| try std.fmt.allocPrint(cx.arena, "Npar1way.ByGroup{d}", .{n}) else "Npar1way";
    const path = try std.fmt.allocPrint(cx.arena, "{s}.{s}.{s}", .{ prefix, try @import("../ods_listing.zig").pathPart(cx.arena, s.input.ds.columns.items[v].name), name });
    if (!listing.accepts(path)) {
        out.shrinkRetainingCapacity(start);
        return;
    }
    try listing.traceObject(cx.arena, name, null, null, path);
}
fn renderScores(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, input: Input, r: stats.Result, v: usize, rep: ?[]const Value, sc: stats.ScoreAnalysis) !void {
    const a = cx.arena;
    var start = out.items.len;
    const analysis_start = start;
    try heading(cx, out, s, rep);
    const label: []const u8 = switch (sc.kind) {
        .wilcoxon => "Wilcoxon Scores (Rank Sums)",
        .median => "Median Scores (Number of Points Above Median)",
        .vw => "Van der Waerden Scores (Normal)",
        .savage => "Savage Scores (Exponential)",
        .ab => "Ansari-Bradley Scores",
        .st => "Siegel-Tukey Scores",
        .klotz => "Klotz Scores",
        .mood => "Mood Scores",
        .conover => "Conover Scores",
        .data => "Data Scores",
    };
    try out.print(a, "{s} for Variable {s}\nClassified by Variable {s}\n\nSum of Expected Std Dev Mean\n{s} N Scores Under H0 Under H0 Score\n", .{ label, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, s.input.ds.columns.items[s.class].name });
    for (sc.groups, 0..) |g, k| try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ input.labels[k], r.counts[k], try scoreNum(a, g.sum), try (if (g.expected == @round(g.expected)) num(a, g.expected, "12.1") else num(a, g.expected, "12.6")), try (if (g.stddev == @round(g.stddev)) num(a, g.stddev, "12.1") else num(a, g.stddev, "12.6")), try num(a, g.mean, if (sc.kind == .median and (g.mean == 0 or g.mean == 0.5 or g.mean == 1)) "12.2" else "12.6") });
    if (sc.has_ties) try out.appendSlice(a, "\nAverage scores were used for ties.\n");
    const object_prefix: []const u8 = switch (sc.kind) {
        .wilcoxon => "Wilcoxon",
        .median => "Median",
        .vw => "VW",
        .savage => "Savage",
        .ab => "AB",
        .st => "ST",
        .klotz => "Klotz",
        .mood => "Mood",
        .conover => "Conover",
        .data => "DataScores",
    };
    try finishTable(cx, out, start, s, v, try std.fmt.allocPrint(a, "{s}Scores", .{object_prefix}));
    start = out.items.len;
    const short: []const u8 = switch (sc.kind) {
        .wilcoxon => "Wilcoxon",
        .median => "Median",
        .vw => "Van der Waerden",
        .savage => "Savage",
        .ab => "Ansari-Bradley",
        .st => "Siegel-Tukey",
        .klotz => "Klotz",
        .mood => "Mood",
        .conover => "Conover",
        .data => "Data Scores",
    };
    if (sc.two_sample) |ts| {
        if (start == analysis_start) try heading(cx, out, s, rep);
        try out.print(a, "\n{s} Two-Sample Test\n\n", .{short});
        if (sc.kind == .wilcoxon) {
            try out.appendSlice(a, "t Approximation");
            if (ts.exact != null) try out.appendSlice(a, " ----------Exact----------");
            try out.appendSlice(a, "\n");
        }
        const right = if (ts.z) |z| z > 0 else false;
        const tail: []const u8 = if (right) "Pr > Z" else "Pr < Z";
        try out.print(a, "{s} Z {s} Pr > |Z|", .{ if (ts.exact != null) @as([]const u8, "Statistic (S)") else "Statistic", tail });
        if (sc.kind == .wilcoxon) try out.print(a, " {s} Pr > |Z|", .{tail});
        if (ts.exact != null) try out.print(a, " {s} Pr >= |S-Mean|", .{if (ts.statistic > sc.groups[ts.selected].expected) @as([]const u8, "Pr >= S") else "Pr <= S"});
        try out.print(a, "\n{s} {s} {s} {s}", .{ try num(a, ts.statistic, "12.4"), try num(a, ts.z, "12.4"), try num(a, ts.p_one, "pvalue6.4"), try num(a, ts.p_two, "pvalue6.4") });
        if (sc.kind == .wilcoxon) try out.print(a, " {s} {s}", .{ try num(a, ts.p_t_one, "pvalue6.4"), try num(a, ts.p_t_two, "pvalue6.4") });
        if (ts.exact) |e| try out.print(a, " {s} {s}", .{ try num(a, if (ts.statistic > sc.groups[ts.selected].expected) e.upper else e.lower, "pvalue6.4"), try num(a, e.two_sided, "pvalue6.4") });
        try out.appendSlice(a, "\n");
        if ((sc.kind == .wilcoxon or sc.kind == .st) and s.options.continuity) try out.appendSlice(a, "\nZ includes a continuity correction of 0.5.\n");
    }
    try finishTable(cx, out, start, s, v, try std.fmt.allocPrint(a, "{s}Test", .{object_prefix}));
    start = out.items.len;
    if (start == analysis_start) try heading(cx, out, s, rep);
    try out.print(a, "\n{s}\n\nChi-Square DF Pr > ChiSq\n{s} {d} {s}\n", .{ if (sc.kind == .wilcoxon) @as([]const u8, "Kruskal-Wallis Test") else try std.fmt.allocPrint(a, "{s} One-Way Analysis", .{short}), try num(a, sc.chi_square, "12.4"), sc.df, try num(a, sc.p, "pvalue6.4") });
    try finishTable(cx, out, start, s, v, if (sc.kind == .wilcoxon) "KruskalWallisTest" else try std.fmt.allocPrint(a, "{s}Analysis", .{object_prefix}));
}
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, input: Input, r: stats.Result, v: usize, rep: ?[]const Value) !void {
    const a = cx.arena;
    const variable = s.input.ds.columns.items[v].name;
    const class = s.input.ds.columns.items[s.class].name;
    var start = out.items.len;
    if (r.anova) |an| {
        const anova_start = start;
        try heading(cx, out, s, rep);
        try out.print(a, "Analysis of Variance for Variable {s}\nClassified by Variable {s}\n\n{s} N Mean\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s}\n", .{ input.labels[k], n, try num(a, r.means[k], "12.6") });
        try finishTable(cx, out, start, s, v, "ClassMeans");
        start = out.items.len;
        if (start == anova_start) try heading(cx, out, s, rep);
        try out.print(a, "\nSource DF Sum of Squares Mean Square F Value Pr > F\nAmong {d} {s} {s} {s} {s}\nWithin {d} {s} {s}\n", .{ an.among_df, try num(a, an.among_ss, "16.6"), try num(a, an.among_ms, if (@abs(an.among_ms) >= 1000) "16.5" else "16.6"), try num(a, an.f, "12.4"), try num(a, an.p, "pvalue6.4"), an.within_df, try num(a, an.within_ss, "16.6"), try num(a, an.within_ms, if (@abs(an.within_ms) >= 500) "16.5" else "16.6") });
        if (r.has_ties) try out.appendSlice(a, "\nAverage scores were used for ties.\n");
        try finishTable(cx, out, start, s, v, "ANOVA");
    }
    for (r.scores) |sc| try renderScores(cx, out, s, input, r, v, rep, sc);
    if (r.edf) |e| {
        start = out.items.len;
        const edf_start = start;
        try heading(cx, out, s, rep);
        try out.print(a, "Kolmogorov-Smirnov Test for Variable {s}\nClassified by Variable {s}\n\nEDF at Deviation from Mean\n{s} N Maximum at Maximum\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s} {s}\n", .{ input.labels[k], n, try num(a, e.at_max[k], "12.6"), try num(a, e.deviations[k], "12.6") });
        try out.print(a, "Total {d} {s}\n\nMaximum Deviation Occurred at Observation {d}\nValue of {s} at Maximum = {s}\n\n", .{ r.n, try num(a, e.pooled_at_max, "12.6"), input.observations[e.max_index], variable, try num(a, e.max_value, "12.1") });
        try finishTable(cx, out, start, s, v, "KSTest");
        start = out.items.len;
        if (start == edf_start) try heading(cx, out, s, rep);
        if (e.d) |d| try out.print(a, "Kolmogorov-Smirnov Two-Sample Test (Asymptotic)\n\nKS {s} D {s}\nKSa {s} Pr > KSa {s}\n", .{ try num(a, e.ks, "12.6"), try num(a, d, "12.6"), try num(a, e.ksa, "12.6"), try num(a, e.ks_p, "pvalue6.4") }) else try out.print(a, "Kolmogorov-Smirnov Statistics (Asymptotic)\n\nKS {s} KSa {s}\n", .{ try num(a, e.ks, "12.6"), try num(a, e.ksa, "12.6") });
        if (s.edf_one_sided) try out.print(a, "D+ {s} Pr > D+ {s}\nD- {s} Pr > D- {s}\n", .{ try num(a, e.d_plus, "12.6"), try num(a, e.d_plus_p, "pvalue6.4"), try num(a, e.d_minus, "12.6"), try num(a, e.d_minus_p, "pvalue6.4") });
        try finishTable(cx, out, start, s, v, if (e.d != null) "KS2Stats" else "KSStats");
        start = out.items.len;
        if (start == edf_start) try heading(cx, out, s, rep);
        try out.print(a, "\nCramer-von Mises Test for Variable {s}\nClassified by Variable {s}\n\nSummed Deviation\n{s} N from Mean\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s}\n", .{ input.labels[k], n, try num(a, e.cm_components[k], "12.6") });
        try finishTable(cx, out, start, s, v, "CVMTest");
        start = out.items.len;
        if (start == edf_start) try heading(cx, out, s, rep);
        try out.print(a, "\nCramer-von Mises Statistics (Asymptotic)\n\nCM {s} CMa {s}\n", .{ try num(a, e.cm, "12.6"), try num(a, e.cma, "12.6") });
        try finishTable(cx, out, start, s, v, "CVMStats");
        if (e.kuiper) |k| {
            start = out.items.len;
            if (start == edf_start) try heading(cx, out, s, rep);
            try out.print(a, "\nKuiper Test for Variable {s}\nClassified by Variable {s}\n\nDeviation\n{s} N from Mean\n", .{ variable, class, class });
            for (r.counts, 0..) |n, j| try out.print(a, "{s} {d} {s}\n", .{ input.labels[j], n, try num(a, e.kuiper_deviations[j], "12.6") });
            try finishTable(cx, out, start, s, v, "KuiperTest");
            start = out.items.len;
            if (start == edf_start) try heading(cx, out, s, rep);
            try out.print(a, "\nKuiper Two-Sample Test (Asymptotic)\n\nK {s} Ka {s} Pr > Ka {s}\n", .{ try num(a, k, "12.6"), try num(a, e.kuiper_scaled, "12.6"), try num(a, e.kuiper_p, "pvalue6.4") });
            try finishTable(cx, out, start, s, v, "KuiperStats");
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    var s = try parse(cx, t);
    const graphs = if (cx.graphics) |g| g.enabled != false and (g.enabled == true or g.cli_dir != null or g.gpath != null) else false;
    if (!s.noprint and !s.plots_none and graphs and !s.plots_only and (s.options.anova or s.options.median or s.options.vw or s.options.savage or s.options.ab or s.options.st or s.options.klotz or s.options.mood or s.options.conover or s.options.data)) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: default graphics for the selected score analyses are not implemented; use PLOTS(ONLY) or PLOTS=NONE", .{});
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    var body: std.ArrayList(u8) = .empty;
    var plot_order: usize = 0;
    for (slices, 0..) |slice, bi| for (s.variables) |v| {
        s.by_number = if (s.by_cols.len > 0) bi + 1 else null;
        const input = try prepare(cx, s, slice.rows, v);
        if (s.variable_info and !s.noprint) {
            const info_start = body.items.len;
            try heading(cx, &body, s, slice.rep);
            const info = try varinfo.collect(cx.arena, s.input.ds, slice.rows, s.class, v, s.frequency, s.missing);
            try varinfo.render(cx.arena, &body, s.input.ds.columns.items[v].name, info, s.frequency != null, s.variable_ties);
            try finishTable(cx, &body, info_start, s, v, "VarInfo");
        }
        if (input.labels.len < 2) {
            try cx.diags.warn(0, "PROC NPAR1WAY: fewer than two nonempty CLASS levels for {s}", .{s.input.ds.columns.items[v].name});
            continue;
        }
        const r = stats.compute(cx.arena, input.values, input.groups, input.labels.len, s.options) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: analysis cannot be computed ({s})", .{@errorName(err)}),
        };
        if (s.edf_one_sided and input.labels.len != 2) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: one-sided EDF requires two CLASS levels", .{});
        const analysis_start = body.items.len;
        if (!s.noprint) try render(cx, &body, s, input, r, v, slice.rep);
        if (s.strata.len > 0) {
            var strat_spec = s;
            strat_spec.stratified_selection = true;
            const si = try prepare(cx, strat_spec, slice.rows, v);
            if (si.labels.len != 2) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: stratified analysis requires two nonempty CLASS levels", .{});
            for (s.strata_kinds) |kind| {
                var options = s.strata_options;
                options.kind = kind;
                const sr = stratified.compute(cx.arena, si.values, si.groups, si.strata, si.strata_labels.len, options) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: stratified analysis unavailable ({s})", .{@errorName(err)}),
                };
                if (!s.noprint) {
                    if (v == s.variables[0] and kind == s.strata_kinds[0]) {
                        var descriptor = strat_spec;
                        descriptor.descriptor_only = true;
                        const di = try prepare(cx, descriptor, slice.rows, v);
                        const frequencies = try cx.arena.alloc(usize, di.strata_labels.len);
                        @memset(frequencies, 0);
                        for (di.strata) |stratum| frequencies[stratum] += 1;
                        const start = body.items.len;
                        try heading(cx, &body, s, slice.rep);
                        try body.print(cx.arena, "Stratum Information\nStratum Frequency\n", .{});
                        for (frequencies, di.strata_labels) |frequency, label| try body.print(cx.arena, "{s} {d}\n", .{ label, frequency });
                        try finishTable(cx, &body, start, s, v, "StrataInfo");
                    }
                    const method_start = body.items.len;
                    try body.print(cx.arena, "\nStratified Analysis Method\nRanks {s}\nWeights {s}\nReference Class {s}\n", .{ if (options.overall) @as([]const u8, "Overall") else "Within Strata", if (options.equal) @as([]const u8, "Equal") else "1/(N+1)", si.labels[sr.selected] });
                    try finishTable(cx, &body, method_start, s, v, "StrataMethod");
                    const prefix: []const u8 = switch (kind) {
                        .wilcoxon => "Wilcoxon",
                        .median => "Median",
                        .vw => "VW",
                        .savage => "Savage",
                        .data => "DataScores",
                    };
                    const scores_start = body.items.len;
                    try body.print(cx.arena, "\n{s} Scores by Strata for Variable {s}\nStratum N Sum Expected Std Dev\n", .{ prefix, s.input.ds.columns.items[v].name });
                    for (sr.strata, si.strata_labels) |stratum, label| try body.print(cx.arena, "{s} {d} {s} {s} {s}\n", .{ label, stratum.selected_n, try num(cx.arena, stratum.sum, "12.6"), try num(cx.arena, stratum.expected, "12.6"), try num(cx.arena, @sqrt(stratum.variance), "12.6") });
                    try finishTable(cx, &body, scores_start, s, v, try std.fmt.allocPrint(cx.arena, "{s}Strata", .{prefix}));
                    const test_start = body.items.len;
                    try body.print(cx.arena, "\nStratified {s} Test\nStatistic Expected Variance Z One-Sided Pr Two-Sided Pr\n{s} {s} {s} {s} {s} {s}\n", .{ prefix, try num(cx.arena, sr.sum, "12.6"), try num(cx.arena, sr.expected, "12.6"), try num(cx.arena, sr.variance, "12.6"), try num(cx.arena, sr.z, "12.4"), try num(cx.arena, sr.p_one, "pvalue6.4"), try num(cx.arena, sr.p_two, "pvalue6.4") });
                    try finishTable(cx, &body, test_start, s, v, try std.fmt.allocPrint(cx.arena, "{s}StrataTest", .{prefix}));
                }
            }
        }
        if (s.fp_test) {
            if (input.labels.len != 2) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: Fligner-Policello requires two CLASS levels", .{});
            var reference: ?usize = null;
            if (s.fp_reference) |ref| switch (ref) {
                .index => |index| reference = index,
                .label => |label| {
                    reference = for (input.reference_labels, 0..) |value, index| {
                        if (std.mem.eql(u8, value, std.mem.trimEnd(u8, label, " "))) break index;
                    } else return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: FP reference class not found", .{});
                },
            };
            const result = fp.compute(cx.arena, input.values, input.groups, reference) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: FP unavailable ({s})", .{@errorName(err)}),
            };
            if (result.z == null) try cx.diags.warn(0, "PROC NPAR1WAY: Fligner-Policello standardization is undefined because its scale is zero", .{});
            if (!s.noprint) {
                var start = body.items.len;
                const fp_start = start;
                try heading(cx, &body, s, slice.rep);
                try body.print(cx.arena, "Fligner-Policello Placements for Variable {s}\nClassified by Variable {s}\n\n{s} N Sum of Placements Mean Placement Std Dev\n", .{ s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, s.input.ds.columns.items[s.class].name });
                for (result.groups, 0..) |g, i| try body.print(cx.arena, "{s} {d} {s} {s} {s}\n", .{ input.labels[i], g.n, try num(cx.arena, g.sum, "12.6"), try num(cx.arena, g.mean, "12.6"), try num(cx.arena, g.stddev, "12.6") });
                try finishTable(cx, &body, start, s, v, "FPPlacements");
                start = body.items.len;
                if (start == fp_start) try heading(cx, &body, s, slice.rep);
                try body.print(cx.arena, "\nFligner-Policello Test\nDifference ({s} - {s}) Z {s} Pr > |Z|\n{s} {s} {s} {s}\n", .{ input.labels[1 - result.reference], input.labels[result.reference], if ((result.z orelse 0) > 0) @as([]const u8, "Pr > Z") else "Pr < Z", try num(cx.arena, result.difference, "12.4"), try num(cx.arena, result.z, "12.4"), try num(cx.arena, result.p_one, "pvalue6.4"), try num(cx.arena, result.p_two, "pvalue6.4") });
                try finishTable(cx, &body, start, s, v, "FPTest");
            }
            if (!s.noprint and !s.plots_none and graphs and (!s.plots_only or s.plots_fp)) {
                var by_text: std.ArrayList(u8) = .empty;
                if (slice.rep) |rep| if (s.by_cols.len > 0) try by.appendLine(cx.arena, &by_text, s.input.ds, rep, s.by_cols);
                const bytes = plots.renderNamed(cx.arena, result.placements, input.groups, input.labels, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, if (s.fp_plot_stats orelse s.plot_stats) result.p_two else null, std.mem.trim(u8, by_text.items, " \r\n"), "fpboxplot", "Distribution of Fligner-Policello Placements", "Placement", "Pr > |Z|") catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: FP plot unavailable ({s})", .{@errorName(err)}),
                };
                const prefix = if (s.by_number) |n| try std.fmt.allocPrint(cx.arena, "Npar1way.ByGroup{d}", .{n}) else "Npar1way";
                try cx.graphics.?.queue(plot_order, "FPBoxPlot", bytes, .{ .name = .FPBoxPlot, .label = "Box Plot of Fligner-Policello Placements", .template = null, .path = try std.fmt.allocPrint(cx.arena, "{s}.{s}.FPBoxPlot", .{ prefix, try @import("../ods_listing.zig").pathPart(cx.arena, s.input.ds.columns.items[v].name) }) });
                plot_order += 1;
            }
        }
        if (s.hodges) {
            if (input.labels.len != 2) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: Hodges-Lehmann requires two CLASS levels", .{});
            var reference: usize = if (r.counts[0] > r.counts[1]) 0 else 1;
            if (s.reference) |ref| switch (ref) {
                .index => |index| reference = index,
                .label => |label| {
                    reference = for (input.reference_labels, 0..) |value, index| {
                        if (std.mem.eql(u8, value, std.mem.trimEnd(u8, label, " "))) break index;
                    } else return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: HL reference class not found", .{});
                },
            };
            var x: std.ArrayList(f64) = .empty;
            var y: std.ArrayList(f64) = .empty;
            for (input.values, input.groups) |value, group| {
                if (group == reference) try x.append(cx.arena, value) else try y.append(cx.arena, value);
            }
            const estimate = hl.compute(cx.arena, x.items, y.items, s.alpha, s.exact_hl) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: HL unavailable ({s})", .{@errorName(err)}),
            };
            if (!s.noprint) {
                const start = body.items.len;
                if (start == analysis_start) try heading(cx, &body, s, slice.rep);
                try body.print(cx.arena, "\nHodges-Lehmann Estimation\n\nLocation Shift ({s} - {s}) {s}\n\nInterval Asymptotic\nType {s}% Confidence Limits Midpoint Standard Error\nAsymptotic (Moses) {s} {s} {s} {s}\n", .{ input.labels[1 - reference], input.labels[reference], try num(cx.arena, estimate.estimate, "12.4"), try num(cx.arena, 100 * (1 - s.alpha), "best8."), try num(cx.arena, estimate.asymptotic.lower, "12.4"), try num(cx.arena, estimate.asymptotic.upper, "12.4"), try num(cx.arena, estimate.asymptotic.midpoint(), "12.4"), try num(cx.arena, estimate.standard_error, "12.4") });
                if (estimate.exact) |interval| try body.print(cx.arena, "Exact {s} {s} {s}\n", .{ try num(cx.arena, interval.lower, "12.4"), try num(cx.arena, interval.upper, "12.4"), try num(cx.arena, interval.midpoint(), "12.4") });
                try finishTable(cx, &body, start, s, v, "HodgesLehmann");
            }
        }
        if (!s.noprint and !s.plots_none and graphs and (!s.plots_only or s.plots_wilcoxon)) for (r.scores) |sc| {
            if (sc.kind != .wilcoxon) continue;
            var by_text: std.ArrayList(u8) = .empty;
            if (slice.rep) |rep| if (s.by_cols.len > 0) try by.appendLine(cx.arena, &by_text, s.input.ds, rep, s.by_cols);
            const bytes = plots.render(cx.arena, sc.values, input.groups, input.labels, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, if (s.wilcoxon_plot_stats orelse s.plot_stats) sc.p else null, std.mem.trim(u8, by_text.items, " \r\n")) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: cannot render Wilcoxon plot ({s})", .{@errorName(err)}),
            };
            const object = try plots.object(cx.arena, if (s.by_cols.len > 0) bi + 1 else null, s.input.ds.columns.items[v].name);
            try cx.graphics.?.queue(plot_order, "WilcoxonBoxPlot", bytes, object);
            plot_order += 1;
        };
        if (!s.noprint and !s.plots_none and graphs and (!s.plots_only or s.plots_edf)) if (r.edf) |e| {
            var by_text: std.ArrayList(u8) = .empty;
            if (slice.rep) |rep| if (s.by_cols.len > 0) try by.appendLine(cx.arena, &by_text, s.input.ds, rep, s.by_cols);
            const bytes = edf_plot.render(cx.arena, input.values, input.groups, input.labels, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, std.mem.trim(u8, by_text.items, " \r\n"), if (s.edf_plot_stats orelse s.plot_stats) e.ks_p else null) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: EDF plot unavailable ({s})", .{@errorName(err)}),
            };
            const prefix = if (s.by_number) |n| try std.fmt.allocPrint(cx.arena, "Npar1way.ByGroup{d}", .{n}) else "Npar1way";
            try cx.graphics.?.queue(plot_order, "EDFPlot", bytes, .{ .name = .EDFPlot, .label = "Empirical Distribution Plot", .template = null, .path = try std.fmt.allocPrint(cx.arena, "{s}.{s}.EDFPlot", .{ prefix, try @import("../ods_listing.zig").pathPart(cx.arena, s.input.ds.columns.items[v].name) }) });
            plot_order += 1;
        };
    };
    try out.appendSlice(cx.arena, body.items);
}

test {
    _ = stats;
    _ = hl;
    _ = fp;
    _ = edf_plot;
    _ = stratified;
}

fn testData(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "group", "x", "y", "f", "b" }) |name| _ = try ds.addColumn(name, .num);
    _ = try ds.addColumn("text", .char);
    // Per-variable missingness differs. Frequency truncation removes row4;
    // missing CLASS row5 is included only under MISSING.
    const nan = std.math.nan(f64);
    const rows = [_][5]f64{ .{ 2, 10, nan, 2.9, 1 }, .{ 1, 20, 7, 1, 1 }, .{ 2, 30, 9, 1, 2 }, .{ 1, 40, 11, 0.9, 2 }, .{ nan, 50, 13, 1, 2 }, .{ 1, nan, 15, 2, 2 } };
    for (rows) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] }, .{ .num = row[4] }, .{ .str = "a" } });
    return ds;
}
test "STAT-NPAR1WAY-001 input roles per-variable missing FREQ truncation and class order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try testData(a);
    try lib.put("sample", ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const s = try parse(cx, try lex.tokenize(a, "proc npar1way wilcoxon; class group; var x y; freq f; run;", &diagnostics));
    const x = try prepare(cx, s, ds.rows.items, s.variables[0]);
    try std.testing.expectEqualSlices(f64, &.{ 10, 10, 20, 30 }, x.values);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1, 0 }, x.groups);
    try std.testing.expectEqualStrings("2", x.labels[0]);
    try std.testing.expectEqualStrings("1", x.labels[1]);
    const y = try prepare(cx, s, ds.rows.items, s.variables[1]);
    try std.testing.expectEqualSlices(f64, &.{ 7, 9, 15, 15 }, y.values);
    try std.testing.expectEqualStrings("1", y.labels[0]);
    const include = try parse(cx, try lex.tokenize(a, "proc npar1way missing wilcoxon; class group; var x; freq f; run;", &diagnostics));
    const xi = try prepare(cx, include, ds.rows.items, include.variables[0]);
    try std.testing.expectEqualSlices(f64, &.{ 10, 10, 20, 30, 50 }, xi.values);
    try std.testing.expectEqual(@as(usize, 3), xi.labels.len);
    try std.testing.expectEqualStrings(".", xi.labels[2]);
    const inferred = try parse(cx, try lex.tokenize(a, "proc npar1way wilcoxon; class group; freq f; by b; run;", &diagnostics));
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, inferred.variables);
    try std.testing.expectEqual(@as(usize, 6), ds.rowCount());
}
test "STAT-NPAR1WAY-001 BY last statement grouping NOPRINT and diagnostic guards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try testData(a);
    try lib.put("sample", ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const s = try parse(cx, try lex.tokenize(a, "proc npar1way wilcoxon; class group; var x; by descending x; by b; run;", &diagnostics));
    try std.testing.expectEqualSlices(usize, &.{4}, s.by_cols);
    try std.testing.expectEqualSlices(bool, &.{false}, s.by_desc);
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, &diagnostics);
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    try std.testing.expectEqual(@as(usize, 2), groups[0].rows.len);
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, "proc npar1way noprint wilcoxon; class group; var x; freq f; run;", &diagnostics));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    for ([_][]const u8{
        "proc npar1way wilcoxon; var x; run;",
        "proc npar1way wilcoxon; class group x; var x; run;",
        "proc npar1way wilcoxon; class group; var text; run;",
        "proc npar1way wilcoxon; class group; var x; freq text; run;",
        "proc npar1way wilcoxno; class group; var x; run;",
        "proc npar1way wilcoxon align=strata; class group; var x; strata b; run;",
        "proc npar1way wilcoxon; class group; var x; exact wilcoxon / mc; run;",
        "proc npar1way plots=medianplot; class group; var x; run;",
        "proc npar1way wilcoxon; class group; class group; var x; run;",
        "proc npar1way wilcoxon; class group; freq f; freq f; var x; run;",
    }, 0..) |source, k| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, source, &d)));
        try std.testing.expectEqual(@as(u8, if (k >= 5) 2 else 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), output.items.len);
    }
}
test "STAT-NPAR1WAY-001 original tied Wilcoxon runs with exact selected analysis only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "ranks");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("group", .char);
    for ([_]f64{ 40, 90, 80, 90, 120, 100, 90, 100, 90, 90, 120, 70 }, 0..) |x, i| try ds.appendRow(&.{ .{ .num = x }, .{ .str = if (i < 6) "A" else "B" } });
    try lib.put("ranks", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc npar1way data=ranks wilcoxon; class group; var x; exact wilcoxon; run;", &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "37.0000 -0.2500 0.4013 0.8026 0.4036 0.8072 0.4004 0.8009") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Median Scores") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0.1111 1 0.7389") != null);
}

test "STAT-NPAR1WAY-001 D014 midstep globals retain inert command notes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try testData(a));
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc npar1way wilcoxon noprint; title 'midstep'; ods listing; class group; x 'echo not-run'; dm log 'file not-created'; var x; run;", &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), d.list.items.len);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "X statement not executed") != null);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[1].message, "DM statement not executed") != null);
}

test "STAT-NPAR1WAY-001 graph requests honor OFF ONLY and NONE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try testData(a));
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = false };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    const source = "proc npar1way wilcoxon plots(only)=wilcoxonboxplot; class group; var x; run;";
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    graphics.enabled = true;
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expectEqual(@as(usize, 1), graphics.prepared.items.len);
    graphics.clear();
    try run(cx, &out, try lex.tokenize(a, "proc npar1way wilcoxon plots=none; class group; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc npar1way plots(only stats nostats)=wilcoxonboxplot; class group; var x; run;", &d)));
}

test "NPAR004 strata missing selection stays separate from unstratified and defaults exclude roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try testData(a);
    try lib.put("sample", ds);
    const changed = try a.dupe(Value, ds.rows.items[5]);
    changed[1] = .{ .num = 60 };
    changed[4] = Value.missing;
    ds.rows.items[5] = changed;
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var s = try parse(cx, try lex.tokenize(a, "proc npar1way; class group; var x; freq f; strata b / ranks=overall; run;", &d));
    try std.testing.expect(!s.options.wilcoxon and !s.options.anova and !s.options.edf);
    try std.testing.expect(s.strata_options.overall and s.strata_options.equal);
    const unstratified = try prepare(cx, s, ds.rows.items, s.variables[0]);
    try std.testing.expectEqualSlices(f64, &.{ 10, 10, 20, 30, 60, 60 }, unstratified.values);
    s.stratified_selection = true;
    const selected = try prepare(cx, s, ds.rows.items, s.variables[0]);
    try std.testing.expectEqualSlices(f64, &.{ 10, 10, 20, 30 }, selected.values);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 1 }, selected.strata);
    s.missing = true;
    const included = try prepare(cx, s, ds.rows.items, s.variables[0]);
    try std.testing.expectEqualSlices(f64, &.{ 10, 10, 20, 30, 50, 60, 60 }, included.values);
    try std.testing.expectEqual(@as(usize, 3), included.strata_labels.len);
}
test "NPAR004 HL object selection preserves only requested complete table and trace identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 5, 6, 7 }, 0..) |v, i| try ds.appendRow(&.{ .{ .num = if (i < 3) 1 else 2 }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var listing: @import("../ods_listing.zig").Listing = .{};
    _ = try listing.parse(a, &d, try lex.tokenize(a, "ods select HodgesLehmann;", &d));
    listing.trace = &d;
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d, .listing = &listing }, &out, try lex.tokenize(a, "proc npar1way varinfo hl(refclass=1) alpha=.2; class g; var x; exact hl; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Location Shift (2 - 1) 4.0000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Wilcoxon Scores") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Kruskal-Wallis") == null);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "Name:       HodgesLehmann") != null);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "Npar1way.x.HodgesLehmann") != null);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "Template:") == null);
}

test "NPAR004 scale score parser and object filtering run numerical producers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 8 }, 0..) |v, i| try ds.appendRow(&.{ .{ .num = if (i < 2) 0 else 1 }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var listing: @import("../ods_listing.zig").Listing = .{};
    _ = try listing.parse(a, &d, try lex.tokenize(a, "ods select ConoverScores;", &d));
    var out: std.ArrayList(u8) = .empty;
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .listing = &listing };
    const source = "proc npar1way ab st klotz mood conover scores=data correct=no; class g; var x; run;";
    const s = try parse(cx, try lex.tokenize(a, source, &d));
    try std.testing.expect(s.options.ab and s.options.st and s.options.klotz and s.options.mood and s.options.conover and s.options.data);
    try std.testing.expect(!s.options.wilcoxon and !s.options.edf and !s.options.anova);
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Conover Scores for Variable x") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "4.500000 14.500000 5.773503 2.250000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Average scores were used for ties.") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Two-Sample Test") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Mood Scores") == null);
}

test "NPAR004 HL string reference preserves significant leading label blanks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 5, 6, 7 }, 0..) |v, i| try ds.appendRow(&.{ .{ .str = if (i < 3) " A" else "B" }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc npar1way hl(refclass=' A') alpha=.2; class g; var x; run;", &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Location Shift (B - A) 4.0000") != null);
}

test "NPAR004 expanded FREQ reaches explicit HL pair allocation guard without partial listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "g", "x", "f" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 1 }, .{ .num = 1001 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 1001 } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc npar1way hl; class g; var x; freq f; run;", &d)));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "PairLimit") != null);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "NPAR005 FP EDF consumer flags graph ONLY OFF and reference orientation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 2, 4, 5 }, 0..) |v, i| try ds.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    const source = "proc npar1way fp(refclass='A') d plots(only)=(fpboxplot edfplot); class g; var x; run;";
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "6.0000 1.6641") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "D+ 0.666667 Pr > D+ 0.2636") != null);
    try std.testing.expectEqual(@as(usize, 2), graphics.prepared.items.len);
    try std.testing.expectEqualStrings("FPBoxPlot", graphics.prepared.items[0].kind);
    try std.testing.expectEqualStrings("EDFPlot", graphics.prepared.items[1].kind);
    graphics.clear();
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc npar1way fp d plots(only)=edfplot; class g; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), graphics.prepared.items.len);
    try std.testing.expectEqualStrings("EDFPlot", graphics.prepared.items[0].kind);
    graphics.clear();
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc npar1way fp; class g; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), graphics.prepared.items.len);
    try std.testing.expectEqualStrings("FPBoxPlot", graphics.prepared.items[0].kind);
    graphics.clear();
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc npar1way edf; class g; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), graphics.prepared.items.len);
    try std.testing.expectEqualStrings("EDFPlot", graphics.prepared.items[0].kind);
    graphics.clear();
    graphics.enabled = false;
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
}
test "NPAR005 FP zero-scale result remains visible and exact unsupported remains a gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 1, 5, 5 }, 0..) |v, i| try ds.appendRow(&.{ .{ .num = if (i < 2) 0 else 1 }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, "proc npar1way fp; class g; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "scale is zero") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "-4.0000 . . .") != null);
    diag.resetGap();
    defer diag.resetGap();
    var dg = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parse(.{ .arena = a, .lib = &lib, .diags = &dg }, try lex.tokenize(a, "proc npar1way edf; class g; var x; exact ks; run;", &dg)));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), dg.hasErrors()));
}

test "NPAR005 selected tests retain BY context and native identities without placement tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("b", .num);
    for (1..3) |b| for ([_]f64{ 1, 2, 3, 2, 4, 5 }, 0..) |v, i| try ds.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = v }, .{ .num = @floatFromInt(b) } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var listing: @import("../ods_listing.zig").Listing = .{};
    _ = try listing.parse(a, &d, try lex.tokenize(a, "ods select FPTest KS2Stats FPBoxPlot EDFPlot;", &d));
    listing.trace = &d;
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true, .listing = &listing };
    try run(.{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics, .listing = &listing }, &out, try lex.tokenize(a, "proc npar1way fp(refclass=1) d plots(only)=(fpboxplot edfplot); class g; var x; by b; run;", &d));
    try std.testing.expectEqual(@as(usize, 4), graphics.prepared.items.len);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "b=1"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "b=2"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Fligner-Policello Placements") == null);
    var graph_path = false;
    var table_path = false;
    for (d.list.items) |item| {
        if (std.mem.indexOf(u8, item.message, "Npar1way.ByGroup2.x.FPBoxPlot") != null) graph_path = true;
        if (std.mem.indexOf(u8, item.message, "Npar1way.ByGroup2.x.EDF.KS2Stats") != null) table_path = true;
    }
    try std.testing.expect(graph_path and table_path);
}

test "NPAR005 per-plot STATS overrides global NOSTATS independently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 2, 4, 5 }, 0..) |v, i| try ds.appendRow(&.{ .{ .num = if (i < 3) 0 else 1 }, .{ .num = v } });
    try lib.put("sample", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    try run(cx, &out, try lex.tokenize(a, "proc npar1way fp d plots(only nostats)=(fpboxplot(stats) edfplot); class g; var x; run;", &d));
    try std.testing.expectEqual(@as(usize, 2), graphics.prepared.items.len);
    try std.testing.expect(std.mem.indexOf(u8, graphics.prepared.items[0].bytes, "Pr &gt; |Z|") != null);
    try std.testing.expect(std.mem.indexOf(u8, graphics.prepared.items[1].bytes, "Pr &gt; KSa") == null);
    try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, "proc npar1way fp plots=fpboxplot(stats nostats); class g; var x; run;", &d)));
}
