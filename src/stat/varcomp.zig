//! PROC VARCOMP statements, roles and the METHOD=REML default listing,
//! SAS/STAT 15.4 Chapter 130 (PROC VARCOMP statement pp.10718-10719, BY/CLASS
//! /MODEL pp.10719-10720, Missing Values p.10721, Computational Methods
//! pp.10722-10723). `parse` records every documented declaration; anything
//! whose result or listing has not been proven against the SAS reference is
//! a D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const cl = @import("class_levels.zig");
const fit = @import("varcomp_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Method = enum { type1, mivque0, ml, reml, grr };

/// One MODEL effect: crossed CLASS variables and the nesting variables in
/// parentheses, both as indexes into `Spec.class`, sorted in CLASS order.
pub const Effect = struct { crossed: []const usize, nest: []const usize };

pub const Spec = struct {
    ds: *Dataset,
    method: Method = .mivque0,
    epsilon: f64 = 1e-8,
    maxiter: usize = 50,
    seed: ?f64 = null,
    /// CLASS variables as dataset columns, in statement order.
    class: []const usize = &.{},
    dependent: usize = 0,
    effects: []const Effect = &.{},
    fixed: usize = 0,
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
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC VARCOMP: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC VARCOMP: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC VARCOMP: " ++ text, args);
}

/// `keyword = number`, starting at the keyword.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.* + 1, .eq)) return invalid(cx, t, i.* + 1);
    var j = i.* + 2;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return invalid(cx, t, j);
    const x = std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j);
    i.* = j + 1;
    return sign * x;
}

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}

/// Position of a CLASS variable named at `i`; effects must use CLASS variables.
fn classIndex(cx: proc.ProcCtx, s: Spec, t: []const lex.Token, i: usize) diag.Error!usize {
    const c = try column(cx, s.ds, t, i);
    for (s.class, 0..) |k, pos| if (k == c) return pos;
    return user(cx, t[i].line, "effect variable {s} is not in the CLASS statement (continuous effects are not allowed)", .{t[i].text});
}

fn sortedUnique(a: A, xs: []usize) ![]const usize {
    std.mem.sort(usize, xs, {}, std.sort.asc(usize));
    var out: std.ArrayList(usize) = .empty;
    for (xs) |x| if (out.items.len == 0 or out.items[out.items.len - 1] != x) try out.append(a, x);
    return out.items;
}

/// MODEL effects between `i` and `end`: `A`, `A*B`, `A(B C)`, `A*B(C)` and
/// bar groups `A|B|...` of plain variables, expanded as in PROC ANOVA.
fn effects(cx: proc.ProcCtx, s: Spec, t: []const lex.Token, start: usize, end: usize) diag.Error![]const Effect {
    const a = cx.arena;
    var list: std.ArrayList(Effect) = .empty;
    var i = start;
    while (i < end) {
        var crossed: std.ArrayList(usize) = .empty;
        try crossed.append(a, try classIndex(cx, s, t, i));
        i += 1;
        var bar = false;
        while (i < end and (at(t, i, .star) or at(t, i, .pipe))) {
            if (at(t, i, .pipe)) bar = true;
            if (bar and at(t, i, .star)) return gap(cx, t[i].line, "mixing | and * in one effect is not implemented", .{});
            try crossed.append(a, try classIndex(cx, s, t, i + 1));
            i += 2;
        }
        var nest: std.ArrayList(usize) = .empty;
        if (at(t, i, .lparen)) {
            if (bar) return gap(cx, t[i].line, "nesting with bar notation is not implemented", .{});
            i += 1;
            while (i < end and !at(t, i, .rparen)) {
                try nest.append(a, try classIndex(cx, s, t, i));
                i += 1;
            }
            if (!at(t, i, .rparen) or nest.items.len == 0) return invalid(cx, t, i);
            i += 1;
        }
        if (bar) {
            // A|B|C -> A B A*B C A*C B*C A*B*C (subsets by highest member).
            const k = crossed.items.len;
            if (k > 10) return gap(cx, lineOf(t, i), "bar groups with more than 10 variables are not implemented", .{});
            var subsets: std.ArrayList(u32) = .empty;
            for (0..k) |top| {
                const hi: u32 = @as(u32, 1) << @intCast(top);
                const before = subsets.items.len;
                try subsets.append(a, hi);
                for (0..before) |x| try subsets.append(a, subsets.items[x] | hi);
            }
            for (subsets.items) |mask| {
                var vars: std.ArrayList(usize) = .empty;
                for (0..k) |b| if (mask & (@as(u32, 1) << @intCast(b)) != 0) try vars.append(a, crossed.items[b]);
                try list.append(a, .{ .crossed = try sortedUnique(a, vars.items), .nest = &.{} });
            }
        } else {
            if (try hasDuplicate(a, crossed.items, nest.items)) return user(cx, lineOf(t, i), "a variable appears more than once in an effect", .{});
            try list.append(a, .{ .crossed = try sortedUnique(a, crossed.items), .nest = try sortedUnique(a, nest.items) });
        }
    }
    return list.items;
}

