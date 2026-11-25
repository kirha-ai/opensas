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

/// A saturated 2x2 factorial with three observed cells has no estimable
/// interaction contrast. Each main effect has one unique contrast: compare
/// its two levels at the other factor's shared observed level. Consequently
/// Type III equals Type II for this specific pattern, regardless of cell counts.
/// This does not extend to larger empty-cell patterns or to Type IV requests.
pub fn singleEmpty2x2(spec: parse.Spec, d: design.Design, factors: []const math.Factors) bool {
    if (!spec.intercept or d.p != 4 or d.classes.len != 2 or factors.len != 3 or d.effects.len != 3) return false;
    for (d.classes) |class| if (class.levels.len != 2 or class.row_levels.len != d.n) return false;
    var main = [_]bool{ false, false };
    var interaction = false;
    for (factors, d.effects) |factor, effect| {
        if (factor.continuous.len != 0 or effect.len != 1) return false;
        if (factor.classes.len == 1) {
            const index: usize = if (factor.classes[0] == d.classes[0].column) 0 else if (factor.classes[0] == d.classes[1].column) 1 else return false;
            if (main[index]) return false;
            main[index] = true;
        } else if (factor.classes.len == 2) {
            if (interaction or factor.classes[0] == factor.classes[1]) return false;
            for (d.classes) |class| if (std.mem.indexOfScalar(usize, factor.classes, class.column) == null) return false;
            interaction = true;
        } else return false;
    }
    if (!main[0] or !main[1] or !interaction) return false;
    var seen = [_]bool{ false, false, false, false };
    for (0..d.n) |i| {
        const left = d.classes[0].row_levels[i] orelse return false;
        const right = d.classes[1].row_levels[i] orelse return false;
        if (left >= 2 or right >= 2) return false;
        seen[left * 2 + right] = true;
    }
    var count: usize = 0;
    for (seen) |present| {
        if (present) count += 1;
    }
    return count == 3;
}

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
    if (result.model.fit.rank != d.p) {
        if (!spec.ss4 and result.model.fit.rank == 3 and singleEmpty2x2(spec, d, factors)) {
            if (result.type_ii.len != factors.len) return error.ExecError;
            for (factors, result.type_ii) |factor, effect| {
                if (factor.classes.len == 2 and effect.df != 0) return error.ExecError;
                if (factor.classes.len == 1 and effect.df != 1) return error.ExecError;
            }
            @memcpy(result.type_iii, result.type_ii);
            return;
        }
        return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient Type III/IV estimable hypotheses are not implemented", .{});
    }
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
