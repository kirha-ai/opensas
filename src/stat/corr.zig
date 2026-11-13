//! CORR: parsing, typed computation, and listing are separate entry points.
//! SAS 9.4 Statistical Procedures pp.8–36; oracle in docs/findings.
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
const advanced = @import("corr_advanced.zig");

pub const VarDef = enum { df, n, wdf, weight };
pub const Options = struct {
    pearson: bool = false,
    spearman: bool = false,
    kendall: bool = false,
    hoeffding: bool = false,
    alpha: bool = false,
    polychoric: ?advanced.PolyOptions = null,
    polyserial: ?advanced.PolyOptions = null,
    fisher: ?advanced.FisherOptions = null,
    singular: f64 = 1e-8,
    singular_specified: bool = false,
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
    partial: []const usize = &.{},
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
    median: f64 = nan,
    partial_variance: f64 = nan,
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
    fisher: advanced.Fisher = .{},
    controls: usize = 0,
};
pub const Group = struct {
    by_values: ?[]const Value,
    simple: []const Simple,
    /// Row-major: WITH (or VAR if absent) by VAR, with source column indices.
    pairs: []const Pair,
    unpartial_pairs: []const Pair = &.{},
    spearman: []const Pair = &.{},
    kendall: []const Pair = &.{},
    hoeffding: []const Pair = &.{},
    alpha: ?advanced.Alpha = null,
    polychoric: []const PolyPair = &.{},
    polyserial: []const PolyPair = &.{},
};
pub const PolyPair = struct { row: usize, column: usize, estimate: advanced.Poly };
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
        } else if (kw(toks, i, "polychoric") or kw(toks, i, "polyserial")) {
            const serial = kw(toks, i, "polyserial");
            var opt: advanced.PolyOptions = .{};
            i += 1;
            if (at(toks, i, .lparen)) {
                i += 1;
                while (!at(toks, i, .rparen)) {
                    if (i >= toks.len or !at(toks, i + 1, .eq)) return fail(cx, toks[@min(i, toks.len - 1)]);
                    const key = toks[i];
                    i += 2;
                    if (eq(key.text, "ordinal") and serial) {
                        if (!kw(toks, i, "with") and !kw(toks, i, "var")) return fail(cx, toks[i]);
                        opt.ordinal_var = kw(toks, i, "var");
                        i += 1;
                    } else if (eq(key.text, "ngroups") and kw(toks, i, "all")) {
                        opt.ngroups = std.math.maxInt(usize);
                        i += 1;
                    } else {
                        const value = try numericOption(cx, toks, &i);
                        if (eq(key.text, "converge") and value > 0 and value < 1) opt.converge = value else if (eq(key.text, "maxiter") and value >= 1 and value < @as(f64, @floatFromInt(std.math.maxInt(usize))) and @trunc(value) == value) opt.maxiter = @intFromFloat(value) else if (eq(key.text, "ngroups") and value > 1 and value < @as(f64, @floatFromInt(std.math.maxInt(usize))) and @trunc(value) == value) opt.ngroups = @intFromFloat(value) else return fail(cx, key);
                    }
                }
                i += 1;
            }
            if (serial) opts.polyserial = opt else opts.polychoric = opt;
        } else if (kw(toks, i, "fisher")) {
            opts.fisher = .{};
            i += 1;
            if (at(toks, i, .lparen)) {
                i += 1;
                while (!at(toks, i, .rparen)) {
                    if (i >= toks.len or !at(toks, i + 1, .eq)) return fail(cx, toks[@min(i, toks.len - 1)]);
                    const key = toks[i];
                    i += 2;
                    if (eq(key.text, "biasadj")) {
                        if (!kw(toks, i, "yes") and !kw(toks, i, "no")) return fail(cx, toks[i]);
                        opts.fisher.?.biasadj = kw(toks, i, "yes");
                        i += 1;
                    } else if (eq(key.text, "type")) {
                        opts.fisher.?.kind = if (kw(toks, i, "lower")) .lower else if (kw(toks, i, "upper")) .upper else if (kw(toks, i, "twosided")) .twosided else return fail(cx, toks[i]);
                        i += 1;
                    } else {
                        const value = try numericOption(cx, toks, &i);
                        if (eq(key.text, "alpha") and value > 0 and value < 1) opts.fisher.?.alpha = value else if (eq(key.text, "rho0") and @abs(value) < 1) opts.fisher.?.rho0 = value else return fail(cx, key);
                    }
                }
                i += 1;
            }
        } else if (kw(toks, i, "singular") and at(toks, i + 1, .eq)) {
            i += 2;
            opts.singular = try numericOption(cx, toks, &i);
            opts.singular_specified = true;
            if (!(opts.singular >= 0 and opts.singular <= 1)) return fail(cx, toks[i - 1]);
        } else if (kw(toks, i, "vardef") and at(toks, i + 1, .eq) and at(toks, i + 2, .name)) {
            const v = toks[i + 2].text;
            opts.vardef = if (eq(v, "df")) .df else if (eq(v, "n")) .n else if (eq(v, "wdf")) .wdf else if (eq(v, "weight") or eq(v, "wgt")) .weight else return fail(cx, toks[i + 2]);
            i += 3;
        } else {
            if (kw(toks, i, "pearson")) opts.pearson = true else if (kw(toks, i, "spearman")) opts.spearman = true else if (kw(toks, i, "hoeffding")) opts.hoeffding = true else if (kw(toks, i, "kendall")) opts.kendall = true else if (kw(toks, i, "alpha")) opts.alpha = true else if (kw(toks, i, "nomiss")) opts.nomiss = true else if (kw(toks, i, "exclnpwgt") or kw(toks, i, "exclnpwgts")) opts.exclnpwgt = true else if (kw(toks, i, "noprint")) opts.noprint = true else if (kw(toks, i, "nosimple")) opts.nosimple = true else if (kw(toks, i, "noprob")) opts.noprob = true else if (kw(toks, i, "nocorr")) opts.nocorr = true else if (kw(toks, i, "cov")) opts.cov = true else if (kw(toks, i, "csscp")) opts.csscp = true else if (kw(toks, i, "sscp")) opts.sscp = true else if (!kw(toks, i, "pearson")) return fail(cx, toks[i]);
            i += 1;
        }
    }
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, 0, "File {s} does not exist.", .{name orelse "_last_"});
    const ds = try proc.procInput(cx.arena, raw, toks, cx.diags);
    var vars: ?[]const usize = null;
    var with: []const usize = &.{};
    var partial: []const usize = &.{};
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
        } else if (kw(toks, i, "partial")) {
            partial = try columns(cx, ds, toks[i + 1 .. end]);
            if (partial.len == 0) return fail(cx, toks[i]);
            opts.nomiss = true;
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
            if (c.type == .num and !contains(with, j) and !contains(partial, j) and !contains(bcols.items, j) and freq != j and weight != j) try cs.append(cx.arena, j);
        }
        vars = cs.items;
    }
    if (vars.?.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: no analysis variables.", .{});
    for (vars.?) |c| if (contains(partial, c)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: analysis variables cannot also be PARTIAL variables.", .{});
    for (with) |c| if (contains(partial, c)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: WITH variables cannot also be PARTIAL variables.", .{});
    if (weight != null and (opts.spearman or opts.kendall or opts.hoeffding or opts.polychoric != null or opts.polyserial != null)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: rank correlations are invalid with WEIGHT.", .{});
    if (partial.len > 0 and (opts.polychoric != null or opts.polyserial != null or opts.hoeffding)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: ordinal correlations with PARTIAL are unsupported.", .{});
    if (opts.polyserial != null and with.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: POLYSERIAL requires WITH.", .{});
    if (opts.alpha and with.len > 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: ALPHA is invalid with WITH.", .{});
    if (opts.singular_specified and partial.len == 0)
        try cx.diags.warn(0, "SINGULAR= option is allowed only when a PARTIAL statement is also specified.", .{});
    if (opts.alpha or opts.cov or opts.csscp or opts.sscp or (!opts.spearman and !opts.kendall and !opts.hoeffding and opts.polychoric == null and opts.polyserial == null)) opts.pearson = true;
    return .{ .partial = partial, .ds = ds, .vars = vars.?, .with = with, .by = bcols.items, .by_desc = by.desc, .notsorted = by.notsorted, .freq = freq, .weight = weight, .options = opts };
}

const Mass = struct { f: f64, w: f64 };
fn mass(s: Spec, row: []const Value) ?Mass {
    const f = if (s.freq) |c| @trunc(row[c].num) else 1;
    const w = if (s.weight) |c| row[c].num else 1;
    if (!std.math.isFinite(f) or f < 1 or !std.math.isFinite(w) or (s.options.exclnpwgt and w <= 0)) return null;
    if (s.options.nomiss) {
        for (s.vars) |c| if (row[c].isMissing()) return null;
        for (s.with) |c| if (row[c].isMissing()) return null;
        for (s.partial) |c| if (row[c].isMissing()) return null;
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
        // A bad BY group must not discard earlier results or prevent later
        // analyses (Statistical Procedures, CORR BY statement, p.16). Keep
        // ordinary step errors armed: continuation is local to this PROC.
        if (s.freq != null and total_freq == 0) {
            try cx.diags.report(.err, 0, "Total frequency is 0 in the input data set.", .{});
            if (s.by.len == 0) return error.ParseError;
            continue;
        }
        if (s.weight != null and total_weight == 0) {
            try cx.diags.report(.err, 0, "Total weight is 0 in the input data set.", .{});
            if (s.by.len == 0) return error.ParseError;
            continue;
        }
        if (s.options.nomiss and total_n == 0) {
            try cx.diags.report(.err, 0, "The NOMISS option is specified, but all variables have at least one missing value for all observations in the input data set.", .{});
            if (s.by.len == 0) return error.ParseError;
            continue;
        }
        if (total_n < 2) try cx.diags.warn(0, "Fewer than 2 observations in the input data set.", .{});
        var simple: std.ArrayList(Simple) = .empty;
        for (s.partial) |c| try simple.append(cx.arena, computeSimple(s, bs.rows, c));
        for (s.with) |c| try simple.append(cx.arena, computeSimple(s, bs.rows, c));
        for (s.vars) |c| if (!contains(s.with, c)) {
            try simple.append(cx.arena, computeSimple(s, bs.rows, c));
        };
        var pairs: std.ArrayList(Pair) = .empty;
        for (rowcols) |r| for (s.vars) |c| {
            try pairs.append(cx.arena, computePair(s, bs.rows, c, r));
        };
        const unpartial_pairs = if (s.partial.len > 0) try cx.arena.dupe(Pair, pairs.items) else &.{};
        if (s.partial.len > 0) try partialPairs(cx.arena, s, bs.rows, pairs.items, .pearson);
        for (simple.items) |*v| {
            if (s.options.spearman or s.options.kendall or s.options.hoeffding or s.options.polychoric != null or s.options.polyserial != null) v.median = try median(cx.arena, s, bs.rows, v.column);
            if (s.partial.len > 0) for (pairs.items) |p| {
                if (p.column == v.column) {
                    v.partial_variance = p.variance_x;
                    break;
                }
            };
        }
        const polychoric = if (s.options.polychoric) |opt| try polyPairs(cx, s, bs.rows, opt, false) else &.{};
        const polyserial = if (s.options.polyserial) |opt| try polyPairs(cx, s, bs.rows, opt, true) else &.{};
        const spearman: []Pair = if (s.options.spearman) try rankPairs(cx.arena, s, bs.rows, .spearman) else &.{};
        const hoeffding: []Pair = if (s.options.hoeffding) try rankPairs(cx.arena, s, bs.rows, .hoeffding) else &.{};
        const kendall: []Pair = if (s.options.kendall) try rankPairs(cx.arena, s, bs.rows, .kendall) else &.{};
        if (s.options.fisher) |f| {
            for (pairs.items) |*p| p.fisher = advanced.fisher(p.r, p.n, p.controls, false, f);
            for (spearman) |*p| p.fisher = advanced.fisher(p.r, p.n, p.controls, true, f);
        }
        var reliability: ?advanced.Alpha = null;
        if (s.options.alpha and s.vars.len < 2) try cx.diags.warn(0, "PROC CORR: ALPHA requires at least two variables.", .{});
        if (s.options.alpha and s.vars.len >= 2) {
            const covs = try cx.arena.alloc(f64, pairs.items.len);
            for (pairs.items, covs) |p, *c| c.* = p.covariance;
            const correlations = try cx.arena.alloc(f64, pairs.items.len);
            for (pairs.items, correlations) |p, *c| c.* = p.r;
            reliability = try advanced.alpha(cx.arena, covs, correlations, s.vars.len);
            if (!s.options.nomiss) {
                for (bs.rows) |row| {
                    var missing = false;
                    for (s.vars) |c| missing = missing or row[c].isMissing();
                    if (missing) {
                        try cx.diags.warn(0, "PROC CORR: use NOMISS with ALPHA when observations have missing values.", .{});
                        break;
                    }
                }
            }
        }
        try groups.append(cx.arena, .{ .by_values = bs.rep, .simple = simple.items, .pairs = pairs.items, .unpartial_pairs = unpartial_pairs, .spearman = spearman, .kendall = kendall, .hoeffding = hoeffding, .alpha = reliability, .polychoric = polychoric, .polyserial = polyserial });
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
            if (@field(s.options, kind)) {
                if (eq(kind, "csscp") and g.unpartial_pairs.len > 0) {
                    var original = g;
                    original.pairs = g.unpartial_pairs;
                    try out.appendSlice(a, "\nUnpartial");
                    try renderMoments(a, out, s, original, kind);
                    try out.appendSlice(a, "\nPartial");
                }
                try renderMoments(a, out, s, g, kind);
            }
        }
        if (!s.options.nosimple) {
            try out.appendSlice(a, if (s.options.spearman or s.options.kendall or s.options.hoeffding or s.options.polychoric != null or s.options.polyserial != null) "\nSimple Statistics\nVariable N Mean Std Dev Median Minimum Maximum\n" else "\nSimple Statistics\nVariable N Mean Std Dev Sum Minimum Maximum\n");
            for (g.simple) |v| {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d:.0}", .{ s.ds.columns.items[v.column].name, v.n }));
                for ([_]f64{ v.mean, v.stddev, if (s.options.spearman or s.options.kendall or s.options.hoeffding or s.options.polychoric != null or s.options.polyserial != null) v.median else v.sum, v.minimum, v.maximum }) |x| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, x, false)}));
                if (s.ds.columns.items[v.column].label) |label| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s}", .{label}));
                try out.append(a, '\n');
            }
        }
        if (s.partial.len > 0 and s.options.pearson and !s.options.nosimple) {
            try out.appendSlice(a, "\nPartial Statistics\nVariable Variance Std Dev\n");
            for (g.simple) |v| {
                if (contains(s.partial, v.column)) continue;
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s}\n", .{ s.ds.columns.items[v.column].name, try number(a, v.partial_variance, false), try number(a, @sqrt(v.partial_variance), false) }));
            }
        }
        if (!s.options.nocorr and s.options.pearson) {
            try out.appendSlice(a, if (s.partial.len > 0) "\nPearson Partial Correlation Coefficients\n" else "\nPearson Correlation Coefficients\n");
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
        try renderAdvanced(a, out, s, g);
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
    const result = try compute(cx, s);
    if (cx.capture) |capture| try @import("ods_corr.zig").publish(cx.arena, cx.diags, capture, result);
    try render(cx.arena, out, result);
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

test "BUG-corrbygroupabort retains valid groups before and after group errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // SAS oracle: each bad-first/middle/last FREQ, WEIGHT and NOMISS case
    // reports one ERROR and both other groups have N=3, r=.96077, p=.1789.
    // Evidence: /tmp/opensas-review-fixes/BUG-corrbygroupabort/{freq,weight,nomiss}_{1,2,3}.*
    const sources = [_][]const u8{
        "proc corr; by g; var x y; freq f; run;",
        "proc corr; by g; var x y; weight f; run;",
        "proc corr nomiss; by g; var x y; run;",
    };
    for (sources, [_][]const u8{ "Total frequency", "Total weight", "NOMISS" }, 0..) |source, message, kind| {
        // The fourth case makes every group invalid; it must retain all errors.
        for (0..4) |bad| {
            const ds = try Testing.dataset(a, &.{ "g", "x", "y", "f" }, &.{});
            for (0..3) |g| {
                const invalid = bad == g or bad == 3;
                for ([_]f64{ 3, 4, 5 }, [_]f64{ 5, 8, 9 }) |x, y| {
                    try ds.appendRow(&.{
                        .{ .num = @floatFromInt(g + 1) },                  .{ .num = x },
                        .{ .num = if (invalid and kind == 2) nan else y }, .{ .num = if (invalid) 0 else 1 },
                    });
                }
            }
            var lib = @import("../exec.zig").Library.init(a);
            try lib.put("d", ds);
            var d = diag.Diagnostics.init(a);
            const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
            const result = try compute(cx, try parse(cx, try lex.tokenize(a, source, &d)));
            try std.testing.expectEqual(@as(usize, if (bad == 3) 0 else 2), result.groups.len);
            try std.testing.expectEqual(@as(usize, if (bad == 3) 3 else 1), d.count());
            try std.testing.expect(d.hasStepErrors() and d.syntax_check);
            try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, d.hasErrors()));
            for (d.list.items) |diagnostic| {
                try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, message) != null);
            }
            var previous: f64 = 0;
            for (result.groups) |g| {
                const key = g.by_values.?[0].num;
                try std.testing.expect(key > previous and key != @as(f64, @floatFromInt(bad + 1)));
                previous = key;
                try Testing.near(3, g.pairs[1].n);
                try std.testing.expectApproxEqAbs(@as(f64, 0.96077), g.pairs[1].r, 0.000005);
                try std.testing.expectApproxEqAbs(@as(f64, 0.1789), g.pairs[1].p, 0.00005);
            }
        }
    }
}

