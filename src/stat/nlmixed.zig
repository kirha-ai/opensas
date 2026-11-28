//! PROC NLMIXED declarations, variable roles, BY/ID and observation
//! accounting, SAS/STAT 15.4 ch.89 (STAT-NLMIXED-001; PROC statement
//! pp.7097-7116, BY p.7117, ID p.7122). The step is parsed and validated, the
//! parameters, random effects and subject clusters are identified, and the
//! "Specifications" and "Dimensions" tables are rendered in the SAS 9.4 layout
//! of the ticket's reference listing. Estimation (adaptive Gaussian
//! quadrature, dual quasi-Newton optimization) belongs to STAT-NLMIXED-002 and
//! is a loud D-009 gap: `run` prints nothing for a step that reaches it, so no
//! partial or approximate analysis is ever displayed.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const ast = @import("../ast.zig");
const pe = @import("../parser_expr.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Distribution = enum { normal, binary, binomial, gamma, negbin, poisson, general };
const dist_names = [_]struct { []const u8, Distribution, usize }{
    .{ "normal", .normal, 2 }, .{ "binary", .binary, 1 },   .{ "binomial", .binomial, 2 }, .{ "gamma", .gamma, 2 },
    .{ "negbin", .negbin, 2 }, .{ "poisson", .poisson, 1 }, .{ "general", .general, 1 },
};

pub const Assignment = struct { target: []const u8, value: *const ast.Expr };
pub const Random = struct {
    effects: []const []const u8,
    mean: *const ast.Expr,
    variance: *const ast.Expr,
    /// SUBJECT= variable and, for `SUBJECT=b(a)`, the containing variables.
    subject: usize,
    within: []const usize = &.{},
};
pub const Bound = struct { name: []const u8, lower: ?f64 = null, upper: ?f64 = null };
pub const Param = struct { name: []const u8, start: f64 = 1 };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    /// PROC statement defaults (pp.7097-7116): METHOD=GAUSS (adaptive),
    /// TECHNIQUE=QUANEW (dual quasi-Newton), ALPHA=0.05.
    alpha: f64 = 0.05,
    df: ?f64 = null,
    /// NOSORTSUB (p.7112): a new subject starts whenever the SUBJECT= value
    /// changes, as before SAS/STAT 13.1.
    nosortsub: bool = false,
    /// Valid PROC options whose effect is not implemented (first is reported).
    gap_options: []const []const u8 = &.{},
    /// Valid statements owned by later NLMIXED tickets (first is reported).
    later: []const []const u8 = &.{},
    program: []const Assignment = &.{},
    response: usize = 0,
    distribution: Distribution = .normal,
    dist_args: []const ast.Expr = &.{},
    randoms: []const Random = &.{},
    bounds: []const Bound = &.{},
    /// Parameters in order of first appearance (PARMS, BOUNDS, programming
    /// statements, MODEL, RANDOM, in source order); unlisted start at 1 (p.7110).
    params: []const Param = &.{},
    /// Data set variables the program, MODEL and RANDOM statements read.
    data_cols: []const usize = &.{},
    /// ID symbols (p.7122): only copied to PREDICT OUT= (STAT-NLMIXED-004).
    ids: []const []const u8 = &.{},
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
fn tilde(t: []const lex.Token, i: usize) bool {
    return at(t, i, .caret) and std.mem.eql(u8, t[i].text, "~");
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC NLMIXED: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, l: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, l, "PROC NLMIXED: " ++ text, args);
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, what: []const u8) diag.Error!f64 {
    var sign: f64 = 1;
    var j = i.*;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    } else if (at(t, j, .plus)) j += 1;
    const v = if (at(t, j, .number)) std.fmt.parseFloat(f64, t[j].text) catch null else null;
    if (v == null) return cx.diags.fail(error.ParseError, lineOf(t, j), "PROC NLMIXED: {s} requires a numeric value", .{what});
    i.* = j + 1;
    return sign * v.?;
}

