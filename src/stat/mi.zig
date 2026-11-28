//! PROC MI declarations, variable roles, observation selection and the
//! deterministic part of the listing (Model Information, Missing Data
//! Patterns, SIMPLE statistics, EM maximum likelihood estimates), SAS/STAT
//! 15.4 physical pp.6425-6431, 6436, 6448-6453. Imputation draws random
//! numbers and belongs to later MI tickets: every path that would need the
//! SAS stream, and every listing shape not proven against the SAS reference,
//! is a D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Em = struct {
    itprint: bool = false,
    outem: ?[]const u8 = null,
    maxiter: usize = 200,
    converge: f64 = 1e-4,
};

pub const Spec = struct {
    input: proc.ProcInput,
    vars: []const usize = &.{},
    frequency: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    simple: bool = false,
    noprint: bool = false,
    /// Null when NIMPUTE= is omitted (the documented default imputes).
    nimpute: ?usize = null,
    seed: ?i64 = null,
    em: ?Em = null,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC MI: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC MI: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
/// Documented PROC MI statement options (physical pp.6425-6429) owned by
/// later MI tickets.
const later_options = [_][]const u8{ "out", "alpha", "mu0", "theta0", "minimum", "maximum", "round", "minmaxiter", "singular" };
const later_statements = [_][]const u8{ "class", "fcs", "mcmc", "mnar", "monotone", "transform" };
const later_em_options = [_][]const u8{ "initial", "outiter" };

fn number(t: []const lex.Token, i: usize) ?f64 {
    if (!at(t, i, .number)) return null;
    return std.fmt.parseFloat(f64, t[i].text) catch null;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
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
        } else if (eq(word, "simple")) {
            s.simple = true;
            i += 1;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "nimpute") and at(t, i + 1, .eq)) {
            if (kw(t, i + 2, "percentmissing")) return gap(cx, t[i].line, "NIMPUTE=PERCENTMISSING is not implemented", .{});
            const x = number(t, i + 2) orelse return invalid(cx, t, i + 2);
            if (x != @trunc(x) or x > 1e9) return invalid(cx, t, i + 2);
            s.nimpute = @intFromFloat(x);
            i += 3;
        } else if (eq(word, "seed") and at(t, i + 1, .eq)) {
            var j = i + 2;
            var sign: f64 = 1;
            if (at(t, j, .minus)) {
                sign = -1;
                j += 1;
            }
            const x = number(t, j) orelse return invalid(cx, t, j);
            if (x != @trunc(x) or x > 2147483647) return invalid(cx, t, j);
            s.seed = @intFromFloat(sign * x);
            i = j + 1;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC MI: input dataset not found", .{});
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
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "var")) {
            if (var_seen) return gap(cx, t[i].line, "duplicate VAR statement policy is not verified", .{});
            var_seen = true;
            var j = i + 1;
            if (j == end) return invalid(cx, t, end);
            while (j < end) {
                const line = t[j].line;
                for (try lists.next(cx.arena, ds, t[0..end], &j, cx.diags)) |n| {
                    const c = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{n});
                    if (std.mem.indexOfScalar(usize, vars.items, c) != null) return gap(cx, line, "repeated VAR variable policy is not verified", .{});
                    try vars.append(cx.arena, c);
                }
            }
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            const c = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC MI: FREQ variable {s} must be numeric", .{t[i + 1].text});
            s.frequency = c;
        } else if (kw(t, i, "em")) {
            if (s.em != null) return gap(cx, t[i].line, "duplicate EM statement policy is not verified", .{});
            var em_options: Em = .{};
            var j = i + 1;
            while (j < end) {
                if (kw(t, j, "itprint")) {
                    em_options.itprint = true;
                    j += 1;
                } else if (kw(t, j, "outem") and at(t, j + 1, .eq)) {
                    if (!at(t, j + 2, .name)) return invalid(cx, t, j + 2);
                    em_options.outem = t[j + 2].text;
                    j += 3;
                    if (at(t, j, .dot)) {
                        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                        em_options.outem = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ em_options.outem.?, t[j + 1].text });
                        j += 2;
                    }
                    if (at(t, j, .lparen)) return gap(cx, t[j].line, "OUTEM= data set options are not implemented", .{});
                } else if (kw(t, j, "maxiter") and at(t, j + 1, .eq)) {
                    const x = number(t, j + 2) orelse return invalid(cx, t, j + 2);
                    if (x != @trunc(x) or x < 1 or x > 1e9) return invalid(cx, t, j + 2);
                    em_options.maxiter = @intFromFloat(x);
                    j += 3;
                } else if ((kw(t, j, "converge") or kw(t, j, "xconv")) and at(t, j + 1, .eq)) {
                    const x = number(t, j + 2) orelse return invalid(cx, t, j + 2);
                    if (!(x > 0 and x < 1)) return cx.diags.fail(error.ParseError, t[j].line, "PROC MI: CONVERGE= must be between 0 and 1", .{});
                    em_options.converge = x;
                    j += 3;
                } else if (at(t, j, .name) and oneOf(t[j].text, &later_em_options)) {
                    return gap(cx, t[j].line, "EM option {s} is not implemented", .{t[j].text});
                } else return invalid(cx, t, j);
            }
            s.em = em_options;
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (var_seen) {
        for (vars.items) |c| {
            const info = ds.columns.items[c];
            // A character analysis variable needs CLASS, which needs FCS or MONOTONE.
            if (info.type != .num) return cx.diags.fail(error.ParseError, 0, "PROC MI: variable {s} in the VAR statement is character and is not a CLASS variable", .{info.name});
            if (s.frequency == c or std.mem.indexOfScalar(usize, cols, c) != null) return gap(cx, 0, "an analysis variable that is also a BY or FREQ variable is not verified", .{});
        }
    } else {
        // Physical p.6448: all continuous variables not named in other statements.
        for (ds.columns.items, 0..) |info, c| {
            if (info.type != .num or s.frequency == c or std.mem.indexOfScalar(usize, cols, c) != null) continue;
            try vars.append(cx.arena, c);
        }
    }
    if (vars.items.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC MI: no analysis variables", .{});
    if (vars.items.len > 64) return gap(cx, 0, "more than 64 analysis variables are not implemented", .{});
    s.vars = vars.items;
    return s;
}