fn numericOption(cx: proc.ProcCtx, toks: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(toks, i.*, .minus) or at(toks, i.*, .plus)) {
        if (at(toks, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(toks, i.*, .number)) return fail(cx, toks[@min(i.*, toks.len - 1)]);
    const v = std.fmt.parseFloat(f64, toks[i.*].text) catch return fail(cx, toks[i.*]);
    i.* += 1;
    return sign * v;
}
fn rankPair(a: std.mem.Allocator, s: Spec, rows: []const []const Value, x: usize, y: usize, method: advanced.Method) !Pair {
    var data: std.ArrayList(advanced.Observation) = .empty;
    defer data.deinit(a);
    for (rows) |row| {
        const m = mass(s, row) orelse continue;
        if (row[x].isMissing() or row[y].isMissing()) continue;
        try data.append(a, .{ .x = row[x].num, .y = row[y].num, .f = m.f });
    }
    const e = try advanced.rank(a, data.items, method);
    return .{ .row = y, .column = x, .n = e.n, .r = e.r, .p = if (x == y and method != .hoeffding) nan else e.p };
}
fn rankPairs(a: std.mem.Allocator, s: Spec, rows: []const []const Value, method: advanced.Method) ![]Pair {
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    const pairs = try a.alloc(Pair, rowcols.len * s.vars.len);
    for (rowcols, 0..) |r, i| for (s.vars, 0..) |c, j| {
        pairs[i * s.vars.len + j] = try rankPair(a, s, rows, c, r, method);
    };
    if (s.partial.len > 0) try partialPairs(a, s, rows, pairs, method);
    return pairs;
}
/// Sequential symmetric Schur complements, with singularity judged against
/// each original diagonal. Redundant controls do not consume residual df.
fn partialPairs(a: std.mem.Allocator, s: Spec, rows: []const []const Value, pairs: []Pair, method: advanced.Method) !void {
    var cols: std.ArrayList(usize) = .empty;
    defer cols.deinit(a);
    for (s.partial) |c| try addColumn(a, &cols, c);
    const k = cols.items.len;
    for (s.vars) |c| try addColumn(a, &cols, c);
    for (s.with) |c| try addColumn(a, &cols, c);
    const n = cols.items.len;
    const matrix = try a.alloc(f64, n * n);
    defer a.free(matrix);
    const original = try a.alloc(f64, n);
    defer a.free(original);
    for (cols.items, 0..) |x, i| for (cols.items, 0..) |y, j| {
        const p = if (method == .pearson) computePair(s, rows, x, y) else try rankPair(a, s, rows, x, y, method);
        matrix[i * n + j] = if (method == .pearson) p.cross else p.r;
    };
    for (0..n) |i| original[i] = matrix[i * n + i];
    var used: usize = 0;
    for (0..k) |c| {
        const pivot = matrix[c * n + c];
        if (!(pivot > 0) or pivot < s.options.singular * original[c]) continue;
        used += 1;
        for (c + 1..n) |i| for (c + 1..n) |j| {
            matrix[i * n + j] -= matrix[i * n + c] * matrix[c * n + j] / pivot;
        };
    }
    for (k..n) |i| {
        if (!(matrix[i * n + i] > 0) or matrix[i * n + i] < s.options.singular * original[i]) {
            for (0..n) |j| {
                matrix[i * n + j] = 0;
                matrix[j * n + i] = 0;
            }
        }
    }
    for (pairs) |*p| {
        const i = std.mem.indexOfScalar(usize, cols.items, p.column).?;
        const j = std.mem.indexOfScalar(usize, cols.items, p.row).?;
        const xx = matrix[i * n + i];
        const yy = matrix[j * n + j];
        const xy = matrix[i * n + j];
        p.controls = used;
        p.r = nan;
        p.p = nan;
        if (i >= k and j >= k and xx > 0 and yy > 0 and xx >= s.options.singular * original[i] and yy >= s.options.singular * original[j]) {
            p.r = std.math.clamp(xy / @sqrt(xx * yy), -1, 1);
            if (i != j and method != .kendall) p.p = advanced.probability(p.r, p.n - @as(f64, @floatFromInt(used)) - 2);
        }
        if (method == .pearson) {
            p.cross = xy;
            p.css_x = xx;
            p.css_y = yy;
            p.divisor = divisor(s.options.vardef, p.n, p.sum_weights) - (if (s.options.vardef == .df or s.options.vardef == .wdf) @as(f64, @floatFromInt(used)) else 0);
            p.covariance = if (p.divisor > 0) xy / p.divisor else nan;
            p.variance_x = if (p.divisor > 0) xx / p.divisor else nan;
            p.variance_y = if (p.divisor > 0) yy / p.divisor else nan;
        }
    }
}
fn renderAdvanced(a: std.mem.Allocator, out: *std.ArrayList(u8), s: Spec, g: Group) !void {
    inline for (.{ "spearman", "kendall", "hoeffding" }) |name| {
        const pairs = @field(g, name);
        if (pairs.len > 0) {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}{s} Correlation Coefficients\nRow Column Correlation", .{ name, if (s.partial.len > 0) @as([]const u8, " Partial") else "" }));
            if (!s.options.noprob and !(eq(name, "kendall") and s.partial.len > 0)) try out.appendSlice(a, " P");
            try out.appendSlice(a, " N\n");
            for (pairs) |p| {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s}", .{ s.ds.columns.items[p.row].name, s.ds.columns.items[p.column].name, try number(a, p.r, false) }));
                if (!s.options.noprob and !(eq(name, "kendall") and s.partial.len > 0)) try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, p.p, true)}));
                try out.appendSlice(a, try std.fmt.allocPrint(a, " {d:.0}\n", .{p.n}));
            }
        }
    }
    inline for (.{ "polychoric", "polyserial" }) |kind| {
        const estimates = @field(g, kind);
        if (estimates.len > 0) {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s} Correlations\n{s}", .{ kind, if (s.options.noprob) @as([]const u8, "Row Column N Correlation StdError WaldChiSquare LRChiSquare\n") else "Row Column N Correlation StdError WaldChiSquare WaldP LRChiSquare LRP\n" }));
            for (estimates) |entry| {
                const e = entry.estimate;
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {d:.0}", .{ s.ds.columns.items[entry.row].name, s.ds.columns.items[entry.column].name, e.n }));
                for ([_]f64{ e.r, e.se, e.wald, e.p, e.lr, e.lr_p }, 0..) |v, i| {
                    if (s.options.noprob and (i == 3 or i == 5)) continue;
                    try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, v, i == 3 or i == 5)}));
                }
                try out.append(a, '\n');
            }
        }
    }
    if (g.alpha) |alpha_result| {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nCronbach Coefficient Alpha\nRaw {s}\nStandardized {s}\nDeleted Variable RawCorrelation RawAlpha StandardizedCorrelation StandardizedAlpha\n", .{ try number(a, alpha_result.raw, false), try number(a, alpha_result.standardized, false) }));
        for (alpha_result.deleted, s.vars) |d, c| try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s} {s} {s}\n", .{ s.ds.columns.items[c].name, try number(a, d.raw_correlation, false), try number(a, d.raw, false), try number(a, d.standardized_correlation, false), try number(a, d.standardized, false) }));
    }
    if (s.options.fisher != null) {
        for ([_][]const Pair{ if (s.options.pearson) g.pairs else &.{}, g.spearman }, [_][]const u8{ "Pearson", "Spearman" }) |pairs, title| {
            if (pairs.len == 0) continue;
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s} Fisher Correlation Statistics\nRow Column N Z Bias Estimate Lower Upper", .{title}));
            if (!s.options.noprob) try out.appendSlice(a, " P");
            try out.append(a, '\n');
            for (pairs) |p| {
                if (p.row == p.column or (s.with.len == 0 and p.row < p.column)) continue;
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {d:.0}", .{ s.ds.columns.items[p.row].name, s.ds.columns.items[p.column].name, p.n }));
                for ([_]f64{ p.fisher.z, p.fisher.bias, p.fisher.estimate, p.fisher.lower, p.fisher.upper }) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, v, false)}));
                if (!s.options.noprob) try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, p.fisher.p, true)}));
                try out.append(a, '\n');
            }
        }
    }
}

