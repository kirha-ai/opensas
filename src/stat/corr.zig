//! Pearson CORR: parsing, typed computation, and listing are separate entry points.
//! SAS 9.4 Statistical Procedures pp.8–23,34–36; oracle in docs/findings.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const parser = @import("../parser.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const io = @import("../io.zig");
const nan = std.math.nan(f64);
const eq = std.ascii.eqlIgnoreCase;

pub const VarDef = enum { df, n, wdf, weight };
pub const Options = struct {
    nomiss: bool = false,
    exclnpwgt: bool = false,
    vardef: VarDef = .df,
    noprint: bool = false,
    nosimple: bool = false,
    noprob: bool = false,
    nocorr: bool = false,
    cov: bool = false,
    csscp: bool = false,
    sscp: bool = false,
};
pub const Spec = struct {
    ds: *Dataset,
    vars: []const usize,
    with: []const usize,
    by: []const usize,
    by_desc: []const bool,
    notsorted: bool,
    freq: ?usize,
    weight: ?usize,
    options: Options,
};
pub const Simple = struct {
    column: usize,
    n: f64 = 0,
    sum_weights: f64 = 0,
    mean: f64 = nan,
    stddev: f64 = nan,
    sum: f64 = 0,
    minimum: f64 = nan,
    maximum: f64 = nan,
    css: f64 = 0,
};
pub const Pair = struct {
    row: usize,
    column: usize,
    n: f64 = 0,
    sum_weights: f64 = 0,
    mean_x: f64 = nan,
    mean_y: f64 = nan,
    css_x: f64 = 0,
    css_y: f64 = 0,
    cross: f64 = 0,
    sum_x: f64 = 0,
    sum_y: f64 = 0,
    uss_x: f64 = 0,
    uss_y: f64 = 0,
    sscp: f64 = 0,
    divisor: f64 = nan,
    covariance: f64 = nan,
    variance_x: f64 = nan,
    variance_y: f64 = nan,
    r: f64 = nan,
    p: f64 = nan,
};
pub const Group = struct {
    by_values: ?[]const Value,
    simple: []const Simple,
    /// Row-major: WITH (or VAR if absent) by VAR, with source column indices.
    pairs: []const Pair,
};
pub const Result = struct { spec: Spec, groups: []const Group };

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return i < t.len and parser.tkKw(t[i], name);
}
fn fail(cx: proc.ProcCtx, t: lex.Token) diag.Error {
    // Named valid constructs retain the interpreter's gap/typo distinction.
    inline for (.{ "out", "outp", "outh", "outk", "outs", "outplc", "outpls", "spearman", "kendall", "hoeffding", "polychoric", "polyserial", "partial", "id", "alpha", "cov", "csscp", "sscp", "fisher", "singular", "plots", "best", "rank" }) |s| {
        if (eq(t.text, s)) diag.markGap();
    }
    return cx.diags.fail(error.ParseError, t.line, "PROC CORR: unsupported option or statement {s}", .{t.text});
}
fn column(cx: proc.ProcCtx, ds: *Dataset, name: []const u8, numeric: bool) diag.Error!usize {
    const c = ds.indexOf(name) orelse return cx.diags.fail(error.ParseError, 0, "Variable {s} not found.", .{name});
    if (numeric and ds.columns.items[c].type != .num)
        return cx.diags.fail(error.ParseError, 0, "PROC CORR: variable {s} must be numeric.", .{name});
    return c;
}
fn contains(cols: []const usize, c: usize) bool {
    return std.mem.indexOfScalar(usize, cols, c) != null;
}
fn addColumn(a: std.mem.Allocator, cols: *std.ArrayList(usize), c: usize) !void {
    if (!contains(cols.items, c)) try cols.append(a, c);
}

fn numberedSuffix(name: []const u8) ?struct { prefix: []const u8, number: usize } {
    var i = name.len;
    while (i > 0 and std.ascii.isDigit(name[i - 1])) i -= 1;
    if (i == name.len) return null;
    return .{ .prefix = name[0..i], .number = std.fmt.parseInt(usize, name[i..], 10) catch return null };
}

