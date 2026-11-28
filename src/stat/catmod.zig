//! PROC CATMOD (STAT-CATMOD-001): data input, variable roles and basic
//! options — PROC CATMOD DATA=/ORDER=DATA|FORMATTED|FREQ|INTERNAL, WEIGHT,
//! POPULATION, BY, WHERE, formatted classification and response variables,
//! RESPONSE MEANS (weighted least squares) or the default generalized logits
//! (maximum likelihood), MODEL response = class effects (main effects and
//! crossings, deviation-from-the-mean coding) with / DESIGN, and interactive
//! RUN groups (S154 Chapter 36, PDF pp. 2191–2193, 2208–2211, 2220–2224).
//! DIRECT (STAT-CATMOD-003, PDF pp. 2196-2197): numeric variables entered
//! by their values, alone or crossed. FACTORS and LOGLIN stay gaps.
//! Everything else is a loud D-009 gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lifetest = @import("lifetest.zig");
const matrix = @import("mixed_fit_matrix.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);
const Token = lex.Token;

fn at(t: []const Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC CATMOD: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC CATMOD: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Statements in effect for the open procedure (each without its `;`). A later
/// statement of the same kind replaces the earlier one (interactive RUN groups).
pub const State = struct {
    proc_stmt: []const Token = &.{},
    weight: ?[]const Token = null,
    response: ?[]const Token = null,
    population: ?[]const Token = null,
    by_stmt: ?[]const Token = null,
    model: ?[]const Token = null,
    where: ?[]const Token = null,
    /// DIRECT (p. 2196): numeric variables entered by their values.
    direct: ?[]const Token = null,
};

/// ORDER= (p.2180): level order of classification and response variables.
pub const Order = enum { internal, data, formatted, freq };

/// `vars` are crossed; `nest` (Generation of the Design Matrix, p. 2224)
/// holds the variable an effect is nested within: A(B) or, with `value`,
/// the nested-by-value form A(B=v).
pub const Nest = struct { v: usize, value: ?[]const u8 = null, numeric: ?f64 = null };
pub const Effect = struct { name: []const u8, vars: []const usize, nest: ?Nest = null };

pub const Spec = struct {
    ds: *Dataset,
    order: Order = .internal,
    noprint: bool = false,
    weight: ?usize = null,
    response: usize = 0,
    means: bool = false,
    pop_vars: []const usize = &.{},
    effects: []const Effect = &.{},
    design: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    by_notsorted: bool = false,
    model_line: usize = 0,
    /// DIRECT variables (STAT-CATMOD-003): one design column of values each.
    direct: []const usize = &.{},
};

fn isDirect(s: Spec, v: usize) bool {
    return std.mem.indexOfScalar(usize, s.direct, v) != null;
}

/// Later CATMOD statements owned by other tickets.
const later_statements = [_][]const u8{ "contrast", "factors", "loglin", "repeated", "restrict" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}

fn parseProc(cx: proc.ProcCtx, s: *Spec, t: []const Token) diag.Error!void {
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            i += 2;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
            }
            if (at(t, i, .lparen)) {
                // Only a lone WHERE= data set option (applied by procInputObs,
                // which reads options of a one-level name only); KEEP=/DROP=/
                // RENAME= and the rest would change the variable roles.
                if (std.mem.indexOfScalar(u8, name.?, '.') != null or !kw(t, i + 1, "where") or !at(t, i + 2, .eq) or !at(t, i + 3, .lparen))
                    return gap(cx, t[i].line, "data set options other than WHERE= on DATA= are not implemented", .{});
                var depth: usize = 0;
                var j = i + 3;
                while (j < t.len) : (j += 1) {
                    if (at(t, j, .lparen)) depth += 1 else if (at(t, j, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                if (!at(t, j + 1, .rparen)) return gap(cx, t[i].line, "data set options other than WHERE= on DATA= are not implemented", .{});
                i = j + 2;
            }
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (eq(v, "data")) s.order = .data else if (eq(v, "internal")) s.order = .internal else if (eq(v, "formatted")) s.order = .formatted else if (eq(v, "freq")) s.order = .freq else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "noprint") and !valued) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "namelen") and valued) {
            // NAMELEN=n, 24 <= n <= 200; effect names longer than 24 are a gap
            // below, so the value changes no listing here.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const n = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (n < 24 or n > 200 or n != @floor(n)) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: NAMELEN= must be an integer between 24 and 200", .{});
            i += 3;
        } else return invalid(cx, t, i);
    }
    const ds = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse
        return cx.diags.fail(error.ParseError, lineOf(t, 0), "PROC CATMOD: input data set not found", .{});
    s.ds = ds;
}

fn varList(cx: proc.ProcCtx, ds: *const Dataset, t: []const Token, start: usize) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < t.len) : (j += 1) {
        if (!at(t, j, .name)) {
            if (at(t, j, .slash)) return gap(cx, t[j].line, "{s} statement options are not implemented", .{t[0].text});
            return gap(cx, t[j].line, "variable lists other than plain names in {s} are not implemented", .{t[0].text});
        }
        const c = try column(cx, ds, t, j);
        for (cols.items) |o| if (o == c) return cx.diags.fail(error.ParseError, t[j].line, "PROC CATMOD: variable {s} appears twice in the {s} statement", .{ t[j].text, t[0].text });
        try cols.append(cx.arena, c);
    }
    if (cols.items.len == 0) return invalid(cx, t, start);
    return cols.items;
}

fn parseModel(cx: proc.ProcCtx, s: *Spec, t: []const Token) diag.Error!void {
    const ds = s.ds;
    s.model_line = t[0].line;
    if (!at(t, 1, .name)) return invalid(cx, t, 1);
    if (at(t, 2, .star) or at(t, 2, .lparen) or kw(t, 1, "_response_")) return gap(cx, t[1].line, "multiple response variables and _RESPONSE_ are not implemented", .{});
    s.response = try column(cx, ds, t, 1);
    if (!at(t, 2, .eq)) return invalid(cx, t, 2);
    var i: usize = 3;
    if (at(t, i, .lparen)) return gap(cx, t[i].line, "a direct design matrix in MODEL is not implemented", .{});
    var effects: std.ArrayList(Effect) = .empty;
    while (i < t.len and !at(t, i, .slash)) {
        var vars: std.ArrayList(usize) = .empty;
        const first = i;
        while (true) {
            if (!at(t, i, .name)) {
                if (i < t.len and (t[i].tag == .lparen or t[i].tag == .pipe or t[i].tag == .at)) return gap(cx, t[i].line, "nested, bar and @ effects are not implemented", .{});
                return invalid(cx, t, i);
            }
            if (kw(t, i, "_response_")) return gap(cx, t[i].line, "_RESPONSE_ effects are not implemented", .{});
            const c = try column(cx, ds, t, i);
            for (vars.items) |o| if (o == c) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: variable {s} appears twice in an effect", .{t[i].text});
            try vars.append(cx.arena, c);
            i += 1;
            if (at(t, i, .star)) {
                i += 1;
                continue;
            }
            break;
        }
        var nest: ?Nest = null;
        if (at(t, i, .lparen)) {
            // ponytail: only one crossed-free variable nested within one
            // variable (A(B), A(B=v)), the forms this section documents;
            // A*B(C) and A(B C) are Specification of Effects (STAT-CATMOD-004).
            if (vars.items.len != 1) return gap(cx, t[i].line, "crossed effects within a nested effect are not implemented", .{});
            const nv = try column(cx, ds, t, i + 1);
            if (nv == vars.items[0]) return gap(cx, t[i].line, "an effect nested within itself is not implemented", .{});
            nest = .{ .v = nv };
            i += 2;
            if (at(t, i, .eq)) {
                i += 1;
                if (at(t, i, .number)) {
                    // A numeric nested value is its BEST16 text (p. 2224;
                    // SAS reference run: b=2.0 and b=1E0 print as b=2, b=1).
                    const x = std.fmt.parseFloat(f64, t[i].text) catch return invalid(cx, t, i);
                    nest.?.numeric = x;
                    nest.?.value = std.mem.trim(u8, try format.apply(cx.arena, .{ .num = x }, "best16."), " ");
                } else if (at(t, i, .string)) {
                    nest.?.value = t[i].text;
                } else return gap(cx, lineOf(t, i), "nested-by-value values other than a number or a quoted string are not implemented", .{});
                i += 1;
            }
            if (!at(t, i, .rparen)) {
                if (at(t, i, .name)) return gap(cx, t[i].line, "effects nested within several variables are not implemented", .{});
                return invalid(cx, t, i);
            }
            i += 1;
        }
        if (at(t, i, .lparen) or at(t, i, .pipe) or at(t, i, .at)) return gap(cx, t[i].line, "nested, bar and @ effects are not implemented", .{});
        // SAS names a crossing with its DIRECT variables first (reference
        // run: a*x with DIRECT x is the effect x*a), class variables after.
        if (s.direct.len > 0) {
            var ordered: std.ArrayList(usize) = .empty;
            for (vars.items) |c| if (isDirect(s.*, c)) try ordered.append(cx.arena, c);
            for (vars.items) |c| if (!isDirect(s.*, c)) try ordered.append(cx.arena, c);
            vars = ordered;
            if (nest) |n| if (isDirect(s.*, n.v) or isDirect(s.*, vars.items[0])) return gap(cx, t[first].line, "DIRECT variables in nested effects are not implemented", .{});
        }
        var nm: Out = .empty;
        for (vars.items, 0..) |c, k| {
            if (k > 0) try nm.append(cx.arena, '*');
            try nm.appendSlice(cx.arena, ds.columns.items[c].name);
        }
        if (nest) |n| {
            try nm.append(cx.arena, '(');
            try nm.appendSlice(cx.arena, ds.columns.items[n.v].name);
            if (n.value) |v| try nm.print(cx.arena, "={s}", .{v});
            try nm.append(cx.arena, ')');
        }
        for (effects.items) |e| if (eq(e.name, nm.items)) return cx.diags.fail(error.ParseError, t[first].line, "PROC CATMOD: effect {s} is specified twice", .{nm.items});
        try effects.append(cx.arena, .{ .name = nm.items, .vars = vars.items, .nest = nest });
    }
    if (effects.items.len == 0) return gap(cx, lineOf(t, i), "an intercept-only MODEL is not implemented", .{});
    s.effects = effects.items;
    for (s.effects) |e| if (e.name.len > 24) return gap(cx, s.model_line, "effect names longer than 24 characters (NAMELEN=) are not implemented", .{});
    if (at(t, i, .slash)) {
        i += 1;
        while (i < t.len) : (i += 1) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            if (eq(t[i].text, "design")) {
                s.design = true;
            } else if (oneOf(t[i].text, &.{ "averaged", "param", "cov", "missing", "nopredvar", "addcell", "alpha", "avgdesign", "clparm", "corrb", "covb", "epsilon", "freq", "maxiter", "ml", "gls", "wls", "noiter", "noint", "noprofile", "noresponse", "nodesign", "noparm", "nogls", "noprint", "onefactor", "oneway", "pred", "predict", "prob", "pcov", "profile", "title", "xpx", "zero" })) {
                return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{t[i].text});
            } else return invalid(cx, t, i);
        }
    }
}

