//! PROC ANOVA MODEL / EFFECTSIZE (STAT-ANOVA-003; S154 p.1129, measures
//! defined in GLM "Effect Size Measures for F Tests", physical pp.4120–4122).
//! Noncentral-F inversion is glm_effectsize.zig's (read-only reuse); the
//! formulas are applied here because ANOVA also prints them where that
//! kernel's domain stops (Low MSE `.` for DFE <= 4, `.` without error DF).
//!
//! Display rules, all from SAS 9.4 reference runs on invented data
//! (2026-11-28, 40 random BY groups plus targeted cases):
//! - Overall block: estimates and limits in BEST6., proportions in 2 decimals.
//! - Noncentrality columns of the effect table share one decimal count per
//!   column: the largest count any value needs to show 3 significant digits
//!   with trailing zeros dropped (659.28 / 46.44 / 6.39; 2395 / 181 / 43).
//! - Variation table: 4 decimals; the intercept has no semipartial measures.
//! ponytail: zero error mean square (`Infty`/`In` cells), noncentrality
//! beyond the kernel's validated range and values needing E notation are
//! loud D-009 gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const kernel = @import("glm_effectsize.zig");
const Table = @import("anova.zig").Table;
const A = std.mem.Allocator;
const nan = std.math.nan(f64);
const inf = std.math.inf(f64);
const alpha: f64 = 0.05;

pub const Kind = enum { effect, intercept, intercept_only, overall };
pub const Sizes = struct {
    mvue: f64 = nan,
    low_mse: f64 = nan,
    lcl: f64 = nan,
    ucl: f64 = nan,
    semi_eta: f64 = nan,
    semi_omega: f64 = nan,
    semi_lcl: f64 = nan,
    semi_ucl: f64 = nan,
    eta: f64 = nan,
    omega: f64 = nan,
    partial_lcl: f64 = nan,
    partial_ucl: f64 = nan,
};

fn gap(cx: proc.ProcCtx, comptime what: []const u8) diag.Error {
    return proc.failGap(cx.diags, 0, "PROC ANOVA: EFFECTSIZE " ++ what ++ " is not implemented", .{});
}

fn interval(cx: proc.ProcCtx, f: f64, df: f64, dfe: f64) diag.Error![2]f64 {
    return .{ try limit(cx, f, df, dfe, 1 - alpha / 2), try limit(cx, f, df, dfe, alpha / 2) };
}

/// The shared kernel validates NC <= 1000; beyond it (an INT intercept test
/// reaches 2395 in a SAS reference run) the same Poisson mixture is summed
/// outward from its mode in log space, up to NC = 1E6. Larger is a gap
/// (SAS itself prints `.` for an F of 3E10).
fn limit(cx: proc.ProcCtx, f: f64, df: f64, dfe: f64, p: f64) diag.Error!f64 {
    if (kernel.noncentrality(f, df, dfe, p)) |nc| return nc else |_| {}
    if (!std.math.isFinite(f) or f < 0) return gap(cx, "with a noncentrality beyond the validated range");
    if (wideCdf(f, df, dfe, 1000) > p) {
        var lo: f64 = 1000;
        var hi: f64 = 2000;
        while (wideCdf(f, df, dfe, hi) > p) {
            if (hi >= 1e6) return gap(cx, "with a noncentrality beyond the validated range");
            lo = hi;
            hi *= 2;
        }
        for (0..200) |_| {
            const mid = lo + (hi - lo) / 2;
            if (wideCdf(f, df, dfe, mid) > p) lo = mid else hi = mid;
            if (hi - lo <= 2e-12 * hi) return lo + (hi - lo) / 2;
        }
    }
    return gap(cx, "with a noncentrality beyond the validated range");
}

/// Noncentral F CDF as the Poisson(NC/2) mixture of I_z(df/2+j, dfe/2),
/// summed from the mode outward until a term is below 1E-16 of the sum.
pub fn wideCdf(x: f64, df: f64, dfe: f64, nc: f64) f64 {
    const fns = @import("../functions.zig");
    const z = df * x / (df * x + dfe);
    const lambda = nc / 2;
    const mode = @floor(lambda);
    const logw = struct {
        fn of(j: f64, l: f64) f64 {
            return -l + j * @log(l) - fns.lgammaOf(j + 1);
        }
    }.of;
    var sum: f64 = 0;
    var j = mode;
    while (j >= 0) : (j -= 1) {
        const term = @exp(logw(j, lambda)) * fns.betaI(z, df / 2 + j, dfe / 2);
        sum += term;
        if (j < mode - 10 and @exp(logw(j, lambda)) < 1e-17) break;
    }
    j = mode + 1;
    while (true) : (j += 1) {
        const w = @exp(logw(j, lambda));
        sum += w * fns.betaI(z, df / 2 + j, dfe / 2);
        if (j > mode + 10 and w < 1e-17) break;
    }
    return @min(1, sum);
}