test "CORR advanced SAS tied ranks partial Fisher and alpha reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z", "f" }, &.{ &.{ 1, 2, 1, 2 }, &.{ 2, 5, 3, 1 }, &.{ 3, 5, 2, 1 }, &.{ 4, 9, 4, 1 }, &.{ 5, 8, 3, 2 }, &.{ 6, 13, 5, 1 }, &.{ 7, 12, 4, 1 }, &.{ 8, 17, 6, 1 } });
    const r = try Testing.analyze(a, ds, "proc corr pearson spearman kendall fisher alpha; var x y z; run;");
    const g = r.groups[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.94612), g.spearman[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.83650), g.kendall[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0041), g.kendall[1].p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.869050), g.alpha.?.raw, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.976693), g.alpha.?.standardized, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.946398), g.alpha.?.deleted[0].raw_correlation, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.772856), g.pairs[1].fisher.lower, 0.0000005);
    const p = (try Testing.analyze(a, ds, "proc corr pearson spearman kendall fisher; var x y; partial z; run;")).groups[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.93350), p.pairs[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.91539), p.spearman[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.61666), p.kendall[1].r, 0.000005);
    try std.testing.expect(std.math.isNan(p.kendall[1].p));
    try std.testing.expectApproxEqAbs(@as(f64, 0.556118), p.pairs[1].fisher.lower, 0.0000005);
    const divisor_n = (try Testing.analyze(a, ds, "proc corr vardef=n; var x y; partial z; run;")).groups[0].pairs[0];
    try Testing.near(8, divisor_n.divisor);
    try Testing.near(1.25, divisor_n.variance_x);
    const f = (try Testing.analyze(a, ds, "proc corr pearson spearman fisher(type=lower rho0=.5 alpha=.1 biasadj=no); var x; with y; freq f; run;")).groups[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.903710), f.pairs[0].fisher.lower, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.867847), f.spearman[0].fisher.lower, 0.0000005);
}

