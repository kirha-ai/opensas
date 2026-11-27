//! REPEATED R-side layout and covariance contracts, S154 physical pp.6680-6694.
//! Raw response-missing positions remain in the within-subject time grid.
//! Covariance assembly is not estimation: signed off-diagonals are never clipped.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const coded = @import("design_matrix.zig");
const classes = @import("class_levels.zig");
const selection = @import("data_selection.zig");
const identity = @import("mixed_random.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Kind = enum { vc, cs, ar1, un, toep };
pub fn structureName(kind: Kind) []const u8 {
    return switch (kind) {
        .vc => "VC",
        .cs => "CS",
        .ar1 => "AR(1)",
        .un => "UN",
        .toep => "TOEP",
    };
}
pub const Spec = struct {
    source: *const Dataset,
    basis: coded.Spec,
    kind: Kind = .vc,
    band: ?usize = null,
    effect: []const usize = &.{},
    subject: []const usize = &.{},
    subject_intercept: bool = false,
    group: []const usize = &.{},
    required_columns: []const usize,
    line: usize,
};
pub const Layout = struct {
    spec: Spec,
    n: usize,
    dimension: usize,
    subjects: []const usize,
    groups: []const usize,
    positions: []const usize,
    source_rows: []const usize,
    weights: []const f64,
    subject_labels: []const []const u8,
    group_labels: []const []const u8,
    max_obs_per_subject: usize,
};
/// Internal named parameter schema. Only UN's packed lower-triangle ordering
/// and VC scalar ordering currently form an external PARMS adapter contract.
/// CS and AR use named quantities to avoid mistaking covariance for correlation.
pub const Parameters = union(Kind) {
    vc: f64,
    cs: struct { covariance: f64, residual: f64 },
    ar1: struct { rho: f64, variance: f64 },
    un: []const f64,
    toep: []const f64, // diagonal, then successive covariance lags
};
pub const Covariance = struct { values: []const f64, n: usize, status: enum { positive_definite, not_positive_definite } };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC MIXED REPEATED: invalid token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .name)) return bad(cx, t, i.*);
    const token = t[i.*];
    i.* += 1;
    return ds.indexOf(token.text) orelse cx.diags.fail(error.ParseError, token.line, "PROC MIXED REPEATED: variable {s} not found", .{token.text});
}
fn effect(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error![]const usize {
    var v: std.ArrayList(usize) = .empty;
    try v.append(cx.arena, try variable(cx, ds, t, i));
    while (at(t, i.*, .star)) {
        i.* += 1;
        try v.append(cx.arena, try variable(cx, ds, t, i));
    }
    if (at(t, i.*, .lparen) or at(t, i.*, .pipe)) return proc.failGap(cx.diags, t[i.*].line, "PROC MIXED REPEATED: nested or bar selector effects are not implemented", .{});
    return v.items;
}
fn positiveInteger(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .number)) return bad(cx, t, i.*);
    const v = std.fmt.parseInt(usize, t[i.*].text, 10) catch return bad(cx, t, i.*);
    if (v == 0) return bad(cx, t, i.*);
    i.* += 1;
    return v;
}
pub fn parse(cx: proc.ProcCtx, ds: *const Dataset, basis: coded.Spec, statements: anytype) diag.Error!?Spec {
    var spec: ?Spec = null;
    for (statements) |statement| {
        if (statement.kind != .repeated) continue;
        if (spec != null) return proc.failGap(cx.diags, statement.line, "PROC MIXED: multiple REPEATED statements are not verified", .{});
        const t = statement.tokens;
        var i: usize = 0;
        var s = Spec{ .source = ds, .basis = basis, .required_columns = &.{}, .line = statement.line };
        if (i < t.len and !at(t, i, .slash)) {
            s.effect = try effect(cx, ds, t, &i);
            for (s.effect) |ci| if (std.mem.indexOfScalar(usize, basis.classes, ci) == null) return cx.diags.fail(error.ParseError, statement.line, "PROC MIXED REPEATED: repeated effects must contain only CLASS variables", .{});
            if (i < t.len and !at(t, i, .slash)) return proc.failGap(cx.diags, t[i].line, "PROC MIXED REPEATED: multiple repeated effects/direct products are not implemented", .{});
        }
        if (at(t, i, .slash)) i += 1;
        while (i < t.len) {
            const token = t[i];
            i += 1;
            if (eq(token.text, "type")) {
                if (!at(t, i, .eq) or !at(t, i + 1, .name)) return bad(cx, t, i);
                i += 1;
                const name = t[i].text;
                i += 1;
                if (eq(name, "vc") or eq(name, "simple")) s.kind = .vc else if (eq(name, "cs")) s.kind = .cs else if (eq(name, "un")) s.kind = .un else if (eq(name, "toep")) s.kind = .toep else if (eq(name, "ar")) s.kind = .ar1 else {
                    for ([_][]const u8{ "ante", "arh", "arma", "csh", "fa", "fa0", "fa1", "hf", "lin", "linear", "toeph", "unr", "sp" }) |known| if (eq(name, known)) return proc.failGap(cx.diags, token.line, "PROC MIXED REPEATED: TYPE={s} is not implemented", .{name});
                    return bad(cx, t, i - 1);
                }
                if (at(t, i, .lparen)) {
                    i += 1;
                    const order = try positiveInteger(cx, t, &i);
                    if (!at(t, i, .rparen)) return bad(cx, t, i);
                    i += 1;
                    if (s.kind == .ar1) {
                        if (order != 1) return proc.failGap(cx.diags, token.line, "PROC MIXED REPEATED: only AR(1) covariance is implemented", .{});
                    } else if (s.kind == .un or s.kind == .toep) s.band = order else return bad(cx, t, i - 1);
                } else if (s.kind == .ar1) return bad(cx, t, i);
                if (at(t, i, .at)) return proc.failGap(cx.diags, token.line, "PROC MIXED REPEATED: direct product structures are not implemented", .{});
            } else if (eq(token.text, "subject") or eq(token.text, "sub") or eq(token.text, "group") or eq(token.text, "grp")) {
                const is_subject = eq(token.text, "subject") or eq(token.text, "sub");
                if (!at(t, i, .eq)) return bad(cx, t, i);
                i += 1;
                if (is_subject and at(t, i, .name) and eq(t[i].text, "intercept")) {
                    s.subject_intercept = true;
                    s.subject = &.{};
                    i += 1;
                } else {
                    const v = try effect(cx, ds, t, &i);
                    for (v) |ci| if (ds.columns.items[ci].type == .char and std.mem.indexOfScalar(usize, basis.classes, ci) == null) return proc.failGap(cx.diags, token.line, "PROC MIXED REPEATED: non-CLASS character subject/group semantics are not verified", .{});
                    if (is_subject) {
                        s.subject = v;
                        s.subject_intercept = false;
                    } else s.group = v;
                }
            } else {
                for ([_][]const u8{ "hlm", "hlps", "ldata", "local", "localw", "nonlocalw", "r", "rc", "rci", "rcorr", "ri", "sscp" }) |known| if (eq(token.text, known)) return proc.failGap(cx.diags, token.line, "PROC MIXED REPEATED: option {s} is not implemented", .{token.text});
                return bad(cx, t, i - 1);
            }
        }
        var required: std.ArrayList(usize) = .empty;
        for ([_][]const usize{ s.effect, s.subject, s.group }) |vars| for (vars) |ci| if (std.mem.indexOfScalar(usize, required.items, ci) == null) try required.append(cx.arena, ci);
        s.required_columns = required.items;
        spec = s;
    }
    return spec;
}
fn classIndex(maps: []const coded.Class, ci: usize) usize {
    for (maps, 0..) |map, j| if (map.column == ci) return j;
    unreachable;
}
pub fn layout(cx: proc.ProcCtx, s: Spec, raw: selection.View, selected: selection.View) diag.Error!Layout {
    const a = cx.arena;
    if (selected.observations.len == 0) return cx.diags.fail(error.ParseError, s.line, "PROC MIXED REPEATED: no usable observations", .{});
    const rows = try a.alloc([]const Value, raw.observations.len);
    for (raw.observations, rows) |obs, *row| {
        row.* = obs.cells;
        for (s.required_columns) |ci| if (selection.missing(obs.cells[ci])) return proc.failGap(cx.diags, s.line, "PROC MIXED REPEATED: missing selector/time values in the raw grid are not implemented", .{});
    }
    var maps: std.ArrayList(coded.Class) = .empty;
    for (s.basis.classes, 0..) |ci, j| {
        if (std.mem.indexOfScalar(usize, s.required_columns, ci) == null) continue;
        if (s.basis.references.len > 0) if (s.basis.references[j]) |ref| if (ref != .last) return proc.failGap(cx.diags, s.line, "PROC MIXED REPEATED: reordered reference levels in residual selectors are not implemented", .{});
        try maps.append(a, .{ .column = ci, .map = try classes.build(a, s.source, rows, ci, .{ .order = s.basis.order }) });
    }
    var subjects = try identity.grouping(cx, s.source, rows, maps.items, s.subject);
    if (s.subject.len == 0 and !s.subject_intercept) {
        const labels = try a.alloc([]const u8, rows.len);
        for (subjects.ids, labels, 0..) |*id, *label, i| {
            id.* = i;
            label.* = try std.fmt.allocPrint(a, "Observation {d}", .{i + 1});
        }
        subjects.labels = labels;
    }
    const groups = try identity.grouping(cx, s.source, rows, maps.items, s.group);
    const raw_positions = try a.alloc(usize, rows.len);
    const counts = try a.alloc(usize, subjects.labels.len);
    @memset(counts, 0);
    var dimension: usize = 0;
    if (s.effect.len > 0) {
        dimension = 1;
        for (s.effect) |ci| dimension = std.math.mul(usize, dimension, maps.items[classIndex(maps.items, ci)].map.levels.len) catch return error.ExecError;
    }
    for (subjects.ids, 0..) |subject, i| {
        if (s.effect.len == 0) {
            raw_positions[i] = counts[subject];
            counts[subject] += 1;
            dimension = @max(dimension, counts[subject]);
        } else {
            var code: usize = 0;
            for (s.effect) |ci| {
                const map = maps.items[classIndex(maps.items, ci)].map;
                code = code * map.levels.len + map.row_to_level[i].?;
            }
            raw_positions[i] = code;
            counts[subject] += 1;
        }
    }
    if (s.band) |band| if (band > dimension) return proc.failGap(cx.diags, s.line, "PROC MIXED REPEATED: band exceeds the observed repeated dimension", .{});
    const n = selected.observations.len;
    const sub = try a.alloc(usize, n);
    const grp = try a.alloc(usize, n);
    const positions = try a.alloc(usize, n);
    const sources = try a.alloc(usize, n);
    const weights = try a.alloc(f64, n);
    const used_counts = try a.alloc(usize, subjects.labels.len);
    @memset(used_counts, 0);
    const subject_group = try a.alloc(?usize, subjects.labels.len);
    @memset(subject_group, null);
    for (selected.observations, 0..) |obs, i| {
        const raw_index = for (raw.observations, 0..) |original, j| {
            if (original.source_number == obs.source_number) break j;
        } else return error.ExecError;
        sub[i] = subjects.ids[raw_index];
        grp[i] = groups.ids[raw_index];
        positions[i] = raw_positions[raw_index];
        sources[i] = obs.source_number;
        weights[i] = obs.weight.num;
        if (!(weights[i] > 0) or !std.math.isFinite(weights[i])) return error.ExecError;
        if (subject_group[sub[i]]) |prior| {
            if (prior != grp[i]) return proc.failGap(cx.diags, s.line, "PROC MIXED REPEATED: GROUP varying within SUBJECT is not implemented", .{});
        } else subject_group[sub[i]] = grp[i];
        for (0..i) |j| if (sub[j] == sub[i] and positions[j] == positions[i]) return cx.diags.fail(error.ExecError, s.line, "PROC MIXED REPEATED: repeated levels are not distinct within a subject; R is singular", .{});
        used_counts[sub[i]] += 1;
    }
    var max_obs: usize = 0;
    for (used_counts) |count| max_obs = @max(max_obs, count);
    return .{ .spec = s, .n = n, .dimension = dimension, .subjects = sub, .groups = grp, .positions = positions, .source_rows = sources, .weights = weights, .subject_labels = subjects.labels, .group_labels = groups.labels, .max_obs_per_subject = max_obs };
}
fn unCount(t: usize, band: usize) usize {
    var n: usize = 0;
    for (0..t) |i| n += @min(i + 1, band);
    return n;
}
fn unIndex(i: usize, j: usize, band: usize) ?usize {
    const hi = @max(i, j);
    const lo = @min(i, j);
    if (hi - lo >= band) return null;
    var n: usize = 0;
    for (0..hi) |row| n += @min(row + 1, band);
    return n + lo - (hi + 1 - @min(hi + 1, band));
}
fn validVariance(x: f64) bool {
    return std.math.isFinite(x) and x >= 0;
}
pub fn covariance(cx: proc.ProcCtx, l: Layout, parameters: []const Parameters) diag.Error!Covariance {
    if (parameters.len != l.group_labels.len) return cx.diags.fail(error.ParseError, l.spec.line, "PROC MIXED REPEATED: covariance parameter group count mismatch", .{});
    if (l.n == 0 or l.subjects.len != l.n or l.groups.len != l.n or l.positions.len != l.n or l.weights.len != l.n) return error.ExecError;
    for (0..l.n) |i| {
        if (l.groups[i] >= parameters.len or l.positions[i] >= l.dimension or !(l.weights[i] > 0) or !std.math.isFinite(l.weights[i])) return error.ExecError;
        for (0..i) |j| if (l.subjects[i] == l.subjects[j] and l.groups[i] != l.groups[j]) return error.ExecError;
    }
    const band = l.spec.band orelse l.dimension;
    for (parameters) |p| {
        if (std.meta.activeTag(p) != l.spec.kind) return error.ExecError;
        switch (p) {
            .vc => |v| if (!validVariance(v)) return error.ExecError,
            .cs => |v| if (!std.math.isFinite(v.covariance) or !validVariance(v.residual)) return error.ExecError,
            .ar1 => |v| if (!validVariance(v.variance) or !std.math.isFinite(v.rho) or @abs(v.rho) >= 1) return error.ExecError,
            .un => |v| {
                if (v.len != unCount(l.dimension, band)) return error.ExecError;
                for (v) |value| if (!std.math.isFinite(value)) return error.ExecError;
                for (0..l.dimension) |i| if (!validVariance(v[unIndex(i, i, band).?])) return error.ExecError;
            },
            .toep => |v| {
                if (v.len != band or !validVariance(v[0])) return error.ExecError;
                for (v) |value| if (!std.math.isFinite(value)) return error.ExecError;
            },
        }
    }
    const nn = std.math.mul(usize, l.n, l.n) catch return error.ExecError;
    const matrix = try cx.arena.alloc(f64, nn);
    @memset(matrix, 0);
    for (0..l.n) |i| for (0..l.n) |j| {
        if (l.subjects[i] != l.subjects[j]) continue;
        const p = parameters[l.groups[i]];
        const left = l.positions[i];
        const right = l.positions[j];
        const lag = @max(left, right) - @min(left, right);
        const value = switch (p) {
            .vc => |v| if (left == right) v else 0,
            .cs => |v| v.covariance + if (left == right) v.residual else @as(f64, 0),
            .ar1 => |v| v.variance * std.math.pow(f64, v.rho, @floatFromInt(lag)),
            .un => |v| if (unIndex(left, right, band)) |k| v[k] else 0,
            .toep => |v| if (lag < v.len) v[lag] else 0,
        };
        matrix[i * l.n + j] = value / (@sqrt(l.weights[i]) * @sqrt(l.weights[j]));
        if (!std.math.isFinite(matrix[i * l.n + j])) return error.ExecError;
    };
    var positive = true;
    _ = @import("mixed_fit_matrix.zig").inverse(cx.arena, matrix, l.n) catch |err| switch (err) {
        error.NotPositiveDefinite => blk: {
            positive = false;
            break :blk @import("mixed_fit_matrix.zig").Inverse{ .values = &.{}, .logdet = 0 };
        },
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ExecError,
    };
    return .{ .values = matrix, .n = l.n, .status = if (positive) .positive_definite else .not_positive_definite };
}

