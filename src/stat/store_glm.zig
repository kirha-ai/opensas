//! GLM producer for the shared OpenSAS native STORE format.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parsing = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");
const store = @import("store.zig");
pub fn validate(cx: proc.ProcCtx, spec: parsing.Spec) diag.Error!void {
    if (spec.store == null) return;
    if (@hasField(parsing.Spec, "repeated")) if (spec.repeated != null) return proc.failGap(cx.diags, 0, "PROC GLM: STORE with REPEATED is not implemented", .{});
    if (spec.responses.len != 1 or spec.by.len > 0 or spec.absorb.len > 0 or spec.random != null or spec.test_requests.len > 0 or spec.manova) return proc.failGap(cx.diags, 0, "PROC GLM: STORE requires one fixed-effects response without BY, ABSORB, RANDOM, TEST or MANOVA", .{});
    for (spec.classes) |ci| if (spec.input.ds.columns.items[ci].format != null) return proc.failGap(cx.diags, 0, "PROC GLM: STORE of formatted CLASS mappings is not implemented", .{});
}
pub fn model(cx: proc.ProcCtx, spec: parsing.Spec, d: design.Design, result: math.Result) diag.Error!store.Model {
    const fit = result.model.fit;
    if (fit.rank != d.p or fit.df_error == 0 or !std.math.isFinite(fit.mse)) return proc.failGap(cx.diags, 0, "PROC GLM: STORE of rank-deficient or saturated fits is not implemented", .{});
    const a = cx.arena;
    const classes = try a.alloc(store.Class, d.classes.len);
    for (classes, d.classes) |*dest, source| {
        const levels = try a.alloc(store.Level, source.levels.len);
        for (levels, source.levels) |*l, source_level| l.* = .{ .number = if (source_level.value == .num) source_level.value.num else null, .text = if (source_level.value == .str) source_level.value.str else null, .label = source_level.label };
        dest.* = .{ .name = spec.input.ds.columns.items[source.column].name, .levels = levels };
    }
    var covariates: std.ArrayList(store.Covariate) = .empty;
    const effects = try a.alloc(store.Effect, spec.effects.len);
    for (effects, spec.effects, d.effects) |*dest, source, block| {
        const factors = try a.alloc(store.Factor, source.variables.len);
        for (factors, source.variables) |*factor, ci| {
            const name = spec.input.ds.columns.items[ci].name;
            const class_index = std.mem.indexOfScalar(usize, spec.classes, ci);
            factor.* = .{ .name = name, .class_index = class_index };
            if (class_index == null) {
                var found = false;
                for (covariates.items) |v| {
                    found = found or std.ascii.eqlIgnoreCase(v.name, name);
                }
                if (!found) {
                    var sum: f64 = 0;
                    var count: f64 = 0;
                    for (d.observations, d.frequencies) |observation, frequency| {
                        sum += observation.cells[ci].num * frequency;
                        count += frequency;
                    }
                    try covariates.append(a, .{ .name = name, .mean = sum / count });
                }
            }
        }
        dest.* = .{ .name = source.name, .start = block.start, .len = block.len, .factors = factors };
    }
    return .{ .procedure = "GLM", .input = spec.input.ds.name, .response = spec.input.ds.columns.items[d.response].name, .label = if (spec.store) |request| request.label else "", .created_unix_seconds = @intCast(@divFloor(std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds, std.time.ns_per_s)), .intercept = spec.intercept, .effects = effects, .classes = classes, .covariates = covariates.items, .coefficients = fit.coefficients, .covariance = fit.covariance, .df_error = fit.df_error, .mse = fit.mse, .n_used = fit.n_used };
}
pub fn save(cx: proc.ProcCtx, spec: parsing.Spec, d: design.Design, result: math.Result) diag.Error!void {
    if (spec.store) |request| try store.save(cx, request, try model(cx, spec, d, result));
}
