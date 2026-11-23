//! Consecutive BY groups for CORR, FREQ and UNIVARIATE.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const format = @import("../format.zig");
const io = @import("../io.zig");
const A = std.mem.Allocator;

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

pub fn appendLine(a: A, out: *std.ArrayList(u8), ds: *Dataset, row: []const Value, cols: []const usize) !void {
    if (!formatted(ds, cols)) return proc.appendByLine(a, out, ds, row, cols);
    const display = try a.dupe(Value, row);
    for (cols) |ci| if (ds.columns.items[ci].format) |spec| {
        display[ci] = .{ .str = std.mem.trim(u8, try format.apply(a, row[ci], spec), " ") };
    };
    try proc.appendByLine(a, out, ds, display, cols);
}
