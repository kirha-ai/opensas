//! PROC HPGENSELECT declarations, variable roles, observation selection and
//! the default maximum likelihood fit without a SELECTION statement, SAS/STAT
//! 15.4 physical pp.4629-4638, 4652-4654 (STAT-HPGENSELECT-001).
//!
//! Only DISTRIBUTION=POISSON with the log link is fitted: the listing layout
//! is the one SAS 9.4 prints for the chapter's getStarted data and for the
//! invented data of tests/corpus/stat_hpgenselect001_*.sas. Every other
//! distribution or link, SELECTION, OUTPUT, PARTITION, PERFORMANCE, CODE,
//! RESTRICT, ZEROMODEL (later HPGENSELECT tickets and the shared
//! high-performance tickets STAT-HP-001..004) is a D-009 gap (rc 2) raised
//! before any listing text is written, as is every display outside the
//! verified layout.
//!
//! Formulas, with f the FREQ value and w the WEIGHT value (pp.4637, 4652):
//!   l(beta)  = sum f w [ y log(mu) - mu - log(y!) ],   mu = exp(x'beta)
//!   score    = sum f w (y - mu) x,  information = sum f w mu x x'
//!   Pearson  = sum f w (y - mu)^2 / mu,  DF = n - p
//!   AIC = -2l + 2p, AICC = -2l + 2pn/(n-p-1), BIC = -2l + p log(n)
//! with n the sum of frequencies used and p the number of nonaliased
//! parameters (checked against the SAS listing of the invented data).
//! ponytail: Newton-Raphson to the numerical maximum (relative step < 1e-11)
//! instead of SAS's ridged iterate stopped at GCONV=1E-8; with quadratic
//! convergence the two agree far below the printed decimals.
const std = @import("std");
const proc = @import("../proc.zig");
const hp = @import("hp_shared.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const glm = @import("genmod_fit.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const lgammaOf = @import("../functions.zig").lgammaOf;
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    response: usize,
    /// MODEL effects in statement order: one input column per main effect.
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    frequency: ?usize = null,
    weight: ?usize = null,
    ids: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    alpha: f64 = 0.05,
    noprint: bool = false,
    /// DISTRIBUTION= as written (only POISSON is fitted).
    distribution: ?[]const u8 = null,
    link: ?[]const u8 = null,

    pub fn isClass(self: Spec, index: usize) bool {
        return std.mem.indexOfScalar(usize, self.classes, index) != null;
    }
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC HPGENSELECT: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC HPGENSELECT: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC HPGENSELECT options (Table 59.1) whose effect is not
/// implemented: output, optimization, tolerance and format options.
const later_options = [_][]const u8{
    "namelen",   "corr",      "cov",      "itdetails", "itselect",   "itsummary", "noclprint", "nostderr",
    "absconv",   "abstol",    "absfconv", "absftol",   "absgconv",   "absgtol",   "fconv",     "ftol",
    "gconv",     "gtol",      "inest",    "lassorho",  "lassosteps", "maxiter",   "maxfunc",   "maxfu",
    "maxtime",   "miniter",   "minit",    "normalize", "outest",     "technique", "tech",      "xconv",
    "xtol",      "lassotol",  "singchol", "singsweep", "singular",   "fmtlibxml",
};
/// Documented MODEL options other than DISTRIBUTION= and LINK=.
const later_model_options = [_][]const u8{ "alpha", "cl", "dispersion", "phi", "initialphi", "noint", "offset", "samplefrac", "start", "include", "noinclude" };
/// Statements owned by later HPGENSELECT / shared HP tickets.
const later_statements = [_][]const u8{ "selection", "output", "partition", "code", "restrict", "zeromodel" };
const distributions = [_][]const u8{ "binary", "binomial", "gamma", "inversegaussian", "ig", "multinomial", "mult", "negativebinomial", "nb", "normal", "gaussian", "poisson", "tweedie", "zinb", "zip" };
const links = [_][]const u8{ "cloglog", "cll", "glogit", "identity", "id", "inverse", "reciprocal", "inverse2", "logit", "loglog", "log", "probit" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}

/// Variable names and numbered ranges (`c1-c5`) in t[from..to].
fn varList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, from: usize, to: usize, out: *std.ArrayList(usize)) diag.Error!void {
    var j = from;
    while (j < to) {
        if (!at(t, j, .name)) return gap(cx, lineOf(t, j), "effects or variable lists other than names and numbered ranges are not implemented", .{});
        if (at(t, j + 1, .minus) and at(t, j + 2, .name) and j + 2 < to) {
            var names: std.ArrayList([]const u8) = .empty;
            try parser.expandRange(cx.arena, &names, t[j].text, t[j + 2].text);
            for (names.items) |n| {
                const c = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, t[j].line, "Variable {s} not found.", .{n});
                try out.append(cx.arena, c);
            }
            j += 3;
        } else {
            try out.append(cx.arena, try column(cx, ds, t, j));
            j += 1;
        }
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .data_name = "", .response = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
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
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            // ALPHA= only affects confidence limits (MODEL CL, OUTPUT: gaps),
            // so the value is validated (0 < alpha < 1, p.4630) and recorded.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, t[i + 2].line, "PROC HPGENSELECT: ALPHA= must be between 0 and 1", .{});
            s.alpha = v;
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC HPGENSELECT: input dataset not found", .{});
    const upper = try std.ascii.allocUpperString(cx.arena, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') != null) upper else try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{upper});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "class")) {
            // p.4628: CLASS may repeat but must precede the MODEL statement.
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPGENSELECT: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| if (at(t, j, .slash) or at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
            var list: std.ArrayList(usize) = .empty;
            try varList(cx, ds, t, i + 1, end, &list);
            for (list.items) |c| if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
        } else if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, t[i].line, "more than one MODEL statement is not implemented", .{});
            model_seen = true;
            if (at(t, i + 2, .slash)) return gap(cx, t[i].line, "the events/trials response is not implemented", .{});
            if (at(t, i + 2, .lparen)) return gap(cx, t[i].line, "MODEL response options are not implemented", .{});
            s.response = try column(cx, ds, t, i + 1);
            if (!at(t, i + 2, .eq)) return invalid(cx, t, i + 2);
            var j = i + 3;
            while (j < end and !at(t, j, .slash)) j += 1;
            for (i + 3..j) |k| if (!at(t, k, .name) and !at(t, k, .minus)) return gap(cx, t[k].line, "MODEL effects other than main effects are not implemented", .{});
            try varList(cx, ds, t, i + 3, j, &effects);
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, end);
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const opt = t[j].text;
                    if (oneOf(opt, &.{ "distribution", "dist", "d", "link" }) and at(t, j + 1, .eq) and at(t, j + 2, .name)) {
                        const value = t[j + 2].text;
                        if (eq(opt, "link")) {
                            if (!oneOf(value, &links)) return invalid(cx, t, j + 2);
                            s.link = value;
                        } else {
                            if (!oneOf(value, &distributions)) return invalid(cx, t, j + 2);
                            s.distribution = value;
                        }
                        j += 3;
                    } else if (oneOf(opt, &later_model_options)) {
                        return gap(cx, t[j].line, "MODEL option {s} is not implemented", .{opt});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "id")) {
            // p.4638: ID variables are copied to the OUTPUT data set only; the
            // OUTPUT statement is a gap, so they are validated and recorded.
            if (end == i + 1) return invalid(cx, t, end);
            try varList(cx, ds, t, i + 1, end, &ids);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "performance")) {
            // Shared single-machine PERFORMANCE contract (STAT-HP-001).
            var perf: hp.Performance = .{};
            try hp.parsePerformance(cx.diags, "HPGENSELECT", t, i, end, &perf);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted CLASS levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC HPGENSELECT: MODEL statement required", .{});
    s.classes = classes.items;
    s.effects = effects.items;
    s.ids = ids.items;
    if (s.isClass(s.response)) return gap(cx, 0, "a CLASS response (binary or multinomial model) is not implemented", .{});
    if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC HPGENSELECT: response variable {s} must be numeric", .{ds.columns.items[s.response].name});
    for (s.effects, 0..) |c, k| {
        if (c == s.response) return cx.diags.fail(error.ParseError, 0, "PROC HPGENSELECT: the response variable cannot be a MODEL effect", .{});
        if (!s.isClass(c) and ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC HPGENSELECT: character variable {s} must be a CLASS variable", .{ds.columns.items[c].name});
        if (std.mem.indexOfScalar(usize, s.effects[0..k], c) != null) return gap(cx, 0, "repeated MODEL effect policy is not verified", .{});
    }
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPGENSELECT: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| !std.math.isFinite(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// One CLASS level: its displayed text and, for numeric variables, its value.
const Level = struct { text: []const u8, value: f64 = 0 };
fn levelLess(_: void, x: Level, y: Level) bool {
    return if (x.value != y.value) x.value < y.value else std.mem.order(u8, x.text, y.text) == .lt;
}

pub const Fit = struct {
    beta: []f64,
    se: []f64,
    aliased: []bool,
    neg2ll: f64,
    pearson: f64,
    rank: usize,
};

/// One analysis (BY group) after observation selection.
pub const Analysis = struct {
    read: usize,
    used: usize,
    freq_read: f64 = 0,
    freq_used: f64 = 0,
    /// Sorted levels per CLASS variable, in CLASS statement order.
    levels: []const []const Level,
    labels: []const []const u8 = &.{},
    fit: ?Fit = null,
    /// Sum of frequencies used: the observation count of the criteria.
    n: f64 = 0,
};

fn levelText(a: A, v: Value) ![]const u8 {
    return switch (v) {
        .str => |text| std.mem.trimEnd(u8, text, " "),
        .num => proc.cellText(a, v),
    };
}

/// Observation selection, pp.4637, 4652-4654: an observation with a missing
/// response, explanatory or CLASS variable, a FREQ value below 1 or missing,
/// or a nonpositive or missing WEIGHT is not used; FREQ values are truncated.
/// CLASS effects use the GLM parameterization (p.4629): one column per sorted
/// level, the last aliased with the intercept.
pub fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Analysis {
    const a = cx.arena;
    const ds = s.input.ds;
    var used: std.ArrayList(usize) = .empty;
    var fw: std.ArrayList(f64) = .empty;
    var result: Analysis = .{ .read = rows.len, .used = 0, .levels = &.{} };
    rows: for (rows, 0..) |row, r| {
        var f: f64 = 1;
        if (s.frequency) |c| {
            const v = row[c].num;
            f = if (std.math.isFinite(v)) @trunc(v) else 0;
            // Sum of Frequencies Read adds the usable (>= 1) values (SAS
            // listing of tests/corpus/stat_hpgenselect001_freq.sas).
            if (f >= 1) result.freq_read += f;
            if (f < 1) continue;
        }
        var w: f64 = 1;
        if (s.weight) |c| {
            w = row[c].num;
            if (!(std.math.isFinite(w) and w > 0)) continue;
        }
        if (missing(row[s.response])) continue;
        for (s.effects) |c| if (missing(row[c])) continue :rows;
        for (s.classes) |c| if (missing(row[c])) continue :rows;
        try used.append(a, r);
        try fw.append(a, f * w);
        result.freq_used += f;
    }
    result.used = used.items.len;
    result.n = result.freq_used;
    const levels = try a.alloc([]const Level, s.classes.len);
    for (s.classes, levels) |c, *out| {
        const info = ds.columns.items[c];
        if (info.format != null) return gap(cx, 0, "formatted CLASS variables are not implemented", .{});
        var list: std.ArrayList(Level) = .empty;
        for (used.items) |r| {
            const v = rows[r][c];
            if (v == .num and (v.num != @trunc(v.num) or @abs(v.num) >= 1e10)) return gap(cx, 0, "noninteger numeric CLASS levels are not implemented", .{});
            const level: Level = .{ .text = try levelText(a, v), .value = if (v == .num) v.num else 0 };
            var found = false;
            for (list.items) |known| found = found or std.mem.eql(u8, known.text, level.text);
            if (!found) try list.append(a, level);
        }
        std.mem.sort(Level, list.items, {}, levelLess);
        out.* = list.items;
    }
    result.levels = levels;
    if (used.items.len == 0) return result;
    var labels: std.ArrayList([]const u8) = .empty;
    try labels.append(a, "Intercept");
    for (s.effects) |c| {
        const nm = ds.columns.items[c].name;
        if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
            for (levels[k]) |level| try labels.append(a, try std.fmt.allocPrint(a, "{s} {s}", .{ nm, level.text }));
        } else try labels.append(a, nm);
    }
    result.labels = labels.items;
    const p = labels.items.len;
    const n = used.items.len;
    const x = try a.alloc(f64, n * p);
    const y = try a.alloc(f64, n);
    for (used.items, 0..) |r, row_ix| {
        const xr = x[row_ix * p ..][0..p];
        xr[0] = 1;
        var j: usize = 1;
        for (s.effects) |c| {
            if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
                const v = try levelText(a, rows[r][c]);
                for (levels[k]) |level| {
                    xr[j] = if (std.mem.eql(u8, v, level.text)) 1 else 0;
                    j += 1;
                }
            } else {
                xr[j] = rows[r][c].num;
                j += 1;
            }
        }
        y[row_ix] = rows[r][s.response].num;
        if (y[row_ix] < 0) return gap(cx, 0, "negative Poisson response values are not implemented", .{});
    }
    result.fit = try poisson(cx, x, y, fw.items, p);
    return result;
}

/// Columns aliased by a sequential (in design order) Cholesky sweep of the
/// weighted crossproducts: the GLM-parameterization generalized inverse.
fn aliasedColumns(a: A, x: []const f64, fw: []const f64, p: usize) ![]bool {
    const g = try a.alloc(f64, p * p);
    @memset(g, 0);
    for (fw, 0..) |w, r| {
        const xr = x[r * p ..][0..p];
        for (0..p) |j| for (0..p) |k| {
            g[j * p + k] += w * xr[j] * xr[k];
        };
    }
    const out = try a.alloc(bool, p);
    const l = try a.alloc(f64, p * p);
    @memset(l, 0);
    for (0..p) |j| {
        var d = g[j * p + j];
        for (0..j) |k| if (!out[k]) {
            d -= l[j * p + k] * l[j * p + k];
        };
        out[j] = !(g[j * p + j] > 0) or !(d > 1e-9 * g[j * p + j]);
        if (out[j]) continue;
        const root = @sqrt(d);
        l[j * p + j] = root;
        for (j + 1..p) |i| {
            var v = g[i * p + j];
            for (0..j) |k| if (!out[k]) {
                v -= l[i * p + k] * l[j * p + k];
            };
            l[i * p + j] = v / root;
        }
    }
    return out;
}

fn poisson(cx: proc.ProcCtx, x: []const f64, y: []const f64, fw: []const f64, p: usize) diag.Error!Fit {
    const a = cx.arena;
    const aliased = try aliasedColumns(a, x, fw, p);
    var keep: std.ArrayList(usize) = .empty;
    for (aliased, 0..) |al, j| if (!al) try keep.append(a, j);
    const q = keep.items.len;
    const beta = try a.alloc(f64, q);
    @memset(beta, 0);
    var sw: f64 = 0;
    var swy: f64 = 0;
    for (fw, y) |w, v| {
        sw += w;
        swy += w * v;
    }
    if (!(swy > 0) or aliased[0]) return gap(cx, 0, "a Poisson fit with an all-zero response or without an intercept is not implemented", .{});
    beta[0] = @log(swy / sw);
    const h = try a.alloc(f64, q * q);
    const g = try a.alloc(f64, q);
    const mu = try a.alloc(f64, y.len);
    var converged = false;
    var iter: usize = 0;
    while (iter < 100) : (iter += 1) {
        @memset(h, 0);
        @memset(g, 0);
        for (y, fw, 0..) |v, w, r| {
            const xr = x[r * p ..][0..p];
            var eta: f64 = 0;
            for (keep.items, 0..) |j, k| eta += xr[j] * beta[k];
            const m = @exp(eta);
            mu[r] = m;
            for (keep.items, 0..) |j, k| {
                g[k] += w * (v - m) * xr[j];
                for (keep.items, 0..) |jj, kk| h[k * q + kk] += w * m * xr[j] * xr[jj];
            }
        }
        if (converged) break;
        if (!glm.cholesky(h, q)) return gap(cx, 0, "a singular or nonconvergent Poisson fit is not implemented", .{});
        glm.choleskySolve(h, q, g);
        var big: f64 = 0;
        for (beta, g) |*b, step| {
            b.* += step;
            big = @max(big, @abs(step) / @max(1, @abs(b.*)));
        }
        if (!std.math.isFinite(big)) break;
        if (big < 1e-11) converged = true;
    }
    if (!converged) return gap(cx, 0, "the Poisson fit did not converge (separation or quasi-complete fit not implemented)", .{});
    // h now holds the information at the estimate (refreshed after the
    // final step); invert it column by column.
    if (!glm.cholesky(h, q)) return gap(cx, 0, "a singular Poisson information matrix is not implemented", .{});
    const full_beta = try a.alloc(f64, p);
    const se = try a.alloc(f64, p);
    @memset(full_beta, 0);
    @memset(se, 0);
    const e = try a.alloc(f64, q);
    for (keep.items, 0..) |j, k| {
        @memset(e, 0);
        e[k] = 1;
        glm.choleskySolve(h, q, e);
        se[j] = @sqrt(e[k]);
        full_beta[j] = beta[k];
    }
    var ll: f64 = 0;
    var pearson: f64 = 0;
    for (y, fw, mu) |v, w, m| {
        ll += w * ((if (v > 0) v * @log(m) else 0) - m - lgammaOf(v + 1));
        pearson += w * (v - m) * (v - m) / m;
    }
    return .{ .beta = full_beta, .se = se, .aliased = aliased, .neg2ll = -2 * ll, .pearson = pearson, .rank = q };
}

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
/// Centered table title; `spaced` tables get the " " spacer line SAS prints
/// above column headings.
fn title(a: A, out: *Out, text: []const u8, width: usize, spaced: bool) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, if (spaced) "\n \n" else "\n\n");
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else fixed(a, p, 4);
}

