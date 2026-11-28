//! PROC HPLOGISTIC data input, variable roles and the default binary logit
//! fit, SAS/STAT 15.4 Chapter 61 (PROC HPLOGISTIC statement pp.4746-4751,
//! BY pp.4751-4752, FREQ p.4753, ID p.4753, WEIGHT p.4764, Missing Values
//! pp.4764-4765). The default fit is a binary logit maximum-likelihood model
//! with GLM-parameterized CLASS main effects, solved by Newton-Raphson on the
//! objective -logL/sum(freq) (NORMALIZE=YES). Pinned against SAS 15.4
//! reference runs (ITDETAILS): the iteration-0 parameters are the weighted
//! least-squares fit of the IRLS working response at mu0 = 5/6 (event) and
//! 1/6 (nonevent); each iteration is a full Newton step; GCONV at iteration k
//! uses the Newton decrement g'H^-1 g of iteration k-1 over |f_k|, and is
//! tested before ABSGCONV (max |g_k| <= 1E-7). Everything else documented
//! (SELECTION, OUTPUT, CODE, PARTITION, PERFORMANCE, model options,
//! interactions, multinomial or character responses, the other optimization
//! options) is a D-009 gap (rc 2) raised before any listing text.
const std = @import("std");
const proc = @import("../proc.zig");
const hp = @import("hp_shared.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const lf = @import("logistic_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Effect = struct { col: usize, class: bool };

pub const Spec = struct {
    ds: *Dataset,
    data_name: []const u8,
    response: usize = 0,
    effects: []const Effect = &.{},
    classes: []const usize = &.{},
    freq: ?usize = null,
    weight: ?usize = null,
    ids: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    noprint: bool = false,
    noitprint: bool = false,
    alpha: f64 = 0.05,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC HPLOGISTIC: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC HPLOGISTIC: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC HPLOGISTIC: " ++ text, args);
}
fn upper(a: A, s: []const u8) ![]const u8 {
    return std.ascii.allocUpperString(a, s);
}

fn dsName(a: A, cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        if (!at(t, i.* + 1, .name)) return invalid(cx, t, i.* + 1);
        name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    return name;
}

fn column(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{try upper(cx.arena, t[i].text)});
}

/// Variable names (lists such as x1-x10 expanded) in t[start..end].
fn names(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, start: usize, end: usize) diag.Error![]usize {
    const a = cx.arena;
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        if (!at(t, j, .name)) return invalid(cx, t, j);
        const line = t[j].line;
        const got = try lists.next(a, ds, t[0..end], &j, cx.diags);
        for (got) |n| try cols.append(a, ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{try upper(a, n)}));
    }
    return cols.items;
}

