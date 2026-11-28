//! PROC STDIZE (SAS/STAT 15.4 ch.115, STAT-STDIZE-001): PROC statement
//! options, VAR / BY / FREQ / WEIGHT roles, missing-value rules, the OUT=
//! data set and the PSTAT "Location and Scale Measures" table.
//!
//! Implemented location/scale measures (Table 115.2, closed form): MEAN,
//! MEDIAN, SUM, EUCLEN, USTD, STD, RANGE, MIDRANGE, MAXABS, IQR and MAD.
//! Percentiles use the order-statistics method with PCTLDEF=5 (the documented
//! default). Every other documented option, method or statement — and every
//! listing whose layout has not been verified against a SAS listing — is a
//! loud D-009 gap; nothing is written or printed for a step that hits one.
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
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { mean, median, sum, euclen, ustd, std, range, midrange, maxabs, iqr, mad };
pub const VarDef = enum { df, n, wdf, weight };

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement (pp.9445-9448). Defaults: METHOD=STD, ADD=0, MULT=1,
    // FUZZ=1E-14, VARDEF=DF, PCTLMTD=ORD_STAT, PCTLDEF=5.
    method: Method = .std,
    add: f64 = 0,
    mult: f64 = 1,
    fuzz: f64 = 1e-14,
    vardef: VarDef = .df,
    nomiss: bool = false,
    replace: bool = false,
    reponly: bool = false,
    /// MISSING=value: replaces missing values after standardizing.
    missing: ?f64 = null,
    pstat: bool = false,
    /// OUT= member; null means the DATAn convention.
    out: ?[]const u8 = null,
    // Roles.
    vars: []const usize = &.{},
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
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC STDIZE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
/// `name` or `lib.name`, optionally followed by a data set option list.
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8, options: *bool) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) {
        options.* = true;
        j = proc.skipParen(t, j);
    }
    into.* = name;
    return j;
}
/// A signed numeric option value at t[i].
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

const method_names = [_]struct { []const u8, Method }{
    .{ "mean", .mean },     .{ "median", .median }, .{ "sum", .sum },     .{ "euclen", .euclen },
    .{ "ustd", .ustd },     .{ "std", .std },       .{ "range", .range }, .{ "midrange", .midrange },
    .{ "maxabs", .maxabs }, .{ "iqr", .iqr },       .{ "mad", .mad },
};
/// Documented METHOD= names (p.9445) whose estimators are not implemented.
const method_gaps = [_][]const u8{ "abw", "ahuber", "awave", "agk", "spacing", "l", "in" };