/// Resolve SAS variable lists in source order, including numbered/name ranges,
/// prefixes, and _NUMERIC_. Explicit character variables fail visibly.
fn columns(cx: proc.ProcCtx, ds: *Dataset, toks: []const lex.Token) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (toks[i].tag != .name) return fail(cx, toks[i]);
        const name = toks[i].text;
        if (at(toks, i + 1, .colon) or eq(name, "_numeric_") or eq(name, "_all_")) {
            var matched = false;
            for (ds.columns.items, 0..) |c, j| {
                if (eq(name, "_numeric_") or eq(name, "_all_") or (c.name.len >= name.len and eq(c.name[0..name.len], name))) {
                    matched = true;
                    if (c.type == .num) try addColumn(cx.arena, &cols, j) else if (!eq(name, "_numeric_"))
                        return cx.diags.fail(error.ParseError, 0, "PROC CORR: variable {s} must be numeric.", .{c.name});
                }
            }
            if (!matched) return cx.diags.fail(error.ParseError, 0, "PROC CORR: variable list {s} matched no variables.", .{name});
            i += if (at(toks, i + 1, .colon)) @as(usize, 2) else 1;
        } else if (at(toks, i + 1, .minus) and at(toks, i + 2, .minus) and at(toks, i + 3, .name)) {
            const first = try column(cx, ds, name, true);
            const last = try column(cx, ds, toks[i + 3].text, true);
            if (last < first) return fail(cx, toks[i]);
            for (first..last + 1) |j| {
                _ = try column(cx, ds, ds.columns.items[j].name, true);
                try addColumn(cx.arena, &cols, j);
            }
            i += 4;
        } else if (at(toks, i + 1, .minus) and at(toks, i + 2, .name)) {
            const first = numberedSuffix(name);
            const last = numberedSuffix(toks[i + 2].text);
            if (first == null or last == null or !eq(first.?.prefix, last.?.prefix) or first.?.number > last.?.number)
                return cx.diags.fail(error.ParseError, toks[i].line, "PROC CORR: invalid numbered variable range.", .{});
            var names: std.ArrayList([]const u8) = .empty;
            try parser.expandRange(cx.arena, &names, name, toks[i + 2].text);
            for (names.items) |n| try addColumn(cx.arena, &cols, try column(cx, ds, n, true));
            i += 3;
        } else {
            try addColumn(cx.arena, &cols, try column(cx, ds, name, true));
            i += 1;
        }
    }
    return cols.items;
}

pub fn parse(cx: proc.ProcCtx, toks: []const lex.Token) diag.Error!Spec {
    var opts: Options = .{};
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (kw(toks, i, "data") and at(toks, i + 1, .eq) and at(toks, i + 2, .name)) {
            name = toks[i + 2].text;
            i += 3;
            if (at(toks, i, .lparen)) i = proc.skipParen(toks, i);
        } else if (kw(toks, i, "vardef") and at(toks, i + 1, .eq) and at(toks, i + 2, .name)) {
            const v = toks[i + 2].text;
            opts.vardef = if (eq(v, "df")) .df else if (eq(v, "n")) .n else if (eq(v, "wdf")) .wdf else if (eq(v, "weight") or eq(v, "wgt")) .weight else return fail(cx, toks[i + 2]);
            i += 3;
        } else {
            if (kw(toks, i, "nomiss")) opts.nomiss = true else if (kw(toks, i, "exclnpwgt") or kw(toks, i, "exclnpwgts")) opts.exclnpwgt = true else if (kw(toks, i, "noprint")) opts.noprint = true else if (kw(toks, i, "nosimple")) opts.nosimple = true else if (kw(toks, i, "noprob")) opts.noprob = true else if (kw(toks, i, "nocorr")) opts.nocorr = true else if (kw(toks, i, "cov")) opts.cov = true else if (kw(toks, i, "csscp")) opts.csscp = true else if (kw(toks, i, "sscp")) opts.sscp = true else if (!kw(toks, i, "pearson")) return fail(cx, toks[i]);
            i += 1;
        }
    }
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, 0, "File {s} does not exist.", .{name orelse "_last_"});
    const ds = try proc.procInput(cx.arena, raw, toks, cx.diags);
    var vars: ?[]const usize = null;
    var with: []const usize = &.{};
    var by_names: std.ArrayList([]const u8) = .empty;
    var freq: ?usize = null;
    var weight: ?usize = null;
    i += 1;
    while (i < toks.len and toks[i].tag != .eof) {
        if (toks[i].tag == .semicolon) {
            i += 1;
            continue;
        }
        const start = i;
        var end = i + 1;
        while (end < toks.len and toks[end].tag != .semicolon and toks[end].tag != .eof) end += 1;
        if (kw(toks, i, "var") or kw(toks, i, "with")) {
            const cs = try columns(cx, ds, toks[i + 1 .. end]);
            if (cs.len == 0) return cx.diags.fail(error.ParseError, toks[i].line, "PROC CORR: empty variable list.", .{});
            var combined: std.ArrayList(usize) = .empty;
            const old = if (kw(toks, i, "var")) vars orelse &.{} else with;
            for (old) |c| try addColumn(cx.arena, &combined, c);
            for (cs) |c| try addColumn(cx.arena, &combined, c);
            if (kw(toks, i, "var")) vars = combined.items else with = combined.items;
        } else if (kw(toks, i, "by")) {
            by_names.clearRetainingCapacity();
            try proc.parseProcBy(cx.arena, cx.diags, toks, &i, &by_names);
        } else if (kw(toks, i, "freq") or kw(toks, i, "weight")) {
            if (end != i + 2 or !at(toks, i + 1, .name)) return fail(cx, toks[i]);
            const c = try column(cx, ds, toks[i + 1].text, true);
            if (kw(toks, i, "freq")) freq = c else weight = c;
        } else if (!kw(toks, i, "where") and !kw(toks, i, "run") and !kw(toks, i, "quit") and !(toks[i].tag == .name and parser.isMidStepSkippable(toks[i].text))) return fail(cx, toks[start]);
        i = end;
    }
    const by = try proc.decodeProcBy(cx.arena, by_names.items);
    var bcols: std.ArrayList(usize) = .empty;
    for (by.names) |n| try bcols.append(cx.arena, try column(cx, ds, n, false));
    if (vars == null) {
        var cs: std.ArrayList(usize) = .empty;
        for (ds.columns.items, 0..) |c, j| {
            if (c.type == .num and !contains(with, j) and !contains(bcols.items, j) and freq != j and weight != j) try cs.append(cx.arena, j);
        }
        vars = cs.items;
    }
    if (vars.?.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: no analysis variables.", .{});
    return .{ .ds = ds, .vars = vars.?, .with = with, .by = bcols.items, .by_desc = by.desc, .notsorted = by.notsorted, .freq = freq, .weight = weight, .options = opts };
}

