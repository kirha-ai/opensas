//! PROC ANOVA declarations, roles and execution boundary (STAT-ANOVA-001)
//! and the MEANS statement (STAT-ANOVA-007, physical pp.1123–1129).
//! S154 ch.29: PROC ANOVA statement (physical pp.1115–1117), BY (1117–1118),
//! FREQ (1119), Missing Values (1138–1139).
//!
//! CLASS / MODEL / Specification of Effects (STAT-ANOVA-003, physical
//! pp.1118–1119, 1129, 1135–1138): ANOVA reads its own effect grammar, REF=,
//! TRUNCATE, INT and NOUNI, and computes sums of squares from cell totals
//! (p.1128 rules), never from the GLM least-squares kernel.
//!
//! ponytail: dataset/CLASS/response/BY/FREQ resolution and row selection
//! are GLM's reader and builder. EFFECTSIZE reuses glm_effectsize.zig's
//! noncentral-F inversion; its degenerate displays stay loud gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const selection = @import("data_selection.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;

pub const Spec = glm.Spec;
pub const Design = glm.design.Design;

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn oneOf(text: []const u8, comptime names: anytype) bool {
    inline for (names) |name| if (eq(text, name)) return true;
    return false;
}

/// ANOVA's own grammar gate. Runs before the shared CLASS/MODEL reader so
/// that GLM-only syntax can never be accepted under PROC ANOVA.
fn check(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!void {
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        const line = t[i].line;
        if (kw(t, i, "data")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: DATA= requires a dataset", .{});
            i += 3;
            if (at(t, i, .dot)) i += 2;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (kw(t, i, "manova") or kw(t, i, "multipass") or kw(t, i, "noprint")) {
            i += 1;
        } else if (kw(t, i, "namelen")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .number)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN= requires an integer", .{});
            const n = std.fmt.parseInt(usize, t[i + 2].text, 10) catch return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN= requires an integer", .{});
            if (n < 20 or n > 200) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN must be 20 through 200", .{});
            i += 3;
        } else if (kw(t, i, "order")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name) or !oneOf(t[i + 2].text, .{ "data", "formatted", "freq", "internal" })) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: ORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
            i += 3;
        } else if (kw(t, i, "outstat")) {
            return proc.failGap(cx.diags, line, "PROC ANOVA: OUTSTAT= is not implemented", .{});
        } else if (kw(t, i, "plots")) {
            // p.1116: PLOTS <(MAXPOINTS=NONE | number)> <=NONE> is the whole grammar.
            if (at(t, i + 1, .eq)) {
                if (!kw(t, i + 2, "none")) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: PLOTS= accepts only NONE", .{});
            } else if (at(t, i + 1, .lparen)) {
                if (!kw(t, i + 2, "maxpoints") or !at(t, i + 3, .eq) or !(kw(t, i + 4, "none") or at(t, i + 4, .number)) or !at(t, i + 5, .rparen)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: PLOTS accepts only the MAXPOINTS=NONE | number option", .{});
                return proc.failGap(cx.diags, line, "PROC ANOVA: PLOTS(MAXPOINTS=) is not implemented", .{});
            } else return proc.failGap(cx.diags, line, "PROC ANOVA: PLOTS without =NONE is not implemented", .{});
            i += 3;
        } else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid PROC statement option {s}", .{t[i].text});
    }
    if (!at(t, i, .semicolon)) return cx.diags.fail(error.ParseError, 0, "PROC ANOVA: expected semicolon", .{});
    i += 1;
    var ended = false;
    var model_seen = false;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        const line = t[i].line;
        const word = t[i].text;
        if (!at(t, i, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement", .{});
        if (oneOf(word, .{ "run", "quit" })) {
            ended = true;
        } else if (oneOf(word, .{ "weight", "id", "lsmeans", "contrast", "estimate", "random", "output", "store", "code" })) {
            return cx.diags.fail(error.ParseError, line, "PROC ANOVA: the {s} statement is not valid in PROC ANOVA", .{word});
        } else if (ended) {
            // pp.1117–1119: ABSORB/BY/FREQ after the first RUN are ignored.
            if (oneOf(word, .{ "by", "freq", "absorb" })) {} else if (oneOf(word, .{ "class", "model" })) {
                return cx.diags.fail(error.ParseError, line, "PROC ANOVA: {s} cannot be declared after the first RUN", .{word});
            } else if (eq(word, "means")) {
                // Interactive MEANS uses the retained fit (STAT-ANOVA-007).
            } else if (oneOf(word, .{ "manova", "test", "repeated" })) {
                return proc.failGap(cx.diags, line, "PROC ANOVA: interactive {s} is not implemented", .{word});
            } else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement {s}", .{word});
        } else if (eq(word, "means")) {
            // Parsed by readMeans once CLASS/MODEL are resolved.
        } else if (oneOf(word, .{ "absorb", "manova", "repeated", "test" })) {
            return proc.failGap(cx.diags, line, "PROC ANOVA: the {s} statement is not implemented", .{word});
        } else if (eq(word, "class")) {
            if (model_seen) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: CLASS must precede MODEL", .{});
        } else if (eq(word, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: only one MODEL statement is allowed", .{});
            model_seen = true;
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) j += 1;
            j += 1;
            // p.1129: the whole MODEL option grammar (SAS 9.4 wording for others).
            while (j < end) : (j += 1) {
                if (at(t, j, .name) and oneOf(t[j].text, .{ "int", "intercept", "nouni" })) continue;
                if (kw(t, j, "effectsize")) continue;
                return cx.diags.fail(error.ParseError, t[j].line, "Syntax error, expecting one of the following: ;, EFFECTSIZE, INTERCEPT, NOUNI.", .{});
            }
        } else if (eq(word, "freq")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: FREQ requires exactly one variable", .{});
        } else if (!oneOf(word, .{ "by", "where", "format", "label", "attrib" })) {
            return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement {s}", .{word});
        }
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC ANOVA: a MODEL statement is required", .{});
}

/// One MEANS effect (S154 physical pp.1123–1129).
pub const MeansRequest = struct { effect: usize, tukey: bool = false, alpha: f64 = 0.05, line: usize = 0 };
pub const Parsed = struct { spec: Spec, means: []const MeansRequest, options: Options = .{} };

/// CLASS options (pp.1118–1119) and MODEL options (p.1129) that the shared
/// GLM reader does not carry. `refs` is indexed like `spec.classes`.
pub const Options = struct {
    intercept: bool = false,
    effectsize: bool = false,
    nouni: bool = false,
    truncate: bool = false,
    refs: []const ?Reference = &.{},
};
pub const Reference = @import("class_levels.zig").Reference;
const NamedRef = struct { name: []const u8, ref: Reference };

/// `s` is one CLASS statement without its semicolon. Returns its variable
/// tokens; REF= and global options are recorded.
fn readClass(cx: proc.ProcCtx, s: []const lex.Token, refs: *std.ArrayList(NamedRef), global: *?Reference, truncate: *bool) diag.Error![]const lex.Token {
    var names: std.ArrayList(lex.Token) = .empty;
    const line = s[0].line;
    var i: usize = 1;
    while (i < s.len and !at(s, i, .slash)) {
        if (!at(s, i, .name)) return cx.diags.fail(error.ParseError, s[i].line, "PROC ANOVA: invalid CLASS statement", .{});
        try names.append(cx.arena, s[i]);
        i += 1;
        if (at(s, i, .lparen)) {
            if (!kw(s, i + 1, "ref") or !at(s, i + 2, .eq) or !at(s, i + 4, .rparen)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: CLASS variable options are (REF='level' | FIRST | LAST)", .{});
            const value = s[i + 3];
            const ref: Reference = if (value.tag == .string) .{ .label = value.text } else if (value.tag == .name and eq(value.text, "first")) .first else if (value.tag == .name and eq(value.text, "last")) .last else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: CLASS REF= requires a quoted level, FIRST or LAST", .{});
            try refs.append(cx.arena, .{ .name = s[i - 1].text, .ref = ref });
            i += 5;
        }
    }
    if (at(s, i, .slash)) {
        i += 1;
        while (i < s.len) {
            if (kw(s, i, "truncate")) {
                truncate.* = true;
                i += 1;
            } else if (kw(s, i, "ref") and at(s, i + 1, .eq) and (kw(s, i + 2, "first") or kw(s, i + 2, "last"))) {
                global.* = if (kw(s, i + 2, "first")) .first else .last;
                i += 3;
            } else return cx.diags.fail(error.ParseError, s[i].line, "PROC ANOVA: CLASS global options are REF=FIRST | LAST and TRUNCATE", .{});
        }
    }
    return names.items;
}

/// One written effect term of S154 pp.1123–1126: crossed CLASS variables
/// and an optional nesting list. Columns are kept in CLASS order.
const Term = struct { crossed: []const usize, nested: []const usize };

fn classPosition(classes: []const usize, ci: usize) usize {
    return std.mem.indexOfScalar(usize, classes, ci) orelse classes.len;
}
fn sortedUnique(a: A, classes: []const usize, items: []const usize) ![]const usize {
    var list: std.ArrayList(usize) = .empty;
    for (items) |ci| if (std.mem.indexOfScalar(usize, list.items, ci) == null) try list.append(a, ci);
    std.mem.sort(usize, list.items, classes, struct {
        fn less(c: []const usize, x: usize, y: usize) bool {
            return classPosition(c, x) < classPosition(c, y);
        }
    }.less);
    return list.items;
}

/// SAS 9.4 messages (live probe): a non-CLASS variable in an effect and in a
/// nesting list.
fn effectVariable(cx: proc.ProcCtx, spec: Spec, t: []const lex.Token, i: *usize, inside: bool) diag.Error!usize {
    if (!at(t, i.*, .name)) return cx.diags.fail(error.ParseError, if (i.* < t.len) t[i.*].line else 0, "PROC ANOVA: invalid effect specification", .{});
    const token = t[i.*];
    i.* += 1;
    const ci = spec.input.ds.indexOf(token.text) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{token.text});
    if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) {
        if (inside) return cx.diags.fail(error.ParseError, token.line, "Nesting of continuous variable not allowed.", .{});
        return cx.diags.fail(error.ParseError, token.line, "No continuous effects allowed in PROC ANOVA.", .{});
    }
    return ci;
}

