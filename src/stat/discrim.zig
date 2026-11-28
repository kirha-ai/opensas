//! PROC DISCRIM declarations, roles and the default listing, SAS/STAT 15.4
//! Chapter 42 (PROC DISCRIM statement pp.2652-2660, BY pp.2660-2661, CLASS
//! p.2661, FREQ pp.2661-2662, ID p.2662, VAR pp.2663-2664, WEIGHT p.2664,
//! Missing Values p.2664, Input Data Sets pp.2675-2676). The default analysis
//! is the parametric (METHOD=NORMAL) linear discriminant function with the
//! pooled covariance matrix (POOL=YES) and equal priors: class summaries come
//! from the CANDISC kernel (read-only reuse), then the pooled covariance
//! COV = E/(N-c), D^2(i|j) = (Xi-Xj)' COV^-1 (Xi-Xj), the linear function
//! (-.5 Xj' COV^-1 Xj, COV^-1 Xj) and the resubstitution classification
//! summary. Everything not verified against a SAS reference is a D-009 gap
//! (rc 2) raised before any listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const varlist = @import("variable_lists.zig");
const candisc = @import("candisc.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    ds: *Dataset,
    noprint: bool = false,
    class: usize = 0,
    vars: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    id: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC DISCRIM: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC DISCRIM: " ++ text, args);
}

fn dataName(a: A, t: []const lex.Token, i: *usize) !?[]const u8 {
    if (!at(t, i.*, .name)) return null;
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot) and at(t, i.* + 1, .name)) {
        name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    return name;
}

/// PROC DISCRIM statement options (Table 42.1) owned by later DISCRIM
/// tickets: valid SAS, not implemented here, so a loud D-009 gap.
const option_gaps = [_][]const u8{
    "anova",    "bcorr",     "bcov",   "bsscp",   "canonical", "can",     "canprefix",   "crosslist", "crosslisterr", "crossvalidate",
    "distance", "k",         "kernel", "kprop",   "list",      "listerr", "mahalanobis", "manova",    "ncan",         "noclassify",
    "out",      "outcross",  "outd",   "outstat", "pcorr",     "pcov",    "posterr",     "psscp",     "r",            "short",
    "simple",   "singular",  "slpool", "stdmean", "tcorr",     "tcov",    "testdata",    "testlist",  "testlisterr",  "testout",
    "testoutd", "threshold", "tsscp",  "wcorr",   "wcov",      "wsscp",   "testclass",   "testfreq",  "testid",       "all",
    "metric",
};

