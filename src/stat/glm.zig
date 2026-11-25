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
    const factors = if (spec.ss2) try cx.arena.alloc(math.Factors, spec.effects.len) else null;
    if (factors) |metadata| for (metadata, spec.effects) |*dest, effect| {
        var classes: std.ArrayList(usize) = .empty;
        var continuous: std.ArrayList(usize) = .empty;
        for (effect.variables) |ci| {
            if (std.mem.indexOfScalar(usize, spec.classes, ci) != null) try classes.append(cx.arena, ci) else try continuous.append(cx.arena, ci);
        }
        dest.* = .{ .classes = classes.items, .continuous = continuous.items };
    };
    var result = math.fit(cx.arena, d.x, d.y, d.n, d.p, effects, .{ .weights = d.weights, .frequencies = d.frequencies, .has_intercept = spec.intercept, .singular = spec.singular, .type_ii = factors }) catch |err| {
        if (err == error.OutOfMemory) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC GLM: numerical fit failed", .{});
    };
    errdefer result.deinit(cx.arena);
    if (result.model.fit.rank < d.p) {
        // Type I/II use nested column spaces and actual rank increments, so empty
        // cells do not require the missing-cell Type III hypothesis builder.
        // Keep unsupported singular coefficient displays and graphs explicit.
        if ((!spec.ss1 and !spec.ss2) or spec.classes.len == 0) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient parameter displays or Type III hypotheses are not implemented", .{});
        if (cx.graphics) |g| if (g.enabled == true and !spec.plots_none and !spec.noprint) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient model graphics are not implemented; specify PLOTS=NONE", .{});
    }
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
        if (!spec.noprint and spec.by.len > 0 and group.observations.len > 0) try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.observations[0].cells, spec.by);
        for (spec.responses) |response| {
            const d = try design.build(cx, spec, group, response);
            var result = try fitDesign(cx, spec, d);
            defer result.deinit(cx.arena);
            if (!spec.noprint) try @import("glm_render.zig").render(cx, out, spec, d, result);
            try @import("glm_lsmeans.zig").execute(cx, out, spec, d, result.model.fit.mse, result.model.fit.df_error);
            try @import("glm_plots.zig").emit(cx, spec, d, result, graph_order);
            graph_order += 1;
        }
    }
}

test {
    _ = @import("glm_tests.zig");
}