/// Documented PROC STDIZE options (Table 115.1) this ticket does not implement.
const option_gaps = [_][]const u8{ "initial", "unstd", "unstdize", "keeplen", "oprefix", "sprefix", "outstat", "nmarkers", "pctldef", "pctlpts", "norm", "snorm" };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = try std.ascii.allocLowerString(a, t[i].text);
        const l = t[i].line;
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, l, "PROC STDIZE: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            const first = i + 2;
            var ignored = false;
            const after = try memberName(cx, t, first, &name, &ignored);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "out") and valued) {
            var options = false;
            i = try memberName(cx, t, i + 2, &s.out, &options);
            if (options) return gap(cx.diags, l, "PROC STDIZE: data set options on OUT= are not implemented", .{});
        } else if (eq(option, "method") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: METHOD= must be a method name", .{});
            const m = t[i + 2].text;
            const found = for (method_names) |p| {
                if (eq(m, p[0])) break p[1];
            } else null;
            if (found) |f| {
                s.method = f;
            } else {
                for (method_gaps) |g| if (eq(m, g)) return gap(cx.diags, l, "PROC STDIZE: METHOD={s} is not implemented (STAT-STDIZE-003)", .{m});
                return cx.diags.fail(error.ParseError, l, "PROC STDIZE: METHOD={s} is not a valid standardization method", .{m});
            }
            i += 3;
            if (at(t, i, .lparen)) return gap(cx.diags, l, "PROC STDIZE: a METHOD= argument is not implemented", .{});
        } else if ((eq(option, "add") or eq(option, "mult") or eq(option, "fuzz")) and valued) {
            i += 2;
            const v = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: {s}= must be a number", .{option});
            if (eq(option, "add")) s.add = v else if (eq(option, "mult")) s.mult = v else {
                if (v < 0) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: FUZZ= must be nonnegative", .{});
                s.fuzz = v;
            }
        } else if (eq(option, "vardef") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: VARDEF= must be DF, N, WDF, WEIGHT or WGT", .{});
            const v = t[i + 2].text;
            s.vardef = if (eq(v, "df")) .df else if (eq(v, "n")) .n else if (eq(v, "wdf")) .wdf else if (eq(v, "weight") or eq(v, "wgt")) .weight else return cx.diags.fail(error.ParseError, l, "PROC STDIZE: VARDEF={s} is not valid", .{v});
            i += 3;
        } else if (eq(option, "pctlmtd") and valued) {
            if (!at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLMTD= must be ORD_STAT, ONEPASS or P2", .{});
            const v = t[i + 2].text;
            if (!eq(v, "ord_stat")) {
                if (eq(v, "onepass") or eq(v, "p2")) return gap(cx.diags, l, "PROC STDIZE: PCTLMTD={s} is not implemented (STAT-STDIZE-004)", .{v});
                return cx.diags.fail(error.ParseError, l, "PROC STDIZE: PCTLMTD={s} is not valid", .{v});
            }
            i += 3;
        } else if (eq(option, "missing") and valued) {
            i += 2;
            if (at(t, i, .name)) return gap(cx.diags, l, "PROC STDIZE: MISSING={s} (a replacement method) is not implemented", .{t[i].text});
            s.missing = number(t, &i) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: MISSING= must be a method or a number", .{});
        } else if (!valued and eq(option, "nomiss")) {
            s.nomiss = true;
            i += 1;
        } else if (!valued and eq(option, "replace")) {
            s.replace = true;
            i += 1;
        } else if (!valued and eq(option, "reponly")) {
            s.reponly = true;
            i += 1;
        } else if (!valued and eq(option, "pstat")) {
            s.pstat = true;
            i += 1;
        } else {
            for (option_gaps) |g| if (eq(option, g)) return gap(cx.diags, l, "PROC STDIZE: the {s} option is not implemented", .{t[i].text});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // pp.9447-9448: "You cannot specify both the REPLACE and REPONLY options."
    if (s.replace and s.reponly) return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: you cannot specify both the REPLACE and REPONLY options", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: input data set not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList(usize) = .empty;
    var var_seen = false;
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
            // p.9449: with more than one BY statement only the last is used.
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (var_seen) return gap(cx.diags, t[i].line, "PROC STDIZE: more than one VAR statement is not verified", .{});
            var_seen = true;
            try columnList(cx, ds, t, i, end, "VAR", &vars);
        } else if (eq(word, "freq")) {
            if (s.freq != null) return gap(cx.diags, t[i].line, "PROC STDIZE: more than one FREQ statement is not verified", .{});
            if (end > i + 2 and at(t, i + 2, .slash)) return gap(cx.diags, t[i].line, "PROC STDIZE: FREQ statement options (NOTRUNCATE) are not implemented", .{});
            s.freq = try oneNumeric(cx, ds, t, i, end, "FREQ");
        } else if (eq(word, "weight") or eq(word, "wgt")) {
            if (s.weight != null) return gap(cx.diags, t[i].line, "PROC STDIZE: more than one WEIGHT statement is not verified", .{});
            s.weight = try oneNumeric(cx, ds, t, i, end, "WEIGHT");
        } else if (eq(word, "location") or eq(word, "scale")) {
            return gap(cx.diags, t[i].line, "PROC STDIZE: the {s} statement (METHOD=IN) is not implemented (STAT-STDIZE-003)", .{word});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    if (!var_seen) {
        // p.9450: without a VAR statement all numeric variables not listed in
        // the BY, FREQ and WEIGHT statements are used.
        for (ds.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(cols, ci) or s.freq == ci or s.weight == ci) continue;
            try vars.append(a, ci);
        }
    }
    s.vars = vars.items;
    if (s.vars.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC STDIZE: no numeric variables to standardize", .{});
    return s;
}

fn oneNumeric(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8) diag.Error!usize {
    if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: the {s} statement takes exactly one variable", .{role});
    const ci = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: variable {s} in the {s} statement is not on the input data set", .{ t[i + 1].text, role });
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC STDIZE: variable {s} in the {s} statement must be numeric", .{ t[i + 1].text, role });
    return ci;
}
fn columnList(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, end: usize, role: []const u8, into: *std.ArrayList(usize)) diag.Error!void {
    if (end == i + 1) return invalid(cx, t, end);
    const body = t[i + 1 .. end];
    var j: usize = 0;
    while (j < body.len) {
        const l = body[j].line;
        const names = try lists.next(cx.arena, ds, body, &j, cx.diags);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC STDIZE: variable {s} in the {s} statement is not on the input data set", .{ n, role });
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC STDIZE: variable {s} in the {s} statement must be numeric", .{ n, role });
            if (!has(into.items, ci)) try into.append(cx.arena, ci);
        }
    }
}