/// The crossed variables of an effect followed by its nesting variable.
fn effectVars(a: A, e: Effect) ![]const usize {
    const n = e.nest orelse return e.vars;
    const all = try a.alloc(usize, e.vars.len + 1);
    @memcpy(all[0..e.vars.len], e.vars);
    all[e.vars.len] = n.v;
    return all;
}

pub fn resolve(cx: proc.ProcCtx, st: State) diag.Error!Spec {
    var s: Spec = .{ .ds = undefined };
    try parseProc(cx, &s, st.proc_stmt);
    const ds = s.ds;
    // Without WEIGHT every observation is one subject (raw data, p. 2220).
    if (st.weight) |weight| {
        if (weight.len != 2) return invalid(cx, weight, 2);
        const wc = try column(cx, ds, weight, 1);
        if (ds.columns.items[wc].type != .num) return cx.diags.fail(error.ParseError, weight[0].line, "PROC CATMOD: WEIGHT variable {s} must be numeric", .{weight[1].text});
        s.weight = wc;
    }
    if (st.response) |r| {
        if (r.len == 1) {
            s.means = false;
        } else if (r.len == 2 and kw(r, 1, "means")) {
            s.means = true;
        } else if (r.len >= 2 and at(r, 1, .name) and oneOf(r[1].text, &.{ "logits", "logit", "clogits", "alogits", "joint", "marginals", "marginal", "mean", "readcell", "exp", "log", "identity" })) {
            return gap(cx, r[1].line, "RESPONSE {s} is not implemented", .{r[1].text});
        } else return gap(cx, r[0].line, "RESPONSE functions other than MEANS are not implemented", .{});
    }
    if (st.direct) |d| if (d.len > 1) {
        var cols: std.ArrayList(usize) = .empty;
        for (d[1..]) |tk| {
            if (tk.tag != .name) return gap(cx, tk.line, "variable lists other than plain names in DIRECT are not implemented", .{});
            const c = ds.indexOf(tk.text) orelse {
                const up = try std.ascii.allocUpperString(cx.arena, tk.text);
                return cx.diags.fail(error.ParseError, tk.line, "Variable {s} not found.", .{up});
            };
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, tk.line, "Variable {s} in list does not match type prescribed for this list.", .{ds.columns.items[c].name});
            if (std.mem.indexOfScalar(usize, cols.items, c) == null) try cols.append(cx.arena, c);
        }
        s.direct = cols.items;
    };
    try parseModel(cx, &s, st.model.?);
    if (st.population) |p| {
        if (s.direct.len > 0) return gap(cx, p[0].line, "DIRECT variables with a POPULATION statement are not implemented", .{});
        s.pop_vars = try varList(cx, ds, p, 1);
        for (s.effects) |e| for (try effectVars(cx.arena, e)) |v| {
            for (s.pop_vars) |pv| {
                if (pv == v) break;
            } else return gap(cx, s.model_line, "model effect variables outside the POPULATION statement are not implemented", .{});
        };
    } else {
        // Class variables first, DIRECT variables after them (SAS reference
        // runs: MODEL y=x a and y=x z x*z with DIRECT x list a or z first).
        var pv: std.ArrayList(usize) = .empty;
        for ([_]bool{ false, true }) |want_direct| for (s.effects) |e| for (try effectVars(cx.arena, e)) |v| {
            if (isDirect(s, v) != want_direct) continue;
            for (pv.items) |o| {
                if (o == v) break;
            } else try pv.append(cx.arena, v);
        };
        s.pop_vars = pv.items;
        for (s.direct) |dv| for (s.pop_vars) |v| {
            if (v == dv) break;
        } else if (dv == s.response) return cx.diags.fail(error.ParseError, s.model_line, "PROC CATMOD: the response variable cannot also be an explanatory variable", .{});
    }
    for (s.pop_vars) |v| if (v == s.response) return cx.diags.fail(error.ParseError, s.model_line, "PROC CATMOD: the response variable cannot also be an explanatory variable", .{});
    if (s.means and ds.columns.items[s.response].type != .num) return cx.diags.fail(error.ParseError, s.model_line, "PROC CATMOD: RESPONSE MEANS requires a numeric response variable", .{});
    if (st.by_stmt) |b| {
        var bys: by.Statements = .{};
        var j: usize = 0;
        var full: std.ArrayList(Token) = .empty;
        try full.appendSlice(cx.arena, b);
        try full.append(cx.arena, .{ .tag = .semicolon, .text = ";", .line = b[0].line });
        try bys.read(cx.arena, full.items, &j);
        const pb = try bys.resolve(cx.arena, ds, cx.diags);
        const cols = try cx.arena.alloc(usize, pb.names.len);
        for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = pb.desc;
        s.by_notsorted = pb.notsorted;
    }
    return s;
}

// ── Contingency table ─────────────────────────────────────────────────────

fn lessValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a < y.num,
        .str => |a| std.mem.lessThan(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}
fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a == y.num,
        .str => |a| std.mem.eql(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}

/// Levels of one classification or response variable. A variable with a
/// format is classified by its trimmed formatted value (values sharing a
/// formatted value form one level, SAS reference run); `vals` keeps the
/// smallest internal value of each level (the INTERNAL sort key, verified on
/// a format merging 'a' and 'c' ahead of 'b') and `texts` the displayed value.
pub const Levels = struct { vals: []Value, texts: [][]const u8, formatted: bool, merged: bool = false };

fn keyText(a: A, ds: *const Dataset, c: usize, v: Value) ![]const u8 {
    if (ds.columns.items[c].format) |f| return std.mem.trim(u8, try format.apply(a, v, f), " ");
    return levelText(a, v);
}

/// Index of `v` among the levels (formatted variables match on the text).
fn findLevel(a: A, ds: *const Dataset, c: usize, ls: Levels, v: Value) !?usize {
    if (ls.formatted) {
        const t = try keyText(a, ds, c, v);
        for (ls.texts, 0..) |l, k| if (std.mem.eql(u8, l, t)) return k;
        return null;
    }
    for (ls.vals, 0..) |l, k| if (sameValue(l, v)) return k;
    return null;
}

