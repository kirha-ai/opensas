//! Shared survival-data contract (STAT-COMMON-015), SAS/STAT 15.4 physical
//! pp.255-262: the response encodings of the survival procedures, the status
//! of each observation, deterministic strata and per-stratum risk sets.
//!
//! Right censoring (`time*censor(values)`) is the only encoding with a landed
//! PROC ticket. Counting-process (left-truncated) and interval-censored
//! responses are representable so a parser can name them, but `check` refuses
//! them: a user error (rc 1) where the procedure does not accept the encoding
//! (LIFETEST "deals exclusively with right-censored data", PHREG "does not
//! allow" left or interval censoring, pp.258, 260) and a D-009 gap (rc 2)
//! where the encoding is valid SAS that opensas cannot execute yet.
//!
//! PROC LIFETEST selects its observations through `classifyRight`.
//! ponytail: PHREG still carries its own copy of these rules; its adoption is
//! a follow-up recorded on the ticket.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const Value = @import("../value.zig").Value;
const selection = @import("data_selection.zig");
const A = std.mem.Allocator;

pub const Procedure = enum {
    lifetest,
    phreg,
    iclifetest,
    icphreg,
    lifereg,

    pub fn label(self: Procedure) []const u8 {
        return switch (self) {
            .lifetest => "LIFETEST",
            .phreg => "PHREG",
            .iclifetest => "ICLIFETEST",
            .icphreg => "ICPHREG",
            .lifereg => "LIFEREG",
        };
    }
};

/// Column indices into the observation rows.
pub const Response = union(enum) {
    /// `time` or `time*censor(values)`: without a censoring variable every
    /// observation is an event.
    right: struct { time: usize, censor: ?usize = null, censor_values: []const f64 = &.{} },
    /// `(start, stop)*censor(values)`: left truncation / counting process.
    counting: struct { start: usize, stop: usize, censor: ?usize = null, censor_values: []const f64 = &.{} },
    /// `(lower, upper)`: a missing lower bound is left censoring, a missing
    /// upper bound right censoring, equal bounds an exact event.
    interval: struct { lower: usize, upper: usize },

    pub fn label(self: Response) []const u8 {
        return switch (self) {
            .right => "right-censored",
            .counting => "counting-process (left-truncated)",
            .interval => "interval-censored",
        };
    }
};

pub const Support = enum { supported, incompatible, unimplemented };

/// Whether `procedure` can analyse `response` here.
pub fn support(procedure: Procedure, response: Response) Support {
    return switch (procedure) {
        .lifetest => if (response == .right) .supported else .incompatible,
        .phreg => switch (response) {
            .right => .supported,
            .counting => .unimplemented,
            .interval => .incompatible,
        },
        // ponytail: no ticket has landed these procedures, so even an
        // encoding they would reject stays a gap rather than a guessed
        // user-error text.
        .iclifetest, .icphreg, .lifereg => .unimplemented,
    };
}

/// Raises the D-009 class for an encoding that cannot be analysed: a user
/// error for an incompatible one, a gap for an unimplemented one.
pub fn check(d: *diag.Diagnostics, line: usize, procedure: Procedure, response: Response) diag.Error!void {
    switch (support(procedure, response)) {
        .supported => {},
        .incompatible => return d.fail(error.ParseError, line, "PROC {s}: {s} response is not valid for this procedure", .{ procedure.label(), response.label() }),
        .unimplemented => return proc.failGap(d, line, "PROC {s}: {s} response is not implemented", .{ procedure.label(), response.label() }),
    }
}

pub const Roles = struct {
    response: Response,
    strata: []const usize = &.{},
    /// MISSING: a missing stratum value is a level of its own.
    missing: bool = false,
    frequency: ?usize = null,
    notruncate: bool = false,
    weight: ?usize = null,
};

pub const Exclusion = enum { missing_time, missing_censor, missing_stratum, missing_frequency, nonpositive_frequency, nonpositive_weight };
pub const Status = union(enum) {
    event,
    right_censored,
    /// Reserved for the interval encodings; never produced for `.right`.
    left_censored,
    interval_censored,
    excluded: Exclusion,

    pub fn used(self: Status) bool {
        return self != .excluded;
    }
};

pub const Obs = struct {
    /// Zero-based position in the classified rows.
    row: usize = 0,
    time: f64,
    event: bool,
    stratum: usize = 0,
    freq: f64 = 1,
    weight: f64 = 1,
};

