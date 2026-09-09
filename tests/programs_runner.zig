//! Program-fixture runner (`zig build programs`). The second corpus tier: where
//! `tests/corpus/*.sas` diffs stdout, these run a real dataset-in → dataset-out
//! program and diff the output *dataset*.
//!
//! For each `tests/programs/<name>/` that has a `program.sas`, it runs the built
//! `sas` binary there (cwd = the fixture dir, so the program's
//! `libname source "inputs"` / `libname target "output"` resolve), then
//! structurally diffs every `expected/*.csv` against the produced `output/*.csv`
//! — column names + order, row count, and cell values (numeric-normalized, so
//! `40` == `40.0`) — not a byte diff. Prints `programs: P/Q passing`.
//!
//! Every `program.sas`'s exit code is checked. One that exits non-zero must
//! declare it with an `expect-rc: N` marker in its header comment; NO MARKER
//! MEANS 0. This suite needed no migration when the default flipped — it had
//! two non-zero programs and both were already pinned (see `fixture_rc.zig`).
//!
//! It IS a gate (like the corpus runner): it exits 1 when any fixture fails.
//! On a failure it surfaces the program's first `UNSUPPORTED:` stderr marker
//! when no output was produced.
//!
//! argv: <sas-binary> <programs-dir>  (both wired by build.zig)

const std = @import("std");
const Io = std.Io;
const fixture_rc = @import("fixture_rc.zig");

const max_file: Io.Limit = .limited(1 << 20);
const unsupported_prefix = "UNSUPPORTED:";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Arena for the whole run: every string here lives until exit and is freed
    // wholesale, so a diagnostic runner needn't thread `free` through the diff.
    const gpa = init.arena.allocator();

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next(); // argv[0]
    const bin_arg = args.next() orelse std.process.fatal("usage: programs_runner <sas-bin> <programs-dir>", .{});
    const programs_dir = args.next() orelse std.process.fatal("usage: programs_runner <sas-bin> <programs-dir>", .{});

    // The child runs with a different cwd, so the binary path must be absolute.
    const bin = if (bin_arg.len > 0 and bin_arg[0] == '/') bin_arg else blk: {
        const cwd = try std.process.currentPathAlloc(io, gpa);
        break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd, bin_arg });
    };

    var root = try Io.Dir.cwd().openDir(io, programs_dir, .{ .iterate = true });
    defer root.close(io);

    var pass: usize = 0;
    var total: usize = 0;
    var it = root.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;

        var pdir = root.openDir(io, entry.name, .{ .iterate = true }) catch continue;
        defer pdir.close(io);

        // a fixture is a dir with a program.sas; anything else is skipped
        const src = pdir.readFileAlloc(io, "program.sas", gpa, max_file) catch continue;
        total += 1;

        if (try runProgram(gpa, io, bin, pdir, programs_dir, entry.name, src)) |reason| {
            std.debug.print("  {s}: FAIL — {s}\n", .{ entry.name, reason });
        } else {
            pass += 1;
        }
    }

    std.debug.print("programs: {d}/{d} passing\n", .{ pass, total });
    if (pass != total) std.process.exit(1);
}

/// Run one fixture and compare its outputs. Returns null on a full match, else a
/// human-readable failure reason.
fn runProgram(gpa: std.mem.Allocator, io: Io, bin: []const u8, pdir: Io.Dir, programs_dir: []const u8, name: []const u8, src: []const u8) !?[]const u8 {
    pdir.createDirPath(io, "output") catch {}; // the program writes here (DSFILE)

    const dir_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ programs_dir, name });
    const res = runWithRetry(gpa, io, bin, dir_path) catch |e|
        return try std.fmt.allocPrint(gpa, "could not run program.sas ({t})", .{e});

    // Checked before the CSV diff: right outputs at the wrong exit code is a
    // failure, and is the exact combination that hid the D-009 inversions.
    if (try fixture_rc.mismatch(gpa, src, res.term)) |why| return why;

    var edir = pdir.openDir(io, "expected", .{ .iterate = true }) catch
        return try std.fmt.allocPrint(gpa, "no expected/ directory", .{});
    defer edir.close(io);

    var found = false;
    var ei = edir.iterate();
    while (try ei.next(io)) |ef| {
        if (ef.kind != .file or !std.mem.endsWith(u8, ef.name, ".csv")) continue;
        found = true;

        const expected = try edir.readFileAlloc(io, ef.name, gpa, max_file);
        const out_rel = try std.fmt.allocPrint(gpa, "output/{s}", .{ef.name});
        const produced = pdir.readFileAlloc(io, out_rel, gpa, max_file) catch {
            if (firstUnsupported(res.stderr)) |feat|
                return try std.fmt.allocPrint(gpa, "{s}: no output ({s})", .{ ef.name, feat });
            return try std.fmt.allocPrint(gpa, "{s}: no output produced", .{ef.name});
        };
        if (try structDiff(gpa, produced, expected)) |why|
            return try std.fmt.allocPrint(gpa, "{s}: {s}", .{ ef.name, why });
    }
    if (!found) return try std.fmt.allocPrint(gpa, "expected/ has no .csv", .{});
    return null;
}