/// The analysis observations of one BY group: one row of `p` values per used
/// observation (NaN = missing) and its integer frequency.
pub const Selected = struct {
    x: []const []const f64,
    w: []const f64,
    /// Observations whose analysis variables are all missing.
    empty: usize,
};

/// Physical p.6436: only the integer part of FREQ is used and a value below 1
/// (or missing) drops the observation. Special missing values are missing.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    var x: std.ArrayList([]const f64) = .empty;
    var w: std.ArrayList(f64) = .empty;
    var empty: usize = 0;
    for (rows) |row| {
        var f: f64 = 1;
        if (s.frequency) |c| {
            const raw = row[c].num;
            if (!std.math.isFinite(raw) or raw < 1) continue;
            f = @trunc(raw);
        }
        const values = try a.alloc(f64, s.vars.len);
        var any = false;
        for (s.vars, values) |c, *v| {
            const raw = row[c].num;
            v.* = if (std.math.isFinite(raw)) raw else std.math.nan(f64);
            any = any or std.math.isFinite(raw);
        }
        if (!any) empty += 1;
        try x.append(a, values);
        try w.append(a, f);
    }
    return .{ .x = x.items, .w = w.items, .empty = empty };
}

pub const Pattern = struct { mask: u64, freq: f64, means: []f64 };
fn observed(mask: u64, j: usize) bool {
    return mask & (@as(u64, 1) << @intCast(j)) != 0;
}
fn patternLess(p: usize, l: Pattern, r: Pattern) bool {
    for (0..p) |j| {
        const lo = observed(l.mask, j);
        if (lo != observed(r.mask, j)) return lo;
    }
    return false;
}
fn maskOf(row: []const f64) u64 {
    var m: u64 = 0;
    for (row, 0..) |v, j| {
        if (!std.math.isNan(v)) m |= @as(u64, 1) << @intCast(j);
    }
    return m;
}

