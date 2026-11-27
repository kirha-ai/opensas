//! MIXED RANDOM variance-component design, S154 physical pp.6675-6680.
//! Z is unweighted; precision weights act on the residual R, not on G.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const coded = @import("design_matrix.zig");
const selection = @import("data_selection.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { effects: []const coded.Effect, intercept: bool = false, subject: []const usize = &.{}, group: []const usize = &.{}, nofullz: bool = false, line: usize };
pub const Spec = struct { source: *const Dataset, basis: coded.Spec, requests: []const Request, required_columns: []const usize };
pub const Component = struct { name: []const u8, kernel: []const f64, columns: usize, effect_index: usize, request_index: usize, group_index: usize };
pub const Column = struct { name: []const u8, effect_index: usize, request_index: usize, subject_index: usize, group_index: usize };
pub const Design = struct { n: usize, q: usize, z: []const f64, columns: []const Column, components: []const Component, subject_count: usize, max_obs_per_subject: usize, first_effect_levels: usize };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC MIXED RANDOM: invalid token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .name)) return bad(cx, t, i.*);
    const token = t[i.*];
    i.* += 1;
    return ds.indexOf(token.text) orelse cx.diags.fail(error.ParseError, token.line, "PROC MIXED RANDOM: variable {s} not found", .{token.text});
}
fn unique(a: std.mem.Allocator, l: *std.ArrayList(usize), ci: usize) !void {
    if (std.mem.indexOfScalar(usize, l.items, ci) == null) try l.append(a, ci);
}
fn selector(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error![]const usize {
    var v: std.ArrayList(usize) = .empty;
    try v.append(cx.arena, try variable(cx, ds, t, i));
    while (at(t, i.*, .star)) {
        i.* += 1;
        try v.append(cx.arena, try variable(cx, ds, t, i));
    }
    if (at(t, i.*, .lparen) or at(t, i.*, .pipe)) return proc.failGap(cx.diags, t[i.*].line, "PROC MIXED RANDOM: nested/bar SUBJECT or GROUP effects are not implemented", .{});
    return v.items;
}
pub fn parse(cx: proc.ProcCtx, ds: *const Dataset, basis: coded.Spec, statements: anytype) diag.Error!Spec {
    var requests: std.ArrayList(Request) = .empty;
    var required: std.ArrayList(usize) = .empty;
    for (statements) |statement| {
        if (statement.kind != .random) continue;
        const t = statement.tokens;
        var i: usize = 0;
        var effects: std.ArrayList(coded.Effect) = .empty;
        var r = Request{ .effects = &.{}, .line = statement.line };
        while (i < t.len and !at(t, i, .slash)) {
            if (at(t, i, .name) and (eq(t[i].text, "int") or eq(t[i].text, "intercept"))) {
                r.intercept = true;
                i += 1;
                continue;
            }
            var factors: std.ArrayList(usize) = .empty;
            var nested: std.ArrayList(usize) = .empty;
            try factors.append(cx.arena, try variable(cx, ds, t, &i));
            while (at(t, i, .star)) {
                i += 1;
                try factors.append(cx.arena, try variable(cx, ds, t, &i));
            }
            if (at(t, i, .lparen)) {
                i += 1;
                while (i < t.len and !at(t, i, .rparen)) {
                    try nested.append(cx.arena, try variable(cx, ds, t, &i));
                    if (at(t, i, .star)) i += 1;
                }
                if (nested.items.len == 0 or !at(t, i, .rparen)) return bad(cx, t, i);
                i += 1;
            }
            if (at(t, i, .pipe) or at(t, i, .at)) return proc.failGap(cx.diags, t[i].line, "PROC MIXED RANDOM: bar and degree effect expansion is not implemented", .{});
            const e = coded.Effect{ .factors = factors.items, .nested = nested.items };
            _ = coded.normalize(cx.arena, ds, basis.classes, e) catch |err| return if (err == error.OutOfMemory) err else bad(cx, t, i);
            try effects.append(cx.arena, e);
            for (factors.items) |ci| try unique(cx.arena, &required, ci);
            for (nested.items) |ci| try unique(cx.arena, &required, ci);
        }
        if (!r.intercept and effects.items.len == 0) return cx.diags.fail(error.ParseError, r.line, "PROC MIXED RANDOM: at least one random effect is required", .{});
        if (at(t, i, .slash)) i += 1;
        while (i < t.len) {
            const token = t[i];
            i += 1;
            if (eq(token.text, "nofullz")) {
                r.nofullz = true;
                continue;
            }
            if (eq(token.text, "type")) {
                if (!at(t, i, .eq) or !at(t, i + 1, .name)) return bad(cx, t, i);
                i += 1;
                if (!eq(t[i].text, "vc")) return proc.failGap(cx.diags, token.line, "PROC MIXED RANDOM: TYPE={s} covariance is not implemented", .{t[i].text});
                i += 1;
            } else if (eq(token.text, "subject") or eq(token.text, "sub") or eq(token.text, "group") or eq(token.text, "grp")) {
                if (!at(t, i, .eq)) return bad(cx, t, i);
                i += 1;
                const vars = try selector(cx, ds, t, &i);
                for (vars) |ci| {
                    if (ds.columns.items[ci].type == .char and std.mem.indexOfScalar(usize, basis.classes, ci) == null)
                        return proc.failGap(cx.diags, token.line, "PROC MIXED RANDOM: non-CLASS character SUBJECT/GROUP semantics are not verified", .{});
                    try unique(cx.arena, &required, ci);
                }
                if (eq(token.text, "subject") or eq(token.text, "sub")) r.subject = vars else r.group = vars;
            } else {
                for ([_][]const u8{ "alpha", "cl", "g", "gc", "gci", "gcorr", "gdata", "gi", "ldata", "ratios", "solution", "s", "v", "vc", "vci", "vcorr", "vi" }) |known| if (eq(token.text, known)) return proc.failGap(cx.diags, token.line, "PROC MIXED RANDOM: option {s} is not implemented", .{token.text});
                return bad(cx, t, i - 1);
            }
        }
        r.effects = effects.items;
        try requests.append(cx.arena, r);
    }
    return .{ .source = ds, .basis = basis, .requests = requests.items, .required_columns = required.items };
}
const BasisColumn = struct { name: []const u8, effect: usize, values: []const f64 };
const Groups = struct { ids: []usize, labels: []const []const u8 };
fn mapIndex(classes: []const coded.Class, ci: usize) ?usize {
    for (classes, 0..) |c, j| if (c.column == ci) return j;
    return null;
}
fn grouping(cx: proc.ProcCtx, ds: *const Dataset, rows: []const []const Value, classes: []const coded.Class, vars: []const usize) diag.Error!Groups {
    const a = cx.arena;
    const ids = try a.alloc(usize, rows.len);
    @memset(ids, 0);
    if (vars.len == 0) return .{ .ids = ids, .labels = &.{""} };
    var continuous = false;
    for (vars) |ci| continuous = continuous or mapIndex(classes, ci) == null;
    var reps: std.ArrayList(usize) = .empty;
    for (rows, 0..) |row, i| {
        for (vars) |ci| if (selection.missing(row[ci])) return cx.diags.fail(error.ParseError, 0, "PROC MIXED RANDOM: missing subject/group value must be excluded before design", .{});
        var found: ?usize = null;
        for (reps.items, 0..) |rep, k| {
            if (continuous and k + 1 != reps.items.len) continue;
            var same = true;
            for (vars) |ci| {
                if (mapIndex(classes, ci)) |j| same = same and classes[j].map.row_to_level[rep] == classes[j].map.row_to_level[i] else same = same and proc.cmpValue(rows[rep][ci], row[ci]) == .eq;
            }
            if (same) {
                found = k;
                break;
            }
        }
        ids[i] = found orelse blk: {
            try reps.append(a, i);
            break :blk reps.items.len - 1;
        };
    }
    // CLASS tuples are ordered by their class-level indices. Continuous
    // selectors deliberately retain contiguous runs, including recurring keys.
    if (!continuous) {
        const order = try a.alloc(usize, reps.items.len);
        for (order, 0..) |*v, i| v.* = i;
        const Ctx = struct {
            vars: []const usize,
            classes: []const coded.Class,
            reps: []const usize,
            fn less(c: @This(), left: usize, right: usize) bool {
                for (c.vars) |ci| {
                    const j = mapIndex(c.classes, ci).?;
                    const l = c.classes[j].map.row_to_level[c.reps[left]].?;
                    const r = c.classes[j].map.row_to_level[c.reps[right]].?;
                    if (l != r) return l < r;
                }
                return false;
            }
        };
        std.mem.sort(usize, order, Ctx{ .vars = vars, .classes = classes, .reps = reps.items }, Ctx.less);
        const remap = try a.alloc(usize, order.len);
        const sorted = try a.alloc(usize, order.len);
        for (order, 0..) |old, new| {
            remap[old] = new;
            sorted[new] = reps.items[old];
        }
        for (ids) |*id| id.* = remap[id.*];
        reps.items = sorted;
    }
    const labels = try a.alloc([]const u8, reps.items.len);
    for (reps.items, labels) |rep, *label| {
        var text: std.ArrayList(u8) = .empty;
        for (vars, 0..) |ci, k| {
            if (k > 0) try text.append(a, ' ');
            const value = if (mapIndex(classes, ci)) |j| classes[j].map.levels[classes[j].map.row_to_level[rep].?].label else try proc.cellText(a, rows[rep][ci]);
            try text.print(a, "{s}={s}", .{ ds.columns.items[ci].name, value });
        }
        label.* = text.items;
    }
    return .{ .ids = ids, .labels = labels };
}

pub fn build(cx: proc.ProcCtx, s: Spec, view: selection.View) diag.Error!Design {
    const a = cx.arena;
    const n = view.observations.len;
    const nn = std.math.mul(usize, n, n) catch return error.ExecError;
    const rows = try a.alloc([]const Value, n);
    for (view.observations, rows) |obs, *row| row.* = obs.cells;
    var vectors: std.ArrayList([]const f64) = .empty;
    var columns: std.ArrayList(Column) = .empty;
    var components: std.ArrayList(Component) = .empty;
    var common_subjects: ?[]const usize = null;
    var subject_count: usize = 1;
    var max_obs = n;
    var first_levels: usize = 0;
    for (s.requests, 0..) |request, ri| {
        var basis = s.basis;
        basis.intercept = request.intercept;
        basis.effects = request.effects;
        const d = coded.build(a, s.source, rows, basis) catch |err| return if (err == error.OutOfMemory) err else cx.diags.fail(error.ParseError, request.line, "PROC MIXED RANDOM: invalid or empty complete-case design", .{});
        if (d.n != n) return cx.diags.fail(error.ParseError, request.line, "PROC MIXED RANDOM: required missing values must be excluded before design", .{});
        const subjects = try grouping(cx, s.source, rows, d.classes, request.subject);
        const groups = try grouping(cx, s.source, rows, d.classes, request.group);
        const subject_groups = try a.alloc(?usize, subjects.labels.len);
        @memset(subject_groups, null);
        const counts = try a.alloc(usize, subjects.labels.len);
        @memset(counts, 0);
        for (subjects.ids, groups.ids) |sub, grp| {
            counts[sub] += 1;
            if (subject_groups[sub]) |prior| {
                if (prior != grp) return proc.failGap(cx.diags, request.line, "PROC MIXED RANDOM: GROUP varying within SUBJECT is not implemented", .{});
            } else subject_groups[sub] = grp;
        }
        if (ri == 0) {
            common_subjects = subjects.ids;
            subject_count = subjects.labels.len;
            max_obs = 0;
            for (counts) |count| max_obs = @max(max_obs, count);
        } else if (common_subjects == null or !std.mem.eql(usize, common_subjects.?, subjects.ids)) {
            common_subjects = null;
            subject_count = 1;
            max_obs = n;
        }
        var base: std.ArrayList(BasisColumn) = .empty;
        var names: std.ArrayList([]const u8) = .empty;
        if (request.intercept) {
            const ones = try a.alloc(f64, n);
            @memset(ones, 1);
            try names.append(a, "Intercept");
            try base.append(a, .{ .name = "Intercept", .effect = 0, .values = ones });
        }
        for (request.effects) |effect| {
            const normalized = try coded.normalize(a, s.source, basis.classes, effect);
            var duplicate = false;
            for (names.items) |old| if (std.mem.eql(u8, old, normalized.name)) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            const effect_id = names.items.len;
            try names.append(a, normalized.name);
            var factors: std.ArrayList(usize) = .empty;
            try factors.appendSlice(a, normalized.nested);
            try factors.appendSlice(a, normalized.crossed);
            var dimension: usize = 1;
            for (factors.items) |ci| dimension = std.math.mul(usize, dimension, d.classes[mapIndex(d.classes, ci).?].map.levels.len) catch return error.ExecError;
            for (0..dimension) |code| {
                const values = try a.alloc(f64, n);
                @memset(values, 0);
                for (rows, 0..) |row, r| {
                    var actual: usize = 0;
                    for (factors.items) |ci| {
                        const c = d.classes[mapIndex(d.classes, ci).?];
                        actual = actual * c.map.levels.len + c.map.row_to_level[r].?;
                    }
                    if (actual != code) continue;
                    var value: f64 = 1;
                    for (normalized.continuous) |ci| value *= row[ci].num;
                    if (!std.math.isFinite(value)) return error.ExecError;
                    values[r] = value;
                }
                try base.append(a, .{ .name = normalized.name, .effect = effect_id, .values = values });
            }
        }
        if (ri == 0) for (base.items) |col| {
            if (col.effect == 0) first_levels += 1;
        };
        const component_begin = components.items.len;
        for (groups.labels, 0..) |label, gi| for (names.items, 0..) |name, ei| {
            const kernel = try a.alloc(f64, nn);
            @memset(kernel, 0);
            try components.append(a, .{ .name = if (groups.labels.len == 1 and request.group.len == 0) name else try std.fmt.allocPrint(a, "{s} ({s})", .{ name, label }), .kernel = kernel, .columns = 0, .effect_index = ei, .request_index = ri, .group_index = gi });
        };
        for (subjects.labels, 0..) |_, si| for (base.items) |col| {
            const vector = try a.alloc(f64, n);
            var nonzero = false;
            for (col.values, subjects.ids, vector) |v, sub, *out| {
                out.* = if (sub == si) v else 0;
                nonzero = nonzero or out.* != 0;
            }
            if (request.nofullz and !nonzero) continue;
            const gi = subject_groups[si].?;
            const component = &components.items[component_begin + gi * names.items.len + col.effect];
            component.columns += 1;
            const kernel: @TypeOf(vector) = @constCast(component.kernel);
            for (0..n) |i| for (0..n) |j| {
                kernel[i * n + j] += vector[i] * vector[j];
                if (!std.math.isFinite(kernel[i * n + j])) return cx.diags.fail(error.ExecError, request.line, "PROC MIXED RANDOM: covariance kernel overflow", .{});
            };
            try vectors.append(a, vector);
            try columns.append(a, .{ .name = col.name, .effect_index = col.effect, .request_index = ri, .subject_index = si, .group_index = gi });
        };
    }
    const q = columns.items.len;
    const z = try a.alloc(f64, std.math.mul(usize, n, q) catch return error.ExecError);
    for (vectors.items, 0..) |vector, j| for (vector, 0..) |v, i| {
        z[i * q + j] = v;
    };
    return .{ .n = n, .q = q, .z = z, .columns = columns.items, .components = components.items, .subject_count = subject_count, .max_obs_per_subject = max_obs, .first_effect_levels = first_levels };
}

const Testing = struct {
    fn parseBody(cx: proc.ProcCtx, ds: *const Dataset, basis: coded.Spec, body: []const u8) !Spec {
        const t = try lex.tokenize(cx.arena, body, cx.diags);
        const Statement = struct { kind: enum { random }, tokens: []const lex.Token, line: usize };
        return parse(cx, ds, basis, &[_]Statement{.{ .kind = .random, .tokens = t[0 .. t.len - 1], .line = 1 }});
    }
    fn context(a: std.mem.Allocator, d: *diag.Diagnostics, lib: *@import("../exec.zig").Library) proc.ProcCtx {
        return .{ .arena = a, .lib = lib, .diags = d };
    }
};

test "MIXED006 Heights random VC design has twelve columns and exact covariance components" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "heights");
    _ = try ds.addColumn("Family", .num);
    _ = try ds.addColumn("Gender", .char);
    _ = try ds.addColumn("Height", .num);
    // All observed Family/Gender multiplicities of the complete public sample.
    // Height does not enter Z; its full original values are tested by MIXED001.
    for ([_]usize{ 3, 2, 3, 3, 1, 1, 2, 3 }, 0..) |count, cell| for (0..count) |_| try ds.appendRow(&.{ .{ .num = @floatFromInt(cell / 2 + 1) }, .{ .str = if (cell % 2 == 0) "F" else "M" }, .{ .num = 0 } });
    const basis = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const s = try Testing.parseBody(cx, &ds, basis, "Family Family*Gender");
    const result = try build(cx, s, try selection.View.init(a, .{ .ds = &ds }, .{}));
    try std.testing.expectEqual(@as(usize, 18), result.n);
    try std.testing.expectEqual(@as(usize, 12), result.q);
    try std.testing.expectEqual(@as(usize, 2), result.components.len);
    try std.testing.expectEqualStrings("Family", result.components[0].name);
    try std.testing.expectEqualStrings("Family*Gender", result.components[1].name);
    try std.testing.expectEqual(@as(usize, 4), result.components[0].columns);
    try std.testing.expectEqual(@as(usize, 8), result.components[1].columns);
    try std.testing.expectEqual(@as(usize, 4), result.first_effect_levels);
    try std.testing.expectEqual(@as(usize, 1), result.subject_count);
    try std.testing.expectEqual(@as(usize, 18), result.max_obs_per_subject);
    for (ds.rows.items, 0..) |left, i| {
        var sum: f64 = 0;
        for (result.z[i * result.q ..][0..result.q]) |v| sum += v;
        try std.testing.expectEqual(@as(f64, 2), sum);
        for (ds.rows.items, 0..) |right, j| {
            const family = left[0].num == right[0].num;
            const gender = std.mem.eql(u8, left[1].str, right[1].str);
            try std.testing.expectEqual(@as(f64, if (family) 1 else 0), result.components[0].kernel[i * 18 + j]);
            try std.testing.expectEqual(@as(f64, if (family and gender) 1 else 0), result.components[1].kernel[i * 18 + j]);
            // Rational variances (2,3,5), plus a zero-boundary random variance.
            const covariance = 2 * result.components[0].kernel[i * 18 + j] + 3 * result.components[1].kernel[i * 18 + j] + @as(f64, if (i == j) 5 else 0);
            try std.testing.expectEqual(@as(f64, if (family) 2 else 0) + @as(f64, if (family and gender) 3 else 0) + @as(f64, if (i == j) 5 else 0), covariance);
        }
    }
}

