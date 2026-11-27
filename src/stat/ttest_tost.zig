//! TOST equivalence helpers (STAT-TTEST-009), S154 physical pp.10630-10631.
//! The option grammar/default bounds are on physical p.10613. Both tails use
//! alpha, overall p=max(p_lower,p_upper), and the test-based interval has level
//! 1-2*alpha. Ordinary 1-alpha intervals remain the caller's responsibility.
//! Difference inputs are on the original scale. Log-ratio estimates/SE are on
//! the natural-log scale; their bounds and displayed intervals are original-scale.
//! No shared parser/execution changes are required to test this module.
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const fit = @import("ttest_fit.zig");
const inference = @import("univ_inference.zig");
const format = @import("../format.zig");
const nan = std.math.nan(f64);
const inf = std.math.inf(f64);
const A = std.mem.Allocator;

pub const Scale = enum { difference, log_ratio };
pub const RawBounds = struct { lower: ?f64 = null, upper: f64, line: usize = 0 };
pub const Bounds = struct { lower: f64, upper: f64 };
pub const Test = struct { null_value: f64, t: f64, p: f64 };
pub const Result = struct {
    estimate: f64,
    se: f64,
    df: f64,
    bounds: Bounds,
    alpha: f64,
    scale: Scale,
    /// Right-tail test against lower bound, labeled "Upper" by SAS.
    lower_test: Test,
    /// Left-tail test against upper bound, labeled "Lower" by SAS.
    upper_test: Test,
    overall_p: f64,
    interval: fit.Interval,
    equivalent: bool,
    lower_contained: bool,
    upper_contained: bool,
};
pub const Row = struct {
    label: []const u8 = "",
    method: []const u8 = "",
    variances: []const u8 = "",
    result: Result,
};

fn bad(d: *diag.Diagnostics, line: usize) diag.Error {
    return d.fail(error.ParseError, line, "PROC TTEST: expected TOST(upper) or TOST(lower,upper) with finite numeric bounds", .{});
}
fn numeric(t: []const lex.Token, i: *usize, d: *diag.Diagnostics, line: usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (i.* < t.len and (t[i.*].tag == .minus or t[i.*].tag == .plus)) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (i.* >= t.len or t[i.*].tag != .number) return bad(d, line);
    const value = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return bad(d, line));
    if (!std.math.isFinite(value)) return bad(d, line);
    i.* += 1;
    return value;
}

/// index points to TOST; on success it points just past the closing parenthesis.
/// Do not resolve omitted lower bounds here: H0 may occur later in the header.
pub fn parseOption(t: []const lex.Token, index: *usize, d: *diag.Diagnostics) diag.Error!RawBounds {
    var i = index.*;
    const line = if (i < t.len) t[i].line else 0;
    if (i >= t.len or t[i].tag != .name or !std.ascii.eqlIgnoreCase(t[i].text, "tost")) return bad(d, line);
    i += 1;
    if (i >= t.len or t[i].tag != .lparen) return bad(d, line);
    i += 1;
    const first = try numeric(t, &i, d, line);
    var r: RawBounds = .{ .upper = first, .line = line };
    if (i < t.len and t[i].tag == .comma) {
        i += 1;
        r.lower = first;
        r.upper = try numeric(t, &i, d, line);
    }
    if (i >= t.len or t[i].tag != .rparen) return bad(d, line);
    index.* = i + 1;
    return r;
}

