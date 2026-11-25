//! STAT-COMMON-012: verified III/IV equality domains and explicit missing-cell gaps.
const std = @import("std");
const testing = std.testing;
const A = std.mem.Allocator;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const glm = @import("glm.zig");
const math = @import("glm_fit.zig");
const policy = @import("glm_type34.zig");
const render = @import("glm_render.zig");
const Analysis = struct { spec: glm.Spec, data: glm.design.Design, result: math.Result };
fn parseDesign(cx: proc.ProcCtx, source: []const u8) !struct { spec: glm.Spec, data: glm.design.Design } {
    const spec = try glm.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try @import("data_selection.zig").View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    return .{ .spec = spec, .data = try glm.design.build(cx, spec, view, spec.responses[0]) };
}
fn analyze(cx: proc.ProcCtx, source: []const u8) !Analysis {
    const parsed = try parseDesign(cx, source);
    return .{ .spec = parsed.spec, .data = parsed.data, .result = try glm.fitDesign(cx, parsed.spec, parsed.data) };
}
fn cells(a: A, lib: *Library, values: []const f64, reverse: bool) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cells");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .char);
    _ = try ds.addColumn("y", .num);
    for (0..values.len) |j| {
        const i = if (reverse) values.len - 1 - j else j;
        try ds.appendRow(&.{ .{ .str = if (i < 4) "A1" else "A2" }, .{ .str = if ((i / 2) % 2 == 0) "B1" else "B2" }, .{ .num = values[i] } });
    }
    try lib.put("cells", ds);
}

test "COMMON012 complete unbalanced III IV hypotheses use equal cells and orthogonal effects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try cells(a, &lib, &.{ 12, 14, 11, 9, 20, 18, 17 }, false);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const r = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss3 ss4; run;");
    try testing.expectEqual(math.TypeIVBasis.complete_factorial, r.result.type_iv_basis.?);
    const contrasts = [_][4]f64{ .{ 0.5, 0.5, -0.5, -0.5 }, .{ 0.5, -0.5, 0.5, -0.5 }, .{ 1, -1, -1, 1 } };
    const means = [_]f64{ 13, 10, 19, 17 };
    const counts = [_]f64{ 2, 2, 2, 1 };
    const expected_l = [_][4]f64{ .{ 0, 2, 0, 0 }, .{ 0, 0, 2, 0 }, .{ 0, 0, 0, 4 } };
    // In the full SAS dummy basis, Table 16.9 gives main-effect higher-order
    // coefficients +/-1/2, orthogonal to the interaction vector (+1,-1,-1,+1).
    for (contrasts[0..2]) |main| {
        var dot: f64 = 0;
        for (main, contrasts[2]) |u, v| dot += u * v;
        try testing.expectEqual(@as(f64, 0), dot);
    }
    for (contrasts, expected_l, 0..) |c, l, e| {
        var estimate: f64 = 0;
        var variance: f64 = 0;
        for (c, means, counts) |value, mean, count| {
            estimate += value * mean;
            variance += value * value / count;
        }
        var lbeta: f64 = 0;
        var lgl: f64 = 0;
        for (l, 0..) |value, j| {
            lbeta += value * r.result.model.fit.coefficients[j];
            for (l, 0..) |other, k| lgl += value * r.result.model.fit.covariance_unscaled[j * 4 + k] * other;
        }
        try testing.expectApproxEqAbs(estimate, lbeta, 1e-11);
        try testing.expectApproxEqAbs(variance, lgl, 1e-11);
        const expected = estimate * estimate / variance;
        for ([_]math.EffectTest{ r.result.type_iii[e], r.result.type_iv[e] }) |effect| {
            try testing.expectEqual(@as(usize, 1), effect.df);
            try testing.expectApproxEqAbs(expected, effect.ss, 1e-10);
            try testing.expectApproxEqAbs(expected / 2, effect.f_value, 1e-10);
            const f = expected / 2;
            const p = 1 - (2.0 / std.math.pi) * (std.math.atan(@sqrt(f / 3)) + @sqrt(3 * f) / (f + 3));
            try testing.expectApproxEqAbs(p, effect.p_value, 1e-12);
        }
    }
    var output: std.ArrayList(u8) = .empty;
    try render.render(cx, &output, r.spec, r.data, r.result);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type III SS") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type IV SS") != null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type I SS") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "Type II SS") == null);
    // Renderer must not produce an IV heading from an unvalidated III result.
    var unchecked = r.result;
    unchecked.type_iv_basis = null;
    output.clearRetainingCapacity();
    try testing.expectError(error.ParseError, render.render(cx, &output, r.spec, r.data, unchecked));
    try testing.expectEqual(@as(usize, 0), output.items.len);
}

