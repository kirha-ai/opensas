//! PROC HPMIXED (S154 Chapter 62, PROC HPMIXED/BY/CLASS/ID/MODEL/RANDOM/
//! WEIGHT statements, physical pp.4810-4843): declarations, basic options,
//! variable roles, observation selection and the deterministic part of the
//! default listing: Model Information, Class Level Information, Number of
//! Observations, Dimensions and (for a fit) Optimization Information. With
//! NOFIT (p.4803) that is the complete listing. A fit additionally needs the
//! REML estimation (STAT-HPMIXED-002/004), tests (STAT-HPMIXED-008/009) and
//! the dual quasi-Newton Iteration History, which depends on SAS's optimizer
//! path; the step prints the verified tables and then reports a loud gap
//! (rc 2). Never an approximate estimate.
//!
//! Rules settled by SAS 9.4 runs of invented data (2026-11-28, recorded in
//! tests/corpus/stat_hpmixed001_*.sas):
//! - an observation is used when the response, every CLASS variable and every
//!   MODEL/RANDOM variable is nonmissing and the WEIGHT is positive (p.4842);
//! - class levels come from observations whose CLASS variables are all
//!   nonmissing, even when the response or weight excludes them;
//! - "Columns in X" counts the level combinations present among the USED
//!   observations, "Columns in Z" the product of the displayed level counts;
//! - "Number of Observations Not Used" is not printed;
//! - NOFIT NOINFO prints nothing; an input without observations writes
//!   WARNING: The data set contains invalid or missing data.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