fn hasDuplicate(a: A, x: []const usize, y: []const usize) !bool {
    const all = try std.mem.concat(a, usize, &.{ x, y });
    std.mem.sort(usize, all, {}, std.sort.asc(usize));
    for (1..all.len) |k| if (all[k] == all[k - 1]) return true;
    return false;
}

fn sameEffect(x: Effect, y: Effect) bool {
    return std.mem.eql(usize, x.crossed, y.crossed) and std.mem.eql(usize, x.nest, y.nest);
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .ds = undefined };
    var data: ?[]const u8 = null;
    var method_seen = false;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return invalid(cx, t, i);
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            var name = t[i + 2].text;
            i += 3;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i + 1].text });
                i += 2;
            }
            data = name;
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on DATA= are not implemented", .{});
        } else if (eq(word, "method") and at(t, i + 1, .eq)) {
            if (method_seen) return invalid(cx, t, i);
            method_seen = true;
            const m = t[i + 2 ..];
            s.method = if (kw(m, 0, "type1")) .type1 else if (kw(m, 0, "mivque0")) .mivque0 else if (kw(m, 0, "ml")) .ml else if (kw(m, 0, "reml")) .reml else if (kw(m, 0, "grr")) .grr else return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) {
                if (s.method != .grr) return invalid(cx, t, i);
                return gap(cx, t[i].line, "METHOD=GRR options are not implemented", .{});
            }
        } else if (eq(word, "epsilon")) {
            s.epsilon = try number(cx, t, &i);
            if (!(s.epsilon > 0)) return user(cx, t[i - 1].line, "EPSILON= must be positive", .{});
        } else if (eq(word, "maxiter")) {
            const x = try number(cx, t, &i);
            if (!(x >= 0) or x != @floor(x) or x > 1e9) return user(cx, t[i - 1].line, "MAXITER= must be a nonnegative integer", .{});
            s.maxiter = @intFromFloat(x);
        } else if (eq(word, "seed")) {
            const x = try number(cx, t, &i);
            if (!(x >= 0) or x != @floor(x)) return user(cx, t[i - 1].line, "SEED= must be an unsigned integer", .{});
            s.seed = x;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // "If this option is omitted, the most recently created SAS data set is
    // used" (p.10718); opensas does not track that here yet.
    const name = data orelse return gap(cx, lineOf(t, 0), "DATA= omitted (most recently created data set) is not implemented", .{});
    const raw = cx.lib.find(name) orelse return user(cx, lineOf(t, 0), "input data set {s} not found", .{name});
    s.ds = try proc.procInput(a, raw, t[0..2], cx.diags);

    var bys: by.Statements = .{};
    var by_seen = false;
    var class_seen = false;
    var model: ?usize = null;
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
            if (class_seen) return gap(cx, t[i].line, "more than one CLASS statement is not implemented", .{});
            class_seen = true;
            var cols: std.ArrayList(usize) = .empty;
            for (i + 1..end) |j| {
                const c = try column(cx, s.ds, t, j);
                for (cols.items) |prev| if (prev == c) return user(cx, t[j].line, "variable {s} appears more than once in the CLASS statement", .{t[j].text});
                try cols.append(a, c);
            }
            if (cols.items.len == 0) return invalid(cx, t, end);
            s.class = cols.items;
        } else if (kw(t, i, "model")) {
            if (model != null) return user(cx, t[i].line, "only one MODEL statement is allowed", .{});
            model = i;
        } else if (kw(t, i, "by")) {
            by_seen = true;
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            // Step boundary tokens may reach the body.
        } else if (kw(t, i, "where")) {
            // WHERE is applied by procInput.
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    const m = model orelse return user(cx, 0, "a MODEL statement is required", .{});
    var end = m;
    while (!at(t, end, .semicolon)) end += 1;
    var slash = end;
    for (m..end) |j| if (at(t, j, .slash)) {
        slash = j;
        break;
    };
    // MODEL dependent(s) = effects
    var j = m + 1;
    var deps: std.ArrayList(usize) = .empty;
    while (j < slash and !at(t, j, .eq)) : (j += 1) try deps.append(a, try column(cx, s.ds, t, j));
    if (!at(t, j, .eq) or deps.items.len == 0) return invalid(cx, t, j);
    if (deps.items.len > 1) return gap(cx, t[m].line, "more than one dependent variable is not implemented", .{});
    s.dependent = deps.items[0];
    if (s.ds.columns.items[s.dependent].type != .num) return user(cx, t[m].line, "dependent variable {s} must be numeric", .{s.ds.columns.items[s.dependent].name});
    for (s.class) |c| if (c == s.dependent) return user(cx, t[m].line, "the dependent variable cannot be a CLASS variable", .{});
    s.effects = try effects(cx, s, t, j + 1, slash);
    for (s.effects, 0..) |e, k| for (s.effects[0..k]) |prev| if (sameEffect(e, prev)) return user(cx, t[m].line, "an effect appears more than once in the MODEL statement", .{});
    var fixed_seen = false;
    j = slash + 1;
    while (j < end) {
        if (kw(t, j, "fixed")) {
            if (fixed_seen) return invalid(cx, t, j);
            fixed_seen = true;
            const x = try number(cx, t, &j);
            if (!(x >= 0) or x != @floor(x)) return user(cx, t[j - 1].line, "FIXED= must be a nonnegative integer", .{});
            if (x > @as(f64, @floatFromInt(s.effects.len))) return user(cx, t[j - 1].line, "FIXED= exceeds the number of effects in the MODEL statement", .{});
            s.fixed = @intFromFloat(x);
        } else if (kw(t, j, "cl") or kw(t, j, "alpha")) {
            return gap(cx, t[j].line, "the MODEL {s} option (confidence limits) is not implemented", .{t[j].text});
        } else return invalid(cx, t, j);
    }
    return s;
}