/// Table 89.1 options other than DATA=, ALPHA= and DF= (valued, then flags).
const valued_gap_options = [_][]const u8{ "absconv", "abstol", "absfconv", "absftol", "absgconv", "absgtol", "absxconv", "absxtol", "asingular", "cfactor", "covsing", "ebssfrac", "ebsstol", "ebsteps", "ebsubsteps", "ebtol", "fconv", "fconv2", "fdigits", "fsize", "g4", "gconv", "hescal", "hs", "instep", "lcdeact", "lcepsilon", "lcsingular", "lcsing", "lcs", "linesearch", "lis", "lsprecision", "lsp", "maxfunc", "maxfu", "maxiter", "maxit", "maxstep", "maxtime", "method", "miniter", "minit", "msingular", "nthreads", "outq", "outr", "qfac", "qmax", "qpoints", "qscalefac", "qtol", "restart", "rest", "singchol", "singhess", "singsweep", "singswp", "singvar", "technique", "tech", "update", "upd", "vsingular", "xconv", "xtol", "xsize", "fd", "fdhessian", "fdhes", "inhessian", "inhess", "optcheck", "dampstep" };
const flag_gap_options = [_][]const u8{ "corr", "cov", "diahes", "ebopt", "ebzstart", "ecorr", "ecov", "eder", "empirical", "flow", "fd", "fdhessian", "fdhes", "hess", "inhessian", "inhess", "itdetails", "list", "listcode", "listdep", "listder", "noad", "noadscale", "optcheck", "dampstep", "start", "trace", "xref", "noprint" };
/// Statements owned by later NLMIXED tickets.
const later_statements = [_][]const u8{ "array", "cmptmodel", "contrast", "estimate", "predict", "replicate" };
const programming_words = [_][]const u8{ "if", "else", "do", "end", "call", "goto", "link", "return", "select", "when", "otherwise", "put", "stop", "abort", "retain", "length", "label", "attrib", "drop", "keep", "format" };

fn exprAt(cx: proc.ProcCtx, t: []const lex.Token, from: usize, to: usize) diag.Error!struct { e: *const ast.Expr, next: usize } {
    const toks = try cx.arena.alloc(lex.Token, to - from + 1);
    @memcpy(toks[0 .. to - from], t[from..to]);
    toks[to - from] = .{ .tag = .eof };
    var ep = pe.Parser.init(cx.arena, toks, cx.diags);
    const e = try ep.parseExpr();
    return .{ .e = e, .next = from + ep.pos };
}

/// `dist(args)` after a tilde; the whole rest of the statement up to `to`.
fn distCall(cx: proc.ProcCtx, t: []const lex.Token, from: usize, to: usize) diag.Error!struct { name: []const u8, args: []const ast.Expr, next: usize } {
    if (!at(t, from, .name) or !at(t, from + 1, .lparen)) return invalid(cx, t, from);
    var depth: usize = 0;
    var j = from + 1;
    while (j < to) : (j += 1) {
        if (at(t, j, .lparen)) depth += 1;
        if (at(t, j, .rparen)) {
            depth -= 1;
            if (depth == 0) break;
        }
    }
    if (j >= to) return invalid(cx, t, to);
    const r = try exprAt(cx, t, from, j + 1);
    if (r.next != j + 1 or r.e.* != .call) return invalid(cx, t, from);
    return .{ .name = r.e.call.name, .args = r.e.call.args, .next = j + 1 };
}