/// Fit Statistics values: 4 decimals below 100 and 2 from 100 to 1000 in
/// the SAS listings; other magnitudes are not verified (see `check`).
fn statText(a: A, v: f64) ![]const u8 {
    return fixed(a, v, if (@abs(v) < 100) 4 else 2);
}

const Criteria = struct { neg2ll: f64, aic: f64, aicc: f64, bic: f64, pearson: f64, pearson_df: f64 };
fn criteria(an: Analysis) Criteria {
    const f = an.fit.?;
    const n = an.n;
    const p: f64 = @floatFromInt(f.rank);
    return .{
        .neg2ll = f.neg2ll,
        .aic = f.neg2ll + 2 * p,
        .aicc = f.neg2ll + 2 * p * n / (n - p - 1),
        .bic = f.neg2ll + p * @log(n),
        .pearson = f.pearson,
        .pearson_df = f.pearson / (n - p),
    };
}

fn inRange(v: f64, lo: f64, hi: f64) bool {
    return @abs(v) >= lo and @abs(v) < hi;
}

/// Listing boundary: values and shapes outside the verified layout are
/// raised before any text is written.
fn check(cx: proc.ProcCtx, s: Spec, an: Analysis) diag.Error!void {
    if (an.used == 0) return gap(cx, 0, "the result for a BY group or data set without usable observations is not verified", .{});
    const f = an.fit.?;
    for (an.labels) |label| if (label.len > 20) return gap(cx, 0, "parameter names longer than 20 characters (NAMELEN=) are not implemented", .{});
    var j: usize = 1;
    for (s.effects) |c| {
        if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
            for (an.levels[k], 0..) |_, level| {
                if (f.aliased[j] != (level + 1 == an.levels[k].len)) return gap(cx, 0, "linearly dependent effects are not implemented", .{});
                j += 1;
            }
        } else {
            if (f.aliased[j]) return gap(cx, 0, "linearly dependent effects are not implemented", .{});
            j += 1;
        }
    }
    const p: f64 = @floatFromInt(f.rank);
    if (an.n < p + 2) return gap(cx, 0, "fit criteria without enough degrees of freedom are not verified", .{});
    const x = criteria(an);
    for ([_]f64{ x.neg2ll, x.aic, x.aicc, x.bic, x.pearson, x.pearson_df }) |v| if (!inRange(v, 0.1, 1000)) return gap(cx, 0, "display of fit statistics outside [0.1, 1000) is not verified", .{});
    for (f.beta, f.se, f.aliased) |b, se, al| if (!al) {
        const chi = (b / se) * (b / se);
        if (!(inRange(b, 0.001, 1000) and inRange(se, 0.001, 1000) and chi < 1000)) return gap(cx, 0, "display of parameter estimates outside the verified range is not implemented", .{});
    };
}