fn readTerm(cx: proc.ProcCtx, spec: Spec, t: []const lex.Token, i: *usize) diag.Error!Term {
    var crossed: std.ArrayList(usize) = .empty;
    try crossed.append(cx.arena, try effectVariable(cx, spec, t, i, false));
    while (at(t, i.*, .star)) {
        i.* += 1;
        try crossed.append(cx.arena, try effectVariable(cx, spec, t, i, false));
    }
    var nested: std.ArrayList(usize) = .empty;
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        while (i.* < t.len and !at(t, i.*, .rparen)) try nested.append(cx.arena, try effectVariable(cx, spec, t, i, true));
        if (nested.items.len == 0 or !at(t, i.*, .rparen)) return cx.diags.fail(error.ParseError, if (i.* < t.len) t[i.*].line else 0, "PROC ANOVA: invalid nested effect", .{});
        i.* += 1;
    }
    return .{ .crossed = try sortedUnique(cx.arena, spec.classes, crossed.items), .nested = try sortedUnique(cx.arena, spec.classes, nested.items) };
}

fn termName(a: A, ds: anytype, term: Term) ![]const u8 {
    var name: std.ArrayList(u8) = .empty;
    for (term.crossed, 0..) |ci, k| {
        if (k > 0) try name.append(a, '*');
        try name.appendSlice(a, ds.columns.items[ci].name);
    }
    if (term.nested.len > 0) {
        try name.append(a, '(');
        for (term.nested, 0..) |ci, k| {
            if (k > 0) try name.append(a, ' ');
            try name.appendSlice(a, ds.columns.items[ci].name);
        }
        try name.append(a, ')');
    }
    return name.items;
}

/// MODEL effects (pp.1123–1126): main, crossed (A*B), nested (B(A),
/// C*D(A B)), bar (A|B|C) and @n. Bar terms expand left to right as binary
/// subsets (A B A*B C ...); nesting lists merge, a combination with a
/// variable both crossed and nested is dropped, and @n bounds the number of
/// variables including nesting ones (A | B(A) | C@2 = A B(A) C A*C). SAS 9.4
/// reference: a repeated effect (A A, A*A) is kept once; A(A) is accepted.
fn readEffects(cx: proc.ProcCtx, spec: Spec, t: []const lex.Token) diag.Error![]const glm.parsing.Effect {
    const a = cx.arena;
    var out: std.ArrayList(glm.parsing.Effect) = .empty;
    var terms: std.ArrayList(Term) = .empty;
    var i: usize = 0;
    while (i < t.len) {
        var chain: std.ArrayList(Term) = .empty;
        try chain.append(a, try readTerm(cx, spec, t, &i));
        while (at(t, i, .pipe)) {
            i += 1;
            try chain.append(a, try readTerm(cx, spec, t, &i));
        }
        var degree: usize = std.math.maxInt(usize);
        if (at(t, i, .at)) {
            if (chain.items.len < 2 or !at(t, i + 1, .number)) return cx.diags.fail(error.ParseError, t[i].line, "PROC ANOVA: @ requires a bar effect and a positive integer", .{});
            degree = std.fmt.parseInt(usize, t[i + 1].text, 10) catch return cx.diags.fail(error.ParseError, t[i].line, "PROC ANOVA: invalid @ degree", .{});
            if (degree == 0) return cx.diags.fail(error.ParseError, t[i].line, "PROC ANOVA: @ degree must be positive", .{});
            i += 2;
        }
        if (chain.items.len > 16) return proc.failGap(cx.diags, t[0].line, "PROC ANOVA: bar expansion beyond sixteen terms is not implemented", .{});
        if (chain.items.len == 1) {
            try terms.append(a, chain.items[0]);
            continue;
        }
        const end = @as(usize, 1) << @as(u5, @intCast(chain.items.len));
        for (1..end) |mask| {
            var crossed: std.ArrayList(usize) = .empty;
            var nested: std.ArrayList(usize) = .empty;
            for (chain.items, 0..) |term, k| if (mask & (@as(usize, 1) << @as(u5, @intCast(k))) != 0) {
                try crossed.appendSlice(a, term.crossed);
                try nested.appendSlice(a, term.nested);
            };
            const c = try sortedUnique(a, spec.classes, crossed.items);
            const n = try sortedUnique(a, spec.classes, nested.items);
            if (c.len + n.len > degree) continue;
            if (@popCount(mask) > 1) {
                var overlap = false;
                for (n) |ci| if (std.mem.indexOfScalar(usize, c, ci) != null) {
                    overlap = true;
                };
                if (overlap) continue;
            }
            try terms.append(a, .{ .crossed = c, .nested = n });
        }
    }
    for (terms.items) |term| {
        const full = try termName(a, spec.input.ds, term);
        // NAMELEN= (p.1115): a main effect name is cut; other shapes are
        // shortened (or gapped) by effectLabel.
        const name = if (term.crossed.len == 1 and term.nested.len == 0) full[0..@min(full.len, spec.namelen)] else full;
        var all: std.ArrayList(usize) = .empty;
        try all.appendSlice(a, term.crossed);
        try all.appendSlice(a, term.nested);
        const variables = try sortedUnique(a, spec.classes, all.items);
        var duplicate = false;
        for (out.items) |e| {
            if (std.mem.eql(u8, e.name, name)) duplicate = true else if (std.mem.eql(usize, e.variables, variables))
                return proc.failGap(cx.diags, t[0].line, "PROC ANOVA: effects {s} and {s} over the same variables are not implemented", .{ e.name, name });
        }
        if (!duplicate) try out.append(a, .{ .name = name, .variables = variables });
    }
    return out.items;
}

const comparison_options = .{ "bon", "cldiff", "clm", "duncan", "dunnett", "dunnettl", "dunnettu", "e", "etype", "gabriel", "gt2", "hovtest", "htype", "kratio", "lines", "linestable", "lsd", "nosort", "regwq", "scheffe", "sidak", "smm", "snk", "t", "waller", "welch" };

