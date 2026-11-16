//! Formatted key-cell resolution shared by numerical plot consumers/builders.
const std = @import("std");
const univ = @import("univariate.zig");
const h = @import("../proc.zig").UnivariateHelpers;
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
pub const Groups = struct { groups: []const h.MeansGroup, key_index: usize = 0 };

pub fn order(a: std.mem.Allocator, resolved: Groups, move: bool) ![]const usize {
    const indices = try a.alloc(usize, resolved.groups.len);
    if (indices.len == 0) return indices;
    var at: usize = 0;
    if (move) {
        indices[0] = resolved.key_index;
        at = 1;
    }
    for (0..indices.len) |i| {
        if (move and i == resolved.key_index) continue;
        indices[at] = i;
        at += 1;
    }
    return indices;
}

pub fn resolve(a: std.mem.Allocator, d: *diag.Diagnostics, ds: *Dataset, groups: []const h.MeansGroup, columns: []const usize, options: univ.Options) diag.Error!Groups {
    if (options.key_levels.len == 0 or groups.len == 0) return .{ .groups = groups };
    if (options.key_levels.len != columns.len) return d.fail(error.ParseError, 0, "UNIVARIATE: KEYLEVEL does not match CLASS variables", .{});
    const values = try a.alloc(Value, columns.len);
    for (columns, options.key_levels, 0..) |column, wanted, j| {
        var found = false;
        var fallback: ?Value = null;
        for (groups) |group| {
            var prefix = true;
            for (columns[0..j], values[0..j]) |prior, value| if (h.compareValue(group.rep[prior], value) != .eq) {
                prefix = false;
                break;
            };
            if (!prefix) continue;
            if (fallback == null) fallback = group.rep[column];
            const label = try formatted(a, ds, group.rep, column);
            if (std.mem.eql(u8, label, std.mem.trimEnd(u8, wanted, " "))) {
                values[j] = group.rep[column];
                found = true;
                break;
            }
        }
        if (!found) {
            try d.warn(0, "UNIVARIATE: KEYLEVEL={s} does not match a CLASS level; using the first available level", .{wanted});
            values[j] = fallback orelse return d.fail(error.ParseError, 0, "UNIVARIATE: unable to resolve key cell", .{});
        }
    }
    for (groups, 0..) |group, index| {
        var match = true;
        for (columns, values) |column, value| if (h.compareValue(group.rep[column], value) != .eq) {
            match = false;
            break;
        };
        if (match) {
            if (columns.len == 2 and options.key_move) {
                // SAS promotes the selected first-class block, and promotes
                // the selected second level only within that block. Other
                // first-class blocks keep their original second-level order.
                const ordered = try a.alloc(h.MeansGroup, groups.len);
                ordered[0] = group;
                var at: usize = 1;
                for (groups, 0..) |other, j| if (j != index and h.compareValue(other.rep[columns[0]], values[0]) == .eq) {
                    ordered[at] = other;
                    at += 1;
                };
                for (groups) |other| if (h.compareValue(other.rep[columns[0]], values[0]) != .eq) {
                    ordered[at] = other;
                    at += 1;
                };
                return .{ .groups = ordered, .key_index = 0 };
            }
            return .{ .groups = groups, .key_index = index };
        }
    }
    return d.fail(error.ParseError, 0, "UNIVARIATE: unable to resolve key cell", .{});
}

fn formatted(a: std.mem.Allocator, ds: *Dataset, row: []const Value, col: usize) ![]const u8 {
    if (row[col] == .str) return std.mem.trimEnd(u8, row[col].str, " ");
    return std.mem.trim(u8, try @import("../format.zig").apply(a, row[col], ds.columns.items[col].format orelse "BEST12."), " ");
}
