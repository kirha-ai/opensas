//! PROC HPNLMOD (SAS/STAT 15.4 ch.63, STAT-HPNLMOD-001): PROC statement
//! options, PARAMETERS, MODEL dependent ~ RESIDUAL(expression), BY, the
//! missing-value and observation rules, and the default listing of a
//! nonlinear least-squares fit. Everything else the chapter defines is a loud
//! D-009 gap owned by the later HPNLMOD tickets; nothing is printed for a step
//! that hits one.
//!
//! The model expression is parsed by the shared expression parser, evaluated
//! by the shared DATA step evaluator and differentiated symbolically by
//! `nlin.deriv` (read-only reuse of PROC NLIN).
//!
//! Optimization: the objective is f = SSE/n. TECHNIQUE=LEVMAR is Moré's
//! trust-region Levenberg-Marquardt; when the trust region does not bind its
//! step is the full Gauss-Newton step (lambda = 0), which reproduces the SAS
//! iteration history to every printed digit (reference: the enzyme data,
//! default options, and two BY groups of it). ponytail: only that undamped
//! path is implemented. A step that would need damping (the Gauss-Newton
//! step does not reduce f, its actual/predicted reduction ratio is below
//! 0.75, or it is longer than the conservative trust radius) is a loud gap
//! owned by STAT-HPNLMOD-005, never an approximate history.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const ast = @import("../ast.zig");
const pe = @import("../parser_expr.zig");
const eval = @import("../eval.zig");
const functions = @import("../functions.zig");
const fmt = @import("../format.zig");
const Pdv = @import("../pdv.zig").Pdv;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const reg_fit = @import("reg_fit.zig");
const nlin = @import("nlin.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const E = *const ast.Expr;
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Param = struct { name: []const u8, start: f64 };

pub const Spec = struct {
    input: proc.ProcInput,
    /// DATA= member name in upper case, and LIBREF.MEMBER.
    member: []const u8 = "",
    data_name: []const u8 = "",
    alpha: f64 = 0.05,
    gconv: f64 = 1e-8,
    noprint: bool = false,
    noitprint: bool = false,
    params: []const Param = &.{},
    dependent: usize = 0,
    model: E = undefined,
    /// Numeric data set columns the model expression references.
    model_cols: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

pub const Iter = struct { evals: usize, f: f64, change: f64, maxgrad: f64 };

pub const Fit = struct {
    read: usize,
    used: usize,
    p: usize,
    f0: f64,
    history: []const Iter,
    theta: []const f64,
    sse: f64,
    total_ss: f64, // uncorrected
    mse: f64,
    se: []const f64,
    lower: []const f64,
    upper: []const f64,
};

// Valid PROC statement options (pp.4863-4868) owned by later tickets.
const valued_gap_options = [_][]const u8{ "absconv", "abstol", "absfconv", "absftol", "absgconv", "absgtol", "df", "fconv", "ftol", "maxiter", "maxit", "maxfunc", "maxfu", "maxtime", "miniter", "minit", "out", "singular", "technique", "tech", "fmtlibxml", "xmlformat" };
const flag_gap_options = [_][]const u8{ "corr", "cov", "ecorr", "ecov" };
// Valid statements owned by later tickets.
const Later = struct { word: []const u8, owner: []const u8 };
const later_statements = [_]Later{
    .{ .word = "bounds", .owner = "STAT-HPNLMOD-006" },
    .{ .word = "restrict", .owner = "STAT-HPNLMOD-006" },
    .{ .word = "estimate", .owner = "STAT-HPNLMOD-007" },
    .{ .word = "predict", .owner = "STAT-HPNLMOD-004" },
    .{ .word = "performance", .owner = "STAT-HPNLMOD-010" },
};
const programming_words = [_][]const u8{ "if", "else", "do", "end", "array", "call", "goto", "link", "return", "select", "when", "otherwise", "put", "stop", "file", "length", "label", "attrib", "drop", "keep", "retain", "abort" };
const distributions = [_][]const u8{ "normal", "binary", "binomial", "gamma", "negbin", "poisson", "general" };

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC HPNLMOD: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, l: usize, comptime f: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, l, "PROC HPNLMOD: " ++ f, args);
}
/// An optionally signed numeric literal at `i.*`; advances past it.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, what: []const u8) diag.Error!f64 {
    var sign: f64 = 1;
    var j = i.*;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    } else if (at(t, j, .plus)) j += 1;
    const v = if (at(t, j, .number)) std.fmt.parseFloat(f64, t[j].text) catch null else null;
    if (v == null) return cx.diags.fail(error.ParseError, line(t, j), "PROC HPNLMOD: {s} requires a numeric value", .{what});
    i.* = j + 1;
    return sign * v.?;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = try std.ascii.allocLowerString(a, t[i].text);
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx, t[i].line, "repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            i += 2;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            if (at(t, i + 1, .dot) and at(t, i + 2, .name)) {
                qualified = i;
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[i].text, t[i + 2].text });
                i += 2;
            }
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if ((eq(option, "alpha") or eq(option, "gconv") or eq(option, "gtol")) and valued) {
            i += 2;
            const v = try number(cx, t, &i, t[i - 2].text);
            if (eq(option, "alpha")) {
                // SAS: "The parameter value 1.5 is not within the required range of 0 and 1."
                if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, line(t, i - 1), "PROC HPNLMOD: The parameter value {d} is not within the required range of 0 and 1.", .{v});
                s.alpha = v;
            } else {
                if (!(v >= 0)) return cx.diags.fail(error.ParseError, line(t, i - 1), "PROC HPNLMOD: GCONV= must be nonnegative", .{});
                if (at(t, i, .number)) return gap(cx, t[i].line, "the GCONV= successive-iteration count n is not implemented (STAT-HPNLMOD-005)", .{});
                s.gconv = v;
            }
        } else if (valued and oneOf(option, &valued_gap_options)) {
            return gap(cx, t[i].line, "PROC statement option {s}= is not implemented (STAT-HPNLMOD-002/004/005/008)", .{t[i].text});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "noitprint")) {
            s.noitprint = true;
            i += 1;
        } else if (oneOf(option, &flag_gap_options)) {
            return gap(cx, t[i].line, "PROC statement option {s} is not implemented (STAT-HPNLMOD-008)", .{t[i].text});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC HPNLMOD: input data set not found", .{});
    const upper = try std.ascii.allocUpperString(a, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') != null) upper else try std.fmt.allocPrint(a, "WORK.{s}", .{upper});
    s.member = s.data_name[std.mem.lastIndexOfScalar(u8, s.data_name, '.').? + 1 ..];
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var params: std.ArrayList(Param) = .empty;
    var model_tokens: ?[]const lex.Token = null;
    var model_at: usize = 0;
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
        if (at(t, i + 1, .eq) or at(t, i + 1, .lbrace) or (at(t, i + 1, .lparen) and !oneOf(word, &.{ "model", "parms", "parameters", "parm" }))) {
            // `name = expression;` and array-element assignments.
            return gap(cx, t[i].line, "programming statements are not implemented (STAT-HPNLMOD-009)", .{});
        } else if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.4869: when more than one BY statement appears only the last is used.
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "parms") or eq(word, "parameters") or eq(word, "parm")) {
            var j = i + 1;
            if (j == end) return gap(cx, t[i].line, "a PARAMETERS statement without parameter specifications is not implemented (STAT-HPNLMOD-006)", .{});
            while (j < end) {
                if (at(t, j, .comma)) {
                    j += 1;
                    continue;
                }
                if (at(t, j, .slash)) return gap(cx, t[j].line, "PARAMETERS statement options are not implemented (STAT-HPNLMOD-006)", .{});
                if (!at(t, j, .name)) return invalid(cx, t, j);
                if (!at(t, j + 1, .eq)) return gap(cx, t[j].line, "a parameter without a starting value (or a parameter list) is not implemented (STAT-HPNLMOD-006)", .{});
                const pname = t[j].text;
                if (ds.indexOf(pname) != null) return gap(cx, t[j].line, "a parameter with the name of an input variable ({s}) is not verified", .{pname});
                j += 2;
                const start = try number(cx, t, &j, "a PARAMETERS starting value");
                if (j < end and !at(t, j, .comma) and !at(t, j, .name) and !at(t, j, .slash)) return gap(cx, t[j].line, "PARAMETERS value lists are not implemented (STAT-HPNLMOD-006)", .{});
                if (kw(t, j, "to")) return gap(cx, t[j].line, "PARAMETERS value lists are not implemented (STAT-HPNLMOD-006)", .{});
                // SAS reference: a repeated parameter keeps its last starting value.
                var found = false;
                for (params.items) |*q| if (eq(q.name, pname)) {
                    q.start = start;
                    found = true;
                };
                if (!found) try params.append(a, .{ .name = pname, .start = start });
            }
        } else if (eq(word, "model")) {
            if (model_tokens != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPNLMOD: Only one MODEL statement can be specified.", .{});
            if (!at(t, i + 1, .name) or !at(t, i + 2, .caret)) return invalid(cx, t, @min(i + 1, end));
            const dist = i + 3;
            if (kw(t, dist, "residual") and at(t, dist + 1, .lparen) and at(t, end - 1, .rparen) and end - 1 > dist + 2) {
                model_tokens = t[dist + 2 .. end - 1];
            } else if (at(t, dist, .name) and oneOf(t[dist].text, &distributions)) {
                return gap(cx, t[i].line, "MODEL distribution {s} is not implemented (STAT-HPNLMOD-003)", .{t[dist].text});
            } else return invalid(cx, t, dist);
            // SAS: "The response variable in the MODEL statement does not appear
            // in the DATA= data set and is not assigned a value in the program."
            s.dependent = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC HPNLMOD: The response variable in the MODEL statement does not appear in the DATA= data set and is not assigned a value in the program.", .{});
            if (ds.columns.items[s.dependent].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPNLMOD: response variable {s} must be numeric", .{t[i + 1].text});
            model_at = i;
        } else if (laterOwner(word)) |owner| {
            return gap(cx, t[i].line, "the {s} statement is not implemented ({s})", .{ word, owner });
        } else if (oneOf(word, &programming_words)) {
            return gap(cx, t[i].line, "programming statements are not implemented (STAT-HPNLMOD-009)", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const body = model_tokens orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC HPNLMOD: A MODEL statement is required in the HPNLMOD procedure.", .{});
    if (params.items.len == 0) return gap(cx, line(t, model_at), "parameters without a PARAMETERS statement (default starting value 1) are not implemented (STAT-HPNLMOD-006)", .{});
    s.params = params.items;

    const etoks = try a.alloc(lex.Token, body.len + 1);
    @memcpy(etoks[0..body.len], body);
    etoks[body.len] = .{ .tag = .eof };
    var ep = pe.Parser.init(a, etoks, cx.diags);
    s.model = try ep.parseExpr();
    if (ep.pos != body.len) return invalid(cx, body, ep.pos);
    var cols: std.ArrayList(usize) = .empty;
    try check(cx, s, s.model, &cols, line(t, model_at));
    s.model_cols = cols.items;

    const pb = try bys.resolve(a, ds, cx.diags);
    const bcols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| bcols[k] = ds.indexOf(n).?;
    s.by_cols = bcols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

fn laterOwner(word: []const u8) ?[]const u8 {
    for (later_statements) |l| if (eq(word, l.word)) return l.owner;
    return null;
}

/// The node kinds `nlin.deriv` can differentiate; anything else is a gap.
fn check(cx: proc.ProcCtx, s: Spec, e: E, cols: *std.ArrayList(usize), l: usize) diag.Error!void {
    switch (e.*) {
        .num => {},
        .variable => |v| {
            for (s.params) |q| if (eq(q.name, v)) return;
            const ci = s.input.ds.indexOf(v) orelse return gap(cx, l, "{s} in the MODEL expression is neither a declared parameter nor an input variable; undeclared parameters are not implemented (STAT-HPNLMOD-006)", .{v});
            if (s.input.ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC HPNLMOD: character variable {s} cannot be used in the MODEL expression", .{v});
            if (std.mem.indexOfScalar(usize, cols.items, ci) == null) try cols.append(cx.arena, ci);
        },
        .unary => |u| {
            if (u.op != .neg) return gap(cx, l, "logical operators in the MODEL expression are not implemented (STAT-HPNLMOD-009)", .{});
            try check(cx, s, u.operand, cols, l);
        },
        .binary => |b| {
            switch (b.op) {
                .add, .sub, .mul, .div, .pow => {},
                else => return gap(cx, l, "only + - * / ** operators are implemented in the MODEL expression (STAT-HPNLMOD-009)", .{}),
            }
            try check(cx, s, b.lhs, cols, l);
            try check(cx, s, b.rhs, cols, l);
        },
        .call => |c| {
            if (c.args.len != 1 or !(eq(c.name, "exp") or eq(c.name, "log") or eq(c.name, "sqrt")))
                return gap(cx, l, "function {s} in the MODEL expression is not implemented; only EXP, LOG and SQRT are (STAT-HPNLMOD-009)", .{c.name});
            try check(cx, s, &c.args[0], cols, l);
        },
        else => return gap(cx, l, "this MODEL expression form is not implemented (STAT-HPNLMOD-009)", .{}),
    }
}

// ── Fit ─────────────────────────────────────────────────────────────────────

const Model = struct {
    ev: eval.Evaluator,
    pdv: *Pdv,
    ds: *const Dataset,
    rows: []const []const Value,
    params: []const Param,

    /// out[m * exprs.len + k] = exprs[k] at observation m (null expression = 0).
    fn at(self: *Model, theta: []const f64, exprs: []const ?E, out: []f64) diag.Error!void {
        const cols = self.ds.columns.items;
        for (self.rows, 0..) |row, m| {
            for (cols, row) |col, v| if (col.type == .num) try self.pdv.set(col.name, v);
            for (self.params, theta) |q, v| try self.pdv.set(q.name, .{ .num = v });
            for (exprs, 0..) |e, k| out[m * exprs.len + k] = if (e) |x| switch (try self.ev.eval(x)) {
                .num => |v| v,
                else => nan,
            } else 0;
        }
    }
};

/// Gaussian elimination with partial pivoting; null when singular.
fn solve(a: A, matrix: []const f64, rhs: []const f64, p: usize) !?[]f64 {
    const m = try a.dupe(f64, matrix);
    const x = try a.dupe(f64, rhs);
    var scale: f64 = 0;
    for (m) |v| scale = @max(scale, @abs(v));
    for (0..p) |c| {
        var best = c;
        for (c + 1..p) |r| if (@abs(m[r * p + c]) > @abs(m[best * p + c])) {
            best = r;
        };
        if (!(@abs(m[best * p + c]) > 1e-12 * scale)) return null;
        if (best != c) {
            for (0..p) |k| std.mem.swap(f64, &m[c * p + k], &m[best * p + k]);
            std.mem.swap(f64, &x[c], &x[best]);
        }
        for (c + 1..p) |r| {
            const f = m[r * p + c] / m[c * p + c];
            for (c..p) |k| m[r * p + k] -= f * m[c * p + k];
            x[r] -= f * x[c];
        }
    }
    var c = p;
    while (c > 0) {
        c -= 1;
        for (c + 1..p) |k| x[c] -= m[c * p + k] * x[k];
        x[c] /= m[c * p + c];
    }
    return x;
}

/// Jacobian cross products at theta: J'J, J'r, SSE, column norms of J.
const Local = struct { xtx: []f64, g: []f64, sse: f64, norms: []f64 };

fn local(a: A, model: *Model, theta: []const f64, exprs: []const ?E, vals: []f64, y: []const f64) diag.Error!Local {
    const p = theta.len;
    try model.at(theta, exprs, vals);
    const l: Local = .{ .xtx = try a.alloc(f64, p * p), .g = try a.alloc(f64, p), .sse = 0, .norms = try a.alloc(f64, p) };
    @memset(l.xtx, 0);
    @memset(l.g, 0);
    var sse: f64 = 0;
    for (y, 0..) |yv, m| {
        const v = vals[m * (p + 1) ..][0 .. p + 1];
        const res = yv - v[0];
        sse += res * res;
        for (0..p) |i| {
            l.g[i] += v[1 + i] * res;
            for (0..p) |j| l.xtx[i * p + j] += v[1 + i] * v[1 + j];
        }
    }
    for (0..p) |i| l.norms[i] = @sqrt(l.xtx[i * p + i]);
    var out = l;
    out.sse = sse;
    return out;
}

/// Fit one BY group. Every condition the reference listings do not verify is
/// a loud gap.
pub fn fit(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Fit {
    const a = cx.arena;
    const p = s.params.len;
    // Missing values: an observation with a missing response or model
    // variable is not used (SAS reference: BY group with 9 read, 7 used).
    var kept: std.ArrayList([]const Value) = .empty;
    for (rows) |row| {
        var ok = !std.math.isNan(row[s.dependent].num);
        for (s.model_cols) |ci| ok = ok and !std.math.isNan(row[ci].num);
        if (ok) try kept.append(a, row);
    }
    const n = kept.items.len;
    if (n <= p + 1) return gap(cx, 0, "a fit with {d} usable observations and {d} parameters is not verified (STAT-HPNLMOD-002)", .{ n, p });
    const nf: f64 = @floatFromInt(n);
    const y = try a.alloc(f64, n);
    var total: f64 = 0;
    for (kept.items, y) |row, *v| {
        v.* = row[s.dependent].num;
        total += v.* * v.*;
    }

    const pdv = try a.create(Pdv);
    pdv.* = Pdv.init(a);
    var model: Model = .{ .ev = .{ .arena = a, .pdv = pdv, .diags = cx.diags, .call_fn = &functions.dispatch }, .pdv = pdv, .ds = s.input.ds, .rows = kept.items, .params = s.params };
    const exprs = try a.alloc(?E, p + 1);
    exprs[0] = s.model;
    for (s.params, 1..) |q, k| exprs[k] = nlin.deriv(a, s.model, q.name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return gap(cx, 0, "the MODEL expression cannot be differentiated (STAT-HPNLMOD-005)", .{}),
    };
    const vals = try a.alloc(f64, n * (p + 1));
    const theta = try a.alloc(f64, p);
    for (s.params, theta) |q, *v| v.* = q.start;

    var history: std.ArrayList(Iter) = .empty;
    var cur = try local(a, &model, theta, exprs, vals, y);
    if (!std.math.isFinite(cur.sse)) return gap(cx, 0, "a model that cannot be evaluated at the starting values is not implemented (STAT-HPNLMOD-005)", .{});
    const f0 = cur.sse / nf;
    // Moré's scaling: running maximum of the Jacobian column norms.
    const diagd = try a.dupe(f64, cur.norms);
    var radius: f64 = 0;
    for (diagd, theta) |d, v| radius += d * v * d * v;
    radius = 100 * @sqrt(radius);
    if (!(radius > 0)) radius = 100;
    var prev_step: f64 = std.math.inf(f64);
    var iterations: usize = 0;
    var evals: usize = 5; // SAS reference: 5 evaluations at iteration 0 for 1-3 parameters
    var prev_f: f64 = nan;
    while (true) {
        for (cur.xtx) |v| if (!std.math.isFinite(v)) return gap(cx, 0, "derivatives that cannot be evaluated are not implemented (STAT-HPNLMOD-005)", .{});
        const f = cur.sse / nf;
        var maxgrad: f64 = 0;
        for (cur.g) |v| maxgrad = @max(maxgrad, @abs(2 * v / nf));
        try history.append(a, .{ .evals = evals, .f = f, .change = if (iterations == 0) nan else @abs(prev_f - f), .maxgrad = maxgrad });
        if (!(cur.sse > 0)) return gap(cx, 0, "an exact fit (zero residual sum of squares) is not verified (STAT-HPNLMOD-005)", .{});
        // ABSGCONV: the reference reports ABSGCONV=1E-7 when it ends a fit.
        if (maxgrad <= 1e-7) return gap(cx, 0, "termination by the ABSGCONV criterion is not implemented (STAT-HPNLMOD-005)", .{});
        if (iterations > 0 and @abs(prev_f - f) <= 1e-15 * @abs(prev_f)) return gap(cx, 0, "termination by the FCONV criterion is not implemented (STAT-HPNLMOD-005)", .{});
        const step = (try solve(a, cur.xtx, cur.g, p)) orelse return gap(cx, 0, "a singular Jacobian cross-product matrix is not implemented (STAT-HPNLMOD-005)", .{});
        var quad: f64 = 0;
        for (cur.g, step) |u, v| quad += u * v;
        // GCONV: g'H^-1 g / |f| with f = SSE/n, g = -2J'r/n, H = 2J'J/n.
        const gc = 2 * quad / cur.sse;
        if (iterations == 0 and gc <= s.gconv) return gap(cx, 0, "convergence at the starting values is not verified (STAT-HPNLMOD-005)", .{});
        if (iterations >= 50) return gap(cx, 0, "the fit did not converge in 50 iterations; nonconvergence reporting is not implemented (STAT-HPNLMOD-005)", .{});
        // The undamped Moré step must lie well inside the trust region.
        var dnorm: f64 = 0;
        for (diagd, cur.norms, step) |*d, cn, v| {
            d.* = @max(d.*, cn);
            dnorm += d.* * v * d.* * v;
        }
        dnorm = @sqrt(dnorm);
        if (!(dnorm <= radius and dnorm <= 2 * prev_step)) return gap(cx, 0, "a Levenberg-Marquardt step restricted by the trust region is not implemented (STAT-HPNLMOD-005)", .{});
        const trial = try a.alloc(f64, p);
        for (trial, theta, step) |*tv, b, d| tv.* = b + d;
        const next = try local(a, &model, trial, exprs, vals, y);
        const predicted = quad; // ||r||^2 - ||r - J s||^2 for the Gauss-Newton step
        if (!(next.sse < cur.sse) or !((cur.sse - next.sse) >= 0.75 * predicted)) return gap(cx, 0, "a damped Levenberg-Marquardt step is not implemented (STAT-HPNLMOD-005)", .{});
        prev_step = dnorm;
        prev_f = f;
        @memcpy(theta, trial);
        cur = next;
        iterations += 1;
        evals = 2;
        // The criterion is tested on the predicted reduction of the step just
        // taken (SAS reference: GCONV=1E-5 stops one iteration after
        // gc <= 1E-5 first holds).
        if (gc <= s.gconv) break;
    }
    // The final row.
    {
        const f = cur.sse / nf;
        var maxgrad: f64 = 0;
        for (cur.g) |v| maxgrad = @max(maxgrad, @abs(2 * v / nf));
        try history.append(a, .{ .evals = evals, .f = f, .change = @abs(prev_f - f), .maxgrad = maxgrad });
        if (maxgrad <= 1e-7) return gap(cx, 0, "termination by the ABSGCONV criterion is not implemented (STAT-HPNLMOD-005)", .{});
    }

    // A constant in the column space of the Jacobian changes the ANOVA to a
    // corrected total; that listing is not verified.
    const ones = try a.alloc(f64, p);
    @memset(ones, 0);
    for (0..n) |m| for (0..p) |i| {
        ones[i] += vals[m * (p + 1) + 1 + i];
    };
    const c1 = (try solve(a, cur.xtx, ones, p)) orelse return gap(cx, 0, "a singular Jacobian cross-product matrix is not implemented (STAT-HPNLMOD-005)", .{});
    var fitted: f64 = 0;
    for (ones, c1) |u, v| fitted += u * v;
    if (nf - fitted < 1e-8 * nf) return gap(cx, 0, "the corrected-total listing of a model with an intercept is not verified (STAT-HPNLMOD-008)", .{});

    const mse = cur.sse / (nf - @as(f64, @floatFromInt(p)));
    const se = try a.alloc(f64, p);
    const lower = try a.alloc(f64, p);
    const upper = try a.alloc(f64, p);
    const unit = try a.alloc(f64, p);
    // SAS reference: ALPHA=0.1 and ALPHA=0.025 print the same 95% limits as
    // the default, so the Parameter Estimates table always uses 0.05.
    const tc = reg_fit.tCritical(0.05, n - p);
    for (0..p) |j| {
        @memset(unit, 0);
        unit[j] = 1;
        const col = (try solve(a, cur.xtx, unit, p)).?;
        se[j] = @sqrt(mse * col[j]);
        lower[j] = theta[j] - tc * se[j];
        upper[j] = theta[j] + tc * se[j];
    }
    return .{ .read = rows.len, .used = n, .p = p, .f0 = f0, .history = history.items, .theta = theta, .sse = cur.sse, .total_ss = total, .mse = mse, .se = se, .lower = lower, .upper = upper };
}

// ── Listing ─────────────────────────────────────────────────────────────────

fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn title(a: A, out: *Out, text: []const u8, width: usize, spaced: bool) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, if (spaced) "\n \n" else "\n\n");
}
fn bestText(a: A, x: f64, w: usize) ![]const u8 {
    const spec = try std.fmt.allocPrint(a, "BEST{d}.", .{w});
    return std.mem.trim(u8, try fmt.apply(a, .{ .num = x }, spec), " ");
}
/// Max Gradient column: BEST8, but fixed notation down to 1E-5 with
/// trailing zeros dropped (reference: 0.000057, 0.00002, 9.72E-6).
pub fn gradText(a: A, x: f64) ![]const u8 {
    const text = try bestText(a, x, 8);
    if (@abs(x) >= 1e-5 and @abs(x) < 1 and std.mem.indexOfScalar(u8, text, 'E') != null) {
        const fixed = try std.fmt.allocPrint(a, "{d:.6}", .{x});
        return std.mem.trimEnd(u8, fixed, "0");
    }
    return text;
}
/// Change column: 8 decimals, fewer when the value needs more than 12
/// characters (reference: 12.49634869, 9458.2818377, 0.00000000).
pub fn changeText(a: A, x: f64) ![]const u8 {
    var decimals: usize = 8;
    while (true) : (decimals -= 1) {
        const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
        if (text.len <= 12 or decimals == 0) return text;
    }
}

/// Listing boundary: shapes outside the verified layout are raised before
/// any text is written.
fn checkLayout(cx: proc.ProcCtx, s: Spec, f: Fit) diag.Error!void {
    // SAS adds a Gradient column to Parameter Estimates when the final
    // gradient is large (present at max 0.005261, absent at max 0.000057);
    // its threshold is not documented.
    if (f.history[f.history.len - 1].maxgrad > 6e-5) return gap(cx, 0, "the Parameter Estimates Gradient column (final max gradient above 6E-5) is not implemented (STAT-HPNLMOD-008)", .{});
    if (f.p < 2 or f.p > 6) return gap(cx, 0, "the Initial Parameter Values layout for {d} parameters is not verified (STAT-HPNLMOD-008)", .{f.p});
    for (s.params) |q| if (q.name.len > 8) return gap(cx, 0, "parameter names longer than 8 characters are not verified in the listing (STAT-HPNLMOD-008)", .{});
    if (s.member.len > 20 or s.input.ds.columns.items[s.dependent].name.len > 20) return gap(cx, 0, "Specifications values longer than 20 characters are not verified (STAT-HPNLMOD-008)", .{});
    for ([_]f64{ f.sse, f.mse }) |v| if (!(v >= 0.01 and v < 100)) return gap(cx, 0, "Fit Statistics values outside [0.01, 100) are not verified (STAT-HPNLMOD-008)", .{});
    for (f.theta, f.se) |b, se| if (!(@abs(b / se) < 10000)) return gap(cx, 0, "t values of 10000 or more are not verified (STAT-HPNLMOD-008)", .{});
}

fn header(a: A, out: *Out, s: Spec) !void {
    try out.appendSlice(a, "\nThe HPNLMOD Procedure\n\n");
    // opensas computes on one thread, so it reports 1 where the SAS reference
    // machine reports its own thread count (STAT-HPNLMOD-010).
    try out.appendSlice(a, "      Performance Information\n\nExecution Mode       Single-Machine\nNumber of Threads    1             \n\n\n");
    const dw = s.data_name.len + 4;
    try title(a, out, "Data Access Information", dw + 28, true);
    try padRight(a, out, "Data", dw);
    try out.appendSlice(a, "Engine    Role     Path\n\n");
    try padRight(a, out, s.data_name, dw);
    try out.appendSlice(a, "V9        Input    On Client\n\n\n");
    try title(a, out, "Specifications", 64, false);
    try padRight(a, out, "Data Source", 44);
    try padRight(a, out, s.member, 20);
    try out.appendSlice(a, "\n");
    try padRight(a, out, "Dependent Variable", 44);
    try padRight(a, out, s.input.ds.columns.items[s.dependent].name, 20);
    try out.appendSlice(a, "\nDistribution                                None (Nonlinear     \n" ++
        "                                            Least Squares)      \n" ++
        "Optimization Technique                      Levenberg-Marquardt \n");
}

fn render(a: A, out: *Out, s: Spec, f: Fit) !void {
    const p = f.p;
    try out.print(a, "Number of Observations Read{d:>16}\nNumber of Observations Used{d:>16}\n\n\n", .{ f.read, f.used });
    try title(a, out, "Dimensions", 40, false);
    try out.print(a, "Parameters{d:>30}\n\n\n", .{p});

    const iw = 8 + 12 * (p - 1) + 14;
    try title(a, out, "Initial Parameter Values", iw, true);
    for (s.params, 0..) |q, k| try padLeft(a, out, q.name, if (k == 0) 8 else 12);
    try out.appendSlice(a, "     Objective\n\n");
    for (s.params, 0..) |q, k| try padLeft(a, out, try bestText(a, q.start, 8), if (k == 0) 8 else 12);
    try padLeft(a, out, try bestText(a, f.f0, 10), 14);
    try out.appendSlice(a, if (s.noitprint) "\n" else "\n\n\n");

    if (!s.noitprint) try iterationTable(a, out, f);
    const message = try std.fmt.allocPrint(a, "Convergence criterion (GCONV={s}) satisfied.", .{try bestText(a, s.gconv, 8)});
    try out.append(a, '\n');
    try out.appendNTimes(a, ' ', (64 - @min(64, message.len)) / 2);
    try padRight(a, out, message, 64 - (64 - @min(64, message.len)) / 2);
    try out.appendSlice(a, "\n\n\n");
    try fitTables(a, out, s, f);
}

fn iterationTable(a: A, out: *Out, f: Fit) !void {
    try out.appendSlice(a, "                          Iteration History\n \n" ++
        "                               Objective                         Max\n" ++
        "Iteration    Evaluations        Function          Change    Gradient\n\n");
    for (f.history, 0..) |it, k| {
        try out.print(a, "{d:>9}{d:>15}", .{ k, it.evals });
        try padLeft(a, out, try bestText(a, it.f, 12), 16);
        try padLeft(a, out, if (k == 0) "" else try changeText(a, it.change), 16);
        try padLeft(a, out, try gradText(a, it.maxgrad), 12);
        try out.append(a, '\n');
    }
}

fn fitTables(a: A, out: *Out, s: Spec, f: Fit) !void {
    const p = f.p;

    try title(a, out, "Fit Statistics", 42, false);
    try padRight(a, out, "SS(Error)", 32);
    try padLeft(a, out, try nlin.cell(a, f.sse), 10);
    try out.append(a, '\n');
    try padRight(a, out, "Error Variance", 32);
    try padLeft(a, out, try nlin.cell(a, f.mse), 10);
    try out.appendSlice(a, "\n\n\n");

    try out.appendSlice(a, "                          Analysis of Variance\n \n" ++
        "                                  Sum of        Mean               Approx\n" ++
        "Source                    DF     Squares      Square    F Value    Pr > F\n\n");
    const model_ss = f.total_ss - f.sse;
    const ms = model_ss / @as(f64, @floatFromInt(p));
    const fvalue = ms / f.mse;
    const prob = reg_fit.fProbability(fvalue, p, f.used - p);
    try out.print(a, "{s:<18}{d:>10}", .{ "Model", p });
    try padLeft(a, out, try nlin.cell(a, model_ss), 12);
    try padLeft(a, out, try nlin.cell(a, ms), 12);
    var ftext = try std.fmt.allocPrint(a, "{d:.2}", .{fvalue});
    if (ftext.len > 7) ftext = try std.fmt.allocPrint(a, "{d:.1}", .{fvalue});
    if (ftext.len > 7) ftext = try std.fmt.allocPrint(a, "{d:.0}", .{fvalue});
    try padLeft(a, out, ftext, 11);
    try padLeft(a, out, if (prob < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{prob}), 10);
    try out.print(a, "\n{s:<18}{d:>10}", .{ "Error", f.used - p });
    try padLeft(a, out, try nlin.cell(a, f.sse), 12);
    try padLeft(a, out, try nlin.cell(a, f.mse), 12);
    try out.appendNTimes(a, ' ', 21);
    try out.print(a, "\n{s:<18}{d:>10}", .{ "Uncorrected Total", f.used });
    try padLeft(a, out, try nlin.cell(a, f.total_ss), 12);
    try out.appendNTimes(a, ' ', 33);
    try out.appendSlice(a, "\n\nAn intercept was not specified for this model.\n\n\n");

    try out.appendSlice(a, "                                  Parameter Estimates\n \n" ++
        "                         Standard                         Approx\n" ++
        "Parameter    Estimate       Error      DF    t Value    Pr > |t|    Approximate 95% Confidence Limits\n\n");
    for (s.params, 0..) |q, i| {
        try padRight(a, out, q.name, 9);
        try padLeft(a, out, try nlin.cell(a, f.theta[i]), 12);
        try padLeft(a, out, try nlin.cell(a, f.se[i]), 12);
        // The reference prints DF 1 for every parameter; p-values and limits
        // use the error degrees of freedom n - p.
        try padLeft(a, out, "1", 8);
        const tv = f.theta[i] / f.se[i];
        try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{tv}), 11);
        const pt = reg_fit.tProbability(tv, f.used - p);
        try padLeft(a, out, if (pt < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{pt}), 12);
        try padLeft(a, out, try nlin.cell(a, f.lower[i]), 12);
        try padLeft(a, out, try nlin.cell(a, f.upper[i]), 12);
        try out.append(a, '\n');
    }
}

/// The BY line as the reference prints it under NOCENTER: flush left.
/// ponytail: the CENTER system option is not modelled; every verified
/// HPNLMOD listing is NOCENTER, so the line is never centered.
fn byLine(a: A, out: *Out, ds: *const Dataset, row: []const Value, cols: []const usize) !void {
    try out.append(a, '\n');
    for (cols, 0..) |ci, j| {
        const info = ds.columns.items[ci];
        const text = if (info.format) |f| try fmt.apply(a, row[ci], f) else try proc.cellText(a, row[ci]);
        if (j > 0) try out.append(a, ' ');
        try out.print(a, "{s}={s}", .{ info.name, std.mem.trim(u8, text, " ") });
    }
    try out.append(a, '\n');
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return gap(cx, line(t, 0), "an input data set without observations is not verified (STAT-HPNLMOD-002)", .{});
    // Fit every group before printing anything: a gap prints nothing.
    const fits = try a.alloc(Fit, groups.len);
    for (groups, fits) |group, *f| {
        f.* = try fit(cx, s, group.rows);
        try checkLayout(cx, s, f.*);
    }
    var body: Out = .empty;
    try header(a, &body, s);
    try cx.diags.note(0, "The HPNLMOD procedure is executing in single-machine mode.", .{});
    for (groups, fits) |group, f| {
        if (s.by_cols.len > 0) {
            try byLine(a, &body, ds, group.rows[0], s.by_cols);
            try body.appendSlice(a, "\nThe HPNLMOD Procedure\n\n");
        } else try body.appendSlice(a, "\n\n");
        try render(a, &body, s, f);
        try cx.diags.note(0, "Convergence criterion (GCONV={s}) satisfied.", .{try bestText(a, s.gconv, 8)});
        try cx.diags.note(0, "An intercept was not specified for this model.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
    }
    // NOPRINT suppresses the listing; the log notes stay.
    if (!s.noprint) try out.appendSlice(a, body.items);
}

test {
    _ = @import("hpnlmod_tests.zig");
}