/// Execution boundary: only the REML default listing is verified.
fn boundary(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    if (s.method != .reml) return gap(cx, 0, "METHOD={s} is not implemented; only METHOD=REML is supported", .{switch (s.method) {
        .type1 => "TYPE1",
        .mivque0 => "MIVQUE0 (the default)",
        .ml => "ML",
        .grr => "GRR",
        .reml => unreachable,
    }});
    if (s.fixed == s.effects.len) return gap(cx, 0, "a model without random effects is not implemented", .{});
}

/// Rows used: nonmissing dependent and nonmissing variables of every effect.
const Group = struct {
    read: usize,
    rows: []const []const Value,
    levels: []cl.Levels, // per CLASS variable (only used ones are meaningful)
    problem: fit.Problem,
};

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |str| std.mem.trim(u8, str, " ").len == 0,
    };
}

fn prepare(cx: proc.ProcCtx, s: Spec, rows_in: []const []const Value) diag.Error!Group {
    const a = cx.arena;
    var used_class = try a.alloc(bool, s.class.len);
    @memset(used_class, false);
    for (s.effects) |e| {
        for (e.crossed) |k| used_class[k] = true;
        for (e.nest) |k| used_class[k] = true;
    }
    var rows: std.ArrayList([]const Value) = .empty;
    for (rows_in) |row| {
        if (missing(row[s.dependent])) continue;
        var skip = false;
        for (s.class, used_class) |c, u| if (u and missing(row[c])) {
            skip = true;
        };
        if (!skip) try rows.append(a, row);
    }
    const levels = try a.alloc(cl.Levels, s.class.len);
    for (s.class, levels) |c, *l| l.* = try cl.build(a, s.ds, rows.items, c, .{});
    const n = rows.items.len;
    const y = try a.alloc(f64, n);
    for (rows.items, y) |row, *v| v.* = row[s.dependent].num;
    var fixed: std.ArrayList(fit.Effect) = .empty;
    const intercept = try a.alloc(u32, n);
    @memset(intercept, 0);
    try fixed.append(a, .{ .level = intercept, .levels = 1 });
    var random: std.ArrayList(fit.Effect) = .empty;
    for (s.effects, 0..) |e, k| {
        const vars = try std.mem.concat(a, usize, &.{ e.crossed, e.nest });
        // Level combinations in lexicographic order of sorted level indexes.
        var keys = try a.alloc(u64, n);
        for (0..n) |o| {
            var key: u64 = 0;
            for (vars) |v| key = key * (levels[v].levels.len + 1) + levels[v].row_to_level[o].?;
            keys[o] = key;
        }
        const sorted = try a.dupe(u64, keys);
        std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
        var distinct: std.ArrayList(u64) = .empty;
        for (sorted) |key| if (distinct.items.len == 0 or distinct.items[distinct.items.len - 1] != key) try distinct.append(a, key);
        const idx = try a.alloc(u32, n);
        for (keys, idx) |key, *out| out.* = @intCast(std.sort.binarySearch(u64, distinct.items, key, struct {
            fn order(x: u64, yv: u64) std.math.Order {
                return std.math.order(x, yv);
            }
        }.order).?);
        const effect: fit.Effect = .{ .level = idx, .levels = distinct.items.len };
        if (k < s.fixed) try fixed.append(a, effect) else try random.append(a, effect);
    }
    return .{ .read = rows_in.len, .rows = rows.items, .levels = levels, .problem = .{ .y = y, .fixed = fixed.items, .random = random.items } };
}

