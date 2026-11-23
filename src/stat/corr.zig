//! CORR: parsing, typed computation, and listing are separate entry points.
//! SAS 9.4 Statistical Procedures pp.8–36; oracle in docs/findings.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const parser = @import("../parser.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const nan = std.math.nan(f64);
const eq = std.ascii.eqlIgnoreCase;
const output = @import("corr_output.zig");
const advanced = @import("corr_advanced.zig");

pub const VarDef = enum { df, n, wdf, weight };
const graphics = @import("corr_plots.zig");
const var_lists = @import("variable_lists.zig");
const by_groups = @import("by_groups.zig");
pub const Options = struct {
    plots: graphics.Options = .{},
    pearson: bool = false,
    spearman: bool = false,
    kendall: bool = false,
    hoeffding: bool = false,
    simple_median: bool = false,
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
    ranked: bool = false,
    best: usize = std.math.maxInt(usize),
    cov: bool = false,
    csscp: bool = false,
    sscp: bool = false,
};
pub const Spec = struct {
    outputs: []const output.Spec = &.{},
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
    rows: []const []const Value = &.{},
    n: f64 = 0,
    sum_weights: f64 = 0,
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
fn column(cx: proc.ProcCtx, ds: *Dataset, name: []const u8) diag.Error!usize {
    return ds.indexOf(name) orelse cx.diags.fail(error.ParseError, 0, "Variable {s} not found.", .{name});
}
fn contains(cols: []const usize, c: usize) bool {
    return std.mem.indexOfScalar(usize, cols, c) != null;
}
fn addColumn(a: std.mem.Allocator, cols: *std.ArrayList(usize), c: usize) !void {
    if (!contains(cols.items, c)) try cols.append(a, c);
}

fn columns(cx: proc.ProcCtx, ds: *Dataset, toks: []const lex.Token, statement: []const u8, prior: []const usize) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    try cols.appendSlice(cx.arena, prior);
    var i: usize = 0;
    while (i < toks.len) {
        const names = try var_lists.next(cx.arena, ds, toks, &i, cx.diags);
        for (names) |name| {
            const ci = try column(cx, ds, name);
            if (ds.columns.items[ci].type != .num)
                return cx.diags.fail(error.ParseError, 0, "Variable {s} in list does not match type prescribed for this list.", .{name});
            if (contains(cols.items, ci))
                return cx.diags.fail(error.ParseError, 0, "Duplicate variable name in the {s} statement.", .{statement});
            try cols.append(cx.arena, ci);
        }
    }
    return cols.items;
}