pub fn resolveBounds(raw: RawBounds, h0: f64, scale: Scale, d: *diag.Diagnostics) diag.Error!Bounds {
    if (!std.math.isFinite(h0) or !std.math.isFinite(raw.upper)) return bad(d, raw.line);
    const lower = raw.lower orelse switch (scale) {
        .difference => h0 + (h0 - raw.upper),
        .log_ratio => h0 / raw.upper,
    };
    if (scale == .log_ratio and (!(h0 > 0) or !(lower > 0) or !(raw.upper > 0)))
        return d.fail(error.ParseError, raw.line, "Equivalence bounds in the TOST option must be greater than zero for a test of a mean ratio or when lognormal data is assumed.", .{});
    if (!std.math.isFinite(lower) or !(lower < raw.upper))
        return d.fail(error.ParseError, raw.line, "Lower equivalence bound is greater than or equal to upper equivalence bound in TOST option.", .{});
    return .{ .lower = lower, .upper = raw.upper };
}

fn upperTail(t: f64, df: f64) f64 {
    // Student(1) is exactly Cauchy. Its elementary tail also preserves the
    // exact p=1/4 boundary at t=1 without an incomplete-beta rounding error.
    if (df == 1) return std.math.atan2(@as(f64, 1), t) / std.math.pi;
    return fit.tProbability(t, df, .upper);
}
fn critical(alpha: f64, df: f64) f64 {
    if (df == 1) {
        // cot(pi*alpha) is stable near zero; the centered tangent is stable
        // near alpha=1/2. This is a distribution identity, not a fitted value.
        if (alpha < 0.125) return 1 / @tan(std.math.pi * alpha);
        if (alpha > 0.875) return -1 / @tan(std.math.pi * (1 - alpha));
        return @tan(std.math.pi * (0.5 - alpha));
    }
    return -inference.tQuantile(alpha, df);
}
fn statistic(delta: f64, se: f64) f64 {
    if (se > 0) return delta / se;
    return if (delta == 0) nan else if (delta < 0) -inf else inf;
}

/// Generic arithmetic-difference or log-ratio TOST. Finite bounds and estimate,
/// nonnegative finite SE, positive DF, and 0<alpha<1 are required. SAS also
/// accepts alpha>=1/2: the displayed 1-2*alpha limits then coincide or reverse.
/// Boundary containment is inclusive, matching live SAS. A zero-SE statistic
/// with a zero numerator remains missing; overall p remains missing if either
/// constituent test is missing, while interval assessment is still explicit.
pub fn evaluate(estimate: f64, se: f64, df: f64, bounds: Bounds, alpha: f64, scale: Scale) diag.Error!Result {
    if (!std.math.isFinite(estimate) or !std.math.isFinite(se) or se < 0 or !std.math.isFinite(df) or !(df > 0) or
        !std.math.isFinite(bounds.lower) or !std.math.isFinite(bounds.upper) or !(bounds.lower < bounds.upper) or !(alpha > 0 and alpha < 1)) return error.ExecError;
    if (scale == .log_ratio and !(bounds.lower > 0)) return error.ExecError;
    const lo = if (scale == .log_ratio) @log(bounds.lower) else bounds.lower;
    const hi = if (scale == .log_ratio) @log(bounds.upper) else bounds.upper;
    const delta_lo = estimate - lo;
    const delta_hi = estimate - hi;
    if (!std.math.isFinite(delta_lo) or !std.math.isFinite(delta_hi)) return error.ExecError;
    const tl = statistic(delta_lo, se);
    const tu = statistic(delta_hi, se);
    const pl = upperTail(tl, df);
    const pu = upperTail(-tu, df);
    const margin = critical(alpha, df) * se;
    const lower = estimate - margin;
    const upper = estimate + margin;
    if (!std.math.isFinite(lower) or !std.math.isFinite(upper)) return error.ExecError;
    var interval: fit.Interval = .{ .lower = lower, .upper = upper };
    var displayed = estimate;
    if (scale == .log_ratio) {
        displayed = @exp(estimate);
        interval = .{ .lower = @exp(lower), .upper = @exp(upper) };
        if (!(displayed > 0) or !std.math.isFinite(displayed) or !std.math.isFinite(interval.upper)) return error.ExecError;
    }
    return .{
        .estimate = displayed,
        .se = se,
        .df = df,
        .bounds = bounds,
        .alpha = alpha,
        .scale = scale,
        .lower_test = .{ .null_value = bounds.lower, .t = tl, .p = pl },
        .upper_test = .{ .null_value = bounds.upper, .t = tu, .p = pu },
        .overall_p = if (std.math.isNan(pl) or std.math.isNan(pu)) nan else @max(pl, pu),
        .interval = interval,
        .equivalent = lower >= lo and upper <= hi,
        .lower_contained = lower >= lo,
        .upper_contained = upper <= hi,
    };
}

