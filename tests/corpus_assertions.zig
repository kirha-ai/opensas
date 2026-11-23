//! Select individual result rows when SAS and OpenSAS lay out the rest of the
//! report differently. Other corpus listings continue to use the exact diff.
//! Rows are ordered, whitespace-insensitive and keep pipe-delimited columns.
//! The token {any} skips one field. A number followed by ~tolerance has an absolute
//! error bound. Counts and substrings also cover diagnostics and generated SVGs.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const header = "# corpus assertions\n";

const Words = struct {
    rest: []const u8,

    fn next(self: *Words) ?[]const u8 {
        self.rest = std.mem.trimStart(u8, self.rest, " \t\r");
        if (self.rest.len == 0) return null;
        const end = if (self.rest[0] == '|') 1 else std.mem.indexOfAny(u8, self.rest, " \t\r|") orelse self.rest.len;
        const word = self.rest[0..end];
        self.rest = self.rest[end..];
        return word;
    }
};

fn fieldMatches(want: []const u8, got: []const u8) bool {
    if (std.mem.eql(u8, want, got) or std.mem.eql(u8, want, "{any}")) return true;
    const sep = std.mem.indexOfScalar(u8, want, '~') orelse return false;
    const expected = std.fmt.parseFloat(f64, want[0..sep]) catch return false;
    const tolerance = std.fmt.parseFloat(f64, want[sep + 1 ..]) catch return false;
    const actual = std.fmt.parseFloat(f64, got) catch return false;
    // At a printed half-digit boundary the binary subtraction may cross the
    // decimal bound by one floating-point rounding unit.
    if (tolerance == 0) return actual == expected;
    return tolerance > 0 and @abs(expected - actual) <= tolerance + std.math.floatEps(f64) * @abs(expected);
}

fn rowMatches(expected: []const u8, actual: []const u8) bool {
    var want: Words = .{ .rest = expected };
    var got: Words = .{ .rest = actual };
    while (want.next()) |field| {
        if (!fieldMatches(field, got.next() orelse return false)) return false;
    }
    return got.next() == null;
}

fn nextListingRow(lines: *std.mem.TokenIterator(u8, .scalar)) ?[]const u8 {
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (std.mem.trim(u8, row, "-").len != 0) return row;
    }
    return null;
}

fn take(input: *[]const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, input.*, ' ') orelse input.len;
    const first = input.*[0..end];
    input.* = if (end < input.len) input.*[end + 1 ..] else "";
    return first;
}