pub const Classified = struct {
    /// One status per input row, in input order.
    status: []const Status,
    /// The used observations, in input order.
    obs: []const Obs,
    /// One representative row per stratum level, ascending by unformatted
    /// value with missing first; empty without strata (one stratum, index 0).
    levels: []const []const Value,

    pub fn strataCount(self: Classified) usize {
        return @max(self.levels.len, 1);
    }
    pub fn excluded(self: Classified, reason: Exclusion) usize {
        var n: usize = 0;
        for (self.status) |s| if (s == .excluded and s.excluded == reason) {
            n += 1;
        };
        return n;
    }
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

/// Per-observation status for a right-censored response, with the selection
/// rules PROC LIFETEST documents (physical pp.5663, 5670-5671): a missing
/// time or censoring value excludes the observation; a missing stratum value
/// excludes it unless MISSING; FREQ is truncated unless NOTRUNCATE and a
/// missing or nonpositive (after truncation: below one) frequency excludes
/// it; a missing or nonpositive WEIGHT excludes it. The first failing rule,
/// in that order, is the recorded reason. Any other encoding is refused by
/// `check` before a row is read.
/// ponytail: a negative time is kept as an ordinary time; no landed ticket
/// has verified a rule for it, and LIFETEST gaps on displaying one.
pub fn classify(a: A, d: *diag.Diagnostics, line: usize, procedure: Procedure, roles: Roles, rows: []const []const Value) diag.Error!Classified {
    try check(d, line, procedure, roles.response);
    return classifyRight(a, roles, rows);
}

/// `classify` for a response already known to be `.right`.
pub fn classifyRight(a: A, roles: Roles, rows: []const []const Value) error{OutOfMemory}!Classified {
    const r = roles.response.right;
    const status = try a.alloc(Status, rows.len);
    var obs: std.ArrayList(Obs) = .empty;
    for (rows, status, 0..) |row, *st, k| {
        st.* = classifyRow(roles, row);
        if (!st.used()) continue;
        var o: Obs = .{ .row = k, .time = row[r.time].num, .event = st.* == .event };
        if (roles.frequency) |c| o.freq = if (roles.notruncate) row[c].num else @trunc(row[c].num);
        if (roles.weight) |c| o.weight = row[c].num;
        try obs.append(a, o);
    }
    var levels: std.ArrayList([]const Value) = .empty;
    if (roles.strata.len > 0) {
        const sorted = try a.alloc([]const Value, obs.items.len);
        for (obs.items, sorted) |o, *s| s.* = rows[o.row];
        std.mem.sort([]const Value, sorted, roles.strata, levelLess);
        for (sorted) |row| if (levels.items.len == 0 or levelOrder(roles.strata, levels.items[levels.items.len - 1], row) != .eq) try levels.append(a, row);
        for (obs.items) |*o| {
            for (levels.items, 0..) |level, k| if (levelOrder(roles.strata, level, rows[o.row]) == .eq) {
                o.stratum = k;
            };
        }
    }
    return .{ .status = status, .obs = obs.items, .levels = levels.items };
}

fn classifyRow(roles: Roles, row: []const Value) Status {
    const r = roles.response.right;
    if (selection.missing(row[r.time])) return .{ .excluded = .missing_time };
    var event = true;
    if (r.censor) |c| {
        if (selection.missing(row[c])) return .{ .excluded = .missing_censor };
        event = std.mem.indexOfScalar(f64, r.censor_values, row[c].num) == null;
    }
    if (!roles.missing) for (roles.strata) |c| if (selection.missing(row[c])) return .{ .excluded = .missing_stratum };
    if (roles.frequency) |c| {
        if (selection.missing(row[c])) return .{ .excluded = .missing_frequency };
        const f = if (roles.notruncate) row[c].num else @trunc(row[c].num);
        if (!(f > 0)) return .{ .excluded = .nonpositive_frequency };
    }
    if (roles.weight) |c| if (selection.missing(row[c]) or !(row[c].num > 0)) return .{ .excluded = .nonpositive_weight };
    return if (event) .event else .right_censored;
}

/// One distinct observed time of a stratum. Counts are FREQ totals; the
/// `weighted_` fields are FREQ*WEIGHT totals. Censoring at a time tied with
/// events follows the events: an observation censored at `time` is still at
/// risk at `time`.
pub const RiskRow = struct {
    time: f64,
    at_risk: f64,
    events: f64,
    censored: f64,
    weighted_at_risk: f64,
    weighted_events: f64,
    weighted_censored: f64,
};
pub const RiskTable = struct {
    /// Ascending distinct times, including times with censoring only.
    rows: []const RiskRow,
    total: f64,
    events: f64,
    censored: f64,
};

fn obsLess(_: void, x: Obs, y: Obs) bool {
    return x.time < y.time;
}

/// Risk-set table of one stratum.
pub fn riskTable(a: A, obs: []const Obs, stratum: usize) !RiskTable {
    var members: std.ArrayList(Obs) = .empty;
    for (obs) |o| if (o.stratum == stratum) try members.append(a, o);
    std.mem.sort(Obs, members.items, {}, obsLess);
    var table: RiskTable = .{ .rows = &.{}, .total = 0, .events = 0, .censored = 0 };
    var weighted_total: f64 = 0;
    for (members.items) |o| {
        table.total += o.freq;
        weighted_total += o.freq * o.weight;
        if (o.event) table.events += o.freq else table.censored += o.freq;
    }
    var rows: std.ArrayList(RiskRow) = .empty;
    var left = table.total;
    var weighted_left = weighted_total;
    var i: usize = 0;
    while (i < members.items.len) {
        var row: RiskRow = .{ .time = members.items[i].time, .at_risk = left, .events = 0, .censored = 0, .weighted_at_risk = weighted_left, .weighted_events = 0, .weighted_censored = 0 };
        while (i < members.items.len and members.items[i].time == row.time) : (i += 1) {
            const o = members.items[i];
            if (o.event) {
                row.events += o.freq;
                row.weighted_events += o.freq * o.weight;
            } else {
                row.censored += o.freq;
                row.weighted_censored += o.freq * o.weight;
            }
        }
        left -= row.events + row.censored;
        weighted_left -= row.weighted_events + row.weighted_censored;
        try rows.append(a, row);
    }
    table.rows = rows.items;
    return table;
}

/// Risk-set tables of every stratum, in level order.
pub fn riskTables(a: A, c: Classified) ![]RiskTable {
    const tables = try a.alloc(RiskTable, c.strataCount());
    for (tables, 0..) |*t, k| t.* = try riskTable(a, c.obs, k);
    return tables;
}

test {
    _ = @import("survival_data_tests.zig");
}
