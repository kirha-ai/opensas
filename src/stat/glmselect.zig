//! PROC GLMSELECT declarations, variable roles, observation selection and the
//! default stepwise (SELECT=SBC, STOP=SBC) path with the DETAILS=ALL STATS=ALL
//! listing, SAS/STAT 15.4 physical pp.4324-4332, 4337, 4356-4357 and the fit
//! criteria of pp.4365-4368. Every valid form whose displayed result is not
//! proven against the reference listing or an independent calculation is a
//! D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const reg_fit = @import("reg_fit.zig");
const ecol = @import("effect_collection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    response: usize,
    /// MODEL effects in statement order: one input column per main effect.
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    frequency: ?usize = null,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    seed: ?f64 = null,
    noprint: bool = false,
    details_all: bool = false,
    stats_all: bool = false,
    /// STAT-COMMON-021: EFFECT statements (COLLECTION of continuous
    /// variables). A MODEL effect index >= the data set's column count names
    /// `constructed[index - column count]`.
    constructed: []const ecol.Spec = &.{},
    selection_none: bool = false,

    pub fn isClass(self: Spec, index: usize) bool {
        return std.mem.indexOfScalar(usize, self.classes, index) != null;
    }
    pub fn constructedOf(self: Spec, index: usize) ?ecol.Collection {
        const ncols = self.input.ds.columns.items.len;
        return if (index >= ncols) self.constructed[index - ncols].body.collection else null;
    }
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC GLMSELECT: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC GLMSELECT: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC GLMSELECT statement options (Table 56.1) owned by later
/// GLMSELECT tickets.
const later_options = [_][]const u8{ "maxmacro", "namelen", "outdesign", "plots", "plot", "testdata", "valdata", "stophorizon", "stb", "tolerance", "tol" };
const later_model_options = [_][]const u8{ "choose", "cvdetails", "cvmethod", "hierarchy", "noint", "orderselect", "select", "stop", "showpvalues", "showpvals", "stb", "drop", "include", "lscoeffs", "maxstep", "maxsteps", "slentry", "sle", "slstay", "sls" };
const later_statements = [_][]const u8{ "effect", "modelaverage", "output", "partition", "performance", "score", "store", "code" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMSELECT: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .data_name = "", .response = undefined };
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
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "seed") and at(t, i + 1, .eq)) {
            // SEED= only drives random partitioning and cross validation,
            // which are gaps here, so the value is validated and recorded.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            s.seed = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: input dataset not found", .{});
    const upper = try std.ascii.allocUpperString(cx.arena, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') != null) upper else try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{upper});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var constructed: std.ArrayList(ecol.Spec) = .empty;
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
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                // CLASS variable and global options: STAT-GLMSELECT-003/004.
                if (at(t, j, .slash) or at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
            }
        } else if (kw(t, i, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMSELECT: only one MODEL statement is allowed", .{});
            model_seen = true;
            s.response = try numericColumn(cx, ds, t, i + 1, "response");
            if (!at(t, i + 2, .eq)) return invalid(cx, t, i + 2);
            var j = i + 3;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                // Crossed, nested, bar and constructed effects and variable
                // list abbreviations: STAT-GLMSELECT-003.
                if (!at(t, j, .name)) return gap(cx, t[j].line, "MODEL effects other than single variable names are not implemented", .{});
                var c: usize = undefined;
                for (constructed.items, 0..) |e, k| {
                    if (eq(e.name, t[j].text)) {
                        c = ds.columns.items.len + k;
                        break;
                    }
                } else c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, effects.items, c) != null) return gap(cx, t[j].line, "repeated MODEL effect policy is not verified", .{});
                try effects.append(cx.arena, c);
            }
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, end);
                while (j < end) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const word = t[j].text;
                    if (eq(word, "details") and at(t, j + 1, .eq)) {
                        if (kw(t, j + 2, "all")) s.details_all = true else if (kw(t, j + 2, "steps") or kw(t, j + 2, "summary")) return gap(cx, t[j].line, "DETAILS={s} is not implemented", .{t[j + 2].text}) else return invalid(cx, t, j + 2);
                        if (at(t, j + 3, .lparen)) return gap(cx, t[j].line, "DETAILS= suboptions are not implemented", .{});
                        j += 3;
                    } else if (eq(word, "stats") and at(t, j + 1, .eq)) {
                        if (kw(t, j + 2, "all")) s.stats_all = true else if (at(t, j + 2, .lparen) or at(t, j + 2, .name)) return gap(cx, t[j].line, "STATS= lists other than ALL are not implemented", .{}) else return invalid(cx, t, j + 2);
                        j += 3;
                    } else if (eq(word, "selection") and at(t, j + 1, .eq)) {
                        if (!at(t, j + 2, .name)) return invalid(cx, t, j + 2);
                        const m = t[j + 2].text;
                        if (oneOf(m, &.{ "forward", "backward", "lar", "lasso", "elasticnet", "grouplasso" })) return gap(cx, t[j].line, "SELECTION={s} is not implemented", .{m});
                        if (!eq(m, "stepwise") and !eq(m, "none")) return invalid(cx, t, j + 2);
                        s.selection_none = eq(m, "none");
                        if (at(t, j + 3, .lparen)) return gap(cx, t[j].line, "SELECTION={s} suboptions are not implemented", .{m});
                        j += 3;
                    } else if (oneOf(word, &later_model_options)) {
                        return gap(cx, t[j].line, "MODEL option {s} is not implemented", .{word});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "effect") and i + 3 < end and at(t, i + 3, .name) and ecol.owns(t[i + 3].text)) {
            // STAT-COMMON-021 shared parsing; GLMSELECT adopts COLLECTION of
            // continuous variables only (other forms: STAT-GLMSELECT-003).
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMSELECT: all EFFECT statements must precede the MODEL statement", .{});
            var names: std.ArrayList([]const u8) = .empty;
            for (constructed.items) |e| try names.append(cx.arena, e.name);
            const e = try ecol.parse(cx.arena, cx.diags, ds, classes.items, names.items, t[i + 1 .. end], t[i].line);
            switch (e.body) {
                .lag => return gap(cx, t[i].line, "LAG effects are not implemented", .{}),
                .collection => |col| {
                    for (col.vars) |v| if (std.mem.indexOfScalar(usize, classes.items, v) != null or ds.columns.items[v].type != .num)
                        return gap(cx, t[i].line, "collection effects with CLASS variables are not implemented", .{});
                },
            }
            try constructed.append(cx.arena, e);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted CLASS levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: MODEL statement required", .{});
    s.classes = classes.items;
    s.effects = effects.items;
    s.constructed = constructed.items;
    for (s.effects) |c| if (s.constructedOf(c)) |col| {
        for (col.vars) |v| {
            if (v == s.response) return gap(cx, 0, "the response variable inside a collection effect is not verified", .{});
            if (s.isClass(v)) return gap(cx, 0, "collection effects with CLASS variables are not implemented", .{});
        }
    };
    if (s.isClass(s.response)) return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: the response variable cannot be a CLASS variable", .{});
    for (s.effects) |c| {
        if (s.constructedOf(c) != null) continue;
        if (c == s.response) return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: the response variable cannot be a MODEL effect", .{});
        if (!s.isClass(c) and ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: character variable {s} must be a CLASS variable", .{ds.columns.items[c].name});
    }
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// One analysis (BY group): centered response and design columns.
pub const Group = struct {
    read: usize,
    n: usize,
    ybar: f64,
    sst: f64,
    y: []const f64,
    /// Centered design columns and their means.
    cols: []const []const f64,
    means: []const f64,
    /// First design column and column count (degrees of freedom) per effect.
    first: []const usize,
    df: []const usize,
    /// Sorted levels per CLASS variable, in CLASS statement order.
    levels: []const []const []const u8,
    parameters: usize,
};

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| !std.math.isFinite(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}
fn textLess(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.order(u8, x, y) == .lt;
}

/// Observation selection, physical p.4332 onward: an observation with a
/// missing response, a missing regressor or a missing CLASS level in any
/// MODEL effect is not used, whichever effects are later selected. A CLASS
/// effect with L levels takes L parameters, the last of which is redundant
/// with the intercept (GLM parameterization), so it carries L-1 columns.
pub fn prepare(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Group {
    const a = cx.arena;
    const ds = s.input.ds;
    var used: std.ArrayList(usize) = .empty;
    rows: for (rows, 0..) |row, r| {
        if (missing(row[s.response])) continue;
        for (s.effects) |c| if (s.constructedOf(c)) |col| {
            for (col.vars) |v| if (missing(row[v])) continue :rows;
        } else if (missing(row[c])) continue :rows;
        for (s.classes) |c| if (missing(row[c])) continue :rows;
        try used.append(a, r);
    }
    const n = used.items.len;
    const levels = try a.alloc([]const []const u8, s.classes.len);
    for (s.classes, levels) |c, *out| {
        if (ds.columns.items[c].type != .char or ds.columns.items[c].format != null) return gap(cx, 0, "numeric or formatted CLASS variables are not implemented", .{});
        var list: std.ArrayList([]const u8) = .empty;
        for (used.items) |r| {
            const label = std.mem.trimEnd(u8, rows[r][c].str, " ");
            var found = false;
            for (list.items) |known| found = found or std.mem.eql(u8, known, label);
            if (!found) try list.append(a, label);
        }
        std.mem.sort([]const u8, list.items, {}, textLess);
        out.* = list.items;
    }
    var g: Group = .{ .read = rows.len, .n = n, .ybar = 0, .sst = 0, .y = &.{}, .cols = &.{}, .means = &.{}, .first = &.{}, .df = &.{}, .levels = levels, .parameters = 1 };
    if (n == 0) return g;
    const y = try a.alloc(f64, n);
    for (used.items, y) |r, *v| v.* = rows[r][s.response].num;
    g.ybar = center(y);
    for (y) |v| g.sst += v * v;
    var cols: std.ArrayList([]const f64) = .empty;
    var means: std.ArrayList(f64) = .empty;
    const first = try a.alloc(usize, s.effects.len);
    const df = try a.alloc(usize, s.effects.len);
    for (s.effects, 0..) |c, e| {
        first[e] = cols.items.len;
        if (s.constructedOf(c)) |col| {
            // p.426: the constituents' design columns in definition order.
            const used_rows = try a.alloc([]const Value, n);
            for (used.items, used_rows) |r, *u| u.* = rows[r];
            const b = try ecol.buildCollection(a, ds, used_rows, s.classes, "", col);
            g.parameters += b.p;
            for (0..b.p) |j| {
                const x = try a.alloc(f64, n);
                for (x, 0..) |*v, r| v.* = b.at(r, j);
                try means.append(a, center(x));
                try cols.append(a, x);
            }
        } else if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
            g.parameters += levels[k].len;
            for (levels[k][0 .. levels[k].len - 1]) |label| {
                const x = try a.alloc(f64, n);
                for (used.items, x) |r, *v| v.* = if (std.mem.eql(u8, std.mem.trimEnd(u8, rows[r][c].str, " "), label)) 1 else 0;
                try means.append(a, center(x));
                try cols.append(a, x);
            }
        } else {
            g.parameters += 1;
            const x = try a.alloc(f64, n);
            for (used.items, x) |r, *v| v.* = rows[r][c].num;
            try means.append(a, center(x));
            try cols.append(a, x);
        }
        df[e] = cols.items.len - first[e];
    }
    g.y = y;
    g.cols = cols.items;
    g.means = means.items;
    g.first = first;
    g.df = df;
    return g;
}

fn center(x: []f64) f64 {
    var sum: f64 = 0;
    for (x) |v| sum += v;
    const mean = sum / @as(f64, @floatFromInt(x.len));
    for (x) |*v| v.* -= mean;
    return mean;
}

pub const Fit = struct {
    sse: f64,
    /// Parameters including the intercept.
    p: usize,
    /// Design columns in the model, ascending.
    cols: []const usize = &.{},
    beta: []const f64 = &.{},
    /// sqrt of the diagonal of (X'X)^-1 per slope, and for the intercept.
    root: []const f64 = &.{},
    intercept_root: f64 = 0,
    press: f64 = 0,
};

/// ponytail: columns are centered and scaled to unit length, so the Cholesky
/// pivots are 1 - R^2 of each column on its predecessors; a pivot below 1e-10
/// is reported as a linear dependency (null) instead of being swept out.
const singular_tolerance: f64 = 1e-10;

/// Least squares of the centered response on the chosen effects. `detail`
/// also computes the coefficient standard-error roots and PRESS.
pub fn fit(a: A, g: Group, in: []const bool, detail: bool) !?Fit {
    var list: std.ArrayList(usize) = .empty;
    for (in, 0..) |yes, e| if (yes) for (g.first[e]..g.first[e] + g.df[e]) |c| try list.append(a, c);
    const m = list.items.len;
    const n = g.n;
    const nf: f64 = @floatFromInt(n);
    const scale = try a.alloc(f64, m);
    const q = try a.alloc(f64, m * n);
    for (list.items, 0..) |c, j| {
        var ss: f64 = 0;
        for (g.cols[c]) |v| ss += v * v;
        if (!(ss > 0)) return null;
        scale[j] = @sqrt(ss);
        for (g.cols[c], 0..) |v, r| q[j * n + r] = v / scale[j];
    }
    const l = try a.alloc(f64, m * m);
    @memset(l, 0);
    for (0..m) |j| for (0..j + 1) |k| {
        var sum: f64 = 0;
        for (0..n) |r| sum += q[j * n + r] * q[k * n + r];
        for (0..k) |h| sum -= l[j * m + h] * l[k * m + h];
        if (j == k) {
            if (!(sum > singular_tolerance)) return null;
            l[j * m + j] = @sqrt(sum);
        } else l[j * m + k] = sum / l[k * m + k];
    };
    // Inverse of the lower factor, then C^-1 = L^-T L^-1.
    const li = try a.alloc(f64, m * m);
    @memset(li, 0);
    for (0..m) |k| {
        li[k * m + k] = 1 / l[k * m + k];
        for (k + 1..m) |j| {
            var sum: f64 = 0;
            for (k..j) |h| sum -= l[j * m + h] * li[h * m + k];
            li[j * m + k] = sum / l[j * m + j];
        }
    }
    const ci = try a.alloc(f64, m * m);
    for (0..m) |j| for (0..m) |k| {
        var sum: f64 = 0;
        for (@max(j, k)..m) |h| sum += li[h * m + j] * li[h * m + k];
        ci[j * m + k] = sum;
    };
    const rhs = try a.alloc(f64, m);
    for (0..m) |j| {
        var sum: f64 = 0;
        for (0..n) |r| sum += q[j * n + r] * g.y[r];
        rhs[j] = sum;
    }
    const gamma = try a.alloc(f64, m);
    for (0..m) |j| {
        var sum: f64 = 0;
        for (0..m) |k| sum += ci[j * m + k] * rhs[k];
        gamma[j] = sum;
    }
    var result: Fit = .{ .sse = 0, .p = m + 1, .cols = list.items };
    const residual = try a.alloc(f64, n);
    for (0..n) |r| {
        var e = g.y[r];
        for (0..m) |j| e -= q[j * n + r] * gamma[j];
        residual[r] = e;
        result.sse += e * e;
    }
    if (!detail) return result;
    const beta = try a.alloc(f64, m);
    const root = try a.alloc(f64, m);
    for (0..m) |j| {
        beta[j] = gamma[j] / scale[j];
        root[j] = @sqrt(ci[j * m + j]) / scale[j];
    }
    var intercept: f64 = 1 / nf;
    for (0..m) |j| for (0..m) |k| {
        intercept += g.means[list.items[j]] / scale[j] * ci[j * m + k] * g.means[list.items[k]] / scale[k];
    };
    for (0..n) |r| {
        var h: f64 = 1 / nf;
        for (0..m) |j| for (0..m) |k| {
            h += q[j * n + r] * ci[j * m + k] * q[k * n + r];
        };
        const e = residual[r] / (1 - h);
        result.press += e * e;
    }
    result.beta = beta;
    result.root = root;
    result.intercept_root = @sqrt(intercept);
    return result;
}

pub const Stats = struct { mse: f64, rsq: f64, adj: f64, aic: f64, aicc: f64, bic: f64, cp: f64, sbc: f64, press: f64, ase: f64 };

/// Fit criteria, physical pp.4365-4366; sigma2 is the full-model mean square.
pub fn sbcOf(n: usize, sse: f64, p: usize) f64 {
    const nf: f64 = @floatFromInt(n);
    return nf * @log(sse / nf) + @as(f64, @floatFromInt(p)) * @log(nf);
}
pub fn statistics(g: Group, f: Fit, sigma2: f64) Stats {
    const n: f64 = @floatFromInt(g.n);
    const p: f64 = @floatFromInt(f.p);
    const base = n * @log(f.sse / n);
    const q = n * sigma2 / f.sse;
    const rsq = 1 - f.sse / g.sst;
    return .{
        .mse = f.sse / (n - p),
        .rsq = rsq,
        .adj = 1 - (n - 1) * (1 - rsq) / (n - p),
        .aic = base + 2 * p + n + 2,
        .aicc = base + n * (n + p) / (n - p - 2),
        .bic = base + 2 * (p + 2) * q - 2 * q * q,
        .cp = f.sse / sigma2 - n + 2 * p,
        .sbc = base + p * @log(n),
        .press = f.press,
        .ase = f.sse / n,
    };
}

pub const Candidate = struct { effect: usize, sbc: f64 };
pub const Step = struct {
    entered: ?usize = null,
    removed: ?usize = null,
    in: []const bool,
    effects_in: usize,
    fit: Fit,
    stats: Stats,
    f: f64 = 0,
    pf: f64 = 1,
    /// Entry or removal candidates of this step, best first.
    candidates: []const Candidate = &.{},
};
pub const Selection = struct {
    group: Group,
    steps: []const Step,
    stop_entry: ?Candidate = null,
    stop_removal: ?Candidate = null,
};

fn candidateLess(_: void, x: Candidate, y: Candidate) bool {
    return x.sbc < y.sbc;
}

/// Stepwise selection with SELECT=SBC and STOP=SBC, physical pp.4363-4364:
/// each step first tries the removal that gives the smallest SBC and takes it
/// when it lowers the criterion; otherwise the entry that gives the smallest
/// SBC when that lowers it; otherwise selection stops at a local minimum.
pub fn select(cx: proc.ProcCtx, g: Group) diag.Error!Selection {
    const a = cx.arena;
    const k = g.first.len;
    if (g.n == 0) return cx.diags.fail(error.ParseError, 0, "PROC GLMSELECT: no valid observations are present", .{});
    if (!(g.sst > 0)) return gap(cx, 0, "the result for a constant response is not verified", .{});
    const all = try a.alloc(bool, k);
    @memset(all, true);
    const full = (try fit(a, g, all, false)) orelse return gap(cx, 0, "linearly dependent effects are not implemented", .{});
    if (g.n < full.p + 3 or !(full.sse > 0)) return gap(cx, 0, "fit criteria without positive full-model error degrees of freedom are not verified", .{});
    const sigma2 = full.sse / @as(f64, @floatFromInt(g.n - full.p));
    var in = try a.alloc(bool, k);
    @memset(in, false);
    var steps: std.ArrayList(Step) = .empty;
    var current = (try fit(a, g, in, true)).?;
    try steps.append(a, .{ .in = try a.dupe(bool, in), .effects_in = 1, .fit = current, .stats = statistics(g, current, sigma2) });
    var result: Selection = .{ .group = g, .steps = &.{} };
    while (true) {
        const now = steps.items[steps.items.len - 1];
        var removal: std.ArrayList(Candidate) = .empty;
        var entry: std.ArrayList(Candidate) = .empty;
        for (0..k) |e| {
            in[e] = !in[e];
            const trial = (try fit(a, g, in, false)) orelse return gap(cx, 0, "linearly dependent effects are not implemented", .{});
            in[e] = !in[e];
            if (!(trial.sse > 0)) return gap(cx, 0, "criteria for an exact fit are not verified", .{});
            try (if (in[e]) removal else entry).append(a, .{ .effect = e, .sbc = sbcOf(g.n, trial.sse, trial.p) });
        }
        std.mem.sort(Candidate, removal.items, {}, candidateLess);
        std.mem.sort(Candidate, entry.items, {}, candidateLess);
        const remove = removal.items.len > 0 and removal.items[0].sbc < now.stats.sbc;
        const enter = !remove and entry.items.len > 0 and entry.items[0].sbc < now.stats.sbc;
        if (!remove and !enter) {
            if (entry.items.len == 0) return gap(cx, 0, "the stop reason when every effect is in the model is not verified", .{});
            result.stop_entry = entry.items[0];
            if (removal.items.len > 0) result.stop_removal = removal.items[0];
            break;
        }
        const e = if (remove) removal.items[0].effect else entry.items[0].effect;
        in[e] = !remove;
        const next = (try fit(a, g, in, true)).?;
        const larger = if (remove) current else next;
        const df2 = g.n - larger.p;
        const f = (@abs(current.sse - next.sse) / @as(f64, @floatFromInt(g.df[e]))) / (larger.sse / @as(f64, @floatFromInt(df2)));
        try steps.append(a, .{
            .entered = if (remove) null else e,
            .removed = if (remove) e else null,
            .in = try a.dupe(bool, in),
            .effects_in = now.effects_in + 1 - 2 * @as(usize, @intFromBool(remove)),
            .fit = next,
            .stats = statistics(g, next, sigma2),
            .f = f,
            .pf = reg_fit.fProbability(f, g.df[e], df2),
            .candidates = if (remove) removal.items else entry.items,
        });
        current = next;
    }
    result.steps = steps.items;
    return result;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn title(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}

const Names = struct {
    s: Spec,
    fn of(self: Names, effect: usize) []const u8 {
        const c = self.s.effects[effect];
        const ds = self.s.input.ds;
        return if (c >= ds.columns.items.len) self.s.constructed[c - ds.columns.items.len].name else ds.columns.items[c].name;
    }
};

/// Analysis of variance, fit statistics and parameter estimates of one model.
fn modelTables(a: A, out: *Out, names: Names, g: Group, st: Step) !void {
    const dfe = g.n - st.fit.p;
    try title(a, out, "Analysis of Variance", 66);
    try out.appendSlice(a, "                                  Sum of           Mean\nSource                 DF        Squares         Square    F Value\n\n");
    try out.print(a, "Model          {d:>10}", .{st.fit.p - 1});
    if (st.fit.p == 1) {
        try out.appendSlice(a, "              0              .        .  \n");
    } else {
        const ssm = g.sst - st.fit.sse;
        const msm = ssm / @as(f64, @floatFromInt(st.fit.p - 1));
        try right(a, out, try fixed(a, ssm, 5), 15);
        try right(a, out, try fixed(a, msm, 5), 15);
        try right(a, out, try fixed(a, msm / st.stats.mse, 2), 11);
        try out.append(a, '\n');
    }
    try out.print(a, "Error          {d:>10}", .{dfe});
    try right(a, out, try fixed(a, st.fit.sse, 5), 15);
    try right(a, out, try fixed(a, st.stats.mse, 5), 15);
    try out.appendSlice(a, "           \n");
    try out.print(a, "Corrected Total{d:>10}", .{g.n - 1});
    try right(a, out, try fixed(a, g.sst, 5), 15);
    try out.appendSlice(a, "                          \n\n\n");
    const x = st.stats;
    const lines = [_]struct { []const u8, f64, usize }{
        .{ "Root MSE", @sqrt(x.mse), 5 }, .{ "Dependent Mean", g.ybar, 5 }, .{ "R-Square", x.rsq, 4 }, .{ "Adj R-Sq", x.adj, 4 },
        .{ "AIC", x.aic, 5 },             .{ "AICC", x.aicc, 5 },           .{ "BIC", x.bic, 5 },      .{ "C(p)", x.cp, 5 },
        .{ "PRESS", x.press, 5 },         .{ "SBC", x.sbc, 5 },             .{ "ASE", x.ase, 5 },
    };
    for (lines) |line| {
        try left(a, out, line[0], 14);
        try right(a, out, try fixed(a, line[1], line[2]), 15);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try title(a, out, "Parameter Estimates", 58);
    try out.appendSlice(a, "                                       Standard\nParameter    DF        Estimate           Error    t Value\n\n");
    var intercept = g.ybar;
    for (st.fit.cols, st.fit.beta) |c, b| intercept -= b * g.means[c];
    const sigma = @sqrt(x.mse);
    try parameter(a, out, "Intercept", intercept, sigma * st.fit.intercept_root);
    var j: usize = 0;
    for (st.in, 0..) |yes, e| if (yes) {
        try parameter(a, out, names.of(e), st.fit.beta[j], sigma * st.fit.root[j]);
        j += 1;
    };
}
fn parameter(a: A, out: *Out, name: []const u8, estimate: f64, se: f64) !void {
    try left(a, out, name, 9);
    try out.appendSlice(a, "     1");
    try right(a, out, try fixed(a, estimate, 6), 16);
    try right(a, out, try fixed(a, se, 6), 16);
    try right(a, out, try fixed(a, estimate / se, 2), 11);
    try out.append(a, '\n');
}

fn candidates(a: A, out: *Out, names: Names, heading: []const u8, list: []const Candidate) !void {
    var w: usize = 6;
    for (list) |c| w = @max(w, names.of(c.effect).len);
    try out.appendSlice(a, "\n\n");
    try title(a, out, heading, 24 + w);
    try out.appendSlice(a, " Rank    ");
    try left(a, out, "Effect", w);
    try out.appendSlice(a, "           SBC\n\n");
    for (list, 1..) |c, rank| {
        try out.print(a, "{d:>5}    ", .{rank});
        try left(a, out, names.of(c.effect), w);
        try right(a, out, try fixed(a, c.sbc, 4), 14);
        try out.append(a, '\n');
    }
}

/// Listing boundary: values and shapes outside the reference listing's
/// proven layout are raised before any text is written.
fn check(cx: proc.ProcCtx, s: Spec, sel: Selection) diag.Error!void {
    const names: Names = .{ .s = s };
    const g = sel.group;
    for (0..s.effects.len) |e| if (names.of(e).len > 9) return gap(cx, 0, "listing columns for effect names longer than 9 characters are not verified", .{});
    if (!(g.sst < 1000 and @abs(g.ybar) < 1000)) return gap(cx, 0, "display of sums of squares or means of 1000 or more is not verified", .{});
    for (sel.steps) |st| {
        // CLASS effects compete as candidates with their L-1 degrees of
        // freedom, but their parameter rows have no layout reference.
        for (st.in, 0..) |yes, e| if (yes and s.constructedOf(s.effects[e]) != null) return gap(cx, 0, "stepwise selection of a constructed effect ({s}) is not implemented", .{names.of(e)});
        for (st.in, 0..) |yes, e| if (yes and s.isClass(s.effects[e])) return gap(cx, 0, "parameter estimates for a selected CLASS effect ({s}) are not implemented", .{names.of(e)});
        if (st.entered != null and st.candidates.len < 10) return gap(cx, 0, "the entry candidate table with fewer than 10 candidates is not verified", .{});
        const x = st.stats;
        for ([_]f64{ x.aic, x.aicc, x.bic, x.cp, x.sbc, x.press, st.f }) |v| if (!(@abs(v) < 1000)) return gap(cx, 0, "display of fit criteria of magnitude 1000 or more is not verified", .{});
        for (st.fit.beta, st.fit.root) |b, r| if (!(@abs(b) < 1000 and r * @sqrt(x.mse) < 1000)) return gap(cx, 0, "display of parameter estimates of magnitude 1000 or more is not verified", .{});
    }
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, sel: Selection, by_label: ?[]const u8) diag.Error!void {
    const a = cx.arena;
    const names: Names = .{ .s = s };
    const g = sel.group;
    const page = if (by_label) |label| try std.fmt.allocPrint(a, "\n{s}\n\nThe GLMSELECT Procedure\n", .{label}) else "\nThe GLMSELECT Procedure\n";
    try out.appendSlice(a, page);
    try out.print(a, "\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n", .{ g.read, g.n });
    if (s.classes.len > 0) {
        var name_width: usize = 5;
        var value_width: usize = 6;
        const values = try a.alloc([]const u8, s.classes.len);
        for (s.classes, g.levels, values) |c, levels, *text| {
            name_width = @max(name_width, s.input.ds.columns.items[c].name.len);
            var joined: Out = .empty;
            for (levels) |label| try joined.print(a, "{s} ", .{label});
            text.* = joined.items;
            value_width = @max(value_width, text.len);
        }
        try out.appendSlice(a, "\n\n");
        try title(a, out, "Class Level Information", name_width + 16 + value_width);
        try left(a, out, "Class", name_width);
        try out.appendSlice(a, "      Levels    Values\n\n");
        for (s.classes, g.levels, values) |c, levels, text| {
            try left(a, out, s.input.ds.columns.items[c].name, name_width);
            try out.print(a, "{d:>12}    ", .{levels.len});
            try left(a, out, text, value_width);
            try out.append(a, '\n');
        }
    }
    try out.print(a, "\n\n        Dimensions\n\nNumber of Effects   {d:>6}\nNumber of Parameters{d:>6}\n", .{ s.effects.len + 1, g.parameters });
    for (sel.steps, 0..) |st, k| {
        try out.appendSlice(a, page);
        try out.print(a, "Stepwise Selection: Step {d}\n", .{k});
        if (st.removed) |e| try out.print(a, "Effect Removed: {s}\n\n", .{names.of(e)}) else if (st.entered) |e| try out.print(a, "Effect Entered: {s}\n\n", .{names.of(e)}) else try out.appendSlice(a, "Effect Entered: Intercept \n\n");
        try modelTables(a, out, names, g, st);
        if (st.removed != null) try candidates(a, out, names, "Removal Candidates", st.candidates) else if (st.entered != null) try candidates(a, out, names, "Best 10 Entry Candidates", st.candidates[0..10]);
        try out.append(a, '\n');
        try out.appendNTimes(a, '-', 160);
        try out.appendSlice(a, "\n\n");
    }
    // Selection summary: at LINESIZE=160 the Pr > F column moves to a
    // second panel.
    try out.appendSlice(a, page);
    try out.append(a, '\n');
    try title(a, out, "Stepwise Selection Summary", 158);
    try out.appendSlice(a, "      Effect     Effect         Number   Number    Model Adjusted \n Step Entered    Removed    Effects In Parms In R-Square R-Square         AIC        AICC         BIC          CP         SBC       PRESS         ASE F Value\n\n");
    var best: [7]usize = @splat(0);
    for (sel.steps, 0..) |st, k| {
        for (&best, criteria(st.stats), 0..) |*b, v, c| {
            const held = criteria(sel.steps[b.*].stats)[c];
            if (if (c == 0) v > held else v < held) b.* = k;
        }
    }
    for (sel.steps, 0..) |st, k| {
        try summaryKey(a, out, names, st, k);
        try out.print(a, "{d:>10}{d:>9}", .{ st.effects_in, st.fit.p });
        try right(a, out, try fixed(a, st.stats.rsq, 4), 9);
        for (criteria(st.stats), 0..) |v, c| {
            try right(a, out, try fixed(a, v, 4), if (c == 0) 9 else 11);
            try out.append(a, if (best[c] == k) '*' else ' ');
        }
        try right(a, out, try fixed(a, st.stats.ase, 4), 11);
        try right(a, out, try fixed(a, st.f, 2), 8);
        try out.append(a, '\n');
        if (k == 0) {
            try out.appendNTimes(a, '-', 157);
            try out.append(a, '\n');
        }
    }
    try out.appendSlice(a, "\n                                                                 * Optimal Value of Criterion\n\n");
    try title(a, out, "Stepwise Selection Summary", 34);
    try out.appendSlice(a, "      Effect     Effect\n Step Entered    Removed    Pr > F\n\n");
    for (sel.steps, 0..) |st, k| {
        try summaryKey(a, out, names, st, k);
        try right(a, out, if (st.pf < 0.0001) "<.0001" else try fixed(a, st.pf, 4), 6);
        try out.append(a, '\n');
        if (k == 0) try out.appendSlice(a, "----------------------------------\n");
    }
    try out.appendSlice(a, "\n   * Optimal Value of Criterion\n\n\nSelection stopped at a local minimum of the SBC criterion.\n\n\n");
    const last = sel.steps[sel.steps.len - 1];
    var w: usize = 6;
    if (sel.stop_entry) |c| w = @max(w, names.of(c.effect).len);
    if (sel.stop_removal) |c| w = @max(w, names.of(c.effect).len);
    try title(a, out, "Stop Details", 46 + w);
    try out.appendSlice(a, "Candidate    ");
    try out.appendNTimes(a, ' ', w);
    try out.appendSlice(a, "     Candidate         Compare\nFor          ");
    try left(a, out, "Effect", w);
    try out.appendSlice(a, "           SBC         SBC\n\n");
    for ([_]?Candidate{ sel.stop_entry, sel.stop_removal }, [_][]const u8{ "Entry", "Removal" }) |candidate, kind| if (candidate) |c| {
        try left(a, out, kind, 13);
        try left(a, out, names.of(c.effect), w);
        try right(a, out, try fixed(a, c.sbc, 4), 14);
        try out.appendSlice(a, "    >    ");
        try left(a, out, try fixed(a, last.stats.sbc, 4), 10);
        try out.append(a, '\n');
    };
    try out.appendSlice(a, page);
    try out.print(a, "Selected Model\n\nThe selected model is the model at the last step (Step {d}).\n\n\nEffects: Intercept ", .{sel.steps.len - 1});
    for (last.in, 0..) |yes, e| if (yes) try out.print(a, "{s} ", .{names.of(e)});
    try out.appendSlice(a, "\n\n\n");
    try modelTables(a, out, names, g, last);
}

/// Starred criteria in column order: Adj R-Sq (largest is best), then AIC,
/// AICC, BIC, C(p), SBC and PRESS (smallest is best).
fn criteria(x: Stats) [7]f64 {
    return .{ x.adj, x.aic, x.aicc, x.bic, x.cp, x.sbc, x.press };
}
fn summaryKey(a: A, out: *Out, names: Names, st: Step, k: usize) !void {
    try out.print(a, "{d:>5} ", .{k});
    try left(a, out, if (st.entered) |e| names.of(e) else if (st.removed == null) "Intercept" else "", 11);
    try left(a, out, if (st.removed) |e| names.of(e) else "", 11);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    // Execution boundary of this ticket.
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, 0, "graphs under ODS GRAPHICS are not implemented", .{});
    if (s.frequency != null) return gap(cx, 0, "FREQ-weighted selection is not implemented", .{});
    if (s.weight != null) return gap(cx, 0, "WEIGHT-weighted selection is not implemented", .{});
    if (s.effects.len == 0) return gap(cx, 0, "a MODEL statement without effects is not verified", .{});
    const ds = s.input.ds;
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    if (s.selection_none) return runNone(cx, out, s, slices);
    const selections = try a.alloc(Selection, slices.len);
    for (slices, selections) |slice, *sel| {
        sel.* = try select(cx, try prepare(cx, s, slice.rows));
        if (!s.noprint) try check(cx, s, sel.*);
    }
    if (s.noprint) return;
    if (!s.details_all or !s.stats_all) return gap(cx, 0, "the listing without DETAILS=ALL and STATS=ALL is not implemented", .{});
    if (io.global_linesize != 160) return gap(cx, 0, "the selection summary panel layout is verified only for LINESIZE=160", .{});
    var body: Out = .empty;
    const response = ds.columns.items[s.response].name;
    const width = @max(s.data_name.len, response.len, 8) + 4;
    try body.appendSlice(a, "\nThe GLMSELECT Procedure\n\n");
    const info = [_]struct { []const u8, []const u8 }{ .{ "Data Set", s.data_name }, .{ "Dependent Variable", response }, .{ "Selection Method", "Stepwise" }, .{ "Select Criterion", "SBC" }, .{ "Stop Criterion", "SBC" }, .{ "Effect Hierarchy Enforced", "None" } };
    for (info) |line| {
        try left(a, &body, line[0], 25);
        try right(a, &body, line[1], width);
        try body.append(a, '\n');
    }
    for (slices, selections) |slice, sel| {
        var label: ?[]const u8 = null;
        if (s.by_cols.len > 0) {
            var text: Out = .empty;
            for (s.by_cols, 0..) |c, k| try text.print(a, "{s}{s}={s}", .{ if (k > 0) " " else "", ds.columns.items[c].name, try proc.cellText(a, slice.rows[0][c]) });
            label = text.items;
        } else try body.append(a, '\n');
        try render(cx, &body, s, sel, label);
    }
    try out.appendSlice(a, body.items);
}

/// SELECTION=NONE (STAT-COMMON-021 reference listing): the full model as
/// specified, a one-step Least Squares Summary and the fitted model's tables.
/// ponytail: only the shape of the reference listing (no BY, no DETAILS= or
/// STATS=, LINESIZE=160, values below 1000) is produced; the rest is a gap.
fn runNone(cx: proc.ProcCtx, out: *Out, s: Spec, slices: []const proc.BySlice) diag.Error!void {
    const a = cx.arena;
    if (s.details_all or s.stats_all) return gap(cx, 0, "DETAILS= or STATS= with SELECTION=NONE is not implemented", .{});
    if (s.by_cols.len > 0) return gap(cx, 0, "BY groups with SELECTION=NONE are not implemented", .{});
    const g = try prepare(cx, s, slices[0].rows);
    if (g.n == 0) return gap(cx, 0, "the result when no observation is used is not verified", .{});
    const all = try a.alloc(bool, s.effects.len);
    @memset(all, true);
    const f = (try fit(a, g, all, true)) orelse return gap(cx, 0, "linearly dependent effects are not implemented", .{});
    if (g.n <= f.p + 2) return gap(cx, 0, "a model without at least 3 error degrees of freedom is not verified", .{});
    const x = statistics(g, f, f.sse / @as(f64, @floatFromInt(g.n - f.p)));
    const sbc0 = sbcOf(g.n, g.sst, 1);
    if (s.noprint) return;
    if (io.global_linesize != 160) return gap(cx, 0, "the SELECTION=NONE listing is verified only for LINESIZE=160", .{});
    const names: Names = .{ .s = s };
    // Effect names of 9 and 10 characters are verified against SAS.
    for (0..s.effects.len) |e| if (names.of(e).len > 10) return gap(cx, 0, "listing columns for effect names longer than 10 characters with SELECTION=NONE are not verified", .{});
    var detailed: usize = 0;
    for (s.constructed) |e| detailed += @intFromBool(e.body.collection.details);
    if (detailed > 1) return gap(cx, 0, "more than one collection effect DETAILS table is not verified", .{});
    if (!(g.sst < 1000 and @abs(g.ybar) < 1000)) return gap(cx, 0, "display of sums of squares or means of 1000 or more is not verified", .{});
    for ([_]f64{ x.aic, x.aicc, x.sbc, sbc0 }) |v| if (!(@abs(v) < 1000)) return gap(cx, 0, "display of fit criteria of magnitude 1000 or more is not verified", .{});
    for (f.beta, f.root) |b, r| if (!(@abs(b) < 1000 and r * @sqrt(x.mse) < 1000)) return gap(cx, 0, "display of parameter estimates of magnitude 1000 or more is not verified", .{});
    for (s.effects) |c| if (s.isClass(c)) return gap(cx, 0, "parameter estimates of a CLASS effect with SELECTION=NONE are not implemented", .{});
    const ds = s.input.ds;
    var body: Out = .empty;
    const response = ds.columns.items[s.response].name;
    const width = @max(s.data_name.len, response.len, 4) + 4;
    try body.appendSlice(a, "\nThe GLMSELECT Procedure\n\n");
    const info = [_]struct { []const u8, []const u8 }{ .{ "Data Set", s.data_name }, .{ "Dependent Variable", response }, .{ "Selection Method", "None" } };
    for (info) |line| {
        try left(a, &body, line[0], 18);
        try right(a, &body, line[1], width);
        try body.append(a, '\n');
    }
    try body.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\n", .{ g.read, g.n });
    for (s.constructed) |e| if (e.body.collection.details) {
        // Collection DETAILS (p.426), layout as SAS/STAT 15.4 prints it.
        var values: Out = .empty;
        for (e.body.collection.vars) |v| try values.print(a, "{s} ", .{ds.columns.items[v].name});
        const vw = @max(values.items.len, 6);
        const heading = try std.fmt.allocPrint(a, "Level Details for Collection Effect {s}", .{e.name});
        try body.appendSlice(a, "\nThe GLMSELECT Procedure\n\n");
        try title(a, &body, heading, 12 + vw);
        try body.print(a, "  Levels    Values\n\n{d:>8}    ", .{e.body.collection.vars.len});
        try left(a, &body, values.items, vw);
        try body.append(a, '\n');
    };
    const counts = [_]usize{ s.effects.len + 1, g.parameters };
    var digits: usize = 1;
    for (counts) |v| digits = @max(digits, std.fmt.count("{d}", .{v}));
    try body.appendSlice(a, "\n\n");
    try body.appendNTimes(a, ' ', (14 + digits) / 2); // centered over 24 + digits
    try body.appendSlice(a, "Dimensions\n\n");
    for ([_][]const u8{ "Number of Effects", "Number of Parameters" }, counts) |label, v| {
        try left(a, &body, label, 20);
        try right(a, &body, try std.fmt.allocPrint(a, "{d}", .{v}), digits + 4);
        try body.append(a, '\n');
    }
    const page = "\nThe GLMSELECT Procedure\n";
    // Least Squares Summary: step 0 (intercept) and step 1 (every effect).
    var ew: usize = 9;
    for (0..s.effects.len) |e| ew = @max(ew, names.of(e).len);
    if (s.effects.len != 1) return gap(cx, 0, "the Least Squares Summary for more than one MODEL effect with SELECTION=NONE is not verified", .{});
    try body.appendSlice(a, page);
    try body.append(a, '\n');
    try body.appendNTimes(a, ' ', (ew + 28) / 2);
    try body.appendSlice(a, "Least Squares Summary\n \n         ");
    try left(a, &body, "Effect", ew);
    try body.appendSlice(a, "      Number      Number\n Step    ");
    try left(a, &body, "Entered", ew);
    try body.appendSlice(a, "  Effects In    Parms In           SBC \n\n");
    const best0 = sbc0 < x.sbc;
    try body.appendSlice(a, "    0    ");
    try left(a, &body, "Intercept", ew);
    try body.print(a, "{d:>12}{d:>12}", .{ 1, 1 });
    try right(a, &body, try fixed(a, sbc0, 4), 14);
    try body.append(a, if (best0) '*' else ' ');
    try body.append(a, '\n');
    try body.appendNTimes(a, '-', 48 + ew);
    try body.appendSlice(a, "\n    1    ");
    try left(a, &body, names.of(0), ew);
    try body.print(a, "{d:>12}{d:>12}", .{ s.effects.len + 1, f.p });
    try right(a, &body, try fixed(a, x.sbc, 4), 14);
    try body.append(a, if (best0) ' ' else '*');
    try body.appendSlice(a, "\n\n               * Optimal Value of Criterion\n");
    // The fitted model.
    try body.appendSlice(a, page);
    try body.appendSlice(a, "Least Squares Model (No Selection)\n\n");
    const dfm = f.p - 1;
    const dfe = g.n - f.p;
    const ssm = g.sst - f.sse;
    const msm = ssm / @as(f64, @floatFromInt(dfm));
    const fv = msm / x.mse;
    try title(a, &body, "Analysis of Variance", 76);
    try body.appendSlice(a, "                                  Sum of           Mean\nSource                 DF        Squares         Square    F Value    Pr > F\n\n");
    try body.print(a, "Model          {d:>10}", .{dfm});
    try right(a, &body, try fixed(a, ssm, 5), 15);
    try right(a, &body, try fixed(a, msm, 5), 15);
    try right(a, &body, try fixed(a, fv, 2), 11);
    try right(a, &body, try pvalue(a, reg_fit.fProbability(fv, dfm, dfe)), 10);
    try body.print(a, "\nError          {d:>10}", .{dfe});
    try right(a, &body, try fixed(a, f.sse, 5), 15);
    try right(a, &body, try fixed(a, x.mse, 5), 15);
    try body.appendNTimes(a, ' ', 21);
    try body.print(a, "\nCorrected Total{d:>10}", .{g.n - 1});
    try right(a, &body, try fixed(a, g.sst, 5), 15);
    try body.appendNTimes(a, ' ', 36);
    try body.appendSlice(a, "\n\n\n");
    const lines = [_]struct { []const u8, f64, usize }{
        .{ "Root MSE", @sqrt(x.mse), 5 }, .{ "Dependent Mean", g.ybar, 5 }, .{ "R-Square", x.rsq, 4 }, .{ "Adj R-Sq", x.adj, 4 },
        .{ "AIC", x.aic, 5 },             .{ "AICC", x.aicc, 5 },           .{ "SBC", x.sbc, 5 },
    };
    for (lines) |line| {
        try left(a, &body, line[0], 14);
        try right(a, &body, try fixed(a, line[1], line[2]), 15);
        try body.append(a, '\n');
    }
    // Parameter labels: the effect name in a column as wide as "Intercept"
    // and the longest effect name, then the constituent column name.
    var labels: std.ArrayList([]const u8) = .empty;
    for (s.effects, 0..) |c, e| {
        if (s.constructedOf(c)) |col| {
            for (col.vars) |v| {
                var label: Out = .empty;
                try left(a, &label, names.of(e), ew + 1);
                try label.appendSlice(a, ds.columns.items[v].name);
                try labels.append(a, label.items);
            }
        } else try labels.append(a, names.of(e));
    }
    var lw: usize = 9;
    for (labels.items) |l| lw = @max(lw, l.len);
    try body.appendSlice(a, "\n\n");
    try title(a, &body, "Parameter Estimates", lw + 61);
    try body.appendNTimes(a, ' ', lw + 30);
    try body.appendSlice(a, "Standard\n");
    try left(a, &body, "Parameter", lw);
    try body.appendSlice(a, "    DF        Estimate           Error    t Value    Pr > |t|\n\n");
    var intercept = g.ybar;
    for (f.cols, f.beta) |c, b| intercept -= b * g.means[c];
    const sigma = @sqrt(x.mse);
    for (0..labels.items.len + 1) |k| {
        const est = if (k == 0) intercept else f.beta[k - 1];
        const se = sigma * (if (k == 0) f.intercept_root else f.root[k - 1]);
        try left(a, &body, if (k == 0) "Intercept" else labels.items[k - 1], lw);
        try body.appendSlice(a, "     1");
        try right(a, &body, try fixed(a, est, 6), 16);
        try right(a, &body, try fixed(a, se, 6), 16);
        try right(a, &body, try fixed(a, est / se, 2), 11);
        try right(a, &body, try pvalue(a, reg_fit.tProbability(est / se, dfe)), 12);
        try body.append(a, '\n');
    }
    try out.appendSlice(a, body.items);
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else fixed(a, p, 4);
}

test {
    _ = @import("glmselect_tests.zig");
}