fn infoTable(a: A, out: *Out, heading: []const u8, lines: []const [2][]const u8) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (lines) |l| {
        lw = @max(lw, l[0].len);
        vw = @max(vw, l[1].len);
    }
    try title(a, out, heading, lw + 4 + vw, false);
    for (lines) |l| {
        try left(a, out, l[0], lw + 4);
        try left(a, out, l[1], vw);
        try out.append(a, '\n');
    }
}

fn header(cx: proc.ProcCtx, out: *Out, s: Spec) !void {
    const a = cx.arena;
    try out.appendSlice(a, "\nThe HPGENSELECT Procedure\n\n");
    // Shared single-machine tables (STAT-HP-001): one truthful thread.
    try hp.performanceInfo(a, out);
    try hp.dataAccessInfo(a, out, s.data_name);
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, an: Analysis) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    var lines: std.ArrayList([2][]const u8) = .empty;
    try lines.append(a, .{ "Data Source", s.data_name });
    try lines.append(a, .{ "Response Variable", ds.columns.items[s.response].name });
    if (s.frequency) |c| try lines.append(a, .{ "Frequency Variable", ds.columns.items[c].name });
    if (s.weight) |c| try lines.append(a, .{ "Weight Variable", ds.columns.items[c].name });
    if (s.classes.len > 0) try lines.append(a, .{ "Class Parameterization", "GLM" });
    try lines.append(a, .{ "Distribution", "Poisson" });
    try lines.append(a, .{ "Link Function", "Log" });
    try lines.append(a, .{ "Optimization Technique", "Newton-Raphson with Ridging" });
    try infoTable(a, out, "Model Information", lines.items);
    try out.print(a, "\n\nNumber of Observations Read{d:>16}\nNumber of Observations Used{d:>16}\n", .{ an.read, an.used });
    if (s.frequency != null) try out.print(a, "Sum of Frequencies Read    {d:>16}\nSum of Frequencies Used    {d:>16}\n", .{ @as(u64, @intFromFloat(an.freq_read)), @as(u64, @intFromFloat(an.freq_used)) });
    if (s.classes.len > 0) {
        var name_width: usize = 5;
        var value_width: usize = 6;
        const values = try a.alloc([]const u8, s.classes.len);
        for (s.classes, an.levels, values) |c, levels, *text| {
            name_width = @max(name_width, ds.columns.items[c].name.len);
            var joined: Out = .empty;
            for (levels) |level| try joined.print(a, "{s} ", .{level.text});
            text.* = joined.items;
            value_width = @max(value_width, text.len);
        }
        try out.appendSlice(a, "\n\n");
        try title(a, out, "Class Level Information", name_width + 14 + value_width, true);
        try left(a, out, "Class", name_width);
        try out.appendSlice(a, "    Levels    Values\n\n");
        for (s.classes, an.levels, values) |c, levels, text| {
            try left(a, out, ds.columns.items[c].name, name_width);
            try out.print(a, "{d:>10}    ", .{levels.len});
            try left(a, out, text, value_width);
            try out.append(a, '\n');
        }
    }
    const f = an.fit.?;
    try out.print(a, "\n\n           Dimensions\n\nNumber of Effects   {d:>12}\nNumber of Parameters{d:>12}\nColumns in X        {d:>12}\n\n\n", .{ s.effects.len + 1, f.rank, an.labels.len });
    const x = criteria(an);
    try out.appendSlice(a, "              Fit Statistics\n\n");
    const stats = [_]struct { []const u8, f64 }{
        .{ "-2 Log Likelihood", x.neg2ll },         .{ "AIC (smaller is better)", x.aic }, .{ "AICC (smaller is better)", x.aicc },
        .{ "BIC (smaller is better)", x.bic },      .{ "Pearson Chi-Square", x.pearson },  .{ "Pearson Chi-Square/DF", x.pearson_df },
    };
    for (stats) |line| {
        try left(a, out, line[0], 32);
        try right(a, out, try statText(a, line[1]), 10);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    var pw: usize = 9;
    for (an.labels) |label| pw = @max(pw, label.len);
    try title(a, out, "Parameter Estimates", pw + 66, true);
    try out.appendNTimes(a, ' ', pw + 30);
    try out.appendSlice(a, "Standard\n");
    try left(a, out, "Parameter", pw);
    try out.appendSlice(a, "    DF        Estimate           Error    Chi-Square    Pr > ChiSq\n\n");
    for (an.labels, 0..) |label, j| {
        try left(a, out, label, pw);
        if (f.aliased[j]) {
            try out.appendSlice(a, "     0               0               .         .             .    \n");
            continue;
        }
        const chi = (f.beta[j] / f.se[j]) * (f.beta[j] / f.se[j]);
        try out.appendSlice(a, "     1");
        try right(a, out, try fixed(a, f.beta[j], 6), 16);
        try right(a, out, try fixed(a, f.se[j], 6), 16);
        try right(a, out, try fixed(a, chi, 4), 14);
        try right(a, out, try pvalue(a, chiTail(chi, 1)), 14);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n         Convergence criterion (GCONV=1E-8) satisfied.          \n");
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, 0, "graphs under ODS GRAPHICS are not implemented", .{});
    const dist = s.distribution orelse return gap(cx, 0, "the default DISTRIBUTION=NORMAL fit is not implemented", .{});
    if (!eq(dist, "poisson")) return gap(cx, 0, "DISTRIBUTION={s} is not implemented", .{dist});
    if (s.link) |l| if (!eq(l, "log")) return gap(cx, 0, "LINK={s} for the Poisson distribution is not implemented", .{l});
    if (s.effects.len == 0) return gap(cx, 0, "an intercept-only MODEL statement is not verified", .{});
    if (s.frequency != null and s.weight != null) return gap(cx, 0, "the listing with both FREQ and WEIGHT statements is not verified", .{});
    const ds = s.input.ds;
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    const results = try a.alloc(Analysis, slices.len);
    for (slices, results) |slice, *an| {
        an.* = try analyze(cx, s, slice.rows);
        if (!s.noprint) try check(cx, s, an.*);
    }
    try cx.diags.note(0, "The HPGENSELECT procedure is executing in single-machine mode.", .{});
    for (slices) |slice| {
        try cx.diags.note(0, "Convergence criterion (GCONV=1E-8) satisfied.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, slice.rows[0], s.by_cols);
    }
    if (s.noprint) return;
    var body: Out = .empty;
    try header(cx, &body, s);
    for (slices, results) |slice, an| {
        if (s.by_cols.len > 0) {
            try body.append(a, '\n');
            for (s.by_cols, 0..) |c, k| try body.print(a, "{s}{s}={s}", .{ if (k > 0) " " else "", ds.columns.items[c].name, try proc.cellText(a, slice.rows[0][c]) });
            try body.appendSlice(a, "\n\nThe HPGENSELECT Procedure\n\n");
        } else try body.appendSlice(a, "\n\n");
        try render(cx, &body, s, an);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("hpgenselect_tests.zig");
}
