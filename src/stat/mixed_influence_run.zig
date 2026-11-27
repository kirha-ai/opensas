//! Noniterative Influence consumer. Unsupported covariance refits/ODS schemas
//! are explicit gaps; native listings use computed diagnostics, not placeholders.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const kernel = @import("mixed_influence.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Options = struct { iterations: usize = 0, effect: []const usize = &.{}, line: usize = 0 };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC MIXED: invalid INFLUENCE option near {s}", .{if (i < t.len) t[i].text else "<end>"});
}
pub fn parse(cx: proc.ProcCtx, ds: *const @import("../dataset.zig").Dataset, t: []const lex.Token, index: *usize) diag.Error!Options {
    var i = index.* + 1;
    var options = Options{ .line = t[index.*].line };
    if (at(t, i, .lparen)) {
        i += 1;
        while (!at(t, i, .rparen)) {
            if (!at(t, i, .name)) return bad(cx, t, i);
            const token = t[i];
            i += 1;
            if (eq(token.text, "iter")) {
                if (!at(t, i, .eq) or !at(t, i + 1, .number)) return bad(cx, t, i);
                i += 1;
                options.iterations = std.fmt.parseInt(usize, t[i].text, 10) catch return bad(cx, t, i);
                i += 1;
            } else if (eq(token.text, "effect")) {
                if (!at(t, i, .eq)) return bad(cx, t, i);
                i += 1;
                var columns: std.ArrayList(usize) = .empty;
                while (true) {
                    if (!at(t, i, .name)) return bad(cx, t, i);
                    const ci = ds.indexOf(t[i].text) orelse return bad(cx, t, i);
                    try columns.append(cx.arena, ci);
                    i += 1;
                    if (!at(t, i, .star)) break;
                    i += 1;
                }
                options.effect = columns.items;
            } else {
                for ([_][]const u8{ "est", "estimates", "keep", "select", "size" }) |known| if (eq(token.text, known)) return proc.failGap(cx.diags, token.line, "PROC MIXED: INFLUENCE {s} is not implemented", .{token.text});
                return bad(cx, t, i - 1);
            }
        }
        i += 1;
    }
    index.* = i;
    return options;
}
pub fn validate(cx: proc.ProcCtx, s: anytype, m: anytype) diag.Error!void {
    const options = m.options.influence orelse return;
    if (s.options.method != .reml) return proc.failGap(cx.diags, options.line, "PROC MIXED: influence for this estimation method is not implemented", .{});
    for (options.effect) |ci| if (std.mem.indexOfScalar(usize, m.matrix.classes, ci) == null) return cx.diags.fail(error.ParseError, options.line, "PROC MIXED: INFLUENCE EFFECT requires CLASS variables", .{});
    if (options.iterations > 0 and (m.has_random or m.has_repeated)) return proc.failGap(cx.diags, options.line, "PROC MIXED: iterative covariance-parameter influence refits are not implemented", .{});
    if (@import("mixed_plots.zig").active(cx) and !s.options.plots_none) return proc.failGap(cx.diags, options.line, "PROC MIXED: influence graphics are not implemented; specify PLOTS=NONE", .{});
    if (cx.capture) |capture| if (capture.wants("Influence")) return proc.failGap(cx.diags, options.line, "PROC MIXED: typed Influence output schema is not verified", .{});
}
fn number(a: std.mem.Allocator, out: *std.ArrayList(u8), value: ?f64) !void {
    try out.append(a, ' ');
    if (value) |v| {
        if (!std.math.isFinite(v)) return error.ExecError;
        try out.appendSlice(a, std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = v }, "best12."), " "));
    } else try out.append(a, '.');
}
pub fn publish(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: anytype, m: anytype, group: anytype, x: anytype, z: anytype, fitted: anytype, profiled: bool, route: *@import("mixed_ods_route.zig").Router) diag.Error!void {
    const options = m.options.influence orelse return;
    const a = cx.arena;
    const n = x.matrix.n;
    const v = try a.alloc(f64, n * n);
    @memset(v, 0);
    const residual = fitted.variances[fitted.variances.len - 1];
    for (0..n) |i| v[i * n + i] = residual / x.weights[i];
    for (z.components, fitted.variances[0..z.components.len]) |component, theta| for (v, component.kernel) |*target, value| {
        target.* += theta * value;
    };
    var sets: []const kernel.Deletion = undefined;
    var labels: []const []const u8 = &.{};
    if (options.effect.len == 0) sets = try kernel.singletonDeletions(a, n) else {
        const rows = try a.alloc([]const @import("../value.zig").Value, n);
        for (x.matrix.source_rows, rows) |index, *row| row.* = group.selected.observations[index].cells;
        const normalized = try @import("design_matrix.zig").normalize(a, s.input.ds, m.matrix.classes, .{ .factors = options.effect });
        const grouped = try @import("mixed_random.zig").grouping(cx, s.input.ds, rows, x.matrix.classes, normalized.crossed);
        labels = grouped.labels;
        const deleted = try a.alloc(kernel.Deletion, labels.len);
        for (deleted, 0..) |*set, k| {
            var indices: std.ArrayList(usize) = .empty;
            for (grouped.ids, 0..) |id, i| if (id == k) try indices.append(a, i);
            set.* = .{ .indices = indices.items };
        }
        sets = deleted;
    }
    const report = kernel.analyse(a, .{ .x = x.matrix.x, .y = x.y, .n = n, .p = x.matrix.p, .weights = x.weights, .has_intercept = m.matrix.intercept, .singular = m.options.singular }, v, sets, if (profiled) .profile_reml else .fixed_covariance) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, options.line, "PROC MIXED: influence boundary is not implemented ({t})", .{err});
    const start = out.items.len;
    try out.appendSlice(a, "\nInfluence Diagnostics\n\n");
    if (options.effect.len == 0) try out.appendSlice(a, "Deleted Obs. Index Observed Predicted Residual Leverage PRESS Residual Student RStudent CookD DFFITS COVRATIO RLD\n") else try out.appendSlice(a, "Effect Level Observations PRESS CookD MDFFITS COVRATIO COVTRACE RLD\n");
    for (report.rows, 0..) |row, k| {
        if (options.effect.len == 0) {
            const physical = x.source_rows[row.deleted[0]];
            const index = for (group.raw.observations, 0..) |obs, i| {
                if (obs.source_number == physical) break i + 1;
            } else return error.ExecError;
            try out.print(a, "{d}", .{index});
            for ([_]?f64{ row.observed, row.predicted, row.residual, row.leverage, row.press_residual, row.student, row.external_student, row.cook_d, row.dffits, row.covratio, row.likelihood_distance }) |value| try number(a, out, value);
        } else {
            try out.print(a, "{s} {d}", .{ labels[k], row.deleted.len });
            for ([_]?f64{ row.press, row.cook_d, row.mdffits, row.covratio, row.covtrace, row.likelihood_distance }) |value| try number(a, out, value);
        }
        try out.append(a, '\n');
        if (row.status != .ok) try cx.diags.note(options.line, "PROC MIXED: influence deletion {d} has unavailable statistics ({t})", .{ k + 1, row.status });
    }
    try route.finish(a, out, start, "Influence");
}

