//! Test-only access to the corpus's single source of expected listing tokens.
//! Existing next/end-listing assets contain the complete original listing;
//! persistence assets use words. Neither form permits omitted output in tests.
const std = @import("std");

pub fn listing(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1024 * 1024));
    return decode(a, bytes);
}

fn decode(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, bytes, "# corpus assertions\n")) return bytes;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var coverage: enum { none, rows, complete } = .none;
    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        const end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        const command = line[0..end];
        const args = if (end < line.len) line[end + 1 ..] else "";
        if (std.mem.eql(u8, command, "next") or std.mem.eql(u8, command, "words")) {
            const whole = std.mem.eql(u8, command, "words");
            if (coverage == .complete or (whole and coverage != .none)) return error.IncompleteListingAsset;
            if (!whole and std.mem.trim(u8, args, " \t").len == 0) return error.IncompleteListingAsset;
            coverage = if (whole) .complete else .rows;
            try out.appendSlice(a, args);
            try out.append(a, '\n');
        } else if (std.mem.eql(u8, command, "end-listing")) {
            if (coverage != .rows or args.len != 0) return error.IncompleteListingAsset;
            coverage = .complete;
        } else {
            // Only non-listing assertions may be ignored. In particular row,
            // rewind, counts and future unknown commands must fail closed.
            const ancillary = for ([_][]const u8{ "log-row", "log-words", "stderr-count", "svg-count", "svg-has", "svg-count-text" }) |allowed| {
                if (std.mem.eql(u8, command, allowed)) break true;
            } else false;
            if (!ancillary) return error.UnsupportedListingAssertion;
        }
    }
    if (coverage != .complete) return error.IncompleteListingAsset;
    return out.items;
}

test "TTEST listing assets require complete coverage and reject subset commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const header = "# corpus assertions\n";
    try std.testing.expectEqualStrings("raw listing\n", try decode(a, "raw listing\n"));
    try std.testing.expectEqualStrings("A B\n", try decode(a, header ++ "words A B\nstderr-count 0 ERROR\n"));
    try std.testing.expectEqualStrings("\n", try decode(a, header ++ "words\n"));
    try std.testing.expectEqualStrings("A\nB\n", try decode(a, header ++ "next A\nnext B\nend-listing\nsvg-count 0\n"));
    for ([_][]const u8{ "next A\n", "stderr-count 0 ERROR\n", "end-listing\n", "next A\nwords A\n", "words A\nnext B\n", "next A\nend-listing\nnext B\n" }) |body|
        try std.testing.expectError(error.IncompleteListingAsset, decode(a, try std.mem.concat(a, u8, &.{ header, body })));
    for ([_][]const u8{ "row A\n", "next A\nrewind\nend-listing\n", "words A\nrow B\n", "stdout-count 1 A\n", "future-command A\n" }) |body|
        try std.testing.expectError(error.UnsupportedListingAssertion, decode(a, try std.mem.concat(a, u8, &.{ header, body })));
}
