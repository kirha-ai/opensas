//! The fixture↔runner contract for the process exit code (D-009), shared by
//! `corpus_runner.zig` and `programs_runner.zig`.
//!
//! A fixture pins the interpreter's exit code with a marker in its header
//! comment, next to the prose that says why:
//!
//! ```
//! /* BUG-foo: ... why this program must be rejected ...
//!    expect-rc: 1 */
//! ```
//!
//! **NOT opt-in any more: no marker means `expect-rc: 0`.** A fixture that exits
//! non-zero must SAY SO, and one that exits non-zero without saying so now
//! fails. Absence of a marker is a claim ("this program runs clean"), not a
//! shrug.
//!
//! It was opt-in until every non-zero fixture carried a marker, because a silent
//! default of 0 would have reddened them all at once. That migration is done:
//! **70 corpus fixtures were pinned first (60 at rc 1, 10 at rc 2), in two
//! commits batched by rc so each carried one reviewable claim**, and only then
//! was the default flipped. The programs suite needed no migration — it had 2
//! non-zero fixtures and both were already pinned.
//!
//! Why flip at all: `qa-tick438-sweep.md` measured the hole. 191 of 1859 corpus
//! fixtures exited non-zero and 70 of them declared nothing, so more than a
//! third of the rc surface was invisible to the suite — in the project whose
//! exit-code contract had just been rebuilt across seven files. That wave moved
//! exactly one unpinned rc (`infile_pad_failsloud`, 1 -> 2, correctly) and
//! nothing noticed. Opt-in coverage is coverage you find out about afterwards.
//!
//! The default is 0 rather than a recorded-observation manifest deliberately.
//! A manifest would have needed no fixture edits, but it stores a MACHINE
//! OBSERVATION with no reasoning attached and a blind regeneration silently
//! re-blesses drift — and at 70 files the edits are cheap enough that the
//! trade is not worth a second source of truth. A marker in the header sits
//! next to the prose that says WHY, which is the thing a future reader needs.
//! See `docs/findings/rc-pin-coverage.md` for the argument in full.
//!
//! Why this exists at all: BUG-nofixturepinsrc / audit-exitcodecontract §6 I1 —
//! neither runner read the rc, so a differential over 1874 fixtures moved one
//! exit code and *no fixture noticed*. That is why six wrong-rc sites survived.
//!
//! **One marker per fixture.** The scan used to take the FIRST occurrence, so
//! prose discussing the marker ("re-pinned from `expect-rc: 1` to 2") silently
//! pinned the prose's number. Neither first nor last is authoritative across
//! every phrasing, so a second occurrence is an error (fail-loud, D-002) —
//! reword the prose (e.g. "expect rc 1") instead of quoting the marker.

const std = @import("std");

pub const marker = "expect-rc:";

/// The exit code a fixture declares, or null when it declares none. Callers get
/// null, not 0, so the "declared nothing" case stays distinguishable here; the
/// default lives in `mismatch`, which is the only place that needs it.
/// Errors (rather than returning null) on a marker followed by something that
/// is not a number — a typo must not silently disable the pin it looks like —
/// and on a SECOND occurrence, which no positional rule can disambiguate.
pub fn expected(src: []const u8) error{ BadMarker, AmbiguousMarker }!?u8 {
    const at = std.mem.indexOf(u8, src, marker) orelse return null;
    if (std.mem.indexOf(u8, src[at + marker.len ..], marker) != null)
        return error.AmbiguousMarker;
    const rest = std.mem.trimStart(u8, src[at + marker.len ..], " \t");
    var end: usize = 0;
    while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
    return std.fmt.parseInt(u8, rest[0..end], 10) catch error.BadMarker;
}