pub fn parse(cx: proc.ProcCtx, toks: []const lex.Token) diag.Error!Spec {
    var opts: Options = .{};
    var outputs: std.ArrayList(output.Spec) = .empty;
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (kw(toks, i, "data") and at(toks, i + 1, .eq) and at(toks, i + 2, .name)) {
            name = toks[i + 2].text;
            i += 3;
            if (at(toks, i, .lparen)) i = proc.skipParen(toks, i);
        } else if (kw(toks, i, "plots")) {
            opts.plots = try graphics.parse(cx, toks, &i);
            if (opts.plots.requests.len > 0) opts.pearson = true;
        } else if (output.kindOf(toks[i].text)) |kind| {
            if (!at(toks, i + 1, .eq) or !at(toks, i + 2, .name)) return cx.diags.fail(error.ParseError, toks[i].line, "PROC CORR: expected an output dataset name", .{});
            var dest: output.Spec = .{ .kind = kind, .name = toks[i + 2].text };
            i += 3;
            if (at(toks, i, .dot)) {
                if (!at(toks, i + 1, .name)) return cx.diags.fail(error.ParseError, toks[i].line, "PROC CORR: expected a member name", .{});
                dest.name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ dest.name, toks[i + 1].text });
                i += 2;
            }
            if (at(toks, i, .lparen)) {
                const end = proc.skipParen(toks, i);
                if (end <= i + 1 or !at(toks, end - 1, .rparen)) return cx.diags.fail(error.ParseError, toks[i].line, "PROC CORR: unclosed output dataset options", .{});
                dest.options = toks[i + 1 .. end - 1];
                i = end;
            }
            for (outputs.items) |*old| {
                if (old.kind == kind) {
                    old.* = dest;
                    break;
                }
            } else try outputs.append(cx.arena, dest);
            switch (kind) {
                .outp => opts.pearson = true,
                .outs => opts.spearman = true,
                .outk => opts.kendall = true,
                .outh => opts.hoeffding = true,
                .outplc => if (opts.polychoric == null) {
                    opts.polychoric = .{};
                },
                .outpls => if (opts.polyserial == null) {
                    opts.polyserial = .{};
                },
            }
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
                        if (eq(key.text, "converge")) {
                            if (value < 0 or value > 1) return cx.diags.fail(error.ParseError, key.line, "The parameter value {d} is not within the required range of 0 and 1.", .{value});
                            opt.converge = value;
                        } else if (eq(key.text, "maxiter") and value >= 1 and value < @as(f64, @floatFromInt(std.math.maxInt(usize))) and @trunc(value) == value) {
                            opt.maxiter = @intFromFloat(value);
                        } else if (eq(key.text, "ngroups") and value > 1 and value < @as(f64, @floatFromInt(std.math.maxInt(usize))) and @trunc(value) == value) {
                            opt.ngroups = @intFromFloat(value);
                        } else return fail(cx, key);
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
                        if (eq(key.text, "rho0")) {
                            if (!(@abs(value) < 1)) return cx.diags.fail(error.ParseError, key.line, "The value of RHO0= must be between -1.0 and 1.0.", .{});
                            opts.fisher.?.rho0 = value;
                        } else if (eq(key.text, "alpha") and value > 0 and value < 1) opts.fisher.?.alpha = value else return fail(cx, key);
                    }
                }
                i += 1;
            }
        } else if (kw(toks, i, "singular") and at(toks, i + 1, .eq)) {
            i += 2;
            opts.singular = try numericOption(cx, toks, &i);
            opts.singular_specified = true;
            if (!(opts.singular >= 0 and opts.singular <= 1)) return fail(cx, toks[i - 1]);
        } else if (kw(toks, i, "rank")) {
            opts.ranked = true;
            i += 1;
        } else if (kw(toks, i, "best") and at(toks, i + 1, .eq)) {
            opts.ranked = true;
            i += 2;
            const v = try numericOption(cx, toks, &i);
            if (!std.math.isFinite(v) or v != @trunc(v)) return cx.diags.fail(error.ParseError, toks[i - 1].line, "PROC CORR: BEST= requires an integer.", .{});
            if (v < 1) try cx.diags.warn(toks[i - 1].line, "The number specified in BEST= option is less than 1; BEST=1 will be used.", .{});
            opts.best = if (v >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) std.math.maxInt(usize) else @intFromFloat(@max(1, v));
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
    var ds = try proc.procInput(cx.arena, raw, toks, cx.diags);
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var vars: ?[]const usize = null;
    var with: []const usize = &.{};
    var partial: []const usize = &.{};
    var by_statements: by_groups.Statements = .{};
    var frequencies: var_lists.NumericRole = .{};
    var weights: var_lists.NumericRole = .{};
    i += 1;
    while (i < toks.len and toks[i].tag != .eof) {
        if (toks[i].tag == .semicolon) {
            i += 1;
            continue;
        }
        const start = i;
        var end = i + 1;
        while (end < toks.len and toks[end].tag != .semicolon and toks[end].tag != .eof) end += 1;
        if (kw(toks, i, "var")) {
            vars = try columns(cx, ds, toks[i + 1 .. end], "VAR", vars orelse &.{});
        } else if (kw(toks, i, "with")) {
            with = try columns(cx, ds, toks[i + 1 .. end], "WITH", with);
        } else if (kw(toks, i, "partial")) {
            partial = try columns(cx, ds, toks[i + 1 .. end], "PARTIAL", partial);
            if (partial.len > 0) opts.nomiss = true;
        } else if (kw(toks, i, "format")) {
            try proc.parseProcFormat(cx.arena, toks, &i, &formats);
        } else if (kw(toks, i, "by")) {
            try by_statements.read(cx.arena, toks, &i);
        } else if (kw(toks, i, "freq") or kw(toks, i, "weight")) {
            const role = if (kw(toks, i, "freq")) &frequencies else &weights;
            try role.add(cx.arena, ds, try var_lists.roleVariable(toks[0..end], i + 1, false, cx.diags), cx.diags);
        } else if (!kw(toks, i, "where") and !kw(toks, i, "run") and !kw(toks, i, "quit") and !(toks[i].tag == .name and parser.isMidStepSkippable(toks[i].text))) return fail(cx, toks[start]);
        i = end;
    }
    for (formats.items) |spec| _ = try column(cx, ds, spec.name);
    ds = try by_groups.withFormats(cx.arena, ds, formats.items);
    const by = try by_statements.resolve(cx.arena, ds, cx.diags);
    var bcols: std.ArrayList(usize) = .empty;
    for (by.names) |n| try bcols.append(cx.arena, try column(cx, ds, n));
    if (vars == null) {
        var cs: std.ArrayList(usize) = .empty;
        for (ds.columns.items, 0..) |c, j| {
            if (c.type == .num and !contains(with, j) and !contains(partial, j) and !contains(bcols.items, j) and !frequencies.contains(j) and !weights.contains(j)) try cs.append(cx.arena, j);
        }
        vars = cs.items;
    }
    const freq = frequencies.first();
    const weight = weights.first();
    if (vars.?.len == 0) return cx.diags.fail(error.ParseError, 0, "Variable list empty.", .{});
    for (vars.?) |c| if (contains(partial, c)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: analysis variables cannot also be PARTIAL variables.", .{});
    for (with) |c| if (contains(partial, c)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: WITH variables cannot also be PARTIAL variables.", .{});
    if (weight != null and (opts.spearman or opts.kendall or opts.hoeffding)) {
        try cx.diags.warn(0, "Nonparametric options not allowed with WEIGHT statement.", .{});
        opts.spearman = false;
        opts.kendall = false;
        opts.hoeffding = false;
    }
    if (weight != null and (opts.polychoric != null or opts.polyserial != null))
        return cx.diags.fail(error.ParseError, 0, "PROC CORR: ordinal correlations are invalid with WEIGHT.", .{});
    if (partial.len > 0 and (opts.polychoric != null or opts.polyserial != null)) return cx.diags.fail(error.ParseError, 0, "PROC CORR: ordinal correlations with PARTIAL are unsupported.", .{});
    if (opts.polyserial != null and with.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC CORR: POLYSERIAL requires WITH.", .{});
    // M9 selects the simple-statistics columns and default Pearson table before
    // dropping HOEFFDING with PARTIAL or ALPHA with WITH.
    opts.simple_median = opts.spearman or opts.kendall or opts.hoeffding or opts.polychoric != null or opts.polyserial != null;
    if (opts.alpha or opts.cov or opts.csscp or opts.sscp or !opts.simple_median) opts.pearson = true;
    if (partial.len > 0 and opts.hoeffding) {
        try cx.diags.warn(0, "HOEFFDING option not allowed with PARTIAL statement.", .{});
        opts.hoeffding = false;
    }
    if (opts.alpha and with.len > 0) {
        try cx.diags.warn(0, "ALPHA option not allowed with WITH statement.", .{});
        opts.alpha = false;
    }
    if (opts.singular_specified and partial.len == 0)
        try cx.diags.warn(0, "SINGULAR= option is allowed only when a PARTIAL statement is also specified.", .{});
    return .{ .outputs = outputs.items, .partial = partial, .ds = ds, .vars = vars.?, .with = with, .by = bcols.items, .by_desc = by.desc, .notsorted = by.notsorted, .freq = freq, .weight = weight, .options = opts };
}

const Mass = struct { f: f64, w: f64 };
pub fn mass(s: Spec, row: []const Value) ?Mass {
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
    const slices = try by_groups.checkedSlices(cx.arena, s.ds, s.by, s.by_desc, s.notsorted, cx.diags);
    var groups: std.ArrayList(Group) = .empty;
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    for (slices) |bs| {
        var total_weight: f64 = 0;
        var total_freq: f64 = 0;
        var total_n: f64 = 0;
        var included_weight: f64 = 0;
        for (bs.rows) |row| {
            const f = if (s.freq) |c| @trunc(row[c].num) else 1;
            if (std.math.isFinite(f) and f >= 1) {
                total_freq += f;
                const w = if (s.weight) |c| row[c].num else 1;
                if (std.math.isFinite(w)) total_weight += @max(0, w) * f;
            }
            if (mass(s, row)) |m| {
                total_n += m.f;
                included_weight += m.w;
            }
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
        if (s.partial.len > 0) try partialPairs(cx, s, bs.rows, pairs.items, .pearson);
        for (simple.items) |*v| {
            if (s.options.simple_median) v.median = try median(cx.arena, s, bs.rows, v.column);
            if (s.partial.len > 0) for (pairs.items) |p| {
                if (p.column == v.column) {
                    v.partial_variance = p.variance_x;
                    break;
                }
                if (p.row == v.column) {
                    v.partial_variance = p.variance_y;
                    break;
                }
            };
        }
        const polychoric = if (s.options.polychoric) |opt| try polyPairs(cx, s, bs.rows, opt, false) else &.{};
        const polyserial = if (s.options.polyserial) |opt| try polyPairs(cx, s, bs.rows, opt, true) else &.{};
        const spearman: []Pair = if (s.options.spearman) try rankPairs(cx, s, bs.rows, .spearman) else &.{};
        const hoeffding: []Pair = if (s.options.hoeffding) try rankPairs(cx, s, bs.rows, .hoeffding) else &.{};
        const kendall: []Pair = if (s.options.kendall) try rankPairs(cx, s, bs.rows, .kendall) else &.{};
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
        try groups.append(cx.arena, .{ .rows = bs.rows, .n = total_n, .sum_weights = included_weight, .by_values = bs.rep, .simple = simple.items, .pairs = pairs.items, .unpartial_pairs = unpartial_pairs, .spearman = spearman, .kendall = kendall, .hoeffding = hoeffding, .alpha = reliability, .polychoric = polychoric, .polyserial = polyserial });
    }
    return .{ .spec = s, .groups = groups.items };
}

fn number(a: std.mem.Allocator, x: f64, probability: bool) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    if (probability) return if (x < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{x});
    return try std.fmt.allocPrint(a, "{d:.5}", .{x});
}
// The D10. estimates reserve space for a sign and retain at least three
// significant digits for small magnitudes before switching to E notation.
fn smallEstimate(a: std.mem.Allocator, x: f64) ![]const u8 {
    if (x == 0) return "0";
    if (@abs(x) < 0.00001) return @import("../format.zig").bestNumW(a, x, 10);
    if (@abs(x) < 0.001) return std.fmt.allocPrint(a, "{d:.7}", .{x});
    return number(a, x, false);
}
fn sixDecimals(a: std.mem.Allocator, x: f64) ![]const u8 {
    return if (std.math.isFinite(x)) std.fmt.allocPrint(a, "{d:.6}", .{x}) else ".";
}
// The Cronbach ODS template uses 8.6. A negative fraction can use all six
// decimals by omitting its leading zero; a larger magnitude reduces precision.
fn alphaStatistic(a: std.mem.Allocator, x: f64) ![]const u8 {
    const full = try sixDecimals(a, x);
    if (full.len <= 8) return full;
    if (std.mem.startsWith(u8, full, "-0.")) return std.fmt.allocPrint(a, "-{s}", .{full[2..]});
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, "8.6"), " ");
}
/// Text is deliberately downstream of Result: output datasets/ODS can consume
/// the full precision typed cells, never scrape this rounded listing.
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), result: Result) !void {
    return renderListing(a, out, result, null);
}