/// One usable value of an analysis variable: x with its integer frequency f
/// and weight w.
pub const Obs = struct { x: f64, f: f64, w: f64 };

/// Values of variable `ci` used for its location and scale (pp.9450-9451,
/// 9457): nonmissing x, FREQ truncated and at least 1, WEIGHT above zero;
/// with NOMISS, rows missing any analysis variable are dropped.
pub fn usable(a: A, s: Spec, rows: []const []const Value, ci: usize) ![]Obs {
    var list: std.ArrayList(Obs) = .empty;
    rows: for (rows) |row| {
        const x = row[ci].num;
        if (std.math.isNan(x)) continue;
        if (s.nomiss) for (s.vars) |v| if (std.math.isNan(row[v].num)) continue :rows;
        var f: f64 = 1;
        if (s.freq) |fc| {
            f = @floor(row[fc].num);
            if (!(f >= 1)) continue;
        }
        var w: f64 = 1;
        if (s.weight) |wc| {
            w = row[wc].num;
            if (!(w > 0)) continue;
        }
        try list.append(a, .{ .x = x, .f = f, .w = w });
    }
    return list.items;
}

fn lessX(_: void, l: Obs, r: Obs) bool {
    return l.x < r.x;
}
/// The k-th (1-based) order statistic of the frequency-expanded sample.
fn orderStat(sorted: []const Obs, k: f64) f64 {
    var cum: f64 = 0;
    for (sorted) |o| {
        cum += o.f;
        if (cum >= k) return o.x;
    }
    return sorted[sorted.len - 1].x;
}
/// PCTLDEF=5 (p.9456): np = j + g; g = 0 -> (x_j + x_{j+1}) / 2, else x_{j+1}.
pub fn percentile(a: A, obs: []const Obs, p: f64) !f64 {
    const sorted = try a.dupe(Obs, obs);
    std.mem.sort(Obs, sorted, {}, lessX);
    var n: f64 = 0;
    for (sorted) |o| n += o.f;
    const np = n * p;
    const j = @floor(np);
    const g = np - j;
    if (g == 0) return (orderStat(sorted, @max(j, 1)) + orderStat(sorted, j + 1)) / 2;
    return orderStat(sorted, j + 1);
}

pub const Measures = struct { location: f64, scale: f64, n: f64 };

