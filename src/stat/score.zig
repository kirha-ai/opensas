//! PROC SCORE (SAS/STAT 15.4 ch.109): PROC statement options (DATA=, SCORE=,
//! OUT=, TYPE=, PREDICT, RESIDUAL, NOSTD), the VAR / BY / ID roles, the
//! documented missing-value rules and the closed-form linear scores written
//! to the OUT= data set (STAT-SCORE-001). PROC SCORE displays no output
//! (p.8911). Everything the cited pages define but this file does not
//! compute, or whose SAS behaviour is not verified, is a loud D-009 gap; no
//! data set is created for a step that hits one.
//!
//! Score of observation i for coefficient row k (pp.8908-8911):
//!   sum_j c_kj * z_ij  (+ Intercept_k when the SCORE= data set carries one),
//! where z = (x - MEAN) / STD when MEAN and STD rows exist and NOSTD is not
//! given, else z = x; a missing coefficient counts as 0; PREDICT turns a
//! coefficient of -1 into 0; RESIDUAL reverses the sign of the score.
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

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8 = "",
    score: *Dataset,
    score_name: []const u8 = "",
    out: ?[]const u8 = null,
    /// TYPE= value; null = the default (_TYPE_='SCORE' or 'USCORE', p.8909).
    type: ?[]const u8 = null,
    predict: bool = false,
    residual: bool = false,
    nostd: bool = false,
    /// VAR names (resolved against both data sets in run).
    vars: []const []const u8 = &.{},
    var_given: bool = false,
    /// ID column indices into DATA=.
    ids: []const usize = &.{},
    /// BY names/directions, resolved against the SCORE= data set.
    by_names: []const []const u8 = &.{},
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
    return cx.diags.fail(error.ParseError, line(t, i), "PROC SCORE: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
/// `name` or `libref.name` after `OPTION=`; returns the index after it and
/// whether data set options followed in parentheses.
fn memberName(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8, paren: *bool) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    paren.* = at(t, j, .lparen);
    if (paren.*) j = proc.skipParen(t, j);
    into.* = name;
    return j;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var name: ?[]const u8 = null;
    var score_name: ?[]const u8 = null;
    var out: ?[]const u8 = null;
    var type_value: ?[]const u8 = null;
    var predict = false;
    var residual = false;
    var nostd = false;
    var qualified: ?usize = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const option = try std.ascii.allocLowerString(a, t[i].text);
        // The chapter states no rule for a repeated PROC option; do not guess one.
        if ((try seen.getOrPut(a, option)).found_existing) return gap(cx.diags, t[i].line, "PROC SCORE: repeated PROC statement option {s} is not verified", .{t[i].text});
        const valued = at(t, i + 1, .eq);
        var paren = false;
        if (eq(option, "data") and valued) {
            const first = i + 2;
            const after = try memberName(cx, t, first, &name, &paren);
            if (at(t, first + 1, .dot)) qualified = first;
            i = after;
        } else if (eq(option, "score") and valued) {
            i = try memberName(cx, t, i + 2, &score_name, &paren);
            if (paren) return gap(cx.diags, t[i - 1].line, "PROC SCORE: data set options on SCORE= are not implemented", .{});
        } else if (eq(option, "out") and valued) {
            i = try memberName(cx, t, i + 2, &out, &paren);
            if (paren) return gap(cx.diags, t[i - 1].line, "PROC SCORE: data set options on OUT= are not implemented (STAT-SCORE-004)", .{});
        } else if (eq(option, "type") and valued) {
            // p.8909: TYPE=name or 'string'; not case sensitive.
            if (!at(t, i + 2, .name) and !at(t, i + 2, .string)) return cx.diags.fail(error.ParseError, t[i].line, "PROC SCORE: TYPE= must be a name or a quoted string", .{});
            type_value = std.mem.trim(u8, t[i + 2].text, " ");
            i += 3;
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "predict")) {
            predict = true;
            i += 1;
        } else if (eq(option, "residual")) {
            residual = true;
            i += 1;
        } else if (eq(option, "nostd")) {
            nostd = true;
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // p.8908: "DATA= ... This option is required."
    if (name == null) return cx.diags.fail(error.ParseError, line(t, 0), "PROC SCORE: the DATA= option is required", .{});
    const raw = cx.lib.find(name.?) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC SCORE: input data set {s} not found", .{name.?});
    // p.8909: without SCORE=, the most recently created data set is used.
    const score = (if (score_name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC SCORE: SCORE= data set {s} not found", .{score_name orelse "_LAST_"});
    if (out == null) return gap(cx.diags, line(t, 0), "PROC SCORE: the automatic DATAn output data set (OUT= omitted) is not implemented (STAT-SCORE-004)", .{});

    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    var s: Spec = .{ .input = undefined, .score = score, .out = out, .type = type_value, .predict = predict, .residual = residual, .nostd = nostd };
    s.data_name = name.?;
    s.score_name = score_name orelse score.name;
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var vars: std.ArrayList([]const u8) = .empty;
    var ids: std.ArrayList(usize) = .empty;
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
            // p.8909: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            if (s.var_given) return gap(cx.diags, t[i].line, "PROC SCORE: more than one VAR statement is not verified", .{});
            s.var_given = true;
            if (end == i + 1) return invalid(cx, t, end);
            // p.8910: VAR variables must be in both data sets and numeric;
            // the list is resolved against the SCORE= data set.
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                const names = try lists.next(a, score, body, &j, cx.diags);
                for (names) |n| {
                    const si = score.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC SCORE: VAR variable {s} is not on the SCORE= data set", .{n});
                    const di = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC SCORE: VAR variable {s} is not on the DATA= data set", .{n});
                    if (score.columns.items[si].type != .num or ds.columns.items[di].type != .num) return cx.diags.fail(error.ParseError, l, "PROC SCORE: VAR variable {s} must be numeric", .{n});
                    var dup = false;
                    for (vars.items) |v| dup = dup or eq(v, n);
                    if (!dup) try vars.append(a, score.columns.items[si].name);
                }
            }
        } else if (eq(word, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            const body = t[i + 1 .. end];
            var j: usize = 0;
            while (j < body.len) {
                const l = body[j].line;
                const names = try lists.next(a, ds, body, &j, cx.diags);
                for (names) |n| {
                    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, l, "PROC SCORE: ID variable {s} is not on the DATA= data set", .{n});
                    if (!has(ids.items, ci)) try ids.append(a, ci);
                }
            }
        } else if (eq(word, "format") or eq(word, "label") or eq(word, "attrib")) {
            return gap(cx.diags, t[i].line, "PROC SCORE: a {s} statement inside the step is not implemented", .{word});
        } else if (eq(word, "where")) {
            // Applied to DATA= by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const pb = try bys.resolve(a, score, cx.diags);
    s.by_names = pb.names;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.ids = ids.items;
    s.vars = vars.items;
    return s;
}

fn trimmed(v: Value) []const u8 {
    return switch (v) {
        .str => |x| std.mem.trim(u8, x, " "),
        else => "",
    };
}
fn sameKey(x: []const Value, xc: []const usize, y: []const Value, yc: []const usize) bool {
    for (xc, yc) |i, j| {
        const p = x[i];
        const q = y[j];
        switch (p) {
            .num => |u| switch (q) {
                .num => |w| if (!(u == w or (std.math.isNan(u) and std.math.isNan(w) and @as(u64, @bitCast(u)) == @as(u64, @bitCast(w))))) return false,
                else => return false,
            },
            .str => if (q != .str or !std.mem.eql(u8, trimmed(p), trimmed(q))) return false,
        }
    }
    return true;
}

/// Coefficients of one SCORE= BY group (p.8909-8911).
const Group = struct {
    rep: ?[]const Value,
    /// Score variable names, in coefficient-row order.
    names: []const []const u8,
    /// Row-major names.len x vars.len; missing coefficients already 0.
    coef: []const f64,
    intercept: []const f64,
    mean: ?[]const f64 = null,
    std: ?[]const f64 = null,
};

fn buildGroup(cx: proc.ProcCtx, s: Spec, rows: []const []const Value, rep: ?[]const Value, vcols: []const usize, type_col: usize, name_col: usize, icpt: ?usize, l0: usize) diag.Error!Group {
    const a = cx.arena;
    const gap = proc.failGap;
    const p = vcols.len;
    var names: std.ArrayList([]const u8) = .empty;
    var coef: std.ArrayList(f64) = .empty;
    var intercept: std.ArrayList(f64) = .empty;
    var g: Group = .{ .rep = rep, .names = &.{}, .coef = &.{}, .intercept = &.{} };
    for (rows) |row| {
        const ty = trimmed(row[type_col]);
        const wanted = if (s.type) |w| eq(ty, w) else eq(ty, "SCORE");
        if (s.type == null and eq(ty, "USCORE")) return gap(cx.diags, l0, "PROC SCORE: _TYPE_='USCORE' coefficients (uncorrected standardization) are not implemented", .{});
        if (eq(ty, "USTD") and !s.nostd) return gap(cx.diags, l0, "PROC SCORE: _TYPE_='USTD' standardization is not implemented", .{});
        if (!s.nostd and (eq(ty, "MEAN") or eq(ty, "STD")) and !wanted) {
            const vals = try a.alloc(f64, p);
            for (vcols, vals) |ci, *v| v.* = row[ci].num;
            if (eq(ty, "MEAN")) {
                if (g.mean != null) return gap(cx.diags, l0, "PROC SCORE: more than one _TYPE_='MEAN' observation in a BY group is not verified", .{});
                g.mean = vals;
            } else {
                if (g.std != null) return gap(cx.diags, l0, "PROC SCORE: more than one _TYPE_='STD' observation in a BY group is not verified", .{});
                g.std = vals;
            }
            continue;
        }
        if (!wanted) continue;
        const nm = trimmed(row[name_col]);
        if (nm.len == 0) return gap(cx.diags, l0, "PROC SCORE: a scoring observation with a blank name is not verified", .{});
        for (names.items) |o| if (eq(o, nm)) return gap(cx.diags, l0, "PROC SCORE: two scoring observations named {s} in one BY group are not verified", .{nm});
        try names.append(a, nm);
        for (vcols) |ci| {
            const c = row[ci].num;
            const v = if (std.math.isNan(c)) 0 else if (s.predict and c == -1) 0 else c;
            try coef.append(a, v);
        }
        const ic: f64 = if (icpt) |ci| row[ci].num else 0;
        try intercept.append(a, if (std.math.isNan(ic)) 0 else ic);
    }
    if ((g.mean == null) != (g.std == null)) return gap(cx.diags, l0, "PROC SCORE: standardization with only one of the _TYPE_='MEAN' and _TYPE_='STD' observations is not verified", .{});
    if (g.std) |sd| for (sd, g.mean.?) |v, m| if (std.math.isNan(v) or std.math.isNan(m) or v == 0) return gap(cx.diags, l0, "PROC SCORE: standardization with a missing or zero MEAN/STD value is not verified", .{});
    if (names.items.len == 0) return gap(cx.diags, l0, "PROC SCORE: a SCORE= BY group without scoring coefficients is not verified", .{});
    g.names = names.items;
    g.coef = coef.items;
    g.intercept = intercept.items;
    return g;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    _ = out; // p.8911: "PROC SCORE produces an output data set but displays no output."
    const a = cx.arena;
    const gap = proc.failGap;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    const sc = s.score;
    const l0 = line(t, 0);
    if (s.predict and s.residual) return gap(cx.diags, l0, "PROC SCORE: PREDICT together with RESIDUAL is not verified", .{});

    // p.8909: _TYPE_ and either _NAME_ or _MODEL_.
    const type_col = sc.indexOf("_TYPE_") orelse return cx.diags.fail(error.ParseError, l0, "PROC SCORE: the SCORE= data set has no _TYPE_ variable", .{});
    const nm_col = sc.indexOf("_NAME_");
    const md_col = sc.indexOf("_MODEL_");
    if (nm_col != null and md_col != null) return gap(cx.diags, l0, "PROC SCORE: a SCORE= data set with both _NAME_ and _MODEL_ is not verified (STAT-SCORE-003)", .{});
    const name_col = nm_col orelse md_col orelse return cx.diags.fail(error.ParseError, l0, "PROC SCORE: the SCORE= data set has no _NAME_ or _MODEL_ variable", .{});
    if (sc.columns.items[type_col].type != .char or sc.columns.items[name_col].type != .char) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: _TYPE_ and _NAME_/_MODEL_ must be character variables", .{});

    // BY columns in both data sets (p.8910).
    const sby = try a.alloc(usize, s.by_names.len);
    for (s.by_names, sby) |n, *c| c.* = sc.indexOf(n).?;
    var present: usize = 0;
    const dby = try a.alloc(usize, s.by_names.len);
    for (s.by_names, dby) |n, *c| {
        if (ds.indexOf(n)) |ci| {
            c.* = ci;
            present += 1;
        }
    }
    const matched = present > 0;
    if (matched and present != s.by_names.len) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: the DATA= data set contains some but not all of the BY variables", .{});
    if (matched) for (sby, dby, s.by_names) |si, di, n| {
        const x = sc.columns.items[si];
        const y = ds.columns.items[di];
        const lx = x.len orelse 8;
        const ly = y.len orelse 8;
        if (x.type != y.type or (x.type == .char and lx != ly)) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: BY variable {s} does not have the same type and length in the DATA= and SCORE= data sets", .{n});
    };

    // VAR columns (p.8910): default = all numeric SCORE= variables.
    var names: std.ArrayList([]const u8) = .empty;
    if (s.var_given) {
        try names.appendSlice(a, s.vars);
    } else {
        for (sc.columns.items, 0..) |c, ci| {
            if (c.type != .num or has(sby, ci) or eq(c.name, "Intercept")) continue;
            if (ds.indexOf(c.name) == null) return gap(cx.diags, l0, "PROC SCORE: without a VAR statement, numeric SCORE= variable {s} is not on the DATA= data set; that case is not verified", .{c.name});
            if (ds.columns.items[ds.indexOf(c.name).?].type != .num) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: variable {s} must be numeric in the DATA= data set", .{c.name});
            try names.append(a, c.name);
        }
    }
    const p = names.items.len;
    if (p == 0) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: no numeric variables to score", .{});
    const svc = try a.alloc(usize, p);
    const dvc = try a.alloc(usize, p);
    for (names.items, svc, dvc) |n, *x, *y| {
        x.* = sc.indexOf(n).?;
        y.* = ds.indexOf(n).?;
    }
    // p.8911: the OUTEST= Intercept enters the scores. Only as a SCORE=
    // variable absent from DATA= and not listed in VAR.
    var icpt: ?usize = null;
    if (sc.indexOf("Intercept")) |ci| if (sc.columns.items[ci].type == .num) {
        var listed = false;
        for (names.items) |n| listed = listed or eq(n, "Intercept");
        if (listed or ds.indexOf("Intercept") != null) return gap(cx.diags, l0, "PROC SCORE: an Intercept variable on the DATA= data set or in the VAR list is not verified (STAT-SCORE-003)", .{});
        icpt = ci;
    };

    // Coefficient groups of the SCORE= data set.
    const sgroups = try by.checkedSlices(a, sc, sby, s.by_desc, s.notsorted, cx.diags);
    var groups: std.ArrayList(Group) = .empty;
    for (sgroups) |sg| try groups.append(a, try buildGroup(cx, s, sg.rows, sg.rep, svc, type_col, name_col, icpt, l0));
    if (groups.items.len == 0) return gap(cx.diags, l0, "PROC SCORE: an empty SCORE= data set is not verified", .{});
    const score_names = groups.items[0].names;
    for (groups.items[1..]) |g| {
        var same = g.names.len == score_names.len;
        if (same) for (g.names, score_names) |x, y| {
            same = same and eq(x, y);
        };
        if (!same) return gap(cx.diags, l0, "PROC SCORE: BY groups with different score variables are not verified", .{});
    }

    // Output layout (p.8911): ID variables (else all DATA= variables), the
    // BY variables, then the new score variables.
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, s.out.?);
    var keep: std.ArrayList(usize) = .empty;
    if (s.ids.len > 0) try keep.appendSlice(a, s.ids) else for (0..ds.columns.items.len) |ci| try keep.append(a, ci);
    for (keep.items) |ci| _ = try o.addColumnLike(ds.columns.items[ci].name, ds.columns.items[ci]);
    // BY variables not already carried from DATA= (taken from SCORE=).
    var extra_by: std.ArrayList(usize) = .empty; // indices into sby
    for (s.by_names, 0..) |n, k| {
        if (o.indexOf(n) != null) continue;
        if (matched) {
            _ = try o.addColumnLike(ds.columns.items[dby[k]].name, ds.columns.items[dby[k]]);
        } else _ = try o.addColumnLike(sc.columns.items[sby[k]].name, sc.columns.items[sby[k]]);
        try extra_by.append(a, k);
    }
    for (score_names) |n| {
        if (o.indexOf(n) != null) return gap(cx.diags, l0, "PROC SCORE: score variable {s} already exists in the output data set; the replacement rule is not verified (STAT-SCORE-004)", .{n});
        _ = try o.addColumn(n, .num);
    }
    const width = o.columns.items.len;
    const ns = score_names.len;

    const dgroups = try by.checkedSlices(a, ds, if (matched) dby else &.{}, if (matched) s.by_desc else &.{}, s.notsorted, cx.diags);
    var gi: usize = 0;
    var gk: usize = 0;
    while (true) {
        // Pair (DATA= rows, coefficient group).
        var rows: []const []const Value = &.{};
        var g: Group = undefined;
        if (matched) {
            if (gi >= dgroups.len) break;
            const dg = dgroups[gi];
            gi += 1;
            if (dg.rows.len == 0) continue;
            const first_try = gk;
            while (gk < groups.items.len and !sameKey(dg.rep.?, dby, groups.items[gk].rep.?, sby)) gk += 1;
            if (gk >= groups.items.len) return cx.diags.fail(error.ParseError, l0, "PROC SCORE: a BY group of the DATA= data set does not appear (in the same order) in the SCORE= data set", .{});
            if (s.notsorted and gk != first_try) return gap(cx.diags, l0, "PROC SCORE: NOTSORTED BY groups present in SCORE= but not in DATA= are not verified", .{});
            g = groups.items[gk];
            gk += 1;
            rows = dg.rows;
        } else {
            // p.8910: no BY variable on DATA= -> every coefficient group scores
            // the entire DATA= data set.
            if (gk >= groups.items.len) break;
            g = groups.items[gk];
            gk += 1;
            rows = ds.rows.items;
        }
        const values = try a.alloc(Value, width);
        for (rows) |row| {
            var c: usize = 0;
            for (keep.items) |ci| {
                values[c] = row[ci];
                c += 1;
            }
            for (extra_by.items) |k| {
                values[c] = if (matched) row[dby[k]] else g.rep.?[sby[k]];
                c += 1;
            }
            for (0..ns) |k| {
                var sum: f64 = g.intercept[k];
                var missing = false;
                for (dvc, 0..) |ci, j| {
                    const w = g.coef[k * p + j];
                    if (w == 0) continue; // p.8911: a 0 coefficient tolerates a missing value
                    const x = row[ci].num;
                    if (std.math.isNan(x)) {
                        missing = true;
                        break;
                    }
                    const z = if (g.mean) |m| (x - m[j]) / g.std.?[j] else x;
                    sum += w * z;
                }
                values[c + k] = if (missing) Value.missing else .{ .num = if (s.residual) -sum else sum };
            }
            try o.appendRow(values);
        }
    }

    const member = s.out.?;
    try cx.lib.put(member, o);
    // ponytail: a one-level name is reported under WORK (no USER libref lookup).
    const upper = try std.ascii.allocUpperString(a, member);
    const prefix: []const u8 = if (std.mem.indexOfScalar(u8, member, '.') == null) "WORK." else "";
    try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ prefix, upper, o.rows.items.len, o.columns.items.len });
}

test {
    _ = @import("score_tests.zig");
}