fn renderListing(a: std.mem.Allocator, out: *std.ArrayList(u8), result: Result, selection: ?*const proc.OdsListing) !void {
    const s = result.spec;
    if (s.options.noprint) return;
    for (result.groups, 1..) |g, by_group| {
        const tables: @import("../ods_listing.zig").Tables = .{ .selection = selection, .prefix = if (g.by_values != null and selection != null) try std.fmt.allocPrint(a, "Corr.ByGroup{d}", .{by_group}) else "Corr" };
        const header_start = out.items.len;
        if (g.by_values) |row| try by_groups.appendLine(a, out, s.ds, row, s.by);
        try out.appendSlice(a, "The CORR Procedure\n\n");
        const header_end = out.items.len;
        var start = header_end;
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
        try tables.finish(a, out, start, "VarInformation");
        inline for (.{ "sscp", "csscp", "cov" }) |kind| {
            if (@field(s.options, kind)) {
                start = out.items.len;
                const normal_name = if (eq(kind, "csscp")) "Csscp" else if (eq(kind, "sscp")) "Sscp" else "Cov";
                if (eq(kind, "csscp") and g.unpartial_pairs.len > 0) {
                    var original = g;
                    original.pairs = g.unpartial_pairs;
                    try out.appendSlice(a, "\nUnpartial");
                    try renderMoments(a, out, s, original, kind);
                    try tables.finish(a, out, start, normal_name);
                    start = out.items.len;
                    try out.appendSlice(a, "\nPartial");
                }
                try renderMoments(a, out, s, g, kind);
                try tables.finish(a, out, start, if (s.partial.len > 0 and eq(kind, "csscp")) "PartialCsscp" else if (s.partial.len > 0 and eq(kind, "cov")) "PartialCov" else normal_name);
            }
        }
        start = out.items.len;
        if (!s.options.nosimple) {
            try out.appendSlice(a, if (s.options.simple_median) "\nSimple Statistics\nVariable N Mean Std Dev Median Minimum Maximum\n" else "\nSimple Statistics\nVariable N Mean Std Dev Sum Minimum Maximum\n");
            for (g.simple) |v| {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d:.0}", .{ s.ds.columns.items[v.column].name, v.n }));
                for ([_]f64{ v.mean, v.stddev, if (s.options.simple_median) v.median else v.sum, v.minimum, v.maximum }) |x| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, x, false)}));
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
        try tables.finish(a, out, start, "SimpleStats");
        start = out.items.len;
        if (!s.options.nocorr and s.options.pearson) {
            try out.appendSlice(a, if (s.partial.len > 0) "\nPearson Partial Correlation Coefficients\n" else "\nPearson Correlation Coefficients\n");
            if (!s.options.noprob) try out.appendSlice(a, "Prob > |r| under H0: Rho=0\n");
            if (s.options.ranked) {
                try renderRanked(a, out, s, g.pairs, false, !s.options.noprob);
            } else {
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
        }
        try tables.finish(a, out, start, if (s.partial.len > 0) "PartialPearsonCorr" else "PearsonCorr");
        try renderAdvanced(a, out, s, g, tables);
        if (out.items.len == header_end) {
            out.shrinkRetainingCapacity(header_start);
            continue;
        }
        try out.append(a, '\n');
    }
}
/// BEST=/RANK change the listing for each response separately. OUTP/OUTS
/// still consume the complete coefficient matrix in variable order.
fn renderRanked(a: std.mem.Allocator, out: *std.ArrayList(u8), s: Spec, pairs: []const Pair, hoeffding: bool, probabilities: bool) !void {
    const row = try a.alloc(Pair, s.vars.len);
    defer a.free(row);
    var rows = std.mem.window(Pair, pairs, row.len, row.len);
    while (rows.next()) |source| {
        @memcpy(row, source);
        // SAS orders tied coefficients by reverse VAR position.
        std.mem.reverse(Pair, row);
        std.mem.sort(Pair, row, hoeffding, struct {
            fn greater(raw: bool, l: Pair, r: Pair) bool {
                if (std.math.isNan(l.r)) return false;
                if (std.math.isNan(r.r)) return true;
                return if (raw) l.r > r.r else @abs(l.r) > @abs(r.r);
            }
        }.greater);
        const top = row[0..@min(s.options.best, row.len)];
        try out.appendSlice(a, s.ds.columns.items[source[0].row].name);
        for (top) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{s.ds.columns.items[v.column].name}));
        try out.appendSlice(a, "\nr");
        for (top) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, v.r, false)}));
        if (probabilities) {
            try out.appendSlice(a, "\nP");
            for (top) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{if (v.row == v.column and std.math.isFinite(v.r)) "-" else try number(a, v.p, true)}));
        }
        try out.appendSlice(a, "\nN");
        for (top) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {d:.0}", .{v.n}));
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
    try output.write(cx, result);
    if (cx.capture) |capture| try @import("ods_corr.zig").publish(cx.arena, cx.diags, capture, result);
    try graphics.execute(cx, result);
    try renderListing(cx.arena, out, result, cx.listing);
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
    for ([_][]const u8{ "var x:;", "var x1--x2;", "var x2-x1;" }) |list| {
        const r = try Testing.analyze(a, ds, try std.fmt.allocPrint(a, "proc corr; {s} weight w; run;", .{list}));
        try std.testing.expectEqual(@as(usize, 2), r.spec.vars.len);
    }
    // M9 rejects a repeated named variable within or across VAR statements.
    try std.testing.expectError(error.ParseError, Testing.analyze(a, ds, "proc corr;var x2 x1 x2;run;"));
}
test "CORR repeated frequency or weight uses first and excludes both from implicit VAR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "w1", "w2" }, &.{ &.{ 1, 1, 3 }, &.{ 3, 2, 1 }, &.{ 7, 1, 2 } });
    for ([_][]const u8{ "freq w1;freq w2;", "weight w1;weight w2;" }) |statements| {
        const result = try Testing.analyze(a, ds, try std.fmt.allocPrint(a, "proc corr;{s}run;", .{statements}));
        try std.testing.expectEqualSlices(usize, &.{0}, result.spec.vars);
        try Testing.near(3.5, result.groups[0].simple[0].mean);
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
fn rankPairs(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, method: advanced.Method) ![]Pair {
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    const a = cx.arena;
    const pairs = try a.alloc(Pair, rowcols.len * s.vars.len);
    for (rowcols, 0..) |r, i| for (s.vars, 0..) |c, j| {
        pairs[i * s.vars.len + j] = try rankPair(a, s, rows, c, r, method);
    };
    if (s.partial.len > 0) try partialPairs(cx, s, rows, pairs, method);
    return pairs;
}
/// Sequential symmetric Schur complements, with singularity judged against
/// each original diagonal. Redundant controls do not consume residual df.
fn partialPairs(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, pairs: []Pair, method: advanced.Method) !void {
    const a = cx.arena;
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
        if (!(pivot > 0) or pivot < s.options.singular * original[c]) {
            try warnPartialSingular(cx, s, cols.items[c], method);
            continue;
        }
        used += 1;
        for (c + 1..n) |i| for (c + 1..n) |j| {
            matrix[i * n + j] -= matrix[i * n + c] * matrix[c * n + j] / pivot;
        };
    }
    for (k..n) |i| {
        if (!(matrix[i * n + i] > 0) or matrix[i * n + i] < s.options.singular * original[i]) {
            try warnPartialSingular(cx, s, cols.items[i], method);
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
fn warnPartialSingular(cx: proc.ProcCtx, s: Spec, col: usize, method: advanced.Method) !void {
    const name: []const u8 = switch (method) {
        .pearson => if (s.options.pearson) "PEARSON" else return,
        .spearman => "SPEARMAN",
        .kendall => "KENDALL",
        .hoeffding => unreachable,
    };
    try cx.diags.warn(0, "The variable {s} is singular in calculating the partial {s} correlations.", .{ s.ds.columns.items[col].name, name });
}
fn renderAdvanced(a: std.mem.Allocator, out: *std.ArrayList(u8), s: Spec, g: Group, tables: @import("../ods_listing.zig").Tables) !void {
    inline for (.{ "spearman", "kendall", "hoeffding" }) |name| {
        const pairs = @field(g, name);
        if (pairs.len > 0) {
            const start = out.items.len;
            if (s.options.ranked) {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}{s} Correlation Coefficients\n", .{ name, if (s.partial.len > 0) @as([]const u8, " Partial") else "" }));
                try renderRanked(a, out, s, pairs, eq(name, "hoeffding"), !s.options.noprob and !(eq(name, "kendall") and s.partial.len > 0));
            } else {
                try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}{s} Correlation Coefficients\nRow Column Correlation", .{ name, if (s.partial.len > 0) @as([]const u8, " Partial") else "" }));
                if (!s.options.noprob and !(eq(name, "kendall") and s.partial.len > 0)) try out.appendSlice(a, " P");
                try out.appendSlice(a, " N\n");
                for (pairs) |p| {
                    try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s}", .{ s.ds.columns.items[p.row].name, s.ds.columns.items[p.column].name, try number(a, p.r, false) }));
                    if (!s.options.noprob and !(eq(name, "kendall") and s.partial.len > 0)) {
                        const prob = if (eq(name, "hoeffding") and p.row == p.column and p.r == 1) nan else p.p;
                        try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, prob, true)}));
                    }
                    try out.appendSlice(a, try std.fmt.allocPrint(a, " {d:.0}\n", .{p.n}));
                }
            }
            const object = if (eq(name, "spearman")) (if (s.partial.len > 0) "PartialSpearmanCorr" else "SpearmanCorr") else if (eq(name, "kendall")) (if (s.partial.len > 0) "PartialKendallCorr" else "KendallCorr") else "HoeffdingCorr";
            try tables.finish(a, out, start, object);
        }
    }
    inline for (.{ "polyserial", "polychoric" }) |kind| {
        const estimates = @field(g, kind);
        if (estimates.len > 0) {
            const start = out.items.len;
            const polychoric = eq(kind, "polychoric");
            const hide_probs = s.options.noprob and !polychoric;
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s} Correlations\n{s} N Correlation StdError WaldChiSquare", .{ kind, if (polychoric) @as([]const u8, "Row Column") else "ContinuousVariable OrdinalVariable" }));
            try out.appendSlice(a, if (hide_probs) " LRChiSquare\n" else " WaldP LRChiSquare LRP\n");
            for (estimates) |entry| {
                const e = entry.estimate;
                const var_first = if (polychoric) s.with.len != 0 else !s.options.polyserial.?.ordinal_var;
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {d:.0}", .{ s.ds.columns.items[if (var_first) entry.column else entry.row].name, s.ds.columns.items[if (var_first) entry.row else entry.column].name, e.n }));
                for ([_]f64{ e.r, e.se, e.wald, e.p, e.lr, e.lr_p }, 0..) |v, i| {
                    if (hide_probs and (i == 3 or i == 5)) continue;
                    const value = if (i == 1)
                        try smallEstimate(a, v)
                    else if ((i == 2 or i == 4) and std.math.isFinite(v))
                        std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = v }, "10.4"), " ")
                    else
                        try number(a, v, i == 3 or i == 5);
                    try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{value}));
                }
                try out.append(a, '\n');
            }
            try tables.finish(a, out, start, if (polychoric) "PolychoricCorr" else "PolyserialCorr");
        }
    }
    if (g.alpha) |alpha_result| {
        var start = out.items.len;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nCronbach Coefficient Alpha\nRaw {s}\nStandardized {s}\n", .{ try alphaStatistic(a, alpha_result.raw), try alphaStatistic(a, alpha_result.standardized) }));
        try tables.finish(a, out, start, "CronbachAlpha");
        start = out.items.len;
        try out.appendSlice(a, "Deleted Variable RawCorrelation RawAlpha StandardizedCorrelation StandardizedAlpha\n");
        for (alpha_result.deleted, s.vars) |d, c| try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s} {s} {s}\n", .{ s.ds.columns.items[c].name, try alphaStatistic(a, d.raw_correlation), try alphaStatistic(a, d.raw), try alphaStatistic(a, d.standardized_correlation), try alphaStatistic(a, d.standardized) }));
        try tables.finish(a, out, start, "CronbachAlphaDel");
    }
    if (s.options.fisher) |opt| {
        for ([_][]const Pair{ if (s.options.pearson) g.pairs else &.{}, g.spearman }, [_][]const u8{ "Pearson", "Spearman" }) |pairs, title| {
            if (pairs.len == 0) continue;
            const start = out.items.len;
            const partial = s.partial.len != 0;
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}{s} Fisher Correlation Statistics\nVariable WithVariable N", .{ title, if (partial) @as([]const u8, " Partial") else "" }));
            if (partial) try out.appendSlice(a, " NPartialled");
            try out.appendSlice(a, " Correlation Z");
            if (opt.biasadj) try out.appendSlice(a, " Bias Estimate");
            if (opt.kind != .upper) try out.appendSlice(a, " Lower");
            if (opt.kind != .lower) try out.appendSlice(a, " Upper");
            if (opt.rho0 != 0) try out.appendSlice(a, " Rho0");
            if (!s.options.noprob) try out.appendSlice(a, " P");
            try out.append(a, '\n');
            const with = if (s.with.len != 0) s.with else s.vars;
            for (s.vars, 0..) |c, j| for (with, 0..) |r, i| {
                if (s.with.len == 0 and i <= j) continue;
                const p = pairs[i * s.vars.len + j];
                try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {d:.0}", .{ s.ds.columns.items[c].name, s.ds.columns.items[r].name, p.n }));
                if (partial) try out.appendSlice(a, try std.fmt.allocPrint(a, " {d}", .{p.controls}));
                try out.appendSlice(a, try std.fmt.allocPrint(a, " {s} {s}", .{ try number(a, p.r, false), try number(a, p.fisher.z, false) }));
                if (opt.biasadj) try out.appendSlice(a, try std.fmt.allocPrint(a, " {s} {s}", .{ try smallEstimate(a, p.fisher.bias), try number(a, p.fisher.estimate, false) }));
                for ([_]f64{ p.fisher.lower, p.fisher.upper }, 0..) |v, bound| {
                    if ((bound == 0 and opt.kind == .upper) or (bound == 1 and opt.kind == .lower)) continue;
                    try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try sixDecimals(a, v)}));
                }
                if (opt.rho0 != 0) try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, opt.rho0, false)}));
                if (!s.options.noprob) try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try number(a, p.fisher.p, true)}));
                try out.append(a, '\n');
            };
            try tables.finish(a, out, start, @import("ods_corr.zig").fisherTableName(eq(title, "Spearman"), s.partial.len != 0));
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
    var listing: std.ArrayList(u8) = .empty;
    try render(a, &listing, r);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Raw 0.869050\nStandardized 0.976693") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "x 0.946398") != null);
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
fn overGroupLimit(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, opt: advanced.PolyOptions, serial: bool) ![]const usize {
    if (opt.ngroups == std.math.maxInt(usize)) return &.{};
    var ordinal: std.ArrayList(usize) = .empty;
    defer ordinal.deinit(cx.arena);
    if (!serial or opt.ordinal_var) for (s.vars) |c| try addColumn(cx.arena, &ordinal, c);
    if (!serial or !opt.ordinal_var) for (s.with) |c| try addColumn(cx.arena, &ordinal, c);
    var excluded: std.ArrayList(usize) = .empty;
    var levels: std.ArrayList(f64) = .empty;
    defer levels.deinit(cx.arena);
    for (ordinal.items) |c| {
        levels.clearRetainingCapacity();
        for (rows) |row| {
            if (mass(s, row) == null or row[c].isMissing() or std.mem.indexOfScalar(f64, levels.items, row[c].num) != null) continue;
            if (levels.items.len == opt.ngroups) {
                try excluded.append(cx.arena, c);
                try cx.diags.warn(0, "The number of groups for variable {s} is greater than {d}, the number in the NGROUPS= option, the affected {s} correlations are set to missing.", .{ s.ds.columns.items[c].name, opt.ngroups, if (serial) @as([]const u8, "polyserial") else "polychoric" });
                break;
            }
            try levels.append(cx.arena, row[c].num);
        }
    }
    return excluded.toOwnedSlice(cx.arena);
}
fn polyPairs(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, opt: advanced.PolyOptions, serial: bool) ![]const PolyPair {
    var results: std.ArrayList(PolyPair) = .empty;
    var constant_columns: std.ArrayList(usize) = .empty;
    defer constant_columns.deinit(cx.arena);
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    const excluded = try overGroupLimit(cx, s, rows, opt, serial);
    defer cx.arena.free(excluded);
    for (rowcols, 0..) |r, i| for (s.vars, 0..) |c, j| {
        if (s.with.len == 0 and i >= j) continue;
        const skip = if (serial) contains(excluded, if (opt.ordinal_var) c else r) else contains(excluded, r) or contains(excluded, c);
        // The first VAR is the first polychoric score in a square request,
        // as it is in the equivalent VAR/WITH request.
        const first_is_row = if (serial) opt.ordinal_var else s.with.len == 0;
        const x_column = if (first_is_row) r else c;
        const y_column = if (first_is_row) c else r;
        var n: f64 = 0;
        var data: std.ArrayList(advanced.Observation) = .empty;
        defer data.deinit(cx.arena);
        for (rows) |row| {
            const m = mass(s, row) orelse continue;
            if (row[c].isMissing() or row[r].isMissing()) continue;
            n += m.f;
            if (!skip) try data.append(cx.arena, .{ .x = row[x_column].num, .y = row[y_column].num, .f = m.f });
        }
        // A rejected polyserial pair has no fit sample. Polychoric still
        // reports the pairwise count when either ordinal variable is excluded.
        const estimate = if (skip)
            advanced.Poly{ .n = if (serial) 0 else n }
        else if (serial)
            advanced.polyserial(cx.arena, data.items, opt) catch |err| switch (err) {
                error.SerialZeroDivide => {
                    try cx.diags.report(.err, 0, "Floating Point Zero Divide.", .{});
                    return cx.diags.fail(error.ExecError, 0, "Termination due to Floating Point Exception", .{});
                },
                else => |e| return e,
            }
        else
            try advanced.polychoric(cx.arena, data.items, opt);
        if (estimate.unsupported_boundary) {
            diag.markGap();
            return cx.diags.fail(error.ParseError, 0, "PROC CORR: {s} boundary information is unresolved at the requested tolerance.", .{if (serial) @as([]const u8, "polyserial") else "polychoric"});
        }
        if (estimate.constant_continuous) {
            if (!contains(constant_columns.items, x_column)) {
                try constant_columns.append(cx.arena, x_column);
                try cx.diags.warn(0, "The standard error for variable {s} is either zero or missing. The affected polyserial correlation are set to missing.", .{s.ds.columns.items[x_column].name});
            }
        } else if (!skip and !estimate.converged) try cx.diags.warn(0, "The algorithm for {s} correlation between {s} and {s} did not converge.", .{
            if (serial) @as([]const u8, "polyserial") else "polychoric",
            s.ds.columns.items[if (s.with.len == 0 or (serial and opt.ordinal_var)) c else r].name,
            s.ds.columns.items[if (s.with.len == 0 or (serial and opt.ordinal_var)) r else c].name,
        });
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

test "CORR polyserial checks usable pairs and constant inputs before zero tolerance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const overlapping = try Testing.dataset(a, &.{ "x", "g" }, &.{ &.{ 1, 1 }, &.{ 3, 1 }, &.{ 2, 2 }, &.{ 4, 2 } });
    const no_pair = try Testing.dataset(a, &.{ "x", "g" }, &.{ &.{ nan, 1 }, &.{ 1, nan } });
    const constant = try Testing.dataset(a, &.{ "x", "g" }, &.{ &.{ 1, 1 }, &.{ 1, 2 }, &.{ 1, 3 } });
    for ([_]*Dataset{ overlapping, no_pair, no_pair, constant }, [_][]const u8{ "0", "0", "1e-4", "0" }) |ds, tol| {
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("d", ds);
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const src = try std.fmt.allocPrint(a, "proc corr polyserial(converge={s});var x;with g;run;", .{tol});
        const spec = try parse(cx, try lex.tokenize(a, src, &d));
        if (ds == constant) {
            const fit = (try compute(cx, spec)).groups[0].polyserial[0].estimate;
            try std.testing.expectEqual(@as(f64, 3), fit.n);
            try std.testing.expect(std.math.isNan(fit.r) and std.math.isNan(fit.se));
            try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
            try std.testing.expectEqualStrings("The standard error for variable x is either zero or missing. The affected polyserial correlation are set to missing.", d.list.items[0].message);
        } else {
            try std.testing.expectError(error.ExecError, compute(cx, spec));
            try std.testing.expectEqual(@as(usize, 2), d.list.items.len);
            try std.testing.expectEqualStrings("Floating Point Zero Divide.", d.list.items[0].message);
            try std.testing.expectEqualStrings("Termination due to Floating Point Exception", d.list.items[1].message);
        }
    }
}

test "CORR zero tolerance requires an unchanged polychoric scoring iterate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 3 }, &.{ 0, 1, 2 }, &.{ 1, 0, 2 }, &.{ 1, 1, 3 } });
    const limited = (try Testing.analyze(a, rows, "proc corr polychoric(converge=0 maxiter=6);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(!limited.converged and std.math.isNan(limited.r));
    const fit = (try Testing.analyze(a, rows, "proc corr polychoric(converge=0 maxiter=12);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expectEqual(@as(f64, 0x1.3c6ef372fe94dp-2), fit.r);
    try std.testing.expectEqual(@as(f64, 0x1.d9fb5f1991926p-2), fit.se);
    const independent = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 0, 0, 5 }, &.{ 0, 1, 5 }, &.{ 1, 0, 5 }, &.{ 1, 1, 5 } });
    const first = (try Testing.analyze(a, independent, "proc corr polychoric(converge=0 maxiter=1);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(first.converged);
    try std.testing.expectEqual(@as(f64, 0), first.r);
    try std.testing.expectEqual(@as(f64, 0), first.lr);
}

test "CORR ordinal convergence accepts one and diagnoses values outside the unit interval" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "g", "h", "f" }, &.{
        &.{ 1, 0, 0, 1 }, &.{ 2, 0, 1, 1 }, &.{ 3, 0, 0, 2 }, &.{ 4, 0, 1, 1 },
        &.{ 5, 1, 0, 1 }, &.{ 6, 1, 1, 2 }, &.{ 7, 1, 0, 1 }, &.{ 8, 1, 1, 1 },
    });
    for ([_][]const u8{ ".9999999999999999", "1", "1.0" }) |value| {
        const chor_src = try std.fmt.allocPrint(a, "proc corr polychoric(converge={s} maxiter=50);var g;with h;freq f;run;", .{value});
        const serial_src = try std.fmt.allocPrint(a, "proc corr polyserial(converge={s} maxiter=50);var x;with g;freq f;run;", .{value});
        const c = (try Testing.analyze(a, ds, chor_src)).groups[0].polychoric[0].estimate;
        const sfit = (try Testing.analyze(a, ds, serial_src)).groups[0].polyserial[0].estimate;
        try Testing.near(0.31052229459722, c.r);
        try Testing.near(0.48267813752924, c.se);
        try Testing.near(0.99, sfit.r);
        try std.testing.expectEqual(@as(f64, 0), sfit.se);
    }
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ "polychoric", "polyserial" }) |method| {
        for ([_][]const u8{ "-0.00001", "1.000001", "2" }) |value| {
            var d = diag.Diagnostics.init(a);
            const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
            const source = try std.fmt.allocPrint(a, "proc corr {s}(converge={s}); var x;with g;run;", .{ method, value });
            try std.testing.expectError(error.ParseError, parse(cx, try lex.tokenize(a, source, &d)));
            const expected = try std.fmt.allocPrint(a, "The parameter value {s} is not within the required range of 0 and 1.", .{value});
            try std.testing.expectEqualStrings(expected, d.list.items[0].message);
        }
    }
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
test "CORR partial singular warnings identify every affected variable and method" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "g", "h" }, &.{
        &.{ 1, 2, 0, 0 }, &.{ 1, 2, 0, 0 }, &.{ 1, 3, 0, 1 },
        &.{ 1, 3, 0, 1 }, &.{ 1, 4, 1, 0 }, &.{ 1, 4, 1, 0 },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, try lex.tokenize(a, "proc corr; var x; with y; partial g h; run;", &d));
    const g = (try compute(cx, s)).groups[0];
    try std.testing.expectEqual(@as(usize, 2), d.list.items.len);
    for (d.list.items, [_][]const u8{ "x", "y" }) |message, col|
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "The variable {s} is singular in calculating the partial PEARSON correlations.", .{col}), message.message);
    try std.testing.expectEqual(@as(f64, 0), g.simple[2].partial_variance);
    try std.testing.expectEqual(@as(f64, 0), g.simple[3].partial_variance);
}
test "CORR Fisher listing uses VAR order and only the requested limits and bias statistics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y" }, &.{ &.{ 1, 1 }, &.{ 2, 3 }, &.{ 3, 2 } });
    const r = try Testing.analyze(a, ds, "proc corr fisher(type=lower biasadj=no rho0=-.3); var y x; run;");
    var listing: std.ArrayList(u8) = .empty;
    try render(a, &listing, r);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "Variable WithVariable N Correlation Z Lower Rho0 P\ny x 3 0.50000 0.54931 . -0.30000 .") != null);
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
test "CORR incompatible rank and ALPHA requests retain the SAS M9 listing and warnings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z", "n" }, &.{
        &.{ 1, 8, 4, 1 }, &.{ 2, 6, 1, 2 }, &.{ 2, 6, 5, 1 },
        &.{ 3, 2, 2, 1 }, &.{ 4, 5, 6, 3 }, &.{ 5, 3, 2, 1 },
        &.{ 6, 1, 5, 2 }, &.{ 8, 4, 8, 1 }, &.{ 9, 1, 3, 1 },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    const cases = [_]struct { source: []const u8, warning: []const u8, output: []const u8, pearson: bool }{
        .{ .source = "proc corr spearman; var x y; weight n;", .warning = "Nonparametric options not allowed with WEIGHT statement.", .output = "-0.75389", .pearson = true },
        .{ .source = "proc corr hoeffding; var x y; partial z;", .warning = "HOEFFDING option not allowed with PARTIAL statement.", .output = "Median Minimum Maximum", .pearson = false },
        .{ .source = "proc corr alpha; var x y; with z;", .warning = "ALPHA option not allowed with WITH statement.", .output = "0.34076 0.09129", .pearson = true },
    };
    for (cases) |case| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        var listing: std.ArrayList(u8) = .empty;
        try run(cx, &listing, try lex.tokenize(a, case.source, &d));
        try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
        try std.testing.expectEqual(.warning, d.list.items[0].severity);
        try std.testing.expectEqualStrings(case.warning, d.list.items[0].message);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, case.output) != null);
        try std.testing.expectEqual(case.pearson, std.mem.indexOf(u8, listing.items, "Pearson") != null);
        for ([_][]const u8{ "spearman", "hoeffding", "Cronbach" }) |ignored| try std.testing.expect(std.mem.indexOf(u8, listing.items, ignored) == null);
    }
}