/// `s` is one MEANS statement without its semicolon.
fn readMeans(cx: proc.ProcCtx, s: []const lex.Token, spec: Spec, requests: *std.ArrayList(MeansRequest)) diag.Error!void {
    const line = s[0].line;
    const first = requests.items.len;
    var i: usize = 1;
    while (i < s.len and s[i].tag != .slash) : (i += 1) {
        if (s[i].tag != .name) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS requires CLASS effects", .{});
        const column = spec.input.ds.indexOf(s[i].text) orelse return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS variable {s} not found", .{s[i].text});
        if (std.mem.indexOfScalar(usize, spec.classes, column) == null) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS effect {s} must be a CLASS variable", .{s[i].text});
        if (at(s, i + 1, .star) or at(s, i + 1, .lparen)) return proc.failGap(cx.diags, line, "PROC ANOVA: crossed or nested MEANS effects are not implemented", .{});
        const effect = for (spec.effects, 0..) |effect, index| {
            if (effect.variables.len == 1 and effect.variables[0] == column) break index;
        } else return proc.failGap(cx.diags, line, "PROC ANOVA: MEANS for effect {s} that is not a main effect of the MODEL is not implemented", .{s[i].text});
        try requests.append(cx.arena, .{ .effect = effect, .line = line });
    }
    if (requests.items.len == first) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS requires an effect", .{});
    var tukey = false;
    var alpha: f64 = 0.05;
    i += 1;
    while (i < s.len) : (i += 1) {
        const word = s[i].text;
        if (s[i].tag != .name) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid MEANS option {s}", .{word});
        if (eq(word, "tukey")) {
            tukey = true;
        } else if (eq(word, "alpha")) {
            if (!at(s, i + 1, .eq) or !at(s, i + 2, .number)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS ALPHA= requires a number", .{});
            alpha = std.fmt.parseFloat(f64, s[i + 2].text) catch return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS ALPHA= requires a number", .{});
            // p.1124: ALPHA= is a probability between 0.0001 and 0.9999.
            if (!(alpha >= 0.0001 and alpha <= 0.9999)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: MEANS ALPHA= must be between 0.0001 and 0.9999", .{});
            i += 2;
        } else if (oneOf(word, comparison_options)) {
            return proc.failGap(cx.diags, line, "PROC ANOVA: MEANS option {s} is not implemented", .{word});
        } else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: unknown MEANS option {s}", .{word});
    }
    for (requests.items[first..]) |*request| {
        request.tukey = tukey;
        request.alpha = alpha;
    }
}

pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!Spec {
    return (try parseAll(cx, tokens)).spec;
}

pub fn parseAll(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!Parsed {
    try check(cx, tokens);
    // The shared CLASS/MODEL reader never sees MEANS: ANOVA owns that grammar.
    var rest: std.ArrayList(lex.Token) = .empty;
    var statements: std.ArrayList([]const lex.Token) = .empty;
    var class_end: ?usize = null; // index of the first CLASS statement's semicolon in `rest`
    var options: Options = .{};
    var refs: std.ArrayList(NamedRef) = .empty;
    var global_ref: ?Reference = null;
    var effect_tokens: []const lex.Token = &.{};
    var response_tokens: []const lex.Token = &.{};
    var i: usize = 0;
    while (i < tokens.len) {
        var end = i;
        while (end < tokens.len and tokens[end].tag != .semicolon and tokens[end].tag != .eof) end += 1;
        if (kw(tokens, i, "means") and i > 0) {
            try statements.append(cx.arena, tokens[i..end]);
        } else if (i == 0) {
            // SAS reference: a repeated DATA= is ignored with a WARNING and
            // the first one is used.
            var data_seen = false;
            var j: usize = 0;
            while (j < @min(tokens.len, end + 1)) {
                if (j >= 2 and kw(tokens, j, "data") and at(tokens, j + 1, .eq)) {
                    if (data_seen) {
                        try cx.diags.report(.warning, tokens[j].line, "Ignoring second data set reference.", .{});
                        j += 3;
                        if (at(tokens, j, .dot)) j += 2;
                        if (at(tokens, j, .lparen)) j = proc.skipParen(tokens, j);
                        continue;
                    }
                    data_seen = true;
                }
                try rest.append(cx.arena, tokens[j]);
                j += 1;
            }
        } else if (kw(tokens, i, "class")) {
            const names = try readClass(cx, tokens[i..end], &refs, &global_ref, &options.truncate);
            if (class_end) |*position| {
                // SAS reference: a second CLASS statement adds its variables
                // to the first; the shared reader takes one CLASS statement.
                try rest.insertSlice(cx.arena, position.*, names);
                position.* += names.len;
            } else {
                try rest.append(cx.arena, tokens[i]);
                try rest.appendSlice(cx.arena, names);
                class_end = rest.items.len;
                try rest.append(cx.arena, tokens[end]);
            }
        } else if (kw(tokens, i, "model")) {
            // The shared reader resolves the responses only; ANOVA reads its
            // own effect grammar and options (pp.1123–1129).
            var equal = i + 1;
            while (equal < end and !at(tokens, equal, .eq)) equal += 1;
            var slash = equal;
            while (slash < end and !at(tokens, slash, .slash)) slash += 1;
            if (equal < end) effect_tokens = tokens[equal + 1 .. slash];
            response_tokens = tokens[i + 1 .. equal];
            for (tokens[@min(slash + 1, end)..end]) |option| {
                if (oneOf(option.text, .{ "int", "intercept" })) options.intercept = true;
                if (eq(option.text, "nouni")) options.nouni = true;
                if (eq(option.text, "effectsize")) options.effectsize = true;
            }
            try rest.appendSlice(cx.arena, tokens[i..@min(end, equal + 1)]);
            try rest.append(cx.arena, tokens[end]);
        } else {
            try rest.appendSlice(cx.arena, tokens[i..@min(tokens.len, end + 1)]);
        }
        i = end + 1;
    }
    const mark = cx.diags.list.items.len;
    var spec = glm.parse(cx, rest.items) catch |err| {
        // SAS 9.4 wording for a character dependent variable (live probe).
        for (cx.diags.list.items[mark..]) |*item| for (response_tokens) |token| {
            const wording = std.fmt.allocPrint(cx.arena, "PROC GLM: variable {s} must be numeric", .{token.text}) catch return error.OutOfMemory;
            if (std.ascii.eqlIgnoreCase(item.message, wording)) item.message = std.fmt.allocPrint(cx.diags.arena, "Variable {s} in list does not match type prescribed for this list.", .{token.text}) catch return error.OutOfMemory;
        };
        return relabel(cx, mark, err);
    };
    // ANOVA prints one "Anova SS" table; never ask the kernel for Type II–IV.
    spec.ss1 = true;
    spec.effects = try readEffects(cx, spec, effect_tokens);
    const resolved = try cx.arena.alloc(?Reference, spec.classes.len);
    @memset(resolved, global_ref);
    for (refs.items) |named| {
        const ci = spec.input.ds.indexOf(named.name) orelse continue;
        resolved[std.mem.indexOfScalar(usize, spec.classes, ci) orelse continue] = named.ref;
    }
    options.refs = resolved;
    var requests: std.ArrayList(MeansRequest) = .empty;
    for (statements.items) |statement| try readMeans(cx, statement, spec, &requests);
    return .{ .spec = spec, .means = requests.items, .options = options };
}

/// Missing-value rule (pp.1138–1139): one response uses rows complete for
/// that response and every independent variable; the MANOVA option makes
/// GLM's builder require every response. FREQ <1 or missing drops the row,
/// fractional FREQ is truncated (p.1119).
pub fn build(cx: proc.ProcCtx, spec: Spec, group: selection.View, response: usize) diag.Error!Design {
    return buildWith(cx, spec, .{}, group, response);
}

/// Row selection and CLASS levels come from the shared GLM builder, given
/// one main effect per model variable (ANOVA never uses its X columns: the
/// sums of squares are computed from cell totals, see `ssTable`). TRUNCATE and
/// REF= then reshape the levels (pp.1118–1119).
pub fn buildWith(cx: proc.ProcCtx, spec: Spec, options: Options, group: selection.View, response: usize) diag.Error!Design {
    const a = cx.arena;
    var mains: std.ArrayList(glm.parsing.Effect) = .empty;
    var seen: std.ArrayList(usize) = .empty;
    for (spec.effects) |effect| for (effect.variables) |ci| if (std.mem.indexOfScalar(usize, seen.items, ci) == null) {
        try seen.append(a, ci);
        const one = try a.alloc(usize, 1);
        one[0] = ci;
        try mains.append(a, .{ .name = spec.input.ds.columns.items[ci].name, .variables = one });
    };
    var plain = spec;
    plain.effects = mains.items;
    var d = try glm.design.build(cx, plain, group, response);
    const rows = try a.alloc([]const @import("../value.zig").Value, d.n);
    for (rows, d.observations[0..d.n]) |*r, o| r.* = o.cells;
    d.classes = try adjustClasses(cx, spec, options, d.classes, rows, d.frequencies[0..d.n]);
    return d;
}

/// TRUNCATE: levels from the first 16 formatted characters (p.1119, SAS
/// reference `abcdefghijklmnop`). REF=: the reference level moves to the
/// end of the level list (p.1118; SAS reference listings show the moved
/// level last in Class Level Information and in MEANS tables).
fn adjustClasses(cx: proc.ProcCtx, spec: Spec, options: Options, classes: []const glm.design.Class, rows: []const []const @import("../value.zig").Value, counts: []const f64) diag.Error![]const glm.design.Class {
    const a = cx.arena;
    const out = try a.dupe(glm.design.Class, classes);
    for (out, 0..) |*class, k| {
        if (options.truncate) {
            const formed = try @import("class_levels.zig").build(a, spec.input.ds, rows, class.column, .{ .order = spec.order, .frequencies = counts, .missing = .exclude, .truncate = true });
            class.* = .{ .column = class.column, .levels = formed.levels, .row_levels = formed.row_to_level };
        }
        const ref = (if (k < options.refs.len) options.refs[k] else null) orelse continue;
        const len = class.levels.len;
        if (len == 0) continue;
        const name = spec.input.ds.columns.items[class.column].name;
        const r: usize = switch (ref) {
            .first => 0,
            .last => len - 1,
            .label => |text| for (class.levels, 0..) |level, index| {
                if (std.mem.eql(u8, std.mem.trim(u8, level.label, " "), std.mem.trim(u8, text, " "))) break index;
            } else return cx.diags.fail(error.ExecError, 0, "Invalid reference value for {s}.", .{name}),
        };
        if (r == len - 1) continue;
        const levels = try a.alloc(glm.design.Level, len);
        const map = try a.alloc(usize, len);
        var next: usize = 0;
        for (class.levels, 0..) |level, index| if (index != r) {
            levels[next] = level;
            map[index] = next;
            next += 1;
        };
        levels[len - 1] = class.levels[r];
        map[r] = len - 1;
        const row_levels = try a.alloc(?usize, class.row_levels.len);
        for (class.row_levels, row_levels) |old, *new| new.* = if (old) |o| map[o] else null;
        class.* = .{ .column = class.column, .levels = levels, .row_levels = row_levels };
    }
    return out;
}

/// The ANOVA computational method (S154 p.1128): each effect's SS is the
/// sum over its cells (all its variables, nesting ones included) of
/// total^2/frequency minus the correction term, less the SS of every model
/// effect whose variables are a proper subset; DF likewise from the number
/// of nonempty cells. This makes the result independent of effect order and
/// pools an omitted effect into the containing one (p.1125: `A B(A)` equals
/// `A A*B`). The Model SS is the sum of the effect SS, capped at the
/// corrected total, and Error SS is the remainder: SAS 9.4 reference runs
/// show exactly this on unbalanced and incomplete-block data (Model =
/// Corrected Total, Error 0), and a negative effect SS displayed as 0.
pub const Row = struct { df: f64, ss: f64 };
pub const Table = struct {
    effects: []const Row,
    model_df: f64,
    model_ss: f64,
    error_df: f64,
    sse: f64,
    total: f64,
    n: f64,
    mean: f64,
    cf: f64,
    uss: f64,
    /// Some effect has cells of different frequencies (p.1107 balance test).
    unequal: bool,
};

pub fn ssTable(cx: proc.ProcCtx, spec: Spec, d: Design) diag.Error!Table {
    const a = cx.arena;
    var n: f64 = 0;
    var sum: f64 = 0;
    var uss: f64 = 0;
    for (d.y[0..d.n], d.frequencies[0..d.n]) |y, f| {
        n += f;
        sum += f * y;
        uss += f * y * y;
    }
    const cf = sum * sum / n;
    const total = @max(0, uss - cf);
    const rows = try a.alloc(Row, spec.effects.len);
    const order = try a.alloc(usize, spec.effects.len);
    for (order, 0..) |*o, k| o.* = k;
    std.mem.sort(usize, order, spec.effects, struct {
        fn less(e: []const glm.parsing.Effect, x: usize, y: usize) bool {
            return e[x].variables.len < e[y].variables.len;
        }
    }.less);
    var unequal = false;
    for (order) |e| {
        const effect = spec.effects[e];
        const positions = try a.alloc(usize, effect.variables.len);
        var cells_total: u64 = 1;
        for (effect.variables, positions) |ci, *pos| {
            pos.* = for (d.classes, 0..) |class, k| {
                if (class.column == ci) break k;
            } else return error.ExecError;
            cells_total = std.math.mul(u64, cells_total, d.classes[pos.*].levels.len) catch return proc.failGap(cx.diags, 0, "PROC ANOVA: effect {s} has too many cells", .{effect.name});
        }
        var cells: std.AutoHashMapUnmanaged(u64, [2]f64) = .empty;
        for (0..d.n) |i| {
            var key: u64 = 0;
            for (positions) |pos| key = key * d.classes[pos].levels.len + (d.classes[pos].row_levels[i] orelse return error.ExecError);
            const entry = try cells.getOrPut(a, key);
            if (!entry.found_existing) entry.value_ptr.* = .{ 0, 0 };
            entry.value_ptr[0] += d.frequencies[i] * d.y[i];
            entry.value_ptr[1] += d.frequencies[i];
        }
        var raw: f64 = 0;
        var first: ?f64 = null;
        var it = cells.valueIterator();
        while (it.next()) |cell| {
            raw += cell[0] * cell[0] / cell[1];
            if (first) |f| {
                if (f != cell[1]) unequal = true;
            } else first = cell[1];
        }
        var ss = raw - cf;
        var df: f64 = @as(f64, @floatFromInt(cells.count())) - 1;
        for (spec.effects, 0..) |other, o| {
            if (other.variables.len >= effect.variables.len) continue;
            const contained = for (other.variables) |ci| {
                if (std.mem.indexOfScalar(usize, effect.variables, ci) == null) break false;
            } else true;
            if (!contained) continue;
            ss -= rows[o].ss;
            df -= rows[o].df;
        }
        // SAS 9.4 reference: a one-level effect has DF 0 and prints `.` tests.
        if (df < 0) return proc.failGap(cx.diags, 0, "PROC ANOVA: effect {s} with negative degrees of freedom is not implemented", .{effect.name});
        rows[e] = .{ .df = df, .ss = ss };
    }
    var model_df: f64 = 0;
    var model_ss: f64 = 0;
    for (rows) |row| {
        model_df += row.df;
        model_ss += row.ss;
    }
    // Rounding noise of a balanced design must not leave a tiny negative SS.
    model_ss = std.math.clamp(model_ss, 0, total);
    const error_df = n - 1 - model_df;
    if (error_df < 0) return proc.failGap(cx.diags, 0, "PROC ANOVA: models with more effect degrees of freedom than observations are not implemented", .{});
    return .{ .effects = rows, .model_df = model_df, .model_ss = model_ss, .error_df = error_df, .sse = total - model_ss, .total = total, .n = n, .mean = sum / n, .cf = cf, .uss = uss, .unequal = unequal };
}

/// `decimals` sentinel: BEST12. (E notation for tiny sums of squares).
const e_notation: usize = 99;
fn number(a: A, value: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(value)) return ".";
    if (decimals == e_notation) return @import("../format.zig").apply(a, .{ .num = value }, "best12.");
    return @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals}));
}
fn compact(a: A, value: f64, decimals: usize) ![]const u8 {
    return std.mem.trim(u8, try number(a, value, decimals), " ");
}
fn probability(a: A, value: f64) ![]const u8 {
    return if (std.math.isFinite(value) and value < 0.0001) "<.0001" else number(a, value, 4);
}
fn places(maximum: f64, digits: i32) usize {
    if (!(maximum > 0) or !std.math.isFinite(maximum)) return @intCast(digits);
    const exponent: i32 = @intFromFloat(@floor(@log10(maximum)));
    return @intCast(@max(0, @min(12, digits - exponent)));
}
fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, group: selection.View) !void {
    if (cx.listing_titles) |titles| {
        try titles.emitTitles(cx.arena, out);
    } else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    if (spec.by.len > 0 and group.observations.len > 0) {
        try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.observations[0].cells, spec.by);
        if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(cx.arena, '\n');
    }
    try out.appendSlice(cx.arena, "\nThe ANOVA Procedure\n");
}

