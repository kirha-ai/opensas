//! PROC LIFEREG declarations, variable roles and observation selection
//! (STAT-LIFEREG-001), SAS/STAT 15.4 physical pp.5535-5538, 5548, 5554-5555
//! and 5566. This ticket owns the parameter objects (`Spec`) and the
//! per-BY-group selection result (`Selected`) that the estimation ticket
//! (STAT-LIFEREG-002) consumes. Maximum-likelihood fitting and every listing
//! table are not implemented: a valid step ends in a D-009 gap (rc 2) raised
//! before any listing text, so a partial page can never be taken for a fit.
//!
//! Right-censored responses are classified through the shared survival-data
//! contract (`survival_data.zig`); the interval form is refused through its
//! `check`, which keeps the rc 2 class the contract assigns to LIFEREG.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const class_levels = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const survival = @import("survival_data.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Distribution = enum { weibull, exponential, gamma, llogistic, logistic, lognormal, normal };

pub const Response = union(enum) {
    /// `response` or `response*censor(list)`.
    right: struct { time: usize, censor: ?usize = null, censor_values: []const f64 = &.{} },
    /// `(lower, upper)`.
    interval: struct { lower: usize, upper: usize },
    /// `events/trials`.
    events_trials: struct { events: usize, trials: usize },
};