test "CORR advanced invalid combinations and options fail through captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "w" }, &.{ &.{ 1, 2, 1 }, &.{ 2, 4, 1 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    for ([_][]const u8{ "proc corr fisher(alpha=0); var x y;", "proc corr fisher(rho0=1); var x y;", "proc corr fisher(biasadj=maybe); var x y;", "proc corr polyserial; var x y;", "proc corr polychoric(ngroups=1); var x y;", "proc corr polychoric(converge=2); var x y;", "proc corr polychoric(maxiter=0); var x y;", "proc corr; var x y; partial x;", "proc corr singular=-.1; var x y; partial w;" }) |source| {
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

test "CORR polyserial listing always shows the continuous variable first" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "g" }, &.{
        &.{ 1, 1 }, &.{ 3, 1 }, &.{ 5, 1 }, &.{ 2, 2 }, &.{ 4, 2 }, &.{ 6, 2 }, &.{ 3, 3 }, &.{ 5, 3 }, &.{ 8, 3 },
    });
    for ([_][]const u8{ "proc corr polyserial;var x;with g;run;", "proc corr polyserial(ordinal=var);var g;with x;run;" }) |source| {
        const g = try Testing.analyze(a, ds, source);
        var listing: std.ArrayList(u8) = .empty;
        try render(a, &listing, g);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "ContinuousVariable OrdinalVariable") != null);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "x g 9 0.53480 0.27980") != null);
        try std.testing.expect(std.mem.indexOf(u8, listing.items, "0.0560 2.2910 0.1301") != null);
        // The M9 Wald listing rounds to 3.6534. At the fitted maximum,
        // independent analytic observed information gives 3.6533474922.
        try std.testing.expectApproxEqAbs(@as(f64, 3.6534), g.groups[0].polyserial[0].estimate.wald, 0.00005);
    }
}
test "CORR group limits name each ordinal variable once and MAXITER names its pair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "r", "c", "n" }, &.{
        &.{ 1, 1, 2 }, &.{ 1, 2, 1 }, &.{ 1, 3, 1 }, &.{ 2, 2, 2 }, &.{ 2, 3, 1 }, &.{ 3, 1, 1 }, &.{ 3, 3, 3 },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const limited = try parse(cx, try lex.tokenize(a, "proc corr polychoric(ngroups=2);var r c;freq n;run;", &d));
    const fit = (try compute(cx, limited)).groups[0].polychoric[0].estimate;
    try std.testing.expectEqual(@as(f64, 11), fit.n);
    try std.testing.expect(std.math.isNan(fit.r));
    try std.testing.expectEqual(@as(usize, 2), d.list.items.len);
    for (d.list.items, [_][]const u8{ "r", "c" }) |msg, col|
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "The number of groups for variable {s} is greater than 2, the number in the NGROUPS= option, the affected polychoric correlations are set to missing.", .{col}), msg.message);
    const iter = try parse(cx, try lex.tokenize(a, "proc corr polychoric(maxiter=1 converge=1e-10);var r c;freq n;run;", &d));
    _ = try compute(cx, iter);
    try std.testing.expectEqual(@as(usize, 3), d.list.items.len);
    try std.testing.expectEqualStrings("The algorithm for polychoric correlation between c and r did not converge.", d.list.items[2].message);
}
test "CORR NGROUPS rejects the polyserial fit before counting its observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "g", "h", "f" }, &.{
        &.{ 1, 1, 1, 2 }, &.{ 2, 2, 2, 3 }, &.{ 3, 3, 1, 4 },
    });
    for ([_][]const u8{
        "proc corr polyserial(ngroups=2); var x; with g h; freq f; run;",
        "proc corr polyserial(ordinal=var ngroups=2); var g h; with x; freq f; run;",
    }) |source| {
        const pairs = (try Testing.analyze(a, ds, source)).groups[0].polyserial;
        try Testing.near(0, pairs[0].estimate.n);
        try std.testing.expect(std.math.isNan(pairs[0].estimate.r));
        try Testing.near(9, pairs[1].estimate.n);
    }
}