/// PROC statement options documented on pp.4746-4751 that this ticket does
/// not implement: each is a visible gap, never a silent no-op.
const gap_options = [_][]const u8{ "absconv", "abstol", "absfconv", "absftol", "absgconv", "absgtol", "fconv", "ftol", "fmtlibxml", "gconv", "gtol", "inest", "itdetails", "itselect", "maxfunc", "maxfu", "maxiter", "maxit", "maxtime", "miniter", "minit", "namelen", "normalize", "nostderr", "outest", "singchol", "singsweep", "singular", "technique", "tech", "nocluster", "nclass" };

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var data: ?[]const u8 = null;
    var s: Spec = .{ .ds = undefined, .data_name = "" };
    var i: usize = 2;
    const l0 = lineOf(t, 0);
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return user(cx, t[i].line, "DATA= is specified more than once", .{});
            i += 2;
            data = try dsName(a, cx, t, &i);
            if (at(t, i, .lparen)) {
                var depth: usize = 0;
                while (i < t.len and !at(t, i, .eof)) : (i += 1) {
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                if (!at(t, i, .rparen)) return invalid(cx, t, i);
                i += 1;
            }
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(v > 0 and v < 1)) return user(cx, t[i].line, "ALPHA= must be between 0 and 1", .{});
            // ALPHA= only sets confidence levels of tables this ticket does
            // not print (CL, STAT-HPLOGISTIC-00x); the default listing is unchanged.
            s.alpha = v;
            i += 3;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "noitprint")) {
            s.noitprint = true;
            i += 1;
        } else {
            for (gap_options) |g| if (eq(word, g)) return gap(cx, t[i].line, "the {s} option is not implemented", .{try upper(a, word)});
            return invalid(cx, t, i);
        }
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = if (data) |name|
        cx.lib.find(name) orelse return user(cx, l0, "input data set {s} not found", .{name})
    else
        proc.lastDataset(cx.lib) orelse return user(cx, l0, "there is no default input data set (_LAST_ is _NULL_)", .{});
    s.ds = try proc.procInput(a, raw, t, cx.diags);
    const nm = data orelse raw.name;
    s.data_name = if (std.mem.indexOfScalar(u8, nm, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{try upper(a, nm)}) else try upper(a, nm);

    var bys: by.Statements = .{};
    var by_seen = false;
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
    var model_tokens: ?[2]usize = null;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const line = t[i].line;
        if (kw(t, i, "model")) {
            if (model_seen) return gap(cx, line, "more than one MODEL statement is not verified", .{});
            model_seen = true;
            model_tokens = .{ i, end };
        } else if (kw(t, i, "class")) {
            if (model_seen) return user(cx, line, "the CLASS statement must precede the MODEL statement", .{});
            for (i + 1..end) |j| if (!at(t, j, .name) and !at(t, j, .minus)) return gap(cx, line, "CLASS statement options are not implemented", .{});
            for (try names(cx, s.ds, t, i + 1, end)) |c| {
                for (classes.items) |p| if (p == c) return user(cx, line, "CLASS variable {s} is listed more than once", .{s.ds.columns.items[c].name});
                try classes.append(a, c);
            }
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            const is_freq = kw(t, i, "freq");
            const role: []const u8 = if (is_freq) "FREQ" else "WEIGHT";
            if (end != i + 2) return user(cx, line, "the {s} statement takes exactly one variable", .{role});
            if ((if (is_freq) s.freq else s.weight) != null) return gap(cx, line, "more than one {s} statement is not verified", .{role});
            const c = try column(cx, s.ds, t, i + 1);
            if (s.ds.columns.items[c].type != .num) return user(cx, line, "{s} variable {s} must be numeric", .{ role, s.ds.columns.items[c].name });
            if (is_freq) s.freq = c else s.weight = c;
        } else if (kw(t, i, "id")) {
            // ID variables only reach OUTPUT data sets (p.4753), which this
            // ticket does not write; they are validated and otherwise inert.
            if (end == i + 1) return invalid(cx, t, end);
            for (try names(cx, s.ds, t, i + 1, end)) |c| try ids.append(a, c);
        } else if (kw(t, i, "by")) {
            // "If you specify more than one BY statement, only the last one
            // specified is used" (p.4751).
            by_seen = true;
            bys = .{};
            var j = i;
            try bys.read(a, t, &j);
        } else if (kw(t, i, "run") or kw(t, i, "quit") or kw(t, i, "where")) {
            // Step boundaries; WHERE is applied by procInput.
        } else if (kw(t, i, "performance")) {
            // Shared single-machine PERFORMANCE contract (STAT-HP-001).
            var perf: hp.Performance = .{};
            try hp.parsePerformance(cx.diags, "HPLOGISTIC", t, i, end, &perf);
        } else if (kw(t, i, "selection") or kw(t, i, "output") or kw(t, i, "code") or kw(t, i, "partition") or kw(t, i, "format") or kw(t, i, "label") or kw(t, i, "attrib")) {
            return gap(cx, line, "the {s} statement is not implemented", .{try upper(a, t[i].text)});
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return user(cx, l0, "a MODEL statement is required", .{});
    s.classes = classes.items;
    s.ids = ids.items;
    try parseModel(cx, &s, t, model_tokens.?[0], model_tokens.?[1]);
    if (by_seen) {
        const resolved = try bys.resolve(a, s.ds, cx.diags);
        const cols = try a.alloc(usize, resolved.names.len);
        for (resolved.names, cols) |n, *c| c.* = s.ds.indexOf(n).?;
        s.by_cols = cols;
        s.by_desc = resolved.desc;
        s.notsorted = resolved.notsorted;
    }
    return s;
}

fn parseModel(cx: proc.ProcCtx, s: *Spec, t: []const lex.Token, start: usize, end: usize) diag.Error!void {
    const a = cx.arena;
    const line = t[start].line;
    var i = start + 1;
    if (!at(t, i, .name)) return user(cx, line, "the MODEL statement needs response = effects", .{});
    if (at(t, i + 1, .slash)) return gap(cx, line, "the events/trials response syntax is not implemented", .{});
    if (at(t, i + 1, .lparen)) return gap(cx, line, "response variable options are not implemented", .{});
    s.response = try column(cx, s.ds, t, i);
    i += 1;
    if (!at(t, i, .eq)) return user(cx, line, "the MODEL statement needs response = effects", .{});
    i += 1;
    var stop = i;
    while (stop < end and !at(t, stop, .slash)) : (stop += 1) {
        if (at(t, stop, .star) or at(t, stop, .pipe) or at(t, stop, .lparen) or at(t, stop, .at)) return gap(cx, line, "interaction, nested and polynomial effects are not implemented", .{});
    }
    if (stop < end) return gap(cx, line, "MODEL statement options are not implemented", .{});
    if (stop == i) return gap(cx, line, "an intercept-only model is not verified", .{});
    var effects: std.ArrayList(Effect) = .empty;
    for (try names(cx, s.ds, t, i, stop)) |c| {
        if (c == s.response) return user(cx, line, "the response variable {s} cannot also be an explanatory effect", .{s.ds.columns.items[c].name});
        for (effects.items) |e| if (e.col == c) return gap(cx, line, "effect {s} is listed more than once; the rule is not verified", .{s.ds.columns.items[c].name});
        var is_class = false;
        for (s.classes) |k| if (k == c) {
            is_class = true;
        };
        if (!is_class and s.ds.columns.items[c].type != .num) return user(cx, line, "variable {s} in the MODEL statement must be numeric or listed in the CLASS statement", .{s.ds.columns.items[c].name});
        try effects.append(a, .{ .col = c, .class = is_class });
    }
    for (s.classes) |k| {
        var used = k == s.response;
        for (effects.items) |e| if (e.col == k) {
            used = true;
        };
        if (!used) return gap(cx, line, "a CLASS variable that is not in the MODEL statement is not verified", .{});
    }
    if (s.ds.columns.items[s.response].type != .num) return gap(cx, line, "a character response variable is not verified", .{});
    if (s.ds.columns.items[s.response].format != null) return gap(cx, line, "a formatted response variable is not verified", .{});
    for (s.classes) |k| if (s.ds.columns.items[k].format != null) return gap(cx, line, "formatted CLASS variables are not verified", .{});
    s.effects = effects.items;
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |x| std.mem.trim(u8, x, " ").len == 0,
    };
}