/// One MODEL/RANDOM effect: a product of CLASS and continuous columns.
pub const Effect = struct { name: []const u8, columns: []const usize };

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    response: usize = 0,
    classes: []const usize = &.{},
    ids: []const usize = &.{},
    fixed: []const Effect = &.{},
    intercept: bool = true,
    random: []const Effect = &.{},
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    /// TEST/CONTRAST/ESTIMATE/LSMEANS statements: parsed by later tickets.
    later_statement: ?[]const u8 = null,
    later_line: usize = 0,
    namelen: usize = 20,
    maxclprint: usize = 20,
    noclprint: bool = false,
    noprint: bool = false,
    nofit: bool = false,
    noinfo: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC HPMIXED: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC HPMIXED: " ++ text, args);
}
fn userError(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC HPMIXED: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC options (Table 62.2, pp.4812-4817) owned by later tickets.
const later_options = [_][]const u8{ "noprofile", "order", "blup", "ic", "infocrit", "itdetails", "lognote", "update", "mmeq", "noitprint", "ranks", "simple", "singchol", "singres", "singular", "nlprint" };
/// Documented statements owned by later HPMIXED tickets that cannot be skipped.
const later_statements = [_][]const u8{ "effect", "repeated", "parms", "output", "nloptions", "freq" };
/// Statements that only act on a fit (STAT-HPMIXED-008/010); a fit gaps anyway.
const fit_statements = [_][]const u8{ "test", "contrast", "estimate", "lsmeans" };

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

/// Effect list `a b a*b ...` up to `end` or a slash.
fn effects(cx: proc.ProcCtx, s: Spec, t: []const lex.Token, start: usize, end: usize, out: *std.ArrayList(Effect)) diag.Error!usize {
    const ds = s.input.ds;
    var j = start;
    while (j < end and !at(t, j, .slash)) {
        if (kw(t, j, "int") or kw(t, j, "intercept")) return gap(cx, t[j].line, "an INTERCEPT effect is not implemented (STAT-HPMIXED-006)", .{});
        var cols: std.ArrayList(usize) = .empty;
        var name: Out = .empty;
        const first = j;
        while (true) {
            if (at(t, j, .lparen) or at(t, j, .pipe) or at(t, j, .at)) return gap(cx, t[j].line, "nested, bar and degree effects are not implemented (STAT-HPMIXED-003)", .{});
            const c = try column(cx, ds, t, j);
            if (!isClass(s, c) and ds.columns.items[c].type != .num) return userError(cx, t[j].line, "character variable {s} must be a CLASS variable", .{t[j].text});
            if (std.mem.indexOfScalar(usize, cols.items, c) != null) return gap(cx, t[j].line, "an effect repeating variable {s} is not implemented", .{t[j].text});
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
        for (out.items) |prior| if (std.mem.eql(usize, prior.columns, cols.items)) return gap(cx, t[first].line, "a repeated effect {s} is not implemented", .{name.items});
        try out.append(cx.arena, .{ .name = name.items, .columns = cols.items });
    }
    return j;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
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
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "method") and at(t, i + 1, .eq)) {
            // p.4802: REML "is currently the only available method".
            if (!kw(t, i + 2, "reml")) return userError(cx, lineOf(t, i + 2), "METHOD= must be REML", .{});
            i += 3;
        } else if (eq(word, "namelen") and at(t, i + 1, .eq)) {
            // p.4803: the default and minimum value is 20.
            const v = try number(cx, t, i + 2);
            if (!(v >= 20) or v != @trunc(v)) return userError(cx, t[i + 2].line, "NAMELEN= must be an integer of at least 20", .{});
            s.namelen = @intFromFloat(@min(v, 1e6));
            i += 3;
        } else if (eq(word, "maxclprint") and at(t, i + 1, .eq)) {
            // p.4802: default 20; 0 prints every level; NOCLPRINT wins.
            const v = try number(cx, t, i + 2);
            if (!(v >= 0) or v != @trunc(v)) return userError(cx, t[i + 2].line, "MAXCLPRINT= must be a nonnegative integer", .{});
            s.maxclprint = @intFromFloat(@min(v, 1e9));
            i += 3;
        } else if (eq(word, "noclprint")) {
            if (at(t, i + 1, .eq)) return gap(cx, t[i].line, "NOCLPRINT=number is not implemented", .{});
            s.noclprint = true;
            i += 1;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "nofit")) {
            s.nofit = true;
            i += 1;
        } else if (eq(word, "noinfo")) {
            s.noinfo = true;
            i += 1;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return userError(cx, 0, "input dataset not found", .{});
    const upper = try std.ascii.allocUpperString(a, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') != null) upper else try std.fmt.allocPrint(a, "WORK.{s}", .{upper});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var model_seen = false;
    var bys: by.Statements = .{};
    var classes: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var fixed: std.ArrayList(Effect) = .empty;
    var random: std.ArrayList(Effect) = .empty;
    // Pass 1: CLASS first, so effect lists know their CLASS variables
    // regardless of the statement order checks done in pass 2.
    i += 1;
    const body = i;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "class")) {
            // p.4817: the CLASS statement must appear before the MODEL statement.
            if (model_seen) return userError(cx, t[i].line, "the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                if (at(t, j, .slash) or at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS statement options are not implemented (STAT-HPMIXED-003)", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(a, c);
            }
            s.classes = classes.items;
        } else if (kw(t, i, "model")) model_seen = true;
        i = end + 1;
    }
    model_seen = false;
    var weight_seen = false;
    i = body;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (kw(t, i, "class")) {
            // handled in pass 1
        } else if (kw(t, i, "model")) {
            if (model_seen) return userError(cx, t[i].line, "only one MODEL statement is allowed", .{});
            model_seen = true;
            s.response = try column(cx, ds, t, i + 1);
            if (ds.columns.items[s.response].type != .num) return userError(cx, t[i + 1].line, "response variable {s} must be numeric", .{t[i + 1].text});
            if (isClass(s, s.response)) return userError(cx, t[i + 1].line, "the response variable cannot be a CLASS variable", .{});
            if (!at(t, i + 2, .eq)) return invalid(cx, t, i + 2);
            var j = try effects(cx, s, t, i + 3, end, &fixed);
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, end);
                while (j < end) : (j += 1) {
                    if (kw(t, j, "noint")) {
                        s.intercept = false;
                    } else if (at(t, j, .name)) {
                        return gap(cx, t[j].line, "MODEL option {s} is not implemented (STAT-HPMIXED-003)", .{t[j].text});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "random")) {
            const j = try effects(cx, s, t, i + 1, end, &random);
            if (j == i + 1) return invalid(cx, t, j);
            if (at(t, j, .slash)) return gap(cx, t[j].line, "RANDOM statement options are not implemented (STAT-HPMIXED-006)", .{});
        } else if (kw(t, i, "by")) {
            // p.4805: when more than one BY statement appears only the last is used.
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "id")) {
            // p.4812: ID variables select the OUTPUT OUT= variables (OUTPUT:
            // STAT-HPMIXED-011); here they are validated and recorded.
            for (i + 1..end) |j| try ids.append(a, try column(cx, ds, t, j));
        } else if (kw(t, i, "weight")) {
            if (weight_seen) return userError(cx, t[i].line, "only one WEIGHT statement is allowed", .{});
            weight_seen = true;
            if (end != i + 2) return invalid(cx, t, if (end == i + 1) end else i + 2);
            const c = try column(cx, ds, t, i + 1);
            if (ds.columns.items[c].type != .num) return userError(cx, t[i + 1].line, "WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            s.weight = c;
        } else if (at(t, i, .name) and oneOf(t[i].text, &fit_statements)) {
            if (s.later_statement == null) {
                s.later_statement = t[i].text;
                s.later_line = t[i].line;
            }
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return userError(cx, 0, "MODEL statement required", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const bcols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| bcols[k] = ds.indexOf(n).?;
    s.by_cols = bcols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
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

fn classRow(s: Spec, row: []const Value) bool {
    for (s.classes) |c| if (missing(row[c])) return false;
    return true;
}

/// Used observation (module comment): response, CLASS, MODEL and RANDOM
/// variables nonmissing and a positive weight.
pub fn usedRow(s: Spec, row: []const Value) bool {
    if (missing(row[s.response]) or !classRow(s, row)) return false;
    for ([_][]const Effect{ s.fixed, s.random }) |list| for (list) |e| for (e.columns) |c| if (missing(row[c])) return false;
    if (s.weight) |w| if (missing(row[w]) or !(row[w].num > 0)) return false;
    return true;
}

fn cellLess(_: void, x: Value, y: Value) bool {
    return proc.cmpValue(x, y) == .lt;
}

/// Sorted distinct values of column `c` over `rows`.
fn levels(a: A, rows: []const []const Value, c: usize) ![]const Value {
    var values = try a.alloc(Value, rows.len);
    for (rows, 0..) |row, k| values[k] = row[c];
    std.mem.sort(Value, values, {}, cellLess);
    var distinct: std.ArrayList(Value) = .empty;
    for (values) |v| if (distinct.items.len == 0 or proc.cmpValue(distinct.items[distinct.items.len - 1], v) != .eq) try distinct.append(a, v);
    return distinct.items;
}

/// Distinct CLASS-level combinations of an effect over `rows`, and the
/// product of its per-variable level counts over the same rows.
fn combos(a: A, s: Spec, e: Effect, rows: []const []const Value) !struct { distinct: usize, product: usize } {
    var product: usize = 1;
    var any_class = false;
    for (e.columns) |c| if (isClass(s, c)) {
        any_class = true;
        product *= (try levels(a, rows, c)).len;
    };
    if (!any_class) return .{ .distinct = 1, .product = 1 };
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var key: Out = .empty;
    for (rows) |row| {
        key.clearRetainingCapacity();
        for (e.columns) |c| if (isClass(s, c)) {
            try key.appendSlice(a, try proc.cellText(a, row[c]));
            try key.append(a, 0);
        };
        const entry = try seen.getOrPut(a, key.items);
        if (!entry.found_existing) entry.key_ptr.* = try a.dupe(u8, key.items);
    }
    return .{ .distinct = seen.count(), .product = product };
}

pub const Dims = struct { read: usize, used: usize, x: usize, z: usize, g: usize };

/// Counts for one BY group; unverified count rules are gaps.
pub fn dimensions(cx: proc.ProcCtx, s: Spec, group: []const []const Value) diag.Error!Dims {
    const a = cx.arena;
    var used: std.ArrayList([]const Value) = .empty;
    var level_rows: std.ArrayList([]const Value) = .empty;
    for (group) |row| {
        if (usedRow(s, row)) try used.append(a, row);
        if (classRow(s, row)) try level_rows.append(a, row);
    }
    var x: usize = if (s.intercept) 1 else 0;
    for (s.fixed) |e| {
        const k = try combos(a, s, e, used.items);
        if (k.distinct != k.product) return gap(cx, 0, "Columns in X for effect {s} with empty level combinations is not verified (STAT-HPMIXED-003)", .{e.name});
        x += k.distinct;
    }
    var z: usize = 0;
    for (s.random) |e| {
        for (e.columns) |c| if (!isClass(s, c)) return gap(cx, 0, "a continuous variable in RANDOM effect {s} is not implemented (STAT-HPMIXED-006)", .{e.name});
        const k = try combos(a, s, e, level_rows.items);
        if (k.distinct != k.product) return gap(cx, 0, "Columns in Z for effect {s} with empty level combinations is not verified (STAT-HPMIXED-006)", .{e.name});
        z += k.product;
    }
    return .{ .read = group.len, .used = used.items.len, .x = x, .z = z, .g = s.random.len };
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
    if (heading.len > 0) try title(a, out, heading, lw + 4 + vw, false);
    for (lines) |l| {
        try left(a, out, l[0], lw + 4);
        if (value_right) try right(a, out, l[1], vw) else try left(a, out, l[1], vw);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
}

fn classTable(cx: proc.ProcCtx, out: *Out, s: Spec, rows: []const []const Value) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    var names_w: usize = 5;
    const texts = try a.alloc([]const u8, s.classes.len);
    const counts = try a.alloc(usize, s.classes.len);
    var widest: usize = 0;
    for (s.classes, texts, counts) |c, *text, *count| {
        if (ds.columns.items[c].format != null) return gap(cx, 0, "formatted CLASS levels are not implemented (STAT-HPMIXED-003)", .{});
        names_w = @max(names_w, ds.columns.items[c].name.len);
        const distinct = try levels(a, rows, c);
        if (ds.columns.items[c].type == .num) for (distinct) |v| if (v.num != @trunc(v.num) or @abs(v.num) >= 1e15) return gap(cx, 0, "noninteger numeric CLASS level formatting is not implemented (STAT-HPMIXED-003)", .{});
        count.* = distinct.len;
        var joined: Out = .empty;
        const shown = if (s.maxclprint == 0) distinct.len else @min(s.maxclprint, distinct.len);
        for (distinct[0..shown]) |v| {
            try joined.appendSlice(a, try proc.cellText(a, v));
            try joined.append(a, ' ');
        }
        if (shown < distinct.len) try joined.appendSlice(a, "...");
        text.* = joined.items;
        widest = @max(widest, joined.items.len);
    }
    // ponytail: the Values column wraps at 45 characters, the width observed
    // in the reference listings; SAS's own width rule is not documented.
    const vw: usize = @min(widest, 45);
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
                while (cut > 0 and rest[cut - 1] != ' ') cut -= 1;
                if (cut == 0) cut = vw;
            }
            try left(a, out, rest[0..cut], vw);
            rest = rest[cut..];
            try out.append(a, '\n');
        }
    }
    try out.appendSlice(a, "\n\n");
}