test "CORR polychoric returns a finite first step for an independent frequency table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 0, 0, 357280 }, &.{ 0, 1, 263088 }, &.{ 1, 0, 274340 }, &.{ 1, 1, 202014 },
    });
    const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=.99 maxiter=1);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fit.converged);
    try std.testing.expectEqual(@as(f64, 1096722), fit.n);
    try std.testing.expectApproxEqAbs(@as(f64, 0), fit.r, 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 0.001517487395931303), fit.se, 1e-16);
    try std.testing.expectApproxEqAbs(@as(f64, 0), fit.lr, 1e-9);
}

test "CORR uses the occupied cell probability floor in fitted likelihood and score" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ -72, -88, 101 }, &.{ 43, 119, 2121 }, &.{ -72, 119, 7171 }, &.{ 0, 119, 1616 },
        &.{ 43, -88, 1414 }, &.{ 43, 91, 6666 },  &.{ 43, 68, 606 },    &.{ -48, 119, 1010 },
    });
    // The first fit assigns probability 4.35e-13 to an occupied cell.
    // Its LR checks the logarithm, and later fits check the scoring step.
    const cases = [_]struct { tol: []const u8, rho: f64, se: f64, lr: f64 }{
        .{ .tol = "1", .rho = -0.96106981353344, .se = 0.0086265455138, .lr = 12009.7483795129 },
        .{ .tol = ".1", .rho = -0.89437947232223, .se = 0.00294875255757, .lr = 13612.6341753773 },
        .{ .tol = "1e-6", .rho = -0.8999899142733, .se = 0.00316562143193, .lr = 13622.2627583379 },
    };
    for (cases) |case| {
        const src = try std.fmt.allocPrint(a, "proc corr polychoric(converge={s});var x;with y;freq f;run;", .{case.tol});
        const fit = (try Testing.analyze(a, ds, src)).groups[0].polychoric[0].estimate;
        try std.testing.expect(fit.converged);
        try std.testing.expectEqual(@as(f64, 20705), fit.n);
        try std.testing.expectApproxEqAbs(case.rho, fit.r, 1e-12);
        try std.testing.expectApproxEqAbs(case.se, fit.se, 1e-13);
        try std.testing.expectApproxEqAbs(case.lr, fit.lr, 1e-9);
    }
}

