//! Shared constructed effects of the EFFECT statement (STAT-COMMON-021):
//! `EFFECT name = COLLECTION (var-list </ DETAILS>)` and
//! `EFFECT name = LAG (variable / WITHIN=variable|(var-list) PERIOD=variable
//! <NLAG=n DESIGNROLE=variable DETAILS>)`.
//! S154 Chapter 20, physical pp.424-425 (EFFECT statement, Table 20.12),
//! p.426 (Collection Effects), pp.426-429 (Lag Effects).
//! Parsing and column construction only; the column block is the shared
//! `effect_constructed.Built` type so a consuming PROC appends every
//! constructed effect the same way.
//! ponytail: standalone like effect_constructed.zig (COMMON-022); the DETAILS
//! tables are parsed into the spec but not rendered (their layout is not on
//! the cited pages) — a consumer must gap a DETAILS request.
//! ponytail: behaviour the cited pages do not state (a repeated option, a
//! repeated variable, a numeric PERIOD= whose formatted order differs from
//! its numeric order, missing WITHIN=/PERIOD=/DESIGNROLE= values, a non-CLASS
//! lagged variable) is a D-009 gap, never a guess.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const levels = @import("class_levels.zig");
const varlists = @import("variable_lists.zig");
const ec = @import("effect_constructed.zig");
const A = std.mem.Allocator;
const D = *diag.Diagnostics;
const Tok = lex.Token;
pub const Built = ec.Built;
const nan = std.math.nan(f64);

pub const Collection = struct {
    vars: []const usize,
    details: bool = false,
};
pub const Lag = struct {
    variable: usize,
    within: []const usize,
    period: usize,
    nlag: usize = 1,
    designrole: ?usize = null,
    details: bool = false,
};
pub const Body = union(enum) { collection: Collection, lag: Lag };
pub const Spec = struct { name: []const u8, body: Body };

/// True when `word` is an effect type this module owns.
pub fn owns(word: []const u8) bool {
    return std.ascii.eqlIgnoreCase(word, "collection") or std.ascii.eqlIgnoreCase(word, "lag");
}

fn user(d: D, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return d.fail(error.ParseError, line, "EFFECT: " ++ fmt, args);
}
fn gap(d: D, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(d, line, "EFFECT: " ++ fmt, args);
}
fn is(t: []const Tok, k: usize, word: []const u8) bool {
    return k < t.len and t[k].tag == .name and std.ascii.eqlIgnoreCase(t[k].text, word);
}
fn tag(t: []const Tok, k: usize, want: lex.Tag) bool {
    return k < t.len and t[k].tag == want;
}
fn once(d: D, line: usize, seen: *bool, comptime option: []const u8) diag.Error!void {
    if (seen.*) return gap(d, line, "the " ++ option ++ " option is repeated; SAS behaviour for a repeated option is not verified", .{});
    seen.* = true;
}
fn isClass(class_columns: []const usize, ci: usize) bool {
    return std.mem.indexOfScalar(usize, class_columns, ci) != null;
}
fn variable(d: D, ds: *const Dataset, t: []const Tok, k: usize, line: usize, comptime option: []const u8) diag.Error!usize {
    if (!tag(t, k, .name)) return user(d, line, option ++ " requires a variable name", .{});
    return ds.indexOf(t[k].text) orelse d.fail(error.ParseError, line, "Variable {s} not found.", .{t[k].text});
}