/// Level order (p.2180, pp.2223-2224): DATA = order of appearance; INTERNAL
/// (default) = ascending unformatted value; FORMATTED = ascending formatted
/// value, except an unformatted numeric variable sorts by value; FREQ =
/// descending weighted frequency, ties in order of appearance (two SAS
/// reference runs: raw ties b,a,c and 2,1,3 kept their data order).
fn levels(a: A, s: Spec, rows: []const []const Value, c: usize) !Levels {
    const ds = s.ds;
    var ls: Levels = .{ .vals = &.{}, .texts = &.{}, .formatted = ds.columns.items[c].format != null };
    var vals: std.ArrayList(Value) = .empty;
    var texts: std.ArrayList([]const u8) = .empty;
    var freq: std.ArrayList(f64) = .empty;
    for (rows) |r| {
        ls.vals = vals.items;
        ls.texts = texts.items;
        const w: f64 = if (s.weight) |wc| r[wc].num else 1;
        if (try findLevel(a, ds, c, ls, r[c])) |k| {
            freq.items[k] += w;
            if (!sameValue(vals.items[k], r[c])) {
                ls.merged = true;
                if (lessValue(r[c], vals.items[k])) vals.items[k] = r[c];
            }
            continue;
        }
        try vals.append(a, r[c]);
        try texts.append(a, try keyText(a, ds, c, r[c]));
        try freq.append(a, w);
    }
    const n = vals.items.len;
    const perm = try a.alloc(usize, n);
    for (perm, 0..) |*p, k| p.* = k;
    const Ctx = struct {
        vals: []const Value,
        texts: []const []const u8,
        freq: []const f64,
        how: Order,
        fn less(cx: @This(), x: usize, y: usize) bool {
            return switch (cx.how) {
                .data => x < y,
                .internal => lessValue(cx.vals[x], cx.vals[y]),
                .formatted => std.mem.lessThan(u8, cx.texts[x], cx.texts[y]),
                .freq => if (cx.freq[x] != cx.freq[y]) cx.freq[x] > cx.freq[y] else x < y,
            };
        }
    };
    var how = s.order;
    if (how == .formatted and !ls.formatted and ds.columns.items[c].type == .num) how = .internal;
    std.sort.block(usize, perm, Ctx{ .vals = vals.items, .texts = texts.items, .freq = freq.items, .how = how }, Ctx.less);
    const ov = try a.alloc(Value, n);
    const ot = try a.alloc([]const u8, n);
    for (perm, 0..) |p, k| {
        ov[k] = vals.items[p];
        ot[k] = texts.items[p];
    }
    ls.vals = ov;
    ls.texts = ot;
    return ls;
}

pub const Table = struct {
    /// Levels per population variable (parallel to Spec.pop_vars).
    pop_levels: []const []const Value,
    /// Displayed level texts (parallel to pop_levels / resp_levels).
    pop_text: []const []const []const u8 = &.{},
    resp_text: []const []const u8 = &.{},
    /// Some used or missing-counted weight is not a whole number.
    frac_weights: bool = false,
    /// Level index tuple of each population, in population order.
    pops: []const []const usize,
    resp_levels: []const Value,
    /// counts[i * J + j]: weighted count of response j in population i.
    counts: []const f64,
    n_obs: usize,
    total: f64,
    freq_missing: f64 = 0,
};

/// A blank character value is missing (SAS character missing).
fn isMissing(v: Value) bool {
    return switch (v) {
        .num => v.isMissing(),
        .str => |t| std.mem.trim(u8, t, " ").len == 0,
    };
}

pub fn tabulate(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Table {
    const a = cx.arena;
    // Missing Values (p. 2220): an observation with a missing MODEL or
    // POPULATION variable, a missing weight or a nonpositive weight is
    // omitted. "Frequency Missing" sums the weights of the observations
    // omitted for missing variable values (SAS reference run: weights 7 and
    // 2 omitted that way give 9; a missing or zero weight adds nothing);
    // "Observations" counts the observations used.
    for (rows) |r| if (s.weight) |wc| {
        if (!r[wc].isMissing() and r[wc].num < 0) return cx.diags.fail(error.ParseError, s.model_line, "The data contain negative weights, which imply negative frequencies.", .{});
    };
    var kept: std.ArrayList([]const Value) = .empty;
    var freq_missing: f64 = 0;
    var frac_missing = false;
    for (rows) |r| {
        const w: f64 = if (s.weight) |wc| (if (r[wc].isMissing()) continue else r[wc].num) else 1;
        var missing = isMissing(r[s.response]);
        for (s.pop_vars) |c| missing = missing or isMissing(r[c]);
        if (missing) {
            freq_missing += w;
            frac_missing = frac_missing or w != @floor(w);
            continue;
        }
        if (w <= 0) continue;
        try kept.append(a, r);
    }
    const used = kept.items;
    // An empty, fully excluded or WHERE-emptied input is the SAS user error
    // (SAS reference runs: 0-observation data set, all weights missing, a
    // WHERE selecting nothing; no listing).
    if (used.len == 0) return cx.diags.fail(error.ParseError, s.model_line, "The data set contains 0 nonmissing observations with positive weight.", .{});
    var tb = try tabulateUsed(cx, s, used, freq_missing);
    tb.frac_weights = tb.frac_weights or frac_missing;
    return tb;
}

fn tabulateUsed(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, freq_missing: f64) diag.Error!Table {
    const a = cx.arena;
    const ds = s.ds;
    const pv = try a.alloc(Levels, s.pop_vars.len);
    for (s.pop_vars, pv) |c, *l| l.* = try levels(a, s, rows, c);
    const rv = try levels(a, s, rows, s.response);
    // ponytail: a format grouping several internal values of a DIRECT
    // variable uses the FIRST internal value (p. 2196); levels keep the
    // smallest, so the grouped case stays loud.
    for (s.pop_vars, pv) |c, l| if (l.merged and isDirect(s, c)) return gap(cx, s.model_line, "a DIRECT variable whose format groups several values is not implemented", .{});
    // ponytail: RESPONSE MEANS scores a response level by its value; a format
    // that merges several values has no verified score.
    if (s.means and rv.merged) return gap(cx, s.model_line, "RESPONSE MEANS with a format that merges response values is not implemented", .{});
    const pl = try a.alloc([]const Value, pv.len);
    const pt = try a.alloc([]const []const u8, pv.len);
    for (pv, pl, pt) |l, *v, *t| {
        v.* = l.vals;
        t.* = l.texts;
    }
    // Populations that occur, ordered lexicographically by level index.
    var keys: std.ArrayList([]usize) = .empty;
    const row_key = try a.alloc([]usize, rows.len);
    const row_resp = try a.alloc(usize, rows.len);
    for (rows, row_key, row_resp) |r, *rk, *rr| {
        const key = try a.alloc(usize, s.pop_vars.len);
        for (s.pop_vars, pv, key) |c, l, *k| k.* = (try findLevel(a, ds, c, l, r[c])).?;
        rk.* = key;
        rr.* = (try findLevel(a, ds, s.response, rv, r[s.response])).?;
        for (keys.items) |o| {
            if (std.mem.eql(usize, o, key)) break;
        } else try keys.append(a, key);
    }
    std.mem.sort([]usize, keys.items, {}, struct {
        fn f(_: void, x: []usize, y: []usize) bool {
            return std.mem.order(usize, x, y) == .lt;
        }
    }.f);
    const pops = try a.alloc([]const usize, keys.items.len);
    for (keys.items, pops) |k, *p| p.* = k;
    const J = rv.vals.len;
    const counts = try a.alloc(f64, pops.len * J);
    @memset(counts, 0);
    var total: f64 = 0;
    var frac = false;
    for (rows, row_key, row_resp) |r, key, j| {
        const i = for (pops, 0..) |p, ix| {
            if (std.mem.eql(usize, p, key)) break ix;
        } else unreachable;
        const w: f64 = if (s.weight) |wc| r[wc].num else 1;
        frac = frac or w != @floor(w);
        counts[i * J + j] += w;
        total += w;
    }
    return .{ .pop_levels = pl, .pop_text = pt, .pops = pops, .resp_levels = rv.vals, .resp_text = rv.texts, .counts = counts, .n_obs = rows.len, .total = total, .freq_missing = freq_missing, .frac_weights = frac };
}

/// Deviation-from-the-mean design (the last level is coded -1; crossings
/// are products with the first variable varying slowest). Returns the row-
/// major matrix (populations x q) and each effect's column count.
pub const Design = struct { x: []f64, q: usize, cols: []const usize };

pub fn designMatrix(a: A, s: Spec, tb: Table) !Design {
    const cols = try a.alloc(usize, s.effects.len);
    var q: usize = 1;
    for (s.effects, cols) |e, *c| {
        c.* = crossedCols(s, tb, e) * nestCols(s, tb, e);
        q += c.*;
    }
    const r = tb.pops.len;
    const x = try a.alloc(f64, r * q);
    for (tb.pops, 0..) |pop, i| {
        x[i * q] = 1;
        var off: usize = 1;
        for (s.effects, cols) |e, n| {
            const nc = crossedCols(s, tb, e);
            // A(B): one block of A's columns per level of B (B outer,
            // p. 2224); A(B=v): A's columns where B is v, zeros elsewhere.
            const in_level: ?usize = if (e.nest) |ns| pop[popPos(s, ns.v)] else null;
            const want: ?usize = if (e.nest) |ns| (if (ns.value != null) byValueLevel(s, tb, ns).? else null) else null;
            for (0..n) |k| {
                var rem = k % nc;
                var value: f64 = 1;
                var vi = e.vars.len;
                while (vi > 0) {
                    vi -= 1;
                    const pp = popPos(s, e.vars[vi]);
                    // A DIRECT variable enters by its internal value (p. 2196).
                    if (isDirect(s, e.vars[vi])) {
                        value *= tb.pop_levels[pp][pop[pp]].num;
                        continue;
                    }
                    const m = tb.pop_levels[pp].len - 1;
                    const level = rem % m;
                    rem /= m;
                    const have = pop[pp];
                    value *= if (have == level) 1 else if (have == m) -1 else 0;
                }
                if (in_level) |lv| {
                    const block = want orelse k / nc;
                    if (lv != block) value = 0;
                }
                x[i * q + off + k] = value;
            }
            off += n;
        }
    }
    return .{ .x = x, .q = q, .cols = cols };
}

fn crossedCols(s: Spec, tb: Table, e: Effect) usize {
    var n: usize = 1;
    for (e.vars) |v| {
        if (!isDirect(s, v)) n *= tb.pop_levels[popPos(s, v)].len - 1;
    }
    return n;
}
fn nestCols(s: Spec, tb: Table, e: Effect) usize {
    const ns = e.nest orelse return 1;
    return if (ns.value != null) 1 else tb.pop_levels[popPos(s, ns.v)].len;
}

/// The level of a nested-by-value effect's variable (p. 2224): values are
/// compared as BEST16 text, left-justified, or as formatted values.
/// ponytail: an unformatted numeric variable compares numerically, which
/// equals the BEST16 comparison except beyond 16 significant digits.
fn byValueLevel(s: Spec, tb: Table, ns: Nest) ?usize {
    const pp = popPos(s, ns.v);
    const formatted = s.ds.columns.items[ns.v].format != null;
    if (!formatted and s.ds.columns.items[ns.v].type == .num) {
        const x = ns.numeric orelse return null;
        for (tb.pop_levels[pp], 0..) |l, k| if (l.num == x) return k;
        return null;
    }
    const want = std.mem.trim(u8, ns.value.?, " ");
    for (tb.pop_text[pp], 0..) |l, k| if (std.mem.eql(u8, std.mem.trim(u8, l, " "), want)) return k;
    return null;
}

fn popPos(s: Spec, v: usize) usize {
    for (s.pop_vars, 0..) |p, k| if (p == v) return k;
    unreachable;
}

// ── Estimation ────────────────────────────────────────────────────────────

pub const Fit = struct {
    beta: []f64,
    cov: []f64,
    /// Functions per population (1 for MEANS, J-1 generalized logits).
    nf: usize,
    /// Residual chi-square (WLS) or likelihood ratio (ML) and its DF.
    resid: f64,
    resid_df: usize,
    /// WLS response functions per population.
    funcs: []const f64 = &.{},
};

fn invert(cx: proc.ProcCtx, m: []const f64, n: usize) diag.Error![]f64 {
    const inv = matrix.inverse(cx.arena, m, n) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return gap(cx, 0, "a singular or ill-conditioned covariance matrix is not implemented", .{}),
    };
    return inv.values;
}