const Symbols = struct {
    names: std.ArrayList([]const u8) = .empty,
    fn add(self: *Symbols, a: A, name: []const u8) !void {
        for (self.names.items) |n| if (eq(n, name)) return;
        try self.names.append(a, name);
    }
    fn walk(self: *Symbols, cx: proc.ProcCtx, e: *const ast.Expr, l: usize) diag.Error!void {
        switch (e.*) {
            .num, .missing => {},
            .str => return gap(cx, l, "character constants in NLMIXED expressions are not implemented (STAT-NLMIXED-014)", .{}),
            .variable => |v| try self.add(cx.arena, v),
            .unary => |u| try self.walk(cx, u.operand, l),
            .binary => |b| {
                try self.walk(cx, b.lhs, l);
                try self.walk(cx, b.rhs, l);
            },
            .call => |c| for (c.args) |*arg| try self.walk(cx, arg, l),
            .array_ref => return gap(cx, l, "array references are not implemented (STAT-NLMIXED-004)", .{}),
        }
    }
};

fn dataColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined, .data_name = "" };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var gaps: std.ArrayList([]const u8) = .empty;
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
        } else if ((eq(option, "alpha") or eq(option, "df")) and valued) {
            // ALPHA= and DF= only change the estimate tables (STAT-NLMIXED-002);
            // they are validated and recorded.
            i += 2;
            const v = try number(cx, t, &i, t[i - 2].text);
            if (eq(option, "alpha")) {
                if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, lineOf(t, i - 1), "PROC NLMIXED: ALPHA= must be between 0 and 1", .{});
                s.alpha = v;
            } else {
                if (!(v > 0)) return cx.diags.fail(error.ParseError, lineOf(t, i - 1), "PROC NLMIXED: DF= must be positive", .{});
                s.df = v;
            }
        } else if (valued and oneOf(option, &valued_gap_options)) {
            try gaps.append(a, option);
            i += 2;
            if (at(t, i, .minus) or at(t, i, .plus)) i += 1;
            if (at(t, i, .semicolon) or at(t, i, .eof)) return invalid(cx, t, i);
            i += 1;
            if (at(t, i, .dot) and at(t, i + 1, .name)) i += 2;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "nosortsub")) {
            s.nosortsub = true;
            i += 1;
        } else if (oneOf(option, &flag_gap_options)) {
            try gaps.append(a, option);
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC NLMIXED: input data set not found", .{});
    const upper_name = try std.ascii.allocUpperString(a, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper_name, '.') != null) upper_name else try std.fmt.allocPrint(a, "WORK.{s}", .{upper_name});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var later: std.ArrayList([]const u8) = .empty;
    var program: std.ArrayList(Assignment) = .empty;
    var randoms: std.ArrayList(Random) = .empty;
    var bounds: std.ArrayList(Bound) = .empty;
    var starts: std.ArrayList(Param) = .empty;
    var ids: std.ArrayList([]const u8) = .empty;
    // Every symbol in source order; parameters are filtered from it below.
    var symbols: Symbols = .{};
    var model_seen = false;
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
        const l = t[i].line;
        if (at(t, i + 1, .eq) and !kw(t, i, "id")) {
            // `name = expression;` (p.7114 programming statements).
            if (end == i + 2) return invalid(cx, t, end);
            if (model_seen) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: the MODEL statement must follow the programming statements", .{});
            const r = try exprAt(cx, t, i + 2, end);
            if (r.next != end) return invalid(cx, t, r.next);
            if (ds.indexOf(word) != null) return gap(cx, l, "assigning to input data set variable {s} is not implemented (STAT-NLMIXED-014)", .{word});
            try symbols.walk(cx, r.e, l);
            try program.append(a, .{ .target = word, .value = r.e });
        } else if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.7117: with several BY statements only the last is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: only one MODEL statement is allowed", .{});
            model_seen = true;
            s.response = try dataColumn(cx, ds, t, i + 1);
            if (ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: dependent variable {s} must be numeric", .{t[i + 1].text});
            if (!tilde(t, i + 2)) return invalid(cx, t, i + 2);
            const d = try distCall(cx, t, i + 3, end);
            if (d.next != end) return invalid(cx, t, d.next);
            var found = false;
            for (dist_names) |entry| if (eq(d.name, entry[0])) {
                if (d.args.len != entry[2]) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: the {s} distribution takes {d} argument(s)", .{ entry[0], entry[2] });
                s.distribution = entry[1];
                found = true;
            };
            if (!found) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: unknown distribution {s} in the MODEL statement", .{d.name});
            for (d.args) |*arg| try symbols.walk(cx, arg, l);
            s.dist_args = d.args;
        } else if (eq(word, "random")) {
            // RANDOM effects ~ normal(m, v) SUBJECT=var (p.7112).
            var j = i + 1;
            var effects: std.ArrayList([]const u8) = .empty;
            while (j < end and at(t, j, .name)) : (j += 1) try effects.append(a, t[j].text);
            if (effects.items.len == 0 or !tilde(t, j)) return invalid(cx, t, j);
            if (effects.items.len > 1) return gap(cx, l, "a RANDOM statement with several effects is not implemented (STAT-NLMIXED-010)", .{});
            const d = try distCall(cx, t, j + 1, end);
            if (!eq(d.name, "normal")) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: the only random-effects distribution is NORMAL", .{});
            if (d.args.len != 2) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: the normal distribution takes 2 arguments", .{});
            j = d.next;
            if (!kw(t, j, "subject") or !at(t, j + 1, .eq)) {
                if (j < end and at(t, j, .name) and oneOf(t[j].text, &.{ "alpha", "df", "out" })) return gap(cx, l, "RANDOM statement option {s} is not implemented (STAT-NLMIXED-010)", .{t[j].text});
                return cx.diags.fail(error.ParseError, lineOf(t, j), "PROC NLMIXED: the RANDOM statement requires SUBJECT=", .{});
            }
            const subject = try dataColumn(cx, ds, t, j + 2);
            j += 3;
            var within: std.ArrayList(usize) = .empty;
            if (at(t, j, .lparen)) {
                j += 1;
                while (j < end and !at(t, j, .rparen)) : (j += 1) try within.append(a, try dataColumn(cx, ds, t, j));
                if (!at(t, j, .rparen) or within.items.len == 0) return invalid(cx, t, j);
                j += 1;
            }
            if (j != end) {
                if (at(t, j, .name) and oneOf(t[j].text, &.{ "alpha", "df", "out" })) return gap(cx, l, "RANDOM statement option {s} is not implemented (STAT-NLMIXED-010)", .{t[j].text});
                return invalid(cx, t, j);
            }
            // Hierarchy (p.7113): each later SUBJECT= is nested in all the
            // earlier ones, written b(a) or c(a b); only that form is verified.
            if (randoms.items.len != within.items.len) return gap(cx, l, "this RANDOM SUBJECT= hierarchy is not implemented (STAT-NLMIXED-006/010)", .{});
            for (randoms.items, within.items) |previous, w| if (previous.subject != w) return gap(cx, l, "this RANDOM SUBJECT= hierarchy is not implemented (STAT-NLMIXED-006/010)", .{});
            for (d.args) |*arg| try symbols.walk(cx, arg, l);
            try randoms.append(a, .{ .effects = effects.items, .mean = &d.args[0], .variance = &d.args[1], .subject = subject, .within = within.items });
        } else if (eq(word, "bounds")) {
            // BOUNDS b-con <, b-con ...> (p.7104); recorded, applied by the
            // optimizer (STAT-NLMIXED-009).
            var j = i + 1;
            while (j < end) {
                var lower: ?f64 = null;
                var upper: ?f64 = null;
                if (at(t, j, .number) or at(t, j, .minus) or at(t, j, .plus)) {
                    const v = try number(cx, t, &j, "a BOUNDS constant");
                    if (at(t, j, .le) or at(t, j, .lt)) lower = v else if (at(t, j, .ge) or at(t, j, .gt)) upper = v else return invalid(cx, t, j);
                    if (at(t, j, .lt) or at(t, j, .gt)) return gap(cx, l, "strict BOUNDS inequalities are not implemented (STAT-NLMIXED-009)", .{});
                    j += 1;
                }
                const first = j;
                while (j < end and at(t, j, .name)) : (j += 1) {}
                if (j == first) return invalid(cx, t, j);
                const names = t[first..j];
                if (at(t, j, .le) or at(t, j, .lt) or at(t, j, .ge) or at(t, j, .gt)) {
                    if (at(t, j, .lt) or at(t, j, .gt)) return gap(cx, l, "strict BOUNDS inequalities are not implemented (STAT-NLMIXED-009)", .{});
                    const is_upper = at(t, j, .le);
                    j += 1;
                    const v = try number(cx, t, &j, "a BOUNDS constant");
                    if (is_upper) upper = v else lower = v;
                }
                if (lower == null and upper == null) return invalid(cx, t, j);
                for (names) |tok| {
                    if (ds.indexOf(tok.text) != null) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: BOUNDS name {s} is an input data set variable, not a parameter", .{tok.text});
                    try symbols.add(a, tok.text);
                    try bounds.append(a, .{ .name = tok.text, .lower = lower, .upper = upper });
                }
                if (j < end) {
                    if (!at(t, j, .comma)) return invalid(cx, t, j);
                    j += 1;
                    if (j == end) return invalid(cx, t, j);
                }
            }
            if (i + 1 == end) return invalid(cx, t, end);
        } else if (eq(word, "parms") or eq(word, "parameters")) {
            // PARMS name-list = number <, ...> (p.7110). Grids, DATA= and the
            // slash options are STAT-NLMIXED-009.
            var j = i + 1;
            if (j == end) return invalid(cx, t, end);
            while (j < end) {
                if (at(t, j, .slash)) return gap(cx, l, "PARMS statement options are not implemented (STAT-NLMIXED-009)", .{});
                const first = j;
                while (j < end and at(t, j, .name)) : (j += 1) {}
                if (j == first or !at(t, j, .eq)) return invalid(cx, t, j);
                const names = t[first..j];
                j += 1;
                const v = try number(cx, t, &j, "a PARMS starting value");
                // `parms a=1 b=2;` (no comma) starts the next group; numbers,
                // TO or BY after a value form a grid.
                const next_group = at(t, j, .name) and !kw(t, j, "to") and !kw(t, j, "by");
                if (j < end and !at(t, j, .comma) and !next_group) return gap(cx, l, "PARMS grids of starting values are not implemented (STAT-NLMIXED-009)", .{});
                for (names) |tok| {
                    for (starts.items) |q| if (eq(q.name, tok.text)) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: parameter {s} is listed more than once in PARMS", .{tok.text});
                    if (ds.indexOf(tok.text) != null) return cx.diags.fail(error.ParseError, l, "PROC NLMIXED: PARMS name {s} is an input data set variable", .{tok.text});
                    try starts.append(a, .{ .name = tok.text, .start = v });
                    try symbols.add(a, tok.text);
                }
                if (j < end and !next_group) {
                    j += 1;
                    if (j == end) return invalid(cx, t, j);
                }
            }
        } else if (eq(word, "id")) {
            // p.7122: ID symbols only add quantities to PREDICT OUT=.
            if (end == i + 1) return invalid(cx, t, end);
            for (t[i + 1 .. end], i + 1..) |tok, j| {
                if (tok.tag != .name) return invalid(cx, t, j);
                try ids.append(a, tok.text);
            }
        } else if (oneOf(word, &later_statements)) {
            try later.append(a, try std.ascii.allocLowerString(a, word));
        } else if (oneOf(word, &programming_words)) {
            return gap(cx, l, "programming statement {s} is not implemented (STAT-NLMIXED-014)", .{word});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC NLMIXED: a MODEL statement is required", .{});
    s.program = program.items;
    s.randoms = randoms.items;
    s.bounds = bounds.items;
    s.ids = ids.items;
    s.gap_options = gaps.items;
    s.later = later.items;

    // Roles: a symbol is a data set variable, an assigned program variable, a
    // random effect, or else a parameter (p.7110).
    var params: std.ArrayList(Param) = .empty;
    var cols: std.ArrayList(usize) = .empty;
    symbol: for (symbols.names.items) |sym| {
        if (ds.indexOf(sym)) |c| {
            if (ds.columns.items[c].type != .num) return gap(cx, lineOf(t, 0), "character variable {s} in NLMIXED expressions is not implemented (STAT-NLMIXED-014)", .{sym});
            if (std.mem.indexOfScalar(usize, cols.items, c) == null) try cols.append(a, c);
            continue;
        }
        for (s.program) |p| if (eq(p.target, sym)) continue :symbol;
        for (s.randoms) |r| for (r.effects) |e| if (eq(e, sym)) continue :symbol;
        var start: f64 = 1;
        for (starts.items) |q| if (eq(q.name, sym)) {
            start = q.start;
        };
        try params.append(a, .{ .name = sym, .start = start });
    }
    s.params = params.items;
    s.data_cols = cols.items;
    for (s.randoms) |r| for (r.effects) |e| {
        if (ds.indexOf(e) != null) return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC NLMIXED: random effect {s} is an input data set variable", .{e});
        for (starts.items) |q| if (eq(q.name, e)) return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC NLMIXED: random effect {s} is also listed in PARMS", .{e});
        var used = false;
        for (symbols.names.items) |sym| used = used or eq(sym, e);
        if (!used) return gap(cx, lineOf(t, 0), "random effect {s} that no programming statement uses is not verified", .{e});
    };
    for (s.ids) |id| {
        var known = ds.indexOf(id) != null;
        for (s.program) |p| known = known or eq(p.target, id);
        for (s.params) |p| known = known or eq(p.name, id);
        if (!known) return gap(cx, lineOf(t, 0), "ID symbol {s} that the program does not define is not verified", .{id});
    }

    const pb = try bys.resolve(a, ds, cx.diags);
    const bcols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| bcols[k] = ds.indexOf(n).?;
    s.by_cols = bcols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Subject cluster counts of one RANDOM statement.
pub const Clusters = struct { subjects: usize, max_obs: usize };
/// Observation accounting of one BY group.
pub const Analysis = struct {
    total: usize,
    used: usize,
    clusters: []const Clusters,
};

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| !std.math.isFinite(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// Observation accounting. Subject clusters are the unique SUBJECT= values
/// (p.7112, SAS/STAT 13.1 onward; NOSORTSUB is a gap); a nested SUBJECT=b(a)
/// cluster is one combination of the containing values and b.
pub fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Analysis {
    const a = cx.arena;
    // An observation is not used when the response or a data set variable
    // the statements read is missing; a missing value in a variable the
    // model does not read does not matter (SAS 9.4 reference run of invented
    // data, tests/corpus/stat_nlmixed001_missing.sas).
    var used: std.ArrayList([]const Value) = .empty;
    rows: for (rows) |row| {
        if (missing(row[s.response])) continue;
        for (s.data_cols) |c| if (missing(row[c])) continue :rows;
        try used.append(a, row);
    }
    if (s.nosortsub and used.items.len != rows.len) return gap(cx, 0, "NOSORTSUB with observations that are not used is not verified", .{});
    const clusters = try a.alloc(Clusters, s.randoms.len);
    for (s.randoms, clusters) |r, *c| {
        c.* = try cluster(a, s, r, used.items);
        // ponytail: the reference runs do not separate counting subjects over
        // used versus all observations; where the two differ it is a gap.
        const all = try cluster(a, s, r, rows);
        if (all.subjects != c.subjects or all.max_obs != c.max_obs) return gap(cx, 0, "subjects that only have unused observations are not verified", .{});
    }
    return .{ .total = rows.len, .used = used.items.len, .clusters = clusters };
}

fn cluster(a: A, s: Spec, r: Random, rows: []const []const Value) !Clusters {
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    var max: usize = 0;
    var runs: usize = 0;
    var run_len: usize = 0;
    var previous: ?[]const u8 = null;
    for (rows) |row| {
        var key: Out = .empty;
        for (r.within) |w| {
            try key.appendSlice(a, try proc.cellText(a, row[w]));
            try key.append(a, 0);
        }
        try key.appendSlice(a, try proc.cellText(a, row[r.subject]));
        if (previous == null or !std.mem.eql(u8, previous.?, key.items)) {
            runs += 1;
            run_len = 0;
        }
        run_len += 1;
        previous = key.items;
        const slot = try counts.getOrPut(a, key.items);
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
        max = @max(max, if (s.nosortsub) run_len else slot.value_ptr.*);
    }
    return .{ .subjects = if (s.nosortsub) runs else counts.count(), .max_obs = max };
}

/// A missing SUBJECT= value stops the step (SAS 9.4 reference run): the
/// observation number is the one in the input data set.
pub fn checkSubjects(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    for (s.input.ds.rows.items, 0..) |row, k| for (s.randoms) |r| if (missing(row[r.subject])) {
        const obs = if (s.input.srcobs) |m| m[k] else k + 1;
        return cx.diags.fail(error.ParseError, 0, "SUBJECT= variable must be nonmissing in observation {d}.", .{obs});
    };
}

fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn joined(a: A, parts: []const []const u8) ![]const u8 {
    var o: Out = .empty;
    for (parts, 0..) |p, k| {
        if (k > 0) try o.appendSlice(a, ", ");
        try o.appendSlice(a, p);
    }
    return o.items;
}

/// "Specifications" (p.7162), in the layout of the reference listing: a
/// 44-column label field and a 20-column value field whose text wraps at
/// word boundaries. Only the default normal model with normal random effects
/// is verified.
pub fn renderSpecifications(cx: proc.ProcCtx, out: *Out, s: Spec) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.distribution != .normal) return gap(cx, 0, "the {s} distribution is not implemented (STAT-NLMIXED-003/006)", .{@tagName(s.distribution)});
    if (s.randoms.len == 0) return gap(cx, 0, "a model without RANDOM statements is not implemented (STAT-NLMIXED-002/010)", .{});
    if (s.randoms.len == 1) return gap(cx, 0, "the Specifications table for one RANDOM statement is not verified (STAT-NLMIXED-013)", .{});
    var effects: std.ArrayList([]const u8) = .empty;
    var dists: std.ArrayList([]const u8) = .empty;
    var subjects: std.ArrayList([]const u8) = .empty;
    for (s.randoms) |r| {
        try effects.appendSlice(a, r.effects);
        try dists.append(a, "Normal");
        try subjects.append(a, ds.columns.items[r.subject].name);
    }
    const lines = [_][2][]const u8{
        .{ "Data Set", s.data_name },
        .{ "Dependent Variable", ds.columns.items[s.response].name },
        .{ "Distribution for Dependent Variable", "Normal" },
        .{ "Random Effects", try joined(a, effects.items) },
        .{ "Distribution for Random Effects", try joined(a, dists.items) },
        .{ "Subject Variables", try joined(a, subjects.items) },
        .{ "Optimization Technique", "Dual Quasi-Newton" },
        .{ "Integration Method", "Adaptive Gaussian Quadrature" },
    };
    for (lines[0..7]) |l| if (l[1].len > 20) return gap(cx, 0, "a Specifications value longer than 20 characters is not verified", .{});
    try out.appendSlice(a, "\nThe NLMIXED Procedure\n\n                         Specifications\n\n");
    for (lines) |l| {
        try left(a, out, l[0], 44);
        // Word wrap at 20 columns (only the integration method needs it).
        var rest = l[1];
        var first = true;
        while (true) {
            if (!first) try out.appendNTimes(a, ' ', 44);
            first = false;
            if (rest.len <= 20) {
                try left(a, out, rest, 20);
                try out.append(a, '\n');
                break;
            }
            const cut = std.mem.lastIndexOfScalar(u8, rest[0..21], ' ') orelse 20;
            try left(a, out, rest[0..cut], 20);
            try out.append(a, '\n');
            rest = std.mem.trimStart(u8, rest[cut..], " ");
        }
    }
}

