//! Shared constructed effects of the EFFECT statement (STAT-COMMON-022):
//! `EFFECT name = POLYNOMIAL|POLY (var-list </ options>)` and
//! `EFFECT name = MULTIMEMBER|MM (var-list </ options>)`.
//! S154 Chapter 20, physical pp.424-425 (EFFECT statement), 429-431
//! (Multimember Effects), 431-434 (Polynomial Effects, Table 20.13).
//! Parsing and column construction only: a typed spec and a typed column block
//! (names, owning effects, dimensions, values). Rendering of the DETAILS tables
//! and adoption by a MODEL statement belong to the consuming PROC tickets.
//! ponytail: standalone — design_matrix.zig is not touched; a PROC that adopts
//! this appends `Built` columns itself. COLLECTION, LAG and SPLINE are loud gaps.
//! ponytail: behaviour the cited pages do not state (a repeated option, a
//! repeated variable, EXPAND with EXPONENT, a zero scale, a missing WEIGHT=
//! value, numeric multimember variables) is a D-009 gap, never a guess.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const levels = @import("class_levels.zig");
const varlists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const D = *diag.Diagnostics;
const Tok = lex.Token;

pub const Method = enum { range, moments, wmoments };
pub const Mode = enum { center, centerscale, none, scale };
pub const Standardize = struct { method: Method = .range, prefix: []const u8 = "s_", mode: Mode = .centerscale };
pub const Polynomial = struct {
    vars: []const usize,
    degree: usize = 1,
    /// Maximum exponent of one variable in a term; defaults to `degree`.
    mdegree: usize = 1,
    standardize: ?Standardize = null,
    /// false = NOSEPARATE: one effect with many parameters.
    separate: bool = true,
    details: bool = false,
    expand: bool = false,
    exponent: []const u8 = "^",
    include_name: bool = false,
    product: []const u8 = "*",
};
pub const Multimember = struct {
    vars: []const usize,
    /// Empty, or one numeric column per member variable (WEIGHT=).
    weights: []const usize = &.{},
    noeffect: bool = false,
    stdize: bool = false,
    details: bool = false,
};
pub const Body = union(enum) { polynomial: Polynomial, multimember: Multimember };
pub const Spec = struct { name: []const u8, body: Body };

/// Row-major n*p block. NaN is a missing design value (the observation cannot
/// be used). `names` are the parameter labels; `effects` is the model effect
/// that owns each column (the term itself, or the EFFECT name).
pub const Built = struct {
    n: usize,
    p: usize,
    x: []const f64,
    names: []const []const u8,
    effects: []const []const u8,
    /// Polynomial only: p * vars.len exponents, and the center/scale applied to
    /// each variable (0 and 1 when that part of the standardization is off).
    exponents: []const usize = &.{},
    centers: []const f64 = &.{},
    scales: []const f64 = &.{},
    pub fn at(self: Built, row: usize, col: usize) f64 {
        return self.x[row * self.p + col];
    }
};

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
fn positive(d: D, t: []const Tok, k: usize, line: usize, comptime option: []const u8) diag.Error!usize {
    if (!tag(t, k + 1, .eq) or !tag(t, k + 2, .number)) return user(d, line, option ++ "= requires a positive integer", .{});
    const v = std.fmt.parseFloat(f64, t[k + 2].text) catch return user(d, line, option ++ "= requires a positive integer", .{});
    if (!(v >= 1) or v != @trunc(v)) return user(d, line, option ++ "= requires a positive integer", .{});
    // ponytail: 64 is far above "a small integer, such as 1, 2, or 3"; larger is refused loudly.
    if (v > 64) return gap(d, line, option ++ "={d} is beyond the supported maximum of 64", .{v});
    return @intFromFloat(v);
}
fn text(tok: Tok) []const u8 {
    return if (tok.empty_quoted_literal) "" else tok.text;
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
    const poly = is(t, 2, "polynomial") or is(t, 2, "poly");
    const mm = is(t, 2, "multimember") or is(t, 2, "mm");
    if (!poly and !mm) {
        if (is(t, 2, "collection") or is(t, 2, "lag") or is(t, 2, "spline")) return gap(d, line, "the {s} effect type is not implemented", .{t[2].text});
        return user(d, line, "{s} is not an effect type", .{t[2].text});
    }
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
            const class = std.mem.indexOfScalar(usize, class_columns, ci) != null;
            const col = ds.columns.items[ci];
            if (poly and col.type != .num) return user(d, line, "polynomial effect variable {s} must be numeric", .{col.name});
            if (poly and class) return user(d, line, "polynomial effect variable {s} is a CLASS variable; it must be continuous", .{col.name});
            if (mm and !class) return user(d, line, "multimember effect variable {s} must appear in the CLASS statement", .{col.name});
            try vars.append(a, ci);
        }
    }
    if (vars.items.len == 0) return user(d, line, "the variable list is empty", .{});
    if (poly) return .{ .name = name, .body = .{ .polynomial = try polyOptions(d, vars.items, o, line) } };
    return .{ .name = name, .body = .{ .multimember = try mmOptions(a, d, ds, vars.items, o, line) } };
}