test "MIXED006 random coefficients SUBJECT independence and GROUP variance components" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "example");
    _ = try ds.addColumn("subject", .char);
    _ = try ds.addColumn("sex", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for (0..4) |i| try ds.appendRow(&.{ .{ .str = if (i < 2) "a" else "b" }, .{ .str = if (i < 2) "F" else "M" }, .{ .num = @floatFromInt(i + 1) }, .{ .num = 1 } });
    const basis = coded.Spec{ .response = 3, .classes = &.{ 0, 1 }, .effects = &.{} };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const plain = try build(cx, try Testing.parseBody(cx, &ds, basis, "intercept x / subject=subject type=vc"), view);
    try std.testing.expectEqual(@as(usize, 4), plain.q);
    try std.testing.expectEqual(@as(usize, 2), plain.subject_count);
    try std.testing.expectEqual(@as(usize, 2), plain.max_obs_per_subject);
    for (0..4) |i| for (0..4) |j| {
        const same = i / 2 == j / 2;
        try std.testing.expectEqual(@as(f64, if (same) 1 else 0), plain.components[0].kernel[i * 4 + j]);
        try std.testing.expectEqual(if (same) @as(f64, @floatFromInt((i + 1) * (j + 1))) else 0, plain.components[1].kernel[i * 4 + j]);
    };
    const grouped = try build(cx, try Testing.parseBody(cx, &ds, basis, "int / sub=subject grp=sex"), view);
    try std.testing.expectEqual(@as(usize, 2), grouped.q);
    try std.testing.expectEqual(@as(usize, 2), grouped.components.len);
    try std.testing.expectEqualStrings("Intercept (sex=F)", grouped.components[0].name);
    try std.testing.expectEqualStrings("Intercept (sex=M)", grouped.components[1].name);
    for (0..4) |i| for (0..4) |j| for (grouped.components, 0..) |component, k| try std.testing.expectEqual(@as(f64, if (i / 2 == k and j / 2 == k) 1 else 0), component.kernel[i * 4 + j]);
    diag.resetGap();
    defer diag.resetGap();
    const varying = try Testing.parseBody(cx, &ds, basis, "int / group=sex");
    try std.testing.expectError(error.ParseError, build(cx, varying, view));
    try std.testing.expect(diag.gapHit());
}

