//! PROC KDE (SAS/STAT 15.4 ch.73, STAT-KDE-001): PROC statement, UNIVAR /
//! BIVAR / BY / FREQ / WEIGHT roles, missing-value and observation rules, the
//! closed-form bandwidths (bivariate Bowman-Foster default, univariate SNR and
//! OS, user BW=/BWM=), the default grid limits and the default "Inputs" and
//! "Controls" listing.
//!
//! The density computation itself (binning, FFT convolution, OUT=, CDF,
//! LEVELS, PERCENTILES, UNISTATS/BIVSTATS), the SJPI/SNRQ/SROT bandwidths,
//! SCORE and every plot are owned by STAT-KDE-002..009 and stay loud D-009
//! gaps: nothing is printed for a step that hits one.
//!
//! Default grid limits (not stated in the chapter; derived from SAS 9.4
//! listings of invented data, see the fixtures): with R = (GRIDU or max) -
//! (GRIDL or min) and step = R/128, an unspecified limit sits
//! k = min(ceil(3h/step), 64) steps beyond the observed extreme, where h is
//! the bandwidth after the BWM= multiplier.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { snr, os };

/// Options that are valid both globally (after the slash) and as v-options.
pub const VOpts = struct {
    bw: ?f64 = null,
    bwm: ?f64 = null,
    gridl: ?f64 = null,
    gridu: ?f64 = null,
    ngrid: ?f64 = null,
};

pub const Stmt = struct {
    bivar: bool,
    /// 1-based statement number within its kind (log NOTE).
    number: usize,
    line: usize,
    /// UNIVAR: one estimate per (deduplicated) variable.
    vars: []const usize = &.{},
    /// BIVAR: one estimate per pair.
    pairs: []const [2]usize = &.{},
    global: VOpts = .{},
    /// v-options by column index (later occurrences override earlier ones).
    vcols: []const usize = &.{},
    vopts: []const VOpts = &.{},
    /// UNIVAR METHOD=; null means the documented default (SJPI, a gap).
    method: ?Method = null,
    noprint: bool = false,
    truncate: bool = false,
    /// A PLOTS= request other than NONE.
    plots: bool = false,
    plots_none: bool = false,

    pub fn opts(self: Stmt, ci: usize) VOpts {
        var o = self.global;
        var k = self.vcols.len;
        while (k > 0) {
            k -= 1;
            if (self.vcols[k] != ci) continue;
            const v = self.vopts[k];
            if (v.bw) |x| o.bw = x;
            if (v.bwm) |x| o.bwm = x;
            if (v.gridl) |x| o.gridl = x;
            if (v.gridu) |x| o.gridu = x;
            if (v.ngrid) |x| o.ngrid = x;
            break;
        }
        return o;
    }
};

pub const Spec = struct {
    input: proc.ProcInput,
    stmts: []const Stmt = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC KDE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn number(t: []const lex.Token, i: *usize) ?f64 {
    var neg = false;
    if (at(t, i.*, .minus)) {
        neg = true;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return null;
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return null;
    i.* += 1;
    return if (neg) -v else v;
}

/// Documented UNIVAR/BIVAR options owned by later KDE tickets.
const option_gaps = [_]struct { []const u8, []const u8 }{
    .{ "cdf", "STAT-KDE-004" },         .{ "levels", "STAT-KDE-003" },   .{ "out", "STAT-KDE-003" },
    .{ "percentiles", "STAT-KDE-003" }, .{ "unistats", "STAT-KDE-003" }, .{ "bivstats", "STAT-KDE-003" },
    .{ "sjpimax", "STAT-KDE-006" },     .{ "sjpimin", "STAT-KDE-006" },  .{ "sjpinum", "STAT-KDE-006" },
    .{ "sjpitol", "STAT-KDE-006" },
};

fn checkValue(cx: proc.ProcCtx, l: usize, option: []const u8, v: f64) diag.Error!void {
    // Messages as SAS 9.4 writes them (reference logs of invented data).
    if (eq(option, "ngrid") or eq(option, "ng")) {
        if (v < 2) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is less than the minimum allowed value of 2.", .{v});
    } else if (eq(option, "bwm")) {
        if (v < 0) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is less than the minimum allowed value of 0.", .{v});
        if (v == 0) return cx.diags.fail(error.ParseError, l, "Bandwidth multipliers must be greater than 0.", .{});
    } else if (eq(option, "bw")) {
        if (v < 0) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is less than the minimum allowed value of 0.", .{v});
        if (v == 0) return cx.diags.fail(error.ParseError, l, "User-specified bandwidth must be greater than 0.", .{});
    }
}

/// One `name=number` v-option or global numeric option at t[i]; null when the
/// name is not one of them.
fn vopt(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, o: *VOpts) diag.Error!bool {
    const name = t[i.*].text;
    const slot: *?f64 = if (eq(name, "bw")) &o.bw else if (eq(name, "bwm")) &o.bwm else if (eq(name, "gridl")) &o.gridl else if (eq(name, "gridu")) &o.gridu else if (eq(name, "ngrid") or eq(name, "ng")) &o.ngrid else return false;
    const l = t[i.*].line;
    if (!at(t, i.* + 1, .eq)) return cx.diags.fail(error.ParseError, l, "PROC KDE: {s} requires =number", .{name});
    i.* += 2;
    const v = number(t, i) orelse return cx.diags.fail(error.ParseError, l, "PROC KDE: {s}= must be a number", .{name});
    try checkValue(cx, l, name, v);
    slot.* = v;
    return true;
}

fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, name: []const u8, l: usize) diag.Error!usize {
    const ci = ds.indexOf(name) orelse return cx.diags.fail(error.ParseError, l, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, name)});
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "Variable {s} in list does not match type prescribed for this list.", .{ds.columns.items[ci].name});
    return ci;
}