test "MIXED013 real Influence consumer uses profiled deletion diagnostics and preserves filters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 3, 5, 7 }) |y| try ds.appendRow(&.{.{ .num = y }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    var listing = @import("../ods_listing.zig").Listing{};
    _ = try listing.parse(a, &d, try lex.tokenize(a, "ods select Influence;", &d));
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d, .listing = &listing };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed;model y= / influence;run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Fit Statistics") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Influence Diagnostics") != null);
    const header = std.mem.indexOf(u8, out.items, "Deleted Obs. Index") orelse return error.MissingTable;
    const start = (std.mem.indexOfScalarPos(u8, out.items, header, '\n') orelse return error.MissingTable) + 1;
    var lines = std.mem.tokenizeScalar(u8, out.items[start..], '\n');
    const first = lines.next().?;
    var values = std.mem.tokenizeAny(u8, first, " \t");
    const expected = [_]f64{ 1, 1, 4, -3, 0.25, -4, -3 / @sqrt(@as(f64, 5)), -@sqrt(@as(f64, 3)), 0.6, -1, 0.8, 3 * @log(@as(f64, 0.6)) + 3 };
    for (expected) |value| try std.testing.expectApproxEqAbs(value, try std.fmt.parseFloat(f64, values.next() orelse return error.MissingValue), 2e-9);
    try std.testing.expect(values.next() == null);
    var rows: usize = 1;
    while (lines.next() != null) rows += 1;
    try std.testing.expectEqual(@as(usize, 4), rows);
    try std.testing.expect(!d.hasErrors());
    const normal = try a.dupe(u8, out.items);
    out.clearRetainingCapacity();
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed;model y= / influence(iter=10);run;", &d));
    try std.testing.expectEqualStrings(normal, out.items); // ITER has no effect without G/R effects
    var grouped = @import("../dataset.zig").Dataset.init(a, "grouped");
    _ = try grouped.addColumn("g", .num);
    _ = try grouped.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 5 }, .{ 2, 7 } }) |row| try grouped.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] } });
    try lib.put("grouped", &grouped);
    out.clearRetainingCapacity();
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed;class g;model y= / influence(effect=g);run;", &d));
    const group_header = std.mem.indexOf(u8, out.items, "Effect Level Observations") orelse return error.MissingTable;
    const group_start = (std.mem.indexOfScalarPos(u8, out.items, group_header, '\n') orelse return error.MissingTable) + 1;
    var group_lines = std.mem.tokenizeScalar(u8, out.items[group_start..], '\n');
    for ([_][]const u8{ "g=1", "g=2" }) |label| {
        var fields = std.mem.tokenizeAny(u8, group_lines.next() orelse return error.MissingValue, " \t");
        try std.testing.expectEqualStrings(label, fields.next().?);
        for ([_]f64{ 2, 34, 2.4, 4, 0.6, 0.4, 15 + 3 * @log(@as(f64, 0.3)) }) |value| try std.testing.expectApproxEqAbs(value, try std.fmt.parseFloat(f64, fields.next() orelse return error.MissingValue), 2e-9);
        try std.testing.expect(fields.next() == null);
    }
    try std.testing.expect(group_lines.next() == null);
}

test "MIXED013 influence unsupported refits capture and graph requests are loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 1, 3 }, .{ 2, 5 }, .{ 2, 7 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
    try lib.put("sample", &ds);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "proc mixed;class g;model y= / influence(iter=1);random g;run;", "proc mixed;model y= / influence(estimates);run;", "proc mixed;model y= / influence(size=2);run;" }) |source| {
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &d)));
        try std.testing.expect(diag.gapHit());
    }
    var graphics = @import("graphics_svg.zig").Session{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    var gcx = cx;
    gcx.graphics = &graphics;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, @import("mixed.zig").run(gcx, &out, try lex.tokenize(a, "proc mixed;model y= / influence;run;", &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
}
