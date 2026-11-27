//! MIXED structural listing from real declarations/designs, never estimates.
const std = @import("std");
const declarations = @import("mixed_parse.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const input = @import("mixed_input.zig");
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), s: declarations.Spec, m: model.Spec, group: input.Group, x: fixed.Design, z: random.Design) !void {
    return renderRouted(a, out, s, m, group, x, z, null);
}
pub fn renderRouted(a: std.mem.Allocator, out: *std.ArrayList(u8), s: declarations.Spec, m: model.Spec, group: input.Group, x: fixed.Design, z: random.Design, route: ?*@import("mixed_ods_route.zig").Router) !void {
    try out.appendSlice(a, "The Mixed Procedure\n\n");
    if (!s.options.noinfo) {
        const start = out.items.len;
        const raw = try std.ascii.allocUpperString(a, s.input.ds.name);
        const name = if (std.mem.indexOfScalar(u8, raw, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{raw}) else raw;
        try out.print(a, "Model Information\n\nData Set {s}\nDependent Variable {s}\nCovariance Structure {s}\nEstimation Method {s}\nResidual Variance Method {s}\nFixed Effects SE Method Model-Based\nDegrees of Freedom Method {s}\n\n", .{
            name,
            s.input.ds.columns.items[m.matrix.response].name,
            if (z.components.len == 0) @as([]const u8, "Diagonal") else "Variance Components",
            if (s.options.method == .type3) @as([]const u8, "Type 3") else try std.ascii.allocUpperString(a, @tagName(s.options.method)),
            if (s.options.method == .type3) @as([]const u8, "Factor") else if (s.options.noprofile) "Parameter" else "Profile",
            if (m.options.ddfm == .residual or z.components.len == 0) @as([]const u8, "Residual") else "Containment",
        });
        if (route) |r| try r.finish(a, out, start, "ModelInfo");
    }
    if (x.matrix.classes.len > 0) {
        const start = out.items.len;
        try out.appendSlice(a, "Class Level Information\n\nClass Levels Values\n\n");
        for (x.matrix.classes) |class| {
            try out.print(a, "{s} {d}", .{ s.input.ds.columns.items[class.column].name, class.map.levels.len });
            for (class.map.levels) |level| try out.print(a, " {s}", .{std.mem.trim(u8, level.label, " ")});
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
        if (route) |r| try r.finish(a, out, start, "ClassLevels");
    }
    if (!s.options.noinfo) {
        var start = out.items.len;
        try out.print(a, "Dimensions\n\nCovariance Parameters {d}\nColumns in X {d}\nColumns in Z {d}\nSubjects {d}\nMax Obs per Subject {d}\n\n", .{ z.components.len + 1, x.matrix.p, z.q, z.subject_count, z.max_obs_per_subject });
        if (route) |r| try r.finish(a, out, start, "Dimensions");
        start = out.items.len;
        try out.print(a, "Number of Observations\n\nNumber of Observations Read {d}\nNumber of Observations Used {d}\nNumber of Observations Not Used {d}\n\n", .{ group.read_count, x.matrix.n, group.read_count - x.matrix.n });
        if (route) |r| try r.finish(a, out, start, "NObs");
    }
}

test "MIXED001 structural output derives class and dimension counts and honors NOINFO" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "trial");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .str = "B" }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = 4 } });
    try ds.appendRow(&.{ .{ .str = "A" }, .{ .num = 5 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("trial", &ds);
    var d = @import("../diag.zig").Diagnostics.init(a);
    const cx = @import("../proc.zig").ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    var s = try declarations.parse(cx, try @import("../lexer.zig").tokenize(a, "proc mixed;class group;model y=group;run;", &d));
    const m = try model.parse(cx, s.input.ds, s.statements, s.options.order, s.options.alpha);
    const groups = try input.prepare(cx, s, m.required_columns);
    const x = try fixed.build(cx, m, groups[0].selected);
    const rs = try random.parse(cx, s.input.ds, m.matrix, s.statements);
    const z = try random.build(cx, rs, groups[0].selected);
    var out: std.ArrayList(u8) = .empty;
    try render(a, &out, s, m, groups[0], x, z);
    try std.testing.expectEqualStrings("The Mixed Procedure\n\nModel Information\n\nData Set WORK.TRIAL\nDependent Variable y\nCovariance Structure Diagonal\nEstimation Method REML\nResidual Variance Method Profile\nFixed Effects SE Method Model-Based\nDegrees of Freedom Method Residual\n\nClass Level Information\n\nClass Levels Values\n\ngroup 2 A B\n\nDimensions\n\nCovariance Parameters 1\nColumns in X 3\nColumns in Z 0\nSubjects 1\nMax Obs per Subject 3\n\nNumber of Observations\n\nNumber of Observations Read 3\nNumber of Observations Used 3\nNumber of Observations Not Used 0\n\n", out.items);
    s.options.noinfo = true;
    out.clearRetainingCapacity();
    try render(a, &out, s, m, groups[0], x, z);
    try std.testing.expectEqualStrings("The Mixed Procedure\n\nClass Level Information\n\nClass Levels Values\n\ngroup 2 A B\n\n", out.items);
}
