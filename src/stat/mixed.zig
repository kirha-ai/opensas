//! PROC MIXED declaration/input entry point. Estimation is separately gated.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
pub const declarations = @import("mixed_parse.zig");
pub const input = @import("mixed_input.zig");
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    const model = @import("mixed_model.zig");
    const fixed = @import("mixed_design.zig");
    const random = @import("mixed_random.zig");
    const math = @import("mixed_fit.zig");
    const render = @import("mixed_render.zig");
    const info = @import("mixed_info.zig");
    const spec = try declarations.parse(cx, tokens);
    // PROC ALPHA controls covariance-parameter CIs, not MODEL ALPHA.
    const m = try model.parse(cx, spec.input.ds, spec.statements, spec.options.order, 0.05);
    const r = try random.parse(cx, spec.input.ds, m.matrix, spec.statements);
    var required: std.ArrayList(usize) = .empty;
    try required.appendSlice(cx.arena, m.required_columns);
    for (r.required_columns) |ci| if (std.mem.indexOfScalar(usize, required.items, ci) == null) try required.append(cx.arena, ci);
    const groups = try input.prepare(cx, spec, required.items);
    if (spec.options.method != .reml) return proc.failGap(cx.diags, spec.line, "PROC MIXED: model estimation is not implemented for METHOD={s}", .{@tagName(spec.options.method)});
    if (spec.options.noprofile or spec.options.alpha_explicit) return proc.failGap(cx.diags, spec.line, "PROC MIXED: unprofiled estimation or covariance-parameter confidence limits are not implemented", .{});
    if (m.has_repeated) return proc.failGap(cx.diags, spec.line, "PROC MIXED: REPEATED covariance inference is not implemented", .{});
    if (m.options.solution or m.options.cl or m.options.intercept_test or m.options.alpha != 0.05) return proc.failGap(cx.diags, m.line, "PROC MIXED: requested fixed-effect solution or confidence-limit output is not implemented", .{});
    if (cx.listing) |listing| if (listing.filtered() or listing.trace != null) return proc.failGap(cx.diags, spec.line, "PROC MIXED: ODS table selection and TRACE routing are not implemented", .{});
    if (cx.graphics) |graphics| if (graphics.enabled == true and !spec.options.plots_none) return proc.failGap(cx.diags, spec.line, "PROC MIXED: ODS graphics are not implemented; specify PLOTS=NONE", .{});
    if (cx.capture) |capture| for ([_][]const u8{ "ModelInfo", "ClassLevels", "Dimensions", "NObs", "CovParms", "FitStatistics", "Tests3", "SolutionF", "SolutionR" }) |name| if (capture.wants(name)) return proc.failGap(cx.diags, spec.line, "PROC MIXED: ODS OUTPUT {s} is not implemented", .{name});
    if (groups.len == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: empty input analysis is not implemented", .{});
    for (groups) |group| {
        if (group.used_count == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: fully excluded BY-group analysis is not implemented", .{});
        const x = try fixed.build(cx, m, group.selected);
        const z = try random.build(cx, r, group.selected);
        if (x.matrix.n != z.n) return proc.failGap(cx.diags, spec.line, "PROC MIXED: fixed/random observation selection differs", .{});
        for (x.matrix.columns) |column| if (column.effect_name.len > spec.options.namelen) return proc.failGap(cx.diags, spec.line, "PROC MIXED: long effect-name presentation is not implemented", .{});
        const components = try cx.arena.alloc(math.Component, z.components.len);
        const names = try cx.arena.alloc([]const u8, z.components.len + 1);
        for (z.components, components, names[0..z.components.len]) |component, *target, *name| {
            target.* = .{ .name = component.name, .kernel = component.kernel, .columns = component.columns };
            name.* = component.name;
        }
        names[names.len - 1] = "Residual";
        const fit = math.fit(cx.arena, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components, .has_intercept = m.matrix.intercept, .singular = m.options.singular }, .{ .method = .reml, .maxiter = spec.options.maxiter, .maxfunc = spec.options.maxfunc, .bic_n = if (components.len == 0) null else @as(f64, @floatFromInt(if (z.subject_count > 1) z.subject_count else z.first_effect_levels)) }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: this estimation boundary is not implemented ({t})", .{err});
        if (!fit.converged) return proc.failGap(cx.diags, spec.line, "PROC MIXED: nonconverged-result reporting is not implemented ({t})", .{fit.status});
        var tests: std.ArrayList(render.NamedTest) = .empty;
        if (!m.options.notest) for (m.matrix.effects, 0..) |_, ei| {
            const contrast = try fixed.type3(cx, m, x, ei);
            const df = if (m.options.ddfm == .residual or z.components.len == 0) fit.df_error else try random.containmentDF(cx, r, x.matrix, z, ei, x.weights, m.options.singular);
            if (df == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: zero containment degrees-of-freedom inference is not implemented", .{});
            const tested = math.testContrast(cx.arena, fit, contrast.coefficients, contrast.rows, df) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: fixed-effect test is not implemented for this estimability boundary ({t})", .{err});
            try tests.append(cx.arena, .{ .name = contrast.name, .num_df = tested.num_df, .den_df = tested.den_df, .f = tested.f, .p = tested.p });
        };
        if (spec.roles.by.len > 0) try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.raw.observations[0].cells, spec.roles.by);
        try info.render(cx.arena, out, spec, m, group, x, z);
        render.render(cx.arena, out, fit, names, tests.items, .{ .noitprint = spec.options.noitprint, .notest = m.options.notest }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: numerical table rendering failed ({t})", .{err});
    }
}

const Testing = struct {
    lib: *@import("../exec.zig").Library,
    d: *diag.Diagnostics,
    cx: proc.ProcCtx,
    fn init(a: std.mem.Allocator) !Testing {
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = @import("../exec.zig").Library.init(a);
        const d = try a.create(diag.Diagnostics);
        d.* = diag.Diagnostics.init(a);
        return .{ .lib = lib, .d = d, .cx = .{ .arena = a, .lib = lib, .diags = d } };
    }
    fn parse(self: Testing, code: []const u8) !declarations.Spec {
        return declarations.parse(self.cx, try lex.tokenize(self.cx.arena, code, self.d));
    }
    const heights_values = [_][3]f64{ .{ 1, 0, 67 }, .{ 1, 0, 66 }, .{ 1, 0, 64 }, .{ 1, 1, 71 }, .{ 1, 1, 72 }, .{ 2, 0, 63 }, .{ 2, 0, 63 }, .{ 2, 0, 67 }, .{ 2, 1, 69 }, .{ 2, 1, 68 }, .{ 2, 1, 70 }, .{ 3, 0, 63 }, .{ 3, 1, 64 }, .{ 4, 0, 67 }, .{ 4, 0, 66 }, .{ 4, 1, 67 }, .{ 4, 1, 67 }, .{ 4, 1, 69 } };
    fn heights(self: Testing, copies: usize) !*Dataset {
        const ds = try self.cx.arena.create(Dataset);
        ds.* = Dataset.init(self.cx.arena, "heights");
        _ = try ds.addColumn("Family", .num);
        _ = try ds.addColumn("Gender", .char);
        _ = try ds.addColumn("Height", .num);
        _ = try ds.addColumn("batch", .num);

        for (0..copies) |copy| for (heights_values) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .str = if (row[1] == 0) "F" else "M" }, .{ .num = row[2] }, .{ .num = @floatFromInt(copy + 1) } });
        try self.lib.put("heights", ds);
        return ds;
    }
    fn sample(self: Testing) !*Dataset {
        const ds = try self.cx.arena.create(Dataset);
        ds.* = Dataset.init(self.cx.arena, "sample");
        for ([_][]const u8{ "g", "y", "x", "w" }) |name| _ = try ds.addColumn(name, .num);
        _ = try ds.addColumn("id", .char);
        const rows = [_][4]f64{ .{ 1, 10, 1, 0.5 }, .{ 1, 20, 2, 0 }, .{ 1, 30, 3, -1 }, .{ 2, 40, 4, 2.5 }, .{ 2, 50, 5, std.math.nan(f64) }, .{ 2, std.math.nan(f64), 6, 1 } };
        for (rows) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] }, .{ .str = "" } });
        try self.lib.put("sample", ds);
        return ds;
    }
};

