//! Conformance corpus runner (`zig build corpus`). Runs the built `sas` binary
//! over every `tests/corpus/*.sas`, diffs its stdout against the sibling
//! `*.txt`, and prints `corpus: P/Q passing`. For each failure it surfaces the
//! first unsupported feature the interpreter reported — a stderr line prefixed
//! `UNSUPPORTED:` — else the first line where output diverged.
//!
//! Most fixtures are independent processes and fan out across a small worker
//! pool (`min(cpu_count, 8)`) via `Io.Group.concurrent`. Fixtures that touch
//! shared on-disk paths (`tests/corpus/includes/` or `.zig-cache`) run
//! **serially after** the parallel wave — otherwise concurrent readers/writers
//! race and flake CI. Failure lines may appear out of directory order; the P/Q
//! total is what gates.
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
/// Cap workers so we don't fork-bomb a laptop / CI runner; corpus is
/// process-spawn heavy, not CPU-bound inside one opensas.
const max_workers: usize = 8;

// ponytail: interpreter↔harness contract — a stage that hits something it can't
// do prints one `UNSUPPORTED: <feature>` line to stderr and bails. The runner
// only reads the first such line; that's what names the next backlog task.
const unsupported_prefix = "UNSUPPORTED:";

const Ctx = struct {
    io: Io,
    gpa: std.mem.Allocator,
    bin: []const u8,
    corpus_dir: []const u8,
    names: []const []const u8,
    next: std.atomic.Value(usize) = .init(0),
    pass: std.atomic.Value(usize) = .init(0),
    print_mu: Io.Mutex = .init,
};

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

    // Collect runnable fixtures on the main thread (SKIP stays ordered). Split
    // shared-FS ("dirty") fixtures from the rest so only the clean set fans out.
    // Each name is owned until exit.
    var clean: std.ArrayList([]const u8) = .empty;
    defer {
        for (clean.items) |n| gpa.free(n);
        clean.deinit(gpa);
    }
    var dirty: std.ArrayList([]const u8) = .empty;
    defer {
        for (dirty.items) |n| gpa.free(n);
        dirty.deinit(gpa);
    }

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".sas")) continue;

        const txt_name = try std.fmt.allocPrint(gpa, "{s}.txt", .{entry.name[0 .. entry.name.len - ".sas".len]});
        defer gpa.free(txt_name);
        dir.access(io, txt_name, .{}) catch |e| {
            std.debug.print("  {s}: SKIP — no expected {s} ({t})\n", .{ entry.name, txt_name, e });
            continue;
        };

        const src = dir.readFileAlloc(io, entry.name, gpa, max_file) catch |e| {
            std.debug.print("  {s}: SKIP — could not read source ({t})\n", .{ entry.name, e });
            continue;
        };
        defer gpa.free(src);

        const name = try gpa.dupe(u8, entry.name);
        if (touchesSharedCorpusFs(src)) {
            try dirty.append(gpa, name);
        } else {
            try clean.append(gpa, name);
        }
    }

    const total = clean.items.len + dirty.items.len;
    var ctx: Ctx = .{
        .io = io,
        .gpa = gpa,
        .bin = bin,
        .corpus_dir = corpus_dir,
        .names = clean.items,
    };

    try runParallel(&ctx);

    // Shared-includes fixtures: one at a time on this task (after the parallel
    // wave so they do not race clean workers either — clean fixtures must not
    // touch includes/, dirty ones only touch among themselves here).
    ctx.names = dirty.items;
    ctx.next = .init(0);
    var serial_dir = try Io.Dir.cwd().openDir(io, corpus_dir, .{});
    defer serial_dir.close(io);
    for (dirty.items) |name| runOne(&ctx, serial_dir, name);

    const pass = ctx.pass.load(.monotonic);
    std.debug.print("corpus: {d}/{d} passing\n", .{ pass, total });
    if (pass != total) std.process.exit(1);
}

/// True when the fixture references a shared on-disk tree that other fixtures
/// also read/write. Those must not run concurrently with each other.
fn touchesSharedCorpusFs(src: []const u8) bool {
    // Case-sensitive: fixtures spell paths this way. Broaden only if a new
    // spelling shows up in the corpus.
    // No trailing slash: fixtures may LIBNAME the directory itself
    // (`"tests/corpus/includes"`) as well as members under it.
    if (std.mem.indexOf(u8, src, "tests/corpus/includes") != null) return true;
    // Scratch libname/FILE targets under the build cache (LIBNAME scan + DELETE
    // can race with sibling writers if these stay in the parallel wave).
    if (std.mem.indexOf(u8, src, ".zig-cache") != null) return true;
    return false;
}

