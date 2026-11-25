//! STAT-COMMON-012: checked Type III/IV hypothesis applicability.
//! S154 physical pp.289–293: III=IV for effects not contained in others,
//! and for factorial designs without missing cells. This module verifies those
//! conditions before using the existing equal-cell Type III construction for IV.
//! General missing-cell orthogonal/distributive hypotheses remain explicit gaps.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const math = @import("glm_fit.zig");

/// Return completeness of the Cartesian product of MODEL's CLASS factors.
/// Ignore unused CLASS declarations and continuous predictors. Design rows have
/// already been filtered for missing response, FREQ and WEIGHT, so an unusable
/// observation cannot masquerade as a populated cell. Counts need not balance.
pub fn completeCells(a: std.mem.Allocator, d: design.Design, factors: []const math.Factors) diag.Error!bool {
    var classes: std.ArrayList(usize) = .empty;
    defer classes.deinit(a);
    for (factors) |factor| for (factor.classes) |column| {
        if (std.mem.indexOfScalar(usize, classes.items, column) == null) try classes.append(a, column);
    };
    const selected = try a.alloc(usize, classes.items.len);
    defer a.free(selected);
    var cells: usize = 1;
    for (classes.items, selected) |column, *index| {
        index.* = for (d.classes, 0..) |class, j| {
            if (class.column == column) break j;
        } else return error.ExecError;
        const count = d.classes[index.*].levels.len;
        if (count == 0) return false;
        cells = std.math.mul(usize, cells, count) catch return false;
        if (cells > d.n) return false;
    }
    const seen = try a.alloc(bool, cells);
    defer a.free(seen);
    @memset(seen, false);
    var observed: usize = 0;
    for (0..d.n) |row| {
        var index: usize = 0;
        for (selected) |j| {
            const class = d.classes[j];
            const level = class.row_levels[row] orelse return error.ExecError;
            if (level >= class.levels.len) return error.ExecError;
            index = index * class.levels.len + level;
        }
        if (!seen[index]) {
            seen[index] = true;
            observed += 1;
        }
    }
    return observed == cells;
}

/// Caller supplies the canonical sum-to-zero effect design, not a separate
/// overparameterized SOLUTION display. No general Type IV missing-cell results
/// are manufactured from a partial Type III table or from full rank alone.
pub fn prepare(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, factors: []const math.Factors, result: *math.Result) diag.Error!void {
    if (!spec.defaultSumsOfSquares() and !spec.ss3 and !spec.ss4) return;
    if (factors.len != spec.effects.len or result.type_iii.len != spec.effects.len) return error.ExecError;
    if (result.model.fit.rank != d.p) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient Type III/IV estimable hypotheses are not implemented", .{});
    var contained = false;
    for (factors) |inner| for (factors) |outer| {
        if (math.contains(outer, inner)) contained = true;
    };
    const basis: math.TypeIVBasis = if (!contained) .no_contained_effects else blk: {
        if (!try completeCells(cx.arena, d, factors)) return proc.failGap(cx.diags, 0, "PROC GLM: Type III/IV hypotheses for contained effects with missing CLASS combinations are not implemented", .{});
        break :blk .complete_factorial;
    };
    if (spec.ss4) {
        if (result.type_iv_basis != null) return error.ExecError;
        // The checked theorem gives the SAME hypothesis, hence the same SS,
        // rank, DF, F and p; recomputing an identical projection adds no content.
        result.type_iv = try cx.arena.dupe(math.EffectTest, result.type_iii);
        result.type_iv_basis = basis;
    }
}