/// Weighted least squares on response means (p.2208 WLS): F_i = sum_j s_j p_ij,
/// V_i = (sum_j s_j^2 p_ij - F_i^2) / n_i, b = (X'V^-1 X)^-1 X'V^-1 F.
pub fn fitMeans(cx: proc.ProcCtx, tb: Table, d: Design) diag.Error!Fit {
    const a = cx.arena;
    const r = tb.pops.len;
    const J = tb.resp_levels.len;
    const q = d.q;
    const f = try a.alloc(f64, r);
    const v = try a.alloc(f64, r);
    for (0..r) |i| {
        var n: f64 = 0;
        var m1: f64 = 0;
        var m2: f64 = 0;
        for (0..J) |j| {
            const c = tb.counts[i * J + j];
            const sc = tb.resp_levels[j].num;
            n += c;
            m1 += c * sc;
            m2 += c * sc * sc;
        }
        f[i] = m1 / n;
        v[i] = (m2 / n - f[i] * f[i]) / n;
        if (!(v[i] > 0)) return gap(cx, 0, "a population with zero response-function variance is not implemented", .{});
    }
    if (q > r) return gap(cx, 0, "models with more parameters than response functions are not implemented", .{});
    const xtx = try a.alloc(f64, q * q);
    const xty = try a.alloc(f64, q);
    @memset(xtx, 0);
    @memset(xty, 0);
    for (0..r) |i| for (0..q) |k| {
        xty[k] += d.x[i * q + k] * f[i] / v[i];
        for (0..q) |l| xtx[k * q + l] += d.x[i * q + k] * d.x[i * q + l] / v[i];
    };
    const cov = try invert(cx, xtx, q);
    const b = try a.alloc(f64, q);
    for (0..q) |k| {
        b[k] = 0;
        for (0..q) |l| b[k] += cov[k * q + l] * xty[l];
    }
    var resid: f64 = 0;
    for (0..r) |i| {
        var fit: f64 = 0;
        for (0..q) |k| fit += d.x[i * q + k] * b[k];
        resid += (f[i] - fit) * (f[i] - fit) / v[i];
    }
    return .{ .beta = b, .cov = cov, .nf = 1, .resid = resid, .resid_df = r - q, .funcs = f };
}

const Logits = struct {
    tb: Table,
    d: Design,
    nf: usize,
    prob: []f64,

    fn probabilities(self: Logits, b: []const f64, i: usize) void {
        const q = self.d.q;
        var denom: f64 = 1;
        for (0..self.nf) |j| {
            var eta: f64 = 0;
            for (0..q) |k| eta += self.d.x[i * q + k] * b[k * self.nf + j];
            self.prob[j] = @exp(eta);
            denom += self.prob[j];
        }
        self.prob[self.nf] = 1;
        for (self.prob) |*v| v.* /= denom;
    }

    /// Log likelihood sum n_ij log p_ij; fills the score g and information h.
    fn evaluate(self: Logits, b: []const f64, g: []f64, h: []f64) f64 {
        const q = self.d.q;
        const nf = self.nf;
        const p = q * nf;
        const J = nf + 1;
        const x = self.d.x;
        const prob = self.prob;
        @memset(g, 0);
        @memset(h, 0);
        var ll: f64 = 0;
        for (0..self.tb.pops.len) |i| {
            self.probabilities(b, i);
            var n: f64 = 0;
            for (0..J) |j| {
                const c = self.tb.counts[i * J + j];
                n += c;
                if (c > 0) ll += c * @log(prob[j]);
            }
            for (0..q) |k| {
                const xk = x[i * q + k];
                if (xk == 0) continue;
                for (0..nf) |j| {
                    g[k * nf + j] += xk * (self.tb.counts[i * J + j] - n * prob[j]);
                    for (0..q) |l| {
                        const xl = x[i * q + l];
                        if (xl == 0) continue;
                        for (0..nf) |m| {
                            const dd: f64 = if (j == m) 1 else 0;
                            h[(k * nf + j) * p + l * nf + m] += n * xk * xl * prob[j] * (dd - prob[m]);
                        }
                    }
                }
            }
        }
        return ll;
    }
};

/// Maximum likelihood for generalized logits log(p_ij / p_iJ) = x_i' b_j by
/// Newton-Raphson. Parameter (k, j) sits at index k * (J-1) + j, the order of
/// the estimates table. The likelihood ratio is 2 sum n_ij log(n_ij / m_ij).
pub fn fitLogits(cx: proc.ProcCtx, tb: Table, d: Design) diag.Error!Fit {
    const a = cx.arena;
    const r = tb.pops.len;
    const J = tb.resp_levels.len;
    if (J < 2) return gap(cx, 0, "a response with a single level is not implemented", .{});
    const nf = J - 1;
    const q = d.q;
    const p = q * nf;
    if (p > r * nf) return gap(cx, 0, "models with more parameters than response functions are not implemented", .{});
    const b = try a.alloc(f64, p);
    @memset(b, 0);
    const trial = try a.alloc(f64, p);
    const g = try a.alloc(f64, p);
    const h = try a.alloc(f64, p * p);
    const g2 = try a.alloc(f64, p);
    const h2 = try a.alloc(f64, p * p);
    const prob = try a.alloc(f64, J);
    const lg = Logits{ .tb = tb, .d = d, .nf = nf, .prob = prob };
    // Newton-Raphson from 0 with step halving; stop when the proportional
    // change in the log likelihood is below EPSILON=1E-8 (MODEL EPSILON=,
    // "Maximum Likelihood Method", S154 Chapter 36).
    var ll = lg.evaluate(b, g, h);
    var converged = false;
    var last_inv: []f64 = &.{};
    var iter: usize = 0;
    while (iter < 20) : (iter += 1) {
        const inv = try invert(cx, h, p);
        last_inv = inv;
        var dir = try a.alloc(f64, p);
        for (0..p) |k| {
            dir[k] = 0;
            for (0..p) |l| dir[k] += inv[k * p + l] * g[l];
        }
        var lambda: f64 = 1;
        var ll_new: f64 = 0;
        var halvings: usize = 0;
        while (true) {
            for (0..p) |k| trial[k] = b[k] + lambda * dir[k];
            ll_new = lg.evaluate(trial, g2, h2);
            if (ll_new >= ll or halvings == 10) break;
            lambda /= 2;
            halvings += 1;
        }
        if (halvings == 10) return gap(cx, 0, "maximum likelihood step-halving failure is not implemented", .{});
        @memcpy(b, trial);
        @memcpy(g, g2);
        @memcpy(h, h2);
        const change = @abs(ll_new - ll) / @abs(ll_new);
        ll = ll_new;
        if (change < 1e-8) {
            converged = true;
            break;
        }
    }
    // MAXITER=20 is the documented default (MODEL MAXITER=).
    if (!converged) return gap(cx, 0, "maximum likelihood that does not converge is not implemented", .{});
    // The covariance is the inverse information at the start of the last
    // iteration: the reference listing (school data, saturated model) shows
    // 23.25 / 0.2277 from it, against 23.24 / 0.2278 at the final estimates.
    const cov = last_inv;
    var lr: f64 = 0;
    for (0..r) |i| {
        var n: f64 = 0;
        lg.probabilities(b, i);
        for (0..J) |j| n += tb.counts[i * J + j];
        for (0..J) |j| {
            const c = tb.counts[i * J + j];
            if (c > 0) lr += 2 * c * @log(c / (n * prob[j]));
        }
    }
    return .{ .beta = b, .cov = cov, .nf = nf, .resid = @max(lr, 0), .resid_df = r * nf - p };
}