const Testing = struct {
    fn context(a: std.mem.Allocator, d: *diag.Diagnostics, lib: *@import("../exec.zig").Library) proc.ProcCtx {
        return .{ .arena = a, .lib = lib, .diags = d };
    }
    fn spec(cx: proc.ProcCtx, ds: *const Dataset, basis: coded.Spec, body: []const u8) !Spec {
        const t = try lex.tokenize(cx.arena, body, cx.diags);
        const Statement = struct { kind: enum { repeated }, tokens: []const lex.Token, line: usize };
        return (try parse(cx, ds, basis, &[_]Statement{.{ .kind = .repeated, .tokens = t[0 .. t.len - 1], .line = 1 }})).?;
    }
    fn sample(a: std.mem.Allocator) !Dataset {
        var ds = Dataset.init(a, "small");
        for ([_][]const u8{ "id", "time", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
        for ([_][4]f64{ .{ 1, 0, 1, 1 }, .{ 1, 1, std.math.nan(f64), 4 }, .{ 1, 2, 3, 4 }, .{ 2, 0, 4, 1 }, .{ 2, 1, 5, 1 }, .{ 2, 2, 6, 1 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
        return ds;
    }
};

test "MIXED007 missing-response positions negative AR correlation and precision scaling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = try Testing.sample(a);
    const basis = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const raw = try selection.View.init(a, .{ .ds = &ds }, .{ .weight = 3 });
    const selected = try raw.select(a, .{ .missing_columns = &.{2}, .weight = .positive_only });
    for ([_][]const u8{ "/ type=ar(1) subject=id", "time / type=ar(1) subject=id" }) |body| {
        const l = try layout(cx, try Testing.spec(cx, &ds, basis, body), raw, selected);
        try std.testing.expectEqual(@as(usize, 3), l.dimension);
        try std.testing.expectEqualSlices(usize, &.{ 0, 2, 0, 1, 2 }, l.positions);
        try std.testing.expectEqualSlices(usize, &.{ 1, 3, 4, 5, 6 }, l.source_rows);
        const r = try covariance(cx, l, &.{.{ .ar1 = .{ .rho = -0.5, .variance = 4 } }});
        const expected = [_]f64{ 4, 0.5, 0, 0, 0, 0.5, 1, 0, 0, 0, 0, 0, 4, -2, 1, 0, 0, -2, 4, -2, 0, 0, 1, -2, 4 };
        try std.testing.expectEqualSlices(f64, &expected, r.values);
        try std.testing.expectEqual(@TypeOf(r.status).positive_definite, r.status);
        try std.testing.expectError(error.ExecError, covariance(cx, l, &.{.{ .ar1 = .{ .rho = -1, .variance = 4 } }}));
        try std.testing.expectError(error.ExecError, covariance(cx, l, &.{.{ .ar1 = .{ .rho = 1, .variance = 4 } }}));
    }
}

test "MIXED007 CS UN Toeplitz signed covariances and singular boundaries are never clipped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "three");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3 }) |y| try ds.appendRow(&.{.{ .num = y }});
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const basis = coded.Spec{ .response = 0, .effects = &.{} };
    const cs = try layout(cx, try Testing.spec(cx, &ds, basis, "/ type=cs subject=intercept"), view, view);
    const valid = try covariance(cx, cs, &.{.{ .cs = .{ .covariance = -1, .residual = 4 } }});
    try std.testing.expectEqualSlices(f64, &.{ 3, -1, -1, -1, 3, -1, -1, -1, 3 }, valid.values);
    try std.testing.expectEqual(@TypeOf(valid.status).positive_definite, valid.status);
    const invalid = try covariance(cx, cs, &.{.{ .cs = .{ .covariance = -2, .residual = 4 } }});
    try std.testing.expectEqual(@as(f64, -2), invalid.values[1]);
    try std.testing.expectEqual(@TypeOf(invalid.status).not_positive_definite, invalid.status);
    const zero = try covariance(cx, cs, &.{.{ .cs = .{ .covariance = 0, .residual = 0 } }});
    try std.testing.expectEqual(@TypeOf(zero.status).not_positive_definite, zero.status);
    for (zero.values) |v| try std.testing.expectEqual(@as(f64, 0), v);
    const un = try layout(cx, try Testing.spec(cx, &ds, basis, "/ type=un subject=intercept"), view, view);
    const matrix = try covariance(cx, un, &.{.{ .un = &.{ 4, -1, 9, 0.5, -2, 16 } }});
    try std.testing.expectEqualSlices(f64, &.{ 4, -1, 0.5, -1, 9, -2, 0.5, -2, 16 }, matrix.values);
    try std.testing.expectEqual(@TypeOf(matrix.status).positive_definite, matrix.status);
    try std.testing.expectError(error.ExecError, covariance(cx, un, &.{.{ .un = &.{ -4, -1, 9, 0.5, -2, 16 } }}));
    const diagonal = try layout(cx, try Testing.spec(cx, &ds, basis, "/ type=un(1) subject=intercept"), view, view);
    const diagmatrix = try covariance(cx, diagonal, &.{.{ .un = &.{ 4, 9, 16 } }});
    try std.testing.expectEqualSlices(f64, &.{ 4, 0, 0, 0, 9, 0, 0, 0, 16 }, diagmatrix.values);
    const toep = try layout(cx, try Testing.spec(cx, &ds, basis, "/ type=toep(2) subject=intercept"), view, view);
    const toeplitz = try covariance(cx, toep, &.{.{ .toep = &.{ 4, -1 } }});
    try std.testing.expectEqualSlices(f64, &.{ 4, -1, 0, -1, 4, -1, 0, -1, 4 }, toeplitz.values);
}

test "MIXED007 subject group identity default independence and nonidentifiable correlations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "identities");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 1 }) |id| try ds.appendRow(&.{ .{ .num = id }, .{ .str = if (id == 1) "F" else "M" }, .{ .num = id } });
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const continuous = coded.Spec{ .response = 2, .classes = &.{1}, .effects = &.{} };
    const categorical = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const run = try layout(cx, try Testing.spec(cx, &ds, continuous, "/ subject=id type=cs"), view, view);
    const level = try layout(cx, try Testing.spec(cx, &ds, categorical, "/ subject=id type=cs"), view, view);
    try std.testing.expectEqual(@as(usize, 3), run.subject_labels.len);
    try std.testing.expectEqual(@as(usize, 2), level.subject_labels.len);
    const run_r = try covariance(cx, run, &.{.{ .cs = .{ .covariance = 1, .residual = 2 } }});
    const level_r = try covariance(cx, level, &.{.{ .cs = .{ .covariance = 1, .residual = 2 } }});
    try std.testing.expectEqual(@as(f64, 0), run_r.values[2]);
    try std.testing.expectEqual(@as(f64, 1), level_r.values[2]);
    const grouped = try layout(cx, try Testing.spec(cx, &ds, categorical, "/ sub=id grp=g type=simple"), view, view);
    const grouped_r = try covariance(cx, grouped, &.{ .{ .vc = 4 }, .{ .vc = 9 } });
    try std.testing.expectEqualSlices(f64, &.{ 4, 0, 0, 0, 9, 0, 0, 0, 4 }, grouped_r.values);
    const separate = try layout(cx, try Testing.spec(cx, &ds, categorical, "/ type=ar(1)"), view, view);
    try std.testing.expectEqual(@as(usize, 3), separate.subject_labels.len);
    try std.testing.expectEqual(@as(usize, 1), separate.dimension);
    const positive = try covariance(cx, separate, &.{.{ .ar1 = .{ .variance = 4, .rho = 0.5 } }});
    const negative = try covariance(cx, separate, &.{.{ .ar1 = .{ .variance = 4, .rho = -0.5 } }});
    try std.testing.expectEqualSlices(f64, positive.values, negative.values); // rho unidentifiable with one row per subject
}

test "MIXED007 duplicate repeated levels and unsupported selectors have captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "duplicate");
    for ([_][]const u8{ "id", "time", "y" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 3 } });
    const basis = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const s = try Testing.spec(cx, &ds, basis, "time / type=un subject=id");
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ExecError, layout(cx, s, view, view));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "R is singular") != null);
    for ([_][]const u8{ "/ type=sp(exp)(time) subject=id", "/ local", "time / r", "time time / type=un@un subject=id" }) |body| {
        diag.resetGap();
        try std.testing.expectError(error.ParseError, Testing.spec(cx, &ds, basis, body));
        try std.testing.expect(diag.gapHit());
    }
}

