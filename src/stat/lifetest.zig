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
const survival = @import("survival_data.zig");
const lt = @import("lifetest_lt.zig");
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
    method: Method = .km,
    /// Life-table interval starts, ascending and beginning at 0 (INTERVALS=).
    intervals: ?[]const f64 = null,
    ninterval: ?f64 = null,
    width: ?f64 = null,
};
pub const Method = enum { km, lt };

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
            // The Breslow and Fleming-Harrington estimates are computed
            // (lifetest_lt.zig) but their listing has no layout reference.
            if (oneOf(m, &.{ "breslow", "b", "fh", "lifetable", "actuarial" })) return gap(cx, t[i].line, "METHOD={s} is not implemented", .{m});
            if (oneOf(m, &.{ "lt", "life", "act" })) s.method = .lt else if (oneOf(m, &.{ "km", "pl" })) s.method = .km else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "intervals") and at(t, i + 1, .eq)) {
            if (s.intervals != null) return invalid(cx, t, i);
            s.intervals = try intervalList(cx, t, &i);
        } else if ((eq(word, "ninterval") or eq(word, "width")) and at(t, i + 1, .eq)) {
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const x = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFETEST: {s}= must be positive", .{word});
            if (eq(word, "width")) s.width = x else s.ninterval = x;
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
    if (s.method != .lt) {
        // With the product-limit method INTERVALS= only thins the display.
        if (s.intervals != null) return gap(cx, 0, "option intervals is not implemented", .{});
        if (s.ninterval != null) return gap(cx, 0, "option ninterval is not implemented", .{});
        if (s.width != null) return gap(cx, 0, "option width is not implemented", .{});
    }
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
            // TIME options (physical p.5669): FAILCODE/EVENTCODE request a
            // competing-risks analysis; nothing else may follow the slash.
            for (i + 1..end) |j| if (at(t, j, .slash)) {
                if (kw(t, j + 1, "failcode") or kw(t, j + 1, "eventcode")) return gap(cx, t[j].line, "TIME option {s} (competing-risks analysis) is not implemented", .{t[j + 1].text});
                return invalid(cx, t, j + 1);
            };
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

/// INTERVALS= endpoints, physical p.5653: blank or comma separated values and
/// `x to y <by z>` ranges, optionally parenthesized. The result is ascending,
/// without duplicates, and always starts at 0.
fn intervalList(cx: proc.ProcCtx, t: []const lex.Token, index: *usize) diag.Error![]const f64 {
    var i = index.* + 2;
    const paren = at(t, i, .lparen);
    if (paren) i += 1;
    var list: std.ArrayList(f64) = .empty;
    try list.append(cx.arena, 0);
    var seen = false;
    while (true) {
        if (at(t, i, .comma)) {
            i += 1;
            continue;
        }
        if (at(t, i, .minus)) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFETEST: INTERVALS= endpoints must be nonnegative", .{});
        if (!at(t, i, .number)) break;
        const first = std.fmt.parseFloat(f64, t[i].text) catch return invalid(cx, t, i);
        i += 1;
        seen = true;
        if (!kw(t, i, "to")) {
            try list.append(cx.arena, first);
            continue;
        }
        if (!at(t, i + 1, .number)) return invalid(cx, t, i + 1);
        const last = std.fmt.parseFloat(f64, t[i + 1].text) catch return invalid(cx, t, i + 1);
        i += 2;
        var step: f64 = 1;
        if (kw(t, i, "by")) {
            if (!at(t, i + 1, .number)) return invalid(cx, t, i + 1);
            step = std.fmt.parseFloat(f64, t[i + 1].text) catch return invalid(cx, t, i + 1);
            if (!(step > 0)) return cx.diags.fail(error.ParseError, t[i].line, "PROC LIFETEST: INTERVALS= increment must be positive", .{});
            i += 2;
        }
        // ponytail: 1e-9 relative slack so that a decimal increment whose
        // multiples round just above the stop value still includes it.
        const count = @floor((last - first) / step * (1 + 1e-9) + 1e-9);
        if (!(count >= 0 and count < 100000)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC LIFETEST: invalid INTERVALS= range", .{});
        var k: f64 = 0;
        while (k <= count) : (k += 1) try list.append(cx.arena, first + k * step);
    }
    if (!seen) return invalid(cx, t, i);
    if (paren) {
        if (!at(t, i, .rparen)) return invalid(cx, t, i);
        i += 1;
    }
    std.mem.sort(f64, list.items, {}, std.sort.asc(f64));
    var n: usize = 1;
    for (list.items[1..]) |x| {
        if (x != list.items[n - 1]) {
            list.items[n] = x;
            n += 1;
        }
    }
    index.* = i;
    return list.items[0..n];
}

pub const Obs = survival.Obs;
pub const Selected = struct {
    obs: []const Obs,
    /// One representative row per stratum level, ascending (missing first).
    levels: []const []const Value,
    read: usize,
    /// The BY group's rows (Obs.row indexes them) and its first row.
    rows: []const []const Value = &.{},
    by_row: ?[]const Value = null,
};

/// Observation selection, physical pp.5663, 5670-5671, through the shared
/// survival-data contract: a missing time or censoring value drops the
/// observation; a missing stratum value drops it unless MISSING; FREQ is
/// truncated unless NOTRUNCATE and a missing or nonpositive (after
/// truncation: below one) frequency drops it; a missing or nonpositive WEIGHT
/// drops it. ID values never select. Strata levels are ordered ascending by
/// unformatted value.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    const c = try survival.classifyRight(a, .{
        .response = .{ .right = .{ .time = s.time, .censor = s.censor, .censor_values = s.censor_values } },
        .strata = s.strata,
        .missing = s.missing,
        .frequency = s.frequency,
        .notruncate = s.notruncate,
        .weight = s.weight,
    }, rows);
    return .{ .obs = c.obs, .levels = c.levels, .read = rows.len, .rows = rows };
}