pub const TukeyInfo = struct { alpha: f64, df_error: f64, mse: f64, critical: f64, msd: f64 };

/// Tukey HSD for k means of equal size n (S154 ch.53 "Multiple Comparisons"):
/// MSD = q(alpha; k, dfe) * sqrt(MSE / n).
pub fn tukeyInfo(alpha: f64, k: usize, df_error: f64, mse: f64, n: f64) error{InvalidArgument}!TukeyInfo {
    if (!(n >= 1) or !(mse >= 0)) return error.InvalidArgument;
    const q = try @import("studentized_range.zig").critical(alpha, k, df_error);
    return .{ .alpha = alpha, .df_error = df_error, .mse = mse, .critical = q, .msd = q * @sqrt(mse / n) };
}

/// LINES grouping: `descending` are the means sorted high to low. Bit g of
/// result[i] is set when mean i belongs to group g (0 = "A"). A group is a
/// maximal run of means whose range does not exceed `msd`. p.1126: a mean
/// in more than 24 groups is an error.
pub fn tukeyGroups(a: A, descending: []const f64, msd: f64) ![]u32 {
    const letters = try a.alloc(u32, descending.len);
    @memset(letters, 0);
    var group: u5 = 0;
    var covered: ?usize = null;
    for (descending, 0..) |top, i| {
        var j = i;
        while (j + 1 < descending.len and top - descending[j + 1] <= msd) j += 1;
        if (covered) |c| if (j <= c) continue;
        if (group >= 24) return error.TooManyGroups;
        for (letters[i .. j + 1]) |*mask| mask.* |= @as(u32, 1) << group;
        group += 1;
        covered = j;
    }
    return letters;
}