pub const Spec = struct {
    input: proc.ProcInput,
    response: Response,
    /// Optional `label:` of the MODEL statement that is used.
    model_label: ?[]const u8 = null,
    /// Main-effect explanatory variables, in MODEL order.
    effects: []const usize = &.{},
    /// CLASS variables, in declaration order.
    classes: []const usize = &.{},
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    noprint: bool = false,
    order: class_levels.Order = .formatted,
    namelen: usize = 20,
    distribution: Distribution = .weibull,
    nolog: bool = false,
    noint: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC LIFEREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC LIFEREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC LIFEREG statement options (Table 76.1) owned by later
/// LIFEREG tickets, and the superseded line-printer graphics options.
const later_options = [_][]const u8{ "covout", "inest", "outest", "plots", "plot", "xdata", "gout" };
/// Documented statements owned by later LIFEREG tickets.
const later_statements = [_][]const u8{ "bayes", "estimate", "inset", "lsmeans", "lsmestimate", "output", "probplot", "slice", "store", "test" };
/// Documented MODEL options owned by later LIFEREG tickets.
const later_model_options = [_][]const u8{ "alpha", "converge", "convg", "corrb", "covb", "initial", "intercept", "itprint", "maxiter", "noscale", "noshape1", "offset", "scale", "shape1", "singular" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFEREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

fn distribution(name: []const u8) ?Distribution {
    if (eq(name, "weibull")) return .weibull;
    if (eq(name, "exponential")) return .exponential;
    if (eq(name, "gamma")) return .gamma;
    if (eq(name, "llogistic")) return .llogistic;
    if (eq(name, "logistic")) return .logistic;
    if (eq(name, "lognormal") or eq(name, "lnormal")) return .lognormal;
    if (eq(name, "normal")) return .normal;
    return null;
}

/// One MODEL statement, tokens `t[i..end]` with `t[i]` the MODEL keyword.
/// The settings of an earlier MODEL statement are discarded by the caller.
fn parseModel(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, s: *Spec) diag.Error!void {
    var i = start + 1;
    if (at(t, i, .lparen)) {
        const lower = try numericColumn(cx, ds, t, i + 1, "lower-bound");
        var j = i + 2;
        if (at(t, j, .comma)) j += 1;
        const upper = try numericColumn(cx, ds, t, j, "upper-bound");
        if (!at(t, j + 1, .rparen)) return invalid(cx, t, j + 1);
        s.response = .{ .interval = .{ .lower = lower, .upper = upper } };
        i = j + 2;
    } else {
        const first = try numericColumn(cx, ds, t, i, "response");
        i += 1;
        if (at(t, i, .slash)) {
            const trials = try numericColumn(cx, ds, t, i + 1, "trials");
            s.response = .{ .events_trials = .{ .events = first, .trials = trials } };
            i += 2;
        } else if (at(t, i, .star)) {
            const censor = try numericColumn(cx, ds, t, i + 1, "censoring");
            if (!at(t, i + 2, .lparen)) return invalid(cx, t, i + 2);
            var values: std.ArrayList(f64) = .empty;
            var j = i + 3;
            while (j < end and !at(t, j, .rparen)) {
                if (at(t, j, .comma)) {
                    j += 1;
                    continue;
                }
                if (kw(t, j, "to") or kw(t, j, "by")) return gap(cx, t[j].line, "censoring value ranges are not implemented", .{});
                var sign: f64 = 1;
                if (at(t, j, .minus)) {
                    sign = -1;
                    j += 1;
                }
                if (!at(t, j, .number)) return invalid(cx, t, j);
                try values.append(cx.arena, sign * (std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j)));
                j += 1;
            }
            if (!at(t, j, .rparen) or values.items.len == 0) return invalid(cx, t, j);
            s.response = .{ .right = .{ .time = first, .censor = censor, .censor_values = values.items } };
            i = j + 1;
        } else s.response = .{ .right = .{ .time = first } };
    }
    if (!at(t, i, .eq)) return invalid(cx, t, i);
    i += 1;
    var effects: std.ArrayList(usize) = .empty;
    while (i < end and !at(t, i, .slash)) : (i += 1) {
        if (at(t, i, .star) or at(t, i, .lparen) or at(t, i, .pipe)) return gap(cx, t[i].line, "interaction, nested and bar effects are not implemented", .{});
        const c = try column(cx, ds, t, i);
        if (std.mem.indexOfScalar(usize, effects.items, c) != null) return gap(cx, t[i].line, "repeated MODEL effect policy is not verified", .{});
        try effects.append(cx.arena, c);
    }
    s.effects = effects.items;
    if (at(t, i, .slash)) i += 1;
    while (i < end) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (oneOf(word, &.{ "dist", "distribution", "d" })) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return invalid(cx, t, i + 1);
            s.distribution = distribution(t[i + 2].text) orelse return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "nolog")) {
            s.nolog = true;
            i += 1;
        } else if (eq(word, "noint")) {
            s.noint = true;
            i += 1;
        } else if (oneOf(word, &later_model_options)) {
            return gap(cx, t[i].line, "MODEL option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .response = undefined };
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
        } else if (eq(word, "order") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const o = t[i + 2].text;
            s.order = if (eq(o, "data")) .data else if (eq(o, "formatted")) .formatted else if (eq(o, "freq")) .freq else if (eq(o, "internal")) .internal else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "namelen") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const n = std.fmt.parseInt(usize, t[i + 2].text, 10) catch return invalid(cx, t, i + 2);
            // "n is a value between 20 and 200" (p.5536).
            if (n < 20 or n > 200) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFEREG: NAMELEN={d} is outside the documented range 20 to 200", .{n});
            s.namelen = n;
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC LIFEREG: input dataset not found", .{});
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
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        var head = i;
        var label: ?[]const u8 = null;
        if (at(t, i, .name) and at(t, i + 1, .colon) and kw(t, i + 2, "model")) {
            label = t[i].text;
            head = i + 2;
        }
        if (kw(t, head, "model")) {
            // "If multiple MODEL statements are present, only the last is
            // used" (p.5535): each one replaces every MODEL-owned setting.
            model_seen = true;
            s.effects = &.{};
            s.distribution = .weibull;
            s.nolog = false;
            s.noint = false;
            s.model_label = label;
            try parseModel(cx, ds, t, head, end, &s);
        } else if (kw(t, i, "class")) {
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                if (at(t, j, .slash)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
            }
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted CLASS levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC LIFEREG: MODEL statement required", .{});
    s.classes = classes.items;
    // A character explanatory variable is only usable as a CLASS variable.
    for (s.effects) |c| if (ds.columns.items[c].type != .num and std.mem.indexOfScalar(usize, s.classes, c) == null)
        return cx.diags.fail(error.ParseError, 0, "PROC LIFEREG: character variable {s} in the MODEL statement must be a CLASS variable", .{ds.columns.items[c].name});
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

pub const Exclusion = enum { missing_response, missing_censor, missing_explanatory, nonpositive_weight };
pub const Status = union(enum) {
    event,
    right_censored,
    excluded: Exclusion,
};
pub const ClassVariable = struct {
    column: usize,
    /// Level labels in ORDER= order, over the used observations.
    labels: []const []const u8,
};
pub const Selected = struct {
    /// One status per input row of the BY group, in input order.
    status: []const Status,
    read: usize,
    used: usize = 0,
    noncensored: usize = 0,
    right_censored: usize = 0,
    /// One entry per CLASS variable that appears in the MODEL statement.
    classes: []const ClassVariable = &.{},

    pub fn excluded(self: Selected, reason: Exclusion) usize {
        var n: usize = 0;
        for (self.status) |st| if (st == .excluded and st.excluded == reason) {
            n += 1;
        };
        return n;
    }
};

/// Observation selection for a right-censored response, physical pp.5554 and
/// 5566: a missing response or censoring value drops the observation, as does
/// a missing explanatory variable of the model (CLASS variables that the
/// MODEL statement does not name are not "needed in that model" and do not
/// select); a missing or nonpositive WEIGHT drops it from the fit. Weights are
/// not truncated. The first failing rule, in that order, is the recorded
/// reason. Counts are observation counts, never weight totals.
/// ponytail: a nonpositive response under the default log transform is kept;
/// its rule belongs to the estimation ticket, which must settle it before a
/// fit can be displayed.
pub fn select(a: A, ds: *const Dataset, s: Spec, rows: []const []const Value) diag.Error!Selected {
    const r = s.response.right;
    const c = try survival.classifyRight(a, .{ .response = .{ .right = .{ .time = r.time, .censor = r.censor, .censor_values = r.censor_values } } }, rows);
    const status = try a.alloc(Status, rows.len);
    const mask = try a.alloc(bool, rows.len);
    var sel: Selected = .{ .status = status, .read = rows.len };
    for (rows, c.status, status, mask) |row, shared, *st, *keep| {
        st.* = switch (shared) {
            .event => .event,
            .right_censored => .right_censored,
            .excluded => |why| .{ .excluded = if (why == .missing_censor) .missing_censor else .missing_response },
            .left_censored, .interval_censored => unreachable,
        };
        if (st.* != .excluded) {
            for (s.effects) |e| if (selection.missing(row[e])) {
                st.* = .{ .excluded = .missing_explanatory };
                break;
            };
        }
        if (st.* != .excluded) if (s.weight) |w| {
            if (selection.missing(row[w]) or !(row[w].num > 0)) st.* = .{ .excluded = .nonpositive_weight };
        };
        keep.* = st.* != .excluded;
        if (keep.*) sel.used += 1;
        if (st.* == .event) sel.noncensored += 1;
        if (st.* == .right_censored) sel.right_censored += 1;
    }
    var classes: std.ArrayList(ClassVariable) = .empty;
    for (s.classes) |col| {
        if (std.mem.indexOfScalar(usize, s.effects, col) == null) continue;
        const levels = try class_levels.build(a, ds, rows, col, .{ .order = s.order, .include_rows = mask });
        const labels = try a.alloc([]const u8, levels.levels.len);
        for (levels.levels, labels) |level, *label| label.* = level.label;
        try classes.append(a, .{ .column = col, .labels = labels });
    }
    sel.classes = classes.items;
    return sel;
}

/// "Number of Parameters" of the Model Information table for the
/// location-scale distributions with one free scale parameter: the intercept,
/// one per continuous effect, levels-1 per CLASS effect ("indicator variables
/// ... for every level of the variable except the last", p.5566) and the
/// scale. Null where this ticket has no verified count.
pub fn parameterCount(s: Spec, sel: Selected) ?usize {
    if (s.noint or s.distribution == .exponential or s.distribution == .gamma) return null;
    var n: usize = 2;
    for (s.effects) |e| {
        var levels: ?usize = null;
        for (sel.classes) |cv| if (cv.column == e) {
            levels = cv.labels.len;
        };
        n += if (levels) |k| (if (k == 0) return null else k - 1) else 1;
    }
    return n;
}

/// Validation and per-BY-group selection without any output.
pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Selected {
    switch (s.response) {
        .right => {},
        .interval => |v| try survival.check(cx.diags, 0, .lifereg, .{ .interval = .{ .lower = v.lower, .upper = v.upper } }),
        .events_trials => return gap(cx, 0, "events/trials response is not implemented", .{}),
    }
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try cx.arena.alloc(Selected, slices.len);
    for (slices, groups) |slice, *group| group.* = try select(cx.arena, s.input.ds, s, slice.rows);
    return groups;
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    _ = out;
    const s = try parse(cx, t);
    _ = try plan(cx, s);
    // ponytail: NOPRINT is a gap too. With no listing and no output data set
    // nothing would show that the model was never fitted.
    return gap(cx, 0, "maximum-likelihood estimation and the listing are not implemented (STAT-LIFEREG-002)", .{});
}

test {
    _ = @import("lifereg_tests.zig");
}
