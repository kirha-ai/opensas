//! PROC LIFETEST declarations, variable roles, observation selection and the
//! default stratified product-limit listing, SAS/STAT 15.4 physical
//! pp.5650-5668 and 5670-5673. Everything whose displayed result has not been
//! proven against an independent derivation is a D-009 gap (rc 2) raised
//! before any listing text is produced, so a partial page can never be taken
//! for a full analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fns = @import("../functions.zig");
const by = @import("by_groups.zig");
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    time: usize,
    censor: ?usize = null,
    censor_values: []const f64 = &.{},
    strata: []const usize = &.{},
    ids: []const usize = &.{},
    frequency: ?usize = null,
    notruncate: bool = false,
    weight: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    missing: bool = false,
    noprint: bool = false,
    notable: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC LIFETEST: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC LIFETEST: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}
/// Documented PROC LIFETEST statement options (Table 77.1 plus the superseded
/// plot options) owned by later LIFETEST tickets.
const later_options = [_][]const u8{ "outcif", "outsurv", "outs", "outtest", "error", "intervals", "nelson", "aalen", "ninterval", "width", "rmst", "rmtl", "alpha", "bandmaxtime", "bandmax", "bandmintime", "bandmin", "confband", "maxtime", "plots", "plot", "atrisk", "noleft", "reduceout", "timelist", "alphaqt", "cifvar", "singular", "stderr", "timelim", "censoredsymbol", "eventsymbol", "formchar", "lineprinter", "nocensplot", "annotate", "gout", "description", "language" };
const later_statements = [_][]const u8{ "test", "survival", "rmst", "rmtl" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFETEST: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .time = undefined };
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
        } else if (eq(word, "missing")) {
            s.missing = true;
            i += 1;
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "notable")) {
            s.notable = true;
            i += 1;
        } else if (eq(word, "method") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const m = t[i + 2].text;
            if (oneOf(m, &.{ "breslow", "b", "fh", "lt", "life", "lifetable", "act", "actuarial" })) return gap(cx, t[i].line, "METHOD={s} is not implemented", .{m});
            if (!oneOf(m, &.{ "km", "pl" })) return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "conftype") and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const m = t[i + 2].text;
            if (oneOf(m, &.{ "linear", "log", "asinsqrt", "logit" })) return gap(cx, t[i].line, "CONFTYPE={s} is not implemented", .{m});
            if (!eq(m, "loglog")) return invalid(cx, t, i + 2);
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC LIFETEST: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var time_seen = false;
    var strata_seen = false;
    var ids: std.ArrayList(usize) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "time")) {
            if (time_seen) return gap(cx, t[i].line, "duplicate TIME statement policy is not verified", .{});
            time_seen = true;
            s.time = try numericColumn(cx, ds, t, i + 1, "TIME");
            if (end != i + 2) {
                if (!at(t, i + 2, .star)) return invalid(cx, t, i + 2);
                s.censor = try numericColumn(cx, ds, t, i + 3, "censoring");
                if (!at(t, i + 4, .lparen) or !at(t, end - 1, .rparen)) return invalid(cx, t, i + 4);
                var values: std.ArrayList(f64) = .empty;
                var j = i + 5;
                while (j < end - 1) {
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
                if (values.items.len == 0) return invalid(cx, t, end - 1);
                s.censor_values = values.items;
            }
        } else if (kw(t, i, "strata")) {
            if (strata_seen) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            strata_seen = true;
            var cols: std.ArrayList(usize) = .empty;
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .slash)) return gap(cx, t[j].line, "STRATA statement options are not implemented", .{});
                if (at(t, j, .lparen)) return gap(cx, t[j].line, "STRATA interval lists are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, cols.items, c) != null) return gap(cx, t[j].line, "repeated STRATA variable policy is not verified", .{});
                try cols.append(cx.arena, c);
            }
            if (cols.items.len == 0) return invalid(cx, t, end);
            s.strata = cols.items;
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
            if (end != i + 2) {
                if (end != i + 4 or !at(t, i + 2, .slash) or !(kw(t, i + 3, "notruncate") or kw(t, i + 3, "notrunc"))) return invalid(cx, t, i + 2);
                s.notruncate = true;
            }
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "id")) {
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| try ids.append(cx.arena, try column(cx, ds, t, j));
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted strata and ID values) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!time_seen) return cx.diags.fail(error.ParseError, 0, "PROC LIFETEST: TIME statement required", .{});
    s.ids = ids.items;
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