test "COMMON012 balanced cells and reordered effect and level declarations preserve III IV" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |balanced| {
        const values: []const f64 = if (balanced) &.{ 12, 14, 11, 9, 20, 18, 16, 18 } else &.{ 12, 14, 11, 9, 20, 18, 17 };
        var lib = Library.init(a);
        try cells(a, &lib, values, false);
        var d = diag.Diagnostics.init(a);
        const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
        const original = try analyze(cx, "proc glm order=data plots=none; class A B; model y=A B A*B / ss3 ss4; run;");
        try cells(a, &lib, values, true);
        const reversed = try analyze(cx, "proc glm order=data plots=none; class B A; model y=B A B*A / ss4 ss3; run;");
        const expected = if (balanced) [_]f64{ 84.5, 12.5, 0.5 } else [_]f64{ 67.6, 10, 0.4 };
        for (expected, [_]usize{ 1, 0, 2 }, 0..) |ss, j, i| {
            try testing.expectApproxEqAbs(ss, original.result.type_iv[i].ss, 1e-10);
            try testing.expectApproxEqAbs(ss, reversed.result.type_iii[j].ss, 1e-10);
            try testing.expectApproxEqAbs(ss, reversed.result.type_iv[j].ss, 1e-10);
        }
        try testing.expectEqualStrings("A2", reversed.data.classes[1].levels[0].label);
        try testing.expect(!d.hasErrors());
    }
}

test "COMMON012 missing corner permits uncontained main effects but rejects interaction III IV" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try cells(a, &lib, &.{ 1, 3, 5, 7, 9, 11 }, false);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const additive = try analyze(cx, "proc glm plots=none; class A B; model y=A B / ss3 ss4; run;");
    try testing.expectEqual(math.TypeIVBasis.no_contained_effects, additive.result.type_iv_basis.?);
    try testing.expect(!try policy.completeCells(a, additive.data, &.{ .{ .classes = &.{0} }, .{ .classes = &.{1} } }));
    for (additive.result.type_iv, [_]f64{ 64, 16 }) |effect, expected| {
        try testing.expectEqual(@as(usize, 1), effect.df);
        try testing.expectApproxEqAbs(expected, effect.ss, 1e-10);
    }
    for ([_][]const u8{ "ss3", "ss4", "ss3 ss4", "ss1 ss4", "ss2 ss3" }) |options| {
        var diagnostics = diag.Diagnostics.init(a);
        var local = cx;
        local.diags = &diagnostics;
        var output: std.ArrayList(u8) = .empty;
        const source = try std.fmt.allocPrint(a, "proc glm plots=none; class A B; model y=A B A*B / {s}; run;", .{options});
        try testing.expectError(error.ParseError, glm.run(local, &output, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.hasErrors());
        try testing.expectEqual(@as(usize, 0), output.items.len);
    }
    // Existing rank-aware I/II paths remain available for the same empty cell.
    const sequential = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss1 ss2; run;");
    try testing.expectEqual(@as(usize, 0), sequential.result.type_i[2].df);
    try testing.expectEqual(@as(usize, 0), sequential.result.type_ii[2].df);
}