fn effectName(a: A, s: Spec, e: Effect) ![]const u8 {
    var out: Out = .empty;
    for (e.crossed, 0..) |k, j| {
        if (j > 0) try out.append(a, '*');
        try out.appendSlice(a, s.ds.columns.items[s.class[k]].name);
    }
    if (e.nest.len > 0) {
        try out.append(a, '(');
        for (e.nest, 0..) |k, j| {
            if (j > 0) try out.append(a, '*');
            try out.appendSlice(a, s.ds.columns.items[s.class[k]].name);
        }
        try out.append(a, ')');
    }
    return out.items;
}

/// Estimate / covariance cell, following the SAS reference listing: 0 as
/// "0", five decimals below 1000, one decimal from 1000, five significant
/// digits below 0.01 and E notation below 1E-4.
pub fn cell(a: A, x: f64) ![]const u8 {
    const m = @abs(x);
    if (x == 0) return "0";
    if (m < 1e-4) {
        const e: i32 = @intFromFloat(@floor(@log10(m)));
        var mant = x / std.math.pow(f64, 10, @floatFromInt(e));
        var ee = e;
        if (@abs(mant) >= 9.99995) {
            mant /= 10;
            ee += 1;
        }
        return std.fmt.allocPrint(a, "{d:.4}E{s}{d:0>2}", .{ mant, if (ee < 0) "-" else "", @abs(ee) });
    }
    if (m < 0.001) return std.fmt.allocPrint(a, "{d:.8}", .{x});
    if (m < 0.01) return std.fmt.allocPrint(a, "{d:.7}", .{x});
    if (m < 1000) return std.fmt.allocPrint(a, "{d:.5}", .{x});
    return std.fmt.allocPrint(a, "{d:.1}", .{x});
}