const StyleSeen = struct { expand: bool = false, exponent: bool = false, include: bool = false, product: bool = false };
fn styleOpt(d: D, o: []const Tok, k: *usize, p: *Polynomial, seen: *StyleSeen, line: usize) diag.Error!void {
    if (is(o, k.*, "expand")) {
        try once(d, line, &seen.expand, "LABELSTYLE EXPAND");
        p.expand = true;
        k.* += 1;
    } else if (is(o, k.*, "exponent")) {
        try once(d, line, &seen.exponent, "LABELSTYLE EXPONENT");
        k.* += 1;
        if (tag(o, k.*, .eq)) {
            if (!tag(o, k.* + 1, .string)) return user(d, line, "EXPONENT= requires a quoted string", .{});
            p.exponent = text(o[k.* + 1]);
            k.* += 2;
        }
    } else if (is(o, k.*, "includename")) {
        try once(d, line, &seen.include, "LABELSTYLE INCLUDENAME");
        p.include_name = true;
        k.* += 1;
    } else if (is(o, k.*, "productsymbol")) {
        try once(d, line, &seen.product, "LABELSTYLE PRODUCTSYMBOL");
        if (!tag(o, k.* + 1, .eq)) return user(d, line, "PRODUCTSYMBOL= requires NONE or a quoted string", .{});
        if (is(o, k.* + 2, "none")) {
            p.product = "";
        } else if (tag(o, k.* + 2, .string)) {
            p.product = text(o[k.* + 2]);
        } else return user(d, line, "PRODUCTSYMBOL= requires NONE or a quoted string", .{});
        k.* += 3;
    } else return user(d, line, "invalid LABELSTYLE= style option", .{});
    if (seen.expand and seen.exponent) return gap(d, line, "LABELSTYLE with both EXPAND and EXPONENT is not verified", .{});
}

fn polyOptions(d: D, vars: []const usize, o: []const Tok, line: usize) diag.Error!Polynomial {
    var p: Polynomial = .{ .vars = vars };
    var mdegree: ?usize = null;
    var s_degree = false;
    var s_mdegree = false;
    var s_details = false;
    var s_nosep = false;
    var s_label = false;
    var s_std = false;
    var style: StyleSeen = .{};
    var k: usize = 0;
    while (k < o.len) {
        if (is(o, k, "degree")) {
            try once(d, line, &s_degree, "DEGREE=");
            p.degree = try positive(d, o, k, line, "DEGREE");
            k += 3;
        } else if (is(o, k, "mdegree")) {
            try once(d, line, &s_mdegree, "MDEGREE=");
            mdegree = try positive(d, o, k, line, "MDEGREE");
            k += 3;
        } else if (is(o, k, "details")) {
            try once(d, line, &s_details, "DETAILS");
            p.details = true;
            k += 1;
        } else if (is(o, k, "noseparate")) {
            try once(d, line, &s_nosep, "NOSEPARATE");
            p.separate = false;
            k += 1;
        } else if (is(o, k, "labelstyle")) {
            try once(d, line, &s_label, "LABELSTYLE=");
            if (!tag(o, k + 1, .eq)) return user(d, line, "LABELSTYLE= requires a style option", .{});
            k += 2;
            if (tag(o, k, .lparen)) {
                k += 1;
                if (tag(o, k, .rparen)) return user(d, line, "LABELSTYLE=() requires a style option", .{});
                while (!tag(o, k, .rparen)) {
                    if (k >= o.len) return user(d, line, "LABELSTYLE=( is missing its closing parenthesis", .{});
                    try styleOpt(d, o, &k, &p, &style, line);
                }
                k += 1;
            } else try styleOpt(d, o, &k, &p, &style, line);
        } else if (is(o, k, "standardize")) {
            try once(d, line, &s_std, "STANDARDIZE");
            var s: Standardize = .{};
            var s_method = false;
            var s_prefix = false;
            k += 1;
            if (tag(o, k, .lparen)) {
                k += 1;
                while (!tag(o, k, .rparen)) {
                    if (is(o, k, "method") and tag(o, k + 1, .eq)) {
                        try once(d, line, &s_method, "STANDARDIZE METHOD=");
                        s.method = if (is(o, k + 2, "moments")) .moments else if (is(o, k + 2, "range")) .range else if (is(o, k + 2, "wmoments")) .wmoments else return user(d, line, "METHOD= requires MOMENTS, RANGE or WMOMENTS", .{});
                    } else if (is(o, k, "prefix") and tag(o, k + 1, .eq)) {
                        try once(d, line, &s_prefix, "STANDARDIZE PREFIX=");
                        if (is(o, k + 2, "none")) {
                            s.prefix = "";
                        } else if (tag(o, k + 2, .string)) {
                            s.prefix = text(o[k + 2]);
                        } else return user(d, line, "PREFIX= requires NONE or a quoted string", .{});
                    } else return user(d, line, "invalid STANDARDIZE centering/scaling option", .{});
                    k += 3;
                }
                k += 1;
            }
            if (tag(o, k, .eq)) {
                s.mode = if (is(o, k + 1, "center")) .center else if (is(o, k + 1, "centerscale")) .centerscale else if (is(o, k + 1, "none")) .none else if (is(o, k + 1, "scale")) .scale else return user(d, line, "STANDARDIZE= requires CENTER, CENTERSCALE, NONE or SCALE", .{});
                k += 2;
            }
            p.standardize = s;
        } else return user(d, line, "invalid polynomial effect option {s}", .{if (o[k].text.len > 0) o[k].text else @tagName(o[k].tag)});
    }
    p.mdegree = mdegree orelse p.degree;
    return p;
}