/// Physical p.6452: observations grouped by which analysis variables are
/// observed; the variable order orders the groups, observed before missing.
pub fn patterns(a: A, p: usize, sel: Selected) ![]Pattern {
    var list: std.ArrayList(Pattern) = .empty;
    for (sel.x, sel.w) |row, f| {
        const mask = maskOf(row);
        const slot = for (list.items) |*item| {
            if (item.mask == mask) break item;
        } else blk: {
            const means = try a.alloc(f64, p);
            @memset(means, 0);
            try list.append(a, .{ .mask = mask, .freq = 0, .means = means });
            break :blk &list.items[list.items.len - 1];
        };
        slot.freq += f;
        for (row, slot.means) |v, *m| {
            if (!std.math.isNan(v)) m.* += f * v;
        }
    }
    for (list.items) |item| for (item.means) |*m| {
        m.* /= item.freq;
    };
    std.mem.sort(Pattern, list.items, p, patternLess);
    return list.items;
}

pub const Univariate = struct { n: f64, mean: f64, sd: f64, min: f64, max: f64 };
/// Available-case statistics, physical p.6449 (divisor n_j - 1).
pub fn univariate(sel: Selected, j: usize) Univariate {
    var u: Univariate = .{ .n = 0, .mean = 0, .sd = std.math.nan(f64), .min = std.math.inf(f64), .max = -std.math.inf(f64) };
    for (sel.x, sel.w) |row, f| {
        if (std.math.isNan(row[j])) continue;
        u.n += f;
        u.mean += f * row[j];
        u.min = @min(u.min, row[j]);
        u.max = @max(u.max, row[j]);
    }
    if (u.n == 0) return u;
    u.mean /= u.n;
    var ss: f64 = 0;
    for (sel.x, sel.w) |row, f| {
        if (!std.math.isNan(row[j])) ss += f * (row[j] - u.mean) * (row[j] - u.mean);
    }
    if (u.n > 1) u.sd = @sqrt(ss / (u.n - 1));
    return u;
}

/// Pearson correlation over the observations where both variables are
/// observed; null when it is undefined.
pub fn pairwise(sel: Selected, j: usize, k: usize) ?f64 {
    var n: f64 = 0;
    var mj: f64 = 0;
    var mk: f64 = 0;
    for (sel.x, sel.w) |row, f| {
        if (std.math.isNan(row[j]) or std.math.isNan(row[k])) continue;
        n += f;
        mj += f * row[j];
        mk += f * row[k];
    }
    if (n < 2) return null;
    mj /= n;
    mk /= n;
    var sjj: f64 = 0;
    var skk: f64 = 0;
    var sjk: f64 = 0;
    for (sel.x, sel.w) |row, f| {
        if (std.math.isNan(row[j]) or std.math.isNan(row[k])) continue;
        sjj += f * (row[j] - mj) * (row[j] - mj);
        skk += f * (row[k] - mk) * (row[k] - mk);
        sjk += f * (row[j] - mj) * (row[k] - mk);
    }
    if (!(sjj > 0 and skk > 0)) return null;
    return sjk / @sqrt(sjj * skk);
}

pub const Iteration = struct { neg2ll: f64, mean: []const f64 };
pub const EmResult = struct {
    initial_mean: []const f64,
    initial_cov: []const f64,
    history: []const Iteration,
    mean: []const f64,
    cov: []const f64,
    iterations: usize,
    converged: bool,
};
/// ponytail: a sweep pivot at or below 1e-8 of its diagonal is treated as a
/// singular covariance and reported, not regularised (SINGULAR= is a later
/// ticket).
const singular_tolerance: f64 = 1e-8;