fn runParallel(ctx: *Ctx) !void {
    if (ctx.names.len == 0) return;

    const io = ctx.io;
    const cpu = std.Thread.getCpuCount() catch 4;
    const want = @max(@as(usize, 1), @min(cpu, max_workers));

    var group: Io.Group = .init;
    var spawned: usize = 0;
    while (spawned < want) : (spawned += 1) {
        group.concurrent(io, worker, .{ctx}) catch |err| switch (err) {
            error.ConcurrencyUnavailable => break,
            else => |e| return e,
        };
    }
    if (spawned == 0) {
        // Io backend cannot spawn threads — drain serially on this task.
        try worker(ctx);
    } else {
        try group.await(io);
    }
}

fn worker(ctx: *Ctx) Io.Cancelable!void {
    const io = ctx.io;
    // Group tasks may only return Cancelable — swallow harness errors as FAIL lines.
    var dir = Io.Dir.cwd().openDir(io, ctx.corpus_dir, .{}) catch |e| {
        std.process.fatal("corpus worker: openDir {s} failed ({t})", .{ ctx.corpus_dir, e });
    };
    defer dir.close(io);

    while (true) {
        const i = ctx.next.fetchAdd(1, .monotonic);
        if (i >= ctx.names.len) return;
        runOne(ctx, dir, ctx.names[i]);
    }
}

fn runOne(ctx: *Ctx, dir: Io.Dir, name: []const u8) void {
    runOneInner(ctx, dir, name) catch |e| {
        ctx.print_mu.lockUncancelable(ctx.io);
        defer ctx.print_mu.unlock(ctx.io);
        std.debug.print("  {s}: FAIL — harness error ({t})\n", .{ name, e });
    };
}

fn runOneInner(ctx: *Ctx, dir: Io.Dir, name: []const u8) !void {
    const io = ctx.io;
    const gpa = ctx.gpa;

    const sas_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ ctx.corpus_dir, name });
    defer gpa.free(sas_path);
    const txt_name = try std.fmt.allocPrint(gpa, "{s}.txt", .{name[0 .. name.len - ".sas".len]});
    defer gpa.free(txt_name);

    const expected = dir.readFileAlloc(io, txt_name, gpa, max_file) catch |e| {
        ctx.print_mu.lockUncancelable(io);
        defer ctx.print_mu.unlock(io);
        std.debug.print("  {s}: FAIL — could not read expected {s} ({t})\n", .{ name, txt_name, e });
        return;
    };
    defer gpa.free(expected);

    const res = std.process.run(gpa, io, .{ .argv = &.{ ctx.bin, sas_path } }) catch |e| {
        ctx.print_mu.lockUncancelable(io);
        defer ctx.print_mu.unlock(io);
        std.debug.print("  {s}: FAIL — could not run interpreter ({t})\n", .{ name, e });
        return;
    };
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    // The rc pin is checked before the diff: a fixture whose stdout matches
    // but whose exit code is wrong must FAIL (that combination is exactly
    // what hid the D-009 inversions — see fixture_rc.zig).
    const src = try dir.readFileAlloc(io, name, gpa, max_file);
    defer gpa.free(src);
    if (try fixture_rc.mismatch(gpa, src, res.term)) |why| {
        defer gpa.free(why);
        ctx.print_mu.lockUncancelable(io);
        defer ctx.print_mu.unlock(io);
        std.debug.print("  {s}: FAIL — {s}\n", .{ name, why });
        return;
    }

    const norm_exp = try normalize(gpa, expected);
    defer gpa.free(norm_exp);
    const norm_got = try normalize(gpa, res.stdout);
    defer gpa.free(norm_got);

    if (std.mem.eql(u8, norm_exp, norm_got)) {
        _ = ctx.pass.fetchAdd(1, .monotonic);
        return;
    }

    ctx.print_mu.lockUncancelable(io);
    defer ctx.print_mu.unlock(io);
    if (firstUnsupported(res.stderr)) |feat| {
        std.debug.print("  {s}: FAIL — first unsupported: {s}\n", .{ name, feat });
    } else {
        const d = firstDiffLine(norm_exp, norm_got);
        std.debug.print("  {s}: FAIL — output differs (expected \"{s}\" | got \"{s}\")\n", .{ name, d.expected, d.got });
    }
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

test "touchesSharedCorpusFs flags includes and zig-cache paths" {
    try std.testing.expect(touchesSharedCorpusFs(
        "libname o \"tests/corpus/includes/dslabel\";\n",
    ));
    try std.testing.expect(touchesSharedCorpusFs(
        "libname o \"tests/corpus/includes\";\n",
    ));
    try std.testing.expect(touchesSharedCorpusFs(
        "proc export outfile=\"tests/corpus/includes/x.csv\";\n",
    ));
    try std.testing.expect(touchesSharedCorpusFs(
        "libname L \".zig-cache\";\n",
    ));
    try std.testing.expect(touchesSharedCorpusFs(
        "file \".zig-cache/out.csv\";\n",
    ));
    try std.testing.expect(!touchesSharedCorpusFs(
        "data a; x=1; run;\nproc print; run;\n",
    ));
}

test {
    // fixture_rc.zig's `test` blocks don't run unless referenced from a test
    // root (modern zig runs only the root file's tests) — pull them in.
    _ = @import("fixture_rc.zig");
}