test "MIXED006 continuous SUBJECT runs differ from CLASS identity and NOFULLZ removes only zero columns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "example");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 2, 1 }, .{ 1, 2 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = 1 } });
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const numeric = coded.Spec{ .response = 2, .effects = &.{} };
    const by_run = try build(cx, try Testing.parseBody(cx, &ds, numeric, "int / subject=id"), view);
    try std.testing.expectEqual(@as(usize, 3), by_run.subject_count);
    try std.testing.expectEqual(@as(f64, 0), by_run.components[0].kernel[2]);
    const categorical = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const by_level = try build(cx, try Testing.parseBody(cx, &ds, categorical, "int / subject=id"), view);
    try std.testing.expectEqual(@as(usize, 2), by_level.subject_count);
    try std.testing.expectEqual(@as(f64, 1), by_level.components[0].kernel[2]);
    const full = try build(cx, try Testing.parseBody(cx, &ds, categorical, "id*b"), view);
    const reduced = try build(cx, try Testing.parseBody(cx, &ds, categorical, "id*b / nofullz"), view);
    try std.testing.expectEqual(@as(usize, 4), full.q);
    try std.testing.expectEqual(@as(usize, 3), reduced.q);
    try std.testing.expectEqualSlices(f64, full.components[0].kernel, reduced.components[0].kernel);
    for (0..3) |i| for (0..3) |j| try std.testing.expectEqual(@as(f64, if (i == j) 1 else 0), full.components[0].kernel[i * 3 + j]);
}

