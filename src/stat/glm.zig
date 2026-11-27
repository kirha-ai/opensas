//! GLM execution boundary; declarations/design/math/rendering remain separate.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const selection = @import("data_selection.zig");
pub const parsing = @import("glm_parse.zig");
pub const design = @import("glm_design.zig");
pub const math = @import("glm_fit.zig");
pub const parse = parsing.parse;
pub const Spec = parsing.Spec;

pub fn fitDesign(cx: proc.ProcCtx, spec: Spec, d: design.Design) diag.Error!math.Result {
    if (d.n == 0) return cx.diags.fail(error.ExecError, 0, "PROC GLM: no valid observations", .{});
    const effects = try cx.arena.alloc(math.Effect, d.effects.len);
    for (effects, d.effects) |*dest, source| dest.* = .{ .start = source.start, .len = source.len };
    const factors = try cx.arena.alloc(math.Factors, spec.effects.len);
    for (factors, spec.effects) |*dest, effect| {
        var classes: std.ArrayList(usize) = .empty;
        var continuous: std.ArrayList(usize) = .empty;
        for (effect.variables) |ci| {
            if (std.mem.indexOfScalar(usize, spec.classes, ci) != null) try classes.append(cx.arena, ci) else try continuous.append(cx.arena, ci);
        }
        dest.* = .{ .classes = classes.items, .continuous = continuous.items };
    }
    const type34 = @import("glm_type34.zig");
    const empty_iii = !spec.ss4 and type34.singleEmpty2x2(spec, d, factors);
    const need_ii = spec.ss2 or (empty_iii and (spec.defaultSumsOfSquares() or spec.ss3));
    var result = math.fit(cx.arena, d.x, d.y, d.n, d.p, effects, .{ .weights = d.weights, .frequencies = d.frequencies, .has_intercept = spec.intercept, .singular = spec.singular, .type_ii = if (need_ii) factors else null }) catch |err| {
        if (err == error.OutOfMemory) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC GLM: numerical fit failed", .{});
    };
    errdefer result.deinit(cx.arena);
    if (result.model.fit.rank < d.p) {
        // Type I/II use nested column spaces and actual rank increments, so empty
        // cells do not require the missing-cell Type III hypothesis builder.
        // Keep unsupported singular coefficient displays and graphs explicit.
        const needs_iii_iv = spec.defaultSumsOfSquares() or spec.ss3 or spec.ss4;
        if ((needs_iii_iv and !(empty_iii and result.model.fit.rank == 3)) or spec.classes.len == 0) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient parameter displays or Type III/IV hypotheses are not implemented", .{});
        if (cx.graphics) |g| if (g.enabled == true and !spec.plots_none and !spec.noprint) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient model graphics are not implemented; specify PLOTS=NONE", .{});
    }
    try type34.prepare(cx, spec, d, factors, &result);
    return result;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const @import("../lexer.zig").Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    try execute(cx, out, spec);
}
pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec) diag.Error!void {
    const view = try selection.View.init(cx.arena, spec.input, .{ .by = spec.by, .frequency = spec.freq, .weight = spec.weight, .id = spec.ids });
    const groups = try view.groups(cx.arena, spec.descending, spec.notsorted, cx.diags);
    if (groups.len == 0) return cx.diags.fail(error.ExecError, 0, "PROC GLM: no observations", .{});
    var graph_order: usize = 0;
    for (groups) |group| {
        if (spec.absorb.len > 0) try @import("glm_absorb.zig").validate(cx, spec, group);
        if (!spec.noprint and spec.by.len > 0 and group.observations.len > 0) try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.observations[0].cells, spec.by);
        for (spec.responses) |response| {
            const d = try design.build(cx, spec, group, response);
            if (spec.absorb.len > 0) {
                if (spec.test_requests.len > 0) return proc.failGap(cx.diags, 0, "PROC GLM: TEST with ABSORB is not implemented", .{});
                if (spec.hov != null) return proc.failGap(cx.diags, 0, "PROC GLM: MEANS with ABSORB is not implemented", .{});
                if (spec.random != null) return proc.failGap(cx.diags, 0, "PROC GLM: RANDOM with ABSORB is not implemented", .{});
                if (@hasField(Spec, "lsmeans")) if (spec.lsmeans.len > 0) return cx.diags.fail(error.ParseError, 0, "PROC GLM: LSMEANS is unavailable with ABSORB", .{});
                var absorbed = try @import("glm_absorb.zig").fit(cx, spec, d);
                defer absorbed.deinit(cx.arena);
                const estimates = try @import("glm_estimate.zig").computeAbsorbed(cx, spec, d, absorbed);
                if (!spec.noprint) {
                    try @import("glm_absorb_render.zig").render(cx, out, spec, d, absorbed);
                    try @import("glm_estimate.zig").renderResults(cx, out, estimates);
                }
                if (!spec.noprint and !spec.plots_none) if (cx.graphics) |g| {
                    if (g.enabled == true) return proc.failGap(cx.diags, 0, "PROC GLM: default graphics with ABSORB are not implemented; use PLOTS=NONE", .{});
                };
                continue;
            }
            var result = try fitDesign(cx, spec, d);
            defer result.deinit(cx.arena);
            const tests = try @import("glm_test_statement.zig").compute(cx, spec, result);
            const hov = if (spec.hov != null) try @import("glm_hov.zig").compute(cx, spec, d) else null;
            const random = try @import("glm_random.zig").computeAll(cx, spec, d, result);
            const estimates = try @import("glm_estimate.zig").computeAll(cx, spec, d, result.model.fit.mse, result.model.fit.df_error);
            if (!spec.noprint) try @import("glm_render.zig").renderPrepared(cx, out, spec, d, result, estimates);
            try @import("glm_test_statement.zig").render(cx, out, spec, tests);
            if (hov) |values| try @import("glm_hov.zig").render(cx, out, spec, d, values);
            for (random) |analysis| {
                var random_spec = spec;
                random_spec.random = analysis.request;
                try @import("glm_random.zig").render(cx, out, random_spec, d, result, analysis.result);
            }
            try @import("glm_lsmeans.zig").execute(cx, out, spec, d, result.model.fit.mse, result.model.fit.df_error);
            try @import("glm_plots.zig").emit(cx, spec, d, result, graph_order);
            graph_order += 1;
        }
    }
}