fn parseStmt(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, bivar: bool, number_in_kind: usize) diag.Error!Stmt {
    const a = cx.arena;
    var s: Stmt = .{ .bivar = bivar, .number = number_in_kind, .line = t[start].line };
    var vars: std.ArrayList(usize) = .empty;
    var pairs: std.ArrayList([2]usize) = .empty;
    var vcols: std.ArrayList(usize) = .empty;
    var vopts: std.ArrayList(VOpts) = .empty;
    var explicit_pairs = false;
    var i = start + 1;
    // Variable list with optional v-options.
    while (i < end and !at(t, i, .slash)) {
        if (at(t, i, .lparen)) {
            if (!bivar) return invalid(cx, t, i);
            // BIVAR (v1 v2): an explicit pair.
            if (!(at(t, i + 1, .name) and at(t, i + 2, .name) and at(t, i + 3, .rparen)))
                return proc.failGap(cx.diags, t[i].line, "PROC KDE: only plain (v1 v2) variable pairs are implemented in BIVAR", .{});
            if (vars.items.len > 0) return proc.failGap(cx.diags, t[i].line, "PROC KDE: mixing a BIVAR variable list with explicit pairs is not verified", .{});
            explicit_pairs = true;
            try pairs.append(a, .{ try numericColumn(cx, ds, t[i + 1].text, t[i].line), try numericColumn(cx, ds, t[i + 2].text, t[i].line) });
            i += 4;
            continue;
        }
        if (!at(t, i, .name)) return invalid(cx, t, i);
        if (explicit_pairs) return proc.failGap(cx.diags, t[i].line, "PROC KDE: mixing a BIVAR variable list with explicit pairs is not verified", .{});
        const l = t[i].line;
        const names = try lists.next(a, ds, t[0..end], &i, cx.diags);
        var last: ?usize = null;
        for (names) |n| {
            const ci = try numericColumn(cx, ds, n, l);
            // UNIVAR x x analyses x once (SAS listing); BIVAR keeps the list.
            if (bivar or std.mem.indexOfScalar(usize, vars.items, ci) == null) try vars.append(a, ci);
            last = ci;
        }
        if (at(t, i, .lparen)) {
            const close = proc.skipParen(t, i);
            var o: VOpts = .{};
            var j = i + 1;
            while (j < close - 1) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                if (!try vopt(cx, t, &j, &o)) {
                    for (option_gaps) |g| if (eq(t[j].text, g[0])) return proc.failGap(cx.diags, t[j].line, "PROC KDE: the {s} option is not implemented ({s})", .{ t[j].text, g[1] });
                    return cx.diags.fail(error.ParseError, t[j].line, "PROC KDE: {s} is not a valid v-option", .{t[j].text});
                }
            }
            try vcols.append(a, last.?);
            try vopts.append(a, o);
            i = close;
        }
    }
    if (at(t, i, .slash)) {
        i += 1;
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        while (i < end) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            const option = try std.ascii.allocLowerString(a, t[i].text);
            const l = t[i].line;
            if ((try seen.getOrPut(a, option)).found_existing) return proc.failGap(cx.diags, l, "PROC KDE: repeated {s} option is not verified", .{t[i].text});
            if (try vopt(cx, t, &i, &s.global)) continue;
            if (eq(option, "noprint")) {
                s.noprint = true;
                i += 1;
            } else if (eq(option, "truncate")) {
                s.truncate = true;
                i += 1;
            } else if (eq(option, "method") and !bivar) {
                if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC KDE: METHOD= must be SJPI, SNR, SNRQ, SROT or OS", .{});
                const m = t[i + 2].text;
                if (eq(m, "snr")) s.method = .snr else if (eq(m, "os")) s.method = .os else if (eq(m, "sjpi") or eq(m, "snrq") or eq(m, "srot")) {
                    return proc.failGap(cx.diags, l, "PROC KDE: METHOD={s} bandwidth selection is not implemented (STAT-KDE-006)", .{m});
                } else return cx.diags.fail(error.ParseError, l, "PROC KDE: METHOD={s} is not a valid bandwidth method", .{m});
                i += 3;
            } else if (eq(option, "plots")) {
                if (!at(t, i + 1, .eq)) return cx.diags.fail(error.ParseError, l, "PROC KDE: PLOTS requires =", .{});
                i += 2;
                if (at(t, i, .lparen)) {
                    const close = proc.skipParen(t, i);
                    if (close == i + 3 and at(t, i + 1, .name) and eq(t[i + 1].text, "none")) s.plots_none = true else s.plots = true;
                    i = close;
                } else if (at(t, i, .name)) {
                    if (eq(t[i].text, "none")) s.plots_none = true else s.plots = true;
                    i += 1;
                    if (at(t, i, .lparen)) i = proc.skipParen(t, i);
                } else return cx.diags.fail(error.ParseError, l, "PROC KDE: PLOTS= requires a plot request", .{});
            } else {
                for (option_gaps) |g| if (eq(option, g[0])) return proc.failGap(cx.diags, l, "PROC KDE: the {s} option is not implemented ({s})", .{ t[i].text, g[1] });
                return cx.diags.fail(error.ParseError, l, "PROC KDE: {s} is not a valid {s} option", .{ t[i].text, if (bivar) @as([]const u8, "BIVAR") else "UNIVAR" });
            }
        }
    }
    if (bivar) {
        if (!explicit_pairs) {
            if (vars.items.len < 2) return cx.diags.fail(error.ParseError, s.line, "PROC KDE: the BIVAR statement requires at least two variables", .{});
            // p.5382: every distinct pair of the list, in list order.
            for (vars.items, 0..) |x, xi| for (vars.items[xi + 1 ..]) |y| try pairs.append(a, .{ x, y });
        }
        s.pairs = pairs.items;
    } else {
        if (vars.items.len == 0) return cx.diags.fail(error.ParseError, s.line, "PROC KDE: the UNIVAR statement requires at least one variable", .{});
        s.vars = vars.items;
    }
    s.vcols = vcols.items;
    s.vopts = vopts.items;
    return s;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    var data_seen = false;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        if (eq(t[i].text, "data") and at(t, i + 1, .eq)) {
            if (data_seen) return proc.failGap(cx.diags, t[i].line, "PROC KDE: a repeated DATA= option is not verified", .{});
            data_seen = true;
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            name = t[first].text;
            var j = first + 1;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name.?, t[j + 1].text });
                qualified = first;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else return cx.diags.fail(error.ParseError, t[i].line, "PROC KDE: {s} is not a valid PROC KDE option (only DATA= is documented)", .{t[i].text});
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC KDE: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var stmts: std.ArrayList(Stmt) = .empty;
    var n_uni: usize = 0;
    var n_bi: usize = 0;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.5386: with more than one BY statement only the last is used.
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "univar")) {
            n_uni += 1;
            try stmts.append(a, try parseStmt(cx, ds, t, i, end, false, n_uni));
        } else if (eq(word, "bivar")) {
            if (n_uni > 0) return proc.failGap(cx.diags, t[i].line, "PROC KDE: the output order of a BIVAR statement after a UNIVAR statement is not verified", .{});
            n_bi += 1;
            try stmts.append(a, try parseStmt(cx, ds, t, i, end, true, n_bi));
        } else if (eq(word, "freq")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC KDE: the FREQ statement takes exactly one variable", .{});
            const ci = try numericColumn(cx, ds, t[i + 1].text, t[i].line);
            // SAS 9.4 listing: with two FREQ statements the first one is used.
            if (s.freq == null) s.freq = ci;
        } else if (eq(word, "weight")) {
            if (s.weight != null) return proc.failGap(cx.diags, t[i].line, "PROC KDE: more than one WEIGHT statement is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC KDE: the WEIGHT statement takes exactly one variable", .{});
            s.weight = try numericColumn(cx, ds, t[i + 1].text, t[i].line);
        } else if (eq(word, "score")) {
            return proc.failGap(cx.diags, t[i].line, "PROC KDE: the SCORE statement is not implemented (STAT-KDE-007)", .{});
        } else if (eq(word, "var")) {
            return proc.failGap(cx.diags, t[i].line, "PROC KDE: the obsolete SAS 8 VAR statement is not implemented; use UNIVAR or BIVAR", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (stmts.items.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "You must specify at least one UNIVAR or BIVAR statement.", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.stmts = stmts.items;
    return s;
}

/// Observation counts and moments of one variable over the usable rows.
pub const Moments = struct { nobs: usize, n: f64, min: f64, max: f64, mean: f64, sigma: f64 };

/// Rows used by one estimate (pp.5386, 5393): every estimate variable
/// nonmissing, FREQ truncated and at least 1, WEIGHT positive.
pub fn usableRows(a: A, s: Spec, rows: []const []const Value, vars: []const usize) ![]const []const Value {
    var list: std.ArrayList([]const Value) = .empty;
    rows: for (rows) |row| {
        for (vars) |v| if (std.math.isNan(row[v].num)) continue :rows;
        if (s.freq) |fc| if (!(@floor(row[fc].num) >= 1)) continue;
        if (s.weight) |wc| if (!(row[wc].num > 0)) continue;
        try list.append(a, row);
    }
    return list.items;
}

/// Moments for the bandwidth (p.5402): unweighted variance with divisor n-1,
/// weighted variance sum(w(x-m)^2)/sum(w); n is the FREQ-expanded count.
pub fn moments(s: Spec, rows: []const []const Value, ci: usize) Moments {
    var n: f64 = 0;
    var sw: f64 = 0;
    var swx: f64 = 0;
    var lo = std.math.inf(f64);
    var hi = -std.math.inf(f64);
    for (rows) |row| {
        const f: f64 = if (s.freq) |fc| @floor(row[fc].num) else 1;
        const w: f64 = if (s.weight) |wc| row[wc].num else 1;
        const x = row[ci].num;
        n += f;
        sw += f * w;
        swx += f * w * x;
        lo = @min(lo, x);
        hi = @max(hi, x);
    }
    const mean = swx / sw;
    var css: f64 = 0;
    for (rows) |row| {
        const f: f64 = if (s.freq) |fc| @floor(row[fc].num) else 1;
        const w: f64 = if (s.weight) |wc| row[wc].num else 1;
        css += f * w * (row[ci].num - mean) * (row[ci].num - mean);
    }
    const divisor = if (s.weight != null) sw else n - 1;
    return .{ .nobs = rows.len, .n = n, .min = lo, .max = hi, .mean = mean, .sigma = @sqrt(css / divisor) };
}

pub const Grid = struct { points: f64, lower: f64, upper: f64, bwm: f64, h: f64 };

pub const GridError = error{ InvalidLimits, TooSmallRange };

/// Bandwidth and grid of one variable of one estimate (see the file header).
pub fn grid(m: Moments, o: VOpts, bivar: bool, method: Method, truncate: bool) GridError!Grid {
    const base = if (o.bw) |b| b else if (bivar)
        m.sigma * std.math.pow(f64, m.n, -1.0 / 6.0) // p.5403 (Bowman and Foster)
    else switch (method) {
        .snr => m.sigma * std.math.pow(f64, 4.0 / (3.0 * m.n), 0.2), // p.5402
        .os => 3.0 * m.sigma * std.math.pow(f64, 1.0 / (70.0 * @sqrt(std.math.pi) * m.n), 0.2),
    };
    // SAS 9.4: constant data fail even with explicit GRIDL=/GRIDU=.
    if (!(m.max > m.min)) return error.TooSmallRange;
    const bwm = o.bwm orelse 1;
    const h = base * bwm;
    var lower = o.gridl;
    var upper = o.gridu;
    if (truncate) {
        if (lower == null) lower = m.min;
        if (upper == null) upper = m.max;
    }
    if (lower == null or upper == null) {
        const range = (upper orelse m.max) - (lower orelse m.min);
        if (!(range > 0)) return error.TooSmallRange;
        const step = range / 128.0;
        const k = @min(@ceil(3.0 * h / step * (1.0 - 1e-12)), 64.0);
        if (lower == null) lower = m.min - k * step;
        if (upper == null) upper = m.max + k * step;
    }
    if (!(lower.? < upper.?)) return error.InvalidLimits;
    return .{ .points = o.ngrid orelse if (bivar) 60 else 401, .lower = lower.?, .upper = upper.?, .bwm = bwm, .h = h };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}

/// Wrap an Inputs value into lines of at most 16 characters, breaking at a
/// blank (dropped) or after an underscore or hyphen, as the SAS listing does.
fn wrap(a: A, text: []const u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var rest = text;
    while (rest.len > 16) {
        var cut: usize = 16;
        var skip: usize = 0;
        var k: usize = 16;
        const found = while (k > 0) : (k -= 1) {
            if (rest[k] == ' ') {
                cut = k;
                skip = 1;
                break true;
            }
            if (rest[k - 1] == '_' or rest[k - 1] == '-') {
                cut = k;
                break true;
            }
        } else false;
        if (!found) cut = 16;
        try parts.append(a, rest[0..cut]);
        rest = rest[cut + skip ..];
    }
    try parts.append(a, rest);
    return parts.items;
}

fn inputRow(a: A, out: *Out, label: []const u8, value: []const u8) !void {
    for (try wrap(a, value), 0..) |part, k| {
        try out.appendSlice(a, if (k == 0) label else "");
        try pad(a, out, 34 - (if (k == 0) label.len else 0));
        try out.appendSlice(a, part);
        try pad(a, out, 17 - part.len);
        try out.append(a, '\n');
    }
}

fn best6(a: A, x: f64) ![]const u8 {
    return std.mem.trim(u8, try format.bestNumW(a, x, 6), " ");
}

fn methodLabel(st: Stmt, users: bool) []const u8 {
    if (users) return "User defined";
    if (st.bivar) return "Simple Normal Reference";
    return switch (st.method.?) {
        .snr => "Simple Normal Reference",
        .os => "Oversmoothed Estimation",
    };
}

fn datasetName(a: A, ds: *const Dataset) ![]const u8 {
    const upper = try std.ascii.allocUpperString(a, ds.name);
    if (std.mem.indexOfScalar(u8, upper, '.') != null) return upper;
    return std.fmt.allocPrint(a, "WORK.{s}", .{upper});
}

/// The default "Inputs" and "Controls" tables of one estimate.
fn renderInputs(a: A, out: *Out, s: Spec, st: Stmt, dsname: []const u8, names: []const []const u8, nobs: usize, users: bool) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe KDE Procedure\n\n");
    try pad(a, out, 22);
    try out.appendSlice(a, "Inputs\n\n");
    try inputRow(a, out, "Data Set", dsname);
    try inputRow(a, out, "Number of Observations Used", try std.fmt.allocPrint(a, "{d}", .{nobs}));
    if (names.len == 1) try inputRow(a, out, "Variable", names[0]) else for (names, 1..) |n, k|
        try inputRow(a, out, try std.fmt.allocPrint(a, "Variable {d}", .{k}), n);
    if (s.weight) |wc| try inputRow(a, out, "Weight", ds.columns.items[wc].name);
    if (s.freq) |fc| try inputRow(a, out, "Freq", ds.columns.items[fc].name);
    try inputRow(a, out, "Bandwidth Method", methodLabel(st, users));
}

fn renderControls(a: A, out: *Out, names: []const []const u8, grids: []const Grid) !void {
    const width = 35 + 10 * (names.len - 1);
    try out.appendSlice(a, "\n\n");
    try pad(a, out, (width - 8) / 2);
    try out.appendSlice(a, "Controls\n \n");
    try pad(a, out, 20);
    for (names, 0..) |n, k| {
        try pad(a, out, (if (k == 0) @as(usize, 15) else 10) - n.len);
        try out.appendSlice(a, n);
    }
    try out.appendSlice(a, "\n\n");
    const labels = [_][]const u8{ "Grid Points", "Lower Grid Limit", "Upper Grid Limit", "Bandwidth Multiplier" };
    for (labels, 0..) |label, r| {
        try out.appendSlice(a, label);
        try pad(a, out, 20 - label.len);
        for (grids, 0..) |g, k| {
            const v = switch (r) {
                0 => g.points,
                1 => g.lower,
                2 => g.upper,
                else => g.bwm,
            };
            const text = try best6(a, v);
            try pad(a, out, (if (k == 0) @as(usize, 15) else 10) -| text.len);
            try out.appendSlice(a, text);
        }
        try out.append(a, '\n');
    }
}

/// BY line flush left (NOCENTER reference listing), as in PROC STDIZE.
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

fn graphicsOn(cx: proc.ProcCtx) bool {
    const g = cx.graphics orelse return false;
    return g.enabled orelse false;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (cx.capture) |c| for ([_][]const u8{ "Inputs", "Controls" }) |name| if (c.wants(name))
        return gap(cx.diags, line(t, 0), "PROC KDE: ODS OUTPUT {s}= is not implemented (STAT-KDE-008)", .{name});
    const dsname = try datasetName(a, ds);
    // Gaps first, so a step that hits one prints nothing.
    for (s.stmts) |st| {
        // pp.5384, 5391: plots need ODS Graphics; with it enabled the
        // statement draws a default plot unless PLOTS=NONE.
        if (graphicsOn(cx) and (st.plots or !st.plots_none))
            return gap(cx.diags, st.line, "PROC KDE: ODS Graphics plots are not implemented (STAT-KDE-009); specify PLOTS=NONE or ODS GRAPHICS OFF", .{});
        if (!st.bivar and st.method == null) {
            for (st.vars) |ci| if (st.opts(ci).bw == null)
                return gap(cx.diags, st.line, "PROC KDE: the default UNIVAR bandwidth (METHOD=SJPI, Sheather-Jones plug-in) is not implemented (STAT-KDE-006); specify BW= or METHOD=SNR|OS", .{});
        }
        const n_est = if (st.bivar) st.pairs.len else st.vars.len;
        for (0..n_est) |e| {
            const vars: []const usize = if (st.bivar) &st.pairs[e] else st.vars[e .. e + 1];
            const users = st.opts(vars[0]).bw != null;
            for (vars) |ci| {
                if ((st.opts(ci).bw != null) != users)
                    return gap(cx.diags, st.line, "PROC KDE: a BIVAR bandwidth given for only one variable of a pair is not verified", .{});
                if (ds.columns.items[ci].name.len > 6)
                    return gap(cx.diags, st.line, "PROC KDE: the Controls layout for variable names longer than 6 characters is not verified", .{});
            }
        }
    }
    var body: Out = .empty;
    for (s.stmts) |st| {
        // SAS 9.4 log for PLOTS= with ODS Graphics disabled; no plot is drawn.
        if (st.plots and !graphicsOn(cx)) try cx.diags.warn(st.line, "You must enable ODS graphics before requesting plots.", .{});
        try cx.diags.note(st.line, "Processing {s} statement number {d}.", .{ if (st.bivar) @as([]const u8, "BIVAR") else "UNIVAR", st.number });
        const n_est = if (st.bivar) st.pairs.len else st.vars.len;
        for (0..n_est) |e| {
            const vars: []const usize = if (st.bivar) &st.pairs[e] else st.vars[e .. e + 1];
            const users = st.opts(vars[0]).bw != null;
            const names = try a.alloc([]const u8, vars.len);
            for (vars, names) |ci, *n| n.* = ds.columns.items[ci].name;
            for (groups) |group| {
                // Run-time errors keep what SAS printed before them.
                const rows = try usableRows(a, s, group.rows, vars);
                if (rows.len < 2) {
                    try out.appendSlice(a, body.items);
                    return cx.diags.fail(error.ParseError, st.line, "Insufficient data.", .{});
                }
                if (!st.noprint and s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
                const grids = try a.alloc(Grid, vars.len);
                for (vars, grids) |ci, *g| {
                    const m = moments(s, rows, ci);
                    g.* = grid(m, st.opts(ci), st.bivar, st.method orelse .snr, st.truncate) catch |err| {
                        // SAS 9.4 prints the Inputs table before the range error.
                        if (err == error.TooSmallRange and !st.noprint) try renderInputs(a, &body, s, st, dsname, names, rows.len, users);
                        try out.appendSlice(a, body.items);
                        return switch (err) {
                            error.InvalidLimits => cx.diags.fail(error.ParseError, st.line, "Invalid grid limits.", .{}),
                            error.TooSmallRange => cx.diags.fail(error.ParseError, st.line, "{s} has too small of a range or the grid size is too large.", .{ds.columns.items[ci].name}),
                        };
                    };
                }
                if (st.noprint) continue;
                try renderInputs(a, &body, s, st, dsname, names, rows.len, users);
                try renderControls(a, &body, names, grids);
            }
        }
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("kde_tests.zig");
}
