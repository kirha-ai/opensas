//! PROC KRIGE2D (SAS/STAT 15.4 ch.74, STAT-KRIGE2D-001): PROC statement
//! options DATA=, NOPRINT, OUTEST= (OUTE=), IDGLOBAL, IDNUM, SINGULARMSG=
//! (SMSG=), PLOTS=NONE; the COORDINATES (XC= / YC=), GRID (X= / Y= lists,
//! TO / BY ranges), PREDICT (VAR=, RADIUS=, MINPOINTS=, MAXPOINTS=), MODEL
//! (SCALE=, RANGE=, FORM=GAUSSIAN, NUGGET=0, SINGULAR=), BY and ID
//! statements; local ordinary kriging (pp.5471-5473) with the Gaussian
//! covariance C(h) = scale*exp(-h^2/range^2) (p.5466, effective range
//! sqrt(3)*range), the Number of Observations / Kriging Information /
//! Covariance Model Information listing and the OUTEST= data set (p.5474).
//! Everything else the cited pages define is a loud D-009 gap: OUTNBHD=,
//! ODS Graphics plots (STAT-KRIGE2D-013), global kriging and NUMPOINTS=
//! (STAT-KRIGE2D-004), NODECREMENT / NOINCREMENT, GRIDDATA= / NPTS=, other
//! covariance forms, nested / anisotropic / nugget models, MDATA= and
//! RESTORE (STAT-KRIGE2D-003/005..009), several PREDICT or MODEL
//! statements.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const Tok = lex.Token;

pub const Model = struct {
    scale: f64,
    range: f64,
    nugget: f64 = 0,
    singular: f64 = 1e-7,
};

pub const Spec = struct {
    input: proc.ProcInput,
    noprint: bool = false,
    outest: ?[]const u8 = null,
    singularmsg: usize = 10,
    x_col: usize = 0,
    y_col: usize = 0,
    var_col: usize = 0,
    id_col: ?usize = null,
    radius: f64 = 0,
    minpoints: usize = 20,
    maxpoints: ?usize = null,
    gx: []const f64 = &.{},
    gy: []const f64 = &.{},
    model: Model = .{ .scale = 0, .range = 0 },
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    plots_none: bool = false,
};

fn at(t: []const Tok, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn line(t: []const Tok, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const Tok, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC KRIGE2D: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}

/// A signed numeric literal at t[i.*]; advances past it.
fn number(cx: proc.ProcCtx, t: []const Tok, i: *usize, what: []const u8) diag.Error!f64 {
    var j = i.*;
    var neg = false;
    if (at(t, j, .minus)) {
        neg = true;
        j += 1;
    }
    if (!at(t, j, .number)) return cx.diags.fail(error.ParseError, line(t, j), "PROC KRIGE2D: {s} requires a numeric value", .{what});
    const v = std.fmt.parseFloat(f64, t[j].text) catch return cx.diags.fail(error.ParseError, t[j].line, "PROC KRIGE2D: invalid {s} value {s}", .{ what, t[j].text });
    i.* = j + 1;
    return if (neg) -v else v;
}

fn count(cx: proc.ProcCtx, t: []const Tok, i: *usize, what: []const u8) diag.Error!usize {
    const l = line(t, i.*);
    const v = try number(cx, t, i, what);
    if (v < 1 or v != @trunc(v) or v > 1e9) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: {s} must be a positive integer", .{what});
    return @intFromFloat(v);
}

/// XC=name or XC=(name); returns the column.
fn varRef(cx: proc.ProcCtx, ds: *Dataset, t: []const Tok, i: *usize, what: []const u8) diag.Error!usize {
    var j = i.*;
    const paren = at(t, j, .lparen);
    if (paren) j += 1;
    if (!at(t, j, .name)) return cx.diags.fail(error.ParseError, line(t, j), "PROC KRIGE2D: {s} requires a variable name", .{what});
    const n = t[j].text;
    j += 1;
    if (paren) {
        if (!at(t, j, .rparen)) return invalid(cx, t, j);
        j += 1;
    }
    i.* = j;
    const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, t[j - 1].line, "PROC KRIGE2D: variable {s} not found", .{n});
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[j - 1].line, "PROC KRIGE2D: variable {s} in the {s} option must be numeric", .{ n, what });
    return ci;
}

