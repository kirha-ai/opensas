//! Full-rank REF/EFFECT coding for binary main-effects LOGISTIC.
//! S154 physical pp.418-420 and5851-5854. Reuses shared typed/formatted levels.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const levels = @import("class_levels.zig");
const proc = @import("../proc.zig");
const A = std.mem.Allocator;
pub const Coding = enum { reference, effect };
pub const ClassSpec = struct { column: usize, reference: levels.Reference = .last, coding: ?Coding = null };
pub const Spec = struct { response: usize, event: ?levels.Reference = null, response_reference: ?levels.Reference = null, response_order: levels.Order = .formatted, response_descending: bool = false, classes: []const ClassSpec = &.{}, effects: []const usize, terms: ?[]const []const usize = null, frequency: ?usize = null, weight: ?usize = null, coding: Coding = .effect };
pub const Class = struct { column: usize, map: levels.Levels, reference: usize, coding: Coding };
pub const Parameter = struct { name: []const u8, level: ?[]const u8 = null };
pub const Effect = struct { column: usize, start: usize, len: usize, class_index: ?usize = null, variables: []const usize, name: []const u8 };
pub const Design = struct { x: []const f64, y: []const f64, n: usize, p: usize, classes: []const Class, parameters: []const Parameter, effects: []const Effect, response: levels.Levels, event_index: usize, frequencies: []const f64, weights: []const f64, source_rows: []const usize, total_frequency: f64 };
pub fn code(level: usize, reference: usize, parameter_level: usize, coding: Coding) f64 {
    if (level == reference) return if (coding == .effect) -1 else 0;
    return if (level == parameter_level) 1 else 0;
}
fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}
fn choose(map: levels.Levels, choice: levels.Reference, column: @import("../dataset.zig").Column) ?usize {
    // Unformatted numeric references identify raw values, not a rounded BEST12
    // label that might be shared by distinct CLASS levels.
    if (choice == .label and column.type == .num and column.format == null) {
        const value = std.fmt.parseFloat(f64, choice.label) catch return null;
        for (map.levels, 0..) |level, i| if (proc.cmpValue(level.value, .{ .num = value }) == .eq) return i;
        return null;
    }
    if (map.reference(choice)) |v| return v;
    if (choice == .label and column.type == .num) {
        const number = std.fmt.parseFloat(f64, choice.label) catch return null;
        for (map.levels, 0..) |level, i| if (proc.cmpValue(level.value, .{ .num = number }) == .eq) return i;
    }
    return null;
}
pub fn build(a: A, ds: *const Dataset, s: Spec, d: *diag.Diagnostics) diag.Error!Design {
    if (s.response >= ds.columns.items.len) return error.ExecError;
    var needed: std.ArrayList(usize) = .empty;
    try needed.append(a, s.response);
    for (s.classes) |c| {
        if (c.column >= ds.columns.items.len) return error.ExecError;
        try needed.append(a, c.column);
    }
    for (s.effects) |ci| {
        if (ci >= ds.columns.items.len) return error.ExecError;
        try needed.append(a, ci);
    }
    var rows: std.ArrayList([]const Value) = .empty;
    var frequencies: std.ArrayList(f64) = .empty;
    var weights: std.ArrayList(f64) = .empty;
    var source_rows: std.ArrayList(usize) = .empty;
    var total_frequency: f64 = 0;
    for (ds.rows.items, 0..) |row, source| {
        const frequency = if (s.frequency) |ci| @trunc(row[ci].num) else 1;
        const weight = if (s.weight) |ci| row[ci].num else 1;
        if (std.math.isNan(frequency) or frequency < 1 or std.math.isNan(weight) or weight <= 0) continue;
        if (!std.math.isFinite(frequency) or !std.math.isFinite(weight)) return error.ExecError;
        var valid = true;
        for (needed.items) |ci| {
            if (ci >= row.len) return error.ExecError;
            if (missing(row[ci])) valid = false else if (row[ci] == .num and !std.math.isFinite(row[ci].num)) return error.ExecError;
        }
        if (valid) {
            try rows.append(a, row);
            try frequencies.append(a, frequency);
            try weights.append(a, weight);
            try source_rows.append(a, source);
            total_frequency += frequency;
        }
    }
    if (rows.items.len == 0) return error.ExecError;
    var response = try levels.build(a, ds, rows.items, s.response, .{ .frequencies = frequencies.items, .order = s.response_order });
    // S154 physical pp.5870–5871,5905–5906: ORDER is applied before DESC;
    // both the displayed profile and row indices must describe the same order.
    if (s.response_descending) {
        const reversed = try a.dupe(levels.Level, response.levels);
        std.mem.reverse(levels.Level, reversed);
        const remapped = try a.dupe(?usize, response.row_to_level);
        for (remapped) |*entry| if (entry.*) |index| {
            entry.* = reversed.len - 1 - index;
        };
        response.levels = reversed;
        response.row_to_level = remapped;
    }
    if (response.levels.len > 2) return proc.failGap(d, 0, "PROC LOGISTIC: only binary response models are implemented", .{});
    if (response.levels.len < 2) return d.fail(error.ExecError, 0, "PROC LOGISTIC: two response levels are required", .{});
    const choice = s.event orelse s.response_reference orelse levels.Reference.first;
    // A formatted response category must be specified by its formatted value.
    // Do not reuse CLASS's historical raw-value fallback for response options.
    const selected = (if (ds.columns.items[s.response].format == null)
        choose(response, choice, ds.columns.items[s.response])
    else
        response.reference(choice)) orelse return d.fail(error.ParseError, 0, "PROC LOGISTIC: EVENT/REF value is not a response level", .{});
    const event_index = if (s.event == null and s.response_reference != null) 1 - selected else selected;
    const classes = try a.alloc(Class, s.classes.len);
    for (s.classes, 0..) |c, i| {
        const map = try levels.build(a, ds, rows.items, c.column, .{ .frequencies = frequencies.items });
        const full = try levels.build(a, ds, ds.rows.items, c.column, .{});
        if (full.levels.len != map.levels.len) return proc.failGap(d, 0, "PROC LOGISTIC: CLASS levels lost through complete-case exclusion are not implemented", .{});
        if (map.levels.len < 2) return proc.failGap(d, 0, "PROC LOGISTIC: one-level CLASS effects are not implemented", .{});
        classes[i] = .{ .column = c.column, .map = map, .reference = choose(map, c.reference, ds.columns.items[c.column]) orelse return d.fail(error.ParseError, 0, "PROC LOGISTIC: reference value is not a CLASS level", .{}), .coding = c.coding orelse s.coding };
    }
    var parameters: std.ArrayList(Parameter) = .empty;
    try parameters.append(a, .{ .name = "Intercept" });
    var effects: std.ArrayList(Effect) = .empty;
    var terms: std.ArrayList([]const usize) = .empty;
    if (s.terms) |items| try terms.appendSlice(a, items) else for (s.effects) |ci| try terms.append(a, try a.dupe(usize, &.{ci}));
    for (terms.items) |variables| {
        const ci = variables[0];
        var class_index: ?usize = null;
        for (classes, 0..) |c, k| if (c.column == ci) {
            class_index = k;
            break;
        };
        if (variables.len > 1) {
            for (variables) |v| for (classes) |c| if (c.column == v) return proc.failGap(d, 0, "PROC LOGISTIC: CLASS interactions are not implemented", .{});
            class_index = null;
        }
        var name: std.ArrayList(u8) = .empty;
        for (variables, 0..) |v, k| {
            if (k > 0) try name.append(a, '*');
            try name.appendSlice(a, ds.columns.items[v].name);
        }
        const start = parameters.items.len;
        if (class_index) |k| {
            const c = classes[k];
            for (c.map.levels, 0..) |level, j| if (j != c.reference) try parameters.append(a, .{ .name = name.items, .level = level.label });
        } else {
            for (variables) |v| if (ds.columns.items[v].type != .num) return error.ExecError;
            try parameters.append(a, .{ .name = name.items });
        }
        try effects.append(a, .{ .column = ci, .start = start, .len = parameters.items.len - start, .class_index = class_index, .variables = variables, .name = name.items });
    }
    const p = parameters.items.len;
    const np = std.math.mul(usize, rows.items.len, p) catch return error.ExecError;
    const x = try a.alloc(f64, np);
    const y = try a.alloc(f64, rows.items.len);
    for (rows.items, 0..) |row, i| {
        y[i] = if (response.row_to_level[i].? == event_index) 1 else 0;
        x[i * p] = 1;
        for (effects.items) |e| {
            if (e.class_index) |k| {
                const c = classes[k];
                var j = e.start;
                for (0..c.map.levels.len) |level| if (level != c.reference) {
                    x[i * p + j] = code(c.map.row_to_level[i].?, c.reference, level, c.coding);
                    j += 1;
                };
            } else {
                var product: f64 = 1;
                for (e.variables) |ci| product *= row[ci].num;
                if (!std.math.isFinite(product)) return error.ExecError;
                x[i * p + e.start] = product;
            }
        }
    }
    return .{ .x = x, .y = y, .n = rows.items.len, .p = p, .classes = classes, .parameters = parameters.items, .effects = effects.items, .response = response, .event_index = event_index, .frequencies = frequencies.items, .weights = weights.items, .source_rows = source_rows.items, .total_frequency = total_frequency };
}