/// Information table of the Tukey page. Not reached from the CLI yet: the
/// LINES display that must follow it is a loud gap (see execute).
pub fn renderTukeyInfo(a: A, out: *std.ArrayList(u8), response: []const u8, info: TukeyInfo) !void {
    try out.print(a, "\nTukey's Studentized Range (HSD) Test for {s}\n\nNOTE: This test controls the Type I experimentwise error rate, but it generally has a higher Type II error rate than REGWQ.\n\n", .{response});
    try out.print(a, "Alpha {d}\nError Degrees of Freedom {d}\nError Mean Square {s}\nCritical Value of Studentized Range {s}\nMinimum Significant Difference {s}\n", .{
        info.alpha, info.df_error, try compact(a, info.mse, places(info.mse, 6)), try compact(a, info.critical, 5), try compact(a, info.msd, places(info.msd, 4)),
    });
}

/// "Level of <effect> N" table: one Mean/Std Dev pair per dependent variable.
fn renderMeans(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, group: selection.View, designs: []const Design, request: MeansRequest) diag.Error!void {
    const a = cx.arena;
    const glm_means = @import("glm_means.zig");
    const tables = try a.alloc(glm_means.Table, designs.len);
    for (tables, designs) |*table, d| table.* = try glm_means.compute(cx, spec, d, .{ .effect = request.effect, .deponly = true });
    const d = designs[0];
    const class = d.classes[tables[0].class_positions[0]];
    try heading(cx, out, spec, group);
    try out.appendSlice(a, "\nLevel of");
    for (designs) |design| {
        // 29-column spanner with the name centred; an odd remainder puts
        // the extra dash on the left (SAS reference: 14 + "y1" + 13).
        // ponytail: names of 29+ characters are not SAS-verified.
        const name = spec.input.ds.columns.items[design.response].name;
        const dashes = if (name.len < 29) 29 - name.len else 2;
        try out.append(a, ' ');
        try out.appendNTimes(a, '-', dashes - dashes / 2);
        try out.appendSlice(a, name);
        try out.appendNTimes(a, '-', dashes / 2);
    }
    try out.print(a, "\n{s} N", .{spec.input.ds.columns.items[class.column].name});
    for (designs) |_| try out.appendSlice(a, " Mean Std Dev");
    try out.appendSlice(a, "\n\n");
    const mean_places = try a.alloc(usize, designs.len);
    const sd_places = try a.alloc(usize, designs.len);
    for (tables, mean_places, sd_places) |table, *mp, *sp| {
        var mean_max: f64 = 0;
        var sd_max: f64 = 0;
        for (table.groups) |g| {
            mean_max = @max(mean_max, @abs(g.means[0]));
            if (std.math.isFinite(g.standard_deviations[0])) sd_max = @max(sd_max, g.standard_deviations[0]);
        }
        mp.* = places(mean_max, 8);
        sp.* = places(sd_max, 8);
    }
    for (tables[0].groups, 0..) |g, row| {
        try out.print(a, "{s} {d}", .{ class.levels[g.levels[0]].label, g.count });
        for (tables, mean_places, sd_places) |table, mp, sp| {
            // Same rows are used for every response (checked in execute).
            const other = table.groups[row];
            try out.print(a, " {s} {s}", .{ try compact(a, other.means[0], mp), try compact(a, other.standard_deviations[0], sp) });
        }
        try out.append(a, '\n');
    }
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec) diag.Error!void {
    return executeAll(cx, out, .{ .spec = spec, .means = &.{} }, false);
}

/// Set by executeAll when the dependent variables of some BY group have
/// different missing-value patterns: p.1139 disables interactivity then.
var patterns_differ = false;

/// Class Level Information when the dependent-variable groups differ
/// (pp.1138–1139): levels come from every observation usable for the
/// independent variables, not from one response's rows (SAS reference: a
/// level absent for one response is still listed).
fn classInfo(cx: proc.ProcCtx, spec: Spec, options: Options, group: selection.View) diag.Error![]const glm.design.Class {
    const a = cx.arena;
    var required: std.ArrayList(usize) = .empty;
    for (spec.effects) |effect| for (effect.variables) |ci| if (std.mem.indexOfScalar(usize, required.items, ci) == null) try required.append(a, ci);
    const usable = try group.select(a, .{ .missing_columns = required.items, .frequency = .truncate_positive, .weight = .positive_only });
    const rows = try a.alloc([]const @import("../value.zig").Value, usable.observations.len);
    const counts = try a.alloc(f64, usable.observations.len);
    for (usable.observations, rows, counts) |row, *r, *c| {
        r.* = row.cells;
        c.* = row.frequency.num;
    }
    const infos = try a.alloc(glm.design.Class, spec.classes.len);
    for (spec.classes, infos) |ci, *info| {
        const formed = try @import("class_levels.zig").build(a, spec.input.ds, rows, ci, .{ .order = spec.order, .frequencies = counts, .missing = .exclude });
        info.* = .{ .column = ci, .levels = formed.levels, .row_levels = formed.row_to_level };
    }
    return adjustClasses(cx, spec, options, infos, rows, counts);
}

/// Observation and frequency counts of one dependent-variable group (FREQ:
/// p.1119; SAS reference listing prints both frequency rows).
fn printCounts(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, group: selection.View, d: Design) !void {
    try out.print(cx.arena, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ d.read, d.n });
    if (spec.freq == null) return;
    var read: f64 = 0;
    for (group.observations) |row| if (row.frequency == .num and std.math.isFinite(row.frequency.num) and @trunc(row.frequency.num) >= 1) {
        read += @trunc(row.frequency.num);
    };
    var used: f64 = 0;
    for (d.frequencies[0..d.n]) |f| used += f;
    try out.print(cx.arena, "Sum of Frequencies Read {d}\nSum of Frequencies Used {d}\n", .{ read, used });
}