/// Location and scale of Table 115.2 for one variable (Computation of the
/// Statistics, p.9454; weighted moments, p.9451). Null when the sample does
/// not determine the measure (no values, or a variance divisor <= 0).
pub fn measures(a: A, s: Spec, obs: []const Obs) !?Measures {
    if (obs.len == 0) return null;
    var n: f64 = 0;
    var sw: f64 = 0;
    var swx: f64 = 0;
    var swxx: f64 = 0;
    var lo = obs[0].x;
    var hi = obs[0].x;
    for (obs) |o| {
        n += o.f;
        sw += o.f * o.w;
        swx += o.f * o.w * o.x;
        swxx += o.f * o.w * o.x * o.x;
        lo = @min(lo, o.x);
        hi = @max(hi, o.x);
    }
    const mean = swx / sw;
    const d: f64 = switch (s.vardef) {
        .df => n - 1,
        .n => n,
        .wdf => sw - 1,
        .weight => sw,
    };
    const loc_scale: [2]f64 = switch (s.method) {
        .mean => .{ mean, 1 },
        .median => .{ try percentile(a, obs, 0.5), 1 },
        .sum => .{ 0, swx },
        .euclen => .{ 0, @sqrt(swxx) },
        .ustd => blk: {
            if (d <= 0) return null;
            break :blk .{ 0, @sqrt(swxx / d) };
        },
        .std => blk: {
            if (d <= 0) return null;
            var css: f64 = 0;
            for (obs) |o| css += o.f * o.w * (o.x - mean) * (o.x - mean);
            break :blk .{ mean, @sqrt(css / d) };
        },
        .range => .{ lo, hi - lo },
        .midrange => .{ (hi + lo) / 2, (hi - lo) / 2 },
        .maxabs => .{ 0, @max(@abs(lo), @abs(hi)) },
        .iqr => .{ try percentile(a, obs, 0.5), try percentile(a, obs, 0.75) - try percentile(a, obs, 0.25) },
        .mad => blk: {
            const med = try percentile(a, obs, 0.5);
            const dev = try a.alloc(Obs, obs.len);
            for (obs, dev) |o, *e| e.* = .{ .x = @abs(o.x - med), .f = o.f, .w = o.w };
            break :blk .{ med, try percentile(a, dev, 0.5) };
        },
    };
    var location = loc_scale[0];
    var scale = loc_scale[1];
    // FUZZ= (p.9445) for the location and scale values.
    if (scale < @abs(location) * s.fuzz) scale = 0 else if (@abs(location) < @abs(s.mult) * s.fuzz) location = 0;
    return .{ .location = location, .scale = scale, .n = n };
}

/// Final OUT= value (p.9448): add + mult * (x - location) / scale, with the
/// FUZZ= rule |result| < mult * fuzz -> 0.
pub fn standardize(s: Spec, m: Measures, x: f64) f64 {
    const r = s.add + s.mult * (x - m.location) / m.scale;
    return if (@abs(r) < @abs(s.mult) * s.fuzz) 0 else r;
}

/// The verified PSTAT subtitle wording of each method (SAS listings).
fn labels(m: Method) ?[2][]const u8 {
    return switch (m) {
        .std => .{ "mean", "standard deviation" },
        .mad => .{ "median", "median abs dev from median" },
        .iqr => .{ "median", "interquartile range" },
        else => null,
    };
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try pad(a, out, width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try pad(a, out, width - text.len);
}

/// The PSTAT table, laid out as in the SAS listing: a Name column as wide as
/// the longest name (at least 4), then Location and Scale right-aligned in 16
/// columns with six decimals and N in 12.
fn table(a: A, out: *Out, names: []const []const u8, label: usize, lab: [2][]const u8, values: []const Measures) !void {
    try out.print(a, "\nThe STDIZE Procedure\n\nLocation and Scale Measures\n \nLocation = {s}     Scale = {s}\n \n", .{ lab[0], lab[1] });
    try left(a, out, "Name", label);
    try right(a, out, "Location", 16);
    try right(a, out, "Scale", 16);
    try right(a, out, "N", 12);
    try out.appendSlice(a, "\n\n");
    for (names, values) |n, m| {
        try left(a, out, n, label);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{m.location}), 16);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.6}", .{m.scale}), 16);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{m.n}), 12);
        try out.appendSlice(a, "\n");
    }
}

/// BY line flush left. ponytail: as in PROC FACTOR, the shared helper centers
/// the BY line; the NOCENTER reference listing has it at column 1.
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