test "CORR three-level staircase tight tolerance has zero-rank Wald inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{ &.{ 1, 1, 10 }, &.{ 1, 2, 4 }, &.{ 2, 2, 8 }, &.{ 2, 3, 2 }, &.{ 3, 3, 7 } });
    for ([_][]const u8{ "1e-5", "1e-6" }) |tol| {
        const source = try std.fmt.allocPrint(a, "proc corr polychoric(converge={s}); var x y; freq f; run;", .{tol});
        const fit = (try Testing.analyze(a, ds, source)).groups[0].polychoric[0].estimate;
        try std.testing.expect(fit.converged);
        try std.testing.expectApproxEqAbs(@as(f64, 0.99985326007584), fit.r, 5e-8);
        try std.testing.expectEqual(@as(f64, 0), fit.se);
        try std.testing.expect(std.math.isNan(fit.wald) and std.math.isNan(fit.p));
        try std.testing.expectApproxEqAbs(@as(f64, 40.9081058800832), fit.lr, 1e-10);
    }
}
test "CORR retracts a projected ordinal step when its likelihood loss is distinguishable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 262255, -32857, 147 }, &.{ 262160, -32724, 105 }, &.{ 262209, -32724, 126 }, &.{ 262255, -32847, 140 },
        &.{ 262128, -32724, 252 }, &.{ 262255, -32821, 91 }, &.{ 262255, -32724, 112 },
    });
    const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-6 maxiter=25);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fit.converged);
    try std.testing.expectEqual(@as(f64, 973), fit.n);
    try std.testing.expectApproxEqAbs(@as(f64, -0.9997288349756279), fit.r, 1e-12);
    try std.testing.expectEqual(@as(f64, 0), fit.se);
    try std.testing.expect(std.math.isNan(fit.wald));
    try std.testing.expectApproxEqAbs(@as(f64, 773.2658152221902), fit.lr, 1e-9);
}

test "CORR rectangular separated margins honor the cap and refine the boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 1, -2, 9 }, &.{ 3, -2, 7 }, &.{ 3, 1, 10 }, &.{ 5, 1, 13 },
        &.{ 5, 4, 14 }, &.{ 7, 4, 5 }, &.{ 7, 7, 11 }, &.{ 7, 10, 7 },
    });
    const early = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-6 maxiter=20);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(!early.converged and !early.unsupported_boundary);
    try std.testing.expectEqual(@as(f64, 76), early.n);
    try std.testing.expect(std.math.isNan(early.r) and std.math.isNan(early.lr));
    const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fit.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9999), fit.r, 1e-14);
    try std.testing.expectEqual(@as(f64, 0), fit.se);
    try std.testing.expect(std.math.isNan(fit.wald));
    try std.testing.expectApproxEqAbs(@as(f64, 124.86114667012117), fit.lr, 1e-9);
}

test "CORR refines repeated polychoric projections with occupied crossing cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 111, -2, 2871 }, &.{ -78, -79, 4257 }, &.{ 111, -79, 792 }, &.{ -78, 58, 99 },
        &.{ -19, -79, 7227 }, &.{ 111, -67, 6633 }, &.{ 111, 58, 2772 }, &.{ 105, -79, 2574 },
    });
    const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
    try std.testing.expect(fit.converged);
    try std.testing.expectEqual(@as(f64, 27225), fit.n);
    try std.testing.expectApproxEqAbs(@as(f64, 0.99999), fit.r, 1e-14);
    try std.testing.expectEqual(@as(f64, 0), fit.se);
    try std.testing.expect(std.math.isNan(fit.wald));
    try std.testing.expectApproxEqAbs(@as(f64, 26726.787288762935), fit.lr, 1e-7);
}