/// Wald chi-square for parameters [lo, hi): b' (Cov_sub)^-1 b.
pub fn wald(cx: proc.ProcCtx, f: Fit, lo: usize, hi: usize) diag.Error!f64 {
    const a = cx.arena;
    const n = hi - lo;
    const p = f.beta.len;
    const sub = try a.alloc(f64, n * n);
    for (0..n) |i| for (0..n) |j| {
        sub[i * n + j] = f.cov[(lo + i) * p + lo + j];
    };
    const inv = try invert(cx, sub, n);
    var w: f64 = 0;
    for (0..n) |i| for (0..n) |j| {
        w += f.beta[lo + i] * inv[i * n + j] * f.beta[lo + j];
    };
    return w;
}

// ── Listing ───────────────────────────────────────────────────────────────

fn fixed(a: A, x: f64, comptime decimals: u8) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return fixed(a, p, 4);
}
/// Estimates and standard errors: four decimals, more for |x| < 0.01 so that
/// three significant digits show (reference: -0.00749 beside 1.0491).
// ponytail: the template's D10.4-like rule, verified only for |x| >= 0.001.
fn estimate(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    const ax = @abs(x);
    if (ax != 0 and ax < 0.001) return gap(cx, 0, "displaying estimates below 0.001 in magnitude is not implemented", .{});
    if (ax >= 10000) return gap(cx, 0, "displaying estimates of 10000 or more is not implemented", .{});
    if (ax != 0 and ax < 0.01) return fixed(cx.arena, x, 5);
    return fixed(cx.arena, x, 4);
}
fn chisq(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    // ponytail: SAS shows 1318307.78 as 1318308 (reference run, STAT-CATMOD-005);
    // the rule for values of 1E6 or more is unverified, so loud.
    if (x >= 1e6) return gap(cx, 0, "chi-square values of 1E6 or more are not implemented", .{});
    return fixed(cx.arena, x, 2);
}
fn levelText(a: A, v: Value) ![]const u8 {
    return std.mem.trim(u8, try proc.cellText(a, v), " ");
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn emit(a: A, out: *Out, b: []const u8) !void {
    try out.appendSlice(a, std.mem.trimEnd(u8, b, " "));
    try out.append(a, '\n');
}
fn dashes(a: A, out: *Out, w: usize) !void {
    try out.appendNTimes(a, '-', w);
    try out.append(a, '\n');
}

fn dataSummary(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table) !void {
    const a = cx.arena;
    const cols = s.ds.columns.items;
    const upper = try std.ascii.allocUpperString(a, s.ds.name);
    const dsname = if (std.mem.indexOfScalar(u8, upper, '.')) |k| (if (std.mem.startsWith(u8, upper, "WORK.")) upper[k + 1 ..] else upper) else upper;
    // Whole-number frequencies: the first value column is max(text, 3) + 5
    // wide and the numbers max(text) wide. A fractional total or Frequency
    // Missing switches SAS to BEST8. frequencies, a first value column of
    // max(text, 7) + 5 and a 6-wide number field (8 after the 15-wide label)
    // (SAS reference runs: first-column texts of 1..4 and 9 characters
    // whole, 2, 3 and 9 fractional; totals 35.75, 4317.95, 10.5).
    const fractional = tb.total != @floor(tb.total) or tb.freq_missing != @floor(tb.freq_missing);
    // ponytail: fractional weights whose sums are whole have no verified layout.
    if (!fractional and tb.frac_weights) return gap(cx, s.model_line, "the Data Summary for fractional weights with whole-number sums is not implemented", .{});
    const fm = if (fractional) try format.bestNumW(a, tb.freq_missing, 8) else try format.bestNum(a, tb.freq_missing);
    const v1 = [_][]const u8{ cols[s.response].name, if (s.weight) |wc| cols[wc].name else "None", dsname, fm };
    const n2 = [_][]const u8{
        try std.fmt.allocPrint(a, "{d}", .{tb.resp_levels.len}),
        try std.fmt.allocPrint(a, "{d}", .{tb.pops.len}),
        if (fractional) try format.bestNumW(a, tb.total, 8) else try format.bestNum(a, tb.total),
        try std.fmt.allocPrint(a, "{d}", .{tb.n_obs}),
    };
    var nw: usize = 0;
    for (n2) |v| nw = @max(nw, v.len);
    if (fractional) {
        // SAS keeps the 6-wide field for a 7-character 4317.95 (one blank after
        // the label); an 8-character value has no verified layout.
        if (nw > 7) return gap(cx, s.model_line, "a fractional Data Summary frequency of 8 or more characters is not implemented", .{});
        nw = 6;
    }
    // The first value column is at least one wider than the number field
    // (SAS reference runs, STAT-CATMOD-005: 1-character texts with totals
    // of 3, 4 and 6 digits give columns of 4, 5 and 7; 2 digits give 3).
    var w1: usize = if (fractional) 7 else @max(3, nw + 1);
    for (v1) |v| w1 = @max(w1, v.len);
    w1 += 5;
    const l1 = [_][]const u8{ "Response", "Weight Variable", "Data Set", "Frequency Missing" };
    const l2 = [_][]const u8{ "Response Levels", "Populations", "Total Frequency", "Observations" };
    const width = 19 + w1 + 17 + nw;
    try centered(a, out, "Data Summary", width);
    try out.append(a, '\n');
    for (0..4) |k| {
        const b = try proc.line(a, width);
        proc.putLeft(b, 1, l1[k]);
        proc.putLeft(b, 20, v1[k]);
        proc.putLeft(b, 20 + w1, l2[k]);
        proc.putRight(b, width, n2[k]);
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

fn profiles(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table) !void {
    const a = cx.arena;
    const cols = s.ds.columns.items;
    const widths = try a.alloc(usize, s.pop_vars.len);
    var width: usize = 10;
    for (s.pop_vars, tb.pop_text, widths) |c, ls, *w| {
        w.* = cols[c].name.len;
        for (ls) |l| w.* = @max(w.*, l.len);
        width += w.* + 4;
    }
    width += 11;
    try centered(a, out, "Population Profiles", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putLeft(b, 1, "Sample");
    var col: usize = 11;
    for (s.pop_vars, widths) |c, w| {
        proc.putLeft(b, col, cols[c].name);
        col += w + 4;
    }
    proc.putLeft(b, col, "Sample Size");
    try emit(a, out, b);
    try dashes(a, out, width);
    for (tb.pops, 0..) |pop, i| {
        b = try proc.line(a, width);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{i + 1}));
        col = 11;
        for (pop, tb.pop_text, widths, s.pop_vars) |k, ls, w, c| {
            // Unformatted DIRECT values are right-aligned (SAS reference
            // run: 0.5, 1.25, 2.125); formatted DIRECT values (one, three)
            // and class levels are left-aligned.
            if (isDirect(s, c) and cols[c].format == null) proc.putRight(b, col + w - 1, ls[k]) else proc.putLeft(b, col, ls[k]);
            col += w + 4;
        }
        var n: f64 = 0;
        for (0..tb.resp_levels.len) |j| n += tb.counts[i * tb.resp_levels.len + j];
        // Fractional sample sizes print as BEST8. (reference: 1233.700123 -> 1233.7).
        proc.putRight(b, width, if (n != @floor(n)) try format.bestNumW(a, n, 8) else try format.bestNum(a, n));
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
    // Response Profiles.
    var rw: usize = cols[s.response].name.len;
    for (tb.resp_text) |l| rw = @max(rw, l.len);
    const width2 = 12 + rw;
    try centered(a, out, "Response Profiles", width2);
    try out.appendSlice(a, " \n");
    b = try proc.line(a, width2);
    proc.putLeft(b, 1, "Response");
    proc.putLeft(b, 13, cols[s.response].name);
    try emit(a, out, b);
    try dashes(a, out, width2);
    for (tb.resp_text, 0..) |l, j| {
        b = try proc.line(a, width2);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{j + 1}));
        proc.putLeft(b, 13, l);
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

/// With q > 1 functions per population (generalized logits of a response
/// with q + 1 levels) only the submatrix shared by the functions is shown,
/// beside the observed functions log(n_j / n_last) (p. 2226; SAS reference
/// runs with 1, 2 and 3 functions). ponytail: the "Response Functions"
/// heading start 7*q is verified for q = 2 and 3 only.
fn designTable(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table, d: Design, f: Fit) !void {
    const a = cx.arena;
    const nf: usize = if (s.means) 1 else tb.resp_levels.len - 1;
    const base = 20 + 14 * (nf - 1);
    const width = base + 9 * d.q;
    try centered(a, out, "Response Functions and Design Matrix", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    if (nf == 1) proc.putRight(b, 20, "Response") else proc.putLeft(b, 7 * nf, "Response Functions");
    const span = 9 * d.q - 2;
    proc.putLeft(b, base + 2 + (span - 12) / 2 + 2, "Design Matrix");
    try emit(a, out, b);
    b = try proc.line(a, width);
    proc.putLeft(b, 1, "Sample");
    if (nf == 1) proc.putRight(b, 20, "Function") else for (0..nf) |j| proc.putRight(b, 20 + 14 * j, try std.fmt.allocPrint(a, "{d}", .{j + 1}));
    for (0..d.q) |k| proc.putRight(b, base + 9 * (k + 1), try std.fmt.allocPrint(a, "{d}", .{k + 1}));
    try emit(a, out, b);
    try dashes(a, out, width);
    const J = tb.resp_levels.len;
    for (0..tb.pops.len) |i| {
        b = try proc.line(a, width);
        proc.putRight(b, 5, try std.fmt.allocPrint(a, "{d}", .{i + 1}));
        for (0..nf) |j| {
            const v = if (s.means) f.funcs[i] else @log(tb.counts[i * J + j] / tb.counts[i * J + J - 1]);
            proc.putRight(b, 20 + 14 * j, try fixed(a, v, 5));
        }
        // Cells print as BEST5. (SAS reference run: DIRECT values 0.5,
        // 1.25, 2.125 and -2.125 print as 0.5, 1.25, 2.125, -2.13).
        for (0..d.q) |k| proc.putRight(b, base + 9 * (k + 1), std.mem.trim(u8, try format.apply(a, .{ .num = d.x[i * d.q + k] }, "best5."), " "));
        try emit(a, out, b);
    }
    try out.appendSlice(a, "\n\n");
}

fn anovaTable(cx: proc.ProcCtx, out: *Out, s: Spec, d: Design, f: Fit) diag.Error!void {
    const a = cx.arena;
    const last = if (s.means) "Residual" else "Likelihood Ratio";
    var sw: usize = @max(9, last.len);
    for (s.effects) |e| sw = @max(sw, e.name.len);
    const width = sw + 7 + 13 + 14;
    try centered(a, out, if (s.means) "Analysis of Variance" else "Maximum Likelihood Analysis of Variance", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    proc.putLeft(b, 1, "Source");
    proc.putRight(b, sw + 7, "DF");
    proc.putRight(b, sw + 20, "Chi-Square");
    proc.putRight(b, width, "Pr > ChiSq");
    try emit(a, out, b);
    try dashes(a, out, width);
    var lo: usize = 0;
    for (0..s.effects.len + 1) |e| {
        const n = (if (e == 0) 1 else d.cols[e - 1]) * f.nf;
        const w = try wald(cx, f, lo, lo + n);
        lo += n;
        b = try proc.line(a, width);
        proc.putLeft(b, 1, if (e == 0) "Intercept" else s.effects[e - 1].name);
        proc.putRight(b, sw + 7, try std.fmt.allocPrint(a, "{d}", .{n}));
        proc.putRight(b, sw + 20, try chisq(cx, w));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(w, @floatFromInt(n))));
        try emit(a, out, b);
    }
    try out.append(a, '\n');
    b = try proc.line(a, width);
    proc.putLeft(b, 1, last);
    proc.putRight(b, sw + 7, try std.fmt.allocPrint(a, "{d}", .{f.resid_df}));
    if (f.resid_df == 0) {
        proc.putRight(b, sw + 18, ".");
        proc.putRight(b, width - 4, ".");
    } else {
        proc.putRight(b, sw + 20, try chisq(cx, f.resid));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(f.resid, @floatFromInt(f.resid_df))));
    }
    try emit(a, out, b);
    try out.appendSlice(a, "\n\n");
}

const Param = struct { effect: []const u8, level: []const u8 };

fn paramLabels(a: A, s: Spec, tb: Table, d: Design) ![]Param {
    const out = try a.alloc(Param, d.q);
    out[0] = .{ .effect = "Intercept", .level = "" };
    var off: usize = 1;
    for (s.effects, d.cols) |e, n| {
        const nc = crossedCols(s, tb, e);
        for (0..n) |k| {
            var parts: std.ArrayList([]const u8) = .empty;
            var rem = k % nc;
            var vi = e.vars.len;
            while (vi > 0) {
                vi -= 1;
                if (isDirect(s, e.vars[vi])) continue;
                const pp = popPos(s, e.vars[vi]);
                const m = tb.pop_levels[pp].len - 1;
                try parts.insert(a, 0, tb.pop_text[pp][rem % m]);
                rem /= m;
            }
            // A(B) labels add B's level after A's (SAS reference run:
            // "rural female"); A(B=v) labels show A's level only.
            if (e.nest) |ns| if (ns.value == null) try parts.append(a, tb.pop_text[popPos(s, ns.v)][k / nc]);
            out[off + k] = .{ .effect = e.name, .level = try std.mem.join(a, " ", parts.items) };
        }
        off += n;
    }
    return out;
}

fn estimatesTable(cx: proc.ProcCtx, out: *Out, s: Spec, tb: Table, d: Design, f: Fit) diag.Error!void {
    const a = cx.arena;
    const labels = try paramLabels(a, s, tb, d);
    var ew: usize = 9;
    var lw: usize = 0;
    for (labels) |l| {
        ew = @max(ew, l.effect.len);
        lw = @max(lw, l.level.len);
    }
    // No level labels (only DIRECT effects) drops the label column (SAS
    // reference run: Estimate ends 12 past "Parameter").
    const pw = if (lw == 0) ew else ew + 1 + lw;
    // One function per population (a two-level response under maximum
    // likelihood) drops the Function Number column (SAS reference run).
    const fn_w: usize = if (s.means or f.nf == 1) 0 else 9;
    const width = pw + fn_w + 12 + 11 + 12 + 14;
    const est = pw + fn_w + 12;
    try centered(a, out, if (s.means) "Analysis of Weighted Least Squares Estimates" else "Analysis of Maximum Likelihood Estimates", width);
    try out.appendSlice(a, " \n");
    var b = try proc.line(a, width);
    if (fn_w > 0) proc.putRight(b, pw + 9, "Function");
    proc.putRight(b, est + 11, "Standard");
    proc.putRight(b, est + 23, "Chi-");
    try emit(a, out, b);
    b = try proc.line(a, width);
    proc.putLeft(b, 1, "Parameter");
    if (fn_w > 0) proc.putLeft(b, pw + 3, "Number");
    proc.putRight(b, est, "Estimate");
    proc.putRight(b, est + 11, "Error");
    proc.putRight(b, est + 23, "Square");
    proc.putRight(b, width, "Pr > ChiSq");
    try emit(a, out, b);
    try dashes(a, out, width);
    const p = f.beta.len;
    for (labels, 0..) |l, k| for (0..f.nf) |j| {
        const ix = k * f.nf + j;
        const se = @sqrt(f.cov[ix * p + ix]);
        const w = f.beta[ix] * f.beta[ix] / (se * se);
        b = try proc.line(a, width);
        const first_of_effect = j == 0 and (k == 0 or !std.mem.eql(u8, labels[k - 1].effect, l.effect));
        if (first_of_effect) proc.putLeft(b, 1, l.effect);
        if (l.level.len > 0) proc.putLeft(b, ew + 2, l.level);
        if (fn_w > 0) proc.putLeft(b, pw + 5, try std.fmt.allocPrint(a, "{d}", .{j + 1}));
        proc.putRight(b, est, try estimate(cx, f.beta[ix]));
        proc.putRight(b, est + 11, try estimate(cx, se));
        proc.putRight(b, est + 23, try chisq(cx, w));
        proc.putRight(b, width, try pvalue(a, lifetest.chiProbability(w, 1)));
        try emit(a, out, b);
    };
}

/// Computes and renders one analysis of one BY group.
pub fn analyze(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value) diag.Error!void {
    const a = cx.arena;
    const tb = try tabulate(cx, s, rows);
    for (s.effects) |e| for (e.vars) |v| if (tb.pop_levels[popPos(s, v)].len < 2) return gap(cx, s.model_line, "an effect variable with a single level is not implemented", .{});
    // ponytail: a (near-)zero cell gives maximum likelihood parameters SAS
    // flags as infinite ('#') with redundant DF ('*'); a SAS reference run
    // with a cell of weight 1E-6 shows both. Unverified, so loud.
    if (!s.means) for (0..tb.pops.len) |i| {
        const J = tb.resp_levels.len;
        var n: f64 = 0;
        for (0..J) |j| n += tb.counts[i * J + j];
        for (0..J) |j| if (tb.counts[i * J + j] < 1e-4 * n) return gap(cx, s.model_line, "maximum likelihood with a zero or near-zero response cell (infinite parameters) is not implemented", .{});
    };
    for (s.effects) |e| if (e.nest) |ns| if (ns.value != null and byValueLevel(s, tb, ns) == null)
        return cx.diags.fail(error.ParseError, s.model_line, "The formatted value specified as a nested level for variable {s} is not in the data.", .{s.ds.columns.items[ns.v].name});
    const d = try designMatrix(a, s, tb);
    // ponytail: an absent nested level combination makes the design rank
    // deficient; SAS then marks redundant parameters ('*' DF, '.' estimates,
    // SAS reference run). That stays loud through the more-parameters-than-
    // functions and singular-matrix gaps of the fits.
    const f = if (s.means) try fitMeans(cx, tb, d) else try fitLogits(cx, tb, d);
    var b: Out = .empty;
    try b.appendSlice(a, "\nThe CATMOD Procedure\n\n");
    try dataSummary(cx, &b, s, tb);
    try profiles(cx, &b, s, tb);
    if (s.design) try designTable(cx, &b, s, tb, d, f);
    if (!s.means) {
        try b.appendSlice(a, "                   Maximum Likelihood Analysis\n\n           Maximum likelihood computations converged.\n\n\n");
    }
    try anovaTable(cx, &b, s, d, f);
    try estimatesTable(cx, &b, s, tb, d, f);
    if (!s.noprint) try out.appendSlice(a, b.items);
}

fn execute(cx: proc.ProcCtx, out: *Out, st: State) diag.Error!void {
    const s = try resolve(cx, st);
    var toks: std.ArrayList(Token) = .empty;
    try toks.appendSlice(cx.arena, st.proc_stmt);
    try toks.append(cx.arena, .{ .tag = .semicolon, .text = ";", .line = st.proc_stmt[0].line });
    if (st.where) |w| {
        try toks.appendSlice(cx.arena, w);
        try toks.append(cx.arena, .{ .tag = .semicolon, .text = ";", .line = w[0].line });
    }
    const input = try proc.procInputObs(cx.arena, s.ds, toks.items, cx.diags);
    var sp = s;
    sp.ds = input.ds;
    const slices = try by.checkedSlices(cx.arena, sp.ds, sp.by_cols, sp.by_desc, sp.by_notsorted, cx.diags);
    // Every group is computed before any text exists (fail loud, no partial listing).
    var groups: std.ArrayList(Out) = .empty;
    for (slices) |slice| {
        var g: Out = .empty;
        if (sp.by_cols.len > 0) try by.appendLine(cx.arena, &g, sp.ds, slice.rep.?, sp.by_cols);
        try analyze(cx, &g, sp, slice.rows);
        try groups.append(cx.arena, g);
    }
    for (groups.items) |g| try out.appendSlice(cx.arena, g.items);
}

// ── Interactive procedure state ───────────────────────────────────────────

var open = false;
var retained_arena: ?std.heap.ArenaAllocator = null;
var retained: State = .{};

fn forget() void {
    open = false;
    retained = .{};
    if (retained_arena) |*arena| arena.deinit();
    retained_arena = null;
}

fn keep(slice: []const Token) ![]const Token {
    const k = retained_arena.?.allocator();
    const copy = try k.alloc(Token, slice.len);
    for (slice, copy) |t, *c| {
        c.* = t;
        c.text = try k.dupe(u8, t.text);
    }
    return copy;
}

/// Applies statements to `st`; a RUN with a MODEL in effect runs the analysis.
/// Returns false when the procedure closes (QUIT or BY processing).
fn statements(cx: proc.ProcCtx, out: *Out, st: *State, t: []const Token, start: usize) diag.Error!bool {
    var i = start;
    var pending = false;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const stmt = t[i..end];
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "run") or eq(word, "quit")) {
            if (stmt.len != 1) return invalid(cx, t, i + 1);
            if (pending) {
                try execute(cx, out, st.*);
                pending = false;
                if (st.by_stmt != null) {
                    try cx.diags.note(t[i].line, "Interactivity disabled with BY processing.", .{});
                    return false;
                }
            }
            if (eq(word, "quit")) return false;
        } else if (eq(word, "model")) {
            st.model = try keep(stmt);
            pending = true;
        } else if (eq(word, "direct")) {
            // p. 2196: DIRECT must precede the MODEL it applies to (SAS
            // reference run: a MODEL earlier in the same RUN group is this
            // error). A new DIRECT deletes the prior DIRECT and MODEL
            // (SAS log NOTEs), so a bare DIRECT returns X to a class variable.
            if (pending) return cx.diags.fail(error.ParseError, t[i].line, "The DIRECT statement must precede the MODEL statement.", .{});
            if (st.model != null) {
                if (st.direct != null) try cx.diags.note(t[i].line, "Prior DIRECT statement(s) deleted.", .{});
                try cx.diags.note(t[i].line, "Prior MODEL statement(s) deleted.", .{});
                st.model = null;
            }
            st.direct = try keep(stmt);
        } else if (eq(word, "weight")) {
            st.weight = try keep(stmt);
        } else if (eq(word, "response")) {
            st.response = try keep(stmt);
        } else if (eq(word, "population")) {
            st.population = try keep(stmt);
        } else if (eq(word, "by")) {
            if (st.model != null and !pending) return cx.diags.fail(error.ParseError, t[i].line, "PROC CATMOD: a BY statement must precede the first RUN", .{});
            st.by_stmt = try keep(stmt);
        } else if (oneOf(word, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{word});
        } else if (eq(word, "where")) {
            // Applied to the input by procInputObs (last WHERE wins).
            st.where = try keep(stmt);
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    // ponytail: a MODEL waiting for a RUN at end of input runs as SAS does
    // at step end.
    if (pending) try execute(cx, out, st.*);
    return true;
}