fn num(a: A, x: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{x});
}

pub fn render(cx: proc.ProcCtx, out: *Out, s: Spec, group: []const []const Value, d: Dims) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    var info: std.ArrayList([2][]const u8) = .empty;
    try info.append(a, .{ "Data Set", s.data_name });
    try info.append(a, .{ "Response Variable", ds.columns.items[s.response].name });
    if (s.weight) |w| try info.append(a, .{ "Weight Variable", ds.columns.items[w].name });
    try info.append(a, .{ "Estimation Method", "Restricted Maximum Likelihood (REML)" });
    try info.append(a, .{ "Degrees of Freedom Method", "Residual" });
    try infoTable(a, out, "Model Information", info.items, false);
    if (s.classes.len > 0 and !s.noclprint) {
        var level_rows: std.ArrayList([]const Value) = .empty;
        for (group) |row| if (classRow(s, row)) try level_rows.append(a, row);
        try classTable(cx, out, s, level_rows.items);
    }
    try infoTable(a, out, "", &.{
        .{ "Number of Observations Read", try num(a, d.read) },
        .{ "Number of Observations Used", try num(a, d.used) },
    }, true);
    try infoTable(a, out, "Dimensions", &.{
        .{ "G-side Cov. Parameters", try num(a, d.g) },
        .{ "R-side Cov. Parameters", "1" },
        .{ "Columns in X", try num(a, d.x) },
        .{ "Columns in Z", try num(a, d.z) },
        .{ "Subjects (Blocks in V)", "1" },
    }, true);
    if (!s.nofit) try infoTable(a, out, "Optimization Information", &.{
        .{ "Optimization Technique", "Dual Quasi-Newton" },
        .{ "Parameters in Optimization", try num(a, d.g) },
        .{ "Lower Boundaries", try num(a, d.g) },
        .{ "Upper Boundaries", "0" },
        .{ "Residual Variance", "Profiled" },
    }, false);
}