fn column(cx: proc.ProcCtx, ds: *const Dataset, tok: lex.Token) diag.Error!usize {
    return ds.indexOf(tok.text) orelse user(cx, tok.line, "Variable {s} not found.", .{try std.ascii.allocUpperString(cx.arena, tok.text)});
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            data = (try dataName(a, t, &i)) orelse return invalid(cx, t, i);
            if (at(t, i, .lparen)) {
                // Data set options are applied by procInput from the PROC tokens.
                var depth: usize = 0;
                while (i < t.len) : (i += 1) {
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                i += 1;
            }
        } else if (eq(word, "method") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            if (!eq(t[i + 2].text, "normal")) {
                if (eq(t[i + 2].text, "npar")) return gap(cx, t[i].line, "METHOD=NPAR (nonparametric discrimination) is not implemented (owned by a later DISCRIM ticket)", .{});
                return invalid(cx, t, i + 2);
            }
            i += 3;
        } else if (eq(word, "pool") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            if (!eq(t[i + 2].text, "yes")) {
                if (eq(t[i + 2].text, "no") or eq(t[i + 2].text, "test")) return gap(cx, t[i].line, "POOL={s} (quadratic discrimination) is not implemented (owned by a later DISCRIM ticket)", .{t[i + 2].text});
                return invalid(cx, t, i + 2);
            }
            i += 3;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else {
            for (option_gaps) |g| if (eq(word, g)) return gap(cx, t[i].line, "the {s} option is not implemented (owned by a later DISCRIM ticket)", .{word});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const name = data orelse return gap(cx, lineOf(t, 0), "DATA= omitted (most recently created data set) is not implemented", .{});
    const raw = cx.lib.find(name) orelse return user(cx, lineOf(t, 0), "File {s} does not exist.", .{try std.ascii.allocUpperString(a, name)});
    s.ds = try proc.procInput(a, raw, t[0..@min(t.len, i + 1)], cx.diags);
    // Input Data Sets (pp.2675-2676): TYPE=CORR/COV/SSCP/LINEAR/... input.
    if (s.ds.indexOf("_type_") != null) return gap(cx, lineOf(t, 0), "input data sets with a _TYPE_ variable (TYPE=CORR, COV, SSCP, LINEAR, QUAD, MIXED) are not implemented", .{});

    var bys: ?by.Statements = null;
    var class: ?usize = null;
    var var_names: ?std.ArrayList([]const u8) = null;
    var freq_seen = false;
    var weight_seen = false;
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
            if (end != i + 2 or !at(t, i + 1, .name)) return user(cx, lineOf(t, i + 2), "Expecting ;.", .{});
            if (class != null) return gap(cx, t[i].line, "more than one CLASS statement is not verified", .{});
            class = try column(cx, s.ds, t[i + 1]);
        } else if (kw(t, i, "var")) {
            if (var_names != null) return gap(cx, t[i].line, "more than one VAR statement is not verified", .{});
            var names: std.ArrayList([]const u8) = .empty;
            try varlist.append(a, s.ds, t[i + 1 .. end], &names, cx.diags);
            if (names.items.len == 0) return invalid(cx, t, end);
            var_names = names;
        } else if (kw(t, i, "by")) {
            if (bys != null) return gap(cx, t[i].line, "more than one BY statement is not verified", .{});
            var fresh: by.Statements = .{};
            var j = i;
            try fresh.read(a, t, &j);
            bys = fresh;
        } else if (kw(t, i, "freq")) {
            if (freq_seen) return gap(cx, t[i].line, "more than one FREQ statement is not verified", .{});
            freq_seen = true;
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const c = try column(cx, s.ds, t[i + 1]);
            if (s.ds.columns.items[c].type != .num) return user(cx, t[i + 1].line, "Variable {s} in list does not match type prescribed for this list.", .{t[i + 1].text});
            s.freq = c;
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return gap(cx, t[i].line, "more than one WEIGHT statement is not verified", .{});
            weight_seen = true;
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const c = try column(cx, s.ds, t[i + 1]);
            if (s.ds.columns.items[c].type != .num) return user(cx, t[i + 1].line, "Variable {s} in list does not match type prescribed for this list.", .{t[i + 1].text});
            s.weight = c;
        } else if (kw(t, i, "id")) {
            // ID (p.2662) labels LIST/LISTERR rows only; it changes nothing
            // in the default listing.
            if (s.id != null) return gap(cx, t[i].line, "more than one ID statement is not verified", .{});
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, if (end == i + 1) end else i + 2);
            s.id = try column(cx, s.ds, t[i + 1]);
        } else if (kw(t, i, "priors")) {
            // PRIORS (pp.2662-2663): EQUAL is the default; the others change
            // the distances and the linear function (later DISCRIM ticket).
            if (!(end == i + 2 and kw(t, i + 1, "equal"))) return gap(cx, t[i].line, "PRIORS other than EQUAL is not implemented (owned by a later DISCRIM ticket)", .{});
        } else if (kw(t, i, "testclass") or kw(t, i, "testfreq") or kw(t, i, "testid")) {
            return gap(cx, t[i].line, "the {s} statement is not implemented (owned by a later DISCRIM ticket)", .{t[i].text});
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where") or (at(t, i, .name) and @import("../parser.zig").isMidStepSkippable(t[i].text))) {
            // Step boundaries; WHERE is applied by procInput; mid-step global
            // statements (ODS, TITLE, OPTIONS) were executed before the step.
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (bys) |b| {
        const resolved = try b.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    s.class = class orelse return user(cx, lineOf(t, 0), "A CLASS statement must be specified.", .{});
    if (s.ds.columns.items[s.class].format != null) return gap(cx, lineOf(t, 0), "a formatted CLASS variable is not implemented", .{});
    var vars: std.ArrayList(usize) = .empty;
    if (var_names) |names| {
        for (names.items) |n| {
            const c = s.ds.indexOf(n) orelse return user(cx, lineOf(t, 0), "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
            if (s.ds.columns.items[c].type != .num) return user(cx, lineOf(t, 0), "Variable {s} in list does not match type prescribed for this list.", .{n});
            if (std.mem.indexOfScalar(usize, vars.items, c) != null) return gap(cx, lineOf(t, 0), "a variable listed twice in the VAR statement is not verified", .{});
            try vars.append(a, c);
        }
    } else {
        // "If you omit the VAR statement, the analysis uses all numeric
        // variables not specified in other statements" (p.2663).
        for (s.ds.columns.items, 0..) |col, c| {
            if (col.type != .num or c == s.class or c == s.freq or c == s.weight or c == s.id) continue;
            if (std.mem.indexOfScalar(usize, s.by_cols, c) != null) continue;
            try vars.append(a, c);
        }
    }
    if (vars.items.len == 0) return gap(cx, lineOf(t, 0), "an analysis without quantitative variables is not verified", .{});
    if (vars.items.len > 16) return gap(cx, lineOf(t, 0), "more than 16 quantitative variables are not implemented", .{});
    if (std.mem.indexOfScalar(usize, vars.items, s.class) != null) return gap(cx, lineOf(t, 0), "the CLASS variable in the VAR list is not verified", .{});
    s.vars = vars.items;
    return s;
}

// ── Analysis ────────────────────────────────────────────────────────────────

pub const Result = struct {
    base: candisc.Result,
    cov_inv: []f64, // p x p
    log_det: f64,
    dist: []f64, // c x c: dist[i*c+j] = D^2(i|j)
    constant: []f64, // c
    coef: []f64, // c x p: coef[j*p+k]
    classified: []f64, // c x c frequency counts: from i into j
    unknown: ?[]f64, // c counts of missing-CLASS observations classified into j
    prior: []f64,
};

pub const AnalysisError = candisc.AnalysisError || error{ MissingClass, Rank };

/// Cholesky inverse and log determinant of a symmetric positive definite
/// p x p matrix; error.Rank when it is not of full rank.
fn invert(a: A, m: []const f64, p: usize, inv: []f64) error{ OutOfMemory, Rank }!f64 {
    const l = try a.alloc(f64, p * p);
    @memset(l, 0);
    var log_det: f64 = 0;
    for (0..p) |i| for (0..i + 1) |j| {
        var x = m[i * p + j];
        for (0..j) |k| x -= l[i * p + k] * l[j * p + k];
        if (i == j) {
            if (!(x > 1e-12 * @abs(m[i * p + i]))) return error.Rank;
            l[i * p + i] = @sqrt(x);
            log_det += 2 * @log(l[i * p + i]);
        } else l[i * p + j] = x / l[j * p + j];
    };
    // Solve L L' X = I column by column.
    const y = try a.alloc(f64, p);
    for (0..p) |col| {
        for (0..p) |i| {
            var x: f64 = if (i == col) 1 else 0;
            for (0..i) |k| x -= l[i * p + k] * y[k];
            y[i] = x / l[i * p + i];
        }
        var i = p;
        while (i > 0) {
            i -= 1;
            var x = y[i];
            for (i + 1..p) |k| x -= l[k * p + i] * inv[k * p + col];
            inv[i * p + col] = x / l[i * p + i];
        }
    }
    return log_det;
}

fn quad(inv: []const f64, p: usize, d: []const f64) f64 {
    var s: f64 = 0;
    for (0..p) |i| for (0..p) |j| {
        s += d[i] * inv[i * p + j] * d[j];
    };
    return s;
}

fn classMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

pub fn analyze(a: A, s: Spec, rows: []const []const Value) AnalysisError!Result {
    const cs: candisc.Spec = .{ .ds = s.ds, .class = s.class, .vars = s.vars, .freq = s.freq, .weight = s.weight };
    var r: Result = undefined;
    r.base = try candisc.analyze(a, cs, rows);
    const b = r.base;
    // Missing Values (p.2664): an observation with a missing CLASS value is
    // left out of the calibration but still classified; the SAS 9.4
    // reference lists it as an unlabeled first row of the resubstitution
    // table. Verified for a character CLASS variable only.
    if (b.n_missing_class > 0 and s.ds.columns.items[s.class].type == .num) return error.MissingClass;
    const p = b.p;
    const c = b.levels.len;
    const dfe = b.nfreq - @as(f64, @floatFromInt(c));
    const cov = try a.alloc(f64, p * p);
    for (cov, b.e) |*x, e| x.* = e / dfe;
    r.cov_inv = try a.alloc(f64, p * p);
    r.log_det = try invert(a, cov, p, r.cov_inv);
    r.prior = try a.alloc(f64, c);
    @memset(r.prior, 1 / @as(f64, @floatFromInt(c)));
    const d = try a.alloc(f64, p);
    r.dist = try a.alloc(f64, c * c);
    for (0..c) |i| for (0..c) |j| {
        for (0..p) |k| d[k] = b.levels[i].mean[k] - b.levels[j].mean[k];
        r.dist[i * c + j] = if (i == j) 0 else quad(r.cov_inv, p, d);
    };
    r.constant = try a.alloc(f64, c);
    r.coef = try a.alloc(f64, c * p);
    for (b.levels, 0..) |l, j| {
        for (0..p) |k| {
            var x: f64 = 0;
            for (0..p) |m| x += r.cov_inv[k * p + m] * l.mean[m];
            r.coef[j * p + k] = x;
        }
        r.constant[j] = -0.5 * quad(r.cov_inv, p, l.mean);
    }
    // Resubstitution: each calibration observation goes to the class with
    // the smallest generalized squared distance (largest posterior).
    r.classified = try a.alloc(f64, c * c);
    @memset(r.classified, 0);
    r.unknown = null;
    if (b.n_missing_class > 0) {
        const u = try a.alloc(f64, c);
        @memset(u, 0);
        r.unknown = u;
    }
    for (rows) |row| {
        const no_class = classMissing(row[s.class]);
        var f: f64 = 1;
        if (s.freq) |fc| {
            const x = row[fc].num;
            if (std.math.isNan(x) or x < 1) continue;
            f = @trunc(x);
        }
        if (s.weight) |wc| {
            const x = row[wc].num;
            if (std.math.isNan(x) or x < 0) continue;
        }
        var complete = true;
        for (s.vars) |col| if (std.math.isNan(row[col].num)) {
            complete = false;
        };
        if (!complete) continue;
        const text = switch (row[s.class]) {
            .str => |x| std.mem.trimEnd(u8, x, " "),
            .num => std.mem.trim(u8, format.apply(a, row[s.class], "best12.") catch return error.OutOfMemory, " "),
        };
        var from: ?usize = null;
        if (!no_class) for (b.levels, 0..) |l, k| if (std.mem.eql(u8, l.text, text)) {
            from = k;
        };
        var best: usize = 0;
        var best_d = std.math.inf(f64);
        for (b.levels, 0..) |l, j| {
            for (s.vars, 0..) |col, k| d[k] = row[col].num - l.mean[k];
            const dj = quad(r.cov_inv, p, d);
            if (dj < best_d) {
                best_d = dj;
                best = j;
            }
        }
        if (from) |k| r.classified[k * c + best] += f else r.unknown.?[best] += f;
    }
    return r;
}

// ── Listing ─────────────────────────────────────────────────────────────────

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn fmt(a: A, x: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, spec), " ");
}

fn fixed(a: A, x: f64, d: usize) ![]const u8 {
    if (std.math.isNan(x)) return ".";
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, d });
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