const Mass = struct { f: f64, w: f64 };
fn mass(s: Spec, row: []const Value) ?Mass {
    const f = if (s.freq) |c| @trunc(row[c].num) else 1;
    const w = if (s.weight) |c| row[c].num else 1;
    if (!std.math.isFinite(f) or f < 1 or !std.math.isFinite(w) or (s.options.exclnpwgt and w <= 0)) return null;
    if (s.options.nomiss) {
        for (s.vars) |c| if (row[c].isMissing()) return null;
        for (s.with) |c| if (row[c].isMissing()) return null;
    }
    return .{ .f = f, .w = @max(w, 0) * f };
}
fn divisor(v: VarDef, n: f64, w: f64) f64 {
    return switch (v) {
        .df => n - 1,
        .n => n,
        .wdf => w - 1,
        .weight => w,
    };
}

/// Weighted centered updates avoid cancellation for large offsets. Frequency
/// is a multiplicity, not an analytic weight: only it multiplies N and df.
pub fn computePair(s: Spec, rows: []const []const Value, xcol: usize, ycol: usize) Pair {
    var p: Pair = .{ .row = ycol, .column = xcol };
    var mx: f64 = 0;
    var my: f64 = 0;
    var origin_x: f64 = 0;
    var origin_y: f64 = 0;
    for (rows) |row| {
        const m = mass(s, row) orelse continue;
        if (row[xcol].isMissing() or row[ycol].isMissing()) continue;
        p.n += m.f;
        if (m.w == 0) continue;
        const raw_x = row[xcol].num;
        const raw_y = row[ycol].num;
        p.sum_x += m.w * raw_x;
        p.sum_y += m.w * raw_y;
        p.uss_x += m.w * raw_x * raw_x;
        p.uss_y += m.w * raw_y * raw_y;
        p.sscp += m.w * raw_x * raw_y;
        // Translate before updating means so small spreads around a large
        // offset do not lose precision at each weighted mean update.
        if (p.sum_weights == 0) {
            origin_x = raw_x;
            origin_y = raw_y;
        }
        const x = raw_x - origin_x;
        const y = raw_y - origin_y;
        const total = p.sum_weights + m.w;
        const dx = x - mx;
        const dy = y - my;
        const factor = (p.sum_weights / total) * m.w;
        p.css_x += factor * dx * dx;
        p.css_y += factor * dy * dy;
        p.cross += factor * dx * dy;
        mx += dx * (m.w / total);
        my += dy * (m.w / total);
        p.sum_weights = total;
    }
    if (p.sum_weights > 0) {
        p.mean_x = origin_x + mx;
        p.mean_y = origin_y + my;
    } else {
        p.css_x = nan;
        p.css_y = nan;
        p.cross = nan;
    }
    if (p.n == 0) {
        p.sum_x = nan;
        p.sum_y = nan;
        p.uss_x = nan;
        p.uss_y = nan;
        p.sscp = nan;
    }
    p.divisor = divisor(s.options.vardef, p.n, p.sum_weights);
    if (p.divisor > 0 and p.sum_weights > 0) {
        p.covariance = p.cross / p.divisor;
        p.variance_x = p.css_x / p.divisor;
        p.variance_y = p.css_y / p.divisor;
    }
    if (p.n >= 2 and p.css_x > 0 and p.css_y > 0) {
        p.r = if (xcol == ycol) 1 else std.math.clamp((p.cross / @sqrt(p.css_x)) / @sqrt(p.css_y), -1, 1);
        // Direct beta tail avoids 1-CDF cancellation for strong correlations.
        if (p.n > 2 and xcol != ycol) p.p = proc.betai((p.n - 2) / 2, 0.5, @max(0, (1 - @abs(p.r)) * (1 + @abs(p.r))));
    }
    return p;
}
fn computeSimple(s: Spec, rows: []const []const Value, c: usize) Simple {
    const p = computePair(s, rows, c, c);
    var v: Simple = .{ .column = c, .n = p.n, .sum_weights = p.sum_weights, .mean = p.mean_x, .css = p.css_x };
    for (rows) |row| {
        const m = mass(s, row) orelse continue;
        if (row[c].isMissing()) continue;
        const x = row[c].num;
        v.sum += m.w * x;
        v.minimum = if (std.math.isNan(v.minimum)) x else @min(v.minimum, x);
        v.maximum = if (std.math.isNan(v.maximum)) x else @max(v.maximum, x);
    }
    if (p.n == 0) v.sum = nan;
    const d = divisor(s.options.vardef, p.n, p.sum_weights);
    if (d > 0 and p.sum_weights > 0) v.stddev = @sqrt(@max(0, p.css_x) / d);
    return v;
}