/// CLI entry: the PROC CATMOD step through its first RUN. The procedure
/// stays open for later RUN groups unless QUIT or BY closed it (p.2180).
pub fn runStep(cx: proc.ProcCtx, out: *Out, t: []const Token) diag.Error!void {
    forget();
    var end: usize = 0;
    while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
    if (!at(t, end, .semicolon)) return invalid(cx, t, end);
    retained_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var st: State = .{ .proc_stmt = try keep(t[0..end]) };
    // Validate the PROC statement before any statement runs.
    var probe: Spec = .{ .ds = undefined };
    try parseProc(cx, &probe, st.proc_stmt);
    const stays = try statements(cx, out, &st, t, end + 1);
    if (!stays) {
        forget();
        return;
    }
    retained = st;
    open = true;
}

/// Statement group arriving after an open PROC CATMOD step. Returns true when
/// consumed here; any other step closes the procedure.
pub fn continuation(cx: proc.ProcCtx, out: *Out, t: []const Token) diag.Error!bool {
    if (!open) return false;
    if (t.len == 0 or t[0].tag != .name) return false;
    if (!oneOf(t[0].text, &.{ "model", "weight", "response", "population", "run", "quit", "by", "where", "contrast", "direct", "factors", "loglin", "repeated", "restrict" })) {
        forget();
        return false;
    }
    var st = retained;
    const stays = statements(cx, out, &st, t, 0) catch |e| {
        retained = st;
        return e;
    };
    if (!stays) {
        forget();
        return true;
    }
    retained = st;
    return true;
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "STAT-CATMOD-001 deviation coding of a crossed effect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "t");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    const lv = [_]Value{ .{ .num = 1 }, .{ .num = 2 } };
    const lw = [_]Value{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 3 } };
    const effects = [_]Effect{ .{ .name = "a", .vars = &.{0} }, .{ .name = "b", .vars = &.{1} }, .{ .name = "a*b", .vars = &.{ 0, 1 } } };
    const s: Spec = .{ .ds = &ds, .pop_vars = &.{ 0, 1 }, .effects = &effects };
    const pops = [_][]const usize{ &.{ 0, 0 }, &.{ 0, 2 }, &.{ 1, 1 } };
    const tb: Table = .{ .pop_levels = &.{ &lv, &lw }, .pops = &pops, .resp_levels = &.{}, .counts = &.{}, .n_obs = 0, .total = 0 };
    const d = try designMatrix(a, s, tb);
    try std.testing.expectEqual(@as(usize, 6), d.q);
    // (a=1, b=1): 1 | 1 | 1 0 | 1 0
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 1, 0, 1, 0 }, d.x[0..6]);
    // (a=1, b=3): 1 | 1 | -1 -1 | -1 -1
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, -1, -1, -1, -1 }, d.x[6..12]);
    // (a=2, b=2): 1 | -1 | 0 1 | 0 -1
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, 0, 1, 0, -1 }, d.x[12..18]);
}