fn isNumClass(s: Spec) bool {
    return s.ds.columns.items[s.class].type == .num;
}

fn levelWidth(s: Spec, r: candisc.Result) usize {
    const col = s.ds.columns.items[s.class];
    if (col.type == .num) return @max(6, col.name.len);
    var w: usize = col.name.len;
    for (r.levels) |l| w = @max(w, l.text.len);
    return w;
}

fn counts(a: A, out: *Out, r: candisc.Result) !void {
    const c = r.levels.len;
    const n: f64 = r.nfreq;
    const left = [_]struct { []const u8, f64 }{ .{ "Total Sample Size", n }, .{ "Variables", @floatFromInt(r.p) }, .{ "Classes", @floatFromInt(c) } };
    const right = [_]struct { []const u8, f64 }{ .{ "DF Total", n - 1 }, .{ "DF Within Classes", n - @as(f64, @floatFromInt(c)) }, .{ "DF Between Classes", @floatFromInt(c - 1) } };
    for (left, right) |l, rr| {
        const lv = try fmt(a, l[1], "best12.");
        const rv = try fmt(a, rr[1], "best12.");
        try pad(a, out, l[0], 38 - lv.len, true);
        try out.appendSlice(a, lv);
        try out.appendNTimes(a, ' ', 10);
        try pad(a, out, rr[0], 38 - rv.len, true);
        try out.appendSlice(a, rv);
        try out.append(a, '\n');
    }
}