fn countMatches(a: Allocator, text: []const u8, args: []const u8) !bool {
    var pattern = args;
    const count = try std.fmt.parseInt(usize, take(&pattern), 10);
    if (pattern.len == 0) return error.EmptyPattern;
    if (std.mem.indexOf(u8, pattern, "\\n") != null) {
        const multiline = try std.mem.replaceOwned(u8, a, pattern, "\\n", "\n");
        defer a.free(multiline);
        return std.mem.count(u8, text, multiline) == count;
    }
    return std.mem.count(u8, text, pattern) == count;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// Returns the first failed assertion, including the stream or graph selector.
pub fn mismatch(a: Allocator, io: Io, dir: Io.Dir, spec: []const u8, stdout: []const u8, stderr: []const u8) !?[]const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |name| a.free(name);
        files.deinit(a);
    }
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".svg"))
            try files.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);
    var lines = std.mem.tokenizeScalar(u8, stdout, '\n');
    var log_lines = std.mem.tokenizeScalar(u8, stderr, '\n');
    var rules = std.mem.tokenizeScalar(u8, spec[header.len..], '\n');
    var checks: usize = 0;
    while (rules.next()) |raw| {
        var args = std.mem.trimEnd(u8, raw, "\r");
        if (args.len == 0 or args[0] == '#') continue;
        const command = take(&args);
        if (std.mem.eql(u8, command, "rewind")) {
            lines = std.mem.tokenizeScalar(u8, stdout, '\n');
            continue;
        }
        const pass = if (std.mem.eql(u8, command, "row")) found: {
            while (lines.next()) |line| {
                if (rowMatches(args, line)) break :found true;
            }
            break :found false;
        } else if (std.mem.eql(u8, command, "log-row")) found: {
            while (log_lines.next()) |line| {
                if (rowMatches(args, line)) break :found true;
            }
            break :found false;
        } else if (std.mem.eql(u8, command, "next"))
            if (nextListingRow(&lines)) |line| rowMatches(args, line) else false
        else if (std.mem.eql(u8, command, "end-listing"))
            nextListingRow(&lines) == null
        else if (std.mem.eql(u8, command, "row-count")) count: {
            const expected = try std.fmt.parseInt(usize, take(&args), 10);
            var all = std.mem.tokenizeScalar(u8, stdout, '\n');
            var hits: usize = 0;
            while (all.next()) |line| {
                if (rowMatches(args, line)) hits += 1;
            }
            break :count expected == hits;
        } else if (std.mem.eql(u8, command, "stdout-count"))
            try countMatches(a, stdout, args)
        else if (std.mem.eql(u8, command, "stderr-count"))
            try countMatches(a, stderr, args)
        else if (std.mem.eql(u8, command, "empty-listing"))
            std.mem.trim(u8, stdout, " \t\r\n").len == 0
        else if (std.mem.eql(u8, command, "svg-count"))
            files.items.len == try std.fmt.parseInt(usize, args, 10)
        else if (std.mem.eql(u8, command, "svg-has") or std.mem.eql(u8, command, "svg-count-text")) graph: {
            const n = try std.fmt.parseInt(usize, take(&args), 10);
            if (n == 0 or n > files.items.len) break :graph false;
            const svg = try dir.readFileAlloc(io, files.items[n - 1], a, .limited(16 << 20));
            defer a.free(svg);
            if (std.mem.eql(u8, command, "svg-count-text")) break :graph try countMatches(a, svg, args);
            break :graph args.len > 0 and std.mem.indexOf(u8, svg, args) != null;
        } else return error.UnknownCorpusAssertion;
        if (!pass) return raw;
        checks += 1;
    }
    if (checks == 0) return error.EmptyAssertions;
    return null;
}

test "ordered row fields preserve missing cells, operators and numeric tolerances" {
    try std.testing.expect(rowMatches("P | <.0001 || {any} | 0.320~0.0005", "P| <.0001 | | x | .3204"));
    try std.testing.expect(!rowMatches("P | . | 0.320~0.0005", "P | 0 | .3201"));
    try std.testing.expect(!rowMatches("P | . | 0.320~0.0005", "P | . | .321"));
    try std.testing.expect(!rowMatches("x 1", "x 1 2"));
}

test "a corpus expectation fails on extra result rows, wrong diagnostics and missing graphs" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{ .iterate = true });
    defer scratch.cleanup();
    const spec = header ++
        "row Name x\nnext A 1.25~0.005\nend-listing\n" ++
        "log-row Path: Corr.ByGroup1\nstderr-count 0 WARNING:\nsvg-count 0\n";
    const listing = "Name x\n------\nA 1.251\n";
    const log = "Path:   Corr.ByGroup1\n";
    try std.testing.expect((try mismatch(a, io, scratch.dir, spec, listing, log)) == null);
    try std.testing.expectEqualStrings("end-listing", (try mismatch(a, io, scratch.dir, spec, listing ++ "B 9\n", log)).?);
    try std.testing.expectEqualStrings("next A 1.25~0.005", (try mismatch(a, io, scratch.dir, spec, "Name x\nA 1.3\n", log)).?);
    try std.testing.expectEqualStrings("stderr-count 0 WARNING:", (try mismatch(a, io, scratch.dir, spec, listing, log ++ "WARNING: failed\n")).?);
    try std.testing.expectEqualStrings("svg-count 1", (try mismatch(a, io, scratch.dir, header ++ "svg-count 1\n", "", "")).?);
}