test "STAT-CATMOD-005 nested and nested-by-value design columns (guide p. 2224 tables)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "t");
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("a", .num);
    const lb = [_]Value{ .{ .num = 1 }, .{ .num = 2 } };
    const la = [_]Value{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 3 } };
    const pops = [_][]const usize{ &.{ 0, 0 }, &.{ 0, 1 }, &.{ 0, 2 }, &.{ 1, 0 }, &.{ 1, 1 }, &.{ 1, 2 } };
    const tb: Table = .{ .pop_levels = &.{ &lb, &la }, .pop_text = &.{ &.{ "1", "2" }, &.{ "1", "2", "3" } }, .pops = &pops, .resp_levels = &.{}, .counts = &.{}, .n_obs = 0, .total = 0 };
    // A(B): B outer, A's deviation columns inside each block.
    const nested = [_]Effect{.{ .name = "a(b)", .vars = &.{1}, .nest = .{ .v = 0 } }};
    const s1: Spec = .{ .ds = &ds, .pop_vars = &.{ 0, 1 }, .effects = &nested };
    const d = try designMatrix(a, s1, tb);
    try std.testing.expectEqual(@as(usize, 5), d.q);
    const want = [_]f64{
        1, 1,  0,  0,  0,
        1, 0,  1,  0,  0,
        1, -1, -1, 0,  0,
        1, 0,  0,  1,  0,
        1, 0,  0,  0,  1,
        1, 0,  0,  -1, -1,
    };
    try std.testing.expectEqualSlices(f64, &want, d.x);
    // A(B=1) A(B=2) gives the same columns.
    const by_value = [_]Effect{ .{ .name = "a(b=1)", .vars = &.{1}, .nest = .{ .v = 0, .value = "1", .numeric = 1 } }, .{ .name = "a(b=2)", .vars = &.{1}, .nest = .{ .v = 0, .value = "2", .numeric = 2.0 } } };
    const s2: Spec = .{ .ds = &ds, .pop_vars = &.{ 0, 1 }, .effects = &by_value };
    const d2 = try designMatrix(a, s2, tb);
    try std.testing.expectEqualSlices(f64, &want, d2.x);
    try std.testing.expectEqualSlices(usize, &.{ 2, 2 }, d2.cols);
    // Labels: A(B) shows A's level then B's; A(B=v) shows A's level only.
    const l1 = try paramLabels(a, s1, tb, d);
    try std.testing.expectEqualStrings("2 1", l1[2].level);
    try std.testing.expectEqualStrings("1 2", l1[3].level);
    const l2 = try paramLabels(a, s2, tb, d2);
    try std.testing.expectEqualStrings("1", l2[3].level);
    // A value not in the data has no level (the SAS user error).
    try std.testing.expect(byValueLevel(s2, tb, .{ .v = 0, .value = "3", .numeric = 3 }) == null);
}