/// Measures of one F test with `ss` on `df` against the ANOVA error term.
/// `.intercept_only`: the semipartial total is the uncorrected one and the
/// conservative limits equal the partial ones (SAS reference, model y= ).
pub fn row(cx: proc.ProcCtx, t: Table, ss: f64, df: f64, kind: Kind) diag.Error!Sizes {
    if (t.error_df == 0 or df == 0) return .{};
    const dfe = t.error_df;
    const mse = t.sse / dfe;
    const n = t.n;
    if (!(mse > 0)) {
        // SAS reference (incomplete blocks, Error SS 0): estimates `.`,
        // limits Infty, partial measures 1; semipartial ones as usual.
        if (!(ss > 0)) return gap(cx, "with a zero effect and a zero error mean square");
        var z: Sizes = .{ .lcl = inf, .ucl = inf, .eta = 1, .omega = 1, .partial_lcl = 1, .partial_ucl = 1 };
        if (kind == .overall) return z;
        if (kind != .effect) return gap(cx, "for the intercept with a zero error mean square");
        z.semi_eta = ss / t.total;
        z.semi_omega = ss / t.total;
        const reduced_dfe = n - df - 1;
        if (!(t.total - ss > 0) or !(reduced_dfe > 0)) return gap(cx, "conservative limits without residual variation");
        const reduced = try interval(cx, (ss / df) / ((t.total - ss) / reduced_dfe), df, reduced_dfe);
        z.semi_lcl = reduced[0] / (reduced[0] + n);
        z.semi_ucl = reduced[1] / (reduced[1] + n);
        return z;
    }
    const f = ss / df / mse;
    const nc = try interval(cx, f, df, dfe);
    var s: Sizes = .{
        .mvue = df * (dfe - 2) * f / dfe - df,
        .low_mse = if (dfe > 4) df * (dfe - 4) * f / dfe - df * (dfe - 4) / (dfe - 2) else nan,
        .lcl = nc[0],
        .ucl = nc[1],
        .eta = ss / (ss + t.sse),
        .omega = (ss - df * mse) / (ss + (n - df) * mse),
        .partial_lcl = nc[0] / (nc[0] + n),
        .partial_ucl = nc[1] / (nc[1] + n),
    };
    if (kind == .intercept or kind == .overall) return s;
    const total = if (kind == .intercept_only) t.uss else t.total;
    s.semi_eta = ss / total;
    s.semi_omega = (ss - df * mse) / (total + mse);
    if (kind == .intercept_only) {
        s.semi_lcl = s.partial_lcl;
        s.semi_ucl = s.partial_ucl;
        return s;
    }
    // Conservative limits: reduced ANOVA with SSE = total - SS on N-DF-1.
    const reduced_dfe = n - df - 1;
    if (!(total - ss > 0) or !(reduced_dfe > 0)) return gap(cx, "conservative limits without residual variation");
    const reduced = try interval(cx, (ss / df) / ((total - ss) / reduced_dfe), df, reduced_dfe);
    s.semi_lcl = reduced[0] / (reduced[0] + n);
    s.semi_ucl = reduced[1] / (reduced[1] + n);
    return s;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    const text = std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
    // SAS reference: a small negative value keeps its sign (`-0.00`).
    if (x < 0 and text[0] != '-') return std.fmt.allocPrint(a, "-{s}", .{text});
    return text;
}
fn best6(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    if (x == inf) return "Infty";
    if (!std.math.isFinite(x)) return ".";
    if (@abs(x) >= 1e6) return gap(cx, "estimates needing E notation");
    return std.mem.trim(u8, try @import("../format.zig").apply(cx.arena, .{ .num = x }, "best6."), " ");
}