/// `t` is the statement after the EFFECT keyword (a trailing `;` is ignored).
/// `class_columns` are the CLASS variables, `defined` the earlier EFFECT names.
pub fn parse(a: A, d: D, ds: *const Dataset, class_columns: []const usize, defined: []const []const u8, tokens: []const Tok, line: usize) diag.Error!Spec {
    var t = tokens;
    while (t.len > 0 and (t[t.len - 1].tag == .semicolon or t[t.len - 1].tag == .eof)) t = t[0 .. t.len - 1];
    if (t.len < 5 or t[0].tag != .name or t[1].tag != .eq or t[2].tag != .name or t[3].tag != .lparen or t[t.len - 1].tag != .rparen)
        return user(d, line, "expected EFFECT effect-name = effect-type (var-list </ effect-options>)", .{});
    const name = t[0].text;
    if (ds.indexOf(name) != null) return user(d, line, "the effect name {s} cannot be the name of a variable in the input data set", .{name});
    for (defined) |other| if (std.ascii.eqlIgnoreCase(other, name)) return user(d, line, "the effect name {s} can appear in only one EFFECT statement", .{name});
    if (!owns(t[2].text)) return user(d, line, "{s} is not a COLLECTION or LAG effect type", .{t[2].text});
    const lag = is(t, 2, "lag");
    const inner = t[4 .. t.len - 1];
    var slash = inner.len;
    for (inner, 0..) |tok, i| if (tok.tag == .slash) {
        slash = i;
        break;
    };
    const vt = inner[0..slash];
    const o = if (slash < inner.len) inner[slash + 1 ..] else inner[inner.len..];
    var vars: std.ArrayList(usize) = .empty;
    var at: usize = 0;
    while (at < vt.len) {
        const names = try varlists.next(a, ds, vt, &at, d);
        for (names) |n| {
            const ci = ds.indexOf(n) orelse return d.fail(error.ParseError, line, "Variable {s} not found.", .{n});
            if (std.mem.indexOfScalar(usize, vars.items, ci) != null) return gap(d, line, "variable {s} is listed more than once; SAS behaviour is not verified", .{n});
            try vars.append(a, ci);
        }
    }
    if (vars.items.len == 0) return user(d, line, "the variable list is empty", .{});
    if (!lag) {
        var c: Collection = .{ .vars = vars.items };
        var k: usize = 0;
        while (k < o.len) : (k += 1) {
            if (!is(o, k, "details")) return user(d, line, "invalid collection effect option {s}; only DETAILS is allowed", .{o[k].text});
            try once(d, line, &c.details, "DETAILS");
        }
        for (c.vars) |ci| if (ds.columns.items[ci].type != .num and !isClass(class_columns, ci))
            return user(d, line, "character collection effect variable {s} must appear in the CLASS statement", .{ds.columns.items[ci].name});
        return .{ .name = name, .body = .{ .collection = c } };
    }
    if (vars.items.len != 1) return user(d, line, "a lag effect requires exactly one variable", .{});
    // ponytail: p.426 defines a lag effect as a classification effect; a
    // continuous lagged variable is not described, so it is refused loudly.
    if (!isClass(class_columns, vars.items[0])) return gap(d, line, "lag effect variable {s} is not a CLASS variable; a continuous lagged variable is not verified", .{ds.columns.items[vars.items[0]].name});
    var g: Lag = .{ .variable = vars.items[0], .within = &.{}, .period = 0 };
    var s_within = false;
    var s_period = false;
    var s_nlag = false;
    var s_role = false;
    var k: usize = 0;
    while (k < o.len) {
        if (is(o, k, "details")) {
            try once(d, line, &g.details, "DETAILS");
            k += 1;
        } else if (is(o, k, "period")) {
            try once(d, line, &s_period, "PERIOD=");
            if (!tag(o, k + 1, .eq)) return user(d, line, "PERIOD= requires a variable name", .{});
            g.period = try variable(d, ds, o, k + 2, line, "PERIOD=");
            k += 3;
        } else if (is(o, k, "designrole")) {
            try once(d, line, &s_role, "DESIGNROLE=");
            if (!tag(o, k + 1, .eq)) return user(d, line, "DESIGNROLE= requires a variable name", .{});
            const ci = try variable(d, ds, o, k + 2, line, "DESIGNROLE=");
            if (ds.columns.items[ci].type != .num) return user(d, line, "DESIGNROLE= variable {s} must be numeric", .{ds.columns.items[ci].name});
            g.designrole = ci;
            k += 3;
        } else if (is(o, k, "nlag")) {
            try once(d, line, &s_nlag, "NLAG=");
            if (!tag(o, k + 1, .eq) or !tag(o, k + 2, .number)) return user(d, line, "NLAG= requires a positive integer", .{});
            const v = std.fmt.parseFloat(f64, o[k + 2].text) catch return user(d, line, "NLAG= requires a positive integer", .{});
            if (!(v >= 1) or v != @trunc(v)) return user(d, line, "NLAG= requires a positive integer", .{});
            if (v > 100000) return gap(d, line, "NLAG={d} is beyond the supported maximum of 100000", .{v});
            g.nlag = @intFromFloat(v);
            k += 3;
        } else if (is(o, k, "within")) {
            try once(d, line, &s_within, "WITHIN=");
            if (!tag(o, k + 1, .eq)) return user(d, line, "WITHIN= requires a variable or a parenthesized variable list", .{});
            var list: std.ArrayList(usize) = .empty;
            if (tag(o, k + 2, .lparen)) {
                var close = k + 3;
                while (close < o.len and !tag(o, close, .rparen)) close += 1;
                if (close >= o.len) return user(d, line, "WITHIN=( is not closed", .{});
                const wt = o[k + 3 .. close];
                var w: usize = 0;
                while (w < wt.len) {
                    for (try varlists.next(a, ds, wt, &w, d)) |n| {
                        const ci = ds.indexOf(n) orelse return d.fail(error.ParseError, line, "Variable {s} not found.", .{n});
                        if (std.mem.indexOfScalar(usize, list.items, ci) != null) return gap(d, line, "WITHIN= variable {s} is listed more than once; SAS behaviour is not verified", .{n});
                        try list.append(a, ci);
                    }
                }
                if (list.items.len == 0) return user(d, line, "the WITHIN= variable list is empty", .{});
                k = close + 1;
            } else {
                try list.append(a, try variable(d, ds, o, k + 2, line, "WITHIN="));
                k += 3;
            }
            g.within = list.items;
        } else return user(d, line, "invalid lag effect option {s}", .{if (k < o.len) o[k].text else "<end>"});
    }
    if (!s_within) return user(d, line, "the WITHIN= option is required for a lag effect", .{});
    if (!s_period) return user(d, line, "the PERIOD= option is required for a lag effect", .{});
    return .{ .name = name, .body = .{ .lag = g } };
}