fn mmOptions(a: A, d: D, ds: *const Dataset, vars: []const usize, o: []const Tok, line: usize) diag.Error!Multimember {
    var m: Multimember = .{ .vars = vars };
    var s_details = false;
    var s_noeffect = false;
    var s_stdize = false;
    var s_weight = false;
    var k: usize = 0;
    while (k < o.len) {
        if (is(o, k, "details")) {
            try once(d, line, &s_details, "DETAILS");
            m.details = true;
            k += 1;
        } else if (is(o, k, "noeffect")) {
            try once(d, line, &s_noeffect, "NOEFFECT");
            m.noeffect = true;
            k += 1;
        } else if (is(o, k, "stdize")) {
            try once(d, line, &s_stdize, "STDIZE");
            m.stdize = true;
            k += 1;
        } else if (is(o, k, "weight")) {
            try once(d, line, &s_weight, "WEIGHT=");
            if (!tag(o, k + 1, .eq)) return user(d, line, "WEIGHT= requires a list of numeric variables", .{});
            k += 2;
            const paren = tag(o, k, .lparen);
            if (paren) k += 1;
            var w: std.ArrayList(usize) = .empty;
            // Without parentheses the list ends once it has one weight per member.
            while (tag(o, k, .name) and (paren or w.items.len < vars.len)) : (k += 1) {
                const ci = ds.indexOf(o[k].text) orelse return d.fail(error.ParseError, line, "Variable {s} not found.", .{o[k].text});
                if (ds.columns.items[ci].type != .num) return user(d, line, "WEIGHT= variable {s} must be numeric", .{ds.columns.items[ci].name});
                try w.append(a, ci);
            }
            if (paren) {
                if (!tag(o, k, .rparen)) return user(d, line, "WEIGHT=( is missing its closing parenthesis", .{});
                k += 1;
            }
            if (w.items.len != vars.len) return user(d, line, "the number of WEIGHT= variables ({d}) must match the number of classification variables ({d})", .{ w.items.len, vars.len });
            m.weights = w.items;
        } else return user(d, line, "invalid multimember effect option {s}", .{if (o[k].text.len > 0) o[k].text else @tagName(o[k].tag)});
    }
    return m;
}

fn num(row: []const Value, ci: usize) diag.Error!f64 {
    if (ci >= row.len) return error.ExecError;
    return switch (row[ci]) {
        .num => |v| v,
        .str => error.ExecError,
    };
}