/// GRID X= / Y= value list (p.5439): number | x1, ..., xm | x1 TO xm <BY d>.
fn gridList(cx: proc.ProcCtx, t: []const Tok, i: *usize, end: usize, what: []const u8) diag.Error![]const f64 {
    const a = cx.arena;
    var vals: std.ArrayList(f64) = .empty;
    while (true) {
        const first = try number(cx, t, i, what);
        if (i.* < end and at(t, i.*, .name) and eq(t[i.*].text, "to")) {
            i.* += 1;
            const last = try number(cx, t, i, what);
            var step: f64 = 1;
            if (i.* < end and at(t, i.*, .name) and eq(t[i.*].text, "by")) {
                i.* += 1;
                step = try number(cx, t, i, what);
            }
            if (step <= 0 or last < first) return proc.failGap(cx.diags, line(t, i.*), "PROC KRIGE2D: a GRID {s} range that is empty or not increasing is not verified", .{what});
            const steps = (last - first) / step;
            const n: usize = @intFromFloat(@floor(steps + 1e-9) + 1);
            if (n > 1_000_000) return proc.failGap(cx.diags, line(t, i.*), "PROC KRIGE2D: GRID {s} ranges of more than 1000000 values are not implemented", .{what});
            for (0..n) |k| try vals.append(a, first + @as(f64, @floatFromInt(k)) * step);
        } else try vals.append(a, first);
        if (i.* < end and at(t, i.*, .comma)) {
            i.* += 1;
            continue;
        }
        break;
    }
    return vals.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const Tok) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{ .input = undefined };
    var data_name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const o = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(o, "data") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            data_name = t[i + 2].text;
            var j = i + 3;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                data_name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[i + 2].text, t[j + 1].text });
                qualified = i + 2;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if ((eq(o, "outest") or eq(o, "oute")) and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            var j = i + 3;
            var name = t[i + 2].text;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[j + 1].text });
                j += 2;
            }
            if (at(t, j, .lparen)) return gap(cx.diags, t[j].line, "PROC KRIGE2D: data set options on OUTEST= are not implemented", .{});
            s.outest = name;
            i = j;
        } else if ((eq(o, "outnbhd") or eq(o, "outn")) and valued) {
            return gap(cx.diags, t[i].line, "PROC KRIGE2D: OUTNBHD= is not implemented (STAT-KRIGE2D-011)", .{});
        } else if ((eq(o, "singularmsg") or eq(o, "smsg")) and valued) {
            var j = i + 2;
            s.singularmsg = try count(cx, t, &j, "SINGULARMSG=");
            i = j;
        } else if (eq(o, "plots")) {
            // p.5432: PLOTS=NONE is the only request without a plot.
            if (valued and at(t, i + 2, .name) and eq(t[i + 2].text, "none") and !at(t, i + 3, .lparen)) {
                s.plots_none = true;
                i += 3;
            } else return gap(cx.diags, t[i].line, "PROC KRIGE2D: PLOTS= requests other than PLOTS=NONE are not implemented (STAT-KRIGE2D-013)", .{});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(o, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(o, "idglobal") or eq(o, "idnum")) {
            // p.5432: these only label OUTNBHD= rows and plots, both gaps here.
            i += 1;
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (data_name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC KRIGE2D: input data set {s} not found", .{data_name orelse "_LAST_"});
    var folded: std.ArrayList(Tok) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = data_name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var have_coord = false;
    var have_grid = false;
    var predicts: usize = 0;
    var models: usize = 0;
    var have_id = false;
    var have_radius = false;
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
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.5437: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "coordinates") or eq(word, "coord")) {
            // p.5438: only one COORDINATES statement is allowed.
            if (have_coord) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: only one COORDINATES statement is allowed", .{});
            have_coord = true;
            var got: [2]bool = .{ false, false };
            var j = i + 1;
            while (j < end) {
                if (!at(t, j, .name) or !at(t, j + 1, .eq)) return invalid(cx, t, j);
                const k = t[j].text;
                j += 2;
                if (eq(k, "xc") or eq(k, "xcoord")) {
                    s.x_col = try varRef(cx, ds, t, &j, "XC=");
                    got[0] = true;
                } else if (eq(k, "yc") or eq(k, "ycoord")) {
                    s.y_col = try varRef(cx, ds, t, &j, "YC=");
                    got[1] = true;
                } else return invalid(cx, t, j - 2);
            }
            if (!got[0] or !got[1]) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the COORDINATES statement requires both XC= and YC=", .{});
        } else if (eq(word, "grid")) {
            if (have_grid) return gap(cx.diags, l, "PROC KRIGE2D: more than one GRID statement is not verified", .{});
            have_grid = true;
            var j = i + 1;
            var gx: ?[]const f64 = null;
            var gy: ?[]const f64 = null;
            while (j < end) {
                if (at(t, j, .slash)) return gap(cx.diags, l, "PROC KRIGE2D: GRID statement options after a slash (LABEL=) are not implemented (STAT-KRIGE2D-004)", .{});
                if (!at(t, j, .name) or !at(t, j + 1, .eq)) return invalid(cx, t, j);
                const k = t[j].text;
                j += 2;
                if (eq(k, "x")) {
                    gx = try gridList(cx, t, &j, end, "X=");
                } else if (eq(k, "y")) {
                    gy = try gridList(cx, t, &j, end, "Y=");
                } else if (eq(k, "npts") or eq(k, "griddata") or eq(k, "gdata") or eq(k, "xc") or eq(k, "yc") or eq(k, "xcoord") or eq(k, "ycoord")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: GRID {s}= is not implemented (STAT-KRIGE2D-004)", .{k});
                } else return invalid(cx, t, j - 2);
            }
            if (gx == null or gy == null) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the GRID statement requires both X= and Y= (or GRIDDATA=)", .{});
            s.gx = gx.?;
            s.gy = gy.?;
        } else if (eq(word, "predict") or eq(word, "pred") or eq(word, "p")) {
            predicts += 1;
            if (predicts > 1) return gap(cx.diags, l, "PROC KRIGE2D: more than one PREDICT statement is not implemented", .{});
            var got_var = false;
            var j = i + 1;
            while (j < end) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                const k = t[j].text;
                if (eq(k, "nodecrement") or eq(k, "nodecr") or eq(k, "noincrement") or eq(k, "noincr")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: PREDICT {s} is not implemented (STAT-KRIGE2D-004)", .{k});
                }
                if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                j += 2;
                if (eq(k, "var")) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    s.var_col = ds.indexOf(t[j].text) orelse return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: variable {s} not found", .{t[j].text});
                    if (ds.columns.items[s.var_col].type != .num) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the VAR= variable {s} must be numeric", .{t[j].text});
                    got_var = true;
                    j += 1;
                } else if (eq(k, "radius") or eq(k, "r")) {
                    s.radius = try number(cx, t, &j, "RADIUS=");
                    if (!(s.radius > 0)) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: RADIUS= must be positive", .{});
                    have_radius = true;
                } else if (eq(k, "minpoints") or eq(k, "minp") or eq(k, "min")) {
                    s.minpoints = try count(cx, t, &j, "MINPOINTS=");
                } else if (eq(k, "maxpoints") or eq(k, "maxp") or eq(k, "max")) {
                    s.maxpoints = try count(cx, t, &j, "MAXPOINTS=");
                } else if (eq(k, "numpoints") or eq(k, "npoints") or eq(k, "npts") or eq(k, "np")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: PREDICT NUMPOINTS= is not implemented (STAT-KRIGE2D-004)", .{});
                } else return invalid(cx, t, j - 2);
            }
            if (!got_var) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the PREDICT statement requires VAR=", .{});
            if (!have_radius) return gap(cx.diags, l, "PROC KRIGE2D: global kriging (PREDICT without RADIUS=) is not implemented (STAT-KRIGE2D-004)", .{});
            if (s.maxpoints) |m| if (m < s.minpoints) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: MAXPOINTS= ({d}) is smaller than MINPOINTS= ({d})", .{ m, s.minpoints });
        } else if (eq(word, "model")) {
            // p.5443: a MODEL statement applies to the most previous PREDICT.
            if (predicts == 0) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: a MODEL statement must follow a PREDICT statement", .{});
            models += 1;
            if (models > 1) return gap(cx.diags, l, "PROC KRIGE2D: more than one MODEL statement is not implemented", .{});
            var scale: ?f64 = null;
            var range: ?f64 = null;
            var gau = false;
            var j = i + 1;
            while (j < end) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                const k = t[j].text;
                if (eq(k, "pownobound") or eq(k, "storeselect")) return gap(cx.diags, l, "PROC KRIGE2D: MODEL {s} is not implemented (STAT-KRIGE2D-003)", .{k});
                if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                j += 2;
                if (at(t, j, .lparen)) return gap(cx.diags, l, "PROC KRIGE2D: nested models (MODEL {s}=(...)) are not implemented (STAT-KRIGE2D-008)", .{k});
                if (eq(k, "scale")) {
                    scale = try number(cx, t, &j, "SCALE=");
                } else if (eq(k, "range")) {
                    range = try number(cx, t, &j, "RANGE=");
                } else if (eq(k, "nugget")) {
                    const v = try number(cx, t, &j, "NUGGET=");
                    if (v < 0) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: NUGGET= must be nonnegative", .{});
                    if (v != 0) return gap(cx.diags, l, "PROC KRIGE2D: a nonzero NUGGET= is not implemented (STAT-KRIGE2D-008)", .{});
                } else if (eq(k, "singular")) {
                    s.model.singular = try number(cx, t, &j, "SINGULAR=");
                    if (!(s.model.singular > 0)) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: SINGULAR= must be positive", .{});
                } else if (eq(k, "form")) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const f = t[j].text;
                    j += 1;
                    if (eq(f, "gaussian") or eq(f, "gau") or eq(f, "gauss")) {
                        gau = true;
                    } else if (eq(f, "cubic") or eq(f, "cub") or eq(f, "exponential") or eq(f, "exp") or eq(f, "matern") or eq(f, "mat") or eq(f, "pentaspherical") or eq(f, "pen") or eq(f, "power") or eq(f, "pow") or eq(f, "sineholeeffect") or eq(f, "she") or eq(f, "spherical") or eq(f, "sph")) {
                        return gap(cx.diags, l, "PROC KRIGE2D: FORM={s} is not implemented (STAT-KRIGE2D-005..007)", .{f});
                    } else return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: unknown FORM= value {s}", .{f});
                } else if (eq(k, "angle") or eq(k, "ratio")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: anisotropic models (MODEL {s}=) are not implemented (STAT-KRIGE2D-008)", .{k});
                } else if (eq(k, "smooth")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: MODEL SMOOTH= (Matern) is not implemented (STAT-KRIGE2D-006)", .{});
                } else if (eq(k, "mdata")) {
                    return gap(cx.diags, l, "PROC KRIGE2D: MODEL MDATA= is not implemented (STAT-KRIGE2D-003)", .{});
                } else return invalid(cx, t, j - 2);
            }
            if (!gau or scale == null or range == null) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the MODEL statement requires SCALE=, RANGE= and FORM= (or MDATA= / STORESELECT)", .{});
            if (!(scale.? > 0) or !(range.? > 0)) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: SCALE= and RANGE= must be positive", .{});
            s.model.scale = scale.?;
            s.model.range = range.?;
        } else if (eq(word, "id")) {
            // p.5441: only one ID variable.
            if (have_id) return gap(cx.diags, l, "PROC KRIGE2D: more than one ID statement is not verified", .{});
            have_id = true;
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: the ID statement names exactly one variable", .{});
            s.id_col = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, l, "PROC KRIGE2D: ID variable {s} not found", .{t[i + 1].text});
        } else if (eq(word, "restore")) {
            return gap(cx.diags, l, "PROC KRIGE2D: the RESTORE statement is not implemented (STAT-KRIGE2D-005)", .{});
        } else if (eq(word, "where")) {
            // Applied to DATA= by procInputObs above.
        } else if (eq(word, "format") or eq(word, "label") or eq(word, "attrib") or eq(word, "freq") or eq(word, "weight")) {
            return gap(cx.diags, l, "PROC KRIGE2D: a {s} statement inside the step is not implemented", .{word});
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!have_coord) return cx.diags.fail(error.ParseError, line(t, 0), "PROC KRIGE2D: a COORDINATES statement is required", .{});
    if (!have_grid) return cx.diags.fail(error.ParseError, line(t, 0), "PROC KRIGE2D: a GRID statement is required", .{});
    if (predicts == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC KRIGE2D: a PREDICT statement is required", .{});
    if (models == 0) return cx.diags.fail(error.ParseError, line(t, 0), "PROC KRIGE2D: the PREDICT statement needs a MODEL statement", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const bcols = try a.alloc(usize, pb.names.len);
    for (pb.names, bcols) |n, *c| c.* = ds.indexOf(n).?;
    s.by_cols = bcols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Gaussian covariance (p.5466): scale * exp(-h^2 / range^2).
pub fn cov(m: Model, h: f64) f64 {
    return m.scale * @exp(-(h * h) / (m.range * m.range));
}

pub const Point = struct { x: f64, y: f64, z: f64 };
pub const Prediction = struct { estimate: f64, stderr: f64, npoints: usize, singular: bool };

/// Solves M v = b in place (n x n, row-major) by Gaussian elimination with
/// partial pivoting; false when a pivot falls below `tol` times the largest
/// absolute matrix entry.
fn solve(m: []f64, b: []f64, n: usize, tol: f64) bool {
    var big: f64 = 0;
    for (m) |v| big = @max(big, @abs(v));
    for (0..n) |c| {
        var p = c;
        for (c + 1..n) |r| if (@abs(m[r * n + c]) > @abs(m[p * n + c])) {
            p = r;
        };
        if (@abs(m[p * n + c]) <= tol * big) return false;
        if (p != c) {
            for (0..n) |k| std.mem.swap(f64, &m[p * n + k], &m[c * n + k]);
            std.mem.swap(f64, &b[p], &b[c]);
        }
        for (c + 1..n) |r| {
            const f = m[r * n + c] / m[c * n + c];
            if (f == 0) continue;
            for (c..n) |k| m[r * n + k] -= f * m[c * n + k];
            b[r] -= f * b[c];
        }
    }
    var r = n;
    while (r > 0) {
        r -= 1;
        var sum = b[r];
        for (r + 1..n) |k| sum -= m[r * n + k] * b[k];
        b[r] = sum / m[r * n + r];
    }
    return true;
}

/// Ordinary kriging at (x0, y0) from `pts` (pp.5472-5473), with the
/// Deutsch-Journel scaling of the unbiasedness row/column by C(0):
/// [C  C0*1; C0*1' 0][lambda; mu/C0] = [c; C0]; variance C0 - lambda'c - mu.
pub fn krige(a: A, m: Model, pts: []const Point, x0: f64, y0: f64) !Prediction {
    const n = pts.len;
    const k = n + 1;
    const c0 = cov(m, 0);
    const mat = try a.alloc(f64, k * k);
    const rhs = try a.alloc(f64, k);
    for (pts, 0..) |p, r| {
        for (pts, 0..) |q, c| mat[r * k + c] = cov(m, std.math.hypot(p.x - q.x, p.y - q.y));
        mat[r * k + n] = c0;
        mat[n * k + r] = c0;
        rhs[r] = cov(m, std.math.hypot(p.x - x0, p.y - y0));
    }
    mat[n * k + n] = 0;
    rhs[n] = c0;
    const c = try a.dupe(f64, rhs);
    if (!solve(mat, rhs, k, m.singular)) return .{ .estimate = std.math.nan(f64), .stderr = std.math.nan(f64), .npoints = n, .singular = true };
    var est: f64 = 0;
    var lc: f64 = 0;
    for (pts, 0..) |p, r| {
        est += rhs[r] * p.z;
        lc += rhs[r] * c[r];
    }
    const v = c0 - lc - rhs[n] * c0;
    return .{ .estimate = est, .stderr = @sqrt(@max(v, 0)), .npoints = n, .singular = false };
}

/// The local neighbourhood (pp.5441-5442): every point within RADIUS=; fewer
/// than MINPOINTS= takes the MINPOINTS= nearest (radius incremented), more
/// than MAXPOINTS= keeps the MAXPOINTS= nearest (radius decremented).
pub const Neighbourhood = struct {
    pts: []const Point,
    /// The radius after an increment (MINPOINTS=) or decrement
    /// (MAXPOINTS=): the distance of the farthest neighbour kept.
    radius: f64,
    incremented: bool = false,
    decremented: bool = false,
};

pub fn neighbours(a: A, s: Spec, pts: []const Point, x0: f64, y0: f64) !Neighbourhood {
    const D = struct { d: f64, i: usize };
    const ds = try a.alloc(D, pts.len);
    for (pts, ds, 0..) |p, *d, i| d.* = .{ .d = std.math.hypot(p.x - x0, p.y - y0), .i = i };
    std.sort.pdq(D, ds, {}, struct {
        fn lt(_: void, l: D, r: D) bool {
            return l.d < r.d or (l.d == r.d and l.i < r.i);
        }
    }.lt);
    var n: usize = 0;
    while (n < ds.len and ds[n].d <= s.radius) n += 1;
    var inc = false;
    var dec = false;
    if (n < s.minpoints) {
        n = @min(s.minpoints, ds.len);
        inc = true;
    }
    if (s.maxpoints) |mx| if (n > mx) {
        // ponytail: among equidistant points the earlier observations are
        // kept; SAS's K-D tree tie order is not reproduced.
        n = mx;
        dec = true;
    };
    const out = try a.alloc(Point, n);
    for (out, ds[0..n]) |*o, d| o.* = pts[d.i];
    return .{ .pts = out, .radius = if (n > 0) ds[n - 1].d else 0, .incremented = inc, .decremented = dec };
}

fn best(a: A, x: f64) ![]const u8 {
    return std.mem.trim(u8, try format.bestNumW(a, x, 9), " ");
}

fn pad(a: A, out: *Out, n: usize) !void {
    for (0..n) |_| try out.append(a, ' ');
}

/// A two-column label / value table: label left, value right-aligned in a
/// column of at least 8, four spaces apart; an optional title centered
/// (`center`) or flush left.
fn table(a: A, out: *Out, title: ?[]const u8, center: bool, rows: []const [2][]const u8) !void {
    var lw: usize = 0;
    var vw: usize = 8;
    for (rows) |r| {
        lw = @max(lw, r[0].len);
        vw = @max(vw, r[1].len);
    }
    const total = lw + 4 + vw;
    if (title) |tt| {
        if (center and total > tt.len) try pad(a, out, (total - tt.len) / 2);
        try out.print(a, "{s}\n\n", .{tt});
    }
    for (rows) |r| {
        try out.appendSlice(a, r[0]);
        try pad(a, out, lw - r[0].len + 4 + vw - r[1].len);
        try out.print(a, "{s}\n", .{r[1]});
    }
}

fn header(a: A, cx: proc.ProcCtx, out: *Out, s: Spec, first: *bool, rep: ?[]const Value, extra: ?[]const u8) !void {
    if (!first.*) if (cx.listing_titles) |titles| try titles.emitTitles(a, out);
    first.* = false;
    if (rep) |row| {
        try by.appendLine(a, out, s.input.ds, row, s.by_cols); // "\n" + BY line
        try out.append(a, '\n');
    } else try out.append(a, '\n');
    try out.print(a, "The KRIGE2D Procedure\nDependent Variable: {s}\n", .{s.input.ds.columns.items[s.var_col].name});
    if (extra) |e| try out.print(a, "{s}\n", .{e});
    try out.append(a, '\n');
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const Tok) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const ds = s.input.ds;
    // p.5433: with ODS Graphics enabled SAS adds a default prediction plot.
    const graphs = !s.noprint and !s.plots_none and if (cx.graphics) |g| g.enabled == true else false;
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    var est: ?*Dataset = null;
    if (s.outest) |_| {
        const o = try a.create(Dataset);
        o.* = Dataset.init(a, s.outest.?);
        // Reference run (SAS 9.4): this variable order, lengths and labels,
        // with the BY variables after STDERR.
        const cols = [_][3][]const u8{
            .{ "LABEL", "c", "Label for the PREDICT/MODEL combination" },
            .{ "VARNAME", "c", "Variable Name" },
            .{ "GXC", "n", "X-coordinate of the grid point" },
            .{ "GYC", "n", "Y-coordinate of the grid point" },
            .{ "NPOINTS", "n", "Number of Points used in Estimation" },
            .{ "ESTIMATE", "n", "Kriging Estimate" },
            .{ "STDERR", "n", "Standard Error of Kriging Estimate" },
        };
        for (cols) |c| {
            _ = try o.addColumn(c[0], if (c[1][0] == 'c') .char else .num);
            o.setLabel(c[0], c[2]);
        }
        o.setLen("LABEL", 12);
        o.setLen("VARNAME", ds.columns.items[s.var_col].name.len);
        for (s.by_cols) |ci| _ = try o.addColumnLike(ds.columns.items[ci].name, ds.columns.items[ci]);
        est = o;
    }
    const var_name = ds.columns.items[s.var_col].name;
    var first = true;
    var singular_msgs: usize = 0;
    // Reference run (SAS 9.4): one warning counts the missing VAR= values.
    var missing: usize = 0;
    for (ds.rows.items) |row| if (std.math.isNan(row[s.var_col].num)) {
        missing += 1;
    };
    if (missing > 0) try cx.diags.warn(0, "The VAR= variable {s}, found in one or more PREDICT statements, contains {d} missing value(s).", .{ var_name, missing });
    for (groups) |g| {
        const rep = if (s.by_cols.len > 0) g.rep else null;
        // p.5438: observations with a missing coordinate or VAR= value are excluded.
        var pts: std.ArrayList(Point) = .empty;
        for (g.rows) |row| {
            const x = row[s.x_col].num;
            const y = row[s.y_col].num;
            const z = row[s.var_col].num;
            if (std.math.isNan(x) or std.math.isNan(y) or std.math.isNan(z)) continue;
            try pts.append(a, .{ .x = x, .y = y, .z = z });
        }
        if (pts.items.len == 0) {
            if (rep) |r| try by.reportNote(a, cx.diags, ds, r, s.by_cols);
            return cx.diags.fail(error.ExecError, 0, "PROC KRIGE2D: there are no valid observations for variable {s}", .{var_name});
        }
        var n_inc: usize = 0;
        var n_dec: usize = 0;
        var max_r: f64 = 0;
        var min_r: f64 = std.math.inf(f64);
        // ponytail: the radius statistics need every neighbourhood, so the
        // kriging systems are solved even under NOPRINT without OUTEST=.
        {
            for (s.gx) |x0| for (s.gy) |y0| {
                const nb = try neighbours(a, s, pts.items, x0, y0);
                if (nb.incremented) {
                    n_inc += 1;
                    max_r = @max(max_r, nb.radius);
                }
                if (nb.decremented) {
                    n_dec += 1;
                    min_r = @min(min_r, nb.radius);
                }
                const o = est orelse continue;
                const p = try krige(a, s.model, nb.pts, x0, y0);
                if (p.singular) {
                    singular_msgs += 1;
                    if (singular_msgs <= s.singularmsg) try cx.diags.warn(0, "Singular kriging system at grid point ({d}, {d}); the prediction is missing.", .{ x0, y0 });
                }
                const row = try a.alloc(Value, o.columns.items.len);
                for (s.by_cols, 0..) |ci, k| row[7 + k] = rep.?[ci];
                row[0] = .{ .str = "Pred1.Model1" };
                row[1] = .{ .str = var_name };
                row[2] = .{ .num = x0 };
                row[3] = .{ .num = y0 };
                row[4] = .{ .num = @floatFromInt(p.npoints) };
                row[5] = .{ .num = p.estimate };
                row[6] = .{ .num = p.stderr };
                try o.appendRow(row);
            };
        }
        if (s.noprint) continue;
        try header(a, cx, out, s, &first, rep, null);
        try table(a, out, null, false, &.{
            .{ "Number of Observations Read", try std.fmt.allocPrint(a, "{d}", .{g.rows.len}) },
            .{ "Number of Observations Used", try std.fmt.allocPrint(a, "{d}", .{pts.items.len}) },
        });
        try out.appendSlice(a, "\n\n");
        var info: std.ArrayList([2][]const u8) = .empty;
        try info.appendSlice(a, &.{
            .{ "Prediction Grid Points", try std.fmt.allocPrint(a, "{d}", .{s.gx.len * s.gy.len}) },
            .{ "Type of Analysis", "Local" },
            .{ "Neighborhood Search Radius", try best(a, s.radius) },
        });
        // Reference run (SAS 9.4): adjusted-radius rows appear only when a
        // grid point needed the adjustment.
        if (n_inc > 0) try info.appendSlice(a, &.{
            .{ "Grid Points with Radius Incremented", try std.fmt.allocPrint(a, "{d}", .{n_inc}) },
            .{ "Maximum Radius", try best(a, max_r) },
        });
        if (n_dec > 0) try info.appendSlice(a, &.{
            .{ "Grid Points with Radius Decremented", try std.fmt.allocPrint(a, "{d}", .{n_dec}) },
            .{ "Minimum Radius", try best(a, min_r) },
        });
        try info.appendSlice(a, &.{
            .{ "Minimum Neighbors", try std.fmt.allocPrint(a, "{d}", .{s.minpoints}) },
            .{ "Maximum Neighbors", if (s.maxpoints) |m| try std.fmt.allocPrint(a, "{d}", .{m}) else "All Within Radius" },
        });
        try table(a, out, "Kriging Information", true, info.items);
        try out.append(a, '\n'); // reference listing: a blank line ends each page
        try header(a, cx, out, s, &first, rep, "Prediction: Pred1, Model: Model1");
        try table(a, out, "Covariance Model Information", false, &.{
            .{ "Type", "Gaussian" },
            .{ "Sill", try best(a, s.model.scale) },
            .{ "Range", try best(a, s.model.range) },
            .{ "Effective Range", try best(a, @sqrt(3.0) * s.model.range) },
            .{ "Nugget Effect", try best(a, s.model.nugget) },
        });
        try out.append(a, '\n');
    }
    if (est) |o| {
        try cx.lib.put(s.outest.?, o);
        const upper = try std.ascii.allocUpperString(a, s.outest.?);
        const lib_prefix: []const u8 = if (std.mem.indexOfScalar(u8, s.outest.?, '.') == null) "WORK." else "";
        try cx.diags.note(0, "The data set {s}{s} has {d} observations and {d} variables.", .{ lib_prefix, upper, o.rows.items.len, o.columns.items.len });
    }
    if (graphs) {
        // The tables above are complete; the plot SAS adds to them is not
        // drawn (nor its implicit DATAn prediction data set), so the step
        // still ends with a visible D-009 gap (as PROC CORRESP does).
        diag.markGap();
        try cx.diags.recoverableErr(0, "PROC KRIGE2D: the default ODS Graphics prediction plot is not implemented (STAT-KRIGE2D-013); specify PLOTS=NONE or ODS GRAPHICS OFF", .{});
    }
}

test {
    _ = @import("krige2d_tests.zig");
}