test "MIXED006 unsupported covariance and prediction requests remain captured gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "example");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    const basis = coded.Spec{ .response = 1, .effects = &.{} };
    for ([_][]const u8{ "int x / type=un", "int / solution", "x / gdata=known", "x / v", "x|x" }) |body| {
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, Testing.parseBody(cx, &ds, basis, body));
        try std.testing.expect(diag.gapHit());
    }
    diag.resetGap();
    try std.testing.expectError(error.ParseError, Testing.parseBody(cx, &ds, basis, "absent"));
    try std.testing.expect(!diag.gapHit());
}

test "MIXED006 duplicate random effects expose nonidentifiable covariance kernels without inventing estimates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "example");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3 }) |v| try ds.appendRow(&.{.{ .num = v }});
    const tokens = try lex.tokenize(a, "int", &d);
    const Statement = struct { kind: enum { random }, tokens: []const lex.Token, line: usize };
    const statements = [_]Statement{ .{ .kind = .random, .tokens = tokens[0..1], .line = 1 }, .{ .kind = .random, .tokens = tokens[0..1], .line = 2 } };
    const s = try parse(cx, &ds, .{ .response = 0, .effects = &.{} }, &statements);
    const result = try build(cx, s, try selection.View.init(a, .{ .ds = &ds }, .{}));
    try std.testing.expectEqual(@as(usize, 2), result.components.len);
    try std.testing.expectEqualSlices(f64, result.components[0].kernel, result.components[1].kernel);
    // All (v1,v2) with a fixed sum give identical V: the likelihood owner
    // must identify this boundary/rank issue; this builder does not fit it.
    for (result.components[0].kernel, result.components[1].kernel) |left, right| try std.testing.expectEqual(2 * left + 3 * right, 5 * left + 0 * right);
}