pub fn compute(cx: proc.ProcCtx, s: Spec) diag.Error!Result {
    if (s.ds.rows.items.len == 0) {
        try cx.diags.report(.note, 0, "No observations were selected from data set {s}.", .{s.ds.name});
        return .{ .spec = s, .groups = &.{} };
    }
    const slices = try proc.bySlices(cx.arena, s.ds.rows.items, s.by);
    if (!s.notsorted) {
        for (slices, 0..) |bs, j| {
            if (j == 0) continue;
            if (proc.byOrderViolation(bs.rep.?, slices[j - 1].rep.?, s.by, s.by_desc, s.ds.sortseq_linguistic orelse io.global_sortseq_linguistic)) |k|
                return cx.diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ s.ds.name, if (s.by_desc[k]) @as([]const u8, "descending") else "ascending" });
        }
    }
    var groups: std.ArrayList(Group) = .empty;
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    for (slices) |bs| {
        var total_weight: f64 = 0;
        var total_freq: f64 = 0;
        var total_n: f64 = 0;
        for (bs.rows) |row| {
            const f = if (s.freq) |c| @trunc(row[c].num) else 1;
            if (std.math.isFinite(f) and f >= 1) {
                total_freq += f;
                const w = if (s.weight) |c| row[c].num else 1;
                if (std.math.isFinite(w)) total_weight += @max(0, w) * f;
            }
            if (mass(s, row)) |m| total_n += m.f;
        }
        if (s.freq != null and total_freq == 0)
            return cx.diags.fail(error.ParseError, 0, "Total frequency is 0 in the input data set.", .{});
        if (s.weight != null and total_weight == 0)
            return cx.diags.fail(error.ParseError, 0, "Total weight is 0 in the input data set.", .{});
        if (s.options.nomiss and total_n == 0)
            return cx.diags.fail(error.ParseError, 0, "The NOMISS option is specified, but all variables have at least one missing value for all observations in the input data set.", .{});
        if (total_n < 2) try cx.diags.warn(0, "Fewer than 2 observations in the input data set.", .{});
        var simple: std.ArrayList(Simple) = .empty;
        for (s.with) |c| try simple.append(cx.arena, computeSimple(s, bs.rows, c));
        for (s.vars) |c| if (!contains(s.with, c)) {
            try simple.append(cx.arena, computeSimple(s, bs.rows, c));
        };
        var pairs: std.ArrayList(Pair) = .empty;
        for (rowcols) |r| for (s.vars) |c| {
            try pairs.append(cx.arena, computePair(s, bs.rows, c, r));
        };
        try groups.append(cx.arena, .{ .by_values = bs.rep, .simple = simple.items, .pairs = pairs.items });
    }
    return .{ .spec = s, .groups = groups.items };
}

