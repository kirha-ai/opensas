//! Graph titles and statistical insets shared by UNIVARIATE plots.
const std = @import("std");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const format = @import("../format.zig");
const dist = @import("univ_distributions.zig");
const parameters = @import("univ_distribution_render.zig").parameters;
const family = @import("univ_distribution_parse.zig").family;
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;

pub const Title = union(enum) {
    default,
    global,
    none,
    label,
    literal: []const u8,

    pub fn parse(d: *diag.Diagnostics, token: Token) diag.Error!Title {
        if (token.tag == .string) return .{ .literal = token.text };
        if (eq(token.text, "title") or eq(token.text, "title1")) return .global;
        if (eq(token.text, "none")) return .none;
        if (eq(token.text, "default")) return .default;
        if (eq(token.text, "labelfmt")) return .label;
        return d.fail(error.ParseError, token.line, "UNIVARIATE: invalid ODSTITLE= value", .{});
    }

    pub fn value(self: Title, a: A, global: ?[]const u8, heading: []const u8, column: @import("../dataset.zig").Column) ![]const u8 {
        return switch (self) {
            .none => "",
            .global => global orelse "",
            .literal => |s| blk: {
                const n = try std.mem.replaceOwned(u8, a, s, "\\n", column.name);
                break :blk try std.mem.replaceOwned(u8, a, n, "\\l", column.label orelse column.name);
            },
            .default, .label => try std.fmt.allocPrint(a, "{s} {s} {s}", .{ heading, if (eq(heading, "Distribution")) "of" else "for", if (self == .label) column.label orelse column.name else column.name }),
        };
    }
};

const Item = struct { key: []const u8, label: ?[]const u8 = null, fmt: ?[]const u8 = null, curve: ?dist.Family = null, symbols: []const []const u8 = &.{} };
pub const Line = struct { key: []const u8, value: []const u8 };
pub const Box = struct { lines: []const Line = &.{}, pos: Position = .nw, header: []const u8 = "" };
const Position = enum { nw, ne, sw, se, n, s, w, e };
pub const Inset = struct {
    items: []const Item = &.{},
    pos: Position = .nw,
    fmt: []const u8 = "BEST8.",
    header: []const u8 = "",

    pub fn parse(a: A, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Inset {
        var inset = Inset{};
        var items: std.ArrayList(Item) = .empty;
        i.* += 1;
        while (t[i.*].tag == .name) {
            const key = t[i.*].text;
            i.* += 1;
            var item = Item{ .key = key, .curve = family(key) };
            if (item.curve == null and !eq(key, "n") and !eq(key, "mean") and !eq(key, "std") and !eq(key, "stddev") and !eq(key, "min") and !eq(key, "max"))
                return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported INSET statistic {s}", .{key});
            if (t[i.*].tag == .eq and t[i.* + 1].tag == .string) {
                item.label = t[i.* + 1].text;
                i.* += 2;
            }
            if (t[i.*].tag == .lparen) {
                i.* += 1;
                if (item.curve != null) {
                    var symbols: std.ArrayList([]const u8) = .empty;
                    while (t[i.*].tag == .name) {
                        try symbols.append(a, t[i.*].text);
                        i.* += 1;
                    }
                    if (symbols.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: INSET requires a distribution parameter", .{});
                    item.symbols = symbols.items;
                } else item.fmt = try readFormat(a, d, t, i);
                if (t[i.*].tag != .rparen) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid INSET parentheses", .{});
                i.* += 1;
            }
            try items.append(a, item);
        }
        if (items.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: missing INSET statistics", .{});
        inset.items = items.items;
        if (t[i.*].tag == .slash) i.* += 1;
        while (t[i.*].tag != .semicolon and t[i.*].tag != .eof) {
            const key = t[i.*].text;
            if (t[i.* + 1].tag != .eq) return d.fail(error.ParseError, 0, "UNIVARIATE: INSET option requires =", .{});
            i.* += 2;
            if (eq(key, "format")) {
                inset.fmt = try readFormat(a, d, t, i);
                continue;
            }
            if (eq(key, "pos") or eq(key, "position")) {
                var found = false;
                inline for (std.meta.tags(Position)) |pos| if (eq(t[i.*].text, @tagName(pos))) {
                    inset.pos = pos;
                    found = true;
                };
                if (!found) return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported INSET position {s}", .{t[i.*].text});
            } else if (eq(key, "header") and t[i.*].tag == .string) inset.header = t[i.*].text else return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported INSET option {s}", .{key});
            i.* += 1;
        }
        return inset;
    }

    pub fn box(self: Inset, a: A, d: *diag.Diagnostics, x: []const f64, curves: []const dist.Distribution) diag.Error!Box {
        var lines: std.ArrayList(Line) = .empty;
        var mean: f64 = 0;
        var ss: f64 = 0;
        for (x, 1..) |v, n| {
            const delta = v - mean;
            mean += delta / @as(f64, @floatFromInt(n));
            ss += delta * (v - mean);
        }
        for (self.items) |item| {
            const spec = item.fmt orelse self.fmt;
            if (item.curve) |wanted| {
                for (curves) |c| if (c.family == wanted) {
                    const pars = try parameters(a, c);
                    if (item.symbols.len == 0) {
                        for (pars) |p| if (p.symbol.len > 0) try append(a, &lines, p.symbol, p.value, spec);
                    } else for (item.symbols) |sym| {
                        var found = false;
                        for (pars) |p| if (eq(sym, p.symbol)) {
                            try append(a, &lines, p.symbol, p.value, spec);
                            found = true;
                            break;
                        };
                        if (!found) return d.fail(error.ParseError, 0, "UNIVARIATE: unknown INSET parameter {s} for {s}", .{ sym, item.key });
                    }
                    break;
                };
            } else {
                const n: f64 = @floatFromInt(x.len);
                const val: f64 = if (eq(item.key, "n")) n else if (eq(item.key, "mean")) mean else if (eq(item.key, "min")) x[0] else if (eq(item.key, "max")) x[x.len - 1] else if (n > 1) @sqrt(ss / (n - 1)) else std.math.nan(f64);
                const key: []const u8 = if (eq(item.key, "n")) "N" else if (eq(item.key, "mean")) "Mean" else if (eq(item.key, "min")) "Minimum" else if (eq(item.key, "max")) "Maximum" else "Std Deviation";
                try append(a, &lines, item.label orelse key, val, spec);
            }
        }
        return .{ .lines = lines.items, .pos = self.pos, .header = self.header };
    }
};

fn append(a: A, lines: *std.ArrayList(Line), key: []const u8, value: f64, spec: []const u8) !void {
    const text = try format.apply(a, .{ .num = value }, spec);
    try lines.append(a, .{ .key = key, .value = std.mem.trim(u8, text, " ") });
}

fn readFormat(a: A, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error![]const u8 {
    if (t[i.*].tag != .name and t[i.*].tag != .number) return d.fail(error.ParseError, 0, "UNIVARIATE: missing INSET format", .{});
    const first = t[i.*].text;
    i.* += 1;
    if (t[i.*].tag != .dot) return first;
    i.* += 1;
    if (t[i.*].tag != .number) return std.mem.concat(a, u8, &.{ first, "." });
    const last = t[i.*].text;
    i.* += 1;
    return std.mem.concat(a, u8, &.{ first, ".", last });
}