/// Spawn the child, retrying transient failures: on a cold cache the runner
/// races the still-parallel build, and the freshly-linked `sas` exe can be
/// briefly missing/unexecutable at spawn time (INFRA-programsflake — the
/// first-run ~129/168 flake). Back off and retry before calling it a failure.
/// ponytail: fixed 10×100ms = 1s worst case per program; raise if it ever
/// flakes on a genuinely slower machine.
fn runWithRetry(gpa: std.mem.Allocator, io: Io, bin: []const u8, dir_path: []const u8) !std.process.RunResult {
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        return std.process.run(gpa, io, .{
            .argv = &.{ bin, "program.sas" },
            .cwd = .{ .path = dir_path },
        }) catch |e| {
            if (attempt >= 10) return e;
            std.Io.sleep(io, .fromMilliseconds(100), .awake) catch {};
            continue;
        };
    }
}

// --- pure comparison logic (unit-tested below; no IO) ------------------------

/// Structural CSV diff. Returns null when the tables match (header names
/// case-insensitively, in order; same row count; cell values, numeric-aware),
/// else a reason. Not a byte diff — quoting/line-endings/numeric spelling don't
/// matter, only the parsed structure.
/// ponytail: naive header case-insensitivity + numeric normalization; no format
/// awareness (e.g. `1e2` vs `100` matches, `01JAN2020` vs a serial would not).
fn structDiff(a: std.mem.Allocator, actual: []const u8, expected: []const u8) !?[]const u8 {
    const arows = try rows(a, actual);
    const erows = try rows(a, expected);
    if (arows.len != erows.len)
        return try std.fmt.allocPrint(a, "row count differs (got {d}, expected {d})", .{ arows.len, erows.len });

    for (erows, 0..) |erow, ri| {
        const ef = try splitCsv(a, erow);
        const af = try splitCsv(a, arows[ri]);
        if (af.len != ef.len)
            return try std.fmt.allocPrint(a, "row {d} column count differs (got {d}, expected {d})", .{ ri, af.len, ef.len });
        for (ef, af, 0..) |ev, av, ci| {
            const ok = if (ri == 0) std.ascii.eqlIgnoreCase(ev, av) else cellEq(av, ev);
            if (!ok) return try std.fmt.allocPrint(a, "row {d} col {d}: {s} differs (got \"{s}\", expected \"{s}\")", .{ ri, ci, if (ri == 0) "header" else "value", av, ev });
        }
    }
    return null;
}

/// Non-blank lines (a trailing newline / CR does not add a row).
fn rows(a: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |line| {
        const l = std.mem.trimEnd(u8, line, "\r");
        if (l.len != 0) try out.append(a, l);
    }
    return out.items;
}

/// Split one CSV line into fields, honouring `"…"` quoting (with `""` escapes).
fn splitCsv(a: std.mem.Allocator, line: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var field: std.ArrayList(u8) = .empty;
    var in_quotes = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (in_quotes) {
            if (c == '"') {
                if (i + 1 < line.len and line[i + 1] == '"') {
                    try field.append(a, '"');
                    i += 1;
                } else in_quotes = false;
            } else try field.append(a, c);
        } else switch (c) {
            '"' => in_quotes = true,
            ',' => try out.append(a, try field.toOwnedSlice(a)),
            else => try field.append(a, c),
        }
    }
    try out.append(a, try field.toOwnedSlice(a));
    return out.items;
}

/// Cell equality: exact bytes, or equal as numbers (`40` == `40.0`). Missing
/// (`.`) and empty compare only to themselves.
fn cellEq(x: []const u8, y: []const u8) bool {
    if (std.mem.eql(u8, x, y)) return true;
    const nx = std.fmt.parseFloat(f64, x) catch return false;
    const ny = std.fmt.parseFloat(f64, y) catch return false;
    return nx == ny;
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

// --- tests -------------------------------------------------------------------

test "structDiff: identical tables match; numeric spelling is normalized" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const al = arena.allocator();
    try std.testing.expect((try structDiff(al, "A,B\n1,x\n", "a,b\n1.0,x\n")) == null);
}

test "structDiff: reports header, value, and shape mismatches" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const al = arena.allocator();
    try std.testing.expect((try structDiff(al, "A,B\n1,x\n", "A,C\n1,x\n")) != null); // header
    try std.testing.expect((try structDiff(al, "A,B\n1,x\n", "A,B\n1,y\n")) != null); // value
    try std.testing.expect((try structDiff(al, "A,B\n1,x\n", "A,B\n1,x\n2,z\n")) != null); // rows
}

test "splitCsv: quoted fields keep commas and padding" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const al = arena.allocator();
    const f = try splitCsv(al, "a,\" A \",\"x,y\",");
    try std.testing.expectEqual(@as(usize, 4), f.len);
    try std.testing.expectEqualStrings("a", f[0]);
    try std.testing.expectEqualStrings(" A ", f[1]);
    try std.testing.expectEqualStrings("x,y", f[2]);
    try std.testing.expectEqualStrings("", f[3]);
}
