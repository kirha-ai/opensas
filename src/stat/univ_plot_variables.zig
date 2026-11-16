//! Shared variable-list syntax and resolution for UNIVARIATE plot statements.
const std = @import("std");
const h = @import("../proc.zig").UnivariateHelpers;
const Token = @import("../lexer.zig").Token;
const Dataset = @import("../dataset.zig").Dataset;
const diag = @import("../diag.zig");
pub fn parse(a: std.mem.Allocator, tokens: []const Token, i: *usize) ![][]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    while (tokens[i.*].tag == .name) : (i.* += 1) {
        if (tokens[i.* + 1].tag == .minus and tokens[i.* + 2].tag == .name) {
            try @import("../parser.zig").expandRange(a, &names, tokens[i.*].text, tokens[i.* + 2].text);
            i.* += 2;
        } else try h.appendVarListName(a, tokens, i, &names);
    }
    return names.items;
}

pub fn resolve(a: std.mem.Allocator, d: *diag.Diagnostics, source: *Dataset, defaults: []const usize, variables: []const []const u8, has_var: bool) diag.Error![]const usize {
    if (variables.len == 0) return defaults;
    var columns: std.ArrayList(usize) = .empty;
    const names = try h.expandVarPrefixes(a, source, variables, d, 0, "UNIVARIATE plot");
    for (names) |name| {
        if (std.ascii.eqlIgnoreCase(name, "_numeric_")) {
            for (source.columns.items, 0..) |column, ci| if (column.type == .num and !std.mem.eql(u8, column.name, "__UNIV_SOURCE_OBS__")) try append(a, d, &columns, defaults, ci, has_var);
        } else {
            const ci = source.indexOf(name) orelse return d.fail(error.ParseError, 0, "UNIVARIATE: plot variable {s} not found", .{name});
            if (source.columns.items[ci].type != .num) return d.fail(error.ParseError, 0, "UNIVARIATE: plot variable {s} must be numeric", .{name});
            try append(a, d, &columns, defaults, ci, has_var);
        }
    }
    return columns.items;
}

fn append(a: std.mem.Allocator, d: *diag.Diagnostics, columns: *std.ArrayList(usize), defaults: []const usize, ci: usize, has_var: bool) diag.Error!void {
    if (has_var and std.mem.indexOfScalar(usize, defaults, ci) == null) return d.fail(error.ParseError, 0, "UNIVARIATE: plot variables must also appear in the VAR statement", .{});
    if (std.mem.indexOfScalar(usize, columns.items, ci) == null) try columns.append(a, ci);
}