test "MIXED001 defaults explicit methods order bounds and retained model interface" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    _ = try h.sample();
    const defaults = try h.parse("proc mixed; class g; model y=x g; random g; run;");
    try std.testing.expectEqual(declarations.Method.reml, defaults.options.method);
    try std.testing.expectEqual(@import("class_levels.zig").Order.formatted, defaults.options.order);
    try std.testing.expectEqual(@as(f64, 0.05), defaults.options.alpha);
    try std.testing.expect(!defaults.options.alpha_explicit);
    try std.testing.expectEqual(@as(usize, 50), defaults.options.maxiter);
    try std.testing.expectEqual(@as(usize, 150), defaults.options.maxfunc);
    try std.testing.expectEqual(@as(usize, 20), defaults.options.namelen);
    try std.testing.expect(defaults.id_columns == null);
    try std.testing.expectEqual(@as(usize, 3), defaults.statements.len);
    try std.testing.expectEqualStrings("y", defaults.statements[1].tokens[0].text);
    for (std.enums.values(declarations.Method)) |method| {
        const code = try std.fmt.allocPrint(h.cx.arena, "proc mixed data=sample method={s} order=data alpha=.1 maxiter=12 maxfunc=45 namelen=32 noprofile noinfo noitprint plots=none; model y=x; run;", .{@tagName(method)});
        const s = try h.parse(code);
        try std.testing.expectEqual(method, s.options.method);
        try std.testing.expectEqual(@import("class_levels.zig").Order.data, s.options.order);
        try std.testing.expectEqual(@as(f64, 0.1), s.options.alpha);
        try std.testing.expect(s.options.alpha_explicit);
        try std.testing.expectEqual(@as(usize, 12), s.options.maxiter);
        try std.testing.expectEqual(@as(usize, 45), s.options.maxfunc);
        try std.testing.expectEqual(@as(usize, 32), s.options.namelen);
        try std.testing.expect(s.options.noprofile and s.options.noinfo and s.options.noitprint and s.options.plots_none);
    }
}