// Terms of total degree `left` over vars[idx..], first variable's exponent
// descending: x1^2, x1*x2, x2^2 (p.431 example; p.432 MDEGREE example).
fn terms(a: A, out: *std.ArrayList(usize), exps: []usize, idx: usize, left: usize, mdegree: usize) A.Error!void {
    if (idx == exps.len - 1) {
        if (left > mdegree) return;
        exps[idx] = left;
        try out.appendSlice(a, exps);
        return;
    }
    var e = @min(left, mdegree);
    while (true) : (e -= 1) {
        exps[idx] = e;
        try terms(a, out, exps, idx + 1, left - e, mdegree);
        if (e == 0) break;
    }
}

/// `rows` are the observations of the analysis. `freq`/`weight` (aligned to
/// `rows`) enter only the MOMENTS/WMOMENTS estimates of Table 20.13; rows whose
/// frequency is missing or < 1, or whose weight is missing or <= 0, are left
/// out of those estimates. ponytail: the caller owns PROC-specific FREQ
/// truncation and which observations are "used in the analysis".
pub fn buildPolynomial(a: A, d: D, ds: *const Dataset, rows: []const []const Value, name: []const u8, p: Polynomial, freq: ?[]const f64, weight: ?[]const f64, line: usize) diag.Error!Built {
    const nv = p.vars.len;
    if (nv == 0 or p.degree == 0 or p.mdegree == 0) return error.ExecError;
    if (freq) |f| if (f.len != rows.len) return error.ExecError;
    if (weight) |w| if (w.len != rows.len) return error.ExecError;
    var ex: std.ArrayList(usize) = .empty;
    const scratch = try a.alloc(usize, nv);
    for (1..p.degree + 1) |deg| {
        try terms(a, &ex, scratch, 0, deg, p.mdegree);
        if (ex.items.len / nv > 100_000) return gap(d, line, "the polynomial has more than 100000 terms", .{});
    }
    const np = ex.items.len / nv;
    const n = rows.len;
    // A row with a missing polynomial variable has missing columns.
    const complete = try a.alloc(bool, n);
    for (rows, 0..) |row, i| {
        complete[i] = true;
        for (p.vars) |ci| if (std.math.isNan(try num(row, ci))) {
            complete[i] = false;
        };
    }
    const centers = try a.alloc(f64, nv);
    const scales = try a.alloc(f64, nv);
    @memset(centers, 0);
    @memset(scales, 1);
    const std_on = p.standardize != null and p.standardize.?.mode != .none;
    if (std_on) {
        const s = p.standardize.?;
        for (p.vars, 0..) |ci, j| {
            var lo = std.math.inf(f64);
            var hi = -std.math.inf(f64);
            var f_sum: f64 = 0;
            var wf_sum: f64 = 0;
            var sum: f64 = 0;
            var used: usize = 0;
            const keep = try a.alloc(bool, n);
            for (rows, 0..) |row, i| {
                keep[i] = complete[i];
                if (keep[i] and s.method != .range) {
                    if (freq) |f| if (!(f[i] >= 1)) {
                        keep[i] = false;
                    };
                    if (weight) |w| if (!(w[i] > 0)) {
                        keep[i] = false;
                    };
                }
                if (!keep[i]) continue;
                const x = try num(row, ci);
                const f = if (freq) |fv| fv[i] else 1;
                const w = if (s.method == .wmoments and weight != null) weight.?[i] else 1;
                used += 1;
                lo = @min(lo, x);
                hi = @max(hi, x);
                f_sum += f;
                wf_sum += w * f;
                sum += w * f * x;
            }
            if (used == 0) return user(d, line, "no valid observations to standardize variable {s}", .{ds.columns.items[ci].name});
            var center: f64 = (hi + lo) / 2;
            var scale: f64 = (hi - lo) / 2;
            if (s.method != .range) {
                center = sum / wf_sum;
                var ss: f64 = 0;
                for (rows, 0..) |row, i| if (keep[i]) {
                    const x = try num(row, ci);
                    const f = if (freq) |fv| fv[i] else 1;
                    const w = if (s.method == .wmoments and weight != null) weight.?[i] else 1;
                    ss += w * f * (x - center) * (x - center);
                };
                scale = @sqrt(ss / (f_sum - 1));
            }
            if (s.mode != .scale) centers[j] = center;
            if (s.mode != .center) {
                if (!(scale > 0) or !std.math.isFinite(scale)) return gap(d, line, "the scale estimate of variable {s} is not positive; SAS behaviour is not verified", .{ds.columns.items[ci].name});
                scales[j] = scale;
            }
        }
    }
    const x = try a.alloc(f64, n * np);
    for (rows, 0..) |row, i| for (0..np) |c| {
        var v: f64 = if (complete[i]) 1 else std.math.nan(f64);
        if (complete[i]) for (p.vars, 0..) |ci, j| {
            const z = (try num(row, ci) - centers[j]) / scales[j];
            for (0..ex.items[c * nv + j]) |_| v *= z;
        };
        x[i * np + c] = v;
    };
    const names = try a.alloc([]const u8, np);
    const effects = try a.alloc([]const u8, np);
    for (0..np) |c| {
        var b: std.ArrayList(u8) = .empty;
        // INCLUDENAME is ignored with NOSEPARATE (p.432).
        if (p.include_name and p.separate) {
            try b.appendSlice(a, name);
            try b.append(a, '_');
        }
        var first = true;
        for (p.vars, 0..) |ci, j| {
            const e = ex.items[c * nv + j];
            if (e == 0) continue;
            for (0..if (p.expand) e else 1) |_| {
                if (!first) try b.appendSlice(a, p.product);
                first = false;
                if (std_on) try b.appendSlice(a, p.standardize.?.prefix);
                try b.appendSlice(a, ds.columns.items[ci].name);
            }
            if (!p.expand and e > 1) {
                try b.appendSlice(a, p.exponent);
                try b.appendSlice(a, try std.fmt.allocPrint(a, "{d}", .{e}));
            }
        }
        names[c] = b.items;
        effects[c] = if (p.separate) b.items else name;
    }
    return .{ .n = n, .p = np, .x = x, .names = names, .effects = effects, .exponents = ex.items, .centers = centers, .scales = scales };
}