pub fn originalFixture(a: A) !Dataset {
    var ds = Dataset.init(a, "binary");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("event", .num);
    for (0..12) |i| try ds.appendRow(&.{ .{ .str = if (i < 6) "A" else "B" }, .{ .num = @floatFromInt(i + 1) }, .{ .num = if ((i + 1) % 3 == 0) 1 else 0 } });
    return ds;
}
test "LOGISTIC_DESIGN manual four-level REF and EFFECT matrices" {
    for (0..4) |level| for (0..3) |parameter| {
        try std.testing.expectEqual(@as(f64, if (level == parameter) 1 else 0), code(level, 3, parameter, .reference));
        try std.testing.expectEqual(@as(f64, if (level == 3) -1 else if (level == parameter) 1 else 0), code(level, 3, parameter, .effect));
    };
}
test "LOGISTIC_DESIGN prediction covariance and odds-ratio invariance" {
    const kernel = @import("logistic_fit.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try originalFixture(a);
    var diagnostics = diag.Diagnostics.init(a);
    const ref = try build(a, &ds, .{ .response = 2, .event = .{ .label = "1" }, .classes = &.{.{ .column = 0, .reference = .{ .label = "A" } }}, .effects = &.{ 0, 1 }, .coding = .reference }, &diagnostics);
    const effect = try build(a, &ds, .{ .response = 2, .event = .{ .label = "1" }, .classes = &.{.{ .column = 0, .reference = .{ .label = "A" } }}, .effects = &.{ 0, 1 }, .coding = .effect }, &diagnostics);
    const r = try kernel.fit(a, ref.x, ref.y, ref.n, ref.p, .{});
    const e = try kernel.fit(a, effect.x, effect.y, effect.n, effect.p, .{});
    for (r.probabilities, e.probabilities) |x, y| try std.testing.expectApproxEqAbs(x, y, 1e-11);
    try std.testing.expectApproxEqAbs(r.coefficients[0] + r.coefficients[1] / 2, e.coefficients[0], 1e-10);
    try std.testing.expectApproxEqAbs(r.coefficients[1] / 2, e.coefficients[1], 1e-10);
    try std.testing.expectApproxEqAbs(r.covariance[4] / 4, e.covariance[4], 1e-10);
    try std.testing.expectApproxEqAbs(@exp(r.coefficients[1]), @exp(2 * e.coefficients[1]), 1e-12);
    try std.testing.expectApproxEqAbs(r.log_likelihood, e.log_likelihood, 1e-12);
    const assoc = kernel.association(ref.y, r.probabilities);
    try std.testing.expectEqual(@as(usize, 32), assoc.pairs);
    try std.testing.expectEqual(@as(usize, 24), assoc.concordant);
}

test "LOGISTIC_DESIGN changing reference or event transforms estimates rather than predictions" {
    const kernel = @import("logistic_fit.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try originalFixture(a);
    var diagnostics = diag.Diagnostics.init(a);
    const first = try build(a, &ds, .{ .response = 2, .event = .last, .classes = &.{.{ .column = 0, .reference = .first }}, .effects = &.{ 0, 1 }, .coding = .reference }, &diagnostics);
    const last = try build(a, &ds, .{ .response = 2, .event = .last, .classes = &.{.{ .column = 0, .reference = .last }}, .effects = &.{ 0, 1 }, .coding = .reference }, &diagnostics);
    const flip = try build(a, &ds, .{ .response = 2, .event = .first, .classes = &.{.{ .column = 0, .reference = .first }}, .effects = &.{ 0, 1 }, .coding = .reference }, &diagnostics);
    const r = try kernel.fit(a, first.x, first.y, first.n, first.p, .{});
    const s = try kernel.fit(a, last.x, last.y, last.n, last.p, .{});
    const f = try kernel.fit(a, flip.x, flip.y, flip.n, flip.p, .{});
    for (r.probabilities, s.probabilities, f.probabilities) |x, y, z| {
        try std.testing.expectApproxEqAbs(x, y, 1e-11);
        try std.testing.expectApproxEqAbs(1 - x, z, 1e-11);
    }
    try std.testing.expectApproxEqAbs(r.coefficients[0] + r.coefficients[1], s.coefficients[0], 1e-10);
    try std.testing.expectApproxEqAbs(-r.coefficients[1], s.coefficients[1], 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 1), @exp(r.coefficients[1]) * @exp(s.coefficients[1]), 1e-10);
}

test "LOGISTIC_DESIGN four-level fitted probabilities and multi-column odds contrasts" {
    const kernel = @import("logistic_fit.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "four");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("y", .num);
    const labels = [_][]const u8{ "A", "B", "C", "D" };
    const counts = [_]usize{ 1, 2, 3, 2 };
    for (labels, counts) |label, events| for (0..4) |i| try ds.appendRow(&.{ .{ .str = label }, .{ .num = if (i < events) 1 else 0 } });
    var d = diag.Diagnostics.init(a);
    const ref = try build(a, &ds, .{ .response = 1, .event = .last, .classes = &.{.{ .column = 0, .reference = .first }}, .effects = &.{0}, .coding = .reference }, &d);
    const effect = try build(a, &ds, .{ .response = 1, .event = .last, .classes = &.{.{ .column = 0, .reference = .first }}, .effects = &.{0}, .coding = .effect }, &d);
    const r = try kernel.fit(a, ref.x, ref.y, ref.n, ref.p, .{ .gconv = 1e-20 });
    const e = try kernel.fit(a, effect.x, effect.y, effect.n, effect.p, .{ .gconv = 1e-20 });
    for (r.probabilities, e.probabilities, 0..) |pr, pe, i| {
        try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(counts[i / 4])) / 4, pr, 1e-10);
        try std.testing.expectApproxEqAbs(pr, pe, 1e-10);
    }
    var sum: f64 = 0;
    for (e.coefficients[1..]) |v| sum += v;
    for (1..4) |j| try std.testing.expectApproxEqAbs(@exp(r.coefficients[j]), @exp(e.coefficients[j] + sum), 1e-9);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 3)), r.coefficients[1], 1e-9);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 9)), r.coefficients[2], 1e-9);
}