/// "Dimensions" (p.7162): counts right-aligned in a 40-column table. The
/// number of quadrature points comes from the adaptive selection of
/// STAT-NLMIXED-002 and is passed in.
pub fn renderDimensions(cx: proc.ProcCtx, out: *Out, s: Spec, an: Analysis, qpoints: usize) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    try out.appendSlice(a, "               Dimensions\n\n");
    var rows: std.ArrayList(struct { []const u8, usize }) = .empty;
    try rows.append(a, .{ "Observations Used", an.used });
    try rows.append(a, .{ "Observations Not Used", an.total - an.used });
    try rows.append(a, .{ "Total Observations", an.total });
    for (s.randoms, an.clusters) |r, c| {
        // One RANDOM statement: "Subjects"; several: "Subjects [var]".
        const label = if (s.randoms.len == 1) "Subjects" else try std.fmt.allocPrint(a, "Subjects [{s}]", .{ds.columns.items[r.subject].name});
        try rows.append(a, .{ label, c.subjects });
        try rows.append(a, .{ "Max Obs per Subject", c.max_obs });
    }
    try rows.append(a, .{ "Parameters", s.params.len });
    try rows.append(a, .{ "Quadrature Points", qpoints });
    for (rows.items) |row| {
        const n = try std.fmt.allocPrint(a, "{d}", .{row[1]});
        if (row[0].len + 1 + n.len > 40) return gap(cx, 0, "a Dimensions row wider than 40 columns is not verified", .{});
        try left(a, out, row[0], 40 - n.len);
        try out.appendSlice(a, n);
        try out.append(a, '\n');
    }
}