fn nobs(a: A, out: *Out, s: Spec, r: candisc.Result) !void {
    var rows: std.ArrayList(struct { []const u8, f64 }) = .empty;
    try rows.append(a, .{ "Number of Observations Read", @floatFromInt(r.n_read) });
    try rows.append(a, .{ "Number of Observations Used", @floatFromInt(r.n_used) });
    if (s.freq != null) {
        try rows.append(a, .{ "Sum of Frequencies Read", r.freq_read });
        try rows.append(a, .{ "Sum of Frequencies Used", r.freq_used });
    }
    if (s.weight != null) {
        try rows.append(a, .{ "Sum of Weights Read", r.wt_read });
        try rows.append(a, .{ "Sum of Weights Used", r.wt_used });
    }
    for (rows.items) |row| {
        const v = try fmt(a, row[1], "best12.");
        try pad(a, out, row[0], 42 - v.len, true);
        try out.appendSlice(a, v);
        try out.append(a, '\n');
    }
}

fn levelsTable(a: A, out: *Out, s: Spec, r: Result) !void {
    const b = r.base;
    const w1 = levelWidth(s, b);
    var w2: usize = "Variable".len;
    for (b.levels) |l| w2 = @max(w2, l.text.len);
    const total = w1 + 4 + w2 + 55;
    try centered(a, out, "Class Level Information", total);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', w1 + 4);
    try pad(a, out, "Variable", total - w1 - 4 - 5, true);
    try out.appendSlice(a, "Prior\n");
    try pad(a, out, s.ds.columns.items[s.class].name, w1, !isNumClass(s));
    try out.appendNTimes(a, ' ', 4);
    try pad(a, out, "Name", w2, true);
    try pad(a, out, "Frequency", 13, false);
    try pad(a, out, "Weight", 13, false);
    try pad(a, out, "Proportion", 14, false);
    try pad(a, out, "Probability", 15, false);
    try out.appendSlice(a, "\n\n");
    for (b.levels, 0..) |l, k| {
        try pad(a, out, l.text, w1, !isNumClass(s));
        try out.appendNTimes(a, ' ', 4);
        try pad(a, out, l.text, w2, true);
        try pad(a, out, try fmt(a, l.freq, "best12."), 13, false);
        try pad(a, out, try fixed(a, l.weight, 4), 13, false);
        try pad(a, out, try fixed(a, l.freq / b.nfreq, 6), 14, false);
        try pad(a, out, try fixed(a, r.prior[k], 6), 15, false);
        try out.append(a, '\n');
    }
}

