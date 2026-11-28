//! PROC LIFETEST life-table (actuarial) method and the Breslow and
//! Fleming-Harrington survivor estimates, SAS/STAT 15.4 physical pp.5671 and
//! 5674-5676. The listing is produced only in the shape proven against the SAS
//! reference (single sample, integer interval endpoints, integer counts);
//! every other shape is a D-009 gap raised before any text is written.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const format = @import("../format.zig");
const survival = @import("survival_data.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
pub const Obs = survival.Obs;

/// One interval [lower, upper); `upper == null` is the open last interval.
/// `survival` and its standard error are the estimates at `lower`. A null
/// quantity is one the printed formula leaves undefined (division by zero or
/// an infinite width), never a silent zero.
pub const Interval = struct {
    lower: f64,
    upper: ?f64,
    entering: f64 = 0,
    failed: f64 = 0,
    censored: f64 = 0,
    effective: f64 = 0,
    q: ?f64 = null,
    q_se: ?f64 = null,
    survival: f64 = 1,
    survival_se: ?f64 = null,
    median: ?f64 = null,
    median_se: ?f64 = null,
    pdf: ?f64 = null,
    pdf_se: ?f64 = null,
    hazard: ?f64 = null,
    hazard_se: ?f64 = null,
};
pub const Table = struct {
    rows: []Interval,
    total: f64 = 0,
    failed: f64 = 0,
    censored: f64 = 0,
    /// A situation whose result the specification does not settle.
    unverified: ?[]const u8 = null,
};

/// Life table over the intervals that start at `endpoints` (ascending, first
/// 0). An observation exactly on an endpoint belongs to the interval that
/// starts there; FREQ totals are the counts.
pub fn lifeTable(a: A, obs: []const Obs, endpoints: []const f64) !Table {
    const rows = try a.alloc(Interval, endpoints.len);
    for (rows, 0..) |*r, i| r.* = .{ .lower = endpoints[i], .upper = if (i + 1 < endpoints.len) endpoints[i + 1] else null };
    var table: Table = .{ .rows = rows };
    for (obs) |o| {
        if (o.time < endpoints[0]) {
            table.unverified = "a time below the first interval";
            continue;
        }
        var index: usize = 0;
        for (endpoints, 0..) |e, i| {
            if (o.time >= e) index = i;
        }
        table.total += o.freq;
        if (o.event) {
            rows[index].failed += o.freq;
            table.failed += o.freq;
        } else {
            rows[index].censored += o.freq;
            table.censored += o.freq;
        }
    }
    var n = table.total;
    var s: f64 = 1;
    // Sum of q/(n'p) over the earlier intervals; null once an interval has p = 0.
    var acc: ?f64 = 0;
    for (rows) |*r| {
        r.entering = n;
        r.effective = n - r.censored / 2;
        r.survival = s;
        r.survival_se = if (acc) |v| s * @sqrt(v) else null;
        if (r.effective > 0) {
            const q = r.failed / r.effective;
            const p = 1 - q;
            r.q = q;
            r.q_se = @sqrt(q * p / r.effective);
            if (r.upper) |upper| {
                const b = upper - r.lower;
                const h = 2 * q / (b * (1 + p));
                r.pdf = s * q / b;
                r.hazard = h;
                if (q > 0) {
                    if (acc) |v| r.pdf_se = r.pdf.? * @sqrt(v + p / (r.effective * q));
                    r.hazard_se = h * @sqrt((1 - (b * h / 2) * (b * h / 2)) / (r.effective * q));
                }
            }
            if (p > 0) {
                if (acc) |v| acc = v + q / (r.effective * p);
            } else acc = null;
            s *= p;
        } else if (table.unverified == null) {
            table.unverified = "an interval that no unit enters";
        }
        n -= r.failed + r.censored;
    }
    // ponytail: the bracketing interval is found by floating comparison; a
    // survival estimate exactly equal to half an earlier one is decided by
    // rounding of the cumulative product.
    for (rows, 0..) |*r, i| {
        if (!(r.survival > 0)) continue;
        const half = r.survival / 2;
        var j = i;
        while (j + 1 < rows.len) : (j += 1) {
            if (rows[j].survival >= half and half > rows[j + 1].survival) {
                const b = rows[j].upper.? - rows[j].lower;
                r.median = rows[j].lower - r.lower + b * (rows[j].survival - half) / (rows[j].survival - rows[j + 1].survival);
                if (rows[j].pdf) |f| {
                    if (f > 0 and r.effective > 0) r.median_se = r.survival / (2 * f * @sqrt(r.effective));
                }
                break;
            }
        }
    }
    return table;
}

/// Default interval width, physical p.5676: 2, 5 or 10 times a power of 10.
/// ponytail: d is compared with 2 and 5 after a relative 1e-12 allowance so
/// that a ratio that is exactly 2 or 5 times a power of 10 is not pushed over
/// the boundary by the rounding of log10/pow.
pub fn defaultWidth(max_time: f64, intervals: f64) f64 {
    const c = @log10(max_time / intervals);
    const b = @floor(c);
    const d = std.math.pow(f64, 10, c - b);
    const m: f64 = if (d <= 2 * (1 + 1e-12)) 2 else if (d <= 5 * (1 + 1e-12)) 5 else 10;
    return m * std.math.pow(f64, 10, b);
}

pub const Estimate = struct { time: f64, survival: f64 };

/// Breslow estimate exp(-sum d/Y) at each distinct event time, p.5671.
pub fn breslow(a: A, table: survival.RiskTable) ![]Estimate {
    var list: std.ArrayList(Estimate) = .empty;
    var hazard: f64 = 0;
    for (table.rows) |row| {
        if (!(row.events > 0)) continue;
        hazard += row.events / row.at_risk;
        try list.append(a, .{ .time = row.time, .survival = @exp(-hazard) });
    }
    return list.items;
}

/// Fleming-Harrington estimate exp(-sum_k sum_{j<d_k} 1/(Y_k - j)), p.5671;
/// null when a number of events is not an integer (not computable).
pub fn flemingHarrington(a: A, table: survival.RiskTable) !?[]Estimate {
    var list: std.ArrayList(Estimate) = .empty;
    var hazard: f64 = 0;
    for (table.rows) |row| {
        if (!(row.events > 0)) continue;
        if (row.events != @floor(row.events) or row.at_risk != @floor(row.at_risk)) return null;
        var j: f64 = 0;
        while (j < row.events) : (j += 1) hazard += 1 / (row.at_risk - j);
        try list.append(a, .{ .time = row.time, .survival = @exp(-hazard) });
    }
    return list.items;
}

fn gap(cx: proc.ProcCtx, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, 0, "PROC LIFETEST: " ++ text, args);
}
fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn cell(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn whole(cx: proc.ProcCtx, x: f64, what: []const u8) diag.Error![]const u8 {
    if (x != @floor(x) or x < 0 or x >= 1e7) return gap(cx, "life-table display of a {s} that is not an integer below 1E7 is not verified", .{what});
    return std.fmt.allocPrint(cx.arena, "{d}", .{@as(u64, @intFromFloat(x))});
}
/// Probabilities: exact 0 prints as 0, otherwise four decimals.
fn prob(a: A, x: f64) ![]const u8 {
    return if (x == 0) "0" else fixed(a, x, 4);
}
/// Standard errors print three significant digits in the reference. Only
/// the magnitudes 0 and [0.001, 0.1) without a trailing zero are evidenced.
fn se3(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    if (x == 0) return "0";
    if (!(x >= 0.001 and x < 0.1)) return gap(cx, "life-table standard error display outside [0.001, 0.1) is not verified", .{});
    const text = try fixed(cx.arena, x, if (x < 0.01) 5 else 4);
    if (text[text.len - 1] == '0') return gap(cx, "life-table standard error display with a trailing zero is not verified", .{});
    return text;
}

const head_estimates =
    \\                                                     Life Table Survival Estimates
    \\ 
    \\                                                                    Conditional
    \\                                          Effective   Conditional   Probability                         Survival    Median     Median
    \\      Interval        Number    Number      Sample    Probability     Standard                          Standard   Residual   Standard
    \\ [Lower,     Upper)   Failed   Censored      Size     of Failure        Error     Survival   Failure     Error     Lifetime    Error
    \\
;
const head_midpoint =
    \\                      Evaluated at the Midpoint of the Interval
    \\ 
    \\                                   PDF                  Hazard
    \\      Interval                   Standard              Standard
    \\ [Lower,     Upper)     PDF       Error      Hazard     Error
    \\
;
const head_summary =
    \\Summary of the Number of Censored and Uncensored Values
    \\ 
    \\                                 Percent
    \\   Total  Failed    Censored    Censored
    \\
;

/// The life-table listing of one sample: estimates, midpoint densities and
/// hazards, censoring summary and the deleted-observation note.
pub fn render(cx: proc.ProcCtx, out: *Out, obs: []const Obs, endpoints: []const f64, read: usize) diag.Error!void {
    const a = cx.arena;
    if (obs.len == 0) return gap(cx, "the result for an input without usable observations is not verified", .{});
    const table = try lifeTable(a, obs, endpoints);
    if (table.unverified) |reason| return gap(cx, "the life table for {s} is not verified", .{reason});
    var body: Out = .empty;
    try body.appendSlice(a, "\nThe LIFETEST Procedure\n\n" ++ head_estimates ++ "\n");
    for (table.rows) |r| {
        try cell(a, &body, try whole(cx, r.lower, "interval endpoint"), 8);
        try cell(a, &body, if (r.upper) |u| try whole(cx, u, "interval endpoint") else ".", 11);
        try cell(a, &body, try whole(cx, r.failed, "count"), 8);
        try cell(a, &body, try whole(cx, r.censored, "count"), 10);
        try cell(a, &body, try fixed(a, r.effective, 1), 12);
        try cell(a, &body, try prob(a, r.q.?), 14);
        try cell(a, &body, try se3(cx, r.q_se.?), 14);
        try cell(a, &body, try prob(a, r.survival), 13);
        try cell(a, &body, try prob(a, 1 - r.survival), 11);
        try cell(a, &body, try se3(cx, r.survival_se orelse return gap(cx, "the life table after an interval in which every unit fails is not verified", .{})), 11);
        if (r.median != null and r.median_se == null) return gap(cx, "a median residual lifetime without a standard error is not verified", .{});
        if (r.median) |m| {
            if (!(m >= 0 and m < 100)) return gap(cx, "median residual lifetime display outside [0, 100) is not verified", .{});
        }
        try cell(a, &body, if (r.median) |m| try fixed(a, m, 4) else ".", 11);
        try cell(a, &body, if (r.median_se) |m| try fixed(a, m, 4) else ".", 11);
        try body.append(a, '\n');
    }
    try body.appendSlice(a, "\n" ++ head_midpoint ++ "\n");
    for (table.rows) |r| {
        try cell(a, &body, try whole(cx, r.lower, "interval endpoint"), 8);
        try cell(a, &body, if (r.upper) |u| try whole(cx, u, "interval endpoint") else ".", 11);
        if (r.upper == null) {
            try body.appendSlice(a, "          .          .          .          .\n");
            continue;
        }
        const pdf_se = r.pdf_se orelse return gap(cx, "density and hazard display for a bounded interval without failures is not verified", .{});
        const hazard_se = r.hazard_se orelse return gap(cx, "density and hazard display for a bounded interval without failures is not verified", .{});
        try cell(a, &body, try fixed(a, r.pdf.?, 4), 11);
        try cell(a, &body, try se3(cx, pdf_se), 11);
        try cell(a, &body, try format.bestNumW(a, r.hazard.?, 8), 11);
        try cell(a, &body, try format.bestNumW(a, hazard_se, 8), 11);
        try body.append(a, '\n');
    }
    try body.appendSlice(a, "\n\n" ++ head_summary ++ "\n");
    try cell(a, &body, try whole(cx, table.total, "count"), 8);
    try cell(a, &body, try whole(cx, table.failed, "count"), 8);
    try cell(a, &body, try whole(cx, table.censored, "count"), 12);
    try cell(a, &body, try fixed(a, 100 * table.censored / table.total, 2), 12);
    try body.append(a, '\n');
    const deleted = read - obs.len;
    // The reference shows the plural wording only.
    if (deleted == 1) return gap(cx, "the wording of the note for a single deleted observation is not verified", .{});
    if (deleted > 0) {
        try body.print(a, "\nNOTE: {d} observations with invalid time, censoring, or frequency values were deleted.\n", .{deleted});
        try cx.diags.note(0, "{d} observations with invalid time, censoring, or frequency values were deleted.", .{deleted});
    }
    try cx.diags.note(0, "The LOGLOG transform is used to compute the confidence limits for the quartiles of the survivor distribution. To suppress using this transform, specify CONFTYPE=LINEAR in the PROC LIFETEST statement.", .{});
    try out.appendSlice(a, body.items);
}