test "MIXED007 complete public repeated-measures input has 27 independent four-time blocks" {
    // Full public Example84.8 data, copied unchanged from its DATALINES input;
    // no estimation/influence result is inferred from this layout check.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/fixtures/stat/mixed/repeated_pr_data.txt", a, .limited(65536));
    var ds = Dataset.init(a, "pr");
    _ = try ds.addColumn("Person", .num);
    _ = try ds.addColumn("Gender", .char);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("Age", .num);
    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const person = try std.fmt.parseFloat(f64, fields.next().?);
        const gender = fields.next().?;
        for ([_]f64{ 8, 10, 12, 14 }) |age| {
            const y = try std.fmt.parseFloat(f64, fields.next().?);
            try ds.appendRow(&.{ .{ .num = person }, .{ .str = gender }, .{ .num = y }, .{ .num = age } });
        }
        try std.testing.expect(fields.next() == null);
    }
    const basis = coded.Spec{ .response = 2, .classes = &.{ 0, 1 }, .effects = &.{} };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const l = try layout(cx, try Testing.spec(cx, &ds, basis, "/ type=un subject=Person"), view, view);
    try std.testing.expectEqual(@as(usize, 108), l.n);
    try std.testing.expectEqual(@as(usize, 27), l.subject_labels.len);
    try std.testing.expectEqual(@as(usize, 4), l.dimension);
    try std.testing.expectEqual(@as(usize, 4), l.max_obs_per_subject);
    const r = try covariance(cx, l, &.{.{ .un = &.{ 5.1192, 2.4409, 3.9279, 3.6105, 2.7175, 5.9798, 2.5222, 3.0624, 3.8235, 4.6180 } }});
    const block = [_]f64{ 5.1192, 2.4409, 3.6105, 2.5222, 2.4409, 3.9279, 2.7175, 3.0624, 3.6105, 2.7175, 5.9798, 3.8235, 2.5222, 3.0624, 3.8235, 4.6180 };
    for (0..108) |i| {
        try std.testing.expectEqual(i / 4, l.subjects[i]);
        try std.testing.expectEqual(i % 4, l.positions[i]);
        try std.testing.expectEqual(i + 1, l.source_rows[i]);
        for (0..108) |j| try std.testing.expectEqual(if (i / 4 == j / 4) block[(i % 4) * 4 + j % 4] else 0, r.values[i * 108 + j]);
    }
    try std.testing.expectEqual(@TypeOf(r.status).positive_definite, r.status);
}