fn median(a: std.mem.Allocator, s: Spec, rows: []const []const Value, col: usize) !f64 {
    var values: std.ArrayList(advanced.Observation) = .empty;
    defer values.deinit(a);
    var n: f64 = 0;
    for (rows) |row| {
        const m = mass(s, row) orelse continue;
        if (row[col].isMissing()) continue;
        n += m.f;
        try values.append(a, .{ .x = row[col].num, .y = 0, .f = m.f });
    }
    if (n == 0) return nan;
    const Less = struct {
        fn less(_: void, x: advanced.Observation, y: advanced.Observation) bool {
            return x.x < y.x;
        }
    };
    std.mem.sort(advanced.Observation, values.items, {}, Less.less);
    var cumulative: f64 = 0;
    var low: f64 = nan;
    for (values.items) |v| {
        cumulative += v.f;
        if (std.math.isNan(low) and cumulative >= @floor((n + 1) / 2)) low = v.x;
        if (cumulative >= @floor(n / 2) + 1) return (low + v.x) / 2;
    }
    return nan;
}
fn polyPairs(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, opt: advanced.PolyOptions, serial: bool) ![]const PolyPair {
    var results: std.ArrayList(PolyPair) = .empty;
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    for (rowcols, 0..) |r, i| for (s.vars, 0..) |c, j| {
        if (s.with.len == 0 and i >= j) continue;
        var data: std.ArrayList(advanced.Observation) = .empty;
        defer data.deinit(cx.arena);
        for (rows) |row| {
            const m = mass(s, row) orelse continue;
            if (row[c].isMissing() or row[r].isMissing()) continue;
            try data.append(cx.arena, .{ .x = row[if (serial and opt.ordinal_var) r else c].num, .y = row[if (serial and opt.ordinal_var) c else r].num, .f = m.f });
        }
        const estimate = if (serial) try advanced.polyserial(cx.arena, data.items, opt) else try advanced.polychoric(cx.arena, data.items, opt);
        if (estimate.unsupported_boundary) {
            diag.markGap();
            return cx.diags.fail(error.ParseError, 0, "PROC CORR: polychoric boundary information is unresolved at the requested tolerance.", .{});
        }
        if (!estimate.converged) try cx.diags.warn(0, "PROC CORR: {s} correlation for {s} and {s} unavailable (insufficient levels, NGROUPS limit, or failure to converge).", .{ if (serial) @as([]const u8, "polyserial") else "polychoric", s.ds.columns.items[c].name, s.ds.columns.items[r].name });
        try results.append(cx.arena, .{ .row = r, .column = c, .estimate = estimate });
    };
    return results.items;
}