/// One E step under (mu, cov): accumulates the expected sufficient statistics
/// and returns the observed-data -2 log likelihood without its constant,
/// sum_i f_i (log|S_oo| + (y_o - mu_o)' S_oo^-1 (y_o - mu_o)), physical p.6450.
fn expectation(a: A, p: usize, sel: Selected, mu: []const f64, cov: []const f64, t1: []f64, t2: []f64) !f64 {
    const m = try a.alloc(f64, p * p);
    const y = try a.alloc(f64, p);
    @memset(t1, 0);
    @memset(t2, 0);
    var total: f64 = 0;
    for (sel.x, sel.w) |row, f| {
        @memcpy(m, cov);
        var logdet: f64 = 0;
        for (0..p) |k| {
            if (std.math.isNan(row[k])) continue;
            const d = m[k * p + k];
            if (!(d > singular_tolerance * cov[k * p + k])) return error.Singular;
            logdet += @log(d);
            for (0..p) |i| {
                if (i == k) continue;
                for (0..p) |j| {
                    if (j != k) m[i * p + j] -= m[i * p + k] * m[k * p + j] / d;
                }
            }
            for (0..p) |i| {
                if (i == k) continue;
                m[i * p + k] /= d;
                m[k * p + i] /= d;
            }
            m[k * p + k] = -1 / d;
        }
        var quad: f64 = 0;
        for (0..p) |i| {
            if (std.math.isNan(row[i])) continue;
            for (0..p) |j| {
                if (!std.math.isNan(row[j])) quad -= (row[i] - mu[i]) * m[i * p + j] * (row[j] - mu[j]);
            }
        }
        total += f * (logdet + quad);
        for (0..p) |i| {
            if (!std.math.isNan(row[i])) {
                y[i] = row[i];
                continue;
            }
            y[i] = mu[i];
            for (0..p) |j| {
                if (!std.math.isNan(row[j])) y[i] += m[i * p + j] * (row[j] - mu[j]);
            }
        }
        for (0..p) |i| {
            t1[i] += f * y[i];
            for (0..p) |j| {
                const residual = if (std.math.isNan(row[i]) and std.math.isNan(row[j])) m[i * p + j] else 0;
                t2[i * p + j] += f * (y[i] * y[j] + residual);
            }
        }
    }
    return total;
}

