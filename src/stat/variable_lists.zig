//! Expand one statistical procedure variable-list expression in SAS order.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const VarType = @import("../pdv.zig").VarType;
const lex = @import("../lexer.zig");
const Token = lex.Token;
const eq = std.ascii.eqlIgnoreCase;

fn tag(t: []const Token, i: usize, wanted: lex.Tag) bool {
    return i < t.len and t[i].tag == wanted;
}

const Suffix = struct {
    prefix: []const u8,
    number: usize,
    digits: usize,
    padded: bool,

    fn parse(name: []const u8) ?Suffix {
        var split = name.len;
        while (split > 0 and std.ascii.isDigit(name[split - 1])) split -= 1;
        if (split == name.len) return null;
        const digits = name[split..];
        return .{ .prefix = name[0..split], .number = std.fmt.parseInt(usize, digits, 10) catch return null, .digits = digits.len, .padded = digits.len > 1 and digits[0] == '0' };
    }
};

fn numbered(a: std.mem.Allocator, ds: *const Dataset, first: Token, last: Token, d: *diag.Diagnostics) diag.Error![][]const u8 {
    for ([_]Token{ first, last }) |endpoint| {
        if (ds.indexOf(endpoint.text) == null)
            return d.fail(error.ParseError, endpoint.line, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, endpoint.text)});
    }
    const suffix_error = "Either roots don't match or start suffix after end suffix.";
    const lo = Suffix.parse(first.text) orelse return d.fail(error.ParseError, first.line, suffix_error, .{});
    const hi = Suffix.parse(last.text) orelse return d.fail(error.ParseError, last.line, suffix_error, .{});
    const padded = lo.padded or hi.padded;
    if (!eq(lo.prefix, hi.prefix) or (padded and lo.digits != hi.digits))
        return d.fail(error.ParseError, last.line, suffix_error, .{});
    const prefix = try std.ascii.allocUpperString(a, lo.prefix);
    const width = if (padded) lo.digits else 0;
    var names: std.ArrayList([]const u8) = .empty;
    var number = lo.number;
    while (true) {
        const generated = try std.fmt.allocPrint(a, "{[p]s}{[n]d:0>[w]}", .{ .p = prefix, .n = number, .w = width });
        const col = ds.indexOf(generated) orelse return d.fail(error.ParseError, first.line, "Variable {s}{d} in suffix list not in data set.", .{ prefix, number });
        try names.append(a, ds.columns.items[col].name);
        if (number == hi.number) break;
        if (number < hi.number) number += 1 else number -= 1;
    }
    return names.items;
}

pub fn datasetName(a: std.mem.Allocator, ds: *const Dataset) ![]const u8 {
    const name = try std.ascii.allocUpperString(a, ds.name);
    return if (std.mem.indexOfScalar(u8, name, '.') == null) std.fmt.allocPrint(a, "WORK.{s}", .{name}) else name;
}

pub fn next(a: std.mem.Allocator, ds: *const Dataset, tokens: []const Token, at: *usize, d: *diag.Diagnostics) diag.Error![][]const u8 {
    if (!tag(tokens, at.*, .name)) return d.fail(error.ParseError, if (at.* < tokens.len) tokens[at.*].line else 0, "Expected a variable name.", .{});
    const first = tokens[at.*];
    at.* += 1;
    var names: std.ArrayList([]const u8) = .empty;
    if (tag(tokens, at.*, .minus)) {
        at.* += 1;
        var filter: ?VarType = null;
        if (tag(tokens, at.*, .name) and tag(tokens, at.* + 1, .minus)) {
            const keyword = tokens[at.*];
            if (eq(keyword.text, "numeric")) {
                filter = .num;
            } else if (eq(keyword.text, "character")) {
                filter = .char;
            } else return d.fail(error.ParseError, keyword.line, "Expected NUMERIC or CHARACTER between range endpoints.", .{});
            at.* += 1;
        }
        const descriptor = tag(tokens, at.*, .minus);
        if (descriptor) at.* += 1;
        if (!tag(tokens, at.*, .name)) return d.fail(error.ParseError, first.line, "Expected the last variable in a range.", .{});
        const last = tokens[at.*];
        at.* += 1;
        if (!descriptor) return numbered(a, ds, first, last, d);
        const start = ds.indexOf(first.text) orelse return d.fail(error.ParseError, first.line, "Variable {s} not found.", .{first.text});
        const end = ds.indexOf(last.text) orelse return d.fail(error.ParseError, last.line, "Variable {s} not found.", .{last.text});
        if (end < start) return d.fail(error.ParseError, first.line, "Starting variable after ending variable in data set.", .{});
        for (ds.columns.items[start .. end + 1]) |col| {
            if (filter == null or filter.? == col.type) try names.append(a, col.name);
        }
    } else if (tag(tokens, at.*, .colon)) {
        at.* += 1;
        for (ds.columns.items) |col| if (std.ascii.startsWithIgnoreCase(col.name, first.text)) {
            try names.append(a, col.name);
        };
        if (names.items.len == 0) try d.warn(first.line, "No variables found beginning with '{s}' in data set {s}.", .{
            try std.ascii.allocUpperString(a, first.text), try datasetName(a, ds),
        });
    } else if (eq(first.text, "_all_") or eq(first.text, "_numeric_") or eq(first.text, "_character_") or eq(first.text, "_char_")) {
        const all = eq(first.text, "_all_");
        const kind: VarType = if (eq(first.text, "_numeric_")) .num else .char;
        for (ds.columns.items) |col| if (all or col.type == kind) {
            try names.append(a, col.name);
        };
        if (!all and names.items.len == 0) {
            try d.warn(first.line, "No {s} variables found in data set {s}.", .{
                if (kind == .num) @as([]const u8, "numeric") else "character", try datasetName(a, ds),
            });
        }
    } else try names.append(a, first.text);
    return names.items;
}