test "MIXED007 actual PROC entry reaches repeated-time validation and valid plotting gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "duplicate");
    for ([_][]const u8{ "id", "time", "y" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 3 } });
    try lib.put("duplicate", &ds);
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    const code = "proc mixed;class id time;model y=;repeated time /type=un subject=id;run;";
    try std.testing.expectError(error.ExecError, @import("mixed.zig").run(cx, &out, try lex.tokenize(a, code, &d)));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    diag.resetGap();
    const pending = "proc mixed;class id time;model y=;repeated /type=un subject=id;run;";
    try std.testing.expectError(error.ParseError, @import("mixed.zig").run(cx, &out, try lex.tokenize(a, pending, &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "TYPE=UN residual covariance estimation is not implemented") != null);
    diag.resetGap();
    try std.testing.expectError(error.ParseError, @import("mixed_parse.zig").parse(cx, try lex.tokenize(a, "proc mixed plot=boxplot;model y=;run;", &d)));
    try std.testing.expect(diag.gapHit());
    diag.resetGap();
    const invalid = "proc mixed method=type3;class id time;model y=;repeated time /type=un subject=id;run;";
    try std.testing.expectError(error.ParseError, @import("mixed.zig").run(cx, &out, try lex.tokenize(a, invalid, &d)));
    try std.testing.expect(!diag.gapHit());
}