/// EM maximum likelihood for multivariate normal data with missing values,
/// physical pp.6450-6451, from the INITIAL=AC start (available-case means and
/// standard deviations, zero correlations). The M step divides by the total
/// frequency.
///
/// ponytail: the guide states the stopping rule (every mean and covariance
/// changes by less than CONVERGE, relatively when the parameter exceeds 0.01
/// in absolute value, else absolutely) without naming the scale. It is applied
/// here to the parameters of the data standardised by the starting means and
/// standard deviations, as in Schafer's (1997) EM that the chapter follows:
/// that is the scale on which the 0.01 rule is meaningful, and it reproduces
/// the SAS reference trajectory (12 iterations on the guide's Fitness1 data,
/// where the raw scale would stop at 10). Evidence is that single trajectory.
pub fn em(a: A, p: usize, sel: Selected, maxiter: usize, converge: f64) !EmResult {
    var n: f64 = 0;
    for (sel.w) |f| n += f;
    const mu = try a.alloc(f64, p);
    const cov = try a.alloc(f64, p * p);
    const scale = try a.alloc(f64, p);
    @memset(cov, 0);
    for (0..p) |j| {
        const u = univariate(sel, j);
        if (!(u.n > 1) or !(u.sd > 0)) return error.Singular;
        mu[j] = u.mean;
        cov[j * p + j] = u.sd * u.sd;
        scale[j] = u.sd;
    }
    const start = try a.dupe(f64, mu);
    const initial_cov = try a.dupe(f64, cov);
    const t1 = try a.alloc(f64, p);
    const t2 = try a.alloc(f64, p * p);
    var history: std.ArrayList(Iteration) = .empty;
    var converged = false;
    var iterations: usize = 0;
    while (true) {
        const ll = try expectation(a, p, sel, mu, cov, t1, t2);
        try history.append(a, .{ .neg2ll = ll, .mean = try a.dupe(f64, mu) });
        if (converged or iterations == maxiter) break;
        iterations += 1;
        converged = true;
        for (0..p) |i| {
            const next = t1[i] / n;
            if (!within((mu[i] - start[i]) / scale[i], (next - start[i]) / scale[i], converge)) converged = false;
            t1[i] = next;
        }
        for (0..p) |i| for (0..p) |j| {
            const next = t2[i * p + j] / n - t1[i] * t1[j];
            const unit = scale[i] * scale[j];
            if (!within(cov[i * p + j] / unit, next / unit, converge)) converged = false;
            cov[i * p + j] = next;
        };
        @memcpy(mu, t1);
    }
    return .{ .initial_mean = start, .initial_cov = initial_cov, .history = history.items, .mean = mu, .cov = cov, .iterations = iterations, .converged = converged };
}
fn within(old: f64, new: f64, criterion: f64) bool {
    const change = @abs(new - old);
    return (if (@abs(old) > 0.01) change / @abs(old) else change) < criterion;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn title(a: A, out: *Out, text: []const u8, width: usize, round_up: bool) !void {
    const room = if (width > text.len) width - text.len else 0;
    try out.appendNTimes(a, ' ', (room + @intFromBool(round_up)) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}
fn spanner(a: A, out: *Out, text: []const u8, width: usize) !void {
    const room = if (width > text.len) width - text.len else 0;
    try out.appendNTimes(a, '-', (room + 1) / 2);
    try out.appendSlice(a, text);
    try out.appendNTimes(a, '-', room / 2);
}
/// ponytail: the reference shows fixed decimals for magnitudes in [1, 1000)
/// (and a bare 0); how the listing formats react outside that range is not
/// verified, so such values are a gap instead of a guessed layout.
fn shown(x: f64) bool {
    return @abs(x) >= 1 and @abs(x) < 1000;
}

/// A pattern-table heading: a name with one lower-to-upper case boundary is
/// split there onto two lines (RunTime -> Run / Time), as in the reference.
const Heading = struct { top: []const u8 = "", bottom: []const u8, width: usize };
fn heading(name: []const u8) ?Heading {
    var cut: ?usize = null;
    for (1..name.len) |i| {
        if (std.ascii.isLower(name[i - 1]) and std.ascii.isUpper(name[i])) {
            if (cut != null) return null;
            cut = i;
        }
    }
    const c = cut orelse return .{ .bottom = name, .width = name.len };
    return .{ .top = name[0..c], .bottom = name[c..], .width = @max(c, name.len - c) };
}

const Computed = struct {
    sel: Selected,
    patterns: []const Pattern,
    total: f64,
    em: ?EmResult = null,
};

fn compute(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Computed {
    const a = cx.arena;
    const sel = try select(a, s, rows);
    if (sel.x.len == 0) return gap(cx, 0, "the result for a group without usable observations is not verified", .{});
    if (sel.empty > 0) return gap(cx, 0, "observations with every analysis variable missing are not verified", .{});
    var c: Computed = .{ .sel = sel, .patterns = try patterns(a, s.vars.len, sel), .total = 0 };
    for (sel.w) |f| c.total += f;
    if (s.em) |em_options| {
        c.em = em(a, s.vars.len, sel, em_options.maxiter, em_options.converge) catch |err| switch (err) {
            error.Singular => return gap(cx, 0, "EM with a singular covariance or a variable with fewer than two distinct observed values is not implemented", .{}),
            else => |e| return e,
        };
        if (!c.em.?.converged) return gap(cx, 0, "the EM result when the algorithm does not converge within MAXITER={d} iterations is not verified", .{em_options.maxiter});
    }
    return c;
}

fn estimates(a: A, out: *Out, names: []const []const u8, mean: []const f64, cov: []const f64) !void {
    const p = names.len;
    try out.appendSlice(a, "_TYPE_    _NAME_  ");
    for (names) |n| try padRight(a, out, n, 16);
    try out.appendSlice(a, "\n\nMEAN              ");
    for (mean) |x| try padRight(a, out, try fixed(a, x, 6), 16);
    try out.append(a, '\n');
    for (names, 0..) |n, i| {
        try out.appendSlice(a, "COV       ");
        try padLeft(a, out, n, 8);
        for (0..p) |j| try padRight(a, out, if (cov[i * p + j] == 0) "0" else try fixed(a, cov[i * p + j], 6), 16);
        try out.append(a, '\n');
    }
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, c: Computed) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const p = s.vars.len;
    const names = try a.alloc([]const u8, p);
    const heads = try a.alloc(Heading, p);
    var longest: usize = 0;
    for (s.vars, names, heads) |col, *n, *h| {
        n.* = ds.columns.items[col].name;
        longest = @max(longest, n.len);
        h.* = heading(n.*) orelse return gap(cx, 0, "the Missing Data Patterns heading for variable {s} is not verified", .{n.*});
    }
    if (longest > 8) return gap(cx, 0, "listing columns for variable names longer than 8 characters are not verified", .{});
    const data_set = try lists.datasetName(a, ds);
    if (data_set.len > 23) return gap(cx, 0, "the Model Information layout for a data set name longer than 23 characters is not verified", .{});
    for (c.patterns) |pat| for (pat.means, 0..) |m, j| {
        if (observed(pat.mask, j) and !shown(m)) return gap(cx, 0, "group mean display outside 1 <= |x| < 1000 is not verified", .{});
    };
    const stats = try a.alloc(Univariate, p);
    const corr = try a.alloc(f64, p * p);
    if (s.simple) {
        // ponytail: the name column of the correlation and EM tables is 8
        // wide in the reference, whose longest name has 8 characters; whether
        // it shrinks for shorter names is not verified.
        if (longest != 8) return gap(cx, 0, "SIMPLE listing columns are verified only when the longest analysis variable name has 8 characters", .{});
        for (stats, 0..) |*u, j| {
            u.* = univariate(c.sel, j);
            if (!(u.n > 1)) return gap(cx, 0, "SIMPLE statistics for a variable with fewer than two observed values are not verified", .{});
            for ([_]f64{ u.mean, u.sd, u.min, u.max }) |x| if (!shown(x)) return gap(cx, 0, "univariate statistic display outside 1 <= |x| < 1000 is not verified", .{});
        }
        for (0..p) |i| for (0..p) |j| {
            corr[i * p + j] = if (i == j) 1 else pairwise(c.sel, i, j) orelse return gap(cx, 0, "an undefined pairwise correlation is not verified", .{});
        };
    }
    if (c.em) |r| {
        if (longest != 8) return gap(cx, 0, "EM listing columns are verified only when the longest analysis variable name has 8 characters", .{});
        // ponytail: the reference iteration history gives its first mean
        // column 15 characters and the others 16, for names of 6, 7 and 8
        // characters; the rule behind the narrower column is unknown.
        if (s.em.?.itprint) for (names, 0..) |n, j| {
            if (if (j == 0) n.len != 6 else n.len < 7) return gap(cx, 0, "the EM iteration history column widths are not verified for these variable names", .{});
        };
        for (r.initial_mean, r.mean) |x, y| if (!shown(x) or !shown(y)) return gap(cx, 0, "EM estimate display outside 1 <= |x| < 1000 is not verified", .{});
        for (r.initial_cov, r.cov) |x, y| if ((x != 0 and !shown(x)) or !shown(y)) return gap(cx, 0, "EM estimate display outside 1 <= |x| < 1000 is not verified", .{});
        for (r.history) |it| {
            if (!shown(it.neg2ll)) return gap(cx, 0, "-2 Log L display outside 1 <= |x| < 1000 is not verified", .{});
            for (it.mean) |x| if (!shown(x)) return gap(cx, 0, "EM estimate display outside 1 <= |x| < 1000 is not verified", .{});
        }
    }

    var body: Out = .empty;
    try body.appendSlice(a, "\nThe MI Procedure\n\n                     Model Information\n\n");
    const info = [_][2][]const u8{
        .{ "Data Set", data_set },
        .{ "Method", "MCMC" },
        .{ "Multiple Imputation Chain", "Single Chain" },
        .{ "Initial Estimates for MCMC", "EM Posterior Mode" },
        .{ "Start", "Starting Value" },
        .{ "Prior", "Jeffreys" },
        .{ "Number of Imputations", "0" },
        .{ "Number of Burn-in Iterations", "200" },
        .{ "Number of Iterations", "100" },
        .{ "Seed for random number generator", try std.fmt.allocPrint(a, "{d}", .{s.seed.?}) },
    };
    for (info) |row| {
        try padLeft(a, &body, row[0], 37);
        try padLeft(a, &body, row[1], 23);
        try body.append(a, '\n');
    }

    var width: usize = 5 + 24 + 16 * p;
    for (heads) |h| width += 4 + h.width;
    try body.appendSlice(a, "\n\n");
    try title(a, &body, "Missing Data Patterns", width, true);
    try body.appendNTimes(a, ' ', 5);
    for (heads) |h| {
        try body.appendNTimes(a, ' ', 4);
        try padLeft(a, &body, h.top, h.width);
    }
    try body.appendNTimes(a, ' ', 28);
    try spanner(a, &body, "Group Means", 16 * p - 4);
    try body.appendSlice(a, "\nGroup");
    for (heads) |h| {
        try body.appendNTimes(a, ' ', 4);
        try padLeft(a, &body, h.bottom, h.width);
    }
    try body.appendSlice(a, "        Freq     Percent");
    for (names) |n| try padRight(a, &body, n, 16);
    try body.appendSlice(a, "\n\n");
    for (c.patterns, 1..) |pat, g| {
        try body.print(a, "{d:>5}", .{g});
        for (heads, 0..) |h, j| {
            try body.appendNTimes(a, ' ', 4);
            try padLeft(a, &body, if (observed(pat.mask, j)) "X" else ".", h.width);
        }
        try body.print(a, "{d:>12}", .{@as(u64, @intFromFloat(pat.freq))});
        try padRight(a, &body, try fixed(a, 100 * pat.freq / c.total, 2), 12);
        for (pat.means, 0..) |m, j| try padRight(a, &body, if (observed(pat.mask, j)) try fixed(a, m, 6) else ".", 16);
        try body.append(a, '\n');
    }

    if (s.simple) {
        try body.appendSlice(a, "\n\n");
        try title(a, &body, "Univariate Statistics", 99, false);
        try body.appendNTimes(a, ' ', 80);
        try spanner(a, &body, "Missing Values", 19);
        try body.appendSlice(a, "\nVariable           N          Mean       Std Dev       Minimum       Maximum       Count    Percent\n\n");
        for (names, stats) |n, u| {
            try padLeft(a, &body, n, 8);
            try body.print(a, "{d:>12}", .{@as(u64, @intFromFloat(u.n))});
            for ([_]f64{ u.mean, u.sd, u.min, u.max }) |x| try padRight(a, &body, try fixed(a, x, 5), 14);
            try body.print(a, "{d:>12}", .{@as(u64, @intFromFloat(c.total - u.n))});
            try padRight(a, &body, try fixed(a, 100 * (c.total - u.n) / c.total, 2), 11);
            try body.append(a, '\n');
        }
        try body.appendSlice(a, "\n\n");
        try title(a, &body, "Pairwise Correlations", 8 + 18 * p, false);
        try body.appendNTimes(a, ' ', 8);
        for (names) |n| try padRight(a, &body, n, 18);
        try body.appendSlice(a, "\n\n");
        for (names, 0..) |n, i| {
            try padLeft(a, &body, n, 8);
            for (0..p) |j| try padRight(a, &body, try fixed(a, corr[i * p + j], 9), 18);
            try body.append(a, '\n');
        }
    }

    if (c.em) |r| {
        try body.appendSlice(a, "\n\n");
        try title(a, &body, "Initial Parameter Estimates for EM", 18 + 16 * p, false);
        try estimates(a, &body, names, r.initial_mean, r.initial_cov);
        if (s.em.?.itprint) {
            try body.appendSlice(a, "\n\n");
            try title(a, &body, "EM (MLE) Iteration History", 26 + 16 * p, false);
            try body.appendSlice(a, "_Iteration_        -2 Log L");
            for (names, 0..) |n, j| try padRight(a, &body, n, if (j == 0) 15 else 16);
            try body.appendSlice(a, "\n\n");
            for (r.history, 0..) |it, k| {
                try body.print(a, "{d:>11}", .{k});
                try padRight(a, &body, try fixed(a, it.neg2ll, 6), 16);
                for (it.mean, 0..) |x, j| try padRight(a, &body, try fixed(a, x, 6), if (j == 0) 15 else 16);
                try body.append(a, '\n');
            }
        }
        try body.appendSlice(a, "\n\n");
        try title(a, &body, "EM (MLE) Parameter Estimates", 18 + 16 * p, false);
        try estimates(a, &body, names, r.mean, r.cov);
    }
    try out.appendSlice(a, body.items);
}

/// OUTEM= TYPE=COV layout: BY variables, _TYPE_, _NAME_, analysis variables;
/// one MEAN row and one COV row per variable for each BY group.
fn outemRows(a: A, ds: *Dataset, s: Spec, rep: ?[]const Value, r: EmResult) !void {
    const p = s.vars.len;
    const lead = s.by_cols.len;
    for (0..p + 1) |k| {
        const row = try a.alloc(Value, lead + 2 + p);
        for (s.by_cols, 0..) |c, j| row[j] = rep.?[c];
        row[lead] = .{ .str = if (k == 0) "MEAN" else "COV" };
        row[lead + 1] = .{ .str = if (k == 0) "" else s.input.ds.columns.items[s.vars[k - 1]].name };
        for (0..p) |j| row[lead + 2 + j] = .{ .num = if (k == 0) r.mean[j] else r.cov[(k - 1) * p + j] };
        try ds.appendRow(row);
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    // Execution boundary: imputation needs the SAS random number stream.
    const nimpute = s.nimpute orelse return gap(cx, 0, "imputation is not implemented; only NIMPUTE=0 (descriptive output and EM estimates) is supported", .{});
    if (nimpute != 0) return gap(cx, 0, "imputation is not implemented; only NIMPUTE=0 (descriptive output and EM estimates) is supported", .{});
    const seed = s.seed orelse return gap(cx, 0, "the clock-generated seed shown when SEED= is omitted cannot be reproduced; specify SEED=", .{});
    if (seed <= 0) return gap(cx, 0, "the clock-generated seed used for SEED<=0 cannot be reproduced", .{});
    const ds = s.input.ds;
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0 or ds.rows.items.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    // Every group is computed and checked before anything is printed.
    const groups = try a.alloc(Computed, slices.len);
    for (slices, groups) |slice, *group| group.* = try compute(cx, s, slice.rows);
    var listing: Out = .empty;
    for (slices, groups) |slice, group| {
        var page: Out = .empty;
        if (s.by_cols.len > 0) {
            // The listing is laid out flush left (the reference runs under
            // NOCENTER), so the shared centred BY line is shifted left too.
            var line: Out = .empty;
            try by.appendLine(a, &line, ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) {
                try page.append(a, '\n');
                try page.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
            }
        }
        try render(cx, &page, s, group);
        if (s.noprint) continue;
        if (cx.listing_titles) |titles| try titles.emitTitles(a, &listing);
        try listing.appendSlice(a, page.items);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, &listing);
    }
    var outem: ?*Dataset = null;
    if (s.em) |em_options| if (em_options.outem) |name| {
        const created = try a.create(Dataset);
        created.* = Dataset.init(a, name);
        for (s.by_cols) |c| _ = try created.addColumnLike(ds.columns.items[c].name, ds.columns.items[c]);
        for ([_][]const u8{ "_TYPE_", "_NAME_" }, [_]usize{ 8, 32 }) |column, len| {
            if (ds.indexOf(column) != null) return gap(cx, 0, "OUTEM= with an input variable named {s} is not verified", .{column});
            const ci = try created.addColumn(column, .char);
            created.columns.items[ci].len = len;
        }
        for (s.vars) |c| _ = try created.addColumnLike(ds.columns.items[c].name, ds.columns.items[c]);
        outem = created;
    };
    for (slices, groups) |slice, group| {
        const r = group.em orelse continue;
        try cx.diags.note(0, "The EM algorithm (MLE) converges in {d} iterations.", .{r.iterations});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, slice.rep.?, s.by_cols);
        if (outem) |created| try outemRows(a, created, s, slice.rep, r);
    }
    if (outem) |created| {
        try cx.lib.put(created.name, created);
        try cx.diags.note(0, "The data set {s} has {d} observations and {d} variables.", .{ try lists.datasetName(a, created), created.rows.items.len, created.columns.items.len });
    }
    try out.appendSlice(a, listing.items);
}

test {
    _ = @import("mi_tests.zig");
}