/// `means_only` replays the retained model for interactive MEANS: the fit is
/// rebuilt and validated but the ANOVA tables are not printed again.
pub fn executeAll(cx: proc.ProcCtx, out: *std.ArrayList(u8), parsed: Parsed, means_only: bool) diag.Error!void {
    const spec = parsed.spec;
    const a = cx.arena;
    patterns_differ = false;
    const graphs = !spec.noprint and !spec.plots_none and if (cx.graphics) |g| g.enabled == true else false;
    // ponytail: with ODS Graphics the Tukey grouping is the LinesPlot graph
    // (STAT-ANOVA-010). The listing LINES table printed otherwise has no SAS
    // layout reference and stays a loud gap.
    for (parsed.means) |request| if (request.tukey and !graphs and !spec.noprint) return proc.failGap(cx.diags, request.line, "PROC ANOVA: the MEANS TUKEY LINES table is not implemented without ODS Graphics", .{});
    // ponytail: box plots of FREQ-weighted data are not validated.
    if (graphs and spec.freq != null and (parsed.means.len != 0 or oneWay(spec))) return proc.failGap(cx.diags, 0, "PROC ANOVA: ODS Graphics box plots with a FREQ statement are not implemented; specify PLOTS=NONE", .{});
    const options = parsed.options;
    // ponytail: NOUNI with ODS Graphics has no SAS reference here.
    if (options.nouni and graphs and (parsed.means.len != 0 or oneWay(spec))) return proc.failGap(cx.diags, 0, "PROC ANOVA: MODEL NOUNI with ODS Graphics is not implemented; specify PLOTS=NONE", .{});
    var warned = false;
    var order: usize = 0;
    const view = try selection.View.init(a, spec.input, .{ .by = spec.by, .frequency = spec.freq });
    const groups = try view.groups(a, spec.descending, spec.notsorted, cx.diags);
    // SAS reference: an empty input is a NOTE with no tables, not an error.
    if (groups.len == 0 or view.observations.len == 0) return cx.diags.note(0, "No observations in data set {s}.", .{try @import("variable_lists.zig").datasetName(a, spec.input.ds)});
    groups: for (groups, 0..) |group, group_index| {
        const by: ?usize = if (spec.by.len != 0) group_index + 1 else null;
        if (by != null) warned = false;
        var designs: std.ArrayList(Design) = .empty;
        var errors: std.ArrayList(ErrorTerm) = .empty;
        var fits: std.ArrayList(Table) = .empty;
        for (spec.responses) |response| {
            const mark = cx.diags.list.items.len;
            const d = buildWith(cx, spec, options, group, response) catch |err| return relabel(cx, mark, err);
            if (d.n == 0) {
                // SAS reference: this ERROR ends only the current BY group.
                const message = "PROC ANOVA: One or more variables are missing or freq or weight is zero on every observation.";
                if (by == null) return cx.diags.fail(error.ExecError, 0, message, .{});
                try cx.diags.recoverableErr(0, message, .{});
                continue :groups;
            }
            const result = try ssTable(cx, spec, d);
            // SAS 9.4 reference: one WARNING per step (per BY group, followed
            // by the BY-group NOTE), only for models with more than one
            // effect (an unbalanced one-way model is valid).
            if (result.unequal and spec.effects.len > 1 and !warned and !means_only) {
                warned = true;
                try cx.diags.report(.warning, 0, "PROC ANOVA has determined that the number of observations in each cell is not equal.  PROC GLM may be more appropriate.", .{});
                if (by != null and group.observations.len > 0) try @import("by_groups.zig").reportNote(a, cx.diags, spec.input.ds, group.observations[0].cells, spec.by);
            }
            try designs.append(a, d);
            try errors.append(a, .{ .df = result.error_df, .mse = if (result.error_df > 0) result.sse / result.error_df else std.math.nan(f64) });
            try fits.append(a, result);
        }
        // pp.1138–1139: dependent variables sharing a missing-value pattern
        // form one group; groups print in order of their first variable.
        const owner = try a.alloc(usize, designs.items.len);
        var partitions: usize = 0;
        for (designs.items, 0..) |d, k| {
            owner[k] = for (designs.items[0..k], 0..) |e, j| {
                if (std.mem.eql(usize, e.source_rows, d.source_rows)) break owner[j];
            } else blk: {
                partitions += 1;
                break :blk partitions - 1;
            };
        }
        const multiple = partitions > 1;
        if (multiple) patterns_differ = true;
        if (!spec.noprint and !means_only) {
            try heading(cx, out, spec, group);
            try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
            const classes = if (multiple) try classInfo(cx, spec, options, group) else designs.items[0].classes;
            for (classes) |class| {
                try out.print(a, "\n{s} {d}", .{ spec.input.ds.columns.items[class.column].name, class.levels.len });
                for (class.levels) |level| try out.print(a, " {s}", .{level.label});
                try out.append(a, '\n');
            }
            for (0..partitions) |part| {
                if (multiple) {
                    try out.appendSlice(a, "\nData for Analysis of");
                    for (designs.items, owner) |d, o| if (o == part) try out.print(a, " {s}", .{spec.input.ds.columns.items[d.response].name});
                    try out.append(a, '\n');
                }
                for (designs.items, owner) |d, o| if (o == part) {
                    try printCounts(cx, out, spec, group, d);
                    break;
                };
            }
            if (multiple) try out.appendSlice(a, "\nNOTE: Variables in each group are consistent with respect to the presence or absence of missing values.\n");
        }
        for (0..partitions) |part| {
            var members: std.ArrayList(Design) = .empty;
            var terms: std.ArrayList(ErrorTerm) = .empty;
            for (designs.items, errors.items, fits.items, owner) |d, term, result, o| {
                if (o != part) continue;
                try members.append(a, d);
                try terms.append(a, term);
                // p.1129: NOUNI suppresses the univariate tables.
                if (spec.noprint or means_only or options.nouni) continue;
                try anovaPage(cx, out, spec, options, group, d, result);
                // pp.1116, 1143: default grouped box plot of a one-way model.
                if (graphs and oneWay(spec)) {
                    const model = try fTest(cx, result.model_ss / result.model_df, result.model_df, result);
                    try boxPlot(cx, spec, d, 0, .model, by, .{ .f = model.value, .p = model.p }, &order);
                }
            }
            if (!spec.noprint) for (parsed.means) |request| {
                // pp.1116, 1143: every MEANS effect gets a box plot per response.
                if (graphs) for (members.items) |d| try boxPlot(cx, spec, d, request.effect, .means, by, null, &order);
                if (request.tukey) {
                    for (members.items, terms.items) |d, term| try tukeyPage(cx, out, spec, group, d, term, request, by, &order);
                } else try renderMeans(cx, out, spec, group, members.items, request);
            };
        }
    }
}

/// Coeff Var, Root MSE and the mean fill 8 characters (SAS 9.4 reference
/// runs across magnitudes: 0.016167, 1.779513, 1579.825, 97044.70).
fn fitDecimals(x: f64) usize {
    const ax = @abs(x);
    if (!std.math.isFinite(ax) or ax < 1) return 6;
    const digits: usize = @intFromFloat(@floor(std.math.log10(ax)) + 1);
    return 7 -| digits;
}

const FTest = struct { value: f64, p: f64, f_text: []const u8, p_text: []const u8 };

/// SAS 9.4 reference: no error DF prints `.`; a zero error mean square with
/// a positive numerator prints `Infty` and `<.0001`.
fn fTest(cx: proc.ProcCtx, ms: f64, df: f64, t: Table) diag.Error!FTest {
    const a = cx.arena;
    if (t.error_df == 0 or df == 0) return .{ .value = std.math.nan(f64), .p = std.math.nan(f64), .f_text = ".", .p_text = "." };
    const mse = t.sse / t.error_df;
    if (mse == 0) {
        if (ms > 0) return .{ .value = std.math.inf(f64), .p = 0, .f_text = "Infty", .p_text = "<.0001" };
        return proc.failGap(cx.diags, 0, "PROC ANOVA: an F test with zero numerator and zero error mean square is not implemented", .{});
    }
    const value = ms / mse;
    // ponytail: SAS prints F in 7 columns (6374.94, then 63920.2, 639747,
    // 6.4E7); the overflow shapes are not pinned, so they are loud.
    if (value >= 1e4) return proc.failGap(cx.diags, 0, "PROC ANOVA: F values of 1E4 or more (overflow display) are not implemented", .{});
    const p = @import("reg_fit.zig").fProbability(value, @intFromFloat(df), @intFromFloat(t.error_df));
    return .{ .value = value, .p = p, .f_text = try number(a, value, 2), .p_text = try probability(a, p) };
}