fn num(a: A, value: f64, spec: []const u8) diag.Error![]const u8 {
    if (std.math.isInf(value)) return if (value < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}

/// class_name=null for one-sample/paired rows; otherwise include CLASS/Method.
/// The caller keeps ordinary Statistics/ConfLimits and replaces only TTests,
/// adding this table with ODS name EquivLimits before EquivTests (p.10644).
pub fn renderAssessment(a: A, out: *std.ArrayList(u8), rows: []const Row, class_name: ?[]const u8) diag.Error!void {
    if (rows.len == 0) return;
    const first = rows[0].result;
    try out.print(a, "TOST Level {s} Equivalence Analysis\n\n", .{try num(a, first.alpha, "best8.")});
    if (first.scale == .log_ratio) try out.appendSlice(a, "Geometric ");
    try out.appendSlice(a, "Lower Upper\n");
    if (class_name) |name| try out.print(a, "{s} Method ", .{name});
    // SAS rounds the displayed percentage with INT(level+0.5), including the
    // degenerate negative-level display when it accepts alpha>1/2.
    const level = @trunc(100 * (1 - 2 * first.alpha) + 0.5);
    try out.print(a, "Mean Bound {s}% CL Mean Bound Assessment\n\n", .{try num(a, level, "best8.")});
    for (rows) |row| {
        const r = row.result;
        if (class_name != null) try out.print(a, "{s} {s} ", .{ row.label, row.method });
        try out.print(a, "{s} {s} {s} {s} {s} {s} {s} {s}\n", .{
            try num(a, r.estimate, "d8.3"),                       try num(a, r.bounds.lower, "best8."),
            if (r.lower_contained) @as([]const u8, "<") else ">", try num(a, r.interval.lower, "d8.3"),
            try num(a, r.interval.upper, "d8.3"),                 if (r.upper_contained) @as([]const u8, "<") else ">",
            try num(a, r.bounds.upper, "best8."),                 if (r.equivalent) @as([]const u8, "Equivalent") else "Not equivalent",
        });
    }
    try out.appendSlice(a, "\n");
}

pub fn renderTests(a: A, out: *std.ArrayList(u8), rows: []const Row, class_name: ?[]const u8) diag.Error!void {
    if (class_name != null) try out.appendSlice(a, "Method Variances ");
    try out.appendSlice(a, "Test Null DF t Value P-Value\n\n");
    for (rows) |row| {
        const r = row.result;
        for ([_]Test{ r.lower_test, r.upper_test }, [_][]const u8{ "Upper", "Lower" }) |t, label| {
            if (class_name != null) try out.print(a, "{s} {s} ", .{ row.method, row.variances });
            try out.print(a, "{s} {s} {s} {s} {s}\n", .{ label, try num(a, t.null_value, "best8."), try num(a, r.df, "best6."), try num(a, t.t, "8.2"), try num(a, t.p, "pvalue6.4") });
        }
        if (class_name != null) try out.print(a, "{s} {s} ", .{ row.method, row.variances });
        try out.print(a, "Overall {s}\n", .{try num(a, r.overall_p, "pvalue6.4")});
    }
    try out.appendSlice(a, "\n");
}

/// Ordinary lognormal tables without the ordinary t test, for a TOST hook.
/// These keep existing table identities without editing ttest_lognormal's API.
pub fn renderLognormalStatistics(a: A, out: *std.ArrayList(u8), r: @import("ttest_lognormal.zig").Result) diag.Error!void {
    try out.appendSlice(a, "Geometric Coefficient\nN Mean of Variation Minimum Maximum\n");
    try out.print(a, "{s} {s} {s} {s} {s}\n\n", .{
        try num(a, @floatFromInt(r.log_fit.n), "best12."), try num(a, r.geometric_mean, "d8.3"),
        try num(a, r.cv, "d8.3"),                          try num(a, r.minimum, "d8.3"),
        try num(a, r.maximum, "d8.3"),
    });
}

pub fn renderLognormalIntervals(a: A, out: *std.ArrayList(u8), r: @import("ttest_lognormal.zig").Result, alpha: f64, show_cv_ci: bool) diag.Error!void {
    const level = try num(a, 100 * (1 - alpha), "best8.");
    try out.print(a, "Geometric Coefficient\nMean {s}% CL Mean of Variation", .{level});
    if (show_cv_ci) try out.print(a, " {s}% CL CV", .{level});
    try out.print(a, "\n{s} {s} {s} {s}", .{
        try num(a, r.geometric_mean, "d8.3"), try num(a, r.mean_ci.lower, "d8.3"),
        try num(a, r.mean_ci.upper, "d8.3"),  try num(a, r.cv, "d8.3"),
    });
    if (show_cv_ci) try out.print(a, " {s} {s}", .{ try num(a, r.cv_ci.lower, "d8.3"), try num(a, r.cv_ci.upper, "d8.3") });
    try out.appendSlice(a, "\n\n");
}

test "TOST009 full unchanged difference oracle tables" {
    const two = @import("ttest_two_sample.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try fit.oneSample(&.{ 43, 90, 84, 87, 116, 95 }, null, null, .{});
    const second = try fit.oneSample(&.{ 86, 99, 93, 92, 121, 71 }, null, null, .{});
    const pair = try two.compute(first, second, .{});
    const bounds: Bounds = .{ .lower = -20, .upper = 20 };
    const rows = [_]Row{
        .{ .label = "Diff (1-2)", .method = "Pooled", .variances = "Equal", .result = try evaluate(pair.pooled.estimate, pair.pooled.std_err, pair.pooled.df, bounds, 0.05, .difference) },
        .{ .label = "Diff (1-2)", .method = "Satterthwaite", .variances = "Unequal", .result = try evaluate(pair.satterthwaite.estimate, pair.satterthwaite.std_err, pair.satterthwaite.df, bounds, 0.05, .difference) },
    };
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "The TTEST Procedure\n\nVariable: x\n\n");
    try two.statistics(a, &out, pair, "group", .{ "A", "B" }, false);
    try two.intervals(a, &out, pair, "group", .{ "A", "B" }, true);
    try renderAssessment(a, &out, &rows, "group");
    try renderTests(a, &out, &rows, "group");
    try two.equalityTable(a, &out, pair);
    const expected = try @import("ttest_test_assets.zig").listing(a, "tests/corpus/persist_ttest_tost_difference.txt");
    var e = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
    var got = std.mem.tokenizeAny(u8, out.items, " \r\n\t\x0c");
    while (e.next()) |word| try std.testing.expectEqualStrings(word, got.next() orelse "<missing>");
    try std.testing.expect(got.next() == null);
    for (rows) |row| {
        try std.testing.expectEqual(@max(row.result.lower_test.p, row.result.upper_test.p), row.result.overall_p);
        try std.testing.expect(!row.result.equivalent);
    }
}

test "TOST009 independent Cauchy exact boundary both sides and alpha" {
    // (-1,1) has mean=0, SE=1, df=1. Student(1) is Cauchy, so
    // P(T>1)=P(T<-1)=1/4 and the 50% interval is [-1,1].
    const r = try evaluate(0, 1, 1, .{ .lower = -1, .upper = 1 }, 0.25, .difference);
    try std.testing.expectEqual(@as(f64, 1), r.lower_test.t);
    try std.testing.expectEqual(@as(f64, -1), r.upper_test.t);
    try std.testing.expectEqual(@as(f64, 0.25), r.lower_test.p);
    try std.testing.expectEqual(@as(f64, 0.25), r.upper_test.p);
    try std.testing.expectEqual(@as(f64, 0.25), r.overall_p);
    try std.testing.expectApproxEqAbs(@as(f64, -1), r.interval.lower, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.interval.upper, 1e-14);
    try std.testing.expect(r.equivalent);
    const tighter = try evaluate(0, 1, 1, .{ .lower = -0.999, .upper = 1 }, 0.25, .difference);
    try std.testing.expect(!tighter.equivalent and tighter.overall_p > 0.25);
    const wider = try evaluate(0, 1, 1, .{ .lower = -1.001, .upper = 1.001 }, 0.25, .difference);
    try std.testing.expect(wider.equivalent and wider.overall_p < 0.25);
    const narrower_alpha = try evaluate(0, 1, 1, .{ .lower = -1, .upper = 1 }, 0.05, .difference);
    try std.testing.expect(!narrower_alpha.equivalent);
    try std.testing.expectApproxEqAbs(1 / @tan(@as(f64, std.math.pi * 0.05)), narrower_alpha.interval.upper, 1e-13);
    // Exact interval endpoints, not rounded printed numbers, determine containment.
    const endpoints = try evaluate(0, 1, 1, .{ .lower = r.interval.lower, .upper = r.interval.upper }, 0.25, .difference);
    try std.testing.expect(endpoints.equivalent);
}

test "TOST009 independent Student2 log-ratio identities and original-scale bounds" {
    const bounds: Bounds = .{ .lower = 0.8, .upper = 1.25 };
    const se = @sqrt(@as(f64, 0.01 / 3.0)); // logs=(-0.1,0,0.1)
    const r = try evaluate(0, se, 2, bounds, 0.05, .log_ratio);
    try std.testing.expectEqual(@as(f64, 1), r.estimate);
    const t = -@log(@as(f64, 0.8)) / se;
    const expected_p = 0.5 * (1 - t / @sqrt(t * t + 2));
    try std.testing.expectApproxEqAbs(expected_p, r.lower_test.p, 1e-13);
    try std.testing.expectApproxEqAbs(expected_p, r.upper_test.p, 1e-13);
    // Student(2) quantile at .95: sqrt(2)*.9/sqrt(1-.9^2).
    const critical_t = @sqrt(@as(f64, 2)) * 0.9 / @sqrt(@as(f64, 1 - 0.9 * 0.9));
    try std.testing.expectApproxEqAbs(@exp(-critical_t * se), r.interval.lower, 1e-12);
    try std.testing.expectApproxEqAbs(@exp(critical_t * se), r.interval.upper, 1e-12);
    try std.testing.expect(r.equivalent);
    const shifted = try evaluate(@log(@as(f64, 10)), se, 2, .{ .lower = 8, .upper = 12.5 }, 0.05, .log_ratio);
    try std.testing.expectApproxEqAbs(r.overall_p, shifted.overall_p, 1e-13);
    try std.testing.expectApproxEqAbs(10 * r.interval.lower, shifted.interval.lower, 1e-12);
    const reflected = try evaluate(0, se, 2, .{ .lower = 1.0 / 1.25, .upper = 1.0 / 0.8 }, 0.05, .log_ratio);
    try std.testing.expectApproxEqAbs(r.overall_p, reflected.overall_p, 1e-13);
}

test "TOST009 parser signed bounds delayed H0 defaults ratio defaults and errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try lex.tokenize(a, "tost(-2e1,+20) alpha=.05;", &d);
    var index: usize = 0;
    const raw = try parseOption(tokens, &index, &d);
    try std.testing.expectEqual(@as(?f64, -20), raw.lower);
    try std.testing.expectEqual(@as(f64, 20), raw.upper);
    try std.testing.expectEqualStrings("alpha", tokens[index].text);
    try std.testing.expectEqual(Bounds{ .lower = -20, .upper = 20 }, try resolveBounds(raw, 999, .difference, &d));
    index = 0;
    const omitted = try parseOption(try lex.tokenize(a, "TOST(2) h0=1;", &d), &index, &d);
    try std.testing.expectEqual(Bounds{ .lower = 0, .upper = 2 }, try resolveBounds(omitted, 1, .difference, &d));
    const ratio = try resolveBounds(.{ .upper = 1.5 }, 1.2, .log_ratio, &d);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), ratio.lower, 1e-14);
    for ([_][]const u8{ "tost()", "tost(,2)", "tost(-2,)", "tost(1,2,3)", "tost(a,2)", "tost(2" }) |source| {
        var errors = diag.Diagnostics.init(a);
        index = 0;
        try std.testing.expectError(error.ParseError, parseOption(try lex.tokenize(a, source, &errors), &index, &errors));
        try std.testing.expect(errors.hasErrors());
        try std.testing.expect(errors.list.items[0].line > 0);
    }
    try std.testing.expectError(error.ParseError, resolveBounds(.{ .lower = 1, .upper = 1 }, 0, .difference, &d));
    try std.testing.expectError(error.ParseError, resolveBounds(.{ .lower = 2, .upper = 1 }, 0, .difference, &d));
    try std.testing.expectError(error.ParseError, resolveBounds(.{ .lower = 0, .upper = 2 }, 1, .log_ratio, &d));
}