fn missingValue(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

/// Collection columns, p.426: the design columns of the constituents. A
/// continuous variable contributes its value; a CLASS variable its GLM
/// indicator columns, one per sorted formatted level (missing levels
/// excluded; the last is aliased with the intercept in a GLM fit). A missing
/// constituent makes every column of the row missing (NaN).
/// Order and names follow SAS/STAT 15.4 as observed (OUTDESIGN= and DETAILS
/// of PROC GLMSELECT, recorded in the COMMON-021 tracker note): the continuous
/// constituents first in definition order, then the CLASS constituents in
/// definition order, named `var` and `var:level`; p.426's "in the order in
/// which they appear" holds within each group. `effects` is the collection
/// name throughout.
pub fn buildCollection(a: A, ds: *const Dataset, rows: []const []const Value, class_columns: []const usize, name: []const u8, c: Collection) diag.Error!Built {
    const n = rows.len;
    var names: std.ArrayList([]const u8) = .empty;
    var order: std.ArrayList(usize) = .empty;
    for (c.vars) |ci| if (!isClass(class_columns, ci)) try order.append(a, ci);
    for (c.vars) |ci| if (isClass(class_columns, ci)) try order.append(a, ci);
    const maps = try a.alloc(?levels.Levels, c.vars.len);
    for (order.items, maps) |ci, *m| {
        if (isClass(class_columns, ci)) {
            m.* = try levels.build(a, ds, rows, ci, .{ .order = .formatted, .missing = .exclude });
            for (m.*.?.levels) |lv| try names.append(a, try std.fmt.allocPrint(a, "{s}:{s}", .{ ds.columns.items[ci].name, lv.label }));
        } else {
            m.* = null;
            try names.append(a, ds.columns.items[ci].name);
        }
    }
    const p = names.items.len;
    const x = try a.alloc(f64, n * p);
    for (rows, 0..) |row, i| {
        var col: usize = 0;
        var bad = false;
        for (order.items, maps) |ci, m| {
            if (m) |lv| {
                const li = lv.row_to_level[i];
                for (0..lv.levels.len) |l| x[i * p + col + l] = if (li != null and li.? == l) 1 else 0;
                if (li == null) bad = true;
                col += lv.levels.len;
            } else {
                const v = row[ci].num;
                x[i * p + col] = v;
                if (std.math.isNan(v)) bad = true;
                col += 1;
            }
        }
        if (bad) @memset(x[i * p .. (i + 1) * p], nan);
    }
    const effects = try a.alloc([]const u8, p);
    @memset(effects, name);
    return .{ .n = n, .p = p, .x = x, .names = names.items, .effects = effects };
}

pub const LagBuilt = struct {
    built: Built,
    /// Per row: true when the observation belongs to the first DESIGNROLE=
    /// group (nonzero, or every row without DESIGNROLE=), the design that is
    /// used to fit the model; false rows use the scoring design.
    fit_row: []const bool,
};

/// Lag columns, pp.426-429: per subject (unique formatted WITHIN= values) and
/// period (sorted unique formatted PERIOD= values), the row at period index
/// p takes the GLM indicator columns of the lagged variable at period p-NLAG
/// of the same subject; rows at periods <= NLAG are 0; a missing lagged value
/// or an absent lagged observation gives missing (NaN) columns. At most one
/// observation per subject and period is allowed. Each DESIGNROLE= group forms
/// its own lag design. Column names are `<effect>_<level>`.
pub fn buildLag(a: A, d: D, ds: *const Dataset, rows: []const []const Value, name: []const u8, g: Lag, line: usize) diag.Error!LagBuilt {
    const n = rows.len;
    const lv = try levels.build(a, ds, rows, g.variable, .{ .order = .formatted, .missing = .exclude });
    const per = try levels.build(a, ds, rows, g.period, .{ .order = .formatted, .missing = .exclude });
    if (ds.columns.items[g.period].type == .num) {
        for (per.levels, 0..) |level, k| if (k > 0 and !(level.value.num > per.levels[k - 1].value.num))
            return gap(d, line, "PERIOD= variable {s}: formatted order differs from numeric order; SAS ordering is not verified", .{ds.columns.items[g.period].name});
    }
    const fit_row = try a.alloc(bool, n);
    const subject = try a.alloc([]const u8, n);
    for (rows, 0..) |row, i| {
        if (per.row_to_level[i] == null) return gap(d, line, "a missing PERIOD= value in a lag effect is not verified", .{});
        var key: std.ArrayList(u8) = .empty;
        for (g.within) |ci| {
            if (missingValue(row[ci])) return gap(d, line, "a missing WITHIN= value in a lag effect is not verified", .{});
            const one = try levels.buildValues(a, &.{row[ci]}, ds.columns.items[ci], .{});
            try key.appendSlice(a, one.levels[0].label);
            try key.append(a, 0);
        }
        subject[i] = key.items;
        fit_row[i] = true;
        if (g.designrole) |ci| {
            const v = row[ci].num;
            if (std.math.isNan(v)) return gap(d, line, "a missing DESIGNROLE= value is not verified", .{});
            fit_row[i] = v != 0;
        }
    }
    // Valid lag design: at most one observation per subject and period.
    for (0..n) |i| for (0..i) |j| {
        if (fit_row[i] == fit_row[j] and per.row_to_level[i].? == per.row_to_level[j].? and std.mem.eql(u8, subject[i], subject[j]))
            return d.fail(error.ParseError, line, "EFFECT {s}: invalid lag design; subject has more than one observation in period {s}", .{ name, per.levels[per.row_to_level[i].?].label });
    };
    const p = lv.levels.len;
    const x = try a.alloc(f64, n * p);
    for (0..n) |i| {
        const out = x[i * p .. (i + 1) * p];
        const pi = per.row_to_level[i].?;
        if (pi < g.nlag) {
            @memset(out, 0);
            continue;
        }
        @memset(out, nan);
        for (0..n) |j| {
            if (fit_row[j] != fit_row[i] or per.row_to_level[j].? != pi - g.nlag or !std.mem.eql(u8, subject[i], subject[j])) continue;
            if (lv.row_to_level[j]) |l| {
                @memset(out, 0);
                out[l] = 1;
            }
            break;
        }
    }
    const names = try a.alloc([]const u8, p);
    for (lv.levels, names) |level, *nm| nm.* = try std.fmt.allocPrint(a, "{s}_{s}", .{ name, level.label });
    const effects = try a.alloc([]const u8, p);
    @memset(effects, name);
    return .{ .built = .{ .n = n, .p = p, .x = x, .names = names, .effects = effects }, .fit_row = fit_row };
}

/// DESIGNROLE= applicability (SAS/STAT 15.4 as observed, PROC GLMSELECT):
/// the zero group is the scoring design, so a zero DESIGNROLE= value on an
/// observation with a nonmissing response is a user error.
pub fn checkDesignRole(d: D, ds: *const Dataset, rows: []const []const Value, g: Lag, response: usize, name: []const u8, line: usize) diag.Error!void {
    const ci = g.designrole orelse return;
    for (rows) |row| {
        if (row[ci].num == 0 and !missingValue(row[response]))
            return d.fail(error.ParseError, line, "In the EFFECT {s} = LAG statement, zero values of the DESIGNROLE variable {s} must correspond to observations where the response value is missing.", .{ name, ds.columns.items[ci].name });
    }
}

test {
    _ = @import("effect_collection_tests.zig");
}