fn covInfo(a: A, out: *Out, r: Result) !void {
    try out.appendSlice(a, "Pooled Covariance Matrix Information\n \n" ++
        "               Natural Log of the\n" ++
        " Covariance    Determinant of the\n" ++
        "Matrix Rank     Covariance Matrix\n\n");
    try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{r.base.p}), 11, false);
    try pad(a, out, try fixed(a, r.log_det, 5), 22, false);
    try out.append(a, '\n');
}

fn levelHeader(a: A, out: *Out, s: Spec, r: candisc.Result, first: []const u8, w1: usize, widths: []const usize, total: ?[]const u8, total_w: usize) !void {
    try pad(a, out, first, w1, true);
    for (r.levels, widths) |l, w| try pad(a, out, l.text, w, false);
    if (total) |tt| try pad(a, out, tt, total_w, false);
    try out.appendSlice(a, "\n\n");
    _ = s;
}

fn sum(xs: []const usize) usize {
    var t: usize = 0;
    for (xs) |x| t += x;
    return t;
}

fn distances(a: A, out: *Out, s: Spec, r: Result) !void {
    const b = r.base;
    const c = b.levels.len;
    const cname = s.ds.columns.items[s.class].name;
    try out.appendSlice(a, "Pairwise Generalized Squared Distances Between Groups\n\n" ++
        " 2         _   _       -1  _   _  \n" ++
        "D (i|j) = (X - X )' COV   (X - X )\n" ++
        "            i   j           i   j \n\n\n");
    const w1 = @max(levelWidth(s, b), "Priors".len);
    const widths = try a.alloc(usize, c);
    for (widths, b.levels) |*w, l| w.* = @max(14, l.text.len + 2);
    try centered(a, out, try std.fmt.allocPrint(a, "Generalized Squared Distance to {s}", .{cname}), w1 + sum(widths));
    try out.appendSlice(a, " \nFrom\n");
    try levelHeader(a, out, s, b, cname, w1, widths, null, 0);
    for (b.levels, 0..) |l, i| {
        try pad(a, out, l.text, w1, !isNumClass(s));
        for (0..c) |j| {
            const v = r.dist[i * c + j];
            try pad(a, out, if (v == 0) "0" else try fixed(a, v, 5), widths[j], false);
        }
        try out.append(a, '\n');
    }
}

