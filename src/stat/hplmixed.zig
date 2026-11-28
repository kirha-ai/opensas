//! PROC HPLMIXED (S154 Chapter 60, PROC HPLMIXED/CLASS/ID/MODEL/RANDOM
//! statements, physical pp.4701-4707): declarations, variable roles, missing
//! values and the default listing for the one estimation shape whose REML
//! solution is closed form and therefore exact:
//!   random coefficients with TYPE=UN, one SUBJECT= effect, RANDOM columns
//!   identical to the MODEL columns (intercept included), every subject with
//!   the same ordered design rows Z_i (balanced). Then V_i = Z G Z' + s2 I and
//!   the REML likelihood separates into the within-subject residual part
//!   (s2 = sum RSS_i / (m(k-q))) and the between part b_i = (Z'Z)^-1 Z'y_i
//!   ~ N(beta, G + s2 (Z'Z)^-1), whose REML covariance is the m-1 divisor
//!   sample covariance S; so G = S - s2 (Z'Z)^-1 when that is positive
//!   definite. Everything else is a loud gap. The NRRIDG iteration history
//!   (SAS starting values and optimizer path) is not reproduced: the listing
//!   omits it and the step reports a gap (rc 2).
const std = @import("std");
const proc = @import("../proc.zig");
const hp = @import("hp_shared.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const fmt = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const reg_fit = @import("reg_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

/// One MODEL/RANDOM term: a product of numeric continuous columns.
pub const Term = struct { name: []const u8, columns: []const usize };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    response: usize = 0,
    classes: []const usize = &.{},
    ids: []const usize = &.{},
    fixed: []const Term = &.{},
    fixed_intercept: bool = true,
    solution: bool = false,
    random: []const Term = &.{},
    random_intercept: bool = false,
    random_seen: bool = false,
    /// SUBJECT= variables: the first, then the nesting variables.
    subject: []const usize = &.{},
    subject_name: []const u8 = "",
    type_un: bool = false,
    namelen: usize = 20,
    maxclprint: usize = 20,
    noclprint: bool = false,
    noprint: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC HPLMIXED: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC HPLMIXED: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
/// Documented PROC options (Table 60.2, pp.4701-4705) whose effect is owned by
/// later HPLMIXED / shared HP tickets.
const later_options = [_][]const u8{ "absconv", "absfconv", "absgconv", "fconv", "gconv", "maxiter", "maxfunc", "maxtime", "miniter", "technique", "tech", "xconv", "blup", "ranks", "singchol", "singsweep", "singular", "itprint", "tol" };
const later_statements = [_][]const u8{ "repeated", "parms", "output", "nloptions", "by", "freq", "weight", "code" };
const later_model_options = [_][]const u8{ "alpha", "cl", "ddfm", "noint", "chisq", "e", "e1", "e2", "e3", "htype" };
const later_random_options = [_][]const u8{ "group", "grp", "alpha", "cl", "solution", "s", "g", "gcorr", "v", "vcorr" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!f64 {
    if (at(t, i, .minus) and at(t, i + 1, .number)) return -(std.fmt.parseFloat(f64, t[i + 1].text) catch return invalid(cx, t, i + 1));
    if (!at(t, i, .number)) return invalid(cx, t, i);
    return std.fmt.parseFloat(f64, t[i].text) catch invalid(cx, t, i);
}
fn isClass(s: Spec, c: usize) bool {
    return std.mem.indexOfScalar(usize, s.classes, c) != null;
}

/// Effect list `a a*b ...` up to `end`/slash. Class variables in effects are
/// a gap (class-effect design columns: later MODEL ticket).
fn terms(cx: proc.ProcCtx, s: Spec, t: []const lex.Token, start: usize, end: usize, allow_int: bool, intercept: *bool, out: *std.ArrayList(Term)) diag.Error!usize {
    const ds = s.input.ds;
    var j = start;
    while (j < end and !at(t, j, .slash)) {
        if (allow_int and (kw(t, j, "int") or kw(t, j, "intercept"))) {
            intercept.* = true;
            j += 1;
            continue;
        }
        var cols: std.ArrayList(usize) = .empty;
        var name: Out = .empty;
        while (true) {
            if (at(t, j, .lparen) or at(t, j, .pipe) or at(t, j, .at)) return gap(cx, t[j].line, "nested, bar and degree effects are not implemented", .{});
            const c = try column(cx, ds, t, j);
            if (isClass(s, c)) return gap(cx, t[j].line, "CLASS variable {s} in a MODEL/RANDOM effect is not implemented", .{t[j].text});
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[j].line, "PROC HPLMIXED: character variable {s} must be a CLASS variable", .{t[j].text});
            if (name.items.len > 0) try name.append(cx.arena, '*');
            try name.appendSlice(cx.arena, ds.columns.items[c].name);
            try cols.append(cx.arena, c);
            j += 1;
            if (j < end and at(t, j, .star)) {
                j += 1;
                continue;
            }
            break;
        }
        for (out.items) |prior| if (std.mem.eql(usize, prior.columns, cols.items)) return gap(cx, t[start].line, "repeated effect {s} policy is not verified", .{name.items});
        try out.append(cx.arena, .{ .name = name.items, .columns = cols.items });
    }
    return j;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .data_name = "" };
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
        } else if (eq(word, "method") and at(t, i + 1, .eq)) {
            // p.4704: REML (default) or ML.
            if (kw(t, i + 2, "ml")) return gap(cx, t[i].line, "METHOD=ML is not implemented", .{});
            if (!kw(t, i + 2, "reml")) return cx.diags.fail(error.ParseError, lineOf(t, i + 2), "PROC HPLMIXED: METHOD= must be REML or ML", .{});
            i += 3;
        } else if (eq(word, "namelen") and at(t, i + 1, .eq)) {
            // p.4705: the minimum value is 20, also the default.
            const v = try number(cx, t, i + 2);
            if (!(v >= 20) or v != @trunc(v)) return cx.diags.fail(error.ParseError, t[i + 2].line, "PROC HPLMIXED: NAMELEN= must be an integer of at least 20", .{});
            s.namelen = @intFromFloat(@min(v, 1e6));
            i += 3;
        } else if (eq(word, "maxclprint") and at(t, i + 1, .eq)) {
            // p.4703: default 20; 0 prints every level.
            const v = try number(cx, t, i + 2);
            if (!(v >= 0) or v != @trunc(v)) return cx.diags.fail(error.ParseError, t[i + 2].line, "PROC HPLMIXED: MAXCLPRINT= must be a nonnegative integer", .{});
            s.maxclprint = @intFromFloat(@min(v, 1e9));
            i += 3;
        } else if (eq(word, "noclprint")) {
            if (at(t, i + 1, .eq)) return gap(cx, t[i].line, "NOCLPRINT=number is not implemented", .{});
            s.noclprint = true;
            i += 1;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC HPLMIXED: input dataset not found", .{});
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
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var fixed: std.ArrayList(Term) = .empty;
    var random: std.ArrayList(Term) = .empty;
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
            // p.4706: the CLASS statement must precede the MODEL statement.
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPLMIXED: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                if (at(t, j, .slash) or at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
            }
            s.classes = classes.items;
        } else if (kw(t, i, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPLMIXED: only one MODEL statement is allowed", .{});
            model_seen = true;
            s.response = try column(cx, ds, t, i + 1);
            if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, t[i + 1].line, "PROC HPLMIXED: response variable {s} must be numeric", .{t[i + 1].text});
            if (isClass(s, s.response)) return cx.diags.fail(error.ParseError, t[i + 1].line, "PROC HPLMIXED: the response variable cannot be a CLASS variable", .{});
            if (!at(t, i + 2, .eq)) return invalid(cx, t, i + 2);
            var ignored = false;
            var j = try terms(cx, s, t, i + 3, end, false, &ignored, &fixed);
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, end);
                while (j < end) : (j += 1) {
                    if (kw(t, j, "solution") or kw(t, j, "s")) {
                        s.solution = true;
                    } else if (at(t, j, .name) and oneOf(t[j].text, &later_model_options)) {
                        return gap(cx, t[j].line, "MODEL option {s} is not implemented", .{t[j].text});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "random")) {
            if (s.random_seen) return gap(cx, t[i].line, "multiple RANDOM statements are not implemented", .{});
            s.random_seen = true;
            var j = try terms(cx, s, t, i + 1, end, true, &s.random_intercept, &random);
            if (!at(t, j, .slash)) return gap(cx, t[i].line, "RANDOM without SUBJECT= and TYPE=UN is not implemented", .{});
            j += 1;
            while (j < end) {
                if ((kw(t, j, "subject") or kw(t, j, "sub")) and at(t, j + 1, .eq)) {
                    j += 2;
                    var subs: std.ArrayList(usize) = .empty;
                    const first = try column(cx, ds, t, j);
                    try subs.append(cx.arena, first);
                    var label: Out = .empty;
                    try label.appendSlice(cx.arena, ds.columns.items[first].name);
                    j += 1;
                    if (at(t, j, .lparen)) {
                        try label.append(cx.arena, '(');
                        j += 1;
                        var k: usize = 0;
                        while (j < end and !at(t, j, .rparen)) : (j += 1) {
                            const c = try column(cx, ds, t, j);
                            try subs.append(cx.arena, c);
                            if (k > 0) try label.append(cx.arena, ' ');
                            try label.appendSlice(cx.arena, ds.columns.items[c].name);
                            k += 1;
                        }
                        if (!at(t, j, .rparen) or k == 0) return invalid(cx, t, j);
                        try label.append(cx.arena, ')');
                        j += 1;
                    } else if (at(t, j, .star)) return gap(cx, t[j].line, "crossed SUBJECT= effects are not implemented", .{});
                    for (subs.items) |c| if (!isClass(s, c)) return gap(cx, t[j - 1].line, "SUBJECT= variable {s} that is not a CLASS variable is not implemented", .{ds.columns.items[c].name});
                    s.subject = subs.items;
                    s.subject_name = label.items;
                } else if (kw(t, j, "type") and at(t, j + 1, .eq)) {
                    if (!kw(t, j + 2, "un")) return gap(cx, t[j].line, "RANDOM TYPE={s} is not implemented", .{if (j + 2 < t.len) t[j + 2].text else ""});
                    s.type_un = true;
                    j += 3;
                } else if (at(t, j, .name) and oneOf(t[j].text, &later_random_options)) {
                    return gap(cx, t[j].line, "RANDOM option {s} is not implemented", .{t[j].text});
                } else return invalid(cx, t, j);
            }
            if (s.subject.len == 0 or !s.type_un) return gap(cx, t[i].line, "RANDOM without SUBJECT= and TYPE=UN is not implemented", .{});
        } else if (kw(t, i, "id")) {
            // p.4706: ID variables are copied to the OUTPUT OUT= data set only
            // (OUTPUT: later ticket); they are validated and recorded.
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| try ids.append(cx.arena, try column(cx, ds, t, j));
        } else if (kw(t, i, "performance")) {
            // Shared single-machine PERFORMANCE contract (STAT-HP-001).
            var perf: hp.Performance = .{};
            try hp.parsePerformance(cx.diags, "HPLMIXED", t, i, end, &perf);
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC HPLMIXED: MODEL statement required", .{});
    s.ids = ids.items;
    s.fixed = fixed.items;
    s.random = random.items;
    return s;
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| !std.math.isFinite(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// Observation selection: an observation with a missing response, MODEL or
/// RANDOM variable, SUBJECT= variable or CLASS variable is not used. With
/// `levels_only`, only missing CLASS/SUBJECT values exclude: SAS counts CLASS
/// levels and Subjects over those rows, so a subject whose responses are all
/// missing is still a level and a subject (SAS-verified, small fixture:
/// 7 subjects, 36 of 39 observations used). ponytail: a missing MODEL
/// covariate is assumed to behave like a missing response here.
pub fn usedRows(a: A, s: Spec, levels_only: bool) ![]const []const Value {
    var used: std.ArrayList([]const Value) = .empty;
    rows: for (s.input.ds.rows.items) |row| {
        for (s.classes) |c| if (missing(row[c])) continue :rows;
        for (s.subject) |c| if (missing(row[c])) continue :rows;
        if (levels_only) {
            try used.append(a, row);
            continue;
        }
        if (missing(row[s.response])) continue;
        for (s.fixed) |term| for (term.columns) |c| if (missing(row[c])) continue :rows;
        for (s.random) |term| for (term.columns) |c| if (missing(row[c])) continue :rows;
        try used.append(a, row);
    }
    return used.items;
}

fn subjectKey(a: A, s: Spec, row: []const Value) ![]const u8 {
    var key: Out = .empty;
    for (s.subject) |c| switch (row[c]) {
        .num => |x| try key.print(a, "n{x}|", .{@as(u64, @bitCast(x))}),
        .str => |text| try key.print(a, "s{s}|", .{std.mem.trimEnd(u8, text, " ")}),
    };
    return key.items;
}
pub fn subjectCount(a: A, s: Spec, rows: []const []const Value) !usize {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (rows) |row| try seen.put(a, try subjectKey(a, s, row), {});
    return seen.count();
}

pub const Fit = struct {
    /// Subjects with used observations (estimation) and over the level rows
    /// (Dimensions "Subjects" and the BIC penalty).
    m: usize,
    subjects: usize = 0,
    k: usize,
    q: usize,
    n: usize,
    g: []f64,
    sigma2: f64,
    beta: []f64,
    se: []f64,
    minus2: f64,
};

fn product(row: []const Value, term: Term) f64 {
    var v: f64 = 1;
    for (term.columns) |c| v *= row[c].num;
    return v;
}
fn invert(a: A, m: []const f64, n: usize) ![]f64 {
    const w = try a.dupe(f64, m);
    const r = try a.alloc(f64, n * n);
    @memset(r, 0);
    for (0..n) |i| r[i * n + i] = 1;
    for (0..n) |col| {
        var piv = col;
        for (col + 1..n) |i| if (@abs(w[i * n + col]) > @abs(w[piv * n + col])) {
            piv = i;
        };
        if (!(@abs(w[piv * n + col]) > 1e-12)) return error.Singular;
        for (0..n) |j| {
            std.mem.swap(f64, &w[col * n + j], &w[piv * n + j]);
            std.mem.swap(f64, &r[col * n + j], &r[piv * n + j]);
        }
        const d = w[col * n + col];
        for (0..n) |j| {
            w[col * n + j] /= d;
            r[col * n + j] /= d;
        }
        for (0..n) |i| if (i != col) {
            const f = w[i * n + col];
            if (f != 0) for (0..n) |j| {
                w[i * n + j] -= f * w[col * n + j];
                r[i * n + j] -= f * r[col * n + j];
            };
        };
    }
    return r;
}
/// log determinant through Cholesky; error.NotPositive when not PD.
fn logdet(a: A, m: []const f64, n: usize) !f64 {
    const l = try a.dupe(f64, m);
    var sum: f64 = 0;
    for (0..n) |j| {
        var d = l[j * n + j];
        for (0..j) |k| d -= l[j * n + k] * l[j * n + k];
        if (!(d > 0)) return error.NotPositive;
        const root = @sqrt(d);
        l[j * n + j] = root;
        sum += 2 * @log(root);
        for (j + 1..n) |i| {
            var v = l[i * n + j];
            for (0..j) |k| v -= l[i * n + k] * l[j * n + k];
            l[i * n + j] = v / root;
        }
    }
    return sum;
}

/// Closed-form balanced REML (see file comment). Errors name the boundary.
pub fn fit(a: A, s: Spec, rows: []const []const Value) !Fit {
    if (!s.random_intercept or !s.fixed_intercept or s.random.len != s.fixed.len) return error.NotBalancedShape;
    for (s.random, s.fixed) |r, f| if (!std.mem.eql(usize, r.columns, f.columns)) return error.NotBalancedShape;
    const q = 1 + s.fixed.len;
    // Subjects in order of first appearance, keyed by their raw values.
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    var members: std.ArrayList(std.ArrayList(usize)) = .empty;
    for (rows, 0..) |row, r| {
        const got = try index.getOrPut(a, try subjectKey(a, s, row));
        if (!got.found_existing) {
            got.value_ptr.* = members.items.len;
            try members.append(a, .empty);
        }
        try members.items[got.value_ptr.*].append(a, r);
    }
    const m = members.items.len;
    const k = members.items[0].items.len;
    if (m < 2 or k <= q) return error.NotBalancedShape;
    const z = try a.alloc(f64, k * q);
    for (members.items[0].items, 0..) |r, i| {
        z[i * q] = 1;
        for (s.fixed, 1..) |term, j| z[i * q + j] = product(rows[r], term);
    }
    for (members.items) |list| {
        if (list.items.len != k) return error.NotBalancedShape;
        for (list.items, 0..) |r, i| for (s.fixed, 1..) |term, j| if (product(rows[r], term) != z[i * q + j]) return error.NotBalancedShape;
    }
    const ztz = try a.alloc(f64, q * q);
    for (0..q) |i| for (0..q) |j| {
        var v: f64 = 0;
        for (0..k) |o| v += z[o * q + i] * z[o * q + j];
        ztz[i * q + j] = v;
    };
    const ainv = try invert(a, ztz, q);
    const b = try a.alloc(f64, m * q);
    var rss: f64 = 0;
    const zy = try a.alloc(f64, q);
    for (members.items, 0..) |list, si| {
        @memset(zy, 0);
        for (list.items, 0..) |r, o| for (0..q) |j| {
            zy[j] += z[o * q + j] * rows[r][s.response].num;
        };
        for (0..q) |i| {
            var v: f64 = 0;
            for (0..q) |j| v += ainv[i * q + j] * zy[j];
            b[si * q + i] = v;
        }
        for (list.items, 0..) |r, o| {
            var fitted: f64 = 0;
            for (0..q) |j| fitted += z[o * q + j] * b[si * q + j];
            const e = rows[r][s.response].num - fitted;
            rss += e * e;
        }
    }
    const sigma2 = rss / @as(f64, @floatFromInt(m * (k - q)));
    const mean = try a.alloc(f64, q);
    @memset(mean, 0);
    for (0..m) |si| for (0..q) |j| {
        mean[j] += b[si * q + j];
    };
    for (mean) |*v| v.* /= @floatFromInt(m);
    const g = try a.alloc(f64, q * q);
    @memset(g, 0);
    for (0..m) |si| for (0..q) |i| for (0..q) |j| {
        g[i * q + j] += (b[si * q + i] - mean[i]) * (b[si * q + j] - mean[j]);
    };
    for (g, ainv) |*v, ai| v.* = v.* / @as(f64, @floatFromInt(m - 1)) - sigma2 * ai;
    _ = logdet(a, g, q) catch return error.BoundaryG;
    // -2 Res Log Likelihood (p.4729 shape, MIXED physical p.6701):
    // (N-p) log 2pi + sum log|V_i| + log|sum X_i'V_i^-1 X_i| + sum r_i'V_i^-1 r_i.
    const v = try a.alloc(f64, k * k);
    for (0..k) |o| for (0..k) |p| {
        var x: f64 = if (o == p) sigma2 else 0;
        for (0..q) |i| for (0..q) |j| {
            x += z[o * q + i] * g[i * q + j] * z[p * q + j];
        };
        v[o * k + p] = x;
    };
    const vinv = try invert(a, v, k);
    const ld = try logdet(a, v, k);
    const w = try a.alloc(f64, q * q);
    for (0..q) |i| for (0..q) |j| {
        var x: f64 = 0;
        for (0..k) |o| for (0..k) |p| {
            x += z[o * q + i] * vinv[o * k + p] * z[p * q + j];
        };
        w[i * q + j] = x * @as(f64, @floatFromInt(m));
    };
    const n = rows.len;
    var quad: f64 = 0;
    const res = try a.alloc(f64, k);
    for (members.items) |list| {
        for (list.items, 0..) |r, o| {
            var fitted: f64 = 0;
            for (0..q) |j| fitted += z[o * q + j] * mean[j];
            res[o] = rows[r][s.response].num - fitted;
        }
        for (0..k) |o| for (0..k) |p| {
            quad += res[o] * vinv[o * k + p] * res[p];
        };
    }
    const minus2 = @as(f64, @floatFromInt(n - q)) * @log(2 * std.math.pi) + @as(f64, @floatFromInt(m)) * ld + try logdet(a, w, q) + quad;
    const cov = try invert(a, w, q);
    const se = try a.alloc(f64, q);
    for (se, 0..) |*e, i| e.* = @sqrt(cov[i * q + i]);
    return .{ .m = m, .k = k, .q = q, .n = n, .g = g, .sigma2 = sigma2, .beta = mean, .se = se, .minus2 = minus2 };
}

fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn title(a: A, out: *Out, text: []const u8, width: usize, spaced: bool) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, if (spaced) "\n \n" else "\n\n");
}
fn infoTable(a: A, out: *Out, heading: []const u8, lines: []const [2][]const u8, value_right: bool) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (lines) |l| {
        lw = @max(lw, l[0].len);
        vw = @max(vw, l[1].len);
    }
    try title(a, out, heading, lw + 4 + vw, false);
    for (lines) |l| {
        try left(a, out, l[0], lw + 4);
        if (value_right) try right(a, out, l[1], vw) else try left(a, out, l[1], vw);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
}
/// Estimate/standard-error display. ponytail: derived from the reference
/// listing (2.0902, 0.5010, 0.01448, 0.005247, 0.000349): four decimals at or
/// above 1, otherwise four significant digits capped at six decimals. Exact
/// SAS template format for other magnitudes is unverified.
fn sig4(a: A, x: f64) ![]const u8 {
    const ax = @abs(x);
    var decimals: usize = 4;
    if (ax > 0 and ax < 1) {
        const mag: i64 = @intFromFloat(@floor(std.math.log10(ax)));
        decimals = @intCast(@min(@as(i64, 6), 3 - mag));
    }
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn numText(a: A, x: f64, spec: []const u8) ![]const u8 {
    // ponytail: Fit Statistics display derived from the two SAS listings
    // (59.38641, 68.76572; 225642): BEST8. below 1E5, else rounded integer.
    if (std.mem.eql(u8, spec, "fit")) return if (@abs(x) >= 1e5 and @abs(x) < 1e8) std.fmt.allocPrint(a, "{d:.0}", .{x}) else numText(a, x, "best8.");
    return std.mem.trim(u8, try fmt.apply(a, .{ .num = x }, spec), " ");
}
fn cellLess(_: void, x: Value, y: Value) bool {
    return proc.cmpValue(x, y) == .lt;
}

/// Subject label shortened to NAMELEN (p.4705). ponytail: the reference
/// shortens the leading variable name of a nested effect; other shapes gap.
fn shortened(cx: proc.ProcCtx, s: Spec) diag.Error![]const u8 {
    if (s.subject_name.len <= s.namelen) return s.subject_name;
    const lead = s.input.ds.columns.items[s.subject[0]].name;
    const over = s.subject_name.len - s.namelen;
    if (over >= lead.len) return gap(cx, 0, "shortening subject effect name {s} is not implemented", .{s.subject_name});
    return std.fmt.allocPrint(cx.arena, "{s}{s}", .{ lead[0 .. lead.len - over], s.subject_name[lead.len..] });
}

fn classTable(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    var names_w: usize = 5;
    const texts = try a.alloc([]const u8, s.classes.len);
    const counts = try a.alloc(usize, s.classes.len);
    for (s.classes, texts, counts) |c, *text, *count| {
        names_w = @max(names_w, ds.columns.items[c].name.len);
        var values: std.ArrayList(Value) = .empty;
        for (rows) |row| try values.append(a, row[c]);
        std.mem.sort(Value, values.items, {}, cellLess);
        var distinct: std.ArrayList(Value) = .empty;
        for (values.items) |v| if (distinct.items.len == 0 or proc.cmpValue(distinct.items[distinct.items.len - 1], v) != .eq) try distinct.append(a, v);
        if (ds.columns.items[c].type == .num) for (distinct.items) |v| if (v.num != @trunc(v.num) or @abs(v.num) >= 1e15) return gap(cx, 0, "noninteger numeric CLASS level formatting is not implemented", .{});
        count.* = distinct.items.len;
        var joined: Out = .empty;
        const shown = if (s.maxclprint == 0) distinct.items.len else @min(s.maxclprint, distinct.items.len);
        for (distinct.items[0..shown], 0..) |v, k| {
            if (k > 0) try joined.append(a, ' ');
            try joined.appendSlice(a, try proc.cellText(a, v));
        }
        if (shown < distinct.items.len) try joined.appendSlice(a, " ...");
        text.* = joined.items;
    }
    // ponytail: the Values column wraps at 45 characters, the width observed
    // in the reference listing; SAS's own width rule is not documented.
    const vw: usize = 45;
    try title(a, out, "Class Level Information", names_w + 4 + 6 + 4 + vw, true);
    try left(a, out, "Class", names_w + 4);
    try out.appendSlice(a, "Levels    Values\n\n");
    for (s.classes, texts, counts) |c, text, count| {
        try left(a, out, ds.columns.items[c].name, names_w + 4);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{count}), 6);
        try out.appendSlice(a, "    ");
        var rest = text;
        var first = true;
        while (first or rest.len > 0) {
            if (!first) try out.appendNTimes(a, ' ', names_w + 4 + 6 + 4);
            first = false;
            var cut = rest.len;
            if (rest.len > vw) {
                cut = vw;
                while (cut > 0 and rest[cut] != ' ') cut -= 1;
                if (cut == 0) cut = vw;
                try left(a, out, rest[0 .. cut + 1], vw);
                rest = rest[cut + 1 ..];
            } else {
                try left(a, out, rest, if (text.len > vw) vw else 0);
                rest = "";
            }
            try out.append(a, '\n');
        }
    }
    try out.appendSlice(a, "\n\n");
}