test "MIXED001 WHERE BY ID and precision-weight selection preserve physical rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    const original = try h.sample();
    const s = try h.parse("proc mixed data=sample; where x>1; by id; by g; id id; weight w; model y=x; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, s.roles.by);
    try std.testing.expectEqualSlices(usize, &.{4}, s.id_columns.?);
    const groups = try input.prepare(h.cx, s, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 2), groups.len);
    try std.testing.expectEqual(@as(usize, 2), groups[0].read_count);
    try std.testing.expectEqual(@as(usize, 0), groups[0].used_count);
    try std.testing.expectEqual(@as(usize, 3), groups[1].read_count);
    try std.testing.expectEqual(@as(usize, 1), groups[1].used_count);
    try std.testing.expectEqual(@as(usize, 2), groups[1].excluded_count);
    const row = groups[1].selected.observations[0];
    try std.testing.expectEqual(@as(usize, 4), row.source_number);
    try std.testing.expectEqual(@as(f64, 2.5), row.weight.num);
    try std.testing.expectEqual(@as(f64, 1), row.frequency.num);
    try std.testing.expectEqualStrings("", row.cells[4].str); // missing ID is retained
    try std.testing.expectEqual(@as(usize, 6), original.rows.items.len);
    const none = try h.parse("proc mixed data=sample(firstobs=2 obs=4); id; model y=x; run;");
    try std.testing.expectEqual(@as(usize, 0), none.id_columns.?.len);
    const selected = try input.prepare(h.cx, none, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 3), selected[0].used_count);
    try std.testing.expectEqual(@as(usize, 2), selected[0].selected.observations[0].source_number);
}

test "MIXED001 descending and NOTSORTED groups include empty selections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    const ds = try h.sample();
    std.mem.reverse([]const Value, ds.rows.items);
    var s = try h.parse("proc mixed; by descending g; weight w; model y=x; run;");
    var grouped = try input.prepare(h.cx, s, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 2), grouped.len);
    try std.testing.expectEqual(@as(f64, 2), grouped[0].raw.observations[0].cells[0].num);
    s = try h.parse("proc mixed; by g notsorted; weight w; model y=x; run;");
    grouped = try input.prepare(h.cx, s, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 2), grouped.len);
    s = try h.parse("proc mixed; by g; model y=x; run;");
    try std.testing.expectError(error.ParseError, input.prepare(h.cx, s, &.{1}));
    ds.rows.clearRetainingCapacity();
    const empty = try h.parse("proc mixed; model y=x; run;");
    const groups = try input.prepare(h.cx, empty, &.{1});
    try std.testing.expectEqual(@as(usize, 1), groups.len);
    try std.testing.expectEqual(@as(usize, 0), groups[0].read_count);
    try std.testing.expectEqual(@as(usize, 0), groups[0].used_count);
}

test "MIXED001 declarations diagnose invalid names and preserve unsupported option status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    _ = try h.sample();
    for ([_][]const u8{ "proc mixed alpha=0;run;", "proc mixed namelen=19;run;", "proc mixed method=banana;run;", "proc mixed order=banana;run;", "proc mixed;weight id;run;", "proc mixed;weight w x;run;", "proc mixed;id absent;run;", "proc mixed;by absent;run;", "proc mixed;model y=x;class g;run;", "proc mixed;freq w;run;" }) |code| {
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, h.parse(code));
        try std.testing.expect(!diag.gapHit());
    }
    for ([_][]const u8{ "proc mixed empirical;run;", "proc mixed plots=all;run;", "proc mixed;weight w;weight x;run;", "proc mixed;id id;id x;run;", "proc mixed;lsmeans g;run;" }) |code| {
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, h.parse(code));
        try std.testing.expect(diag.gapHit());
    }
    const before = h.d.count();
    try std.testing.expectError(error.ParseError, h.parse("proc mixed;\nweight absent;\nrun;"));
    try std.testing.expectEqual(@as(usize, 2), h.d.list.items[before].line);
}

