//! Observed population margins, S154 physical pp.4146–4147.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const coded = @import("design_matrix.zig");
const population = @import("glm_lsmeans_at.zig");
fn matches(pop: population.Population, classes: []const coded.Class, row: usize, values: []const ?usize) bool {
    for (values, classes, pop.maps) |value, class, map| if (value) |level| {
        if (map.row_to_level[row] != map.row_to_level[class.map.levels[level].first_row]) return false;
    };
    return true;
}
pub fn classCoefficient(cx: proc.ProcCtx, pop: population.Population, classes: []const coded.Class, target: []const ?usize, column: []const ?usize, bylevel: bool) diag.Error!f64 {
    const free = try cx.arena.dupe(?usize, column);
    for (free, target) |*value, fixed| if (fixed != null) { value.* = null; };
    var numerator: f128 = 0;
    var denominator: f128 = 0;
    for (pop.observations, pop.map_rows) |observation, row| {
        if (bylevel and !matches(pop, classes, row, target)) continue;
        const weight = @as(f128, observation.frequency.num) * observation.weight.num;
        denominator += weight;
        if (matches(pop, classes, row, free)) numerator += weight;
    }
    if (!(denominator > 0)) return error.ExecError;
    return @floatCast(numerator / denominator);
}
pub fn covariateCoefficient(cx: proc.ProcCtx, pop: population.Population, classes: []const coded.Class, target: []const ?usize, variables: []const usize) diag.Error!f64 {
    var numerator: f128 = 0;
    var denominator: f128 = 0;
    for (pop.observations, pop.map_rows) |observation, row| {
        if (!matches(pop, classes, row, target)) continue;
        const weight = @as(f128, observation.frequency.num) * observation.weight.num;
        var product: f128 = 1;
        for (variables) |column| product *= observation.cells[column].num;
        numerator += weight * product;
        denominator += weight;
    }
    if (!(denominator > 0)) return error.ExecError;
    const value: f64 = @floatCast(numerator / denominator);
    if (!std.math.isFinite(value)) return proc.failGap(cx.diags, 0, "PROC GLM: BYLEVEL covariate moment exceeds the supported numerical domain", .{});
    return value;
}