fn jointRank(cx: proc.ProcCtx, x: coded.Design, z: Design, omit: ?Column, weights: ?[]const f64, singular: f64, intercept: bool) diag.Error!usize {
    var kept: std.ArrayList(usize) = .empty;
    for (z.columns, 0..) |column, j| {
        if (omit) |excluded| if (column.request_index == excluded.request_index and std.mem.eql(u8, column.name, excluded.name)) continue;
        try kept.append(cx.arena, j);
    }
    const p = x.p + kept.items.len;
    const values = try cx.arena.alloc(f64, x.n * p);
    for (0..x.n) |i| {
        @memcpy(values[i * p ..][0..x.p], x.x[i * x.p ..][0..x.p]);
        for (kept.items, 0..) |j, k| values[i * p + x.p + k] = z.z[i * z.q + j];
    }
    const zeros = try cx.arena.alloc(f64, x.n);
    @memset(zeros, 0);
    const ranked = try @import("reg_diagnostics.zig").fit(cx.arena, values, zeros, x.n, p, weights, intercept, singular);
    return ranked.fit.rank;
}
/// S154 physical p.6656: smallest rank contribution to [X Z] among RANDOM
/// effects syntactically containing the fixed effect; otherwise N-rank([X Z]).
/// Removing an effect removes all its SUBJECT/GROUP columns together.
pub fn containmentDF(cx: proc.ProcCtx, s: Spec, x: coded.Design, z: Design, effect_index: usize, weights: ?[]const f64, singular: f64) diag.Error!usize {
    if (effect_index >= s.basis.effects.len or x.n != z.n) return error.ExecError;
    const full = try jointRank(cx, x, z, null, weights, singular, s.basis.intercept);
    const target = s.basis.effects[effect_index];
    var minimum: ?usize = null;
    for (z.columns, 0..) |column, j| {
        var seen = false;
        for (z.columns[0..j]) |prior| if (prior.request_index == column.request_index and std.mem.eql(u8, prior.name, column.name)) {
            seen = true;
            break;
        };
        if (seen) continue;
        const request = s.requests[column.request_index];
        var variables: std.ArrayList(usize) = .empty;
        try variables.appendSlice(cx.arena, request.subject);
        for (request.effects) |effect| {
            const normalized = try coded.normalize(cx.arena, s.source, s.basis.classes, effect);
            if (std.mem.eql(u8, normalized.name, column.name)) {
                try variables.appendSlice(cx.arena, effect.factors);
                try variables.appendSlice(cx.arena, effect.nested);
                break;
            }
        }
        var contains = true;
        for (target.factors) |ci| contains = contains and std.mem.indexOfScalar(usize, variables.items, ci) != null;
        for (target.nested) |ci| contains = contains and std.mem.indexOfScalar(usize, variables.items, ci) != null;
        if (!contains) continue;
        const without = try jointRank(cx, x, z, column, weights, singular, s.basis.intercept);
        if (without > full) return error.ExecError;
        const contribution = full - without;
        minimum = if (minimum) |prior| @min(prior, contribution) else contribution;
    }
    return minimum orelse x.n - full;
}