fn number(a: std.mem.Allocator, x: f64, probability: bool) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    if (probability) return if (x < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{x});
    return try std.fmt.allocPrint(a, "{d:.5}", .{x});
}
/// Text is deliberately downstream of Result: output datasets/ODS can consume
/// the full precision typed cells, never scrape this rounded listing.
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), result: Result) !void {
    const s = result.spec;
    if (s.options.noprint) return;
    for (result.groups) |g| {
        if (g.by_values) |row| try proc.appendByLine(a, out, s.ds, row, s.by);
        try out.appendSlice(a, "The CORR Procedure\n\n");
        if (s.with.len > 0) {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{d} With Variables:", .{s.with.len}));
            for (s.with) |c| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{s.ds.columns.items[c].name}));
            try out.append(a, '\n');
        }
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d} Variables:", .{s.vars.len}));
        for (s.vars) |c| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{s.ds.columns.items[c].name}));
        try out.append(a, '\n');
        if (s.freq) |c| try out.appendSlice(a, try std.fmt.allocPrint(a, "Freq Variable: {s}\n", .{s.ds.columns.items[c].name}));
        if (s.weight) |c| try out.appendSlice(a, try std.fmt.allocPrint(a, "Weight Variable: {s}\n", .{s.ds.columns.items[c].name}));
        inline for (.{ "sscp", "csscp", "cov" }) |kind| {
            if (@field(s.options, kind)) try renderMoments(a, out, s, g, kind);
        }
        if (!s.options.nosimple) {
            try out.appendSlice(a, "\nSimple Statistics\nVariable N Mean Std Dev Sum Minimum Maximum\n");
            for (g.simple) |v| {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d:.0}", .{ s.ds.columns.items[v.column].name, v.n }));
                for ([_]f64{ v.mean, v.stddev, v.sum, v.minimum, v.maximum }) |x| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, x, false)}));
                if (s.ds.columns.items[v.column].label) |label| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s}", .{label}));
                try out.append(a, '\n');
            }
        }
        if (!s.options.nocorr) {
            try out.appendSlice(a, "\nPearson Correlation Coefficients\n");
            if (!s.options.noprob) try out.appendSlice(a, "Prob > |r| under H0: Rho=0\n");
            try out.appendSlice(a, "Number of Observations\nVariable");
            for (s.vars) |c| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{s.ds.columns.items[c].name}));
            try out.append(a, '\n');
            const rowcols = if (s.with.len > 0) s.with else s.vars;
            for (rowcols, 0..) |c, j| {
                const ps = g.pairs[j * s.vars.len ..][0..s.vars.len];
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}", .{s.ds.columns.items[c].name}));
                for (ps) |p| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, p.r, false)}));
                if (!s.options.noprob) {
                    try out.appendSlice(a, "\nP");
                    for (ps) |p| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{if (p.row == p.column and p.n > 2 and !std.math.isNan(p.r)) "-" else try number(a, p.p, true)}));
                }
                try out.appendSlice(a, "\nN");
                for (ps) |p| try out.appendSlice(a, try std.fmt.allocPrint(a, " {d:.0}", .{p.n}));
                try out.append(a, '\n');
            }
        }
        try out.append(a, '\n');
    }
}
/// Each pair carries its own marginals: unlike a diagonal lookup, these
/// remain valid with unequal missingness and rectangular WITH/VAR matrices.
fn renderMoments(a: std.mem.Allocator, out: *std.ArrayList(u8), s: Spec, g: Group, comptime kind: []const u8) !void {
    const title = if (eq(kind, "cov")) "Covariance" else if (eq(kind, "csscp")) "Corrected Sums of Squares and Crossproducts" else "Sums of Squares and Crossproducts";
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\nRow Column {s} Divisor N\n", .{ title, if (eq(kind, "cov")) "Covariance RowVariance ColumnVariance" else "Crossproduct RowSS ColumnSS" }));
    for (g.pairs) |p| {
        const cross = if (eq(kind, "cov")) p.covariance else if (eq(kind, "csscp")) p.cross else p.sscp;
        const row_ss = if (eq(kind, "cov")) p.variance_y else if (eq(kind, "csscp")) p.css_y else p.uss_y;
        const col_ss = if (eq(kind, "cov")) p.variance_x else if (eq(kind, "csscp")) p.css_x else p.uss_x;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s} {s} {s} {s} {d:.0}\n", .{
            s.ds.columns.items[p.row].name, s.ds.columns.items[p.column].name,
            try number(a, cross, false),    try number(a, row_ss, false),
            try number(a, col_ss, false),   try number(a, p.divisor, false),
            p.n,
        }));
    }
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), toks: []const lex.Token) diag.Error!void {
    const s = try parse(cx, toks);
    try render(cx.arena, out, try compute(cx, s));
}