pub fn render(cx: proc.ProcCtx, out: *Out, s: Spec, level_rows: []const []const Value, f: Fit) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe HPLMIXED Procedure\n\n");
    // Shared single-machine tables (STAT-HP-001): one truthful thread.
    try hp.performanceInfo(a, out);
    try hp.dataAccessInfo(a, out, s.data_name);
    try out.appendSlice(a, "\n\n");
    const subject = try shortened(cx, s);
    try infoTable(a, out, "Model Information", &.{
        .{ "Data Set", s.data_name },
        .{ "Dependent Variable", ds.columns.items[s.response].name },
        .{ "Covariance Structure", "Unstructured" },
        .{ "Subject Effect", subject },
        .{ "Estimation Method", "Restricted Maximum Likelihood" },
        .{ "Residual Variance Method", "Profile" },
        .{ "Fixed Effects SE Method", "Model-Based" },
        .{ "Degrees of Freedom Method", "Residual" },
    }, false);
    if (s.classes.len > 0 and !s.noclprint) try classTable(cx, out, s, level_rows);
    const ncov = f.q * (f.q + 1) / 2 + 1;
    const d = struct {
        fn n(al: A, x: usize) ![]const u8 {
            return std.fmt.allocPrint(al, "{d}", .{x});
        }
    };
    try infoTable(a, out, "Dimensions", &.{
        .{ "Covariance Parameters", try d.n(a, ncov) },
        .{ "Columns in X", try d.n(a, f.q) },
        .{ "Columns in Z per Subject", try d.n(a, f.q) },
        .{ "Subjects", try d.n(a, f.subjects) },
        .{ "Max Obs per Subject", try d.n(a, f.k) },
    }, true);
    const nread = ds.rows.items.len;
    try infoTable(a, out, "", &.{
        .{ "Number of Observations Read", try d.n(a, nread) },
        .{ "Number of Observations Used", try d.n(a, f.n) },
        .{ "Number of Observations Not Used", try d.n(a, nread - f.n) },
    }, true);
    try infoTable(a, out, "Optimization Information", &.{
        .{ "Optimization Technique", "Newton-Raphson with Ridging" },
        .{ "Parameters in Optimization", try d.n(a, ncov - 1) },
        .{ "Lower Boundaries", try d.n(a, f.q) },
        .{ "Upper Boundaries", "0" },
        .{ "Starting Values From", "Data" },
    }, false);
    // Iteration history: not reproduced (file comment); reported by run().
    try title(a, out, "Covariance Parameter Estimates", 44, true);
    const sw = @max(7, subject.len);
    try left(a, out, "Cov Parm", 12);
    try left(a, out, "Subject", sw);
    try out.appendSlice(a, "    Estimate\n\n");
    for (0..f.q) |i| for (0..i + 1) |j| {
        try left(a, out, try std.fmt.allocPrint(a, "UN({d},{d})", .{ i + 1, j + 1 }), 12);
        try left(a, out, subject, sw);
        try right(a, out, try sig4(a, f.g[i * f.q + j]), 12);
        try out.append(a, '\n');
    };
    try left(a, out, "Residual", 12 + sw);
    try right(a, out, try sig4(a, f.sigma2), 12);
    try out.appendSlice(a, "\n\n\n");
    const dcov: f64 = @floatFromInt(ncov);
    const nstar: f64 = @floatFromInt(f.n - f.q);
    try infoTable(a, out, "Fit Statistics", &.{
        .{ "-2 Res Log Likelihood", try numText(a, f.minus2, "fit") },
        .{ "AIC (Smaller is Better)", try numText(a, f.minus2 + 2 * dcov, "fit") },
        .{ "AICC (Smaller is Better)", try numText(a, f.minus2 + 2 * dcov * nstar / (nstar - dcov - 1), "fit") },
        .{ "BIC (Smaller is Better)", try numText(a, f.minus2 + dcov * @log(@as(f64, @floatFromInt(f.subjects))), "fit") },
    }, true);
    if (s.solution) {
        const df = f.n - f.q;
        try title(a, out, "Solution for Fixed Effects", 64, true);
        try out.appendSlice(a, "                         Standard\nEffect       Estimate       Error      DF    t Value    Pr > |t|\n\n");
        for (0..f.q) |i| {
            try left(a, out, if (i == 0) "Intercept" else s.fixed[i - 1].name, 13);
            try right(a, out, try sig4(a, f.beta[i]), 8);
            try right(a, out, try sig4(a, f.se[i]), 12);
            try right(a, out, try numText(a, @floatFromInt(df), "best4."), 8);
            const tv = f.beta[i] / f.se[i];
            try right(a, out, try numText(a, tv, "7.2"), 11);
            const p = reg_fit.tProbability(tv, df);
            try right(a, out, if (p < 0.0001) "<.0001" else try numText(a, p, "6.4"), 12);
            try out.append(a, '\n');
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, 0, "graphs under ODS GRAPHICS are not implemented", .{});
    if (!s.random_seen) return gap(cx, 0, "a model without a RANDOM statement is not implemented", .{});
    const rows = try usedRows(a, s, false);
    const level_rows = try usedRows(a, s, true);
    if (rows.len == 0) return cx.diags.fail(error.ParseError, 0, "PROC HPLMIXED: no valid observations", .{});
    var f = fit(a, s, rows) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.BoundaryG => gap(cx, 0, "a nonpositive-definite closed-form G (boundary REML solution) needs the iterative optimizer, which is not implemented", .{}),
        else => gap(cx, 0, "estimation outside the balanced random-coefficients shape (RANDOM columns equal to MODEL columns, identical subject designs) is not implemented ({t})", .{err}),
    };
    f.subjects = try subjectCount(a, s, level_rows);
    if (s.noprint) return;
    try render(cx, out, s, level_rows, f);
    // Loud: the listing above omits the Iteration History and its convergence
    // status line, which depend on SAS's starting values and optimizer path.
    diag.markGap();
    try cx.diags.recoverableErr(0, "PROC HPLMIXED: the Iteration History table and convergence status are not implemented (estimates above are the exact closed-form REML solution)", .{});
}

test {
    _ = @import("hplmixed_tests.zig");
}