fn linearFunction(a: A, out: *Out, s: Spec, r: Result) !void {
    const b = r.base;
    const p = b.p;
    const cname = s.ds.columns.items[s.class].name;
    try out.appendSlice(a, "Linear Discriminant Function\n\n" ++
        "               _     -1 _                              -1 _ \n" ++
        "Constant = -.5 X' COV   X      Coefficient Vector = COV   X \n" ++
        "                j        j                                 j\n\n\n");
    var w1: usize = "Variable".len;
    for (s.vars) |col| w1 = @max(w1, s.ds.columns.items[col].name.len);
    const widths = try a.alloc(usize, b.levels.len);
    for (widths, b.levels) |*w, l| w.* = @max(14, l.text.len + 2);
    try centered(a, out, try std.fmt.allocPrint(a, "Linear Discriminant Function for {s}", .{cname}), w1 + sum(widths));
    try out.appendSlice(a, " \n");
    try levelHeader(a, out, s, b, "Variable", w1, widths, null, 0);
    try pad(a, out, "Constant", w1, true);
    for (r.constant, widths) |x, w| try pad(a, out, try fixed(a, x, 5), w, false);
    try out.append(a, '\n');
    for (s.vars, 0..) |col, k| {
        try pad(a, out, s.ds.columns.items[col].name, w1, true);
        for (widths, 0..) |w, j| try pad(a, out, try fixed(a, r.coef[j * p + k], 5), w, false);
        try out.append(a, '\n');
    }
}

