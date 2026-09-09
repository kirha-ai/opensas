//! Conformance corpus runner (`zig build corpus`). Runs the built `sas` binary
//! over every `tests/corpus/*.sas`, diffs its stdout against the sibling
//! `*.txt`, and prints `corpus: P/Q passing`. For each failure it surfaces the
//! first unsupported feature the interpreter reported — a stderr line prefixed
//! `UNSUPPORTED:` — else the first line where output diverged.
//!
//! Every fixture's exit code is checked. A fixture that exits non-zero must
//! declare it with an `expect-rc: N` marker in its header comment; NO MARKER
//! MEANS 0, so an undeclared non-zero exit fails. (It was opt-in until all 70
//! non-zero corpus fixtures were pinned — see `fixture_rc.zig` for why the
//! default flipped and `docs/findings/rc-pin-coverage.md` for the measurement.)
//!
//! This report drives the backlog (see manager.md §5), but it IS a gate: it
//! exits 1 when any fixture fails. It used to always exit 0, which is how
//! `CORPUS=0` came to be printed beside `1671/1673`.
//!
//! argv: <sas-binary> <corpus-dir>  (both wired by build.zig)

const std = @import("std");
const Io = std.Io;
const fixture_rc = @import("fixture_rc.zig");

const max_file: Io.Limit = .limited(1 << 20);

// ponytail: interpreter↔harness contract — a stage that hits something it can't
// do prints one `UNSUPPORTED: <feature>` line to stderr and bails. The runner
// only reads the first such line; that's what names the next backlog task.
const unsupported_prefix = "UNSUPPORTED:";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next(); // argv[0]
    const bin = args.next() orelse std.process.fatal("usage: corpus_runner <sas-bin> <corpus-dir>", .{});
    const corpus_dir = args.next() orelse std.process.fatal("usage: corpus_runner <sas-bin> <corpus-dir>", .{});

    var dir = try Io.Dir.cwd().openDir(io, corpus_dir, .{ .iterate = true });
    defer dir.close(io);

    var pass: usize = 0;
    var total: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".sas")) continue;
        total += 1;

        const sas_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ corpus_dir, entry.name });
        defer gpa.free(sas_path);
        const txt_name = try std.fmt.allocPrint(gpa, "{s}.txt", .{entry.name[0 .. entry.name.len - ".sas".len]});
        defer gpa.free(txt_name);

        const expected = dir.readFileAlloc(io, txt_name, gpa, max_file) catch |e| {
            std.debug.print("  {s}: SKIP — no expected {s} ({t})\n", .{ entry.name, txt_name, e });
            total -= 1;
            continue;
        };
        defer gpa.free(expected);

        const res = std.process.run(gpa, io, .{ .argv = &.{ bin, sas_path } }) catch |e| {
            std.debug.print("  {s}: FAIL — could not run interpreter ({t})\n", .{ entry.name, e });
            continue;
        };
        defer gpa.free(res.stdout);
        defer gpa.free(res.stderr);

        // The rc pin is checked before the diff: a fixture whose stdout matches
        // but whose exit code is wrong must FAIL (that combination is exactly
        // what hid the D-009 inversions — see fixture_rc.zig).
        const src = try dir.readFileAlloc(io, entry.name, gpa, max_file);
        defer gpa.free(src);
        if (try fixture_rc.mismatch(gpa, src, res.term)) |why| {
            defer gpa.free(why);
            std.debug.print("  {s}: FAIL — {s}\n", .{ entry.name, why });
            continue;
        }

        const norm_exp = try normalize(gpa, expected);
        defer gpa.free(norm_exp);
        const norm_got = try normalize(gpa, res.stdout);
        defer gpa.free(norm_got);

        if (std.mem.eql(u8, norm_exp, norm_got)) {
            pass += 1;
            continue;
        }

        if (firstUnsupported(res.stderr)) |feat| {
            std.debug.print("  {s}: FAIL — first unsupported: {s}\n", .{ entry.name, feat });
        } else {
            const d = firstDiffLine(norm_exp, norm_got);
            std.debug.print("  {s}: FAIL — output differs (expected \"{s}\" | got \"{s}\")\n", .{ entry.name, d.expected, d.got });
        }
    }

    std.debug.print("corpus: {d}/{d} passing\n", .{ pass, total });
    if (pass != total) std.process.exit(1);
}

// --- pure diff logic (unit-tested below; no IO) ---------------------------

/// Trim trailing whitespace per line and drop trailing blank lines, so a diff
/// is not tripped by an interpreter's stray trailing space or final newline.
/// ponytail: trailing-whitespace-insensitive; tighten to byte-exact if a SAS
/// fixture ever depends on trailing blanks (list-mode char padding might).
fn normalize(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |line| try lines.append(gpa, std.mem.trimEnd(u8, line, " \t\r"));
    var end = lines.items.len;
    while (end > 0 and lines.items[end - 1].len == 0) end -= 1;
    return std.mem.join(gpa, "\n", lines.items[0..end]);
}

fn firstUnsupported(stderr: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, stderr, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, unsupported_prefix))
            return std.mem.trim(u8, t[unsupported_prefix.len..], " \t\r");
    }
    return null;
}

const Diff = struct { expected: []const u8, got: []const u8 };

/// First line at which two (normalized) outputs differ. Only called on a known
/// mismatch, so it always finds one; a short side reports "<eof>".
fn firstDiffLine(exp: []const u8, got: []const u8) Diff {
    var ei = std.mem.splitScalar(u8, exp, '\n');
    var gi = std.mem.splitScalar(u8, got, '\n');
    while (true) {
        const e = ei.next();
        const g = gi.next();
        if (e == null and g == null) return .{ .expected = "<eof>", .got = "<eof>" };
        const es = e orelse "<eof>";
        const gs = g orelse "<eof>";
        if (!std.mem.eql(u8, es, gs)) return .{ .expected = es, .got = gs };
    }
}

test "normalize trims trailing ws and blank lines" {
    const a = std.testing.allocator;
    const out = try normalize(a, "a  \nb\t\n\n\n");
    defer a.free(out);
    try std.testing.expectEqualStrings("a\nb", out);
}

test "firstUnsupported reads the marker" {
    try std.testing.expectEqualStrings(
        "PROC MEANS",
        firstUnsupported("NOTE: running\nUNSUPPORTED: PROC MEANS\nmore\n").?,
    );
    try std.testing.expect(firstUnsupported("no marker here\n") == null);
}

test "firstDiffLine finds the first divergence" {
    const d = firstDiffLine("x=1\ny=2", "x=1\ny=9");
    try std.testing.expectEqualStrings("y=2", d.expected);
    try std.testing.expectEqualStrings("y=9", d.got);

    const d2 = firstDiffLine("x=1", "x=1\nextra");
    try std.testing.expectEqualStrings("<eof>", d2.expected);
    try std.testing.expectEqualStrings("extra", d2.got);
}

test {
    // fixture_rc.zig's `test` blocks don't run unless referenced from a test
    // root (modern zig runs only the root file's tests) — pull them in.
    _ = @import("fixture_rc.zig");
}