test "MIXED007 explicit repeated CLASS levels index covariance without sorting observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    const cx = Testing.context(a, &d, &lib);
    var ds = Dataset.init(a, "shuffled");
    _ = try ds.addColumn("time", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 2, 0, 1 }) |time| try ds.appendRow(&.{ .{ .num = time }, .{ .num = 1 } });
    const basis = coded.Spec{ .response = 1, .classes = &.{0}, .effects = &.{} };
    const view = try selection.View.init(a, .{ .ds = &ds }, .{});
    const l = try layout(cx, try Testing.spec(cx, &ds, basis, "time / type=ar(1) subject=intercept"), view, view);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 1 }, l.positions);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, l.source_rows);
    const r = try covariance(cx, l, &.{.{ .ar1 = .{ .rho = 0.5, .variance = 4 } }});
    try std.testing.expectEqualSlices(f64, &.{ 4, 1, 2, 1, 4, 2, 2, 2, 4 }, r.values);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, Testing.spec(cx, &ds, basis, "y / type=un subject=intercept"));
    try std.testing.expect(!diag.gapHit());
    const too_wide = try Testing.spec(cx, &ds, basis, "time / type=un(4) subject=intercept");
    try std.testing.expectError(error.ParseError, layout(cx, too_wide, view, view));
    try std.testing.expect(diag.gapHit());
}
