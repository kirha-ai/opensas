//! HISTOGRAM KERNEL option lists, independent of estimation and output.
const std = @import("std");
const kernel = @import("univ_kernel.zig");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const numeric = @import("univ_distribution_parse.zig").numeric;
const eq = std.ascii.eqlIgnoreCase;

pub fn parse(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error![]kernel.Request {
    i.* += 1;
    var kinds: std.ArrayList(kernel.Kind) = .empty;
    var bandwidths: std.ArrayList(kernel.Bandwidth) = .empty;
    var lower: std.ArrayList(?f64) = .empty;
    var upper: std.ArrayList(?f64) = .empty;
    if (t[i.*].tag == .lparen) {
        i.* += 1;
        while (t[i.*].tag != .rparen) {
            if (t[i.*].tag != .name or t[i.* + 1].tag != .eq) return d.fail(error.ParseError, 0, "UNIVARIATE: expected KERNEL option=value", .{});
            const key = t[i.*].text;
            i.* += 2;
            if (eq(key, "k")) {
                if (kinds.items.len > 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated KERNEL K option", .{});
                while (t[i.*].tag == .name and t[i.* + 1].tag != .eq) {
                    const name = t[i.*].text;
                    const kind: kernel.Kind = if (eq(name, "n") or eq(name, "normal")) .normal else if (eq(name, "q") or eq(name, "quadratic")) .quadratic else if (eq(name, "t") or eq(name, "triangular")) .triangular else return d.fail(error.ParseError, 0, "UNIVARIATE: unknown kernel {s}", .{name});
                    try kinds.append(a, kind);
                    i.* += 1;
                    if (t[i.*].tag == .comma) i.* += 1;
                }
                if (kinds.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty kernel list", .{});
            } else if (eq(key, "c")) {
                if (bandwidths.items.len > 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated KERNEL C option", .{});
                while (t[i.*].tag == .number or t[i.*].tag == .plus or t[i.*].tag == .minus or (t[i.*].tag == .name and t[i.* + 1].tag != .eq)) {
                    if (t[i.*].tag == .name) {
                        const name = t[i.*].text;
                        const bandwidth: kernel.Bandwidth = if (eq(name, "mise")) .mise else if (eq(name, "sjpi")) .sjpi else return d.fail(error.ParseError, 0, "UNIVARIATE: unknown bandwidth method {s}", .{name});
                        try bandwidths.append(a, bandwidth);
                        i.* += 1;
                    } else try bandwidths.append(a, .{ .numeric = try numeric(d, t, i) });
                    if (t[i.*].tag == .comma) i.* += 1;
                }
                if (bandwidths.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty bandwidth list", .{});
            } else if (eq(key, "lower") or eq(key, "upper")) {
                const list = if (eq(key, "lower")) &lower else &upper;
                if (list.items.len > 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated kernel bound", .{});
                while (t[i.*].tag == .number or t[i.*].tag == .plus or t[i.*].tag == .minus or t[i.*].tag == .dot) {
                    if (t[i.*].tag == .dot) {
                        try list.append(a, null);
                        i.* += 1;
                    } else try list.append(a, try numeric(d, t, i));
                    if (t[i.*].tag == .comma) i.* += 1;
                }
                if (list.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty kernel bound list", .{});
            } else return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported KERNEL option {s}", .{key});
        }
        i.* += 1;
    }
    const count = @max(1, @max(kinds.items.len, bandwidths.items.len));
    const result = try a.alloc(kernel.Request, count);
    for (result, 0..) |*request, j| {
        request.* = .{};
        if (kinds.items.len > 0) request.kind = kinds.items[@min(j, kinds.items.len - 1)];
        if (bandwidths.items.len > 0) request.bandwidth = bandwidths.items[@min(j, bandwidths.items.len - 1)];
        if (lower.items.len > 0) request.lower = lower.items[@min(j, lower.items.len - 1)];
        if (upper.items.len > 0) request.upper = upper.items[@min(j, upper.items.len - 1)];
    }
    return result;
}

test "UNIVARIATE kernel lists repeat last bandwidth and bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const t = try @import("../lexer.zig").tokenize(a, "kernel(k=n q t c=.5 mise lower=. 0 upper=20);", &d);
    var i: usize = 0;
    const requests = try parse(a, &d, t, &i);
    try std.testing.expectEqual(@as(usize, 3), requests.len);
    try std.testing.expectEqual(kernel.Kind.triangular, requests[2].kind);
    try std.testing.expect(requests[2].bandwidth == .mise);
    try std.testing.expectEqual(@as(?f64, null), requests[0].lower);
    try std.testing.expectEqual(@as(?f64, 0), requests[2].lower);
    try std.testing.expectEqual(@as(?f64, 20), requests[2].upper);
    try std.testing.expectEqual(@import("../lexer.zig").Tag.semicolon, t[i].tag);
}