pub const Obs = struct { time: f64, event: bool, stratum: usize, freq: f64 = 1, weight: f64 = 1 };
pub const Selected = struct {
    obs: []Obs,
    /// One representative row per stratum level, ascending (missing first).
    levels: []const []const Value,
    read: usize,
};

fn valueLess(x: Value, y: Value) bool {
    return switch (x) {
        .num => |xv| blk: {
            const yv = y.num;
            if (std.math.isNan(xv)) break :blk !std.math.isNan(yv);
            if (std.math.isNan(yv)) break :blk false;
            break :blk xv < yv;
        },
        .str => |xs| std.mem.lessThan(u8, std.mem.trimEnd(u8, xs, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}
fn levelOrder(cols: []const usize, x: []const Value, y: []const Value) std.math.Order {
    for (cols) |c| {
        if (valueLess(x[c], y[c])) return .lt;
        if (valueLess(y[c], x[c])) return .gt;
    }
    return .eq;
}
fn levelLess(cols: []const usize, x: []const Value, y: []const Value) bool {
    return levelOrder(cols, x, y) == .lt;
}

/// Observation selection, physical pp.5663, 5670-5671: a missing time or
/// censoring value drops the observation; a missing stratum value drops it
/// unless MISSING; FREQ is truncated unless NOTRUNCATE and a missing or
/// nonpositive (after truncation: below one) frequency drops it; a missing or
/// nonpositive WEIGHT drops it. ID values never select. Strata levels are
/// ordered ascending by unformatted value.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    var kept: std.ArrayList([]const Value) = .empty;
    var obs: std.ArrayList(Obs) = .empty;
    for (rows) |row| {
        if (selection.missing(row[s.time])) continue;
        var o: Obs = .{ .time = row[s.time].num, .event = true, .stratum = 0 };
        if (s.censor) |c| {
            if (selection.missing(row[c])) continue;
            o.event = std.mem.indexOfScalar(f64, s.censor_values, row[c].num) == null;
        }
        if (!s.missing) {
            var skip = false;
            for (s.strata) |c| skip = skip or selection.missing(row[c]);
            if (skip) continue;
        }
        if (s.frequency) |c| {
            if (selection.missing(row[c])) continue;
            o.freq = if (s.notruncate) row[c].num else @trunc(row[c].num);
            if (!(o.freq > 0)) continue;
        }
        if (s.weight) |c| {
            if (selection.missing(row[c]) or !(row[c].num > 0)) continue;
            o.weight = row[c].num;
        }
        try kept.append(a, row);
        try obs.append(a, o);
    }
    var levels: std.ArrayList([]const Value) = .empty;
    if (s.strata.len > 0) {
        const sorted = try a.dupe([]const Value, kept.items);
        std.mem.sort([]const Value, sorted, s.strata, levelLess);
        for (sorted) |row| if (levels.items.len == 0 or levelOrder(s.strata, levels.items[levels.items.len - 1], row) != .eq) try levels.append(a, row);
        for (kept.items, obs.items) |row, *o| {
            for (levels.items, 0..) |level, k| if (levelOrder(s.strata, level, row) == .eq) {
                o.stratum = k;
            };
        }
    }
    return .{ .obs = obs.items, .levels = levels.items, .read = rows.len };
}

pub const Row = struct { time: f64, censored: bool, survival: ?f64 = null, se: ?f64 = null, failed: usize, left: usize };
pub const Quartile = struct { estimate: ?f64 = null, lower: ?f64 = null, upper: ?f64 = null };
pub const Stratum = struct {
    rows: []Row,
    total: usize,
    failed: usize,
    event_times: []f64,
    at_risk: []f64,
    deaths: []f64,
    survival: []f64,
    se: []?f64,
    quartiles: [3]Quartile = @splat(.{}),
    mean: f64 = 0,
    mean_se: ?f64 = null,
    last_censored: bool = false,
    tied_events: bool = false,
    /// A displayed quantity whose rule the specification does not settle.
    unverified: ?[]const u8 = null,
};
const z975: f64 = 1.959963984540054;
/// ponytail: a product-limit estimate is a product of at most D correctly
/// rounded ratios, so its relative error is below D*2^-52; 1e-12 separates
/// "exactly equal to 1-p" from the next attainable value for D < 4000.
const equal_tolerance: f64 = 1e-12;

fn obsLess(_: void, x: Obs, y: Obs) bool {
    if (x.time != y.time) return x.time < y.time;
    return x.event and !y.event;
}

/// Kaplan-Meier estimate with Greenwood standard error, quartiles with
/// log-log limits and the restricted mean, physical pp.5671-5673.
pub fn productLimit(a: A, input: []const Obs) !Stratum {
    const obs = try a.dupe(Obs, input);
    std.mem.sort(Obs, obs, {}, obsLess);
    var rows: std.ArrayList(Row) = .empty;
    var times: std.ArrayList(f64) = .empty;
    var risk: std.ArrayList(f64) = .empty;
    var deaths: std.ArrayList(f64) = .empty;
    var surv: std.ArrayList(f64) = .empty;
    var ses: std.ArrayList(?f64) = .empty;
    var st: Stratum = .{ .rows = &.{}, .total = obs.len, .failed = 0, .event_times = &.{}, .at_risk = &.{}, .deaths = &.{}, .survival = &.{}, .se = &.{} };
    var s: f64 = 1;
    var greenwood: f64 = 0;
    var left = obs.len;
    var i: usize = 0;
    while (i < obs.len) {
        var j = i;
        var d: usize = 0;
        while (j < obs.len and obs[j].time == obs[i].time) : (j += 1) {
            if (obs[j].event) d += 1;
        }
        if (d > 0) {
            const n: f64 = @floatFromInt(left);
            const df: f64 = @floatFromInt(d);
            s *= (n - df) / n;
            var se: ?f64 = null;
            if (d < left) {
                greenwood += df / (n * (n - df));
                se = s * @sqrt(greenwood);
            } else s = 0;
            if (d > 1) st.tied_events = true;
            for (0..d) |k| {
                left -= 1;
                st.failed += 1;
                try rows.append(a, .{ .time = obs[i].time, .censored = false, .survival = if (k + 1 == d) s else null, .se = if (k + 1 == d) se else null, .failed = st.failed, .left = left });
            }
            try times.append(a, obs[i].time);
            try risk.append(a, n);
            try deaths.append(a, df);
            try surv.append(a, s);
            try ses.append(a, se);
        }
        for (i + d..j) |_| {
            left -= 1;
            try rows.append(a, .{ .time = obs[i].time, .censored = true, .failed = st.failed, .left = left });
        }
        i = j;
    }
    st.rows = rows.items;
    st.event_times = times.items;
    st.at_risk = risk.items;
    st.deaths = deaths.items;
    st.survival = surv.items;
    st.se = ses.items;
    st.last_censored = obs.len > 0 and !obs[obs.len - 1].event;
    const count = times.items.len;
    if (count == 0) {
        st.unverified = "a stratum without events";
        return st;
    }
    for ([_]f64{ 0.75, 0.5, 0.25 }, 0..) |p, q| {
        const target = 1 - p;
        for (surv.items, 0..) |value, k| {
            if (@abs(value - target) <= equal_tolerance) {
                if (k + 1 == count) st.unverified = "a quartile at a survival plateau that ends the event times" else st.quartiles[q].estimate = (times.items[k] + times.items[k + 1]) / 2;
                break;
            }
            if (value < target) {
                st.quartiles[q].estimate = times.items[k];
                break;
            }
        }
        // Brookmeyer-Crowley set under g(x) = log(-log(x)), g'(x) = 1/(x log x).
        var first: ?usize = null;
        var last: ?usize = null;
        for (surv.items, ses.items, 0..) |value, se, k| {
            // At S = 0 the statistic is undefined. The SAS listing behind the
            // default stratified fixture leaves the upper limit missing when
            // the event time just before it is in the set, and the guide's
            // Figure 77.4 median (upper 253 although S reaches 0 at 323)
            // shows the point does not rejoin a set that has already ended:
            // it only extends a set that reaches the preceding event time.
            const inside = if (se) |e| (e > 0 and @abs((@log(-@log(value)) - @log(-@log(target))) / (e / (value * @log(value)))) <= z975) else (k > 0 and last != null and last.? == k - 1);
            if (se == null and first == null) st.unverified = "quartile limits when the first eligible event time has survival 0";
            if (inside) {
                if (first == null) first = k;
                last = k;
            }
        }
        if (first) |k| {
            st.quartiles[q].lower = times.items[k];
            if (last.? + 1 < count) st.quartiles[q].upper = times.items[last.? + 1];
        } else if (st.unverified == null) st.unverified = "quartile limits with an empty confidence set";
    }
    // Mean restricted to the largest event time; variance with m/(m-1).
    var previous_time: f64 = 0;
    var previous_s: f64 = 1;
    for (times.items, surv.items) |time, value| {
        st.mean += previous_s * (time - previous_time);
        previous_time = time;
        previous_s = value;
    }
    var variance: f64 = 0;
    var m: f64 = 0;
    for (deaths.items) |d| m += d;
    for (0..count) |k| {
        var area: f64 = 0;
        for (k + 1..count) |l| area += surv.items[l - 1] * (times.items[l] - times.items[l - 1]);
        const n = risk.items[k];
        const d = deaths.items[k];
        if (n > d) variance += area * area * d / (n * (n - d));
    }
    if (m > 1) st.mean_se = @sqrt(variance * m / (m - 1)) else if (st.unverified == null) st.unverified = "the mean standard error with a single event";
    return st;
}

pub const Homogeneity = struct {
    logrank: []f64,
    wilcoxon: []f64,
    logrank_cov: []f64,
    wilcoxon_cov: []f64,
    /// -2 log likelihood ratio under the exponential model.
    lr: f64,
};

/// K-sample log-rank and Wilcoxon (weight = pooled number at risk) statistics
/// with their hypergeometric covariances, and the exponential likelihood
/// ratio statistic.
pub fn homogeneity(a: A, obs: []const Obs, k: usize) !Homogeneity {
    const h: Homogeneity = .{ .logrank = try a.alloc(f64, k), .wilcoxon = try a.alloc(f64, k), .logrank_cov = try a.alloc(f64, k * k), .wilcoxon_cov = try a.alloc(f64, k * k), .lr = 0 };
    @memset(h.logrank, 0);
    @memset(h.wilcoxon, 0);
    @memset(h.logrank_cov, 0);
    @memset(h.wilcoxon_cov, 0);
    const n_k = try a.alloc(f64, k);
    const d_k = try a.alloc(f64, k);
    const events = try a.alloc(f64, k);
    const exposure = try a.alloc(f64, k);
    @memset(events, 0);
    @memset(exposure, 0);
    for (obs) |o| {
        exposure[o.stratum] += o.time;
        if (o.event) events[o.stratum] += 1;
    }
    for (obs, 0..) |pivot, index| {
        if (!pivot.event) continue;
        var earlier = false;
        for (obs[0..index]) |o| earlier = earlier or (o.event and o.time == pivot.time);
        if (earlier) continue;
        @memset(n_k, 0);
        @memset(d_k, 0);
        for (obs) |o| {
            if (o.time >= pivot.time) n_k[o.stratum] += 1;
            if (o.event and o.time == pivot.time) d_k[o.stratum] += 1;
        }
        var n: f64 = 0;
        var d: f64 = 0;
        for (n_k, d_k) |x, y| {
            n += x;
            d += y;
        }
        for (0..k) |g| {
            h.logrank[g] += d_k[g] - d * n_k[g] / n;
            h.wilcoxon[g] += n * (d_k[g] - d * n_k[g] / n);
        }
        if (n > 1) for (0..k) |g| for (0..k) |l| {
            const v = d * (n - d) / (n - 1) * (n_k[g] / n) * ((if (g == l) @as(f64, 1) else 0) - n_k[l] / n);
            h.logrank_cov[g * k + l] += v;
            h.wilcoxon_cov[g * k + l] += n * n * v;
        };
    }
    var total_events: f64 = 0;
    var total_exposure: f64 = 0;
    var lr: f64 = 0;
    for (events, exposure) |d, time| {
        total_events += d;
        total_exposure += time;
        if (d > 0) lr += d * @log(d / time);
    }
    if (total_events > 0) lr -= total_events * @log(total_events / total_exposure);
    var result = h;
    result.lr = 2 * lr;
    return result;
}

pub fn chiProbability(x: f64, df: f64) f64 {
    return 1 - fns.gammaP(df / 2, x / 2);
}

pub const Equality = struct { chi: f64, df: usize };
/// ponytail: a pivot below 1e-9 of its original diagonal is treated as a
/// linear dependency. The K x K rank covariance has zero row sums, so its
/// dependent pivot is pure rounding (about 1e-16 relative); a matrix that is
/// merely ill conditioned to 1e-9 would need a scaled decomposition.
const singular_tolerance: f64 = 1e-9;

/// Homogeneity statistic v' V^- v, physical p.5682: V^- is the generalized
/// inverse obtained by eliminating the diagonal pivots in order and skipping
/// linearly dependent ones; the degrees of freedom are the rank of V.
pub fn quadraticForm(a: A, v: []const f64, cov: []const f64, k: usize) !Equality {
    const m = try a.dupe(f64, cov);
    const y = try a.dupe(f64, v);
    var result: Equality = .{ .chi = 0, .df = 0 };
    for (0..k) |p| {
        const pivot = m[p * k + p];
        if (!(pivot > singular_tolerance * cov[p * k + p])) continue;
        result.chi += y[p] * y[p] / pivot;
        result.df += 1;
        for (p + 1..k) |i| {
            const f = m[i * k + p] / pivot;
            y[i] -= f * y[p];
            for (p..k) |j| m[i * k + j] -= f * m[p * k + j];
        }
    }
    return result;
}

/// Per-BY-group selections; raises the documented data errors.
pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Selected {
    const slices = try by.checkedSlices(cx.arena, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try cx.arena.alloc(Selected, slices.len);
    for (slices, groups) |slice, *group| group.* = try select(cx.arena, s, slice.rows);
    return groups;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
/// Survival-table probabilities: exact 0 prints as 0, otherwise 4 decimals.
fn probability(a: A, out: *Out, value: ?f64) !void {
    const x = value orelse return padRight(a, out, ".", 12);
    try padRight(a, out, if (x == 0) "0" else try fixed(a, x, 4), 12);
}
/// Time-scale values print with five decimals; a missing value puts its
/// period under the decimal point.
fn timeCell(a: A, out: *Out, value: ?f64) !void {
    if (value) |x| try padRight(a, out, try fixed(a, x, 5), 12) else try out.appendSlice(a, "      .     ");
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, sel: Selected) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    // Execution boundary: only the listing shape proven against the SAS
    // reference and independent hand calculation is produced.
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group listing layout is not verified", .{});
    if (s.frequency != null) return gap(cx, 0, "FREQ-expanded estimates and listing are not implemented", .{});
    if (s.weight != null) return gap(cx, 0, "weighted Kaplan-Meier estimation is not implemented", .{});
    if (s.ids.len > 0) return gap(cx, 0, "ID columns in the survival listing are not implemented", .{});
    if (sel.obs.len == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});
    if (s.strata.len != 1) return gap(cx, 0, "listing without STRATA or with several STRATA variables is not implemented", .{});
    const strata_info = ds.columns.items[s.strata[0]];
    if (strata_info.type != .char or strata_info.format != null) return gap(cx, 0, "numeric or formatted STRATA levels are not implemented", .{});
    if (sel.levels.len != 2) return gap(cx, 0, "homogeneity results for {d} strata are not implemented", .{sel.levels.len});
    const time_name = ds.columns.items[s.time].name;
    const strata_name = strata_info.name;
    // ponytail: column widths are verified for names and levels that fit the
    // reference's 8-character columns; wider text needs the template widths.
    if (time_name.len > 8 or strata_name.len > 8) return gap(cx, 0, "listing columns for variable names longer than 8 characters are not verified", .{});
    const labels = try a.alloc([]const u8, sel.levels.len);
    for (sel.levels, labels) |row, *label| {
        label.* = std.mem.trimEnd(u8, row[s.strata[0]].str, " ");
        if (label.len == 0) return gap(cx, 0, "display of a missing STRATA level is not verified", .{});
        if (label.len > 8) return gap(cx, 0, "listing columns for STRATA levels longer than 8 characters are not verified", .{});
    }
    for (sel.obs) |o| if (o.time < 0 or o.time >= 10) return gap(cx, 0, "survival time display outside [0, 10) is not verified", .{});
    const strata = try a.alloc(Stratum, sel.levels.len);
    for (strata, 0..) |*st, k| {
        var members: std.ArrayList(Obs) = .empty;
        for (sel.obs) |o| if (o.stratum == k) try members.append(a, o);
        st.* = try productLimit(a, members.items);
        if (st.unverified) |reason| return gap(cx, 0, "{s} is not verified", .{reason});
    }
    const h = try homogeneity(a, sel.obs, 2);
    for ([_]f64{ h.logrank[0], h.wilcoxon[0] }) |x| if (!(@abs(x) >= 0.1 and @abs(x) < 10)) return gap(cx, 0, "rank statistic display outside 0.1 <= |x| < 10 is not verified", .{});
    for ([_]f64{ h.logrank_cov[0], h.wilcoxon_cov[0] }) |x| if (!(x >= 1 and x < 100)) return gap(cx, 0, "rank covariance display outside 1 <= x < 100 is not verified", .{});

    var body: Out = .empty;
    for (strata, 0..) |st, k| {
        try body.print(a, "\nThe LIFETEST Procedure\n \nStratum {d}: {s} = {s}\n\n", .{ k + 1, strata_name, labels[k] });
        if (!s.notable) {
            try body.appendSlice(a, "                 Product-Limit Survival Estimates\n \n                                     Survival\n                                     Standard    Number    Number\n");
            try padRight(a, &body, time_name, 8);
            try body.appendSlice(a, "     Survival    Failure      Error      Failed     Left\n\n");
            try body.print(a, " 0.00000       1.0000           0           0      0{d:>10}   \n", .{st.total});
            var any_censored = false;
            for (st.rows) |row| {
                any_censored = any_censored or row.censored;
                try padRight(a, &body, try fixed(a, row.time, 5), 8);
                try body.append(a, if (row.censored) '*' else ' ');
                try probability(a, &body, row.survival);
                try probability(a, &body, if (row.survival) |x| 1 - x else null);
                // The standard error is undefined once the estimate reaches 0.
                try probability(a, &body, if (row.censored) null else row.se);
                try body.print(a, "{d:>7}{d:>10}   \n", .{ row.failed, row.left });
            }
            if (any_censored) try body.appendSlice(a, "\nNOTE: The marked survival times are censored observations.\n");
            try body.appendSlice(a, "\n\n");
        }
        try body.print(a, "Summary Statistics for Time Variable {s}\n\n                   Quartile Estimates\n \n              Point         95% Confidence Interval\nPercent    Estimate    Transform      [Lower      Upper)\n\n", .{time_name});
        for ([_]usize{ 75, 50, 25 }, st.quartiles) |percent, q| {
            try body.print(a, "{d:>7}", .{percent});
            try timeCell(a, &body, q.estimate);
            try body.appendSlice(a, "    LOGLOG   ");
            try timeCell(a, &body, q.lower);
            try timeCell(a, &body, q.upper);
            try body.append(a, '\n');
        }
        try body.appendSlice(a, "\n\n            Standard\n    Mean       Error\n\n");
        try padRight(a, &body, try fixed(a, st.mean, 5), 8);
        try padRight(a, &body, try fixed(a, st.mean_se.?, 5), 12);
        try body.append(a, '\n');
        // ponytail: the note is wrapped as the reference wraps it at LINESIZE=160.
        if (st.last_censored) try body.appendSlice(a, "\nNOTE: The mean survival time and its standard error were underestimated because the largest observation was censored and the estimation was restricted to the \n      largest event time.\n");
    }
    try body.appendSlice(a, "\n\n    Summary of the Number of Censored and Uncensored Values\n \n                                                        Percent\nStratum    ");
    try padLeft(a, &body, strata_name, 8);
    try body.appendSlice(a, "       Total  Failed    Censored    Censored\n\n");
    var total: usize = 0;
    var failed: usize = 0;
    for (strata, 0..) |st, k| {
        total += st.total;
        failed += st.failed;
        try body.print(a, "{d:>7}    ", .{k + 1});
        try padLeft(a, &body, labels[k], 8);
        try body.print(a, "{d:>12}{d:>8}{d:>12}{s:>12}\n", .{ st.total, st.failed, st.total - st.failed, try fixed(a, 100 * @as(f64, @floatFromInt(st.total - st.failed)) / @as(f64, @floatFromInt(st.total)), 2) });
    }
    try body.appendNTimes(a, '-', 63);
    try body.print(a, "\n  Total            {d:>12}{d:>8}{d:>12}{s:>12}\n", .{ total, failed, total - failed, try fixed(a, 100 * @as(f64, @floatFromInt(total - failed)) / @as(f64, @floatFromInt(total)), 2) });
    try body.print(a, "\nThe LIFETEST Procedure\n\nTesting Homogeneity of Survival Curves for {s} over Strata\n\n\n        Rank Statistics\n \n", .{time_name});
    try padLeft(a, &body, strata_name, 8);
    try body.appendSlice(a, "    Log-Rank    Wilcoxon\n\n");
    for (labels, 0..) |label, k| {
        try padLeft(a, &body, label, 8);
        try padRight(a, &body, try fixed(a, h.logrank[k], if (@abs(h.logrank[k]) < 1) 5 else 4), 12);
        try padRight(a, &body, try fixed(a, h.wilcoxon[k], if (@abs(h.wilcoxon[k]) < 1) 5 else 4), 12);
        try body.append(a, '\n');
    }
    for ([_][]const u8{ "Log-Rank", "Wilcoxon" }, [_][]const f64{ h.logrank_cov, h.wilcoxon_cov }) |title, cov| {
        try body.print(a, "\n\nCovariance Matrix for the {s} Statistics\n \n", .{title});
        try padLeft(a, &body, strata_name, 8);
        try padRight(a, &body, labels[0], 11);
        try padRight(a, &body, labels[1], 14);
        try body.appendSlice(a, "\n\n");
        const decimals: usize = if (cov[0] < 10) 5 else 4;
        for (labels, 0..) |label, k| {
            try padLeft(a, &body, label, 8);
            try padRight(a, &body, try fixed(a, cov[k * 2], decimals), 11);
            try padRight(a, &body, try fixed(a, cov[k * 2 + 1], decimals), 14);
            try body.append(a, '\n');
        }
    }
    try body.appendSlice(a, "\n\n       Test of Equality over Strata\n \n                                   Pr >\nTest      Chi-Square      DF    Chi-Square\n\n");
    const logrank = try quadraticForm(a, h.logrank, h.logrank_cov, 2);
    const wilcoxon = try quadraticForm(a, h.wilcoxon, h.wilcoxon_cov, 2);
    // The covariance range checks above guarantee rank 1 for two strata.
    if (logrank.df != 1 or wilcoxon.df != 1) return gap(cx, 0, "equality tests with a singular two-stratum covariance are not verified", .{});
    const tests = [_]struct { name: []const u8, chi: f64 }{
        .{ .name = "Log-Rank", .chi = logrank.chi },
        .{ .name = "Wilcoxon", .chi = wilcoxon.chi },
        .{ .name = "-2Log(LR)", .chi = h.lr },
    };
    for (tests) |tst| {
        const p = chiProbability(tst.chi, 1);
        try padLeft(a, &body, tst.name, 10);
        try padRight(a, &body, try fixed(a, tst.chi, 4), 10);
        try body.appendSlice(a, "       1      ");
        try body.appendSlice(a, if (p < 0.0001) "<.0001" else try fixed(a, p, 4));
        try body.appendSlice(a, "  \n");
    }
    try cx.diags.note(0, "The LOGLOG transform is used to compute the confidence limits for the quartiles of the survivor distribution. To suppress using this transform, specify CONFTYPE=LINEAR in the PROC LIFETEST statement.", .{});
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const groups = try plan(cx, s);
    if (s.noprint) return;
    if (groups.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    for (groups) |group| try render(cx, out, s, group);
}

test {
    _ = @import("lifetest_tests.zig");
}
