//! PROC NLIN (SAS/STAT 15.4 ch.88): PROC statement options, PARAMETERS/PARMS,
//! MODEL, BY and ID roles, missing-value selection and the default listing of
//! a METHOD=MARQUARDT least-squares fit (STAT-NLIN-001). Everything else the
//! chapter defines is a loud D-009 gap; nothing is printed for a step that
//! hits one.
//!
//! The model expression is parsed by the shared expression parser and
//! evaluated by the shared DATA step evaluator. Derivatives are symbolic:
//! `deriv` builds derivative expressions from the model AST and those are
//! evaluated by the same evaluator (first order for the Jacobian, second
//! order for Hougaard's skewness).
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
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

pub const Method = enum { gauss, marquardt, newton, gradient };
pub const Param = struct { name: []const u8, values: []const f64 };

pub const Spec = struct {
    input: proc.ProcInput,
    // PROC statement defaults: METHOD=GAUSS, CONVERGE=1E-5, MAXITER=100,
    // ALPHA=0.05.
    method: Method = .gauss,
    hougaard: bool = false,
    converge: f64 = 1e-5,
    maxiter: usize = 100,
    alpha: f64 = 0.05,
    /// Valid PROC options this file does not implement (first one is reported).
    gap_options: []const []const u8 = &.{},
    /// Valid statements owned by later NLIN tickets.
    later: []const []const u8 = &.{},
    params: []const Param = &.{},
    dependent: usize = 0,
    model: *const ast.Expr = undefined,
    /// Numeric data set columns the model expression references.
    model_cols: []const usize = &.{},
    id_cols: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

pub const Fit = struct {
    read: usize,
    used: usize,
    missing: usize,
    p: usize,
    grid: []const f64, // rows of p + 1 (parameters, SSE); one row = no grid
    history: []const f64, // rows of p + 1, iteration 0 first
    iterations: usize,
    theta: []const f64,
    sse: f64,
    r: f64,
    ppc: f64,
    ppc_i: usize,
    rpc: f64,
    rpc_i: usize,
    object: f64,
    total_ss: f64, // uncorrected
    mse: f64,
    se: []const f64,
    lower: []const f64,
    upper: []const f64,
    skew: []const f64, // empty without HOUGAARD
    corr: []const f64, // p x p
};

// PROC statement options of pp.6987-6998 that are valid but not implemented.
const valued_gap_options = [_][]const u8{ "best", "convergeobj", "convergeparm", "delta", "fd", "fdhessian", "maxsubit", "outest", "plots", "plot", "rho", "sigsq", "singular", "smethod", "tau", "nlinmeasures", "bias", "save" };
const flag_gap_options = [_][]const u8{ "bias", "ecorr", "ecov", "eformat", "flow", "g4", "list", "listall", "listcode", "listdep", "listder", "nlinmeasures", "nohalve", "noitprint", "noprint", "noxref", "plots", "plot", "print", "save", "stats", "totalss", "trace", "uncorrecteddf", "xref" };
const later_statements = [_][]const u8{ "bounds", "bootstrap", "contrast", "control", "estimate", "output", "profile", "retain" };
const programming_words = [_][]const u8{ "if", "else", "do", "end", "array", "call", "goto", "link", "return", "select", "when", "otherwise", "put", "stop", "file", "length", "label", "attrib", "drop", "keep" };

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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC NLIN: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
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
    if (v == null) return cx.diags.fail(error.ParseError, line(t, j), "PROC NLIN: {s} requires a numeric value", .{what});
    i.* = j + 1;
    return sign * v.?;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var gaps: std.ArrayList([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = try std.ascii.allocLowerString(a, t[i].text);
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return proc.failGap(cx.diags, t[i].line, "PROC NLIN: repeated PROC statement option {s} is not verified", .{t[i].text});
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
        } else if (eq(option, "method") and valued) {
            const m = i + 2;
            s.method = if (kw(t, m, "gauss") or kw(t, m, "gaussnewton")) .gauss else if (kw(t, m, "marquardt")) .marquardt else if (kw(t, m, "newton")) .newton else if (kw(t, m, "gradient")) .gradient else return cx.diags.fail(error.ParseError, line(t, m), "PROC NLIN: METHOD= must be GAUSS, MARQUARDT, NEWTON or GRADIENT", .{});
            i += 3;
        } else if ((eq(option, "converge") or eq(option, "maxiter") or eq(option, "alpha")) and valued) {
            i += 2;
            const v = try number(cx, t, &i, t[i - 2].text);
            if (eq(option, "converge")) {
                if (!(v >= 0)) return cx.diags.fail(error.ParseError, line(t, i - 1), "PROC NLIN: CONVERGE= must be nonnegative", .{});
                s.converge = v;
            } else if (eq(option, "maxiter")) {
                if (!(v >= 0) or v != @floor(v) or v > 1e9) return cx.diags.fail(error.ParseError, line(t, i - 1), "PROC NLIN: MAXITER= must be a nonnegative integer", .{});
                s.maxiter = @intFromFloat(v);
            } else {
                if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, line(t, i - 1), "PROC NLIN: ALPHA= must be between 0 and 1", .{});
                s.alpha = v;
            }
        } else if (valued and oneOf(option, &valued_gap_options)) {
            try gaps.append(a, option);
            i += 2;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i) else {
                if (at(t, i, .minus)) i += 1;
                if (at(t, i, .semicolon) or at(t, i, .eof)) return invalid(cx, t, i);
                i += 1;
                if (at(t, i, .dot) and at(t, i + 1, .name)) i += 2;
                if (at(t, i, .lparen)) i = proc.skipParen(t, i);
            }
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "hougaard")) {
            s.hougaard = true;
            i += 1;
        } else if (oneOf(option, &flag_gap_options)) {
            try gaps.append(a, option);
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC NLIN: input data set not found", .{});
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
    var later: std.ArrayList([]const u8) = .empty;
    var ids: std.ArrayList(usize) = .empty;
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
        if (at(t, i + 1, .eq) or (eq(word, "der") and at(t, i + 1, .dot))) {
            // `name = expression;` and `DER.parm = expression;`
            return proc.failGap(cx.diags, t[i].line, "PROC NLIN: programming statements and DER. statements are not implemented (STAT-NLIN-015)", .{});
        } else if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "parms") or eq(word, "parameters") or eq(word, "parm")) {
            var j = i + 1;
            if (j == end) return invalid(cx, t, end);
            while (j < end) {
                if (at(t, j, .slash)) return proc.failGap(cx.diags, t[j].line, "PROC NLIN: PARAMETERS statement options (PDATA=) are not implemented (STAT-NLIN-008)", .{});
                if (!at(t, j, .name) or !at(t, j + 1, .eq)) return invalid(cx, t, j);
                const pname = t[j].text;
                for (params.items) |q| if (eq(q.name, pname)) return cx.diags.fail(error.ParseError, t[j].line, "PROC NLIN: parameter {s} is declared more than once", .{pname});
                if (ds.indexOf(pname) != null) return cx.diags.fail(error.ParseError, t[j].line, "PROC NLIN: parameter {s} has the name of a variable in the input data set", .{pname});
                j += 2;
                var values: std.ArrayList(f64) = .empty;
                const first = try number(cx, t, &j, "a PARAMETERS starting value");
                if (kw(t, j, "to")) {
                    j += 1;
                    const last = try number(cx, t, &j, "PARAMETERS TO");
                    var step: f64 = 1;
                    if (kw(t, j, "by")) {
                        j += 1;
                        step = try number(cx, t, &j, "PARAMETERS BY");
                    }
                    if (!(step > 0) or !(last >= first)) return proc.failGap(cx.diags, line(t, j - 1), "PROC NLIN: a PARAMETERS grid with a nonpositive BY or a descending range is not verified (STAT-NLIN-008)", .{});
                    const count = @floor((last - first) / step + 1e-9);
                    if (count > 1e5) return cx.diags.fail(error.ParseError, line(t, j - 1), "PROC NLIN: the PARAMETERS grid for {s} is too large", .{pname});
                    var k: f64 = 0;
                    while (k <= count) : (k += 1) try values.append(a, first + k * step);
                } else try values.append(a, first);
                if (at(t, j, .comma)) return proc.failGap(cx.diags, t[j].line, "PROC NLIN: comma-separated PARAMETERS value lists are not implemented (STAT-NLIN-008)", .{});
                try params.append(a, .{ .name = pname, .values = values.items });
            }
        } else if (eq(word, "model")) {
            if (model_tokens != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC NLIN: only one MODEL statement is allowed", .{});
            if (!at(t, i + 1, .name) or !at(t, i + 2, .eq) or end <= i + 3) return invalid(cx, t, @min(i + 1, end));
            s.dependent = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "PROC NLIN: dependent variable {s} is not on the input data set", .{t[i + 1].text});
            if (ds.columns.items[s.dependent].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC NLIN: dependent variable {s} must be numeric", .{t[i + 1].text});
            model_tokens = t[i + 3 .. end];
            model_at = i;
        } else if (eq(word, "id")) {
            // p.7003: ID variables only label the OUTPUT data set.
            if (end == i + 1) return invalid(cx, t, end);
            for (t[i + 1 .. end], i + 1..) |tok, j| {
                if (tok.tag != .name) return invalid(cx, t, j);
                const ci = ds.indexOf(tok.text) orelse return cx.diags.fail(error.ParseError, tok.line, "PROC NLIN: variable {s} in the ID statement is not on the input data set", .{tok.text});
                try ids.append(a, ci);
            }
        } else if (oneOf(word, &later_statements)) {
            try later.append(a, try std.ascii.allocLowerString(a, word));
        } else if (oneOf(word, &programming_words)) {
            return proc.failGap(cx.diags, t[i].line, "PROC NLIN: programming statements are not implemented (STAT-NLIN-015)", .{});
        } else if (eq(word, "format")) {
            return proc.failGap(cx.diags, t[i].line, "PROC NLIN: a FORMAT statement inside the step is not implemented", .{});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const body = model_tokens orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC NLIN: a MODEL statement is required", .{});
    if (params.items.len == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC NLIN: a PARAMETERS statement is required", .{});
    s.params = params.items;
    s.gap_options = gaps.items;
    s.later = later.items;
    s.id_cols = ids.items;

    // The model expression: shared expression parser, then a whitelist of the
    // node kinds this file can differentiate.
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

fn check(cx: proc.ProcCtx, s: Spec, e: *const ast.Expr, cols: *std.ArrayList(usize), l: usize) diag.Error!void {
    const gap = proc.failGap;
    switch (e.*) {
        .num => {},
        .variable => |v| {
            for (s.params) |q| if (eq(q.name, v)) return;
            const ci = s.input.ds.indexOf(v) orelse return cx.diags.fail(error.ParseError, l, "PROC NLIN: {s} in the MODEL expression is neither a parameter nor a variable in the input data set", .{v});
            if (s.input.ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "PROC NLIN: character variable {s} cannot be used in the MODEL expression", .{v});
            if (std.mem.indexOfScalar(usize, cols.items, ci) == null) try cols.append(cx.arena, ci);
        },
        .unary => |u| {
            if (u.op != .neg) return gap(cx.diags, l, "PROC NLIN: logical operators in the MODEL expression are not implemented (STAT-NLIN-003)", .{});
            try check(cx, s, u.operand, cols, l);
        },
        .binary => |b| {
            switch (b.op) {
                .add, .sub, .mul, .div, .pow => {},
                else => return gap(cx.diags, l, "PROC NLIN: only + - * / ** operators are implemented in the MODEL expression (STAT-NLIN-003)", .{}),
            }
            try check(cx, s, b.lhs, cols, l);
            try check(cx, s, b.rhs, cols, l);
        },
        .call => |c| {
            if (c.args.len != 1 or !(eq(c.name, "exp") or eq(c.name, "log") or eq(c.name, "sqrt")))
                return gap(cx.diags, l, "PROC NLIN: function {s} in the MODEL expression is not implemented; only EXP, LOG and SQRT are (STAT-NLIN-003/005)", .{c.name});
            try check(cx, s, &c.args[0], cols, l);
        },
        else => return gap(cx.diags, l, "PROC NLIN: this MODEL expression form is not implemented (STAT-NLIN-003)", .{}),
    }
}

// ── Symbolic derivatives (null = identically zero) ──────────────────────────

const E = *const ast.Expr;
fn node(a: A, e: ast.Expr) !E {
    const p = try a.create(ast.Expr);
    p.* = e;
    return p;
}
fn bin(a: A, op: ast.BinOp, l: E, r: E) !E {
    if (op == .mul) {
        if (l.* == .num and l.num == 1) return r;
        if (r.* == .num and r.num == 1) return l;
    }
    return node(a, .{ .binary = .{ .op = op, .lhs = l, .rhs = r } });
}
fn neg(a: A, e: E) !E {
    return node(a, .{ .unary = .{ .op = .neg, .operand = e } });
}
fn call1(a: A, name: []const u8, arg: E) !E {
    const args = try a.alloc(ast.Expr, 1);
    args[0] = arg.*;
    return node(a, .{ .call = .{ .name = name, .args = args } });
}
fn sum(a: A, l: ?E, r: ?E) !?E {
    if (l == null) return r;
    if (r == null) return l;
    return try bin(a, .add, l.?, r.?);
}

/// d(e)/d(name) as an expression for the shared evaluator; `e` has passed `check`.
pub fn deriv(a: A, e: E, name: []const u8) error{ OutOfMemory, Unsupported }!?E {
    switch (e.*) {
        .num => return null,
        .variable => |v| return if (eq(v, name)) try node(a, .{ .num = 1 }) else null,
        .unary => |u| {
            if (u.op != .neg) return error.Unsupported;
            const d = (try deriv(a, u.operand, name)) orelse return null;
            return try neg(a, d);
        },
        .binary => |b| {
            const dl = try deriv(a, b.lhs, name);
            const dr = try deriv(a, b.rhs, name);
            switch (b.op) {
                .add => return sum(a, dl, dr),
                .sub => {
                    if (dr == null) return dl;
                    if (dl == null) return try neg(a, dr.?);
                    return try bin(a, .sub, dl.?, dr.?);
                },
                .mul => return sum(a, if (dl) |d| try bin(a, .mul, d, b.rhs) else null, if (dr) |d| try bin(a, .mul, b.lhs, d) else null),
                .div => {
                    // (u/v)' = u'/v - u*v'/(v*v)
                    const first: ?E = if (dl) |d| try bin(a, .div, d, b.rhs) else null;
                    const d = dr orelse return first;
                    const second = try bin(a, .div, try bin(a, .mul, b.lhs, d), try bin(a, .mul, b.rhs, b.rhs));
                    if (first == null) return try neg(a, second);
                    return try bin(a, .sub, first.?, second);
                },
                .pow => {
                    // (u**v)' = v*u**(v-1)*u' + u**v*log(u)*v'
                    const first: ?E = if (dl) |d| try bin(a, .mul, try bin(a, .mul, b.rhs, try bin(a, .pow, b.lhs, try bin(a, .sub, b.rhs, try node(a, .{ .num = 1 })))), d) else null;
                    const second: ?E = if (dr) |d| try bin(a, .mul, try bin(a, .mul, e, try call1(a, "log", b.lhs)), d) else null;
                    return sum(a, first, second);
                },
                else => return error.Unsupported,
            }
        },
        .call => |c| {
            if (c.args.len != 1) return error.Unsupported;
            const u: E = &c.args[0];
            const d = (try deriv(a, u, name)) orelse return null;
            if (eq(c.name, "exp")) return try bin(a, .mul, e, d);
            if (eq(c.name, "log")) return try bin(a, .div, d, u);
            if (eq(c.name, "sqrt")) return try bin(a, .div, d, try bin(a, .mul, try node(a, .{ .num = 2 }), e));
            return error.Unsupported;
        },
        else => return error.Unsupported,
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
        if (!(@abs(m[best * p + c]) > 1e-13 * scale)) return null;
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

/// Fit one BY group. Every condition the reference listing does not verify is
/// a loud gap.
pub fn fit(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Fit {
    const a = cx.arena;
    const gap = proc.failGap;
    const p = s.params.len;
    if (s.method != .marquardt) return gap(cx.diags, 0, "PROC NLIN: only METHOD=MARQUARDT is verified against SAS output; METHOD={s} (GAUSS is the default) is not implemented (STAT-NLIN-002/006)", .{@tagName(s.method)});

    // Missing Values (p.7024): an observation with a missing dependent or
    // model variable is not used.
    var kept: std.ArrayList([]const Value) = .empty;
    for (rows) |row| {
        var ok = !std.math.isNan(row[s.dependent].num);
        for (s.model_cols) |ci| ok = ok and !std.math.isNan(row[ci].num);
        if (ok) try kept.append(a, row);
    }
    const n = kept.items.len;
    if (n <= p) return gap(cx.diags, 0, "PROC NLIN: a fit with {d} usable observations and {d} parameters is not implemented (STAT-NLIN-002)", .{ n, p });
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
    for (s.params, 1..) |q, k| exprs[k] = deriv(a, s.model, q.name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return gap(cx.diags, 0, "PROC NLIN: the MODEL expression cannot be differentiated (STAT-NLIN-005)", .{}),
    };
    const only_f = exprs[0..1];
    const vals = try a.alloc(f64, n * (p + 1));
    const fv = try a.alloc(f64, n);
    const State = struct {
        fn sse(m: *Model, th: []const f64, ex: []const ?E, buf: []f64, yy: []const f64) diag.Error!f64 {
            try m.at(th, ex, buf);
            var t: f64 = 0;
            for (buf, yy) |f, v| t += (v - f) * (v - f);
            return t;
        }
    };

    // Grid of starting values: the point with the smallest SSE starts the fit.
    var multi: usize = 0;
    var grid_n: usize = 1;
    for (s.params) |q| if (q.values.len > 1) {
        multi += 1;
        grid_n = q.values.len;
    };
    if (multi > 1) return gap(cx.diags, 0, "PROC NLIN: a starting-value grid over more than one parameter is not verified (STAT-NLIN-008)", .{});
    const grid = try a.alloc(f64, grid_n * (p + 1));
    const theta = try a.alloc(f64, p);
    var best: usize = 0;
    for (0..grid_n) |g| {
        const row = grid[g * (p + 1) ..][0 .. p + 1];
        for (s.params, 0..) |q, k| row[k] = if (q.values.len > 1) q.values[g] else q.values[0];
        row[p] = try State.sse(&model, row[0..p], only_f, fv, y);
        if (!std.math.isFinite(row[p])) return gap(cx.diags, 0, "PROC NLIN: a model that cannot be evaluated at the starting values is not implemented (STAT-NLIN-005)", .{});
        if (row[p] < grid[best * (p + 1) + p]) best = g;
    }
    @memcpy(theta, grid[best * (p + 1) ..][0..p]);
    var sse = grid[best * (p + 1) + p];

    var history: std.ArrayList(f64) = .empty;
    try history.appendSlice(a, theta);
    try history.append(a, sse);
    const xtx = try a.alloc(f64, p * p);
    const g = try a.alloc(f64, p);
    const damped = try a.alloc(f64, p * p);
    const trial = try a.alloc(f64, p);
    const prev = try a.alloc(f64, p);
    var prev_sse: f64 = nan;
    var lambda: f64 = 1e-7; // Marquardt: lambda starts at 1E-7, /10 on success, *10 on failure
    var iterations: usize = 0;
    var r: f64 = nan;
    var gn: []f64 = undefined;
    while (true) {
        try model.at(theta, exprs, vals);
        @memset(xtx, 0);
        @memset(g, 0);
        for (0..n) |m| {
            const v = vals[m * (p + 1) ..][0 .. p + 1];
            const res = y[m] - v[0];
            for (0..p) |i| {
                g[i] += v[1 + i] * res;
                for (0..p) |j| xtx[i * p + j] += v[1 + i] * v[1 + j];
            }
        }
        for (xtx) |v| if (!std.math.isFinite(v)) return gap(cx.diags, 0, "PROC NLIN: derivatives that cannot be evaluated are not implemented (STAT-NLIN-005)", .{});
        gn = (try solve(a, xtx, g, p)) orelse return gap(cx.diags, 0, "PROC NLIN: a singular Jacobian cross-product matrix is not implemented (STAT-NLIN-006)", .{});
        if (!(sse > 0)) return gap(cx.diags, 0, "PROC NLIN: an exact fit (zero residual sum of squares) is not verified (STAT-NLIN-006)", .{});
        var quad: f64 = 0;
        for (g, gn) |u, v| quad += u * v;
        // R = sqrt(r'X(X'X)^-1 X'r / SSE): the relative offset convergence measure.
        r = @sqrt(@max(quad, 0) / sse);
        if (r < s.converge) break;
        if (iterations >= s.maxiter) return gap(cx.diags, 0, "PROC NLIN: the fit did not converge in {d} iterations; nonconvergence reporting is not implemented (STAT-NLIN-006)", .{s.maxiter});
        var tries: usize = 0;
        const new_sse = while (true) : (tries += 1) {
            if (tries > 60) return gap(cx.diags, 0, "PROC NLIN: no Marquardt step reduces the sum of squares; this is not implemented (STAT-NLIN-006)", .{});
            @memcpy(damped, xtx);
            for (0..p) |i| damped[i * p + i] *= 1 + lambda;
            if (try solve(a, damped, g, p)) |d| {
                for (trial, theta, d) |*tv, b, dv| tv.* = b + dv;
                const t = try State.sse(&model, trial, only_f, fv, y);
                if (t < sse) {
                    lambda /= 10;
                    break t;
                }
            }
            lambda *= 10;
        };
        @memcpy(prev, theta);
        prev_sse = sse;
        @memcpy(theta, trial);
        sse = new_sse;
        iterations += 1;
        try history.appendSlice(a, theta);
        try history.append(a, sse);
    }
    if (iterations == 0) return gap(cx.diags, 0, "PROC NLIN: convergence at the starting values (no iteration) is not verified (STAT-NLIN-006)", .{});

    var f: Fit = .{ .read = rows.len, .used = n, .missing = rows.len - n, .p = p, .grid = grid, .history = history.items, .iterations = iterations, .theta = theta, .sse = sse, .r = r, .ppc = 0, .ppc_i = 0, .rpc = 0, .rpc_i = 0, .object = @abs(prev_sse - sse) / (prev_sse + 1e-6), .total_ss = total, .mse = sse / @as(f64, @floatFromInt(n - p)), .se = &.{}, .lower = &.{}, .upper = &.{}, .skew = &.{}, .corr = &.{} };
    // PPC: prospective relative parameter change of the next Gauss-Newton
    // step; RPC: retrospective relative change of the last step.
    for (0..p) |i| {
        const ppc = @abs(gn[i]) / (@abs(theta[i]) + 1e-6);
        const rpc = @abs(theta[i] - prev[i]) / (@abs(prev[i]) + 1e-6);
        if (ppc > f.ppc) {
            f.ppc = ppc;
            f.ppc_i = i;
        }
        if (rpc > f.rpc) {
            f.rpc = rpc;
            f.rpc_i = i;
        }
    }

    // The listing with an intercept (corrected total) has no reference: detect
    // a constant in the column space of the Jacobian.
    const ones = try a.alloc(f64, p);
    @memset(ones, 0);
    for (0..n) |m| for (0..p) |i| {
        ones[i] += vals[m * (p + 1) + 1 + i];
    };
    const c1 = (try solve(a, xtx, ones, p)).?;
    var fitted: f64 = 0;
    for (ones, c1) |u, v| fitted += u * v;
    const nf: f64 = @floatFromInt(n);
    if (nf - fitted < 1e-8 * nf) return gap(cx.diags, 0, "PROC NLIN: the corrected-total listing of a model with an intercept is not verified (STAT-NLIN-013)", .{});

    // (X'X)^-1
    const inv = try a.alloc(f64, p * p);
    const unit = try a.alloc(f64, p);
    for (0..p) |j| {
        @memset(unit, 0);
        unit[j] = 1;
        const col = (try solve(a, xtx, unit, p)).?;
        for (0..p) |i| inv[i * p + j] = col[i];
    }
    const se = try a.alloc(f64, p);
    const lower = try a.alloc(f64, p);
    const upper = try a.alloc(f64, p);
    const corr = try a.alloc(f64, p * p);
    const tc = reg_fit.tCritical(s.alpha, n - p);
    for (0..p) |i| {
        se[i] = @sqrt(f.mse * inv[i * p + i]);
        lower[i] = theta[i] - tc * se[i];
        upper[i] = theta[i] + tc * se[i];
        for (0..p) |j| corr[i * p + j] = if (i == j) 1 else inv[i * p + j] / @sqrt(inv[i * p + i] * inv[j * p + j]);
    }
    f.se = se;
    f.lower = lower;
    f.upper = upper;
    f.corr = corr;

    if (s.hougaard) {
        // Hougaard's skewness: E[(b_i - E b_i)^3] = -mse^2 * sum_jkl
        // L_ij L_ik L_il (W_jkl + W_kjl + W_lkj), W_jkl = sum_m J_mj H_mkl,
        // L = (X'X)^-1, standardised by (mse * L_ii)^1.5.
        const second = try a.alloc(?E, p * p);
        for (0..p) |k| for (0..p) |l| {
            second[k * p + l] = if (exprs[1 + k]) |d1| deriv(a, d1, s.params[l].name) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Unsupported => return gap(cx.diags, 0, "PROC NLIN: second derivatives of the MODEL expression are not available (STAT-NLIN-011)", .{}),
            } else null;
        };
        const h = try a.alloc(f64, n * p * p);
        try model.at(theta, second, h);
        const w = try a.alloc(f64, p * p * p);
        @memset(w, 0);
        for (0..n) |m| for (0..p) |j| for (0..p * p) |kl| {
            w[j * p * p + kl] += vals[m * (p + 1) + 1 + j] * h[m * p * p + kl];
        };
        const skew = try a.alloc(f64, p);
        for (0..p) |i| {
            var third: f64 = 0;
            for (0..p) |j| for (0..p) |k| for (0..p) |l| {
                third += inv[i * p + j] * inv[i * p + k] * inv[i * p + l] * (w[(j * p + k) * p + l] + w[(k * p + j) * p + l] + w[(l * p + k) * p + j]);
            };
            skew[i] = -f.mse * f.mse * third / std.math.pow(f64, f.mse * inv[i * p + i], 1.5);
            if (!std.math.isFinite(skew[i])) return gap(cx.diags, 0, "PROC NLIN: Hougaard's skewness could not be evaluated (STAT-NLIN-011)", .{});
        }
        f.skew = skew;
    }
    return f;
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
/// The D8.3-style cell of the NLIN tables: decimals follow the magnitude
/// (reference: 0.00313, 0.0741, 19.6606, 158.1, 3075.4, 88537.2, 290116, 0).
pub fn cell(a: A, x: f64) ![]const u8 {
    if (x == 0) return "0";
    const ax = @abs(x);
    const decimals: usize = if (ax < 0.01) @intFromFloat(@min(14, 2 - @floor(std.math.log10(ax)))) else if (ax < 100) 4 else if (ax < 100000) 1 else 0;
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn best8(a: A, x: f64) ![]const u8 {
    const text = std.mem.trim(u8, try fmt.apply(a, .{ .num = x }, "BEST8."), " ");
    // The reference prints 7.83E-5 as 0.000078: fixed notation down to 1E-5.
    if (@abs(x) >= 1e-5 and @abs(x) < 1 and std.mem.indexOfScalar(u8, text, 'E') != null) return std.fmt.allocPrint(a, "{d:.6}", .{x});
    return text;
}
fn summary(a: A, out: *Out, label: []const u8, value: []const u8) !void {
    try out.appendSlice(a, label);
    try padLeft(a, out, value, @max(33, label.len + 2 + value.len) - label.len);
    try out.append(a, '\n');
}
fn heading(a: A, out: *Out, s: Spec, method: bool) !void {
    try out.print(a, "\nThe NLIN Procedure\nDependent Variable {s}\n", .{s.input.ds.columns.items[s.dependent].name});
    if (method) try out.appendSlice(a, "Method: Marquardt\n");
    try out.append(a, '\n');
}

fn render(a: A, out: *Out, s: Spec, f: Fit) !void {
    const p = f.p;
    if (f.grid.len > p + 1) {
        try heading(a, out, s, false);
        const width = 8 + 12 * p;
        try out.appendNTimes(a, ' ', (width - @min(width, 11) + 1) / 2);
        try out.appendSlice(a, "Grid Search\n");
        try padLeft(a, out, "Sum of", width);
        try out.append(a, '\n');
        for (s.params, 0..) |q, k| try padLeft(a, out, q.name, if (k == 0) 8 else 12);
        try padLeft(a, out, "Squares", 12);
        try out.appendSlice(a, "\n\n");
        var g: usize = 0;
        while (g < f.grid.len) : (g += p + 1) {
            for (f.grid[g..][0 .. p + 1], 0..) |v, k| try padLeft(a, out, try cell(a, v), if (k == 0) 8 else 12);
            try out.append(a, '\n');
        }
    }
    try heading(a, out, s, true);
    const width = 17 + 12 * p;
    try out.appendNTimes(a, ' ', (width - @min(width, 15)) / 2);
    try out.appendSlice(a, "Iterative Phase\n");
    try padLeft(a, out, "Sum of", width);
    try out.appendSlice(a, "\n Iter");
    for (s.params) |q| try padLeft(a, out, q.name, 12);
    try padLeft(a, out, "Squares", 12);
    try out.appendSlice(a, "\n\n");
    var it: usize = 0;
    while (it * (p + 1) < f.history.len) : (it += 1) {
        try out.print(a, "{d:>5}", .{it});
        for (f.history[it * (p + 1) ..][0 .. p + 1]) |v| try padLeft(a, out, try cell(a, v), 12);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\nNOTE: Convergence criterion met." ++ " " ** 32 ++ "\n\n\n       Estimation Summary\n\n");
    try summary(a, out, "Method", "Marquardt");
    try summary(a, out, "Iterations", try std.fmt.allocPrint(a, "{d}", .{f.iterations}));
    try summary(a, out, "R", try best8(a, f.r));
    try summary(a, out, try std.fmt.allocPrint(a, "PPC({s})", .{s.params[f.ppc_i].name}), try best8(a, f.ppc));
    try summary(a, out, try std.fmt.allocPrint(a, "RPC({s})", .{s.params[f.rpc_i].name}), try best8(a, f.rpc));
    try summary(a, out, "Object", try best8(a, f.object));
    try summary(a, out, "Objective", try best8(a, f.sse));
    try summary(a, out, "Observations Read", try std.fmt.allocPrint(a, "{d}", .{f.read}));
    try summary(a, out, "Observations Used", try std.fmt.allocPrint(a, "{d}", .{f.used}));
    try summary(a, out, "Observations Missing", try std.fmt.allocPrint(a, "{d}", .{f.missing}));

    try out.appendSlice(a, "\n\nNOTE: An intercept was not specified for this model.\n\n");
    try out.appendSlice(a, "                                  Sum of        Mean               Approx\n");
    try out.appendSlice(a, "Source                    DF     Squares      Square    F Value    Pr > F\n\n");
    const model_ss = f.total_ss - f.sse;
    const ms = model_ss / @as(f64, @floatFromInt(p));
    const fvalue = ms / f.mse;
    const prob = reg_fit.fProbability(fvalue, p, f.used - p);
    try out.print(a, "{s:<18}{d:>10}", .{ "Model", p });
    try padLeft(a, out, try cell(a, model_ss), 12);
    try padLeft(a, out, try cell(a, ms), 12);
    var ftext = try std.fmt.allocPrint(a, "{d:.2}", .{fvalue});
    if (ftext.len > 7) ftext = try std.fmt.allocPrint(a, "{d:.1}", .{fvalue});
    if (ftext.len > 7) ftext = try std.fmt.allocPrint(a, "{d:.0}", .{fvalue});
    try padLeft(a, out, ftext, 11);
    try padLeft(a, out, if (prob < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{prob}), 10);
    try out.print(a, "\n{s:<18}{d:>10}", .{ "Error", f.used - p });
    try padLeft(a, out, try cell(a, f.sse), 12);
    try padLeft(a, out, try cell(a, f.mse), 12);
    try out.appendNTimes(a, ' ', 21);
    try out.print(a, "\n{s:<18}{d:>10}", .{ "Uncorrected Total", f.used });
    try padLeft(a, out, try cell(a, f.total_ss), 12);
    try out.appendNTimes(a, ' ', 33);

    const level = (1 - s.alpha) * 100;
    const level_text = if (@abs(level - @round(level)) < 1e-9) try std.fmt.allocPrint(a, "{d:.0}", .{level}) else try std.fmt.allocPrint(a, "{d}", .{level});
    try out.print(a, "\n\n\n                              Approx       Approximate {s}%\n", .{level_text});
    try out.appendSlice(a, "Parameter      Estimate    Std Error      Confidence Limits");
    if (s.hougaard) try out.appendSlice(a, "     Skewness");
    try out.appendSlice(a, "\n\n");
    var name_width: usize = 6;
    for (s.params) |q| name_width = @max(name_width, q.name.len);
    for (s.params, 0..) |q, i| {
        try padRight(a, out, q.name, @max(11, name_width + 1));
        try padLeft(a, out, try cell(a, f.theta[i]), 12);
        try padLeft(a, out, try cell(a, f.se[i]), 13);
        try padLeft(a, out, try cell(a, f.lower[i]), 12);
        try padLeft(a, out, try cell(a, f.upper[i]), 12);
        if (s.hougaard) try padLeft(a, out, try cell(a, f.skew[i]), 12);
        try out.append(a, '\n');
    }

    const cwidth = name_width + 16 * p;
    try out.appendSlice(a, "\n\n");
    try out.appendNTimes(a, ' ', (cwidth - @min(cwidth, 30)) / 2);
    try out.appendSlice(a, "Approximate Correlation Matrix\n");
    try out.appendNTimes(a, ' ', name_width);
    for (s.params) |q| try padLeft(a, out, q.name, 16);
    try out.appendSlice(a, "\n\n");
    for (s.params, 0..) |q, i| {
        try padRight(a, out, q.name, name_width);
        for (0..p) |j| try padLeft(a, out, try std.fmt.allocPrint(a, "{d:.7}", .{f.corr[i * p + j]}), 16);
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const l0 = line(t, 0);
    const gap = proc.failGap;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);

    // Boundaries owned by later NLIN tickets: fail visibly, print nothing.
    if (s.later.len > 0) return gap(cx.diags, l0, "PROC NLIN: the {s} statement is not implemented (STAT-NLIN-004/008..012)", .{s.later[0]});
    if (s.gap_options.len > 0) return gap(cx.diags, l0, "PROC NLIN: PROC statement option {s} is not implemented (STAT-NLIN-002/006/011..014)", .{s.gap_options[0]});

    var body: Out = .empty;
    for (groups) |group| {
        const f = try fit(cx, s, group.rows);
        if (s.by_cols.len > 0) try by.appendLine(a, &body, ds, group.rows[0], s.by_cols);
        try render(a, &body, s, f);
    }
    for (groups) |group| {
        for (s.params) |q| try cx.diags.note(0, "DER.{s} not initialized or missing. It will be computed automatically.", .{q.name});
        try cx.diags.note(0, "Convergence criterion met.", .{});
        if (s.by_cols.len > 0) try by.reportNote(a, cx.diags, ds, group.rows[0], s.by_cols);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("nlin_tests.zig");
}
