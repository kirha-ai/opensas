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
const plots = @import("npar1way_plots.zig");
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
    plots_none: bool = false,
    plots_only: bool = false,
    plots_wilcoxon: bool = false,
    plot_stats: bool = true,
    options: stats.Options = .{},
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
    if (eq(name, "wilcoxon")) o.wilcoxon = true else if (eq(name, "median")) o.median = true else if (eq(name, "vw") or eq(name, "normal")) o.vw = true else if (eq(name, "savage")) o.savage = true else if (eq(name, "anova")) o.anova = true else if (eq(name, "edf") or eq(name, "ks")) o.edf = true else return false;
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
        } else if (kw(t, i, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (kw(t, i, "missing")) {
            s.missing = true;
            i += 1;
        } else if (at(t, i, .name) and analysis(&s.options, t[i].text)) {
            chosen = true;
            i += 1;
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
                if (kw(t, i, "none")) s.plots_none = true else if (kw(t, i, "wilcoxonboxplot") or kw(t, i, "wilcoxon")) s.plots_wilcoxon = true else return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: plot {s} is not implemented", .{t[i].text});
                i += 1;
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
                if (token.tag == .name and eq(token.text, "wilcoxon")) s.options.exact_wilcoxon = true else return proc.failGap(cx.diags, token.line, "PROC NPAR1WAY: EXACT {s} is not implemented", .{token.text});
            }
        } else if (kw(t, i, "strata") or kw(t, i, "output")) return proc.failGap(cx.diags, t[i].line, "PROC NPAR1WAY: {s} is not implemented", .{t[i].text}) else if (kw(t, i, "x")) {
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
        for (ds.columns.items, 0..) |col, k| if (col.type == .num and k != s.class and (s.frequency == null or k != s.frequency.?) and std.mem.indexOfScalar(usize, cols, k) == null) try variables.append(cx.arena, k);
    } else for (var_names.items) |n| {
        const col = ds.indexOf(n).?;
        if (ds.columns.items[col].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: VAR variable {s} must be numeric", .{n});
        if (std.mem.indexOfScalar(usize, variables.items, col) == null) try variables.append(cx.arena, col);
    }
    if (variables.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC NPAR1WAY: no numeric analysis variables", .{});
    s.variables = variables.items;
    if (!chosen) {
        const correction = s.options.continuity;
        const exact = s.options.exact_wilcoxon;
        s.options = .{};
        s.options.continuity = correction;
        s.options.exact_wilcoxon = exact;
    }
    if (exact_seen and !s.options.exact_wilcoxon) {
        if (s.options.wilcoxon and !s.options.anova and !s.options.median and !s.options.vw and !s.options.savage and !s.options.edf) s.options.exact_wilcoxon = true else return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: default EXACT analyses other than WILCOXON are not implemented", .{});
    }
    if (s.options.exact_wilcoxon or s.plots_wilcoxon) s.options.wilcoxon = true;
    return s;
}

pub const Input = struct { values: []const f64, groups: []const usize, labels: []const []const u8, observations: []const usize };
/// Expand truncated positive FREQ after per-VAR missing selection. CLASS
/// membership uses formatted values and levels retain first-observation order.
pub fn prepare(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, variable: usize) diag.Error!Input {
    const a = cx.arena;
    const valid = try a.alloc(bool, rows.len);
    const freqs = try a.alloc(f64, rows.len);
    for (rows, 0..) |row, k| {
        const f = if (s.frequency) |c| row[c].num else 1;
        freqs[k] = if (std.math.isFinite(f) and f >= 1) @floor(f) else 0;
        valid[k] = freqs[k] > 0 and !selection.missing(row[variable]);
    }
    const levels = try classes.build(a, s.input.ds, rows, s.class, .{ .order = .data, .missing = if (s.missing) .include else .exclude, .include_rows = valid, .frequencies = freqs });
    var values: std.ArrayList(f64) = .empty;
    var groups: std.ArrayList(usize) = .empty;
    var observations: std.ArrayList(usize) = .empty;
    for (rows, 0..) |row, k| if (levels.row_to_level[k]) |level| {
        if (!valid[k]) continue;
        // Avoid a huge materialization without silently reducing the FREQ.
        if (freqs[k] > 1_000_000 or @as(f64, @floatFromInt(values.items.len)) + freqs[k] > 1_000_000) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: expanded frequency above one million is not implemented", .{});
        const n: usize = @intFromFloat(freqs[k]);
        for (0..n) |_| {
            try values.append(a, row[variable].num);
            try groups.append(a, level);
            try observations.append(a, k + 1);
        }
    };
    const labels = try a.alloc([]const u8, levels.levels.len);
    for (levels.levels, 0..) |l, k| labels[k] = std.mem.trim(u8, l.label, " ");
    return .{ .values = values.items, .groups = groups.items, .labels = labels, .observations = observations.items };
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
fn renderScores(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, input: Input, r: stats.Result, v: usize, rep: ?[]const Value, sc: stats.ScoreAnalysis) !void {
    const a = cx.arena;
    try heading(cx, out, s, rep);
    const label: []const u8 = switch (sc.kind) {
        .wilcoxon => "Wilcoxon Scores (Rank Sums)",
        .median => "Median Scores (Number of Points Above Median)",
        .vw => "Van der Waerden Scores (Normal)",
        .savage => "Savage Scores (Exponential)",
    };
    try out.print(a, "{s} for Variable {s}\nClassified by Variable {s}\n\nSum of Expected Std Dev Mean\n{s} N Scores Under H0 Under H0 Score\n", .{ label, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, s.input.ds.columns.items[s.class].name });
    for (sc.groups, 0..) |g, k| try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{ input.labels[k], r.counts[k], try scoreNum(a, g.sum), try (if (g.expected == @round(g.expected)) num(a, g.expected, "12.1") else num(a, g.expected, "12.6")), try (if (g.stddev == @round(g.stddev)) num(a, g.stddev, "12.1") else num(a, g.stddev, "12.6")), try num(a, g.mean, if (sc.kind == .median and (g.mean == 0 or g.mean == 0.5 or g.mean == 1)) "12.2" else "12.6") });
    if (r.has_ties) try out.appendSlice(a, "\nAverage scores were used for ties.\n");
    const short: []const u8 = switch (sc.kind) {
        .wilcoxon => "Wilcoxon",
        .median => "Median",
        .vw => "Van der Waerden",
        .savage => "Savage",
    };
    if (sc.two_sample) |ts| {
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
        if (sc.kind == .wilcoxon and s.options.continuity) try out.appendSlice(a, "\nZ includes a continuity correction of 0.5.\n");
    }
    try out.print(a, "\n{s}\n\nChi-Square DF Pr > ChiSq\n{s} {d} {s}\n", .{ if (sc.kind == .wilcoxon) @as([]const u8, "Kruskal-Wallis Test") else try std.fmt.allocPrint(a, "{s} One-Way Analysis", .{short}), try num(a, sc.chi_square, "12.4"), sc.df, try num(a, sc.p, "pvalue6.4") });
}
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, input: Input, r: stats.Result, v: usize, rep: ?[]const Value) !void {
    const a = cx.arena;
    const variable = s.input.ds.columns.items[v].name;
    const class = s.input.ds.columns.items[s.class].name;
    if (r.anova) |an| {
        try heading(cx, out, s, rep);
        try out.print(a, "Analysis of Variance for Variable {s}\nClassified by Variable {s}\n\n{s} N Mean\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s}\n", .{ input.labels[k], n, try num(a, r.means[k], "12.6") });
        try out.print(a, "\nSource DF Sum of Squares Mean Square F Value Pr > F\nAmong {d} {s} {s} {s} {s}\nWithin {d} {s} {s}\n", .{ an.among_df, try num(a, an.among_ss, "16.6"), try num(a, an.among_ms, if (@abs(an.among_ms) >= 1000) "16.5" else "16.6"), try num(a, an.f, "12.4"), try num(a, an.p, "pvalue6.4"), an.within_df, try num(a, an.within_ss, "16.6"), try num(a, an.within_ms, if (@abs(an.within_ms) >= 500) "16.5" else "16.6") });
        if (r.has_ties) try out.appendSlice(a, "\nAverage scores were used for ties.\n");
    }
    for (r.scores) |sc| try renderScores(cx, out, s, input, r, v, rep, sc);
    if (r.edf) |e| {
        try heading(cx, out, s, rep);
        try out.print(a, "Kolmogorov-Smirnov Test for Variable {s}\nClassified by Variable {s}\n\nEDF at Deviation from Mean\n{s} N Maximum at Maximum\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s} {s}\n", .{ input.labels[k], n, try num(a, e.at_max[k], "12.6"), try num(a, e.deviations[k], "12.6") });
        try out.print(a, "Total {d} {s}\n\nMaximum Deviation Occurred at Observation {d}\nValue of {s} at Maximum = {s}\n\n", .{ r.n, try num(a, e.pooled_at_max, "12.6"), input.observations[e.max_index], variable, try num(a, e.max_value, "12.1") });
        if (e.d) |d| try out.print(a, "Kolmogorov-Smirnov Two-Sample Test (Asymptotic)\n\nKS {s} D {s}\nKSa {s} Pr > KSa {s}\n", .{ try num(a, e.ks, "12.6"), try num(a, d, "12.6"), try num(a, e.ksa, "12.6"), try num(a, e.ks_p, "pvalue6.4") }) else try out.print(a, "Kolmogorov-Smirnov Statistics (Asymptotic)\n\nKS {s} KSa {s}\n", .{ try num(a, e.ks, "12.6"), try num(a, e.ksa, "12.6") });
        try out.print(a, "\nCramer-von Mises Test for Variable {s}\nClassified by Variable {s}\n\nSummed Deviation\n{s} N from Mean\n", .{ variable, class, class });
        for (r.counts, 0..) |n, k| try out.print(a, "{s} {d} {s}\n", .{ input.labels[k], n, try num(a, e.cm_components[k], "12.6") });
        try out.print(a, "\nCramer-von Mises Statistics (Asymptotic)\n\nCM {s} CMa {s}\n", .{ try num(a, e.cm, "12.6"), try num(a, e.cma, "12.6") });
        if (e.kuiper) |k| {
            try out.print(a, "\nKuiper Test for Variable {s}\nClassified by Variable {s}\n\nDeviation\n{s} N from Mean\n", .{ variable, class, class });
            for (r.counts, 0..) |n, j| try out.print(a, "{s} {d} {s}\n", .{ input.labels[j], n, try num(a, e.kuiper_deviations[j], "12.6") });
            try out.print(a, "\nKuiper Two-Sample Test (Asymptotic)\n\nK {s} Ka {s} Pr > Ka {s}\n", .{ try num(a, k, "12.6"), try num(a, e.kuiper_scaled, "12.6"), try num(a, e.kuiper_p, "pvalue6.4") });
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const graphs = if (cx.graphics) |g| g.enabled != false and (g.enabled == true or g.cli_dir != null or g.gpath != null) else false;
    if (!s.noprint and !s.plots_none and graphs and !s.plots_only and (s.options.anova or s.options.median or s.options.vw or s.options.savage or s.options.edf)) return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: default graphics other than Wilcoxon are not implemented; use PLOTS(ONLY)=WILCOXONBOXPLOT or PLOTS=NONE", .{});
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    var body: std.ArrayList(u8) = .empty;
    var plot_order: usize = 0;
    for (slices, 0..) |slice, bi| for (s.variables) |v| {
        const input = try prepare(cx, s, slice.rows, v);
        if (input.labels.len < 2) {
            try cx.diags.warn(0, "PROC NPAR1WAY: fewer than two nonempty CLASS levels for {s}", .{s.input.ds.columns.items[v].name});
            continue;
        }
        const r = stats.compute(cx.arena, input.values, input.groups, input.labels.len, s.options) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: analysis cannot be computed ({s})", .{@errorName(err)}),
        };
        if (!s.noprint) try render(cx, &body, s, input, r, v, slice.rep);
        if (!s.noprint and !s.plots_none and graphs) for (r.scores) |sc| {
            if (sc.kind != .wilcoxon) continue;
            var by_text: std.ArrayList(u8) = .empty;
            if (slice.rep) |rep| if (s.by_cols.len > 0) try by.appendLine(cx.arena, &by_text, s.input.ds, rep, s.by_cols);
            const bytes = plots.render(cx.arena, sc.values, input.groups, input.labels, s.input.ds.columns.items[v].name, s.input.ds.columns.items[s.class].name, if (s.plot_stats) sc.p else null, std.mem.trim(u8, by_text.items, " \r\n")) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, 0, "PROC NPAR1WAY: cannot render Wilcoxon plot ({s})", .{@errorName(err)}),
            };
            const object = try plots.object(cx.arena, if (s.by_cols.len > 0) bi + 1 else null, s.input.ds.columns.items[v].name);
            try cx.graphics.?.queue(plot_order, "WilcoxonBoxPlot", bytes, object);
            plot_order += 1;
        };
    };
    try out.appendSlice(cx.arena, body.items);
}

test {
    _ = stats;
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
        "proc npar1way wilcoxon; class group; var x; strata b; run;",
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