test "MIXED001 unimplemented MIVQUE0 never reports successful output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    _ = try h.sample();
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(h.cx, &out, try lex.tokenize(h.cx.arena, "proc mixed method=mivque0;by g;model y=x;run;", h.d)));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), h.d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, try h.d.render(), "model estimation is not implemented") != null);
}

test "MIXED001 complete Heights inputs preserve eighteen observations in each BY group" {
    // Complete public input from S154 MIXED Getting Started, also used by
    // both original MIXED001 cases. Only input/group behavior is accepted;
    // no fixed/random-model numerical output is claimed by this test.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const h = try Testing.init(arena.allocator());
    _ = try h.heights(2);
    const values = Testing.heights_values;
    const s = try h.parse("proc mixed data=heights;by batch;class Family Gender;model Height=Gender Family Family*Gender;run;");
    const grouped = try input.prepare(h.cx, s, &.{ 0, 1, 2 });
    try std.testing.expectEqual(@as(usize, 2), grouped.len);
    for (grouped, 0..) |g, i| {
        try std.testing.expectEqual(@as(usize, 18), g.read_count);
        try std.testing.expectEqual(@as(usize, 18), g.used_count);
        try std.testing.expectEqual(@as(usize, 0), g.excluded_count);
        for (g.selected.observations, values, 0..) |obs, want, j| {
            try std.testing.expectEqual(@as(usize, i * 18 + j + 1), obs.source_number);
            try std.testing.expectEqual(want[0], obs.cells[0].num);
            try std.testing.expectEqualStrings(if (want[1] == 0) "F" else "M", obs.cells[1].str);
            try std.testing.expectEqual(want[2], obs.cells[2].num);
            try std.testing.expectEqual(@as(f64, 1), obs.weight.num);
        }
    }
    const random = try h.parse("proc mixed;class Family Gender;model Height=Gender;random Family Family*Gender;run;");
    const pooled = try input.prepare(h.cx, random, &.{ 0, 1, 2 });
    try std.testing.expectEqual(@as(usize, 1), pooled.len);
    try std.testing.expectEqual(@as(usize, 36), pooled[0].used_count);
    try std.testing.expectEqual(@as(usize, 3), random.statements.len);
    try std.testing.expectEqual(@FieldType(declarations.Statement, "kind").random, random.statements[2].kind);
}

test "MIXED006 real entry reproduces complete Heights fixed and random listing tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Testing.init(a);
    _ = try h.heights(1);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try run(h.cx, &out, try lex.tokenize(a, "proc mixed data=heights;class Family Gender;model Height=Gender Family Family*Gender;run;", h.d));
    try run(h.cx, &out, try lex.tokenize(a, "proc mixed;class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.d));
    const expected = try @import("ttest_test_assets.zig").listing(a, "tests/corpus/persist_mixed_heights.txt");
    var want = std.mem.tokenizeAny(u8, expected, " \t\r\n\x0c");
    var got = std.mem.tokenizeAny(u8, out.items, " \t\r\n\x0c");
    while (want.next()) |token| try std.testing.expectEqualStrings(token, got.next() orelse return error.TestExpectedEqual);
    try std.testing.expect(got.next() == null);
    try std.testing.expect(!h.d.hasErrors());
    try std.testing.expect(!diag.gapHit());
}

test "MIXED006 real BY entry reproduces complete grouped and pooled original listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Testing.init(a);
    const ds = try h.heights(2);
    ds.name = "_oracle_input";
    ds.columns.items[3].name = "_oracle_by";
    try h.lib.put("_oracle_input", ds);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try run(h.cx, &out, try lex.tokenize(a, "proc mixed data=_oracle_input;by _oracle_by;class Family Gender;model Height=Gender Family Family*Gender;run;", h.d));
    try run(h.cx, &out, try lex.tokenize(a, "proc mixed;class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.d));
    const expected = try @import("ttest_test_assets.zig").listing(a, "tests/corpus/persist_mixed_heights_by.txt");
    var want = std.mem.tokenizeAny(u8, expected, " \t\r\n\x0c");
    var got = std.mem.tokenizeAny(u8, out.items, " \t\r\n\x0c");
    while (want.next()) |token| try std.testing.expectEqualStrings(token, got.next() orelse return error.TestExpectedEqual);
    try std.testing.expect(got.next() == null);
    try std.testing.expect(!h.d.hasErrors());
    try std.testing.expect(!diag.gapHit());
}