const Testing = struct {
    fn dataset(a: std.mem.Allocator, names: []const []const u8, data: []const []const f64) !*Dataset {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        for (names) |n| _ = try ds.addColumn(n, .num);
        for (data) |row| {
            const vs = try a.alloc(Value, row.len);
            for (row, 0..) |v, j| vs[j] = .{ .num = v };
            try ds.appendRow(vs);
        }
        return ds;
    }
    fn analyze(a: std.mem.Allocator, ds: *Dataset, source: []const u8) !Result {
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("d", ds);
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        return compute(cx, try parse(cx, try lex.tokenize(a, source, &d)));
    }
    fn near(expected: f64, actual: f64) !void {
        try std.testing.expectApproxEqAbs(expected, actual, 1e-10);
    }
    fn mixed(a: std.mem.Allocator) !*Dataset {
        return dataset(a, &.{ "x", "y", "z", "w", "f" }, &.{
            &.{ 1, 2, 7, 1, 1 },   &.{ 2, nan, 7, 2, 2.9 }, &.{ nan, 5, 7, 1, 1 },
            &.{ 4, 8, 7, 0, 3 },   &.{ 5, 3, 7, -2, 1 },    &.{ 6, 9, 7, nan, 1 },
            &.{ 7, 4, nan, 3, 2 }, &.{ 8, 11, 7, 2, 0 },    &.{ 9, 12, 7, 1, nan },
        });
    }
};
test "CORR SAS reference Pearson, p-value, descriptions and variable order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 2 }, &.{ 2, 5 }, &.{ 3, 5 }, &.{ 4, 9 }, &.{ 5, 8 }, &.{ 6, 13 }, &.{ 7, 12 }, &.{ 8, 17 } });
    const r = try Testing.analyze(a, ds, "proc corr data=d; var Y X; run;");
    const g = r.groups[0];
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, r.spec.vars);
    try Testing.near(0.96204126289224, g.pairs[1].r);
    try std.testing.expect(g.pairs[1].p > 0.00013 and g.pairs[1].p < 0.00014);
    try Testing.near(8, g.pairs[1].n);
    try Testing.near(8.875, g.simple[0].mean);
    try Testing.near(71, g.simple[0].sum);
    try Testing.near(@sqrt(6.0), g.simple[1].stddev);
    try Testing.near(1, g.simple[1].minimum);
    try Testing.near(8, g.simple[1].maximum);
}
test "CORR pairwise missing patterns and FREQ WEIGHT agree with SAS" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try Testing.analyze(a, try Testing.mixed(a), "proc corr; var y x z; weight w; freq f; run;");
    const g = r.groups[0];
    try Testing.near(8, g.simple[0].n);
    try Testing.near(31.0 / 8.0, g.simple[0].mean);
    try Testing.near(@sqrt(4.875 / 7.0), g.simple[0].stddev);
    try Testing.near(9, g.simple[1].n);
    try Testing.near(51.0 / 11.0, g.simple[1].mean);
    try Testing.near(8, g.simple[0].maximum); // zero weight affects extrema
    try Testing.near(7, g.pairs[1].n);
    try Testing.near(6, g.pairs[2].n);
    try Testing.near(1, g.pairs[1].r);
    try std.testing.expect(g.pairs[1].p < 1e-12);
    try std.testing.expect(std.math.isNan(g.pairs[8].r));
}
test "CORR NOMISS deletes across WITH and VAR; EXCLNPWGT changes N not means" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.mixed(a);
    const r = try Testing.analyze(a, ds, "proc corr nomiss; var y x; with z; weight w; freq f; run;");
    for (r.groups[0].simple) |v| try Testing.near(5, v.n);
    for (r.groups[0].pairs) |p| {
        try Testing.near(5, p.n);
        try std.testing.expect(std.math.isNan(p.r));
    }
    try Testing.near(2, r.groups[0].simple[1].mean);
    const e = try Testing.analyze(a, ds, "proc corr exclnpwgt; var x; with y z; weight w; freq f; run;");
    try Testing.near(4, e.groups[0].simple[0].n);
    try Testing.near(3.875, e.groups[0].simple[0].mean);
    try Testing.near(@sqrt(4.875 / 3.0), e.groups[0].simple[0].stddev);
    try Testing.near(5, e.groups[0].simple[0].maximum);
    try Testing.near(3, e.groups[0].pairs[0].n);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, e.spec.with);
}
test "CORR tiny samples, perfect negative correlation and constants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "g", "x", "y", "z" }, &.{ &.{ 1, 1, 2, 7 }, &.{ 2, 1, 2, 7 }, &.{ 2, 2, 4, 7 }, &.{ 3, 1, 6, 7 }, &.{ 3, 2, 4, 7 }, &.{ 3, 3, 2, 7 } });
    const r = try Testing.analyze(a, ds, "proc corr; by g; var x y z; run;");
    try std.testing.expectEqual(@as(usize, 3), r.groups.len);
    try std.testing.expect(std.math.isNan(r.groups[0].pairs[0].r));
    try std.testing.expect(std.math.isNan(r.groups[0].simple[0].stddev));
    try Testing.near(1, r.groups[1].pairs[1].r);
    try std.testing.expect(std.math.isNan(r.groups[1].pairs[1].p));
    try Testing.near(-1, r.groups[2].pairs[1].r);
    try std.testing.expect(r.groups[2].pairs[1].p < 1e-7);
    try std.testing.expect(std.math.isNan(r.groups[2].pairs[8].r));
}
test "CORR default variables exclude BY FREQ WEIGHT WITH; WHERE preserves source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.mixed(a);
    const r = try Testing.analyze(a, ds, "proc corr data=d(where=(x<6) obs=3); with y; freq f; weight w; where x>1; run;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, r.spec.vars);
    try Testing.near(6, r.groups[0].simple[1].n);
    try Testing.near(4, r.groups[0].pairs[0].n);
    try std.testing.expectEqual(@as(usize, 9), ds.rows.items.len);
}
test "CORR descending and NOTSORTED grouping with last BY winning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "g", "x", "y" }, &.{ &.{ 2, 1, 2 }, &.{ 2, 2, 4 }, &.{ 1, 3, 6 }, &.{ 1, 4, 8 } });
    const r = try Testing.analyze(a, ds, "proc corr; by x; by descending g; run;");
    try std.testing.expectEqual(@as(usize, 2), r.groups.len);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, r.spec.vars);
    const n = try Testing.analyze(a, ds, "proc corr; by g notsorted; var x y; run;");
    try Testing.near(1, n.groups[0].pairs[1].r);
}
test "CORR missing values, all zero weights, no observations and stable offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{ &.{ 1, 2, 0 }, &.{ 2, 3, -1 } });
    try std.testing.expectError(error.ParseError, Testing.analyze(a, ds, "proc corr; var x y; weight w; run;"));
    const e = try Testing.analyze(a, ds, "proc corr; var x y; where x>99; run;");
    try std.testing.expectEqual(@as(usize, 0), e.groups.len);
    const large = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1e12 + 1, 1e12 + 3 }, &.{ 1e12 + 2, 1e12 + 5 }, &.{ 1e12 + 3, 1e12 + 7 } });
    const l = try Testing.analyze(a, large, "proc corr; run;");
    try Testing.near(1, l.groups[0].pairs[1].r);
    try Testing.near(1, l.groups[0].simple[0].stddev);
}
test "CORR variable lists and variance divisors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x1", "x2", "w" }, &.{ &.{ 1, 2, 1 }, &.{ 3, 4, 2 }, &.{ 5, 8, 3 } });
    for ([_][]const u8{ "df", "n", "wdf", "weight", "wgt" }, [_]f64{ 2, 3, 5, 6, 6 }) |v, d| {
        const src = try std.fmt.allocPrint(a, "proc corr vardef={s}; var x1-x2; weight w; run;", .{v});
        const r = try Testing.analyze(a, ds, src);
        try Testing.near(@sqrt((40.0 / 3.0) / d), r.groups[0].simple[0].stddev);
        try std.testing.expectApproxEqAbs(@as(f64, 0.98287), r.groups[0].pairs[1].r, 0.000005);
        try std.testing.expectApproxEqAbs(@as(f64, 0.1180), r.groups[0].pairs[1].p, 0.00005);
    }
    for ([_][]const u8{ "var x:;", "var x1--x2;", "var x2 x1 x2;" }) |list| {
        const r = try Testing.analyze(a, ds, try std.fmt.allocPrint(a, "proc corr; {s} weight w; run;", .{list}));
        try std.testing.expectEqual(@as(usize, 2), r.spec.vars.len);
    }
}
test "CORR invalid inputs fail through captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "g", "x", "y" }, &.{ &.{ 2, 1, 2 }, &.{ 1, 2, 4 } });
    _ = try ds.addColumn("char", .char);
    // Invalid-column cases fail before reading rows; restore schema afterwards.
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ "proc corr; var absent; run;", "proc corr; weight char; run;", "proc corr; freq char; run;", "proc corr; with char; run;", "proc corr; by absent; run;", "proc corr typo; run;", "proc corr; var x-y; run;", "proc corr; var x; weight x y; run;" }) |src| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, src, &d)));
        try std.testing.expect(d.hasStepErrors());
    }
    ds.columns.items.len -= 1;
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc corr; by g; var x y; run;", &d));
    try std.testing.expectError(error.ParseError, compute(cx, s));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "not sorted") != null);
}