fn anyLine(lines: []const ?[]const u8) bool {
    for (lines) |l| if (l != null) return true;
    return false;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const p = s.vars.len;

    // p.9450: the WEIGHT variable applies only to some methods; for the others
    // its role is not documented precisely enough to reproduce.
    if (s.weight != null) switch (s.method) {
        .range, .midrange, .maxabs => return gap(cx.diags, l0, "PROC STDIZE: a WEIGHT statement with METHOD=RANGE, MIDRANGE or MAXABS is not verified", .{}),
        .median, .iqr, .mad => return gap(cx.diags, l0, "PROC STDIZE: weighted percentiles (WEIGHT with METHOD=MEDIAN, IQR or MAD) are not implemented (STAT-STDIZE-004)", .{}),
        else => {},
    };
    if (s.replace and s.missing != null) return gap(cx.diags, l0, "PROC STDIZE: REPLACE combined with MISSING= is not verified", .{});
    if (s.replace and s.add != 0) return gap(cx.diags, l0, "PROC STDIZE: REPLACE with a nonzero ADD= is not verified", .{});
    if (s.pstat) {
        if (labels(s.method) == null) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT listing for METHOD={s} is not verified against SAS output (STAT-STDIZE-006)", .{@tagName(s.method)});
        if (s.weight != null) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT Sum of Weights column is not verified against SAS output (STAT-STDIZE-006)", .{});
    }
    if (cx.capture) |c| if (c.wants("Statistics")) return gap(cx.diags, l0, "PROC STDIZE: ODS OUTPUT Statistics= is not implemented (STAT-STDIZE-006)", .{});

    if (s.pstat and groups.len > 1) if (cx.listing_titles) |titles| if (anyLine(&titles.footnotes))
        return gap(cx.diags, l0, "PROC STDIZE: footnotes on BY-group PSTAT pages are not verified against SAS output", .{});

    const names = try a.alloc([]const u8, p);
    var label: usize = 4;
    for (s.vars, names) |ci, *n| {
        n.* = ds.columns.items[ci].name;
        label = @max(label, n.len);
    }
    const member = s.out orelse blk: {
        var k: usize = 1;
        while (true) : (k += 1) {
            const candidate = try std.fmt.allocPrint(a, "data{d}", .{k});
            if (cx.lib.find(candidate) == null) break :blk candidate;
        }
    };
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, member);
    for (ds.columns.items) |c| _ = try o.addColumnLike(c.name, c);

    var body: Out = .empty;
    const ms = try a.alloc(Measures, p);
    for (groups, 0..) |group, gi| {
        for (s.vars, ms) |ci, *m| {
            const obs = try usable(a, s, group.rows, ci);
            m.* = (try measures(a, s, obs)) orelse return gap(cx.diags, l0, "PROC STDIZE: variable {s} has too few usable values in a BY group; the missing location/scale handling is not verified (STAT-STDIZE-004)", .{ds.columns.items[ci].name});
            if (m.scale == 0 and !s.reponly) return gap(cx.diags, l0, "PROC STDIZE: constant data (variable {s} has zero scale) are not implemented (STAT-STDIZE-004)", .{ds.columns.items[ci].name});
            if (s.pstat) {
                const text = try std.fmt.allocPrint(a, "{d:.6}", .{@max(@abs(m.location), @abs(m.scale))});
                if (text.len > 14) return gap(cx.diags, l0, "PROC STDIZE: the PSTAT number layout for magnitudes this large is not verified", .{});
            }
        }
        if (s.pstat) {
            // Verified (SAS listing): every BY-group page after the first
            // repeats the titles after one blank line.
            if (gi > 0) if (cx.listing_titles) |titles| if (anyLine(&titles.titles)) {
                try body.append(a, '\n');
                try titles.emitTitles(a, &body);
            };
            if (s.by_cols.len > 0) try byLine(a, &body, ds, group.rows[0], s.by_cols);
            try table(a, &body, names, label, labels(s.method).?, ms);
        }
        for (group.rows) |row| {
            const values = try a.dupe(Value, row);
            for (s.vars, ms) |ci, m| {
                const x = row[ci].num;
                if (std.math.isNan(x)) {
                    // Missing Values (p.9457): REPLACE -> 0 after standardizing
                    // (= the location before it); REPONLY -> the location;
                    // MISSING=value -> value after standardizing.
                    if (s.missing) |v| values[ci] = .{ .num = v } else if (s.replace) {
                        values[ci] = .{ .num = 0 };
                    } else if (s.reponly) values[ci] = .{ .num = m.location };
                } else if (!s.reponly) values[ci] = .{ .num = standardize(s, m, x) };
            }
            try o.appendRow(values);
        }
    }
    try cx.lib.put(member, o);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    const upper = try std.ascii.allocUpperString(a, member);
    const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
    try out.appendSlice(a, body.items);
    // Verified (SAS listing): the step's listing ends with one blank line.
    if (body.items.len > 0) try out.append(a, '\n');
}

test {
    _ = @import("stdize_tests.zig");
}