/// Compare a fixture's rc against a finished child. Null when it matches, else
/// the mismatch, named — "failed" alone would recreate the problem one level up.
/// An undeclared fixture is held to 0 (see the module comment), and its message
/// names the marker so the fix is obvious from the failure line alone.
pub fn mismatch(a: std.mem.Allocator, src: []const u8, term: std.process.Child.Term) !?[]const u8 {
    const want = expected(src) catch |err| switch (err) {
        error.AmbiguousMarker => return try std.fmt.allocPrint(a, "multiple `{s}` markers (keep exactly one; reword prose that quotes it)", .{marker}),
        error.BadMarker => return try std.fmt.allocPrint(a, "malformed `{s}` marker (want e.g. `{s} 1`)", .{ marker, marker }),
    };
    const w = want orelse 0; // no marker == "this program runs clean"
    return switch (term) {
        .exited => |got| if (got == w) null else if (want == null)
            try std.fmt.allocPrint(a, "exit code: {d}, but the fixture declares none — add `{s} {d}` to its header comment, next to the prose that says why", .{ got, marker, got })
        else
            try std.fmt.allocPrint(a, "exit code: expected {d}, got {d}", .{ w, got }),
        else => try std.fmt.allocPrint(a, "exit code: expected {d}, child did not exit normally ({s})", .{ w, @tagName(term) }),
    };
}

test "expected: opt-in, parses, and is loud about a typo" {
    try std.testing.expectEqual(@as(?u8, null), try expected("data a; x=1; run;\n"));
    try std.testing.expectEqual(@as(?u8, 0), try expected("/* clean\n   expect-rc: 0 */\n"));
    try std.testing.expectEqual(@as(?u8, 1), try expected("/* expect-rc: 1 */\n"));
    try std.testing.expectEqual(@as(?u8, 3), try expected("/* D-009a: abort return 3\n   expect-rc: 3 */\n"));
    try std.testing.expectError(error.BadMarker, expected("/* expect-rc: one */\n"));
    try std.testing.expectError(error.BadMarker, expected("/* expect-rc: */\n"));
}

test "expected: a second occurrence is ambiguous — loud, never a positional guess" {
    // the hazard that motivated it: prose quoting the marker ahead of the pin
    try std.testing.expectError(error.AmbiguousMarker, expected("/* re-pinned from `expect-rc: 1` to 2\n   expect-rc: 2 */\n"));
    // and prose AFTER the pin (a positional "last wins" rule would bite here)
    try std.testing.expectError(error.AmbiguousMarker, expected("/* expect-rc: 2 — see the expect-rc: convention */\n"));
    // one marker, even late in the file, still parses
    try std.testing.expectEqual(@as(?u8, 2), try expected("data a; run;\n/* expect-rc: 2 */\n"));
}

test "mismatch: an undeclared fixture is held to 0, and the message says how to fix it" {
    const a = std.testing.allocator;
    // the flip: no marker used to mean "unchecked", now it means "must be 0"
    try std.testing.expect((try mismatch(a, "no marker", .{ .exited = 0 })) == null);
    const und = (try mismatch(a, "no marker", .{ .exited = 7 })).?;
    defer a.free(und);
    try std.testing.expectEqualStrings(
        "exit code: 7, but the fixture declares none — add `expect-rc: 7` to its header comment, next to the prose that says why",
        und,
    );
    // a DECLARED mismatch keeps the terser two-number message
    const dec = (try mismatch(a, "/* expect-rc: 1 */", .{ .exited = 2 })).?;
    defer a.free(dec);
    try std.testing.expectEqualStrings("exit code: expected 1, got 2", dec);
    // declaring 0 explicitly is still legal and still passes
    try std.testing.expect((try mismatch(a, "/* expect-rc: 0 */", .{ .exited = 0 })) == null);
    // AmbiguousMarker still wins over the default — it is a marker problem, not an rc one
    const amb0 = (try mismatch(a, "/* expect-rc: 0 */ /* expect-rc: 0 */", .{ .exited = 0 })).?;
    defer a.free(amb0);
    try std.testing.expectEqualStrings("multiple `expect-rc:` markers (keep exactly one; reword prose that quotes it)", amb0);
}

test "mismatch: names both numbers, and only fires when declared" {
    const a = std.testing.allocator;
    try std.testing.expect((try mismatch(a, "/* expect-rc: 1 */", .{ .exited = 1 })) == null);
    const m = (try mismatch(a, "/* expect-rc: 1 */", .{ .exited = 2 })).?;
    defer a.free(m);
    try std.testing.expectEqualStrings("exit code: expected 1, got 2", m);
    const amb = (try mismatch(a, "/* expect-rc: 1 */ /* expect-rc: 2 */", .{ .exited = 1 })).?;
    defer a.free(amb);
    try std.testing.expectEqualStrings("multiple `expect-rc:` markers (keep exactly one; reword prose that quotes it)", amb);
}