test "CORR no valid FREQ, no valid WEIGHT, and NOMISS empty sample are SAS errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f", "w" }, &.{ &.{ 1, nan, 0, nan }, &.{ nan, 3, nan, nan } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ "proc corr; var x y; freq f; run;", "proc corr; var x y; weight w; run;", "proc corr nomiss; var x y; run;" }, [_][]const u8{ "Total frequency", "Total weight", "NOMISS" }) |src, message| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const s = try parse(cx, try lex.tokenize(a, src, &d));
        try std.testing.expectError(error.ParseError, compute(cx, s));
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), message) != null);
    }
}
test "CORR zero-weight pairs and wholly missing variables preserve N and missing sum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "w", "z" }, &.{ &.{ 1, 2, 0, nan }, &.{ 2, 3, -1, nan }, &.{ nan, 5, 1, nan } });
    const r = try Testing.analyze(a, ds, "proc corr; var x y z; weight w; run;");
    try Testing.near(2, r.groups[0].simple[0].n);
    try Testing.near(0, r.groups[0].simple[0].sum);
    try std.testing.expect(std.math.isNan(r.groups[0].simple[0].stddev));
    try std.testing.expect(std.math.isNan(r.groups[0].simple[2].sum));
    try std.testing.expect(std.math.isNan(r.groups[0].pairs[1].r));
    try Testing.near(2, r.groups[0].pairs[1].n);
    try Testing.near(5, r.groups[0].simple[1].mean);
}