fn levelText(a: A, v: Value) ![]const u8 {
    return switch (v) {
        .str => |x| std.mem.trimEnd(u8, x, " "),
        .num => |x| std.mem.trim(u8, try format.bestNumW(a, x, 12), " "),
    };
}

fn lessValue(_: void, x: Value, y: Value) bool {
    return switch (x) {
        .num => |p| p < y.num,
        .str => |p| std.mem.order(u8, std.mem.trimEnd(u8, p, " "), std.mem.trimEnd(u8, y.str, " ")) == .lt,
    };
}

fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |p| p == y.num,
        .str => |p| std.mem.eql(u8, std.mem.trimEnd(u8, p, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}

/// Sorted distinct values of column c over the used rows.
fn levels(a: A, rows: []const []const Value, used: []const usize, c: usize) ![]Value {
    var vals: std.ArrayList(Value) = .empty;
    for (used) |r| {
        const v = rows[r][c];
        var seen = false;
        for (vals.items) |w| if (sameValue(v, w)) {
            seen = true;
            break;
        };
        if (!seen) try vals.append(a, v);
    }
    std.mem.sort(Value, vals.items, {}, lessValue);
    return vals.items;
}

pub const Iter = struct { f: f64, change: ?f64, max_grad: f64 };
pub const Stop = enum { gconv, absgconv };

pub const Result = struct {
    beta: []f64,
    cov: []f64,
    history: []Iter,
    stop: Stop,
    ll: f64,
};

fn cholSolve(a: A, h: []const f64, p: usize, b: []const f64) !?[]f64 {
    const l = try a.dupe(f64, h);
    for (0..p) |j| {
        var d = l[j * p + j];
        for (0..j) |k| d -= l[j * p + k] * l[j * p + k];
        if (!(d > 0)) return null;
        d = @sqrt(d);
        l[j * p + j] = d;
        for (j + 1..p) |i| {
            var v = l[i * p + j];
            for (0..j) |k| v -= l[i * p + k] * l[j * p + k];
            l[i * p + j] = v / d;
        }
    }
    const x = try a.dupe(f64, b);
    for (0..p) |i| {
        var v = x[i];
        for (0..i) |k| v -= l[i * p + k] * x[k];
        x[i] = v / l[i * p + i];
    }
    var i = p;
    while (i > 0) {
        i -= 1;
        var v = x[i];
        for (i + 1..p) |k| v -= l[k * p + i] * x[k];
        x[i] = v / l[i * p + i];
    }
    return x;
}

fn objective(x: []const f64, y: []const f64, m: []const f64, b: []const f64, norm: f64) f64 {
    const p = b.len;
    var s: f64 = 0;
    for (y, 0..) |v, i| {
        var eta: f64 = 0;
        for (0..p) |j| eta += x[i * p + j] * b[j];
        // -log P(observed): softplus(-eta) for an event, softplus(eta) otherwise.
        const z = if (v == 1) -eta else eta;
        s += m[i] * (@max(0, z) + std.math.log1p(@exp(-@abs(z))));
    }
    return s / norm;
}

/// Binary logit fit on a full-rank design x (n*p), event indicator y,
/// multiplicity m = freq*weight, normalized by norm = sum(freq).
pub fn fit(a: A, x: []const f64, y: []const f64, m: []const f64, n: usize, p: usize, norm: f64) !?Result {
    // Iteration 0: weighted least squares of the IRLS working response at
    // mu0 = 5/6 for events, 1/6 otherwise.
    const xtx = try a.alloc(f64, p * p);
    const xtz = try a.alloc(f64, p);
    @memset(xtx, 0);
    @memset(xtz, 0);
    const mu_event: f64 = 5.0 / 6.0;
    const w0 = mu_event * (1 - mu_event);
    const eta0 = @log(mu_event / (1 - mu_event));
    for (0..n) |i| {
        const z = if (y[i] == 1) eta0 + (1 - mu_event) / w0 else -eta0 - (1 - mu_event) / w0;
        const w = m[i] * w0;
        for (0..p) |j| {
            xtz[j] += w * x[i * p + j] * z;
            for (0..p) |k| xtx[j * p + k] += w * x[i * p + j] * x[i * p + k];
        }
    }
    var b = (try cholSolve(a, xtx, p, xtz)) orelse return null;
    var history: std.ArrayList(Iter) = .empty;
    const g = try a.alloc(f64, p);
    const h = try a.alloc(f64, p * p);
    var prev_f: ?f64 = null;
    var prev_dec: ?f64 = null;
    var iter: usize = 0;
    while (iter <= 50) : (iter += 1) {
        @memset(g, 0);
        @memset(h, 0);
        for (0..n) |i| {
            var eta: f64 = 0;
            for (0..p) |j| eta += x[i * p + j] * b[j];
            const mu = lf.probability(eta);
            const r = m[i] * (mu - y[i]) / norm;
            const w = m[i] * mu * (1 - mu) / norm;
            for (0..p) |j| {
                g[j] += r * x[i * p + j];
                for (0..p) |k| h[j * p + k] += w * x[i * p + j] * x[i * p + k];
            }
        }
        const f = objective(x, y, m, b, norm);
        var mg: f64 = 0;
        for (g) |v| mg = @max(mg, @abs(v));
        if (prev_f) |pf| if (!(f <= pf)) return null; // a full step that does not improve needs ridging: gap
        try history.append(a, .{ .f = f, .change = if (prev_f) |pf| pf - f else null, .max_grad = mg });
        var stop: ?Stop = null;
        if (prev_dec) |dec| if (dec / @abs(f) <= 1e-8) {
            stop = .gconv;
        };
        if (stop == null and mg <= 1e-7) stop = .absgconv;
        const d = (try cholSolve(a, h, p, g)) orelse return null;
        if (stop) |st| {
            // Covariance: inverse of the unnormalized information.
            const cov = try a.alloc(f64, p * p);
            const e = try a.alloc(f64, p);
            for (0..p) |c| {
                @memset(e, 0);
                e[c] = 1;
                const col = (try cholSolve(a, h, p, e)) orelse return null;
                for (0..p) |r| cov[r * p + c] = col[r] / norm;
            }
            return .{ .beta = b, .cov = cov, .history = history.items, .stop = st, .ll = -f * norm };
        }
        var dec: f64 = 0;
        for (g, d) |gv, dv| dec += gv * dv;
        prev_dec = dec;
        prev_f = f;
        const nb = try a.alloc(f64, p);
        for (0..p) |j| nb[j] = b[j] - d[j];
        b = nb;
    }
    return null;
}

fn pad(a: A, out: *Out, n: usize) !void {
    try out.appendNTimes(a, ' ', n);
}
fn title(a: A, out: *Out, text: []const u8, width: usize) !void {
    try pad(a, out, (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    try pad(a, out, width -| text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    try pad(a, out, width -| text.len);
}

const Pair = struct { label: []const u8, value: []const u8 };

/// Label/value table with left-aligned values padded to the widest value.
fn infoTable(a: A, out: *Out, name: ?[]const u8, rows: []const Pair) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (rows) |r| {
        lw = @max(lw, r.label.len);
        vw = @max(vw, r.value.len);
    }
    if (name) |n| {
        try title(a, out, n, lw + 4 + vw);
        try out.append(a, '\n');
    }
    for (rows) |r| {
        try left(a, out, r.label, lw + 4);
        try left(a, out, r.value, vw);
        try out.append(a, '\n');
    }
}

/// Label/value table with values right-aligned so each line is `width` long.
fn countTable(a: A, out: *Out, name: ?[]const u8, rows: []const Pair, width: usize) !void {
    if (name) |n| {
        try title(a, out, n, width);
        try out.append(a, '\n');
    }
    for (rows) |r| {
        try out.appendSlice(a, r.label);
        try right(a, out, r.value, width - r.label.len);
        try out.append(a, '\n');
    }
}

fn fixed(a: A, x: f64, d: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, d });
}

/// Estimates and standard errors (SAS 15.4 reference listings): at least 4
/// decimals and 4 significant digits within 8 characters; BEST8. when fewer
/// than two significant digits would remain.
fn estimate(cx: proc.ProcCtx, x: f64) ![]const u8 {
    const a = cx.arena;
    if (x == 0) return "0";
    const ax = @abs(x);
    if (ax >= 100) return gap(cx, 0, "the display of an estimate or standard error of 100 or more is not verified", .{});
    const mag: i64 = @intFromFloat(@floor(std.math.log10(ax)));
    var d: usize = @intCast(@max(4, 3 - mag));
    var s = try fixed(a, x, d);
    while (s.len > 8 and d > 0) {
        d -= 1;
        s = try fixed(a, x, d);
    }
    // Significant digits shown: d - (number of leading zero decimals).
    const lead: i64 = if (mag < 0) -mag - 1 else 0;
    if (@as(i64, @intCast(d)) - lead < 2) return std.mem.trim(u8, try format.bestNumW(a, x, 8), " ");
    return s;
}

/// Fit statistics: 4 decimals below 100, 2 below 1000, none from 10000
/// (reference listings); four integer digits and a million or more are not
/// verified.
fn fitStat(cx: proc.ProcCtx, x: f64) ![]const u8 {
    const ax = @abs(x);
    if (ax < 100) return fixed(cx.arena, x, 4);
    if (ax < 1000) return fixed(cx.arena, x, 2);
    if (ax >= 10000 and ax < 100000) return fixed(cx.arena, x, 0);
    return gap(cx, 0, "the display of a fit statistic between 1000 and 10000 or of 100000 or more is not verified", .{});
}

/// BEST8. as the SAS 15.4 reference listings show it below 1: fixed notation
/// (trailing zeros dropped) while it keeps two significant digits, otherwise
/// E notation. ponytail: the shared bestNumW picks E notation for values such
/// as 0.00051 (reported to the coordinator; Base format code is not changed).
fn best8(a: A, x: f64) ![]const u8 {
    const ax = @abs(x);
    if (x == 0 or ax >= 1 or x < 0) return std.mem.trim(u8, try format.bestNumW(a, x, 8), " ");
    const mag: i64 = @intFromFloat(@floor(std.math.log10(ax)));
    if (6 - (-mag - 1) >= 2) {
        const s = try fixed(a, x, 6);
        if (std.mem.indexOfScalar(u8, s, '.') != null) return std.mem.trimEnd(u8, std.mem.trimEnd(u8, s, "0"), ".");
        return s;
    }
    return std.mem.trim(u8, try format.bestNumW(a, x, 8), " ");
}

fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return fixed(a, p, 4);
}