test "CORR ordinal SAS joint MLE and convergence options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 12 }, &.{ 1, 2, 5 }, &.{ 1, 3, 3 }, &.{ 2, 1, 4 }, &.{ 2, 2, 17 }, &.{ 2, 3, 6 }, &.{ 3, 1, 2 }, &.{ 3, 2, 8 }, &.{ 3, 3, 13 } });
    const c = (try Testing.analyze(a, ds, "proc corr polychoric; var x y; freq f; run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(c.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.59061), c.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10494), c.se, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 31.6730), c.wald, 0.001);
    const s = (try Testing.analyze(a, ds, "proc corr polyserial; var x; with y; freq f; run;")).groups[0].polyserial[0].estimate;
    try std.testing.expect(s.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.51865), s.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.09703), s.se, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 28.5704), s.wald, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 17.9375), s.lr, 0.00005);
    const fail_result = (try Testing.analyze(a, ds, "proc corr polychoric(maxiter=1); var x y; freq f; run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(!fail_result.converged and std.math.isNan(fail_result.r));
}

test "CORR Hoeffding SAS tied coefficients and probability integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z" }, &.{ &.{ 1, 2, 1 }, &.{ 2, 5, 3 }, &.{ 3, 5, 2 }, &.{ 4, 9, 4 }, &.{ 5, 8, 3 }, &.{ 6, 13, 5 }, &.{ 7, 12, 4 }, &.{ 8, 17, 6 } });
    const g = (try Testing.analyze(a, ds, "proc corr hoeffding; var x y z; run;")).groups[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.38839), g.hoeffding[1].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0018), g.hoeffding[1].p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20089), g.hoeffding[2].r, 0.000005);

    try std.testing.expectApproxEqAbs(@as(f64, 0.87667), g.hoeffding[4].r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.67299), g.hoeffding[8].r, 0.000005);
}

test "CORR strong ordinal association SAS solver regression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 50 }, &.{ 1, 2, 2 }, &.{ 1, 3, 1 }, &.{ 2, 1, 2 }, &.{ 2, 2, 20 }, &.{ 2, 3, 1 }, &.{ 3, 1, 1 }, &.{ 3, 2, 2 }, &.{ 3, 3, 10 } });
    const g = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-8) polyserial(converge=1e-8); var x; with y; freq f; run;")).groups[0];
    try std.testing.expect(g.polychoric[0].estimate.converged);
    try std.testing.expect(g.polyserial[0].estimate.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.93009), g.polychoric[0].estimate.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03050), g.polychoric[0].estimate.se, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.82436), g.polyserial[0].estimate.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.03886), g.polyserial[0].estimate.se, 0.000005);
}

test "CORR advanced singular controls Fisher tails constants and missing ranks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z", "z2", "c", "neg" }, &.{ &.{ 1, 2, 1, 2, 1, -1 }, &.{ 2, 5, 3, 6, 1, -2 }, &.{ 3, 5, 2, 4, 1, -3 }, &.{ 4, 9, 4, 8, 1, -4 }, &.{ 5, 8, 3, 6, 1, -5 }, &.{ 6, 13, 5, 10, 1, -6 }, &.{ 7, 12, 4, 8, 1, -7 }, &.{ 8, 17, 6, 12, 1, -8 } });
    const g = (try Testing.analyze(a, ds, "proc corr pearson spearman kendall fisher; var x y; partial z z2 c; run;")).groups[0];
    try std.testing.expectEqual(@as(usize, 1), g.pairs[1].controls);
    try std.testing.expectApproxEqAbs(@as(f64, 0.556118), g.pairs[1].fisher.lower, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.464915), g.spearman[1].fisher.lower, 0.0000005);
    const upper = (try Testing.analyze(a, ds, "proc corr fisher(type=upper rho0=-.5); var x; with y; run;")).groups[0].pairs[0];
    try std.testing.expectApproxEqAbs(@as(f64, 0.989857), upper.fisher.upper, 0.0000005);
    try std.testing.expect(upper.fisher.p > 0.9999);
    const boundary = (try Testing.analyze(a, ds, "proc corr fisher; var x neg c; run;")).groups[0];
    try std.testing.expect(std.math.isNan(boundary.pairs[1].fisher.z));
    try std.testing.expect(std.math.isNan(boundary.pairs[2].r));
    const missing = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 2 }, &.{ 2, nan }, &.{ 3, 8 }, &.{ 4, 4 }, &.{ 5, 5 } });
    const r = (try Testing.analyze(a, missing, "proc corr spearman; var x y; run;")).groups[0].spearman[1];
    try Testing.near(0.4, r.r);
    try Testing.near(0.6, r.p);
    try Testing.near(4, r.n);
    const tiny = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 1 }, &.{ 2, 2 } });
    const t = (try Testing.analyze(a, tiny, "proc corr kendall hoeffding noprob; var x y; run;")).groups[0];
    try Testing.near(1, t.kendall[1].r);
    try std.testing.expect(std.math.isNan(t.kendall[1].p));
    try std.testing.expect(std.math.isNan(t.hoeffding[1].r));
}
test "CORR alpha pairwise missing uses Pearson matrix for standardized reliability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z", "w" }, &.{ &.{ 1, 2, 1, 1 }, &.{ 2, 5, 1, 2 }, &.{ 3, nan, 1, 3 }, &.{ 4, 6, 1, 1 }, &.{ 5, 8, 1, 2 } });
    const r = (try Testing.analyze(a, ds, "proc corr alpha; var x y z; run;")).groups[0].alpha.?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.746411), r.raw, 0.0000005);
    try std.testing.expect(std.math.isNan(r.standardized));
    try std.testing.expectApproxEqAbs(@as(f64, 0.974036), r.deleted[2].standardized, 0.0000005);
    const w = (try Testing.analyze(a, ds, "proc corr alpha; var x y; weight w; run;")).groups[0].alpha.?;
    try std.testing.expectApproxEqAbs(@as(f64, 1.002278), w.raw, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.972118), w.standardized, 0.0000005);
    const n = (try Testing.analyze(a, ds, "proc corr alpha vardef=n; var x y; run;")).groups[0].alpha.?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.985782), n.raw, 0.0000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.974036), n.standardized, 0.0000005);
}
test "CORR advanced invalid combinations and options fail through captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{ &.{ 1, 2, 1 }, &.{ 2, 4, 1 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ "proc corr spearman; var x y; weight w;", "proc corr hoeffding; var x y; partial w;", "proc corr alpha; var x; with y;", "proc corr fisher(alpha=0); var x y;", "proc corr fisher(rho0=1); var x y;", "proc corr fisher(biasadj=maybe); var x y;", "proc corr polyserial; var x y;", "proc corr polychoric(ngroups=1); var x y;", "proc corr polychoric(converge=0); var x y;", "proc corr polychoric(maxiter=0); var x y;", "proc corr; var x y; partial x;", "proc corr singular=-.1; var x y; partial w;" }) |source| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasStepErrors());
    }
}