test "MIXED006 containment uses actual joint-rank contributions not a named-effect shortcut" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "heights");
    _ = try ds.addColumn("Family", .num);
    _ = try ds.addColumn("Gender", .char);
    _ = try ds.addColumn("Height", .num);
    for ([_]usize{ 3, 2, 3, 3, 1, 1, 2, 3 }, 0..) |count, cell| for (0..count) |_| try ds.appendRow(&.{ .{ .num = @floatFromInt(cell / 2 + 1) }, .{ .str = if (cell % 2 == 0) "F" else "M" }, .{ .num = 0 } });
    const basis = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{.{ .factors = &.{1} }} };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const x = try coded.build(a, &ds, ds.rows.items, basis);
    const s = try Testing.parseBody(cx, &ds, basis, "Family Family*Gender");
    const z = try build(cx, s, view);
    // rank[X Z]=8; removing Family*Gender leaves rank5 => denominator3.
    try std.testing.expectEqual(@as(usize, 3), try containmentDF(cx, s, x, z, 0, null, 1e-10));
    const only = try Testing.parseBody(cx, &ds, basis, "Family");
    const zonly = try build(cx, only, view);
    // Family does not syntactically contain Gender: residual18-rank5=13.
    try std.testing.expectEqual(@as(usize, 13), try containmentDF(cx, only, x, zonly, 0, null, 1e-10));
    const aliased = try Testing.parseBody(cx, &ds, basis, "Gender");
    const za = try build(cx, aliased, view);
    // A random effect entirely inside X has zero contribution, not residualDF.
    try std.testing.expectEqual(@as(usize, 0), try containmentDF(cx, aliased, x, za, 0, null, 1e-10));
}