const Group = struct {
    read: usize,
    used: []usize,
    freq_read: f64,
    freq_used: f64,
};

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    const slices = try by.checkedSlices(a, s.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const cols = s.ds.columns.items;
    if (s.ds.rows.items.len == 0) return gap(cx, 0, "an input data set with no observations is not verified", .{});

    // Validate and fit every group before any listing text.
    const Fitted = struct {
        g: Group,
        resp: []Value,
        resp_freq: [2]f64,
        class_levels: [][]Value,
        names: [][]const u8,
        aliased: []bool,
        beta: []f64,
        se: []f64,
        res: Result,
        columns: usize,
        max_cols: usize,
        rank: usize,
        null_ll: f64,
    };
    const fits = try a.alloc(Fitted, slices.len);
    var truncated = false;
    for (slices, fits) |slice, *ft| {
        var used: std.ArrayList(usize) = .empty;
        var freq_read: f64 = 0;
        var freq_used: f64 = 0;
        for (slice.rows, 0..) |row, r| {
            var ok = !isMissing(row[s.response]);
            for (s.effects) |e| if (isMissing(row[e.col])) {
                ok = false;
            };
            if (s.freq) |fc| {
                const fv = row[fc].num;
                if (std.math.isNan(fv) or fv < 1) return gap(cx, 0, "the Sum of Frequencies Read with a missing or less-than-one FREQ value is not verified", .{});
                if (fv != @floor(fv)) truncated = true;
                freq_read += @floor(fv);
            }
            if (s.weight) |wc| {
                const wv = row[wc].num;
                if (std.math.isNan(wv) or !(wv > 0)) ok = false;
            }
            if (ok) {
                try used.append(a, r);
                if (s.freq) |fc| freq_used += @floor(row[fc].num);
            }
        }
        if (s.freq == null) {
            freq_read = @floatFromInt(slice.rows.len);
            freq_used = @floatFromInt(used.items.len);
        }
        if (used.items.len == 0) return gap(cx, 0, "a BY group or data set with no usable observations is not verified", .{});
        const resp = try levels(a, slice.rows, used.items, s.response);
        if (resp.len == 1) return gap(cx, 0, "a response with a single level is not verified", .{});
        if (resp.len > 2) return gap(cx, 0, "a response with more than two levels (multinomial models) is not implemented", .{});
        const class_levels = try a.alloc([]Value, s.effects.len);
        var columns: usize = 1;
        var max_cols: usize = 1;
        for (s.effects, class_levels) |e, *lv| {
            lv.* = if (e.class) try levels(a, slice.rows, used.items, e.col) else &.{};
            const k = if (e.class) lv.len else 1;
            columns += k;
            max_cols = @max(max_cols, k);
        }
        // Design (GLM parameterization) and parameter names.
        const n = used.items.len;
        const xfull = try a.alloc(f64, n * columns);
        const pnames = try a.alloc([]const u8, columns);
        pnames[0] = "Intercept";
        {
            var c: usize = 1;
            for (s.effects, class_levels) |e, lv| {
                if (e.class) {
                    for (lv) |l| {
                        pnames[c] = try std.fmt.allocPrint(a, "{s} {s}", .{ cols[e.col].name, try levelText(a, l) });
                        c += 1;
                    }
                } else {
                    pnames[c] = cols[e.col].name;
                    c += 1;
                }
            }
        }
        const y = try a.alloc(f64, n);
        const m = try a.alloc(f64, n);
        var resp_freq = [2]f64{ 0, 0 };
        for (used.items, 0..) |r, i| {
            const row = slice.rows[r];
            const xi = xfull[i * columns ..][0..columns];
            xi[0] = 1;
            var c: usize = 1;
            for (s.effects, class_levels) |e, lv| {
                if (e.class) {
                    for (lv) |l| {
                        xi[c] = if (sameValue(row[e.col], l)) 1 else 0;
                        c += 1;
                    }
                } else {
                    xi[c] = row[e.col].num;
                    c += 1;
                }
            }
            const event = sameValue(row[s.response], resp[0]);
            y[i] = if (event) 1 else 0;
            const fq: f64 = if (s.freq) |fc| @floor(row[fc].num) else 1;
            const wt: f64 = if (s.weight) |wc| row[wc].num else 1;
            m[i] = fq * wt;
            resp_freq[if (event) 0 else 1] += fq;
        }
        // Aliasing: sweep X'MX in column order (GLM parameterization).
        const xtx = try a.alloc(f64, columns * columns);
        @memset(xtx, 0);
        for (0..n) |i| for (0..columns) |j| for (0..columns) |k| {
            xtx[j * columns + k] += m[i] * xfull[i * columns + j] * xfull[i * columns + k];
        };
        const orig = try a.alloc(f64, columns);
        for (0..columns) |j| orig[j] = xtx[j * columns + j];
        const aliased = try a.alloc(bool, columns);
        @memset(aliased, false);
        for (0..columns) |k| {
            const piv = xtx[k * columns + k];
            if (!(piv > 1e-12 * @max(orig[k], 1e-300))) {
                aliased[k] = true;
                continue;
            }
            for (0..columns) |i| if (i != k) {
                const f = xtx[i * columns + k] / piv;
                for (0..columns) |j| xtx[i * columns + j] -= f * xtx[k * columns + j];
            };
        }
        var rank: usize = 0;
        for (aliased) |al| {
            if (!al) rank += 1;
        }
        const xr = try a.alloc(f64, n * rank);
        for (0..n) |i| {
            var c: usize = 0;
            for (0..columns) |j| if (!aliased[j]) {
                xr[i * rank + c] = xfull[i * columns + j];
                c += 1;
            };
        }
        const res = (try fit(a, xr, y, m, n, rank, freq_used)) orelse return gap(cx, 0, "the optimization needs ridging, line search or more than 50 iterations, which is not verified", .{});
        const beta = try a.alloc(f64, columns);
        const se = try a.alloc(f64, columns);
        {
            var c: usize = 0;
            for (0..columns) |j| {
                if (aliased[j]) {
                    beta[j] = 0;
                    se[j] = std.math.nan(f64);
                } else {
                    beta[j] = res.beta[c];
                    se[j] = @sqrt(res.cov[c * rank + c]);
                    c += 1;
                }
            }
        }
        var tm: f64 = 0;
        var te: f64 = 0;
        for (y, m) |yv, mv| {
            tm += mv;
            te += mv * yv;
        }
        const pe = te / tm;
        const null_ll = te * @log(pe) + (tm - te) * std.math.log1p(-pe);
        ft.* = .{
            .g = .{ .read = slice.rows.len, .used = used.items, .freq_read = freq_read, .freq_used = freq_used },
            .resp = resp,
            .resp_freq = resp_freq,
            .class_levels = class_levels,
            .names = pnames,
            .aliased = aliased,
            .beta = beta,
            .se = se,
            .res = res,
            .columns = columns,
            .max_cols = max_cols,
            .rank = rank,
            .null_ll = null_ll,
        };
    }
    try cx.diags.note(0, "The HPLOGISTIC procedure is executing in single-machine mode.", .{});
    if (truncated) try cx.diags.note(0, "At least one frequency has been truncated because of a non-integer value.", .{});

    // Render everything into a scratch buffer first so a display gap leaves
    // no partial listing.
    var body: Out = .empty;
    const o = &body;
    try pageStart(cx, o);
    try o.appendSlice(a, "\nThe HPLOGISTIC Procedure\n\n");
    // opensas computes on one thread (as PROC HPPRINCOMP, HPREG and
    // HPGENSELECT report); thread semantics belong to STAT-HP-002.
    try infoTable(a, o, "Performance Information", &.{
        .{ .label = "Execution Mode", .value = "Single-Machine" },
        .{ .label = "Number of Threads", .value = "1" },
    });
    {
        const dw = @max(4, s.data_name.len);
        const width = dw + 4 + 6 + 4 + 5 + 4 + 9;
        try o.appendSlice(a, "\n\n");
        try title(a, o, "Data Access Information", width);
        try o.appendSlice(a, " \n");
        try left(a, o, "Data", dw + 4);
        try o.appendSlice(a, "Engine    Role     Path\n\n");
        try left(a, o, s.data_name, dw + 4);
        try o.appendSlice(a, "V9        Input    On Client\n");
    }
    for (slices, fits, 0..) |slice, ft, gi| {
        if (s.by_cols.len > 0) {
            if (gi > 0) try pageStart(cx, o);
            try o.append(a, '\n');
            var line: Out = .empty;
            try by.appendLine(a, &line, s.ds, slice.rep.?, s.by_cols);
            if (line.items.len > 0) try o.appendSlice(a, std.mem.trim(u8, line.items, " \n"));
            try o.appendSlice(a, "\n\nThe HPLOGISTIC Procedure\n\n");
        } else try o.appendSlice(a, "\n\n");
        var mi: std.ArrayList(Pair) = .empty;
        try mi.append(a, .{ .label = "Data Source", .value = s.data_name });
        try mi.append(a, .{ .label = "Response Variable", .value = cols[s.response].name });
        if (s.weight) |wc| try mi.append(a, .{ .label = "Weight Variable", .value = cols[wc].name });
        if (s.freq) |fc| try mi.append(a, .{ .label = "Frequency Variable", .value = cols[fc].name });
        if (s.classes.len > 0) try mi.append(a, .{ .label = "Class Parameterization", .value = "GLM" });
        try mi.append(a, .{ .label = "Distribution", .value = "Binary" });
        try mi.append(a, .{ .label = "Link Function", .value = "Logit" });
        try mi.append(a, .{ .label = "Optimization Technique", .value = "Newton-Raphson with Ridging" });
        try infoTable(a, o, "Model Information", mi.items);

        if (s.classes.len > 0) {
            var cw: usize = 5;
            var vw: usize = 6;
            const texts = try a.alloc([]const u8, s.classes.len);
            for (s.classes, texts) |k, *tx| {
                cw = @max(cw, cols[k].name.len);
                var buf: Out = .empty;
                const lv = if (k == s.response) ft.resp else blk: {
                    for (s.effects, ft.class_levels) |e, l| if (e.col == k) break :blk l;
                    unreachable;
                };
                for (lv) |l| {
                    try buf.appendSlice(a, try levelText(a, l));
                    try buf.append(a, ' ');
                }
                tx.* = buf.items;
                vw = @max(vw, buf.items.len);
            }
            try o.appendSlice(a, "\n\n");
            try title(a, o, "Class Level Information", cw + 4 + 6 + 4 + vw);
            try o.appendSlice(a, " \n");
            try left(a, o, "Class", cw + 4);
            try o.appendSlice(a, "Levels    ");
            try o.appendSlice(a, "Values");
            try o.appendSlice(a, "\n\n");
            for (s.classes, texts) |k, tx| {
                const nl = if (k == s.response) ft.resp.len else blk: {
                    for (s.effects, ft.class_levels) |e, l| if (e.col == k) break :blk l.len;
                    unreachable;
                };
                try left(a, o, cols[k].name, cw);
                try right(a, o, try std.fmt.allocPrint(a, "{d}", .{nl}), 10);
                try pad(a, o, 4);
                try left(a, o, tx, vw);
                try o.append(a, '\n');
            }
        }
        {
            var rows: std.ArrayList(Pair) = .empty;
            try rows.append(a, .{ .label = "Number of Observations Read", .value = try std.fmt.allocPrint(a, "{d}", .{ft.g.read}) });
            try rows.append(a, .{ .label = "Number of Observations Used", .value = try std.fmt.allocPrint(a, "{d}", .{ft.g.used.len}) });
            if (s.freq != null) {
                try rows.append(a, .{ .label = "Sum of Frequencies Read", .value = try std.fmt.allocPrint(a, "{d}", .{ft.g.freq_read}) });
                try rows.append(a, .{ .label = "Sum of Frequencies Used", .value = try std.fmt.allocPrint(a, "{d}", .{ft.g.freq_used}) });
            }
            try o.appendSlice(a, "\n\n");
            try countTable(a, o, null, rows.items, 43);
        }
        const rname = cols[s.response].name;
        const lv0 = try levelText(a, ft.resp[0]);
        const lv1 = try levelText(a, ft.resp[1]);
        {
            const yw = @max(rname.len, @max(lv0.len, lv1.len));
            try o.appendSlice(a, "\n\n");
            try title(a, o, "Response Profile", 12 + 4 + yw + 4 + 9);
            try o.appendSlice(a, " \n     Ordered");
            try pad(a, o, 4 + yw + 4 + 9 - 5);
            try o.appendSlice(a, "Total\n       Value    ");
            try right(a, o, rname, yw);
            try o.appendSlice(a, "    Frequency\n\n");
            for ([_][]const u8{ lv0, lv1 }, 0..) |lv, k| {
                try right(a, o, try std.fmt.allocPrint(a, "{d}", .{k + 1}), 12);
                try pad(a, o, 4);
                try right(a, o, lv, yw);
                try right(a, o, try std.fmt.allocPrint(a, "{d}", .{ft.resp_freq[k]}), 13);
                try o.append(a, '\n');
            }
            try o.print(a, "\nYou are modeling the probability that {s}='{s}'.\n", .{ rname, lv0 });
        }
        if (!s.noitprint) {
            try o.appendSlice(a, "\n\n");
            try title(a, o, "Iteration History", 69);
            try o.appendSlice(a, " \n                               Objective                         Max\nIteration    Evaluations        Function          Change    Gradient\n\n");
            for (ft.res.history, 0..) |h, k| {
                try right(a, o, try std.fmt.allocPrint(a, "{d}", .{k}), 9);
                try right(a, o, if (k == 0) "4" else "2", 15);
                try right(a, o, std.mem.trim(u8, try format.bestNumW(a, h.f, 12), " "), 16);
                if (h.change) |c| {
                    try right(a, o, try fixed(a, c, 8), 16);
                } else try o.appendSlice(a, "       .        ");
                try right(a, o, try best8(a, h.max_grad), 12);
                try o.append(a, '\n');
            }
        }
        try o.appendSlice(a, switch (ft.res.stop) {
            .gconv => "\n         Convergence criterion (GCONV=1E-8) satisfied.          \n",
            .absgconv => "\n        Convergence criterion (ABSGCONV=1E-7) satisfied.        \n",
        });
        try o.appendSlice(a, "\n\n");
        try countTable(a, o, "Dimensions", &.{
            .{ .label = "Columns in X", .value = try std.fmt.allocPrint(a, "{d}", .{ft.columns}) },
            .{ .label = "Number of Effects", .value = try std.fmt.allocPrint(a, "{d}", .{s.effects.len + 1}) },
            .{ .label = "Max Effect Columns", .value = try std.fmt.allocPrint(a, "{d}", .{ft.max_cols}) },
            .{ .label = "Rank of Cross-product Matrix", .value = try std.fmt.allocPrint(a, "{d}", .{ft.rank}) },
            .{ .label = "Parameters in Optimization", .value = try std.fmt.allocPrint(a, "{d}", .{ft.rank}) },
        }, 40);
        const m2ll = -2 * ft.res.ll;
        const k: f64 = @floatFromInt(ft.rank);
        const nn = ft.g.freq_used;
        try o.appendSlice(a, "\n\n");
        try countTable(a, o, "Fit Statistics", &.{
            .{ .label = "-2 Log Likelihood", .value = try fitStat(cx, m2ll) },
            .{ .label = "AIC (smaller is better)", .value = try fitStat(cx, m2ll + 2 * k) },
            .{ .label = "AICC (smaller is better)", .value = if (nn - k - 1 > 0) try fitStat(cx, m2ll + 2 * k * nn / (nn - k - 1)) else return gap(cx, 0, "AICC with no more observations than parameters plus one is not verified", .{}) },
            .{ .label = "BIC (smaller is better)", .value = try fitStat(cx, m2ll + k * @log(nn)) },
        }, 42);
        {
            const lr = 2 * (ft.res.ll - ft.null_ll);
            const df = ft.rank - 1;
            try o.appendSlice(a, "\n\n");
            try title(a, o, "Testing Global Null Hypothesis: BETA=0", 55);
            try o.appendSlice(a, " \nTest                 Chi-Square       DF     Pr > ChiSq\n\nLikelihood Ratio");
            try right(a, o, try fixed(a, @max(lr, 0), 4), 15);
            try right(a, o, try std.fmt.allocPrint(a, "{d}", .{df}), 9);
            try right(a, o, try pvalue(a, lf.chiTail(@max(lr, 0), df)), 15);
            try o.append(a, '\n');
        }
        {
            var any_aliased = false;
            for (ft.aliased) |al| {
                if (al) any_aliased = true;
            }
            var nw: usize = 9;
            for (ft.names) |nm| nw = @max(nw, nm.len);
            const ew: usize = if (any_aliased) 9 else 8;
            const width = nw + 4 + ew + 4 + 8 + 4 + 5 + 4 + 7 + 4 + 8;
            try o.appendSlice(a, "\n\n");
            try title(a, o, "Parameter Estimates", width);
            try o.appendSlice(a, " \n");
            try pad(a, o, nw + 4 + ew + 4);
            try o.appendSlice(a, "Standard\n");
            try left(a, o, "Parameter", nw);
            try right(a, o, "Estimate", ew + 4);
            try o.appendSlice(a, "       Error       DF    t Value    Pr > |t|\n\n");
            for (ft.names, ft.beta, ft.se, ft.aliased) |nm, b, se, al| {
                try left(a, o, nm, nw);
                if (al) {
                    try right(a, o, "0", ew + 4);
                    try o.appendSlice(a, "           .        .        .         .    \n");
                    continue;
                }
                const tv = b / se;
                try right(a, o, try estimate(cx, b), ew + 4);
                try right(a, o, try estimate(cx, se), 12);
                try o.appendSlice(a, "    Infty");
                try right(a, o, try fixed(a, tv, 2), 11);
                try right(a, o, try pvalue(a, lf.chiTail(tv * tv, 1)), 12);
                try o.append(a, '\n');
            }
        }
        try cx.diags.note(0, "You are modeling the probability that {s}='{s}'.", .{ rname, lv0 });
        try cx.diags.note(0, "Convergence criterion ({s}) satisfied.", .{if (ft.res.stop == .gconv) "GCONV=1E-8" else "ABSGCONV=1E-7"});
    }
    if (cx.listing_titles) |titles| try titles.emitFootnotes(a, o);
    if (!s.noprint) try out.appendSlice(a, body.items);
}

/// A new listing page: SAS 15.4 reference runs separate pages by one blank
/// line, which the procedure-title line supplies when no TITLE is active.
fn pageStart(cx: proc.ProcCtx, out: *Out) !void {
    const titles = cx.listing_titles orelse return;
    for (titles.titles) |ln| if (ln != null) {
        try out.append(cx.arena, '\n');
        break;
    };
    try titles.emitTitles(cx.arena, out);
}

test {
    _ = @import("hplogistic_tests.zig");
}
