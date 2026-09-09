//! Diagnostics — line-tagged messages collected across lex/parse/exec, plus
//! the shared error set every stage returns. Matches the lexer's Error style:
//! a tiny error set for control flow (callers `try`), while the human-readable
//! detail lives here so the CLI can print a SAS-style log at the end.
//!
//! Arena-backed: the arena owns every message string, so callers may `report`
//! with a transient stack buffer and forget about it.

const std = @import("std");

/// What went wrong, at the type level. Stages return these; the accompanying
/// `Diagnostics` holds the readable text. Mirrors the lexer's error set —
/// grow it as stages land, don't invent per-call error types.
pub const Error = error{
    LexError,
    ParseError,
    ExecError,
    OutOfMemory,
};

/// SAS log levels. `err` maps to SAS "ERROR:", `warn` to "WARNING:",
/// `note` to "NOTE:".
pub const Severity = enum {
    note,
    warning,
    err,

    /// The SAS log prefix for this level.
    pub fn tag(self: Severity) []const u8 {
        return switch (self) {
            .note => "NOTE",
            .warning => "WARNING",
            .err => "ERROR",
        };
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    /// 1-based source line; 0 means "no line" (rendered without a location).
    line: usize,
    /// Arena-owned message text.
    message: []const u8,
    /// A RECOVERABLE error: loud in the log and counts toward hasErrors()/
    /// exit code, but does NOT trigger step-skipping syntax-check mode
    /// (BUG-errhalt is about STEP errors). Two species: a macro-language
    /// error confined to the failing macro (real SAS: "the macro will stop
    /// executing" — a macro error must not silently kill independent later
    /// steps; that took the study meter 26/27 → 0/27), and an rc-by-design
    /// condition whose method returns a documented return code the caller
    /// inspects (SEV-rcbydesignerr — see Diagnostics.rcErr).
    recoverable: bool = false,
    /// GH#17 ISS-macrolinemap: this `line` is in POST-EXPANSION coordinates of a
    /// macro-generated token stream, NOT a source line — so `render` marks it
    /// `(expanded L86)` and no reader (or a line-map harness) mistakes it
    /// for a line in a source/macro file. Set from `Diagnostics.expansion_space`.
    expanded: bool = false,
};

/// Collects diagnostics into an arena. One per interpreter run.
pub const Diagnostics = struct {
    arena: std.mem.Allocator,
    list: std.ArrayList(Diagnostic),
    /// GH#17 ISS-macrolinemap: true once the run is executing macro-EXPANDED text,
    /// so every `line` recorded is a post-expansion offset, not a source line. main
    /// sets it when `macro.expand` actually transformed the source (a no-op macro
    /// pass keeps it false → plain syntax errors still report their real source line).
    /// Every diagnostic recorded while set is flagged `expanded` so `render` marks it.
    /// ponytail: run-global flag, not a true source→line map — the honest cheap fix
    /// (mark, don't mislead). Upgrade path: thread an offset→source-line map through
    /// macro.zig so the reported line is the ORIGINAL source line; heavy, do it only
    /// if a study actually needs exact macro line numbers, not just "not a lie".
    expansion_space: bool = false,
    /// F7: `options nonotes;` suppresses log NOTEs; `options notes;` re-enables.
    /// Set by main's OPTIONS branch — `report` drops `.note` diagnostics while set
    /// (warnings/errors always record). Production clinical runs rely on NONOTES.
    suppress_notes: bool = false,

    pub fn init(arena: std.mem.Allocator) Diagnostics {
        return .{ .arena = arena, .list = .empty };
    }

    /// Record a diagnostic; `fmt`/`args` are `std.fmt`-formatted into the arena.
    /// Returns only OutOfMemory — recording a problem is not itself the failure.
    pub fn report(
        self: *Diagnostics,
        severity: Severity,
        line: usize,
        comptime fmt: []const u8,
        args: anytype,
    ) error{OutOfMemory}!void {
        if (severity == .note and self.suppress_notes) return; // F7: OPTIONS NONOTES
        const message = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.list.append(self.arena, .{
            .severity = severity,
            .line = line,
            .message = message,
            .expanded = self.expansion_space,
        });
    }

    /// Record an error and hand back the matching `Error` so callers can
    /// `return diags.fail(error.ParseError, line, "...", .{})` in one line.
    pub fn fail(
        self: *Diagnostics,
        comptime e: Error,
        line: usize,
        comptime fmt: []const u8,
        args: anytype,
    ) Error {
        self.report(.err, line, fmt, args) catch return error.OutOfMemory;
        return e;
    }

    /// Record a macro-scoped ERROR: loud in the log and non-zero exit, but
    /// exempt from syntax-check step-skipping (see Diagnostic.recoverable).
    pub fn macroErr(self: *Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        return self.recoverableErr(line, fmt, args);
    }

    /// Record an rc-by-design ERROR (SEV-rcbydesignerr): a condition whose
    /// method returns a documented return code the caller is expected to
    /// inspect. SAS 9.4 Component Objects: Reference gives every hash method
    /// the same contract — "A return code of zero indicates success; a
    /// nonzero value indicates failure. If you do not supply a return code
    /// variable for the method call and the method fails, then an appropriate
    /// error message is written to the log." (ADD printed p.24, FIND_NEXT
    /// p.53, OUTPUT p.73, REMOVE p.82; offset +11 per the volume's
    /// provenance header.) The log ERROR is SAS's own, so it stays an ERROR
    /// and still fails the exit code — but errhalt-skipping later steps
    /// would make the documented check-the-rc pattern useless (the D-014
    /// shape: legal SAS turned into a step-killer), so it is recoverable.
    pub fn rcErr(self: *Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        return self.recoverableErr(line, fmt, args);
    }

    fn recoverableErr(self: *Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        const message = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.list.append(self.arena, .{
            .severity = .err,
            .line = line,
            .message = message,
            .recoverable = true,
            .expanded = self.expansion_space,
        });
    }

    pub fn warn(self: *Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        return self.report(.warning, line, fmt, args);
    }

    pub fn note(self: *Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        return self.report(.note, line, fmt, args);
    }

    pub fn count(self: *const Diagnostics) usize {
        return self.list.items.len;
    }

    pub fn hasErrors(self: *const Diagnostics) bool {
        for (self.list.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    /// True only for STEP errors — the syntax-check-mode trigger (BUG-errhalt).
    /// Recoverable errors (recoverableErr) still fail the run's exit code via
    /// hasErrors() but do not poison later independent steps.
    pub fn hasStepErrors(self: *const Diagnostics) bool {
        for (self.list.items) |d| {
            if (d.severity == .err and !d.recoverable) return true;
        }
        return false;
    }

    /// Render every diagnostic as a SAS-style log, one per line, into the arena.
    /// `ERROR(L12): message` when located, `ERROR: message` when line == 0.
    pub fn render(self: *const Diagnostics) error{OutOfMemory}![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        for (self.list.items) |d| {
            if (d.line == 0) {
                try buf.print(self.arena, "{s}: {s}\n", .{ d.severity.tag(), d.message });
            } else if (d.expanded) {
                // GH#17: post-expansion offset, not a source line — say so, so the
                // number is never line-mapped into an innocent source/macro file.
                try buf.print(self.arena, "{s}(expanded L{d}): {s}\n", .{ d.severity.tag(), d.line, d.message });
            } else {
                try buf.print(self.arena, "{s}(L{d}): {s}\n", .{ d.severity.tag(), d.line, d.message });
            }
        }
        return buf.items;
    }
};

// ── exit-code contract (D-009 / FLY-exitcodes) ───────────────────────────────
// A calling coding agent routes on the process exit code: 0 = clean; 1 =
// user-program error (their SAS is wrong — parse/exec/data errors → "fix your
// SAS"); 2 = opensas defect or gap (an UNSUPPORTED feature/PROC or an internal
// panic → "file an opensas issue"). A gap OUTRANKS a user error: an opensas
// defect is worth surfacing even when the program also has a bad statement.

/// Process-global "an opensas gap was hit this run" flag. Set by every
/// UNSUPPORTED path — main.failLoud and proc.unsupported — so `exitCode` can tell
/// an opensas defect (2) from the user's own error (1).
var g_gap: bool = false;
pub fn markGap() void {
    g_gap = true;
}
pub fn gapHit() bool {
    return g_gap;
}
/// Clear the per-run gap flag (main calls it before each interpret; tests use it).
pub fn resetGap() void {
    g_gap = false;
}

/// The D-009 exit code from the two run signals: `gap` (any UNSUPPORTED/defect) →
/// 2, else `user_err` (any ERROR-level diagnostic from the user's program) → 1,
/// else 0. Pure so it is unit-tested without spawning a process (D-003).
pub fn exitCode(gap: bool, user_err: bool) u8 {
    if (gap) return 2;
    if (user_err) return 1;
    return 0;
}

test "D-009 exit-code contract: 0 clean / 1 user error / 2 opensas gap" {
    try std.testing.expectEqual(@as(u8, 0), exitCode(false, false));
    try std.testing.expectEqual(@as(u8, 1), exitCode(false, true)); // user's SAS is wrong
    try std.testing.expectEqual(@as(u8, 2), exitCode(true, false)); // opensas gap
    try std.testing.expectEqual(@as(u8, 2), exitCode(true, true)); // gap outranks user error
}

test "D-009: classify via the captured reporter, no spawn (D-003)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = Diagnostics.init(arena.allocator());
    resetGap();

    // clean run → 0
    try std.testing.expectEqual(@as(u8, 0), exitCode(gapHit(), diags.hasErrors()));

    // a user-program parse error, reported through the captured diags → 1
    _ = diags.fail(error.ParseError, 3, "expected ';'", .{}) catch {};
    try std.testing.expectEqual(@as(u8, 1), exitCode(gapHit(), diags.hasErrors()));

    // an opensas UNSUPPORTED gap on top → 2 (outranks the user error)
    markGap();
    try std.testing.expectEqual(@as(u8, 2), exitCode(gapHit(), diags.hasErrors()));
    resetGap();
}

test "collect, query, render" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var diags = Diagnostics.init(a);
    try std.testing.expect(!diags.hasErrors());

    try diags.warn(3, "variable {s} is uninitialized", .{"AGE"});
    try diags.report(.err, 12, "unexpected token '{c}'", .{'@'});

    try std.testing.expectEqual(@as(usize, 2), diags.count());
    try std.testing.expect(diags.hasErrors());

    const out = try diags.render();
    try std.testing.expectEqualStrings(
        "WARNING(L3): variable AGE is uninitialized\n" ++
            "ERROR(L12): unexpected token '@'\n",
        out,
    );
}

test "macroErr fails the run but is not a step error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var diags = Diagnostics.init(arena.allocator());
    try diags.macroErr(0, "Apparent symbolic reference {s} not resolved.", .{"NB"});
    try std.testing.expect(diags.hasErrors()); // non-zero exit (fail loud)
    try std.testing.expect(!diags.hasStepErrors()); // no syntax-check poison

    // SEV-rcbydesignerr: an rc-by-design condition behaves identically.
    try diags.rcErr(0, "hash add: duplicate key (duplicate:'e')", .{});
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(!diags.hasStepErrors());

    try diags.report(.err, 5, "step error", .{});
    try std.testing.expect(diags.hasStepErrors());
}

test "fail records the error and returns it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var diags = Diagnostics.init(a);
    const e = diags.fail(error.ParseError, 0, "missing semicolon", .{});
    try std.testing.expectError(error.ParseError, @as(Error!void, e));
    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqualStrings("ERROR: missing semicolon\n", try diags.render());
}

test "suppress_notes drops NOTEs but keeps warnings/errors (F7 OPTIONS NONOTES)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = Diagnostics.init(arena.allocator());

    diags.suppress_notes = true; // OPTIONS NONOTES
    try diags.note(1, "variable ZZ is uninitialized", .{});
    try diags.warn(2, "kept warning", .{});
    try diags.report(.err, 3, "kept error", .{});
    try std.testing.expectEqual(@as(usize, 2), diags.count()); // note dropped

    diags.suppress_notes = false; // OPTIONS NOTES re-enables
    try diags.note(4, "now recorded", .{});
    try std.testing.expectEqual(@as(usize, 3), diags.count());
}