test "COMMON012 full rank alone does not prove complete factorial applicability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "three");
    for ([_][]const u8{ "A", "B", "C" }) |name| _ = try ds.addColumn(name, .char);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("w", .num);
    _ = try ds.addColumn("f", .num);
    // Seven of eight cells, replicated twice: N=14 exceeds the nominal cell
    // count, and the model with all two-way terms is still full rank seven.
    for (0..7) |cell| for (0..2) |rep| {
        try ds.appendRow(&.{ .{ .str = if (cell & 4 == 0) "1" else "2" }, .{ .str = if (cell & 2 == 0) "1" else "2" }, .{ .str = if (cell & 1 == 0) "1" else "2" }, .{ .num = @floatFromInt(1 + cell * 2 + rep * 2) }, .{ .num = 1 }, .{ .num = 1 } });
    };
    // These raw rows do not populate the absent cell after FREQ/WEIGHT filtering.
    try ds.appendRow(&.{ .{ .str = "2" }, .{ .str = "2" }, .{ .str = "2" }, .{ .num = 20 }, .{ .num = 0 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .str = "2" }, .{ .str = "2" }, .{ .str = "2" }, .{ .num = 20 }, .{ .num = 1 }, .{ .num = 0 } });
    var lib = Library.init(a);
    try lib.put("three", &ds);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const parsed = try parseDesign(cx, "proc glm plots=none; class A B C; weight w; freq f; model y=A B C A*B A*C B*C / ss4; run;");
    try testing.expectEqual(@as(usize, 14), parsed.data.n);
    try testing.expectEqual(@as(usize, 16), parsed.data.read);
    const effects = try a.alloc(math.Effect, parsed.data.effects.len);
    for (effects, parsed.data.effects) |*dest, source| dest.* = .{ .start = source.start, .len = source.len };
    var numeric = try math.fit(a, parsed.data.x, parsed.data.y, parsed.data.n, parsed.data.p, effects, .{});
    defer numeric.deinit(a);
    try testing.expectEqual(@as(usize, 7), numeric.model.fit.rank);
    try testing.expectEqual(@as(usize, 7), parsed.data.p);
    try testing.expectError(error.ParseError, glm.fitDesign(cx, parsed.spec, parsed.data));
    try testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "missing CLASS combinations") != null);
    // C is unused in this second model: its missing joint combination must not
    // falsely invalidate the complete observed A*B factorial.
    const ab = try analyze(cx, "proc glm plots=none; class A B C; weight w; freq f; model y=A B A*B / ss4; run;");
    try testing.expectEqual(math.TypeIVBasis.complete_factorial, ab.result.type_iv_basis.?);
}

test "COMMON012 multi-column IV and explicit table combinations use actual effect rank" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "groups");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 3, 4, 6, 8 }, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 2) "A" else if (i < 4) "B" else "C" }, .{ .num = y } });
    var lib = Library.init(a);
    try lib.put("groups", &ds);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const r = try analyze(cx, "proc glm plots=none; class g; model y=g / ss1 ss2 ss3 ss4; run;");
    const effect = r.result.type_iv[0];
    try testing.expectEqual(@as(usize, 2), effect.df);
    try testing.expectApproxEqAbs(@as(f64, 25.2), effect.ss, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 6.3), effect.f_value, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 7.3), effect.p_value, 1e-12);
    var output: std.ArrayList(u8) = .empty;
    try render.render(cx, &output, r.spec, r.data, r.result);
    for ([_][]const u8{ "Type I SS", "Type II SS", "Type III SS", "Type IV SS" }) |heading| try testing.expectEqual(@as(usize, 1), std.mem.count(u8, output.items, heading));
    for ([_][]const u8{ "ss3", "ss4" }) |option| {
        const source = try std.fmt.allocPrint(a, "proc glm plots=none; class g; model y=g / {s}; run;", .{option});
        const single = try analyze(cx, source);
        output.clearRetainingCapacity();
        try render.render(cx, &output, single.spec, single.data, single.result);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, output.items, "Source DF Type"));
    }
    try testing.expectError(error.ParseError, glm.parse(cx, try lex.tokenize(a, "proc glm; class g; model y=g / ss4=1; run;", &d)));
}

fn allocationCheck(allocator: A) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try cells(a, &lib, &.{ 12, 14, 11, 9, 20, 18, 17 }, false);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    var r = try analyze(cx, "proc glm plots=none; class A B; model y=A B A*B / ss4; run;");
    defer r.result.deinit(a);
}

test "COMMON012 Type IV applicability and result allocation failures release storage" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationCheck, .{});
}
