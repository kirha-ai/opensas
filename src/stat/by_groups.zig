//! Consecutive BY groups for CORR, FREQ and UNIVARIATE.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const format = @import("../format.zig");
const io = @import("../io.zig");
const A = std.mem.Allocator;
const Token = @import("../lexer.zig").Token;
const lists = @import("variable_lists.zig");

/// Every statistical BY statement resolves against the input descriptor.
/// The final statement supplies the grouping keys and directions.
pub const Statements = struct {
    lists: std.ArrayList([]const Token) = .empty,

    pub fn read(self: *Statements, a: A, tokens: []const Token, i: *usize) !void {
        const start = i.* + 1;
        i.* = start;
        while (i.* < tokens.len and tokens[i.*].tag != .semicolon and tokens[i.*].tag != .eof) i.* += 1;
        try self.lists.append(a, tokens[start..i.*]);
    }

    pub fn resolve(self: Statements, a: A, ds: *const Dataset, d: *diag.Diagnostics) diag.Error!proc.ProcBy {
        var names: std.ArrayList([]const u8) = .empty;
        var directions: std.ArrayList(bool) = .empty;
        var notsorted = false;
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        for (self.lists.items, 0..) |tokens, statement_ix| {
            names.clearRetainingCapacity();
            directions.clearRetainingCapacity();
            notsorted = false;
            var i: usize = 0;
            var descending = false;
            while (i < tokens.len) {
                if (tokens[i].tag == .name and std.ascii.eqlIgnoreCase(tokens[i].text, "descending")) {
                    descending = true;
                    i += 1;
                    continue;
                }
                if (tokens[i].tag == .name and std.ascii.eqlIgnoreCase(tokens[i].text, "notsorted")) {
                    notsorted = true;
                    i += 1;
                    continue;
                }
                const line = tokens[i].line;
                const selected = try lists.next(a, ds, tokens, &i, d);
                for (selected) |n| {
                    const ci = ds.indexOf(n) orelse return d.fail(error.ParseError, line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                    const name = ds.columns.items[ci].name;
                    if (statement_ix + 1 == self.lists.items.len) {
                        const entry = try seen.getOrPut(a, ci);
                        if (entry.found_existing) try d.warn(line, "Duplication of by variable \"{s}\" ignored.", .{name});
                    }
                    try names.append(a, name);
                    try directions.append(a, descending);
                    descending = false; // DESCENDING qualifies the first variable of a range.
                }
            }
            if (descending) return d.fail(error.ParseError, 0, "BY DESCENDING must be followed by a variable name", .{});
        }
        return .{ .names = names.items, .desc = directions.items, .notsorted = notsorted };
    }
};

/// Procedure-local FORMAT changes the descriptor without rewriting shared input observations.
pub fn withFormats(a: A, ds: *Dataset, specs: []const proc.VarSpec) !*Dataset {
    if (specs.len == 0) return ds;
    const view = try a.create(Dataset);
    view.* = ds.*;
    view.columns = .empty;
    try view.columns.appendSlice(a, ds.columns.items);
    for (specs) |spec| if (view.indexOf(spec.name)) |ci| {
        view.columns.items[ci].format = if (spec.spec.len == 0) null else spec.spec;
    };
    return view;
}

fn formatted(ds: *const Dataset, cols: []const usize) bool {
    for (cols) |ci| if (ds.columns.items[ci].format != null) return true;
    return false;
}

fn sameKey(a: A, ds: *const Dataset, previous: []const Value, next: []const Value, cols: []const usize) !bool {
    for (cols) |ci| {
        if (proc.cmpValue(previous[ci], next[ci]) == .eq) continue;
        const spec = ds.columns.items[ci].format orelse return false;
        const lhs = try format.apply(a, previous[ci], spec);
        const rhs = try format.apply(a, next[ci], spec);
        if (!std.mem.eql(u8, std.mem.trimEnd(u8, lhs, " "), std.mem.trimEnd(u8, rhs, " "))) return false;
    }
    return true;
}

fn slices(a: A, ds: *const Dataset, cols: []const usize) ![]proc.BySlice {
    if (!formatted(ds, cols)) return proc.bySlices(a, ds.rows.items, cols);

    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var groups: std.ArrayList(proc.BySlice) = .empty;
    const rows = ds.rows.items;
    var first: usize = 0;
    while (first < rows.len) {
        var next = first + 1;
        while (next < rows.len) : (next += 1) {
            _ = scratch.reset(.retain_capacity);
            if (!try sameKey(scratch.allocator(), ds, rows[next - 1], rows[next], cols)) break;
        }
        try groups.append(a, .{ .rep = rows[first], .rows = rows[first..next] });
        first = next;
    }
    return groups.items;
}

/// M9 checks the original key on the first observation of successive formatted
/// groups. An internal reversal within a single formatted group is valid.
pub fn checkedSlices(a: A, ds: *const Dataset, cols: []const usize, desc: []const bool, notsorted: bool, d: *diag.Diagnostics) diag.Error![]proc.BySlice {
    const groups = try slices(a, ds, cols);
    if (!notsorted and groups.len > 1) {
        for (groups[1..], groups[0 .. groups.len - 1]) |next, previous| {
            if (proc.byOrderViolation(next.rep.?, previous.rep.?, cols, desc, ds.sortseq_linguistic orelse io.global_sortseq_linguistic)) |k| {
                return d.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (desc[k]) @as([]const u8, "descending") else "ascending" });
            }
        }
    }
    return groups;
}

pub fn reportNote(a: A, d: *diag.Diagnostics, ds: *const Dataset, row: []const Value, by: []const usize) !void {
    var keys: std.ArrayList(u8) = .empty;
    for (by, 0..) |ci, j| {
        const info = ds.columns.items[ci];
        const text = if (info.format) |fmt| try format.apply(a, row[ci], fmt) else try proc.cellText(a, row[ci]);
        if (j > 0) try keys.append(a, ' ');
        try keys.print(a, "{s}={s}", .{ info.name, std.mem.trim(u8, text, " ") });
    }
    try d.report(.note, 0, "The above message was for the following BY group:\n      {s}", .{keys.items});
}

pub fn appendLine(a: A, out: *std.ArrayList(u8), ds: *Dataset, row: []const Value, cols: []const usize) !void {
    if (!formatted(ds, cols)) return proc.appendByLine(a, out, ds, row, cols);
    const display = try a.dupe(Value, row);
    for (cols) |ci| if (ds.columns.items[ci].format) |spec| {
        display[ci] = .{ .str = std.mem.trim(u8, try format.apply(a, row[ci], spec), " ") };
    };
    try proc.appendByLine(a, out, ds, display, cols);
}

test "statistical BY numbered keys resolve in source order with one descending modifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "g1", "g3", "g2" }) |name| _ = try ds.addColumn(name, .num);
    var d = diag.Diagnostics.init(a);
    const tokens = try @import("../lexer.zig").tokenize(a, "by descending g1-g3;", &d);
    var by: Statements = .{};
    var i: usize = 0;
    try by.read(a, tokens, &i);
    const resolved = try by.resolve(a, &ds, &d);
    for (resolved.names, [_][]const u8{ "g1", "g2", "g3" }) |actual, expected| try std.testing.expectEqualStrings(expected, actual);
    try std.testing.expectEqualSlices(bool, &.{ true, false, false }, resolved.desc);
}