fn classification(a: A, out: *Out, s: Spec, r: Result) !void {
    const b = r.base;
    const c = b.levels.len;
    const cname = s.ds.columns.items[s.class].name;
    try out.appendSlice(a, try std.fmt.allocPrint(a, "Classification Summary for Calibration Data: {s}\n", .{try varlist.datasetName(a, s.ds)}));
    try out.appendSlice(a, "Resubstitution Summary using Linear Discriminant Function\n\n" ++
        "Generalized Squared Distance Function\n\n" ++
        " 2         _       -1   _  \n" ++
        "D (X) = (X-X )' COV  (X-X )\n" ++
        " j          j            j \n\n");
    try out.appendSlice(a, try std.fmt.allocPrint(a, "Posterior Probability of Membership in Each {s}\n\n", .{cname}));
    try out.appendSlice(a, "                   2                    2    \n" ++
        "Pr(j|X) = exp(-.5 D (X)) / SUM exp(-.5 D (X))\n" ++
        "                   j        k           k    \n\n\n");
    // ponytail: column widths calibrated on the SAS 9.4 reference listing
    // (13 for short level names, name length + 6 for longer ones).
    const w1 = @max(levelWidth(s, b), "Priors".len);
    const widths = try a.alloc(usize, c);
    for (widths, b.levels) |*w, l| w.* = @max(13, l.text.len + 6);
    const total_w = w1 + sum(widths) + 13;
    try centered(a, out, try std.fmt.allocPrint(a, "Number of Observations and Percent Classified into {s}", .{cname}), total_w);
    try out.appendSlice(a, " \nFrom\n");
    try levelHeader(a, out, s, b, cname, w1, widths, "Total", 13);
    const col_tot = try a.alloc(f64, c);
    @memset(col_tot, 0);
    var grand: f64 = 0;
    if (r.unknown) |u| {
        var row_tot: f64 = 0;
        for (u) |x| row_tot += x;
        try out.appendNTimes(a, ' ', w1);
        for (u, widths, 0..) |x, w, j| {
            try pad(a, out, try fmt(a, x, "best12."), w, false);
            col_tot[j] += x;
        }
        try pad(a, out, try fmt(a, row_tot, "best12."), 13, false);
        try out.append(a, '\n');
        try out.appendNTimes(a, ' ', w1);
        for (u, widths) |x, w| try pad(a, out, try fixed(a, 100 * x / row_tot, 2), w, false);
        try pad(a, out, "100.00", 13, false);
        try out.appendSlice(a, "\n\n");
        grand += row_tot;
    }
    for (b.levels, 0..) |l, i| {
        var row_tot: f64 = 0;
        for (0..c) |j| row_tot += r.classified[i * c + j];
        try pad(a, out, l.text, w1, !isNumClass(s));
        for (0..c) |j| {
            try pad(a, out, try fmt(a, r.classified[i * c + j], "best12."), widths[j], false);
            col_tot[j] += r.classified[i * c + j];
        }
        try pad(a, out, try fmt(a, row_tot, "best12."), 13, false);
        try out.append(a, '\n');
        try out.appendNTimes(a, ' ', w1);
        for (0..c) |j| try pad(a, out, try fixed(a, 100 * r.classified[i * c + j] / row_tot, 2), widths[j], false);
        try pad(a, out, "100.00", 13, false);
        try out.appendSlice(a, "\n\n");
        grand += row_tot;
    }
    try pad(a, out, "Total", w1, true);
    for (col_tot, widths) |x, w| try pad(a, out, try fmt(a, x, "best12."), w, false);
    try pad(a, out, try fmt(a, grand, "best12."), 13, false);
    try out.append(a, '\n');
    try out.appendNTimes(a, ' ', w1);
    for (col_tot, widths) |x, w| try pad(a, out, try fixed(a, 100 * x / grand, 2), w, false);
    try pad(a, out, "100.00", 13, false);
    try out.appendSlice(a, "\n\n");
    try pad(a, out, "Priors", w1, true);
    for (r.prior, widths) |x, w| try pad(a, out, try fixed(a, x, 5), w, false);
    try out.appendNTimes(a, ' ', 13);
    try out.append(a, '\n');
    try out.appendNTimes(a, ' ', total_w);
    try out.append(a, '\n');
}

fn errorCounts(a: A, out: *Out, s: Spec, r: Result) !void {
    const b = r.base;
    const c = b.levels.len;
    const cname = s.ds.columns.items[s.class].name;
    const rate = try a.alloc(f64, c);
    for (0..c) |i| {
        var row_tot: f64 = 0;
        for (0..c) |j| row_tot += r.classified[i * c + j];
        rate[i] = 1 - r.classified[i * c + i] / row_tot;
    }
    // Error Count Estimates: rate_j = 1 - correct_j / n_j; Total = SUM q_j rate_j.
    const e1: usize = 12;
    const ew = try a.alloc(usize, c);
    for (ew, b.levels) |*w, l| w.* = @max(12, l.text.len + 4);
    try centered(a, out, try std.fmt.allocPrint(a, "Error Count Estimates for {s}", .{cname}), e1 + sum(ew) + 12);
    try out.appendSlice(a, " \n");
    try levelHeader(a, out, s, b, "", e1, ew, "Total", 12);
    var total_rate: f64 = 0;
    for (rate, r.prior) |x, q| total_rate += x * q;
    try pad(a, out, "Rate", e1, true);
    for (rate, ew) |x, w| try pad(a, out, try fixed(a, x, 4), w, false);
    try pad(a, out, try fixed(a, total_rate, 4), 12, false);
    try out.append(a, '\n');
    try pad(a, out, "Priors", e1, true);
    for (r.prior, ew) |x, w| try pad(a, out, try fixed(a, x, 4), w, false);
    try out.appendNTimes(a, ' ', 12);
    try out.append(a, '\n');
}