test "CORR Hoeffding untied low medium high degenerate and FREQ replication coefficients" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ys = [_][]const f64{ &.{ 3, 7, 1, 8, 2, 6, 4, 5 }, &.{ 1, 3, 2, 5, 4, 7, 6, 8 }, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }, &.{ 2, 9, 1, 8, 4, 11, 3, 12, 5, 10, 6, 7 } };
    for (ys, [_]f64{ 1.0 / 56.0, 9.0 / 28.0, 1, 5.0 / 198.0 }, [_]f64{ 0.27035003097535, 0.00421936667347, 0, 0.19028121558348 }) |y, expected, expected_p| {
        const ds = try Testing.dataset(a, &.{ "x", "y" }, &.{});
        for (y, 1..) |value, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = value } });
        const p = (try Testing.analyze(a, ds, "proc corr hoeffding; var x; with y; run;")).groups[0].hoeffding[0];
        try Testing.near(expected, p.r);
        try std.testing.expectApproxEqAbs(expected_p, p.p, 5e-13);
    }
    const compressed = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 3, 2 }, &.{ 1, 1, 1 }, &.{ 2, 2, 3 }, &.{ 3, 3, 1 }, &.{ 4, 1, 2 } });
    const expanded = try Testing.dataset(a, &.{ "x", "y" }, &.{});
    for (compressed.rows.items) |row| {
        for (0..@as(usize, @intFromFloat(row[2].num))) |_| try expanded.appendRow(row[0..2]);
    }
    const c = (try Testing.analyze(a, compressed, "proc corr spearman kendall hoeffding noprob; var x y; freq f; run;")).groups[0];
    const e = (try Testing.analyze(a, expanded, "proc corr spearman kendall hoeffding noprob; var x y; run;")).groups[0];
    try Testing.near(-1.0 / 7.0, c.hoeffding[1].r);
    for (c.hoeffding, e.hoeffding) |v, w| {
        try Testing.near(v.r, w.r);
        try std.testing.expectApproxEqAbs(v.p, w.p, 5e-13);
    }
    try Testing.near(c.spearman[1].r, e.spearman[1].r);
    try Testing.near(c.kendall[1].r, e.kendall[1].r);
    const constant = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 1 }, &.{ 2, 1 }, &.{ 3, 1 }, &.{ 4, 1 }, &.{ 5, 1 }, &.{ 6, 1 } });
    const d = (try Testing.analyze(a, constant, "proc corr hoeffding noprob; var x y; run;")).groups[0];
    try Testing.near(-0.625, d.hoeffding[1].r);
    try Testing.near(-1.171875, d.hoeffding[3].r);
    try Testing.near(1, c.hoeffding[1].p);
    try Testing.near(1, d.hoeffding[1].p);
    try Testing.near(1, d.hoeffding[3].p);
}
test "CORR ordinal boundaries and ORDINAL NGROUPS options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 10 }, &.{ 2, 2, 10 }, &.{ 3, 3, 10 } });
    const g = (try Testing.analyze(a, ds, "proc corr polychoric polyserial(ordinal=var ngroups=all); var x; with y; freq f; run;")).groups[0];
    try Testing.near(1, g.polychoric[0].estimate.r);
    try Testing.near(0, g.polychoric[0].estimate.se);
    try Testing.near(1, g.polyserial[0].estimate.r);
    try std.testing.expect(std.math.isNan(g.polyserial[0].estimate.se));
    const limited = (try Testing.analyze(a, ds, "proc corr polychoric(ngroups=2); var x y; freq f; run;")).groups[0];
    try std.testing.expect(!limited.polychoric[0].estimate.converged);
    const zero = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 2, 9 }, &.{ 2, 1, 11 }, &.{ 2, 2, 3 } });
    const z = (try Testing.analyze(a, zero, "proc corr polychoric; var x y; freq f; run;")).groups[0].polychoric[0].estimate;
    try Testing.near(-0.999, z.r);
    try Testing.near(0, z.se);
    try std.testing.expect(std.math.isNan(z.wald));
    try std.testing.expectApproxEqAbs(@as(f64, 17.2930), z.lr, 0.00005);
}

test "CORR sparse polychoric boundary fails through captured diagnostics instead of spurious Wald inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 10 }, &.{ 1, 2, 4 }, &.{ 2, 2, 8 }, &.{ 2, 3, 2 }, &.{ 3, 3, 7 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc corr polychoric(converge=1e-5); var x y; freq f; run;", &d));
    try std.testing.expectError(error.ParseError, compute(cx, s));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "boundary information is unresolved") != null);
}

test "CORR convergence and iteration exhaustion match asymmetric SAS table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 900 }, &.{ 1, 2, 20 }, &.{ 1, 3, 5 }, &.{ 2, 1, 3 }, &.{ 2, 2, 50 }, &.{ 2, 3, 3 }, &.{ 3, 1, 2 }, &.{ 3, 2, 4 }, &.{ 3, 3, 13 } });
    for ([_]usize{ 3, 4 }) |limit| {
        const source = try std.fmt.allocPrint(a, "proc corr polychoric(converge=.01 maxiter={d}); var x y; freq f; run;", .{limit});
        const result = (try Testing.analyze(a, ds, source)).groups[0].polychoric[0].estimate;
        try std.testing.expect(!result.converged and std.math.isNan(result.r));
    }
    const result = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-8); var x y; freq f; run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(result.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.94595), result.r, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01381), result.se, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 353.3860), result.lr, 0.00005);
}

