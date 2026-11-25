//! STAT-REG-003: a numeric MODEL design, independently calculable by symmetry.
//! SAS/STAT 15.4 physical p.8576: numeric responses/regressors and optional labels;
//! p.8583: NOINT removes the otherwise implicit intercept. No CLASS coding or
//! implicit polynomial/interaction construction is valid in PROC REG MODEL.
const std = @import("std");
const reg = @import("reg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const proc = @import("../proc.zig");
const numerical = @import("reg_diagnostics.zig");

test "STAT-REG-003 MODEL roles and NOINT produce the documented numeric design" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var ds = Dataset.init(a, "corners");
    // Deliberately different from MODEL order, so descriptor order cannot
    // accidentally masquerade as correct response and regressor resolution.
    for ([_][]const u8{ "z", "response_b", "x", "response_a" }) |name| _ = try ds.addColumn(name, .num);
    // Four corners: x,z = (-1,-1),(-1,1),(1,-1),(1,1).
    // The columns 1,x,z,x*z are mutually orthogonal, each with squared norm 4.
    // response_a = 10 + 2*x - 3*z + x*z;
    // response_b = -4 + x/2 + 5*z + 2*x*z.
    const rows = [_][4]f64{
        .{ -1, -7.5, -1, 12 },
        .{ 1, -1.5, -1, 4 },
        .{ -1, -10.5, 1, 14 },
        .{ 1, 3.5, 1, 10 },
    };
    for (rows) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] } });
    try lib.put("corners", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const tokens = try lex.tokenize(a, "proc reg data=corners;" ++
        " pair: model response_a response_b = x z;" ++
        " origin: model response_a = x z / noint; run;", &d);
    const spec = try reg.parse(cx, tokens);
    try std.testing.expectEqual(@as(usize, 3), spec.models.len);
    const with_intercept = [_]f64{ 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1 };
    const without_intercept = [_]f64{ -1, -1, -1, 1, 1, -1, 1, 1 };
    const answers = [_]struct {
        label: []const u8,
        response: usize,
        beta: []const f64,
        sse: f64,
        df_error: usize,
    }{
        .{ .label = "pair", .response = 3, .beta = &.{ 10, 2, -3 }, .sse = 4, .df_error = 1 },
        .{ .label = "pair", .response = 1, .beta = &.{ -4, 0.5, 5 }, .sse = 16, .df_error = 1 },
        .{ .label = "origin", .response = 3, .beta = &.{ 2, -3 }, .sse = 404, .df_error = 2 },
    };
    for (spec.models, answers, 0..) |model, answer, i| {
        try std.testing.expectEqualStrings(answer.label, model.label);
        try std.testing.expectEqual(answer.response, model.dependent);
        try std.testing.expectEqualSlices(usize, &.{ 2, 0 }, model.regressors);
        try std.testing.expectEqual(i != 2, model.intercept);
        const selected = try reg.select(cx, spec, model, ds.rows.items);
        try std.testing.expectEqualSlices(f64, if (model.intercept) &with_intercept else &without_intercept, selected.x);
        try std.testing.expectEqualSlices(f64, if (answer.response == 3) &.{ 12, 4, 14, 10 } else &.{ -7.5, -1.5, -10.5, 3.5 }, selected.y);
        const result = try numerical.fit(a, selected.x, selected.y, selected.y.len, selected.columns, null, model.intercept, model.singular);
        // Every operation in this small orthogonal design is dyadic. Exact
        // coefficient/SSE comparisons are intentional, not broad tolerances.
        try std.testing.expectEqualSlices(f64, answer.beta, result.fit.coefficients);
        try std.testing.expectEqual(answer.sse, result.fit.sse);
        try std.testing.expectEqual(answer.df_error, result.fit.df_error);
        try std.testing.expectEqual(@as(usize, 4), result.fit.n_used);
    }
    try std.testing.expect(!d.hasErrors());
}

test "STAT-REG-003 character regressors are invalid rather than implicit CLASS effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var ds = Dataset.init(a, "categories");
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("group", .char);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .str = "A" } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .str = "B" } });
    try lib.put("categories", &ds);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    const tokens = try lex.tokenize(a, "proc reg data=categories;model y=group;run;", &d);
    try std.testing.expectError(error.ParseError, reg.run(cx, &out, tokens));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "numeric") != null);
}