/// The BY line as the reference prints it under NOCENTER: flush left.
/// ponytail: the CENTER system option is not modelled for this procedure.
fn byLine(a: A, out: *Out, ds: *const Dataset, row: []const Value, cols: []const usize) !void {
    for (cols, 0..) |ci, j| {
        if (ds.columns.items[ci].format != null) return error.FormattedBy;
        if (j > 0) try out.append(a, ' ');
        try out.print(a, "{s}={s}", .{ ds.columns.items[ci].name, try proc.cellText(a, row[ci]) });
    }
    try out.appendSlice(a, "\n\n");
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, 0, "graphs under ODS GRAPHICS are not implemented", .{});
    const ds = s.input.ds;
    if (ds.rows.items.len == 0) {
        // SAS 9.4 (module comment): WARNING, no listing, step stopped.
        try cx.diags.warn(0, "The data set contains invalid or missing data.", .{});
        return;
    }
    if (s.nofit and s.later_statement != null) return gap(cx, s.later_line, "{s} under NOFIT is not verified (STAT-HPMIXED-008)", .{s.later_statement.?});
    if (!s.nofit and s.random.len == 0) return gap(cx, 0, "a fit without a RANDOM statement is not implemented (STAT-HPMIXED-002)", .{});
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const dims = try a.alloc(Dims, groups.len);
    for (groups, dims) |group, *d| d.* = try dimensions(cx, s, group.rows);
    if (s.noinfo) {
        // SAS 9.4: NOFIT NOINFO prints nothing (module comment).
        if (s.nofit) return;
        return gap(cx, 0, "NOINFO with a fit is not implemented (STAT-HPMIXED-012)", .{});
    }
    var body: Out = .empty;
    for (groups, dims, 0..) |group, d, k| {
        if (s.by_cols.len > 0) {
            if (k > 0) try body.append(a, '\n');
            byLine(a, &body, ds, group.rows[0], s.by_cols) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.FormattedBy => gap(cx, 0, "formatted BY variables are not implemented", .{}),
            };
        } else if (k > 0) try body.append(a, '\n');
        try body.appendSlice(a, "The HPMIXED Procedure\n\n");
        try render(cx, &body, s, group.rows, d);
    }
    if (!s.noprint) try out.appendSlice(a, body.items);
    if (s.nofit) return;
    // Loud: the estimation part of the listing is not produced.
    diag.markGap();
    try cx.diags.recoverableErr(0, "PROC HPMIXED: REML estimation (Iteration History, Covariance Parameter Estimates, Fit Statistics, tests) is not implemented (STAT-HPMIXED-002); the tables above are the verified model information", .{});
}

test {
    _ = @import("hpmixed_tests.zig");
}