fn anovaPage(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, options: Options, group: selection.View, d: Design, t: Table) diag.Error!void {
    const a = cx.arena;
    try heading(cx, out, spec, group);
    const name = spec.input.ds.columns.items[d.response].name;
    try out.print(a, "\nDependent Variable: {s}\n", .{name});
    // SAS reference listing: the FREQ variable is named under the heading.
    if (spec.freq) |fc| try out.print(a, "\nFrequency: {s}\n", .{spec.input.ds.columns.items[fc].name});
    try out.appendSlice(a, "\nSum of\nSource DF Squares Mean Square F Value Pr > F\n");
    // p.1129 and SAS reference: INT, or a model without effects, adds the
    // intercept to the Model row and the effect table and the total becomes
    // the uncorrected one; R-Square stays on the corrected scale.
    const with_intercept = options.intercept or spec.effects.len == 0;
    const model_df = t.model_df + @as(f64, if (with_intercept) 1 else 0);
    const model_ss = t.model_ss + if (with_intercept) t.cf else 0;
    const total_df = if (with_intercept) t.n else t.n - 1;
    const total_ss = if (with_intercept) t.uss else t.total;
    const model_ms = if (model_df > 0) model_ss / model_df else std.math.nan(f64);
    const model_f = try fTest(cx, model_ms, model_df, t);
    // SAS reference listings: the sums-of-squares columns never show more
    // than 8 decimals (6.75000000, 0.42857143), whatever the magnitude.
    const largest = @max(total_ss, @max(model_ss, t.sse));
    // SAS 9.4 reference (40 random BY groups): below 1E-5 the SS and MS
    // columns switch to BEST12. E notation (5.6E-5 still prints 0.00005637,
    // 9.98E-6 prints 9.9768518E-6). The 8-decimal cap otherwise holds.
    const decimals: usize = if (largest > 0 and largest < 1e-5) e_notation else @min(8, places(largest, 9));
    const mse: f64 = if (t.error_df > 0) t.sse / t.error_df else std.math.nan(f64);
    try out.print(a, "\nModel {d} {s} {s} {s} {s}\n\nError {d} {s} {s}\n\n{s} Total {d} {s}\n", .{
        model_df,                          try number(a, model_ss, decimals), try number(a, model_ms, decimals), model_f.f_text,                                     model_f.p_text,
        t.error_df,                        try number(a, t.sse, decimals),    try number(a, mse, decimals),      if (with_intercept) "Uncorrected" else "Corrected", total_df,
        try number(a, total_ss, decimals),
    });
    const r_square = if (t.total > 0) t.model_ss / t.total else std.math.nan(f64);
    const root = @sqrt(mse);
    const cv = 100 * root / t.mean;
    // SAS reference: a zero Root MSE prints as `0` in both columns.
    const cv_text = if (root == 0) "0" else try number(a, cv, fitDecimals(cv));
    const root_text = if (root == 0) "0" else try number(a, root, fitDecimals(root));
    try out.print(a, "\nR-Square Coeff Var Root MSE {s} Mean\n\n{s} {s} {s} {s}\n", .{
        name, try number(a, r_square, 6), cv_text, root_text, try number(a, t.mean, fitDecimals(t.mean)),
    });
    var maximum: f64 = if (with_intercept) t.cf else 0;
    for (t.effects) |effect| maximum = @max(maximum, effect.ss);
    const effect_decimals: usize = if (maximum > 0 and maximum < 1e-5) e_notation else @min(8, places(maximum, 9));
    // EFFECTSIZE rows: the intercept (when shown) and each effect.
    const count = t.effects.len + @as(usize, if (with_intercept) 1 else 0);
    const sizes = try a.alloc(es.Sizes, count);
    if (options.effectsize) {
        const intercept_only = spec.effects.len == 0;
        // Overall: the corrected model (or the intercept alone).
        const overall = if (intercept_only) try es.row(cx, t, t.cf, 1, .intercept_only) else try es.row(cx, t, t.model_ss, t.model_df, .overall);
        try es.renderOverall(cx, out, overall);
        var k: usize = 0;
        if (with_intercept) {
            sizes[0] = try es.row(cx, t, t.cf, 1, if (intercept_only) .intercept_only else .intercept);
            k = 1;
        }
        for (t.effects) |row| {
            sizes[k] = try es.row(cx, t, @max(0, row.ss), row.df, .effect);
            k += 1;
        }
    }
    const columns = if (options.effectsize) try es.ncColumns(cx, sizes) else undefined;
    if (options.effectsize) {
        try out.appendSlice(a, "\nNoncentrality Parameter\nMin Var\nUnbiased Low MSE\nSource DF Anova SS Mean Square F Value Pr > F Estimate Estimate 95% Confidence Limits\n\n");
    } else try out.appendSlice(a, "\nSource DF Anova SS Mean Square F Value Pr > F\n\n");
    var labels: std.ArrayList([]const u8) = .empty;
    if (with_intercept) {
        const f = try fTest(cx, t.cf, 1, t);
        try out.print(a, "Intercept 1 {s} {s} {s} {s}", .{ try number(a, t.cf, effect_decimals), try number(a, t.cf, effect_decimals), f.f_text, f.p_text });
        if (options.effectsize) try es.ncCells(out, a, columns, 0);
        try out.append(a, '\n');
        try labels.append(a, "Intercept");
    }
    for (spec.effects, t.effects) |effect, row| {
        const ss = @max(0, row.ss);
        const ms = if (row.df > 0) ss / row.df else std.math.nan(f64);
        const f = try fTest(cx, ms, row.df, t);
        // SAS 9.4 reference: an all-zero Anova SS column prints `0`.
        const ss_text = if (maximum == 0) "0" else try number(a, ss, effect_decimals);
        const label = try effectLabel(cx, spec, effect);
        try out.print(a, "{s} {d} {s} {s} {s} {s}", .{ label, row.df, ss_text, try number(a, ms, effect_decimals), f.f_text, f.p_text });
        if (options.effectsize) try es.ncCells(out, a, columns, labels.items.len);
        try out.append(a, '\n');
        try labels.append(a, label);
    }
    if (options.effectsize) try es.renderVariation(a, out, labels.items, sizes);
}

/// NAMELEN= (p.1115) display of an effect name. SAS reference listings:
/// a long main effect is cut to NAMELEN characters; a two-factor crossing
/// shares NAMELEN-1 characters between its names, the extra character
/// going to the second (NAMELEN=20: "averyvery*anotherver"; NAMELEN=40:
/// 19 + "*" + 20). Other shortened shapes (three or more factors, nested
/// effects) are not SAS-verified: loud gap.
fn effectLabel(cx: proc.ProcCtx, spec: Spec, effect: glm.parsing.Effect) diag.Error![]const u8 {
    const a = cx.arena;
    if (effect.variables.len == 1) return effect.name;
    // SAS reference: the factors of a crossed CLASS effect are named in
    // CLASS-statement order (`model y=b|a` with `class a b;` prints a*b).
    const position = struct {
        fn of(classes: []const usize, ci: usize) usize {
            return std.mem.indexOfScalar(usize, classes, ci) orelse classes.len;
        }
    }.of;
    var swapped = false;
    if (effect.variables.len == 2 and std.mem.indexOfScalar(u8, effect.name, '(') == null and position(spec.classes, effect.variables[1]) < position(spec.classes, effect.variables[0])) swapped = true;
    const names = try a.alloc([]const u8, effect.variables.len);
    var joined: usize = effect.variables.len - 1;
    for (names, effect.variables) |*name, ci| {
        name.* = spec.input.ds.columns.items[ci].name;
        joined += name.len;
    }
    if (swapped) std.mem.swap([]const u8, &names[0], &names[1]);
    if (joined <= spec.namelen) {
        if (!swapped) return effect.name;
        const star = std.mem.indexOfScalar(u8, effect.name, '*') orelse return effect.name;
        return std.fmt.allocPrint(a, "{s}*{s}", .{ effect.name[star + 1 ..], effect.name[0..star] });
    }
    if (effect.variables.len != 2 or std.mem.indexOfScalar(u8, effect.name, '(') != null)
        return proc.failGap(cx.diags, 0, "PROC ANOVA: shortening effect name {s} to NAMELEN={d} is not implemented for this effect shape", .{ effect.name, spec.namelen });
    // A name shorter than its share keeps its length and leaves the rest to
    // the other (SAS reference: "g*anotherveryveryver").
    const room = spec.namelen - 1;
    var first = room / 2;
    if (names[0].len < first) first = names[0].len else if (names[1].len < room - first) first = room - names[1].len;
    return std.fmt.allocPrint(a, "{s}*{s}", .{ names[0][0..first], names[1][0 .. room - first] });
}

/// The shared GLM reader and design builder label their diagnostics
/// `PROC GLM:`; under PROC ANOVA the message must name this procedure.
fn relabel(cx: proc.ProcCtx, mark: usize, err: diag.Error) diag.Error {
    for (cx.diags.list.items[mark..]) |*item| if (std.mem.startsWith(u8, item.message, "PROC GLM:")) {
        item.message = std.fmt.allocPrint(cx.diags.arena, "PROC ANOVA:{s}", .{item.message["PROC GLM:".len..]}) catch return error.OutOfMemory;
    };
    return err;
}

const ErrorTerm = struct { df: f64, mse: f64 };
const plots = @import("anova_plots.zig");
const es = @import("anova_effectsize.zig");

fn oneWay(spec: Spec) bool {
    return spec.effects.len == 1 and spec.effects[0].variables.len == 1 and spec.classes.len == 1;
}

/// p.1117: plots needing more than MAXPOINTS=5000 points are suppressed.
pub const max_points = 5000;

fn boxPlot(cx: proc.ProcCtx, spec: Spec, d: Design, effect: usize, kind: plots.Kind, by: ?usize, inset: ?plots.Inset, order: *usize) diag.Error!void {
    const session = cx.graphics orelse return;
    if (d.n > max_points) return;
    const a = cx.arena;
    const column = spec.effects[effect].variables[0];
    const class = for (d.classes) |class| {
        if (class.column == column) break class;
    } else return error.ExecError;
    const groups = try a.alloc(usize, d.n);
    for (groups, 0..) |*g, row| g.* = class.row_levels[row] orelse return error.ExecError;
    const labels = try a.alloc([]const u8, class.levels.len);
    for (labels, class.levels) |*label, level| label.* = level.label;
    const response = spec.input.ds.columns.items[d.response].name;
    const name = spec.input.ds.columns.items[column].name;
    const bytes = plots.boxSvg(a, kind, d.y[0..d.n], groups, labels, response, name, inset) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return proc.failGap(cx.diags, 0, "PROC ANOVA: the box plot for {s} by {s} cannot be drawn (empty level or non-finite value)", .{ response, name }),
    };
    try plots.queue(session, order.*, try plots.boxObject(a, kind, by, response, name), bytes);
    order.* += 1;
}

pub const TukeyLines = struct { labels: []const []const u8, means: []const f64, masks: []const u32, info: TukeyInfo };

