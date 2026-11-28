//! One within-subject factor, S154 physical pp.4100–4104,4149–4156.
//! GLM uses complete SUBJECT rows, not long-form time covariance fitting.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const selection = @import("data_selection.zig");
const multi = @import("reg_mtest.zig");
const Fit = @import("reg_fit.zig").Fit;
const Constraint = @import("reg_restrict.zig").Constraint;
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Transformation = enum { contrast, polynomial, helmert, mean, profile };
pub const Epsilon = enum { hfl, hf, cm };
pub const Request = struct {
    name: []const u8,
    levels: []const f64,
    transformation: Transformation = .contrast,
    reference: usize,
    nom: bool = false,
    nou: bool = false,
    summary: bool = false,
    printe: bool = false,
    printh: bool = false,
    printm: bool = false,
    exact: bool = false,
    epsilon: Epsilon = .hfl,
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
pub fn read(cx: proc.ProcCtx, t: []const lex.Token, spec: glm.Spec) diag.Error!Request {
    if (!at(t, 1, .name)) return cx.diags.fail(error.ParseError, 0, "PROC GLM: REPEATED requires a factor name", .{});
    if (spec.input.ds.indexOf(t[1].text) != null) return cx.diags.fail(error.ParseError, t[1].line, "PROC GLM: REPEATED factor name must not name an input variable", .{});
    var count = spec.responses.len;
    var i: usize = 2;
    if (at(t, i, .number)) {
        count = std.fmt.parseInt(usize, t[i].text, 10) catch return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: REPEATED levels must be an integer", .{});
        i += 1;
    }
    if (count < 2) return cx.diags.fail(error.ParseError, t[1].line, "PROC GLM: REPEATED requires at least two levels", .{});
    // Check multifactor grammar before the single-factor dimension check.
    for (t) |token| if (token.tag == .comma) return proc.failGap(cx.diags, token.line, "PROC GLM: multiple within-subject factors are not implemented", .{});
    if (count != spec.responses.len) return cx.diags.fail(error.ParseError, t[1].line, "PROC GLM: REPEATED levels must equal the number of responses", .{});
    if (count > 17) return proc.failGap(cx.diags, t[1].line, "PROC GLM: REPEATED beyond seventeen levels is not implemented", .{});
    const levels = try cx.arena.alloc(f64, count);
    for (levels, 0..) |*level, k| level.* = @floatFromInt(k + 1);
    if (at(t, i, .lparen)) {
        i += 1;
        for (levels) |*level| {
            var sign: f64 = 1;
            if (at(t, i, .minus) or at(t, i, .plus)) {
                if (at(t, i, .minus)) sign = -1;
                i += 1;
            }
            if (!at(t, i, .number)) return cx.diags.fail(error.ParseError, t[1].line, "PROC GLM: REPEATED requires one numeric value per level", .{});
            level.* = sign * (std.fmt.parseFloat(f64, t[i].text) catch return error.ParseError);
            if (!std.math.isFinite(level.*)) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: nonfinite repeated level", .{});
            i += 1;
        }
        if (!at(t, i, .rparen)) return cx.diags.fail(error.ParseError, t[1].line, "PROC GLM: REPEATED level list has the wrong length", .{});
        i += 1;
    }
    var result: Request = .{ .name = t[1].text, .levels = levels, .reference = count - 1 };
    if (i < t.len and t[i].tag != .slash) {
        result.transformation = if (eq(t[i].text, "contrast")) .contrast else if (eq(t[i].text, "polynomial")) .polynomial else if (eq(t[i].text, "helmert")) .helmert else if (eq(t[i].text, "mean")) .mean else if (eq(t[i].text, "profile")) .profile else {
            if (eq(t[i].text, "identity")) return proc.failGap(cx.diags, t[i].line, "PROC GLM: REPEATED IDENTITY is not implemented", .{});
            return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: invalid REPEATED transformation", .{});
        };
        i += 1;
        if (at(t, i, .lparen)) {
            if (result.transformation != .contrast and result.transformation != .mean) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: this transformation has no reference level", .{});
            if (!at(t, i + 1, .number) or !at(t, i + 2, .rparen)) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: invalid reference level", .{});
            const reference = std.fmt.parseInt(usize, t[i + 1].text, 10) catch return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: reference level must be an integer", .{});
            if (reference < 1 or reference > count) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: reference level is out of range", .{});
            result.reference = reference - 1;
            i += 3;
        }
    }
    if (at(t, i, .slash)) i += 1;
    while (i < t.len) {
        const name = t[i].text;
        if (eq(name, "nom")) result.nom = true else if (eq(name, "nou")) result.nou = true else if (eq(name, "summary")) result.summary = true else if (eq(name, "printe")) result.printe = true else if (eq(name, "printh")) result.printh = true else if (eq(name, "printm")) result.printm = true else if (eq(name, "htype") or eq(name, "uepsdef") or eq(name, "mstat")) {
            if (!at(t, i + 1, .eq) or i + 2 >= t.len) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: REPEATED option requires a value", .{});
            const value = t[i + 2].text;
            if (eq(name, "htype")) {
                if (!eq(value, "3")) return proc.failGap(cx.diags, t[i].line, "PROC GLM: REPEATED HTYPE other than 3 is not implemented", .{});
            } else if (eq(name, "uepsdef")) {
                result.epsilon = if (eq(value, "hfl")) .hfl else if (eq(value, "hf")) .hf else if (eq(value, "cm")) .cm else return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: invalid UEPSDEF", .{});
            } else if (eq(value, "exact")) result.exact = true else if (!eq(value, "fapprox")) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: invalid MSTAT", .{});
            i += 2;
        } else if (eq(name, "canonical") or eq(name, "canon") or eq(name, "mean") or eq(name, "printrv")) return proc.failGap(cx.diags, t[i].line, "PROC GLM: REPEATED {s} is not implemented", .{name}) else return cx.diags.fail(error.ParseError, t[i].line, "PROC GLM: invalid REPEATED option {s}", .{name});
        i += 1;
    }
    if (result.nom and result.nou) return proc.failGap(cx.diags, t[1].line, "PROC GLM: combined REPEATED NOM/NOU is not implemented", .{});
    return result;
}

/// Rows of M' (one contrast per row). Polynomial basis uses centered, scaled
/// abscissae and two-pass Gram-Schmidt so unequal spacing does not form X'X.
pub fn transformation(a: A, request: Request) diag.Error![]const []const f64 {
    const k = request.levels.len;
    const rows = try a.alloc([]const f64, k - 1);
    if (request.transformation == .polynomial) {
        var minimum = request.levels[0];
        var maximum = minimum;
        for (request.levels, 0..) |v, i| {
            for (request.levels[0..i]) |prior| if (v == prior) return error.ExecError;
            minimum = @min(minimum, v);
            maximum = @max(maximum, v);
        }
        const center = minimum / 2 + maximum / 2;
        const scale = maximum / 2 - minimum / 2;
        if (!(scale > 0)) return error.ExecError;
        const basis = try a.alloc([]f64, k);
        basis[0] = try a.alloc(f64, k);
        @memset(basis[0], 1 / @sqrt(@as(f64, @floatFromInt(k))));
        for (1..k) |degree| {
            const row = try a.alloc(f64, k);
            for (row, request.levels, basis[degree - 1]) |*v, x, previous| v.* = (x - center) / scale * previous;
            for (0..2) |_| for (basis[0..degree]) |prior| {
                var dot: f128 = 0;
                for (row, prior) |x, y| dot += @as(f128, x) * y;
                for (row, prior) |*x, y| x.* -= @as(f64, @floatCast(dot)) * y;
            };
            var norm: f128 = 0;
            for (row) |x| norm += @as(f128, x) * x;
            if (!(norm > 0x1p-80)) return error.ExecError;
            for (row) |*x| x.* /= @sqrt(@as(f64, @floatCast(norm)));
            basis[degree] = row;
            rows[degree - 1] = row;
        }
    } else {
        var ordinal: usize = 0;
        for (rows, 0..) |*dest, j| {
            const row = try a.alloc(f64, k);
            @memset(row, 0);
            switch (request.transformation) {
                .contrast, .mean => {
                    if (ordinal == request.reference) ordinal += 1;
                    if (request.transformation == .mean) @memset(row, -1 / @as(f64, @floatFromInt(k - 1))) else row[request.reference] = -1;
                    row[ordinal] = 1;
                    ordinal += 1;
                },
                .profile => {
                    row[j] = 1;
                    row[j + 1] = -1;
                },
                .helmert => {
                    row[j] = 1;
                    @memset(row[j + 1 ..], -1 / @as(f64, @floatFromInt(k - j - 1)));
                },
                .polynomial => unreachable,
            }
            dest.* = row;
        }
    }
    return rows;
}

pub const Sphericity = struct { gg: f64, adjusted: f64, criterion: f64, chi_square: f64, df: usize, probability: f64 };
/// E here MUST be expressed in an orthonormal contrast basis for epsilons.
/// Mauchly's W alone is also computed for the requested nonorthogonal basis.
pub fn sphericity(e: []const f64, b: usize, error_df: usize, subjects: usize, method: Epsilon) diag.Error!Sphericity {
    if (b == 0 or b > 16 or e.len != b * b or error_df == 0) return error.ExecError;
    var scale: f64 = 0;
    for (e) |value| {
        if (!std.math.isFinite(value)) return error.ExecError;
        scale = @max(scale, @abs(value));
    }
    for (0..b) |i| for (0..i) |j| {
        if (@abs(e[i * b + j] - e[j * b + i]) > 32 * std.math.floatEps(f64) * scale) return error.ExecError;
    };
    var trace: f128 = 0;
    var square: f128 = 0;
    for (0..b) |i| {
        trace += e[i * b + i];
        for (0..b) |j| square += @as(f128, e[i * b + j]) * e[j * b + i];
    }
    if (!(trace > 0 and square > 0)) return error.ExecError;
    const bf: f64 = @floatFromInt(b);
    const v: f64 = @floatFromInt(error_df);
    const gg: f64 = @floatCast(trace * trace / (@as(f128, @floatFromInt(b)) * square));
    if (!(gg > 0 and gg <= 1 + 1e-12)) return error.ExecError;
    const n: f64 = @floatFromInt(if (method == .hf) subjects else error_df + 1);
    var adjusted = if (b == 1) 1 else (n * bf * gg - 2) / (bf * (v - bf * gg));
    if (method == .cm) {
        const va = (v - 1) + v * (v - 1) / 2;
        if (!(va > 0)) return error.ExecError;
        adjusted *= (va - 2) * (va - 4) / (va * va);
    }
    if (!std.math.isFinite(adjusted) or adjusted <= 0) return error.ExecError;
    // Cholesky in fixed small storage: positive-definite E is the currently
    // supported sphericity domain; singular covariance is a visible gap.
    if (b > 16) return error.ExecError;
    var lower = [_]f128{0} ** 256;
    var log_det: f128 = 0;
    for (0..b) |i| for (0..i + 1) |j| {
        var value: f128 = e[i * b + j];
        for (0..j) |l| value -= lower[i * b + l] * lower[j * b + l];
        if (i == j) {
            if (!(value > trace * 0x1p-44)) return error.ExecError;
            lower[i * b + j] = @sqrt(value);
            log_det += @log(value);
        } else lower[i * b + j] = value / lower[j * b + j];
    };
    const log_w: f64 = @min(0, @as(f64, @floatCast(log_det - @as(f128, @floatFromInt(b)) * @log(trace / @as(f128, @floatFromInt(b))))));
    const correction = 1 - (2 * bf * bf + bf + 2) / (6 * bf * v);
    if (b > 1 and correction <= 0) return error.ExecError;
    const chi = -v * correction * log_w;
    const df = b * (b + 1) / 2 - 1;
    return .{ .gg = @min(1, gg), .adjusted = adjusted, .criterion = @exp(log_w), .chi_square = chi, .df = df, .probability = if (df == 0) 1 else 1 - @import("../functions.zig").gammaP(@as(f64, @floatFromInt(df)) / 2, chi / 2) };
}

pub const Analysis = struct {
    design: glm.design.Design,
    original: []const Fit,
    transform: []const []const f64,
    tests: []const multi.Result,
    orthogonal_tests: []const multi.Result,
    between: glm.math.Result,
    sphere: Sphericity,
    transformed_sphere: Sphericity,
    error_matrix: []const f64,
    error_df: usize,
};
fn hypotheses(a: A, p: usize, start: usize, count: usize) ![]const Constraint {
    const rows = try a.alloc(Constraint, count);
    for (rows, 0..) |*row, j| {
        const coefficients = try a.alloc(f64, p);
        @memset(coefficients, 0);
        coefficients[start + j] = 1;
        row.* = .{ .coefficients = coefficients, .rhs = 0 };
    }
    return rows;
}
fn multivariate(cx: proc.ProcCtx, fits: []const Fit, weights: []const f64, linear: []const Constraint, m: []const []const f64, exact: bool) diag.Error!multi.Result {
    return multi.evaluate(cx.arena, fits, weights, .{ .statement_index = 0, .number = 0, .label = null, .linear = linear, .transform = m, .exact = exact }) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED singular covariance, nonestimable hypothesis, or requested multivariate inference is not implemented", .{});
    };
}
pub fn compute(cx: proc.ProcCtx, spec: glm.Spec, group: selection.View) diag.Error!Analysis {
    const request = spec.repeated.?;
    if (!spec.noprint and !spec.plots_none) if (cx.graphics) |graphics| {
        if (graphics.enabled == true) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED graphics are not implemented; specify PLOTS=NONE", .{});
    };
    if (!spec.nouni) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED individual response output requires MODEL NOUNI until its multivariate listing is implemented", .{});
    if (!spec.intercept or spec.absorb.len > 0 or spec.weight != null or spec.freq != null or spec.random != null or spec.contrasts.len > 0 or spec.test_requests.len > 0 or spec.estimates.len > 0 or spec.lsmeans.len > 0 or spec.means.len > 0 or spec.hov != null) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED with NOINT, ABSORB, WEIGHT/FREQ, or additional analysis statements is not implemented", .{});
    if (spec.ss1 or spec.ss2 or spec.ss4) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED requires default or Type III hypotheses", .{});
    const a = cx.arena;
    const d = try glm.design.build(cx, spec, group, spec.responses[0]);
    const k = spec.responses.len;
    const fits = try a.alloc(Fit, k);
    for (fits, spec.responses) |*fit, response| {
        var current = d;
        const y = try a.alloc(f64, d.n);
        for (d.observations, y) |row, *value| value.* = row.cells[response].num;
        current.y = y;
        const result = try glm.fitDesign(cx, spec, current);
        fit.* = result.model.fit;
        if (fit.rank != d.p or fit.df_error < k - 1) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED requires a full-rank between-subject design and sufficient residual degrees of freedom", .{});
    }
    const m = transformation(a, request) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC GLM: repeated or numerically unresolved polynomial spacings are not implemented", .{});
    };
    var orthogonal_request = request;
    orthogonal_request.transformation = .polynomial;
    const regular = try a.alloc(f64, k);
    for (regular, 0..) |*value, j| value.* = @floatFromInt(j);
    orthogonal_request.levels = regular;
    const orthogonal = if (request.transformation == .polynomial) m else try transformation(a, orthogonal_request);
    const tests = try a.alloc(multi.Result, d.effects.len + 1);
    const orthogonal_tests = try a.alloc(multi.Result, tests.len);
    for (tests, orthogonal_tests, 0..) |*test_result, *ortho_result, j| {
        const block: glm.design.Effect = if (j == 0) .{ .start = 0, .len = 1 } else d.effects[j - 1];
        if (!request.nom and @min(k - 1, block.len) > 1) return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED general multivariate table presentation is not implemented; use NOM", .{});
        const linear = try hypotheses(a, d.p, block.start, block.len);
        test_result.* = try multivariate(cx, fits, d.weights, linear, m, request.exact);
        ortho_result.* = if (request.transformation == .polynomial) test_result.* else try multivariate(cx, fits, d.weights, linear, orthogonal, request.exact);
    }
    var between_design = d;
    const between_y = try a.alloc(f64, d.n);
    for (d.observations, between_y) |row, *value| {
        var sum: f128 = 0;
        for (spec.responses) |ci| sum += row.cells[ci].num;
        value.* = @floatCast(sum / @sqrt(@as(f128, @floatFromInt(k))));
    }
    between_design.y = between_y;
    const between = try glm.fitDesign(cx, spec, between_design);
    const v = fits[0].df_error;
    const sphere = sphericity(orthogonal_tests[0].error_matrix, k - 1, v, d.n, request.epsilon) catch return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED degenerate sphericity is not implemented", .{});
    const transformed_sphere = sphericity(tests[0].error_matrix, k - 1, v, d.n, request.epsilon) catch return proc.failGap(cx.diags, 0, "PROC GLM: REPEATED degenerate transformed covariance is not implemented", .{});
    const e = try a.alloc(f64, k * k);
    for (0..k) |i| for (0..k) |j| {
        var sum: f128 = 0;
        for (fits[i].residuals, fits[j].residuals) |x, y| sum += @as(f128, x) * y;
        e[i * k + j] = @floatCast(sum);
    };
    return .{ .design = d, .original = fits, .transform = m, .tests = tests, .orthogonal_tests = orthogonal_tests, .between = between, .sphere = sphere, .transformed_sphere = transformed_sphere, .error_matrix = e, .error_df = v };
}
pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: glm.Spec, group: selection.View) diag.Error!void {
    const result = try compute(cx, spec, group);
    if (!spec.noprint) try @import("glm_repeated_render.zig").render(cx, out, spec, result);
}
test {
    _ = @import("glm_repeated_tests.zig");
}
