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
    const mixed_ods = @import("mixed_ods.zig");
    const parms = @import("mixed_parms.zig");
    const spec = try declarations.parse(cx, tokens);
    const parameter_spec = try parms.parse(cx, spec.statements);
    if (parameter_spec != null and spec.options.method != .reml) return proc.failGap(cx.diags, spec.line, "PROC MIXED: PARMS with METHOD={s} is not implemented", .{@tagName(spec.options.method)});
    if (parameter_spec) |parameters| if (parameters.data_name) |data_name| if (cx.lib.find(data_name)) |data| {
        for (spec.roles.by) |ci| if (data.indexOf(spec.input.ds.columns.items[ci].name) != null) return proc.failGap(cx.diags, spec.line, "PROC MIXED: BY-specific PARMSDATA matching is not implemented", .{});
    };
    // PROC ALPHA controls covariance-parameter CIs, not MODEL ALPHA.
    const m = try model.parse(cx, spec.input.ds, spec.statements, spec.options.order, 0.05);
    const r = try random.parse(cx, spec.input.ds, m.matrix, spec.statements);
    const repeated = @import("mixed_repeated.zig");
    const residual_spec = try repeated.parse(cx, spec.input.ds, m.matrix, spec.statements);
    var required: std.ArrayList(usize) = .empty;
    try required.appendSlice(cx.arena, m.required_columns);
    for (r.required_columns) |ci| if (std.mem.indexOfScalar(usize, required.items, ci) == null) try required.append(cx.arena, ci);
    if (residual_spec) |rs| for (rs.required_columns) |ci| if (std.mem.indexOfScalar(usize, required.items, ci) == null) try required.append(cx.arena, ci);
    const groups = try input.prepare(cx, spec, required.items);
    if (m.has_repeated and spec.options.method == .type3) return cx.diags.fail(error.ParseError, spec.line, "PROC MIXED: METHOD=TYPE3 does not permit a REPEATED statement", .{});
    if (m.has_repeated and (spec.options.method == .type1 or spec.options.method == .type2)) return cx.diags.fail(error.ParseError, spec.line, "PROC MIXED: METHOD=TYPE1/TYPE2 cannot be used with REPEATED", .{});
    if (spec.options.method != .reml and spec.options.method != .type3) return proc.failGap(cx.diags, spec.line, "PROC MIXED: model estimation is not implemented for METHOD={s}", .{@tagName(spec.options.method)});
    if ((spec.options.noprofile and parameter_spec == null) or spec.options.alpha_explicit) return proc.failGap(cx.diags, spec.line, "PROC MIXED: unprofiled estimation or covariance-parameter confidence limits are not implemented", .{});
    if (m.options.solution or m.options.cl or m.options.intercept_test or m.options.alpha != 0.05) return proc.failGap(cx.diags, m.line, "PROC MIXED: requested fixed-effect solution or confidence-limit output is not implemented", .{});
    try @import("mixed_plots.zig").validate(cx, spec, m);
    try @import("mixed_influence_run.zig").validate(cx, spec, m);
    if (spec.options.method == .type3) if (cx.capture) |capture| if (capture.wants("Type3")) return proc.failGap(cx.diags, spec.line, "PROC MIXED: ODS OUTPUT Type3 is not implemented", .{});
    if (groups.len == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: empty input analysis is not implemented", .{});
    for (groups, 0..) |group, by_index| {
        const group_start = out.items.len;
        var route = mixed_ods.routing.Router{ .selection = cx.listing, .prefix = if (spec.roles.by.len > 0) try std.fmt.allocPrint(cx.arena, "Mixed.ByGroup{d}", .{by_index + 1}) else "Mixed", .diags = if (cx.listing != null or cx.capture != null) cx.diags else null };
        if (group.used_count == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: fully excluded BY-group analysis is not implemented", .{});
        if (residual_spec) |rs| {
            _ = try repeated.layout(cx, rs, group.raw, group.selected);
            return proc.failGap(cx.diags, rs.line, "PROC MIXED REPEATED: TYPE={s} residual covariance estimation is not implemented", .{repeated.structureName(rs.kind)});
        }
        const x = try fixed.build(cx, m, group.selected);
        const z = try random.build(cx, r, group.selected);
        if (x.matrix.n != z.n) return proc.failGap(cx.diags, spec.line, "PROC MIXED: fixed/random observation selection differs", .{});
        for (x.matrix.columns) |column| if (column.effect_name.len > spec.options.namelen) return proc.failGap(cx.diags, spec.line, "PROC MIXED: long effect-name presentation is not implemented", .{});
        const inference_requests = try @import("mixed_contrasts.zig").parse(cx, m, z, spec.statements);
        const components = try cx.arena.alloc(math.Component, z.components.len);
        const names = try cx.arena.alloc([]const u8, z.components.len + 1);
        for (z.components, components, names[0..z.components.len]) |component, *target, *name| {
            target.* = .{ .name = component.name, .kernel = component.kernel, .columns = component.columns };
            name.* = component.name;
        }
        names[names.len - 1] = "Residual";
        if (spec.options.method == .type3) {
            try @import("mixed_theory_type3_run.zig").runRouted(cx, out, spec, m, r, group, x, z, components, names, &route);
            if (route.visible == 0) out.shrinkRetainingCapacity(group_start);
            continue;
        }
        const fit_model = math.Model{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components, .has_intercept = m.matrix.intercept, .singular = m.options.singular };
        const fit_options = math.Options{ .method = .reml, .maxiter = spec.options.maxiter, .maxfunc = spec.options.maxfunc, .convergence = spec.options.convergence, .criterion = spec.options.criterion, .absolute = spec.options.absolute, .bic_n = if (components.len == 0) null else @as(f64, @floatFromInt(if (z.subject_count > 1) z.subject_count else z.first_effect_levels)) };
        var parameter_search: ?parms.Result = null;
        const fit = if (parameter_spec) |parameters| blk: {
            parameter_search = try parms.execute(cx, fit_model, parameters, fit_options, spec.options.noprofile);
            break :blk parameter_search.?.fit;
        } else math.fit(cx.arena, fit_model, fit_options) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: this estimation boundary is not implemented ({t})", .{err});
        const usable_inference = fit.converged or fit.status == .evaluated;
        if (!usable_inference) try cx.diags.warnStatus(0, "Convergence criteria not met: {s} Last covariance estimates are retained; fixed-effect inference is not produced.", .{math.statusReason(fit.status)});
        var tests: std.ArrayList(render.NamedTest) = .empty;
        if (usable_inference and !m.options.notest) for (m.matrix.effects, 0..) |_, ei| {
            const contrast = try fixed.type3(cx, m, x, ei);
            const df = if (m.options.ddfm == .residual or z.components.len == 0) fit.df_error else try random.containmentDF(cx, r, x.matrix, z, ei, x.weights, m.options.singular);
            if (df == 0) return proc.failGap(cx.diags, spec.line, "PROC MIXED: zero containment degrees-of-freedom inference is not implemented", .{});
            const tested = math.testContrast(cx.arena, fit, contrast.coefficients, contrast.rows, df) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: fixed-effect test is not implemented for this estimability boundary ({t})", .{err});
            try tests.append(cx.arena, .{ .name = contrast.name, .num_df = tested.num_df, .den_df = tested.den_df, .f = tested.f, .p = tested.p });
        };
        try mixed_ods.publish(cx, spec, m, group, x, z, r, fit, names, tests.items, parameter_search, parameter_spec);
        route.converged = fit.converged;
        if (spec.roles.by.len > 0) try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.raw.observations[0].cells, spec.roles.by);
        var displayed_spec = spec;
        if (parameter_search) |search| displayed_spec.options.noprofile = !search.profile;
        try info.renderRouted(cx.arena, out, displayed_spec, m, group, x, z, &route);
        if (parameter_search) |search| try parms.renderSearchRouted(cx.arena, out, search, parameter_spec.?, &route);
        render.render(cx.arena, out, fit, names, tests.items, .{ .noitprint = spec.options.noitprint, .notest = m.options.notest or !usable_inference, .nofit = fit.status == .evaluated or !usable_inference, .parms_lrt = if (parameter_search) |search| search.likelihood_ratio else null, .route = &route }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, spec.line, "PROC MIXED: numerical table rendering failed ({t})", .{err});
        if (usable_inference) try @import("mixed_contrasts.zig").publishRouted(cx, out, m, r, x, z, fit, fit.variances, inference_requests, &route);
        if (usable_inference) try @import("mixed_influence_run.zig").publish(cx, out, spec, m, group, x, z, fit, if (parameter_search) |search| search.profile else true, &route);
        if (route.visible == 0) out.shrinkRetainingCapacity(group_start);
        if (usable_inference) try @import("mixed_plots.zig").execute(cx, spec, m, group, x, z, fit, if (spec.roles.by.len > 0) by_index + 1 else null);
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

test "MIXED017 real residual panels match manual studentized statistics and actual SVG coordinates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Testing.init(a);
    _ = try h.heights(1);
    var graphics = @import("graphics_svg.zig").Session{ .arena = a, .io = std.testing.io, .diags = h.d, .enabled = true };
    var cx = h.cx;
    cx.graphics = &graphics;
    var out: std.ArrayList(u8) = .empty;
    const code = "proc mixed plots(only obsno)=studentpanel(marginal conditional);class Family Gender;model Height=Gender;random Family Family*Gender;run;";
    try run(cx, &out, try lex.tokenize(a, code, h.d));
    try std.testing.expectEqual(@as(usize, 2), graphics.prepared.items.len);
    const plots = @import("mixed_plots.zig");
    // S154 physical figures84.15/84.16, pp.6731-6732, displayed precision.
    for (graphics.prepared.items, [_][4]f64{ .{ -1.88, 0.1353, 1.6916, 0.9261 }, .{ -1.678, -0.022, 2.0034, 1.0329 } }, 0..) |artifact, ref, mode_index| {
        const bytes = artifact.bytes;
        try std.testing.expectApproxEqAbs(ref[0], try plots.attribute(bytes, "data-minimum"), 0.0005);
        // Figure84.16 prints conditional mean to THREE decimals (-0.022);
        // Figure84.15 prints marginal mean to four (.1353).
        try std.testing.expectApproxEqAbs(ref[1], try plots.attribute(bytes, "data-mean"), if (mode_index == 0) @as(f64, 0.00005) else 0.0005);
        try std.testing.expectApproxEqAbs(ref[2], try plots.attribute(bytes, "data-maximum"), 0.00005);
        try std.testing.expectApproxEqAbs(ref[3], try plots.attribute(bytes, "data-sd"), 0.00005);
        try std.testing.expectEqual(@as(f64, 18), try plots.attribute(bytes, "data-observations"));
        try std.testing.expectEqual(@as(usize, 18), std.mem.count(u8, bytes, "class=\"observation\""));
        try std.testing.expectEqual(@as(usize, 18), std.mem.count(u8, bytes, "class=\"quantile\""));
        try std.testing.expectEqual(@as(usize, 65), std.mem.count(u8, bytes, "class=\"density-coordinate\""));
        try plots.verifyGeometry(bytes);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "Predicted Mean") != null);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "Normal density") != null);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "Observation 1;") != null);
    }
    graphics.clear();
    out.clearRetainingCapacity();
    graphics.enabled = false;
    try run(cx, &out, try lex.tokenize(a, code, h.d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    graphics.enabled = true;
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc mixed plots=none;class Family Gender;model Height=Gender / residual;random Family Family*Gender;run;", h.d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc mixed;class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc mixed plots(only maxpoints=2)=residualpanel;class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.d));
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    try std.testing.expect(std.mem.indexOf(u8, try h.d.render(), "MAXPOINTS=2") != null);
    out.clearRetainingCapacity();
    try run(cx, &out, try lex.tokenize(a, "proc mixed plots(only)=pearsonpanel(unpack);class Family Gender;model Height=Gender;random Family Family*Gender;run;", h.d));
    try std.testing.expectEqual(@as(usize, 3), graphics.prepared.items.len);
    for (graphics.prepared.items) |artifact| try plots.verifyGeometry(artifact.bytes);
}
