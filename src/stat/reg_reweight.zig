//! REWEIGHT selection and private weight state (S154 physical pp.8595–8598).
//! Selectors use the last fitted model; updating weights never changes DATA.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Value = @import("../value.zig").Value;
const Dataset = @import("../dataset.zig").Dataset;
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;
pub const Statistic = enum { prediction, residual, student, rstudent, leverage, cookd, stdp, stdr };
pub const Source = union(enum) { column: usize, observation, statistic: Statistic };
pub const Comparison = enum { lt, le, gt, ge, eq, ne };
pub const Atom = struct { source: Source, comparison: Comparison, value: Value };
pub const Request = struct { kind: enum { change, status, undo } = .change, selection: enum { previous, all, condition } = .previous, first: ?Atom = null, second: ?Atom = null, logical_and: bool = true, weight: f64 = 0, reset: bool = false, nolist: bool = false };
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return i < t.len and t[i].tag == .name and std.ascii.eqlIgnoreCase(t[i].text, name);
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!Value {
    var sign: f64 = 1;
    if (i.* < t.len and (t[i.*].tag == .minus or t[i.*].tag == .plus)) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (i.* == t.len) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: missing numeric value", .{});
    if (t[i.*].tag == .dot) {
        i.* += 1;
        if (i.* < t.len and t[i.*].tag == .name and t[i.*].text.len == 1) {
            const c = t[i.*].text[0];
            if (std.ascii.isAlphabetic(c) or c == '_') {
                i.* += 1;
                return Value.specialMissing(c);
            }
        }
        return Value.missing;
    }
    if (t[i.*].tag != .number) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG REWEIGHT: expected numeric value", .{});
    const value = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return error.ParseError);
    i.* += 1;
    if (!std.math.isFinite(value)) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: nonfinite value", .{});
    return .{ .num = value };
}
fn atom(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!Atom {
    if (i.* >= t.len or t[i.*].tag != .name) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: expected a variable or diagnostic", .{});
    const name = t[i.*].text;
    i.* += 1;
    var source: Source = undefined;
    if (i.* < t.len and t[i.*].tag == .dot) {
        i.* += 1;
        if (std.ascii.eqlIgnoreCase(name, "obs")) source = .observation else {
            const statistic: Statistic = if (std.ascii.eqlIgnoreCase(name, "r") or std.ascii.eqlIgnoreCase(name, "residual")) .residual else if (std.ascii.eqlIgnoreCase(name, "p") or std.ascii.eqlIgnoreCase(name, "predicted")) .prediction else if (std.ascii.eqlIgnoreCase(name, "student")) .student else if (std.ascii.eqlIgnoreCase(name, "rstudent")) .rstudent else if (std.ascii.eqlIgnoreCase(name, "h") or std.ascii.eqlIgnoreCase(name, "leverage")) .leverage else if (std.ascii.eqlIgnoreCase(name, "cookd")) .cookd else if (std.ascii.eqlIgnoreCase(name, "stdp")) .stdp else if (std.ascii.eqlIgnoreCase(name, "stdr")) .stdr else {
                inline for (.{ "dffits", "covratio", "press", "stdi", "lcl", "ucl", "lclm", "uclm", "dfbetas" }) |known| if (std.ascii.eqlIgnoreCase(name, known)) return proc.failGap(cx.diags, 0, "PROC REG REWEIGHT: diagnostic {s}. is not implemented", .{name});
                return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: unknown diagnostic {s}.", .{name});
            };
            source = .{ .statistic = statistic };
        }
    } else source = .{ .column = ds.indexOf(name) orelse return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: variable {s} not found", .{name}) };
    if (i.* >= t.len) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: missing comparison", .{});
    const comparison: Comparison = switch (t[i.*].tag) {
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
        .eq => .eq,
        .ne => .ne,
        .name => if (kw(t, i.*, "lt")) .lt else if (kw(t, i.*, "le")) .le else if (kw(t, i.*, "gt")) .gt else if (kw(t, i.*, "ge")) .ge else if (kw(t, i.*, "eq")) .eq else if (kw(t, i.*, "ne")) .ne else return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: invalid comparison", .{}),
        else => return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: invalid comparison", .{}),
    };
    i.* += 1;
    const value: Value = if (i.* < t.len and t[i.*].tag == .string) value: {
        const text = t[i.*].text;
        i.* += 1;
        if (text.len > 8) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: character values cannot exceed eight characters", .{});
        break :value .{ .str = text };
    } else try number(cx, t, i);
    const character = source == .column and ds.columns.items[source.column].type == .char;
    if (character != (value == .str)) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: condition value type does not match variable", .{});
    return .{ .source = source, .comparison = comparison, .value = value };
}
pub fn parse(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token) diag.Error!Request {
    var result: Request = .{};
    var i: usize = 0;
    if (kw(t, 0, "status") or kw(t, 0, "undo")) {
        if (t.len != 1) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT STATUS/UNDO cannot take conditions or options", .{});
        result.kind = if (kw(t, 0, "status")) .status else .undo;
        return result;
    }
    if (kw(t, 0, "allobs")) {
        result.selection = .all;
        i = 1;
    } else if (t.len > 0 and t[0].tag != .slash) {
        result.selection = .condition;
        result.first = try atom(cx, ds, t, &i);
        if (i < t.len and (kw(t, i, "and") or kw(t, i, "or") or t[i].tag == .amp or t[i].tag == .pipe)) {
            result.logical_and = kw(t, i, "and") or t[i].tag == .amp;
            i += 1;
            result.second = try atom(cx, ds, t, &i);
        }
    }
    if (i < t.len) {
        if (t[i].tag != .slash) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT supports one or two comparisons", .{});
        i += 1;
        if (i == t.len) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: expected an option after /", .{});
    }
    var specified_weight = false;
    while (i < t.len) {
        if (kw(t, i, "reset")) {
            result.reset = true;
            i += 1;
        } else if (kw(t, i, "nolist")) {
            result.nolist = true;
            i += 1;
        } else if (kw(t, i, "weight")) {
            if (i + 1 >= t.len or t[i + 1].tag != .eq) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT WEIGHT requires =", .{});
            i += 2;
            const value = try number(cx, t, &i);
            if (std.math.isNan(value.num) or value.num < 0) return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT WEIGHT must be nonnegative", .{});
            result.weight = value.num;
            specified_weight = true;
        } else return cx.diags.fail(error.ParseError, 0, "PROC REG REWEIGHT: unknown option", .{});
    }
    if (result.reset and specified_weight) return proc.failGap(cx.diags, 0, "PROC REG REWEIGHT: combining RESET and WEIGHT is not implemented", .{});
    return result;
}
pub const DiagnosticModel = struct { response: usize, regressors: []const usize, intercept: bool, fit: Fit, source_rows: []const usize, precision_weights: []const f64, has_frequency: bool };
fn statisticValue(ds: *const Dataset, required: []const usize, model: DiagnosticModel, index: usize, kind: Statistic) diag.Error!Value {
    const row = ds.rows.items[index];
    for (required) |ci| if (!std.math.isFinite(row[ci].num)) return Value.missing;
    const p = model.fit.coefficients.len;
    if (p != model.regressors.len + @as(usize, if (model.intercept) 1 else 0)) return error.ExecError;
    var prediction: f128 = if (model.intercept) model.fit.coefficients[0] else 0;
    for (model.regressors, 0..) |ci, j| prediction += @as(f128, row[ci].num) * model.fit.coefficients[j + @as(usize, if (model.intercept) 1 else 0)];
    const predicted: f64 = @floatCast(prediction);
    if (!std.math.isFinite(predicted)) return error.ExecError;
    const residual = row[model.response].num - predicted;
    if (kind == .prediction) return .{ .num = predicted };
    if (kind == .residual) return .{ .num = residual };
    if (model.has_frequency) return error.ExecError;
    const found = std.mem.indexOfScalar(usize, model.source_rows, index + 1);
    const weight = if (found) |i| model.precision_weights[i] else 0;
    const leverage = if (found) |i| model.fit.leverage[i] else 0;
    if (kind == .leverage) return .{ .num = leverage };
    if (!(model.fit.mse > 0) or !std.math.isFinite(model.fit.mse)) return Value.missing;
    if (kind == .stdp) {
        var variance: f128 = 0;
        for (0..p) |j| for (0..p) |k| {
            const left = if (model.intercept and j == 0) @as(f64, 1) else row[model.regressors[j - @as(usize, if (model.intercept) 1 else 0)]].num;
            const right = if (model.intercept and k == 0) @as(f64, 1) else row[model.regressors[k - @as(usize, if (model.intercept) 1 else 0)]].num;
            variance += @as(f128, left) * model.fit.covariance_unscaled[j * p + k] * right;
        };
        return .{ .num = @sqrt(@max(0, @as(f64, @floatCast(variance)) * model.fit.mse)) };
    }
    if (!(weight > 0) or !(leverage < 1 - 64 * std.math.floatEps(f64))) return Value.missing;
    const standard = @sqrt(model.fit.mse * (1 - leverage) / weight);
    return .{ .num = switch (kind) {
        .stdr => standard,
        .student => residual / standard,
        .cookd => if (model.fit.rank > 0) weight * residual * residual / model.fit.mse / @as(f64, @floatFromInt(model.fit.rank)) * leverage / ((1 - leverage) * (1 - leverage)) else std.math.nan(f64),
        .rstudent => value: {
            if (model.fit.df_error <= 1) break :value std.math.nan(f64);
            const deleted = (model.fit.sse - weight * residual * residual / (1 - leverage)) / @as(f64, @floatFromInt(model.fit.df_error - 1));
            break :value if (deleted > 0) residual / @sqrt(deleted * (1 - leverage) / weight) else std.math.nan(f64);
        },
        else => unreachable,
    } };
}
fn compare(left: Value, right: Value, operation: Comparison) bool {
    const order: std.math.Order = if (left == .str) std.mem.order(u8, std.mem.trimEnd(u8, left.str, " "), std.mem.trimEnd(u8, right.str, " ")) else order: {
        const lm = std.math.isNan(left.num);
        const rm = std.math.isNan(right.num);
        if (lm and rm) break :order std.math.order(Value.missingRank(left.num), Value.missingRank(right.num));
        if (lm) break :order .lt;
        if (rm) break :order .gt;
        break :order std.math.order(left.num, right.num);
    };
    return switch (operation) {
        .lt => order == .lt,
        .le => order != .gt,
        .gt => order == .gt,
        .ge => order != .lt,
        .eq => order == .eq,
        .ne => order != .eq,
    };
}
fn matchesAtom(ds: *const Dataset, required: []const usize, model: ?DiagnosticModel, row: usize, condition: Atom) diag.Error!bool {
    const value: Value = switch (condition.source) {
        .column => |ci| ds.rows.items[row][ci],
        .observation => .{ .num = @floatFromInt(row + 1) },
        .statistic => |kind| try statisticValue(ds, required, model orelse return error.ExecError, row, kind),
    };
    return compare(value, condition.value, condition.comparison);
}
pub fn selection(a: A, ds: *const Dataset, required: []const usize, models: []const DiagnosticModel, request: Request, previous: ?[]const bool) diag.Error![]const bool {
    const n = ds.rows.items.len;
    if (request.selection == .previous) {
        const saved = previous orelse return error.ExecError;
        if (saved.len != n) return error.ExecError;
        return saved;
    }
    const result = try a.alloc(bool, n);
    if (request.selection == .all) {
        @memset(result, true);
        return result;
    }
    const first = request.first orelse return error.ExecError;
    const diagnostics = first.source == .statistic or (request.second != null and request.second.?.source == .statistic);
    if (diagnostics and models.len == 0) return error.ExecError;
    for (result, 0..) |*selected, i| {
        selected.* = false;
        const count = if (diagnostics) models.len else 1;
        for (0..count) |j| {
            const model: ?DiagnosticModel = if (diagnostics) models[j] else null;
            const left = try matchesAtom(ds, required, model, i, first);
            const value = if (request.second) |second| value: {
                const right = try matchesAtom(ds, required, model, i, second);
                break :value if (request.logical_and) left and right else left or right;
            } else left;
            if (value) {
                selected.* = true;
                break;
            }
        }
    }
    return result;
}
pub const State = struct {
    original: []const f64,
    current: []const f64,
    selected: ?[]const bool = null,
    previous: ?[]const f64 = null,
    after_undo: bool = false,
    pub fn init(a: A, ds: *const Dataset, weight: ?usize) !State {
        const values = try a.alloc(f64, ds.rows.items.len);
        for (values, ds.rows.items) |*v, row| v.* = if (weight) |ci| row[ci].num else 1;
        return .{ .original = values, .current = values };
    }
    pub fn change(self: *State, a: A, chosen: []const bool, request: Request) !void {
        if (chosen.len != self.current.len) return error.ExecError;
        const values = try a.dupe(f64, self.current);
        for (chosen, 0..) |selected, i| if (selected) {
            values[i] = if (request.reset) self.original[i] else request.weight;
        };
        self.previous = self.current;
        self.current = values;
        self.selected = chosen;
        self.after_undo = false;
    }
    pub fn undo(self: *State) !void {
        self.current = self.previous orelse return error.ExecError;
        self.previous = null;
        self.after_undo = true;
    }
};