test "CORR resolves separated four-level projections with distinguishable likelihood gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ -21, 14, 4224 }, &.{ 17, 9, 2432 }, &.{ 17, 12, 3328 }, &.{ 4, 14, 4480 },
        &.{ 17, 14, 11264 }, &.{ 17, -4, 768 }, &.{ -2, 14, 2688 },
    });
    const second = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 14, 6, 2560 }, &.{ -14, 28, 2048 }, &.{ 14, 28, 1920 },  &.{ 14, 2, 6016 },
        &.{ 1, 28, 3200 }, &.{ 14, 18, 768 },   &.{ -24, 28, 3840 },
    });
    for ([_]*Dataset{ first, second }, [_]f64{ 29184, 20352 }, [_]f64{ -0.999, -0.9999 }, [_]f64{ 7635.472308469951, 17791.23558852251 }) |ds, n, r, lr| {
        const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
        try std.testing.expect(fit.converged);
        try std.testing.expectEqual(n, fit.n);
        try std.testing.expectApproxEqAbs(r, fit.r, 1e-14);
        try std.testing.expectEqual(@as(f64, 0), fit.se);
        try std.testing.expect(std.math.isNan(fit.wald) and std.math.isNan(fit.p));
        try std.testing.expectApproxEqAbs(lr, fit.lr, 1e-9);
    }
}

test "CORR keeps a separated four-level projection unresolved when likelihood gaps overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 25, 12, 256 },  &.{ 25, -2, 800 },  &.{ -25, 15, 496 }, &.{ 25, 15, 1120 },
        &.{ -13, 15, 128 }, &.{ 25, -18, 368 }, &.{ 10, 15, 624 },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try lex.tokenize(a, "proc corr polychoric(converge=1e-6);var x;with y;freq f;run;", &d));
    // M9 returns -0.99999. Accepting the first projection would report -0.999.
    try std.testing.expectError(error.ParseError, compute(cx, spec));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "boundary information is unresolved") != null);
}

test "CORR four-level staircase keeps a captured diagnostic for its unresolved boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{
        &.{ 0, 0, 3500 },   &.{ 11, 0, 2500 },  &.{ 12, 0, 1800 },  &.{ 23, 0, 1500 },
        &.{ 23, 19, 3300 }, &.{ 23, 23, 3100 }, &.{ 23, 27, 1400 },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const capped = try parse(cx, try lex.tokenize(a, "proc corr polychoric(converge=1e-6 maxiter=24); var x; with y; freq f; run;", &d));
    const fit = (try compute(cx, capped)).groups[0].polychoric[0].estimate;
    try std.testing.expectEqual(@as(f64, 17100), fit.n);
    try std.testing.expect(!fit.converged and std.math.isNan(fit.r) and std.math.isNan(fit.se) and std.math.isNan(fit.lr));
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqualStrings("The algorithm for polychoric correlation between y and x did not converge.", d.list.items[0].message);
    const s = try parse(cx, try lex.tokenize(a, "proc corr polychoric(converge=1e-6); var x y; freq f; run;", &d));
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

test "CORR polychoric first step preserves native score scaling and variable order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_][3]f64{
        .{ 0, 0, 3500 },   .{ 11, 0, 2500 },  .{ 12, 0, 1800 },  .{ 23, 0, 1500 },
        .{ 23, 19, 3300 }, .{ 23, 23, 3100 }, .{ 23, 27, 1400 },
    };
    // These scale pairs share all three first-step fields in SAS 9.4 M9.
    // The unequal integer scales distinguish the order of the two reciprocal roots.
    const cases = [_]struct { scales: [2][2]f64, expected: [3]f64 }{
        .{ .scales = .{ .{ 1, 1 }, .{ 0x1p300, 0x1p300 } }, .expected = .{ 0.9460017945521846, 0.0055509154975335, 14570.35682193622 } },
        .{ .scales = .{ .{ -1, 1 }, .{ -0x1p300, 0x1p300 } }, .expected = .{ -0.9460017945521834, 0.005550915497533486, 14570.356821936199 } },
        .{ .scales = .{ .{ 2, 3 }, .{ 3, 5 } }, .expected = .{ 0.9460017945521842, 0.005550915497533494, 14570.356821936213 } },
    };
    for (cases) |case| {
        var first: ?[3]f64 = null;
        for (case.scales) |scale| {
            const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{});
            for (rows) |row| try ds.appendRow(&.{ .{ .num = scale[0] * row[0] }, .{ .num = scale[1] * row[1] }, .{ .num = row[2] } });
            for ([_][]const u8{ "var x;with y;", "var x y;" }) |vars| {
                const source = try std.fmt.allocPrint(a, "proc corr polychoric(converge=.99 maxiter=1);{s}freq f;run;", .{vars});
                const result = (try Testing.analyze(a, ds, source)).groups[0].polychoric[0].estimate;
                try std.testing.expect(result.converged);
                const values = [3]f64{ result.r, result.se, result.lr };
                for (values, case.expected) |actual, target| try std.testing.expectApproxEqRel(target, actual, 1e-13);
                if (first) |original| try std.testing.expectEqual(original, values) else first = values;
            }
        }
    }
}

test "CORR polychoric scoring starts at the first retained pair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rows = [_][3]f64{
        .{ 0, 0, 3500 },    .{ -11, 0, 2500 },  .{ -12, 0, 1800 },  .{ -23, 0, 1500 },
        .{ -23, 19, 3300 }, .{ -23, 23, 3100 }, .{ -23, 27, 1400 },
    };
    var estimates: [3]f64 = undefined;
    for (&estimates, 0..) |*estimate, order| {
        const ds = try Testing.dataset(a, &.{ "x", "y", "f" }, &.{});
        // An ignored row precedes every fit. The last order emits one copy
        // of the original first pair, then the remaining counts in reverse.
        try ds.appendRow(&.{ .{ .num = -23 }, .{ .num = 19 }, .{ .num = 0 } });
        if (order == 2) try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 0 }, .{ .num = 1 } });
        for (0..rows.len) |i| {
            const idx = if (order == 0) i else rows.len - i - 1;
            const row = rows[idx];
            const count = if (order == 2 and idx == 0) row[2] - 1 else row[2];
            try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = count } });
        }
        const fit = (try Testing.analyze(a, ds, "proc corr polychoric(converge=.99 maxiter=1);var x;with y;freq f;run;")).groups[0].polychoric[0].estimate;
        try std.testing.expect(fit.converged);
        estimate.* = fit.r;
    }
    // M9 first-step coefficients are BFEE45A58E31E2D3 and BFEE45A58E31E2D4
    // for this reflection. Splitting FREQ preserves the original coefficient.
    try std.testing.expectApproxEqAbs(@as(f64, -0.9460017945521834), estimates[0], 1e-14);
    try std.testing.expectEqual(std.math.nextAfter(f64, estimates[0], -std.math.inf(f64)), estimates[1]);
    try std.testing.expectEqual(estimates[0], estimates[2]);
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
test "CORR public Hoeffding captures median SimpleStats and expires unmatched PearsonCorr" {
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
    try run(cx, &listing, try lex.tokenize(a, "proc corr hoeffding;var x y;run;", &diagnostics));
    try capture.finish(&lib, &diagnostics);
    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expect(lib.find("p") == null);
    const stats = lib.find("s").?;
    try std.testing.expectEqual(@as(usize, 2), stats.rowCount());
    try std.testing.expectEqual(@as(f64, 3.5), stats.row(0)[stats.indexOf("Median").?].num);
    try std.testing.expect(stats.indexOf("Sum") == null);
    try std.testing.expect(std.mem.indexOf(u8, try diagnostics.render(), "Output 'PearsonCorr' was not created") != null);
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

test "FEAT-base-stat-results six matrix destinations use their own coefficient and metadata" {
    // Saved SAS M9 corr_outp, corr_outs, corr_outk, corr_outh, corr_outplc,
    // corr_outpls_schema. OUT* implies the method even without a display option.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "g", "h" }, &.{ &.{ 1, 2, 0, 0 }, &.{ 2, 5, 0, 1 }, &.{ 3, 5, 0, 0 }, &.{ 4, 9, 0, 1 }, &.{ 5, 8, 1, 0 }, &.{ 6, 13, 1, 1 }, &.{ 7, 12, 1, 0 }, &.{ 8, 17, 1, 1 } });
    ds.setLabel("x", "Baseline");
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    var listing: std.ArrayList(u8) = .empty;
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, &listing, try lex.tokenize(a, "proc corr data=d noprint out=linear outs=s outk=k outh=h; var x y; run;", &d));
    for ([_][]const u8{ "linear", "s", "k", "h" }, [_]f64{ 0.96204, 0.94612, 0.83650, 0.38839 }) |name, r| {
        const result = lib.find(name).?;
        try std.testing.expectEqual(@as(usize, 4), result.columns.items.len);
        try std.testing.expectEqual(@as(usize, 5), result.rowCount());
        try std.testing.expectEqual(@as(?usize, 8), result.columns.items[1].len);
        try std.testing.expectEqualStrings("Baseline", result.columns.items[2].label.?);
        try std.testing.expectEqualStrings("MEAN", result.row(0)[0].str);
        try std.testing.expectEqual(@as(f64, 4.5), result.row(0)[2].num);
        try std.testing.expectApproxEqAbs(@as(f64, 4.94072), result.row(1)[3].num, 0.000005);
        try std.testing.expectEqualStrings("N", result.row(2)[0].str);
        try std.testing.expectEqualStrings("x", result.row(3)[1].str);
        try std.testing.expectEqualStrings("CORR", result.row(4)[0].str);
        try std.testing.expectApproxEqAbs(r, result.row(3)[3].num, 0.000005);
        try std.testing.expectApproxEqAbs(r, result.row(4)[2].num, 0.000005);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.87667), lib.find("h").?.row(4)[3].num, 0.000005);
    try run(cx, &listing, try lex.tokenize(a, "proc corr data=d noprint outplc=p; var g h; run;", &d));
    try std.testing.expectApproxEqAbs(@as(f64, 0), lib.find("p").?.row(3)[3].num, 0.000005);
    const serial = try Testing.dataset(a, &.{ "x", "g" }, &.{ &.{ 1, 1 }, &.{ 3, 1 }, &.{ 5, 1 }, &.{ 2, 2 }, &.{ 4, 2 }, &.{ 6, 2 }, &.{ 3, 3 }, &.{ 5, 3 }, &.{ 8, 3 } });
    try lib.put("d", serial);
    try run(cx, &listing, try lex.tokenize(a, "proc corr data=d noprint outpls=work.serial; var x; with g; run;", &d));
    const pls = lib.find("serial").?;
    try std.testing.expectEqual(@as(usize, 4), pls.rowCount());
    try std.testing.expectEqualStrings("g", pls.row(3)[1].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.53480), pls.row(3)[2].num, 0.000005);
    try std.testing.expectEqual(@as(usize, 0), listing.items.len);
}