test {
    _ = @import("glm_computational_tests.zig");
    _ = @import("glm_effectsize.zig");
    _ = @import("glm_tests.zig");
    _ = @import("glm_persistence_tests.zig");
}

/// Minimal retained GLM execution boundary. Initial analyses are not replayed
/// by later RUN statements. Post-fit analyses not implemented here remain loud.
pub fn continuationKeyword(name: []const u8) bool {
    inline for (.{ "run", "quit", "absorb", "by", "freq", "weight", "id", "class", "model", "where", "means", "lsmeans", "contrast", "estimate", "test", "random", "repeated", "manova", "output", "store", "code" }) |keyword| {
        if (std.ascii.eqlIgnoreCase(name, keyword)) return true;
    }
    return false;
}
pub const Session = struct {
    spec: Spec,
    pub fn continuation(self: *Session, cx: proc.ProcCtx, tokens: []const @import("../lexer.zig").Token) diag.Error!bool {
        var i: usize = 0;
        while (i < tokens.len and tokens[i].tag != .eof) {
            if (tokens[i].tag == .semicolon) {
                i += 1;
                continue;
            }
            const token = tokens[i];
            var end = i;
            while (end < tokens.len and tokens[end].tag != .semicolon and tokens[end].tag != .eof) end += 1;
            if (end >= tokens.len or tokens[end].tag != .semicolon) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: expected semicolon in continuation", .{});
            const eq = std.ascii.eqlIgnoreCase;
            if (eq(token.text, "quit")) {
                if (end != i + 1) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid QUIT boundary", .{});
                return false;
            }
            if (eq(token.text, "run")) {
                if (end != i + 1) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid RUN boundary", .{});
            } else if (eq(token.text, "absorb") or eq(token.text, "by") or eq(token.text, "freq") or eq(token.text, "weight") or eq(token.text, "id")) {
                // S154 pp.4065–4072/4106: declarations after first RUN are ignored.
            } else if (eq(token.text, "model") or eq(token.text, "class")) {
                return cx.diags.fail(error.ParseError, token.line, "PROC GLM: CLASS/MODEL cannot be redeclared after the first RUN", .{});
            } else if (self.spec.absorb.len > 0 and (eq(token.text, "lsmeans") or eq(token.text, "output"))) {
                return cx.diags.fail(error.ParseError, token.line, "PROC GLM: {s} is unavailable with ABSORB", .{token.text});
            } else return proc.failGap(cx.diags, token.line, "PROC GLM: interactive {s} is not implemented", .{token.text});
            i = end + 1;
        }
        return true;
    }
};
pub fn canContinue(cx: proc.ProcCtx, spec: Spec) diag.Error!bool {
    if (spec.by.len > 0) return false;
    if (spec.manova or spec.responses.len < 2) return true;
    const view = try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    const first = try design.build(cx, spec, view, spec.responses[0]);
    for (spec.responses[1..]) |response| {
        const other = try design.build(cx, spec, view, response);
        if (!std.mem.eql(usize, first.source_rows, other.source_rows)) return false;
    }
    return true;
}
