//! PROC SURVEYMEANS declarations, variable roles, observation selection and
//! the default listing (Data Summary, Class Level Information, Stratum
//! Information, Statistics with the Taylor-series variance), SAS/STAT 15.4
//! chapter 121, physical pp.9907-9935. Every documented feature whose result
//! or layout has not been checked against a reference is a D-009 gap (rc 2)
//! raised before any listing text of its BY group is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const ods_table = @import("ods_table.zig");
const design = @import("survey_design.zig");
const tQuantile = @import("univ_inference.zig").tQuantile;
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Population = union(enum) {
    none,
    /// TOTAL=value: the same population total for every stratum.
    total: f64,
    /// RATE=value as a proportion: the same sampling rate for every stratum.
    rate: f64,
    /// TOTAL=data set: stratum variables plus `_TOTAL_`.
    total_data: *Dataset,
};

pub const Spec = struct {
    input: proc.ProcInput,
    /// Analysis variables in VAR order (all eligible numeric ones by default).
    vars: []const usize = &.{},
    /// Numeric variables analysed as categorical (CLASS statement).
    classes: []const usize = &.{},
    weight: ?usize = null,
    strata: []const usize = &.{},
    clusters: []const usize = &.{},
    /// STRATA / LIST.
    list: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    /// MISSING: missing STRATA and CLUSTER values are valid levels.
    missing: bool = false,
    alpha: f64 = 0.05,
    population: Population = .none,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYMEANS: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYMEANS: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Statistic keywords of the PROC statement (physical pp.9917-9921). The
/// default set NOBS MEAN STDERR CLM is what the listing shows; any explicit
/// selection belongs to the statistic-keyword tickets.
const statistic_keywords = [_][]const u8{ "all", "clm", "clsum", "cv", "cvsum", "df", "geomean", "gmclm", "gmstderr", "lclm", "lclsum", "lgmclm", "max", "mean", "median", "min", "nmiss", "nobs", "q1", "q3", "range", "ratio", "std", "stderr", "sum", "sumwgt", "t", "uclm", "uclsum", "ugmclm", "var", "varsum", "deciles", "quartiles", "percentile", "quantile", "pctl" };
const later_options = [_][]const u8{ "nomcar", "nosparse", "stacking", "plots", "plot", "varheader", "nonsymcl", "symcl", "order", "varmethod", "ncluster", "nclu", "nstrata", "nstr", "nmiss" };
const later_statements = [_][]const u8{ "domain", "subgroup", "poststrata", "ratio", "repweights" };

fn number(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!f64 {
    if (!at(t, i, .number)) return invalid(cx, t, i);
    return std.fmt.parseFloat(f64, t[i].text) catch invalid(cx, t, i);
}

/// Plain variable names up to `end` or a slash. Name ranges and special lists
/// are a gap, never silently one variable.
fn columns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, stop: *usize) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end and !at(t, j, .slash)) : (j += 1) {
        if (!at(t, j, .name)) {
            if (at(t, j, .minus) or at(t, j, .colon)) return gap(cx, t[j].line, "variable list shorthand is not implemented", .{});
            return invalid(cx, t, j);
        }
        if (t[j].text.len > 0 and t[j].text[0] == '_' and oneOf(t[j].text, &.{ "_numeric_", "_character_", "_all_" })) return gap(cx, t[j].line, "variable list shorthand is not implemented", .{});
        const c = ds.indexOf(t[j].text) orelse return cx.diags.fail(error.ParseError, t[j].line, "Variable {s} not found.", .{t[j].text});
        if (std.mem.indexOfScalar(usize, cols.items, c) == null) try cols.append(cx.arena, c);
    }
    stop.* = j;
    return cols.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var total_name: ?[]const u8 = null;
    var total_line: usize = 0;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (name != null) return invalid(cx, t, i);
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if ((eq(word, "total") or eq(word, "n")) and at(t, i + 1, .eq)) {
            if (s.population != .none or total_name != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: only one of TOTAL= and RATE= may be specified", .{});
            if (at(t, i + 2, .name)) {
                total_name = t[i + 2].text;
                total_line = t[i].line;
                i += 3;
                if (at(t, i, .dot)) {
                    if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                    total_name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ total_name.?, t[i + 1].text });
                    i += 2;
                }
            } else {
                const x = try number(cx, t, i + 2);
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: TOTAL= must be positive", .{});
                s.population = .{ .total = x };
                i += 3;
            }
        } else if ((eq(word, "rate") or eq(word, "r")) and at(t, i + 1, .eq)) {
            if (s.population != .none or total_name != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: only one of TOTAL= and RATE= may be specified", .{});
            if (at(t, i + 2, .name)) return gap(cx, t[i].line, "RATE= data set is not implemented", .{});
            const x = try number(cx, t, i + 2);
            // Physical p.9916: a proportion in (0,1), or a percentage in
            // [1,100]; the value 1 means 100%.
            if (!(x > 0 and x <= 100)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: RATE= must be a positive proportion or percentage", .{});
            s.population = .{ .rate = if (x < 1) x else x / 100 };
            i += 3;
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            const x = try number(cx, t, i + 2);
            if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: ALPHA= must be between 0 and 1", .{});
            s.alpha = x;
            i += 3;
        } else if (eq(word, "missing")) {
            s.missing = true;
            i += 1;
        } else if (eq(word, "df") and at(t, i + 1, .eq)) {
            return gap(cx, t[i].line, "option DF= is not implemented", .{});
        } else if (oneOf(word, &statistic_keywords)) {
            return gap(cx, t[i].line, "statistic keyword {s} is not implemented", .{word});
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: input dataset not found", .{});
    if (total_name) |n| s.population = .{ .total_data = cx.lib.find(n) orelse return cx.diags.fail(error.ParseError, total_line, "PROC SURVEYMEANS: TOTAL= data set {s} not found", .{n}) };
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var var_seen = false;
    var vars: std.ArrayList(usize) = .empty;
    var classes: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        var stop: usize = end;
        if (kw(t, i, "var")) {
            const cols = try columns(cx, ds, t, i + 1, end, &stop);
            if (stop != end or cols.len == 0) return invalid(cx, t, stop);
            var_seen = true;
            for (cols) |c| if (std.mem.indexOfScalar(usize, vars.items, c) == null) try vars.append(cx.arena, c);
        } else if (kw(t, i, "class")) {
            const cols = try columns(cx, ds, t, i + 1, end, &stop);
            if (stop != end or cols.len == 0) return invalid(cx, t, stop);
            for (cols) |c| if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            const c = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYMEANS: WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.weight = c;
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            if (s.strata.len > 0) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            s.strata = try columns(cx, ds, t, i + 1, end, &stop);
            if (s.strata.len == 0) return invalid(cx, t, stop);
            if (stop != end) {
                var j = stop + 1;
                if (j == end) return invalid(cx, t, j);
                while (j < end) : (j += 1) {
                    if (kw(t, j, "list")) s.list = true else if (kw(t, j, "nocollapse")) return gap(cx, t[j].line, "STRATA option NOCOLLAPSE is not implemented", .{}) else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            if (s.clusters.len > 0) return gap(cx, t[i].line, "duplicate CLUSTER statement policy is not verified", .{});
            s.clusters = try columns(cx, ds, t, i + 1, end, &stop);
            if (stop != end or s.clusters.len == 0) return invalid(cx, t, stop);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const by_cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| by_cols[k] = ds.indexOf(n).?;
    s.by_cols = by_cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    for (classes.items) |c| if (ds.columns.items[c].type == .num and ds.columns.items[c].format != null) return gap(cx, 0, "formatted CLASS levels are not implemented", .{});
    s.classes = classes.items;
    if (!var_seen) {
        // Physical p.9933: without VAR, every numeric variable that has no
        // other role, plus the CLASS variables.
        for (ds.columns.items, 0..) |c, ci| {
            const role = (s.weight != null and s.weight.? == ci) or
                std.mem.indexOfScalar(usize, s.strata, ci) != null or
                std.mem.indexOfScalar(usize, s.clusters, ci) != null or
                std.mem.indexOfScalar(usize, s.by_cols, ci) != null;
            if (role) continue;
            if (c.type == .num or std.mem.indexOfScalar(usize, s.classes, ci) != null) try vars.append(cx.arena, ci);
        }
        if (vars.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: no analysis variables", .{});
    }
    s.vars = vars.items;
    return s;
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}
fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => proc.cmpValue(x, y) == .eq,
        .str => |text| y == .str and std.mem.eql(u8, std.mem.trimEnd(u8, text, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}

pub const Selected = struct {
    rows: []const []const Value,
    read: usize,
};

/// Observation selection, physical pp.9934-9935: a missing or nonpositive
/// WEIGHT value drops the observation; a missing STRATA or CLUSTER value
/// drops it unless MISSING is specified. Analysis-variable missing values do
/// not select here: they are handled per variable.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    var kept: std.ArrayList([]const Value) = .empty;
    outer: for (rows) |row| {
        if (s.weight) |w| if (!(row[w].num > 0)) continue;
        if (!s.missing) {
            for (s.strata) |c| if (isMissing(row[c])) continue :outer;
            for (s.clusters) |c| if (isMissing(row[c])) continue :outer;
        }
        try kept.append(a, row);
    }
    return .{ .rows = kept.items, .read = rows.len };
}

const KeyOrder = struct {
    rows: []const []const Value,
    strata: []const usize,
    clusters: []const usize,
    fn compare(self: KeyOrder, x: usize, y: usize, with_clusters: bool) std.math.Order {
        for (self.strata) |c| {
            const o = proc.cmpValue(self.rows[x][c], self.rows[y][c]);
            if (o != .eq) return o;
        }
        if (with_clusters) for (self.clusters) |c| {
            const o = proc.cmpValue(self.rows[x][c], self.rows[y][c]);
            if (o != .eq) return o;
        };
        return .eq;
    }
    fn less(self: KeyOrder, x: usize, y: usize) bool {
        return self.compare(x, y, true) == .lt;
    }
};

const Item = struct {
    col: usize,
    level: ?[]const u8,
    n: usize,
    /// Per-stratum counts for the Stratum Information table.
    stratum_n: []const usize,
    est: design.Estimate,
    lower: f64,
    upper: f64,
};

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn count(a: A, n: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{n});
}
/// Confidence-limit columns are 10 wide with one fixed number of decimals per
/// column, chosen so that the largest value fills the width.
fn limitDecimals(largest: f64) usize {
    var digits: usize = 1;
    var x = largest;
    while (x >= 10) : (x /= 10) digits += 1;
    return 9 - digits;
}
fn levelText(a: A, v: Value) ![]const u8 {
    return std.mem.trim(u8, try proc.cellText(a, v), " ");
}

/// One BY group (or the whole input): design, estimates, listing, ODS.
fn analyze(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value, rep: ?[]const Value) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const sel = try select(a, s, rows);
    // Execution boundary: how excluded observations are counted in the Data
    // Summary and enter the variance has no reference yet.
    if (sel.rows.len != sel.read) return gap(cx, 0, "the listing for input with observations excluded by missing or nonpositive WEIGHT, STRATA or CLUSTER values is not verified", .{});
    const n = sel.rows.len;
    if (n == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});
    for (s.vars) |c| for (sel.rows) |row| {
        if (isMissing(row[c])) return gap(cx, 0, "missing values of analysis variable {s} are not implemented", .{ds.columns.items[c].name});
    };

    // Strata ascending by unformatted value; sampling units inside strata.
    const order = try a.alloc(usize, n);
    for (order, 0..) |*o, k| o.* = k;
    const keys: KeyOrder = .{ .rows = sel.rows, .strata = s.strata, .clusters = s.clusters };
    std.mem.sort(usize, order, keys, KeyOrder.less);
    const stratum = try a.alloc(usize, n);
    const cluster = try a.alloc(usize, n);
    const weight = try a.alloc(f64, n);
    var stratum_rep: std.ArrayList(usize) = .empty;
    var n_clusters: usize = 0;
    for (order, 0..) |row_ix, k| {
        const new_stratum = k == 0 or keys.compare(order[k - 1], row_ix, false) != .eq;
        if (new_stratum) try stratum_rep.append(a, row_ix);
        if (s.clusters.len == 0 or new_stratum or keys.compare(order[k - 1], row_ix, true) != .eq) n_clusters += 1;
        stratum[row_ix] = stratum_rep.items.len - 1;
        cluster[row_ix] = n_clusters - 1;
        weight[row_ix] = if (s.weight) |w| sel.rows[row_ix][w].num else 1;
    }
    const n_strata = stratum_rep.items.len;
    const units = try a.alloc(usize, n_strata);
    const obs = try a.alloc(usize, n_strata);
    @memset(units, 0);
    @memset(obs, 0);
    {
        const seen = try a.alloc(bool, n_clusters);
        @memset(seen, false);
        for (stratum, cluster) |h, c| {
            obs[h] += 1;
            if (!seen[c]) {
                seen[c] = true;
                units[h] += 1;
            }
        }
    }
    for (units) |u| if (u < 2) return gap(cx, 0, "variance estimation with a single sampling unit in a stratum is not implemented", .{});

    // Finite population correction, physical p.9916: f_h = n_h / N_h.
    var totals: ?[]f64 = null;
    var rates: ?[]f64 = null;
    switch (s.population) {
        .none => {},
        .rate => |r| {
            rates = try a.alloc(f64, n_strata);
            @memset(rates.?, r);
        },
        .total => |x| {
            totals = try a.alloc(f64, n_strata);
            @memset(totals.?, x);
        },
        .total_data => |td| {
            const total_col = td.indexOf("_total_") orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: TOTAL= data set {s} has no _TOTAL_ variable", .{td.name});
            if (td.columns.items[total_col].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: _TOTAL_ must be numeric", .{});
            const match = try a.alloc(usize, s.strata.len);
            for (s.strata, match) |c, *m| {
                const nm = ds.columns.items[c].name;
                m.* = td.indexOf(nm) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: TOTAL= data set {s} has no stratum variable {s}", .{ td.name, nm });
            }
            totals = try a.alloc(f64, n_strata);
            for (stratum_rep.items, totals.?) |row_ix, *slot| {
                var found: ?f64 = null;
                for (td.rows.items) |trow| {
                    var same = true;
                    for (s.strata, match) |c, m| same = same and sameValue(sel.rows[row_ix][c], trow[m]);
                    if (same) {
                        found = trow[total_col].num;
                        break;
                    }
                }
                slot.* = found orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: the TOTAL= data set {s} has no total for a stratum of the input data", .{td.name});
            }
        },
    }
    if (totals) |list| {
        rates = try a.alloc(f64, n_strata);
        for (list, units, rates.?) |x, u, *r| {
            const sample: f64 = @floatFromInt(u);
            if (!(x >= sample)) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYMEANS: a population total is missing or less than the number of sampling units", .{});
            r.* = sample / x;
        }
    }
    const d: design.Design = .{ .stratum = stratum, .cluster = cluster, .weight = weight, .n_strata = n_strata, .n_clusters = n_clusters, .rate = rates };
    const df = d.df();
    if (!(df > 0)) return gap(cx, 0, "confidence limits without positive degrees of freedom are not implemented", .{});
    const tq = tQuantile(1 - s.alpha / 2, df);

    // Analysis items: one per numeric variable, one per level of a
    // categorical (character or CLASS) variable, levels ascending.
    var items: std.ArrayList(Item) = .empty;
    const ClassInfo = struct { col: usize, levels: []const []const u8 };
    var class_info: std.ArrayList(ClassInfo) = .empty;
    const y = try a.alloc(f64, n);
    var sum_weights: f64 = 0;
    for (weight) |w| sum_weights += w;
    for (s.vars) |c| {
        const categorical = ds.columns.items[c].type != .num or std.mem.indexOfScalar(usize, s.classes, c) != null;
        if (!categorical) {
            for (sel.rows, y) |row, *v| v.* = row[c].num;
            try items.append(a, .{ .col = c, .level = null, .n = n, .stratum_n = obs, .est = try design.taylorMean(a, d, y), .lower = 0, .upper = 0 });
            continue;
        }
        if (ds.columns.items[c].format != null) return gap(cx, 0, "formatted categorical levels are not implemented", .{});
        const by_value = try a.alloc(usize, n);
        for (by_value, 0..) |*o, k| o.* = k;
        const one: KeyOrder = .{ .rows = sel.rows, .strata = &.{c}, .clusters = &.{} };
        std.mem.sort(usize, by_value, one, KeyOrder.less);
        var names: std.ArrayList([]const u8) = .empty;
        var first: usize = 0;
        while (first < n) {
            var next = first + 1;
            while (next < n and one.compare(by_value[first], by_value[next], false) == .eq) next += 1;
            @memset(y, 0);
            const per = try a.alloc(usize, n_strata);
            @memset(per, 0);
            for (by_value[first..next]) |row_ix| {
                y[row_ix] = 1;
                per[stratum[row_ix]] += 1;
            }
            const text = try levelText(a, sel.rows[by_value[first]][c]);
            try names.append(a, text);
            try items.append(a, .{ .col = c, .level = text, .n = next - first, .stratum_n = per, .est = try design.taylorMean(a, d, y), .lower = 0, .upper = 0 });
            first = next;
        }
        try class_info.append(a, .{ .col = c, .levels = names.items });
    }
    var largest_lower: f64 = 0;
    var largest_upper: f64 = 0;
    for (items.items) |*it| {
        it.lower = it.est.mean - tq * it.est.stderr;
        it.upper = it.est.mean + tq * it.est.stderr;
        if (!std.math.isFinite(it.lower) or !std.math.isFinite(it.upper)) return gap(cx, 0, "non-finite estimates are not verified", .{});
        // ponytail: the 12.6 / 10-wide displays are verified for nonnegative
        // limits and moderate magnitudes only.
        if (it.lower < 0) return gap(cx, 0, "display of negative confidence limits is not verified", .{});
        if (@abs(it.est.mean) >= 1e5 or it.est.stderr >= 1e5 or it.upper >= 1e8) return gap(cx, 0, "display of estimates of this magnitude is not verified", .{});
        largest_lower = @max(largest_lower, it.lower);
        largest_upper = @max(largest_upper, it.upper);
    }
    const lower_dec = limitDecimals(largest_lower);
    const upper_dec = limitDecimals(largest_upper);
    const percent = 100 * (1 - s.alpha);
    if (@abs(percent - @round(percent)) > 1e-9) return gap(cx, 0, "confidence-level heading for a fractional percentage is not verified", .{});
    if (s.list) {
        if (totals == null) return gap(cx, 0, "STRATA / LIST without TOTAL= is not implemented", .{});
        if (s.strata.len != 1 or ds.columns.items[s.strata[0]].type != .num or ds.columns.items[s.strata[0]].format != null) return gap(cx, 0, "STRATA / LIST for other than one unformatted numeric stratum variable is not implemented", .{});
        if (s.clusters.len > 0) return gap(cx, 0, "STRATA / LIST with CLUSTER is not implemented", .{});
        for (totals.?) |x| if (x != @round(x)) return gap(cx, 0, "display of a fractional population total is not verified", .{});
    }

    var vw: usize = 8;
    var lw: usize = 5;
    for (items.items) |it| {
        vw = @max(vw, ds.columns.items[it.col].name.len);
        if (it.level) |text| lw = @max(lw, text.len);
    }
    const has_level = class_info.items.len > 0;

    var body: Out = .empty;
    try body.appendSlice(a, "\nThe SURVEYMEANS Procedure\n\n            Data Summary\n\n");
    if (s.strata.len > 0) {
        try left(a, &body, "Number of Strata", 22);
        try right(a, &body, try count(a, n_strata), 14);
        try body.append(a, '\n');
    }
    if (s.clusters.len > 0) {
        try left(a, &body, "Number of Clusters", 22);
        try right(a, &body, try count(a, n_clusters), 14);
        try body.append(a, '\n');
    }
    try left(a, &body, "Number of Observations", 22);
    try right(a, &body, try count(a, n), 14);
    try body.append(a, '\n');
    if (s.weight != null) {
        try left(a, &body, "Sum of Weights", 22);
        try right(a, &body, std.mem.trim(u8, try format.apply(a, .{ .num = sum_weights }, "BEST12."), " "), 14);
        try body.append(a, '\n');
    }
    if (has_level) {
        var widest: usize = 0;
        var cw: usize = 8;
        for (class_info.items) |ci| {
            var len: usize = 0;
            for (ci.levels) |text| len += text.len + 1;
            widest = @max(widest, len + 1);
            cw = @max(cw, ds.columns.items[ci.col].name.len);
        }
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Class Level Information", cw + 16 + widest);
        try body.appendSlice(a, " \n");
        try left(a, &body, "Variable", cw);
        try body.appendSlice(a, "      Levels    Values\n\n");
        for (class_info.items) |ci| {
            try left(a, &body, ds.columns.items[ci.col].name, cw);
            try right(a, &body, try count(a, ci.levels.len), 12);
            try body.appendSlice(a, "   ");
            for (ci.levels) |text| try body.print(a, " {s}", .{text});
            try body.appendSlice(a, "  \n");
        }
    }
    if (s.list) {
        const sc = s.strata[0];
        const item_width = vw + (if (has_level) 4 + lw else 0) + 12;
        const width = 59 + 4 + item_width;
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Stratum Information", width);
        try body.appendSlice(a, " \nStratum                         Pop.       Samp\n Index");
        try right(a, &body, ds.columns.items[sc].name, 14);
        try body.appendSlice(a, "           Total       Rate       N Obs    ");
        try left(a, &body, "Variable", vw);
        if (has_level) {
            try body.appendSlice(a, "    ");
            try left(a, &body, "Level", lw);
        }
        try right(a, &body, "N", 12);
        try body.append(a, '\n');
        try body.appendNTimes(a, '-', width);
        try body.append(a, '\n');
        for (stratum_rep.items, 0..) |row_ix, h| {
            var previous: ?usize = null;
            for (items.items, 0..) |it, k| {
                if (k == 0) {
                    try right(a, &body, try count(a, h + 1), 4);
                    try right(a, &body, try levelText(a, sel.rows[row_ix][sc]), 16);
                    try right(a, &body, try fixed(a, totals.?[h], 0), 16);
                    try right(a, &body, try std.fmt.allocPrint(a, "{d:.2}%", .{100 * rates.?[h]}), 11);
                    try right(a, &body, try count(a, obs[h]), 12);
                    try body.appendSlice(a, "    ");
                } else try body.appendNTimes(a, ' ', 63);
                try left(a, &body, if (previous == it.col) "" else ds.columns.items[it.col].name, vw);
                previous = it.col;
                if (has_level) {
                    try body.appendSlice(a, "    ");
                    try left(a, &body, it.level orelse "", lw);
                }
                try right(a, &body, try count(a, it.stratum_n[h]), 12);
                try body.append(a, '\n');
            }
        }
        try body.appendNTimes(a, '-', width);
        try body.append(a, '\n');
    }
    {
        const lead = vw + (if (has_level) 4 + lw else 0);
        const width = lead + 16 + 16 + 16 + 25;
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Statistics", width);
        try body.appendSlice(a, " \n");
        try right(a, &body, "Std Error", lead + 48);
        try body.append(a, '\n');
        try left(a, &body, "Variable", vw);
        if (has_level) {
            try body.appendSlice(a, "    ");
            try left(a, &body, "Level", lw);
        }
        try right(a, &body, "N", 16);
        try right(a, &body, "Mean", 16);
        try right(a, &body, "of Mean", 16);
        const heading = try std.fmt.allocPrint(a, "{d}% CL for Mean", .{@as(u64, @intFromFloat(@round(percent)))});
        try body.appendNTimes(a, ' ', 4 + (21 - @min(21, heading.len)) / 2);
        try body.appendSlice(a, heading);
        try body.append(a, '\n');
        try body.appendNTimes(a, '-', width);
        try body.append(a, '\n');
        var previous: ?usize = null;
        for (items.items) |it| {
            try left(a, &body, if (previous == it.col) "" else ds.columns.items[it.col].name, vw);
            previous = it.col;
            if (has_level) {
                try body.appendSlice(a, "    ");
                try left(a, &body, it.level orelse "", lw);
            }
            try right(a, &body, try count(a, it.n), 16);
            try right(a, &body, try fixed(a, it.est.mean, 6), 16);
            try right(a, &body, try fixed(a, it.est.stderr, 6), 16);
            try body.appendSlice(a, "    ");
            try right(a, &body, try fixed(a, it.lower, lower_dec), 10);
            try body.append(a, ' ');
            try right(a, &body, try fixed(a, it.upper, upper_dec), 10);
            try body.append(a, '\n');
        }
        try body.appendNTimes(a, '-', width);
        try body.append(a, '\n');
    }
    if (rep) |r| try by.appendLine(a, out, ds, r, s.by_cols);
    try out.appendSlice(a, body.items);

    if (cx.capture) |capture| if (capture.wants("Statistics")) {
        var table = try ods_table.Builder.init(a, ds, s.by_cols, rep);
        try table.char("VarName", vw);
        if (has_level) {
            // The reference PROC PRINT of this table breaks the heading into
            // Var / Level, which PRINT does only for a display format
            // narrower than the name: the level column carries $w. of the
            // longest level.
            var longest: usize = 1;
            for (items.items) |it| if (it.level) |text| {
                longest = @max(longest, text.len);
            };
            try table.char("VarLevel", longest);
            table.ds.setFormat("VarLevel", try std.fmt.allocPrint(a, "${d}.", .{longest}));
        }
        try table.num("N", "12.");
        try table.num("Mean", "12.6");
        try table.num("StdErr", "12.6");
        try table.num("LowerCLMean", try std.fmt.allocPrint(a, "10.{d}", .{lower_dec}));
        try table.num("UpperCLMean", try std.fmt.allocPrint(a, "10.{d}", .{upper_dec}));
        for (items.items) |it| {
            var cells: std.ArrayList(Value) = .empty;
            try cells.append(a, ods_table.s(ds.columns.items[it.col].name));
            if (has_level) try cells.append(a, ods_table.s(it.level orelse ""));
            for ([_]f64{ @floatFromInt(it.n), it.est.mean, it.est.stderr, it.lower, it.upper }) |x| try cells.append(a, ods_table.n(x));
            try table.row(cells.items);
        }
        try capture.publish(a, cx.diags, "Statistics", &table.ds);
    };
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const ds = s.input.ds;
    if (s.by_cols.len == 0) return analyze(cx, out, s, ds.rows.items, null);
    const groups = try by.checkedSlices(cx.arena, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    // Nothing is printed unless every BY group can be analysed.
    var body: Out = .empty;
    for (groups, 0..) |group, k| {
        if (k > 0) {
            try body.append(cx.arena, '\n');
            if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, &body);
        }
        try analyze(cx, &body, s, group.rows, group.rep.?);
    }
    try out.appendSlice(cx.arena, body.items);
    try cx.diags.note(0, "The BY statement provides completely separate analyses of the BY groups.  It does not provide a statistically valid subpopulation or domain analysis, where the total number of units in the subpopulation is not known with certainty. If you want a domain analysis, you should include the DOMAIN variables in a DOMAIN statement.", .{});
}

test {
    _ = design;
}

test "STAT-SURVEYMEANS-001 observation selection by WEIGHT, STRATA, CLUSTER and MISSING" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nan = std.math.nan(f64);
    // Columns: y, weight, stratum (character), cluster.
    const rows = [_][]const Value{
        &.{ .{ .num = 1 }, .{ .num = 2 }, .{ .str = "a" }, .{ .num = 1 } },
        &.{ .{ .num = 2 }, .{ .num = 0 }, .{ .str = "a" }, .{ .num = 1 } }, // zero weight
        &.{ .{ .num = 3 }, .{ .num = -1 }, .{ .str = "a" }, .{ .num = 2 } }, // negative weight
        &.{ .{ .num = 4 }, .{ .num = nan }, .{ .str = "b" }, .{ .num = 2 } }, // missing weight
        &.{ .{ .num = 5 }, .{ .num = 1 }, .{ .str = "  " }, .{ .num = 3 } }, // missing stratum
        &.{ .{ .num = 6 }, .{ .num = 1 }, .{ .str = "b" }, .{ .num = nan } }, // missing cluster
        &.{ .{ .num = nan }, .{ .num = 1 }, .{ .str = "b" }, .{ .num = 4 } }, // missing analysis value stays
    };
    var s: Spec = .{ .input = undefined, .vars = &.{0}, .weight = 1, .strata = &.{2}, .clusters = &.{3} };
    const strict = try select(a, s, &rows);
    try std.testing.expectEqual(@as(usize, 7), strict.read);
    try std.testing.expectEqual(@as(usize, 2), strict.rows.len);
    try std.testing.expectEqual(@as(f64, 1), strict.rows[0][0].num);
    try std.testing.expect(std.math.isNan(strict.rows[1][0].num));
    // MISSING keeps missing STRATA and CLUSTER levels, never a bad weight.
    s.missing = true;
    try std.testing.expectEqual(@as(usize, 4), (try select(a, s, &rows)).rows.len);
    // Without WEIGHT, STRATA and CLUSTER every observation is used.
    try std.testing.expectEqual(@as(usize, 7), (try select(a, .{ .input = undefined }, &rows)).rows.len);
}

test "STAT-SURVEYMEANS-001 confidence-limit columns fill ten characters" {
    try std.testing.expectEqual(@as(usize, 8), limitDecimals(7.04054539));
    try std.testing.expectEqual(@as(usize, 7), limitDecimals(10.4594546));
    try std.testing.expectEqual(@as(usize, 8), limitDecimals(0.7343101));
}