fn pad(a: A, out: *Out, text: []const u8, width: usize, left: bool) !void {
    if (!left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
    if (left) if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}

fn compute(cx: proc.ProcCtx, s: Spec, g: Group) diag.Error!fit.Reml {
    const n = g.problem.y.len;
    if (n == 0) return gap(cx, 0, "the result for a BY group or data set without usable observations is not verified", .{});
    // ponytail: dense n x n REML algebra; larger inputs need the sparse
    // W-transformation the guide cites.
    if (n > 2000) return gap(cx, 0, "METHOD=REML with more than 2000 observations is not implemented", .{});
    return fit.reml(cx.arena, g.problem, s.epsilon, s.maxiter) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => gap(cx, 0, "REML estimation failed ({s}); this case is not implemented", .{@errorName(e)}),
    };
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, g: Group, r: fit.Reml) diag.Error!void {
    const a = cx.arena;
    try out.appendSlice(a, "\nVariance Components Estimation Procedure\n\n      Class Level Information\n \nClass         Levels    Values\n\n");
    for (s.class, g.levels) |c, l| {
        try pad(a, out, s.ds.columns.items[c].name, 14, true);
        try pad(a, out, try std.fmt.allocPrint(a, "{d}", .{l.levels.len}), 6, false);
        try out.appendSlice(a, "    ");
        for (l.levels) |lv| {
            try out.appendSlice(a, std.mem.trim(u8, lv.label, " "));
            try out.append(a, ' ');
        }
        try out.appendSlice(a, "\n\n");
    }
    try out.print(a, "\nNumber of Observations Read {d: >11}\nNumber of Observations Used {d: >11}\n\n\n", .{ g.read, g.rows.len });
    try out.print(a, "Dependent Variable:    {s}\n\n\n", .{s.ds.columns.items[s.dependent].name});
    // The REML Iterations table is NOT printed: see `run`.
    if (r.converged) try out.appendSlice(a, "Convergence criteria met.\n\n\n");
    var names: std.ArrayList([]const u8) = .empty;
    for (s.effects[s.fixed..]) |e| try names.append(a, try std.fmt.allocPrint(a, "Var({s})", .{try effectName(a, s, e)}));
    try names.append(a, "Var(Error)");
    var w: usize = "Variance Component".len;
    for (names.items) |nm| w = @max(w, nm.len);
    try out.appendSlice(a, "          REML Estimates\n \n");
    try pad(a, out, "Variance Component", w, true);
    try out.appendSlice(a, "        Estimate\n\n");
    for (names.items, r.theta) |nm, x| {
        try pad(a, out, nm, w, true);
        try pad(a, out, try cell(a, x), 16, false);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n                                         Asymptotic Covariance Matrix of Estimates\n \n");
    const q = names.items.len;
    try out.appendNTimes(a, ' ', w);
    for (names.items) |nm| try pad(a, out, nm, 26, false);
    try out.appendSlice(a, "\n\n");
    for (0..q) |i| {
        try pad(a, out, names.items[i], w, true);
        for (0..q) |j| try pad(a, out, try cell(a, r.cov[i * q + j]), 26, false);
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    try boundary(cx, s);
    if (slices.len == 0 or s.ds.rows.items.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    const groups = try a.alloc(Group, slices.len);
    const fits = try a.alloc(fit.Reml, slices.len);
    for (slices, groups, fits) |slice, *g, *f| {
        g.* = try prepare(cx, s, slice.rows);
        f.* = try compute(cx, s, g.*);
    }
    for (slices, groups, fits) |slice, g, f| {
        if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
        if (s.by_cols.len > 0) {
            var line: Out = .empty;
            try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) {
                try out.append(a, '\n');
                try out.appendSlice(a, std.mem.trimStart(u8, line.items[1..], " "));
            }
        }
        try render(cx, out, s, g, f);
        if (cx.listing_titles) |titles| try titles.emitFootnotes(a, out);
    }
    // D-009: the REML Iterations rows after iteration 0 depend on the exact
    // Newton-Raphson variant of the W-transformation algorithm, which is not
    // reproduced; the history is withheld loudly instead of printing
    // iterates that differ from SAS. Estimates and covariance are verified.
    for (fits) |f| if (!f.converged) {
        try cx.diags.warn(0, "PROC VARCOMP: REML did not converge within MAXITER={d} iterations; estimates are from the last iteration.", .{s.maxiter});
    };
    diag.markGap();
    try cx.diags.report(.err, 0, "PROC VARCOMP: the REML Iterations table (iteration history) is not implemented; it was omitted from the listing.", .{});
}

test {
    _ = @import("varcomp_fit.zig");
    _ = @import("varcomp_tests.zig");
}
