//! One-way dispersion ANOVA, S154 physical pp.4089–4090 and 4143–4144.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Method = enum { levene_square, levene_abs, bf, obrien, bartlett };
pub const Request = struct { column: usize, method: Method = .levene_square, w: f64 = 0.5 };
pub const Result = struct { chi_square: ?f64 = null, counts: []usize, means: []f64, standard_deviations: []f64, dispersion: []f64, df: usize, df_error: usize, ss: f64, sse: f64, ms: f64, mse: f64, f_value: f64, p_value: f64 };
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec) diag.Error!Request {
    if (tokens.len < 4 or tokens[1].tag != .name or tokens[2].tag != .slash) return proc.failGap(cx.diags, tokens[0].line, "PROC GLM: MEANS currently requires one factor and HOVTEST", .{});
    const column = spec.input.ds.indexOf(tokens[1].text) orelse return cx.diags.fail(error.ParseError, tokens[1].line, "PROC GLM: MEANS variable not found", .{});
    var result: Request = .{ .column = column };
    var i: usize = 3;
    if (!eq(tokens[i].text, "hovtest")) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: MEANS option {s} is not implemented", .{tokens[i].text});
    i += 1;
    if (i < tokens.len and tokens[i].tag == .eq) {
        i += 1;
        if (i == tokens.len) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: HOVTEST requires a method", .{});
        if (eq(tokens[i].text, "levene")) result.method = .levene_square else if (eq(tokens[i].text, "bf")) result.method = .bf else if (eq(tokens[i].text, "obrien")) result.method = .obrien else if (eq(tokens[i].text, "bartlett")) result.method = .bartlett else return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: unknown HOVTEST method", .{});
        i += 1;
    }
    if (i < tokens.len and tokens[i].tag == .lparen) {
        i += 1;
        if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: malformed HOVTEST suboption", .{});
        const option = tokens[i];
        i += 2;
        if (result.method == .levene_square and eq(option.text, "type")) {
            if (eq(tokens[i].text, "abs")) result.method = .levene_abs else if (!eq(tokens[i].text, "square")) return cx.diags.fail(error.ParseError, option.line, "PROC GLM: Levene TYPE must be ABS or SQUARE", .{});
            i += 1;
        } else if (result.method == .obrien and eq(option.text, "w")) {
            var sign: f64 = 1;
            if (tokens[i].tag == .minus or tokens[i].tag == .plus) {
                if (tokens[i].tag == .minus) sign = -1;
                i += 1;
            }
            if (i == tokens.len or tokens[i].tag != .number) return cx.diags.fail(error.ParseError, option.line, "PROC GLM: OBRIEN W requires a finite number", .{});
            result.w = sign * (std.fmt.parseFloat(f64, tokens[i].text) catch return cx.diags.fail(error.ParseError, option.line, "PROC GLM: invalid OBRIEN W value", .{}));
            if (!std.math.isFinite(result.w)) return cx.diags.fail(error.ParseError, option.line, "PROC GLM: OBRIEN W must be finite", .{});
            i += 1;
        } else return cx.diags.fail(error.ParseError, option.line, "PROC GLM: inapplicable HOVTEST suboption", .{});
        if (i == tokens.len or tokens[i].tag != .rparen) return cx.diags.fail(error.ParseError, option.line, "PROC GLM: HOVTEST suboption requires closing parenthesis", .{});
        i += 1;
    }
    if (i < tokens.len) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: additional MEANS options are not implemented", .{});
    return result;
}
fn less(_: void, a: f64, b: f64) bool { return a < b; }
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design) diag.Error!Result {
    const request = spec.hov.?;
    if (spec.absorb.len != 0 or spec.freq != null or spec.weight != null or !spec.intercept or spec.classes.len != 1 or spec.effects.len != 1 or spec.effects[0].variables.len != 1 or spec.effects[0].variables[0] != request.column or spec.classes[0] != request.column) return proc.failGap(cx.diags, 0, "PROC GLM: MEANS HOVTEST currently supports unweighted one-way CLASS models", .{});
    const a = cx.arena;
    const class = d.classes[0];
    const k = class.levels.len;
    if (k < 2 or d.n <= k) return proc.failGap(cx.diags, 0, "PROC GLM: HOVTEST requires two groups and residual degrees of freedom", .{});
    const counts = try a.alloc(usize, k);
    const means = try a.alloc(f64, k);
    const standard_deviations = try a.alloc(f64, k);
    const dispersion = try a.alloc(f64, d.n);
    const centers = try a.alloc(f64, k);
    const scratch = try a.alloc(f64, d.n);
    for (0..k) |g| {
        var count: usize = 0;
        for (d.y, class.row_levels) |y, level| if (level.? == g) { scratch[count] = y; count += 1; };
        counts[g] = count;
        var delta: f64 = 0;
        const anchor = scratch[0];
        for (scratch[0..count]) |y| delta += y - anchor;
        means[g] = anchor + delta / @as(f64, @floatFromInt(count));
        var ss: f64 = 0;
        for (scratch[0..count]) |y| ss += (y - means[g]) * (y - means[g]);
        standard_deviations[g] = if (count > 1) @sqrt(ss / @as(f64, @floatFromInt(count - 1))) else std.math.nan(f64);
        if (request.method == .bf) {
            std.mem.sort(f64, scratch[0..count], {}, less);
            centers[g] = scratch[count / 2] / 2 + scratch[(count - 1) / 2] / 2;
        } else centers[g] = means[g];
        if (request.method == .obrien and count < 3) return proc.failGap(cx.diags, 0, "PROC GLM: OBRIEN HOVTEST requires at least three observations per group", .{});
    }
    if (request.method == .bartlett) {
        // Bartlett's corrected likelihood-ratio statistic; independent formula:
        // https://www.itl.nist.gov/div898/handbook/eda/section3/eda357.htm
        var pooled: f64 = 0;
        var logarithms: f64 = 0;
        var reciprocals: f64 = 0;
        for (counts, standard_deviations) |count, sd| {
            if (count < 2 or !(sd > 0) or !std.math.isFinite(sd)) return proc.failGap(cx.diags, 0, "PROC GLM: Bartlett HOVTEST requires positive variance in every group", .{});
            const df: f64 = @floatFromInt(count - 1);
            pooled += df * sd * sd;
            logarithms += df * @log(sd * sd);
            reciprocals += 1 / df;
        }
        const df = k - 1;
        const dfe = d.n - k;
        const denominator_df: f64 = @floatFromInt(dfe);
        const correction = 1 + (reciprocals - 1 / denominator_df) / (3 * @as(f64, @floatFromInt(df)));
        const raw = denominator_df * @log(pooled / denominator_df) - logarithms;
        const budget = 256 * std.math.floatEps(f64) * @max(1, @abs(logarithms));
        if (!std.math.isFinite(raw) or raw < -budget) return error.ExecError;
        const statistic = @max(0, raw) / correction;
        const nan = std.math.nan(f64);
        return .{ .counts = counts, .means = means, .standard_deviations = standard_deviations, .dispersion = &.{}, .df = df, .df_error = dfe, .ss = nan, .sse = nan, .ms = nan, .mse = nan, .f_value = nan, .chi_square = statistic, .p_value = @import("logistic_fit.zig").chiTail(statistic, df) };
    }
    for (d.y, class.row_levels, dispersion) |y, level, *z| {
        const g = level.?;
        const delta = y - centers[g];
        z.* = switch (request.method) {
            .bartlett => unreachable,
            .levene_abs, .bf => @abs(delta),
            .levene_square => delta * delta,
            .obrien => blk: {
                const n: f64 = @floatFromInt(counts[g]);
                const variance = standard_deviations[g] * standard_deviations[g];
                break :blk ((request.w + n - 2) * n * delta * delta - request.w * (n - 1) * variance) / ((n - 1) * (n - 2));
            },
        };
        if (!std.math.isFinite(z.*)) return cx.diags.fail(error.ExecError, 0, "PROC GLM: HOVTEST dispersion overflow", .{});
    }
    const zmeans = try a.alloc(f64, k);
    @memset(zmeans, 0);
    var total: f64 = 0;
    for (dispersion, class.row_levels) |z, level| { zmeans[level.?] += z; total += z; }
    total /= @as(f64, @floatFromInt(d.n));
    var ss: f64 = 0;
    for (zmeans, counts) |*mean, count| {
        mean.* /= @as(f64, @floatFromInt(count));
        ss += @as(f64, @floatFromInt(count)) * (mean.* - total) * (mean.* - total);
    }
    var sse: f64 = 0;
    for (dispersion, class.row_levels) |z, level| sse += (z - zmeans[level.?]) * (z - zmeans[level.?]);
    if (!(sse > 0) or !std.math.isFinite(ss) or !std.math.isFinite(sse)) return proc.failGap(cx.diags, 0, "PROC GLM: degenerate HOVTEST dispersion inference is not implemented", .{});
    const df = k - 1;
    const dfe = d.n - k;
    const ms = ss / @as(f64, @floatFromInt(df));
    const mse = sse / @as(f64, @floatFromInt(dfe));
    const statistic = ms / mse;
    return .{ .counts = counts, .means = means, .standard_deviations = standard_deviations, .dispersion = dispersion, .df = df, .df_error = dfe, .ss = ss, .sse = sse, .ms = ms, .mse = mse, .f_value = statistic, .p_value = @import("reg_fit.zig").fProbability(statistic, df, dfe) };
}
fn number(a: std.mem.Allocator, x: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, result: Result) diag.Error!void {
    if (spec.noprint) return;
    const a = cx.arena;
    const request = spec.hov.?;
    const response = spec.input.ds.columns.items[d.response].name;
    const name = spec.input.ds.columns.items[request.column].name;
    const method = switch (request.method) { .levene_abs, .levene_square => "Levene's", .bf => "Brown and Forsythe's", .obrien => "O'Brien's", .bartlett => "Bartlett's" };
    const transformation = switch (request.method) { .levene_abs => "Absolute Deviations from Group Means", .levene_square => "Squared Deviations from Group Means", .bf => "Absolute Deviations from Group Medians", .obrien => "Transformed Deviations", .bartlett => "" };
    if (result.chi_square) |statistic| {
        try out.print(a, "\nThe GLM Procedure\nBartlett's Test for Homogeneity of {s} Variance\n\nSource DF Chi-Square Pr > ChiSq\n{s} {d} {s} {s}\n", .{ response, name, result.df, try number(a, statistic, 4), if (result.p_value < 0.0001) "<.0001" else try number(a, result.p_value, 4) });
    } else {
        try out.print(a, "\nThe GLM Procedure\n{s} Test for Homogeneity of {s} Variance\nANOVA of {s}\n\nSum of Mean\nSource DF Squares Square F Value Pr > F\n", .{ method, response, transformation });
        try out.print(a, "{s} {d} {s} {s} {s} {s}\nError {d} {s} {s}\n", .{ name, result.df, try number(a, result.ss, 8), try number(a, result.ms, 8), try number(a, result.f_value, 2), if (result.p_value < 0.0001) "<.0001" else try number(a, result.p_value, 4), result.df_error, try number(a, result.sse, 8), try number(a, result.mse, 8) });
    }
    // MEANS also requests descriptives; do not silently omit this companion.
    try out.print(a, "\nThe GLM Procedure\n\nLevel of {s} N {s} Mean Std Dev\n", .{ name, response });
    for (d.classes[0].levels, result.counts, result.means, result.standard_deviations) |level, count, mean, sd| try out.print(a, "{s} {d} {s} {s}\n", .{ level.label, count, try number(a, mean, 7), try number(a, sd, 7) });
}

test { _ = @import("glm_hov_tests.zig"); }