test "CORR sparse polychoric SAS scoring initialization covariance and iteration limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 10 }, &.{ 1, 2, 4 }, &.{ 2, 2, 8 }, &.{ 2, 3, 2 }, &.{ 3, 3, 7 } });
    const result = (try Testing.analyze(a, ds, "proc corr polychoric;var x y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(result.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9990304484694), result.r, 5e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1169549768335), result.se, 5e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 72.965915384262), result.wald, 0.001);
    try std.testing.expectApproxEqRel(@as(f64, 1.3190831196899e-17), result.p, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 40.9081053981301), result.lr, 1e-7);
    const loose = (try Testing.analyze(a, ds, "proc corr polychoric(converge=.001);var x y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expectApproxEqAbs(@as(f64, 0.99729481288087), loose.r, 5e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01781882037824), loose.se, 5e-7);
    for ([_]usize{ 5, 10 }) |limit| {
        const source = try std.fmt.allocPrint(a, "proc corr polychoric(maxiter={d});var x y;freq f;run;", .{limit});
        try std.testing.expect(!(try Testing.analyze(a, ds, source)).groups[0].polychoric[0].estimate.converged);
    }
    const mirrored = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{});
    const transposed = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{});
    for (ds.rows.items) |row| {
        try mirrored.appendRow(&.{ row[0], .{ .num = -row[1].num }, row[2] });
        try transposed.appendRow(&.{ row[1], row[0], row[2] });
    }
    for ([_]*Dataset{ mirrored, transposed }, [_]f64{ -1, 1 }) |input, sign| {
        const check = (try Testing.analyze(a, input, "proc corr polychoric;var x y;freq f;run;")).groups[0].polychoric[0].estimate;
        try std.testing.expectApproxEqAbs(sign * 0.9990304484694, check.r, 5e-8);
        try std.testing.expectApproxEqAbs(@as(f64, 0.1169549768335), check.se, 5e-7);
    }
    const labels = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 100, 1, 10 }, &.{ 100, 2, 4 }, &.{ 101, 2, 8 }, &.{ 101, 3, 2 }, &.{ 1000, 3, 7 } });
    const first = (try Testing.analyze(a, labels, "proc corr polychoric(converge=.99 maxiter=1);var x y;freq f;run;")).groups[0].polychoric[0].estimate;
    try Testing.near(0.999, first.r);
    try std.testing.expectApproxEqAbs(@as(f64, 0.12853158043271), first.se, 5e-8);
    const changed = (try Testing.analyze(a, labels, "proc corr polychoric;var x y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expectApproxEqAbs(@as(f64, 0.99915910281921), changed.r, 5e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.21383503532071), changed.se, 5e-6);
    const heldout = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 5 }, &.{ 1, 2, 7 }, &.{ 2, 2, 8 }, &.{ 2, 3, 3 }, &.{ 3, 3, 12 } });
    const checked = (try Testing.analyze(a, heldout, "proc corr polychoric;var x y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expectApproxEqAbs(@as(f64, 0.99894222793371), checked.r, 5e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.21987585371233), checked.se, 5e-6);
}

test "CORR positive rectangle integration resolves near-boundary quadrants" {
    const kernel = @import("corr_polychoric.zig");
    for ([_]f64{ -0.999999, -0.99, -0.4, 0, 0.4, 0.99, 0.999999 }) |rho| {
        const expected = 0.25 + std.math.asin(rho) / (2 * std.math.pi);
        try std.testing.expectApproxEqAbs(expected, kernel.rectangleProbability(-40, 0, -40, 0, rho), 5e-11);
    }
    const rare = kernel.rectangleProbability(-0.4, -0.3, 0.3, 0.4, 0.99);
    try std.testing.expect(rare > 0 and rare < 1e-5);
}

test "CORR public Hoeffding small N fractional FREQ exclusions and NOPROB" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]usize{ 4, 5, 6 }) |n| {
        const ds = try Testing.dataset(a, &.{ "x", "y" }, &.{});
        for (0..n) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = @floatFromInt(i) } });
        const result = try Testing.analyze(a, ds, "proc corr hoeffding nosimple;var x;with y;run;");
        const pair = result.groups[0].hoeffding[0];
        if (n < 5) try std.testing.expect(std.math.isNan(pair.r)) else try Testing.near(1, pair.r);
        if (n <= 5) try std.testing.expect(std.math.isNan(pair.p)) else try Testing.near(0, pair.p);
        var listing: std.ArrayList(u8) = .empty;
        try render(a, &listing, result);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "Row Column Correlation P N") != null);
        const suppressed = try Testing.analyze(a, ds, "proc corr hoeffding nosimple noprob;var x;with y;run;");
        listing.clearRetainingCapacity();
        try render(a, &listing, suppressed);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "Row Column Correlation P N") == null);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "Row Column Correlation N") != null);
    }
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 3, 2.9 }, &.{ 1, 1, 1 }, &.{ 2, 2, 3 }, &.{ 3, 3, 1 }, &.{ 4, 1, 2 }, &.{ 100, -100, 0 }, &.{ 200, -200, nan } });
    const pair = (try Testing.analyze(a, ds, "proc corr hoeffding;var x;with y;freq f;run;")).groups[0].hoeffding[0];
    try Testing.near(9, pair.n);
    try Testing.near(-1.0 / 7.0, pair.r);
    try Testing.near(1, pair.p);
    const missing = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 1 }, &.{ 2, 4 }, &.{ 3, 2 }, &.{ 4, 6 }, &.{ 5, 3 }, &.{ 6, 5 }, &.{ 7, nan }, &.{ nan, 7 } });
    const complete_pair = (try Testing.analyze(a, missing, "proc corr hoeffding;var x;with y;run;")).groups[0].hoeffding[0];
    try Testing.near(6, complete_pair.n);
    try Testing.near(0, complete_pair.r);
    try std.testing.expectApproxEqAbs(@as(f64, 0.36426667551153), complete_pair.p, 5e-13);
}
test "CORR public Hoeffding preserves ODS advanced capture rejection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 2 }, &.{ 2, 1 }, &.{ 3, 4 }, &.{ 4, 3 }, &.{ 5, 6 }, &.{ 6, 5 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var diagnostics = diag.Diagnostics.init(a);
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &diagnostics, try lex.tokenize(a, "ods output PearsonCorr=p SimpleStats=s;", &diagnostics));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, run(cx, &listing, try lex.tokenize(a, "proc corr hoeffding;var x y;run;", &diagnostics)));
    try std.testing.expect(diagnostics.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try diagnostics.render(), "ODS OUTPUT") != null);
}

test "CORR rectangle quadrature preserves partition mass and likelihood descent" {
    const kernel = @import("corr_polychoric.zig");
    const states = [_][4]f64{
        .{ -0.4956306291470207, 0.8088444041132948, 0.2855878655411077, 0.9947335197981 },
        .{ -0.495630632452179, 0.8088444028834387, 0.2855878638305473, 0.9950991078001906 },
    };
    const counts = [_]f64{ 280, 0, 273, 161, 0, 189 };
    var likelihood: [2]f64 = undefined;
    for (states, 0..) |state, k| {
        const x = [_]f64{ -40, state[0], state[1], 40 };
        const y = [_]f64{ -40, state[2], 40 };
        var total: f64 = 0;
        var nll: f64 = 0;
        for (0..3) |i| for (0..2) |j| {
            const p = kernel.rectangleProbability(x[i], x[i + 1], y[j], y[j + 1], state[3]);
            const transposed = kernel.rectangleProbability(y[j], y[j + 1], x[i], x[i + 1], state[3]);
            try std.testing.expect(std.math.isFinite(p) and p >= 0);
            try std.testing.expectApproxEqAbs(p, transposed, 3e-13);
            total += p;
            if (counts[i * 2 + j] > 0) nll -= counts[i * 2 + j] * @log(p);
        };
        try std.testing.expectApproxEqAbs(@as(f64, 1), total, 3e-13);
        likelihood[k] = nll;
    }
    // SAS PROBBNRM independently verifies these fixed iteration states.
    try std.testing.expectApproxEqAbs(@as(f64, 1227.6442891538863), likelihood[0], 5e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 1227.6442884965318), likelihood[1], 5e-9);
    try std.testing.expect(likelihood[1] < likelihood[0] - 5e-7);
}