test "STAT-CATMOD-001 WLS means and ML logits by hand on a saturated two-population table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d0 = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = undefined, .diags = &d0 };
    // Two populations, responses 0/1 with counts (10, 30) and (20, 20).
    const lv = [_]Value{ .{ .num = 1 }, .{ .num = 2 } };
    const rl = [_]Value{ .{ .num = 0 }, .{ .num = 1 } };
    const pops = [_][]const usize{ &.{0}, &.{1} };
    const tb: Table = .{ .pop_levels = &.{&lv}, .pops = &pops, .resp_levels = &rl, .counts = &.{ 10, 30, 20, 20 }, .n_obs = 4, .total = 80 };
    const d: Design = .{ .x = @constCast(&[_]f64{ 1, 1, 1, -1 }), .q = 2, .cols = &.{1} };
    const m = try fitMeans(cx, tb, d);
    // F = 0.75, 0.5: b0 = 0.625, b1 = 0.125; saturated residual 0.
    try std.testing.expectApproxEqAbs(@as(f64, 0.625), m.beta[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.125), m.beta[1], 1e-12);
    try std.testing.expectEqual(@as(usize, 0), m.resid_df);
    // Var(b1) = (V1 + V2) / 4 with V1 = .75*.25/40, V2 = .25/40.
    try std.testing.expectApproxEqAbs((0.1875 / 40.0 + 0.25 / 40.0) / 4.0, m.cov[3], 1e-15);
    const l = try fitLogits(cx, tb, d);
    // logit(p_0 / p_1) = log(1/3), log(1): b0 = -log(3)/2, b1 = -log(3)/2.
    try std.testing.expectApproxEqAbs(-@log(3.0) / 2.0, l.beta[0], 1e-9);
    try std.testing.expectApproxEqAbs(-@log(3.0) / 2.0, l.beta[1], 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0), l.resid, 1e-9);
}

test "STAT-CATMOD-001 level order: FREQ ties keep data order, formats merge levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "t");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("w", .num);
    const r = [_][2]Value{
        .{ .{ .str = "b" }, .{ .num = 2 } }, .{ .{ .str = "ac" }, .{ .num = 1 } },
        .{ .{ .str = "c" }, .{ .num = 2 } }, .{ .{ .str = "ab" }, .{ .num = 1 } },
    };
    var rows: [4][]const Value = undefined;
    for (&rows, &r) |*o, *x| o.* = x;
    // FREQ: weighted counts b 2, ac 1, c 2, ab 1 -> b, c (tie: data order), ac, ab.
    var s: Spec = .{ .ds = &ds, .weight = 1, .order = .freq };
    var l = try levels(a, s, &rows, 0);
    try std.testing.expectEqualStrings("b", l.texts[0]);
    try std.testing.expectEqualStrings("c", l.texts[1]);
    try std.testing.expectEqualStrings("ac", l.texts[2]);
    // $1. merges ac and ab into 'a' (weight 2, smallest value ab): INTERNAL
    // sorts a, b, c; FREQ puts the three ties in data order b, a, c.
    ds.columns.items[0].format = "$1.";
    s.order = .internal;
    l = try levels(a, s, &rows, 0);
    try std.testing.expect(l.merged);
    try std.testing.expectEqual(@as(usize, 3), l.texts.len);
    try std.testing.expectEqualStrings("a", l.texts[0]);
    try std.testing.expectEqualStrings("ab", l.vals[0].str);
    s.order = .freq;
    l = try levels(a, s, &rows, 0);
    try std.testing.expectEqualStrings("b", l.texts[0]);
    try std.testing.expectEqualStrings("a", l.texts[1]);
    try std.testing.expectEqualStrings("c", l.texts[2]);
}

test "STAT-CATMOD-003 DIRECT design columns: values, value times deviation, value products (guide p. 2196)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "t");
    _ = try ds.addColumn("a", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("z", .num);
    const la = [_]Value{ .{ .str = "p" }, .{ .str = "q" } };
    const lx = [_]Value{ .{ .num = 0.5 }, .{ .num = 1.25 }, .{ .num = 2.125 } };
    const lz = [_]Value{ .{ .num = 0 }, .{ .num = 3 } };
    // Populations ordered a (class) then x then z (DIRECT last).
    const pops = [_][]const usize{ &.{ 0, 0, 1 }, &.{ 0, 2, 0 }, &.{ 1, 1, 1 } };
    const tb: Table = .{ .pop_levels = &.{ &la, &lx, &lz }, .pop_text = &.{ &.{ "p", "q" }, &.{ "0.5", "1.25", "2.125" }, &.{ "0", "3" } }, .pops = &pops, .resp_levels = &.{}, .counts = &.{}, .n_obs = 0, .total = 0 };
    const effects = [_]Effect{ .{ .name = "a", .vars = &.{0} }, .{ .name = "x", .vars = &.{1} }, .{ .name = "x*a", .vars = &.{ 1, 0 } }, .{ .name = "x*z", .vars = &.{ 1, 2 } } };
    const s: Spec = .{ .ds = &ds, .pop_vars = &.{ 0, 1, 2 }, .effects = &effects, .direct = &.{ 1, 2 } };
    const d = try designMatrix(a, s, tb);
    // One column per DIRECT effect: 1 | a | x | x*a | x*z.
    try std.testing.expectEqual(@as(usize, 5), d.q);
    try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1, 1 }, d.cols);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 0.5, 0.5, 1.5 }, d.x[0..5]);
    try std.testing.expectEqualSlices(f64, &.{ 1, 1, 2.125, 2.125, 0 }, d.x[5..10]);
    try std.testing.expectEqualSlices(f64, &.{ 1, -1, 1.25, -1.25, 3.75 }, d.x[10..15]);
    // DIRECT variables add no level text: x and x*z unlabeled, x*a "p".
    const l = try paramLabels(a, s, tb, d);
    try std.testing.expectEqualStrings("", l[2].level);
    try std.testing.expectEqualStrings("p", l[3].level);
    try std.testing.expectEqualStrings("", l[4].level);
}