test "TOST009 zero SE missing tests validation and reflection" {
    const inside = try evaluate(0, 0, 2, .{ .lower = -1, .upper = 1 }, 0.05, .difference);
    try std.testing.expectEqual(@as(f64, 0), inside.overall_p);
    try std.testing.expect(inside.equivalent);
    const boundary = try evaluate(0, 0, 2, .{ .lower = 0, .upper = 1 }, 0.05, .difference);
    try std.testing.expect(std.math.isNan(boundary.lower_test.p));
    try std.testing.expect(std.math.isNan(boundary.overall_p));
    try std.testing.expect(boundary.equivalent); // live SAS: collapsed interval is contained
    const outside = try evaluate(2, 0, 2, .{ .lower = 0, .upper = 1 }, 0.05, .difference);
    try std.testing.expectEqual(@as(f64, 1), outside.overall_p);
    try std.testing.expect(!outside.equivalent);
    const r = try evaluate(0.3, 0.7, 8, .{ .lower = -1, .upper = 2 }, 0.05, .difference);
    const mirror = try evaluate(-0.3, 0.7, 8, .{ .lower = -2, .upper = 1 }, 0.05, .difference);
    try std.testing.expectApproxEqAbs(r.lower_test.p, mirror.upper_test.p, 1e-14);
    try std.testing.expectApproxEqAbs(r.overall_p, mirror.overall_p, 1e-14);
    try std.testing.expectError(error.ExecError, evaluate(0, 1, 0, .{ .lower = -1, .upper = 1 }, 0.05, .difference));
    try std.testing.expectError(error.ExecError, evaluate(0, -1, 2, .{ .lower = -1, .upper = 1 }, 0.05, .difference));
    try std.testing.expectError(error.ExecError, evaluate(0, 1, 2, .{ .lower = -1, .upper = 1 }, 0, .difference));
    try std.testing.expectError(error.ExecError, evaluate(0, 1, 2, .{ .lower = 0, .upper = 1 }, 0.05, .log_ratio));
    try std.testing.expectError(error.ExecError, evaluate(inf, 1, 2, .{ .lower = -1, .upper = 1 }, 0.05, .difference));
}