fn accepts(cx: proc.ProcCtx, name: []const u8) bool {
    const l = cx.listing orelse return true;
    var buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "Discrim.{s}", .{name}) catch return true;
    return l.accepts(path);
}

fn page(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, rep: ?[]const Value) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
    if (s.by_cols.len > 0) {
        var line: Out = .empty;
        try by.appendLine(a, &line, s.ds, rep.?, s.by_cols);
        if (line.items.len > 0) {
            try out.append(a, '\n');
            try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
        }
    }
    try out.appendSlice(a, "\nThe DISCRIM Procedure\n");
}

pub fn render(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, r: Result, rep: ?[]const Value) !void {
    const pages = try a.alloc(Out, 3);
    for (pages) |*pg| pg.* = .empty;
    const parts = [_]struct { usize, []const u8 }{ .{ 0, "Counts" }, .{ 0, "NObs" }, .{ 0, "ClassLevels" }, .{ 0, "PooledCovInfo" }, .{ 1, "Dist" }, .{ 1, "LinearDiscFunc" }, .{ 2, "ClassifiedResub" }, .{ 2, "ErrorResub" } };
    for (parts, 0..) |part, k| {
        if (!accepts(cx, part[1])) continue;
        const pg = &pages[part[0]];
        // Page 1 separates tables by two blank lines, pages 2-3 by one; the
        // classification page starts right below the procedure name.
        if (pg.items.len > 0) {
            try pg.appendSlice(a, if (part[0] == 0) "\n\n" else "\n");
        } else if (part[0] < 2) try pg.append(a, '\n');
        switch (k) {
            0 => try counts(a, pg, r.base),
            1 => try nobs(a, pg, s, r.base),
            2 => try levelsTable(a, pg, s, r),
            3 => try covInfo(a, pg, r),
            4 => try distances(a, pg, s, r),
            5 => try linearFunction(a, pg, s, r),
            6 => try classification(a, pg, s, r),
            else => try errorCounts(a, pg, s, r),
        }
    }
    for (pages) |pg| if (pg.items.len > 0) {
        try page(a, cx, out, s, rep);
        try out.appendSlice(a, pg.items);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    };
}

fn warnings(cx: proc.ProcCtx, r: candisc.Result) !void {
    if (r.n_missing_vars > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group will not be included in the analysis due to missing values.", .{r.n_missing_vars});
    if (r.n_missing_class > 0) try cx.diags.warnStatus(0, "{d} observations in DATA= data set or BY group are excluded from the development of the classification criterion due to missing values on CLASS variable.", .{r.n_missing_class});
    if (r.n_invalid > 0) try cx.diags.warnStatus(0, "{d} observations excluded due to invalid WEIGHT or FREQ variable values.", .{r.n_invalid});
    const excluded = r.n_missing_vars + r.n_missing_class + r.n_invalid;
    if (excluded > 0) try cx.diags.warnStatus(0, "A total of {d} of the {d} observations in the DATA= data set were excluded (frequency sum = {s}).", .{ excluded, r.n_read, std.mem.trim(u8, try format.apply(cx.arena, .{ .num = r.freq_used }, "best12."), " ") });
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (s.ds.rows.items.len == 0) return gap(cx, 0, "an empty input data set is not verified", .{});
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const results = try a.alloc(Result, slices.len);
    for (slices, results) |slice, *r| {
        r.* = analyze(a, s, slice.rows) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Empty => return gap(cx, 0, "a BY group or data set without usable observations is not verified", .{}),
            error.OneLevel => return gap(cx, 0, "a CLASS variable with fewer than two levels is not verified", .{}),
            error.NoDf => return gap(cx, 0, "an analysis without within-class degrees of freedom is not verified", .{}),
            error.Singular, error.Rank => return gap(cx, 0, "a singular pooled covariance matrix (or zero weights) is not implemented (owned by a later DISCRIM ticket)", .{}),
            error.MissingClass => return gap(cx, 0, "observations with a missing CLASS value are not implemented", .{}),
        };
        for (r.base.levels) |l| if (l.freq == 1) return gap(cx, 0, "a class level with a single observation is not verified", .{});
    }
    for (slices, results) |slice, r| {
        try warnings(cx, r.base);
        if (!s.noprint) try render(a, cx, out, s, r, slice.rep);
    }
}

test {
    _ = @import("discrim_tests.zig");
}