test "CORR repeated VAR WITH append and frequency changes Pearson significance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z", "f" }, &.{ &.{ 1, 2, 3, 2.9 }, &.{ 3, 4, 1, 1 }, &.{ 5, 8, 4, 3 } });
    const r = try Testing.analyze(a, ds, "proc corr; var x; var y; run;");
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, r.spec.vars);
    const w = try Testing.analyze(a, ds, "proc corr; var x; with y; with z; run;");
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, w.spec.with);
    try std.testing.expectApproxEqAbs(@as(f64, 0.7877), w.groups[0].pairs[1].p, 0.00005);
    const f = try Testing.analyze(a, ds, "proc corr; var x y; freq f; run;");
    try Testing.near(6, f.groups[0].pairs[1].n);
    try Testing.near(20.0 / 6.0, f.groups[0].simple[0].mean);
    try std.testing.expectApproxEqAbs(@as(f64, 0.99083), f.groups[0].pairs[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0001), f.groups[0].pairs[1].p, 0.00005);
}

test "CORR weighted COV CSSCP SSCP preserve pair-specific marginals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{ &.{ 1, 2, 1 }, &.{ 3, 4, 2 }, &.{ 5, 8, 3 } });
    const r = try Testing.analyze(a, ds, "proc corr cov csscp sscp; var x; with y; weight w; run;");
    const p = r.groups[0].pairs[0];
    try Testing.near(146, p.sscp);
    try Testing.near(94, p.uss_x);
    try Testing.near(228, p.uss_y);
    try Testing.near(64.0 / 3.0, p.cross);
    try Testing.near(40.0 / 3.0, p.css_x);
    try Testing.near(106.0 / 3.0, p.css_y);
    try Testing.near(32.0 / 3.0, p.covariance);
    const m = try Testing.analyze(a, try Testing.mixed(a), "proc corr cov csscp sscp; var x; with y; weight w; freq f; run;");
    const q = m.groups[0].pairs[0];
    try Testing.near(7, q.n);
    try Testing.near(43.0 / 7.0, q.mean_x);
    try Testing.near(26.0 / 7.0, q.mean_y);
    try Testing.near(170, q.sscp);
    try Testing.near(295, q.uss_x);
    try Testing.near(100, q.uss_y);
}
test "CORR translated weighted moments retain small spreads at large offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{ &.{ 1, 2, 1 }, &.{ 2, 5, 2 }, &.{ 3, 5, 1 }, &.{ 4, 9, 3 }, &.{ 5, 8, 1 }, &.{ 6, 13, 2 }, &.{ 7, 12, 1 }, &.{ 8, 17, 2 } });
    const shifted = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{});
    for (plain.rows.items) |row| try shifted.appendRow(&.{ .{ .num = 1e12 + row[0].num / 1024 }, .{ .num = 1e12 + row[1].num / 1024 }, row[2] });
    const p = (try Testing.analyze(a, plain, "proc corr; var x y; weight w; run;")).groups[0].pairs[1];
    const q = (try Testing.analyze(a, shifted, "proc corr; var x y; weight w; run;")).groups[0].pairs[1];
    try Testing.near(p.r, q.r);
    try Testing.near(p.p, q.p);
    try Testing.near(p.cross / 1048576, q.cross);
    try Testing.near(p.css_x / 1048576, q.css_x);
}