pub const Row = struct {
    time: f64,
    censored: bool,
    survival: ?f64 = null,
    se: ?f64 = null,
    failed: usize,
    left: usize,
    freq: usize = 1,
    row: usize = 0,
    /// WEIGHT analyses: weighted cumulative failures, weighted number left and
    /// the observation's weight.
    failed_w: f64 = 0,
    left_w: f64 = 0,
    weight: f64 = 1,
};
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

/// Integer replication count of an observation; render() gaps fractional
/// (NOTRUNCATE) frequencies before any estimate is listed.
fn units(o: Obs) usize {
    return @intFromFloat(@max(o.freq, 0));
}

fn obsLess(_: void, x: Obs, y: Obs) bool {
    if (x.time != y.time) return x.time < y.time;
    return x.event and !y.event;
}

/// Kaplan-Meier estimate with Greenwood standard error, quartiles with
/// log-log limits and the restricted mean, physical pp.5671-5673.
pub fn productLimit(a: A, input: []const Obs) !Stratum {
    return productLimitImpl(a, input, false);
}

/// The adjusted Kaplan-Meier estimate (AKME, Xie and Liu 2005) for the WEIGHT
/// statement, physical p.5673: weighted events and risk sets in the product,
/// variance S(t)^2 * sum (d_w/Y_w) / (M_j (1 - d_w/Y_w)) with the effective
/// risk-set size M_j = (sum w)^2 / sum w^2. The restricted-mean variance uses
/// the same increments and the unweighted event count in m/(m-1) (verified
/// against a SAS listing of invented data).
pub fn productLimitWeighted(a: A, input: []const Obs) !Stratum {
    return productLimitImpl(a, input, true);
}