test "FEAT-base-stat-results SSCP intercept alpha blocks and BY row descriptors" {
    // SAS M9 corr_outp_matrix_types and corr_outp_by_metadata.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z" }, &.{ &.{ 1, 8, 4 }, &.{ 2, 6, 1 }, &.{ 2, 6, 5 }, &.{ 3, 2, 2 }, &.{ 4, 5, 6 }, &.{ 5, 3, 2 }, &.{ 6, 1, 5 }, &.{ 8, 4, 8 }, &.{ 9, 1, 3 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    var listing: std.ArrayList(u8) = .empty;
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    try run(cx, &listing, try lex.tokenize(a, "proc corr data=d cov csscp sscp alpha noprint outp=m;var x y z;run;", &d));
    const m = lib.find("m").?;
    try std.testing.expectEqual(@as(usize, 22), m.rowCount());
    try std.testing.expectEqualStrings("Intercept", m.columns.items[2].name);
    try std.testing.expectEqualStrings("Intercept", m.row(0)[1].str);
    try std.testing.expectEqual(@as(f64, 9), m.row(0)[2].num);
    try std.testing.expectEqual(@as(f64, 40), m.row(0)[3].num);
    try std.testing.expectEqual(@as(f64, 177), m.row(3)[3].num);
    try std.testing.expectEqualStrings("CSSCP", m.row(4)[0].str);
    try std.testing.expect(m.row(4)[2].isMissing());
    try std.testing.expectApproxEqAbs(@as(f64, 2.125), m.row(7)[5].num, 1e-10);
    try std.testing.expectEqualStrings("RAWALPHA", m.row(13)[0].str);
    try std.testing.expectApproxEqAbs(@as(f64, -0.508), m.row(13)[3].num, 0.0005);
    try std.testing.expectEqualStrings("STDCTDEL", m.row(18)[0].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.590), m.row(18)[5].num, 0.0005);
    const by = try a.create(Dataset);
    by.* = Dataset.init(a, "d");
    _ = try by.addColumn("site", .char);
    by.setLen("site", 8);
    by.setLabel("site", "Study site");
    for ([_][]const u8{ "x", "y" }) |v| _ = try by.addColumn(v, .num);
    for ([_][2]f64{ .{ 1, 3 }, .{ 2, 1 }, .{ 5, 4 }, .{ 3, 2 }, .{ 4, 6 }, .{ 7, 5 } }, 0..) |xy, i|
        try by.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = xy[0] }, .{ .num = xy[1] } });
    try lib.put("d", by);
    try run(cx, &listing, try lex.tokenize(a, "proc corr data=d noprint outp=b;by site;var y x;run;", &d));
    const b = lib.find("b").?;
    try std.testing.expectEqual(@as(usize, 10), b.rowCount());
    try std.testing.expectEqualStrings("Study site", b.columns.items[0].label.?);
    try std.testing.expectEqual(@as(?usize, 8), b.columns.items[0].len);
    try std.testing.expectEqualStrings("y", b.columns.items[3].name);
    try std.testing.expectEqualStrings("B", b.row(9)[0].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), b.row(9)[3].num, 1e-12);
}

test "CORR BEST selects absolute correlations and RANK preserves source matrices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "y", "z" }, &.{
        &.{ 1, 8, 4 }, &.{ 2, 6, 1 }, &.{ 2, 6, 5 }, &.{ 3, 2, 2 }, &.{ 4, 5, 6 },
        &.{ 5, 3, 2 }, &.{ 6, 1, 5 }, &.{ 8, 4, 8 }, &.{ 9, 1, 3 },
    });
    const result = try Testing.analyze(a, ds, "proc corr data=d best=2 nosimple; var x y z; run;");
    var out: std.ArrayList(u8) = .empty;
    try render(a, &out, result);
    for ([_][]const u8{ "x x y\nr 1.00000 -0.73193", "y y x\nr 1.00000 -0.73193", "z z x\nr 1.00000 0.34076" }) |line|
        try std.testing.expect(std.mem.indexOf(u8, out.items, line) != null);
    try std.testing.expectEqual(@as(usize, 9), result.groups[0].pairs.len);

    out.clearRetainingCapacity();
    const rectangular = try Testing.analyze(a, ds, "proc corr data=d rank noprob nosimple; with x; var z y; run;");
    try render(a, &out, rectangular);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "x y z\nr -0.73193 0.34076\nN 9 9") != null);
    try std.testing.expectEqual(@as(usize, 2), rectangular.groups[0].pairs[0].column);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    const spec = try parse(.{ .arena = a, .lib = &lib, .diags = &d }, try lex.tokenize(a, "proc corr data=d best=0; var x y; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), spec.options.best);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(.warning, d.list.items[0].severity);
}

test "CORR nested ordinal listing respects native chi-square field width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "r", "c", "f" }, &.{ &.{ 0, 0, 7 }, &.{ 0, 1, 11 }, &.{ 1, 3, 17 } });
    const g = try Testing.analyze(a, ds, "proc corr polychoric(converge=1e-8);var r c;freq f;run;");
    var listing: std.ArrayList(u8) = .empty;
    try render(a, &listing, g);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "8.96292E-8 1.2448E14 <.0001 48.4914") != null);
}

test "CORR small Fisher bias displays the significant digits from manual example 2.4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const batch1 = @as(f64, 0.2208125944316187) / (2 * 149);
    const batch2 = @as(f64, 0.3369440964259697) / (2 * 149);
    try std.testing.expectEqualStrings("0.0007410", try smallEstimate(a, batch1));
    try std.testing.expectEqualStrings("-0.0007410", try smallEstimate(a, -batch1));
    try std.testing.expectEqualStrings("0.00113", try smallEstimate(a, batch2));
}

test "CORR Hoeffding listing suppresses perfect self-dependence but shows distinct variables and tied diagonals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.dataset(a, &.{ "x", "clone", "tied" }, &.{
        &.{ 1, 1, 2 }, &.{ 2, 2, 5 },  &.{ 3, 3, 5 },  &.{ 4, 4, 9 },
        &.{ 5, 5, 8 }, &.{ 6, 6, 13 }, &.{ 7, 7, 12 }, &.{ 8, 8, 17 },
    });
    const g = try Testing.analyze(a, ds, "proc corr hoeffding;var x clone tied;run;");
    var listing: std.ArrayList(u8) = .empty;
    try render(a, &listing, g);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "x x 1.00000 . 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "x clone 1.00000 <.0001 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing.items, "tied tied 0.87667 <.0001 8") != null);
}

test "CORR reversed item uses eight columns for negative Cronbach alpha" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("-.507921", try alphaStatistic(a, -0.507921));
    try std.testing.expectEqualStrings("-5.29412", try alphaStatistic(a, -5.294117647058823));
    try std.testing.expectEqualStrings("-5.46060", try alphaStatistic(a, -5.4606001));
}