test "CORR case2 public convergence is not defeated by quadrature error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 280 }, &.{ 2, 0, 273 }, &.{ 2, 20, 161 }, &.{ 12, 20, 189 } });
    const cases = .{
        .{ ".00045", 14, @as(f64, 0.99473351980195), @as(f64, 0.24731650570926), @as(f64, 633.376921745778), @as(f64, 0.00005767977253) },
        .{ ".00038", 15, @as(f64, 0.99509910781704), @as(f64, 0.36558803940963), @as(f64, 633.376923060487), @as(f64, 0.00649050816535) },
    };
    inline for (cases) |c| {
        const source = try std.fmt.allocPrint(a, "proc corr polychoric(converge={s} maxiter={d});var x;with y;freq f;run;", .{ c[0], c[1] });
        const result = (try Testing.analyze(a, ds, source)).groups[0].polychoric[0].estimate;
        try std.testing.expect(result.converged);
        try Testing.near(903, result.n);
        try std.testing.expectApproxEqAbs(c[2], result.r, 5e-8);
        try std.testing.expectApproxEqAbs(c[3], result.se, 5e-7);
        try std.testing.expectApproxEqAbs(c[4], result.lr, 1e-7);
        try std.testing.expectApproxEqAbs(c[5], result.p, 5e-8);
    }
}

test "CORR quadrature change preserves independent interior SAS controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 17 }, &.{ 0, 20, 4 }, &.{ 2, 0, 23 }, &.{ 2, 20, 14 }, &.{ 12, 0, 3 }, &.{ 12, 20, 29 } });
    const second = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 26 }, &.{ 0, 3, 13 }, &.{ 0, 23, 4 }, &.{ 7, 0, 3 }, &.{ 7, 3, 18 }, &.{ 7, 23, 31 } });
    const third = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 11 }, &.{ 0, 2, 4 }, &.{ 0, 7, 3 }, &.{ 1, 0, 5 }, &.{ 1, 2, 17 }, &.{ 1, 7, 6 }, &.{ 9, 0, 2 }, &.{ 9, 2, 7 }, &.{ 9, 7, 19 } });
    const fourth = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ -1, 2, 14 }, &.{ -1, 11, 9 }, &.{ 3, 2, 6 }, &.{ 3, 11, 23 } });
    const Case = struct { ds: *Dataset, source: []const u8, r: f64, se: f64, lr: f64 };
    for ([_]Case{
        .{ .ds = first, .source = "proc corr polychoric;var x;with y;freq f;run;", .r = 0.73357532289915, .se = 0.0836568956254, .lr = 32.2741142794848 },
        .{ .ds = second, .source = "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;", .r = 0.80508700896629, .se = 0.06662433183458, .lr = 43.9079638988586 },
        .{ .ds = third, .source = "proc corr polychoric;var x;with y;freq f;run;", .r = 0.64919651354426, .se = 0.093706839039, .lr = 24.0452695361532 },
        .{ .ds = fourth, .source = "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;", .r = 0.60674978943585, .se = 0.16026513167272, .lr = 8.93456112392664 },
    }) |c| {
        const result = (try Testing.analyze(a, c.ds, c.source)).groups[0].polychoric[0].estimate;
        try std.testing.expect(result.converged);
        try std.testing.expectApproxEqAbs(c.r, result.r, 5e-8);
        try std.testing.expectApproxEqAbs(c.se, result.se, 5e-7);
        try std.testing.expectApproxEqAbs(c.lr, result.lr, 1e-7);
    }
}

test "CORR convergence scaling and near-zero fallback match SAS stopping steps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ordinary = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 17 }, &.{ 0, 20, 4 }, &.{ 2, 0, 23 }, &.{ 2, 20, 14 }, &.{ 12, 0, 3 }, &.{ 12, 20, 29 } });
    const early = (try Testing.analyze(a, ordinary, "proc corr polychoric(maxiter=4);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(!early.converged);
    const fifth = (try Testing.analyze(a, ordinary, "proc corr polychoric(maxiter=5);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fifth.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.73357532289915), fifth.r, 5e-8);
    const near_zero = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 17 }, &.{ 0, 20, 4 }, &.{ 2, 0, 23 }, &.{ 2, 20, 14 }, &.{ 12, 0, 5 }, &.{ 12, 20, 27 } });
    const fourth = (try Testing.analyze(a, near_zero, "proc corr polychoric(maxiter=4);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fourth.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.67528568038814), fourth.r, 5e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.09426981785414), fourth.se, 5e-7);
}

test "CORR absolute information pivots reproduce the native frequency discriminator" {
    const kernel = @import("corr_polychoric.zig");
    // Native SAS information at case 22's reported rho. The fourth Schur
    // pivot is 8.662041195e-10 per unit frequency scale. SAS stops at scale
    // 11 and 11.5, and continues at 12, under all tested SINGULAR settings.
    const native = [_]f64{
        73.6937388608656,     -16.0494708087452,    -19.0587465853628,    -5.5682364317907e-10,
        -16.0494708087452,    36.7011896917651,     -2.6765361015066e-12, 1.2524460613515e-10,
        -19.0587465853628,    -2.6765361015066e-12, 38.1348299140736,     6.0614628392537e-10,
        -5.5682364317907e-10, 1.2524460613515e-10,  6.0614628392537e-10,  8.6620411951505e-10,
    };
    for ([_]f64{ 11, 11.5, 12 }, [_]usize{ 3, 3, 4 }) |scale, expected_rank| {
        var matrix = native;
        for (&matrix) |*v| v.* *= scale;
        var rhs = [_]f64{ 0, 0, 0, 1 };
        try std.testing.expectEqual(expected_rank, kernel.solveInformation(&matrix, &rhs).?);
        if (expected_rank == 3) try Testing.near(0, rhs[3]) else try std.testing.expectApproxEqRel(@as(f64, 1154462299.91641 / 12.0), rhs[3], 1e-10);
    }
    var invalid = native;
    invalid[0] = nan;
    var rhs = [_]f64{ 0, 0, 0, 1 };
    try std.testing.expect(kernel.solveInformation(&invalid, &rhs) == null);
}

test "CORR SINGULAR without PARTIAL warns rather than implying an information-rank control" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z" }, &.{ &.{ 1, 2, 1 }, &.{ 2, 4, 3 }, &.{ 3, 5, 2 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ ".5", "1e-8" }) |value| {
        var diagnostics = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
        const source = try std.fmt.allocPrint(a, "proc corr singular={s};var x y;run;", .{value});
        _ = try parse(cx, try lex.tokenize(a, source, &diagnostics));
        try std.testing.expect(!diagnostics.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diagnostics.render(), "SINGULAR= option is allowed only when a PARTIAL statement") != null);
    }
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    _ = try parse(cx, try lex.tokenize(a, "proc corr singular=.5;var x y;partial z;run;", &diagnostics));
    try std.testing.expectEqual(@as(usize, 0), diagnostics.count());
}