fn productLimitImpl(a: A, input: []const Obs, weighted: bool) !Stratum {
    const obs = try a.dupe(Obs, input);
    std.mem.sort(Obs, obs, {}, obsLess);
    var rows: std.ArrayList(Row) = .empty;
    var times: std.ArrayList(f64) = .empty;
    var risk: std.ArrayList(f64) = .empty;
    var deaths: std.ArrayList(f64) = .empty;
    var surv: std.ArrayList(f64) = .empty;
    var ses: std.ArrayList(?f64) = .empty;
    var increments: std.ArrayList(f64) = .empty;
    var left_w: f64 = 0;
    var failed_w: f64 = 0;
    for (obs) |o| left_w += o.weight;
    var st: Stratum = .{ .rows = &.{}, .total = obs.len, .failed = 0, .event_times = &.{}, .at_risk = &.{}, .deaths = &.{}, .survival = &.{}, .se = &.{} };
    var s: f64 = 1;
    var greenwood: f64 = 0;
    // FREQ replicates an observation (physical p.5663): one listing row per
    // observation, its count added to the failed/left columns at once.
    var left: usize = 0;
    for (obs) |o| left += units(o);
    st.total = left;
    var i: usize = 0;
    while (i < obs.len) {
        var j = i;
        var d: usize = 0;
        var event_rows: usize = 0;
        while (j < obs.len and obs[j].time == obs[i].time) : (j += 1) {
            if (obs[j].event) {
                d += units(obs[j]);
                event_rows += 1;
            }
        }
        if (d > 0 and weighted) {
            var dw: f64 = 0;
            var squares: f64 = 0;
            for (obs[i..j]) |o| if (o.event) {
                dw += o.weight;
            };
            for (obs[i..]) |o| squares += o.weight * o.weight;
            const ratio = dw / left_w;
            s *= 1 - ratio;
            var se: ?f64 = null;
            var increment: f64 = 0;
            if (d < left) {
                increment = ratio / ((left_w * left_w / squares) * (1 - ratio));
                greenwood += increment;
                se = s * @sqrt(greenwood);
            } else s = 0;
            if (d > 1) st.tied_events = true;
            const n: f64 = @floatFromInt(left);
            for (obs[i .. i + event_rows], 0..) |o, k| {
                left -= units(o);
                st.failed += units(o);
                left_w -= o.weight;
                failed_w += o.weight;
                const last = k + 1 == event_rows;
                try rows.append(a, .{ .time = o.time, .censored = false, .survival = if (last) s else null, .se = if (last) se else null, .failed = st.failed, .left = left, .row = o.row, .failed_w = failed_w, .left_w = @max(left_w, 0), .weight = o.weight });
            }
            try times.append(a, obs[i].time);
            try risk.append(a, n);
            try deaths.append(a, @floatFromInt(d));
            try surv.append(a, s);
            try ses.append(a, se);
            try increments.append(a, increment);
        } else if (d > 0) {
            const n: f64 = @floatFromInt(left);
            const df: f64 = @floatFromInt(d);
            s *= (n - df) / n;
            var se: ?f64 = null;
            if (d < left) {
                greenwood += df / (n * (n - df));
                se = s * @sqrt(greenwood);
            } else s = 0;
            if (d > 1) st.tied_events = true;
            for (obs[i .. i + event_rows], 0..) |o, k| {
                left -= units(o);
                st.failed += units(o);
                const last = k + 1 == event_rows;
                try rows.append(a, .{ .time = o.time, .censored = false, .survival = if (last) s else null, .se = if (last) se else null, .failed = st.failed, .left = left, .freq = units(o), .row = o.row });
            }
            try times.append(a, obs[i].time);
            try risk.append(a, n);
            try deaths.append(a, df);
            try surv.append(a, s);
            try ses.append(a, se);
        }
        for (obs[i + event_rows .. j]) |o| {
            left -= units(o);
            left_w -= o.weight;
            try rows.append(a, .{ .time = o.time, .censored = true, .failed = st.failed, .left = left, .freq = units(o), .row = o.row, .failed_w = failed_w, .left_w = @max(left_w, 0), .weight = o.weight });
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
                // A plateau after the last event time ends at a censored time,
                // so the midpoint is undefined and the estimate is missing
                // (SAS listing with MISSING: 75th percentile of stratum A).
                if (k + 1 < count) st.quartiles[q].estimate = (times.items[k] + times.items[k + 1]) / 2;
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
        if (weighted) variance += area * area * increments.items[k] else if (n > d) variance += area * area * d / (n * (n - d));
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
        exposure[o.stratum] += o.freq * o.time;
        if (o.event) events[o.stratum] += o.freq;
    }
    for (obs, 0..) |pivot, index| {
        if (!pivot.event) continue;
        var earlier = false;
        for (obs[0..index]) |o| earlier = earlier or (o.event and o.time == pivot.time);
        if (earlier) continue;
        @memset(n_k, 0);
        @memset(d_k, 0);
        for (obs) |o| {
            if (o.time >= pivot.time) n_k[o.stratum] += o.freq;
            if (o.event and o.time == pivot.time) d_k[o.stratum] += o.freq;
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

/// Weighted (adjusted) log-rank test with the WEIGHT statement, physical
/// p.5682 (Xie and Liu 2005, 2011): v_k = sum_j (d^w_jk - Y^w_jk d^w_j / Y^w_j)
/// and V_kh = sum_j d_j (Y_j - d_j) / (Y_j (Y_j - 1)) sum_i c_ik c_ih over the
/// risk set, c_ik = w_i (I(X_i = k) - Y^w_jk / Y^w_j); the guide's V_kk and
/// V_kh terms are exactly these products. The Wilcoxon version multiplies
/// each event time by the weighted number at risk Y^w_j (verified against a
/// SAS listing of invented data). SAS lists no likelihood-ratio test here.
pub fn weightedHomogeneity(a: A, obs: []const Obs, k: usize) !Homogeneity {
    const h: Homogeneity = .{ .logrank = try a.alloc(f64, k), .wilcoxon = try a.alloc(f64, k), .logrank_cov = try a.alloc(f64, k * k), .wilcoxon_cov = try a.alloc(f64, k * k), .lr = 0 };
    @memset(h.logrank, 0);
    @memset(h.wilcoxon, 0);
    @memset(h.logrank_cov, 0);
    @memset(h.wilcoxon_cov, 0);
    const yw = try a.alloc(f64, k);
    const dw = try a.alloc(f64, k);
    for (obs, 0..) |pivot, index| {
        if (!pivot.event) continue;
        var earlier = false;
        for (obs[0..index]) |o| earlier = earlier or (o.event and o.time == pivot.time);
        if (earlier) continue;
        @memset(yw, 0);
        @memset(dw, 0);
        var n: f64 = 0;
        var d: f64 = 0;
        for (obs) |o| {
            if (o.time >= pivot.time) {
                yw[o.stratum] += o.weight;
                n += 1;
            }
            if (o.event and o.time == pivot.time) {
                dw[o.stratum] += o.weight;
                d += 1;
            }
        }
        var y_total: f64 = 0;
        var d_total: f64 = 0;
        for (yw, dw) |x, y| {
            y_total += x;
            d_total += y;
        }
        for (0..k) |g| {
            const v = dw[g] - yw[g] * d_total / y_total;
            h.logrank[g] += v;
            h.wilcoxon[g] += y_total * v;
        }
        if (n > 1) {
            const factor = d * (n - d) / (n * (n - 1));
            for (obs) |o| if (o.time >= pivot.time) for (0..k) |g| for (0..k) |l| {
                const cg = o.weight * ((if (o.stratum == g) @as(f64, 1) else 0) - yw[g] / y_total);
                const cl = o.weight * ((if (o.stratum == l) @as(f64, 1) else 0) - yw[l] / y_total);
                h.logrank_cov[g * k + l] += factor * cg * cl;
                h.wilcoxon_cov[g * k + l] += y_total * y_total * factor * cg * cl;
            };
        }
    }
    return h;
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
    for (slices, groups) |slice, *group| {
        group.* = try select(cx.arena, s, slice.rows);
        group.by_row = slice.rep;
    }
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

/// Integer digits of |x| (0 below 1).
fn intDigits(x: f64) usize {
    var n: usize = 0;
    var v = @abs(x);
    while (v >= 1) : (v /= 10) n += 1;
    return n;
}
/// Decimals SAS prints in a rank-statistic or covariance column: the column
/// shares one count, set by its largest magnitude, so that the column shows
/// `significant` digits (5 for rank statistics, 6 for covariances; below one
/// the rank statistics keep 5 decimals, the covariances 6). Evidenced by SAS
/// listings for column maxima in [0.1, limit); outside that range, or where a
/// per-value rule would print differently from the per-column one and the
/// listings do not tell which applies, the caller gaps.
fn columnDecimals(values: []const f64, significant: usize, below_one: usize, limit: f64) ?usize {
    var top: f64 = 0;
    for (values) |x| top = @max(top, @abs(x));
    if (!(top >= 0.1 and top < limit)) return null;
    const digits = intDigits(top);
    return if (digits == 0) below_one else significant - digits;
}
/// A covariance cell in an 8-column field: a negative value below one drops
/// its leading zero when it would not fit (SAS listing `-.962222`).
fn covarianceText(a: A, x: f64, decimals: usize) ![]const u8 {
    const text = try fixed(a, x, decimals);
    if (text.len > 8 and std.mem.startsWith(u8, text, "-0.")) return std.fmt.allocPrint(a, "-{s}", .{text[2..]});
    return text;
}
/// Every page of the listing starts like this; inside a BY group the BY line
/// precedes the procedure title (SAS listing with BY).
fn pageHead(a: A, body: *Out, byline: []const u8) !void {
    if (byline.len > 0) try body.print(a, "\n{s}\n", .{byline});
    try body.appendSlice(a, "\nThe LIFETEST Procedure\n");
}

/// Weighted-count cells: 12 wide, exact zero as 0, otherwise 4 decimals.
fn weightCell(a: A, out: *Out, x: f64) !void {
    // ponytail: a weighted number left that cancels to rounding noise is 0.
    try padRight(a, out, if (@abs(x) < 1e-9) "0" else try fixed(a, x, 4), 12);
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, sel: Selected) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    // Execution boundary: only the listing shapes proven against SAS
    // reference listings and independent hand calculation are produced.
    const weighted = s.weight != null;
    if (weighted and (s.frequency != null or s.ids.len > 0)) return gap(cx, 0, "WEIGHT together with FREQ or ID in the survival listing is not verified", .{});
    if (s.ids.len > 1) return gap(cx, 0, "several ID variables in the survival listing are not verified", .{});
    if (s.ids.len > 0 and s.frequency != null) return gap(cx, 0, "ID together with FREQ in the survival listing is not verified", .{});
    const id_col: ?usize = if (s.ids.len == 1) s.ids[0] else null;
    if (id_col) |c| {
        const info = ds.columns.items[c];
        // ponytail: the ID column is evidenced for a character variable of
        // length 8 with a name of at most 8 characters.
        if (info.type != .char or info.format != null or (info.len orelse 8) != 8 or info.name.len > 8) return gap(cx, 0, "ID column layout other than an unformatted $8 character variable is not verified", .{});
    }
    for (sel.obs) |o| if (o.freq != @floor(o.freq)) return gap(cx, 0, "noninteger FREQ values (NOTRUNCATE) are not implemented", .{});
    if (sel.obs.len == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});
    if (s.strata.len != 1) return gap(cx, 0, "listing without STRATA or with several STRATA variables is not implemented", .{});
    const strata_info = ds.columns.items[s.strata[0]];
    if (strata_info.format != null) return gap(cx, 0, "formatted STRATA levels are not implemented", .{});
    // An unformatted numeric STRATA variable prints in a 12-wide BEST12.
    // column (SAS listing); the layout is evidenced for integer levels.
    const numeric = strata_info.type == .num;
    if (sel.levels.len < 2) return gap(cx, 0, "the listing for a single stratum is not verified", .{});
    const time_name = ds.columns.items[s.time].name;
    const strata_name = strata_info.name;
    // ponytail: column widths are verified for names and levels that fit the
    // reference's 8-character columns; wider text needs the template widths.
    if (time_name.len > 8 or strata_name.len > 8) return gap(cx, 0, "listing columns for variable names longer than 8 characters are not verified", .{});
    const labels = try a.alloc([]const u8, sel.levels.len);
    for (sel.levels, labels) |row, *label| {
        // A missing level (MISSING option) is listed blank, ordered first.
        if (numeric) {
            const x = row[s.strata[0]].num;
            if (std.math.isNan(x) or x != @floor(x) or @abs(x) >= 1e8) return gap(cx, 0, "missing or noninteger numeric STRATA levels are not verified", .{});
            label.* = try std.fmt.allocPrint(a, "{d}", .{@as(i64, @intFromFloat(x))});
        } else label.* = std.mem.trimEnd(u8, row[s.strata[0]].str, " ");
        if (label.len > 8) return gap(cx, 0, "listing columns for STRATA levels longer than 8 characters are not verified", .{});
    }
    for (sel.obs) |o| if (o.time < 0 or o.time >= 10) return gap(cx, 0, "survival time display outside [0, 10) is not verified", .{});
    const K = sel.levels.len;
    const strata = try a.alloc(Stratum, K);
    for (strata, 0..) |*st, k| {
        var members: std.ArrayList(Obs) = .empty;
        for (sel.obs) |o| if (o.stratum == k) try members.append(a, o);
        st.* = if (weighted) try productLimitWeighted(a, members.items) else try productLimit(a, members.items);
        if (st.unverified) |reason| return gap(cx, 0, "{s} is not verified", .{reason});
        if (weighted) {
            var sum: f64 = 0;
            for (members.items) |o| sum += o.weight;
            // ponytail: weighted columns are evidenced below 100.
            if (!(sum < 100)) return gap(cx, 0, "weighted number display of 100 or more is not verified", .{});
        }
    }
    const h = if (weighted) try weightedHomogeneity(a, sel.obs, K) else try homogeneity(a, sel.obs, K);
    // Column decimals (see columnDecimals); each column must agree with the
    // per-value rule except where a SAS listing shows the column rule.
    const rank_dec = try a.alloc(usize, 2);
    for ([_][]const f64{ h.logrank, h.wilcoxon }, rank_dec) |col, *dec| {
        dec.* = columnDecimals(col, 5, 5, 100) orelse return gap(cx, 0, "rank statistic display outside 0.1 <= |x| < 100 is not verified", .{});
        for (col) |x| if (columnDecimals(&.{x}, 5, 5, 100) != dec.*) return gap(cx, 0, "rank statistics of different magnitudes in one column are not verified", .{});
    }
    const cov_dec = try a.alloc(usize, 2 * K);
    for ([_][]const f64{ h.logrank_cov, h.wilcoxon_cov }, 0..) |cov, m| {
        var whole: ?usize = null;
        for (0..K) |c| {
            const col = try a.alloc(f64, K);
            for (0..K) |r| col[r] = cov[r * K + c];
            const dec = columnDecimals(col, 6, 6, 1000) orelse return gap(cx, 0, "rank covariance display outside 0.1 <= |x| < 1000 is not verified", .{});
            if (whole != null and whole.? != dec) return gap(cx, 0, "covariance columns of different magnitudes are not verified", .{});
            whole = dec;
            cov_dec[m * K + c] = dec;
        }
    }
    const logrank = try quadraticForm(a, h.logrank, h.logrank_cov, K);
    const wilcoxon = try quadraticForm(a, h.wilcoxon, h.wilcoxon_cov, K);
    if (logrank.df != K - 1 or wilcoxon.df != K - 1) return gap(cx, 0, "equality tests with a singular rank covariance are not verified", .{});
    var byline: []const u8 = "";
    if (sel.by_row) |row| {
        var tmp: Out = .empty;
        try by.appendLine(a, &tmp, ds, row, s.by_cols);
        byline = std.mem.trim(u8, tmp.items, " \n");
    }

    var body: Out = .empty;
    // Optional columns after Number Left: FREQ adds `Freq`, ID adds the ID
    // variable; the table title is centred over the wider table.
    const indent: usize = if (weighted) 25 else if (s.frequency != null) 21 else if (id_col != null) 23 else 17;
    // NOTABLE (physical p.5654) leaves only the censoring summary and the
    // tests: the SAS listing drops each stratum's page (estimates, quartiles,
    // mean) and the log drops the quartile-transform note.
    if (!s.notable) for (strata, 0..) |st, k| {
        try pageHead(a, &body, byline);
        try body.print(a, " \nStratum {d}: {s} = {s}\n\n", .{ k + 1, strata_name, labels[k] });
        {
            try body.appendNTimes(a, ' ', indent);
            try body.appendSlice(a, "Product-Limit Survival Estimates\n \n");
            try body.appendSlice(a, if (weighted) "                                     Survival          Weighted\n                                     Standard     Number      Number\n" else "                                     Survival\n                                     Standard    Number    Number\n");
            try padRight(a, &body, time_name, 8);
            try body.appendSlice(a, if (weighted) "     Survival    Failure      Error       Failed       Left        Weight" else "     Survival    Failure      Error      Failed     Left");
            if (s.frequency != null) try body.appendSlice(a, "     Freq");
            if (id_col) |c| try body.print(a, "     {s}", .{ds.columns.items[c].name});
            try body.appendSlice(a, "\n\n");
            if (weighted) {
                var sum: f64 = 0;
                for (st.rows) |row| sum += row.weight;
                try body.appendSlice(a, " 0.00000       1.0000           0           0");
                try weightCell(a, &body, 0);
                try weightCell(a, &body, sum);
                try weightCell(a, &body, 0);
                try body.append(a, '\n');
            } else try body.print(a, " 0.00000       1.0000           0           0      0{d:>10}", .{st.total});
            if (weighted) {} else if (s.frequency != null) try body.print(a, "{d:>11}\n", .{0}) else if (id_col != null) try body.appendSlice(a, "               \n") else try body.appendSlice(a, "   \n");
            var any_censored = false;
            for (st.rows) |row| {
                any_censored = any_censored or row.censored;
                try padRight(a, &body, try fixed(a, row.time, 5), 8);
                try body.append(a, if (row.censored) '*' else ' ');
                try probability(a, &body, row.survival);
                try probability(a, &body, if (row.survival) |x| 1 - x else null);
                // The standard error is undefined once the estimate reaches 0.
                try probability(a, &body, if (row.censored) null else row.se);
                if (weighted) {
                    try weightCell(a, &body, row.failed_w);
                    try weightCell(a, &body, row.left_w);
                    try weightCell(a, &body, row.weight);
                    try body.append(a, '\n');
                    continue;
                }
                try body.print(a, "{d:>7}{d:>10}", .{ row.failed, row.left });
                if (s.frequency != null) {
                    try body.print(a, "{d:>11}\n", .{row.freq});
                } else if (id_col) |c| {
                    try body.appendSlice(a, "       ");
                    try padLeft(a, &body, std.mem.trimEnd(u8, sel.rows[row.row][c].str, " "), 8);
                    try body.append(a, '\n');
                } else try body.appendSlice(a, "   \n");
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
    };
    if (s.notable) try pageHead(a, &body, byline) else try body.appendSlice(a, "\n");
    // A numeric STRATA column is 12 wide instead of 8; the centred title and
    // the rule widen with it.
    const extra: usize = if (numeric) 4 else 0;
    try body.appendSlice(a, "\n");
    try body.appendNTimes(a, ' ', 4 + extra / 2);
    try body.appendSlice(a, "Summary of the Number of Censored and Uncensored Values\n \n");
    try body.appendNTimes(a, ' ', 56 + extra);
    try body.appendSlice(a, "Percent\nStratum    ");
    if (numeric) try padRight(a, &body, strata_name, 12) else try padLeft(a, &body, strata_name, 8);
    try body.appendSlice(a, "       Total  Failed    Censored    Censored\n\n");
    var total: usize = 0;
    var failed: usize = 0;
    for (strata, 0..) |st, k| {
        total += st.total;
        failed += st.failed;
        try body.print(a, "{d:>7}    ", .{k + 1});
        if (numeric) try padRight(a, &body, labels[k], 12) else try padLeft(a, &body, labels[k], 8);
        try body.print(a, "{d:>12}{d:>8}{d:>12}{s:>12}\n", .{ st.total, st.failed, st.total - st.failed, try fixed(a, 100 * @as(f64, @floatFromInt(st.total - st.failed)) / @as(f64, @floatFromInt(st.total)), 2) });
    }
    try body.appendNTimes(a, '-', 63 + extra);
    try body.appendSlice(a, "\n  Total");
    try body.appendNTimes(a, ' ', 12 + extra);
    try body.print(a, "{d:>12}{d:>8}{d:>12}{s:>12}\n", .{ total, failed, total - failed, try fixed(a, 100 * @as(f64, @floatFromInt(total - failed)) / @as(f64, @floatFromInt(total)), 2) });
    try pageHead(a, &body, byline);
    try body.print(a, "\nTesting Homogeneity of Survival Curves for {s} over Strata\n\n\n        Rank Statistics\n \n", .{time_name});
    try padLeft(a, &body, strata_name, 8);
    try body.appendSlice(a, "    Log-Rank    Wilcoxon\n\n");
    for (labels, 0..) |label, k| {
        try padLeft(a, &body, label, 8);
        try padRight(a, &body, try fixed(a, h.logrank[k], rank_dec[0]), 12);
        try padRight(a, &body, try fixed(a, h.wilcoxon[k], rank_dec[1]), 12);
        try body.append(a, '\n');
    }
    for ([_][]const u8{ "Log-Rank", "Wilcoxon" }, [_][]const f64{ h.logrank_cov, h.wilcoxon_cov }, 0..) |title, cov, m| {
        // The title is centred over the 8 + 11 + 14(K-1) column table.
        const heading = try std.fmt.allocPrint(a, "Covariance Matrix for the {s} Statistics", .{title});
        const first: usize = if (numeric) 9 else 11;
        const width = 8 + first + 14 * (K - 1);
        try body.appendSlice(a, "\n\n");
        if (width > heading.len) try body.appendNTimes(a, ' ', (width - heading.len + 1) / 2);
        try body.print(a, "{s}\n \n", .{heading});
        try padLeft(a, &body, strata_name, 8);
        for (labels, 0..) |label, c| try padRight(a, &body, label, if (c == 0) first else 14);
        try body.appendSlice(a, "\n\n");
        for (labels, 0..) |label, r| {
            try padLeft(a, &body, label, 8);
            for (0..K) |c| try padRight(a, &body, try covarianceText(a, cov[r * K + c], cov_dec[m * K + c]), if (c == 0) first else 14);
            try body.append(a, '\n');
        }
    }
    try body.appendSlice(a, "\n\n       Test of Equality over Strata\n \n                                   Pr >\nTest      Chi-Square      DF    Chi-Square\n\n");
    const tests = [_]struct { name: []const u8, chi: f64 }{
        .{ .name = "Log-Rank", .chi = logrank.chi },
        .{ .name = "Wilcoxon", .chi = wilcoxon.chi },
        .{ .name = "-2Log(LR)", .chi = h.lr },
    };
    const df: f64 = @floatFromInt(K - 1);
    // SAS lists no likelihood-ratio test for a WEIGHT analysis.
    for (tests[0..if (weighted) 2 else 3]) |tst| {
        const p = chiProbability(tst.chi, df);
        try padLeft(a, &body, tst.name, 10);
        try padRight(a, &body, try fixed(a, tst.chi, 4), 10);
        try body.print(a, "{d:>8}      ", .{K - 1});
        try body.appendSlice(a, if (p < 0.0001) "<.0001" else try fixed(a, p, 4));
        try body.appendSlice(a, "  \n");
    }
    if (!s.notable) try cx.diags.note(0, "The LOGLOG transform is used to compute the confidence limits for the quartiles of the survivor distribution. To suppress using this transform, specify CONFTYPE=LINEAR in the PROC LIFETEST statement.", .{});
    try out.appendSlice(a, body.items);
}

/// Life-table execution boundary: one sample with FREQ, explicit INTERVALS=.
fn renderLifeTable(cx: proc.ProcCtx, out: *Out, s: Spec, sel: Selected) diag.Error!void {
    // The CLI always carries a graphics session; only ODS GRAPHICS ON makes
    // SAS draw the default life-table survival plot.
    if (cx.graphics) |g| if (g.enabled == true) return gap(cx, 0, "life-table graphs under ODS GRAPHICS are not implemented", .{});
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group listing layout is not verified", .{});
    if (s.strata.len > 0) return gap(cx, 0, "life-table listing with STRATA is not implemented", .{});
    if (s.weight != null) return gap(cx, 0, "WEIGHT with the life-table method is not verified", .{});
    if (s.ids.len > 0) return gap(cx, 0, "ID with the life-table method is not verified", .{});
    if (s.notable) return gap(cx, 0, "NOTABLE with the life-table method is not verified", .{});
    // The guide gives the default width (lifetest_lt.defaultWidth) but not
    // how many intervals of that width are formed.
    const endpoints = s.intervals orelse return gap(cx, 0, "life-table intervals from WIDTH=, NINTERVAL= or the default are not implemented; specify INTERVALS=", .{});
    try lt.render(cx, out, sel.obs, endpoints, sel.read);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const groups = try plan(cx, s);
    if (s.noprint) return;
    if (groups.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    // All BY groups are rendered before anything is listed, so a gap in a
    // later group never leaves a partial listing behind.
    var all: Out = .empty;
    for (groups) |group| {
        if (s.method == .lt) try renderLifeTable(cx, &all, s, group) else try render(cx, &all, s, group);
    }
    try out.appendSlice(cx.arena, all.items);
}

test {
    _ = @import("lifetest_tests.zig");
}