fn labelLess(_: void, l: []const u8, r: []const u8) bool {
    return std.mem.order(u8, l, r) == .lt;
}

/// One column per level of the union of the member variables' formatted values
/// (ascending), each cell the number of times the level occurs in the row
/// (p.429), or the sum of the WEIGHT= values of the members that carry it.
/// A row with every member missing is all missing, or all zero with NOEFFECT.
pub fn buildMultimember(a: A, d: D, ds: *const Dataset, rows: []const []const Value, name: []const u8, m: Multimember, line: usize) diag.Error!Built {
    if (m.vars.len == 0 or (m.weights.len != 0 and m.weights.len != m.vars.len)) return error.ExecError;
    const n = rows.len;
    var all: std.ArrayList([]const u8) = .empty;
    const maps = try a.alloc(levels.Levels, m.vars.len);
    for (m.vars, 0..) |ci, j| {
        // ponytail: numeric members need the formatted-value ordering of the
        // union, which the cited pages do not pin down; refused loudly.
        if (ds.columns.items[ci].type != .char) return gap(d, line, "numeric multimember variable {s} is not implemented", .{ds.columns.items[ci].name});
        maps[j] = try levels.build(a, ds, rows, ci, .{ .order = .formatted, .missing = .exclude });
        for (maps[j].levels) |lv| {
            for (all.items) |have| {
                if (std.mem.eql(u8, have, lv.label)) break;
            } else try all.append(a, lv.label);
        }
    }
    std.mem.sort([]const u8, all.items, {}, labelLess);
    const np = all.items.len;
    const x = try a.alloc(f64, n * np);
    @memset(x, 0);
    for (rows, 0..) |row, i| {
        var members: usize = 0;
        var total: f64 = 0;
        for (m.vars, 0..) |_, j| {
            const li = maps[j].row_to_level[i] orelse continue;
            const label = maps[j].levels[li].label;
            var w: f64 = 1;
            if (m.weights.len != 0) {
                w = try num(row, m.weights[j]);
                if (std.math.isNan(w)) return gap(d, line, "a missing WEIGHT= value for a nonmissing member is not verified against SAS", .{});
            }
            for (all.items, 0..) |have, c| if (std.mem.eql(u8, have, label)) {
                x[i * np + c] += w;
            };
            members += 1;
            total += w;
        }
        if (members == 0) {
            if (!m.noeffect) @memset(x[i * np .. (i + 1) * np], std.math.nan(f64));
            continue;
        }
        if (m.stdize) {
            if (total == 0) return gap(d, line, "STDIZE with a zero row sum is not verified against SAS", .{});
            for (x[i * np .. (i + 1) * np]) |*v| v.* /= total;
        }
    }
    const effects = try a.alloc([]const u8, np);
    @memset(effects, name);
    return .{ .n = n, .p = np, .x = x, .names = all.items, .effects = effects };
}

test {
    _ = @import("effect_constructed_tests.zig");
}