/// The per-group page header: the BY line then the procedure title, as the
/// reference listing prints it after the one Specifications table.
pub fn renderGroupHeader(cx: proc.ProcCtx, out: *Out, s: Spec, row: []const Value) diag.Error!void {
    const a = cx.arena;
    if (s.by_cols.len == 0) {
        try out.appendSlice(a, "\n\n");
        return;
    }
    // Flush left as in the NOCENTER reference listing (like PROC HPREG).
    for (s.by_cols, 0..) |c, k| {
        if (s.input.ds.columns.items[c].format != null) return gap(cx, 0, "formatted BY variables are not verified", .{});
        try out.print(a, "{s}{s}={s}", .{ if (k > 0) " " else "\n", s.input.ds.columns.items[c].name, try proc.cellText(a, row[c]) });
    }
    try out.appendSlice(a, "\n\nThe NLMIXED Procedure\n\n");
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    _ = out;
    const s = try parse(cx, t);
    const l0 = lineOf(t, 0);
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, l0, "graphs under ODS GRAPHICS are not implemented (STAT-NLMIXED-013)", .{});
    if (s.later.len > 0) return gap(cx, l0, "the {s} statement is not implemented (STAT-NLMIXED-004/005/011/012)", .{s.later[0]});
    if (s.gap_options.len > 0) return gap(cx, l0, "PROC statement option {s} is not implemented (STAT-NLMIXED-002/005/007/008/013)", .{s.gap_options[0]});
    const ds = s.input.ds;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0) return gap(cx, l0, "the result for an empty input data set is not verified", .{});
    // Validate the displayed tables before the estimation boundary so the
    // model shape is checked (they are not printed: nothing is shown for a
    // step that cannot finish).
    try checkSubjects(cx, s);
    var scratch: Out = .empty;
    try renderSpecifications(cx, &scratch, s);
    for (groups) |group| _ = try analyze(cx, s, group.rows);
    return gap(cx, l0, "marginal likelihood estimation (adaptive Gaussian quadrature, dual quasi-Newton) is not implemented (STAT-NLMIXED-002)", .{});
}

test {
    _ = @import("nlmixed_tests.zig");
}