pub fn renderOverall(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Sizes) diag.Error!void {
    const a = cx.arena;
    try out.print(a, "\nOverall Noncentrality\n\nMin Var Unbiased Estimate {s}\nLow MSE Estimate {s}\n95% Confidence Limits ({s},{s})\n", .{ try best6(cx, s.mvue), try best6(cx, s.low_mse), try best6(cx, s.lcl), try best6(cx, s.ucl) });
    try out.print(a, "\n\nProportion of Variation Accounted for\n\nEta-Square {s}\nOmega-Square {s}\n95% Confidence Limits ({s},{s})\n", .{ try fixed(a, s.eta, 2), try fixed(a, s.omega, 2), try fixed(a, s.partial_lcl, 2), try fixed(a, s.partial_ucl, 2) });
}

/// Decimals needed to show `x` with 3 significant digits, trailing zeros
/// dropped; 0 and missing need none.
pub fn significantDecimals(a: A, x: f64) !usize {
    if (!std.math.isFinite(x) or x == 0) return 0;
    const exponent: i64 = @intFromFloat(@floor(std.math.log10(@abs(x))));
    var d: usize = @intCast(@max(0, 2 - exponent));
    if (d == 0) return 0;
    const text = try fixed(a, x, d);
    var end = text.len;
    while (d > 0 and text[end - 1] == '0') : (d -= 1) end -= 1;
    return d;
}

pub const Columns = [4][]const []const u8;

pub fn ncColumns(cx: proc.ProcCtx, sizes: []const Sizes) diag.Error!Columns {
    const a = cx.arena;
    var columns: Columns = undefined;
    inline for (.{ "mvue", "low_mse", "lcl", "ucl" }, 0..) |field, c| {
        var decimals: usize = 0;
        for (sizes) |s| {
            const x = @field(s, field);
            if (std.math.isFinite(x) and @abs(x) >= 1e6) return gap(cx, "estimates needing E notation");
            decimals = @max(decimals, try significantDecimals(a, x));
        }
        const texts = try a.alloc([]const u8, sizes.len);
        // SAS reference: an infinite limit is `Infty` cut to the column, `In`.
        for (sizes, texts) |s, *text| text.* = if (@field(s, field) == inf) "In" else try fixed(a, @field(s, field), decimals);
        columns[c] = texts;
    }
    return columns;
}

pub fn ncCells(out: *std.ArrayList(u8), a: A, columns: Columns, index: usize) !void {
    for (columns) |column| try out.print(a, " {s}", .{column[index]});
}

pub fn renderVariation(a: A, out: *std.ArrayList(u8), labels: []const []const u8, sizes: []const Sizes) !void {
    try out.appendSlice(a, "\nTotal Variation Accounted For Partial Variation Accounted For\nSemipartial Conservative Partial\nSemipartial Omega- 95% Confidence Partial Omega-\nSource Eta-Square Square Limits Eta-Square Square 95% Confidence Limits\n\n");
    for (labels, sizes) |label, s| {
        try out.appendSlice(a, label);
        for ([_]f64{ s.semi_eta, s.semi_omega, s.semi_lcl, s.semi_ucl, s.eta, s.omega, s.partial_lcl, s.partial_ucl }) |x| try out.print(a, " {s}", .{try fixed(a, x, 4)});
        try out.append(a, '\n');
    }
}

test "STAT-ANOVA-003 EFFECTSIZE wide noncentral F agrees with the shared kernel where both apply" {
    // Independent of the kernel's forward recursion: log-space weights from the mode.
    for ([_]f64{ 1, 30, 300, 900 }) |nc| {
        const k = try kernel.noncentralCdf(5, 2, 10, nc);
        try std.testing.expectApproxEqAbs(k, wideCdf(5, 2, 10, nc), 1e-10);
    }
}

test "STAT-ANOVA-003 EFFECTSIZE column decimals: 3 significant digits, trailing zeros dropped, column maximum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // SAS reference columns: 659.28/46.44/6.39 (2), 2395/181/43 (0), 19.035 -> 19 (0).
    try std.testing.expectEqual(@as(usize, 0), try significantDecimals(a, 659.28));
    try std.testing.expectEqual(@as(usize, 1), try significantDecimals(a, 46.44));
    try std.testing.expectEqual(@as(usize, 2), try significantDecimals(a, 6.3942));
    try std.testing.expectEqual(@as(usize, 0), try significantDecimals(a, 19.035));
    try std.testing.expectEqual(@as(usize, 1), try significantDecimals(a, 3.39699));
    try std.testing.expectEqual(@as(usize, 4), try significantDecimals(a, 0.0569));
    try std.testing.expectEqual(@as(usize, 0), try significantDecimals(a, 0));
    try std.testing.expectEqual(@as(usize, 3), try significantDecimals(a, -0.6179));
}