/// Level means sorted high to low (ties keep level order) with their Tukey
/// groups. Null when the cells are unequal (harmonic-mean form: gap).
pub fn tukeyLines(a: A, labels: []const []const u8, means: []const f64, counts: []const usize, alpha: f64, df_error: f64, mse: f64) !?TukeyLines {
    for (counts) |n| if (n != counts[0]) return null;
    const index = try a.alloc(usize, means.len);
    for (index, 0..) |*x, i| x.* = i;
    std.mem.sort(usize, index, means, struct {
        fn before(m: []const f64, l: usize, r: usize) bool {
            return m[l] > m[r] or (m[l] == m[r] and l < r);
        }
    }.before);
    const sorted_labels = try a.alloc([]const u8, means.len);
    const sorted = try a.alloc(f64, means.len);
    for (index, sorted_labels, sorted) |source, *label, *mean| {
        label.* = labels[source];
        mean.* = means[source];
    }
    const info = try tukeyInfo(alpha, means.len, df_error, mse, @floatFromInt(counts[0]));
    return .{ .labels = sorted_labels, .means = sorted, .masks = try tukeyGroups(a, sorted, info.msd), .info = info };
}

fn tukeyPage(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, group: selection.View, d: Design, term: ErrorTerm, request: MeansRequest, by: ?usize, order: *usize) diag.Error!void {
    const a = cx.arena;
    const session = cx.graphics orelse return error.ExecError;
    const table = try @import("glm_means.zig").compute(cx, spec, d, .{ .effect = request.effect, .deponly = true });
    const class = d.classes[table.class_positions[0]];
    const labels = try a.alloc([]const u8, table.groups.len);
    const means = try a.alloc(f64, table.groups.len);
    const counts = try a.alloc(usize, table.groups.len);
    for (table.groups, labels, means, counts) |g, *label, *mean, *count| {
        label.* = class.levels[g.levels[0]].label;
        mean.* = g.means[0];
        count.* = g.count;
    }
    if (labels.len < 2) return proc.failGap(cx.diags, request.line, "PROC ANOVA: MEANS TUKEY for a single level is not implemented", .{});
    const lines = (tukeyLines(a, labels, means, counts, request.alpha, term.df, term.mse) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return proc.failGap(cx.diags, request.line, "PROC ANOVA: this MEANS TUKEY grouping cannot be computed (studentized range arguments or more than 24 groups)", .{}),
    }) orelse return proc.failGap(cx.diags, request.line, "PROC ANOVA: MEANS TUKEY with unequal cell sizes is not implemented", .{});
    const response = spec.input.ds.columns.items[d.response].name;
    const effect = spec.input.ds.columns.items[class.column].name;
    try heading(cx, out, spec, group);
    try renderTukeyInfo(a, out, response, lines.info);
    const bytes = plots.linesSvg(a, lines.labels, lines.means, lines.masks, response, effect, request.alpha) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ExecError,
    };
    try plots.queue(session, order.*, try plots.linesObject(a, by, response, effect), bytes);
    order.* += 1;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    try executeAll(cx, out, try parseAll(cx, tokens), false);
}

/// ponytail: process-wide state instead of a session object threaded through
/// the step runner (which other procedures are editing in parallel). The
/// open step's own tokens are retained (p.1138) in a private arena; an
/// interactive MEANS re-resolves CLASS/MODEL from them and rebuilds the fit,
/// which is the retained fit because any other step closes the procedure.
var interactive = false;
var retained_arena: ?std.heap.ArenaAllocator = null;
var retained: []const lex.Token = &.{};

fn forget() void {
    interactive = false;
    retained = &.{};
    if (retained_arena) |*arena| arena.deinit();
    retained_arena = null;
}

/// CLI entry: runs the step and leaves the procedure open unless BY was used
/// or QUIT closed it (pp.1118, 1138).
pub fn runStep(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    forget();
    const parsed = try parseAll(cx, tokens);
    try executeAll(cx, out, parsed, false);
    var quit = false;
    for (tokens, 0..) |token, i| if ((i == 0 or tokens[i - 1].tag == .semicolon) and token.tag == .name and eq(token.text, "quit")) {
        quit = true;
    };
    // p.1139: different missing-value patterns disable interactivity.
    if (parsed.spec.by.len != 0 or quit or patterns_differ) return;
    // Keep PROC/CLASS/MODEL/FREQ/WHERE...; drop RUN and already-run MEANS.
    retained_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const keep = retained_arena.?.allocator();
    var kept: std.ArrayList(lex.Token) = .empty;
    var i: usize = 0;
    while (i < tokens.len and tokens[i].tag != .eof) {
        var end = i;
        while (end < tokens.len and tokens[end].tag != .semicolon and tokens[end].tag != .eof) end += 1;
        if (!(i > 0 and (kw(tokens, i, "means") or kw(tokens, i, "run")))) for (tokens[i..@min(tokens.len, end + 1)]) |token| {
            if (token.tag == .eof) break;
            var copy = token;
            copy.text = try keep.dupe(u8, token.text);
            try kept.append(keep, copy);
        };
        i = end + 1;
    }
    retained = kept.items;
    interactive = true;
}

/// Statement group arriving after an open PROC ANOVA step. Returns true when
/// it was consumed here. MEANS runs against the retained model; the other
/// valid interactive requests are D-009 gaps, never open-code user errors;
/// any other step closes the procedure.
pub fn continuation(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!bool {
    if (!interactive) return false;
    if (tokens.len == 0 or tokens[0].tag != .name) return false;
    const word = tokens[0].text;
    if (oneOf(word, .{ "manova", "test", "repeated" })) return proc.failGap(cx.diags, tokens[0].line, "PROC ANOVA: interactive {s} is not implemented", .{word});
    if (eq(word, "quit")) {
        forget();
        return true;
    }
    if (eq(word, "means")) {
        var all: std.ArrayList(lex.Token) = .empty;
        try all.appendSlice(cx.arena, retained);
        try all.appendSlice(cx.arena, &.{ .{ .tag = .name, .text = "run", .line = tokens[0].line }, .{ .tag = .semicolon, .text = ";", .line = tokens[0].line } });
        var quit = false;
        var i: usize = 0;
        while (i < tokens.len and tokens[i].tag != .eof) {
            var end = i;
            while (end < tokens.len and tokens[end].tag != .semicolon and tokens[end].tag != .eof) end += 1;
            if (kw(tokens, i, "quit")) quit = true;
            // RUN/QUIT are boundaries; the gate in parseAll judges the rest.
            if (!kw(tokens, i, "run") and !kw(tokens, i, "quit")) try all.appendSlice(cx.arena, tokens[i..@min(tokens.len, end + 1)]);
            i = end + 1;
        }
        try all.append(cx.arena, .{ .tag = .eof });
        // A failed request leaves the procedure open, as in SAS.
        // The step runner flushes graphs only at step end; an interactive
        // MEANS writes its own box plots now (and drops them on failure).
        errdefer if (cx.graphics) |session| session.clear();
        try executeAll(cx, out, try parseAll(cx, all.items), true);
        if (cx.graphics) |session| try session.flush();
        if (quit) forget();
        return true;
    }
    // RUN executes pending (none) statements; ABSORB/BY/FREQ after the first
    // RUN are ignored (pp.1117–1119).
    if (oneOf(word, .{ "run", "by", "freq", "absorb" })) return true;
    forget();
    return false;
}

test "ANOVA001 open procedure turns unimplemented interactive requests into gaps until another step or QUIT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diagnostics = diag.Diagnostics.init(a);
    var library = @import("../exec.zig").Library.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &library, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    defer forget();
    defer diag.resetGap();
    // STAT-ANOVA-007 made interactive MEANS real; MANOVA stays the gap shape.
    const manova = try lex.tokenize(a, "manova h=g; run;", &diagnostics);
    try std.testing.expect(!try continuation(cx, &out, manova));
    interactive = true;
    try std.testing.expect(try continuation(cx, &out, try lex.tokenize(a, "run;", &diagnostics)));
    try std.testing.expect(try continuation(cx, &out, try lex.tokenize(a, "freq f;", &diagnostics)));
    diag.resetGap();
    try std.testing.expectError(error.ParseError, continuation(cx, &out, manova));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try std.testing.expect(!try continuation(cx, &out, try lex.tokenize(a, "proc print; run;", &diagnostics)));
    try std.testing.expect(!interactive);
    interactive = true;
    try std.testing.expect(try continuation(cx, &out, try lex.tokenize(a, "quit;", &diagnostics)));
    try std.testing.expect(!try continuation(cx, &out, manova));
    try std.testing.expectEqualStrings("", out.items);
}

test {
    _ = @import("anova_tests.zig");
    _ = @import("anova_effectsize.zig");
}
